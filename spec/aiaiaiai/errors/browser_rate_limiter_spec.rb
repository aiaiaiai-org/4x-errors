# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require 'rspec'
require_relative '../../../lib/aiaiaiai/errors/browser_rate_limiter'

RSpec.describe Aiaiaiai::Errors::BrowserRateLimiter do
  context 'when key capacity is full' do
    let(:limiter) { described_class.new(events_per_window: 2, max_keys: 2) }

    before do
      limiter.consume('ip-a')
      limiter.consume('ip-b')
    end

    it 'rejects a new key instead of evicting live counters' do
      expect(limiter.consume('ip-c').allowed).to be(false)
    end

    it 'reports a positive retry interval' do
      expect(limiter.consume('ip-c').retry_after).to be_positive
    end

    it 'preserves the existing key budget' do
      limiter.consume('ip-a')
      expect(limiter.consume('ip-a').allowed).to be(false)
    end
  end

  it 'reclaims expired keys after the window ends' do
    now = 0.0
    limiter = described_class.new(max_keys: 1, window_seconds: 2, clock: -> { now })
    limiter.consume('ip-a')
    now = 3.0
    expect(limiter.consume('ip-b').allowed).to be(true)
  end
end
