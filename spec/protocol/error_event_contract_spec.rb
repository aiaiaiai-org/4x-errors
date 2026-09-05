# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'
require 'rspec'

RSpec.describe 'errors.v1 error event contract' do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:schema) do
    JSON.parse(File.read(File.join(root, 'protocol/errors.v1/error-event.schema.json')))
  end
  let(:valid_event) do
    path = File.join(root, 'protocol/errors.v1/fixtures/error-event.valid.json')
    JSON.parse(File.read(path))
  end
  let(:invalid_event) do
    path = File.join(root, 'protocol/errors.v1/fixtures/error-event.invalid-unknown-field.json')
    JSON.parse(File.read(path))
  end

  it 'pins the protocol version and rejects unknown top-level fields' do
    expect(schema.dig('properties', 'protocol_version', 'const')).to eq('errors.v1')
    expect(schema['additionalProperties']).to be(false)
  end

  it 'keeps the required wire fields explicit' do
    expect(schema['required']).to contain_exactly(
      'protocol_version', 'event_id', 'error_id', 'project', 'source', 'severity',
      'message', 'full_text', 'observed_at', 'context', 'tags'
    )
  end

  it 'keeps stable identifiers lowercase and dot-separated' do
    error_pattern = Regexp.new(schema.dig('properties', 'error_id', 'pattern'))
    family_pattern = Regexp.new(schema.dig('properties', 'family_id', 'pattern'))

    expect(error_pattern.match?('ai.model.load.failed')).to be(true)
    expect(error_pattern.match?('ai.model-load.failed')).to be(false)
    expect(family_pattern.match?('family.ai.model.availability')).to be(true)
  end

  it 'does not invent a closed severity vocabulary in errors.v1' do
    expect(schema.dig('properties', 'severity')).not_to have_key('enum')
  end

  it 'keeps payload bounds in the canonical schema' do
    expect(schema.dig('properties', 'message', 'maxLength')).to eq(4096)
    expect(schema.dig('properties', 'full_text', 'maxLength')).to eq(32_768)
    expect(schema.dig('properties', 'tags', 'maxItems')).to eq(32)
  end

  it 'provides a fixture that conforms to the declared top-level shape' do
    declared = schema.fetch('properties').keys

    expect(valid_event.keys - declared).to be_empty
    expect(schema.fetch('required') - valid_event.keys).to be_empty
    expect(valid_event['protocol_version']).to eq('errors.v1')
  end

  it 'documents rejection with an intentionally unknown field fixture' do
    declared = schema.fetch('properties').keys

    expect(invalid_event.keys - declared).to eq(['unexpected'])
  end
end
