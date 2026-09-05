# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

module Aiaiaiai
  module Errors
    # What an unconfigured SDK reports with.
    #
    # It accepts every call and does nothing, so an application that reports
    # errors behaves identically whether or not a collector was ever set up.
    class NullReporter
      def report(_event) = false

      def relate(_relation) = false

      def flush(**) = true

      def shutdown(**) = true

      def null? = true

      def statistics = { queued: 0, dropped: 0, circuit: :closed, null: true }
    end
  end
end
