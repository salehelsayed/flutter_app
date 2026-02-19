# Unread Badges — Cross-Screen Notification System Spec

**Feature name:** Unread Badges
**Screens affected:** Feed (Feed C), Orbit (Circle 2), NavigationBar (all screens that render it)
**Purpose:** Give users a clear, glanceable understanding of which friends have sent new messages — without requiring them to open every conversation to find out. Badges appear in three coordinated locations and dismiss through natural user actions, not manual clearing.

---

## IMPORTANT: Reuse Existing Components

Before implementing anything in this spec, **audit the existing Flutter codebase** to identify widgets, services, utilities, themes, and patterns that are already built. Do NOT re-implement what already exists.

The spec below describes the design using **platform-agnostic names** (e.g. "NavigationBar", "FeedCard", "FriendRow"). These are logical component names — not file paths. Your job is to find the Flutter equivalents in the project. The following concepts are expected to already exist in the app:

| Concept | What to Look For | What It Does |
|---|---|---|
| Bottom Navigation Bar | A bottom tab bar with Feed / Remember / Orbit tabs. | Search for a shared navigation widget, bottom bar, or tab controller. The Feed tab button is where the nav badge attaches. |
| Feed Message Cards | The card components on the Feed screen that show a friend's avatar, name, timestamp, and message text. | Search for message card, feed card, or timeline item widgets. These cards need the glow border treatment. |
| Friend List Rows | The tappable rows on the Orbit screen showing friend avatar, name, activity, and timestamp. | Search for friend row, contact list, or circle friend widgets. These rows need the unread pill badge. |
| Conversation Screen | A screen showing the full message history between two users. | Search for conversation, chat, or letter screen widgets. Opening this screen is what clears a friend's unread badge. |
| Message Database / Store | The local database or state store where received messages are persisted. | Search for message models, database helpers, or state management for conversations. This is where `receivedAt` and `readAt` timestamps live. |
| Navigation State | The state that tracks which screen the user is currently viewing. | Search for navigation controllers, route observers, or screen state management. Needed for the Feed tab badge dismiss logic. |
| Theme System | A theme/color scheme that screens receive (dark mode, accent colors, glass effects). | Search for `ThemeData`, custom theme classes, or color constant files. |

**Implementation rule:** For every component described in this spec, search the codebase first. If a Flutter equivalent exists, import and reuse it. Only create new code for functionality that is genuinely new (e.g. the unread count computation, badge widgets, glow border styling, dismiss-on-navigation logic).

---

## Feature Overview

The unread badge system communicates new message activity across three locations, each serving a different level of awareness:

1. **Feed cards** — A soft glow border distinguishes cards with new (unread) messages from cards the user has already seen. This answers: "Which messages in my feed are new right now?"
2. **NavigationBar Feed tab** — A small circular badge on the Feed icon shows the total number of messages received since the app was opened. This answers: "Do I have anything new to check on the Feed?"
3. **Orbit friend rows** — A pill badge on each friend's row shows that friend's unread message count. This answers: "Which specific friends have sent me messages I haven't read yet?"

Each badge type has its own dismiss behavior, reflecting the user action that naturally indicates "I've seen this":

| Badge Location | What Clears It | Why |
|---|---|---|
| **Feed card glow border** | Opening the Feed screen (session-based — see Section 3) | The glow means "new since your last visit." Seeing the feed = visiting. |
| **NavigationBar Feed tab badge** | Navigating to any other screen (Remember, Orbit, etc.) | The tab badge is a session-level "you have new stuff on Feed" flag. Once you've been on the Feed and then leave, it means you've seen it. |
| **Orbit friend row badge** | Opening that specific friend's Conversation Screen | Per-friend badges are persistent. They only clear when you actually open the conversation — because that's the only action that proves you've read that friend's messages. |

```
FEED SCREEN (Feed C)                    ORBIT SCREEN
+--------------------------------------+  +--------------------------------------+
| Good evening             [Avatar (9)]|  | [X]                        [Avatar] |
| From your people                     |  |                                     |
|                                      |  |         YOUR INNER CIRCLE           |
| ┌──────────────────────────────────┐ |  |            ( orbital )              |
| │░░ Sarah              9:12 AM [3]│ |  |                                     |
| │░░ Just wanted to let you know... │ |  |  Friends              [QR] [Scan]  |
| │░░                    [Reply]     │ |  |  ┌──────────────────────────────┐   |
| └──────────────────────────────────┘ |  |  │ [Av] Sarah      [3] 2m ago  │   |
|                                      |  |  │      @sarah_1               │   |
| ┌──────────────────────────────────┐ |  |  ├──────────────────────────────┤   |
| │   Mike               11:30 AM   │ |  |  │ [Av] Mike          5m ago > │   |
| │   Remember when we used to...    │ |  |  │      @mike_2               │   |
| │                      [Reply]     │ |  |  ├──────────────────────────────┤   |
| └──────────────────────────────────┘ |  |  │ [Av] Emma      [7] 15m ago │   |
|                                      |  |  │      @emma_3               │   |
| ┌──────────────────────────────────┐ |  |  └──────────────────────────────┘   |
| │░░ Emma                2:45 PM [7]│ |  |                                     |
| │░░ The sunset tonight reminded... │ |  +--------------------------------------+
| │░░                    [Reply]     │ |
| └──────────────────────────────────┘ |   ░░ = glow border on unread cards
|                                      |   [3] = unread pill badge
+--------------------------------------+
|  [Feed •14]  [Remember]  [Orbit]     |   <- Nav bar with Feed tab badge
+--------------------------------------+
```

---

## Data Model

### Message Object (Extended)

Each message in the database needs two timestamps to support the badge system:

```js
{
  id: Number,
  friendId: Number,              // Which friend sent this message
  text: String,                  // Message content
  receivedAt: Date,              // When the message arrived on this device
  readAt: Date | null,           // When the user opened the conversation containing this message
                                 // null = unread
}
```

### Derived Counts

Two computed values drive all badge rendering:

```js
// Per-friend unread count (used for Orbit friend badges and Feed card badges)
function getUnreadCount(friendId) {
  return db.messages
    .filter(msg => msg.friendId === friendId && msg.readAt === null)
    .length
}

// Total feed unreads (used for NavigationBar Feed tab badge)
function getTotalUnreadCount() {
  return db.messages
    .filter(msg => msg.readAt === null)
    .length
}
```

### Marking Messages as Read

Messages are marked as read when the user opens a specific friend's conversation:

```js
// Called when navigating to ConversationScreen for a given friend
function markConversationAsRead(friendId) {
  const now = new Date()
  db.messages
    .filter(msg => msg.friendId === friendId && msg.readAt === null)
    .forEach(msg => { msg.readAt = now })
}
```

This is the **only** action that marks messages as read. Scrolling through the Feed, visiting Orbit, or navigating between tabs does NOT mark individual messages as read — it only affects badge *visibility* (see dismiss behaviors below).

---

## 1. Feed Card Glow Border (Unread Card Treatment)

### What It Does

On the Feed screen (Feed C), message cards from friends who have unread messages are visually distinguished with a subtle orange glow border around the entire card. Cards from friends with no unread messages look normal (the current default appearance). This creates an immediate visual hierarchy: glowing cards demand attention, flat cards have been addressed.

### Visual Spec

**Unread card (has unread messages from this friend):**

```
┌──────────────────────────────────────┐
│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│  <- Soft orange glow around entire card
│░ [Avatar] Sarah        9:12 AM  [3] ░│
│░ Just wanted to let you know I've    ░│
│░ been thinking about you today...    ░│
│░                          [Reply]    ░│
│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
└──────────────────────────────────────┘
```

**Read card (no unread messages from this friend):**

```
┌──────────────────────────────────────┐
│ [Avatar] Mike          11:30 AM      │  <- Normal flat card, no glow, no badge
│ Remember when we used to stay up...  │
│                          [Reply]     │
└──────────────────────────────────────┘
```

#### Glow Border Style

Applied as a CSS class on the message card element when `getUnreadCount(message.friendId) > 0`.

| Property | Value |
|---|---|
| Class name | `.unread-glow-border` (added alongside existing card classes) |
| Box shadow | `0 0 12px rgba(255, 107, 107, 0.3), 0 0 4px rgba(255, 142, 83, 0.2), inset 0 0 0 1px rgba(255, 107, 107, 0.25)` |
| Transition | `box-shadow 0.4s ease` (smooth appearance/disappearance) |

The glow uses the same orange-red color family as all other badges in the system (`#ff6b6b` to `#ff8e53`). The `inset` shadow creates a subtle inner border so the glow doesn't feel like just a blur — it looks like the card itself is emitting light.

**Important:** The glow border is applied to the existing `.message-card` element. No wrapper or additional DOM element is needed. The class is conditionally added:

```js
<article className={`message-card text-only${unreadCount > 0 ? ' unread-glow-border' : ''}`}>
```

#### Unread Count Pill Badge

In addition to the glow border, unread cards also show a small pill badge with the count number inside the card's header area (`.friend-indicator`), right-aligned.

| Property | Value |
|---|---|
| Class name | `.card-unread-badge` |
| Position | Inside `.friend-indicator`, after `.friend-info`, aligned right via `margin-left: auto` |
| Min width | `20px` |
| Height | `20px` |
| Padding | `0 6px` |
| Border radius | `10px` (pill shape) |
| Background | `linear-gradient(135deg, #ff6b6b, #ff8e53)` |
| Color | `white` |
| Font size | `11px` |
| Font weight | `700` |
| Box shadow | `0 0 8px rgba(255, 107, 107, 0.4)` (subtle glow matching the gradient) |
| Flex shrink | `0` |
| Render condition | Only when `unreadCount > 0` |

```
┌─ .friend-indicator ──────────────────────────────────────┐
│ [Avatar 36px]  Sarah          9:12 AM          [  3  ]   │
│                .friend-name   .message-context  .badge   │
└──────────────────────────────────────────────────────────┘
```

### Dismiss Behavior

The glow border is **session-based** — it indicates "new since your last visit to the Feed screen."

| Event | What Happens |
|---|---|
| User opens Feed | Cards with `unreadCount > 0` render with glow border and pill badge |
| User stays on Feed | Glow borders persist — they're a static visual indicator, not time-based |
| User navigates away from Feed | On the next return to Feed, any messages that were visible during the previous visit no longer glow (their `receivedAt` is now older than the last Feed visit) |
| User opens a friend's Conversation | That friend's messages get `readAt` set → their Feed card loses the glow border AND the pill badge (both on Feed and Orbit) |

**Implementation:**

```js
// Store the timestamp of the last Feed screen visit
let lastFeedVisitAt = null  // persisted locally

// When Feed screen mounts or becomes active:
function onFeedScreenOpen() {
  // Cards glow if they have messages received AFTER the last visit
  // After a short delay, update the visit timestamp
  // (This ensures the user sees the glow before it's "consumed")
  lastFeedVisitAt = new Date()
}

// A card should glow if:
function shouldCardGlow(friendId) {
  return getUnreadCount(friendId) > 0
}
```

### Relationship to Other Screens

| Screen | How This Badge Relates |
|---|---|
| **Orbit** | The same `unreadCount` per friend drives both the Feed card glow AND the Orbit friend row badge. Opening a conversation from either screen clears both. |
| **Conversation Screen** | Opening a conversation calls `markConversationAsRead(friendId)`, which sets `readAt` on all that friend's unread messages. This removes the glow from their Feed card and the badge from their Orbit row simultaneously. |
| **NavigationBar** | The Feed tab badge (Section 3) shows the total of all unread counts. As individual conversations are marked read, this total decreases. |

---

## 2. Orbit Friend Row Badges

### What It Does

On the Orbit screen, each friend row in the friends list shows a small pill badge with that friend's unread message count. The badge replaces the chevron arrow on rows that have unreads, making it immediately clear which friends need attention. Friends with no unread messages show the normal chevron.

### Visual Spec

**Friend row with unreads:**

```
┌────────────────────────────────────────────────────┐
│  [Avatar 48px]   Sarah             [3]   2m ago    │
│    (●)           @sarah_1                          │
│                  Sent you a voice note             │
└────────────────────────────────────────────────────┘
```

**Friend row without unreads (unchanged from current design):**

```
┌────────────────────────────────────────────────────┐
│  [Avatar 48px]   Mike              5m ago        > │
│                  @mike_2                           │
│                  Shared a memory                   │
└────────────────────────────────────────────────────┘
```

#### Badge Style (`.friend-unread-badge`)

Positioned inside the `.circle-friend-meta` column, above the timestamp. When present, the chevron arrow is hidden.

| Property | Value |
|---|---|
| Class name | `.friend-unread-badge` |
| Position | Inside `.circle-friend-meta`, above `.circle-friend-time` |
| Min width | `20px` |
| Height | `20px` |
| Padding | `0 6px` |
| Border radius | `10px` (pill shape) |
| Background | `linear-gradient(135deg, #ff6b6b, #ff8e53)` |
| Color | `white` |
| Font size | `11px` |
| Font weight | `700` |
| Box shadow | `0 0 8px rgba(255, 107, 107, 0.4)` |
| Display | `flex; align-items: center; justify-content: center` |
| Render condition | Only when `unreadCount > 0` |

#### Meta Column Layout Change

The `.circle-friend-meta` column renders differently based on unread state:

**When `unreadCount > 0`:**

```
┌─ .circle-friend-meta ─┐
│     [ 3 ]              │  <- .friend-unread-badge (pill)
│     2m ago             │  <- .circle-friend-time (below badge)
│                        │  <- NO chevron
└────────────────────────┘
```

**When `unreadCount === 0`:**

```
┌─ .circle-friend-meta ─┐
│     5m ago             │  <- .circle-friend-time
│       >                │  <- chevron SVG
└────────────────────────┘
```

**Implementation:**

```js
<div className="circle-friend-meta">
  {friend.unreadCount > 0 ? (
    <>
      <span className="friend-unread-badge">{friend.unreadCount}</span>
      <span className="circle-friend-time">{friend.lastSeen}</span>
    </>
  ) : (
    <>
      <span className="circle-friend-time">{friend.lastSeen}</span>
      <svg><!-- chevron --></svg>
    </>
  )}
</div>
```

### Dismiss Behavior

Orbit friend badges are **per-friend** and **persistent** — they only disappear when you open that specific friend's conversation.

| Event | What Happens |
|---|---|
| User opens Orbit screen | Each friend row shows their `unreadCount` as a badge (if > 0) |
| User taps a friend row with a badge | Navigates to that friend's Conversation Screen. `markConversationAsRead(friendId)` is called. When the user returns to Orbit, that friend's badge is gone. |
| User opens conversation from Feed card | Same effect — `markConversationAsRead(friendId)` clears the Orbit badge for that friend too. |
| New message arrives while on Orbit | Badge appears (or count increments) on the corresponding friend row in real-time. |
| User browses Orbit without tapping any rows | All badges persist. Scrolling past a friend does NOT clear their badge. You must open the conversation. |

**Why per-friend persistent?** Because the Orbit is a directory of all your friends. Simply scrolling past a name doesn't mean you've read their messages. The badge should only disappear when you've actually entered the conversation — that's the only meaningful signal that you've engaged with that friend's messages.

---

## 3. NavigationBar Feed Tab Badge

### What It Does

A small circular badge overlapping the top-right corner of the Feed button in the NavigationBar. It shows the total number of unread messages across all friends. This gives the user a constant awareness of "do I have new stuff on the Feed?" regardless of which screen they're currently viewing.

### Visual Spec

```
┌────────────────────────────────────────────┐
│                                            │
│   [Feed •14]    [Remember]    [Orbit]      │
│                                            │
└────────────────────────────────────────────┘
         ^
         └── Small orange circle with "14" overlapping Feed icon
```

#### Badge Style (`.nav-feed-badge`)

Positioned absolute relative to the Feed button element.

| Property | Value |
|---|---|
| Class name | `.nav-feed-badge` |
| Position | `absolute; top: -4px; right: 2px` (relative to the Feed button, which needs `position: relative`) |
| Width | `18px` |
| Height | `18px` |
| Border radius | `50%` (perfect circle) |
| Background | `linear-gradient(135deg, #ff6b6b, #ff8e53)` |
| Color | `white` |
| Font size | `10px` |
| Font weight | `700` |
| Box shadow | `0 0 8px rgba(255, 107, 107, 0.4)` |
| Display | `flex; align-items: center; justify-content: center` |
| Pointer events | `none` (badge should not intercept taps on the Feed button) |
| Render condition | Only when `totalUnreadCount > 0` |

#### NavigationBar Component Change

The NavigationBar component accepts a new prop:

```js
// NavigationBar receives the total unread count
const NavigationBar = ({
  isNavVisible,
  onSwitchView,
  activeTab = 'feed',
  feedUnreadCount = 0,       // NEW: total unread messages for Feed tab badge
}) => {
  // ...

  // Feed button needs position: relative for the badge to anchor to
  <button style={{ ...buttonStyles, position: 'relative' }}>
    {feedUnreadCount > 0 && (
      <span className="nav-feed-badge">{feedUnreadCount}</span>
    )}
    <svg><!-- Feed icon --></svg>
    <span>Feed</span>
  </button>
}
```

#### Prop Threading

Every screen that renders the NavigationBar must pass `feedUnreadCount`. The value is computed once (from the message database) and threaded through:

```js
// Compute once at the app level or in a shared provider
const feedUnreadCount = getTotalUnreadCount()

// Pass to all NavigationBar instances
<NavigationBar feedUnreadCount={feedUnreadCount} ... />
```

| Screen | NavigationBar Usage |
|---|---|
| Feed (Feed C) | `<NavigationBar feedUnreadCount={totalUnread} activeTab="feed" />` |
| Remember (Memories) | `<NavigationBar feedUnreadCount={totalUnread} activeTab="memories" />` |
| 1st Contact D | `<NavigationBar feedUnreadCount={totalUnread} />` |
| Other screens with nav | `<NavigationBar feedUnreadCount={totalUnread} />` |

**Note:** The Orbit screen does NOT render NavigationBar (it has its own floating search trigger instead — see orbit-spec.md Section 10d). So the nav badge is not visible on Orbit.

### Dismiss Behavior

The Feed tab badge has a unique **session-level** dismiss:

| Event | What Happens |
|---|---|
| App launches | `feedUnreadCount` is computed from all messages with `readAt === null`. Badge appears if > 0. |
| User is on Feed screen | Badge is visible on the Feed tab (shows the count even while viewing Feed). |
| User navigates away from Feed | Badge **disappears** — specifically, the nav badge clears when the user leaves the Feed screen. The rationale: the user has "seen" the Feed, so the tab-level nudge is no longer needed. |
| User returns to Feed | If NEW messages arrived while they were away, the badge reappears with the new count. If no new messages arrived, no badge. |
| User opens a conversation (from any screen) | `markConversationAsRead(friendId)` reduces the total count. The badge updates in real-time. If it reaches 0, the badge disappears. |

**Implementation:**

```js
// Track whether the user has visited the Feed this session
const [feedSeenAt, setFeedSeenAt] = useState(null)

// When Feed screen becomes active
function onFeedEnter() {
  setFeedSeenAt(new Date())
}

// The nav badge shows:
// - Total messages received AFTER feedSeenAt (if feedSeenAt exists)
// - Total messages with readAt === null (if feedSeenAt is null, i.e. first visit)
function getNavBadgeCount() {
  if (feedSeenAt) {
    return db.messages
      .filter(msg => msg.receivedAt > feedSeenAt && msg.readAt === null)
      .length
  }
  return getTotalUnreadCount()
}
```

**Simplified alternative** (if the timestamp approach is too complex for initial implementation):

```js
// Simple version: badge = total unreads, clears to 0 when user navigates AWAY from Feed
// Re-appears only when new messages arrive
```

---

## 4. Shared Badge Visual Language

All three badge types share the same visual DNA so they read as a unified notification system:

### Color Palette

| Token | Value | Usage |
|---|---|---|
| Badge gradient start | `#ff6b6b` | Left/top of all badge backgrounds |
| Badge gradient end | `#ff8e53` | Right/bottom of all badge backgrounds |
| Badge gradient | `linear-gradient(135deg, #ff6b6b, #ff8e53)` | All badge backgrounds (pills and circles) |
| Badge glow | `rgba(255, 107, 107, 0.4)` | `box-shadow` on all badges |
| Badge text | `white` (#ffffff) | Count numbers on all badges |
| Card glow outer | `rgba(255, 107, 107, 0.3)` | Outer glow on unread Feed cards |
| Card glow mid | `rgba(255, 142, 83, 0.2)` | Mid glow on unread Feed cards |
| Card glow inner | `rgba(255, 107, 107, 0.25)` | Inset border on unread Feed cards |

### Typography

| Context | Size | Weight |
|---|---|---|
| Feed card pill badge | `11px` | `700` |
| Orbit friend row pill badge | `11px` | `700` |
| NavigationBar circle badge | `10px` | `700` |

### Sizing

| Badge Type | Shape | Dimensions |
|---|---|---|
| Feed card pill (`.card-unread-badge`) | Pill | min-width `20px`, height `20px`, padding `0 6px`, border-radius `10px` |
| Orbit friend pill (`.friend-unread-badge`) | Pill | min-width `20px`, height `20px`, padding `0 6px`, border-radius `10px` |
| NavigationBar circle (`.nav-feed-badge`) | Circle | `18x18px`, border-radius `50%` |

### Existing Badge Reference

The app already has a `.unread-badge` class on the header avatar in Feed C. This existing badge uses the same gradient:

```css
/* Already exists in the codebase — reference, do not duplicate */
.unread-badge {
  background: linear-gradient(135deg, #ff6b6b, #ff8e53);
  border-radius: 50%;
  font-size: 11px;
  font-weight: 600;
  color: white;
}
```

The new badge classes follow the same visual pattern but are purpose-built for their specific placements.

---

## 5. State Flow Diagram

This shows the complete lifecycle of unread state across all three badge locations:

```
NEW MESSAGE ARRIVES (from friend Sarah)
         │
         ▼
┌─────────────────────────────────┐
│  db.messages.insert({           │
│    friendId: sarah.id,          │
│    receivedAt: now,             │
│    readAt: null          ← KEY │
│  })                             │
└─────────┬───────────────────────┘
          │
          ├──────────────────────────────────────────────┐
          │                                              │
          ▼                                              ▼
┌──────────────────────┐                    ┌──────────────────────┐
│ FEED SCREEN          │                    │ ORBIT SCREEN         │
│                      │                    │                      │
│ Sarah's card:        │                    │ Sarah's row:         │
│  • Glow border ON    │                    │  • Badge shows [3]   │
│  • Pill badge [3]    │                    │  • Chevron hidden    │
│                      │                    │                      │
│ Nav bar:             │                    │ (No nav bar on Orbit)│
│  • Feed tab [14]     │                    │                      │
└──────────┬───────────┘                    └──────────┬───────────┘
           │                                           │
           │         USER TAPS SARAH'S CARD            │
           │         OR SARAH'S ROW                    │
           │                    │                      │
           │                    ▼                      │
           │     ┌──────────────────────────┐          │
           │     │ CONVERSATION SCREEN      │          │
           │     │ (Sarah)                  │          │
           │     │                          │          │
           │     │ markConversationAsRead() │          │
           │     │ → Sarah's readAt = now   │          │
           │     └──────────────┬───────────┘          │
           │                    │                      │
           │                    ▼                      │
           │     ┌──────────────────────────┐          │
           │     │ ALL BADGES UPDATE:       │          │
           │     │                          │          │
           │     │ • Feed card glow: OFF    │◄─────────┘
           │     │ • Feed card pill: GONE   │
           │     │ • Orbit row badge: GONE  │
           │     │ • Nav total: 14→11       │
           │     └──────────────────────────┘
           │
           │    USER NAVIGATES TO REMEMBER/ORBIT
           │                    │
           │                    ▼
           │     ┌──────────────────────────┐
           │     │ Nav Feed tab badge:      │
           │     │ CLEARS (session-seen)    │
           │     │                          │
           │     │ Friend badges: UNCHANGED │
           │     │ (only conversation       │
           │     │  clears those)           │
           │     └──────────────────────────┘
```

---

## 6. Animations

### 6a. Badge Appearance

When a badge first renders (e.g. new message arrives, or screen loads with existing unreads):

| Property | Value |
|---|---|
| Animation | Scale from `0` to `1` with slight overshoot |
| Duration | `300ms` |
| Easing | `cubic-bezier(0.34, 1.56, 0.64, 1)` (spring overshoot) |
| Keyframes | `0%: scale(0), opacity(0)` → `100%: scale(1), opacity(1)` |

```css
@keyframes badgeAppear {
  from {
    transform: scale(0);
    opacity: 0;
  }
  to {
    transform: scale(1);
    opacity: 1;
  }
}
```

### 6b. Badge Count Update

When the count number changes (e.g. 3 → 4):

| Property | Value |
|---|---|
| Animation | Quick scale pulse |
| Duration | `200ms` |
| Easing | `ease-out` |
| Keyframes | `scale(1)` → `scale(1.2)` → `scale(1)` |

### 6c. Badge Disappearance

When `unreadCount` transitions from > 0 to 0:

| Property | Value |
|---|---|
| Animation | Scale down and fade out |
| Duration | `250ms` |
| Easing | `ease-in` |
| Keyframes | `scale(1), opacity(1)` → `scale(0), opacity(0)` |

### 6d. Glow Border Transition

The Feed card glow border uses a CSS transition, not a keyframe animation:

| Property | Value |
|---|---|
| Property | `box-shadow` |
| Duration | `400ms` |
| Easing | `ease` |

This means the glow fades in/out smoothly when the `.unread-glow-border` class is added/removed.

---

## 7. Edge Cases

| Scenario | Behavior |
|---|---|
| User has 0 friends | No badges anywhere. Feed shows empty state, Orbit shows empty list. |
| User has friends but 0 unread messages | No badges, no glow borders. Everything renders in its default state. |
| Badge count exceeds 99 | Show "99+" (truncate). Badge pill width expands to fit but uses `max-width` to prevent overflow. |
| New message arrives while user is on Feed | The new card (if visible) gains the glow border. The nav badge count increments. |
| New message arrives while user is on Orbit | The corresponding friend row's badge count increments (or appears if it was 0). |
| User opens conversation that has 0 unreads | Nothing changes. `markConversationAsRead()` is a no-op if there are no unread messages. |
| Multiple messages from the same friend | Badge shows total count (e.g. 3 messages from Sarah = badge shows "3"), not "1 conversation." |
| User force-quits the app | All unread state is persisted in the local database. On next launch, badges reappear with correct counts. |
| User has unreads but message cards haven't loaded yet | Badge counts should be derived from the database, not from rendered cards. Show badges as soon as the count query resolves, even if the UI is still loading. |

---

## Appendix: Token Reference

### CSS Classes

| Class | Element | Screen |
|---|---|---|
| `.unread-glow-border` | Message card (`<article>`) | Feed (Feed C) |
| `.card-unread-badge` | Pill badge (`<span>`) | Feed (Feed C), inside `.friend-indicator` |
| `.friend-unread-badge` | Pill badge (`<span>`) | Orbit, inside `.circle-friend-meta` |
| `.nav-feed-badge` | Circle badge (`<span>`) | NavigationBar, inside Feed `<button>` |

### Colors

| Token | Value | Usage |
|---|---|---|
| Badge gradient | `linear-gradient(135deg, #ff6b6b, #ff8e53)` | All badge backgrounds |
| Badge glow shadow | `0 0 8px rgba(255, 107, 107, 0.4)` | All badge box-shadows |
| Badge text | `#ffffff` | All badge text |
| Card glow (full) | `0 0 12px rgba(255, 107, 107, 0.3), 0 0 4px rgba(255, 142, 83, 0.2), inset 0 0 0 1px rgba(255, 107, 107, 0.25)` | Unread Feed card box-shadow |

### Typography

| Element | Size | Weight | Color |
|---|---|---|---|
| Card pill badge count | 11px | 700 | white |
| Friend row pill badge count | 11px | 700 | white |
| Nav circle badge count | 10px | 700 | white |

### Sizing

| Element | Size |
|---|---|
| Card pill badge | min-width 20px, height 20px, border-radius 10px |
| Friend row pill badge | min-width 20px, height 20px, border-radius 10px |
| Nav circle badge | 18x18px, border-radius 50% |

### Animations

| Animation | Duration | Easing | Usage |
|---|---|---|---|
| `badgeAppear` | 300ms | `cubic-bezier(0.34, 1.56, 0.64, 1)` | Badge first render |
| Badge count pulse | 200ms | `ease-out` | Count number changes |
| Badge disappear | 250ms | `ease-in` | Count reaches 0 |
| Glow border transition | 400ms | `ease` | Card gains/loses unread state |

---

## Design Rationale

| Decision | Why |
|---|---|
| Glow border, not left accent bar | The glow border wraps the entire card, making unread cards feel "alive" — like they're emitting energy. A left bar is a convention from email/Slack; the glow feels more native to this app's glassmorphic, ambient aesthetic. |
| Three badge locations, not one | Each location serves a different user intent. The nav badge says "check the Feed." The Feed glow says "these are new." The Orbit badges say "this friend needs your attention." Together they create awareness at every level without requiring the user to memorize anything. |
| Nav badge clears on screen change | The nav badge answers "is there new stuff on Feed?" Once you've been to the Feed and then navigated away, you've answered that question. Keeping the badge after you've seen the Feed would create badge fatigue. |
| Friend badges only clear on conversation open | Scrolling past a friend's name in a list is not the same as reading their messages. The badge should persist until you've actually engaged with that friend's conversation. This respects the friend's effort in reaching out. |
| Shared orange-red gradient | One visual language for "unread" across the entire app. The warm orange stands out against the cool dark/teal theme without clashing. It's urgent but not alarming (not pure red). |
| Pill shape for counts, circle for totals | Pills expand to fit multi-digit numbers (e.g. "12") gracefully. The nav badge is always a circle because it's small and the total is usually 1-2 digits. |
| Glow border + pill badge together | The glow catches your eye while scrolling (peripheral vision). The pill tells you the exact count (focused attention). They serve different cognitive purposes and work best together. |
| No auto-dismiss timers | We considered clearing badges after the card is visible for 2 seconds, but rejected it. Badges should reflect state, not time. If you haven't read the message, the badge stays. Simple, honest, predictable. |
