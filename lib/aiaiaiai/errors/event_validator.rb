# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'
require 'time'

module Aiaiaiai
  module Errors
    # Validates transport and protocol constraints for one errors.v1 event.
    class EventValidator
      MAX_CONTEXT_BYTES = 16_384
      MAX_TAGS = 32
      MAX_TAG_LENGTH = 255
      REQUIRED_FIELDS = %w[
        protocol_version event_id error_id project source severity message full_text
        observed_at context tags
      ].freeze
      OPTIONAL_FIELDS = %w[family_id caused_by_event_id correlation_id].freeze
      ALLOWED_FIELDS = (REQUIRED_FIELDS + OPTIONAL_FIELDS).freeze
      ERROR_ID = /\A[a-z0-9]+(?:\.[a-z0-9]+)+\z/
      FAMILY_ID = /\Afamily\.[a-z0-9]+(?:\.[a-z0-9]+)+\z/
      UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      STRING_RULES = {
        'project' => [1, 255],
        'source' => [1, 255],
        'severity' => [1, 64],
        'message' => [1, 4096],
        'full_text' => [0, 32_768],
        'correlation_id' => [0, 255]
      }.freeze

      def validate(event)
        return ['event must be an object'] unless event.is_a?(Hash)

        errors = []
        validate_fields(event, errors)
        validate_identifiers(event, errors)
        STRING_RULES.each { |field, rule| validate_string(event, field, *rule, errors) }
        validate_observed_at(value(event, 'observed_at'), errors)
        validate_context(value(event, 'context'), errors)
        validate_tags(value(event, 'tags'), errors)
        errors
      end

      def valid?(event)
        validate(event).empty?
      end

      private

      def validate_fields(event, errors)
        keys = event.keys.map(&:to_s)
        unknown = keys - ALLOWED_FIELDS
        missing = REQUIRED_FIELDS - keys
        errors << "unknown fields: #{unknown.sort.join(', ')}" unless unknown.empty?
        errors << "missing fields: #{missing.sort.join(', ')}" unless missing.empty?
      end

      def validate_identifiers(event, errors)
        protocol = value(event, 'protocol_version')
        errors << 'protocol_version must equal errors.v1' if protocol != 'errors.v1'
        validate_pattern(value(event, 'event_id'), 'event_id', UUID, errors)
        validate_pattern(value(event, 'error_id'), 'error_id', ERROR_ID, errors)
        validate_optional_pattern(value(event, 'family_id'), 'family_id', FAMILY_ID, errors)
        caused_by = value(event, 'caused_by_event_id')
        validate_optional_pattern(caused_by, 'caused_by_event_id', UUID, errors)
      end

      def validate_string(event, field, minimum, maximum, errors)
        return unless present_key?(event, field)

        field_value = value(event, field)
        return if field_value.nil? && OPTIONAL_FIELDS.include?(field)
        return errors << "#{field} must be a string" unless field_value.is_a?(String)

        errors << "#{field} must not be empty" if minimum.positive? && field_value.empty?
        errors << "#{field} exceeds #{maximum} characters" if field_value.length > maximum
      end

      def validate_observed_at(observed_at, errors)
        return errors << 'observed_at must be a date-time string' unless observed_at.is_a?(String)

        Time.iso8601(observed_at)
      rescue ArgumentError
        errors << 'observed_at must be a valid date-time'
      end

      def validate_context(context, errors)
        return errors << 'context must be an object' unless context.is_a?(Hash)
        return unless JSON.generate(context).bytesize > MAX_CONTEXT_BYTES

        errors << "context exceeds #{MAX_CONTEXT_BYTES} serialized bytes"
      end

      def validate_tags(tags, errors)
        return errors << 'tags must be an array' unless tags.is_a?(Array)

        errors << "tags exceeds #{MAX_TAGS} items" if tags.length > MAX_TAGS
        errors << 'tags must be unique' unless tags.uniq.length == tags.length
        validate_tag_values(tags, errors)
      end

      def validate_tag_values(tags, errors)
        return errors << 'tags must contain strings only' unless tags.all?(String)

        errors << 'tags must not contain empty strings' if tags.any?(&:empty?)
        return unless tags.any? { |tag| tag.length > MAX_TAG_LENGTH }

        errors << "tags must not exceed #{MAX_TAG_LENGTH} characters"
      end

      def validate_pattern(field_value, field, pattern, errors)
        return if field_value.is_a?(String) && pattern.match?(field_value)

        errors << "#{field} has invalid format"
      end

      def validate_optional_pattern(field_value, field, pattern, errors)
        return if field_value.nil?

        validate_pattern(field_value, field, pattern, errors)
      end

      def value(event, field)
        event[field] || event[field.to_sym]
      end

      def present_key?(event, field)
        event.key?(field) || event.key?(field.to_sym)
      end
    end
  end
end
