// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

const DEFAULT_BATCH_SIZE = 50;
const DEFAULT_MAX_ATTEMPTS = 3;
const DEFAULT_BASE_DELAY_MS = 250;
const DEFAULT_MAX_DELAY_MS = 4_000;
const DEFAULT_FAILURE_THRESHOLD = 5;
const DEFAULT_COOLDOWN_MS = 30_000;

export function createQueuedDelivery({
  queue,
  send,
  batchSize = DEFAULT_BATCH_SIZE,
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
  const limit = positiveInteger(batchSize) ? batchSize : DEFAULT_BATCH_SIZE;
  const retry = normalizeRetry({ maxAttempts, baseDelayMs, maxDelayMs, sleep, random });
  const circuit = createCircuit({ failureThreshold, cooldownMs, nowMs });

  return {
    submit(event) {
      pipeline = pipeline.then(() => submitEvent(queue, send, event, limit, retry, circuit)).catch(() => undefined);
      return pipeline;
    },
    flush() {
      pipeline = pipeline.then(() => drainQueue(queue, send, limit, retry, circuit)).catch(() => undefined);
      return pipeline;
    }
  };
}

async function submitEvent(queue, send, event, batchSize, retry, circuit) {
  if (!queue?.available) {
    await safeSend(send, event);
    return;
  }

  await queue.enqueue(event);
  await drainQueue(queue, send, batchSize, retry, circuit);
}

async function drainQueue(queue, send, batchSize, retry, circuit) {
  if (!queue?.available || circuit.isOpen()) return;

  const events = await queue.peek(batchSize);
  if (events.length === 0) return;

  const acknowledged = [];
  for (const event of events) {
    if (circuit.isOpen()) break;
    const delivered = await sendWithRetry(send, event, retry);
    circuit.record(delivered);
    if (!delivered) break;
    acknowledged.push(event.event_id);
  }

  if (acknowledged.length > 0) await queue.remove(acknowledged);
}

async function sendWithRetry(send, event, retry) {
  for (let attempt = 1; attempt <= retry.maxAttempts; attempt += 1) {
    if (await safeSend(send, event)) return true;
    if (attempt === retry.maxAttempts) break;
    await retry.sleep(jitteredDelay(attempt, retry));
  }
  return false;
}

async function safeSend(send, event) {
  try {
    return (await send(event)) === true;
  } catch {
    return false;
  }
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
