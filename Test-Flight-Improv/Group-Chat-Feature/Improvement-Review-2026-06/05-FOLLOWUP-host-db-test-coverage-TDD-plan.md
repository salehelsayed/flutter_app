> Part of the **[Group Chat Improvement Review](./README.md)** · Follow-up to [05 recovery-orchestration TDD plan](./05-P1-recovery-orchestration-hardening-TDD-plan.md) · Priority **P2 (test-debt, non-blocking)**

---

# 05 — Follow-up: Host real-DB coverage for the new Phase-3 / Phase-4 SQL surfaces

**Status: IMPLEMENTED 2026-06-17 (host-green, format + analyze clean). All 3 phases landed.**
> - **Phase A** — `test/core/database/helpers/group_rejoin_state_db_helpers_test.dart` (NEW, `sqflite_common_ffi`): 9/9 green. 088 schema (columns/PK/DEFAULT-0/nullable/idempotent) + first-failure-attempt-1 + ON CONFLICT upsert-increment (one row) + per-group independence + clear-target-only + clear-absent-noop + exact epoch-ms UTC round-trip.
> - **Phase B** — `test/core/database/helpers/group_message_retry_backoff_db_helpers_test.dart` (NEW, `sqflite_common_ffi`): 10/10 green. 087 idempotent ALTER + defaults; `dbRecordGroupMessageRetryFailure` increment/schedule/terminal-flip/never-touch-terminal-or-incoming; `dbLoadRetryableOutgoingGroupMessages` eligibility filter (NULL/past eligible, backed-off/terminal/incoming excluded) + limit; `dbClearGroupMessageRetryBackoff` reconnect re-arm (leaves terminal); `dbResetGroupMessageRetryState` manual re-arm (terminal-only); **clobber-safety** — a normal `dbInsertGroupMessage` re-save (toMap-shaped, backoff cols omitted) goes through the duplicate-insert `_updateGroupMessageRow` UPDATE path and does NOT reset `retry_attempt_count`/`next_eligible_at`.
> - **Phase C** — `test/core/database/integration/full_migration_chain_test.dart`: added 087 + 088 to `runFreshInstallMigrations` + asserts a fresh install ends with `group_messages.retry_attempt_count`/`next_eligible_at` and the `group_rejoin_state` table. Chain test green.
> - **No production code changed; no new migration; no flag.** The `@Tags(['device'])` SQLCipher proofs are untouched — these back-fill the missing fast host layer beneath them. Combined run: **All tests passed!** (Phase A +9, Phase B +10, chain +27 incl. new asserts); `dart format` clean; `flutter analyze` "No issues found!".

---

**Status: GAP CONFIRMED (15-agent verify+refute workflow 2026-06-17 + 1st-party grep audit).**
**Scope: TEST-ONLY. Production code for findings 05 + 06 is FULLY IMPLEMENTED, wired, and host-green — this plan closes a single test-harness gap. There is no implementation gap and nothing to ship behind a flag.**

## 0. What the verification found (so this plan stays scoped)

A full re-verification of plans 05 and 06 against the working tree (not HEAD — both are uncommitted) found **everything implemented and host-green**:

- **Plan 06** — Phase 1A (Dart `{from,message,timestamp ?? 0}` projection), 1B (cross-language golden vector `957339b5…` Dart==Go, + a 2nd realistic-envelope golden `d198d184…`), 1C (`SetEscapeHTML(false)`), Phase 2 (dead `groupInboxCappedCounter` now `.Add()`'d in **both** memory + redis backends, double-count-safe). Dart suite **122/122**, Go relay `go test ./...` **green (13.5s)**. All deferred items (Improvements 2-full / 4 / 5 / 6) are **legitimate, evidence-backed defers** (the cheap operator-visible counter half of Improvement 2 *was* built; Improvement 4 has zero prod callers; Improvement 5/Redis is not the deployed backend; Improvement 6 is a boundary-only single-message edge whose dominant direction is intended).
- **Plan 05** — Phase 1 (gate FIFO-serialize + `tryRun` + `runWithGroupRecoveryGateOrSkip`, provider OR-in, retrier wrap w/ GAP-3a order), Phase 1b (resume 3d/3e/3f gated), Phase 2 (`hasMorePages` + `onFirstPageStopped` + `drainGroupOfflineInboxContinuation`, first-page-inside-gate / continuation-outside, ack-doesn't-purge-relay verified), Phase 3 (`RejoinOutcome` + per-group map + `canAcknowledgeGroupRecovery => !skipped && errorCount==0` + bounded rejoin retry / mig **088** / `GROUP_REJOIN_PERMANENTLY_STUCK`), Phase 4 (mig **087** backoff columns w/ correct `fromMap`-read/`toMap`-omit asymmetry, exp backoff base 30s ×2 cap 30min, terminal `send_failed`, manual re-arm, reconnect-clear, ±20% jitter, LetterCard + screen UI). Host suites **gate 8/8 · retrier 27/27 · rejoin 32/32 · retry-failed 24/24**, all green.
- **Go per-group ack SKIP = DEFERRED_OK (not laziness):** the node's recovery signal is a single `needsGroupRecovery bool` set by the **relay** watchdog; the node holds no per-group recovery state and doesn't enumerate groups (they live in Dart/DB). A `groupId`-parameterized ack would be a no-op param + a gomobile rebuild for zero value. The Dart eligibility-over-recoverable-set fix (Phase 3) is the correct complete solution.
- **Device proofs exist and are build-time-clean:** `integration_test/group_recovery_gate_serialization_proof_test.dart`, `integration_test/group_rejoin_state_db_proof_test.dart`, `integration_test/group_message_retry_backoff_db_proof_test.dart` — all `@Tags(['device'])`, all under `integration_test/`, so a default `flutter test` (test/-only scope) **never compiles or runs them**. Zero host build-time bloat.

### The one real gap

The **new raw-SQL DB surfaces** introduced by Phase 3 + Phase 4 are exercised against a real database **only** in those `@Tags(['device'])` proofs (excluded from routine host/CI runs) and via the pure-Dart `InMemory*` fakes (which *reimplement* the increment/filter logic in Dart). The repo's own fast host-real-DB convention — **26 `*_db_helpers_test.dart` files, 102 files using `sqflite_common_ffi`** — was skipped for them. Confirmed by grep:

| New SQL surface | Host real-DB test | Device proof | In-memory fake |
|---|---|---|---|
| `group_rejoin_state_db_helpers.dart` (mig **088**) | **ABSENT** (`group_rejoin_state` appears in **0** files under `test/`) | ✅ `group_rejoin_state_db_proof_test.dart` (device) | ✅ `InMemoryGroupRepository` (Dart reimpl) |
| `group_messages` backoff queries (mig **087**: `dbLoadRetryableOutgoingGroupMessages` filter, `recordRetryFailure`, `clearRetryBackoff`, `resetRetryStateForManualRetry`) | **ABSENT** (`group_messages_db_helpers_test.dart` has **0** refs to `next_eligible_at`/`retry_attempt_count`; the only host ref is the use-case test, which runs the fake) | ✅ `group_message_retry_backoff_db_proof_test.dart` (device) | ✅ `InMemoryGroupMessageRepository` (Dart reimpl) |
| Migrations 087 + 088 fresh-install schema | **ABSENT** (`full_migration_chain_test.dart` `runFreshInstallMigrations` never calls either migration; never creates either surface) | partial (each proof runs its own migration in `setUp`) | n/a |

**Why it matters (against the user's stated criteria #2 "integrated into the harness, minimizing build time" and #3 "test gaps"):** the InMemory fake and the production SQL are **independent implementations**; the fast host suite validates only the fake. A regression in the `ON CONFLICT … DO UPDATE SET … + 1` upsert, the `next_eligible_at IS NULL OR <= now` eligibility filter, the terminal-status exclusion, the `toMap`-omits-columns clobber-safety, or the `int(ms) ↔ DateTime(UTC)` round-trip would **pass every default host/CI run** and only surface when someone manually runs a device proof on hardware — exactly the "green in tests, broken on device" failure mode the `sqflite_common_ffi` host-DB pattern exists to prevent. The fix is cheap (~1s host tests, no device build), so closing it *improves* build-time economics rather than worsening them.

**Explicitly NOT in scope (avoid over-engineering):** no new production behavior; no second copy of the use-case/backoff arithmetic (host-covered already); no CI-on-simulator lane for the device proofs (heavier, against "minimize build time"). Just promote the device-only **SQL** assertions to a fast host real-DB layer, matching the existing convention.

---

## 1. Phase A — Host real-DB test for `group_rejoin_state` helpers + migration 088

**File (new):** `test/core/database/helpers/group_rejoin_state_db_helpers_test.dart`
**Pattern to mirror:** any sibling, e.g. `test/core/database/helpers/group_pending_reactions_db_helpers_test.dart` (`sqflite_common_ffi` `databaseFactoryFfi`, open in-memory DB in `setUp`, run the owning migration, exercise the real helper fns). Re-uses the assertions already proven on-device in `integration_test/group_rejoin_state_db_proof_test.dart`, but host-runnable.

**Under test:** `lib/core/database/helpers/group_rejoin_state_db_helpers.dart` (`dbLoadGroupRejoinStates`, `dbRecordGroupRejoinFailure`, `dbClearGroupRejoinState`) + `lib/core/database/migrations/088_group_rejoin_state.dart` + the `int↔DateTime` round-trip in `group_repository_impl.dart:415-417,432`.

- **Red (these fail/don't exist today):**
  1. **migration creates the table** — after `runGroupRejoinStateMigration(db)`, `PRAGMA table_info(group_rejoin_state)` returns columns `group_id` (PK), `rejoin_attempt_count` (NOT NULL DEFAULT 0), `next_eligible_at` (nullable INTEGER).
  2. **first failure inserts attempt 1** — `dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: T)`; `dbLoadGroupRejoinStates(db)['g1']` → `attemptCount == 1`, `nextEligibleAt == T`.
  3. **second failure upserts via `ON CONFLICT`** — a second `dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: T2)` → `attemptCount == 2`, `nextEligibleAt == T2` (proves the `DO UPDATE SET rejoin_attempt_count + 1` path, not an INSERT-OR-IGNORE no-op).
  4. **per-group independence** — recording `g2` leaves `g1`'s count untouched.
  5. **clear deletes only the target** — `dbClearGroupRejoinState(db, 'g1')` removes `g1`, `g2` survives.
  6. **UTC ms round-trip** — drive through `GroupRepositoryImpl.recordGroupRejoinFailure(nextEligibleAt: someUtcDateTime)` then `loadGroupRejoinStates()` and assert the returned `DateTime` equals the input to the millisecond and `isUtc == true` (locks `group_repository_impl.dart:415-417/432`).
- **Green:** no production change — the implementation is correct; the test just exercises it on a real DB.
- **Gate:** new file green on host (`flutter test test/core/database/helpers/group_rejoin_state_db_helpers_test.dart`); no `@Tags`/`@TestOn` (must run in the default host suite); ~1s, no device build.

---

## 2. Phase B — Host real-DB test for the `group_messages` retry-backoff queries + migration 087

**File:** extend the existing `test/core/database/helpers/group_messages_db_helpers_test.dart` (or add `group_messages_retry_backoff_db_helpers_test.dart` if cleaner) — it currently has **zero** references to the Phase-4 columns.
**Under test:** `lib/core/database/helpers/group_messages_db_helpers.dart` (`dbLoadRetryableOutgoingGroupMessages` + the backoff setters) + `lib/core/database/migrations/087_group_message_retry_backoff_columns.dart` + the `fromMap`/`toMap` asymmetry in `lib/features/groups/domain/entities/group_message.dart`. Mirrors the on-device assertions in `integration_test/group_message_retry_backoff_db_proof_test.dart`, host-runnable.

- **Red:**
  1. **migration adds columns idempotently** — after `runGroupMessageRetryBackoffColumnsMigration(db)` (run twice to prove the `PRAGMA` column-exists guard), `group_messages` has `retry_attempt_count` (NOT NULL DEFAULT 0) + `next_eligible_at` (nullable).
  2. **eligibility filter** — seed outgoing `failed`/`pending` rows with `next_eligible_at` in the past, in the future, and NULL, plus a terminal `send_failed` row and an `is_incoming=1` row; `dbLoadRetryableOutgoingGroupMessages(db, now)` returns **only** the past/NULL non-terminal outgoing rows (locks `WHERE status IN ('failed','pending') AND is_incoming=0 AND (next_eligible_at IS NULL OR next_eligible_at <= now)`).
  3. **`recordRetryFailure` increments + schedules; terminal flip at cap** — repeated calls climb `retry_attempt_count` and set a future `next_eligible_at`; at the cap the row flips to `send_failed` and then drops out of the eligibility query.
  4. **`clearRetryBackoff` re-arms backed-off rows, leaves terminal untouched** — sets `next_eligible_at = NULL` for retryable rows; a `send_failed` row is unchanged.
  5. **`resetRetryStateForManualRetry` re-arms only terminal rows** — a `send_failed` row → `status='failed'`, `retry_attempt_count=0`, `next_eligible_at=NULL`; a plain `failed`/`pending` row is untouched.
  6. **`toMap` clobber-safety** — set backoff state on a row, then `saveMessage`/`dbInsertGroupMessage(message.toMap())` for the same id and assert `retry_attempt_count`/`next_eligible_at` are **unchanged** (proves `toMap` omits the columns — `group_message.dart` fromMap-reads but never toMap-writes them; this is the load-bearing invariant of Phase 4).
- **Green:** no production change.
- **Gate:** host-green in the default suite; no device tag; the existing `group_messages_db_helpers_test.dart` cases stay green.

---

## 3. Phase C — Add migrations 087 + 088 to the fresh-install chain test

**File:** `test/core/database/integration/full_migration_chain_test.dart` (`runFreshInstallMigrations`, ~:118-186).

- **Red:** the fresh-install path never runs `runGroupMessageRetryBackoffColumnsMigration` or `runGroupRejoinStateMigration`, so a fresh DB created by the chain test has neither the backoff columns nor `group_rejoin_state` — a schema-drift hole (the chain jumps 083→089 with no assertion for 087/088).
- **Green:** add both migration calls in version order to `runFreshInstallMigrations`, and add assertions that a fresh install ends with `group_messages.retry_attempt_count`/`next_eligible_at` present and a `group_rejoin_state` table present. (Confirm the upgrade-path gates `if (oldVersion < 87)` / `< 88` in `main.dart` already cover migrators — they do; this is the fresh-install half.)
- **Gate:** chain test green; fresh-install schema now matches `main.dart` onCreate.

---

## 4. Test & verification strategy

- All three phases are **host unit tests** using `sqflite_common_ffi` (the established 102-file pattern) — fast (~1s each), **no device/sim build**, run in the default `flutter test test/...` scope. This is the explicit "minimize build time" win: SQL regressions get caught in routine CI instead of only on a manual device proof run.
- The `integration_test/*_db_proof_test.dart` device proofs stay as the encrypted-SQLCipher truth on real hardware; this plan does not touch or duplicate them — it back-fills the missing **fast** layer beneath them.
- No production code changes; no migration; no new flag. If any Red passes unexpectedly, that itself is a finding (means coverage exists elsewhere) — re-scope.

## 5. Rollout order

1. **Phase A** (`group_rejoin_state` host helper test) — smallest, brand-new helper file, highest-value (the only surface with **zero** host references anywhere).
2. **Phase B** (`group_messages` backoff host helper test).
3. **Phase C** (fold 087 + 088 into the fresh-install chain test).

Independently landable; pure test additions; expected to be green on first run against the already-correct implementation.

## 6. Out of scope / non-blocking nits

- **Plan 06 doc-cite drift (low):** `06-…-TDD-plan.md` §1 row 6 + §7 cite the client retention drop at `drain_group_offline_inbox_use_case.dart:518-525`, but on the working tree that region is now the `GROUP_DRAIN_OFFLINE_INBOX_DECODE_SKIPPED` block; the real payload-time retention drop (`parsedTimestamp.isBefore(retentionCutoff)`) drifted to **:602-610**. Behavior unchanged; deferral still legitimate. A one-line doc fix only — no code/test action.
