# INTEGRATE-SV-016 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `SV-016` from the full-with-rules worktree into main: bridge group keygen failure must not surface as an unclassified field access/type error, and the create fallback path must roll back while preserving the keygen failure code.

This is standard worktree-to-main integration, not new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-016-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: partial. Current main already had `callGroupKeygen` classified failure and malformed-success handling; it lacked row-named SV-016 keygen tests and the create fallback still surfaced a generic no-key `StateError` without preserving `KEYGEN_FAILED`.
- Imported delta: create fallback keygen errors now include the `BridgeCommandException` error code in flow diagnostics and the thrown `StateError`; row-owned keygen helper and create rollback tests were added/renamed.
- Current-main adaptation: no decrypt helper, add-member, broader diagnostics, observability, or simulator proof changes were imported.
- Live proof: not required. Source 3-Party E2E is `N/A`; no iOS 26.2 simulator proof is claimed.

## Imported Artifacts

- `lib/features/groups/application/create_group_use_case.dart`
  - Preserves classified keygen error code during rollback and thrown create failure.
- `test/core/bridge/bridge_group_helpers_test.dart`
  - Adds SV-016 keygen failure and malformed success classification selectors.
- `test/features/groups/application/create_group_use_case_test.dart`
  - Adds SV-016 create rollback proof that surfaces `KEYGEN_FAILED` and avoids `_TypeError`.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Already Present

- `lib/core/bridge/bridge_group_helpers.dart`
  - `callGroupKeygen` already classified `{ok:false}` as `BridgeCommandException('group.keygen', errorCode, errorMessage)` and malformed success responses as `INVALID_RESPONSE`; no production helper edit was required.

## Verification

- PASS: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name "SV-016"`
- PASS: `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart --plain-name "SV-016"`
- PASS: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name "callGroupKeygen"`
- PASS: `flutter analyze --no-pub lib/core/bridge/bridge_group_helpers.dart lib/features/groups/application/create_group_use_case.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart`
- PASS: `dart format --set-exit-if-changed lib/core/bridge/bridge_group_helpers.dart lib/features/groups/application/create_group_use_case.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart`
- PASS: scoped `git diff --check`

## Closure

`INTEGRATE-SV-016` is accepted as host-only. Later observability rows remain separate pending integration sessions.
