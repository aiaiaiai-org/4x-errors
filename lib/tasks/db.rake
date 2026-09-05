# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

namespace :db do
  desc 'Apply every pending migration'
  task :migrate do
    with_database do |db|
      Aiaiaiai::Errors::Collector::Database.migrate(db)
      puts "migrations applied to #{Aiaiaiai::Errors::Collector::Database.redact}"
    end
  end

  desc 'Roll the schema back to VERSION (a migration timestamp, or 0 for empty)'
  task :rollback do
    target = Integer(ENV.fetch('VERSION'))
    with_database do |db|
      Aiaiaiai::Errors::Collector::Database.migrate(db, target: target)
      puts "schema rolled back to #{target}"
    end
  end

  desc 'Exit non-zero unless every migration has been applied'
  task :current do
    with_database do |db|
      if Aiaiaiai::Errors::Collector::Database.migrations_current?(db)
        puts 'migrations are current'
      else
        warn 'migrations are pending'
        exit 1
      end
    end
  end

  def with_database
    require_relative '../aiaiaiai/errors/collector'
    db = Aiaiaiai::Errors::Collector::Database.connect
    yield db
  ensure
    db&.disconnect
  end
end
