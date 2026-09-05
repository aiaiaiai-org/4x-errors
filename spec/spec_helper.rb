# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "rack/test"
require "aiaiaiai/errors"
require "aiaiaiai/errors/collector"
require "aiaiaiai/errors/collector/production_smoke"

Dir[File.expand_path("support/*.rb", __dir__)].sort.each { |file| require file }

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.include_chain_clauses_in_custom_matcher_descriptions = true }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.warnings = false
  config.order = :random
  Kernel.srand(config.seed)

  config.after { Aiaiaiai::Errors.reset! }
end
