# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'
require 'rack/test'
require 'rspec'
require_relative '../../../app'

RSpec.describe Aiaiaiai::Errors::App do
  include Rack::Test::Methods

  def app
    described_class.app
  end

  def post_browser_event(payload)
    header 'Origin', 'https://nilx.one'
    post '/v1/browser/events', JSON.generate(payload), 'CONTENT_TYPE' => 'application/json'
  end

  let(:recorded_events) { [] }
  let(:store) { instance_double(Aiaiaiai::Errors::EventStore) }
  let(:policy) do
    Aiaiaiai::Errors::BrowserIngestPolicy.new(
      'nilx-one/web' => ['https://nilx.one']
    )
  end
  let(:event) do
    path = File.expand_path('../../../protocol/errors.v1/fixtures/error-event.valid.json', __dir__)
    JSON.parse(File.read(path)).merge('project' => 'nilx-one/web')
  end

  before do
    allow(store).to receive(:insert) do |payload|
      recorded_events << payload
      payload.fetch('event_id')
    end
    allow(store).to receive(:insert_batch) do |payloads|
      recorded_events.concat(payloads)
      payloads.map { |payload| payload.fetch('event_id') }
    end
    described_class.event_store = store
    described_class.browser_policy = policy
  end

  after do
    described_class.event_store = nil
    described_class.browser_policy = nil
  end

  it 'accepts an allowed zero-secret browser event' do
    post_browser_event(event)

    expect(last_response.status).to eq(201)
    expect(last_response.headers['Access-Control-Allow-Origin']).to eq('https://nilx.one')
    expect(recorded_events).to eq([event])
  end

  it 'accepts a bounded browser event batch' do
    second = event.merge('event_id' => '22222222-2222-4222-8222-222222222222')
    post_browser_event([event, second])
    response = JSON.parse(last_response.body)

    expect(last_response.status).to eq(201)
    expect(response.fetch('event_ids')).to eq([event.fetch('event_id'), second.fetch('event_id')])
    expect(recorded_events).to eq([event, second])
  end

  it 'rejects an empty batch before persistence' do
    post_browser_event([])

    expect(last_response.status).to eq(422)
    expect(recorded_events).to be_empty
  end

  it 'rejects an oversized batch before persistence' do
    post_browser_event(Array.new(51) { event })

    expect(last_response.status).to eq(422)
    expect(recorded_events).to be_empty
  end

  it 'rejects the whole batch before persistence when one event is invalid' do
    invalid = event.merge(
      'event_id' => '22222222-2222-4222-8222-222222222222',
      'error_id' => 'invalid id'
    )
    post_browser_event([event, invalid])

    expect(last_response.status).to eq(422)
    expect(JSON.parse(last_response.body).fetch('error')).to eq('invalid_event')
    expect(recorded_events).to be_empty
  end

  it 'rejects a project that is not bound to the request origin' do
    event['project'] = 'other/project'
    post_browser_event(event)

    expect(last_response.status).to eq(403)
    expect(JSON.parse(last_response.body)).to eq('error' => 'project_origin_not_allowed')
    expect(recorded_events).to be_empty
  end

  it 'rejects the whole batch when one project is not bound to the origin' do
    other = event.merge(
      'event_id' => '22222222-2222-4222-8222-222222222222',
      'project' => 'other/project'
    )
    post_browser_event([event, other])

    expect(last_response.status).to eq(403)
    expect(recorded_events).to be_empty
  end

  it 'answers CORS preflight only for configured origins' do
    header 'Origin', 'https://nilx.one'
    options '/v1/browser/events'

    expect(last_response.status).to eq(204)
    expect(last_response.headers['Access-Control-Allow-Origin']).to eq('https://nilx.one')
    expect(last_response.headers['Access-Control-Allow-Methods']).to eq('POST, OPTIONS')
  end
end
