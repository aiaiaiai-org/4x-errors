# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'puma'
require 'puma/configuration'

# The whole path, once: host application -> SDK -> HTTPS -> collector ->
# PostgreSQL, over a real socket and a real database.
RSpec.describe 'reporting end to end', :database do
  let(:database) { TestDatabase.connection }
  let(:token) { 'nilx-one-web.end-to-end' }
  let(:tokens) do
    Aiaiaiai::Errors::Collector::TokenStore.new(
      'nilx-one/web' => [Aiaiaiai::Errors::Collector::TokenStore.digest(token)]
    )
  end

  let(:server) do
    app = Aiaiaiai::Errors::Collector.rack_app(db: database, tokens: tokens, logger: nil)
    Puma::Server.new(app, Puma::Events.new)
  end
  let(:port) { server.add_tcp_listener('127.0.0.1', 0).addr[1] }

  before do
    port
    server.run
  end

  after { server.stop(true) }

  def configure(**overrides)
    Aiaiaiai::Errors.configure do |config|
      config.endpoint = "http://127.0.0.1:#{port}"
      config.token = token
      config.project = 'nilx-one/web'
      config.environment = 'production'
      config.component = 'web'
      config.proxy = nil
      config.flush_interval = 0.05
      config.shutdown_timeout = 5.0
      overrides.each { |name, value| config.public_send(:"#{name}=", value) }
    end
  end

  def report_a_failure
    raise ArgumentError, 'model weights are missing'
  rescue ArgumentError => e
    Aiaiaiai::Errors.capture(e, error_id: 'ai.model.load.failed',
                                family_id: 'ai.model.availability',
                                context: { 'model' => 'avatar-v3', 'token' => 'must not survive' },
                                tags: { 'release' => '2026.09.1' })
    Aiaiaiai::Errors.flush(timeout: 5.0)
  end

  it 'stores what a host application reported' do
    configure
    report_a_failure
    row = database[:error_events].first

    expect(row[:error_id]).to eq('ai.model.load.failed')
    expect(row[:project]).to eq('nilx-one/web')
    expect(row[:component]).to eq('web')
    expect(row[:exception].to_h['type']).to eq('ArgumentError')
    expect(row[:context].to_h['model']).to eq('avatar-v3')
  end

  it 'decides for itself what the reporter may not, and scrubs what it should not have sent' do
    configure
    report_a_failure
    row = database[:error_events].first

    expect(row[:severity]).to eq('error')
    expect(row[:context].to_h['token']).to eq('[redacted]')
    expect(row[:received_at]).to be_within(60).of(Time.now.utc)
    expect(database[:error_families].select_map(:family_id)).to eq(['ai.model.availability'])
  end

  it 'carries an explicit causal relation through to the graph' do
    configure

    Aiaiaiai::Errors.relate(source: 'ai.model.load.failed', type: 'root_cause_of',
                            target: 'ai.avatar.response.unavailable', confidence: 0.95,
                            evidence: %w[explicit_reporter_relation dependency_failure],
                            note: 'the avatar pipeline has no fallback model')
    Aiaiaiai::Errors.flush(timeout: 5.0)

    store = Aiaiaiai::Errors::Collector::Store.new(database)
    expect(store.effects_of('ai.model.load.failed')).to eq(['ai.avatar.response.unavailable'])
  end

  it 'does not report the same occurrence twice when the host retries' do
    configure

    2.times do
      Aiaiaiai::Errors.report(error_id: 'ai.model.load.failed',
                              occurrence_key: 'nightly-rebuild-2026-09-05')
      Aiaiaiai::Errors.flush(timeout: 5.0)
    end

    expect(database[:error_events].count).to eq(1)
  end

  it 'leaves the host running when the collector disappears mid-flight' do
    configure(max_retries: 0)
    Aiaiaiai::Errors.report(error_id: 'ai.model.load.failed')
    Aiaiaiai::Errors.flush(timeout: 5.0)

    database.disconnect
    allow(Aiaiaiai::Errors::Collector::Database).to receive(:reachable?).and_return(false)

    expect { 20.times { Aiaiaiai::Errors.report(error_id: 'ai.inference.backend.unavailable') } }
      .not_to raise_error
    Aiaiaiai::Errors.flush(timeout: 2.0)
    expect(database[:error_events].count).to be >= 1
  end
end
