# INTEGRATE-OB-005 Integration Contract

Status: skipped_already_present

Source-of-truth worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-005-plan.md`

This is a minimal worktree-to-main integration contract. It preserves the historical worktree row plan and closure evidence as source-of-truth and does not regenerate the original implementation plan.

## Row Scope

`OB-005` covers validation-rejection diagnostics being visible in Flutter diagnostics and flow logs with safe fields, while fake-network validation-reject diagnostics create no visible message row and do not poison later valid delivery.

## Already Present Evidence

Current main already has equivalent/stronger validation-rejection coverage through `DE-016`:

- `test/core/bridge/go_bridge_client_test.dart`: `DE-016 validation reject diagnostic reaches safe logs without group message callback` proves `group:validation_rejected` reaches `groupDiagnosticEventStream`, emits `GROUP_VALIDATION_REJECTED`, carries safe reason/hash/envelope/epoch fields, omits raw `groupId`/`senderId`, and does not invoke normal group-message callbacks.
- `test/features/groups/integration/group_resume_recovery_test.dart`: `DE-016 validation reject diagnostic stays safe and later fake-network delivery persists` proves fake-network validation-reject diagnostic injection creates no visible row and later valid delivery persists exactly once.
- `test/shared/fakes/fake_group_pubsub_network.dart`: `emitValidationRejectedDiagnostic(...)` already exists.
- `lib/core/bridge/go_bridge_client.dart`: validation-reject routing is already present.

No code, test, harness, fixture, criteria, or script changes were imported for OB-005.

## Evidence

- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "DE-016 validation reject diagnostic reaches safe logs without group message callback"` passed.
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "DE-016 validation reject diagnostic stays safe and later fake-network delivery persists"` passed.
- `git diff --check` passed after closure docs.

No simulator proof is required because source 3-Party E2E is `N/A`.

## Closure Verdict

Skipped as already present. The source OB-005 row-owned selectors would duplicate already accepted DE-016 current-main coverage, so this integration recorded the equivalence instead of importing duplicate tests. Adjacent OB diagnostics rows, simulator proof paths, Android, physical iOS, source worktree docs, and COMPLETE_1 docs remain out of scope.
