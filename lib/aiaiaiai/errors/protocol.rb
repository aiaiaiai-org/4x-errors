# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require_relative "protocol/bounding"
require_relative "protocol/fingerprint"
require_relative "protocol/limits"
require_relative "protocol/scrubber"
require_relative "protocol/vocabulary"

module Aiaiaiai
  module Errors
    # errors.v1: the canonical contract.
    #
    # The schema in protocol/ is the normative artefact. This module is the
    # Ruby reference implementation of it and carries nothing Ruby specific:
    # any language can reimplement it from the schema and this directory.
    module Protocol
      VERSION = Vocabulary::VERSION

      ROOT = File.expand_path("../../..", __dir__)
      SCHEMA_PATH = File.join(ROOT, "protocol", "errors.v1.schema.json")

      module_function

      def schema_path
        SCHEMA_PATH
      end

      def schema
        @schema ||= JSON.parse(File.read(SCHEMA_PATH, encoding: "UTF-8")).freeze
      end

      # Loaded lazily: validation pulls in a JSON Schema engine that reporting
      # hosts do not need.
      def validator
        require_relative "protocol/validator"
        Validator.default
      end
    end
  end
end
