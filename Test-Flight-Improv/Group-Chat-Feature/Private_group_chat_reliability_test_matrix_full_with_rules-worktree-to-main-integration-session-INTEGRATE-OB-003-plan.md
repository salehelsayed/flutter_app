# INTEGRATE-OB-003 Integration Contract

Status: accepted

Source-of-truth worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-003-plan.md`

This is a minimal worktree-to-main integration contract. It preserves the historical worktree row plan and closure evidence as source-of-truth and does not regenerate the original implementation plan.

## Row Scope

`OB-003` covers publish debug and fallback diagnostics that distinguish:

- zero-peer publish-debug metadata at the bridge flow-event seam;
- validation rejection diagnostics without normal message callback delivery;
- durable zero-peer inbox fallback success;
- zero-peer inbox failure as a distinct fallback branch.

The source fake-network row test delta was skipped as already present in main because `DE-016 validation reject diagnostic stays safe and later fake-network delivery persists` already proves validation rejection visibility, no message row from the diagnostic, and later valid delivery.

No simulator proof is required because source 3-Party E2E is `N/A`.

## Integrated Files

- `test/core/bridge/go_bridge_client_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Skipped Already Present

- `test/features/groups/integration/group_resume_recovery_test.dart`: source OB-003 fake-network selector was not duplicated because current main already has equivalent stronger coverage in `DE-016 validation reject diagnostic stays safe and later fake-network delivery persists`.
- `test/shared/fakes/fake_group_pubsub_network.dart`: `emitValidationRejectedDiagnostic(...)` already exists in current main.
- `lib/core/bridge/go_bridge_client.dart` and `lib/features/groups/application/send_group_message_use_case.dart`: production diagnostic behavior was already present.

## Evidence

- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "OB-003"` passed.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "OB-003"` passed.
- Equivalent fake-network preservation selector passed: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "DE-016 validation reject diagnostic stays safe and later fake-network delivery persists"`.
- Bridge preservation passed: `group publish debug push event keeps the raw flow event name`, `GO-003`, and `DE-016` selectors in `go_bridge_client_test.dart`.
- Send-use-case preservation passed: `GO-001`, `GO-002`, `DE-006`, and `DE-007` selectors in `send_group_message_use_case_test.dart`.
- `dart format --set-exit-if-changed test/core/bridge/go_bridge_client_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed with 0 changed.
- `flutter analyze --no-pub test/core/bridge/go_bridge_client_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed with no issues.
- `git diff --check` passed after closure docs.

## Closure Verdict

Accepted. Only missing row-owned OB-003 bridge and send-use-case test assertions were imported. Equivalent fake-network coverage was recorded as already present instead of duplicating the DE-016 selector. Adjacent OB diagnostics rows, simulator proof paths, Android, physical iOS, source worktree docs, and COMPLETE_1 docs remain out of scope.
