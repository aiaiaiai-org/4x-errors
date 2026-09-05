# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

RSpec.describe Aiaiaiai::Errors::Collector::TokenStore do
  let(:token) { 'nilx-one-web.SjRDMz1wS0tvcw' }
  let(:store) { described_class.new('nilx-one/web' => [described_class.digest(token)]) }

  it 'resolves a token to the one project it belongs to' do
    expect(store.authenticate(token)).to eq('nilx-one/web')
  end

  it 'refuses everything else' do
    expect(store.authenticate("#{token}x")).to be_nil
    expect(store.authenticate('')).to be_nil
    expect(store.authenticate(nil)).to be_nil
  end

  it 'never holds a usable token, only its digest' do
    configured = store.instance_variable_get(:@projects_by_digest)

    expect(configured.keys).to all(match(/\A[0-9a-f]{64}\z/))
    expect(configured.keys).not_to include(token)
  end

  it 'refuses to start with a plaintext token in its configuration' do
    expect { described_class.new('nilx-one/web' => [token]) }
      .to raise_error(described_class::InvalidConfiguration, /SHA-256/)
  end

  it 'reads its configuration from the environment' do
    digest = described_class.digest(token)
    configured = %({"nilx-one/web":["#{digest}"]})
    built = described_class.from_env({ described_class::ENV_VAR => configured })

    expect(built.authenticate(token)).to eq('nilx-one/web')
  end

  it 'is empty, not broken, when nothing is configured' do
    expect(described_class.from_env({})).to be_empty
  end

  it 'refuses configuration that is not JSON' do
    expect { described_class.from_env({ described_class::ENV_VAR => 'not json' }) }
      .to raise_error(described_class::InvalidConfiguration)
  end

  it 'issues a token together with the digest to configure for it' do
    issued = described_class.issue('0xda-market/api')

    expect(issued[:digest]).to eq(described_class.digest(issued[:token]))
    expect(described_class.new('0xda-market/api' => [issued[:digest]]).authenticate(issued[:token]))
      .to eq('0xda-market/api')
  end

  it 'supports more than one live token per project, so rotation needs no downtime' do
    old = described_class.issue('nilx-one/web')
    new = described_class.issue('nilx-one/web')
    rotating = described_class.new('nilx-one/web' => [old[:digest], new[:digest]])

    expect(rotating.authenticate(old[:token])).to eq('nilx-one/web')
    expect(rotating.authenticate(new[:token])).to eq('nilx-one/web')
  end
end
