# 36 - Long-Press Selected Message Visibility - Session 1 Plan

## Real Scope

- Extend the shared long-press overlay contract so the selected direct-message
  content remains visibly present while the overlay is open.
- Keep the reaction row and context menu visually anchored to that same
  selected message on the conversation surface.
- Add or update the direct shared-overlay and conversation regressions that
  prove visible target-message continuity, edge clamping, and preserved action
  behavior.
- Do not take feed-card parity or final report-wide closure in this session.

## Closure Bar

Session `1` is good enough when direct conversations show the selected message
as the focal element of the long-press overlay state, the reaction row and menu
stay visually anchored around it, top/bottom viewport clamping still keeps the
stack usable, and existing reply/copy/edit/delete/reaction/backdrop-dismiss
behavior still passes its current rules.

## Source Of Truth

Primary docs:

- `Test-Flight-Improv/36-long-press-selected-message-visibility-session-breakdown.md`
- `Test-Flight-Improv/36-long-press-selected-message-visibility.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current code and tests beat stale prose on disagreement. Current repo evidence
used for this plan:

- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`

## Session Classification

- `implementation-ready`

## Exact Problem Statement

The shared `MessageContextOverlay` currently renders the blurred backdrop, the
inline `ReactionBar`, and the menu card, but it does not render the selected
message itself. The direct conversation screen opens the overlay from an
`anchorRect`, so the action stack is positioned near the pressed message, but
the user still loses the target-message focal element once the backdrop blur is
applied. Session `1` must close that UI gap on the direct conversation surface
without widening into feed parity, message business rules, or shared 1:1
send/persist correctness changes.

## Files And Repos To Inspect Next

Production files:

- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/widgets/reaction_bar.dart`

Direct tests:

- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`

## Existing Tests Covering This Area

- `message_context_overlay_test.dart` already covers action rendering, action
  taps, and backdrop dismiss, but not selected-message visibility or anchored
  continuity.
- `conversation_screen_test.dart` already covers conversation rendering and
  overlay-related behavior, but not the selected-message host inside the
  overlay state.
- `conversation_wired_test.dart` already exercises reply/edit/delete overlay
  flows from the wired conversation surface and should continue to pin those
  user-visible actions after the UI presentation change.

## Regression/Tests To Add First

- Add direct widget/screen assertions that the selected message remains
  rendered as part of the overlay presentation instead of existing only behind
  the blurred backdrop.
- Add direct positioning/clamping assertions for conversation-surface overlay
  states near the top and bottom of the viewport so the selected message,
  reaction row, and menu remain on-screen and associated.
- Preserve or extend existing action assertions so reply/copy/edit/delete,
  emoji reaction, and backdrop dismiss behavior remain intact after the shared
  overlay contract changes.

## Step-By-Step Implementation Plan

1. Inspect the current direct-message long-press seam in
   `conversation_screen.dart`, `letter_card.dart`, and
   `message_context_overlay.dart` to choose the smallest way to pass the
   selected message presentation into the shared overlay without widening the
   public contract more than necessary.
2. Add the direct regression coverage first in the overlay and conversation
   screen/widget tests for selected-message visibility and viewport clamping.
3. Implement the shared overlay host so it can render the selected message as
   part of the long-press stack, while keeping the reaction row and action menu
   anchored around the same target.
4. Update the conversation screen call site so the pressed direct-message card
   provides the selected-message content and any positioning details the shared
   overlay needs.
5. Re-run the direct conversation suites, then run the required `baseline`
   gate because production Flutter UI code changed.
6. Stop after direct-conversation acceptance. If the cleanest fix clearly
   requires feed-card parity or broader shared 1:1 behavior changes, return
   `blocked` instead of widening Session `1`.

## Risks And Edge Cases

- Selected messages near the top or bottom of the viewport may force the
  overlay stack to clamp, so the selected-message host cannot assume ideal
  vertical spacing.
- Taller messages or messages with media/quoted content may need the host to
  preserve message identity without assuming a fixed short text bubble.
- The shared overlay contract is used by feed in Session `2`, so Session `1`
  should keep the API evolvable without trying to finish feed parity now.
- The working tree already contains unrelated and adjacent uncommitted changes;
  execution must preserve user changes and avoid reverting repo-local edits not
  required for this session.

## Exact Tests And Gates To Run

Direct tests:

- `flutter test test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`

Named gate:

- `./scripts/run_test_gates.sh baseline`

Fast structural validation may use one of the direct `flutter test` commands
above before broader test execution if the seam changes widget signatures or
overlay wiring.

## Known-Failure Interpretation

- Treat failures in the newly added selected-message visibility or clamping
  assertions as Session `1` regressions until fixed.
- Treat failures in untouched areas as new regressions only if they reproduce
  after accounting for the repo's already-dirty working tree and are plausibly
  tied to the changed overlay/conversation seam.
- Do not add `1to1` gate coverage unless the implementation widens into shared
  send/persist/listener semantics rather than staying on UI presentation.

## Done Criteria

- The direct conversation long-press overlay visibly includes the selected
  message while open.
- The reaction row and menu remain visually anchored to that selected message.
- Top and bottom viewport cases keep the message identifiable and the action
  stack usable.
- Existing direct-message overlay actions still behave the same under current
  rules.
- The three direct conversation suites and the `baseline` gate pass, or any
  non-session failure is explicitly proven pre-existing and documented in the
  execution result.

## Scope Guard

- Do not implement feed-card parity in this session.
- Do not add new menu actions or change availability rules for existing
  actions.
- Do not change reaction send semantics, delete semantics, quote-send
  persistence, or broader 1:1 reliability behavior.
- Do not redesign the whole overlay architecture if a narrower host-contract
  change solves the problem.

## Accepted Differences / Intentionally Out Of Scope

- Feed-card parity stays in Session `2`.
- Group-thread long-press behavior remains out of scope.
- Exact animation tuning and presentation polish beyond visible anchored
  continuity are intentionally secondary unless required to keep the selected
  message identifiable.

## Dependency Impact

- Session `2` depends on this session establishing the shared selected-message
  overlay contract and proving it on the direct conversation surface first.
- If Session `1` ends `blocked`, Session `2` should remain dependency-blocked
  rather than implementing feed parity against an unstable shared contract.
