// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { IDBFactory } from 'fake-indexeddb';
import { createIndexedDbQueue } from '../src/indexeddb_queue.js';
import { createQueuedDelivery } from '../src/queued_delivery.js';

const oversized = {
  protocol_version: 'errors.v1',
  event_id: '99999999-9999-4999-8999-999999999999',
  error_id: 'ai.model.unavailable',
  project: 'nilx-one/web',
  source: 'browser',
  severity: 'error',
  message: 'oversized',
  full_text: 'x'.repeat(2_000),
  observed_at: '2026-09-05T11:00:00.000Z',
  context: {},
  tags: [],
  family_id: null,
  caused_by_event_id: null,
  correlation_id: null
};

test('does not send a queued event that exceeds the request byte bound', async () => {
  const queue = createIndexedDbQueue({
    indexedDB: new IDBFactory(),
    databaseName: 'oversized-request'
  });
  await queue.enqueue(oversized);
  let attempts = 0;
  const delivery = createQueuedDelivery({
    queue,
    maxRequestBytes: 500,
    send: async () => {
      attempts += 1;
      return true;
    }
  });

  await delivery.flush();

  assert.equal(attempts, 0);
  assert.deepEqual(await queue.peek(), [oversized]);
});
