# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

namespace :smoke do
  desc 'Validate the production database from a protected job (writes and removes one smoke record)'
  task :production do
    require_relative '../aiaiaiai/errors/collector'
    require_relative '../aiaiaiai/errors/collector/production_smoke'

    db = Aiaiaiai::Errors::Collector::Database.connect
    run_id = ENV['GITHUB_RUN_ID'] || SecureRandom.uuid
    passed = Aiaiaiai::Errors::Collector::ProductionSmoke.new(db: db, run_id: run_id).call
    db.disconnect

    exit(passed ? 0 : 1)
  end
end
