# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require_relative 'protocol'
require_relative 'protocol/validator'
require_relative 'collector/database'
require_relative 'collector/ingest'
require_relative 'collector/store'
require_relative 'collector/token_store'
require_relative 'collector/app'

module Aiaiaiai
  module Errors
    # The server side of errors.v1.
    #
    # It owns the production database and is the only thing that talks to it.
    # Reporters hold a project scoped token and nothing else.
    module Collector
      module_function

      def rack_app(db: Database.connect, tokens: TokenStore.from_env, logger: default_logger)
        store = Store.new(db)
        App.with(
          ingest: Ingest.new(store: store, tokens: tokens),
          database: db,
          logger: logger
        )
      end

      def default_logger
        require 'logger'
        Logger.new($stdout, level: ENV.fetch('LOG_LEVEL', 'info'))
      end
    end
  end
end
