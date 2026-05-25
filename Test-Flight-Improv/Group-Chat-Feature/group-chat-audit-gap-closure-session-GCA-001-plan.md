Status: execution-ready

# GCA-001 - Group List Load Error Surface Plan

## Planning Progress

- `2026-05-23T18:50:55+02:00` - Arbiter completed. Files inspected since last update: patched plan sections. Decision/blocker: structural blocker was patched by making `group_list_screen_test.dart` run-only, not edit-planned. Next action: final reviewer pass.
- `2026-05-23T18:51:12+02:00` - Final Reviewer started. Files inspected since last update: patched plan artifact. Decision/blocker: verify the patched plan no longer permits a fourth non-doc edit. Next action: final sufficiency result.
- `2026-05-23T18:51:33+02:00` - Final Reviewer completed. Files inspected since last update: patched plan grep for optional/fourth-file wording and status. Decision/blocker: sufficient as-is; no structural blocker remains. Next action: final arbiter pass.
- `2026-05-23T18:51:49+02:00` - Final Arbiter started. Files inspected since last update: final reviewer notes. Decision/blocker: classify remaining details and decide execution readiness. Next action: final status.
- `2026-05-23T18:52:01+02:00` - Final Arbiter completed. Files inspected since last update: final plan artifact. Decision/blocker: no structural blockers remain; plan is execution-ready. Next action: hand off compact planning verdict.

## Execution Progress

- `2026-05-23T18:53:44+02:00` - Contract extracted. Files inspected since last update: session plan, session breakdown, source matrix, git status. Decision/blocker: nested spawned agents are unavailable in this toolset; proceeding under local sequential fallback as the fresh execution agent. Next action: inspect owner files and update the focused wired regression first.
- `2026-05-23T18:54:11+02:00` - Executor local fallback started. Files inspected since last update: `group_list_wired.dart`, `group_list_screen.dart`, `group_list_wired_test.dart`, run-only `group_list_screen_test.dart`. Decision/blocker: existing `loading clears on error` test asserts the false empty-state bug; rewrite it as the required failing regression. Next action: edit `group_list_wired_test.dart` only, then run the focused selector for RED evidence.
- `2026-05-23T18:54:28+02:00` - Focused RED test started. Files touched since last update: `group_list_wired_test.dart`. Command: `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart --plain-name "load failure shows retryable error instead of empty state"`. Decision/blocker: production code still unchanged; expecting failure on missing error/retry UI. Next action: capture failure, then implement the minimal wired/screen state.
- `2026-05-23T18:55:25+02:00` - Focused RED test completed. Files touched since last update: `group_list_wired_test.dart`. Command result: failed as expected because `Couldn't load groups` was not found after `_ThrowingGroupRepository.getActiveGroups()` threw. Decision/blocker: valid failing-first evidence captured. Next action: edit `group_list_screen.dart` and `group_list_wired.dart` for minimal error/retry state.
- `2026-05-23T18:56:49+02:00` - Executor implementation completed; focused verification started. Files touched since last update: `group_list_wired.dart`, `group_list_screen.dart`, `group_list_wired_test.dart`. Command: `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart --plain-name "load failure shows retryable error instead of empty state"`. Decision/blocker: implementation adds local error state, screen error rendering, and retry into existing `_loadGroups()` path. Next action: capture focused verification result.
- `2026-05-23T18:57:17+02:00` - Focused verification failed; fix pass started. Files touched since last update: `group_list_wired_test.dart`. Command result: retry invoked the throwing repository again, but the test tried to observe a transient loading row after a fast synchronous failure. Decision/blocker: adjust the fake to hold the second failure open so the retry loading transition is deterministic. Next action: patch test fake only, rerun focused selector.
- `2026-05-23T18:57:39+02:00` - Focused fix-pass verification started. Files touched since last update: `group_list_wired_test.dart`. Command: `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart --plain-name "load failure shows retryable error instead of empty state"`. Decision/blocker: fake now gates the retry failure to prove loading and retry path deterministically. Next action: capture focused pass/fail result.
- `2026-05-23T18:58:09+02:00` - Focused fix-pass verification failed; test-fake patch continued. Files touched since last update: `group_list_wired_test.dart`. Command result: second failure gate stayed unresolved because the fake cleared the completer before `releaseNextFailure()`. Decision/blocker: test fake bookkeeping bug only; production behavior unchanged. Next action: keep the held completer releasable, rerun focused selector.
- `2026-05-23T18:58:32+02:00` - Focused fix-pass verification restarted. Files touched since last update: `group_list_wired_test.dart`. Command: `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart --plain-name "load failure shows retryable error instead of empty state"`. Decision/blocker: retry gate is now releasable. Next action: capture focused pass/fail result.
- `2026-05-23T18:58:51+02:00` - Focused verification passed; direct presentation tests started. Files touched since last update: `group_list_wired.dart`, `group_list_screen.dart`, `group_list_wired_test.dart`. Focused command result: passed. Direct command: `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart test/features/groups/presentation/group_list_screen_test.dart`. Decision/blocker: required focused proof is green. Next action: capture direct presentation result.
- `2026-05-23T18:59:12+02:00` - Direct presentation tests passed; named gate started. Files touched since last update: no new files. Direct command result: passed. Named gate command: `./scripts/run_test_gates.sh groups`. Decision/blocker: named group gate is feasible locally. Next action: capture named gate result, then run `git diff --check`.
- `2026-05-23T19:01:19+02:00` - Named group gate failed; triage started. Files inspected since last update: `scripts/run_test_gates.sh`, gate test list, group integration import references, group membership failure context. Command result: `./scripts/run_test_gates.sh groups` exited 1 after `group_membership_smoke_test.dart`, ending at `00:52 +289 -12`; final visible failure was `GM-028 empty PeerId add event does not persist or block valid delivery`, expecting one recipient but getting none. Decision/blocker: touched files are group-list presentation only, and group integration gate files have no `GroupList`/`group_list` references; classify as unrelated-to-this-session unless isolated rerun contradicts that. Next action: run isolated final-visible failing selector, then `git diff --check`.
- `2026-05-23T19:01:42+02:00` - Named gate triage completed; final hygiene started. Files inspected since last update: `group_membership_smoke_test.dart` GM-028 selector. Triage command: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-028 empty PeerId add event does not persist or block valid delivery"`; result: failed the same way in isolation, with no group-list import path. Decision/blocker: group gate remains red due to unrelated membership integration failures. Next action: run `git diff --check`, then local QA review.
- `2026-05-23T19:02:20+02:00` - Local QA found a scope issue; fix pass started. Files inspected/touched since last update: `group_list_wired.dart`. Decision/blocker: initial `_beginLoadGroups()` ran for stream/resume refreshes too, which could add a loading skeleton when no content exists; narrow loading transition to the explicit retry path to preserve existing refresh behavior. Next action: patch `group_list_wired.dart` and rerun focused/direct verification.
- `2026-05-23T19:02:43+02:00` - Scope fix completed; focused/direct re-verification started. Files touched since last update: `group_list_wired.dart`. Command: `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart --plain-name "load failure shows retryable error instead of empty state"`. Decision/blocker: retry is the only path that forces the no-content loading transition now. Next action: capture focused result and rerun direct presentation command.
- `2026-05-23T19:03:02+02:00` - Focused re-verification passed; direct re-verification started. Files touched since last update: no new files. Focused command result: passed. Direct command: `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart test/features/groups/presentation/group_list_screen_test.dart`. Decision/blocker: focused retry/error behavior remains green after scope fix. Next action: capture direct result and rerun `git diff --check`.
- `2026-05-23T19:03:23+02:00` - Direct re-verification passed; final hygiene started. Files touched since last update: no new files. Direct command result: passed. Command: `git diff --check`. Decision/blocker: required direct proof is green after the final production patch; named gate remains red only on unrelated membership integration tests. Next action: capture hygiene result and complete local QA.
- `2026-05-23T19:04:04+02:00` - Final hygiene and local QA completed. Files inspected since last update: final diffs for `group_list_wired.dart`, `group_list_screen.dart`, `group_list_wired_test.dart`, `git status`. `git diff --check` result: passed. Decision/blocker: no session-owned blocking issues remain; named group gate failure is unrelated to the touched group-list presentation files and has an explicit follow-up. Next action: return compact execution verdict.

## Final Execution Verdict

- Verdict: `accepted_with_explicit_follow_up`.
- Spawned-agent isolation used: no nested spawn tool was available; local sequential fallback was used inside this fresh execution agent.
- Files changed: `lib/features/groups/presentation/screens/group_list_wired.dart`, `lib/features/groups/presentation/screens/group_list_screen.dart`, `test/features/groups/presentation/group_list_wired_test.dart`.
- Tests updated: `group_list_wired_test.dart` rewrote `loading clears on error` into `load failure shows retryable error instead of empty state`, including retry-path proof.
- Required focused test: passed after failing first.
- Required direct presentation command: passed.
- Named group gate: run, but failed in unrelated `group_membership_smoke_test.dart` coverage (`./scripts/run_test_gates.sh groups` exited 1 at `00:52 +289 -12`; isolated `GM-028 empty PeerId add event does not persist or block valid delivery` also failed without importing the touched group-list files).
- Final hygiene: `git diff --check` passed.
- Blocking issues remaining: none for GCA-001.
- Non-blocking follow-up: repair or separately classify the pre-existing group membership gate failures before treating the full `groups` gate as green.
- Completion rationale: the session-owned false empty state is covered by a focused regression and fixed without touching more than the three allowed non-doc files; existing group-list presentation coverage still passes.

## Evidence Collector Notes

- Source row `GCA-001` is `Open` and scoped to `GroupListWired`, `GroupListScreen`, and focused widget/unit tests.
- `GroupListWired._loadGroups()` currently catches any load exception, emits `GROUP_LIST_FL_LOAD_ERROR`, sets `_isLoading = false`, and does not retain/pass a load-error state to the screen.
- `GroupListScreen` currently renders content when groups or pending invites exist, loading placeholders when `isLoading` is true, and the empty state otherwise. It has no load-error prop or retry affordance.
- `test/features/groups/presentation/group_list_screen_test.dart` covers rendering, empty, loading, loading-with-data, invite cards, and backlog summaries, but not a load-error state.
- `test/features/groups/presentation/group_list_wired_test.dart` already has `_ThrowingGroupRepository` and a current regression-shaped test named `loading clears on error` that asserts the wrong behavior: a repository failure hides the spinner and shows `No groups yet`.
- Direct gate evidence sources list focused group presentation tests and the group host suite. `Test-Flight-Improv/test-gates-reference.md` says the script wins for named gates and `./scripts/run_test_gates.sh groups` applies to group behavior changes.

## real scope

Change only the group-list initial load failure surface. `GroupListWired` should preserve a load-failure state when `groupRepo.getActiveGroups()` or the immediately associated list metadata loads fail, and `GroupListScreen` should render that state when there are no groups or pending invites to show. Keep successful group rendering, pending invite rendering, loading placeholders, empty state copy, invite accept/decline behavior, navigation, and stream refresh behavior unchanged.

Do not refactor group repositories, listeners, invite flows, group cards, navigation, persistence, bridge behavior, background lifecycle, localization, or design system components.

## closure bar

The session is good enough when a repository load failure on the group list is user-visible, does not show or imply the normal empty state, and has a minimal retry path back to the existing `_loadGroups()` behavior. Existing loading, empty, populated, and pending-invite states must still render as before.

## source of truth

- Primary row contract: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md` row `GCA-001`.
- Session decomposition: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md` session `GCA-001`.
- Current code and direct tests beat stale prose if they disagree.
- Gate source: `Test-Flight-Improv/test-gates-reference.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.

## session classification

`implementation-ready`

## exact problem statement

Today, when the group list repository load throws, `GroupListWired` logs a flow event and clears `_isLoading`, but it gives `GroupListScreen` no failure signal. With no loaded groups or pending invites, the screen falls through to `No groups yet`, which falsely tells the user there are no groups and gives no retry affordance.

The user-visible behavior must improve to distinguish:

- initial loading: loading skeleton/spinner;
- successful empty result: `No groups yet`;
- load failure with no displayable data: a concrete error state plus retry, with no `No groups yet` claim.

Existing successful data display must stay unchanged. If groups or pending invites are already displayable during a later refresh failure, this session should not replace visible data with a full-screen error unless implementation evidence proves that is already the local pattern.

## files and repos to inspect next

- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/screens/group_list_screen.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/groups/presentation/group_list_screen_test.dart` only as an unchanged regression file to run, not as a planned edit.
- Gate/script reference if command behavior is unclear: `scripts/run_test_gates.sh`, `Test-Flight-Improv/test-gates-reference.md`

## existing tests covering this area

- `test/features/groups/presentation/group_list_screen_test.dart`
  - Covers rendering groups, empty state, loading placeholders, loading-with-data, pending invites, expired invites, type badges, and backlog summaries.
  - Missing: explicit load-error state rendering.
- `test/features/groups/presentation/group_list_wired_test.dart`
  - Covers initial active-group load, stream refresh, pending invite load/refresh, invite accept/decline, navigation, unread counts, slow initial loading, and current error behavior.
  - Existing `loading clears on error` is the key failing-first candidate because it currently locks in the bug by expecting `No groups yet` after `_ThrowingGroupRepository.getActiveGroups()` throws.

## regression/tests to add first

TDD first step: in `test/features/groups/presentation/group_list_wired_test.dart`, change the existing `loading clears on error` test into a regression such as `load failure shows retryable error instead of empty state`.

The failing assertion should:

- use the existing `_ThrowingGroupRepository`;
- pump `GroupListWired` with that repository;
- wait for the failed initial load;
- expect the loading placeholder is gone;
- expect user-visible error copy such as `Couldn't load groups`;
- expect a retry affordance such as a `Retry` button;
- expect `find.text('No groups yet')` is `findsNothing`.

Do not add a second test file in this session. The two production files plus `group_list_wired_test.dart` already consume the three allowed non-doc file slots.

## step-by-step implementation plan

1. Add or rewrite the focused wired regression first in `test/features/groups/presentation/group_list_wired_test.dart`. Run only that selector and confirm it fails because the screen still shows `No groups yet` and has no error/retry UI.
2. In `lib/features/groups/presentation/screens/group_list_screen.dart`, add a minimal nullable load-error prop and nullable retry callback, both defaulting to no error. Render order should be: content if groups or pending invites exist; loading if `isLoading`; error if the error prop is set; otherwise the existing empty state.
3. Add a small private `_buildLoadErrorState` UI using existing `backgroundReadableColors`, a simple error icon, stable text, and a `TextButton` or `TextButton.icon` wired to the retry callback. Keep copy concise and testable. Do not add localization or a new component in this session.
4. In `lib/features/groups/presentation/screens/group_list_wired.dart`, add private state for the current load error. Clear it on successful load. On catch, set it while also clearing `_isLoading`, and pass it plus a retry callback to `GroupListScreen`.
5. Ensure retry invokes the existing load path and, when there is no current displayable content, puts the screen back into loading state before the async work. Do not change invite accept/decline reload semantics except for reusing the same load state handling.
6. Run the focused test selector. If it fails because more than `group_list_wired.dart`, `group_list_screen.dart`, and one focused test file are required, stop and mark the session blocked under the hard constraint.
7. Run the direct presentation tests and formatting/check gates listed below.

## risks and edge cases

- Later refresh failure after existing groups are displayed: avoid replacing visible content with an error screen unless there is no displayable data, because this row is about false empty state on load failure.
- Pending invites only: existing content branch should keep showing pending invite content, not the full-screen error.
- Retry loop: retry must not leave the loading skeleton stuck if the repository fails again.
- Async lifecycle: preserve the existing `mounted` checks around `_loadGroups()`.
- Error details: do not expose raw exception text to users; flow logging already records the technical error.

## exact tests and gates to run

Focused failing-first and fix verification:

```sh
flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart --plain-name "load failure shows retryable error instead of empty state"
```

Direct presentation coverage:

```sh
flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart test/features/groups/presentation/group_list_screen_test.dart
```

Named gate for group behavior changes:

```sh
./scripts/run_test_gates.sh groups
```

Final hygiene:

```sh
git diff --check
```

If the named group gate is too expensive for the executor's local budget, it may be deferred only with a truthful note; the focused wired test and direct presentation tests are not optional.

## known-failure interpretation

Treat failures in the focused wired selector as session-owned. Treat failures in the direct presentation command as session-owned only if they involve `GroupListWired`, `GroupListScreen`, or the new error-state expectations. For `./scripts/run_test_gates.sh groups`, investigate any failure, but do not classify unrelated pre-existing integration failures as caused by this session without a diff-linked reason. `Test-Flight-Improv/test-gates-reference.md` contains older known-failure notes for other gates; they do not excuse a new failure in the focused group-list tests.

## done criteria

- The focused wired regression fails before implementation and passes after implementation.
- Repository load failure is user-visible and does not show `No groups yet`.
- Retry is present and calls back into the existing load path.
- Existing group-list loading, empty, group-content, and pending-invite tests pass.
- No more than three non-doc files are touched.
- `git diff --check` passes.

## scope guard

Non-goals:

- no repository, database, bridge, listener, invite, navigation, or localization refactor;
- no new dependencies;
- no redesign or polish beyond the minimal error state;
- no changes to other group audit rows;
- no changes to source matrix or breakdown ledger during implementation until the session has actual passing evidence.

Stop and block if making this reliable requires touching more than three non-doc files, changing shared app error-state architecture, adding a global retry framework, or altering group/invite persistence semantics.

## accepted differences / intentionally out of scope

- This session does not define a global error component for all group screens; later rows may add analogous error states for contact pickers or conversation loads.
- This session does not guarantee full-screen error replacement when a refresh fails after existing groups or pending invites are already visible.
- This session does not add localized strings because the row requires a minimal bug fix and no polish.

## dependency impact

Closing `GCA-001` removes the group-list false-empty-state gap and gives later group presentation sessions a small local precedent for loading/error/empty separation. If this plan blocks under the three-file constraint, downstream sessions should not copy the group-list approach until the blocker is resolved.

## Reviewer Notes

- Sufficiency: sufficient with adjustment.
- Missing files/tests/gates: mandatory sections are present; direct focused test, direct presentation tests, group gate, and `git diff --check` are named.
- Stale/incorrect assumptions: no stale source-of-truth issue found. The current test suite already contains the failing seam via `_ThrowingGroupRepository`.
- Overengineering: no new shared architecture or dependencies are planned.
- Decomposition: narrow enough for one executor session, except optional `group_list_screen_test.dart` wording could accidentally make the implementation touch four non-doc files.
- Minimum adjustment needed: remove the optional screen-test path or explicitly require blocking before touching a fourth non-doc file.

## Final Reviewer Notes

- Sufficiency: sufficient as-is after the arbiter patch.
- Missing files/tests/gates: none.
- Stale/incorrect assumptions: none found.
- Overengineering: none; the plan stays to a local error prop, wired state, and one existing test file.
- Decomposition: enough to minimize hallucination during execution.
- Minimum needed to make sufficient: already done.

## Arbiter Notes

- Structural blockers: draft wording allowed an optional fourth non-doc file edit. Patched once by making `test/features/groups/presentation/group_list_screen_test.dart` run-only and requiring the regression to stay in `group_list_wired_test.dart`.
- Incremental details: none requiring another plan change.
- Accepted differences: no global/shared error component, no localization pass, and no later-session parity work in this session.

## Final Arbiter Notes

- Structural blockers remaining: none.
- Incremental details intentionally deferred: no pure-screen test edit; `group_list_screen_test.dart` remains an unchanged regression command because the wired repository-failure test proves the requested seam within the three-file cap.
- Accepted differences intentionally left unchanged: no shared error-state architecture, no localization, no behavior changes for later refresh failures when groups or pending invites are already visible.
- Final verdict: execution-ready.
