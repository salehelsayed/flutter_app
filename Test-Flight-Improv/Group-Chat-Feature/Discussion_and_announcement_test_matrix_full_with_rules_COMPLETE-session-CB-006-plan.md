# Session Plan: CB-006

## Row Contract

- source row: `CB-006`
- matrix contract: Create-time description support is honest.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows the create surface exposes only the optional name field, the wired create path does not send a hidden description value, and description editing remains a later metadata flow instead of a silent create-time promise.

## Scope Guard

- tests and docs only
- do not add create-time description support in this session
- do not broaden into later metadata-edit flows beyond the minimal references needed to prove the omission stays honest

## Planned Proof

1. Add widget proof that the create sheet exposes only one metadata text field, the optional group name field.
2. Add wired-flow proof that the create bridge request omits `description` entirely.
3. Update the matrix, inventory, and breakdown to point at the row-owned proof.

## Files Expected

- `test/features/groups/presentation/widgets/group_name_panel_test.dart`
- `test/features/groups/presentation/create_group_picker_wired_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
