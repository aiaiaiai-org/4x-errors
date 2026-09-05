# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'
require 'rack/test'
require 'rspec'
require_relative '../../../app'

RSpec.describe Aiaiaiai::Errors::App do
  include Rack::Test::Methods

  let(:fixture_path) do
    File.expand_path('../../../protocol/errors.v1/fixtures/error-event.valid.json', __dir__)
  end
  let(:event) { JSON.parse(File.read(fixture_path)) }
  let(:event_store) { instance_double(Aiaiaiai::Errors::EventStore) }
  let(:authenticator) { instance_double(Aiaiaiai::Errors::IngestAuthenticator) }
  let(:headers) do
    {
      'CONTENT_TYPE' => 'application/json',
      'HTTP_AUTHORIZATION' => 'Bearer trusted-token'
    }
  end

  before do
    allow(event_store).to receive(:insert)
    allow(authenticator).to receive(:authenticated?).and_return(true)
    described_class.event_store = event_store
    described_class.authenticator = authenticator
  end

  after do
    described_class.event_store = nil
    described_class.authenticator = nil
  end

  def app
    described_class.app
  end

  it 'exposes a health endpoint' do
    get '/health'

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq('status' => 'ok')
  end

  it 'identifies the service at the root' do
    get '/'

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to include('service' => '4x-errors', 'status' => 'ok')
  end

  it 'persists an authenticated valid errors.v1 event' do
    allow(event_store).to receive(:insert).with(event).and_return(event.fetch('event_id'))

    post '/v1/events', JSON.generate(event), headers

    expect(last_response.status).to eq(201)
    expect(JSON.parse(last_response.body)).to eq('event_id' => event.fetch('event_id'))
  end

  it 'binds authentication to the event project' do
    post '/v1/events', JSON.generate(event), headers

    expect(authenticator).to have_received(:authenticated?).with(
      'Bearer trusted-token', event.fetch('project')
    )
  end

  it 'rejects unauthenticated events before persistence' do
    allow(authenticator).to receive(:authenticated?).and_return(false)

    post '/v1/events', JSON.generate(event), headers

    expect(last_response.status).to eq(401)
    expect(event_store).not_to have_received(:insert)
  end

  it 'rejects invalid events before persistence' do
    event['unexpected'] = true

    post '/v1/events', JSON.generate(event), headers

    expect(last_response.status).to eq(422)
    expect(event_store).not_to have_received(:insert)
  end

  it 'rejects requests larger than the transport limit' do
    post '/v1/events', 'x' * (described_class::MAX_REQUEST_BYTES + 1), headers

    expect(last_response.status).to eq(413)
  end

  it 'fails closed when collector dependencies are not configured' do
    described_class.authenticator = nil

    post '/v1/events', JSON.generate(event), headers

    expect(last_response.status).to eq(503)
  end
end
