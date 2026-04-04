# Session 1 Plan - Feed inline-reply viewport reorientation and proof

## Final verdict

`implementation-ready`

Current repo evidence keeps Report `45` scoped to one Feed-owned UI continuity
seam:

- `lib/features/feed/presentation/screens/feed_screen.dart` owns the only Feed
  `CustomScrollView`, currently keyed for raw scroll storage with
  `PageStorageKey('feed-scroll')` and not for per-card viewport anchoring.
- The same file already renders cards with stable `ValueKey(item.id)` identity
  plus `findChildIndexCallback`, so a same-card reorientation fix can stay local
  to Feed's sliver/view layer instead of rewriting feed ordering.
- `lib/features/feed/presentation/screens/feed_wired.dart` owns the successful
  inline-reply mutation that creates `SessionReply`, marks the conversation read,
  and refreshes the contact item, which is exactly when the card can collapse
  and move.
- Existing tests already pin adjacent behavior, including Feed/Orbit round-trip
  scroll storage and post-reply unread truth, but no direct regression proves
  `visible card -> successful inline reply -> card repositions -> viewport
  follows the same card`.

This session should therefore land the smallest truthful viewport-follow
contract between `FeedWired` and `FeedScreen`, add the missing direct
regressions, and close the report without widening into unread-model redesign,
notification-routing, or broader host-navigation work.

## Final plan

### real scope

- Add a bounded Feed-owned mechanism that re-orients the current scroll view to
  the same 1:1 card after a successful inline reply causes that card to
  collapse, resize, or reorder.
- Thread the minimum state needed from `FeedWired` into `FeedScreen` so the
  screen can identify which contact card to follow after the post-send refresh.
- Preserve current successful inline reply behavior:
  - optimistic `SessionReply`
  - card collapse or replied presentation
  - local read-marking
  - Feed unread-preview truth already closed by Report `40`
  - Feed/Orbit handled-notification truth already closed by Report `44`
- Add the missing direct regression for the escaped user flow, plus one bounded
  repeated-reply proof if the same seam owns it.
- Refresh the Report `45` breakdown artifact and `Test-Flight-Improv/00-INDEX.md`
  after the code and proof land.

### closure bar

- After a successful inline reply from a visible 1:1 Feed card, the viewport no
  longer leaves the user centered on the stale old scroll position while that
  same card moved elsewhere in the list.
- The same card remains visibly oriented and immediately usable for follow-up
  replies.
- Existing post-reply collapse/replied-state behavior still works.
- Existing Feed unread-preview truth after inline reply still works.
- Existing Feed/Orbit round-trip scroll preservation still works for unrelated
  navigation.
- Required direct tests and named gates pass.
- `baseline` is rerun because Flutter production files under `lib/` changed.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md`
  - `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/00-INDEX.md`
  - `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
  - `Test-Flight-Improv/44-feed-orbit-notification-desync-session-breakdown.md`
- Current code and tests win over stale prose when they disagree.
- Verified live seam files:
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/inline_reply_input.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- Feed currently preserves a raw scroll offset for the whole surface, not a
  viewport anchor tied to the active card.
- A successful inline reply can change the same thread from unread or active
  into replied state and move it across the Feed's above-divider and below-divider
  sort boundary.
- Because no same-card follow signal exists today, the user can remain looking
  at stale surrounding content after send success even though the active card
  moved and is still the next interaction target.
- Existing tests prove nearby behaviors, but no direct regression proves the
  escaped user-visible continuity contract or the repeated-reply drift case.

### files and repos to inspect next

- Production files:
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
- Conditional production helpers:
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/inline_reply_input.dart`
    only if the final seam needs a narrow card-level or post-focus callback
- Direct tests:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
    if the landed fix introduces explicit screen-level controller or visibility
    behavior that should be pinned independently
- Conditional higher-layer suites:
  - `test/features/feed/integration/expanded_collapsed_card_test.dart`
  - `test/features/feed/integration/feed_card_flow_test.dart`
    only if the final implementation changes visible card transition structure
    rather than only screen-level viewport ownership
- Closure docs:
  - `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md`

### existing tests covering this area

- `test/features/feed/presentation/screens/feed_screen_test.dart`
  already proves Feed renders through `CustomScrollView` rather than an eager
  scroll view.
- `test/features/feed/presentation/screens/feed_wired_test.dart`
  already proves Feed scroll position survives an inline Feed/Orbit round trip.
- `test/features/feed/presentation/screens/feed_wired_test.dart`
  already proves successful inline reply collapses into replied state and
  older unread rows do not resurface after the later incoming sequence covered
  by Report `40`.
- Missing today:
  - no direct regression that proves a visible mid-scroll Feed card remains
    visible after successful inline reply reorders it
  - no direct regression that proves repeated successful inline replies from the
    same card do not let the viewport drift away

### regression/tests to add first

- Add a primary widget regression in
  `test/features/feed/presentation/screens/feed_wired_test.dart` that:
  1. seeds a long enough Feed list to require mid-scroll interaction;
  2. scrolls until the target contact card is visible but not pinned at the top;
  3. performs a successful inline reply from that card;
  4. proves the post-send viewport still contains that same contact card after
     the card collapses or reorders.
- Add a second bounded proof in the same suite for a consecutive successful
  inline reply if the first regression does not already prove the repeat case.
- Keep this regression in `feed_wired_test.dart` first because the failing seam
  spans screen scroll ownership plus the real inline-reply success path.
- Do not start with a new integration test unless the widget-level regression
  cannot honestly prove the user-visible continuity contract.

### step-by-step implementation plan

1. Add the failing `feed_wired_test.dart` regression for
   `visible card mid-scroll -> successful inline reply -> same card remains
   visible after movement`.
2. Decide the narrowest coherent seam for viewport follow:
   - likely `FeedWired` records a one-shot follow target after successful
     inline reply, and
   - `FeedScreen` uses stable keyed card identity plus a scroll controller or
     `Scrollable.ensureVisible` style hook to re-orient to that card after the
     refreshed list settles.
3. Land the full caller/callee seam coherently in one pass:
   - screen/controller ownership in `feed_screen.dart`
   - follow-target or trigger ownership in `feed_wired.dart`
   - direct tests that prove the seam
4. Preserve existing PageStorage scroll behavior for unrelated navigation; stop
   if the new regression passes and the existing Feed scroll round-trip test
   remains green.
5. Add the bounded repeated-reply regression only if the first landing does not
   already prove the repeat case honestly.
6. Run the exact direct tests and named gates below.
7. Refresh the Report `45` breakdown ledger and `00-INDEX.md`.

### risks and edge cases

- Breaking the existing Feed/Orbit round-trip scroll storage while trying to add
  same-card reorientation.
- Triggering scroll jumps for unrelated feed refreshes instead of only for the
  successful inline-reply seam in scope.
- Racing against layout or focus changes so the scroll happens before the card's
  new post-reply position exists.
- Reopening Report `40` behavior by accidentally changing post-reply unread
  projection instead of only viewport continuity.
- Losing follow-up reply usability if the card stays technically visible but is
  pushed to an unusable edge of the viewport.

### exact tests and gates to run

- Direct tests:
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
    if `FeedScreen` gains explicit new controller/visibility behavior
- Conditional direct suites if touched:
  - `flutter test test/features/feed/integration/expanded_collapsed_card_test.dart`
  - `flutter test test/features/feed/integration/feed_card_flow_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh feed`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
- Do not run `./scripts/run_test_gates.sh transport` unless the final diff
  reaches startup, reconnect, notification-open, or other transport-owned seams,
  which this plan treats as out of scope.

### known-failure interpretation

- There is no accepted exemption for the new viewport-follow regression in this
  session.
- If the new regression still shows the target card leaving the viewport after
  send success, Session `1` is not done.
- Existing Feed scroll round-trip or post-reply unread-truth regressions caused
  by this diff are blocking because they are part of the closure bar.
- If a named gate fails in an unrelated file, do not wave it off generically;
  name the exact file/test and why it is pre-existing and outside this session's
  seam.

### done criteria

- The new direct viewport-follow regression exists and passes.
- Successful inline reply keeps the same Feed card visibly oriented after the
  card moves.
- Existing adjacent Feed inline-reply behaviors remain green.
- Existing Feed/Orbit round-trip scroll preservation remains green.
- Required direct suites and named gates pass, or any unrelated pre-existing
  failure is documented explicitly with evidence.
- The Report `45` breakdown artifact and `00-INDEX.md` reflect the landed
  closure state.

### scope guard

- Do not redesign Feed ordering, unread-model semantics, or card collapse rules.
- Do not reopen Report `40` unread-preview work or Report `44` Feed/Orbit
  handled-notification synchronization work unless concrete new evidence proves a
  shared regression.
- Do not build a generic scroll-restoration framework for every Feed mutation.
- Do not widen into group-thread parity, full conversation-screen behavior, or
  app-shell navigation work.
- Do not edit frozen gate definitions for this session.

### accepted differences / intentionally out of scope

- Exact final alignment can remain implementation-defined as long as the same
  card is clearly kept visible and usable for immediate follow-up interaction.
- The fix does not need to preserve the card's exact prior on-screen pixel
  position.
- Group-card behavior remains out of scope.
- Full conversation screen viewport behavior remains out of scope.

### dependency impact

- This plan unblocks the execution step for Session `1` only.
- No later session in Report `45` depends on it because the breakdown contains a
  single runnable implementation session.
- If execution proves the seam actually belongs to a broader unread-projection
  or host-navigation contract, stop and refresh the breakdown rather than
  widening this session silently.

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- whether a dedicated `feed_screen_test.dart` regression is needed beyond the
  `feed_wired_test.dart` flow can wait until the landed code seam is clear
- whether the repeated-reply proof needs its own standalone test can wait until
  the first regression exists

## Accepted differences intentionally left unchanged

- exact viewport alignment after reply
- group-thread parity
- full conversation-screen parity
- broader Feed/Orbit host-navigation behavior

## Exact docs/files used as evidence

- `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md`
- `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
- `Test-Flight-Improv/44-feed-orbit-notification-desync-session-breakdown.md`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/inline_reply_input.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

## Why the plan is safe to implement now

- The plan targets one coherent seam: Feed viewport continuity after successful
  inline reply.
- The regression-first contract is explicit and tied to the exact escaped user
  flow.
- The direct test and named gate contract is explicit.
- The scope guard keeps the execution step from drifting into adjacent reports
  or architecture work already closed elsewhere.
