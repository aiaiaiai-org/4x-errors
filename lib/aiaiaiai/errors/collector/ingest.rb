# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "json"
require "securerandom"
require "sequel"
require "time"

module Aiaiaiai
  module Errors
    module Collector
      # The ingest pipeline, in the order the contract fixes:
      #
      #   authenticate -> validate -> match project -> normalise -> scrub ->
      #   fingerprint -> resolve registry -> resolve family -> persist ->
      #   persist relations -> answer with the event ids.
      #
      # Every stage either passes the payload on or ends the request with a
      # status the contract names. Nothing partially succeeds: persistence runs
      # in one transaction.
      class Ingest
        BEARER = /\ABearer\s+(?<token>[^\s]+)\z/i

        Result = Struct.new(:status, :body) do
          def to_json(*args)
            JSON.generate(body, *args)
          end
        end

        def initialize(store:, tokens:, validator: Protocol.validator, clock: -> { Time.now.utc })
          @store = store
          @tokens = tokens
          @validator = validator
          @clock = clock
        end

        attr_reader :store, :tokens, :validator, :clock

        def call(authorization:, raw_body:)
          project = tokens.authenticate(bearer_token(authorization))
          return result(401, error: "unauthorized") if project.nil?

          payload = parse(raw_body)
          return result(400, error: "malformed_json") if payload == :unparseable

          violations = validator.validate(payload)
          unless violations.empty?
            return result(400, error: "invalid_payload", protocol_version: Protocol::VERSION,
              violations: violations.map { |violation| {pointer: violation.pointer, message: violation.message} })
          end

          return result(403, error: "project_mismatch") unless payload["project"] == project

          persist(payload, project)
        rescue Store::CycleRejected => error
          result(409, error: "causal_cycle", message: error.message)
        end

        private

        def persist(payload, project)
          received_at = clock.call
          protocol_version = payload["protocol_version"]

          events = payload["events"].map { |event| normalise_event(event, project, protocol_version, received_at) }
          relations = Array(payload["relations"]).map { |relation| normalise_relation(relation, received_at) }

          recorded = store.record(events: events, relations: relations, received_at: received_at)

          result(202,
            accepted: recorded[:events].length,
            events: recorded[:events].map { |event| {event_id: event[:event_id], duplicate: event[:duplicate]} },
            relations: {
              stored: recorded[:relations].count { |relation| relation[:stored] },
              already_known: recorded[:relations].count { |relation| !relation[:stored] }
            })
        end

        # Secrets are removed before anything else is derived from the payload,
        # so neither the stored row nor the fingerprint can carry one.
        def normalise_event(event, project, protocol_version, received_at)
          clean = Protocol::Scrubber.scrub(event)

          {
            id: SecureRandom.uuid_v7,
            protocol_version: protocol_version,
            error_id: clean["error_id"],
            reported_family_id: clean["family_id"],
            project: project,
            component: clean["component"],
            environment: clean["environment"],
            severity: clean["severity"] || Protocol::Vocabulary::DEFAULT_SEVERITY,
            message: clean["message"],
            exception: json_or_nil(clean["exception"]),
            fingerprint: Protocol::Fingerprint.for(clean),
            context: Sequel.pg_jsonb(clean["context"] || {}),
            tags: Sequel.pg_jsonb(clean["tags"] || {}),
            observed_at: parse_time(clean["observed_at"]) || received_at,
            occurrence_key: clean["occurrence_key"],
            sdk: json_or_nil(clean["sdk"]),
            local_ref: clean["local_ref"]
          }
        end

        def normalise_relation(relation, received_at)
          {
            source: symbolise_endpoint(relation["source"]),
            target: symbolise_endpoint(relation["target"]),
            type: relation["type"],
            confidence: relation["confidence"],
            evidence: relation["evidence"],
            note: relation["note"],
            created_by: "reporter",
            created_at: received_at
          }
        end

        def symbolise_endpoint(endpoint)
          endpoint.transform_keys(&:to_sym)
        end

        def json_or_nil(value)
          value.nil? ? nil : Sequel.pg_jsonb(value)
        end

        def parse_time(value)
          value && Time.iso8601(value).utc
        rescue ArgumentError, TypeError
          nil
        end

        def parse(raw_body)
          JSON.parse(raw_body.to_s)
        rescue JSON::ParserError
          :unparseable
        end

        def bearer_token(authorization)
          match = BEARER.match(authorization.to_s)
          match && match[:token]
        end

        def result(status, **body)
          Result.new(status, body)
        end
      end
    end
  end
end
