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
        stores_by_url = {}
        default = connector.call(default_url)
        stores_by_url[default_url] = default
        overrides = routes.to_h do |project, url|
          stores_by_url[url] ||= connector.call(url, **OVERRIDE_CONNECTION_OPTIONS)
          [project, stores_by_url.fetch(url)]
        end
        new(default: default, overrides: overrides)
      rescue StandardError
        stores_by_url&.values&.uniq&.each(&:close)
        raise
      end

      def self.parse_overrides(value)
        return {} if value.nil? || value.strip.empty?

        mapping = JSON.parse(value, allow_duplicate_key: false)
        raise ArgumentError, 'ERRORS_PROJECT_DATABASE_URLS must be an object' unless mapping.is_a?(Hash)

        mapping.each { |project, url| validate_mapping!(project, url) }
        mapping
      rescue JSON::ParserError, URI::InvalidURIError
        raise ArgumentError, 'ERRORS_PROJECT_DATABASE_URLS must be valid'
      end

      def self.validate_mapping!(project, url)
        pattern = %r{\A[a-zA-Z0-9][a-zA-Z0-9._/-]{0,254}\z}
        unless project.is_a?(String) && project.match?(pattern) && url.is_a?(String)
          raise ArgumentError, 'invalid project database mapping'
        end

        uri = URI.parse(url)
        valid_scheme = %w[postgres postgresql].include?(uri.scheme)
        valid_destination = uri.host && uri.user && uri.path && uri.path != '/'
        sslmode = URI.decode_www_form(uri.query.to_s).to_h['sslmode']
        unless valid_scheme && valid_destination && %w[require verify-ca verify-full].include?(sslmode)
          raise ArgumentError, 'invalid project database mapping (TLS required)'
        end
      rescue URI::InvalidURIError, ArgumentError
        raise ArgumentError, 'invalid project database mapping (TLS required)'
      end
      private_class_method :validate_mapping!

      def initialize(default:, overrides: {})
        @default = default
        @overrides = overrides.freeze
      end

      def insert(event)
        project = event.fetch('project')
        store_for(project).insert(event)
      rescue Sequel::Error
        raise ProjectDatabaseUnavailable, 'dedicated project database unavailable' if dedicated?(project)

        raise
      end

      def insert_batch(events)
        projects = events.map { |event| event.fetch('project') }.uniq
        raise ArgumentError, 'batch must contain one project' unless projects.size == 1

        project = projects.first
        store_for(project).insert_batch(events)
      rescue Sequel::Error
        raise ProjectDatabaseUnavailable, 'dedicated project database unavailable' if dedicated?(project)

        raise
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
