# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

module Aiaiaiai
  module Errors
    # Bounded process-local fixed-window limiter for the untrusted browser ingest path.
    class BrowserRateLimiter
      DEFAULT_EVENTS_PER_WINDOW = 120
      DEFAULT_WINDOW_SECONDS = 60
      DEFAULT_MAX_KEYS = 10_000

      Result = Data.define(:allowed, :retry_after)

      def initialize(events_per_window: DEFAULT_EVENTS_PER_WINDOW,
                     window_seconds: DEFAULT_WINDOW_SECONDS,
                     max_keys: DEFAULT_MAX_KEYS,
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @events_per_window = positive_integer(events_per_window, DEFAULT_EVENTS_PER_WINDOW)
        @window_seconds = positive_integer(window_seconds, DEFAULT_WINDOW_SECONDS)
        @max_keys = positive_integer(max_keys, DEFAULT_MAX_KEYS)
        @clock = clock
        @entries = {}
        @mutex = Mutex.new
      end

      def consume(key, cost: 1)
        event_cost = positive_integer(cost, 1)
        now = @clock.call

        @mutex.synchronize do
          prune!(now)
          entry = current_entry(key, now)
          return rejected(entry, now) if entry[:count] + event_cost > @events_per_window

          entry[:count] += event_cost
          Result.new(allowed: true, retry_after: nil)
        end
      end

      private

      def current_entry(key, now)
        entry = @entries[key]
        if entry.nil? || now >= entry[:expires_at]
          ensure_capacity!
          entry = { count: 0, expires_at: now + @window_seconds }
          @entries[key] = entry
        end
        entry
      end

      def rejected(entry, now)
        retry_after = [(entry[:expires_at] - now).ceil, 1].max
        Result.new(allowed: false, retry_after: retry_after)
      end

      def prune!(now)
        @entries.delete_if { |_key, entry| now >= entry[:expires_at] }
      end

      def ensure_capacity!
        return if @entries.length < @max_keys

        oldest_key = @entries.min_by { |_key, entry| entry[:expires_at] }&.first
        @entries.delete(oldest_key) if oldest_key
      end

      def positive_integer(value, fallback)
        value.is_a?(Integer) && value.positive? ? value : fallback
      end
    end
  end
end
