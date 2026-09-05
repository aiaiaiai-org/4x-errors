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

test('opens after repeated exhausted deliveries and resumes after cooldown', async () => {
  const queue = createIndexedDbQueue({
    indexedDB: new IDBFactory(),
    databaseName: 'circuit-breaker'
  });
  let clock = 1_000;
  let attempts = 0;
  const delivery = createQueuedDelivery({
    queue,
    send: async () => {
      attempts += 1;
      return false;
    },
    maxAttempts: 1,
    failureThreshold: 2,
    cooldownMs: 500,
    nowMs: () => clock
  });

  await delivery.submit(event('11111111-1111-4111-8111-111111111111'));
  await delivery.submit(event('22222222-2222-4222-8222-222222222222'));
  assert.equal(attempts, 2);

  await delivery.submit(event('33333333-3333-4333-8333-333333333333'));
  assert.equal(attempts, 2);
  assert.equal(await queue.size(), 3);

  clock += 500;
  await delivery.flush();
  assert.equal(attempts, 3);
  assert.equal(await queue.size(), 3);
});

test('successful delivery resets consecutive failure tracking', async () => {
  const queue = createIndexedDbQueue({
    indexedDB: new IDBFactory(),
    databaseName: 'circuit-reset'
  });
  const outcomes = [false, true, false, true];
  let attempts = 0;
  const delivery = createQueuedDelivery({
    queue,
    send: async () => {
      attempts += 1;
      return outcomes.shift() ?? true;
    },
    maxAttempts: 1,
    failureThreshold: 2,
    cooldownMs: 10_000,
    nowMs: () => 1_000
  });

  await delivery.submit(event('44444444-4444-4444-8444-444444444444'));
  await delivery.flush();
  await delivery.submit(event('55555555-5555-4555-8555-555555555555'));
  await delivery.flush();

  assert.equal(attempts, 4);
  assert.equal(await queue.size(), 0);
});
