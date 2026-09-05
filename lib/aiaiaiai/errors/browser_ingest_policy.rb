# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'
require 'uri'

module Aiaiaiai
  module Errors
    # Filters untrusted browser ingest by exact project/origin configuration.
    class BrowserIngestPolicy
      def self.from_json(json)
        mapping = JSON.parse(json)
        raise ArgumentError, 'browser ingest origins must be an object' unless mapping.is_a?(Hash)

        new(mapping)
      rescue JSON::ParserError => error
        raise ArgumentError, 'browser ingest origins must be valid JSON', cause: error
      end

      def initialize(mapping)
        @origins = mapping.to_h do |project, origins|
          values = Array(origins).map { |origin| normalize_origin(origin) }.uniq.freeze
          raise ArgumentError, 'browser ingest project must have at least one origin' if values.empty?

          [String(project), values]
        end.freeze
      end

      def configured?
        !@origins.empty?
      end

      def origin_allowed?(origin)
        normalized = normalize_origin(origin)
        @origins.values.any? { |origins| origins.include?(normalized) }
      rescue ArgumentError
        false
      end

      def project_origin_allowed?(project, origin)
        origins = @origins[project]
        return false unless origins

        origins.include?(normalize_origin(origin))
      rescue ArgumentError
        false
      end

      private

      def normalize_origin(origin)
        uri = URI.parse(String(origin))
        valid = %w[http https].include?(uri.scheme) && uri.host && uri.path.to_s.empty? && !uri.query
        raise ArgumentError, 'browser ingest origin must be an HTTP(S) origin' unless valid

        port = uri.port
        default_port = (uri.scheme == 'https' && port == 443) || (uri.scheme == 'http' && port == 80)
        authority = default_port ? uri.host : "#{uri.host}:#{port}"
        "#{uri.scheme}://#{authority}"
      rescue URI::InvalidURIError => error
        raise ArgumentError, 'browser ingest origin must be valid', cause: error
      end
    end
  end
end
