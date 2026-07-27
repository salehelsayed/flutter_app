# 283 - Unused GroupInboxCursor Model Removal

Status: Plan-green; implementation-complete and closed
Type: Modification
Spec: free-text DTR-10 item 7
Classification: implemented-and-verified
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-26 CEST | Evidence Collector | `group_inbox_cursor.dart`, runtime-root manifest/tests, migration 066, cursor DB helpers, repository/drain sources and tests, gate scripts | Confirmed that `GroupInboxCursor` is an orphan source model; the live cursor boundary uses raw DB rows and repository `String?` cursors without importing it | Define a leaf-only removal contract and persistence sentinels |
| 2026-07-26 CEST | Planner | DTR08-COMP-010, tier matrix, plan template, sufficiency checklist | Removal needs no schema/native/relay/device change; runtime-root bookkeeping must leave with the source while migration 066 and live cursor behavior remain protected | Hand off causal RED and preservation gates |
| 2026-07-27 CEST | Independent reviewer | Current source/tests/gates plus Graphify review context | Core deletion bet confirmed; TC-283-02 was corrected to an aggregate sentinel and TC-283-01 now retains the production `main.dart` cursor injection. Re-sweep verdict: `ready`; evidence, causality, scope, and gates clear; boundary/reversibility N/A | Execute the reviewed contract |

## Problem And Evidence

- Behavior to improve: remove the unused `GroupInboxCursor` Dart model without
  weakening the durable group inbox cursor used by startup and inbox replay.
- Impact: leaving the orphan makes the live persistence design ambiguous and
  invites a future cleanup to confuse one unused model with the production
  cursor table and repository transaction.
- Confirmed root cause/current gap: `GroupInboxCursor` is declared only in
  `lib/features/groups/domain/models/group_inbox_cursor.dart:1`; current-source
  exact-symbol and import searches find no executable consumer. The live
  repository instead injects a raw-row loader and returns a `String?` cursor at
  `lib/features/groups/domain/repositories/group_message_repository_impl.dart:170`
  and `:447`.
- Existing coverage:
  `test/core/database/migrations/066_group_sync_receipts_test.dart::PREREQ-GROUP-SYNC-RECEIPTS creates cursor and receipt tables idempotently`
  protects the table; DB helper, repository, and drain tests protect persistence,
  page-transaction ordering, retry, and replay. The full migration-chain tests
  protect both the v65-to-v66 upgrade and production registry ordering.
- Missing coverage: HEAD has no causal source contract requiring the orphan
  model and its DTR-01 candidate declaration to be absent while naming the live
  persistence files that must remain.
- Confirmed: `tool/runtime_roots/runtime_roots.json` records the exact source
  as a DTR-10 candidate, while
  `test/unit/runtime_root_inventory_test.dart::DTR-04 preserves owner-gated group and posts candidates`
  and
  `::repository manifest accounts for current non-main sources and keeps known candidates advisory`
  currently require it to remain. Those records must change atomically with
  deletion.
- Owner decision: the current authenticated project owner explicitly approved
  removal of only this unused model while preserving the real cursor boundary.
- Refuted: “removing `GroupInboxCursor` removes group inbox cursors” is refuted.
  Migration 066 creates `group_inbox_cursors`; DB helpers load/upsert raw rows;
  the repository and drain use cursor strings without this model.
- Unresolved findings: none for the leaf deletion. Any future table, migration,
  cursor format, or repository change remains a separate schema/protocol plan.
- Affected production, test, and gate files:
  `lib/features/groups/domain/models/group_inbox_cursor.dart`,
  `tool/runtime_roots/runtime_roots.json`,
  `test/unit/runtime_root_inventory_test.dart`,
  exact migration/helper/repository/drain preservation tests, and the existing
  `runtime-roots` and `groups` gates.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `0c2b989ba6d96ada`; current.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-10 remove only unused GroupInboxCursor model group_inbox_cursor.dart while preserving migration 066 group_sync_receipts database helpers repository page transaction and inbox behavior" --profile tdd --budget 700`.
- Anchors:
  `GroupInboxCursor` ->
  `lib/features/groups/domain/models/group_inbox_cursor.dart:1`;
  `group_sync_receipts` ->
  `test/features/account_migration/application/migration_database_schema_inventory_test.dart:134`.
- Surfaced proof/gate files: account-migration schema inventory and real
  SQLCipher staging tests; targeted source verification added migration 066,
  DB helper, group repository, drain, runtime-root, and gate registrations.
- Graph gaps requiring source search: the compact result did not surface the
  raw DB helper/repository/drain path or DTR runtime-root bookkeeping.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Delete only
  `lib/features/groups/domain/models/group_inbox_cursor.dart`.
- Remove only its exact declaration from
  `tool/runtime_roots/runtime_roots.json`.
- Replace the DTR-04 presence expectation with a DTR-10 absence/source-boundary
  contract and update the exact candidate-set expectation in
  `test/unit/runtime_root_inventory_test.dart`.

Must preserve:

- DB migration 066 table/index contract ->
  `PREREQ-GROUP-SYNC-RECEIPTS creates cursor and receipt tables idempotently`.
- Cursor persistence across reopen ->
  `PREREQ-GROUP-SYNC-RECEIPTS persists cursor and receipts across reopen`.
- Repository cursor/receipt transaction behavior ->
  `loads durable cursor and receipts through repository`.
- Drain starts at the persisted cursor and commits advancement only after page
  application ->
  the two named `PREREQ-GROUP-SYNC-RECEIPTS` drain tests.
- Production composition still injects `dbLoadGroupInboxCursor` and projects
  its raw row to the repository `String?` cursor ->
  `test/unit/runtime_root_inventory_test.dart::DTR-10 retires orphan GroupInboxCursor model only`.
- Full production migration registry ordering ->
  `test/core/database/integration/full_migration_chain_test.dart::production registries preserve the exact ordered v95 baseline`.
- The v65-to-v66 forward upgrade creates the live sync tables without losing
  group messages ->
  `test/core/database/integration/full_migration_chain_test.dart::PREREQ-GROUP-SYNC-RECEIPTS v65 to v66 upgrade creates sync tables and preserves group messages`.

Hard `Do not`:

- Do not edit migration 066, the `group_inbox_cursors` or
  `group_message_receipts` schemas, DB helpers, repository interfaces or
  implementations, drain/replay/listener behavior, `main.dart`, bridge/native/Go
  cursor formats, or account-migration cursor metadata.
- Do not add a replacement model merely to preserve the deleted shape.
- Do not delete persistence tests or reinterpret lack of fleet cursor telemetry
  as permission to alter storage.

Deferred / accepted difference:

- Persisted cursor storage and replay remain owned by Groups + Database +
  Release under DTR08-COMP-010; this plan resolves only the orphan Dart model.

Dependencies:

- DTR-01 runtime-root bookkeeping and DTR08-COMP-010 must be updated atomically
  with the leaf deletion.
- DTR10-AUTH-07 authorizes only this plan's exact model/manifest/test
  bookkeeping boundary.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-283-01 | The orphan model and its candidate declaration are absent, while exact migration/helper/repository/drain and production-composition anchors remain | `test/unit/runtime_root_inventory_test.dart::DTR-10 retires orphan GroupInboxCursor model only` | Host source/policy test over the real repository and runtime-root manifest | Causal RED: HEAD contains the source and declaration -> GREEN: both are absent while the live persistence path and `main.dart` `dbLoadGroupInboxCursorFn` injection remain | Restore the model/manifest declaration or remove the production cursor injection -> TC-283-01 red | `flutter test --no-pub test/unit/runtime_root_inventory_test.dart --plain-name 'DTR-10 retires orphan GroupInboxCursor model only'`; registered in existing `runtime-roots` gate |
| TC-283-02 | Runtime-root inventory remains complete and the candidate set no longer contains the retired model | `test/unit/runtime_root_inventory_test.dart::repository manifest accounts for current non-main sources and keeps known candidates advisory` | Host inventory tool against the coherent final tree | Aggregate GREEN sentinel, not a causal RED: the current shared tree already fails earlier on unrelated external-entrypoint/tracked-deletion drift -> GREEN only after the final-tree inventory is coherent and the retired candidate is absent | Restore the model or stale manifest declaration in a coherent final tree -> TC-283-02 red | `flutter test --no-pub test/unit/runtime_root_inventory_test.dart --plain-name 'repository manifest accounts for current non-main sources and keeps known candidates advisory'`; existing `runtime-roots` registration |
| TC-283-03 | Migration 066 still creates the live cursor and receipt tables idempotently | `test/core/database/migrations/066_group_sync_receipts_test.dart::PREREQ-GROUP-SYNC-RECEIPTS creates cursor and receipt tables idempotently` | Core migration host / SQLite FFI; preservation only, no SQLCipher or schema-change claim | GREEN sentinel -> GREEN unchanged after leaf deletion | Remove/rename the cursor table or a required column -> TC-283-03 red | `flutter test --no-pub test/core/database/migrations/066_group_sync_receipts_test.dart`; AUTO (`test/core/**`) |
| TC-283-04 | Cursor and receipts persist across database reopen | `test/core/database/helpers/group_sync_receipts_db_helpers_test.dart::PREREQ-GROUP-SYNC-RECEIPTS persists cursor and receipts across reopen` | Core repository/helper host / reopened SQLite FFI DB | GREEN sentinel -> GREEN unchanged | Stop persisting or loading the cursor row -> TC-283-04 red | `flutter test --no-pub test/core/database/helpers/group_sync_receipts_db_helpers_test.dart --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS persists cursor and receipts across reopen'`; AUTO (`test/core/**`) |
| TC-283-05 | Repository page transaction exposes the durable cursor and receipts | `test/features/groups/domain/repositories/group_message_repository_impl_test.dart::loads durable cursor and receipts through repository` | Feature repository host / real SQLite FFI helper-backed repository | GREEN sentinel -> GREEN unchanged | Bypass `dbLoadGroupInboxCursorFn` or receipt loading -> TC-283-05 red | `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'loads durable cursor and receipts through repository'`; AUTO and existing `GROUP_TESTS` entry |
| TC-283-06 | Inbox drain loads the durable cursor and advances it only after successful page application | `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::PREREQ-GROUP-SYNC-RECEIPTS loads durable cursor and advances only after page apply`; `::PREREQ-GROUP-SYNC-RECEIPTS failed page commit does not advance cursor or save receipts` | Feature application host / fake bridge plus helper-backed repository | GREEN sentinels -> GREEN unchanged | Advance before apply or commit cursor on failed page -> corresponding sentinel red | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS'`; AUTO and existing `GROUP_TESTS` entry |
| TC-283-07 | The supported migration registry still includes the exact v66 step, and a v65 profile upgrades without losing group messages | `test/core/database/integration/full_migration_chain_test.dart::production registries preserve the exact ordered v95 baseline`; `::PREREQ-GROUP-SYNC-RECEIPTS v65 to v66 upgrade creates sync tables and preserves group messages` | Core migration-chain host / production registries and SQLite FFI upgrade fixture | GREEN sentinels -> GREEN unchanged | Remove/reorder v66 or make its upgrade destructive -> corresponding sentinel red | Two exact `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name ...` commands below; AUTO (`test/core/**`) |

## Implementation Steps

1. Snapshot `git status --short`. Add TC-283-01 and update only the two
   inventory expectations required for the later deletion. Run TC-283-01 and
   record its causal RED because the model and declaration still exist. Record
   TC-283-02's existing unrelated aggregate failure separately; do not claim it
   as this plan's RED.
2. Delete `group_inbox_cursor.dart` and remove its exact manifest declaration.
   Do not touch any similarly named migration, table, metadata model, helper,
   repository, or bridge symbol.
3. Run TC-283-01 and DTR-04 in the shared tree, prove TC-283-02 through the
   coherent isolated `runtime-roots` gate, then run the exact migration/helper/
   repository/drain and migration-chain sentinels.
4. Run `runtime-roots`, `groups`, the justified feature family sweep, strict
   analysis, scope searches, and diff hygiene.
5. Perform representative mutations by restoring a temporary copy/declaration
   and, separately, removing the retained production cursor-injection anchor;
   prove TC-283-01 re-reds for both, then return to the intended deletion with
   `main.dart` byte-identical to its pre-plan state.

## Risks And Blind Spots

- Name collision with live cursor concepts -> TC-283-01 names exact protected
  anchors, including production composition, and TC-283-03 through TC-283-06
  exercise the real persistence path.
- Lifecycle / derived-state durability: TC-283-04 reopens the DB and TC-283-06
  resumes from its durable cursor.
- Sibling-surface consistency: account-migration
  `MigrationGroupInboxCursorMetadata` is a distinct retained type and is
  explicitly out of scope.
- Destructive-action side effects: TC-283-01 limits deletion to one source and
  one manifest declaration; TC-283-03/04 assert retained tables and rows.
- Invariant re-verification under new transitions: N/A — no transition changes;
  existing drain retry/commit sentinels remain green.

## Gate Cadence

- Per-plan closure: causal inventory contract, exact migration/helper/repository/
  drain sentinels, `runtime-roots`, `groups`, and the justified
  `feature-host-all` sweep because an app-owned feature source is deleted.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Wave 3 DTR-09/10/11
  batch is complete, and once at final rollout/release closure.
- Shared tests outside feature/core globs:
  `test/unit/runtime_root_inventory_test.dart` runs directly and through
  `runtime-roots`.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes.
git status --short

# Scaffolded causal RED; expect non-zero because the exact source/declaration
# still exist.
flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
  --plain-name 'DTR-10 retires orphan GroupInboxCursor model only'

# Aggregate inventory baseline only. On the current shared dirty tree this
# already exits non-zero before its candidate assertion because unrelated
# entrypoint/tracked-deletion inventory work is incomplete. Do not attribute
# that failure to TC-283; require this selector to be green on a coherent final
# tree before closure.
flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
  --plain-name 'repository manifest accounts for current non-main sources and keeps known candidates advisory'

# Focused GREEN in the shared tree; expect exit 0 and zero failed tests after
# deletion/bookkeeping. The aggregate selector is closed by the coherent
# isolated runtime-roots gate below.
flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
  --plain-name 'DTR-10 retires orphan GroupInboxCursor model only'
flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
  --plain-name 'DTR-04 preserves owner-gated group and posts candidates'

# Exact persistence preservation; expect exit 0 and zero failed tests.
flutter test --no-pub \
  test/core/database/migrations/066_group_sync_receipts_test.dart \
  test/core/database/helpers/group_sync_receipts_db_helpers_test.dart
flutter test --no-pub \
  test/features/groups/domain/repositories/group_message_repository_impl_test.dart \
  --plain-name 'loads durable cursor and receipts through repository'
flutter test --no-pub \
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS'
flutter test --no-pub \
  test/core/database/integration/full_migration_chain_test.dart \
  --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS v65 to v66 upgrade creates sync tables and preserves group messages'
flutter test --no-pub \
  test/core/database/integration/full_migration_chain_test.dart \
  --plain-name 'production registries preserve the exact ordered v95 baseline'

# Exact import/source absence. Test names may mention `GroupInboxCursor`, so the
# symbol census is intentionally production-only. Status 1 means no matches;
# status 0 (a match) or status >1 (an operational error) fails closed.
DTR10_CURSOR_IMPORT_STATUS=0
rg -n 'import .*group_inbox_cursor\.dart' \
  lib test --glob '*.dart' || DTR10_CURSOR_IMPORT_STATUS=$?
test "$DTR10_CURSOR_IMPORT_STATUS" -eq 1

DTR10_CURSOR_SYMBOL_STATUS=0
rg -n '\bGroupInboxCursor\b' \
  lib --glob '*.dart' || DTR10_CURSOR_SYMBOL_STATUS=$?
test "$DTR10_CURSOR_SYMBOL_STATUS" -eq 1

# Curated and affected family gates; expect exit 0 and target selection.
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# Hygiene; expect zero analyzer issues and no whitespace errors.
./scripts/check_flutter_analyze_strict.sh
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: after the test-only scaffold, TC-283-01 fails because the exact
  orphan source and manifest declaration still exist. TC-283-02 is an aggregate
  GREEN sentinel and its pre-existing shared-tree inventory failure is not this
  plan's RED.
- Green sentinel: migration 066, DB reopen, repository transaction, and drain
  commit/failure tests remain green.
- Pre-existing dirty tree / known failure: execution must record and preserve
  all unrelated user-owned changes before scaffolding.
- Environment blocker: none. The previously pending dirty-wave strict-analysis
  gate passed in the final root closure run.
- Scope drift: any need to edit schema, DB helper, repository/drain, native/Go,
  account-migration metadata, or `main.dart` stops execution and requires a new
  plan.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [x] Preservation and named gates pass with semantic outcomes.
- [x] Existing harness registrations select the named tests.
- [x] No schema, migration, native, Go, relay, or device surface changed.
- [x] Strict analysis has no issues and `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/unit/runtime_root_inventory_test.dart --plain-name 'DTR-10 retires orphan GroupInboxCursor model only'`.
- Contract size: seven rows; TC-283-01 is the causal removal RED, TC-283-02 is
  the aggregate final-tree inventory sentinel, and TC-283-03 through TC-283-07
  are persistence-preservation sentinels.
- Preservation command:
  `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS'`.
- Manual registration: none; runtime-root test uses the existing
  `runtime-roots` registration, core/feature tests auto-glob, and repository/
  drain tests already belong to `GROUP_TESTS`.
- Migration: none; DB migration 066 is unchanged and tested only as a sentinel.
- Boundary closure: host-only.
- Unresolved evidence: none for the exact orphan leaf.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-27 CEST | Review fixes | Plan, current source/tests/gates, Graphify review context | Independent review found TC-283-02 non-causal on the dirty tree and a missing production-composition sentinel; both were corrected and the re-sweep was `ready` | TC-283-01 is the sole causal RED; `main.dart` cursor injection is protected | None | Execute the corrected contract |
| 2026-07-27 CEST | Causal RED and mutations | Inventory test, retired model/declaration, read-only `main.dart` anchor | TC-283-01 failed only on the source/declaration before deletion; restoring both re-red; removing the production injection anchors re-red | Both counterexamples are discriminated; `main.dart` SHA-256 returned to `9027c35ead35b25189e3a9d2fe387af244abd7388b1e5e5b92e289eb2ddcb55f` | None | Apply the leaf deletion |
| 2026-07-27 CEST | Implementation and preservation | Model, manifest, inventory test; migration/helper/repository/drain/chain sentinels | Deleted the 31-line orphan and its exact declaration; TC-283-01, DTR-04, migration/helper (5 tests), repository (1), drain (4), v65-to-v66 (1), and registry (1) all passed | Live cursor tables, DB helpers, repository/drain transaction, production injection, metadata sibling, and migration chain remain intact | None | Run registered gates |
| 2026-07-27 CEST | Registered gates | Runtime-root and Groups suites; feature family | Detached `HEAD + Plan 283` `runtime-roots`: exit 0, 17 tests, trustworthy/no drift, exact three-path proof, shared index byte-identical; `groups`: exit 0, 3,235 tests; `feature-host-all --batch-flutter --concurrency 2 --reporter failures-only`: exit 0, 815 exact test paths, 8,485 passed, 1 expected SQLCipher capability skip | Plan-specific, curated, and aggregate feature behavior is green | None | Close strict analysis at wave/final aggregation |
| 2026-07-27 CEST | Analysis, graph, and hygiene | Plan-owned Dart test, whole package, architecture graph, source census | Scoped fatal analysis: no issues; broad strict analysis: one unrelated `waitUntil` unused warning in the pre-modified `group_edge_cases_smoke_test.dart`; incremental Graphify refresh current; source/directive/manifest census and `git diff --check` clean | Attributable delta is analyzer- and scope-clean | Dirty-wave strict gate pending; do not edit the unrelated test under Plan 283 | Close strict analysis at wave/final aggregation |
| 2026-07-27 CEST | Final closure | Repository-wide strict analysis and diff hygiene | Current root closure run: strict analyzer reported no issues; `git diff --check` passed | The sole pending dirty-wave gate is resolved; the earlier warning row is retained as execution history and superseded by this result | None | Plan-green |
