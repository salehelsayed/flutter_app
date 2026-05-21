# INTEGRATE-OB-002 Integration Contract

Status: accepted

Source-of-truth worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-002-plan.md`

This is a minimal worktree-to-main integration contract. It preserves the historical worktree row plan and closure evidence as source-of-truth and does not regenerate the original implementation plan.

## Row Scope

`OB-002` covers safe diagnostic metadata for config, key-rotation, and publish failure paths:

- config-update failure diagnostics include safe group/member prefixes, a membership operation id, and a classified error code;
- key-generation failure diagnostics include safe group prefix, expected key epoch, operation id, and classified error code;
- publish failure diagnostics include safe group prefix, key epoch, message id prefix, and classified error code;
- raw group ids, peer ids, and message ids are not logged in the row-owned diagnostic details.

No simulator proof is required because source 3-Party E2E is `N/A`.

## Integrated Files

- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Evidence

- `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name "OB-002"` passed.
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name "OB-002"` passed.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "OB-002"` passed after serial rerun; the first parallel attempt failed only in Flutter native-assets startup/install-name setup.
- `dart format --set-exit-if-changed lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart` passed with 0 changed after formatting.
- `flutter analyze --no-pub lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart` passed with no issues.
- `git diff --check` passed after closure docs.

## Closure Verdict

Accepted. Only row-owned meaningful OB-002 deltas were imported into main. Adjacent observability rows, decryption repair workflow, validation rejection surfacing, simulator proof paths, Android, physical iOS, source worktree docs, and COMPLETE_1 docs remain out of scope.
