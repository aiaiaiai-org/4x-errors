# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require_relative 'lib/aiaiaiai/errors/collector'

run Aiaiaiai::Errors::Collector.rack_app
