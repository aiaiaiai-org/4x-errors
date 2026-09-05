# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'sequel'
require 'sequel/extensions/migration'

RSpec.describe Sequel::Migrator do
  let(:database) do
    Sequel.connect(ENV.fetch('TEST_DATABASE_URL')).tap { |db| db.extension :pg_json }
  end
  let(:event_id) { '00000000-0000-4000-8000-000000000001' }
  let(:event) do
    {
      event_id: event_id,
      protocol_version: 'errors.v1',
      error_id: 'ai.model.load.failed',
      project: 'nilx-one/web',
      source: 'browser',
      severity: 'error',
      message: 'Model failed to load',
      full_text: 'Model failed to load from local runtime',
      observed_at: Time.utc(2026, 9, 5, 9, 0, 0),
      context: Sequel.pg_jsonb({ 'runtime' => 'webllm' }),
      tags: Sequel.pg_jsonb(%w[ai model]),
      family_id: 'family.ai.model.availability',
      caused_by_event_id: nil,
      correlation_id: 'load-session-1'
    }
  end
  let(:expected_columns) do
    %i[event_id protocol_version error_id project source severity message full_text observed_at context
       tags family_id caused_by_event_id correlation_id received_at]
  end

  before do
    described_class.run(database, File.expand_path('../../db/migrations', __dir__))
  end

  after do
    database.disconnect
  end

  it 'creates the error_events persistence shape' do
    columns = database.schema(:error_events).to_h
    expect(columns.keys).to include(*expected_columns)
    expect(columns.dig(:event_id, :db_type)).to eq('uuid')
    expect(columns.dig(:received_at, :allow_null)).to be(false)
  end

  it 'round-trips an errors.v1-shaped event' do
    database[:error_events].insert(event)
    row = database[:error_events].where(event_id: event_id).first
    expect(row.fetch(:error_id)).to eq('ai.model.load.failed')
    expect(row.fetch(:context)).to eq('runtime' => 'webllm')
    expect(row.fetch(:received_at)).not_to be_nil
  end

  it 'enables row-level security without browser-facing policies' do
    expect(row_level_security_enabled?).to be(true)
    expect(error_event_policy_count).to eq(0)
  end

  def row_level_security_enabled?
    database.fetch(<<~SQL).get(:relrowsecurity)
      SELECT relrowsecurity FROM pg_class WHERE oid = 'error_events'::regclass
    SQL
  end

  def error_event_policy_count
    database.fetch(<<~SQL).get(:count)
      SELECT COUNT(*) AS count
      FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'error_events'
    SQL
  end
end
