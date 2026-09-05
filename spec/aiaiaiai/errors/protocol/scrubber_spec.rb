# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

RSpec.describe Aiaiaiai::Errors::Protocol::Scrubber do
  it 'redacts by key, whatever the value looks like' do
    scrubbed = described_class.scrub({ 'password' => 'hunter2', 'api_key' => 12_345,
                                       'note' => 'fine' })

    expect(scrubbed).to eq({ 'password' => '[redacted]', 'api_key' => '[redacted]',
                             'note' => 'fine' })
  end

  it 'redacts credentials embedded in values, keeping the diagnostic part' do
    url = 'postgres://collector:s3cret@db.example.com/errors'
    redacted = 'postgres://[redacted]@db.example.com/errors'

    scrubbed = described_class.scrub({ 'dsn' => 'ignored by key',
                                       'detail' => "connecting to #{url} failed" })

    expect(scrubbed['detail']).to eq("connecting to #{redacted} failed")
  end

  it 'redacts bearer tokens and JSON web tokens found in free text' do
    scrubbed = described_class.scrub([
                                       'Authorization: Bearer abcdef0123456789',
                                       'token eyJhbGciOi.eyJzdWIiOiI.SflKxwRJSM'
                                     ])

    expect(scrubbed).to all(include('[redacted]'))
    expect(scrubbed.join).not_to include('abcdef0123456789')
  end

  it 'reaches into nested structures' do
    scrubbed = described_class.scrub({ 'outer' => { 'list' => [{ 'secret' => 'x' }] } })

    expect(scrubbed.dig('outer', 'list', 0, 'secret')).to eq('[redacted]')
  end
end
