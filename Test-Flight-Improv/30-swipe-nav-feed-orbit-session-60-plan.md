# Session 60 Plan

## Final verdict

`implementation-ready`

Session `59` is now accepted in the live repo: Feed and Orbit switch through a
shared host, `OrbitWired` has the embedded exit/report seam, Feed scroll and
Orbit search state survive tab round trips, and the direct Session `59`
verification set plus `baseline` are green on `2026-03-30`. Report `30`
remains open only for the Session `60` gesture family: there is still no
screen-level horizontal drag host, no threshold or velocity completion, no
interactive finger-follow transition, and no explicit arbitration between the
new screen swipe and the existing Feed quote-swipe / Orbit row-swipe owners.

## Final plan

### real scope

- Add a bounded screen-level horizontal swipe contract on top of the landed
  shared Feed/Orbit host in
  `lib/features/feed/presentation/screens/feed_wired.dart`.
- Support Feed left-swipe -> Orbit and Orbit right-swipe -> Feed with
  threshold- and velocity-based completion plus snap-back before threshold.
- Make the transition horizontal and finger-following so the visual motion
  matches sibling top-level surfaces rather than a modal route.
- Dismiss Feed keyboard and active composer focus when swipe-away navigation
  leaves Feed.
- Preserve vertical-scroll priority for diagonal or primarily vertical drags.
- Preserve Feed quote-reply ownership and Orbit row-reveal / row-close
  ownership instead of replacing those local gestures.
- Run final Report `30` acceptance and update closure docs if the report
  actually closes.

### closure bar

- Feed left-swipe navigates to Orbit and Orbit right-swipe navigates to Feed.
- Sub-threshold drags snap back cleanly with no tab switch.
- High-velocity flicks can complete navigation even below the distance
  threshold.
- Drag motion is horizontal and finger-following rather than tap-only state
  swapping.
- Swiping away from Feed dismisses the keyboard and does not leave stale focus.
- Feed quote-swipe still wins on incoming message bubbles.
- Orbit row-close / row-reveal still wins where row-local ownership should
  take precedence.
- Feed scroll state and Orbit search/filter/list state remain preserved across
  swipe and tap round trips.
- Direct gesture suites plus `baseline` pass, and any closure docs reflect the
  final Report `30` state honestly.

### source of truth

- `Test-Flight-Improv/30-swipe-nav-feed-orbit-session-breakdown.md`
- `Test-Flight-Improv/30-swipe-nav-feed-orbit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- Current repo code and tests beat stale prose when they disagree.

### session classification

`implementation-ready`

### exact problem statement

- Session `59` removed the normal-path modal push/pop dependency, so Session
  `60` must build on the landed shared host rather than reintroducing routes.
- Current repo search on `2026-03-30` still finds no screen-level horizontal
  drag handlers in the Feed/Orbit host surfaces.
- `SwipeToQuoteBubble` already owns right-swipe on Feed message bubbles and
  `SwipeableFriendRow` already owns left-reveal plus right-close semantics on
  Orbit rows; the new host gesture must coexist with those local owners.
- Final closure still depends on proving threshold, velocity, snap-back,
  keyboard-dismiss, and preserved-state behavior under the swipe contract.

### files and repos to inspect next

Production files:

- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/feed/presentation/widgets/swipe_to_quote_bubble.dart`
- `lib/features/orbit/presentation/widgets/swipeable_friend_row.dart`
- `lib/features/feed/application/app_shell_controller.dart` only if a tiny host
  helper is required

Direct tests:

- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/feed/presentation/widgets/swipe_to_quote_bubble_test.dart`
- `test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart`
- `test/features/posts/phase1/app_shell_controller_test.dart`

### regression/tests to add first

- Add direct regressions for Feed -> Orbit threshold completion, snap-back
  before threshold, and velocity-triggered completion.
- Add direct regressions for Orbit -> Feed swipe completion and tap/swipe
  interop after the host transition lands.
- Add a regression proving Feed keyboard/focus clears on swipe-away.
- Add arbitration regressions proving Feed quote-swipe and Orbit row-close /
  row-reveal still win where intended.

### step-by-step implementation plan

1. Extend the shared host in `feed_wired.dart` with a drag-progress model that
   keeps both screens mounted and drives horizontal presentation.
2. Choose a host structure that can expose finger-following horizontal motion
   without breaking the already-landed state-preservation contract.
3. Keep Feed and Orbit tap navigation aligned with the swipe host so the shell
   truth remains `AppShellController.activeTab`.
4. Dismiss Feed focus at swipe-away start or completion, whichever preserves
   current composer behavior cleanly.
5. Gate screen-level gesture ownership so vertical scroll and local row/message
   gestures still win when they should.
6. Land the direct gesture regressions before relying on the broader gate.
7. Run the direct suites and `baseline`; run `feed` only if the final patch
   materially changes Feed card/composer/inline-reply behavior beyond hosting
   and gesture ownership.

### risks and edge cases

- Regressing the Session `59` preserved-state host while adding drag motion.
- Accidentally stealing right-swipe from `SwipeToQuoteBubble`.
- Accidentally stealing Orbit row-close behavior from
  `SwipeableFriendRow` when a row is already open.
- Causing diagonal drags to jitter horizontal navigation during ordinary
  vertical scrolling.
- Clearing Feed focus too late and leaving the nav hidden during or after a
  swipe.

### exact tests and gates to run

- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
- `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `flutter test test/features/feed/presentation/widgets/swipe_to_quote_bubble_test.dart`
- `flutter test test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart`
- `flutter test test/features/posts/phase1/app_shell_controller_test.dart`
- `./scripts/run_test_gates.sh baseline`
- Conditional: `./scripts/run_test_gates.sh feed` only if the final patch
  materially changes Feed card/composer/inline-reply behavior beyond hosting
  and gesture ownership

### known-failure interpretation

- Any failure that shows Feed or Orbit state being recreated is a regression
  against Session `59`, not an acceptable tradeoff for gesture work.
- Any failure where Feed quote-reply or Orbit row-close stops owning its local
  direction is a Session `60` blocker, not a polish follow-up.

### done criteria

- Feed left-swipe completes into Orbit by threshold or velocity and Orbit
  right-swipe completes back to Feed by threshold or velocity.
- Sub-threshold drags snap back cleanly with finger-following horizontal
  motion and no phantom tab switch.
- Swiping away from Feed clears keyboard/focus without regressing the existing
  inline composer behavior.
- Feed quote-swipe ownership and Orbit row-close / row-reveal ownership remain
  correct under the new host gesture contract.
- Feed scroll state and Orbit search/filter/list state stay preserved across
  swipe and tap round trips on top of the accepted Session `59` host.
- The direct Session `60` regressions and existing direct Feed / Orbit / local
  gesture suites pass.
- `./scripts/run_test_gates.sh baseline` passes, and `feed` runs only if the
  landed patch materially changes Feed card, composer, inline-reply, or
  feed-to-conversation behavior beyond hosting and gesture ownership.
- The rollout docs are refreshed honestly: this breakdown is updated with the
  execution result, and `Test-Flight-Improv/00-INDEX.md` is updated only if
  Report `30` actually closes.

### scope guard

- Do not reopen or redesign the accepted Session `59` shared-host migration
  unless a bounded fix is strictly required to land the Session `60` gesture
  contract safely.
- Do not reintroduce the normal-path modal `Navigator.push` / slide-up route as
  the Feed <-> Orbit navigation seam.
- Do not broaden into notification-originated Orbit routing parity, a broader
  app-root tab-shell rewrite, or unread/badge architecture work.
- Do not add swipe behavior beyond Feed left-swipe -> Orbit and Orbit
  right-swipe -> Feed.
- Do not replace `SwipeToQuoteBubble` or `SwipeableFriendRow` with a new
  gesture system when bounded precedence wiring is sufficient.

### accepted differences / intentionally out of scope

- Keep Session `59` as the accepted owner of shared-host state preservation,
  inline Orbit exit handling, and ordinary tap-based tab truth.
- Keep notification-opened Orbit routing and any broader standalone-route
  parity work out of scope except for a minimal compatibility fix if the
  Session `60` patch would otherwise break compilation or runtime behavior.
- Keep Orbit sub-tab swipe behavior, multi-touch gestures, and unrelated feed
  or conversation interaction redesign out of scope.
- Keep the established repo-truth correction that Feed quote-reply is not a
  same-direction conflict with Feed -> Orbit left-swipe; the real same-
  direction arbitration risk is Orbit row-close versus Orbit -> Feed return.

### dependency impact

- Session `60` is the final implementation slice for Report `30`.
- If Session `60` lands and closure clears, Report `30` can close.
- If Session `60` remains blocked, Report `30` stays open while Session `59`
  remains accepted and should reopen only on a real regression.
