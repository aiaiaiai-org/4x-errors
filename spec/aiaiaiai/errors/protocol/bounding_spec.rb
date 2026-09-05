# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

RSpec.describe Aiaiaiai::Errors::Protocol::Bounding do
  let(:limits) { Aiaiaiai::Errors::Protocol::Limits }

  it 'truncates long strings' do
    bounded = described_class.context({ 'blob' => 'x' * 10_000 })

    expect(bounded['blob'].length).to eq(limits::CONTEXT_STRING_CHARS)
  end

  it 'keeps the whole context within its byte budget' do
    bounded = described_class.context((1..500).to_h { |index| ["key#{index}", 'v' * 500] })

    expect(JSON.generate(bounded).bytesize).to be <= limits::CONTEXT_BYTES
    expect(bounded['_dropped_keys']).to be_positive
  end

  it 'cuts nesting instead of recursing forever' do
    cyclic = {}
    cyclic['self'] = cyclic

    expect { described_class.context(cyclic) }.not_to raise_error
    expect(JSON.generate(described_class.context(cyclic))).to include('[truncated]')
  end

  it 'survives values that cannot describe themselves' do
    hostile = Class.new do
      def to_s = raise('no')

      def inspect = raise('no')
    end.new

    expect(described_class.context({ 'hostile' => hostile })['hostile']).to eq('[unserialisable]')
  end

  it 'survives invalid encodings' do
    bounded = described_class.context({ 'bytes' => "caf\xC3".b })

    expect { JSON.generate(bounded) }.not_to raise_error
  end

  it 'flattens an exception with its cause chain' do
    inner = ArgumentError.new('inner')
    outer = begin
      begin
        raise inner
      rescue ArgumentError
        raise 'outer'
      end
    rescue RuntimeError => e
      e
    end

    flattened = described_class.exception(outer)

    expect(flattened['type']).to eq('RuntimeError')
    expect(flattened.dig('cause', 'type')).to eq('ArgumentError')
    expect(flattened['backtrace'].length).to be <= limits::BACKTRACE_FRAMES
  end

  it 'produces a context every bound accepts' do
    validator = Aiaiaiai::Errors::Protocol.validator
    hostile = { 'deep' => { 'a' => { 'b' => { 'c' => { 'd' => { 'e' => { 'f' => 'g' } } } } } },
                'long' => 'x' * 9_000 }

    payload = {
      'protocol_version' => 'errors.v1', 'project' => 'nilx-one/web',
      'events' => [{ 'error_id' => 'a.b', 'environment' => 'test',
                     'context' => described_class.context(hostile) }]
    }

    expect(validator.validate(payload)).to be_empty
  end
end
