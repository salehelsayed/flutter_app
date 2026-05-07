# DIF-004 - Folded Intro Review UI Rendering Plan

Status: execution-ready

## Planning Progress

- `2026-05-06 20:09 CEST` - Planner completed. Files inspected since last update: evidence set above plus `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`. Decision/blocker: draft keeps legacy raw grouped constructors as compatibility fallbacks and adds folded item rendering paths for `IntrosTab` and `OrbitScreen`; no blocker. Next action: reviewer sufficiency pass.
- `2026-05-06 20:11 CEST` - Reviewer started. Files inspected since last update: full draft plan. Decision/blocker: review focused on scope drift, test sufficiency, bridge safety for `DIF-005`, and whether optional folded paths are enough for this pure UI session. Next action: record sufficiency findings.
- `2026-05-06 20:11 CEST` - Reviewer completed. Files inspected since last update: full draft plan. Decision/blocker: sufficient as-is; no structural blocker. One incremental detail remains: execution may choose exact attribution delimiter, but tests should assert both names rather than a delimiter. Next action: arbiter classification.
- `2026-05-06 20:11 CEST` - Arbiter started. Files inspected since last update: reviewer pass and full draft plan. Decision/blocker: classify reviewer finding and decide whether a fix loop is required. Next action: record final arbiter verdict.
- `2026-05-06 20:11 CEST` - Arbiter completed. Files inspected since last update: reviewer pass and full draft plan. Decision/blocker: no structural blockers; no fix loop required. Next action: mark plan execution-ready.

## Execution Progress

- `2026-05-06 20:29 CEST` - Orchestrator final verdict recorded. Files inspected or touched: this plan and `git status --short`. Command/result: no additional tests run after QA; Executor direct GREEN commands and `./scripts/run_test_gates.sh intro` are recorded green below, and QA targeted owner-suite rerun passed with `+41`. Decision/blocker: final verdict `Accepted` for session `DIF-004`; no fix pass required; source matrix row `DIF-004`, later source rows, and the session breakdown remain open/pending per this plan's source-matrix closure guard.
- `2026-05-06 20:29 CEST` - QA Reviewer completed. Files inspected or touched: this plan's `## Execution Progress`, scoped diffs for `intro_row.dart`, `intros_tab.dart`, `orbit_screen.dart`, the four DIF-004 widget test files, `load_introductions_use_case.dart`, source matrix row statuses, and session ledger statuses. Command/result: `flutter test test/features/introduction/presentation/widgets/intro_row_test.dart test/features/introduction/presentation/widgets/intros_tab_test.dart test/features/introduction/presentation/widgets/intros_tab_extended_test.dart test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart` passed with `+41`. Decision/blocker: no blocking issues found; RED and GREEN evidence are present, folded UI renders one row with multi-introducer attribution, raw grouped fallbacks still compile, folded callbacks remain display-source raw-id scoped, `DIF-004` and later source rows remain open/pending. Next action: return QA accepted verdict without closing docs or source matrix rows.
- `2026-05-06 20:26 CEST` - QA Reviewer local inspection started. Files inspected or touched: this plan, `git status --short`, `$implementation-execution-qa-orchestrator` instructions. Command running: none. Decision/blocker: beginning scoped QA review of DIF-004 owner diffs, RED/GREEN evidence, folded rendering behavior, raw-id action semantics, and scope guard compliance. Next action: inspect scoped diff and relevant production/test files without editing source or test code.
- `2026-05-06 20:26 CEST` - QA Reviewer spawned/running. Files inspected or touched: this plan, `git status --short`, `git diff --name-only`; command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...`. Decision/blocker: Executor evidence is present and green; next action: wait for separate QA sufficiency review.
- `2026-05-06 20:26 CEST` - Executor completed final scope check and handoff. Files inspected or touched: `git status --short`, `git diff --name-only`, scoped diff for this session's owner files and plan. Command running: none. Decision/blocker: this session touched only the DIF-004 owner production files, required widget tests, and this session plan; unrelated dirty files from earlier sessions remain untouched; source matrix row `DIF-004` was not closed. Next action: return Executor summary for QA Reviewer handoff.
- `2026-05-06 20:25 CEST` - Executor completed named intro gate. Files inspected or touched: no new edits. Command/result: `./scripts/run_test_gates.sh intro` passed with exit code 0 and final `All tests passed!` output. Decision/blocker: no gate blocker; next action: final scope check and Executor completion evidence.
- `2026-05-06 20:25 CEST` - Executor started named intro gate. Files inspected or touched: no new edits. Command running: `./scripts/run_test_gates.sh intro`. Decision/blocker: feasible to run locally; next action: record exact gate result.
- `2026-05-06 20:25 CEST` - Executor completed required direct GREEN tests. Files inspected or touched: no new edits. Commands/results: `flutter test test/features/introduction/presentation/widgets/intro_row_test.dart` passed; `flutter test test/features/introduction/presentation/widgets/intros_tab_test.dart` passed; `flutter test test/features/introduction/presentation/widgets/intros_tab_extended_test.dart` passed; `flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart` passed; `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` passed; `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart` passed; `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"` passed; `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"` passed. Decision/blocker: direct folded UI, Orbit compatibility, and badge companion tests are green; next action: run named intro gate.
- `2026-05-06 20:25 CEST` - Executor started required direct GREEN tests. Files inspected or touched: no new edits. Command running: direct `flutter test` commands from this plan. Decision/blocker: run exact required commands in order and record each pass/fail before named gate.
- `2026-05-06 20:24 CEST` - Executor completed implementation and formatting. Files inspected or touched: `lib/features/introduction/presentation/widgets/intro_row.dart`, `lib/features/introduction/presentation/widgets/intros_tab.dart`, `lib/features/orbit/presentation/screens/orbit_screen.dart`, `test/features/introduction/presentation/widgets/intro_row_test.dart`, `test/features/introduction/presentation/widgets/intros_tab_test.dart`, `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`, `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`. Command/result: `dart format lib/features/introduction/presentation/widgets/intro_row.dart lib/features/introduction/presentation/widgets/intros_tab.dart lib/features/orbit/presentation/screens/orbit_screen.dart test/features/introduction/presentation/widgets/intro_row_test.dart test/features/introduction/presentation/widgets/intros_tab_test.dart test/features/introduction/presentation/widgets/intros_tab_extended_test.dart test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart` passed. Decision/blocker: folded row bridge is landed with raw grouped fallback intact and raw display-source action/delete ids preserved; next action: run required direct GREEN commands.
- `2026-05-06 20:22 CEST` - Executor started implementation. Files inspected or touched: `lib/features/introduction/presentation/widgets/intro_row.dart`, `lib/features/introduction/presentation/widgets/intros_tab.dart`, `lib/features/orbit/presentation/screens/orbit_screen.dart`. Command running: none. Decision/blocker: implementing optional folded inputs only, preserving raw grouped fallback and legacy raw-id callbacks; next action: patch production files.
- `2026-05-06 20:21 CEST` - Executor completed RED test run. Files inspected or touched: direct widget tests only. Commands/results: `flutter test test/features/introduction/presentation/widgets/intro_row_test.dart --plain-name "shows multiple introducer attributions in one row"` failed as expected with `No named parameter with the name 'introducerAttributionNames'` on `IntroRow`; `flutter test test/features/introduction/presentation/widgets/intros_tab_test.dart --plain-name "renders duplicate aboza introductions as one folded review row"` failed as expected with `No named parameter with the name 'foldedReviewItems'` on `IntrosTab`; `flutter test test/features/introduction/presentation/widgets/intros_tab_extended_test.dart --plain-name "folded attribution falls back for blank introducer names and keeps long names actionable"` failed as expected with `No named parameter with the name 'foldedReviewItems'` on `IntrosTab`; `flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart --plain-name "renders duplicate aboza introductions as one folded row in the active intros sliver"` failed as expected with `No named parameter with the name 'foldedReviewItems'` on `OrbitIntrosViewData`. Decision/blocker: RED is valid for missing folded UI bridge; next action: implement the smallest folded rendering bridge in owner production files.
- `2026-05-06 20:20 CEST` - Executor started RED test run. Files inspected or touched: direct widget tests only. Command running: four required `flutter test --plain-name` RED commands. Decision/blocker: expecting failures from missing folded UI constructor/rendering support; next action: record each command result before production edits.
- `2026-05-06 20:19 CEST` - Executor completed RED test authoring. Files inspected or touched: `test/features/introduction/presentation/widgets/intro_row_test.dart`, `test/features/introduction/presentation/widgets/intros_tab_test.dart`, `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`, `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`. Command running: none. Decision/blocker: required folded row tests added before production edits; next action: run the four exact RED `flutter test --plain-name` commands and record results.
- `2026-05-06 20:17 CEST` - Executor started RED test authoring. Files inspected or touched: direct widget tests only. Command running: none. Decision/blocker: tests will use `foldIntroductionsForReview(...)` and intentionally reference folded UI inputs before production edits; next action: add the four required failing widget tests.
- `2026-05-06 20:16 CEST` - Executor completed owner inspection. Files inspected or touched: `lib/features/introduction/presentation/widgets/intro_row.dart`, `lib/features/introduction/presentation/widgets/intros_tab.dart`, `lib/features/orbit/presentation/screens/orbit_screen.dart`, `lib/features/introduction/application/load_introductions_use_case.dart`, `test/features/introduction/presentation/widgets/intro_row_test.dart`, `test/features/introduction/presentation/widgets/intros_tab_test.dart`, `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`, `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`, `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`, `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`. Command running: none. Decision/blocker: current UI has only raw grouped rows and single introducer attribution; folded projection has the needed target, attribution, and raw display-source fields; no blocker. Next action: add the required RED widget tests before production edits.
- `2026-05-06 20:15 CEST` - Executor started owner inspection. Files inspected or touched: this plan. Command running: none. Decision/blocker: following the existing execution contract locally as the Executor pass; next action: inspect owner production files, read-only projection dependency, and direct widget tests before edits.
- `2026-05-06 20:13 CEST` - Orchestrator started contract extraction. Files inspected or touched: this plan, `git status --short`; command running: none. Decision/blocker: spawned sub-agent path is available through `codex exec`; next action: extract contract and spawn Executor.
- `2026-05-06 20:13 CEST` - Contract extracted. Files inspected or touched: this plan, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`; command running: none. Decision/blocker: scope is folded UI rendering only in `IntroRow`, `IntrosTab`, `OrbitScreen`, and direct widget tests; RED commands, direct GREEN commands, and `./scripts/run_test_gates.sh intro` are explicit; next action: spawn Executor for tests-first implementation.
- `2026-05-06 20:14 CEST` - Executor spawned/running. Files inspected or touched: this plan; command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...`. Decision/blocker: no blocker; next action: wait for Executor completion evidence and inspect required file/test deltas.
- `2026-05-06 20:14 CEST` - Executor spawn retry. Files inspected or touched: this plan; command running: none. Decision/blocker: first `codex exec` attempt exited before child work because approval option was in the wrong CLI position; next action: retry spawn with global approval/model options.

## Evidence Summary

- `DIF-004` is open in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` and pending in the session breakdown. `DIF-001` is the only dependency listed for this session and is closed/accepted.
- `lib/features/introduction/application/load_introductions_use_case.dart` already defines `FoldedIntroductionReviewItem`, `FoldedIntroductionIntroducerAttribution`, `foldIntroductionsForReview(...)`, and `countFoldedPendingIntroductionTargets(...)`.
- `IntroRow` renders one `IntroductionModel`, one `Introduced by <name>` attribution from `introduction.introducerUsername`, and action button keys based on the raw intro id.
- `IntrosTab` still accepts `Map<String, List<IntroductionModel>> groupedIntros`, renders `IntroGroupHeader` per introducer, and expands every raw row.
- `OrbitScreen` still models intro entries as raw grouped rows through `OrbitIntrosViewData.groupedIntros` and `_OrbitIntroEntry.row(IntroductionModel)`.
- `OrbitWired` and `FeedWired` already use `countFoldedPendingIntroductionTargets(...)` for badge/review counts, but `OrbitWired` still publishes raw grouped intro rows to `OrbitScreen`.
- The repo has dirty changes from prior accepted sessions. This plan treats those as current input and does not revert or normalize them.

## real scope

This session changes only folded intro review rendering:

- Add a folded rendering path for `IntrosTab`.
- Add a folded rendering path for the active `OrbitScreen` intros sliver.
- Extend row rendering so one row can display multiple introducer attributions while keeping the existing single-introducer row behavior.
- Keep legacy raw grouped inputs as compatibility fallbacks until `DIF-005` wires folded data from `OrbitWired`.

This session does not:

- Change database schema, repositories, or `foldIntroductionsForReview(...)`.
- Wire folded accept/pass actions, folded processing ids, duplicate tap suppression, badge reload behavior, Feed badge behavior, simulator proof, closure docs, or the source matrix `DIF-004` status.
- Change delete semantics. Delete remains raw-intro scoped until product scope says otherwise.

## closure bar

`DIF-004` is good enough when widget-level UI can render two raw duplicate introductions for the same target as one folded review row, with exactly one visible Accept and one visible Pass decision, and an in-row attribution naming both introducers. Single-introducer rows must still render the same target name, attribution copy, button copy, waiting/status labels, blocked state, and message CTA behavior that existing row tests cover.

The compatibility bridge is acceptable only if it lets existing raw grouped callers keep compiling while future `DIF-005` can pass folded review data without replacing the `OrbitScreen` rendering branch again.

## source of truth

- Current code and tests win over stale prose.
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` row `DIF-004` is the behavior contract for this session.
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md` defines session scope, dependency, and planned file boundaries.
- `Test-Flight-Improv/test-gate-definitions.md` defines named gates. If it disagrees with `scripts/run_test_gates.sh`, the script wins.
- `DIF-001` projection code is accepted current architecture and should be reused rather than reimplemented.

## session classification

`implementation-ready`

The prerequisite folded projection exists and direct widget seams are clear. No device/simulator proof is required for this row.

## exact problem statement

The visible intro review UI still expands raw introduction rows by introducer. If two friends introduce the current user to the same target, the UI can show two review rows and two Accept/Pass decisions even though the folded application projection already treats that target as one review item.

The user-visible behavior must improve so duplicate target intros render as one review row with multi-introducer attribution. Single-introducer rows must remain compatible. Action side effects must stay unchanged in this session; any tap still flows through the legacy raw intro callback until `DIF-005`.

## files and repos to inspect next

Production files:

- `lib/features/introduction/presentation/widgets/intro_row.dart`
- `lib/features/introduction/presentation/widgets/intros_tab.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/introduction/application/load_introductions_use_case.dart` as a read-only projection dependency

Compatibility/compile context:

- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`

Direct tests:

- `test/features/introduction/presentation/widgets/intro_row_test.dart`
- `test/features/introduction/presentation/widgets/intros_tab_test.dart`
- `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`
- `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`

Gate docs:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

- `intro_row_test.dart` covers pending buttons, processing disable state, connected/passed/already-connected labels, waiting label, single introducer attribution, readable colors, and RTL/LTR direction for display names and attribution.
- `intros_tab_test.dart` covers empty state, grouped raw rows, group headers, target names, single attribution, pending actions, callbacks, and responded status labels.
- `intros_tab_extended_test.dart` covers multiple raw introducer headers, expired non-action UI, empty state, fallback display names, and long names with actions.
- `orbit_screen_archived_groups_test.dart` covers the active intros sliver, no nested `ListView`, raw group headers, raw rows, review count display, intro banner copy, and live raw intro delete affordance.
- `orbit_screen_loading_test.dart` covers broad Orbit screen construction/readable visuals and should catch accidental constructor or projection regressions.
- `orbit_intros_wiring_test.dart` is a direct companion suite named by the gate docs for intro-to-Orbit follow-up wiring; it is not the primary folded UI proof for this session but should remain green.

Missing coverage:

- No direct widget test proves that duplicate target intros collapse to one visible row.
- No row test proves multiple introducer names can be displayed inside a single intro row.
- No Orbit pure-screen test proves the active intros sliver can consume folded review items.

## regression/tests to add first

Add these tests before production edits and run the exact `--plain-name` commands to capture RED:

- In `test/features/introduction/presentation/widgets/intro_row_test.dart`, add `shows multiple introducer attributions in one row`. Build `IntroRow` with a new folded attribution input containing `Noor` and `Layla`; assert `Introduced by` remains once, both names render in the attribution text, and the single-introducer default test remains unchanged.
- In `test/features/introduction/presentation/widgets/intros_tab_test.dart`, add `renders duplicate aboza introductions as one folded review row`. Create two `IntroductionModel` rows with different introducers and the same target peer/name `aboza`, pass folded review items built by `foldIntroductionsForReview(...)`, and assert one `aboza` row, one `Accept`, one `Pass`, attribution names both introducers, and no folded-path `IntroGroupHeader`.
- In `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`, add `folded attribution falls back for blank introducer names and keeps long names actionable`. Use one blank introducer name and one long introducer name for the same target; assert the blank name falls back to the introducer peer id, the long name is present, and the row still has one Accept and one Pass.
- In `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`, add `renders duplicate aboza introductions as one folded row in the active intros sliver`. Build `OrbitIntrosViewData` with raw grouped rows plus folded review items, set `filterTab: 'intros'`, and assert `CustomScrollView` still exists, `ListView` does not, one `aboza` row appears, one Accept and one Pass appear, and both introducer names appear inside the row attribution.

The RED should be missing constructor parameters/row attribution support or duplicate raw rendering, not unrelated runtime failures.

## step-by-step implementation plan

1. Add the failing widget tests above. Use `foldIntroductionsForReview(...)` in tests rather than hand-building folded items so the UI tests stay tied to the accepted `DIF-001` projection.
2. Extend `IntroRow` with a small optional folded attribution input, preferably `List<String>? introducerAttributionNames` or an equivalent display text field. Keep the existing default path from `introduction.introducerUsername ?? 'someone'`. Normalize empty provided names out of the display list and retain `TextOverflow.ellipsis` plus `detectTextDirection(...)` on the final attribution string.
3. Add a folded rendering path to `IntrosTab` without removing the existing raw grouped constructor contract. The narrow bridge should be an optional `List<FoldedIntroductionReviewItem>? foldedReviewItems` input. When it is non-null, render the folded list directly and do not emit `IntroGroupHeader`; when it is null, keep the existing raw grouped behavior for compatibility.
4. In the folded `IntrosTab` path, map each `FoldedIntroductionReviewItem` to `IntroRow` using `targetDisplayName`, `targetPeerId`, `newestIntroduction`, and `introducerAttributions.map((a) => a.displayName)`. Derive `ownPartyStatus` from the folded pending/accepted/passed current-viewer id lists. Show actions only when the folded item has pending current-viewer decisions and no accepted/passed current-viewer decision.
5. Keep folded `IntrosTab` callbacks raw-id compatible for this session: invoke `onAccept`/`onPass` with `item.displaySourceIntroductionId` only. Mark this in code through naming, not broad comments. `DIF-005` owns replacing these callbacks with folded group actions.
6. Update `OrbitIntrosViewData` in `orbit_screen.dart` with an optional `List<FoldedIntroductionReviewItem>? foldedReviewItems` field. Keep `groupedIntros` required for now so `OrbitWired` and existing tests keep compiling. If `introCount`/`reviewCount` getters use intro rows, prefer folded length when `foldedReviewItems` is supplied and raw length otherwise.
7. Update `_OrbitIntroEntry` and `_buildIntroEntries(...)` so the active intro sliver uses `data.foldedReviewItems` when supplied. Preserve pending group invite entries and the existing empty state. Keep the old raw grouped branch only as a compatibility fallback until `DIF-005`.
8. Render folded Orbit rows through the same `IntroRow` mapping rules as `IntrosTab`: target display fields from the folded item, multi-introducer names inside the row, one visible Accept/Pass decision, `isProcessing` true if any underlying raw intro id is in `processingIntroductionIds`, blocked state by `targetPeerId`, and raw callback id as `displaySourceIntroductionId`.
9. Do not touch `OrbitWired` publishing, folded accept/pass use cases, processing suppression, Feed badge behavior, or matrix closure. If a compile issue forces a small `OrbitWired` edit, keep it to passing the unchanged raw grouped data into the still-compatible constructor.
10. Run `dart format` on touched Dart files, then run the exact direct tests and gates listed below.

Stop early if the added RED tests show `foldIntroductionsForReview(...)` cannot represent the required display state; that would reopen a `DIF-001` prerequisite rather than justify inventing a second folding algorithm in presentation.

## risks and edge cases

- Mixed response state: if any underlying intro already has the current viewer accepted/passed, the folded row must not show a fresh Accept/Pass prompt just because another duplicate raw row is pending.
- Blank introducer names: use `FoldedIntroductionIntroducerAttribution.displayName`, which already falls back to introducer peer id.
- Long attribution text: preserve the existing row layout with `Expanded` and ellipsis so actions remain visible.
- Single introducer compatibility: default `IntroRow` behavior must keep the existing `Introduced by Alice` path.
- Legacy callbacks: after this session, a folded UI row may still invoke only the display-source raw intro id. This is an accepted interim difference and must be closed by `DIF-005` before rollout closure.
- Raw fallback drift: keep the fallback small and avoid adding new product behavior there, so future `DIF-005` can remove or bypass it cleanly.

## exact tests and gates to run

RED commands after adding tests:

```bash
flutter test test/features/introduction/presentation/widgets/intro_row_test.dart --plain-name "shows multiple introducer attributions in one row"
flutter test test/features/introduction/presentation/widgets/intros_tab_test.dart --plain-name "renders duplicate aboza introductions as one folded review row"
flutter test test/features/introduction/presentation/widgets/intros_tab_extended_test.dart --plain-name "folded attribution falls back for blank introducer names and keeps long names actionable"
flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart --plain-name "renders duplicate aboza introductions as one folded row in the active intros sliver"
```

Direct GREEN commands after implementation:

```bash
flutter test test/features/introduction/presentation/widgets/intro_row_test.dart
flutter test test/features/introduction/presentation/widgets/intros_tab_test.dart
flutter test test/features/introduction/presentation/widgets/intros_tab_extended_test.dart
flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart
flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart
flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"
```

Named gate:

```bash
./scripts/run_test_gates.sh intro
```

No device, relay, or simulator proof is required for `DIF-004`.

## known-failure interpretation

No tests were run during planning, so there is no new planning-time known-failure list. During execution:

- Treat the new `--plain-name` failures as valid RED only if they fail for missing folded UI rendering or missing row attribution support.
- If an existing direct file fails before implementation for unrelated reasons, rerun the narrower pre-existing test or record it separately before changing code.
- Do not classify dirty changes from `DIF-001` through `DIF-003` as regressions unless the same command was green after those accepted sessions and now fails due to `DIF-004` edits.
- A named gate failure outside introduction/orbit/feed folded rendering is not `DIF-004` closure evidence; document it and keep the direct folded widget proofs separate.

## done criteria

- The plan's first failing widget tests are added and initially fail for the expected folded UI gap.
- `IntroRow` supports multi-introducer attribution without regressing single-introducer display.
- `IntrosTab` can render supplied folded review items as one row per target with in-row multi-introducer attribution.
- The active `OrbitScreen` intros sliver can render supplied folded review items as one row per target with no nested `ListView`.
- Legacy raw grouped callers still compile and keep their fallback behavior until `DIF-005`.
- All direct GREEN commands listed above pass, or any unrelated pre-existing failure is documented with a concrete command and reason.
- `./scripts/run_test_gates.sh intro` passes, or a non-DIF-004 failure is documented separately.

## scope guard

Do not implement folded action semantics, group-level callbacks, processing by folded group id, duplicate tap suppression, Orbit/Feed badge reload changes, simulator scripts, docs closure, source matrix closure, repository/schema changes, or delete folding in this session.

Do not replace `foldIntroductionsForReview(...)` with presentation-only grouping. Do not broaden this into a visual redesign of Orbit, Feed, intro rows, group headers, or navigation badges. Do not remove raw grouped compatibility unless every current production caller is updated within this session without entering `DIF-005` behavior.

## accepted differences / intentionally out of scope

- Folded row actions remain legacy raw-id callbacks for this session. This is intentionally incomplete and belongs to `DIF-005`.
- Processing state can only reflect underlying raw intro ids already present in `processingIntroductionIds`; folded group-level suppression is intentionally out of scope.
- `OrbitWired` may continue publishing raw grouped intros after this session. The UI data object must be ready to accept folded items so `DIF-005` can switch the publisher without another rendering rewrite.
- Feed badge and Orbit badge counts were addressed by `DIF-002`; this session must not alter them.
- Four-identity simulator evidence belongs to `DIF-006`, not this plan.

## dependency impact

`DIF-005` depends on this plan's folded UI data path. If execution chooses a different bridge than optional `foldedReviewItems`, it must still leave a clear way for `OrbitWired` to publish folded review items and call folded group actions without duplicating row-rendering logic.

`DIF-006` and `DIF-007` should not start from this plan alone. They require `DIF-005` to close the action-processing and wired integration gaps first.

## Reviewer Pass

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? `Sufficient as-is`.
- Missing files, tests, regressions, or gates: none structural. The plan names the row/widget files, `OrbitScreen`, current wired compile context, direct widget commands, Orbit companion tests, Feed/Orbit folded badge companion assertions, and the named intro gate.
- Stale or incorrect assumptions: none found. The draft correctly treats `DIF-001` projection as accepted, `DIF-002` count work as already closed, and `DIF-005` wired folded actions/publisher work as out of scope.
- Overengineering: none structural. Optional `foldedReviewItems` is a narrow bridge that avoids forcing `OrbitWired` into `DIF-004`.
- Decomposition safety: sufficient. The steps add RED widget tests first, then row attribution, then `IntrosTab`, then `OrbitScreen` folded sliver, and stop before action semantics.
- Minimum needed to make sufficient: already met. Execution should avoid asserting a specific attribution delimiter; tests should assert both introducer names are present in the row attribution.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: attribution delimiter is intentionally left to execution; tests should assert both names in the row attribution, not exact punctuation.
- Accepted differences: legacy raw-id callbacks and raw grouped publisher compatibility remain until `DIF-005`.
- Stop rule: no structural blocker was found, so no fix loop is required.

## Final Planning Output

- Final verdict: execution-ready for exactly one session, `DIF-004`.
- Final plan: add RED widget tests first, extend `IntroRow` for multi-introducer attribution, add folded item rendering paths to `IntrosTab` and `OrbitScreen`, keep raw grouped compatibility for `DIF-005`, and run the direct widget/companion tests plus `./scripts/run_test_gates.sh intro`.
- Structural blockers remaining: none.
- Incremental details intentionally deferred: exact attribution delimiter and any later removal of raw fallback.
- Accepted differences intentionally left unchanged: raw-id callbacks, raw processing ids, raw `OrbitWired` publisher, badge reload behavior, delete semantics, simulator proof, and source matrix closure.
- Exact docs/files used as evidence: `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`, `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md`, `lib/features/introduction/application/load_introductions_use_case.dart`, `lib/features/introduction/presentation/widgets/intro_row.dart`, `lib/features/introduction/presentation/widgets/intros_tab.dart`, `lib/features/orbit/presentation/screens/orbit_screen.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, `lib/features/feed/presentation/screens/feed_wired.dart`, and the listed direct test files.
- Why the plan is safe to implement now: the accepted folded projection exists, the plan does not invent a second folding algorithm, the bridge avoids forcing `DIF-005` into this session, the first tests are direct widget REDs, and the scope guard explicitly blocks action wiring, count changes, simulator work, and closure docs.
