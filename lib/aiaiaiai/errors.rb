# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require_relative 'errors/version'
require_relative 'errors/configuration'
require_relative 'errors/protocol'
require_relative 'errors/payload'
require_relative 'errors/recursion_guard'
require_relative 'errors/reporter'
require_relative 'errors/null_reporter'

module Aiaiaiai
  # Reporting side of errors.v1.
  #
  #   Aiaiaiai::Errors.configure do |errors|
  #     errors.endpoint = "https://errors.aiaiaiai.org"
  #     errors.token    = ENV["ERRORS_TOKEN"]
  #     errors.project  = "nilx-one/web"
  #   end
  #
  #   Aiaiaiai::Errors.capture(exception, error_id: "ai.model.load.failed")
  #
  # Every public call here is total. It returns nil or a boolean, never raises
  # into its caller, and never blocks it on the network. If the SDK is not
  # configured, or the collector is unreachable, or the payload cannot be
  # built, the call is a no-op. That is the single invariant this file exists
  # to protect: reporting a failure must not become one.
  module Errors
    MUTEX = Mutex.new

    class << self
      def configure
        safely do
          configuration = Configuration.new
          yield configuration if block_given?
          install(configuration)
        end
        nil
      end

      def configuration
        MUTEX.synchronize { @configuration ||= Configuration.new }
      end

      def reporter
        MUTEX.synchronize { @reporter ||= NullReporter.new }
      end

      def configured?
        !reporter.null?
      end

      # Reports an exception under a stable semantic identity.
      def capture(exception, error_id:, family_id: nil, context: {}, tags: {},
                  severity: nil, component: nil, occurrence_key: nil)
        safely do
          reporter.report(
            Payload.event(
              configuration: configuration, error_id: error_id, exception: exception,
              message: exception.respond_to?(:message) ? exception.message : nil,
              family_id: family_id, context: context, tags: tags,
              severity: severity, component: component, occurrence_key: occurrence_key
            )
          )
        end
      end

      # Reports a failure that is not carried by an exception object.
      def report(error_id:, message: nil, family_id: nil, context: {}, tags: {},
                 severity: nil, component: nil, occurrence_key: nil)
        safely do
          reporter.report(
            Payload.event(
              configuration: configuration, error_id: error_id, message: message,
              family_id: family_id, context: context, tags: tags,
              severity: severity, component: component, occurrence_key: occurrence_key
            )
          )
        end
      end

      # States an explicit relation between two failures. Causal claims need
      # evidence beyond similarity; the collector enforces that too.
      def relate(source:, type:, target:, confidence:, evidence: [], note: nil)
        safely do
          reporter.relate(
            Payload.relation(
              source: source, type: type, target: target,
              confidence: confidence, evidence: evidence, note: note
            )
          )
        end
      end

      def flush(timeout: nil)
        safely { reporter.flush(timeout: timeout || configuration.shutdown_timeout) } || false
      end

      def shutdown(timeout: nil)
        safely { reporter.shutdown(timeout: timeout || configuration.shutdown_timeout) } || false
      end

      def statistics
        safely { reporter.statistics } || {}
      end

      # Returns the SDK to its unconfigured state. Intended for tests.
      def reset!
        previous = MUTEX.synchronize do
          reporter = @reporter
          @reporter = nil
          @configuration = nil
          reporter
        end
        previous&.shutdown(timeout: 0.1) unless previous.nil? || previous.null?
        nil
      end

      private

      def install(configuration)
        replaced = MUTEX.synchronize do
          previous = @reporter
          @configuration = configuration
          @reporter = configuration.usable? ? Reporter.new(configuration) : NullReporter.new
          previous
        end
        replaced&.shutdown(timeout: 0.1) unless replaced.nil? || replaced.null?
        install_shutdown_hook
      end

      # A bounded flush at exit, so an orderly shutdown does not silently lose
      # what was already queued. It waits for the configured timeout and no
      # longer.
      def install_shutdown_hook
        return if @shutdown_hook_installed

        @shutdown_hook_installed = true
        at_exit { shutdown }
      end

      # The one place exceptions from reporting stop.
      def safely
        RecursionGuard.guard do
          yield
        rescue StandardError => e
          note_internal_error(e)
          nil
        end
      end

      def note_internal_error(error)
        handler = @configuration&.on_internal_error
        handler&.call(error)
        @configuration&.logger&.debug { "[aiaiaiai-errors] #{error.class}: #{error.message}" }
        nil
      rescue StandardError
        nil
      end
    end
  end
end
