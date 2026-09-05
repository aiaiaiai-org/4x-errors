// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { IDBFactory } from 'fake-indexeddb';
import { createIndexedDbQueue } from '../src/indexeddb_queue.js';

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

test('persists queued events across queue instances', async () => {
  const indexedDB = new IDBFactory();
  const first = createIndexedDbQueue({ indexedDB, databaseName: 'persist' });
  await first.enqueue(event('11111111-1111-4111-8111-111111111111'));

  const second = createIndexedDbQueue({ indexedDB, databaseName: 'persist' });
  assert.equal(await second.size(), 1);
  assert.deepEqual(await second.peek(), [event('11111111-1111-4111-8111-111111111111')]);
});

test('drops the oldest event when the bounded queue overflows', async () => {
  const queue = createIndexedDbQueue({
    indexedDB: new IDBFactory(),
    databaseName: 'bounded',
    maxEntries: 2
  });
  const first = event('11111111-1111-4111-8111-111111111111');
  const second = event('22222222-2222-4222-8222-222222222222');
  const third = event('33333333-3333-4333-8333-333333333333');

  await queue.enqueue(first);
  await queue.enqueue(second);
  await queue.enqueue(third);

  assert.equal(await queue.size(), 2);
  assert.deepEqual(await queue.peek(), [second, third]);
});

test('removes acknowledged events by event id', async () => {
  const queue = createIndexedDbQueue({
    indexedDB: new IDBFactory(),
    databaseName: 'remove'
  });
  const first = event('11111111-1111-4111-8111-111111111111');
  const second = event('22222222-2222-4222-8222-222222222222');
  await queue.enqueue(first);
  await queue.enqueue(second);

  await queue.remove([first.event_id]);

  assert.deepEqual(await queue.peek(), [second]);
});

test('degrades to an empty no-op queue when IndexedDB is unavailable', async () => {
  const queue = createIndexedDbQueue({ indexedDB: null });

  await assert.doesNotReject(queue.enqueue(event('11111111-1111-4111-8111-111111111111')));
  assert.equal(await queue.size(), 0);
  assert.deepEqual(await queue.peek(), []);
});
