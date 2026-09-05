// © 2026 aiaiaiai · aiaiaiai.org
// SPDX-License-Identifier: Apache-2.0

const DEFAULT_WINDOW_MS = 5_000;
const DEFAULT_MAX_ENTRIES = 256;

export function createEventDeduplicator({
  windowMs = DEFAULT_WINDOW_MS,
  maxEntries = DEFAULT_MAX_ENTRIES
} = {}) {
  const window = nonNegativeNumber(windowMs) ? windowMs : DEFAULT_WINDOW_MS;
  const limit = positiveInteger(maxEntries) ? maxEntries : DEFAULT_MAX_ENTRIES;
  const seen = new Map();

  return {
    accept(event) {
      const timestamp = Date.parse(event?.observed_at);
      if (!Number.isFinite(timestamp)) return true;

      pruneExpired(seen, timestamp, window);
      const fingerprint = stableStringify(fingerprintPayload(event));
      const previous = seen.get(fingerprint);
      if (previous !== undefined && timestamp - previous <= window) return false;

      seen.delete(fingerprint);
      seen.set(fingerprint, timestamp);
      trimOldest(seen, limit);
      return true;
    }
  };
}

function fingerprintPayload(event) {
  return {
    protocol_version: event.protocol_version,
    error_id: event.error_id,
    project: event.project,
    source: event.source,
    severity: event.severity,
    message: event.message,
    full_text: event.full_text,
    context: event.context,
    tags: event.tags,
    family_id: event.family_id,
    caused_by_event_id: event.caused_by_event_id,
    correlation_id: event.correlation_id
  };
}

function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  if (value && typeof value === 'object') {
    const entries = Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`);
    return `{${entries.join(',')}}`;
  }
  return JSON.stringify(value);
}

function pruneExpired(seen, timestamp, windowMs) {
  for (const [fingerprint, observedAt] of seen) {
    if (timestamp - observedAt > windowMs) seen.delete(fingerprint);
  }
}

function trimOldest(seen, maxEntries) {
  while (seen.size > maxEntries) {
    const oldest = seen.keys().next().value;
    seen.delete(oldest);
  }
}

function positiveInteger(value) {
  return Number.isInteger(value) && value > 0;
}

function nonNegativeNumber(value) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}
