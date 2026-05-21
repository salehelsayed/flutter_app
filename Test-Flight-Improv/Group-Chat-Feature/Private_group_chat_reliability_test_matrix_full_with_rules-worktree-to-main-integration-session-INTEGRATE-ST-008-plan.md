# INTEGRATE-ST-008 Plan - Standard Integration Contract

Status: accepted

## Scope

Import and verify historical row `ST-008`: "DB lock contention does not delay bridge event handling into message loss."

This was standard worktree-to-main integration, not gap-closure. The historical source plan and closure evidence stayed the source of truth; no original implementation plan was regenerated.

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-008-plan.md`.
- Source row-owned proof selectors:
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "ST-008"`
  - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-008"`
- Source 3-party E2E: `N/A`; no simulator or live proof is required for this row.

## Imported Delta

- Imported the row-owned direct listener contention proof that holds the first incoming message write, queues later listener events, releases the held write, and proves all ST-008 events persist and emit exactly once.
- Imported the bridge/write-transaction guard assertion proving a native bridge send inside the DB-write zone fails with `BridgeCallInsideDbTransactionError`.
- Imported the row-owned fake-network contention proof that injects a contended Bob message repository, proves Charlie keeps processing while Bob is blocked, and verifies Alice/Bob/Charlie converge without missing or duplicate ST-008 messages.
- Added the narrow `GroupTestUser.create` test hook for injecting an `InMemoryGroupMessageRepository` implementation; default test-user behavior remains unchanged.

## Verification

Passed:

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "ST-008"`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-008"`
- `dart format --set-exit-if-changed test/shared/fakes/group_test_user.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- `flutter analyze --no-pub test/shared/fakes/group_test_user.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- `git diff --check`

## Verdict

`accepted`

ST-008 is imported and verified. The integration stayed limited to row-owned DB-lock contention proof artifacts and documentation ledger updates. Existing blocked rows remain unchanged.
