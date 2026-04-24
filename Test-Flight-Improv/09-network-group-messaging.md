# Network Architecture: Group Messaging & Announcements

## Executive Summary

Robust small/medium-group messaging via GossipSub, symmetric group encryption,
relay inbox fallback, and startup/resume recovery. The earlier pass overstated
three things: group media retry is **already implemented**, announcement
coverage inside the Flutter tree is stronger than initially reported, and
announcement writer enforcement is now repo-locally verifiable in `go-mknoon`.
The remove-vs-send boundary is now explicit instead of best-effort: live and
replay paths persist a sender-specific `member_removed.removedAt` cutoff, and
remaining peers accept removed-sender traffic only when
`message.timestamp < removedAt`. Repo-owned membership
add/remove/role-update system events are now listener-authenticated against
durable local creator/admin facts before local state is mutated, and the acting
peer persists the same membership watermark locally when it originates a
role/remove change, so stale replays no longer rely on recipient-only ordering
state. Group backlog replay also now owns one explicit 7-day retention
boundary: non-system relay backlog older than the cutoff is skipped during
inbox drain, the group persists whether older backlog expired versus newer
messages were still retained, and the shipped group conversation/list surfaces
show truthful expired-versus-mixed-window copy instead of implying full
recovery. Removed peers also keep the targeted replay/offline catch-up path
that replays the same `member_removed` cleanup on reconnect. The remaining
architectural risks are concentrated around receipt-less publish semantics,
residual revocation timing outside that explicit cutoff, and scale beyond the
current repo-owned 50-member cap.

---

## Group Creation Flow

```
createGroup() → callGroupCreate(bridge) → Go creates group/topic/key
→ Save to DB (group + creator member/admin) → Return GroupModel
```

- Group key material is created during group setup
- Creator is registered as admin
- Topic subscription is joined immediately

### Group Types

| Type | Write Permission | Read | Reactions |
|------|-----------------|------|-----------|
| **chat** | admin + writer | all | all |
| **announcement** | admin only | all | all |
| **qa** | admin + writer | all | all |

`qa` still exists in model/schema but is filtered out of current group-creation UI.

---

## Message Sending

### Dual-Path Architecture

```
sendGroupMessage()
  ├── callGroupPublish(bridge)   ← GossipSub to online peers
  └── _tryInboxStore(bridge)     ← Relay inbox for offline members
      (concurrent)
```

### 4-Way Result Matrix

| Publish | Inbox | topicPeers | Status |
|---------|-------|-----------|--------|
| OK | OK | > 0 | `sent` |
| OK | OK | = 0 | `pending` / inbox-backed |
| OK | FAIL | > 0 | `sent` |
| FAIL | * | * | `failed` |

### Key Design: Pre-Persistence

- Group messages are stored before send with enough data for retry/recovery
- This is one of the strongest correctness properties in the current group flow

### V3 Group Envelope

```json
{
  "version": "3",
  "type": "group_message",
  "groupId": "...",
  "senderId": "...",
  "signature": "...",
  "keyEpoch": 3,
  "encrypted": {
    "ciphertext": "base64(...)",
    "nonce": "base64(...)"
  }
}
```

### GossipSub Config

- Flood publish for small-group reliability
- Topic validation checks signature/member/key-epoch constraints

---

## Message Receiving

```
Go GossipSub → validate signature → decrypt → emit group message
→ GroupMessageListener → persist/broadcast
→ notifications / media handling / local UI updates
```

- Group notifications now preserve an optional message anchor in the local
  payload and route target (`group:<groupId>|message:<messageId>` when
  present), so tapping a notification can open the correct group with the
  relevant message context highlighted while older unanchored
  `group:<groupId>` payloads remain valid.

### System Messages (In-Band)

| Type | Action |
|------|--------|
| `member_added` | Persist member and sync config only when the sender matches durable local creator/admin facts |
| `members_added` | Batch persist and sync config only when the sender matches durable local creator/admin facts |
| `member_removed` | Remove from DB or leave group if self only when the sender matches durable local creator/admin facts, persist a sender-specific removedAt cutoff for removed-sender traffic, and replay the same path during inbox drain |
| `member_role_updated` | Apply the authenticated authoritative member snapshot, update badges/permissions/myRole, and persist the same membership-event watermark used to reject stale role or removal replays |
| `group_dissolved` | Persist the group-wide dissolved state only when the sender matches current durable admin facts, store a readable timeline event, retain read-only history, reject later sends and reaction mutation, skip future rejoin attempts during restart/recovery, and keep later local cleanup device-local instead of publishing a new leave |
| `key_rotated` | Update stored key + keyEpoch |

---

## Member Management

### Add Member

1. Admin verifies own role
2. Persist member to DB
3. Sync config to bridge/native layer
4. New member becomes valid sender under the current config

### Current membership size contract

- The Flutter-owned product contract now enforces one explicit hard cap of
  `50` total members per group, including the creator/admin.
- `createGroupWithMembers(...)`, `addGroupMember(...)`, and the add-member
  batch invite flow all use the same shared
  `group_membership_limit_policy.dart` seam.
- Over-limit create and invite selections are rejected before local mutation,
  bridge config sync, or `members_added` publish.
- Batch overflow is all-or-nothing: admins must reduce the requested selection
  and retry; the existing group stays unchanged.
- The shipped create-group and add-member flows now surface truthful size-limit
  feedback instead of falling back to generic failure copy for this case.

### Remove Member

1. Admin updates membership/key state for the remaining group
2. Publish `member_removed` live with one stable `removedAt` cutoff so online peers converge immediately on the same remove-vs-send boundary
3. Store a targeted relay inbox payload for the removed peer with the same
   `member_removed` system envelope
4. On reconnect, replay that system envelope through `GroupMessageListener` so
   self-removal reuses the live `leaveGroup()` plus `groupRemovedStream` path
5. After rotation completes, the first subsequent real send by a remaining
   member uses the promoted key epoch from local group state rather than the
   pre-removal epoch; this removal-boundary proof is now covered directly in
   `test/features/groups/application/member_removal_integration_test.dart`

### Group Invite (P2P)

- Encrypted 1:1 invite payload carries group config/key context
- Transport reuses 1:1 delivery logic (direct → relay → inbox)
- Invite receipt now stores a durable pending review item instead of silently
  materializing the group; explicit accept reuses the join + inbox-drain path,
  while decline and expiry leave no local group/member/key ghost state behind
- The remove -> rotate -> re-invite path is now directly covered in
  `test/features/groups/integration/invite_round_trip_test.dart`: the invite
  carries the rotated epoch, the rejoined member persists that fresh epoch,
  and the member's first post-rejoin send uses the rotated epoch rather than
  stale removed credentials

### Roles

| Role | Send (chat) | Send (announcement) | React | Admin ops |
|------|-------------|---------------------|-------|-----------|
| admin | yes | yes | yes | yes |
| writer | yes | no | yes | no |
| reader | no | no | yes | no |

---

## Peer Discovery

### Discovery Loop (per group)

1. Wait for relay/circuit readiness
2. Initial jitter delay
3. Attempt direct dial of known members
4. Rendezvous fallback / re-registration loop
5. Backoff on repeated failure

### Connection Timeline

| Phase | Time |
|-------|------|
| Relay + circuit ready | ~0-1s |
| Jitter delay | ~0-1s |
| First successful dial | ~1-3s |
| Rendezvous fallback | slower path |

---

## Reconnection & Startup Recovery

### On App Resume

1. `rejoinGroupTopics()`
2. `drainGroupOfflineInbox()`
3. `recoverStuckSendingGroupMessages()`
4. `retryFailedGroupMessages()`
5. `retryIncompleteGroupUploads()` — this already exists and is important
6. admin-only group actions stay blocked while the rejoin + drain pair is
   still in flight, so stale cached membership/admin state cannot drive
   privileged behavior before replay settles

### Inbox Drain

- Cursor-based retrieval
- Paged processing
- Resume until cursor exhausted
- Replayed `{"__sys": ...}` envelopes are routed through
  `GroupMessageListener`, so offline `member_removed` catch-up reuses the live
  self-removal cleanup path and stops draining once the group is deleted
  locally, with direct proof that both same-page and later-cursor queued
  post-removal traffic are cut off for the removed peer
- Remaining-peer replay now uses the same persisted `member_removed.removedAt`
  cutoff instead of arrival timing alone, so removed-sender traffic still
  lands when `message.timestamp < removedAt` and is dropped during
  drain/reconnect at or after that cutoff
- Non-system replayed backlog now uses one repo-owned 7-day retention window
  (`groupBacklogRetentionWindow`): messages older than the cutoff are skipped
  during drain, while newer retained backlog still replays in cursor order
- Drain persists the latest expired and retained replay timestamps
  (`lastBacklogExpiredAt` / `lastBacklogRetainedAt`) on the group so the UI can
  distinguish fully expired backlog from mixed-window recovery
- Message-retention filtering is intentionally content-only: replayed
  `{"__sys": ...}` envelopes stay exempt from the cutoff so offline membership,
  self-removal, and dissolve convergence still apply even when those envelopes
  are older than the backlog message window
- Temporary partition catch-up is now directly covered with a fake-network
  partition-heal regression: one peer misses two split-window sends, replays
  them through deterministic cursor pages on heal, and then resumes live group
  delivery after rejoin
- Resume/startup recovery now executes inside a shared runtime fence, so
  admin-only actions such as add/remove-member flows and announcement-group
  sends fail fast until replayed membership changes have settled

---

## Scalability Analysis

The current Flutter app now owns one explicit product cap: groups can contain
up to `50` total members, including the creator/admin. Requests above that cap
are rejected before mutation rather than treated as merely unprofiled.

| Group Size | Discovery Time | Publish Latency | Status |
|-----------|---------------|-----------------|--------|
| 2-10 | Fast | Fast | Production-ready |
| 10-50 | Acceptable | Acceptable | Repo-owned current cap (50 total members max) |
| 51-100 | Rejected by app-owned contract | Rejected by app-owned contract | Above the current 50-member cap |
| 100+ | Rejected by app-owned contract | Rejected by app-owned contract | Defer until the product contract changes |

### Bottlenecks at Scale

- Direct dials grow with member count
- Flood publish overhead rises with group size
- Relay inbox cost rises with stored volume
- Discovery tuning becomes more important as groups grow

---

## Identified Issues

### Reliability Gaps

| Issue | Severity | Description |
|-------|----------|-------------|
| Bridge-package announcement publish proof is thinner than node-side proof | Low | Repo-local Go enforcement is verifiable in `go-mknoon/node`, `bridge.go` delegates `GroupPublish()` into `PublishGroupMessage()`, and `go test ./bridge` is green, but bridge publish tests are still mostly chat-shaped |
| GossipSub is still receipt-less | Medium | `topicPeers` is a snapshot, not proof of end-user receipt |
| Admin revocation timing | Medium | Revoked admins may still send until config/key state catches up |
| Strict global ordering remains best-effort outside the explicit remove-vs-send cutoff | Low | UI sorts by timestamps, same-sender sequential `M1 -> M2` delivery is directly covered, and the removed-sender boundary now uses deterministic `member_removed.removedAt`, but strict total ordering across arbitrary concurrent senders is still not guaranteed |

### Missing Features

| Feature | Impact |
|---------|--------|
| Full-text search | UX |
| Scheduled announcements | UX |
| Read receipts for announcements | UX |
| Rich admin transfer flows | Admin |

---

## Already Present (Validated)

- Durable group media retry/recovery is already implemented
- Announcement auth/reaction coverage already exists in Flutter tests
- Announcement-specific create-group coverage now exists in Flutter tests
- Offline self-removal catch-up is implemented and directly covered by
  listener/drain/resume group regressions plus the `groups` gate
- Group backlog retention is now directly covered: the repo owns one 7-day
  replay boundary, older non-system relay backlog expires during inbox drain,
  newer retained backlog still lands in order, and the shipped conversation and
  group-list surfaces show truthful expired-versus-mixed-window recovery state.
  Direct proof lives in
  `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`,
  `test/features/groups/integration/group_resume_recovery_test.dart`,
  `test/features/groups/presentation/group_conversation_screen_test.dart`,
  `test/features/groups/presentation/group_list_screen_test.dart`, and the
  same-day `./scripts/run_test_gates.sh groups` plus
  `./scripts/run_test_gates.sh baseline` runs
- Post-creation group metadata editing is now implemented: admins can rename a
  group and update description/photo from the shipped group-info surface, raw
  unauthorized metadata envelopes are rejected in the listener, and offline
  replay keeps the newest metadata watermark instead of rolling back to older
  edits. Direct proof lives in
  `test/features/groups/presentation/group_info_wired_test.dart`,
  `test/features/groups/application/group_message_listener_test.dart`, and
  `test/features/groups/integration/group_resume_recovery_test.dart`
- Same-sender sequential ordering is now directly covered: the three-user smoke
  regression in `test/features/groups/integration/group_messaging_smoke_test.dart`
  proves both recipients display `M1` before `M2` under the repo's
  timestamp-based ordering rule
- Remove-vs-send boundary convergence is now directly covered in both live and
  replay paths: `test/features/groups/integration/group_membership_smoke_test.dart`
  proves the live remaining-peer cutoff, while
  `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  and `test/features/groups/integration/group_resume_recovery_test.dart`
  prove inbox-drained and resumed remaining peers keep the same
  `message.timestamp < member_removed.removedAt` rule
- Post-removal store-and-forward cut-off is now directly covered: replayed
  self-removal stops both later queued messages on the current inbox page and
  later cursor pages for that group
- Removal-boundary key rotation is now directly covered: once the remove +
  rotate flow completes, the first subsequent real send persists and
  inbox-stores the rotated epoch
- Re-invite epoch refresh is now directly covered: the deterministic remove +
  rotate + re-invite round trip proves the invite and the rejoined member's
  first send both use the rotated epoch
- Stale-client resync is now directly covered: resume/startup recovery owns a
  shared fence across rejoin + inbox drain, and admin-only group actions are
  rejected until replayed membership changes settle
- Offline bystander membership convergence is now directly covered: one
  reconnect regression forces a member offline while another member is removed
  and a new member is added, then proves rejoin plus inbox drain converge the
  reconnecting bystander onto the same final member/admin map and metadata as
  live peers
- Admin-initiated group dissolve is now directly covered as a frozen-state
  network contract: the repo publishes authenticated `group_dissolved` system
  envelopes, accepts them only from current admins on live and replay paths,
  persists dissolved read-only history, blocks post-dissolve sends and
  reaction mutation, keeps dissolved groups out of restart/recovery rejoin,
  and lets each device later delete the recovered history locally from Group
  Info without publishing a new leave event. Direct proof lives in
  `test/features/groups/application/dissolve_group_use_case_test.dart`,
  `test/features/groups/application/group_message_listener_test.dart`,
  `test/features/groups/application/send_group_message_use_case_test.dart`,
  `test/features/groups/application/send_group_reaction_use_case_test.dart`,
  `test/features/groups/application/remove_group_reaction_use_case_test.dart`,
  `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`,
  `test/features/groups/application/rejoin_group_topics_use_case_test.dart`,
  `test/features/groups/application/delete_group_and_messages_use_case_test.dart`,
  `test/features/groups/integration/group_membership_smoke_test.dart`,
  `test/features/groups/presentation/group_info_wired_test.dart`,
  `test/features/feed/presentation/screens/feed_wired_test.dart`,
  `integration_test/group_recovery_e2e_test.dart`, and the same-day
  `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh feed`
  runs
- Post-creation admin-role propagation is now directly covered: promote,
  demote, multi-admin leave, and the concurrent/conflicting admin-change
  paths all converge under authenticated authoritative snapshots plus
  persisted `lastMembershipEventAt`, with direct proof in
  `test/features/groups/application/group_message_listener_test.dart`,
  `test/features/groups/presentation/group_info_wired_test.dart`, and
  `test/features/groups/integration/group_membership_smoke_test.dart`
- Replay protection is now directly covered: replaying the same group envelope
  through `GroupMessageListener` keeps both the persisted message count and the
  local notification count at `1`
- Per-group mute is now directly covered: `is_muted` persists in repo state,
  `GroupMessageListener` suppresses local notifications for muted groups
  without blocking delivery or unread counters, and the shipped group-info UI
  can toggle mute and unmute on demand
- Duplicate membership-event idempotence is now directly covered: duplicate
  `member_added` converges to one canonical member/admin-role state, and stale
  repeat self-removal is ignored once the group is already deleted locally
- Stale membership-event rollback is now directly covered: a persisted
  group-level membership-event watermark makes the listener ignore older
  add/remove snapshots after newer state has already been applied
- Offline-add bootstrap is now directly covered: invite acceptance on reconnect
  bootstraps the group, drains missed inbox traffic, and allows immediate
  post-bootstrap participation
- Explicit invite decision lifecycle is now directly covered: valid invites
  land as pending review items, the shipped group list exposes accept, decline,
  and expired states without silent auto-join, and accept/decline paths clean
  up pending rows while preserving the intended join or non-join contract
- Same-user multi-device convergence is now directly covered under one
  explicit repo-owned rule: once a second device has already materialized the
  group locally, group-authoritative membership state, metadata, and message
  history converge across same-identity devices, while mute, unread counters,
  local notification suppression, and pending-invite review remain
  installation-local. Sibling-device self-delivery is persisted as local
  `sent` history rather than unread incoming state, with direct proof in
  `lib/features/groups/domain/models/group_multi_device_policy.dart`,
  `test/features/groups/domain/models/group_multi_device_policy_test.dart`,
  `test/features/groups/integration/group_multi_device_convergence_test.dart`,
  `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`,
  `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`,
  and the same-day `./scripts/run_test_gates.sh groups` run
- Repo-local Go-side announcement writer enforcement is present in `go-mknoon/node/pubsub.go`, backed by announcement-specific node tests, and verified by `go test ./node` plus `go test ./bridge`
- Duplicate reaction prevention/replacement is already covered by current reaction storage/tests

---

## How to Measure Performance

### Key Metrics

| Metric | Formula | Target |
|--------|---------|--------|
| **Delivery rate** | publish success / total publishes | High for current small/medium groups |
| **Peer discovery time** | join → first peer connected | Track p95 for real groups |
| **Inbox drain completeness** | processed / stored | 100% |
| **Reconnection time** | app resume → first usable group state | Keep bounded |
| **Publish latency** | publish start → publish return | Track by group size |

### Instrumentation Points

1. `sendGroupMessage()` — publish duration + topicPeers
2. Discovery loop phases
3. Offline inbox drain pages/messages processed
4. Group rejoin time per group
5. Group upload retry counts/results

Start with local counters/timers before proposing discovery rewrites.

---

## Recommended Improvements

### P0 — Correctness
1. **Preserve the existing repo-local announcement writer-enforcement proof**
2. **Only add a bridge-package announcement `GroupPublish()` regression if package-boundary proof becomes necessary**

### P1 — Measurement / Scale
3. **Add local discovery/publish/inbox timing counters**
4. **Profile 50+ member groups before introducing new architecture**
5. **Only optimize reopen/discovery caching if traces show churn**

### P2 — UX
6. **Reconnection indicator for slow rejoin cases**
7. **Read receipts for announcements**
8. **Search**
9. **Scheduled announcements**
