# Session 55 Plan - Intro-notification Orbit entry parity and final Report 27 closure

## Final verdict

`implementation-ready` via controller-local plan materialization fallback.

- Two fresh planning-agent attempts stayed bounded but failed to materialize
  this doc-scoped plan artifact, so this plan is synthesized directly from the
  Session `55` breakdown plus verified current repo evidence.
- Current repo evidence still shows a real Session `55` gap: the
  intro-notification `NotificationRouteTargetKind.intros` path in
  `lib/main.dart` pushes `OrbitWired` with `appShellController` but without a
  nav-capable `feedUnreadCountListenable`, and it does not switch the shell to
  `orbit` before push, so notification-opened Orbit cannot yet show truthful
  nav state or Feed unread-badge parity.

## Final plan

### real scope

- Keep the current modal notification push/pop architecture in `lib/main.dart`.
- Make the intro-notification Orbit entry reuse the already-landed persistent
  nav contract from the Feed-owned path by supplying:
  - truthful `AppShellController` state on entry and on return
  - a nav-capable `feedUnreadCountListenable`
- Prefer the smallest honest app-root implementation:
  - capture the pre-push shell tab
  - switch the shell to `orbit` before the intro Orbit route is shown
  - supply a Feed unread-count listenable seeded from
    `messageRepository.getTotalUnreadCountExcludingArchived()`
  - restore the prior shell tab only if the intro Orbit route closes while the
    shell is still `orbit`
- Add one narrow app-root/widget regression for the intro-notification route
  contract, plus the direct notification and Orbit/Feed reruns already assigned
  by the breakdown.
- Do not reopen Session `54`, redesign the nav architecture, or widen into
  Orbit keep-alive / sibling-host work from Report `30`.

### closure bar

- Notification-opened Orbit shows the shared `FeedNavigationBar`.
- `Orbit` is the truthful active tab on intro-notification entry.
- Feed unread-badge parity is truthful on that route entry.
- Returning to Feed from notification-opened Orbit leaves
  `AppShellController` truthful whether the user taps `Feed` in the nav or
  closes Orbit while still on the `orbit` tab.
- The modal push/pop architecture remains unchanged.
- Direct notification/orbit/feed regressions pass, and `baseline` passes
  because `lib/main.dart` changed.
- Closure docs move Report `27` to closed only if the landed evidence meets the
  overall report closure bar without widening into Report `30`.

### source of truth

- `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md` is the
  governing contract for Session `55` scope, dependencies, tests, and closure
  obligations.
- `Test-Flight-Improv/14-regression-test-strategy.md` provides the
  direct-regression-first policy.
- `Test-Flight-Improv/test-gate-definitions.md` is the source of truth for
  named gates and confirms `baseline` is required when `lib/main.dart`
  changes.
- Current code and tests beat stale prose:
  - `lib/main.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/conversation/domain/repositories/message_repository.dart`
  - `test/integration/notification_deeplink_integration_test.dart`
  - `test/core/notifications/notification_push_tap_navigate_test.dart`
  - `test/features/push/application/prepare_notification_open_use_case_test.dart`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
- Verified current-repo facts that drive this session:
  - `FeedWired` already passes `_totalUnreadCountNotifier` into `OrbitWired` on
    the Feed-owned route.
  - `OrbitWired` only shows the persistent nav when both
    `appShellController` and `feedUnreadCountListenable` are present.
  - `main.dart` still opens intro-notification Orbit without a
    `feedUnreadCountListenable`, and it does not switch the shell to `orbit`
    before the push.
  - Current direct notification tests cover routing/preparation helpers but do
    not yet prove intro-notification Orbit nav visibility, active-tab truth, or
    shell-truthful return.

### session classification

`implementation-ready`

### exact problem statement

- Session `54` landed the in-app Feed-owned Orbit nav seam, but the app-root
  intro-notification seam is still behind it.
- On the intro-notification path, `main.dart` pushes `OrbitWired` directly from
  the app root:
  - without `feedUnreadCountListenable`, so Orbit cannot render the shared nav
    host it already supports
  - without switching `AppShellController` to `orbit`, so even after nav input
    is supplied the active tab would stay stale on entry
- The route also lacks Feed-return reconciliation at the app-root seam, so
  closing notification-opened Orbit while the shell still says `orbit` would
  leave shell state stale.
- Existing notification-route tests stop at route-target preparation/routing and
  do not prove the app-root intro Orbit surface contract.

### files and repos to inspect next

- Repo scope stays inside
  `/Users/I560101/Project-Sat/mknoon-2/flutter_app`.
- Production files:
  - `lib/main.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/conversation/domain/repositories/message_repository.dart`
- Direct tests:
  - `test/integration/notification_deeplink_integration_test.dart`
  - `test/features/push/application/prepare_notification_open_use_case_test.dart`
  - `test/core/notifications/notification_push_tap_navigate_test.dart` only if
    notification route dispatch changes
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - one new narrow app-root/widget regression:
    `test/features/push/application/intro_notification_orbit_route_test.dart`
- Closure docs:
  - `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md` only if Report `27` actually closes
  - `Test-Flight-Improv/17-roadmap-closure-audit.md` only if that same closure
    state changes

### existing tests covering this area

- `test/integration/notification_deeplink_integration_test.dart` proves remote
  and local notification routing sequences, but it does not prove intro Orbit
  nav visibility or shell-state truth.
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
  proves intro notifications do not trigger unrelated chat catch-up, but it
  does not exercise the app-root Orbit surface.
- `test/core/notifications/notification_push_tap_navigate_test.dart` proves
  route-target extraction for conversation/group pushes only; it is relevant
  only if dispatch wiring changes.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` already
  proves the persistent-nav host contract when Orbit is given both
  `appShellController` and `feedUnreadCountListenable`.
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
  already proves Orbit bottom chrome and content spacing above the persistent
  nav.
- `test/features/feed/presentation/screens/feed_wired_test.dart` already proves
  the Feed-owned persistent-nav seam from Session `54`.

### regression/tests to add first

- Add `test/features/push/application/intro_notification_orbit_route_test.dart`
  first.
  It should prove the app-root intro-notification route contract in one narrow
  harness:
  - opening the intro Orbit route switches the shell to `orbit`
  - the pushed Orbit surface receives a Feed unread badge input and shows the
    shared nav with `Orbit` active
  - tapping `Feed` returns shell state to `feed`
  - closing the route while still on `orbit` restores the pre-push tab
- Keep existing direct notification helper tests intact; do not weaken them to
  paper over the missing app-root proof.

### step-by-step implementation plan

1. Re-read the current dirty `lib/main.dart` and targeted tests before editing,
   then implement only against the repo as it exists now.
2. In `lib/main.dart`, extract or add the smallest app-root helper that opens
   intro-notification Orbit truthfully:
   - snapshot the current shell tab
   - load Feed unread count via
     `messageRepository.getTotalUnreadCountExcludingArchived()`
   - wrap that count in a `ValueNotifier<int>`
   - switch the shell to `orbit` before the push
   - push the existing Orbit route using `OrbitWired`
   - on route completion, dispose the notifier and restore the prior shell tab
     only if the shell still says `orbit`
3. Thread the new unread-count listenable into the intro-notification
   `OrbitWired` construction in `lib/main.dart`.
   Do not change `OrbitWired` itself unless implementation reveals one tiny
   constructor/threading gap.
4. Add the new narrow app-root/widget regression proving the intro-notification
   route contract.
5. Update `test/integration/notification_deeplink_integration_test.dart` only
   if a small helper-level assertion is still missing after the widget proof.
6. Run the exact direct tests and named gate below.
7. Stop and replan if truthful parity requires a broader live unread-count
   controller or wider shell-host redesign. That would exceed Session `55`
   scope.

### risks and edge cases

- `lib/main.dart` is a broad app-root file, so implementation must avoid
  accidental churn outside the intros notification branch.
- The notification path may open Orbit while the shell is already `orbit`; the
  return-tab logic must preserve the pre-push tab rather than always forcing
  `feed`.
- A snapshot `ValueNotifier<int>` is the smallest honest unread-badge input for
  this session. If execution proves live unread updates are required for
  correctness rather than polish, stop and re-evaluate scope before inventing a
  root-owned unread controller.
- The workspace is already dirty in unrelated files, including Orbit and Feed
  files; execution must merge carefully and must not revert unrelated work.
- `baseline` may expose unrelated worktree breakage. Only classify a failure as
  pre-existing if the failing area is clearly outside the changed intro route
  seam and the failure already existed in current repo state.

### exact tests and gates to run

- Direct tests:
  - `flutter test test/features/push/application/intro_notification_orbit_route_test.dart`
  - `flutter test test/integration/notification_deeplink_integration_test.dart`
  - `flutter test test/features/push/application/prepare_notification_open_use_case_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/core/notifications/notification_push_tap_navigate_test.dart`
    only if notification dispatch code changes
- Named gate:
  - `./scripts/run_test_gates.sh baseline`

### known-failure interpretation

- There is no accepted known-failure exemption for the new intro-notification
  route regression or the required direct suites listed above.
- If `baseline` fails outside the changed notification/Orbit seam, execution
  must record the exact unrelated failure and judge whether it is genuinely
  pre-existing current-repo breakage or a regression widened by this session.
- Missing the new widget regression, missing the required direct notification
  suite, or skipping `baseline` is a blocking failure for this session.

### done criteria

- `lib/main.dart` opens intro-notification Orbit with:
  - shell tab switched to `orbit`
  - a supplied unread-count listenable
  - prior shell tab restored on close when still appropriate
- Notification-opened Orbit shows the shared nav with `Orbit` active and a
  truthful Feed unread badge.
- Returning to Feed from notification-opened Orbit leaves the shell truthful.
- The new app-root/widget regression passes.
- Required direct tests pass.
- `baseline` passes.
- Closure docs are updated only after the landed evidence proves Report `27`
  closed in maintenance-time meaning.

### scope guard

- Do not redesign Feed/Orbit hosting into sibling tabs, `IndexedStack`,
  `PageView`, swipe navigation, or Orbit keep-alive.
- Do not reopen Session `54` unless current repo evidence shows an actual
  regression in the already-landed Feed-owned route seam.
- Do not build a general root unread-count architecture unless the minimal
  snapshot-listenable approach is disproven by execution evidence.
- Do not widen into notification dispatch parsing changes unless execution
  proves the current dispatch path is wrong.
- Do not edit unrelated dirty files or revert user work.

### accepted differences / intentionally out of scope

- `TC-27-C05` remains deferred to Report `30`.
- The current modal push/pop architecture remains in place.
- `OrbitCloseButton` redesign is still out of scope.
- Session `54` remains historical already-landed work unless a real regression
  forces reopening it.

### dependency impact

- Session `55` is the final executable session for Report `27`.
- If this plan lands and the closure bar is met, closure work should update:
  - `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md` only if Report `27` closes
  - `Test-Flight-Improv/17-roadmap-closure-audit.md` only if that same closure
    state changes
- If this plan blocks on a broader unread-count architecture or shell-host
  redesign, final program acceptance must remain open and Report `27` must not
  be marked closed.

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- Whether the intro-notification unread badge should live-update while Orbit is
  already open, unless execution evidence proves the snapshot approach is
  insufficient for correctness.
- Any additional helper refactor in `lib/main.dart` beyond what is needed to
  make the intro route truthful and testable.

## Accepted differences intentionally left unchanged

- Session `54` remains historical already-landed work.
- `TC-27-C05` remains deferred to Report `30`.
- The current modal route architecture remains unchanged.
- `OrbitCloseButton` redesign remains out of scope.

## Exact docs/files used as evidence

- `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/main.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/conversation/domain/repositories/message_repository.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/core/notifications/notification_push_tap_navigate_test.dart`
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

## Why the plan is safe or unsafe to implement now

- Safe to implement now because the remaining gap is narrow, current repo
  evidence is explicit, the production seam is isolated to the intro
  notification branch in `lib/main.dart`, and the required direct tests/gates
  are concrete.
- The plan stays within Session `55` by reusing the landed Orbit nav host
  rather than inventing new navigation architecture or reopening Session `54`.
