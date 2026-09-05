# 4x-errors

Shared error reporting protocol, SDKs and collector for 4xAI child organisations and personal projects.

`4x-errors` provides one small, fault-tolerant boundary for reporting failures across otherwise independent projects. A reporting failure must never become an application failure.

## Model

The system keeps four concepts separate:

- **event** — one concrete observed occurrence;
- **error ID** — the stable semantic identity of a failure kind;
- **family ID** — a cross-project family of errors that may share an underlying cause;
- **causal relation** — an explicit directional relation such as `root_cause_of` or `derivative_of`.

Errors from different repositories may belong to the same family. Family membership alone does not assert causality: similarity is evidence, not proof.

```text
aiaiaiai-org/artificial-intelligence ─┐
                                      ├─ ai.model.availability
nilx-one/ai ──────────────────────────┘

ai.model.load.failed
        │
        └── root_cause_of ──► ai.avatar.response.unavailable
```

Causal relations retain confidence and evidence. Unknown causality remains an explicit and valid state.

## Architecture

```text
consumer
   │
   └── thin SDK / adapter
            │
            ▼
        errors.v1
            │
            ▼
      Ruby collector
            │
            ▼
       PostgreSQL
       / Supabase
```

The protocol is canonical. Ruby is the first reference implementation, not a runtime requirement for consumers. Rust, TypeScript, Swift and other adapters can implement the same contract without changing its semantics.

The collector is intentionally small: modern Ruby, Roda, Sequel and PostgreSQL. Production persistence is owned by 4xAI; consumers never receive database credentials.

## Reliability

The reporting path is designed as a non-critical dependency. SDK calls must not raise into the host application. Missing configuration behaves as a null reporter. Network work uses bounded queues, short timeouts, bounded retries and recursion protection. Collector or database downtime must not break the application being observed.

## First integrations

The first consumer is `nilx-one/web`. Planned integrations then extend to `aiaiaiai-org/artificial-intelligence`, `nilx-one/ai`, `nilx-one/core` and `0xda-market/*` through language-appropriate thin adapters sharing `errors.v1`.

The project starts as an error event store and causal model rather than a Sentry clone. Grouping, diagnostics and higher-level observability should grow from verified needs without expanding the critical reporting surface unnecessarily.


## Using it

A reporting project holds one endpoint and one project-scoped token. It never
holds database credentials.

```ruby
Aiaiaiai::Errors.configure do |errors|
  errors.endpoint = "https://errors.aiaiaiai.org"
  errors.token    = ENV["ERRORS_TOKEN"]
  errors.project  = "nilx-one/web"
end

Aiaiaiai::Errors.capture(exception, error_id: "ai.model.load.failed",
                         family_id: "ai.model.availability")
```

Or, from any language:

```sh
curl -X POST https://errors.aiaiaiai.org/v1/events \
  -H "authorization: Bearer $ERRORS_TOKEN" \
  -H "content-type: application/json" \
  -d '{"protocol_version":"errors.v1","project":"nilx-one/web",
       "events":[{"error_id":"ai.model.load.failed","environment":"production"}]}'
```

## Documentation

| | |
|---|---|
| [`docs/protocol.md`](docs/protocol.md) | errors.v1: the wire contract, the causal vocabulary and its invariants |
| [`docs/sdk.md`](docs/sdk.md) | reporting from Ruby, and what the reporting path guarantees |
| [`docs/operations.md`](docs/operations.md) | configuration, migrations, rollback, tokens, production validation |
| [`docs/security.md`](docs/security.md) | the credential boundary, in full |

## Layout

```text
protocol/          the normative schema and the cross-language conformance fixtures
lib/…/protocol/    the vocabulary, limits, validation, scrubbing and fingerprinting
lib/…/collector/   the Roda application, the ingest pipeline and the store
lib/…/             the Ruby SDK: reporter, bounded queue, circuit breaker, transport
db/migrations/     the schema, its indexes, its constraints and its access rules
spec/              the test suite, including the conformance run over the fixtures
```

## Working on it

```sh
docker run --rm -d -e POSTGRES_HOST_AUTH_METHOD=trust -p 5432:5432 postgres:17
export DATABASE_URL=postgres://postgres@127.0.0.1:5432/4x_errors
export TEST_DATABASE_URL=postgres://postgres@127.0.0.1:5432/4x_errors_test

bundle install
bundle exec rake db:migrate
bundle exec rake ci
```

Ruby is pinned in `.ruby-version` and read from there by the container image
and by every workflow; nothing retypes the version.

---

© 2026 aiaiaiai · aiaiaiai.org
