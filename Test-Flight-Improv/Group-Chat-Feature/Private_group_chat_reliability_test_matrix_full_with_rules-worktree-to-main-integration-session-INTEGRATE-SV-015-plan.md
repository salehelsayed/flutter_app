# INTEGRATE-SV-015 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `SV-015` from the full-with-rules worktree into main: `callGroupDecrypt` must classify native decrypt failures and malformed success payloads as `BridgeCommandException`, not Dart cast/type errors.

This is standard worktree-to-main integration, not new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-015-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: missing. Current main still read `response['plaintext'] as String` without checking `{ok:false}` or validating malformed success responses.
- Imported delta: `callGroupDecrypt` throws `BridgeCommandException('group.decrypt', errorCode, errorMessage)` on `{ok:false}` and throws `BridgeCommandException('group.decrypt', 'INVALID_RESPONSE', ...)` when a success response lacks a plaintext string.
- Current-main adaptation: no keygen, create-group, decrypt repair, observability, or broader bridge helper changes were imported; SV-016 remains separate.
- Live proof: not required. Source 3-Party E2E is `N/A`; no iOS 26.2 simulator proof is claimed.

## Imported Artifacts

- `lib/core/bridge/bridge_group_helpers.dart`
  - Classifies `group.decrypt` native failures and malformed success responses before returning plaintext.
- `test/core/bridge/bridge_group_helpers_test.dart`
  - Adds SV-015 decrypt failure and malformed success classification tests.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Verification

- PASS: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name "SV-015"`
- PASS: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name "callGroupDecrypt"`
- PASS: `dart analyze lib/core/bridge/bridge_group_helpers.dart test/core/bridge/bridge_group_helpers_test.dart`
- PASS: `dart format --set-exit-if-changed lib/core/bridge/bridge_group_helpers.dart test/core/bridge/bridge_group_helpers_test.dart`
- PASS: scoped `git diff --check`

## Closure

`INTEGRATE-SV-015` is accepted as host-only. Adjacent row `SV-016` remains a separate pending integration session.
