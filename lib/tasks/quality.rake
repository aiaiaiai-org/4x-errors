# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

desc 'Check formatting and lint, as CI does'
task :lint do
  sh 'bundle exec rubocop'
end

namespace :lint do
  desc 'Correct everything RuboCop can correct on its own'
  task :fix do
    sh 'bundle exec rubocop --autocorrect'
  end
end
