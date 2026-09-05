// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { createBrowserReporter } from '../src/index.js';

const UUID = '11111111-1111-4111-8111-111111111111';

function reporter(events, overrides = {}) {
  return createBrowserReporter({
    project: 'nilx-one/web',
    source: 'browser',
    transport: async (event) => events.push(event),
    now: () => new Date('2026-09-05T11:00:00.000Z'),
    randomUUID: () => UUID,
    ...overrides
  });
}

test('normalizes bounded message, full text and tags before transport', async () => {
  const events = [];
  const instance = reporter(events);

  instance.report({
    errorId: 'ai.model.unavailable',
    message: 'm'.repeat(5_000),
    fullText: 'f'.repeat(40_000),
    tags: [...Array.from({ length: 40 }, (_, index) => `tag-${index}`), 'tag-0', 'x'.repeat(300)]
  });
  await Promise.resolve();

  assert.equal(events.length, 1);
  assert.equal(events[0].message.length, 4_096);
  assert.equal(events[0].full_text.length, 32_768);
  assert.equal(events[0].tags.length, 32);
  assert.equal(new Set(events[0].tags).size, 32);
  assert.ok(events[0].tags.every((tag) => tag.length <= 255));
});

test('rejects invalid optional identifiers without escaping into the host', () => {
  const events = [];
  const instance = reporter(events);

  assert.doesNotThrow(() => instance.report({
    errorId: 'ai.model.unavailable',
    familyId: 'not-a-family'
  }));
  assert.equal(events.length, 0);
});

test('rejects an event that still exceeds the request bound', () => {
  const events = [];
  const instance = reporter(events);

  assert.doesNotThrow(() => instance.report({
    errorId: 'ai.model.unavailable',
    severity: 's'.repeat(600_000)
  }));
  assert.equal(events.length, 0);
});

test('invalid oversized project configuration produces a no-op reporter', () => {
  const events = [];
  const instance = reporter(events, { project: 'p'.repeat(256) });

  assert.doesNotThrow(() => instance.report({ errorId: 'ai.model.unavailable' }));
  assert.equal(events.length, 0);
});
