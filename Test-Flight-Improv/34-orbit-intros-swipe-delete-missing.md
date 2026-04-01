# 34 - Orbit Intros Swipe Delete Missing On Live Screen

## 1. Title and Type

- Title: Orbit Intros swipe delete missing on live screen
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing.md`

## 2. Problem Statement

Users can open `Orbit` and switch to the `Intros` filter, but swiping an intro
row from right to left does not reveal any delete option on the live screen.
The row behaves like a static intro card with accept, pass, unavailable, or
status-only UI.

From the user's perspective, that means there is still no production way to
remove a visible introduction from the Orbit Intros list, even though
`Test-Flight-Improv/25-delete-intro-swipe.md` already describes swipe-to-delete
as the intended behavior for this surface.

## 3. Impact Analysis

- Affected users: any user who has visible introductions in `Orbit > Intros`
- When it appears: every time the user attempts a left swipe on a live intro row
- Severity: moderate; core navigation still works, but list management and
  documented affordance expectations fail
- Frequency: high for anyone trying to clean up or dismiss intros
- Visible cost: the user reaches a dead end on the actual Orbit screen and has
  no production-facing delete fallback
- Workaround evidence in repo: deletion exists only in the settings debug
  surface, not in the end-user Orbit flow

## 4. Current State

- `Test-Flight-Improv/25-delete-intro-swipe.md:7-29` and
  `Test-Flight-Improv/25-delete-intro-swipe.md:136-216` already define the
  intended Orbit swipe-delete behavior, including a delete affordance,
  confirmation, list removal, and badge updates.

- The live Orbit screen still renders intro rows directly inside
  `lib/features/orbit/presentation/screens/orbit_screen.dart:27-44` and
  `lib/features/orbit/presentation/screens/orbit_screen.dart:606-712`.
  `OrbitIntrosViewData` exposes `onAccept`, `onPass`, and `onSendMessage`, but
  no delete callback. Each intro row is built as a plain `IntroRow` inside
  `Padding`; there is no swipe wrapper on the live intro path.

- Orbit wiring matches that limitation.
  `lib/features/orbit/presentation/screens/orbit_wired.dart:240-256` passes
  only accept, pass, and send-message callbacks into `OrbitIntrosViewData`.
  `lib/features/orbit/presentation/screens/orbit_wired.dart:692-733` contains
  `_onAcceptIntro` and `_onPassIntro`, but no intro delete handler.

- The intro row widget itself does not expose any delete seam.
  `lib/features/introduction/presentation/widgets/intro_row.dart:10-163`
  supports accept, pass, unavailable, waiting, connected, and status-label
  rendering, but no delete gesture, delete button, or delete callback.

- The underlying delete primitive already exists.
  `lib/features/introduction/domain/repositories/introduction_repository.dart:4-16`
  exposes `deleteIntroduction(String id)`, and
  `lib/core/database/helpers/introductions_db_helpers.dart:37-64` performs the
  hard delete. This means the missing behavior is on the live Orbit UI and
  wiring path, not in storage.

- A debug-only deletion surface also exists.
  `lib/features/settings/presentation/screens/settings_wired.dart:256-292`
  deletes stored intro rows and pairs through the repository, and
  `lib/features/settings/presentation/widgets/settings_introduction_debug_card.dart:212-227`
  exposes `Delete Row` and `Delete Pair` buttons. That confirms deletion is
  repo-backed, but not available to end users in Orbit.

- The current Orbit loader is narrower than the older doc's status matrix.
  `lib/core/database/helpers/introductions_db_helpers.dart:394-425` only loads
  rows whose overall status is `pending` or `already_connected`. So the live
  Orbit Intros screen does not currently show every state listed in
  `25-delete-intro-swipe.md` such as passed or expired rows. The live bug is
  the missing delete affordance on the rows that are actually rendered today.

- There is coverage drift between tested intro UI and the live Orbit surface.
  `lib/features/introduction/presentation/widgets/intros_tab.dart:10-124`
  still mirrors grouped intro rendering, but the current Orbit production path
  renders intros inline inside `orbit_screen.dart` instead of instantiating
  `IntrosTab`.

- Existing adjacent coverage does not touch the failing live path.
  `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart:41-133`
  covers intro counts, grouping, and accept/pass flows.

- Existing adjacent coverage does not touch the failing live path.
  `test/features/introduction/presentation/widgets/intros_tab_test.dart:32-240`
  covers legacy `IntrosTab` rendering and accept/pass callbacks.

- Existing adjacent coverage does not touch the failing live path.
  `test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart:48-190`
  covers swipe-to-reveal delete on friend rows.

- No current test was found that asserts delete affordance visibility,
  confirmation, or deletion execution for intro rows on the live Orbit screen.
  A targeted run of the adjacent intro/orbit/swipe tests passes without
  covering that behavior.

## 5. Scope Clarification

- In scope: the actual `Orbit > Intros` screen exposing a visible delete
  affordance when the user swipes a currently rendered intro row left
- In scope: user-visible delete behavior on the live Orbit intro list, not only
  in debug screens or legacy intro widgets
- In scope: the intro row states that the current Orbit loader can actually
  surface to users

- Non-goal: redesigning friend-row or group-row swipe behavior
- Non-goal: changing accept/pass business rules or intro grouping presentation
- Non-goal: deciding cross-device, P2P, or server-synced delete semantics
- Non-goal: broadening Orbit Intros to show passed, expired, or other statuses
  that the current loader does not already display
- Non-goal: deciding whether any non-visible mirrored intro row should also be
  deleted outside the live Orbit list

- Accepted ambiguity: final confirmation copy and button labels can remain open
- Accepted ambiguity: whether every currently rendered non-pending intro state,
  such as `already_connected` if surfaced, shares the same delete affordance
- Accepted ambiguity: whether canceling a delete leaves the row visually open or
  closes it, as long as the intro remains clearly not deleted

## 6. Test Cases

### Happy Path

- `TC-34-H01` Given the user is on `Orbit > Intros` with at least one visible
  intro row, when the user swipes that row from right to left far enough to
  trigger the row action state, then a visible delete affordance appears on that
  live row.

- `TC-34-H02` Given a live Orbit intro row is showing the delete affordance,
  when the user taps delete, then the app presents a clear confirmation step
  before any intro is removed.

- `TC-34-H03` Given the confirmation is shown for a visible Orbit intro row,
  when the user confirms deletion, then that row disappears from the live Intros
  list and remains absent after the list refreshes or the user reopens the
  screen.

- `TC-34-H04` Given an introducer section contains only one visible intro row,
  when the user deletes that row, then the section header also disappears from
  the live Intros list.

- `TC-34-H05` Given the deleted row is the last visible intro in Orbit, when
  deletion completes, then the live screen shows the `No introductions yet`
  empty state.

- `TC-34-H06` Given the deleted row contributes to the visible Orbit intro
  count, when deletion completes, then the Orbit intro badge/count reflects the
  removal.

### Edge Cases

- `TC-34-E01` Given the user performs only a short horizontal drag or a
  primarily vertical drag on an intro row, when the gesture ends, then the list
  keeps normal scroll behavior and no delete affordance is shown.

- `TC-34-E02` Given multiple intro rows are visible, when one row is already
  open and the user begins opening another, then the UI keeps only one open row
  state at a time.

- `TC-34-E03` Given the confirmation step is open for a visible intro row, when
  the user cancels, then the intro remains in the list and no deletion occurs.

- `TC-34-E04` Given Orbit currently surfaces intro rows through the pending
  loader, when the user encounters each live row state that the screen can
  actually render today, then delete availability is consistent and observable
  for that state rather than silently missing on some rows.

- `TC-34-E05` Given intro updates or screen refreshes occur around the same
  time as a deletion, when the delete completes, then the removed intro does not
  immediately reappear unless a genuinely new introduction is received.

### Regressions To Preserve

- `TC-34-R01` Pending intro rows continue to show working `Accept` and `Pass`
  actions on the live Orbit screen.

- `TC-34-R02` Existing intro grouping, section headers, attribution text, and
  empty-state copy remain intact outside the new delete affordance.

- `TC-34-R03` Existing friend swipe actions continue to behave as they do today,
  including delete behavior already covered by the friend swipe row tests.

### Existing Partial Coverage

- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart:41-133`
  partially covers intro loading, counts, and accept/pass state changes.

- `test/features/introduction/presentation/widgets/intros_tab_test.dart:32-240`
  partially covers grouped intro rendering and legacy accept/pass callbacks.

- `test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart:48-190`
  partially covers the swipe-to-delete interaction pattern on friend rows.

### Current Coverage Gaps

- No current test was found for swipe-to-reveal delete on intro rows inside the
  live Orbit screen.

- No current test was found for intro delete confirmation and removal behavior
  on the live Orbit screen.

- No current test was found for Orbit intro badge/count updates after deleting a
  live intro row.
