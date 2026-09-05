// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { createEventDeduplicator } from '../src/deduplicator.js';

function event(observedAt, overrides = {}) {
  return {
    protocol_version: 'errors.v1',
    event_id: overrides.event_id ?? crypto.randomUUID(),
    error_id: 'ai.model.unavailable',
    project: 'nilx-one/web',
    source: 'browser',
    severity: 'error',
    message: 'Model unavailable',
    full_text: 'Model unavailable',
    observed_at: observedAt,
    context: { model: 'local', nested: { b: 2, a: 1 } },
    tags: ['web'],
    family_id: null,
    caused_by_event_id: null,
    correlation_id: null,
    ...overrides
  };
}

test('drops identical events inside the deduplication window despite unique event ids', () => {
  const deduplicator = createEventDeduplicator({ windowMs: 5_000 });
  const first = event('2026-09-05T11:00:00.000Z');
  const duplicate = event('2026-09-05T11:00:01.000Z');

  assert.equal(deduplicator.accept(first), true);
  assert.equal(deduplicator.accept(duplicate), false);
});

test('accepts the same semantic event after the window expires', () => {
  const deduplicator = createEventDeduplicator({ windowMs: 1_000 });

  assert.equal(deduplicator.accept(event('2026-09-05T11:00:00.000Z')), true);
  assert.equal(deduplicator.accept(event('2026-09-05T11:00:01.001Z')), true);
});

test('keeps distinct sanitized payloads distinct and ignores object key order', () => {
  const deduplicator = createEventDeduplicator();
  const first = event('2026-09-05T11:00:00.000Z');
  const reordered = event('2026-09-05T11:00:01.000Z', {
    context: { nested: { a: 1, b: 2 }, model: 'local' }
  });
  const different = event('2026-09-05T11:00:02.000Z', { message: 'Another failure' });

  assert.equal(deduplicator.accept(first), true);
  assert.equal(deduplicator.accept(reordered), false);
  assert.equal(deduplicator.accept(different), true);
});

test('bounds retained fingerprints', () => {
  const deduplicator = createEventDeduplicator({ maxEntries: 2, windowMs: 60_000 });
  const first = event('2026-09-05T11:00:00.000Z', { message: 'first' });
  const second = event('2026-09-05T11:00:01.000Z', { message: 'second' });
  const third = event('2026-09-05T11:00:02.000Z', { message: 'third' });

  assert.equal(deduplicator.accept(first), true);
  assert.equal(deduplicator.accept(second), true);
  assert.equal(deduplicator.accept(third), true);
  assert.equal(deduplicator.accept(first), true);
});
