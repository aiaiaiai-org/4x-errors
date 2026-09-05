// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { IDBFactory } from 'fake-indexeddb';
import { createIndexedDbQueue } from '../src/indexeddb_queue.js';
import { createQueuedDelivery } from '../src/queued_delivery.js';

function event(id, overrides = {}) {
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
    correlation_id: null,
    ...overrides
  };
}

function queue(name) {
  return createIndexedDbQueue({ indexedDB: new IDBFactory(), databaseName: name });
}

test('removes a durable batch only after successful delivery', async () => {
  const durableQueue = queue('delivery-success');
  const first = event('11111111-1111-4111-8111-111111111111');
  const second = event('22222222-2222-4222-8222-222222222222');
  await durableQueue.enqueue(first);
  await durableQueue.enqueue(second);
  const payloads = [];
  const delivery = createQueuedDelivery({
    queue: durableQueue,
    send: async (payload) => {
      payloads.push(payload);
      return true;
    }
  });

  await delivery.flush();

  assert.deepEqual(payloads, [[first, second]]);
  assert.equal(await durableQueue.size(), 0);
});

test('retries a durable batch with exponential jittered backoff', async () => {
  const durableQueue = queue('delivery-retry');
  const attempts = [];
  const delays = [];
  const value = event('33333333-3333-4333-8333-333333333333');
  const delivery = createQueuedDelivery({
    queue: durableQueue,
    send: async (payload) => {
      attempts.push(payload);
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
  assert.deepEqual(attempts[0], [value]);
  assert.deepEqual(delays, [100, 200]);
  assert.equal(await durableQueue.size(), 0);
});

test('retains the whole batch after the retry budget is exhausted', async () => {
  const durableQueue = queue('delivery-failure');
  const first = event('44444444-4444-4444-8444-444444444444');
  const second = event('55555555-5555-4555-8555-555555555555');
  await durableQueue.enqueue(first);
  await durableQueue.enqueue(second);
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

  await delivery.flush();

  assert.equal(attempts, 3);
  assert.deepEqual(await durableQueue.peek(), [first, second]);
});

test('keeps unavailable IndexedDB fallback one-shot and single-event', async () => {
  const unavailableQueue = createIndexedDbQueue({ indexedDB: null });
  const payloads = [];
  const delivery = createQueuedDelivery({
    queue: unavailableQueue,
    send: async (payload) => {
      payloads.push(payload);
      return false;
    },
    maxAttempts: 5,
    sleep: async () => undefined
  });
  const value = event('66666666-6666-4666-8666-666666666666');

  await delivery.submit(value);

  assert.deepEqual(payloads, [value]);
});

test('limits one network batch to 50 events', async () => {
  const durableQueue = queue('delivery-count-limit');
  const events = Array.from({ length: 51 }, (_, index) => event(`event-${index}`));
  for (const value of events) await durableQueue.enqueue(value);
  const payloads = [];
  const delivery = createQueuedDelivery({
    queue: durableQueue,
    send: async (payload) => {
      payloads.push(payload);
      return true;
    }
  });

  await delivery.flush();

  assert.equal(payloads[0].length, 50);
  assert.deepEqual(await durableQueue.peek(), [events[50]]);
});

test('splits a batch before the configured serialized byte limit', async () => {
  const durableQueue = queue('delivery-byte-limit');
  const first = event('77777777-7777-4777-8777-777777777777', { full_text: 'a'.repeat(400) });
  const second = event('88888888-8888-4888-8888-888888888888', { full_text: 'b'.repeat(400) });
  await durableQueue.enqueue(first);
  await durableQueue.enqueue(second);
  const payloads = [];
  const oneEventBytes = new TextEncoder().encode(JSON.stringify([first])).byteLength;
  const delivery = createQueuedDelivery({
    queue: durableQueue,
    maxRequestBytes: oneEventBytes + 10,
    send: async (payload) => {
      payloads.push(payload);
      return true;
    }
  });

  await delivery.flush();

  assert.deepEqual(payloads, [[first]]);
  assert.deepEqual(await durableQueue.peek(), [second]);
});
