// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

const REDACTED = '[REDACTED]';
const CIRCULAR = '[CIRCULAR]';
const TRUNCATED = '[TRUNCATED]';
const MAX_DEPTH = 8;
const MAX_STRING_LENGTH = 4096;
const MAX_CONTEXT_BYTES = 16_384;
const SENSITIVE_KEY = /(?:password|passwd|authorization|cookie|token|secret|api[_-]?key)/i;

export function sanitizeContext(value) {
  const seen = new WeakSet();
  const sanitized = sanitizeValue(value, 0, seen);
  const context = isPlainObject(sanitized) ? sanitized : {};
  return fitSerializedContext(context);
}

function sanitizeValue(value, depth, seen) {
  if (depth > MAX_DEPTH) return TRUNCATED;
  if (value === null || typeof value === 'boolean' || typeof value === 'number') return value;
  if (typeof value === 'string') return truncateString(value);
  if (typeof value !== 'object') return String(value);
  if (seen.has(value)) return CIRCULAR;

  seen.add(value);
  try {
    if (Array.isArray(value)) return value.map((item) => sanitizeValue(item, depth + 1, seen));
    if (!isPlainObject(value)) return Object.prototype.toString.call(value);

    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [
        key,
        SENSITIVE_KEY.test(key) ? REDACTED : sanitizeValue(entry, depth + 1, seen)
      ])
    );
  } finally {
    seen.delete(value);
  }
}

function fitSerializedContext(context) {
  if (byteSize(context) <= MAX_CONTEXT_BYTES) return context;

  const fitted = {};
  for (const [key, value] of Object.entries(context)) {
    fitted[key] = value;
    if (byteSize(fitted) > MAX_CONTEXT_BYTES) {
      delete fitted[key];
      fitted.__truncated__ = true;
      break;
    }
  }
  return fitted;
}

function byteSize(value) {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}

function truncateString(value) {
  if (value.length <= MAX_STRING_LENGTH) return value;
  return `${value.slice(0, MAX_STRING_LENGTH)}${TRUNCATED}`;
}

function isPlainObject(value) {
  if (!value || typeof value !== 'object') return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}
