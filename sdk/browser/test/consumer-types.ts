// © 2026 aiaiaiai · aiaiaiai.org
// Repository license is not selected yet; no SPDX identifier is asserted here.

import {
  createBrowserReporter,
  type BrowserReporter,
  type ErrorReportInput
} from '@aiaiaiai/4x-errors-browser';

const reporter: BrowserReporter = createBrowserReporter({
  project: 'nilx-one/web',
  source: 'browser',
  collectorEndpoint: 'https://errors.example'
});

const report: ErrorReportInput = {
  errorId: 'ai.model.unavailable',
  message: 'Model unavailable',
  context: { model: 'local' },
  tags: ['web']
};

reporter.report(report);
await reporter.flush();
reporter.dispose();
