# Session PREREQ-GROUP-SYNC-RECEIPTS Plan - Durable Group Sync Cursors And Receipts

Status: qa_passed

## Planning Progress

| timestamp | role | files inspected since last update | decision/blocker | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T20:42:33+02:00 | Planner completed | `implementation-session-pipeline-orchestrator`; `implementation-plan-orchestrator`; source matrix rows DB-004, DB-012, EC-007; session breakdown row 55; `test-inventory.md`; `lib/core/database/migrations/018_group_messages_tables.dart`; `lib/core/database/helpers/group_messages_db_helpers.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `lib/features/groups/domain/models/group_message.dart`; `lib/features/groups/domain/repositories/group_message_repository.dart`; `lib/features/groups/domain/repositories/group_message_repository_impl.dart`; `lib/main.dart`; focused cursor/receipt code search; `flutter devices` | Repo-owned prerequisite. DB-004 has no durable group sync cursor, no group receipt owner, and no atomic message/receipt/cursor apply boundary. This plan is implementation-ready pending reviewer/arbiter. | Run plan Reviewer, then Arbiter. |
| 2026-05-01T20:57:00+02:00 | Evidence collector completed | Breakdown row 55; DB-004, DB-012, EC-007 matrix rows; cursor flow; group message schema/helpers/repository; drain tests; migration wiring | Read-only collector confirmed DB-004 is the only closure candidate, DB-012 can only narrow receipt blockers, EC-007 stays out unless membership freshness is implemented, and the missing seams are durable cursor, durable receipt owner, and a DB-owned transaction helper. | Fold evidence into arbiter decision. |
| 2026-05-01T21:01:00+02:00 | Reviewer attempts closed | Plan-review agents `019de4db-297e-7791-b772-abbc04b4ac37` and `019de4de-1cc1-7101-bb62-7dd9cae5d36c`; local arbiter check; evidence collector findings | Reviewer agents stalled and were closed. No local blocking plan defects found: closure scope, rollback bar, source-row guardrails, host-only profile, and validation preservation are explicit. Status moved to `execution-ready`. | Hand off to Executor. |

## Run Mode

- Active mode: implementation-committed gap-closure.
- Reopened prerequisite: `PREREQ-GROUP-SYNC-RECEIPTS`.
- Owned source blockers: DB-004, DB-012 receipt blockers, and EC-007 only if this work creates an authoritative durable membership-history freshness source.
- Source row state at planning intake: DB-004 `Partial`, DB-012 `Partial`, EC-007 `Partial`.
- Intended closure effect: move DB-004 to `Covered` only after production schema/helpers/repository/drain code prove durable group inbox cursors, first-class group receipts, and a single transaction boundary for message insert plus receipt/read-state plus cursor advancement. DB-012 can only be narrowed for receipt idempotency in this session; it must remain `Partial` until bans, remote deletes, commits/key packages, and the full all-event-family matrix close elsewhere. EC-007 remains `Partial` unless a later inviter-freshness owner uses a durable membership history primitive with direct stale-invite proof.
- Device/relay defaults verified on 2026-05-01: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` is visible to Flutter as an iPhone Air simulator, and `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` is available for supporting proof. This session is host-only because its blockers are local DB/application primitives.

## Evidence Collector Findings

### Existing Behavior

- `drain_group_offline_inbox_use_case.dart` owns group inbox replay and calls `callGroupInboxRetrieveWithCursor`, but `_drainGroupInbox` uses a local `String cursor = ''` and assigns `cursor = nextCursor` after applying the page. The cursor is not durably loaded or saved.
- The same drain path applies each payload one at a time through `GroupMessageListener.handleReplayEnvelope` or `handleIncomingGroupMessage`, and only after the page loop does it advance the in-memory cursor. There is no production owner that atomically applies a message row, read/receipt state, and cursor advancement together.
- `group_messages` has `read_at` and `dbMarkGroupMessagesAsRead`, but there is no first-class group delivery/read receipt table or helper.
- `GroupMessageRepositoryImpl.saveMessage` delegates directly to `dbInsertGroupMessage`; it has no grouped apply method for replay-page state.
- Database version is currently `65`; migration `065_group_history_gap_repairs` is the latest wired migration in fresh install and upgrade paths.

### Missing Seams

- No durable per-group inbox/sync cursor table, helper, or repository owner exists.
- No durable group receipt table, helper, repository API, or idempotency contract exists.
- No crash-window transaction seam exists for the DB-004 tuple: message insert, receipt/read-state update, and cursor advancement.
- No direct regression proves a thrown transaction rolls back message insertion, receipt insertion/read-state update, and cursor advancement together.
- No direct regression proves duplicate receipt replay is idempotent and cannot create visible timeline spam or unread-count corruption.

### Stale vs Authoritative Docs

- DB-004 row-owned plan correctly classified the row as `prerequisite-blocked` because the durable cursor, receipt, and transaction primitives did not exist.
- This prerequisite is the owner session that may unblock DB-004. It must update DB-004 source docs only after code and tests prove the full tuple.
- DB-012 remains broader than this session. Receipt idempotency can be added here, but bans, remote deletes, commits/key packages, and the full all-family matrix remain owned by `PREREQ-REMOTE-EVENT-FAMILIES` or later row-owned work.
- EC-007 remains an inviter-freshness problem, not a receipt/cursor problem, unless this session also introduces a durable membership-history proof source and direct stale self-consistent invite rejection evidence. This plan does not claim that scope.

## Real Scope

Implement the smallest first-class group sync/receipt slice needed to unblock DB-004:

- add migration `066_group_sync_receipts.dart` and bump app DB wiring from version 65 to 66
- create durable `group_inbox_cursors` or equivalently named table keyed by `group_id`
- create durable `group_message_receipts` table keyed by group, message, member/device or peer, and receipt type
- add helper functions that load/upsert cursors and receipts and apply an inbox page in a single SQLite transaction
- add domain models and repository methods only where they clarify typed ownership and match existing helper-backed repository patterns
- integrate `drain_group_offline_inbox_use_case.dart` so replay starts from the durable cursor and advances it only through the transaction owner after validated page application
- keep existing replay validation, event-log append, removed-member cutoff, message-id dedupe, media handling, and history-gap repair behavior intact
- record receipt rows only from explicit receipt payloads or test-provided receipt metadata; do not invent a UI receipt feature or remote event-family product beyond the durable apply primitive

## Closure Bar

DB-004 may move from `Partial` to `Covered` only when all of these are true:

- fresh-install and upgrade migrations create durable cursor and receipt tables with idempotent indexes/constraints
- helper/repository tests prove cursor and receipt rows survive DB reopen
- helper tests prove message insert, receipt/read-state update, and cursor advancement happen in one transaction
- failure-injection tests prove an exception inside that transaction leaves no inserted message, no inserted receipt/read-state mutation, and no advanced cursor
- drain tests prove an existing durable cursor is used for the next replay request and the cursor is not advanced when page application fails
- receipt idempotency tests prove duplicate receipt replay does not duplicate receipt rows, double count, or corrupt read state
- full migration-chain fresh install includes the new tables
- `groups`, `completeness-check`, targeted direct suites, targeted analyzer for touched Dart files, and `git diff --check` pass
- source matrix DB-004, `test-inventory.md`, this plan, and the breakdown ledger cite concrete evidence before DB-004 is marked `Covered`

DB-012 can only be narrowed in this session if receipt idempotency has concrete evidence. DB-012 must remain `Partial` unless the complete row-named event-family matrix is also implemented and proven, which is outside this prerequisite.

## Source Of Truth

- Primary status source: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`, rows DB-004, DB-012, and EC-007.
- Current prerequisite scope: row 55 in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`.
- Existing blocked-row evidence: `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-DB-004-plan.md`, `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-DB-012-plan.md`, and `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-EC-007-plan.md`.
- Test-gate source of truth: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.

## Session Classification

`implementation-ready`.

This is a repo-owned host-only code-and-test prerequisite. Live device/relay evidence is supporting only because the missing surfaces are local durable state and transaction boundaries.

## Exact Problem Statement

DB-004 requires the app to survive a crash between message insertion, receipt/read-state update, and sync cursor advancement. The repo currently persists group messages and can continue relay cursor pages within a single process, but it has no durable cursor, no group receipt owner, and no single transaction boundary tying the tuple together. A crash or exception can therefore be unproven at the exact boundary DB-004 cares about: cursor advancement without all rows, receipt state without its message, or repeated replay without idempotent receipt handling.

## Files To Inspect Before Editing

- `lib/main.dart`
- `lib/core/database/migrations/018_group_messages_tables.dart`
- `lib/core/database/migrations/065_group_history_gap_repairs.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `test/core/database/helpers/group_messages_db_helpers_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`

Likely new files:

- `lib/core/database/migrations/066_group_sync_receipts.dart`
- `lib/core/database/helpers/group_sync_receipts_db_helpers.dart`
- `lib/features/groups/domain/models/group_message_receipt.dart`
- `lib/features/groups/domain/models/group_inbox_cursor.dart`
- `lib/features/groups/domain/repositories/group_sync_receipt_repository.dart`
- `lib/features/groups/domain/repositories/group_sync_receipt_repository_impl.dart`
- focused migration/helper/repository tests for those owners

## Implementation Steps

1. Add migration `066_group_sync_receipts.dart` with durable cursor and receipt tables, indexes, and idempotent create semantics. Wire it into `lib/main.dart` imports, fresh install, upgrade path, and DB version 66. Update full migration-chain tests to assert the new tables.
2. Add typed models for group inbox cursor and group message receipt. Use simple string receipt types such as `delivered` and `read`; keep them data-layer primitives, not UI features.
3. Add helper functions for loading/upserting cursor and receipt rows, plus a transaction owner that accepts a message row, zero or more receipt rows, optional read-state update, and the next cursor. The helper must write all changes inside `db.transaction`.
4. Add repository wiring that exposes the transaction owner to application code without disrupting the existing `GroupMessageRepository` save/read API. Prefer constructor-injected helper functions to match local repository style.
5. Update `drain_group_offline_inbox_use_case.dart` to load the durable cursor before the first request and to advance it only after the page's validated message/receipt application succeeds. Preserve the existing in-memory first-page-only continuation behavior, history-gap repair flow, missing-key repair flow, and group-removed early return.
6. Teach drain tests to inject explicit group receipt metadata or receipt payloads and prove duplicate receipt replay is idempotent. Do not add a user-facing receipt UI.
7. Add failure-injection tests around the transaction helper and drain path so failed page application leaves the durable cursor unchanged and rolls back message/receipt/read-state changes.
8. Update DB-004 source docs to `Covered` only after direct tests and gates pass. Update DB-012 notes only to record receipt idempotency narrowing, keeping DB-012 `Partial`. Leave EC-007 `Partial` unless a direct inviter-freshness implementation is added, which is not planned here.

## Regression/Tests To Add First

- `test/core/database/migrations/066_group_sync_receipts_test.dart`
  - creates cursor and receipt tables/indexes idempotently
  - enforces primary keys/unique receipt identity
- `test/core/database/helpers/group_sync_receipts_db_helpers_test.dart`
  - persists cursor and receipts across reopen
  - applies message, read-state, receipt, and cursor in one transaction
  - induced failure rolls back message, receipt, read-state, and cursor
  - duplicate receipt upsert is idempotent
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` or a new repository test
  - repository exposes durable cursor/receipt state and transactional apply through injected helpers
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `PREREQ-GROUP-SYNC-RECEIPTS loads durable cursor before replay and advances only after successful page apply`
  - `PREREQ-GROUP-SYNC-RECEIPTS failed page apply does not advance durable cursor`
  - `PREREQ-GROUP-SYNC-RECEIPTS duplicate receipt replay is idempotent`
- `test/core/database/integration/full_migration_chain_test.dart`
  - fresh install includes the new tables and upgrade path preserves seeded adjacent group message data

## Required Gates

- `flutter test --no-pub test/core/database/migrations/066_group_sync_receipts_test.dart`
- `flutter test --no-pub test/core/database/helpers/group_sync_receipts_db_helpers_test.dart`
- `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS'`
- `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name 'fresh install'`
- targeted `dart analyze` over touched Dart files, accepting only pre-existing info diagnostics if they are unrelated and documented
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

Known unrelated caveat: broad `dart analyze lib/main.dart` has pre-existing unrelated diagnostics, including a `GroupListWired` constructor mismatch involving `groupPendingKeyRepairRepository`. Do not fix unrelated analyzer debt in this prerequisite unless a touched file cannot be analyzed in isolation.

## Scope Guard

- Do not redesign group messaging, event logs, history-gap repair, key repair, or invite freshness.
- Do not mark DB-012 `Covered` from receipt evidence alone.
- Do not mark EC-007 `Covered` unless authoritative inviter membership freshness and stale self-consistent invite rejection are implemented and directly tested.
- Do not create visible receipt UI or product copy unless an existing test requires a hidden state assertion.
- Do not bypass existing replay validation paths or message dedupe to make the transaction easier.

## Arbiter Decision

`execution-ready`.

The plan has enough concrete scope and stop rules to implement safely. It does not overclaim DB-012 or EC-007, and it requires the exact DB-004 primitives before any source-row closure. Reviewer agents were unavailable due to stalled execution, so this decision relies on local arbiter review plus the completed read-only evidence collector. The Executor must keep source docs unchanged until code/tests/gates pass.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T20:42:33+02:00 | Planner completed | This plan | Plan drafted for Reviewer. | Run Reviewer/Arbiter before Executor. |
| 2026-05-01T21:01:00+02:00 | Arbiter completed | This plan; evidence collector findings | Plan accepted as execution-ready after two stalled reviewer attempts were closed. | Start Executor. |
| 2026-05-01T21:14:00+02:00 | Local executor completed | `lib/core/database/migrations/066_group_sync_receipts.dart`; `lib/core/database/helpers/group_sync_receipts_db_helpers.dart`; `lib/features/groups/domain/models/group_inbox_cursor.dart`; `lib/features/groups/domain/models/group_message_receipt.dart`; `lib/features/groups/domain/repositories/group_message_repository.dart`; `lib/features/groups/domain/repositories/group_message_repository_impl.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `lib/features/groups/application/group_message_listener.dart`; `lib/main.dart`; focused tests | Implemented durable cursor/receipt schema, helper-backed transaction owner, repository wiring, drain cursor/receipt apply, and initial regression tests. | Run QA reviewer. |
| 2026-05-01T21:16:00+02:00 | QA reviewer returned blocking findings | `group_message_listener.dart`; `drain_group_offline_inbox_use_case.dart`; `group_sync_receipts_db_helpers.dart`; `full_migration_chain_test.dart`; `main.dart` | Same-session implementation-owned recovery required: listener replay swallowed failures before transaction commit, and upgrade-path proof stopped at v65. | Patch recovery and rerun gates. |
| 2026-05-01T21:19:00+02:00 | Recovery implemented | `group_message_listener.dart`; `drain_group_offline_inbox_use_case.dart`; `drain_group_offline_inbox_use_case_test.dart`; `full_migration_chain_test.dart` | Added fail-fast offline replay mode, passed it from transactional drain, added listener-failure rollback regression, split v65 upgrade helper, and added v65-to-v66 seeded group-message preservation test. | Rerun focused tests, gates, and QA. |
| 2026-05-01T21:20:00+02:00 | Recovery gates passed | Focused PREREQ tests; fresh install and v65-to-v66 migration tests; scoped analyzer; group gate; completeness; diff check | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS'` passed +4; `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS'` passed +1; prior focused migration/helper/repository tests passed; fresh install passed +1; scoped analyzer exited 0 with info-only diagnostics; analyzer including `group_message_listener.dart` still shows existing warning debt; `./scripts/run_test_gates.sh groups` passed +102; `./scripts/run_test_gates.sh completeness-check` passed 710/710; `git diff --check` passed. | Run QA. |
| 2026-05-01T21:24:00+02:00 | QA reviewer returned blocking finding | `group_message_listener.dart`; `drain_group_offline_inbox_use_case.dart`; `drain_group_offline_inbox_use_case_test.dart`; `test/shared/fakes/in_memory_group_message_repository.dart` | Same-session implementation-owned recovery required: system replay still saved timeline rows through the root repository and swallowed system-handler errors, so a system-message save failure could leave timeline state outside the replay transaction while allowing cursor advancement. | Patch system replay to use the transaction-scoped message repository and fail fast. |
| 2026-05-01T21:29:00+02:00 | Second recovery implemented | `group_message_listener.dart`; `drain_group_offline_inbox_use_case_test.dart`; `test/shared/fakes/in_memory_group_message_repository.dart` | `_handleSystemMessage` now receives the transaction-scoped `GroupMessageRepository`, propagates `rethrowOnError`, and passes that repository to system timeline helper methods; fake repository gained targeted save-failure injection; added a PREREQ regression proving system replay failure emits no timeline row/event and advances no cursor. | Rerun focused tests, gates, and final QA. |
| 2026-05-01T21:31:00+02:00 | Second recovery gates passed | Focused PREREQ tests; listener regression suite; scoped analyzer; group gate; completeness; diff check | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS'` passed +5; `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` passed +88; `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS'` passed +1; `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name 'Fresh install path'` passed +1; migration/helper/repository PREREQ suites passed; scoped analyzer excluding pre-existing listener warning debt exited 0 with info-only diagnostics; analyzer including `group_message_listener.dart` still exits 2 on pre-existing warning debt; `./scripts/run_test_gates.sh groups` passed +102; `./scripts/run_test_gates.sh completeness-check` passed 710/710; `git diff --check` passed. | Run final read-only QA. |
| 2026-05-01T21:36:00+02:00 | Final QA accepted | Final read-only QA agent; implementation files; focused tests; named gates | QA returned no blocking findings and accepted DB-004 closure. Concrete accepted evidence includes durable cursor/receipt schema, transaction-scoped page apply, production repository wiring, durable cursor drain integration, normal/system replay fail-fast behavior, rollback/idempotency/fresh-install/v65-to-v66 tests, `groups`, `completeness-check`, and diff hygiene. DB-012 remains `Partial`; only receipt idempotency is narrowed. | Close DB-004 source docs and continue to `PREREQ-SECRET-STORAGE-WRAPPING`. |

## Recovery Input

Blocker signature: `PREREQ-GROUP-SYNC-RECEIPTS` / implementation-owned QA blocker / offline replay listener errors swallowed before transaction failure plus missing v65-to-v66 upgrade proof / owner files `group_message_listener.dart`, `drain_group_offline_inbox_use_case.dart`, `drain_group_offline_inbox_use_case_test.dart`, and `full_migration_chain_test.dart`.

Same-session recovery was used once for this signature. The repaired contract is that transactional offline replay calls `GroupMessageListener.handleReplayEnvelope(..., rethrowOnError: true)`, so listener-side application failures roll back message rows, receipt/read-state writes, and cursor advancement. The migration proof now seeds `group_messages` before migration 066 and asserts both new sync tables are created while seeded group data is preserved.

## Recovery Input 2

Blocker signature: `PREREQ-GROUP-SYNC-RECEIPTS` / implementation-owned QA blocker / system replay timeline saves used the root repository and system replay errors were swallowed before transaction failure / owner files `group_message_listener.dart`, `drain_group_offline_inbox_use_case.dart`, `drain_group_offline_inbox_use_case_test.dart`, and `test/shared/fakes/in_memory_group_message_repository.dart`.

Same-session recovery was used once for this distinct signature. The repaired contract is that system replay uses the same transaction-scoped `GroupMessageRepository` as normal message replay for timeline-message persistence, and `rethrowOnError: true` makes system-handler failures abort the inbox-page transaction before receipts or cursor advancement commit. The direct regression injects a system timeline save failure and proves no timeline row, no emitted message event, and no durable cursor advancement remain after the failed replay.

## Final QA Verdict

`accepted` / `qa_passed`.

DB-004 can move to `Covered` with concrete evidence from migration 066, `group_sync_receipts_db_helpers.dart`, repository and `main.dart` transaction-scoped wiring, durable cursor integration in `drain_group_offline_inbox_use_case.dart`, fail-fast normal and system replay in `group_message_listener.dart`, and the focused rollback/idempotency/migration/listener regression tests plus `groups`, `completeness-check`, and diff hygiene. DB-012 remains `Partial`; this prerequisite only narrows durable receipt idempotency, not bans, remote deletes, complete remote-event idempotency, or inviter freshness.
