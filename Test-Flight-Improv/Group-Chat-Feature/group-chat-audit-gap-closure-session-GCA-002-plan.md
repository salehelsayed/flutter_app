Status: approval-required

# GCA-002 Contact Picker Loading and Error States Plan

## Planning Progress

- 2026-05-23 19:12:15 CEST - Planner completed. Files inspected since last update: plan draft only. Decision/blocker: drafted full-scope approval-required plan and safe two-session split; no execution-ready status under current cap. Next action: reviewer sufficiency pass.
- 2026-05-23 19:12:15 CEST - Reviewer started. Files inspected since last update: plan draft. Decision/blocker: review mandatory sections, tests/gates, cap logic, and scope drift. Next action: classify sufficiency and required adjustments.
- 2026-05-23 19:13:02 CEST - Reviewer completed. Files inspected since last update: plan draft. Decision/blocker: sufficient as an approval-required plan after making the exact file-count impact explicit; no missing mandatory section. Next action: arbiter classification.
- 2026-05-23 19:13:33 CEST - Arbiter started. Files inspected since last update: reviewer findings and adjusted plan. Decision/blocker: classify file-cap blocker and deferred details. Next action: final arbiter decision.
- 2026-05-23 19:13:33 CEST - Arbiter completed. Files inspected since last update: reviewer findings and adjusted plan. Decision/blocker: full row remains approval-required under the hard cap; no further planning loop needed. Next action: hand back compact verdict to the pipeline controller.

## real scope

Fix only row `GCA-002`: the create-group contact picker and the add-member contact picker must not represent unresolved or failed contact loading as `No contacts available`.

In scope if user approves the file-count exception:

- Add explicit initial contact-loading state and load-error state to `CreateGroupPickerWired` and `ContactPickerWired`.
- Pass those states into `CreateGroupPickerScreen` and `ContactPickerScreen`.
- Render loading/error UI before the true empty state when there is no displayable contact content.
- Add focused failing-first tests for both picker paths.

Out of scope:

- Retry affordances, copy polish, layout redesign, refactors, shared-state abstractions, new dependencies, invite/send semantics, group creation semantics, and unrelated matrix rows.

## closure bar

The session is good enough only when both picker paths distinguish these states:

- Initial unresolved load shows a loading indicator, not `No contacts available`.
- Load failure shows a user-visible contact-load error, not `No contacts available`.
- Successful empty load still shows the existing `No contacts available` copy.
- Successful non-empty load still lists contacts, preserves sorting/filtering, excludes self/current group members, and preserves current selection/create/invite behavior.

Under the current three-file non-doc cap, this closure bar cannot be reached in one implementation session without either splitting the row or getting explicit approval to exceed the cap.

## source of truth

- Primary row: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md`, row `GCA-002`.
- Session contract and hard stop: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md`, session `GCA-002`.
- Current code and current tests win over stale prose.
- `Test-Flight-Improv/test-gate-definitions.md` and `Test-Flight-Improv/test-gates-reference.md` govern named/supporting gates.
- If docs disagree, current code/tests and `test-gate-definitions.md` win. The breakdown classifies `GCA-002` as `implementation-ready`, but its own hard cap makes the current full-scope implementation approval-required.

## session classification

`prerequisite-blocked`.

Reason: completing both create-group and add-member picker paths cleanly requires more than three non-doc files. The prerequisite is either explicit user approval to exceed the cap or a decomposition split into two smaller sessions.

Full-scope approval path file count: six non-doc files in the lowest-risk local pattern (`create_group_picker_wired.dart`, `create_group_picker_screen.dart`, `contact_picker_wired.dart`, `contact_picker_screen.dart`, `create_group_picker_wired_test.dart`, `contact_picker_wired_test.dart`). A five-file variant using one new combined test file is possible but less local and duplicates more setup.

## exact problem statement

`CreateGroupPickerWired` starts with `_contacts = []` and only logs contact load failures. While the async load is unresolved or failed, `CreateGroupPickerScreen` receives an empty list and renders `No contacts available`.

`ContactPickerWired` starts with `_availableContacts = []` and has no load-error catch around `getActiveContacts`, `getMembers`, or `loadIdentity`. While the async load is unresolved, and especially if it fails, `ContactPickerScreen` receives an empty list and renders `No contacts available`.

The user-visible bug is false empty-state copy during loading or failure. What must stay unchanged: true-empty success still says `No contacts available`; contact sorting/filtering, self/member exclusion, selection, creation, invite fanout, navigation, and existing snackbars remain unchanged.

## files and repos to inspect next

Already inspected production files:

- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/features/groups/presentation/screens/create_group_picker_screen.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/contact_picker_screen.dart`

Already inspected direct tests:

- `test/features/groups/presentation/create_group_picker_wired_test.dart`
- `test/features/groups/presentation/create_group_picker_screen_test.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`
- `test/features/groups/presentation/contact_picker_screen_test.dart`

If approval is granted, inspect only these again at implementation time plus the existing fake contact repository/interface if needed for a throwing or delayed test fake:

- `lib/features/contacts/domain/repositories/contact_repository.dart`
- `test/shared/fakes/in_memory_contact_repository.dart`

## existing tests covering this area

- `create_group_picker_wired_test.dart` covers successful active contact load, self exclusion, selection, group creation success, creation failure snackbar, size-limit snackbar, and back navigation.
- `create_group_picker_screen_test.dart` covers header/search rendering, contact rows, true empty state, search, selection panel visibility, back button, and create-progress indicator.
- `contact_picker_wired_test.dart` covers successful available-contact load excluding members/self, selection, invite/add-member behavior, invite failure snackbar, back/cancel, and several invite fanout edge cases.
- `contact_picker_screen_test.dart` covers header, contact rows, true empty state, selection count, selected icons, confirm button, search, invite-progress overlay, and readability.

Missing coverage:

- No focused test holds the contact load pending and asserts loading instead of empty.
- No focused test injects contact-load failure and asserts error instead of empty.
- Add-member load failure is especially uncovered because `_loadAvailableContacts` currently does not catch initial load errors.

## regression/tests to add first

Failing-first tests before implementation:

- In `test/features/groups/presentation/create_group_picker_wired_test.dart`, add a delayed contact repository test: after the first pump, expect a `CircularProgressIndicator` and expect `No contacts available` absent; after completing the load with an empty list, expect `No contacts available`.
- In `test/features/groups/presentation/create_group_picker_wired_test.dart`, add a throwing contact repository test: after load failure, expect `Couldn't load contacts` or equivalent explicit error and expect `No contacts available` absent.
- In `test/features/groups/presentation/contact_picker_wired_test.dart`, add the same delayed-load test for `ContactPickerWired`.
- In `test/features/groups/presentation/contact_picker_wired_test.dart`, add the same throwing-load test for `ContactPickerWired`.

These prove the exact seam: the wired state no longer passes ambiguous empty content to the pure screens during unresolved or failed loading, while successful empty data remains a true empty state.

## step-by-step implementation plan

This is not execution-ready under the current cap. If the user approves a file-count exception, execute:

1. Add failing tests first using small local test fakes. Prefer subclassing `InMemoryContactRepository` to delay or throw `getActiveContacts()` so the existing test builders and setup stay intact.
2. Add minimal state to `CreateGroupPickerWired`: `_isLoadingContacts = true`, `_contactLoadErrorMessage`, and a private constant such as `Couldn't load contacts`. On success set contacts, loading false, error null. On catch emit the existing load error event, set loading false, and set the error only when there is no displayable contact content.
3. Add the same minimal state to `ContactPickerWired`, including a load-error catch and a flow event for initial load failure. Do not change invite failure handling.
4. Add optional constructor fields with defaults to `CreateGroupPickerScreen`: `isLoadingContacts = false` and `contactLoadErrorMessage`.
5. Add optional constructor fields with defaults to `ContactPickerScreen`: `isLoadingContacts = false` and `contactLoadErrorMessage`.
6. In both screens, choose body state in this order when there is no contact content: loading, load error, true empty. Preserve the existing contact list path when contacts are non-empty.
7. Run direct tests and hygiene. Update source matrix and session breakdown only after implementation evidence is green or truthfully classified.

Safe split option without approval:

- `GCA-002A` create-group picker only: touch `create_group_picker_wired.dart`, `create_group_picker_screen.dart`, and `create_group_picker_wired_test.dart`.
- `GCA-002B` add-member picker only: touch `contact_picker_wired.dart`, `contact_picker_screen.dart`, and `contact_picker_wired_test.dart`.

Stop if evidence disproves the need for either path or if implementation drifts into retry UX, shared components, l10n regeneration, or invite/create behavior.

## risks and edge cases

- A pending async load must not call `setState` after unmount.
- Failed initial load should not leave a visible true-empty state underneath.
- A successful empty load must still be distinguishable from a failure.
- Existing contact filtering after search should remain unchanged.
- Add-member must continue excluding existing group members and self.
- Existing create/invite in-progress indicators must not be conflated with contact initial-load state.

## exact tests and gates to run

If approval is granted and implementation proceeds:

```bash
flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart --plain-name "shows contact loading state before contacts resolve"
flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart --plain-name "load failure shows contact load error instead of empty state"
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name "shows contact loading state before contacts resolve"
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name "load failure shows contact load error instead of empty state"
flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart test/features/groups/presentation/create_group_picker_screen_test.dart test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/presentation/contact_picker_screen_test.dart
flutter test --no-pub test/features/contact_request/integration/contact_request_flow_test.dart
git diff --check
```

Named `groups` gate:

```bash
./scripts/run_test_gates.sh groups
```

Run `groups` only if implementation changes invite/add-member execution semantics beyond initial load/error presentation, or if the executor/reviewer decides that touching `ContactPickerWired` is enough to require the full group messaging gate. The breakdown's likely gates for this row are focused Flutter tests and `git diff --check`.

## known-failure interpretation

`GCA-001` closure recorded an unrelated existing `./scripts/run_test_gates.sh groups` failure in `group_membership_smoke_test.dart` for `GM-028 empty PeerId add event does not persist or block valid delivery`.

For this session:

- Direct picker tests must pass; a direct failure in touched files is not historical.
- `git diff --check` must pass.
- If `groups` is run and only the same isolated `GM-028` failure remains, classify it as residual only if the failure is unchanged and no touched loading/error path is implicated.
- Any new failure in the touched picker files, contact-entry flow, invite picker behavior, or contact request supplemental direct suite blocks closure.

## done criteria

Because this plan is approval-required, planning is done when the blocker and smallest safe choices are explicit.

Implementation can be considered done only after:

- Both picker paths show loading/error instead of false empty state.
- True empty successful loads still show `No contacts available`.
- Focused failing-first tests are added and pass.
- Required direct tests and hygiene pass or unrelated historical failures are documented.
- Source matrix row `GCA-002` and this breakdown ledger are updated with evidence.

## scope guard

Do not:

- Add retry buttons or reload interactions.
- Add or regenerate localization files unless the user explicitly approves that extra scope.
- Introduce a shared contact-picker state abstraction.
- Move business logic out of wired widgets.
- Change group creation, add-member, invite fanout, key distribution, navigation, or snackbar semantics.
- Touch more than three non-doc files without explicit approval.
- Mark the plan `execution-ready` while the full row exceeds the cap.

A three-file workaround that renders loading/error UI directly inside both wired widgets would bypass the local pure-screen pattern and duplicate presentation code; treat that as overengineering and out of scope for this plan.

## accepted differences / intentionally out of scope

- Create-group and add-member picker titles/copy differ today; this session should not standardize them.
- The add-member picker already has an invite-progress overlay; the new contact-load state is separate and should not reuse invite-progress semantics.
- A retry affordance would match the earlier group-list pattern more closely, but the `GCA-002` row asks only to avoid false empty state and add loading/error coverage.

## dependency impact

No later `GCA-*` session depends on `GCA-002` behavior directly, but the overall group chat audit closure cannot be `closed` while row `GCA-002` remains `Open` or approval-required. If the user chooses the split, the source row should remain open until both sub-sessions are closed or one is explicitly blocked.

## evidence collector notes

- Matrix row `GCA-002` is `Open` and names all four picker components plus focused tests.
- Breakdown row `GCA-002` repeats the exact scope and hard cap.
- `CreateGroupPickerWired` initializes `_contacts` as empty, catches load errors only by logging, and passes the list directly into the screen.
- `CreateGroupPickerScreen` renders `No contacts available` whenever `contacts.isEmpty`.
- `ContactPickerWired` initializes `_availableContacts` as empty, performs the initial load without a catch, and passes the list directly into the screen.
- `ContactPickerScreen` renders `No contacts available` whenever `contacts.isEmpty`.
- Existing tests cover success/empty/invite/create paths but not pending or failed initial contact loads.

## reviewer findings

Reviewer sufficiency: sufficient as an approval-required/prerequisite-blocked plan.

Missing files, tests, or gates: none structurally. The plan includes the four production files, four direct test files, contact repository fake/interface, focused failing-first tests, direct aggregate tests, supplemental contact-entry direct suite, `git diff --check`, and conditional `groups` gate.

Stale or incorrect assumptions: the breakdown's `implementation-ready` classification is stale against its own hard cap once current code confirms both picker paths require clean screen and wired changes.

Overengineering: shared abstractions, retry UX, localization regeneration, and wired-only UI workarounds are explicitly guarded out.

Decomposition: enough to minimize hallucination. The safe split keeps each sub-session at three non-doc files; the full row needs user approval.

Minimum needed to make sufficient: already included; the reviewer adjustment was to state the six-file approval path and three-file split file counts explicitly.

## arbiter decision

Structural blockers:

- Full-scope `GCA-002` cannot be implemented safely under the current three-file non-doc cap because the local architecture requires two wired files, two pure screen files, and focused tests. This blocks `execution-ready` status.

Incremental details:

- Exact user-facing error copy can be finalized during implementation, but it must be explicit enough for tests and must not require l10n regeneration unless separately approved.
- The full `groups` gate remains conditional because the planned behavior is initial load/error presentation, not invite delivery semantics.

Accepted differences:

- No retry affordance in this row.
- No shared picker-state abstraction.
- No wired-only UI workaround to force the diff under three files.

Arbiter stop rule: no new structural blocker in the plan itself. Stop after this pass. Final reusable state is `approval-required`, not `execution-ready`.
