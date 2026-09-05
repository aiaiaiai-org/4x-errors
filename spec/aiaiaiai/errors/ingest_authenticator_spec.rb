# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'digest'
require 'json'
require 'rspec'
require_relative '../../../lib/aiaiaiai/errors/ingest_authenticator'

RSpec.describe Aiaiaiai::Errors::IngestAuthenticator do
  let(:token) { 'nilx-one-web-ingest-token' }
  let(:digest) { Digest::SHA256.hexdigest(token) }
  let(:authenticator) { described_class.new('nilx-one/web' => [digest]) }

  it 'accepts the token only for its bound project' do
    authorization = "Bearer #{token}"

    expect(authenticator.authenticated?(authorization, 'nilx-one/web')).to be(true)
    expect(authenticator.authenticated?(authorization, 'nilx-one/ai')).to be(false)
  end

  it 'rejects missing and invalid bearer credentials' do
    expect(authenticator.authenticated?(nil, 'nilx-one/web')).to be(false)
    expect(authenticator.authenticated?('Bearer wrong', 'nilx-one/web')).to be(false)
  end

  it 'supports multiple digests for token rotation' do
    rotated = Digest::SHA256.hexdigest('rotated-token')
    authenticator = described_class.new('nilx-one/web' => [digest, rotated])

    expect(authenticator.authenticated?('Bearer rotated-token', 'nilx-one/web')).to be(true)
  end

  it 'loads digest configuration from JSON' do
    json = JSON.generate('nilx-one/web' => digest)
    configured = described_class.from_json(json)

    expect(configured.authenticated?("Bearer #{token}", 'nilx-one/web')).to be(true)
  end

  it 'rejects malformed digest configuration' do
    invalid_configuration = { 'nilx-one/web' => 'plaintext-token' }

    expect { described_class.new(invalid_configuration) }.to raise_error(ArgumentError)
  end
end
