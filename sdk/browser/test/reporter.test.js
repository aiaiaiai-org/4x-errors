// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { createBrowserReporter } from '../src/index.js';

test('emits one errors.v1 event through the injected transport', async () => {
  const events = [];
  const reporter = createBrowserReporter({
    project: 'nilx-one/web',
    source: 'browser',
    transport: async (event) => events.push(event),
    now: () => new Date('2026-09-05T11:00:00.000Z'),
    randomUUID: () => '11111111-1111-4111-8111-111111111111'
  });

  reporter.report({
    errorId: 'ai.model.unavailable',
    message: 'Model unavailable',
    context: { model: 'local' },
    tags: ['web']
  });
  await Promise.resolve();

  assert.equal(events.length, 1);
  assert.deepEqual(events[0], {
    protocol_version: 'errors.v1',
    event_id: '11111111-1111-4111-8111-111111111111',
    error_id: 'ai.model.unavailable',
    project: 'nilx-one/web',
    source: 'browser',
    severity: 'error',
    message: 'Model unavailable',
    full_text: 'Model unavailable',
    observed_at: '2026-09-05T11:00:00.000Z',
    context: { model: 'local' },
    tags: ['web'],
    family_id: null,
    caused_by_event_id: null,
    correlation_id: null
  });
});

test('invalid configuration produces a no-op reporter', () => {
  const reporter = createBrowserReporter({ project: 'nilx-one/web' });

  assert.doesNotThrow(() => reporter.report({ errorId: 'ai.model.unavailable' }));
});

test('report never exposes transport rejection to the host', async () => {
  const reporter = createBrowserReporter({
    project: 'nilx-one/web',
    source: 'browser',
    transport: async () => {
      throw new Error('collector unavailable');
    },
    randomUUID: () => '11111111-1111-4111-8111-111111111111'
  });

  assert.doesNotThrow(() => reporter.report({ errorId: 'ai.model.unavailable' }));
  await Promise.resolve();
});

test('malformed reports are swallowed instead of reaching host logic', () => {
  let called = false;
  const reporter = createBrowserReporter({
    project: 'nilx-one/web',
    source: 'browser',
    transport: () => {
      called = true;
    }
  });

  assert.doesNotThrow(() => reporter.report({ errorId: 'invalid id' }));
  assert.equal(called, false);
});
