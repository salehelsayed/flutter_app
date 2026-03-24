# Group & Announcement Message Delivery Reliability TDD Plan

**Status:** Draft
**Date:** 2026-03-24
**Companion:** [Message Delivery Reliability TDD Plan (1:1)](message-delivery-reliability-tdd-plan.md)

---

## Section 0: Plan Overview

### Core Bug

Same fundamental failure mode as the 1:1 send-then-lock bug, but amplified by group-specific architecture:

A user sends a group message, taps Send, and immediately locks the device. The message may be permanently lost because:

1. **No background task protection.** The group send pipeline (media upload, GossipSub publish, inbox store) runs unprotected on iOS. Locking the device suspends the process mid-flight.
2. **No retry for failed sends.** `sendGroupMessage` returns `SendGroupMessageResult.error` on publish failure, the Wired layer sets status to `'failed'`, but there is zero retry infrastructure for group messages. No resume sweep exists today. No reconnect sweep exists today. Worse, the use case does not own optimistic persistence for all callers, so some sends are not even retry-discoverable after a crash.
3. **GossipSub is fire-and-forget.** `topic.Publish()` returning nil does NOT mean any peer received the message. If 0 mesh peers are connected (common after relay reconnect or discovery delay), the message is silently dropped by the network.
4. **Inbox store is fire-and-forget.** `_safeInboxStore` is started concurrently with publish and wraps `callGroupInboxStore` in a try/catch that swallows all errors. If the relay is unreachable or slow, the inbox copy is silently lost, and the current structure makes it easy to accidentally double-store when adding 0-peer compensation.
5. **Optimistic DB row has no universal recovery path.** `group_conversation_wired.dart` creates an optimistic `GroupMessage` with `status: 'sending'` and persists it before the publish call, but `feed_wired.dart` calls `sendGroupMessage()` directly without pre-persisting a retryable row. Crash behavior differs by caller.
6. **Media uploads are sequential.** Group media uploads happen in a `for` loop with `await` (lines 382-403 of `group_conversation_wired.dart`). With 3 images, each waits for the previous to finish. Voice has additional durability and stable-ID gaps beyond this loop.
7. **3 sequential DB reads before send.** `sendGroupMessage` use case (lines 91-132) awaits `getGroup`, `getLatestKey`, and `_loadGroupPushRecipients` one-by-one. These are independent queries that could run in parallel with `Future.wait()`.
8. **Local retry/recovery changes do not flow back into open group UI.** Group screens listen to inbound listener events, not to a general outgoing message mutation stream. A DB fix alone can leave visible state stale until reload.

### Scope

**In scope:**
- Group chat text, media, and voice sends (all `GroupType` values: `chat`, `announcement`, `qa`)
- Announcement text, media, and voice sends (admin-only write path, same use case, same bugs)
- Send-then-lock lifecycle failure for group messages
- Stuck `'sending'` group message recovery (DB sweep + retry)
- Failed group message retry (resume sweep; reconnect sweep only if topic-ready ordering is defined)
- GossipSub 0-peer publish detection and fallback
- Inbox store promotion from optional fire-and-forget to required fallback
- Parallel media upload + group media upload retry
- Voice message reliability for groups (upload + publish pipeline)
- iOS background task protection for group send pipeline
- Lifecycle pause handler for group in-flight messages
- Key rotation safety window (messages sent with old key during rotation must not be silently dropped)
- Member config sync atomicity (add/remove member config update must not race with in-flight messages)
- Announcement-specific acceptance proofs (admin-only send authorization, reader rejection)
- Wire envelope persistence design for group message retry
- Early recovery default for this plan: text-only retry first. Failed media/voice rows are skipped until Sections 5 and 6 land durable retry inputs and then expand retry scope.

**Out of scope:**
- Group history sync / message backfill (retrieving missed messages from relay inbox on rejoin)
- Causal ordering / vector clocks (messages may arrive out of order; this is accepted)
- Relay capacity scaling (relay inbox storage limits, 500 msg cap, 7-day TTL, eviction policy)
- Cross-relay deduplication (single relay assumption)
- Reader role enforcement at the transport layer (enforced at application layer only)
- QA-type group-specific features (question/answer threading, voting)
- 1:1 message reliability (covered by companion plan)

### Implementation Guardrails

This plan is intentionally sufficient, not perfect. If a section contains both a minimal reliable fix and a larger hardening design, the minimal reliable fix wins unless the section explicitly adds the storage, API, and test scope required for the larger design.

Cross-section ownership:
- The unified send contract is owned by the Database Schema + Send Flow work. `sendGroupMessage()` must own pre-persisted outgoing rows and persisted retry payloads for all production callers before recovery/retry sections are implemented.
- Section 1 owns group stuck-send recovery and failed-message retry.
- Section 4 owns inbox outcome persistence and inbox-only retry.
- Section 8 owns 0-peer publish semantics and `successNoPeers` / `pending`.
- Section 9 is split into a sufficient atomicity phase and a deferred hardening phase.

### Architecture Summary

Group messages use a **dual-path delivery architecture**:

1. **GossipSub (live path):** `callGroupPublish` sends the message via Go's `GroupPublish`, which encrypts (AES-256-GCM with the group symmetric key), signs (Ed25519), wraps in a v3 envelope, and calls `topic.Publish()`. Go uses `WithFloodPublish(true)`, meaning the message is sent to ALL directly connected peers, not just a GossipSub mesh subset. However, if no peers are connected to the topic, the message is dropped.

2. **Relay inbox (store-and-forward path):** `_safeInboxStore` sends a plaintext JSON payload (not the v3 encrypted envelope) to the relay via `callGroupInboxStore`. The relay stores it per-recipient and triggers FCM push. Offline members pull from inbox on reconnect via `callGroupInboxRetrieve` / `callGroupInboxRetrieveWithCursor`.

**Current send flow in `sendGroupMessage`:**
- Both paths run **concurrently** (`publishFuture` + `inboxFuture`) — confirmed truly parallel on the native side (GCD concurrent queue)
- Publish result determines success/failure return value
- Inbox store failure is silently swallowed
- Local DB save happens **only after** both paths complete
- No optimistic DB row is created by the use case (the Wired layer creates one before calling the use case, but only `GroupConversationWired` does so today; `FeedWired` does not)
- Open group UI listens to inbound listener events only; local outgoing status recovery is not automatically pushed back into mounted screens

**Key difference from 1:1:** There is no `wireEnvelope` persisted for group messages. The v3 envelope is constructed and published inside Go, never returned to Dart. Retry must re-encrypt and re-publish, not replay a cached envelope. This means retry for groups is more expensive (requires group key + sender keys) and must handle key rotation (the group key epoch may have changed between the original send and the retry).

**Encryption:** AES-256-GCM with a shared symmetric group key, rotated on member removal. Key generation number (`keyGeneration` / `keyEpoch`) is included in the message envelope so receivers can select the correct decryption key.

**Group types relevant to this plan:**
- `GroupType.chat` — all members can send (writer role)
- `GroupType.announcement` — only admin can send; members are readers
- `GroupType.qa` — all members can send (same write path as chat)

All three types use the same `sendGroupMessage` use case and the same dual-path delivery. The only difference is the authorization check at line 102 of `send_group_message_use_case.dart`.

### Section Map

| Section | Title | What It Fixes | Layer | Priority |
|---|---|---|---|---|
| 1 | Stuck-Sending Recovery | `'sending'` group messages orphaned in `group_messages` table forever after app kill | Dart: DB helpers, group message repository, new group message retrier, resume handler | P0 |
| 2 | Lifecycle Pause Handler | No `AppLifecycleState.paused` handler for group in-flight messages | Dart: `handleAppPaused()` extension, `_MyAppState` lifecycle integration | P1 |
| 3 | iOS Background Task Protection | Group send pipeline (upload, GossipSub publish, inbox store) runs unprotected on iOS | Dart + Swift: `bg:begin`/`bg:end` in `group_conversation_wired.dart` | P1 |
| 4 | Inbox Store as Required Fallback | `_safeInboxStore` silently swallows all failures; messages appear "sent" while nobody receives them | Dart: `sendGroupMessage` use case, new inbox retry use case | P0 |
| 5 | Parallel Media Upload + Group Media Retry | Sequential media uploads + sequential DB reads + no group media retry | Dart: wired `Future.wait()`, use case parallel reads, new retry use case | P1 |
| 6 | Voice Message Reliability | Voice temp file volatility, dual-ID orphan, no pre-upload persistence | Dart: wired durable copy, stable ID threading, retry integration | P2 |
| 7 | Key Rotation Safety Window | Messages silently dropped during key rotation race window | Go: dual-epoch grace period + Dart: reorder rotation | P2 |
| 8 | 0-Peer Publish Detection | `topic.Publish()` returns nil with 0 peers; message lost silently | Go: peer count in response + Dart: escalate inbox store | P0 |
| 9 | Member Config Sync Atomicity | DB vs Go validator split-brain on add/remove member | Dart: rollback, resync, sequential queue | P2 |
| 10 | Announcement Acceptance Proofs | End-to-end proofs for announcement write constraint + reliability | Dart: targeted acceptance tests | P3 |
| 11 | Test Infrastructure | Cross-cutting integration test extensions | Dart: FakeGroupPubSubNetwork + GroupTestUser + harness extensions | P3 |
| DB | Database Schema Changes | New columns for reliability tracking | Dart: migrations, model, DB helpers | P0 |
| Go | Go-Side Changes | Peer count, grace period, decryption events, pre-check | Go: pubsub, bridge, config | P0-P2 |

### Dependencies Between Sections

```
DB Schema + Wire Envelope Persistence
    |
    v
Section 4 (inbox as required fallback) <--> Section 8 (0-peer detection)
    |
    v
Section 1 (stuck-sending recovery)
    |
    ├──> Section 2 (lifecycle pause)
    ├──> Section 5 (parallel media upload + retry)
    |         |
    |         └──> Section 6 (voice reliability)
    |
    └──> Section 7 (key rotation safety)

Section 3 (iOS background task)     — depends on final send-path contract from Sections 4/5/6
Section 9 (member config sync)      — independent
Section 10 (announcement proofs)    — depends on Sections 1, 3, 7, 8 and supported media scope
Section 11 (test infrastructure)    — built incrementally, finalized after all above
```

### Recommended Implementation Order

| Phase | Sections | Weeks | Rationale |
|---|---|---|---|
| **Phase 1 (P0)** | DB Schema, Wire Envelope Persistence, S4, S8, S1, Go 10.1 | 1-3 | Establish one coherent send contract first: pre-persist, inbox retry payloads, 0-peer detection, and retryable rows for all callers. |
| **Phase 2 (P1)** | S2, S3, S5, Go 10.2-10.3 | 4-6 | Lifecycle defense, background task coverage, durable media retry, and core Go observability / grace-period work. |
| **Phase 3 (P2-P3)** | S6, S7, S9, S10, S11, Go 10.4 | 7-9 | Voice specialization, full key-rotation coordination, config sync hardening, acceptance proofs, and end-to-end test infra. |

### Can Each Section Ship Independently?

| Section | Independent? | Notes |
|---|---|---|
| Section 1 | **Qualified** | Standalone only after the plan makes `sendGroupMessage()` own pre-persisted retryable rows for all production callers, not just `GroupConversationWired`. |
| Section 2 | **After Section 1** | Early recovery in this plan is text-only first; media/voice retry expands only after Sections 5 and 6 land. |
| Section 3 | **Qualified — requires Dart + Swift** | Same `bg:begin`/`bg:end` MethodChannel as 1:1 (already exists). Presentation-layer only. |
| Section 4 | **Qualified — benefits from S8** | Can ship alone to make inbox store failures visible, but full value requires S8's 0-peer detection. |
| Section 5 | **After Section 1** | Also depends on durable pending-upload storage semantics and retry-time path resolution. |
| Section 6 | **After Section 5** | Voice is a specialization of media upload retry and should share the same durable pending-path contract. |
| Section 7 | **Qualified** | Can ship alone but retry re-encryption interacts with S1's retry path. |
| Section 8 | **Qualified — benefits from S4** | Can ship alone to surface 0-peer detection, but the fallback action requires S4's inbox-as-required pattern. |
| Section 9 | **Yes** | Standalone config consistency fix. |
| Section 10 | **After Sections 1 + 3 + 7 + 8** | Tests retry paths, bg-task behavior, 0-peer semantics, and key rotation together. |
| Section 11 | **After all others** | Integration tests reference code from all sections. |

### Key Differences from 1:1 Plan

| Concern | 1:1 | Group |
|---|---|---|
| Delivery mechanism | Direct P2P stream or relay inbox (sequential) | GossipSub flood publish + relay inbox (concurrent) |
| Wire envelope | Persisted to DB before send; replay on retry | Not persisted; constructed inside Go; retry must re-encrypt |
| Encryption | ML-KEM-768 per-recipient | AES-256-GCM shared symmetric key with epoch |
| Retry key management | Recipient's ML-KEM public key (stable) | Group key may have rotated between send and retry |
| Delivery confirmation | Recipient ack (or inbox acceptance) | None — GossipSub is fire-and-forget, inbox store is fire-and-forget |
| Optimistic DB row | Created by Wired, retried by `PendingMessageRetrier` | Created only by some callers today (`GroupConversationWired`, not `FeedWired`); no group retrier exists |
| Member changes during send | N/A | Key rotation, member add/remove can race with in-flight messages |
| Background task call sites | `conversation_wired.dart` (3 sites), `feed_wired.dart` (1 site) | `group_conversation_wired.dart` (2 sites: `_onSend`, voice stop handler) |
| Media uploads | Sequential (`for` + `await`) | Sequential → **should be parallel** (`Future.wait`) |
| Local UI mutation stream | Existing message listeners and wired updates cover retry-visible state | Inbound listener only; local outgoing retry/recovery state is not pushed back into mounted group UI |

### Estimated Test Totals

| Section | Unit | Integration | Total |
|---|---|---|---|
| 1. Stuck-Sending Recovery | 8 | 4 | 12 |
| 2. Lifecycle Pause Handler | 6 | 5 | 11 |
| 3. iOS Background Task | 4 | 3 | 7 |
| 4. Inbox Store Fallback | 7 | 5 | 12 |
| 5. Parallel Media Upload | 8 | 6 | 14 |
| 6. Voice Message | 5 | 4 | 9 |
| 7. Key Rotation Safety | 6 | 3 | 9 |
| 8. 0-Peer Detection | 5 | 4 | 9 |
| 9. Member Config Sync | 6 | 4 | 10 |
| 10. Announcement Proofs | 5 | 5 | 10 |
| 11. Test Infrastructure | 10 | 2 | 12 |

Totals should be recalculated after implementation planning stabilizes. The current table is illustrative only, and some simplified unit-test assumptions in the draft have already been replaced with more repo-accurate widget and integration proofs.

---

## Database Schema Changes

### Current Schema (Reference)

The `group_messages` table was created in migration `018_group_messages_tables.dart`:

```sql
CREATE TABLE IF NOT EXISTS group_messages (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  sender_peer_id TEXT NOT NULL,
  sender_username TEXT,
  text TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  key_generation INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'sent',
  is_incoming INTEGER NOT NULL DEFAULT 1,
  read_at TEXT,
  created_at TEXT NOT NULL
);
```

Migration `026_group_quoted_message_id.dart` later added `quoted_message_id TEXT`.

The 1:1 `messages` table already has `wire_envelope TEXT` (migration 014) and `transport TEXT` (migration 012). The group table has neither, nor any inbox-tracking or upload-retry columns.

### Revised Schema Scope

Keep these new columns on `group_messages`:
- `wire_envelope TEXT`
- `inbox_stored INTEGER NOT NULL DEFAULT 0`
- `inbox_retry_payload TEXT`

Do not add `upload_retry_count` to `group_messages`.

`upload_retry_count` is attachment-scoped state and belongs on `media_attachments`, not on `group_messages`. Multi-attachment sends need retry state per attachment.

`pending` is a new outgoing status value only. No `group_messages` schema change is required for `pending` because the existing `status` column is already unconstrained `TEXT`.

### New Migration: `041_group_message_reliability_columns.dart`

**File:** `lib/core/database/migrations/041_group_message_reliability_columns.dart`

Three `ALTER TABLE` statements, each guarded by a `PRAGMA table_info` check (idempotent, matching the pattern in `014_wire_envelope_column.dart`):

```sql
-- 1. Serialized publish parameters (JSON) for retry without full re-encryption roundtrip.
--    Stores plaintext inputs needed to reconstruct a callGroupPublish call.
--    Cleared (set NULL) once message is confirmed published.
ALTER TABLE group_messages ADD COLUMN wire_envelope TEXT;

-- 2. Whether the message was stored in the inbox relay for offline members.
--    0 = not stored (or not attempted), 1 = stored successfully.
ALTER TABLE group_messages ADD COLUMN inbox_stored INTEGER NOT NULL DEFAULT 0;

-- 3. Serialized inbox-store parameters (JSON) for retrying callGroupInboxStore
--    without guessing push recipients or payload structure from the message row.
ALTER TABLE group_messages ADD COLUMN inbox_retry_payload TEXT;
```

### GroupMessage Model Changes

Three new fields on the `GroupMessage` class:

| Field | Type | Default | DB Column | Purpose |
|---|---|---|---|---|
| `wireEnvelope` | `String?` | `null` | `wire_envelope` | Cached plaintext publish parameters for retry. Not the encrypted v3 envelope — stores the inputs needed to reconstruct a `callGroupPublish` call. Does NOT contain `senderPrivateKey` (resolved from `SecureKeyStore` at retry time). |
| `inboxStored` | `bool` | `false` | `inbox_stored` | `0`/`1` integer in DB, `bool` in model. Tracks relay inbox confirmation. |
| `inboxRetryPayload` | `String?` | `null` | `inbox_retry_payload` | Cached plaintext inbox-store parameters for retry. Stores the exact request inputs required to reconstruct `callGroupInboxStore` for offline recipients. |

**Constructor change:**
```dart
const GroupMessage({
  // ... existing fields ...
  this.wireEnvelope,
  this.inboxStored = false,
  this.inboxRetryPayload,
});
```

**`fromMap` additions:**
```dart
wireEnvelope: map['wire_envelope'] as String?,
inboxStored: (map['inbox_stored'] as int? ?? 0) == 1,
inboxRetryPayload: map['inbox_retry_payload'] as String?,
```

**`toMap` additions:**
```dart
'wire_envelope': wireEnvelope,
'inbox_stored': inboxStored ? 1 : 0,
'inbox_retry_payload': inboxRetryPayload,
```

**`copyWith` additions:**
```dart
Object? wireEnvelope = _sentinel,  // sentinel pattern for nullable clear
bool? inboxStored,
Object? inboxRetryPayload = _sentinel,
```

`pending` is a first-class outgoing status value in the `GroupMessage` model, but it does not require a schema migration because `group_messages.status` is already free-form `TEXT`.

### New DB Helper Functions

All functions in `lib/core/database/helpers/group_messages_db_helpers.dart`:

#### `dbLoadStuckSendingGroupMessages(Database db, {required DateTime olderThan, int limit = 50})`

```sql
SELECT * FROM group_messages
WHERE status = 'sending' AND is_incoming = 0 AND timestamp < ?
ORDER BY timestamp ASC LIMIT ?
```

#### `dbLoadFailedOutgoingGroupMessages(Database db, {int limit = 50})`

```sql
SELECT * FROM group_messages
WHERE status = 'failed' AND is_incoming = 0
ORDER BY timestamp ASC LIMIT ?
```

#### `dbLoadGroupMessagesWithFailedInboxStore(Database db, {int limit = 50})`

```sql
SELECT * FROM group_messages
WHERE is_incoming = 0 AND inbox_stored = 0
  AND status IN ('sent', 'pending') AND inbox_retry_payload IS NOT NULL
ORDER BY timestamp ASC LIMIT ?
```

#### `dbTransitionGroupSendingToFailed(Database db, {required DateTime olderThan})`

```sql
UPDATE group_messages SET status = 'failed'
WHERE status = 'sending' AND is_incoming = 0 AND timestamp < ?
```
Returns `int` (rows updated).

#### `dbUpdateGroupMessageInboxStored(Database db, String id, {required bool stored})`

```sql
UPDATE group_messages SET inbox_stored = ? WHERE id = ?
```

#### `dbUpdateGroupMessageInboxRetryPayload(Database db, String id, String? inboxRetryPayload)`

```sql
UPDATE group_messages SET inbox_retry_payload = ? WHERE id = ?
```

#### `dbUpdateGroupMessageWireEnvelope(Database db, String id, String? wireEnvelope)`

```sql
UPDATE group_messages SET wire_envelope = ? WHERE id = ?
```

### DB Schema TDD Tests

**File:** `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`

#### Migration Tests

1. `adds wire_envelope column` — PRAGMA table_info check
2. `adds inbox_stored column with default 0` — insert row without specifying, read back
3. `adds inbox_retry_payload column` — PRAGMA table_info check
4. `is idempotent` — run migration twice, no error
5. `preserves existing rows` — insert before migration, run migration, verify unchanged

#### dbLoadStuckSendingGroupMessages Tests

6. `returns empty list when no messages exist`
7. `returns only outgoing sending messages older than threshold` — seed old + recent, assert only old returned
8. `excludes incoming messages`
9. `excludes non-sending statuses`
10. `ordered by timestamp ASC`
11. `respects limit`

#### dbLoadFailedOutgoingGroupMessages Tests

12. `returns only failed outgoing messages`
13. `does not return failed incoming messages`
14. `ordered by timestamp ASC`
15. `respects limit`

#### dbLoadGroupMessagesWithFailedInboxStore Tests

16. `returns sent messages with inbox_stored=0 and inbox_retry_payload set`
17. `excludes messages where inbox_stored=1`
18. `excludes messages with null inbox_retry_payload`
19. `includes pending messages with inbox_stored=0 and retry payload set`
20. `excludes incoming messages`

#### dbTransitionGroupSendingToFailed Tests

21. `transitions old sending messages to failed`
22. `does not touch recent sending messages`
23. `does not touch incoming messages`
24. `preserves wire_envelope on transitioned rows`
25. `returns count of affected rows`

#### Update Helper Tests

26. `dbUpdateGroupMessageInboxStored sets to 1`
27. `dbUpdateGroupMessageInboxStored sets back to 0`
28. `dbUpdateGroupMessageInboxRetryPayload stores JSON`
29. `dbUpdateGroupMessageInboxRetryPayload clears with null`
30. `dbUpdateGroupMessageWireEnvelope stores JSON`
31. `dbUpdateGroupMessageWireEnvelope clears with null`
32. `does not affect other rows`

#### GroupMessage Model Tests

33. `fromMap reads wire_envelope`
34. `fromMap defaults wire_envelope to null`
35. `fromMap reads inbox_stored as bool`
36. `fromMap reads inbox_retry_payload`
37. `toMap serializes inbox_stored as int`
38. `copyWith sentinel clears wireEnvelope to null`
39. `copyWith sentinel clears inboxRetryPayload to null`
40. `copyWith preserves inboxRetryPayload when not specified`
41. `copyWith preserves wireEnvelope when not specified`

---

## Section 1: Stuck-Sending Recovery for Group Messages

### 1.1 Problem Statement

Group messages can become permanently stuck in `status='sending'` if the app crashes, is killed by the OS, or is suspended mid-publish. Unlike 1:1 messaging, which has a full recovery pipeline (`recoverStuckSendingMessages` → `retryFailedMessages` → `retryUnackedMessages`), group messaging has zero equivalent. A group message saved to the DB as `'sending'` before `callGroupPublish` completes will remain in that state forever — the user sees a spinner that never resolves.

The 1:1 pipeline works as follows:
1. `dbRecoverStuckSendingMessages` (DB helper) — batch UPDATE of `sending` → `failed` for outgoing messages older than a threshold
2. `MessageRepositoryImpl.recoverStuckSendingMessages` (repo method) — computes cutoff, delegates to the DB helper
3. `recoverStuckSendingMessages` use case — calls the repo, emits FLOW events
4. Wired into `handleAppResumed` (Step 8a) and `PendingMessageRetrier._retryIfNeeded` (Step 1)
5. `retryFailedMessages` use case — picks up the now-`failed` messages and re-sends via `sendChatMessage`

Groups need an analogous pipeline, adapted for the `group_messages` table and `sendGroupMessage` use case.

Two repo-specific caveats must be reflected in the design:
- Today only `GroupConversationWired` creates a pre-publish outgoing row. `FeedWired` currently does not, so Section 1 moves pre-persisted outgoing-row ownership into `sendGroupMessage()` for all callers.
- DB recovery alone is not enough for visible correctness. Open group surfaces currently need a local outgoing-mutation signal if retry/recovery changes should update the mounted UI without reload.

### 1.1.1 Entry Gate

Section 1 requires the unified pre-persist send contract to land first:
- `sendGroupMessage()` must persist the outgoing row before any publish attempt.
- The same contract must apply to all production callers, including `GroupConversationWired` and `FeedWired`.
- Unauthorized and not-found paths must not persist an outgoing row.

### 1.2 Design

#### 1.2.1 New Repository Methods

**On `GroupMessageRepository` (abstract):**
- `Future<int> recoverStuckSendingMessages({required Duration olderThan})` — transitions stuck `'sending'` to `'failed'`
- `Future<List<GroupMessage>> getFailedOutgoingMessages()` — loads all `'failed'` outgoing group messages

**On `GroupMessageRepositoryImpl`:**
- Constructor gains two new injected DB helper functions
- `recoverStuckSendingMessages` computes `cutoff = DateTime.now().toUtc().subtract(olderThan)`, delegates to DB helper
- `getFailedOutgoingMessages` delegates to DB helper, maps rows to `GroupMessage.fromMap`

**On `InMemoryGroupMessageRepository`:**
- `recoverStuckSendingMessages` iterates `_messages`, flips `'sending'` → `'failed'` for outgoing older than cutoff
- `getFailedOutgoingMessages` returns `_messages.values.where(status == 'failed' && !isIncoming).toList()`

#### 1.2.2 New Use Case: `recoverStuckSendingGroupMessages`

**Location:** `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`

```dart
Future<int> recoverStuckSendingGroupMessages({
  required GroupMessageRepository groupMsgRepo,
  Duration threshold = kStuckSendingGroupThreshold,  // 30s
})
```

Calls `groupMsgRepo.recoverStuckSendingMessages(olderThan: threshold)`, emits `RECOVER_STUCK_SENDING_GROUP_START` / `_RECOVERED` / `_NONE` FLOW events. Returns count.

#### 1.2.3 New Use Case: `retryFailedGroupMessages`

**Location:** `lib/features/groups/application/retry_failed_group_messages_use_case.dart`

```dart
Future<int> retryFailedGroupMessages({
  required GroupMessageRepository groupMsgRepo,
  required GroupRepository groupRepo,
  required IdentityRepository identityRepo,
  required Bridge bridge,
  MediaAttachmentRepository? mediaAttachmentRepo,
})
```

Logic:
1. Load identity (bail with 0 if null)
2. Call `groupMsgRepo.getFailedOutgoingMessages()`
3. Default scope for this plan: retry only rows that are provably text-only from persisted retry metadata created by the unified send contract. Skip failed media/voice rows with a FLOW event until Sections 5 and 6 land the durable retry contract.
4. For each retryable failed message, call `sendGroupMessage()` using the final retry identity contract:
   - reuse the original `messageId` and `timestamp`
5. Re-run announcement authorization checks on every retry so resume/retry never bypasses admin-only write rules
6. Catch per-message errors, continue with next
7. Emit FLOW events per message: `_FOUND`, `_SUCCESS`, `_SKIPPED_UNSUPPORTED`, `_STILL_FAILED`, `_COMPLETE`
8. Return count of successfully retried messages

#### Retry Row Identity Contract

First sufficient version: retry in place.

`retryFailedGroupMessages` reuses the original `messageId` and `timestamp` when calling `sendGroupMessage()`. The failed row is updated or replaced in place. Do not create a second retry row in this phase.

#### Retry Eligibility

Auto-retry in Sections 1 and 2 applies only to rows that are provably text-only from persisted retry metadata created by the send contract.

If a failed row cannot be proven text-only from persisted metadata, leave it in `failed` and defer it to Sections 5 and 6.

#### 1.2.4 Wiring into `handleAppResumed`

Add new parameters on `handleAppResumed`:
- `Future<int> Function()? recoverStuckSendingGroupMessagesFn`
- `Future<int> Function()? retryFailedGroupMessagesFn`

Group recovery callbacks run as new Step 3d and Step 3e inside the existing group-recovery gate, after Step 3c and before Step 4. The existing 1:1 Step 8 recovery sweep remains unchanged.

Insert after Step 3c (group inbox drain) and BEFORE Step 4 (key exchange retry):
- Step 3d: `recoverStuckSendingGroupMessagesFn?.call()` — transitions group `'sending'` → `'failed'`
- Step 3e: `retryFailedGroupMessagesFn?.call()` — retries group `'failed'` messages

Each step is fault-isolated (try/catch, non-fatal).

**Critical constraint:** Group message retry on resume MUST happen AFTER `rejoinGroupTopics` (Step 3b) because `sendGroupMessage` calls `callGroupPublish` which requires an active GossipSub topic subscription.

**Additional constraint:** Keep Steps 3d/3e inside the existing group-recovery gate and AFTER Step 3c (group inbox drain). The first sufficient version of this plan should not run group retry before topic rejoin and inbox catch-up are complete.

#### 1.2.5 Reconnect Sweep Decision

Default for this plan: group stuck recovery and failed-message retry are **resume-only**. Do not wire them into `PendingMessageRetrier` in this implementation pass.

Rationale:
- reconnect-time group retry needs a topic-ready ordering contract that does not exist today
- resume already provides a deterministic place after `rejoinGroupTopics` and inbox drain
- deferring reconnect retry keeps the first implementation simpler and avoids racing topic rejoin

#### Visible State Scope

First sufficient version does not promise visible retry or recovery state changes in already-open group screens without reload.

Open-screen outgoing mutation streams are deferred. Remove any Section 1 acceptance proof or test that depends on mounted group UI updating from repository-driven outgoing status changes.

### 1.3 Affected Files

| File | Change |
|---|---|
| `lib/core/database/helpers/group_messages_db_helpers.dart` | Add `dbRecoverStuckSendingGroupMessages`, `dbLoadFailedOutgoingGroupMessages` |
| `lib/features/groups/domain/repositories/group_message_repository.dart` | Add `recoverStuckSendingMessages`, `getFailedOutgoingMessages` to abstract |
| `lib/features/groups/domain/repositories/group_message_repository_impl.dart` | Implement new methods, add two new constructor params for injected DB helpers |
| `test/shared/fakes/in_memory_group_message_repository.dart` | Implement `recoverStuckSendingMessages`, `getFailedOutgoingMessages` |
| `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart` | **New file** |
| `lib/features/groups/application/retry_failed_group_messages_use_case.dart` | **New file** |
| `lib/features/groups/application/send_group_message_use_case.dart` | Move pre-persisted outgoing-row ownership here so all production callers become retry-discoverable |
| `lib/core/lifecycle/handle_app_resumed.dart` | Add params + Steps 3d/3e |
| `lib/features/feed/presentation/screens/feed_wired.dart` | Move feed-inline group send onto the same pre-persisted send contract |
| `test/features/groups/application/send_group_message_use_case_test.dart` | Add pre-persist and retry-eligibility coverage for the unified send contract |
| `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` | Add failed/outgoing load and stuck-send recovery coverage |
| `test/features/feed/presentation/screens/feed_wired_test.dart` | Cover feed-inline sends becoming retry-discoverable under the shared contract |
| `lib/main.dart` | Wire new callbacks through DI chain |

### 1.4 TDD Tests (13 tests)

**File:** `test/core/database/helpers/group_messages_db_helpers_stuck_sending_test.dart`

1. **DB helper recovers stuck sending older than threshold** — Insert 3 messages: one 5min old sending, one 10s old sending (recent), one sent. Call with 30s cutoff. Assert returns 1, only old message transitioned.
2. **DB helper does not touch incoming messages** — Insert incoming `'sending'` 5min old. Assert returns 0.
3. **DB helper returns 0 when no stuck messages** — Insert one `'sent'`. Assert returns 0.
4. **DB helper loads failed outgoing** — Insert failed+outgoing, failed+incoming, sent+outgoing. Assert returns only the first.

**File:** `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`

5. **Use case returns count from repo** — Seed 2 outgoing sending 5min old. Assert returns 2, both now `'failed'`.
6. **Returns 0 when nothing stuck** — Empty repo. Assert returns 0.
7. **Respects threshold** — Seed 1 sending 10s old. Call with 30s threshold. Assert returns 0.

**File:** `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`

8. **Retries each failed message in place via sendGroupMessage** — Seed 2 failed. FakeBridge returns ok. Assert returns 2, original rows transition to `'sent'`, bridge received 2 `group:publish` calls, and no second retry row is created.
9. **Returns 0 when identity is null** — Assert returns 0, message unchanged.
10. **Catches per-message errors and continues** — FakeBridge throws on first, succeeds on second. Assert returns 1.
11. **Feed-inline group send becomes retry-discoverable after pre-persist patch** — Simulate feed send, crash before publish resolves, assert resume sweep finds a retryable row.
12. **Rows that are not provably text-only are skipped with telemetry when media retry is not yet in scope** — Seed failed row whose persisted retry metadata includes media. Assert skip event and no bridge publish.

**File:** `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`

13. **handleAppResumed calls group recovery after rejoin + drain** — Tracking closure. Assert order `rejoinGroupTopics -> drainGroupOfflineInbox -> recoverStuck -> retryFailed`.

### 1.5 Acceptance Proof

All 13 tests pass. FLOW logs on resume show:
- `RECOVER_STUCK_SENDING_GROUP_START` → `RECOVER_STUCK_SENDING_GROUP_RECOVERED`
- `RETRY_FAILED_GROUP_MESSAGES_START` → `RETRY_FAILED_GROUP_MESSAGES_FOUND` → `RETRY_FAILED_GROUP_MESSAGE_SUCCESS` → `RETRY_FAILED_GROUP_MESSAGES_COMPLETE`

Status transition: `'sending'` → `'failed'` → `'sent'` (or stays `'failed'` if offline).

---

## Section 2: Lifecycle Pause Handler for Groups

### 2.1 Problem Statement

The existing `handleAppPaused()` transitions 1:1 conversation messages from `status='sending'` to `status='failed'` so they become eligible for retry on resume. However, it has zero awareness of group messages. The `group_messages` table has the same `status` column with the same lifecycle, but no code exists to sweep group messages on pause.

**Consequence:** When a user sends a group message, locks the device mid-publish, and the OS suspends the process, the group message row remains in `status='sending'` indefinitely. On resume, `handleAppResumed()` rejoins group topics and drains the group offline inbox, but never looks for orphaned outgoing group messages.

One more caveat from the current repo: `handleAppPaused()` has 1:1-centric early-return behavior today. The section must make group-only pending sends safe even when there are zero 1:1 sending rows.

### 2.2 Design

#### Resume Handler Dependency

Section 2 owns pause-time transition of outgoing group rows from `sending` to `failed`.

Section 1 owns the new group resume callbacks and their use cases. Once those callbacks exist, `handleAppResumed()` must invoke them after Step 3c, inside the existing group-recovery gate, before Step 4. The existing 1:1 Step 8 recovery sweep remains unchanged.

#### Pause Handler Changes

**New signature:**
```dart
Future<AppPausedResult> handleAppPaused({
  required MessageRepository messageRepo,
  GroupMessageRepository? groupMsgRepo,  // NEW — optional for backward compat
})
```

**`AppPausedResult` extension:**
```dart
class AppPausedResult {
  final int transitionedCount;          // existing — 1:1 messages
  final int groupTransitionedCount;     // NEW — group messages
}
```

**New DB helper:** `dbTransitionGroupSendingToFailed(Database db)` — bulk UPDATE:
```sql
UPDATE group_messages SET status = 'failed'
WHERE status = 'sending' AND is_incoming = 0
```

This is a bulk operation (not per-row) because group messages do not need the conditional guard — there is no concurrent delivery path that could race `'sending'` → `'delivered'` for outgoing group messages.

**Pause handler flow:**
1. (existing) Transition 1:1 `'sending'` → `'failed'`
2. (NEW) If `groupMsgRepo != null`, call `groupMsgRepo.transitionSendingToFailed()`
3. Return `AppPausedResult` with both counts

Errors in step 2 are caught and logged, never propagated.

**Important:** Do not let an existing "no 1:1 sending messages" fast-path skip step 2. Group-only pending sends must still transition.

Early recovery default for this plan is text-only. Failed media/voice rows may be marked failed on pause, but retry support for those rows is added only after Sections 5 and 6 land.

### 2.3 Affected Files

| File | Change |
|---|---|
| `lib/core/lifecycle/handle_app_paused.dart` | Add optional `groupMsgRepo` param; add group sweep; extend `AppPausedResult` |
| `lib/core/lifecycle/handle_app_resumed.dart` | Add `recoverStuckSendingGroupMessagesFn`, `retryFailedGroupMessagesFn` params; Steps 3d/3e |
| `lib/core/database/helpers/group_messages_db_helpers.dart` | Add `dbTransitionGroupSendingToFailed` |
| `lib/features/groups/domain/repositories/group_message_repository.dart` | Add `transitionSendingToFailed()` |
| `lib/features/groups/domain/repositories/group_message_repository_impl.dart` | Implement |
| `test/shared/fakes/in_memory_group_message_repository.dart` | Extend fake repo with group pause-time status transitions |
| `test/shared/helpers/lifecycle_helpers.dart` | Reuse the shared lifecycle helpers for group pause/resume coverage |
| `lib/main.dart` | Wire `groupMsgRepo` to `handleAppPaused`; wire callbacks to `handleAppResumed` |

### 2.4 TDD Tests (7 tests)

**File:** `test/core/database/helpers/group_messages_db_helpers_sending_test.dart`

1. **dbTransitionGroupSendingToFailed bulk transitions** — 3 sending outgoing + 2 sent + 1 incoming sending. Assert returns 3, correct rows flipped.

**File:** `test/core/lifecycle/handle_app_paused_group_test.dart`

2. **handleAppPaused transitions group alongside 1:1** — Seed both repos. Assert both counts correct.
3. **Group error isolation** — Group repo throws. Assert 1:1 still transitions, `groupTransitionedCount == 0`.
4. **groupMsgRepo null** — Assert `groupTransitionedCount == 0`, no errors.
5. **Group-only pending sends still transition when 1:1 count is zero** — Seed only group sending rows. Assert group transition still occurs.

**File:** `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`

6. **Group recovery runs after rejoinGroupTopics and after drainGroupOfflineInbox** — Track call order. Assert `rejoinGroupTopics` before `drainGroupOfflineInbox` before `recoverStuck` before `retryFailed`.
7. **Feature gate controls whether group recovery runs** — Disable group recovery. Assert Steps 3d/3e skipped.

### 2.5 Acceptance Proof

Manual verification on physical device:
1. Send group message, immediately lock device
2. Wait 30s, unlock
3. Verify message leaves `'sending'` and reaches the supported final state for the documented scope (`'sent'`, `'pending'`, or `'failed'`)
4. Check FLOW logs: `APP_LIFECYCLE_PAUSE_GROUP_TRANSITION` with count, then `RECOVER_STUCK_SENDING_GROUP_RECOVERED`, then `RETRY_FAILED_GROUP_MESSAGE_SUCCESS`

---

## Section 3: iOS Background Task Protection for Group Sends

### 3.1 Problem Statement

The 1:1 conversation send pipeline protects against iOS suspension by wrapping the entire send path in a `callBgBegin()`/`callBgEnd()` pair, requesting up to ~30 seconds of background execution time from `UIApplication.beginBackgroundTask`.

The group conversation send pipeline (`GroupConversationWired._onSend`, lines 289-464) performs an equivalent multi-step async sequence — media upload, GossipSub publish, inbox store — but makes **zero** calls to `callBgBegin` or `callBgEnd`. Neither function is imported or called.

The same gap exists on the voice send path (`_onRecordStop`). This plan includes voice in Section 3.

The 1:1 code has two distinct send methods that both acquire background tasks:
- `_onSend` (text + media) — line 676: acquires before upload, releases in `finally` at line 850
- `_onSendVoice` (voice messages) — line 1320: acquires before local transfer / relay upload, releases in `finally` at line 1476

Both follow the same structural pattern: acquire immediately after argument validation, wrap the entire I/O block in `try`, release in `finally`.

`FeedWired._onGroupInlineSend` is another production group send surface, but to keep the first implementation pass simple, Section 3 explicitly excludes feed-inline send from background-task work. Feed-inline reliability still benefits from the unified pre-persist / retry contract in Section 1 and the send contract in Sections 4 and 8.

### 3.2 Design

Insert `callBgBegin()` AFTER optimistic message DB persist (line 372) and BEFORE the I/O `try` block (line 374). `callBgEnd()` goes in a new `finally` clause.

**Structural change:**

```
_onSend:
  early returns (empty text, no peerId)       // no I/O — no bg task needed
  persist optimistic message to DB
  final bgTaskId = await callBgBegin(widget.bridge);   // NEW
  try {                                                  // NEW outer try
    try {
      upload attachments
        early return on upload failure                   // EXIT PATH A
      sendGroupMessage (publish + inbox store)
      if (!mounted) return                               // EXIT PATH B
      update UI or restore snapshot
    } catch {                                            // EXIT PATH C
      restore snapshot
    }
  } finally {                                            // NEW
    if (bgTaskId != null) {
      await callBgEnd(widget.bridge, bgTaskId);
    }
  }
```

**Exit path coverage:**

| Exit path | Current behavior | With fix |
|---|---|---|
| **A**: Upload failure early return | Returns without cleanup | `finally` calls `callBgEnd` |
| **B**: `!mounted` return | Returns without cleanup | `finally` calls `callBgEnd` |
| **C**: Exception caught | Restores UI, no bg cleanup | `finally` calls `callBgEnd` |
| **D**: Normal success | Falls through, no bg cleanup | `finally` calls `callBgEnd` |

**Bridge nullability:** In `GroupConversationWired`, `bridge` is non-nullable (`final Bridge bridge`), simplifying the call site — no null check needed. The `bgTaskId` null check is still required because `callBgBegin` returns `null` when the OS refuses the task.

**Coverage constraint:** `callBgEnd()` must happen after the full protected pipeline, including the inbox-store future. Do not treat "publish returned" as the end of protected work.

Use an order-recording bridge patterned after the existing 1:1 background-task tests, plus injected `uploadMediaFn` closures, so tests can assert cross-layer ordering:
`bg:begin -> upload -> group:publish -> group:inboxStore -> bg:end`.

#### Voice Send Path

In `_onRecordStop`, acquire `bgTaskId` immediately after optimistic row persistence and before `groupRepo.getMembers(...)`.

Wrap `getMembers`, upload, publish, inbox-store, and post-send UI update in `try/finally`. Release with `callBgEnd()` in `finally`.

Do not add voice retry or durable-file behavior in this section. Voice durability remains owned by Section 6.

This section protects only `GroupConversationWired` text and voice send paths. `FeedWired._onGroupInlineSend` remains an intentionally deferred unprotected production path in this phase.

### 3.3 Affected Files

| File | Change |
|---|---|
| `lib/features/groups/presentation/screens/group_conversation_wired.dart` | Wrap `_onSend` and voice send I/O blocks in `callBgBegin`/`callBgEnd` |
| `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` | **New** — background task tests |

No changes needed to `bridge.dart`, `GoBridge.swift`, or `GoBridge.kt` — the background task infrastructure already exists.

### 3.4 TDD Tests (8 tests)

All tests use a `FakeBridge` that records `bg:begin` and `bg:end` calls.

1. **Background task acquired before network I/O on successful group send** — Assert `bg:begin` before upload / `group:publish` in call log, `bg:end` after publish + inbox-store complete.
2. **Released on media upload failure (early return path A)** — Stub upload to return null. Assert `bg:begin` + `bg:end` received, no `group:publish` or `group:inboxStore` bridge call occurs.
3. **Released on exception (catch path C)** — Stub `uploadMediaFn` or the publish bridge to throw. Assert `bg:begin` + `bg:end` received, `GROUP_CONV_FL_SEND_ERROR` emitted.
4. **Send proceeds normally when OS refuses background task** — FakeBridge returns empty for `bg:begin`. Assert send still succeeds, `callBgEnd` not called (no task ID).
5. **Released when widget unmounts mid-send (exit path B)** — Dispose widget before UI update. Assert `bg:end` called, no `setState` after unmount.
6. **Covers full media + publish + inbox store sequence** — Add artificial delays. Assert `bg:begin` timestamp before upload, `bg:end` after inbox store completion.
7. **Voice send path is background-task protected** — Record voice, stop recording, assert `bg:begin` before upload/publish and `bg:end` in `finally`.
8. **Order-recording bridge proves no early cleanup** — Assert `bg:begin -> upload -> publish -> inbox store -> bg:end`.

### 3.5 Acceptance Proof

Manual verification:
1. Open group conversation on physical iOS device
2. Send message with photo attachment
3. Immediately press power button to lock
4. Unlock after ~10 seconds
5. Verify the message is no longer stuck in `status='sending'` and reaches the supported success or failure state for the active send contract
6. Verify via bridge call-order logging or a dedicated native log that `bg:end` happened after the protected send pipeline completed

---

## Section 4: Inbox Store as Required Fallback

### 4.0 Dependency

This section depends on the unified pre-persist send contract and owns the inbox-result contract. After this section lands, `sendGroupMessage()` must own one in-flight inbox-store future and must be able to observe whether it succeeded. Do not use fire-and-forget inbox semantics after this section.

### 4.1 Problem Statement

`_safeInboxStore` (lines 235-279 of `send_group_message_use_case.dart`) wraps `callGroupInboxStore` in a bare try/catch that logs a flow event and returns void. The caller has no way to know whether the store succeeded. If the relay is unreachable, the error is swallowed. The message is still saved locally with `status: 'sent'`, giving the sender a false positive.

**Combined failure mode:** When the sender publishes to zero peers AND inbox store silently fails, the message is persisted locally as `'sent'` while no other group member will ever receive it. No retry mechanism, no UI indication, no recovery path.

**Contrast with 1:1 chat:** `sendChatMessage` treats inbox store as a meaningful reliability signal — it checks the boolean return from `p2pService.storeInInbox`, records the transport as `'inbox'`, and when inbox store fails on an unacknowledged send, it downgrades status to `'sent'` (pending retry) rather than claiming `'delivered'`.

### 4.2 Design

#### Replace `_safeInboxStore` with `_tryInboxStore`

Returns `Future<bool>`:
- `true` — `callGroupInboxStore` completed without error and Go returned `ok: true`
- `false` — any exception or `ok != true`

The wrapper still catches exceptions (never crashes the send path), but now the caller knows the outcome.

This wrapper must not destroy the only in-flight failure signal if Section 8 later escalates the same inbox-store attempt when `topicPeers == 0`.

#### Updated Send Flow

Start exactly one inbox-store future once, before awaiting publish:

1. Kick off `publishFuture`
2. Kick off one `inboxFuture`
3. Capture inbox completion/error without swallowing it permanently
4. Await publish result and persist the observed inbox outcome from that same `inboxFuture`
5. **publish OK + inbox OK** → save `inboxStored = true`, clear `inbox_retry_payload`, return the current success contract
6. **publish OK + inbox fails** → save `inboxStored = false`, retain `inbox_retry_payload`, return the current success contract with inbox retry still pending
7. **publish fails + inbox fails** → return `SendGroupMessageResult.error`, preserve retry inputs
8. **publish fails + inbox succeeds** → still return error; the publish path is authoritative for send completion, but keep the inbox result explicit on the row

This section does not introduce `successNoPeers` or `pending`. Zero-peer publish semantics remain owned by Section 8.

#### New Use Case: `retryFailedGroupInboxStores`

**File:** `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`

```dart
Future<int> retryFailedGroupInboxStores({
  required Bridge bridge,
  required GroupMessageRepository msgRepo,
})
```

1. Query only outgoing rows where:
   - `is_incoming = 0`
   - `status IN ('sent', 'pending')`
   - `inbox_retry_payload IS NOT NULL`
   - `inbox_stored = 0`
2. For each, reconstruct inbox payload from `inbox_retry_payload` and call `callGroupInboxStore`
3. On success: update `inbox_stored = 1`
4. On failure: leave `inbox_stored = 0`, log, continue
5. Batch limit: 20 per resume cycle

Legacy rows without `inbox_retry_payload` are not retry-eligible.

`GroupMessage` must carry both `inboxStored` and `inboxRetryPayload`.

Repository and DB helper APIs must be able to:
- persist `inbox_retry_payload`
- clear `inbox_retry_payload`
- update `inbox_stored`
- query retry-eligible rows using `inbox_retry_payload IS NOT NULL`

#### Wire into Resume Handler

New step 8e after existing step 8d:
```dart
if (retryFailedGroupInboxStoresFn != null) {
  try { await retryFailedGroupInboxStoresFn(); }
  catch (e) { /* non-fatal */ }
}
```

Default for this plan: inbox-store retry is **resume-only**. Do not wire it into `PendingMessageRetrier` in this implementation pass.

### 4.3 Affected Files

| File | Change |
|---|---|
| `lib/features/groups/domain/models/group_message.dart` | Carry both `inboxStored` and `inboxRetryPayload` |
| `lib/core/database/migrations/041_group_message_reliability_columns.dart` | `inbox_stored` and `inbox_retry_payload` columns |
| `lib/core/database/helpers/group_messages_db_helpers.dart` | Add retry-eligible query, `dbUpdateGroupMessageInboxStored`, and `dbUpdateGroupMessageInboxRetryPayload` |
| `lib/features/groups/domain/repositories/group_message_repository.dart` | Add inbox retry query and inbox result update methods |
| `lib/features/groups/domain/repositories/group_message_repository_impl.dart` | Persist, clear, and query `inbox_retry_payload`; update `inbox_stored` |
| `lib/features/groups/application/send_group_message_use_case.dart` | Replace `_safeInboxStore` with `_tryInboxStore`, set `inboxStored`, add dual-failure path |
| `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart` | **New** |
| `lib/core/lifecycle/handle_app_resumed.dart` | Add Step 8e |
| `test/shared/fakes/in_memory_group_message_repository.dart` | Implement inbox retry payload behavior in test repo |
| `lib/main.dart` | Wire retry into resume handler DI |

### 4.4 TDD Tests (11 tests)

1. **`_tryInboxStore` returns true on success, false on failure** — Bridge success → true; bridge throws → false; bridge returns ok:false → false
2. **Saves `inboxStored: true` when inbox store succeeds** — Both publish + inbox OK. Assert saved message has `inboxStored == true`.
3. **Saves `inboxStored: false` and emits warning when inbox fails but publish succeeds** — Publish OK, inbox throws. Assert `inboxStored == false`, warning event emitted.
4. **Uses the same in-flight inbox future and never duplicates `group:inboxStore`** — Assert exactly one inbox-store call occurs on the success path.
5. **Retry skips legacy rows with null `inbox_retry_payload`** — Seed pre-migration-style row. Assert skip and no guessed inbox call.
6. **Retry query selects only retry-eligible outgoing rows** — Seed incoming rows, `status='failed'`, and rows without payload. Assert only `sent`/`pending` outgoing rows with payload are loaded.
7. **Retry retries messages with `inboxStored == false` using `inbox_retry_payload`** — Seed 3 messages (one true, one false, one incoming null). Assert only the false one retried, updated to true.
8. **Retry handles per-message failure** — 2 false messages, bridge fails on first, succeeds on second. Assert returns 1.
9. **Retry respects batch limit** — 25 false messages, default limit 20. Assert 20 retried, 5 remain.
10. **Resume handler Step 8e invokes retry** — Tracking closure. Assert called once.
11. **DB migration adds inbox_stored + inbox_retry_payload idempotently** — Run twice, no error; existing rows remain backward-compatible.

### 4.5 Acceptance Proof

- `_safeInboxStore` no longer exists — replaced by `_tryInboxStore`
- No silent swallowing — every inbox store failure emits a distinguishable flow event, and `sendGroupMessage()` now owns an observable inbox result instead of fire-and-forget behavior
- Dual-failure proof: test confirms both publish + inbox fail → `error`, no message saved as `'sent'`
- Backward compat: legacy rows are skipped because they have no `inbox_retry_payload`, not because `inbox_stored` is `NULL`

---

## Section 5: Parallel Media Upload + Group Media Retry

### 5.0 Dependency

Section 5 depends on Section 1's unified pre-persist message contract and on attachment-scoped retry state in `media_attachments`.

Do not add `upload_retry_count` to `group_messages`. Add attachment-scoped `upload_retry_count` to `media_attachments`.

### 5.1 Problem Statement

**Sequential uploads (media):** In `group_conversation_wired.dart` (lines 382-403), media uploads execute in a sequential `for` loop. Each upload must complete before the next begins. With 3 images at 2-4s each, user sees 6-12s upload spinner. The uploads are independent (separate blob IDs, separate relay calls), so they can run concurrently.

**Sequential DB reads (text):** `sendGroupMessage` use case (lines 91-132) performs 3 independent `await` DB reads (`getGroup`, `getLatestKey`, `_loadGroupPushRecipients`) before the concurrent publish+inbox. This adds ~2 unnecessary DB roundtrips to every text send.

**No group media retry:** The existing `retryIncompleteUploads()` only handles 1:1 messages (queries the `messages` table). Group attachments are created with `downloadStatus: 'done'` (line 325) and never persisted with `'upload_pending'` before upload — invisible to any retry scan.

**Missing durable pending-path contract:** The current draft does not specify where pre-upload files live, how retry resolves them after restart, or when pending storage is cleaned up. Without that, "retry incomplete group uploads" is not implementable for real media sends.

**Note:** 1:1 uploads are ALSO sequential (same `for` + `await` pattern in `conversation_wired.dart`), but that is out of scope for this plan.

### 5.2 Design

#### 5.A — Parallel Media Upload

Replace the sequential `for` loop with `Future.wait()`:

```dart
final uploadFutures = mediaToUpload.map((pending) async {
  final mime = _mimeFromPath(pending.file.path);
  return widget.uploadMediaFn(
    bridge: widget.bridge,
    localFilePath: pending.file.path,
    mime: mime,
    recipientPeerId: widget.group.id,
    mediaFileManager: widget.mediaFileManager,
    width: pending.width,
    height: pending.height,
    durationMs: pending.durationMs,
    allowedPeers: allowedPeers,
  );
});
final results = await Future.wait(uploadFutures);
```

**Failure strategy: fail-all.** If any single upload returns `null`, abort the entire send and restore the composer. This matches existing sequential behavior and avoids partial-send complexity.

#### 5.A.1 — Parallel DB Reads

Keep `getGroup()` as the sequential not-found / authorization gate. After `group` is confirmed valid, parallelize only:
- `getLatestKey()`
- `_loadGroupPushRecipients()`

The use case currently performs 3 sequential DB reads:

```dart
final group = await groupRepo.getGroup(groupId);           // Sequential DB read 1
final latestKey = await groupRepo.getLatestKey(groupId);    // Sequential DB read 2
final recipientPeerIds = await _loadGroupPushRecipients(...); // Sequential DB read 3
```

The first read remains sequential. The latter two can run in parallel:

```dart
final group = await groupRepo.getGroup(groupId);
final (latestKey, recipientPeerIds) = await (
  groupRepo.getLatestKey(groupId),
  _loadGroupPushRecipients(groupRepo: groupRepo, groupId: groupId, senderPeerId: senderPeerId),
).wait;
```

SQLCipher serializes writes but allows concurrent reads, so this is safe.

#### 5.B — Pre-Upload Persistence

Before calling `uploadMediaFn`, copy each local input into durable `pending_uploads/...` storage, persist each attachment with `downloadStatus: 'upload_pending'`, a relative `pending_uploads/...` path, and a pre-generated `blobId`. This makes group attachments visible to the retry use case on resume.

The durable `pending_uploads/...` copy becomes the canonical upload source immediately.

Initial send and retry both:
- copy to `pending_uploads/...`
- persist that relative path
- resolve that stored path to an absolute path
- upload from the resolved durable path

The pre-generated `blobId` establishes the **stable-ID contract**: if the upload is interrupted and retried, the same `blobId` prevents duplicate blobs on the relay.

The temp path used by the picker / recorder must never be the persisted retry path.

#### 5.C — New Use Case: `retryIncompleteGroupUploads()`

**File:** `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`

Mirrors `retryIncompleteUploads()` but resolves the parent message via `GroupMessageRepository.getMessage()` and calls `sendGroupMessage()` instead of `sendChatMessage()`.

Key differences from 1:1:
- Needs `senderPublicKey`, `senderPrivateKey`, `senderUsername` from identity
- Calls `groupRepo.getMembers(groupId)` to derive `allowedPeers` for upload
- Uses same `kMaxUploadRetries` constant and transient vs. terminal failure classification
- Distinguishes group vs 1:1 by checking `groupMsgRepo.getMessage(messageId)`
- Groups attachments by `messageId`, preserves already-`done` attachments, re-uploads only `upload_pending`, and calls `sendGroupMessage()` once per message with the full attachment set
- Resolves the stored relative pending path back to an absolute path at retry time and passes `mediaFileManager:` during re-upload
- Deletes the pending-upload directory only after the final send succeeds

Reliable group media retry requires `mediaAttachmentRepo` and `mediaFileManager`. First sufficient version must either require both dependencies for group media send paths or explicitly reduce scope when either dependency is missing.

#### 5.D — Wire into Resume Handler

Group upload retry runs inside the existing group-recovery gate after:
`rejoinGroupTopics -> drainGroupOfflineInbox -> recoverStuckSendingGroupMessages`
and before:
`retryFailedGroupMessages`

Do not place group upload retry in the generic 1:1 Step 8 block.

Default for this plan: incomplete group upload retry is **resume-only**. Do not wire it into `PendingMessageRetrier` in this implementation pass.

### 5.3 Affected Files

| File | Change |
|---|---|
| `lib/features/groups/presentation/screens/group_conversation_wired.dart` | Replace sequential `for` with `Future.wait()`; persist `upload_pending` before upload; pass `blobId:`; upload from the durable pending copy |
| `lib/features/groups/application/send_group_message_use_case.dart` | Keep `getGroup()` sequential, then parallelize `getLatestKey()` and `_loadGroupPushRecipients()` |
| `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` | **New** |
| `lib/features/media/domain/repositories/media_attachment_repository.dart` | Add attachment-scoped retry count behavior where missing |
| `lib/core/lifecycle/handle_app_resumed.dart` | Add group upload retry inside the group-recovery gate |
| `lib/main.dart` | Wire `retryIncompleteGroupUploads` |

### 5.4 TDD Tests (11 tests)

1. **3 images complete in parallel wall-clock time** — Fake upload with 50ms delay. Assert all start within 10ms of each other, total ~50ms not ~150ms.
2. **One failure aborts all, composer restored** — 3 attachments, third returns null. Assert `sendGroupMessage` never called, composer restored.
3. **`getGroup()` stays sequential while follow-up reads execute in parallel** — Fake repo with 50ms delay per read. Assert `getGroup()` completes first and the combined `getLatestKey()` + recipient lookup cost is ~50ms, not ~100ms.
4. **`upload_pending` rows exist before `uploadMediaFn` called** — Inside upload callback, query repo. Assert attachments already persisted with `'upload_pending'`.
5. **Persisted pending path is durable and relative** — Assert DB stores `pending_uploads/...`, not the original temp path.
6. **Group retry re-uploads only `upload_pending` attachments and re-sends once** — Seed stuck GroupMessage + mixed `done` / `upload_pending` attachments. Assert only pending uploads rerun and `sendGroupMessage` called once with the full set.
7. **Group retry skips 1:1 attachments** — Seed both group and 1:1 pending. Assert only group processed.
8. **Transient failure increments attachment-scoped retry count, terminal after `kMaxUploadRetries`** — Seed attachment retry count at 2, upload returns null. Assert transitions to `'upload_failed'`.
9. **handleAppResumed calls group upload retry in the group-recovery order** — Assert `rejoinGroupTopics -> drainGroupOfflineInbox -> recoverStuck -> retryIncompleteGroupUploads -> retryFailed`.
10. **Stable-ID contract: retry uses same blobId** — Assert `uploadMediaFn` receives `blobId: 'blob-abc-123'`.
11. **Pending directory cleanup happens only after final send success** — Assert retry does not delete the pending dir on upload-only success or before the send completes.

---

## Section 6: Voice Message Reliability for Groups

### 6.1 Problem Statement

**Dual-ID orphan:** When `_onRecordStop` fires, it generates an optimistic attachment ID at line 1020 (`_uuid.v4()`). The subsequent `uploadMediaFn` call at line 1071 does NOT pass a `blobId:` parameter. Inside `uploadMedia` (line 48), a second independent UUID is generated. The optimistic row references one ID, the relay blob carries another. Result: orphan row.

**Temp file volatility:** The recorder writes to the platform temp directory (e.g., iOS `tmp/`). If the app is killed or the upload is slow, the OS may purge the temp file before `uploadMedia` reads it. The `uploadMedia` function copies to `MediaFileManager` storage only AFTER successful upload (line 94-106), meaning the source must survive the entire round-trip.

**No retry path:** When `uploadMediaFn` returns null, the message is marked `'failed'`, but the temp file is likely gone by retry time. No mechanism exists to retry voice uploads.

**No pre-upload persistence:** Unlike 1:1, the group voice path does not persist attachment rows before upload. Crash during upload = attachment metadata lost entirely.

**No background-task protection on voice path:** `_onRecordStop` is also outside the Section 3 protection boundary until that section is patched.

### 6.2 Design

Reliable group voice sending requires non-null `mediaAttachmentRepo` and `mediaFileManager`.

First sufficient version:
- if either dependency is unavailable, do not expose the group voice send path
- do not fall back to temp-file-only reliability

Storage and retry contract:
1. Generate `messageId` and stable `attachmentId`.
2. Call `copyToDurableStorage(...)` and keep the returned relative `pending_uploads/...` path for DB.
3. Resolve that relative path to an absolute path for the upload call.
4. Persist an `upload_pending` attachment row with the relative durable path.
5. Keep an in-memory optimistic attachment with the resolved absolute path for immediate UI.
6. Call `uploadMediaFn(blobId: attachmentId, localFilePath: resolvedPendingPath, ...)`.
7. Let `uploadMedia()` create the final `media/...` copy on success.
8. Delete `pending_uploads/<messageId>/` only after the final `sendGroupMessage()` success path.

No change is required in `upload_media_use_case.dart` for stable IDs. `uploadMedia()` already accepts `blobId`.

Preserve the existing quote-restoration behavior on voice upload and publish failure. Section 6 must not regress that behavior.

### 6.3 Affected Files

| File | Change |
|---|---|
| `lib/features/groups/presentation/screens/group_conversation_wired.dart` | Refactor `_onRecordStop`: durable copy, stable IDs, persist attachment, pass `blobId:` |
| `test/features/groups/presentation/group_conversation_wired_test.dart` | Cover voice-path durability and quote-restoration behavior |
| `test/shared/fakes/fake_media_file_manager.dart` | Support durable pending-path assertions |
| `test/shared/fakes/fake_audio_recorder_service.dart` | Support voice-path failure and recovery scenarios |

### 6.4 TDD Tests (6 tests)

1. **Durable copy created before upload begins** — Assert `copyToDurableStorage` called before `uploadMediaFn`, durable path used not temp path.
2. **Stable attachment ID threads through** — Assert optimistic ID == upload blobId == published mediaAttachment ID. Expect 2 `saveAttachment` calls total: one for `upload_pending`, one overwrite to `done` on success.
3. **Optimistic attachment persisted before upload** — Block upload with Completer. Assert attachment in DB with `'upload_pending'` before unblocking.
4. **Voice send path is unavailable when durability dependencies are missing** — Assert the group voice affordance is not exposed if `mediaAttachmentRepo` or `mediaFileManager` is null.
5. **Upload failure leaves retryable state and preserves quote restoration** — Upload returns null. Assert durable file exists, status `'failed'`, attachment row remains `upload_pending` with the same `blobId`, duration, and waveform, and the quoted draft is restored.
6. **Successful send cleans up `pending_uploads` and temp deletion after the durable copy does not crash** — Assert `deletePendingUploadDir` called, final path in `media/`, and upload proceeds from the durable path even if the temp file disappears.

---

## Section 7: Key Rotation Safety Window

### 7.1 Problem Statement

When admin rotates the group encryption key:

1. Admin calls `rotateAndDistributeGroupKey` — generates new key (epoch N+1), saves locally, immediately updates Go validator via `callGroupUpdateKey`.
2. Go validator uses single stored epoch — `groupTopicValidator` verifies signatures by rebuilding `BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, ciphertext)`. The moment Go updates to epoch N+1, any message signed with epoch N fails verification → `ValidationReject`.
3. Distribution is asynchronous — new key distributed one-by-one via 1:1 P2P. Takes seconds to minutes per member.
4. Messages silently rejected during the gap — members still on epoch N have their messages rejected by validators already on epoch N+1. No error feedback, no retry.
5. The `key_rotated` system message is itself at risk — published with new epoch, rejected by members who haven't updated.

**Impact:** In a group of 5 where rotation takes 10s, roughly 4 messages from non-admin members will be silently dropped per rotation event.

One more implementation constraint from the current repo: `callGroupRotateKey` already mutates Go state immediately. The current "distribute first, update own validator last" wording is not implementable until the bridge contract changes.

### 7.2 Design

#### Dual-Epoch Grace Period (Go)

Extend `GroupKeyInfo` with previous key tracking:

```go
type GroupKeyInfo struct {
    Key           string    // current key
    KeyEpoch      int       // current epoch
    PrevKey       string    // previous key (empty if no grace active)
    PrevKeyEpoch  int
    GraceDeadline time.Time // when to stop accepting PrevKeyEpoch
}
```

**Validator change:** After current-epoch check fails, if `PrevKey != ""` AND `time.Now().Before(GraceDeadline)`, retry with `PrevKeyEpoch`. Accept if valid.

This grace-period fallback must apply to decryption in `handleGroupSubscription` as well as signature validation. Accepting an old-epoch envelope in the validator but then failing to decrypt it still loses the message.

**Constant:** `KeyRotationGracePeriod = 30 * time.Second`

#### Bridge Contract

Add `group:generateNextKey`.

Request:
```json
{ "groupId": "..." }
```

Success response:
```json
{ "ok": true, "groupKey": "...", "keyEpoch": 2 }
```

New Dart callers use `group:generateNextKey` plus `group:updateKey`.
`group:rotateKey` is no longer used by the new Dart rotation flow after this section lands. If retained, it is legacy-only and must be called out explicitly as such.

#### Reorder Rotation (Dart)

Change `rotateAndDistributeGroupKey`:
1. Call a non-mutating bridge/API step to generate the next key and epoch (`{groupKey, keyEpoch}`) without updating Go validator state yet
2. **Distribute to all members FIRST** (1:1 P2P), using concurrent per-member sends with per-recipient timeout
3. **Update admin's own Go validator LAST** (after distribution completes or a global 15s timeout) via `group:updateKey`
4. Broadcast `key_rotated` system message (with new epoch, after admin's validator updated)

This narrows the window: admin keeps sending/accepting on old epoch while distribution is in progress.

Default key-activation model for this plan: do **not** introduce a persisted active-vs-pending key model. Keep the generated next key in local rotation scope only, and do not save it to `groupRepo` until `group:updateKey` succeeds for the admin. `sendGroupMessage()` continues using the currently persisted key/epoch until promotion.

#### Receiver-Side Promotion Rule

`GroupKeyUpdateListener` calls `group:updateKey` first.

Only after bridge success does it persist or promote the new `GroupKeyInfo` locally.

On bridge failure it emits telemetry and keeps the old key active.

#### Current Removal Flow Compatibility

The existing `member_removed` broadcast remains before key promotion.

Patch `group_info_wired.dart` and its tests to preserve the current removal flow shape while moving the new generate/distribute/promote semantics inside `rotateAndDistributeGroupKey()`.

#### Epoch Mismatch Event (Go)

Emit `group:epoch_rejected` when validator rejects due to epoch mismatch (distinguishable from other signature failures).

Treat this event as diagnostic-only in this plan. Do not add Dart routing for it in this implementation pass.

No Section 7 changes are required in `go-mknoon/crypto/group.go`. This section changes epoch selection, validator behavior, bridge contracts, and promotion order, not AES-GCM helper code.

### 7.3 Affected Files

**Go:**

| File | Change |
|---|---|
| `go-mknoon/node/group.go` | Extend `GroupKeyInfo` with `PrevKey`, `PrevKeyEpoch`, `GraceDeadline` |
| `go-mknoon/node/pubsub.go` — `groupTopicValidator` | Dual-epoch verification with grace check |
| `go-mknoon/node/pubsub.go` — `UpdateGroupKey` | Preserve previous key + set grace deadline; no-op on stale/equal epochs |
| `go-mknoon/node/config.go` | Add `KeyRotationGracePeriod` constant |
| `go-mknoon/bridge/bridge.go` | Add non-mutating `group:generateNextKey` before delayed admin activation |

**Dart:**

| File | Change |
|---|---|
| `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart` | Generate next key without Go activation; distribute first; update own Go last; add distribution timeout |
| `lib/core/bridge/bridge_group_helpers.dart` | Expose the new non-mutating rotate/generate-next-key bridge contract |
| `lib/features/groups/application/group_key_update_listener.dart` | Save/promote the new key only after `callGroupUpdateKey` succeeds |
| `lib/features/groups/presentation/screens/group_info_wired.dart` | Preserve current member-removal flow while switching to generate/distribute/promote semantics |
| `test/features/groups/presentation/group_info_wired_test.dart` | Cover removal-flow compatibility and rotation ordering |
| `test/features/groups/application/member_removal_integration_test.dart` | Cover removal broadcast order vs key promotion |
| `lib/core/bridge/go_bridge_client.dart` | Add `group:generateNextKey` client support |
| `test/core/bridge/bridge_group_helpers_test.dart` | Cover generate-next-key helper contract |
| `test/core/bridge/go_bridge_client_test.dart` | Cover `group:generateNextKey` request/response handling |
| `go-mknoon/bridge/bridge_test.go` | Cover the new bridge contract and legacy `group:rotateKey` treatment |

### 7.4 TDD Tests (11 tests)

**Go tests** (`go-mknoon/node/pubsub_test.go`):

1. **Validator accepts previous epoch during grace period** — Rotate 1→2, validate epoch-1 envelope within 30s. Assert accept.
2. **Validator rejects previous epoch after grace expires** — Set `GraceDeadline` in past. Assert reject.
3. **Validator accepts current epoch regardless** — During grace, validate epoch-2 envelope. Assert accept.
4. **UpdateGroupKey preserves previous key** — Update 1→2. Assert `PrevKey="key-A"`, `PrevKeyEpoch=1`, `GraceDeadline` ~30s from now.
5. **First join sets no grace period** — Assert `PrevKey=""`, `GraceDeadline` zero.
6. **Old-epoch envelope decrypts successfully during grace** — Accept + decrypt + emit message, not just validate.

**Dart tests:**

7. **Rotation distributes before updating own validator** — Track call order. Assert all `sendP2PMessage` before `callGroupUpdateKey`.
8. **Updates own validator after distribution timeout** — One member offline (hangs). Assert admin's `callGroupUpdateKey` still fires after 15s.
9. **Distribution timeout does not block attempts to later recipients** — One member hangs. Assert other recipients were still attempted before admin promotion.
10. **GroupKeyUpdateListener promotes only after `group:updateKey` succeeds** — Emit key_update message. Assert `callGroupUpdateKey` called with new epoch and local persistence happens only after bridge success.
11. **Generated next key is not persisted before admin promotion** — Assert `groupRepo.getLatestKey()` remains at epoch N until `group:updateKey` succeeds, then advances to N+1.

### 7.5 Acceptance Proof

Integration scenario (3 nodes):
1. All joined at epoch 1, messages flow normally
2. Admin rotates key → epoch 2. Distribution begins.
3. Before B receives new key, B publishes with epoch 1 → A accepts (grace period) → C accepts (still on epoch 1)
4. After B receives epoch 2, B publishes with epoch 2 → all accept
5. During grace, the old-epoch message is validated **and decrypted**
6. After 30s grace expires, epoch 1 messages rejected
7. Alice's first post-rotation send uses epoch 2 after admin activation

---

## Section 8: 0-Peer Publish Detection and Compensation

### 8.0 Dependency

Section 8 depends on Section 4's inbox-result contract. It assumes `sendGroupMessage()` owns one in-flight inbox-store future and can observe whether it succeeded. Do not reintroduce fire-and-forget inbox behavior here.

### 8.1 Problem Statement

GossipSub's `topic.Publish()` returns `nil` even when there are zero peers subscribed to the topic. The current Go code calls `topic.ListPeers()` and logs the count as a diagnostic event, but the bridge response is always `{"ok": true}` regardless of peer count. Dart has no way to detect 0-peer publishes.

### 8.2 Design

#### Go: Return Peer Count in Publish Response

Change `PublishGroupMessage(...)` from:
`(string, error)`
to:
`(messageId string, topicPeers int, err error)`

After `topic.Publish()` succeeds, include `topicPeers` in the response:

```go
return okJSON(map[string]interface{}{
    "ok":         true,
    "messageId":  msgId,
    "topicPeers": len(topicPeers),
})
```

Update `bridge.go` and `cmd/testpeer` to pass through or explicitly discard `topicPeers`.

#### Dart: Conditional Inbox Store Escalation

After `await publishFuture` succeeds, read `result['topicPeers']`:

- **`> 0`**: Normal success, status `'sent'`, inbox remains fire-and-forget
- **`== 0`**: Escalate inbox store to **required** using the same in-flight inbox-store future. Do NOT issue a second `group:inboxStore` call. Status `'pending'`.
- **`0` + inbox fails**: Return `SendGroupMessageResult.error`
- **Missing key** (old Go binary): Treat as legacy success (backward compat)

New enum variant: `SendGroupMessageResult.successNoPeers`

`SendGroupMessageResult.successNoPeers` is a successful return value and must return a non-null `GroupMessage` whose `status` is `'pending'`.

| topicPeers | Inbox Store | Message Status | UI Indicator |
|---|---|---|---|
| > 0 | any | `'sent'` | Normal sent icon |
| 0 | succeeded | `'pending'` | Distinct icon, color, and accessibility semantic |
| 0 | failed | `'failed'` | Error state; retry affordance |

All send callers must treat `SendGroupMessageResult.successNoPeers` as a successful send path, not an error path.

First sufficient UI pass: render `pending` distinctly through icon, color, and accessibility semantic only. Do not add explanatory inline text in this phase.

`pending` requires no DB migration. The existing `group_messages.status` column already accepts arbitrary `TEXT` values.

### 8.3 Affected Files

| File | Change |
|---|---|
| `go-mknoon/node/pubsub.go` | Return peer count from `PublishGroupMessage` |
| `go-mknoon/bridge/bridge.go` | Include `topicPeers` in response |
| `lib/features/groups/application/send_group_message_use_case.dart` | Read `topicPeers`, escalate inbox, set status |
| `lib/features/groups/presentation/screens/group_conversation_wired.dart` | Treat `successNoPeers` as success for text and voice paths |
| `lib/features/feed/presentation/screens/feed_wired.dart` | Treat `successNoPeers` as success for feed composer |
| `lib/features/conversation/presentation/widgets/letter_card.dart` | Render outgoing `pending` distinctly from `sent` / `failed` |
| `lib/features/feed/presentation/widgets/message_bubble.dart` | Render `pending` distinctly in feed message bubbles |
| `lib/features/feed/presentation/widgets/scrollable_message_preview.dart` | Render `pending` distinctly in preview surfaces |
| `lib/features/groups/domain/models/group_message.dart` | Add/recognize `pending` as a first-class outgoing status |
| `lib/core/database/migrations/018_group_messages_tables.dart` | No schema change required; `status` already accepts arbitrary `TEXT` |
| `go-mknoon/cmd/testpeer/commands.go` | Accept or explicitly discard the new peer-count return value |

### 8.4 TDD Tests (10 tests)

**Go:**
1. **Returns peer count > 0** — Two nodes, both join topic. Assert `peerCount >= 1`.
2. **Returns 0 count when no peers** — Single node. Assert `peerCount == 0`, no error.

**Dart:**
3. **Returns `successNoPeers` + a non-null message whose status is `'pending'` when 0 peers + inbox OK** — ZeroPeerBridge. Assert result and status.
4. **Returns `error` when 0 peers + inbox fails** — Both fail. Assert error, no message saved.
5. **Returns `success` + status `'sent'` when peers > 0** — Normal bridge. Assert normal path.
6. **Treats missing `topicPeers` as legacy success** — Old bridge response without key. Assert success.
7. **Text send treats `successNoPeers` as success** — Assert no draft restoration or snackbar error.
8. **Voice send treats `successNoPeers` as success** — Assert optimistic row reaches `pending`, not failed.
9. **Feed composer treats `successNoPeers` as success** — Assert no error UI and no failed optimistic revert.
10. **`pending` renders distinctly** — Widget test proves `pending` is visually and semantically different from `sent` and `failed`.

---

## Section 9: Member Config Sync Atomicity

### 9.1 Problem Statement

Member addition and removal each require two sequential operations that must remain consistent:
1. Local DB mutation (`saveMember` / `removeMember`)
2. Go validator config update (`callGroupUpdateConfig`)

These are not wrapped in any transactional mechanism. If the bridge call fails, the system enters split-brain:

| Failure | DB state | Go state | Symptom |
|---|---|---|---|
| Add member, bridge fails | Member saved | Member absent from config | New member's messages silently rejected |
| Remove member, bridge fails | Member deleted | Member still in config | Removed member's messages still accepted |

Additionally, nothing prevents two system messages from interleaving their DB writes and bridge calls.

The current listener recovery idea in this draft is also too weak for out-of-order or dropped config-bearing system messages. Once local DB state is stale, "rebuild config from DB and retry once" is no longer an authoritative recovery source by itself.

### 9.2 Design

#### Phase A — Sufficient Now

This phase owns only:
1. rollback on use-case config-sync failure,
2. a single owner for `group:updateConfig` in each path,
3. per-group serialization of listener config updates,
4. one retry using the incoming `groupConfig` snapshot,
5. terminal `CONFIG_SYNC_FAILED` emission on second failure.

#### Deferred Hardening

The following are explicitly deferred unless this section is expanded to include `groups` schema, model, repository, and payload changes:
- persisted `membershipRevision`
- `lastAppliedMembershipRevision`
- dirty-config persistence
- stale-revision discard across restart

`addGroupMember(syncBridgeConfig: true)` performs:
`saveMember() -> callGroupUpdateConfig()`
and removes the member on failure.

Batch callers in `contact_picker_wired.dart` and `create_group_with_members_use_case.dart` pass `syncBridgeConfig: false` and keep exactly one final `callGroupUpdateConfig()`.

`removeGroupMember()` captures the removed member, rolls back on bridge failure, and remains the single-member removal sync point.

`GroupMessageListener` chains config work through a per-group future.

For each config-bearing system message:
1. read the incoming `groupConfig`
2. apply the local member DB mutation
3. call `group:updateConfig`
4. on failure, retry once using the same incoming `groupConfig`
5. on second failure, emit `CONFIG_SYNC_FAILED`

First sufficient version limits stale-order handling to in-process per-group serialization only.

### 9.3 Affected Files

| File | Change |
|---|---|
| `lib/features/groups/application/add_group_member_use_case.dart` | Add `callGroupUpdateConfig` + rollback on failure |
| `lib/features/groups/application/remove_group_member_use_case.dart` | Capture member, add rollback on bridge failure |
| `lib/features/groups/application/group_message_listener.dart` | Add `_configUpdateLock` queue; resync-retry in system message handlers |
| `lib/features/groups/presentation/screens/contact_picker_wired.dart` | Pass `syncBridgeConfig: false` in batch add-member flows and own the final config update |
| `lib/features/groups/application/create_group_with_members_use_case.dart` | Pass `syncBridgeConfig: false` in batch add-member flows and own the final config update |
| `lib/features/groups/presentation/screens/group_info_wired.dart` | Reuse the single-owner config update flow from member-management UI |

### 9.4 TDD Tests (7 tests)

1. **`addGroupMember` rolls back DB when bridge fails** — Bridge throws. Assert member row removed after rollback.
2. **`removeGroupMember` restores member when bridge times out** — Assert original member restored.
3. **Listener `_handleMemberAdded` retries once using the incoming `groupConfig` snapshot and then succeeds** — First call fails, second succeeds. Assert 2 `updateConfig` calls, member persisted.
4. **Listener `_handleMembersAdded` retries once using the incoming `groupConfig` snapshot and then succeeds** — Batch invite path covered, not only single-member add.
5. **Concurrent system messages execute sequentially across the full pipeline** — Two rapid messages. Assert configs built from correct sequential DB state.
6. **`_handleMemberRemoved` emits `CONFIG_SYNC_FAILED` when both attempts fail** — Both initial and retry throw. Assert terminal failure emission, no exception propagated.
7. **`addGroupMember(syncBridgeConfig: false)` avoids duplicate higher-level sync** — Assert batch callers still perform exactly one final `callGroupUpdateConfig`.

---

## Section 10: Announcement-Specific Acceptance Proofs

### 10.0 Dependencies

Proofs 10-A, 10-B, and 10-C depend on the final send-state contract from Sections 3, 6, and 8.

Until Section 8 lands, use current `success` semantics instead of `successNoPeers` / `pending`.

### 10.1 Why Needed

Announcements share the full transport stack but have asymmetric write permissions (admin-only). Enforcement happens at two independent layers:
1. **Dart:** `sendGroupMessage` checks `group.type == GroupType.announcement && group.myRole != GroupRole.admin`
2. **Go:** `groupTopicValidator` calls `isAllowedWriter(config, senderId)`, returns `ValidationReject` for non-admin

Proofs must demonstrate that the complete reliability path works correctly under this permission model, and that no reliability fix (retry, background task, inbox store) bypasses the authorization check.

They must also cover the optimistic UI layer, because the current group UI can create/persist an outgoing row before the use-case authorization check if the UI gate regresses.

### 10.2 Acceptance Proofs (6 scenarios)

#### Proof 10-A: Admin Text + Lock Phone → Delivered via Inbox

- **Setup:** Announcement group: 1 admin (Alice), 3 readers (Bob, Carol, Dave)
- **Action:** Alice sends text, immediately locks phone
- **Assert:** Run through `GroupConversationWired` plus lifecycle helpers, not only the use case. If `topicPeers > 0`, expect `SendGroupMessageResult.success`; if `topicPeers == 0`, expect `SendGroupMessageResult.successNoPeers` plus local `status: 'pending'`. Prove `bg:begin` before protected work and `bg:end` after completion.

#### Proof 10-B: Admin Media + Lock Phone → Delivered

- **Setup:** Announcement group: 1 admin, 2 readers. Alice has image attachment.
- **Action:** Alice sends with media, locks phone
- **Assert:** Run through the real widget/integration path with media metadata, `messageId`, and `keyGeneration` preserved. Success semantics follow the same `topicPeers > 0` vs `topicPeers == 0` rule as 10-A. Media attachment reference intact in all readers' messages.

#### Proof 10-C: Admin Voice + Lock Phone → Delivered

- **Setup:** Announcement group. Alice has audio attachment.
- **Action:** Alice sends voice-only (empty text), locks phone
- **Assert:** Empty text + media accepted (not rejected by empty-text guard), push body shows "Alice sent a voice message", and the proof runs through the Section 6 durable voice path rather than a simplified text-only harness.

#### Proof 10-D: Non-Admin Rejection and No Unauthorized Row

This proof has four parts:
1. Reader UI is read-only: no text input, no attach affordance, no mic affordance, no quote-send affordance.
2. If a hidden send or voice callback is invoked directly, no unauthorized retryable outgoing row may remain persisted.
3. Dart use case rejects the send with `SendGroupMessageResult.unauthorized` and makes no publish or inbox-store bridge call.
4. Go validator rejects a crafted reader announcement envelope.

#### Proof 10-E: Reader Catch-Up on Resume

Announcement reader catch-up on resume remains the announcement-specific acceptance proof here.

Same-message dedupe across live delivery plus inbox replay is owned by the generic drain / inbox reliability coverage and is only referenced from this section.

#### Proof 10-F: Post-Rotation Announcement Authorization

After key rotation, the next announcement sent by the admin uses the new epoch and remains authorized.

The full grace-period validation and decryption matrix is owned by Section 7 and is not re-proven here.

Bridge-backed multi-user announcement proofs depend on the Section 11 `GroupTestUser` bridge-send extension. Do not bypass the real group send path in these acceptance checks.

---

## Section 11: Test Infrastructure

### 11.1 Current Assessment

Existing reusable infrastructure:
- `FakeGroupPubSubNetwork`
- `GroupTestUser`
- `InMemoryGroupMessageRepository`
- `_SlowPublishBridge`
- `_InboxStoreFailBridge`
- `_CursorInboxBridge`
- `lifecycle_helpers.dart`
- `lifecycle_bridge.dart`
- existing group resume and inbox integration suites

Actually missing infrastructure for this plan:
- a bridge-backed group sender helper for `GroupTestUser`
- a bridge-level zero-peer publish helper that returns `topicPeers: 0`
- group-specific lifecycle wiring that reuses the shared lifecycle helpers
- fake-repo methods that mirror the new production recovery and retry interfaces

### 11.2 Required Extensions

#### Bridge Extensions

Promote and reuse existing bridge patterns first.
Add only one clearly missing helper for this plan:
- `_ZeroPeerPublishBridge` or equivalent response preset for `group:publish`

Background-task ordering helpers remain dependent on Section 3 and are not mandatory for the Section 11 baseline.

#### GroupTestUser Extensions

Primary missing extension:
- `sendGroupMessageViaBridge(...)`

Lifecycle helpers should reuse `lifecycle_helpers.dart`, not introduce a second lifecycle model.

Add listener control or re-subscribe hooks only if a targeted scenario actually needs them.

#### InMemoryGroupMessageRepository Extension

Extend the fake to mirror whatever new `GroupMessageRepository` methods Sections 1, 2, and 4 add.

Status-query convenience methods are optional and secondary.

### 11.3 New Test Helpers

#### `GroupReliabilityTestHarness`

`GroupReliabilityTestHarness` is optional extraction, not required baseline infrastructure.

Start by extending `GroupTestUser` plus the existing bridge and lifecycle helpers. Extract a higher-level harness only after at least two scenarios need the same orchestration repeatedly.

#### `MessageStatusTracker`

`MessageStatusTracker` is optional.

Introduce it only if direct repository assertions become too noisy after retry behavior lands.

### 11.4 Integration Test Scenarios

1. **Publish with zero peers falls back to inbox** — Use the bridge-backed send path. Alice publishes, 0 peers, Bob drains inbox. Assert delivery and assert the publish response exposed the zero-peer condition.
2. **Inbox store failure doesn't block publish** — Use bridge-backed send. Inbox fails, pubsub delivers. Assert message received.
3. **Stuck sending recovery after background** — Use slow publish plus lifecycle helpers, not only a synthetic `_isPaused` flag. Assert stuck, resume, assert recovered.
4. **Partial delivery with inbox drain completion** — 3 users, deliver to 1 via pubsub, 2 via inbox. Assert all have message.
5. **Full lifecycle round-trip** — Normal exchange, pause Bob, send while paused, resume Bob, drain, assert all messages, no duplication.
6. **Failed message retry after network recovery** — Use bridge-backed send. Track in-place retry of the original failed row.
7. **Multi-group resume doesn't burst** — 10 groups, 1 missed each. Assert bounded recovery (one retrieve per group).

Keep most bridge-backed orchestration scenarios in `test/features/groups/integration/`.

Keep only one or two simulator or device smoke checks in `integration_test/`, centered on cursor inbox drain or announcement recovery.

---

## Go-Side Changes

### 10.1 Peer Count in Publish Response (supports Section 8)

**Current:** `PublishGroupMessage` returns `(string, error)`. `GroupPublish` bridge returns `{"ok": true, "messageId": "..."}`.

**Change:** Change `PublishGroupMessage(...)` to return `(messageId string, topicPeers int, err error)` and pass `topicPeers` through the bridge response: `{"ok": true, "messageId": "...", "topicPeers": N}`. Update all direct callers, including `go-mknoon/cmd/testpeer/commands.go`, to accept or explicitly discard the new return value.

`GroupPublishReaction` is unchanged in this implementation pass. Peer-count return is limited to `GroupPublish`.

### 10.2 Key Rotation Grace Period (supports Section 7)

**Change `groupTopicValidator`:** After current-epoch signature check fails, retry with `prevKeyEpoch` while within `KeyRotationGracePeriod` (30s). The same grace-period concept must apply to decryption in `handleGroupSubscription`, not only validation.

**Change `UpdateGroupKey`:** Preserve previous key and grace deadline in one canonical state model. On `incomingEpoch > currentEpoch`, shift current into previous and stamp grace timing. On `incomingEpoch <= currentEpoch`, no-op.

### 10.3 Decryption Failure Event Emission (new)

**Current:** `handleGroupSubscription` logs decryption failures via `log.Printf` and skips with `continue`. Dart has no visibility.

**Change:** Emit `group:decryption_failed` event with `{groupId, senderId, keyEpoch, localKeyEpoch, error}`. Also emit `group:payload_parse_failed` for inner payload errors. Continue to skip the message after emitting. Treat these as observability events unless Dart consumers are added.

### 10.4 Validator Pre-Check for Own Messages (new)

**Current:** Sender's own validator runs asynchronously in GossipSub. If it rejects the sender's message (e.g., epoch mismatch), `topic.Publish()` still returns nil. Silent self-rejection.

**Change:** Defer validator pre-check for own messages out of this implementation plan. It remains a follow-up hardening item after peer-count and grace-period work lands.

### Go Implementation Order

1. **10.1** (Peer Count) — standalone, simplest, unblocks Dart S8
2. **10.3** (Decryption Events) — standalone, adds observability
3. **10.2** (Grace Period) — validator + decryption grace machinery
4. **10.4** (Pre-Check) — deferred follow-up after shared validation logic is extracted

### Bridge API Summary

| Function | Current → New | Breaking? |
|---|---|---|
| `GroupPublish` success | `{ok, messageId}` → `{ok, messageId, topicPeers}` | No at the JSON bridge level; Go call sites must accept the new return value |
| `GroupPublish` error | unchanged in this plan | No |
| `GroupPublishReaction` | unchanged in this plan | No |
| New event | — | `group:decryption_failed {groupId, senderId, keyEpoch, localKeyEpoch, error}` |
| New event | — | `group:payload_parse_failed {groupId, senderId, envelopeType}` |
| Group key generation | — | Add `group:generateNextKey {groupId} -> {ok, groupKey, keyEpoch}` before delayed admin activation |

---

## Wire Envelope Persistence Design

### Problem

In 1:1, the wire envelope is persisted BEFORE send, enabling crash recovery via replay. Group messages have no equivalent — the v3 envelope is constructed inside Go, never returned to Dart. Group inbox retry also needs a second persisted payload; publish retry input alone is not enough.

### Options Analysis

| Option | Description | Pros | Cons |
|---|---|---|---|
| **A** | Go returns envelope; Dart persists; Go publishes raw bytes | Exact parity with 1:1; no re-encryption on retry | Requires new Go API, 2 bridge round-trips, key epoch staleness |
| **B** | Persist plaintext parameters; retry re-encrypts | No Go changes; key rotation handled naturally; no private key in DB | Re-encryption on retry; slightly more expensive |
| **C** | Persist bridge command JSON; replay exact call | No Go changes; exact replay | Stores `senderPrivateKey` in DB (security regression); bridge format coupling |

### Recommendation: Option B (Persist Plaintext Parameters)

**Rationale:**
1. **No Go changes required** — avoids cross-platform risk
2. **Re-encryption is acceptable** — group encryption uses stable symmetric key; fresh nonce is equally valid
3. **Key rotation handled naturally** — Go picks up current key on retry
4. **No private key in DB** — `senderPrivateKey` resolved from `SecureKeyStore` at retry time
5. **Alignment with inbox store** — both paths share plaintext retry inputs, but inbox retry needs its own payload column because its request shape is different from publish

### `retryPayload` Design

**Column:** `wire_envelope TEXT` (reuses the column name for consistency with 1:1, stores plaintext JSON not encrypted envelope)

**Contents:**
```json
{
  "groupId": "...",
  "text": "...",
  "senderPeerId": "...",
  "senderPublicKey": "...",
  "senderUsername": "...",
  "quotedMessageId": "...",
  "media": [...]
}
```

**Note:** `senderPrivateKey` is NOT stored. Resolved from `IdentityRepository` → `SecureKeyStore` at retry time.

**Second column:** `inbox_retry_payload TEXT`

**Contents:**
```json
{
  "groupId": "...",
  "message": {...},
  "recipientPeerIds": ["..."],
  "pushTitle": "...",
  "pushBody": "..."
}
```

### Lifecycle

| Phase | status | wire_envelope | inbox_retry_payload |
|---|---|---|---|
| Pre-publish | `'sending'` | JSON string | JSON string |
| Publish succeeded with peers | `'sent'` | `NULL` (cleared) | `NULL` if inbox succeeded, retained if inbox retry needed |
| Publish succeeded with 0 peers + inbox OK | `'pending'` | `NULL` (cleared) | `NULL` |
| Publish failed | `'failed'` | JSON string (retained for retry) | JSON string |
| Retry succeeded | `'sent'` or `'pending'` | `NULL` (cleared) | cleared if inbox succeeded |
| Retry failed again | `'failed'` | JSON string | JSON string |

### Send Flow Change

The send flow changes from "publish then persist" to "persist-with-sending-status then publish then update-status":

1. After validation, build `retryPayload` JSON from validated parameters
2. Build `inboxRetryPayload` JSON from the exact `callGroupInboxStore` request inputs
3. Create `GroupMessage` with status `'sending'`, `wireEnvelope`, and `inboxRetryPayload` populated
4. Persist via `msgRepo.saveMessage(message)` — **BEFORE bridge call**, inside `sendGroupMessage()` so all production callers use the same contract
5. Call `callGroupPublish` + one `_tryInboxStore` future concurrently
6. On success with peers: update to `'sent'`, clear `wireEnvelope`, clear `inboxRetryPayload` only if inbox succeeded
7. On success with 0 peers + inbox OK: update to `'pending'`, clear both retry payloads
8. On failure: update to `'failed'`, keep retry payloads

`FeedWired` must move onto this same contract. The sufficient plan should no longer rely on some callers pre-persisting rows in the UI while others do not.

This closes **Window A** (crash before publish returns): the row exists with `'sending'` + `wireEnvelope`. The retrier can pick it up.

---

## Appendix A: Affected Files Summary

### New Files (to be created)

| File | Purpose |
|---|---|
| `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart` | Transition stuck `'sending'` → `'failed'` |
| `lib/features/groups/application/retry_failed_group_messages_use_case.dart` | Retry `'failed'` group messages |
| `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart` | Retry messages where `inbox_stored == false` |
| `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` | Retry interrupted group media uploads |
| `lib/core/database/migrations/041_group_message_reliability_columns.dart` | New columns |

### Modified Files

**Dart Application Layer:**
- `lib/features/groups/application/send_group_message_use_case.dart` — pre-persist with `'sending'`, `_tryInboxStore`, `wireEnvelope`, `successNoPeers`, and gated parallel follow-up reads
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart` — reorder: distribute first, update own last
- `lib/features/groups/application/add_group_member_use_case.dart` — add `callGroupUpdateConfig` + rollback
- `lib/features/groups/application/remove_group_member_use_case.dart` — rollback on bridge failure
- `lib/features/groups/application/group_message_listener.dart` — config update queue, resync-retry
- `lib/features/groups/application/group_key_update_listener.dart` — align listener with final key activation / grace model
- `lib/features/feed/presentation/screens/feed_wired.dart` — unify feed-inline send with the same pre-persist and `successNoPeers` contract

**Dart Domain Layer:**
- `lib/features/groups/domain/models/group_message.dart` — `wireEnvelope`, `inboxStored`, `inboxRetryPayload`, and `pending` status handling
- `lib/features/groups/domain/repositories/group_message_repository.dart` — new methods
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart` — implement
- `lib/features/media/domain/repositories/media_attachment_repository.dart` — attachment-scoped upload retry state

**Dart Presentation Layer:**
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — `callBgBegin`/`callBgEnd`, parallel uploads, durable voice copy, stable IDs
- `lib/features/conversation/presentation/widgets/letter_card.dart` — render outgoing `pending` distinctly
- `lib/features/feed/presentation/widgets/message_bubble.dart` — render outgoing `pending` distinctly
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart` — render outgoing `pending` distinctly
- `lib/features/groups/presentation/screens/group_info_wired.dart` — preserve member-removal flow while updating rotation/config ownership

**Dart Core:**
- `lib/core/database/helpers/group_messages_db_helpers.dart` — reliability helpers including inbox retry payload updates
- `lib/core/lifecycle/handle_app_paused.dart` — group sweep
- `lib/core/lifecycle/handle_app_resumed.dart` — Steps 3d/3e plus group upload and inbox retry wiring
- `lib/core/bridge/bridge_group_helpers.dart` — peer count and non-mutating key-generation contract
- `lib/core/bridge/go_bridge_client.dart` — `group:generateNextKey` client support
- `lib/main.dart` — wire all new callbacks

**Go:**
- `go-mknoon/node/pubsub.go` — peer count return, grace period, decryption events
- `go-mknoon/node/group.go` — extend `GroupKeyInfo`
- `go-mknoon/node/config.go` — `KeyRotationGracePeriod`
- `go-mknoon/bridge/bridge.go` — include `topicPeers`, new event types
- `go-mknoon/cmd/testpeer/commands.go` — accept or discard new peer-count return value

**Test Infrastructure:**
- `test/core/bridge/fake_bridge.dart` — add reusable zero-peer and ordering presets
- `test/shared/helpers/lifecycle_helpers.dart` — reuse shared lifecycle orchestration for group scenarios
- `test/shared/fakes/test_user.dart` — extend shared user helpers for bridge-backed group sends

### New Test Files

| File | Tests |
|---|---|
| `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` | ~36 |
| `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart` | 3 |
| `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` | 3 |
| `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` | 4 |
| `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` | 5 |
| `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` | 6 |
| `test/features/groups/presentation/screens/group_voice_reliability_test.dart` | 6 |
| `test/core/lifecycle/handle_app_paused_group_test.dart` | 4 |
| `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` | 4 |
| `test/features/groups/integration/group_message_retry_smoke_test.dart` | 7 |
| `go-mknoon/node/pubsub_delivery_test.go` | 8 |

**Total:** scope and test counts should be recalculated after implementation, but the affected surface is smaller than the original draft because retry-visibility UI streaming and persisted config-revision hardening are deferred.

---

## Appendix B: Implementation Risk Assessment

| Section | Risk if Skipped | Severity | Blast Radius |
|---|---|---|---|
| 1. Stuck-Sending Recovery | Messages hang in "sending" forever. Blocks retry in S2, S5, S6. | **Critical** | All group messaging |
| 2. Lifecycle Pause Handler | Backgrounding during send produces orphaned messages. Most common user action. | **Critical** | All mobile users |
| 3. iOS Background Task | iOS kills process mid-send after ~5s. | **High** | iOS users only |
| 4. Inbox Store Fallback | Small groups silently drop messages. GossipSub alone insufficient. | **Critical** | Small groups, offline-first |
| 5. Parallel Media Upload | Single slow upload blocks all messages. Group feels unresponsive. | **High** | Any group with media |
| 6. Voice Message | Voice notes fail silently on slow connections. | **Medium** | Voice message users |
| 7. Key Rotation Safety | Messages permanently undecryptable during rotation. Silent, irreversible. | **High** | Any group during rotation |
| 8. 0-Peer Detection | Messages "sent" but received by nobody. Most insidious failure — invisible. | **High** | Groups with unreliable connectivity |
| 9. Member Config Sync | Divergent member lists. Self-heals on next sync but confusing window. | **Medium** | Multi-admin groups |
| 10. Announcement Proofs | Delivery gaps undetected in announcements. | **Low** | Announcement groups |
| 11. Test Infrastructure | Regressions go undetected; flaky tests accumulate. | **High** | Development velocity |

**Non-negotiable for release:** DB Schema / Wire Envelope Persistence, Sections 1, 4, and 8. Section 2 remains non-negotiable for the iOS send-then-lock failure mode, and Section 7 carries disproportionate severity relative to cost and should not be deferred past Phase 2.
