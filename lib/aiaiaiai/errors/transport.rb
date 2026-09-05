# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

require_relative 'version'

module Aiaiaiai
  module Errors
    # Delivery of one errors.v1 request over HTTPS.
    #
    # The transport reports an outcome, never an exception, and never looks at
    # the response body: a collector that answers with nonsense is treated
    # exactly like one that answers correctly.
    class Transport
      DELIVERED = :delivered
      TRANSIENT_FAILURE = :transient_failure
      PERMANENT_FAILURE = :permanent_failure

      EVENTS_PATH = '/v1/events'

      # Statuses worth trying again: the collector is busy or briefly broken.
      RETRYABLE_STATUSES = [408, 425, 429].freeze

      def initialize(configuration)
        @configuration = configuration
        @uri = URI.join(ensure_trailing_slash(configuration.endpoint),
                        EVENTS_PATH.delete_prefix('/'))
      rescue URI::InvalidURIError, ArgumentError
        @uri = nil
      end

      attr_reader :configuration, :uri

      def deliver(payload)
        return PERMANENT_FAILURE if uri.nil?

        body = JSON.generate(payload)
        classify(perform(body))
      rescue JSON::GeneratorError, Encoding::UndefinedConversionError
        # An unserialisable payload will never become serialisable.
        PERMANENT_FAILURE
      rescue StandardError
        # Everything a network can do to a request arrives here: SocketError,
        # SystemCallError, the Net::HTTP timeouts and protocol errors,
        # OpenSSL::SSL::SSLError. None of them is worth distinguishing, because
        # the answer to all of them is the same.
        TRANSIENT_FAILURE
      end

      private

      def perform(body)
        request = Net::HTTP::Post.new(uri.request_uri)
        request['content-type'] = 'application/json'
        request['authorization'] = "Bearer #{configuration.token}"
        request['user-agent'] = "#{SDK_NAME}/#{VERSION}"
        request.body = body

        http.start { |connection| connection.request(request) }
      end

      def http
        connection = build_connection
        connection.use_ssl = uri.scheme == 'https'
        connection.open_timeout = configuration.open_timeout
        connection.read_timeout = configuration.read_timeout
        connection.write_timeout = configuration.write_timeout
        connection
      end

      def build_connection
        case configuration.proxy
        when :environment then Net::HTTP.new(uri.host, uri.port)
        when nil, false then Net::HTTP.new(uri.host, uri.port, nil)
        else proxied_connection(URI.parse(configuration.proxy.to_s))
        end
      end

      def proxied_connection(proxy)
        Net::HTTP.new(uri.host, uri.port, proxy.host, proxy.port, proxy.user, proxy.password)
      end

      def classify(response)
        status = response.code.to_i
        return DELIVERED if status.between?(200, 299)
        return TRANSIENT_FAILURE if status >= 500 || RETRYABLE_STATUSES.include?(status)

        # 400, 401, 403: the request itself is wrong. Sending it again cannot help.
        PERMANENT_FAILURE
      end

      def ensure_trailing_slash(endpoint)
        endpoint.to_s.end_with?('/') ? endpoint.to_s : "#{endpoint}/"
      end
    end
  end
end
