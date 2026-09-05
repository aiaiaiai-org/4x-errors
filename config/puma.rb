# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

# The collector is IO bound and small. Threads carry the concurrency; workers
# exist so that one wedged process cannot take the endpoint down with it.
threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS", ENV.fetch("PUMA_THREADS", "8")))
threads threads_count, threads_count

port Integer(ENV.fetch("PORT", "8080"))
environment ENV.fetch("RACK_ENV", "production")

workers Integer(ENV.fetch("WEB_CONCURRENCY", "2"))
preload_app!

# Bounded, so a hung request cannot hold a thread forever.
worker_timeout 30

# preload_app! builds the application, and its connection pool, before forking.
# A connection inherited across fork is shared with the parent and cannot be
# used safely, so it is dropped on both sides. Sequel reconnects on demand.
before_fork do
  Sequel::DATABASES.each(&:disconnect) if defined?(Sequel)
end

on_worker_boot do
  Sequel::DATABASES.each(&:disconnect) if defined?(Sequel)
end
