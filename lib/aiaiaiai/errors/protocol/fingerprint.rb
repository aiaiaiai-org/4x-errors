# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "digest"

module Aiaiaiai
  module Errors
    module Protocol
      # Deterministic grouping key for occurrences the reporter did not
      # fingerprint itself.
      #
      # The fingerprint is derived from semantic identity plus the shape of the
      # failure message, never from its variable parts, so the same failure
      # keeps one fingerprint across hosts, requests and refactors.
      module Fingerprint
        PREFIX = "sha256:"

        NOISE = [
          [/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i, "<uuid>"],
          [/\b0x[0-9a-f]+\b/i, "<hex>"],
          [%r{\b[a-z]?[:/][^\s"']*[/\\][^\s"']*}i, "<path>"],
          [/\b\d+\b/, "<n>"],
          [/"[^"]*"/, "<str>"],
          [/'[^']*'/, "<str>"]
        ].freeze

        module_function

        def for(event)
          existing = event["fingerprint"]
          return existing if existing && !existing.empty?

          exception = event["exception"]
          derive(
            event["error_id"],
            exception && exception["type"],
            (exception && exception["message"]) || event["message"]
          )
        end

        def derive(error_id, exception_type, message)
          material = [error_id, exception_type, shape(message)].join("\n")
          PREFIX + Digest::SHA256.hexdigest(material)
        end

        # Collapses the variable parts of a message so that only its shape
        # contributes to the fingerprint.
        def shape(message)
          return "" if message.nil?

          NOISE.reduce(message.to_s) { |carry, (pattern, placeholder)| carry.gsub(pattern, placeholder) }
        end
      end
    end
  end
end
