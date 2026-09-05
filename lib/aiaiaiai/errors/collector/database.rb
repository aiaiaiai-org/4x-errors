# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "sequel"
require "uri"

module Aiaiaiai
  module Errors
    module Collector
      # The one place that knows how to reach PostgreSQL.
      #
      # The connection URL is read from the environment and never logged,
      # echoed or included in an error message: everything that has to name the
      # database uses {redact}.
      module Database
        MIGRATIONS_PATH = File.join(Protocol::ROOT, "db", "migrations")
        LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

        Error = Class.new(StandardError)
        NotConfigured = Class.new(Error)

        module_function

        def connect(url = ENV["DATABASE_URL"], max_connections: Integer(ENV.fetch("DATABASE_MAX_CONNECTIONS", "8")))
          raise NotConfigured, "DATABASE_URL is not set" if url.nil? || url.empty?

          db = Sequel.connect(
            require_tls(url),
            max_connections: max_connections,
            pool_timeout: 5,
            connect_timeout: 5
          )
          db.extension :pg_array, :pg_json
          db
        end

        # Supabase is only ever reached over TLS. A URL that forgot to say so
        # is corrected rather than trusted.
        def require_tls(url)
          uri = URI.parse(url)
          return url if LOCAL_HOSTS.include?(uri.host) || uri.query.to_s.include?("sslmode=")

          uri.query = [uri.query, "sslmode=require"].compact.reject(&:empty?).join("&")
          uri.to_s
        rescue URI::InvalidURIError
          url
        end

        # A form of the URL that is safe to print.
        def redact(url = ENV["DATABASE_URL"])
          return "(unset)" if url.nil? || url.empty?

          uri = URI.parse(url)
          "#{uri.scheme}://#{"#{uri.user}:***@" if uri.user}#{uri.host}:#{uri.port}#{uri.path}"
        rescue URI::InvalidURIError
          "(unparseable)"
        end

        def migrate(db, target: nil)
          Sequel.extension :migration
          Sequel::Migrator.run(db, MIGRATIONS_PATH, target: target)
        end

        def migrations_current?(db)
          Sequel.extension :migration
          Sequel::Migrator.is_current?(db, MIGRATIONS_PATH)
        end

        def reachable?(db)
          db.fetch("SELECT 1 AS reachable").first[:reachable] == 1
        rescue Sequel::Error, StandardError
          false
        end
      end
    end
  end
end
