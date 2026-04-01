# 27 - Persistent Bottom Navigation Bar Across Feed and Orbit Session Breakdown

## Historical recommended plan count

- `1`
- The only active downstream planning slot for this report was
  `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-55-plan.md`, and it
  is now completed.
- Keep `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-54-plan.md` as
  the historical doc-scoped artifact for already-landed in-app work. Do not
  replan either session unless a real regression reopens that seam.

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/27-persistent-nav-bar-orbit.md`
- Session `55` status:
  `accepted`; this artifact is the stable closure-owner record for Report
  `27`, and future work should reopen only on real regressions.
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Final program acceptance verdict

- Final program state:
  `closed`
- Program-level verdict:
  Sessions `54` and `55` together meet the overall closure bar for Report
  `27`
- Why:
  - Feed-originated Orbit and intro-notification Orbit now both show the shared
    `FeedNavigationBar` with truthful active-tab state
  - the intro-notification app-root seam now supplies the unread-badge input
    that `OrbitWired` expects, so Feed badge parity remains truthful on entry
  - returning from notification-opened Orbit now leaves
    `AppShellController` truthful whether the user taps `Feed` in the nav or
    closes Orbit while still on the `orbit` tab
  - the accepted fix kept the modal push/pop architecture intact and did not
    widen into Report `30`
- Acceptance evidence:
  - Session `54` remains historical already-landed evidence for the
    Feed-originated seam
  - Session `55` landed `openIntroNotificationOrbitRoute(...)` in
    `lib/main.dart` plus the new direct regression
    `test/features/push/application/intro_notification_orbit_route_test.dart`
  - Session `55` passed:
    - `flutter test test/features/push/application/intro_notification_orbit_route_test.dart`
    - `flutter test test/integration/notification_deeplink_integration_test.dart`
    - `flutter test test/features/push/application/prepare_notification_open_use_case_test.dart`
    - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
    - `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
    - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
    - `./scripts/run_test_gates.sh baseline`
- Residual-only outcome for this rollout:
  - none beyond the explicitly deferred `TC-27-C05` follow-up owned by Report
    `30`
- Still-open implementation items for this rollout:
  - none
- Accepted differences preserved at program level:
  - `TC-27-C05` stays deferred to Report `30`
  - the current modal route architecture stays in place
  - the app-root intro route uses a snapshot unread-count listenable rather
    than widening into a new root-owned live unread controller
  - `OrbitCloseButton` redesign remains out of scope

## Overall closure bar

Report `27` is closed only when the current modal Feed <-> Orbit contract and
the intro-notification Orbit entry both present one honest top-level navigation
surface:

- Feed-originated Orbit and intro-notification Orbit both show the shared
  `FeedNavigationBar` with truthful active-tab state and Feed unread-badge
  parity.
- Returning to Feed from Orbit leaves `AppShellController` truthful whether
  Orbit was opened from Feed or from an intro notification.
- The current modal push/pop architecture remains in place. Report `27` does
  not widen into sibling-tab hosting, `PageView`, `IndexedStack`, or swipe
  navigation.
- Orbit bottom chrome and scrolled content stay clear of the persistent nav.
- Permanent regressions prove both entry paths.
- `TC-27-C05` stays deferred to Report `30`; Report `27` closes on persistent
  nav parity and truthful shell state, not Orbit keep-alive after a full pop
  and later reopen.

## Source of truth

Current code and tests beat stale prose where they differ. This decomposition is
governed by the following evidence, in descending priority:

- `lib/main.dart` now routes `NotificationRouteTargetKind.intros` through
  `openIntroNotificationOrbitRoute(...)`, which:
  - snapshots the current shell tab
  - loads Feed unread count through `MessageRepository`
  - supplies `OrbitWired` with a nav-capable `feedUnreadCountListenable`
  - switches the shell to `orbit` before push
  - restores the prior shell tab only when the route closes while the shell is
    still `orbit`
- `lib/features/feed/presentation/screens/feed_wired.dart` remains the
  Feed-originated modal owner and still passes `_totalUnreadCountNotifier`
  into `OrbitWired` as `feedUnreadCountListenable`.
- `lib/features/orbit/presentation/screens/orbit_wired.dart` still renders the
  persistent nav only when both `appShellController` and
  `feedUnreadCountListenable` are present; both accepted entry paths now satisfy
  that contract.
- `lib/features/orbit/presentation/screens/orbit_screen.dart` still hosts the
  shared `FeedNavigationBar` and reserves bottom space so Orbit chrome stays
  above it.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`,
  `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`,
  and `test/features/feed/presentation/screens/feed_wired_test.dart` already
  prove the in-app persistent-nav seam that Session `54` owned.
- `test/features/push/application/intro_notification_orbit_route_test.dart`
  now proves the app-root intro-notification Orbit contract:
  persistent nav visible, `Orbit` active, truthful Feed unread badge, Feed
  return restoring shell state, and close-while-on-Orbit restoring the prior
  tab.
- `test/integration/notification_deeplink_integration_test.dart` and
  `test/features/push/application/prepare_notification_open_use_case_test.dart`
  remain required direct suites for the notification-open boundary and passed
  in Session `55`.
- `Test-Flight-Improv/27-persistent-nav-bar-orbit.md` defines the product
  intent and accepted defer of `TC-27-C05`.
- `Test-Flight-Improv/14-regression-test-strategy.md` defines the
  direct-regression-first policy.
- `Test-Flight-Improv/test-gate-definitions.md` remains the source of truth for
  named gates and keeps `test/integration/notification_deeplink_integration_test.dart`
  in the optional/manual direct-suite bucket rather than a frozen named gate.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Execution verdict | Closure docs touched | Blocker note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `54` | In-app Orbit persistent-nav host and shell parity | `stale/already-covered` | `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-54-plan.md` | none | `skipped/historical` | `already-covered before this pipeline run` | none | none |
| `55` | Intro-notification Orbit entry parity and final Report 27 closure | `implementation-ready` | `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-55-plan.md` | `54` | `accepted` | `accepted after bounded planning/execution fallback` | live breakdown, `00`, `17` | none |

## Ordered session breakdown

### Session 54

- Title:
  `In-app Orbit persistent-nav host and shell parity`
- Session id:
  `54`
- Closure verdict:
  `historical/already-covered`
- Pipeline status in this run:
  `skipped`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-54-plan.md`
- Exact scope:
  - historical already-landed work that made the Feed-originated Orbit route
    reuse the shared nav host
  - truthful active-tab state and Feed unread-badge parity on the in-app route
  - safe Orbit bottom-chrome spacing above the persistent nav
  - Feed return behavior that leaves the shell truthful on the in-app route
- Why it is its own session:
  - it covered the Feed-owned modal seam, which is independent from the
    app-root intro-notification seam
  - it already had its own doc-scoped plan artifact and direct regression
    family
- Likely code-entry files:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
- Likely direct tests/regressions:
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
- Likely named gates:
  - none by default; the governing direct suites stay outside the frozen named
    gate lists
- Matrix/closure docs to update when done:
  - none now; only reopen this session if a real regression forces new work
- Dependency on earlier sessions:
  - none
- Reopen only on real regression:
  - Feed-originated Orbit stops showing the shared nav
  - Feed return from Orbit stops restoring shell truth
  - duplicate Orbit taps stop being route-level no-ops
  - Orbit bottom chrome or Feed unread-badge parity regresses

### Session 55

- Title:
  `Intro-notification Orbit entry parity and final Report 27 closure`
- Session id:
  `55`
- Closure verdict:
  `accepted`
- Execution verdict:
  `accepted after bounded planning/execution fallback`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-55-plan.md`
- Landed production files:
  - `lib/main.dart`
- Landed tests/docs:
  - `test/features/push/application/intro_notification_orbit_route_test.dart`
  - `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md`
  - `Test-Flight-Improv/17-roadmap-closure-audit.md`
- Exact scope:
  - update the intro-notification entry in `lib/main.dart` so Orbit opens with
    the same honest persistent-nav contract already used on the Feed-originated
    path
  - provide the unread-badge input that `OrbitWired` now expects for nav
    parity, instead of opening Orbit without a nav-capable
    `feedUnreadCountListenable`
  - keep `AppShellController` truthful when the user returns from
    notification-opened Orbit to Feed
  - add the missing regressions proving:
    - intro notification payloads route to Orbit
    - Orbit opens with the persistent nav visible and `Orbit` active
    - Feed unread-badge parity remains truthful on that entry path
    - returning to Feed leaves shell state truthful
  - refresh Report `27` closure state in this breakdown artifact, and update
    `Test-Flight-Improv/00-INDEX.md` plus
    `Test-Flight-Improv/17-roadmap-closure-audit.md` only if Session `55`
    actually closes the report at maintenance time
- Why it is its own session:
  - it is an app-root notification-routing seam, not the already-landed
    Feed-owned modal-route seam
  - it needs a different regression family: notification boundary/app-root
    proof plus a closure refresh for Report `27`
  - it can land independently without changing the already-green in-app path
- Likely code-entry files:
  - `lib/main.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart` only if a small
    constructor/threading adjustment is still needed
  - `lib/features/orbit/presentation/screens/orbit_screen.dart` only if a tiny
    nav-host detail is still missing on the notification path
  - `lib/core/notifications/notification_route_dispatch.dart` only if a small
    route-target wiring adjustment is proven necessary
- Likely direct tests/regressions:
  - `test/integration/notification_deeplink_integration_test.dart`
  - `test/core/notifications/notification_push_tap_navigate_test.dart`
  - `test/features/push/application/prepare_notification_open_use_case_test.dart`
  - one narrow app-root/widget regression proving intro-notification Orbit
    opens with the shared nav visible and `Orbit` active
  - targeted reruns of:
    - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
    - `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
    - `test/features/feed/presentation/screens/feed_wired_test.dart`
- Likely named gates:
  - `baseline`, because Session `55` changes app-root notification-open wiring
    in `lib/main.dart`
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md` only if Report `27` moves into closed
    maintenance-time meaning
  - `Test-Flight-Improv/17-roadmap-closure-audit.md` only if that same closure
    state changes
- Dependency on earlier sessions:
  - `54`
- Done bar for this session:
  - intro-notification Orbit entry shows the shared `FeedNavigationBar`
  - `Orbit` is active on entry and Feed unread-badge parity is truthful
  - returning to Feed leaves `AppShellController` truthful
  - direct notification/orbit/feed regressions land and pass
  - Report `27` closes without widening into Report `30`

## Why this was not fewer sessions

- One session would be unsafe because the already-landed Feed-owned route seam
  and the formerly open app-root notification seam had different owners, code
  entry points, regressions, and closure bars.
- Replanning Session `54` would create false churn against current repo state,
  where the in-app persistent-nav seam already exists and has passing direct
  evidence.

## Why this was not more sessions

- Splitting Session `55` into separate wiring, regression, and closure docs
  sessions would be bookkeeping without independent verification value.
- The app-root notification-entry parity work was one coherent seam, and it
  closed with its own direct regressions plus the bounded maintenance-doc
  refresh.

## Executed regression and gate contract

- Follow the direct-regression-first policy from
  `Test-Flight-Improv/14-regression-test-strategy.md`.
- Session `54` is already covered by landed direct suites and does not justify
  another planning slot.
- Session `55` ran and passed:
  - `flutter test test/features/push/application/intro_notification_orbit_route_test.dart`
  - `flutter test test/integration/notification_deeplink_integration_test.dart`
  - `flutter test test/features/push/application/prepare_notification_open_use_case_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/core/notifications/notification_push_tap_navigate_test.dart` was
  correctly left untouched because notification dispatch parsing/wiring did not
  change.
- Named-gate result:
  - `./scripts/run_test_gates.sh baseline` passed
  - `test/integration/notification_deeplink_integration_test.dart` remained a
    required direct suite even though `Test-Flight-Improv/test-gate-definitions.md`
    keeps it outside the frozen named gate lists

## Matrix update contract

- Session `55` owned the maintenance-time closure refresh for Report `27`.
- `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md` is now
  refreshed to reflect landed status, exact evidence, and accepted differences.
- `Test-Flight-Improv/00-INDEX.md` and
  `Test-Flight-Improv/17-roadmap-closure-audit.md` now reflect Report `27` as
  closed maintenance-time work.
- No new matrix doc should be invented for Report `27`; reuse these existing
  folder-level closure references.

## Historical downstream execution path used

### Session 54

- Do not send Session `54` through the pipeline now; it stays as a historical
  ledger row unless a real regression reopens it.
- If reopened by real repo evidence, it should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 55

- Planning-agent isolation was attempted first, but two bounded spawned-agent
  attempts failed to materialize the required plan doc; the controller then
  created `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-55-plan.md`
  directly from the breakdown plus current repo evidence.
- Execution/QA isolation was attempted next; when the spawned execution flow
  stalled without landing work, bounded controller-side recovery completed the
  code change, tests, and closure refresh instead of widening scope or
  restarting the session.
- No additional downstream work remains unless a real regression reopens Report
  `27`.

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- Session `54` remains historical already-landed work and is not reopened by
  default.
- `TC-27-C05` stays deferred to Report `30`.
- The current modal route architecture stays in place for Report `27`.
- `OrbitCloseButton` redesign remains out of scope.
- The app-root intro route keeps a snapshot unread-count listenable instead of
  introducing a broader root-owned live unread controller.

## Exact docs/files used as evidence

- `Test-Flight-Improv/27-persistent-nav-bar-orbit.md`
- `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-54-plan.md`
- `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-55-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/17-roadmap-closure-audit.md`
- `lib/main.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/features/push/application/intro_notification_orbit_route_test.dart`
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

## Why the closed breakdown is safe for maintenance

- The doc-scoped split is preserved: Session `54` stays historical and Session
  `55` stands as the accepted closure owner for the only app-root seam this
  report still had open.
- Both sessions keep their existing doc-scoped intended plan files for future
  historical/reference use.
- Reopen conditions, required direct suites, accepted differences, and closure
  doc ownership are explicit enough to preserve maintenance-time intent without
  reopening Report `30` scope by accident.
