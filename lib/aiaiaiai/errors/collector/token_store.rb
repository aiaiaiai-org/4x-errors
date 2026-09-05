# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "digest"
require "json"
require "openssl"
require "securerandom"

module Aiaiaiai
  module Errors
    module Collector
      # Project scoped ingest tokens.
      #
      # Only SHA-256 digests are configured, so the deployment environment
      # never holds a usable token, and comparison is constant time. A token
      # authenticates exactly one project; the pipeline then refuses any
      # payload that claims to belong to a different one.
      class TokenStore
        ENV_VAR = "ERRORS_INGEST_TOKENS"
        DIGEST_FORMAT = /\A[0-9a-f]{64}\z/

        class InvalidConfiguration < StandardError; end

        # ERRORS_INGEST_TOKENS is a JSON object of project => [sha256 digest].
        def self.from_env(env = ENV)
          raw = env[ENV_VAR].to_s.strip
          return new({}) if raw.empty?

          parsed = JSON.parse(raw)
          raise InvalidConfiguration, "#{ENV_VAR} must be a JSON object of project => [digest]" unless parsed.is_a?(Hash)

          new(parsed)
        rescue JSON::ParserError
          raise InvalidConfiguration, "#{ENV_VAR} is not valid JSON"
        end

        def self.digest(token)
          Digest::SHA256.hexdigest(token.to_s)
        end

        # Mints a token and the digest to configure for it. The token itself is
        # never stored anywhere by this system.
        def self.issue(project)
          token = "#{project.tr("/", "_")}.#{SecureRandom.urlsafe_base64(32)}"
          {project: project, token: token, digest: digest(token)}
        end

        def initialize(digests_by_project)
          @projects_by_digest = {}
          digests_by_project.each do |project, digests|
            Array(digests).each do |value|
              normalised = value.to_s.downcase
              unless DIGEST_FORMAT.match?(normalised)
                raise InvalidConfiguration, "#{project} is configured with something that is not a SHA-256 digest"
              end

              @projects_by_digest[normalised] = project.to_s
            end
          end
          @projects_by_digest.freeze
        end

        def empty?
          @projects_by_digest.empty?
        end

        # Returns the project the token belongs to, or nil.
        def authenticate(token)
          return nil if token.nil? || token.empty?

          presented = self.class.digest(token)
          @projects_by_digest.each do |digest, project|
            return project if OpenSSL.fixed_length_secure_compare(digest, presented)
          end
          nil
        end
      end
    end
  end
end
