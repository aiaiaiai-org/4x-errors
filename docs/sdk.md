# Reporting from Ruby

```ruby
Aiaiaiai::Errors.configure do |errors|
  errors.endpoint    = "https://errors.aiaiaiai.org"
  errors.token       = ENV["ERRORS_TOKEN"]
  errors.project     = "nilx-one/web"
  errors.environment = "production"
  errors.component   = "web"
end
```

Incomplete configuration is not an error. Without an endpoint, a token and a
project the SDK installs a null reporter, and an application that reports
errors behaves identically to one that does not.

## The three calls

```ruby
Aiaiaiai::Errors.capture(exception, error_id: "ai.model.load.failed",
                         family_id: "ai.model.availability",
                         context: {model: "avatar-v3"},
                         tags: {release: "2026.09.1"})

Aiaiaiai::Errors.report(error_id: "ai.inference.runtime.unknown",
                        message: "inference stopped without a diagnosable cause",
                        severity: "warning")

Aiaiaiai::Errors.relate(source: "ai.model.load.failed",
                        type: "root_cause_of",
                        target: "ai.avatar.response.unavailable",
                        confidence: 0.95,
                        evidence: %w[explicit_reporter_relation dependency_failure])
```

`occurrence_key:` makes a report idempotent. A job that retries can pass the
same key and be certain the occurrence is stored once.

## What these calls guarantee

They return `nil` or a boolean. They never raise into the caller, and they
never block it on the network. That is the invariant the SDK exists to protect,
and `spec/sdk/reporting_spec.rb` is written as a list of ways to violate it.

Concretely, the reporting path is bounded at every point:

| | |
|---|---|
| Queue | bounded; the newest report is dropped and counted when it is full |
| Delivery | a background thread; the caller never waits |
| Timeouts | 1 s to connect, 2 s to read and write |
| Retries | bounded, exponential, jittered |
| Circuit breaker | opens after repeated failure and stops delivery entirely until a cooldown passes |
| Recursion | a report raised while reporting is dropped, including from the delivery thread |
| Payload | truncated to the protocol limits before sending; unserialisable values are replaced, not raised |
| Shutdown | `at_exit` flush with a deadline; it waits for `shutdown_timeout` and no longer |

A DNS failure, a refused connection, a silent collector, a TLS mismatch, a
rejected token, a `500`, an answer that is not HTTP at all, a full queue, a
context that cannot be serialised, an absent configuration: each has a test,
and in each the host application is unaffected.

## Settings

| Setting | Default | |
|---|---|---|
| `endpoint` | `ERRORS_ENDPOINT` | collector base URL; the SDK posts to `<endpoint>/v1/events` |
| `token` | `ERRORS_TOKEN` | project-scoped ingest token |
| `project` | `ERRORS_PROJECT` | must match the token's project |
| `environment` | `ERRORS_ENVIRONMENT`, `RACK_ENV`, `development` | |
| `component` | `ERRORS_COMPONENT` | default component for every report |
| `queue_limit` | 1000 | |
| `batch_size` | 32 | |
| `flush_interval` | 2.0 s | |
| `open_timeout` / `read_timeout` / `write_timeout` | 1.0 / 2.0 / 2.0 s | |
| `max_retries` | 2 | |
| `backoff` / `backoff_max` | 0.2 s / 5.0 s | |
| `failure_threshold` / `circuit_reset_after` | 5 / 30 s | |
| `shutdown_timeout` | 2.0 s | |
| `proxy` | `:environment` | `nil` to ignore proxy environment variables |
| `on_internal_error` | `nil` | called with anything the SDK swallowed |

`Aiaiaiai::Errors.statistics` reports what has been queued, dropped and whether
the circuit is open — useful as a gauge in the host's own metrics.

## Choosing an error_id

An `error_id` is the stable semantic identity of a failure kind. It should
survive a refactor that does not change what failed, and it should not encode
the message, the request, or the line number.

```
ai.model.load.failed
ai.inference.backend.unavailable
identity.provider.unreachable
map.renderer.initialization.failed
```

Repository names belong in an `error_id` only when the repository is part of
what makes the failure distinct. The `project` field already records who
reported it.

## Another language

`errors.v1` is HTTPS and JSON, and the collector cares about nothing else.
An adapter needs only to build the document, post it with a bearer token, and
uphold the same invariant on its own side. Start from
[`docs/protocol.md`](protocol.md) and the fixtures in `protocol/fixtures`.

---

© 2026 aiaiaiai · aiaiaiai.org
