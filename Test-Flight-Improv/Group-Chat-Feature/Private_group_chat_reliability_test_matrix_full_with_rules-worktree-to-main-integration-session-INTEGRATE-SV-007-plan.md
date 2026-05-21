# INTEGRATE-SV-007 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `SV-007` from the full-with-rules worktree into main: a group message whose payload `groupId` does not match the topic group it arrived on must be rejected and must not appear in either group timeline.

This is standard worktree-to-main integration, not new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-007-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: partial. Current main already had native GK-015 group-id mismatch validation and listener schema support for optional `topicGroupId`, but lacked the SV-007 row-named selector bundle and app-layer topic/payload mismatch guard.
- Imported delta: only the missing SV-007 row-owned guard, fake-network topic marker, and proof selectors.
- Current-main adaptation: the imported listener diagnostic uses current-main `_membershipFlowId` redaction instead of the historical source helper name.
- Live proof: not required; source 3-Party E2E is `N/A`.

## Imported Artifacts

- `go-mknoon/node/pubsub_test.go`
  - `TestSV007GroupTopicValidatorRejectsEnvelopeGroupMismatch`
- `lib/features/groups/application/group_message_listener.dart`
  - rejects non-empty `topicGroupId` values that differ from payload `groupId` before persistence.
- `test/shared/fakes/fake_group_pubsub_network.dart`
  - stamps delivered fake-network message events with `topicGroupId`.
- `test/features/groups/application/group_message_listener_test.dart`
  - `SV-007 topic group mismatch is rejected before listener persistence`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `SV-007 fake-network topic mismatch is rejected from both groups`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Verification

- PASS: `gofmt -w go-mknoon/node/pubsub_test.go`
- PASS: `dart format --set-exit-if-changed lib/features/groups/application/group_message_listener.dart test/shared/fakes/fake_group_pubsub_network.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- PASS: `cd go-mknoon && go test ./node -run TestSV007GroupTopicValidatorRejectsEnvelopeGroupMismatch -count=1`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart --plain-name SV-007`
- PASS: `cd go-mknoon && go test ./node -run 'TestSV007GroupTopicValidatorRejectsEnvelopeGroupMismatch|TestGK015ValidateGroupEnvelopeRejectsGroupIDMismatchBeforeTransportPeerAndSignature|TestGK015GroupTopicValidatorRejectsGroupIDMismatchAndEmitsReason' -count=1`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name 'DE-013 malformed group message schema rejects before persistence and valid later event persists|SV-007 topic group mismatch is rejected before listener persistence'`
- PASS: `flutter test --no-pub test/shared/fakes/fake_group_pubsub_network_test.dart --plain-name GO-012`
- PASS: `dart analyze lib/features/groups/application/group_message_listener.dart test/shared/fakes/fake_group_pubsub_network.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- PASS: `git diff --check`

## Closure

`INTEGRATE-SV-007` is accepted as host/fake-network-only integration. Adjacent rows `SV-008` and later remain separate pending integration sessions.
