# Session 59 Plan

## Final verdict

`implementation-ready`

The repo now contains a partial Session `59` landing: `FeedWired` has already
started switching normal Feed/Orbit navigation through an `IndexedStack` host,
but the Orbit side has not finished the matching embedded exit/report seam yet.
Session `59` is still implementation-ready as a bounded recovery/finish pass
because the remaining blocker is local and explicit: `flutter analyze` now
fails on `feed_wired.dart` passing `onEmbeddedExit` into `OrbitWired` before
`orbit_wired.dart` defines that contract, and the updated direct tests have not
been verified yet.

## Final plan

### real scope

- Replace the normal in-app Feed -> Orbit modal push/pop seam in
  `lib/features/feed/presentation/screens/feed_wired.dart` with a bounded local
  shared host for tap-based Feed/Orbit switching.
- Keep `AppShellController.activeTab` as the truth source for `feed` vs
  `orbit`; the shared host should react to controller changes instead of
  calling `Navigator.push(...)` for the Report 30 path.
- Keep both screen subtrees alive during the same in-app session so Feed scroll
  state and Orbit search/filter/list state survive tab round trips.
- Preserve the current `FeedRouteChanges` contract, including
  `changedContactPeerIds`, `changedGroupIds`, `reloadAllContacts`,
  `reloadAllGroups`, and `refreshPendingIntroductions`.
- Preserve the current shared-nav badge truth already present in the dirty
  worktree through `FeedNavigationBar`, Feed unread counts, and Orbit intro
  badge counts.
- Keep notification-originated / standalone Orbit modal entry out of scope
  except for a tiny compatibility shim if the shared-host refactor forces one.
- Leave all swipe, drag, threshold, velocity, and horizontal motion work for
  Session 60.

### closure bar

- Tapping `Orbit` from Feed on the Report 30 path no longer requires
  `Navigator.push(buildOrbitSlideUpRoute(...))`.
- Tapping back to `Feed`, or using Orbit's close affordance under the shared
  host, switches tabs without destroying the Feed or Orbit `State` objects for
  the same session.
- Feed scroll position survives a Feed -> Orbit -> Feed round trip.
- Orbit search/filter/list state survives an Orbit -> Feed -> Orbit round trip.
- Returning from Orbit inside the shared host still applies accumulated
  `FeedRouteChanges`, including targeted contact/group refreshes, full reloads,
  and pending-introduction badge refresh.
- Existing direct Feed/Orbit tests are updated for the shared-host seam and
  `./scripts/run_test_gates.sh baseline` passes.
- `./scripts/run_test_gates.sh feed` runs only if implementation spills into
  feed card/composer/inline-reply/feed-to-conversation behavior beyond shell or
  nav hosting.

### source of truth

- Active session contract:
  `Test-Flight-Improv/30-swipe-nav-feed-orbit-session-breakdown.md`, especially
  Session 59.
- Background / acceptance context only when needed:
  `Test-Flight-Improv/30-swipe-nav-feed-orbit.md`.
- Regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`.
- Named-gate authority:
  `Test-Flight-Improv/test-gate-definitions.md`.
- Current code and tests beat stale prose when they disagree.
- If the gate docs and `scripts/run_test_gates.sh` ever disagree, the script
  wins.

### session classification

`implementation-ready`

### exact problem statement

- `FeedWired` has already been partially refactored toward a shared host, so
  this recovery pass must finish and verify that landing rather than redoing a
  clean-sheet host rewrite.
- The dirty worktree already added Orbit-side persistent-nav behavior in
  `lib/features/orbit/presentation/screens/orbit_wired.dart` and
  `lib/features/orbit/presentation/screens/orbit_screen.dart`; Session 59 must
  preserve that live behavior while removing the modal dependency for ordinary
  Feed/Orbit switching.
- The dirty worktree also added intro-badge refresh obligations through
  `FeedRouteChanges.refreshPendingIntroductions`; the shared host must not drop
  that field while replacing `Navigator.pop(_buildRouteChanges())`.
- The partial landing is currently internally mismatched: `feed_wired.dart`
  passes `onEmbeddedExit` into `OrbitWired`, but
  `lib/features/orbit/presentation/screens/orbit_wired.dart` does not yet
  declare or honor that embedded callback, so analysis fails before runtime
  verification can even start.
- `lib/features/feed/presentation/screens/feed_screen.dart` still owns its nav
  locally and has no host-mode suppression toggle today, so the plan must not
  assume a clean-screen rewrite or centralized nav architecture unless the host
  pattern actually requires it.

### files and repos to inspect next

Production files:

- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`
- `lib/features/feed/application/app_shell_controller.dart` only if a tiny
  helper is required
- `lib/features/feed/domain/models/app_shell_tab.dart`
- `lib/features/feed/domain/models/feed_route_changes.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/orbit/presentation/navigation/orbit_route_transition.dart` only
  for preserving standalone modal Orbit entry
- `lib/main.dart` only if a compatibility touch is required for
  `openIntroNotificationOrbitRoute(...)`

Direct tests:

- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/posts/phase1/app_shell_controller_test.dart`
- `test/features/push/application/intro_notification_orbit_route_test.dart`
  only if `lib/main.dart` or standalone modal Orbit entry is touched

### existing tests covering this area

- `test/features/posts/phase1/app_shell_controller_test.dart` already proves
  valid `feed` / `orbit` switching and duplicate-switch suppression.
- `test/features/feed/presentation/screens/feed_wired_test.dart` already covers
  Orbit nav presence, modal-route result refresh for targeted
  `changedContactPeerIds`, modal-route `reloadAllContacts`, and the new dirty
  worktree intro-badge regressions for initial load, stream refresh, and route
  return refresh.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` already
  covers close-button modal pop behavior, the dirty worktree persistent-nav
  badges, persistent-nav `Feed` tap pop semantics, persistent-nav `Orbit` tap
  no-op behavior, nested `FeedRouteChanges` application for Orbit-owned flows,
  and search-context preservation while unrelated friend updates arrive.
- `test/features/feed/presentation/screens/feed_screen_test.dart` already
  covers the `CustomScrollView` Feed surface and nav visibility rules when
  composer focus and keyboard insets are active.
- `test/features/push/application/intro_notification_orbit_route_test.dart`
  already pins the standalone notification-opened Orbit modal path with
  persistent nav and shell-tab restoration.
- Missing coverage: no direct regression yet proves Report 30 tab switching
  avoids `Navigator.push(...)`, keeps Feed and Orbit mounted together, preserves
  Feed scroll across host tab round trips, preserves Orbit search/filter state
  across host tab round trips, or applies shared-host return changes without a
  route pop.

### regression/tests to add first

- Rewrite the current Feed-side modal-route navigation assertions in
  `test/features/feed/presentation/screens/feed_wired_test.dart` so tapping
  `Orbit` proves the shared host switches tabs without pushing a new route on
  the Report 30 path.
- Add a Feed-host regression proving the existing
  `PageStorageKey('feed-scroll')` survives Feed -> Orbit -> Feed inside one
  shared widget tree.
- Add a host regression proving Orbit search/filter state survives
  Orbit -> Feed -> Orbit because the same `OrbitWired` state stays mounted.
- Replace the modal pop-result refresh assertions with shared-host return
  assertions that still apply `changedContactPeerIds`, `reloadAllContacts`, and
  `refreshPendingIntroductions`. Include group fields if the implementation
  touches Orbit-owned group flows.
- Extend `test/features/orbit/presentation/screens/orbit_wired_test.dart` only
  if `OrbitWired` gains an explicit embedded-host exit callback distinct from
  standalone modal pop behavior.
- Touch
  `test/features/push/application/intro_notification_orbit_route_test.dart`
  only if the shared-host refactor changes the standalone notification-opened
  Orbit route contract.

### step-by-step implementation plan

1. Keep the partial `FeedWired` shared-host landing and reconcile the rest of
   the session around it instead of reintroducing modal push/pop for the normal
   Report 30 path.
2. Finish the minimum Session 59 host shape: keep an `IndexedStack`,
   `Stack` + `Offstage`, or equivalent mounted-child pattern that preserves
   state without introducing drag or gesture plumbing.
3. Give `lib/features/orbit/presentation/screens/orbit_wired.dart` the missing
   embedded exit/report seam so Orbit close and Orbit nav `Feed` actions can
   return a `FeedRouteChanges?` payload without `Navigator.pop(...)` when Orbit
   is mounted inline.
4. Preserve the existing standalone modal Orbit path for callers that still
   need it, including `openIntroNotificationOrbitRoute(...)` in `lib/main.dart`
   and the current standalone Orbit test harnesses, unless a tiny compatibility
   change is unavoidable.
5. Reuse `lib/features/feed/domain/models/feed_route_changes.dart` and its
   existing `merge(...)` helper instead of inventing a new return model for the
   shared host.
6. Preserve the dirty-worktree persistent-nav and badge behavior already in
   `feed_navigation_bar.dart`, `feed_screen.dart`, `orbit_wired.dart`, and
   `orbit_screen.dart`. Do not centralize nav ownership unless the chosen host
   pattern makes duplicate nav painting unavoidable.
7. Align the partially rewritten direct tests with the finished inline-host
   behavior, removing stale modal-route expectations only where the Report 30
   path truly moved inline and keeping standalone notification/modal coverage
   honest.
8. Run `flutter analyze` on the touched Feed/Orbit host files first so the
   recovery pass proves the embedded callback contract is internally coherent
   before relying on widget suites and gates.
9. If Feed needs a tiny host-only flag such as nav suppression or adjusted
   bottom padding, keep it surgical and prove it in
   `test/features/feed/presentation/screens/feed_screen_test.dart`. Do not
   broaden into a Feed layout redesign.
10. Run the direct suites and `baseline` once the host seam compiles. Stop and
    re-plan if the refactor starts forcing a broader app-root or
    notification-route rewrite.

### risks and edge cases

- The worktree is already dirty in the exact Feed/Orbit files and tests this
  session targets. Implementation must merge with those local edits rather than
  resetting them.
- Feed composer focus is still coupled to `_activeFocusPeerId`; leaving Feed
  must continue to clear focus so the nav bar does not stay hidden on return.
- Orbit state preservation only works if the same `OrbitWired` `State` object
  stays alive. Recreating `OrbitWired` on tab changes silently fails the
  session.
- The shared-host return seam must preserve all `FeedRouteChanges` fields,
  including the dirty-worktree `refreshPendingIntroductions` badge-refresh
  contract.
- Standalone modal Orbit entry in `lib/main.dart` and
  `test/features/push/application/intro_notification_orbit_route_test.dart`
  must keep working if untouched.
- Session 60 will later need a swipe-capable host. Session 59 should not choose
  a host shape that destroys state or hard-codes modal-only return semantics.

### exact tests and gates to run

- `flutter analyze lib/features/feed/presentation/screens/feed_wired.dart lib/features/orbit/presentation/screens/orbit_wired.dart test/features/feed/presentation/screens/feed_wired_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
- `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `flutter test test/features/posts/phase1/app_shell_controller_test.dart`
- `./scripts/run_test_gates.sh baseline`
- Conditional:
  `flutter test test/features/push/application/intro_notification_orbit_route_test.dart`
  only if the standalone notification-opened Orbit route or `lib/main.dart`
  changes
- Conditional: `./scripts/run_test_gates.sh feed` only if the implementation
  changes feed cards, feed composer, inline reply, or feed-to-conversation
  handoff behavior
- Do not run `./scripts/run_test_gates.sh 1to1` unless the work accidentally
  changes feed-originated messaging behavior beyond shell or nav hosting

### known-failure interpretation

- Existing modal push/pop assertions in
  `test/features/feed/presentation/screens/feed_wired_test.dart` are expected to
  change for the Report 30 path because Feed now enters Orbit through the
  partially landed inline host. Keep the standalone modal assertions in
  `test/features/orbit/presentation/screens/orbit_wired_test.dart` unless the
  implementation explicitly adds separate inline-host callback coverage.
- The current recovery snapshot already fails analysis because
  `feed_wired.dart` passes an undefined `onEmbeddedExit` named parameter into
  `OrbitWired`; fix that contract mismatch before treating later test failures
  as the next blocker.
- Failures isolated to the current dirty worktree long-press / quote-context
  edits in `feed_screen.dart`, `feed_wired.dart`, `feed_screen_test.dart`, or
  `feed_wired_test.dart` should be treated as concurrent-edit reconciliation
  unless the new shared host directly breaks the same assertions.
- Asset / blur / overflow noise already handled by the existing nav test
  suppressors is not a new Session 59 regression by itself.
- A `baseline` failure outside the changed Feed/Orbit shell seam is pre-existing
  unless the stack trace points back to the shared-host refactor.

### done criteria

- Normal in-app Feed/Orbit tab taps in `FeedWired` no longer depend on modal
  push/pop.
- The shared-host and embedded-exit/report contract compiles cleanly, including
  the inline `OrbitWired` constructor seam used by `FeedWired`.
- Feed scroll state and Orbit search/filter/list state survive same-session tab
  round trips.
- Orbit close and Orbit nav `Feed` return through the shared-host seam while
  still applying accumulated `FeedRouteChanges`, including pending-introduction
  badge refresh.
- Standalone modal Orbit entry remains compiling and working, or an explicit
  tiny compatibility shim plus conditional test update covers the touched path.
- The direct test suites above pass, `baseline` passes, and any conditional
  feed / notification suite triggered by the actual diff also passes.

### scope guard

- No swipe gestures, drag thresholds, velocity handling, page-drag ownership,
  or horizontal motion work in this session.
- No broad `AppShellController` rewrite; only a tiny helper is acceptable if
  it removes duplication.
- No new badge architecture, no new bottom-nav component, and no visual redesign
  of Feed or Orbit chrome.
- No broad `main.dart` or notification-route refactor; only a tiny
  compatibility shim is acceptable, otherwise stop and re-plan.
- No feed card, composer, send-path, or conversation-handoff behavior changes
  beyond minimal host integration.

### accepted differences / intentionally out of scope

- Standalone modal Orbit routes can remain for non-Report 30 entry paths,
  including `openIntroNotificationOrbitRoute(...)`.
- Swipe conflict handling, finger-following motion, snap-back behavior, and
  keyboard dismissal during swipe stay deferred to Session 60.
- Whether the shared host uses `IndexedStack`, `Stack` + `Offstage`, or an
  equivalent mounted-child pattern is an implementation detail, not part of the
  session contract.

### dependency impact

- Session 60 depends on Session 59 landing a stable shared host plus an
  embedded Orbit exit/report seam. If Session 59 leaves normal tab switching on
  modal push/pop or still recreates Orbit state, Session 60 must be re-planned.
- If Session 59 uncovers a broader requirement to unify notification-opened
  Orbit entry with the in-app shared host, Session 60 should pause until that
  architectural dependency is re-audited.
- If Session 59 ends up lifting nav ownership to the host, Session 60 should
  revisit how one truthful nav instance behaves during interactive drag.

## Structural blockers remaining

- None.

## Incremental details intentionally deferred

- The exact mounted-child host primitive (`IndexedStack` vs `Stack` +
  `Offstage`) is intentionally left open.
- Whether `FeedScreen` needs a tiny host-mode flag is intentionally deferred
  until the concrete host shape proves it necessary.
- The exact callback name for inline Orbit exit/report behavior is intentionally
  deferred as long as it carries `FeedRouteChanges?` without widening scope.

## Accepted differences intentionally left unchanged

- Standalone modal Orbit entry stays allowed for notification or other
  non-Report 30 entry seams.
- The dirty-worktree persistent-nav behavior inside modal Orbit tests is kept as
  current repo truth and should not be “simplified away” during Session 59.
- Gesture physics and screen-level swipe arbitration remain Session 60 work.

## Exact docs/files used as evidence

- [30-swipe-nav-feed-orbit-session-breakdown.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/30-swipe-nav-feed-orbit-session-breakdown.md)
- [30-swipe-nav-feed-orbit-session-59-plan.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/30-swipe-nav-feed-orbit-session-59-plan.md)
- [30-swipe-nav-feed-orbit.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/30-swipe-nav-feed-orbit.md)
- [14-regression-test-strategy.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/14-regression-test-strategy.md)
- [test-gate-definitions.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/test-gate-definitions.md)
- [feed_wired.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/screens/feed_wired.dart)
- [feed_screen.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/screens/feed_screen.dart)
- [feed_navigation_bar.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/feed_navigation_bar.dart)
- [app_shell_controller.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/application/app_shell_controller.dart)
- [app_shell_tab.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/domain/models/app_shell_tab.dart)
- [feed_route_changes.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/domain/models/feed_route_changes.dart)
- [orbit_wired.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/presentation/screens/orbit_wired.dart)
- [orbit_screen.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/presentation/screens/orbit_screen.dart)
- [orbit_route_transition.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/presentation/navigation/orbit_route_transition.dart)
- [main.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/main.dart)
- [feed_wired_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/screens/feed_wired_test.dart)
- [feed_screen_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/screens/feed_screen_test.dart)
- [orbit_wired_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/screens/orbit_wired_test.dart)
- [app_shell_controller_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/posts/phase1/app_shell_controller_test.dart)
- [intro_notification_orbit_route_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/push/application/intro_notification_orbit_route_test.dart)

## Why the plan is safe or unsafe to implement now

- Safe now because the live repo already isolates the critical seams:
  `FeedWired` has a partial inline `IndexedStack` host plus
  `appShellController` tab switching for the Report 30 path,
  `OrbitWired` still has the bounded persistent-nav + modal-return behavior
  that must be split into standalone versus embedded exit paths,
  `FeedRouteChanges` already carries all required refresh fields, and the
  direct tests already identify which Feed-side modal assertions must become
  shared-host assertions.
- Safe now because the refreshed gate contract matches the current regression
  docs: direct Feed/Orbit suites plus `baseline` are required, while the `feed`
  gate is conditional rather than assumed.
- Unsafe only if implementation starts forcing a broader app-root or
  notification-route unification than the bounded compatibility shim allowed
  above. In that case the session should stop and be re-planned rather than
  silently widening scope.
