# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "json"
require "roda"

module Aiaiaiai
  module Errors
    module Collector
      # The entire HTTP surface: a health probe and one ingest endpoint.
      #
      # Keeping the surface this small is deliberate. Everything the collector
      # knows how to do beyond accepting events -- curating the registry,
      # reclassifying families -- happens through operational tasks, not
      # through endpoints exposed to reporters.
      class App < Roda
        plugin :default_headers,
          "content-type" => "application/json; charset=utf-8",
          "cache-control" => "no-store",
          "x-content-type-options" => "nosniff"
        plugin :halt
        plugin :error_handler do |error|
          logger&.error("#{error.class}: #{error.message}")
          response.status = 500
          # Never let an internal failure describe itself to a reporter.
          json(error: "internal_error")
        end
        plugin :not_found do
          json(error: "not_found")
        end

        # Builds a runnable application around its dependencies.
        def self.with(ingest:, database:, logger: nil)
          Class.new(self) do
            opts[:ingest] = ingest
            opts[:database] = database
            opts[:logger] = logger
          end
        end

        route do |r|
          r.get "health" do
            health
          end

          r.on "v1" do
            r.post "events" do
              ingest
            end
          end
        end

        private

        def health
          reachable = Database.reachable?(opts[:database])
          response.status = reachable ? 200 : 503
          json(
            status: reachable ? "ok" : "degraded",
            database: reachable ? "ok" : "unreachable",
            protocol_version: Protocol::VERSION
          )
        end

        def ingest
          body = read_bounded_body
          result = opts[:ingest].call(authorization: request.get_header("HTTP_AUTHORIZATION"), raw_body: body)
          response.status = result.status
          result.to_json
        end

        # A body above the protocol limit is refused before it is parsed, so an
        # oversized payload costs the collector one read and nothing more.
        def read_bounded_body
          limit = Protocol::Limits::BODY_BYTES
          declared = request.content_length&.to_i
          return too_large(limit) if declared && declared > limit

          body = request.body&.read(limit + 1) || ""
          return too_large(limit) if body.bytesize > limit

          body
        end

        def too_large(limit)
          response.status = 413
          request.halt([413, {"content-type" => "application/json; charset=utf-8"},
            [json(error: "payload_too_large", limit_bytes: limit)]])
        end

        def json(**body)
          JSON.generate(body)
        end

        def logger
          opts[:logger]
        end
      end
    end
  end
end
