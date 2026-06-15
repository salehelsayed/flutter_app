Status: executed-accepted

# MIG-004 Plan: SQLCipher snapshot, schema manifest, and DB import staging

Source doc: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`  
Breakdown artifact: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`  
Session id: `MIG-004`  
Session title: SQLCipher snapshot, schema manifest, and DB import staging

## Planning Progress

- 2026-06-07 00:00:45 CEST - Arbiter completed. Files inspected since last update: reviewer outcome, patched tests/docs and command contract, accepted differences, scope guard, and stop rule. Decision/blocker: no structural blockers remain; patched incremental details are sufficient and the plan is execution-ready. Next action: hand this exact MIG-004 plan to implementation execution; do not broaden into later Move Account sessions.
- 2026-06-07 00:00:45 CEST - Reviewer completed; Arbiter started. Files inspected since last update: full MIG-004 draft, mandatory section list, checklist ledger, SQLCipher evidence-gated wording, test/gate commands, simulator-gate rationale, docs contract, and later-session exclusions. Decision/blocker: plan is sufficient with small adjustments only; no structural blocker. Next action: patch missing cleanup-test list entry and explicit format/diff commands, then arbitrate.
- 2026-06-06 23:57:17 CEST - Planner completed; Reviewer started. Files inspected since last update: this draft plan synthesized from the collected evidence. Decision/blocker: draft covers the requested MIG-004 checklist, dependencies, tests/gates, docs contract, known-failure interpretation, and scope guard; no implementation has been performed. Next action: review the draft for missing proof, simulator-gate need, hidden later-session scope, and stale assumptions.
- 2026-06-06 23:57:17 CEST - Evidence Collector completed; Planner started. Files inspected since last update: source proposal lines for DB import/export acceptance gaps, MIG-004 breakdown row, MIG-001/MIG-003 plan/closure notes, current dirty status, graphify queries, DB opener, main database version/migration chain, identity secret/null-column migrations, secure-storage staging/cleanup, identity repository, gate definitions/scripts, test inventory, `pubspec.yaml`, and existing DB/secure-storage tests. Decision/blocker: no current account-migration DB snapshot/import primitive exists; normal DB opener and MIG-003 staging contracts are reusable evidence; SQLCipher runtime capability must be proven by execution, not assumed. Next action: draft the execution-safe plan.
- 2026-06-06 23:53:25 CEST - Evidence Collector started. Files inspected since last update: `git status --short`, required plan path existence check. Decision/blocker: plan artifact did not exist; dirty worktree contains MIG-001 through MIG-003 changes and must be preserved. Next action: query graphify before broad source browsing, then collect scoped source, breakdown, secure-storage, SQLCipher, migration, and gate evidence.

## Execution Progress

- 2026-06-07 00:37:54 CEST - Phase: local QA fallback found compile blocker. Inspected evidence: host and macOS SQLCipher export capability reruns, `flutter devices`, staged-open capability command output, graphify query for `MigrationSecureStoreScope`, `migration_database_import_staging.dart`, `migration_secure_storage_staging.dart`, and `migration_secure_storage_key.dart` enum references. Current command/state: no command running; `flutter test test/features/account_migration/application/migration_database_import_staging_test.dart --plain-name "opens staged SQLCipher database with staged key"` fails at load time because `migration_database_import_staging.dart` references `MigrationSecureStoreScope` without importing the model that defines it. Decision/blocker state: additional session-caused compile blocker found; SQLCipher export capability also remains unproven on host and macOS with `MissingPluginException`. Next action: spawn fresh Executor fix pass 2 to add the missing model import or equivalent narrow compile fix, rerun the staged-open focused test, and then stop blocked if real SQLCipher capability remains unproven.
- 2026-06-07 00:36:28 CEST - Phase: post-fix QA spawn fallback / local final review. Inspected evidence: post-fix QA Reviewer agent status, latest plan progress, and scoped status. Current command/state: spawned post-fix QA Reviewer did not return a handoff or update file-backed progress during the bounded wait and was closed with previous status `running`; no QA file edits were observed. Decision/blocker state: local read-only QA fallback is being used; current blocking evidence is the required SQLCipher capability proof failing on both host and macOS-target commands per fix-pass handoff. Next action: independently rerun the focused SQLCipher capability commands, record exact results, then write the final blocked verdict if capability remains unproven.
- 2026-06-07 00:33:09 CEST - Phase: Executor fix pass 1 stopped on user request / evidence-gated handoff. Inspected/touched evidence: schema-inventory fixture, snapshot-exporter fixture/capability test, direct-test outputs, `flutter devices`, target-specific macOS capability output, package/repo search for existing SQLCipher test-registration paths, formatter result, graphify update state, and scoped `git status --short`. Current command/state: no command is running; `graphify update .` was started after code changes, stayed running past the bounded wait, did not accept stdin interruption, and was terminated with `pkill -f "graphify update \\."` at the stop boundary. Decision/blocker state: `blocked` / `environment_blocker`; schema-inventory and manifest direct tests pass, snapshot exporter fake-adapter behavior passes, but real SQLCipher export capability remains unproven because both host and explicit macOS-target `flutter test` capability commands fail with `MissingPluginException(No implementation found for method openDatabase on channel com.davidmartos96.sqflite_sqlcipher)`. Next action: next retry should focus on a supported plugin-registered SQLCipher capability harness/command for MIG-004 before attempting to close this session; do not mark breakdown MIG-004 closed.
- 2026-06-07 00:29:26 CEST - Phase: direct test 3 capability host failure / target retry starting. Inspected/touched evidence: snapshot exporter rerun output after binding initialization. Current command/state: `flutter test test/features/account_migration/application/migration_database_snapshot_exporter_test.dart` remains `+2 -1`; failure is the `SQLCipher export capability` case with `MissingPluginException(No implementation found for method openDatabase on channel com.davidmartos96.sqflite_sqlcipher)`, while the two fake-adapter exporter behavior tests pass. Decision/blocker state: host runner cannot prove real SQLCipher capability; classification `environment/tooling-related capability gap` pending target retry, not accepted. Next action: inspect available Flutter devices and try an exact macOS-target SQLCipher capability command before deciding whether MIG-004 must stop evidence-gated.
- 2026-06-07 00:28:42 CEST - Phase: direct test 3 rerun failed / focused triage classified. Inspected/touched evidence: snapshot exporter rerun output and existing test-binding patterns. Current command/state: `flutter test test/features/account_migration/application/migration_database_snapshot_exporter_test.dart` improved to `+2 -1`; remaining failure is the `SQLCipher export capability` case returning unsupported because Flutter services binding was not initialized before the SQLCipher plugin path. Decision/blocker state: session-caused test harness setup failure for the capability probe, not a production SQLCipher capability verdict yet. Next action: initialize `TestWidgetsFlutterBinding` in the snapshot exporter test and rerun the same focused direct test.
- 2026-06-07 00:27:50 CEST - Phase: direct test 3 failed / focused triage classified. Inspected/touched evidence: snapshot exporter test output, snapshot exporter fixture, and scoped fixture pattern scan across MIG-004 database tests. Current command/state: `flutter test test/features/account_migration/application/migration_database_snapshot_exporter_test.dart` failed `+0 -3`; no command running. Decision/blocker state: session-caused fixture isolation failure before production behavior: source/exported fixture DBs both use `inMemoryDatabasePath`, so `identity` already exists during setup; teardown also uses `late` DBs. Next action: patch only the snapshot exporter fixture to use isolated temp DB paths and safe nullable teardown, then rerun the same focused snapshot exporter direct test.
- 2026-06-07 00:27:19 CEST - Phase: direct test 2 completed / direct test 3 starting. Inspected/touched evidence: manifest test/model and snapshot exporter test/implementation. Current command/state: `flutter test test/features/account_migration/application/migration_database_manifest_test.dart` passed `+2`; about to run `flutter test test/features/account_migration/application/migration_database_snapshot_exporter_test.dart`. Decision/blocker state: manifest slice green; snapshot exporter slice `pending_triage`. Next action: run the snapshot exporter direct test and classify any SQLCipher/export or fixture failures before applying fixes.
- 2026-06-07 00:26:55 CEST - Phase: direct test 1 completed / direct test 2 starting. Inspected/touched evidence: schema-inventory fixture and manifest model/test entry points. Current command/state: `flutter test test/features/account_migration/application/migration_database_schema_inventory_test.dart` passed `+2`; about to run `flutter test test/features/account_migration/application/migration_database_manifest_test.dart`. Decision/blocker state: schema-inventory fixture blocker resolved; manifest slice status `pending_triage`. Next action: run the manifest direct test and triage only manifest-slice failures if red.
- 2026-06-07 00:26:27 CEST - Phase: schema-inventory fixture fix applied. Inspected/touched evidence: `test/features/account_migration/application/migration_database_schema_inventory_test.dart` and weak scoped Graphify result for MIG-004 schema/import context. Current command/state: about to run `flutter test test/features/account_migration/application/migration_database_schema_inventory_test.dart`. Decision/blocker state: fixture blocker addressed narrowly by using nullable teardown, `singleInstance: false` in-memory opens, and removing manual `sqlite_sequence` creation; behavioral status still `pending_triage` until focused rerun completes. Next action: rerun the schema-inventory direct test and triage only that slice if it remains red.
- 2026-06-07 00:25:30 CEST - Phase: fresh Executor fix pass 1 start. Inspected evidence: existing `## Execution Progress` entries and prior local QA fallback blocker for `migration_database_schema_inventory_test.dart`. Current command/state: no code edits, fixture triage, SQLCipher capability commands, or gate reruns have started in this fix pass. Decision/blocker state: `pending_triage`; MIG-004 remains not accepted, first direct test is known red from the fixture creating reserved `sqlite_sequence`, reused in-memory DB state, and unsafe teardown after setup failure. Next action: run scoped graphify/context checks, inspect the failing fixture and MIG-004 direct-test contract, fix only the schema-inventory fixture first, then rerun that focused test before continuing the remaining required direct tests.
- 2026-06-07 00:24:29 CEST - Phase: local QA fallback completed. Inspected evidence: Executor handoff, `flutter test test/features/account_migration/application/migration_database_schema_inventory_test.dart` rerun, schema-inventory test fixture, schema-inventory implementation, `currentIdentityDatabaseVersion` extraction, and scoped status/diff. Current command/state: no command running; focused QA rerun failed with `+0 -2` on reserved `sqlite_sequence`, reused `:memory:` state, and late `db` teardown after open failure. Decision/blocker state: blocking issues remain: first direct MIG-004 test is red, direct test suite/gates are incomplete, SQLCipher capability evidence is missing, and MIG-004 is unsafe to accept. Next action: spawn fresh Executor fix pass 1 to fix the schema-inventory fixture first, then continue required direct-test triage and capability/gate collection without broadening beyond MIG-004.
- 2026-06-07 00:23:54 CEST - Phase: QA spawn fallback. Inspected evidence: QA Reviewer agent status, this progress section, and `git status --short`. Current command/state: spawned QA Reviewer did not return a handoff or update file-backed progress during the bounded wait and was closed with previous status `running`; no QA file edits were observed. Decision/blocker state: `spawn_or_tool_failure` for the spawned QA attempt only; local sequential fallback is being used for the QA review step because the failed QA child produced no partial code/test/doc work. Next action: perform a focused local QA review of the partial MIG-004 landing and Executor handoff, then either spawn a fresh Executor fix pass for blocking issues or finish blocked if the workflow cannot safely continue.
- 2026-06-07 00:20:23 CEST - Phase: stopped on user request / Executor handoff. Inspected/touched evidence: latest direct-test output for `flutter test test/features/account_migration/application/migration_database_schema_inventory_test.dart`, scoped status for MIG-004 files, and prior initial red-test output. Current command/state: no command is running; last completed command failed with `+0 -2` because the test fixture attempted to create reserved table `sqlite_sequence` and reused `inMemoryDatabasePath` across opens, causing `identity already exists`. Decision/blocker state: `test_or_gate_failure`; implementation is partial and not QA-ready; SQLCipher capability commands have not been run and capability remains unproven. Next action: on retry, fix the schema-inventory fixture to use isolated DB paths or `singleInstance: false` and avoid manually creating `sqlite_sequence`, then continue direct-test triage before capability/gate collection.
- 2026-06-07 00:19:43 CEST - Phase: implementation pass 1 complete / direct tests starting. Inspected/touched evidence: added `currentIdentityDatabaseVersion`, MIG-004 schema inventory, manifest/cipher metadata, SQLCipher snapshot exporter/adapter/probe, staged DB import opener/verification, import validator, DB artifact cleanup, and narrow FFI import fixes for the new tests; formatted `lib/features/account_migration` and `test/features/account_migration`. Current command/state: about to run the six direct MIG-004 tests individually. Decision/blocker state: initial red failure classified as session-caused missing MIG-004 APIs plus test import ambiguity; no SQLCipher capability verdict yet. Next action: run direct tests, triage any failing slice before further fixes, then collect the explicit capability commands.
- 2026-06-07 00:14:37 CEST - Phase: contract extracted / red-test capture starting. Inspected evidence: MIG-004 real scope, closure bar, source-of-truth, required six direct tests, affected existing tests, named gates, dirty worktree, graphify query output, Flutter SQLite DB map, and the six landed MIG-004 test files. Current command/state: about to run `flutter test` across the six direct MIG-004 test files for initial red evidence. Decision/blocker state: `pending_triage`; expected failure is missing MIG-004 production API/behavior; do not fix before recording result. Next action: run the six direct new tests, classify the initial failure, then implement the smallest production surface the tests require.
- 2026-06-07 00:13:40 CEST - Phase: fresh Executor recovery start. Inspected evidence: plan path and existing `## Execution Progress` entries, workspace root, and presence of `graphify-out/graph.json`. Current command/state: no test reruns, code edits, or failure triage started in this recovery pass yet. Decision/blocker state: `pending_triage`; prior Executor red-test additions must be preserved; MIG-004 remains not accepted; real SQLCipher export/open/cipher capability is still evidence-gated and fake-only proof is insufficient. Next action: extract the exact MIG-004 contract from this doc, inspect the six landed direct tests plus narrow owner files, run graphify queries before broad source browsing, capture red-test evidence where feasible, then implement only MIG-004.
- 2026-06-07 00:12:32 CEST - Phase: controller bounded-wait recovery. Inspected evidence: first Executor agent status, this progress section, `git status --short`, and new MIG-004 test file inventory under `test/features/account_migration/application/`. Current command/state: first Executor made real assigned-step progress by adding the six direct red-test files, but did not return a final result after the bounded wait plus one progress-based extended wait and was closed with previous status `running`. Decision/blocker state: partial red-test evidence exists; not accepted; no production implementation handoff yet; avoid hidden state by spawning a fresh isolated Executor recovery pass against the repo evidence now present. Next action: fresh Executor must inspect the landed tests, capture/complete red-test evidence if needed, implement MIG-004 narrowly, run required tests/gates, and write a trustworthy final handoff or exact evidence-gated blocker.
- 2026-06-07 00:11:20 CEST - Phase: red tests added. Inspected/touched evidence: added the six required MIG-004 direct test files under `test/features/account_migration/application/` for schema inventory, manifest compatibility, SQLCipher snapshot export, staged import open, import validation, and DB artifact cleanup. Current command/state: production implementation files have not been added yet; tests define the intended narrow MIG-004 APIs and capability plain-name cases. Decision/blocker state: pending red-test evidence; no blocker yet. Next action: run the six new direct test commands and record initial failures before implementation.
- 2026-06-07 00:06:13 CEST - Phase: executor contract extraction. Inspected evidence: MIG-004 plan/breakdown/source-doc scope, current dirty worktree, graphify query for MIG-004 SQLCipher/import staging context, Flutter SQLite repo DB map, existing account-migration application/model/test inventory, and required test/gate list. Current command/state: no code edits started; `graphify query "MIG-004 account migration SQLCipher snapshot schema manifest import staging existing code tests" --budget 2400` returned only broad SQLCipher/staging nodes, so plan plus targeted source files remain authoritative. Decision/blocker state: no blocker yet; execute only MIG-004; preserve MIG-001 through MIG-003/user edits; do not mark breakdown MIG-004 closed; SQLCipher capability remains evidence-gated and fake-only proof is unacceptable. Next action: inspect narrow DB opener, migration chain/version, secure-storage staging/cleanup APIs, identity helper/repository, and peer test patterns, then add the required direct red tests before production implementation.
- 2026-06-07 00:04:40 CEST - Phase: controller contract extraction. Inspected evidence: this MIG-004 plan, reusable breakdown, source proposal, `git status --short`, graphify query for MIG-004 SQLCipher/import staging context, execution/QA skill contract, Flutter SQLite guidance, and Flutter test guidance. Current command/state: no code edits started; graphify query returned only weak broad matches, so the plan and targeted source files remain authoritative for implementation. Decision/blocker state: execution contract is concrete; no blocker; dirty MIG-001 through MIG-003 worktree must be preserved; execute only MIG-004 and do not update the breakdown row to closed. Next action: spawn a fresh Executor with requested model `gpt-5.5` and `reasoning_effort: xhigh` in the role prompt to add direct red tests first, implement narrowly, run required evidence/gates, update this progress section during long phases, and stop evidence-gated if real SQLCipher capability cannot be proven.

## real scope

MIG-004 implements only the account-migration database export/import core:

- Produce a consistent SQLCipher database snapshot for the current encrypted `identity.db` using `sqlcipher_export` or another explicitly proven SQLCipher/SQLite-consistent primitive.
- Add a migration DB manifest with migration protocol version, source app/build version when available, minimum importer/app version policy, current exported DB version `74`, schema hash, generated durable table/column inventory, SQLCipher opener/cipher metadata, and DB checksum fields.
- Define a SQLCipher cipher-parameter compatibility policy. Prefer pinned migration PRAGMAs before first read when supported; otherwise record opener metadata and run a tested `cipher_migrate` or explicit rejection path.
- Stage imported DB files under migration-session paths and verify they open with the staged `db_encryption_key` from MIG-003 before any active DB path or active secure-storage key is overwritten.
- Verify staged import identity rows preserve null secret columns: `identity.private_key`, `identity.mnemonic12`, and `identity.ml_kem_secret_key` stay `NULL`; required staged secure-storage values exist for `db_encryption_key`, `identity_private_key`, `identity_mnemonic12`, and required ML-KEM material before `secrets_migrated` can be promoted.
- Verify DB checksum, schema compatibility, `PRAGMA quick_check` or stronger available integrity check, manifest/schema hash, unsupported versions, wrong DB key, torn snapshot, stale manifest, and missing staged identity secrets all fail closed.
- Define rollback and cleanup boundaries for staged DB files, SQLite sidecars, manifest files, and interaction with MIG-003 failed-import cleanup.

MIG-004 must not implement media/app-owned file manifests or copies, group device identity/NSE continuity, local transfer, durable cutover, migrated-out runtime gates, pending-work migration, UI journey, erase/reset UI, runtime named gates beyond DB/startup safety, or final device acceptance. It also must not mark the overall Move Account program complete.

## closure bar

MIG-004 is good enough when direct tests and documented evidence prove every requested item below:

| Requested item | Required MIG-004 proof |
| --- | --- |
| SQLCipher consistent snapshot/export | Exporter uses `sqlcipher_export` or a proven equivalent through a narrow adapter. Tests prove a snapshot of seeded committed rows imports cleanly and reject torn/incomplete outputs. Execution must collect actual SQLCipher capability evidence; a fake-only proof is insufficient. |
| Schema/app version manifest | Manifest includes protocol/app/min-importer fields, DB version `74`, generated table/column inventory from the current migrated schema, schema hash, and source DB checksum. Tests reject missing, stale, unsupported, or incompatible version fields. |
| SQLCipher cipher parameter policy | Tests cover metadata capture and either pinned PRAGMA application before open, `cipher_migrate`, or explicit incompatible-parameter rejection. Execution must record which SQLCipher PRAGMAs are actually readable/settable in this repo target. |
| DB import staging/open verification | Import opens only a staged DB path with the staged DB key from MIG-003, runs schema/checksum/integrity verification before commit, and never calls normal `openEncryptedDatabase` in a way that can generate a new active DB key or empty replacement database. |
| Imported identity-row null-secret verification tied to staged secure-storage secrets | Validator proves imported identity rows keep the three secret columns `NULL`, required staged identity/DB/ML-KEM secrets are present, active keys remain untouched before promotion, and `secrets_migrated` is not promoted before this verification succeeds. If a bridge-backed ML-KEM challenge primitive is available, include it; otherwise record the missing primitive as a later cryptographic proof residual and do not pretend it passed. |
| DB checksum/schema compatibility | Manifest checksum and schema hash/inventory match the staged DB; wrong checksum, changed schema, lower/greater unsupported DB versions, missing table/column entries, and integrity-check failures reject import before commit. |
| Rollback/cleanup boundaries | Failed/cancelled import deletes staged DB, sidecars, manifest/temp files, and invokes MIG-003 failed-import cleanup only for the session; active DB, active secure-storage keys, and device-local authority are not touched. Successful import cleanup removes staging artifacts only after verification/promotion handoff is safe. |

No simulator closure gate is required for MIG-004 because this session is host-testable DB/snapshot/import validation and explicitly excludes multi-device transfer, transport, notifications, lifecycle, cutover, media rendering, and final iOS-to-iOS acceptance. Later sessions still need simulator/device evidence.

## source of truth

- Primary product/security contract: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`, especially the rows requiring consistent DB snapshots, DB key-before-open ordering, checksum rejection, version compatibility, SQLCipher parameter compatibility, null identity secret columns, staged secure-storage verification, and existing SQLCipher behavior preservation.
- Session boundary: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`, MIG-004 row. This wins over broader feature requirements for what belongs in this session.
- Dependency contracts: MIG-001 device-local authority/import precondition code and MIG-003 secure-storage registry/staging/promotion/cleanup code and closure notes. MIG-004 consumes those contracts; it does not reopen them.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- Current code/tests win over stale prose. Evidence inspected includes `lib/core/database/encrypted_db_opener.dart`, `lib/main.dart`, `lib/core/database/migrations/001_identity_table.dart`, `003_mlkem_keys.dart`, `004_nullify_secret_columns.dart`, `005_secret_null_checks.dart`, `lib/features/account_migration/application/migration_secure_storage_staging.dart`, `migration_secure_storage_registry.dart`, `migration_secure_storage_cleanup.dart`, `lib/features/identity/domain/repositories/identity_repository_impl.dart`, existing DB tests, and gate scripts.
- Graphify was queried first as required. The initial SQLCipher/MIG-004 query returned weak broad matches; the secure-storage query returned useful MIG-003 staging/cleanup nodes. Targeted docs and source are authoritative where graph context was incomplete.

Dirty-worktree note: planning observed existing modified/untracked files from MIG-001 through MIG-003 plus this MIG-004 plan. Treat them as current user/controller work and do not revert them.

## session classification

implementation-ready

The session has a narrow host-testable implementation path, but it has a hard evidence stop: execution must prove the real SQLCipher export/open/cipher metadata capability on an actual supported repo target. If that capability cannot be proven after adding the narrow adapter/probe, execution must stop as evidence-gated rather than substituting fake-only snapshot proof.

## exact problem statement

The app currently opens `identity.db` with `openEncryptedDatabase`, which loads or creates `db_encryption_key`, migrates plaintext DBs with `sqlcipher_export`, and opens version `74` through `main.dart`. Existing tests mostly prove key format and full migration-chain schema, not account-migration export/import.

The Move Account feature needs an import path that can copy and verify a current encrypted SQLCipher DB without creating an empty replacement DB, losing schema-version-74 rows, accepting incompatible SQLCipher defaults, or promoting secure-storage sentinels before imported secrets are ready. Without MIG-004, later media/group/transfer/cutover sessions have no trustworthy DB bundle boundary.

Normal startup SQLCipher opening, plaintext-to-encrypted migration, identity loading, secure-storage migration, and migration-chain behavior must stay unchanged for non-migration users.

## files and repos to inspect next

Production files likely to add:

- `lib/features/account_migration/domain/models/migration_database_manifest.dart`
- `lib/features/account_migration/domain/models/migration_database_validation_result.dart`
- `lib/features/account_migration/application/migration_database_schema_inventory.dart`
- `lib/features/account_migration/application/migration_database_snapshot_exporter.dart`
- `lib/features/account_migration/application/migration_database_import_staging.dart`
- `lib/features/account_migration/application/migration_database_import_validator.dart`

Production files to inspect/update narrowly:

- `lib/core/database/encrypted_db_opener.dart` - reuse SQLCipher export/open knowledge; do not route staged import through key-generation behavior.
- `lib/main.dart` - current DB version is `74` and migration order is authoritative. Extract a tiny reusable current-version/migration-runner source only if execution needs it to avoid a stale duplicate.
- `lib/core/database/migrations/` - schema inventory source through current migrations `001` through `074`.
- `lib/core/database/helpers/identity_db_helpers.dart` - identity row loading if the validator uses helper-backed reads.
- `lib/features/account_migration/application/migration_secure_storage_staging.dart`
- `lib/features/account_migration/application/migration_secure_storage_registry.dart`
- `lib/features/account_migration/application/migration_secure_storage_cleanup.dart`
- `lib/features/account_migration/application/account_migration_import_precondition.dart`
- `lib/features/identity/domain/repositories/identity_repository_impl.dart`
- `pubspec.yaml` - currently has `sqflite_sqlcipher`, `sqflite_common_ffi`, `path_provider`, and `crypto`.

Tests and docs:

- New `test/features/account_migration/application/migration_database_manifest_test.dart`
- New `test/features/account_migration/application/migration_database_schema_inventory_test.dart`
- New `test/features/account_migration/application/migration_database_snapshot_exporter_test.dart`
- New `test/features/account_migration/application/migration_database_import_staging_test.dart`
- New `test/features/account_migration/application/migration_database_import_validator_test.dart`
- New `test/features/account_migration/application/migration_database_import_cleanup_test.dart`
- Existing `test/core/database/encrypted_db_opener_test.dart`
- Existing `test/core/database/integration/full_migration_chain_test.dart`
- Existing `test/features/account_migration/application/migration_secure_storage_staging_test.dart`
- Existing `test/features/account_migration/application/migration_secure_storage_cleanup_test.dart`
- Existing `test/features/account_migration/application/account_migration_import_precondition_test.dart`
- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
- `Test-Flight-Improv/codebase-test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` only if new tests require explicit executable classification.

## existing tests covering this area

- `test/core/database/encrypted_db_opener_test.dart` proves DB encryption key string/storage contracts only; it does not currently open/export/import an account-migration database.
- `test/core/database/integration/full_migration_chain_test.dart` proves full schema migration coverage and key schema-version-74 columns, but not exported snapshot integrity or manifest compatibility.
- Individual `test/core/database/migrations/*_test.dart` files prove migration semantics and idempotency for many migrations, including identity null-secret constraints and version-74 group-message logical delivery fields.
- `test/core/secure_storage/migrate_secrets_to_secure_storage_test.dart` proves normal startup secret migration and nulling of identity secret columns, not staged import ordering.
- `test/features/identity/domain/repositories/identity_repository_impl_test.dart` proves identity loading reads secrets from secure storage and mirrors ML-KEM secrets to the shared store, not staged import verification.
- MIG-003 tests prove session-scoped staging, promotion validation, rollback, cleanup, and required staged secret presence. They do not prove a staged DB can open with the staged DB key or that an imported identity row matches staged secrets.
- `test/features/account_migration/application/account_migration_import_precondition_test.dart` proves new-phone import preconditions around active identity/authority, not DB staging internals.

Missing today:

- No account-migration DB manifest model or generated schema inventory.
- No direct test proves current DB version `74` table/column inventory is captured from the migrated schema.
- No account-migration SQLCipher export/import primitive exists.
- No test rejects torn SQLCipher snapshots, wrong DB keys, stale manifests, unsupported DB versions, checksum mismatch, or schema mismatch.
- No import validator ties null identity secret columns to MIG-003 staged secure-storage secrets before `secrets_migrated` promotion.
- No cleanup test covers staged DB files and SQLite sidecars.

## regression/tests to add first

Add red tests before production implementation:

- `test/features/account_migration/application/migration_database_schema_inventory_test.dart`
  - Builds or opens a current migrated schema and proves generated inventory contains all durable non-`sqlite_%` tables and columns, including schema-version-74 fields such as `group_members.devices_json`, `group_messages.transport_peer_id`, `group_messages.last_send_attempt_at`, `group_messages.logical_delivery_id`, group welcome package tombstones, pending key repair/membership tables, sync receipt tables, and inbox staging tables.
  - Proves schema hash changes when a durable table/column is missing from the inventory.
- `test/features/account_migration/application/migration_database_manifest_test.dart`
  - Proves manifest serialization includes protocol version, source app/build version field or explicit unknown marker, minimum importer version, DB version `74`, schema hash, DB checksum, SQLCipher metadata/policy, and generated table/column inventory.
  - Proves incompatible protocol/app/min-importer/database versions are rejected before DB commit.
- `test/features/account_migration/application/migration_database_snapshot_exporter_test.dart`
  - Proves the exporter invokes a SQLCipher export/equivalent adapter against an already-open source DB, writes only encrypted/staged output paths, computes a checksum, and rejects an adapter result that does not pass integrity/schema checks.
  - Includes a capability/probe test or evidence hook that executes `PRAGMA cipher_version` and the chosen export primitive on a supported target. If host FFI cannot do this, record the target-specific evidence command and stop as evidence-gated until it passes.
- `test/features/account_migration/application/migration_database_import_staging_test.dart`
  - Proves staged import reads `db_encryption_key` through `MigrationSecureStorageStaging.readStagedValue`, opens the staged DB path with that key, and does not call active-key generation or active DB replacement.
  - Proves wrong/missing staged DB key, unsupported SQLCipher metadata, incompatible schema, failed `quick_check`/integrity check, and checksum mismatch fail closed and leave active DB and active secure-storage keys untouched.
- `test/features/account_migration/application/migration_database_import_validator_test.dart`
  - Proves identity row secret columns are `NULL`.
  - Proves required staged primary/shared identity secrets exist before allowing secure-storage promotion.
  - Proves active `secrets_migrated` is not set by DB import verification itself.
  - Proves optional ML-KEM challenge verification runs when a bridge-backed challenge primitive is available; otherwise the validator reports a distinct residual/unsupported proof state that cannot be counted as final cryptographic acceptance.
- `test/features/account_migration/application/migration_database_import_cleanup_test.dart`
  - Proves failed/cancelled import deletes staged DB files, `-wal`, `-shm`, temp/export sidecars, manifest artifacts, and invokes MIG-003 failed-import cleanup for that session without deleting unrelated active keys or active authority.

Then run affected existing direct tests for DB opener, migration chain, secure-storage staging/cleanup, and import preconditions.

## step-by-step implementation plan

1. Add the red tests above. Keep fixture DBs small but include representative rows/tables from identity, contacts, messages/conversations, groups, posts/social-feed, introductions, inbox staging, and version-74 group delivery fields. Do not add media files or app-owned file manifests in this session.
2. Add manifest and validation-result models. Keep them data-only with explicit protocol/current DB version constants and deterministic JSON ordering for stable hashes.
3. Add schema inventory generation from an open `Database` using `sqlite_master`, `PRAGMA table_info`, and index/trigger metadata only if needed for compatibility. Exclude `sqlite_%` internals and ephemeral temp tables.
4. Add a schema hash and DB checksum helper using `package:crypto` SHA-256. Checksum the exported encrypted DB artifact; schema hash is over canonical inventory JSON.
5. Add a narrow SQLCipher export adapter abstraction so tests can prove command ordering while execution can plug in real `sqlcipher_export` or an equivalent proven primitive. Do not expose generic raw SQL execution outside the migration module.
6. Implement the snapshot exporter. It must require an already-open source DB supplied by the caller, write to a migration staging/export path, compute checksum, capture SQLCipher metadata, and verify exported DB integrity before returning the manifest.
7. Add SQLCipher metadata/policy handling. Read `PRAGMA cipher_version` plus supported cipher settings where available; apply pinned PRAGMAs before first read or run `cipher_migrate` only through a tested branch. If the package/runtime cannot expose needed PRAGMAs, fail with an explicit unsupported-parameter result.
8. Implement staged import opening against a non-active DB path. It must obtain the DB key from MIG-003 staged secure storage, never from active storage, and never call `openEncryptedDatabase` in a mode that can generate or persist a new active `db_encryption_key`.
9. Implement import validation in this order: manifest/version compatibility, checksum, SQLCipher open, integrity check, schema inventory/hash, identity row null-secret checks, required staged secret presence, optional cryptographic identity proof when available, then verified result.
10. Add cleanup helpers for staged DB artifacts and sidecars. Wire failure/cancellation to MIG-003 `failedImportCleanup`/staging cleanup at the service boundary without changing MIG-003 internals.
11. If implementation needs the DB version/migration runner outside `main.dart`, extract only a tiny shared database schema source of truth and update `main.dart` to use it. Do not change migration semantics or reorder existing migrations.
12. Run direct tests and format touched Dart files. Update docs after tests pass.
13. Run completeness and baseline gates as listed below. Run `graphify update .` after code changes, per repo guidance.
14. Stop and replan if execution discovers that SQLCipher export cannot be proven on any supported target, if staged import requires a broad app startup rewrite, if DB-key verification cannot be separated from active secure-storage promotion, or if media/files/group/cutover behavior becomes necessary to make tests pass.

## risks and edge cases

- Calling normal `openEncryptedDatabase` during import can generate a fresh `db_encryption_key`, create an empty DB, or persist active state before verification.
- SQLCipher settings can differ across exporter/importer defaults. The plan must prove pinned/migrated settings or reject incompatible artifacts.
- Copying a live DB file without SQLCipher/SQLite snapshot semantics can miss WAL/committed state or produce a torn snapshot.
- `PRAGMA quick_check` may be weaker than full `integrity_check`; execution should use the strongest practical check and record the chosen evidence.
- Schema inventory can drift if it duplicates the migration list manually. Prefer live schema introspection and a current-version constant over hand-maintained tables.
- Identity secret columns must remain null in the DB. Reintroducing DB-resident secrets would violate migration 005 and normal secure-storage behavior.
- `secrets_migrated` is dangerous if set before staged DB and staged identity secrets are verified.
- Cleanup must remove SQLite sidecars and temp artifacts without deleting active `identity.db` or unrelated active secure-storage keys.
- Host FFI may not prove real SQLCipher behavior. Treat that as an evidence problem, not as permission to claim fake adapter coverage.

## exact tests and gates to run

Direct new MIG-004 tests:

```bash
flutter test test/features/account_migration/application/migration_database_schema_inventory_test.dart
flutter test test/features/account_migration/application/migration_database_manifest_test.dart
flutter test test/features/account_migration/application/migration_database_snapshot_exporter_test.dart
flutter test test/features/account_migration/application/migration_database_import_staging_test.dart
flutter test test/features/account_migration/application/migration_database_import_validator_test.dart
flutter test test/features/account_migration/application/migration_database_import_cleanup_test.dart
```

Affected existing direct tests:

```bash
flutter test test/core/database/encrypted_db_opener_test.dart
flutter test test/core/database/integration/full_migration_chain_test.dart
flutter test test/core/secure_storage/migrate_secrets_to_secure_storage_test.dart
flutter test test/features/identity/domain/repositories/identity_repository_impl_test.dart
flutter test test/features/account_migration/application/migration_secure_storage_staging_test.dart
flutter test test/features/account_migration/application/migration_secure_storage_cleanup_test.dart
flutter test test/features/account_migration/application/account_migration_import_precondition_test.dart
```

Capability evidence that execution must collect before closure:

```bash
flutter test test/features/account_migration/application/migration_database_snapshot_exporter_test.dart --plain-name "SQLCipher export capability"
flutter test test/features/account_migration/application/migration_database_import_staging_test.dart --plain-name "opens staged SQLCipher database with staged key"
```

If those names cannot be implemented as host tests because the SQLCipher plugin is target-bound, execution must record the exact target-specific command used, such as:

```bash
FLUTTER_DEVICE_ID=macos flutter test test/features/account_migration/application/migration_database_snapshot_exporter_test.dart --plain-name "SQLCipher export capability"
```

Named/host gates:

```bash
dart format lib/features/account_migration test/features/account_migration
git diff --check
./scripts/run_test_gates.sh completeness-check
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
```

Optional breadth only if execution extracts shared DB migration/version wiring:

```bash
./scripts/run_test_gates.sh core-host-all --only test/core/database/integration/full_migration_chain_test.dart
```

Do not add `$run-flutter-reliability-sims` closure for MIG-004. Simulator and multi-device evidence remains assigned to later transfer/cutover/runtime/final acceptance sessions.

## known-failure interpretation

- Treat failures in the new MIG-004 tests, DB opener, migration chain, secure-storage staging/cleanup, identity repository, and import-precondition tests as session-caused unless a focused pre-change rerun proves the same failure already existed.
- A plain `./scripts/run_test_gates.sh baseline` failure caused only by multiple attached devices/no selected target is an environment/device-selection failure; retry with `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` before classifying behavior red.
- Existing macOS build warnings, deployment-target warnings, or `Failed to foreground app; open returned 1` are not blockers if the gate exits green, matching prior MIG-003 gate interpretation.
- SQLCipher capability absence on host is not a pass. If real export/open/cipher metadata cannot be proven on any supported target in this session, mark execution evidence-gated and do not call MIG-004 closed.
- Dirty worktree files from MIG-001 through MIG-003 are baseline state for this planning session. Do not revert or attribute them to MIG-004 unless execution edits them.

## done criteria

- Direct red tests are added first and fail for missing MIG-004 behavior before production implementation.
- A SQLCipher snapshot/export primitive is implemented or an equivalent primitive is proven, with real capability evidence recorded.
- Manifest contains protocol/app/min-importer data, DB version `74`, SQLCipher metadata/policy, checksum, schema hash, and generated table/column inventory.
- Staged import opens only with staged MIG-003 `db_encryption_key` and cannot generate/persist a new active key or active empty DB.
- Import validation rejects torn snapshots, wrong keys, unsupported versions, checksum mismatch, schema mismatch, integrity failure, missing identity row, non-null identity secret columns, and missing staged required secrets.
- Identity verification confirms DB secret columns remain `NULL` and required staged secure-storage identity/DB/ML-KEM secrets are available before `secrets_migrated` promotion.
- Cleanup deletes staged DB artifacts and SQLite sidecars while preserving active DB, active secure-storage values, and device-local authority unless explicit later erase/reset handles them.
- Existing normal SQLCipher open, migration-chain, identity loading, and MIG-003 staging/cleanup tests still pass.
- Source proposal and test inventory are updated for MIG-004 evidence/residuals; gate definitions/script are updated only if new test classification requires it.
- `./scripts/run_test_gates.sh completeness-check`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, and `graphify update .` pass after implementation edits.

Checklist ledger:

| Requirement | Done-state classification |
| --- | --- |
| SQLCipher consistent snapshot/export | Covered by exporter tests and real capability evidence. |
| Schema/app version manifest | Covered by manifest tests. |
| SQLCipher cipher parameter policy | Covered by metadata/pinned-PRAGMA/cipher-migrate/rejection tests plus capability evidence. |
| DB import staging/open verification | Covered by staging tests using MIG-003 staged DB key. |
| Imported identity-row null-secret verification tied to staged secure-storage secrets | Covered by import validator tests and MIG-003 staging dependency. |
| DB checksum/schema compatibility | Covered by manifest/checksum/schema/integrity tests. |
| Rollback/cleanup boundaries | Covered by DB artifact cleanup tests plus MIG-003 failed-import cleanup integration. |

## scope guard

Non-goals for MIG-004:

- No media, avatars, post media, app documents, file root scanning, file checksums, native storage preflight, or non-critical cache classification.
- No group device identity migration, retained group-key window proof, group/NSE notification-preview continuity, or group delivery semantics beyond schema rows surviving DB export/import.
- No local-network transfer, segmented encryption, resumable chunks, WiFi discovery, relay/cloud decisions, or transport protocol.
- No durable cutover, server lease cleanup, old-phone runtime shutdown, push/rendezvous unregister, or final active-device authority transition.
- No pending-work ownership migration, retry queue migration, upload queue migration, or send/inbox pause behavior.
- No user-facing journey UI, progress UI, wake-lock behavior, erase/reset UI, or migrated-out UX.
- No final acceptance or simulator/device journey claims.
- No broad database architecture rewrite, generic backup framework, raw SQL abstraction layer, or migration-order refactor beyond a tiny reusable current DB version/migration source if execution proves it is necessary.

Overengineering indicators: adding a new storage engine, changing normal app startup DB semantics, replacing helper repositories, bundling files/media/group validation, or requiring network/cutover state to validate a staged DB.

## accepted differences / intentionally out of scope

- MIG-004 consumes MIG-003 staged secure-storage contracts; it does not re-enumerate keychain values or prove the full secure-storage export payload contains every primary/shared key.
- Host tests can prove DB and staged-secret logic, but real iOS Keychain lock/reboot/iCloud/app-restore behavior remains later device/simulator acceptance.
- Full ML-KEM public/secret cryptographic challenge is included only if an existing bridge-backed primitive can support it without expanding scope. If not, MIG-004 must record a residual proof gap and still prove staged-secret presence/null DB columns; final cryptographic acceptance remains later.
- Database row survival across schema version `74` is in scope; rendering the migrated UI, media files, posts/media decryption, group message decryption, notification previews, and pending jobs are later sessions.
- Old-phone final-export quiescing across sends/inbox/files is out of scope. MIG-004 provides a DB snapshot primitive that later cutover/final-export sessions call after they pause mutable account activity.

## dependency impact

- MIG-005 depends on MIG-004 manifest/checksum/schema outputs before adding media/app-owned file manifests.
- MIG-006 depends on DB row survival and schema inventory before proving group device identity and NSE preview continuity.
- MIG-007 depends on the exported DB artifact/manifest shape before transporting it.
- MIG-008 depends on staged import/open verification before durable new-active cutover can be safe.
- MIG-010 depends on DB schema inventory and row survival before pending-work ownership migration.
- MIG-012 final acceptance depends on MIG-004 evidence but must add device/simulator, transfer, cutover, UI, and lifecycle proof.

If MIG-004 becomes evidence-gated because SQLCipher export/open capability cannot be proven, downstream MIG-005 through MIG-012 should not proceed beyond planning against a provisional DB bundle contract.

## docs-to-update contract

After implementation evidence, update only current docs needed for durable project state:

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`: rows for SQLCipher export consistency, schema/app version manifest, cipher parameter policy, DB key-before-open ordering, checksum/schema compatibility, identity null-secret/staged-secret verification, and residuals for media/group/transfer/cutover/final acceptance.
- `Test-Flight-Improv/codebase-test-inventory.md`: new MIG-004 account-migration DB tests and any core DB tests added/changed.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`: only if completeness-check shows a new file needs explicit classification.
- Do not update the session breakdown to `closed` during implementation planning or coding. Closure status belongs to the later closure audit step after accepted execution/QA evidence.

## reviewer / arbiter stop rule

Reviewer must answer whether this plan is sufficient as-is, sufficient with adjustments, or insufficient; must check exact checklist coverage, direct tests, SQLCipher capability evidence, simulator-gate need, source-of-truth correctness, hidden media/group/transfer/cutover scope, and stale assumptions from the dirty MIG-001 through MIG-003 worktree.

Arbiter must classify findings as structural blockers, incremental details, or accepted differences. Structural blockers include missing checklist proof, fake-only SQLCipher proof, missing DB-key-before-open ordering, missing closure bar, missing test/gate contract, accidentally including later-session media/group/transfer/cutover/UI work, or omitting the known-failure/evidence-gated interpretation. If structural blockers exist, patch this plan once and run one final reviewer/arbiter pass. If no structural blockers remain, stop and mark this plan `execution-ready`.

## reviewer outcome

Reviewer verdict: sufficient with small adjustments; no structural blocker.

- Missing files/tests/gates: add `migration_database_import_cleanup_test.dart` to the tests/docs list and make formatting/diff-check commands explicit. Patched.
- Stale assumptions: SQLCipher runtime capability is intentionally not assumed; the plan requires real capability evidence and evidence-gated stop behavior.
- Simulator gate need: no `$run-flutter-reliability-sims` gate is required for MIG-004 because the session excludes multi-device transfer, transport, notifications, lifecycle, media rendering, cutover, runtime gates, and final acceptance.
- Overengineering/scope drift: no structural drift after the scope guard; schema row survival is allowed, while media/files/group behavior, transfer, cutover, pending work, UI, and final acceptance remain out of scope.
- Checklist parity: every user-listed MIG-004 item maps to a concrete planned proof or evidence-gated stop condition.

## arbiter outcome

Final planning verdict: execution-ready.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact SQLCipher PRAGMA availability and target command are execution evidence, not planning-time guesses.
- The implementation may choose `quick_check` or `integrity_check`, but must record which stronger practical check was used.

Accepted differences intentionally left unchanged:

- No media/files, group/NSE continuity, transfer, durable cutover, runtime gates, pending-work migration, UI, simulator journey, or final program acceptance in MIG-004.
- Full ML-KEM cryptographic challenge proof remains conditional on an existing bridge-backed primitive; staged-secret presence and null DB columns are mandatory in this session.

## Execution Verdict

Verdict: accepted.

QA mode: spawned execution/QA attempts stalled before trustworthy file-backed verdicts, so the isolated controller completed the remaining implementation verification and closure review locally from repo evidence. Earlier blocked entries remain above as provenance; the final pass resolved the session-caused compile/test fixture blockers and replaced fake-only SQLCipher capability proof with a plugin-registered macOS integration probe.

Blockers: none for MIG-004.

Evidence:

- `flutter test test/features/account_migration/application/migration_database_schema_inventory_test.dart test/features/account_migration/application/migration_database_manifest_test.dart test/features/account_migration/application/migration_database_snapshot_exporter_test.dart test/features/account_migration/application/migration_database_import_staging_test.dart test/features/account_migration/application/migration_database_import_validator_test.dart test/features/account_migration/application/migration_database_import_cleanup_test.dart` passed with `+12 ~1`; the skipped case is the host/unit SQLCipher capability probe, now covered by `integration_test/migration_database_sqlcipher_capability_test.dart`.
- `flutter test -d macos integration_test/migration_database_sqlcipher_capability_test.dart` passed, proving plugin-registered SQLCipher open/export capability on a supported repo target. macOS emitted existing deployment-target/linker warnings and `Failed to foreground app; open returned 1`, but the test exited green.
- `flutter test test/core/database/encrypted_db_opener_test.dart test/core/database/integration/full_migration_chain_test.dart test/core/secure_storage/migrate_secrets_to_secure_storage_test.dart test/features/identity/domain/repositories/identity_repository_impl_test.dart test/features/account_migration/application/migration_secure_storage_staging_test.dart test/features/account_migration/application/migration_secure_storage_cleanup_test.dart test/features/account_migration/application/account_migration_import_precondition_test.dart` passed.
- `dart format lib/core/database/app_database_version.dart lib/main.dart lib/features/account_migration test/features/account_migration integration_test/migration_database_sqlcipher_capability_test.dart` passed with no file changes.
- `git diff --check` passed.
- `./scripts/run_test_gates.sh completeness-check` passed with `789/789 test files classified`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed.
- `graphify update .` passed after code/doc changes; it rebuilt `graphify-out/graph.json` and `GRAPH_REPORT.md`, skipped oversized HTML visualization, and reported the non-blocking graphify skill/package version warning.

Accepted residuals: full bundle exporter/importer consumption by transfer/cutover flows, media/app-owned files, group/NSE continuity, segmented transfer, durable cutover, migrated-out runtime gates, pending-work ownership, journey UI, simulator/device final acceptance, and final program closure remain explicitly assigned to MIG-005 through MIG-012. Full bridge-backed ML-KEM challenge proof remains a later cryptographic acceptance residual because this session proves staged secret presence and null DB secret columns but does not add a new bridge primitive.

## Closure Progress

- 2026-06-07 00:57:14 CEST | Role: Completion Auditor completed | Files inspected/touched: MIG-004 implementation files, direct tests, macOS SQLCipher integration capability probe, source proposal evidence rows, codebase test inventory, gate definitions, gate script classification, this plan, breakdown ledger, and graphify output. | Command/result: verified the implementation covers schema inventory/hash, manifest compatibility, SQLCipher snapshot/export adapter and capability proof, staged DB open from MIG-003 staged DB key, checksum/schema/integrity validation, identity null-secret and staged-secret verification, and staged artifact cleanup. | Decision/blocker: closure classification is `closed` for MIG-004 only; no session blockers remain.
- 2026-06-07 00:57:14 CEST | Role: Closure Writer completed | Files inspected/touched: this plan and `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`. | Command/result: recorded the final execution verdict, gate evidence, accepted residuals, and breakdown status delta. | Decision/blocker: no blocker; source proposal and inventory docs already carry the MIG-004 coverage/classification updates from execution.
- 2026-06-07 00:57:14 CEST | Role: Closure Reviewer completed | Files inspected/touched: this plan's verdict/closure progress, breakdown controller progress/session ledger/closure deltas, and source proposal MIG-004 evidence/residual wording. | Command/result: reviewed closure updates for overclaiming, stale blocked-state wording, fake-only SQLCipher proof, and final-verdict drift. | Decision/blocker: closure docs accepted; MIG-004 is closed for the session only, MIG-005 through MIG-012 remain pending, and no final program verdict is written.
