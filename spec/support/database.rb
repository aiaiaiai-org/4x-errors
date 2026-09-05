# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

# The integration database.
#
# Examples tagged :database run against a real, empty PostgreSQL. There is no
# in-memory substitute: the schema carries constraints, partial unique indexes,
# an immutability trigger and a recursive query, and none of those are worth
# testing against a fake.
module TestDatabase
  DEFAULT_URL = "postgres://postgres@127.0.0.1:5432/4x_errors_test"

  TABLES = %i[
    event_relations
    error_relations
    error_events
    error_family_memberships
    error_definitions
    error_families
  ].freeze

  module_function

  def url
    ENV["TEST_DATABASE_URL"] || DEFAULT_URL
  end

  def connection
    @connection ||= begin
      db = Aiaiaiai::Errors::Collector::Database.connect(url)
      Aiaiaiai::Errors::Collector::Database.migrate(db)
      db
    end
  rescue Sequel::DatabaseConnectionError => error
    abort <<~MESSAGE
      Cannot reach the test database at #{Aiaiaiai::Errors::Collector::Database.redact(url)}.

      Start one and point TEST_DATABASE_URL at it, for example:
        docker run --rm -e POSTGRES_HOST_AUTH_METHOD=trust -p 5432:5432 postgres:17

      #{error.class}
    MESSAGE
  end

  def clean
    connection.run("TRUNCATE #{TABLES.join(", ")} RESTART IDENTITY CASCADE")
  end
end

RSpec.configure do |config|
  # The connection is opened and migrated on first use, so a run with no
  # database examples needs no database.
  config.before(:each, :database) { TestDatabase.clean }
end
