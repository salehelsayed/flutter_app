# Network Architecture: Group Messaging & Announcements

## Executive Summary

Robust small/medium-group messaging via GossipSub, symmetric group encryption, relay inbox fallback, and startup/resume recovery. The earlier pass overstated three things: group media retry is **already implemented**, announcement coverage inside the Flutter tree is stronger than initially reported, and announcement writer enforcement is now repo-locally verifiable in `go-mknoon`. The remaining architectural risks are concentrated around receipt-less publish semantics, revocation timing, and unprofiled scale beyond the current sweet spot.

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

### System Messages (In-Band)

| Type | Action |
|------|--------|
| `member_added` | Persist member, sync config |
| `members_added` | Batch persist, sync config |
| `member_removed` | Remove from DB or leave group if self |
| `key_rotated` | Update stored key + keyEpoch |

---

## Member Management

### Add Member

1. Admin verifies own role
2. Persist member to DB
3. Sync config to bridge/native layer
4. New member becomes valid sender under the current config

### Group Invite (P2P)

- Encrypted 1:1 invite payload carries group config/key context
- Transport reuses 1:1 delivery logic (direct → relay → inbox)

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

### Inbox Drain

- Cursor-based retrieval
- Paged processing
- Resume until cursor exhausted

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
| Ordering remains best-effort | Low | UI sorts by timestamps; strict ordering is not guaranteed |

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
