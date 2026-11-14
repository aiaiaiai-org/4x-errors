# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require 'rspec'
require_relative '../../../lib/aiaiaiai/errors/browser_rate_limiter'

RSpec.describe Aiaiaiai::Errors::BrowserRateLimiter do
  it 'rejects new keys when capacity is full instead of evicting live counters' do
    limiter = described_class.new(events_per_window: 2, max_keys: 2)
    expect(limiter.consume('ip-a').allowed).to eq(true)
    expect(limiter.consume('ip-b').allowed).to eq(true)
    result = limiter.consume('ip-c')
    expect(result.allowed).to eq(false)
    expect(result.retry_after).to be_positive
    expect(limiter.consume('ip-a').allowed).to eq(true)
    expect(limiter.consume('ip-a').allowed).to eq(false)
    expect(limiter.consume('ip-c').allowed).to eq(false)
  end

  it 'reclaims expired keys without unlimited key growth' do
    now = 0.0
    limiter = described_class.new(max_keys: 1, window_seconds: 2, clock: -> { now })
    expect(limiter.consume('ip-a').allowed).to eq(true)
    expect(limiter.consume('ip-b').allowed).to eq(false)
    now = 3.0
    expect(limiter.consume('ip-b').allowed).to eq(true)
  end
end
