# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

RSpec.describe Aiaiaiai::Errors::Protocol::Fingerprint do
  it 'keeps a reporter supplied fingerprint' do
    expect(described_class.for({ 'error_id' => 'a.b',
                                 'fingerprint' => 'sha256:given' })).to eq('sha256:given')
  end

  it 'ignores the variable parts of a message' do
    first = described_class.for({ 'error_id' => 'ai.model.load.failed',
                                  'message' => 'model 41 missing at /var/models/a.bin' })
    second = described_class.for({ 'error_id' => 'ai.model.load.failed',
                                   'message' => 'model 77 missing at /var/models/b.bin' })

    expect(first).to eq(second)
  end

  it 'separates different semantic identities' do
    first = described_class.for({ 'error_id' => 'ai.model.load.failed', 'message' => 'boom' })
    second = described_class.for({ 'error_id' => 'ai.inference.backend.unavailable',
                                   'message' => 'boom' })

    expect(first).not_to eq(second)
  end

  it 'separates different exception types under one error id' do
    base = { 'error_id' => 'ai.model.load.failed', 'message' => 'boom' }
    timeout = described_class.for(base.merge('exception' => { 'type' => 'Net::ReadTimeout' }))
    refused = described_class.for(base.merge('exception' => { 'type' => 'Errno::ECONNREFUSED' }))

    expect(timeout).not_to eq(refused)
  end
end
