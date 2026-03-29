# 26 - Long-Press Context Menu on Messages (Reply, Copy, Emoji Bar)

**Feature Improvement**

---

## 1. Problem Statement

The app currently supports **swipe-right-to-reply** on incoming messages and
**long-press to show emoji reaction bar**. However, the reply action is not
discoverable through the long-press gesture, and there is no way to copy message
text to the clipboard.

**What is insufficient:**

- **Reply discoverability:** The only way to reply (quote) a message is via
  right-swipe, a gesture that is not visually indicated and that many users do
  not discover. Signal, iMessage, and WhatsApp all surface "Reply" in a
  long-press context menu, making it immediately visible.
- **No copy-to-clipboard:** Users cannot copy the text of a received or sent
  message. The app uses `Clipboard.setData()` elsewhere (settings peer ID, QR
  code, mnemonic) but not on messages.
- **Emoji bar positioning:** The current long-press only shows the emoji
  reaction bar (`ReactionBar`) as a dialog with a transparent barrier. There is
  no blurred background overlay behind it, and no context menu options appear
  below the message. The Signal reference shows the emoji bar floating above the
  message with a full-screen blur behind it.

**Where this must work (two surfaces):**

1. **Orbit 1:1 conversations** — `ConversationScreen` using `LetterCard` widgets
2. **Stack/Feed cards** — `FeedScreen` using `MessageBubble` inside
   `ScrollableMessagePreview` (both collapsed and open mode cards)

**Who is affected:** All users viewing text messages in any conversation context.

---

## 2. Impact Analysis

| Dimension | Assessment |
|-----------|-----------|
| Severity | Moderate — reply exists but is hidden; copy is completely absent |
| Frequency | Every conversation, every message — core messaging interaction |
| User consequence | Users miss the reply feature entirely; cannot copy text for sharing outside the app |
| Workaround | Swipe-right for reply (undiscoverable); no workaround for copy |
| Platform scope | iOS and Android (Flutter) |

| Scenario | Current UX | Desired UX |
|----------|-----------|------------|
| User wants to reply to a message | Must know to swipe right (no visual hint) | Long-press shows "Reply" option; swipe-right also still works |
| User wants to copy message text | Not possible | Long-press shows "Copy" option; text goes to clipboard |
| User wants to react with emoji | Long-press shows emoji bar with transparent background | Long-press shows emoji bar above message with blurred background, plus context menu below |

---

## 3. Current State

### 3.1 Long-Press Gesture Handling

Both message surfaces already detect long-press and call a callback:

| Surface | Widget | Long-Press Wiring |
|---------|--------|-------------------|
| Orbit 1:1 | `LetterCard` (letter_card.dart:66–67) | `GestureDetector(onLongPress: onLongPress, ...)` |
| Feed/Stack | `MessageBubble` (message_bubble.dart:64–65) | `GestureDetector(onLongPress: onLongPress, ...)` |

**Orbit path:** `LetterCard.onLongPress` → `ConversationScreen._showReactionBar(messageId, cardContext)` (conversation_screen.dart:533–564) → `showDialog()` with `ReactionBar` widget, `barrierColor: Colors.transparent`.

**Feed path:** `MessageBubble.onLongPress` → `onMessageLongPress` callback → wired to feed's reaction bar show logic.

In both cases, long-press **only** shows the emoji reaction bar. There is no
context menu, no copy action, and no reply action from this gesture.

### 3.2 Emoji Reaction Bar

| File | Key Details |
|------|------------|
| `lib/features/conversation/presentation/widgets/reaction_bar.dart` | 155 lines |

- **Preset emojis:** `['👍', '❤️', '😂', '😮', '😢', '🙏']` (line 5)
- **Styling:** Glassmorphic bar with `BackdropFilter(blur: 24px)`, background
  `rgba(18, 20, 28, 0.95)`, border `rgba(255, 255, 255, 0.10)`, rounded corners
  28px (lines 59–71)
- **Animation:** Scale 0.8 → 1.0 over 200ms with `easeOut` (lines 39–46)
- **Positioning:** Placed above message using `anchorY` coordinate, 8px gap,
  clamped to screen (lines 86–101)
- **Dismissal:** Tap on transparent overlay calls `onDismiss` (lines 103–110)
- **Current issue:** The dialog uses `barrierColor: Colors.transparent`
  (conversation_screen.dart:549), so there is no blurred background overlay
  behind the reaction bar — just a transparent tap-to-dismiss layer.

### 3.3 Swipe-to-Reply (Quote)

| File | Key Details |
|------|------------|
| `lib/features/feed/presentation/widgets/swipe_to_quote_bubble.dart` | 159 lines |

- **Trigger:** Right-swipe on **incoming messages only** (conversation_screen.dart:478, scrollable_message_preview.dart:311)
- **Mechanics:** 72px trigger width, 8px direction lock threshold, fires at 50%
  (36px), 250ms snap-back animation (lines 24–25, 39, 91)
- **Visual:** Reply icon revealed behind bubble with opacity/scale transition

**Reply flow (Orbit 1:1):**
1. Swipe triggers → `onQuoteReply!(message.id)` (conversation_screen.dart:480)
2. `_onQuoteReply(messageId)` sets `_activeQuoteMessageId` (conversation_wired.dart:930–932)
3. Compose area shows quoted text preview
4. User sends message → `quotedMessageId` included in payload
5. Message persisted with `quoted_message_id` field

**Reply flow (Feed/Stack):**
1. Swipe triggers → `onQuoteReply!(msg.id)` (scrollable_message_preview.dart:313)
2. `_onQuoteReply(contactPeerId, messageId)` sets `_activeQuoteMessageIds[key]` (feed_wired.dart:2169–2171)
3. Feed compose area shows quoted text preview
4. Same send flow with `quotedMessageId`

**Key constraint:** Swipe-to-reply is currently only available on **incoming**
messages (`if (message.isIncoming && widget.onQuoteReply != null)` at
conversation_screen.dart:478 and scrollable_message_preview.dart:311). The
context menu "Reply" should work on **both incoming and sent** messages.

### 3.4 Clipboard Usage

Clipboard is already used in the app via `Clipboard.setData(ClipboardData(text: ...))`:

| Location | What is copied |
|----------|---------------|
| `settings_wired.dart` | Peer ID, mnemonic phrase |
| `qr_code_section.dart` | QR code data |

**No clipboard integration exists for message text.**

### 3.5 Blur / Overlay Patterns

| Location | Blur Usage |
|----------|-----------|
| `ReactionBar` (reaction_bar.dart:62) | `ImageFilter.blur(sigmaX: 24, sigmaY: 24)` on the bar itself |
| `LetterCard` (letter_card.dart:70) | `BackdropFilter` on the card background |
| Confirmation dialogs | Blur overlays in orbit confirmation dialog |

The app has established patterns for `BackdropFilter` usage. The current
reaction bar overlay uses `Colors.transparent` as its barrier — the Signal
reference shows a full-screen blur behind the emoji bar and context menu.

### 3.6 Message Data Available at Long-Press

At the point of long-press, the following data is accessible:

| Field | Available in MessageBubble | Available in LetterCard |
|-------|---------------------------|------------------------|
| Message text | `text` (line 19) | `text` (line 19) |
| Message ID | Via `onLongPress` callback parameter | Via `onLongPress` callback parameter |
| Is incoming | `isIncoming` (line 22) | `isIncoming` (line 21) |
| Sender name | `senderLabel` (line 24) | `senderName` (line 18) |
| Message position (for anchoring) | Via `cardContext` render box | Via `cardContext` render box |

---

## 4. Scope Clarification

| Area | Status | Notes |
|------|--------|-------|
| Long-press context menu with "Reply" and "Copy" | **In scope** | New context menu widget |
| Emoji reaction bar repositioned above message in overlay | **In scope** | Adjust existing `ReactionBar` positioning within the overlay |
| Full-screen blurred background on long-press overlay | **In scope** | Replace transparent barrier with blur |
| Copy message text to clipboard | **In scope** | `Clipboard.setData()` for message text |
| Reply from context menu triggers existing quote flow | **In scope** | Wire to existing `onQuoteReply` callbacks |
| Reply on both incoming AND sent messages via context menu | **In scope** | Swipe-to-reply stays incoming-only; context menu reply works on all |
| Works in Orbit 1:1 conversations (`ConversationScreen`) | **In scope** | `LetterCard` surface |
| Works in Feed/Stack cards (`FeedScreen`) | **In scope** | `MessageBubble` surface |
| Swipe-to-reply continues to work unchanged | **Unchanged** | Existing swipe gesture is not modified |
| Emoji reaction sending/receiving logic | **Unchanged** | Existing P2P reaction flow is not modified |
| Full emoji picker (bottom sheet) | **Unchanged** | Still accessible via "+" button in reaction bar |
| Forward, Select, Info, Pin, Delete menu items | **Out of scope** | Only "Reply" and "Copy" per requirements |
| Media-only messages (no text) | **In scope** | Copy should be disabled/hidden for messages with no text content |
| Voice messages | **In scope** | Copy should be disabled/hidden for audio-only messages |
| Group/announcement messages | **Out of scope unless they use the same surfaces** | If they use `MessageBubble` or `LetterCard`, they get the feature automatically |

---

## 5. Test Cases

### Group A: Long-Press Trigger and Overlay Appearance

**TC-26-A01** — Long-press on a received text message in Orbit 1:1 shows the context overlay
Given the user is in an Orbit 1:1 conversation with at least one received text message,
when the user long-presses on the message for the standard long-press duration,
then a full-screen overlay appears with: (1) a blurred background, (2) the emoji reaction bar positioned above the message, and (3) a context menu below the message with "Reply" and "Copy" options.

**TC-26-A02** — Long-press on a sent text message in Orbit 1:1 shows the context overlay
Given the user is in an Orbit 1:1 conversation with at least one sent text message,
when the user long-presses on their own sent message,
then the same overlay appears with emoji bar, blurred background, and context menu with "Reply" and "Copy".

**TC-26-A03** — Long-press on a received text message in a Feed/Stack card shows the context overlay
Given the user has an open feed card with at least one received text message,
when the user long-presses on the message,
then the overlay appears with emoji bar above, blurred background, and context menu with "Reply" and "Copy".

**TC-26-A04** — Long-press on a sent text message in a Feed/Stack card shows the context overlay
Given the user has an open feed card with at least one sent text message,
when the user long-presses on their own sent message,
then the overlay appears with emoji bar, blurred background, and context menu.

**TC-26-A05** — Blurred background covers the full screen
Given the context overlay is showing,
when the user looks at the area behind the emoji bar and context menu,
then the entire background behind the overlay is visually blurred (not transparent, not solid black).

**TC-26-A06** — Emoji bar appears above the long-pressed message
Given the user long-presses a message in the middle of the screen,
when the overlay appears,
then the emoji reaction bar is positioned directly above the target message with a visible gap, not centered on screen or at an arbitrary position.

**TC-26-A07** — Emoji bar stays on-screen when message is near top
Given the user long-presses a message near the top edge of the screen,
when the overlay appears,
then the emoji bar is clamped so it remains fully visible on screen (does not clip above the top edge).

### Group B: Context Menu Actions — Reply

**TC-26-B01** — Tapping "Reply" on a received message in Orbit 1:1 activates quote mode
Given the context overlay is showing for a received message in an Orbit 1:1 conversation,
when the user taps "Reply",
then the overlay dismisses, the compose area shows a quoted-message preview bar with the selected message's text, and the keyboard focus moves to the text input.

**TC-26-B02** — Tapping "Reply" on a sent message in Orbit 1:1 activates quote mode
Given the context overlay is showing for a sent message in Orbit 1:1,
when the user taps "Reply",
then the overlay dismisses and the compose area shows a quoted-message preview for the sent message.

**TC-26-B03** — Tapping "Reply" on a message in a Feed/Stack card activates quote mode
Given the context overlay is showing for a message in a feed card,
when the user taps "Reply",
then the overlay dismisses and the feed card's compose area shows the quoted-message preview.

**TC-26-B04** — Sending a reply after context-menu "Reply" includes the quote reference
Given the user tapped "Reply" from the context menu and typed a response,
when the user sends the message,
then the sent message includes `quotedMessageId` referencing the original message, and the recipient sees the reply with a quote bar.

**TC-26-B05** — "Reply" from context menu followed by clearing the quote
Given the user tapped "Reply" from the context menu and the quote preview is showing,
when the user taps the dismiss/clear button on the quote preview bar,
then the quote is removed and the next sent message has no `quotedMessageId`.

### Group C: Context Menu Actions — Copy

**TC-26-C01** — Tapping "Copy" on a text message copies the text to clipboard
Given the context overlay is showing for a message with text content "Hello, how are you?",
when the user taps "Copy",
then the overlay dismisses and the system clipboard contains exactly "Hello, how are you?".

**TC-26-C02** — Copied text can be pasted into the compose area
Given the user copied a message's text via the context menu,
when the user taps in the compose input and pastes,
then the copied message text appears in the input field.

**TC-26-C03** — Copy on a message with only media (no text) is hidden or disabled
Given a message that contains only an image/video/audio attachment with no text body,
when the user long-presses on it,
then the context menu either hides the "Copy" option or shows it disabled/grayed out.

**TC-26-C04** — Copy on a message with both text and media copies only the text
Given a message with text "Check this out" and an attached image,
when the user taps "Copy",
then the clipboard contains "Check this out" (text only, not a media reference).

### Group D: Dismissal Behavior

**TC-26-D01** — Tapping the blurred background dismisses the overlay
Given the context overlay (emoji bar + context menu + blur) is showing,
when the user taps anywhere on the blurred background (outside the emoji bar and context menu),
then the entire overlay dismisses and the conversation returns to normal.

**TC-26-D02** — Selecting an emoji dismisses the overlay
Given the context overlay is showing,
when the user taps one of the preset emojis in the reaction bar,
then the reaction is sent, and the entire overlay (including context menu) dismisses.

**TC-26-D03** — Tapping "+" for full emoji picker dismisses the context menu overlay
Given the context overlay is showing,
when the user taps the "+" button in the reaction bar,
then the context overlay dismisses and the full emoji picker bottom sheet appears.

**TC-26-D04** — Back button / swipe-back dismisses the overlay
Given the context overlay is showing,
when the user presses the system back button (Android) or swipe-back gesture (iOS),
then the overlay dismisses without any action taken.

### Group E: Interaction with Existing Swipe-to-Reply

**TC-26-E01** — Swipe-to-reply still works on incoming messages after feature addition
Given an incoming message in Orbit 1:1,
when the user swipes right on the message (without long-pressing),
then the existing swipe-to-reply triggers at the 50% threshold and activates quote mode, unchanged from current behavior.

**TC-26-E02** — Swipe-to-reply still works on incoming messages in Feed/Stack cards
Given an incoming message in a feed card,
when the user swipes right,
then the existing swipe-to-reply triggers as before.

**TC-26-E03** — Swipe-to-reply is still restricted to incoming messages
Given a sent message in Orbit 1:1,
when the user attempts to swipe right on it,
then no swipe gesture is detected (swipe-to-reply remains incoming-only; the context menu is the way to reply to sent messages).

### Group F: Emoji Reaction Bar Behavior Within Overlay

**TC-26-F01** — Emoji bar shows the user's current reaction as selected
Given the user has already reacted to a message with the heart emoji,
when the user long-presses the same message,
then the heart emoji in the reaction bar appears visually selected/highlighted.

**TC-26-F02** — Tapping a different emoji changes the reaction
Given the user long-presses a message they previously reacted to with thumbs-up,
when the user taps the laugh emoji,
then the thumbs-up reaction is replaced with the laugh reaction.

**TC-26-F03** — Emoji bar animation plays on overlay appearance
Given the user long-presses a message,
when the overlay appears,
then the emoji bar scales from 0.8 to 1.0 with an ease-out animation over approximately 200ms.

### Group G: Edge Cases

**TC-26-G01** — Long-press on a message near the bottom of the screen
Given a message is near the bottom edge of the screen,
when the user long-presses it,
then the context menu and emoji bar are positioned so they remain fully visible (the layout adapts so nothing is clipped off-screen).

**TC-26-G02** — Long-press on a very long message
Given a message with 500+ characters of text,
when the user long-presses it and taps "Copy",
then the full message text (all 500+ characters) is copied to the clipboard.

**TC-26-G03** — Long-press while scrolling does not trigger accidentally
Given the user is actively scrolling through messages,
when the user's finger pauses briefly on a message during scroll deceleration,
then the context overlay does not appear (only an intentional stationary long-press triggers it).

**TC-26-G04** — Multiple sequential long-presses on different messages
Given the user long-presses message A, dismisses the overlay, then long-presses message B,
when the overlay appears for message B,
then it shows the emoji bar and context menu for message B (not message A), with message B's reaction state.

**TC-26-G05** — Long-press on a message with RTL text
Given a message containing Arabic or Hebrew text,
when the user long-presses and taps "Copy",
then the RTL text is copied correctly to the clipboard with proper directionality preserved.

**TC-26-G06** — Context menu on a failed/pending message
Given a sent message with status "failed" or "pending" (not yet delivered),
when the user long-presses it,
then the context overlay still appears. "Copy" works for the text. "Reply" works to quote the message locally.

### Group H: Visual Design Consistency

**TC-26-H01** — Context menu matches the app's glassmorphic design language
Given the context overlay is showing,
when the user inspects the context menu visually,
then it uses the same glassmorphic styling as the emoji reaction bar: dark translucent background, subtle border, rounded corners, white text at appropriate alpha levels.

**TC-26-H02** — Context menu items have icons alongside text labels
Given the context overlay is showing,
when the user looks at the context menu,
then "Reply" and "Copy" each have an icon to their left (consistent with the Signal reference showing icon + label layout).

**TC-26-H03** — Overlay works in both light and dark environments
Given the app's dark theme,
when the context overlay is shown over messages with varying background brightness,
then the blur, emoji bar, and context menu are all legible and visually consistent.
