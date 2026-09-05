# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

Sequel.migration do
  up do
    create_table(:error_events) do
      column :event_id, :uuid, primary_key: true, null: false
      String :protocol_version, null: false, size: 32
      String :error_id, null: false, size: 255
      String :project, null: false, size: 255
      String :source, null: false, size: 255
      String :severity, null: false, size: 64
      String :message, null: false, text: true
      String :full_text, null: false, text: true
      column :observed_at, 'timestamptz', null: false
      column :context, :jsonb, null: false
      column :tags, :jsonb, null: false
      String :family_id, null: true, size: 255
      column :caused_by_event_id, :uuid, null: true
      String :correlation_id, null: true, size: 255
      column :received_at, 'timestamptz', null: false, default: Sequel::CURRENT_TIMESTAMP

      index :error_id
      index :project
      index :observed_at
      index :family_id
      index :correlation_id
    end

    run 'ALTER TABLE error_events ENABLE ROW LEVEL SECURITY'
    run <<~SQL
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
          REVOKE ALL ON TABLE error_events FROM anon;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
          REVOKE ALL ON TABLE error_events FROM authenticated;
        END IF;
      END
      $$;
    SQL
  end

  down do
    drop_table(:error_events)
  end
end
