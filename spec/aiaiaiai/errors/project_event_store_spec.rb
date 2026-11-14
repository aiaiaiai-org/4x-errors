# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require 'rspec'
require_relative '../../../lib/aiaiaiai/errors/project_event_store'

RSpec.describe Aiaiaiai::Errors::ProjectEventStore do
  let(:default) { double('default storage', ready?: true, close: nil) }
  let(:dedicated) { double('dedicated storage', ready?: true, close: nil) }
  let(:router) { described_class.new(default: default, overrides: { 'market/trading' => dedicated }) }

  it 'selects the default store for an unconfigured project' do
    expect(default).to receive(:insert).with('project' => 'ordinary/app')
    router.insert('project' => 'ordinary/app')
  end

  it 'selects an explicit dedicated store only from server configuration' do
    expect(dedicated).to receive(:insert).with('project' => 'market/trading')
    router.insert('project' => 'market/trading')
  end

  it 'keeps batches atomic inside one configured database' do
    events = [{ 'project' => 'market/trading' }, { 'project' => 'market/trading' }]
    expect(dedicated).to receive(:insert_batch).with(events)
    router.insert_batch(events)
  end

  it 'refuses batches that cross database boundaries' do
    expect { router.insert_batch([{ 'project' => 'ordinary/app' }, { 'project' => 'market/trading' }]) }
      .to raise_error(ArgumentError, 'batch must contain one project')
  end

  it 'checks both stores before advertising readiness' do
    allow(dedicated).to receive(:ready?).and_return(false)
    expect(router.ready?).to eq(false)
  end

  it 'does not accept arbitrary or duplicated project database configuration' do
    expect(described_class.parse_overrides(nil)).to eq({})
    expect(described_class.parse_overrides('{"market/trading":"postgresql://host/db"}'))
      .to eq('market/trading' => 'postgresql://host/db')
    expect { described_class.parse_overrides('{"same":"postgres://a","same":"postgres://b"}') }
      .to raise_error(ArgumentError)
    expect { described_class.parse_overrides('{"market/trading":"https://malicious.example"}') }
      .to raise_error(ArgumentError)
  end

  it 'uses the single central default when no override is supplied' do
    calls = []
    connector = ->(url) { calls << url; default }
    obj = described_class.from_env(default_url: 'postgres://central/default', overrides_json: nil,
                                   connector: connector)
    expect(calls).to eq(['postgres://central/default'])
    expect(obj.ready?).to eq(true)
  end
end
