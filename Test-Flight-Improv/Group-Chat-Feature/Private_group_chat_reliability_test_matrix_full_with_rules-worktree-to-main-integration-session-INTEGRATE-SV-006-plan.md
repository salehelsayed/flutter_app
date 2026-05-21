# INTEGRATE-SV-006 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `SV-006` from the full-with-rules worktree into main: replaying an old valid group message must dedupe by `messageId` and must not bypass local removal/re-add membership intervals.

This is standard worktree-to-main integration, not new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-006-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: partial. Current main already had supporting LP-013 duplicate wire-envelope preservation, GI/RA/UP replay interval coverage, and duplicate application persistence behavior.
- Imported delta: only the missing SV-006 row-owned proof selectors.
- Current-main adaptation: removed-window rejection emits `GROUP_HANDLE_INCOMING_MSG_SELF_REMOVED_WINDOW_AFTER_REJOIN`, which is equivalent or stronger for the row contract than the historical `GROUP_HANDLE_INCOMING_MSG_LOCAL_REMOVED_INTERVAL_REPLAY_REJECTED` event.
- Live proof: not required; source 3-Party E2E is `N/A`.

## Imported Artifacts

- `go-mknoon/node/pubsub_delivery_test.go`
  - `TestSV006ReplayedWireEnvelopePreservesApplicationMessageIdForDedupe`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `SV-006 replay dedupes same epoch and rejects removed-interval after readd`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `SV-006 fake-network replay duplicate and removed-interval delivery stay deduped`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Verification

- PASS: `gofmt -w go-mknoon/node/pubsub_delivery_test.go`
- PASS: `dart format --set-exit-if-changed test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- PASS: `cd go-mknoon && go test ./node -run TestSV006ReplayedWireEnvelopePreservesApplicationMessageIdForDedupe -count=1`
- PASS: `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart --plain-name SV-006`
- PASS: `cd go-mknoon && go test ./node -run 'TestSV006ReplayedWireEnvelopePreservesApplicationMessageIdForDedupe|TestLP013DuplicateWireEnvelopeWithDistinctPubSubSeqnosPreservesApplicationMessageId|TestLP013ConflictingApplicationDuplicatePubSubPayloadsPreserveFirstWriterInputsForDartDedupe' -count=1`
- PASS: `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name 'duplicate replay with the same messageId ignores a tampered timestamp|duplicate replay with the same messageId ignores conflicting content|replayed removed-sender message after cutoff does not overwrite the accepted pre-cutoff row|SV-006 replay dedupes same epoch and rejects removed-interval after readd'`
- PASS: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --name 'SV-006 fake-network replay duplicate and removed-interval delivery stay deduped|RA-016 removed-interval replay after re-add is rejected while current delivery converges'`
- PASS: `dart analyze test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- PASS: `git diff --check`

## Closure

`INTEGRATE-SV-006` is accepted as host/fake-network-only integration. Adjacent rows `SV-007` and later remain separate pending integration sessions.
