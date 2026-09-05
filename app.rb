# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

# frozen_string_literal: true

require "json"
require "roda"

module Aiaiaiai
  module Errors
    class App < Roda
      plugin :json

      route do |r|
        r.root do
          {
            service: "4x-errors",
            status: "ok"
          }
        end

        r.get "health" do
          {
            status: "ok"
          }
        end
      end
    end
  end
end
