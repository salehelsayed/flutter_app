# INTEGRATE-SV-005 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `SV-005` from the full-with-rules worktree into main: tampered ciphertext or nonce is rejected without stream poisoning.

This is standard worktree-to-main integration, not new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-005-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: partial. Existing current-main behavior already covered supporting DE-014 decryption-failure recovery and native single-envelope tampered nonce/ciphertext diagnostics.
- Imported delta: only the missing SV-005 row-owned proof selectors.
- Live proof: not required; source 3-Party E2E is `N/A`.

## Imported Artifacts

- `go-mknoon/node/pubsub_decryption_failure_test.go`
  - `TestSV005TamperedCiphertextOrNonceDoesNotPoisonLaterValidDelivery`
- `test/features/groups/application/group_message_listener_test.dart`
  - `SV-005 tampered envelope diagnostic does not poison later listener delivery`
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - `SV-005 tampered envelope diagnostic does not poison later fake-network delivery`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Verification

- PASS: `gofmt -w go-mknoon/node/pubsub_decryption_failure_test.go`
- PASS: `dart format --set-exit-if-changed test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart`
- PASS: `cd go-mknoon && go test ./node -run TestSV005TamperedCiphertextOrNonceDoesNotPoisonLaterValidDelivery -count=1`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart --plain-name SV-005`
- PASS: `cd go-mknoon && go test ./node -run 'TestSV005TamperedCiphertextOrNonceDoesNotPoisonLaterValidDelivery|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext' -count=1`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name 'DE-014 decryption failure queues repair placeholder and later valid event still persists|SV-005 tampered envelope diagnostic does not poison later listener delivery'`
- PASS: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'DE-014 decrypt failure repairs from durable replay and preserves later fake-network delivery|SV-005 tampered envelope diagnostic does not poison later fake-network delivery'`
- PASS: `dart analyze test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart`
- PASS: `git diff --check`

## Closure

`INTEGRATE-SV-005` is accepted as host/fake-network-only integration. Adjacent rows `SV-006` and later remain separate pending integration sessions.
