# Session Plan: RY-007

## Row Contract

- source row: `RY-007`
- matrix contract: Partition heal and delayed delivery converge without duplicates and resume live delivery.
- current source truth before execution: `Partial`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof already shows:
  - the partitioned member misses split-window live delivery instead of silently appearing online
  - owned inbox replay restores the missed backlog in cursor order without duplicate visible rows
  - live delivery resumes after heal on the same group without reopening the split window as a stuck or replay-only state

## Scope Guard

- keep scope on the exact partition-heal replay contract only
- prefer row-owned evidence closure if current repo proof is already direct enough
- do not broaden into device-lab proof, relay privacy, or replay-attack rows

## Planned Proof

1. Audit the existing partition-heal integration coverage in `group_resume_recovery_test.dart`.
2. Reconcile that direct repo proof against the older matrix and breakdown classification drift.
3. Update closure docs only if the current test already pins backlog replay order, duplicate absence, and post-heal live delivery.

## Files Expected

- `test/features/groups/integration/group_resume_recovery_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
