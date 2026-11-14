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

The collector already accepts owner-provided PostgreSQL configuration via a
**private deployment setting**. The central `DATABASE_URL` points to the
existing 4x-errors Supabase Postgres; when not overridden, every project uses
it automatically.

A product owner can provide a compatible, restricted database connection URL
to the trusted collector administrator/operator for setup. That URL is placed
into the collector's private `ERRORS_PROJECT_DATABASE_URLS` mapping, e.g.:

```json
{"0xda-market/trading-lab":"postgresql://<restricted-writer>@<owned-host>/<errors-db>"}
```

This is accepted as **project setup data, not public event data**. The
database is selected using the validated project ID and an existing private
mapping. Other projects still use the central Supabase automatically.

**Not yet implemented:** a self-service onboarding screen/API that accepts a
database URL directly from an authenticated project owner. Such an endpoint
must verify ownership via the control plane (e.g. AIS), receive credentials
over TLS, encrypt them at rest, verify database ownership and schema, limit
connection privileges, apply connection timeout and network egress controls,
and never return the credential to a public client. Until then, registration
uses private operator configuration instead. Treat an arbitrary database URL
submitted in an error event as untrusted and never connect to it.

## Compatible database requirements

The owner's target PostgreSQL must support the collector's
`db/migrations` schema and `errors.v1` record format. Use a dedicated
writer role with only required privileges, TLS and network restrictions.
Before enabling, run `bundle exec ruby bin/migrate` on the **collector**
with the same private environment to migrate each configured store.

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
