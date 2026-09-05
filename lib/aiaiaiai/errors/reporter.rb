# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require_relative "bounded_queue"
require_relative "circuit_breaker"
require_relative "payload"
require_relative "recursion_guard"
require_relative "transport"

module Aiaiaiai
  module Errors
    # Hands work to a background thread and returns immediately.
    #
    # The calling thread never waits on the network, never blocks on a full
    # queue and never sees an exception from here. Delivery is best effort by
    # design: an occurrence that cannot be delivered within the configured
    # bounds is dropped and counted, never retried forever and never queued
    # without limit.
    class Reporter
      def initialize(configuration, transport: Transport.new(configuration))
        @configuration = configuration
        @transport = transport
        @breaker = CircuitBreaker.new(
          threshold: configuration.failure_threshold,
          reset_after: configuration.circuit_reset_after
        )
        @queue = BoundedQueue.new(configuration.queue_limit)
        @mutex = Mutex.new
        @thread = nil
        @pid = Process.pid
        @stopping = false
        @delivering = false
        @abandoned = 0
      end

      attr_reader :configuration

      def report(event)
        enqueue(kind: :event, data: event)
      end

      def relate(relation)
        enqueue(kind: :relation, data: relation)
      end

      def null? = false

      # Waits, but never for longer than +timeout+.
      def flush(timeout: configuration.shutdown_timeout)
        deadline = monotonic + timeout.to_f
        ensure_dispatcher
        loop do
          return true if @queue.empty? && !@delivering
          return false if monotonic >= deadline

          sleep 0.005
        end
      end

      def shutdown(timeout: configuration.shutdown_timeout)
        deadline = monotonic + timeout.to_f
        flush(timeout: timeout)
        @stopping = true
        @queue.close

        thread = @mutex.synchronize do
          running = @thread
          @thread = nil
          running
        end
        return true if thread.nil?

        thread.join([deadline - monotonic, 0.01].max)
        thread.kill if thread.alive?
        true
      end

      def statistics
        {queued: @queue.size, dropped: @queue.dropped + @abandoned, circuit: @breaker.state, null: false}
      end

      private

      def enqueue(item)
        return false if @stopping

        ensure_dispatcher
        @queue.push(item)
      end

      # Started on first use, and restarted after a fork or an unexpected
      # death. A child process never inherits the parent's backlog.
      def ensure_dispatcher
        return if @thread&.alive? && @pid == Process.pid

        @mutex.synchronize do
          if @pid != Process.pid
            @pid = Process.pid
            @queue = BoundedQueue.new(configuration.queue_limit)
            @thread = nil
          end
          next if @thread&.alive?

          @thread = Thread.new { run }
          @thread.name = "aiaiaiai-errors-reporter"
          @thread.abort_on_exception = false
          @thread.report_on_exception = false
        end
      end

      def run
        # Anything this thread reports about itself is dropped on the spot.
        RecursionGuard.claim_thread

        until @stopping && @queue.empty?
          batch = @queue.pop_batch(configuration.batch_size, configuration.flush_interval)
          next if batch.empty?

          @delivering = true
          begin
            deliver(batch)
          ensure
            @delivering = false
          end
        end
      rescue
        # The reporter is not worth a host thread. It restarts on next use.
        nil
      end

      def deliver(batch)
        document = Payload.request(
          project: configuration.project,
          events: batch.filter_map { |item| item[:data] if item[:kind] == :event },
          relations: batch.filter_map { |item| item[:data] if item[:kind] == :relation }
        )

        attempt = 0
        loop do
          unless @breaker.allow?
            @abandoned += batch.size
            return
          end

          case @transport.deliver(document)
          when Transport::DELIVERED
            @breaker.record_success
            return
          when Transport::PERMANENT_FAILURE
            # A rejected request is rejected however often it is sent.
            @breaker.record_failure
            @abandoned += batch.size
            return
          else
            @breaker.record_failure
            attempt += 1
            if attempt > configuration.max_retries || @stopping
              @abandoned += batch.size
              return
            end
            sleep backoff(attempt)
          end
        end
      end

      # Exponential, capped, and jittered so that many hosts recovering at once
      # do not arrive together.
      def backoff(attempt)
        ceiling = [configuration.backoff * (2**(attempt - 1)), configuration.backoff_max].min
        ceiling * (0.5 + (rand / 2))
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
