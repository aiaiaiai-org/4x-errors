# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require_relative "lib/aiaiaiai/errors/collector"

run Aiaiaiai::Errors::Collector.rack_app
