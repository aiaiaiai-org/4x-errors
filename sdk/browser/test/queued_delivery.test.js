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

function queue(name) {
  return createIndexedDbQueue({ indexedDB: new IDBFactory(), databaseName: name });
}

test('removes an event only after successful delivery', async () => {
  const durableQueue = queue('delivery-success');
  const delivered = [];
  const delivery = createQueuedDelivery({
    queue: durableQueue,
    send: async (value) => {
      delivered.push(value.event_id);
      return true;
    }
  });
  const value = event('11111111-1111-4111-8111-111111111111');

  await delivery.submit(value);

  assert.deepEqual(delivered, [value.event_id]);
  assert.equal(await durableQueue.size(), 0);
});

test('retries a durable queued event with exponential jittered backoff', async () => {
  const durableQueue = queue('delivery-retry');
  const attempts = [];
  const delays = [];
  const value = event('22222222-2222-4222-8222-222222222222');
  const delivery = createQueuedDelivery({
    queue: durableQueue,
    send: async () => {
      attempts.push(value.event_id);
      return attempts.length === 3;
    },
    maxAttempts: 3,
    baseDelayMs: 200,
    maxDelayMs: 1_000,
    random: () => 0.5,
    sleep: async (delayMs) => delays.push(delayMs)
  });

  await delivery.submit(value);

  assert.equal(attempts.length, 3);
  assert.deepEqual(delays, [100, 200]);
  assert.equal(await durableQueue.size(), 0);
});

test('retains an event after the bounded retry budget is exhausted', async () => {
  const durableQueue = queue('delivery-failure');
  let attempts = 0;
  const delivery = createQueuedDelivery({
    queue: durableQueue,
    send: async () => {
      attempts += 1;
      return false;
    },
    maxAttempts: 3,
    sleep: async () => undefined
  });
  const value = event('33333333-3333-4333-8333-333333333333');

  await delivery.submit(value);

  assert.equal(attempts, 3);
  assert.deepEqual(await durableQueue.peek(), [value]);
});

test('retains queued events when transport throws', async () => {
  const durableQueue = queue('delivery-network-error');
  const delivery = createQueuedDelivery({
    queue: durableQueue,
    send: async () => {
      throw new Error('network unavailable');
    },
    maxAttempts: 2,
    sleep: async () => undefined
  });
  const value = event('44444444-4444-4444-8444-444444444444');

  await delivery.submit(value);

  assert.deepEqual(await durableQueue.peek(), [value]);
});

test('keeps unavailable IndexedDB fallback one-shot and best-effort', async () => {
  const unavailableQueue = createIndexedDbQueue({ indexedDB: null });
  let attempts = 0;
  const delivery = createQueuedDelivery({
    queue: unavailableQueue,
    send: async () => {
      attempts += 1;
      return false;
    },
    maxAttempts: 5,
    sleep: async () => undefined
  });
  const value = event('55555555-5555-4555-8555-555555555555');

  await delivery.submit(value);

  assert.equal(attempts, 1);
});

test('acknowledges only the successful prefix of a queued drain', async () => {
  const durableQueue = queue('delivery-prefix');
  const first = event('66666666-6666-4666-8666-666666666666');
  const second = event('77777777-7777-4777-8777-777777777777');
  await durableQueue.enqueue(first);
  await durableQueue.enqueue(second);

  const attempts = [];
  const delivery = createQueuedDelivery({
    queue: durableQueue,
    send: async (value) => {
      attempts.push(value.event_id);
      return value.event_id === first.event_id;
    },
    maxAttempts: 1
  });

  await delivery.flush();

  assert.deepEqual(attempts, [first.event_id, second.event_id]);
  assert.deepEqual(await durableQueue.peek(), [second]);
});
