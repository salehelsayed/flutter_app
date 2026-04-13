# Session Plan: RY-015

## Row Contract

- source row: `RY-015`
- matrix contract: Encrypted replay respects add/remove/leave membership boundaries.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows replayed removal and leave boundaries stay truthful and rejoined members recover only on the fresh rotated epoch

## Scope Guard

- keep scope on replay-era membership windows
- do not overclaim product-scope behavior outside remove, leave, and re-invite boundaries already implemented in the repo
- reuse existing recovery and wired surfaces instead of inventing separate fake membership rules

## Executed Proof

1. `test/features/groups/integration/group_resume_recovery_test.dart` now proves removed offline members drain the replayed removal, lose access, and cannot send after resume while remaining members keep only the before-cutoff backlog.
2. `test/features/groups/presentation/group_info_wired_test.dart` now proves voluntary leave broadcasts a durable left-the-group event before local cleanup.
3. `test/features/groups/integration/invite_round_trip_test.dart` now proves remove -> rotate -> re-invite and offline re-invite recovery on the rotated epoch only.

## Files Expected

- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

