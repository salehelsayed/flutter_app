# Session Plan: SV-007

## Row Contract

- source row: `SV-007`
- matrix contract: Concurrent key-rotation races across admins converge to one final usable epoch.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows:
  - competing key-update deliveries do not leave multiple incompatible stored keys for the same final epoch
  - higher-generation updates still win when the race resolves in epoch order
  - the final converged key state remains usable by the existing send path without inventing new coordination primitives

## Scope Guard

- keep scope on convergence of stored key truth and sendability
- prefer one listener-level race regression plus reuse of existing rotated-send tests over broader admin or network refactors
- do not widen into dispatcher-overflow, replay security, or encrypted offline replay work

## Planned Proof

1. Add a key-update listener regression where two conflicting same-generation updates arrive back-to-back and must collapse to one stored key for that generation.
2. Reuse the existing sequential `epoch 2 then epoch 3` listener proof as the higher-epoch convergence path.
3. Reuse the existing rotated-send proof in `send_group_message_use_case_test.dart` (and, if needed, the integration equivalent) as the final usable-send contract once convergence is complete.
4. Run the targeted Dart tests, then update the matrix, inventory, and breakdown if the row-owned convergence contract is explicit enough.

## Files Expected

- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart` (evidence reuse unless a new assertion is needed)
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
