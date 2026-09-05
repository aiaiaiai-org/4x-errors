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
const FAMILY_ID = /^family\.[a-z0-9]+(?:\.[a-z0-9]+)+$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const IDENTIFIER_MAX_LENGTH = 255;
const MESSAGE_MAX_LENGTH = 4_096;
const FULL_TEXT_MAX_LENGTH = 32_768;
const TAGS_MAX_ITEMS = 32;
const REQUEST_MAX_BYTES = 512 * 1024;

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
  if (!boundedNonEmptyString(config.project, IDENTIFIER_MAX_LENGTH)) return null;
  if (!boundedNonEmptyString(config.source, IDENTIFIER_MAX_LENGTH)) return null;

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
  if (!boundedNonEmptyString(input.errorId, IDENTIFIER_MAX_LENGTH) || !ERROR_ID.test(input.errorId)) {
    throw new TypeError('errorId must be a semantic error identifier');
  }

  const observedAt = config.now();
  if (!(observedAt instanceof Date) || Number.isNaN(observedAt.getTime())) {
    throw new TypeError('now must return a valid Date');
  }

  const eventId = config.randomUUID();
  if (!UUID.test(eventId)) throw new TypeError('randomUUID must return a UUID');

  const event = {
    protocol_version: PROTOCOL_VERSION,
    event_id: eventId,
    error_id: input.errorId,
    project: config.project,
    source: config.source,
    severity: stringOr(input.severity, 'error'),
    message: boundedString(stringOr(input.message, input.errorId), MESSAGE_MAX_LENGTH),
    full_text: boundedString(
      stringOr(input.fullText, stringOr(input.message, input.errorId)),
      FULL_TEXT_MAX_LENGTH
    ),
    observed_at: observedAt.toISOString(),
    context: sanitizeContext(input.context),
    tags: normalizedTags(input.tags),
    family_id: optionalIdentifier(input.familyId, FAMILY_ID),
    caused_by_event_id: optionalUuid(input.causedByEventId),
    correlation_id: optionalBoundedString(input.correlationId)
  };

  if (serializedRequestBytes(event) > REQUEST_MAX_BYTES) {
    throw new RangeError('error event exceeds browser request bound');
  }
  return event;
}

function normalizedTags(value) {
  if (!Array.isArray(value)) return [];
  const tags = value
    .filter(nonEmptyString)
    .map((tag) => boundedString(tag, IDENTIFIER_MAX_LENGTH));
  return [...new Set(tags)].slice(0, TAGS_MAX_ITEMS);
}

function optionalIdentifier(value, pattern) {
  if (value === undefined || value === null || value === '') return null;
  if (!boundedNonEmptyString(value, IDENTIFIER_MAX_LENGTH) || !pattern.test(value)) {
    throw new TypeError('optional identifier is invalid');
  }
  return value;
}

function optionalUuid(value) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string' || !UUID.test(value)) throw new TypeError('optional UUID is invalid');
  return value;
}

function optionalBoundedString(value) {
  if (value === undefined || value === null || value === '') return null;
  if (!boundedNonEmptyString(value, IDENTIFIER_MAX_LENGTH)) {
    throw new TypeError('optional string exceeds protocol bound');
  }
  return value;
}

function serializedRequestBytes(event) {
  return new TextEncoder().encode(JSON.stringify([event])).byteLength;
}

function defaultRandomUUID() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  throw new Error('crypto.randomUUID is unavailable');
}

function nonEmptyString(value) {
  return typeof value === 'string' && value.length > 0;
}

function boundedNonEmptyString(value, maxLength) {
  return nonEmptyString(value) && value.length <= maxLength;
}

function boundedString(value, maxLength) {
  return value.length <= maxLength ? value : value.slice(0, maxLength);
}

function stringOr(value, fallback) {
  return nonEmptyString(value) ? value : fallback;
}
