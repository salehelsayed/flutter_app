# INTEGRATE-SV-014 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `SV-014` from the full-with-rules worktree into main: relay-visible group inbox requests for membership add/remove/re-add replay must not expose membership event ids, system event types, member names, public key material, or group config content outside encrypted payloads.

This is standard worktree-to-main integration, not new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-014-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: partial. Current main already had opaque replay-envelope privacy and newer removed-member snapshot/revoked-device signature protections; it still exposed membership-prefixed replay `messageId` values in relay-visible replay envelope metadata and lacked the SV-014 row-named proofs.
- Imported delta: membership replay message ids are omitted from relay-visible envelope and signed-payload metadata while non-membership message ids remain visible; accepted-join replay keeps the timeline message id inside encrypted plaintext for recipients; row-owned Dart, fake-network, and Go tests prove membership replay privacy.
- Current-main adaptation: preserved current removed-member snapshot, revoked-device, recipient hash, and signature verification behavior instead of copying stale source hunks that would weaken those protections.
- Live proof: not required. Source 3-Party E2E is `N/A`; no iOS 26.2 simulator proof is claimed.

## Imported Artifacts

- `lib/features/groups/application/group_offline_replay_envelope.dart`
  - Suppresses membership-prefixed replay message ids from relay-visible envelope and signed-payload metadata.
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
  - Stores accepted-join timeline id inside encrypted replay plaintext.
- `test/features/groups/application/group_offline_replay_envelope_test.dart`
  - Adds SV-014 relay-visible membership replay redaction proof.
- `test/features/groups/integration/group_membership_smoke_test.dart`
  - Adds SV-014 fake-network membership churn replay-store privacy proof.
- `go-mknoon/node/group_inbox_test.go`
  - Adds `TestSV014GroupInboxStoreRequest_OmitsMembershipReplayPlaintext`.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Verification

- PASS: `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart --plain-name "SV-014"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "SV-014"`
- PASS: `cd go-mknoon && go test ./node -run TestSV014 -count=1`
- PASS: `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart`
- PASS: `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart --plain-name "GK-028"`
- PASS: `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name "EK004 successful accept stores signed member_joined replay envelope"`
- PASS: `cd go-mknoon && go test ./node -run 'TestSV014|TestBuildGroupInboxStoreRequest_MarshalsRecipientPeerIds|TestGM028BuildGroupInboxStoreRequestDropsBlankRecipientPeerIds' -count=1`
- PASS: `flutter analyze --no-pub lib/features/groups/application/group_offline_replay_envelope.dart lib/features/groups/application/accept_pending_group_invite_use_case.dart test/features/groups/application/group_offline_replay_envelope_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
- PASS: `dart format --set-exit-if-changed lib/features/groups/application/group_offline_replay_envelope.dart lib/features/groups/application/accept_pending_group_invite_use_case.dart test/features/groups/application/group_offline_replay_envelope_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
- PASS: `test -z "$(gofmt -l go-mknoon/node/group_inbox_test.go)"`
- PASS: scoped `git diff --check`

## Closure

`INTEGRATE-SV-014` is accepted as host/native/fake-network-only. Adjacent rows `SV-015` and later remain separate pending integration sessions.
