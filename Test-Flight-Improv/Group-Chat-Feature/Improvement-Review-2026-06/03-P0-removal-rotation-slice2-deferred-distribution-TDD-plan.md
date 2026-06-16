> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P0 (residue, best-effort)** · Slice 2 of the TDD plan for **[03-P0-removal-rotation-fails-closed.md](./03-P0-removal-rotation-fails-closed.md)**

---

# TDD Plan — Slice 2: sender-side deferred-distribution convergence

**Status: PLAN ONLY.** Decomposed for TDD execution. Verified against HEAD `124-harness-refactor` (commit `41061593`).

> Companion to the [finding](./03-P0-removal-rotation-fails-closed.md) and to the [Slice 1 plan](./03-P0-removal-rotation-fails-closed-TDD-plan.md). Slice 1 (the **security core**) is **landed and device-verified**. This document specifies the **only remaining deferred item**: making a keyless / undelivered *remaining* member converge onto the promoted epoch, instead of sitting on the old key until an unrelated future rotation. This is a **convergence feature, not a security gate** — see §1.

---

## 0. Resolution verification (what's done, what's left)

**Slice 1 is DONE and verified.** The security core (R-0 → R-1 → R-2) landed: rotation is now **promote-then-defer** (`RotateGroupKeyOutcome`, the abort gates removed), the admin caller no longer throws into the re-add rollback, and the rollback is `removalBroadcast`-guarded so a removed member is **never** re-granted the key. Verification of record:

| Gate | Evidence |
|---|---|
| Groups suite | **2070 green** (`-j 1`), `flutter analyze` no new issues |
| Adversarial invariant pass | **INV-R1..R5 confirmed** (durable exclusion, no re-grant, monotonic epoch, rotated ≠ fully-distributed, leave path unchanged) |
| Device proof | **PASSED** on iPhone 17 Pro simulator (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`) + Pixel 6, via `integration_test/group_removal_rotation_keyless_proof_test.dart` — real `GoBridgeClient`, real ML-KEM-768 + AES-GCM: keyless bystander no longer aborts; epoch+1 promoted; `deferredPeerIds == [carol]`; new epoch decrypts; removed member's retained key fails |

**What Slice 1 leaves open — the convergence gap (C8 in the finding).** Slice 1 *records* the deferred member but does not converge it. After a removal with a keyless / undelivered remaining member Y:

- The rotation promotes the new epoch and, for each deferred peer, fires the **enqueue seam** introduced in Slice 1:
  `EnqueueDeferredGroupKeyDistribution` typedef — `rotate_and_distribute_group_key_use_case.dart:23-28` (`{required groupId, required peerId, required keyEpoch}`), optional param at `:99`, invoked once per deferred peer at `:470-477` after promotion+save, with `GROUP_ROTATE_KEY_DEFERRED_REPAIR_QUEUED` (`:461-469`) per peer and one `GROUP_ROTATE_KEY_PARTIAL_DISTRIBUTION` summary (`:489-498`).
- **That seam's production default is a no-op.** All three rotate call sites pass *nothing* → null default → the deferred peer is recorded only in telemetry + the transient `RotateGroupKeyOutcome.deferredPeerIds`, then forgotten.
- There is **no key-pull and no sender re-push anywhere** (verified in Slice 1 §0.4): the receiver-driven repair runner retries *decryption* once a key is already local (`group_pending_key_repair_service.dart` `_retryOne` → `decryptGroupOfflineReplayEnvelope`), never fetches or re-distributes a key. So Y has **no existing convergence path**; it reads new-epoch traffic only when some later rotation happens to reach it.

**Slice 2 = wire that seam to a durable queue + a drainer.** A new `group_pending_key_distributions` table persists each deferred `(groupId, peerId, keyEpoch)`; a `GroupPendingKeyDistributionRunner` re-distributes the **current** group key to the target the moment the target gains a usable ML-KEM key (and on app resume as catch-all). The seam (`rotate_uc.dart:99/470-477`) is the integration point — Slice 2 replaces the no-op default with `repo.enqueue` at all three call sites.

---

## 1. Critical assessment & scoping

**Slice 2 is best-effort convergence, NOT a security gate.** The deferred member is an *insider* who was already a member at rotation time; before the removal they could already read old-epoch traffic, and after Slice 1 they retain the old key until they converge. Failing to converge them is a **degraded-read** condition for an already-authorized peer, never a confidentiality leak — the *removed* member (the security boundary) is durably excluded by Slice 1 regardless of whether Slice 2 ever runs. This frames every trade-off below: Slice 2 may be bounded, may give up after an attempt cap, and may lag a resume cycle, all without weakening the P0.

### 1.1 Dedicated table vs status-overload of `group_pending_key_repairs` (recommended: dedicated)

The finding's note ("could reuse repair infra") and Slice 1 OQ-1 both surface this. **Recommendation: a dedicated `group_pending_key_distributions` table.** Rationale, source-anchored:

- The repair table stores a **replay envelope** (`replay_envelope_json`, `063_group_pending_key_repairs.dart:14`) and the repair runner's `_retryOne` (`group_pending_key_repair_service.dart:427`) is **decryption-specific** — no envelope → "waiting for replay envelope" + stay pending; else decrypt via `decryptGroupOfflineReplayEnvelope` and replay an incoming message/reaction. That is a *receiver-pull* direction.
- A distribution row stores **no envelope** and retries *sender-push* (re-encrypt the current group key to the now-keyed target device). Overloading one table with two opposite directions and two incompatible `_retryOne` semantics is exactly the "status overload proves confusing" hazard the finding flags, and it would entangle the receiver-repair invariants that Slice 1 / the 02 self-heal plan depend on.
- A dedicated table is cheap (mirror the well-factored `063` template end to end) and keeps each runner's terminal-state logic clean. The repair runner has **no numeric attempt cap** (only a key-presence retry-vs-terminal gate, `group_pending_key_repair_service.dart:548`); the distribution runner will add an explicit cap (§2 bounded), which is another reason not to fold the two.

### 1.2 Explicitly OUT OF SCOPE

- **The Slice 1 security core** — `RotateGroupKeyOutcome`, the removed abort gates, the `removalBroadcast`-guarded rollback. Do **not** re-touch. Slice 2 only consumes the already-shipped seam.
- **Receiver-driven repair** (`group_pending_key_repairs` / `GroupPendingKeyRepairRunner`) — untouched; the dedicated table is precisely to avoid disturbing it.
- **Active key-pull / Go grace ring** — out of scope here (that is the 02 self-heal plan's deferred Go work). Slice 2 is Dart-only re-push triggered by a local ML-KEM-key write; no Go rebuild.

---

## 2. Target invariants (the contract Slice 2 must satisfy)

Every Slice-2 test is written against these. INV-D* are new; INV-R* are Slice 1's and **must not regress**.

- **INV-D1 (convergence):** a deferred member recorded at rotation time eventually receives the **promoted** epoch once it has a usable ML-KEM key on an active device. After the drain succeeds for target Y, Y can decrypt a message published at the current epoch, and the pending row is finalized `distributed`.
- **INV-D2 (epoch-monotonic):** the drainer always re-distributes the **current** persisted key (`groupRepo.getLatestKey(groupId)` = `latestKey.keyGeneration`/`latestKey.encryptedKey`), **never** the row's possibly-stale `key_epoch`. A stale-epoch row never resurrects an older key for anyone (consistent with INV-R3). The row's `key_epoch` is provenance/telemetry only.
- **INV-D3 (bounded):** the queue cannot grow or retry unboundedly. Each attempt increments `attempts`; on a configured cap the row is finalized `unreachable` with `last_error` + a flow event, and is no longer scanned. A target whose key never returns does not pin the drainer forever.
- **INV-D4 (idempotent):** enqueuing the same `(group_id, peer_id)` twice is safe — a `UNIQUE(group_id, peer_id)` upsert merges (refreshing `key_epoch`/`updated_at`) rather than duplicating, and re-running the drain over an already-`distributed`/`unreachable` row is a no-op (finalize-once via `WHERE finalized_at IS NULL`). Re-enqueue from a second rotation while a row is still `pending` does not reset `attempts` to mask exhaustion.
- **INV-D5 (security core preserved — MUST NOT REGRESS):** wiring the seam and running the drain never re-adds a removed member, never resurrects an old epoch, and never makes `rotateAndDistributeGroupKey` abort. INV-R1..R5 stay green; the seam is fire-and-forget (an enqueue throw never aborts rotation, preserving `rotate_uc.dart:477-486`).

---

## 3. TDD sessions (decomposed, RED-then-GREEN)

All sessions are TDD: write the RED test(s) first, then the minimal GREEN change. Each session is independently testable. The whole slice mirrors the receiver-repair subsystem (`063` migration / helpers / repo / `GroupPendingKeyRepairRunner`) one-to-one — see the cheat-sheet in §3.6.

### Session D-1 — migration: `group_pending_key_distributions` table + DB version bump

**RED — `test/core/database/migrations/0NN_group_pending_key_distributions_test.dart`** (template: `077_message_relay_custody_test.dart`). FFI setup (`sqfliteFfiInit()` + `databaseFactoryFfi` + `inMemoryDatabasePath`), `setUp` runs no prerequisite (standalone table). Three canonical tests: (1) table + indexes created (assert via `PRAGMA table_info` column set + `PRAGMA index_list`); (2) idempotent (run twice → no error, single table); (3) `UNIQUE(group_id, peer_id)` enforced (duplicate insert raises).

**GREEN — `lib/core/database/migrations/0NN_group_pending_key_distributions.dart`** (template: `063_group_pending_key_repairs.dart`, signature/telemetry per `075`):

```
runGroupPendingKeyDistributionsMigration(Database db) async  // Future<void>, emitFlowEvent START/SUCCESS/ERROR, rethrow
  CREATE TABLE IF NOT EXISTS group_pending_key_distributions (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL,
    peer_id TEXT NOT NULL,
    transport_peer_id TEXT,
    device_id TEXT,
    key_epoch INTEGER NOT NULL,            -- provenance only; drain re-reads getLatestKey
    status TEXT NOT NULL DEFAULT 'pending',-- pending | distributed | unreachable
    attempts INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    finalized_at TEXT,
    UNIQUE(group_id, peer_id)
  );
  CREATE INDEX IF NOT EXISTS idx_gpkd_group_status ON group_pending_key_distributions (group_id, status, created_at);
  CREATE INDEX IF NOT EXISTS idx_gpkd_peer_status   ON group_pending_key_distributions (peer_id, status);
```

**Version-bump wiring (3 touch points, per migration-pattern research):**
- Bump `lib/core/database/app_database_version.dart:1` `currentIdentityDatabaseVersion` 77 → **NN** (next free at landing — see §6 contention; assume **078**).
- `lib/main.dart` `onCreate` tail (~`:454-456`, after `runMessageRelayCustodyMigration`): append `await runGroupPendingKeyDistributionsMigration(db);` + import (`:93`-style).
- `lib/main.dart` `onUpgrade` tail (~`:679-684`): append `if (oldVersion < NN) { await runGroupPendingKeyDistributionsMigration(db); }`. Guards are NOT positionally ordered — append, don't insert.
- **Chain chokepoints (lockstep):** add the migration to both helper chains + the import block in `test/core/database/integration/full_migration_chain_test.dart`, and add the new table to the inventory in `test/features/account_migration/application/migration_database_schema_inventory_test.dart` (the `group_pending_key_repairs` table is already enumerated there — mirror it).

### Session D-2 — DB helpers + model + repository

**RED:**
- `test/core/database/helpers/group_pending_key_distributions_db_helpers_test.dart` (template: `group_pending_key_repairs_db_helpers_test.dart`) — FFI + migration in `setUp`; exercise each plain helper directly (insert returns `created==true` once; second insert merges `key_epoch`/`updated_at`, returns `false`, skips if terminal; pending-only filter; record-attempt increments + gated on `status='pending'`; finalize gated on `finalized_at IS NULL`).
- `test/features/groups/domain/repositories/group_pending_key_distribution_repository_impl_test.dart` (template: `group_pending_key_repair_repository_impl_test.dart`) — repo over the **real** `db*` helpers (FFI + real migration in `setUp`), asserting the `{distribution, created}` upsert result and finalize/record passthrough.

**GREEN — mirror the `063` shape exactly:**
- `lib/core/database/helpers/group_pending_key_distributions_db_helpers.dart` — five plain `Database db`-first functions:
  - `dbUpsertGroupPendingKeyDistribution(db, Map row) → Future<bool>` (manual insert-or-update; `true` only on fresh insert; on existing `pending` refresh `key_epoch`/`transport_peer_id`/`device_id`/`updated_at`; skip if terminal).
  - `dbLoadGroupPendingKeyDistribution(db, id) → Future<Map?>`.
  - `dbLoadPendingGroupKeyDistributions(db, {groupId?, peerId?, limit=50}) → Future<List<Map>>` (`WHERE status='pending' [AND group_id=? / peer_id=?] ORDER BY created_at ASC, id ASC LIMIT`). Provide a `peerId`-scoped variant for the key-arrival trigger (drain only that target's rows) and a `groupId`-scoped variant for resume sweeps.
  - `dbRecordGroupPendingKeyDistributionAttempt(db, id, {lastError, updatedAt})` (`attempts = attempts + 1`, gated `WHERE id=? AND status='pending'`).
  - `dbFinalizeGroupPendingKeyDistribution(db, id, {status, lastError, finalizedAt})` (set status + conditional last_error + updated_at + finalized_at, gated `WHERE id=? AND finalized_at IS NULL`).
- `lib/features/groups/domain/models/group_pending_key_distribution.dart` — `GroupPendingKeyDistribution` (`fromMap`/`toMap`/sentinel `copyWith`); status constants `pending`/`distributed`/`unreachable`; deterministic id builder `groupPendingKeyDistributionId(groupId, peerId)`.
- `lib/features/groups/domain/repositories/group_pending_key_distribution_repository.dart` (+ `_impl.dart`) — interface `GroupPendingKeyDistributionRepository`: `enqueue(GroupPendingKeyDistribution) → GroupPendingKeyDistributionUpsertResult {distribution, created}`, `getDistribution(id)`, `getPendingForPeer({groupId?, peerId, limit})`, `getPendingForGroup({groupId, limit})`, `recordAttempt(id, {lastError})`, `finalizeDistributed(id)`, `finalizeUnreachable(id, {lastError})`. Impl is constructor-injected DB helper **function typedefs** (not raw `Database`); `enqueue` calls the helper then re-loads to return the current row; finalize/record stamp `DateTime.now().toUtc().toIso8601String()` and pick the status const at the repo layer.

### Session D-3 — wire the Slice 1 enqueue seam (3 rotate call sites) + DI

**RED:**
- Extend `rotate_and_distribute_group_key_use_case_test.dart`: with a spy `enqueueDeferredDistribution`, assert it is invoked once per `deferredPeerIds` entry with `(groupId, peerId, newEpoch)` (this seam contract already exists from Slice 1 — the new assertion is that the *production* closure persists a row). Confirm an enqueue throw does **not** abort rotation (INV-D5 / `rotate_uc.dart:477-486`).
- Add a focused test per call site that the production closure writes a `pending` row for each deferred peer (over the in-memory distribution repo fake): the admin-removal path, the leave path, the creator-backstop path.

**GREEN — thread a real `EnqueueDeferredGroupKeyDistribution` into all three sites** (Slice 1 seam map; each closure body is identical, only DI differs):
- **A — `lib/main.dart:2107-2119`** (`rotateGroupKeyAfterRemoteRemoval` closure): main.dart has direct repo access — pass `enqueueDeferredDistribution: ({required groupId, required peerId, required keyEpoch}) async { await groupPendingKeyDistributionRepository.enqueue(GroupPendingKeyDistribution(id: groupPendingKeyDistributionId(groupId, peerId), groupId: groupId, peerId: peerId, keyEpoch: keyEpoch, ...)); }`.
- **B — `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart:193-203`**: add an `EnqueueDeferredGroupKeyDistribution?` param to `broadcastVoluntaryLeave` and forward it into the rotate call; supply the real impl from main.dart's leave wiring.
- **C — `lib/features/groups/presentation/screens/group_info_wired.dart:1056-1070`**: add a widget field `enqueueDeferredDistribution` and thread it through the DI chain (`main.dart → MyApp → StartupRouter → … → OrbitWired → GroupInfoWired`), forwarding into the call.
- **DI (main.dart):** construct `GroupPendingKeyDistributionRepositoryImpl` at the repo region (mirror `group_pending_key_repair` repo ctor ~`:1298-1309`, each typedef closing over module `db` + plain helpers); store on the app object (mirror `:2782`).

### Session D-4 — `GroupPendingKeyDistributionRunner` (the drainer)

**RED — `test/features/groups/application/group_pending_key_distribution_service_test.dart`** (template: `group_pending_key_repair_service_test.dart`; fakes `FakeBridge`, `InMemoryGroupRepository`, a local `_InMemoryGroupPendingKeyDistributionRepository`). Cases:
1. *converges once target keyed* — seed a `pending` row for peer Y at epoch E; group's `getLatestKey` = E (or E+1); Y now has a usable ML-KEM key on an active device. Drive `runner.drainPendingForPeer(groupId, peerId)`. **Assert (INV-D1):** a `group_key_update` envelope targeting Y captured in `bridge.commandLog`/send spy; row finalized `distributed`; the key distributed equals `getLatestKey().encryptedKey`.
2. *still keyless → stays pending* — Y has no usable key on any active device (`_deliverableDevicesForRotation` empty). **Assert:** `recordAttempt` (attempts+1, last_error set), no send, row stays `pending`.
3. *epoch-monotonic (INV-D2)* — seed row with stale `key_epoch = E-2` while `getLatestKey = E`. **Assert:** the **current** key (epoch E) is distributed, never E-2; row's stale epoch never resurrects an old key.
4. *bounded (INV-D3)* — drive until `attempts == cap`; **assert** row finalized `unreachable` with `last_error` + a `GROUP_KEY_DISTRIBUTION_UNREACHABLE` flow event; subsequent drains skip it.
5. *idempotent / finalize-once (INV-D4)* — drain an already-`distributed` row → no-op; double-finalize → second call no-ops (`finalized_at IS NULL` gate).

**GREEN — `lib/features/groups/application/group_pending_key_distribution_service.dart`** (parallel to `GroupPendingKeyRepairRunner`). Deps (required): `bridge`, `groupRepo`, `repository`, `loadIdentity` (or `IdentityRepository`), `sendP2PMessage`, `storeP2PMessageInInbox`; (config): `attemptCap` (default e.g. 8), `perRecipientTimeout`.
- `drainPendingForPeer({groupId, peerId}) → Future<int>` and `drainPendingForGroup({groupId}) → Future<int>` — load pending rows, loop `_drainOne`, return distributed count.
- `_drainOne(row) → Future<bool>` — reconstruct the per-device distribution inputs **at drain time** (the row persisted only `groupId`/`peerId`/`keyEpoch`):
  1. identity/sender keys via `loadIdentity()` → `selfPeerId`(=`sourcePeerId`), `senderPublicKey`, `senderPrivateKey`, `senderUsername`.
  2. `sourceDevice` via `resolveSourceDevice(selfMember: <self entry from getMembers>, senderPublicKey:, sourceDeviceId: null)` (falls to `firstActiveDeviceForSigningKey`).
  3. `member` + `device`: re-read `groupRepo.getMembers(groupId)`, find `peerId == row.peerId`, iterate `deliverableDevicesForRotation(member)` — **the now-keyed devices**. Empty ⇒ `recordAttempt` and return false (stay pending / eventually cap).
  4. `newEpoch`/`newKey` = `groupRepo.getLatestKey(groupId)` → `keyGeneration`/`encryptedKey` (current, INV-D2).
  5. `preTransitionStateHash` = `await buildGroupTransitionStateHash(groupRepo, groupId)` (`signed_group_transition_audit.dart:412`).
  6. `eventAt` = fresh `DateTime.now().toUtc()`.
  - For each deliverable device call the **exposed** `distributeRotatedKeyToDevice(...)` (next bullet). On any-device success → `finalizeDistributed(row.id)` + `GROUP_KEY_DISTRIBUTION_DISTRIBUTED`; on cap → `finalizeUnreachable`; else `recordAttempt` + stay pending.
- **Expose the private helper** — in `rotate_and_distribute_group_key_use_case.dart`, add a package-visible wrapper `distributeRotatedKeyToDevice({...})` that forwards to `_distributeRotatedKeyToDeviceWithRetry` (`:673-723`, so the drain inherits retry; it wraps `_distributeRotatedKeyToDevice` `:725-872`). Signature per the slice1-seam research (bridge/groupRepo/groupId/sourcePeerId/sourceDevice/sender keys/username/member/device/newEpoch/newKey/eventAt/preTransitionStateHash/sendP2PMessage/storeP2PMessageInInbox + `perRecipientTimeout`/`attemptCount`/`retryDelay`). Also expose `resolveSourceDevice` (`:995-1014`) and `deliverableDevicesForRotation` (`:884-893`) as package-visible (or fold their resolution inside the wrapper) so the drainer rebuilds inputs 2-3 without duplicating the keyless/legacy-fallback logic. Keep all of this in `rotate_uc.dart` so the private signing/encrypt chain is not re-exported.

### Session D-5 — drain triggers (ml-kem-key-updated write + app resume)

**RED:**
- `group_message_listener_test.dart` / a focused config-apply test: when an incoming verified group config gives a previously-keyless member a usable ML-KEM key (`saveMember`), the distribution runner is kicked for that `(groupId, peerId)` and the row drains. Use the `_sameDeviceSet` delta (`add_group_member_use_case.dart:57-105`) as the "key actually changed" guard so unrelated `saveMember` writes (username-only, e.g. `handle_incoming_group_message_use_case.dart:631`) do **not** trigger.
- `handle_app_resumed`-level test: a `pending` distribution row drains on resume.

**GREEN — two triggers (mirror the proven `GroupPendingKeyRepairRunner` dual-trigger pattern):**
1. **Event trigger (promptness) — the member-key-arrival write.** The group analogue of the contact-key hook is the config-apply `saveMember`:
   - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart:934-943` (`GroupMember.fromConfigMap` → `saveMember`) — primary site a remote member's `mlKemPublicKey`/`devices` first land.
   - `lib/features/groups/application/add_group_member_use_case.dart:311` — guard with the `_sameDeviceSet` (`:57-105`) delta.
   - Thread a `drainDeferredDistributionsForPeer(groupId, peerId)` callback (mirrors `retryPendingGroupKeyRepairs` wired at `main.dart:2236-2237`) and fire it after the key-bearing `saveMember`. (The contact-side 1:1 analogue is `handle_incoming_message_use_case.dart:353` `HandleMessageResult.contactKeyUpdated`; group members do **not** use `ml_kem_key_updated_ts`, so the group trigger is the `saveMember` device-set delta, not the `075` contacts column.)
2. **Catch-all — app resume.** Thread the runner into `handleAppResumed` (`lib/core/lifecycle/handle_app_resumed.dart`, wired at `main.dart:3636`, alongside `pendingKeyRepairRepo` `:3649`) so a `drainPendingForGroup` sweep runs on every `AppLifecycleState.resumed` (`main.dart:3554-3555`) — covering writes that happened while backgrounded or with the app dead. (Note from research: the resume path does **not** already call any distribution drain; this hook must be added.)
- **DI:** construct `GroupPendingKeyDistributionRunner` once (mirror `group_pending_key_repair` runner ctor ~`:2173-2184`), store on the app object, hand its `drainDeferredDistributionsForPeer` to the key-arrival sites and its `drainPendingForGroup` to `handleAppResumed`.

### 3.6 Repair → distribution mirror cheat-sheet

| Receiver-repair subsystem (existing) | New distribution subsystem (Slice 2) |
|---|---|
| `063_group_pending_key_repairs.dart` / `runGroupPendingKeyRepairsMigration` | `0NN_group_pending_key_distributions.dart` / `runGroupPendingKeyDistributionsMigration` |
| `group_pending_key_repairs_db_helpers.dart` (5 plain fns) | `group_pending_key_distributions_db_helpers.dart` (5 plain fns) |
| `GroupPendingKeyRepair` model + 3 status consts | `GroupPendingKeyDistribution` model + `pending`/`distributed`/`unreachable` |
| `GroupPendingKeyRepairRepository(Impl)` + `{repair, created}` | `GroupPendingKeyDistributionRepository(Impl)` + `{distribution, created}` |
| `GroupPendingKeyRepairRunner.retryPendingRepairsForKey/_retryOne/_finalizeUndecryptable` | `GroupPendingKeyDistributionRunner.drainPendingForPeer/_drainOne/finalizeUnreachable` |
| `currentIdentityDatabaseVersion = 77` | bump to **NN** + `onCreate` line + `onUpgrade (oldVersion < NN)` |
| Drain on `saveKey` (`group_key_update_listener.dart:524→534`) | Drain on member-key-arrival `saveMember` + app resume |
| `main.dart:1298` repo ctor, `:2173` runner ctor, `:2236` listener wiring | same three insertion points + the seam at the 3 rotate call sites |

---

## 4. Test & verification strategy (summary)

**Unit:** D-1 migration schema/idempotency/UNIQUE; D-2 helpers + repo over real FFI DB; D-4 runner (converge / stay-pending / epoch-monotonic / bounded / idempotent). Decisive cases: INV-D1 convergence, INV-D2 stale-epoch never resurrects, INV-D3 cap → `unreachable`, INV-D4 finalize-once.

**Integration (this repo):**
- `group_membership_smoke_test.dart` — **"remove with a keyless bystander → bystander converges after key-updated drain"**: admin removes X, remaining member Y keyless; assert (Slice 1, retained) X durably excluded + no rollback + epoch promoted + a `pending` distribution row for Y; then Y gains a usable ML-KEM key (config-apply `saveMember`), the trigger fires `drainDeferredDistributionsForPeer`, the row finalizes `distributed`, and Y can decrypt at the current epoch.
- `group_recovery_e2e_test.dart` — extend so an **ML-KEM-regenerated** member is the keyless bystander while a third member is removed; assert convergence after the regenerated key lands.
- Regression: `leave_group_use_case_test.dart`, `rotate_and_distribute_group_key_use_case_test.dart`, full groups suite stay green (INV-D5 / INV-R1..R5).

**Negative / security assertions (must hold — Slice 1 carried forward):** after removal X cannot decrypt at the new epoch (any bystander key state); `_rollbackFailedMemberRemoval` never runs once `member_removed` is published; the drain never resurrects an old epoch for X or anyone (INV-D2).

**Inventory/gates:** add a `test-inventory.md` row + `test-gate-definitions.md` gate for "keyless remaining member converges onto the promoted epoch after re-key."

---

## 5. Simulator / device verification (MANDATORY)

**New sim proof file:** `integration_test/group_removal_rotation_keyless_converge_proof_test.dart` — `@Tags(['device'])` + `library;`, modeled directly on the Slice 1 `integration_test/group_removal_rotation_keyless_proof_test.dart` and the ML-007 `group_real_crypto_onboarding_test.dart`. Single booted sim, one **real `GoBridgeClient`**, real Go ML-KEM-768 + AES-GCM. Harness shape: `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`; `setUp: bridge = GoBridgeClient(); await bridge.initialize();`; `tearDown: bridge.dispose();`; real `_generateIdentity` (`identity.generate` + `mlkem.keygen`), real `_groupEncrypt`/`_groupDecryptRaw` (`group.encrypt`/`group.decrypt`).

**Scenario (extends the Slice 1 proof past where it stops — Carol records deferred but never converges):**
1. `_generateIdentity` Alice(admin) + Bob(keyed, to-be-removed) + **Carol keyless** (`mlKemPublicKey: null`). `InMemoryGroupRepository` + the new in-memory distribution repo fake.
2. `createGroup(alice)`, `addGroupMember(bob)`, `saveMember(carol, mlKemPublicKey: null)`. `epoch1 = getLatestKey`; capture `bobRetainedKey`. `removeMember(bob)`.
3. **Rotate with the Slice 2 seam** — `rotateAndDistributeGroupKey(... enqueueDeferredDistribution: pendingRepo.enqueue, sendP2PMessage: spy)`. Assert `outcome.rotated && !fullyDistributed`, `deferredPeerIds == [carol.peerId]`, exactly one `pending` row for `(groupId, carol.peerId, epoch2)`, `epoch2.keyGeneration == epoch1+1`.
4. **Carol gains a REAL key** — `bridge.send({'cmd':'mlkem.keygen'})`; `saveMember(carol with carolKey.publicKey)` (now deliverable).
5. **Drain** — `runner.drainPendingForPeer(groupId, carol.peerId)` (or `drainDeferredDistributionsForPeer`) with the `sendP2PMessage` spy capturing Carol's envelope. Assert the row is cleared (`distributed`) and the spy targeted Carol's transport peer; the **current** epoch (epoch2) was distributed, not the stale row epoch (INV-D2).
6. **Convergence with real crypto** — `group.encrypt` `'post-removal new-epoch message'` under `epoch2.encryptedKey`; decrypt Carol's captured key-update envelope to recover her epoch2 key copy; `group.decrypt` the message under it and assert plaintext matches → formerly-keyless Carol now reads new-epoch traffic (INV-D1). Slice 1 negative invariant retained: `group.decryptRaw(bobRetainedKey, cipher)['ok'] != true`.

**Exact run commands (concrete available iOS simulators by device ID; `.xcframework` / `.aar` already built — no `make all`/`pod install` needed):**
```
# Primary target — iPhone 17 Pro
flutter test integration_test/group_removal_rotation_keyless_converge_proof_test.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469

# Or via the gate runner (threads -d $FLUTTER_DEVICE_ID, one integration file at a time)
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh <new-converge-gate>
```
Add **both** the Slice 1 (`group_removal_rotation_keyless_proof_test.dart`) and this Slice 2 file to the transport/real-crypto gate list in `scripts/run_test_gates.sh` (currently only `group_real_crypto_onboarding_test.dart` is listed ~`:118`; integration files run one at a time ~`:278-284`, device threaded ~`:244-247`).

**Multi-device variant (follow-on, optional):** a two-real-node convergence run using the UP004 sims — Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C` — where the keyless bystander is a *separate device* that regenerates its ML-KEM key and converges over the real relay (mirrors the Slice 1 Pixel 6 / iPhone 13 field run). The single-sim in-process proof above is the gating one; this multi-device run is corroboration.

---

## 6. Risks, trade-offs & rollout

- **Migration-number contention (CONFIRMED ≥4-way).** `078` is the next free integer (latest on disk is `077_message_relay_custody.dart`), but four PLAN-ONLY docs all eye it: this Slice 2 (`078_group_pending_key_distributions`), the [02 undecryptable self-heal plan](./02-P0-undecryptable-messages-self-heal-TDD-plan.md) (`078_group_pending_key_repairs_status_index`), the [09 media bounded+honest plan](./09-P1-media-bounded-and-honest-TDD-plan.md) (`078_media_attachment_download_retry_column`), and the [10 reaction reliability plan](./10-...) (`078_group_pending_reactions`). **The integer is reserved only by the file existing + the `app_database_version.dart` bump + the `onUpgrade` guard merging — not by a plan naming it.** Authoring rule: at implementation time re-derive `NN = max(existing NNN files) + 1`; whichever lands first takes **078**, second **079**, third **080**, fourth **081**. Reconcile `full_migration_chain_test.dart` (both helper chains + imports) and `migration_database_schema_inventory_test.dart` in lockstep.
- **Backlog never drains for a permanently-gone target (bounded — accepted):** if a deferred member's ML-KEM key never returns, the row retries up to `attemptCap` then finalizes `unreachable` with a flow event and is no longer scanned (INV-D3). It can be re-enqueued by a later rotation. This is the correct posture for a *best-effort* convergence of an already-authorized insider; it never affects the removed-member security boundary.
- **Weaker fan-out atomicity (accepted, unchanged from Slice 1):** insiders may briefly read old-epoch traffic until the drain reaches them. Forward secrecy for the *removed* member (Slice 1) outranks synchronous convergence for insiders, who already held the old key.
- **Seam fire-and-forget (INV-D5):** an enqueue throw must never abort rotation — the production closure runs inside the existing try/catch (`rotate_uc.dart:477-486`); a drain failure is logged and retried, never propagated into the rotate caller.
- **Trigger noise:** the member-key-arrival hook must use the `_sameDeviceSet` delta to avoid firing on username-only `saveMember` writes; the resume sweep is bounded by the pending-row scan. No periodic timer is added.
- **Rollout order:** Slice 1 is **done + device-verified** — Slice 2 lands after, behind its own migration coordination. D-1 → D-2 → D-3 (seam wiring) → D-4 (runner) → D-5 (triggers) → sim proof. Each session independently testable; the seam is already shipped (no-op), so D-3 is a pure default-swap.

## 7. Open questions

- **OQ-1 (table strategy):** dedicated `group_pending_key_distributions` (recommended — §1.1, clean separation from the decryption-specific repair `_retryOne`) vs status-overload `group_pending_key_repairs`. Recommendation: dedicated.
- **OQ-2 (drain trigger):** member-key-arrival `saveMember` hook (prompt) vs resume-only (simpler). Recommendation: both — key-arrival for promptness, resume as catch-all (matches the proven `GroupPendingKeyRepairRunner` dual trigger).
- **OQ-3 (attempt cap value):** the repair runner has **no** numeric cap (key-presence gate only). Slice 2 adds one (default ~8) for boundedness. Confirm the cap + whether a permanently-`unreachable` row should be auto-re-enqueued by the next successful rotation (recommended: yes, the rotate seam naturally re-upserts via `UNIQUE(group_id, peer_id)`).
- **OQ-4 (migration number):** re-derive at landing (§6); do not hard-code `078` from this plan.

## 8. Effort estimate

**Medium.** D-1 migration + version wiring + chain reconciliation (~0.5 day); D-2 helpers/model/repo (mirror `063`, ~0.5–1 day); D-3 seam wiring across 3 call sites + DI threading (~0.5 day, the GroupInfoWired thread is the fiddly part); D-4 runner + exposing the 3 private rotate helpers (~1 day); D-5 triggers + resume hook (~0.5 day); sim proof + gate wiring (~0.5–1 day, the long pole per harness constraints). Total ~3.5–4.5 focused days. Lower-stakes than Slice 1 (best-effort convergence, no security gate), but carries the DB-version coordination cost.
