# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

namespace :tokens do
  desc "Mint an ingest token for PROJECT (prints the token once; store only the digest)"
  task :issue do
    require_relative "../aiaiaiai/errors/collector"

    project = ENV.fetch("PROJECT")
    issued = Aiaiaiai::Errors::Collector::TokenStore.issue(project)

    puts "project : #{issued[:project]}"
    puts "token   : #{issued[:token]}"
    puts "digest  : #{issued[:digest]}"
    puts
    puts "Give the token to the reporting project. Configure only the digest:"
    puts %(ERRORS_INGEST_TOKENS={"#{issued[:project]}":["#{issued[:digest]}"]})
  end
end
