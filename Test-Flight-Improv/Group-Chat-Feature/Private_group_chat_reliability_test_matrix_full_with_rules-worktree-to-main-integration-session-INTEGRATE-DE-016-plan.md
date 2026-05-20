# INTEGRATE-DE-016 Worktree-To-Main Integration Contract

Status: accepted

## Scope

Import and reconcile only source row `DE-016`: validation rejection diagnostics must surface with safe fields and must not poison later valid group delivery.

This is a standard integration contract, not a regeneration of the historical worktree implementation plan. The source plan and closure evidence remain the historical source of truth.

Out of scope: schema validation (`DE-013`), payload parse recovery (`DE-015`), membership/content ordering (`DE-017`), EventChannel recovery, dispatcher starvation, production behavior changes, unrelated fake-network route-mode/delivery-record helpers, criteria/live harnesses, iOS simulator proof, UI, media, notification, relay behavior, and adjacent row closure.

## Reconciliation

- Current main already had native validation-rejection behavior and stronger privacy-safe diagnostic coverage through `TestGA002NonMemberCannotPublishValidEnvelope`, `TestGA026ValidationRejectDiagnosticsArePrivacySafeForAllReasons`, and `TestGO005ValidationRejectDiagnosticsAreRateLimitedByReasonGroupSenderTransport`. The source native DE-016 selector was not duplicated.
- `go_bridge_client_test.dart` was reconciled by renaming/extending the existing validation-rejection bridge proof to the DE-016 row and asserting `GROUP_VALIDATION_REJECTED` flow-log details remain safe.
- `fake_group_pubsub_network.dart` gained only the minimal row-owned `emitValidationRejectedDiagnostic` helper on top of the existing diagnostic stream registration.
- `group_resume_recovery_test.dart` gained the row-owned fake-network DE-016 selector proving validation-rejection diagnostics create no visible row and later valid delivery persists once.

## Verification

Passed:

```bash
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'DE-016'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-016'
cd go-mknoon && go test ./node -run '^(TestGA002NonMemberCannotPublishValidEnvelope|TestGA026ValidationRejectDiagnosticsArePrivacySafeForAllReasons|TestGO005ValidationRejectDiagnosticsAreRateLimitedByReasonGroupSenderTransport)$' -count=1
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'GO-003 group publish validation feedback reaches diagnostics stream without invoking group message callback'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-015 payload parse diagnostic does not poison later fake-network delivery'
flutter analyze --no-pub test/core/bridge/go_bridge_client_test.dart test/shared/fakes/fake_group_pubsub_network.dart test/features/groups/integration/group_resume_recovery_test.dart
dart format test/core/bridge/go_bridge_client_test.dart test/shared/fakes/fake_group_pubsub_network.dart test/features/groups/integration/group_resume_recovery_test.dart
```

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

Result: red at `+207 -3` only on preserved non-DE-016 residuals `BB-007`, `BB-012`, and `GM-029`.

```bash
./scripts/run_test_gates.sh completeness-check
```

Result: red on the unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification residual (`732/733`).

No iOS 26.2 live simulator proof was required or claimed because DE-016 is host native/Dart bridge/fake-network proof.
