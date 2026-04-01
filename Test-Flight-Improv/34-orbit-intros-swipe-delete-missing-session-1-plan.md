# Session 1 Plan - Live Orbit intro swipe-delete affordance, confirmation, and count truth

## Final verdict

`implementation-ready`

Current repo evidence still shows the live Orbit intro delete seam is open:

- `OrbitScreen` still renders intro rows as plain `IntroRow` widgets inside
  padding while friend and group rows already use `SwipeableFriendRow`.
- `OrbitIntrosViewData` and `OrbitWired` still expose only accept, pass, and
  send-message intro actions; no delete callback is wired through the live
  Orbit intro path.
- The delete primitive already exists in the introduction repository and DB
  helpers, and the existing Orbit confirmation dialog plus delete button are
  already implemented elsewhere, so the missing work is a bounded live
  Orbit-intro UI+wiring slice rather than a new persistence or protocol
  contract.

## Final plan

### real scope

- Add one delete action seam to the live `Orbit > Intros` path by threading a
- delete callback through `OrbitIntrosViewData` and `OrbitWired`.
- Expose a bounded left-swipe delete affordance for the intro rows that the
  live Orbit loader currently renders.
- Reuse the existing Orbit destructive confirmation dialog before delete.
- Refresh live Orbit intro state after delete so row removal, group header
  cleanup, empty state, and `projection.introsCount` remain truthful.
- Preserve current accept, pass, blocked/unavailable, mutual-accepted
  send-message, friend-swipe, and group-swipe behavior.
- Preserve the existing route-return refresh flag so shared Feed/Orbit hosts do
  not regress pending-intro badge freshness after a local intro delete.

### closure bar

- A visible live intro row on `Orbit > Intros` can be swiped left to reveal a
  delete affordance.
- Short or primarily vertical drags do not reveal delete and normal list scroll
  still works.
- Only one live intro row can remain open at a time.
- Tapping delete shows a confirmation step before destructive action.
- Confirming deletion removes the intro from the live list, removes any now
  empty introducer header, and shows `No introductions yet` when the final live
  intro disappears.
- The live Orbit intro count and persistent-nav Orbit badge remain truthful
  after deletion.
- Existing live intro accept/pass/send-message behavior and current friend/group
  swipe behavior remain unchanged.
- Direct regressions proving the live path pass, and
  `./scripts/run_test_gates.sh baseline` passes because Flutter production code
  changed on a top-level surface.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing-session-breakdown.md`
  - `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing.md`
  - `Test-Flight-Improv/25-delete-intro-swipe.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code and tests beat stale prose when they disagree.
- Verified repo seams:
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/introduction/presentation/widgets/intro_row.dart`
  - `lib/features/orbit/presentation/widgets/swipeable_friend_row.dart`
  - `lib/features/orbit/presentation/widgets/swipe_action_buttons.dart`
  - `lib/features/orbit/presentation/widgets/confirmation_dialog.dart`
  - `lib/features/feed/domain/models/feed_route_changes.dart`
  - `lib/features/introduction/domain/repositories/introduction_repository.dart`
  - `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
  - `lib/core/database/helpers/introductions_db_helpers.dart`
  - `test/shared/fakes/in_memory_introduction_repository.dart`

### session classification

`implementation-ready`

### exact problem statement

- The live Orbit intro surface still has no user-facing delete affordance even
  though the intended behavior is already documented and the delete primitive is
  already implemented underneath.
- `OrbitScreen` renders intro rows directly and never wraps them in a swipe
  action owner, so the live row behaves like a static card.
- `OrbitWired` owns current intro count truth and route-return refresh flags,
  but it has no delete handler and therefore cannot refresh Orbit/Feed truth
  after a delete.
- Adjacent tests cover friend swipe, legacy intro widgets, and intro counts,
  but no current regression proves live intro delete reveal, confirmation,
  removal, or badge/count truth.
- Current repo truth narrows scope: the live intro loader still surfaces only
  rows in status `pending` or `already_connected`, so this session must fix the
  live rows that actually render today rather than reopening broader loader
  status scope.

### files and repos to inspect next

- Repo scope stays inside
  `/Users/I560101/Project-Sat/mknoon-2/flutter_app`.
- Production files:
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/introduction/presentation/widgets/intro_row.dart`
  - `lib/features/orbit/presentation/widgets/swipeable_friend_row.dart`
  - `lib/features/orbit/presentation/widgets/swipe_action_buttons.dart`
  - `lib/features/orbit/presentation/widgets/confirmation_dialog.dart`
  - `lib/features/feed/domain/models/feed_route_changes.dart` only if the
    current route-return refresh flag needs a narrow clarification instead of
    direct reuse
- Direct tests:
  - `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`
    or a new narrow Orbit-screen intro-delete widget test file if execution
    keeps the new live intro assertions separate
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `test/features/introduction/presentation/widgets/intro_row_test.dart`
  - `test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart`
  - `test/features/orbit/presentation/widgets/confirmation_dialog_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart` only if the
    route-return intro refresh seam needs a direct Feed-side assertion
- Closure docs:
  - `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md` only if this session actually closes
    Report `34`
  - `Test-Flight-Improv/17-roadmap-closure-audit.md` only if the same closure
    pass intentionally refreshes folder-level status wording

### existing tests covering this area

- `test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart`
  already proves the bounded Orbit swipe row contract: left reveal, one-open-row
  notifier behavior, delete callback plumbing, and right-swipe close.
- `test/features/orbit/presentation/widgets/confirmation_dialog_test.dart`
  already proves the destructive Orbit confirmation dialog behavior.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` already
  proves persistent-nav badge threading and current intro empty-state behavior.
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  already proves intro repository truth, accept/pass wiring, and count updates
  for adjacent live intro flows.
- `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`
  already proves live intro rendering sits in the sliver list rather than a
  nested list view.
- `test/features/introduction/presentation/widgets/intro_row_test.dart` already
  proves current row content and status labeling contracts.
- Missing today:
  - no direct proof that a live Orbit intro row reveals delete on swipe
  - no direct proof that delete confirmation appears for the live intro row
  - no direct proof that live delete removes the intro, cleans up headers/empty
    state, and updates Orbit intro count/badge truth

### regression/tests to add first

- Add or extend a live Orbit-screen widget regression first to prove:
  - swipe reveal on a live intro row
  - short/vertical drags do not reveal delete
  - only one row can stay open at a time
- Add or extend `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  to prove live delete removes the intro row, updates `projection.introsCount`,
  and preserves the `No introductions yet` empty state when the final intro is
  deleted.
- Add or extend `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  to prove the delete path uses the existing repository primitive and updates
  pending intro count truth.
- Touch `intro_row_test.dart`, `swipeable_friend_row_test.dart`, and
  `confirmation_dialog_test.dart` only if execution changes those seams rather
  than purely reusing them.

### step-by-step implementation plan

1. Re-read the targeted Orbit intro screen, Orbit wired, and adjacent tests in
   the live dirty tree before editing. Merge with existing unrelated changes; do
   not revert them.
2. Add one delete callback to `OrbitIntrosViewData` and thread it from
   `OrbitWired` into the live intro-row rendering path.
3. Choose the smallest bounded swipe implementation for live intro rows:
   either reuse `SwipeableFriendRow` directly when the current contract fits, or
   add the smallest intro-specific wrapper/extraction that preserves the same
   one-open-row and left-reveal behavior without widening friend/group scope.
4. Reuse `DeleteActionButton` and `showConfirmationDialog(...)` for the delete
   affordance and confirmation step; keep copy and button labels bounded to this
   seam.
5. Implement `_onDeleteIntro` in `OrbitWired` so confirmation gates the delete,
   `deleteIntroduction(id)` is called, `_refreshPendingIntroductionsOnPop` is
   set truthfully, and `_loadIntroductions()` republishes the live Orbit intro
   list/count after delete.
6. Preserve existing accept/pass/send-message row behavior and existing friend
   and group swipe behavior while adding the intro delete path.
7. Land the new direct live-path regressions before relying on the broader gate.
8. Run the exact direct suites and `baseline` listed below.
9. Stop and re-evaluate if truthful delete behavior unexpectedly requires P2P
   signaling, DB schema changes, a widened intro loader, or a broader Feed/Orbit
   badge architecture change. Those exceed Session `1` scope.

### risks and edge cases

- Horizontal swipe on intro rows must not steal primarily vertical list scroll.
- The new intro row action owner must not regress the existing one-open-row
  contract on Orbit.
- Delete confirmation must not remove the row on cancel.
- The intro count can be stale if delete does not reload or republish the same
  source of truth that Orbit already uses.
- The shared-host route-return flag must stay bounded; do not trigger a broader
  Feed or Orbit reload when a narrow pending-intro refresh flag is sufficient.
- The working tree is already dirty in adjacent Orbit and Feed files, so
  execution must merge carefully and must not revert unrelated edits.

### exact tests and gates to run

- Fast structural validation before broader runs:
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
    when the callback seam lands, or the smallest targeted Orbit intro widget
    suite if that is the quickest compile-shape proof
- Direct tests:
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`
    or the new narrow live-intro delete widget test file if execution splits it
    out
  - `flutter test test/features/introduction/presentation/widgets/intro_row_test.dart`
    only if row content/status behavior changes
  - `flutter test test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart`
    only if shared swipe mechanics are edited
  - `flutter test test/features/orbit/presentation/widgets/confirmation_dialog_test.dart`
    only if confirmation dialog behavior or copy plumbing changes
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
    only if execution touches the Feed-side route-return intro-refresh seam
- Named gate:
  - `./scripts/run_test_gates.sh baseline`

### known-failure interpretation

- There is no accepted known-failure exemption for the new live intro delete
  regressions in this session.
- Missing the new direct live Orbit intro delete proof, skipping required direct
  tests, or skipping `baseline` is a blocking failure.
- If a required direct test or `baseline` fails outside the changed Orbit intro
  seam, classify it as pre-existing only when the failure is clearly unrelated
  to the session's edits and the evidence supports that reading.
- `feed_wired_test.dart`, `intro_row_test.dart`, `swipeable_friend_row_test.dart`,
  and `confirmation_dialog_test.dart` are conditionally skippable only if the
  implementation truly leaves those seams untouched.

### done criteria

- A live intro row on `Orbit > Intros` reveals delete on left swipe.
- Short or vertical drags do not reveal delete and keep normal scroll behavior.
- The UI keeps only one open intro row at a time.
- Delete taps show confirmation before any data change.
- Confirmed delete removes the intro from the live list, drops any empty
  introducer header, and reaches `No introductions yet` when appropriate.
- Orbit intro count truth is republished after delete and persistent-nav Orbit
  badge truth remains honest.
- Existing accept, pass, send-message, friend-swipe, and group-swipe behavior
  remain intact.
- The direct Session `1` regressions pass and `./scripts/run_test_gates.sh baseline`
  passes.
- The session breakdown is refreshed honestly with the execution result, and
  `00-INDEX.md` is updated only if Report `34` actually closes.

### scope guard

- Do not add P2P, relay, or cross-device intro delete semantics.
- Do not add a new intro delete DB schema, soft-delete state, or migration.
- Do not widen the live intro loader to passed, expired, or other non-live
  statuses.
- Do not redesign friend-row or group-row swipe behavior while fixing intro
  delete.
- Do not broaden into a new root-owned Orbit badge controller, broader Feed
  badge architecture work, or other navigation redesign.
- Do not treat debug settings delete tools as the user-facing surface; the fix
  must land on the live Orbit intro path.

### accepted differences / intentionally out of scope

- Delete remains local-only and repo-backed by the existing hard-delete
  primitive.
- Confirmation copy/button text may vary within the proposal's accepted
  ambiguity as long as destructive intent is clear.
- Whether cancel leaves the row visually open or closed is acceptable either
  way if the intro remains not deleted and the UI stays understandable.
- Current repo truth that the live loader shows only `pending` and
  `already_connected` rows stays accepted for this session.

### dependency impact

- Session `1` is the only implementation slice for Report `34`.
- If Session `1` lands and closure clears, Report `34` can close.
- If Session `1` blocks, Report `34` stays open; no later session exists to
  absorb this seam.
