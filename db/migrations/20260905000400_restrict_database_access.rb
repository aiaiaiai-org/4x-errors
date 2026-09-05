# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

# Database credentials are server side only. No browser, and no Supabase
# client role, ever reaches these tables.
#
# Row level security is enabled with no permissive policy: the collector
# connects as the table owner and is unaffected, while every other role is
# denied even if a grant is added by accident later. The Supabase browser roles
# are additionally stripped of all privileges, present or future.
tables = %i[
  error_events
  error_definitions
  error_families
  error_family_memberships
  error_relations
  event_relations
].freeze

browser_roles = %w[anon authenticated].freeze

Sequel.migration do
  up do
    tables.each do |table|
      run "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;"
      run "REVOKE ALL ON TABLE #{table} FROM PUBLIC;"
    end

    browser_roles.each do |role|
      run <<~SQL
        DO $$
        BEGIN
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '#{role}') THEN
            REVOKE ALL ON ALL TABLES IN SCHEMA public FROM #{role};
            REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM #{role};
            REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM #{role};
            REVOKE USAGE ON SCHEMA public FROM #{role};
            ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM #{role};
            ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM #{role};
          END IF;
        END
        $$;
      SQL
    end
  end

  down do
    tables.each { |table| run "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY;" }
    # Browser role privileges are intentionally not restored: granting database
    # access to a browser role is never a rollback step.
  end
end
