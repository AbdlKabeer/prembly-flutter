## Unreleased

* `integrity.hooking_framework_detected` on Android and iOS: Frida, Xposed, LSPosed and Substrate
  detection. iOS reports it apart from `is_rooted`, so a hooked device is no longer folded into the
  jailbreak flag. Best effort: `true` is strong evidence, `false` is not proof.

## 0.1.0

First release: the Flutter counterpart of `@olakay/prembly` (contract v4).

* `Prembly.init` with a publishable key (`live_pk_…` / `test_pk_…`); secret keys are rejected.
* `Prembly.workflow.start` / `open`: hosted workflows in a full-screen WebView, with events and a
  single end-of-flow callback (`completed`, `failed`, `manual_review`, `expired`, `cancelled`).
* `Prembly.tm`: Transaction Monitoring device sessions (`identify`, `getDeviceSession`,
  `getDeviceId`, `getSignalsPreview`, `setLocationEnabled`, `reset`), with native signal collection
  on Android and iOS ported from `prembly-tm-native`.
