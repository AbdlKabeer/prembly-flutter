## 0.1.0

First release: the Flutter counterpart of `@olakay/prembly` (contract v4).

* `Prembly.init` with a publishable key (`live_pk_…` / `test_pk_…`); secret keys are rejected.
* `Prembly.workflow.start` / `open`: hosted workflows in a full-screen WebView, with events and a
  single end-of-flow callback (`completed`, `failed`, `manual_review`, `expired`, `cancelled`).
* `Prembly.tm`: Transaction Monitoring device sessions (`identify`, `getDeviceSession`,
  `getDeviceId`, `getSignalsPreview`, `setLocationEnabled`, `reset`), with native signal collection
  on Android and iOS ported from `prembly-tm-native`.
