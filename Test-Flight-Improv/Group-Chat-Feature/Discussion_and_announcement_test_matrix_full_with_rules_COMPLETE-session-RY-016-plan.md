# Session Plan: RY-016

## Row Contract

- source row: `RY-016`
- matrix contract: Encrypted replay remains reliable through retry, resume, cursor drain, reconnect, and dedupe.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows the encrypted replay path keeps the existing recovery-owner, cursor, resume, and dedupe guarantees intact

## Scope Guard

- keep scope on recovery ownership and reliability parity
- do not re-open unrelated notification or ordering work
- prefer current replay and lifecycle suites over one-off reliability harnesses

## Executed Proof

1. `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` now proves cursor continuation and encrypted replay drain behavior directly.
2. `test/features/groups/integration/group_resume_recovery_test.dart` now proves multi-page replay with tampered timestamps still stores one row, partition heal resumes without duplicates, and zero-peer inbox failure stays on the failed-message retry owner.
3. The current-session reruns of `rejoin_group_topics_use_case_test.dart`, `retry_failed_group_inbox_stores_use_case_test.dart`, `handle_app_resumed_group_recovery_test.dart`, and `handle_app_resumed_group_inbox_retry_test.dart` keep the rejoin and retry owners pinned around that encrypted replay path.

## Files Expected

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

