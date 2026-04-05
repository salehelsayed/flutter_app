# Network Architecture: Group Messaging & Announcements

## Executive Summary

Robust small/medium-group messaging via GossipSub, symmetric group encryption, relay inbox fallback, and startup/resume recovery. The earlier pass overstated three things: group media retry is **already implemented**, announcement coverage inside the Flutter tree is stronger than initially reported, and announcement writer enforcement is now repo-locally verifiable in `go-mknoon`. The remove-vs-send boundary is now explicit instead of best-effort: live and replay paths persist a sender-specific `member_removed.removedAt` cutoff, and remaining peers accept removed-sender traffic only when `message.timestamp < removedAt`. Repo-owned membership add/remove system events are now also listener-authenticated against durable local creator/admin facts before local state is mutated, so raw non-admin bypass traffic no longer lands at the Flutter seam. Removed peers also keep the targeted replay/offline catch-up path that replays the same `member_removed` cleanup on reconnect. The remaining architectural risks are concentrated around receipt-less publish semantics, residual revocation timing outside that explicit cutoff, and unprofiled scale beyond the current sweet spot.

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
| `key_rotated` | Update stored key + keyEpoch |

---

## Member Management

### Add Member

1. Admin verifies own role
2. Persist member to DB
3. Sync config to bridge/native layer
4. New member becomes valid sender under the current config

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
- Temporary partition catch-up is now directly covered with a fake-network
  partition-heal regression: one peer misses two split-window sends, replays
  them through deterministic cursor pages on heal, and then resumes live group
  delivery after rejoin
- Resume/startup recovery now executes inside a shared runtime fence, so
  admin-only actions such as add/remove-member flows and announcement-group
  sends fail fast until replayed membership changes have settled

---

## Scalability Analysis

| Group Size | Discovery Time | Publish Latency | Status |
|-----------|---------------|-----------------|--------|
| 2-10 | Fast | Fast | Production-ready |
| 10-50 | Acceptable | Acceptable | Reasonable current target |
| 50-100 | Needs profiling | Needs profiling | Unproven |
| 100+ | Not currently justified | Not currently justified | Defer architecture work until measured |

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
| Group avatar/description management | UX |
| Rich admin transfer / dissolution flows | Admin |

---

## Already Present (Validated)

- Durable group media retry/recovery is already implemented
- Announcement auth/reaction coverage already exists in Flutter tests
- Announcement-specific create-group coverage now exists in Flutter tests
- Offline self-removal catch-up is implemented and directly covered by
  listener/drain/resume group regressions plus the `groups` gate
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
  live peers. Richer admin-role propagation remains unsupported scope.
- Replay protection is now directly covered: replaying the same group envelope
  through `GroupMessageListener` keeps both the persisted message count and the
  local notification count at `1`
- Duplicate membership-event idempotence is now directly covered: duplicate
  `member_added` converges to one canonical member/admin-role state, and stale
  repeat self-removal is ignored once the group is already deleted locally
- Stale membership-event rollback is now directly covered: a persisted
  group-level membership-event watermark makes the listener ignore older
  add/remove snapshots after newer state has already been applied
- Offline-add bootstrap is now directly covered: invite acceptance on reconnect
  bootstraps the group, drains missed inbox traffic, and allows immediate
  post-bootstrap participation
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
