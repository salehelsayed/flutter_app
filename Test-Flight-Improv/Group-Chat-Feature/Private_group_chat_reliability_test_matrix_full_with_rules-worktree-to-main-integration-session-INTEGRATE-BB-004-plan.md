# INTEGRATE-BB-004 Plan: Standard Worktree-To-Main Integration

Status: accepted

Final verdict: accepted. This standard integration pass imported only the missing historical BB-004 row-owned tests into main, kept production files untouched, verified focused and affected gates, and left BB-005 untouched.

## Planning Progress

- 2026-05-17 CEST - Evidence Collector completed. Inspected the integration breakdown row, source worktree matrix row, source worktree breakdown row, historical BB-004 plan/closure evidence, exact source changed files, main same-file BB-004 anchors, main dirty-file state, and COMPLETE_1 compatibility overlap candidates.
- 2026-05-17 CEST - Planner completed. Drafted a one-row standard-integration contract for `INTEGRATE-BB-004` only, with compare-before-edit, skip, partial-import, conflict, and final ledger status rules.
- 2026-05-17 CEST - Reviewer completed. No structural blocker found; source BB-004 is tests-only and production changes are forbidden unless comparison proves a real conflict/blocker, in which case the session must stop as `blocked_conflict`.
- 2026-05-17 CEST - Arbiter completed. Final contract is execution-ready for import/reconcile/verify only; `BB-005` and all other rows remain out of scope.

## Execution Progress

- 2026-05-17 02:44 CEST - Local execution started after plan completion. Files inspected: this plan, historical BB-004 plan/evidence, source test anchors, main test anchors, main integration breakdown row `INTEGRATE-BB-004`, and COMPLETE_1 semantic overlap candidates. Decision/blocker: main lacked the BB-004 row-named tests; COMPLETE_1 had no concrete same-file or behavior conflict; source BB-004 was tests-only, so production files stayed out of scope.
- 2026-05-17 02:45 CEST - Imported only missing BB-004 row-owned tests into `go-mknoon/bridge/bridge_test.go`, `test/core/bridge/bridge_group_helpers_test.dart`, and `test/features/groups/application/create_group_use_case_test.dart`. Production files were not changed. Next action: run focused historical tests.
- 2026-05-17 02:49 CEST - Focused tests, broad selectors, full bridge backstop, required host groups smoke, format, and diff hygiene all passed. Decision/blocker: none; final execution result is accepted.

## Final Execution Result

Final execution verdict: `accepted`.

Changed files imported into main:

- `go-mknoon/bridge/bridge_test.go`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-004-plan.md`

Production files changed: none.

Imported BB-004 delta:

- Added native bridge proof `TestGroupCreate_BB004ReturnsCoherentInitialStateAndAcceptsFirstPublish`.
- Added Dart bridge-helper proof that `callGroupCreate` preserves coherent create response fields and `callGroupPublish` publishes with the created group id.
- Added Flutter create-use-case proof that local group/member/key state uses the bridge group id, canonical `/mknoon/group/<groupId>` topic fallback, creator config, group key, and epoch.

Skipped duplicate or already-present work:

- Existing nearby create, key, join, rejoin, and publish tests were preserved and not rewritten into BB-004.
- Historical source closure docs were not copied into main.
- No COMPLETE_1 conflicting row was found for the touched test files or the BB-004 create/publish proof.

Verification evidence:

- `cd go-mknoon && go test ./bridge -run 'TestGroupCreate_BB004ReturnsCoherentInitialStateAndAcceptsFirstPublish' -count=1` passed (`ok github.com/mknoon/go-mknoon/bridge 0.509s`).
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name "BB-004"` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart --plain-name "BB-004"` passed (`+1`).
- `cd go-mknoon && go test ./bridge -run 'TestGroupCreate_BB004ReturnsCoherentInitialStateAndAcceptsFirstPublish|TestGroupPublish_ResponseIncludesTopicPeers|TestSP003GroupCreateGeneratesFreshV4GroupIdsAndKeys|TestGroupGenerateNextKey_DoesNotMutateStoredKeyState' -count=1` passed (`ok github.com/mknoon/go-mknoon/bridge 0.410s`).
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/join_group_use_case_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart` passed (`+177`).
- `cd go-mknoon && go test ./bridge -count=1` passed (`ok github.com/mknoon/go-mknoon/bridge 109.198s`).
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed (`+164`).
- `dart format --set-exit-if-changed test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart` passed.
- `git diff --check -- go-mknoon/bridge/bridge_test.go test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-004-plan.md` passed.

Blocker: none.

Next allowed session after closure updates the integration breakdown: `INTEGRATE-BB-005`.

## Real Scope

Active mode is `standard integration`, not gap-closure.

Scope is exactly `INTEGRATE-BB-004`, source row `BB-004`: "Create returns a coherent group id, config, topic, group key, and epoch." The only allowed work in a future execution pass is import, reconcile, and verify row-owned BB-004 test evidence from the historical worktree closure into the main checkout.

No production files may be changed. Historical BB-004 closure is tests-only. If comparison against main proves that a production change would be needed, stop immediately and mark `blocked_conflict`; do not broaden the session.

## Closure Bar

The session is closed only when one final disposition is recorded:

- `accepted`: missing meaningful BB-004 row-owned tests or fixtures were integrated, no production files changed, focused and affected tests passed or have explicit non-BB-004 failure classification, and the integration ledger can name exact files/tests.
- `skipped_already_present`: main already contains all meaningful BB-004 row-owned proof; no code/test file is modified; evidence names exact existing anchors and verification performed.
- `blocked_conflict`: source BB-004 proof conflicts with current main or COMPLETE_1-owned behavior/files, or would require production changes; stop and map affected rows from both breakdowns.
- `blocked_external_fixture`: only if a required verification fixture outside repo control blocks proof. BB-004 is host-only, so this should be rare and must include the exact blocked command/fixture.

## Source Of Truth

- Integration row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`, row `INTEGRATE-BB-004`, currently pending integration.
- Source worktree row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`, row `BB-004`, status `Covered`.
- Source worktree breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`, session `BB-004`, status `accepted`, execution ownership `tests completed`.
- Historical plan/evidence: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-004-plan.md`.
- Main compatibility breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.

Current code/tests in main win over stale prose. Historical implementation plans are evidence only; do not recreate them.

## Session Classification

`implementation-ready` for standard integration only.

This is not a new product implementation rollout and not gap closure. It is evidence-gated until the source-vs-main comparison proves whether to accept, skip, or block.

## Exact Problem Statement

The source worktree closed BB-004 with tests proving coherent create response and first publish behavior. Main needs a one-row integration decision for that historical proof without replaying the original rollout or touching adjacent rows.

The risk is importing stale or duplicate tests into dirty main files, or widening a tests-only historical row into production behavior. The desired behavior is either exact row-owned BB-004 proof in main or a documented skip/block with concrete evidence.

## Exact Source Changed Files From BB-004 Evidence

Historical BB-004 row-owned test import candidates:

- `go-mknoon/bridge/bridge_test.go`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/create_group_use_case_test.dart`

Historical BB-004 evidence-only docs, not import candidates:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-004-plan.md`

The closure evidence says production files stayed untouched.

## Files And Repos To Inspect Next

Before any edit, inspect these source and main pairs:

- worktree `go-mknoon/bridge/bridge_test.go` against main `go-mknoon/bridge/bridge_test.go`
- worktree `test/core/bridge/bridge_group_helpers_test.dart` against main `test/core/bridge/bridge_group_helpers_test.dart`
- worktree `test/features/groups/application/create_group_use_case_test.dart` against main `test/features/groups/application/create_group_use_case_test.dart`

Also inspect:

- historical BB-004 plan closure commands and done criteria
- source worktree matrix row `BB-004`
- source worktree breakdown session `BB-004`
- main compatibility breakdown rows listed below
- current main `git status --short` for the three import-candidate test files

Planning-time observation: the three candidate test files are already modified in main, and a quick anchor scan did not find `BB-004` or `TestGroupCreate_BB004ReturnsCoherentInitialStateAndAcceptsFirstPublish` in main. Treat this as preliminary only; rerun the comparison during execution and preserve unrelated dirty changes.

## COMPLETE_1 Overlap To Inspect

Same-file overlap search in the COMPLETE_1 breakdown found no direct references to the three BB-004 import-candidate test paths. Still inspect semantic overlap before edits, especially rows whose closure could be affected by create, join, key, topic, or publish behavior:

- `GL-005`: successful join stores config and joined key snapshot atomically.
- `GP-001`: unjoined publish fails clearly.
- `GP-003`: caller-provided publish message id is preserved.
- `GP-004`: publish generates UUID when message id is empty.
- `GP-005`: zero-topic-peer publish succeeds and reports zero.
- `GP-007`: zero-peer publish has bounded wait and delegates reliability.
- `GA-001`: current private-chat member publishes and the active receiver gets exactly one message.

If a future comparison finds an actual same-file or behavior conflict, stop and write a conflict map naming the affected source `BB-004` evidence and the exact COMPLETE_1 rows/tests before any code or test merge.

## Existing Tests Covering This Area

Historical BB-004 evidence added:

- Go native bridge test `TestGroupCreate_BB004ReturnsCoherentInitialStateAndAcceptsFirstPublish`.
- Dart helper test with `BB-004` in `bridge_group_helpers_test.dart`.
- Flutter create-use-case test with `BB-004` in `create_group_use_case_test.dart`.

Main currently has nearby create/key/publish tests in the same files, but the BB-004 row-owned anchors must be compared against source before deciding to import or skip.

## Regression/Tests To Add First

Do not add new regressions from scratch.

If missing from main, integrate only the meaningful historical BB-004 row-owned tests from the three source test files. Do not add new assertions beyond what is required to reconcile those historical tests with current main APIs and fixtures.

If BB-004 proof is already present under equivalent anchors, add no code/test edits and use `skipped_already_present`.

## Step-By-Step Implementation Plan

1. Re-read the source matrix row, source breakdown session, historical plan/evidence, and exact three source test files.
2. Re-read the three main target files and run a local diff against the worktree versions, scoped to BB-004 anchors and surrounding helper fixtures.
3. Inspect current main dirty changes in those files and preserve them.
4. Inspect COMPLETE_1 overlap candidates and decide whether any row-owned behavior or test fixture conflicts with the BB-004 source proof.
5. If all BB-004 proof is already present in main, modify no code/test files and prepare `skipped_already_present` ledger evidence.
6. If proof is partially present, integrate only the missing BB-004 test blocks or row-owned helper fixture adjustments needed by those tests.
7. If comparison shows a production requirement, same-file ownership conflict, incompatible fixture expectation, or semantic conflict with COMPLETE_1 rows, stop as `blocked_conflict`.
8. Run the focused historical BB-004 tests plus any affected main/COMPLETE_1 tests.
9. Record one final ledger disposition using the contract in this plan. Do not proceed to `BB-005`.

## Risks And Edge Cases

- Main target test files are already dirty. Do not overwrite unrelated work.
- Historical BB-004 accepted native `GroupCreate` omitting `topicName` because Flutter canonical fallback `/mknoon/group/<groupId>` was proven. Do not convert that accepted difference into a production change.
- First publish in a single-node host proof may report `topicPeers == 0`; BB-004 requires `ok: true` and a non-empty message id, not live multi-peer delivery.
- Go and Flutter create timestamps are independent; do not add timestamp equality checks.
- COMPLETE_1 semantic overlap is mostly Go node publish/join behavior, not the exact BB-004 bridge/helper/create-use-case files. A conflict must be concrete, not speculative.

## Exact Tests And Gates To Run

Historical focused BB-004 tests:

```bash
cd go-mknoon && go test ./bridge -run 'TestGroupCreate_BB004ReturnsCoherentInitialStateAndAcceptsFirstPublish' -count=1
```

```bash
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name "BB-004"
```

```bash
flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart --plain-name "BB-004"
```

Historical direct/backstop tests:

```bash
cd go-mknoon && go test ./bridge -run 'TestGroupCreate_BB004ReturnsCoherentInitialStateAndAcceptsFirstPublish|TestGroupPublish_ResponseIncludesTopicPeers|TestSP003GroupCreateGeneratesFreshV4GroupIdsAndKeys|TestGroupGenerateNextKey_DoesNotMutateStoredKeyState' -count=1
```

```bash
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/join_group_use_case_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart
```

Required host smoke and hygiene:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

```bash
cd go-mknoon && go test ./bridge -count=1
```

```bash
git diff --check
```

If a COMPLETE_1 overlap becomes affected, also run the row-owned selector(s) from that COMPLETE_1 row plan or the narrowest equivalent main selector, then record why they were needed.

## Known-Failure Interpretation

Any failure in a BB-004-named test is blocking.

A failure in create, helper routing, local group/member/key persistence, first publish, or canonical topic fallback is presumed related until proven otherwise.

Unrelated pre-existing failures may be recorded, but `accepted` cannot be used unless BB-004 proof itself is green and affected main/COMPLETE_1 tests are either green or classified with concrete non-BB-004 evidence.

## Done Criteria

- Exactly one row is resolved: `INTEGRATE-BB-004`.
- No `BB-005` planning, comparison, import, or ledger work is performed.
- No production files are changed.
- Imported tests, if any, are limited to missing meaningful BB-004 row-owned proof.
- If no import is needed, no code/test file is modified.
- Conflicts stop the session and include a row map from both breakdowns.
- Final ledger status is one of `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture`.

## Scope Guard

Do not modify production files.

Do not modify the integration breakdown while creating this plan artifact. A future execution/closure pass may update only the final `INTEGRATE-BB-004` ledger entry after proof is complete.

Do not recreate, rewrite, or rerun the original worktree implementation plan.

Do not copy source closure docs into main as implementation evidence. Use them only to identify what tests and commands were historically accepted.

Do not add relay, fake-network, simulator, real-device, UI, notification, media, security, membership lifecycle, or adjacent delivery behavior.

## Accepted Differences / Intentionally Out Of Scope

- Native `GroupCreate` may omit `topicName`; BB-004 historical closure accepted Flutter canonical topic fallback proof instead.
- BB-004 is host-only. Device-lab, relay, fake-network, real-network, simulator, and 3-party proof were not run or claimed historically and are not required for this integration row.
- Durable send queue behavior is not part of BB-004; first publish acceptance is proven at the native bridge/helper boundary.

## Dependency Impact

BB-004 coherent create state is a prerequisite assumption for later create/join/rejoin/key rows, but this integration session must not repair later rows. If BB-004 blocks, record the blocker so later rows can pause or map the prerequisite instead of compensating locally.
