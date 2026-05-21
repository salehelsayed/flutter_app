# INTEGRATE-OB-004 Integration Contract

Status: accepted

Source-of-truth worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-004-plan.md`

This is a minimal worktree-to-main integration contract. It preserves the historical worktree row plan and closure evidence as source-of-truth and does not regenerate the original implementation plan.

## Row Scope

`OB-004` covers live `group:decryption_failed` diagnostics creating a real key-repair workflow rather than a log-only artifact:

- a pending-key placeholder row is persisted and emitted;
- one durable `GroupPendingKeyRepair` is stored;
- one `GroupKeyRepairRequest` is sent with `groupKeyRepairReasonLiveDiagnostic`;
- duplicate live diagnostics dedupe instead of creating duplicate rows or repair requests;
- fake-network diagnostics do not create a normal plaintext delivery row.

Production listener and repair-service behavior was already present in current main. The integration imported only the missing row-owned fake-network helper and proof selectors.

No simulator proof is required because source 3-Party E2E is `N/A`.

## Integrated Files

- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Already Present And Preserved

- `lib/features/groups/application/group_message_listener.dart`: already routes live group decryption diagnostics into `queueLiveGroupDecryptionFailureRepair`.
- `lib/features/groups/application/group_pending_key_repair_service.dart`: already creates deterministic live repair ids, pending placeholders, durable pending repairs, and repair requests while deduping repeats.
- `test/shared/fakes/group_test_user.dart`: already wires fake-network diagnostic streams into `GroupMessageListener`.
- Adjacent `GO-004`, `DE-014`, and `SV-005` coverage remains separate and was preserved by focused selectors.

## Evidence

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "OB-004"` passed.
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "OB-004"` passed.
- Listener preservation passed: `GO-004 live decryption failure creates repair placeholder and trigger without plaintext delivery`, `DE-014 decryption failure queues repair placeholder and later valid event still persists`, and `SV-005 tampered envelope diagnostic does not poison later listener delivery`.
- Fake-network preservation passed: `DE-014 decrypt failure repairs from durable replay and preserves later fake-network delivery` and `SV-005 tampered envelope diagnostic does not poison later fake-network delivery`.
- `dart format --set-exit-if-changed lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_pending_key_repair_service.dart test/shared/fakes/fake_group_pubsub_network.dart test/shared/fakes/group_test_user.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed with 0 changed.
- `flutter analyze --no-pub lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_pending_key_repair_service.dart test/shared/fakes/fake_group_pubsub_network.dart test/shared/fakes/group_test_user.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed with no issues.
- `git diff --check` passed after closure docs.

## Closure Verdict

Accepted. The missing row-owned fake-network diagnostic helper plus direct and fake-network OB-004 proof selectors were imported. Production decryption-repair behavior and `GroupTestUser` diagnostic wiring were already present and left unchanged. Adjacent OB diagnostics rows, simulator proof paths, Android, physical iOS, source worktree docs, and COMPLETE_1 docs remain out of scope.
