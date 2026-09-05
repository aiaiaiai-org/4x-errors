# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "json"
require "json_schemer"

require_relative "limits"
require_relative "vocabulary"

module Aiaiaiai
  module Errors
    module Protocol
      # Machine validation of an errors.v1 payload.
      #
      # Structure is validated against the published JSON Schema, so any
      # language can reproduce it. The checks the schema cannot express --
      # nesting depth, byte size, batch-local references and the causality
      # invariants -- are applied afterwards, in the same order for everyone.
      class Validator
        Violation = Struct.new(:pointer, :message) do
          def to_s
            "#{pointer}: #{message}"
          end
        end

        def self.default
          @default ||= new
        end

        def initialize(schema_path: Protocol.schema_path)
          @schemer = JSONSchemer.schema(JSON.parse(File.read(schema_path, encoding: "UTF-8")))
        end

        # Returns [] for a valid payload, or the violations that reject it.
        def validate(payload)
          return [Violation.new("", "payload must be a JSON object")] unless payload.is_a?(Hash)

          violations = schema_violations(payload)
          return violations unless violations.empty?

          semantic_violations(payload)
        end

        def valid?(payload)
          validate(payload).empty?
        end

        private

        def schema_violations(payload)
          @schemer.validate(payload).map do |error|
            Violation.new(error["data_pointer"], schema_message(error))
          end
        end

        def schema_message(error)
          message = error["error"].to_s
          # Drop json_schemer's leading location, it is already the pointer.
          message.sub(/\A(?:value|string|number|integer|array|object|boolean|null) at `[^`]*` /, "")
        end

        def semantic_violations(payload)
          violations = []
          events = payload["events"]

          if events.empty? && Array(payload["relations"]).empty?
            violations << Violation.new("", "a request must carry at least one event or one relation")
          end

          events.each_with_index do |event, index|
            pointer = "/events/#{index}"
            bound_container(violations, "#{pointer}/context", event["context"]) if event.key?("context")
            check_cause_depth(violations, "#{pointer}/exception", event["exception"]) if event.key?("exception")
          end

          check_local_refs(violations, events)
          check_relations(violations, payload["relations"], events)
          violations
        end

        def check_local_refs(violations, events)
          seen = {}
          events.each_with_index do |event, index|
            ref = event["local_ref"]
            next unless ref

            if seen.key?(ref)
              violations << Violation.new("/events/#{index}/local_ref",
                "duplicates the local_ref of /events/#{seen[ref]}")
            end
            seen[ref] = index
          end
        end

        def check_relations(violations, relations, events)
          return if relations.nil?

          refs = events.filter_map { |event| event["local_ref"] }

          relations.each_with_index do |relation, index|
            pointer = "/relations/#{index}"
            source = relation["source"]
            target = relation["target"]

            check_endpoint(violations, "#{pointer}/source", source, refs)
            check_endpoint(violations, "#{pointer}/target", target, refs)

            if endpoint_kind(source) != endpoint_kind(target)
              violations << Violation.new(pointer,
                "source and target must both identify error ids or both identify events")
            elsif source == target
              violations << Violation.new(pointer, "source and target are identical")
            end

            next unless Vocabulary.causal?(relation["type"])

            evidence = Array(relation["evidence"])
            if (evidence - Vocabulary::WEAK_EVIDENCE).empty?
              violations << Violation.new("#{pointer}/evidence",
                "#{evidence.join(", ")} alone cannot establish a causal relation: similarity is not causality")
            end
          end
        end

        def check_endpoint(violations, pointer, endpoint, refs)
          ref = endpoint["local_ref"]
          return unless ref && !refs.include?(ref)

          violations << Violation.new(pointer, "local_ref #{ref.inspect} does not name an event in this request")
        end

        # Relations connect error ids to error ids, or concrete events to
        # concrete events. The two levels are never mixed.
        def endpoint_kind(endpoint)
          endpoint.key?("error_id") ? :error : :event
        end

        def check_cause_depth(violations, pointer, exception, depth = 1)
          return if exception.nil?

          if depth > Limits::CAUSE_DEPTH
            violations << Violation.new(pointer, "exception cause chain is deeper than #{Limits::CAUSE_DEPTH}")
            return
          end

          check_cause_depth(violations, "#{pointer}/cause", exception["cause"], depth + 1)
        end

        def bound_container(violations, pointer, value)
          bytes = JSON.generate(value).bytesize
          if bytes > Limits::CONTEXT_BYTES
            violations << Violation.new(pointer, "is #{bytes} bytes, above the #{Limits::CONTEXT_BYTES} byte limit")
          end
          walk(violations, pointer, value, 1)
        rescue JSON::GeneratorError, SystemStackError
          violations << Violation.new(pointer, "is not serialisable JSON")
        end

        def walk(violations, pointer, value, depth)
          if depth > Limits::CONTEXT_DEPTH
            violations << Violation.new(pointer, "is nested deeper than #{Limits::CONTEXT_DEPTH}")
            return
          end

          case value
          when Hash
            if value.size > Limits::CONTEXT_KEYS
              violations << Violation.new(pointer, "has #{value.size} keys, above the #{Limits::CONTEXT_KEYS} key limit")
            end
            value.each { |key, nested| walk(violations, "#{pointer}/#{key}", nested, depth + 1) }
          when Array
            if value.size > Limits::CONTEXT_ITEMS
              violations << Violation.new(pointer, "has #{value.size} items, above the #{Limits::CONTEXT_ITEMS} item limit")
            end
            value.each_with_index { |nested, index| walk(violations, "#{pointer}/#{index}", nested, depth + 1) }
          when String
            if value.length > Limits::CONTEXT_STRING_CHARS
              violations << Violation.new(pointer,
                "is #{value.length} characters, above the #{Limits::CONTEXT_STRING_CHARS} character limit")
            end
          end
        end
      end
    end
  end
end
