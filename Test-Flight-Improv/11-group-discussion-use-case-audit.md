# Use Case Audit: Group Discussions

**Total Implemented:** 28 use cases + 3 listeners = 31 features
**Test Files:** 29 | **Test Quality:** Core implemented flows are broadly covered (many Good / Excellent)

---

## Category 1: Group Lifecycle

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 1 | Create group | `create_group_use_case.dart` | YES | Good |
| 2 | Create group with members (bulk) | `create_group_with_members_use_case.dart` | YES | Good |
| 3 | Join group | `join_group_use_case.dart` | YES | Good |
| 4 | Leave group | `leave_group_use_case.dart` | YES | Good |
| 5 | Delete group + messages | `delete_group_and_messages_use_case.dart` | YES | Good |
| 6 | Archive group | `archive_group_use_case.dart` | YES | Good |
| 7 | Unarchive group | `unarchive_group_use_case.dart` | YES | Good |

---

## Category 2: Member Management

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 8 | Add group member | `add_group_member_use_case.dart` | YES | Good |
| 9 | Remove group member | `remove_group_member_use_case.dart` | YES | Good |
| 10 | Update group member role | `update_group_member_role_use_case.dart` | YES | Good |
| 11 | Send group invite (P2P) | `send_group_invite_use_case.dart` | YES | Good |
| 12 | Handle incoming group invite | `handle_incoming_group_invite_use_case.dart` | YES | Excellent |

---

## Category 3: Sending Messages

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 13 | Send group message (text + media) | `send_group_message_use_case.dart` | YES | Excellent |
| 14 | Send group reaction | `send_group_reaction_use_case.dart` | YES | Good |
| 15 | Remove group reaction | `remove_group_reaction_use_case.dart` | YES | Good |

---

## Category 4: Receiving Messages

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 16 | Handle incoming group message | `handle_incoming_group_message_use_case.dart` | YES | Good |
| 17 | Handle incoming group reaction | `handle_incoming_group_reaction_use_case.dart` | YES | Good |
| 18 | Group message listener | `group_message_listener.dart` | YES | Excellent |

---

## Category 5: Message Lifecycle (Retry/Recovery)

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 19 | Retry failed group messages | `retry_failed_group_messages_use_case.dart` | YES | Good |
| 20 | Recover stuck sending messages | `recover_stuck_sending_group_messages_use_case.dart` | YES | Good |
| 21 | Retry incomplete media uploads | `retry_incomplete_group_uploads_use_case.dart` | YES | Good |
| 22 | Retry failed inbox stores | `retry_failed_group_inbox_stores_use_case.dart` | YES | Good |

---

## Category 6: Key Management

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 23 | Rotate group key | `rotate_group_key_use_case.dart` | YES | Good |
| 24 | Rotate + distribute group key | `rotate_and_distribute_group_key_use_case.dart` | YES | Excellent |
| 25 | Group key update listener | `group_key_update_listener.dart` | YES | Good |

---

## Category 7: Peer Discovery & Recovery

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 26 | Rejoin group topics on startup | `rejoin_group_topics_use_case.dart` | YES | Good |
| 27 | Drain offline inbox (paginated) | `drain_group_offline_inbox_use_case.dart` | YES | Excellent |
| 28 | Group invite listener | `group_invite_listener.dart` | YES | Excellent |

---

## Missing Features (NOT IMPLEMENTED)

| # | Feature | Impact | Priority |
|---|---------|--------|----------|
| 28 | **Delete single message** | No per-message soft-delete or tombstone | Medium |
| 29 | **Pin/unpin message** | No pinning in current group model/use case | Low |
| 31 | **Thread replies** | `quotedMessageId` exists, but no dedicated thread model/view | Low |
| 32 | **Search messages** | No full-text search | Medium |
| 37 | **Mute member** | No per-member moderation mute | Low |
| 38 | **Read receipts** | No sender-visible delivery/read tracking | Medium |
| 39 | **Admin transfer** | No dedicated admin handoff flow exists; the repo now blocks sole-admin self-leave instead of allowing leaderless exit | High |

---

## Already Present (Validated)

- Duplicate reaction replacement/prevention is already handled by current reaction storage/tests
- Durable group media retry/recovery already exists
- Core group message, invite, and resume/drain flows are already well tested
- Duplicate group-member adds are now rejected before config sync, and stale picker selections no longer emit duplicate `members_added` side effects
- Non-member group removals are now rejected before config sync, and stale remove attempts surface an error without removal broadcast side effects
- Remaining members now see a readable removal timeline event on the live conversation stream while the converged member list still updates correctly
- Group notifications now stay off while a member is removed and resume only after that member's rejoin becomes effective again
- Remaining members now see a readable re-add timeline event on the live conversation stream while the converged member list still updates correctly
- Offline re-invites now have an exact inbox-fallback reconnect regression proving the removed member restores rotated group state before resumed sends
- Member-role group sends are now blocked until bootstrap key state exists locally, with direct proof in `send_group_message_use_case_test.dart` and `group_membership_smoke_test.dart`
- Last-admin self-leave is now blocked, so the repo no longer allows groups to become leaderless through the local leave flow
- Post-creation admin promotion and demotion are now landed member-management flows, with direct proof in `update_group_member_role_use_case_test.dart`, `group_info_wired_test.dart`, and `group_membership_smoke_test.dart`
- Multi-admin leave now keeps the remaining admin path healthy by broadcasting the leaving admin's self-removal, rotating the key for remaining peers, and persisting the same membership watermark used for stale-event rejection
- Concurrent and conflicting multi-admin membership changes now converge under authenticated authoritative snapshots plus persisted `lastMembershipEventAt`, with direct listener and smoke proof in `group_message_listener_test.dart` and `group_membership_smoke_test.dart`
- Post-creation group metadata editing is now a shipped contract: admins can rename a group and update its description/photo from group info, non-admins do not see the edit affordance, unauthorized raw `group_metadata_updated` envelopes are ignored, and offline peers converge to the final metadata state under repeated edits. Direct proof lives in `group_info_screen_test.dart`, `group_info_wired_test.dart`, `group_message_listener_test.dart`, `group_list_wired_test.dart`, `group_conversation_wired_test.dart`, and `group_resume_recovery_test.dart`
- Per-group mute is now a shipped notification contract: members can mute or unmute one group from group info, the repo persists `is_muted`, and `GroupMessageListener` suppresses local notifications for muted groups without dropping delivery or unread state. Direct proof lives in `set_group_muted_use_case_test.dart`, `group_message_listener_test.dart`, `group_info_screen_test.dart`, `group_info_wired_test.dart`, and the same-day `groups` gate.
- Explicit invite accept, decline, and expiry are now a shipped contract: invite receipt stores a pending review item instead of auto-joining, accepting reuses the persisted join plus inbox-drain path, and decline or expiry leave no ghost group state behind. Direct proof lives in `group_invite_listener_test.dart`, `accept_pending_group_invite_use_case_test.dart`, `decline_pending_group_invite_use_case_test.dart`, `invite_round_trip_test.dart`, `group_list_screen_test.dart`, `group_list_wired_test.dart`, and the same-day `groups` gate.
- Admin-initiated group dissolve is now a shipped contract: admins can dissolve from group info, all members retain read-only history, offline peers converge through authenticated `group_dissolved` replay, and post-dissolve send/rejoin paths stay blocked. Direct proof lives in `dissolve_group_use_case_test.dart`, `group_message_listener_test.dart`, `send_group_message_use_case_test.dart`, `rejoin_group_topics_use_case_test.dart`, `group_membership_smoke_test.dart`, `group_info_wired_test.dart`, `group_conversation_wired_test.dart`, and the same-day `groups` gate.

---

## Verdict

**Implemented core group-discussion features are well tested.** Lifecycle, sending, reactions, retry, key rotation, recovery, post-creation admin-role management, post-creation group metadata editing, per-group mute, explicit invite-decision flows, and admin-initiated dissolve all have direct coverage. The remaining gaps are mainly product-scope features such as search, admin transfer, and message-level moderation. These are roadmap choices, not evidence of weak core architecture.
