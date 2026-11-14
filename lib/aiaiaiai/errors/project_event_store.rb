# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require 'json'
require_relative 'event_store'

module Aiaiaiai
  module Errors
    # Routes a project's events to its operator-selected PostgreSQL database.
    # Applications and public ingest requests can never choose database URLs.
    class ProjectEventStore
      def self.from_env(default_url: ENV['DATABASE_URL'], overrides_json: ENV['ERRORS_PROJECT_DATABASE_URLS'],
                        connector: ->(url) { EventStore.connect(url) })
        raise ArgumentError, 'default collector DATABASE_URL is required' if default_url.to_s.empty?

        mapping = parse_overrides(overrides_json)
        stores = {}
        begin
          default = connector.call(default_url)
          mapping.each do |project, url|
            stores[project] = connector.call(url)
          end
          new(default: default, overrides: stores)
        rescue StandardError
          ([default, *stores.values].compact).each(&:close)
          raise
        end
      end

      def self.parse_overrides(value)
        return {} if value.nil? || value.strip.empty?

        mapping = JSON.parse(value, allow_duplicate_key: false)
        raise ArgumentError, 'ERRORS_PROJECT_DATABASE_URLS must be an object' unless mapping.is_a?(Hash)

        mapping.each do |project, url|
          unless project.is_a?(String) && project.match?(/\A[a-zA-Z0-9][a-zA-Z0-9._\/-]{0,254}\z/) &&
                 url.is_a?(String) && url.match?(/\Apostgres(?:ql)?:\/\//)
            raise ArgumentError, 'invalid project database mapping'
          end
        end
        mapping
      rescue JSON::ParserError
        raise ArgumentError, 'ERRORS_PROJECT_DATABASE_URLS must be valid JSON'
      end

      def initialize(default:, overrides: {})
        @default = default
        @overrides = overrides.freeze
      end

      def insert(event)
        store_for(event.fetch('project')).insert(event)
      end

      def insert_batch(events)
        projects = events.map { |event| event.fetch('project') }.uniq
        raise ArgumentError, 'batch must contain one project' unless projects.size == 1

        store_for(projects.first).insert_batch(events)
      end

      def ready?
        @default.ready? && @overrides.values.all?(&:ready?)
      end

      def close
        ([@default] + @overrides.values).uniq.each(&:close)
      end

      private

      def store_for(project)
        @overrides.fetch(project, @default)
      end
    end
  end
end
