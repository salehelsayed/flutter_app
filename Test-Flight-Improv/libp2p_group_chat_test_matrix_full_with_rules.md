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
| GM-001 | Create group successfully | A is authenticated/authorized to create groups; B and C are valid peers. | 1. A creates a group with B and C. 2. B and C sync group state. | Group is created once; A/B/C see the same group ID, member list, and admin list. | P0 | Recommended | Required | Required | N/A | Required |  |
| GM-002 | Create/add with offline member bootstrap | A can add members; C is offline during creation or add. | 1. A creates the group or adds C while C is offline. 2. C reconnects. | C receives the group state/invite on reconnect and can participate according to product rules. | P1 | Recommended | Required | N/A | Required | Required | Use C as the offline invitee or added member; reconnect C after the add/create step. |
| GM-003 | Online fan-out | A, B, and C are in the same group and online. | 1. A sends a message to the group. | B and C receive the message; A sees local success state. | P0 | Recommended | Required | Required | Recommended | Required |  |
| GM-004 | Exactly-once display | A, B, and C are online; dedupe is enabled. | 1. A sends one message. 2. Observe B and C timelines. | Each recipient sees exactly one copy; no duplicate UI entries. | P0 | Required | Required | N/A | Required | Required |  |
| GM-005 | Reply fan-out | A, B, and C are online; group has a prior message. | 1. B replies to A’s message in the group. | A and C receive the reply once; reply links to the correct parent message. | P0 | Recommended | Required | N/A | Recommended | Required |  |
| GM-006 | Sequential same-sender ordering | A, B, and C are online. | 1. A sends M1 then M2 in order. | B and C display M1 before M2 according to the app’s ordering rule. | P1 | Required | Required | N/A | Required | Required |  |
| GM-007 | Simultaneous send | A, B, and C are online. | 1. A and B send at nearly the same time. | C receives both messages; neither is lost or merged incorrectly. | P0 | Recommended | Required | N/A | Required | Required |  |
| GM-008 | Retry without duplicates | Connectivity is unstable; dedupe is enabled. | 1. A sends a message. 2. A retries after timeout/reconnect. | B and C still show one copy; sender state resolves cleanly. | P0 | Required | Required | N/A | Required | Recommended | Best when fake-net can force retry windows and duplicate deliveries. |
| GM-009 | Offline recipient receives later | C is offline; A and B are online. | 1. A sends a group message. 2. C reconnects later. | B receives immediately; C receives once after reconnect/store-and-forward. | P0 | Recommended | Required | N/A | Required | Required |  |
| GM-010 | Background notification | B’s app is backgrounded; notifications are enabled. | 1. A sends a group message. | B gets one notification for the correct group. | P0 | Recommended | Required | N/A | N/A | Required | Run on a simulator with real notification delivery enabled. |
| GM-011 | Notification deep link | B received a group notification. | 1. B taps the notification. | App opens the correct group and lands on the relevant message context. | P1 | Required | Required | N/A | N/A | Required | Assert both the target group and the target message anchor/deep-link. |
| GM-012 | App restart recovery | Group has recent messages. | 1. Exchange messages. 2. Force close and reopen app. | History reloads correctly; last-message preview and unread state remain consistent. | P0 | Recommended | Required | N/A | N/A | Required |  |
| GM-013 | Mixed delivery paths | One recipient is direct; another uses relay/store-and-forward. | 1. A sends a group message. | Both recipients receive the same message once despite different transport paths. | P0 | Recommended | Required | N/A | Required | Recommended | Useful only if your harness can force direct vs relay/store-and-forward paths. |
| GM-014 | Partial fan-out | One member is temporarily unreachable. | 1. A sends a group message to a 3+ member group. | Reachable members receive immediately; unreachable member receives later if supported; send is not marked globally failed because one peer was unavailable. | P0 | Recommended | Required | N/A | Required | Recommended | Use one temporarily unreachable recipient and keep the other recipient online. |
| GM-015 | Sender disconnected behavior | A is disconnected or loses connection during send. | 1. A attempts to send a group message. | App queues correctly or fails clearly; no false ‘sent’ state and no ghost duplicates later. | P0 | Required | Required | N/A | Required | Recommended | Force disconnect during send, not before compose. |
| GM-016 | Network partition and reconnect | Group is split by a temporary connectivity partition. | 1. Send messages on one side. 2. Heal the partition. | Missed messages sync correctly after reconnect according to retention rules. | P1 | Recommended | Required | N/A | Required | Recommended | Fake-net should control partition start, heal time, and message release order. |



## Membership and Role Control


| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| MR-001 | Only admin can add members | A is admin; B is non-admin; D is not in the group. | 1. A attempts to add D. 2. B attempts to add D in a separate run. | Admin add succeeds; non-admin add is blocked in UI and rejected by protocol/state validation. | P0 | Required | Required | N/A | Recommended | Required | Run two permutations: admin add succeeds; non-admin add fails. |
| MR-002 | Add member success | A is admin; D is a valid peer not in the group. | 1. A adds D. | D joins the group and can participate after membership/bootstrap completes. | P0 | Recommended | Required | Required | Recommended | Required | With 3 simulators, use C as the newly added member. |
| MR-003 | New member cannot send before bootstrap completes | A has just added D; D has not fully synced group state/keys. | 1. D attempts to send immediately before bootstrap finishes. | App blocks send or queues it until bootstrap finishes; no invalid message is accepted by others. | P1 | Required | Required | N/A | Required | Recommended | Assert bootstrap/key sync completion before first accepted send. |
| MR-004 | Add existing member handled cleanly | D is already an active member. | 1. Admin attempts to add D again. | No duplicate member entry or duplicate system event; app returns a clear no-op/error. | P1 | Required | Required | N/A | Recommended | Recommended |  |
| MR-005 | Member list sync after add | A adds D; B and C are existing members. | 1. A adds D. 2. B and C refresh/sync state. | All members see the same updated member list and D’s role/badge state. | P0 | Recommended | Required | N/A | Recommended | Required | Check member list, admin badges, and local role state on every device. |
| MR-006 | Only admin can remove members | A is admin; B is non-admin; C is a member. | 1. A removes C. 2. In a separate run, B attempts to remove C. | Admin removal succeeds; non-admin removal is blocked in UI and rejected by protocol/state validation. | P0 | Required | Required | Required | Recommended | Required | Run two permutations: admin remove succeeds; non-admin remove fails. |
| MR-007 | Remove member confirmation | A is admin; C is a member. | 1. A chooses Remove member. | App shows confirmation text such as ‘Remove this member from the group? They will stop receiving new messages.’ Removal occurs only after confirm. | P0 | Recommended | Required | Recommended | N/A | Required | Keep copy short and explicit: remove member, consequence, and confirm action. |
| MR-007B | Remove member cancellation keeps membership unchanged | A is admin; C is a member. | 1. A chooses Remove member. 2. A cancels at the confirmation prompt. | C remains in the group; no removal system event is emitted; C can still send/receive and continue receiving notifications. | P1 | Recommended | Required | N/A | N/A | Required | Cancel must be a no-op both in UI and in persisted membership state. |
| MR-008 | Remove non-member handled cleanly | C is already absent from the group. | 1. Admin attempts to remove C again. | App returns a clear no-op/error; no state corruption or misleading system event. | P1 | Required | Required | N/A | Recommended | Recommended |  |
| MR-009 | Removed member loses send permission | C was removed from the group. | 1. C attempts to send a group message. | Send is blocked locally or rejected by protocol; remaining members do not receive the message. | P0 | Required | Required | Required | Required | Required | This is the main “removed member blocked” release gate. |
| MR-010 | Removed member loses receive permission | C was removed from the group. | 1. A sends new group messages after removal. | C does not receive any post-removal group messages. | P0 | Required | Required | Required | Required | Required | Pair with MR-009; together they prove removal is effective both ways. |
| MR-011 | Removed member loses notifications | C was removed from the group; notifications were previously enabled. | 1. A sends new group messages after removal. | C does not receive new notifications for that group. | P0 | Required | Required | N/A | Recommended | Required | Notification suppression after removal should be tested separately from mute. |
| MR-012 | Removed member is notified | C was removed from the group. | 1. C syncs local state after removal. | C sees a clear local notice such as ‘You were removed from this group’ and input is disabled or the group is archived/hidden per product rule. | P0 | Required | Required | Recommended | Recommended | Required |  |
| MR-013 | Remaining members see removal system event | A removes C; B remains in group. | 1. A removes C. 2. B views timeline/member list. | Remaining members see a system event such as ‘A removed C’ and the member list updates. | P1 | Recommended | Required | N/A | Recommended | Required |  |
| MR-014 | Removed while offline | C is offline when A removes C. | 1. A removes C while C is offline. 2. C reconnects later. | On reconnect, C syncs to removed state, cannot send/receive, and sees the removal notice. | P0 | Required | Required | N/A | Required | Required | Use offline removal plus delayed reconnect to catch stale-state bugs. |
| MR-015 | Removed while typing/sending | C is composing or sending while A removes C. | 1. C starts sending. 2. A removes C before send completes. | Any post-removal message from C is rejected; remaining members do not receive unauthorized messages. | P0 | Required | Required | N/A | Required | Recommended | Best with fake-net or transport hooks so the remove happens in the send window. |
| MR-016 | Admin can promote another admin | A is admin; B is a normal member. | 1. A promotes B to admin. | B gains admin privileges and can perform admin-only actions immediately after sync. | P0 | Required | Required | Required | Recommended | Required | After promotion, immediately try an admin-only action from B. |
| MR-017 | Non-admin cannot self-promote | B is a normal member. | 1. B attempts to make self admin. | Action is blocked in UI and rejected by protocol/state validation. | P0 | Required | Required | N/A | Recommended | Recommended |  |
| MR-018 | Promote non-member handled cleanly | D is not in the group. | 1. A attempts to promote D to admin. | Action fails cleanly; no phantom admin/member entry is created. | P1 | Required | Required | N/A | Recommended | Recommended |  |
| MR-019 | System event for admin promotion | A promotes B to admin. | 1. A promotes B. 2. C views group timeline/member list. | Members see a system event such as ‘A made B an admin’ and B shows an admin badge. | P1 | Recommended | Required | N/A | Recommended | Required |  |
| MR-020 | At least one admin remains | There is exactly one admin in the group. | 1. Last admin attempts to leave or remove self without transfer. | Action is blocked until admin rights are transferred or another admin exists. | P0 | Required | Required | N/A | Recommended | Required | If last-admin protection is product enforced in UI, still test protocol rejection elsewhere. |
| MR-021 | Admin leave flow with multiple admins | A and B are admins. | 1. A leaves the group. | Group remains healthy with B as admin; membership updates on all peers. | P1 | Recommended | Required | N/A | Recommended | Required |  |
| MR-022 | Member can leave group | C is a non-admin member. | 1. C leaves the group. | C can no longer send/receive group messages; remaining members see the leave event if the product shows one. | P0 | Required | Required | N/A | Recommended | Required |  |
| MR-023 | Non-admin cannot edit group metadata | A is admin; B is non-admin. | 1. B attempts to rename the group or change picture/description. | Action is blocked in UI and rejected by protocol/state validation. | P1 | Required | Required | N/A | N/A | Required | The protocol-layer rejection is covered separately by SC-002. |
| MR-024 | Admin change propagates to offline members | C is offline when A promotes B or removes D. | 1. Perform the admin/membership change. 2. C reconnects. | C syncs the latest roles/member list correctly on reconnect. | P1 | Required | Required | N/A | Required | Required | Take one device offline before the role change, then reconnect it after. |



## Re-invite and Rejoin


| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| RJ-001 | Admin can re-invite removed member | A is admin; C was previously removed. | 1. A adds C back to the group. | Re-invite succeeds and C can rejoin using fresh group state. | P0 | Required | Required | Required | Required | Required | Use the same third identity that was previously removed. |
| RJ-002 | Non-admin cannot re-invite | B is non-admin; C was previously removed. | 1. B attempts to add C back. | Action is blocked in UI and rejected by protocol/state validation. | P0 | Required | Required | N/A | Recommended | Recommended |  |
| RJ-003 | Re-invited member can send again | C has been re-added and completed bootstrap. | 1. C sends a new group message. | Message is accepted and delivered to current members. | P0 | Required | Required | Required | Required | Required | A good smoke candidate because it proves the re-invite is actually usable. |
| RJ-004 | Re-invited member can receive again | C has been re-added. | 1. A sends a new group message after rejoin. | C receives new post-rejoin messages once. | P0 | Required | Required | Recommended | Required | Required |  |
| RJ-005 | Notifications resume after rejoin | C had been removed, then re-added; notifications are enabled. | 1. A sends a new group message after rejoin. | C receives notifications again only after rejoin becomes effective. | P1 | Required | Required | N/A | Recommended | Required | Make sure notification delivery resumes only after rejoin becomes effective. |
| RJ-006 | Rejoin clears removed state | C was previously shown as removed and is now re-added. | 1. C opens the group after successful rejoin. | Removed banner/input lock is cleared; UI shows the group as active again. | P0 | Required | Required | N/A | Recommended | Required |  |
| RJ-007 | System event for re-add | A re-adds C. | 1. Remaining members view timeline/member list. | Members see a system event such as ‘A added C’. | P1 | Recommended | Required | N/A | Recommended | Required |  |
| RJ-008 | Rejoined member sees current membership and admins | C was removed, several changes happened, then C was re-added. | 1. C rejoins and syncs state. | C sees the latest member list, admin list, metadata, and current group epoch. | P0 | Required | Required | N/A | Required | Required | This should also assert the current epoch/version and role badges. |
| RJ-009 | Removed-period history is not exposed by default | C was removed at T1 and re-added at T2; messages exist between T1 and T2. | 1. C rejoins. 2. C tries to access messages from T1→T2. | C cannot access removed-period history unless that is an explicit product rule. | P0 | Required | Required | N/A | Required | Required | Make the allowed history rule explicit in product docs and test data setup. |
| RJ-010 | Re-invite while removed member is offline | C is offline when A re-adds C. | 1. A re-adds C while C is offline. 2. C reconnects later. | C syncs rejoin state on reconnect and gains access only to allowed post-rejoin messages. | P1 | Required | Required | N/A | Required | Required | Same flow as RJ-001 but with C offline during the re-add. |



## Security, Correctness, and Convergence


| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| SC-001 | UI restrictions are not the only restrictions | A is admin; B is non-admin. | 1. B bypasses UI and submits a raw protocol/state change for add/remove/promote. | Unauthorized action is rejected by protocol/state validation; no peer applies it. | P0 | Required | Required | N/A | Required | Recommended | 3-sim E2E needs an instrumented or debug client that can bypass the normal UI. |
| SC-002 | Unauthorized metadata changes rejected at protocol layer | B is non-admin. | 1. B bypasses UI and submits raw rename/photo/description change. | Peers reject the change; canonical metadata remains unchanged. | P1 | Required | Required | N/A | Required | Recommended | Same as SC-001 but for rename/photo/description messages. |
| SC-003 | Removed member cannot decrypt future messages | C was removed; cryptographic group messaging is enabled. | 1. A/B exchange new messages after C’s removal. 2. C intercepts/stores traffic. | C cannot decrypt any future group traffic after removal. | P0 | Required | Required | N/A | Required | Recommended | A plain UI E2E cannot prove cryptographic failure; use debug hooks or captured ciphertext. |
| SC-004 | Group key/epoch rotates on removal | C is a current member; encryption epoching is enabled. | 1. A removes C. 2. Members send new messages. | Post-removal messages use a new valid epoch/key state. | P0 | Required | Required | N/A | Required | Recommended | Assert epoch/key identifiers before and after removal. |
| SC-005 | Group key/epoch updates correctly on re-invite | C was removed, then re-added. | 1. A re-adds C. 2. C syncs fresh state. 3. New messages are exchanged. | C receives the current epoch/key state; stale removed credentials are not reused. | P0 | Required | Required | N/A | Required | Recommended | Assert that rejoin provisions fresh state rather than reusing stale removed credentials. |
| SC-006 | Unknown/non-member sender is rejected | X is not in the group. | 1. X sends or relays a forged group message. | Peers reject the message; no UI entry or unread counter change occurs. | P0 | Required | Required | N/A | Required | Recommended | This usually needs a raw/instrumented sender because normal UI will not allow non-member send. |
| SC-007 | Stale client resync | A client has old cached membership/admin state. | 1. Client reconnects after offline period with group changes pending. | Client converges to the latest valid group state before sending privileged operations. | P0 | Required | Required | N/A | Required | Required | A normal 3-sim flow can cover this by reconnecting a stale offline client. |
| SC-008 | Duplicate-path dedupe | Network can deliver the same message via multiple paths. | 1. Inject the same valid message via two routes. | UI shows one copy and state updates only once. | P0 | Required | Required | N/A | Required | Recommended | Prefer fake-net or injected duplicate frames to make this deterministic. |
| SC-009 | Tampered message rejection | A valid message is modified in transit or storage. | 1. Deliver a message with invalid signature/envelope/ciphertext. | Peers reject it; no UI entry, notification, or unread increment appears. | P0 | Required | Required | N/A | Required | N/A | Do not force plain 3-sim UI E2E; use integration plus malformed-frame injection. |
| SC-010 | Replay protection | A previously valid message exists in history. | 1. Replay the same old message/envelope later. | Peers do not treat it as a new message; no duplicate timeline entry or notification. | P0 | Required | Required | N/A | Required | Recommended | Use a replayed stored envelope or message ID, not a fresh resend path. |
| SC-011 | Post-removal store-and-forward cut-off | C is removed while some peers still have queued messages for delivery. | 1. Queue messages after removal. 2. Attempt delivery to C later. | C cannot receive/decrypt any post-removal queued messages. | P0 | Required | Required | N/A | Required | Required | This is the removal-boundary test most teams miss. |
| SC-012 | Membership change ordering vs in-flight messages | A removes C around the same time A/B send new messages. | 1. Interleave removal and message sends near the boundary. | Messages are accepted or rejected according to the defined ordering/epoch rule; state converges consistently across peers. | P0 | Required | Required | N/A | Required | Recommended | Drive ordering explicitly in fake-net; black-box E2E is usually too flaky alone. |
| SC-013 | Concurrent admin changes converge safely | A and B are admins. | 1. A and B make different membership/role changes nearly simultaneously. | Group converges deterministically; no split-brain member/admin list. | P1 | Required | Required | N/A | Required | Recommended | Needs deterministic conflict timing to avoid non-reproducible failures. |
| SC-014 | Conflicting add/remove of same member converges deterministically | Two admins act on C around the same time. | 1. One admin removes C while another re-adds or promotes C near-simultaneously. | All peers converge to the same final membership/role state according to conflict-resolution rules. | P1 | Required | Required | N/A | Required | Recommended | Write down the conflict-resolution rule before automating the test. |
| SC-015 | Membership and role events are authenticated | A membership/role event is received from the network. | 1. Deliver valid and invalid signed membership events. | Only events authorized by the correct admin role are accepted and applied. | P0 | Required | Required | N/A | Required | N/A | Best covered at integration/fake-net level with signed event injection. |
| SC-016 | Local send status reflects partial success accurately | One recipient is unreachable while others receive the message. | 1. A sends a message during partial fan-out. | Sender sees accurate status (e.g., sent to group / pending for some peers) per product rule; app does not falsely report total failure if the group send is otherwise valid. | P1 | Required | Required | N/A | Required | Recommended | Useful when the product shows partial send or pending-recipient status. |
| SC-017 | Duplicate membership or role event is idempotent | A valid add/remove/promote/demote event exists and can be delivered more than once. | 1. Deliver the same valid membership or role event twice. | The state change is applied once; member/admin lists remain correct; no duplicate system event or duplicate badge update is shown. | P0 | Required | Required | N/A | Required | Recommended | Check both canonical state and timeline/system-event idempotency. |
| SC-018 | Older membership or role event cannot roll back newer state | A newer valid membership or role event has already been applied. | 1. Deliver an older valid event after the newer one. | Peers keep the latest valid state and ignore the stale event; no rollback or split-brain member/admin list occurs. | P0 | Required | Required | N/A | Required | Recommended | Use explicit sequence/version metadata in the test fixture if your protocol has it. |



## Metadata, Notifications, and Optional Feature Coverage


| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| UX-001 | New member history policy | D is newly added to an existing group with prior history. | 1. A adds D. 2. D opens the group. | D sees exactly the history allowed by product policy: future-only, limited recent history, or full history. | P1 | Required | Required | N/A | Recommended | Required | Choose one history rule and encode it in both product docs and test data. |
| UX-002 | Group rename | Rename feature exists; A is allowed to rename. | 1. A renames the group. | All members see the new name; non-admin behavior follows policy. | P1 | Recommended | Required | N/A | Recommended | Required |  |
| UX-003 | Group picture/description update | Picture/description feature exists; A is allowed to edit. | 1. A updates group picture/description. | All members sync the new metadata and caches refresh correctly. | P2 | Recommended | Required | N/A | Recommended | Required | If image/file upload is involved, split metadata-update logic from media-upload logic. |
| UX-004 | Mute notifications per group | B is a current member; group notifications can be muted. | 1. B mutes the group. 2. A sends new messages. | Messages still arrive, but B receives no notifications while mute is active. | P1 | Required | Required | N/A | N/A | Required | Do not confuse mute with removal; both need separate tests. |
| UX-005 | Unread count correctness | Unread counters are enabled. | 1. Send several messages, including duplicates/retries/reconnects. 2. Open the group. | Unread count increments/decrements correctly and is not double-counted by duplicate deliveries. | P1 | Required | Required | N/A | Recommended | Required |  |
| UX-006 | Long text / emoji / RTL / special characters | Group supports text messages. | 1. Send messages with long text, emoji, Arabic/RTL, and special characters. | Rendering, storage, notifications, and sync behave correctly without corruption. | P1 | Recommended | Required | N/A | N/A | Required |  |
| UX-007 | Large message or attachment | Large payloads or attachments are supported. | 1. Send a large payload/attachment. | Delivery succeeds within limits or fails cleanly with clear user feedback; no broken partial state remains. | P2 | Recommended | Required | N/A | Required | Required | Only required if attachments or large payloads are supported. |
| UX-008 | Store-and-forward expiry / retention boundary | Offline retention/TTL exists. | 1. Keep C offline past the retention boundary. 2. Send messages. 3. C reconnects. | Behavior matches policy: expired messages are unavailable with clear UX, and newer retained messages sync normally. | P2 | Recommended | Required | N/A | Required | Recommended | Time-based tests are best with controllable clocks or retention config overrides. |
| UX-009 | Max group size limit | A configured or product max group size exists. | 1. Add members until limit is reached. 2. Try to add one more. | Add beyond limit fails cleanly with clear feedback; existing group remains healthy. | P2 | Required | Required | N/A | N/A | N/A | 3-sim E2E is only practical if your max size can be hit with 3 peers; otherwise use helper peers. |
| UX-010 | Member list consistency after reconnect | Multiple peers reconnect after different offline periods. | 1. Apply several membership/role changes. 2. Reconnect all peers. | All peers converge to the same final member/admin list and metadata. | P1 | Required | Required | N/A | Required | Required | A reconnect-convergence test should compare all member/admin lists after sync settles. |
| UX-011 | Admin demotion / revoke admin | Admin demotion feature exists. | 1. A demotes B from admin to member. | B immediately loses admin-only permissions; peers show updated role/system event per product rule. | P2 | Required | Required | N/A | Recommended | Required | If you support demotion, immediately verify the demoted admin can no longer manage the group. |
| UX-012 | Invite accept / decline / expiry | Your product uses explicit invites instead of immediate add. | 1. A invites D. 2. D accepts, declines, or lets invite expire in separate runs. | Each path behaves predictably: accept joins, decline does not join, expiry invalidates the invite without ghost membership. | P2 | Required | Required | N/A | Recommended | Required | Only applicable if your product uses invite acceptance rather than immediate add. |
| UX-013 | Multi-device state convergence | A user can be signed in on multiple devices. | 1. Use two devices for the same user. 2. Apply membership, mute, and message changes. | Both devices converge to the same group state, notifications, and unread counters per product rule. | P2 | Required | Required | N/A | Recommended | Recommended | Use two simulators for the same user plus one other member. |
| UX-014 | Group dissolve / deletion | Group deletion/dissolve feature exists. | 1. Allowed actor dissolves/deletes the group. | All members see the correct final state; no one can send to the dissolved group afterward. | P2 | Required | Required | N/A | Recommended | Required | Only applicable if group deletion or dissolve exists. |
| UX-015 | Admin-only send / announcement mode | Your product supports an admins-only send mode. | 1. Admin enables admins-only send. 2. B tries to send. 3. A sends. | B is blocked from sending; admin messages continue to work; all peers show the correct mode/state. | P2 | Required | Required | N/A | Recommended | Required | Try both a blocked member send and a permitted admin send in the same run. |



## Recommended smoke suite

These are the journeys marked **Smoke = Required** in the matrix:

- **GM-001** — Create group successfully
- **GM-003** — Online fan-out
- **MR-002** — Add member success
- **MR-006** — Only admin can remove members
- **MR-009** — Removed member loses send permission
- **MR-010** — Removed member loses receive permission
- **MR-016** — Admin can promote another admin
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
