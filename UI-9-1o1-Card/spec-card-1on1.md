# Card Design Spec — 1:1 Conversations

## For the Implementing Agent

**Before you write any code**, scan the existing codebase:

1. **Search for existing message/thread/conversation models.** Extend what exists. Do not create parallel data structures.
2. **Search for existing card, bubble, or feed list components.** Reuse and extend them. Do not duplicate.
3. **Search for existing theme tokens and CSS variables.** The app uses a dark glassmorphic design system. If the app defines `--glass-bg`, `--text-muted`, or similar — use those instead of hardcoding the rgba values from this spec.
4. **Search for existing compose/input components.** The app may have text input or send button components from a conversation screen. Reuse them.
5. **Search for existing media rendering.** Image grids, video players, thumbnails — reuse if they exist.

The rgba values and pixel sizes below are **design intent**. Prefer the app's existing values when they serve the same purpose.

---

## Core Concept

The stack card IS the conversation. The user reads, replies, and quote-replies **without leaving the feed**. No navigation to a separate chat screen for everyday exchanges.

### Three Depth Levels

| Level | Name | What the user sees | When |
|---|---|---|---|
| 1 | **Collapsed** | Last 2 messages as a mini exchange + inline reply input | Default. A glance. |
| 2 | **Expanded** | Full message thread as bubbles + compose area | Tap to read everything. |
| 3 | **Full Screen** | Complete conversation history in a dedicated screen | Tap "View earlier" on threads with 8+ messages. |

---

## Data Model

### Message

```
id                 Unique identifier
threadId           Links to the parent thread card
friendId           The friend this conversation is with
type               'received' | 'sent'
text               String | null  (null = media-only message)
timestamp          When the message was created
readAt             When the user read this message (null = unread)
unread             Derived: type === 'received' && readAt === null
quotedMessageId    ID of the message this replies to, or null
media              Array<MediaItem> | null
```

### MediaItem

```
type               'image' | 'video'
url                URL or local file path
thumbnailUrl       Optional. Pre-generated thumbnail for fast loading.
width              Original width in pixels
height             Original height in pixels
duration           Video only. Seconds or display string like "0:24".
blurhash           Optional. Placeholder blur hash while loading.
```

### Thread Card

```
id                 Unique card identifier
friendId           The friend this conversation is with
messages           Message[] — all messages, chronological order
latestTimestamp    Timestamp of the most recent message
unreadCount        Count of messages where unread === true
hasUserReplied     Boolean — at least one sent message in this thread
lastReplyTimestamp Timestamp of the user's most recent sent message, or null
state              Derived (see below): 'unread' | 'read' | 'replied' | 'active'
totalMessages      messages.length
```

### Conversation States

Derived from the messages. Never stored independently.

| State | Rule | Visual summary |
|---|---|---|
| **unread** | `unreadCount > 0 && !hasUserReplied` | Orange glow + badge |
| **read** | `unreadCount === 0 && !hasUserReplied` | Neutral (no glow, no badge) |
| **replied** | `hasUserReplied && unreadCount === 0` | Teal checkmark + "You replied" |
| **active** | `hasUserReplied && unreadCount > 0` | Orange glow + badge + "You replied" |

---

## Thread Splitting Rules

One friend can have **multiple cards** on the feed. Each card is a time-bounded conversation thread.

### Rule 1 — Time Gap (4+ hours)

4+ hours between the last message in one cluster and the next incoming message creates a new card.

```
Sarah 9:05 AM  "Want to grab coffee?"
You   9:10 AM  "Yes! Meet at 10?"
                                         <- 7 hour gap
Sarah 4:30 PM  "Just saw the craziest thing"
```

Result: 2 cards for Sarah.

### Rule 2 — Reply Closes a Stack

Replying soft-closes the stack. If the friend sends new messages **4+ hours after your reply**, those start a new card.

### Rule 3 — Quick Follow-up Stays Together

If the friend responds **within 4 hours** of your reply, the message stays in the same card. The card transitions to `active`.

### Rule 4 — Session Boundary

Cards with unread messages appear above a "Previously Seen" divider. Read/replied cards appear below. This is a display split, not a data split.

### Edge Cases

- **User sends first** (no received messages): Creates a card in `replied` state. Friend response within 4h → `active`. No response after 4h → stays `replied`.
- **Burst across the gap boundary**: Messages at 3:58 PM, 4:01 PM, 4:03 PM after an 11:00 AM last message — all go in the new stack. Do not split mid-burst (messages <5 min apart = one burst).
- **Simultaneous sends**: Both users send within seconds. Order by timestamp. Same stack.

---

## Card Anatomy — Collapsed (Layer 1)

```
+------------------------------------------+
|  [avatar]  Sarah              9:45 AM    |  <- Header
|  ↩ You replied 9:35 AM                   |  <- Reply indicator (conditional)
|                                           |
|  Sarah: Thank you!! Dinner Saturday?     |  <- Exchange line 1
|  You:   CONGRATULATIONS!!                |  <- Exchange line 2
|                                           |
|  +3 earlier                    v         |  <- Peek hint (conditional)
|  ---------------------------------------- |
|  [ Reply...                          ]   |  <- Inline reply input
+------------------------------------------+
```

### Header

| Element | Details |
|---|---|
| Avatar | Friend's profile image, circle, left-aligned |
| Name | Friend's display name |
| Time | Most recent message timestamp, right-aligned, muted |
| Badge | Unread count (only when `unreadCount > 0`) |
| Checkmark | Teal check icon (only when `state === 'replied'`) |

Badge and checkmark are mutually exclusive — `active` shows badge (the "You replied" sub-line handles the reply signal).

### Reply Indicator

Shown when `(state === 'replied' || state === 'active') && hasUserReplied`.

```
↩ You replied 9:35 AM
```

Small reply-arrow icon + text. The time is the user's most recent sent message timestamp.

### Exchange Preview

The **last 2 messages** (`messages.slice(-2)`), in chronological order.

Each line: `Name: message text`

| Scenario | What appears |
|---|---|
| 1 received, no reply | Single line: friend's message |
| Multiple received, no reply | 2nd-to-last + latest |
| Friend sent, you replied | Friend's latest → Your reply (dimmer) |
| You replied, friend responded | Your reply (dimmer) → Friend's response |
| Multiple replies from you | Your 2nd-to-last → Your latest |
| Media-only message | `[icon] Photo` / `[icon] 3 photos` / `[icon] Video` |
| Media + text | `[icon]` badge + caption text |

**Styling:**
- Received line: normal text brightness. Name label: weight 600, 12px, 50% opacity.
- Sent line: dimmer text (~65% opacity). "You:" label: weight 600, 12px, teal at 50%.
- Both lines: single-line, `text-overflow: ellipsis`.
- Quote-reply: `↩` arrow before "You:" when the sent message has a `quotedMessageId`.

### Peek Hint

Shown when `totalMessages > 2`:

```
+3 earlier  v
```

"+N earlier" where N = `totalMessages - 2`. Down-chevron icon. Tapping expands the card.

### Inline Reply Input

Always present at the bottom of every collapsed card.

- Pill-shaped single-line input
- Placeholder: `'replied'` → "Continue..." / all others → "Reply..."
- Tapping focuses the input. A circular send button scales in when there's text.
- Sending: appends a `sent` message, updates exchange preview, recalculates state, clears input. User never leaves the feed.
- **Must stop event propagation** so tapping the input doesn't trigger expand/collapse.

---

## Card Anatomy — Expanded (Layer 2)

Tap the card body to expand. All messages appear as bubbles with a compose area at the bottom.

```
+------------------------------------------+
|  [avatar]  Sarah              9:45 AM    |
|  ↩ You replied 9:35 AM                   |
|                                           |
|  [View 4 earlier messages]               |  <- 8+ msgs only
|                                           |
|  +------------------------------------+  |
|  | Received bubble                    |  |  <- full width
|  |                          9:02 AM   |  |
|  +------------------------------------+  |
|                                           |
|       +-------------------------------+  |
|       | Sent bubble                 |>|  |  <- indented, teal accent
|       |                You · 9:15 AM |>|
|       +-------------------------------+  |
|                                           |
|  +------------------------------------+  |
|  | [media grid]                       |  |  <- media in bubble
|  | Caption text                       |  |
|  |                          9:20 AM   |  |
|  +------------------------------------+  |
|                                           |
|              ^ Collapse                   |
|  ---------------------------------------- |
|  [ Write something...            ] [>]   |  <- compose area
+------------------------------------------+
```

### Message Bubbles

**Received:**
- Full width (no extra horizontal margin)
- Glass background
- Normal text brightness

**Sent:**
- 24px left margin (indented)
- Right border accent: 2px solid teal ~30%
- Dimmer text (~70% opacity)
- Timestamp prefixed with "You · " in teal

**Unread received:**
- Same as received + warm/orange border tint + subtle inset glow

**With media:**
- Media grid renders inside the bubble, above text
- Text below media = caption
- Media-only: just grid + timestamp, no empty paragraph

**With quote reference (quote-reply):**
- Mini quote bar above the message text
- Vertical line left (2px, muted) + original text (1 line, truncated, small, very muted)
- Tapping the quote scrolls to the original message

### "View Earlier" Link

Threads with 8+ messages show at the top:

```
View 4 earlier messages
```

Tapping navigates to the full conversation screen (Layer 3). Only the most recent 6 messages are shown in the expanded card.

### Collapse Hint

Below the last bubble, above the compose:

```
^ Collapse
```

Chevron-up + text, muted. Tapping collapses back to Layer 1.

### Compose Area

Replaces the inline reply input when expanded.

| Feature | Collapsed input | Expanded compose |
|---|---|---|
| Height | Single line, fixed | Auto-grows up to 4 lines |
| Placeholder | "Reply..." / "Continue..." | "Write something..." |
| Quote preview | Not supported | Shown above input when quoting |

**Quote preview:** Teal bar left, "Replying to" label, quoted text (max 2 lines), "×" close button.

---

## Quote-Reply

### Why

When a friend sends 5 messages and you want to reply to #2 specifically, a flat reply is ambiguous. Quote-reply adds a reference.

### Triggering

In **expanded view only**:
- Mobile: swipe right on a received bubble
- Desktop: long-press or double-click on a received bubble

Result: The compose area shows a quote preview. On send, the message stores `quotedMessageId`.

### Display

**Expanded bubble:**
```
+-------------------------------+
| ┊ Original message text      |  <- 1 line, muted, small
| Your reply here              |
|                     9:15 AM |>|
+-------------------------------+
```

**Collapsed exchange preview:**
```
Sarah: The original message
↩ You: Your reply to that specific message
```

### Edge Cases

- **Quoting media**: Quote bar shows "Photo" or "Video". If it had a caption, show the caption.
- **Quoting a very long message**: 1 line in bubble bar, 2 lines in compose preview.
- **Quoting a deleted message**: "Message unavailable" in muted italic.
- **Quote-reply to a quote-reply**: Show only the direct parent. No nesting.

---

## Media Messages

### Content Combinations

A message can be: text-only, media-only, or text + media. The `media` array can hold multiple items (batch send).

### Grid Layouts

| Count | Layout | Aspect |
|---|---|---|
| 1 | Full width | 4:3 |
| 2 | Side by side | 1:1 each |
| 3 | 1 top (full), 2 bottom (half) | Top: 2:1, Bottom: 1:1 |
| 4 | 2×2 grid | 1:1 each |
| 5+ | 2×2 for first 4, "+N" overlay on 4th | 1:1 each |

- Gap: 3px
- Container border-radius: 10px (clips children)
- Item border-radius: 4px
- `object-fit: cover`
- Grid placed inside bubble, above any text

### Video Thumbnail

- Semi-transparent dark overlay (~30% black)
- Centered play icon (filled triangle, white, ~28px)
- Duration badge below play icon (small, dark pill background)
- Tapping opens the video player

### Media in Collapsed Preview

| Content | Preview |
|---|---|
| 1 image, no text | `[camera-icon] Photo` |
| 3 images, no text | `[camera-icon] 3 photos` |
| 1 video, no text | `[video-icon] Video` |
| Image + caption | `[camera-icon]` + caption text |
| Mixed types | `[camera-icon] 2 photos · Video` |

Icon: 11-13px, same muted color as the name label.

### Edge Cases

- **Image load failure**: Placeholder rectangle with muted icon. Same aspect ratio. Grid does not collapse.
- **No video thumbnail**: Dark rectangle with play icon + duration.
- **Mixed image + video in one message**: Same grid. Video items get overlay.
- **5+ items**: First 4 in grid, 4th gets "+N" dark overlay. Tap opens gallery.
- **Media-only message**: Bubble = grid + timestamp. No empty `<p>`.
- **Sending media**: Show local file immediately (optimistic). Loading indicator on thumbnail. Replace URL on upload complete.
- **Aspect ratio**: `object-fit: cover` means some cropping. Tap to view full resolution.

---

## Conversation States — Visual Treatment

### Unread

- Orange glow on card border
- Unread count badge in header
- No checkmark
- Placeholder: "Reply..."

### Read

- No glow, no badge, no checkmark
- Neutral glass card
- Placeholder: "Reply..."

### Replied

- Teal checkmark in header
- "You replied [time]" sub-line
- Subtle teal border tint
- Placeholder: "Continue..."

### Active

- Orange glow on card border (new messages)
- Unread count badge
- "You replied [time]" sub-line persists
- Placeholder: "Reply..."

---

## Feed Ordering

**Above "Previously Seen" divider:**
- `state === 'unread'` or `state === 'active'`
- Sorted by most recent message, newest first

**Below divider:**
- `state === 'read'` or `state === 'replied'`
- Sorted by most recent message, newest first

Divider only shown if both sections have cards.

---

## Interaction Behaviors

### Expand / Collapse
- Tap card body (not input, not interactive elements) → toggle
- Only cards with 2+ messages expand
- Only one card expanded at a time
- Collapsing clears any active quote-reply

### Sending (Inline)
1. Tap input → focus → send button animates in
2. Type → tap send (or Enter)
3. New `sent` message appended
4. State recalculated (mark all received as read, then derive)
5. Exchange preview updates, input clears

### Sending (Expanded Compose)
Same as inline, but new bubble appears at bottom. Auto-scroll only if user is already at bottom.

### Quote-Reply Gesture
- Swipe right (mobile) or double-click (desktop) on received bubble
- Quote preview appears in compose. Cancel with "×".
- On send: message includes `quotedMessageId`

### Marking as Read
- Expanding a card: mark received as read after 300-500ms delay
- Sending a reply (inline): mark all received as read immediately
- Recalculate state after marking

---

## Visual Design Tokens

Use the app's existing tokens where they match. These are design intent.

### Card Container
```
Unread/Active glow:
  border: warm/orange tint
  box-shadow: 0 0 20px rgba(255, 107, 107, 0.08)

Replied border:
  border-color: rgba(78, 205, 196, 0.12)

Stacked look (2+ msgs, collapsed):
  Faux stacked-paper shadow behind the card
```

### Exchange Preview
```
Received line:  14px, line-height 1.5, ~85% opacity
  Name label:   600 weight, 12px, ~50% opacity
Sent line:      14px, line-height 1.5, ~65% opacity
  "You:" label: 600 weight, 12px, teal ~50%
Both:           nowrap, ellipsis
↩ arrow:        teal ~45%, 13px
Media icon:     11-13px, ~40% (received) or teal ~45% (sent)
```

### Bubbles
```
Received:       bg white ~4%, border white ~6%, radius 14px, pad 10px 14px, text ~85%
Sent:           bg white ~2.5%, border white ~5%, border-right 2px teal ~30%,
                radius 14px, pad 10px 14px, margin-left 24px, text ~70%
Unread:         bg white ~6%, border warm ~15%, inset shadow warm ~8%
Timestamp:      11px, ~25%, right-aligned. "You ·" prefix: teal ~40%, weight 500
Quote bar:      border-left 2px white ~15%, pad-left 8px, 12px, ~35%, 1-line truncated
```

### Inline Reply Input
```
Container:      bg white ~4%, border white ~8%, radius 20px, pad 4px 6px 4px 16px
Active:         bg white ~6%, border teal ~20%
Input:          14px, ~90%, placeholder ~25%
Send:           32px circle, bg teal ~20%, icon arrow-up 16px teal, scale-in 200ms
```

### Compose Area
```
Container:      border-top white ~6%, pad-top 8px
Input row:      same as inline reply
Quote preview:  bg white ~3%, border white ~6%, radius 10px, pad 8px 10px
  Bar:          3px wide, teal ~30%, full height
  Label:        11px, weight 600, teal ~50%
  Text:         12px, ~40%, max 2 lines
  Close:        "×", ~25%
```

### Media Grid
```
Grid:           gap 3px, radius 10px, overflow hidden
Items:          radius 4px, bg white ~3% (placeholder), object-fit cover
Video overlay:  bg black ~30%, play icon white ~90% 28px
Duration:       11px, weight 600, white ~80%, bg black ~40%, pad 2px 6px, radius 4px
```

### Badge & Checkmark
```
Badge:          small circle, warm/orange bg, white bold text, min-width for 2 digits
Checkmark:      22px circle, bg teal ~15%, icon 13px teal, animate on state change
Reply line:     12px, ~40%, reply-arrow 12px inline, "You replied [time]"
```

---

## Edge Cases Checklist

### Empty / Unusual States
- No messages → don't render the card
- Only sent messages (user initiated) → display normally, state = `replied`
- Friend blocked mid-thread → card stays visible but reply input disabled, muted overlay

### Content Length
- 500+ char message → collapsed: 1 line + ellipsis. Expanded: full text, bubble grows.
- 20+ messages → expanded shows recent 6 + "View N earlier" link
- 10+ messages in under a minute → same thread, last 2 in preview, "+N earlier"

### Real-time Updates
- New message while card is visible → update exchange preview (collapsed), append bubble (expanded), recalculate state
- New message while user is typing → don't disrupt typing, update card behind the input
- New message while card is expanded → append bubble, auto-scroll only if already at bottom

### State Transitions
- User replies → mark all received as read → state becomes `replied`
- User deletes sent message → recalculate `hasUserReplied`, state may revert
- Two cards for same friend, reply to one → only that card's state changes

### Accessibility
- Screen reader: announce friend name, state, message count, exchange text
- Keyboard: Tab → input, Enter → send, Escape → collapse

---

## What NOT to Build

- No separate message list screen. The feed IS the message list.
- No typing indicators. This is intimate messaging, not real-time chat.
- No read receipts visible to the friend.
- No delivery status icons (single check / double check).
- No emoji reactions on messages (quote-reply handles specificity).
