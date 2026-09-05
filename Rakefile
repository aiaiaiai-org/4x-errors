# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'rake'

Dir[File.expand_path('lib/tasks/*.rake', __dir__)].each { |task| load task }

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  # RSpec is a development dependency; production images do not carry it.
end

desc 'Everything CI runs: formatting, lint and the whole test suite'
task ci: %i[lint spec]

task default: :ci
