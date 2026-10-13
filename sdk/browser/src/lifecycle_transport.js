// © 2026 aiaiaiai · aiaiaiai.org
// SPDX-License-Identifier: Apache-2.0

import { createBrowserHttpTransport } from './http_transport.js';

export function createBrowserLifecycleTransport(options) {
  return createBrowserHttpTransport({ ...options, keepalive: true });
}
