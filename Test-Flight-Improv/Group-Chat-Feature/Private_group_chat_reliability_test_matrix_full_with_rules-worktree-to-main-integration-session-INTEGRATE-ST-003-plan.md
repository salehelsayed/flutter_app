# INTEGRATE-ST-003 Plan - Standard Integration Contract

Status: accepted

## Scope

Import and verify historical row `ST-003`: "Epoch monotonicity property test."

This was standard worktree-to-main integration, not gap-closure. The historical source plan and closure evidence stayed the source of truth; no original implementation plan was regenerated.

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-003-plan.md`.
- Source row-owned proof selectors:
  - `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name "ST-003 randomized key updates keep epoch monotonic and reject same-epoch conflicts"`
  - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-003 fake-network randomized key epoch monotonicity keeps active epoch"`
- Source 3-party E2E: `N/A`.

## Imported Delta

- Added the row-owned seeded listener property selector to `group_key_update_listener_test.dart`.
- Added the row-owned fake-network integration selector to `group_messaging_smoke_test.dart`.
- Production code stayed unchanged because current main already had the monotonic key-update behavior and adjacent fixed-case coverage from GEK/KE rows.

## Verification

Passed:

- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name "ST-003 randomized key updates keep epoch monotonic and reject same-epoch conflicts"`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-003 fake-network randomized key epoch monotonicity keeps active epoch"`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name "delayed older key update after newer generation does not promote active key"`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name "KE-005 conflicting same-generation key updates keep first accepted material"`
- `flutter analyze --no-pub test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`

No iOS simulator/live proof was required because the source row is host/integration only.

## Verdict

`accepted`

ST-003 is imported and verified. The integration stayed limited to row-owned deterministic property coverage and documentation ledger updates. Existing blocked rows remain unchanged.
