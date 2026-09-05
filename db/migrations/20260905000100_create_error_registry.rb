# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

# The curated side of the model: which failure kinds exist, which families
# exist, and which failure belongs to which family right now.
#
# Membership is revisable. Reclassifying a failure supersedes a membership row
# and inserts a new one; no raw occurrence is ever touched.
Sequel.migration do
  change do
    create_table(:error_families) do
      String :family_id, primary_key: true, null: false
      String :title, null: false
      String :description, text: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:error_definitions) do
      String :error_id, primary_key: true, null: false
      String :title
      String :description, text: true
      String :default_severity
      # True while the registry entry exists only because the collector saw the
      # error id in traffic. Curation flips it to false.
      TrueClass :auto_registered, null: false, default: true
      DateTime :first_seen_at
      DateTime :last_seen_at
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      constraint(:error_definitions_severity_known) do
        {default_severity: [nil, "debug", "info", "warning", "error", "critical"]}
      end
    end

    create_table(:error_family_memberships) do
      primary_key :id, type: :Bignum
      foreign_key :error_id, :error_definitions, type: String, null: false, on_delete: :cascade
      foreign_key :family_id, :error_families, type: String, null: false, on_delete: :cascade
      BigDecimal :confidence, size: [4, 3], null: false, default: 1.0
      column :evidence, "text[]", null: false
      # How the membership came to exist: reported by an SDK, asserted by a
      # human, or derived by a deterministic rule.
      String :source, null: false, default: "reported"
      String :note, text: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :superseded_at
      String :superseded_reason, text: true

      constraint(:memberships_confidence_is_a_probability) { (confidence >= 0) & (confidence <= 1) }
      constraint(:memberships_source_known) { {source: %w[reported curated rule]} }
      constraint(:memberships_have_evidence, Sequel.lit("cardinality(evidence) > 0"))
    end

    # One active membership per (error, family). History stays queryable.
    add_index :error_family_memberships, [:error_id, :family_id],
      unique: true, where: {superseded_at: nil}, name: :error_family_memberships_active_uniq
    add_index :error_family_memberships, [:family_id], where: {superseded_at: nil},
      name: :error_family_memberships_active_family_idx
  end
end
