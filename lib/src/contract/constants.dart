/// Contract constants. Copied verbatim from the TypeScript reference (docs/contract.md, v4).
library;

const String defaultBaseUrl = 'https://backend.prembly.com';

/// The hosted workflow app. The single place the default is defined.
const String defaultHostedUrl = 'https://sdk-live.prembly.com/';

const String tmSessionsPath =
    '/api/v1/fraud/transaction-monitoring/sdk/v1/sessions';
const String workflowSessionsPath =
    '/api/v1/compliance-workflow/sdk/v1/sessions/';

const String headerPublishableKey = 'X-Publishable-Key';
const String headerAppId = 'X-App-Id';
const String headerSdkPlatform = 'X-SDK-Platform';
const String headerSdkVersion = 'X-SDK-Version';

const Duration defaultTimeout = Duration(milliseconds: 5000);

/// Creating a workflow session is a user-initiated action, so it gets longer than TM.
const Duration defaultWorkflowTimeout = Duration(milliseconds: 15000);

const String liveKeyPrefix = 'live_pk_';
const String sandboxKeyPrefix = 'test_pk_';

/// Event envelope `source` values.
const String eventSource = 'prembly-sdk';
const String legacyWorkflowEventSource = 'prembly-workflow-sdk';
