> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P1** · TDD plan for [finding 05](./05-P1-recovery-orchestration-hardening.md)

---

# 05 — Harden Recovery Orchestration: Verified TDD Plan

> **PHASE 1 IMPLEMENTED 2026-06-16 (uncommitted, host-green, TDD; adversarial /workflow review CLEAN after closing one test-gap).**
> - **P1.2** `main.dart` provider OR-in: `() => _isResuming || isGroupRecoveryInProgress()` (closes the startup fire-and-forget hole). Wiring-lock test flipped red→green.
> - **P1.1** `group_recovery_gate.dart`: `run()` → serializing one-at-a-time queue; added `tryRun()` + top-level `runWithGroupRecoveryGateOrSkip`. Implemented via an internal FIFO `List<void Function()> _queued` + `_running` flag (NOT future-chaining — chaining off a root-zone `Future.value()` stalls `fakeAsync`). `_activeDepth`/`activeDepthListenable` preserved for the UI shell; `begin()` at enqueue so `isActive` covers queued passes.
> - **P1.3** `pending_message_retrier.dart`: `_retryIfNeeded` group section wrapped in `runWithGroupRecoveryGate` (finding-125 GAP-3a order preserved byte-for-byte); 30s sweep switched to `runWithGroupRecoveryGateOrSkip` + new `PENDING_RETRIER_GROUP_SWEEP_SKIPPED_GATE_ACTIVE` event.
> - **Tests:** new `group_recovery_gate_test.dart` (7) + 4 new retrier tests (gate-held-during-group-section, 12-step GAP-3a order lock, whole-pass external-hold skip, sweep-OrSkip-skip-not-queue + event — the last added after review, mutation-verified). Gates: gate 7 · retrier 27 · wiring 6 · use-cases 222 · group_info_wired 64 · resume-recovery 92 green; `analyze`/`format` clean. Only red = pre-existing `handle_app_resumed_group_recovery_test:1538` (baseline-confirmed not-mine via gate stash).
> - **DEVICE PROOF (Phase 1):** `integration_test/group_recovery_gate_serialization_proof_test.dart` (`@Tags(['device'])`) — **PASSED 3/3 on iPhone 16e simulator** (real iOS Dart runtime, real `Future`s/`Timer`s): serialization + OrSkip-skip + thrown-pass-releases, and the retrier suppressed-during-recovery → resumes-after-release path (P1.2+P1.3 end-to-end).
>
> **PHASE 3 (Dart eligibility half) ALSO IMPLEMENTED 2026-06-16 (uncommitted, host-green, TDD, mutation-verified):** `rejoin_group_topics_use_case.dart` (CLEAN, no schema): added `RejoinOutcome` enum + `perGroupOutcomes` map on `RejoinGroupTopicsResult`; **revised `canAcknowledgeGroupRecovery` from `!skipped && skippedNoKeyCount==0 && errorCount==0` → `!skipped && errorCount==0`** so a permanently-un-rejoinable no-key group no longer blocks the node-wide ack (was: sticky `needsGroupRecovery` forever); transient errors still block (conservative). +4 tests (no-key-doesn't-block [mutation-verified], error-still-blocks, per-group-map-independent, dissolved→skippedDissolved). rejoin 29 · handle_app_resumed only pre-existing `:1538` · startup-rejoin+resume 102 green.
>
> - **STILL DEFERRED (hard-blocked):** Phase 1b (resume gate-boundary — finding-02 owns `handle_app_resumed.dart`), Phase 2 (drain continuation — finding-06/10 own the drain file), Phase 3 **Go per-group ack** (node-wide contract + gomobile rebuild), Phase 4 (backoff/jitter/terminal-`send_failed`/manual-retry UI — needs a new migration; the 082 slot is already taken by finding-10's `082_message_reaction_tombstone`, so it's **083+**, and the UI lands in finding-10-dirty `group_conversation_wired.dart`).

**Status: VERIFIED (5-agent verify+refute recon, 2026-06-16) against the working tree on branch `124-harness-refactor`.**
**Headline: every one of the original spec's 7 findings + root causes R1–R6 is still CONFIRMED-UNIMPLEMENTED. The spec's *conclusions* hold. But the spec's audit (2026-06-06) is 10 days stale: the migration number is wrong, the Go ack line is wrong, every line number drifted (+4 to +663), and the spec under-credits mitigations that already shipped. This plan corrects all of that and re-scopes the work to be collision-aware against the heavy concurrent editing in flight (findings 02/03/06/09/10/123/125).**

> This is a planning artifact. It supersedes the line numbers and migration number in `05-P1-recovery-orchestration-hardening.md` (do not trust that doc's `:NNN` citations or "migration 076"). The original spec's *prose findings* remain the source of intent.

---

## 0. What changed since the 2026-06-06 audit (corrections that gate scoping)

| Spec claim | Reality on HEAD/working-tree (2026-06-16) | Impact |
|---|---|---|
| "Latest migration is 074, so this is **076**" | DB version is **81** (`app_database_version.dart:1`). Migrations exist through **`081_group_pending_reactions.dart`**. `076` already exists (`076_post_media_attachment_crypto_columns.dart`). | **Phase-4 migration must be `082`** (DB v82), claimed *at landing* — the `078–081` band is contended by findings 03/08/10. The spec's `076` is a hard error. |
| Go ack `GroupAcknowledgeRecovery()` node-wide at `bridge.go:656` | Node-wide at **`bridge.go:861`** (zero args). Node-wide at all 4 layers: Dart `callGroupAcknowledgeRecovery` (`bridge_group_helpers.dart:201`, empty payload), Go `GroupAcknowledgeRecovery()` (`bridge.go:861`), `Node.AcknowledgeGroupRecovery()` (`node.go:1852`), `RelaySessionManager.AcknowledgeGroupRecovery()` (`relay_session.go:652`). | P1.5 true per-group ack still needs a **Go contract change + gomobile rebuild**. The Dart-only eligibility fix is the realistic near-term path. |
| Retrier has "no guard" / "wraps nothing" | The retrier **already** has an external-recovery skip guard: `_retryIfNeeded:325-332` and `_runGroupContinuitySweepIfNeeded:276-283` both `if (_isExternalRecoveryInProgressFn?.call() == true) return;`, emitting `PENDING_RETRIER_SKIPPED_EXTERNAL_RECOVERY` / `PENDING_RETRIER_GROUP_SWEEP_SKIPPED_EXTERNAL_RECOVERY` — the exact events the spec's test strategy names. Plus `_isRetrying`/`_isGroupContinuitySweeping` reentrancy flags. | The guard keys off the **`_isResuming`-only provider**, so it does NOT cover the **startup fire-and-forget**. **P1.2 (OR-in the gate) is the live unlock**; P1.1's `tryRun` is partly redundant with this guard (still worth it for defense-in-depth + the post-check race). |
| Resume ack runs "outside the gate" (gate closes at 222) | The resume gate now opens at `handle_app_resumed.dart:196` and closes at **`:284`**, enclosing rejoin + `reconcileMissedGroupDissolves` (finding-123) + drain + **ack**. The ack is **inside** the gate. The *follow-on outbound retries* (recover-stuck/uploads/retry-failed + steps 8a-8i) are what's outside. | P1.3's framing is right but its boundary cite is stale; the blast radius is **larger** now (concurrent work added steps 8g/8h/8i outside the gate). |
| `enableResumeGroupRecovery` "(already exists)" | **Correct.** Declared `p2p_bridge_client.dart:49` (`bool.fromEnvironment`, default true); read `handle_app_resumed.dart:25`, `pending_message_retrier.dart:167-168`. | Rollout-behind-flag premise valid. |
| Finding 7: "recovery is silent / no terminal status" | The `isRecovering` "catching up" shell **exists** (`group_conversation_wired.dart:4660` `groupRecoveryGate.activeDepthListenable` → `:4687 isRecovering:`), and the single-message `retryFailedGroupMessage` entry exists (`retry_failed_group_messages_use_case.dart:105`). No terminal **per-message** status exists (`send_failed`/`sendFailed` strings are the group-**invite** enum — a red herring). | Finding 7's real gap is narrow: a per-message **terminal status + badge**, not the overall indicator. |

---

## 1. Resolution verdict (per improvement)

| # | Improvement | Status | Decisive evidence (CURRENT source) |
|---|---|---|---|
| P1.1 | `GroupRecoveryGate` → serializing primitive | **CONFIRMED-UNIMPLEMENTED** | `group_recovery_gate.dart:23-30` — `run()` just brackets `begin()`/`end()` (`:10-13`/`:15-21`); no `_tail`/`Completer` chain, no `tryRun()`, no `runWithGroupRecoveryGateOrSkip`. File is **CLEAN** (zero line drift). |
| P1.2 | Retrier observes ALL external recovery | **CONFIRMED-UNIMPLEMENTED** | `main.dart:3088-3090` — `setExternalRecoveryInProgressProvider(() => _isResuming)`; no `|| isGroupRecoveryInProgress()`. |
| P1.3 | Widen gate to full pipeline (scoping) | **CONFIRMED-UNIMPLEMENTED** | Resume gate `handle_app_resumed.dart:196-284` wraps rejoin+reconcile+drain+ack only; follow-ons `recoverStuck:347 / uploads:370 / retryFailed:391` + steps `8a-8i:486-665` run with `isGroupRecoveryInProgress()==false`. Retrier: `runWithGroupRecoveryGate` appears **only** at `pending_message_retrier.dart:287` (inside the 30s sweep); `_retryIfNeeded:323-551` wraps nothing. |
| P1.4 | First-page-fast resume drain + continuation | **CONFIRMED-UNIMPLEMENTED** | `drainGroupOfflineInbox` defaults `drainAllPages=true` (`drain_..._use_case.dart:77`); resume caller `handle_app_resumed.dart:242-253` passes no `drainAllPages:false`; `drainGroupOfflineInboxContinuation` **does not exist** (only a docstring at `:59-62`). NOTE: the first-page-stop path *is* implemented in `_drainGroupInbox:911-944` (persists cursor + `GROUP_DRAIN_OFFLINE_INBOX_FIRST_PAGE_DONE`; cursor read at `:298`) — so the continuation is a thin wrapper, **feasible**. |
| P1.5 | Per-group recovery tracking; ack what can be acked | **CONFIRMED-UNIMPLEMENTED** | `rejoin_group_topics_use_case.dart:36-37` `canAcknowledgeGroupRecovery => !skipped && skippedNoKeyCount==0 && errorCount==0` (whole-batch); `errorCount++` per-group `:162-163`; `RejoinGroupTopicsResult:23-38` carries only aggregate ints; no per-group map. Go ack node-wide (see §0). |
| P1.6 | Jitter + bounded backoff (+ migration) | **CONFIRMED-UNIMPLEMENTED** | Bare `Timer`/`Timer.periodic`, no jitter (`pending_message_retrier.dart:197/200-203/206-209`; constants `:23-27`). `retry_failed_group_messages_use_case.dart` re-sends all retryable rows, no cap/`next_eligible_at`. `retry_failed_group_inbox_stores_use_case.dart` only `LIMIT 20`. Uploads are the only capped path. **Migration = 082** (not 076). |
| P1.7 | Outbound repair in 30s sweep + terminal per-message state | **CONFIRMED-UNIMPLEMENTED** | `_runGroupContinuitySweepIfNeeded:267-321` does rejoin+drain+ack only (omits recover-stuck/uploads/retry-failed, which live only in `_retryIfNeeded`). No terminal per-message status. `isRecovering` shell + single-msg retry already exist. |

---

## 2. Collision map (drives sequencing — verified via `git status` / `git diff`)

| File | State | Owner of the dirt | Plan impact |
|---|---|---|---|
| `group_recovery_gate.dart` | **CLEAN** (zero drift) | — | P1.1 lands cleanly. **Start here.** |
| `pending_message_retrier.dart` | **CLEAN** | — | P1.3-retrier + P1.6-timers + P1.7-sweep safe. **Preserve the finding-125 GAP-3a ordering** (inbox-store custody-confirm `:416-426` BEFORE retry-failed `:428-438`). |
| `rejoin_group_topics_use_case.dart` | **CLEAN** | — | P1.5 Dart-eligibility safe. |
| `retry_failed_group_messages_use_case.dart` / `retry_failed_group_inbox_stores_use_case.dart` | **CLEAN** | — | P1.6 backoff logic safe (the *columns* need migration 082 — contended). |
| `main.dart` | DIRTY (+79) | findings 02/03 | P1.2 is a 1-line change in the **untouched** `:3088` initState region — low risk, rebase-sensitive line numbers. |
| `startup_router.dart` | DIRTY (+1) | finding-02 | Gate region `:655` untouched; trivial. |
| `handle_app_resumed.dart` | DIRTY (+25) | **finding-02 UDM-B** actively adding ungated Step 8i in the *exact* region P1.3-resume / P1.4 touch | **HIGH collision** — defer P1.3-resume + P1.4-caller until finding-02 lands. |
| `drain_group_offline_inbox_use_case.dart` | DIRTY | **finding-06** (hash) + **finding-10** (threads `pendingReactionRepo` through the drain signatures) | **HIGH collision** for P1.4 (continuation must thread the now-larger param set). Defer until finding-10 lands. |
| `app_database_version.dart` | DIRTY (→81) | findings 03/08/10 | Any new migration (082) collides; **claim the number at landing**. |
| `group_message_listener.dart` / `group_conversation_wired.dart` | DIRTY (+175 / reactions) | finding-10 | Not Phase-1 files; the `:4660` recovery-shell region is distinct from finding-10's `:4485/:4540` edits, so a future P1.7 badge has low collision there. |

---

## 3. Phase 1 — Gate serialization + provider OR-in + retrier-scoping *(pure Dart, no schema, CLEAN files)*

**Goal:** close the startup-fire-and-forget overlap and make the advisory flag accurate for the retrier path, on files with no active concurrent editor. This is the felt-correctness win at the lowest blast radius.

### P1.2 — Make the provider see the gate *(the live unlock; do first)* — TDD red→green
- **File:** `lib/main.dart` (provider wiring at `:3088-3090`, region clean).
- **Red:** in `pending_message_retrier_test.dart`, with the external-recovery provider returning `true` (simulating an active **startup** gate while `_isResuming` is false), assert the debounced first sweep no-ops and emits `PENDING_RETRIER_SKIPPED_EXTERNAL_RECOVERY`. (This already passes when `_isResuming` is true; the new test covers the *gate-active, resume-false* case, which today proceeds.)
- **Green:**
  ```dart
  widget.pendingMessageRetrier.setExternalRecoveryInProgressProvider(
    () => _isResuming || isGroupRecoveryInProgress(),
  );
  ```
  This makes the **existing** skip guard (`_retryIfNeeded:325-332`, sweep `:276-283`) cover the startup fire-and-forget — the actual residual hole.
- **Gate:** retrier unit test green; no behavior change when neither `_isResuming` nor the gate is active.

### P1.1 — `GroupRecoveryGate` → serializing mutex + `tryRun` *(foundational)* — TDD red→green
- **File:** `lib/features/groups/application/group_recovery_gate.dart` (CLEAN). Keep `_activeDepth` + `activeDepthListenable` exactly as-is (the `isRecovering` shell at `group_conversation_wired.dart:4660` depends on it — do not break that contract).
- **Red (new `group_recovery_gate_test.dart` cases):**
  1. two concurrent `run()` calls **serialize** — the second action's body starts only after the first completes (assert via ordered side-effect list); fails today (both run concurrently).
  2. `tryRun()` returns `null` while a pass is active/queued; fails today (no `tryRun`).
  3. `activeDepthListenable` still reflects depth during a pass (regression guard for the UI shell).
  4. an action that throws still releases the chain (next `run()` proceeds) and propagates the error to its own caller.
- **Green:** implement the serialization chain (`_tail` future) + `tryRun` per the spec's P1.1 sketch; add top-level `runWithGroupRecoveryGateOrSkip` mirroring `runWithGroupRecoveryGate`.
- **Caller policy:** **startup** (`startup_router.dart:655`) and **resume** (`handle_app_resumed.dart:196`) keep `run()` (must complete; now queue instead of overlap). **Retrier sweeps** adopt `tryRun()`/`runWithGroupRecoveryGateOrSkip` (skip-not-pile-on) — see P1.3.
- **Gate:** new gate tests green; existing `activeDepthListenable` consumers unaffected; full groups suite green.

### P1.3 (retrier half only) — wrap `_retryIfNeeded` in the gate *(CLEAN file)* — TDD red→green
- **File:** `lib/core/services/pending_message_retrier.dart` (CLEAN). Wrap the `_retryIfNeeded` group section in `runWithGroupRecoveryGate` so `isGroupRecoveryInProgress()` reads `true` while it re-sends messages (matching the 30s sweep at `:287`). With P1.1 serialization, the 5min/debounced pass and the continuity sweep can no longer overlap.
- **CRITICAL — preserve ordering:** the section order was expanded by finding-125 GAP-3a — `retryFailedGroupInboxStores` (custody-confirm) at `:416-426` runs **before** `retryFailedGroupMessages` (`:428-438`). The gate wrap must not reorder these.
- **Red:** in `pending_message_retrier_test.dart`, inject a probe into the retrier's recover-stuck/retry-failed fns asserting `isGroupRecoveryInProgress()==true` while they run; fails today (reads false). Add a test that the 12-step order is unchanged.
- **Green:** wrap the section; keep step order byte-for-byte.
- **Gate:** retrier suite green; ordering assertion green.

> **Phase-1 explicitly EXCLUDES** the `handle_app_resumed.dart` gate-boundary move (the resume half of P1.3) — that file is under active finding-02 editing in the exact region. Defer to Phase 1b after finding-02 lands.

---

## 3b. Phase 1b — Resume-side gate widening *(DEFERRED until `handle_app_resumed.dart` settles)*
Move the resume gate close from `:284` down to enclose the outbound-retry follow-ons (recover-stuck `:347`, uploads `:370`, retry-failed `:391`; ideally steps 8a-8i `:486-665`). **Blocked:** finding-02 UDM-B is actively adding ungated Step 8i (`retryAllPendingGroupKeyRepairsFn`) in this region. Re-derive the boundary after that commits; preserve the per-step fault-isolated try/catch. Minimum safe subset if needed sooner: wrap only `recoverStuck` + `retryFailed` (the message-resending steps) and document that uploads/inbox-store/key-repair retries are intentionally outside.

---

## 4. Phase 2 — First-page-fast resume drain + `drainGroupOfflineInboxContinuation` *(DEFERRED: drain file under active finding-06/10 edit)*

**Feasibility confirmed:** the first-page-stop path already exists (`_drainGroupInbox:911-944` persists the cursor + early-returns `GROUP_DRAIN_OFFLINE_INBOX_FIRST_PAGE_DONE`; cursor read at `:298`). So the continuation is a thin wrapper.

- **`drain_group_offline_inbox_use_case.dart`:** add `drainGroupOfflineInboxContinuation(...)` that re-runs the drain per group with `drainAllPages: true` starting from the persisted cursor. **Must thread the finding-10 `pendingReactionRepo` param** (and any other new params) — this is why it's deferred until finding-10 lands.
- **`handle_app_resumed.dart`:** call `drainGroupOfflineInbox(..., drainAllPages: false)` *inside* the gate (fast first page → feeds ack eligibility), then `unawaited(drainGroupOfflineInboxContinuation(...))` *outside* the gate. (Also under finding-02 edit — coordinate.)
- **TDD:** `app_lifecycle_recovery_test.dart` — drain called with `drainAllPages:false`; continuation scheduled `unawaited` outside the gate; first page renders before continuation completes. Integration: `group_multi_*_real_harness.dart` time-to-first-message vs time-to-full-drain.
- **No overlap with finding-06's hash rewrite** (`:1455-1487`) — disjoint region; textual-rebase only.

---

## 5. Phase 3 — Per-group recovery tracking; ack what can be acked

**Dart-only half is doable now** (`rejoin_group_topics_use_case.dart` is CLEAN); the true per-group Go ack is deferred (node-wide contract).

- **Dart eligibility fix (no schema):** add per-group outcomes to `RejoinGroupTopicsResult` (`Map<String, RejoinOutcome>` where outcome ∈ {joined, skippedNoKey, error, skippedDissolved}; keep aggregates for back-compat). Revise `canAcknowledgeGroupRecovery`: ack is eligible if **every group eligible to rejoin** (has a key, not dissolved) joined this pass or is already known-joined; **no-key groups do NOT block** the ack; transient errors block ack **only for affected groups**.
  - **TDD** (`rejoin_group_topics_use_case_test.dart`): one transient per-group error does NOT block ack of the others; no-key groups do not block ack; per-group attempt count increments; only failed groups retried next pass.
- **Bounded per-group retry:** track `rejoin_attempt_count` + `next_eligible_at` (needs the Phase-4 migration / a small `group_rejoin_state` surface) so the next pass retries only still-failing groups with backoff. Emit `GROUP_REJOIN_PERMANENTLY_STUCK` when a group exceeds its budget (greppable proof).
- **Go contract (deferred):** true per-group ack requires changing `GroupAcknowledgeRecovery()` (`bridge.go:861`), `Node.AcknowledgeGroupRecovery` (`node.go:1852`), `RelaySessionManager` (`relay_session.go:652`) to accept a `groupId` + gomobile rebuild. **Until then:** keep node-wide ack but compute eligibility over the *recoverable* set only (the Dart change alone fixes the common single-transient-failure strand). Update the two `APP_LIFECYCLE_RESUME_GROUP_ACK_SKIPPED` emit sites (`handle_app_resumed.dart:280`, `:332`).

---

## 6. Phase 4 — Migration **082** + jitter/backoff/attempt caps + terminal per-message status

**Migration number is `082`, not 076** (DB → v82). Claim the number *at landing* (the `078–081` band is contended; 081 = finding-10 `group_pending_reactions`). Mirror the additive-idempotent ALTER precedent `042_media_attachment_reliability_columns.dart:13/:30`.

- **`082_group_retry_backoff_columns.dart` (new):** add `retry_attempt_count INTEGER NOT NULL DEFAULT 0` + `next_eligible_at INTEGER` (epoch ms, nullable) to `group_messages` and the group-inbox-store surface, plus the P1.5 `group_rejoin_state` tracking. Bump `app_database_version.dart` to 82. Idempotent column-exists guards; no CHECK constraints.
  - **TDD:** migration test (idempotent ALTER, defaults, additive) following the `042` test pattern.
- **Timers (P1.6):** `pending_message_retrier.dart:197/200-209` — replace `Timer.periodic` with a self-rescheduling `Timer` recomputing a jittered delay each tick (`interval * (0.8 + random.nextDouble() * 0.4)`).
  - **TDD:** jittered delay falls within ±20% (inject a seeded RNG).
- **Per-row backoff:** `retry_failed_group_messages_use_case.dart` + `retry_failed_group_inbox_stores_use_case.dart` — select only rows where `next_eligible_at IS NULL OR <= now`; on failure `retry_attempt_count += 1`, `next_eligible_at = now + base * 2^attempt` (base 30s, cap 30min, ±20% jitter); reset on successful send or on a fresh offline→online transition (reconnect always gets one immediate attempt). New repo query/setters in `group_message_repository(+impl/db helpers)`.
  - **TDD:** future `next_eligible_at` rows skipped; attempt count climbs; exceeding cap flips to terminal `send_failed`; manual single-message retry still works.
- **Terminal per-message status + UI (P1.7):** introduce `send_failed` (permanently-failed) distinct from `failed`, set when `retry_attempt_count` exceeds cap; render a per-message manual-retry affordance in `group_conversation_wired/screen` (single-message `retryFailedGroupMessage` entry already exists at `:105`). Treat `send_failed` as a strict superset of `failed` on read paths; only the retry-eligibility query + the badge branch on it.
- **30s-sweep outbound repair (P1.7):** in `_runGroupContinuitySweepIfNeeded`, after drain add `recoverStuckSendingGroupMessagesFn` + `retryFailedGroupMessagesFn` (text-only); keep the heavier `retryIncompleteGroupUploadsFn` on the 5min cadence. (Retrier file is CLEAN — this part can land in Phase 1 if desired; grouped here for cohesion with the terminal-status work.)

---

## 7. Explicitly DEFERRED / sequencing

| Item | Decision | Reason |
|---|---|---|
| P1.3 resume-half (gate boundary move in `handle_app_resumed.dart`) | **DEFER to Phase 1b** | finding-02 UDM-B actively editing the exact region (Step 8i) — rebase after it lands. |
| P1.4 (drain continuation) | **DEFER to Phase 2** | `drain_..._use_case.dart` under active finding-06 + finding-10 edits; continuation must thread finding-10's `pendingReactionRepo`. |
| True per-group Go ack | **DEFER** | node-wide at all 4 layers; needs Go change + gomobile rebuild. Dart eligibility fix unblocks the common case first. |
| Migration 082 + backoff columns + terminal status | **DEFER to Phase 4** | migration namespace contended (078–081 in flight); claim 082 at landing. |
| Gap-repair per-group cooldown | **SKIP (optional)** | already first-success-stop; lowest priority. |

---

## 8. Test & verification strategy (per phase)

- **Phase 1 (unit):** `group_recovery_gate_test.dart` (serialize, `tryRun` null-while-active, depth-listenable intact, error-releases-chain); `pending_message_retrier_test.dart` (gate-active-resume-false → `PENDING_RETRIER_SKIPPED_EXTERNAL_RECOVERY`; `_retryIfNeeded` runs with `isGroupRecoveryInProgress()==true`; 12-step order preserved).
- **Phase 2:** `app_lifecycle_recovery_test.dart` (`drainAllPages:false`; continuation unawaited outside gate; first-page-before-full-drain); integration `group_multi_*_real_harness.dart`.
- **Phase 3:** `rejoin_group_topics_use_case_test.dart` (one transient error doesn't block other groups; no-key doesn't block; per-group attempt count; only-failed-retried).
- **Phase 4:** migration `082` test (additive/idempotent, `042` pattern); `retry_failed_group_messages_use_case_test.dart` (future `next_eligible_at` skipped; cap → terminal `send_failed`; manual retry works); jitter within ±20%.
- **Integration:** extend `integration_test/group_recovery_e2e_test.dart` — assert no duplicate `GROUP_DRAIN_*` across overlapping startup+retrier passes (single-pass), and a node with one un-rejoinable group still acks recovery for the rest (no sticky `needsGroupRecovery`).
- **Greppable device proofs:** `PENDING_RETRIER_SKIPPED_EXTERNAL_RECOVERY`, `GROUP_REJOIN_PERMANENTLY_STUCK`, per-row backoff scheduling events, `GROUP_DRAIN_OFFLINE_INBOX_FIRST_PAGE_DONE`.

---

## 9. Rollout order (collision-aware)

1. **Phase 1** (CLEAN files): P1.2 provider OR-in → P1.1 gate mutex + `tryRun` → P1.3 retrier-half wrap (preserve finding-125 order). *No schema; ships behind `enableResumeGroupRecovery` (default true).* **Optionally** fold in P1.7's 30s-sweep outbound-repair (retrier is clean).
2. **Phase 1b** (after finding-02 lands): resume-side gate widening in `handle_app_resumed.dart`.
3. **Phase 2** (after finding-10 lands): first-page-fast drain + `drainGroupOfflineInboxContinuation`.
4. **Phase 3** (Dart eligibility now; Go per-group ack later): per-recoverable-set ack.
5. **Phase 4** (claim migration 082 at landing): backoff columns + jitter + terminal `send_failed` + manual-retry UI.

Each phase is independently shippable and testable. Phases 1 + 1b + 2 deliver most of the felt latency/jank + convergence win at the lowest risk; Phases 3–4 carry the Go-contract + schema dependencies.
