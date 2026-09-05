# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

# Raw occurrences: the ground truth of the system.
#
# Rows here are append only. They deliberately carry no foreign key to the
# registry: an occurrence must never be rejected because curation has not
# caught up with reality.
Sequel.migration do
  up do
    create_table(:error_events) do
      uuid :id, primary_key: true, null: false
      String :protocol_version, null: false
      String :error_id, null: false
      String :reported_family_id
      String :project, null: false
      String :component
      String :environment, null: false
      String :severity, null: false
      String :message, text: true
      jsonb :exception
      String :fingerprint, null: false
      jsonb :context, null: false, default: Sequel.lit("'{}'::jsonb")
      jsonb :tags, null: false, default: Sequel.lit("'{}'::jsonb")
      DateTime :observed_at, null: false
      DateTime :received_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      String :occurrence_key
      jsonb :sdk

      constraint(:error_events_severity_known) do
        {severity: %w[debug info warning error critical]}
      end
    end

    # Idempotency: a reporter that retries the same occurrence stores it once.
    add_index :error_events, [:project, :occurrence_key],
      unique: true, where: Sequel.~(occurrence_key: nil), name: :error_events_occurrence_uniq
    add_index :error_events, [:error_id, :received_at], name: :error_events_error_id_idx
    add_index :error_events, [:project, :environment, :received_at], name: :error_events_project_idx
    add_index :error_events, [:fingerprint, :received_at], name: :error_events_fingerprint_idx
    add_index :error_events, [:reported_family_id], where: Sequel.~(reported_family_id: nil),
      name: :error_events_reported_family_idx

    run <<~SQL
      CREATE OR REPLACE FUNCTION error_events_are_immutable() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'error_events rows are immutable (attempted % on %)', TG_OP, OLD.id
          USING ERRCODE = 'restrict_violation';
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER error_events_no_update
        BEFORE UPDATE ON error_events
        FOR EACH ROW EXECUTE FUNCTION error_events_are_immutable();
    SQL
  end

  down do
    run <<~SQL
      DROP TRIGGER IF EXISTS error_events_no_update ON error_events;
      DROP FUNCTION IF EXISTS error_events_are_immutable();
    SQL
    drop_table(:error_events)
  end
end
