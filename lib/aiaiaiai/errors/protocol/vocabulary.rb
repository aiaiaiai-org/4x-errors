# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

module Aiaiaiai
  module Errors
    module Protocol
      # The closed vocabulary of errors.v1.
      #
      # Everything here is part of the wire contract: changing a value is a
      # protocol change and requires a new protocol version.
      module Vocabulary
        VERSION = 'errors.v1'

        SEVERITIES = %w[debug info warning error critical].freeze
        DEFAULT_SEVERITY = 'error'

        # Causal relations, expressed as the canonical cause -> effect edge they
        # contribute to the causal graph.
        #
        #   :forward  source is the cause, target is the effect
        #   :backward target is the cause, source is the effect
        CAUSAL_RELATIONS = {
          'root_cause_of' => :forward,
          'contributes_to' => :forward,
          'derivative_of' => :backward,
          'triggered_by' => :backward
        }.freeze

        # Relations that carry no causal claim at all.
        NON_CAUSAL_RELATIONS = {
          'correlated_with' => :nondirectional,
          'duplicate_of' => :alias_to_canonical
        }.freeze

        RELATION_TYPES = (CAUSAL_RELATIONS.keys + NON_CAUSAL_RELATIONS.keys).freeze

        EVIDENCE = %w[
          explicit_reporter_relation
          deterministic_rule
          shared_trace_id
          shared_operation_id
          dependency_failure
          temporal_sequence
          human_review
          heuristic_similarity
        ].freeze

        # Similarity is not causality. Evidence listed here may support a causal
        # relation but can never establish one on its own.
        WEAK_EVIDENCE = %w[heuristic_similarity].freeze

        module_function

        def causal?(relation_type)
          CAUSAL_RELATIONS.key?(relation_type)
        end

        # The cause -> effect edge a relation contributes, or nil for
        # non-causal relations.
        def causal_edge(relation_type, source, target)
          case CAUSAL_RELATIONS[relation_type]
          when :forward then [source, target]
          when :backward then [target, source]
          end
        end
      end
    end
  end
end
