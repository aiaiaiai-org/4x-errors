// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { createBrowserLifecycleTransport } from '../src/lifecycle_transport.js';

test('uses credential-free fetch keepalive for lifecycle delivery', async () => {
  const calls = [];
  const send = createBrowserLifecycleTransport({
    collectorEndpoint: 'https://errors.aiaiaiai.org',
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      return { ok: true };
    }
  });

  const accepted = await send([{ event_id: '11111111-1111-4111-8111-111111111111' }]);

  assert.equal(accepted, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://errors.aiaiaiai.org/v1/browser/events');
  assert.equal(calls[0].init.keepalive, true);
  assert.equal(calls[0].init.credentials, 'omit');
});

test('lifecycle transport is best-effort on network failure', async () => {
  const send = createBrowserLifecycleTransport({
    collectorEndpoint: 'https://errors.aiaiaiai.org',
    fetchImpl: async () => { throw new Error('page closing'); }
  });

  assert.equal(await send([]), false);
});
