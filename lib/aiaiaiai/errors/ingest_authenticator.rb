# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'digest'
require 'json'
require 'openssl'

module Aiaiaiai
  module Errors
    # Authenticates trusted ingest callers without storing plaintext tokens.
    class IngestAuthenticator
      BEARER = /\ABearer (?<token>.+)\z/
      SHA256_HEX = /\A[0-9a-f]{64}\z/i

      def self.from_json(json)
        configuration = JSON.parse(json)
        raise ArgumentError, 'ingest token configuration must be an object' unless configuration.is_a?(Hash)

        new(configuration)
      rescue JSON::ParserError => e
        raise ArgumentError, 'ingest token configuration must be valid JSON' from e
      end

      def initialize(project_digests)
        @project_digests = normalize(project_digests)
      end

      def authenticated?(authorization, project)
        token = bearer_token(authorization)
        return false unless token && project.is_a?(String)

        candidates = @project_digests.fetch(project, EMPTY_DIGESTS)
        actual = Digest::SHA256.digest(token)
        candidates.any? { |expected| OpenSSL.fixed_length_secure_compare(actual, expected) }
      end

      private

      EMPTY_DIGESTS = [].freeze

      def normalize(project_digests)
        project_digests.to_h do |project, digests|
          raise ArgumentError, 'project names must be non-empty strings' unless valid_project?(project)

          [project, normalize_digests(digests)]
        end.freeze
      end

      def normalize_digests(digests)
        values = digests.is_a?(Array) ? digests : [digests]
        raise ArgumentError, 'each project must have at least one ingest token digest' if values.empty?
        raise ArgumentError, 'ingest token digests must be SHA-256 hex strings' unless values.all? { |value| valid_digest?(value) }

        values.map { |value| [value].pack('H*').freeze }.freeze
      end

      def valid_project?(project)
        project.is_a?(String) && !project.empty?
      end

      def valid_digest?(value)
        value.is_a?(String) && SHA256_HEX.match?(value)
      end

      def bearer_token(authorization)
        return unless authorization.is_a?(String)

        BEARER.match(authorization)&.fetch(:token)
      end
    end
  end
end
