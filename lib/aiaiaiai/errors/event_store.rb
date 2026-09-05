# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'sequel'
require 'time'

module Aiaiaiai
  module Errors
    # Persists already-validated errors.v1 events.
    class EventStore
      PERSISTED_FIELDS = %w[
        event_id protocol_version error_id project source severity message full_text observed_at
        context tags family_id caused_by_event_id correlation_id
      ].freeze

      def self.connect(database_url)
        database = Sequel.connect(database_url)
        database.extension :pg_json
        new(database, owns_database: true)
      end

      def initialize(database, owns_database: false)
        @database = database
        @owns_database = owns_database
      end

      def insert(event)
        @database[:error_events].insert(attributes_for(event))
        event.fetch('event_id')
      end

      def insert_batch(events)
        @database.transaction do
          events.each { |event| @database[:error_events].insert(attributes_for(event)) }
        end
        events.map { |event| event.fetch('event_id') }
      end

      def close
        @database.disconnect if @owns_database
      end

      private

      def attributes_for(event)
        attributes = PERSISTED_FIELDS.to_h { |field| [field.to_sym, event[field]] }
        attributes[:observed_at] = Time.iso8601(attributes.fetch(:observed_at))
        attributes[:context] = Sequel.pg_jsonb(attributes.fetch(:context))
        attributes[:tags] = Sequel.pg_jsonb(attributes.fetch(:tags))
        attributes
      end
    end
  end
end
