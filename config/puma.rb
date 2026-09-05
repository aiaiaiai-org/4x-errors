# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

# The collector is IO bound and small, so threads carry the concurrency.
threads_count = Integer(ENV.fetch('PUMA_THREADS', '8'))
threads threads_count, threads_count

port Integer(ENV.fetch('PORT', '9292'))
environment ENV.fetch('RACK_ENV', 'production')

# Single mode by default. Raise WEB_CONCURRENCY to run workers; the hooks below
# make that safe.
workers Integer(ENV.fetch('WEB_CONCURRENCY', '0'))
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
