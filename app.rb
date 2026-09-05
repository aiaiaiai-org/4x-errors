# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'json'
require 'roda'
require_relative 'lib/aiaiaiai/errors/browser_ingest_policy'
require_relative 'lib/aiaiaiai/errors/event_store'
require_relative 'lib/aiaiaiai/errors/event_validator'
require_relative 'lib/aiaiaiai/errors/ingest_authenticator'

module Aiaiaiai
  # Shared 4x-errors collector and reporting components.
  module Errors
    # HTTP entry point for the 4x-errors collector.
    class App < Roda
      MAX_REQUEST_BYTES = 524_288

      class << self
        attr_accessor :event_store, :authenticator, :browser_policy
      end

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

        r.post('v1', 'events') { ingest_event(r) }
        r.post('v1', 'browser', 'events') { ingest_browser_event(r) }
        r.on('v1', 'browser', 'events') { r.options { browser_preflight(r) } }
      end

      def ingest_event(request)
        request.halt json_error(503, 'collector_unconfigured') unless trusted_collector_configured?
        event = parse_json(request, read_event_body(request))
        authorize_event(request, event)
        validate_event(request, event)
        persist_event(event)
      end

      def ingest_browser_event(request)
        request.halt json_error(503, 'collector_unconfigured') unless browser_collector_configured?
        origin = request.env['HTTP_ORIGIN']
        request.halt json_error(403, 'origin_not_allowed') unless browser_origin_allowed?(origin)

        set_browser_cors(origin)
        event = parse_json(request, read_event_body(request))
        validate_event(request, event)
        authorize_browser_project(request, event, origin)
        persist_event(event)
      end

      def browser_preflight(request)
        return request.halt json_error(503, 'collector_unconfigured') unless browser_collector_configured?

        origin = request.env['HTTP_ORIGIN']
        request.halt json_error(403, 'origin_not_allowed') unless browser_origin_allowed?(origin)
        set_browser_cors(origin)
        response['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
        response['Access-Control-Allow-Headers'] = 'Content-Type'
        response['Access-Control-Max-Age'] = '600'
        response.status = 204
        ''
      end

      def read_event_body(request)
        body = request.body.read(MAX_REQUEST_BYTES + 1)
        request.halt json_error(413, 'request_too_large') if body.bytesize > MAX_REQUEST_BYTES
        body
      end

      def parse_json(request, body)
        JSON.parse(body)
      rescue JSON::ParserError
        request.halt json_error(400, 'invalid_json')
      end

      def authorize_event(request, event)
        authorization = request.env['HTTP_AUTHORIZATION']
        project = event.is_a?(Hash) ? event['project'] : nil
        authenticated = self.class.authenticator.authenticated?(authorization, project)
        request.halt json_error(401, 'unauthorized') unless authenticated
      end

      def authorize_browser_project(request, event, origin)
        project = event.is_a?(Hash) ? event['project'] : nil
        allowed = self.class.browser_policy.project_origin_allowed?(project, origin)
        request.halt json_error(403, 'project_origin_not_allowed') unless allowed
      end

      def validate_event(request, event)
        errors = EventValidator.new.validate(event)
        request.halt json_error(422, 'invalid_event', errors) unless errors.empty?
      end

      def persist_event(event)
        event_id = self.class.event_store.insert(event)
        response.status = 201
        { event_id: event_id }
      end

      def trusted_collector_configured?
        self.class.event_store && self.class.authenticator
      end

      def browser_collector_configured?
        self.class.event_store && self.class.browser_policy&.configured?
      end

      def browser_origin_allowed?(origin)
        origin && self.class.browser_policy.origin_allowed?(origin)
      end

      def set_browser_cors(origin)
        response['Access-Control-Allow-Origin'] = origin
        response['Vary'] = 'Origin'
      end

      def json_error(status, code, details = nil)
        payload = { error: code }
        payload[:details] = details if details
        [status, { 'content-type' => 'application/json' }, [JSON.generate(payload)]]
      end
    end

    App.event_store = EventStore.connect(ENV.fetch('DATABASE_URL')) if ENV.key?('DATABASE_URL')
    if ENV.key?('INGEST_TOKEN_DIGESTS')
      App.authenticator = IngestAuthenticator.from_json(ENV.fetch('INGEST_TOKEN_DIGESTS'))
    end
    if ENV.key?('BROWSER_INGEST_ORIGINS')
      App.browser_policy = BrowserIngestPolicy.from_json(ENV.fetch('BROWSER_INGEST_ORIGINS'))
    end
  end
end
