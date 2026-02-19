# Feed D — Thread-Grouped Stacked Cards Design Specification

## Overview

Feed D is an evolution of the text-only message feed that **groups multiple messages from the same friend into a single expandable card**. Instead of displaying every message as its own card (which creates clutter when a friend sends 5 messages in a row), messages are grouped into **thread cards** — one card per friend per session.

The same friend can appear **twice** in the feed: once as an unread stack at the top (new messages since the user's last visit), and once as a read card further down (messages from a previous session). A labeled divider separates the two sections.

There are **three visual states** for a thread card:
1. **Collapsed (single message)** — looks identical to a Feed C card. No stacking, no expand hint.
2. **Collapsed (multiple messages)** — shows the latest message, a "+N more messages" hint, and a **stacked paper depth effect** behind the card suggesting more content underneath.
3. **Expanded** — all messages are revealed as a vertical mini-thread of bubbles inside the card, with time-gap dividers between non-consecutive messages. Tapping the card again collapses it.

Unread thread cards also receive an **orange glow border** and an **unread count pill badge** (see badge-spec.md for the full badge system spec).

---

## IMPORTANT: Reuse Existing Components

Before implementing anything in this spec, **audit the existing Flutter codebase** to identify widgets, services, utilities, themes, and patterns that are already built. Do NOT re-implement what already exists.

The spec below describes the design using **platform-agnostic names**. These are logical component names — not file paths. Your job is to find the Flutter equivalents in the project. The following concepts are expected to already exist in the app:

| Concept | What to Look For | What It Does |
|---|---|---|
| Feed Message Card | The glassmorphic card from Feed C — rounded corners, frosted glass background, card glow, friend indicator row, message content, reply footer. | Search for message card, feed card, or timeline item widgets. This is the **base** that thread cards build on. |
| Bottom Navigation Bar | A bottom tab bar with Feed / Remember / Orbit tabs. Accepts a `feedUnreadCount` prop. | Search for a shared navigation widget, bottom bar, or tab controller. |
| Scroll-Based Visibility | Logic that hides/shows floating UI (e.g. nav bar) based on scroll direction. | Search for scroll listeners, `ScrollController` usage, or visibility toggle logic. |
| Theme System | A theme/color scheme that screens receive (dark mode, accent colors, glass effects). | Search for `ThemeData`, custom theme classes, or color constant files. |
| Unread Badge System | The glow border and pill badge from badge-spec.md. | Search for unread badge widgets, glow border styles, or badge overlay components. |
| Message Database / Store | Where received messages are persisted with `receivedAt` and `readAt` timestamps. | Search for message models, database helpers, or conversation state. |
| Conversation Screen | A screen showing the full message history between two users. | Search for conversation, chat, or letter screen widgets. Opening this clears unread badges. |

**Implementation rule:** The thread card is NOT a new card widget — it is the existing Feed C message card enhanced with grouping logic, expand/collapse state, stacked paper styling, and bubble sub-components. Reuse the existing card widget and extend it.

---

## Screen Layout

```
+----------------------------------------------+
|  Good evening                   [Avatar (12)] |  <- Header with total unread badge
|  From your people                             |
|                                               |
|  ┌─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░─┐   |
|  │░ [Av] Olivia         9:20 PM     [1] ░│   |  <- Single unread, no stack
|  │░ Random thought: remember when...     ░│   |
|  │░                           [Reply]    ░│   |
|  └─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░─┘   |
|                                               |
|  ┌─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░─┐   |
|  ├─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░──┤   |  <- Stacked paper layers
|  ├─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░───┤   |
|  │░ [Av] Emma           7:30 PM     [4] ░│   |  <- 4 unread messages stacked
|  │░ Also saw this quote and immediately  ░│   |
|  │░ thought of you...                    ░│   |
|  │░                                      ░│   |
|  │░     +3 more messages        ˅        ░│   |  <- Peek hint
|  │░                           [Reply]    ░│   |
|  └─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░─┘   |
|                                               |
|  ┌─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░─┐   |
|  ├─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░──┤   |
|  │░ [Av] Mike           9:15 AM     [3] ░│   |
|  │░ You NEED to try this next time 😍   ░│   |
|  │░     +2 more messages        ˅       ░│   |
|  │░                           [Reply]    ░│   |
|  └─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░─┘   |
|                                               |
|  ┌─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░─┐   |
|  │░ [Av] Sarah          9:03 AM     [2] ░│   |
|  │░ I got the job!! 🎉🎉🎉              ░│   |
|  │░     +1 more message         ˅       ░│   |
|  │░                           [Reply]    ░│   |
|  └─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░─┘   |
|                                               |
|  ┌─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░─┐   |
|  ├─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░──┤   |
|  │░ [Av] James          4:45 PM     [2] ░│   |
|  │░ Found a ramen spot that would blow   ░│   |
|  │░ your mind...                         ░│   |
|  │░     +1 more message         ˅       ░│   |
|  │░                           [Reply]    ░│   |
|  └─░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░─┘   |
|                                               |
|  ──────── PREVIOUSLY SEEN ────────            |  <- Session divider
|                                               |
|  ┌──────────────────────────────────────┐    |
|  │ [Av] Emma      Yesterday 3:15 PM     │    |  <- Read card, no glow, no badge
|  │ What are you doing this weekend?      │    |
|  │                           [Reply]     │    |
|  └──────────────────────────────────────┘    |
|                                               |
|  ┌──────────────────────────────────────┐    |
|  ├──────────────────────────────────────┤    |
|  │ [Av] Mike       Yesterday 8:45 PM    │    |  <- Read stack, expandable
|  │ Sometimes I wonder what I did to...   │    |
|  │     +1 more message          ˅       │    |
|  │                           [Reply]     │    |
|  └──────────────────────────────────────┘    |
|                                               |
|  ┌──────────────────────────────────────┐    |
|  │ [Av] Sarah    Yesterday 11:30 AM     │    |
|  │ Just wanted to say I'm so grateful    │    |
|  │ for you...               [Reply]      │    |
|  └──────────────────────────────────────┘    |
|                                               |
+----------------------------------------------+
|  [Feed •12]    [Remember]    [Orbit]          |  <- NavigationBar
+----------------------------------------------+

   ░░ = orange glow border (unread cards only)
   [3] = unread count pill badge
```

---

## Data Model

### Message Object

```js
{
  id: Number,
  friendId: Number,            // References the friend who sent the message
  text: String,                // Message content
  time: String,                // Human-readable timestamp (e.g. "9:12 AM", "Yesterday 2:30 PM")
  receivedAt: Date,            // Machine timestamp — when the message arrived on this device
  readAt: Date | null,         // When the user opened the conversation for this friend. null = unread.
}
```

### Thread Card Object (Computed)

Thread cards are not stored — they are computed from the message list at render time:

```js
{
  key: String,                 // Unique identifier: "{friendId}-unread" or "{friendId}-read"
  friend: Friend,              // The friend object (name, avatar, color, etc.)
  messages: Message[],         // All messages in this thread, in chronological order
  latestTime: String,          // The time of the most recent message in the thread
  unreadCount: Number,         // Count of messages where readAt === null
  isUnreadCard: Boolean,       // true = this card is in the "new" section, false = "previously seen"
}
```

### Grouping Algorithm

Messages are grouped into thread cards by **friend + read/unread status**. This means the same friend can produce two cards: one for their unread messages and one for their previously read messages.

```js
// Step 1: Separate messages into unread and read buckets
const unreadByFriend = new Map()  // friendId → ThreadCard
const readByFriend = new Map()    // friendId → ThreadCard

for (const message of allMessages) {
  const isUnread = message.readAt === null
  const map = isUnread ? unreadByFriend : readByFriend

  if (!map.has(message.friendId)) {
    map.set(message.friendId, {
      key: `${message.friendId}-${isUnread ? 'unread' : 'read'}`,
      friend: getFriend(message.friendId),
      messages: [],
      latestTime: null,
      unreadCount: 0,
      isUnreadCard: isUnread,
    })
  }

  const card = map.get(message.friendId)
  card.messages.push(message)
  card.latestTime = message.time
  if (isUnread) card.unreadCount++
}

// Step 2: Sort each section by most recent message (newest first)
const unreadCards = [...unreadByFriend.values()]
  .sort((a, b) => b.messages.at(-1).receivedAt - a.messages.at(-1).receivedAt)

const readCards = [...readByFriend.values()]
  .sort((a, b) => b.messages.at(-1).receivedAt - a.messages.at(-1).receivedAt)

// Step 3: Concatenate — unread cards first, then read cards
const allCards = [...unreadCards, ...readCards]
```

### Total Unread Count

Used for both the header avatar badge and the NavigationBar Feed tab badge:

```js
const totalUnread = allCards.reduce((sum, card) => sum + card.unreadCount, 0)
```

---

## Card Anatomy — Collapsed State (Single Message)

When a thread card contains only one message, it renders identically to a Feed C text message card. No stacked paper effect, no expand hint.

```
+------------------------------------------+
|  [card-glow overlay]                     |
|                                          |
|  [avatar 42px]  Friend Name             |
|                 9:12 AM          [badge] |
|                                          |
|  Message text content goes here.         |
|  Single message, full display.           |
|                                          |
|  ──────────────────────────────────────  |
|                          [ Reply button] |
+------------------------------------------+
```

This card uses the exact same structure as Feed C. See feed-c-message-cards-spec.md for full styling details. The only additions are the optional unread glow border and pill badge from badge-spec.md.

---

## Card Anatomy — Collapsed State (Multiple Messages)

When a thread card contains 2 or more messages, it shows the **most recent message** and adds visual cues that more content exists.

### Structure

```
  ┌────────────────────────────────────────┐   <- Stacked layer 2 (furthest back)
  ├────────────────────────────────────────┤   <- Stacked layer 1
  │  [card-glow overlay]                   │
  │                                        │
  │  [avatar 42px]  Friend Name            │
  │                 9:15 AM        [badge]  │   <- Most recent message's time
  │                                        │
  │  Latest message text goes here.        │   <- Only the most recent message
  │                                        │
  │      +2 more messages         ˅        │   <- Peek hint
  │                                        │
  │  ────────────────────────────────────  │
  │                        [ Reply button] │
  └────────────────────────────────────────┘
```

### Stacked Paper Effect

Two pseudo-element layers behind the main card create the illusion of stacked papers, communicating "there's more here" without text.

**Layer 1 (directly behind the card):**

| Property | Value |
|---|---|
| Position | `absolute` (via `::before` pseudo-element) |
| Inset | `left: 6px; right: 6px; bottom: -4px` |
| Height | `100%` of the card |
| Border radius | `20px` |
| Background | `rgba(255, 255, 255, 0.03)` |
| Border | `1px solid rgba(255, 255, 255, 0.06)` |
| Z-index | `-1` (behind the main card) |
| Pointer events | `none` |

**Layer 2 (furthest back):**

| Property | Value |
|---|---|
| Position | `absolute` (via `::after` pseudo-element) |
| Inset | `left: 12px; right: 12px; bottom: -8px` |
| Height | `100%` of the card |
| Border radius | `20px` |
| Background | `rgba(255, 255, 255, 0.015)` |
| Border | `1px solid rgba(255, 255, 255, 0.03)` |
| Z-index | `-2` |

**When the card also has an unread glow border**, the stacked layers receive a faint matching glow:

| Layer | Box shadow |
|---|---|
| Layer 1 | `0 0 8px rgba(255, 107, 107, 0.15)` |
| Layer 2 | `0 0 6px rgba(255, 107, 107, 0.08)` |

**Extra bottom margin:** Stacked cards need `margin-bottom: 12px` to create room for the protruding layers without overlapping the next card.

### Peek Hint

A centered line below the message text indicating more content is available.

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; justify-content: center; gap: 6px` |
| Padding | `10px 0 2px` |
| Color | `rgba(255, 255, 255, 0.35)` |
| Font size | `13px` |

**Text content:** `"+{N} more message{s}"` where N = `card.messages.length - 1`. Uses plural "messages" when N > 1.

**Chevron icon:** A small downward-pointing arrow (`16x16px`, stroke-based SVG, `opacity: 0.5`) indicating the card can be expanded.

### Cursor

Multi-message cards show `cursor: pointer` to indicate they are tappable. Single-message cards show `cursor: default`.

---

## Card Anatomy — Expanded State

When the user taps a multi-message card, it expands in-place to reveal all messages as a vertical thread of bubbles. The stacked paper layers disappear, the latest-message preview is replaced by the full thread, and a collapse hint appears at the bottom.

### Structure

```
┌──────────────────────────────────────────┐
│  [card-glow overlay]                     │
│                                          │
│  [avatar 42px]  Friend Name              │
│                 9:15 AM          [badge]  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ Hey! Just got to that café we      │  │  <- Bubble 1
│  │ talked about                       │  │
│  │                         9:12 AM    │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ They actually have that crazy      │  │  <- Bubble 2
│  │ drink you mentioned                │  │
│  │                         9:13 AM    │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ───────────── 2:30 PM ──────────────   │  <- Time gap divider
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ Been thinking about what you       │  │  <- Bubble 3
│  │ said yesterday...                  │  │
│  │                         2:30 PM    │  │
│  └────────────────────────────────────┘  │
│                                          │
│                ˄  Collapse               │  <- Collapse hint
│                                          │
│  ────────────────────────────────────── │
│                          [ Reply button] │
└──────────────────────────────────────────┘
```

### Thread Body Container

| Property | Value |
|---|---|
| Padding | `4px 20px 8px` |
| Layout | `display: flex; flex-direction: column; gap: 8px` |

### Message Bubble

Each message in the thread renders as a rounded bubble with the message text and timestamp.

| Property | Value |
|---|---|
| Background | `rgba(255, 255, 255, 0.04)` |
| Border | `1px solid rgba(255, 255, 255, 0.06)` |
| Border radius | `14px` |
| Padding | `10px 14px` |
| Entry animation | `feedDBubbleIn 0.3s ease backwards` — slides up 8px and scales from 0.97, with staggered delay |

**Bubble text:**

| Property | Value |
|---|---|
| Color | `rgba(255, 255, 255, 0.85)` |
| Font size | `14px` |
| Line height | `1.5` |
| Margin | `0` |

**Bubble timestamp:**

| Property | Value |
|---|---|
| Display | `block` |
| Margin top | `6px` |
| Font size | `11px` |
| Color | `rgba(255, 255, 255, 0.25)` |
| Text align | `right` |

**Unread bubble variant:** When the individual message is unread (`readAt === null`), the bubble receives enhanced styling:

| Property | Value |
|---|---|
| Background | `rgba(255, 255, 255, 0.06)` (brighter) |
| Border color | `rgba(255, 107, 107, 0.15)` (warm tint) |
| Box shadow | `inset 0 0 0 1px rgba(255, 107, 107, 0.08)` (subtle inner glow) |

### Stagger Animation

Bubbles animate in one by one with staggered delays:

| Bubble index | Animation delay |
|---|---|
| 1st | `0ms` |
| 2nd | `40ms` |
| 3rd | `80ms` |
| 4th | `120ms` |
| 5th | `160ms` |
| 6th | `200ms` |

```css
@keyframes feedDBubbleIn {
  from {
    opacity: 0;
    transform: translateY(8px) scale(0.97);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}
```

### Time Gap Divider

When consecutive messages within the same thread are separated by a significant time gap (different AM/PM period, or 2+ hours apart), a thin divider line with a timestamp label appears between them.

**Detection logic:**

```js
function hasTimeGap(messages, currentIndex) {
  if (currentIndex === 0) return false
  const prev = messages[currentIndex - 1]
  const curr = messages[currentIndex]
  // Compare time periods and hour distances
  // If messages span AM→PM or are 2+ hours apart, show a divider
  return significantTimeDifference(prev.receivedAt, curr.receivedAt)
}
```

**Divider styling:**

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; gap: 12px` |
| Padding | `4px 0` |

**Divider lines (left and right of the label):**

| Property | Value |
|---|---|
| Generated via | `::before` and `::after` pseudo-elements |
| Flex | `1` |
| Height | `1px` |
| Background | `rgba(255, 255, 255, 0.06)` |

**Divider label:**

| Property | Value |
|---|---|
| Font size | `10px` |
| Font weight | `600` |
| Color | `rgba(255, 255, 255, 0.2)` |
| Text transform | `uppercase` |
| Letter spacing | `0.5px` |
| White space | `nowrap` |
| Content | The timestamp of the next message (e.g. "2:30 PM") |

### Collapse Hint

A small centered prompt at the bottom of the thread body indicating the card can be collapsed.

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; justify-content: center; gap: 6px` |
| Padding | `6px 0 0` |
| Color | `rgba(255, 255, 255, 0.25)` |
| Font size | `12px` |
| Font weight | `500` |
| Content | Upward chevron SVG (`16x16px`, `opacity: 0.5`) + "Collapse" text |

### Expanded Card Behavior

When expanded:
- The stacked paper pseudo-elements (`::before`, `::after`) are hidden (`display: none`)
- The card gains `transition: all 0.3s ease` for a smooth height change
- The peek hint is replaced by the full thread body
- The friend header and reply footer remain unchanged

---

## Session Divider

A labeled horizontal line separating unread cards (top) from previously-seen read cards (bottom).

### When to Render

The divider renders once, at the position where the first read card appears — but only if there are unread cards above it.

```js
const firstReadIndex = sortedCards.findIndex(card => !card.isUnreadCard)
const showDivider = firstReadIndex > 0  // Only if there are unreads above
```

### Structure

```
  ─────────── PREVIOUSLY SEEN ───────────
```

### Styling

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; gap: 14px` |
| Padding | `8px 4px 12px` |
| Margin top | `4px` |

**Lines (left and right of label):**

| Property | Value |
|---|---|
| Generated via | `::before` and `::after` pseudo-elements |
| Flex | `1` |
| Height | `1px` |
| Background | `rgba(255, 255, 255, 0.08)` |

**Label:**

| Property | Value |
|---|---|
| Content | "Previously seen" |
| Font size | `11px` |
| Font weight | `600` |
| Color | `rgba(255, 255, 255, 0.2)` |
| Text transform | `uppercase` |
| Letter spacing | `1px` |
| White space | `nowrap` |

---

## Unread Badge on Thread Card

Each unread thread card shows a single orange pill badge in the friend indicator row, right-aligned. The badge shows the count of unread messages in that specific thread card.

**Position:** Inside the friend indicator row, after the friend info, pushed right via `margin-left: auto`.

**See badge-spec.md** for the full visual specification of the `.card-unread-badge` element. It is the same badge used in Feed C.

**Render condition:** Only when `card.unreadCount > 0`.

```
┌─ Friend Indicator Row ──────────────────────────┐
│ [Avatar]  Friend Name     9:15 AM        [ 3 ]  │
│           .friend-info    .message-context .badge │
└─────────────────────────────────────────────────┘
```

---

## Unread Glow Border

Unread thread cards receive a multi-layered box-shadow that creates a warm orange glow around the entire card.

**See badge-spec.md** for the full visual specification of the `.unread-glow-border` treatment.

| Property | Value |
|---|---|
| Box shadow | `0 0 12px rgba(255, 107, 107, 0.3), 0 0 4px rgba(255, 142, 83, 0.2), inset 0 0 0 1px rgba(255, 107, 107, 0.25)` |

**Render condition:** Applied as a CSS class when `card.unreadCount > 0`:

```js
className = `message-card text-only${card.unreadCount > 0 ? ' unread-glow-border' : ''}`
```

Cards in the "previously seen" section never have the glow border or badge.

---

## Interaction: Expand / Collapse

### Tap to Expand

Tapping a collapsed multi-message card expands it to show all messages.

| Property | Value |
|---|---|
| Trigger | `onTap` / `onClick` on the card element |
| Condition | Only cards with `messages.length > 1`. Single-message cards are not tappable. |
| State | A local state variable tracks which card key is currently expanded. Only one card can be expanded at a time. |
| Animation | Card height grows smoothly (`transition: all 0.3s ease`), bubbles stagger in |

### Tap to Collapse

Tapping an expanded card (anywhere on the card) collapses it back to show only the latest message.

### Tap Reply

The Reply button has `stopPropagation` — tapping it does NOT toggle the expand state. Instead, it navigates to the Conversation Screen for that friend.

```js
// Pseudocode
function onReplyTap(event, friend) {
  event.stopPropagation()  // Prevent card expand/collapse
  navigateToConversation(friend)
}
```

### Expand State Management

```js
const [expandedCard, setExpandedCard] = useState(null)  // stores the card.key or null

function toggleExpand(cardKey) {
  setExpandedCard(prev => prev === cardKey ? null : cardKey)
}
```

---

## Feed Composition and Sort Order

### Section 1: Unread Cards (Top)

All thread cards where `isUnreadCard === true`, sorted by the most recent message's `receivedAt` timestamp (newest first).

### Divider

The "Previously seen" divider (renders only if both sections have cards).

### Section 2: Read Cards (Bottom)

All thread cards where `isUnreadCard === false`, sorted by the most recent message's `receivedAt` timestamp (newest first).

### Key Behavior: Same Friend, Two Cards

If Sarah sent 1 message yesterday (which the user read) and 2 new messages today (not yet read), the feed shows:

1. **Sarah (unread)** — Top section. Glow border, badge showing "2", stacked paper, her 2 new messages.
2. **"Previously seen" divider**
3. **Sarah (read)** — Bottom section. No glow, no badge, her 1 old message.

When the user opens Sarah's conversation (from either card's Reply button, or from the Orbit screen), `markConversationAsRead(sarah.id)` is called. On the next feed render:
- Sarah's unread card disappears (all her messages are now read)
- A single Sarah card appears in the "previously seen" section containing all 3 messages

---

## Animations

### Card Entrance

Same as Feed C — staggered slide-up and scale-in:

| Property | Value |
|---|---|
| Duration | `600ms` |
| Easing | `ease` |
| Stagger | `cardIndex * 80ms` |
| Keyframes | From `translateY(30px) scale(0.95) opacity(0)` to `translateY(0) scale(1) opacity(1)` |

### Bubble Entrance (on expand)

| Property | Value |
|---|---|
| Duration | `300ms` |
| Easing | `ease` |
| Stagger | `bubbleIndex * 40ms` |
| Fill | `backwards` |
| Keyframes | From `translateY(8px) scale(0.97) opacity(0)` to `translateY(0) scale(1) opacity(1)` |

### Expand / Collapse Transition

| Property | Value |
|---|---|
| Property | `all` |
| Duration | `300ms` |
| Easing | `ease` |

---

## Relationship to Other Screens

| Screen | How Feed D Relates |
|---|---|
| **Orbit** | The same per-friend `unreadCount` drives both Feed D card badges AND Orbit friend row badges. Opening a conversation from either screen clears both. See badge-spec.md. |
| **Conversation Screen** | Tapping "Reply" on any thread card opens the Conversation Screen for that friend. This calls `markConversationAsRead(friendId)`, which sets `readAt` on all that friend's unread messages. On return, the unread card moves to the "previously seen" section. |
| **NavigationBar** | The Feed tab badge shows `totalUnread` (sum of all unread counts). See badge-spec.md Section 3. |

---

## Visual Design Principles

1. **One card per friend per session** — Instead of 5 separate Mike cards, you see one Mike stack. This reduces clutter while preserving every message inside the expandable thread.
2. **Stacked paper = "there's more"** — The depth effect is an instant visual signal without requiring text. Even at a glance, you can tell which cards have threads.
3. **Expand in place** — The thread opens inside the card, not in a new screen. This keeps context (you can see other cards above/below) and feels lightweight.
4. **Session divider, not dimming** — Read cards look the same as unread cards. The divider label is the only distinction. This avoids making old messages feel "less important" — they're just not new.
5. **Glow border = unread** — Consistent with badge-spec.md. The warm orange glow is the universal "new" indicator across Feed and Orbit.
6. **Time gaps = conversation rhythm** — Inside expanded threads, time dividers show when a friend returned hours later to send more messages. This reveals the natural rhythm of the conversation.
7. **Reply does not expand** — Clear separation of concerns. Tapping the card explores the thread. Tapping Reply starts a conversation. These are different user intents.

---

## Appendix: Token Reference

### Colors

| Token | Value | Usage |
|---|---|---|
| Card background | `var(--glass-bg)` — `rgba(255, 255, 255, 0.08)` | All thread cards |
| Card border | `var(--glass-border)` — `rgba(255, 255, 255, 0.12)` | All thread cards |
| Card glow gradient | `linear-gradient(135deg, #a8edea, #fed6e3)` | Ambient glow at top of card |
| Friend avatar border | `#4ecdc4` (uniform teal) | All avatar borders |
| Unread glow | `0 0 12px rgba(255, 107, 107, 0.3), 0 0 4px rgba(255, 142, 83, 0.2), inset 0 0 0 1px rgba(255, 107, 107, 0.25)` | Unread card border glow |
| Badge gradient | `linear-gradient(135deg, #ff6b6b, #ff8e53)` | Unread count badge |
| Badge glow | `0 0 8px rgba(255, 107, 107, 0.4)` | Badge shadow |
| Bubble background | `rgba(255, 255, 255, 0.04)` | Message bubble (read) |
| Bubble background (unread) | `rgba(255, 255, 255, 0.06)` | Message bubble (unread) |
| Bubble border | `rgba(255, 255, 255, 0.06)` | Message bubble (read) |
| Bubble border (unread) | `rgba(255, 107, 107, 0.15)` | Message bubble (unread) |
| Stacked layer 1 bg | `rgba(255, 255, 255, 0.03)` | First pseudo-element |
| Stacked layer 2 bg | `rgba(255, 255, 255, 0.015)` | Second pseudo-element |
| Divider line | `rgba(255, 255, 255, 0.08)` | Session divider |
| Divider / time gap text | `rgba(255, 255, 255, 0.2)` | Label text |

### Typography

| Element | Size | Weight | Color |
|---|---|---|---|
| Friend name | 16px | 600 | `var(--text-primary)` |
| Message time (header) | 12px | 400 | `var(--text-muted)` |
| Message text (card) | 16px | 400 | `rgba(255, 255, 255, 0.95)` |
| Message text (bubble) | 14px | 400 | `rgba(255, 255, 255, 0.85)` |
| Bubble timestamp | 11px | 400 | `rgba(255, 255, 255, 0.25)` |
| Unread badge count | 11px | 700 | `white` |
| Peek hint | 13px | 500 | `rgba(255, 255, 255, 0.35)` |
| Collapse hint | 12px | 500 | `rgba(255, 255, 255, 0.25)` |
| Session divider label | 11px | 600 | `rgba(255, 255, 255, 0.2)`, uppercase, `letter-spacing: 1px` |
| Time gap label | 10px | 600 | `rgba(255, 255, 255, 0.2)`, uppercase, `letter-spacing: 0.5px` |

### Spacing

| Context | Value |
|---|---|
| Feed container | `padding: 8px 16px 24px`, `gap: 20px` |
| Card border radius | `28px` |
| Friend indicator padding | `18px 20px 12px` |
| Message content padding | `16px 20px` |
| Reply footer padding | `12px 20px 18px` |
| Thread body padding | `4px 20px 8px` |
| Thread body gap | `8px` |
| Bubble padding | `10px 14px` |
| Bubble border radius | `14px` |
| Stacked card extra margin | `margin-bottom: 12px` |
| Stacked layer 1 offset | `left: 6px; right: 6px; bottom: -4px` |
| Stacked layer 2 offset | `left: 12px; right: 12px; bottom: -8px` |
| Session divider padding | `8px 4px 12px` |

### Animations

| Animation | Duration | Easing | Stagger |
|---|---|---|---|
| Card entrance | 600ms | ease | `cardIndex * 80ms` |
| Bubble entrance (`feedDBubbleIn`) | 300ms | ease | `bubbleIndex * 40ms` |
| Expand/collapse transition | 300ms | ease | — |
