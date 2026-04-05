# 1. Title and Type

- Title: Group Notification Mute and Invite Decision Controls
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls.md`
- Matrix rows: `UX-004`, `UX-012`

# 2. Problem Statement

- Users currently receive group-notification behavior without any per-group mute control, and incoming group invites are auto-processed once sender/contact checks pass instead of being presented as an explicit accept, decline, or expiry decision.
- This means members cannot silence one noisy group without relying on broader notification suppression rules, and invite recipients cannot choose whether to join before the group is persisted locally.
- The missing product contract leaves both notification preference control and invite-decision lifecycle as unsupported journeys even though the underlying notification and invite plumbing already exists.

# 3. Impact Analysis

- Affects members who participate in several groups with different notification expectations.
- Affects invite recipients who need agency over whether to join immediately, postpone, decline, or allow an invite to expire.
- The notification gap appears in normal day-to-day usage, while the invite-decision gap appears any time group membership should be intentional rather than automatic.
- Today’s behavior can feel surprising: messages may notify correctly under current rules, but there is no per-group mute preference, and a valid invite can create a group locally without an explicit user decision step.

# 4. Current State

- Group notifications are already emitted by `GroupMessageListener` and are suppressed only by conditions such as own-message checks, active-conversation tracking, recent remote-push de-dupe, and self-removal cleanup. There is no repo-local per-group mute state or mute UI flow in current group code/tests. Evidence: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Existing notification tests prove current behavior such as showing notifications for incoming messages, suppressing duplicates, suppressing while viewing the active group, and suppressing after self-removal. They do not cover a member-controlled per-group mute preference. Evidence: `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`
- Incoming group invites are processed automatically once received by `GroupInviteListener`: the listener hands the payload to `handleIncomingGroupInvite`, persists the group/members/key on success, joins the topic, drains the offline inbox, and broadcasts the joined group to the UI. There is no explicit accept, decline, or expiry state machine in the current product. Evidence: `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `test/features/groups/application/group_invite_listener_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`
- Current invite handling already distinguishes unknown sender, duplicate group, invalid payload, and decryption failure, which shows there is safety validation today even though there is no explicit user decision surface. Evidence: `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- Existing audit docs explicitly call out both gaps: no app-layer group mute flow and no strong invite expiry semantics. Evidence: `Test-Flight-Improv/11-group-discussion-use-case-audit.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`

# 5. Scope Clarification

- In scope:
  - a member-facing per-group mute contract that changes notification behavior without breaking delivery
  - an explicit group-invite decision lifecycle covering accept, decline, and expiry outcomes
  - user-visible outcomes for what happens before acceptance, after decline, and after expiry
  - preservation of current invite and notification safety behavior where still applicable
- Explicit non-goals:
  - redesigning the global notification system
  - redesigning contacts/blocking logic beyond the current invite sender checks
  - changing ordinary message delivery semantics for members who stay unmuted
- Accepted ambiguities for the later implementation pass:
  - exact mute choices such as indefinite mute versus timed mute
  - exact invite expiry window and copy
  - exact UI surface where pending invites are reviewed or actioned

# 6. Test Cases

## Happy Path

- A member mutes a specific group, new group messages still arrive and remain readable, but that member stops receiving notifications for that group while mute is active.
- A member later un-mutes the same group, and normal notification behavior resumes for future messages.
- An invited user explicitly accepts a valid invite, joins the group, and then sees the same membership/message recovery behavior expected for a successful join.

## Edge Cases

- Declining a valid invite does not create ghost group membership, does not join the topic, and does not leave behind a misleading joined-group surface.
- Letting an invite expire produces a clear non-joined outcome and does not create ghost membership or reusable stale invite state.
- A duplicate invite for an already joined group stays safe and predictable under the new explicit-decision contract.
- An invite from an unknown or blocked sender remains rejected under the same safety rules that apply today.
- A muted group still increments whatever non-notification state the product chooses to preserve, such as unread indicators, instead of silently dropping message delivery.

## Regressions To Preserve

- Existing notification suppression while viewing the active group conversation keeps working.
- Existing duplicate-notification suppression and remote-push de-dupe keep working for groups that are not muted.
- Existing invite cryptography, sender validation, duplicate-group rejection, and offline inbox recovery remain intact once a user actually accepts an invite.
