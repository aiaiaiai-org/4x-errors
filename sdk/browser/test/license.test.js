// © 2026 aiaiaiai · aiaiaiai.org
// SPDX-License-Identifier: Apache-2.0

import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const TEST_DIR = dirname(fileURLToPath(import.meta.url));
const SOURCE_DIR = join(TEST_DIR, '..', 'src');
const COPYRIGHT = '// © 2026 aiaiaiai · aiaiaiai.org';
const SPDX = '// SPDX-License-Identifier: Apache-2.0';

test('published browser sources declare the canonical Apache-2.0 header', async () => {
  const sourceFiles = (await readdir(SOURCE_DIR))
    .filter((name) => name.endsWith('.js') || name.endsWith('.d.ts'))
    .sort();

  assert.ok(sourceFiles.length > 0, 'browser package must publish source files');

  for (const name of sourceFiles) {
    const content = await readFile(join(SOURCE_DIR, name), 'utf8');
    const [copyright, spdx] = content.split('\n', 2);

    assert.equal(copyright, COPYRIGHT, `${name} must keep the canonical copyright notice`);
    assert.equal(spdx, SPDX, `${name} must declare Apache-2.0 via SPDX`);
  }
});
