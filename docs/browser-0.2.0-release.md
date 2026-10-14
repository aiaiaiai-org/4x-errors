# Browser SDK 0.2.0 release

Status: release candidate; not published. Production acceptance from the first 0x1 browser consumer is still required before this release.
Protocol: errors.v1 (unchanged).

## Included fixes

- Global runtime errors and promise rejections use valid dot-separated identifiers.
- HTTP and lifecycle requests have a five-second deadline and abort stalled fetches.
- Failed IndexedDB writes or reads fall back to direct best-effort delivery.
- Collector retries acknowledge existing event IDs without overwriting the first occurrence or rolling back new events in a batch.
- Collector /ready checks browser configuration, schema and trusted database writer permissions.
- Deployment can reuse a selected immutable image_sha from master ancestry.
- nilx-one/web PR #410 fixes three invalid map error IDs; client package upgrade follows publication.

## Independently verified self-hosting

PR #49 adds the complete [fork self-host flow](self-hosting.md): private PostgreSQL, migration runner, collector, optional Caddy HTTPS, backups and upgrades. Its CI verifies actual HTTP acknowledgements and persisted rows, immutable replay, mixed batches, backup creation, retained rows across stop/start and Caddy configuration. It also fixes missing runtime gems in the previous image. These results establish deployability, not live public DNS/TLS or the first 0x1 browser integration.

A fork can build and operate this stack without our infra, Supabase or GHCR. The optional registry namespace comes from the fork's repository. The SDK keeps errors.v1.

## Production prerequisites

Configure the 4x-errors repository Production environment. Keep credentials in GitHub secrets, never in browser configuration or release notes.

| Setting | Kind | Purpose |
| --- | --- | --- |
| DATABASE_URL | secret | PostgreSQL writer connection |
| BROWSER_INGEST_ORIGINS | variable | Mapping of projects to exact allowed origins |
| SSH_HOST | secret | Existing collector host |
| SSH_USER | secret | Deployment account on that host |
| SSH_PRIVATE_KEY | secret | Authorized deployment key |
| COLLECTOR_PUBLIC_ORIGIN | variable | Public HTTPS collector origin |
| SSH_PORT | variable | Defaults to 22022 |
| EDGE_NETWORK | variable | Defaults to nilx-edge |
| COLLECTOR_DEPLOYMENT_ROOT | variable | Defaults to .local/share/aiaiaiai |

For the nilx.one website, the origin mapping includes:

```text
"nilx-one/web":"https://nilx.one",
```

Mapping fragments support newlines and a trailing comma; full JSON objects and arrays of origins remain supported. Duplicate project keys fail configuration validation. Values are normalized before use with Docker env-file.

Add other origins only after verifying the actual Telegram/Discord host origin.
For the direct-SSH workflow, the edge proxy routes the public collector hostname to errors-collector:9292 on its Docker network. SSH fields apply to that workflow only; the independent self-host CLI requires no SSH credentials or upstream infrastructure. For self-hosting, setup generates the database credential locally and Caddy routes to collector:9292.

Automatic default placement through aiaiaiai-org/infra is not implemented yet. Do not describe missing SSH credentials as a working infra fallback.

## Acceptance before publication

1. Confirm schema migration 001 is applied and public browser roles cannot insert directly.
2. Select a successful Package collector image whose code includes the fixes. Run Deploy collector on master with its full image_sha. Confirm public /ready returns 200 and status ready.
3. From a permitted 0x1 browser origin, emit a uniquely identified errors.v1 event. Record its event_id and the collector acknowledgement.
4. Query error_events through the trusted database connection; the exact event_id must exist once.
5. Replay the event, then send a batch containing the replay and a new event. Both requests must succeed; the original remains unchanged and the new event is stored once.
6. Verify automatic error and unhandledrejection capture with the candidate SDK, reload/reconnect queue delivery and application behavior while the collector is unavailable.

A successful CI or readiness response alone does not satisfy this acceptance.

## Publish and integrate

After acceptance and release PR CI pass, merge the release PR. Create browser-v0.2.0 on the verified commit and publish its GitHub Release. Wait for successful CI on the tagged commit, then manually run Publish browser SDK on that tag; creating the release alone does not publish npm. Publication verifies the tag/version match, master ancestry and successful CI for the exact commit. It packages once and publishes that archive without repeating CI. A fork must change the npm scope and configure its own trusted publisher before publishing.

Verify npm resolves @aiaiaiai/4x-errors-browser@0.2.0. Upgrade the 0x1 dependency and lockfile, run client CI and deployment validation, deploy the verified client artifact and repeat the production event check. SDK publication, collector deployment and client deployment are separate operations.

## Observed blocker on 2026-10-14

The most recent collector deployment run is 38240677235, which failed at configuration validation on 2026-10-12. Its logs showed missing BROWSER_INGEST_ORIGINS, SSH_HOST, SSH_USER, SSH_PRIVATE_KEY and COLLECTOR_PUBLIC_ORIGIN. No later deployment run was found. Supabase was restored and schema version 1 was subsequently verified; this does not establish the deployed collector's database role or routing.

Still required to clear this release: record the deployed image SHA, public readiness result, permitted 0x1 browser origin, acknowledged event IDs and matching production database rows including replay/new-event behavior. Source CI and the isolated self-host smoke do not substitute for this evidence.

No production end-to-end success or npm 0.2.0 publication is claimed.

© 2026 aiaiaiai · aiaiaiai.org
