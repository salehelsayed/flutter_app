# Narrowed Discussion / Announcement Audit

Date: 2026-04-13

Scope for this pass:
- group reaction send / receive / replay paths
- degraded invite-accept recovery
- only concrete code gaps or test gaps that affect reliability

Focused verification run:
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart test/features/groups/application/send_group_reaction_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- Result: green

## Verdict on pass-1 findings

- `downgrade` `Group reaction replay durability is still best-effort, not owned` - The code really does treat replay storage as best-effort, but the live reaction path, local persistence, and replay happy path are already covered, so this is weaker than a release-blocking gap. It is a reliability concern, not a correctness contradiction. References: [`lib/features/groups/application/send_group_reaction_use_case.dart`](../../lib/features/groups/application/send_group_reaction_use_case.dart:131), [`lib/features/groups/application/remove_group_reaction_use_case.dart`](../../lib/features/groups/application/remove_group_reaction_use_case.dart:92), [`test/features/groups/application/send_group_reaction_use_case_test.dart`](../../test/features/groups/application/send_group_reaction_use_case_test.dart), [`test/features/groups/integration/group_resume_recovery_test.dart`](../../test/features/groups/integration/group_resume_recovery_test.dart:1386).

- `keep` `Incoming group reaction sender identity is not cross-checked against the decrypted payload` - The outer envelope sender is used for membership validation, while the inner decrypted `payload.senderPeerId` is what gets stored and replayed. That leaves a real trust seam if a malformed or buggy event reaches this layer. The current tests only prove the stale-member-list case, not the mismatch case. References: [`lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`](../../lib/features/groups/application/handle_incoming_group_reaction_use_case.dart:61), [`lib/features/groups/application/send_group_reaction_use_case.dart`](../../lib/features/groups/application/send_group_reaction_use_case.dart:94), [`go-mknoon/node/pubsub.go`](../../go-mknoon/node/pubsub.go:242), [`test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`](../../test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart:157).

- `keep` `Degraded invite acceptance does not guarantee a durable member_joined event` - `acceptPendingGroupInvite()` only persists and publishes the join timeline on the success branch. When `bridgeError` happens, the invite row is removed and the group is kept locally, but the durable join event is skipped. Later rejoin recovery is tested, but the degraded path itself is still not owning the timeline contract. References: [`lib/features/groups/application/accept_pending_group_invite_use_case.dart`](../../lib/features/groups/application/accept_pending_group_invite_use_case.dart:95), [`test/features/groups/application/accept_pending_group_invite_use_case_test.dart`](../../test/features/groups/application/accept_pending_group_invite_use_case_test.dart:232), [`test/features/groups/integration/invite_round_trip_test.dart`](../../test/features/groups/integration/invite_round_trip_test.dart:1445).

## New Findings

- None. The remaining reaction and invite paths already have enough coverage for the scope of this pass.
