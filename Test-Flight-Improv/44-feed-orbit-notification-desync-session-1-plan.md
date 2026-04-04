# Session 1 Plan - Feed/Orbit handled-notification sync and proof

## Final verdict

`implementation-ready`

Current repo evidence keeps Report `44` scoped to one missing shared-host sync
seam:

- `lib/features/feed/presentation/screens/feed_wired.dart` already treats a
  handled 1:1 notification as complete when the user collapses the Feed card
  or sends a successful inline reply from that card.
- `lib/features/orbit/presentation/screens/orbit_wired.dart` owns separate
  in-memory friend-row state and only refreshes that state from Orbit-owned
  route returns plus incoming/contact update streams.
- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
  does not emit a general read-mutation change event that mounted Orbit could
  observe automatically.
- Freshly opening Orbit later should already read the updated unread truth from
  repository state; the missing product contract is keeping an already-mounted
  Orbit host from contradicting Feed after Feed already handled the message.

This session should therefore land the smallest truthful Feed-to-mounted-Orbit
refresh contract, add direct cross-surface regressions, and close the report
without widening into notification-open routing or a broader unread-state
architecture rewrite.

## Final plan

### real scope

- Add a bounded external refresh signal from Feed into the already-mounted
  Orbit host so Orbit can reuse its current targeted contact refresh path when
  Feed handles a 1:1 notification.
- Trigger that shared-host refresh when Feed handles the contact by:
  - collapsing an unread/active 1:1 card
  - completing a successful inline reply from that 1:1 card
- Preserve current Feed unread-stack behavior from Report `40` and current
  Orbit targeted refresh behavior from Report `30`.
- Add direct regressions proving:
  - Feed handles notification while Orbit is already mounted -> Orbit row no
    longer shows that contact as unread
  - Feed handles notification before Orbit is first opened -> first Orbit render
    is already clear
- Refresh the Report `44` breakdown ledger and `Test-Flight-Improv/00-INDEX.md`
  after the code and proof land.

### closure bar

- A handled 1:1 notification on Feed no longer remains as stale unread state in
  mounted Orbit for the same contact.
- Both Feed handling paths in scope, collapse and successful inline reply, stay
  synchronized with Orbit.
- Opening Orbit later after Feed already handled the notification still renders
  the cleared state truthfully on first load.
- Existing Feed card behavior, Orbit incoming refresh behavior, and the shared
  Feed/Orbit host from Report `30` do not regress.
- Direct regressions for the escaped cross-surface sequence pass.
- `baseline` is rerun because shared Feed/Orbit production files under `lib/`
  changed.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/44-feed-orbit-notification-desync-session-breakdown.md`
  - `Test-Flight-Improv/44-feed-orbit-notification-desync.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/00-INDEX.md`
  - `Test-Flight-Improv/30-swipe-nav-feed-orbit-session-breakdown.md`
  - `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
- Current code and tests win over stale prose when they disagree.
- Verified live seam files:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/domain/models/feed_route_changes.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/orbit/presentation/widgets/friend_row.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- Feed correctly considers the notification handled after collapse or successful
  inline reply.
- Mounted Orbit keeps its own cached friend rows and can continue showing the
  same contact as unread because no Feed-originated refresh reaches Orbit.
- That leaves users with contradictory unread truth across two sides of the
  same shared Feed/Orbit host.

### files and repos to inspect next

- Production files:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
- Direct tests:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart` only if
    final execution needs a direct Orbit seam regression in addition to the
    shared-host Feed regressions
- Closure docs:
  - `Test-Flight-Improv/44-feed-orbit-notification-desync-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md`

### existing tests covering this area

- `test/features/feed/presentation/screens/feed_wired_test.dart` already proves
  Feed collapse behavior, Feed inline reply unread truth, and shared-host Orbit
  route-return refresh behavior.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` already
  proves targeted Orbit row refresh on incoming chat events and route returns.
- Missing today:
  - no direct shared-host regression that proves a Feed-originated handled
    notification clears the same mounted Orbit row
  - no direct regression that proves later first-open Orbit renders the handled
    state clearly after Feed already consumed the notification

### regression/tests to add first

- Add the shared-host Feed regression for:
  - mounted Orbit + Feed collapse clears the same Orbit row
  - mounted Orbit + Feed successful inline reply clears the same Orbit row
- Add the later-open regression for:
  - Feed successful inline reply before first Orbit open still yields a clear
    first Orbit render

### step-by-step implementation plan

1. Re-read the current Feed and Orbit host seam in the live dirty worktree and
   merge carefully with unrelated local edits.
2. Add the smallest external refresh contract that lets Feed send targeted
   `FeedRouteChanges` into mounted Orbit without changing the broader route
   result model.
3. Reuse Orbit's existing `_applyRouteChanges(...)` and `_refreshOrbitFriend(...)`
   path instead of introducing a second unread-refresh implementation.
4. Call the new mounted-Orbit refresh hook only after Feed actually handles the
   conversation as read on collapse or successful inline reply.
5. Add the direct shared-host regressions in `feed_wired_test.dart`.
6. Run the exact direct tests and the named gate listed below.
7. Refresh the Report `44` closure ledger and `00-INDEX.md`.

### risks and edge cases

- Do not accidentally widen into group unread sync, intro badge work, or
  app-root notification-open routing.
- The mounted-Orbit refresh hook must not trigger full Orbit reload churn when
  a single contact refresh is enough.
- Shared-host state must remain stable if Orbit was never mounted; later first
  open should still rely on repo truth without needing a live mounted listener.
- Preserve Report `40` Feed unread preview behavior and Report `30` shared-host
  navigation behavior.

### exact tests and gates to run

- Direct tests:
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh feed` only if direct evidence or touched files
    show the landed seam widened beyond the shared Feed/Orbit unread-host path

### known-failure interpretation

- There is no accepted exemption for the new shared-host regressions in this
  session.
- If mounted Orbit still shows the handled contact as unread after Feed cleared
  it, Session `1` is not done.
- A later failure in notification-open routing or inbox recovery discovered
  during this session should be recorded as separate scope unless the evidence
  proves this session directly caused it.

### done criteria

- Feed-originated handled 1:1 notification state no longer contradicts mounted
  Orbit for the same contact.
- Collapse and successful inline reply both keep Orbit synchronized.
- The later first-open Orbit path still renders cleared state truthfully.
- The direct regressions and `baseline` pass.
- The Report `44` breakdown and `00-INDEX.md` record the landed closure state.

### scope guard

- Do not redesign repository change streams or unread-count architecture.
- Do not reopen app-root notification-open routing or sibling tab-shell work.
- Do not widen into group-thread sync, intro badge behavior, or new product
  affordances.
