# 36 - Long-Press Selected Message Visibility - Session 2 Plan

## Real Scope

- Carry the landed selected-message overlay host across the feed thread-card
  surfaces that already open `MessageContextOverlay`.
- Preserve parity across the feed card paths that route long-press through the
  collapsed and expanded message-preview tree.
- Add or update the direct feed regressions that prove the selected feed
  message remains visibly present and anchored while the overlay is open.
- Finish the report `36` acceptance and closure update once feed parity is
  verified.

## Closure Bar

Session `2` is good enough when feed thread cards that already expose the
shared long-press overlay keep the selected message visibly present between the
reaction row and menu, collapsed and expanded feed routes still identify the
correct message, existing reply/copy/edit/delete/reaction behavior remains
intact, and the report `36` breakdown artifact can honestly close with no broad
1:1 reliability reopen.

## Source Of Truth

Primary docs:

- `Test-Flight-Improv/36-long-press-selected-message-visibility-session-breakdown.md`
- `Test-Flight-Improv/36-long-press-selected-message-visibility.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current code and tests beat stale prose on disagreement. Current repo evidence
used for this plan:

- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `lib/features/feed/presentation/widgets/message_bubble.dart`
- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
- `test/features/feed/integration/feed_card_flow_test.dart`
- `test/features/feed/integration/expanded_collapsed_card_test.dart`

## Session Classification

- `implementation-ready`

## Exact Problem Statement

Session `1` landed the shared overlay host and direct-conversation adoption, but
feed still opens `MessageContextOverlay` with only `anchorRect` plus action
callbacks. The feed message-preview tree already long-presses into the shared
overlay through `ScrollableMessagePreview` and `FeedScreen`, yet it does not
pass the selected `MessageBubble` presentation into the overlay. Session `2`
must adopt the landed host on the feed surfaces, prove collapsed and expanded
card parity, and then close the report without drifting into feed-originated
send/persistence changes.

## Files And Repos To Inspect Next

Production files:

- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `lib/features/feed/presentation/widgets/message_bubble.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`

Direct tests:

- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
- `test/features/feed/integration/feed_card_flow_test.dart`
- `test/features/feed/integration/expanded_collapsed_card_test.dart`

## Existing Tests Covering This Area

- `feed_screen_test.dart` already covers long-press reply/edit/copy/delete
  behavior, but not selected-message visibility in the overlay state.
- `feed_wired_test.dart` already covers feed-originated reply/edit/delete wiring
  and should keep those flows stable after the presentation change.
- `scrollable_message_preview_test.dart` already proves long-press selects the
  correct `ThreadMessage` through the preview routing seam.
- `feed_card_flow_test.dart` and `expanded_collapsed_card_test.dart` already
  pin feed card state transitions and should stay green when the overlay
  adoption lands.

## Regression/Tests To Add First

- Add direct feed-screen assertions that the selected feed message is rendered
  inside `MessageContextOverlay` instead of remaining only behind the backdrop.
- Add direct parity assertions for both collapsed and expanded feed paths so the
  same selected message remains visually anchored around the reaction row and
  menu.
- Preserve or extend existing action assertions so reply/copy/edit/delete and
  emoji reaction behavior remain intact after the feed adoption change.

## Step-By-Step Implementation Plan

1. Inspect the current feed long-press seam from
   `scrollable_message_preview.dart` through `feed_screen.dart` to identify the
   smallest way to rebuild the selected `MessageBubble` for the shared overlay.
2. Add the direct feed regressions first for selected-message visibility and
   anchored ordering in the overlay state, covering collapsed and expanded card
   routes as needed.
3. Update the feed overlay call site so it passes an inert selected
   `MessageBubble` into `MessageContextOverlay` using the already-landed shared
   host contract from Session `1`.
4. Verify that the feed card/preview routing tree still targets the correct
   message in both collapsed and expanded states without reopening quote/send
   semantics.
5. Run the direct feed suites, then run `./scripts/run_test_gates.sh baseline`
   and `./scripts/run_test_gates.sh feed`.
6. If feed adoption forces changes to feed-originated send/reply persistence or
   other shared 1:1 correctness paths, stop and either run the companion
   `1to1` gate or return `blocked` rather than silently widening Session `2`.
7. After passing tests/gates, update the breakdown artifact to close report
   `36` honestly at the doc level.

## Risks And Edge Cases

- Feed long-press routing spans `FeedScreen`, `ScrollableMessagePreview`, and
  the collapsed/expanded card bodies, so the selected-message host must not
  only work on one card mode.
- Feed bubbles have different width/height behavior than conversation
  `LetterCard`s, especially for compact inline text, media, and quoted content.
- Some feed actions can bridge into 1:1 reply/edit semantics, so Session `2`
  must avoid changing those payload paths unless a real regression forces it.
- The working tree already contains unrelated and adjacent uncommitted changes;
  execution must preserve user changes and avoid reverting repo-local edits not
  required for this session.

## Exact Tests And Gates To Run

Direct tests:

- `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- `flutter test test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
- `flutter test test/features/feed/integration/feed_card_flow_test.dart`
- `flutter test test/features/feed/integration/expanded_collapsed_card_test.dart`

Named gates:

- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh feed`

Conditional named gate:

- `./scripts/run_test_gates.sh 1to1` only if the implementation widens into
  feed-originated quote/send semantics or other shared 1:1 correctness paths.

## Known-Failure Interpretation

- Treat failures in new selected-message visibility or anchored-overlay
  assertions as Session `2` regressions until fixed.
- Treat failures in unchanged feed card state transitions as new regressions if
  they reproduce after the overlay adoption patch.
- Do not classify the lack of a `1to1` run as a gap unless the implementation
  actually touches shared feed-originated send/reply correctness rather than
  staying on presentation/routing parity.

## Done Criteria

- Feed long-press overlay states visibly include the selected `MessageBubble`
  while open.
- Collapsed and expanded feed routes still identify the correct selected
  message.
- Existing feed reply/copy/edit/delete/reaction actions still behave under
  their current rules.
- The direct feed suites, `baseline`, and `feed` gates pass, and `1to1` is run
  only if scope widens into shared messaging correctness.
- The breakdown artifact is updated with a truthful final report verdict for
  `36`.

## Scope Guard

- Do not reopen the direct-conversation work accepted in Session `1` unless a
  real shared-overlay regression appears.
- Do not change feed-originated send persistence, retry, or listener behavior
  unless the feed adoption work proves a real 1:1 correctness bug.
- Do not redesign feed card architecture if a narrower preview-to-overlay
  adoption solves the problem.
- Do not add new menu actions or change the availability rules for existing
  actions.

## Accepted Differences / Intentionally Out Of Scope

- Group-thread long-press behavior remains out of scope.
- Wider 1:1 reliability, transport, or persistence work remains out of scope
  unless feed adoption proves a concrete regression.
- Animation tuning beyond visible anchored continuity remains secondary unless
  required to keep the selected feed message identifiable.

## Dependency Impact

- Session `2` is the final runnable session for report `36`; its closure update
  determines the program-level verdict.
- If Session `2` ends `blocked`, the report must remain `still_open` in the
  breakdown artifact rather than being partially closed on Session `1` alone.
