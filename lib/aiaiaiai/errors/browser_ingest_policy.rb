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
      rescue JSON::ParserError => e
        raise ArgumentError, 'browser ingest origins must be valid JSON', cause: e
      end

      def initialize(mapping)
        @origins = mapping.to_h do |project, origins|
          values = normalize_origins(origins)
          if values.empty?
            raise ArgumentError, 'browser ingest project must have at least one origin'
          end

          [String(project), values.freeze]
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

      def normalize_origins(origins)
        Array(origins).map { |origin| normalize_origin(origin) }.uniq
      end

      def normalize_origin(origin)
        uri = parse_origin(origin)
        raise ArgumentError, 'browser ingest origin must be an HTTP(S) origin' unless valid_origin?(uri)

        "#{uri.scheme}://#{origin_authority(uri)}"
      end

      def parse_origin(origin)
        URI.parse(String(origin))
      rescue URI::InvalidURIError => e
        raise ArgumentError, 'browser ingest origin must be valid', cause: e
      end

      def valid_origin?(uri)
        valid_scheme?(uri) && uri.host && origin_only?(uri)
      end

      def valid_scheme?(uri)
        %w[http https].include?(uri.scheme)
      end

      def origin_only?(uri)
        uri.path.to_s.empty? && !uri.query && !uri.fragment && !uri.userinfo
      end

      def origin_authority(uri)
        return uri.host if default_port?(uri)

        "#{uri.host}:#{uri.port}"
      end

      def default_port?(uri)
        (uri.scheme == 'https' && uri.port == 443) ||
          (uri.scheme == 'http' && uri.port == 80)
      end
    end
  end
end
