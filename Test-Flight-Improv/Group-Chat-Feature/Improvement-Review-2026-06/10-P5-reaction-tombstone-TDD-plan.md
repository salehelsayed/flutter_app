> Follow-up to **[10-P2 reaction-reliability TDD plan](./10-P2-reaction-reliability-TDD-plan.md)** · the deferred **Phase 5 (Gap 3c)** · Priority **P3**

---

# TDD Plan — `removed_at` tombstone for full remove-then-stale-add convergence

**Status: IMPLEMENTED (2026-06-16), host-green.** P5.1–P5.4 landed TDD: migration 082 (DB v82), `MessageReaction.removedAt`, soft-delete `dbDeleteReaction` + `dbLoadActiveOrTombstonedReactionForSender` + `removed_at IS NULL` loaders, repo interface `getReactionForSenderIncludingRemoved` + additive `removeReaction(...,{removedAtTimestamp})`, and tombstone-aware LWW comparand (`removed_at ?? timestamp`) wired into BOTH the 1:1 and group receive guards + threaded through all 4 remove call sites. Gates: full groups suite **2160**, core/database green, all 1:1+group+posts reaction suites green (INV-T5), `flutter analyze` 0 new, migration chain green. The only repo-wide failure is the pre-existing `retry_unacked` `'inboxed'` (115 work, fails in isolation, zero reaction involvement). **P5.5 device proofs — BOTH PASSED:**
- **Single-sim real-SQLCipher DB proof** (`integration_test/group_reaction_reliability_db_proof_test.dart`, iPhone 16e, 3/3): migrations 081/082 apply on the encrypted engine; tombstone soft-delete hides from loaders + comparand sees it + re-add clears; bulk cleanup hard-removes tombstones (no leak); buffer dedup/lookup/claim/cap/TTL correct.
- **3-sim real cross-device add-roundtrip convergence** (`private_reaction_roundtrip`, Alice iPhone 17 Pro / Bob iPhone Air / Charlie iPhone 17, real Go ML-KEM bridge + prod relay `mknoun.xyz`): orchestrator verdict "valid for alice, bob, charlie"; Bob's 🔥 `reactionOutcome:success` **observed+converged by all three**; live FLOW shows Phase-1 custody on device (Bob outbox SAVE→`group:publishReaction` success→`stored`), migrations 081/082 applied on each device's real SQLCipher.
- **3-sim rapid add/remove TOGGLE convergence** (NEW `private_reaction_toggle_convergence`, same three sims): Bob toggles add 🔥→remove→re-add ✅; verdict "valid for alice, bob, charlie" requiring all three converge to exactly one final ✅ AND Alice+Charlie `observedRemoveEvent:true`. **Live device FLOW proved the whole Phase 3+4+5 path** on Alice+Charlie: `RECEIVE_STORED(🔥)` → `RECEIVE_REMOVED` (Phase-5 soft-delete tombstone) → `RECEIVE_STORED(✅)` (Phase-3 LWW clears the tombstone); Bob `REMOVE_QUEUED` (Phase-1 custody). A receiver that dropped the remove and merely REPLACE'd 🔥→✅ would fail `observedRemoveEvent`.
- (Both runs required reconciling pre-existing NON-reaction harness drift first — `group_multi_device_real_harness.dart` lacked migrations 081/082/083 in its onCreate and 3 self-heal-era `GroupPendingKeyRepairRepositoryImpl` closures.)

This plan closes the **one-directional LWW residual** documented in Phase 3: today a remove *deletes* the `message_reactions` row, so a later *older* add finds nothing to compare against and re-inserts → cross-member divergence (`remove → stale-add`).

## Design corrections vs the parent plan's Phase 5 sketch

The parent plan said "convert the 3 hard-delete helpers to soft-delete." That is **over-broad and wrong**:

1. **Tombstone ONLY `dbDeleteReaction`** — the per-`(message_id, sender_peer_id)` remove that is part of the LWW protocol. `dbDeleteReactionsForMessage` / `dbDeleteReactionsForContact` are destructive *cleanup* (message/contact deletion); soft-deleting them would leave **orphan tombstones forever** (no message row to ever clear them) — an unbounded leak. They stay HARD deletes; they already remove active rows **and** tombstones for the target.
2. **The add apply needs no change.** `message_reactions` is `UNIQUE(message_id, sender_peer_id)` (migration 016) with `ConflictAlgorithm.replace`. A non-stale add's `saveReaction` REPLACEs the tombstone row with `removed_at = NULL` automatically — *provided* `MessageReaction.toMap` writes `removed_at`. Staleness is decided in the use-case guard **before** the apply, exactly as Phase 3.
3. **Tombstone needs a sender-authored comparand.** A remove records `removed_at = <remove payload timestamp>` (NOT `now()`), so cross-device LWW compares authored ISO-8601 timestamps consistently. This requires an **additive** `removeReaction(..., {String? removedAtTimestamp})` threaded through the 4 callers.
4. **LWW comparand must see tombstones.** UI loaders (`getReactionsForMessage`/`ForMessages`) gain `removed_at IS NULL`; a NEW tombstone-aware single getter feeds the guard, whose comparand = `removed_at ?? timestamp`.

**Scope note (documented residual):** option = soft-delete an **existing** row (the `remove → stale-add` case the parent plan targets, where the remove is applied *after* the add so a row exists). The fully-reordered `remove-before-add` edge (remove arrives at the receiver with no prior add) is NOT covered here (would require synthesizing a tombstone row from the remove payload) — it is a smaller window already shrunk by Phase 2 serialization, and is left as an explicit residual.

## Migration numbering — `082` (DB v81 → v82)

HEAD ceiling is v81 (`app_database_version.dart` after 10-P2 Phase 4). Phase 5 takes **`082`**. `migration_database_schema_inventory_test.dart` is version-independent (frozen v74 fixture) → no change; only `full_migration_chain_test.dart` reconciles.

## Invariants

- **INV-T1 (tombstone on remove):** an applied remove sets `removed_at = <remove timestamp>` on the `(message_id, sender_peer_id)` row instead of deleting it; the reaction disappears from all UI loaders.
- **INV-T2 (stale-add blocked):** an add whose `timestamp` is `isBefore` a tombstone's `removed_at` is dropped (no re-insert) on BOTH the 1:1 and group receive paths.
- **INV-T3 (newer-add clears):** an add whose `timestamp` is `>=` the tombstone's `removed_at` re-inserts an active reaction (`removed_at` cleared).
- **INV-T4 (cleanup hard-deletes):** message/contact deletion removes active rows AND tombstones (no orphan leak); ordering preserved (`...ForContact` before message deletion).
- **INV-T5 (no regression):** all 1:1 + group + posts reaction suites stay green; `getReactionsForMessage(s)` never returns a tombstoned row.

## Phases (test-first)

- **P5.1 — migration 082 + model.** `ALTER TABLE message_reactions ADD COLUMN removed_at TEXT` (additive, nullable). `MessageReaction.removedAt` + `toMap`/`fromMap` (writes `removed_at`, default null). Migration test + chain reconcile. Bump `app_database_version` → 82.
- **P5.2 — db-helper soft-delete + loaders.** `dbDeleteReaction(db, messageId, senderPeerId, {String? removedAtTimestamp})` → UPDATE `removed_at` (fallback `now()` when null). `dbInsertReaction` carries `removed_at`. `dbLoadReactionsForMessage`/`ForMessages` add `removed_at IS NULL`. New `dbLoadActiveOrTombstonedReactionForSender(db, messageId, senderPeerId)`. Real-SQLite helper tests for INV-T1..T4.
- **P5.3 — repo interface + fakes.** `removeReaction(messageId, senderPeerId, {String? removedAtTimestamp})`; new `getReactionForSenderIncludingRemoved(...)`. Update `ReactionRepositoryImpl`, `FakeReactionRepository`, and any other implementers to model tombstones.
- **P5.4 — use-case LWW integration (1:1 + group).** Both guards switch their comparand to `getReactionForSenderIncludingRemoved` with `removed_at ?? timestamp`; both remove applies pass `removedAtTimestamp: payload.timestamp`. The send-side removes (`remove_reaction_use_case`, `remove_group_reaction_use_case`) pass their remove `timestamp`. RED tests: remove-then-stale-add stays removed; newer add clears.
- **P5.5 — device convergence proof (simulator).** Real-crypto integration test mirroring `group_*_converge_proof_test.dart`: rapid add/remove toggle + reordered stale re-add converge across two members. Run on a booted simulator.

## Gates

Per-phase real-SQLite + unit/widget green; full 1:1 conversation + group + posts reaction suites green (INV-T5); migration chain green; `flutter analyze` 0 new; simulator proof green.
