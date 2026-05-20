# INTEGRATE-BB-003 Standard Integration Contract

Status: accepted

## Planning Progress

- 2026-05-17: Evidence Collector completed. Files inspected since last update: worktree source matrix row `BB-003`, worktree session breakdown `BB-003`, historical worktree plan and execution evidence, main integration breakdown, COMPLETE_1 compatibility breakdown, and read-only current main/worktree anchors. Decision/blocker: BB-003 is covered/accepted in the source worktree and has a bounded source file/test inventory; no blocker to writing a standard integration contract.
- 2026-05-17: Planner completed. Files inspected since last update: this artifact. Decision/blocker: plan is standard integration only, not gap-closure, and reuses original implementation evidence instead of recreating the worktree implementation plan. Next action: review scope, tests, overlap, and ledger contract.
- 2026-05-17: Reviewer completed. Files inspected since last update: this artifact. Decision/blocker: sufficient with one adjustment: make the one-row guard and final ledger status options explicit. Next action: arbiter stop check.
- 2026-05-17: Arbiter completed. Files inspected since last update: this artifact. Decision/blocker: no structural blocker remains; execution may proceed later for `INTEGRATE-BB-003` only. Next action: hand off the plan.

## Execution Progress

- 2026-05-17 02:22 CEST - Executor started / contract extracted. Files inspected or touched: this plan, source worktree BB-003 matrix row, source worktree BB-003 breakdown entries, historical BB-003 plan final verdict and evidence, main integration breakdown row `INTEGRATE-BB-003`, COMPLETE_1 compatibility breakdown, current main/source git status, and the six requested BB-003 source changed files. Decision/blocker: source BB-003 is accepted host-only evidence; COMPLETE_1 exact searches for `BB-003`, `GroupCreate`, `group:create`, creator-material fields, and BB-003 file names found no overlapping accepted row. Main is partial, not already present: BB-003 test names and creator-material guards are absent while prior BB-001/BB-002 dirty changes are present. Next action: import only missing BB-003 production/test delta in row-owned files.
- 2026-05-17 02:27 CEST - Local fallback import completed after the spawned executor stalled before importing BB-003. Files touched: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/create_group_with_members_use_case.dart`, `test/features/groups/application/create_group_use_case_test.dart`, and `test/features/groups/application/create_group_with_members_use_case_test.dart`. Decision/blocker: imported only missing BB-003 creator-material validation and row-owned tests/fixtures; no COMPLETE_1 conflicting row was found; no BB-004 work started.
- 2026-05-17 02:30 CEST - Required focused and affected-main verification completed. Commands passed: focused Go BB-003 selector, focused Flutter create selector, focused Flutter create-with-members selector, combined Flutter create/create-with-members backstop, full `go test ./bridge` after adding the historical `bridge_generate_next_key_test.go` fixture adjustment, `dart format --set-exit-if-changed`, `git diff --check`, and recommended macOS `groups` smoke. Decision/blocker: none; final execution result is accepted.

## Final Execution Result

Final execution verdict: `accepted`.

Changed files imported into main:

- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/bridge/bridge_generate_next_key_test.go`
- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-003-plan.md`

Imported BB-003 delta:

- Native `GroupCreate` trims and requires `name`, `groupType`, `creatorPeerId`, `creatorPublicKey`, and `creatorMlKemPublicKey` before group id/key generation or topic join.
- Flutter `createGroup` rejects blank creator peer id, creator public key, creator ML-KEM public key, and missing/blank signed-create private key before bridge create or local persistence.
- Flutter `createGroupWithMembers` rejects missing/blank identity ML-KEM before create or invite side effects.
- Row-owned Go and Flutter BB-003 tests were added.
- Existing valid Go create fixtures in touched tests now provide creator ML-KEM so they continue testing their original success/backstop contracts.

Skipped duplicate or already-present work:

- Prior BB-001 callback refresh and BB-002 `NOT_INITIALIZED` tests were preserved and not reworked.
- No source closure docs were copied into main; the integration breakdown remains the reconciliation ledger.
- COMPLETE_1 search found no conflicting accepted row for `BB-003`, `GroupCreate`, `group:create`, creator-material fields, or the touched create files.

Verification evidence:

- `cd go-mknoon && go test ./bridge -run 'TestGroupCreate_BB003RequiresCompleteCreatorIdentityAndKeyMaterial|TestGroupCreate_(InvalidJSON|MissingFields|GL005RejectsUnsupportedPublicOrOpenGroupTypes)'` passed (`ok github.com/mknoon/go-mknoon/bridge 0.584s`).
- `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart --plain-name "BB-003 creator identity contract"` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name "BB-003"` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart` passed (`+35`).
- `cd go-mknoon && go test ./bridge` passed (`ok github.com/mknoon/go-mknoon/bridge 109.141s`).
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed (`+164`).
- `dart format --set-exit-if-changed lib/features/groups/application/create_group_use_case.dart lib/features/groups/application/create_group_with_members_use_case.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart` passed.
- `git diff --check -- go-mknoon/bridge/bridge.go go-mknoon/bridge/bridge_test.go go-mknoon/bridge/bridge_generate_next_key_test.go lib/features/groups/application/create_group_use_case.dart lib/features/groups/application/create_group_with_members_use_case.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-003-plan.md` passed.

Blocker: none.

Next allowed session after closure updates the integration breakdown: `INTEGRATE-BB-004`.

## Real Scope

Active mode: standard integration.

Import, reconcile, and verify exactly worktree row `BB-003` into the main checkout if and only if main lacks the row-owned behavior. This is not a gap-closure run and not a new implementation rollout.

The integration session owns only `INTEGRATE-BB-003` / source row `BB-003`: "Private group create requires complete creator identity and key material." Do not proceed to `BB-004`, do not bundle create-success coherence, and do not update any adjacent integration row.

## Closure Bar

The row can close only when main is truthfully classified as one of:

- `accepted`: missing BB-003 row-owned delta was imported, focused BB-003 and affected main/COMPLETE_1 tests passed, and the integration ledger records exact files/tests.
- `skipped_already_present`: main already has the complete BB-003 behavior and proof; no production/test code is modified.
- `blocked_conflict`: BB-003 overlaps a main/COMPLETE_1 row or dirty worktree change in a way that cannot be safely reconciled in this row; affected rows from both breakdowns are mapped.
- `blocked_external_fixture`: verification depends on an unavailable external fixture. This should be rare for BB-003 because the historical closure is host-only.

## Source Of Truth

- Primary worktree row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`, row `BB-003`.
- Source worktree breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`, session `BB-003`.
- Historical row plan and closure evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-003-plan.md`.
- Main compatibility breakdown: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Main integration breakdown: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.

Original implementation plans must be reused as evidence and comparison input only. Do not recreate, rewrite, or rerun the original worktree implementation plan.

## Session Classification

`implementation-ready` for standard integration, with an immediate branch to `skipped_already_present` if main comparison proves the full row already exists.

## Exact Problem Statement

The source worktree closed BB-003 by enforcing that private group creation fails before bridge create, topic join, local persistence, signed create event append, invite setup, or creator member/key creation when creator peer id, signing public key, ML-KEM public key, or signed-create private key is missing or blank.

The integration problem is to determine whether that exact row-owned behavior and proof are already present in main. If not, import only the missing meaningful BB-003 delta. Preserve existing main behavior and COMPLETE_1 accepted rows.

## Source Changed Files

Historical BB-003 closure evidence identifies these exact source changed files.

Production:

- `go-mknoon/bridge/bridge.go`
- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`

Tests:

- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/bridge/bridge_generate_next_key_test.go`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`

Historical closure docs, evidence only:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-003-plan.md`

Do not infer additional source files unless the file is proven by historical BB-003 closure evidence or by direct comparison as an already-present main equivalent.

## Files And Repos To Inspect Next

Before any edit, inspect and compare each source changed file above in:

- main checkout: `/Users/I560101/Project-Sat/mknoon-2/flutter_app`
- source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`

Also inspect:

- worktree matrix row `BB-003`
- worktree breakdown session `BB-003`
- historical BB-003 plan `Execution Progress`, `Execution Final Verdict`, and `Evidence passed`
- main integration breakdown row `INTEGRATE-BB-003`
- COMPLETE_1 compatibility breakdown by exact file names, test names, and scenario language

Read-only preflight on 2026-05-17 found main did not have the exact BB-003 test names and still showed the old missing-ML-KEM paths, but execution must recompare because the main worktree is dirty.

## Existing Tests Covering This Area

Historical BB-003 proof:

- `TestGroupCreate_BB003RequiresCompleteCreatorIdentityAndKeyMaterial`
- `BB-003 creator identity contract`
- `BB-003 rejects missing identity ML-KEM before create or invites`

Adjacent existing coverage to preserve in main:

- create success, rollback, signed-create, keyless-create, creator identity, description, and metadata tests in `test/features/groups/application/create_group_use_case_test.dart`
- create-with-members invite fanout, degraded invite/config paths, and identity export tests in `test/features/groups/application/create_group_with_members_use_case_test.dart`
- bridge `GroupCreate` invalid JSON, missing fields, unsupported type, create success, and generate-next-key setup tests

## COMPLETE_1 Overlap And Conflict Check

The main integration breakdown's known COMPLETE_1 overlap guard does not list `BB-003`. That does not remove the obligation to inspect overlaps.

Before edits, search the COMPLETE_1 compatibility breakdown for:

- `BB-003`
- `GroupCreate`
- `group:create`
- `creatorMlKemPublicKey`
- `creatorPeerId`
- `creatorPublicKey`
- `create_group_use_case_test.dart`
- `create_group_with_members_use_case_test.dart`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`

If any COMPLETE_1 row owns a conflicting accepted behavior in the same files, stop and write `blocked_conflict`. Map affected rows from:

- full-with-rules worktree breakdown: `BB-003`
- COMPLETE_1 breakdown: exact overlapping row ids found by search

Known nearby compatibility risks to preserve if touched:

- public/open unsupported create rejection from older/main evidence, especially `GL005`/unsupported-type bridge tests if present in main
- create signed-event rollback and creator identity export evidence from main test inventory rows such as `GL-002` and `ID-001`, if those rows are represented in the current main docs
- create-with-members degraded invite/config warning rows, if current main evidence names them

If BB-003 integration would require changing node join/rejoin, pubsub, invite fanout, device harnesses, or COMPLETE_1 group lifecycle rows, stop as `blocked_conflict`; that is outside this row.

## Regression/Tests To Add First

Do not add tests until after the main comparison confirms BB-003 is not already present.

If partially present, add only missing row-owned BB-003 tests from the historical worktree evidence:

- Go bridge missing/blank creator material table test.
- Flutter create missing/blank peer id, signing public key, ML-KEM public key, and signed-create private key test.
- Flutter create-with-members missing identity ML-KEM pre-create/pre-invite test.
- Valid create payload adjustments in touched Go tests only where needed to keep existing success-path tests testing their original row.

If already present, add no tests and mark `skipped_already_present` with file/test evidence.

## Step-By-Step Integration Plan

1. Confirm main worktree status and note unrelated dirty files. Do not revert or normalize existing user changes.
2. Inspect worktree row `BB-003`, the historical BB-003 plan/closure evidence, and the exact source changed files listed above.
3. Inspect COMPLETE_1 compatibility rows using exact file/test/scenario searches before editing.
4. Compare each source changed file against main before edits. Use behavior-level comparison, not blind copying.
5. If main already contains the full row behavior and focused tests, modify no production/test code and classify `skipped_already_present`.
6. If main is partial, integrate only the missing meaningful BB-003 delta in the exact source changed files. Preserve main's existing accepted behavior and dirty worktree changes.
7. If any conflict appears, stop immediately and classify `blocked_conflict` with affected row ids from both breakdowns.
8. Run required focused tests plus any affected COMPLETE_1/main tests.
9. Update this plan with execution evidence, then update the integration breakdown ledger with exactly one final status. Do not advance to `BB-004` in this session.

## Risks And Edge Cases

- Validation order can accidentally change unsupported group-type tests; complete identity material must be supplied in unsupported-type success-to-validation fixtures.
- Existing main create/signing behavior may be newer than the worktree row. Preserve main behavior unless it violates BB-003 directly.
- Main may have dirty changes in the same files. Work with them; do not revert.
- A broad gate failure is not a BB-003 failure unless it touches creator-material validation, create persistence, create-with-members identity ML-KEM, bridge `GroupCreate`, or an explicitly mapped COMPLETE_1 overlap.

## Exact Tests And Gates To Run

Required BB-003 tests from historical closure:

```bash
cd go-mknoon && go test ./bridge -run 'TestGroupCreate_BB003RequiresCompleteCreatorIdentityAndKeyMaterial|TestGroupCreate_(InvalidJSON|MissingFields|GL005RejectsUnsupportedPublicOrOpenGroupTypes)'
```

```bash
flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart --plain-name "BB-003 creator identity contract"
```

```bash
flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name "BB-003"
```

Required preservation/backstop tests:

```bash
flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart
```

```bash
cd go-mknoon && go test ./bridge
```

Recommended historical smoke, required before `accepted` if the integration changes production code and the environment can run macOS Flutter:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

Always run:

```bash
git diff --check
```

Add any affected COMPLETE_1/main tests discovered during overlap inspection. If no overlap is found, record that evidence explicitly.

## Known-Failure Interpretation

BB-003 focused test failures are blockers.

Unrelated broad failures in current main can be recorded without reopening BB-003 only when the focused BB-003 tests and mapped overlap tests are green and the failing test names do not involve `GroupCreate`, creator identity/key-material validation, create persistence, or create-with-members identity fanout.

Do not accept the row on docs-only evidence unless the code and focused tests are already present in main and the session is classified `skipped_already_present`.

## Done Criteria

- Main was compared against the source worktree before edits.
- Source changed-file inventory was confirmed from historical BB-003 closure evidence.
- COMPLETE_1 overlaps were searched and either mapped to tests or recorded as none found.
- Final outcome is one of `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture`.
- No `BB-004` work was started.
- No original worktree implementation plan was recreated.

## Scope Guard

Do not:

- implement `BB-004` or any later row
- convert this into gap-closure
- alter device, relay, fake-network, simulator, notification, UI, media, or pubsub lifecycle surfaces
- update the integration breakdown until actual execution/closure
- modify production or test files if main already contains the complete BB-003 behavior
- copy broad worktree formatting or unrelated test churn

## Accepted Differences / Intentionally Out Of Scope

BB-003 remains host-only. Device-lab, relay, real-network, simulator, and 3-party proof were not run or claimed historically and are not required for this standard integration unless a new main conflict proves otherwise.

Native `GroupCreate` does not validate the private signing key because that key stays in Flutter. The private-key side is owned by the Flutter signed-create boundary.

## Dependency Impact

Later create and invite rows may assume creator identity/key material is complete only after `INTEGRATE-BB-003` is `accepted` or `skipped_already_present`. If this row is `blocked_conflict`, do not advance `INTEGRATE-BB-004` until the conflict mapping is reviewed.
