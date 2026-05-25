Status: execution-ready

# GCA-002B Add-Member Picker Loading/Error States Plan

## Planning Progress

- 2026-05-23 19:21:11 CEST - Arbiter completed. Files inspected since last update: reviewer notes and patched run-only test wording. Decision/blocker: the fourth-file wording risk was structural and has been patched; no additional structural blockers found. Next action: final reviewer pass.
- 2026-05-23 19:21:11 CEST - Final Reviewer started. Files inspected since last update: patched plan grep for `unless`, `contact_picker_screen_test`, and cap wording. Decision/blocker: verify the adjusted plan no longer permits over-scope implementation. Next action: final sufficiency result.
- 2026-05-23 19:21:11 CEST - Final Reviewer completed. Files inspected since last update: patched mandatory sections, test commands, and scope guard. Decision/blocker: sufficient as-is; no missing files, tests, gates, or stale assumptions remain. Next action: final arbiter pass.
- 2026-05-23 19:21:11 CEST - Final Arbiter started. Files inspected since last update: final reviewer notes. Decision/blocker: classify remaining details and decide execution readiness. Next action: final status.
- 2026-05-23 19:21:11 CEST - Final Arbiter completed. Files inspected since last update: final plan artifact. Decision/blocker: no structural blockers remain; plan is execution-ready. Next action: hand off compact planning verdict.

## Execution Progress

- 2026-05-23 19:24:15 CEST - Contract extracted. Files inspected since last update: session plan, breakdown row, source matrix row, scoped git status. Decision/blocker: spawned subagent tools are not exposed in this context; proceed with the user-authorized local sequential fallback inside this fresh execution agent. Next action: inspect owner files and add failing-first regressions.
- 2026-05-23 19:24:49 CEST - Executor running. Files inspected since last update: `contact_picker_wired.dart`, `contact_picker_screen.dart`, `contact_picker_wired_test.dart`, run-only `contact_picker_screen_test.dart`, contact repository fake/interface. Decision/blocker: current code has no loading/error state and directly renders the empty state while contact loading is unresolved. Next action: add the two wired failing-first regressions.
- 2026-05-23 19:25:28 CEST - RED selectors completed. Files touched since last update: `contact_picker_wired_test.dart`. Commands: focused loading selector failed because `Loading contacts...` was absent; focused failure selector failed with uncaught `StateError('contacts unavailable')` and no retryable error UI. Decision/blocker: expected RED confirmed. Next action: implement minimal loading/error props and wired retry state.
- 2026-05-23 19:26:58 CEST - Executor implementation completed. Files touched since last update: `contact_picker_wired.dart`, `contact_picker_screen.dart`, `contact_picker_wired_test.dart`. Commands: both focused selectors reran and passed. Decision/blocker: contact-loading and retryable failure states now pass focused coverage. Next action: run required direct contact picker suite.
- 2026-05-23 19:27:18 CEST - Direct suite completed. Files touched since last update: none. Command: `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/presentation/contact_picker_screen_test.dart` passed. Decision/blocker: direct contact picker regression coverage is green. Next action: run named `groups` gate.
- 2026-05-23 19:29:16 CEST - Named gate and hygiene completed. Files touched since last update: none. Commands: `./scripts/run_test_gates.sh groups` failed at `00:51 +289 -12`, final visible failure `GM-028 empty PeerId add event does not persist or block valid delivery`; isolated rerun of that selector also failed with the same assertion in `group_membership_smoke_test.dart`; `git diff --check` passed. Decision/blocker: classify group gate red as residual unrelated integration coverage, matching prior `GCA-001` evidence and no diff-linked path from contact picker presentation files. Next action: local QA review.
- 2026-05-23 19:29:57 CEST - QA Reviewer completed. Files inspected since last update: implementation diff, scoped status, GCA-001 gate precedent, GM-028 failure context. Decision/blocker: no session-owned blocking issues; touched non-doc implementation files are exactly the three allowed files, direct contact picker coverage is green, and the remaining gate red is unrelated residual integration coverage. Next action: write final execution verdict.

## Evidence Collector Notes

- Source row `GCA-002B` is `Open` and scoped to `ContactPickerWired`, `ContactPickerScreen`, and focused tests only.
- The breakdown says `GCA-002B` was split from create-group picker work to keep row-owned implementation within the three non-doc-file hard stop.
- `ContactPickerWired` initializes `_availableContacts` to an empty list, starts `_loadAvailableContacts()` in `initState`, and has no `_isLoadingContacts` or load-error state. A thrown `getActiveContacts()`, `getMembers()`, or `loadIdentity()` exception currently leaves the screen with empty contacts and no explicit recovery.
- `ContactPickerScreen` only receives `contacts`, `isInviting`, selection callbacks, and background preference. Its main content chooses `_buildEmptyState()` whenever `widget.contacts.isEmpty`, so both initial load and load failure can show `No contacts available`.
- Existing focused tests cover rendering, empty state, selection, invite flow, invite failure snackbars, and invite overlay loading. They do not cover initial contact loading or contact-load failure.
- `test/shared/fakes/in_memory_contact_repository.dart` returns active contacts synchronously enough for most tests; a focused test can use a small subclass/fake in `contact_picker_wired_test.dart` to hold or fail `getActiveContacts()` without editing shared fakes.
- `GCA-001` established a local precedent for separating loading, error, and empty states with minimal local props/state, but this session must not reuse or change group-list files.
- Gate docs and `scripts/run_test_gates.sh` define `./scripts/run_test_gates.sh groups` as the named group behavior gate. Recent matrix notes already record that this gate can be red on unrelated `group_membership_smoke_test.dart` `GM-028`.

## real scope

Change only the add-member contact picker loading/error surface.

Implementation may touch at most these three non-doc files:

- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/contact_picker_screen.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`

`test/features/groups/presentation/contact_picker_screen_test.dart` is run-only direct regression coverage for this session. Do not edit it during implementation.

Do not touch `CreateGroupPickerWired`, `CreateGroupPickerScreen`, repositories, shared fakes, invite application use cases, group membership logic, database code, localization files, or dependencies.

## closure bar

The session is good enough when the add-member picker clearly distinguishes:

- initial contact load in progress: no `No contacts available` empty claim;
- successful empty contact result: the existing `No contacts available` empty state remains;
- contact-load failure with no displayable contacts: a concrete retryable error is shown and the empty state is not shown.

Existing contact filtering, self/member exclusion, selection, invite CTA, invite overlay loading, back navigation, and invite result behavior must stay unchanged.

## source of truth

- Primary row contract: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md` row `GCA-002B`.
- Session decomposition: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md` session `GCA-002B`.
- Current code and focused tests beat stale prose if they disagree.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md`; if docs disagree with `scripts/run_test_gates.sh`, the script wins.
- Existing dirty worktree entries from prior sessions are not part of this session and must not be reverted.

## session classification

`implementation-ready`

## exact problem statement

Today, `ContactPickerWired` starts with `_availableContacts = []` and calls `_loadAvailableContacts()` asynchronously. `ContactPickerScreen` receives only that list and renders `No contacts available` whenever it is empty. While the initial load is unresolved, or after a contact/member/identity load throws, the user can see a false empty state instead of loading progress or a retryable error.

The user-visible behavior must improve without changing the invite pipeline: users should not be told there are no contacts while the picker is still loading or when contact loading failed.

## files and repos to inspect next

- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/contact_picker_screen.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`
- `test/features/groups/presentation/contact_picker_screen_test.dart` as run-only regression coverage
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/test-gates-reference.md`

## existing tests covering this area

- `test/features/groups/presentation/contact_picker_screen_test.dart`
  - Covers header/back, contact list rendering, empty state, toggle callback, selected count, selected icons, send-invites CTA, search, invite loading overlay, and readability.
  - Missing: initial contact-loading state and load-error state.
- `test/features/groups/presentation/contact_picker_wired_test.dart`
  - Covers filtering out existing members and self, selection, selected count, invite batch persistence, config publish, invite fanout, pop result, back result, stale duplicate failure, over-limit failure, invite warning feedback, and invite error snackbar.
  - Missing: unresolved initial contact load and contact-load failure before invite selection.

## regression/tests to add first

Add both failing-first regressions to `test/features/groups/presentation/contact_picker_wired_test.dart` before touching production:

1. `shows loading state instead of empty state while contacts load`
   - Use a local test fake/subclass whose `getActiveContacts()` waits on a `Completer`.
   - Pump `ContactPickerWired`.
   - Before releasing the completer, expect a loading indicator or stable loading copy and expect `No contacts available` is absent.
   - Release the completer with contacts, pump, and expect normal contact rows appear.

2. `contact load failure shows retryable error instead of empty state`
   - Use a local test fake/subclass that throws from `getActiveContacts()` on the first attempt and can succeed on retry.
   - Pump `ContactPickerWired`, wait for the failed load, and expect user-visible error copy such as `Couldn't load contacts`, a `Retry` button, and no `No contacts available`.
   - Tap `Retry`, let the fake return a contact, and expect the contact row appears and the error clears.

Run the new selectors before implementation and record that they fail because production still renders the empty state / lacks the error state.

## step-by-step implementation plan

1. Add the two wired regressions above in `contact_picker_wired_test.dart`. Keep all helper fakes local to that file; do not edit shared fakes.
2. Run each new selector and confirm RED evidence before production changes.
3. In `contact_picker_screen.dart`, add minimal props for contact-loading state, load-error message, and retry callback, all with defaults that preserve existing callers.
4. Change the main content render order so non-empty contacts still show the list; otherwise show loading first, then error, then the existing empty state.
5. Add small private loading and error builders using existing readable colors, `CircularProgressIndicator` or a simple icon, stable copy, and a `TextButton` retry affordance. Do not add localization or new shared components.
6. In `contact_picker_wired.dart`, add `_isLoadingContacts` initialized for initial load, a nullable `_contactLoadErrorMessage`, and a private load-error copy constant.
7. Wrap `_loadAvailableContacts()` in `try/catch`; on success set sorted contacts, clear loading and error; on failure emit a focused flow event, clear loading, and set the user-facing error only when there are no displayable contacts.
8. Pass `isLoadingContacts`, `contactLoadErrorMessage`, and retry callback into `ContactPickerScreen`.
9. Keep `_isInviting` and invite error snackbar behavior unchanged; the new loading/error state is only for loading contacts into the picker.
10. Rerun focused selectors, then direct contact picker tests and final hygiene.
11. Stop and mark blocked if the executor finds this cannot be implemented without touching more than the three allowed non-doc files.

## risks and edge cases

- Initial async load must not flash the empty state before the first repository result.
- Retry must clear the error and show loading while no contacts are displayable, then either show contacts or restore the retryable error.
- A real empty successful result must still show `No contacts available`.
- Contact list filtering must continue to exclude existing group members and self.
- Existing invite overlay loading must remain separate from contact-loading state.
- Raw exception text must not be shown to users; technical details can stay in flow events.
- Mounted checks must still guard async state updates.

## exact tests and gates to run

Focused RED/GREEN selectors:

```sh
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name "shows loading state instead of empty state while contacts load"
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name "contact load failure shows retryable error instead of empty state"
```

Direct focused contact picker suite:

```sh
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/presentation/contact_picker_screen_test.dart
```

Named group behavior gate:

```sh
./scripts/run_test_gates.sh groups
```

Final hygiene:

```sh
git diff --check
```

Run `dart format` on any touched Dart files before final verification if formatting changed.

## known-failure interpretation

Treat failures in the two new selectors as session-owned. Treat failures in `contact_picker_wired_test.dart` or `contact_picker_screen_test.dart` as session-owned unless clearly caused by pre-existing dirty work outside the contact picker files.

For `./scripts/run_test_gates.sh groups`, investigate any failure. The current matrix/breakdown notes record a residual unrelated `group_membership_smoke_test.dart` `GM-028` failure from `GCA-001`; it may be classified as residual for this session only if an isolated rerun reproduces it and there is no diff-linked path from the contact picker presentation changes to that integration assertion.

Do not classify failures in `pubspec.yaml`, group-list files, or unrelated untracked upload directories as session-owned unless this session changes them.

## done criteria

- Both new focused regressions fail before production changes and pass after implementation.
- Loading state appears during unresolved initial contact load and does not show `No contacts available`.
- Contact-load failure shows retryable error UI and does not show `No contacts available`.
- Retry can recover from a load failure and display contacts.
- Successful empty result still shows the existing empty state.
- Existing contact picker wired/screen tests pass.
- No more than three non-doc files are touched by implementation.
- `git diff --check` passes.

## scope guard

Non-goals:

- no create-group picker changes;
- no repository/shared fake changes;
- no invite/member application logic changes;
- no bridge, p2p, identity, persistence, or database changes;
- no localization or copy sweep;
- no new dependencies;
- no shared app-wide loading/error framework;
- no visual redesign.

Overengineering includes introducing a common async state abstraction, moving contact loading into a separate controller, changing `ContactRepository`, or broadening retry behavior beyond the add-member contact-load path. Stop and block if any of those become necessary.

## accepted differences / intentionally out of scope

- `GCA-002A` create-group picker loading/error parity is intentionally separate and must not be bundled here.
- This session does not localize new hardcoded strings, matching the explicit no-localization constraint and existing hardcoded contact picker copy.
- This session does not add pure screen tests for the new props; wired tests are sufficient because they exercise the rendered screen through the scoped failing seam while preserving the three non-doc-file cap.
- Later refresh failure with already visible contacts can keep showing existing contacts rather than replacing the list with a full-screen error.

## dependency impact

Closing `GCA-002B` removes the add-member picker false-empty-state gap and allows the breakdown ledger/source matrix row to be closed by the closure phase with focused test evidence. If this plan blocks under the three-file cap, downstream sessions should not assume the add-member picker has reliable loading/error separation.

## Reviewer Notes

- Sufficiency: sufficient with adjustment.
- Missing files/tests/gates: no missing mandatory gate; focused RED/GREEN selectors, direct contact picker tests, named `groups` gate, and `git diff --check` are named.
- Stale or incorrect assumptions: none found; current code confirms there is no contact-loading/error state.
- Overengineering: no shared framework, dependency, localization, or repository change is planned.
- Decomposition: narrow enough except the draft wording around `contact_picker_screen_test.dart` could invite a fourth non-doc edit.
- Minimum needed to make sufficient: make `contact_picker_screen_test.dart` explicitly run-only and keep all new assertions in `contact_picker_wired_test.dart`.

## Arbiter Notes

- Structural blockers: draft wording could have allowed an optional fourth non-doc edit in `contact_picker_screen_test.dart`. Patched once by making that file run-only and requiring all new assertions to stay in `contact_picker_wired_test.dart`.
- Incremental details: none requiring another plan change.
- Accepted differences: no pure screen test edit, no localization, no shared error-state component, no create-group picker parity work.

## Final Reviewer Notes

- Sufficiency: sufficient as-is after the cap wording patch.
- Missing files/tests/gates: none.
- Stale or incorrect assumptions: none found.
- Overengineering: none; the plan remains local to two production files and one focused test file.
- Decomposition: enough to minimize hallucination during execution.
- Minimum needed to make sufficient: already done.

## Final Arbiter Notes

- Structural blockers remaining: none.
- Incremental details intentionally deferred: no pure screen test edit; `contact_picker_screen_test.dart` remains a run-only direct regression command.
- Accepted differences intentionally left unchanged: `GCA-002A` remains separate, new strings are not localized, and no global async/error framework is introduced.
- Final verdict: execution-ready.
