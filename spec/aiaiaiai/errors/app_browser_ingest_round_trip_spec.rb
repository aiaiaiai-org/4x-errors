# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require 'json'
require 'rack/test'
require 'sequel'
require 'sequel/extensions/migration'
require_relative '../../../app'

RSpec.describe Aiaiaiai::Errors::App do
  include Rack::Test::Methods

  let(:database) do
    Sequel.connect(ENV.fetch('TEST_DATABASE_URL')).tap do |connection|
      connection.extension :pg_json
    end
  end
  let(:event) do
    fixture = File.expand_path('../../../protocol/errors.v1/fixtures/error-event.valid.json',
                               __dir__)
    JSON.parse(File.read(fixture)).merge(
      'event_id' => 'd9efad3d-aad9-44d5-8126-b0b39f000001',
      'project' => '4x-errors/smoke'
    )
  end

  def app
    described_class.app
  end

  before do
    Sequel::Migrator.run(database, File.expand_path('../../../db/migrations', __dir__))
    database[:error_events].where(event_id: event.fetch('event_id')).delete
    described_class.event_store = Aiaiaiai::Errors::EventStore.new(database)
    described_class.browser_policy = Aiaiaiai::Errors::BrowserIngestPolicy.new(
      '4x-errors/smoke' => ['https://smoke.example']
    )
    described_class.browser_rate_limiter = Aiaiaiai::Errors::BrowserRateLimiter.new
  end

  after do
    if database.table_exists?(:error_events)
      database[:error_events].where(event_id: event.fetch('event_id')).delete
    end
    described_class.event_store = nil
    described_class.browser_policy = nil
    described_class.browser_rate_limiter = nil
    database.disconnect
  end

  it 'persists a zero-secret browser event to PostgreSQL and returns its identifier' do
    post_event(event, origin: 'https://smoke.example')

    expect(last_response.status).to eq(201)
    expect(JSON.parse(last_response.body)).to eq('event_id' => event.fetch('event_id'))
    expect(persisted_event).to include(project: '4x-errors/smoke', error_id: 'ai.model.load.failed',
                                       received_at: be_a(Time))
  end

  it 'rejects a disallowed origin without writing a row' do
    post_event(event, origin: 'https://blocked.example')

    expect(last_response.status).to eq(403)
    expect(database[:error_events].where(event_id: event.fetch('event_id')).count).to eq(0)
  end

  it 'rejects a malformed event without writing a row' do
    post_event(event.merge('error_id' => 'invalid identifier'), origin: 'https://smoke.example')

    expect(last_response.status).to eq(422)
    expect(database[:error_events].where(event_id: event.fetch('event_id')).count).to eq(0)
  end

  def persisted_event
    database[:error_events].where(event_id: event.fetch('event_id')).first
  end

  def post_event(payload, origin:)
    post '/v1/browser/events', JSON.generate(payload),
         'CONTENT_TYPE' => 'application/json', 'HTTP_ORIGIN' => origin
  end
end
