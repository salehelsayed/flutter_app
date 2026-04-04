# Libp2p Group Chat Test Matrix with Coverage Rules

## Scope

This file reviews your group-chat journeys, keeps the strong flows you already identified, adds the meaningful missing ones, and maps each journey to the right automation layers without forcing all five layers on every test.

## Actors

- **A** = group creator or current admin
- **B** = regular member
- **C** = regular member or the member being removed and later re-added
- **D** = newly added member
- **X** = non-member or unauthorized peer

## Priority guide

- **P0** = release-blocking; core correctness, permissions, cryptographic access, and data integrity
- **P1** = important; should be covered before broad rollout
- **P2** = optional or feature-dependent; cover if the feature exists


## Minimum group settings and permissions

These are the baseline settings your product should support before broad rollout:

- Admin can add members.
- Only admin can remove members.
- Admin can promote other members to admin.
- Admin can re-invite a removed member.
- Only the allowed role can edit group info such as name, picture, and description.
- Members can leave the group.
- Per-group mute is supported.
- Member list shows admin badges.
- Removing a member shows a confirmation dialog.
- Removed members see a clear removed-state message.
- The group cannot end up with zero admins.
- Optional features, if supported: admin demotion, explicit invite accept/decline, admins-only send mode, group dissolve/deletion.

## Current repo execution note (2026-04-04)

Use this note when turning this matrix into repo-local work in `flutter_app`:

- Landed current Flutter-owned scope:
  admin add/remove, re-invite bootstrap, announcement admin-only send,
  member-list sync, leave-group behavior, key rotation and rejoin recovery, and
  group notification-open routing all have repo-local code and tests.
- Not currently landed as repo-local product features:
  admin promotion/transfer or demotion flows, editable group metadata after
  creation, per-group mute, and explicit invite accept/decline. Treat those row
  clusters as explicit follow-up or out-of-scope until the product implements
  them.
- Repo-external or split-boundary proof:
  raw non-member rejection, some protocol-layer authorization checks, and
  ciphertext-level post-removal decrypt proof depend on validator, bridge, or
  crypto-harness evidence in addition to Flutter-owned tests.
- Execution rule for this matrix:
  do not treat every row as an immediate missing Flutter regression. First
  classify each row cluster as current Flutter-owned scope, repo-external proof,
  or unsupported product scope.


## Coverage policy used in this matrix

### Coverage legend

- **Required** = should exist for this journey before you treat the feature as production-ready.
- **Recommended** = high-value coverage, but not mandatory for every release gate.
- **N/A** = do not force this layer for this journey.

### Rules

**Unit**  
Use for logic-heavy pieces:
- role checks
- dedupe
- replay protection
- epoch/key rotation
- notification suppression after removal
- unread counter logic
- state transitions such as `removed -> rejoined`

**Integration**  
Use for most journeys:
- add/remove member
- promote admin
- re-invite
- send/receive
- notification behavior
- metadata sync

**Smoke**  
Keep this small and release-blocking:
- create group
- online fan-out
- add member
- remove member
- removed member blocked
- re-invite works
- admin promotion works

**Fake Network**  
Use where the network behavior is the main risk:
- retries
- duplicates
- offline recipient
- reconnect
- relay/store-and-forward
- partition healing
- removal boundary
- queued delivery after removal
- concurrent admin changes

**3-party E2E (3 simulators)**  
Use for user-visible A/B/C flows:
- A sends and B/C receive
- A removes C
- C stops receiving/sending
- A re-invites C
- B gets promoted to admin
- notification deep-link behavior
- member list and role badges sync across devices

### Matrix interpretation

- **Integration** is marked **Required** across this matrix because every row here is a meaningful multi-component behavior.
- Optional P2 rows still assume the feature exists. If the feature does not exist in your product, mark that row **Out of Scope** in your tracker rather than forcing the test.
- Some security rows have **Recommended** 3-party E2E coverage only because they usually need a debug client, raw protocol hooks, or additional observability to assert correctly.
- Rows that depend on unsupported admin-role features, editable metadata,
  per-group mute, or repo-external validator/ciphertext proof should be
  classified explicitly during rollout rather than silently treated as missing
  Flutter-only test work.


## Missing journeys added in this revision

Compared with the earlier version, this revision explicitly adds a few important gaps:

- **MR-007B**: canceling the remove-member confirmation keeps membership unchanged.
- **SC-017**: duplicate membership or role events are idempotent.
- **SC-018**: older membership or role events cannot roll back newer state.

It also keeps the earlier additions that matter for libp2p group chat:
- sequential same-sender ordering
- offline bootstrap for newly added or re-added members
- invalid target handling such as add-existing, remove-non-member, and promote-non-member
- protocol-level authorization checks, not just UI checks
- key or epoch rotation on removal and re-invite
- store-and-forward cut-off after removal
- membership and message boundary ordering around removal
- concurrent admin-change convergence
- optional feature coverage such as demotion, invites, multi-device sync, dissolve, and admins-only send mode


## Core Group Messaging


| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| GM-001 | Create group successfully | A is authenticated/authorized to create groups; B and C are valid peers. | 1. A creates a group with B and C. 2. B and C sync group state. | Group is created once; A/B/C see the same group ID, member list, and admin list. | P0 | Recommended | Required | Required | N/A | Required | Covered on 2026-04-04 by `test/features/groups/integration/group_messaging_smoke_test.dart`, which now asserts shared group id plus aligned member/admin state across A/B/C before send. |
| GM-002 | Create/add with offline member bootstrap | A can add members; C is offline during creation or add. | 1. A creates the group or adds C while C is offline. 2. C reconnects. | C receives the group state/invite on reconnect and can participate according to product rules. | P1 | Recommended | Required | N/A | Required | Required | Partial on 2026-04-04: the repo proves offline invite fallback, invite bootstrap persistence, inbox drain after join, and post-bootstrap participation, but there is still no single offline-add-then-reconnect end-to-end regression that closes this exact row. |
| GM-003 | Online fan-out | A, B, and C are in the same group and online. | 1. A sends a message to the group. | B and C receive the message; A sees local success state. | P0 | Recommended | Required | Required | Recommended | Required | Covered on 2026-04-04 by the existing opening scenario in `test/features/groups/integration/group_messaging_smoke_test.dart`, which proves A/B/C are online in the same group, B and C receive A's message, and A retains the local successful outgoing copy; `test/features/groups/application/send_group_message_use_case_test.dart` separately proves sender-local send success. |
| GM-004 | Exactly-once display | A, B, and C are online; dedupe is enabled. | 1. A sends one message. 2. Observe B and C timelines. | Each recipient sees exactly one copy; no duplicate UI entries. | P0 | Required | Required | N/A | Required | Required | Covered on 2026-04-04 by the existing opening scenario in `test/features/groups/integration/group_messaging_smoke_test.dart`, which proves that after one send from A, Bob has exactly one incoming message and Charlie has exactly one incoming message; no GM-004-specific code or test delta landed after that green smoke run. |
| GM-005 | Reply fan-out | A, B, and C are online; group has a prior message. | 1. B replies to A’s message in the group. | A and C receive the reply once; reply links to the correct parent message. | P0 | Recommended | Required | N/A | Recommended | Required | Covered on 2026-04-04 by the widened quoted-reply scenario in `test/features/groups/integration/group_messaging_smoke_test.dart`, which now includes Charlie and proves Alice and Charlie each receive Bob’s quoted reply exactly once with the correct `quotedMessageId`, while Bob retains the local outgoing quoted reply with the same parent id; `test/features/groups/application/send_group_message_use_case_test.dart` keeps the quoted-message send seam green. |
| GM-006 | Sequential same-sender ordering | A, B, and C are online. | 1. A sends M1 then M2 in order. | B and C display M1 before M2 according to the app’s ordering rule. | P1 | Required | Required | N/A | Required | Required | Partial on 2026-04-04: storage and UI ordering are chronological by timestamp and existing smoke coverage observes ordered incoming texts, but `09-network-group-messaging.md` still records ordering as best-effort and the repo lacks one exact same-sender M1->M2 proof for both recipients. |
| GM-007 | Simultaneous send | A, B, and C are online. | 1. A and B send at nearly the same time. | C receives both messages; neither is lost or merged incorrectly. | P0 | Recommended | Required | N/A | Required | Required | Covered on 2026-04-04 by the new simultaneous-send smoke scenario in `test/features/groups/integration/group_messaging_smoke_test.dart`, which uses `Future.wait` for Alice and Bob sends and proves Charlie receives both distinct incoming messages with two unique message ids and no loss. |
| GM-008 | Retry without duplicates | Connectivity is unstable; dedupe is enabled. | 1. A sends a message. 2. A retries after timeout/reconnect. | B and C still show one copy; sender state resolves cleanly. | P0 | Required | Required | N/A | Required | Recommended | Covered on 2026-04-04 by the widened `failed message retry after network recovery` scenario in `test/features/groups/integration/group_resume_recovery_test.dart`, which now includes Charlie and proves the retried message resolves from `failed` to `sent` while Bob and Charlie each store exactly one incoming copy of the same retried message id after recovery. |
| GM-009 | Offline recipient receives later | C is offline; A and B are online. | 1. A sends a group message. 2. C reconnects later. | B receives immediately; C receives once after reconnect/store-and-forward. | P0 | Recommended | Required | N/A | Required | Required | Covered on 2026-04-04 by the tightened `partial delivery with inbox drain completion` scenario in `test/features/groups/integration/group_resume_recovery_test.dart`, which now asserts the online reader has the message before any offline drain, the offline readers have none before drain, and each offline reader receives exactly one copy after inbox drain completes. |
| GM-010 | Background notification | B’s app is backgrounded; notifications are enabled. | 1. A sends a group message. | B gets one notification for the correct group. | P0 | Recommended | Required | N/A | N/A | Required | Covered on 2026-04-04 at the repo-owned local notification seam by `test/features/push/application/show_notification_use_case_test.dart`, where `keeps group payload contract for local group notifications` runs with `AppLifecycleState.paused`, asserts exactly one notification, and verifies the `group:group-123` payload plus sender/body fields; the same file's `shows notification when app is backgrounded` keeps the background lifecycle path green. This row does not claim GM-011 tap routing or external push-transport proof. |
| GM-011 | Notification deep link | B received a group notification. | 1. B taps the notification. | App opens the correct group and lands on the relevant message context. | P1 | Required | Required | N/A | N/A | Required | Open on 2026-04-04: current push-open coverage proves the app routes to the correct group only after targeted group catch-up, but the route model has no message anchor and the repo does not currently prove landing on the relevant message context. |
| GM-012 | App restart recovery | Group has recent messages. | 1. Exchange messages. 2. Force close and reopen app. | History reloads correctly; last-message preview and unread state remain consistent. | P0 | Recommended | Required | N/A | N/A | Required | Covered on 2026-04-04 by the tightened `message is received after app restart with rejoin` scenario in `test/features/groups/integration/group_messaging_smoke_test.dart`, which now asserts Bob still has two persisted incoming messages after restart, unread count remains `2`, and the latest thread summary points to `After restart`. |
| GM-013 | Mixed delivery paths | One recipient is direct; another uses relay/store-and-forward. | 1. A sends a group message. | Both recipients receive the same message once despite different transport paths. | P0 | Recommended | Required | N/A | Required | Recommended | Covered on 2026-04-04 by the existing `partial delivery with inbox drain completion` scenario in `test/features/groups/integration/group_resume_recovery_test.dart`, which already proves one online reader receives the message before inbox drain while offline readers receive the same message exactly once after inbox drain completes; that mixed live plus inbox-backed proof satisfies this row at the repo-owned seam without reopening GM-014 partial-fanout wording. |
| GM-014 | Partial fan-out | One member is temporarily unreachable. | 1. A sends a group message to a 3+ member group. | Reachable members receive immediately; unreachable member receives later if supported; send is not marked globally failed because one peer was unavailable. | P0 | Recommended | Required | N/A | Required | Recommended | Covered on 2026-04-04 by the existing `partial delivery with inbox drain completion` scenario in `test/features/groups/integration/group_resume_recovery_test.dart`, which returns success with `sent` despite offline recipients, proves the online reader receives the message before inbox drain, and proves the offline readers each receive exactly one copy after inbox drain completes; that accepted partial-delivery evidence satisfies this row without reopening GM-015 sender-disconnect semantics. |
| GM-015 | Sender disconnected behavior | A is disconnected or loses connection during send. | 1. A attempts to send a group message. | App queues correctly or fails clearly; no false ‘sent’ state and no ghost duplicates later. | P0 | Required | Required | N/A | Required | Recommended | Covered on 2026-04-04 by the existing send-failure and retry-recovery seams in `test/features/groups/application/send_group_message_use_case_test.dart` and `test/features/groups/integration/group_resume_recovery_test.dart`: `persists explicit inbox success when publish fails` proves publish failure persists the outgoing row as `failed` instead of a false `sent` state, and `failed message retry after network recovery` proves later recovery completes without duplicate recipient copies; that accepted evidence closes this sender-disconnect row without reopening broader retry or transport scope. |
| GM-016 | Network partition and reconnect | Group is split by a temporary connectivity partition. | 1. Send messages on one side. 2. Heal the partition. | Missed messages sync correctly after reconnect according to retention rules. | P1 | Recommended | Required | N/A | Required | Recommended | Partial on 2026-04-04: the repo proves a temporarily disconnected member drains missed messages and resumes live delivery after rejoin, but there is still no explicit fake-network partition/heal regression with controlled split timing and release order. |



## Membership and Role Control


| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| MR-001 | Only admin can add members | A is admin; B is non-admin; D is not in the group. | 1. A attempts to add D. 2. B attempts to add D in a separate run. | Admin add succeeds; non-admin add is blocked in UI and rejected by protocol/state validation. | P0 | Required | Required | N/A | Recommended | Required | Covered on 2026-04-04 by `test/features/groups/presentation/group_info_wired_test.dart`, which shows `Add Member` only for admins, plus `test/features/groups/application/add_group_member_use_case_test.dart`, which proves admin add succeeds and non-admin callers are rejected at the use-case seam. |
| MR-002 | Add member success | A is admin; D is a valid peer not in the group. | 1. A adds D. | D joins the group and can participate after membership/bootstrap completes. | P0 | Recommended | Required | Required | Recommended | Required | Covered on 2026-04-04 by `test/features/groups/integration/group_membership_smoke_test.dart`, whose `add member syncs every member list and the new member can participate` scenario proves the newly added member converges on the group state and can send a live message that the existing members receive. |
| MR-003 | New member cannot send before bootstrap completes | A has just added D; D has not fully synced group state/keys. | 1. D attempts to send immediately before bootstrap finishes. | App blocks send or queues it until bootstrap finishes; no invalid message is accepted by others. | P1 | Required | Required | N/A | Required | Recommended | Open on 2026-04-04: the repo proves sends work after bootstrap and fail when the group is absent, but there is still no explicit bootstrap-complete gate and `sendGroupMessage` falls back to key epoch `0` when no key is present. |
| MR-004 | Add existing member handled cleanly | D is already an active member. | 1. Admin attempts to add D again. | No duplicate member entry or duplicate system event; app returns a clear no-op/error. | P1 | Required | Required | N/A | Recommended | Recommended | Partial on 2026-04-04: `ContactPickerWired` excludes existing members from the add flow and the direct add-member use case upserts duplicate peerIds into one member row, but the repo does not yet prove a clear no-op/error outcome or duplicate system-event suppression for this row. |
| MR-005 | Member list sync after add | A adds D; B and C are existing members. | 1. A adds D. 2. B and C refresh/sync state. | All members see the same updated member list and D’s role/badge state. | P0 | Recommended | Required | N/A | Recommended | Required | Covered on 2026-04-04 by `test/features/groups/integration/group_membership_smoke_test.dart`, whose `add member syncs every member list and the new member can participate` scenario asserts admin, existing member, and newly added member all converge on the same member list and role assignments. |
| MR-006 | Only admin can remove members | A is admin; B is non-admin; C is a member. | 1. A removes C. 2. In a separate run, B attempts to remove C. | Admin removal succeeds; non-admin removal is blocked in UI and rejected by protocol/state validation. | P0 | Required | Required | Required | Recommended | Required | Covered on 2026-04-04 by `test/features/groups/presentation/group_info_wired_test.dart`, which keeps remove controls hidden for non-admins, `test/features/groups/application/remove_group_member_use_case_test.dart`, which proves non-admin callers are rejected, and `test/features/groups/integration/group_membership_smoke_test.dart`, which proves the live admin-removal path still succeeds and syncs. |
| MR-007 | Remove member confirmation | A is admin; C is a member. | 1. A chooses Remove member. | App shows confirmation text such as ‘Remove this member from the group? They will stop receiving new messages.’ Removal occurs only after confirm. | P0 | Recommended | Required | Recommended | N/A | Required | Covered on 2026-04-04 by `test/features/groups/presentation/group_info_wired_test.dart`, which now proves tapping remove opens an explicit confirmation dialog with consequence copy and that the existing removal flow only proceeds after the confirm action. |
| MR-007B | Remove member cancellation keeps membership unchanged | A is admin; C is a member. | 1. A chooses Remove member. 2. A cancels at the confirmation prompt. | C remains in the group; no removal system event is emitted; C can still send/receive and continue receiving notifications. | P1 | Recommended | Required | N/A | N/A | Required | Covered on 2026-04-04 by `test/features/groups/presentation/group_info_wired_test.dart`, whose `canceling remove member keeps membership unchanged` regression proves canceling the dialog leaves the member visible and emits no bridge or removal activity. |
| MR-008 | Remove non-member handled cleanly | C is already absent from the group. | 1. Admin attempts to remove C again. | App returns a clear no-op/error; no state corruption or misleading system event. | P1 | Required | Required | N/A | Recommended | Recommended | Partial on 2026-04-04: the remove-member use case appears tolerant of an already absent member because it snapshots the target and rebuilds config from remaining members, but there is still no direct non-member-remove regression and no asserted user-facing no-op/error contract. |
| MR-009 | Removed member loses send permission | C was removed from the group. | 1. C attempts to send a group message. | Send is blocked locally or rejected by protocol; remaining members do not receive the message. | P0 | Required | Required | Required | Required | Required | Covered on 2026-04-04 by `test/features/groups/integration/group_membership_smoke_test.dart`, whose `removed member cannot send after self-removal cleanup` scenario proves the bridge-backed send returns `groupNotFound`, persists no outgoing row, and reaches no remaining member. |
| MR-010 | Removed member loses receive permission | C was removed from the group. | 1. A sends new group messages after removal. | C does not receive any post-removal group messages. | P0 | Required | Required | Required | Required | Required | Covered on 2026-04-04 by `test/features/groups/integration/group_membership_smoke_test.dart`, whose `admin removes member — removed member stops receiving messages` scenario proves the removed member keeps only pre-removal incoming traffic while remaining members continue to receive the post-removal message. |
| MR-011 | Removed member loses notifications | C was removed from the group; notifications were previously enabled. | 1. A sends new group messages after removal. | C does not receive new notifications for that group. | P0 | Required | Required | N/A | Recommended | Required | Covered on 2026-04-04 by `test/features/groups/application/group_message_listener_test.dart`, whose `does not notify after self-removal deletes the group` scenario proves self-removal triggers local cleanup and suppresses later notifications for that group. |
| MR-012 | Removed member is notified | C was removed from the group. | 1. C syncs local state after removal. | C sees a clear local notice such as ‘You were removed from this group’ and input is disabled or the group is archived/hidden per product rule. | P0 | Required | Required | Recommended | Recommended | Required | Covered on 2026-04-04 by `test/features/groups/presentation/group_conversation_wired_test.dart`, whose `current group removal shows a notice and exits the conversation route` scenario proves the user sees `You were removed from this group.` and is navigated out of the deleted conversation. |
| MR-013 | Remaining members see removal system event | A removes C; B remains in group. | 1. A removes C. 2. B views timeline/member list. | Remaining members see a system event such as ‘A removed C’ and the member list updates. | P1 | Recommended | Required | N/A | Recommended | Required | Partial on 2026-04-04: the repo broadcasts and processes `member_removed` config events so remaining members converge on the updated membership state, but system messages are explicitly not surfaced on the UI message stream, so a visible `A removed C` timeline event is not proven. |
| MR-014 | Removed while offline | C is offline when A removes C. | 1. A removes C while C is offline. 2. C reconnects later. | On reconnect, C syncs to removed state, cannot send/receive, and sees the removal notice. | P0 | Required | Required | N/A | Required | Required | Open on 2026-04-04: the current remove flow only publishes `member_removed` live through `group:publish`, and the removed-state notice depends on a live `groupRemovedStream` event, so there is still no repo-local offline catch-up path that would move a removed peer into removed state after reconnect. |
| MR-015 | Removed while typing/sending | C is composing or sending while A removes C. | 1. C starts sending. 2. A removes C before send completes. | Any post-removal message from C is rejected; remaining members do not receive unauthorized messages. | P0 | Required | Required | N/A | Required | Recommended | Open on 2026-04-04: the repo now proves post-removal send rejection after cleanup and separately proves sends are pre-persisted before publish completes, but `09-network-group-messaging.md` still records ordering as best-effort, so the remove-vs-send boundary remains an explicit open ordering gap rather than covered behavior. |
| MR-016 | Admin can promote another admin | A is admin; B is a normal member. | 1. A promotes B to admin. | B gains admin privileges and can perform admin-only actions immediately after sync. | P0 | Required | Required | Required | Recommended | Required | Unsupported on 2026-04-04: current repo docs say roles are not richly managed after creation, so admin-promotion flows are out of the landed product contract rather than missing test coverage. |
| MR-017 | Non-admin cannot self-promote | B is a normal member. | 1. B attempts to make self admin. | Action is blocked in UI and rejected by protocol/state validation. | P0 | Required | Required | N/A | Recommended | Recommended | Unsupported on 2026-04-04: current repo docs say roles are not richly managed after creation, so self-promotion checks are outside the landed product contract. |
| MR-018 | Promote non-member handled cleanly | D is not in the group. | 1. A attempts to promote D to admin. | Action fails cleanly; no phantom admin/member entry is created. | P1 | Required | Required | N/A | Recommended | Recommended | Unsupported on 2026-04-04: current repo docs keep promotion and richer role-management flows out of scope after creation, so this non-member promotion row should stay explicit product-scope debt rather than reopen feature work silently. |
| MR-019 | System event for admin promotion | A promotes B to admin. | 1. A promotes B. 2. C views group timeline/member list. | Members see a system event such as ‘A made B an admin’ and B shows an admin badge. | P1 | Recommended | Required | N/A | Recommended | Required | Unsupported on 2026-04-04: admin promotion is not a landed role-management feature in the current product, so the related system-event row remains out of scope. |
| MR-020 | At least one admin remains | There is exactly one admin in the group. | 1. Last admin attempts to leave or remove self without transfer. | Action is blocked until admin rights are transferred or another admin exists. | P0 | Required | Required | N/A | Recommended | Required | Open on 2026-04-04: `11-group-discussion-use-case-audit.md` still records that groups can become leaderless if the original admin leaves, and `leave_group_use_case.dart` still leaves unconditionally, so last-admin protection is not currently enforced in the repo-owned product contract. |
| MR-021 | Admin leave flow with multiple admins | A and B are admins. | 1. A leaves the group. | Group remains healthy with B as admin; membership updates on all peers. | P1 | Recommended | Required | N/A | Recommended | Required | Unsupported on 2026-04-04: current docs say roles are not richly managed after creation and admin transfer is missing, so there is no landed multi-admin leave contract to close here. |
| MR-022 | Member can leave group | C is a non-admin member. | 1. C leaves the group. | C can no longer send/receive group messages; remaining members see the leave event if the product shows one. | P0 | Required | Required | N/A | Recommended | Required | Covered on 2026-04-04 by `test/features/groups/integration/group_edge_cases_smoke_test.dart`, whose `leave group voluntarily — user stops receiving` scenario proves the leaving member stops receiving later traffic, plus `test/features/groups/application/leave_group_use_case_test.dart`, which proves leave cleans up local group, member, and key data. |
| MR-023 | Non-admin cannot edit group metadata | A is admin; B is non-admin. | 1. B attempts to rename the group or change picture/description. | Action is blocked in UI and rejected by protocol/state validation. | P1 | Required | Required | N/A | N/A | Required | Unsupported on 2026-04-04: post-creation metadata editing is not surfaced in the landed product, so this row stays explicit out-of-scope behavior instead of silently creating new feature work. |
| MR-024 | Admin change propagates to offline members | C is offline when A promotes B or removes D. | 1. Perform the admin/membership change. 2. C reconnects. | C syncs the latest roles/member list correctly on reconnect. | P1 | Required | Required | N/A | Required | Required | Open on 2026-04-04: the promotion/admin-change half is out of current scope, and the supported removal half still only broadcasts live through `group:publish`, with no repo proof that an offline member reconnects and syncs the updated member/admin list. |



## Re-invite and Rejoin


| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| RJ-001 | Admin can re-invite removed member | A is admin; C was previously removed. | 1. A adds C back to the group. | Re-invite succeeds and C can rejoin using fresh group state. | P0 | Required | Required | Required | Required | Required | Covered on 2026-04-04 by the new `removed member can be re-added with current state and resumes send/receive` scenario in `test/features/groups/integration/group_membership_smoke_test.dart`, together with `test/features/groups/presentation/contact_picker_wired_test.dart` proving the re-invite path sends the latest `groupKey` and `keyEpoch`, and `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart` proving invite bootstrap persists the fresh group, members, and key. |
| RJ-002 | Non-admin cannot re-invite | B is non-admin; C was previously removed. | 1. B attempts to add C back. | Action is blocked in UI and rejected by protocol/state validation. | P0 | Required | Required | N/A | Recommended | Recommended | Covered on 2026-04-04 by `test/features/groups/application/add_group_member_use_case_test.dart`, whose `rejects when caller is not admin` proof closes the permission seam used for both first-time adds and re-invites after removal. |
| RJ-003 | Re-invited member can send again | C has been re-added and completed bootstrap. | 1. C sends a new group message. | Message is accepted and delivered to current members. | P0 | Required | Required | Required | Required | Required | Covered on 2026-04-04 by `test/features/groups/integration/group_membership_smoke_test.dart`, whose `removed member can be re-added with current state and resumes send/receive` scenario proves the re-added member sends `I am back` with the current key epoch and the current members receive it. |
| RJ-004 | Re-invited member can receive again | C has been re-added. | 1. A sends a new group message after rejoin. | C receives new post-rejoin messages once. | P0 | Required | Required | Recommended | Required | Required | Covered on 2026-04-04 by `test/features/groups/integration/group_membership_smoke_test.dart`, whose `removed member can be re-added with current state and resumes send/receive` scenario proves the re-added member receives `Welcome back` after the rejoin becomes effective. |
| RJ-005 | Notifications resume after rejoin | C had been removed, then re-added; notifications are enabled. | 1. A sends a new group message after rejoin. | C receives notifications again only after rejoin becomes effective. | P1 | Required | Required | N/A | Recommended | Required | Partial on 2026-04-04: the repo proves rejoin restores current state and send/receive behavior, and it separately proves incoming group messages can raise notifications, but there is still no exact regression showing notifications stay off while removed and resume only after rejoin becomes effective. |
| RJ-006 | Rejoin clears removed state | C was previously shown as removed and is now re-added. | 1. C opens the group after successful rejoin. | Removed banner/input lock is cleared; UI shows the group as active again. | P0 | Required | Required | N/A | Recommended | Required | Covered on 2026-04-04 by `test/features/groups/integration/group_membership_smoke_test.dart`, whose `removed member can be re-added with current state and resumes send/receive` scenario proves the previously deleted group becomes active again with the current key and live send/receive restored, plus `test/features/groups/presentation/group_list_wired_test.dart`, whose `refreshes group list when groupInviteListener emits` proof covers the surfaced active-group refresh contract. The current product clears removed state by recreating the group on re-invite rather than toggling a persistent removed banner. |
| RJ-007 | System event for re-add | A re-adds C. | 1. Remaining members view timeline/member list. | Members see a system event such as ‘A added C’. | P1 | Recommended | Required | N/A | Recommended | Required | Partial on 2026-04-04: the repo broadcasts and consumes re-add config events so membership state converges, but those events are not emitted as user-visible chat or timeline messages, so a visible `A added C` system event is not proven. |
| RJ-008 | Rejoined member sees current membership and admins | C was removed, several changes happened, then C was re-added. | 1. C rejoins and syncs state. | C sees the latest member list, admin list, metadata, and current group epoch. | P0 | Required | Required | N/A | Required | Required | Covered on 2026-04-04 by `test/features/groups/integration/group_membership_smoke_test.dart`, whose `removed member can be re-added with current state and resumes send/receive` scenario asserts the rejoined member sees the latest member list, the current admin role assignments, and key epoch `2`, while `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart` keeps the invite bootstrap persistence seam green. |
| RJ-009 | Removed-period history is not exposed by default | C was removed at T1 and re-added at T2; messages exist between T1 and T2. | 1. C rejoins. 2. C tries to access messages from T1→T2. | C cannot access removed-period history unless that is an explicit product rule. | P0 | Required | Required | N/A | Required | Required | Covered on 2026-04-04 by `test/features/groups/integration/group_membership_smoke_test.dart`, whose `removed member can be re-added with current state and resumes send/receive` scenario proves the rejoined member still sees pre-removal history and new post-rejoin traffic but does not see the `During removal` message sent while they were out of the group. The current invite/rejoin bootstrap restores current state without backfilling removed-period history by default. |
| RJ-010 | Re-invite while removed member is offline | C is offline when A re-adds C. | 1. A re-adds C while C is offline. 2. C reconnects later. | C syncs rejoin state on reconnect and gains access only to allowed post-rejoin messages. | P1 | Required | Required | N/A | Required | Required | Partial on 2026-04-04: the repo proves re-invites can fall back to inbox, invite bootstrap restores group and key state, and rejoined members regain only allowed post-rejoin access, but there is still no exact offline-during-re-add then reconnect-later end-to-end regression. |



## Security, Correctness, and Convergence


| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| SC-001 | UI restrictions are not the only restrictions | A is admin; B is non-admin. | 1. B bypasses UI and submits a raw protocol/state change for add/remove/promote. | Unauthorized action is rejected by protocol/state validation; no peer applies it. | P0 | Required | Required | N/A | Required | Recommended | Open on 2026-04-04: local Flutter tests cover UI/use-case admin gating for add/remove, but inbound membership system messages are still applied without sender-role authentication in `group_message_listener.dart`, so raw bypass resistance is not closed at the repo-owned layer. Promotion flows are also not current repo-owned scope. |
| SC-002 | Unauthorized metadata changes rejected at protocol layer | B is non-admin. | 1. B bypasses UI and submits raw rename/photo/description change. | Peers reject the change; canonical metadata remains unchanged. | P1 | Required | Required | N/A | Required | Recommended | Unsupported on 2026-04-04: post-creation rename, photo, and description mutation are not landed product seams here, so this row should stay explicit unsupported scope rather than pretending current repo work merely lacks raw protocol proof. |
| SC-003 | Removed member cannot decrypt future messages | C was removed; cryptographic group messaging is enabled. | 1. A/B exchange new messages after C’s removal. 2. C intercepts/stores traffic. | C cannot decrypt any future group traffic after removal. | P0 | Required | Required | N/A | Required | Recommended | Repo-external on 2026-04-04: `test/features/groups/application/member_removal_integration_test.dart` proves the rotated key is not distributed to the removed member and the remaining member adopts the new key, but actual intercepted-ciphertext decrypt failure for the removed peer still depends on crypto-harness or captured-traffic proof outside plain Flutter tests. |
| SC-004 | Group key/epoch rotates on removal | C is a current member; encryption epoching is enabled. | 1. A removes C. 2. Members send new messages. | Post-removal messages use a new valid epoch/key state. | P0 | Required | Required | N/A | Required | Recommended | Partial on 2026-04-04: `test/features/groups/application/member_removal_integration_test.dart` and `test/features/groups/presentation/group_info_wired_test.dart` prove the remove flow rotates and distributes a new key to the remaining members, but there is still no deterministic removal-boundary test proving the first real post-removal send already uses the rotated epoch. |
| SC-005 | Group key/epoch updates correctly on re-invite | C was removed, then re-added. | 1. A re-adds C. 2. C syncs fresh state. 3. New messages are exchanged. | C receives the current epoch/key state; stale removed credentials are not reused. | P0 | Required | Required | N/A | Required | Recommended | Partial on 2026-04-04: the new rejoin smoke proves the rejoined member resumes on key epoch `2`, but that proof still injects the fresh key through the test helper. Invite handling separately proves it persists a supplied key/epoch, so the repo still lacks one deterministic remove->reinvite flow that proves fresh key issuance and no stale credential reuse end to end. |
| SC-006 | Unknown/non-member sender is rejected | X is not in the group. | 1. X sends or relays a forged group message. | Peers reject the message; no UI entry or unread counter change occurs. | P0 | Required | Required | N/A | Required | Recommended | Covered on 2026-04-04 at the validator layer by `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_test.go`, which reject non-member senders before delivery. The local Flutter handler remains permissive if a bad payload somehow bypasses that validator, so this row should be read as repo-level validator coverage, not as an app-layer fallback guarantee. |
| SC-007 | Stale client resync | A client has old cached membership/admin state. | 1. Client reconnects after offline period with group changes pending. | Client converges to the latest valid group state before sending privileged operations. | P0 | Required | Required | N/A | Required | Required | Partial on 2026-04-04: startup/watchdog rejoin and message catch-up are covered, but rejoin rebuilds from locally cached membership state and the repo still lacks a proof that offline membership/admin changes are replayed before a privileged operation. |
| SC-008 | Duplicate-path dedupe | Network can deliver the same message via multiple paths. | 1. Inject the same valid message via two routes. | UI shows one copy and state updates only once. | P0 | Required | Required | N/A | Required | Recommended | Covered on 2026-04-04 by `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, whose `deduplicates by messageId when pubsub and group inbox deliver same message` proof closes the mixed-path dedupe seam, plus `test/features/groups/integration/group_edge_cases_smoke_test.dart`, whose `duplicate delivery — GroupMessageListener handles idempotently` scenario keeps the live duplicate-delivery path green. |
| SC-009 | Tampered message rejection | A valid message is modified in transit or storage. | 1. Deliver a message with invalid signature/envelope/ciphertext. | Peers reject it; no UI entry, notification, or unread increment appears. | P0 | Required | Required | N/A | Required | N/A | Covered on 2026-04-04 by repo-level reject/drop tests in `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, and `integration_test/transport_e2e_test.dart`, which keep tampered group traffic from being received or persisted. This note does not claim a separate local unread/notification assertion beyond that drop behavior. |
| SC-010 | Replay protection | A previously valid message exists in history. | 1. Replay the same old message/envelope later. | Peers do not treat it as a new message; no duplicate timeline entry or notification. | P0 | Required | Required | N/A | Required | Recommended | Partial on 2026-04-04: replay deliveries are deduped and may only enrich sparse metadata on the existing row, but the “no duplicate notification” half is still an inference from listener control flow rather than a dedicated replay-through-notification regression. |
| SC-011 | Post-removal store-and-forward cut-off | C is removed while some peers still have queued messages for delivery. | 1. Queue messages after removal. 2. Attempt delivery to C later. | C cannot receive/decrypt any post-removal queued messages. | P0 | Required | Required | N/A | Required | Required | Open on 2026-04-04: the repo proves live post-removal receive blocking and rotated-key distribution cut-off, but there is still no direct queued-after-removal inbox-drain proof, and offline removed-state recovery remains open in `MR-014`. |
| SC-012 | Membership change ordering vs in-flight messages | A removes C around the same time A/B send new messages. | 1. Interleave removal and message sends near the boundary. | Messages are accepted or rejected according to the defined ordering/epoch rule; state converges consistently across peers. | P0 | Required | Required | N/A | Required | Recommended | Open on 2026-04-04: `Test-Flight-Improv/09-network-group-messaging.md` still records ordering as best-effort, and `MR-015` remains an explicit remove-vs-send ordering gap, so in-flight membership/message boundary behavior is not currently closed. |
| SC-013 | Concurrent admin changes converge safely | A and B are admins. | 1. A and B make different membership/role changes nearly simultaneously. | Group converges deterministically; no split-brain member/admin list. | P1 | Required | Required | N/A | Required | Recommended | Unsupported on 2026-04-04: the current product has a single effective admin path, not a supported two-admin mutation model, so concurrent admin-change convergence is outside current scope. |
| SC-014 | Conflicting add/remove of same member converges deterministically | Two admins act on C around the same time. | 1. One admin removes C while another re-adds or promotes C near-simultaneously. | All peers converge to the same final membership/role state according to conflict-resolution rules. | P1 | Required | Required | N/A | Required | Recommended | Unsupported on 2026-04-04: sequential remove/re-add behavior exists, but the exact two-admin conflicting add/remove case is outside the current single-effective-admin product contract. |
| SC-015 | Membership and role events are authenticated | A membership/role event is received from the network. | 1. Deliver valid and invalid signed membership events. | Only events authorized by the correct admin role are accepted and applied. | P0 | Required | Required | N/A | Required | N/A | Open on 2026-04-04: `lib/features/groups/application/group_message_listener.dart` applies `member_added` and `member_removed` system messages without verifying sender admin authority, so this row still depends on future signed-event or validator enforcement and is not closed by current local tests. |
| SC-016 | Local send status reflects partial success accurately | One recipient is unreachable while others receive the message. | 1. A sends a message during partial fan-out. | Sender sees accurate status (e.g., sent to group / pending for some peers) per product rule; app does not falsely report total failure if the group send is otherwise valid. | P1 | Required | Required | N/A | Required | Recommended | Covered on 2026-04-04: group send status is explicitly defined and tested as `sent` or inbox-backed success on partial fan-out and zero-peer fallback, so this row closes at the current product-rule seam. |
| SC-017 | Duplicate membership or role event is idempotent | A valid add/remove/promote/demote event exists and can be delivered more than once. | 1. Deliver the same valid membership or role event twice. | The state change is applied once; member/admin lists remain correct; no duplicate system event or duplicate badge update is shown. | P0 | Required | Required | N/A | Required | Recommended | Partial on 2026-04-04: member persistence is upsert-like and membership events are not surfaced on `groupMessageStream`, but the repo still lacks a row-owned duplicate membership/role event regression proving one canonical state change and one UI effect. |
| SC-018 | Older membership or role event cannot roll back newer state | A newer valid membership or role event has already been applied. | 1. Deliver an older valid event after the newer one. | Peers keep the latest valid state and ignore the stale event; no rollback or split-brain member/admin list occurs. | P0 | Required | Required | N/A | Required | Recommended | Open on 2026-04-04: membership system messages carry no explicit sequence/version metadata, and `group_message_listener.dart` applies them in arrival order, so stale-event rollback prevention is not currently proven and may require new ordering metadata or validator rules. |



## Metadata, Notifications, and Optional Feature Coverage


| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| UX-001 | New member history policy | D is newly added to an existing group with prior history. | 1. A adds D. 2. D opens the group. | D sees exactly the history allowed by product policy: future-only, limited recent history, or full history. | P1 | Required | Required | N/A | Recommended | Required | Partial on 2026-04-04: current behavior implies future-from-membership plus post-join inbox replay, but the repo still lacks one direct row-owned policy test that pins new-member history semantics explicitly. |
| UX-002 | Group rename | Rename feature exists; A is allowed to rename. | 1. A renames the group. | All members see the new name; non-admin behavior follows policy. | P1 | Recommended | Required | N/A | Recommended | Required | Unsupported on 2026-04-04: group rename is not surfaced after creation in the landed product, so this row should remain explicit unsupported scope. |
| UX-003 | Group picture/description update | Picture/description feature exists; A is allowed to edit. | 1. A updates group picture/description. | All members sync the new metadata and caches refresh correctly. | P2 | Recommended | Required | N/A | Recommended | Required | Unsupported on 2026-04-04: avatar, photo, and description editing are not a shipped post-creation workflow here, so this row remains unsupported scope. |
| UX-004 | Mute notifications per group | B is a current member; group notifications can be muted. | 1. B mutes the group. 2. A sends new messages. | Messages still arrive, but B receives no notifications while mute is active. | P1 | Required | Required | N/A | N/A | Required | Unsupported on 2026-04-04: there is no app-layer per-group mute flow or UI in the current product, so this row should close as unsupported scope. |
| UX-005 | Unread count correctness | Unread counters are enabled. | 1. Send several messages, including duplicates/retries/reconnects. 2. Open the group. | Unread count increments/decrements correctly and is not double-counted by duplicate deliveries. | P1 | Required | Required | N/A | Recommended | Required | Partial on 2026-04-04: unread counting and message deduplication are both covered, but the repo still lacks one row-owned regression proving unread counters stay correct across duplicate, retry, and reconnect flows end to end. |
| UX-006 | Long text / emoji / RTL / special characters | Group supports text messages. | 1. Send messages with long text, emoji, Arabic/RTL, and special characters. | Rendering, storage, notifications, and sync behave correctly without corruption. | P1 | Recommended | Required | N/A | N/A | Required | Partial on 2026-04-04: bidi sanitization and mixed RTL/LTR preview rendering are covered, but the repo still lacks one direct end-to-end row proof for long text, emoji, and special-character behavior together. |
| UX-007 | Large message or attachment | Large payloads or attachments are supported. | 1. Send a large payload/attachment. | Delivery succeeds within limits or fails cleanly with clear user feedback; no broken partial state remains. | P2 | Recommended | Required | N/A | Required | Required | Partial on 2026-04-04: attachments and durable failed-media recovery are real and tested, but the repo does not yet prove a large-payload or explicit size-limit contract for this row. |
| UX-008 | Store-and-forward expiry / retention boundary | Offline retention/TTL exists. | 1. Keep C offline past the retention boundary. 2. Send messages. 3. C reconnects. | Behavior matches policy: expired messages are unavailable with clear UX, and newer retained messages sync normally. | P2 | Recommended | Required | N/A | Required | Recommended | Contract-undefined on 2026-04-04: store-and-forward replay exists, but the current repo does not define or prove a retention or TTL expiry boundary for group messages. |
| UX-009 | Max group size limit | A configured or product max group size exists. | 1. Add members until limit is reached. 2. Try to add one more. | Add beyond limit fails cleanly with clear feedback; existing group remains healthy. | P2 | Required | Required | N/A | N/A | N/A | Contract-undefined on 2026-04-04: the repo documents scale targets and profiling ranges, not a hard max-group-size enforcement rule, so this row remains unscoped rather than covered. |
| UX-010 | Member list consistency after reconnect | Multiple peers reconnect after different offline periods. | 1. Apply several membership/role changes. 2. Reconnect all peers. | All peers converge to the same final member/admin list and metadata. | P1 | Required | Required | N/A | Required | Required | Partial on 2026-04-04: member-list convergence after add, remove, and restart exists, but the exact reconnect-after-membership-churn comparison across all peers is still only partially covered. |
| UX-011 | Admin demotion / revoke admin | Admin demotion feature exists. | 1. A demotes B from admin to member. | B immediately loses admin-only permissions; peers show updated role/system event per product rule. | P2 | Required | Required | N/A | Recommended | Required | Unsupported on 2026-04-04: admin promotion and demotion are not shipped role-management flows in this product, so this row should remain unsupported scope. |
| UX-012 | Invite accept / decline / expiry | Your product uses explicit invites instead of immediate add. | 1. A invites D. 2. D accepts, declines, or lets invite expire in separate runs. | Each path behaves predictably: accept joins, decline does not join, expiry invalidates the invite without ghost membership. | P2 | Required | Required | N/A | Recommended | Required | Unsupported on 2026-04-04: invites are auto-processed on receipt with no accept, decline, or expiry state machine, so this row is outside the landed product contract. |
| UX-013 | Multi-device state convergence | A user can be signed in on multiple devices. | 1. Use two devices for the same user. 2. Apply membership, mute, and message changes. | Both devices converge to the same group state, notifications, and unread counters per product rule. | P2 | Required | Required | N/A | Recommended | Recommended | Contract-undefined on 2026-04-04: current repo proof is multi-peer convergence only, with no same-user multi-device contract or regression to close this row honestly. |
| UX-014 | Group dissolve / deletion | Group deletion/dissolve feature exists. | 1. Allowed actor dissolves/deletes the group. | All members see the correct final state; no one can send to the dissolved group afterward. | P2 | Required | Required | N/A | Recommended | Required | Unsupported on 2026-04-04: the product supports leaving or local deletion, not an admin-initiated group dissolve workflow, so this row should remain explicit unsupported scope. |
| UX-015 | Admin-only send / announcement mode | Your product supports an admins-only send mode. | 1. Admin enables admins-only send. 2. B tries to send. 3. A sends. | B is blocked from sending; admin messages continue to work; all peers show the correct mode/state. | P2 | Required | Required | N/A | Recommended | Required | Covered on 2026-04-04: announcement/admin-only send is a landed feature with direct auth, UI, and end-to-end proof in `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, and `test/features/groups/integration/announcement_happy_path_test.dart`. |



## Recommended smoke suite

These are the journeys marked **Smoke = Required** in the matrix:

- **GM-001** — Create group successfully
- **GM-003** — Online fan-out
- **MR-002** — Add member success
- **MR-006** — Only admin can remove members
- **MR-009** — Removed member loses send permission
- **MR-010** — Removed member loses receive permission
- **RJ-001** — Admin can re-invite removed member
- **RJ-003** — Re-invited member can send again

Useful extras if you want a slightly larger smoke suite:

- **MR-007** — Remove member confirmation
- **MR-012** — Removed member is notified
- **RJ-004** — Re-invited member can receive again

## Notes for implementation

- For every permission journey, verify both layers: the UI blocks the action and the protocol or state-validation layer rejects any bypass attempt.
- For removal and re-invite, assert the group epoch or key before and after the change, not only the visible UI behavior.
- For dedupe, verify there is no duplicate timeline item, notification, unread increment, or persisted message row.
- For fake-network tests, make delivery ordering, retry windows, partitions, reconnect timing, and queued-message release deterministic.
- For 3-simulator E2E, collapse roles when needed. Example: A = admin, B = existing member, C = target member being added, removed, or re-invited.
