# Doc 66 Session 3 Plan

## Scope

- Re-run the focused doc-66 regression suite.
- Run the named `groups` gate.
- Persist the session ledger and final verdict into the reusable doc-66
  breakdown artifact.
- Confirm the rollout stayed inside the source-doc scope guard.

## Files

- `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-breakdown.md`
- `lib/core/services/pending_message_retrier.dart`
- `lib/main.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`

## Tests

- `flutter test test/core/services/pending_message_retrier_test.dart test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
- `./scripts/run_test_gates.sh groups`

## Gates

- `./scripts/run_test_gates.sh groups`

## Done Criteria

- Focused regressions pass.
- The named `groups` gate passes.
- The breakdown ledger records sessions `1`, `2`, and `3` as accepted.
- The final verdict for doc 66 is persisted as closed with concrete evidence.

## Scope Guard

- No adaptive timer backoff.
- No Go group discovery loop changes.
- No inbox cursor optimization.
