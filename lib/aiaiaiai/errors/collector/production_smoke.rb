# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "json"
require "rack/mock_request"
require "securerandom"

module Aiaiaiai
  module Errors
    module Collector
      # A live check that the collector and its production database actually
      # work together, run from a protected job before a change is merged.
      #
      # It is deliberately not a deployment. It never resets or rewrites the
      # schema, writes only records that name themselves as smoke records, and
      # removes them again. The credentials it uses exist for the length of the
      # run and are never stored.
      class ProductionSmoke
        SMOKE_PROJECT = "aiaiaiai-org/4x-errors-smoke"
        OTHER_PROJECT = "aiaiaiai-org/4x-errors-smoke-other"
        SMOKE_ERROR_ID = "collector.production.smoke"
        SMOKE_FAMILY_ID = "collector.production.selfcheck"

        Check = Struct.new(:name, :ok, :detail) do
          def to_s
            "#{ok ? "ok  " : "FAIL"}  #{name}#{" — #{detail}" if detail}"
          end
        end

        def initialize(db:, run_id: SecureRandom.uuid, out: $stdout)
          @db = db
          @run_id = run_id
          @out = out
          @checks = []
          @smoke_token = TokenStore.issue(SMOKE_PROJECT)
          @other_token = TokenStore.issue(OTHER_PROJECT)
        end

        attr_reader :db, :run_id, :out, :checks

        # Returns true when every check passed.
        def call
          out.puts "4x-errors production validation"
          out.puts "database: #{Database.redact}"
          out.puts "run     : #{run_id}"
          out.puts

          run_checks
        ensure
          remove_smoke_records
          checks.each { |check| out.puts check }
          out.puts
          out.puts(checks.all?(&:ok) ? "all checks passed; nothing was deployed" : "validation failed")
        end

        private

        def run_checks
          check("database_connectivity") { Database.reachable?(db) or raise "database did not answer" }
          check("migrations_are_current") { Database.migrations_current?(db) or raise "migrations are pending" }
          check("health_database_dependency") { health_reports_database }
          event_id = check("ingest_test_event") { ingest_smoke_event }
          check("read_back_test_event") { read_back(event_id) }
          check("idempotency_test") { repeats_resolve_to_one_event(event_id) }
          check("cross_project_token_rejection") { foreign_token_is_refused }
          check("verify_received_at_is_server_generated") { received_at_is_the_servers(event_id) }

          checks.all?(&:ok)
        end

        def check(name)
          result = yield
          checks << Check.new(name, true, nil)
          result
        rescue => error
          checks << Check.new(name, false, "#{error.class}: #{error.message}")
          nil
        end

        def app
          @app ||= Collector.rack_app(
            db: db,
            tokens: TokenStore.new(
              SMOKE_PROJECT => [@smoke_token[:digest]],
              OTHER_PROJECT => [@other_token[:digest]]
            ),
            logger: nil
          )
        end

        def health_reports_database
          response = Rack::MockRequest.new(app).get("/health")
          body = JSON.parse(response.body)
          raise "health answered #{response.status}" unless response.status == 200
          raise "health does not report the database" unless body["database"] == "ok"

          true
        end

        def post(document, token:)
          Rack::MockRequest.new(app).post(
            "/v1/events",
            :input => JSON.generate(document),
            "CONTENT_TYPE" => "application/json",
            "HTTP_AUTHORIZATION" => "Bearer #{token}"
          )
        end

        def smoke_document(project: SMOKE_PROJECT)
          {
            "protocol_version" => Protocol::VERSION,
            "project" => project,
            "events" => [{
              "error_id" => SMOKE_ERROR_ID,
              "family_id" => SMOKE_FAMILY_ID,
              "environment" => "production",
              "severity" => "info",
              "component" => "production-validation",
              "message" => "production validation smoke record, safe to delete",
              "occurrence_key" => occurrence_key,
              # Deliberately old: the collector must date the record itself.
              "observed_at" => "2020-01-01T00:00:00Z",
              "tags" => {"smoke" => "true", "run_id" => run_id}
            }]
          }
        end

        def occurrence_key
          "smoke:#{run_id}"
        end

        def ingest_smoke_event
          response = post(smoke_document, token: @smoke_token[:token])
          raise "ingest answered #{response.status}" unless response.status == 202

          JSON.parse(response.body).dig("events", 0, "event_id") or raise "no event id was returned"
        end

        def read_back(event_id)
          raise "nothing to read back" if event_id.nil?

          row = db[:error_events][id: event_id]
          raise "the event was not stored" if row.nil?
          raise "the wrong project was stored" unless row[:project] == SMOKE_PROJECT
          raise "the wrong error id was stored" unless row[:error_id] == SMOKE_ERROR_ID

          true
        end

        def repeats_resolve_to_one_event(event_id)
          response = post(smoke_document, token: @smoke_token[:token])
          body = JSON.parse(response.body)

          raise "a repeat answered #{response.status}" unless response.status == 202
          raise "a repeat created a second event" unless body.dig("events", 0, "event_id") == event_id
          raise "a repeat was not reported as a duplicate" unless body.dig("events", 0, "duplicate")
          raise "a repeat stored a second row" unless smoke_events.count == 1

          true
        end

        def foreign_token_is_refused
          response = post(smoke_document, token: @other_token[:token])
          raise "a token from another project was answered with #{response.status}" unless response.status == 403

          true
        end

        def received_at_is_the_servers(event_id)
          raise "nothing to inspect" if event_id.nil?

          row = db[:error_events][id: event_id]
          raise "observed_at was not kept as reported" unless row[:observed_at].utc.year == 2020
          raise "received_at was not generated by the collector" unless (Time.now.utc - row[:received_at].utc).abs < 600

          true
        end

        def smoke_events
          db[:error_events].where(project: [SMOKE_PROJECT, OTHER_PROJECT], occurrence_key: occurrence_key)
        end

        # Removes this run's records, and the registry entries it created if
        # nothing else refers to them. Anything else is left alone: production
        # data is never cleaned up by a test.
        def remove_smoke_records
          removed = smoke_events.delete
          out.puts "removed #{removed} smoke record(s)"

          return if db[:error_events].where(error_id: SMOKE_ERROR_ID).count.positive?

          db[:error_family_memberships].where(error_id: SMOKE_ERROR_ID, family_id: SMOKE_FAMILY_ID).delete
          db[:error_definitions].where(error_id: SMOKE_ERROR_ID, auto_registered: true).delete
          db[:error_families].where(family_id: SMOKE_FAMILY_ID).delete
        rescue => error
          out.puts "smoke records could not be removed: #{error.class}"
        end
      end
    end
  end
end
