# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

module Aiaiaiai
  module Errors
    # HTTP behavior for the zero-secret, untrusted browser ingest boundary.
    module BrowserIngest
      MAX_BROWSER_BATCH_SIZE = 50

      def ingest_browser_event(request)
        ensure_browser_configured!(request)
        origin = require_browser_origin!(request)
        apply_browser_cors(origin)
        payload = parse_json(request, read_event_body(request))
        events = normalize_browser_events(request, payload)
        events.each do |event|
          validate_event(request, event)
          authorize_browser_project(request, event, origin)
        end
        persist_browser_events(events, batch: payload.is_a?(Array))
      end

      def browser_preflight(request)
        ensure_browser_configured!(request)
        origin = require_browser_origin!(request)
        apply_browser_cors(origin)
        apply_preflight_headers
        response.status = 204
        ''
      end

      private

      def normalize_browser_events(request, payload)
        return [payload] unless payload.is_a?(Array)

        request.halt json_error(422, 'invalid_batch') if payload.empty? || payload.length > MAX_BROWSER_BATCH_SIZE
        payload
      end

      def persist_browser_events(events, batch:)
        return persist_event(events.fetch(0)) unless batch

        event_ids = self.class.event_store.insert_batch(events)
        response.status = 201
        { event_ids: event_ids }
      end

      def authorize_browser_project(request, event, origin)
        project = event.is_a?(Hash) ? event['project'] : nil
        allowed = self.class.browser_policy.project_origin_allowed?(project, origin)
        request.halt json_error(403, 'project_origin_not_allowed') unless allowed
      end

      def browser_collector_configured?
        self.class.event_store && self.class.browser_policy&.configured?
      end

      def ensure_browser_configured!(request)
        return if browser_collector_configured?

        request.halt json_error(503, 'collector_unconfigured')
      end

      def require_browser_origin!(request)
        origin = request.env['HTTP_ORIGIN']
        request.halt json_error(403, 'origin_not_allowed') unless browser_origin_allowed?(origin)
        origin
      end

      def browser_origin_allowed?(origin)
        origin && self.class.browser_policy.origin_allowed?(origin)
      end

      def apply_browser_cors(origin)
        response['Access-Control-Allow-Origin'] = origin
        response['Vary'] = 'Origin'
      end

      def apply_preflight_headers
        response['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
        response['Access-Control-Allow-Headers'] = 'Content-Type'
        response['Access-Control-Max-Age'] = '600'
      end
    end
  end
end
