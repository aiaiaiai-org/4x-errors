// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import assert from 'node:assert/strict';
import test from 'node:test';
import { attachGlobalErrorCapture } from '../src/global_capture.js';

function runtimeTarget() {
  const listeners = new Map();
  return {
    addEventListener(type, listener) { listeners.set(type, listener); },
    removeEventListener(type, listener) {
      if (listeners.get(type) === listener) listeners.delete(type);
    },
    dispatch(type, event) { listeners.get(type)?.(event); },
    has(type) { return listeners.has(type); }
  };
}

test('captures window errors with stable semantic identifiers', () => {
  const target = runtimeTarget();
  const reports = [];
  const detach = attachGlobalErrorCapture({ reporter: { report: (input) => reports.push(input) }, target });

  target.dispatch('error', {
    message: 'boom',
    filename: '/app.js',
    lineno: 12,
    colno: 7,
    error: { stack: 'Error: boom\n at app.js:12:7' }
  });

  assert.equal(reports.length, 1);
  assert.equal(reports[0].errorId, 'browser.runtime.unhandled_error');
  assert.equal(reports[0].message, 'boom');
  assert.deepEqual(reports[0].context, { filename: '/app.js', line: 12, column: 7 });

  detach();
  assert.equal(target.has('error'), false);
});

test('captures unhandled promise rejections', () => {
  const target = runtimeTarget();
  const reports = [];
  attachGlobalErrorCapture({ reporter: { report: (input) => reports.push(input) }, target });

  target.dispatch('unhandledrejection', { reason: new Error('rejected') });

  assert.equal(reports.length, 1);
  assert.equal(reports[0].errorId, 'browser.promise.unhandled_rejection');
  assert.equal(reports[0].message, 'rejected');
});

test('recursion guard suppresses nested global capture', () => {
  const target = runtimeTarget();
  let reports = 0;
  attachGlobalErrorCapture({
    target,
    reporter: {
      report() {
        reports += 1;
        target.dispatch('error', { message: 'nested' });
      }
    }
  });

  target.dispatch('error', { message: 'outer' });
  assert.equal(reports, 1);
});

test('capture failures never escape into host runtime', () => {
  const target = runtimeTarget();
  attachGlobalErrorCapture({ reporter: { report() { throw new Error('report failed'); } }, target });

  assert.doesNotThrow(() => target.dispatch('error', { message: 'boom' }));
  assert.doesNotThrow(() => target.dispatch('unhandledrejection', { reason: 'rejected' }));
});
