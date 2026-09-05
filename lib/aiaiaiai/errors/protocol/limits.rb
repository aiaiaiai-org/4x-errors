# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

module Aiaiaiai
  module Errors
    module Protocol
      # Hard bounds of errors.v1.
      #
      # The collector rejects anything above these bounds; the SDK truncates to
      # them before sending, so a well behaved reporter never trips them.
      module Limits
        BODY_BYTES = 1_048_576      # 1 MiB, whole request
        EVENTS_PER_REQUEST = 100
        RELATIONS_PER_REQUEST = 200

        ID_CHARS = 200              # error_id, family_id, project, occurrence_key
        MESSAGE_CHARS = 4_096
        COMPONENT_CHARS = 100
        FINGERPRINT_CHARS = 128

        EXCEPTION_TYPE_CHARS = 200
        BACKTRACE_FRAMES = 50
        BACKTRACE_FRAME_CHARS = 512
        CAUSE_DEPTH = 5

        CONTEXT_BYTES = 16_384
        CONTEXT_DEPTH = 6
        CONTEXT_KEYS = 64           # per object
        CONTEXT_ITEMS = 64          # per array
        CONTEXT_STRING_CHARS = 2_048

        TAGS = 32
        TAG_KEY_CHARS = 64
        TAG_VALUE_CHARS = 256

        NOTE_CHARS = 1_000
        LOCAL_REF_CHARS = 64
      end
    end
  end
end
