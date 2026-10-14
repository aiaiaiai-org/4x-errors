# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require 'rspec'
require_relative '../../../lib/aiaiaiai/errors/browser_ingest_policy'

RSpec.describe Aiaiaiai::Errors::BrowserIngestPolicy do
  subject(:policy) do
    described_class.new(
      'nilx-one/web' => ['https://nilx.one', 'https://app.nilx.one']
    )
  end

  it 'allows an origin configured for the declared project' do
    expect(policy.project_origin_allowed?('nilx-one/web', 'https://nilx.one')).to be(true)
  end

  it 'does not treat an allowed origin as authority for another project' do
    expect(policy.project_origin_allowed?('other/project', 'https://nilx.one')).to be(false)
  end

  it 'normalizes default HTTPS ports' do
    expect(policy.origin_allowed?('https://nilx.one:443')).to be(true)
  end

  it 'rejects non-origin URLs' do
    expect(policy.origin_allowed?('https://nilx.one/path')).to be(false)
  end

  it 'accepts screenshot-style mappings with a trailing comma and multiple lines' do
    config = %("nilx-one/web":"https://nilx.one",\n"other/app":"https://example.com",)
    parsed = described_class.from_json(config)

    expect(parsed.project_origin_allowed?('nilx-one/web', 'https://nilx.one')).to be(true)
    expect(parsed.project_origin_allowed?('other/app', 'https://example.com')).to be(true)
  end

  it 'preserves full JSON and multiple origins per project' do
    parsed = described_class.from_json('{"app":["https://one.example","https://two.example"]}')

    expect(parsed.project_origin_allowed?('app', 'https://two.example')).to be(true)
  end

  it 'rejects duplicate projects rather than overwriting their origins' do
    config = '"app":"https://one.example","app":"https://two.example",'

    expect { described_class.from_json(config) }.to raise_error(ArgumentError, /duplicate.*app/)
  end

  it 'rejects invalid mapping syntax with a configuration error' do
    expect { described_class.from_json('"app":oops') }.to raise_error(ArgumentError, /valid JSON/)
  end
end
