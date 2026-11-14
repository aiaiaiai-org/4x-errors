# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require 'rspec'
require_relative '../../../lib/aiaiaiai/errors/project_event_store'

RSpec.describe Aiaiaiai::Errors::ProjectEventStore do
  let(:default) { instance_spy(Aiaiaiai::Errors::EventStore, ready?: true, close: nil) }
  let(:dedicated) { instance_spy(Aiaiaiai::Errors::EventStore, ready?: true, close: nil) }
  let(:router) do
    described_class.new(default: default, overrides: { 'market/trading' => dedicated })
  end

  it 'selects central default for unconfigured projects' do
    router.insert('project' => 'ordinary/app')
    expect(default).to have_received(:insert).with('project' => 'ordinary/app')
  end

  it 'selects dedicated store only for an explicitly mapped project' do
    router.insert('project' => 'market/trading')
    expect(dedicated).to have_received(:insert).with('project' => 'market/trading')
  end

  it 'keeps one-project batch atomic within one database' do
    events = Array.new(2) { { 'project' => 'market/trading' } }
    router.insert_batch(events)
    expect(dedicated).to have_received(:insert_batch).with(events)
  end

  it 'refuses mixed-project batch routing' do
    events = [{ 'project' => 'ordinary/app' }, { 'project' => 'market/trading' }]
    expect { router.insert_batch(events) }.to raise_error(ArgumentError, 'batch must contain one project')
  end

  it 'refuses readiness when a dedicated database fails its health check' do
    allow(dedicated).to receive(:ready?).and_return(false)
    expect(router.ready?).to be(false)
  end

  it 'defaults to zero custom database routes' do
    expect(described_class.parse_overrides(nil)).to eq({})
  end

  it 'accepts a server-side dedicated database mapping' do
    mapping = '{"market/trading":"postgresql://host/db"}'
    expect(described_class.parse_overrides(mapping)).to eq('market/trading' => 'postgresql://host/db')
  end

  it 'rejects duplicated project mapping keys' do
    mapping = '{"same":"postgres://a","same":"postgres://b"}'
    expect { described_class.parse_overrides(mapping) }.to raise_error(ArgumentError)
  end

  it 'rejects a client-controlled web URL in storage routing' do
    mapping = '{"market/trading":"https://malicious.example"}'
    expect { described_class.parse_overrides(mapping) }.to raise_error(ArgumentError)
  end

  it 'uses one default connection when no override is configured' do
    connector = ->(_url) { default }
    obj = described_class.from_env(default_url: 'postgres://central/default', connector: connector)
    expect(obj.ready?).to be(true)
  end
end
