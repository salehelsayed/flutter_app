> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P0** · TDD plan for **[02-P0-undecryptable-messages-self-heal.md](./02-P0-undecryptable-messages-self-heal.md)**

---

# TDD Plan — Eliminate permanently-undecryptable group messages (self-heal)

**Status: PLAN ONLY.** Decomposed for TDD execution. Verified against HEAD `124-harness-refactor` (commit `41061593`).

> **Currency audit (2026-06-16, vs the working tree on top of `41061593`).** Re-verified by a 17-agent workflow (graphify + raw-source + `git diff`, every blocker adversarially re-confirmed). **Bug premise fully intact** — all 8 §0 root causes still `NOT_RESOLVED`, and the core `group_pending_key_repair_service.dart` is byte-pristine (untouched since `d26f062d`), so UDM-A/C/D logic is unaffected. **Two blockers were fixed in this revision:** (1) the migration is renumbered **078 → 080 / DB v78 → v80** — slots `078` (`group_pending_key_distributions`, Finding 03) and `079` (`message_dedup_key`, F8/125) already landed (untracked) and `currentIdentityDatabaseVersion` is already `79`; (2) the UDM-B resume sweep is now an **ungated Step 8i** following the landed Finding-03 `drainPendingKeyDistributionsFn` precedent (the old "inside the `resumeGroupRecoveryEnabled` gate" instruction is wrong — Step 8 sits outside it). Line refs refreshed throughout. UDM-C's Go-contract fallback is now **mandatory** (no distinct crypto `errorCode` exists). `migration_database_schema_inventory_test.dart` needs **no** edit (v74 fixture, index-only migration adds no table).

> Companion to the [finding](./02-P0-undecryptable-messages-self-heal.md). The finding describes *what's wrong*; this plan describes *how to fix it test-first, in shippable slices, in the right order, with the coupling made explicit*.

---

## 0. Resolution verification (is the finding still open?)

**Yes — entirely open.** A graph-first verification + adversarial cross-check pass (16 agents) scored **all 8 evidence sections NOT_RESOLVED at high confidence**, with the finding's claims still accurate (only line drift). No post-review HEAD commit touched the self-heal files with a relevant subject; the structure is frozen relative to the review.

| § | Root cause | Status | Anchor proof (HEAD) |
|---|-----------|--------|---------------------|
| A | 30s wall-clock grace | **NOT_RESOLVED** | `KeyRotationGracePeriod = 30 * time.Second` (`config.go:46`); stamped at receiver apply-time (`pubsub.go:808,869`) |
| B | single prev epoch in-memory | **NOT_RESOLVED** | `GroupKeyInfo` still only `Key`/`PrevKey` (`go-mknoon/node/group.go:62-68`); no ring. *Dart 8-gen replay mitigation intact — not a regression* |
| C | future-epoch → `ValidationReject` | **NOT_RESOLVED** | verify falls to `return false` → `bad_signature_or_epoch` → `ValidationReject` (`pubsub.go:1280,1554-1556`); no `ValidationIgnore`, no `key_epoch_behind` |
| D | live recovery reactive only | **NOT_RESOLVED** | `emitGroupDecryptionFailed` still omits `messageId` despite receiving `env` (`pubsub.go:1699-1711`; call sites `:1599` no-key / `:1609` decrypt-error); no in-Go re-request |
| E | **no active key-pull (load-bearing gap)** | **NOT_RESOLVED** | `emitGroupKeyRepairRequest` still log-only stub (`group_pending_key_repair_service.dart:58-69`), wired at ~9 direct call-sites + 3 `??` defaults; no `group_key_repair_request` wire type anywhere |
| F | narrow retry triggers only | **NOT_RESOLVED** | only `getPendingRepairsForGroupEpoch`; no resume sweep, no backoff timer, no status-leading index |
| G | live placeholder stuck + duplicate | **NOT_RESOLVED** | `_handleMessage` persists real msg (`group_message_listener.dart:926`) but never supersedes the synthetic `live:` placeholder |
| H | first-hiccup → permanent undecryptable | **NOT_RESOLVED** | `_retryOne` catch finalizes on any non-`'Missing group replay key'` error (`group_pending_key_repair_service.dart:543-557`); `attempts` never gates terminal |

**Near-miss "fixes" explicitly ruled out:** `group_validation_feedback.go` notifies the *sender* of a reject (opposite direction); `resend_group_invite_use_case.dart` is *admin-initiated* (not receiver-side pull); the `_isRepairPlaceholder` guards in `handle_incoming_group_message_use_case.dart` only match the offline placeholder (real wire id), never the synthetic-id live placeholder.

---

## 1. Critical assessment & scoping decision

The finding's 6 improvements are **not a monolith**, and shipping them as one block would be wrong:

- **#1 (10-min grace), #2 (retained epoch ring), #3 (active key-pull)** change the **crypto/security posture** — they widen the window in which a *removed* member can still decrypt traffic from an epoch they held, add an inbound key-distribution attack surface, and require a `gomobile bind` rebuild + the iPhone13/Pixel6 device matrix. These deserve an explicit threat-model review and device gates. The finding itself sequences them last.
- **#6 (bounded finalize), #4 (resume/timer sweep), #5a (live supersede), #5c (TTL self-clear)** are **Dart-only, security-neutral, no Go rebuild**, and kill the two most *user-visible* permanent symptoms (the stuck-placeholder-plus-duplicate, and the first-hiccup gravestone).

**The non-obvious coupling that drives ordering:** making the undecryptable transition non-eager (**#6**) only *helps a user* if a retry actually re-fires later (**#4**). Without #4's sweep, #6 converts "wrongly branded undecryptable" into "stuck on the waiting placeholder" — better, but not *resolved*. Symmetrically, a no-envelope live placeholder under #6+#4 would retry forever unless **#5c** bounds it (or **#5a** supersedes it when the real message lands). So the Dart quartet is a **single coherent slice** that must ship together to deliver "self-heals and renders."

### Recommended scope

- **Slice 1 (this plan, execution-ready): the Dart-only quartet** — `#5a → #4 → #6 → #5c`. Security-neutral, no device gate beyond a regression pass, delivers the bulk of user-visible relief.
- **Slice 2 (specified, deferred): the Go epoch/grace + active-pull program** — `#1/#2`, `#5b`, `#3`. Land *after* Slice 1 is device-verified, each behind a threat-model review and the two-device matrix.

This matches the finding's own rollout order (lowest-risk first) and the repo's session-decomposition convention (the finding's handoff proposes `UDM-001..006`).

---

## 2. Slice 1 — Dart-only self-heal (execution-ready, security-neutral)

All four sessions are TDD: write the RED test(s) first, then the minimal GREEN change. No Go rebuild. Shared prep below lands once.

### Session 0 (prep) — extract the shared repair-repository fake

**Why:** six test files each define a private `_InMemoryGroupPendingKeyRepairRepository`; one differently-named (`_SmokeInMemoryGroupPendingKeyRepairRepository`). Slice 1 adds methods to this fake (`getAllPendingRepairs`, `getPendingRepairsForGroup`, `deleteRepair`) and a 7th copy would guarantee drift.

- **Extract** the canonical copy (`test/features/groups/application/group_pending_key_repair_service_test.dart:89-165`) into `test/shared/fakes/in_memory_group_pending_key_repair_repository.dart`, preserving each existing copy's exact `upsert`/`recordAttempt`/`finalize` semantics.
- Migrate the 6 callers (service, listener, smoke, accept-invite, drain, resume-recovery tests) to the shared fake. **Gate:** the groups suite stays green with zero behavior change before any production edit.
- *Optional:* if extraction risks churn under deadline, allow the new sessions to extend the existing private fakes and defer extraction — but flag it as tech debt.

---

### Session UDM-A (#5a) — supersede `live:` placeholders from the live-delivery path

**Root cause R5 (§G).** A real message arriving via the live/membership-flush/push-loss path persists under its real wire `messageId` and never clears the synthetic-id `live:` placeholder → stuck placeholder + duplicate.

**RED tests (write first):**
1. `test/features/groups/application/group_message_listener_test.dart` — *"real live message supersedes the live placeholder for same group+sender+epoch (no duplicate)"*. Reuse the harness at `:1005-1083` (test `GO-004`; the working-tree edits to this file are +120 notification-banner lines appended at EOF `:11226+`, below all anchors — nothing shifted). Fire `group:decryption_failed` for `group-1/peer-sender/keyEpoch:3` → assert placeholder created (`msgRepo.count==1`, repair `replayEnvelopeJson==null`). Then `sourceController.add({...keyEpoch:3, senderId:'peer-sender', messageId:'normal-live-after-diagnostic'})` → **assert `msgRepo.count == 1` (not 2)** — this flips the assertion at `:1081` which currently encodes the bug — the synthetic `live:` message is gone, the repair is `repaired` with `finalizedAt` set, and a `GROUP_LIVE_DECRYPTION_REPAIR_SUPERSEDED` flow event fired.
2. *Guard:* a live message with a **non-matching** epoch (`keyEpoch:4`) or sender leaves the placeholder intact and `pending_key` (supersede must be precise, mirroring `_isLiveDiagnosticRepairForSender`).
3. *Regression (keep separate, stays green):* the durable-replay supersede path (`queueMissingGroupReplayKeyRepairFromEnvelope` → `_supersedeLiveDiagnosticRepairForDurableReplay`) still deletes + finalizes after the refactor.

**GREEN edits:**
- `group_pending_key_repair_service.dart:202-236` (fn body; `:238-246` is the separate `_isLiveDiagnosticRepairForSender` helper) — extract a **public** `supersedeLiveGroupDecryptionRepairForDelivery({pendingKeyRepairRepo, msgRepo, groupId, senderPeerId, transportPeerId, keyEpoch})` from the body of `_supersedeLiveDiagnosticRepairForDurableReplay` (note: the *private* fn currently has no standalone `transportPeerId` param — transport match lives in the helper at `:244`; the new **public** signature adds it); make the private fn delegate to it (byte-identical durable behavior). Query by `(groupId, keyEpoch)` + sender match — **do not** reconstruct the synthetic id (it embeds `localKeyEpoch`, which the live path doesn't know). Match sender on `senderPeerId` **or** `transportPeerId`.
- `group_message_listener.dart:925-927` — inside the `if (result != null)` block, **after** `_emitGroupMessage(result)` (`:926`), call the new public supersede with the in-scope handles (`senderId` `:764`, `transportPeerId` `:768-770`, `groupId` `:762`, `result.keyGeneration`, the already-injected `_pendingKeyRepairRepo` field `:124`, `msgRepo` `:761`), guarded by `result.keyGeneration > 0 && senderId.isNotEmpty`. **No new constructor param.**

**Migration:** none. **Coupling:** self-contained — lands first, fixes the duplicate immediately. **Risk:** placeholders stored with sender `'unknown'` (`transportPeerId==null`) won't match a real `senderId`; #5c (TTL) is the safety net. Placement *after* persist guarantees a mid-way crash never deletes the placeholder without the real message landing (`_handleMessage` is serialized under `_userMessageWorkQueue`).

---

### Session UDM-B (#4) — all-pending scan API + resume sweep + bounded-backoff timer

**Root cause R4 (§F).** Persisted pending repairs only re-fire on a fresh `group_key_update`/invite-accept for that exact `(group,epoch)`; nothing re-runs them on resume or a timer.

**RED tests (write first):**
1. `test/core/database/helpers/group_pending_key_repairs_db_helpers_test.dart` — `dbLoadAllPendingGroupKeyRepairs` returns only `pending_key` rows across all groups/epochs, ordered `created_at ASC, id ASC`, honoring `limit`; `dbLoadPendingGroupKeyRepairsForGroup` filters to one group, excludes finalized. Reuse the FFI in-memory setup (`:10-23`) + `repairRow()` builder (`:25-55`).
2. `test/core/database/migrations/080_group_pending_key_repairs_status_index_test.dart` — running the full chain through `079` then `080` creates `idx_group_pending_key_repairs_status_created`; idempotent on re-run. Mirror `063_group_pending_key_repairs_test.dart:51-69`.
3. `group_pending_key_repair_service_test.dart` — `retryAllPending()` sweeps a persisted pending repair whose replay key now exists → returns count 1, status `repaired`, `finalizedAt` set; a second null-envelope repair is left `pending_key` (proving it reuses `_retryOne` semantics).
4. `test/core/lifecycle/handle_app_resumed_pending_key_repair_sweep_test.dart` — the sweep runs **after** the Step-3c `drainGroupOfflineInbox` **and after** the landed Finding-03 Step 8h (`drainPendingKeyDistributionsFn`) (ordered recorder: `sweep index > drain(3c) index AND > Step 8h index`); a throw in a prior step doesn't skip the sweep, a throw in the sweep doesn't crash resume. **Do not** assert a "skipped when flag off" case — the sweep is **ungated** (see GREEN edits). Mirror `handle_app_resumed_group_inbox_retry_test.dart`.
5. `test/features/groups/application/group_pending_key_repair_backoff_timer_test.dart` — `fakeAsync` + injected `createTimer` factory + injected schedule; sweep fires at +5s/+30s/+2m, clamps at 2m while sweeps return 0, **stops** after a sweep repairs (or no pending remain), `dispose()` cancels. Mirror `pending_message_retrier_test.dart`/`key_exchange_retrier_test.dart` (`fake_async ^1.3.3` already in pubspec).

**GREEN edits:**
- `group_pending_key_repair_repository.dart` — add abstract `getAllPendingRepairs({int limit = 200})` and `getPendingRepairsForGroup({required String groupId, int limit = 100})` (both `status='pending_key'`, `ORDER BY created_at ASC, id ASC`).
- `lib/features/groups/domain/repositories/group_pending_key_repair_repository_impl.dart` — two new injected helper-fn fields + ctor params + overrides (mirror the `getPendingRepairsForGroupEpoch` override at `:56-68`). The matching abstract methods go in `…/group_pending_key_repair_repository.dart:24`.
- `group_pending_key_repairs_db_helpers.dart` (insert after `dbLoadPendingGroupKeyRepairsForEpoch` ends at `:80`, before the next helper at `:82` — the file is 123 lines, **not** EOF) — `dbLoadAllPendingGroupKeyRepairs(db, {limit})` (`WHERE status = ?`) and `dbLoadPendingGroupKeyRepairsForGroup(db, {groupId, limit})`.
- **New** `lib/core/database/migrations/080_group_pending_key_repairs_status_index.dart` (slots `078`/`079` are already taken by `group_pending_key_distributions`/`message_dedup_key`) — `CREATE INDEX IF NOT EXISTS idx_group_pending_key_repairs_status_created ON group_pending_key_repairs(status, created_at)` (status-leading; the existing `idx_..._group_epoch_status` leads with `group_id` and can't serve a status-only predicate). `emitFlowEvent` START/SUCCESS/ERROR like 063; export `runGroupPendingKeyRepairsStatusIndexMigration(Database)`.
- `lib/core/database/app_database_version.dart:1` — bump `79 → 80` (pre-state is already `79`, not 77).
- `lib/main.dart` — onCreate: append the call **after `runMessageDedupKeyMigration`** (`:464`, the current last onCreate call); onUpgrade: add `if (oldVersion < 80) { await runGroupPendingKeyRepairsStatusIndexMigration(db); }` **after the existing `oldVersion < 79` block** (`:699`) — the `< 78`/`< 79` slots are taken by distributions/dedup; thread the two new helper closures into the repo ctor; import `080_group_pending_key_repairs_status_index` (the `078`/`079` imports already exist at `:75-76`). **Both** onCreate and onUpgrade must run it (fresh installs vs upgrades).
- `group_pending_key_repair_service.dart` (after `retryPendingRepairsForKey` `:425`; `_retryOne` begins `:427`) — `Future<int> retryAllPending({int limit = 200})` iterating `getAllPendingRepairs` → `_retryOne`, emitting `GROUP_PENDING_KEY_REPAIR_SWEEP`. Reuses `_retryOne` verbatim. *(The class is `GroupPendingKeyRepairRunner` (`:383`), constructed as `groupPendingKeyRepairRunner` in `main.dart:2254`.)*
- **New** `lib/features/groups/application/group_pending_key_repair_backoff_timer.dart` — `GroupPendingKeyRepairBackoffTimer(runSweep, schedule = [5s,30s,2m], createTimer = Timer.new)`; advance through schedule while sweeps return 0, clamp at 2m, stop on repair-or-empty; `start/stop/dispose`. The injectable `createTimer` seam is the test hook (no clock-injection precedent in this stack — follow the real-`Timer?`-field + `fakeAsync` pattern).
- `lib/core/lifecycle/handle_app_resumed.dart` — new `Future<int> Function()? retryAllPendingGroupKeyRepairsFn`; insert a fault-isolated step (try/catch + `emitFlowEvent` on error) as **Step 8i**, immediately after the landed Finding-03 **Step 8h** (`drainPendingKeyDistributionsFn`, `~:640`), guarded **only** by `if (retryAllPendingGroupKeyRepairsFn != null)` — **ungated** (matches the Step 8h precedent; `enableResumeGroupRecovery` no longer wraps Step 8, and `retryAllPending` is internally cheap when there are no pending rows). **Use a NEW param** — do **not** reuse `drainPendingKeyDistributionsFn`. Freshly-drained keys are still present because Step-3c `drainGroupOfflineInbox` (`:240`) and Step 8h both run earlier in the sequence.
- `lib/main.dart` — construct the timer with `runner.retryAllPending` (the runner already exists at `:2254`); add runner + timer as `MyApp` fields; pass `retryAllPendingGroupKeyRepairsFn` into the `handleAppResumed` call (`~:3743-3837`, alongside the existing `drainPendingKeyDistributionsFn` at `:3757`; read `widget.groupPendingKeyRepairRunner`, not a local); cancel the timer in `_MyAppState.dispose()` (`:3615-3645`, mirror `pendingMessageRetrier.dispose()` at `:3619`).

**Migration:** **080 / DB v80**, index-only (no data backfill, `IF NOT EXISTS`, fail-open). **Coupling:** the sweep and `_retryOne` are shared with #6 — write #4's tests against current `_retryOne` semantics and re-validate after #6. **Risk:** ordering (sweep must be *after* drain or it re-creates the bug); `full_migration_chain_test.dart` is **already modified** in the working tree (imports/runs `078`+`079`) — **append** the `080` import + call after the `runMessageDedupKeyMigration` calls in **both** the explicit-chain block (`:172-173`) and `buildAllMigrations` (`:289-290`), plus an `idx_group_pending_key_repairs_status_created` assertion; there is **no** version-int literal to flip and an index-only migration adds no table. `migration_database_schema_inventory_test.dart` needs **no** change (it pins a v74 fixture and asserts table membership only). A backlog `>200` drains across repeated timer fires (don't stop while pending rows remain even if a sweep repaired 0).

---

### Session UDM-C (#6) — bounded, classified "undecryptable" finalization

**Root cause R6 (§H).** `_retryOne`'s catch finalizes on the *first* non-`'Missing group replay key'` error; `attempts` is tracked but never gates the terminal transition. A one-shot `BRIDGE_TIMEOUT`, a not-yet-injected reaction repo, or a transient ordering `StateError` permanently brands a message *"Message could not be decrypted."*

**RED tests (write first)** — matrix in `group_pending_key_repair_service_test.dart`:
| Scenario | Setup | Expect |
|---|---|---|
| transient bridge decrypt (`BRIDGE_TIMEOUT`) | key present, valid envelope, `group.decrypt` → `{ok:false, errorCode:'BRIDGE_TIMEOUT'}` | stays `pending_key`, `finalizedAt==null`, text unchanged, `attempts += 1` |
| missing reaction repository (`StateError :462`) | reaction repair, runner built without `reactionRepo` | stays `pending_key`, not terminal |
| reaction replay validation rejected (`StateError :476`) | reaction repair, processing returns null | stays `pending_key`, not terminal |
| replay validation rejected (`StateError :517`) | decrypt OK, `handleIncomingGroupMessage` → null | stays `pending_key`, not terminal |
| replay didn't replace placeholder (`StateError :529`) | processed but placeholder unreplaced | stays `pending_key`, not terminal |
| key still missing | `getKeyByGeneration → null`, `StateError('Missing group replay key …')` | requeued even at `attempts==10` (key absence never terminal) |
| crypto-fail, key present, `attempts < 5` | force `GroupOfflineReplaySignatureException('signature_invalid')` (FakeBridge `payload.verify → {ok:true, valid:false}`), pre-seed `attempts=3` | stays `pending_key`, `attempts==4`, **not** finalized |
| **crypto-fail, key present, `attempts >= 5`** | same, pre-seed `attempts=5` | **`undecryptable`**, `finalizedAt` set, text *"Message could not be decrypted."* — the **only** terminal test |
| no double-count | two transient cycles | `attempts == 2` (guards the `:446`+catch double-increment) |

**GREEN edits** (`group_pending_key_repair_service.dart`):
- `:543-557` — replace the single key-missing guard + unconditional `_finalizeUndecryptable` with a 3-way classification: **(1)** key-missing / structural-or-transient → `recordAttempt` + return false (stay pending); **(2)** confirmed crypto/auth failure **with key present** → if `attempts >= kGroupKeyRepairMaxAttempts` finalize, else stay pending; **(3)** everything else → stay pending, never finalize.
- New consts/helpers near `:630` — `const kGroupKeyRepairMaxAttempts = 5;`, `_isConfirmedCryptoFailure(Object e)` (true **only** for `GroupOfflineReplaySignatureException` with an **authenticity** reason — `signature_invalid`, `plaintext_hash_mismatch`, `signed_payload_mismatch`, `sender_{key,device,transport}_mismatch`, `payload_*_mismatch`, etc.). **CONFIRMED: there is no `BridgeCommandException` crypto path to key off** — `GroupDecryptMessage` (`go-mknoon/.../bridge.go:2493`) returns only `INTERNAL_ERROR` (`:2515`, on *any* decrypt failure or panic) or `INVALID_INPUT` (`:2506/:2510`); a real AES-GCM auth failure is indistinguishable from a transient/internal error, and all authenticity checks are Dart-side via `GroupOfflineReplaySignatureException`. So `BRIDGE_TIMEOUT`/`UNKNOWN`/`INTERNAL_ERROR` are **always non-terminal**. Treat **ambiguous** reasons (`missing_*`, `unknown_sender`, `revoked_device`, `group_mismatch`, `relay_sender_mismatch`, `recipient_not_entitled`) as **non-terminal** — these are data/membership-not-yet-applied, and marking them terminal re-introduces false-undecryptable on a just-joined device.
- **Fix the double-increment:** `recordAttempt` is called at `:446` (pre-try) *and* in the catch (`:549`). Collapse to **one increment per cycle** (single source of truth) or `attempts` advances 2/cycle and the `>=5` gate trips in ~3 real cycles.

**Migration:** none (`attempts` column already exists). **Coupling:** STRONG with #4 — #6 stops the false-poisoning, but only #4's sweep guarantees the now-pending message eventually retries and renders. **Land #4 with or before #6.** **Risk:** the Go `group.decrypt` error contract is now **CONFIRMED** to lack a distinct crypto `errorCode` (only `INTERNAL_ERROR`/`INVALID_INPUT`), so terminal classification **must** be scoped to `GroupOfflineReplaySignatureException` authenticity reasons (never classify `BRIDGE_TIMEOUT`/`UNKNOWN`/`INTERNAL_ERROR` as crypto). Audit the groups suite for any test asserting undecryptable-on-first-failure for a *non-crypto* error (per the B3 precedent, expect mechanical reconciliations).

---

### Session UDM-D (#5c) — TTL self-clear for no-envelope live placeholders

**Root cause R5 (§G), tail case.** A `live:` placeholder with `replayEnvelopeJson==null` whose real message *never* arrives (sender `'unknown'`, epoch skew, lost) would, under #6+#4, retry forever (short-circuiting on `'waiting for replay envelope'`) and never clear — a permanent gravestone with no ciphertext.

**RED tests (write first)** — `group_pending_key_repair_service_test.dart`:
1. *self-clear after TTL:* seed a `live:` repair, `replayEnvelopeJson==null`, `createdAt = now - 25h`; run the sweep with injected `now` → `getRepair(id)==null` (**DELETED**, not status-flipped — explicitly **not** `undecryptable`), placeholder message gone, no `'waiting for replay envelope'` attempt recorded, `GROUP_PENDING_KEY_REPAIR_SELF_CLEARED` fired.
2. *within TTL preserved:* same with `createdAt = now - 1h` → stays `pending_key`, `attempts==1`, `lastError=='waiting for replay envelope'` (current behavior; parameterize the existing `:14-86` test by `createdAt`).
3. *durable never self-cleared:* an offline repair (`replayEnvelopeJson!=null`, `createdAt = now - 48h`) is **not** deleted (TTL is scoped to `live:` + null-envelope).

**GREEN edits:**
- `group_pending_key_repair_service.dart` near the reason consts — `const liveGroupNoEnvelopeRepairTtl = Duration(hours: 24);`.
- `group_pending_key_repair_repository.dart` — add `Future<void> deleteRepair(String id);` (today only `finalize*` exist, which UPDATE status — neither removes the row).
- `group_pending_key_repair_repository_impl.dart` — implement `deleteRepair` via a new injected helper + ctor param.
- `group_pending_key_repairs_db_helpers.dart` — `dbDeleteGroupPendingKeyRepair(db, id)` (`db.delete(... where: 'id = ?')`) with `emitFlowEvent`.
- `group_pending_key_repair_service.dart:427-444` — in the no-envelope branch of `_retryOne`, **before** the `'waiting for replay envelope'` `recordAttempt`, check `now.difference(repair.createdAt) >= ttl` and if so DELETE (message + repair) + emit `SELF_CLEARED` instead of looping. (Riding `_retryOne` means every existing trigger — and #4's sweep — ages stale placeholders out. Pass `now` injectable for tests.)
- `lib/main.dart` — pass `dbDeleteGroupPendingKeyRepair` into the repo ctor so `deleteRepair` is non-null in production.

**Migration:** none (`created_at` exists and is index-covered for ordering). **Coupling:** partially on #4 — without a resume sweep, a device that never gets another key-save/invite event for that group won't age the placeholder; #5c rides existing triggers *and* #4's sweep. **Risk:** must DELETE (assert `getRepair(id)==null`) not `finalizeUndecryptable`, to distinguish from the §H bug.

---

## 3. Slice 2 — Go epoch/grace + active key-pull (specified, deferred behind security review)

These close the *remaining* gap (the no-replay-envelope, never-superseded case truly recovers) but change crypto posture and need a `gomobile bind` rebuild + the device matrix. **Do not bundle with Slice 1.** Specify each as its own session; land after Slice 1 is device-verified.

| Session | Scope (finding §) | Must prove before closure | Security gate |
|---|---|---|---|
| **UDM-E** (#1+#2) | Configurable grace (default 10 min) + retained epoch-key ring (K=5) in `GroupKeyInfo`; anchor live decrypt/verify to **keys held**, not the timer; keep the timer only to constrain which epoch a node will *sign/publish* under | `pubsub_key_rotation_grace_test.go` deadline-negative becomes retained-vs-**evicted**; existing live accept/reject stays green; `UpdateGroupKey`/`RefreshJoinedGroupStateIfNewer` **append** (not overwrite), evict past K | Threat-model delta: a removed member can decrypt epochs they *already held* for longer; forward secrecy preserved (new epoch never delivered to them). Bound K=5, grace ~10 min. Device matrix: offline > 10 min then foreground, no permanent placeholder/duplicate |
| **UDM-F** (#5b) | Future-epoch live envelope → `pubsub.ValidationIgnore` (not `Reject`, no peer penalty) + `group:key_epoch_behind` diagnostic; optional buffer + re-process after `UpdateGroupKey` advances; additive privacy-safe `messageId` on `group:decryption_failed` | Future-epoch table test proves Ignore + diagnostic; malformed/unauthorized still `Reject`; `pubsub_decryption_failure_test.go:283-296` still excludes plaintext/keys/ciphertext/nonce/signature and does **not** assert `messageId` carries ciphertext | Privacy contract: `messageId` only; any encrypted-envelope field is out of scope absent a separate privacy-reviewed change |
| **UDM-G** (#3) | Real outbound signed `group_key_repair_request {groupId, keyEpoch, requesterPeerId, requesterDeviceId, sig}` via the existing direct/inbox fallback; **replace** the log-only `emitGroupKeyRepairRequest` stub at all 8 wiring sites + the 3 terminal callsites (incl. the already-firing `_requestReceivedMessageKeyRepairIfLocalEpochIsBehind`); admin responder = targeted re-run of `_distributeRotatedKeyToDevice` for that epoch (never mint a new one) | Requester/admin tests: exact-epoch re-delivery, no new epoch minted, **member-at-epoch** authz, per-`(requester,groupId,epoch)` rate-limit; old stub wiring replaced everywhere | Attack surface: sign requests; rate-limit; admin only re-delivers epochs the requester was entitled to. Best-effort/additive — old peers ignore the new wire type (strictly no worse than today) |

> **Note for Slice 2:** Slice 1's #5a/#5c already remove the *visible* duplicate/gravestone, so Slice 2's job narrows to "a member who genuinely missed a key actively recovers it" — which is exactly **UDM-G**. UDM-E/F reduce how often that path is needed (wider live eligibility, no peer penalty). Sequence **UDM-G last** (largest, highest surface).

---

## 4. Cross-cutting gates & verification

| Gate | Requirement |
|------|-------------|
| Focused Dart unit | `flutter test` on `group_pending_key_repair_service_test.dart`, `group_message_listener_test.dart`, `group_pending_key_repairs_db_helpers_test.dart`, the new `080_*_test.dart`, `handle_app_resumed_pending_key_repair_sweep_test.dart`, `group_pending_key_repair_backoff_timer_test.dart` |
| Migration chain | `full_migration_chain_test.dart` — **append** the `080` import + call (after `runMessageDedupKeyMigration` in both the explicit chain and `buildAllMigrations`) + an `idx_group_pending_key_repairs_status_created` assertion; it's already at the v79 baseline (no version literal to flip). `migration_database_schema_inventory_test.dart` needs **no** change (v74 fixture; index-only migration adds no table). Green |
| Named groups gate | `scripts/run_test_gates.sh groups` (7 host files) stays green. **Note:** the repair *unit* tests are **not** in this gate — they run under `run_host_test_gates.sh` host-all + the completeness check; ensure new tests land under `test/` so the dir-sweep catches them |
| FLOW assertions | Presence of `GROUP_PENDING_KEY_REPAIR_REPAIRED`, `GROUP_LIVE_DECRYPTION_REPAIR_SUPERSEDED`, `GROUP_PENDING_KEY_REPAIR_SELF_CLEARED`, `GROUP_PENDING_KEY_REPAIR_SWEEP`; **absence** of lingering `..._WAITING_FOR_REPLAY_ENVELOPE` / `..._UNDECRYPTABLE` after convergence (capture via `debugSetFlowEventSink`) |
| Completeness / static | repo completeness check + `git diff --check` before closure; `flutter analyze` no new issues |
| Device (Slice 1) | iPhone13 + Pixel6: member offline across a rotation, foreground → missed message renders, **no permanent placeholder, no duplicate** (Slice 1 fixes the visible symptoms even without the Go pull) |
| Device (Slice 2) | Add the "**zero permanently-undecryptable messages after a membership change**" gate to `test-gate-definitions.md` + the notification/recovery matrix, incl. background > 10 min then foreground |

**Harnesses to reuse (no new infra for Slice 1):** `FakeGroupPubSubNetwork` (`emitDecryptionFailureDiagnostic:135`), `GroupTestUser.create` (threads `requestGroupKeyRepair` + `pendingKeyRepairRepo` + `groupDiagnosticEvents`), `FakeBridge` (`responses['group.decrypt']`, `payload.verify {ok:true,valid:false}` to force `signature_invalid`), `in_memory_group_repository.dart`, `in_memory_group_message_repository.dart`, `FakeP2PService`, `fakeAsync`/`fake.elapse` (`pending_message_retrier_test.dart`, `key_exchange_retrier_test.dart`), FFI in-memory DB + `_openVersion74Fixture` cross-version pattern.

---

## 5. Risks & rollout order

**Recommended order (each independently shippable, lowest-risk first):**
1. **Session 0** (shared fake) → **UDM-A (#5a)** — kills the visible duplicate. Pure Dart, no migration, no coupling.
2. **UDM-B (#4)** — retry infrastructure (migration 080, resume sweep, backoff timer). Build before #6 so #6's now-pending repairs actually re-fire.
3. **UDM-C (#6)** — bounded/classified finalize. Backed by #4's retry path.
4. **UDM-D (#5c)** — TTL self-clear. Rides #4's sweep + existing triggers.
5. *(after Slice 1 device-verified)* **UDM-E/F/G** — Go grace/ring, future-epoch Ignore, active pull — each behind threat-model review + device matrix.

**Top risks (Slice 1):**
- **`attempts` double-increment** (`:446` + catch `:549`) silently halves the N=5 budget — collapse to one increment/cycle (has its own RED test).
- **Go `group.decrypt` error contract** unverified — default to terminal-only on `GroupOfflineReplaySignatureException` authenticity reasons; never classify `BRIDGE_TIMEOUT`/`UNKNOWN` as crypto.
- **Sweep ordering & placement** — must run *after* the Step-3c `drainGroupOfflineInbox` and the Finding-03 Step 8h (newly-drained keys present). Place it as an **ungated Step 8i** (guard only `if (fn != null)`), matching the landed Step 8h precedent — do **not** put it inside the `resumeGroupRecoveryEnabled` gate (Step 8 sits outside it).
- **Migration version bump** (`79 → 80`) — `full_migration_chain_test.dart` is already modified for `078`/`079`; **append** the `080` import/call + index assertion (no version literal to flip). The schema-inventory test needs **no** change. Verify onCreate **and** onUpgrade both run `080`.
- **Backoff timer leak** — cancel in `_MyAppState.dispose()`; the injectable `createTimer` seam keeps tests off the real clock.

**What Slice 1 does and doesn't close:** Slice 1 removes the two *visible* permanent symptoms (stuck-placeholder+duplicate, first-hiccup gravestone) and makes persisted repairs actually retry. It does **not** make a member who truly missed a key *actively* recover it without a relay-inbox replay — that residual is **UDM-G (#3)** in Slice 2, which is why the program isn't "fully closed" until Slice 2 lands. State this explicitly at Slice-1 closure so the residual isn't mistaken for done.
