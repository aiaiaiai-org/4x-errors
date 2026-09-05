# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

# Explicit relations, at two levels.
#
# error_relations state something about failure kinds ("this kind of failure
# causes that kind"). event_relations state something about two concrete
# occurrences. The levels are never mixed.
#
# Both tables keep confidence and evidence on every row: a relation without a
# stated basis cannot be recorded. Causal cycles are rejected by the collector,
# which serialises writes to this graph.
Sequel.migration do
  change do
    create_table(:error_relations) do
      primary_key :id, type: :Bignum
      String :source_error_id, null: false
      String :relation_type, null: false
      String :target_error_id, null: false
      BigDecimal :confidence, size: [4, 3], null: false
      column :evidence, "text[]", null: false
      String :note, text: true
      String :created_by, null: false, default: "reporter"
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      constraint(:error_relations_type_known) do
        {relation_type: %w[root_cause_of derivative_of contributes_to triggered_by correlated_with duplicate_of]}
      end
      constraint(:error_relations_confidence_is_a_probability) { (confidence >= 0) & (confidence <= 1) }
      constraint(:error_relations_have_evidence, Sequel.lit("cardinality(evidence) > 0"))
      constraint(:error_relations_not_reflexive, Sequel.lit("source_error_id <> target_error_id"))
      # Similarity is not causality.
      constraint(:error_relations_causality_needs_more_than_similarity, Sequel.lit(<<~SQL))
        relation_type IN ('correlated_with', 'duplicate_of')
        OR cardinality(array_remove(evidence, 'heuristic_similarity')) > 0
      SQL
    end

    add_index :error_relations, [:source_error_id, :relation_type, :target_error_id],
      unique: true, name: :error_relations_uniq
    add_index :error_relations, [:target_error_id, :relation_type], name: :error_relations_target_idx

    create_table(:event_relations) do
      primary_key :id, type: :Bignum
      foreign_key :source_event_id, :error_events, type: :uuid, null: false, on_delete: :cascade
      String :relation_type, null: false
      foreign_key :target_event_id, :error_events, type: :uuid, null: false, on_delete: :cascade
      BigDecimal :confidence, size: [4, 3], null: false
      column :evidence, "text[]", null: false
      String :note, text: true
      String :created_by, null: false, default: "reporter"
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      constraint(:event_relations_type_known) do
        {relation_type: %w[root_cause_of derivative_of contributes_to triggered_by correlated_with duplicate_of]}
      end
      constraint(:event_relations_confidence_is_a_probability) { (confidence >= 0) & (confidence <= 1) }
      constraint(:event_relations_have_evidence, Sequel.lit("cardinality(evidence) > 0"))
      constraint(:event_relations_not_reflexive, Sequel.lit("source_event_id <> target_event_id"))
      constraint(:event_relations_causality_needs_more_than_similarity, Sequel.lit(<<~SQL))
        relation_type IN ('correlated_with', 'duplicate_of')
        OR cardinality(array_remove(evidence, 'heuristic_similarity')) > 0
      SQL
    end

    add_index :event_relations, [:source_event_id, :relation_type, :target_event_id],
      unique: true, name: :event_relations_uniq
    add_index :event_relations, [:target_event_id, :relation_type], name: :event_relations_target_idx
  end
end
