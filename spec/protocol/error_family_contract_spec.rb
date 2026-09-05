# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'
require 'rspec'

RSpec.describe 'error family contract' do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:schema) do
    JSON.parse(File.read(File.join(root, 'protocol/errors.v1/error-family.schema.json')))
  end
  let(:family) do
    path = File.join(root, 'protocol/errors.v1/fixtures/error-family.valid.json')
    JSON.parse(File.read(path))
  end

  it 'keeps family identifiers lowercase and dot-separated' do
    pattern = Regexp.new(schema.dig('properties', 'family_id', 'pattern'))

    expect(pattern.match?(family.fetch('family_id'))).to be(true)
    expect(pattern.match?('family.ai-model.availability')).to be(false)
  end

  it 'pins the lifecycle vocabulary from the protocol contract' do
    expect(schema.dig('properties', 'status', 'enum')).to eq(
      %w[open investigating known resolved]
    )
  end

  it 'requires explicit project scope and rejects schema drift' do
    expect(schema.fetch('required')).to contain_exactly(
      'family_id', 'title', 'description', 'projects', 'status'
    )
    expect(schema['additionalProperties']).to be(false)
    expect(family.fetch('projects')).not_to be_empty
  end
end
