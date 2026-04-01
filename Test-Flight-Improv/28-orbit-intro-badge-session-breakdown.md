# 28 - Orbit Intro Badge Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/28-orbit-intro-badge-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/28-orbit-intro-badge.md`
- Recovery pass type:
  `doc-scoped recomposition after retryable pipeline failure`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `1`

## Overall closure bar

Report `28` is closed only when the current shared bottom-nav contract tells
the truth about pending introductions everywhere that already hosts
`FeedNavigationBar`, without inventing a second unread system:

- the `Orbit` button can render pending-intro badge truth independently from
  the existing Feed unread badge on the Feed surface and on the already-open
  persistent-nav Orbit host from Report `27`
- initial badge state is expiry-aware on cold load and app reopen, not just on
  live intro delivery
- incoming intro receipt, remote intro status changes, and returning from
  Orbit after local `accept` or `pass` cannot leave the Feed-owned Orbit badge
  stale
- `alreadyConnected` and expired intros do not keep the badge alive, normal
  Orbit navigation still works, and the existing intro notification continues
  to fire
- permanent direct regressions prove shared-nav badge coexistence, intro-count
  truth, route-return freshness, and unchanged navigation behavior

## Source of truth

Current code and tests beat stale proposal assumptions where they differ. This
recovery decomposition is governed by:

- `Test-Flight-Improv/28-orbit-intro-badge.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md`
- `Test-Flight-Improv/session-35-plan.md`

Current repo seams that govern the split:

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

Direct tests and closure evidence that matter now:

- `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
- `test/features/feed/presentation/widgets/nav_bar_button_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `test/features/push/application/intro_notification_orbit_route_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`

Repo-truth differences that shape this split:

- Report `27` is already the current shared-nav host contract in this working
  tree: `FeedWired` passes `_totalUnreadCountNotifier` into `OrbitWired`, and
  `OrbitWired` / `OrbitScreen` now render the shared `FeedNavigationBar` when
  the persistent-nav host is active
- `FeedNavigationBar` production code still exposes only `feedBadgeCount`, but
  `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
  already contains an in-progress direct expectation for `orbitBadgeCount`;
  downstream execution must merge with that live tree instead of assuming a
  clean untouched baseline
- `FeedWired` still leaves `introReceivedStream` as a no-op and has no
  pending-intro badge state or route-return refresh hook today
- `FeedRouteChanges` still carries only contact/group refreshes
- `OrbitWired` already owns expiry-aware intro loading and `_introsCount` for
  the Orbit surface, but that truth is not threaded back into the shared nav
  contract or returned to Feed after local intro actions
- `countPendingIntroductions()` already excludes `alreadyConnected` rows, while
  expiry only becomes truthful after `expireOldIntroductions(...)` runs
- Report `25` delete-intro UI is still not landed; the delete-path case in the
  proposal remains a future reuse obligation rather than a driver for a second
  session now
- the previous blocked pipeline attempt landed no Report `28` production or
  regression code; current working-tree differences are separate live repo
  state, not accepted closure evidence

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Initial status | Recovery context | Prior pipeline verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `56` | Shared Orbit intro badge contract and freshness wiring | `implementation-ready` | `Test-Flight-Improv/28-orbit-intro-badge-session-56-plan.md` | none | `pending` | Retryable recovery after prior `spawn_or_tool_failure`; keep the same doc-scoped Session `56` plan path because no landed Report `28` code forces a re-split | `blocked / still_open` |

## Recovery context carried forward

- `2026-03-30`: the previous pipeline attempt ended `blocked` / `still_open`
  for retryable reason `spawn_or_tool_failure`
- `2026-03-30`: no Report `28` production or regression changes landed during
  that failed pipeline attempt
- `2026-03-30`: this decomposition recomposes against the latest repo state
  and preserves the existing doc-scoped intended plan path
  `Test-Flight-Improv/28-orbit-intro-badge-session-56-plan.md`

## Ordered session breakdown

### Session 56

- Title:
  `Shared Orbit intro badge contract and freshness wiring`
- Session id:
  `56`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/28-orbit-intro-badge-session-56-plan.md`
- Exact scope:
  - extend the shared `FeedNavigationBar` contract so Feed unread and Orbit
    pending-intro badge state can coexist without mixing counts
  - thread the new Orbit badge input through both shared-nav hosts:
    `FeedScreen` and the current persistent-nav `OrbitScreen`
  - add Feed-owned pending-intro badge state in `FeedWired`, including
    expiry-aware initial load after identity is known
  - refresh the Feed-owned badge from live intro receipt and remote intro
    status changes that alter pending-intro truth
  - add one bounded intro-refresh signal to `FeedRouteChanges` or an
    equivalent narrow route result so local Orbit `accept` or `pass` cannot
    leave the Feed badge stale on return
  - keep `OrbitWired` as the owner of Orbit-surface intro count truth, but
    thread that truth into the shared nav contract instead of creating a new
    root-owned controller
  - preserve current intro notification behavior, current Report `27`
    persistent-nav behavior, and existing Feed/Orbit tap semantics
  - merge with the live in-progress `orbitBadgeCount` test expectation rather
    than reverting it
- Why it is its own session:
  - one cohesive user-visible slice on a single shared nav component and its
    two current hosts
  - one direct regression family spanning Feed, persistent-nav Orbit, intro
    listener follow-up wiring, and route-return freshness
  - it can land and be verified now without waiting for unimplemented Report
    `25` delete UI
- Likely code-entry files:
  - `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/domain/models/feed_route_changes.dart`
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/feed/presentation/widgets/nav_bar_button.dart` only if badge
    pass-through semantics or accessibility text need a narrow adjustment
  - `lib/features/introduction/application/expire_old_introductions_use_case.dart`
    only as a reused dependency, not a redesign target
- Likely direct tests/regressions:
  - `flutter test test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
  - `flutter test test/features/feed/presentation/widgets/nav_bar_button_test.dart`
    only if badge rendering semantics change beyond pass-through wiring
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `flutter test test/features/introduction/application/introduction_listener_test.dart`
  - `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart`
  - `flutter test test/features/introduction/regression/introduction_regression_test.dart`
  - conditional:
    `flutter test test/features/push/application/intro_notification_orbit_route_test.dart`
    only if implementation evidence forces a notification-opened host-contract
    adjustment rather than staying inside the current shared-nav surfaces
- Likely named gates:
  - no frozen named gate owns this seam directly
  - run the direct intro/orbit/feed maintenance suite above
  - run `./scripts/run_test_gates.sh baseline` as the companion gate because
    this is shared top-level surface wiring
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/28-orbit-intro-badge-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md` only if Session `56` actually closes
    Report `28` into stable maintenance-time meaning
- Dependency on earlier sessions:
  - none

## Why This Is Not Fewer Sessions

Zero sessions would leave the current repo in a misleading state: the shared
nav component would still lack Orbit intro badge truth, Feed would still miss
expiry-aware initial/live intro truth, and returning from Orbit after local
intro actions could still leave the Feed badge stale. Those concerns must land
together to produce one honest verified badge behavior.

## Why This Is Not More Sessions

Splitting shared-nav widget changes, Feed-side intro truth, persistent-nav
Orbit parity, and route-return freshness into multiple sessions would mostly
create bookkeeping and half-states:

- the badge contract is shared across Feed and the already-present persistent
  Orbit host, so splitting the two surfaces would duplicate the same
  verification value
- a separate app-root notification session is unnecessary unless implementation
  proves `lib/main.dart` or the notification-open contract must change
- a separate delete-path session would be speculative today because Report `25`
  is still not landed in the current repo
- a separate closure-only session would be artificial because there is only one
  implementation slice and its closure update belongs in the same verified
  landing

## Regression And Gate Contract

- `Test-Flight-Improv/14-regression-test-strategy.md` applies here as a
  direct-regression-first seam, not as a reason to invent a new named gate
- `Test-Flight-Improv/test-gate-definitions.md` says intro/orbit/feed
  follow-up work stays in direct suites plus `baseline`, not in a frozen named
  intro gate
- minimum direct proof for Session `56`:
  - shared nav renders independent Feed and Orbit badge truth without mixing
    counts
  - cold load and app reopen are expiry-aware before publishing badge truth
  - intro receipt and remote status changes refresh the Feed badge without
    visiting Orbit
  - local Orbit `accept` or `pass` cannot leave Feed stale on return
  - persistent-nav Orbit still renders truthful badge state and active-tab
    behavior
  - Orbit tap/navigation and intro notification behavior remain unchanged
- companion gate:
  - `./scripts/run_test_gates.sh baseline`

## Matrix Update Contract

- Do not create a new matrix doc for Report `28`
- The live closure-owner doc for this rollout is
  `Test-Flight-Improv/28-orbit-intro-badge-session-breakdown.md`
- Session `56` owns the maintenance-time update of this breakdown artifact
- Update `Test-Flight-Improv/00-INDEX.md` only if Session `56` actually closes
  Report `28`; otherwise keep closure state local to the plan/execution
  artifacts

## Intended downstream execution path

- Session `56` should next go through, in order:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`

## Recovery pass outcome

- `2026-03-30`: Session `56` completed during this doc-scoped recovery pass
  and stayed inside the one-session scope defined by this breakdown
- planning recovery:
  - the refreshed plan artifact at
    `Test-Flight-Improv/28-orbit-intro-badge-session-56-plan.md` was reused as
    the source of truth after a retryable spawned-planning stall; no re-split
    or renumbering was needed
- execution / QA recovery:
  - repeated retryable spawn/tool failures in the spawned execution leg were
    recovered locally against the current dirty repo state so the report would
    not remain falsely open for an operational reason
  - the accepted implementation landed only in the Report `28` target seam:
    shared-nav badge coexistence, Feed-owned expiry-aware intro badge refresh,
    bounded route-return freshness, and persistent-nav Orbit badge parity
- direct proof run on `2026-03-30`:
  - `flutter test test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `flutter test test/features/introduction/application/introduction_listener_test.dart`
  - `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart`
  - `flutter test test/features/introduction/regression/introduction_regression_test.dart`
  - `flutter test test/features/push/application/intro_notification_orbit_route_test.dart`
  - `./scripts/run_test_gates.sh baseline`
- operational note:
  - `baseline` required forcing the device selection to `macOS` because the
    script otherwise paused on an interactive chooser; that was operational
    friction, not a product or regression blocker

## Final program acceptance verdict

- `closed`
- Report `28` is now closed: Session `56` landed the shared Orbit intro badge
  contract, Feed-owned expiry-aware/live/route-return refresh wiring, and the
  persistent-nav Orbit badge parity required by the overall closure bar without
  widening into app-root badge architecture or new product scope

## Structural blockers remaining

- none
- retryable operational history carried forward for context only:
  - the prior pipeline attempt ended `blocked` / `still_open` on
    `spawn_or_tool_failure` before any accepted Session `56` evidence landed
  - the recovery pass also had retryable spawned-step stalls plus an
    interactive `baseline` device prompt, but those were spent and resolved
    inside the bounded recovery stack and do not keep the report open

## Accepted Differences Intentionally Left Unchanged

- reuse the existing numeric `badgeCount` visual contract by default; do not
  force a separate dot-only visual system unless later product evidence
  requires it
- Report `25` delete-path parity is documented as a future reuse obligation,
  not as a current session, because the delete-intro UI does not exist in the
  current repo
- do not introduce a new root-owned unread/intro controller for this report
- do not reopen Report `27` architecture or widen into Report `30` swipe-host
  scope

## Exact docs/files used as evidence

- Docs:
  - `Test-Flight-Improv/28-orbit-intro-badge.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/00-INDEX.md`
  - `Test-Flight-Improv/27-persistent-nav-bar-orbit-session-breakdown.md`
  - `Test-Flight-Improv/session-35-plan.md`
- Live code/tests:
  - `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/domain/models/feed_route_changes.dart`
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/introduction/application/introduction_listener.dart`
  - `lib/features/introduction/application/expire_old_introductions_use_case.dart`
  - `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `test/features/push/application/intro_notification_orbit_route_test.dart`
  - `test/features/introduction/regression/introduction_regression_test.dart`

## Why the breakdown is now safe as the closure reference

- Session `56` stayed at the minimum safe size: one cohesive shared-nav /
  intro-freshness seam with no follow-on closure session required
- the accepted maintenance-time proof is explicit and repeatable:
  `feed_navigation_bar_test.dart`, `feed_wired_test.dart`,
  `orbit_wired_test.dart`, `orbit_intros_wiring_test.dart`, the intro
  listener / handling / regression suites, the notification-open Orbit route
  test, and `baseline`
- the retryable `spawn_or_tool_failure` history is preserved so future retries
  are not mistaken for product gaps, but it is no longer an active blocker
- later work should reopen Report `28` only on real regressions in shared
  Orbit intro badge truth, not to invent a second unread system or broaden the
  navigation architecture
