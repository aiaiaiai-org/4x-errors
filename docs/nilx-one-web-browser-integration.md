# nilx-one/web browser integration

`@aiaiaiai/4x-errors-browser` is the canonical browser client for `nilx-one/web`.

The consumer owns only package installation and public reporter configuration. It does not own database access, Supabase credentials, retry state, batching, durable queueing, collector availability, or delivery lifecycle.

## Install

After the browser package is published from this repository:

```sh
pnpm add @aiaiaiai/4x-errors-browser
```

Do not copy SDK source into `nilx-one/web` and do not embed a collector secret in browser code.

## Configure

```ts
import { createBrowserReporter } from '@aiaiaiai/4x-errors-browser';

export const errorReporter = createBrowserReporter({
  project: 'nilx-one/web',
  source: 'browser',
  collectorEndpoint: import.meta.env.VITE_ERRORS_COLLECTOR_ENDPOINT
});
```

The collector endpoint is public configuration. The browser reporter uses the zero-secret `/v1/browser/events` boundary.

Global `error` and `unhandledrejection` capture is enabled by default. Explicit domain failures remain reportable with `report()`:

```ts
errorReporter.report({
  errorId: 'ai.model.unavailable',
  message: 'Local model unavailable',
  context: { phase: 'load' }
});
```

Call `dispose()` only when the reporter's application lifetime ends. Normal application code does not need to manage IndexedDB, flush retries, online recovery, lifecycle delivery, deduplication, batching, or circuit-breaker state.

## Client merge gate

Before the first `nilx-one/web` integration is merged:

- install the published package rather than vendoring source;
- configure `project` as `nilx-one/web`;
- configure only the public collector endpoint in browser environment state;
- verify the collector allows the production/staging origins used by the client;
- verify explicit reporting and global capture in the client build;
- verify queued events survive reload and reconnect;
- verify `nilx-one/web` remains functional while its own backend is unavailable;
- verify collector failure does not escape into application logic;
- keep database credentials and trusted ingest tokens out of browser code.

Package publication and collector deployment are separate protected delivery actions. This document does not authorize either action.

© 2026 aiaiaiai · aiaiaiai.org
