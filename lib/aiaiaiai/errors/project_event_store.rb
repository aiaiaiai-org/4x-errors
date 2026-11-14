# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require 'json'
require_relative 'event_store'

module Aiaiaiai
  module Errors
    # Routes project events using operator-managed database configuration only.
    class ProjectEventStore
      def self.from_env(default_url: ENV.fetch('DATABASE_URL', nil),
                        overrides_json: ENV.fetch('ERRORS_PROJECT_DATABASE_URLS', nil),
                        connector: ->(url) { EventStore.connect(url) })
        raise ArgumentError, 'default collector DATABASE_URL is required' if default_url.to_s.empty?

        default = connector.call(default_url)
        stores = parse_overrides(overrides_json).transform_values { |url| connector.call(url) }
        new(default: default, overrides: stores)
      rescue StandardError
        [default, *stores&.values].compact.each(&:close)
        raise
      end

      def self.parse_overrides(value)
        return {} if value.nil? || value.strip.empty?

        mapping = JSON.parse(value, allow_duplicate_key: false)
        unless mapping.is_a?(Hash)
          raise ArgumentError, 'ERRORS_PROJECT_DATABASE_URLS must be an object'
        end
        mapping.each { |project, url| validate_mapping!(project, url) }
        mapping
      rescue JSON::ParserError
        raise ArgumentError, 'ERRORS_PROJECT_DATABASE_URLS must be valid JSON'
      end

      def self.validate_mapping!(project, url)
        valid_project = project.is_a?(String) && project.match?(%r{\A[a-zA-Z0-9][a-zA-Z0-9._/-]{0,254}\z})
        valid_url = url.is_a?(String) && url.match?(%r{\Apostgres(?:ql)?://})
        raise ArgumentError, 'invalid project database mapping' unless valid_project && valid_url
      end
      private_class_method :validate_mapping!

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
