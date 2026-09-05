# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

module Aiaiaiai
  module Errors
    # Everything the reporter needs, with defaults chosen so that the reporting
    # path stays cheap and bounded even when the collector is unreachable.
    #
    # An incomplete configuration is not an error: it produces a null reporter.
    class Configuration
      attr_accessor :endpoint, :token, :project, :environment, :component,
        :queue_limit, :batch_size, :flush_interval,
        :open_timeout, :read_timeout, :write_timeout,
        :max_retries, :backoff, :backoff_max,
        :failure_threshold, :circuit_reset_after,
        :shutdown_timeout, :proxy, :logger, :on_internal_error

      def initialize
        @endpoint = ENV["ERRORS_ENDPOINT"]
        @token = ENV["ERRORS_TOKEN"]
        @project = ENV["ERRORS_PROJECT"]
        @environment = ENV["ERRORS_ENVIRONMENT"] || ENV["RACK_ENV"] || "development"
        @component = ENV["ERRORS_COMPONENT"]

        @queue_limit = 1_000
        @batch_size = 32
        @flush_interval = 2.0

        @open_timeout = 1.0
        @read_timeout = 2.0
        @write_timeout = 2.0

        @max_retries = 2
        @backoff = 0.2
        @backoff_max = 5.0

        @failure_threshold = 5
        @circuit_reset_after = 30.0

        @shutdown_timeout = 2.0
        @proxy = :environment
        @logger = nil
        @on_internal_error = nil
      end

      # Reporting is only attempted when the reporter knows where to send, what
      # to authenticate with, and who it is reporting for.
      def usable?
        [endpoint, token, project].none? { |value| value.nil? || value.to_s.empty? }
      end
    end
  end
end
