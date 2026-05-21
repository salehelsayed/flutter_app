# INTEGRATE-OB-012 Sensitive Diagnostic Redaction Integration Contract

Status: accepted

## Source Of Truth
- Source row: `OB-012` / "Sensitive diagnostic redaction is tested with real-looking secrets".
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-012-plan.md`.
- Source closure status: accepted/covered with focused host proof. Source 3-Party E2E is `N/A`.

## Integration Scope
Import only the row-owned real-looking secret redaction delta:

- `lib/core/utils/flow_event_emitter.dart`
- `test/core/utils/flow_event_emitter_test.dart`
- `test/core/bridge/go_bridge_client_test.dart`

Out of scope: broad observability completeness, analytics backends, validation-rejection semantics, malformed native event counting, callback exception visibility, release telemetry, simulator/device proof, source matrix rewrites, COMPLETE_1 docs, and source worktree docs.

## Imported Delta
- `sanitizeDiagnosticText` now redacts JSON-style quoted sensitive assignments inside free-form diagnostic strings before logs or flow-event sink payloads are emitted. This preserves current-main broader redaction for PEM blocks, multiaddrs, sensitive keys, peer IDs, and quoted/unquoted `key=value` assignments.
- `flow_event_emitter_test.dart` adds `OB-012 redacts real-looking diagnostic secrets from sink and logs`.
- `go_bridge_client_test.dart` adds `OB-012 redacts real-looking secrets in bridge and push diagnostics`.

## Verification
- `dart format --set-exit-if-changed lib/core/utils/flow_event_emitter.dart test/core/utils/flow_event_emitter_test.dart test/core/bridge/go_bridge_client_test.dart`
- `flutter test --no-pub test/core/utils/flow_event_emitter_test.dart --plain-name "OB-012"` (`+1`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "OB-012"` (`+1`)
- `flutter test --no-pub test/core/utils/flow_event_emitter_test.dart --plain-name "ER005"` (`+1`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "ER005"` (`+2`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "SV-013"` (`+2`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "GO-008"` (`+2`; initial preservation run failed on JSON-style `text` leakage, then passed after the OB-012 sanitizer fix)
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GO-008"` (`+1`)
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "GO-008"` (`+1`)
- `cd go-mknoon && go test ./node -run 'TestGO008FailureDiagnosticsDoNotLeakSensitiveLogsOrEvents' -count=1` (`ok`)
- `flutter analyze --no-pub lib/core/utils/flow_event_emitter.dart test/core/utils/flow_event_emitter_test.dart test/core/bridge/go_bridge_client_test.dart` (`No issues found!`)
- `git diff --check`

## Device Proof
No simulator or live-device proof was required or claimed. Source 3-Party E2E is `N/A`, so the iOS 26.2-only device rule was not invoked.

## Closure Verdict
Accepted for `INTEGRATE-OB-012`. The row imported the missing real-looking secret proof selectors and a narrow sanitizer fix for JSON-style sensitive assignments while preserving current-main ER005, SV-013, and GO-008 redaction behavior. Unrelated `info.plist` remained unstaged and untouched.
