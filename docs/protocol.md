# errors.v1

The protocol is the canonical artefact of this repository. Ruby is the first
implementation of it, not part of it.

- Normative schema: [`protocol/errors.v1.schema.json`](../protocol/errors.v1.schema.json)
- Conformance fixtures: [`protocol/fixtures`](../protocol/fixtures)

## Transport

| | |
|---|---|
| Protocol | HTTPS |
| Encoding | JSON, UTF-8 |
| Ingest | `POST /v1/events` |
| Health | `GET /health` |
| Credential | `Authorization: Bearer <project token>` |

## The four concepts

The model keeps four things apart, and the distinction is the point of the
project.

| Concept | Identifier | Who assigns it | Mutable |
|---|---|---|---|
| One observed occurrence | `event_id` (UUIDv7) | the collector | never |
| A kind of failure | `error_id` | the reporting project | stable across refactors |
| A family of related failures | `family_id` | curated, seeded by reporters | reclassifiable |
| A stated relation between failures | — | reporters and humans | append only |

`error_id` is a semantic identifier such as `ai.model.load.failed`. It is never
derived from a free-form message, and it does not need to name the repository
it came from unless the repository is part of what makes the failure distinct.

`family_id` may span repositories. `aiaiaiai-org/artificial-intelligence` and
`nilx-one/ai` reporting different `error_id`s into `ai.model.availability` is
the expected case, not a special one.

## Request

```json
{
  "protocol_version": "errors.v1",
  "project": "nilx-one/web",
  "events": [
    {
      "error_id": "ai.model.load.failed",
      "family_id": "ai.model.availability",
      "environment": "production",
      "severity": "error",
      "component": "inference-gateway",
      "message": "model weights are missing",
      "exception": {"type": "Errno::ENOENT", "message": "…", "backtrace": ["…"], "cause": {"type": "…"}},
      "context": {"model": "avatar-v3"},
      "tags": {"release": "2026.09.1"},
      "observed_at": "2026-09-05T04:12:31.482Z",
      "occurrence_key": "nightly-rebuild-2026-09-05",
      "fingerprint": "sha256:…",
      "local_ref": "cause",
      "sdk": {"name": "aiaiaiai-errors-ruby", "version": "0.1.0"}
    }
  ],
  "relations": [
    {
      "source": {"error_id": "ai.model.load.failed"},
      "type": "root_cause_of",
      "target": {"error_id": "ai.avatar.response.unavailable"},
      "confidence": 0.95,
      "evidence": ["explicit_reporter_relation", "dependency_failure"],
      "note": "the avatar pipeline has no fallback model"
    }
  ]
}
```

Only `protocol_version`, `project`, `events` and, per event, `error_id` and
`environment` are required. A request must carry at least one event or one
relation. Unknown fields are rejected rather than dropped, so a reporter never
believes it sent something the collector ignored.

`received_at` is not in the schema at all: there is no way for a reporter to
influence it. The collector stamps it.

`local_ref` is an alias scoped to one request, so that two occurrences reported
together can be related to each other before either has an `event_id`. It is
never stored.

## Relations

A relation connects two `error_id`s, or two concrete events, never one of each.

| Type | Reads as | Causal | Contributes the edge |
|---|---|---|---|
| `root_cause_of` | source is the root cause of target | yes | source → target |
| `contributes_to` | source contributes to target | yes | source → target |
| `derivative_of` | source is derived from target | yes | target → source |
| `triggered_by` | source was triggered by target | yes | target → source |
| `correlated_with` | source and target occur together | no | — |
| `duplicate_of` | source is an alias of target | no | — |

`confidence` (0–1) and `evidence` are both required. A relation with no stated
basis cannot be recorded.

Evidence vocabulary: `explicit_reporter_relation`, `deterministic_rule`,
`shared_trace_id`, `shared_operation_id`, `dependency_failure`,
`temporal_sequence`, `human_review`, `heuristic_similarity`.

### Invariants

- **Similarity is not causality.** `heuristic_similarity` is admissible
  evidence, but a causal relation supported by nothing else is rejected. It is
  perfectly valid evidence for `correlated_with`.
- **Family membership is not causality.** Two errors in one family assert
  kinship and nothing more.
- **Unknown causality is a valid state.** An event with no relation is
  complete, not incomplete.
- **Cycles are rejected.** An effect may not be, transitively, its own cause.
  The collector serialises writes to the causal graph so that two concurrent
  requests cannot jointly create one.
- **Reclassification never rewrites history.** Moving an `error_id` to another
  family supersedes a membership row; the raw occurrences keep the family their
  reporter claimed at the time.

## Responses

| Situation | Status | Body |
|---|---|---|
| Accepted | `202` | `{"accepted":1,"events":[{"event_id":"…","duplicate":false}],"relations":{…}}` |
| Repeated `occurrence_key` | `202` | the same `event_id`, `"duplicate":true` |
| Malformed payload | `400` | `{"error":"invalid_payload","violations":[{"pointer":"…","message":"…"}]}` |
| Body is not JSON | `400` | `{"error":"malformed_json"}` |
| Missing or unknown token | `401` | `{"error":"unauthorized"}` |
| Token belongs to another project | `403` | `{"error":"project_mismatch"}` |
| Relation would close a causal cycle | `409` | `{"error":"causal_cycle","message":"…"}` |
| Body above the size limit | `413` | `{"error":"payload_too_large","limit_bytes":1048576}` |
| Anything unexpected | `500` | `{"error":"internal_error"}` |

`409` and `413` are the two statuses beyond the base contract. A cycle is not a
malformed request — it conflicts with what is already stored — and an oversized
body is refused before it is parsed.

Persistence is atomic per request: either every event and relation in it is
stored, or none is.

## Limits

| | |
|---|---|
| Request body | 1 MiB |
| Events per request | 100 |
| Relations per request | 200 |
| Message | 4096 characters |
| Context | 16 KiB, 6 levels deep, 64 keys or items per level, 2048 characters per string |
| Tags | 32 entries, 64-character keys, 256-character values |
| Backtrace | 50 frames, 512 characters each, cause chain 5 deep |

The SDK truncates to these bounds before sending, so a well behaved reporter
never trips them.

## Fingerprints

A reporter may supply a `fingerprint`. When it does not, the collector derives
one from the semantic identity and the *shape* of the message: numbers, UUIDs,
hex values, paths and quoted strings are replaced with placeholders first. The
same failure therefore keeps one fingerprint across hosts, requests and
refactors.

## Versioning

`protocol_version` is exact. `errors.v1` will accept only `"errors.v1"`; a
change that would break an existing reporter becomes `errors.v2` on its own
endpoint, and the two run side by side until reporters have moved.

## Implementing an adapter

The fixtures are the specification for a new language. An implementation
conforms when it accepts every fixture under `protocol/fixtures/valid` and
rejects every one under `protocol/fixtures/invalid`, reporting at least the
JSON Pointers each invalid fixture names. Nothing in the fixtures or the schema
mentions Ruby, and nothing in them mentions a consuming project.

---

© 2026 aiaiaiai · aiaiaiai.org
