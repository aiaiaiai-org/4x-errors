# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

module Aiaiaiai
  module Errors
    # Reporting about reporting is never useful and is sometimes fatal.
    #
    # Any call made while this thread is already inside the reporter is
    # ignored, which also silences the delivery thread: a failure raised while
    # sending cannot be sent.
    module RecursionGuard
      KEY = :aiaiaiai_errors_reporting

      module_function

      def active?
        !Thread.current[KEY].nil?
      end

      # Yields unless this thread is already reporting; returns nil if it is.
      def guard
        return nil if active?

        Thread.current[KEY] = true
        begin
          yield
        ensure
          Thread.current[KEY] = nil
        end
      end

      # Marks the current thread as permanently internal.
      def claim_thread
        Thread.current[KEY] = true
      end
    end
  end
end
