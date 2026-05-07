Status: execution-ready

# DIF-002 - Folded Count Contract Plan

## Execution Progress

- `2026-05-06 19:25 CEST` - QA Reviewer completed. Files inspected since last update: final dirty state and plan progress after QA test reruns. Commands/results: `flutter test test/features/introduction/application/load_introductions_test.dart` passed with `00:00 +16: All tests passed!`; `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"` passed with `00:00 +1: All tests passed!`; `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"` passed with `00:00 +1: All tests passed!`; final `git diff --check` passed with no output. Decision/blocker: no blocking issues found; direct helper, Feed, and Orbit evidence satisfies the DIF-002 closure bar, and named intro gate plus `orbit_intros_wiring_test.dart` remain correctly out of scope for this session.
- `2026-05-06 19:26 CEST` - Final verdict written. Files touched since last update: this plan only. Decision/blocker: `accepted`; no fix pass needed after QA; no blocking issues remain. Next action: stop this DIF-002-only execution session.
- `2026-05-06 19:24 CEST` - QA Reviewer started. Files inspected since last update: this plan progress, source matrix row diff, current dirty state/stat, DIF-002 owner code/test diffs, Feed/Orbit count routing context, repository/count references by `rg`, changed filename list, and `git diff --check`. Command/result: `git diff --check` passed with no output. Decision/blocker: no blocker found yet; direct GREEN commands are being rerun for independent QA confidence. Next action: run the three DIF-002 direct test commands.
- `2026-05-06 19:22 CEST` - Executor completion recorded. Files inspected since last update: `git status --short`, `git diff --stat`, `git diff --check`, and targeted `rg` checks for the helper/tests/source row. Result: `git diff --check` passed with no whitespace errors; final dirty state includes expected controller-owned DIF-001 docs/code plus DIF-002 owner files and this plan. Decision/blocker: no unresolved DIF-002 blocker; no commit, stage, PR, named intro gate, or `orbit_intros_wiring_test.dart` run was performed because the plan scoped them out. Next action: return final executor summary.
- `2026-05-06 19:23 CEST` - QA Reviewer spawn started. Files inspected since last update: Executor final handoff and current plan progress. Command running: `codex -a never exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C . -s danger-full-access -o /tmp/dif002-qa-result.txt -`. Decision/blocker: using separate CLI child-agent isolation for QA; no fix pass started unless QA returns blocking issues. Next action: wait for QA sufficiency review.
- `2026-05-06 19:21 CEST` - GREEN direct tests completed and source row updated. Commands/results: `flutter test test/features/introduction/application/load_introductions_test.dart` passed with `00:00 +16: All tests passed!`; `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"` passed with `00:00 +1: All tests passed!`; `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"` passed with `00:00 +1: All tests passed!`. Files touched since last update: this plan and `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` row `DIF-002` only. Decision/blocker: closure bar satisfied by direct helper, Feed, and Orbit evidence; named intro gate remains deferred by plan. Next action: final status inspection and executor completion.
- `2026-05-06 19:20 CEST` - Implementation completed. Files touched since last update: `lib/features/introduction/application/load_introductions_use_case.dart`, `lib/features/feed/presentation/screens/feed_wired.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, and this plan; formatted product files with `dart format lib/features/introduction/application/load_introductions_use_case.dart lib/features/feed/presentation/screens/feed_wired.dart lib/features/orbit/presentation/screens/orbit_wired.dart`. Decision/blocker: repository `countPendingIntroductions(...)` remains raw; Feed now loads rows after expiration and counts folded pending targets, while preserving group invite addition and request-id stale handling; Orbit keeps raw grouped rendering data and uses the helper only for `_introsCount`. Next action: run the three direct GREEN commands.
- `2026-05-06 19:20 CEST` - RED direct tests completed before product edits. Commands/results: `flutter test test/features/introduction/application/load_introductions_test.dart` failed as expected with `Method not found: 'countFoldedPendingIntroductionTargets'` at the four new helper-test call sites; `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"` failed as expected with `Expected: <1> Actual: <2>`; `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"` failed as expected with `Expected: <1> Actual: <2>`. Decision/blocker: RED evidence matches the planned raw-count bug. Next action: implement shared helper and route Feed/Orbit counts through it.
- `2026-05-06 19:19 CEST` - Planned RED tests added before product edits. Files touched since last update: this plan, `test/features/introduction/application/load_introductions_test.dart`, `test/features/feed/presentation/screens/feed_wired_test.dart`, and `test/features/orbit/presentation/screens/orbit_wired_test.dart`; formatted touched test files with `dart format test/features/introduction/application/load_introductions_test.dart test/features/feed/presentation/screens/feed_wired_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart`. Decision/blocker: product files are still unedited by this executor. Next action: run the three direct RED commands.
- `2026-05-06 19:16 CEST` - Executor started in workspace `/Users/I560101/Project-Sat/mknoon-2/flutter_app`. Files inspected since last update: `git status --short`, this DIF-002 plan, `lib/features/introduction/application/load_introductions_use_case.dart`, `test/features/introduction/application/load_introductions_test.dart`, `lib/features/feed/presentation/screens/feed_wired.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, `test/features/feed/presentation/screens/feed_wired_test.dart`, `test/features/orbit/presentation/screens/orbit_wired_test.dart`, and `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`. Decision/blocker: dirty state matches the controller-owned DIF-001 snapshot; no product edits made yet. Next action: add planned direct RED tests.
- `2026-05-06 19:14 CEST` - Contract extraction started. Files inspected since last update: `git status --short`, this DIF-002 plan, and `Test-Flight-Improv/test-gate-definitions.md`. Decision/blocker: pre-execution dirty state matches the controller-owned DIF-001 snapshot; extracting only DIF-002 scope before any code/test edits. Next action: record extracted contract and spawn isolated Executor.
- `2026-05-06 19:15 CEST` - Contract extracted. Files inspected since last update: this DIF-002 plan and gate definitions. Decision/blocker: scope is shared folded pending-count helper plus Feed/Orbit count-source routing only; RED tests required first in `load_introductions_test.dart`, `feed_wired_test.dart`, and `orbit_wired_test.dart`; direct tests are the three plan-listed `flutter test` commands; named intro gate is documented as deferred for later integrated sessions by the plan. Next action: spawn Executor with model `gpt-5.5` and reasoning effort `xhigh`.
- `2026-05-06 19:16 CEST` - Executor spawn started. Files inspected since last update: no additional files. Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C . -s danger-full-access -a never -o /tmp/dif002-executor-result.txt -`. Decision/blocker: using CLI child-agent isolation. Next action: wait for Executor result and inspect file-backed evidence.
- `2026-05-06 19:17 CEST` - Executor spawn retry needed. Files inspected since last update: Codex CLI error output. Decision/blocker: first child did not materialize because `-a never` was passed after `exec`; retrying with approval policy as a top-level Codex option. Next action: relaunch Executor with corrected CLI option ordering.

## Final Execution Verdict

- Final verdict: `accepted`
- Spawned-agent isolation used: yes; separate `codex exec` child agents ran Executor and QA Reviewer with model `gpt-5.5` and reasoning effort `xhigh`.
- Local sequential fallback used: no.
- Files changed for `DIF-002`: `lib/features/introduction/application/load_introductions_use_case.dart`, `lib/features/feed/presentation/screens/feed_wired.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, `test/features/introduction/application/load_introductions_test.dart`, `test/features/feed/presentation/screens/feed_wired_test.dart`, `test/features/orbit/presentation/screens/orbit_wired_test.dart`, this plan file, and source matrix row `DIF-002` in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`.
- Tests added or updated: helper-level folded pending-count tests, Feed folded Orbit badge duplicate-target test, and Orbit folded intro-count duplicate-target test.
- Exact RED commands/results: `flutter test test/features/introduction/application/load_introductions_test.dart` failed with missing `countFoldedPendingIntroductionTargets`; `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"` failed with `Expected: <1> Actual: <2>`; `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"` failed with `Expected: <1> Actual: <2>`.
- Exact GREEN commands/results: Executor and QA both ran `flutter test test/features/introduction/application/load_introductions_test.dart` (`+16`), `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"` (`+1`), and `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"` (`+1`); QA also ran `git diff --check`, which passed with no output.
- Named gates: none required by this `DIF-002` plan; `./scripts/run_test_gates.sh intro` and `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart` stayed out of scope.
- Blocking issues remaining: none.
- Non-blocking follow-ups deferred: none for `DIF-002`; QA noted incidental `dart format` churn in touched test files as non-blocking.
- Why safe to consider complete: shared folded pending-count semantics are covered directly and consumed by Feed and Orbit count sources, raw repository count/loading/grouped rendering semantics remain unchanged, and source row `DIF-002` is closed with matching direct evidence.

## Planning Progress

- `2026-05-06 19:11 CEST` - Arbiter completed. Files inspected since last update: reviewer findings and draft plan sections. Decision/blocker: one structural blocker confirmed: regression-first sequencing for Feed/Orbit user-facing tests is under-specified. Next action: patch the plan once, then run one final reviewer and arbiter pass.
- `2026-05-06 19:12 CEST` - Final Reviewer started. Files inspected since last update: patched `step-by-step implementation plan` and `exact tests and gates to run` sections. Decision/blocker: checking the one structural patch only. Next action: confirm sufficiency or identify remaining blockers.
- `2026-05-06 19:12 CEST` - Final Reviewer completed. Files inspected since last update: patched `step-by-step implementation plan` and `exact tests and gates to run` sections. Decision/blocker: sufficient as-is; regression-first sequencing now covers helper, Feed, and Orbit tests before production edits. Next action: final Arbiter stop-rule check.
- `2026-05-06 19:12 CEST` - Final Arbiter started. Files inspected since last update: final reviewer finding and patched plan. Decision/blocker: applying stop rule. Next action: classify remaining findings.
- `2026-05-06 19:12 CEST` - Final Arbiter completed. Files inspected since last update: final reviewer finding and patched plan. Decision/blocker: no structural blockers remain; incremental detail about exact `--plain-name` strings is intentionally deferred. Next action: stop planning; plan is reusable for `DIF-002` execution.

## Evidence Collector Notes

- `DIF-001` dependency is satisfied by the source matrix and breakdown ledger, and `foldIntroductionsForReview(...)` now exists in `lib/features/introduction/application/load_introductions_use_case.dart`.
- Current folded projection groups active review rows by the viewer's counterparty peer id. It includes overall `pending` and `alreadyConnected` rows for review visibility, while tracking pending/accepted/passed current-viewer decision ids.
- `IntroductionRepository.countPendingIntroductions(...)` delegates to `dbCountPendingIntroductions(...)`; the DB query counts raw rows where the viewer is recipient or introduced and `status = 'pending'`.
- `InMemoryIntroductionRepository.countPendingIntroductions(...)` mirrors the raw-row pending-only count.
- `FeedWired._refreshOrbitBadgeCount()` expires old intros and then reads `introRepo.countPendingIntroductions(ownPeerId)` for the Orbit nav badge.
- `OrbitWired._loadIntroductions()` expires old intros, loads `loadIntroductionsForUser(...)`, and sets `_introsCount = pending.length`, so duplicate raw rows still inflate the Orbit review count.
- Existing tests already pin `alreadyConnected` visibility through `getPendingIntroductionsForUser(...)` and exclusion from `countPendingIntroductions(...)`; expired and passed/non-pending rows are excluded from pending count. No existing direct test covers two introducers creating duplicate pending rows for the same viewer/counterparty.
- `Test-Flight-Improv/test-gate-definitions.md` defines `./scripts/run_test_gates.sh intro` as the named intro gate and requires direct Orbit/Feed companion suites when intro changes affect Orbit or Feed follow-up surfaces.

## real scope

Implement only the `DIF-002` folded count contract:

- Add a shared application-level folded pending-count helper near the existing folded projection in `lib/features/introduction/application/load_introductions_use_case.dart`.
- The helper counts distinct viewer counterparties among true overall `pending` introduction rows where the current user is either `recipientId` or `introducedId`.
- Route current user-facing count sources through that helper:
  - `FeedWired._refreshOrbitBadgeCount()` should stop using raw `introRepo.countPendingIntroductions(...)` for the Orbit nav badge.
  - `OrbitWired._loadIntroductions()` should stop using raw `pending.length` for `_introsCount`.
- Preserve raw introduction loading, raw grouped rendering data, persisted row shape, existing `countPendingIntroductions(...)` repository contract, and all accept/pass/delete behavior.
- Do not change DB schema, migrations, delivery, notification routing, simulator scripts, or folded row rendering/action semantics in this session.

Owner files:

- `lib/features/introduction/application/load_introductions_use_case.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `test/features/introduction/application/load_introductions_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart` only if the implementation uses or updates that lighter wiring harness

Read-only fallback files if implementation evidence disproves the application-helper path:

- `lib/features/introduction/domain/repositories/introduction_repository.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
- `lib/core/database/helpers/introductions_db_helpers.dart`
- `test/core/database/helpers/intro_db_helpers_test.dart`
- `test/shared/fakes/in_memory_introduction_repository.dart`

## closure bar

`DIF-002` is good enough when direct tests prove that duplicate raw pending rows for the same viewer/counterparty count as one user-facing pending/review target on both recipient-side and introduced-side views, while `alreadyConnected`, `passed`, `expired`, and other non-`pending` overall statuses do not inflate badges. Feed and Orbit user-facing counts must both consume the same folded count semantics. Existing raw list loading and review visibility for `alreadyConnected` rows must remain unchanged.

## source of truth

- Current code and tests are authoritative when they conflict with proposal prose.
- The active product contract is source row `DIF-002` in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`.
- Session decomposition and dependency state come from `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`.
- Named gate requirements come from `Test-Flight-Improv/test-gate-definitions.md`.
- `DIF-001` is an accepted dependency, and its current folded projection helper/model in `load_introductions_use_case.dart` should be reused instead of replanned.

## session classification

`implementation-ready`

## exact problem statement

The folded review projection can now represent two raw pending introductions from different introducers to the same viewer/counterparty as one review target, but the current count sources still count raw rows. `FeedWired` reads `countPendingIntroductions(...)`, and `OrbitWired` sets `_introsCount` from `pending.length`, so duplicate raw rows can inflate user-facing badges/review counts. The fix must count folded targets for user-facing pending/review counts without letting `alreadyConnected`, `passed`, `expired`, or other non-pending rows re-enter badge counts.

## files and repos to inspect next

Before editing during execution, inspect:

- `lib/features/introduction/application/load_introductions_use_case.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `test/features/introduction/application/load_introductions_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

Run `git status --short` before editing. Preserve existing DIF-001 changes in `load_introductions_use_case.dart`, `load_introductions_test.dart`, the source matrix, and the breakdown ledger. Do not revert or restage unrelated dirty files.

## existing tests covering this area

- `test/features/introduction/application/load_introductions_test.dart` covers `loadIntroductionsForUser(...)`, `groupByIntroducer(...)`, and the new `foldIntroductionsForReview(...)` projection from `DIF-001`, including recipient-side and introduced-side target resolution.
- `test/core/database/helpers/intro_db_helpers_test.dart` pins DB helper behavior: loading includes `already_connected` rows for visibility, while DB pending count counts only raw `pending` rows.
- `test/features/introduction/application/handle_incoming_introduction_test.dart` pins `alreadyConnected` visibility and exclusion from pending badge count through repository behavior.
- `test/features/introduction/regression/introduction_regression_test.dart` pins expired exclusion from `countPendingIntroductions(...)`.
- `test/features/feed/presentation/screens/feed_wired_test.dart` already verifies Feed's Orbit badge excludes expired introductions after expiration.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` already checks intro badge count in single-row flows.

Missing coverage:

- No direct test currently proves folded count for duplicate raw pending rows with the same counterparty from two introducers.
- No direct test currently proves the introduced-side duplicate count case.
- No current Feed/Orbit user-facing count test proves duplicate folded targets count once.

## regression/tests to add first

Add failing direct tests before product edits:

- In `test/features/introduction/application/load_introductions_test.dart`, add a `folded pending count` group for the shared helper:
  - recipient viewer: two `pending` rows, same `introducedId`, different `introducerId`s, count is `1`.
  - introduced viewer: two `pending` rows, same `recipientId`, different `introducerId`s, count is `1`.
  - different counterparties still count separately.
  - `alreadyConnected`, `passed`, `expired`, and `mutualAccepted` rows do not count, while overall `pending` rows still count even if the current viewer's individual status is already `accepted` to preserve the existing one-sided accept count rule.
- In `test/features/feed/presentation/screens/feed_wired_test.dart`, add a first-load Orbit badge test with two pending rows for the same `otherPeerId` from different introducers; expected badge count is `1`.
- In `test/features/orbit/presentation/screens/orbit_wired_test.dart`, add or adapt an Orbit intro badge/review-count test with two pending rows for the same `otherPeerId` from different introducers; expected intro badge/review count is `1`.
- Use `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart` only if the implementation exposes the count helper through the existing non-widget wiring harness; do not add duplicate coverage there if the `OrbitWired` widget test already proves the user-facing count.

## step-by-step implementation plan

1. Reconfirm dirty state with `git status --short` and read the owner files listed above.
2. Add all planned direct RED tests before product code:
   - helper-level folded pending-count tests in `load_introductions_test.dart`
   - Feed first-load Orbit badge duplicate-target test in `feed_wired_test.dart`
   - Orbit intro badge/review-count duplicate-target test in `orbit_wired_test.dart`, or the lighter `orbit_intros_wiring_test.dart` only if that is the actual count seam
3. Run the new direct tests for RED before product edits. If an existing unrelated failure appears, record it under known-failure interpretation before continuing.
4. Implement a synchronous helper in `load_introductions_use_case.dart`, for example `countFoldedPendingIntroductionTargets({required List<IntroductionModel> introductions, required String ownPeerId})`, using the same viewer counterparty logic as the folded projection but filtering to `IntroductionOverallStatus.pending`.
5. If Feed needs an async convenience helper, add the smallest wrapper that calls `loadIntroductionsForUser(...)` then the synchronous helper. Do not call `foldIntroductionsForReview(...)` directly for badge count unless it first excludes `alreadyConnected` rows, because folded review visibility and folded badge count have different status filters.
6. Route `OrbitWired._loadIntroductions()` to compute `_introsCount` with the shared helper while leaving `_groupedIntros` and `_introducerUsernames` based on raw `pending` rows for pre-DIF-004 rendering compatibility.
7. Route `FeedWired._refreshOrbitBadgeCount()` through the same folded count semantics after `expireOldIntroductions(...)`, preserving pending group invite count addition and request-id stale result handling.
8. Stop and revisit the plan only if implementation evidence shows `FeedWired` or another user-facing badge cannot safely load rows and must keep using `countPendingIntroductions(...)`. In that case, switch to a repository/DB count change, add DB helper and fake tests, and explicitly preserve the same status and counterparty rules.
9. Re-run the same direct suites for GREEN after implementation.
10. Update source row `DIF-002` only after direct evidence is green, recording exact commands and outcomes. Do not close other rows.

## risks and edge cases

- `alreadyConnected` rows are intentionally visible in review loading but must remain excluded from user-facing pending badges.
- Overall `pending` rows where the current viewer has already accepted are currently still counted until the overall intro leaves pending; preserve that rule unless current tests prove it is stale.
- Recipient-side and introduced-side target resolution must mirror `DIF-001` so the same counterparty folds regardless of which side the viewer is on.
- Feed badge refresh already has expiration and stale request-id handling; keep that flow intact when replacing the raw count call.
- Orbit still renders raw grouped rows until later folded UI sessions; only the count changes in this session.
- Loading rows for Feed instead of using the DB count may cost one row query on badge refresh, but the scope is small and avoids changing broad repository semantics.

## exact tests and gates to run

During execution, after adding RED tests and before implementation, run only the direct tests needed to capture RED:

```bash
flutter test test/features/introduction/application/load_introductions_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"
```

After implementation, run the direct suites touched by this session:

```bash
flutter test test/features/introduction/application/load_introductions_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"
```

If `orbit_intros_wiring_test.dart` is changed, also run:

```bash
flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart
```

Named gate for later integrated sessions, not required during planning and normally deferred until integrated intro UI/wiring sessions:

```bash
./scripts/run_test_gates.sh intro
```

## known-failure interpretation

No tests were executed during planning, so there is no fresh baseline. During execution, a RED result from the newly added folded count tests is expected before production changes. If an existing direct suite is already red before the new tests are added, capture the exact failing test names and do not classify them as DIF-002 regressions unless the failure intersects the folded count owner files. Do not close `DIF-002` on partially green evidence if any newly added folded count regression remains red.

## done criteria

- Shared folded pending-count helper exists and is used by both current user-facing count sources.
- Direct helper tests cover recipient-side duplicates, introduced-side duplicates, distinct targets, and status exclusions.
- Feed badge direct test proves duplicate rows for one folded target count once.
- Orbit intro badge/review count direct test proves duplicate rows for one folded target count once.
- Existing `alreadyConnected`, expired, passed, and one-sided accepted count rules remain intact.
- No DB migration or repository count semantic change is introduced unless the fallback path is explicitly taken and covered by DB/fake tests.
- Source row `DIF-002` is updated from `Open` to `Closed` only with exact green direct-test evidence.

## scope guard

Non-goals:

- Do not implement folded Accept/Pass actions; that is `DIF-003`.
- Do not render folded rows in `IntrosTab` or `OrbitScreen`; that is `DIF-004`.
- Do not rework Orbit processing state, folded action dispatch, or full Feed/Orbit integration beyond count sources; that is `DIF-005`.
- Do not add the four-identity simulator proof; that is `DIF-006`.
- Do not run final program closure or update unrelated matrix rows; that is `DIF-007`.
- Do not change SQLite schema, introduction IDs, delivery/outbox behavior, notification routing, contact creation, expiration policy, or delete semantics.
- Do not replace repository APIs broadly unless the application-helper path is impossible to use safely.

Overengineering signals:

- Adding a new repository abstraction solely for counts while only Feed and Orbit need folded badge semantics.
- Changing raw row loading or grouped raw rendering before the folded UI session.
- Making folded count depend on introducer display names, row ordering, or UI grouping headers.

## accepted differences / intentionally out of scope

- Repository `countPendingIntroductions(...)` may remain a raw-row count in this session. The intentionally scoped replacement is the shared application helper used by user-facing badge/review counts.
- Folded review projection includes `alreadyConnected` rows for visibility, but folded pending badge count filters them out. That difference is intentional and already reflected by existing badge exclusion rules.
- Group invite badge counts remain additive and are not folded with introductions.
- Device/simulator/relay proof is intentionally out of scope for `DIF-002` unless implementation unexpectedly changes device-backed behavior, which this plan avoids.

## dependency impact

- `DIF-003` can rely on `DIF-002` only for count semantics, not folded action behavior.
- `DIF-004` should keep using the `DIF-001` projection for row rendering and should not reinterpret badge status rules.
- `DIF-005` should verify that Orbit/Feed integration still routes through the shared folded count helper; if `DIF-002` could not update a user-facing count source, `DIF-005` must explicitly own the remaining source.
- `DIF-006` and `DIF-007` should not proceed to final proof/closure until `DIF-002` source row records green direct count evidence.

## expected docs updates

When implementation and direct verification are complete, update only the `DIF-002` row in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` with:

- status `Closed`
- exact tests added and exact green command output summaries
- the chosen count path, especially whether repository `countPendingIntroductions(...)` stayed raw or changed

Do not mark breakdown ledger result `accepted` in this implementation session unless the closure-audit workflow explicitly owns that update.

## Reviewer Findings

Verdict: sufficient with adjustment.

- Missing files, tests, regressions, or gates: no owner file class is missing. Direct helper, Feed badge, and Orbit badge/review tests are identified. The named intro gate and companion direct-test rule are present.
- Stale or incorrect assumptions: no stale source-of-truth issue found. The application-helper path is consistent with the proposal option that allows a repository count replacement where user-facing badges need folded count.
- Overengineering: no overengineering in the selected first path. Keeping repository/DB count raw is acceptable if user-facing call sites are routed through the shared helper.
- Decomposition sufficiency: mostly sufficient, but step ordering currently makes Feed/Orbit regressions appear after product edits. That weakens the regression-first contract for the actual user-facing surfaces.
- Minimum adjustment needed: revise steps and test commands so all planned DIF-002 regressions are added and run for RED before production edits, then implementation routes helper, Feed, and Orbit count sources.

## Arbiter Decisions

Structural blockers:

- Regression-first sequencing was incomplete for the Feed/Orbit user-facing count regressions. The plan must require those tests before the corresponding production edits.

Incremental details:

- Exact `--plain-name` strings may be adjusted during implementation to match the final test names.

Accepted differences:

- Repository `countPendingIntroductions(...)` can remain raw-row based if Feed and Orbit route through the shared application helper.
- DB helper tests are required only if the fallback repository/DB path is taken.

## Final Reviewer Findings

Verdict: sufficient as-is.

- Missing files, tests, regressions, or gates: none remaining.
- Stale or incorrect assumptions: none found after the structural patch.
- Overengineering: none introduced by the patch.
- Decomposition sufficiency: sufficient; all planned regressions are now required before production edits, and fallback repository/DB work is gated by implementation evidence.
- Minimum needed to make the plan sufficient: no further changes.

## Final Arbiter Decision

Structural blockers:

- None remaining.

Incremental details intentionally deferred:

- Exact `--plain-name` strings may be adjusted to match final test names during implementation.

Accepted differences intentionally left unchanged:

- User-facing folded count can be provided by an application helper while repository `countPendingIntroductions(...)` remains raw-row based.
- DB helper/fake count tests remain conditional on taking the repository/DB fallback path.

Stop-rule result: no new structural blocker after the patch, so planning stops with `Status: execution-ready`.
