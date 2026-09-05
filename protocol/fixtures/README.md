# errors.v1 conformance fixtures

Every fixture is one JSON document:

```json
{
  "description": "what the case establishes",
  "valid": false,
  "violations": ["/events/0/error_id"],
  "payload": { "…": "the errors.v1 request under test" }
}
```

- `payload` is a literal `POST /v1/events` request body.
- `valid` says whether a conforming implementation must accept it.
- `violations` lists JSON Pointers into `payload` that an implementation must
  report for an invalid case. It is a lower bound: reporting further violations
  of the same payload is conforming, reporting none of them is not.

The fixtures are deliberately free of Ruby: they are the shared conformance
suite for every future adapter — Rust, TypeScript, Swift — not a test detail of
this collector.

---

© 2026 aiaiaiai · aiaiaiai.org
