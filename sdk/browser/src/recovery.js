// © 2026 aiaiaiai · aiaiaiai.org
// SPDX-License-Identifier: Apache-2.0

export function attachDeliveryRecovery({ delivery, target = globalThis }) {
  if (!delivery || typeof delivery.flush !== 'function') return () => {};

  void safeFlush(delivery);

  if (!target || typeof target.addEventListener !== 'function') return () => {};

  const handleOnline = () => {
    void safeFlush(delivery);
  };
  target.addEventListener('online', handleOnline);

  return () => {
    try {
      target.removeEventListener?.('online', handleOnline);
    } catch {
      // Recovery teardown is non-critical and must never affect the host.
    }
  };
}

async function safeFlush(delivery) {
  try {
    await delivery.flush();
  } catch {
    // Recovery remains best-effort; delivery owns retry and persistence semantics.
  }
}
