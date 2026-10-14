# Run your own 4x-errors

Fork or clone this repository and run the collector and PostgreSQL on your own machine.
No aiaiaiai account, Supabase project, npm publication, GHCR access or infra deployment is required.
Prerequisites: Linux/macOS, Bash and Docker with the Compose v2 plugin. Windows can use WSL2.

## First start

On the machine where you want to run the service:

```sh
git clone https://github.com/YOUR_ACCOUNT/YOUR_FORK.git
cd YOUR_FORK
bash bin/self-host setup
bash bin/self-host up
bash bin/self-host verify
```

Setup asks for the project identifier, application origin and collector URL. It generates a database password and saves configuration in a private, git-ignored `.env`. Repeating setup preserves the existing password and configuration.

For local development, enter an application origin such as `http://localhost:5173` and leave the collector URL empty. The collector is available at `http://localhost:1927`; PostgreSQL is not exposed on the host network.

For a public installation, enter `https://errors.example.com`. Point that hostname's DNS to your server and allow incoming ports 80 and 443. Setup enables Caddy, which obtains and renews HTTPS certificates automatically. An existing web server on those ports needs its own reverse-proxy configuration; remove `public` from `COMPOSE_PROFILES` and route to the collector's loopback port instead.

`up` builds your checkout, waits for PostgreSQL, runs migrations and starts the collector. `verify` sends a new event, checks its HTTP acknowledgement and exact database row, replays it without changing the stored occurrence, then submits a batch containing that event and a new one. Two diagnostic events remain in your database with the `self-host-smoke` tag. This checks the private installation; it does not claim a real browser application has already been integrated.

## Integrate an application

Install the canonical SDK; self-hosting the collector does not require renaming or publishing the SDK:

```sh
npm install @aiaiaiai/4x-errors-browser
```

```ts
import { createBrowserReporter } from '@aiaiaiai/4x-errors-browser';

const errors = createBrowserReporter({
  project: 'my/app',
  source: 'browser',
  collectorEndpoint: 'https://errors.example.com',
});

errors.report({ errorId: 'app.operation.failed', message: 'Operation failed' });
```

Only the collector endpoint and project identity belong in the browser. Automatic runtime-error capture is enabled. Confirm an emitted event in your own database; the local smoke test does not substitute for the real browser-origin and HTTPS check. The SDK release containing the global-capture fixes must be published before consumers can install those fixes from npm.

If you also change the SDK, test it locally as a workspace/file dependency or publish under your own npm scope. Do not publish a fork over the upstream package name.

## Configure permitted origins

In `.env`, a quoted multiline mapping supports the same convenient format as the GitHub Variable:

```dotenv
BROWSER_INGEST_ORIGINS='"my/app":"https://app.example.com",
"other/app":["https://other.example.com","http://localhost:5173"],'
COLLECTOR_PUBLIC_ORIGIN=https://errors.example.com
```

Full JSON objects remain supported. A project accepts one origin or an array; duplicate project entries are rejected rather than overwritten. Origins contain only scheme, host and optional port, with no path. Browser events remain untrusted; the allowlist is not an identity proof.

Public configuration goes in GitHub Variables when using Actions. Database passwords, trusted-ingest token digests and SSH keys remain secrets. For this standalone installation, keep the private `.env` on the server and out of git. The script never sources it as shell code.

## Operate and upgrade

```sh
bash bin/self-host logs
bash bin/self-host backup
git pull --ff-only
bash bin/self-host up
bash bin/self-host verify
bash bin/self-host stop
```

Backups are private PostgreSQL custom-format dumps in `self-host-backups/`. Copy them to separate storage and test restoration before relying on them. `stop` preserves database and certificate volumes. Never use `docker compose down -v` unless you intend to erase them. Back up before an upgrade; automatic rollback of database migrations is not performed.

The stack runs one collector instance. Horizontal scaling and online migration coordination are separate operational work.

## Prebuilt images and forks

The Package collector workflow publishes to the fork's own lowercase `ghcr.io/OWNER/REPOSITORY:sha-COMMIT`, not the upstream namespace. Enable Actions on your fork and permit package writes. The source-build flow above works without this workflow or a registry.

To use a prebuilt image, set `COLLECTOR_IMAGE` in `.env`, pull that image with Docker, and run `SELF_HOST_BUILD=0 bash bin/self-host up`. Authenticate Docker first if your package is private.

For phone-only operators, use a browser terminal provided by your server vendor or an SSH client to run these three setup commands once. The private `.env` stays on the server; subsequent upgrades can be run there without distributing machine credentials to applications.

© 2026 aiaiaiai · aiaiaiai.org
