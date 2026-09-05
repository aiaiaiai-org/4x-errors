# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "stringio"

# The production validation is code, so it is tested like code -- here against
# the integration database, so that the run against the real one is not its
# first execution.
RSpec.describe Aiaiaiai::Errors::Collector::ProductionSmoke, :database do
  subject(:smoke) { described_class.new(db: database, run_id: "spec-run", out: output) }

  let(:database) { TestDatabase.connection }
  let(:output) { StringIO.new }

  it "passes against a migrated database" do
    expect(smoke.call).to be(true)
    expect(smoke.checks.map(&:name)).to eq(%w[
      database_connectivity migrations_are_current health_database_dependency
      ingest_test_event read_back_test_event idempotency_test
      cross_project_token_rejection verify_received_at_is_server_generated
    ])
    expect(smoke.checks.select { |check| !check.ok }).to be_empty
  end

  it "leaves nothing behind" do
    smoke.call

    expect(database[:error_events].count).to be_zero
    expect(database[:error_definitions].where(error_id: described_class::SMOKE_ERROR_ID).count).to be_zero
    expect(database[:error_families].where(family_id: described_class::SMOKE_FAMILY_ID).count).to be_zero
  end

  it "never prints the database credentials" do
    smoke.call

    expect(output.string).not_to include(TestDatabase.url)
    expect(output.string).to include("nothing was deployed")
  end

  it "does not touch records that are not its own" do
    database[:error_definitions].insert(error_id: "someone.elses.error", auto_registered: false,
      created_at: Time.now.utc, updated_at: Time.now.utc)

    smoke.call

    expect(database[:error_definitions].where(error_id: "someone.elses.error").count).to eq(1)
  end

  it "fails loudly when the schema is behind" do
    allow(Aiaiaiai::Errors::Collector::Database).to receive(:migrations_current?).and_return(false)

    expect(smoke.call).to be(false)
    expect(smoke.checks.find { |check| check.name == "migrations_are_current" }.ok).to be(false)
  end
end
