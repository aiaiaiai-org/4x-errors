# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "json"

RSpec.describe "families and causality", :database do
  include Rack::Test::Methods

  let(:database) { TestDatabase.connection }
  let(:store) { Aiaiaiai::Errors::Collector::Store.new(database) }
  let(:tokens) do
    Aiaiaiai::Errors::Collector::TokenStore.new(
      "aiaiaiai-org/artificial-intelligence" => [Aiaiaiai::Errors::Collector::TokenStore.digest("ai.token")],
      "nilx-one/ai" => [Aiaiaiai::Errors::Collector::TokenStore.digest("nilx.token")]
    )
  end
  let(:app) { Aiaiaiai::Errors::Collector.rack_app(db: database, tokens: tokens, logger: nil) }

  def ingest(document, bearer:)
    header "authorization", "Bearer #{bearer}"
    post "/v1/events", JSON.generate(document), "CONTENT_TYPE" => "application/json"
    last_response
  end

  def request(project:, events: [], relations: nil)
    document = {"protocol_version" => "errors.v1", "project" => project, "events" => events}
    document["relations"] = relations if relations
    document
  end

  def event(error_id, **overrides)
    {"error_id" => error_id, "environment" => "production"}.merge(overrides)
  end

  def relation(source, type, target, confidence: 0.9, evidence: %w[dependency_failure])
    {"source" => source, "type" => type, "target" => target, "confidence" => confidence, "evidence" => evidence}
  end

  describe "one failure kind, many occurrences" do
    it "keeps every occurrence and one registry entry" do
      3.times { |index| ingest(request(project: "nilx-one/ai", events: [event("ai.model.load.failed", "message" => "attempt #{index}")]), bearer: "nilx.token") }

      expect(database[:error_events].count).to eq(3)
      expect(database[:error_definitions].count).to eq(1)
    end
  end

  describe "cross-project families" do
    it "lets two different projects put different error ids in one family" do
      ingest(request(project: "aiaiaiai-org/artificial-intelligence",
        events: [event("ai.model.load.failed", "family_id" => "ai.model.availability")]), bearer: "ai.token")
      ingest(request(project: "nilx-one/ai",
        events: [event("ai.inference.backend.unavailable", "family_id" => "ai.model.availability")]), bearer: "nilx.token")

      expect(store.family_members("ai.model.availability"))
        .to eq(["ai.inference.backend.unavailable", "ai.model.load.failed"])
      expect(database[:error_events].select_map(:project).uniq.length).to eq(2)
    end

    it "asserts kinship without asserting causality" do
      ingest(request(project: "nilx-one/ai",
        events: [event("ai.model.load.failed", "family_id" => "ai.model.availability"),
          event("ai.inference.backend.unavailable", "family_id" => "ai.model.availability")]), bearer: "nilx.token")

      expect(store.family_members("ai.model.availability").length).to eq(2)
      expect(database[:error_relations].count).to be_zero
      expect(store.effects_of("ai.model.load.failed")).to be_empty
    end
  end

  describe "explicit causal relations" do
    before do
      ingest(request(project: "nilx-one/ai",
        events: [event("ai.model.load.failed"), event("ai.avatar.response.unavailable")],
        relations: [relation({"error_id" => "ai.model.load.failed"}, "root_cause_of",
          {"error_id" => "ai.avatar.response.unavailable"})]), bearer: "nilx.token")
    end

    it "stores the relation with its confidence and evidence" do
      row = database[:error_relations].first

      expect(row[:relation_type]).to eq("root_cause_of")
      expect(row[:confidence]).to eq(0.9)
      expect(row[:evidence]).to eq(["dependency_failure"])
    end

    it "is queryable from both directions" do
      expect(store.effects_of("ai.model.load.failed")).to eq(["ai.avatar.response.unavailable"])
      expect(store.causes_of("ai.avatar.response.unavailable")).to eq(["ai.model.load.failed"])
      expect(store.causes_of("ai.model.load.failed")).to be_empty
    end

    it "reads derivative_of as the same edge stated from the other side" do
      ingest(request(project: "nilx-one/ai", events: [],
        relations: [relation({"error_id" => "ai.session.refresh.failed"}, "derivative_of",
          {"error_id" => "identity.provider.unreachable"})]), bearer: "nilx.token")

      expect(store.effects_of("identity.provider.unreachable")).to eq(["ai.session.refresh.failed"])
      expect(store.causes_of("ai.session.refresh.failed")).to eq(["identity.provider.unreachable"])
    end

    it "is idempotent" do
      ingest(request(project: "nilx-one/ai", events: [],
        relations: [relation({"error_id" => "ai.model.load.failed"}, "root_cause_of",
          {"error_id" => "ai.avatar.response.unavailable"})]), bearer: "nilx.token")

      expect(database[:error_relations].count).to eq(1)
      expect(JSON.parse(last_response.body).dig("relations", "already_known")).to eq(1)
    end
  end

  describe "correlation" do
    it "records a non-causal relation without contributing a causal edge" do
      ingest(request(project: "nilx-one/ai", events: [],
        relations: [relation({"error_id" => "map.renderer.initialization.failed"}, "correlated_with",
          {"error_id" => "map.tiles.fetch.failed"}, confidence: 0.4,
          evidence: %w[heuristic_similarity temporal_sequence])]), bearer: "nilx.token")

      expect(last_response.status).to eq(202)
      expect(store.effects_of("map.renderer.initialization.failed")).to be_empty
      expect(store.causes_of("map.tiles.fetch.failed")).to be_empty
    end
  end

  describe "causal cycles" do
    it "refuses a relation that would close a cycle, and stores nothing from that request" do
      ingest(request(project: "nilx-one/ai", events: [],
        relations: [relation({"error_id" => "a.one"}, "root_cause_of", {"error_id" => "b.two"}),
          relation({"error_id" => "b.two"}, "root_cause_of", {"error_id" => "c.three"})]), bearer: "nilx.token")

      response = ingest(request(project: "nilx-one/ai",
        events: [event("c.three")],
        relations: [relation({"error_id" => "c.three"}, "root_cause_of", {"error_id" => "a.one"})]), bearer: "nilx.token")

      expect(response.status).to eq(409)
      expect(JSON.parse(response.body)["error"]).to eq("causal_cycle")
      expect(database[:error_relations].count).to eq(2)
      expect(database[:error_events].count).to be_zero
    end

    it "refuses a cycle stated in the opposite direction just as firmly" do
      ingest(request(project: "nilx-one/ai", events: [],
        relations: [relation({"error_id" => "a.one"}, "root_cause_of", {"error_id" => "b.two"})]), bearer: "nilx.token")

      response = ingest(request(project: "nilx-one/ai", events: [],
        relations: [relation({"error_id" => "b.two"}, "contributes_to", {"error_id" => "a.one"})]), bearer: "nilx.token")

      expect(response.status).to eq(409)
    end

    it "allows a diamond: two paths to one effect are not a cycle" do
      response = ingest(request(project: "nilx-one/ai", events: [],
        relations: [relation({"error_id" => "root.cause"}, "root_cause_of", {"error_id" => "left.branch"}),
          relation({"error_id" => "root.cause"}, "root_cause_of", {"error_id" => "right.branch"}),
          relation({"error_id" => "left.branch"}, "root_cause_of", {"error_id" => "joined.effect"}),
          relation({"error_id" => "right.branch"}, "root_cause_of", {"error_id" => "joined.effect"})]), bearer: "nilx.token")

      expect(response.status).to eq(202)
      expect(store.causes_of("joined.effect")).to eq(["left.branch", "right.branch"])
    end
  end

  describe "relations between concrete occurrences" do
    it "relates two events reported in one request" do
      response = ingest(request(project: "nilx-one/ai",
        events: [event("identity.provider.unreachable", "local_ref" => "cause"),
          event("ai.session.refresh.failed", "local_ref" => "effect")],
        relations: [relation({"local_ref" => "cause"}, "root_cause_of", {"local_ref" => "effect"},
          evidence: %w[shared_trace_id])]), bearer: "nilx.token")

      expect(response.status).to eq(202)
      row = database[:event_relations].first
      ids = database[:error_events].order(:error_id).select_map(:id)
      expect([row[:source_event_id], row[:target_event_id]]).to match_array(ids)
    end

    it "does not persist the batch local alias" do
      ingest(request(project: "nilx-one/ai", events: [event("a.one", "local_ref" => "cause")]), bearer: "nilx.token")

      expect(database[:error_events].columns).not_to include(:local_ref)
    end
  end

  describe "reclassification" do
    before do
      ingest(request(project: "nilx-one/ai",
        events: [event("ai.model.load.failed", "family_id" => "ai.model.availability")]), bearer: "nilx.token")
    end

    it "moves an error to another family without touching the raw occurrence" do
      before_event = database[:error_events].first

      store.reclassify(error_id: "ai.model.load.failed",
        from_family_id: "ai.model.availability",
        to_family_id: "ai.inference.runtime",
        reason: "the loader failure is a runtime concern")

      expect(store.active_families("ai.model.load.failed")).to eq(["ai.inference.runtime"])
      expect(database[:error_events].first).to eq(before_event)
      expect(database[:error_events].first[:reported_family_id]).to eq("ai.model.availability")
    end

    it "keeps the superseded membership as history" do
      store.reclassify(error_id: "ai.model.load.failed", from_family_id: "ai.model.availability",
        to_family_id: "ai.inference.runtime", reason: "moved")

      superseded = database[:error_family_memberships].where(family_id: "ai.model.availability").first
      expect(superseded[:superseded_at]).not_to be_nil
      expect(superseded[:superseded_reason]).to eq("moved")
    end

    it "is not undone by reporters that keep claiming the old family" do
      store.reclassify(error_id: "ai.model.load.failed", from_family_id: "ai.model.availability",
        to_family_id: "ai.inference.runtime", reason: "moved")

      ingest(request(project: "nilx-one/ai",
        events: [event("ai.model.load.failed", "family_id" => "ai.model.availability")]), bearer: "nilx.token")

      expect(store.active_families("ai.model.load.failed")).to eq(["ai.inference.runtime"])
    end
  end

  describe "raw occurrences" do
    it "cannot be modified, by anyone" do
      ingest(request(project: "nilx-one/ai", events: [event("a.one")]), bearer: "nilx.token")

      expect { database[:error_events].update(message: "rewritten") }
        .to raise_error(Sequel::DatabaseError, /immutable/)
    end
  end

  describe "unknown causality" do
    it "is a valid state, not a missing one" do
      ingest(request(project: "nilx-one/ai", events: [event("ai.inference.runtime.unknown")]), bearer: "nilx.token")

      expect(last_response.status).to eq(202)
      expect(store.causes_of("ai.inference.runtime.unknown")).to be_empty
      expect(database[:error_events].count).to eq(1)
    end
  end
end
