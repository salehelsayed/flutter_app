Status: accepted

## Planning Progress

- 2026-06-03 22:34 CEST - Evidence Collector in progress. Files inspected since last update: source proposal, session breakdown, git status. Decision/blocker: dependency `timeout-pending-retry` is accepted and `status-timestamp-migration` remains pending; dirty worktree contains unrelated local changes including `info.plist` that must be preserved. Next action: inspect current DB version, migration style, group message schema/helpers, group message model/repository/use cases, direct tests, and gate definitions.
- 2026-06-03 22:47 CEST - Evidence Collector completed; Planner started. Files inspected since last update: `lib/main.dart`, migration files `018`, `041`, `061`, `069`, `072`, group message DB helpers/model/repository, send/retry/recover use cases, in-memory fake, direct helper/application/lifecycle tests, full migration chain, `scripts/run_test_gates.sh`, and `Test-Flight-Improv/test-gate-definitions.md`. Decision/blocker: current DB version is `72`; additive guarded migration `073` is safe to plan; no blocker. Next action: draft the narrow execution plan and regression contract.
- 2026-06-03 22:55 CEST - Planner completed; Reviewer started. Files inspected since last update: draft plan artifact, repository implementation test setup. Decision/blocker: draft includes required simulator gate and migration/version contract; reviewer found repository-level SQLite tests must be direct scope because `GroupMessage.toMap()` will include the new column. Next action: patch direct tests and reviewer findings.
- 2026-06-03 22:58 CEST - Reviewer completed; Arbiter started. Files inspected since last update: patched plan artifact. Decision/blocker: no structural blocker remains after adding repository-level fixture/test coverage; one optional `dbLoadStuckSendingGroupMessages` consistency detail remains intentionally non-blocking. Next action: classify findings and set final execution readiness if safe.
- 2026-06-03 23:00 CEST - Arbiter completed. Files inspected since last update: final plan artifact. Decision/blocker: no structural blockers remain; implementation is safe to start within the exact session scope. Next action: executor may implement only this plan and must not update the breakdown ledger or source-doc final verdict.

## Execution Progress

- 2026-06-03 22:41:21 CEST - Parent controller starting execution phase. Files inspected or touched since planning: final plan artifact and session breakdown controller progress. Decision/blocker: no blocker; plan is `Status: execution-ready` and remains doc-scoped to `status-timestamp-migration`. Next action: spawn a fresh `gpt-5.5`/`xhigh` `$implementation-execution-qa-orchestrator` child for this plan.
- 2026-06-03 22:43:03 CEST - Execution QA Orchestrator contract extracted. Files inspected or touched since last update: plan artifact, `implementation-execution-qa-orchestrator` skill, `git status --short`. Decision/blocker: no blocker; exact scope is migration `073`, `last_send_attempt_at` model/helper/repository/use-case wiring, required direct tests, `groups` gate, group simulator proof, `git diff --check`, and preservation of unrelated dirty changes. Next action: spawn fresh Executor child with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-06-03 22:43:57 CEST - Executor contract extracted. Files inspected or touched since last update: plan artifact, `flutter-sqlite-migrations-and-repositories` skill, `git status --short`. Decision/blocker: no blocker; executing only `status-timestamp-migration`, preserving unrelated dirty changes, and adding required regression tests before production edits. Next action: inspect owner files and direct test fixtures, then patch plan-scoped tests.
- 2026-06-03 22:44:49 CEST - Executor regression phase started. Files inspected or touched since last update: `lib/main.dart`, migrations `018`, `041`, `061`, `072`, group message DB helpers/model/repository/use cases, in-memory fake, and direct test search results. Decision/blocker: no blocker; current DB version is `72`, migration `073` is absent, and recovery transition currently keys off `timestamp`. Next action: add/update plan-scoped regression tests before production edits.
- 2026-06-03 22:47:34 CEST - Parent controller bounded-wait heartbeat. Files inspected or touched since last update: execution orchestrator output, plan `Execution Progress`, and plan-owner git status. Decision/blocker: no blocker yet; nested Executor child remains running, and no new migration/test files have appeared after the `22:44:49` regression-phase heartbeat. Next action: continue waiting on the execution orchestrator to apply its no-progress/fallback rules.
- 2026-06-03 22:49:39 CEST - Executor regression tests patched. Files inspected or touched since last update: new migration test, group message DB helper tests, repository test, send/retry/recover use-case tests, resume test, and full migration chain test. Decision/blocker: no blocker; tests now expect nullable `last_send_attempt_at`, UTC model mapping, fresh send/retry attempt timestamps, cutoff fallback, and fresh-install/upgrade chain coverage. Next action: run the new migration test for expected pre-implementation failure, then implement production migration/model/helper/use-case wiring.
- 2026-06-03 22:50:21 CEST - Executor red check completed. Files inspected or touched since last update: `test/core/database/migrations/073_group_message_last_send_attempt_at_test.dart`. Command/result: `flutter test --no-pub test/core/database/migrations/073_group_message_last_send_attempt_at_test.dart` failed as expected because `lib/core/database/migrations/073_group_message_last_send_attempt_at.dart` and `runGroupMessageLastSendAttemptAtMigration` do not exist yet. Decision/blocker: no blocker; expected red regression. Next action: implement production migration, main DB version wiring, model mapping, helper cutoff SQL, send attempt timestamp, and fake repository behavior.
- 2026-06-03 22:52:51 CEST - Executor production edit phase completed; direct-test phase starting. Files inspected or touched since last update: migration `073`, `lib/main.dart`, group message model, DB helpers, send use case, in-memory fake, plan-scoped direct tests, full migration chain test, and one mechanical group sync receipts schema helper. Decision/blocker: no blocker; edits are additive and formatted. Next action: run the required direct Flutter tests in the plan order.
- 2026-06-03 22:54:30 CEST - Executor child bounded wait exhausted and closed. Files inspected or touched since last update: plan `Execution Progress`, `git status --short`, `git diff --stat`, migration directory listing. Decision/blocker: nested Executor returned no final result after the permitted waits and was closed with previous status `running`; visible repo evidence includes regression and production edits, so this isolated execution-orchestrator child will perform controller-side verification recovery before QA rather than respawning the same Executor blindly. Next action: inspect scoped diffs, run the exact required direct tests/gates, record results, then spawn a separate QA Reviewer.
- 2026-06-03 22:55:07 CEST - Controller-side verification recovery started. Files inspected or touched since last update: migration `073`, `lib/main.dart`, `group_messages_db_helpers.dart`, `group_message.dart`, `send_group_message_use_case.dart`, in-memory fake, and plan-scoped direct-test diffs. Decision/blocker: no blocker found in code-shape inspection; landed changes appear coherent enough for required direct tests. Current command: starting `flutter test --no-pub test/core/database/migrations/073_group_message_last_send_attempt_at_test.dart`. Next action: run direct tests in plan order and record pass/fail evidence.
- 2026-06-03 22:56:06 CEST - Direct-test failure triaged before fix. Files inspected or touched since last update: `lib/features/groups/application/send_group_message_use_case.dart`. Command/result: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart` failed at compile load because `lastSendAttemptAt` was passed to `_resolveOutgoingMessageId`, which has no such parameter. Decision/blocker: session-owned compile-shape issue in the controller-side recovery patch; classification `pending_fix`, no gate triage needed. Next action: move the attempt timestamp to the outgoing `GroupMessage` construction and rerun the focused send use-case test.
- 2026-06-03 22:57:47 CEST - Direct tests completed. Files inspected or touched since last update: `send_group_message_use_case.dart` compile fix and plan-scoped Dart files formatted. Commands/results: `flutter test --no-pub test/core/database/migrations/073_group_message_last_send_attempt_at_test.dart` PASS; `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_sending_test.dart` PASS; `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` PASS; `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart` PASS; `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart` FAIL once with the triaged compile-shape issue then PASS after focused fix; `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart` PASS; `flutter test --no-pub test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart` PASS; `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart` PASS; `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart` PASS; `dart format <plan-scoped Dart files>` reported 0 changed. Decision/blocker: no direct-test blocker remains. Current command: starting `./scripts/run_test_gates.sh groups`. Next action: run required groups gate, triage only if failure differs from the known allowed `GCA-004` residual.
- 2026-06-03 22:59:26 CEST - Required groups gate failed; triage artifact recorded before rerun. Files inspected or touched since last update: streamed `./scripts/run_test_gates.sh groups` output. Failing gate command: `./scripts/run_test_gates.sh groups` exited `1`. Failing file/test name: not yet known from retained output; stream ended with `Some tests failed` and `+317 -1`. Log path: none, command was not redirected. Exact focused triage command about to run: `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'GCA-004 bridgeError recovery drains inbox after settled materialized invite'`. Classification state: `pending_triage`. Next action: compare focused rerun failure signature to the plan-allowed known `GCA-004` residual.
- 2026-06-03 22:59:56 CEST - Groups gate triage completed. Files inspected or touched since last update: focused `invite_round_trip_test.dart` rerun output. Commands/results: `./scripts/run_test_gates.sh groups` FAILED with one retained failure; focused `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'GCA-004 bridgeError recovery drains inbox after settled materialized invite'` FAILED at `test/features/groups/integration/invite_round_trip_test.dart:2930` with `Expected: not null`, `Actual: <null>`. Decision/blocker: no session-owned gate blocker; failure matches the plan's exact known allowed `GCA-004` residual. Current command: starting required simulator proof `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --only integration_test/group_recovery_e2e_test.dart`. Next action: run simulator proof and triage any failure as blocking unless environment-related evidence proves otherwise.
- 2026-06-03 23:02:51 CEST - Required simulator proof completed. Files inspected or touched since last update: simulator runner output. Command/result: `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --only integration_test/group_recovery_e2e_test.dart` PASS; resolved one-device simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`; runner command `#8` passed and reliability simulations completed for scope `group`. Decision/blocker: no simulator blocker. Current command: starting `git diff --check`. Next action: run diff cleanliness check, inspect final scoped diff, then spawn separate QA Reviewer.
- 2026-06-03 23:03:42 CEST - Verification handoff to QA. Files inspected or touched since last update: final `git status --short`, plan-scoped `git diff --stat`, and plan execution progress. Commands/results: `git diff --check` PASS; extra touched-file validation `flutter test --no-pub test/core/database/helpers/group_sync_receipts_db_helpers_test.dart` PASS. Decision/blocker: no executor-side blocker remains; unrelated dirty worktree changes are still present and preserved. Next action: spawn separate QA Reviewer child with `model: gpt-5.5` and `reasoning_effort: xhigh` for strict execution sufficiency review.
- 2026-06-03 23:07:41 CEST - Final execution verdict written. Files inspected or touched since last update: QA Reviewer result, final `git status --short`, and this plan file. Command/result: spawned QA Reviewer child returned `no_blocking_issues`, with no non-blocking follow-ups required. Decision/blocker: final execution verdict `accepted`; no blocking issues remain; required direct tests, allowed-residual groups gate triage, required simulator proof, and `git diff --check` evidence are recorded above. Next action: parent controller may perform session/breakdown closure separately.

## real scope

Implement exactly the `status-timestamp-migration` session:

- Add one nullable `TEXT` column named `last_send_attempt_at` to `group_messages` in migration `073_group_message_last_send_attempt_at.dart`.
- Bump the app database version from `72` to `73` in `lib/main.dart`; import, run on fresh create, and run on upgrade when `oldVersion < 73`.
- Extend `GroupMessage` with nullable `DateTime? lastSendAttemptAt`, mapped to/from `last_send_attempt_at`.
- Write a fresh UTC attempt timestamp whenever an outgoing group row enters `status: 'sending'`.
- Keep the logical message `timestamp` unchanged. Retries must continue to reuse the original message id and original message timestamp.
- Change `dbTransitionGroupSendingToFailed` to compare `COALESCE(last_send_attempt_at, timestamp)` against the cutoff when `olderThan` is provided, and keep legacy rows with `NULL last_send_attempt_at` falling back to `timestamp`.

Do not change UI retry affordances, local-status broadcast behavior, bridge timeout, pending retry payloads, live/replay dedup, notification behavior, source docs, breakdown ledger status, or final whole-doc verdict.

## closure bar

The session is closed only when:

- Migration `073` adds `group_messages.last_send_attempt_at` idempotently and preserves existing rows with `NULL` in the new column.
- Fresh installs and upgrades both include the new column.
- A new or retried outgoing group send persists `status: 'sending'` with `last_send_attempt_at` near the actual send attempt time, not the original logical message timestamp.
- A retried row with an old `timestamp` but fresh `last_send_attempt_at` is not flipped to `failed` by `dbTransitionGroupSendingToFailed(... olderThan: ...)`.
- A legacy row with `NULL last_send_attempt_at` still uses `timestamp` and preserves the old stuck-sending behavior.
- Existing status transitions to `sent`, `pending`, or `failed` keep the attempt timestamp available but do not use it for timeline ordering or duplicate identity.
- Direct tests, the group named gate, and the required group simulator proof below are run, with only the known `GCA-004` gate residual allowed.

Checklist coverage:

| Required item | Planned proof |
|---|---|
| Nullable group-message status-change or send-attempt timestamp column | New `073` migration test plus full migration chain column assertion. |
| Next DB version after current version `72` | `lib/main.dart` version/import/onCreate/onUpgrade diff plus migration test naming. |
| Write it when rows enter `sending` | `send_group_message_use_case_test.dart` and retry-focused test proving fresh `lastSendAttemptAt` on pre-persisted sending row. |
| `dbTransitionGroupSendingToFailed` compares against it | DB helper tests where old logical timestamp plus fresh attempt timestamp stays `sending`, stale attempt timestamp flips `failed`. |
| Legacy fallback to `timestamp` | DB helper and migration tests with `NULL last_send_attempt_at`. |
| Dependency `timeout-pending-retry` accepted | Breakdown ledger evidence at 2026-06-03 records `timeout-pending-retry` as `accepted_with_explicit_follow_up`. |

## source of truth

- Active product/session contract: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`.
- Active decomposition contract: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-breakdown.md`, session `status-timestamp-migration`.
- Gate source of truth: `scripts/run_test_gates.sh` wins over `Test-Flight-Improv/test-gate-definitions.md` if they disagree.
- Current code and tests win over stale prose.
- Current dirty worktree must be preserved. Pre-existing changes include `info.plist`, prior group retry/timeout/local-status work, and untracked sibling session plans/breakdown artifacts.

## session classification

`implementation-ready`

Evidence supports a narrow additive schema and helper/model/use-case change. No prerequisite blocker is present because the required `timeout-pending-retry` dependency is accepted in the breakdown ledger.

## exact problem statement

A retry pre-persists an outgoing group message as `sending` while intentionally reusing the original message id and original message `timestamp`. The stuck-sending sweep currently uses `group_messages.timestamp < cutoff`, so a fresh retry of an old failed row can be marked `failed` immediately or during the same resume/retry window even though the bridge send is still in flight. That can trigger another retry cycle and contribute to duplicate delivery.

The user-visible behavior to improve is that a fresh retry attempt must get the full stuck-sending threshold before recovery flips it to `failed`. Existing id-stable retry identity, timeline ordering, pending in-doubt handling, and local status broadcasts must stay unchanged.

## files and repos to inspect next

Production owner files:

- `lib/core/database/migrations/073_group_message_last_send_attempt_at.dart` (new)
- `lib/main.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`

Direct test owner files:

- `test/core/database/migrations/073_group_message_last_send_attempt_at_test.dart` (new)
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_sending_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`

## existing tests covering this area

- `test/core/database/helpers/group_messages_db_helpers_sending_test.dart` currently proves bulk `sending -> failed` transitions affect outgoing rows only.
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` currently proves stuck-sending load/transition behavior, ordering by `timestamp`, legacy reliability columns, and model mapping for group message rows.
- `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart` currently proves the use case returns the repository count and respects the threshold through the in-memory fake, but it keys off `timestamp` today.
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart` currently proves resume ordering calls group recovery before retry.
- `test/features/groups/application/send_group_message_use_case_test.dart` already has pre-persist tests proving a `sending` row exists before bridge calls, and retry/timeout tests from prior sessions.
- `test/core/database/integration/full_migration_chain_test.dart` currently verifies fresh-install and upgrade-chain schema but does not yet know migration `073`.

Missing coverage before implementation:

- No test proves a fresh retry attempt is protected from stale logical message timestamps.
- No migration test proves a nullable group-message send-attempt column.
- No model/repository test proves `last_send_attempt_at` round-trips through SQLite-backed repository saves and loads.

## regression/tests to add first

Add failing tests before production edits:

1. `test/core/database/migrations/073_group_message_last_send_attempt_at_test.dart`
   - Prove `runGroupMessageLastSendAttemptAtMigration` adds nullable `last_send_attempt_at` to `group_messages`.
   - Prove an existing row survives with `last_send_attempt_at IS NULL`.
   - Prove the migration is idempotent.

2. `test/core/database/helpers/group_messages_db_helpers_sending_test.dart`
   - Insert an outgoing `sending` row with old `timestamp` and fresh `last_send_attempt_at`; assert `dbTransitionGroupSendingToFailed(... olderThan: cutoff)` affects `0` rows.
   - Insert an outgoing `sending` row with recent `timestamp` and stale `last_send_attempt_at`; assert it transitions to `failed`.
   - Insert a legacy outgoing `sending` row with `NULL last_send_attempt_at` and old `timestamp`; assert fallback still transitions it.

3. `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
   - Extend helper setup to run migration `073`.
   - Add `GroupMessage.fromMap`/`toMap` round-trip assertions for `lastSendAttemptAt`.
   - Preserve ordering tests by `timestamp`, not `last_send_attempt_at`.

4. `test/features/groups/application/send_group_message_use_case_test.dart`
   - Add a pre-persist test where caller supplies an old `timestamp` and the first saved `sending` row has `lastSendAttemptAt` bounded between test start/end, while `message.timestamp` remains the supplied old value.

5. `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
   - Run migration `073` in setup and prove `saveMessage`/`getMessage` round-trips `lastSendAttemptAt`.
   - Keep the prior local outgoing status event tests green; the new column must not change event emission semantics.

6. `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
   - Add a retry proof where a failed row with an old original `timestamp` is retried under the same id/timestamp and the saved `sending` row has a fresh `lastSendAttemptAt`.

7. `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`
   - Update the in-memory fake-backed behavior to use `lastSendAttemptAt ?? timestamp`, proving old message timestamp plus fresh attempt timestamp stays `sending`.

8. `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
   - Keep resume order proof and add, only if the existing harness allows without broad rewrites, a narrow assertion that recover-before-retry does not immediately fail a freshly retried old row.

## step-by-step implementation plan

1. Add migration `073_group_message_last_send_attempt_at.dart` following the guarded `PRAGMA table_info(group_messages)` pattern from migrations `041` and `061`. Emit start/already-done/success/error flow events using the existing migration style.
2. Wire migration `073` into `lib/main.dart`: import, `version: 73`, run after `runGroupPendingMembershipMessagesMigration(db)` in `onCreate`, and add `if (oldVersion < 73) await runGroupMessageLastSendAttemptAtMigration(db);` in `onUpgrade`.
3. Extend `GroupMessage` with `DateTime? lastSendAttemptAt`, `fromMap`, `toMap`, and `copyWith`, using UTC ISO-8601 strings and nullable legacy handling.
4. In `sendGroupMessage`, capture `final sendAttemptAt = DateTime.now().toUtc();` separately from the logical `now = timestamp ?? DateTime.now().toUtc();`. Set `lastSendAttemptAt: sendAttemptAt` on the pre-persist `status: 'sending'` row. Do not change outgoing `messageId`, `timestamp`, `createdAt`, retry payload timestamps, or timeline ordering.
5. Let subsequent `copyWith(status: 'sent'/'pending'/'failed')` paths preserve `lastSendAttemptAt`. Do not clear it on success or failure.
6. Keep `retry_failed_group_messages_use_case.dart` passing `timestamp: msg.timestamp`; the fresh attempt time belongs in `sendGroupMessage`, not in the retry caller.
7. Update `dbTransitionGroupSendingToFailed` to compare `COALESCE(last_send_attempt_at, timestamp) < ?` when `olderThan` is provided. Keep the no-cutoff bulk transition unchanged except for preserving the new column.
8. Update `dbLoadStuckSendingGroupMessages` only if executor evidence shows a caller relies on its selection for this same recovery path. If changed, use the same `COALESCE(last_send_attempt_at, timestamp)` predicate and keep ordering by `timestamp ASC, id ASC`.
9. Update `InMemoryGroupMessageRepository.recoverStuckSendingMessages` to use `msg.lastSendAttemptAt ?? msg.timestamp` so app/use-case tests match production semantics.
10. Update direct test setup helpers to run migration `073` and include `last_send_attempt_at` only where necessary. Keep legacy-row tests intentionally omitting it.
11. Update `full_migration_chain_test.dart` imports, fresh install chain, upgrade chain, and group message column assertion for `last_send_attempt_at`.
12. Stop if evidence shows the column already exists in current code, or if current DB version is no longer `72`; refresh this plan before implementing in that case.

## risks and edge cases

- Migration/version risk: `lib/main.dart` has a manual import/onCreate/onUpgrade chain. Missing any one of those makes fresh install or upgrade diverge.
- Column naming risk: use exactly `last_send_attempt_at`; do not add both `status_updated_at` and `last_send_attempt_at`.
- Time semantics risk: `message.timestamp` is a logical identity/order timestamp; `lastSendAttemptAt` is an operational retry timestamp. Mixing them reopens duplicate-id or timeline bugs.
- Legacy risk: old rows and test fixtures will have `NULL last_send_attempt_at`; all mapping and SQL must tolerate null.
- Test-fixture risk: any SQLite-backed test repository that calls `GroupMessage.toMap()` must run migration `073` before saving rows, or it will try to insert a column that does not exist.
- Dirty worktree risk: `GroupMessageRepositoryImpl`, `GroupMessageRepository`, and `InMemoryGroupMessageRepository` already contain prior local-status-broadcast changes. Implement on top of them; do not revert or simplify those changes.
- Resume/retry race: recover and retry order must remain the same; only the cutoff predicate changes.
- Background/local broadcast: count-only row change events from prior session should still emit after recover transitions; this session must not alter their contract.

## exact tests and gates to run

Focused direct tests:

```bash
flutter test --no-pub test/core/database/migrations/073_group_message_last_send_attempt_at_test.dart
flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_sending_test.dart
flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_reliability_test.dart
flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart
flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart
flutter test --no-pub test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart
flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart
```

Required named and simulator gates:

```bash
./scripts/run_test_gates.sh groups
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart
```

Conditional gate:

```bash
./scripts/run_test_gates.sh completeness-check
```

Run `completeness-check` only if implementation adds a test outside the existing implicit `test/core/database/*.dart` direct-suite bucket or edits any gate/classification docs. A new file under `test/core/database/migrations/` should already be covered by the documented direct database bucket, but the executor should verify this if the completeness script flags it.

## known-failure interpretation

`./scripts/run_test_gates.sh groups` may fail only with the known carried residual:

- Test: `GCA-004 bridgeError recovery drains inbox after settled materialized invite`
- File: `test/features/groups/integration/invite_round_trip_test.dart:2930`
- Assertion: `Expected: not null`, `Actual: <null>`

Any other failure, any changed line number/assertion in the same test, any simulator failure, or any direct-test failure is session-owned until triaged with focused reruns and evidence.

## done criteria

- Plan-scoped code compiles and formats.
- Migration `073` exists, is idempotent, and is wired into `lib/main.dart` for both fresh install and upgrade from version `72`.
- `GroupMessage` round-trips `lastSendAttemptAt` while legacy rows remain valid.
- `sendGroupMessage` writes a fresh `lastSendAttemptAt` whenever it saves `status: 'sending'`.
- Retry preserves original `messageId` and logical `timestamp` but receives a fresh attempt timestamp.
- `dbTransitionGroupSendingToFailed` uses `COALESCE(last_send_attempt_at, timestamp)` for cutoff comparison.
- Direct tests, `groups`, and the group simulator proof run with only the known `GCA-004` allowance.
- No production/test files outside direct owner scope are changed, except mechanical migration-chain/test helper updates required by this scope.
- `info.plist` and unrelated dirty worktree changes are preserved.

## scope guard

Non-goals:

- Do not alter bridge timeout budgets, native transport, relay retry payload construction, or `timeout-pending-retry` behavior.
- Do not change text retry UI, voice retry/upload recovery, restored composer continuation, or local status broadcast UX.
- Do not alter message id generation, duplicate-detection predicates, message ordering, notification routing, receive-side live/replay serialization, or media upload status semantics.
- Do not backfill old rows; `NULL` plus fallback is the compatibility contract.
- Do not add indexes unless a measured query-plan problem appears in this session. The transition query remains a bounded status/is_incoming update and no performance problem is currently proven.
- Do not update the breakdown ledger, source proposal final verdict, notification matrix, or gate docs unless a new test classification is actually required.

Overengineering markers:

- Adding both `status_updated_at` and `last_send_attempt_at`.
- Updating the attempt timestamp on every status change rather than only when a row enters `sending`.
- Rewriting repository interfaces broadly when `saveMessage`/model mapping can carry the value.
- Changing retry callers to mint new logical timestamps.

## accepted differences / intentionally out of scope

- The column is named `last_send_attempt_at` rather than `status_updated_at` because the session only needs the time a row enters `sending`; this avoids implying every status transition must update the field.
- Legacy rows are not backfilled. `NULL` fallback to `timestamp` intentionally preserves old behavior for pre-migration stuck rows.
- No final source-doc or notification-matrix closure is performed here; `acceptance-doc-closure` owns that.
- No simulator scenario is created unless `integration_test/group_recovery_e2e_test.dart` lacks a narrow proof after implementation. If it lacks one, the executor should extend that existing group recovery scenario rather than create a new broad harness.

## dependency impact

- This session depends on `timeout-pending-retry` because retries and in-doubt states must already preserve same-id send semantics and pending retry payloads.
- `live-replay-dedup` can proceed after this session; it should not assume stuck-sending recovery still keys only off logical message `timestamp`.
- `acceptance-doc-closure` must collect this session's migration/direct/gate evidence before recording the final duplicate-delivery cascade verdict.

## reviewer pass

Reviewer verdict: sufficient with adjustments, now patched.

Findings checked:

- Missing direct coverage: repository-level SQLite tests were missing even though `GroupMessage.toMap()` will add `last_send_attempt_at`; patched by adding `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`.
- Migration-chain risk: covered by new migration test, `lib/main.dart` version wiring, and `full_migration_chain_test.dart`.
- Simulator closure: included because this is group messaging and resume/retry recovery behavior.
- Stale assumptions: current repo evidence shows DB version `72`, no existing `last_send_attempt_at`, and dirty worktree changes in prior sessions that must be preserved.
- Scope creep: plan does not reopen UI retry, timeout, local broadcast, live/replay dedup, notification, source-doc verdict, or gate-doc work.
- Overengineering: plan chooses one column and rejects indexes/backfills/broad repository rewrites.

## arbiter decision

Arbiter verdict: execution-ready.

Structural blockers:

- None.

Incremental details intentionally deferred:

- `dbLoadStuckSendingGroupMessages` is currently test-only in repo evidence. Updating it to use `COALESCE(last_send_attempt_at, timestamp)` is allowed only if executor evidence shows it is part of the same recovery seam; otherwise keeping it unchanged is acceptable because the session contract specifically owns `dbTransitionGroupSendingToFailed`.
- A new narrow assertion in `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart` is useful if the existing harness can express it without broad rewrites; direct DB/use-case tests are the required proof if that lifecycle harness becomes awkward.

Accepted differences intentionally left unchanged:

- Use `last_send_attempt_at`, not `status_updated_at`, because this session only needs the timestamp for entering `sending`.
- Do not backfill old rows; `NULL` plus fallback to `timestamp` is the compatibility contract.
- Do not update source proposal, breakdown ledger, notification matrix, or final verdict in this session.

Final verdict:

- Safe to implement now as `implementation-ready`.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`
- `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/main.dart`
- `lib/core/database/migrations/018_group_messages_tables.dart`
- `lib/core/database/migrations/041_group_message_reliability_columns.dart`
- `lib/core/database/migrations/061_group_message_transport_peer_id.dart`
- `lib/core/database/migrations/069_group_message_local_deletions.dart`
- `lib/core/database/migrations/072_group_pending_membership_messages.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/core/database/migrations/061_group_message_transport_peer_id_test.dart`
- `test/core/database/migrations/072_group_pending_membership_messages_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_sending_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`

Why the plan is safe to implement now:

- It is additive and nullable, has a clear legacy fallback, and keeps logical message identity/timeline timestamps unchanged.
- It isolates the only schema-bearing slice into version `73`, with direct migration, full-chain, helper, repository, use-case, lifecycle, group gate, and simulator proof.
- It explicitly preserves unrelated dirty worktree changes, including `info.plist`, and forbids source-doc/breakdown final verdict updates.
