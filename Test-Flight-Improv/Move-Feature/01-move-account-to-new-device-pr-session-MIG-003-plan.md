Status: executed-accepted

# MIG-003 Plan: Secure-storage registry, staging, and cleanup

## Planning Progress

- 2026-06-06 23:06:38 CEST | Role: Arbiter completed | Files inspected since last update: Reviewer findings and existing accepted-differences sections in this plan. | Decision/blocker: No structural blockers remain; accepted differences are documented and incremental details do not block execution. | Next action: Hand this exact MIG-003 plan to implementation execution; do not broaden into later Move Account sessions.
- 2026-06-06 23:06:13 CEST | Role: Arbiter started | Files inspected since last update: Reviewer findings in this plan. | Decision/blocker: No reviewer structural blocker is currently recorded; Arbiter will classify findings before final readiness. | Next action: Classify structural blockers, incremental details, and accepted differences, then update this artifact's final status.
- 2026-06-06 23:05:35 CEST | Role: Reviewer completed | Files inspected since last update: current MIG-003 plan, MIG-003 breakdown gate notes, source proposal simulator acceptance section, and `test-gate-definitions.md` push decrypt simulator smoke definition. | Decision/blocker: Reviewer finds the plan sufficient as-is for MIG-003; no structural blocker. Simulator/device proof is residual because this session does not touch NSE payload shape, simulator injection scripts, OS delivery, transfer, cutover, or final acceptance. | Next action: Run Arbiter to classify the reviewer findings and either mark execution-ready or persist a blocker.
- 2026-06-06 23:04:40 CEST | Role: Reviewer started | Files inspected since last update: current MIG-003 plan, MIG-003 breakdown row, source proposal secure-storage requirements, gate-definition excerpts for baseline/completeness/simulator gates, and dirty worktree status. | Decision/blocker: Reviewer is checking plan sufficiency only; no implementation or renewed evidence collection is in scope. | Next action: Verify mandatory sections, checklist ledger, closure bar, tests/gates, docs, simulator-gate need, stale assumptions, and scope guard.
- 2026-06-06 23:02:57 CEST | Role: Controller recovery / Reviewer handoff | Files inspected since last update: active process table, terminated stale MIG-003 planner process, and current plan artifact. | Decision/blocker: No MIG-003 planning blocker. The Planner draft is present in this file; the stale parent was stopped after conflicting heartbeat patches, and remaining planning work is Reviewer then Arbiter against the current draft. | Next action: Launch fresh reviewer/arbiter planning child without redoing evidence collection or implementation.

## Execution Progress

- 2026-06-06 23:13:34 CEST | Phase: red-test implementation started | Files inspected/touched: secure-storage interfaces, Flutter secure store, startup secrets migration, secret reference helpers, identity/group repositories, settings preference models/tests, push token store, account-migration authority repository/tests, fake secure store. | Command/result: targeted `sed`/`rg` inspection completed; no production edits yet. | Decision/blocker: point-operation stores and current fake-store style are sufficient; no platform enumeration or broad secure-store interface change needed. | Next action: add MIG-003 red tests for registry, DB-reference collection, staging/promotion, cleanup, source audit, and push-token storage policy.
- 2026-06-06 23:10:38 CEST | Phase: Executor implementation discovery started | Files inspected/touched: implementation/graphify skill docs, full MIG-003 plan, MIG-003 breakdown row, dirty worktree status, scoped graphify query. | Command/result: `graphify query "MIG-003 secure storage migration registry staging cleanup secrets_migrated sentinel account migration secure keys iOS shared access group" --budget 2000` completed with weak scoped context; `git status --short` shows expected pre-existing MIG/account-migration dirty work plus this plan. | Decision/blocker: no blocker; current plan and targeted source files are authoritative. | Next action: inspect existing secure storage, identity/group/settings/push/account-migration seams, then add MIG-003 tests and narrow production helpers.
- 2026-06-06 23:09:16 CEST | Phase: contract extracted | Files inspected/touched: this MIG-003 plan, session breakdown MIG-003 row, `Test-Flight-Improv/test-gate-definitions.md`, dirty worktree status, scoped graphify query. | Command/result: `graphify query "MIG-003 secure storage migration registry staging cleanup secrets_migrated sentinel account migration secure keys iOS shared access group"` completed with weak scoped context; current plan/source code remain authoritative. | Decision/blocker: execution contract is concrete and bounded to MIG-003 secure-storage registry, DB-reference collection, staging/promotion, cleanup, push-token classification, and docs; no blocker. | Next action: spawn fresh Executor agent with model `gpt-5.5` and reasoning_effort `xhigh`.
- 2026-06-06 23:10:08 CEST | Phase: Executor spawned/running | Files inspected/touched: this plan file. | Command/result: spawned Executor agent `019e9ec5-6c85-74f1-84ed-53483fb0b14d` (`Turing`) with prompt requesting model `gpt-5.5` and reasoning_effort `xhigh`. | Decision/blocker: no blocker; waiting for file-backed implementation, direct test, gate, doc, and graphify evidence. | Next action: bounded wait for Executor result, then spawn separate QA Reviewer if trustworthy evidence is returned.
- 2026-06-06 23:14:45 CEST | Phase: Executor spawn/no-progress recovery | Files inspected/touched: this plan file, current dirty status, account-migration file lists. | Command/result: bounded waits for Executor `019e9ec5-6c85-74f1-84ed-53483fb0b14d` timed out; child was closed while still running after plan-heartbeat-only progress and no trustworthy final code/test/doc evidence. | Decision/blocker: classify nested Executor as `spawn_or_tool_failure`; local sequential fallback is allowed because this controller is already isolated, the plan is concrete, and no child code/test/doc partials created hidden state ambiguity. | Next action: perform Executor responsibilities locally, then run separate local QA pass or spawn QA if local fallback reaches implementation evidence.
- 2026-06-06 23:20:15 CEST | Phase: red-test evidence captured | Files inspected/touched: new MIG-003 account-migration secure-storage tests and push-token infrastructure test. | Command/result: `flutter test test/features/account_migration/application/migration_secure_storage_registry_test.dart` failed at compile load because `migration_secure_storage_registry.dart` and `migration_secure_storage_key.dart` do not exist. | Decision/blocker: expected RED state for missing MIG-003 registry/model APIs; not a blocker. | Next action: implement narrow registry, reference collector, staging/promotion, cleanup, and push-token key constants to satisfy tests.
- 2026-06-06 23:23:13 CEST | Phase: local Executor implementation checkpoint | Files inspected/touched: added `migration_secure_storage_key.dart`, registry, reference collector, staging, cleanup, six new direct test files, and public push-token secure-storage key constants; ran `dart format` on touched Dart files. | Command/result: implementation compiled syntactically through formatter; direct tests not rerun yet after production landing. | Decision/blocker: no blocker; implementation remains within MIG-003 scope and does not touch DB snapshot/import, transfer, cutover, runtime gates, or UI. | Next action: run required new direct tests as fast structural validation, then affected existing direct tests.
- 2026-06-06 23:24:23 CEST | Phase: new direct tests passed | Files inspected/touched: new registry, reference collector, staging, cleanup, source audit, and push-token tests. | Command/result: passed `flutter test test/features/account_migration/application/migration_secure_storage_registry_test.dart`; passed `flutter test test/features/account_migration/application/migration_secure_storage_reference_collector_test.dart`; passed `flutter test test/features/account_migration/application/migration_secure_storage_staging_test.dart`; passed `flutter test test/features/account_migration/application/migration_secure_storage_cleanup_test.dart`; passed `flutter test test/features/account_migration/application/migration_secure_storage_source_audit_test.dart`; passed `flutter test test/features/push/infrastructure/push_token_store_impl_test.dart`. | Decision/blocker: no blocker; fast structural validation for new MIG-003 seams is green. | Next action: run required affected existing direct tests.
- 2026-06-06 23:26:00 CEST | Phase: affected existing direct tests passed | Files inspected/touched: existing secure-storage, identity, group, settings, and account-authority direct suites. | Command/result: passed `flutter test test/core/secure_storage/migrate_secrets_to_secure_storage_test.dart`; passed `flutter test test/core/secure_storage/flutter_secure_key_store_test.dart`; passed `flutter test test/features/identity/domain/repositories/identity_repository_impl_test.dart`; passed `flutter test test/features/groups/domain/repositories/group_repository_impl_test.dart`; passed `flutter test test/features/settings/application/background_preference_use_cases_test.dart`; passed `flutter test test/features/settings/application/image_quality_preference_use_cases_test.dart`; passed `flutter test test/features/settings/application/video_quality_preference_use_cases_test.dart`; passed `flutter test test/features/account_migration/application/account_migration_authority_repository_test.dart`. | Decision/blocker: no blocker; existing normal startup, identity, group, preference, and authority behavior remains green. | Next action: update required source proposal and codebase test inventory docs, then run baseline gate.
- 2026-06-06 23:28:40 CEST | Phase: docs updated / gate triage starting | Files inspected/touched: source proposal, codebase test inventory, and `test-gate-definitions.md`. | Command/result: source proposal records MIG-003 host coverage plus later exporter/importer/device residuals; test inventory now lists five new account-migration tests and one push infrastructure test; gate definitions classify the new push infrastructure test as direct non-named-gate coverage. | Decision/blocker: because `test-gate-definitions.md` changed, conditional `./scripts/run_test_gates.sh completeness-check` is required before baseline. | Next action: run `./scripts/run_test_gates.sh completeness-check`, then required baseline gate.
- 2026-06-06 23:29:07 CEST | Phase: gate failure triage | Files inspected/touched: this plan file; `test-gate-definitions.md` just changed. | Command/result: `./scripts/run_test_gates.sh completeness-check` failed with `781/782 test files classified`; unmatched file: `test/features/push/infrastructure/push_token_store_impl_test.dart`; no log redirection. | Decision/blocker: classification state `pending_triage`; likely classification wording did not satisfy the completeness script. | Next action: inspect `scripts/run_test_gates.sh` completeness classifier with `rg -n "completeness|classified|Unmatched|test-gate-definitions" scripts Test-Flight-Improv`.
- 2026-06-06 23:29:52 CEST | Phase: completeness-check passed / baseline starting | Files inspected/touched: `scripts/run_test_gates.sh`, `test-gate-definitions.md`, this plan file. | Command/result: classified `test/features/push/infrastructure/push_token_store_impl_test.dart` in `OUT_OF_GATE_TESTS`; rerun `./scripts/run_test_gates.sh completeness-check` passed with `782/782 test files classified`. | Decision/blocker: prior completeness failure was session-caused missing executable classification and is fixed; no blocker. | Next action: run required named gate `./scripts/run_test_gates.sh baseline`.
- 2026-06-06 23:31:37 CEST | Phase: baseline gate failure triage | Files inspected/touched: baseline gate output. | Command/result: `./scripts/run_test_gates.sh baseline` ran host baseline tests to `All tests passed!` then failed when launching integration-test entries because Flutter reported multiple attached devices and no selected target; no log redirection. | Decision/blocker: classification state `environment/device-selection`; this matches the plan's known-failure interpretation and requires retry with explicit host device. | Next action: run focused retry `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`.
- 2026-06-06 23:34:28 CEST | Phase: local Executor complete / graph update starting | Files inspected/touched: MIG-003 code, tests, docs, gate script and definitions; baseline gate output. | Command/result: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed after the initial device-selection failure; macOS integration build emitted deployment-target/object-version warnings and `Failed to foreground app; open returned 1`, but loading-states and posts integration entries passed. | Decision/blocker: no Executor blocker remains; all required direct tests, conditional completeness-check, and required baseline evidence are green with the first baseline failure classified as environment/device-selection. | Next action: run `graphify update .`, inspect final diff/status, then start the QA Reviewer role boundary.
- 2026-06-06 23:39:35 CEST | Phase: graph update complete / QA Reviewer handoff | Files inspected/touched: `graphify-out/graph.json`, `graphify-out/GRAPH_REPORT.md`, current git status, and this plan file. | Command/result: `graphify update .` completed successfully after code changes; output reported graphify skill/package version warning `0.8.32` vs `0.8.33`, rebuilt 91,556 nodes, 161,829 edges, and 4,043 communities, and skipped `graph.html` as too large. | Decision/blocker: no graphify blocker; dirty worktree still includes expected prior MIG-001/MIG-002 changes plus MIG-003 code/docs/tests. | Next action: spawn fresh QA Reviewer agent with requested model `gpt-5.5` and reasoning_effort `xhigh`.
- 2026-06-06 23:39:35 CEST | Phase: QA Reviewer spawned/running | Files inspected/touched: this plan file. | Command/result: preparing fresh QA Reviewer prompt against exact MIG-003 plan, implementation evidence, direct tests, completeness-check, baseline retry, docs, and graphify status. | Decision/blocker: no blocker; QA must verify scope adherence and closure criteria before final verdict. | Next action: bounded wait for QA Reviewer verdict, then run fix loop only if QA reports MIG-003 blockers.
- 2026-06-06 23:43:57 CEST | Phase: QA Reviewer spawn/no-progress recovery | Files inspected/touched: this plan file and current dirty status. | Command/result: QA Reviewer agent `019e9ee1-6293-7f31-a3b4-946ee58e8357` (`Epicurus`) timed out without a file-backed verdict and was closed while still running. | Decision/blocker: classify nested QA as `spawn_or_tool_failure`; local sequential QA fallback is allowed under the same already-isolated controller because Executor evidence is file-backed and complete. | Next action: run local QA review against MIG-003 code, tests, docs, gates, and scope guard, then record final verdict.
- 2026-06-06 23:45:28 CEST | Phase: local QA completed / final verdict | Files inspected/touched: secure-storage model, registry, reference collector, staging, cleanup, push-token store, new MIG-003 tests, source proposal, codebase test inventory, gate definitions, gate script classification, and current status. | Command/result: local QA reviewed implemented behavior against done criteria and recorded direct/gate evidence; no additional production/test code changes were needed. | Decision/blocker: final execution verdict `accepted`; no MIG-003 blockers. Residual exporter/importer integration, real iOS Keychain lifecycle, cutover/runtime push leases, UI, simulator/device acceptance, and final journey proof remain later-session scope per accepted differences. | Next action: hand final execution result back to the session pipeline.

## Execution Verdict

Verdict: accepted.

QA mode: spawned QA Reviewer `019e9ee1-6293-7f31-a3b4-946ee58e8357` was attempted with requested model `gpt-5.5` and reasoning_effort `xhigh`, then closed after no file-backed verdict. Local sequential QA fallback was used under the skill fallback rule and recorded above.

Blockers: none.

Residuals: full bundle export/import consumption, imported secret-to-identity verification, real iOS Keychain lock/reboot/iCloud behavior, durable cutover, migrated-out runtime gates, server push/rendezvous lease cleanup, journey UI, simulator/device final acceptance, and final program closure remain intentionally out of MIG-003 scope.

## Closure Progress

- 2026-06-06 23:49:13 CEST | Role: Closure Controller fallback recorded | Files inspected/touched: this MIG-003 plan, breakdown ledger, source proposal coverage rows, codebase test inventory, gate definitions, MIG-003 secure-storage implementation files/tests, current dirty status, and scoped graphify query. | Command/result: real spawned closure roles were not used because the available `multi_agent_v1.spawn_agent` tool does not expose `model` or `reasoning_effort` fields, so the required `model: gpt-5.5` and `reasoning_effort: xhigh` role-agent settings could not be guaranteed. | Decision/blocker: no blocker; simulate Completion Auditor, Closure Writer, and Closure Reviewer sequentially in this controller and record the fallback here.
- 2026-06-06 23:49:13 CEST | Role: Completion Auditor completed | Files inspected/touched: `lib/features/account_migration/domain/models/migration_secure_storage_key.dart`, `lib/features/account_migration/application/migration_secure_storage_registry.dart`, `migration_secure_storage_reference_collector.dart`, `migration_secure_storage_staging.dart`, `migration_secure_storage_cleanup.dart`, `lib/features/push/infrastructure/push_token_store_impl.dart`, new MIG-003 test files, source proposal evidence rows, codebase test inventory, gate definitions, and the accepted execution evidence above. | Command/result: verified the repo contains the explicit fixed/dynamic secure-storage registry, DB-reference collector, session-scoped staging keys, required-secret promotion validation, promoted-key rollback journal, registry-driven cleanup, push-token clear/regenerate constants/tests, source proposal coverage/residual rows, inventory entries, and out-of-gate push infrastructure classification. Existing accepted evidence records all required new direct tests, affected direct tests, `./scripts/run_test_gates.sh completeness-check`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, and `graphify update .` as passed. | Decision/blocker: closure classification is `closed` for MIG-003 only. No MIG-003 blockers or stale-doc findings found; remaining export/import consumption, secret-to-identity verification, iOS Keychain lifecycle/device proof, cutover/runtime gates, UI, simulator acceptance, and final program closure are later-session scope, not MIG-003 reopen items.
- 2026-06-06 23:49:13 CEST | Role: Closure Writer completed | Files inspected/touched: this plan and `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`. | Command/result: added this closure progress section and updated the breakdown ledger to mark MIG-003 closed for the session only, with closure evidence, accepted differences, residual-only wording, and no final program verdict. | Decision/blocker: no blocker; source proposal, codebase test inventory, and gate definitions already carry the execution-time MIG-003 evidence and remain accurate as durable current-doc artifacts.
- 2026-06-06 23:50:49 CEST | Role: Closure Reviewer completed | Files inspected/touched: this plan's closure progress, the breakdown controller progress/session ledger/closure deltas, and source proposal MIG-003 coverage/residual rows. | Command/result: reviewed closure updates for accuracy, stale wording, overclaiming, accidental product-scope reopen, and missing residual notes; verified MIG-003 is closed only for the host-side secure-storage registry/staging/promotion/cleanup/push-token policy closure bar, MIG-004 through MIG-012 remain pending, and no final program verdict was added. | Decision/blocker: closure docs accepted; no blockers.

## real scope

MIG-003 builds only the secure-storage migration registry, staging, promotion, and cleanup layer:

- Add a migration registry for app-owned secure-storage keys across the primary app keychain and iOS shared access group `group.com.mknoon.app.share`.
- Use an explicit fixed-key registry merged with DB-discovered `secure:` references. Current `SecureKeyStore` and `FlutterSecureKeyStore` expose point `read`/`write`/`delete`/`containsKey` only, so do not plan platform namespace enumeration unless execution proves it is already safely available.
- Classify every current fixed key with an explicit policy: `db_encryption_key`, `identity_private_key`, `identity_mnemonic12`, `identity_ml_kem_secret_key`, `secrets_migrated`, `background_preference`, `image_quality_preference`, `video_quality_preference`, `push_fcm_token`, `push_fcm_platform`, and `account_migration_authority:v1`.
- Classify DB-discovered primary-store references such as `secure:group_key_material:<encodedGroupId>:<generation>` and `secure:media_attachment_encryption_key:<attachmentId>`.
- Classify iOS shared-store mirrors: `identity_ml_kem_secret_key` and committed group mirrors `group_key:<rawGroupId>:<generation>`.
- Define staging keys under a migration-session namespace so imported secure values never overwrite active keys until promotion.
- Add promotion rules, rollback metadata, registry-driven account erase/reset, success cleanup, cancellation cleanup, and failed-import cleanup for both primary and shared stores.
- Add migration-specific sentinel ordering rules so `secrets_migrated` is not set for an import until required staged/promoted secure secrets are present and ready.
- Preserve current normal startup secure-storage migration behavior outside account migration.

This session must not implement SQLCipher snapshot/import, media/app-owned file transfer, group device identity or push-preview continuity, local network transfer, durable old/new cutover, migrated-out runtime gates, pending-work migration, journey UI, simulator/device final acceptance, or final program closure.

## closure bar

MIG-003 is good enough when host-side tests prove the checklist below. Device-specific iOS Keychain accessibility, lock/reboot, iCloud Backup, and iCloud Keychain behavior remain residual evidence for later iOS device/simulator acceptance because fake key stores and constructor tests cannot prove OS persistence semantics.

| Checklist item | Required proof in this session |
| --- | --- |
| Primary app keychain registry | Registry includes every current fixed primary key and DB-discovered primary `secure:` reference category with policy and criticality. |
| iOS shared access-group registry | Registry includes shared `identity_ml_kem_secret_key` and `group_key:<rawGroupId>:<generation>` mirror categories, scoped to `group.com.mknoon.app.share`. |
| Fixed keys classified | Tests assert policy for DB key, identity secrets, sentinel, app preferences, push-token keys, and account authority. |
| DB-discovered `secure:` references | Tests derive references from representative group/media DB rows or row fixtures and merge them with fixed registry entries without relying on rows alone. |
| App preferences | `background_preference`, `image_quality_preference`, and `video_quality_preference` are explicitly migrated or intentionally defaulted; they cannot disappear only because no row references them. |
| Push-token material | `push_fcm_token` and `push_fcm_platform` are device-bound, not migrated as active state, and are cleared/ignored so fresh registration is forced later. |
| Identity secrets | Primary identity secrets migrate as required critical keys; shared ML-KEM mirror is classified separately. |
| Group key references | Primary committed/pending group key material references are discovered from DB rows; committed shared mirrors are addressed by raw group ID/generation. Pending drafts are primary-store only under the current model. |
| Device-local authority | `account_migration_authority:v1` is intentionally device-local, excluded from export/import payloads, and included only in explicit local erase/reset policy. |
| Staging namespace | Staging writes use session-scoped non-active keys and do not overwrite active primary/shared keys. |
| Promotion rules | Promotion requires all required staged keys for the import phase, writes active keys in deterministic order, tracks promoted keys, and can clean already-promoted values if commit fails. |
| Registry-driven erase/reset | Account erase/reset deletes every registry-owned app secret in both stores, including shared mirrors; device-local authority is cleared only for explicit local erase/reset. |
| Success/cancel/failed cleanup | Success cleanup removes staging keys; cancellation removes staging keys without touching active keys; failed-import cleanup removes staging and any already-promoted keys recorded for that session. |
| Sentinel ordering | `secrets_migrated` cannot be staged/promoted as active `true` until `db_encryption_key`, required identity secrets, and required ML-KEM state are present according to the registry/promotion validator. |

## source of truth

- Session boundary: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`, MIG-003 lines 136-146.
- Product/security source: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`, especially fixed secure keys, registry/enumeration requirements, cleanup, push-token policy, staging, iCloud/keychain residuals, and sentinel ordering.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- Current code/tests win over stale prose. Important evidence files include `lib/core/secure_storage/secure_key_store.dart`, `lib/core/secure_storage/flutter_secure_key_store.dart`, `lib/core/secure_storage/migrate_secrets_to_secure_storage.dart`, `lib/core/secure_storage/secret_storage_references.dart`, `lib/core/database/encrypted_db_opener.dart`, `lib/features/identity/domain/repositories/identity_repository_impl.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/features/push/infrastructure/push_token_store_impl.dart`, settings preference models/use cases, and MIG-001 account-migration authority files.
- `graphify query "MIG-003 secure storage migration registry staging cleanup secrets_migrated sentinel account migration secure keys iOS shared access group"` was run as required, but returned weak scoped context. Targeted docs and code are authoritative for this plan.

Dirty-worktree note: planning observed existing dirty/untracked changes in the source proposal, codebase test inventory, identity/QR/account-migration code and tests, MIG-001/MIG-002 plan files, this MIG-003 plan file, and the session breakdown. Treat those as existing user/controller work; do not revert them.

## session classification

implementation-ready

The planned implementation is narrow and host-testable. It depends on MIG-001's device-local authority key existing, which is present in the current worktree. It does not require simulator closure because it does not exercise OS lifecycle, transport, notification delivery, or a two-device migration journey.

## exact problem statement

The app stores account-critical data in secure storage but has no complete migration registry. `SecureKeyStore` only supports point operations, so a migration exporter cannot discover all app-owned keychain data by enumeration. Some required keys are fixed and not row-referenced, while others are stored as DB row `secure:` references. iOS notification preview support mirrors selected material into a separate shared access group with different key names. Existing cleanup paths are local and feature-specific, not migration-registry driven.

Without MIG-003, a migration could import a database whose DB key, identity secrets, group keys, media keys, app preferences, or shared mirrors are missing; overwrite active secure-storage values during staging; leave old staged/promoted secrets after cancellation or failed import; copy old push-token material as active state; or set `secrets_migrated` in an order that makes an imported identity unloadable.

## files and repos to inspect next

Production files likely to add:

- `lib/features/account_migration/domain/models/migration_secure_storage_key.dart`
- `lib/features/account_migration/application/migration_secure_storage_registry.dart`
- `lib/features/account_migration/application/migration_secure_storage_staging.dart`
- `lib/features/account_migration/application/migration_secure_storage_cleanup.dart`
- `lib/features/account_migration/application/migration_secure_storage_reference_collector.dart`

Production files to inspect/update narrowly:

- `lib/core/secure_storage/secure_key_store.dart`
- `lib/core/secure_storage/flutter_secure_key_store.dart`
- `lib/core/secure_storage/migrate_secrets_to_secure_storage.dart`
- `lib/core/secure_storage/secret_storage_references.dart`
- `lib/core/database/encrypted_db_opener.dart`
- `lib/features/identity/domain/repositories/identity_repository_impl.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/features/push/infrastructure/push_token_store_impl.dart`
- `lib/features/settings/domain/models/background_preference.dart`
- `lib/features/settings/domain/models/image_quality_preference.dart`
- `lib/features/account_migration/application/account_migration_authority_repository_impl.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- group key DB helper files only as needed to collect committed and pending key rows.

Tests and docs:

- New `test/features/account_migration/application/*secure_storage*_test.dart`
- New `test/features/push/infrastructure/push_token_store_impl_test.dart` if push-token policy needs direct infrastructure coverage.
- Existing direct tests listed in the gate section.
- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
- `Test-Flight-Improv/codebase-test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md` only if new tests require classification.

## existing tests covering this area

- `test/core/secure_storage/migrate_secrets_to_secure_storage_test.dart` proves the current identity DB-to-secure-store migration and sentinel behavior for normal startup, but not migration import ordering.
- `test/core/secure_storage/flutter_secure_key_store_test.dart` proves `FlutterSecureKeyStore` defaults to the app store and can be constructed with `group.com.mknoon.app.share`; it does not prove OS keychain semantics.
- `test/features/identity/domain/repositories/identity_repository_impl_test.dart` proves identity secrets are read/written in primary secure storage and ML-KEM secret mirroring to the shared store.
- `test/features/groups/domain/repositories/group_repository_impl_test.dart` proves group key material is wrapped under `secure:group_key_material:<encodedGroupId>:<generation>`, retained generations are mirrored to shared `group_key:<rawGroupId>:<generation>`, missing material fails closed, and group key deletion removes primary/shared keys for known group rows.
- Settings preference tests prove preference key read/write/default behavior.
- MIG-001 tests prove `account_migration_authority:v1` is device-local secure-store state and startup/import preconditions observe it.

Missing today:

- No registry completeness test covers every app-owned fixed secure key.
- No test merges fixed keys with DB-discovered `secure:` references.
- No migration staging/promotion/rollback test protects active keys.
- No registry-driven erase/reset/success/cancel/failed-import cleanup test covers primary and shared stores together.
- No push-token infrastructure test pins the clear/regenerate policy at the storage-key level.
- No import-specific sentinel-ordering proof prevents `secrets_migrated` from being set before imported secrets are ready.

## regression/tests to add first

Add red tests before production changes:

- `test/features/account_migration/application/migration_secure_storage_registry_test.dart`
  - Asserts fixed primary policies for `db_encryption_key`, identity secrets, `secrets_migrated`, settings preferences, push token/platform, and `account_migration_authority:v1`.
  - Asserts shared-store policies for `identity_ml_kem_secret_key` and `group_key:<rawGroupId>:<generation>`.
  - Asserts every fixed key has one of migrate, clear, regenerate, derived-on-promotion, or intentionally-device-local.
- `test/features/account_migration/application/migration_secure_storage_reference_collector_test.dart`
  - Builds representative group/media row fixtures and proves DB-discovered `secure:` references are collected as primary-store keys.
  - Proves primary group key names use encoded group IDs while shared group mirror names use raw group IDs.
  - Proves pending group key rotation drafts are primary-store only unless the production mirror model changes.
- `test/features/account_migration/application/migration_secure_storage_staging_test.dart`
  - Proves staged primary/shared writes use session-scoped staging keys and leave active keys untouched.
  - Proves promotion refuses missing critical staged keys, promotes all required keys deterministically, tracks promoted keys, and can roll back promoted keys for failed import.
  - Proves `secrets_migrated` is not promoted until `db_encryption_key`, `identity_private_key`, `identity_mnemonic12`, and required ML-KEM state are present according to the imported account requirements.
- `test/features/account_migration/application/migration_secure_storage_cleanup_test.dart`
  - Proves account erase/reset uses the registry to delete all active app-owned primary/shared keys.
  - Proves success cleanup deletes staging keys only.
  - Proves cancellation cleanup deletes staging keys and preserves pre-existing active keys.
  - Proves failed-import cleanup deletes staging plus any recorded already-promoted keys in both stores.
- `test/features/account_migration/application/migration_secure_storage_source_audit_test.dart`
  - Scans repo-local secure-store key call sites or central key constants so a new fixed app-owned secure-storage key fails tests unless it is added to the migration registry or explicitly ignored with a reason.
- `test/features/push/infrastructure/push_token_store_impl_test.dart`
  - Pins `push_fcm_token` and `push_fcm_platform` write/read/clear behavior and invalid partial-token cleanup so MIG-003 can safely classify them as device-bound clear/regenerate material.

Then run affected existing direct tests to ensure current identity, group, settings, and secure-storage behavior remains intact.

## step-by-step implementation plan

1. Add migration secure-storage model types for store scope, key category, policy, criticality, and cleanup behavior. Keep them small data objects; do not introduce a broad state-machine framework.
2. Add an explicit fixed-key registry for current app-owned keys. Prefer importing existing public constants where available; if constants are private, either expose narrowly named constants or duplicate them only in the registry with source comments and audit tests.
3. Add DB-reference collection helpers that accept row/provider inputs for secure-reference-bearing records. For this session, use helper abstractions and row fixtures; do not build SQLCipher export/import.
4. Add a combined registry resolver that merges fixed keys and DB-discovered references, deduplicates by store scope plus active key, and emits deterministic ordering for testable cleanup/promotion.
5. Add staging namespace helpers. Use a session-scoped prefix that encodes original store scope and active key so staged primary/shared values cannot collide with active values.
6. Add staging write/read/promote helpers using existing `SecureKeyStore` point operations. Promotion must validate all required keys before writing active keys.
7. Add a promoted-key journal for the migration session so failed-import cleanup can delete active keys already promoted before an error. Keep the journal in secure storage or a migration staging record; do not use the migrated DB bundle.
8. Add registry-driven cleanup helpers for explicit account erase/reset, successful import cleanup, cancellation cleanup, and failed-import cleanup. All helpers must accept both primary and optional shared-store instances.
9. Add import sentinel-ordering validator/helper. It must treat `secrets_migrated` as derived-on-promotion for account migration, not as a blind copied fixed value.
10. Add push-token classification and cleanup. Do not promote the old phone's `push_fcm_token`/`push_fcm_platform` as active new-phone state; clear/ignore them and leave fresh registration to later cutover/startup work.
11. Add the secure-storage source audit test. Keep ignores explicit for dynamic `secure:` reference builders, migration staging keys, test-only fakes, and intentionally device-local authority.
12. Run direct tests first. If production Dart files changed, run `dart format` on touched Dart files and `graphify update .` after implementation.
13. Update docs listed below after tests pass.
14. Stop and replan if execution discovers that real keychain enumeration is mandatory, if DB snapshot/import must be implemented to collect references, or if sentinel ordering cannot be tested without MIG-004 import code.

## risks and edge cases

- Private string constants can drift from the registry. The audit test or central constants must catch new fixed keys.
- Shared group mirror keys use raw group IDs, while primary references use URI-encoded group IDs. Mixing those names would break cleanup or push preview decryption.
- `secrets_migrated` is safe for normal startup migration but dangerous if blindly copied before imported identity secrets are active.
- Failed import after partial promotion must delete already-promoted keys without deleting unrelated pre-existing active keys.
- Cancellation cleanup must not erase an existing active account on a phone where import was blocked or explicit reset was not performed.
- App preference defaults are non-secret but still app-owned secure-store values; losing them silently is a migration completeness bug.
- Push-token values are device-bound and stale across phones. Migrating them as active state can make the old token win until later registration.
- Host fake stores can prove registry logic and dual-store cleanup, but cannot prove iOS Keychain accessibility, lock/reboot readability, backup exclusion, or iCloud behavior.

## exact tests and gates to run

Required new direct tests:

```bash
flutter test test/features/account_migration/application/migration_secure_storage_registry_test.dart
flutter test test/features/account_migration/application/migration_secure_storage_reference_collector_test.dart
flutter test test/features/account_migration/application/migration_secure_storage_staging_test.dart
flutter test test/features/account_migration/application/migration_secure_storage_cleanup_test.dart
flutter test test/features/account_migration/application/migration_secure_storage_source_audit_test.dart
flutter test test/features/push/infrastructure/push_token_store_impl_test.dart
```

Required affected existing direct tests:

```bash
flutter test test/core/secure_storage/migrate_secrets_to_secure_storage_test.dart
flutter test test/core/secure_storage/flutter_secure_key_store_test.dart
flutter test test/features/identity/domain/repositories/identity_repository_impl_test.dart
flutter test test/features/groups/domain/repositories/group_repository_impl_test.dart
flutter test test/features/settings/application/background_preference_use_cases_test.dart
flutter test test/features/settings/application/image_quality_preference_use_cases_test.dart
flutter test test/features/settings/application/video_quality_preference_use_cases_test.dart
flutter test test/features/account_migration/application/account_migration_authority_repository_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh baseline
```

Conditional gates:

```bash
./scripts/run_test_gates.sh completeness-check
```

Run `completeness-check` only if execution updates `Test-Flight-Improv/test-gate-definitions.md` or adds tests outside ordinary feature-local/unit coverage that require gate classification. Run push decrypt simulator dry-run only if execution touches NSE fixture scripts or push decrypt simulator scripts; this plan does not require it.

No `$run-flutter-reliability-sims` command is required for MIG-003. This session does not close multi-device transfer, notification delivery, OS lifecycle, media rendering, migrated-out runtime behavior, or final iOS-to-iOS acceptance.

## known-failure interpretation

- Treat failures in new MIG-003 direct tests as session-caused unless a red-before-green run already recorded the same expected missing-API failure.
- Treat failures in identity/group/settings/secure-storage direct tests as session-caused unless a focused pre-change rerun proves they were already red.
- If `./scripts/run_test_gates.sh baseline` fails because multiple Flutter devices are attached, rerun with an explicit host device such as `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` and record the first failure as environment/device-selection only if the retry passes.
- Do not remove or reclassify existing gate tests to make MIG-003 green. Red named gates require exact failing file/test names and a pre-existing, unrelated, flaky, environment, or session-caused classification.

## done criteria

- Registry data objects and resolver exist for primary and shared stores.
- Fixed-key registry covers all current fixed app-owned secure-storage keys with explicit policies.
- DB-discovered primary `secure:` group/media references merge with fixed keys and are tested.
- Shared iOS ML-KEM and group mirror keys are classified and cleanup-tested.
- Staging keys never overwrite active keys before promotion.
- Promotion validates required staged secrets first and records promoted keys for rollback.
- Account erase/reset, success cleanup, cancellation cleanup, and failed-import cleanup are registry-driven and pass primary/shared no-survivor assertions.
- Push-token keys are clear/regenerate, not migrated as active account state.
- `account_migration_authority:v1` is documented and tested as intentionally device-local, excluded from migration export/import, and only cleared by explicit local erase/reset.
- `secrets_migrated` import promotion is blocked until required secure secrets are staged/promoted and ready.
- Required direct tests and `./scripts/run_test_gates.sh baseline` pass or have exact approved known-failure classifications.
- Proposal/test docs are updated as listed below.

Coverage ledger:

| User-listed MIG-003 requirement | Closure state required |
| --- | --- |
| registry across primary and iOS shared access group | Covered by registry tests and cleanup tests with dual stores |
| fixed keys | Covered by fixed-key registry policy tests |
| DB-discovered `secure:` references | Covered by reference collector tests |
| app preferences | Covered by registry policy plus existing settings tests |
| push-token material | Covered by push-token infrastructure test and registry policy |
| identity secrets | Covered by registry policy plus identity repository tests |
| group key references | Covered by primary/shared naming and reference collector tests |
| intentionally device-local authority | Covered by registry policy plus MIG-001 authority repository test |
| staging namespace behavior | Covered by staging tests |
| promotion rules | Covered by promotion validation/rollback tests |
| registry-driven erase/reset | Covered by cleanup no-survivor tests |
| success/cancel/failed-import cleanup | Covered by cleanup mode tests |
| sentinel ordering | Covered by sentinel promotion-ordering tests |

## scope guard

Non-goals:

- No SQLCipher snapshot/import, database opening of an imported DB, schema manifest, or SQLCipher parameter policy.
- No media/app-owned file copy, checksum, storage preflight, or render proof.
- No group device identity preservation/rebind, key-package continuity, push-preview continuity proof, or multi-epoch group-history acceptance beyond key classification.
- No local-network transfer, QR pairing changes, encryption channel, chunking, resumability, or transport.
- No durable cutover, old-phone migrated-out runtime gates, push/rendezvous unregister, server lease cleanup, or pending-work migration.
- No full journey UI, progress UI, erase UI, simulator/device final acceptance, or final program closure.
- No generic secret manager rewrite or unrelated secure-storage refactor.

Overengineering signals:

- Adding platform keychain namespace enumeration when an explicit registry plus DB references is sufficient.
- Moving normal startup DB opener or identity migration behavior into account migration without a failing MIG-003 regression.
- Introducing a generalized transaction framework instead of a narrow staged-write/promoted-key journal.
- Making fake host tests claim iOS lock/reboot/iCloud behavior.

## accepted differences / intentionally out of scope

- Explicit registry plus DB-discovered references is the planned implementation path; platform keychain enumeration is not required unless execution evidence proves the registry cannot satisfy the source contract.
- Host tests can prove dual-store logic with fake stores and `FlutterSecureKeyStore` construction only. Real iOS Keychain accessibility across lock, unlock, reboot, iCloud Backup, iCloud Keychain, app reinstall, and OS restore remains residual acceptance for later device/simulator work.
- Push-token continuity is intentionally not preserved in this session. Old token material is clear/regenerate by policy.
- `account_migration_authority:v1` is intentionally device-local. It must not appear in migration export/import payloads even though local erase/reset may clear it.
- Full imported identity verification, including ML-KEM challenge against imported public key, is later import-verification scope. MIG-003 only gates sentinel promotion on required staged/promoted secret presence and registry readiness.
- Group notification-preview continuity is not closed here; this session only classifies shared mirror keys and proves cleanup/staging behavior.

## dependency impact

- MIG-004 depends on the staged/promoted `db_encryption_key` and sentinel-ordering contract before opening an imported SQLCipher database.
- MIG-005 depends on media secure-key reference collection but owns app-owned file transfer and media render/checksum proof.
- MIG-006 depends on group primary/shared key classification but owns group device identity, push-preview continuity, and multi-epoch history acceptance.
- MIG-008 durable cutover depends on cleanup and promoted-key rollback semantics but owns old/new active authority ordering.
- MIG-009 migrated-out runtime gates depend on push-token clear/regenerate policy and authority classification but own runtime enforcement.
- MIG-011 UI must call these cleanup/erase primitives instead of ad hoc key deletes.
- MIG-012 final acceptance must include iOS Keychain lock/reboot/iCloud residual behavior because MIG-003 host tests cannot close it.

## docs to update when execution finishes

- Update `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md` coverage/gap rows for primary/shared keychain completeness, fixed-key policies, DB-discovered references, push-token policy, device-local authority classification, staging, erase/reset, success/cancel/failed cleanup, sentinel ordering, and residual iOS keychain/iCloud behavior.
- Update `Test-Flight-Improv/codebase-test-inventory.md` for new account-migration secure-storage tests and any new push infrastructure test.
- Update `Test-Flight-Improv/test-gate-definitions.md` only if new tests require explicit classification or named gate membership. Do not widen frozen gates for ordinary feature-local unit tests.
- Leave `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md` unchanged unless execution discovers a real scope/dependency correction.

## Reviewer findings

Verdict: sufficient as-is for MIG-003 planning, with no structural blocker.

- Mandatory sections: present. The plan includes real scope, closure bar, source of truth, session classification, exact problem statement, files to inspect, existing tests, regressions to add first, implementation steps, risks, exact tests/gates, known-failure interpretation, done criteria, scope guard, accepted differences, and dependency impact. The additional docs section is appropriate for execution bookkeeping.
- Checklist coverage: sufficient. The closure bar and done-criteria coverage ledger map every user-listed MIG-003 requirement to a concrete proof or explicit residual/accepted difference: primary/shared registry, fixed keys, DB-discovered references, preferences, push-token policy, identity secrets, group key references, device-local authority, staging, promotion, erase/reset, cleanup modes, and `secrets_migrated` ordering.
- Closure bar: sufficient. It defines host-side proof for registry/staging/cleanup and explicitly preserves iOS lock/reboot/iCloud behavior as later residual acceptance rather than overclaiming it.
- Exact tests/gates: sufficient. The plan names new direct test files, affected existing direct tests, `./scripts/run_test_gates.sh baseline`, and conditional `./scripts/run_test_gates.sh completeness-check`. The conditional push decrypt simulator handling is acceptable because the plan does not touch push decrypt fixtures, simulator injection scripts, iOS NSE payload shape, Android push intake, or notification-preview delivery proof.
- Simulator gate need: no `$run-flutter-reliability-sims` gate is required for this session. MIG-003 does not close multi-device transfer, runtime delivery, notification opening, transport, cutover, lifecycle recovery, media rendering, or final iOS-to-iOS acceptance. Device and simulator proof remains assigned to later acceptance work, especially MIG-006 where notification-preview continuity is closed and MIG-012 where iOS device acceptance is closed.
- Stale assumptions: none found in the reviewed material. The plan acknowledges the point-operation-only `SecureKeyStore`, the explicit registry plus DB-reference strategy, the current shared access-group name, and dirty worktree state. Current code/tests remain the winner if execution finds drift.
- Scope guard: sufficient. The non-goals block prevents DB snapshot/import, media transfer, group continuity proof, local-network transfer, cutover, migrated-out gates, pending work, UI, and final acceptance from entering MIG-003.
- Decomposition quality: sufficient. Implementation steps are narrow enough for a future executor to add registry models, reference collection, staging/promotion, cleanup, sentinel ordering, and tests without inventing unrelated account-migration architecture.
- Minimum adjustment needed: none before execution.

## Arbiter decision

Final verdict: execution-ready for MIG-003.

Structural blockers:

- None.

Incremental details:

- None required before execution. A future executor may tighten wording or add candidate file names if live code discovery reveals a narrower helper location, but that is implementation-time detail and not a planning blocker.

Accepted differences:

- No platform keychain namespace enumeration is required for MIG-003 unless execution proves the explicit registry plus DB-discovered references cannot satisfy the source contract.
- No `$run-flutter-reliability-sims` gate or push decrypt simulator smoke is required in this session. The plan does not change transport, notification delivery/opening, NSE payload shape, simulator injection scripts, cutover, OS lifecycle recovery, or final two-device acceptance.
- iOS Keychain lock/reboot/iCloud/restore behavior remains residual acceptance for later device/simulator work; MIG-003 host tests must not claim it closed.
- Push-token material is intentionally clear/regenerate, not migrated as active state.
- `account_migration_authority:v1` is intentionally device-local and excluded from migration export/import payloads while still clearable by explicit local erase/reset.
- Full imported identity verification, group notification-preview continuity, DB snapshot/import, media transfer, durable cutover, migrated-out gates, pending work, UI, and final acceptance remain assigned to later sessions.

Arbiter rationale: the Reviewer found all mandatory plan sections present, checklist coverage itemized, closure bar explicit, regression-first tests named, named gates bounded, docs-to-update listed, simulator need correctly scoped, stale assumptions handled by current-code-wins language, and scope guard strong enough to prevent later-session bleed. With no structural blocker, the stop rule applies and this plan is reusable for execution.
