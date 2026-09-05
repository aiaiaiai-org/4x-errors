// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

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
