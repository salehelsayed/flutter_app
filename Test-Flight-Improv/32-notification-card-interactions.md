# 32 - Notification-Opened Feed Card: Profile Picture and Collapse Bar Non-Responsive

**Bug**

---

## 1. Problem Statement

When a user receives a message notification and opens the app on the Feed
screen, the corresponding stack card opens automatically in "open mode"
(showing unread messages). The messages display correctly. However:

1. **Tapping the profile picture** does not open the main chat window.
2. **Tapping the collapse bar** (below the messages) does not collapse the card.

Both interactions work correctly when the card reaches open mode through normal
app usage (receiving a message while the app is already open, or manually
expanding a card).

**Reproduction steps:**

1. Close the app (background or kill).
2. Receive a 1:1 message from a contact.
3. Tap the notification to open the app.
4. Observe the Feed screen with the contact's card in open mode, messages visible.
5. Tap the profile picture (avatar) in the card header → **nothing happens**
   (expected: opens full conversation screen).
6. Tap the collapse bar at the bottom of the messages → **nothing happens**
   (expected: collapses the card back to preview mode).

**Who is affected:** All users who open the app via a message notification.

---

## 2. Impact Analysis

| Dimension | Assessment |
|-----------|-----------|
| Severity | High — core navigation broken; user cannot open conversation or collapse card |
| Frequency | Every time the app is opened via a message notification with a feed card |
| User consequence | Cannot navigate to full conversation; cannot collapse the card; forced to restart or scroll away |
| Workaround | Navigate away and back, or open Orbit and find the contact there |
| Platform scope | iOS and Android (Flutter) |

---

## 3. Current State

### 3.1 Card Mode Selection

| File | Key Lines |
|------|-----------|
| `lib/features/feed/presentation/widgets/feed_card.dart` | Line 97, 130 |
| `lib/features/feed/domain/models/feed_item.dart` | Lines 172–175 |

**`_showOpen`** (feed_card.dart:97):
```dart
bool get _showOpen => widget.thread.isOpenMode && widget.sessionReply == null;
```

**`isOpenMode`** (feed_item.dart:172–175):
```dart
bool get isOpenMode =>
    conversationState == ConversationState.unread ||
    conversationState == ConversationState.active;
```

When a notification arrives, the conversation state becomes `unread`/`active`,
so `isOpenMode` is `true`, and the card renders `OpenModeCardBody`.

### 3.2 Open Mode Card Body — Callback Wiring

| File | Key Lines |
|------|-----------|
| `lib/features/feed/presentation/widgets/feed_card.dart` | Lines 162–185 |
| `lib/features/feed/presentation/widgets/open_mode_card_body.dart` | Lines 20–21, 95–157 |

**FeedCard._buildOpenBody()** (feed_card.dart:162–185):
- `onViewEarlier: widget.onViewFullConversation` (line 166) — avatar tap in
  OpenMode is wired to `onViewFullConversation`.
- `onCollapse: widget.onToggleExpand` (line 167) — collapse is wired to
  `onToggleExpand`.

**OpenModeCardBody header** (open_mode_card_body.dart:120–122):
- Avatar: `GestureDetector(onTap: onViewEarlier, child: UserAvatar(...))`.
- `onViewEarlier` is received from `_buildOpenBody()` as `widget.onViewFullConversation`.

**Collapse hint** (scrollable_message_preview.dart:167–170):
- `GestureDetector(onTap: widget.onCollapse, behavior: HitTestBehavior.opaque, ...)`
- `onCollapse` flows: FeedCard `widget.onToggleExpand` → OpenModeCardBody
  `onCollapse` → ScrollableMessagePreview `onCollapse` → `_buildCollapseHint()`.

### 3.3 Collapsed Mode Card Body — Callback Wiring (Works Correctly)

| File | Key Lines |
|------|-----------|
| `lib/features/feed/presentation/widgets/feed_card.dart` | Lines 187–213 |
| `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart` | Lines 123–124, 169 |

**FeedCard._buildCollapsedBody()** (feed_card.dart:187–213):
- `onViewFullConversation: widget.onViewFullConversation` (line 195).
- `onTapExpand: widget.onToggleExpand` (line 193).
- `onCollapse: widget.onToggleExpand` (line 194).

**CollapsedModeCardBody header** (collapsed_mode_card_body.dart:123–124):
- Avatar: `GestureDetector(onTap: onViewFullConversation, child: UserAvatar(...))`.
- Header area: `GestureDetector(onTap: onTapExpand, ...)` (line 87–88).

### 3.4 FeedWired Card Expansion State

| File | Key Lines |
|------|-----------|
| `lib/features/feed/presentation/screens/feed_wired.dart` | Lines 169, 2097–2153 |

- `_expandedCardId` (line 169): Tracks which card is manually expanded.
  Only set by `_onToggleExpand()` callback.
- `_onToggleExpand(String cardId)` (lines 2097–2153): Toggles expansion,
  clears session replies, updates state.
- When card enters open mode via **notification**, `_expandedCardId` is **never
  set** — the card is open because `isOpenMode` is `true` (data-driven), not
  because `_expandedCardId` matches.

### 3.5 Notification Handling Flow

| File | Key Lines |
|------|-----------|
| `lib/main.dart` | Lines 1365–1518 |

- Notification tap handler: `_onNotificationTap()` → `_handleNotificationRouteTarget()`.
- For `conversation` kind: pushes `ConversationWired` directly via
  `Navigator.push()` (line ~1486–1513).
- Does **not** signal FeedWired to expand a specific card.
- When app is opened from notification to Feed screen: incoming message
  listener fires, conversation state changes to `unread`, card renders in
  open mode automatically — but FeedWired's callback state may not be
  initialized.

### 3.6 FeedWired Callback Wiring to FeedScreen

| File | Key Lines |
|------|-----------|
| `lib/features/feed/presentation/screens/feed_wired.dart` | Line 2220 |
| `lib/features/feed/presentation/screens/feed_screen.dart` | Lines 542–544 |

- `onViewFullConversation: _onViewFullConversation` (feed_wired.dart:2220).
- `onToggleExpand: _onToggleExpand` (fed through to FeedCard).
- FeedScreen passes to FeedCard: `onViewFullConversation: onViewFullConversation != null ? () => onViewFullConversation!(item.contactPeerId) : null` (feed_screen.dart:542–544).

**Key concern:** If `onViewFullConversation` is null when the card renders
(before FeedWired finishes init), the callback will be null and taps will do
nothing.

### 3.7 Incoming Message Listener

| File | Key Lines |
|------|-----------|
| `lib/features/feed/presentation/screens/feed_wired.dart` | Chat message listener setup |

When a message arrives while FeedWired is mounted:
- `_applyIncomingContactMessageToFeed()` updates the feed item's conversation
  state.
- Card transitions to `isOpenMode = true` → renders `OpenModeCardBody`.
- Callbacks are already wired (FeedWired is fully initialized).

When app opens from cold start via notification:
- FeedWired `initState()` runs, listeners and callbacks start initializing.
- Feed data loads asynchronously.
- Card may render before callbacks are fully wired.
- Timing-dependent: if card renders during `_isLoading = true` phase, callbacks
  may not yet be available.

### 3.8 Existing Tests

| File | Coverage |
|------|----------|
| `test/features/feed/presentation/screens/feed_wired_test.dart` | General card expansion, no notification scenario |
| `test/integration/notification_deeplink_integration_test.dart` | Notification routing, not card interaction |
| `test/features/feed/integration/expanded_collapsed_card_test.dart` | Card state, not notification-triggered |

- **No test exists** for: notification-triggered card → profile picture tap.
- **No test exists** for: notification-triggered card → collapse bar tap.

---

## 4. Scope Clarification

| Area | Status | Notes |
|------|--------|-------|
| Profile picture tap opens conversation in notification-opened card | **In scope** | Core bug |
| Collapse bar tap collapses notification-opened card | **In scope** | Core bug |
| Callback wiring timing on cold-start notification path | **In scope** | Likely root cause |
| Feed card interactions without notification (manual expand) | **Unchanged** | Already works |
| Notification routing to full conversation screen | **Unchanged** | Direct push works |
| Feed data loading and rendering | **Unchanged** | Data loads correctly |
| Message display in open mode card | **Unchanged** | Messages display correctly |

---

## 5. Test Cases

### Group A: Profile Picture Tap (Notification Path)

**TC-32-A01** — Profile picture opens conversation after notification cold-start
Given the app is not running and a message notification arrives from contact Bob,
when the user taps the notification, the Feed screen loads with Bob's card in
open mode, and the user taps Bob's profile picture (avatar),
then the full conversation screen for Bob opens.

**TC-32-A02** — Profile picture opens conversation after notification warm-start
Given the app is backgrounded and a message notification arrives from contact Bob,
when the user taps the notification, the Feed screen shows with Bob's card in
open mode, and the user taps Bob's profile picture,
then the full conversation screen for Bob opens.

**TC-32-A03** — Profile picture works after notification when app was on Feed
Given the app is on the Feed screen (foreground) and a new message arrives
(no notification tap, just live message),
when the card transitions to open mode and the user taps the profile picture,
then the full conversation screen opens.

### Group B: Collapse Bar Tap (Notification Path)

**TC-32-B01** — Collapse bar collapses the card after notification cold-start
Given the app is not running and a message notification arrives,
when the user taps the notification, the Feed screen loads with the card in
open mode, and the user taps the collapse bar (the hint row below messages),
then the card collapses to its preview/closed state.

**TC-32-B02** — Collapse bar collapses the card after notification warm-start
Given the app is backgrounded and a message notification arrives,
when the user taps the notification, the card is in open mode, and the user
taps the collapse bar,
then the card collapses.

**TC-32-B03** — Collapse bar works after multiple messages arrive via notification
Given 3 messages arrive from the same contact while the app is closed,
when the user opens via notification and the card shows all 3 unread messages,
then the collapse bar tap collapses the card normally.

### Group C: Comparison with Non-Notification Path (Regression)

**TC-32-C01** — Profile picture works on manually expanded card
Given the user is on the Feed screen and manually taps a card to expand it,
when the user taps the profile picture,
then the full conversation screen opens (existing behavior, must not regress).

**TC-32-C02** — Collapse bar works on manually expanded card
Given the user has manually expanded a card,
when the user taps the collapse bar,
then the card collapses (existing behavior, must not regress).

**TC-32-C03** — Profile picture works on card that entered open mode from live message
Given the app is open on the Feed screen,
when a new message arrives and the card transitions to open mode,
then tapping the profile picture opens the full conversation (existing
behavior, must not regress).

**TC-32-C04** — Collapse bar works on card that entered open mode from live message
Given the app is open and a card is in open mode due to a live message,
when the user taps the collapse bar,
then the card collapses (existing behavior, must not regress).

### Group D: Timing and Initialization

**TC-32-D01** — Interactions work even if card renders before feed fully loads
Given the app is opened from a notification and feed items are still loading,
when the first card renders in open mode and the user immediately taps the
profile picture,
then either: (a) the tap opens the conversation, or (b) the card waits until
fully initialized and then responds to taps (no silent failure).

**TC-32-D02** — Interactions work after scrolling the feed
Given the user opens via notification, the card is in open mode,
when the user scrolls the feed up and down and then taps the profile picture
on the open card,
then the conversation opens.

**TC-32-D03** — Multiple notifications from different contacts
Given the user has notifications from contacts Alice and Bob,
when the user opens the app and both cards are in open mode,
then tapping Alice's profile picture opens Alice's conversation, and tapping
Bob's collapse bar collapses Bob's card.

### Group E: Edge Cases

**TC-32-E01** — Group conversation card interactions from notification
Given a group message notification arrives,
when the user opens the app and the group card is in open mode,
then tapping the group icon (avatar area) opens the group conversation, and
tapping the collapse bar collapses the card.

**TC-32-E02** — Card with many unread messages from notification
Given 20 unread messages from a contact arrived while the app was closed,
when the user opens via notification and the card shows a scrollable message
preview,
then the "View Earlier" link and collapse bar are both tappable and functional.

**TC-32-E03** — Blocked contact card from notification
Given a notification arrives from a contact the user has blocked (edge case),
when the card shows with the blocked overlay,
then interactions are appropriately blocked (consistent with normal behavior).

**TC-32-E04** — App killed during notification handling
Given the user taps a notification and the app begins cold-starting,
when the app is killed mid-initialization and restarted,
then on the next open, the card interactions work normally.

### Group F: Inline Reply Input

**TC-32-F01** — Inline reply input works on notification-opened card
Given the card is in open mode from a notification,
when the user taps the reply input field and types a message,
then the message can be composed and sent normally.

**TC-32-F02** — Swipe-to-reply works on notification-opened card
Given the card is in open mode from a notification with received messages,
when the user swipes right on a received message bubble,
then the swipe-to-reply gesture works and the quote preview appears in the
compose area.
