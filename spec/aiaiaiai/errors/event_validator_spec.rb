# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'
require 'rspec'
require_relative '../../../lib/aiaiaiai/errors/event_validator'

RSpec.describe Aiaiaiai::Errors::EventValidator do
  subject(:validator) { described_class.new }

  let(:fixture_path) do
    File.expand_path('../../../protocol/errors.v1/fixtures/error-event.valid.json', __dir__)
  end
  let(:event) { JSON.parse(File.read(fixture_path)) }

  it 'accepts the canonical valid fixture' do
    expect(validator.validate(event)).to be_empty
  end

  it 'rejects unknown top-level fields' do
    event['unexpected'] = true

    expect(validator.validate(event)).to include('unknown fields: unexpected')
  end

  it 'enforces the serialized context byte limit' do
    event['context'] = { 'payload' => 'x' * 16_384 }

    expect(validator.validate(event)).to include('context exceeds 16384 serialized bytes')
  end

  it 'enforces tag count and tag types' do
    event['tags'] = Array.new(33, 'tag') + [1]
    errors = validator.validate(event)

    expect(errors).to include('tags exceeds 32 items', 'tags must contain strings only')
  end

  it 'rejects malformed semantic identifiers' do
    event['error_id'] = 'AI MODEL FAILED'
    event['family_id'] = 'model.availability'
    errors = validator.validate(event)

    expect(errors).to include('error_id has invalid format', 'family_id has invalid format')
  end
end
