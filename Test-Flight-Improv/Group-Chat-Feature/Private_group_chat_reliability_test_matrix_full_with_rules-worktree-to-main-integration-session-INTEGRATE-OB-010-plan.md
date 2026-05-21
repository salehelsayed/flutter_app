# INTEGRATE-OB-010 Callback Exception Observability Integration Contract

Status: accepted

## Source Of Truth
- Source row: `OB-010` / "Group callback exceptions are observable in tests".
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-010-plan.md`.
- Source closure status: accepted/covered with focused bridge proof. Source 3-Party E2E is `N/A`.

## Integration Scope
Import only the row-owned Flutter bridge callback-observability seam:

- `lib/core/bridge/go_bridge_client.dart`
- `test/core/bridge/go_bridge_client_test.dart`

Current-main EventChannel recovery, malformed/unknown push-event diagnostics, raw Go flow redaction, and `group:publish_validation_rejected` routing were preserved.

Out of scope: OB-009 malformed-event handling, OB-011 release telemetry, retry-loop telemetry, dispatcher recovery, native Go dispatcher behavior, live harnesses, criteria, scripts, simulator/device proof, source matrix rewrites, COMPLETE_1 docs, and broad bridge refactors.

## Imported Delta
- `GoBridgeClient` now emits sanitized `GROUP_MESSAGE_CALLBACK_ERROR` when `onGroupMessageReceived` throws.
- `GoBridgeClient` now emits sanitized `GROUP_REACTION_CALLBACK_ERROR` when `onGroupReactionReceived` throws.
- `OB-010 group callback exceptions emit diagnostics and later events deliver` proves throwing message/reaction callbacks are logged and flow-diagnosed while later message/reaction callbacks still deliver.

## Verification
- `dart format --set-exit-if-changed lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart`
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "OB-010"` (`+1`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "DE-009"` (`+1`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "DE-018"` (`+1`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "OB-009"` (`+1`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "DE-019"` (`+2`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "ST-011"` (`No tests ran`; selector not present in current main, so no ST-011 claim)
- `flutter analyze --no-pub lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart` (`No issues found!`)
- `git diff --check`

## Device Proof
No simulator or live-device proof was required or claimed. Source 3-Party E2E is `N/A`, so the iOS 26.2-only device rule was not invoked.

## Closure Verdict
Accepted for `INTEGRATE-OB-010`. The row imported the missing callback diagnostics and focused proof, preserved current-main adjacent bridge behavior, and left unrelated `info.plist` untouched.
