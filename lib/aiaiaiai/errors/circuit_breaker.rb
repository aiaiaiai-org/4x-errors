# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

module Aiaiaiai
  module Errors
    # Stops talking to a collector that has stopped answering.
    #
    # After enough consecutive failures the circuit opens and delivery is
    # abandoned outright until a cooldown has passed. One trial delivery then
    # decides whether to close it again.
    class CircuitBreaker
      def initialize(threshold:, reset_after:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @threshold = threshold
        @reset_after = reset_after
        @clock = clock
        @failures = 0
        @opened_at = nil
        @mutex = Mutex.new
      end

      def allow?
        @mutex.synchronize { state == :closed || state == :half_open }
      end

      def state
        return :closed if @opened_at.nil?

        (@clock.call - @opened_at >= @reset_after) ? :half_open : :open
      end

      def record_success
        @mutex.synchronize do
          @failures = 0
          @opened_at = nil
        end
      end

      def record_failure
        @mutex.synchronize do
          # A failed trial delivery restarts the cooldown rather than
          # hammering an unhealthy collector.
          if @opened_at
            @opened_at = @clock.call
          else
            @failures += 1
            @opened_at = @clock.call if @failures >= @threshold
          end
        end
      end
    end
  end
end
