# INTEGRATE-ST-010 Plan - Standard Integration Contract

Status: accepted

## Scope

Import and verify historical row `ST-010`: "Invalid JSON and malformed bridge payload fuzzing."

This was standard worktree-to-main integration, not gap-closure. The historical source plan and closure evidence stayed the source of truth; no original implementation plan was regenerated.

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-010-plan.md`.
- Source row-owned proof selectors:
  - `cd go-mknoon && go test ./bridge -run TestST010 -count=1`
  - `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "ST-010"`
- Source 3-party E2E: `N/A`.

## Imported Delta

- Imported the row-owned `GoBridgeClient.send` request-envelope guard so invalid JSON, non-object requests, missing or blank `cmd`, non-string `cmd`, and non-object payloads return structured `INVALID_INPUT` without invoking the native MethodChannel.
- Imported the row-owned Dart bridge proof selector for malformed request envelopes and malformed native group responses, including sensitive sentinel non-leakage.
- Imported the row-owned Go bridge fuzz selector proving group bridge commands reject invalid JSON, malformed payloads, and missing required fields without panic, without success artifacts, and without mutating usable group state.

## Verification

Passed:

- `go test ./bridge -run TestST010 -count=1` from `go-mknoon`
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "ST-010"`
- `dart format --set-exit-if-changed lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart`
- `gofmt -w go-mknoon/bridge/bridge_test.go`
- `dart analyze lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart`
- `gofmt -l go-mknoon/bridge/bridge_test.go`
- `git diff --check`

## Verdict

`accepted`

ST-010 is imported and verified. The integration stayed limited to row-owned malformed bridge payload validation and proof artifacts. Existing blocked rows remain unchanged.
