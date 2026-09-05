# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'

module Aiaiaiai
  module Errors
    # Validates transport and protocol constraints for one errors.v1 event.
    class EventValidator
      MAX_CONTEXT_BYTES = 16_384
      MAX_TAGS = 32
      REQUIRED_FIELDS = %w[
        protocol_version event_id error_id project source severity message full_text observed_at context tags
      ].freeze
      OPTIONAL_FIELDS = %w[family_id caused_by_event_id correlation_id].freeze
      ALLOWED_FIELDS = (REQUIRED_FIELDS + OPTIONAL_FIELDS).freeze
      ERROR_ID = /\A[a-z0-9]+(?:\.[a-z0-9]+)+\z/
      FAMILY_ID = /\Afamily\.[a-z0-9]+(?:\.[a-z0-9]+)+\z/
      UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

      LIMITS = {
        'protocol_version' => 32,
        'error_id' => 255,
        'project' => 255,
        'source' => 255,
        'severity' => 64,
        'message' => 4096,
        'full_text' => 32_768,
        'family_id' => 255,
        'correlation_id' => 255
      }.freeze

      def validate(event)
        return ['event must be an object'] unless event.is_a?(Hash)

        errors = []
        validate_fields(event, errors)
        validate_identifiers(event, errors)
        validate_strings(event, errors)
        validate_payloads(event, errors)
        errors
      end

      def valid?(event)
        validate(event).empty?
      end

      private

      def validate_fields(event, errors)
        unknown = event.keys.map(&:to_s) - ALLOWED_FIELDS
        missing = REQUIRED_FIELDS - event.keys.map(&:to_s)
        errors << "unknown fields: #{unknown.sort.join(', ')}" unless unknown.empty?
        errors << "missing fields: #{missing.sort.join(', ')}" unless missing.empty?
      end

      def validate_identifiers(event, errors)
        errors << 'protocol_version must equal errors.v1' unless value(event, 'protocol_version') == 'errors.v1'
        validate_pattern(event, 'event_id', UUID, errors)
        validate_pattern(event, 'error_id', ERROR_ID, errors)
        validate_optional_pattern(event, 'family_id', FAMILY_ID, errors)
        validate_optional_pattern(event, 'caused_by_event_id', UUID, errors)
      end

      def validate_strings(event, errors)
        LIMITS.each do |field, limit|
          next unless present_key?(event, field)

          field_value = value(event, field)
          next if field_value.nil? && OPTIONAL_FIELDS.include?(field)

          errors << "#{field} must be a string" unless field_value.is_a?(String)
          next unless field_value.is_a?(String)

          errors << "#{field} must not be empty" if field_value.empty?
          errors << "#{field} exceeds #{limit} characters" if field_value.length > limit
        end
      end

      def validate_payloads(event, errors)
        context = value(event, 'context')
        tags = value(event, 'tags')
        errors << 'context must be an object' unless context.is_a?(Hash)
        if context.is_a?(Hash) && JSON.generate(context).bytesize > MAX_CONTEXT_BYTES
          errors << "context exceeds #{MAX_CONTEXT_BYTES} serialized bytes"
        end
        errors << 'tags must be an array' unless tags.is_a?(Array)
        errors << "tags exceeds #{MAX_TAGS} items" if tags.is_a?(Array) && tags.length > MAX_TAGS
        errors << 'tags must contain strings only' if tags.is_a?(Array) && tags.any? { |tag| !tag.is_a?(String) }
      end

      def validate_pattern(event, field, pattern, errors)
        field_value = value(event, field)
        errors << "#{field} has invalid format" unless field_value.is_a?(String) && pattern.match?(field_value)
      end

      def validate_optional_pattern(event, field, pattern, errors)
        field_value = value(event, field)
        return if field_value.nil?

        validate_pattern(event, field, pattern, errors)
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
