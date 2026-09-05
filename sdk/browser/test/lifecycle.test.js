// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { attachLifecycleDelivery } from '../src/lifecycle.js';

function target() {
  const listeners = new Map();
  return {
    addEventListener(type, listener) { listeners.set(type, listener); },
    removeEventListener(type, listener) {
      if (listeners.get(type) === listener) listeners.delete(type);
    },
    dispatch(type) { listeners.get(type)?.(); },
    has(type) { return listeners.has(type); }
  };
}

test('pagehide triggers one best-effort lifecycle flush', async () => {
  const runtimeTarget = target();
  const payloads = [];
  const delivery = {
    async lifecycleFlush(sendLifecycle) {
      await sendLifecycle([{ event_id: '11111111-1111-4111-8111-111111111111' }]);
    }
  };
  const detach = attachLifecycleDelivery({
    delivery,
    target: runtimeTarget,
    sendLifecycle: async (payload) => {
      payloads.push(payload);
      return true;
    }
  });

  runtimeTarget.dispatch('pagehide');
  await Promise.resolve();
  assert.equal(payloads.length, 1);

  detach();
  assert.equal(runtimeTarget.has('pagehide'), false);
});

test('lifecycle flush failures never escape page shutdown', () => {
  const runtimeTarget = target();
  attachLifecycleDelivery({
    target: runtimeTarget,
    sendLifecycle: async () => false,
    delivery: { lifecycleFlush() { throw new Error('failed'); } }
  });

  assert.doesNotThrow(() => runtimeTarget.dispatch('pagehide'));
});
