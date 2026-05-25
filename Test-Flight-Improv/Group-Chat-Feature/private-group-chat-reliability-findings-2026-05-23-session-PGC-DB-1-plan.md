# Session PGC-DB-1 Plan: Message Repository And DB Helper Data-Integrity Hardening

Status: execution-ready

## Planning Progress

- 2026-05-23 23:19:31 CEST - Arbiter completed. Files inspected since last update: plan artifact self-review. Decision/blocker: no structural blockers remain; incremental details are documented and accepted differences are explicit. Next action: plan is execution-ready for `PGC-004`, `PGC-005`, and `PGC-006` only.
- 2026-05-23 23:19:06 CEST - Reviewer completed; Arbiter started. Files inspected since last update: plan artifact self-review. Decision/blocker: reviewer found no structural blocker after adding PGC-006 migrated-test setup detail, unique-conflict-only handling, and one missing outgoing preservation selector. Next action: arbiter classification and final reusable status.
- 2026-05-23 23:18:30 CEST - Planner completed; Reviewer started. Files inspected since last update: plan artifact self-review. Decision/blocker: draft has mandatory sections and exact gates; reviewer is checking sufficiency around PGC-006 test setup and outgoing transition protection. Next action: patch any structural gaps once, then classify findings.
- 2026-05-23 23:14:17 CEST - Planner started. Files inspected since last update: none. Decision/blocker: draft will stay inside rows `PGC-004`, `PGC-005`, and `PGC-006`; no product/test code edits during planning. Next action: write mandatory plan sections, exact tests/gates, and stop/scope guard.
- 2026-05-23 23:14:02 CEST - Evidence Collector completed. Files inspected since last update: `Test-Flight-Improv/test-gates-reference.md`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, `lib/main.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_sync_receipts_db_helpers.dart`, `lib/features/groups/domain/models/group_message.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `test/core/database/helpers/group_messages_db_helpers_test.dart`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`, `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/core/database/integration/full_migration_chain_test.dart`. Decision/blocker: current code confirms all three target rows remain meaningful; no blocker. Next action: draft the narrow execution plan with regression-first tests and scope guard.

## Execution Progress

- 2026-05-23 23:44:56 CEST - Final verdict written. Files inspected since last update: scoped `git status`, QA result, and this plan. Command currently running: none. Decision/blocker: verdict is `accepted_with_explicit_follow_up`; no blocking issues remain for `PGC-DB-1`. Follow-up is limited to the unrelated dirty-tree `./scripts/run_test_gates.sh groups` failures already recorded in this section and `/tmp/pgc_db1_groups_gate.log`. Next action: stop this one-session execution without running unrelated sessions or closure docs.
- 2026-05-23 23:43:21 CEST - QA Reviewer completed. Files inspected since last update: `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`, `test/core/database/helpers/group_messages_db_helpers_test.dart`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`, this plan, `/tmp/pgc-db-1-executor-result.txt`, and `/tmp/pgc_db1_groups_gate.log`. Commands run: `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_test.dart test/core/database/helpers/group_messages_db_helpers_reliability_test.dart test/features/groups/domain/repositories/group_message_repository_impl_test.dart`; `git diff --check -- <scoped files and plan>`; read-only `git diff`, `rg`, `sed`, `nl`, and `git status` inspections. Decision/blocker: no blocking findings; implementation satisfies `PGC-004`, `PGC-005`, and `PGC-006` in the scoped DB/repository surface, and scope stayed limited to the two production files, three focused test files, and plan notes. Non-blocking finding: the red `./scripts/run_test_gates.sh groups` log remains accepted as unrelated because the exact failures are already recorded, the scoped owner suites pass, no PGC-DB-1 error markers appear in the log, and the failing integration tests use in-memory group-message repositories rather than the changed DB helper. Next action: accept this session with explicit follow-up for the unrelated dirty-tree group gate failures outside `PGC-DB-1`.
- 2026-05-23 23:40:18 CEST - QA Reviewer spawn started. Files inspected since last update: Executor result file, current execution progress, and orchestrator workflow. Command currently running: `codex -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -a never exec -C /Users/I560101/Project-Sat/mknoon-2/flutter_app`. Decision/blocker: Executor handed off with scoped edits and a red `groups` gate classified as unrelated; separate QA Reviewer will now verify implementation sufficiency, scope adherence, and gate classification for `PGC-DB-1` only. Next action: wait for QA result and only spawn a fix pass if QA reports blocking issues.
- 2026-05-23 23:39:03 CEST - Executor completed and handed off for QA. Files inspected/touched since last update: scoped status/diff only; no additional code edits. Command currently running: none. Decision/blocker: touched files remain limited to the allowed two production files, three test files, and this progress section. Conditional migration/full-chain/completeness gates were not run because this session did not edit migrations, DB version/schema, gate definitions, or classification docs, and the user excluded closure docs. Next action: separate QA Reviewer should review the implementation and evidence.
- 2026-05-23 23:38:40 CEST - Executor hygiene completed. Files inspected/touched since last update: formatted `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`, `test/core/database/helpers/group_messages_db_helpers_test.dart`, and `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`. Command currently running: none. Decision/blocker: `dart format ...` completed with `Formatted 5 files (0 changed) in 0.03 seconds`; `git diff --check` passed with no output. Next action: record final Executor handoff.
- 2026-05-23 23:37:55 CEST - Executor required named gate completed red. Files inspected/touched since last update: inspected `/tmp/pgc_db1_groups_gate.log`; no file edits. Command currently running: none. Decision/blocker: `./scripts/run_test_gates.sh groups` was run, then rerun with output captured at `/tmp/pgc_db1_groups_gate.log`; rerun failed with 14 failures. Classification: unrelated-but-required in the dirty tree, not PGC-DB-1-caused, because all five focused selectors, all preservation selectors, and all three direct owner suites passed, and the gate log contains no `dbRunGroupInboxPageTransactionFn`, `StateError`, `GROUP_DRAIN_OFFLINE_INBOX_ERROR`, `GROUP_MESSAGES_DB_LOAD_ONE_ERROR`, or `GROUP_MESSAGES_DB_INSERT_ERROR` markers. Exact failures: `BB-007 accepted pending invite joins with exact full config and replays accepted epoch`; `IJ005 multi-use direct credential replay is duplicate-safe`; `BB-012 restart recovery drains replay before ack and stays live`; `NW-004 reconnect recovery stays live after ack across multiple groups`; `IR-018 restart recovery keeps recovering state until replay drains and live stays active`; `PL-004 quote ids survive live replay and re-add visibility boundaries`; `DE-004 live plus inbox replay duplicate keeps one row and commits replay evidence`; `IR-003 timestamp replay boundary drains same-ms fake-network messages once`; `ST-004 clock skew fake-network replay keeps relay boundary exact`; `GE-017 seeded random membership operations preserve invariants`; `GE-019 seeded random key rotations preserve access windows`; `GE-020 long soak private group with churn preserves convergence`; `GM-029 config version monotonicity converges across A/B/C shuffled delivery`; `GM-028 empty PeerId add event does not persist or block valid delivery`. Next action: run final format and diff hygiene.
- 2026-05-23 23:34:15 CEST - Executor direct owner suites completed. Files inspected/touched since last update: touched `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` to run migration `061` in the existing UP-008 fresh file DB setup, then formatted that test file. Command currently running: none. Decision/blocker: `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_test.dart` passed; first `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` failed with a session-caused setup omission, then passed after adding migration `061`; `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart` passed. Next action: run required named gate `./scripts/run_test_gates.sh groups`.
- 2026-05-23 23:33:39 CEST - Executor owner suite triage started. Files inspected/touched since last update: no additional edits yet. Command currently running: none. Decision/blocker: `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_test.dart` passed; `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` failed in existing `UP-008 pending outbound retry row survives database restart and stays eligible` because the session added `transport_peer_id` to the shared `makeRow` helper while that test's fresh file DB setup did not run migration `061`. Classification: caused by this session's test setup change, not a product failure. Next action: add migration `061` to that fresh DB setup and rerun the reliability owner suite.
- 2026-05-23 23:33:12 CEST - Executor preservation selectors completed. Files inspected/touched since last update: no additional file edits. Command currently running: none. Decision/blocker: all required preservation selectors passed after implementation: handle-incoming self echo; group-listener NW-008, DE-005, and GP-025/LP013; send pre-persist, IR-007 publish-success/inbox-failure, IR-007 publish-failure/inbox-failure, GO-002, publish-fail/inbox-OK; and retry failed inbox stores same-id selector. Note: pre-implementation preservation selectors were not run before code edits; the five new focused RED selectors were run before implementation as required by the user request. Next action: run direct owner suites.
- 2026-05-23 23:31:54 CEST - Executor focused post-implementation selectors completed. Files inspected/touched since last update: no additional file edits. Command currently running: none. Decision/blocker: all five focused selectors now pass: PGC-004 missing transaction helper, PGC-005 DB helper rethrow, PGC-005 repository propagation, PGC-006 duplicate incoming preservation, and PGC-006 outgoing transition preservation. Next action: run preservation selectors and triage any failure before widening to owner suites.
- 2026-05-23 23:30:57 CEST - Executor implementation completed. Files inspected/touched since last update: touched `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, and formatted all five touched Dart files. Command currently running: none. Decision/blocker: `runInboxPageTransaction` now throws before `apply` when the durable transaction helper is absent; `dbLoadGroupMessage` emits a DB load-one error and rethrows; `dbInsertGroupMessage` now inserts first and on same-id uniqueness conflict applies direction-aware duplicate handling without `ConflictAlgorithm.replace`. Next action: rerun the five focused selectors post-implementation.
- 2026-05-23 23:28:42 CEST - Executor RED selectors completed. Files inspected/touched since last update: no additional file edits; inspected current code behavior in `group_message_repository_impl.dart` and `group_messages_db_helpers.dart` while interpreting selector results. Command currently running: none. Decision/blocker: `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name "PGC-004 runInboxPageTransaction without helper fails before applying page writes"` failed as expected because missing helper invoked `apply`; `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_test.dart --plain-name "PGC-005 dbLoadGroupMessage rethrows database errors"` failed as expected because DB error returned `null`; `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name "PGC-005 getMessage propagates db load errors"` passed before implementation because the repository already directly awaits injected load failures; `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_reliability_test.dart --plain-name "PGC-006 duplicate incoming save preserves operational fields"` failed as expected because `ConflictAlgorithm.replace` clobbered the row; `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_reliability_test.dart --plain-name "PGC-006 outgoing duplicate save preserves intentional state transitions"` passed before implementation because replace already applies outgoing final rows. Next action: implement only the PGC-004 fail-fast, PGC-005 rethrow, and PGC-006 direction-aware insert/update behavior.
- 2026-05-23 23:27:50 CEST - Executor RED tests added. Files inspected/touched since last update: touched `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`, `test/core/database/helpers/group_messages_db_helpers_test.dart`, and `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`. Command currently running: none. Decision/blocker: added exactly the five requested focused selectors; reliability test setup now runs migration `061` so `transport_peer_id` is available for PGC-006 assertions. Next action: run the five focused selectors before implementation and record RED/unexpected-pass evidence.
- 2026-05-23 23:24:43 CEST - Executor started locally for session `PGC-DB-1`. Files inspected since last update: this plan, `git status --short`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`, `test/core/database/helpers/group_messages_db_helpers_test.dart`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`, group message migrations `018`, `026`, `041`, and `061`, and `lib/features/groups/domain/models/group_message.dart`. Command currently running: none. Decision/blocker: dirty worktree contains many unrelated group/bridge/docs changes; expected production/test files are not already modified in status, so Executor edits will stay scoped to the two production files, three test files, and this progress section. Next action: add the five requested RED regression selectors before implementation.
- 2026-05-23 23:21:26 CEST - Contract extraction started. Files inspected since last update: `implementation-execution-qa-orchestrator/SKILL.md`, this plan, `Test-Flight-Improv/test-gates-reference.md`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, `git status --short`. Command currently running: none. Decision/blocker: execution will stay limited to session `PGC-DB-1` / rows `PGC-004`, `PGC-005`, `PGC-006`; dirty worktree has unrelated changes that must not be reverted. Next action: extract exact scope, tests, gates, done criteria, and spawn the Executor.
- 2026-05-23 23:21:26 CEST - Contract extracted. Files inspected since last update: this plan and gate references. Command currently running: none. Decision/blocker: required scope is two production files, focused DB/repository tests named by the plan, preservation selectors, owner suites, `./scripts/run_test_gates.sh groups`, `dart format`, and `git diff --check`; conditional migration/completeness gates are not required unless migrations/schema/gate docs are touched. Next action: spawn isolated Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-23 23:22:26 CEST - Executor spawn requested/running. Files inspected since last update: no additional files. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" -s danger-full-access -a never -C /Users/I560101/Project-Sat/mknoon-2/flutter_app`. Decision/blocker: spawned Executor will own regression-first implementation and required test/gate execution within the user-limited write scope; closure matrix/breakdown docs are intentionally excluded by the user request. Next action: wait for Executor result and inspect landed evidence before QA.
- 2026-05-23 23:23:04 CEST - Executor spawn command corrected. Files inspected since last update: no additional files. Command currently running: none. Decision/blocker: first spawn command exited before agent materialization because `-a never` was placed after `codex exec`; no child work or partial edits occurred. Next action: retry spawn with approval flag passed to the top-level `codex` command.

## Real Scope

Session `PGC-DB-1` owns only rows `PGC-004`, `PGC-005`, and `PGC-006` from `private-group-chat-reliability-findings-2026-05-23-matrix.md`.

Implementation scope:

- Make `GroupMessageRepositoryImpl.runInboxPageTransaction` fail fast when `dbRunGroupInboxPageTransactionFn` is absent so replay cannot silently skip cursor, receipt, or read-marker persistence.
- Make `dbLoadGroupMessage` return `null` only for a successful empty query and rethrow real database/query errors.
- Replace destructive `ConflictAlgorithm.replace` in `dbInsertGroupMessage` with a scoped insert/update path that preserves operational state on duplicate incoming saves while still allowing intentional outgoing state transitions.
- Add focused tests before implementation and update only the source matrix rows and session ledger after implementation evidence exists.

Out of scope:

- No changes to Go, relay, bridge protocol, migrations, DB version, media attachment schema, group listener architecture, send UX, retry UX, or notification behavior.
- No work on rows `PGC-001`, `PGC-002`, `PGC-007` through `PGC-018`.
- No cleanup of unrelated dirty-worktree changes.

## Closure Bar

The session is good enough when:

- A missing inbox page transaction helper throws before `apply` runs and before any cursor/receipt/read side effects can be silently dropped.
- `dbLoadGroupMessage` propagates database failures to callers while the existing "no row" path still returns `null`.
- Duplicate incoming saves cannot clear or regress existing `read_at`, verified `transport_peer_id`, `quoted_message_id`, outgoing retry/custody columns, or future unknown columns by delete/reinsert.
- Outgoing saves still intentionally transition the same row through `sending` to `sent`, `pending`, or `failed`, including `wire_envelope`, `inbox_stored`, and `inbox_retry_payload` changes used by send and inbox retry flows.
- Focused RED regressions fail before implementation where current behavior is wrong, pass after implementation, preservation selectors for self-echo, duplicate incoming, and retry transitions still pass, and the required named gate contract is satisfied or any pre-existing unrelated red gate is recorded exactly.

## Source Of Truth

Authoritative docs:

- Source matrix: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`
- Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`
- Gate reference: `Test-Flight-Improv/test-gates-reference.md`
- Gate definitions: `Test-Flight-Improv/test-gate-definitions.md`
- Gate implementation: `scripts/run_test_gates.sh`

Conflict rules:

- Current code and tests beat stale prose.
- `scripts/run_test_gates.sh` wins if it disagrees with gate prose.
- This plan wins for session scope unless direct repo evidence proves a row is already covered or unsafe.
- Rows outside `PGC-004`, `PGC-005`, and `PGC-006` are not reopened by this session.

## Session Classification

`implementation-ready`

## Exact Problem Statement

`PGC-004`: `GroupMessageRepositoryImpl.runInboxPageTransaction` currently falls back to `await apply(this)` when no transaction helper is injected. That fallback can save messages but silently skips cursor, receipt, and read-marker persistence. A replay page can therefore be processed without durable replay progress, which risks replay loops or missing receipt/read state.

`PGC-005`: `dbLoadGroupMessage` catches every exception and returns `null`. Callers use `null` as "message not found", so a SQLite/query failure can be misclassified as a dedupe miss or missing row instead of stopping the unsafe path.

`PGC-006`: `dbInsertGroupMessage` currently uses `ConflictAlgorithm.replace`. On SQLite, replacement deletes and reinserts the row. A duplicate or repair save can therefore erase operational state that is not present in the incoming row, including read state, verified transport identity, quote linkage, inbox custody/retry fields, and future columns. The fix must prevent duplicate incoming clobber while preserving intentional outgoing status/custody transitions.

User-visible behavior to improve:

- Offline inbox drain progress, receipts, and local read state do not silently disappear when helper wiring is wrong.
- A broken DB read path fails closed instead of causing duplicate processing or wrong dedupe decisions.
- Duplicate incoming delivery cannot make a read or enriched message look unread/sparser, and cannot erase retry/custody metadata from an existing row.

Behavior that must stay unchanged:

- Outgoing sends still pre-persist `sending` rows and later update the same message id to `sent`, `pending`, or `failed`.
- Publish-success plus inbox-failure remains a visible success with `pending` retry state, not a duplicate row.
- Publish-failure plus inbox-failure remains a failed-message retry row, not inbox-only retry.
- Self-echo reconciliation promotes eligible local outgoing rows to `sent` without creating incoming duplicates.
- Local deletion tombstones still block user-deleted same-id replay saves, while membership repair deletion still allows same-id restore.

## Files And Repos To Inspect Next

Production files expected to change:

- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`

Production files to inspect but avoid editing unless evidence requires it:

- `lib/core/database/helpers/group_sync_receipts_db_helpers.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/main.dart`

Direct tests expected to change:

- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`

Preservation tests to run, but not edit unless a direct regression proves they need a focused assertion:

- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`

Closure docs to update only after implementation evidence:

- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`

## Existing Tests Covering This Area

Existing direct coverage:

- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` covers repository round trip, quoted ids, local-deletion tombstones, membership-repair deletion, status updates, failed outgoing queries, unread marking, content dedupe, cursor loading, receipt loading, and read receipt marking inside a real transaction.
- `test/core/database/helpers/group_messages_db_helpers_test.dart` covers group message insert/load/page/latest/count/read/delete basics, transport peer id, and quoted id round trips.
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` covers reliability columns, stuck-sending queries, failed outgoing queries, failed inbox-store queries, transition-to-failed behavior, and update helpers for `inbox_stored`, `inbox_retry_payload`, and `wire_envelope`.
- `test/features/groups/application/send_group_message_use_case_test.dart` pins pre-persist `sending` state, live publish/inbox result matrix, pending inbox retry, failed retry ownership, and no duplicate outgoing rows.
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` pins same-id pending inbox retry promotion to `sent` without duplicate rows.
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` pins self-echo reconciliation, duplicate-by-id dedupe, quote enrichment, tampered duplicate rejection, and conflicting duplicate sender rejection.
- `test/features/groups/application/group_message_listener_test.dart` pins duplicate live/replay handling, self-echo listener reconciliation, one notification for duplicate replay, and duplicate PubSub preservation of first row/content/status.

Missing coverage:

- No test currently proves `runInboxPageTransaction` fails when its durable transaction helper is missing.
- No test currently proves `dbLoadGroupMessage` rethrows DB errors instead of returning `null`.
- No DB-helper test currently proves duplicate incoming saves preserve existing operational fields under real SQLite row conflict behavior.
- No DB-helper test currently proves outgoing same-id saves still transition `sending` to final send states after `ConflictAlgorithm.replace` is removed.

## Regression/Tests To Add First

Add these tests before implementation and verify the target regressions fail in the current tree:

1. `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
   - Test name: `PGC-004 runInboxPageTransaction without helper fails before applying page writes`.
   - Construct a `GroupMessageRepositoryImpl` with `dbRunGroupInboxPageTransactionFn: null`.
   - Call `runInboxPageTransaction` with a non-empty `nextCursor`, at least one receipt, and `markReadMessageIds`.
   - The test must expect a `StateError` and prove the `apply` callback was not invoked.
   - Why it proves the seam: current code invokes `apply(this)` and returns, silently dropping cursor/receipt/read persistence.

2. `test/core/database/helpers/group_messages_db_helpers_test.dart`
   - Test name: `PGC-005 dbLoadGroupMessage rethrows database errors`.
   - Use a real SQLite executor in an error state, for example close the in-memory DB before calling `dbLoadGroupMessage`, or use another focused executor pattern already accepted in this repo.
   - The test must expect the database/query exception to propagate.
   - Keep the existing no-row test proving `null` for a successful empty query.
   - Why it proves the seam: current code catches every exception and returns `null`.

3. `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
   - Test name: `PGC-005 getMessage propagates db load errors`.
   - Inject a `dbLoadGroupMessage` function that throws.
   - Assert `repo.getMessage(id)` and `repo.existsByMessageId(id)` propagate the error rather than treating it as missing.
   - Why it proves the seam: callers must not collapse DB failures into dedupe misses.

4. `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
   - Test name: `PGC-006 duplicate incoming save preserves operational fields`.
   - Ensure this test file's setup runs the group message table migration plus the reliability, quoted-message, transport-peer-id, and local-deletion migrations needed by the columns under test. If `runGroupMessageTransportPeerIdMigration` is not already in this file at execution time, add it before writing the PGC-006 assertions.
   - Seed an incoming row with non-null `read_at`, `transport_peer_id`, `quoted_message_id`, and any reliability columns available in the migrated test DB.
   - Save the same id again as a duplicate incoming row with sparse/null operational fields and changed/tampered duplicate payload fields.
   - Assert there is still one row and the original `read_at`, `transport_peer_id`, `quoted_message_id`, status, timestamp/text, and retry/custody fields were not cleared or regressed. If the existing row has a null `quoted_message_id` and the duplicate carries a quote, allow quote enrichment only when that is already supported by `handle_incoming_group_message_use_case.dart`.
   - Why it proves the seam: current `ConflictAlgorithm.replace` can delete/reinsert and clobber columns omitted or nulled by the duplicate save.

5. `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
   - Test name: `PGC-006 outgoing duplicate save preserves intentional state transitions`.
   - Use the same migrated test setup as the duplicate incoming test so `wire_envelope`, `inbox_stored`, `inbox_retry_payload`, `quoted_message_id`, and `transport_peer_id` are all available.
   - Seed an outgoing row with `status = sending`, `wire_envelope` set, `inbox_stored = 0`, and `inbox_retry_payload` set.
   - Save the same id as an outgoing final row for each relevant final state: `sent` with `wire_envelope = null`, `inbox_stored = 1`, `inbox_retry_payload = null`; `pending` with `wire_envelope = null`, `inbox_stored = 0`, retry payload retained; and `failed` with failure retry fields retained.
   - Assert each update stays one row and applies the intentional outgoing fields exactly.
   - Why it proves the seam: the replacement removal must not accidentally freeze outgoing rows in stale `sending` state or drop retry ownership.

6. Preservation selectors, run before and after implementation:
   - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` selector `DE-005 self echo reconciles pending outbound row without creating incoming duplicate`.
   - `test/features/groups/application/group_message_listener_test.dart` selectors `NW-008 duplicate connection path delivery keeps one visible row and status`, `DE-005 self echo emits reconciled outbound row once`, and `GP-025 LP013 duplicate PubSub delivery preserves first row and notification state`.
   - `test/features/groups/application/send_group_message_use_case_test.dart` selectors `pre-persist: message saved with sending status + wireEnvelope + inboxRetryPayload BEFORE bridge call`, `IR-007 publish success plus inbox failure is pending and inbox retry closes same id`, `IR-007 publish failure plus inbox failure is failed and owned by message retry`, `GO-002 publish success with inbox failure stays pending and retryable`, and `publish fail + inbox OK keeps failed status but persists inbox success explicitly`.
   - `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` selector `IR-007 inbox retry sends same pending message id once without duplicate rows`.

## Step-By-Step Implementation Plan

1. Record dirty-worktree context before editing.
   - Run `git status --short`.
   - Do not revert or overwrite unrelated modified files.
   - If the two expected production files or three expected test files contain unrelated edits, keep edits narrow and do not normalize unrelated formatting.

2. Add the regression tests first.
   - Add the five `PGC-004`, `PGC-005`, and `PGC-006` focused tests above.
   - Run only those new selectors first and record which ones fail before implementation.
   - If any new selector unexpectedly passes, inspect current code before changing it; do not implement a redundant fix.

3. Implement `PGC-004` in `GroupMessageRepositoryImpl.runInboxPageTransaction`.
   - When `dbRunGroupInboxPageTransactionFn == null`, throw a `StateError` that names the missing inbox page transaction helper.
   - Throw before `apply` runs. A partial non-transactional fallback is not acceptable for this method because the method contract includes cursor, receipt, and read-marker durability.
   - Keep `getInboxCursor` and `getReceiptsForMessage` optional read helpers unchanged; this session only hardens the write transaction method.

4. Implement `PGC-005` in `dbLoadGroupMessage`.
   - Remove the catch-and-return-null behavior.
   - Optionally emit a DB error flow event consistent with nearby helpers, then rethrow.
   - Keep the successful empty-query behavior as `null`.
   - Do not broaden this row into count/page/latest helpers unless a new direct test proves the same target bug there; this session owns only the matrix-named `dbLoadGroupMessage` path.

5. Implement `PGC-006` in `dbInsertGroupMessage`.
   - Preserve the existing local deletion tombstone guard before any insert/update.
   - Stop using `ConflictAlgorithm.replace`.
   - Prefer a real insert for new ids.
   - Catch only the same-id uniqueness conflict when choosing the update path; rethrow unrelated database errors.
   - On same-id conflict, load the existing row and choose a direction-aware update:
     - Existing incoming plus duplicate incoming: preserve the existing durable message body and operational fields. Do not clear `read_at`, `transport_peer_id`, `quoted_message_id`, `wire_envelope`, `inbox_stored`, or `inbox_retry_payload`. Allow narrowly scoped enrichment only when the existing optional field is null and the duplicate carries the missing trusted value already expected by existing duplicate replay tests, such as missing `quoted_message_id` enrichment.
     - Existing outgoing plus outgoing final row: apply intentional send-state transitions from the new row, including `status`, `wire_envelope`, `inbox_stored`, `inbox_retry_payload`, and any send-owned quote/transport fields. Keep one row with the same id.
     - Existing outgoing plus validated self-echo reconciliation: keep it in the outgoing branch because `_reconcileOutgoingSelfEchoDuplicate` saves an outgoing `copyWith(status: 'sent', wireEnvelope: null)`.
     - Existing incoming plus outgoing, or conflicting sender/group/id direction not already handled by callers: fail closed or no-op without clobbering the existing row. Do not invent cross-direction merge semantics.
   - Use explicit column updates instead of delete/reinsert so future columns not named by the session are not dropped.
   - If current pending-key repair placeholder behavior requires upgrading an `undecryptable` incoming placeholder to a delivered incoming row with the same id, add a focused preservation selector before supporting that one upgrade path. Do not make general duplicate incoming replacement permissive.

6. Run the focused direct tests and preservation selectors.
   - Fix only failures caused by the session changes.
   - If a preservation selector exposes a legitimate conflict between duplicate incoming preservation and outgoing transition updates, keep outgoing transition preservation and narrow the incoming duplicate merge policy rather than returning to replacement.

7. Run the required named gate and hygiene checks.
   - Run direct owner suites after focused selectors.
   - Run the Group Messaging Gate because the shared group message persistence helper affects group send, receive, retry, and resume behavior.
   - Run format and diff hygiene.

8. Update closure docs only after tests/gates have evidence.
   - Mark matrix rows `PGC-004`, `PGC-005`, and `PGC-006` `Closed` only with exact code/test evidence.
   - Update the `PGC-DB-1` ledger row in the session breakdown with execution verdict and closure docs touched.
   - Do not mark dependent `PGC-SEND-1` closed from this work; only note that its DB dependency is satisfied if all PGC-DB-1 evidence passes.

Stop early if:

- Current code already contains a non-replace upsert that passes the new PGC-006 RED tests.
- `dbLoadGroupMessage` already propagates database errors in the dirty tree at execution time.
- The transaction helper is intentionally absent in a production construction path that the executor can prove is still used. In that case, convert `PGC-004` to blocked with exact wiring evidence instead of adding unsafe fallback behavior.

## Risks And Edge Cases

- Dirty worktree overlap: many group application and test files are already modified. Implementation must not revert or normalize unrelated edits.
- Outgoing transition regression: replacing `ConflictAlgorithm.replace` with a too-conservative no-op can leave rows stuck in `sending` or `pending`.
- Incoming clobber regression: a duplicate inbox/live replay with sparse fields can clear read state, transport identity, quote linkage, or retry metadata if update policy is too permissive.
- Self-echo: local outgoing rows must reconcile to outgoing `sent` without becoming incoming or unread.
- Offline replay: missing DB helper wiring must fail before cursor advancement can be lost. Silent fallback is worse than a thrown error.
- DB read failures: a closed/corrupt DB or query exception must not be mistaken for "message id not found".
- Repair placeholders: if same-id repair legitimately upgrades an `undecryptable` placeholder, support only that explicit path with a test.
- Local deletion tombstones: user-deleted same-id replay must still be blocked.
- Future columns: duplicate handling must avoid delete/reinsert so unknown future columns are not erased.

## Exact Tests And Gates To Run

Focused RED/implementation selectors:

```bash
flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name "PGC-004 runInboxPageTransaction without helper fails before applying page writes"
flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_test.dart --plain-name "PGC-005 dbLoadGroupMessage rethrows database errors"
flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name "PGC-005 getMessage propagates db load errors"
flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_reliability_test.dart --plain-name "PGC-006 duplicate incoming save preserves operational fields"
flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_reliability_test.dart --plain-name "PGC-006 outgoing duplicate save preserves intentional state transitions"
```

Preservation selectors:

```bash
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "DE-005 self echo reconciles pending outbound row without creating incoming duplicate"
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "NW-008 duplicate connection path delivery keeps one visible row and status"
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "DE-005 self echo emits reconciled outbound row once"
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "GP-025 LP013 duplicate PubSub delivery preserves first row and notification state"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "pre-persist: message saved with sending status + wireEnvelope + inboxRetryPayload BEFORE bridge call"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "IR-007 publish success plus inbox failure is pending and inbox retry closes same id"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "IR-007 publish failure plus inbox failure is failed and owned by message retry"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GO-002 publish success with inbox failure stays pending and retryable"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "publish fail + inbox OK keeps failed status but persists inbox success explicitly"
flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name "IR-007 inbox retry sends same pending message id once without duplicate rows"
```

Direct owner suites:

```bash
flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_test.dart
flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_reliability_test.dart
flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh groups
```

Required hygiene:

```bash
dart format lib/features/groups/domain/repositories/group_message_repository_impl.dart lib/core/database/helpers/group_messages_db_helpers.dart test/features/groups/domain/repositories/group_message_repository_impl_test.dart test/core/database/helpers/group_messages_db_helpers_test.dart test/core/database/helpers/group_messages_db_helpers_reliability_test.dart
git diff --check
```

Conditional gates:

```bash
flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart
./scripts/run_test_gates.sh completeness-check
```

Run the conditional commands only if implementation touches migrations, DB versioning, schema setup, gate definitions, or test classification docs. This plan does not expect those edits.

PR-wide gate:

```bash
./scripts/run_test_gates.sh baseline
```

Run this when the session is being landed as a PR or folded into a release gate, because the gate reference says Baseline runs on every PR. It is not a substitute for the direct PGC-DB-1 selectors.

## Known-Failure Interpretation

- Do not classify a failure in any new `PGC-004`, `PGC-005`, or `PGC-006` selector as historical unless it fails before implementation in the same dirty tree and the plan is updated with that evidence.
- Do not classify any failure in `group_messages_db_helpers_test.dart`, `group_messages_db_helpers_reliability_test.dart`, or `group_message_repository_impl_test.dart` as unrelated without a same-tree pre-run showing it was already red.
- If `./scripts/run_test_gates.sh groups` is red only on pre-existing non-PGC residuals already documented in the dirty tree, record the exact failing test names, counts, and logs, then verify all PGC-DB-1 direct selectors and owner suites are green. A group gate failure involving group message save/load, send-state transitions, duplicate incoming handling, inbox retry, self-echo, or replay is a session blocker.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` contains historical notes where group gate failures were preserved as unrelated residuals such as `BB-007`, `BB-012`, and `GM-029`, and completeness-check classification residuals existed in older work. Those notes are not automatic exemptions; re-check current failure names before using them.
- If multiple devices are attached for integration-backed gates, follow `Test-Flight-Improv/test-gates-reference.md` and set `FLUTTER_DEVICE_ID=<device-id>` where needed.

## Done Criteria

- The five new focused PGC selectors exist and pass.
- The new `PGC-004` selector proves missing helper throws before `apply`.
- The new `PGC-005` selectors prove DB errors propagate and no-row still returns `null`.
- The new `PGC-006` selectors prove duplicate incoming preservation and outgoing transition preservation under real SQLite helper behavior.
- Preservation selectors for self-echo, duplicate incoming handling, pending inbox retry, failed retry ownership, and no duplicate outgoing rows pass.
- Direct owner suites pass.
- `./scripts/run_test_gates.sh groups` passes, or any pre-existing unrelated red tests are documented exactly and no PGC-DB-1-related failure remains.
- `dart format` has been run on touched Dart files and `git diff --check` passes.
- Source matrix rows `PGC-004`, `PGC-005`, and `PGC-006` and the `PGC-DB-1` ledger row are updated with exact evidence.

## Scope Guard

Do not:

- Edit product or test files outside the named production/test files unless a failing PGC-DB-1 direct test proves the need.
- Touch migrations, DB version, schema docs, Go, relay, bridge/native code, group send UX, listener lifecycle, pending-membership buffering, key retention, relay ACLs, or envelope cryptography.
- Replace group message persistence with a broad generic ORM/upsert abstraction.
- Reopen 1:1 message persistence or copy 1:1 behavior unless used only as read-only reference.
- Turn incoming duplicate saves into full replacement.
- Freeze outgoing saves so `sending` cannot intentionally become `sent`, `pending`, or `failed`.
- Clear `wire_envelope`, `inbox_retry_payload`, `inbox_stored`, `read_at`, `transport_peer_id`, or `quoted_message_id` on duplicate incoming rows unless a row-specific test proves that exact transition is legitimate.
- Modify in-memory fake repositories to paper over DB-helper behavior. Fakes can receive matching assertions only if needed to keep existing tests meaningful.
- Mark rows `PGC-004`, `PGC-005`, or `PGC-006` closed from code inspection alone.

Overengineering signals:

- Adding a migration for this session.
- Adding a generalized conflict-resolution framework.
- Changing listener, send, drain, or retry architecture to compensate for DB-helper behavior.
- Expanding this session into `PGC-SEND-1`, `PGC-INCOMING-1`, or drain rows.

## Accepted Differences / Intentionally Out Of Scope

- 1:1 message DB helpers may use different merge/update semantics. This session does not seek 1:1 parity.
- `getInboxCursor` and `getReceiptsForMessage` remain optional read helpers returning `null` or empty values when not injected. The fail-fast requirement is only for the write transaction method that otherwise drops durable page state.
- The source matrix marks `PGC-003` and `PGC-017` skipped; this session does not revisit migrations or envelope AAD/header binding.
- `PGC-SEND-1` owns visible status semantics for live publish and inbox custody. `PGC-DB-1` only preserves the DB upsert behavior that later send work depends on.
- Durable pending-membership buffering and listener shutdown races remain `PGC-LISTENER-1`.

## Dependency Impact

- `PGC-SEND-1` depends on `PGC-DB-1` because repeated `saveMessage` calls must safely update the same outgoing message id during send and retry flows.
- `PGC-INCOMING-1` may rely on the duplicate incoming no-clobber contract when it narrows content-based dedupe.
- Drain/listener sessions benefit from `PGC-004` fail-fast behavior because a missing transaction helper becomes visible instead of creating replay-loop symptoms.
- If `PGC-006` changes materially during execution, rerun or revisit dependent send/retry plans before implementing `PGC-SEND-1`.

## Evidence Collected

- `private-group-chat-reliability-findings-2026-05-23-matrix.md` rows `PGC-004`, `PGC-005`, and `PGC-006` are `Open` and describe the three target risks.
- `private-group-chat-reliability-findings-2026-05-23-session-breakdown.md` classifies `PGC-DB-1` as `implementation-ready`, with no dependencies, and names the same intended plan file.
- `GroupMessageRepositoryImpl.runInboxPageTransaction` currently calls `apply(this)` and returns when `dbRunGroupInboxPageTransactionFn` is `null`.
- `lib/main.dart` production construction enables inbox page transactions for the app repository, so fail-fast protects unexpected/miswired construction without removing production functionality.
- `dbApplyGroupInboxPageTransaction` persists page writes, receipts, local read markers, and cursor together inside `dbWriteTransaction`.
- `dbLoadGroupMessage` currently catches all exceptions and returns `null`.
- `dbInsertGroupMessage` currently calls `db.insert(... conflictAlgorithm: ConflictAlgorithm.replace)`.
- `GroupMessage` maps the operational columns this session must preserve: `transport_peer_id`, `quoted_message_id`, `status`, `is_incoming`, `read_at`, `wire_envelope`, `inbox_stored`, and `inbox_retry_payload`.
- Send/retry tests already pin intentional outgoing transitions, including pre-persist `sending`, pending inbox retry, failed retry ownership, and same-id inbox retry promotion.
- Incoming/listener tests already pin self-echo, duplicate-by-id, duplicate quote enrichment, duplicate connection delivery, and duplicate PubSub preservation at the application level, but current DB helper tests do not pin real SQLite duplicate-save clobber behavior.

## Reviewer Findings

Reviewer verdict: sufficient with adjustments, and the adjustments have been applied in this plan.

Sufficiency questions:

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient with adjustments.
- What files, tests, regressions, or gates are missing? The first draft needed explicit PGC-006 test setup for `transport_peer_id` plus reliability columns, and one more outgoing preservation selector for publish-failure plus inbox-success. Those are now included.
- What assumptions are stale or incorrect? None found. Current code evidence confirms `runInboxPageTransaction` fallback, `dbLoadGroupMessage` catch-all, and `ConflictAlgorithm.replace` are still present in the inspected dirty tree.
- What is overengineered? No overengineering in the final plan. The scope guard blocks migrations, generalized conflict frameworks, and listener/send architecture changes.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. It gives one narrow production edit for `PGC-004`, one for `PGC-005`, one direction-aware helper edit for `PGC-006`, focused RED tests, preservation selectors, and stop conditions.
- What is the minimum needed to make the plan sufficient? Keep the current tests/gates and scope guard intact; implementation must add regressions first and must not broaden outside rows `PGC-004`, `PGC-005`, and `PGC-006`.

## Arbiter Decision

Structural blockers:

- None.

Incremental details:

- The reviewer-added migrated-test setup detail and outgoing preservation selector are now part of the plan.
- Exact `--plain-name` selectors may need trivial name adjustment only if the executor chooses a clearer test name while preserving the PGC row prefix and assertion contract.

Accepted differences:

- No 1:1 message DB parity work.
- No migration/schema change unless execution evidence unexpectedly proves one is necessary; the current plan treats such a need as a stop-and-replan condition.
- No `PGC-SEND-1` closure; this session only supplies its DB persistence prerequisite.

Arbiter verdict:

- No new structural blocker remains.
- The plan is execution-ready for rows `PGC-004`, `PGC-005`, and `PGC-006` only.

## Final Planning Output

Final verdict:

- `execution-ready`

Final plan:

- Add RED regressions for missing transaction helper fail-fast, DB read error propagation, duplicate incoming no-clobber, and outgoing same-id state transitions.
- Implement only `GroupMessageRepositoryImpl.runInboxPageTransaction` and `dbInsertGroupMessage`/`dbLoadGroupMessage` in `group_messages_db_helpers.dart`.
- Run the exact focused selectors, direct owner suites, `./scripts/run_test_gates.sh groups`, format, and `git diff --check`.
- Update only the source matrix rows `PGC-004`, `PGC-005`, `PGC-006`, and the `PGC-DB-1` ledger after evidence exists.

Structural blockers remaining:

- None.

Incremental details intentionally deferred:

- None that affect safety. Selector wording can change only if the assertion contract remains identical.

Accepted differences intentionally left unchanged:

- 1:1 persistence behavior, migrations, Go/relay/native code, listener lifecycle, send UX, and all non-`PGC-DB-1` rows.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`
- `Test-Flight-Improv/test-gates-reference.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/main.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/core/database/helpers/group_sync_receipts_db_helpers.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `test/core/database/helpers/group_messages_db_helpers_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`

Why the plan is safe to implement now:

- It is row-scoped to `PGC-004`, `PGC-005`, and `PGC-006`.
- It requires regressions before implementation.
- It names the preservation selectors that protect intentional outgoing state transitions.
- It explicitly blocks duplicate incoming replacement/clobber.
- It has a scope guard against migrations, architecture changes, unrelated dirty-worktree cleanup, and dependent-session closure.
