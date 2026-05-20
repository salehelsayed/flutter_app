# INTEGRATE-DE-018 Worktree-To-Main Integration Contract

Status: accepted

## Scope

Import and reconcile only source row `DE-018`: an unknown future group event must be logged and ignored without blocking later known group message or group reaction callbacks.

This is a standard integration contract, not a regeneration of the historical worktree implementation plan. The source plan and closure evidence remain the historical source of truth.

Out of scope: payload parse failure (`DE-015`), validation diagnostics (`DE-016`), membership/content ordering (`DE-017`), EventChannel recovery (`DE-019`), dispatcher starvation (`DE-020`), UI, notification, relay behavior, simulator/device proof, and adjacent row closure.

## Reconciliation

- Current main already had the production bridge behavior: `GoBridgeClient` routes `group_message:received` and `group_reaction:received`, while unknown push events fall through to the default log-and-ignore path.
- The source DE-018 row is tests-only. No production, harness, fixture, criteria, or script file was imported.
- `go_bridge_client_test.dart` gained the missing row-owned selector `DE-018 unknown group event is ignored without blocking known callbacks`, proving an unknown `group:future_protocol_probe` invokes no known callbacks, logs the unknown event, and does not poison later known message/reaction routing.

## Verification

Passed:

```bash
dart format test/core/bridge/go_bridge_client_test.dart
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "DE-018"
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --name "DE-009|DE-015|DE-016|GO-003|GO-004|GO-008"
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart
flutter analyze --no-pub test/core/bridge/go_bridge_client_test.dart
git diff --check
```

No named broad gate or iOS 26.2 live simulator proof was required or claimed because DE-018 is a host bridge-router unit proof; source `3-Party E2E` is `N/A`.
