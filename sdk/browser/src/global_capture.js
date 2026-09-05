// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

const WINDOW_ERROR_ID = 'browser.runtime.unhandled_error';
const REJECTION_ERROR_ID = 'browser.promise.unhandled_rejection';

export function attachGlobalErrorCapture({ reporter, target = globalThis }) {
  if (!reporter || typeof reporter.report !== 'function') return () => {};
  if (!target || typeof target.addEventListener !== 'function') return () => {};

  let handling = false;
  const guardedReport = (input) => {
    if (handling) return;
    handling = true;
    try {
      reporter.report(input);
    } catch {
      // Global capture must never participate in the host failure path.
    } finally {
      handling = false;
    }
  };

  const handleError = (event = {}) => {
    const error = event.error;
    guardedReport({
      errorId: WINDOW_ERROR_ID,
      message: textOr(event.message, textOr(error?.message, 'Unhandled browser error')),
      fullText: textOr(error?.stack, textOr(event.message, 'Unhandled browser error')),
      context: {
        filename: textOrNull(event.filename),
        line: numberOrNull(event.lineno),
        column: numberOrNull(event.colno)
      },
      tags: ['global', 'window.error']
    });
  };

  const handleRejection = (event = {}) => {
    const reason = event.reason;
    guardedReport({
      errorId: REJECTION_ERROR_ID,
      message: rejectionMessage(reason),
      fullText: rejectionFullText(reason),
      tags: ['global', 'unhandledrejection']
    });
  };

  target.addEventListener('error', handleError);
  target.addEventListener('unhandledrejection', handleRejection);

  return () => {
    try {
      target.removeEventListener?.('error', handleError);
      target.removeEventListener?.('unhandledrejection', handleRejection);
    } catch {
      // Capture teardown is non-critical.
    }
  };
}

function rejectionMessage(reason) {
  if (typeof reason === 'string' && reason.length > 0) return reason;
  return textOr(reason?.message, 'Unhandled promise rejection');
}

function rejectionFullText(reason) {
  return textOr(reason?.stack, rejectionMessage(reason));
}

function textOr(value, fallback) {
  return typeof value === 'string' && value.length > 0 ? value : fallback;
}

function textOrNull(value) {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function numberOrNull(value) {
  return Number.isFinite(value) ? value : null;
}
