# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

module Aiaiaiai
  module Errors
    # A queue that refuses to grow.
    #
    # When it is full the newest item is dropped and counted. Reporting must
    # never become the reason a host runs out of memory, and it must never
    # block the thread that is trying to report.
    class BoundedQueue
      def initialize(limit)
        @limit = limit
        @items = []
        @dropped = 0
        @closed = false
        @mutex = Mutex.new
        @waiters = ConditionVariable.new
      end

      attr_reader :limit

      # Returns false when the item was dropped. Never blocks.
      def push(item)
        @mutex.synchronize do
          if @closed || @items.size >= @limit
            @dropped += 1 unless @closed
            next false
          end

          @items << item
          @waiters.signal
          true
        end
      end

      # Takes up to +max+ items, waiting at most +timeout+ seconds for the
      # first one.
      def pop_batch(max, timeout)
        @mutex.synchronize do
          @waiters.wait(@mutex, timeout) if @items.empty? && !@closed
          @items.shift(max)
        end
      end

      def size
        @mutex.synchronize { @items.size }
      end

      def dropped
        @mutex.synchronize { @dropped }
      end

      def empty?
        size.zero?
      end

      def close
        @mutex.synchronize do
          @closed = true
          @waiters.broadcast
        end
      end

      def closed?
        @mutex.synchronize { @closed }
      end
    end
  end
end
