# errors.v1

`errors.v1` is the transport-neutral event contract used by `4x-errors` reporters and collectors.

The protocol is canonical. SDKs, collectors and storage adapters implement it; they do not redefine it.

## Error event

Each event represents one observed failure occurrence.

Required fields:

- `protocol_version` — exactly `errors.v1`.
- `event_id` — UUID for this occurrence.
- `error_id` — stable lowercase dot-separated semantic identifier such as `ai.model.load.failed`.
- `project` — reporting project identity.
- `source` — component or boundary that observed the failure.
- `severity` — non-empty severity label supplied by the producer; `errors.v1` does not prescribe a fixed vocabulary.
- `message` — concise human-readable summary, maximum 4096 characters.
- `full_text` — extended diagnostic text, maximum 32768 characters.
- `observed_at` — RFC 3339 / JSON Schema `date-time` timestamp.
- `context` — structured diagnostic object.
- `tags` — at most 32 unique tags.

Optional fields:

- `family_id` — known `family.<domain>.<topic>` semantic family, or `null`.
- `caused_by_event_id` — UUID of a directly preceding causal event when explicitly known, or `null`.
- `correlation_id` — application-defined correlation identifier, or `null`.

Unknown top-level fields are rejected. This keeps producer drift observable rather than silently accepting incompatible payloads.

## Identity semantics

`event_id` identifies an occurrence. `error_id` identifies a stable class of error. Repeated events may therefore share the same `error_id` while always having different `event_id` values.

A family groups semantically related errors. Family membership does not imply causality. The family registry and causal relation model are defined separately from this event contract.

## Compatibility

Changes that alter required fields, field meaning, accepted value domains or rejection behaviour require a new protocol version. Additions to implementation-specific transport, persistence or SDK behaviour do not change this contract unless the wire event itself changes.

The JSON Schema in `error-event.schema.json` is the machine-readable source of truth for the event shape.

© 2026 aiaiaiai · aiaiaiai.org
