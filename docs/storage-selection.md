# 4x-errors storage selection

Client integration never accepts a database URL, username or credential. Storage is
selected **inside the collector** based on a project allowlist managed by the
operator, not on browser-controlled request headers, JSON or JavaScript config.

## Default (shared Supabase)

Set `DATABASE_URL` on the **collector only** to the existing 4x-errors
Supabase PostgreSQL connection string. This is the default for every registered
project with no override. Do not give this value to a client or build artifact.
The database must have the `db/migrations` schema and a restricted writer.

## Optional dedicated database per project

An operator may set `ERRORS_PROJECT_DATABASE_URLS` on the collector only:

```json
{"0xda-market/trading-lab":"postgresql://<dedicated-collector-writer>@<host>/<database>"}
```

Projects not present in this map continue to use the default Supabase storage.
No client can supply or override this map. URLs should use a TLS PostgreSQL
connection; keep the setting in private deployment secrets, not a GitHub variable.

Before enabling overrides, run `bundle exec ruby bin/migrate` with the same
server-side `DATABASE_URL` and `ERRORS_PROJECT_DATABASE_URLS` to apply the
canonical schema to the central and dedicated databases.

Browser batches are intentionally single-project: a batch spanning multiple
projects is rejected before insertion because atomicity cannot cross separate
PostgreSQL connections. Each project's events are routed to exactly one store.

## Public ingest security

Consumers send only `errors.v1` events to the collector's `/v1/browser/events`
endpoint, using a public project identifier and a configured Origin. An Origin
allowlist is an **abuse filter**, not authentication; a non-browser client can
forge it. Enable edge/WAF IP and global project quotas before accepting public
traffic. The ingest API alone persists events, and must not expose SELECT,
UPDATE, DELETE, SQL or arbitrary URL routing. Restrict `anon` and
`authenticated` DB permissions and keep row-level security enabled on the
central Supabase tables.

The collector needs a database connection secret **once**. Applications
need **zero 4x-errors tokens and zero database credentials**.

---

© 2026 aiaiaiai · aiaiaiai.org
