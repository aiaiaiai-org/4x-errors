# 4x-errors storage: shared by default, your PostgreSQL optionally

Developers integrating 4x-errors may choose one of two storage options:

- **Default:** no database configuration in the product. The independent
  4x-errors collector writes to its existing central PostgreSQL/Supabase.
- **Own PostgreSQL:** the product owner can **submit a connection URL during
  protected project onboarding**. Once verified, the collector stores the
  connection configuration privately and routes that project's errors to the
  owner's database using the same `errors.v1` schema.

The second option must not require a permanent 4x-errors project ingest token.
The **connection credential for the owner's database is different**: it is
inevitable for direct PostgreSQL writing and must never be embedded in frontend
code or sent along with an error event.

## Current implementation

The collector accepts operator-registered PostgreSQL destinations via a
**private deployment setting**. The central `DATABASE_URL` points to the
existing 4x-errors Supabase Postgres; when not overridden, every project uses
it automatically.

A product owner can provide a compatible, restricted database connection URL
to the trusted collector administrator/operator for setup. That URL is placed
into the collector's private `ERRORS_PROJECT_DATABASE_URLS` mapping, e.g.:

```json
{"0xda-market/trading-lab":"postgresql://writer@db.example.com/errors?sslmode=verify-full"}
```

This is accepted as **project setup data, not public event data**. The optional
`ERRORS_PROJECT_DATABASE_URLS` production secret is passed only to the server
runtime when configured; it is never placed in the SDK or public endpoints. The
database is selected using the validated project ID and an existing private
mapping. Other projects still use the central Supabase automatically.

**Not yet implemented:** a self-service onboarding screen/API that accepts a
database URL directly from an authenticated project owner. Such an endpoint
must verify ownership via the control plane (e.g. AIS), receive credentials
over TLS, encrypt them at rest, verify database ownership and schema, limit
connection privileges, enforce network egress controls,
and never return the credential to a public client. Until then, registration
uses private operator configuration instead. Treat an arbitrary database URL
submitted in an error event as untrusted and never connect to it.

## Compatible database requirements

The owner's target PostgreSQL must support the canonical `db/migrations`
schema and `errors.v1`. The operator must provision and migrate the owner's
DB **separately**, with an owner/DDL role, by explicitly pointing `DATABASE_URL`
to that database for a controlled `bundle exec ruby bin/migrate` run.
The shared production migration workflow deliberately migrates **only the
central Supabase**; releases never execute DDL in external customer databases.

After migration, provision a distinct runtime role with `USAGE` on the schema
and `INSERT` on `error_events`, and create a PostgreSQL RLS `FOR INSERT`
policy restricted to the intended project (e.g. `WITH CHECK (project =
'0xda-market/trading-lab')`). Migration 001 enables RLS but does **not** create
that per-project policy. The runtime writer must not need table ownership,
`BYPASSRLS`, `CREATE`, `SELECT`, or DDL privileges. Verify the schema and a
real test insert with the restricted writer before activation; the collector
does not yet perform an onboarding privilege check automatically.

Dedicated URLs must use TLS (`sslmode=require`, `verify-ca`, or preferably
`verify-full`). The collector establishes their connections lazily, applies
connection/pool and statement timeouts, and shares pools for identical URLs.
An unavailable dedicated database causes a project-specific 503 without
changing the global `/ready` health check, which only checks central storage.
Map known project IDs exactly; unknown or misspelled keys are not discovered
automatically by the collector.

Public `/v1/browser/events` batches are single-project to preserve atomic
inserts. Mixed-project batches are rejected, not split between databases.
Read operations, arbitrary SQL, storage choices and connection strings are
never exposed on the public error-reporting endpoint.

## Client usage remains the same

Browser, Telegram Mini App, Native and backend clients send events to the
collector using their public project ID and `errors.v1`. They do not need
4x-errors ingest tokens or PostgreSQL credentials. Changing a project's
database never changes its client SDK integration.

Client-origin headers are not an authentication proof; abuse protection
must include project/origin allowlisting, quotas, request size limits and
distributed edge rate limiting. In the shared Supabase, do not grant
`anon` or `authenticated` direct table write privileges; preserve RLS.

---

© 2026 aiaiaiai · aiaiaiai.org
