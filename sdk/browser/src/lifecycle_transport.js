// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

const BROWSER_INGEST_PATH = '/v1/browser/events';

export function createBrowserLifecycleTransport({ collectorEndpoint, fetchImpl = globalThis.fetch }) {
  const endpoint = normalizeEndpoint(collectorEndpoint);
  if (!endpoint || typeof fetchImpl !== 'function') return null;

  return async (payload) => {
    try {
      await fetchImpl(endpoint, {
        method: 'POST',
        mode: 'cors',
        credentials: 'omit',
        keepalive: true,
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload)
      });
      return true;
    } catch {
      return false;
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
