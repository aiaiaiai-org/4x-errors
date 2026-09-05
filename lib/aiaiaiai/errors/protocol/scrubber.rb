# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

module Aiaiaiai
  module Errors
    module Protocol
      # Removes credentials and other obvious secrets from a payload.
      #
      # Scrubbing runs on the collector, before anything is persisted, so a
      # careless reporter cannot durably store a secret. The SDK applies the
      # same rules before sending, so a secret does not travel at all when the
      # reporter is well behaved.
      module Scrubber
        REDACTED = "[redacted]"

        SENSITIVE_KEY = /
          pass(word|wd|phrase)? | secret | token | credential | cookie |
          api[_-]?key | access[_-]?key | private[_-]?key | signing[_-]?key |
          authorization | auth[_-]?header | session[_-]?id | set[_-]?cookie |
          database[_-]?url | connection[_-]?string | dsn
        /xi

        SENSITIVE_VALUE = [
          # URL with inline credentials: postgres://user:password@host/db
          %r{\b([a-z][a-z0-9+.-]*://)[^\s:/@]+:[^\s/@]+@}i,
          # Authorization headers pasted into free text
          /\b(bearer|basic|token)\s+[A-Za-z0-9._~+\/=-]{8,}/i,
          # JSON web tokens
          /\beyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\b/,
          # PEM private key blocks
          /-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----/m
        ].freeze

        module_function

        # Recursively scrubs any JSON-shaped value.
        def scrub(value, key: nil)
          return REDACTED if key && SENSITIVE_KEY.match?(key.to_s)

          case value
          when Hash then value.to_h { |nested_key, nested| [nested_key, scrub(nested, key: nested_key)] }
          when Array then value.map { |nested| scrub(nested) }
          when String then scrub_string(value)
          else value
          end
        end

        def scrub_string(string)
          SENSITIVE_VALUE.reduce(string) do |carry, pattern|
            carry.gsub(pattern) do |match|
              # Keep the scheme of a credentialed URL, it is diagnostic and not secret.
              scheme = Regexp.last_match(1)
              scheme&.end_with?("://") ? "#{scheme}#{REDACTED}@" : REDACTED
            end
          end
        end
      end
    end
  end
end
