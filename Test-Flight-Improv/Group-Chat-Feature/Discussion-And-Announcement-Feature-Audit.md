## 1. Title and Type

- Title: Discussion and Announcement Group Feature Audit
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`

## 2. Problem Statement

- Users need discussion and announcement groups to feel trustworthy, readable, and complete: membership changes should be visible, identities should be human-readable, message cards should render cleanly, reaction participation should be transparent, long-press message actions should feel coherent, media should work across the whole member list, and sending plus offline catch-up should not feel fragile.
- The repo already ships strong group foundations for create, invite review, send, media, admin-only announcement write control, mute, metadata editing, and recovery, but several visible journeys remain incomplete or inconsistent, especially once offline replay privacy and membership-bound decryptability are treated as core product requirements rather than optional hardening.
- The main user-facing gaps are around membership-event UX, creator/admin identity display, group message-card rendering quality, reaction-participant visibility, long-press message-context parity versus 1:1 conversations, cross-friendship participation journeys, and relay-inbox privacy plus membership-aware decryptability for offline replay, in addition to missing higher-level product tools such as search, pinning, read receipts, scheduled announcements, explicit ownership handoff, and one reliability precision gap around how zero-peer plus inbox-fail sends are meant to recover.

## 3. Impact Analysis

- Affects both `GroupType.chat` discussion groups and `GroupType.announcement` groups.
- Affects admins when they invite, remove, promote, or hand off responsibility.
- Affects invitees when deciding whether to join and when other members need to understand who actually joined.
- Affects members in mixed social graphs, especially if two people are in the same group but are not direct contacts/friends.
- Affects day-to-day readability if message cards render with a doubled or stacked-shell artifact that makes one message look like two overlapping bubbles.
- Affects trust in reactions when group members can see emoji counts but cannot inspect who reacted, and a tap instead mutates the viewer's own reaction.
- Affects day-to-day usability if long-pressing a group message exposes only reactions while the mature 1:1 surface already provides a full selected-message overlay with reply/copy/edit/delete affordances.
- Affects offline members and privacy expectations if relay operators can inspect stored replay payloads.
- Affects members who go offline during heavy text/media chat or during add/remove/leave transitions, because replay needs to remain both decryptable for legitimate members and unavailable to peers outside the valid membership window.
- Affects bootstrap integrity if group creation can appear successful without a persisted local group key, because later invite fan-out, restart/rejoin, and local key-epoch truth can silently break even when the live Go node originally had key material.
- Severity is mixed:
  - high for identity and membership trust issues such as peer ID fallback or invisible invite acceptance
  - medium for conversation rendering defects that make messages look visually duplicated or broken
  - medium for reaction transparency gaps where users can see that multiple people reacted but cannot tell who reacted with which emoji
  - medium for interaction-parity gaps where the same message object supports rich context actions in 1:1 but only a narrow reaction affordance in groups
  - high for offline replay privacy and continuity if group relay inbox payloads are stored in plaintext or if encrypted replay cannot survive add/remove/leave boundaries
  - medium for bootstrap key-integrity gaps where a group can be saved locally without usable key state after a partially successful create flow
  - medium for retry-lane truth gaps where a failed zero-peer send keeps inbox retry state but recovery ownership between inbox-only retry and full resend is not explicit enough
  - medium for invite-accept recovery gaps where newly joined members can catch up messages immediately but still miss offline reactions until a later global drain
  - medium for invite-accept join-recovery gaps where the product can report `Joined ..., but recovery is still catching up` after local persistence succeeds and bridge join times out, yet there is no direct end-to-end proof that automatic rejoin closes that state promptly or any explicit manual retry surface if it does not
  - medium for non-friend UX gaps and missing persistent membership timelines
  - lower for roadmap-style enhancements such as search, scheduling, analytics, or pinning
- Repo evidence suggests the transport and recovery layer is comparatively strong, so the biggest remaining problems are now more product-surface and UX-contract gaps than basic send-path fragility.

## 4. Current State

Affected code areas and adjacent evidence:

- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/domain/models/group_reaction_payload.dart`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/widgets/group_member_row.dart`
- `lib/features/feed/presentation/widgets/swipe_to_quote_bubble.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/features/conversation/domain/models/message_reaction.dart`
- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/home/presentation/widgets/user_avatar.dart`
- `lib/features/settings/application/profile_update_listener.dart`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/group_inbox_test.go`
- `go-mknoon/cmd/testpeer/commands.go`
- `go-relay-server/inbox.go`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_reaction_roundtrip_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/13-announcement-use-case-audit.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/Group-Chat-Feature/C4-02-Send-Message.md`
- `Test-Flight-Improv/Message-Bubble-List-1_1-Feature/message_context_overlay_test_matrix_full_with_rules.md`

### Requested Journeys

| Requested journey | Status | Current repo evidence |
|---|---|---|
| 1. Show a short in-group message after adding members | `partial` | Admins currently get a local snackbar after the picker returns (`Member invited` / `X members invited`) in `group_info_wired.dart`, but the shipped add flow publishes `members_added` from `contact_picker_wired.dart` and `_handleMembersAdded()` in `group_message_listener.dart` does not save or emit a timeline row. A single-member `member_added` timeline helper exists, but the active UI path does not use it. |
| 2. Show `X accepted the invite` when invitees join | `shipped` | `acceptPendingGroupInvite()` now runs the durable join helper for both the success and degraded `bridgeError` branches, and `accept_pending_group_invite_use_case_test.dart`, `group_list_wired_test.dart`, `group_message_listener_test.dart`, and `invite_round_trip_test.dart` now prove the readable `member_joined` timeline remains visible across accept, shipped accept-surface, listener materialization, and existing-member render flows. |
| 3. Show admin-driven member removals in the group | `shipped` | `group_info_wired.dart` publishes `member_removed` and saves a local timeline row via `buildMemberRemovedTimelineMessage(...)`. `group_message_listener.dart` saves and emits the readable removal timeline for remaining members. Tests cover this in `group_info_wired_test.dart`, `group_message_listener_test.dart`, and `group_membership_smoke_test.dart`. |
| 3a. Show when a member voluntarily leaves the group | `partial` | The timeline text builder already supports this copy: `buildMemberRemovedTimelineText(...)` returns `X left the group` when actor and subject are the same, and `group_message_listener.dart` will persist that readable timeline if it receives a matching `member_removed` system event. But the only broadcaster found is `_broadcastSelfRemovalIfNeeded()` in `group_info_wired.dart`, and that helper returns early unless the leaver is an admin with at least one other admin still present. The generic `leaveGroup()` cleanup use case in `leave_group_use_case.dart` sends no system event, so ordinary-member voluntary leave and any non-UI caller currently produce no durable leave message for remaining members. |
| 4. Show admin usernames instead of peer IDs | `partial` | The UI will show usernames when present, but `createGroup()` persists the creator as `GroupMember(... username: null ...)` in `create_group_use_case.dart`, `buildGroupConfigPayload()` republishes that null username, and `group_member_row.dart` falls back to truncated `peerId` when `username` is absent. This matches the reported symptom that admins can still render as peer IDs. |
| 5. Let two non-friend members still write and see messages | `partial` | Inference from current code: once membership exists, group messaging is membership-based, not contact-based. `sendGroupMessage()` uses `groupRepo` and member lists, and `handleIncomingGroupMessage()` checks group membership rather than `contactRepo`. However, the create and add-member pickers are contact-only (`getActiveContacts()` in `create_group_picker_wired.dart` and `contact_picker_wired.dart`), and incoming invites from unknown senders are rejected in `handle_incoming_group_invite_use_case.dart`. |
| 6. Let all members see image/video/voice messages even when they are not friends | `shipped` at the group-membership layer | `send_group_message_use_case.dart` fans out by `groupRepo.getMembers()`, not by contacts. `handle_incoming_group_message_use_case.dart` saves incoming media attachments without a friendship check, and `group_message_listener.dart` auto-downloads group media. Group media coverage appears in `send_group_message_use_case_test.dart`, `handle_incoming_group_message_use_case_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, and `announcement_happy_path_test.dart`. No direct repo test names a “non-friend media” scenario, but the current path is membership-driven. |
| 7. Make sending in groups reliable | `shipped` | `send_group_message_use_case.dart` pre-persists outgoing rows, runs publish and inbox fallback concurrently, distinguishes `sending` / `sent` / `pending` / `failed`, and preserves retry payloads. Recovery and retry use cases exist for failed sends, incomplete uploads, stuck sending rows, offline inbox drain, and topic rejoin. The current closure reference in `20-group-discussion-reliability-closure-reference.md` and tests such as `group_resume_recovery_test.dart` and `group_messaging_smoke_test.dart` support this. |
| 8. Render each group message as one clear bubble without a doubled or stacked-card artifact | `partial` | User-supplied screenshots from the current product show some received group messages rendering like two rounded bubbles layered on top of one another. The likely render seam is the shared `LetterCard` glassmorphic container inside `group_conversation_screen.dart`, optionally wrapped by `SwipeToQuoteBubble` for incoming group messages. Current tests such as `letter_card_test.dart` and `group_conversation_screen_test.dart` verify content and interaction seams, but no direct repo-local visual regression or golden test appears to assert that a single group message renders as one stable card shell without duplicate-looking background layers. |
| 9. Let long-pressing a group message feel as complete and coherent as the 1:1 MessageContextOverlay flow where that parity is product-supported | `partial` | Direct 1:1 conversations already route long-press into the shared `MessageContextOverlay` from `conversation_screen.dart`, with selected-message preview, blur backdrop, anchored reactions, and conditional reply/edit/copy/delete actions. Group conversations in `group_conversation_screen.dart` do not use that shared overlay; long-press currently opens only a `ReactionBar`, and only when `onReactionSelected` is wired. Group quote-reply exists separately via `SwipeToQuoteBubble` for incoming rows, but there is no long-press reply entry point, no copy action, no selected-message preview, and no group-specific context menu. Important nuance: most of this gap is UI-host parity, not a transport limitation. Group transport differences matter mainly for networked message-edit/delete features, not for local-only affordances such as previewing the selected message or copying text. |
| 10. When several members react to a message, tapping the visible reaction chip should show who reacted with which emoji instead of immediately assuming the viewer wants to remove or replace their own reaction | `partial` | Group messages render reactions through the shared `LetterCard`, where `_buildReactionChipWidgets()` groups reactions by emoji and shows only the emoji/count. Chip taps call `onReactionTap(emoji)`. In group chat, `group_conversation_screen.dart` wires that tap directly to `onReactionSelected(message.id, emoji)`, and `_onReactionSelected()` in `group_conversation_wired.dart` treats a matching own emoji as a toggle-off that removes the viewer's reaction. `MessageReaction` and `GroupReactionPayload` persist `senderPeerId` but not display username, and no repo-local reaction participant sheet, tooltip, or detail overlay was found. This requirement needs to hold for the same group conversation surface when opened from `Orbit` and when opened from `Feed`, because both entry points route into `GroupConversationWired` through `orbit_wired.dart` and `feed_wired.dart`. |

### Adjacent Good-Experience Capabilities

| Capability that should exist in a good discussion/announcement product | Status | Current repo evidence |
|---|---|---|
| Create both discussion and announcement groups | `shipped` | Orbit routes the requested type into `CreateGroupPickerWired`; `create_group_use_case.dart`, `create_group_picker_wired_test.dart`, and `announcement_happy_path_test.dart` cover the type-aware create path. |
| Group creation never reports success without usable local key state for send, invite, and restart/rejoin flows | `partial` | Current Go `group:create` normally generates and returns `groupKey` or fails, but `create_group_use_case.dart` still has a defensive branch where a missing `groupKey` falls back to `group.keygen`, and if that second step throws the error is only logged while the group and creator member remain saved. In that broken local state, `create_group_with_members_use_case.dart` skips invite send because `getLatestKey(...)` is null, `send_group_message_use_case.dart` can still persist outgoing rows with `keyEpoch = 0` for admins, and `rejoin_group_topics_use_case.dart` later skips the group entirely on restart because no local key exists. No direct repo-local test currently proves the double-failure path is rejected or repaired. |
| Zero-peer plus inbox-fail sends recover through one explicit, truthful retry contract | `partial` | `send_group_message_use_case.dart` marks the row `failed` when `topicPeers == 0` and inbox store also fails, while keeping `inboxRetryPayload` on the row. But `retry_failed_group_inbox_stores_use_case.dart` only scans `status IN ('sent', 'pending')`, so this branch is not owned by the inbox-only retry lane. Recovery currently depends on the broader `retry_failed_group_messages_use_case.dart` full resend path instead. Existing unit coverage proves `0-peer + inbox fail -> error`, and the failed-message retry system exists, but no direct repo-local regression proves this exact branch is intentionally recovered through resend and never stranded by the status mismatch. |
| Accepting a pending invite replays offline reactions in the same immediate catch-up pass | `shipped` | The supported invite-accept path already drains with `GroupMessageListener` and `reactionRepo` when they are supplied, and `accept_pending_group_invite_use_case_test.dart` plus `group_list_wired_test.dart` now prove the immediate post-accept catch-up window can materialize both the replayed message and its replayed reaction before the pending invite row disappears. |
| Accepting a pending invite still reaches a live subscribed group after bridge timeout or delayed join acknowledgement | `shipped` | `materializeAcceptedGroupInvitePayload(...)` still persists the group before join, and the degraded `bridgeError` branch now keeps the group saved, clears the pending invite row, and still stores the durable join event for replay even when live `group:publish` fails. `group_list_wired_test.dart` keeps the honest `recovery is still catching up` UI contract, and `invite_round_trip_test.dart` now directly proves later `rejoinGroupTopics(...)` plus inbox drain convergence without recreating the invite row or duplicating join history. |
| Explicit invite review: accept, decline, expiry | `shipped` | Pending invite persistence and review live in `group_invite_listener.dart`, `pending_group_invite.dart`, `pending_group_invite_card.dart`, `accept_pending_group_invite_use_case.dart`, and `decline_pending_group_invite_use_case.dart`, with coverage in `group_list_wired_test.dart` and `invite_round_trip_test.dart`. |
| Read-only announcement compose for non-admins | `shipped` | `group_conversation_screen.dart` shows the read-only banner, `group_conversation_wired.dart` computes `canWrite`, and `send_group_message_use_case.dart` rejects non-admin announcement sends. Covered in `announcement_happy_path_test.dart`. |
| Post-creation admin promotion and demotion | `shipped` | `group_info_wired.dart` calls `updateGroupMemberRole(...)`, then emits `member_role_updated`, saves a local role-change timeline row via `buildMemberRoleUpdatedTimelineMessage(...)`, publishes the system event live, and stores it for offline replay. `group_message_listener.dart` persists the same readable role-change timeline for recipients when that system event arrives. Covered in `group_info_wired_test.dart`, `group_message_listener_test.dart`, and documented in `59-post-creation-admin-role-management.md`. |
| Edit group name, description, and group photo | `shipped` | `group_info_wired.dart` and `update_group_metadata_use_case.dart` support metadata updates; `group_message_listener.dart` applies `group_metadata_updated`; coverage exists in `group_info_wired_test.dart` and adjacent group tests. |
| Per-group notification mute | `shipped` | `set_group_muted_use_case.dart`, `group_info_screen.dart`, and `group_message_listener.dart` support and enforce mute without dropping delivery. This is reflected in current group tests and the later landed state described after `61-group-notification-mute-and-invite-decision-controls.md`. |
| Dissolve group but keep history read-only | `shipped` | `dissolve_group_use_case.dart`, `group_message_listener.dart`, `group_info_screen.dart`, and `group_conversation_screen.dart` implement dissolve and read-only history. |
| Quote replies and reactions | `shipped` | Quote wiring is present in `group_conversation_screen.dart` and `send_group_message_use_case.dart`; reactions are handled by `send_group_reaction_use_case.dart`, `handle_incoming_group_reaction_use_case.dart`, and announcement happy-path coverage. |
| Reaction chips reveal which members reacted with which emoji without overloading inspection as removal | `partial` | The shared `LetterCard` currently collapses reactions into emoji chips with counts and forwards only the tapped emoji. In group chat, that tap is wired to the current add/remove reaction action, not to an inspection surface. The current reaction model stores `senderPeerId` but not a reaction username, so no repo-local group UI currently exposes a readable per-reactor list. |
| Full long-press message context overlay for group messages, with honest action parity versus 1:1 | `partial` | 1:1 already uses the shared `MessageContextOverlay` (`message_context_overlay.dart`) and has deep widget/screen coverage for reply, copy, edit, delete, selected-message preview, dismissal, action ordering, and host parity. Group chat currently does not adopt that overlay. The group surface opens only a `ReactionBar` from `_showReactionBar()` in `group_conversation_screen.dart`, while reply is exposed separately through `SwipeToQuoteBubble` on incoming messages only. Copy is absent, and edit/delete are absent because group per-message edit/delete product flows are not landed. Also, when `reactionRepo` is null, `group_conversation_wired.dart` passes no `onReactionSelected`, which disables group long-press altogether even for potentially local-only actions. |
| Single, visually stable message bubbles in the group timeline | `partial` | User-supplied screenshots show some incoming group messages rendering with what looks like a second rounded shell behind the main card. The current group timeline uses `LetterCard` from `lib/features/conversation/presentation/widgets/letter_card.dart`, wrapped in `SwipeToQuoteBubble` for swipe-to-reply behavior on incoming rows. Inference from current code: the visual artifact is likely in this shared rendering stack rather than in group transport logic. Existing tests exercise `LetterCard` content and group conversation behavior, but no repo-local visual regression test was found that would catch a duplicated-shell or double-bubble appearance. |
| Real usernames and profile pictures for every participant in the member list and conversation | `partial` | Conversation bubbles use `LetterCard` + `UserAvatar(peerId: ...)`, which can show a file-backed avatar if one already exists. But `group_member_row.dart` still uses a placeholder initial-circle instead of `UserAvatar`, and `profile_update_listener.dart` only downloads profile pictures for known contacts. Inference: non-friends are likely to fall back to ring avatars or placeholders rather than true profile photos. |
| Non-friend-friendly entry path into the same group | `missing` in current product flow | Both create-group and add-member pickers only load `getActiveContacts()`, and invite receipt rejects unknown senders in `handle_incoming_group_invite_use_case.dart`. The repo supports mixed-member messaging better than it supports mixed-member onboarding. |
| Persistent join/acceptance audit trail in the chat history | `shipped` | `acceptPendingGroupInvite()` now owns a durable `member_joined` timeline event for accepted invites, including the degraded `bridgeError` branch, and the accept/listener/round-trip coverage proves that existing members can render the same readable join audit trail truthfully. |
| Durable `X left the group` audit trail when a member leaves voluntarily | `partial` | `group_membership_timeline_message.dart` can already render `X left the group`, but the emit path is not generalized. `_broadcastSelfRemovalIfNeeded()` in `group_info_wired.dart` broadcasts only for a narrow multi-admin self-leave case, while `leave_group_use_case.dart` performs cleanup only. As a result, the product currently documents admin removal better than voluntary leave. |
| Encrypted relay inbox storage for offline group replay | `missing` | Current repo evidence shows plaintext replay storage: `send_group_message_use_case.dart` builds a raw JSON `inboxPayload`, `callGroupInboxStore()` in `bridge_group_helpers.dart` forwards raw `message` to `group:inboxStore`, `Node.GroupInboxStore()` in `go-mknoon/node/group_inbox.go` stores that same `message` string in the relay request, and `drain_group_offline_inbox_use_case.dart` later `jsonDecode`s the stored relay `message`. The required future contract is stronger than “encrypt text eventually”: offline replay for text, quote replies, images, videos, GIFs/files, and recorded voice must be opaque to relay operators, remain reliably recoverable for legitimate members, and stay membership-window aware when users are added, removed, or leave. Members added later should only decrypt the backlog they are entitled to after the relevant membership/key epoch, and removed or departed members should not decrypt replay for newer traffic. Legacy old-build convenience is intentionally out of scope for this requirement. Important nuance: this finding is specific to group offline replay payloads, not the separately encrypted pending-group-invite flow. |
| Search inside group history | `missing` | No repo-local group search flow, search use case, or search UI surface was found under `lib/features/groups`. |
| Pin/unpin important messages | `missing` | No repo-local pinning flow or pin state was found under `lib/features/groups`. |
| Message edit and per-message delete/tombstone | `missing` for groups | No repo-local group edit/delete message product flow was found under `lib/features/groups`; current delete support is group-level removal such as `delete_group_and_messages_use_case.dart`, not message-level moderation. |
| Read receipts or reader counts | `missing` | No repo-local group read-receipt contract was found; `20-group-discussion-reliability-closure-reference.md` explicitly treats read receipts as outside the current closure bar. |
| Explicit admin transfer / ownership handoff | `partial` | Multi-admin promotion/demotion exists, but no dedicated transfer-owner contract, handoff UX, or “make X the sole owner” flow was found. |
| Member-level moderation such as mute/ban by admin | `missing` | No repo-local per-member mute or ban capability was found under `lib/features/groups`. |
| Scheduled announcements, announcement edit-after-send, delete-after-send, or analytics | `missing` | `13-announcement-use-case-audit.md` still lists these as missing announcement-specific product features. |

Important current user-visible flow details:

- Group invites are now explicit review items instead of forced auto-join, and the invite card already shows the inviter name and group type.
- Discussion groups allow regular members to write; announcement groups keep non-admins read-only while still allowing them to read and react.
- The current reaction-chip contract is action-first rather than information-first. Group messages show emoji counts, but tapping a chip routes straight into the add/remove reaction action for the current viewer instead of showing who reacted with which emoji.
- The same group conversation surface is entered from more than one product surface. `Orbit` group taps and `Feed` group-thread taps both navigate into `GroupConversationWired`, so reaction inspection and other message-level UX fixes need to behave consistently from both entry points instead of landing in one path only.
- Direct 1:1 messages already use the shared `MessageContextOverlay` with selected-message preview plus reply/copy/edit/delete gating. Group messages do not. Current group long-press opens only reactions, and quote reply is split into a separate swipe gesture on incoming rows.
- The current group long-press gap is mostly a presentation and feature-contract issue, not a fundamental group-transport issue. Local-only affordances such as selected-message preview, reply entry, and copy can be designed independently from the later protocol work needed for group edit/delete parity.
- Voluntary leave is not covered as robustly as admin removal. The repo already knows how to render `X left the group` if a self-removal event exists, but the current broadcast path is narrow and `leaveGroup()` itself is only a cleanup use case.
- Current offline catch-up already helps reliability, but the relay-stored replay copy is still plaintext and not yet defined as a membership-aware encrypted contract for text, image, video, or recorded voice traffic.
- Pending-invite acceptance still treats `bridgeError` as a degraded accepted state rather than a hard reject. The group can remain persisted locally while topic join is pending later recovery, the shipped snackbars still say recovery is catching up, and the current accept/widget/round-trip proofs now show that this degraded state still owns one durable join event and later converges without reviving the pending invite row.
- Current user screenshots also confirm two visible polish bugs that match repo seams: some group messages render with a doubled-card visual artifact, and the group-info member list can still show the admin as a truncated peer ID instead of a username.
- The sender-side reliability story is stronger than the UX story around membership and identity. The biggest remaining gaps are not “message send usually fails”; they are “the app does not always explain membership state clearly enough” and “member identity is not consistently human-readable.”
- Current group bootstrap assumes local key persistence succeeds whenever create succeeds. That is usually true with the shipped Go bridge, but the Dart defensive branch still allows a locally keyless success outcome if a malformed or future bridge response omits `groupKey` and fallback keygen also fails.

## 5. Scope Clarification

- In scope:
  - user-visible expectations for discussion and announcement groups
  - the seven requested journeys in the prompt
  - adjacent group-chat capabilities that materially affect day-to-day UX quality
  - whether the repo currently ships, partially ships, or does not ship those capabilities
- Explicit non-goals:
  - the disabled `GroupType.qa` product path
  - implementation planning, architecture redesign, or session rollout proposals
  - solving how non-friend onboarding should work at protocol level
  - defining exact privacy policy for future read receipts, analytics, or presence
  - preserving plaintext replay compatibility for old app builds once encrypted group inbox replay becomes the required contract
- Accepted ambiguities for a later implementation pass:
  - exact copy for add-member, invite-accepted, and join timeline events
  - whether the doubled-bubble artifact is caused by `LetterCard` itself, the group-specific wrapper stack, or a blur/compositing interaction on certain devices
  - whether reaction-participant disclosure should open from chip tap, long-press, a bottom sheet, or another detail surface, as long as inspection is not overloaded with destructive mutation
  - how closely group long-press should mirror the 1:1 `MessageContextOverlay` before group per-message edit/delete is a shipped product feature
  - whether non-friend participation should be enabled through invites only, direct add, share links, QR, or a broader membership model
  - whether admin transfer is exposed as a dedicated “transfer ownership” action or remains a narrower multi-admin contract

## 6. Test Cases

### Happy Path

- An admin creates either a discussion or announcement group, sees a clear type badge, and reaches the correct write policy immediately after creation.
- A successful group create always leaves the app with usable local key material, so immediate sends, member invites, and later restart/rejoin flows all have the same truthful key state and key epoch.
- When an admin adds one or more members, the admin receives immediate success feedback and the conversation history shows a durable readable event naming the added members.
- When an invitee accepts, the invite disappears from pending review, the member list updates, and existing members see a durable readable join/accept event in the group history.
- When an invitee accepts, the immediate offline catch-up pass also converges any stored group reactions needed to make the just-recovered message history truthful, rather than showing messages first and waiting for a later background sweep to add reactions.
- If invite acceptance returns a bridge-timeout or similar join `bridgeError`, the product still converges to a live subscribed group through the shipped automatic recovery paths, and the user either sees honest degraded-state messaging during catch-up or an explicit retry path if recovery does not complete promptly.
- When an admin removes a member, remaining members see a readable removal event, and the removed member loses group access with clear feedback.
- When a member leaves voluntarily, remaining members see a durable readable `X left the group` event instead of the member silently disappearing with only local cleanup on the leaver's device.
- In a discussion group, any current member can send text, images, videos, GIFs, voice messages, quote replies, and reactions.
- In an announcement group, only admins can compose messages, while non-admin readers still see messages and can react.
- When several members react to a group message, tapping the visible reaction cluster reveals who reacted with which emoji using readable participant identity, and does not unexpectedly remove the viewer's own reaction on first tap.
- The reaction-participant inspection behavior is the same whether the user opened that group conversation from the main chat list in `Orbit` or from the group thread card in `Feed`.
- A received or sent group message renders as one clear card, without a second offset rounded shell that makes the row look visually duplicated.
- Long-pressing a supported group message opens one coherent context surface that keeps the selected message visible, exposes the approved action set honestly, and does not force users to remember a different gesture model than the mature 1:1 surface unless the product intentionally documents that difference.
- If a message is sent while peers are offline or connectivity is unstable, the sender still sees honest status and the message recovers through retry/resume paths instead of disappearing silently.
- Discussion and announcement sends stay truthful if the app backgrounds, the conversation route unmounts, or live topic peers drop to zero during send; the final row still converges to the correct terminal state instead of getting stranded in `sending`.
- If live topic peers are zero and relay inbox store also fails, the failed row still recovers through one explicit supported retry path instead of silently depending on a mismatched status bucket that no retry job owns.
- If a group message is replayed through relay inbox storage for offline members, the relay-stored payload is encrypted or otherwise opaque to relay operators while still remaining recoverable by legitimate group members.
- The encrypted replay contract works the same for text, quote replies, images, videos, GIF/file attachments, and recorded voice messages, so offline users catch up without a separate degraded media path.
- If members are added, removed, or leave while some peers are offline, replay still converges cleanly: legitimate members decrypt the messages they are entitled to for the correct membership/key epoch, and peers outside that valid window do not.

### Edge Cases

- A creator/admin with a valid username never renders as raw peer ID in the member list or other identity surfaces just because the local creator row was initialized without a username.
- Incoming group messages do not visually render as two overlapping cards or a duplicated bubble shell on some rows while other rows look normal.
- If `group:create` ever returns no `groupKey`, the app either repairs local key state before returning success or fails the create honestly; it does not leave a half-created group that cannot invite members, rejoin topics after restart, or persist truthful key-epoch metadata.
- If a zero-peer send fails both live fan-out and inbox store, the app does not leave a `failed` row with `inboxRetryPayload` that looks retryable in storage but is skipped by the intended retry owner forever.
- If a pending invite is accepted while offline group reactions are queued in the relay inbox, the newly joined member does not see a temporarily reaction-less message history just because the invite-accept drain path omitted `reactionRepo`.
- If invite acceptance persists the group locally but `callGroupJoinWithConfig(...)` times out or errors, the accepted group does not remain stranded indefinitely in a local-only state with no live subscription. Automatic rejoin on startup/resume/recovery either converges promptly or the product exposes an explicit retry path and truthful state.
- If group long-press action parity is intentionally partial before group edit/delete lands, the remaining group actions still appear through one clear surface and do not disappear entirely just because reactions are unavailable.
- If the viewing member has already reacted, inspecting the reaction cluster does not silently remove or replace that reaction on first tap.
- A member who is already in the group but is not a direct contact/friend can still send and receive group messages without a new friendship prerequisite.
- A non-friend member’s image/video/voice message still lands for the rest of the group because group fan-out follows membership state rather than friend state.
- If true profile-photo sharing is supported for group participants, a non-friend member’s picture resolves without requiring them to first become a contact; otherwise the fallback identity remains readable and intentional rather than broken-looking.
- Re-adding, duplicate inviting, or stale membership replays do not create duplicate members or duplicate timeline spam.
- Removed members cannot continue sending post-removal traffic, and members who were absent during removal still converge to the same final state after replay/recovery.
- Ordinary member voluntary leave does not silently skip the group timeline just because no admin removed them, and alternate callers of the leave flow do not bypass the visible audit trail.
- An offline member who later becomes newly added to the group does not get undecryptable junk or unauthorized historical replay; they recover exactly the backlog permitted by the current membership/key rules.
- Encrypting offline replay does not create a degraded path where text works but image/video/voice replay fails, loses attachment metadata, or becomes permanently stuck in pending download/render states.

### Preservation / Regression

- Existing invite safety remains intact: blocked senders, unknown senders, invalid payloads, duplicates, decline, and expiry still behave correctly.
- Any bootstrap-key-integrity fix preserves the normal current bridge contract where `group:create` returns key material on success, while preventing the fallback branch from silently creating a locally keyless group.
- Any fix for zero-peer plus inbox-fail recovery preserves the current separation between inbox-only retry and full resend, or deliberately simplifies it, but does not leave the branch recoverable only by accident.
- Any fix for invite-accept reaction catch-up preserves the current non-destructive replay model and later continuity sweeps, while making the first post-accept view of the group conversation reaction-truthful without waiting for a later global drain.
- Any fix for invite-accept join recovery preserves the current accepted-group persistence model and existing startup/resume/watchdog rejoin paths, while proving that a `bridgeError` acceptance does not leave the group indefinitely in a local-only state or falsely imply that live join already succeeded.
- Any future voluntary-leave timeline fix does not create duplicate `member_removed` / `left the group` events by conflating generic local cleanup with explicit broadcast semantics.
- Existing send lifecycle protections remain intact: background-task begin/end ordering, route-unmount completion, and zero-peer inbox fallback still produce honest final status for discussion and announcement sends.
- If relay inbox encryption is added for group replay, existing offline drain, cursor pagination, resend, dedupe, and recovery behavior still works without plaintext regressions on the relay path.
- Encryption of the relay replay path does not reduce current-version group reliability for text, image, video, or voice traffic, even across mixed online/offline membership changes.
- No old-build compatibility requirement should weaken the encrypted replay contract; the trust bar is correctness and seamlessness for the supported current build family.
- Existing announcement admin-only enforcement remains intact in Flutter and in the shared publish path.
- Existing reaction add/remove behavior and live reaction updates remain intact after adding any group reaction-participant inspection surface; counts stay truthful and explicit remove/change actions still work.
- Existing entry-point parity remains intact: opening the same group from `Orbit` or from `Feed` reaches the same reaction-inspection behavior and does not leave one surface with stale or missing message actions.
- Existing swipe-to-quote, reaction send/remove, and any later-adopted group long-press overlay stay behaviorally aligned instead of fighting each other with duplicate gestures or inconsistent action entry points.
- Existing swipe-to-quote, highlight, reaction, media, and message-status behavior remain intact after any fix for the doubled-bubble rendering artifact.
- Existing shipped metadata editing, notification mute, admin promotion/demotion, dissolve, quote reply, reactions, and media retry/delete behavior remain intact.
- Existing sender-side reliability guarantees remain intact: pre-persist, inbox fallback, failed-send retry, incomplete-upload retry, topic rejoin, and offline inbox drain.

Current direct coverage notes:

- Strong existing coverage already exists for create/join/send/media/recovery in `group_message_listener_test.dart`, `group_messaging_smoke_test.dart`, `group_resume_recovery_test.dart`, `announcement_happy_path_test.dart`, and `invite_round_trip_test.dart`.
- `group_conversation_wired_bg_task_test.dart` already proves important send-lifecycle behavior for discussion and announcement text sends across background/unmount and zero-peer fallback, but those cases are not yet called out as a first-class matrix row.
- No direct repo-local test was found for the shipped batch `members_added` UI path producing a durable in-chat add-members timeline.
- `accept_pending_group_invite_use_case_test.dart`, `group_list_wired_test.dart`, `group_message_listener_test.dart`, and `invite_round_trip_test.dart` now directly prove pending-invite acceptance emits one durable readable join timeline, keeps the honest degraded warning, drains immediate offline reactions on the supported path, and later converges after `bridgeError` without duplicate join history.
- No direct repo-local test was found for the defensive double-failure path where `group:create` returns no `groupKey`, fallback `group.keygen` also fails, and the app should reject or repair the create instead of saving a keyless local group.
- Existing unit coverage proves `0-peer + inbox fail -> error` in `send_group_message_use_case_test.dart`, and existing retry coverage proves generic failed-message resend plus inbox-only retry in isolation, but no direct repo-local test currently proves the specific `failed + inboxRetryPayload` row from the zero-peer branch is intentionally recovered by the shipped retry orchestration rather than skipped by inbox-only retry semantics.
- Report `70` closed the former sender-side reaction replay durability gap:
  `send_group_reaction_use_case.dart` and
  `remove_group_reaction_use_case.dart` now stage exact replay-store retry
  rows, `retry_failed_group_inbox_stores_use_case_test.dart` and
  `group_resume_recovery_test.dart` prove retry/resume convergence for
  reaction add/remove, and `announcement_happy_path_test.dart` confirms the
  announcement-reader path also ends with a truthful `stored` replay row after
  immediate success.
- No direct repo-local test was found proving that a member who leaves voluntarily creates a durable `X left the group` event for remaining members; current tests cover local leave cleanup and stop-receiving behavior more than visible timeline behavior.
- No direct repo-local test was found for creator/admin username backfill preventing peer-ID fallback in real group member lists.
- Existing reaction coverage proves chip rendering, tap forwarding, reaction live updates, and group reaction roundtrip behavior in `letter_card_test.dart`, `group_conversation_wired_test.dart`, and `group_reaction_roundtrip_test.dart`, but no direct repo-local test currently proves a group reaction participant list, readable reactor names, or a non-destructive tap-to-inspect contract.
- Current repo evidence shows both `Orbit` and `Feed` can open group conversations: `orbit_wired.dart` pushes `GroupConversationWired` on group-row tap, `feed_wired.dart` pushes `GroupConversationWired` for `GroupThreadFeedItem`, and `feed_wired_test.dart` already proves group thread cards render in Feed. No direct repo-local test currently proves that a future reaction-participant inspection surface works the same after entering the group from both `Orbit` and `Feed`.
- 1:1 already has deep direct coverage for the shared long-press overlay in `message_context_overlay_test.dart`, `conversation_screen_test.dart`, and `conversation_wired_test.dart`, but no equivalent repo-local group test family currently proves selected-message preview, action ordering, reply/copy parity, or graceful fallback when reactions are unavailable.
- Existing `letter_card_test.dart` and `group_conversation_screen_test.dart` cover content and interaction seams, but no direct repo-local visual regression or golden test was found for the doubled-bubble rendering artifact shown in the user screenshots.
- No direct repo-local test was found for non-friend profile-picture visibility inside group surfaces, even though messaging itself is currently membership-based rather than friendship-based.
- Current repo evidence indicates the group relay inbox path stores plaintext replay payloads, so no direct repo-local test currently proves encrypted offline group replay.
- No direct repo-local test currently proves encrypted replay remains correct across add/remove/leave boundaries or across text, image, video, and recorded voice backlog recovery.
