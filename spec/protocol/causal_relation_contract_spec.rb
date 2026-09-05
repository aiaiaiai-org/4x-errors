# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'
require 'rspec'

RSpec.describe 'errors.v1 causal relation contract' do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:schema) do
    JSON.parse(File.read(File.join(root, 'protocol/errors.v1/causal-relation.schema.json')))
  end
  let(:valid_relation) do
    path = File.join(root, 'protocol/errors.v1/fixtures/causal-relation.valid.json')
    JSON.parse(File.read(path))
  end

  it 'keeps the causal relation wire fields explicit' do
    expect(schema['required']).to contain_exactly(
      'relation_id', 'from_error_id', 'to_error_id', 'kind', 'confidence', 'evidence', 'created_at'
    )
    expect(schema['additionalProperties']).to be(false)
  end

  it 'pins the supported relation kinds without equating grouping with causality' do
    expect(schema.dig('properties', 'kind', 'enum')).to contain_exactly(
      'root_cause_of', 'derivative_of', 'triggers', 'related_to'
    )
    expect(schema.fetch('properties')).not_to have_key('family_id')
  end

  it 'uses the same stable lowercase dot-separated error identifiers as events' do
    from_pattern = Regexp.new(schema.dig('properties', 'from_error_id', 'pattern'))
    to_pattern = Regexp.new(schema.dig('properties', 'to_error_id', 'pattern'))

    expect(from_pattern.match?('ai.model.load.failed')).to be(true)
    expect(to_pattern.match?('ai.avatar.response.unavailable')).to be(true)
    expect(from_pattern.match?('ai.model-load.failed')).to be(false)
  end

  it 'does not invent evidence or confidence semantics before they are specified' do
    expect(schema.dig('properties', 'confidence')).to eq({})
    expect(schema.dig('properties', 'evidence')).to eq({})
  end

  it 'provides a fixture matching the declared top-level shape' do
    declared = schema.fetch('properties').keys

    expect(valid_relation.keys - declared).to be_empty
    expect(schema.fetch('required') - valid_relation.keys).to be_empty
    expect(valid_relation['kind']).to eq('root_cause_of')
  end
end
