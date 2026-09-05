# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

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
end
