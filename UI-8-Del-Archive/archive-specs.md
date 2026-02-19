# Archive & More — Swipe Actions on Friend Rows Spec

**Feature name:** Archive & More (Swipe Actions)
**Screens affected:** Orbit (Friend List)
**Purpose:** Let users declutter their active friends list by archiving friends they don't actively communicate with — without unfriending or losing the connection. Archiving silences notifications from that friend while still receiving their messages. The user can access all archived friends through a dedicated filter tab and unarchive them at any time.

---

## IMPORTANT: This Spec Targets an Existing Flutter Application

This spec was designed from a React prototype (kitchen/landing screen) used for visual exploration. **The actual application is built in Flutter/Dart.** The screen names, file names, class names, and widget names in your Flutter project will NOT match the names used in this spec.

**Before writing any code, you MUST:**

1. **Audit the existing Flutter codebase thoroughly.** Search for every concept listed in the table below. Many of these widgets, services, models, and patterns already exist — possibly under different names.
2. **Do NOT create new files, widgets, models, or services** for things that are already implemented. Reuse, extend, or modify what's there.
3. **Do NOT rename or restructure** existing code to match this spec's naming. Adapt the spec to fit your project's conventions, not the other way around.

The spec below describes the design using **platform-agnostic names** (e.g. "FriendRow", "Orbit Screen"). These are logical component names — not file paths. Your job is to find the Flutter equivalents in the project.

### Lookup Table — Find These in Your Codebase First

| Concept | What to Search For | What This Spec Calls It |
|---|---|---|
| Orbit Screen / Friend List | The screen with the orbital visualization at the top and a scrollable list of all friends below. Search for orbit, circle, friend list, contacts screen widgets. | "Orbit Screen" |
| Friend Row Widget | The tappable row showing friend avatar, name, username, activity, and timestamp. Search for friend row, contact row, circle friend, user tile widgets. | "FriendRow" |
| Friend Data Model | The model/entity representing a friend with fields like name, username, avatar, status, lastActivity. Search for friend model, contact model, user model, peer model classes. | "Friend object" |
| Friend Database / Store | The local database or state store where friends are persisted. Search for friend repository, contact store, database helpers, Hive/Isar/SQLite tables, provider/bloc/riverpod state. | "db.friends" |
| Notification Service | The service that handles push notifications for incoming messages. Search for notification manager, push service, FCM handler, local notification helper. | "notificationService" |
| Conversation Screen | The screen showing the full message history between two users. Search for conversation, chat, letter, message thread screen widgets. | "Conversation Screen" |
| Theme System | A theme/color scheme that screens receive (dark mode, accent colors, glass effects). Search for `ThemeData`, custom theme extensions, color constant files, design token files. | "theme" |
| Swipe / Dismissible Widgets | Flutter has built-in `Dismissible` and packages like `flutter_slidable`. Check if any swipe-to-action pattern is already implemented anywhere in the app. | "SwipeableFriendRow" |
| Tab / Filter Widgets | Segmented controls, toggle buttons, or filter chips that already exist. Search for `ToggleButtons`, `SegmentedButton`, `CupertinoSlidingSegmentedControl`, or custom tab widgets. | "Filter Toggle" |

**Implementation rule:** For every component described in this spec, search the codebase first. If a Flutter equivalent exists, import and reuse it. Only create new code for functionality that is genuinely new (e.g. the swipe gesture wrapper, archive state field, filter toggle UI, notification silencing logic).

**Flutter-specific note:** For the swipe gesture, consider using Flutter's `Dismissible` widget, the `flutter_slidable` package, or a custom `GestureDetector` with `AnimationController`. Choose whichever approach is most consistent with patterns already in the project. If the project already uses a specific gesture/animation library, use that.

---

## Feature Overview

This feature introduces two interconnected capabilities on the Orbit screen:

1. **Swipe Actions** — Swiping a friend row to the left reveals two circular action buttons ("More" and "Archive") that slide into view from behind the card. This is the primary interaction for managing friends.
2. **Filter Toggle** — A segmented control below the "Friends" header lets the user switch between "All" (active friends) and "Archived" (archived friends). This is how the user retrieves and manages their archived friends.

### What "Archive" Means

Archiving a friend is **NOT** the same as blocking, muting, or unfriending:

| Action | Still Friends? | Receive Messages? | Get Notifications? | Visible in Active List? |
|---|---|---|---|---|
| **Archive** | Yes | Yes | **No** | No (moved to Archived tab) |
| Block | No | No | No | No |
| Mute | Yes | Yes | No | Yes (stays in list) |
| Unfriend | No | No | No | No |

**Key distinction:** Archiving moves the friend out of the main list and silences notifications, but the friendship and all message history are fully preserved. Messages from archived friends still arrive in the database — the user simply won't be interrupted by them. The friend has no way to know they've been archived.

Think of it like email archiving: the conversation isn't deleted, it's just moved out of the inbox so it doesn't demand attention.

---

## 1. Swipe-to-Reveal Actions (Active Friends)

### What It Does

On the Orbit screen, each friend row in the "All" tab is swipeable. When the user swipes a friend row to the left, the card content slides left to reveal two circular action buttons sitting behind it: **"More"** (left) and **"Archive"** (right).

### Visual Spec

**At rest (no swipe) — card looks completely normal:**

```
┌────────────────────────────────────────────────────┐
│  [Avatar 48px]   Sarah             [3]   2m ago    │
│    (●)           @sarah_1                          │
│                  Sent you a voice note             │
└────────────────────────────────────────────────────┘
```

The swipe actions are completely invisible. No background color, no peeking buttons — the card is identical to its appearance without this feature.

**During swipe (finger dragging left):**

```
┌─────────────────────────────────────────┐
│  [Avatar]  Sarah         [3]  2m ago   │──┐
│    (●)     @sarah_1                    │  │   (More)   (Archive)
│            Sent you a voice note       │  │    ⋮          📦
└─────────────────────────────────────────┘──┘
                                             ↑ Action buttons slide in
                                               from behind the card
```

**Fully swiped (snapped open):**

```
┌──────────────────────────────────┐
│  [Avatar]  Sarah      [3] 2m ago│    ( ⋮ )      ( 📦 )
│    (●)     @sarah_1             │    More       Archive
│            Sent you a voice...  │   (gray)     (orange)
└──────────────────────────────────┘
```

### Gesture Mechanics

The swipe follows iOS Mail-style physics:

| Property | Value |
|---|---|
| Gesture direction | Left only (horizontal). Right swipe does nothing. |
| Action area total width | `148px` (two 62px buttons + 8px gap + 8px padding on each side) |
| Snap threshold | 50% of action width (`74px`). If the user drags past this, the row snaps open. Below it, the row snaps back closed. |
| Rubber band | If the user drags beyond the action width, the excess is dampened by 70% (`over * 0.3`), creating the characteristic iOS bounce-back feel. |
| Easing (snap animation) | `cubic-bezier(0.25, 0.46, 0.45, 0.94)` — smooth deceleration |
| Snap duration | `300ms` |
| Vertical scroll lock | If the initial gesture is more vertical than horizontal (detected by comparing `|dx|` vs `|dy|` in the first 8px of movement), the swipe is cancelled and the list scrolls normally. |

**State transitions:**

```
IDLE ──(swipe left > 8px)──▶ DRAGGING ──(release past threshold)──▶ OPEN
                                │                                      │
                                │ (release before threshold)           │ (tap outside / swipe right)
                                ▼                                      ▼
                              IDLE ◀──────────────────────────────── IDLE
```

**Only one row open at a time:** If the user swipes a new row while another is already open, the previously open row should snap closed before the new one opens.

### Action Buttons

Both buttons are circular with icon + label:

#### "More" Button (Left)

| Property | Value |
|---|---|
| Shape | Circle, `62px` diameter |
| Background | `linear-gradient(135deg, #64748b, #475569)` (slate gray) |
| Icon | Vertical three-dot ellipsis (⋮) — 16x16px, white, stroke-width 2 |
| Label | "More" — 10px, weight 600, white, 3px below icon |
| Tap behavior | Closes the swipe row. (In the future, this will open a context menu with options like "Mute", "Block", "Report", etc. For now, it simply snaps the row closed.) |

#### "Archive" Button (Right)

| Property | Value |
|---|---|
| Shape | Circle, `62px` diameter |
| Background | `linear-gradient(135deg, #f59e0b, #f97316)` (amber-to-orange) |
| Icon | Archive box — 16x16px, white, stroke-width 2 (box with horizontal line in middle) |
| Label | "Archive" — 10px, weight 600, white, 3px below icon |
| Tap behavior | Archives the friend (see Section 3 for the archive flow) |

#### Button Reveal Animation

The action buttons don't just appear — they slide in from behind the card with a subtle parallax effect:

| Property | Value |
|---|---|
| Actions container | Positioned absolute, right-aligned behind the card. Has `border-radius: 16px` and `overflow: hidden` to match card shape. |
| Container transform | Starts at `translateX(ACTION_WIDTH)` (fully hidden off-right). Tracks with the card drag, moving toward `translateX(0)` as the card slides. |
| Individual button parallax | Each button has an additional `translateX(offset * 0.15)` that resolves to `0` when fully revealed. This creates a subtle "catching up" effect as the buttons appear — they slightly lag behind the container, making the reveal feel organic rather than rigid. |
| Pointer events | Disabled (`pointer-events: none`) until the swipe begins. Enabled when the wrapper enters the `swiping` state. This prevents accidental taps on hidden buttons. |
| Drag performance | During active dragging, all `transition` properties are set to `none` for instant 1:1 tracking. The spring transitions only apply on release (snap). |

---

## 2. Swipe-to-Reveal Actions (Archived Friends)

### What It Does

In the "Archived" tab, friend rows are also swipeable — but they reveal a single action: **"Unarchive"**.

### Visual Spec

**Fully swiped open (Archived tab):**

```
┌──────────────────────────────────┐
│  [Avatar]  Sarah         2m ago │       (  ↩  Unarchive  )
│            @sarah_1             │        (teal gradient)
│            Sent you a voice...  │
└──────────────────────────────────┘
```

#### "Unarchive" Button

| Property | Value |
|---|---|
| Shape | Pill / rounded rectangle, `116px` wide, `44px` tall, `border-radius: 999px` |
| Background | `linear-gradient(135deg, #10b981, #06b6d4)` (green-to-teal) |
| Icon | Return arrow (↩) — 16x16px, white, stroke-width 2 |
| Label | "Unarchive" — 10px, weight 600, white, next to icon |
| Action area width | `132px` (smaller than the active-row actions since it's a single button) |
| Tap behavior | Unarchives the friend — moves them back to the "All" tab immediately |

**Note:** Archived friend rows do NOT show unread badges, even if the archived friend has sent messages. The timestamp and chevron are shown as normal.

---

## 3. Archive Flow

### Step-by-Step

When the user taps the "Archive" button on a swiped-open friend row:

```
1. BUTTON TAP
   │
   ▼
2. SWIPE ROW SNAPS CLOSED
   │  The card slides back to its normal position (300ms spring)
   │
   ▼
3. COLLAPSE ANIMATION BEGINS
   │  The entire row animates out:
   │  • max-height: 100px → 0       (350ms ease-in)
   │  • opacity: 1 → 0              (300ms ease-in)
   │  • vertical margins collapse    (350ms ease-in)
   │
   ▼
4. FRIEND MOVED TO ARCHIVED STATE
   │  After the animation completes (~380ms):
   │  • Friend's `isArchived` field is set to `true` in the database
   │  • Friend is removed from the "All" list
   │  • Friend appears in the "Archived" list
   │  • Archived tab count badge updates
   │  • Active tab count updates
   │
   ▼
5. NOTIFICATION SILENCING ACTIVATES
   │  The notification service checks `isArchived` before showing
   │  push notifications. Archived friends are excluded.
   │
   ▼
6. DONE
   The friend is archived. Their row is gone from the active list.
   Messages still arrive silently in the database.
```

### Collapse Animation Detail

| Property | From | To | Duration | Easing |
|---|---|---|---|---|
| `max-height` | `100px` | `0` | `350ms` | `ease-in` |
| `opacity` | `1` | `0` | `300ms` | `ease-in` |
| `margin-top` | normal | `0` | `350ms` | `ease-in` |
| `margin-bottom` | normal | `0` | `350ms` | `ease-in` |
| `overflow` | — | `hidden` | — | (set immediately) |

The animation is triggered by adding an `archive-out` class to the row wrapper element. The state change (moving the friend to archived) happens after the animation completes, not before — so the user sees the smooth exit before the list re-renders.

---

## 4. Unarchive Flow

### Step-by-Step

When the user taps the "Unarchive" button while in the Archived tab:

```
1. BUTTON TAP
   │
   ▼
2. SWIPE ROW SNAPS CLOSED
   │  The card slides back to its normal position
   │
   ▼
3. FRIEND MOVED TO ACTIVE STATE
   │  • Friend's `isArchived` field is set to `false`
   │  • Friend is removed from the "Archived" list
   │  • Friend reappears in the "All" list
   │  • Both tab counts update
   │
   ▼
4. NOTIFICATION SILENCING DEACTIVATES
   │  The friend is once again included in push notification
   │  delivery. Future messages will trigger notifications.
   │
   ▼
5. DONE
   The friend is back in the active list.
```

**Note:** Unlike archiving, unarchiving does NOT play the collapse animation — the row simply disappears from the Archived list on the next render. If the user switches to the "All" tab, the friend appears in its normal sorted position.

---

## 5. Filter Toggle (All / Archived)

### What It Does

A segmented control sits below the "Friends" header on the Orbit screen. It lets the user switch between viewing active friends and archived friends without leaving the screen.

### Visual Spec

```
Friends                          [QR]  [Scan]
┌──────────────────────────────────────────┐
│  [ All  100 ]  [ Archived  12 ]          │
└──────────────────────────────────────────┘
```

The toggle sits between the "Friends" header row (with QR/Scan buttons) and the friend list. It is hidden when the search overlay is active.

#### Toggle Container (`.friends-filter-toggle`)

| Property | Value |
|---|---|
| Layout | Horizontal flex, `gap: 2px` |
| Background | `rgba(255, 255, 255, 0.06)` |
| Border | `1px solid rgba(255, 255, 255, 0.08)` |
| Border radius | `10px` |
| Padding | `3px` (inner padding around buttons) |

#### Toggle Button (`.friends-filter-btn`)

| Property | Inactive | Active |
|---|---|---|
| Background | `transparent` | `rgba(255, 255, 255, 0.12)` |
| Text color | `rgba(255, 255, 255, 0.4)` | `rgba(255, 255, 255, 0.95)` |
| Font size | `13px` | `13px` |
| Font weight | `600` | `600` |
| Padding | `5px 14px` | `5px 14px` |
| Border radius | `8px` | `8px` |
| Box shadow | none | `0 1px 4px rgba(0, 0, 0, 0.2)` |
| Transition | `all 0.25s ease` | `all 0.25s ease` |

#### Count Badge (`.friends-filter-count`)

A small inline count badge appears next to each tab label:

| Property | Value |
|---|---|
| Shape | Pill, `border-radius: 9px` |
| Min width | `18px` |
| Height | `18px` |
| Padding | `0 5px` |
| Font size | `11px` |
| Font weight | `700` |
| Margin left | `5px` |
| Background (inactive) | `rgba(255, 255, 255, 0.1)` |
| Background (active) | `rgba(255, 255, 255, 0.15)` |

**Rendering rules:**
- "All" tab always shows its count badge (number of active friends)
- "Archived" tab only shows a count badge when `archivedCount > 0`. When there are no archived friends, the badge is hidden to keep the tab clean.

### Tab Behavior

| Tab | What It Shows |
|---|---|
| **All** (default) | All friends that are NOT archived. This is the default view when the Orbit screen opens. |
| **Archived** | Only friends that ARE archived. Shows the archived empty state if no friends are archived. |

Switching tabs filters the friend list instantly — no loading state, no animation. The search function (when active) searches within the currently selected tab only.

### Archived Empty State

When the "Archived" tab is selected but no friends are archived:

```
┌──────────────────────────────────────────┐
│                                          │
│             [ 📦 ]                       │
│                                          │
│     No archived friends yet.             │
│     Swipe left on a friend to            │
│     archive them.                        │
│                                          │
└──────────────────────────────────────────┘
```

| Element | Style |
|---|---|
| Icon container | `48px` square, `border-radius: 14px`, `background: rgba(255, 255, 255, 0.06)` |
| Icon | Archive box, `24x24px`, `color: rgba(255, 255, 255, 0.25)` |
| Text | `14px`, `color: rgba(255, 255, 255, 0.35)`, `line-height: 1.4`, centered |
| Padding | `40px` top/bottom, `20px` sides |

---

## 6. Data Model

### Friend Object (Extended)

Each friend in the database needs one new field:

```js
{
  id: Number,
  name: String,
  username: String,
  avatar: String | null,
  status: 'online' | 'offline',
  lastActivity: String,
  lastSeen: String,
  isArchived: Boolean,          // NEW — default: false
  archivedAt: Date | null,      // NEW — when the friend was archived, null if not archived
}
```

### Archive / Unarchive Operations

```js
// Archive a friend
function archiveFriend(friendId) {
  db.friends.update(friendId, {
    isArchived: true,
    archivedAt: new Date(),
  })
}

// Unarchive a friend
function unarchiveFriend(friendId) {
  db.friends.update(friendId, {
    isArchived: false,
    archivedAt: null,
  })
}
```

### Derived Lists

```js
// Active friends (shown in "All" tab)
function getActiveFriends() {
  return db.friends.filter(f => !f.isArchived)
}

// Archived friends (shown in "Archived" tab)
function getArchivedFriends() {
  return db.friends.filter(f => f.isArchived)
}

// Count for tab badges
function getArchivedCount() {
  return db.friends.filter(f => f.isArchived).length
}
```

---

## 7. Notification Behavior for Archived Friends

This is the core behavioral difference of archiving. When a friend is archived:

| Event | Behavior |
|---|---|
| **Archived friend sends a message** | Message is received and stored in the local database. NO push notification is shown. NO sound plays. NO badge count increments on any screen. The message exists silently. |
| **User opens archived friend's conversation** | All messages (including those received while archived) are visible. The conversation looks and works identically to a normal conversation. |
| **User unarchives the friend** | Any unread messages from that friend that accumulated while archived now become "visible" to the badge system — unread badges appear on the Feed, Orbit row, and Nav bar as if the messages just arrived. Future messages trigger notifications normally. |

### Implementation

The notification service should check `isArchived` before deciding whether to show a notification:

```js
// Called when a new message arrives
function onMessageReceived(message) {
  // Always store the message
  db.messages.insert(message)

  // Check if the sender is archived
  const friend = db.friends.get(message.friendId)
  if (friend.isArchived) {
    // Silently store — do NOT notify
    return
  }

  // Friend is not archived — show notification as normal
  notificationService.show({
    title: friend.name,
    body: message.text,
    // ...
  })
}
```

### Relationship to Unread Badges (see badge-spec.md)

Archived friends are **excluded from all badge calculations**:

| Badge Location | Effect of Archive |
|---|---|
| Feed card glow border | Archived friend's messages do NOT appear on the Feed at all. Their cards are filtered out. |
| NavigationBar Feed tab badge | Archived friend's unread messages are NOT counted in the total. |
| Orbit friend row badge | Archived friend's row is only visible in the "Archived" tab, and it does NOT show an unread badge even if messages exist. |

When a friend is **unarchived**, their unread messages re-enter the badge calculations. Feed cards reappear, the nav badge total increases, and the Orbit row badge shows the count.

---

## 8. Interaction with Other Features

### Orbital Visualization

Archived friends are **removed from the orbital rings** at the top of the Orbit screen. Only active friends appear in the Inner Circle visualization. If an Inner Circle friend is archived, the orbital re-calculates to fill the gap with the next active friend.

### Search

The search function on the Orbit screen searches within the **currently active tab**:
- If "All" is selected, search filters active friends only
- If "Archived" is selected, search filters archived friends only

A search result for an archived friend shows the same row design but with the "Unarchive" swipe action (not "More" + "Archive").

### Feed Screen

Archived friends' messages do NOT appear on the Feed screen. When a friend is archived, any existing Feed cards from that friend should be filtered out of the Feed. When unarchived, their cards reappear.

### Conversation Access

Archiving does NOT prevent the user from opening an archived friend's conversation. The user can:
1. Go to the "Archived" tab
2. Tap the archived friend's row
3. Open their full conversation history
4. Read and reply to messages normally

Sending a reply to an archived friend does NOT automatically unarchive them. The user must explicitly swipe → Unarchive to restore the friend to the active list and re-enable notifications.

---

## 9. Animations Summary

| Animation | Trigger | Duration | Easing | Description |
|---|---|---|---|---|
| Card slide (drag) | Touch/drag | 1:1 tracking | `none` (during drag) | Card follows finger exactly, no transition delay |
| Card snap open | Release past threshold | `300ms` | `cubic-bezier(0.25, 0.46, 0.45, 0.94)` | Card snaps to fully open position |
| Card snap closed | Release before threshold | `300ms` | `cubic-bezier(0.25, 0.46, 0.45, 0.94)` | Card snaps back to resting position |
| Button parallax | During drag | 1:1 tracking | `none` (during drag) | Buttons slide in with 15% parallax offset |
| Button parallax (snap) | Release | `300ms` | `cubic-bezier(0.25, 0.46, 0.45, 0.94)` | Buttons settle into final position |
| Archive collapse | After Archive tap | `350ms` | `ease-in` | Row collapses (height, opacity, margins) |
| Unarchive entrance | After state change | `350ms` | `ease-out` | Row expands into place (height, opacity) |
| Filter tab switch | Tab tap | `250ms` | `ease` | Background/color transition on active tab |
| Rubber band | Drag past action width | 1:1 tracking | `none` | Excess drag dampened by 70% |

---

## 10. Edge Cases

| Scenario | Behavior |
|---|---|
| User has 0 friends | No filter toggle shown. Empty friends list state (existing behavior). |
| User has 0 archived friends | "Archived" tab shows empty state with archive icon and instructional text. The tab count badge is hidden. |
| User archives all friends | "All" tab shows empty list. "Archived" tab shows all friends. Orbital visualization is empty. |
| User swipes during scroll | If the initial gesture is more vertical than horizontal, the swipe is cancelled and the list scrolls. The row does not open. |
| User swipes one row while another is open | The previously open row snaps closed, then the new row begins tracking the swipe. |
| Rapid archive/unarchive | Each action is independent. Archiving then immediately switching to "Archived" tab shows the friend. Unarchiving and switching to "All" shows them back. |
| Archive an Inner Circle friend | The friend is removed from the orbital rings. The orbital re-renders with remaining active friends. |
| New message from archived friend while on Orbit | No visual change. The message is stored silently. If the user opens the Archived tab and taps the friend, they'll see the new message in the conversation. |
| App restart with archived friends | `isArchived` state is persisted. On next launch, the filter defaults to "All" tab. Archived friends remain archived. |
| Search while on Archived tab | Search filters the archived friends list only. No results shows the "No friends matching..." empty state. |

---

## 11. "More" Button — Future Scope

The "More" button currently closes the swipe row without performing an action. It is a placeholder for a future context menu. When implemented, tapping "More" should open a bottom sheet or popup with options such as:

- **Mute** — Silence notifications but keep in active list
- **Block** — End the friendship entirely
- **Report** — Flag the friend for abuse
- **Remove Friend** — Unfriend without blocking

This spec does not define the "More" menu implementation — only its position, appearance, and placeholder behavior. A separate spec will cover the context menu when it's designed.

---

## Appendix: Token Reference

### CSS Classes

| Class | Element | Purpose |
|---|---|---|
| `.swipe-row-wrapper` | Outer `<div>` | Positions actions behind content, manages CSS vars for reveal width |
| `.swipe-row-actions` | Actions `<div>` | Absolute-positioned container for buttons, slides in from right |
| `.swipe-row-content` | Content `<div>` | The slideable layer containing the friend row card |
| `.swipe-action-btn` | `<button>` | Base style for all circular action buttons |
| `.swipe-action-btn--more` | `<button>` | Gray gradient for the More button |
| `.swipe-action-btn--archive` | `<button>` | Orange gradient for the Archive button |
| `.swipe-action-btn--unarchive` | `<button>` | Teal gradient for the Unarchive pill button |
| `.swipe-row-wrapper.swiping` | State class | Added when user is actively swiping — enables pointer events on actions |
| `.swipe-row-wrapper.dragging` | State class | Added during active touch — disables transitions for 1:1 tracking |
| `.swipe-row-wrapper.archiving` | State class | Added when archive animation is in progress |
| `.swipe-row-wrapper.archive-out` | State class | Added to trigger the collapse animation |
| `.friends-filter-toggle` | Container `<div>` | Segmented control wrapper |
| `.friends-filter-btn` | `<button>` | Individual filter tab button |
| `.friends-filter-btn--active` | State class | Active tab styling |
| `.friends-filter-count` | `<span>` | Inline count badge in each tab |
| `.archived-empty` | Container `<div>` | Empty state for the Archived tab |
| `.archived-empty-icon` | `<div>` | Icon container in the empty state |

### CSS Custom Properties

| Property | Set On | Purpose |
|---|---|---|
| `--swipe-actions-width` | `.swipe-row-wrapper` | Total width of the action area (varies: `148px` for active rows, `132px` for archived rows) |
| `--swipe-actions-reveal` | `.swipe-row-wrapper` | How many pixels of the actions are currently visible (0 to `actions-width`). Updated in real-time during drag. |
| `--swipe-actions-offset` | `.swipe-row-wrapper` | The remaining hidden width (`actions-width - reveal`). Used to position the actions container and apply parallax to buttons. |

### Colors

| Token | Value | Usage |
|---|---|---|
| More button gradient | `linear-gradient(135deg, #64748b, #475569)` | Slate gray for the More button |
| Archive button gradient | `linear-gradient(135deg, #f59e0b, #f97316)` | Amber-to-orange for the Archive button |
| Unarchive button gradient | `linear-gradient(135deg, #10b981, #06b6d4)` | Green-to-teal for the Unarchive button |
| Filter toggle background | `rgba(255, 255, 255, 0.06)` | Segmented control container |
| Filter toggle border | `rgba(255, 255, 255, 0.08)` | Segmented control border |
| Active tab background | `rgba(255, 255, 255, 0.12)` | Selected tab fill |
| Inactive tab text | `rgba(255, 255, 255, 0.4)` | Unselected tab label |
| Active tab text | `rgba(255, 255, 255, 0.95)` | Selected tab label |
| Count badge background | `rgba(255, 255, 255, 0.1)` | Pill count in tabs |

### Sizing

| Element | Dimensions |
|---|---|
| Action button (More, Archive) | `62px` circle (`border-radius: 999px`) |
| Action button icon | `16x16px` |
| Action button label | `10px`, weight `600` |
| Unarchive button | `116px` wide, `44px` tall, pill shape |
| Active row action area | `148px` total |
| Archived row action area | `132px` total |
| Filter toggle padding | `3px` inner |
| Filter tab padding | `5px 14px` |
| Count badge | min-width `18px`, height `18px`, `border-radius: 9px` |

### Animations

| Animation | Duration | Easing |
|---|---|---|
| Snap open/closed | `300ms` | `cubic-bezier(0.25, 0.46, 0.45, 0.94)` |
| Archive collapse | `350ms` | `ease-in` |
| Unarchive entrance | `350ms` | `ease-out` |
| Filter tab transition | `250ms` | `ease` |
| Rubber band damping | — | `0.3` factor (70% dampened) |

---

## Design Rationale

| Decision | Why |
|---|---|
| Swipe-left gesture (iOS Mail style) | This is the most widely understood gesture for "manage this item" on mobile. Users intuitively know to swipe list items for actions. It's fast (no long-press delay), reversible (just swipe back), and doesn't clutter the visible UI with buttons. |
| Two circular buttons, not a sliding panel | Circular buttons feel more intentional and app-specific than full-width sliding panels. They give each action a distinct visual identity (color + icon) and prevent accidental taps by requiring precision. |
| Archive, not delete | The app is about intimate connections. Deleting/unfriending is permanent and emotionally loaded. Archiving is gentle — it says "not now" rather than "never." It matches how people manage relationships: sometimes you drift apart temporarily. The door stays open. |
| Notifications silenced, messages still received | This is the key UX insight. The user wants to reduce noise, not cut off communication. If Sarah archives Mike, and Mike sends something important 3 months later, Sarah can find it when she's ready — she just won't be interrupted by it. |
| Filter toggle, not a separate screen | Archived friends are accessible within the same screen (Orbit), not buried in settings. A toggle keeps the mental model simple: "my friends are here, some are just in the other tab." Two taps to see them, one swipe to bring them back. |
| "More" as a placeholder | The More button establishes the pattern for future actions (mute, block, report) without implementing them now. By shipping the swipe gesture with two buttons from the start, adding actions later doesn't change the interaction model. |
| No unread badges on archived rows | Showing badges on archived friends would defeat the purpose. The whole point of archiving is to stop being nudged about that person. Badges only return when the friend is unarchived. |
| Feed cards hidden for archived friends | Same principle — archiving means "I don't want to see this person's activity in my daily flow." Their messages are preserved but not surfaced. |
