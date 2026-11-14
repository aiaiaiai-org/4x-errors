# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require 'rspec'
require_relative '../../../lib/aiaiaiai/errors/project_event_store'

RSpec.describe Aiaiaiai::Errors::ProjectEventStore do
  let(:default) { instance_spy(Aiaiaiai::Errors::EventStore, ready?: true, close: nil) }
  let(:dedicated) { instance_spy(Aiaiaiai::Errors::EventStore, ready?: true, close: nil) }
  let(:router) { described_class.new(default: default, overrides: { 'market/trading' => dedicated }) }
  let(:dedicated_url) { 'postgresql://writer:secret@db.example.com/errors?sslmode=verify-full' }

  it 'selects the shared default for unconfigured projects' do
    router.insert('project' => 'ordinary/app')
    expect(default).to have_received(:insert).with('project' => 'ordinary/app')
  end

  it 'selects a dedicated database only for an explicitly mapped project' do
    router.insert('project' => 'market/trading')
    expect(dedicated).to have_received(:insert).with('project' => 'market/trading')
  end

  it 'keeps same-project batches atomic' do
    events = Array.new(2) { { 'project' => 'market/trading' } }
    router.insert_batch(events)
    expect(dedicated).to have_received(:insert_batch).with(events)
  end

  it 'rejects mixed-project batches' do
    events = [{ 'project' => 'ordinary/app' }, { 'project' => 'market/trading' }]
    expect { router.insert_batch(events) }.to raise_error(ArgumentError, 'batch must contain one project')
  end

  it 'keeps collector readiness healthy when a dedicated database is down' do
    allow(dedicated).to receive(:ready?).and_return(false)
    expect(router.ready?).to be(true)
    expect(dedicated).not_to have_received(:ready?)
  end

  it 'limits a failing dedicated database to that project' do
    allow(dedicated).to receive(:insert).and_raise(Sequel::DatabaseError, 'down')
    expect { router.insert('project' => 'market/trading') }
      .to raise_error(described_class::ProjectDatabaseUnavailable, 'dedicated project database unavailable')
    router.insert('project' => 'ordinary/app')
    expect(default).to have_received(:insert)
  end

  it 'does not disguise failure of the shared database as a dedicated-project failure' do
    allow(default).to receive(:insert).and_raise(Sequel::DatabaseError, 'down')
    expect { router.insert('project' => 'ordinary/app') }.to raise_error(Sequel::DatabaseError)
  end

  it 'defaults to no dedicated database routes' do
    expect(described_class.parse_overrides(nil)).to eq({})
  end

  it 'accepts a private TLS-protected dedicated mapping' do
    mapping = JSON.generate('market/trading' => dedicated_url)
    expect(described_class.parse_overrides(mapping)).to eq('market/trading' => dedicated_url)
  end

  it 'rejects duplicated project keys' do
    url = dedicated_url.to_json
    expect { described_class.parse_overrides(%({"same":#{url},"same":#{url}})) }
      .to raise_error(ArgumentError)
  end

  it 'rejects non-PostgreSQL destinations and unencrypted connections' do
    ['https://malicious.example', 'postgresql://writer@db.example.com/errors'].each do |url|
      expect { described_class.parse_overrides(JSON.generate('market/trading' => url)) }
        .to raise_error(ArgumentError)
    end
  end

  it 'connects dedicated databases without testing them during boot and bounds requests' do
    calls = []
    connector = lambda do |url, **opts|
      calls << [url, opts]
      url == 'postgresql://default/main' ? default : dedicated
    end
    routes = JSON.generate('market/trading' => dedicated_url)
    obj = described_class.from_env(default_url: 'postgresql://default/main',
                                   overrides_json: routes, connector: connector)
    expect(obj.ready?).to be(true)
    expect(calls.length).to eq(2)
    expect(calls.last.last).to include(test: false, connect_timeout: 3, pool_timeout: 2, max_connections: 2)
  end

  it 'reuses one connection pool for identical database URLs and closes it once' do
    calls = []
    connector = lambda do |url, **_opts|
      calls << url
      url == 'postgresql://default/main' ? default : dedicated
    end
    routes = JSON.generate('market/a' => dedicated_url, 'market/b' => dedicated_url)
    obj = described_class.from_env(default_url: 'postgresql://default/main',
                                   overrides_json: routes, connector: connector)
    expect(calls.length).to eq(2)
    obj.close
    expect(dedicated).to have_received(:close).once
  end

  it 'closes already-opened pools when a later override cannot be created' do
    second_url = 'postgresql://writer:secret@other.example.com/errors?sslmode=require'
    connector = lambda do |url, **_opts|
      case url
      when 'postgresql://default/main' then default
      when dedicated_url then dedicated
      else raise Sequel::DatabaseConnectionError, 'down'
      end
    end
    routes = JSON.generate('market/a' => dedicated_url, 'market/b' => second_url)
    expect do
      described_class.from_env(default_url: 'postgresql://default/main',
                               overrides_json: routes, connector: connector)
    end.to raise_error(Sequel::DatabaseConnectionError)
    expect(default).to have_received(:close)
    expect(dedicated).to have_received(:close)
  end
end
