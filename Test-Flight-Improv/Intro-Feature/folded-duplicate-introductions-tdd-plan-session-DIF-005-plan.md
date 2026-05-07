Status: execution-ready

# DIF-005 - Orbit Wired and Feed Badge Integration Plan

## Planning Progress

- `2026-05-06 20:44 CEST` - Arbiter completed. Files inspected since last
  update: reviewer pass and full plan. Decision/blocker: no structural
  blockers; the reviewer adjustment is incremental and already applied. Next
  action: mark `DIF-005` plan execution-ready.
- `2026-05-06 20:44 CEST` - Arbiter started. Files inspected since last
  update: reviewer pass and full plan. Decision/blocker: classify reviewer
  findings into structural blockers, incremental details, and accepted
  differences. Next action: record final arbiter verdict.
- `2026-05-06 20:43 CEST` - Reviewer completed. Files inspected since last
  update: full draft plan and evidence summary. Decision/blocker: sufficient
  with one non-structural adjustment to make the format command explicit; no
  scope, regression, or gate blocker found. Next action: arbiter
  classification.
- `2026-05-06 20:43 CEST` - Reviewer started. Files inspected since last
  update: full draft plan. Decision/blocker: review focused on stale Feed
  assumptions, folded processing suppression, direct RED/GREEN sufficiency,
  source matrix expectations, and later-row scope guard. Next action: record
  sufficiency findings.
- `2026-05-06 20:41 CEST` - Planner completed. Files inspected since last
  update: `OrbitWired`, `OrbitScreen`, `FeedWired`, folded projection/action
  use cases, direct Orbit/Feed tests, source matrix, session breakdown, and gate
  definitions. Decision/blocker: draft is implementation-ready if review finds
  no missing regression contract. Next action: reviewer sufficiency pass.

## Execution Progress

- `2026-05-06 20:46 CEST` - Contract extraction started. Files inspected or
  touched: this plan, source matrix excerpts, session breakdown excerpts, gate
  file locations, owner file locations. Command currently running: none.
  Decision/blocker: no production edits before extracting exact scope, RED,
  GREEN, gate, done, non-goal, and dirty-worktree constraints. Next action:
  persist extracted contract and start RED test work.
- `2026-05-06 20:46 CEST` - Contract extracted. Files inspected or touched:
  this plan only. Command currently running: none. Decision/blocker: execute
  only `DIF-005`; primary owner files are `lib/features/orbit/presentation/screens/orbit_wired.dart`
  and `test/features/orbit/presentation/screens/orbit_wired_test.dart`; add the
  three named RED tests first; leave Feed production read-only unless a new RED
  proves a current raw-count regression; required direct GREEN commands and
  named gate are the commands listed in this plan; do not touch `DIF-006` or
  `DIF-007`. The current tool surface has no child-agent spawn tool, so this
  isolated execution invocation will use the skill's local sequential fallback
  and keep Executor and QA phases separate in-file. Next action: inspect owner
  files and add RED tests before production edits.
- `2026-05-06 20:46 CEST` - Executor local fallback started. Files inspected or
  touched: this plan. Command currently running: none. Decision/blocker:
  spawned Executor materialization is unavailable in this tool surface; local
  fallback will execute sequentially and preserve a separate QA review phase.
  Next action: inspect `OrbitWired`, folded API dependencies, and
  `orbit_wired_test.dart`.
- `2026-05-06 20:47 CEST` - RED tests started. Files inspected or touched:
  `test/features/orbit/presentation/screens/orbit_wired_test.dart`,
  `lib/features/orbit/presentation/screens/orbit_wired.dart`,
  `lib/features/orbit/presentation/screens/orbit_screen.dart`,
  `lib/features/introduction/application/load_introductions_use_case.dart`,
  `lib/features/introduction/application/folded_introduction_response_use_case.dart`.
  Command currently running: none. Decision/blocker: prerequisites exist and no
  Feed raw-count regression was found in the execution contract evidence. Next
  action: add the three required RED `OrbitWired` tests before production
  edits.
- `2026-05-06 20:48 CEST` - RED tests added; exact RED commands started. Files
  inspected or touched: `test/features/orbit/presentation/screens/orbit_wired_test.dart`.
  Command currently running: `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets into one OrbitWired intro row and badge target"`,
  followed by the two folded action `--plain-name` commands. Decision/blocker:
  production files remain untouched. Next action: record expected RED failures
  before implementation.
- `2026-05-06 20:50 CEST` - RED fixture correction. Files inspected or
  touched: `test/features/orbit/presentation/screens/orbit_wired_test.dart`.
  Command currently running: none. Decision/blocker: first RED attempt failed
  for the wrong reason because fixed March timestamps were expired by
  `expireOldIntroductions(...)`, yielding no rows instead of proving the wired
  folded gap. Next action: replace those timestamps with fresh ordered values
  and rerun the exact RED commands before production edits.
- `2026-05-06 20:51 CEST` - RED commands completed. Files inspected or touched:
  `test/features/orbit/presentation/screens/orbit_wired_test.dart`. Commands
  finished: the three exact `flutter test ... --plain-name` RED commands in
  this plan. Decision/blocker: valid RED captured. Publish test failed with two
  `Dora` row texts instead of one; folded Accept and Pass tests failed because
  another raw duplicate `Accept` remained enabled while the display-source id
  was processing. Next action: implement the scoped `OrbitWired` folded
  publisher/action/processing guard changes.
- `2026-05-06 20:51 CEST` - Implementation started. Files inspected or touched:
  `lib/features/orbit/presentation/screens/orbit_wired.dart`. Command currently
  running: none. Decision/blocker: edits are limited to importing folded action
  wrappers, storing/publishing folded review items, resolving callback ids to
  folded items, guarding all underlying ids while processing, and preserving the
  existing single-id fallback. Next action: patch `OrbitWired`.
- `2026-05-06 20:52 CEST` - Implementation completed; required GREEN commands
  started. Files inspected or touched:
  `lib/features/orbit/presentation/screens/orbit_wired.dart`,
  `test/features/orbit/presentation/screens/orbit_wired_test.dart`. Command
  currently running: `dart format lib/features/orbit/presentation/screens/orbit_wired.dart test/features/orbit/presentation/screens/orbit_wired_test.dart`.
  Decision/blocker: folded state publishing, callback resolution, all-id
  processing guard, folded Accept/Pass wrappers, reload, and raw fallback are
  landed. Next action: run each exact direct GREEN command and then the intro
  gate.
- `2026-05-06 20:53 CEST` - Direct GREEN commands completed; named gate
  started. Files inspected or touched:
  `lib/features/orbit/presentation/screens/orbit_wired.dart`,
  `test/features/orbit/presentation/screens/orbit_wired_test.dart`,
  `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`,
  `test/features/feed/presentation/screens/feed_wired_test.dart`. Commands
  finished: `dart format ...` and all eight exact direct GREEN test commands
  listed in this plan, each passed. Command currently running:
  `./scripts/run_test_gates.sh intro`. Decision/blocker: no direct-test failure
  remains and Feed stayed read-only. Next action: record intro gate result.
- `2026-05-06 20:54 CEST` - Named gate completed; QA Reviewer local fallback
  started. Files inspected or touched: this plan. Command currently running:
  none. Decision/blocker: `./scripts/run_test_gates.sh intro` passed. Next
  action: perform a separate QA sufficiency pass over scope adherence,
  regressions, direct commands, named gate evidence, source-row update
  expectations, and residual blockers.
- `2026-05-06 20:55 CEST` - QA Reviewer local fallback completed. Files
  inspected or touched: `lib/features/orbit/presentation/screens/orbit_wired.dart`,
  `test/features/orbit/presentation/screens/orbit_wired_test.dart`,
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`,
  this plan. Command currently running: none. Decision/blocker: no blocking
  issues found. Scope stayed within `OrbitWired`, its direct test, this plan,
  and the source matrix row; Feed production, simulator scripts, schemas,
  repositories, folded projection/action internals, `DIF-006`, and `DIF-007`
  were not edited. Next action: update only source matrix row `DIF-005` to
  `Closed` with exact evidence and write final verdict.
- `2026-05-06 20:55 CEST` - Final verdict written. Files inspected or touched:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`,
  this plan. Command currently running: none. Decision/blocker: source matrix
  row `DIF-005` is `Closed` with RED/GREEN/gate evidence; `DIF-006` and
  `DIF-007` remain untouched and open. Next action: return final execution
  status.

## Final Execution Verdict

- Final verdict: `accepted`
- Spawned-agent isolation used: unavailable in this tool surface; local
  sequential fallback used under the skill contract, with separate Executor and
  QA phases recorded above.
- Blocking issues remaining: none.
- Non-blocking follow-ups deferred: none.
- Why complete: the three required RED tests failed for the expected active
  wired folded publish/action gaps, the scoped `OrbitWired` implementation
  passes all exact direct GREEN commands and `./scripts/run_test_gates.sh intro`,
  QA found no scope drift or missing evidence, and source matrix row `DIF-005`
  is closed with concrete evidence while later rows remain open.

## Evidence Summary

- The source matrix row `DIF-005` was `Open` before execution and required the
  wired Orbit flow to process a folded Accept/Pass once, disable the whole
  folded row while processing, reload folded state, and keep the Orbit
  badge/review count folded. It is now `Closed` with the execution evidence
  recorded in the source matrix.
- The session breakdown marks `DIF-005` as `implementation-ready`, with
  dependencies `DIF-001`, `DIF-002`, `DIF-003`, and `DIF-004`.
- `lib/features/introduction/application/load_introductions_use_case.dart`
  already provides `FoldedIntroductionReviewItem`,
  `foldIntroductionsForReview(...)`, and
  `countFoldedPendingIntroductionTargets(...)`.
- `lib/features/introduction/application/folded_introduction_response_use_case.dart`
  already provides `acceptFoldedIntroduction(...)` and
  `passFoldedIntroduction(...)`, returning per-id applied/skipped/failed
  outcomes.
- `lib/features/orbit/presentation/screens/orbit_screen.dart` already accepts
  optional `OrbitIntrosViewData.foldedReviewItems`, renders one folded row per
  item, sends `item.displaySourceIntroductionId` through the existing
  `onAccept`/`onPass` callbacks, and marks a folded row processing when any
  underlying raw id is in `processingIntroductionIds`.
- `lib/features/orbit/presentation/screens/orbit_wired.dart` currently keeps
  only raw `_groupedIntros`, publishes `OrbitIntrosViewData` without
  `foldedReviewItems`, calls single-id `acceptIntroduction(...)` and
  `passIntroduction(...)`, and tracks `_processingIntroductionIds` by only the
  tapped raw id. It already sets `_introsCount` with
  `countFoldedPendingIntroductionTargets(...)`.
- `lib/features/feed/presentation/screens/feed_wired.dart` already refreshes
  the Orbit badge by loading introductions through `loadIntroductionsForUser`
  and counting them with `countFoldedPendingIntroductionTargets(...)`; no
  current Feed production change is evident.
- Existing `orbit_wired_test.dart` covers folded Orbit badge count and raw
  single-row processing/duplicate-tap suppression, but it does not prove that
  active `OrbitWired` publishes folded review rows or that a folded row action
  applies to every underlying raw intro id.

## real scope

This session is limited to the active wired integration for folded duplicate
introductions:

- Update `OrbitWired` to compute and publish folded intro review items into
  `OrbitIntrosViewData.foldedReviewItems`.
- Route folded row Accept/Pass callbacks through
  `acceptFoldedIntroduction(...)` and `passFoldedIntroduction(...)` when the
  callback id belongs to a current folded item.
- Track processing for the folded row by the full underlying raw id set, or an
  equivalent guard that makes `OrbitScreen` disable the folded row because it
  already checks whether any underlying id is processing.
- Suppress duplicate taps while any underlying id in the folded item is already
  processing.
- Reload introductions after the folded action so `OrbitWired` republishes
  folded state and folded counts.
- Keep Orbit badge/review counts based on
  `countFoldedPendingIntroductionTargets(...)`.

Feed scope is evidence-only for this row unless future execution discovers that
`FeedWired` has regressed to a raw repository count path. Current planning
evidence says it has not.

This session does not change schemas, repositories, folded projection rules,
folded application action rules, row visuals, delete semantics, simulator
scripts, source row closure, final test inventory, or broad Orbit/Feed UI.

## closure bar

`DIF-005` is good enough when, from the active `OrbitWired` path, two pending
introductions for the same current-viewer target render as one folded Orbit
intro row with one Accept and one Pass action, one folded Orbit badge/review
target count, and one processing state. A single tap must apply the action to
all pending underlying raw intro ids in that folded item. A second tap while
processing must not trigger extra updates. After completion, the screen must
reload through the same folded publisher rather than falling back to duplicate
raw rows.

Raw single-intro behavior must remain compatible. If a callback id cannot be
resolved to a folded item, the existing single-id accept/pass path should remain
available as a fallback.

## source of truth

- Current code and tests win over stale prose.
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`
  row `DIF-005` is the scenario contract.
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`
  defines this session's scope, dependency state, likely files, and likely
  gates.
- `DIF-001` through `DIF-004` closure evidence in the source matrix and session
  ledger is accepted current architecture.
- `Test-Flight-Improv/test-gate-definitions.md` defines named gate intent. If
  it disagrees with `scripts/run_test_gates.sh`, the script wins.
- `FeedWired` code is authoritative for whether more Feed badge work is needed;
  inspection shows it already uses the folded badge path.

## session classification

`implementation-ready`

The prerequisite folded projection, folded count helper, folded action use
cases, and folded UI rendering path already exist. No device, relay, or
simulator proof profile is required for this row.

## exact problem statement

The app can compute folded pending intro counts and render folded rows when
given folded UI data, but active `OrbitWired` still publishes raw grouped intro
rows and invokes raw single-id accept/pass use cases. As a result, duplicate
introductions for the same target can still appear as duplicate active Orbit
review rows, and tapping one row can update only one underlying raw
introduction.

The user-visible behavior must improve so active Orbit presents one folded row
and one folded action for duplicate target intros. The behavior that must stay
unchanged: raw single-intro flows, existing folded count semantics, Feed's
already-folded badge path, and all prior accepted UI rendering compatibility.

## files and repos to inspect next

Production files:

- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart` as a read-only
  folded UI callback/processing contract unless a compile issue requires a
  narrow adjustment
- `lib/features/feed/presentation/screens/feed_wired.dart` as a read-only badge
  evidence file unless a future RED test finds a current-row regression
- `lib/features/introduction/application/load_introductions_use_case.dart` as a
  read-only folded projection/count dependency
- `lib/features/introduction/application/folded_introduction_response_use_case.dart`
  as a read-only folded action dependency

Direct tests:

- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

Gate docs and script:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

- `test/features/orbit/presentation/screens/orbit_wired_test.dart` already has
  `folds duplicate pending introduction targets in the Orbit intro count`,
  proving the Orbit nav badge can count duplicate pending target intros as one.
- The same file already has raw single-intro processing tests:
  `accepting an intro shows processing immediately and ignores duplicate taps`
  and `passing an intro disables both actions immediately and ignores duplicate
  taps`.
- `test/features/feed/presentation/screens/feed_wired_test.dart` already has
  `loads the Orbit badge from folded pending introduction targets on first
  load`, proving the current Feed badge path uses folded target counts.
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  covers lower-level intro accept/pass wiring and intro count refresh behavior,
  but it does not exercise the active folded `OrbitWired` widget path.
- `DIF-004` widget tests cover folded row rendering when folded data is supplied
  to `OrbitScreen`, but they do not prove `OrbitWired` supplies that data.

Missing coverage:

- No active `OrbitWired` test proves duplicate target intros render as one row.
- No active `OrbitWired` test proves folded Accept/Pass updates all underlying
  raw ids.
- No active `OrbitWired` test proves duplicate taps are suppressed at the folded
  row while one underlying action is blocked.
- No active `OrbitWired` test proves reload after folded actions keeps folded
  row/count behavior.

## regression/tests to add first

Add these RED tests in
`test/features/orbit/presentation/screens/orbit_wired_test.dart` before
production edits:

1. `folds duplicate pending introduction targets into one OrbitWired intro row and badge target`
   - Seed two pending introductions for the current user with different
     introducers, stable different `createdAt` values, and the same
     `otherPeerId`/target username.
   - Pump `OrbitWired` with `initialFilterTab: 'intros'`, an Orbit shell
     controller, and a feed unread notifier.
   - Assert one target display row, one Accept action, one Pass action, one
     folded attribution text containing both introducer names, and Orbit badge
     count `1`.
   - Expected RED before implementation: duplicate raw rows/actions are visible
     because `OrbitWired` does not publish `foldedReviewItems`.

2. `accepting a folded Orbit intro disables the folded row and updates every underlying intro once`
   - Use `_BlockingIntroductionRepository` with two same-target pending intros
     and an `acceptGate`.
   - Make the newer intro id deterministic, for example `intro-newer`, so the
     folded row's button key is `ValueKey('intro-accept-intro-newer')`.
   - Tap Accept, pump once, assert exactly one processing label/state, no
     additional enabled `Accept` remains for a duplicate row, the folded row
     Pass button is disabled, and `acceptedUpdates == 1` while the gate blocks
     the first underlying update.
   - Tap the same Accept finder again while blocked and assert
     `acceptedUpdates == 1`.
   - Complete the gate, pump to settle, then assert both raw introduction rows
     have the current viewer's status accepted, the view still shows one folded
     target row, no Accept/Pass actions remain for that folded item, and Orbit
     badge count is still `1` because the overall rows remain one-sided
     pending.
   - Expected RED before implementation: raw duplicate UI and/or single-id
     accept updates only one underlying intro.

3. `passing a folded Orbit intro disables the folded row and updates every underlying intro once`
   - Use `_BlockingIntroductionRepository` with two same-target pending intros
     and a `passGate`.
   - Tap the folded row Pass button, pump once, assert the folded row actions
     are disabled, no extra enabled duplicate-row action remains, and
     `passedUpdates == 1` while blocked.
   - Tap the same Pass finder again while blocked and assert
     `passedUpdates == 1`.
   - Complete the gate, pump to settle, then assert both raw introductions have
     current-viewer status `passed`, both overall statuses are `passed`, the
     folded target row is gone, and Orbit badge count is `0`.
   - Expected RED before implementation: duplicate raw UI and/or single-id pass
     updates only one underlying intro.

Do not add a new Feed test up front. The existing Feed folded badge test already
targets the inspected Feed seam. Add a Feed RED only if future execution finds a
current raw repository count path in `FeedWired`.

## step-by-step implementation plan

1. Add the three RED `OrbitWired` widget tests above. Prefer stable timestamps
   over relying on insertion order so the folded display-source id is
   deterministic.
2. Run the three exact RED commands listed in this plan and record the expected
   failure reason before production edits.
3. In `lib/features/orbit/presentation/screens/orbit_wired.dart`, import
   `folded_introduction_response_use_case.dart`.
4. Add folded state to `_OrbitWiredState`, for example
   `List<FoldedIntroductionReviewItem> _foldedReviewItems = const [];`.
   Keep `_groupedIntros` for raw compatibility and for any still-raw fallback
   path.
5. In `_loadIntroductions()`, after loading `pending`, compute:
   `foldIntroductionsForReview(introductions: pending, ownPeerId: ownPeerId)`.
   Store it in `_foldedReviewItems`, keep `_groupedIntros` and
   `_introducerUsernames` populated, and keep `_introsCount` based on
   `countFoldedPendingIntroductionTargets(...)`.
6. In `_buildListProjection()`, pass
   `foldedReviewItems: List<FoldedIntroductionReviewItem>.unmodifiable(_foldedReviewItems)`
   into `OrbitIntrosViewData`. Preserve the existing raw `groupedIntros`
   argument.
7. Add a small resolver helper in `OrbitWired`, for example
   `_foldedIntroForActionId(String introductionId)`, matching either
   `displaySourceIntroductionId` or membership in `introductionIds`. This keeps
   the current `OrbitScreen` callback signature usable.
8. Add a folded processing guard helper. If the callback resolves to a folded
   item and any underlying id is already in `_processingIntroductionIds`, return
   without work. Otherwise add all underlying ids to `_processingIntroductionIds`
   before publishing the projection. Remove the same id set in `finally`.
9. Update `_onAcceptIntro(String introductionId)` so the folded path calls
   `acceptFoldedIntroduction(...)` with the resolved folded item. For applied
   results whose `introduction?.status` is `mutualAccepted`, compute the other
   peer id, de-dupe by peer id, mark the contact changed, and refresh the Orbit
   friend once per peer. Keep the existing single-id `acceptIntroduction(...)`
   behavior as the fallback when no folded item resolves.
10. Update `_onPassIntro(String introductionId)` similarly so the folded path
    calls `passFoldedIntroduction(...)`. Keep the existing single-id
    `passIntroduction(...)` fallback.
11. In both folded action paths, set `_refreshPendingIntroductionsOnPop = true`
    and `await _loadIntroductions()` after the action batch, matching the
    existing single-id reload semantics.
12. Do not edit `OrbitScreen`, `IntroRow`, `IntrosTab`, `FeedWired`, repositories,
    or schema unless the new tests expose a compile or behavior mismatch in the
    existing folded UI contract. If such a mismatch appears, keep the adjustment
    narrowly tied to `OrbitWired` consuming the already-accepted `DIF-004`
    folded UI API.
13. Run `dart format` on touched Dart files.
14. Run the exact direct GREEN commands and named gate listed below.
15. Source matrix expectation for future execution/closure: after RED evidence,
    implementation, direct GREEN commands, and QA acceptance, update only source
    matrix row `DIF-005` to `Closed` with the concrete evidence. Do not update
    `DIF-006` or `DIF-007`. This planning turn must not close the source row.

Stop early and mark the plan blocked if `foldedReviewItems` is missing from
`OrbitScreen` in the execution checkout, if `acceptFoldedIntroduction(...)` or
`passFoldedIntroduction(...)` is unavailable, or if Feed inspection contradicts
the planning evidence and shows the badge still reads a raw repository count.

## risks and edge cases

- Processing suppression must use the whole folded item, not only the display
  source id, or a duplicate raw id can remain tappable.
- The folded action wrappers re-read current rows and can return skipped or
  failed per-id results. The UI should still reload after the batch so stale
  duplicates disappear or show the current folded state.
- Accepting duplicate rows can keep the folded target count at `1` because the
  overall introductions remain pending until mutual acceptance. Passing the
  folded item should reduce the folded target count to `0`.
- If multiple applied accept results become `mutualAccepted`, Orbit friend
  refresh should de-dupe by other peer id to avoid redundant work for the same
  target.
- Existing raw single-intro processing tests must remain green; the folded
  path should be behavior-equivalent when there is only one pending raw id.
- Feed badge behavior currently appears complete; adding Feed production work
  without a failing Feed test would be scope drift.

## exact tests and gates to run

RED commands after adding tests:

```bash
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets into one OrbitWired intro row and badge target"
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "accepting a folded Orbit intro disables the folded row and updates every underlying intro once"
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "passing a folded Orbit intro disables the folded row and updates every underlying intro once"
```

Direct GREEN commands after implementation:

```bash
dart format lib/features/orbit/presentation/screens/orbit_wired.dart test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets into one OrbitWired intro row and badge target"
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "accepting a folded Orbit intro disables the folded row and updates every underlying intro once"
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "passing a folded Orbit intro disables the folded row and updates every underlying intro once"
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "accepting an intro shows processing immediately and ignores duplicate taps"
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "passing an intro disables both actions immediately and ignores duplicate taps"
flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"
```

Named gate:

```bash
./scripts/run_test_gates.sh intro
```

`./scripts/run_test_gates.sh feed` is not required for the planned no-Feed-code
path. If future execution edits `FeedWired` or feed card behavior after finding
a real Feed regression, add the Feed RED first and then run:

```bash
./scripts/run_test_gates.sh feed
```

## known-failure interpretation

No tests were run during planning. During execution:

- The three new RED tests are valid only if they fail because active
  `OrbitWired` does not yet publish folded data or does not yet apply folded
  actions to every underlying id.
- A failure from missing `foldIntroductionsForReview(...)`,
  `countFoldedPendingIntroductionTargets(...)`, `foldedReviewItems`,
  `acceptFoldedIntroduction(...)`, or `passFoldedIntroduction(...)` is a
  prerequisite regression against accepted prior sessions and should block
  `DIF-005` implementation rather than be reimplemented locally.
- Prior accepted evidence says `./scripts/run_test_gates.sh intro` was green
  after `DIF-004`; treat a new intro-gate failure after `DIF-005` edits as
  suspect unless logs clearly identify an unrelated environmental or preexisting
  failure.
- Dirty changes from prior sessions or the user must not be reverted or
  normalized. If an unrelated dirty file causes a test failure, document the
  exact command and failure separately.

## done criteria

- Three `OrbitWired` RED tests are added first and fail for the expected wired
  folded publish/action gap.
- `OrbitWired` publishes folded review items into `OrbitScreen`.
- Duplicate same-target introductions render through active `OrbitWired` as one
  folded row with one Accept and one Pass action.
- Folded Accept applies to every pending underlying current-viewer decision id,
  suppresses duplicate taps while blocked, reloads, and leaves one folded
  pending target count when the overall rows are still one-sided pending.
- Folded Pass applies to every pending underlying current-viewer decision id,
  suppresses duplicate taps while blocked, reloads, removes the folded target
  from review, and updates Orbit badge/review count to zero for that target.
- Existing raw single-intro processing tests remain green.
- Existing Feed folded badge test remains green without Feed production edits.
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart` and
  `./scripts/run_test_gates.sh intro` are green, or any non-DIF-005 failure is
  recorded with exact command output and reason.
- Source matrix row `DIF-005` is updated only by the future execution/closure
  path after GREEN evidence and QA acceptance; it is not changed by planning.

## source matrix update expectations

Planning turn expectation:

- Leave `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`
  row `DIF-005` as `Open`.
- Leave `DIF-006` and `DIF-007` untouched.

Future execution/closure expectation:

- If the RED/GREEN and gate evidence above passes and QA accepts the scoped
  diff, update only row `DIF-005` to `Closed` with exact RED failure reasons,
  exact direct GREEN commands, and the named intro gate result.
- If a prerequisite from `DIF-001` through `DIF-004` is missing in the execution
  checkout, do not close `DIF-005`; mark the blocker concretely in the execution
  artifact.
- If Feed unexpectedly needs code changes, include the new Feed RED/GREEN
  evidence in row `DIF-005`; do not broaden the row into Feed card redesign or
  later closure work.

## scope guard

Do not add simulator scenarios, four-device proof, relay/device profiles,
schema migrations, repository rewrites, folded projection rewrites, folded
application action rewrites, UI redesign, delete folding, final test inventory
closure, or closure of later source rows.

Do not change `FeedWired` unless a current failing test proves it still uses a
raw count path. Do not run or require the Feed gate for the no-Feed-code path.
Do not remove raw grouped compatibility in `OrbitWired`/`OrbitScreen`; keep a
fallback for callbacks that cannot be resolved to a folded item.

## accepted differences / intentionally out of scope

- `FeedWired` production code is intentionally left unchanged because it already
  uses folded pending target counts.
- Repository `countPendingIntroductions(...)` remains raw-row based per
  `DIF-002`; user-facing badge code should use the folded helper instead.
- `OrbitScreen`'s string callback signature can remain raw-id shaped for this
  session. `OrbitWired` can resolve that id back to the folded item.
- Delete behavior remains display-source raw-id scoped.
- Device/simulator proof belongs to `DIF-006`; final regression inventory and
  rollout closure belong to `DIF-007`.

## dependency impact

`DIF-006` depends on `DIF-005` because the simulator folded duplicate proof
needs active Orbit to render one folded row and apply one folded Accept/Pass
decision across all underlying intro ids.

`DIF-007` depends on `DIF-005` and `DIF-006` because final closure should not
claim folded duplicate introductions are rollout-ready while active
`OrbitWired` still uses raw row actions or while the device proof is absent.

If this plan changes during execution because Feed unexpectedly needs code,
`DIF-006` can still proceed only after the revised `DIF-005` row has concrete
green Orbit and Feed evidence.

## Reviewer Pass

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient?
  `Sufficient with adjustments`.
- What files, tests, regressions, or gates are missing? No structural missing
  coverage. The plan names the production owner file, read-only dependencies,
  three RED `OrbitWired` regressions, raw single-intro compatibility commands,
  the direct Orbit intro wiring companion suite, the existing Feed folded badge
  companion assertion, and the named intro gate. The only adjustment was making
  the `dart format` command explicit.
- What assumptions are stale or incorrect? None found. Current `FeedWired`
  evidence shows folded counting; current `OrbitScreen` evidence shows folded
  rendering and processing-by-underlying-id support.
- What is overengineered? No structural overengineering. The plan keeps raw
  fallback callbacks and avoids changing projection, repository, Feed, or UI
  surfaces.
- Is the work decomposed enough to minimize hallucination during
  implementation? Yes. The executor can add RED tests first, then add folded
  state publishing, resolver/processing guard helpers, and folded action calls
  in `OrbitWired`.
- What is the minimum needed to make the plan sufficient? Already applied:
  include the exact format command alongside the direct GREEN commands.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: the reviewer requested an explicit format command; this
  is already added to the direct GREEN command block. No fix loop is required.
- Accepted differences: no Feed production change is planned because current
  `FeedWired` already uses folded counts; raw repository counts remain raw per
  `DIF-002`; `OrbitScreen` keeps the raw-id shaped callback signature while
  `OrbitWired` resolves the id back to the folded item; delete folding,
  simulator proof, and final closure remain later scope.
- Stop rule: no structural blocker was found, so planning stops here and the
  plan is marked `execution-ready`.

## Final Planning Output

- Final verdict: `execution-ready` for exactly one session, `DIF-005`.
- Final plan: add three `OrbitWired` RED tests first, implement folded publish
  state plus folded accept/pass resolver and all-underlying-id processing guard
  in `OrbitWired`, leave Feed production unchanged unless a new Feed RED proves
  otherwise, then run the exact direct commands and `./scripts/run_test_gates.sh
  intro`.
- Structural blockers remaining: none.
- Incremental details intentionally deferred: exact helper names and whether the
  executor de-dupes mutual-acceptance refreshes sequentially or through a local
  set, as long as it refreshes once per peer and preserves behavior.
- Accepted differences intentionally left unchanged: raw repository count API,
  raw grouped fallback compatibility, raw-id shaped UI callbacks, delete
  behavior, Feed production code, simulator proof, and final test-inventory
  closure.
- Exact docs/files used as evidence:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`,
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`,
  `Test-Flight-Improv/test-gate-definitions.md`,
  `scripts/run_test_gates.sh`,
  `lib/features/orbit/presentation/screens/orbit_wired.dart`,
  `lib/features/orbit/presentation/screens/orbit_screen.dart`,
  `lib/features/feed/presentation/screens/feed_wired.dart`,
  `lib/features/introduction/application/load_introductions_use_case.dart`,
  `lib/features/introduction/application/folded_introduction_response_use_case.dart`,
  `test/features/orbit/presentation/screens/orbit_wired_test.dart`,
  `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`, and
  `test/features/feed/presentation/screens/feed_wired_test.dart`.
- Why the plan is safe to implement now: all dependencies are accepted in the
  ledger/source matrix, the active gap is isolated to `OrbitWired`, the plan
  requires failing tests before code edits, the direct tests pin folded UI,
  folded action, raw fallback, Orbit companion wiring, and Feed folded badge
  behavior, and the scope guard excludes later simulator and closure work.
