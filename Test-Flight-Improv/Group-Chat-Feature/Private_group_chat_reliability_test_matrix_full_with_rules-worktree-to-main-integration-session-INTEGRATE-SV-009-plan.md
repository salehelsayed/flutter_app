# INTEGRATE-SV-009 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `SV-009` from the full-with-rules worktree into main: malformed member signing, ML-KEM, device-signing, device ML-KEM, or key-package public material must be rejected before add/join/config state can become active.

This is standard worktree-to-main integration, not new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-009-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: partial. Current main already rejected no-delivery identities and invalid join material, but did not reject malformed member key-material strings before local add persistence, invite materialization, listener membership/config mutation, or native join/config acceptance.
- Imported delta: only missing SV-009 row-owned key-material validation helpers, add/join/invite/listener/native bridge guards, and row-owned host proof selectors.
- Current-main adaptation: source peer-id canonicalization and duplicate-peer variant helpers from later SV rows were intentionally not imported; SV-009 stayed limited to malformed key material.
- Live proof: not required. Source 3-Party E2E is `N/A`; no iOS 26.2 simulator proof is claimed.

## Imported Artifacts

- `lib/features/groups/domain/models/group_member.dart`
  - key-material rejection helpers for group members and group config members.
- `lib/features/groups/application/add_group_member_use_case.dart`
  - rejects malformed member key material before persistence or `group:updateConfig`.
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - rejects malformed invite group-config member key material before active state.
- `lib/features/groups/application/join_group_use_case.dart`
  - rejects malformed full-config member key material before bridge join.
- `lib/features/groups/application/group_message_listener.dart`
  - rejects malformed `member_added`, `members_added`, and authoritative config snapshots before local mutation or bridge config sync.
- `go-mknoon/bridge/bridge.go`
  - rejects malformed member key material in native `group:join` and `group:updateConfig`.
- `go-mknoon/bridge/bridge_test.go`
  - `TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys`
- `test/features/groups/application/add_group_member_use_case_test.dart`
  - `SV-009 malformed member key material is rejected before add or config sync`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  - `SV-009 rejects invite member key material before join state is active`
- `test/features/groups/application/group_message_listener_test.dart`
  - `SV-009 malformed membership key material is rejected without state or config sync`
- `test/features/groups/integration/group_membership_smoke_test.dart`
  - `SV-009 malformed member keys never activate and later valid add still syncs`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Verification

- PASS: `gofmt -w go-mknoon/bridge/bridge.go go-mknoon/bridge/bridge_test.go`
- PASS: `dart format --set-exit-if-changed lib/features/groups/domain/models/group_member.dart lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/handle_incoming_group_invite_use_case.dart lib/features/groups/application/join_group_use_case.dart lib/features/groups/application/group_message_listener.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
- PASS: `cd go-mknoon && go test ./bridge -run TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys -count=1`
- PASS: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name "SV-009"`
- PASS: `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name "SV-009"`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "SV-009"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "SV-009"`
- PASS: `dart analyze lib/features/groups/domain/models/group_member.dart lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/handle_incoming_group_invite_use_case.dart lib/features/groups/application/join_group_use_case.dart lib/features/groups/application/group_message_listener.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
- PASS: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name "BB-006"`
- PASS: `flutter test --no-pub test/features/groups/application/join_group_use_case_test.dart --plain-name "BB-006"`
- PASS: `cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic_BB006RejectsLegacyTopicNameOnlyPayload|TestGroupJoinTopic_WithInviteData|TestGroupUpdateConfig_WithNewMember' -count=1`
- PASS: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name "GM-002"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "GM-002"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "GM-003"`
- PASS: `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name "accepts pending invite, persists group, and drains inbox"`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name "GM-011|GM-012|GM-013|GM-014|unauthorized member_added|unauthorized members_added|SV-008 unauthorized config update payloads leave state and bridge unchanged"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --name "GM-011|GM-012|GM-013|GM-014|ML-013|SV-008"`
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name "GM-002|GM-003|GM-011|GM-012|GM-013|GM-014|SV-008"`
- PASS: `git diff --check`

## Closure

`INTEGRATE-SV-009` is accepted as host-only. Adjacent rows `SV-010` and later remain separate pending integration sessions.
