> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P0** · TDD plan for **[03-P0-removal-rotation-fails-closed.md](./03-P0-removal-rotation-fails-closed.md)**

---

# TDD Plan — Make admin member-removal durable & security-correct

**Status: PLAN ONLY.** Decomposed for TDD execution. Verified against HEAD `124-harness-refactor` (commit `41061593`).

> Companion to the [finding](./03-P0-removal-rotation-fails-closed.md). The finding describes *what's wrong*; this plan describes *how to fix it test-first, in shippable slices, in the right order, with the already-landed parts carved out so they are not re-touched.*

---

## 0. Resolution verification (is the finding still open?)

**Partially.** A graph-first verification + adversarial cross-check pass (17 agents, verify→refute→synthesize) plus an independent source read scored the finding's three sub-paths as **diverged**: the **voluntary-leave** half was fixed by the H-01 / non-admin-leave work (commit `576dc41e`, 2026-06-15); the **admin-removal** half — the primary P0 — is **fully live and untouched**; the proposed **deferred-distribution** infrastructure is **absent**.

| Claim | Finding thesis | Status (HEAD) | Anchor proof |
|---|---|---|---|
| **C1** | rotation hard-aborts on a keyless remaining member | **STILL-LIVE** | `if (undeliverableMembers.isNotEmpty) { … return null; }` — `rotate_and_distribute_group_key_use_case.dart:155-168`, runs **before** key generation (`:230`) and local promotion (`:336-358`) |
| **C2** | the gate keys on ML-KEM key *presence*, not reachability | **STILL-LIVE** | `_hasUsableMlKemPublicKey` = `value != null && value.trim().isNotEmpty` (`:757-758`); `_deliverableDevicesForRotation :746-755`; `_undeliverableActiveMembers :736-744` |
| **C3** | return type conflates "couldn't fan out" with "true failure" | **STILL-LIVE** | signature still `Future<GroupKeyInfo?>` (`:29`); 12× `return null` for both genuine-failure and fan-out-incomplete (`:331`) |
| **C4** | rollback re-adds removed member + re-publishes a config including them | **STILL-LIVE (core P0)** | `_rollbackFailedMemberRemoval` re-`saveMember(removedMember)` (`group_info_wired.dart:818-820`) + `callGroupUpdateConfig(buildGroupConfigPayload(restoredGroup, restoredMembers))` (`:834-841`); **no `removalBroadcast` guard** |
| **C5** | `_onRemoveMember` throws on null rotation → catch rolls back | **STILL-LIVE** | `if (rotatedKey == null) throw StateError(group_info_rotate_key_failed)` (`:1065-1069`); catch fires `_rollbackFailedMemberRemoval` whenever `localRemovalAccepted` (`:1076-1080`), which is always true by then (`:897`) |
| **C6** | voluntary-leave broadcasts then throws on rotation → split-brain | **RESOLVED** | best-effort: `rotationDeferred = rotatedKey == null`, no throw, returns `VoluntaryLeaveBroadcastResult(didBroadcast: true)` (`broadcast_voluntary_leave_use_case.dart:190-231`) |
| **C7** | `_onLeave` skips local cleanup on rotation failure | **RESOLVED** | `leaveGroup` + `deleteMessagesForGroup` run unconditionally (`group_info_wired.dart:363-369`); catch rolls back only on native `group:leave` failure (`_isNativeLeaveFailure :728-729`), and that rollback restores **only the leaver's own key window**, never re-adds a member |
| **C8** | reuse repair infra for sender-side deferred distribution | **ABSENT** | repair system is purely receiver-driven (2 upsert sites, both decrypt-failure); statuses `pending_key`/`repaired`/`undecryptable` only (`group_pending_key_repair.dart:1-3`); `pending_distribution` = 0 matches |

**Decisive nuance the H-01 fix did *not* close (verified, not in the original finding):**

1. **The admin-removal path was never touched.** H-01's diff (`576dc41e`) does not reference `_onRemoveMember`, `_rollbackFailedMemberRemoval`, or `localRemovalAccepted` (grep = 0). The leave path got `rotationDeferred`; the removal path still throws-and-rolls-back.
2. **`removeGroupMember` does not rotate** (grep for `rotate`/`generateNextKey`/`saveKey` = 0). It only DB-removes the member (`:203`) and pushes a member-excluded Go config (`:214`). So `rotateAndDistributeGroupKey` is the **sole** mechanism that revokes the live key — and it aborts on keyless members. When it aborts, *nothing* rotated.
3. **The voluntary-leave forward-secrecy backstop reuses the same aborting primitive.** `_maybeRotateGroupKeyAfterRemoteRemoval` (`group_message_listener.dart:3338-3403`) calls `rotateAndDistributeGroupKey` → so even the *leave* path's creator re-key silently no-ops when a keyless bystander exists (caught + logged `…_SKIPPED`, `:3382-3402`). Fixing the primitive (Slice 1) therefore *also* hardens the already-shipped leave backstop.
4. **There is no key-pull anywhere.** The receiver-driven repair's production wiring is `requestGroupKeyRepair: emitGroupKeyRepairRequest` (`main.dart:1992` ×8), and that function only emits a flow event (`group_pending_key_repair_service.dart:58-69`). The runner retries **decryption** once a key is already local (`_retryOne` → `decryptGroupOfflineReplayEnvelope`, `:450`); it never fetches a key. So a keyless bystander has **no existing convergence path** — confirming C8 is genuinely needed for full convergence (Slice 2), and that Slice 1 alone leaves keyless insiders temporarily unable to read new-epoch traffic (acceptable — they were already broken; the *removed* member is what must be excluded).

**The exact live failure (admin removes X; a different remaining member Y is keyless):**
`removeGroupMember` excludes X locally + in Go config → `member_removed` is **published** to the group (`:972`) → `rotateAndDistributeGroupKey` hits `_undeliverableActiveMembers = [Y]` → `return null` (`:167`) **before generating any new epoch** → `_onRemoveMember` throws (`:1066`) → catch runs `_rollbackFailedMemberRemoval` (`:1080`) → X is **re-saved** and the Go config is **re-published including X** (`:837-841`). Net: the new epoch was never generated, so the live key is unchanged and **X still holds it**; X is **restored to membership**; remaining members already saw `member_removed` → roster split-brain. Both halves of the security invariant are violated.

---

## 1. Critical assessment & scoping decision

The finding bundles a **security-correctness fix** and a **convergence feature** under one P0. They must not ship as one block, and one of the three sub-paths is already done:

- **Security core (must, durable):** the removed member loses the live key *unconditionally*, and the rollback *never* re-grants them. This is the P0. It is achievable **Dart-only**, **no migration**, **no Go rebuild**, and is independently shippable and testable.
- **Convergence (best-effort, deferred):** keyless/undelivered *remaining* members eventually get the new epoch. This needs **new sender-side infrastructure** (a migration + drain trigger) and is *not* a security gate — deferred insiders keep reading old-epoch traffic (which they already could) until repaired. The finding itself sequences this last.
- **Voluntary-leave (DONE):** carved out entirely — see §1.2.

**The non-obvious coupling that drives ordering:** the security core has two halves that are only safe *together*. Making rotation "promote-then-defer" (so X loses the key even with a keyless Y) is useless if the caller still **rolls back and re-adds X** on the now-rare genuine failure; and making the rollback safe is useless if rotation still **aborts** and returns the same `null` it does today. So Slice 1 is a **single coherent slice**: the primitive change (Phase R-1) and the caller change (Phase R-2) ship together, gated on the same security assertions.

### 1.1 Recommended scope

- **Slice 1 (this plan, execution-ready): the security core** — `R-1` (rotation promote-then-defer + `RotateGroupKeyOutcome`) → `R-2` (admin caller: no-throw + `removalBroadcast`-guarded rollback). Dart-only, no migration, no Go rebuild. Delivers the entire P0 *security* fix. After Slice 1, a keyless bystander no longer blocks (or reverses) a removal.
- **Slice 2 (specified, deferred): convergence** — `R-3` (sender-side deferred distribution + drain trigger). Adds a migration and a runner; lands *after* Slice 1 is device-verified. Without it, keyless bystanders are temporarily on the old epoch (degraded read, not a security hole).

This matches the finding's own rollout order ("land use-case + tests first … then flip `group_info_wired` … each step independently testable") and the repo's security-first convention.

### 1.2 Explicitly OUT OF SCOPE — do **not** re-touch (already landed, verified)

- **Voluntary-leave path (C6, C7):** `broadcastVoluntaryLeaveAndRotateKey` best-effort rotation + `rotationDeferred`; `_onLeave` unconditional `leaveGroup`/`deleteMessagesForGroup`; leave-only rollback `_rollbackFailedVoluntaryLeave`/`_restoreFailedLeaveKeyWindow` (restores key window, never re-adds a member). Landed H-01 / non-admin-leave (commit `576dc41e`).
- **Creator-driven leave backstop wiring:** `RotateGroupKeyAfterRemoteRemoval` typedef + `_maybeRotateGroupKeyAfterRemoteRemoval` + `main.dart` wiring exist. Slice 1 *improves* it for free (it calls the fixed primitive); its residual *timing* weakness (offline/non-creator-admin → no rotate) is a separate, lower-priority follow-up, **not** this P0.

**Regression obligation:** because both the admin-removal caller *and* the leave caller (directly and via the creator backstop) call `rotateAndDistributeGroupKey`, every change to that primitive's return/abort semantics in R-1 **must** keep the leave path green. Both callers are updated in lock-step with the signature change.

---

## 2. Target invariants (the contract Slice 1 must satisfy)

These are the assertions every Slice-1 test is written against. They are the finding's "negative / security assertions" made executable:

- **INV-R1 (durable exclusion):** after `_onRemoveMember(X)` returns, regardless of any remaining member's key state, a new epoch has been **generated, promoted, and persisted** locally (`groupRepo.getLatestKey` advanced) and **X is not in its recipient set**. X cannot decrypt a message published at the new epoch.
- **INV-R2 (no re-grant):** `_rollbackFailedMemberRemoval` is **never** invoked once `member_removed` has been published. After the broadcast, X is gone from local DB and Go config and stays gone; no path re-`saveMember(X)` or re-publishes a config containing X.
- **INV-R3 (monotonic epoch):** rotation only ever advances the epoch; a keyless bystander or a failed delivery never causes an old epoch to be resurrected for X or anyone.
- **INV-R4 (rotated ≠ fully-distributed):** the use case returns `rotated == true` whenever the epoch was promoted, even if some remaining members are deferred; `key == null` (`rotated == false`) occurs **only** when the epoch could not be promoted (genuine generate/promote failure).
- **INV-R5 (leave path unchanged):** the voluntary-leave caller and the creator backstop continue to treat a non-rotated outcome as `rotationDeferred` and complete local cleanup; no leave-path test regresses.

---

## 3. Slice 1 — security core (execution-ready, Dart-only, no migration)

All sessions are TDD: write the RED test(s) first, then the minimal GREEN change.

### Session R-0 (prep) — introduce `RotateGroupKeyOutcome`, keep behavior byte-identical

**Why first:** the return-type change (C3) is the compiler-enforced spine that lets R-1 and R-2 distinguish "deferred" from "failed". Landing it as a pure refactor (no behavior change) de-risks the two behavioral sessions.

**GREEN edits (no RED — pure refactor, existing tests are the guard):**
- New value object in `rotate_and_distribute_group_key_use_case.dart` (or a sibling `rotate_group_key_outcome.dart`):
  ```dart
  class RotateGroupKeyOutcome {
    final GroupKeyInfo? key;            // non-null iff a new epoch was promoted + saved locally
    final int distributedDeviceCount;  // device targets that confirmed delivery (direct or inbox)
    final List<String> deferredPeerIds; // remaining members NOT delivered now (keyless OR delivery-failed)
    const RotateGroupKeyOutcome({this.key, this.distributedDeviceCount = 0, this.deferredPeerIds = const []});
    bool get rotated => key != null;
    bool get fullyDistributed => deferredPeerIds.isEmpty;
    static const notRotated = RotateGroupKeyOutcome();
  }
  ```
- Change the signature `Future<GroupKeyInfo?>` → `Future<RotateGroupKeyOutcome>` (`:29`). For this session ONLY, preserve exact current behavior: every `return null` → `return RotateGroupKeyOutcome.notRotated;`, and the success `return keyInfo;` (`:422`) → `return RotateGroupKeyOutcome(key: keyInfo, distributedDeviceCount: distributionTargets.length, deferredPeerIds: const []);`. **The abort gates at `:155-168` and `:320-332` are NOT touched yet** — they still `return notRotated`.
- Update both call sites to the equivalent of their old null-check:
  - `group_info_wired.dart:1050` — `final outcome = await …; final rotatedKey = outcome.key; if (rotatedKey == null) throw …` (behavior identical).
  - `broadcast_voluntary_leave_use_case.dart:193` — `final outcome = await …; rotatedKey = outcome.key; rotationDeferred = !outcome.rotated;` (behavior identical).
  - `main.dart:1993-2014` `rotateGroupKeyAfterRemoteRemoval` callback — `return (await rotateAndDistributeGroupKey(...)).rotated;` (was `rotated != null`).
- **Gate:** `rotate_and_distribute_group_key_use_case_test.dart`, `remove_group_member_use_case_test.dart`, `leave_group_use_case_test.dart`, and the groups smoke suite stay green with zero behavior change. Mechanically reconcile any test that asserted on the raw `GroupKeyInfo?` return to read `.key`.

---

### Session R-1 — rotation: promote-then-defer (Phase 1, the revocation fix)

**Root cause C1/C2 (§ finding).** The undeliverable gate aborts the entire rotation *before* the epoch is generated, so a keyless bystander prevents the removed member from losing the key.

**RED tests (write first) — `rotate_and_distribute_group_key_use_case_test.dart`:**
1. *"keyless remaining member no longer aborts the rotation"* — group {self(creator), X(removed-already-excluded by caller in real flow; here: members = self + Y), Y with **empty `mlKemPublicKey`** on every device}. Call rotate. **Assert:** result `rotated == true`; `groupRepo.getLatestKey` advanced by one epoch; the promoted key was `saveKey`'d (fake records it); `deferredPeerIds == [Y.peerId]`; **`callGroupGenerateNextKey` was invoked** (today it is not reached). This RED test fails on HEAD at `:167`.
2. *"mixed cohort: keyed-online direct, keyed-offline inbox, keyless deferred"* — members self + A(keyed, send succeeds) + B(keyed, direct times out → inbox stores) + C(keyless). **Assert:** epoch promoted; A delivered direct; B delivered via inbox fallback; `deferredPeerIds == [C]`; `distributedDeviceCount == 2`.
3. *"delivery failure to a keyed member defers instead of aborting"* — member A keyed but both direct send AND inbox store fail. **Assert:** epoch still promoted (`rotated == true`); `A ∈ deferredPeerIds`; **no `return notRotated`** (this RED test fails on HEAD at `:331`).
4. *"genuine failure still returns notRotated"* — `callGroupGenerateNextKey` returns `ok:false` (or epoch mismatch, or `callGroupUpdateKey` promote throws). **Assert:** `rotated == false`; `getLatestKey` **unchanged**; nothing deferred-enqueued. (Guards INV-R4: only true promote failure is `null`.)
5. *"deferred peers are enqueued through the injected seam"* — inject a spy `enqueueDeferredDistribution`; assert it is called once per `deferredPeerIds` entry with `(groupId, peerId, newEpoch)`, and a `GROUP_ROTATE_KEY_DEFERRED_REPAIR_QUEUED` flow event fires per peer + one `GROUP_ROTATE_KEY_PARTIAL_DISTRIBUTION` summary. (In Slice 1 the seam default is a no-op; Slice 2 supplies the real impl.)

**GREEN edits — `rotate_and_distribute_group_key_use_case.dart`:**
- **Remove the abort at `:155-168`.** Replace with: compute `deferredPeers = _undeliverableActiveMembers(...)` (rename to `_keylessRemainingMembers` for clarity), emit nothing fatal, **continue**.
- Build `distributionTargets` as today (`:170-181`) — keyless members are naturally absent (they have no deliverable device).
- **Transport-unavailable (`:183-193`):** instead of `return notRotated` when `sendP2PMessage == null`, treat all `distributionTargets` members as deferred and continue to promotion. (Edge case; production removal always supplies transport — `group_info_wired.dart:1058`. Document it.)
- Generate / reuse-draft unchanged (`:202-270`); genuine failures still `return notRotated`.
- Distribute best-effort (loop `:282-315`) — collect, per member, whether **any** of its device targets succeeded. Members with zero successful device deliveries join `deferredPeers`.
- **Remove the abort at `:320-332`.** Replace with telemetry (`GROUP_ROTATE_KEY_DISTRIBUTION_INCOMPLETE` is fine) + fold failed members into `deferredPeers`; **do not return.**
- **Promote unconditionally** (`callGroupUpdateKey :336-350` + `saveKey :358` + `clearPendingKeyRotation :359`) — gated only on "key generated". A `callGroupUpdateKey` throw here is the *only* thing that yields `notRotated` after generation (INV-R4). **Promotion stays after distribution** so reachable members typically hold the key before the admin switches; the change is that promotion is no longer *conditional* on distribution success.
- **Enqueue deferred:** after promotion, for each `deferredPeers` member call the injected `enqueueDeferredDistribution` seam (new optional param, default no-op) + emit the per-peer/summary flow events.
- Broadcast `key_rotated` unchanged (`:367-410`).
- Return `RotateGroupKeyOutcome(key: keyInfo, distributedDeviceCount: <count of delivered device targets>, deferredPeerIds: deferredPeers.map(peerId))`.

**Migration:** none. **Go rebuild:** none. **Coupling:** the leave caller + creator backstop now get unconditional promotion for free — **add a leave-path regression test** (creator leaver with a keyless bystander → epoch promoted, `rotationDeferred == false`). **Risk:** the promote-then-defer order means a remaining keyed member whose delivery raced a failure is briefly on the old epoch; the receiver decrypt-retry runner already heals that once the key lands (and Slice 2 actively re-pushes).

---

### Session R-2 — admin caller: no-throw on partial, `removalBroadcast`-guarded rollback (Phase 2)

**Root cause C4/C5 (§ finding).** The catch rolls back unconditionally, re-granting X.

**RED tests (write first):**

- **`remove_group_member_use_case_test.dart` / `group_membership_smoke_test.dart`** (whichever hosts the wired `_onRemoveMember` harness; if `_onRemoveMember` is only reachable as a widget method, add a focused widget test in `group_info_wired_test.dart` mirroring the leave-path widget tests):
  1. *"removal with a keyless bystander is durable (no rollback, no re-grant)"* — admin removes X; remaining member Y keyless. With R-1 in place rotation returns `rotated == true, deferredPeerIds:[Y]`. **Assert (INV-R1/R2):** X absent from `groupRepo.getMembers` *and* from the last `callGroupUpdateConfig` payload; `_rollbackFailedMemberRemoval` **never ran** (spy / no `saveMember(X)`); a **non-fatal** partial-distribution SnackBar shown (not the error path); epoch advanced.
  2. *"genuine rotation failure after broadcast does NOT roll back"* — force `rotated == false` *after* `member_removed` published (e.g. `callGroupUpdateKey` promote throws). **Assert (INV-R2):** X stays removed locally + in Go config (no re-add/re-publish); a retry-able warning surfaced/flow event emitted; `_rollbackFailedMemberRemoval` not called.
  3. *"pre-broadcast failure still rolls back (legitimate)"* — force a failure *before* the publish (e.g. `removeGroupMember` Go config throws, or publish returns `ok:false` at `:986`). **Assert:** `_rollbackFailedMemberRemoval` **is** called (since `member_removed` never went out) and restores state — the only case where re-adding X is correct.
  4. *"fully-distributed removal shows no warning"* — all remaining members keyed+online → `fullyDistributed == true` → success, no SnackBar, X excluded.

**GREEN edits — `group_info_wired.dart`:**
- Add `var removalBroadcast = false;` alongside `localRemovalAccepted` (`:861`). Set `removalBroadcast = true;` immediately after the publish succeeds (`:986`, in the `else` of the `ok != true` check).
- Replace the rotation handling (`:1050-1069`):
  ```dart
  final outcome = await rotateAndDistributeGroupKey(...);
  if (!outcome.rotated) {
    // Removal already broadcast + committed. The re-key is best-effort/retryable.
    // Do NOT throw into the re-add rollback (INV-R2). Surface a retryable warning.
    emitFlowEvent(layer:'FL', event:'GROUP_INFO_FL_REMOVE_REKEY_DEFERRED', details:{...});
    _showRemoveRekeyDeferredWarning(); // non-fatal; removal stands
  } else if (!outcome.fullyDistributed) {
    _showPartialDistributionWarning(); // non-fatal; new l10n
  }
  ```
- **Guard the rollback** at the catch (`:1076`): `if (localRemovalAccepted && !removalBroadcast && preRemovalGroup != null && preRemovalMember != null) { … _rollbackFailedMemberRemoval(…); }`. After the broadcast, the catch falls through to telemetry + (non-re-adding) error SnackBar only.
- New l10n key `group_info_remove_member_partial_distribution` (+ `ar`/`de` + regenerated `app_localizations*.dart`), e.g. *"Member removed. Some members will receive the new key when they reconnect."* Retain `group_info_rotate_key_failed` only for the genuine pre-broadcast failure SnackBar (or repurpose to the deferred-rekey warning).

**Migration:** none. **Coupling:** must land with R-1 (depends on `RotateGroupKeyOutcome`). **Risk:** the "genuine failure after broadcast" residual = X keeps the *old* key until a later successful rotation (forward-secrecy delayed, **never** re-granted). Slice 2's queue is the convergence backstop for that residual; document it as accepted.

**Slice 1 gate:** `rotate_and_distribute_group_key_use_case_test.dart` + `remove_group_member_use_case_test.dart` + `group_membership_smoke_test.dart` + `leave_group_use_case_test.dart` + full groups suite green (`-j 1` if shared-gate flake applies); `flutter analyze` no new issues. Device proof in §5.

---

## 4. Slice 2 — convergence: sender-side deferred distribution (specified, deferred)

**Root cause C8 (§ finding).** No mechanism re-pushes the new epoch to a member who was keyless at rotation time. After Slice 1 they sit on the old epoch until an unrelated future rotation. This slice drains them.

### Session R-3 — `group_pending_key_distributions` + drain trigger

**Recommended design (OQ-1): a dedicated table, not a status-overload of `group_pending_key_repairs`.** The repair table stores a *replay envelope* and retries *decryption* (`_retryOne` is decryption-specific); a sender-distribution row stores no envelope and retries *distribution*. Overloading one table with two opposite directions (receiver-pull vs sender-push) and incompatible `_retryOne` semantics is the "status overload proves confusing" case the finding flags. A dedicated table keeps the receiver-repair invariants untouched.

- **Migration `078_group_pending_key_distributions.dart`** (verify next free number at implementation — `077` is the latest; the [02 self-heal plan](./02-P0-undecryptable-messages-self-heal-TDD-plan.md) also eyes `078`, so coordinate landing order) → bump DB version to v78. Columns: `id TEXT PK`, `group_id`, `target_peer_id`, `target_transport_peer_id`, `target_device_id`, `key_epoch INTEGER`, `attempts INTEGER DEFAULT 0`, `last_error TEXT`, `created_at`, `finalized_at`. Index on `(group_id)` and a status-leading scan for the drainer.
- **DB helpers** `group_pending_key_distributions_db_helpers.dart` + repository (mirror the `063`/repair shape): `enqueue`, `getPending`, `recordAttempt`, `finalize`.
- **Wire the seam** introduced in R-1: `enqueueDeferredDistribution` → repository `enqueue`. DI thread through `main.dart`.
- **Drainer** `GroupPendingKeyDistributionRunner` (parallel to `GroupPendingKeyRepairRunner`): for each pending row, if the target now has a usable ML-KEM key on an active device, distribute the **current persisted** key for the group via an exposed `distributeRotatedKeyToDevice` (make `_distributeRotatedKeyToDevice` package-visible or expose a thin wrapper); on success `finalize`; on attempt-cap exhaustion `finalize` as `unreachable` + flow event.
- **Trigger:** the natural signal already exists — **migration `075_contacts_ml_kem_key_updated_ts`** records when a member's ML-KEM key changes. Drain on: (a) that key-updated write, (b) app resume, (c) the same periodic/resume triggers that already drive `retryPendingRepairsForKey`. (OQ-2: prefer hooking the key-updated write for promptness vs piggy-backing resume for simplicity.)

**RED tests:** `group_pending_key_distributions` enqueue/query; drainer distributes once target gains a usable ML-KEM key then finalizes; attempt-cap finalizes `unreachable`; epoch monotonic (a stale-epoch row never resurrects an old key — INV-R3). Integration: `group_membership_smoke_test.dart` "remove with keyless bystander → bystander converges after key-updated drain"; extend `group_recovery_e2e_test.dart` so an ML-KEM-regenerated member is the keyless bystander while a third is removed.

**Migration:** yes (`078`). **Go rebuild:** none. **Risk:** backlog never drains if a member's key never returns — bounded by attempt cap + `unreachable` finalize + observable flow events (mirrors `063`'s `attempts`/`finalized_at`).

---

## 5. Test & verification strategy (summary)

**Unit (Slice 1):** the RED suites in R-1/R-2 above. The decisive security cases: keyless-bystander → epoch promoted + X excluded + no rollback (INV-R1/R2); genuine-failure-after-broadcast → no re-add (INV-R2); pre-broadcast failure → rollback still fires (legitimate).

**Integration (this repo):** `group_membership_smoke_test.dart` "remove with a keyless bystander" asserting durable removal; `leave_group_use_case_test.dart` regression (creator leaver + keyless bystander now promotes); for Slice 2, `group_recovery_e2e_test.dart` recovered-member-as-bystander convergence.

**Negative / security assertions (must-haves, from the finding):**
1. After removal of X (any bystander key state), X **cannot decrypt** a message published at the new epoch.
2. `_rollbackFailedMemberRemoval` **never** runs once `member_removed` is published.
3. New epoch is monotonic; deferred distribution never resurrects an old epoch for X.

**Device matrix (Test-Flight-Improv):** iPhone13 + Pixel6 — admin removes one device's owner while the other device has a stripped/legacy ML-KEM key; confirm the removal **sticks** (no re-add), the removed member stops decrypting new-epoch traffic, and (Slice 2) the bystander recovers after the key-updated drain. Add a row to `test-inventory.md` and a gate to `test-gate-definitions.md` for "member removal is durable under a keyless remaining member."

---

## 6. Risks, trade-offs & rollout

- **Weaker fan-out atomicity (accepted):** post-Slice-1, some remaining members may briefly be on the old epoch (deferred). Correct posture — forward secrecy for the *boundary* (the removed member) outranks synchronous convergence for *insiders*, who already held the old key.
- **Residual after Slice 1, before Slice 2:** a keyless bystander can't read new-epoch traffic until Slice 2 (or an unrelated later rotation). Degraded read for an already-broken member — **not** a security hole. The *removed* member is durably excluded.
- **Genuine-rotation-failure-after-broadcast residual:** removed member keeps the *old* key until a successful rotation — forward-secrecy delayed, never re-granted. Slice 2's queue + the creator backstop converge it.
- **Return-type ripple:** `RotateGroupKeyOutcome` touches 3 call sites (admin removal, leave use case, creator-backstop callback) + tests — compiler-enforced, contained; R-0 lands it as a no-op refactor first.
- **Leave-path regression surface:** the primitive is shared; R-1 must keep the leave suite + creator-backstop behavior green (INV-R5).
- **Rollout order:** R-0 → R-1 → R-2 (ship Slice 1 together; it is the P0) → device-verify → R-3 (Slice 2). Each session independently testable; Slice 1 carries no migration, so it can ship ahead of any DB-version coordination.

## 7. Open questions

- **OQ-1 (table strategy):** dedicated `group_pending_key_distributions` (recommended — clean separation) vs reuse `group_pending_key_repairs` with `status='pending_distribution'` (finding's preferred — no migration). Recommendation: dedicated, because the repair runner's `_retryOne` is decryption-specific and the two directions don't share semantics.
- **OQ-2 (drain trigger):** hook the `075` ML-KEM-key-updated write (prompt) vs piggy-back app-resume/periodic (simpler). Recommendation: both — key-updated for promptness, resume as the catch-all.
- **OQ-3 (migration number):** `078` assumed; coordinate with the 02 self-heal plan which also eyes `078`. Whichever lands second takes `079`.
- **OQ-4 (leave-backstop timing follow-up):** the creator-only, eventual re-key (`group_message_listener.dart:3362-3365`) still doesn't rotate if the creator is offline or only non-creator admins remain. Out of this P0; track as a separate convergence-timing finding.

## 8. Effort estimate

**Medium–Large.** Slice 1 is the bulk of the *value* and is contained: R-0 (mechanical return-type, ~0.5 day), R-1 (rotation rewrite + tests, ~1–1.5 days), R-2 (caller no-throw + safe rollback + l10n + tests, ~1 day). Slice 2 (migration + helpers + repo + drainer + trigger wiring + integration/device proofs, ~1.5–2 days) is more code but lower-stakes. Total ~4–5 focused days, device proofs the long pole per this repo's harness constraints. Slice 1 alone (~2.5–3 days) closes the P0 security defect and is independently shippable.
