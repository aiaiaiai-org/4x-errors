# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'digest'
require 'json'
require 'rack/test'
require 'sequel'
require 'sequel/extensions/migration'
require_relative '../../../app'

RSpec.describe Aiaiaiai::Errors::App do
  include Rack::Test::Methods

  let(:database) do
    Sequel.connect(ENV.fetch('TEST_DATABASE_URL')).tap { |db| db.extension :pg_json }
  end
  let(:fixture_path) do
    File.expand_path('../../../protocol/errors.v1/fixtures/error-event.valid.json', __dir__)
  end
  let(:event) { JSON.parse(File.read(fixture_path)) }
  let(:token) { 'integration-test-token' }
  let(:digest) { Digest::SHA256.hexdigest(token) }

  before do
    Sequel::Migrator.run(database, File.expand_path('../../../db/migrations', __dir__))
    database[:error_events].delete
    described_class.event_store = Aiaiaiai::Errors::EventStore.new(database)
    described_class.authenticator = Aiaiaiai::Errors::IngestAuthenticator.new(
      'nilx-one/web' => digest
    )
  end

  after do
    described_class.event_store = nil
    described_class.authenticator = nil
    database[:error_events].delete if database.table_exists?(:error_events)
    database.disconnect
  end

  def app
    described_class.app
  end

  it 'authenticates, validates and persists the canonical event' do
    post_trusted_event

    expect(last_response.status).to eq(201)
    expect(persisted_event).to include(project: 'nilx-one/web', error_id: 'ai.model.load.failed')
    expect(persisted_event.fetch(:received_at)).not_to be_nil
  end

  def post_trusted_event
    post '/v1/events', JSON.generate(event), request_headers
  end

  def persisted_event
    database[:error_events].where(event_id: event.fetch('event_id')).first
  end

  def request_headers
    {
      'CONTENT_TYPE' => 'application/json',
      'HTTP_AUTHORIZATION' => "Bearer #{token}"
    }
  end
end
