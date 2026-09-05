# The credential boundary

One rule shapes the design: **the database is reachable only by the collector.**
Everything else follows from it.

## Who holds what

| | Holds `DATABASE_URL` | Holds an ingest token | Reaches PostgreSQL |
|---|---|---|---|
| Collector | yes | — | yes |
| Reporting project (`nilx-one/web`, …) | no | yes, its own | no |
| Browser | no | no | no |
| Regular CI | no | test-only, generated per run | ephemeral database only |
| Production validation job | yes, from the `production` environment | minted for the run | yes |

A reporting project never receives database credentials and never talks to
Supabase. It holds one project-scoped token and one HTTPS endpoint. That is the
whole integration surface.

## In the database

`20260905000400_restrict_database_access.rb` enables row level security on
every table and adds no permissive policy. The collector connects as the table
owner and is unaffected; every other role is denied, and would stay denied even
if a grant were added by accident later.

The Supabase browser roles `anon` and `authenticated` are additionally stripped
of all privileges on tables, sequences and functions, present and future, via
`ALTER DEFAULT PRIVILEGES`. Schema-level `USAGE` may remain, inherited from
`PUBLIC`; it confers nothing without table privileges, and revoking it from
`PUBLIC` on a Supabase project would break the platform's own roles.

`error_events` carries a trigger that raises on `UPDATE`. Raw occurrences are
ground truth: interpretation of them is revisable, they are not. `DELETE` is
permitted, so retention and the removal of smoke records remain possible.

## In transit and at rest

- TLS is forced onto any `DATABASE_URL` that names a non-local host, whether or
  not it asked for it.
- The connection URL is never logged, echoed or included in an error message.
  Anything that has to name the database uses `Database.redact`, which is
  covered by a test that feeds it a password and asserts it does not appear.
- Ingest tokens are configured as SHA-256 digests, never as tokens. Comparison
  is constant time.
- Payloads are scrubbed on the collector before anything is persisted:
  credential-shaped keys, URLs with inline credentials, bearer headers, JSON
  web tokens and PEM private key blocks. The SDK applies the same rules before
  sending, so in the normal case a secret never leaves the reporting host at
  all. Scrubbing runs *before* the fingerprint is derived, so a secret cannot
  reach storage through the grouping key either.
- Internal failures answer `{"error":"internal_error"}`. The collector never
  describes its own internals to a reporter.

## In CI

The regular workflow has no access to the `production` environment, so it
cannot read `DATABASE_URL` even if a step asked for it. It also asserts the
variable is unset before running anything, so a future misconfiguration fails
loudly rather than quietly writing to production.

The production validation workflow refuses to run for a pull request from a
fork, so an untrusted job can never reach the production database.

## Reporting a problem

Open a private security advisory on the repository rather than an issue.

---

© 2026 aiaiaiai · aiaiaiai.org
