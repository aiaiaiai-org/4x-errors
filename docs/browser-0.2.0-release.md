# Browser SDK 0.2.0 release

Status: prepared, not published. Production acceptance is required before release.
Protocol: errors.v1 (unchanged).

## Included fixes

- Global runtime errors and promise rejections use valid dot-separated identifiers.
- HTTP and lifecycle requests have a five-second deadline and abort stalled fetches.
- Failed IndexedDB writes or reads fall back to direct best-effort delivery.
- Collector retries acknowledge existing event IDs without overwriting the first occurrence or rolling back new events in a batch.
- Collector /ready checks browser configuration, schema and trusted database writer permissions.
- Deployment can reuse a selected immutable image_sha from master ancestry.
- nilx-one/web PR #410 fixes three invalid map error IDs; client package upgrade follows publication.

## Production prerequisites

Configure the 4x-errors repository Production environment. Keep credentials in GitHub secrets, never in browser configuration or release notes.

| Setting | Kind | Purpose |
| --- | --- | --- |
| DATABASE_URL | secret | PostgreSQL writer connection |
| BROWSER_INGEST_ORIGINS | secret | JSON mapping of projects to exact allowed origins |
| SSH_HOST | secret | Existing collector host |
| SSH_USER | secret | Deployment account on that host |
| SSH_PRIVATE_KEY | secret | Authorized deployment key |
| COLLECTOR_PUBLIC_ORIGIN | variable | Public HTTPS collector origin |
| SSH_PORT | variable | Defaults to 22022 |
| EDGE_NETWORK | variable | Defaults to nilx-edge |
| COLLECTOR_DEPLOYMENT_ROOT | variable | Defaults to .local/share/aiaiaiai |

For the nilx.one website, the origin mapping includes:

```json
{"nilx-one/web":["https://nilx.one"]}
```

Add other origins only after verifying the actual Telegram/Discord host origin.
The edge proxy must route the public collector hostname to errors-collector:9292 on the configured Docker network.

## Acceptance before publication

1. Confirm schema migration 001 is applied and public browser roles cannot insert directly.
2. Select a successful Package collector image whose code includes the fixes. Run Deploy collector on master with its full image_sha. Confirm public /ready returns 200 and status ready.
3. From a permitted 0x1 browser origin, emit a uniquely identified errors.v1 event. Record its event_id and the collector acknowledgement.
4. Query error_events through the trusted database connection; the exact event_id must exist once.
5. Replay the event, then send a batch containing the replay and a new event. Both requests must succeed; the original remains unchanged and the new event is stored once.
6. Verify automatic error and unhandledrejection capture with the candidate SDK, reload/reconnect queue delivery and application behavior while the collector is unavailable.

A successful CI or readiness response alone does not satisfy this acceptance.

## Publish and integrate

After acceptance and release PR CI pass, merge the release PR. Create browser-v0.2.0 on the verified commit and publish its GitHub Release. Manually run Publish browser SDK on that tag; creating the release alone does not publish npm.

Verify npm resolves @aiaiaiai/4x-errors-browser@0.2.0. Upgrade the 0x1 dependency and lockfile, run client CI and deployment validation, deploy the verified client artifact and repeat the production event check. SDK publication, collector deployment and client deployment are separate operations.

## Observed blocker on 2026-10-14

The most recent collector deployment run is 38240677235, which failed at configuration validation on 2026-10-12. Its logs showed missing BROWSER_INGEST_ORIGINS, SSH_HOST, SSH_USER, SSH_PRIVATE_KEY and COLLECTOR_PUBLIC_ORIGIN. No later deployment run was found. Supabase was restored and schema version 1 was subsequently verified; this does not establish the deployed collector's database role or routing.

No production end-to-end success or npm 0.2.0 publication is claimed.

© 2026 aiaiaiai · aiaiaiai.org
