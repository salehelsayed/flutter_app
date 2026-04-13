# Session Plan: SV-010

## Row Contract

- source row: `SV-010`
- matrix contract: Topic namespace / `topicName` contract between Go and Dart is explicit and tested.
- current source truth before execution: `Open`
- dependency: `CB-007`
- closure target for this session: update the source matrix row to `Covered` only if the canonical `topicName` contract is pinned across the create bridge response, the creator-path fallback, and the persisted group row.

## Scope Guard

- tests and docs only after the `CB-007` creator-path fix lands
- do not broaden into unrelated bridge-contract rows

## Planned Proof

1. Reuse the bridge helper contract tests that already pin canonical `/mknoon/group/...` responses.
2. Reuse the creator-path regression added by `CB-007` to prove the persisted fallback cannot drift from Go's canonical namespace.
3. Update the row-owned docs with the explicit file-and-test evidence.

## Files Expected

- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
