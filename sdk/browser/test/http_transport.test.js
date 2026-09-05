// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { createBrowserHttpTransport } from '../src/http_transport.js';

const event = {
  protocol_version: 'errors.v1',
  event_id: '11111111-1111-4111-8111-111111111111',
  error_id: 'ai.model.unavailable',
  project: 'nilx-one/web',
  source: 'browser',
  severity: 'error',
  message: 'Model unavailable',
  full_text: 'Model unavailable',
  observed_at: '2026-09-05T11:00:00.000Z',
  context: {},
  tags: [],
  family_id: null,
  caused_by_event_id: null,
  correlation_id: null
};

test('posts errors.v1 to the canonical zero-secret browser endpoint', async () => {
  const requests = [];
  const send = createBrowserHttpTransport({
    collectorEndpoint: 'https://errors.aiaiaiai.org',
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return { ok: true };
    }
  });

  assert.equal(await send(event), true);
  assert.equal(requests[0].url, 'https://errors.aiaiaiai.org/v1/browser/events');
  assert.equal(requests[0].options.method, 'POST');
  assert.equal(requests[0].options.credentials, 'omit');
  assert.deepEqual(JSON.parse(requests[0].options.body), event);
});

test('does not duplicate the canonical path when a full ingest URL is supplied', async () => {
  let requestedUrl;
  const send = createBrowserHttpTransport({
    collectorEndpoint: 'https://errors.aiaiaiai.org/v1/browser/events',
    fetchImpl: async (url) => {
      requestedUrl = url;
      return { ok: true };
    }
  });

  await send(event);

  assert.equal(requestedUrl, 'https://errors.aiaiaiai.org/v1/browser/events');
});

test('treats non-2xx collector responses as failed delivery', async () => {
  const send = createBrowserHttpTransport({
    collectorEndpoint: 'https://errors.aiaiaiai.org',
    fetchImpl: async () => ({ ok: false })
  });

  assert.equal(await send(event), false);
});

test('rejects malformed or unsupported collector endpoints', () => {
  assert.equal(createBrowserHttpTransport({ collectorEndpoint: 'not a url', fetchImpl: async () => ({ ok: true }) }), null);
  assert.equal(createBrowserHttpTransport({ collectorEndpoint: 'ftp://errors.example', fetchImpl: async () => ({ ok: true }) }), null);
});
