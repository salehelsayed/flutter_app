> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P2** · Source finding: [`10-P2-reaction-reliability.md`](./10-P2-reaction-reliability.md)

---

# TDD Plan — Make group reactions as reliable as messages

**Status: PLAN ONLY.** Decomposed for TDD execution. Verified against HEAD `124-harness-refactor` (commit `41061593`) by a 10-agent verification workflow (3 graph-first recon → 3 adversarial refute → 3 cross-cut → synthesis) on 2026-06-16.

---

## 0. Resolution verification — is the finding still open?

**Verdict: ALL THREE gaps are confirmed UNRESOLVED and UNMITIGATED on HEAD.** Every load-bearing source citation in the source finding was verified exact; only benign line drift was found (already accounted for below with current line numbers). The group-reaction code is genuinely untouched: `send_group_reaction_use_case.dart`, `remove_group_reaction_use_case.dart`, `handle_incoming_group_reaction_use_case.dart`, and `group_reaction_payload.dart` were last modified by `e7a840e5` (2026-05-25); the only post-`e7a840e5` edit anywhere near the reaction code was 124 (`576dc41e`) wrapping `_handleLiveReaction` in a benign `_allowsInboundAccountSideEffects` gate — it added **no** custody, buffering, or serialization.

**Ownership boundary (not a duplicate of other planned work):**
- **125 (1:1 reliability)** is disjoint: its "F7-reactions" targets the *1:1 direct/relay* path (`p2p_service_impl.dart`, Go `node.go` `shouldDeferDirectAck`, `handle_incoming_reaction_use_case.dart`) — a different transport and different files. It never touches `send_group_reaction_use_case` / `handle_incoming_group_reaction_use_case` / the group GossipSub path.
- **Undecryptable self-heal (02)** is about group key-repair for undecryptable *messages*; it owns no reaction gap.
- **Posts reactions are already shipped** and out of scope. (Note: a `queuedForRetry` enum value already exists in `send_post_reaction_use_case.dart` — a *separate* enum; no compile clash, but do not conflate.)

| Gap | Claim | HEAD status | Strongest proof (current line numbers) |
|-----|-------|-------------|----------------------------------------|
| **1** | Live-publish failure is a hard drop (no custody, no retry) | **UNRESOLVED** (most severe) | `send_group_reaction_use_case.dart:174` returns `(publishFailed, null)` on `result['ok']!=true` and `:182` on a thrown bridge error — both *inside* the publish try-block (`:154-183`), strictly **before** `_stageReactionInboxStore` (`:186`, whose only durable write is `reactionReplayOutboxRepo.saveEntry` at `:285`) and `reactionRepo.saveReaction` (`:199`). Remove path mirrors it: `remove_group_reaction_use_case.dart:110/:118` before `_stageRemoveReactionInboxStore` (`:122`) and `reactionRepo.removeReaction` (`:134`). Wired layer silently reverts: `group_conversation_wired.dart:~4548` (send else) / `~4491` (remove else) → `_restoreReactionState` (`~4552-4560`) is a pure `setState` revert — no persist, no outbox, no retry, no SnackBar. |
| **2** | Reaction-before-message is silently dropped (no buffer) | **UNRESOLVED** (moderate) | `handle_incoming_group_reaction_use_case.dart:136-148` returns terminal `unknownMessage` when `msgRepo.getMessage(payload.messageId)==null` — **after** all sender/membership/device validation (`:61-131`), so the reaction is known-good. `group_message_listener.dart:~4220` emits `ReactionChange` only on `success`. **Second drop site the source finding missed:** the offline-drain path `drain_group_offline_inbox_use_case.dart:533-554` also calls `handleIncomingGroupReaction`, discards the result, and `return`s. No `group_pending_reactions` table or buffer exists. |
| **3** | Concurrent add/remove can commit out of order (no serialize, no LWW) | **UNRESOLVED** (narrowest) | Messages: `group_message_listener.dart:280-281` `incomingGroupMessages.asyncMap(_handleLiveMessage)` (serialized). Reactions: `:301` `incomingGroupReactions.listen(_handleLiveReaction)`; `_handleLiveReaction` (`:371-381`) fires `_handleReaction(data)` via tracking-only `_trackInFlight` **without returning/awaiting**. No LWW anywhere: `reactionTimestamp` (`handle_incoming_group_reaction_use_case.dart:71-74`) is consumed **only** by the dissolve gate; the apply at `:168-194` is an unconditional `saveReaction`/`removeReaction`; the repo (`reaction_repository_impl.dart:28-85`) and DB helpers (`reactions_db_helpers.dart`, `ConflictAlgorithm.replace` + plain `WHERE` delete) carry no timestamp predicate. |

**Load-bearing claim "Improvement 1 needs no retry-driver change" — HOLDS, with one critical reframing.** The retry driver (`retry_failed_group_inbox_stores_use_case.dart:108-175`) already queries `group_reaction_replay_outbox` (`loadRetryableEntries` → `dbLoadRetryableGroupReactionReplayOutboxEntries`, `WHERE delivery_status IN ('pending','failed')`), re-drives via `storeGroupOfflineReplayFromRetryPayload`, marks rows `stored`, and is wired in production on every retrier tick (`pending_message_retrier.dart:416`, `main.dart:2294-2302`) and every app resume (`handle_app_resumed.dart:606`, `main.dart:3595-3599`). **But** the *only* writer of those rows (`_stageReactionInboxStore`, `send_group_reaction_use_case.dart:186`) runs only **after** publish succeeds. So on a true publish failure no row exists and the driver finds nothing. **The consumer is complete; the producer is missing.** Gap 1's fix is purely producer-side. (Secondary note verified: reactions share the message-row `limit` budget — `remainingReactionSlots = limit - messages.length`, `:56` — so reactions are skipped on a tick when ≥20 message rows are backlogged. Bounds throughput; not a correctness bug.)

---

## 1. Critical assessment & scoping decision

The source finding is accurate and well-scoped. Two corrections / additions from verification:

1. **Gap 2 has a second drop site** — the offline-drain path. Any buffer fix must cover **both** the live listener and `drain_group_offline_inbox_use_case`, or relay-delivered (store-and-forward) reactions that arrive before their message will still be dropped. The cleanest way to cover both for free is to do the buffering **inside the use case** (durable-table write) rather than only in the listener (see OQ-1).
2. **Gap 3's tombstone touches a shared table.** There is **no** group-only reaction table — both 1:1 and group reactions persist in the single `message_reactions` table (migration `016`) via the shared `ReactionRepository`. A `removed_at` tombstone (the source finding's optional `079`) would convert 3 hard-delete helpers in `reactions_db_helpers.dart` to soft-delete, add `removed_at IS NULL` filters to all loaders, and require clearing the tombstone on re-add (`ConflictAlgorithm.replace` keyed on `UNIQUE(message_id, sender_peer_id)`). That is a 1:1 + group blast radius. **Defer it** (Phase 5, optional follow-up) and ship the repo timestamp-guard first.

### Migration numbering — allocate at landing time, do NOT hard-code

HEAD ceiling is **v77** (`app_database_version.dart:1`; highest file `077_message_relay_custody.dart`; `onUpgrade` tail `if (oldVersion < 77)`). The source finding proposed `078`/`079`, but **078 is already contended by at least three other PLAN-ONLY docs** (undecryptable self-heal `078_group_pending_key_repairs_status_index`; 03-removal-rotation Slice-2; 09-media). **Do not bind this plan to a specific integer.** The only migration this plan needs (Phase 4's buffer table; Phase 5's optional tombstone) must take the **next free integer at landing time** (call them `N` and `N+1`). Whichever plan lands first wins its number; second-to-land rebases. The shared chokepoint tests `full_migration_chain_test.dart` and `migration_database_schema_inventory_test.dart` must be reconciled in lockstep with whatever has already landed.

### In scope

- **Phase 1 (Gap 1)** — producer-side durable custody + pre-persist on publish failure, for send and remove; new `queuedForRetry` outcome; wired layer stops the silent revert. **No migration.**
- **Phase 2 (Gap 3a)** — serialize the live reaction path (mirror messages' `asyncMap`). **No migration.**
- **Phase 3 (Gap 3b)** — repo-level last-writer-wins timestamp guard (shared repo; covers 1:1 + group). **No migration.**
- **Phase 4 (Gap 2)** — durable pending-reaction buffer + flush on message arrival, covering listener + offline-drain + startup. **Migration `N`.**
- **Phase 5 (Gap 3c, OPTIONAL / DEFERRED)** — `removed_at` tombstone on `message_reactions` for full remove-then-stale-add defense. **Migration `N+1`.** Gated on device-matrix evidence of residual divergence.

### Out of scope

Post reactions (already shipped); the 1:1 direct-reaction ack-before-commit work (owned by 125); any wire-format change (`GroupReactionPayload.timestamp` already round-trips — `group_reaction_payload.dart` — so LWW needs no new wire field).

---

## 2. Invariants (the contract the tests lock)

- **INV-R1 (custody):** A group reaction add/remove whose live publish returns `ok != true` or throws MUST leave (a) a durable `group_reaction_replay_outbox` row in `pending`/`failed`, and (b) locally-persisted optimistic reaction state. It MUST NOT silently revert the UI.
- **INV-R2 (retry, no driver change):** Such rows are re-driven by the existing retry driver with **zero** change to `retry_failed_group_inbox_stores_use_case` or its wiring. The plan adds only the producer row.
- **INV-R3 (idempotent re-delivery):** Re-staging/re-publishing a reaction is idempotent — sender side via the deterministic `reaction_id` PK (`_deterministicAddReactionId`, `send_group_reaction_use_case.dart:217-231`, and the remove-id helper), receiver side via `UNIQUE(message_id, sender_peer_id)` upsert/delete.
- **INV-R4 (buffer, both paths):** A fully-validated reaction whose target message is absent MUST be retained and replayed when the message lands — on **both** the live-listener path and the offline-drain path — instead of a terminal `unknownMessage` drop.
- **INV-R5 (buffer bounds):** The buffer is per-group capped (reuse the `50` cap pattern), TTL'd, deduped by `reaction_id`, evicted oldest-first; each flushed reaction emits its `ReactionChange` **exactly once**.
- **INV-R6 (serialize):** Live reaction handling is serialized like messages — no two `_handleReaction` invocations overlap across their `await` points; the handler future is awaited.
- **INV-R7 (LWW):** For a given `(message_id, sender_peer_id)`, an event with an older `timestamp` MUST NOT overwrite the effect of a newer one (within the limits of Phase 3 vs Phase 5 — see Risks).
- **INV-R8 (no regression):** 1:1 reaction behavior (shared `ReactionRepository` + shared `message_reactions` table) is preserved; existing group / 1:1 / posts reaction suites stay green.

---

## 3. Phases

Each phase is **test-first**: write the RED tests, watch them fail, implement to GREEN, then run the phase gate. Sequence is by ascending risk and migration cost; Phases 1–3 ship together as the low-risk core.

### Phase 0 (prep) — fakes & seam audit

No production change. Confirm the test seams exist and decide the durable-buffer fake.

- `test/shared/fakes/fake_group_reaction_replay_outbox_repository.dart` already exists — confirm it records `saveEntry`/`updateEntryStatus`/`loadRetryableEntries` so Phase 1 can assert the producer row.
- `test/features/conversation/domain/repositories/fake_reaction_repository.dart` exists — confirm it records `saveReaction`/`removeReaction` and (Phase 3) can model a stored timestamp.
- If Phase 4 builds the durable table: create `FakeGroupPendingReactionRepository` mirroring the membership-message fake, and extend `GroupTestUser` / `FakeGroupPubSubNetwork` plumbing.

**Gate:** `flutter analyze` clean; no behavior change.

---

### Phase 1 — Gap 1: custody-before-publish (send + remove + wired). NO MIGRATION. *Ship first.*

**RED tests**

`test/features/groups/application/send_group_reaction_use_case_test.dart`:
- On `result['ok'] != true`: assert `reactionReplayOutboxRepo.saveEntry` **was** called with a `pending`/`failed` row, `reactionRepo.saveReaction` **was** called (optimistic persist), and the result is the new `SendGroupReactionResult.queuedForRetry` (with a non-null returned `MessageReaction`).
- On a thrown bridge error in the publish call: same assertions.
- On `ok == true`: unchanged — returns `success` with the confirmed reaction, exactly one outbox row, one `saveReaction`.
- Idempotency (INV-R3): two staged attempts for the same add produce one outbox row (deterministic `reaction_id` PK).

`test/features/groups/application/remove_group_reaction_use_case_test.dart`:
- Same matrix for the remove path: publish-fail / throw → outbox row staged + local `removeReaction` applied + `RemoveGroupReactionResult.queuedForRetry`.
- Remove re-staging idempotency (verify the remove-reaction id is deterministic; if not, that is a sub-bug to fix here so repeated removes don't create distinct rows).

`group_conversation_wired` widget test (extend the existing reaction widget tests):
- On `queuedForRetry`, the optimistic emoji is **kept** (temp swapped for the persisted `MessageReaction`, not reverted via `_restoreReactionState`).
- On `groupNotFound` / `notMember` / `unauthorizedSenderKey` / `messageNotFound` and on a thrown exception → still revert (unchanged).
- On `groupDissolved` → `_restoreReactionStateAfterDissolve` (unchanged).

**GREEN implementation**

1. `send_group_reaction_use_case.dart`: reorder so the durable + local steps run regardless of publish outcome. Concretely: build payload → `_stageReactionInboxStore` (writes the `pending` outbox row) → `reactionRepo.saveReaction` (optimistic local) → attempt publish. On publish `ok` → `success`; on `ok != true` or throw → `queuedForRetry` (the row already exists; the existing retry driver will re-drive it). Add `queuedForRetry` to `SendGroupReactionResult` and return the persisted `MessageReaction` alongside it.
2. `remove_group_reaction_use_case.dart`: identical reorder; add `RemoveGroupReactionResult.queuedForRetry`.
3. `group_conversation_wired.dart`: in `_onReactionSelected` send/remove branches, treat `queuedForRetry` like `success` for UI retention (swap temp→persisted on send; no-op keep on remove). Optionally surface a subtle "will deliver when reconnected" affordance (not required for closure).

**Caveat handled (INV-R3):** staging-before-publish enables a duplicate live publish on a later retry — safe because reaction IDs are deterministic and receivers upsert/delete by `(message_id, sender_peer_id)`.

**Gate:** the two use-case suites + the wired reaction widget tests green; `flutter analyze` clean; **mutation check** — revert the reorder and confirm the new RED tests fail. Confirm the existing retry-driver suite (`retry_failed_group_inbox_stores` tests) still passes unchanged (INV-R2).

---

### Phase 2 — Gap 3a: serialize the live reaction path. NO MIGRATION.

**RED test** — new `test/features/groups/application/group_message_listener_reaction_serialize_test.dart`: feed two reactions for the same `(messageId, senderPeerId)` back-to-back on the reaction stream where the first handler's async prefix is slow; assert they are applied in arrival order (no interleave) and the handler future is awaited (e.g. a completion signal fires only after the second is applied).

**GREEN** — in `group_message_listener.dart`, change `incomingGroupReactions.listen(_handleLiveReaction)` (`:301`) to `incomingGroupReactions.asyncMap(_handleLiveReaction).listen(...)`, and make `_handleLiveReaction` (`:371-381`) **return** the future it currently fires via `_trackInFlight`. (Option A from the source finding — global serialization mirroring messages at `:280-281`; lowest risk. Option B per-`(groupId)` via `_enqueueGroupConfigWork` only if throughput in large groups is later measured to matter.)

**Gate:** new test green; existing listener suite green; `flutter analyze` clean; mutation check (restore `.listen` → test fails).

---

### Phase 3 — Gap 3b: repo last-writer-wins timestamp guard. NO MIGRATION. *(shared repo — covers 1:1 + group)*

**RED tests**

`test/features/conversation/domain/repositories/reaction_repository_impl_test.dart` and `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`:
- A stale add (older `timestamp`) does **not** overwrite a newer stored reaction.
- A newer add **does** overwrite an older stored reaction.
- A remove with a timestamp older than the stored add is a no-op (within Phase-3 limits); a newer remove deletes.
- 1:1 path unaffected: existing `send_reaction_use_case` / `handle_incoming_reaction_use_case` / `reaction_repository_impl` tests stay green (INV-R8).

**GREEN** — push the timestamp comparison into the repo / DB-helper layer so `saveReaction`/`removeReaction` are conditional on `incoming.timestamp > existing.timestamp` for the same `(message_id, sender_peer_id)`. Wire the apply step (`handle_incoming_group_reaction_use_case.dart:168-194`) to honor it. No schema change.

**Known limitation (documented, see Phase 5):** without a tombstone, a remove deletes the row, so a later *older* add finds nothing to compare against and re-inserts (remove-then-stale-add). Phases 1+2 already shrink this window dramatically; the residual is low-stakes. Phase 5 closes it fully if device testing shows divergence.

**Gate:** repo + handle suites green; **1:1 reaction suites green (regression guard)**; `flutter analyze` clean; mutation check.

---

### Phase 4 — Gap 2: durable pending-reaction buffer + flush. MIGRATION `N` (next-free-at-landing). *(both listener + offline-drain + startup)*

**RED tests**

`test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`:
- Reaction with an absent target message, after passing all validation, returns the new `HandleGroupReactionResult.bufferedPendingMessage` (not `unknownMessage`) and the reaction is recorded in the buffer.

New `test/features/groups/application/group_message_listener_reaction_buffer_test.dart`:
- Buffer a reaction, then deliver its target message → the buffered `ReactionChange` is emitted **exactly once** (INV-R5) and the buffer entry is cleared.
- Cap eviction (per-group cap, oldest-first) and TTL expiry.
- Dedup by `reaction_id` (re-delivered buffered reaction does not stack).

Offline-drain coverage (extend `drain_group_offline_inbox_use_case` tests): a relay-delivered reaction whose message is absent is buffered (not dropped at `:533-554`), then flushed when the message later drains.

Startup flush (mirror `_flushStartupDurableMembershipDependentMessages`): buffered durable rows replay on listener start.

Migration test `test/core/database/migrations/0NN_group_pending_reactions_test.dart` (mirror `054_..._test.dart` / `072_..._test.dart`) + helper tests; chain tests `full_migration_chain_test.dart` + `migration_database_schema_inventory_test.dart` to the new version.

**GREEN implementation**

1. **Migration `N`** `0NN_group_pending_reactions.dart` — template `072_group_pending_membership_messages.dart`: columns `(id PK, group_id, message_id TEXT nullable, sender_peer_id, reaction_json TEXT NOT NULL, received_at, created_at, updated_at)`; index on `(group_id, message_id)`; **partial-UNIQUE** dedup index on `reaction_id` (and/or `(group_id, message_id)` `WHERE message_id <> ''`) mirroring 072's `WHERE message_id IS NOT NULL AND message_id <> ''`. All `CREATE ... IF NOT EXISTS`, wrapped in START/SUCCESS/ERROR `emitFlowEvent(layer:'DB')` + rethrow. Bump `app_database_version.dart` to `N` and append the `if (oldVersion < N)` block in `main.dart` (strict ascending; reconcile with whatever landed first).
2. DB helpers + `GroupPendingReactionRepository` (+ impl + interface).
3. `handle_incoming_group_reaction_use_case.dart`: at the absent-message branch (`:136-148`), after validation, write the buffer row and return `bufferedPendingMessage` instead of `unknownMessage`. **Buffering inside the use case** means both the live listener and the offline-drain path get it for free (resolves the second drop site) — see OQ-1.
4. `group_message_listener.dart`: add the flush hook in `_handleMessage` immediately after `_emitGroupMessage(result)` (`~:811-833`) — look up buffered reactions keyed by `result.id`, re-run them through `handleIncomingGroupReaction` (now with the message present), emit each `ReactionChange`. Mirror `_flushMembershipDependentMessages` (`:1292`) and add a startup flush mirroring `_flushStartupDurableMembershipDependentMessages` (`:1442`). Also flush at the drain-path message-persist site.
5. Add FLOW events `GROUP_REACTION_BUFFERED` / `GROUP_REACTION_BUFFER_FLUSHED` for device observability.

**Gate:** all new + migration + chain tests green; full groups suite green (`-j 1` if the known shared-global-gate-file parallel race bites); `flutter analyze` clean; mutation check on the buffer/flush.

---

### Phase 5 (OPTIONAL / DEFERRED) — Gap 3c: `removed_at` tombstone. MIGRATION `N+1`. *(shared table — 1:1 + group)*

Gated on device-matrix evidence of residual cross-member divergence after Phases 1–4. If pursued:

- Migration `N+1` `0NN_message_reaction_tombstone.dart`: `ALTER TABLE message_reactions ADD COLUMN removed_at TEXT` (nullable; additive-safe).
- Convert the 3 hard-delete helpers in `reactions_db_helpers.dart` (`dbDeleteReaction`, `dbDeleteReactionsForMessage`, `dbDeleteReactionsForContact`) to set `removed_at`; add `removed_at IS NULL` to all loaders (`dbLoadReactionsForMessage`/`ForMessages`); **clear `removed_at` on re-add** (ensure `MessageReaction.toMap` writes `removed_at = null` so a `ConflictAlgorithm.replace` insert can't resurrect a stale tombstone). Preserve `dbDeleteReactionsForContact`'s ordering (runs before message deletion).
- LWW then treats `removed_at` newer than an incoming add's timestamp as "remove wins."
- **Regression surface is 1:1 + group** — full conversation + group reaction suites must stay green.

---

## 4. Cross-cutting gates & verification

**Unit/widget (per phase, above).** Plus integration:

- `test/features/groups/integration/group_reaction_roundtrip_test.dart` — add: (a) publish-failure injection → reaction survives in outbox and is re-driven by `retryFailedGroupInboxStores`; (b) reaction-before-message ordering on `FakeGroupPubSubNetwork` → buffered reaction appears after the message arrives; (c) rapid add/remove toggle → final state consistent across two `GroupTestUser`s.
- `test/features/conversation/integration/emoji_reaction_exchange_test.dart` — regression guard for 1:1 after the shared-repo Phase 3 change.
- `integration_test/group_recovery_e2e_test.dart` / `group_recovery_cli_e2e_test.dart` — add a reaction-recovery leg: send a reaction while the peer is offline, confirm it lands via relay custody on reconnect.

**Migration chain (lockstep):** `full_migration_chain_test.dart` + `migration_database_schema_inventory_test.dart` must move to version `N` in lockstep with whatever migration landed first (078–080 are contended by ≥3 other unlanded plans — see §1).

**Suite gates:** full groups suite green (use `-j 1` if the pre-existing shared-global-gate-file parallel race appears); 1:1 conversation reaction suites green (INV-R8); posts reaction suites green; `flutter analyze` — 0 new issues.

**Device matrix (two-device, group):**
- Reaction sent during a transient publish failure (force device B's topic-not-yet-joined window) is delivered after retry.
- Reaction received before its message becomes visible when the message lands.
- Rapid add/remove toggle converges across members.
- Greppable FLOW events: existing `GROUP_REACTION_SEND_*`, `RETRY_FAILED_GROUP_REACTION_REPLAY_OK/ERROR`; new `GROUP_REACTION_BUFFERED` / `GROUP_REACTION_BUFFER_FLUSHED`.

---

## 5. Risks, rollout order & open questions

| Risk / trade-off | Mitigation |
|------------------|-----------|
| Staging-before-publish enables a duplicate live publish on retry | Safe — deterministic reaction IDs + receiver upsert/delete by `(message_id, sender_peer_id)` ⇒ idempotent (INV-R3). |
| Keeping the optimistic emoji on `queuedForRetry` could show one that ultimately never delivers | Bounded retry governs the outbox; reactions are low-stakes; optional subtle pending affordance. Strictly better than today's *guaranteed* divergence. |
| Phase 3 repo guard is shared (1:1 + group) | Explicit 1:1 regression tests (INV-R8); change is purely "ignore strictly-older write," semantically safe for both. |
| LWW without tombstone can't defend remove-then-stale-add | Documented; Phases 1+2 shrink the window; Phase 5 tombstone only if device evidence shows residual divergence. |
| Buffer growth / memory | Per-group cap (reuse `50`) + TTL + oldest-first eviction; durable variant prunes like 072. |
| Reaction drain shares the message-row `limit` budget | Known; bounds throughput under heavy message backlog, not a correctness bug. |
| **Migration-number contention (078–080 claimed by ≥3 other plans)** | Allocate `N`/`N+1` at landing time (next free integer); reconcile the two chain tests in lockstep with whatever landed first. |

**Rollout order:** Phase 0 → **Phase 1 (Gap 1)** → **Phase 2 (Gap 3a)** → **Phase 3 (Gap 3b)** ship together as the low-risk, no-migration core (Gap 1 is the highest-value win). → **Phase 4 (Gap 2)** next (only migration in the core). → **Phase 5 (Gap 3c)** optional, deferred, device-evidence-gated. No feature flag is strictly required; the buffer + LWW can be guarded behind the existing `groupRecoveryEnabled` flag (`pending_message_retrier.dart`) for a staged rollout.

**Open questions:**
- **OQ-1 (buffer location):** Buffer **inside the use case** (durable-table write — automatically covers both the live listener *and* the offline-drain second drop site; my recommendation) vs **in the listener** (mirrors the membership-message pattern exactly but must separately patch the drain path). Recommend the use-case-level durable buffer for coverage + durability; the listener still owns the flush hook.
- **OQ-2 (remove-id determinism):** Confirm the remove-reaction id helper is deterministic; if not, fix it in Phase 1 so repeated remove re-stages are idempotent at the outbox PK.
- **OQ-3 (Phase 5 trigger):** Define the device-matrix observation that promotes Phase 5 from deferred to required (cross-member divergence after a rapid toggle that survives Phases 1–4).
