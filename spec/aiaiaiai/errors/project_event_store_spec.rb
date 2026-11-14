# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require 'rspec'
require_relative '../../../lib/aiaiaiai/errors/project_event_store'

RSpec.describe Aiaiaiai::Errors::ProjectEventStore do
  describe '#routing' do
    let(:default) { instance_spy(Aiaiaiai::Errors::EventStore, ready?: true, close: nil) }
    let(:dedicated) { instance_spy(Aiaiaiai::Errors::EventStore, ready?: true, close: nil) }
    let(:router) do
      described_class.new(default: default, overrides: { 'market/trading' => dedicated })
    end

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
      expect { router.insert_batch(events) }
        .to raise_error(ArgumentError, 'batch must contain one project')
    end

    it 'keeps collector readiness healthy when a dedicated database is down' do
      allow(dedicated).to receive(:ready?).and_return(false)
      expect(router.ready?).to be(true)
      expect(dedicated).not_to have_received(:ready?)
    end

    it 'limits a failing dedicated database to that project' do
      allow(dedicated).to receive(:insert).and_raise(Sequel::DatabaseError, 'down')
      expect { router.insert('project' => 'market/trading') }
        .to raise_error(described_class::ProjectDatabaseUnavailable)
      router.insert('project' => 'ordinary/app')
      expect(default).to have_received(:insert)
    end

    it 'does not disguise failure of the shared database as a dedicated-project failure' do
      allow(default).to receive(:insert).and_raise(Sequel::DatabaseError, 'down')
      expect { router.insert('project' => 'ordinary/app') }.to raise_error(Sequel::DatabaseError)
    end
  end

  describe '.from_env' do
    let(:fixtures) do
      {
        default: instance_spy(Aiaiaiai::Errors::EventStore, ready?: true, close: nil),
        dedicated: instance_spy(Aiaiaiai::Errors::EventStore, ready?: true, close: nil),
        default_url: 'postgresql://default/main',
        dedicated_url: 'postgresql://writer:secret@db.example.com/errors?sslmode=verify-full'
      }
    end
    let(:calls) { [] }
    let(:connector) do
      lambda do |url, **opts|
        calls << [url, opts]
        if url == fixtures.fetch(:default_url)
          fixtures.fetch(:default)
        else
          fixtures.fetch(:dedicated)
        end
      end
    end
    let(:routes) { JSON.generate('market/trading' => fixtures.fetch(:dedicated_url)) }
    let(:configured_router) do
      described_class.from_env(default_url: fixtures.fetch(:default_url),
                               overrides_json: routes, connector: connector)
    end

    it 'defaults to no dedicated database routes' do
      expect(described_class.parse_overrides(nil)).to eq({})
    end

    it 'accepts a private TLS-protected dedicated mapping' do
      expect(described_class.parse_overrides(routes))
        .to eq('market/trading' => fixtures.fetch(:dedicated_url))
    end

    it 'rejects duplicated project keys' do
      url = fixtures.fetch(:dedicated_url).to_json
      expect { described_class.parse_overrides(%({"same":#{url},"same":#{url}})) }
        .to raise_error(ArgumentError)
    end

    it 'rejects non-PostgreSQL destinations and unencrypted connections' do
      ['https://malicious.example', 'postgresql://writer@db.example.com/errors'].each do |url|
        expect { described_class.parse_overrides(JSON.generate('market/trading' => url)) }
          .to raise_error(ArgumentError)
      end
    end

    it 'does not test dedicated databases during boot' do
      expect(configured_router.ready?).to be(true)
      expect(calls.length).to eq(2)
      expect(calls.last.last).to include(test: false)
    end

    it 'bounds connection and pool waits for dedicated databases' do
      configured_router
      expect(calls.last.last).to include(connect_timeout: 3, pool_timeout: 2, max_connections: 2)
    end

    context 'when two projects share one dedicated database' do
      let(:routes) do
        JSON.generate('market/a' => fixtures.fetch(:dedicated_url),
                      'market/b' => fixtures.fetch(:dedicated_url))
      end

      it 'reuses the dedicated pool' do
        configured_router
        expect(calls.length).to eq(2)
      end

      it 'closes each pool once' do
        configured_router.close
        expect(fixtures.fetch(:dedicated)).to have_received(:close).once
      end
    end

    context 'when a later override fails to initialize' do
      let(:routes) do
        JSON.generate('market/a' => fixtures.fetch(:dedicated_url),
                      'market/b' => 'postgresql://writer@other.example.com/errors?sslmode=require')
      end
      let(:connector) do
        lambda do |url, **_opts|
          raise Sequel::DatabaseConnectionError, 'down' if url.include?('other.example.com')

          if url == fixtures.fetch(:default_url)
            fixtures.fetch(:default)
          else
            fixtures.fetch(:dedicated)
          end
        end
      end

      it 'raises the connection error' do
        expect { configured_router }.to raise_error(Sequel::DatabaseConnectionError)
      end

      it 'closes already-created pools' do
        expect { configured_router }.to raise_error(Sequel::DatabaseConnectionError)
        expect(fixtures.fetch(:default)).to have_received(:close)
        expect(fixtures.fetch(:dedicated)).to have_received(:close)
      end
    end
  end
end
