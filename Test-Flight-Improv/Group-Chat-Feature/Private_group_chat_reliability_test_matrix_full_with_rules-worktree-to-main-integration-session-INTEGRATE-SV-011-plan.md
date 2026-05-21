# INTEGRATE-SV-011 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `SV-011` from the full-with-rules worktree into main: a sender with valid current group-key material but no active membership must still be rejected before persistence, event-log append, or fanout acceptance.

This is standard worktree-to-main integration, not new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-011-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: partial. Current main already rejected nonmember senders and already had the listener membership-watermark buffering guard equivalent to the source row, but the unknown-sender diagnostic did not include the row-owned `keyEpoch` proof field and the row-named tests were absent.
- Imported delta: add `keyEpoch` to `GROUP_HANDLE_INCOMING_MSG_UNKNOWN_SENDER_REJECTED` diagnostics and import only the row-owned Go, direct Flutter, and fake-network SV-011 proof selectors.
- Current-main adaptation: existing listener membership-dependent buffering behavior was inspected and left unchanged as already present.
- Live proof: not required. Source 3-Party E2E is `N/A`; no iOS 26.2 simulator proof is claimed.

## Imported Artifacts

- `go-mknoon/node/pubsub_authorization_forward_test.go`
  - `TestSV011ValidKeyNonMemberEnvelopeRejectsOnMembership`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - includes `keyEpoch` in unknown-sender rejection diagnostics.
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `SV-011 valid key nonmember sender is rejected before persistence or event log`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `SV-011 valid-key nonmember fake-network publish is rejected by all recipients`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Verification

- PASS: `cd go-mknoon && go test ./node -run TestSV011 -count=1`
- PASS: `cd go-mknoon && go test ./node -run 'TestSV011|TestGA002NonMemberCannotPublishValidEnvelope|TestGA026ValidationRejectDiagnosticsArePrivacySafeForAllReasons' -count=1`
- PASS: `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "SV-011"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "SV-011"`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "DE-017 content before member add is buffered then respects joined interval"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "DE-017 out-of-order membership and content converges to membership interval"`
- PASS: `dart format --set-exit-if-changed lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- PASS: `flutter analyze --no-pub lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- PASS: `gofmt` and scoped `git diff --check`

## Closure

`INTEGRATE-SV-011` is accepted as host/fake-network-only. Adjacent rows `SV-012` and later remain separate pending integration sessions.
