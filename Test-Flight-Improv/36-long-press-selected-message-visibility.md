# 36 - Long-Press Context Overlay Should Keep the Selected Message Visible

## 1. Title and Type

- Title: Long-Press Context Overlay Should Keep the Selected Message Visible
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/36-long-press-selected-message-visibility.md`

## 2. Problem Statement

Users long-press a message to react or use message actions such as Reply, Copy,
or Delete. The current overlay shows the reaction bar and action menu, but it
does not keep the selected message itself clearly visible as the focal element
of that state.

From the user’s perspective, the interaction loses context at the moment it
should become more precise. The user-provided reference shows the selected
message staying visible between the reaction row and the action sheet, while the
rest of the screen is de-emphasized. In the current app flow, users get the
actions, but not the same visual confirmation of which message they are acting
on, and the overlay can feel detached from the target message rather than
smoothly anchored to it.

## 3. Impact Analysis

- Affected users: anyone using long-press actions on supported direct-message
  surfaces.
- When it appears: every time the long-press context overlay opens in the
  conversation screen or thread feed cards.
- Severity: moderate. The actions are present, but the interaction loses visual
  clarity in a core messaging flow.
- Frequency: high for users who rely on reply, copy, delete, or quick reactions.
- User cost: weaker confidence that the correct message is selected.
- User cost: less polished interaction compared with the expected
  anchored-message presentation in the provided reference.
- User cost: added hesitation when multiple nearby messages are visually
  similar.

## 4. Current State

- Long-press is already wired on the two message surfaces that expose the shared
  context overlay:
  - `lib/features/conversation/presentation/widgets/letter_card.dart`
  - `lib/features/feed/presentation/widgets/message_bubble.dart`
- Both surfaces route long-press into a shared overlay flow:
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
- The shared overlay is implemented in
  `lib/features/conversation/presentation/widgets/message_context_overlay.dart`.
  Its visible content is the blurred backdrop, the `ReactionBar`, and the
  context menu card.
- The overlay is positioned from an `anchorRect` captured from the pressed
  message’s render box. That lets the reaction bar and menu align around the
  message position, but the overlay API does not receive or render the selected
  message content itself.
- Because the overlay only draws the backdrop, reaction bar, and menu, the
  selected message is not presented as a clear focal element in the overlay
  state. It remains only in the background conversation/feed content behind the
  blur.
- Existing direct tests currently cover the presence and action behavior of the
  overlay, not the visibility of the selected message while the overlay is open:
  - `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
- Adjacent repo context:
  - `Test-Flight-Improv/26-long-press-message-context-menu.md` describes the
    broader long-press menu feature area that is now present in code.
  - This spec is narrower and only covers the remaining presentation gap around
    selected-message visibility and anchored positioning.

## 5. Scope Clarification

- In scope: the long-pressed message remains visibly identifiable while the
  overlay is open.
- In scope: the reaction row and action menu feel visually anchored to that
  same message, not detached from it.
- In scope: the overlay presentation behaves consistently on the current
  direct-message surfaces that already use `MessageContextOverlay`.
- In scope: existing reply, copy, edit, delete, and reaction affordances remain
  usable while this presentation issue is addressed.
- Out of scope: adding new menu actions.
- Out of scope: changing which actions are available for which message types.
- Out of scope: changing reaction send/delete/edit business rules.
- Out of scope: expanding this spec to group-thread long-press behavior that
  still uses a separate reaction-only dialog path.
- Accepted ambiguity: the exact motion curve, animation duration, and spacing
  values.
- Accepted ambiguity: the exact rendering strategy used to keep the selected
  message visible, as long as the user-visible behavior is preserved.
- Accepted ambiguity: the exact amount of blur or scrim applied to surrounding
  content, as long as the selected message remains the clear focal element.

## 6. Test Cases

### Happy Path

- **HP-36-01**: In a direct conversation, long-pressing an incoming message
  opens the context overlay with the selected message still clearly visible,
  the reaction bar above it, and the action menu below it.
- **HP-36-02**: In a direct conversation, long-pressing an outgoing message
  opens the same anchored presentation, with the selected message remaining
  visibly associated with the overlay actions.
- **HP-36-03**: In a thread feed card that already supports the shared context
  overlay, long-pressing a message keeps that specific message visibly present
  while the reaction bar and menu open around it.
- **HP-36-04**: When the overlay opens, the selected message does not appear to
  jump to an unrelated position or disappear behind the backdrop. The resulting
  state reads as one continuous interaction centered on the pressed message.

### Edge Cases

- **EC-36-01**: When the selected message is near the top of the viewport, the
  overlay still keeps the message identifiable and keeps the reaction row and
  menu on-screen without clipping.
- **EC-36-02**: When the selected message is near the bottom of the viewport,
  the overlay still keeps the message identifiable and keeps the action stack
  on-screen without awkward overlap or off-screen placement.
- **EC-36-03**: When there are several visually similar neighboring messages,
  opening the overlay still makes it unambiguous which exact message is the
  active target.
- **EC-36-04**: When the selected message has a taller presentation such as
  multi-line text, quoted content, or attached media, the overlay still keeps
  the target message visually associated with the action stack.

### Regressions To Preserve

- **RG-36-01**: Existing long-press actions remain available under their current
  rules, including reply on supported messages and copy only when message text
  is available.
- **RG-36-02**: Selecting an emoji still applies the reaction to the chosen
  message and dismisses the overlay afterward.
- **RG-36-03**: Tapping Reply, Copy, Edit, or Delete still routes through the
  same user-visible flows already covered by current tests.
- **RG-36-04**: Tapping outside the overlay still dismisses it.
- **RG-36-05**: Deleted messages remain inert and do not open the context
  overlay.

### Existing Coverage and Gaps

- Existing coverage already verifies action availability and dismissal in
  `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`.
- Existing coverage already verifies action availability and dismissal in
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`.
- Existing coverage already verifies action availability and dismissal in
  `test/features/feed/presentation/screens/feed_screen_test.dart`.
- Current gap: the inspected tests do not assert that the selected message stays
  visible and visually anchored while the overlay is presented.
