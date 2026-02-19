# Block, Delete & Archive — Friend Row Swipe Actions Spec

**Feature name:** Block, Delete & Archive (Swipe Actions)
**Screens affected:** Orbit (Friend List), Conversation Screen (3-dot menu)
**Purpose:** Give users full control over their friend connections through swipe-to-reveal actions on the Orbit screen. Users can archive friends to silence notifications, delete chats to declutter their list, or block contacts to stop all communication. Each destructive action (block, delete) requires explicit confirmation through a popup dialog. Users can also block/unblock from within the Conversation Screen's overflow menu.

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
| Message Database / Store | The local database or state store where messages are persisted. Search for message repository, chat store, conversation database. Delete operations affect this store. | "db.messages" |
| Notification Service | The service that handles push notifications for incoming messages. Search for notification manager, push service, FCM handler, local notification helper. | "notificationService" |
| Conversation Screen | The screen showing the full message history between two users. Search for conversation, chat, letter, message thread screen widgets. This screen has the 3-dot overflow menu for block/unblock. | "Conversation Screen" |
| Overflow / 3-Dot Menu | The menu accessible from the top-right of the Conversation Screen. Search for popup menu, overflow menu, app bar actions, more options. | "3-dot menu" |
| Confirmation Dialog | Any existing alert dialog, modal bottom sheet, or confirmation popup. Search for `AlertDialog`, `showDialog`, `showModalBottomSheet`, `CupertinoAlertDialog`, or custom dialog widgets. | "Confirmation Popup" |
| Swipe / Dismissible Widgets | Flutter has built-in `Dismissible` and packages like `flutter_slidable`. Check if any swipe-to-action pattern is already implemented anywhere in the app. | "SwipeableFriendRow" |
| Filter / Tab Widgets | Segmented controls or toggle buttons. Search for `ToggleButtons`, `SegmentedButton`, `CupertinoSlidingSegmentedControl`, or custom tab/filter widgets. | "Filter Toggle" |
| Theme System | A theme/color scheme that screens receive. Search for `ThemeData`, custom theme extensions, color constant files, design token files. | "theme" |

**Implementation rule:** For every component described in this spec, search the codebase first. If a Flutter equivalent exists, import and reuse it. Only create new code for functionality that is genuinely new (e.g. the swipe gesture wrapper, block/delete state fields, confirmation dialog content, notification silencing logic).

**Flutter-specific note:** For the swipe gesture, consider using Flutter's `Dismissible` widget, the `flutter_slidable` package, or a custom `GestureDetector` with `AnimationController`. For the confirmation dialog, prefer the project's existing dialog pattern (Material `AlertDialog`, Cupertino-style, or a custom widget). Choose whichever approach is most consistent with patterns already in the project.

---

## Feature Overview

This feature introduces three friend management actions accessible via swipe-left on friend rows in the Orbit screen, plus block/unblock from the Conversation Screen:

### The Three Swipe Actions

| Action | Button Color | Confirmation Required? | Reversible? | What It Does |
|---|---|---|---|---|
| **Block** | Gray (`#6b7280`) | Yes — popup | Yes (Unblock) | Stops all communication. Friend cannot send messages. |
| **Delete** | Red (`#ef4444`) | Yes — popup | No | Removes the chat from the user's list. Messages are deleted locally. |
| **Archive** | Orange (`#f59e0b`) | No — instant | Yes (Unarchive) | Moves friend to Archived tab. Silences notifications. Messages still arrive silently. |

### Quick Comparison — Block vs Delete vs Archive

| Behavior | Block | Delete | Archive |
|---|---|---|---|
| Still friends? | No (connection severed) | Partially (removed from list, but friend is not notified) | Yes |
| Receive new messages? | **No** — messages are rejected | **Yes** — if the friend sends again, a new chat appears | **Yes** — messages arrive silently |
| Friend notified? | No | No | No |
| Chat history preserved? | Yes (hidden, restored on unblock) | **No** — local chat history is deleted | Yes |
| Visible in friend list? | No (removed entirely) | No (removed entirely) | No (moved to Archived tab) |
| Get notifications? | No | N/A (no longer in list) | **No** |
| Reversible? | Yes — Unblock from swipe or Conversation 3-dot menu | No — once deleted, chat history is gone | Yes — Unarchive from Archived tab |
| Friend can re-connect? | No — blocked until user unblocks | Yes — if friend sends a message, it creates a new chat | N/A — still connected |

---

## 1. Swipe-to-Reveal Actions (Active Friends)

### What It Does

On the Orbit screen, each friend row in the "All" tab is swipeable. When the user swipes a friend row to the left, the card content slides left to reveal three circular action buttons sitting behind it: **Block** (left), **Delete** (center), and **Archive** (right).

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

**Fully swiped (snapped open) — three action buttons revealed:**

```
┌───────────────────────────────┐
│  [Av]  Sarah      [3] 2m ago │    ( 🚫 )    ( 🗑 )    ( 📦 )
│   (●)  @sarah_1              │    Block     Delete   Archive
│        Sent you a voice...   │   (gray)     (red)   (orange)
└───────────────────────────────┘
```

### Gesture Mechanics

The swipe follows iOS Mail-style physics:

| Property | Value |
|---|---|
| Gesture direction | Left only (horizontal). Right swipe does nothing. |
| Action area total width | `218px` (three 62px circular buttons + 8px gaps + 8px padding on each side) |
| Snap threshold | 50% of action width (`109px`). If the user drags past this, the row snaps open. Below it, the row snaps back closed. |
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

All three buttons are circular (62px) with icon above label:

#### "Block" Button (Left Position)

| Property | Value |
|---|---|
| Shape | Circle, `62px` diameter |
| Background | `linear-gradient(135deg, #6b7280, #4b5563)` (neutral gray) |
| Icon | Circle with diagonal line (🚫) — 16x16px, white, stroke-width 2 |
| Label | "Block" — 10px, weight 600, white, 3px below icon |
| Tap behavior | Opens confirmation popup (see Section 4). Does NOT archive or delete. |

**When the friend is already blocked**, this button transforms into "Unblock":

| Property | Value (Unblock variant) |
|---|---|
| Background | `linear-gradient(135deg, #10b981, #06b6d4)` (green-to-teal) |
| Icon | Return arrow (↩) — 16x16px, white, stroke-width 2 |
| Label | "Unblock" |
| Tap behavior | Immediately unblocks the friend (no confirmation needed). Snaps row closed. |

#### "Delete" Button (Center Position)

| Property | Value |
|---|---|
| Shape | Circle, `62px` diameter |
| Background | `linear-gradient(135deg, #ef4444, #dc2626)` (red) |
| Icon | Trash can — 16x16px, white, stroke-width 2 |
| Label | "Delete" — 10px, weight 600, white, 3px below icon |
| Tap behavior | Opens confirmation popup (see Section 4). Does NOT immediately delete. |

#### "Archive" Button (Right Position)

| Property | Value |
|---|---|
| Shape | Circle, `62px` diameter |
| Background | `linear-gradient(135deg, #f59e0b, #f97316)` (amber-to-orange) |
| Icon | Archive box — 16x16px, white, stroke-width 2 |
| Label | "Archive" — 10px, weight 600, white, 3px below icon |
| Tap behavior | **Immediately archives** the friend (no confirmation). Snaps row closed, then plays collapse animation. (See archive-more-spec.md for full archive flow details.) |

### Button Reveal Animation

The action buttons don't just appear — they slide in from behind the card with a subtle parallax effect:

| Property | Value |
|---|---|
| Actions container | Positioned absolute, right-aligned behind the card. Has `border-radius: 16px` and `overflow: hidden` to match card shape. |
| Container transform | Starts at `translateX(ACTION_WIDTH)` (fully hidden off-right). Tracks with the card drag, moving toward `translateX(0)` as the card slides. |
| Individual button parallax | Each button has an additional `translateX(offset * 0.15)` that resolves to `0` when fully revealed. This creates a subtle "catching up" effect — buttons slightly lag behind the container, making the reveal feel organic rather than rigid. |
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
| Icon | Return arrow (↩) — 16x16px, white, stroke-width 2, inline left of label |
| Label | "Unarchive" — 11px, weight 600, white, `letter-spacing: 0.2px` |
| Layout | Horizontal (`flex-direction: row`, `gap: 6px`) — icon and label side by side |
| Action area width | `132px` (smaller than the active-row actions since it's a single button) |
| Tap behavior | Unarchives the friend — moves them back to the "All" tab immediately. No confirmation needed. |

**Note:** Archived friend rows do NOT show unread badges, even if the archived friend has sent messages. The timestamp and chevron are shown as normal.

---

## 3. Block & Unblock from Conversation Screen

### What It Does

In addition to the swipe action on the Orbit screen, users can block and unblock friends from within the Conversation Screen. This is accessible through the **3-dot overflow menu** (⋮) in the top-right of the conversation header.

### Visual Spec

**3-dot menu — friend is not blocked:**

```
┌──────────────────────┐
│  Search               │
│  Mute notifications   │
│  ────────────────     │
│  Block {name}         │   ← Red text
│  Delete chat          │   ← Red text
└──────────────────────┘
```

**3-dot menu — friend IS blocked:**

```
┌──────────────────────┐
│  Search               │
│  Mute notifications   │
│  ────────────────     │
│  Unblock {name}       │   ← Green text
│  Delete chat          │   ← Red text
└──────────────────────┘
```

### Behavior

| Action | Menu Item Text | Text Color | Confirmation? | What Happens |
|---|---|---|---|---|
| Block | "Block {friendName}" | Red (`#ef4444`) | Yes — same popup as Orbit swipe (Section 4) | Blocks the friend. The conversation screen should show a "You blocked this contact" banner at the bottom replacing the message input. |
| Unblock | "Unblock {friendName}" | Green (`#10b981`) | No — instant | Unblocks the friend. The message input reappears. The user can send messages again. |
| Delete | "Delete chat" | Red (`#ef4444`) | Yes — same popup as Orbit swipe (Section 4) | Deletes the chat. User is navigated back to the previous screen (Orbit or Feed). |

### Blocked Conversation State

When viewing a conversation with a blocked friend, the screen should show:

```
┌──────────────────────────────────────────┐
│  ←  Sarah                          ⋮    │
│──────────────────────────────────────────│
│                                          │
│  (previous messages still visible)       │
│                                          │
│──────────────────────────────────────────│
│  🚫 You blocked this contact.           │
│     Unblock to send messages.    [Unblock]│
└──────────────────────────────────────────┘
```

| Element | Style |
|---|---|
| Banner background | `rgba(255, 255, 255, 0.04)` |
| Banner border-top | `1px solid rgba(255, 255, 255, 0.08)` |
| Icon | Block icon (🚫), 16px, `rgba(255, 255, 255, 0.35)` |
| Text | `13px`, `rgba(255, 255, 255, 0.5)` |
| "Unblock" button | Text button, `13px`, weight 600, color `#10b981` (green) |

The message input field, send button, and attachment options are all hidden. The user must unblock before they can compose messages.

---

## 4. Confirmation Popups

### What They Do

Both "Block" and "Delete" actions require the user to confirm before proceeding. A centered dialog appears over a frosted overlay. The user can cancel (dismiss) or confirm (execute the action).

### Visual Spec

**Block confirmation:**

```
┌──────────────────────────────────────┐
│                                      │
│  Block contact?                      │
│                                      │
│  {Name} will no longer be able to    │
│  message you until you unblock them. │
│                                      │
│  ┌─────────────┐  ┌─────────────┐   │
│  │   Cancel     │  │    Block    │   │
│  │   (gray)     │  │    (red)    │   │
│  └─────────────┘  └─────────────┘   │
│                                      │
└──────────────────────────────────────┘
```

**Delete confirmation:**

```
┌──────────────────────────────────────┐
│                                      │
│  Delete chat?                        │
│                                      │
│  This will remove your chat with     │
│  {Name} from your list only. {Name}  │
│  can still send you messages, and    │
│  you will still receive them.        │
│                                      │
│  ┌─────────────┐  ┌─────────────┐   │
│  │   Cancel     │  │   Delete    │   │
│  │   (gray)     │  │    (red)    │   │
│  └─────────────┘  └─────────────┘   │
│                                      │
└──────────────────────────────────────┘
```

### Dialog Content

| Action | Title | Description | Confirm Label | Confirm Tone |
|---|---|---|---|---|
| **Block** | "Block contact?" | "{Name} will no longer be able to message you until you unblock them." | "Block" | Danger (red) |
| **Delete** | "Delete chat?" | "This will remove your chat with {Name} from your list only. {Name} can still send you messages, and you will still receive them." | "Delete" | Danger (red) |

### Dialog Component Styles

#### Overlay (`.swipe-confirm-overlay`)

| Property | Value |
|---|---|
| Position | `fixed`, `inset: 0` (full screen) |
| Z-index | `1400` (above everything) |
| Background | `rgba(5, 8, 14, 0.62)` (dark semi-transparent) |
| Backdrop filter | `blur(4px)` |
| Layout | `flex`, centered both axes |
| Padding | `24px` (safe area from edges) |
| Tap behavior | Tapping the overlay (outside the card) dismisses the dialog (Cancel) |

#### Card (`.swipe-confirm-card`)

| Property | Value |
|---|---|
| Width | `min(340px, 100%)` |
| Border radius | `18px` |
| Border | `1px solid rgba(255, 255, 255, 0.14)` |
| Background | `linear-gradient(180deg, rgba(18, 20, 28, 0.98) 0%, rgba(11, 13, 20, 0.98) 100%)` |
| Box shadow | `0 18px 48px rgba(0, 0, 0, 0.52)` |
| Padding | `16px` |
| Tap behavior | Tapping inside the card does NOT dismiss (event propagation stopped) |

#### Title (`.swipe-confirm-title`)

| Property | Value |
|---|---|
| Font size | `17px` |
| Font weight | `700` |
| Color | `rgba(255, 255, 255, 0.96)` |
| Letter spacing | `-0.2px` |
| Margin | `0` |

#### Description (`.swipe-confirm-text`)

| Property | Value |
|---|---|
| Font size | `13px` |
| Line height | `1.45` |
| Color | `rgba(255, 255, 255, 0.62)` |
| Margin | `10px 0 0` |

#### Action Buttons Container (`.swipe-confirm-actions`)

| Property | Value |
|---|---|
| Layout | `flex`, horizontal |
| Gap | `8px` |
| Margin top | `16px` |

#### Button Base (`.swipe-confirm-btn`)

| Property | Value |
|---|---|
| Flex | `1` (equal width buttons) |
| Height | `38px` |
| Border radius | `10px` |
| Border | `1px solid transparent` |
| Font size | `13px` |
| Font weight | `600` |
| Cursor | `pointer` |

#### Cancel Button (`.swipe-confirm-btn--cancel`)

| Property | Value |
|---|---|
| Color | `rgba(255, 255, 255, 0.8)` |
| Background | `rgba(255, 255, 255, 0.07)` |
| Border color | `rgba(255, 255, 255, 0.16)` |

#### Danger Button (`.swipe-confirm-btn--danger`)

| Property | Value |
|---|---|
| Color | `white` |
| Background | `linear-gradient(135deg, #ef4444, #dc2626)` (red gradient) |

Used for both Block and Delete confirm buttons — any action that is destructive or hard to reverse.

---

## 5. Block Flow

### Step-by-Step (from Orbit swipe)

```
1. USER SWIPES LEFT ON FRIEND ROW
   │  Three buttons revealed: Block, Delete, Archive
   │
   ▼
2. USER TAPS "BLOCK"
   │
   ▼
3. CONFIRMATION POPUP APPEARS
   │  Title: "Block contact?"
   │  Description: "{Name} will no longer be able to message you
   │                until you unblock them."
   │  Buttons: [Cancel] [Block]
   │
   ├──(User taps Cancel)──▶ Popup dismissed. Swipe row stays open. No action taken.
   │
   ▼ (User taps Block)
4. FRIEND IS BLOCKED
   │  • Friend's `isBlocked` field set to `true` in database
   │  • Popup dismissed
   │  • Swipe row snaps closed
   │  • Friend row remains in the list (with Block button now showing "Unblock")
   │
   ▼
5. EFFECTS TAKE HOLD
   │  • All incoming messages from this friend are REJECTED (not stored)
   │  • No push notifications from this friend
   │  • Friend's Feed cards are filtered out
   │  • Friend is removed from badge calculations
   │  • If user opens the conversation, the blocked banner appears
   │  • The friend has NO way to tell they've been blocked
   │
   ▼
6. DONE
```

### Step-by-Step (from Conversation 3-dot menu)

```
1. USER OPENS CONVERSATION WITH FRIEND
   │
   ▼
2. USER TAPS 3-DOT MENU (⋮)
   │
   ▼
3. USER TAPS "Block {Name}"
   │
   ▼
4. SAME CONFIRMATION POPUP AS ORBIT
   │  (Identical dialog — same title, description, buttons)
   │
   ├──(Cancel)──▶ Menu closed, no action.
   │
   ▼ (Confirm)
5. FRIEND IS BLOCKED
   │  • Message input replaced by blocked banner
   │  • "Unblock to send messages" shown
   │  • Menu item changes to "Unblock {Name}" (green)
```

---

## 6. Unblock Flow

Unblocking can happen from two places:

### From Orbit Swipe

1. User swipes left on the blocked friend's row
2. The Block button now shows as "Unblock" (green-to-teal gradient, ↩ icon)
3. User taps "Unblock"
4. **No confirmation needed** — friend is immediately unblocked
5. Swipe row snaps closed
6. Block button reverts to "Block" (gray)
7. Messages can be received again; notifications resume

### From Conversation Screen

1. User opens conversation with blocked friend
2. Blocked banner is visible at bottom
3. User either:
   - Taps "Unblock" button in the banner, OR
   - Taps 3-dot menu → "Unblock {Name}"
4. **No confirmation needed** — friend is immediately unblocked
5. Message input reappears
6. Menu item reverts to "Block {Name}" (red)

**Why no confirmation for unblock?** Unblocking is always safe — it restores the previous state. The user is adding capability, not removing it. There's no data loss or irreversible consequence.

---

## 7. Delete Flow

### Step-by-Step

```
1. USER SWIPES LEFT ON FRIEND ROW
   │  Three buttons revealed: Block, Delete, Archive
   │
   ▼
2. USER TAPS "DELETE"
   │
   ▼
3. CONFIRMATION POPUP APPEARS
   │  Title: "Delete chat?"
   │  Description: "This will remove your chat with {Name} from
   │                your list only. {Name} can still send you
   │                messages, and you will still receive them."
   │  Buttons: [Cancel] [Delete]
   │
   ├──(User taps Cancel)──▶ Popup dismissed. Swipe row stays open. No action taken.
   │
   ▼ (User taps Delete)
4. CHAT IS DELETED
   │  • Popup dismissed
   │  • Swipe row snaps closed
   │  • Row collapse animation plays (same as archive collapse)
   │  • Friend removed from the list
   │
   ▼
5. DATA CLEANUP
   │  • All local message history for this friend is DELETED from the database
   │  • The friend is removed from the friends list
   │  • Friend is removed from the orbital visualization
   │  • Feed cards from this friend are removed
   │  • All badge counts are recalculated
   │
   ▼
6. WHAT HAPPENS NEXT
   │  • The friend is NOT notified
   │  • The friend is NOT blocked — they can still send messages
   │  • If the friend sends a new message, a NEW chat is created
   │    (appears as if they're contacting the user for the first time)
   │  • Previous chat history is GONE — it is not recoverable
   │
   ▼
7. DONE
```

**Important UX note in the popup:** The description explicitly tells the user that the friend "can still send you messages, and you will still receive them." This prevents confusion — the user understands that deleting is not the same as blocking.

---

## 8. Archive Flow

Archive is unchanged from the existing behavior (see `archive-more-spec.md` for full details). The key difference from Block and Delete:

- **No confirmation popup** — archiving is instant because it's fully reversible
- Tapping "Archive" immediately: snaps the row closed → plays collapse animation → moves friend to Archived tab
- Notifications are silenced but messages still arrive
- User can Unarchive at any time from the Archived tab

---

## 9. Data Model

### Friend Object (Extended)

Each friend in the database needs these fields to support all three actions:

```js
{
  id: Number,
  name: String,
  username: String,
  avatar: String | null,
  status: 'online' | 'offline',
  lastActivity: String,
  lastSeen: String,
  isArchived: Boolean,          // default: false — see archive-more-spec.md
  archivedAt: Date | null,      // when archived, null if not
  isBlocked: Boolean,           // NEW — default: false
  blockedAt: Date | null,       // NEW — when blocked, null if not
}
```

### Operations

```js
// Block a friend
function blockFriend(friendId) {
  db.friends.update(friendId, {
    isBlocked: true,
    blockedAt: new Date(),
  })
  // Stop receiving messages from this friend
  messagingService.rejectMessagesFrom(friendId)
}

// Unblock a friend
function unblockFriend(friendId) {
  db.friends.update(friendId, {
    isBlocked: false,
    blockedAt: null,
  })
  // Resume receiving messages from this friend
  messagingService.acceptMessagesFrom(friendId)
}

// Delete a chat
function deleteChat(friendId) {
  // Delete all local messages
  db.messages.deleteWhere({ friendId: friendId })
  // Remove friend from friends list
  db.friends.delete(friendId)
}
```

---

## 10. Notification & Messaging Behavior

### When a Friend is Blocked

| Event | Behavior |
|---|---|
| Blocked friend sends a message | Message is **rejected** at the messaging layer. It is NOT stored in the local database. The user never sees it. |
| User tries to send message to blocked friend | The message input is hidden. The blocked banner is shown. The user must unblock first. |
| Friend is unblocked | Future messages are accepted and stored normally. Messages sent while blocked are **lost** — they were never received. |
| Friend can tell they're blocked? | **No.** The friend receives no notification or indication. Their messages simply don't get delivered (from their perspective, the user might just not be responding). |

### When a Friend is Archived (recap)

| Event | Behavior |
|---|---|
| Archived friend sends a message | Message is **received and stored** in the local database. No push notification. No sound. No badge count. |
| User opens archived friend's conversation | All messages are visible, including those received while archived. |
| Friend is unarchived | Accumulated unread messages become visible to the badge system. Notifications resume for future messages. |

### When a Chat is Deleted

| Event | Behavior |
|---|---|
| Deleted friend sends a new message | A **new chat** is created. The message appears as if it's the first message from this person. Previous history is gone. |
| User searches for deleted friend | The friend does NOT appear in the Orbit list or search. They are fully removed. |
| User wants to reconnect with deleted friend | The friend would need to send a new message, or the user would need to re-add them via QR code / peer discovery. |

---

## 11. Filter Toggle (All / Archived)

The filter toggle is unchanged from `archive-more-spec.md`. It sits below the "Friends" header on the Orbit screen with two tabs:

- **All** — Shows active (non-archived) friends with count badge
- **Archived** — Shows archived friends with count badge (hidden when 0)

Blocked friends appear in the "All" tab with their Block button showing "Unblock" when swiped. Deleted friends do not appear in either tab.

See `archive-more-spec.md` Section 5 for full filter toggle styling details.

---

## 12. Interaction with Other Features

### Feed Screen

| Friend State | Feed Behavior |
|---|---|
| Active | Messages appear as feed cards normally |
| Archived | Messages are NOT shown on the Feed (filtered out) |
| Blocked | Messages are NOT received, so no feed cards |
| Deleted | Friend is gone — no feed cards |

### Unread Badges (see badge-spec.md)

| Friend State | Badge Behavior |
|---|---|
| Active | All badges work normally (Feed glow, Orbit pill, Nav total) |
| Archived | Excluded from all badge calculations |
| Blocked | Excluded from all badge calculations (no messages to count) |
| Deleted | Friend removed — no badges |

### Orbital Visualization

| Friend State | Orbital Behavior |
|---|---|
| Active | Appears in orbital rings if in Inner Circle |
| Archived | Removed from orbital rings |
| Blocked | Removed from orbital rings |
| Deleted | Removed from orbital rings |

### Search

- Search filters within the currently active tab ("All" or "Archived")
- Blocked friends are searchable in the "All" tab (user needs to find them to unblock via swipe)
- Deleted friends are NOT searchable (they're gone)

---

## 13. Animations Summary

| Animation | Trigger | Duration | Easing | Description |
|---|---|---|---|---|
| Card slide (drag) | Touch/drag | 1:1 tracking | `none` (during drag) | Card follows finger exactly |
| Card snap open | Release past threshold | `300ms` | `cubic-bezier(0.25, 0.46, 0.45, 0.94)` | Card snaps to fully open position |
| Card snap closed | Release before threshold | `300ms` | `cubic-bezier(0.25, 0.46, 0.45, 0.94)` | Card snaps back to resting position |
| Button parallax | During drag | 1:1 tracking | `none` (during drag) | Buttons slide in with 15% parallax offset |
| Button parallax (snap) | Release | `300ms` | `cubic-bezier(0.25, 0.46, 0.45, 0.94)` | Buttons settle into final position |
| Archive/Delete collapse | After action confirmed | `350ms` | `ease-in` | Row collapses (height, opacity, margins) |
| Unarchive entrance | After state change | `350ms` | `ease-out` | Row expands into place |
| Confirmation popup appear | Action button tap | Instant (no animation) | — | Overlay and card appear immediately |
| Confirmation popup dismiss | Cancel tap or overlay tap | Instant (no animation) | — | Overlay and card disappear immediately |
| Rubber band | Drag past action width | 1:1 tracking | `none` | Excess drag dampened by 70% |

---

## 14. Edge Cases

| Scenario | Behavior |
|---|---|
| User blocks then immediately unblocks | Both operations are independent. Block sets `isBlocked: true`, unblock sets `isBlocked: false`. No cooldown. |
| User archives then blocks same friend | Both states are tracked independently. If blocked AND archived, the block takes priority — messages are rejected (not silently received). |
| User deletes a friend they've blocked | The friend is deleted. The block state is also removed since the friend no longer exists in the database. If the friend sends a message later, it creates a new (unblocked) chat. |
| User deletes a friend with unread messages | All messages (read and unread) are deleted locally. Badge counts are recalculated. |
| Block/delete popup is open and user taps overlay | Popup is dismissed (Cancel behavior). No action taken. |
| Block/delete popup is open and user navigates back | Popup should be dismissed. No action taken. |
| Multiple swipe rows open | Only one row should be open at a time. Opening a new row closes the previous one. |
| Blocked friend sends message via different channel | This spec only covers in-app messaging. If the app has other communication channels, each should check `isBlocked` independently. |
| User opens conversation of blocked friend from a deep link | The conversation opens with the blocked banner visible. The 3-dot menu shows "Unblock {Name}". |
| App restart after block/delete | All state is persisted in the local database. Blocked friends remain blocked. Deleted friends remain gone. |

---

## Appendix: Token Reference

### CSS Classes

| Class | Element | Purpose |
|---|---|---|
| `.swipe-row-wrapper` | Outer `<div>` | Positions actions behind content, manages CSS vars for reveal width |
| `.swipe-row-actions` | Actions `<div>` | Absolute-positioned container for action buttons |
| `.swipe-row-content` | Content `<div>` | The slideable layer containing the friend row card |
| `.swipe-action-btn` | `<button>` | Base style for circular action buttons (62px) |
| `.swipe-action-btn--block` | `<button>` | Gray gradient for the Block button |
| `.swipe-action-btn--unblock` | `<button>` | Green-to-teal gradient for the Unblock button |
| `.swipe-action-btn--delete` | `<button>` | Red gradient for the Delete button |
| `.swipe-action-btn--archive` | `<button>` | Orange gradient for the Archive button |
| `.swipe-action-btn--unarchive` | `<button>` | Green-to-teal pill for the Unarchive button (archived tab) |
| `.swipe-row-wrapper.swiping` | State class | Enables pointer events on action buttons |
| `.swipe-row-wrapper.dragging` | State class | Disables transitions for 1:1 drag tracking |
| `.swipe-row-wrapper.archiving` | State class | Triggers collapse animation |
| `.swipe-row-wrapper.archive-out` | State class | Collapse animation target state |
| `.swipe-confirm-overlay` | `<div>` | Full-screen frosted overlay behind the popup |
| `.swipe-confirm-card` | `<div>` | The popup card container |
| `.swipe-confirm-title` | `<h4>` | Popup title text |
| `.swipe-confirm-text` | `<p>` | Popup description text |
| `.swipe-confirm-actions` | `<div>` | Horizontal button row in popup |
| `.swipe-confirm-btn` | `<button>` | Base popup button style |
| `.swipe-confirm-btn--cancel` | `<button>` | Gray cancel button |
| `.swipe-confirm-btn--danger` | `<button>` | Red destructive action button |
| `.friends-filter-toggle` | `<div>` | Segmented control container |
| `.friends-filter-btn` | `<button>` | Individual filter tab |
| `.friends-filter-btn--active` | State class | Active tab highlight |
| `.friends-filter-count` | `<span>` | Inline count badge in tabs |
| `.archived-empty` | `<div>` | Empty state for Archived tab |

### CSS Custom Properties

| Property | Set On | Purpose |
|---|---|---|
| `--swipe-actions-width` | `.swipe-row-wrapper` | Total width of action area (`218px` for active, `132px` for archived) |
| `--swipe-actions-offset` | `.swipe-row-wrapper` | Remaining hidden width, drives action container and button parallax transforms |

### Colors

| Token | Value | Usage |
|---|---|---|
| Block button gradient | `linear-gradient(135deg, #6b7280, #4b5563)` | Gray for Block |
| Unblock button gradient | `linear-gradient(135deg, #10b981, #06b6d4)` | Green-teal for Unblock |
| Delete button gradient | `linear-gradient(135deg, #ef4444, #dc2626)` | Red for Delete |
| Archive button gradient | `linear-gradient(135deg, #f59e0b, #f97316)` | Orange for Archive |
| Unarchive button gradient | `linear-gradient(135deg, #10b981, #06b6d4)` | Green-teal for Unarchive |
| Danger button gradient | `linear-gradient(135deg, #ef4444, #dc2626)` | Red confirm button in popup |
| Cancel button bg | `rgba(255, 255, 255, 0.07)` | Gray cancel button |
| Cancel button border | `rgba(255, 255, 255, 0.16)` | Cancel button border |
| Overlay bg | `rgba(5, 8, 14, 0.62)` | Popup overlay background |
| Popup card bg | `linear-gradient(180deg, rgba(18, 20, 28, 0.98), rgba(11, 13, 20, 0.98))` | Dialog card background |
| Popup card border | `rgba(255, 255, 255, 0.14)` | Dialog card border |
| Title text | `rgba(255, 255, 255, 0.96)` | Popup title |
| Description text | `rgba(255, 255, 255, 0.62)` | Popup body text |

### Sizing

| Element | Dimensions |
|---|---|
| Action button (Block, Delete, Archive) | `62px` circle (`border-radius: 999px`) |
| Action button icon | `16x16px` |
| Action button label | `10px`, weight `600` |
| Unarchive pill button | `116px` wide, `44px` tall, `border-radius: 999px` |
| Active row action area | `218px` total (3 buttons) |
| Archived row action area | `132px` total (1 button) |
| Popup card | `min(340px, 100%)` wide |
| Popup card radius | `18px` |
| Popup card padding | `16px` |
| Popup button height | `38px` |
| Popup button radius | `10px` |

### Typography

| Element | Size | Weight | Color |
|---|---|---|---|
| Action button label | `10px` | `600` | white |
| Unarchive button label | `11px` | `600` | white |
| Popup title | `17px` | `700` | `rgba(255, 255, 255, 0.96)` |
| Popup description | `13px` | `400` | `rgba(255, 255, 255, 0.62)` |
| Popup button text | `13px` | `600` | varies by button type |

### Animations

| Animation | Duration | Easing |
|---|---|---|
| Snap open/closed | `300ms` | `cubic-bezier(0.25, 0.46, 0.45, 0.94)` |
| Archive/Delete collapse | `350ms` | `ease-in` |
| Unarchive entrance | `350ms` | `ease-out` |
| Rubber band damping | — | `0.3` factor (70% dampened) |
| Popup appear/dismiss | Instant | — |

---

## Design Rationale

| Decision | Why |
|---|---|
| Three distinct actions, not a menu | Each action has a unique severity and color. Showing them as separate buttons makes the consequences visible at a glance — gray (neutral), red (destructive), orange (soft). A menu would hide these visual cues behind an extra tap. |
| Block and Delete require confirmation, Archive doesn't | Block and Delete have consequences that are harder to reverse (block severs communication, delete erases history). Archive is fully and instantly reversible, so a confirmation popup would just slow down a safe action. |
| Block doesn't delete, Delete doesn't block | These are independent actions. Some users want to stop communication (block) but keep the history. Others want to clean up their list (delete) without cutting off the person. Combining them would remove user choice. |
| Unblock doesn't require confirmation | Unblocking only adds capability — it never removes anything. It's always safe, so friction is unnecessary. |
| Confirmation popup over the swipe row, not inline | The popup forces the user to pause and read. Inline confirmations (like "Are you sure?" replacing the button) are too easy to tap through. A full overlay with distinct Cancel/Confirm buttons ensures deliberate action. |
| Delete description says "can still send you messages" | This is the most common point of confusion. Users expect "delete" to mean "block." The explicit description manages expectations: deleting is about cleaning up YOUR view, not controlling THEIR behavior. |
| Block/Unblock accessible from Conversation Screen too | Users might want to block someone while reading their messages (e.g. receiving harassment). Requiring them to exit the conversation, go to Orbit, find the person, and swipe would be hostile UX. The 3-dot menu provides immediate access. |
| Blocked conversation shows banner, not empty screen | Preserving the message history while showing the blocked state lets the user review what happened. An empty screen would feel like data loss. The banner clearly communicates the current state and provides a one-tap unblock. |
| Red color for destructive actions | Universal convention. Red = danger/irreversible. Used consistently for Delete button, Block confirm, and the danger confirm button in popups. |
| Gray for Block button (not red) | Block is destructive but reversible. Using red for both Block and Delete would make them visually identical in the swipe row. Gray distinguishes "stop communication" (block) from "erase data" (delete). The red confirmation popup still appears when the user taps Block, reinforcing the seriousness at the decision point. |
