// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { attachDeliveryRecovery } from '../src/recovery.js';

function target() {
  const listeners = new Map();
  return {
    addEventListener(type, listener) {
      listeners.set(type, listener);
    },
    removeEventListener(type, listener) {
      if (listeners.get(type) === listener) listeners.delete(type);
    },
    dispatch(type) {
      listeners.get(type)?.();
    },
    has(type) {
      return listeners.has(type);
    }
  };
}

test('flushes once on startup and again when connectivity returns', async () => {
  const runtimeTarget = target();
  let flushes = 0;
  const delivery = { async flush() { flushes += 1; } };

  const detach = attachDeliveryRecovery({ delivery, target: runtimeTarget });
  await Promise.resolve();
  assert.equal(flushes, 1);

  runtimeTarget.dispatch('online');
  await Promise.resolve();
  assert.equal(flushes, 2);

  detach();
  assert.equal(runtimeTarget.has('online'), false);
});

test('recovery failures never escape into host logic', async () => {
  const runtimeTarget = target();
  const delivery = { async flush() { throw new Error('collector unavailable'); } };

  assert.doesNotThrow(() => attachDeliveryRecovery({ delivery, target: runtimeTarget }));
  await Promise.resolve();
  assert.doesNotThrow(() => runtimeTarget.dispatch('online'));
  await Promise.resolve();
});
