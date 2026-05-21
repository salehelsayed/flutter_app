# INTEGRATE-SV-004 Forged Sender Identity Or Signature Integration Contract

Status: accepted

## Source Of Truth

- Source row: `SV-004 | Forged sender identity or signature is rejected`
- Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical row plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-004-plan.md`
- Source closure status: accepted / Covered.
- Integration mode: standard import/reconcile/verify. This contract did not regenerate the historical implementation plan and did not reimplement the row from scratch.

## Reconciliation Classification

`partial_present`: current main already had the production sender/device/signature validation behavior through accepted COMPLETE_1/current-main rows such as GA-006, GK-008, GK-026, GK-028, and GE-018. The integration imported only the missing row-owned SV-004 proof selectors.

## Integrated Artifacts

- `go-mknoon/node/pubsub_authorization_forward_test.go`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## Explicitly Unchanged

- Production validator, listener, and repository behavior stayed unchanged.
- Source docs, COMPLETE_1 docs, source session plans, adjacent SV rows, UI, notification, media, relay, stress rows, Android, physical iOS, and simulator proofs were out of scope.

## Verification

- `gofmt -w go-mknoon/node/pubsub_authorization_forward_test.go`
- `dart format --set-exit-if-changed test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- `cd go-mknoon && go test ./node -run 'TestSV004ForgedSenderIdentityOrSignatureRejectsWithSafeDiagnostics|TestGA006SenderTransportPeerMismatchRejects|TestGroupTopicValidator_BadSignature|TestGroupTopicValidator_SpoofedPublicKey' -count=1`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart --plain-name SV-004`
- `dart analyze go-mknoon/node/pubsub_authorization_forward_test.go test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- `cd go-mknoon && go test ./node -run 'TestSV001|TestSV002|TestSV003|TestGK008|TestGK027|TestGA026|TestGA006SenderTransportPeerMismatchRejects|TestGroupTopicValidator_(BadSignature|SpoofedPublicKey)' -count=1`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name 'MS002 rejects transport peer mismatch before persistence or event log|SV-004 forged sender transport identity is rejected before persistence or event log'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name 'SV-001 never-member message is quarantined before stream storage or notification|SV-002 removed old-key message is rejected before stream storage unread or notification|SV-002 removed old-key reaction event does not mutate visible reactions'`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --name 'SV-001 never-member fake-network publish is rejected by all recipients|SV-002 removed old-key publish reaches listeners without timeline unread or reaction mutation|SV-003 pending re-add publish is blocked until current config and key|SV-004 forged sender identity is rejected by all fake-network recipients'`

No iOS 26.2 live proof was required or claimed because the source row marks 3-Party E2E as `N/A`.
