# Transport Routing Strategy

> **Scope:** The decision logic for choosing transport paths and handling failures.
> **Includes:** 1:1 race strategy (connection reuse, WiFi vs direct, relay probe, inbox fallback), group dual-path (GossipSub + inbox coordination, 4-way result matrix), group reaction routing (add + remove), other 1:1 variants (introductions, reactions, contact requests, group invites, key updates, profile updates, deletions, voice messages), retry/recovery routing (1:1 failed/unacked, group retry, upload retriers, key exchange retry, introduction retry), share delivery, post delivery subsystem, group lifecycle GossipSub events (blast radius), test coverage matrix per decision branch, uncovered gaps, blast radius per routing change.
> **Excludes:** Go protocol internals (see `00`), Dart listener/repo wiring (see `01`), UI layer (see `02`), and detailed timeout tuning / performance analysis beyond the routing-relevant budgets called out here (see `03`).

---

## 1. 1:1 Message Routing

**File:** `lib/features/conversation/application/send_chat_message_use_case.dart`

### Decision Tree

```
sendChatMessage()
  |
  +-- Gate: text non-empty or has attachments? --NO--> return invalidMessage
  +-- Gate: edit action requires messageId, timestamp, createdAt? --NO--> return invalidMessage
  +-- Gate: node started? --NO--> return nodeNotRunning
  |
  +-- Serialize: build envelope, encrypt if ML-KEM key available
  |     Encryption failure (ok != true or exception) → return sendFailed (terminal, no inbox)
  +-- Pre-persist: update wireEnvelope in DB (only if messageId != null — edits/retries; new sends persist later)
  |
  +-- Is peer already connected? (local state check, no network)
  |     |
  |     YES --> sendMessageWithReply (2s timeout)
  |     |         |
  |     |         +-- sent == true + ACK --> DONE (transport: direct/relay/local)
  |     |         +-- sent == true + no ACK --> try inbox handoff
  |     |         |     +-- Inbox OK  --> status: delivered, transport: inbox
  |     |         |     +-- Inbox fail --> status: sent, wireEnvelope retained for retry
  |     |         +-- sent == false --> silent fall-through to race (no exception, no else branch)
  |     |         +-- Exception thrown --> caught, fall through to race
  |     |
  |     NO --> fall through to race
  |
  +-- RACE: start both futures simultaneously
  |     |
  |     +-- WiFi path (only if isLocalPeer(peerId) returns true):
  |     |     sendLocalMessage + implicit ACK
  |     |     Budget: 1.5s (interactiveLocalBudget)
  |     |     On failure: relayProbeEligible = false
  |     |
  |     +-- Direct P2P path (always started):
  |           discover (budgetMs) --> dial (budgetMs) --> send (budgetMs)
  |           All three sub-steps receive the same 2000ms (interactiveDirectBudget) value,
  |           but the outer .timeout(2s) wall-clock cap means total cannot exceed 2s.
  |           On peer_not_found: relayProbeEligible = true
  |           On dial_failed: relayProbeEligible = true
  |           On send_failed: relayProbeEligible = false
  |           On timeout: relayProbeEligible = false
  |     |
  |     First success wins. No explicit cancellation is performed; later results are ignored.
  |     |
  |     +-- Both succeed --> first to complete wins
  |     +-- One succeeds --> that one wins
  |     +-- Both fail --> aggregate failures (see Race Aggregation below)
  |
  +-- Any race winner? --YES--> DONE
  |
  +-- Relay probe eligible? (ANY failure across race legs had relayProbeEligible = true)
  |     |
  |     NO --> skip to inbox
  |     |
  |     YES --> probeRelay (Go-side RelayProbeTimeout: 5s; no Dart-side timeout wrapper)
  |               |
  |               +-- Exception from probeRelay: return failed(failureReason), skip to inbox
  |               |
  |               +-- connected:
  |               |     1. dialPeer (2s timeout) — establishes relay circuit (best-effort, errors caught)
  |               |     2. send loop: up to 2 attempts (relayProbeSendAttempts), 250ms backoff between
  |               |        +-- Any attempt succeeds --> DONE (transport: relay)
  |               |        +-- All attempts fail --> return failed('send_failed'), fall to inbox
  |               |
  |               +-- noReservation: return failed('peer_not_found') --> fall to inbox
  |               +-- error: return failed(original failureReason) --> fall to inbox
  |
  +-- Inbox fallback: storeInInbox (Go-side InboxTimeout: 15s; no Dart-side timeout wrapper)
        |
        +-- Success --> DONE (transport: inbox, status: delivered)
        +-- Failure --> status: failed, wireEnvelope retained for PendingMessageRetrier replay
```

### Race Aggregation Logic

When all race futures fail, the aggregator iterates all `_RaceResult` failures. If **any** failure has `relayProbeEligible: true`, the combined result is probe-eligible and the `failureReason` is replaced with that failure's reason. This is an any/or scan — a single probe-eligible failure from either the WiFi or direct leg enables the relay probe.

The same aggregation logic applies in both the `.then()` (non-exception results) and `.catchError()` (thrown exceptions) handlers. Thrown exceptions create a `_RaceResult.failed(e.toString())` with `relayProbeEligible: false` by default, but the aggregator still scans all accumulated failures.

### Connection Reuse

**How it works:** `p2pService.currentState.connections` is an in-memory list maintained by Go bridge callbacks (`peer:connected` adds, `peer:disconnected` removes). It is also reconciled by the periodic `node:status` health check (30s interval).

**Staleness behavior:** If Go misses a disconnect event, the Dart-side connection list can temporarily stay stale until a later health check or recovery path corrects it. In that case, the reuse attempt can fail and fall through to the normal race.

**After a successful send:** If the connection remains present in `p2pService.currentState.connections`, the next send can use the same fast path without a fresh discover/dial.

### WiFi Prioritization

WiFi gets a **tighter budget** (1.5s vs 2s). The WiFi path is only constructed when `isLocalPeer(peerId)` returns true — which checks the current local-discovery state populated by the local discovery service.

WiFi is **not** given priority in the race — both paths start at the same instant. Its code-level advantage is only the tighter local budget, which prevents a stalled local connection from blocking the direct path for long.

### Relay Probe Eligibility

Only two failure reasons enable the relay probe:
- `peer_not_found` — rendezvous couldn't find the peer (stale registration)
- `dial_failed` — peer was found but couldn't connect (NAT, transient)

These suggest the peer might be online but undiscoverable. The probe bypasses rendezvous entirely by attempting a direct circuit relay connection.

Four failure reasons do NOT enable the probe:
- `send_failed` — peer was connected but the write failed (application-layer problem)
- `direct_timeout` — the outer 2s cap fired (we don't know which step was slow)
- `local_send_failed` — WiFi issue, not a discoverability problem
- Thrown exceptions — `.catchError()` creates `_RaceResult.failed()` with default `relayProbeEligible: false`

### Unacked Send Handling

A send can succeed (bytes written) without being acknowledged (no ACK frame read). When this happens:
1. Immediate inbox handoff attempted (best-effort durability upgrade)
2. If inbox succeeds: status = `delivered`, transport = `inbox`
3. If inbox fails: status = `sent`, wireEnvelope retained for PendingMessageRetrier replay

### Stale Attachment Cleanup

Before persisting outgoing media attachments, `_persistOutgoingMedia` checks for stale `upload_pending` placeholder rows from prior failed attempts. If any are found for the same message, it clears that message's existing attachment rows before saving the final attachments.

### Constants

| Constant | Value | Used By |
|---|---|---|
| `interactiveLocalBudget` | 1500ms | WiFi race path |
| `interactiveDirectBudget` | 2000ms | Direct race outer cap, per-step budget, connection reuse timeout, relay probe dial + send timeout |
| `relayProbeSendAttempts` | 2 | Relay probe send loop |
| `relayProbeRetryBackoff` | 250ms | Delay between relay probe send attempts |

---

## 2. Group Message Routing

**File:** `lib/features/groups/application/send_group_message_use_case.dart`

### Decision Tree

```
sendGroupMessage()
  |
  +-- Gate: group exists? --NO--> return groupNotFound
  +-- Gate: group dissolved? --YES--> return groupDissolved
  +-- Gate: announcement group + recovery in progress? --YES--> return error
  |     (Only applies to announcement groups. Regular chat groups skip this gate.)
  +-- Gate: announcement group and sender not admin? --YES--> return unauthorized
  +-- Gate: empty message (no text + no media)? --YES--> return error
  +-- Gate: no key + sender not admin (bootstrap pending)? --YES--> return error
  |     (Admin bypass: admin can proceed with keyEpoch = 0 when no key exists)
  |
  +-- Build wireEnvelope (always present) and inboxRetryPayload
  |     inboxRetryPayload can be NULL if: latestKey == null (admin with no key)
  |     or buildGroupOfflineReplayEnvelope throws (exception swallowed)
  |
  +-- Pre-persist: save with status:sending + wireEnvelope + inboxRetryPayload BEFORE bridge call
  |
  +-- Start both futures (no await between them — both bridge calls in-flight simultaneously):
  |     |
  |     +-- publishFuture: callGroupPublish (10s timeout)
  |     |     Go handles v3 encrypt + sign internally
  |     |
  |     +-- inboxFuture: _tryInboxStore (10s timeout) OR Future.value(false) if replayEnvelope == null
  |           Passes the encrypted replayEnvelope (NOT the raw inboxPayload JSON)
  |           Targets: all non-sender members with non-empty peerIds, deduplicated
  |           Empty recipient list passed as null (not empty list) to bridge
  |           Side-channel: .then() sets inboxResult variable for non-blocking check
  |
  +-- await publishFuture (publish is the authority)
  |     Exception path: catch sets publishOk=false, publishErrorCode remains null
  |
  +-- Evaluate result matrix:
        |
        +-- Publish FAILED (publishOk == false):
        |     |
        |     +-- await inboxFuture (blocking)
        |     |
        |     +-- BRIDGE_TIMEOUT + inbox OK:
        |     |     status: sent, wireEnvelope: null, inboxStored: true, inboxRetryPayload: null
        |     |     Return: success (timeout might be bridge MethodChannel, not actual publish)
        |     |
        |     +-- Non-timeout error + inbox OK:
        |     |     status: failed, inboxStored: true, inboxRetryPayload: null
        |     |     Return: error (publish problem should not be hidden)
        |     |
        |     +-- Non-timeout error + inbox FAILED:
        |     |     status: failed, inboxStored: false, inboxRetryPayload: kept
        |     |     wireEnvelope also retained (no updateWireEnvelope call)
        |     |     Return: error
        |     |
        |     +-- Exception (publishErrorCode == null) + inbox OK/FAIL:
        |           Falls through to non-timeout branch above (null != 'BRIDGE_TIMEOUT')
        |
        +-- Publish OK + topicPeers == null (legacy, no topicPeers key in response):
        |     Single-tick yield: await Future<void>.value() if inboxResult still null
        |     Then snapshot inboxResult:
        |       true  → status: sent, both payloads cleared
        |       false → status: pending, inboxRetryPayload kept
        |       null  → status: pending, background promotion via _finalizeSuccessfulPublishInboxStoreInBackground
        |     Return: success
        |
        +-- Publish OK + topicPeers > 0:
        |     Same three-way inbox check as legacy path above
        |     Return: success
        |
        +-- Publish OK + topicPeers == 0 (nobody listening):
              await inboxFuture (blocking — must know inbox outcome)
              Inbox OK → status: sent, Return: successNoPeers
              Inbox fail → status: failed, Return: error
                (inboxRetryPayload implicitly retained — no updateInboxRetryPayload call)
```

### Key Asymmetries

**Publish is the authority, inbox is the backup.** Publish failure with inbox success is still marked `failed` (except for the BRIDGE_TIMEOUT special case). Publish success does **not** always produce a final durable `sent` state immediately: when the inbox result is still pending or fails, the stored message can remain `pending` until the inbox path completes or is retried.

**Why?** GossipSub delivers to live peers immediately. Inbox is store-and-forward for offline peers. If publish says "0 topic peers" but inbox succeeds, the message will be retrieved when members come online — that's a valid success. But if publish returns a non-timeout error, something is wrong with the group's pubsub state, and marking it as success would hide the problem.

**The BRIDGE_TIMEOUT exception:** A 10s timeout on publish doesn't mean the publish failed — GossipSub is fire-and-forget, and the timeout might be on the bridge MethodChannel, not on the actual publish. So the code treats it as "probably worked, inbox has it anyway."

### Concurrent Execution Mechanism

Not `Future.wait`. Both futures are created back-to-back without any `await` between them, putting both bridge calls in-flight simultaneously. Only `publishFuture` is explicitly awaited. The inbox outcome is observed via a side-channel `bool? inboxResult` variable that is set by a `.then()` callback on `inboxFuture`. When publish completes, the code checks whether `inboxResult` is already non-null (inbox finished) or still null (inbox still in-flight). For the `topicPeers > 0` and legacy paths, a single-tick `await Future<void>.value()` yield is used as a best-effort check before deciding between foreground await and background promotion.

### Inbox Recipient Selection

`_loadGroupPushRecipients` calls `groupRepo.getMembers(groupId)`, maps to peer IDs, filters out the sender and empty IDs, and deduplicates via `.toSet()`. If the resulting list is empty (group has only the sender), it is passed as `null` to the bridge call — the relay receives no recipient list.

---

## 3. Group Reaction Routing

**Files:** `lib/features/groups/application/send_group_reaction_use_case.dart` (add), `lib/features/groups/application/remove_group_reaction_use_case.dart` (remove)

Both add and remove reactions use the same routing. `removeGroupReaction` mirrors `sendGroupReaction` structurally — GossipSub publish (blocking, failure terminal) → durable outbox staging → unawaited inbox store. The only difference: remove skips the `message exists` gate (validates group + membership only) and deletes the local reaction row instead of saving one.

**Substantially different from group messages:**

```
sendGroupReaction()
  |
  +-- Gate: group exists
  +-- Gate: sender is member (any member can react, even in announcement groups)
  +-- Gate: message exists
  |
  +-- Build payload (action: 'add' or 'remove' depending on use case)
  |
  +-- Await publish (callGroupPublishReaction, 10s timeout) — BLOCKING
  |     |
  |     +-- result['ok'] != true --> return publishFailed (NO inbox fallback)
  |     +-- Exception caught --> return publishFailed (NO inbox fallback)
  |     +-- Note: BRIDGE_TIMEOUT is caught inside callGroupPublishReaction and
  |     |   returned as { "ok": false }, so it triggers the ok != true branch above,
  |     |   NOT the exception catch. Either way, result is publishFailed.
  |     +-- Success --> continue
  |
  +-- _stageReactionInboxStore (AWAITED — two internal failure points):
  |     |
  |     +-- Try 1: buildGroupOfflineReplayInboxRetryPayload (bridge encrypt call)
  |     |     Throws → emits GROUP_REACTION_OUTBOX_STAGE_FAILED, returns early
  |     |     (inbox call never fires, saveReaction still runs below)
  |     |
  |     +-- Try 2: reactionReplayOutboxRepo.saveEntry (DB write)
  |     |     Throws → emits GROUP_REACTION_OUTBOX_STAGE_FAILED, sets staged=false
  |     |     (does NOT return early — inbox call still fires below)
  |     |
  |     +-- Fire-and-forget: unawaited(_attemptReactionInboxStore(...))
  |           Calls storeGroupOfflineReplayFromRetryPayload (group:inboxStore bridge call)
  |           Always fires regardless of staged flag
  |           If inbox fails + staged=true → outbox status updated to failed
  |           If inbox succeeds + staged=false → no DB update (staged guard at line 247)
  |           If inbox succeeds + staged=true → outbox status updated to stored
  |
  +-- Convert payload to MessageReaction (toMessageReaction)
  +-- Persist reaction locally (saveReaction) — always runs after staging returns
  |     Runs even if inbox staging silently failed
  +-- Return success
```

**Key differences from group messages:**
- Publish failure is terminal — no inbox fallback, no retry via inbox
- Publish is awaited sequentially (not raced with inbox)
- Inbox is fire-and-forget after successful publish (via durable outbox pattern)
- No 4-way matrix, no topicPeers check
- Reactions use a separate `GroupReactionReplayOutboxRepository` for durable inbox staging
- BRIDGE_TIMEOUT on publish is **terminal** for reactions (returns `publishFailed`), unlike group messages where BRIDGE_TIMEOUT + inbox OK = success
- No pre-persist step — reaction is saved locally after publish succeeds, regardless of inbox staging outcome
- `staged` flag gates whether outbox DB status updates occur, but the actual inbox bridge call fires unconditionally
- Two separate try/catch blocks in `_stageReactionInboxStore` produce identical `GROUP_REACTION_OUTBOX_STAGE_FAILED` flow event names, making them indistinguishable in logs
- `toMessageReaction()` runs before `saveReaction` — if it fails, no local persistence and no success return

---

## 4. Other Message Types (1:1 variants)

### 1:1 Introductions

**File:** `lib/features/introduction/application/introduction_outbound_delivery.dart`

**Initial delivery** uses the **full race strategy** — same as chat messages: connection reuse → WiFi/direct race → relay probe → inbox fallback. Implemented in `deliverIntroductionPayloadReliably`, which replicates the four-stage race independently from `sendChatMessage`. Imports shared constants (`interactiveDirectBudget`, `interactiveLocalBudget`, `relayProbeSendAttempts`, `relayProbeRetryBackoff`) from `send_chat_message_use_case.dart`.

**Pre-persist:** Before the race, saves an `IntroductionOutboxDelivery` row with `deliveryStatus: sending` and `deliveryPath: pending`. After delivery completes, updates the row to `delivered`/`sent`/`failed` with the winning transport path. Delivered rows are deleted immediately after the status update.

**Connection reuse check differs from chat:** Uses `p2pService.isConnectedToPeer(targetPeerId) || p2pService.currentState.connections.any(...)` — an OR of two checks. Chat send uses only the `connections.any(...)` check.

**Race aggregation is correct:** Unlike the delete use case, introduction's `.catchError` correctly calls `_mergeFailures` which scans all failures for `relayProbeEligible`. No known divergence from the chat send race aggregator.

**Retry path is inbox-only:** `retryPendingIntroductionDeliveries` loads all retryable outbox rows and delivers each via `p2pService.storeInInbox` only — no race, no relay probe, no discover/dial. Already-delivered rows with `deliveryPath == inbox` are cleaned up (deleted) without re-sending. Failed inbox retries update the outbox row to `failed` with `lastError: 'inbox_retry_failed'`.

### 1:1 Reactions (Add + Remove)

**Files:** `lib/features/conversation/application/send_reaction_use_case.dart` (add), `lib/features/conversation/application/remove_reaction_use_case.dart` (remove)

Both use the same send-or-inbox routing:

```
p2pService.sendMessage(peerId, envelope)
  |
  +-- Success --> DONE (add: save reaction locally; remove: delete reaction locally)
  +-- Failure --> p2pService.storeInInbox(peerId, envelope)
                    |
                    +-- Success --> DONE (delivered via inbox)
                    +-- Failure --> status: failed (retry-eligible)
```

No race strategy, no WiFi path, no relay probe. ML-KEM encryption is mandatory (non-nullable `recipientMlKemPublicKey` parameter). Encryption failure is terminal — returns `encryptionFailed`, inbox is NOT attempted. Only send-layer failures trigger the inbox fallback.

### Group Invites

**File:** `lib/features/groups/application/send_group_invite_use_case.dart`

Same simple send-or-inbox pattern as 1:1 reactions. Two terminal encryption points: `recipientMlKemPublicKey == null` returns `encryptionRequired` (before any send); `encryptResult['ok'] != true` returns `sendFailed` (before any send). Neither triggers inbox fallback.

### Contact Requests

**File:** `lib/features/contact_request/application/send_contact_request_use_case.dart`

A distinct routing pattern — not the full race, not simple send-or-inbox:

```
sendContactRequest()
  |
  +-- WiFi-first: if isLocalPeer, try sendLocalMessage
  |     Success → return success (done)
  |     Failure → fall through
  |
  +-- Sequential discover → dial → sendMessageWithReply (requires sent && acknowledged)
  |     Success → return success (done)
  |     Any step fails → fall through
  |
  +-- Inbox fallback: storeInInbox
        Success → return success
        Failure → return sendFailed
```

No race (sequential, not parallel). No relay probe. Encryption: v2 if `recipientPublicKey` parameter is provided, v1 plaintext fallback otherwise. No silent downgrade from v2 to v1 when a v2 key is provided but encryption fails — encryption failure with a provided key is terminal.

### Key Updates

**File:** `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`

Two transport operations:

1. **1:1 P2P distribution** to each member via `p2pService.sendMessage`. Members without `mlKemPublicKey` are filtered out before distribution. At the call sites in `group_info_wired.dart`, the `sendP2PMessage` callback hardcodes `return true` regardless of `sendMessage` outcome — the delivery result is discarded. Distribution uses `Future.wait` across all eligible members with per-member encryption. Errors are caught and logged without affecting the overall result. If the `sendP2PMessage` parameter is null, `Future.value(true)` is returned (no-op). **No inbox fallback** for key distribution.

2. **GossipSub broadcast** of a `key_rotated` system message via `callGroupPublish` (step 4, after the admin's own key is promoted locally). Broadcast failure is non-fatal — emits `GROUP_ROTATE_KEY_BROADCAST_ERROR` but does not prevent the function from returning the new key info.

### Profile Updates

**File:** `lib/features/settings/application/upload_profile_picture_use_case.dart`

**Not simple send-or-inbox.** Uses `sendMessageWithReply` (not `sendMessage`) with `acknowledged` requirement for direct success. Two-attempt inbox fallback: if first `storeInInbox` fails, performs `performImmediateHealthCheck()`, then retries `storeInInbox` once more. Uses v1 plaintext envelope (no encryption).

### 1:1 Message Deletion

**File:** `lib/features/conversation/application/delete_message_use_case.dart`

Uses the **full race strategy** (mirrors chat messages) — connection reuse → WiFi/direct race → relay probe → inbox. Imports shared constants from `send_chat_message_use_case.dart`.

**Known divergence from chat race:** The delete `.catchError()` race aggregator creates `_DeleteRaceResult.failed(e.toString())` without `relayProbeEligible: true`, then uses `failures.first.reason` at completer completion with no `relayProbeEligible` scan. If a race future throws (rather than returning a failure result), the relay probe step is suppressed for deletions but would be attempted for chat sends. The chat send aggregator was fixed to scan correctly; the delete copy was not updated.

**Additional divergence:** In `_persistOutgoingDeleteResult`, when `sendResult.sent && !acknowledged`, the code attempts a second `storeInInbox` call after the race succeeds, before falling back to a `sent` tombstone. This is an extra implicit inbox attempt not in the main race flow.

### Posts

**File:** `lib/features/posts/application/post_delivery_runner.dart`

Fan-out: `_runRecipientFanout` delivers to recipients concurrently with a sliding window of up to `defaultPostDeliveryConcurrency = 25` parallel recipients. Per-recipient delivery in `_deliverToRecipient`:

1. `ensurePostRecipientDirectConnection` — discover + dial via `post_follow_on_delivery.dart`
2. `sendMessageWithReply` (only if connection succeeded, waits for ACK)
3. `storeInInbox` — inbox fallback if direct fails or connection unavailable

If discovery fails, falls directly to inbox without attempting `sendMessageWithReply`. There is no relay probe stage.

Encryption is non-terminal: if `bridge == null || recipient.mlKemPublicKey == null`, falls back to v1 plaintext envelope.

### Post Passes (Reposts)

**File:** `lib/features/posts/application/post_delivery_runner.dart` (`executePostPass`)

Same `_runRecipientFanout` → `_deliverToRecipient` pipeline as regular posts. Same concurrent fan-out (up to 25). Encryption failure IS terminal for post passes — `_RecipientDeliveryBuildException` is thrown.

### Post Comments

**File:** `lib/features/posts/application/send_post_comment_use_case.dart`

Uses the **split form** of outbox delivery: `createLocalPostComment` calls `queuePostEngagementFollowOn` (queue only — persists a `PostFollowOnOutboxEvent`), then `deliverCreatedLocalPostComment` calls `deliverQueuedPostEngagementFollowOn` (deliver only — runs `fanoutPostFollowOnEnvelope`). The two-step split ensures the outbox row survives if the process crashes between queue and deliver. Fan-out to multiple recipients (author + repost participants), up to `defaultPostCommentDeliveryConcurrency = 25` concurrent. No encryption (v1 plain JSON).

### Post Reactions / Post Comment Reactions

**Files:** `lib/features/posts/application/send_post_reaction_use_case.dart`, `lib/features/posts/application/send_post_comment_reaction_use_case.dart`

Uses the **combined form**: `queueAndSendPostEngagementFollowOn` (queue + deliver in one call) → `fanoutPostFollowOnEnvelope`. Durable outbox queue. No encryption. Fan-out to multiple recipients.

### Shared Post Delivery Infrastructure

| Utility | File | Used By |
|---|---|---|
| `ensurePostRecipientDirectConnection` | `post_follow_on_delivery.dart` | Posts, post passes, post comments, post reactions, post comment reactions |
| `fanoutPostFollowOnEnvelope` | `post_follow_on_delivery.dart` | Post comments, post reactions, post comment reactions |
| `PostDeliveryRunner` | `post_delivery_runner.dart` | Posts, post passes |
| `queuePostEngagementFollowOn` + `deliverQueuedPostEngagementFollowOn` | `post_engagement_follow_on_support.dart` | Post comments (split form) |
| `queueAndSendPostEngagementFollowOn` | `post_engagement_follow_on_support.dart` | Post reactions, post comment reactions (combined form) |
| `PostFollowOnOutboxEvent` | outbox model | Post comments, post reactions, post comment reactions (durable retry queue) |

### Voice Messages

**File:** `lib/features/conversation/application/send_voice_message_use_case.dart`

Thin wrapper: uploads audio via bridge, then delegates entirely to `sendChatMessage` with a single audio `MediaAttachment`. No custom routing — the full race strategy runs. Listed in blast radius under "Chat, edit, and voice."

### Share Delivery

**File:** `lib/features/share/application/share_batch_delivery_coordinator.dart`

Orchestrates multi-recipient share delivery. Routes by target type:
- **Contact targets:** Calls `sendChatMessage` (full race strategy). Before the message send, for each media attachment, checks `isLocalPeer` and attempts `sendLocalMedia` — this is a **CDN-bypass shortcut** that transfers file bytes directly to a LAN peer, but it does NOT bypass `sendChatMessage`. The message envelope is always routed via the full race regardless of whether `sendLocalMedia` succeeded.
- **Group targets:** Calls `sendGroupMessage` (full dual-path GossipSub + inbox). No `sendLocalMedia` for groups.

### 1:1 Retry / Recovery Routing

These use cases make routing decisions that differ from the initial send path:

**`retry_failed_messages_use_case.dart`** — Three-tier dispatch for `status: failed` messages:

```
retryFailedMessage(msg)
  |
  +-- wireEnvelope present + transport == 'inbox'?
  |     YES → promote to delivered immediately (no network call, crash-recovery)
  |
  +-- wireEnvelope present?
  |     YES → storeInInbox directly (inbox fast-path, skips race + re-encryption)
  |       +-- Success → status: delivered, transport: inbox, wireEnvelope cleared
  |       +-- Failure (false or exception) → fall through to full send below
  |
  +-- Resolve attachments (re-upload if needed, skip if local file missing)
  +-- sendChatMessage (full race strategy with original messageId/timestamp)
```

The wire-envelope inbox fast-path is the key routing decision: failed messages with a cached `wireEnvelope` attempt inbox delivery first, avoiding re-encryption and the full race. Only if inbox fails does the retrier re-enter `sendChatMessage`.

**`retry_unacked_messages_use_case.dart`** — Inbox-only for `status: sent` messages older than 60s:

```
retryUnackedMessages()
  |
  +-- Skip if wireEnvelope null/empty (defensive guard)
  +-- transport == 'inbox'? → promote to delivered (no network, crash-recovery)
  +-- storeInInbox once
        +-- Success → status: delivered, transport: inbox
        +-- Failure → leave as 'sent', retry on next online transition
```

No `sendChatMessage` call anywhere. Purely inbox-only promotion. No re-encryption, no race, no relay probe.

### Upload Retry Callers

These re-enter the primary routing after completing media re-uploads:

- **`retry_incomplete_uploads_use_case.dart`** — After re-uploading pending 1:1 attachments, calls `sendChatMessage` with the original `messageId`/`timestamp` (full race). Has an abort guard: if the message row was deleted or status changed by a concurrent call, the send is skipped.
- **`retry_incomplete_group_uploads_use_case.dart`** — After re-uploading pending group attachments (via concurrent `Future.wait`), calls `sendGroupMessage` with the original `messageId`/`timestamp` (full dual-path). Accepts both `success` and `successNoPeers` as success outcomes.

---

## 5. Test Coverage Matrix

### 1:1 Send — Decision Branch Coverage

| Decision Branch | Tested? | Test Location |
|---|---|---|
| **Connection reuse: already connected → fast path** | YES | Lines 1275-1311: verifies discover=0, dial=0 |
| **Connection reuse: relay-backed connection preserves transport** | YES | Lines 1313-1348 |
| **Connection reuse: local peer on reuse path** | YES | Lines 1391-1424 |
| **Connection reuse: unacked → inbox handoff** | YES | Lines 1426-1464 |
| **Race: WiFi succeeds** | YES | Lines 959-977 |
| **Race: WiFi fails → direct path used** | YES | Lines 980-1001 |
| **Race: WiFi + direct both would succeed → first wins** | YES | Lines 1466-1487 |
| **Race: slow WiFi doesn't block direct** | YES | Lines 1489-1511 |
| **Relay probe: connected → sends live** | YES | Lines 1110-1135 |
| **Relay probe: connected → send with lost ACK → inbox** | YES | Lines 1220-1248 |
| **Relay probe: noReservation → inbox** | YES | Lines 1164-1191 |
| **Relay probe: error → inbox** | YES | Lines 1193-1218 |
| **Relay probe: not eligible (send_failed) → skip** | NO | Behavior exists in code, but there is no explicit assertion for this branch yet |
| **Inbox fallback: success** | YES | Lines 761-786 |
| **Inbox fallback: failure → status:failed** | YES | Lines 738-759 |
| **All paths fail → inbox tried once** | YES | Lines 1543-1563 |
| **wireEnvelope persisted before transport** | YES | Lines 1592-1737 (4 sub-paths) |
| **Node not running** | YES | Lines 474-490 |
| **Invalid message (empty, whitespace)** | YES | Lines 396-472 |
| **P2P throws exception → sendFailed** | YES | Lines 788-809 |
| **Discover returns null** | YES | Lines 811-830 |
| **Dial returns false** | YES | Lines 832-849 |
| **Inbox fallback edge: storeInInbox throws → failed + wireEnvelope retained** | YES | Lines 1872-1892 |
| **Inbox fallback edge: storeInInbox throws on direct success → no impact** | YES | Lines 1893-1912 |

### Group Send — Decision Branch Coverage

| Decision Branch | Tested? | Test Location |
|---|---|---|
| **Dual-path concurrent execution** | YES | Lines 844-875 (wall-clock timing proof) |
| **Publish OK + peers > 0 + inbox OK** | YES | Lines 1731-1760 |
| **Publish OK + peers > 0 + inbox fail** | YES | Lines 1762-1796 |
| **Publish OK + peers > 0 + inbox in flight** | YES | Lines 1799-1850 |
| **Publish OK + 0 peers + inbox OK → successNoPeers** | YES | Lines 1647-1675 |
| **Publish OK + 0 peers + inbox fail → error** | YES | Lines 1677-1729 |
| **Publish OK + missing topicPeers (legacy) + inbox OK** | YES | Lines 1853-1883 |
| **Publish OK + missing topicPeers + inbox fail** | YES | Lines 1885-1919 |
| **Publish fail + inbox fail → both payloads retained** | YES | Lines 1921-1955 |
| **Publish fail + inbox OK → failed but inboxStored** | YES | Lines 1957-1988 |
| **Publish BRIDGE_TIMEOUT + inbox OK → success** | YES | Lines 1990-2026 |
| **Inbox store ok:false treated as inbox failure** | YES | Lines 2028-2061 |
| **Pre-persist before bridge call** | YES | Lines 1540-1596 |
| **Unauthorized / group not found → no DB row** | YES | Lines 1599-1643 |
| **Exactly one inbox call (no double-call)** | YES | Lines 2062-2088 |
| **Retry re-executes full routing** | YES | retry test lines 258-288 |

### Group Reaction — Decision Branch Coverage

| Decision Branch | Tested? | Test Location |
|---|---|---|
| **Publish success + inbox store staged** | YES | Lines 251-280 |
| **Publish success + inbox store fails → still success** | YES | Lines 282-318 |
| **Publish failure → publishFailed, no inbox** | YES | Lines 223-249 |
| **Non-member rejected** | YES | Lines 165-182 |
| **Announcement member can react** | YES | Lines 104-163 |
| **Unknown messageId rejected** | YES | Lines 185-203 |
| **Unknown group rejected** | YES | Lines 204-222 |

### Retry / Recovery — Coverage

| Decision Branch | Tested? | Test File |
|---|---|---|
| **Retry failed text-only row** | YES | `retry_failed_group_messages_use_case_test.dart` line 258 |
| **Retry zero-peer + inbox-fail row** | YES | same file, line 291 |
| **Retry failed row when inboxRetryPayload cleared** | YES | same file, line 337 |
| **Retry failed media row from persisted attachments** | YES | same file, line 386 |
| **Continues iteration after per-message publish error** | YES | same file, line 635 |
| **Skip rows with upload_pending attachments** | YES | same file, line 513 |
| **Inbox store retry: eligible sent messages** | YES | `retry_failed_group_inbox_stores_use_case_test.dart` |
| **Inbox store retry: eligible pending → promoted to sent** | YES | same file |
| **Inbox store retry: skips already-stored messages** | YES | same file |
| **Inbox store retry: reaction replay outbox rows** | YES | same file |
| **Stuck sending → failed transition** | YES | `recover_stuck_sending_group_messages_use_case_test.dart` |

### Uncovered Branches (Gaps)

| Gap | Risk | Where to Add Test |
|---|---|---|
| `replayEnvelope == null` (no key for inbox) → inbox resolves `false` immediately | Low — inbox just returns false | `send_group_message_use_case_test.dart` |
| Inbox `TimeoutException` caught by `_tryInboxStore` | Low — same catch block as other errors | `send_group_message_use_case_test.dart` |
| Reaction `buildGroupOfflineReplayInboxRetryPayload` throws | Low — outbox silently skipped, saveReaction still runs | `send_group_reaction_use_case_test.dart` |
| Reaction publish fails → verify 0 inbox bridge calls (assertion gap) | Low — test exists but missing explicit 0-call assertion | `send_group_reaction_use_case_test.dart` |
| 1:1 encryption failure (`callEncryptMessage` returns `ok != true` or throws) | Low — returns sendFailed, no inbox | `send_chat_message_use_case_test.dart` |
| Edit validation gate (missing messageId/timestamp/createdAt) | Low — returns invalidMessage | `send_chat_message_use_case_test.dart` |

---

## 6. Transport Labels

After a successful send, the message is tagged with the transport that won:

| Label | Meaning | How Determined |
|---|---|---|
| `local` | WiFi WebSocket | Peer was in mDNS map |
| `direct` | TCP/QUIC to peer | No circuit relay in multiaddr |
| `relay` | Circuit relay through relay server | Multiaddr contains `/p2p-circuit` |
| `inbox` | Store-and-forward at relay | Inbox fallback was used |

For group messages, `GroupMessage` has no `transport` field. Delivery outcome is represented by `status` (`sending`/`pending`/`sent`/`delivered`/`failed`) + `inboxStored` (bool) + `inboxRetryPayload` (nullable). The model represents both live publish and offline replay storage, but the actual inbox bridge call is skipped when no replay envelope is available; these paths are not stored as transport labels.

---

## 7. Blast Radius

### If you change the race strategy:

- Chat, edit, and voice use `sendChatMessage` — affected directly
- Share-to-contact (`share_batch_delivery_coordinator.dart`) calls `sendChatMessage` — affected directly
- `retry_failed_messages_use_case.dart` calls `sendChatMessage` as tier-3 fallback — affected
- `retry_incomplete_uploads_use_case.dart` calls `sendChatMessage` after media re-upload — affected
- Delete has its **own parallel race implementation** in `delete_message_use_case.dart` — imports constants (`interactiveDirectBudget`, `relayProbeSendAttempts`, etc.) from `send_chat_message_use_case.dart`, so constant changes propagate automatically while logic changes must be applied separately. **Known bug:** delete's `.catchError()` aggregator does not scan `relayProbeEligible`
- Introductions have their **own race implementation** in `introduction_outbound_delivery.dart` — imports shared constants from `send_chat_message_use_case.dart`, has correct `_mergeFailures` aggregation (no bug). Constant changes propagate; logic changes must be applied separately
- Contact requests have their **own sequential routing** (WiFi-first → discover-dial-send → inbox) — not race-based, not affected by race changes
- Other 1:1 types (reactions, invites, etc.) use the simpler send-or-inbox path — not affected
- Run: `send_chat_message_use_case_test.dart` AND `delete_message_use_case_test.dart`

### If you change relay probe logic:

- Only affects 1:1 sends that fail discover or dial
- Group messages never use relay probe
- Run: relay probe test group in `send_chat_message_use_case_test.dart` (lines 1047-1248)

### If you change the group dual-path coordination:

- Group messages (`sendGroupMessage`) — primary path
- Share-to-group (`share_batch_delivery_coordinator.dart`) calls `sendGroupMessage` — affected
- `retry_failed_group_messages_use_case.dart` calls `sendGroupMessage` for retry — affected
- `retry_incomplete_group_uploads_use_case.dart` calls `sendGroupMessage` after media re-upload — affected
- Does NOT affect group reactions (different coordination model)
- Run: `send_group_message_use_case_test.dart` WU-3 group (lines 1647-2088)

### If you change group reaction routing:

- Affects both add (`send_group_reaction_use_case.dart`) and remove (`remove_group_reaction_use_case.dart`) — same routing
- Does NOT affect group messages (different coordination model)
- Run: `send_group_reaction_use_case_test.dart`, `remove_group_reaction_use_case_test.dart`

### If you change inbox fallback:

- Affects the message types that actually call inbox storage, but not all of them in the same way
- Key updates have no inbox fallback
- Group reactions only use inbox staging after a successful publish; publish failure is terminal
- `retry_failed_messages_use_case.dart` uses inbox as tier-2 fast-path — affected directly
- `retry_unacked_messages_use_case.dart` is pure inbox-only — affected directly
- Introduction retry (`retryPendingIntroductionDeliveries`) is inbox-only — affected directly
- Profile updates have a two-attempt inbox path with health check between — affected separately
- Run: inbox-related tests across all send use case test files

### If you change post delivery / fan-out:

- Posts and post passes share `PostDeliveryRunner` (`_runRecipientFanout` → `_deliverToRecipient`)
- Post comments, post reactions, post comment reactions share `fanoutPostFollowOnEnvelope` pipeline
- Both groups share `ensurePostRecipientDirectConnection` for discover+dial
- Run: post delivery tests, post follow-on delivery tests

### If you change profile update notification routing:

- Only affects `upload_profile_picture_use_case.dart` — isolated two-attempt inbox path
- Does NOT affect other 1:1 types

### If you change key distribution routing:

- 1:1 distribution: only affects `rotate_and_distribute_group_key_use_case.dart` — no inbox fallback to break
- GossipSub broadcast: the `key_rotated` system message uses `callGroupPublish` — changes to GossipSub publish behavior also affect key rotation

### If you change `callGroupPublish` behavior:

- Group messages (Section 2) — primary send path
- Key rotation — `key_rotated` system broadcast (failure non-fatal)
- Group dissolve (`dissolve_group_use_case.dart`) — `group_dissolved` system message (failure terminal)
- Group creation (`create_group_with_members_use_case.dart`) — `members_added` system message (failure non-fatal)
- Invite acceptance (`accept_pending_group_invite_use_case.dart`) — `member_joined` system message (failure non-fatal)
- Group reactions — uses `callGroupPublishReaction` (separate bridge command, same underlying pubsub)

### If you change contact request routing:

- `send_contact_request_use_case.dart` — primary path
- `retry_incomplete_key_exchanges_use_case.dart` calls `sendContactRequest` for ML-KEM key recovery at startup — also affected
- Does NOT affect other 1:1 types (different routing pattern)

### If you add a new transport path (e.g., Bluetooth):

- Touch: `send_chat_message_use_case.dart` (add to race), `p2p_service.dart` (new method), `p2p_service_impl.dart` (implementation)
- Thread transport label through `SendMessageResult` and `ConversationMessage.transport`
- Add tests for: new path wins race, new path loses race, new path fails → fallback
- Consider: should delete and introduction race implementations also get the new path?
