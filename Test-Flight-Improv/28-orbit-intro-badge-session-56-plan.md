# Session 56 Plan - Shared Orbit intro badge contract and freshness wiring

## Final verdict

`implementation-ready`; current repo evidence still shows Session `56` is
open.

- `FeedNavigationBar` production code still accepts only `feedBadgeCount`, and
  both `FeedScreen` and persistent-nav `OrbitScreen` still thread only Feed
  unread state into the shared nav.
- `FeedWired` still has no Feed-owned intro badge truth: its
  `introReceivedStream` listener is a no-op, intro status handling only
  refreshes mutual-accept contact cards, and `FeedRouteChanges` still has no
  bounded intro-refresh signal.
- `OrbitWired` still owns expiry-aware intro truth locally, while the working
  tree already contains an in-progress `orbitBadgeCount` expectation in
  `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`;
  execution must merge with that live state instead of resetting it.

## Final plan

### real scope

- Extend the shared `FeedNavigationBar` contract so Feed unread and Orbit
  pending-intro badge counts can coexist without mixing counts.
- Thread the Orbit intro badge input through both shared-nav hosts:
  `FeedScreen` and the already-landed persistent-nav `OrbitScreen`.
- Add Feed-owned pending-intro badge state in `FeedWired`, including:
  - expiry-aware initial load after identity is available
  - refresh on new intro receipt
  - refresh on remote intro status changes that affect pending truth
- Close the local route-return freshness seam by adding one bounded intro badge
  refresh signal to `FeedRouteChanges` or an equivalent narrow route result so
  local Orbit `accept` or `pass` cannot leave Feed stale on return.
- Keep `OrbitWired` as the source of truth for Orbit intro count on the Orbit
  surface; do not introduce a second owner or root-level controller.
- Preserve current intro notification behavior and existing Feed/Orbit tap
  behavior.

### closure bar

- `FeedNavigationBar` can render independent Feed unread and Orbit pending
  intro counts on both Feed and persistent-nav Orbit surfaces.
- Feed-side cold load and app reopen are expiry-aware before publishing intro
  badge truth.
- New intro receipt, remote intro status changes, and returning from Orbit
  after local `accept` or `pass` all refresh the Feed-owned intro badge.
- `alreadyConnected` and expired intros do not keep the Orbit badge alive.
- Existing Orbit navigation behavior and intro notification behavior remain
  unchanged.
- Direct regressions proving shared-nav badge coexistence, intro-count truth,
  route-return freshness, and unchanged nav behavior pass.
- `./scripts/run_test_gates.sh baseline` passes because this is shared
  top-level surface wiring.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/28-orbit-intro-badge-session-breakdown.md`
  - `Test-Flight-Improv/28-orbit-intro-badge.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code and tests beat stale prose when they disagree.
- Verified repo seams:
  - `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`
  - `lib/features/feed/presentation/widgets/nav_bar_button.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/domain/models/feed_route_changes.dart`
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/introduction/application/introduction_listener.dart`
  - `lib/features/introduction/application/load_introductions_use_case.dart`
  - `lib/features/introduction/application/expire_old_introductions_use_case.dart`
  - `lib/features/introduction/domain/repositories/introduction_repository.dart`
  - `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
  - `lib/core/database/helpers/introductions_db_helpers.dart`

### session classification

`implementation-ready`

### exact problem statement

- `FeedNavigationBar` currently exposes only `feedBadgeCount`, so the shared
  nav cannot show Orbit intro truth.
- `FeedScreen` only threads Feed unread state into the shared nav.
- `FeedWired` has no pending-intro badge state and leaves
  `introReceivedStream.listen((_) {})` as a no-op.
- `FeedWired` handles intro status changes only for mutual-accepted contact
  refreshes, not for Feed-owned badge truth.
- `FeedRouteChanges` tracks contact/group refreshes only, so local Orbit intro
  actions do not have a bounded return signal for badge refresh.
- `OrbitWired` already owns expiry-aware intro loading and `_introsCount`, but
  that truth is not threaded back into the shared nav contract.
- `countPendingIntroductions()` already excludes `alreadyConnected`, while
  expired rows become truthful only after `expireOldIntroductions(...)` runs.

### files and repos to inspect next

- Repo scope stays inside
  `/Users/I560101/Project-Sat/mknoon-2/flutter_app`.
- Production files:
  - `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`
  - `lib/features/feed/presentation/widgets/nav_bar_button.dart` only if badge
    pass-through semantics need a narrow update
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/domain/models/feed_route_changes.dart`
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
- Direct tests:
  - `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
  - `test/features/feed/presentation/widgets/nav_bar_button_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `test/features/introduction/application/introduction_listener_test.dart`
  - `test/features/introduction/application/handle_incoming_introduction_test.dart`
  - `test/features/introduction/regression/introduction_regression_test.dart`
  - `test/features/push/application/intro_notification_orbit_route_test.dart`
    only if notification-opened persistent-nav behavior is touched
- Closure docs:
  - `Test-Flight-Improv/28-orbit-intro-badge-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md` only if Session `56` actually closes
    Report `28`

### existing tests covering this area

- `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
  already includes a live dirty-tree `orbitBadgeCount` expectation and is the
  first direct seam for proving independent Feed and Orbit badge truth without
  count mixing.
- `test/features/feed/presentation/widgets/nav_bar_button_test.dart` already
  proves badge rendering semantics and `99+` cap.
- `test/features/feed/presentation/screens/feed_wired_test.dart` already proves
  Orbit nav presence, route-return contact/group refreshes, and mutual-accept
  contact refresh behavior.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` already
  proves persistent-nav rendering with Feed unread state and route-return
  refresh behavior on the Orbit surface.
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  already proves intro count repository truth and accept/pass intro count
  changes in Orbit-facing intro flows.
- `test/features/introduction/application/introduction_listener_test.dart`
  already proves intro receipt/status stream behavior.
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
  already proves `alreadyConnected` rows do not inflate pending intro counts.
- `test/features/introduction/regression/introduction_regression_test.dart`
  already proves expired intros are excluded from `countPendingIntroductions`.
- `test/features/push/application/intro_notification_orbit_route_test.dart`
  already proves notification-opened persistent-nav behavior and should stay
  unchanged unless this session touches that route.
- Missing today:
  - no direct proof that Feed and Orbit badges coexist in the shared nav
  - no direct proof that Feed-side intro badge truth is expiry-aware on load
  - no direct proof that local Orbit `accept` or `pass` refreshes the Feed
    badge on return

### regression/tests to add first

- Extend `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
  first to prove independent Feed and Orbit badge inputs are passed through the
  shared nav without mixing counts.
- Add or extend `test/features/feed/presentation/screens/feed_wired_test.dart`
  to prove:
  - expiry-aware initial intro badge load after identity resolution
  - live badge refresh on intro receipt and status change
  - route-return badge refresh after local Orbit `accept` or `pass`
- Add or extend `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  to prove persistent-nav Orbit badge truth coexists with existing Feed unread
  badge threading and active-tab behavior.
- Keep `test/features/push/application/intro_notification_orbit_route_test.dart`
  unchanged unless implementation evidence forces notification-route contract
  changes.

### step-by-step implementation plan

1. Re-read the current dirty targeted files before editing and implement only
   against the live repo state.
2. Extend `FeedNavigationBar` with one additional Orbit intro badge input,
   reusing the existing numeric `badgeCount` visual contract.
3. Thread that new Orbit badge input through `FeedScreen` and `OrbitScreen`
   without altering existing nav tap behavior.
4. Add Feed-owned pending-intro badge state in `FeedWired`:
   - wait until identity / own peer ID is known
   - run `expireOldIntroductions(...)`
   - publish truth from `countPendingIntroductions(...)`
   - guard async updates with mounted / latest-request checks as needed
5. Replace the no-op `introReceivedStream` listener in `FeedWired` with a
   pending-intro badge refresh path.
6. Extend intro status handling in `FeedWired` so status changes refresh badge
   truth while preserving the existing mutual-accepted contact refresh.
7. Extend `FeedRouteChanges` with one bounded intro-refresh signal and use it
   in `FeedWired._applyRouteChanges`.
8. Make `OrbitWired` return that intro-refresh signal when local intro actions
   (`accept` / `pass`) can change pending badge truth, while continuing to use
   its existing intro load path for Orbit-local truth.
9. Thread `OrbitWired` intro count into `OrbitScreen` persistent nav so the
   shared nav stays truthful on the Orbit surface too.
10. Add or update the direct regressions above, then run the exact tests and
    gate below.
11. Stop and re-evaluate if truthful behavior requires `lib/main.dart`, a
    root-owned badge controller, or wider navigation redesign. That exceeds
    Session `56` scope.

### risks and edge cases

- Feed intro badge loading cannot happen until own peer ID is available, so
  initial load ordering matters.
- Multiple intro events can race; asynchronous badge loads must not publish
  stale counts after a newer refresh finishes.
- Expired intros must not remain visible just because Feed skipped
  `expireOldIntroductions(...)`.
- `alreadyConnected` must continue to stay out of badge truth through existing
  repository contracts, not duplicated client-side filters.
- Route-return refresh should stay bounded; do not force unrelated full Feed or
  Orbit reloads when a narrow intro refresh signal is enough.
- The working tree is already dirty in several targeted files, so execution
  must merge carefully and must not revert unrelated edits.

### exact tests and gates to run

- Direct tests:
  - `flutter test test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
  - `flutter test test/features/feed/presentation/widgets/nav_bar_button_test.dart`
    only if badge rendering or semantics change beyond simple pass-through
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `flutter test test/features/introduction/application/introduction_listener_test.dart`
  - `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart`
  - `flutter test test/features/introduction/regression/introduction_regression_test.dart`
  - `flutter test test/features/push/application/intro_notification_orbit_route_test.dart`
    only if notification-opened persistent-nav behavior changes
- Named gate:
  - `./scripts/run_test_gates.sh baseline`

### known-failure interpretation

- There is no accepted known-failure exemption for the new shared-nav intro
  badge regressions in this session.
- Missing the new shared-nav / Feed freshness regressions, skipping any
  required direct suite above, or skipping `baseline` is a blocking failure.
- If a required test or `baseline` fails outside the changed Feed / Orbit /
  intro badge seam, classify it as pre-existing only when the failure is
  clearly unrelated to this session's edits and the evidence supports that
  reading.
- The notification-route test is conditionally skippable only if this session
  does not touch the notification-opened persistent-nav contract.

### done criteria

- `FeedNavigationBar` truthfully renders independent Feed and Orbit badge
  counts.
- `FeedScreen` and persistent-nav `OrbitScreen` both thread the new shared-nav
  Orbit badge input.
- `FeedWired` publishes expiry-aware intro badge truth after identity load and
  refreshes it on intro receipt, intro status changes, and route return from
  local Orbit intro actions.
- `OrbitWired` keeps persistent-nav intro badge truth aligned with its existing
  intro count and returns a bounded route result for local intro-action
  freshness.
- `alreadyConnected`, expired intros, existing Orbit navigation, and intro
  notification behavior remain unchanged.
- Required direct suites and `./scripts/run_test_gates.sh baseline` pass.

### scope guard

- Do not introduce a second badge visual system, a dot-only indicator, or a new
  nav component.
- Do not redesign `NavBarButton` unless one narrow accessibility or pass-through
  adjustment is required.
- Do not widen into `lib/main.dart`, notification routing, swipe navigation,
  keep-alive behavior, or a root-owned intro badge controller unless code
  evidence proves the session contract is incomplete.
- Do not broaden into Report `25` delete-path parity.
- Do not clean up unrelated dirty files while working this session.

### accepted differences / intentionally out of scope

- Reuse the existing numeric `badgeCount` contract; do not force a separate
  dot-only product system.
- Leave Report `25` delete-intro parity for future work because the delete UI
  is still not landed.
- Keep the current Report `27` modal / persistent-nav architecture.
- Keep `alreadyConnected` and expired intro handling on the existing repo
  contracts rather than inventing a second intro status model.
- Leave notification-opened persistent-nav behavior unchanged unless the
  implementation unexpectedly touches that path.

### dependency impact

- Session `56` has no earlier session dependency and is the only executable
  session in this breakdown.
- If execution lands cleanly, closure must update
  `Test-Flight-Improv/28-orbit-intro-badge-session-breakdown.md` and update
  `Test-Flight-Improv/00-INDEX.md` only if Report `28` truly closes.
- If execution proves that truthful behavior needs app-root nav ownership or
  notification-route changes, stop rather than widening scope; the session
  should become `blocked` or `accepted_with_explicit_follow_up`, not silently
  broadened.
