// © 2026 aiaiaiai · aiaiaiai.org
// SPDX-License-Identifier: Apache-2.0

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
