// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

export function attachConnectivityRecovery({ flush, eventTarget = globalThis }) {
  if (typeof flush !== 'function') return createNoopRecovery();

  let active = true;
  const recover = () => {
    if (!active) return;
    void Promise.resolve().then(flush).catch(() => undefined);
  };

  recover();

  const canListen = typeof eventTarget?.addEventListener === 'function';
  if (canListen) eventTarget.addEventListener('online', recover);

  return {
    dispose() {
      active = false;
      if (canListen && typeof eventTarget.removeEventListener === 'function') {
        eventTarget.removeEventListener('online', recover);
      }
    }
  };
}

function createNoopRecovery() {
  return { dispose() {} };
}
