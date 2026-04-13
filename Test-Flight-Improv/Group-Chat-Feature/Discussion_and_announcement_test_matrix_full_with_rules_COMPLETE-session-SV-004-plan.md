# Session Plan: SV-004

## Row Contract

- source row: `SV-004`
- matrix contract: Replay attack with tampered timestamps or reordered envelopes does not create duplicate visible messages or bypass cutoffs.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows:
  - a duplicate replay cannot create a second visible message row on the Flutter receive path when sequencing hints or timestamps are altered
  - removal and dissolve cutoffs still hold truthfully when replayed envelopes arrive out of order relative to those membership boundary events
  - the proof is narrow to replay resistance and does not overclaim adjacent crypto-diagnostics or dispatcher-overflow rows

## Scope Guard

- keep scope on replay / reorder resistance only
- prefer the smallest receive-path fix plus direct unit or integration regressions over broad inbox or dispatcher refactors
- do not widen into malformed-ciphertext diagnostics (`SV-005`), previous-key grace (`SV-006`), or key-race convergence (`SV-007`)

## Planned Proof

1. Inspect the current `handleIncomingGroupMessage` dedupe fallback and confirm whether timestamp-tampered replays without a stable `messageId` can still duplicate a visible row.
2. Tighten the receive-path replay guard only as much as needed to make reordered or timestamp-tampered duplicates non-visible without regressing legitimate distinct messages.
3. Add focused `handle_incoming_group_message_use_case_test.dart` regressions for:
   - timestamp-tampered duplicate replay without a second persisted row
   - replay attempts that arrive after a persisted removal or dissolve cutoff and still do not create a second visible row
4. Reuse the existing resume/recovery proof only if it already closes the reorder/cutoff part of the row without extra production changes.
5. Run the targeted Flutter tests, then update the matrix, inventory, and breakdown if the row-owned closure bar is satisfied.

## Files Expected

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart` if an extra row-owned replay regression is still needed
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
