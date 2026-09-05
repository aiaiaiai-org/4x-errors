// © 2026 aiaiaiai · aiaiaiai.org
// SPDX-License-Identifier: Apache-2.0

export interface BrowserReporterConfig {
  project: string;
  source: string;
  collectorEndpoint?: string;
  transport?: (event: ErrorEventV1) => void | Promise<void>;
  runtimeTarget?: {
    addEventListener(type: string, listener: (...args: unknown[]) => void): void;
    removeEventListener?(type: string, listener: (...args: unknown[]) => void): void;
  };
  captureGlobalErrors?: boolean;
  now?: () => Date;
  randomUUID?: () => string;
}

export interface ErrorReportInput {
  errorId: string;
  severity?: string;
  message?: string;
  fullText?: string;
  context?: Record<string, unknown>;
  tags?: string[];
  familyId?: string | null;
  causedByEventId?: string | null;
  correlationId?: string | null;
}

export interface ErrorEventV1 {
  protocol_version: 'errors.v1';
  event_id: string;
  error_id: string;
  project: string;
  source: string;
  severity: string;
  message: string;
  full_text: string;
  observed_at: string;
  context: Record<string, unknown>;
  tags: string[];
  family_id: string | null;
  caused_by_event_id: string | null;
  correlation_id: string | null;
}

export interface BrowserReporter {
  report(input: ErrorReportInput): void;
  flush(): Promise<void>;
  dispose(): void;
}

export function createBrowserReporter(config?: Partial<BrowserReporterConfig>): BrowserReporter;
