# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'
require 'roda'

module Aiaiaiai
  module Errors
    # HTTP entry point for the 4x-errors collector.
    class App < Roda
      plugin :json

      route do |r|
        r.root do
          {
            service: '4x-errors',
            status: 'ok'
          }
        end

        r.get 'health' do
          {
            status: 'ok'
          }
        end
      end
    end
  end
end
