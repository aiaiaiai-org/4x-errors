// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { IDBFactory } from 'fake-indexeddb';
import { createIndexedDbQueue } from '../src/indexeddb_queue.js';
import { createQueuedDelivery } from '../src/queued_delivery.js';

const EVENT = {
  protocol_version: 'errors.v1',
  event_id: '11111111-1111-4111-8111-111111111111',
  error_id: 'browser.runtime.unhandled_error',
  project: 'nilx-one/web',
  source: 'browser',
  severity: 'error',
  message: 'boom',
  full_text: 'boom',
  observed_at: '2026-09-05T12:00:00.000Z',
  context: {},
  tags: [],
  family_id: null,
  caused_by_event_id: null,
  correlation_id: null
};

test('lifecycle snapshot never removes durable events without confirmed normal delivery', async () => {
  const queue = createIndexedDbQueue({
    indexedDB: new IDBFactory(),
    databaseName: 'lifecycle-retains-queue'
  });
  await queue.enqueue(EVENT);
  const payloads = [];
  const delivery = createQueuedDelivery({ queue, send: async () => false });

  await delivery.lifecycleFlush(async (payload) => {
    payloads.push(payload);
    return true;
  });

  assert.deepEqual(payloads, [[EVENT]]);
  assert.deepEqual(await queue.peek(), [EVENT]);
});
