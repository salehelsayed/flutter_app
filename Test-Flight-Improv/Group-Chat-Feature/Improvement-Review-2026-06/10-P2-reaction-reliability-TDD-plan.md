> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P2** · Source finding: [`10-P2-reaction-reliability.md`](./10-P2-reaction-reliability.md)

---

# TDD Plan — Make group reactions as reliable as messages

**Status: PLAN ONLY.** Decomposed for TDD execution. Verified against HEAD `124-harness-refactor` (commit `41061593`) by a 10-agent verification workflow (3 graph-first recon → 3 adversarial refute → 3 cross-cut → synthesis) on 2026-06-16.

> **Re-reviewed 2026-06-16** (6-agent workflow vs the current working tree, *post* the 078/079/080 + 03/04/self-heal landings). Outcome: structure/scoping/invariants and **Phases 1/2/4 are sound**, but the plan was **not** implementable verbatim. Applied edits: **(a)** Phase 3 rewritten from a shared-repo guard to a **use-case-level LWW guard** that mirrors the *already-shipped* 1:1 guard (the old "1:1 and group are byte-identical / no LWW anywhere" premise was **false**); **(b)** OQ-2 promoted from "confirm" to a **required Phase-1 step** (the remove path mints a non-deterministic outbox PK); **(c)** migration ceiling refreshed **v77 → v80** (Phase 4 = `081`, Phase 5 = `082`); **(d)** chain-test lockstep corrected (`migration_database_schema_inventory_test.dart` does **not** move — version-independent); **(e)** drifted listener/wiring anchors re-pinned against the working tree. Anchors into the three reaction *use-case* files are unchanged (those files are untouched since `e7a840e5`); only listener/`main.dart`/`handle_app_resumed` anchors drifted.

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
| **2** | Reaction-before-message is silently dropped (no buffer) | **UNRESOLVED** (moderate) | `handle_incoming_group_reaction_use_case.dart:136-148` returns terminal `unknownMessage` when `msgRepo.getMessage(payload.messageId)==null` — **after** all sender/membership/device validation (`:61-131`), so the reaction is known-good. (Note: this branch is gated by `if (msgRepo != null)` at `:134`.) `group_message_listener.dart:4243` (`_handleReaction`) emits `ReactionChange` only on `success`. **Second drop site the source finding missed:** the offline-drain path `drain_group_offline_inbox_use_case.dart:533-554` also calls `handleIncomingGroupReaction`, discards the result, and `return`s. No `group_pending_reactions` table or buffer exists. |
| **3** | Concurrent add/remove can commit out of order (no serialize; **group** path has no LWW) | **UNRESOLVED** (narrowest) | Messages: `group_message_listener.dart:280-281` `incomingGroupMessages.asyncMap(_handleLiveMessage)` (serialized). Reactions: `:301` `incomingGroupReactions.listen(_handleLiveReaction)`; `_handleLiveReaction` (`:371-381`) is `void` and fires `_handleReaction(data)` via tracking-only `_trackInFlight` **without returning/awaiting** (the awaited `_allowsInboundAccountSideEffects` gate at `:373-378` runs inside this un-serialized future, widening the overlap window). **The group apply has no LWW:** `reactionTimestamp` (`handle_incoming_group_reaction_use_case.dart:71-85`) is consumed **only** by the dissolve gate; the apply at `:168-205` is an unconditional `saveReaction`/`removeReaction`. ⚠️ **Correction (re-review):** it is **not** true that there is "no LWW anywhere" — the **1:1 receive path already implements use-case-level LWW** (`handle_incoming_reaction_use_case.dart:178-199` + `_isStaleComparedToCurrent`/`:253-264`, parsed-`DateTime` compare, covers the remove direction). The gap is **group-only**: the group use case simply lacks the guard the 1:1 use case already has. Phase 3 closes it by mirroring that guard (see Phase 3). The shared repo (`reaction_repository_impl.dart:28-85`) + DB helpers (`reactions_db_helpers.dart`, `ConflictAlgorithm.replace` + plain `WHERE` delete) carry no timestamp predicate and are deliberately **left untouched**. |

**Load-bearing claim "Improvement 1 needs no retry-driver change" — HOLDS, with one critical reframing.** The retry driver (`retry_failed_group_inbox_stores_use_case.dart:108-175`) already queries `group_reaction_replay_outbox` (`loadRetryableEntries` → `dbLoadRetryableGroupReactionReplayOutboxEntries`, `WHERE delivery_status IN ('pending','failed')`), re-drives via `storeGroupOfflineReplayFromRetryPayload`, marks rows `stored`, and is wired in production on every retrier tick (`lib/core/services/pending_message_retrier.dart:416` guard / `:418` invocation, gated by `groupRecoveryEnabled` `:336`; constructed at `main.dart:2538-2546`) and every app resume (`handle_app_resumed.dart:609` guard / `:611` invocation, Step 8g; `main.dart:3875-3879`). **But** the *only* writer of those rows (`_stageReactionInboxStore`, `send_group_reaction_use_case.dart:186`) runs only **after** publish succeeds. So on a true publish failure no row exists and the driver finds nothing. **The consumer is complete; the producer is missing.** Gap 1's fix is purely producer-side. (Secondary note verified: reactions share the message-row `limit` budget — `remainingReactionSlots = limit - messages.length`, `:56` — so reactions are skipped on a tick when ≥20 message rows are backlogged. Bounds throughput; not a correctness bug.) *[Re-review: `pending_message_retrier` path corrected to `lib/core/services/`; `main.dart`/`handle_app_resumed` anchors re-pinned to the current working tree — they had drifted ~+250–280 lines under the concurrent landings.]*

---

## 1. Critical assessment & scoping decision

The source finding is accurate and well-scoped. Two corrections / additions from verification:

1. **Gap 2 has a second drop site** — the offline-drain path. Any buffer fix must cover **both** the live listener and `drain_group_offline_inbox_use_case`, or relay-delivered (store-and-forward) reactions that arrive before their message will still be dropped. The cleanest way to cover both for free is to do the buffering **inside the use case** (durable-table write) rather than only in the listener (see OQ-1).
2. **Gap 3's tombstone touches a shared table.** There is **no** group-only reaction table — both 1:1 and group reactions persist in the single `message_reactions` table (migration `016`) via the shared `ReactionRepository` (threaded to ~20 call-sites: 1:1 send/receive, group send/receive, share-target, qr-scanner). A `removed_at` tombstone (the source finding's optional extra migration) would convert 3 hard-delete helpers in `reactions_db_helpers.dart` to soft-delete, add `removed_at IS NULL` filters to all loaders, and require clearing the tombstone on re-add (`ConflictAlgorithm.replace` keyed on `UNIQUE(message_id, sender_peer_id)`). That is a 1:1 + group blast radius. **Defer it** (Phase 5, optional follow-up).
3. **Gap 3's LWW belongs at the use-case layer, NOT the shared repo (re-review correction).** The 1:1 receive path *already* does last-writer-wins in its use case (`handle_incoming_reaction_use_case.dart:178-199` / `_isStaleComparedToCurrent` `:253-264`). Phase 3 mirrors that into `handle_incoming_group_reaction_use_case.dart` and leaves the shared `ReactionRepository` / `reactions_db_helpers.dart` untouched. Pushing a guard into the repo instead would (a) require a new transactional read-before-write (the current `ConflictAlgorithm.replace` insert and plain `WHERE` delete read nothing → TOCTOU window, no comparand for the remove direction), and (b) double-guard the 1:1 path that already self-filters, across all ~20 call-sites — an INV-R8 hazard for no benefit. See Phase 3.

### Migration numbering — now settled at `081`/`082` (re-confirm free at landing)

HEAD ceiling is **v80** (`app_database_version.dart:1` `currentIdentityDatabaseVersion = 80`; highest file `080_group_pending_key_repairs_status_index.dart`; `onUpgrade` tail `if (oldVersion < 80)` at `main.dart:713`). Since this plan was first drafted, **`078_group_pending_key_distributions` (03-removal-rotation), `079_message_dedup_key`, and `080_group_pending_key_repairs_status_index` (self-heal) have all LANDED.** So **Phase 4 takes migration `081`** and **Phase 5 takes `082`**. No other in-tree migration occupies `081`. Other still-unlanded group-chat plans (06/09 etc.) also eye the next free integer, so **re-confirm `081` is free at this plan's own landing time**; whoever lands first wins it and the other rebases. Only **`full_migration_chain_test.dart`** needs structural reconciliation (recipe in §4); **`migration_database_schema_inventory_test.dart` is version-independent (frozen v74 raw-`CREATE` fixture) and does NOT move** — it was untouched by the 078/079/080 landings.

### In scope

- **Phase 1 (Gap 1)** — producer-side durable custody + pre-persist on publish failure, for send and remove; new `queuedForRetry` outcome; **deterministic remove-reaction id (OQ-2, required)**; wired layer stops the silent revert. **No migration.**
- **Phase 2 (Gap 3a)** — serialize the live reaction path (mirror messages' `asyncMap`); a 3-part edit, not a one-liner. **No migration.**
- **Phase 3 (Gap 3b)** — **use-case-level** last-writer-wins guard in the *group* use case, mirroring the existing 1:1 guard; shared repo left untouched. **No migration.**
- **Phase 4 (Gap 2)** — durable pending-reaction buffer + a single flush hook on message arrival (covers live listener + offline-drain via replay + startup). **Migration `081`.**
- **Phase 5 (Gap 3c, OPTIONAL / DEFERRED)** — `removed_at` tombstone on `message_reactions` for full remove-then-stale-add defense. **Migration `082`.** Gated on device-matrix evidence of residual divergence.

### Out of scope

Post reactions (already shipped); the 1:1 direct-reaction ack-before-commit work (owned by 125); any wire-format change (`GroupReactionPayload.timestamp` already round-trips — `group_reaction_payload.dart` — so LWW needs no new wire field).

---

## 2. Invariants (the contract the tests lock)

- **INV-R1 (custody):** A group reaction add/remove whose live publish returns `ok != true` or throws MUST leave (a) a durable `group_reaction_replay_outbox` row in `pending`/`failed`, and (b) locally-persisted optimistic reaction state. It MUST NOT silently revert the UI.
- **INV-R2 (retry, no driver change):** Such rows are re-driven by the existing retry driver with **zero** change to `retry_failed_group_inbox_stores_use_case` or its wiring. The plan adds only the producer row.
- **INV-R3 (idempotent re-delivery):** Re-staging/re-publishing a reaction is idempotent — sender side via the deterministic `reaction_id` PK (`_deterministicAddReactionId`, `send_group_reaction_use_case.dart:217-231`, **and a new `_deterministicRemoveReactionId` added in Phase 1 — the remove path currently uses `_uuid.v4()` at `remove_group_reaction_use_case.dart:82`, which is non-deterministic; see OQ-2**), receiver side via `UNIQUE(message_id, sender_peer_id)` upsert/delete.
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
- `test/features/conversation/domain/repositories/fake_reaction_repository.dart` exists — confirm it records `saveReaction`/`removeReaction` and (Phase 3) can return a stored reaction with a timestamp for the group use case's LWW comparand. *(Phase 3 now guards at the use-case layer, so the group `handle_incoming_group_reaction_use_case` test asserts the stale-skip via this fake — no real-DB test of a repo predicate is needed.)*
- If Phase 4 builds the durable table: create `InMemoryGroupPendingReactionRepository` (the existing durable-buffer fake to clone is `test/shared/fakes/in_memory_group_pending_membership_message_repository.dart` — note the `InMemory` prefix, not `Fake`), and extend `GroupTestUser` / `FakeGroupPubSubNetwork` plumbing.
- Also verify (Phase 3 prereq): 1:1 reaction timestamps are sender-authored ISO-8601 UTC (`send_reaction_use_case.dart:61`) so the existing 1:1 use-case LWW is sound and the mirrored group guard is safe.

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
- **Remove re-staging idempotency (OQ-2 — now a confirmed bug, REQUIRED to fix here):** assert two remove re-stages for the same `(groupId, messageId, senderPeerId)` produce **one** outbox row. This is currently broken: `remove_group_reaction_use_case.dart:82` mints the outbox PK via `_uuid.v4()`, so under the Phase-1 stage-before-publish reorder a repeated remove (or a retry-then-user-retry interleave) creates a *second* distinct `group_reaction_replay_outbox` row for the same logical remove. The RED test fails until the deterministic helper below exists.

`group_conversation_wired` widget test (extend the existing reaction widget tests):
- On `queuedForRetry`, the optimistic emoji is **kept** (temp swapped for the persisted `MessageReaction`, not reverted via `_restoreReactionState`).
- On `groupNotFound` / `notMember` / `unauthorizedSenderKey` / `messageNotFound` and on a thrown exception → still revert (unchanged).
- On `groupDissolved` → `_restoreReactionStateAfterDissolve` (unchanged).

**GREEN implementation**

1. `send_group_reaction_use_case.dart`: reorder so the durable + local steps run regardless of publish outcome. Concretely: build payload → `_stageReactionInboxStore` (writes the `pending` outbox row) → `reactionRepo.saveReaction` (optimistic local) → attempt publish. On publish `ok` → `success`; on `ok != true` or throw → `queuedForRetry` (the row already exists; the existing retry driver will re-drive it). Add `queuedForRetry` to `SendGroupReactionResult` and return the persisted `MessageReaction` alongside it.
2. `remove_group_reaction_use_case.dart`: identical reorder; add `RemoveGroupReactionResult.queuedForRetry`. **(OQ-2, REQUIRED)** add a top-level `_deterministicRemoveReactionId({groupId, messageId, senderPeerId})` mirroring `_deterministicAddReactionId` (`send_group_reaction_use_case.dart:217-231`: sha256 over canonical JSON with `action: 'remove'`, prefix `group-reaction-remove-`); replace `_uuid.v4()` at `:82` with it; drop the now-unused `uuid` import. This makes repeated remove re-stages collapse to one outbox row at the PK.
3. `group_conversation_wired.dart`: in `_onReactionSelected` send/remove branches, treat `queuedForRetry` like `success` for UI retention (swap temp→persisted on send; no-op keep on remove). Optionally surface a subtle "will deliver when reconnected" affordance (not required for closure).

**Caveat handled (INV-R3):** staging-before-publish enables a duplicate live publish on a later retry — safe because reaction IDs are deterministic and receivers upsert/delete by `(message_id, sender_peer_id)`.

**Gate:** the two use-case suites + the wired reaction widget tests green; `flutter analyze` clean; **mutation check** — revert the reorder and confirm the new RED tests fail. Confirm the existing retry-driver suite (`retry_failed_group_inbox_stores` tests) still passes unchanged (INV-R2).

---

### Phase 2 — Gap 3a: serialize the live reaction path. NO MIGRATION.

**RED test** — new `test/features/groups/application/group_message_listener_reaction_serialize_test.dart`: feed two reactions for the same `(messageId, senderPeerId)` back-to-back on the reaction stream where the first handler's async prefix is slow; assert they are applied in arrival order (no interleave) and the handler future is awaited (e.g. a completion signal fires only after the second is applied). **Interleave at the `_allowsInboundAccountSideEffects` gate await (`:373-378`), not only at `_handleReaction`** — today that gate runs inside the un-serialized future, so two reactions' gate checks overlap; the test must prove the *whole* handler (gate included) is serialized.

**GREEN** — this is a **3-part edit** in `group_message_listener.dart`, not a one-liner (`_handleLiveReaction` is currently `void` and fires its work fire-and-forget, so `asyncMap` would not actually serialize it):
1. Change the signature `void _handleLiveReaction(...)` → `Future<void> _handleLiveReaction(...)` (`:371`).
2. Add `return` before the `_trackInFlight(...)` call (`:372`) so the tracked future — which already wraps the `_allowsInboundAccountSideEffects` gate at `:373-378` — is returned and therefore awaited.
3. Rewire the subscription `incomingGroupReactions.listen(_handleLiveReaction)` (`:301`) → `incomingGroupReactions.asyncMap(_handleLiveReaction).listen((_) {})`.

This copies the message path's shape verbatim (`incomingGroupMessages.asyncMap(_handleLiveMessage)` at `:280-281`, where `_handleLiveMessage` is `Future<void>` returning `_trackInFlight(...)`); `_trackInFlight` (`:436`) is shared by both handlers — no new infra. (Option A — global serialization; lowest risk. Option B per-`(groupId)` via `_enqueueGroupConfigWork` only if large-group throughput is later measured to matter.)

**Gate:** new test green; existing listener suite green; `flutter analyze` clean; mutation check (restore `.listen` → test fails).

---

### Phase 3 — Gap 3b: **use-case-level** last-writer-wins guard in the group use case. NO MIGRATION. *(group-only — mirrors the shipped 1:1 guard; shared repo untouched)*

> **Re-review rewrite.** The original plan pushed an `incoming.timestamp > existing.timestamp` predicate into the shared repo / DB-helper. That was rejected: the shared `ReactionRepository` feeds ~20 call-sites; `dbInsertReaction` (`reactions_db_helpers.dart:9-39`) is a bare `ConflictAlgorithm.replace` and `dbDeleteReaction` (`:115-147`) a plain `WHERE` delete — *neither reads anything* — so a "conditional" there is a brand-new transactional read-modify-write (TOCTOU window, ISO-8601 `TEXT` ordering risk) **and** it would double-guard the 1:1 path, which **already** does use-case-level LWW (`handle_incoming_reaction_use_case.dart:178-199` + `_isStaleComparedToCurrent` `:253-264`). The group use case simply lacks that guard. So: **mirror the 1:1 guard into the group use case; leave the shared repo and the 1:1 path untouched.** INV-R8 is then satisfied *by construction*.

**RED tests**

`test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`:
- A stale add (incoming `timestamp` `isBefore` the stored reaction's) is dropped — the apply is skipped, result is `success` with no state change (mirrors the 1:1 use case's stale-drop return).
- A newer add **does** overwrite the older stored reaction.
- A remove whose `timestamp` is older than the stored add is a no-op; a newer remove deletes. *(The remove is comparable only while the add row still exists — see Known limitation.)*
- **1:1 regression guard (INV-R8):** the shared repo/helpers are NOT touched, so `send_reaction_use_case` / `handle_incoming_reaction_use_case` / `reaction_repository_impl` suites must stay green unchanged.

**GREEN** — in `handle_incoming_group_reaction_use_case.dart`, before the apply switch (`:168-205`), load the current stored reaction for `(messageId, senderPeerId)` and **skip the apply when the incoming reaction is stale**, mirroring the 1:1 guard:
- Reuse the same comparison shape as `_isStaleComparedToCurrent` (`handle_incoming_reaction_use_case.dart:253-264`): **compare PARSED `DateTime`s** (`incoming.timestamp.isBefore(current.timestamp)`), **not** lexicographic `TEXT` — `MessageReaction.timestamp` is an ISO-8601 string and string ordering is only coincidentally correct.
- Gate **before** the add/remove branch so the remove direction is covered while the add row still carries a comparand.
- No `ReactionRepository` / `reactions_db_helpers` / schema change. (If a repo-level guard is ever revived, it MUST be gated group-only at the repo boundary and prove non-conflict with the existing 1:1 use-case guard — not the default here.)

**Prereq verified (INV-R8):** 1:1 reaction timestamps are sender-authored and monotonic (`send_reaction_use_case.dart:61` stamps `DateTime.now().toUtc().toIso8601String()`), so the 1:1 self-filter is sound and unaffected; the group path's `GroupReactionPayload.timestamp` round-trips the sender stamp identically. Confirm both in Phase 0.

**Known limitation (documented, see Phase 5):** without a tombstone, a remove deletes the row, so a later *older* add finds nothing to compare against and re-inserts (remove-then-stale-add). LWW here is therefore **one-directional** (protects a stored add from an older add or older remove; cannot protect a remove from a later stale add). Phases 1+2 already shrink this window dramatically; the residual is low-stakes. Phase 5 closes it fully if device testing shows divergence.

**Gate:** group handle suite green; **1:1 + posts reaction suites green (regression guard — must be byte-unchanged since the shared repo is untouched)**; `flutter analyze` clean; mutation check (remove the stale-skip → the stale-add RED test fails).

---

### Phase 4 — Gap 2: durable pending-reaction buffer + flush. MIGRATION `081`. *(one flush hook covers live listener + offline-drain + startup)*

**RED tests**

`test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`:
- Reaction with an absent target message, after passing all validation, returns the new `HandleGroupReactionResult.bufferedPendingMessage` (not `unknownMessage`) and the reaction is recorded in the buffer. **The test MUST pass a non-null `msgRepo` whose `getMessage` returns `null`** — the absent-message branch is gated by `if (msgRepo != null)` at `:134`; with a null `msgRepo` the branch is unreachable and the test passes vacuously against old code.

New `test/features/groups/application/group_message_listener_reaction_buffer_test.dart`:
- Buffer a reaction, then deliver its target message → the buffered `ReactionChange` is emitted **exactly once** (INV-R5) and the buffer entry is cleared.
- Cap eviction (per-group cap, oldest-first) and TTL expiry.
- Dedup by `reaction_id` (re-delivered buffered reaction does not stack).

Offline-drain coverage (extend `drain_group_offline_inbox_use_case` tests): a relay-delivered reaction whose message is absent is buffered (the use case writes the buffer row, so the `:533-554` drain site inherits it for free), then flushed when the message later drains *via the same `:926` flush hook* (the drain replays messages through `handleReplayEnvelope` → `_emitGroupMessage`).

Startup flush (mirror `_flushStartupDurableMembershipDependentMessages` `:1465`): buffered durable rows replay on listener start.

Migration test `test/core/database/migrations/081_group_pending_reactions_test.dart` (mirror `054_..._test.dart` / `072_..._test.dart`) + helper tests; reconcile `full_migration_chain_test.dart` only (see §4 for the exact recipe). **`migration_database_schema_inventory_test.dart` needs NO change** — it is version-independent (frozen v74 fixture).

**GREEN implementation**

1. **Migration `081`** `081_group_pending_reactions.dart` — template `072_group_pending_membership_messages.dart`: columns `(id PK, group_id, message_id TEXT nullable, sender_peer_id, reaction_json TEXT NOT NULL, received_at, created_at, updated_at)`; index on `(group_id, message_id)`; **partial-UNIQUE** dedup index on `reaction_id` (and/or `(group_id, message_id)` `WHERE message_id <> ''`) mirroring 072's `WHERE message_id IS NOT NULL AND message_id <> ''`. All `CREATE ... IF NOT EXISTS`, wrapped in START/SUCCESS/ERROR `emitFlowEvent(layer:'DB')` + rethrow. *(If retry/attempt accounting is wanted, the just-landed `078_group_pending_key_distributions.dart` column set — `status TEXT NOT NULL DEFAULT 'pending'` + `attempts`/`last_error`/`finalized_at` — is a better starting point than 072's bare timestamps.)* Bump `app_database_version.dart:1` to `81` and wire **BOTH** `main.dart` sites: append `await runGroupPendingReactionsMigration(db);` to the **onCreate** runner list (after `runGroupPendingKeyRepairsStatusIndexMigration` ~`:476`) AND append `if (oldVersion < 81) { await runGroupPendingReactionsMigration(db); }` to the **onUpgrade** tail (after the `oldVersion < 80` block ~`:715`). *(Omitting onCreate = fresh installs never get the table.)*
2. DB helpers + `GroupPendingReactionRepository` (+ impl + interface) — production analog to clone is the `group_pending_membership_message{,_repository,_repository_impl}` + `group_pending_membership_messages_db_helpers` trio.
3. `handle_incoming_group_reaction_use_case.dart`: at the absent-message branch (`:136-148`, inside the `if (msgRepo != null)` guard at `:134`), after validation, write the buffer row and return `bufferedPendingMessage` instead of `unknownMessage`. **Buffering inside the use case** means both the live listener and the offline-drain path get the durable WRITE for free (resolves the second drop site) — see OQ-1.
4. `group_message_listener.dart`: add the flush hook immediately after the live message persist `_emitGroupMessage(result)` at **`:926`** (after `handleIncomingGroupMessage` at `:904`) — look up buffered reactions keyed by `result.id`, re-run them through `handleIncomingGroupReaction` (now with the message present), emit each `ReactionChange`. **A single hook at `:926` serves BOTH the live and the drain paths** — the drain has no independent message-persist site; it replays via `handleReplayEnvelope` → `_handleMessage` → `_emitGroupMessage(result):926`. Mirror `_flushMembershipDependentMessages` (`:1315`) and add a startup flush mirroring `_flushStartupDurableMembershipDependentMessages` (`:1465`, startup-wired at `:328`). **DELETE the durable buffer row before emitting each `ReactionChange`** (mirror membership `_deleteDurableMembershipDependentMessage` `:1398`) so INV-R5 exactly-once holds under overlapping startup-flush + `:926`-flush.
   - **Wiring:** inject `GroupPendingReactionRepository` as a **constructor dependency of `GroupMessageListener`** (mirror `pendingMembershipMessageRepo` — field `:125`, constructed at `main.dart:2206`). **Do NOT** copy the process-wide-sink + standalone-`Runner` pattern from the just-landed `setDeferredDistributionDrainSink` / `GroupPendingKeyDistributionRunner` (03) — that pattern exists only because key-arrival triggers fire from sites with no listener handle; the reaction flush triggers on message arrival, which already flows through the listener.
5. Add FLOW events `GROUP_REACTION_BUFFERED` / `GROUP_REACTION_BUFFER_FLUSHED` for device observability.

**Gate:** all new + migration + chain tests green; full groups suite green (`-j 1` if the known shared-global-gate-file parallel race bites); `flutter analyze` clean; mutation check on the buffer/flush.

---

### Phase 5 (OPTIONAL / DEFERRED) — Gap 3c: `removed_at` tombstone. MIGRATION `082`. *(shared table — 1:1 + group)*

Gated on device-matrix evidence of residual cross-member divergence after Phases 1–4. If pursued:

- Migration `082` `082_message_reaction_tombstone.dart`: `ALTER TABLE message_reactions ADD COLUMN removed_at TEXT` (nullable; additive-safe). *(Re-confirm `082` is free at landing.)*
- Convert the 3 hard-delete helpers in `reactions_db_helpers.dart` (`dbDeleteReaction`, `dbDeleteReactionsForMessage`, `dbDeleteReactionsForContact`) to set `removed_at`; add `removed_at IS NULL` to all loaders (`dbLoadReactionsForMessage`/`ForMessages`); **clear `removed_at` on re-add** (ensure `MessageReaction.toMap` writes `removed_at = null` so a `ConflictAlgorithm.replace` insert can't resurrect a stale tombstone). Preserve `dbDeleteReactionsForContact`'s ordering (runs before message deletion).
- LWW then treats `removed_at` newer than an incoming add's timestamp as "remove wins."
- **Regression surface is 1:1 + group** — full conversation + group reaction suites must stay green.

---

## 4. Cross-cutting gates & verification

**Unit/widget (per phase, above).** Plus integration:

- `test/features/groups/integration/group_reaction_roundtrip_test.dart` — add: (a) publish-failure injection → reaction survives in outbox and is re-driven by `retryFailedGroupInboxStores`; (b) reaction-before-message ordering on `FakeGroupPubSubNetwork` → buffered reaction appears after the message arrives; (c) rapid add/remove toggle → final state consistent across two `GroupTestUser`s.
- `test/features/conversation/integration/emoji_reaction_exchange_test.dart` — regression guard for 1:1; with the re-review Phase 3 (group-only use-case guard, shared repo untouched) this suite must stay **byte-unchanged**.
- `integration_test/group_recovery_e2e_test.dart` / `group_recovery_cli_e2e_test.dart` — add a reaction-recovery leg: send a reaction while the peer is offline, confirm it lands via relay custody on reconnect.

**Migration chain — `full_migration_chain_test.dart` only.** Verified recipe (copy what the just-landed 078/079/080 did): (a) add the `081_group_pending_reactions.dart` import after the `080` import (~`:77`); (b) append `await runGroupPendingReactionsMigration(db);` to **both** runner builders — `runFreshInstallMigrations` (after the last call ~`:175`) **and** `runUpgradePathFromV1` (~`:304`); (c) add `'group_pending_reactions'` to the test-1a `containsAll([...])` table-name list (~`:499`). **`migration_database_schema_inventory_test.dart` is version-independent (frozen v74 raw-`CREATE` fixture) and needs NO change** — it was untouched by 078/079/080 (commit `3b657723`).

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
| Staging-before-publish enables a duplicate live publish on retry | Safe — deterministic reaction IDs (add helper `:217-231`; **new remove helper, Phase 1 / OQ-2**) + receiver upsert/delete by `(message_id, sender_peer_id)` ⇒ idempotent (INV-R3). |
| Keeping the optimistic emoji on `queuedForRetry` could show one that ultimately never delivers | Bounded retry governs the outbox; reactions are low-stakes; optional subtle pending affordance. Strictly better than today's *guaranteed* divergence. |
| ~~Phase 3 repo guard is shared~~ → **Phase 3 is group-only (re-review)** | LWW lands in the *group* use case mirroring the shipped 1:1 guard; the shared `ReactionRepository`/`reactions_db_helpers` and the 1:1 path are untouched, so INV-R8 holds **by construction**. Avoids the repo-level read-before-write (TOCTOU + `TEXT` ordering) the original draft implied. |
| LWW without tombstone can't defend remove-then-stale-add | Documented (one-directional); Phases 1+2 shrink the window; Phase 5 tombstone only if device evidence shows residual divergence. |
| Buffer growth / memory | Per-group cap (reuse `50`) + TTL + oldest-first eviction; durable variant prunes like 072. |
| Reaction drain shares the message-row `limit` budget | Known; bounds throughput under heavy message backlog, not a correctness bug. |
| ~~Migration-number contention~~ → **settled: Phase 4 = `081`, Phase 5 = `082`** | 078/079/080 have landed; 081 is free. Re-confirm at landing (other unlanded plans eye the next integer); reconcile `full_migration_chain_test.dart` only (§4). |

**Rollout order:** Phase 0 → **Phase 1 (Gap 1)** → **Phase 2 (Gap 3a)** → **Phase 3 (Gap 3b)** ship together as the low-risk, no-migration core (Gap 1 is the highest-value win). → **Phase 4 (Gap 2)** next (only migration in the core). → **Phase 5 (Gap 3c)** optional, deferred, device-evidence-gated. No feature flag is strictly required; the buffer + LWW can be guarded behind the existing `groupRecoveryEnabled` flag (`lib/core/services/pending_message_retrier.dart`) for a staged rollout.

**Open questions:**
- **OQ-1 (buffer location) — RESOLVED:** buffer **inside the use case** (durable write covers both the live listener *and* the offline-drain second drop site for free); the **single `:926` flush hook** in the listener owns the flush and is inherited by the drain via replay. The listener owns the `GroupPendingReactionRepository` as a constructor dep (not a process-wide sink).
- **OQ-2 (remove-id determinism) — RESOLVED: confirmed bug, now a required Phase-1 step.** `remove_group_reaction_use_case.dart:82` uses `_uuid.v4()` for the outbox PK → repeated remove re-stages create distinct rows. Phase 1 adds `_deterministicRemoveReactionId` (no longer optional).
- **OQ-3 (Phase 5 trigger):** Define the device-matrix observation that promotes Phase 5 from deferred to required (cross-member divergence after a rapid toggle that survives Phases 1–4).
