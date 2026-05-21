# INTEGRATE-ST-015 Worktree-To-Main Integration Contract

Status: accepted

Current session: `INTEGRATE-ST-015`
Source row: `ST-015` / "Seeded reproduction logs are stable enough for debugging"
Mode: current-main import/reconcile/verify only, not original worktree implementation planning
Writable artifact for this planning session: this file only

## Planning Progress

- 2026-05-21 17:39:12 CEST - Arbiter completed. Files inspected since last update: draft contract and reviewer checks. Decision/blocker: no structural blocker remains; status is `execution-ready`. Next action: future executor may implement only this contract.
- 2026-05-21 17:39:12 CEST - Reviewer completed. Files inspected since last update: missing-file evidence, current/source smoke selector diff evidence, matrix/inventory requirements. Decision/blocker: sufficient after explicit no-live-proof, scope guard, and ledger/commit instructions. Next action: arbiter pass.
- 2026-05-21 17:39:12 CEST - Planner completed. Files inspected since last update: source helper/test contents, source ST-015 smoke selector, current smoke imports/selectors, current integration breakdown, current inventory. Decision/blocker: current main lacks the row-owned ST-015 helper, helper test, import, and fake-network selector; no blocker. Next action: reviewer pass.
- 2026-05-21 17:39:12 CEST - Evidence Collector completed. Files inspected since last update: source ST-015 plan, source matrix row, source and current `test-inventory.md`, current integration breakdown, source/current candidate test files, and `git status --short`. Decision/blocker: current HEAD is `f1903e8f`; only unrelated `info.plist` was dirty before this plan file; no blocker. Next action: planner pass.
- 2026-05-21 17:37:28 CEST - Evidence Collector started. Files inspected since last update: `git status --short`, `git log -1 --oneline`, target plan path existence. Decision/blocker: current HEAD is `f1903e8f Integrate ST-014 soak proof`; only `info.plist` is dirty; no blocker. Next action: inspect row-owned source and current files.

## real scope

Create the smallest current-main ST-015 integration: import or reconcile the source row's deterministic seeded reproduction-log helper, its focused unit test, and the row-named fake-network integration selector into current main.

This plan does not recreate, rewrite, or rerun the historical source implementation plan. It treats the source ST-015 plan and closure evidence as the row contract, then adapts that into current main without disturbing later integrated work.

## closure bar

ST-015 can close as accepted only when current main contains row-owned evidence that a seed-`15015` randomized private-group fake-network failure can be captured as byte-identical canonical JSON across reruns, including seed, ordered operations, `group:publish` bridge responses, delivery diagnostics, and a failure marker that localizes the simulated miss to the transport layer.

Required source matrix coverage is Unit, Integration, and Fake Network. Smoke and 3-Party E2E are `N/A`. Live/iOS proof is not required and must not be requested, run, or claimed for ST-015.

## source of truth

Authoritative row intent and closure evidence:

- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-015-plan.md`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Authoritative current-main integration state:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- current main code/tests at HEAD `f1903e8f`

On disagreement, preserve current-main code shape and import only equivalent ST-015 row-owned behavior from the source worktree. Do not wholesale-copy source files over current main.

## session classification

`implementation-ready`

The gap is narrow and evidence-backed: current main is missing `test/shared/fakes/seeded_group_reproduction_log.dart`, missing `test/shared/fakes/seeded_group_reproduction_log_test.dart`, and current `test/features/groups/integration/group_messaging_smoke_test.dart` lacks the ST-015 helper import and selector.

## exact problem statement

Current main has supporting seeded and fake-network primitives from prior rows, including GO-012, GE-017/019/020, and accepted ST-014 soak proof, but those are not equivalent ST-015 closure. Main cannot yet prove that a failed randomized private-group reliability run emits a deterministic, rerunnable reproduction artifact with enough debug context to identify whether the failure belongs to transport, key, config, or UI/application state.

What must improve: add current-main ST-015 test-harness evidence for deterministic reproduction logs.

What must stay unchanged: production behavior, live harness behavior, ST-014 soak proof, ST-013 relay-chaos proof, ST-012 topic-leak proof, ST-010 malformed-payload proof, ST-009 max-size churn proof, UI/media/security rows, and all unrelated files.

## exact missing row-owned deltas to import/reconcile

1. Add `test/shared/fakes/seeded_group_reproduction_log.dart` from the source worktree as a test-harness-only helper.
2. Add `test/shared/fakes/seeded_group_reproduction_log_test.dart` from the source worktree as the focused ST-015 unit proof.
3. Reconcile `test/features/groups/integration/group_messaging_smoke_test.dart` by adding only:
   - local import `../../../shared/fakes/seeded_group_reproduction_log.dart`;
   - selector `ST-015 seeded reproduction log reruns with stable debug context`.
4. Preserve current-main imports, helper classes, and all already-integrated selectors in `group_messaging_smoke_test.dart`; do not replace the file with the older source-worktree version.
5. After execution evidence passes, update only current integration ledger/inventory docs in a closure step; do not update source docs or COMPLETE_1 docs.

## file-by-file classification

| File | Current state | ST-015 action | Classification |
|------|---------------|---------------|----------------|
| `test/shared/fakes/seeded_group_reproduction_log.dart` | Missing from current main | Add from source, preserving the canonical JSON helper for row id, seed, scenario, ordered operations, bridge responses, diagnostics, and optional failure metadata | Row-owned test helper; new file |
| `test/shared/fakes/seeded_group_reproduction_log_test.dart` | Missing from current main | Add focused unit test `ST-015 canonicalizes seed operation bridge diagnostic and failure` | Row-owned unit proof; new file |
| `test/features/groups/integration/group_messaging_smoke_test.dart` | Exists in current main with later integrated rows; lacks ST-015 import/selector | Merge only the ST-015 import and `ST-015 seeded reproduction log reruns with stable debug context` selector | Row-owned fake-network integration proof; reconcile only |
| `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` | Current closure doc has ST-014 accepted but no current ST-015 closure row | Update only after direct tests and hygiene pass | Closure ledger doc; execution/closure phase only |
| `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md` | Records `INTEGRATE-ST-015` as sole pending row | Update only after direct tests and hygiene pass | Integration ledger doc; execution/closure phase only |
| `info.plist` | Pre-existing unrelated dirty file | Leave untouched and unstaged | Out of scope |

## files and repos to inspect next

Before editing, re-run `git status --short` and confirm the only pre-existing dirty file is `info.plist` plus this plan file.

Inspect these source/current paths side by side:

- source helper: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/shared/fakes/seeded_group_reproduction_log.dart`
- source helper test: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/shared/fakes/seeded_group_reproduction_log_test.dart`
- source selector: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/integration/group_messaging_smoke_test.dart`
- current selector target: `test/features/groups/integration/group_messaging_smoke_test.dart`

Do not inspect or edit broader source docs except as evidence already named in this plan.

## existing tests covering this area

Existing current-main supporting tests prove seeded models, fake-network messaging, and ST-014 soak behavior, but they do not prove ST-015's reproduction-artifact contract.

Missing focused tests:

- `ST-015 canonicalizes seed operation bridge diagnostic and failure`
- `ST-015 seeded reproduction log reruns with stable debug context`

## regression/tests to add first

Add the helper and helper unit test first, then reconcile the fake-network selector. The unit test pins canonical map-key ordering and byte-identical artifacts across insertion-order changes. The fake-network selector proves the same seed produces the same artifact across two Alice/Bob/Charlie runs with ordered send operations, `group:publish` responses, delivery diagnostics, and a deterministic transport failure marker.

## step-by-step implementation plan

1. Run `git status --short`; confirm `info.plist` remains unrelated and unstaged.
2. Add the missing helper file from the source worktree.
3. Add the missing helper unit test from the source worktree.
4. Patch current `group_messaging_smoke_test.dart` with only the ST-015 helper import and selector; preserve current-main file order and all existing selectors, especially ST-014.
5. Run the focused ST-015 unit and fake-network integration tests.
6. Run scoped format, analyzer, and diff hygiene gates.
7. If all gates pass, update current test inventory and integration breakdown as closure-owned docs.
8. Commit only row-owned ST-015 code/test/doc changes; leave `info.plist` unstaged and untouched.

Stop early if current main already has equivalent ST-015 coverage after a fresh recheck; in that case run the selectors and update ledger evidence only.

## risks and edge cases

- Wholesale-copying the source `group_messaging_smoke_test.dart` would regress current-main rows integrated after the source snapshot.
- The ST-015 helper must stay test-harness-only; no production code should import it.
- The canonical JSON helper must keep ordered operation lists while sorting map keys recursively.
- The fake-network selector uses a simulated failure marker; it must not require real network, relay, simulator, device, or live proof.
- The file named `group_messaging_smoke_test.dart` hosts the fake-network integration selector, but the matrix `Smoke` column remains `N/A` for ST-015.

## exact tests and gates to run

Focused ST-015 tests:

```sh
flutter test --no-pub test/shared/fakes/seeded_group_reproduction_log_test.dart --plain-name "ST-015"
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-015"
```

Scoped hygiene:

```sh
dart format --set-exit-if-changed test/shared/fakes/seeded_group_reproduction_log.dart test/shared/fakes/seeded_group_reproduction_log_test.dart test/features/groups/integration/group_messaging_smoke_test.dart
flutter analyze --no-pub test/shared/fakes/seeded_group_reproduction_log.dart test/shared/fakes/seeded_group_reproduction_log_test.dart test/features/groups/integration/group_messaging_smoke_test.dart
git diff --check
```

No live/device/simulator proof:

- Do not run `run_group_multi_party_device_real.dart`.
- Do not run iOS, Android, macOS, Chrome, relay, or physical-device proof for ST-015.
- Do not add or change integration-test criteria or live-harness files for ST-015.

## known-failure interpretation

Focused ST-015 failures are row-owned and must be fixed before closure.

Unrelated broad-suite residuals remain out of scope unless they are caused by the ST-015 files changed in this session. If a broad completeness check is run later and reports the new ST-015 helper test as unclassified, that is closure-doc work for current `test-inventory.md`, not a reason to broaden code changes.

Existing blockers remain unchanged: `KE-007` and `KE-009` stay `blocked_conflict`; `ML-012`, `NW-014`, `UP-002`, `UP-004`, `UP-006`, `UP-009`, `UP-010`, `UP-011`, and prior `ST-001` stay under their existing classifications until their own controller reclassification.

## done criteria

- `test/shared/fakes/seeded_group_reproduction_log.dart` exists in current main and is test-only.
- `test/shared/fakes/seeded_group_reproduction_log_test.dart` exists and its ST-015 selector passes.
- `test/features/groups/integration/group_messaging_smoke_test.dart` has the ST-015 helper import and selector, with no unrelated selector churn.
- Focused ST-015 unit and fake-network tests pass.
- Scoped format, analyzer, and `git diff --check` pass.
- Current `test-inventory.md` and integration breakdown record ST-015 accepted only after evidence passes.
- `info.plist` remains untouched, unstaged, and absent from the ST-015 commit.

## scope guard

Do not edit or import:

- ST-014 soak, ST-013 relay chaos, ST-012 topic leak, ST-010 malformed bridge fuzzing, ST-009 max-size churn, ST-011 EventChannel reinitialize, ST-008 DB contention, or any other non-ST-015 row;
- UI, media, notification, privacy, or security rows;
- production code under `lib/`, native Go code, live harness, criteria scripts, runner scripts, or simulator/device assets;
- source matrix docs, source session plans, source session breakdowns, source worktree docs, COMPLETE_1 docs, or unrelated files;
- `info.plist`.

Do not stage or commit during this planning task. Future execution commits must include only row-owned ST-015 files plus current closure docs after evidence passes.

## accepted differences / intentionally out of scope

The source row marks `Smoke` and `3-Party E2E` as `N/A`; current-main integration must preserve that. ST-015 is satisfied by host unit and fake-network integration evidence, not by live proof.

No criteria proof, live verdict field, iOS simulator proof, relay proof, Android proof, physical iOS proof, UI proof, media proof, or security proof is required or accepted for this row.

## dependency impact

`INTEGRATE-ST-015` is the sole pending row after accepted `INTEGRATE-ST-014`. If execution closes ST-015 as accepted, the current integration breakdown should move from accepted 186 / pending 1 to accepted 187 / pending 0 while preserving the existing skipped, blocked-conflict, and blocked-external-fixture classifications.

After closure, the next action should be final integration-program closure/audit, not another row import.

## ledger and commit instructions for after execution

After the focused tests and hygiene gates pass:

1. Update `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` with a current-main ST-015 `Covered - accepted` row noting the helper, unit selector, fake-network selector, scoped analyzer/format, `git diff --check`, and explicit no-live-proof requirement.
2. Update `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md` with an `INTEGRATE-ST-015` accepted ledger row and current program verdict showing pending `0`.
3. Commit only row-owned ST-015 files and current closure docs:
   - `test/shared/fakes/seeded_group_reproduction_log.dart`
   - `test/shared/fakes/seeded_group_reproduction_log_test.dart`
   - `test/features/groups/integration/group_messaging_smoke_test.dart`
   - this plan
   - current integration breakdown and current test inventory after closure updates
4. Do not stage or commit `info.plist`.
5. Do not include source-worktree docs, source matrix docs, COMPLETE_1 docs, live-harness files, criteria files, runner files, production files, or unrelated dirty files.

## Execution Progress

- 2026-05-21 17:42:06 CEST - Executor started. Files inspected or touched: `git status --short`. Decision/blocker: dirty state matched allowed baseline with modified `info.plist` plus untracked ST-015 plan. Next action: inspect source helper/test and current smoke file.
- 2026-05-21 17:42:36 CEST - Contract extracted. Files inspected or touched: ST-015 plan, source `seeded_group_reproduction_log.dart`, source `seeded_group_reproduction_log_test.dart`, source/current `group_messaging_smoke_test.dart`. Decision/blocker: current main lacked the two row-owned helper files plus the ST-015 smoke import/selector. Next action: add helper/test and reconcile selector only.
- 2026-05-21 17:43:16 CEST - Executor patch completed. Files touched: `test/shared/fakes/seeded_group_reproduction_log.dart`, `test/shared/fakes/seeded_group_reproduction_log_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`. Decision/blocker: helper/test added; smoke file patched with the ST-015 import and selector only. Next action: run focused ST-015 tests.
- 2026-05-21 17:43:35 CEST - Focused unit test finished. Command: `flutter test --no-pub test/shared/fakes/seeded_group_reproduction_log_test.dart --plain-name "ST-015"`. Status: passed, `+1: All tests passed!`. Next action: run focused fake-network selector.
- 2026-05-21 17:43:42 CEST - Focused fake-network selector first run finished. Command: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-015"`. Status: failed before ST-015 log assertions because current-main bridge-backed sends returned `error` from `GROUP_SEND_MSG_USE_CASE_BOOTSTRAP_PENDING`; classified as row-owned selector drift against current-main key preconditions. Next action: patch only the ST-015 selector setup with deterministic group key seeding.
- 2026-05-21 17:44:09 CEST - Executor fix patch completed. Files touched: `test/features/groups/integration/group_messaging_smoke_test.dart`. Decision/blocker: ST-015 selector now saves deterministic `GroupKeyInfo` for Alice, Bob, and Charlie before starting listeners. Next action: rerun focused fake-network selector.
- 2026-05-21 17:44:24 CEST - Focused fake-network selector rerun finished. Command: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-015"`. Status: passed, `+1: All tests passed!`. Next action: run scoped hygiene gates.
- 2026-05-21 17:44:34 CEST - Format gate finished. Command: `dart format --set-exit-if-changed test/shared/fakes/seeded_group_reproduction_log.dart test/shared/fakes/seeded_group_reproduction_log_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`. Status: passed, `Formatted 3 files (0 changed)`.
- 2026-05-21 17:45:03 CEST - Analyzer gate finished. Command: `flutter analyze --no-pub test/shared/fakes/seeded_group_reproduction_log.dart test/shared/fakes/seeded_group_reproduction_log_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`. Status: passed, `No issues found! (ran in 28.6s)`.
- 2026-05-21 17:45:09 CEST - Diff hygiene finished. Command: `git diff --check`. Status: passed with no output. No live/device/simulator proof was run; ST-015 live proof is N/A.
- 2026-05-21 17:45:22 CEST - Final status inspected. Files touched in executor scope: `test/shared/fakes/seeded_group_reproduction_log.dart`, `test/shared/fakes/seeded_group_reproduction_log_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, and this ST-015 plan. Decision/blocker: no staging or commit performed; `info.plist` remains unrelated and unstaged. Integration breakdown and test inventory intentionally not edited per current executor instruction.

## Final Execution Verdict

Verdict: `accepted`

Scope completed:

- Added test-only seeded reproduction helper at `test/shared/fakes/seeded_group_reproduction_log.dart`.
- Added focused unit proof at `test/shared/fakes/seeded_group_reproduction_log_test.dart`.
- Patched current `test/features/groups/integration/group_messaging_smoke_test.dart` with the ST-015 helper import and selector only, preserving existing current-main selectors. The selector was reconciled to current-main bridge-backed send preconditions by seeding a deterministic group key for all three fake users.
- Updated this plan with execution evidence only.

Required commands and final status:

- `flutter test --no-pub test/shared/fakes/seeded_group_reproduction_log_test.dart --plain-name "ST-015"`: passed, `+1: All tests passed!`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-015"`: initial run failed with `GROUP_SEND_MSG_USE_CASE_BOOTSTRAP_PENDING`; after the row-owned selector fix, rerun passed, `+1: All tests passed!`
- `dart format --set-exit-if-changed test/shared/fakes/seeded_group_reproduction_log.dart test/shared/fakes/seeded_group_reproduction_log_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`: passed, `Formatted 3 files (0 changed)`
- `flutter analyze --no-pub test/shared/fakes/seeded_group_reproduction_log.dart test/shared/fakes/seeded_group_reproduction_log_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`: passed, `No issues found! (ran in 28.6s)`
- `git diff --check`: passed with no output

Non-goals honored:

- No live/device/simulator proof was run; ST-015 live proof is N/A.
- No integration breakdown or test-inventory edits were made in this executor pass.
- No staging or commit was performed.
- Pre-existing unrelated `info.plist` remained untouched and unstaged.

## Closure Documentation Note

- 2026-05-21 closure worker accepted ST-015 in the current integration breakdown and current test inventory only. The breakdown now records all 202 rows with terminal statuses: accepted 187, pending 0, skipped 4, blocked_conflict 2, blocked_external_fixture 9. Final program closure remains for controller/final audit.
