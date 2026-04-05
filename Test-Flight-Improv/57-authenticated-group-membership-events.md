# Authenticated Group Membership Events

## 1. Title and Type

- Title: Authenticated membership and role events for group state changes
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/57-authenticated-group-membership-events.md`

## 2. Problem Statement

- Group membership changes are user-visible trust boundaries: add, remove, and role updates should only be accepted when they come from an authorized actor.
- The current Flutter listener applies membership system events without validating sender authority at the app-owned layer.
- From a user perspective, that means UI restrictions are not enough: a forged or unauthorized membership event could be processed even though the actor should not be allowed to change the group.

## 3. Impact Analysis

- Affects admins, regular members, and any peer consuming group config-change events.
- Appears whenever membership or role system messages are delivered from the network or replayed through local handling.
- Severity is high because unauthorized membership changes would undermine the trust model of group admin actions.
- The current rollout remains blocked on this gap for both `SC-001` and `SC-015` in the group gap matrix.

## 4. Current State

- `lib/features/groups/application/group_message_listener.dart` handles `member_added`, `members_added`, and `member_removed` system messages and persists their effects.
- In the current listener path, the handler uses `senderId` and `senderUsername` for timeline text and bookkeeping, but it does not verify admin authority before applying the membership change.
- The in-scope matrix keeps both `SC-001` and `SC-015` open in `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`.
- Current test coverage in `test/features/groups/application/group_message_listener_test.dart` exercises duplicate handling, stale-event handling, timeline emission, and removal behavior, but the gap matrix still says authenticated sender-role enforcement is not closed.
- Adjacent use-case tests in:
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
  prove UI/use-case gating for local actions, but they do not close raw inbound membership-event authorization by themselves.

## 5. Scope Clarification

- In scope:
  - user-visible correctness that only authorized membership or role events are applied
  - rejection behavior for unauthorized inbound membership events
  - preservation of valid authorized membership-event handling
- Not in scope:
  - unsupported promotion or demotion product flows beyond the repo-owned contract
  - broad cryptographic redesign outside the user-visible authorization requirement
  - unrelated messaging or notification behavior
- Accepted ambiguity for the later implementation pass:
  - this spec does not choose whether enforcement should live in the validator, signed-event payloads, the Flutter listener, or a combination; it only requires that unauthorized events not be applied

## 6. Test Cases

### Happy Path

- A valid membership-removal event from an authorized admin is accepted and applied, and peers converge on the expected member list update.
- A valid membership-add event from an authorized admin is accepted and applied, and peers converge on the expected member list update.

### Edge Cases

- An inbound unauthorized remove event from a non-admin is rejected, and no peer updates the member list or timeline as if the action succeeded.
- An inbound unauthorized add event from a non-admin is rejected, and no new member becomes active from that event.
- If a valid authorized event is followed by an older unauthorized event, the unauthorized event does not roll back the newer valid state.
- Replayed duplicate authorized events remain idempotent and do not create duplicate UI side effects.

### Bug Regression

- If a non-admin bypasses UI restrictions and injects a raw membership-change event, the app must reject it and keep the canonical membership state unchanged across peers.

### Regressions To Preserve

- Existing authorized add/remove flows that already work through the local admin-owned paths must continue to work.
- Existing duplicate-event and stale-event protections must keep working after membership-event authentication lands.

