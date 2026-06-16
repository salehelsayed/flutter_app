> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P1** · [Findings appendix](./appendix-findings.md)

> ⚠️ **Superseded for implementation by [`05-P1-recovery-orchestration-hardening-TDD-plan.md`](./05-P1-recovery-orchestration-hardening-TDD-plan.md)** (verified 5-agent recon, 2026-06-16). All 7 findings + R1–R6 are still confirmed-unimplemented, but this spec's audit (2026-06-06) is stale: **proposed migration `076` is wrong — it already exists; the next free is `082` (DB v82)**; the Go ack is `bridge.go:861` (node-wide); **every line number drifted +4 to +663**; and the retrier already has an external-recovery skip guard (keyed to `_isResuming` only) + the resume ack already runs inside the gate. Use the TDD plan for line numbers, the corrected migration, reframed findings, and collision-aware phasing. This doc remains the source of intent (the prose findings).

---

# Harden recovery orchestration: real locking, scoping, and backoff

**Priority: P1** — reliability / performance / UX. Effort: **Large** (multiple touched subsystems, one schema migration, broad test surface).

> **Audit 2026-06-06:** all 7 current-behaviour findings and all 7 proposed improvements (P1.1–P1.7) are still unimplemented and accurate. The duplicate-delivery cascade work (doc 01) did NOT absorb any of this doc's fixes: the gate is still a counter, the retrier provider still watches only `_isResuming`, the resume drain is still all-pages, the ack is still all-or-nothing, and there is no jitter/backoff/terminal status. (Line numbers refreshed; proposed migration renumbered from 073 to 076 — 073/074 now exist.)

This theme turns the group-chat recovery layer from a collection of independently-firing passes guarded by an *advisory* flag into a properly serialized, correctly scoped, fast-first-page, jitter/backoff-aware pipeline. The work is significant but largely mechanical: it adds real mutual exclusion, widens the gate to the right boundaries, splits the resume drain into fast/background phases, makes the recovery ack per-group instead of all-or-nothing, and adds jitter + bounded exponential backoff to the retry timers and per-row retries.

---

## Why this matters (user experience)

Coming back online is the single most performance-sensitive moment in the app: the user is staring at a group thread waiting for missed messages to appear. Today, several recovery passes can run **at the same time on the same groups**, each repeating the same bridge decode work and DB writes, contending on the SQLCipher connection exactly when latency is most visible. Cursor advancement from one pass can make another re-process the same page. The resume sequence blocks on draining *every page of every group* before the UI settles. A single transient rejoin error on one topic strands the whole node in `needsGroupRecovery`, so it keeps re-running the full pipeline on every state change and never converges. And after a relay outage, every client retries on fixed 5min/30s cadences with no jitter, producing synchronized thundering-herd load on the relay and peers precisely when catch-up matters most.

The net effect is that "coming back online" feels janky and slow. Fixing this makes catch-up fast, predictable, and self-healing.

---

## Current behaviour & evidence

### 1. The gate is advisory, not a lock
`GroupRecoveryGate` is a re-entrant *counter*. `begin()`/`end()` only increment/decrement `_activeDepth`; `run()` never serializes — it just brackets the action with `begin()`/`end()` (`lib/features/groups/application/group_recovery_gate.dart:10-30`, run() at :23-30). The design doc states this explicitly: it "does not itself reject or serialize concurrent callers" (`Test-Flight-Improv/Group-Chat-Feature/C4-05-Recovery-And-Reliability.md:142`).

Mutual exclusion is a patchwork across three entry points:
- **Startup** wraps recovery fire-and-forget in `runWithGroupRecoveryGate` with no other guard (`lib/features/identity/presentation/startup_router.dart:578-602`).
- **Resume** sets `_isResuming = true` (`lib/main.dart:3103`) which the retrier reads via its external-recovery provider, wired to `() => _isResuming` (`lib/main.dart:2425-2426`).
- The **retrier** observes only `_isResuming` — **not** the startup fire-and-forget. Its first online sweep is debounced 5s and scheduled in `start()` (`lib/core/services/pending_message_retrier.dart:125-127, 163-171`), and `pendingMessageRetrier.start()` runs during the same startup sequence (`lib/main.dart:2099`).

So the retrier's `_retryIfNeeded` (which itself calls rejoin + drain + recover-stuck + retry-failed, `pending_message_retrier.dart:290-530`) can fire while startup's drain is still running — both calling `rejoinGroupTopics` + `drainGroupOfflineInbox` on the full group set with no mutual exclusion.

### 2. Follow-on retries run OUTSIDE the gate (scoping is inconsistent)
In `handle_app_resumed.dart` the `runWithGroupRecoveryGate` block opens at line 148 and **closes at line 222**. Everything after runs outside the gate: `recoverStuckSendingGroupMessagesFn` (line 270), `retryIncompleteGroupUploadsFn` (line 293), `retryFailedGroupMessagesFn` (line 314), and all of steps 8a-8f (lines 408-528). While those run, `isGroupRecoveryInProgress()` reads `false`.

That flag is the guard that protects mutating operations: announcement sends gate on it (`send_group_message_use_case.dart:691`, now conditioned on `group.type == GroupType.announcement && isGroupRecoveryInProgress()`), as do member-role changes (`update_group_member_role_use_case.dart:38`), avatar updates (`group_info_wired.dart:1443/1543`), and (per the same pattern) `add_group_member`, `remove_group_member`, and `update_group_metadata`. So while the stuck-sweep is actively re-sending group messages, those mutations are no longer blocked.

The same inconsistency is *worse* in the retrier: only `_runGroupContinuitySweepIfNeeded` (the 30s sweep) wraps its rejoin+drain in `runWithGroupRecoveryGate` (`pending_message_retrier.dart:235-288`). The main `_retryIfNeeded` path (lines 290-530) wraps **nothing** — even its rejoin/drain/ack/recover-stuck/retry-failed all run with the gate reading false.

### 3. Resume blocks on draining ALL pages of ALL groups
`drainGroupOfflineInbox` defaults `drainAllPages = true`, `maxPages = 100`, `pageSize = 50`, `maxConcurrentGroupDrains = 4` (`drain_group_offline_inbox_use_case.dart:75-78, 27-28`). The function's own doc describes a "first page synchronous + background continuation via `drainGroupOfflineInboxContinuation`" design (lines 56-61) — but the resume caller awaits `drainGroupOfflineInbox` **without** passing `drainAllPages: false` (`handle_app_resumed.dart:180-191`), and the whole call sits inside the awaited gate block. **Note:** the cited continuation function `drainGroupOfflineInboxContinuation` does not actually exist in the codebase — the doc comment is aspirational. So resume blocks on the full multi-page drain of every group before completing, and the background-continuation path it claims to support has never been implemented.

### 4. All-or-nothing recovery ack strands the node
`canAcknowledgeGroupRecovery` requires `!skipped && skippedNoKeyCount == 0 && errorCount == 0` across the entire batch (`rejoin_group_topics_use_case.dart:36-37`). Any single per-group exception increments `errorCount` (lines 162-182). Resume only acks when `needsGroupRecovery && rejoinResult.canAcknowledgeGroupRecovery && groupDrainResult.isSuccessful` (`handle_app_resumed.dart:200-202`); otherwise it emits `APP_LIFECYCLE_RESUME_GROUP_ACK_SKIPPED` and leaves `needsGroupRecovery` set (lines 213-221). The next online transition then re-triggers the entire pipeline (`pending_message_retrier.dart:101-128`). There is **no per-group recovery tracking** — one transient failure on one topic blocks the ack for all groups, potentially forever, with only a flow-log signal.

### 5. No backoff / no jitter anywhere
Timers use fixed intervals scheduled bare via `Timer` / `Timer.periodic`: `periodicRetryInterval = 5min`, `groupContinuitySweepInterval = 30s`, `retryDebounce = 5s` (`pending_message_retrier.dart:22-26, 163-177`). `retryFailedGroupMessages` re-sends every failed row each pass with no per-message backoff or attempt cap (`retry_failed_group_messages_use_case.dart:193-207`). `retryFailedGroupInboxStores` has only a per-pass limit (default 20) and no per-row attempt cap/delay (`retry_failed_group_inbox_stores_use_case.dart:28, 76-106`). Only uploads have a ceiling (`kMaxUploadRetries`, `retry_incomplete_group_uploads_use_case.dart:373, 480`). History-gap repair runs on every drain when gaps exist, iterating `authorizedSources` (`drain_group_offline_inbox_use_case.dart:1192`) — though it breaks on the first successful source (lines 1291-1292), so it only fans out to all peers while each is failing.

### 6. The 30s sweep skips outbound repair
`_runGroupContinuitySweepIfNeeded` does rejoin + drain + ack only (`pending_message_retrier.dart:235-288`); it omits `recoverStuckSendingGroupMessagesFn` / `retryIncompleteGroupUploadsFn` / `retryFailedGroupMessagesFn`, which live only in `_retryIfNeeded` (lines 350-385). So a foreground-but-alive app that never hits a fresh offline→online transition only repairs outbound sends every 5 minutes, even though inbound catch-up runs every 30s.

### 7. Recovery is largely silent per-message
Recovery use cases communicate only via `emitFlowEvent` (e.g. `RETRY_FAILED_GROUP_MESSAGES_MESSAGE_STILL_FAILED`, `retry_failed_group_messages_use_case.dart:314-321`). There is no terminal `permanently_failed` status distinct from `failed`, so the UI cannot tell "still retrying" from "gave up." A gate-driven "catching up" shell *does* already exist (`group_conversation_wired.dart:4270` passes `isRecovering` into `group_conversation_screen.dart:325`), so the genuine remaining gap is a **per-message** terminal-failure state + manual-retry affordance — not the overall indicator.

---

## Root cause(s)

| # | Root cause | Symptom it produces |
|---|------------|---------------------|
| R1 | `GroupRecoveryGate.run()` is a counter, not a mutex; no caller waits for or skips an in-progress pass | Overlapping startup + retrier + resume passes duplicating decode/DB work, cursor thrash |
| R2 | The retrier's external-recovery provider only observes `_isResuming`, ignoring the startup fire-and-forget | Retrier sweeps during startup recovery |
| R3 | Gate boundaries are drawn around rejoin+drain only; follow-on retries (and the entire `_retryIfNeeded` path) sit outside | Mutations interleave with active recovery; advisory flag is inaccurate end-to-end |
| R4 | Resume uses the all-pages default and there is no continuation implementation | UI settles late on heavy backlog |
| R5 | Ack eligibility is a whole-batch boolean; recovery state is a single node-wide flag, not per-group | One transient failure strands the whole node |
| R6 | Timers and per-row retries have no jitter, no backoff, no attempt caps (except uploads) | Thundering-herd load, indefinite re-tries of permanently-failing rows |

---

## Proposed improvements

### P1.1 — Make `GroupRecoveryGate` a real serializing primitive
Convert `run()` to serialize concurrent callers, and add a non-blocking `tryRun()` for callers that should skip rather than queue. Keep the `_activeDepth` counter and `activeDepthListenable` for the UI "catching up" shell (do not break that contract). File: `lib/features/groups/application/group_recovery_gate.dart`.

```dart
class GroupRecoveryGate {
  int _activeDepth = 0;
  final ValueNotifier<int> _activeDepthListenable = ValueNotifier<int>(0);
  Future<void> _tail = Future<void>.value(); // serialization chain

  bool get isActive => _activeDepth > 0;
  ValueListenable<int> get activeDepthListenable => _activeDepthListenable;

  // Serializes: callers run one after another, never concurrently.
  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final prior = _tail;
    _tail = completer.future.then((_) {}, onError: (_) {});
    () async {
      await prior; // wait for the in-flight pass
      _enter();
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        _leave();
      }
    }();
    return completer.future;
  }

  // Returns null immediately if a pass is already active/queued.
  Future<T?> tryRun<T>(Future<T> Function() action) async {
    if (isActive) return null;
    return run(action);
  }

  void _enter() { _activeDepth += 1; _activeDepthListenable.value = _activeDepth; }
  void _leave() { if (_activeDepth > 0) { _activeDepth -= 1; _activeDepthListenable.value = _activeDepth; } }
}
```

Add a top-level `runWithGroupRecoveryGateOrSkip` mirroring `runWithGroupRecoveryGate`. Decide policy per caller:
- **Startup** and **resume**: use `run()` (they must complete; serialize so they queue rather than overlap).
- **Retrier sweeps** (`_retryIfNeeded`, `_runGroupContinuitySweepIfNeeded`): use `tryRun()` — if recovery is already active, skip this tick entirely instead of piling on. This is the core de-duplication.

### P1.2 — Make the retrier observe ALL external recovery, not just resume
The retrier should treat *any* active gate as "external recovery in progress." Extend the provider to OR-in the gate state. In `lib/main.dart:2425-2426`:

```dart
widget.pendingMessageRetrier.setExternalRecoveryInProgressProvider(
  () => _isResuming || isGroupRecoveryInProgress(),
);
```

Combined with P1.1's `tryRun`, the retrier's first 5s online sweep will now no-op while startup's drain is still inside the gate (fixes R1/R2).

### P1.3 — Widen the gate to the full recovery pipeline (fix scoping)
Draw the gate boundary around the *entire* recovery sequence so the advisory flag is accurate end-to-end and mutation guards actually hold while stuck/failed retries (which re-send messages) run.

- **`handle_app_resumed.dart`:** move the closing of `runWithGroupRecoveryGate` from line 222 down to enclose at least steps 3d-3f (recover-stuck + retry-incomplete-uploads + retry-failed-group). Strongly recommend enclosing 8a-8f as well so the single flag covers the whole pass. Net change: one block boundary moves; the existing fault-isolated try/catch per step is preserved.
- **`pending_message_retrier.dart`:** wrap the entire `_retryIfNeeded` group section (lines 319-385, and ideally the whole body) in `runWithGroupRecoveryGate` so it matches the continuity sweep. With P1.1 serialization this also means the periodic 5min pass and the debounced online pass can never overlap.

If the team prefers minimal blast radius, the *minimum* safe fix is wrapping `recoverStuck` + `retryFailed` (the message-resending steps) inside the gate; document explicitly that uploads/intro/inbox-store retries are intentionally outside.

### P1.4 — Drain first page fast on resume, finish in background
Implement the documented (but missing) `drainGroupOfflineInboxContinuation`, and change the resume caller to a two-phase drain.

- In `drain_group_offline_inbox_use_case.dart`: add `drainGroupOfflineInboxContinuation(...)` that re-runs `_drainGroupInbox` for each group with the *same* cursor semantics but starting from the persisted cursor (so it resumes where the first-page pass stopped), iterating remaining pages up to `maxPages`. The per-group cursor is already persisted across pages, so the continuation is a thin wrapper that calls the existing drain with `drainAllPages: true` after the first synchronous page.
- In `handle_app_resumed.dart:180-191`: call `drainGroupOfflineInbox(..., drainAllPages: false)` *inside* the gate (fast first page), capture its result for ack eligibility, then `unawaited(drainGroupOfflineInboxContinuation(...))` *outside* the gate to finish remaining pages in the background.

This keeps the gate window short and makes the conversation interactive after one page per group instead of up to 100. Ack eligibility (P1.5) is computed from the first-page drain result; the continuation does not gate the ack.

### P1.5 — Per-group recovery tracking; ack what can be acked
Replace the all-or-nothing batch ack with per-group recovery state so one transient failure cannot strand the node.

- In `rejoin_group_topics_use_case.dart`: have `RejoinGroupTopicsResult` carry per-group outcomes (`Map<String, RejoinOutcome>` where outcome ∈ {joined, skippedNoKey, error, skippedDissolved}) in addition to the existing aggregate counts (keep those for back-compat).
- Distinguish **permanent skips** (no key → cannot rejoin, not a failure) from **transient errors**. `canAcknowledgeGroupRecovery` should become: ack is eligible if *every group that is eligible to rejoin* (has a key, not dissolved) either joined this pass or is already known-joined. No-key groups should NOT block the ack (they were never recoverable). Transient errors block ack *only for the affected groups*.
- Add **bounded retry of just the failed groups** before giving up: track a per-group `rejoin_attempt_count` + `next_eligible_at` (see P1.6 schema) so the next pass retries only the still-failing groups, with backoff, instead of re-running the whole batch on every state change.
- Surface a diagnostic when a group has exceeded its rejoin attempt budget so a permanently-stuck `needsGroupRecovery` is observable (greppable flow event, e.g. `GROUP_REJOIN_PERMANENTLY_STUCK`).

**Wire/Go impact:** `callGroupAcknowledgeRecovery` is currently node-wide. If Go can accept a per-group ack, prefer acking each successfully-recovered group individually; otherwise keep the node-wide ack but only fire it once the *eligible* set is fully recovered (the Dart-side change alone already unblocks the common single-transient-failure case). Confirm the Go ack contract before choosing — as of 2026-06-06 `GroupAcknowledgeRecovery()` (`go-mknoon/bridge/bridge.go:656`) is still node-wide, so this open question stands.

### P1.6 — Jitter + bounded exponential backoff
Add jitter to the timers and a per-row backoff schedule.

- **Timers** (`pending_message_retrier.dart:163-177`): apply ±20% jitter. Replace `Timer.periodic` with a self-rescheduling `Timer` that recomputes a jittered delay each tick (e.g. `interval * (0.8 + random.nextDouble() * 0.4)`), so clients de-synchronize after a shared relay outage.
- **Per-row backoff (DB migration 076):** add `retry_attempt_count INTEGER NOT NULL DEFAULT 0` and `next_eligible_at INTEGER` (epoch ms, nullable) to the `group_messages` table and the group-inbox-store + (per P1.5) a small `group_rejoin_state` tracking surface. Follow the existing `upload_retry_count` precedent (`042_media_attachment_reliability_columns.dart`). Latest migration is **074**, so this is **076**. (Note: `073_group_message_last_send_attempt_at.dart` already added a `last_send_attempt_at` column to `group_messages`, but NOT the proposed `retry_attempt_count`/`next_eligible_at` columns — those remain to be added.)
  - `retry_failed_group_messages_use_case.dart`: only select rows where `next_eligible_at IS NULL OR next_eligible_at <= now`; on each failed attempt set `retry_attempt_count += 1` and `next_eligible_at = now + base * 2^attempt` (capped, e.g. base 30s, cap 30min, ±20% jitter). When `retry_attempt_count` exceeds a cap (mirror `kMaxUploadRetries`), flip the row to a terminal status (see P1.7).
  - `retry_failed_group_inbox_stores_use_case.dart`: same backoff + attempt cap.
- **Gap repair** is already first-success-stop; lower priority. Optionally gate re-running gap detection behind a per-group cooldown so it doesn't re-scan on every drain.

### P1.7 — Outbound repair in the 30s sweep + terminal per-message state (lower priority, folds in cleanly)
- In `_runGroupContinuitySweepIfNeeded`, after drain, add a lightweight outbound-repair step: `recoverStuckSendingGroupMessagesFn` + `retryFailedGroupMessagesFn` (text-only). Keep the heavier `retryIncompleteGroupUploadsFn` on the 5min cadence. This closes the "outbound sits failed up to 5min" gap for foreground-alive apps.
- Introduce a terminal `send_failed` (permanently-failed) status distinct from `failed`, set when `retry_attempt_count` exceeds cap, and render a per-message manual-retry affordance in the group timeline (the single-message `retryFailedGroupMessage` entry point already exists, `retry_failed_group_messages_use_case.dart:97`). This is the genuine per-message UX gap from finding 7.

---

## Affected files & components

| File | Change |
|------|--------|
| `lib/features/groups/application/group_recovery_gate.dart` | Serializing `run()` + `tryRun()` + `runWithGroupRecoveryGateOrSkip` (P1.1) |
| `lib/main.dart` | External-recovery provider ORs in `isGroupRecoveryInProgress()` (P1.2) |
| `lib/core/services/pending_message_retrier.dart` | Sweeps use `tryRun`; wrap `_retryIfNeeded` in gate; jittered self-rescheduling timers; outbound repair in 30s sweep (P1.1/1.3/1.6/1.7) |
| `lib/features/identity/presentation/startup_router.dart` | Startup uses serializing `run()` (P1.1) |
| `lib/core/lifecycle/handle_app_resumed.dart` | Move gate boundary to enclose follow-on retries; first-page-fast drain + background continuation; per-group ack eligibility (P1.3/1.4/1.5) |
| `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` | Implement `drainGroupOfflineInboxContinuation`; first-page-only path (P1.4) |
| `lib/features/groups/application/rejoin_group_topics_use_case.dart` | Per-group outcomes; transient-vs-permanent split; revised `canAcknowledgeGroupRecovery`; bounded per-group retry (P1.5) |
| `lib/features/groups/application/retry_failed_group_messages_use_case.dart` | Backoff schedule, attempt cap, terminal status (P1.6/1.7) |
| `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart` | Backoff schedule + attempt cap (P1.6) |
| `lib/core/database/migrations/076_group_retry_backoff_columns.dart` (new) | `retry_attempt_count`, `next_eligible_at`, group-rejoin state (P1.5/1.6) |
| `lib/features/groups/domain/repositories/group_message_repository.dart` (+impl/db helpers) | New query: eligible failed rows by `next_eligible_at`; setters for attempt/next-eligible/terminal status |
| `lib/features/groups/presentation/screens/group_conversation_wired.dart` / `group_conversation_screen.dart` | Per-message terminal `send_failed` badge + manual retry affordance (P1.7) |

---

## Test & verification strategy

**Unit (Dart, fastest signal):**
- `group_recovery_gate_test.dart` (new/extended): two concurrent `run()` calls serialize (second starts only after first completes); `tryRun()` returns `null` while active; `activeDepthListenable` still reflects depth for the UI shell.
- `pending_message_retrier_test.dart`: with the external-recovery provider returning true (simulating an active gate), the debounced first sweep no-ops (assert `PENDING_RETRIER_SKIPPED_EXTERNAL_RECOVERY`); jittered timer fires within ±20% window; 30s sweep now invokes the injected outbound-repair fns.
- `handle_app_resumed` test (`app_lifecycle_recovery_test.dart`): drain called with `drainAllPages: false`; continuation scheduled (unawaited) outside the gate; `isGroupRecoveryInProgress()` reads true across recover-stuck/retry-failed steps via a probe injected into those fns.
- `rejoin_group_topics_use_case_test.dart`: one transient per-group error does NOT block ack of the other groups; no-key groups do not block ack; per-group attempt count increments and only failed groups are retried next pass.
- `retry_failed_group_messages_use_case_test.dart`: rows with `next_eligible_at` in the future are skipped; attempt count climbs; exceeding cap flips to terminal `send_failed`; manual single-message retry still works.
- Migration test for `076` (idempotent ALTER, default values, CHECK-free additive columns) following the `042` test pattern.

**Integration harnesses (this repo's `integration_test/`):**
- `integration_test/group_recovery_e2e_test.dart` — extend to assert no duplicate decode/DB writes across overlapping startup + retrier passes (e.g. count `GROUP_DRAIN_*` flow events for a group during a single recovery and assert single-pass), and that a node with one un-rejoinable group still acks recovery for the rest (no sticky `needsGroupRecovery`).
- `integration_test/group_multi_device_real_harness.dart` / `group_multi_party_device_real_harness.dart` — background→resume with heavy backlog: assert first page renders before continuation completes (measure time-to-first-message vs. time-to-full-drain).

**Device matrix / Test-Flight-Improv:**
- Add rows to the recovery matrices (`Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `52-notification-journey-test-matrix.md`) covering: (a) cold-start-while-retrier-starts no-overlap; (b) resume with 100-page backlog first-page latency; (c) one-group-fails-rejoin still converges; (d) relay-outage thundering-herd de-sync (observe jittered retry timestamps across N devices). Update `C4-05-Recovery-And-Reliability.md:142` to describe the gate as a real serializing primitive.
- Greppable flow-event proofs: `GROUP_REJOIN_PERMANENTLY_STUCK`, retrier skip events, and per-row backoff scheduling events provide log-based verification on real devices (the repo's standard proof mechanism).

---

## Risks, trade-offs & rollout

| Risk | Mitigation |
|------|------------|
| Serializing the gate could **deadlock** if a gated action awaits another gate acquisition (re-entrancy) | The new `run()` queues rather than re-enters; audit for nested `runWithGroupRecoveryGate` calls (startup/resume currently do not nest). Keep the depth counter purely for UI; do not gate on it for serialization. |
| Widening the gate **lengthens the window** where mutations (sends, membership) are blocked | P1.4 (first-page-fast) keeps the *blocking* window short; the long-tail continuation runs outside the gate, so user-facing mutations are only blocked during the fast phase. |
| Per-group ack changes **Go's recovery contract** | Confirm whether Go supports per-group ack; if not, keep node-wide ack but compute eligibility over the *recoverable* set only — a Dart-only change that still fixes the common case. Feature-flag behind `enableResumeGroupRecovery` (already exists). |
| Backoff could **delay legitimate retries** of a row that would now succeed | Cap backoff (e.g. 30min) and reset `retry_attempt_count`/`next_eligible_at` on a successful send or on a fresh offline→online transition, so reconnect always gives one immediate attempt. |
| Migration 076 on existing installs | Additive, idempotent ALTER with defaults (mirror `042`); no CHECK constraints; safe on upgrade. |
| Terminal `send_failed` status touches UI + every status read | Treat `send_failed` as a strict superset behavior of `failed` for read paths; only the retry-eligibility query and the per-message badge branch on it. |

**Rollout:** ship behind the existing `enableResumeGroupRecovery` flag in phases — (1) gate serialization + provider OR-in + scoping (pure correctness, no schema); (2) first-page-fast drain + continuation (UX latency); (3) per-group ack (Go-contract-dependent); (4) migration 076 + backoff/jitter + terminal status + manual-retry UI. Each phase is independently shippable and independently testable.

---

## Effort estimate

| Phase | Scope | Effort |
|-------|-------|--------|
| 1 | Gate → serializing mutex + `tryRun`; provider OR-in; widen scope in resume + retrier | **M** (no schema; high test value, low blast radius) |
| 2 | First-page-fast resume drain + implement continuation | **M** |
| 3 | Per-group recovery tracking + ack-what-can-be-acked | **M-L** (depends on Go ack contract) |
| 4 | Migration 076 + jitter/backoff/attempt caps + terminal `send_failed` + manual-retry UI | **L** |

**Overall: Large.** Phases 1-2 deliver most of the felt latency/jank win and carry the lowest risk; phases 3-4 deliver the convergence/self-healing and thundering-herd wins and carry the schema + Go-contract dependencies.
