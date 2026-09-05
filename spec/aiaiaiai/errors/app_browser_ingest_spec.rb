# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'
require 'rack/test'
require 'rspec'
require_relative '../../../app'

RSpec.describe Aiaiaiai::Errors::App do
  include Rack::Test::Methods

  class RecordingEventStore
    attr_reader :events

    def initialize
      @events = []
    end

    def insert(event)
      @events << event
      event.fetch('event_id')
    end
  end

  def app
    described_class.app
  end

  let(:store) { RecordingEventStore.new }
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
    described_class.event_store = store
    described_class.browser_policy = policy
  end

  after do
    described_class.event_store = nil
    described_class.browser_policy = nil
  end

  it 'accepts an allowed zero-secret browser event' do
    header 'Origin', 'https://nilx.one'
    post '/v1/browser/events', JSON.generate(event), 'CONTENT_TYPE' => 'application/json'

    expect(last_response.status).to eq(201)
    expect(last_response.headers['Access-Control-Allow-Origin']).to eq('https://nilx.one')
    expect(store.events).to eq([event])
  end

  it 'rejects a project that is not bound to the request origin' do
    event['project'] = 'other/project'
    header 'Origin', 'https://nilx.one'
    post '/v1/browser/events', JSON.generate(event), 'CONTENT_TYPE' => 'application/json'

    expect(last_response.status).to eq(403)
    expect(JSON.parse(last_response.body)).to eq('error' => 'project_origin_not_allowed')
    expect(store.events).to be_empty
  end

  it 'answers CORS preflight only for configured origins' do
    header 'Origin', 'https://nilx.one'
    options '/v1/browser/events'

    expect(last_response.status).to eq(204)
    expect(last_response.headers['Access-Control-Allow-Origin']).to eq('https://nilx.one')
    expect(last_response.headers['Access-Control-Allow-Methods']).to eq('POST, OPTIONS')
  end
end
