// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import { createEventDeduplicator } from './deduplicator.js';
import { createBrowserHttpTransport } from './http_transport.js';
import { createIndexedDbQueue } from './indexeddb_queue.js';
import { createQueuedDelivery } from './queued_delivery.js';
import { attachDeliveryRecovery } from './recovery.js';
import { sanitizeContext } from './sanitize.js';

const PROTOCOL_VERSION = 'errors.v1';
const ERROR_ID = /^[a-z0-9]+(?:\.[a-z0-9]+)+$/;

export function createBrowserReporter(config = {}) {
  const normalized = normalizeConfig(config);
  if (!normalized) return createNoopReporter();

  const delivery = createDelivery(normalized);
  if (!delivery) return createNoopReporter();
  const deduplicator = createEventDeduplicator();
  const detachRecovery = attachDeliveryRecovery({ delivery, target: normalized.runtimeTarget });

  return {
    report(input) {
      try {
        const event = buildEvent(normalized, input);
        if (!deduplicator.accept(event)) return;
        void delivery.submit(event);
      } catch {
        // Reporting is deliberately non-critical and must never escape into the host.
      }
    },
    flush() {
      return delivery.flush();
    },
    dispose() {
      detachRecovery();
    }
  };
}

function normalizeConfig(config) {
  if (!config || typeof config !== 'object') return null;
  if (!nonEmptyString(config.project) || !nonEmptyString(config.source)) return null;

  const collectorEndpoint = nonEmptyString(config.collectorEndpoint)
    ? config.collectorEndpoint
    : null;
  const transport = typeof config.transport === 'function' ? config.transport : null;
  if (!collectorEndpoint && !transport) return null;

  return {
    project: config.project,
    source: config.source,
    collectorEndpoint,
    transport,
    runtimeTarget: config.runtimeTarget ?? globalThis,
    now: typeof config.now === 'function' ? config.now : () => new Date(),
    randomUUID: typeof config.randomUUID === 'function' ? config.randomUUID : defaultRandomUUID
  };
}

function createDelivery(config) {
  if (config.transport) return createInjectedDelivery(config.transport);

  const send = createBrowserHttpTransport({ collectorEndpoint: config.collectorEndpoint });
  if (!send) return null;

  const queue = createIndexedDbQueue({
    databaseName: queueDatabaseName(config.project, config.collectorEndpoint)
  });
  return createQueuedDelivery({ queue, send });
}

function createInjectedDelivery(transport) {
  return {
    async submit(event) {
      try {
        await transport(event);
      } catch {
        // Custom transports preserve the same fail-safe host boundary.
      }
    },
    async flush() {}
  };
}

function createNoopReporter() {
  return {
    report() {},
    async flush() {},
    dispose() {}
  };
}

function queueDatabaseName(project, collectorEndpoint) {
  return `4x-errors:${project}:${collectorEndpoint}`;
}

function buildEvent(config, input) {
  if (!input || typeof input !== 'object') throw new TypeError('error report must be an object');
  if (!nonEmptyString(input.errorId) || !ERROR_ID.test(input.errorId)) {
    throw new TypeError('errorId must be a semantic error identifier');
  }

  const observedAt = config.now();
  if (!(observedAt instanceof Date) || Number.isNaN(observedAt.getTime())) {
    throw new TypeError('now must return a valid Date');
  }

  return {
    protocol_version: PROTOCOL_VERSION,
    event_id: config.randomUUID(),
    error_id: input.errorId,
    project: config.project,
    source: config.source,
    severity: stringOr(input.severity, 'error'),
    message: stringOr(input.message, input.errorId),
    full_text: stringOr(input.fullText, stringOr(input.message, input.errorId)),
    observed_at: observedAt.toISOString(),
    context: sanitizeContext(input.context),
    tags: stringArrayOrEmpty(input.tags),
    family_id: nullableString(input.familyId),
    caused_by_event_id: nullableString(input.causedByEventId),
    correlation_id: nullableString(input.correlationId)
  };
}

function defaultRandomUUID() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  throw new Error('crypto.randomUUID is unavailable');
}

function nonEmptyString(value) {
  return typeof value === 'string' && value.length > 0;
}

function stringOr(value, fallback) {
  return nonEmptyString(value) ? value : fallback;
}

function nullableString(value) {
  return nonEmptyString(value) ? value : null;
}

function stringArrayOrEmpty(value) {
  return Array.isArray(value) ? value.filter((item) => typeof item === 'string') : [];
}
