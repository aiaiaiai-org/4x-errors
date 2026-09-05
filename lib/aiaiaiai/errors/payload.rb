# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "time"

require_relative "protocol"
require_relative "version"

module Aiaiaiai
  module Errors
    # Turns host data into errors.v1 documents.
    #
    # Building is total: anything the host passes in either becomes a valid
    # event or is refused here, where refusal is cheap. A single malformed
    # report must never cost a whole batch of good ones.
    module Payload
      SEMANTIC_ID = /\A[a-z0-9]+([._-][a-z0-9]+)*\z/
      ENVIRONMENT = /\A[a-z0-9][a-z0-9._-]*\z/

      InvalidReport = Class.new(StandardError)

      module_function

      def event(configuration:, error_id:, exception: nil, message: nil, family_id: nil,
        context: {}, tags: {}, severity: nil, component: nil, occurrence_key: nil, observed_at: Time.now)
        built = {
          "error_id" => semantic_id!(error_id, "error_id"),
          "environment" => environment(configuration.environment),
          "severity" => severity(severity),
          "observed_at" => timestamp(observed_at),
          "sdk" => {"name" => SDK_NAME, "version" => VERSION}
        }

        built["family_id"] = semantic_id!(family_id, "family_id") if family_id
        if component || configuration.component
          built["component"] = Protocol::Bounding.truncate(
            Protocol::Bounding.safe_string(component || configuration.component), Protocol::Limits::COMPONENT_CHARS
          )
        end
        built["message"] = Protocol::Bounding.message(message) if message
        built["exception"] = Protocol::Bounding.exception(exception) if exception
        if occurrence_key
          built["occurrence_key"] = Protocol::Bounding.truncate(
            Protocol::Bounding.safe_string(occurrence_key), Protocol::Limits::ID_CHARS
          )
        end

        bounded_context = Protocol::Bounding.context(context)
        built["context"] = Protocol::Scrubber.scrub(bounded_context) unless bounded_context.empty?
        bounded_tags = Protocol::Bounding.tags(tags)
        built["tags"] = Protocol::Scrubber.scrub(bounded_tags) unless bounded_tags.empty?

        built
      end

      def relation(source:, type:, target:, confidence:, evidence:, note: nil)
        unless Protocol::Vocabulary::RELATION_TYPES.include?(type.to_s)
          raise InvalidReport, "#{type.inspect} is not a relation type"
        end

        known = Array(evidence).map(&:to_s) & Protocol::Vocabulary::EVIDENCE
        raise InvalidReport, "a relation needs at least one known kind of evidence" if known.empty?

        built = {
          "source" => endpoint(source),
          "type" => type.to_s,
          "target" => endpoint(target),
          "confidence" => probability(confidence),
          "evidence" => known.uniq
        }
        if note
          built["note"] = Protocol::Bounding.truncate(
            Protocol::Bounding.safe_string(note), Protocol::Limits::NOTE_CHARS
          )
        end
        built
      end

      def request(project:, events: [], relations: [])
        document = {
          "protocol_version" => Protocol::VERSION,
          "project" => project,
          "events" => events
        }
        document["relations"] = relations unless relations.empty?
        document
      end

      # A bare string names an error id; a hash names whichever level of the
      # model the caller meant.
      def endpoint(value)
        return {"error_id" => semantic_id!(value, "error_id")} if value.is_a?(String) || value.is_a?(Symbol)

        raise InvalidReport, "a relation endpoint is a string or a hash" unless value.is_a?(Hash)

        normalised = value.transform_keys(&:to_s)
        return {"error_id" => semantic_id!(normalised["error_id"], "error_id")} if normalised.key?("error_id")
        return {"event_id" => normalised["event_id"].to_s} if normalised.key?("event_id")
        return {"local_ref" => normalised["local_ref"].to_s} if normalised.key?("local_ref")

        raise InvalidReport, "a relation endpoint names an error_id, an event_id or a local_ref"
      end

      def semantic_id!(value, field)
        identifier = value.to_s
        raise InvalidReport, "#{field} #{value.inspect} is not a stable semantic identifier" unless
          SEMANTIC_ID.match?(identifier) && identifier.length <= Protocol::Limits::ID_CHARS

        identifier
      end

      def severity(value)
        candidate = value.to_s.downcase
        Protocol::Vocabulary::SEVERITIES.include?(candidate) ? candidate : Protocol::Vocabulary::DEFAULT_SEVERITY
      end

      def environment(value)
        candidate = value.to_s.downcase.gsub(/[^a-z0-9._-]/, "-").sub(/\A[^a-z0-9]+/, "")
        candidate.empty? ? "unknown" : candidate[0, 50]
      end

      def probability(value)
        number = Float(value)
        number.clamp(0.0, 1.0)
      rescue ArgumentError, TypeError
        raise InvalidReport, "confidence #{value.inspect} is not a number between 0 and 1"
      end

      def timestamp(value)
        (value.respond_to?(:utc) ? value.utc : Time.now.utc).iso8601(3)
      rescue
        Time.now.utc.iso8601(3)
      end
    end
  end
end
