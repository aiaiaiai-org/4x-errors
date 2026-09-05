// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

export function attachLifecycleDelivery({ delivery, sendLifecycle, target = globalThis }) {
  if (!delivery || typeof delivery.lifecycleFlush !== 'function') return () => {};
  if (typeof sendLifecycle !== 'function') return () => {};
  if (!target || typeof target.addEventListener !== 'function') return () => {};

  const handlePageHide = () => {
    try {
      void delivery.lifecycleFlush(sendLifecycle);
    } catch {
      // Lifecycle delivery is best-effort and must never affect page shutdown.
    }
  };
  target.addEventListener('pagehide', handlePageHide);

  return () => {
    try {
      target.removeEventListener?.('pagehide', handlePageHide);
    } catch {
      // Lifecycle teardown is non-critical.
    }
  };
}
