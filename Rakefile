# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "rake"

Dir[File.expand_path("lib/tasks/*.rake", __dir__)].sort.each { |task| load task }

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  # RSpec is a development dependency; production images do not carry it.
end

desc "Lint and the whole test suite"
task ci: [:lint, :spec]

task default: :ci
