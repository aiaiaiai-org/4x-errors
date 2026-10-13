// © 2026 aiaiaiai · aiaiaiai.org
// SPDX-License-Identifier: Apache-2.0

const BROWSER_INGEST_PATH = '/v1/browser/events';

export function createBrowserHttpTransport({ collectorEndpoint, fetchImpl = globalThis.fetch, timeoutMs = 5_000, keepalive = false }) {
  const endpoint = normalizeEndpoint(collectorEndpoint);
  if (!endpoint || typeof fetchImpl !== 'function') return null;

  const timeout = Number.isFinite(timeoutMs) && timeoutMs > 0 ? timeoutMs : 5_000;
  return async (payload) => {
    const controller = new AbortController();
    let timer;
    try {
      const expired = new Promise((resolve) => {
        timer = setTimeout(() => {
          controller.abort();
          resolve(false);
        }, timeout);
      });
      const request = Promise.resolve().then(() => fetchImpl(endpoint, {
        method: 'POST',
        mode: 'cors',
        credentials: 'omit',
        ...(keepalive ? { keepalive: true } : {}),
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload),
        signal: controller.signal
      })).then((response) => response.ok, () => false);
      return await Promise.race([request, expired]);
    } finally {
      clearTimeout(timer);
    }
  };
}

function normalizeEndpoint(value) {
  if (typeof value !== 'string' || value.length === 0) return null;

  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;

    if (!url.pathname.endsWith(BROWSER_INGEST_PATH)) {
      const prefix = url.pathname.replace(/\/+$/, '');
      url.pathname = `${prefix}${BROWSER_INGEST_PATH}`;
    }
    url.search = '';
    url.hash = '';
    return url.toString();
  } catch {
    return null;
  }
}
