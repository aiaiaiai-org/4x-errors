// © 2026 aiaiaiai · aiaiaiai.org
// SPDX-License-Identifier: Apache-2.0

import assert from 'node:assert/strict';
import test from 'node:test';
import { verifyBrowserRelease } from '../../../scripts/verify-browser-release.mjs';

const release = {
  refType: 'tag',
  refName: 'browser-v0.2.0',
  repository: 'aiaiaiai-org/4x-errors',
  packageName: '@aiaiaiai/4x-errors-browser',
  version: '0.2.0'
};

test('accepts a release tag matching the canonical package version', () => {
  assert.doesNotThrow(() => verifyBrowserRelease(release));
});

test('refuses branch publication and mismatched tags', () => {
  assert.throws(() => verifyBrowserRelease({ ...release, refType: 'branch' }), /not a branch/);
  assert.throws(() => verifyBrowserRelease({ ...release, refName: 'browser-v0.1.0' }), /do not match/);
});

test('requires a fork publisher to choose its own package namespace', () => {
  assert.throws(() => verifyBrowserRelease({ ...release, repository: 'someone/fork' }), /own npm scope/);
  assert.doesNotThrow(() => verifyBrowserRelease({
    ...release, repository: 'someone/fork', packageName: '@someone/errors-browser'
  }));
});
