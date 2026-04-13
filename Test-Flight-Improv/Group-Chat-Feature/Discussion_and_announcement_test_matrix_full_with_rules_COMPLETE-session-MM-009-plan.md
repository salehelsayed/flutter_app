# Session Plan: MM-009

## Row Contract

- source row: `MM-009`
- matrix contract: Zero-peer plus inbox-fail sends recover through one explicit retry owner and never get stranded between retry lanes.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof shows:
  - the initial zero-peer plus inbox-fail branch lands on a failed row with durable retry material
  - inbox-store retry does not steal ownership from that failed row
  - failed-message retry recovers the same row in place and restores durable delivery

## Scope Guard

- keep scope on the zero-peer plus inbox-fail retry-owner contract only
- do not broaden into adjacent pending/live-peer retry rows
- prefer tests first; only change product code if the current retry-owner split is actually broken

## Planned Proof

1. Add a unit regression pinning zero-peer plus inbox-fail recovery through `retryFailedGroupMessages(...)`.
2. Add an integration regression pinning that the failed row is skipped by inbox-store retry, then recovered by failed-message retry, then delivered through offline inbox recovery.
3. Run the targeted unit and integration tests.

## Files Expected

- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
