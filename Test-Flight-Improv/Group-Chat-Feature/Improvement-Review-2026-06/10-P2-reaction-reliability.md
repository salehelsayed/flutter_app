> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P2** · [Findings appendix](./appendix-findings.md)

---

# Make reactions as reliable as messages

**Priority: P2** &nbsp;|&nbsp; **Effort: Medium** &nbsp;|&nbsp; **Type: Reliability / Correctness**

> One-liner: Give reactions offline custody, serialize add/remove with last-writer-wins, and buffer reactions that arrive before their target message.

## Why this matters (user experience)

Group messages in mknoon already have three layers of resilience: optimistic local state, live GossipSub publish, and durable relay-inbox custody with a background retry driver. Reactions look like they have the same layers, but on the failure paths they silently fall back to "drop and forget." The result is **divergent reaction state across members**: an emoji that everyone else sees never appears on your device, or one you tapped never reaches anyone else, with no feedback and no recovery.

Three distinct gaps produce this:

1. **A live-publish failure discards the reaction entirely** — it is reverted in the UI and never staged for offline custody or retry, even though the equivalent message would have been queued.
2. **A reaction that arrives before its target message is permanently dropped** — unlike messages, there is no pending buffer to hold it until the message lands.
3. **Add/remove are processed concurrently and can commit out of order** — a fast toggle (add → remove, or emoji change) can leave a phantom reaction stuck on, or a real one missing.

None of these lose a *message*, so the stakes are lower than message reliability — but reactions are a high-frequency, highly-visible signal, and the inconsistency reads as "this app is flaky." All three fixes reuse infrastructure that already exists for messages.

## Current behaviour & evidence

### Gap 1 — Live-publish failure is a hard drop (no custody, no retry)

`sendGroupReaction` builds the payload, publishes live, and **returns immediately** on any publish failure — *before* the relay-inbox staging step that would make the reaction durable and retryable:

- `lib/features/groups/application/send_group_reaction_use_case.dart:168-175` — returns `SendGroupReactionResult.publishFailed` when `result['ok'] != true`.
- `lib/features/groups/application/send_group_reaction_use_case.dart:176-183` — returns `publishFailed` on a thrown bridge error.
- Both return **before** `_stageReactionInboxStore` (`send_group_reaction_use_case.dart:186`) and `reactionRepo.saveReaction` (`:199`).

The wired layer then reverts the optimistic emoji with no user feedback:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart:4144-4146` — the `else` branch calls `_restoreReactionState`, silently rolling the emoji back.

The **remove path has the identical bug**:

- `lib/features/groups/application/remove_group_reaction_use_case.dart:109-119` — returns `publishFailed` *before* `_stageRemoveReactionInboxStore` (`:122`) and `reactionRepo.removeReaction` (`:134`).

By contrast, the message send path stages relay-inbox custody even at zero peers, and the durable outbox is re-driven by `retryFailedGroupInboxStores`.

> **Scope note (verified):** With GossipSub flood-publish, `topic.Publish()` returns `nil` at zero connected peers (`go-mknoon/node/pubsub.go:736-740`), so the *zero-peers* case generally returns `ok == true` and is already covered. The real gap is the **genuine publish-error / thrown-exception path** (topic not yet joined, transient bridge error), exactly the case that drops the reaction here.

### Gap 2 — Reaction-before-message is silently dropped

GossipSub delivers reactions and messages on **separate streams**, so a reaction can arrive before (or racing) the message it targets. When the target message is not yet persisted, the handler returns `unknownMessage` and the reaction is discarded forever:

- `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart:134-148` — returns `HandleGroupReactionResult.unknownMessage` when `msgRepo.getMessage(payload.messageId) == null`.
- `lib/features/groups/application/group_message_listener.dart:3979-4012` — `_handleReaction` only emits a `ReactionChange` on `result == success` (emit at `:4010`), so `unknownMessage` is dropped with no buffering.

There is **no pending-reaction buffer**. Messages have one (`_shouldBufferMembershipDependentMessage` / `_bufferMembershipDependentMessage`, `group_message_listener.dart:1026-1209`, with durable backing in `group_pending_membership_messages`), but a grep for any `pendingReaction` / `bufferReaction` analogue finds nothing.

Critically, the reaction has **already passed all its own validation** by this point — sender membership, sender/payload binding, and device-binding are checked at `handle_incoming_group_reaction_use_case.dart:88-131`, *independent of the message's existence*. So the reaction is known-good; it is dropped only for a transient ordering reason.

### Gap 3 — Concurrent add/remove can commit out of order

Live **messages** are serialized — each handler is awaited before the next runs:

- `lib/features/groups/application/group_message_listener.dart:251` — `incomingGroupMessages.asyncMap(_handleLiveMessage)`.

**Reactions are not.** They use a plain `listen` callback that fires the handler without awaiting it:

- `group_message_listener.dart:271` — `incomingGroupReactions.listen(_handleLiveReaction)`.
- `group_message_listener.dart:335-336` — `_handleLiveReaction` calls `_trackInFlight(_handleReaction(data))` and **does not return or await** the future. `Stream.listen` never awaits an async callback, so multiple `_handleReaction` invocations interleave across their `await` points (`getMember`, `getMessage`, `removeReaction` / `saveReaction`).

There is also **no last-writer-wins guard**. The payload timestamp is parsed but used *only* for the dissolve check, never for ordering:

- `handle_incoming_group_reaction_use_case.dart:71-74` — `reactionTimestamp` parsed and compared to `dissolvedAt` only.
- `lib/features/conversation/domain/repositories/reaction_repository_impl.dart:27-85` — `saveReaction` is an unconditional insert/upsert; `removeReaction` is a plain delete-by-`(messageId, senderPeerId)`. Neither compares timestamps.

So two in-flight handlers for the same `(messageId, senderPeerId)` race, and whichever write *lands last* wins regardless of which event is *newer*.

> **Severity nuance (verified):** Both add and remove for a toggle originate from one ordered Go stream, so the second handler only *starts* after the first's synchronous prefix, and sqflite serializes the individual writes — this narrows but does not eliminate the interleave window (the gap is between `getMessage`/`getMember` and the final write). Practical severity is moderate, but it is a real correctness bug and is cheap to close.

## Root cause(s)

| # | Root cause | Mechanism |
|---|-----------|-----------|
| 1 | Reaction send treats live publish as the *gate* for custody, instead of staging custody unconditionally | `return publishFailed` executes before the staging + local-persist steps in both send and remove use cases |
| 2 | No pending-reaction buffer; the message-existence check is terminal | `unknownMessage` returns instead of holding the (already-validated) reaction until the message lands |
| 3 | Reaction handling is fire-and-forget and order-blind | `listen(_handleLiveReaction)` instead of `asyncMap`; no per-`(messageId, senderPeerId)` serialization; timestamp not used for ordering |

## Proposed improvements

### Improvement 1 — Stage custody before/independent of live publish (mirror the message path)

In **`send_group_reaction_use_case.dart`** and **`remove_group_reaction_use_case.dart`**, restructure so the durable replay-outbox entry and local optimistic state are committed **regardless of live-publish outcome**, and treat publish failure as *queued-with-retry* rather than a hard drop.

Concretely, reorder to: build payload → **stage replay-outbox entry** (`_stageReactionInboxStore` / `_stageRemoveReactionInboxStore`) → **persist local optimistic state** (`reactionRepo.saveReaction` / `removeReaction`) → attempt live publish. Then:

- If live publish succeeds → return `success` (as today).
- If live publish fails or throws → the reaction is **already durable** in `group_reaction_replay_outbox` with `deliveryStatus = pending`. Return a new outcome `queuedForRetry` (or keep `success` semantics — the local state is correct and the durable row exists) instead of `publishFailed`.

This makes `retryFailedGroupInboxStores` (`lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart:108-175`) automatically re-drive the reaction — it already drains retryable reaction rows after message rows, calling `storeGroupOfflineReplayFromRetryPayload` and marking them `stored`. No change to the retry driver is required; we just need the row to exist on the failure path.

**Wired-layer change (`group_conversation_wired.dart:4144-4146`):** stop reverting the optimistic emoji on a queued-with-retry outcome. Keep the emoji shown (it is durable and will be retried). Only revert on hard validation failures (`groupNotFound`, `notMember`, `unauthorizedSenderKey`, `messageNotFound`) and on `groupDissolved` (existing behaviour). Optionally surface a subtle "will deliver when reconnected" affordance, consistent with how messages indicate pending delivery.

**Caveat to handle (decided design point):** today the live publish is the *first* side effect, so staging-after-publish means a publish failure leaves nothing. Moving staging *first* means a duplicate live publish on a later retry is possible. This is safe because reaction IDs are **deterministic** — `_deterministicAddReactionId` (`send_group_reaction_use_case.dart:217-232`) and the remove-id helper derive the ID from `(action, emoji, groupId, messageId, senderPeerId)`, and receivers upsert/delete by `(messageId, senderPeerId)`. A reaction delivered twice is idempotent. No new dedup logic needed.

*No new wire format, DB table, or migration for this improvement* — it reuses `group_reaction_replay_outbox` (migration 054) and the existing retry driver.

### Improvement 2 — Buffer reactions whose target message has not yet arrived

Add a bounded, TTL'd pending-reaction buffer in `group_message_listener.dart`, modeled directly on the membership-dependent message buffer (`_pendingMembershipDependentMessagesByGroup`, `group_message_listener.dart:124-125, 1026-1209`).

**Receive-side change (`handle_incoming_group_reaction_use_case.dart`):** when `msgRepo != null` and the target message is absent (`:134-148`), do **not** return a terminal `unknownMessage`. Instead, return a distinct outcome — e.g. `HandleGroupReactionResult.bufferedPendingMessage` — *after* all sender/membership/device validation has passed (validation already happens at `:88-131`, before the message check, so the reaction is known-good). This keeps the "validate-then-act" ordering intact.

**Listener-side change (`group_message_listener.dart`):**

1. On `bufferedPendingMessage`, enqueue the raw reaction `data` into an in-memory map keyed by `(groupId, messageId)`, capped per group (reuse the `_maxPending… = 50` cap pattern) with an oldest-first eviction and a TTL (e.g. 10 minutes), de-duping by reaction ID so a re-delivered reaction does not stack.
2. **Flush hook:** in `_handleMessage`, immediately after `handleIncomingGroupMessage` returns a non-null `result` and `_emitGroupMessage(result)` fires (`group_message_listener.dart:811-833`), look up any buffered reactions keyed by `result.id` and re-run them through `handleIncomingGroupReaction` (now with the message present), emitting each resulting `ReactionChange`. This is the exact analogue of how membership-dependent messages flush when membership lands (`_flushMembershipDependentMessages`).

**Durability (optional, recommended for parity):** back the buffer with a small table `group_pending_reactions` (new migration `078_group_pending_reactions`) mirroring `group_pending_membership_messages` (migration 072) — columns `(id PK, group_id, message_id, sender_peer_id, reaction_json, received_at, created_at, updated_at)` with an index on `(group_id, message_id)` and a unique index on reaction ID. Flush durable rows on the same hook and at startup, matching `_flushStartupDurableMembershipDependentMessages` (`group_message_listener.dart:1340`). If a lighter touch is preferred for the first cut, ship the **in-memory** buffer only (TTL-bounded), accepting that a reaction buffered across an app kill before its message arrives is lost — this is still strictly better than today's unconditional drop.

> **Minimum-viable alternative** (if buffering is descoped): persist the reaction optimistically even when the message is absent (it is independently validated) and let the UI render it once the message lands. The buffer is cleaner because it avoids orphan reaction rows referencing a `message_id` that never arrives, but either approach removes the silent drop.

### Improvement 3 — Serialize reaction handling and add last-writer-wins

**Serialize (`group_message_listener.dart`):** route reactions through the same back-pressured pipeline as messages, or serialize per key.

- *Option A (simplest, matches messages):* change `incomingGroupReactions.listen(_handleLiveReaction)` (`:271`) to `incomingGroupReactions.asyncMap(_handleLiveReaction).listen(...)`, and make `_handleLiveReaction` (`:335-336`) **return** the future it currently fires-and-forgets. This serializes *all* reactions globally, exactly like messages, eliminating cross-reaction interleave.
- *Option B (finer-grained):* reuse the existing per-group serialization primitive `_enqueueGroupConfigWork(groupId, work)` (`group_message_listener.dart:4022`) to serialize per `(groupId)` or per `(messageId, senderPeerId)`, allowing parallelism across unrelated groups. Option B is preferable if reaction throughput in large groups is a concern; Option A is the lowest-risk change.

**Last-writer-wins (`handle_incoming_group_reaction_use_case.dart` + reaction repo):** make the apply step honor the payload timestamp so a stale add cannot overwrite a newer remove (or vice-versa) regardless of arrival/commit order.

- Add a `lastWriteAt` (or reuse `timestamp`) comparison in the apply path (`handle_incoming_group_reaction_use_case.dart:168-194`): before `saveReaction` / `removeReaction`, read the current stored reaction for `(messageId, senderPeerId)` and **skip the write if the incoming `reactionTimestamp` is not strictly newer** than the stored one.
- To make this robust against remove-then-stale-add, removes must leave a tombstone timestamp rather than a bare row deletion — otherwise a remove deletes the row and a later (older) add finds nothing to compare against and re-inserts. Two viable approaches:
  - **Tombstone column:** add `removed_at TEXT` to `message_reactions` (new migration `079_message_reaction_tombstone`), keep the row on remove, and treat a row with `removed_at` newer than an incoming add's timestamp as "remove wins." Requires read-path filtering (`getReactionsForMessage` excludes tombstoned rows) and periodic pruning.
  - **Timestamp guard without tombstone (lighter):** push the timestamp comparison into the repo so `saveReaction`/`removeReaction` are conditional on `incoming.timestamp > existing.timestamp`. This closes the common toggle race within a session but cannot defend against a remove whose row no longer exists; acceptable given reactions are low-stakes and Improvement 1+3-serialization already shrink the window dramatically.

  Recommend the **timestamp-guard-in-repo** approach for the first cut (no schema change, no migration), and reserve the tombstone migration for a follow-up if cross-member divergence is still observed in device testing.

> **Wire-format note:** `GroupReactionPayload` already carries `timestamp` and it already round-trips over the wire (`message_reaction.dart` / `group_reaction_payload.dart`), so last-writer-wins needs **no new wire field** — only that senders set it to a monotonic send time (they already do: `DateTime.now().toUtc()` at `send_group_reaction_use_case.dart:142`).

## Affected files & components

| File | Change |
|------|--------|
| `lib/features/groups/application/send_group_reaction_use_case.dart` | Reorder: stage outbox + persist local **before** live publish; return `queuedForRetry` instead of `publishFailed` on publish failure (Imp. 1) |
| `lib/features/groups/application/remove_group_reaction_use_case.dart` | Same reorder for the remove path (Imp. 1) |
| `lib/features/groups/presentation/screens/group_conversation_wired.dart` | Stop reverting optimistic emoji on queued-with-retry; keep showing it (`:4144-4146`) (Imp. 1) |
| `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart` | Return `bufferedPendingMessage` instead of terminal `unknownMessage` (`:134-148`); add timestamp-based last-writer-wins guard around `:168-194` (Imp. 2, 3) |
| `lib/features/groups/application/group_message_listener.dart` | Add pending-reaction buffer + flush hook in `_handleMessage` after `_emitGroupMessage` (`:811-833`); switch reactions to `asyncMap` / `_enqueueGroupConfigWork` and await them (`:271, 335-336`) (Imp. 2, 3) |
| `lib/features/conversation/domain/repositories/reaction_repository_impl.dart` (+ interface, + db helpers) | Add timestamp-guarded conditional save/remove (Imp. 3) |
| `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart` | **No change** — already drains reaction outbox rows (`:108-175`); benefits automatically once rows exist on the failure path |
| *New (optional)* `lib/core/database/migrations/078_group_pending_reactions.dart` + helpers + repo | Durable pending-reaction buffer, mirroring migration 072 (Imp. 2, optional) |
| *New (optional, follow-up)* `lib/core/database/migrations/079_message_reaction_tombstone.dart` | `removed_at` tombstone column for full remove-then-stale-add defense (Imp. 3, optional) |

**Components touched:** group reaction send/remove use cases, group message listener (receive pipeline), reaction repository + DB layer, group conversation wired UI, lifecycle/resume retry wiring (no change needed — already wired in `main.dart:2015, 3179` and `handle_app_resumed.dart:512`).

## Test & verification strategy

### Unit tests (extend existing suites)

- `test/features/groups/application/send_group_reaction_use_case_test.dart` — assert that on `result['ok'] != true` **and** on a thrown bridge error, the replay-outbox `saveEntry` is still called and the local reaction is persisted; assert the new `queuedForRetry` outcome.
- `test/features/groups/application/remove_group_reaction_use_case_test.dart` — same assertions for the remove path.
- `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart` — (a) reaction with absent target message returns `bufferedPendingMessage` (not `unknownMessage`); (b) a stale add (older timestamp) does **not** overwrite a newer remove and vice-versa (last-writer-wins).
- New listener test (e.g. `group_message_listener_reaction_buffer_test.dart`) — buffer a reaction, then deliver its message, assert the buffered `ReactionChange` is emitted exactly once; assert cap eviction and TTL expiry; assert two interleaved add/remove handlers commit in timestamp order under the serialized pipeline.
- `test/features/conversation/domain/repositories/reaction_repository_impl_test.dart` — timestamp-guarded conditional save/remove.
- If durable buffer is built: new migration test `test/core/database/migrations/078_group_pending_reactions_test.dart` mirroring `054_…test.dart` and `016_…test.dart`, plus helper tests.

### Integration harness

- `test/features/groups/integration/group_reaction_roundtrip_test.dart` and `test/features/conversation/integration/emoji_reaction_exchange_test.dart` — extend with: (1) publish-failure injection → reaction survives in outbox and is re-driven by `retryFailedGroupInboxStores`; (2) reaction-before-message ordering on the `FakeGroupPubSubNetwork` → buffered reaction appears after the message arrives; (3) rapid add/remove toggle → final state is consistent across two `GroupTestUser`s.
- `integration_test/group_recovery_e2e_test.dart` / `group_recovery_cli_e2e_test.dart` — add a reaction-recovery leg: send reaction while peer offline, confirm it lands via relay custody on reconnect (currently message-only).

### Device matrix & Test-Flight gates

- Add a reaction row to the relevant matrices under `Test-Flight-Improv/` (e.g. the group-chat test inventory and `test-gate-definitions.md`): "reaction sent during transient publish failure is delivered after retry," "reaction received before message becomes visible when message lands," and "rapid toggle converges across members."
- Real-device leg (two-device, same matrix used for NET-REL work): toggle reactions rapidly on device A while device B observes; force device B's topic-not-yet-joined window to exercise the publish-failure custody path. Greppable FLOW events already exist (`GROUP_REACTION_SEND_*`, `RETRY_FAILED_GROUP_REACTION_REPLAY_OK/ERROR`); add `GROUP_REACTION_BUFFERED` / `GROUP_REACTION_BUFFER_FLUSHED` for buffer observability.

## Risks, trade-offs & rollout

| Risk / trade-off | Mitigation |
|------------------|-----------|
| Staging-before-publish enables a duplicate live publish on retry | Safe: reaction IDs are deterministic and receivers upsert/delete by `(messageId, senderPeerId)` — re-delivery is idempotent (`send_group_reaction_use_case.dart:217-232`) |
| Keeping the optimistic emoji on publish failure could show an emoji that ultimately never delivers (e.g. permanent failure) | Bounded retry already governs the outbox; reactions are low-stakes; optionally show a subtle pending affordance. Strictly better than the current silent revert which is *guaranteed* divergence |
| Pending-reaction buffer growth / memory | Per-group cap (reuse 50) + TTL + oldest-first eviction, mirroring membership buffer; durable variant prunes like migration 072 |
| Serializing all reactions (Option A) could add latency in very high-throughput groups | Use per-group `_enqueueGroupConfigWork` (Option B) if measured; messages already accept this trade-off |
| Last-writer-wins without a tombstone can't defend remove-then-stale-add | Documented; ship repo timestamp-guard first, add `079` tombstone migration only if device testing shows residual divergence |
| New migrations (078 / 079) are additive | Both are `CREATE TABLE/INDEX IF NOT EXISTS` / `ADD COLUMN` and idempotent, matching established migration patterns; no backfill needed |

**Rollout:** Improvements 1 and 3-serialization are low-risk, self-contained, and reuse existing infrastructure — ship first. Improvement 2 (in-memory buffer) next. The durable buffer (078) and tombstone (079) are optional follow-ups gated on device-matrix observations. No feature flag is strictly required, but the buffer and last-writer-wins can be guarded by the existing group-recovery enablement flag (`groupRecoveryEnabled`, `pending_message_retrier.dart:469`) if a staged rollout is desired.

## Effort estimate

| Workstream | Estimate |
|-----------|----------|
| Imp. 1 — custody-before-publish (send + remove + wired) | ~0.5 day |
| Imp. 3 — serialize reactions + repo timestamp-guard | ~0.5–1 day |
| Imp. 2 — in-memory pending-reaction buffer + flush hook | ~1 day |
| Imp. 2 — durable buffer (migration 078 + helpers + repo + startup flush) *(optional)* | +1 day |
| Imp. 3 — tombstone migration 079 *(optional follow-up)* | +0.5 day |
| Unit + integration tests across all of the above | ~1–1.5 days |
| Device-matrix verification | ~0.5 day |

**Core (Imp. 1 + 3 + in-memory Imp. 2 + tests): ~3–4 days. Full (with durable buffer + tombstone): ~5 days.** Matches the "medium effort; the offline-custody fallback is small" framing — Improvement 1 is the small, high-value fix; Improvements 2 and 3 are the medium-effort correctness work that fully closes reaction divergence.
