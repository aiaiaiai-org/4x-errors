# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'

RSpec.describe 'the ingest endpoint', :database do
  include Rack::Test::Methods

  let(:database) { TestDatabase.connection }
  let(:token) { 'nilx-one-web.token' }
  let(:other_token) { 'market.token' }
  let(:tokens) do
    Aiaiaiai::Errors::Collector::TokenStore.new(
      'nilx-one/web' => [Aiaiaiai::Errors::Collector::TokenStore.digest(token)],
      '0xda-market/api' => [Aiaiaiai::Errors::Collector::TokenStore.digest(other_token)]
    )
  end
  let(:app) { Aiaiaiai::Errors::Collector.rack_app(db: database, tokens: tokens, logger: nil) }

  def payload(events: [event], relations: nil, project: 'nilx-one/web')
    document = { 'protocol_version' => 'errors.v1', 'project' => project, 'events' => events }
    document['relations'] = relations if relations
    document
  end

  def event(**overrides)
    { 'error_id' => 'ai.model.load.failed', 'environment' => 'production' }.merge(overrides)
  end

  def ingest(document, bearer: token, body: nil)
    header 'authorization', bearer && "Bearer #{bearer}"
    post '/v1/events', body || JSON.generate(document), 'CONTENT_TYPE' => 'application/json'
    last_response
  end

  def body
    JSON.parse(last_response.body)
  end

  describe 'the response contract' do
    it 'accepts a valid event with 202 and answers with its event id' do
      response = ingest(payload)

      expect(response.status).to eq(202)
      expect(body['accepted']).to eq(1)
      expect(body.dig('events', 0, 'event_id')).to match(/\A[0-9a-f-]{36}\z/)
      expect(body.dig('events', 0, 'duplicate')).to be(false)
    end

    it 'rejects a malformed payload with 400 and says where it is wrong' do
      response = ingest(payload(events: [event('error_id' => 'Not An Error Id')]))

      expect(response.status).to eq(400)
      expect(body['error']).to eq('invalid_payload')
      expect(body['violations'].map do |violation|
        violation['pointer']
      end).to include('/events/0/error_id')
    end

    it 'rejects a body that is not JSON with 400' do
      expect(ingest(nil, body: '{not json').status).to eq(400)
    end

    it 'rejects a missing or unknown token with 401' do
      expect(ingest(payload, bearer: nil).status).to eq(401)
      expect(ingest(payload, bearer: 'not-a-real-token').status).to eq(401)
    end

    it 'rejects a token that belongs to another project with 403' do
      response = ingest(payload, bearer: other_token)

      expect(response.status).to eq(403)
      expect(body['error']).to eq('project_mismatch')
      expect(database[:error_events].count).to be_zero
    end

    it 'refuses a body above the protocol limit before parsing it' do
      oversized = 'x' * (Aiaiaiai::Errors::Protocol::Limits::BODY_BYTES + 1)

      expect(ingest(nil, body: oversized).status).to eq(413)
    end

    it 'answers unknown routes as JSON' do
      get '/nope'

      expect(last_response.status).to eq(404)
      expect(JSON.parse(last_response.body)).to eq({ 'error' => 'not_found' })
    end
  end

  describe 'idempotency' do
    it 'treats a repeated occurrence key as the occurrence already stored' do
      first = ingest(payload(events: [event('occurrence_key' => 'deploy-1:job-9')]))
      first_id = JSON.parse(first.body).dig('events', 0, 'event_id')

      second = ingest(payload(events: [event('occurrence_key' => 'deploy-1:job-9',
                                             'message' => 'retry')]))

      expect(second.status).to eq(202)
      expect(body.dig('events', 0, 'event_id')).to eq(first_id)
      expect(body.dig('events', 0, 'duplicate')).to be(true)
      expect(database[:error_events].count).to eq(1)
    end

    it 'scopes occurrence keys to a project' do
      ingest(payload(events: [event('occurrence_key' => 'shared')]))
      ingest(payload(events: [event('occurrence_key' => 'shared')], project: '0xda-market/api'),
             bearer: other_token)

      expect(database[:error_events].count).to eq(2)
    end
  end

  describe 'what the collector decides, not the reporter' do
    it 'generates received_at itself' do
      ingest(payload(events: [event('observed_at' => '2020-01-01T00:00:00Z')]))
      row = database[:error_events].first

      expect(row[:observed_at]).to eq(Time.utc(2020, 1, 1))
      expect(row[:received_at]).to be_within(60).of(Time.now.utc)
    end

    it 'has no way to accept a received_at from a reporter' do
      response = ingest(payload(events: [event('received_at' => '2020-01-01T00:00:00Z')]))

      expect(response.status).to eq(400)
    end

    it 'falls back to the time of receipt when the reporter did not observe one' do
      ingest(payload)
      row = database[:error_events].first

      expect(row[:observed_at]).to eq(row[:received_at])
    end

    it 'assigns the event id' do
      ingest(payload)

      expect(database[:error_events].first[:id]).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'derives a fingerprint when the reporter did not supply one' do
      ingest(payload(events: [event('message' => 'model 12 missing')]))

      expect(database[:error_events].first[:fingerprint]).to start_with('sha256:')
    end

    it 'defaults the severity' do
      ingest(payload)

      expect(database[:error_events].first[:severity]).to eq('error')
    end
  end

  describe 'scrubbing' do
    it 'removes secrets before anything is stored' do
      ingest(payload(events: [event(
        'message' => 'could not reach postgres://collector:s3cret@db.example.com/errors',
        'context' => { 'api_key' => 'abcd1234', 'attempt' => 2 }
      )]))
      row = database[:error_events].first

      expect(row[:message]).not_to include('s3cret')
      expect(row[:context].to_h).to eq({ 'api_key' => '[redacted]', 'attempt' => 2 })
    end
  end

  describe 'the registry' do
    it 'records every error id it has seen, marked as not yet curated' do
      ingest(payload)
      definition = database[:error_definitions].first

      expect(definition[:error_id]).to eq('ai.model.load.failed')
      expect(definition[:auto_registered]).to be(true)
      expect(definition[:first_seen_at]).not_to be_nil
    end

    it 'moves last_seen_at forward without inventing a second entry' do
      ingest(payload)
      first_seen = database[:error_definitions].first[:first_seen_at]
      ingest(payload)

      expect(database[:error_definitions].count).to eq(1)
      expect(database[:error_definitions].first[:first_seen_at]).to eq(first_seen)
    end

    it 'records the family the reporter claimed, as a revisable membership' do
      ingest(payload(events: [event('family_id' => 'ai.model.availability')]))

      expect(database[:error_families].select_map(:family_id)).to eq(['ai.model.availability'])
      membership = database[:error_family_memberships].first
      expect(membership[:source]).to eq('reported')
      expect(membership[:evidence]).to eq(['explicit_reporter_relation'])
      expect(membership[:superseded_at]).to be_nil
    end

    it 'keeps the reported family on the raw event as reported' do
      ingest(payload(events: [event('family_id' => 'ai.model.availability')]))

      expect(database[:error_events].first[:reported_family_id]).to eq('ai.model.availability')
    end
  end

  describe 'health' do
    it 'reports the database dependency' do
      get '/health'

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body))
        .to eq({ 'status' => 'ok', 'database' => 'ok', 'protocol_version' => 'errors.v1' })
    end

    it 'answers 503 when the database is not reachable' do
      allow(Aiaiaiai::Errors::Collector::Database).to receive(:reachable?).and_return(false)
      get '/health'

      expect(last_response.status).to eq(503)
      expect(JSON.parse(last_response.body)['database']).to eq('unreachable')
    end
  end
end
