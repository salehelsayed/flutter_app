# DB-001 Plan: Original Group Table Creation Migrations Before 026

## real scope

Add direct migration coverage for the original pre-026 group schema owners: `017_groups_tables.dart` and `018_group_messages_tables.dart`. The session should prove the `groups`, `group_members`, `group_keys`, and `group_messages` tables are created idempotently with expected baseline columns, defaults, constraints, indexes, and baseline insert/query behavior.

Do not redesign the group schema, do not add new migration versions, and do not broaden into later group migrations except where needed to explain that 026+ coverage is already separate.

## closure bar

DB-001 can close when a focused migration test proves a clean pre-026 database can run migrations 017 and 018, insert/query one valid baseline group/member/key/message set, observe expected defaults and CHECK/UNIQUE/PRIMARY KEY constraints, and rerun both migrations without schema drift or duplicate-index failure. The source matrix and `test-inventory.md` must record DB-001 as `Covered` with file-and-command evidence.

## source of truth

- Primary row: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`, row `DB-001`.
- Decomposition/ledger: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`.
- Inventory: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- Current code beats stale prose: `lib/core/database/migrations/017_groups_tables.dart`, `lib/core/database/migrations/018_group_messages_tables.dart`, and existing migration tests under `test/core/database/migrations/`.

## session classification

`implementation-ready`. Current repo evidence suggests this is a missing direct-test gap, so production code should change only if the new DB-001 regression exposes a real migration defect.

## exact problem statement

The matrix still marks DB-001 `Open` because the inventory explicitly says there are no tests for the original group table creation migrations before 026. Later tests cover additions such as `quoted_message_id`, metadata, mute, dissolve, backlog, invite revocation/consumption, member permissions, and media columns, but there is no row-owned proof for the original group tables themselves.

## files and repos to inspect next

- `lib/core/database/migrations/017_groups_tables.dart`
- `lib/core/database/migrations/018_group_messages_tables.dart`
- `test/core/database/migrations/026_group_quoted_message_id_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## existing tests covering this area

`026_group_quoted_message_id_test.dart` uses migrations 017 and 018 as prerequisites before testing migration 026, and `full_migration_chain_test.dart` runs the broad chain. Those are supporting evidence only because neither asserts the original pre-026 group table schema, constraints, indexes, idempotency, and baseline row behavior as DB-001 requires.

## regression/tests to add first

Add `test/core/database/migrations/017_018_group_original_tables_test.dart` or an equivalently named focused test file. It should:

- run `runGroupsTablesMigration` and `runGroupMessagesTablesMigration` on an in-memory database
- assert all four original tables exist
- assert important columns and defaults for `groups`, `group_members`, `group_keys`, and `group_messages`
- assert the group member role/type CHECK constraints and unique topic/primary-key constraints reject invalid or duplicate rows
- insert/query one baseline group, member, key, and message row before any 026+ migration runs
- rerun migrations 017 and 018 and assert table/index state remains usable

## step-by-step implementation plan

1. Add the focused pre-026 migration test file under `test/core/database/migrations/`.
2. Keep production migrations unchanged unless the test exposes a real mismatch between intended DB-001 behavior and current migration SQL.
3. Run the focused DB-001 migration test.
4. If production code changed, run `test/core/database/integration/full_migration_chain_test.dart`.
5. Update the source matrix row DB-001 to `Covered` with concrete file and command evidence.
6. Update `test-inventory.md` to remove the stale missing-coverage statement and add DB-001 coverage evidence.
7. Update this plan with execution evidence and final verdict.

## risks and edge cases

The main risk is overclaiming later group schema behavior as original pre-026 coverage. The test should assert only the columns and constraints introduced by migrations 017 and 018, not columns added later by 026, 041, 048-059, or future migrations. Another risk is treating the broad migration chain as enough; it is not row-owned DB-001 closure without direct assertions.

## exact tests and gates to run

Required direct test:

```sh
flutter test --no-pub test/core/database/migrations/017_018_group_original_tables_test.dart
```

Run if production migration code changes:

```sh
flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart
```

Recommended after docs update:

```sh
./scripts/run_test_gates.sh completeness-check
git diff --check
```

The breakdown lists broad group gates, but DB-001 is a migration-schema row. Do not spend a full groups/integration sweep unless production behavior outside migrations changes.

## known-failure interpretation

Unrelated dirty-tree failures in group UI, media, or network suites are not DB-001 regressions unless this session changes those files. A failure in the new DB-001 migration test or full migration chain after changing migration code is blocking.

## done criteria

- A focused pre-026 migration test exists and passes.
- DB-001 source matrix status is `Covered`.
- `test-inventory.md` records the DB-001 test and no longer says original group table creation migrations have no tests.
- The session ledger records DB-001 as accepted with the plan path and exact evidence.
- No unrelated existing dirty-tree changes are reverted.

## scope guard

Do not add migration 060, do not rewrite migrations 017/018 unless a direct test proves a real bug, do not add foreign keys to old tables as part of this row, do not change repository behavior, and do not cover later migrations here. DB-001 is only the original group table creation contract before 026.

## accepted differences / intentionally out of scope

The original migrations do not include later columns such as `quoted_message_id`, reliability columns, metadata watermarks, mute/dissolve/backlog state, invite tables, member permissions, or media integrity/encryption fields. Those are intentionally covered by later migration rows and must not be folded into DB-001.

## dependency impact

Closing DB-001 gives later DB rows a stable baseline for original group table creation. It does not unblock rows that require signed event logs, transactional crash recovery, export policy, search APIs, or migration APIs.

## execution evidence

- Local execution fallback was used after the spawned execution agent produced no on-disk code or evidence within the bounded wait.
- Added `test/core/database/migrations/017_018_group_original_tables_test.dart`.
- The focused test proves migrations 017/018 create `groups`, `group_members`, `group_keys`, and `group_messages`; expose expected baseline columns/defaults/indexes; support baseline group/member/key/message insert and query before migration 026; enforce original type, role, unique-topic, member primary-key, and key primary-key constraints; and rerun idempotently.
- No production migration code changed, so the full migration chain was not required by this plan.
- Direct gate passed: `flutter test --no-pub test/core/database/migrations/017_018_group_original_tables_test.dart` (`+3`).
- Source matrix row `DB-001` was updated to `Covered`.
- `test-inventory.md` was updated with DB-001 crosswalk evidence, migration inventory entry, aggregate count increments, and removal of the stale pre-026 migration coverage gap.

## final verdict

Execution complete and ready for closure audit. DB-001 meets the plan closure bar with focused test evidence and no production migration changes.
