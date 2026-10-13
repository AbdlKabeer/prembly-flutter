# prembly (Flutter)

Prembly for Flutter: hosted **workflows** and **Transaction Monitoring** (TM) behind one
`Prembly.init`, `Prembly.workflow` and `Prembly.tm` API. It is the Flutter counterpart of the
JavaScript / React Native package `@olakay/prembly` and follows the same contract
([`docs/contract.md`](https://www.npmjs.com/package/@olakay/prembly) in that package): same keys,
endpoints, headers, error codes, events and TM behaviour.

Use a **publishable** key only: `live_pk_…` for live, `test_pk_…` for sandbox. The prefix decides the
environment. Secret keys (`*_sk_*`) are rejected by `init`; never put one in an app.

## Install

```yaml
dependencies:
  prembly:
    path: ../prembly-flutter # until it is published
```

### iOS

Minimum iOS 15.0. Add a camera description to `ios/Runner/Info.plist` (workflows use the camera
for selfie and ID capture):

```xml
<key>NSCameraUsageDescription</key>
<string>We use the camera to verify your identity.</string>
```

The plugin is CocoaPods-only for now, so `pod install` runs as usual. Flutter warns that plugins
will eventually be expected to support Swift Package Manager; see "Not yet" below.

### Android

Minimum SDK 24. Add the permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
```

The app asks for the camera at runtime the first time a workflow needs it.

## Quick start

```dart
import 'package:prembly/prembly.dart';

// Once, early (for example in main()). Use test_pk_… while developing.
Prembly.init(publishableKey: 'test_pk_xxxxxxxx');
```

### Workflows

```dart
// The SDK creates the session…
final handle = await Prembly.workflow.start(
  context: context,
  workflowId: 'wf_123',
  customer: const WorkflowCustomer(firstName: 'Ada', lastName: 'Obi', email: 'ada@example.com'),
  onEvent: (event) => debugPrint('${event.type} ${event.nodeId ?? ''}'),
  callback: (result) => debugPrint('${result.status} ${result.sessionId}'),
);

// …or open one your backend created:
Prembly.workflow.open(context: context, sessionId: sessionId, callback: (r) {});

handle.close(); // dismiss early: reported once as `cancelled`
```

The flow opens as a full-screen route with a close button. `callback` fires **once**, when the flow
ends, with a `WorkflowResult`:

| `status` | Meaning |
| --- | --- |
| `completed`, `failed`, `manual_review`, `expired` | Sent by the hosted app when the flow ends. |
| `cancelled` | The person closed the flow (close button, back gesture, or `handle.close()`) before it ended. `lastEvent` says where they were; `processing` means their steps were done and the checks carry on in the background. |
| `failed` / `not_available` | The flow could not start. `error` has the `code` and `message`. |

`onEvent` receives every event from the hosted app (`loaded`, `step_started`, `step_completed`,
`processing`, and the end states). Events carry no personal data.

`start` throws a `PremblyError` when it cannot start, and also calls `callback` with the failure.
`ErrorCode` values: `invalid_request`, `unauthorised`, `not_found`, `rate_limited`, `network_error`,
`timeout`, `server_error`, `invalid_key`, `not_initialised`, `not_available`.

### Transaction Monitoring

```dart
Prembly.tm.identify('customer-123');          // null when they sign out
final session = await Prembly.tm.getDeviceSession();
// Send session.deviceSessionId to your backend with the transaction. It is null if no session
// could be created: send the request anyway.
```

`getDeviceSession` never throws. A failed session is `DeviceSession(deviceSessionId: null,
deviceId, error)` so a payment is never blocked. A session is cached until 30 seconds before it
expires, concurrent callers share one request, and the cache is dropped when the customer, the
location setting or `init` changes. The default timeout is 5 seconds. Location is off by default and
is only read when the app already holds the permission: it never prompts.

Also: `getDeviceId()`, `getSignalsPreview()`, `setLocationEnabled(bool)`, `reset()`.

## How workflows run

The hosted workflow app only posts its events when it runs inside a frame, so the WebView loads a
small wrapper page that frames the hosted link, exactly as the web SDK does, and forwards the
messages to Dart. A message is accepted only if it comes from that frame, from the hosted app's
origin, and carries a per-flow random nonce.

## Not yet

* **Swift Package Manager** for iOS: the plugin is CocoaPods-only. SwiftPM links a plugin under its
  folder name, which must match the package name.
* **Web, macOS, Windows, Linux:** Android and iOS only.
* The signals a platform cannot provide are omitted, never guessed (see the contract).
* Other products (`Prembly.kyc` and so on) and `Prembly.register`: not available.

## Develop

```sh
flutter pub get
flutter test                                    # Dart unit tests
cd example && flutter test integration_test -d <device>   # the real plugin on a device or simulator
```
