# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "json"
require "time"

require_relative "limits"

module Aiaiaiai
  module Errors
    module Protocol
      # Coerces arbitrary host data into the bounded, JSON-shaped values that
      # errors.v1 accepts.
      #
      # Nothing here may raise: whatever the host handed us, the result is a
      # payload the collector will accept. Values that cannot be represented
      # are replaced, not reported.
      module Bounding
        TRUNCATED = "[truncated]"
        UNSERIALISABLE = "[unserialisable]"
        DROPPED_KEYS = "_dropped_keys"

        module_function

        def context(value)
          bounded = coerce(value, 1)
          bounded = {"value" => bounded} unless bounded.is_a?(Hash)
          fit_bytes(bounded, Limits::CONTEXT_BYTES)
        end

        def tags(value)
          return {} unless value.is_a?(Hash)

          value.first(Limits::TAGS).to_h do |key, tag|
            [truncate(safe_string(key), Limits::TAG_KEY_CHARS), truncate(safe_string(tag), Limits::TAG_VALUE_CHARS)]
          end
        end

        def message(value)
          return nil if value.nil?

          truncate(safe_string(value), Limits::MESSAGE_CHARS)
        end

        # Flattens a Ruby exception, including its cause chain, into the
        # errors.v1 exception shape.
        def exception(error, depth = 1)
          return nil if error.nil?

          shape = {"type" => truncate(safe_string(error.class.name), Limits::EXCEPTION_TYPE_CHARS)}
          shape["message"] = message(safe_string(error.message))
          backtrace = error.backtrace
          if backtrace.is_a?(Array) && !backtrace.empty?
            shape["backtrace"] = backtrace.first(Limits::BACKTRACE_FRAMES)
              .map { |frame| truncate(safe_string(frame), Limits::BACKTRACE_FRAME_CHARS) }
          end
          if depth < Limits::CAUSE_DEPTH && error.respond_to?(:cause) && error.cause && !error.cause.equal?(error)
            cause = exception(error.cause, depth + 1)
            shape["cause"] = cause if cause
          end
          shape
        rescue
          {"type" => UNSERIALISABLE}
        end

        def coerce(value, depth)
          case value
          when nil, true, false, Integer then value
          when Float then value.finite? ? value : safe_string(value)
          when String then truncate(value, Limits::CONTEXT_STRING_CHARS)
          when Symbol then truncate(value.to_s, Limits::CONTEXT_STRING_CHARS)
          when Time then value.utc.iso8601(3)
          when Hash then coerce_hash(value, depth)
          when Array then coerce_array(value, depth)
          else truncate(safe_string(value), Limits::CONTEXT_STRING_CHARS)
          end
        end

        def coerce_hash(value, depth)
          return TRUNCATED if depth >= Limits::CONTEXT_DEPTH

          value.first(Limits::CONTEXT_KEYS).to_h do |key, nested|
            [truncate(safe_string(key), Limits::TAG_KEY_CHARS), coerce(nested, depth + 1)]
          end
        end

        def coerce_array(value, depth)
          return TRUNCATED if depth >= Limits::CONTEXT_DEPTH

          value.first(Limits::CONTEXT_ITEMS).map { |nested| coerce(nested, depth + 1) }
        end

        # Drops trailing keys until the object serialises within its budget,
        # recording how many were dropped.
        def fit_bytes(hash, budget)
          return hash if JSON.generate(hash).bytesize <= budget

          kept = hash.to_a
          dropped = 0
          while !kept.empty? && JSON.generate(kept.to_h.merge(DROPPED_KEYS => dropped + 1)).bytesize > budget
            kept.pop
            dropped += 1
          end
          kept.to_h.merge(DROPPED_KEYS => dropped)
        rescue JSON::GeneratorError, SystemStackError
          {DROPPED_KEYS => hash.size}
        end

        def truncate(string, limit)
          return string if string.length <= limit

          "#{string[0, limit - TRUNCATED.length]}#{TRUNCATED}"
        end

        def safe_string(value)
          string = value.to_s
          (string.encoding == Encoding::UTF_8 && string.valid_encoding?) ? string : string.scrub("?").encode("UTF-8")
        rescue
          UNSERIALISABLE
        end
      end
    end
  end
end
