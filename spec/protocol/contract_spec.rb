# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "json"

# The conformance suite. Every fixture in protocol/fixtures is a statement
# about errors.v1 that any implementation, in any language, must reproduce.
RSpec.describe "errors.v1 conformance" do
  fixtures = Dir[File.expand_path("../../protocol/fixtures/*/*.json", __dir__)].sort
  validator = Aiaiaiai::Errors::Protocol.validator

  it "ships fixtures for both outcomes" do
    expect(fixtures.count { |path| path.include?("/valid/") }).to be >= 8
    expect(fixtures.count { |path| path.include?("/invalid/") }).to be >= 15
  end

  fixtures.each do |path|
    fixture = JSON.parse(File.read(path, encoding: "UTF-8"))
    name = path.split("/fixtures/").last

    it "#{fixture["valid"] ? "accepts" : "rejects"} #{name}: #{fixture["description"]}" do
      violations = validator.validate(fixture["payload"])

      if fixture["valid"]
        expect(violations.map(&:to_s)).to be_empty
      else
        expect(violations).not_to be_empty
        expect(violations.map(&:pointer)).to include(*Array(fixture["violations"]))
      end
    end
  end

  describe "the published schema" do
    it "is the normative artefact and is valid JSON Schema" do
      expect(Aiaiaiai::Errors::Protocol.schema["$id"]).to eq("https://aiaiaiai.org/schemas/errors.v1.schema.json")
      expect { JSONSchemer.schema(Aiaiaiai::Errors::Protocol.schema) }.not_to raise_error
    end

    it "names the same relation and evidence vocabulary as the Ruby implementation" do
      relation_types = Aiaiaiai::Errors::Protocol.schema.dig("$defs", "relation", "properties", "type", "enum")
      evidence = Aiaiaiai::Errors::Protocol.schema.dig("$defs", "relation", "properties", "evidence", "items", "enum")

      expect(relation_types).to match_array(Aiaiaiai::Errors::Protocol::Vocabulary::RELATION_TYPES)
      expect(evidence).to match_array(Aiaiaiai::Errors::Protocol::Vocabulary::EVIDENCE)
    end

    it "carries no reference to any consuming project" do
      raw = File.read(Aiaiaiai::Errors::Protocol.schema_path, encoding: "UTF-8")

      expect(raw).not_to match(/nilx|0xda|aiaiaiai-org|artificial-intelligence/i)
      expect(raw).not_to match(/ruby|rails|roda|sequel/i)
    end
  end

  describe "similarity and causality" do
    it "keeps them distinct: similarity is admissible evidence, never sufficient for a cause" do
      causal = {
        "protocol_version" => "errors.v1", "project" => "nilx-one/web", "events" => [],
        "relations" => [{"source" => {"error_id" => "a.b"}, "type" => "root_cause_of",
                         "target" => {"error_id" => "c.d"}, "confidence" => 0.9,
                         "evidence" => ["heuristic_similarity"]}]
      }
      correlated = causal.merge("relations" => [causal["relations"].first.merge("type" => "correlated_with")])

      expect(validator.validate(causal)).not_to be_empty
      expect(validator.validate(correlated)).to be_empty
    end
  end
end
