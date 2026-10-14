// © 2026 aiaiaiai · aiaiaiai.org
// SPDX-License-Identifier: Apache-2.0

import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function verifyBrowserRelease({ refType, refName, repository, packageName, version }) {
  if (refType !== 'tag') throw new Error('Publish from a browser-vVERSION tag, not a branch.');
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(version)) {
    throw new Error('Package version must be a release version.');
  }
  if (refName !== `browser-v${version}`) throw new Error('Tag and package version do not match.');
  if (repository !== 'aiaiaiai-org/4x-errors' && packageName === '@aiaiaiai/4x-errors-browser') {
    throw new Error('Choose your own npm scope before publishing a fork.');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const pkg = JSON.parse(readFileSync(new URL('../sdk/browser/package.json', import.meta.url)));
    verifyBrowserRelease({
      refType: process.env.GITHUB_REF_TYPE,
      refName: process.env.GITHUB_REF_NAME,
      repository: process.env.GITHUB_REPOSITORY,
      packageName: pkg.name,
      version: pkg.version
    });
    process.stdout.write(`Validated ${pkg.name}@${pkg.version}\n`);
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
