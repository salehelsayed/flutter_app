Status: accepted

# INTEGRATE-ML-014 Integration Contract

## Source Evidence
- Source row: `ML-014` / "Config update failure after local member insert rolls back or owns recovery".
- Controlling integration row: `INTEGRATE-ML-014` in `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-014-plan.md`.
- Source commits checked: `8cb8bd7c` and `f3739d78`. The meaningful source delta for main integration is row-owned tests only; source production changes are not part of ML-014.

## File Classification
- Production files: inspect-only for this integration. Current evidence says rollback behavior is already present in `addGroupMember`, `createGroupWithMembers`, and `ContactPickerWired`.
- Test files: allowed to import only the missing ML-014 row-named proof selectors.
- Docs: this file is the only integration contract doc touched in this row. The integration breakdown ledger, source matrix, and test inventory stay untouched for controller closure.

## Imported Deltas
- `test/features/groups/application/add_group_member_use_case_test.dart`: added `ML-014 rolls back local insert after group:updateConfig failure`.
- `test/features/groups/application/create_group_with_members_use_case_test.dart`: added `ML-014 rolls back all locally inserted create members after config sync failure`.
- `test/features/groups/presentation/contact_picker_wired_test.dart`: added `ML-014 config failure rolls back picker members and creates no invite retry state`.
- `test/features/groups/integration/group_membership_smoke_test.dart`: added `ML-014 config update failure rolls back local insert without fake-network membership`.

## Tests To Run
- `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'ML-014'`
- `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name 'ML-014'`
- `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'ML-014'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-014'`
- `git diff --check`

## Execution Progress And Final Verdict
- 2026-05-18: Imported the four row-owned ML-014 tests into the allowed target files. No production files were edited. No formatting command has been run.
- `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'ML-014'`: passed 1/1.
- `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name 'ML-014'`: passed 1/1.
- `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'ML-014'`: passed 1/1.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-014'`: passed 1/1.
- `git diff --check`: passed before and after final contract update.
- Final verdict: accepted.
