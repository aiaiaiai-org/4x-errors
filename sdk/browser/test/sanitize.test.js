// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { sanitizeContext } from '../src/sanitize.js';

test('redacts sensitive context keys recursively', () => {
  const context = sanitizeContext({
    password: 'secret',
    nested: {
      Authorization: 'Bearer token',
      api_key: 'abc',
      safe: 'visible'
    }
  });

  assert.deepEqual(context, {
    password: '[REDACTED]',
    nested: {
      Authorization: '[REDACTED]',
      api_key: '[REDACTED]',
      safe: 'visible'
    }
  });
});

test('handles circular context without throwing', () => {
  const context = { component: 'map' };
  context.self = context;

  assert.deepEqual(sanitizeContext(context), {
    component: 'map',
    self: '[CIRCULAR]'
  });
});

test('bounds serialized context to the errors.v1 transport limit', () => {
  const context = sanitizeContext({
    first: 'a'.repeat(5_000),
    second: 'b'.repeat(5_000),
    third: 'c'.repeat(5_000),
    fourth: 'd'.repeat(5_000),
    fifth: 'e'.repeat(5_000)
  });
  const bytes = new TextEncoder().encode(JSON.stringify(context)).byteLength;

  assert.ok(bytes <= 16_384);
  assert.equal(context.__truncated__, true);
});

test('non-object context becomes an empty object', () => {
  assert.deepEqual(sanitizeContext('not context'), {});
});
