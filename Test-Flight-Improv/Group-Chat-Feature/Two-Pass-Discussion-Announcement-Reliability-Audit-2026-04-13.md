# Two-Pass Discussion / Announcement Reliability Audit

Date: 2026-04-13

## Scope

- Discussion and announcement group-chat reliability after the recent message-feature changes.
- Focused on test coverage versus real code behavior across Flutter client and Go transport/relay seams.
- Prioritized non-happy-path trust issues over broad roadmap ideas.

## Method

- Reviewed:
  - `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
  - `Discussion-And-Announcement-Feature-Audit.md`
  - `test-inventory.md`
- Ran two narrowed background review passes and adjudicated them against the code directly.
- Ran targeted verification:
  - `flutter test --no-pub test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart test/features/groups/application/send_group_reaction_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  - Result: green

Related pass artifact:
- `Narrowed-Discussion-Announcement-Audit-2026-04-13.md`

## Final Adjudicated Findings

- `P1` `keep` Reaction sender identity is not bound tightly enough on receive.
  - `handleIncomingGroupReaction()` validates membership with the outer `senderId`, but persists and removes reactions using the inner decrypted `payload.senderPeerId`.
  - The Go side emits both pieces separately, and the Flutter side never asserts that they match.
  - That leaves a real trust seam: a mismatched inner payload can poison who appears to have reacted, or whose reaction gets removed, without any test catching it.
  - Evidence:
    - `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
    - `go-mknoon/node/pubsub.go`
    - `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`

- `P1` `keep` Degraded invite acceptance does not own the durable `member_joined` contract.
  - `acceptPendingGroupInvite()` only publishes and persists the readable join event in the `HandleGroupInviteResult.success` branch.
  - In the `bridgeError` branch, the pending invite row is cleared and the group is kept locally, but no durable join event is published or queued for later ownership.
  - Current tests prove the success path and the degraded local-warning path separately, but they do not prove that existing members still get the durable join timeline in the degraded accept case.
  - Evidence:
    - `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
    - `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
    - `test/features/groups/integration/invite_round_trip_test.dart`

- `P2` `downgrade` Group reaction replay durability is still best-effort rather than owned.
  - Reaction add/remove replay storage is fire-and-forget or best-effort; the sender can see success while offline peers miss that reaction if relay storage fails.
  - I am not promoting this to a release-blocking correctness gap because live reaction delivery, local persistence, and replay happy paths are already covered, and the current code may be intentionally trading durability for simplicity.
  - It is still worth tracking because the current green unit tests do not prove the failure path; in the focused run, `send_group_reaction_use_case_test.dart` still logged `GROUP_REACTION_INBOX_STORE_FAILED` while the use case returned success.
  - Evidence:
    - `lib/features/groups/application/send_group_reaction_use_case.dart`
    - `lib/features/groups/application/remove_group_reaction_use_case.dart`
    - `test/features/groups/application/send_group_reaction_use_case_test.dart`
    - `test/features/groups/integration/group_resume_recovery_test.dart`

## Test Additions Worth Landing

- Add a receive-side reaction test where outer `senderId` and decrypted `payload.senderPeerId` differ, and assert the event is rejected.
- Add a degraded invite-accept test that proves the `bridgeError` path still results in one durable `member_joined` timeline event for existing members, or explicitly proves a recovery owner takes responsibility later.
- If offline reaction truth is part of the release contract, add a failure-owner test for reaction replay storage and retry; otherwise document reaction replay as best-effort so the matrix does not over-claim it.

## Concerns Reviewed But Not Promoted

- I looked at reaction behavior around dissolved/read-only groups and reaction cutoff parity with removed members.
- Those seams are worth a later focused pass, but I did not promote them here because the current product contract is not explicit enough to call them definite regressions without overreaching.
