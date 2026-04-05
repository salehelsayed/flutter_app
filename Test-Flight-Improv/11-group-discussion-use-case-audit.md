# Use Case Audit: Group Discussions

**Total Implemented:** 27 use cases + 3 listeners = 30 features
**Test Files:** 28 | **Test Quality:** Core implemented flows are broadly covered (many Good / Excellent)

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
| 10 | Send group invite (P2P) | `send_group_invite_use_case.dart` | YES | Good |
| 11 | Handle incoming group invite | `handle_incoming_group_invite_use_case.dart` | YES | Excellent |

---

## Category 3: Sending Messages

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 12 | Send group message (text + media) | `send_group_message_use_case.dart` | YES | Excellent |
| 13 | Send group reaction | `send_group_reaction_use_case.dart` | YES | Good |
| 14 | Remove group reaction | `remove_group_reaction_use_case.dart` | YES | Good |

---

## Category 4: Receiving Messages

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 15 | Handle incoming group message | `handle_incoming_group_message_use_case.dart` | YES | Good |
| 16 | Handle incoming group reaction | `handle_incoming_group_reaction_use_case.dart` | YES | Good |
| 17 | Group message listener | `group_message_listener.dart` | YES | Excellent |

---

## Category 5: Message Lifecycle (Retry/Recovery)

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 18 | Retry failed group messages | `retry_failed_group_messages_use_case.dart` | YES | Good |
| 19 | Recover stuck sending messages | `recover_stuck_sending_group_messages_use_case.dart` | YES | Good |
| 20 | Retry incomplete media uploads | `retry_incomplete_group_uploads_use_case.dart` | YES | Good |
| 21 | Retry failed inbox stores | `retry_failed_group_inbox_stores_use_case.dart` | YES | Good |

---

## Category 6: Key Management

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 22 | Rotate group key | `rotate_group_key_use_case.dart` | YES | Good |
| 23 | Rotate + distribute group key | `rotate_and_distribute_group_key_use_case.dart` | YES | Excellent |
| 24 | Group key update listener | `group_key_update_listener.dart` | YES | Good |

---

## Category 7: Peer Discovery & Recovery

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 25 | Rejoin group topics on startup | `rejoin_group_topics_use_case.dart` | YES | Good |
| 26 | Drain offline inbox (paginated) | `drain_group_offline_inbox_use_case.dart` | YES | Excellent |
| 27 | Group invite listener | `group_invite_listener.dart` | YES | Excellent |

---

## Missing Features (NOT IMPLEMENTED)

| # | Feature | Impact | Priority |
|---|---------|--------|----------|
| 28 | **Delete single message** | No per-message soft-delete or tombstone | Medium |
| 29 | **Pin/unpin message** | No pinning in current group model/use case | Low |
| 30 | **Mute group notifications** | No app-layer mute flow | Medium |
| 31 | **Thread replies** | `quotedMessageId` exists, but no dedicated thread model/view | Low |
| 32 | **Search messages** | No full-text search | Medium |
| 33 | **Group avatar/photo** | No full avatar/media management flow | Low |
| 34 | **Update group name** | Name remains mostly locked after creation | Medium |
| 35 | **Update group description** | Description editing not currently surfaced | Low |
| 36 | **Promote/demote member** | Roles are not richly managed after creation | Medium |
| 37 | **Mute member** | No per-member moderation mute | Low |
| 38 | **Read receipts** | No sender-visible delivery/read tracking | Medium |
| 39 | **Admin transfer** | No dedicated admin handoff flow exists; the repo now blocks sole-admin self-leave instead of allowing leaderless exit | High |
| 40 | **Group dissolution** | No explicit admin-initiated dissolve workflow | Low |
| 41 | **Invite expiry** | Invites do not have strong expiry semantics | Low |

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

---

## Verdict

**Implemented core group-discussion features are well tested.** Lifecycle, sending, reactions, retry, key rotation, and recovery all have direct coverage. The remaining gaps are mainly product-scope features such as search, richer admin tooling, and message-level moderation. These are roadmap choices, not evidence of weak core architecture.
