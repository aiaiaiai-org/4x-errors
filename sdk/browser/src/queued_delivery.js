// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

const DEFAULT_BATCH_SIZE = 50;
const DEFAULT_MAX_REQUEST_BYTES = 512 * 1024;
const DEFAULT_MAX_ATTEMPTS = 3;
const DEFAULT_BASE_DELAY_MS = 250;
const DEFAULT_MAX_DELAY_MS = 4_000;
const DEFAULT_FAILURE_THRESHOLD = 5;
const DEFAULT_COOLDOWN_MS = 30_000;

export function createQueuedDelivery({
  queue,
  send,
  batchSize = DEFAULT_BATCH_SIZE,
  maxRequestBytes = DEFAULT_MAX_REQUEST_BYTES,
  maxAttempts = DEFAULT_MAX_ATTEMPTS,
  baseDelayMs = DEFAULT_BASE_DELAY_MS,
  maxDelayMs = DEFAULT_MAX_DELAY_MS,
  failureThreshold = DEFAULT_FAILURE_THRESHOLD,
  cooldownMs = DEFAULT_COOLDOWN_MS,
  sleep = defaultSleep,
  random = Math.random,
  nowMs = Date.now
}) {
  let pipeline = Promise.resolve();
  const limit = positiveInteger(batchSize) ? Math.min(batchSize, DEFAULT_BATCH_SIZE) : DEFAULT_BATCH_SIZE;
  const byteLimit = positiveInteger(maxRequestBytes) ? maxRequestBytes : DEFAULT_MAX_REQUEST_BYTES;
  const retry = normalizeRetry({ maxAttempts, baseDelayMs, maxDelayMs, sleep, random });
  const circuit = createCircuit({ failureThreshold, cooldownMs, nowMs });

  return {
    submit(event) {
      pipeline = pipeline
        .then(() => submitEvent(queue, send, event, limit, byteLimit, retry, circuit))
        .catch(() => undefined);
      return pipeline;
    },
    flush() {
      pipeline = pipeline
        .then(() => drainBacklog(queue, send, limit, byteLimit, retry, circuit))
        .catch(() => undefined);
      return pipeline;
    },
    lifecycleFlush(sendLifecycle) {
      pipeline = pipeline
        .then(() => sendLifecycleSnapshot(queue, sendLifecycle, limit, byteLimit))
        .catch(() => undefined);
      return pipeline;
    }
  };
}

async function submitEvent(queue, send, event, batchSize, maxRequestBytes, retry, circuit) {
  if (!queue?.available) {
    await safeSend(send, event);
    return;
  }

  await queue.enqueue(event);
  await drainOnce(queue, send, batchSize, maxRequestBytes, retry, circuit);
}

async function drainBacklog(queue, send, batchSize, maxRequestBytes, retry, circuit) {
  while (await drainOnce(queue, send, batchSize, maxRequestBytes, retry, circuit)) {
    // Successful bounded batches continue until the durable backlog is empty.
  }
}

async function drainOnce(queue, send, batchSize, maxRequestBytes, retry, circuit) {
  if (!queue?.available || circuit.isOpen()) return false;

  const batch = await queuedBatch(queue, batchSize, maxRequestBytes);
  if (batch.length === 0) return false;

  const delivered = await sendWithRetry(send, batch, retry);
  circuit.record(delivered);
  if (!delivered) return false;

  await queue.remove(batch.map((event) => event.event_id));
  return true;
}

async function sendLifecycleSnapshot(queue, sendLifecycle, batchSize, maxRequestBytes) {
  if (!queue?.available || typeof sendLifecycle !== 'function') return;
  const batch = await queuedBatch(queue, batchSize, maxRequestBytes);
  if (batch.length === 0) return;
  await safeSend(sendLifecycle, batch);
  // Lifecycle delivery is best-effort; normal confirmed delivery owns acknowledgement.
}

async function queuedBatch(queue, batchSize, maxRequestBytes) {
  const queued = await queue.peek(batchSize);
  if (queued.length === 0) return [];
  return selectRequestBatch(queued, maxRequestBytes);
}

function selectRequestBatch(events, maxRequestBytes) {
  const batch = [];
  for (const event of events) {
    const candidate = [...batch, event];
    if (serializedBytes(candidate) > maxRequestBytes) break;
    batch.push(event);
  }
  return batch;
}

async function sendWithRetry(send, payload, retry) {
  for (let attempt = 1; attempt <= retry.maxAttempts; attempt += 1) {
    if (await safeSend(send, payload)) return true;
    if (attempt === retry.maxAttempts) break;
    await retry.sleep(jitteredDelay(attempt, retry));
  }
  return false;
}

async function safeSend(send, payload) {
  try {
    return (await send(payload)) === true;
  } catch {
    return false;
  }
}

function serializedBytes(value) {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}

function createCircuit({ failureThreshold, cooldownMs, nowMs }) {
  const threshold = positiveInteger(failureThreshold) ? failureThreshold : DEFAULT_FAILURE_THRESHOLD;
  const cooldown = nonNegativeNumber(cooldownMs) ? cooldownMs : DEFAULT_COOLDOWN_MS;
  const clock = typeof nowMs === 'function' ? nowMs : Date.now;
  let failures = 0;
  let openUntil = 0;

  return {
    isOpen() {
      return clock() < openUntil;
    },
    record(success) {
      if (success) {
        failures = 0;
        openUntil = 0;
        return;
      }
      failures += 1;
      if (failures >= threshold) {
        openUntil = clock() + cooldown;
        failures = 0;
      }
    }
  };
}

function normalizeRetry({ maxAttempts, baseDelayMs, maxDelayMs, sleep, random }) {
  return {
    maxAttempts: positiveInteger(maxAttempts) ? maxAttempts : DEFAULT_MAX_ATTEMPTS,
    baseDelayMs: nonNegativeNumber(baseDelayMs) ? baseDelayMs : DEFAULT_BASE_DELAY_MS,
    maxDelayMs: nonNegativeNumber(maxDelayMs) ? maxDelayMs : DEFAULT_MAX_DELAY_MS,
    sleep: typeof sleep === 'function' ? sleep : defaultSleep,
    random: typeof random === 'function' ? random : Math.random
  };
}

function jitteredDelay(attempt, retry) {
  const ceiling = Math.min(retry.maxDelayMs, retry.baseDelayMs * (2 ** (attempt - 1)));
  return Math.floor(ceiling * clampUnit(retry.random()));
}

function clampUnit(value) {
  if (!Number.isFinite(value)) return 0.5;
  return Math.min(1, Math.max(0, value));
}

function defaultSleep(delayMs) {
  return new Promise((resolve) => setTimeout(resolve, delayMs));
}

function positiveInteger(value) {
  return Number.isInteger(value) && value > 0;
}

function nonNegativeNumber(value) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}
