Status: execution-ready

# DIF-001 - Folded Projection Contract Plan

## Planning Progress

- 2026-05-06 18:40 CEST - Role: Arbiter completed. Files inspected since last update: reviewer findings and final plan artifact. Decision/blocker: no structural blockers remain; DIF-001 plan is execution-ready with direct projection tests as closure. Next action: hand off plan path; no implementation or tests were run in planning.
- 2026-05-06 18:40 CEST - Role: Arbiter started. Files inspected since last update: reviewer findings and adjusted plan wording. Decision/blocker: no obvious structural blocker; classify reviewer adjustment and accepted out-of-scope work before finalizing. Next action: write arbiter decision and set execution-ready status if no structural blocker remains.
- 2026-05-06 18:40 CEST - Role: Reviewer completed. Files inspected since last update: drafted plan content only. Decision/blocker: sufficient with one clarity adjustment: action-state fields should be factual projection data first, with final UI/action execution left to later sessions; no structural blocker found. Next action: run arbiter classification and decide final status.
- 2026-05-06 18:40 CEST - Role: Reviewer started. Files inspected since last update: drafted DIF-001 plan sections and heading inventory. Decision/blocker: mandatory sections are present; review will check action-state wording, direct-test/gate contract, and scope boundaries for hidden DIF-002 through DIF-005 leakage. Next action: record sufficiency findings and patch only structural or clarity gaps.
- 2026-05-06 18:40 CEST - Role: Planner completed. Files inspected since last update: no new files; draft built from collected evidence. Decision/blocker: draft is implementation-ready if reviewer accepts that DIF-001 owns projection/tests only and defers counts, actions, UI, and simulator proof. Next action: run sufficiency review against mandatory sections, gates, scope guard, and closure bar.

## Execution Progress

- 2026-05-06 18:48 CEST - Phase: controller contract extraction completed. Files inspected: this DIF-001 plan, source matrix row `DIF-001`, implementation-orchestrator skill, current owner-file git status. Decision/blocker: scope is projection-only in the introduction application layer; required direct gate is `flutter test test/features/introduction/application/load_introductions_test.dart`; source row update is allowed only after implementation and direct evidence satisfy closure. Next action: spawn Executor.
- 2026-05-06 18:49 CEST - Phase: Executor spawn starting. Files inspected/touched: this plan progress section only. Command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app`. Decision/blocker: spawned-agent path is available through the local Codex CLI. Next action: Executor adds RED projection tests first, lands smallest projection helper/model, and runs required direct tests.
- 2026-05-06 18:50 CEST - Phase: Executor spawn retry. Files inspected/touched: this plan progress section only. Command result: first spawn attempt exited before child work because `--ask-for-approval` was passed to the `exec` subcommand instead of the top-level CLI. Decision/blocker: no child code/test/doc delta occurred; relaunch with corrected CLI option placement. Next action: spawn Executor again.
- 2026-05-06 18:50 CEST - Phase: Executor owner-file inspection started. Files inspected: this DIF-001 plan, `lib/features/introduction/application/load_introductions_use_case.dart`, `test/features/introduction/application/load_introductions_test.dart`, `lib/features/introduction/domain/models/introduction_model.dart`, `test/shared/fakes/in_memory_introduction_repository.dart`. Decision/blocker: contract is executable with projection-only tests in the existing load-introductions suite; raw loader/grouping compatibility must be preserved. Next action: add RED folded projection tests before production changes.
- 2026-05-06 18:53 CEST - Phase: RED projection tests captured. Files touched: `test/features/introduction/application/load_introductions_test.dart`. Command: `flutter test test/features/introduction/application/load_introductions_test.dart`. Result: failed as expected with `Method not found: 'foldIntroductionsForReview'` in the new projection tests. Decision/blocker: expected TDD red only; proceed to smallest application-layer projection implementation. Next action: update `load_introductions_use_case.dart`.
- 2026-05-06 18:55 CEST - Phase: implementation completed. Files touched: `lib/features/introduction/application/load_introductions_use_case.dart`, `test/features/introduction/application/load_introductions_test.dart`. Decision/blocker: added pure `foldIntroductionsForReview` projection plus folded review item/introducer attribution types; raw `loadIntroductionsForUser(...)` and `groupByIntroducer(...)` remain raw. Next action: run required direct test command.
- 2026-05-06 18:55 CEST - Phase: direct tests completed. Files touched: this plan progress section only. Command: `flutter test test/features/introduction/application/load_introductions_test.dart`. Result: pass, `+12`, all tests passed. Decision/blocker: no Executor blocker from required direct evidence. Next action: hand off for separate QA Reviewer; do not update source matrix row in Executor pass.
- 2026-05-06 18:56 CEST - Phase: QA Reviewer spawn starting. Files inspected/touched: this plan progress section and Executor handoff summary. Command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app`. Decision/blocker: Executor completed with scoped code/test/doc delta and direct test evidence. Next action: QA Reviewer checks scope adherence, behavior, required tests, and done criteria without fixing code.
- 2026-05-06 18:57 CEST - Phase: QA Reviewer started. Files inspected: this DIF-001 plan, Executor handoff summary, current git status. Decision/blocker: review-only scope confirmed; required closure command remains `flutter test test/features/introduction/application/load_introductions_test.dart`. Next action: inspect landed diffs and run the direct test.
- 2026-05-06 18:58 CEST - Phase: QA Reviewer completed. Files inspected/touched: `lib/features/introduction/application/load_introductions_use_case.dart`, `test/features/introduction/application/load_introductions_test.dart`, this plan progress section. Command: `flutter test test/features/introduction/application/load_introductions_test.dart`. Result: pass, `+12`, all tests passed. Decision/blocker: no blocking issues; DIF-001 projection contract and scope guard satisfied. Next action: parent handles final source matrix/breakdown closure.
- 2026-05-06 18:59 CEST - Phase: final verdict written. Files touched: this plan file and source matrix row `DIF-001` in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`. Decision/blocker: no blockers remain; source row marked `Closed` with direct test evidence. Next action: stop this one-session execution.

## Execution Verdict

Final verdict: accepted.

Spawned-agent isolation used: yes. Executor and QA Reviewer ran as separate `codex exec` processes with `model: gpt-5.5` and `model_reasoning_effort="xhigh"`.

Local sequential fallback used: no.

Files changed:

- `lib/features/introduction/application/load_introductions_use_case.dart`
- `test/features/introduction/application/load_introductions_test.dart`
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-001-plan.md`
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` row `DIF-001`

Exact tests and gates run:

- Executor RED: `flutter test test/features/introduction/application/load_introductions_test.dart` failed as expected with `Method not found: 'foldIntroductionsForReview'`.
- Executor green: `flutter test test/features/introduction/application/load_introductions_test.dart` passed, `+12`.
- QA green: `flutter test test/features/introduction/application/load_introductions_test.dart` passed, `+12`.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none.

Why this session is safe to consider complete: the projection helper/model exists in the introduction application layer, focused tests cover the DIF-001 folding, target resolution, newest-row fallback, current-viewer action-state, and persisted-row compatibility contract, raw loader/grouping behavior remains raw and green, and no count, action, UI, wiring, simulator, repository, or migration scope was implemented.

## real scope

DIF-001 owns one application-level folded introduction review projection over existing raw `IntroductionModel` rows. The implementation should add a small projection model/helper near `lib/features/introduction/application/load_introductions_use_case.dart`, or in a new adjacent application file if that keeps the raw loader file readable.

The projection must:

- resolve the current viewer's target peer with `recipientId == ownPeerId ? introducedId : recipientId`
- fold active raw rows by that target peer across multiple introducers
- preserve every underlying introduction id, raw `IntroductionModel`, introducer id, and introducer display name attribution
- expose enough display fallback state for later UI sessions, including target peer id/name fields and a deterministic newest-row fallback
- expose factual current-viewer action state without applying actions, including which underlying rows are still pending for the current viewer and which rows are already accepted or passed
- treat existing persisted rows that deserialize through `IntroductionModel.fromMap` as valid input
- avoid mutating, deleting, merging, rewriting, or migrating raw introduction rows

The existing raw APIs remain raw in this session unless a tiny wrapper is needed:

- `loadIntroductionsForUser(...)` should continue returning raw `List<IntroductionModel>` for existing callers and tests.
- `groupByIntroducer(...)` should continue working for current tests and legacy call sites until later UI sessions replace sender grouping.

## closure bar

DIF-001 is good enough when an implementer can prove, with focused application tests, that duplicate active introductions for the same viewer target fold to one projection item while unrelated targets remain separate, both recipient-side and introduced-side viewers resolve the correct target, newest-row ordering only affects display fallback, and upgrade-style deserialized persisted rows keep all raw ids/statuses/attribution/pending decisions intact without mutation.

No UI, badge, group action, database migration, simulator, relay, or device proof is required for this session unless implementation unexpectedly adds those dependencies.

## source of truth

Authoritative inputs:

- Current code and tests win over stale prose.
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` defines the fold, display, action, count, and upgrade contracts; DIF-001 uses only the projection and upgrade portions.
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md` defines DIF-001 scope, expected plan path, dependencies, and expected docs update.
- `lib/features/introduction/application/load_introductions_use_case.dart` is the current application loading seam.
- `lib/features/introduction/domain/models/introduction_model.dart` is the persisted row model and serialization contract.
- `test/features/introduction/application/load_introductions_test.dart` is the preferred direct projection test file unless a new adjacent projection suite is clearer.
- `scripts/run_test_gates.sh` is the gate execution source of truth when it disagrees with `Test-Flight-Improv/test-gate-definitions.md`.

## session classification

`implementation-ready`

No prerequisite session is required. DIF-002, DIF-003, DIF-004, and DIF-005 depend on this projection contract after it exists.

## exact problem statement

The shipped application loads raw active introduction rows and groups them by introducer. When two different introducers introduce the current viewer to the same target peer, downstream review surfaces can present duplicate rows and duplicate decisions for the same person.

For DIF-001, the missing piece is not UI rendering or action execution. The missing piece is a stable application projection that folds duplicate active rows by the current viewer's target peer while preserving the raw rows for compatibility and later group actions. Upgraded users with rows already persisted by the current shipped build must see valid folded projection input after `IntroductionModel.fromMap(...)`; no migration-time merge or deletion is allowed.

Behavior that must stay unchanged:

- Raw loader behavior remains available.
- Repository SQL and in-memory fake behavior stay raw.
- Existing pending/alreadyConnected inclusion rules stay intact.
- Existing accept/pass, mutual acceptance, contact creation, and outbound response behavior are not changed in this session.

## files and repos to inspect next

Primary owner files:

- `lib/features/introduction/application/load_introductions_use_case.dart`
- Optional new adjacent file: `lib/features/introduction/application/folded_introduction_projection.dart`
- `test/features/introduction/application/load_introductions_test.dart`
- Optional new adjacent suite: `test/features/introduction/application/folded_introduction_projection_test.dart`

Read-only context files to re-check if implementation details are unclear:

- `lib/features/introduction/domain/models/introduction_model.dart`
- `lib/core/database/helpers/introductions_db_helpers.dart`
- `test/shared/fakes/in_memory_introduction_repository.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

Dirty-worktree handling:

- Current observed dirty file before this plan was created: `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`.
- Treat that change as user-owned. Do not revert it.
- Before implementation, run `git status --short`; preserve any unrelated dirty files and avoid broad formatting churn.

## existing tests covering this area

Existing direct tests:

- `test/features/introduction/application/load_introductions_test.dart` covers raw `loadIntroductionsForUser(...)` returning pending rows for recipient/introduced users and `groupByIntroducer(...)` grouping by introducer id.
- `test/features/introduction/application/handle_incoming_introduction_test.dart` covers `alreadyConnected` serialization, loader inclusion, and pending badge exclusion at repository level.
- `test/features/introduction/application/edge_cases_test.dart` covers repository pending filtering by status.
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart` covers current Orbit intro wiring expectations around raw loading, introducer grouping, counts, accept/pass, delete, and stream refresh.

Missing tests for DIF-001:

- No test folds two introducers for the same target into one projection item.
- No test proves different targets remain separate when introducer is the same or different.
- No test proves recipient-side and introduced-side viewer target resolution.
- No test proves newest row affects only display fallback, not fold membership.
- No upgrade-style test deserializes existing persisted row maps through `IntroductionModel.fromMap(...)` and verifies projection compatibility without mutation.

## regression/tests to add first

Add failing projection tests before production code. Prefer a new `group('foldIntroductionsForReview')` in `test/features/introduction/application/load_introductions_test.dart` if the projection lives in `load_introductions_use_case.dart`; use a new adjacent folded projection suite if a new production helper file is created.

Required cases:

- Two active pending rows from two introducers to the same target fold into one item; the item exposes both intro ids and both introducer names.
- Rows for different target peers remain separate even if the current viewer and/or introducer overlap.
- Current viewer as `recipientId` resolves target from `introducedId`; current viewer as `introducedId` resolves target from `recipientId`.
- Newest row only drives target/display fallback ordering or representative display fields; all fold members remain present regardless of age.
- A row where the current viewer has already accepted/passed is represented in factual action-state fields so later UI/action sessions do not incorrectly ask for the same decision again; pending rows remain visible in the preserved underlying ids/statuses.
- Upgrade-style fixture: build raw row maps matching existing persisted introduction columns, deserialize with `IntroductionModel.fromMap(...)`, project them, and assert raw `toMap()` snapshots are unchanged and no ids/statuses/introducer names/pending decisions are lost.

These tests prove the application projection seam directly and avoid pulling UI or repository count semantics into DIF-001.

## step-by-step implementation plan

1. Add the failing projection tests listed above. Keep existing raw loader and `groupByIntroducer(...)` assertions in place to guard compatibility.
2. Add a small immutable folded projection type, for example `FoldedIntroductionReviewItem`, with fields for `targetPeerId`, display fallback data, raw `introductions`, `introductionIds`, introducer attribution, current-viewer pending decision ids, and a conservative action/display state.
3. Add a pure projection helper, for example `foldIntroductionsForReview({required List<IntroductionModel> introductions, required String ownPeerId})`.
4. In the helper, discard rows where `ownPeerId` is neither `recipientId` nor `introducedId`, and only fold active review rows with `status == pending` or `status == alreadyConnected` unless the function is documented as accepting only loader output. Prefer defensive filtering because the upgrade fixture calls the helper directly.
5. Resolve each row's target peer from the viewer perspective and group by target peer id, not introducer id.
6. Sort each fold deterministically by parsed `createdAt` descending, with a stable fallback tie-breaker by id for malformed or equal timestamps. Use the newest row only for representative display fallback fields; never use it to drop older members.
7. Preserve attribution in first-seen or deterministic display order, deduplicating repeated introducer ids/names without losing the raw rows. Missing names should use the existing local fallback style such as `Unknown`, not add UI copy beyond what later UI sessions own.
8. Derive current-viewer decision state from the correct side of each raw row: `recipientStatus` when `ownPeerId == recipientId`, `introducedStatus` when `ownPeerId == introducedId`. Prefer factual fields such as `pendingDecisionIntroIds`, `acceptedDecisionIntroIds`, `passedDecisionIntroIds`, `hasCurrentViewerResponded`, and `hasPendingCurrentViewerDecision`; any convenience `isActionable` must be derived from those fields and must not replace the underlying ids/statuses that DIF-003 needs.
9. Keep `loadIntroductionsForUser(...)` returning raw rows. If useful, add `loadFoldedIntroductionsForUser(...)` as a thin wrapper that loads raw rows and calls the pure projection helper, but do not update Orbit or Feed call sites in this session.
10. Stop and reclassify as `stale/already-covered` only if implementation discovers an equivalent folded projection already exists and tests can bind to it without adding duplicate architecture.

## risks and edge cases

- Viewer-side ambiguity: the same raw row must resolve target and current-viewer party status differently for recipient versus introduced users.
- Mixed current-viewer statuses inside one fold can cause repeated Accept/Pass prompts if action state ignores already accepted/passed rows.
- `alreadyConnected` rows are active for review visibility but should not be treated like pending badge/action rows.
- Deserialized persisted rows may have null usernames or key fields; projection must preserve raw data and use bounded fallbacks without requiring migrations.
- `createdAt` ordering currently comes from SQL as descending, but in-memory tests and direct helper inputs should not depend on repository ordering.
- Duplicate introducer names or ids should not hide underlying intro ids.
- No pause/resume, offline/online, relay, simulator, notification, or device lifecycle dependency was found for DIF-001.

## exact tests and gates to run

Direct tests for this session:

```bash
flutter test test/features/introduction/application/load_introductions_test.dart
```

If implementation creates a new adjacent projection suite instead:

```bash
flutter test test/features/introduction/application/folded_introduction_projection_test.dart
flutter test test/features/introduction/application/load_introductions_test.dart
```

Compatibility companion if the projection helper is imported by Orbit tests during this session:

```bash
flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart
```

Named gate contract:

- Do not run gates during planning.
- For DIF-001 implementation, the direct application test command above is the required closure gate.
- `./scripts/run_test_gates.sh intro` is named by the breakdown for later integrated sessions and should be run after UI/action/count integration or during DIF-007 closure, not as a blocker for this projection-only session unless implementation unexpectedly touches send, accept, pass, listener, intro picker, or repository behavior.

## known-failure interpretation

This planning session intentionally did not run tests.

For implementation:

- A newly added projection test should fail before production code because the helper/model does not exist or does not fold; that is the expected TDD red.
- Existing raw-loader tests in `load_introductions_test.dart` must stay green after implementation.
- If `load_introductions_test.dart` has a pre-existing unrelated failure before adding projection tests, record the failure separately and do not classify it as a DIF-001 regression.
- If `orbit_intros_wiring_test.dart` is run only because a helper is imported there, failures outside pure projection/load grouping should be classified as later DIF-004/DIF-005 scope unless caused by DIF-001 edits.
- Intro gate failures are not DIF-001 blockers unless the implementation broadened into intro send/accept/pass/listener/picker/repository behavior.

## done criteria

- A folded projection type/helper exists in the introduction application layer.
- Focused projection tests prove same-target folding, different-target separation, recipient-side and introduced-side resolution, newest-row display fallback without membership loss, current-viewer decision-state preservation, and upgrade-style persisted-row compatibility.
- Existing raw `loadIntroductionsForUser(...)` and `groupByIntroducer(...)` tests still pass.
- No raw `IntroductionModel` rows are mutated, merged, deleted, or rewritten by projection code.
- No database migration or repository schema/query change is introduced.
- No UI, badge, group action, simulator, relay, or device proof is added.
- Source matrix row `DIF-001` is updated after implementation with the direct test evidence and final status.

## scope guard

Non-goals for DIF-001:

- Do not change `countPendingIntroductions(...)` or badge semantics; that is DIF-002.
- Do not add folded Accept/Pass use cases or processing suppression; that is DIF-003/DIF-005.
- Do not update `IntrosTab`, `OrbitScreen`, sender headers, or visible copy; that is DIF-004.
- Do not update `OrbitWired` or `FeedWired` production flows; that is DIF-005 unless only a no-op import/export adjustment is necessary.
- Do not add simulator scenarios, smoke scripts, or four-identity device proof; that is DIF-006.
- Do not run full regression/documentation closure; that is DIF-007.
- Do not add a DB migration, new repository schema, raw-row merge table, background repair job, or cache invalidation layer.

Overengineering signals:

- A generalized cross-feature folding framework.
- New persistence for folded groups.
- Changes to single-intro accept/pass logic.
- UI copy/layout implementation in the projection session.
- Treating malformed persisted rows as a migration problem instead of preserving valid current `IntroductionModel` rows.

## accepted differences / intentionally out of scope

- The projection can expose a compact introducer attribution structure rather than final UI strings; final copy belongs to DIF-004.
- The projection can expose pending/action-state ids without executing group actions; action execution belongs to DIF-003.
- Raw repository counts may still count raw pending rows after DIF-001; folded count behavior belongs to DIF-002.
- Orbit may continue rendering grouped raw intros until DIF-004/DIF-005 consume the projection.
- No device/relay proof profile is attached because DIF-001 is pure application projection and direct unit/widget-testable code.

## dependency impact

- DIF-002 should reuse the same target-resolution/folding logic or an intentionally shared counting helper so badge counts do not drift from projection semantics.
- DIF-003 should consume the fold's underlying ids and current-viewer pending decision ids for group accept/pass.
- DIF-004 should render one row per folded item and use the projection's attribution/display fallback.
- DIF-005 should wire processing and badge state to folded ids/counts after DIF-002 through DIF-004 exist.
- DIF-006 and DIF-007 should not be attempted as closure evidence until this projection contract is stable.

If DIF-001 changes the projection type name or field names during implementation, later session plans must bind to the final names rather than inventing parallel helpers.

## expected docs updates

After implementation and verification, update the source matrix row `DIF-001` in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` with the final status and direct test evidence. If the session pipeline tracks status in the breakdown artifact, update only the DIF-001 entry/ledger without rewriting unrelated dirty content.

## reviewer pass

Verdict: sufficient with adjustments.

Findings:

- Mandatory sections are present.
- Regression-first rule is explicit and points to the direct application suite.
- The named gate contract matches the breakdown: direct tests close DIF-001; `./scripts/run_test_gates.sh intro` is deferred to later integrated sessions unless scope broadens.
- Scope guard prevents DIF-002 count work, DIF-003 actions, DIF-004 UI, DIF-005 wiring, DIF-006 simulator proof, and DIF-007 closure.
- Adjustment applied: action-state wording now emphasizes factual projection fields and leaves final UI/action execution policy to later sessions.

Missing files, tests, regressions, or gates: none structural.

Stale or incorrect assumptions: none found from inspected evidence.

Overengineering: none after action-state wording was narrowed to projection data.

Minimum needed to implement safely: follow the direct projection tests first, keep raw loader behavior unchanged, and update only DIF-001 docs after verification.

## evidence used

- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`
- `lib/features/introduction/application/load_introductions_use_case.dart`
- `lib/features/introduction/domain/models/introduction_model.dart`
- `lib/core/database/helpers/introductions_db_helpers.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
- `test/shared/fakes/in_memory_introduction_repository.dart`
- `test/features/introduction/application/load_introductions_test.dart`
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/features/introduction/application/edge_cases_test.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## arbiter decision

Structural blockers: none.

Incremental details:

- Concrete projection type and field names may differ from the examples if implementation keeps the same contract and tests prove it.
- `./scripts/run_test_gates.sh intro` remains a later integrated-session/DIF-007 gate unless DIF-001 implementation expands beyond projection-only application code.

Accepted differences:

- Final UI strings, Orbit rendering, badge counts, group Accept/Pass, simulator proof, and full closure are intentionally not implemented or required in DIF-001.
- Raw repository loader/count semantics may remain raw after this session; later sessions will consume or extend the projection contract.

Final verdict: execution-ready. The plan is safe to implement now because it has a narrow projection-only scope, explicit owner files, regression-first tests, direct test commands, dirty-worktree handling, expected docs updates, known-failure interpretation, and a stop rule for stale/already-covered evidence.
