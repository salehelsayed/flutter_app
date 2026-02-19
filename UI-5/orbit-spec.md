# Orbit — Inner Circle / Friends Screen Design Spec

**Screen name:** Orbit (Circle 2)
**Entry point:** Tapping "Orbit" tab in the bottom `NavigationBar`
**Purpose:** The user's central hub for managing their social graph — viewing their closest friends on an orbital visualization, browsing all friends, searching, and accessing QR-based friend-adding features

---

## IMPORTANT: Reuse Existing Components

Before implementing anything in this spec, **audit the existing Flutter codebase** to identify widgets, services, utilities, themes, and patterns that are already built. Do NOT re-implement what already exists.

The spec below describes the design using **platform-agnostic names** (e.g. "RingBrandedAvatar", "NavigationBar"). These are logical component names — not file paths. Your job is to find the Flutter equivalents in the project. The following concepts are expected to already exist in the app:

| Concept | What to Look For | What It Does |
|---|---|---|
| Branded Avatar Generator | A widget that generates a unique avatar from a peer ID / hash string. Used as fallback when no photo exists. | Search for widgets related to avatar generation, peer ID hashing, or ring-based SVG/canvas rendering. |
| Bottom Navigation Bar | A bottom tab bar with Feed / Remember / Orbit tabs. | Search for a shared navigation widget, bottom bar, or tab controller. |
| Scroll-Based Visibility | Logic that hides/shows floating UI (e.g. FABs, bottom bars) based on scroll direction. | Search for scroll listeners, `ScrollController` usage, or visibility toggle logic. |
| Current User Data | The logged-in user's model (name, username, peer ID, QR data, etc.). | Search for a user model, auth state, or user provider/service. |
| Theme System | A theme/color scheme that screens receive (dark mode, accent colors, glass effects). | Search for `ThemeData`, custom theme classes, or color constant files. |
| QR Code Screen | A screen that displays the user's QR code and optionally opens a QR scanner. | **Already exists in the app.** Do not rebuild — navigate to it. |
| Conversation Screen | A screen showing the full message history between two users, with compose area. Supports an empty/first-conversation state. | Search for conversation, chat, or letter screen widgets. |
| Glassmorphic Styling | Frosted glass backgrounds (`BackdropFilter`, semi-transparent containers). | Search for shared glass card widgets or backdrop filter helpers. |
| Ambient Background | Floating radial gradient decoration behind screen content. | Search for background gradient or ambient decoration widgets. |
| Card Entrance Animation | Staggered slide-up + fade-in animation used for list items across screens. | Search for shared animation builders, stagger helpers, or `AnimationController` patterns. |

**Implementation rule:** For every component described in this spec, search the codebase first. If a Flutter equivalent exists, import and reuse it. Only create new code for functionality that is genuinely new to this screen (e.g. the orbit placement algorithm driven by `messageCount`, the search collapse animation, friend row tap-to-conversation navigation).

---

## Screen Overview

The Orbit screen is the user's social map. At the top, an orbital visualization places the user at the center, with their closest friends arranged in concentric rings based on conversation activity. Below the orbital, a scrollable list of all friends provides quick access to profiles and conversations. A floating search bar at the bottom allows instant filtering, and when activated, the orbital collapses to give maximum space to search results.

This screen answers the question: "Who are my people, and who am I closest to right now?"

```
+------------------------------------------+
| [X]                                      |  <- Close button (top-left, sticky)
|                              [Avatar 44] |  <- User's avatar (top-right)
|                                          |
|           YOUR INNER CIRCLE              |  <- Section title
|                                          |
|             ╭─ ─ ─ ─ ─╮                 |
|          ╭──│─ ─ ─ ─ ─│──╮              |  <- Orbit ring 2 (8 friends)
|         ╱   │  ○   ○  │   ╲             |
|        ○    │ ╭─────╮ │    ○             |  <- Orbit ring 1 (5 friends)
|        │    │ │ YOU │ │    │             |  <- Center: user avatar
|        ○    │ ╰─────╯ │    ○             |
|         ╲   │  ○   ○  │   ╱             |
|          ╰──│─ ─ ─ ─ ─│──╯              |
|             ╰─ ─ ─ ─ ─╯         +87     |  <- Overflow badge
|                                          |
|             Close Friends                |  <- Subtitle
|                                          |
|  Friends                  [My QR] [Scan] |  <- List header + action buttons
|  ┌──────────────────────────────────────┐|
|  │ [Avatar] Sarah         Active now   >││  <- Friend row
|  │          @sarah_1                    ││
|  │          Sent you a voice note       ││
|  ├──────────────────────────────────────┤│
|  │ [Avatar] Mike          2m ago       >││
|  │          @mike_2                     ││
|  │          Shared a memory             ││
|  ├──────────────────────────────────────┤│
|  │ [Avatar] Emma          5m ago       >││
|  │          ...                         ││
|  └──────────────────────────────────────┘│
|                                          |
|  ┌─────────────┐  ┌─────────────┐       |  <- QR action cards
|  │ [QR icon]   │  │ [Cam icon]  │       |
|  │ My QR Code  │  │ Scan QR     │       |
|  │ Share to add│  │ Add instant │       |
|  └─────────────┘  └─────────────┘       |
|                                          |
+------------------------------------------+
| [🔍 Search friends...]            [X]    |  <- Floating search trigger
+------------------------------------------+
```

---

## Data Model and Database Relationship

### Friend Object

Each friend in the system has the following shape. The `messageCount` field is critical — it drives the orbital ring placement algorithm.

```js
{
  id: Number,                  // Unique friend ID
  name: String,                // Display name (e.g. "Sarah")
  username: String,            // Handle without @ prefix (e.g. "sarah_1")
  peerId: String,              // Peer-to-peer connection identifier (used for RingBrandedAvatar generation)
  avatar: String | null,       // URL to avatar image, or null (falls back to RingBrandedAvatar)
  color: String,               // Hex color for avatar border/glow (e.g. "#4ecdc4")
  status: 'online' | 'offline',
  lastActivity: String,        // Most recent activity description (e.g. "Sent you a voice note")
  lastSeen: String,            // Human-readable time (e.g. "Active now", "2m ago", "1d ago")
  messageCount: Number,        // Total messages exchanged (sent + received). Queried from the conversation database. Determines orbit placement.
  connectedDate: String,       // When the connection was established (e.g. "February 9, 2026")
}
```

### Orbit Placement Algorithm

Friends are **sorted by `messageCount` descending** (most-chatted first), then distributed across exactly 2 orbital rings:

```js
// Sort all friends by message count (most active conversations first)
const sorted = [...allFriends].sort((a, b) => b.messageCount - a.messageCount)

// Ring 1 (inner): Top 5 friends by message count
// Ring 2 (outer): Next 8 friends by message count
// Remaining friends: Shown only in the list below, not on the orbital
const RING_1_COUNT = 5
const RING_2_COUNT = 8
const INNER_CIRCLE_COUNT = RING_1_COUNT + RING_2_COUNT  // 13 total on orbits

const ring1Friends = sorted.slice(0, RING_1_COUNT)
const ring2Friends = sorted.slice(RING_1_COUNT, INNER_CIRCLE_COUNT)
const remainingCount = sorted.length - INNER_CIRCLE_COUNT
```

**Important:** The orbit is not static decoration — it is a live reflection of the user's actual conversation patterns. If a user starts messaging someone new frequently, that friend's avatar will move to an inner ring over time. This creates a dynamic, honest map of the user's real relationships.

### Relationship to Other Screens

| Screen | Relationship |
|---|---|
| **Feed (Feed C)** | Tapping a friend row in the Orbit list opens that friend's **Conversation Screen** (same as tapping Reply on a Feed card). If no conversation exists, it opens Conv. (1st) — the empty first-conversation screen. |
| **Conversation Screen** | The Orbit is the primary way to initiate a conversation with any friend. Tapping a friend row navigates to `ConversationScreen` with that friend's data. The `messageCount` used for orbit sorting is derived from counting messages in the conversation history. |
| **Conv. (1st)** | If a friend has `messageCount === 0` (connected but never messaged), tapping their row opens the first-conversation empty state screen. |
| **1st Contact D** | After a new connection is made (via QR scan), the new friend appears in the Orbit list and on the outer ring (they start with `messageCount: 0`). |
| **My QR Screen** | The "My QR" button on the Orbit screen navigates to the existing `QRCodeScreen` component. See Section 8 for details. |
| **Scan QR Screen** | The "Scan" button navigates to `QRCodeScreen` with `startWithScanner={true}`. |
| **NavigationBar** | The Orbit screen is one of three tabs: Feed / Remember / Orbit. The "Orbit" tab is highlighted as active (`activeTab="circle"`). |

### How `messageCount` Is Computed

The `messageCount` for each friend should be derived from the conversation database:

```js
// Pseudocode — count all messages (sent + received) for a given friend
function getMessageCount(friendId) {
  return db.messages
    .filter(msg => msg.conversationWith === friendId)
    .length
}
```

This count is recalculated whenever the Orbit screen is opened (or on a reasonable interval) so the orbital visualization stays current.

---

## Anatomy — Top to Bottom

### 1. Screen Container

The entire screen is a full-height scrollable container with an ambient background.

| Property | Value |
|---|---|
| Layout | `display: flex; flex-direction: column` inside a `screen-frame` wrapper |
| Height | `100%` of the screen frame |
| Background | Theme-driven via `--theme-bg` (defaults to `linear-gradient(180deg, #0f0f18 0%, #0a0a0f 100%)`) |
| Overflow | `overflow-y: auto` on the inner `app-container` |
| Ambient BG | Standard `.ambient-bg` element — floating radial gradients that drift behind all content |

---

### 2. Close Button (Sticky)

A small circular button pinned to the top-left corner. Returns the user to the Feed screen.

| Property | Value |
|---|---|
| Position | `sticky`, `top: 0`, `z-index: 200`. Wrapped in a zero-height container with `pointer-events: none` (button itself is `pointer-events: auto`) |
| Size | `36x36px` |
| Shape | Circle (`border-radius: 50%`) |
| Background | `rgba(255,255,255,0.1)` |
| Backdrop filter | `blur(12px)` |
| Border | `1px solid rgba(255,255,255,0.12)` |
| Icon | X mark (two diagonal lines), `16x16px`, `strokeWidth: 2.5`, `rgba(255,255,255,0.8)` |
| Action | Navigates to `feedC` (the main Feed screen) |

---

### 3. Header Area

Minimal header showing only the user's own avatar, right-aligned.

| Property | Value |
|---|---|
| Layout | `display: flex; justify-content: flex-end` |
| Class | `.header-minimal` |
| Avatar | User's `RingBrandedAvatar` at `44px` (generated from `currentUser.qrCode` peer ID) |

---

### 4. Orbital Visualization Section

The signature UI element — a visual map of the user's closest friends arranged in concentric rings.

#### 4a. Section Container (`.circle-orbital-section`)

| Property | Value |
|---|---|
| Text align | `center` |
| Padding | `20px 0` |

#### 4b. Section Title

| Property | Value |
|---|---|
| Content | "YOUR INNER CIRCLE" |
| Font size | `14px` |
| Font weight | `600` |
| Color | `var(--text-muted)` — `rgba(255,255,255,0.4)` |
| Text transform | `uppercase` |
| Letter spacing | `1px` |
| Margin bottom | `24px` |

#### 4c. Orbital Container (`.circle-orbital.circle-orbital-large`)

| Property | Value |
|---|---|
| Size | `320x320px` |
| Position | `relative` |
| Margin | `0 auto` (centered) |

#### 4d. Orbital Rings (`.orbital-rings`)

Two concentric dashed circles representing the relationship tiers. Rendered as absolutely positioned elements within the orbital container.

| Ring | Spec |
|---|---|
| **Ring 1 (inner)** | `inset: 98px` (i.e. `160px center - 62px radius`). Border: `1px dashed rgba(129,230,217,0.12)` (teal tint). `box-shadow: 0 0 8px rgba(129,230,217,0.03)` |
| **Ring 2 (outer)** | `inset: 52px` (i.e. `160px center - 108px radius`). Border: `1px dashed rgba(167,139,250,0.10)` (purple tint). `box-shadow: 0 0 8px rgba(129,230,217,0.03)` |

The rings use `position: absolute; border-radius: 50%` and are purely decorative guides.

#### 4e. Center Avatar (`.orbital-center`)

The user's own avatar sits at the exact center of the orbital.

| Property | Value |
|---|---|
| Position | Absolute, `top: 50%; left: 50%; transform: translate(-50%, -50%)` |
| Size | `48px` (rendered via `RingBrandedAvatar`) |
| Shape | Circle (`border-radius: 50%; overflow: hidden`) |
| Box shadow | `none` (clean, no glow) |

#### 4f. Orbital Friends (`.orbital-friend`)

Each friend avatar is positioned on its ring using trigonometric calculation.

**Positioning formula:**

```js
// For each friend on ring `ringIndex` at position `i`:
const offset = ringIndex * 15                          // Stagger rotation per ring
const angle = (i * (360 / ring.count) + offset - 90) * (Math.PI / 180)  // -90 starts from top
const x = Math.cos(angle) * ring.radius
const y = Math.sin(angle) * ring.radius
// Applied via CSS custom properties: --x and --y
```

| Property | Value |
|---|---|
| Position | Absolute, `top: 50%; left: 50%; transform: translate(calc(-50% + var(--x)), calc(-50% + var(--y)))` |
| Shape | Circle (`border-radius: 50%; overflow: hidden`) |
| Box shadow | `none` |
| Entry animation | `orbitFadeIn 0.5s ease backwards` — scales from `0` to `1`, with staggered delay (`globalIndex * 0.04s`) |

**Ring 1 friends (inner orbit):**

| Property | Value |
|---|---|
| Count | `5` friends |
| Radius | `62px` from center |
| Avatar size | `38x38px` |
| Border | `1.5px solid rgba(255,255,255,0.12)` |

**Ring 2 friends (outer orbit):**

| Property | Value |
|---|---|
| Count | `8` friends |
| Radius | `108px` from center |
| Avatar size | `30x30px` |
| Border | `1px solid rgba(255,255,255,0.08)` |

**Avatar rendering:**
- If `friend.avatar` exists: `<img>` with `object-fit: cover`, matching the ring's avatar size, class `.orbital-friend-img`
- If `friend.avatar` is `null`: `<RingBrandedAvatar>` generated from `friend.peerId`

**Online indicator (`.orbital-online-dot`):**
Only shown for friends with `status: 'online'`. A small green dot at the bottom-right of the avatar.

| Property | Value |
|---|---|
| Size | `10x10px` (ring 1), `7x7px` (ring 2) |
| Background | `#1DB954` |
| Border | `2px solid #0a0a0f` (matches screen background) |
| Position | `absolute; bottom: 2px; right: 2px` |

#### 4g. Overflow Badge (`.orbital-overflow`)

When there are more friends than the 13 slots on the two orbits, a "+N" badge appears on the outer ring.

| Property | Value |
|---|---|
| Position | Placed at the next angular position after the last friend on ring 2 |
| Size | `28x28px` |
| Shape | Circle (`border-radius: 50%`) |
| Background | `rgba(255,255,255,0.06)` |
| Border | `1px dashed rgba(255,255,255,0.2)` |
| Backdrop filter | `blur(4px)` |
| Font size | `10px` |
| Font weight | `600` |
| Color | `rgba(255,255,255,0.5)` |
| Letter spacing | `-0.5px` |
| Content | "+N" where N = `totalFriends - 13` |
| Entry animation | `orbitFadeIn 0.5s ease backwards`, delay `1s` |

#### 4h. Subtitle (`.circle-count`)

| Property | Value |
|---|---|
| Content | "Close Friends" |
| Font size | `14px` |
| Color | `var(--text-secondary)` — `rgba(255,255,255,0.6)` |
| Margin top | `20px` |

---

### 5. Friends List Section

The full list of all friends (not just inner circle), scrollable below the orbital.

#### 5a. Feed Container (`.circle-feed`)

| Property | Value |
|---|---|
| Padding | `8px 16px 24px` |
| Layout | `display: flex; flex-direction: column; gap: 24px` |
| Bottom padding | `100px` when search inactive (room for floating trigger), `320px` when search active (room for keyboard dock) |
| Transition | `padding-bottom 0.56s cubic-bezier(0.22, 0.61, 0.36, 1)` |

#### 5b. List Header (`.circle-list-header`)

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; justify-content: space-between` |
| Padding | `0 4px` |
| Margin bottom | `8px` |

**Title:**

| Property | Value |
|---|---|
| Content | "Friends" |
| Font size | `16px` |
| Font weight | `600` |
| Color | `var(--text-primary)` — `rgba(255,255,255,0.95)` |

**Action buttons (right side, hidden during search):**

Two pill buttons side by side with `gap: 8px`:

| Button | Label | Icon | Action |
|---|---|---|---|
| My QR | "My QR" | QR code grid SVG | Navigates to `qrCode` screen |
| Scan | "Scan" | Camera SVG | Navigates to `scanQR` screen |

**Button shared style (`.circle-add-btn`):**

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; gap: 6px` |
| Padding | `8px 14px` |
| Background | `rgba(29,185,84,0.15)` |
| Border | `1px solid rgba(29,185,84,0.3)` |
| Border radius | `10px` |
| Icon | `16x16px`, color `#1DB954` |
| Label | `13px`, weight `600`, color `#1DB954` |
| Hover | Background `rgba(29,185,84,0.25)` |

#### 5c. Friend Row (`.circle-friend-row`)

Each friend is rendered as a full-width tappable card.

```
┌──────────────────────────────────────────────────┐
│  [Avatar 48px]   Sarah            Active now   > │
│    (●)           @sarah_1                        │
│                  Sent you a voice note           │
└──────────────────────────────────────────────────┘
```

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; gap: 14px` |
| Padding | `14px 16px` |
| Background | `var(--glass-bg)` — `rgba(255,255,255,0.08)` |
| Border | `1px solid var(--glass-border)` — `rgba(255,255,255,0.12)` |
| Border radius | `16px` |
| Cursor | `pointer` |
| Entry animation | `cardEnter 0.4s ease backwards`, staggered by `index * 0.02s` |
| Hover | `background: rgba(255,255,255,0.06); border-color: rgba(255,255,255,0.15)` |
| Action | Tapping a friend row should navigate to that friend's **Conversation Screen**. If `messageCount === 0`, open **Conv. (1st)** instead. |

**Avatar area (`.circle-friend-avatar`):**

| Property | Value |
|---|---|
| Size | `48x48px` |
| Shape | Circle |
| Overflow | `hidden` |
| Flex shrink | `0` |
| Image | `object-fit: cover`, class `.circle-friend-img` |
| Fallback | `RingBrandedAvatar` at `48px` if no avatar URL |
| Online dot | `.circle-online-dot` — `12x12px`, `#1DB954`, `border: 2px solid #0a0a0f`, positioned `absolute; bottom: 2px; right: 2px` |

**Friend info column (`.circle-friend-info`):**

| Element | Spec |
|---|---|
| Container | `flex: 1; display: flex; flex-direction: column; gap: 2px` |
| Name (`.circle-friend-name`) | `15px`, weight `600`, `var(--text-primary)` |
| Username (`.circle-friend-username`) | `13px`, weight `400`, `var(--text-muted)` |
| Activity (`.circle-friend-activity`) | `12px`, weight `400`, `var(--text-secondary)`, `margin-top: 2px` |

**When searching:** If the friend is part of the Inner Circle (top 13 by message count), an **"Inner Circle" badge** appears inline after their name:

| Property | Value |
|---|---|
| Class | `.search-inner-badge` |
| Font size | `10px` |
| Font weight | `600` |
| Letter spacing | `0.3px` |
| Padding | `2px 7px` |
| Margin left | `8px` |
| Border radius | `10px` |
| Background | `rgba(29,185,84,0.15)` |
| Color | `rgba(29,185,84,0.8)` |
| Vertical align | `middle` |

**Meta column (`.circle-friend-meta`):**

| Element | Spec |
|---|---|
| Container | `display: flex; flex-direction: column; align-items: flex-end; gap: 4px` |
| Time (`.circle-friend-time`) | `12px`, `var(--text-muted)` |
| Chevron | Right-pointing SVG, `16x16px`, `var(--text-muted)` |

#### 5d. No Results State (`.search-overlay-empty`)

Shown when search is active, a query exists, but no friends match.

| Property | Value |
|---|---|
| Layout | `flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px` |
| Padding top | `60px` |
| Icon | Search magnifying glass SVG, `40x40px`, `opacity: 0.25` |
| Text | `No friends matching "[query]"`, `15px`, `rgba(255,255,255,0.3)` |

---

### 6. QR Action Cards

Two side-by-side cards at the bottom of the friend list, providing quick access to QR features. **Hidden during search.**

```
┌─────────────────┐  ┌─────────────────┐
│    [QR Icon]    │  │   [Cam Icon]    │
│   My QR Code    │  │    Scan QR      │
│ Share to add    │  │ Add a friend    │
│   friends       │  │   instantly     │
└─────────────────┘  └─────────────────┘
```

#### Card Container (`.circle-add-card`)

| Property | Value |
|---|---|
| Layout | `flex; flex-direction: column; align-items: center; gap: 10px; flex: 1` |
| Padding | `18px 12px` |
| Background | `rgba(29,185,84,0.08)` |
| Border | `1px solid rgba(29,185,84,0.2)` |
| Border radius | `20px` |
| Text align | `center` |
| Cursor | `pointer` |
| Hover | `background: rgba(29,185,84,0.12); border-color: rgba(29,185,84,0.3)` |

**Icon container (`.circle-add-icon`):**

| Property | Value |
|---|---|
| Size | `44x44px` |
| Border radius | `14px` |
| Background | `rgba(29,185,84,0.2)` |
| Icon | `22x22px` SVG, color `#1DB954` |

**Left card ("My QR Code"):**
- Icon: QR code grid SVG
- Title: "My QR Code" — `14px`, weight `600`, `var(--text-primary)`
- Subtitle: "Share to add friends" — `11px`, `var(--text-muted)`
- Action: Navigates to the existing `QRCodeScreen` component (`onSwitchView('qrCode')`)

**Right card ("Scan QR"):**
- Icon: Camera SVG
- Title: "Scan QR" — `14px`, weight `600`, `var(--text-primary)`
- Subtitle: "Add a friend instantly" — `11px`, `var(--text-muted)`
- Action: Navigates to `QRCodeScreen` with scanner mode (`onSwitchView('scanQR')`)

---

### 7. Search System

The search system has three interconnected parts: a floating trigger at the bottom, a collapsible header/orbital section, and a bottom-docked search bar with keyboard.

#### 7a. Floating Search Trigger (`.circle-search-trigger`)

A frosted-glass pill that floats above the bottom of the screen when the user is NOT actively searching.

```
┌──────────────────────────────────────────┐
│  🔍  Search friends...            [X]    │
└──────────────────────────────────────────┘
```

| Property | Value |
|---|---|
| Position | `absolute; bottom: 40px; left: 50%` |
| Width | `75%`, `max-width: 320px` |
| Z-index | `101` |
| Transform (hidden) | `translate(-50%, 14px) scale(0.985)` |
| Transform (visible) | `translate(-50%, 0) scale(1)` |
| Opacity transition | `0.34s ease` |
| Transform transition | `0.46s cubic-bezier(0.22, 0.61, 0.36, 1)` |
| Visibility | Only shown when `!searchActive && isNavVisible` (hides on scroll-down) |

**Contains two elements side by side (`gap: 10px`):**

1. **Search button (left, flex: 1):**

| Property | Value |
|---|---|
| Padding | `10px 16px` |
| Background | `rgba(30,30,35,0.85)` |
| Backdrop filter | `blur(20px)` |
| Border | `1px solid rgba(255,255,255,0.1)` |
| Border radius | `24px` |
| Color | `rgba(255,255,255,0.35)` |
| Font size | `14px` |
| Content | Search icon SVG (`15x15px`, `opacity: 0.5`) + "Search friends..." text |
| Action | Opens the search mode (see 7c) |

2. **Close button (right):**

| Property | Value |
|---|---|
| Size | `38x38px` |
| Shape | Circle |
| Background | `rgba(30,30,35,0.9)` |
| Backdrop filter | `blur(20px)` |
| Border | `1px solid rgba(255,255,255,0.14)` |
| Icon | X mark, `15x15px`, `rgba(255,255,255,0.72)` |
| Action | Navigates back to Feed (`onSwitchView('feedC')`) |

#### 7b. Collapsible Section (Header + Orbital)

When search activates, the header and orbital visualization collapse upward to give maximum vertical space to the search results.

**Outer shell (`.circle-collapsible-shell`):**

| Property | Value |
|---|---|
| Display | `grid` |
| Grid template rows (default) | `1fr` |
| Grid template rows (hidden) | `0fr` |
| Transition | `grid-template-rows 0.58s cubic-bezier(0.22, 0.61, 0.36, 1)` |

**Inner content (`.circle-collapsible`):**

| Property | Value |
|---|---|
| Min height | `0` (required for grid collapse) |
| Overflow | `hidden` |
| Default state | `opacity: 1; transform: translateY(0) scale(1)` |
| Hidden state | `opacity: 0; transform: translateY(-16px) scale(0.985); pointer-events: none` |
| Transitions | `opacity 0.42s ease`, `transform 0.5s cubic-bezier(0.22, 0.61, 0.36, 1)` |
| Transform origin | `top center` |
| Will-change | `opacity, transform` |

**Animation sequence when search opens:**
1. The orbital section and header fade up and shrink (`translateY(-16px) scale(0.985)`) over ~500ms
2. Simultaneously, the grid row collapses from `1fr` to `0fr` over ~580ms
3. The friends list slides up smoothly to fill the freed space
4. The bottom search dock slides up from below

**Animation sequence when search closes:**
1. The bottom dock slides down
2. The grid row expands back to `1fr`
3. The orbital fades back in with a subtle downward slide

#### 7c. Bottom Search Dock (`.search-bottom-dock`)

A docked panel that slides up from the bottom of the screen containing the search input and a simulated keyboard.

| Property | Value |
|---|---|
| Position | `absolute; bottom: 0; left: 0; right: 0` |
| Z-index | `200` |
| Background | `rgba(18,18,22,0.98)` |
| Border top | `1px solid rgba(255,255,255,0.08)` |
| Default state | `transform: translateY(100%)` (hidden below screen) |
| Active state | `transform: translateY(0)` |
| Transition | `transform 0.56s cubic-bezier(0.22, 0.61, 0.36, 1)` |

**Search bar row (`.search-bottom-bar`):**

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; gap: 10px` |
| Padding | `10px 14px` |

**Input wrapper (`.search-overlay-input-wrap`):**

| Property | Value |
|---|---|
| Layout | `flex: 1; display: flex; align-items: center; gap: 10px` |
| Padding | `10px 14px` |
| Background | `rgba(255,255,255,0.06)` |
| Border | `1px solid rgba(255,255,255,0.1)` |
| Border radius | `24px` |

**Search input (`.search-overlay-input`):**

| Property | Value |
|---|---|
| Background | `transparent` |
| Color | `#fff` |
| Font size | `15px` |
| Placeholder | "Search friends..." in `rgba(255,255,255,0.3)` |
| Border | `none` |
| Outline | `none` |
| Flex | `1` |

**Clear button (`.search-overlay-clear`):** (only visible when query is non-empty)

| Property | Value |
|---|---|
| Size | `28x28px` |
| Shape | Circle |
| Background | `rgba(255,255,255,0.1)` |
| Icon | X mark, `16x16px`, `rgba(255,255,255,0.5)` |
| Action | Clears the search query and refocuses the input |

**Close button (`.search-overlay-close`):**

| Property | Value |
|---|---|
| Size | `38x38px` |
| Shape | Circle |
| Background | `rgba(30,30,35,0.9)` |
| Border | `1px solid rgba(255,255,255,0.14)` |
| Icon | X mark, `15x15px`, `rgba(255,255,255,0.72)` |
| Action | Closes search mode, clears query, restores orbital |

#### 7d. Simulated Keyboard (`.sim-keyboard`)

A QWERTY keyboard rendered in the bottom dock for the prototype/demo. In production, this would be the native OS keyboard.

| Property | Value |
|---|---|
| Padding | `6px 4px 14px` |
| Layout | `flex; flex-direction: column; gap: 6px` |
| Background | `rgba(28,28,32,0.98)` |

**Key layout (4 rows):**

```
Row 1: q w e r t y u i o p
Row 2: a s d f g h j k l
Row 3: [shift] z x c v b n m [del]
Row 4: [123]  [        space        ]  [go]
```

**Standard key (`.sim-kb-key`):**

| Property | Value |
|---|---|
| Height | `40px` |
| Min width | `30px` |
| Max width | `36px` |
| Flex | `1` |
| Background | `rgba(255,255,255,0.12)` |
| Border | `none` |
| Border radius | `6px` |
| Color | `#fff` |
| Font size | `15px` |
| Active state | `background: rgba(255,255,255,0.28)` |

**Function key (`.sim-kb-key--fn` — shift, del, 123):**

| Property | Value |
|---|---|
| Flex | `1.4` |
| Max width | `48px` |
| Background | `rgba(255,255,255,0.07)` |
| Font size | `13px` |
| Color | `rgba(255,255,255,0.7)` |

**Space key (`.sim-kb-key--space`):**

| Property | Value |
|---|---|
| Flex | `6` |
| Max width | `none` |
| Font size | `13px` |
| Color | `rgba(255,255,255,0.5)` |

**Go key (`.sim-kb-key--go`):**

| Property | Value |
|---|---|
| Background | `rgba(29,185,84,0.35)` |
| Color | `#1DB954` |
| Font weight | `600` |

#### 7e. Search Filtering Logic

The search filters the friends list in real-time as the user types:

```js
const query = searchQuery.toLowerCase().trim()
const displayedFriends = query
  ? allFriends.filter(f =>
      f.name.toLowerCase().includes(query) ||
      f.username.toLowerCase().includes(query)
    )
  : allFriends
```

- **No query:** Show all friends
- **With query:** Filter by name OR username (case-insensitive, substring match)
- **No results:** Show the empty state (Section 5d)
- **Inner Circle badge:** When searching, friends who are in the Inner Circle (orbit positions 0-12) show an "Inner Circle" badge next to their name to help identify them in filtered results

---

### 8. My QR / Scan QR Integration

The Orbit screen provides two entry points to the QR system. **Both navigate to the existing `QRCodeScreen` component** — no new QR screen needs to be built.

| Entry Point | Navigation Call | Behavior |
|---|---|---|
| "My QR" header button | `onSwitchView('qrCode')` | Opens QR screen showing the user's own QR code for others to scan |
| "My QR Code" bottom card | `onSwitchView('qrCode')` | Same as above |
| "Scan" header button | `onSwitchView('scanQR')` | Opens QR screen with the camera/scanner active (`startWithScanner={true}`) |
| "Scan QR" bottom card | `onSwitchView('scanQR')` | Same as above |

The QR screen's back button returns to the Orbit screen (`previousView` is tracked by the app's navigation state).

---

## 9. Animations

### 9a. Orbit Avatar Entrance (`orbitFadeIn`)

When the screen first loads, each orbital avatar scales in from nothing.

```css
@keyframes orbitFadeIn {
  from {
    opacity: 0;
    transform: translate(calc(-50% + var(--x)), calc(-50% + var(--y))) scale(0);
  }
  to {
    opacity: 1;
    transform: translate(calc(-50% + var(--x)), calc(-50% + var(--y))) scale(1);
  }
}
```

| Property | Value |
|---|---|
| Duration | `500ms` |
| Easing | `ease` |
| Fill | `backwards` |
| Stagger | `globalIndex * 40ms` (ring 1 friends animate first, then ring 2) |

### 9b. Friend Row Entrance (`cardEnter`)

Friend rows in the list stagger in with a subtle slide-up.

| Property | Value |
|---|---|
| Duration | `400ms` |
| Easing | `ease` |
| Fill | `backwards` |
| Stagger | `index * 20ms` |

### 9c. Search Transition

The search open/close is a coordinated multi-element animation:

| Element | Animation | Duration | Easing |
|---|---|---|---|
| Collapsible shell (grid rows) | `1fr` to `0fr` | `580ms` | `cubic-bezier(0.22, 0.61, 0.36, 1)` |
| Collapsible content (opacity + transform) | Fade out + slide up | `420-500ms` | `ease` / `cubic-bezier(0.22, 0.61, 0.36, 1)` |
| Bottom dock (slide up) | `translateY(100%)` to `translateY(0)` | `560ms` | `cubic-bezier(0.22, 0.61, 0.36, 1)` |
| Friends list padding | `100px` to `320px` | `560ms` | `cubic-bezier(0.22, 0.61, 0.36, 1)` |
| Floating trigger | Fades out (driven by state change) | `340ms` | `ease` |

### 9d. Overflow Badge Entrance

The "+N" overflow badge appears after the orbital friends have finished animating.

| Property | Value |
|---|---|
| Animation | `orbitFadeIn` (same as friends) |
| Delay | `1s` (waits for all friend avatars to appear first) |

---

## 10. Navigation and Screen Transitions

### 10a. Entry: From NavigationBar

The Orbit screen is accessed by tapping the **"Orbit" tab** in the bottom `NavigationBar`. The NavigationBar has three tabs:

| Tab | Label | Navigates To |
|---|---|---|
| Feed | "Feed" | `feed` / `feedC` |
| Remember | "Remember" | `memories` |
| **Orbit** | **"Orbit"** | **`circle2`** |

When Orbit is active, the "Orbit" tab shows the active pill highlight style (glass gradient, elevated, white text).

### 10b. Exit: Close Button

The close button (X, top-left) navigates back to the Feed screen (`feedC`). The floating trigger's close button does the same.

### 10c. Exit: Friend Row Tap

Tapping a friend row navigates to their conversation:

```js
// Pseudocode for friend row tap handler
function handleFriendTap(friend) {
  if (friend.messageCount === 0) {
    // No conversation history — open first-conversation empty state
    navigateTo('conversationEmpty', { friend })
  } else {
    // Has conversation history — open full conversation
    navigateTo('conversation', { friend })
  }
}
```

### 10d. NavigationBar Visibility

The Orbit screen does NOT render the standard `NavigationBar` component. Instead, it has its own floating search trigger at the bottom that serves a similar docking position. The `NavigationBar` is only shown on Feed, Remember, and the Contact screens.

The close/X buttons on the Orbit screen return the user to a NavigationBar-enabled screen.

### 10e. Scroll-Based Visibility

The floating search trigger respects scroll direction:

- **Scrolling down** past 100px: Trigger hides (`opacity: 0`)
- **Scrolling up** or **at top** (< 50px): Trigger shows (`opacity: 1`)
- Uses the shared `useScrollNavVisibility` hook

---

## Appendix: Token Reference

### Colors

| Token | Value | Usage |
|---|---|---|
| `--theme-bg` | Theme-driven (default: `linear-gradient(180deg, #0f0f18 0%, #0a0a0f 100%)`) | Screen background |
| `--glass-bg` | `rgba(255,255,255,0.08)` | Friend row background |
| `--glass-border` | `rgba(255,255,255,0.12)` | Friend row border |
| `--text-primary` | `rgba(255,255,255,0.95)` | Friend name, list header |
| `--text-secondary` | `rgba(255,255,255,0.6)` | Activity text, subtitle |
| `--text-muted` | `rgba(255,255,255,0.4)` | Username, time, section title |
| `#1DB954` | Green | QR buttons, online dot, go key, Inner Circle badge |
| `rgba(29,185,84,0.15)` | Green at 15% | QR button backgrounds |
| `rgba(29,185,84,0.3)` | Green at 30% | QR button borders |
| `rgba(129,230,217,0.12)` | Teal | Ring 1 dashed border |
| `rgba(167,139,250,0.10)` | Purple | Ring 2 dashed border |

### Typography

| Element | Size | Weight | Color |
|---|---|---|---|
| Section title "YOUR INNER CIRCLE" | 14px | 600 | `--text-muted`, uppercase, `letter-spacing: 1px` |
| Subtitle "Close Friends" | 14px | 400 | `--text-secondary` |
| List header "Friends" | 16px | 600 | `--text-primary` |
| QR button label | 13px | 600 | `#1DB954` |
| Friend name | 15px | 600 | `--text-primary` |
| Friend username | 13px | 400 | `--text-muted` |
| Friend activity | 12px | 400 | `--text-secondary` |
| Friend time | 12px | 400 | `--text-muted` |
| Inner Circle badge | 10px | 600 | `rgba(29,185,84,0.8)` |
| Overflow badge "+N" | 10px | 600 | `rgba(255,255,255,0.5)` |
| Search input | 15px | 400 | `#fff` |
| Search placeholder | 15px | 400 | `rgba(255,255,255,0.3)` |
| Keyboard key | 15px | 400 | `#fff` |
| No results text | 15px | 400 | `rgba(255,255,255,0.3)` |
| QR card title | 14px | 600 | `--text-primary` |
| QR card subtitle | 11px | 400 | `--text-muted` |

### Spacing

| Context | Value |
|---|---|
| Feed container padding | `8px 16px 24px` |
| Feed container bottom (default) | `100px` |
| Feed container bottom (search active) | `320px` |
| Friend row padding | `14px 16px` |
| Friend row gap | `14px` (between avatar, info, meta) |
| Friend list gap | `8px` (between rows) |
| List header margin bottom | `8px` |
| QR card padding | `18px 12px` |
| QR card gap | `10px` |
| QR cards row gap | `10px` |
| Orbital section padding | `20px 0` |
| Orbital container size | `320x320px` |
| Ring 1 radius | `62px` |
| Ring 2 radius | `108px` |
| Search bar padding | `10px 14px` |
| Search input padding | `10px 14px` |
| Keyboard padding | `6px 4px 14px` |
| Keyboard row gap | `6px` |
| Keyboard key gap | `5px` |

### Avatar Sizes

| Context | Size |
|---|---|
| User avatar (header) | 44px |
| User avatar (orbital center) | 48px |
| Ring 1 friend avatars | 38px |
| Ring 2 friend avatars | 30px |
| Overflow badge | 28px |
| Friend list avatars | 48px |
| Online dot (orbital ring 1) | 10px |
| Online dot (orbital ring 2) | 7px |
| Online dot (friend list) | 12px |

### Animations

| Animation | Duration | Easing | Delay / Stagger |
|---|---|---|---|
| Orbit avatar entrance (`orbitFadeIn`) | 500ms | ease | `globalIndex * 40ms` |
| Overflow badge entrance | 500ms | ease | `1000ms` |
| Friend row entrance (`cardEnter`) | 400ms | ease | `index * 20ms` |
| Collapsible shell (grid collapse) | 580ms | `cubic-bezier(0.22, 0.61, 0.36, 1)` | 0 |
| Collapsible content (fade/transform) | 420–500ms | ease / cubic-bezier | 0 |
| Bottom dock slide | 560ms | `cubic-bezier(0.22, 0.61, 0.36, 1)` | 0 |
| Feed padding transition | 560ms | `cubic-bezier(0.22, 0.61, 0.36, 1)` | 0 |
| Floating trigger show/hide | 340–460ms | ease / cubic-bezier | 0 |

### Z-Index

| Element | Z-Index |
|---|---|
| Close button (sticky) | 200 |
| Bottom search dock | 200 |
| Floating search trigger | 101 |
| Orbital center | auto (within orbital flow) |
| Orbital friends | auto (within orbital flow) |

---

## Design Rationale

| Decision | Why |
|---|---|
| 2-orbit maximum | Simplicity. More rings would create visual noise and dilute the meaning of "inner circle." Two tiers (5 + 8) create a clear hierarchy: your closest 5, and your next closest 8. |
| Sorted by message count | The orbit should reflect reality, not wishful thinking. If you message Sarah every day and haven't talked to Jake in months, Sarah should be closer to center. This creates an honest, dynamic map. |
| User at center | You are the gravitational center of your own social universe. This reinforces the feeling of being surrounded by people who care about you. |
| No NavigationBar on Orbit | The Orbit is a focused, immersive view of your social graph. The floating search trigger replaces the nav bar's position and provides the primary interactive element. Close/X buttons handle escape. |
| Search collapses the orbital | When you're searching, you need list space, not a visualization. The smooth collapse animation makes the transition feel intentional rather than jarring. The orbital returns when you close search. |
| Friends list below orbital | The orbital shows the top 13; the list shows everyone. Scrolling down naturally transitions from "visual overview" to "detailed directory." |
| QR integration via existing screens | The QR code screen already exists and works. The Orbit screen provides convenient access points but does not duplicate QR functionality. |
| Staggered entry animations | Each avatar popping in creates a sense of the circle "assembling" around you. The inner ring loads first (closer friends), then the outer ring, then the overflow badge last. |
| Online dots at different sizes | Ring 2 is farther away and avatars are smaller, so the online dot scales down proportionally to avoid looking oversized. |
| Inner Circle badge in search | When filtering a long list, it's helpful to know which friends hold privileged orbital positions. The badge is search-only to avoid clutter in the normal view. |
| Close button returns to Feed | The Feed is the "home" screen. The Orbit is a side panel you visit to manage your circle, then return to your inbox. |
