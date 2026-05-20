# INTEGRATE-NW-013 Plan - Minimal Standard Integration Contract

Status: execution-complete-with-classified-residuals

Mode: standard worktree-to-main integration. This is import/reconcile/verify work for already-accepted source row `NW-013`; it is not gap-closure and must not recreate or rewrite the historical source worktree implementation plan.

## Planning Progress

| timestamp | role | files inspected since last update | decision/blocker | next action |
|---|---|---|---|---|
| 2026-05-20 16:07:39 CEST | Evidence Collector started | Target plan path existence; `implementation-plan-orchestrator` skill | Source row and intended integration plan path are confirmed; no blocker. | Inspect current integration breakdown and historical NW-013 source plan/evidence. |
| 2026-05-20 16:08:38 CEST | Evidence Collector completed | Current integration breakdown; historical NW-013 plan; source matrix row; source test inventory; source session breakdown; source/current migration inventories; source/current `main.dart`; source/current rotation-draft searches | Standard integration is needed. Current main has no durable pending rotation draft behavior. Source migration `068_group_key_rotation_drafts` conflicts with current main `068_removed_group_member_snapshots` and `069_group_message_local_deletions`. | Draft the minimal integration contract with a required migration renumber to the next main migration number, likely `070`. |
| 2026-05-20 16:09:25 CEST | Planner completed | Same evidence set plus current/source repository and rotation use-case snippets | Drafted a row-scoped import plan: bring over only durable pending rotation draft behavior and row-owned tests, renumber source migration/test/imports to `070`, and keep proof host-only. | Review for missing gates, stale assumptions, and scope drift. |
| 2026-05-20 16:09:25 CEST | Reviewer completed | Draft contract sections, source touched-file inventory, current-main classification, tests/gates, device profile | Sufficient with no structural gap: scope, closure bar, regression-first tests, migration conflict handling, and no-device proof profile are explicit. | Arbiter classification. |
| 2026-05-20 16:09:25 CEST | Arbiter completed | Reviewer findings and final contract | No structural blockers. Incremental details such as exact hunk placement are executor-owned. | Execute later from this contract only. |

## Execution Progress

| timestamp | phase | files inspected or touched | command/evidence | decision/blocker | next action |
|---|---|---|---|---|---|
| 2026-05-20 16:09:25 CEST | planning-complete | This plan only; evidence read from the current integration breakdown and historical source NW-013 plan/matrix/test-inventory/session-breakdown | No code, tests, harnesses, ledgers, or other docs were edited; no long live/device proof was run. | Minimal standard integration contract is execution-ready. | Future executor should run a dirty-state check, then import only missing row-owned NW-013 deltas with source migration `068` renumbered to next current main migration, likely `070`. |
| 2026-05-20 16:12:25 CEST | controller-started | Execution plan; orchestrator skill; migration inventory; row-owned dirty-state check | `git status --short -- <row-owned files>` showed only this plan as untracked; migration inventory ends at `069_group_message_local_deletions`; `codex exec` is available for spawned Executor/QA. | No blocker. | Extract execution contract and spawn Executor with `070_group_key_rotation_drafts` migration requirement. |
| 2026-05-20 16:12:25 CEST | contract-extracted | This plan; historical source NW-013 plan; current/source migration inventories | Scope is INTEGRATE-NW-013 only; source migration `068` must be imported as current-main `070`; host-only tests/gates are required; source worktree, ledgers, non-row files, Go/native, UI/notification/media/privacy are out of scope. | No blocker. | Spawn Executor for row-owned implementation and focused proof. |
| 2026-05-20 16:12:53 CEST | executor-spawned | This plan | Spawning Executor with `codex exec -m gpt-5.5`; requested `reasoning_effort: xhigh`; write scope limited to row-owned files. | No blocker. | Wait for Executor result, then inspect landed diff and spawn QA. |
| 2026-05-20 16:13:56 CEST | executor-running | This plan; orchestrator skill; SQLite migration/repository skill; row-owned dirty-state check | `git status --short` shows only this plan as untracked before implementation. | No blocker; executing INTEGRATE-NW-013 only with migration renumbered to `070_group_key_rotation_drafts`. | Inspect current/source row-owned files and import the pending rotation draft behavior. |
| 2026-05-20 16:17:27 CEST | executor-spawn-no-progress | This plan; spawned Executor terminal output; row-owned dirty-state check | Spawned Executor produced inspection output and the executor-running heartbeat, but no row-owned code/test diff and no final result after bounded waits; child process was stopped to avoid concurrent edits. | `spawn_or_tool_failure` for the spawned Executor attempt; no partial code/test edits to reconcile. | Use local sequential fallback for Executor work now, then run a separate QA review pass. |
| 2026-05-20 16:18:32 CEST | local-executor-implementation-started | Current/source row-owned use-case, repository, helper, migration, fake, and direct/fake-network test references | Current main behavior differs from source in adjacent removed-member snapshot support and distribution retry handling; implementation will add only pending-draft behavior and preserve those current-main paths. | No blocker. | Patch repository/helper/migration/use-case/main wiring and add focused NW-013 tests. |
| 2026-05-20 16:22:22 CEST | local-executor-implementation-patched | Row-owned repository contract/impl, group key helper, `070` migration, `main.dart`, in-memory fake, use-case, NW-013 direct/fake-network/helper/repository/migration/full-chain tests | Added pending draft table/API/use-case persistence as `070_group_key_rotation_drafts`; preserved `RemovedGroupMemberSnapshotRepository` and current distribution retry behavior. | No blocker identified before validation. | Run scoped format, then focused host-only tests and maintenance gates. |
| 2026-05-20 16:22:48 CEST | local-executor-format-finished | Row-owned Dart files | `dart format <row-owned Dart files>` formatted `test/core/database/helpers/group_keys_db_helpers_test.dart`; all other row-owned files already formatted. | No blocker. | Run format check and focused tests. |
| 2026-05-20 16:23:14 CEST | local-executor-tests-started | Row-owned Dart files | `dart format --set-exit-if-changed <row-owned Dart files>` passed. | No blocker. | Run focused host-only test selectors in plan order. |
| 2026-05-20 16:26:48 CEST | local-executor-focused-tests-finished | Row-owned test files and scoped production files | Passed: `flutter test --no-pub test/core/database/migrations/070_group_key_rotation_drafts_test.dart`; helper pending selector; repository NW-013 selector after fixing a test helper parameter mismatch; use-case NW-013 selector; use-case `KE-013|KE-020|promotes generated` selector; fake-network NW-013 selector; fake-network `KE-015 partial key distribution|KE-020 concurrent rotations` selector; full migration chain. Passed maintenance: `flutter analyze <row-owned Dart files>` and `git diff --check -- <row-owned files>`. | No blocker in focused proof. | Run feasible named host gates, then QA review. |
| 2026-05-20 16:30:16 CEST | local-executor-named-gate-classification-started | `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`; focused rerun of `test/features/groups/integration/group_membership_smoke_test.dart` | Broad `groups` gate is red at `+245 -9`; first focused classification narrowed at least one failure to `group_membership_smoke_test.dart`, which is outside NW-013 row ownership, but compact output hid the exact failing test name. | Gate is not accepted yet because exact residual classification is still pending. | Rerun the narrowed suite with JSON output, classify exact failing test(s), then continue QA. |
| 2026-05-20 16:33:19 CEST | local-executor-named-gates-finished | JSON rerun of the six `groups` gate host files; isolated `NW-004` startup-rejoin selector; `./scripts/run_test_gates.sh completeness-check` | `groups` remains red on nine non-NW-013 failures: known residuals `BB-007`, `BB-012`, `IR-003`, `IR-018`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, plus an isolated-red `NW-004 reconnect recovery stays live after ack across multiple groups` startup-rejoin failure outside this row's files/behavior. `completeness-check` remains red on known unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`. | Focused NW-013 proof is green, but broad named gates are not globally green; `NW-004` is an out-of-scope gate residual, not a row-owned fix target. | Run local QA review for scope, migration numbering, draft/key behavior, and final verdict classification. |
| 2026-05-20 16:33:31 CEST | local-qa-started | Row-owned diff, test evidence, gate residuals, migration inventory | QA will verify no non-row writes, migration `070`, preserved removed-member snapshot repository support, pending drafts excluded from committed key lookup/send path, and exact residual classification. | No QA finding yet. | Inspect status/diff and rerun final hygiene where needed. |
| 2026-05-20 16:35:35 CEST | local-qa-completed | Row-owned diff, final status, focused rerun after QA cleanup, format/analyze/diff hygiene | QA found no blocking NW-013 implementation issue. Replaced the pending-draft mismatch sentinel with an explicit typed load result, reran `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'NW-013'` green, reran row-owned `dart format --set-exit-if-changed`, row-owned `flutter analyze`, and `git diff --check` green. Status shows only the plan plus NW-013 row-owned files changed/untracked. | No NW-013 blocker. Broad `groups` and `completeness-check` residuals remain external follow-ups. | Write final execution verdict. |
| 2026-05-20 16:35:35 CEST | final-verdict | Full local execution and QA evidence | Verdict: `accepted`. NW-013 row contract is implemented and directly verified; no source/ledger/COMPLETE_1/non-row files were edited. | No NW-013 blocker. Broad `groups` and `completeness-check` reds are residual-only and outside this row. | Return final summary to user. |

## Real Scope

Own exactly integration row `INTEGRATE-NW-013`, sourced from historical row `NW-013`: "Stop/start during key rotation does not fork epochs."

The row contract is: if an active member/admin restarts after generating the next group key but before the update is locally committed, retry after restart must reuse the original generated key for `committedEpoch + 1`. It must not generate different same-epoch key material, must not expose pending drafts through committed-key lookup, must keep normal sends on the committed key until promotion, and must clear the pending draft only after successful local promotion/save.

This planning pass edited only this plan file. Future execution may inspect and reconcile code/tests, but must stay inside the row-owned import set below and preserve unrelated dirty worktree edits.

## Closure Bar

`INTEGRATE-NW-013` is good enough when current main has the source row's durable pending rotation draft behavior imported under the current main migration sequence, direct and fake-network selectors prove restart retry reuses the original draft key, persistence tests prove drafts round-trip without becoming the latest committed key, adjacent KE-013/KE-015/KE-020 behavior remains green or explicitly classified, and all proof is host-only with no iOS/device/relay claim.

## Source Of Truth

- Controlling integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`, where `NW-013` was `covered` in source and `pending_integration` in main at planning time, then accepted by this closure pass.
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-013-plan.md`.
- Historical source matrix row and test inventory under `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/`.
- Current main code/tests win over stale source prose for conflicts. Source closure evidence wins for row-owned behavior and proof shape. Current integration breakdown wins for integration state and ordering.

## Session Classification

`implementation-ready` standard integration.

This is not acceptance-only because current main does not already have the durable pending rotation draft repository/migration/use-case behavior. It is not gap-closure because the source worktree already closed NW-013; the task is to import/reconcile that accepted row into main.

## Exact Problem Statement

Current main rotates by restoring the latest committed key, generating `expectedEpoch`, distributing it, promoting it through Go, and then saving it as committed. If the rotator stops after some recipients receive the generated key but before local promotion/save, retry can generate a different key for the same epoch. Receivers already reject same-epoch different-key updates, so the sender must persist and reuse the original generated-but-uncommitted key.

User-visible behavior to improve: active members keep a monotonic usable key epoch across stop/start during rotation and can receive after retry.

Must stay unchanged: committed `group_keys` remains the source for normal sends; pending drafts must not be returned by `getLatestKey`; failed/future/skipped-epoch drafts fail closed; existing key update conflict rejection and adjacent partial-distribution semantics remain intact.

## Source Touched-File Inventory

Source row-owned production/import files:

- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/core/database/helpers/group_keys_db_helpers.dart`
- `lib/core/database/migrations/068_group_key_rotation_drafts.dart`
- `lib/main.dart`
- `test/shared/fakes/in_memory_group_repository.dart`

Source row-owned tests:

- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/core/database/migrations/068_group_key_rotation_drafts_test.dart`
- `test/core/database/helpers/group_keys_db_helpers_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`

Source closure docs used only as evidence, not to edit in this planning pass:

- `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-013-plan.md`
- `Private_group_chat_reliability_test_matrix_full_with_rules.md`
- `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- `test-inventory.md`

## Current Main Classification

Already present:

- Adjacent committed-key behavior exists: current rotation restores persisted committed key before generating and has KE-013/KE-020 style tests already present.
- Current main has migration `068_removed_group_member_snapshots` and migration `069_group_message_local_deletions`.
- `GroupRepository` already has `RemovedGroupMemberSnapshotRepository`; this must be preserved when adding the draft capability.

Partial:

- `rotate_and_distribute_group_key_use_case.dart` has expected-epoch validation, distribution failure handling, serialized rotation queueing, promotion, and committed `saveKey`, but it does not persist or reuse generated-but-uncommitted key material.
- `group_keys_db_helpers.dart`, `GroupRepositoryImpl`, and `InMemoryGroupRepository` have committed-key support but no pending rotation draft API in current main.

Missing:

- `GroupKeyRotationDraftRepository` contract and implementation.
- SQL table/helper support for `group_key_rotation_drafts`.
- Use-case load/save/reuse/clear/future-draft-fail-closed behavior.
- NW-013 direct, fake-network, migration/helper/repository, and full-chain tests.

Conflicting:

- Source migration `068_group_key_rotation_drafts.dart` and `068_group_key_rotation_drafts_test.dart` cannot be imported as `068` because main already uses `068_removed_group_member_snapshots`; main also already has `069_group_message_local_deletions`.
- Executor must renumber the source draft migration file, test, imports, references, migration runner calls, full migration chain ordering, and diagnostic strings to the next current main migration number, likely `070_group_key_rotation_drafts`.

## Files And Repos To Inspect Next

Inspect current main and source versions of:

- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/core/database/helpers/group_keys_db_helpers.dart`
- `lib/main.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/core/database/helpers/group_keys_db_helpers_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- Source `lib/core/database/migrations/068_group_key_rotation_drafts.dart` and source `test/core/database/migrations/068_group_key_rotation_drafts_test.dart`, but import them as current-main `070` unless a newer migration exists at execution time.

## Existing Tests Covering This Area

Existing adjacent coverage in current main:

- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` has KE-013 persisted committed-key restore and KE-020 concurrent rotation coverage.
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` has partial-distribution/promotion behavior that must remain intact.
- `test/features/groups/integration/group_messaging_smoke_test.dart` has adjacent KE-015/KE-020 fake-network coverage.

Missing in current main:

- No current-main `NW-013` selectors.
- No durable pending rotation draft migration/helper/repository tests.
- No proof that a retry after stop/start reuses original generated key material instead of generating a same-epoch replacement.

## Regression/Tests To Add First

Add or import these before behavior changes where feasible:

- Direct use-case selector `NW-013 restart retry reuses pending generated key before commit`: first attempt generates epoch `2` key `A`, partial distribution fails before promotion, latest committed key remains epoch `1`, retry with bridge capable of generating key `B` reuses/distributes/promotes key `A`, and no same-epoch different-key payloads exist.
- Direct use-case selector `NW-013 future pending draft fails closed instead of skipping epoch`: a pending draft above `committedEpoch + 1` must not advance the group.
- Repository selector `NW-013 pending rotation draft round-trips without becoming latest key`.
- Migration/helper selectors for renumbered `070_group_key_rotation_drafts`.
- Fake-network selector `NW-013 stop-start retry reuses pending rotation key and preserves fake-network delivery`.

## Step-By-Step Implementation Plan

1. Run `git status --short -- <row-owned files>` and preserve all unrelated dirty edits.
2. Determine the next migration number in current main at execution time. Based on current evidence, use `070_group_key_rotation_drafts`, not source `068`.
3. Import the source draft migration as the renumbered migration and update `lib/main.dart` plus full migration chain tests in numeric order after `069_group_message_local_deletions`.
4. Import pending draft helper APIs in `group_keys_db_helpers.dart`, preserving existing committed-key queries.
5. Add `GroupKeyRotationDraftRepository` to `group_repository.dart` without removing existing `RemovedGroupMemberSnapshotRepository`.
6. Wire `GroupRepositoryImpl` and `InMemoryGroupRepository` to save/load/clear pending drafts separately from committed keys.
7. Update `rotate_and_distribute_group_key_use_case.dart` to load a pending draft for `committedEpoch + 1`, save a newly generated draft before distribution, keep it on explicit distribution/promote failures, clear it only after `saveKey`, clear stale drafts at/below committed epoch, and fail closed on future/skipped-epoch drafts.
8. Import/adapt the NW-013 direct, fake-network, migration/helper/repository, and full migration chain tests with migration number `070`.
9. Run focused host-only selectors and scoped maintenance gates.
10. If focused tests pass, record closure evidence later in the appropriate closure phase. This planning pass must not update ledgers or test inventory.

Stop if current main already receives this behavior from another row before execution; reclassify as `stale/already-covered` only with concrete current-main code/test evidence.

## Risks And Edge Cases

- Same-epoch different-key fork after restart is the primary risk.
- Pending drafts must not become normal committed keys before promotion, or send-time epoch binding can regress.
- Future/skipped-epoch drafts must fail closed rather than silently jumping epochs.
- Distribution timeout/failure and promote failure must retain the pending draft for retry.
- Successful promotion must clear only the matching draft.
- Concurrent rotations must still serialize and allocate increasing committed epochs.
- Migration order must preserve main's existing `068_removed_group_member_snapshots` and `069_group_message_local_deletions`.

## Exact Tests And Gates To Run

Focused host-only tests:

```bash
flutter test --no-pub test/core/database/migrations/070_group_key_rotation_drafts_test.dart
flutter test --no-pub test/core/database/helpers/group_keys_db_helpers_test.dart --name 'pending group-key rotations|rotation draft'
flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart --plain-name 'NW-013 pending rotation draft round-trips without becoming latest key'
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'NW-013'
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --name 'KE-013|KE-020|promotes generated'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'NW-013 stop-start retry reuses pending rotation key and preserves fake-network delivery'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --name 'KE-015 partial key distribution|KE-020 concurrent rotations'
flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart
```

Scoped maintenance:

```bash
dart format --set-exit-if-changed lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart lib/features/groups/domain/repositories/group_repository.dart lib/features/groups/domain/repositories/group_repository_impl.dart lib/core/database/helpers/group_keys_db_helpers.dart lib/core/database/migrations/070_group_key_rotation_drafts.dart lib/main.dart test/shared/fakes/in_memory_group_repository.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/core/database/migrations/070_group_key_rotation_drafts_test.dart test/core/database/helpers/group_keys_db_helpers_test.dart test/features/groups/domain/repositories/group_repository_impl_test.dart test/core/database/integration/full_migration_chain_test.dart
flutter analyze lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart lib/features/groups/domain/repositories/group_repository.dart lib/features/groups/domain/repositories/group_repository_impl.dart lib/core/database/helpers/group_keys_db_helpers.dart lib/core/database/migrations/070_group_key_rotation_drafts.dart lib/main.dart test/shared/fakes/in_memory_group_repository.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/core/database/migrations/070_group_key_rotation_drafts_test.dart test/core/database/helpers/group_keys_db_helpers_test.dart test/features/groups/domain/repositories/group_repository_impl_test.dart test/core/database/integration/full_migration_chain_test.dart
git diff --check -- lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart lib/features/groups/domain/repositories/group_repository.dart lib/features/groups/domain/repositories/group_repository_impl.dart lib/core/database/helpers/group_keys_db_helpers.dart lib/core/database/migrations/070_group_key_rotation_drafts.dart lib/main.dart test/shared/fakes/in_memory_group_repository.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/core/database/migrations/070_group_key_rotation_drafts_test.dart test/core/database/helpers/group_keys_db_helpers_test.dart test/features/groups/domain/repositories/group_repository_impl_test.dart test/core/database/integration/full_migration_chain_test.dart
```

Named host gates if feasible after focused proof:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

## Known-Failure Interpretation

Do not classify a failure as NW-013 unless it touches pending rotation draft behavior, committed-key visibility, key distribution/promote retry, migration/helper/repository round-trip, or the exact NW-013 fake-network selector.

Known residuals from the current integration breakdown through NW-012 must remain separate unless fresh evidence proves this row caused them: broad `groups` gate red on `GM-029`, `completeness-check` red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification, and fixed-date replay preservation residuals outside NW-013.

## Device/Relay Proof Profile

Host-only.

`3-Party E2E` is `N/A` for NW-013. No simulator/device proof is required or claimed. No iOS 26.2 live proof is required or claimed. No relay-backed run, `MKNOON_RELAY_ADDRESSES`, stale process check, iOS UDID selection, Android, physical iOS, macOS app-peer, web, Go/native, UI, notification, media, privacy, or broader chaos proof is part of this row.

Historical source evidence also closed NW-013 without simulator/device proof.

## Done Criteria

- Source pending draft behavior is present in current main under the current main migration sequence, likely `070_group_key_rotation_drafts`.
- `getLatestKey` and normal sends continue to see only committed keys.
- Retry after stop/start reuses the original generated pending key for `committedEpoch + 1`.
- Future/skipped-epoch pending drafts fail closed.
- Pending drafts survive explicit distribution/promote failures and are cleared only after successful local promotion/save.
- Focused NW-013 direct, fake-network, migration/helper/repository, and full migration chain tests pass.
- Adjacent KE-013, KE-015, and KE-020 preservation selectors pass or have exact non-NW-013 classification.
- Scoped format/analyze and `git diff --check` pass for row-owned files.
- Device/relay proof remains explicitly host-only with no iOS 26.2 live claim.

## Scope Guard

Do not edit source worktree files, source matrix, source session breakdown, COMPLETE_1 docs, unrelated ledgers, unrelated feature docs, Go/native files, live harnesses, relay scripts, UI, notification, media, privacy, or broader network/chaos rows as part of NW-013.

Do not import source migration `068` under that number. Do not overwrite current main migration `068_removed_group_member_snapshots` or `069_group_message_local_deletions`.

Do not weaken receiver same-epoch conflict rejection to make NW-013 pass. The row prevents the sender from creating that conflict.

Do not close NW-014, NW-015, KE-007, KE-009, ML-012, or any non-NW-013 row by implication.

## Accepted Differences / Intentionally Out Of Scope

- Historical source used migration `068`; current main must use the next main migration number, likely `070`.
- Historical source did not require device proof; current integration must remain host-only.
- No Go/native proof is required because the source row's ownership is Dart persistence/repository/use-case behavior.
- Adjacent key listener, stale config, relay, reconnect, chaos, and notification/media rows remain independent.

## Dependency Impact

Later network/key-rotation reliability rows may rely on NW-013 only for durable reuse of locally generated but uncommitted rotation material. If this integration blocks on migration ordering or draft visibility, later rows that assume monotonic stop/start key rotation should be skipped or revisited.

## Reviewer Pass

Sufficiency: sufficient as-is for standard integration.

Missing files/tests/gates: none structurally. The contract names source inventory, current-main conflict classification, row-owned files, focused host tests, preservation selectors, scoped maintenance, known residual handling, and host-only proof profile.

Stale assumptions: migration number `070` is marked "likely"; executor must recheck current migration inventory before editing. Device-proof assumptions are avoided because no live proof is required.

Overengineering: avoided. The plan imports the source row's narrow persistence/use-case contract and does not add relay, live harness, product UI, or broader recovery work.

Minimum needed to implement safely: run dirty-state checks, renumber source migration/test/imports to the current next main migration, import only the row-owned draft behavior/tests, then run the listed host gates.

## Arbiter Decision

Planning verdict: execution-ready for `INTEGRATE-NW-013` only.

Structural blockers remaining: none.

Incremental details intentionally deferred: exact hunk placement, exact current next migration number if main advances beyond `069`, and adaptation to unrelated dirty edits in row-owned files.

Accepted differences intentionally left unchanged: host-only proof, no 3-party E2E, no iOS 26.2 live proof, no source migration-number reuse, no adjacent-row closure.

Why safe to implement now: the contract is evidence-backed by the accepted source NW-013 plan and source matrix/test-inventory closure, current main lacks the durable draft behavior, and the only known conflict is explicit and bounded to migration renumbering.

## Closure Audit Result

Closure verdict: `accepted`.

The execution status is `execution-complete-with-classified-residuals`: row-owned NW-013 implementation and proof passed, and the remaining red broad gates are classified as non-NW-013 residuals rather than blockers. Earlier child-only follow-up wording is superseded by the controller-allowed terminal status `accepted` because no NW-013 blocker remains.

Closed for INTEGRATE-NW-013: migration `070_group_key_rotation_drafts`, pending rotation draft helper/repository APIs, rotate-and-distribute draft reuse behavior, in-memory fake support, direct/fake-network proof selectors, repository/helper/migration/full-chain tests, KE-013/KE-015/KE-020 preservation selectors, row-owned format/analyze checks, and row-owned `git diff --check`.

Controller spot-check evidence after execution: `dart format --set-exit-if-changed <row-owned files>` passed with 0 changed; `git diff --check -- <row-owned files>` passed; and `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'NW-013'` passed with `+2`.

Residual-only items preserved outside NW-013: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+245 -9` on known non-NW-013 failures `BB-007`, `BB-012`, `IR-003`, `IR-018`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, plus isolated out-of-scope `NW-004 reconnect recovery stays live after ack across multiple groups`; `./scripts/run_test_gates.sh completeness-check` remains red on known unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`. Device profile is host-only; 3-Party E2E is `N/A`; no iOS 26.2/live proof is required or claimed.
