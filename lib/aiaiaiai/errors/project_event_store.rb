# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require 'json'
require 'uri'
require_relative 'event_store'

module Aiaiaiai
  module Errors
    # Selects trusted destinations from operator-managed configuration, never from event data.
    class ProjectEventStore
      class ProjectDatabaseUnavailable < StandardError; end

      OVERRIDE_CONNECTION_OPTIONS = {
        test: false, connect_timeout: 3, pool_timeout: 2, max_connections: 2,
        after_connect: ->(connection) { connection.exec('SET statement_timeout = 3000') }
      }.freeze

      def self.from_env(default_url: ENV.fetch('DATABASE_URL', nil),
                        overrides_json: ENV.fetch('ERRORS_PROJECT_DATABASE_URLS', nil),
                        connector: ->(url, **options) { EventStore.connect(url, **options) })
        raise ArgumentError, 'default collector DATABASE_URL is required' if default_url.to_s.empty?

        routes = parse_overrides(overrides_json)
        stores = { default_url => connector.call(default_url) }
        overrides = connect_overrides(routes, stores, connector)
        new(default: stores.fetch(default_url), overrides: overrides)
      rescue StandardError
        stores.values.uniq.each(&:close) if stores
        raise
      end

      def self.connect_overrides(routes, stores, connector)
        routes.to_h do |project, url|
          stores[url] ||= connector.call(url, **OVERRIDE_CONNECTION_OPTIONS)
          [project, stores.fetch(url)]
        end
      end
      private_class_method :connect_overrides

      def self.parse_overrides(value)
        return {} if value.nil? || value.strip.empty?

        mapping = JSON.parse(value, allow_duplicate_key: false)
        unless mapping.is_a?(Hash)
          raise ArgumentError, 'ERRORS_PROJECT_DATABASE_URLS must be an object'
        end

        mapping.each { |project, url| validate_mapping!(project, url) }
        mapping
      rescue JSON::ParserError
        raise ArgumentError, 'ERRORS_PROJECT_DATABASE_URLS must be valid'
      end

      def self.validate_mapping!(project, url)
        return if valid_project?(project) && valid_url?(url)

        raise ArgumentError, 'invalid project database mapping (TLS required)'
      end
      private_class_method :validate_mapping!

      def self.valid_project?(project)
        pattern = %r{\A[a-zA-Z0-9][a-zA-Z0-9._/-]{0,254}\z}
        project.is_a?(String) && project.match?(pattern)
      end
      private_class_method :valid_project?

      def self.valid_url?(url)
        return false unless url.is_a?(String)

        uri = URI.parse(url)
        valid_postgres_url?(uri) && encrypted_connection?(uri)
      rescue URI::InvalidURIError, ArgumentError
        false
      end
      private_class_method :valid_url?

      def self.valid_postgres_url?(uri)
        %w[postgres postgresql].include?(uri.scheme) &&
          uri.host && uri.user && !uri.path.to_s.empty? && uri.path != '/'
      end
      private_class_method :valid_postgres_url?

      def self.encrypted_connection?(uri)
        sslmode = URI.decode_www_form(uri.query.to_s).to_h['sslmode']
        %w[require verify-ca verify-full].include?(sslmode)
      end
      private_class_method :encrypted_connection?

      def initialize(default:, overrides: {})
        @default = default
        @overrides = overrides.freeze
      end

      def insert(event)
        project = event.fetch('project')
        store_for(project).insert(event)
      rescue Sequel::Error
        raise unless dedicated?(project)

        raise ProjectDatabaseUnavailable, 'dedicated project database unavailable'
      end

      def insert_batch(events)
        projects = events.map { |event| event.fetch('project') }.uniq
        raise ArgumentError, 'batch must contain one project' unless projects.size == 1

        project = projects.first
        store_for(project).insert_batch(events)
      rescue Sequel::Error
        raise unless dedicated?(project)

        raise ProjectDatabaseUnavailable, 'dedicated project database unavailable'
      end

      def ready?
        @default.ready?
      end

      def close
        ([@default] + @overrides.values).uniq.each(&:close)
      end

      private

      def store_for(project)
        @overrides.fetch(project, @default)
      end

      def dedicated?(project)
        store = @overrides[project]
        store && !store.equal?(@default)
      end
    end
  end
end
