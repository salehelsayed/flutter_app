# Settings — Profile, Identity & Recovery

**Screen name:** Settings
**Entry point:** Tapping the header avatar on any screen that shows the user's avatar (Feed Live, 1st Contact D, etc.)
**Exit:** Back button returns to the previous screen
**Purpose:** A single place where the user manages their profile picture, sees their peer ID, and accesses their recovery phrase (mnemonic seed)

---

## Overview

Settings is a vertically scrollable screen with three content sections stacked inside glass cards. The screen follows the app's dark glassmorphic aesthetic — near-black backgrounds, frosted glass surfaces, subtle borders, and high-contrast white text. There are no tabs, no nested navigation, no modals. Everything is visible on one scroll.

The screen is security-sensitive. The recovery phrase is blurred by default and requires an explicit tap to reveal. Peer ID and mnemonic both support one-tap copy with visual confirmation.

---

## Screen Layout

```
+------------------------------------------+
| [<]         Settings              (spacer)|  <- sticky frosted header
+------------------------------------------+
|                                          |
|          [  Avatar 100px  ]              |  <- RingBrandedAvatar or uploaded photo
|          [camera btn overlay]            |  <- 32px teal circle, bottom-right
|          mknoon/@Username                |
|                                          |
+------------------------------------------+
|  PEER ID                                 |  <- uppercase section label
|  +--------------------------------------+|
|  | 12D3KooWQTqt...pXKpuGH    [copy btn]||  <- monospace, word-break, copy icon
|  | Your unique identifier on the network||  <- helper text below
|  +--------------------------------------+|
+------------------------------------------+
|  RECOVERY PHRASE                         |  <- uppercase section label
|  +--------------------------------------+|
|  | Never share this phrase...           ||  <- red warning text
|  |  +----------------------------------+||
|  |  |  [blurred grid + "Tap to reveal"]|||  <- overlay on blurred 3x4 grid
|  |  |  1 abandon  2 ability  3 able    |||
|  |  |  4 about    5 above   6 absent   |||
|  |  |  7 absorb   8 abstract 9 absurd  |||
|  |  | 10 abuse   11 access  12 accident|||
|  |  +----------------------------------+||
|  | [Copy to clipboard]  [Hide]          ||  <- shown only after reveal
|  +--------------------------------------+|
+------------------------------------------+
|                                          |
|         (120px bottom spacer)            |  <- clearance for floating nav bar
+------------------------------------------+
```

---

## Navigation — Entry & Exit

### Opening Settings

The header avatar on screens like Feed Live and 1st Contact D acts as the entry point. Tapping it navigates to `settings`.

| Element | Behavior |
|---|---|
| **Trigger** | `onClick` on the header avatar container |
| **Action** | `onSwitchView('settings')` — stores the current screen as `previousView` |
| **Cursor** | `pointer` when `onAvatarClick` is provided |

### Leaving Settings

| Element | Behavior |
|---|---|
| **Back button** | Top-left of the sticky header. Calls `onBack()` which navigates to `previousView` (falls back to `feedLive` if no previous screen) |
| **Nav bar** | The standard floating `NavigationBar` is present at the bottom for direct navigation to other sections |

---

## Anatomy — Top to Bottom

### 1. Screen Container

The full-screen wrapper. Uses the same `screen-frame` + `app-container` pattern as every other screen.

| Property | Value |
|---|---|
| Layout | Relative-positioned frame wrapping a scrollable `app-container` |
| Height | `100%` of the screen frame |
| Background | `#0a0a0f` (near-black), ambient radial gradient floats behind content |
| Scroll | `overflow-y: auto` on the inner container |
| Theme | Receives `theme` prop and sets CSS custom properties (`--theme-accent1`, `--theme-accent2`, `--theme-glass-bg`, `--theme-glass-border`, etc.) |

---

### 2. Sticky Header

A frosted glass bar pinned to the top of the scroll container. Three-column flex layout: back button, centered title, invisible spacer for balance.

```
[<]         Settings              (40px spacer)
```

| Element | Spec |
|---|---|
| **Container** | `position: sticky; top: 0; z-index: 10`, `padding: 16px 20px`, `background: rgba(10, 10, 15, 0.8)`, `backdrop-filter: blur(24px)`, `border-bottom: 1px solid rgba(255,255,255,0.12)` |
| **Layout** | `display: flex; align-items: center; justify-content: space-between` |
| **Back button** | `40x40px` circle, `border-radius: 50%`, `background: var(--glass-bg)`, `border: 1px solid var(--glass-border)`, `color: var(--text-primary)`. Contains a left-pointing chevron SVG (`20x20`, stroke width `2.5`). Hover: `background: rgba(255,255,255,0.08)`, transition `0.2s` |
| **Title** | `"Settings"`, `font-size: 18px`, `font-weight: 600`, `color: var(--text-primary)`, `letter-spacing: -0.01em` |
| **Right spacer** | Empty `div` with `width: 40px` to balance the back button |

---

### 3. Profile Section

A centered column displaying the user's avatar with an upload overlay, and their username beneath.

| Element | Spec |
|---|---|
| **Container** | `display: flex; flex-direction: column; align-items: center`, `padding: 32px 20px 24px`, `gap: 16px` |
| **Avatar wrapper** | `position: relative`, `width: 100px; height: 100px` |
| **Avatar (default)** | `RingBrandedAvatar` component at `size={100}`, rendered from the user's `peerId`. This is the generative ring-based avatar used throughout the app |
| **Avatar (uploaded)** | When the user uploads a photo, it replaces the generative avatar. `100x100px`, `border-radius: 50%`, `object-fit: cover`, `border: 2px solid var(--glass-border)` |
| **Camera button** | `position: absolute; bottom: 0; right: 0`, `32x32px` circle, `background: #14b8a6` (teal), `color: white`, `border: 2px solid #0a0a0f` (matches screen bg so it looks "cut out"). Contains a camera SVG icon (`16x16`). Hover: `transform: scale(1.1)`, `background: #0d9488`. This is a `<label>` wrapping a hidden `<input type="file" accept="image/*">` |
| **Username** | Two inline spans: `"mknoon/"` in `font-size: 15px; font-weight: 500; color: var(--text-secondary)`, then `"@Username"` in `font-size: 15px; font-weight: 600; color: var(--text-primary)`. Centered via `text-align: center` |

#### Profile Image Upload Flow

1. User taps the teal camera button
2. Native file picker opens (filtered to `image/*`)
3. Selected file is read via `FileReader.readAsDataURL()`
4. The data URL is stored in component state (`profileImage`)
5. The avatar switches from `RingBrandedAvatar` to the uploaded `<img>`
6. No crop, no resize — the image is displayed as-is with `object-fit: cover` and circular clip

---

### 4. Peer ID Section

Displays the user's libp2p peer ID in a glass card with a copy button.

#### 4a. Section Label

| Property | Value |
|---|---|
| Text | `"PEER ID"` |
| Font | `11px`, weight `700`, `text-transform: uppercase`, `letter-spacing: 0.08em` |
| Color | `var(--text-muted)` — `rgba(255,255,255,0.4)` |
| Spacing | `margin-bottom: 8px`, `padding-left: 4px` |

#### 4b. Card Container

| Property | Value |
|---|---|
| Background | `var(--glass-bg)` — `rgba(255,255,255,0.08)` |
| Border | `1px solid var(--glass-border)` — `rgba(255,255,255,0.12)` |
| Border radius | `16px` |
| Padding | `16px` |
| Backdrop filter | `blur(24px)` |

#### 4c. Peer ID Row

A flex row with the peer ID text on the left and a copy button on the right.

| Element | Spec |
|---|---|
| **Layout** | `display: flex; align-items: flex-start; gap: 12px` |
| **Peer ID text** | `<code>` element. `font-family: 'SF Mono', 'Fira Code', monospace`, `font-size: 12px`, `line-height: 1.5`, `color: var(--text-primary)`, `word-break: break-all`. Sits inside a subtle inner container: `background: rgba(255,255,255,0.03)`, `padding: 10px 12px`, `border-radius: 10px`, `border: 1px solid rgba(255,255,255,0.05)` |
| **Copy button** | `36x36px`, `border-radius: 10px`, `border: 1px solid var(--glass-border)`, `background: var(--glass-bg)`, `color: var(--text-secondary)`. Contains a copy SVG icon (`16x16`). Hover: `background: rgba(255,255,255,0.08)`, `color: var(--text-primary)`, transition `0.2s` |

#### 4d. Helper Text

| Property | Value |
|---|---|
| Text | `"Your unique identifier on the network"` |
| Font | `12px`, weight `400` |
| Color | `var(--text-muted)` |
| Spacing | `margin-top: 10px` |

#### 4e. Copy Interaction

1. User taps the copy button
2. `navigator.clipboard.writeText(peerId)` is called
3. The copy icon instantly swaps to a checkmark icon (same size, teal-ish color from inherited text color)
4. After **2 seconds**, the icon reverts to the copy icon
5. No toast, no snackbar — the icon swap is the entire feedback

---

### 5. Recovery Phrase Section

The most sensitive section. Displays the user's 12-word BIP-39 mnemonic seed phrase in a blurred grid that the user must explicitly reveal.

#### 5a. Section Label

Same style as the Peer ID section label, text: `"RECOVERY PHRASE"`.

#### 5b. Card Container

Same glass card style as the Peer ID card (`16px` radius, glass bg/border/blur).

#### 5c. Warning Text

| Property | Value |
|---|---|
| Text | `"Never share this phrase with anyone. It grants full access to your account."` |
| Font | `13px`, weight `500`, `line-height: 1.4` |
| Color | `#f87171` (red-400) |
| Spacing | `margin-bottom: 14px` |

#### 5d. Mnemonic Grid (Hidden State — Default)

The 12 words are always rendered in a 3-column CSS grid, but in the default state they are blurred and covered by a tap-to-reveal overlay.

| Property | Value |
|---|---|
| **Grid container** | `position: relative`, `border-radius: 12px`, `overflow: hidden` |
| **Grid layout** | `display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px` |
| **Blur** | `filter: blur(8px)` on the grid, `user-select: none`, `pointer-events: none` |
| **Transition** | `filter 0.3s ease` — smooth de-blur when revealed |

Each word cell:

| Property | Value |
|---|---|
| Layout | `display: flex; align-items: center; gap: 8px` |
| Padding | `8px 10px` |
| Background | `rgba(255,255,255,0.04)` |
| Border | `1px solid rgba(255,255,255,0.06)` |
| Border radius | `10px` |
| **Index number** | `font-size: 11px`, `color: var(--text-muted)`, `font-weight: 600`, `min-width: 16px` |
| **Word text** | `font-size: 13px`, `color: var(--text-primary)`, `font-weight: 500` |

#### 5e. Reveal Overlay

Sits absolutely on top of the blurred grid. A button covering the entire grid area.

| Property | Value |
|---|---|
| Position | `position: absolute; inset: 0` (covers entire grid) |
| Layout | `display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px` |
| Background | `rgba(10, 10, 15, 0.4)` — semi-transparent dark wash |
| Border | None |
| Border radius | `12px` |
| Color | `var(--text-secondary)` |
| Font | `14px`, weight `500` |
| Icon | Eye SVG, `24x24px` |
| Text | `"Tap to reveal"` |
| Hover | `background: rgba(10,10,15,0.3)`, `color: var(--text-primary)` |
| Z-index | `2` (above the blurred grid) |
| Cursor | `pointer` |
| Action | On tap, sets `showMnemonic = true` — removes the overlay and removes `filter: blur(8px)` from the grid |

#### 5f. Mnemonic Grid (Revealed State)

When `showMnemonic` is true:
- The blur filter is removed (transition animates from `blur(8px)` to `blur(0)` over `0.3s`)
- The overlay is removed from the DOM
- `pointer-events` and `user-select` are restored
- Two action buttons appear below the grid

#### 5g. Action Buttons (Visible Only When Revealed)

A horizontal flex row below the grid with two buttons.

| Element | Spec |
|---|---|
| **Container** | `display: flex; gap: 8px; margin-top: 14px` |
| **Copy button** | `flex: 1`. Copies all 12 words joined by spaces to clipboard. Icon swaps from copy to checkmark for 2 seconds (same pattern as Peer ID copy). Label reads `"Copy to clipboard"` then `"Copied!"` while in confirmation state |
| **Hide button** | `flex: 0 0 auto` (shrink-to-fit). Re-blurs the grid and restores the overlay. Icon: eye-off SVG (`18x18`). Label: `"Hide"` |

Both buttons share the same base style:

| Property | Value |
|---|---|
| Padding | `10px 14px` |
| Border radius | `10px` |
| Border | `1px solid var(--glass-border)` |
| Background | `var(--glass-bg)` |
| Color | `var(--text-secondary)` |
| Font | `13px`, weight `500` |
| Layout | `display: flex; align-items: center; justify-content: center; gap: 6px` |
| Hover | `background: rgba(255,255,255,0.08)`, `color: var(--text-primary)` |
| Transition | `all 0.2s` |

---

### 6. Bottom Spacer

A `120px` tall empty div at the bottom of the scroll container, providing clearance so the last card isn't hidden behind the floating navigation bar.

---

### 7. Navigation Bar

The standard floating `NavigationBar` component, positioned absolutely at the bottom of the screen frame (outside the scroll container). Same component used across Feed Live, 1st Contact D, and other screens. Hides on scroll-down, reappears on scroll-up or at the top.

---

## State Summary

| State variable | Type | Default | Purpose |
|---|---|---|---|
| `profileImage` | `string \| null` | `null` | Data URL of uploaded profile photo |
| `showMnemonic` | `boolean` | `false` | Whether the recovery phrase grid is revealed |
| `copied` | `boolean` | `false` | Peer ID copy confirmation (resets after 2s) |
| `copiedMnemonic` | `boolean` | `false` | Mnemonic copy confirmation (resets after 2s) |

---

## Props

| Prop | Type | Purpose |
|---|---|---|
| `onSwitchView` | `(viewId: string) => void` | Navigate to any screen (used by NavigationBar) |
| `onBack` | `() => void` | Navigate back to the previous screen |
| `theme` | `object` | Color theme with `bg`, `accent1`, `accent2`, `text`, `textMuted`, `glassBg`, `glassBorder` |

---

## Data Sources

| Data | Source | Notes |
|---|---|---|
| **Peer ID** | `currentUser.qrCode` | The libp2p peer identifier string. Example: `12D3KooWQTqttTb9ujg1pVRmMfNsntP5r1HuoJwHw6XqshXKpuGH` |
| **Username** | `currentUser.username` | Displayed as `mknoon/@{username}` |
| **Mnemonic** | 12-word BIP-39 seed phrase | In the prototype this is mock data. In production, read from the local keystore |
| **Profile image** | Local state (uploaded file) | In production, persist to local storage or user profile |

---

## Design Tokens Reference

These are the CSS custom properties the screen consumes. They are set by the theme system and cascade from the screen frame wrapper.

| Token | Default value | Usage |
|---|---|---|
| `--glass-bg` | `rgba(255,255,255,0.08)` | Card backgrounds, button backgrounds |
| `--glass-border` | `rgba(255,255,255,0.12)` | Card borders, button borders |
| `--glass-blur` | `24px` | Backdrop blur radius for frosted glass |
| `--text-primary` | `rgba(255,255,255,0.95)` | Headings, peer ID text, word text |
| `--text-secondary` | `rgba(255,255,255,0.6)` | Username prefix, copy button icons, overlay text |
| `--text-muted` | `rgba(255,255,255,0.4)` | Section labels, helper text, mnemonic indices |

---

## Interaction Flows

### Flow 1: Upload Profile Picture

```
User taps camera button
  -> Native file picker opens (image/* filter)
  -> User selects a photo
  -> FileReader reads file as data URL
  -> State updates: profileImage = dataURL
  -> Avatar switches from RingBrandedAvatar to <img> with circular clip
```

### Flow 2: Copy Peer ID

```
User taps copy button next to peer ID
  -> navigator.clipboard.writeText(peerId)
  -> Icon swaps: copy -> checkmark
  -> 2 second timer starts
  -> Timer fires: icon swaps back: checkmark -> copy
```

### Flow 3: Reveal Recovery Phrase

```
User taps "Tap to reveal" overlay
  -> showMnemonic = true
  -> Overlay removed from DOM
  -> Grid blur transitions from 8px to 0px over 0.3s
  -> pointer-events and user-select restored
  -> Copy and Hide buttons appear below grid
```

### Flow 4: Copy Recovery Phrase

```
User taps "Copy to clipboard" button
  -> 12 words joined by spaces, copied to clipboard
  -> Icon swaps: copy -> checkmark
  -> Label swaps: "Copy to clipboard" -> "Copied!"
  -> 2 second timer fires: reverts both to original state
```

### Flow 5: Hide Recovery Phrase

```
User taps "Hide" button
  -> showMnemonic = false
  -> Grid blur transitions from 0px to 8px over 0.3s
  -> pointer-events: none, user-select: none applied
  -> Copy and Hide buttons removed
  -> "Tap to reveal" overlay re-appears
```

---

## Accessibility Notes

- The back button and all interactive elements should have a minimum `44x44px` tap target
- The camera upload button is a `<label>` wrapping a hidden file input — this is natively accessible
- The mnemonic grid uses `user-select: none` when hidden to prevent accidental selection of blurred text
- The warning text uses red (`#f87171`) which has sufficient contrast against the dark card background
- Copy confirmation is visual (icon swap) — consider adding `aria-live="polite"` announcements for screen readers in production
