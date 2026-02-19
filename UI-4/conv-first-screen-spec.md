# Conv. (1st) — First-Time Conversation Screen Design Spec

**Screen name:** Conv. (1st)
**Entry point:** Tapping "Send Message" on the 1st Contact D "Connected!" card
**Purpose:** The user's very first conversation with a new connection — no message history exists yet

---

## Screen Overview

This screen is the beginning of a relationship. There is no chat history to show, so instead of a blank void, the screen presents a warm, ceremonial moment: the friend's avatar, a "Connected!" label, and a gentle prompt inviting the user to write their first message. It should feel like opening a brand new journal — full of possibility, not emptiness.

```
+------------------------------------------+
|  [<]  [Avatar 36px]  Alex          [...]  |  <- Header
|         Connected February 9, 2026        |
|                                           |
|                                           |
|                                           |
|            [Avatar 80px + glow]           |
|                                           |
|              Connected!                   |  <- Green, glowing
|           February 9, 2026               |  <- Muted
|                                           |
|         - - - - - - - - - - -            |  <- Dashed divider
|                                           |
|          Write the first letter           |
|       to start your conversation          |
|                                           |
|                                           |
|                                           |
+-------------------------------------------+
|  +-------------------------------------+  |
|  | Write something...                  |  |  <- Compose input
|  +-------------------------------------+  |
|   [+]                           [Send]    |  <- Action row
+-------------------------------------------+
```

---

## Anatomy — Top to Bottom

### 1. Screen Container

The entire screen is a full-height flex column. No navigation bar is shown — this is an immersive, focused writing space.

| Property | Value |
|---|---|
| Layout | `display: flex; flex-direction: column` |
| Height | `100%` of the screen frame |
| Background | `#0a0a0f` (near-black) |
| Ambient BG | Floating radial gradients (purple/pink/teal) that drift slowly behind all content |

---

### 2. Conversation Header

A sticky frosted-glass bar at the top showing who you're writing to.

```
[<]   [Avatar]   Alex                    [...]
                 Connected February 9, 2026
```

| Element | Spec |
|---|---|
| **Container** | `padding: 16px 20px`, `backdrop-filter: blur(20px)`, `background: linear-gradient(180deg, rgba(10,10,15,0.98) 0%, rgba(10,10,15,0.85) 80%, rgba(10,10,15,0) 100%)`, `z-index: 100`, sticky to top |
| **Back button** | Left-pointing chevron, `24x24px` icon, `rgba(255,255,255,0.6)` color, `44x44px` tap target, circular hover state at `rgba(255,255,255,0.08)` |
| **Avatar** | `36px` circle, `border: 2px solid #4ecdc4`, `box-shadow: 0 0 12px rgba(78,205,196,0.3)`, `object-fit: cover`. Falls back to `RingBrandedAvatar` if no photo |
| **Friend name** | `16px`, weight `600`, `rgba(255,255,255,0.95)` |
| **Status line** | `12px`, weight `400`, `rgba(255,255,255,0.4)`, reads "Connected February 9, 2026" |
| **Overflow button** | Three vertical dots, `20x20px`, `rgba(255,255,255,0.4)`, `44x44px` tap target |
| **Gap** | `14px` between elements |

---

### 3. Conversation Body — Empty State

The body fills all remaining space between the header and compose area. When there are no messages, it displays the **empty state** — a vertically and horizontally centered composition.

#### 3a. Empty State Wrapper

| Property | Value |
|---|---|
| Layout | `flex: 1; display: flex; align-items: center; justify-content: center` |
| Transition | Fades out with `opacity 0.4s ease` when the first message is sent |

#### 3b. Ambient Glow

A breathing radial glow behind the avatar, using the friend's color.

| Property | Value |
|---|---|
| Position | Absolute, centered at `top: 30%; left: 50%; transform: translate(-50%, -50%)` |
| Size | `300x300px` |
| Gradient | `radial-gradient(circle, rgba(78,205,196,0.08) 0%, rgba(78,205,196,0.03) 40%, transparent 70%)` |
| Filter | `blur(40px)` |
| Animation | `emptyStateGlow 6s ease-in-out infinite` — scales between `1.0` and `1.15` while opacity pulses between `0.6` and `1.0` |
| Pointer events | None |

#### 3c. Friend Avatar (Large)

The friend's photo displayed prominently as a centered circle.

| Property | Value |
|---|---|
| Size | `80x80px` |
| Shape | Circle (`border-radius: 50%`) |
| Border | `2px solid #4ecdc4` (friend's color) |
| Glow | `box-shadow: 0 0 30px rgba(78,205,196,0.3), 0 10px 40px rgba(0,0,0,0.4)` |
| Fit | `object-fit: cover` |
| Fallback | `RingBrandedAvatar` at `80px` if no photo URL |
| Spacing | `margin-bottom: 16px` |
| Z-index | `1` (above the ambient glow) |

#### 3d. "Connected!" Label

| Property | Value |
|---|---|
| Font size | `20px` |
| Font weight | `600` |
| Color | `var(--theme-accent1)` — defaults to `#1DB954` (green) |
| Text shadow | `0 0 20px rgba(29,185,84,0.4)` — soft green glow |
| Spacing | `margin-bottom: 4px` |

#### 3e. Connection Date

| Property | Value |
|---|---|
| Font size | `13px` |
| Font weight | `400` |
| Color | `rgba(255,255,255,0.35)` |
| Spacing | `margin-bottom: 24px` |
| Content | The date the connection was made (e.g. "February 9, 2026") |

#### 3f. Dashed Divider

A subtle horizontal rule separating the connection info from the writing prompt.

| Property | Value |
|---|---|
| Width | `60%` of the container |
| Border | `1px dashed rgba(255,255,255,0.12)` (top only) |
| Height | `1px` with no fill |
| Spacing | `margin-bottom: 24px` |

#### 3g. Writing Prompt

The call to action — inviting the user to begin.

| Property | Value |
|---|---|
| Font size | `17px` |
| Font weight | `500` |
| Color | `rgba(255,255,255,0.5)` |
| Line height | `1.5` |
| Text align | `center` |
| Content | "Write the first letter" (line break) "to start your conversation" |

---

### 4. Compose Area

Fixed at the bottom. This is where the user writes and sends their first message.

#### 4a. Compose Container

| Property | Value |
|---|---|
| Position | Relative, `z-index: 50`, flex-shrink `0` |
| Padding | `12px 16px`, bottom adds `env(safe-area-inset-bottom)` |
| Background | `linear-gradient(180deg, transparent 0%, rgba(10,10,15,0.95) 20%)` — fades in from transparent so there's no hard edge against the body |
| Backdrop filter | `blur(20px)` |

#### 4b. Text Input

A glassmorphic `<textarea>` that auto-grows as the user types.

| Property | Value |
|---|---|
| Min height | `44px` |
| Max height | `160px` (scrolls internally beyond this) |
| Padding | `12px 16px` |
| Background | `rgba(255,255,255,0.06)` |
| Border | `1px solid rgba(255,255,255,0.10)` |
| Border radius | `22px` |
| Font | `15px`, system font stack, `line-height: 1.5` |
| Text color | `rgba(255,255,255,0.95)` |
| Placeholder | "Write something..." in `rgba(255,255,255,0.3)` |
| Focus state | Border brightens to `rgba(255,255,255,0.20)`, glow: `box-shadow: 0 0 0 1px rgba(255,255,255,0.08), 0 4px 20px rgba(0,0,0,0.3)` |
| Resize | `none` — grows automatically via JS |

The placeholder deliberately uses the verb **"Write"** (not "Type" or "Send") to reinforce the letter metaphor.

#### 4c. Action Row

Below the textarea, spaced with `justify-content: space-between`.

**Left — Attachment button (+):**

| Property | Value |
|---|---|
| Tap target | `44x44px`, `border-radius: 50%` |
| Icon | Circle with plus sign, `22x22px`, `rgba(255,255,255,0.4)` |
| Hover | Background `rgba(255,255,255,0.08)`, icon brightens to `0.7` |

**Right — Send button:**

| Property | Value |
|---|---|
| Visibility | **Hidden by default** (`opacity: 0; transform: scale(0.9); pointer-events: none`). Only appears when text input is non-empty |
| Appear transition | `opacity` and `transform` over `0.25s ease` |
| Shape | Pill (`border-radius: 100px`) |
| Padding | `10px 20px` |
| Background | `rgba(29,185,84,0.15)` |
| Border | `1px solid rgba(29,185,84,0.3)` |
| Color | `#1DB954` (green) |
| Font | `14px`, weight `600` |
| Content | Paper-plane SVG icon (`18x18px`) + "Send" text |
| Hover | Background `0.25` opacity, border `0.5`, `box-shadow: 0 4px 16px rgba(29,185,84,0.2)`, slight `scale(1.02)` lift |
| Active | `scale(0.97)` press |

#### 4d. Length Hint

Only appears when text exceeds ~2000 characters.

| Property | Value |
|---|---|
| Font size | `11px` |
| Color | `rgba(255,255,255,0.25)` |
| Text align | Right |
| Content | "Long letters are lovely" |
| Visibility | Fades in with `opacity 0.3s ease` |

---

## Interaction: Sending the First Message

This is the key moment — the transition from empty state to active conversation.

### Sequence

1. **User types** in the compose input. The Send button fades in.

2. **User taps Send** (or presses Enter).

3. **Empty state fades out** (400ms, opacity 0). The avatar, "Connected!" label, date, divider, and prompt all dissolve together as one unit.

4. **After fade completes**, the empty state is replaced by:
   - A **compact origin marker** at the top (48px avatar, smaller "Connected!" at 15px, date at 12px)
   - The user's **sent letter card** below it

5. **Sent letter card animates in** from below: `translateY(20px)` to `0`, `scale(0.97)` to `1`, `opacity 0` to `1`, over `400ms` with `cubic-bezier(0.16, 1, 0.3, 1)` easing.

### Post-First-Send Layout

```
+-------------------------------------------+
|  [<]  [Avatar 36px]  Alex          [...]  |
|         Connected February 9, 2026        |
|                                           |
|            [Avatar 48px]                  |  <- Compact origin
|             Connected!                    |
|          February 9, 2026                 |
|                                           |
|       ----  TODAY  ----                   |  <- Date separator
|                                           |
|  +-------------------------------------+ |
|  |        You            3:42 PM       | |  <- Sent letter card
|  |                                     | |     (right accent edge,
|  |  Your first message text here.      | |      muted white border)
|  |  Whatever the user typed...         | |
|  |                           Delivered | |
|  +-------------------------------------+ |
|                                           |
+-------------------------------------------+
|  compose area                             |
+-------------------------------------------+
```

### Compact Origin Marker

| Property | Value |
|---|---|
| Avatar | `48px` (down from `80px`) |
| "Connected!" | `15px` (down from `20px`) |
| Date | `12px` (down from `13px`) |
| Layout | Centered column, `padding: 24px 16px 16px`, `gap: 4px` |

### Sent Letter Card (User's First Message)

| Property | Value |
|---|---|
| Background | `rgba(255,255,255,0.04)` — slightly more recessed than received cards |
| Border | `1px solid rgba(255,255,255,0.08)` |
| Right accent | `border-right: 3px solid rgba(255,255,255,0.25)` |
| Right glow | Pseudo-element, `60px` wide, `linear-gradient(270deg, rgba(255,255,255,0.04), transparent)` |
| Border radius | `24px` |
| Avatar | User's `RingBrandedAvatar` at `32px`, border `rgba(255,255,255,0.25)`, glow `rgba(255,255,255,0.1)` |
| Name | "You", `14px`, weight `500`, `rgba(255,255,255,0.6)` |
| Time | Current time, `11px`, `rgba(255,255,255,0.35)` |
| Body text | `15px`, `line-height: 1.65`, `rgba(255,255,255,0.80)` |
| Delivery note | "Delivered", `10px`, `rgba(255,255,255,0.15)`, right-aligned |
| Entry animation | `letterSend` — `translateY(20px) scale(0.97)` to `translateY(0) scale(1)`, `400ms`, `cubic-bezier(0.16, 1, 0.3, 1)` |

---

## The Two-Phone Flow

This section describes the complete end-to-end experience when two users interact for the first time.

### Scenario

- **User-A** and **User-B** just connected (both saw the 1st Contact D "Connected!" screen)
- **User-A** taps "Send Message" and writes the first letter
- **User-B** receives it

### Step-by-step

```
User-A's phone                          User-B's phone
─────────────                          ─────────────
1st Contact D                          1st Contact D
"Connected! [User-B]"                  "Connected! [User-A]"
     │                                      │
     ▼                                      │
Taps "Send Message"                         │
     │                                      │
     ▼                                      │
Conv. (1st) screen                          │
(empty state)                               │
     │                                      │
     ▼                                      │
Writes and sends                            │
first letter                                │
     │                                      ▼
     │                              User-A's message appears
     │                              on User-B's Feed screen
     │                              as a Feed Message Card
     │                                      │
     │                                      ▼
     │                              User-B taps "Reply"
     │                              (or taps the card)
     │                                      │
     │                                      ▼
     │                              Conversation screen opens
     │                              showing User-A's letter
     │                              (received card) + compose area
     │                                      │
     │                                      ▼
     │                              User-B writes and sends reply
     │                                      │
     ▼                                      │
User-B's reply appears              Conversation now shows:
on User-A's Feed screen             - Origin marker
as a Feed Message Card              - User-A's letter (received)
                                    - User-B's reply (sent)
```

---

## 5. Feed Message Card (How a received message appears on the Feed)

When User-B opens their Feed screen, User-A's message appears as a **text-only message card** — the same card style used in Feed C. This is how all incoming messages are displayed.

### Structure

```
+------------------------------------------+
|  [card-glow overlay]                     |
|                                          |
|  [avatar 42px]  User-A's Name           |
|                 9:12 AM                  |
|                                          |
|  Message text content goes here.         |
|  Multiple lines of text with generous    |
|  line height...                          |
|                                          |
|  ──────────────────────────────────────  |
|                          [ Reply button] |
+------------------------------------------+
```

### 5a. Card Container (`.message-card.text-only`)

| Property | Value |
|---|---|
| Border radius | `28px` |
| Background | `var(--glass-bg)` — `rgba(255,255,255,0.08)` |
| Border | `1px solid var(--glass-border)` — `rgba(255,255,255,0.12)` |
| Backdrop filter | `blur(24px)` (frosted glass) |
| Overflow | `hidden` |
| Position | `relative` |
| Min height | `auto` |
| Entry animation | `cardEnter 0.6s ease backwards` — slides up `30px` and scales from `0.95` to `1.0`. Each card staggers by `index * 0.1s` |

### 5b. Card Glow (`.card-glow`)

An ambient gradient glow at the top of each card.

| Property | Value |
|---|---|
| Position | Absolute, pinned `top: 0; left: 0; right: 0` |
| Height | `200px` |
| Background | `var(--card-gradient)` — `linear-gradient(135deg, #a8edea, #fed6e3)` (cyan to pink) |
| Opacity | `0.15` (increases to `0.25` on hover) |
| Filter | `blur(40px)` |
| Pointer events | `none` |
| Transition | `opacity 0.3s ease` |

### 5c. Friend Indicator (`.friend-indicator`)

The sender's identity row at the top of the card.

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; gap: 12px` |
| Padding | `18px 20px 12px` |
| Z-index | `1` (above the glow) |

**Avatar (`.friend-avatar`):**

| Property | Value |
|---|---|
| Size | `42x42px` |
| Shape | Circle (`border-radius: 50%`) |
| Border | `2px solid var(--friend-color)` — the sender's assigned color (e.g. `#4ecdc4`) |
| Glow | `box-shadow: 0 0 20px var(--friend-color)` |
| Fit | `object-fit: cover` |

**Friend Info (`.friend-info`):**

| Property | Value |
|---|---|
| Layout | Flex column, `gap: 2px` |

**Friend Name (`.friend-name`):**

| Property | Value |
|---|---|
| Font size | `16px` |
| Font weight | `600` |
| Color | `var(--text-primary)` — `rgba(255,255,255,0.95)` |

**Time (`.message-context`):**

| Property | Value |
|---|---|
| Font size | `12px` |
| Font weight | `400` |
| Color | `var(--text-muted)` — `rgba(255,255,255,0.4)` |

### 5d. Message Content (`.message-content` > `.text-message-content`)

| Property | Value |
|---|---|
| Container padding | `16px 20px` |
| Z-index | `1` |
| Font size | `16px` |
| Line height | `1.6` |
| Color | `rgba(255,255,255,0.95)` |
| Font weight | `400` |
| Letter spacing | `0.2px` |
| Word wrap | `break-word` |

### 5e. Message Footer (`.message-footer`)

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; justify-content: flex-end` |
| Padding | `12px 20px 18px` |
| Z-index | `1` |
| Separator | `border-top: 1px solid rgba(255,255,255,0.08)`, `margin-top: 12px`, `padding-top: 12px` (specific to `.text-only` cards) |

**Reply Button (`.reply-btn`):**

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; gap: 8px` |
| Padding | `10px 18px` |
| Background | `rgba(255,255,255,0.08)` |
| Border | `none` |
| Border radius | `24px` (pill) |
| Color | `var(--text-secondary)` — `rgba(255,255,255,0.6)` |
| Font size | `14px`, weight `500` |
| Icon | Chat bubble SVG, `18x18px`, stroke-based, `viewBox="0 0 24 24"`, `strokeWidth="2"`, `fill="none"` |
| Content | SVG icon + "Reply" text |
| Hover | `background: rgba(255,255,255,0.15)`, `color: var(--text-primary)` |

### 5f. Feed Message Card Data Model

```js
{
  id: Number,
  friend: {
    name: String,       // Sender's display name
    avatar: String,     // URL to sender's avatar image
    color: String,      // Hex color for avatar border/glow
  },
  text: String,         // Message content (the letter body)
  time: String,         // Display time (e.g. "9:12 AM")
}
```

---

## 6. Conversation Screen — Letter Card Design

When a user taps "Reply" on a Feed card (or taps the card itself), the **Conversation screen** opens. This shows the full message history between the two users as a vertical stack of **letter cards**.

### Key principle: Letters, not chat bubbles

Both received and sent messages are **full-width** glassmorphic cards. There is no left/right alignment. Authorship is distinguished by:
- A subtle **accent edge** (left for received, right for sent)
- Slight differences in background opacity and text brightness

This avoids the chat-app visual pattern (L/R bubbles) and reinforces the "letters between friends" metaphor.

### 6a. Conversation Screen Layout

```
+------------------------------------------+
|  [<] Friend Name                   [...]  |  <- Conversation header
|      Connected [date]                     |
|                                           |
|            [Avatar 48px]                  |  <- Compact origin marker
|             Connected!                    |
|          [connection date]                |
|                                           |
|       ---- JANUARY 15 ----               |  <- Date separator
|                                           |
|  ┃ [avatar] Friend        9:12 AM       |  <- Received letter
|  ┃                                       |     (left teal accent)
|  ┃ Message text from your friend...      |
|  ┃                                       |
|                                           |
|       [avatar] You         9:45 AM     ┃ |  <- Sent letter
|                                        ┃ |     (right white accent)
|       Your reply text here...          ┃ |
|                              Delivered ┃ |
|                                           |
|       ---- JANUARY 16 ----               |
|                                           |
|  ┃ [avatar] Friend        6:30 PM       |
|  ┃                                       |
|  ┃ Another message from them...          |
|  ┃                                       |
|                                           |
+-------------------------------------------+
|  +-------------------------------------+  |
|  | Write something...                  |  |
|  +-------------------------------------+  |
|   [+]                           [Send]    |
+-------------------------------------------+
```

### 6b. Letter Card — Shared Base (`.letter-card`)

All letter cards share these base properties:

| Property | Value |
|---|---|
| Border radius | `24px` |
| Overflow | `hidden` |
| Backdrop filter | `blur(24px)` |
| Position | `relative` |
| Entry animation | `letterReveal 0.4s ease backwards` — `translateY(12px)` to `0`, `opacity 0` to `1`. Stagger: `50ms` per card |

### 6c. Received Letter Card (`.letter-card.received`)

A message from the other person. Has a colored left-edge accent to identify authorship.

```
+----------------------------------------------+
┃  [Avatar 32px] Friend Name      9:12 AM     |
┃                                              |
┃  Message text here. This is the full         |
┃  content of the letter from your friend.     |
┃  It can be long and thoughtful.              |
┃                                              |
+----------------------------------------------+
```

| Property | Value |
|---|---|
| Background | `rgba(255,255,255,0.06)` |
| Border | `1px solid rgba(255,255,255,0.10)` |
| Left accent | `border-left: 3px solid var(--friend-color)` — the sender's color (e.g. `#4ecdc4` teal) |
| Left glow | Pseudo-element (`::before`), `60px` wide, `linear-gradient(90deg, rgba(78,205,196,0.08), transparent)` — a subtle colored wash from the left edge |

**Header (`.letter-header`):**

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; gap: 10px` |
| Padding | `14px 16px 8px` |

**Avatar (`.letter-avatar`):**

| Property | Value |
|---|---|
| Size | `32x32px` |
| Shape | Circle |
| Border | `2px solid var(--friend-color)` |
| Glow | `box-shadow: 0 0 10px var(--friend-color)` |
| Fallback | `RingBrandedAvatar` at `32px` if no photo |

**Sender name (`.letter-sender-name`):**

| Property | Value |
|---|---|
| Font size | `14px` |
| Font weight | `600` |
| Color | `rgba(255,255,255,0.9)` |
| Flex | `1` (fills remaining space) |

**Time (`.letter-time`):**

| Property | Value |
|---|---|
| Font size | `11px` |
| Font weight | `400` |
| Color | `rgba(255,255,255,0.35)` |

**Body (`.letter-body`):**

| Property | Value |
|---|---|
| Padding | `4px 16px 16px` |
| Font size | `15px` |
| Line height | `1.65` |
| Color | `rgba(255,255,255,0.90)` |
| Font weight | `400` |
| Letter spacing | `0.2px` |

### 6d. Sent Letter Card (`.letter-card.sent`)

The current user's own message. Visually recessed compared to received cards — your own words feel less novel than theirs.

```
+----------------------------------------------+
|      [Avatar 32px] You          9:45 AM     ┃
|                                              ┃
|  Your reply text here. This is what          ┃
|  you wrote back to your friend.              ┃
|                                    Delivered ┃
+----------------------------------------------+
```

| Property | Value |
|---|---|
| Background | `rgba(255,255,255,0.04)` — slightly more transparent than received |
| Border | `1px solid rgba(255,255,255,0.08)` — slightly fainter |
| Right accent | `border-right: 3px solid rgba(255,255,255,0.25)` — muted white/silver |
| Right glow | Pseudo-element (`::before`), `60px` wide, positioned right, `linear-gradient(270deg, rgba(255,255,255,0.04), transparent)` |

**Avatar:**

| Property | Value |
|---|---|
| Source | User's `RingBrandedAvatar` (or photo if set) at `32px` |
| Border | `rgba(255,255,255,0.25)` — neutral, not colored |
| Glow | `box-shadow: 0 0 10px rgba(255,255,255,0.1)` — very subtle |

**Sender name:**

| Property | Value |
|---|---|
| Content | "You" |
| Font size | `14px` |
| Font weight | `500` (lighter than received card's `600`) |
| Color | `rgba(255,255,255,0.6)` (dimmer than received card's `0.9`) |

**Body text:**

| Property | Value |
|---|---|
| Color | `rgba(255,255,255,0.80)` (slightly dimmer than received card's `0.90`) |
| All other properties | Same as received card body |

**Delivery note (`.letter-delivery-note`):**

| Property | Value |
|---|---|
| Content | "Delivered" — no timestamps, no "Read" state. Once the letter leaves your hands, it belongs to the recipient |
| Font size | `10px` |
| Font weight | `400` |
| Color | `rgba(255,255,255,0.15)` — barely visible unless you look for it |
| Text align | `right` |
| Padding | `0 16px 12px` |

### 6e. Visual Comparison: Received vs Sent

| Property | Received | Sent |
|---|---|---|
| Background | `rgba(255,255,255,0.06)` | `rgba(255,255,255,0.04)` |
| Border | `1px solid rgba(255,255,255,0.10)` | `1px solid rgba(255,255,255,0.08)` |
| Accent edge | **Left**, 3px, friend's color | **Right**, 3px, `rgba(255,255,255,0.25)` |
| Edge glow | Left, friend color at 8% | Right, white at 4% |
| Avatar border | Friend's color | `rgba(255,255,255,0.25)` |
| Avatar glow | Friend's color | `rgba(255,255,255,0.1)` |
| Name | Friend's name, `600` weight, `0.9` opacity | "You", `500` weight, `0.6` opacity |
| Body text | `0.90` opacity | `0.80` opacity |
| Delivery note | None | "Delivered" at `0.15` opacity |
| Border radius | `24px` | `24px` |

The difference is deliberately subtle. Both card types belong to the same journal. The sent card simply recedes slightly — your own handwriting in a letter exchange feels less novel than the other person's.

### 6f. Anchor Message Highlighting

When the conversation opens from a "Reply" tap on a specific Feed card, that message gets a temporary highlight to orient the user.

| Property | Value |
|---|---|
| Box shadow | `0 0 0 2px rgba(78,205,196,0.3), 0 0 30px rgba(78,205,196,0.1)` |
| Animation | `anchorPulse 2s ease-out 0.5s forwards` — glow pulses then fades to nothing |
| Purpose | "You are here" moment without permanent clutter |

### 6g. Date Separators

When messages span multiple days, a date separator appears between letter cards.

```
       ----  JANUARY 15  ----
```

| Property | Value |
|---|---|
| Layout | Flex row with `gap: 16px` |
| Lines | `::before` and `::after` pseudo-elements, `flex: 1`, `height: 1px`, `linear-gradient(90deg, transparent, rgba(255,255,255,0.12), transparent)` |
| Label | `11px`, weight `500`, `rgba(255,255,255,0.3)`, `text-transform: uppercase`, `letter-spacing: 1px` |

### 6h. Letter Card Data Model

```js
// Single message in the conversation
{
  id: Number,
  type: 'received' | 'sent',
  text: String,           // The letter body
  time: String,           // Display time (e.g. "9:12 AM")
  date: String,           // Date label for grouping (e.g. "January 15")
  isAnchor: Boolean,      // True if this is the message being replied to (optional)
}
```

---

## 7. Screen Transitions

### 7a. Transition from 1st Contact D ("Send Message" tap)

When the user taps the green **Send Message** pill on the Connected! card, the card transforms into the conversation screen.

**Animation sequence (600ms total):**

1. **Card lift (0–200ms):** The Connected! card gently lifts toward the top of the screen. The avatar and "Connected!" headline slide up and scale down slightly (to 0.85), settling into the conversation header position.

2. **Background morph (100–400ms):** The card's glassmorphic background expands to fill the full screen. The ambient background gradient cross-fades from the 1st Contact D variant to the conversation screen variant.

3. **Compose entrance (300–600ms):** The compose area slides up from below with the first-time empty state content.

```css
/* Card lift */
transition: transform 200ms cubic-bezier(0.16, 1, 0.3, 1);

/* Background morph */
transition: all 300ms ease;

/* Compose entrance */
transition: opacity 300ms ease, transform 300ms cubic-bezier(0.16, 1, 0.3, 1);
transition-delay: 300ms;
transform: translateY(40px) -> translateY(0);
```

### 7b. Transition from Feed C ("Reply" tap)

When the user taps the **Reply** button on a Feed C message card, the card opens up to become the conversation.

**Animation sequence (540ms total):**

1. **Card expansion (0–360ms):** The tapped card scales up and expands to fill the screen. Other cards fade to `opacity: 0` over the first 200ms. The tapped card's `border-radius` animates from `28px` to `0px`. The glassmorphic background remains visible — the user should feel they are *inside* the card now.

2. **Content reveal (200–540ms):** As the card reaches full size, the conversation history fades in above the message that prompted the reply (the "anchor message"), and the compose area slides up from the bottom.

```css
/* Card expansion */
transition: all 360ms cubic-bezier(0.16, 1, 0.3, 1);
transform: scale(1) -> fills viewport;
border-radius: 28px -> 0px;

/* Sibling card fade */
transition: opacity 200ms ease-out;

/* Content reveal */
transition: opacity 340ms ease, transform 340ms cubic-bezier(0.16, 1, 0.3, 1);
transition-delay: 200ms;
```

### 7c. Transition from Feed card tap (full card surface)

When the user taps anywhere on a feed card (not just the Reply button), the conversation screen opens with that message as the anchor. The entire card surface is a tap target for entering the conversation.

---

## 8. Feed Integration — Sent Messages Policy

### 8a. The Feed remains "From your people" — incoming only

Sent messages do **NOT** appear as cards in the Feed. This is the strongest recommendation in this spec.

**Why:**

1. **The feed's identity is reception.** The header says "From your people." Adding your own messages would be like seeing your own gifts mixed in with ones you received. It breaks the emotional framing.

2. **Scarcity creates value.** Each card carries the weight of someone else's intention. They chose to write to *you*. Diluting with your own words cheapens every card.

3. **Asymmetric design is intentional.** The feed is for reading. The conversation screen is for writing. Preserving this separation keeps each space purposeful.

4. **Clutter.** If a user has 8 friends and sends messages to 4 of them, the feed could double in size. The contemplative scrolling experience is destroyed by noise.

5. **Self-consciousness.** Seeing your own sent messages in a public-feeling feed may cause users to second-guess what they wrote. The conversation screen is a private, two-person space.

**Counter-arguments (acknowledged and rejected):**

- "Users might want to see what they wrote." — That is what the conversation screen is for. Tapping any friend's card opens the full history.
- "It enriches the narrative." — It clutters the narrative. The feed tells the story of what your friends say to you. Your replies are a different chapter.

### 8b. "You replied" Indicator on Feed Cards

Although sent messages do not appear as feed cards, the feed acknowledges active conversations. When the user has replied to a friend, that friend's **next incoming message card** shows a whisper-quiet indicator:

```
+----------------------------------------------+
|  [Avatar] Sarah          9:12 AM        |
|  [tiny reply icon] You replied 2h ago        |  <- Sub-line
|                                              |
|  "Message text from Sarah..."                |
|                                              |
|                          [Reply]             |
+----------------------------------------------+
```

```css
.reply-indicator {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 0 20px 4px;
  position: relative;
  z-index: 1;
}

.reply-indicator svg {
  width: 12px;
  height: 12px;
  color: rgba(255, 255, 255, 0.25);
}

.reply-indicator span {
  font-size: 11px;
  font-weight: 400;
  color: rgba(255, 255, 255, 0.25);
}
```

Barely visible unless you look for it. Tells the user "you are in conversation with this person" without disrupting the incoming-only feed.

---

## 9. Micro-Interactions and Animations

### 9a. Letter Card Entry (Conversation History)

When the conversation opens and history loads, letter cards enter with a staggered animation — softer and faster than feed cards, since these are being *revealed* rather than *arriving*.

```css
.letter-card {
  animation: letterReveal 0.4s ease backwards;
}

@keyframes letterReveal {
  from {
    opacity: 0;
    transform: translateY(12px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
```

Stagger: **50ms** between cards (faster than the feed's 100ms — this is review, not discovery).

Cards above the viewport (scrolled off-screen initially) do not animate — they simply exist when the user scrolls up.

### 9b. Message Send Animation (5-step sequence)

When the user taps Send:

1. **Input content vanishes (0–150ms):** The text in the compose input fades to `opacity: 0` and the input shrinks back to its minimum height.

2. **Send button pulse (0–300ms):** The Send button briefly flashes with a brighter green glow:
   ```css
   @keyframes sendPulse {
     0% { box-shadow: 0 0 0 0 rgba(29, 185, 84, 0.4); }
     50% { box-shadow: 0 0 0 12px rgba(29, 185, 84, 0); }
     100% { box-shadow: 0 0 0 0 rgba(29, 185, 84, 0); }
   }
   ```

3. **New letter card appears (150–550ms):** The sent message materializes as a new letter card at the bottom of the conversation:
   ```css
   @keyframes letterSend {
     from {
       opacity: 0;
       transform: translateY(20px) scale(0.97);
     }
     to {
       opacity: 1;
       transform: translateY(0) scale(1);
     }
   }
   ```
   Duration: 400ms, easing: `cubic-bezier(0.16, 1, 0.3, 1)`, delay: 150ms.

4. **Auto-scroll (150–550ms):** The conversation body smoothly scrolls to reveal the new card fully (`scroll-behavior: smooth`).

5. **Send button fades back to hidden (400–650ms):** Since the input is now empty, the send button returns to its invisible state.

### 9c. Message Receive Animation (Real-Time)

If a new message arrives while the conversation screen is open:

1. **Haptic feedback:** Subtle vibration (10ms light impact on iOS).

2. **Letter card entrance:** The new received card slides in from below with a more dramatic animation than sent messages:
   ```css
   @keyframes letterReceive {
     from {
       opacity: 0;
       transform: translateY(30px) scale(0.95);
     }
     to {
       opacity: 1;
       transform: translateY(0) scale(1);
     }
   }
   ```
   Duration: 500ms, easing: `cubic-bezier(0.16, 1, 0.3, 1)`.

3. **Edge glow pulse:** The left-edge accent of the new card briefly glows brighter for 1.5s before settling:
   ```css
   @keyframes edgeGlowPulse {
     0% { border-left-color: var(--friend-color); box-shadow: -4px 0 20px var(--friend-color); }
     100% { border-left-color: var(--friend-color); box-shadow: none; }
   }
   ```

### 9d. Compose Input Focus Animation

When the user taps the compose input:

1. The input border brightens from `rgba(255,255,255,0.10)` to `rgba(255,255,255,0.20)` over 200ms.
2. A subtle glow appears: `box-shadow: 0 0 0 1px rgba(255,255,255,0.08)`.
3. The placeholder text fades from 30% to 20% opacity (becomes even more ghostly as you prepare to write over it).

### 9e. Long-Press Context Menu

Long-pressing any letter card (received or sent) triggers a gentle scale-up (`1.0` to `1.02`) and reveals a glassmorphic context menu.

**For received messages:** "Copy Text," "React," "Save."
**For sent messages:** "Copy Text," "Delete."

```css
.letter-context-menu {
  background: rgba(30, 30, 35, 0.9);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 16px;
  padding: 6px;
  min-width: 180px;
  box-shadow: 0 16px 48px rgba(0, 0, 0, 0.5);
}

.letter-context-menu-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  border-radius: 12px;
  font-size: 15px;
  color: rgba(255, 255, 255, 0.85);
  cursor: pointer;
  transition: background 0.15s ease;
}

.letter-context-menu-item:hover {
  background: rgba(255, 255, 255, 0.08);
}

.letter-context-menu-item.destructive {
  color: #ff6b6b;
}

.letter-context-menu-item svg {
  width: 20px;
  height: 20px;
  opacity: 0.6;
}
```

### 9f. Anchor Scroll Behavior

On open, the conversation body scrolls so the **anchor message** is vertically centered in the viewport. If there are fewer messages above the anchor than half the viewport height, the scroll position starts at the top. The scroll is **instant** (no smooth scroll on entry) — the user should see their context immediately.

After the initial positioning, normal smooth scrolling applies to user-initiated scrolls.

---

## 10. Navigation and Back Behavior

### 10a. Back Button

The back arrow in the conversation header returns the user to the screen they came from. The transition reverses the entry animation:

| Entry Point | Back Destination | Transition Style |
|---|---|---|
| Feed C Reply button | Feed C (preserved scroll position) | Reverse card expansion, 360ms, `cubic-bezier(0.16, 1, 0.3, 1)` |
| Feed C card tap | Feed C (preserved scroll position) | Reverse card expansion |
| 1st Contact D Send Message | 1st Contact D | Reverse morph — conversation collapses, Connected! card re-forms |
| In-feed Connected! card | Feed C (scroll to that card) | Reverse card expansion |

### 10b. Swipe-Back Gesture

On mobile, a swipe-from-left-edge gesture triggers back navigation. During the gesture, the conversation screen translates right following the finger, with the previous screen visible behind at reduced scale and dimmed.

```css
/* During swipe-back gesture */
.conversation-screen.swiping {
  transition: none; /* Follows finger directly */
  box-shadow: -8px 0 32px rgba(0, 0, 0, 0.5);
}

.previous-screen-behind {
  transform: scale(0.95);
  opacity: 0.5;
  filter: blur(2px);
}
```

If the swipe exceeds **40%** of the screen width, the back navigation completes. Otherwise, it snaps back.

### 10c. Navigation Bar

The bottom `NavigationBar` (Feed / Remember / Orbit) is **hidden** on the conversation screen. The user must use the back button or swipe gesture to return to a navigation-enabled screen.

**Rationale:** Showing the nav bar while writing a letter to a friend would be like having a TV on in the background while writing a heartfelt note. The conversation demands full attention.

### 10d. Keyboard Behavior

When the keyboard opens (user taps the compose input):

1. The compose area stays **anchored to the top of the keyboard**.
2. The conversation body **shrinks in height** to accommodate the keyboard.
3. Auto-scroll positions the most recent message (or anchor message) just above the compose area, so the user can see context while writing.
4. The conversation header remains **sticky at the top** and does NOT scroll away.

```css
.conversation-body.keyboard-active {
  padding-bottom: 0; /* Compose container handles its own spacing */
}
```

### 10e. Entry Point State Management

The conversation screen must track its entry context to return correctly:

```js
{
  origin: 'feedC' | 'firstContactD' | 'inFeedContact',
  scrollPosition: Number,   // Feed scroll position to restore
  cardIndex: Number,         // Which card was tapped
}
```

---

## Appendix: Token Reference

### Colors

| Token | Value | Usage |
|---|---|---|
| `--bg-primary` | `#0a0a0f` | Screen background |
| `--glass-bg` | `rgba(255, 255, 255, 0.08)` | Standard glassmorphic surface (Feed cards) |
| `--glass-bg-subtle` | `rgba(255, 255, 255, 0.06)` | Received letter card |
| `--glass-bg-recessed` | `rgba(255, 255, 255, 0.04)` | Sent letter card |
| `--glass-border` | `rgba(255, 255, 255, 0.12)` | Standard border (Feed cards) |
| `--glass-border-subtle` | `rgba(255, 255, 255, 0.10)` | Received letter card border |
| `--glass-border-faint` | `rgba(255, 255, 255, 0.08)` | Sent letter card border |
| `--glass-blur` | `24px` | Standard backdrop blur |
| `--text-primary` | `rgba(255, 255, 255, 0.95)` | Primary text, friend name |
| `--text-secondary` | `rgba(255, 255, 255, 0.6)` | Secondary text, reply button, sent card name |
| `--text-muted` | `rgba(255, 255, 255, 0.4)` | Muted text, time stamps, status line |
| `--text-ghost` | `rgba(255, 255, 255, 0.25)` | Ghost text ("You replied" indicator) |
| `--text-invisible` | `rgba(255, 255, 255, 0.15)` | Nearly invisible ("Delivered" note) |
| `--accent-green` | `#1DB954` | Primary action, "Connected!", Send button |
| `--accent-green-bg` | `rgba(29, 185, 84, 0.15)` | Green button background |
| `--accent-green-border` | `rgba(29, 185, 84, 0.3)` | Green button border |
| `--accent-teal` | `#4ecdc4` | Friend accent, received card edge |
| `--friend-color` | Dynamic, per-friend | Avatar border/glow, received card edge |
| `--card-gradient` | `linear-gradient(135deg, #a8edea, #fed6e3)` | Feed card glow (cyan to pink) |

### Typography

| Element | Size | Weight | Color |
|---|---|---|---|
| Feed card friend name | 16px | 600 | `--text-primary` |
| Feed card time | 12px | 400 | `--text-muted` |
| Feed card message body | 16px | 400 | `rgba(255,255,255,0.95)` |
| Feed card reply button | 14px | 500 | `--text-secondary` |
| Conversation header name | 16px | 600 | `--text-primary` |
| Conversation header status | 12px | 400 | `--text-muted` |
| Letter sender name (received) | 14px | 600 | `rgba(255,255,255,0.9)` |
| Letter sender name (sent) | 14px | 500 | `rgba(255,255,255,0.6)` |
| Letter time | 11px | 400 | `rgba(255,255,255,0.35)` |
| Letter body (received) | 15px | 400 | `rgba(255,255,255,0.90)` |
| Letter body (sent) | 15px | 400 | `rgba(255,255,255,0.80)` |
| Compose input | 15px | 400 | `--text-primary` |
| Compose placeholder | 15px | 400 | `rgba(255,255,255,0.3)` |
| Date separator | 11px | 500 | `rgba(255,255,255,0.3)`, uppercase, `letter-spacing: 1px` |
| Empty state "Connected!" | 20px | 600 | `--accent-green` |
| Empty state prompt | 17px | 500 | `rgba(255,255,255,0.5)` |
| Empty state date | 13px | 400 | `rgba(255,255,255,0.35)` |
| Delivery note | 10px | 400 | `rgba(255,255,255,0.15)` |
| "You replied" indicator | 11px | 400 | `rgba(255,255,255,0.25)` |
| Length hint | 11px | 400 | `rgba(255,255,255,0.25)` |

### Spacing

| Context | Value |
|---|---|
| Feed container padding | `8px 16px 24px` |
| Feed card gap | 20px |
| Feed card border-radius | 28px |
| Feed card friend indicator padding | `18px 20px 12px` |
| Feed card message content padding | `16px 20px` |
| Feed card footer padding | `12px 20px 18px` |
| Conversation body padding | `8px 16px 24px` |
| Letter card gap | 16px |
| Letter card border-radius | 24px |
| Letter card header padding | `14px 16px 8px` |
| Letter card body padding | `4px 16px 16px` |
| Conversation header padding | `16px 20px` |
| Compose container padding | `12px 16px` |
| Compose input padding | `12px 16px` |
| Compose input border-radius | 22px |
| Empty state padding | `40px 32px` |
| Origin marker padding | `24px 16px 16px` |

### Avatar Sizes

| Context | Size |
|---|---|
| Feed card | 42px |
| Conversation header | 36px |
| Letter card | 32px |
| Empty state (large) | 80px |
| Origin marker (compact) | 48px |

### Animations

| Animation | Duration | Easing | Delay |
|---|---|---|---|
| Feed card entrance (`cardEnter`) | 600ms | ease | stagger 100ms |
| Screen transition — card expand | 360ms | `cubic-bezier(0.16, 1, 0.3, 1)` | 0 |
| Screen transition — card lift | 200ms | `cubic-bezier(0.16, 1, 0.3, 1)` | 0 |
| Screen transition — background morph | 300ms | ease | 100ms |
| Screen transition — compose entrance | 300ms | ease + cubic-bezier | 300ms |
| Sibling card fade | 200ms | ease-out | 0 |
| Content reveal | 340ms | ease / cubic-bezier | 200ms |
| Letter card reveal (`letterReveal`) | 400ms | ease | stagger 50ms |
| Letter send entrance (`letterSend`) | 400ms | `cubic-bezier(0.16, 1, 0.3, 1)` | 150ms |
| Letter receive entrance (`letterReceive`) | 500ms | `cubic-bezier(0.16, 1, 0.3, 1)` | 0 |
| Send button pulse (`sendPulse`) | 300ms | ease | 0 |
| Anchor highlight fade (`anchorPulse`) | 2000ms | ease-out | 500ms |
| Edge glow pulse (`edgeGlowPulse`) | 1500ms | ease-out | 0 |
| Input focus border | 200ms | ease | 0 |
| Send button appear/hide | 250ms | ease | 0 |
| Empty state dissolve | 400ms | ease | 0 |
| First letter appear | 400ms | `cubic-bezier(0.16, 1, 0.3, 1)` | 400ms |
| Empty state ambient glow (`emptyStateGlow`) | 6000ms | ease-in-out | infinite loop |

### Z-Index

| Element | Z-Index |
|---|---|
| Conversation header | 100 |
| Compose container | 50 |
| Context menu | 200 |
| Letter cards | 1 |
| Empty state content | 1 |
| Ambient background | 0 |

---

## Design Rationale

| Decision | Why |
|---|---|
| Large avatar in empty state | This is a person, not a feature. Center them. |
| "Write the first letter" prompt | The word "letter" sets the emotional tone — this is not a chat app, it's an exchange of personal letters. |
| Dashed divider | Visually separates the connection event from the call to action without feeling heavy. Dashes suggest something incomplete, waiting to be filled in. |
| Breathing ambient glow | The screen is alive and waiting, not static and dead. Subtle motion signals possibility. |
| Send button hidden until text exists | Reduces visual clutter on an already minimal screen. The action appears when the intent does. |
| Empty state dissolves, doesn't slide | A dissolve feels like a transformation — the potential becomes reality. A slide would feel like navigating away. |
| Compact origin marker persists after send | The "Connected!" moment becomes a permanent marker at the top of the conversation — like the first page of a journal noting when it was started. |
| No nav bar in conversation | This is an intimate, focused space. The user should be thinking about their friend, not about navigating elsewhere. |
| Feed stays incoming-only | The Feed says "From your people" — it's a curated inbox of letters received. Sent messages live in the Conversation screen, not the Feed. Scarcity creates value. |
| Feed card matches Feed C style | Consistency. A message from a new connection should look identical to a message from an existing friend. No special treatment — they've been welcomed into the circle. |
| Full-width letter cards (not L/R bubbles) | Avoids chat-app visual patterns. Reinforces the shared-journal metaphor. |
| Left accent = received, right accent = sent | Subtle authorship cue without spatial chat alignment. You can tell who wrote what at a glance from the colored edge. |
| Sent cards visually recessed | Your own words feel less novel than theirs. The slight opacity reduction creates a natural reading hierarchy — their letters are the ones you came to read. |
| No read receipts or typing indicators | Privacy-first. This is correspondence, not surveillance. Letters arrive as complete thoughts. |
| "Delivered" at 15% opacity | Your letter left your hands; it belongs to them now. No "Read" state, no tracking. Just quiet acknowledgment that it was sent. |
| "Write something..." placeholder | Verb "write" reinforces letter metaphor over "type" or "send." |
| No character counter (gentle hint at 2000+) | "Long letters are lovely" — warm encouragement over cold restriction. |
| Anchor message highlight fades over 2s | Orients the user without permanent visual noise. |
| Swipe-back matches iOS patterns | Familiar navigation reduces cognitive load. |
| Card expansion transition from Feed | User should feel they are stepping *inside* the card — continuity between feed and conversation. |
| Card morph transition from 1st Contact | The person (avatar) smoothly becomes the conversation context — continuity between connection and correspondence. |
