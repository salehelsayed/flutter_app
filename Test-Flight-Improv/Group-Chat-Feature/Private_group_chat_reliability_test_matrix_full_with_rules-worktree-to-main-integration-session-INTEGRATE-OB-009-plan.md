# INTEGRATE-OB-009 Native Event Diagnostics Integration Contract

Status: accepted

## Source Of Truth
- Source row: `OB-009` / "Unknown or malformed native events are counted and sanitized".
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-009-plan.md`.
- Source closure status: accepted/covered with focused bridge proof. Source 3-Party E2E is `N/A`.

## Integration Scope
Import only the row-owned Flutter bridge/EventChannel diagnostic seam:

- `lib/core/bridge/go_bridge_client.dart`
- `test/core/bridge/go_bridge_client_test.dart`

Current-main sanitizer and push diagnostic helpers were already present and preserved. The import intentionally avoided overwriting current-main EventChannel recovery, raw Go flow metadata handling, `group:publish_validation_rejected`, and other adjacent bridge behavior.

Out of scope: OB-010 callback exception diagnostics, OB-011 release telemetry, retry-loop telemetry, dispatcher recovery, native Go dispatcher behavior, live harnesses, criteria, scripts, simulator/device proof, source matrix rewrites, COMPLETE_1 docs, and broad bridge refactors.

## Imported Delta
- `GoBridgeClient` now counts malformed and unknown native push events with test-visible counters.
- `_handleEvent` validates raw EventChannel wrappers before routing: non-string events, invalid JSON, non-object JSON, missing/blank event names, and non-map `data` are recorded as malformed.
- Unknown well-formed events now emit sanitized `GO_BRIDGE_UNKNOWN_PUSH_EVENT` flow and push diagnostics instead of only raw debug output.
- Malformed events emit sanitized `GO_BRIDGE_MALFORMED_PUSH_EVENT` flow and push diagnostics without raw malformed payload values.
- `OB-009 unknown and malformed native events are counted and sanitized` proves invalid JSON, missing/blank event names, non-map data, sensitive unknown event names, sanitized logs, counters, and later known callback routing.

## Verification
- `dart format --set-exit-if-changed lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart`
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "OB-009"` (`+1`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "DE-018"` (`+1`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "OB-006"` (`+1`)
- `flutter analyze --no-pub lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart` (`No issues found!`)
- `git diff --check`

## Device Proof
No simulator or live-device proof was required or claimed. Source 3-Party E2E is `N/A`, so the iOS 26.2-only device rule was not invoked.

## Closure Verdict
Accepted for `INTEGRATE-OB-009`. The row imported the missing bridge behavior and focused test, preserved current-main adjacent bridge behavior, and left unrelated `info.plist` untouched.
