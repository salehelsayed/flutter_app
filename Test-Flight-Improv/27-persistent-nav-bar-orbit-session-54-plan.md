# Session 54 Plan - Orbit route persistent-nav adoption and shell-state parity

## Final verdict

`implementation-ready` with two execution cautions:

- the targeted Feed-side files are currently dirty in the worktree, including in-flight message-context / quote-reply edits in `feed_screen.dart`, `feed_wired.dart`, and `feed_wired_test.dart`, and the two primary Orbit direct suites are dirty as well, so implementation must rebase against the repo as it exists now instead of assuming a clean baseline
- direct reruns on 2026-03-30 confirm the primary Orbit direct suites already encode most of the Session 54 contract, but they still fail at compile time because production `OrbitScreen` / `OrbitWired` do not yet expose the nav parameters those tests expect

## Final plan

### real scope

- Reuse the existing `FeedNavigationBar` contract on the in-app Orbit route instead of inventing a second tab bar widget.
- Keep the current Feed-owned modal push/pop architecture in `FeedWired`; Session 54 only makes that seam truthful while Orbit is open.
- Make Orbit-side tab behavior honest for the in-app path: `Feed` from Orbit returns cleanly through the current route contract, `Orbit` while already on Orbit is a true no-op, and active-tab state stays coherent with `_orbitRouteOpen` and `_orbitReturnTab`.
- Preserve Feed-side behavior that already exists, especially hiding the nav bar only when inline reply focus and keyboard insets are both present.
- Reserve enough bottom space on Orbit so the nav bar, search trigger, search dock, close button, and scroll content do not obscure each other.
- Carry Feed unread-badge parity onto Orbit through the smallest honest seam already present in `FeedWired`.
- Land permanent direct regressions for Feed-originated Orbit entry, Orbit-hosted `Feed` return, duplicate `Orbit` taps, active-tab truth, badge parity, and Orbit chrome/padding behavior.
- Do not touch `main.dart`, notification entry, or Session 55 acceptance work in this session.

### closure bar

- Feed-originated navigation to Orbit still uses the existing slide-up route, but Orbit now renders the same bottom-nav affordance with `Orbit` active.
- Tapping `Feed` from Orbit returns to Feed without leaving shell state stuck on `orbit`.
- Tapping `Orbit` while already on Orbit does not push a second route, flicker state, or mutate the controller.
- Feed keeps its current keyboard-hide nav behavior.
- Orbit bottom chrome remains reachable and visually unobscured with the nav present.
- The same unread-count contract used by Feed is visible from Orbit.
- Direct Feed/Orbit widget and screen regressions pin all of the above without widening into notification-entry or sibling-shell rewrites.

### source of truth

- `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md` is the governing session contract for Session 54 scope, order, accepted differences, and downstream obligations.
- `Test-Flight-Improv/27-persistent-nav-bar-orbit.md` is problem framing only; where it conflicts with the session split, the breakdown artifact and current repo state win.
- `Test-Flight-Improv/test-gate-definitions.md` is the execution source of truth for named gates.
- `Test-Flight-Improv/14-regression-test-strategy.md` supplies the direct-regression-first policy; it does not override the breakdown artifact's narrower Session 54 split.
- Current code and current tests win over stale prose:
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`
  - `lib/features/feed/application/app_shell_controller.dart`
  - `lib/features/feed/domain/models/app_shell_tab.dart`
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/orbit/presentation/navigation/orbit_route_transition.dart`
  - `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
  - `test/features/posts/phase1/app_shell_controller_test.dart`
- Observed repo-state test results on 2026-03-30 are part of the source-of-truth evidence:
  - `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` fails at compile time because `OrbitScreen` has no `activeTab` named parameter
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart` fails at compile time because `OrbitWired` has no `feedUnreadCountListenable` named parameter
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart` currently passes

### session classification

`implementation-ready`

### exact problem statement

- `FeedScreen` is still the only place that hosts `FeedNavigationBar`, so the nav disappears as soon as `FeedWired` pushes `OrbitWired`.
- `FeedWired._onShellChanged()` and `_openOrbitRoute()` already define the real in-app seam: switch controller to `orbit`, push the Orbit route once, and on pop restore `_orbitRouteOpen` and `_orbitReturnTab`.
- `OrbitWired` already accepts `appShellController`, but `OrbitScreen` does not render or drive any persistent nav, so the user loses tab affordance, active-tab truth, and Feed badge parity while Orbit is open.
- The current Orbit direct suites already express the intended Session 54 contract, but production constructor surfaces lag behind them: `OrbitScreen` does not accept `activeTab` / `onSwitchView`, and `OrbitWired` does not accept `feedUnreadCountListenable`.
- `OrbitScreen` also has no bottom-padding contract for an added nav host; it currently relies on fixed bottom positions for the close button and search trigger plus a `SizedBox(height: projection.searchActive ? 320 : 100)` spacer.
- The user-visible improvement for Session 54 is limited to the normal in-app Feed <-> Orbit route path. Notification entry and app-root parity stay unchanged here and are owned by Session 55.
- Feed cards, feed content, Orbit data flows, and the broader transition model must stay unchanged unless a tiny local layout adjustment is the only safe way to avoid nav overlap.

### files and repos to inspect next

- Repo scope is local to `/Users/I560101/Project-Sat/mknoon-2/flutter_app`; no other repo is needed.
- Production files:
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`
  - `lib/features/feed/application/app_shell_controller.dart` only if a small shell helper is genuinely needed
  - `lib/features/feed/domain/models/app_shell_tab.dart`
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/orbit/presentation/navigation/orbit_route_transition.dart` only if a minimal route/layout tweak is needed
- Direct tests and helpers:
  - `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
  - `test/features/posts/phase1/app_shell_controller_test.dart`
  - `test/shared/fakes/in_memory_message_repository.dart` only if execution abandons the already-wired `ValueNotifier<int>` seam and instead tries to prove badge parity through repository-backed unread counts

### existing tests covering this area

- `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart` covers the shared nav component's labels, tap callbacks, visual scaffolding, and the rule that only the Feed button receives the badge count.
- `test/features/feed/presentation/screens/feed_screen_test.dart` already pins Feed-side nav visibility and the keyboard-hide rule:
  - nav stays visible when reply focus exists without keyboard insets
  - nav hides when reply focus and software keyboard insets are both present
- `test/features/feed/presentation/screens/feed_wired_test.dart` currently passes and already proves Feed can push the Orbit route and reconcile `FeedRouteChanges` after pop; it does not yet pin the pushed Orbit surface's persistent-nav truth, so Session 54 should extend this file only for the missing Feed-owned route assertion.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` already contains Session 54 regressions for shared unread badge parity, Orbit-hosted `Feed` return, and duplicate `Orbit` taps as a route-level no-op. Its helper already accepts `appShellController` and `feedUnreadCountListenable`; the current failure is production constructor drift, not missing test harness wiring.
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` already contains the bottom-chrome and search-dock geometry regressions for the persistent-nav seam. Its helper is ahead of production and is red only because `OrbitScreen` does not yet expose the nav parameters it expects.
- `test/features/posts/phase1/app_shell_controller_test.dart` already proves invalid and duplicate `switchTo()` requests are ignored at the controller level; it does not prove route-level no-op behavior.

### regression/tests to add first

- `test/features/feed/presentation/screens/feed_wired_test.dart`
  - Add the missing Feed-owned route regression that taps `Orbit` from Feed, waits for the route transition, and asserts the pushed Orbit surface still shows `FeedNavigationBar` with `Orbit` active.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - Keep the existing badge-parity, `Feed` return, and duplicate-`Orbit` no-op regressions intact and use them as the first red bar to turn green; do not rewrite or delete them to make the suite compile.
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
  - Keep the existing bottom-chrome and search-dock geometry regressions intact and use them as the layout acceptance contract once `OrbitScreen` exposes the missing nav parameters.
- `test/features/posts/phase1/app_shell_controller_test.dart`
  - Only add coverage here if implementation introduces a tiny helper in `AppShellController`; otherwise keep controller tests unchanged and prove behavior at the route/widget seam instead.

### step-by-step implementation plan

1. Re-read the current dirty versions of `feed_screen.dart`, `feed_wired.dart`, `feed_wired_test.dart`, `orbit_wired_test.dart`, and `orbit_screen_loading_test.dart` before editing, then implement against those exact contents without reverting the in-flight message-context / quote-reply or persistent-nav regression changes already present there.
2. Make the current Orbit direct suites compile without widening scope:
   - add only the missing `OrbitScreen` nav constructor surface (`activeTab`, `onSwitchView`, `feedUnreadCountListenable`)
   - add only the missing `OrbitWired` constructor surface needed to forward the Feed unread-count listenable
   - keep the already-written Orbit tests as the contract instead of replacing them
3. Add the missing Feed-owned route regression in `feed_wired_test.dart` so the actual `FeedWired` push seam is pinned end-to-end without disturbing the new quote-reply work already living in that file.
4. Extend the Orbit presentation seam so `OrbitScreen` can host the existing `FeedNavigationBar` contract:
   - pass active tab, switch callback, and Feed unread count into Orbit
   - reuse the existing nav widget instead of creating a second Orbit-specific tab component
5. Update Orbit layout to reserve bottom space and reposition bottom chrome relative to the nav host:
   - keep the close button and search trigger reachable
   - keep the search dock from colliding with the nav host
   - keep Feed's keyboard-hide behavior local to Feed rather than copying it onto Orbit by accident
6. Wire Orbit-side tab actions through the current route/controller contract:
   - `Feed` from Orbit should switch shell state back to `feed` and pop the Orbit route exactly once
   - `Orbit` from Orbit should be a no-op because the controller already ignores duplicate `switchTo()` values
   - `FeedWired._orbitRouteOpen` and `_orbitReturnTab` must remain coherent after a manual Feed return from Orbit
7. Reuse Feed's existing `_totalUnreadCountNotifier` seam for Orbit badge parity before considering any repository or controller helper changes.
   Do not introduce app-root state ownership, notification work, or repo-fake unread plumbing unless the current listenable seam is proven insufficient.
8. Keep `orbit_route_transition.dart` unchanged unless a minimal local layout fix is required to prevent nav/chrome overlap during the existing slide-up animation.
9. Run the exact direct suites listed below and stop if the work unexpectedly requires `main.dart`, notification routing, a sibling-tab shell rewrite, or broad Feed card/composer changes. That would violate Session 54 scope and belongs to Session 55, Report 30, or replanning.

### risks and edge cases

- `lib/features/feed/presentation/screens/feed_screen.dart`, `lib/features/feed/presentation/screens/feed_wired.dart`, `test/features/feed/presentation/screens/feed_wired_test.dart`, `test/features/orbit/presentation/screens/orbit_wired_test.dart`, and `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` are already dirty in the worktree; blindly applying stale diffs would be unsafe.
- Those dirty Feed-side edits already add message-context overlay and quote-reply focus behavior, so Session 54 nav work in the same files can accidentally regress unrelated interaction behavior if the implementation rewrites instead of merges.
- The primary Orbit acceptance suites are already red at compile time, so there is a real risk of "fixing" the problem by deleting or diluting tests rather than by landing the missing constructor/threading work.
- `Feed` tapped from Orbit can desynchronize controller state and route state if implementation switches tabs without also popping the pushed Orbit route.
- Duplicate `Orbit` taps can still misbehave at the route level even though `AppShellController` already ignores duplicate values; the regression must prove only one route stays open.
- `OrbitScreen` currently uses fixed bottom offsets plus a bottom spacer tuned for search-only chrome. Adding nav without revisiting those numbers can obscure the close button, search trigger, or list tail.
- If new Feed-side assertions reach for repository-backed unread counts instead of the already-injected listenable seam, `test/shared/fakes/in_memory_message_repository.dart` will return `0` and create false confidence.
- Feed scroll state should stay preserved because the Feed route remains mounted under the Orbit route; Orbit state across a full pop and reopen is not guaranteed in the current architecture and must not be promised here.

### exact tests and gates to run

- Direct suites:
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
  - `flutter test test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
- Conditional direct suite:
  - `flutter test test/features/posts/phase1/app_shell_controller_test.dart` only if `AppShellController` is modified
- Named gates:
  - none by default for the bounded Session 54 seam, because current gate definitions keep the relevant Orbit and Feed suites as direct runs outside the frozen named lists
  - do not widen this session into `feed`, `groups`, or `transport`
  - re-evaluate `./scripts/run_test_gates.sh feed` only if implementation spills into Feed card/composer/inline-reply behavior
  - run `./scripts/run_test_gates.sh baseline` only if implementation unexpectedly moves root app-shell ownership or startup wiring outside the current Feed/Orbit seam

### known-failure interpretation

- Pre-existing repo-state failures observed on 2026-03-30:
  - `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` fails to compile because `OrbitScreen` has no named parameter `activeTab`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart` fails to compile because `OrbitWired` has no named parameter `feedUnreadCountListenable`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "orbit route result refreshes only the changed contact snapshot"` passes, confirming the existing Feed-owned Orbit route seam is still green enough to build on
- Treat those Orbit compile failures as the exact Session 54 drift to fix, not as a reason to widen scope into unrelated Orbit or Feed bugs.
- If a targeted direct suite fails for reasons other than the known constructor drift after implementation starts, classify that separately before expanding scope.
- If badge-parity assertions read `0` from the default in-memory message fake, treat that as a harness mistake and switch back to the existing listenable seam or an explicit spy.
- Unrelated dirty worktree changes, especially in Feed files, must be treated as pre-existing local context rather than normalized inside this session.

### done criteria

- Feed-originated Orbit entry shows the reused `FeedNavigationBar` on Orbit with `Orbit` active.
- Orbit-hosted `Feed` tap returns to Feed cleanly and leaves `appShellController.activeTab == AppShellTab.feed`.
- Orbit-hosted duplicate `Orbit` taps are true no-ops at the route level.
- Orbit bottom chrome and content padding remain usable with the nav host present.
- Feed keeps the current keyboard-hide rule for inline reply.
- Orbit shows the same honest Feed unread badge contract as Feed.
- The direct regressions listed above are present and the targeted suites pass.
- No Session 55 files or notification-entry behavior are modified unless the breakdown artifact itself must be refreshed to narrow later work.

### scope guard

- Do not modify `lib/main.dart` or any notification/deep-link routing.
- Do not process Session 55 or any other report artifact.
- Do not replace the current modal route architecture with `PageView`, `IndexedStack`, sibling tabs, or swipe navigation.
- Do not create a second Orbit-only nav widget when `FeedNavigationBar` can be reused.
- Do not revert or refactor the current message-context overlay / quote-reply work that is already present in the dirty Feed files and tests.
- Do not broaden into Feed card behavior, Feed composer behavior, Orbit data loading, or unrelated app-shell cleanup.
- Do not invent a new named gate, closure doc, or matrix doc for this seam.

### accepted differences / intentionally out of scope

- Notification/root-entry Orbit parity and `test/integration/notification_deeplink_integration_test.dart` remain Session 55 work.
- The current vertical slide-up modal route semantics remain in place unless a tiny local layout adjustment is required to keep the nav/chrome honest.
- Orbit state across a full pop back to Feed and later reopen is still route-backed and may reset; Session 54 does not promise sibling-tab keep-alive parity.
- Close-button retention or removal is not a separate goal for this session.

### dependency impact

- Session 55 depends on Session 54 producing exactly one honest Orbit nav contract for reuse from the notification-entry seam.
- If Session 54 ends up requiring `main.dart`, notification routing, or root-shell ownership changes, Session 55 must be replanned rather than absorbing those changes implicitly.
- If Session 54 narrows or changes the accepted differences for Session 55, refresh `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md` after implementation.

## Structural blockers remaining

- None.

## Incremental details intentionally deferred

- Whether the shared nav host lives as a tiny placement helper or as small duplicated placement code is an implementation detail, not a planning blocker, as long as `FeedNavigationBar` itself is reused.
- Whether `orbit_route_transition.dart` needs a tiny layout-related tweak is deferred until the bottom-chrome regression proves overlap.
- Whether the close button stays or is removed for cleanliness is deferred unless the chosen implementation makes one option obviously simpler without widening scope.

## Accepted differences intentionally left unchanged

- Session 54 does not solve notification-entry parity.
- Session 54 does not solve swipe or horizontal Feed/Orbit navigation.
- Session 54 does not upgrade Feed/Orbit into a persistent sibling-tab shell that preserves Orbit state after a full pop.

## Exact docs/files used as evidence

- `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md`
- `Test-Flight-Improv/27-persistent-nav-bar-orbit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`
- `lib/features/feed/application/app_shell_controller.dart`
- `lib/features/feed/domain/models/app_shell_tab.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/orbit/presentation/navigation/orbit_route_transition.dart`
- `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
- `test/features/posts/phase1/app_shell_controller_test.dart`
- `test/shared/fakes/in_memory_message_repository.dart`

## Why the plan is safe or unsafe to implement now

- Safe:
  - the in-app Feed <-> Orbit seam is already explicit in current code
  - the breakdown artifact isolates Session 54 from Session 55 cleanly
  - the current red Orbit direct suites already encode most of the desired contract, so execution has a concrete target instead of a speculative one
  - the current dirty Feed-side edits are identifiable and orthogonal, so the implementation can merge around them without reopening the session scope
  - duplicate-tab behavior is already partially pinned at the controller layer
- Unsafe if executed carelessly:
  - the worktree is dirty in targeted Feed files and the shared Feed test harness
  - the source doc is broader than the session split, so implementing from prose alone would leak Session 55 scope
  - deleting or weakening the already-written Orbit regressions would create false green results without actually fixing the seam
