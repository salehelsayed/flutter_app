# GCA-002A Create-Group Picker Loading/Error States Plan

Status: execution-ready

## Planning Progress

- 2026-05-23 19:17:12 CEST - Planner started. Files inspected since last update: none. Decision/blocker: no blocker; use the existing GCA-001 loading/error state pattern but keep this session create-group-only. Next action: write the execution plan, tests, gates, and scope guard.
- 2026-05-23 19:19:39 CEST - Planner completed. Files inspected since last update: none. Decision/blocker: draft plan written with a three-file implementation cap and failing-test-first sequence. Next action: review plan sufficiency, stale assumptions, missing gates, and overengineering risk.
- 2026-05-23 19:20:48 CEST - Reviewer started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-002A-plan.md`. Decision/blocker: review against hard cap, TDD order, gates, and scope. Next action: record sufficiency findings.
- 2026-05-23 19:20:48 CEST - Reviewer completed. Files inspected since last update: none. Decision/blocker: sufficient with one required adjustment: remove the conditional fourth-file compatibility escape hatch. Next action: arbitrate the finding and patch the plan once if structural.
- 2026-05-23 19:21:30 CEST - Arbiter completed. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-002A-plan.md`. Decision/blocker: the hard-cap escape hatch was structural and has been removed; final review finds no remaining structural blocker. Next action: execute the plan with failing tests first.

## Evidence Collector Findings

- Source matrix row `GCA-002A` is `Open` and says create-group contact loading failures can show `No contacts available` instead of a loading/error state.
- The breakdown classifies `GCA-002A` as `implementation-ready`, with no dependency on earlier sessions, and limits scope to `CreateGroupPickerWired`, `CreateGroupPickerScreen`, and focused create-group picker tests.
- `CreateGroupPickerWired` currently starts with `_contacts = []`, has `_isCreating` but no contact-loading state, calls `_loadContacts()` from `initState`, and only emits `CREATE_GROUP_PICKER_FL_LOAD_CONTACTS_ERROR` on failure.
- `CreateGroupPickerScreen` currently receives only `contacts`, selection callbacks, create state, and background preference; if `widget.contacts.isEmpty`, it always renders `No contacts available`.
- Existing create-group wired tests cover successful contact loading, self-exclusion, selection, create success/failure, warnings, size-limit errors, and back navigation, but not pending contact load or contact-load failure.
- The recently closed `GCA-001` group list path established a local pattern for distinguishing initial loading, load failure, retry, and true empty state without broad architecture changes.
- The group named gate exists, but the source row and breakdown call for focused direct tests plus `git diff --check`; the matrix records a residual unrelated `groups` gate failure in `group_membership_smoke_test.dart` `GM-028` from `GCA-001` closure evidence.

## Real scope

Change only the create-group contact picker path so it distinguishes:

- contact load pending
- contact load failed
- contact load succeeded with zero contacts
- contact load succeeded with contacts

Implementation is capped at these three non-doc files:

- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/features/groups/presentation/screens/create_group_picker_screen.dart`
- `test/features/groups/presentation/create_group_picker_wired_test.dart`

Do not change `ContactPickerWired`, `ContactPickerScreen`, contact repositories, group creation use cases, bridge behavior, navigation, localization files, dependencies, or shared test fakes.

## Closure bar

The session is closed when the create-group picker no longer renders `No contacts available` while the initial contact load is still pending or after `contactRepo.getActiveContacts()` fails with no displayable contacts. A real zero-contact success must still render `No contacts available`. Existing selection, create, warning, and back-navigation behavior must remain unchanged.

## Source of truth

Current code and focused tests win over stale prose. The source matrix row `GCA-002A` and the session breakdown define the allowed scope. `Test-Flight-Improv/test-gate-definitions.md` defines named gates. The closed `GCA-001` group-list implementation is useful as a local pattern for loading/error separation, but it does not expand this session beyond the create-group picker.

## Session classification

`implementation-ready`

## Exact problem statement

`CreateGroupPickerWired` initializes `_contacts` as an empty list and does not track contact-load progress or failure. `CreateGroupPickerScreen` treats an empty `contacts` list as a true empty result. Because `_loadContacts()` is asynchronous and its catch block only logs the failure, users can see `No contacts available` during initial load and after a failed contact load. The fix must make those states explicit without changing group creation semantics.

## Files and repos to inspect next

- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/features/groups/presentation/screens/create_group_picker_screen.dart`
- `test/features/groups/presentation/create_group_picker_wired_test.dart`
- `test/features/groups/presentation/create_group_picker_screen_test.dart` for constructor/default compatibility evidence only; do not edit it in this session.
- `Test-Flight-Improv/test-gate-definitions.md` if the executor decides to run any broader named gate beyond the focused direct tests.

## Existing tests covering this area

- `test/features/groups/presentation/create_group_picker_wired_test.dart` covers successful active-contact loading, self-contact exclusion, contact selection, create success navigation, create failure snackbar, invite-degradation warning, member limit failure, and back navigation.
- `test/features/groups/presentation/create_group_picker_screen_test.dart` covers header/search/list/empty/select/create-loading/readability behavior for the pure screen.
- Missing coverage: pending initial contact load, contact-load failure, and retry/loading behavior after contact-load failure.

## Regression/tests to add first

Add failing tests first in `test/features/groups/presentation/create_group_picker_wired_test.dart`:

1. `shows contact-loading state instead of empty state while contacts are loading`
   Use a local `_SlowContactRepository` or `_DeferredContactRepository` that returns a pending `Future<List<ContactModel>>`. After the first pump, assert a contact-loading indicator/key is visible and `No contacts available` is absent. Complete the future with `contactAlice`, pump frames, and assert Alice appears.
2. `contact load failure shows retryable error instead of empty state`
   Use a local `_ThrowingContactRepository` patterned after `_ThrowingGroupRepository` in `group_list_wired_test.dart`. Assert `Couldn't load contacts`, a `Retry` button, and no `No contacts available`. Hold the next failure, tap `Retry`, assert the loading state appears and the repository call count increments, then release and assert the error returns.

These tests should fail against current code because the wired widget passes an empty contact list to the screen before and after load failure.

## Step-by-step implementation plan

1. Add the failing wired tests and local contact repository fakes in `create_group_picker_wired_test.dart`; run each new test by `--plain-name` and confirm it fails for the intended reason.
2. Extend `CreateGroupPickerScreen` with optional/defaulted contact-load UI props: `isLoadingContacts`, `loadErrorMessage`, and `onRetryLoadContacts`.
3. In `CreateGroupPickerScreen`, change the expanded content selection order to prefer the real contact list when non-empty, then contact-loading state, then load-error state, then true empty state.
4. Add small private `_buildLoadingState` and `_buildLoadErrorState` helpers. Use existing readable color patterns and hardcoded English strings consistent with the current file; do not touch l10n.
5. In `CreateGroupPickerWired`, add `_isLoadingContacts = true`, a nullable current load-error message, and a local constant such as `Couldn't load contacts`.
6. On successful `_loadContacts()`, set sorted/self-filtered contacts, clear the load error, and set `_isLoadingContacts = false`.
7. On `_loadContacts()` failure, keep emitting the existing flow event, set `_isLoadingContacts = false`, and set the load-error message only when there are no displayable contacts.
8. Add a retry callback that clears the error and shows loading when there are no contacts, then calls `_loadContacts()` again. Use `unawaited` with `dart:async` if needed to satisfy lints.
9. Pass the new contact-load props from wired to screen. Stop here if the failing tests pass and existing create-group picker tests remain green.

## Risks and edge cases

- The true empty state must remain reachable after a successful load with zero contacts.
- A slow contact load must not expose selection controls for nonexistent contacts or show `No contacts available`.
- Retry should show loading only when there are no displayable contacts; this avoids blanking an existing contact list if a later reload path is introduced.
- Existing group creation failure handling must remain separate from contact-load failure handling.
- Search-empty behavior for a non-empty contact list remains out of scope.

## Exact tests and gates to run

Failing-test-first commands before implementation:

```bash
flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart --plain-name "shows contact-loading state instead of empty state while contacts are loading"
flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart --plain-name "contact load failure shows retryable error instead of empty state"
```

After implementation:

```bash
flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart --plain-name "shows contact-loading state instead of empty state while contacts are loading"
flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart --plain-name "contact load failure shows retryable error instead of empty state"
flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart test/features/groups/presentation/create_group_picker_screen_test.dart
git diff --check
```

The breakdown lists focused Flutter tests plus `git diff --check` as the likely gates for this session. If a controller asks for `./scripts/run_test_gates.sh groups`, run it after the focused tests and apply the known-failure interpretation below.

## Known-failure interpretation

Focused create-group picker test failures are in scope and must be fixed. Compile failures from the direct `create_group_picker_screen_test.dart` command are in scope only when they expose incorrect/defaultless screen prop changes; fix those within the three named implementation files and do not edit the screen test file. If the broader `groups` named gate is run and fails only on the already-recorded isolated `group_membership_smoke_test.dart` `GM-028` failure from `GCA-001`, classify it as residual/unrelated and record the exact evidence rather than expanding this session.

## Done criteria

- The two new tests fail before implementation for the expected empty-state behavior.
- The implementation changes no more than three non-doc files.
- Pending contact load shows a loading state and does not show `No contacts available`.
- Contact-load failure with no contacts shows `Couldn't load contacts` and retry affordance, not `No contacts available`.
- Successful zero-contact load still shows `No contacts available`.
- Existing create-group picker behaviors covered by the focused direct tests still pass.
- `git diff --check` passes.

## Scope guard

Do not implement add-member picker changes in this session. Do not refactor shared picker UI, create reusable loading/error abstractions, alter contact repository APIs, add localization keys, change group creation/invite logic, change Orbit routing, change background/readability systems, or update unrelated GCA rows. Any need to edit more than the three named non-doc files is a stop-and-report condition.

## Reviewer pass

Reviewer verdict: sufficient with adjustment.

- Missing files/tests/gates: none after focused wired tests and the direct screen compile/run command are named.
- Stale assumptions: none found; current code confirms the empty-list conflation.
- Overengineering: retry is acceptable because it is a single local affordance matching the just-closed group-list load-error pattern; broader shared abstractions are explicitly forbidden.
- Decomposition: narrow enough for implementation, provided the hard cap remains absolute.
- Required adjustment: remove any wording that permits editing a fourth non-doc file for constructor compatibility. The screen props must be defaulted so existing screen tests compile without edits; if not, the executor must fix within the three named files or stop.

## Arbiter pass

Arbiter verdict: `execution-ready`.

- Structural blockers: none remaining. The only structural issue found by review was conditional permission to edit a fourth non-doc file; the plan now makes the three-file cap absolute.
- Incremental details intentionally deferred: no dedicated pure-screen loading/error tests because the wired regression tests exercise the real screen while preserving the hard cap.
- Accepted differences intentionally left unchanged: hardcoded English copy stays local to this already hardcoded screen; add-member picker work remains owned by `GCA-002B`.
- Stop rule: implementation must stop and report if it cannot pass the focused regression without editing outside the three named non-doc files.

## Accepted differences / intentionally out of scope

`GCA-002B` owns the add-member contact picker. `GCA-003` owns partial group creation/member-add failures after selection. Search results with no matches may still render an empty list without a special search-empty message. Full localization of new hardcoded copy is intentionally deferred because this file already uses hardcoded strings and the session forbids localization work.

## Dependency impact

Closing this session gives `GCA-002B` a narrow pattern for add-member loading/error states but does not unblock it automatically. Later group creation reliability rows should assume the picker now distinguishes contact-load failure from a true empty contact set; they should not rely on `No contacts available` as a generic failure signal.

## Execution Progress

- 2026-05-23 19:24:03 CEST - Contract extracted. Files inspected/touched: plan, breakdown, matrix, `create_group_picker_wired.dart`, `create_group_picker_screen.dart`, `create_group_picker_wired_test.dart`, `create_group_picker_screen_test.dart`. Decision/blocker: no nested subagent-spawn tool is available in this execution context; use the skill's local sequential fallback because this is already a fresh isolated execution agent and no child produced partial work. Next action: perform Executor pass with failing tests first inside the allowed write set.
- 2026-05-23 19:25:23 CEST - Executor RED tests completed. Files inspected/touched: `create_group_picker_wired_test.dart`. Commands: `flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart --plain-name "shows contact-loading state instead of empty state while contacts are loading"` failed because `create-group-contact-loading` was absent; `flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart --plain-name "contact load failure shows retryable error instead of empty state"` failed because `Couldn't load contacts` was absent. Decision/blocker: RED evidence matches the planned empty-state conflation. Next action: implement local contact-loading/error props and wired retry state.
- 2026-05-23 19:27:03 CEST - Executor implementation and required tests completed. Files inspected/touched: `create_group_picker_wired.dart`, `create_group_picker_screen.dart`, `create_group_picker_wired_test.dart`. Commands: both focused `--plain-name` tests passed after implementation; `flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart test/features/groups/presentation/create_group_picker_screen_test.dart` passed; `git diff --check` passed. Decision/blocker: no focused test blocker. Next action: perform local QA Reviewer pass for scope, behavior, and evidence sufficiency.
- 2026-05-23 19:27:25 CEST - Local QA Reviewer completed and final verdict written. Files inspected/touched: final diff for allowed write set and this plan. Command: final `git diff --check` passed after progress updates. Decision/blocker: accepted; no blocking issues and no fix pass required. Next action: return compact execution verdict to the pipeline controller.
