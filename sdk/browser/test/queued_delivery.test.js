// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { IDBFactory } from 'fake-indexeddb';
import { createIndexedDbQueue } from '../src/indexeddb_queue.js';
import { createQueuedDelivery } from '../src/queued_delivery.js';

function event(id) {
  return {
    protocol_version: 'errors.v1',
    event_id: id,
    error_id: 'ai.model.unavailable',
    project: 'nilx-one/web',
    source: 'browser',
    severity: 'error',
    message: id,
    full_text: id,
    observed_at: '2026-09-05T11:00:00.000Z',
    context: {},
    tags: [],
    family_id: null,
    caused_by_event_id: null,
    correlation_id: null
  };
}

test('removes an event only after successful delivery', async () => {
  const queue = createIndexedDbQueue({
    indexedDB: new IDBFactory(),
    databaseName: 'delivery-success'
  });
  const delivered = [];
  const delivery = createQueuedDelivery({
    queue,
    send: async (value) => {
      delivered.push(value.event_id);
      return true;
    }
  });
  const value = event('11111111-1111-4111-8111-111111111111');

  await delivery.submit(value);

  assert.deepEqual(delivered, [value.event_id]);
  assert.equal(await queue.size(), 0);
});

test('retains an event when collector delivery fails', async () => {
  const queue = createIndexedDbQueue({
    indexedDB: new IDBFactory(),
    databaseName: 'delivery-failure'
  });
  const delivery = createQueuedDelivery({
    queue,
    send: async () => false
  });
  const value = event('22222222-2222-4222-8222-222222222222');

  await delivery.submit(value);

  assert.equal(await queue.size(), 1);
  assert.deepEqual(await queue.peek(), [value]);
});

test('retains queued events when transport throws', async () => {
  const queue = createIndexedDbQueue({
    indexedDB: new IDBFactory(),
    databaseName: 'delivery-network-error'
  });
  const delivery = createQueuedDelivery({
    queue,
    send: async () => {
      throw new Error('network unavailable');
    }
  });
  const value = event('33333333-3333-4333-8333-333333333333');

  await delivery.submit(value);

  assert.deepEqual(await queue.peek(), [value]);
});

test('uses a one-shot best-effort send when IndexedDB is unavailable', async () => {
  const queue = createIndexedDbQueue({ indexedDB: null });
  const delivered = [];
  const delivery = createQueuedDelivery({
    queue,
    send: async (value) => {
      delivered.push(value.event_id);
      return true;
    }
  });
  const value = event('44444444-4444-4444-8444-444444444444');

  await delivery.submit(value);

  assert.deepEqual(delivered, [value.event_id]);
});

test('acknowledges only the successful prefix of a queued drain', async () => {
  const queue = createIndexedDbQueue({
    indexedDB: new IDBFactory(),
    databaseName: 'delivery-prefix'
  });
  const first = event('55555555-5555-4555-8555-555555555555');
  const second = event('66666666-6666-4666-8666-666666666666');
  await queue.enqueue(first);
  await queue.enqueue(second);

  const attempts = [];
  const delivery = createQueuedDelivery({
    queue,
    send: async (value) => {
      attempts.push(value.event_id);
      return value.event_id === first.event_id;
    }
  });

  await delivery.flush();

  assert.deepEqual(attempts, [first.event_id, second.event_id]);
  assert.deepEqual(await queue.peek(), [second]);
});
