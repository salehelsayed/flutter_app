# Session Plan: MM-012

## Row Contract

- source row: `MM-012`
- matrix contract: Send rules during active group recovery are explicit and intentional.
- current source truth before execution: `Partial`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows:
  - discussion sends are blocked while recovery is active
  - announcement-admin sends are blocked while recovery is active
  - the real wired sender path restores user intent and does not allow stale or hidden send paths to bypass the gate

## Scope Guard

- tests only
- do not broaden into unrelated retry, inbox, or stale-callback rows beyond the minimal references needed to close this send contract
- preserve the current product contract; do not invent a send-during-recovery allowance if the repo already blocks it

## Planned Proof

1. Add a unit regression pinning discussion send rejection while `groupRecoveryGate` is active.
2. Add an integration acceptance test using the real `GroupConversationWired` sender path to show discussion and announcement-admin drafts are restored and no bridge send occurs while recovery is active.
3. Run the targeted unit and integration tests.

## Files Expected

- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
