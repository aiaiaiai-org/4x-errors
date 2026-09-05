// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

const DEFAULT_BATCH_SIZE = 50;

export function createQueuedDelivery({ queue, send, batchSize = DEFAULT_BATCH_SIZE }) {
  let pipeline = Promise.resolve();
  const limit = positiveInteger(batchSize) ? batchSize : DEFAULT_BATCH_SIZE;

  return {
    submit(event) {
      pipeline = pipeline.then(() => submitEvent(queue, send, event, limit)).catch(() => undefined);
      return pipeline;
    },
    flush() {
      pipeline = pipeline.then(() => drainQueue(queue, send, limit)).catch(() => undefined);
      return pipeline;
    }
  };
}

async function submitEvent(queue, send, event, batchSize) {
  if (!queue?.available) {
    await safeSend(send, event);
    return;
  }

  await queue.enqueue(event);
  await drainQueue(queue, send, batchSize);
}

async function drainQueue(queue, send, batchSize) {
  if (!queue?.available) return;

  const events = await queue.peek(batchSize);
  if (events.length === 0) return;

  const acknowledged = [];
  for (const event of events) {
    const delivered = await safeSend(send, event);
    if (!delivered) break;
    acknowledged.push(event.event_id);
  }

  if (acknowledged.length > 0) await queue.remove(acknowledged);
}

async function safeSend(send, event) {
  try {
    return (await send(event)) === true;
  } catch {
    return false;
  }
}

function positiveInteger(value) {
  return Number.isInteger(value) && value > 0;
}
