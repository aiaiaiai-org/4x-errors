# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

namespace :format do
  desc "Rewrite every source into the project's canonical formatting"
  task :fix do
    sh "bundle exec standardrb --fix --format quiet"
  end

  # What CI runs. It rewrites, then asks git whether anything changed, so it
  # needs a clean working tree; locally, `rake format:fix` is the same check.
  desc "Fail if a committed source is not in canonical formatting (needs a clean tree)"
  task :check do
    sh "bundle exec standardrb --fix --format quiet"
    sh "git diff --exit-code"
  end
end

desc "Lint every source"
task :lint do
  sh "bundle exec standardrb --format quiet"
end
