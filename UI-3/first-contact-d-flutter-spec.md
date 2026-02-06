# First Contact D Screen - Flutter Implementation Spec

Complete design specification for recreating the **1st Contact D** screen in Flutter.
Each section maps to a discrete Flutter widget.

---

## Table of Contents

1. [Global Design Tokens](#1-global-design-tokens)
2. [Screen Frame (Scaffold)](#2-screen-frame-scaffold)
3. [Ambient Background](#3-ambient-background)
4. [Header](#4-header)
5. [Connection Card](#5-connection-card)
   - 5a. Card Shell
   - 5b. Card Glow
   - 5c. Avatar Section
   - 5d. Content Wrapper (match-content layout)
   - 5e. Headline & Burst Animation
   - 5f. Friend Info
   - 5g. Action Button
6. [Navigation Bar](#6-navigation-bar)
   - 6a. Nav Wrapper (positioning & visibility)
   - 6b. Nav Container (glass bar)
   - 6c. Nav Button Base
   - 6d. Active Button (glass pill)
   - 6e. Inactive Button
   - 6f. Nav Icons (SVG assets)
7. [RingBrandedAvatar (Generative Avatar)](#7-ringbrandedavatar-generative-avatar)
8. [Scroll-Based Nav Visibility Behavior](#8-scroll-based-nav-visibility-behavior)
9. [Theme / Color System](#9-theme--color-system)
10. [Animations Reference](#10-animations-reference)

---

## 1. Global Design Tokens

These are the root-level design tokens used throughout the screen.

### Colors

| Token | Value | Usage |
|---|---|---|
| `glass-bg` | `rgba(255, 255, 255, 0.08)` | Card backgrounds |
| `glass-border` | `rgba(255, 255, 255, 0.12)` | Card border |
| `glass-blur` | `24px` | Backdrop blur radius for cards |
| `text-primary` | `rgba(255, 255, 255, 0.95)` | Primary text (headings, names) |
| `text-secondary` | `rgba(255, 255, 255, 0.6)` | Secondary text |
| `text-muted` | `rgba(255, 255, 255, 0.4)` | Muted labels, prefixes |
| `theme-bg` | `#0a0a0f` | Screen background |
| `theme-accent1` | `#1DB954` | Primary accent (green) |
| `theme-accent2` | `#1ed760` | Secondary accent (lighter green) |
| `theme-text` | `#ffffff` | Base text color |
| `theme-text-muted` | `rgba(255, 255, 255, 0.6)` | Muted theme text |
| `theme-glass-bg` | `rgba(30, 30, 35, 0.6)` | Glass panel background |
| `theme-glass-border` | `rgba(255, 255, 255, 0.05)` | Glass panel border |

### Typography

| Element | Size | Weight | Color | Extra |
|---|---|---|---|---|
| Username prefix (`mknoon/`) | 18px | 500 | `text-muted` | - |
| Username (`@Username`) | 18px | 600 | `text-primary` | - |
| "Connected!" heading | 26px | 800 | `theme-accent1` (#1DB954) | `text-shadow: 0 0 30px rgba(29, 185, 84, 0.5)` |
| Friend name (h2) | 24px | 700 | white | `text-shadow: 0 2px 10px rgba(0, 0, 0, 0.5)` |
| Action button text | 15px | 600 | `theme-accent1` | - |
| Nav button labels | 11px | 500 | varies by active state | - |

### Font Family

```
-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif
```

Flutter equivalent: use the default system font, or specify `fontFamily: '.SF Pro Display'` on iOS / `'Roboto'` on Android.

---

## 2. Screen Frame (Scaffold)

**Flutter widget:** `Scaffold` or raw `Container` inside a `Stack`

The screen frame is the outermost container. It provides relative positioning so the floating navigation bar can anchor to it.

### Screen Widget Inputs

| Param | Type | Default | Description |
|---|---|---|---|
| `onSwitchView` | `Function(String)` | required | Navigation callback, passed down to `NavigationBar`. Called with `'feed'`, `'memories'`, or `'circle'`. |
| `theme` | `MknoonTheme` | Default theme (see Section 9) | Color/style theme applied to the entire screen. Optional — falls back to the default dark theme if omitted. |

### Data Contracts

These data objects are consumed by child components. Define them as model classes in Flutter.

#### `currentUser` (used by Header)

| Field | Type | Value in source | Consumed by |
|---|---|---|---|
| `name` | String | `'You'` | — |
| `username` | String | `'Username'` | Header username text (`@Username`) |
| `avatar` | String? | `null` | Header avatar (null = use generated avatar) |
| `qrCode` | String | `'12D3KooWQTqttTb9ujg1pVRmMfNsntP5r1HuoJwHw6XqshXKpuGH'` | Seed for `RingBrandedAvatar` in Header |
| `qrImage` | String | `'/qr-code.png'` | — (not used on this screen) |

#### `newFriend` (used by ConnectionCard)

| Field | Type | Value in source | Consumed by |
|---|---|---|---|
| `name` | String | `'Sarah'` | Friend name text (Section 5f) |
| `username` | String | `'sarah_m'` | — (not displayed on this screen variant) |
| `peerId` | String | `'12D3KooWsarahm2024bestfriend...'` | Seed for `RingBrandedAvatar` fallback (Section 5c) |
| `avatar` | String? | Unsplash URL | Avatar image source; if `null`, renders `RingBrandedAvatar` instead (Section 5c) |
| `color` | String (hex) | `'#1DB954'` | Sets `--friend-color` on the card; tints action button and glow |

### Layout

| Property | Value |
|---|---|
| Position | Relative (parent for absolute-positioned nav) |
| Width | `100%` (match parent) |
| Height | `100%` (match parent) |
| Overflow | Hidden (clip children) |
| Background | `#0a0a0f` (via theme) |

### Structure (widget tree)

```
ScreenFrame (Stack)
  ├── ScrollableContent (SingleChildScrollView / CustomScrollView)
  │     ├── AmbientBackground
  │     ├── Header
  │     └── MessagesFeed (Column with padding)
  │           └── ConnectionCard
  └── NavigationBar (Positioned at bottom)
```

The scrollable content and nav bar are siblings inside a `Stack`. The nav bar floats on top.

### MessagesFeed Container (`messages-feed`)

The wrapper around all card content. In Flutter: a `Padding` + `Column`.

| Property | Value | Flutter equivalent |
|---|---|---|
| Padding | `8px top, 16px horizontal, 24px bottom` | `EdgeInsets.fromLTRB(16, 8, 16, 24)` |
| Layout | Flex column | `Column(crossAxisAlignment: CrossAxisAlignment.stretch)` |
| Gap | 20px between children | `SizedBox(height: 20)` between cards, or `MainAxisAlignment` with spacers |
| Position | Relative | Default |
| Z-index | 1 (above ambient background) | Place after `AmbientBackground` in the `Stack` or column order |

---

## 3. Ambient Background

**Flutter widget:** `Positioned.fill` + `IgnorePointer` + `CustomPaint` or stacked `Container`s with `RadialGradient`

A decorative, non-interactive animated background layer behind all content.

### Layout

| Property | Value |
|---|---|
| Position | Absolute, fills parent |
| Width / Height | 100% of viewport |
| Pointer events | None (pass-through) |
| Z-index | 0 (behind everything) |

### Visual

The `::before` pseudo-element (in Flutter: a child container) is **200% width and 200% height**, offset by `-50%` top and left, creating an oversized canvas that animates.

Three overlapping radial gradients:

| Gradient | Center | Color | Spread |
|---|---|---|---|
| 1 | 20%, 20% | `rgba(120, 80, 200, 0.15)` (purple) | 0% to 50% then transparent |
| 2 | 80%, 80% | `rgba(255, 100, 150, 0.1)` (pink) | 0% to 50% then transparent |
| 3 | 50%, 50% | `rgba(80, 200, 200, 0.08)` (teal) | 0% to 50% then transparent |

### Animation: `ambientFloat`

- Duration: **20 seconds**, ease-in-out, infinite loop
- Keyframes:
  - 0% / 100%: `translate(0, 0) rotate(0deg)`
  - 33%: `translate(-5%, 5%) rotate(5deg)`
  - 66%: `translate(5%, -5%) rotate(-5deg)`

In Flutter: use an `AnimationController` with `Tween` to animate `Transform` translations and rotations on the gradient container.

---

## 4. Header

**Flutter widget:** Custom `SliverAppBar` or a sticky `Container`

A sticky top bar with the username on the left and the user's generated avatar on the right.

### Layout

| Property | Value |
|---|---|
| Position | Sticky to top |
| Z-index | 100 |
| Padding | `20px top, 24px horizontal, 16px bottom` |
| Background | `linear-gradient(180deg, rgba(10, 10, 15, 0.98) 0%, rgba(10, 10, 15, 0) 100%)` |
| Backdrop filter | `blur(20px)` |
| Flex direction | Row, space-between, vertically centered |
| Flex shrink | 0 (don't compress) |

### Left side: Username Display

A horizontal `Row` with no gap:

1. **Prefix text** `"mknoon/"` - 18px, weight 500, color `text-muted` (`rgba(255,255,255,0.4)`)
2. **Username** `"@Username"` - 18px, weight 600, color `text-primary` (`rgba(255,255,255,0.95)`)

### Right side: Avatar

The `RingBrandedAvatar` widget (see Section 7) at **44px** size.

Wrapped in a container with:
- `borderRadius: 50%` (circular clip)
- `overflow: hidden`
- `border: 2px solid rgba(255, 255, 255, 0.2)`

---

## 5. Connection Card

**Flutter widget:** Custom `StatelessWidget` wrapping a `Container` inside `Stack`

This is the main content card showing the "Connected!" state with a friend's avatar.

### 5a. Card Shell

The outer card container.

| Property | Value |
|---|---|
| Border radius | 28px |
| Overflow | Hidden (clip children) |
| Background | `rgba(255, 255, 255, 0.08)` (glass-bg) |
| Border | `1px solid rgba(255, 255, 255, 0.12)` (glass-border) |
| Backdrop filter | `blur(24px)` (glass-blur) |
| Min height | 360px |
| Position | Relative (for absolutely-positioned avatar) |
| Entry animation | `cardEnter` - fade + slide up (see Section 10) |

The card uses CSS custom properties:
- `--card-gradient`: set to `transparent` for this screen
- `--friend-color`: `#1DB954`

### 5b. Card Glow

A decorative gradient overlay at the top of the card.

| Property | Value |
|---|---|
| Position | Absolute, top: 0, left: 0, right: 0 |
| Height | 200px |
| Background | `var(--card-gradient)` (transparent in this screen) |
| Opacity | 0.15 (0.15 on hover for this card variant) |
| Filter | `blur(40px)` |
| Pointer events | None |

Since `--card-gradient` is `transparent` on this screen, the glow is effectively invisible. Include the widget for reusability across other screens where the gradient is visible.

### 5c. Avatar Section

The avatar is **absolutely centered** in the card.

#### Avatar Container (`match-avatar-container-compact`)

| Property | Value |
|---|---|
| Position | Absolute |
| Top | 50% |
| Left | 50% |
| Transform | `translate(-50%, -50%)` (centered) |
| Z-index | 1 |
| Display | Flex, centered both axes |

In Flutter: `Positioned` with `top: 0, bottom: 0, left: 0, right: 0` + `Center`.

#### Avatar Glow (`match-avatar-glow-compact`)

A blurred decorative light behind the avatar.

| Property | Value |
|---|---|
| Position | Absolute (behind the image) |
| Size | 150px x 150px |
| Background | `var(--card-gradient)` |
| Opacity | 0.3 |
| Filter | `blur(40px)` |
| Pointer events | None |

#### Avatar Wrapper (`match-avatar-wrapper-compact`)

The circular frame around the avatar image.

| Property | Value |
|---|---|
| Border radius | 50% (circle) |
| Overflow | Hidden |
| Box shadow (3 layers) | `0 20px 60px rgba(0,0,0,0.5)`, `0 0 0 3px rgba(255,255,255,0.1)`, `0 0 60px rgba(29,185,84,0.3)` |
| Entry animation | `avatarEnter` - scale from 0.5 to 1 (see Section 10) |

#### Avatar Image

| Property | Value |
|---|---|
| Width | 120px |
| Height | 120px |
| Object fit | Cover |
| Shape | Circular (clipped by parent) |

If no photo URL is available, render a `RingBrandedAvatar` at 100px instead.

### 5d. Content Wrapper (`match-content`)

**Flutter widget:** A `Column` inside a `Container` — this is the primary layout wrapper that vertically positions the headline at the top, the friend name below the avatar, and the action button at the bottom. It sits as a sibling to the absolutely-centered avatar, layered above it via z-index.

#### Base styles (`.match-content`)

| Property | Value | Flutter equivalent |
|---|---|---|
| Position | Relative | Default (within Stack child) |
| Z-index | 1 (base), **2** in compact variant | Ordering in Stack children |
| Height | 100% | `double.infinity` or parent constraint |
| Min height | 480px (base), **360px** in compact variant | `ConstrainedBox(constraints: BoxConstraints(minHeight: 360))` |
| Display | Flex column | `Column` |
| Justify content | `flex-end` | `MainAxisAlignment.end` |
| Padding | 32px 24px (base), **24px 20px** in compact variant | `EdgeInsets.symmetric(horizontal: 20, vertical: 24)` |

#### Overrides applied in `match-card-avatar-compact` context (this screen)

The compact variant overrides the base. These are the **effective values** for the 1st Contact D screen:

| Property | Effective Value |
|---|---|
| Z-index | **2** (above the avatar layer at z-index 1) |
| Min height | **360px** |
| Padding | **24px vertical, 20px horizontal** |

#### Layout behavior explained

The `match-content` Column uses `justify-content: flex-end`, which pushes all children to the bottom by default. However, the **headline** child has `margin-bottom: auto` (in the base `.match-headline` class), which absorbs all available vertical space and pushes the headline to the top. In the compact variant, this is replaced by explicit `padding-top: 15px` and `padding-bottom: 80px` on the headline.

This creates the vertical layout:

```
┌─────────────────────────┐  ← match-content top (padding-top: 24px)
│  Headline ("Connected!")│  ← padding-top: 15px, padding-bottom: 80px
│  + Burst Animation      │
│                         │
│     [Avatar floats       │  ← Avatar is NOT inside match-content;
│      here, centered      │    it's an absolute-positioned sibling
│      via absolute pos]   │    at z-index 1. The 80px padding-bottom
│                         │    on headline + 80px margin-top on friend
│  Friend Name ("Sarah") │  ← margin-top: 80px, margin-bottom: 4px
│                         │
│  [Send Message] button  │  ← margin-top: 8px
│                         │
└─────────────────────────┘  ← match-content bottom (padding-bottom: 24px)
```

The 80px `padding-bottom` on the headline and 80px `margin-top` on friend-info create a ~160px vertical gap in the middle — this is where the absolutely-centered avatar visually appears, even though it's a separate layer.

#### Key architectural note for Flutter

In Flutter, model this as a `Stack`:

```dart
Stack(
  children: [
    // Layer 1 (z-index 1): Centered avatar
    Positioned.fill(
      child: Center(child: AvatarSection()),
    ),
    // Layer 2 (z-index 2): Content column
    Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 360),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Headline pushes to top via Spacer or explicit padding
            HeadlineSection(),  // has bottom padding 80px
            Spacer(),           // or use margin-top on next child
            FriendInfo(),       // has top margin 80px
            ActionButton(),     // has top margin 8px
          ],
        ),
      ),
    ),
  ],
)
```

### 5e. Headline & Burst Animation

The "Connected!" text with animated expanding rings.

#### Headline Container (`match-headline` inside `match-card-avatar-compact`)

| Property | Value |
|---|---|
| Padding top | 15px |
| Padding bottom | 80px (space for centered avatar) |
| Text align | Center |
| Z-index | 2 (above avatar) |

#### "Connected!" Text

| Property | Value |
|---|---|
| Font size | 26px |
| Font weight | 800 (extra bold) |
| Color | `#1DB954` (theme accent) |
| Text shadow | `0 0 30px rgba(29, 185, 84, 0.5)` |
| Margin bottom | 6px |
| Animation | `fadeInUp` 0.5s ease, 0.4s delay |

#### Icon Burst (checkmark with expanding rings)

Container:

| Property | Value |
|---|---|
| Size | 40px x 40px |
| Margin | `0 auto 8px` (centered, 8px below) |
| Display | Flex, centered |

Checkmark SVG icon:

| Property | Value |
|---|---|
| Size | 28px x 28px |
| Color | `#1DB954` |
| Filter | `drop-shadow(0 0 20px #1DB954)` |
| Animation | `iconPop` - scale from 0 to 1, 0.5s, 0.3s delay |

SVG path data: `M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z`

#### Burst Rings (3 expanding circles)

Three absolutely-positioned rings that continuously expand outward.

| Property | Value |
|---|---|
| Size | 100% of parent (40px) |
| Border radius | 50% |
| Border | `2px solid #1DB954` |
| Fill | None |
| Animation | `burstExpand` 1.5s ease-out infinite |

Stagger:
- burst-1: delay `0s`
- burst-2: delay `0.3s`
- burst-3: delay `0.6s`

`burstExpand` keyframes:
- 0%: `scale(0.5)`, opacity `0.8`
- 100%: `scale(2)`, opacity `0`

### 5f. Friend Info

Below the avatar, showing the friend's name.

| Property | Value |
|---|---|
| Text align | Center |
| Margin bottom | 4px |
| Margin top | 80px (space for centered avatar above) |
| Z-index | 2 |
| Animation | `fadeInUp` 0.5s ease, 0.6s delay |

#### Friend Name (h2)

| Property | Value |
|---|---|
| Font size | 24px |
| Font weight | 700 |
| Color | white |
| Text shadow | `0 2px 10px rgba(0, 0, 0, 0.5)` |

### 5g. Action Button ("Send Message")

A pill-shaped, ghost-style button with accent tint.

#### Button Container (`match-actions`)

| Property | Value |
|---|---|
| Display | Flex |
| Justify content | Center |
| Margin top | 8px |
| Animation | `fadeInUp` 0.5s ease, 0.7s delay |

#### Button (`match-action-compact`)

| Property | Value |
|---|---|
| Display | Inline flex, row, centered |
| Gap | 6px (between icon and text) |
| Padding | `7px 16px` |
| Background | `rgba(29, 185, 84, 0.15)` |
| Border | `1px solid rgba(29, 185, 84, 0.3)` |
| Border radius | 100px (full pill) |
| Color | `#1DB954` |
| Font size | 15px |
| Font weight | 600 |
| Width | Fit content / intrinsic |
| Transition | All 0.2s ease |

Hover state:
- Background: `rgba(29, 185, 84, 0.25)`
- Border color: `rgba(29, 185, 84, 0.5)`
- Transform: `translateY(-1px)`
- Box shadow: `0 4px 12px rgba(29, 185, 84, 0.2)`

#### Button Icon (chat bubble)

| Property | Value |
|---|---|
| Size | 18px x 18px |
| Color | Inherited (`#1DB954`) |
| Fill | `currentColor` |

SVG path data: `M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z`

---

## 6. Navigation Bar

**Flutter widget:** Custom `StatelessWidget` using `Positioned` inside the screen's `Stack`

A floating glass navigation bar anchored to the bottom of the screen frame, with three tab buttons. Supports an `activeTab` prop to highlight the correct button.

### Props / Parameters

| Param | Type | Default | Description |
|---|---|---|---|
| `isNavVisible` | bool | required | Controls opacity fade (from scroll behavior, see Section 8) |
| `onSwitchView` | Function(String) | required | Callback invoked with a route string when a tab is tapped |
| `activeTab` | String | `'feed'` | Which tab shows the glass pill highlight |

**Default behavior:** The 1st Contact D screen mounts `NavigationBar` **without** passing `activeTab`, so it defaults to `'feed'`:

```dart
NavigationBar(isNavVisible: isNavVisible, onSwitchView: onSwitchView)
// activeTab defaults to 'feed' → Feed button gets the glass pill
```

### Tab Route Mapping

Each button, when tapped, calls `onSwitchView` with a specific string. This is the contract between the nav bar and the parent screen's router:

| Button | Label | `onSwitchView` argument | Active when `activeTab ==` |
|---|---|---|---|
| Feed | "Feed" | `'feed'` | `'feed'` |
| Remember | "Remember" | `'memories'` | `'memories'` |
| Orbit | "Orbit" | `'circle'` | `'circle'` |

The parent screen is responsible for receiving this string and navigating to the correct screen. The nav bar itself does not perform navigation — it only fires the callback.

### 6a. Nav Wrapper (positioning & visibility)

The outermost wrapper that positions the bar and controls its fade in/out.

| Property | Value |
|---|---|
| Position | Absolute |
| Bottom | 40px |
| Left | 50% |
| Transform | `translateX(-50%)` (horizontally centered) |
| Z-index | 100 |
| Opacity | `1` when visible, `0` when hidden |
| Transition | `opacity 0.3s ease` |
| Pointer events | `auto` when visible, `none` when hidden |

In Flutter: use `AnimatedOpacity` + `IgnorePointer(ignoring: !isVisible)` inside a `Positioned(bottom: 40)` with `Align(alignment: Alignment.center)`.

### 6b. Nav Container (glass bar)

The visible navigation bar background.

| Property | Value |
|---|---|
| Background | `rgba(30, 30, 35, 0.8)` |
| Backdrop filter | `blur(20px)` |
| Border | `1px solid rgba(255, 255, 255, 0.08)` |
| Border radius | 30px |
| Padding | `10px 12px` |
| Layout | Row (flex), gap 8px, centered |

In Flutter: `ClipRRect(borderRadius: 30)` + `BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20))` + `Container(decoration: ...)`.

### 6c. Nav Button Base (shared between active/inactive)

All three buttons share these base properties to ensure identical sizing and prevent layout shift when switching active states.

| Property | Value |
|---|---|
| Background | Transparent |
| Border | `1px solid transparent` |
| Box sizing | Border-box |
| Border radius | 18px |
| Layout | Column (flex), centered both axes |
| Gap | 4px (between icon and label) |
| Width | 60px (fixed) |
| Padding | `8px 6px` |
| Font size | 11px |
| Font weight | 500 |
| Flex shrink | 0 |
| Transition | `background 0.2s ease, border-color 0.2s ease, color 0.2s ease, opacity 0.2s ease, box-shadow 0.2s ease, transform 0.2s ease` |

### 6d. Active Button (glass pill)

Applied to whichever tab is currently active. This is the "glass pill" highlight effect.

| Property | Value |
|---|---|
| Color | `#ffffff` (white) |
| Opacity | 1 |
| Background | `linear-gradient(145deg, rgba(255,255,255,0.34) 0%, rgba(255,255,255,0.2) 58%, rgba(255,255,255,0.14) 100%)` |
| Border color | `rgba(255, 255, 255, 0.42)` |
| Backdrop filter | `blur(14px) saturate(1.25)` |
| Box shadow | 4 layers (see below) |
| Text shadow | `0 1px 2px rgba(0, 0, 0, 0.35)` |
| Transform | `translateY(-1px)` (subtle lift) |

**Box shadow layers (in order):**

1. `0 8px 22px rgba(0, 0, 0, 0.36)` - outer drop shadow
2. `0 0 0 1px rgba(255, 255, 255, 0.14)` - thin outline ring
3. `inset 0 1px 0 rgba(255, 255, 255, 0.45)` - top inner highlight
4. `inset 0 -10px 16px rgba(0, 0, 0, 0.14)` - bottom inner darkening

In Flutter: use `Container` with `BoxDecoration` containing `gradient`, `border`, `borderRadius`, and `boxShadow`. For backdrop filter, wrap in `ClipRRect` + `BackdropFilter`. The text shadow goes on the `Text` widget's `style.shadows`.

### 6e. Inactive Button

| Property | Value |
|---|---|
| Color | `rgba(255, 255, 255, 0.5)` |
| Opacity | 0.7 |
| Background | Transparent (from base) |
| Border | `1px solid transparent` (from base) |

### 6f. Nav Icons (SVG assets)

Each button has a custom SVG icon at **24x24px** rendered above the text label. These are brand-specific illustrated icons, not standard material icons.

**Recommendation for Flutter:** Save each SVG below as a standalone `.svg` file (e.g. `assets/icons/nav_feed.svg`, `assets/icons/nav_remember.svg`, `assets/icons/nav_orbit.svg`) and load them with the `flutter_svg` package. This avoids recreating complex path data in `CustomPainter`.

#### Feed Icon

- Rendered size: 24x24
- ViewBox: `0 0 800 800`
- Description: An illustrated fruit/seed composition with green striped bodies and red flesh accents.

```xml
<svg width="24" height="24" viewBox="0 0 800 800" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <pattern id="stripes" width="20" height="10" patternUnits="userSpaceOnUse">
      <rect width="20" height="10" fill="#228B22"/>
      <path d="M0,5 Q5,0 10,5 T20,5" stroke="#3CB371" stroke-width="2" fill="none"/>
    </pattern>
    <radialGradient id="fleshGrad" cx="50%" cy="50%" r="50%" fx="50%" fy="50%">
      <stop offset="0%" stop-color="#FF4500"/>
      <stop offset="100%" stop-color="#DC143C"/>
    </radialGradient>
  </defs>
  <rect width="800" height="800" fill="none"/>
  <!-- Main body: large striped ellipse with flesh patch and seeds -->
  <g transform="translate(400, 400) scale(1.5)">
    <ellipse rx="100" ry="120" fill="url(#stripes)" stroke="#228B22" stroke-width="2"/>
    <path d="M-20,-100 C-40,-80 -30,-60 -10,-40 C10,-20 30,-30 50,-50 C40,-70 20,-90 -20,-100 Z" fill="url(#fleshGrad)"/>
    <g fill="black">
      <circle cx="-10" cy="-70" r="2"/>
      <circle cx="10" cy="-60" r="2"/>
      <circle cx="30" cy="-80" r="2"/>
      <circle cx="0" cy="-90" r="2"/>
    </g>
  </g>
  <!-- Top-right wedge -->
  <g transform="translate(650, 150) rotate(-30) scale(1.2)">
    <path d="M-80,0 A80,80 0 0,1 80,0 L0,100 Z" fill="url(#fleshGrad)"/>
    <path d="M-80,0 A80,80 0 0,1 80,0" fill="none" stroke="#228B22" stroke-width="10"/>
    <g fill="black">
      <circle cx="-30" cy="20" r="2"/>
      <circle cx="0" cy="40" r="2"/>
      <circle cx="30" cy="30" r="2"/>
    </g>
  </g>
  <!-- Bottom-left striped ellipse with rind edge -->
  <g transform="translate(150, 650) rotate(20) scale(1.2)">
    <ellipse rx="90" ry="100" fill="url(#stripes)" stroke="#228B22" stroke-width="2"/>
    <path d="M-90,0 Q-70,20 -50,0 Q-30,20 -10,0 Q10,20 30,0 Q50,20 70,0 L70,100 Q50,80 30,100 Q10,80 -10,100 Q-30,80 -50,100 Q-70,80 -90,100 Z" fill="url(#fleshGrad)"/>
    <g fill="black">
      <circle cx="-60" cy="40" r="2"/>
      <circle cx="-20" cy="60" r="2"/>
      <circle cx="20" cy="50" r="2"/>
      <circle cx="50" cy="70" r="2"/>
    </g>
  </g>
  <!-- Mid-left small wedge -->
  <g transform="translate(200, 250) rotate(45) scale(0.8)">
    <path d="M-60,0 A60,60 0 0,1 60,0 L0,75 Z" fill="url(#fleshGrad)"/>
    <path d="M-60,0 A60,60 0 0,1 60,0" fill="none" stroke="#228B22" stroke-width="8"/>
    <g fill="black">
      <circle cx="-20" cy="20" r="2"/>
      <circle cx="20" cy="30" r="2"/>
    </g>
  </g>
  <!-- Bottom-right small wedge -->
  <g transform="translate(600, 600) rotate(15) scale(0.7)">
    <path d="M-50,0 A50,50 0 0,1 50,0 L0,60 Z" fill="url(#fleshGrad)"/>
    <path d="M-50,0 A50,50 0 0,1 50,0" fill="none" stroke="#228B22" stroke-width="7"/>
    <g fill="black">
      <circle cx="-10" cy="20" r="2"/>
      <circle cx="10" cy="15" r="2"/>
    </g>
  </g>
  <!-- Right-center striped ellipse with white quarter -->
  <g transform="translate(700, 400) rotate(90) scale(1.1)">
    <ellipse rx="80" ry="90" fill="url(#stripes)" stroke="#228B22" stroke-width="2"/>
    <path d="M0,-90 L0,0 L80,0 A80,90 0 0,0 0,-90" fill="white"/>
  </g>
</svg>
```

#### Remember Icon

- Rendered size: 24x24
- ViewBox: `0 0 800 400`
- Description: A stylized key — red heart-shaped head (rotated -90deg) with green stroke and black eye dots, connected to a green key shaft with a flag tooth, and a small black rectangle at the tip.

```xml
<svg width="24" height="24" viewBox="0 0 800 400" xmlns="http://www.w3.org/2000/svg">
  <!-- Heart-shaped key head, rotated -90deg from bottom-left -->
  <g transform="translate(0, 400) rotate(-90)">
    <path d="M120,100 C80,100 50,140 50,200 C50,260 80,300 120,300 C160,300 180,260 190,220 C200,260 220,300 260,300 C300,300 330,260 330,200 C330,140 300,100 260,100 C220,100 200,140 190,180 C180,140 160,100 120,100 Z"
          fill="#E52421" stroke="#228B22" stroke-width="20"/>
    <!-- Eye dots -->
    <circle cx="120" cy="200" r="15" fill="#000000"/>
    <circle cx="260" cy="200" r="15" fill="#000000"/>
  </g>
  <!-- Key shaft with flag tooth -->
  <path d="M330,180 L760,180 C771.046,180 780,188.954 780,200 C780,211.046 771.046,220 760,220 L660,220 L660,270 L740,270 L740,320 L660,320 L660,220 L330,220 Z"
        fill="#228B22"/>
  <!-- Tip rectangle -->
  <rect x="680" y="280" width="40" height="20" fill="#000000"/>
</svg>
```

#### Orbit Icon

- Rendered size: 24x24
- ViewBox: `0 0 100 100`
- Description: Three concentric circles (green outer, white middle, red inner) with black seed-shaped dots arranged in a 5-row grid across the red area, resembling a watermelon cross-section.

```xml
<svg width="24" height="24" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <!-- Three concentric rings -->
  <circle cx="50" cy="50" r="48" fill="#009746"/>
  <circle cx="50" cy="50" r="40" fill="#FFFFFF"/>
  <circle cx="50" cy="50" r="35" fill="#E52421"/>

  <!-- Seed dots (black, teardrop-shaped paths) arranged in 5 rows -->
  <g fill="#000000">
    <!-- Row 1 (top, 3 seeds) -->
    <path d="M50,24 C51.5,24 52.5,27 52.5,29 C52.5,31.5 51.2,33 50,33 C48.8,33 47.5,31.5 47.5,29 C47.5,27 48.5,24 50,24 Z"/>
    <path d="M62,28 C63.5,28 64.5,31 64.5,33 C64.5,35.5 63.2,37 62,37 C60.8,37 59.5,35.5 59.5,33 C59.5,31 60.5,28 62,28 Z"/>
    <path d="M38,28 C39.5,28 40.5,31 40.5,33 C40.5,35.5 39.2,37 38,37 C36.8,37 35.5,35.5 35.5,33 C35.5,31 36.5,28 38,28 Z"/>

    <!-- Row 2 (upper-mid, 4 seeds) -->
    <path d="M30,41 C31.5,41 32.5,44 32.5,46 C32.5,48.5 31.2,50 30,50 C28.8,50 27.5,48.5 27.5,46 C27.5,44 28.5,41 30,41 Z"/>
    <path d="M44,44 C45.5,44 46.5,47 46.5,49 C46.5,51.5 45.2,53 44,53 C42.8,53 41.5,51.5 41.5,49 C41.5,47 42.8,44 44,44 Z"/>
    <path d="M56,44 C57.5,44 58.5,47 58.5,49 C58.5,51.5 57.2,53 56,53 C54.8,53 53.5,51.5 53.5,49 C53.5,47 54.8,44 56,44 Z"/>
    <path d="M70,41 C71.5,41 72.5,44 72.5,46 C72.5,48.5 71.2,50 70,50 C68.8,50 67.5,48.5 67.5,46 C67.5,44 68.5,41 70,41 Z"/>

    <!-- Row 3 (lower-mid, 4 seeds) -->
    <path d="M30,59 C31.5,59 32.5,62 32.5,64 C32.5,66.5 31.2,68 30,68 C28.8,68 27.5,66.5 27.5,64 C27.5,62 28.5,59 30,59 Z"/>
    <path d="M44,62 C45.5,62 46.5,65 46.5,67 C46.5,69.5 45.2,71 44,71 C42.8,71 41.5,69.5 41.5,67 C41.5,65 42.8,62 44,62 Z"/>
    <path d="M56,62 C57.5,62 58.5,65 58.5,67 C58.5,69.5 57.2,71 56,71 C54.8,71 53.5,69.5 53.5,67 C53.5,65 54.8,62 56,62 Z"/>
    <path d="M70,59 C71.5,59 72.5,62 72.5,64 C72.5,66.5 71.2,68 70,68 C68.8,68 67.5,66.5 67.5,64 C67.5,62 68.5,59 70,59 Z"/>

    <!-- Row 4 (bottom, 3 seeds) -->
    <path d="M38,72 C39.5,72 40.5,75 40.5,77 C40.5,79.5 39.2,81 38,81 C36.8,81 35.5,79.5 35.5,77 C35.5,75 36.5,72 38,72 Z"/>
    <path d="M62,72 C63.5,72 64.5,75 64.5,77 C64.5,79.5 63.2,81 62,81 C60.8,81 59.5,79.5 59.5,77 C59.5,75 60.5,72 62,72 Z"/>
    <path d="M50,76 C51.5,76 52.5,79 52.5,81 C52.5,83.5 51.2,85 50,85 C48.8,85 47.5,83.5 47.5,81 C47.5,79 48.5,76 50,76 Z"/>
  </g>
</svg>
```

#### Checkmark Icon (used in Connection Card burst)

- ViewBox: `0 0 24 24`
- Fill: `currentColor` (inherits `#1DB954`)

```xml
<svg viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
</svg>
```

#### Chat Bubble Icon (used in "Send Message" button)

- ViewBox: `0 0 24 24`
- Fill: `currentColor` (inherits `#1DB954`)

```xml
<svg viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
  <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z"/>
</svg>
```

---

## 7. RingBrandedAvatar (Generative Avatar)

**Flutter widget:** Custom `StatelessWidget` using `CustomPainter`

A deterministic, hash-based generative avatar rendered as concentric rings on a dark background. Given the same `peerId` string, it always produces the same visual.

### Input

| Param | Type | Default | Description |
|---|---|---|---|
| `peerId` | String | required | Seed string for hash generation |
| `size` | double | 64 | Widget width and height in px |

### Hash Algorithm & Color Generation

> **Note to coding agent:** The Flutter application already has its own hash algorithm and color generation logic. Use the existing implementation from the app's codebase. Do **not** introduce a new hash function — reuse whatever the project already provides so that avatar visuals stay consistent across the application.

The key contract is:
- The hash function takes a `peerId` string and returns a deterministic positive integer.
- The color generator takes that hash + an index and returns an HSL-derived `Color`.
- Given the same `peerId`, the same visual must always be produced.

### Rendering

**Canvas:** SVG with viewBox `0 0 100 100` -> in Flutter, a `CustomPainter` on a 100x100 logical canvas.

1. **Background rectangle:** Fill `#0a0a0f`, corner radius 15
2. **Rings:** 3-5 concentric circles (count = `3 + (hash % 3)`)

   For each ring `i`:
   | Property | Derivation |
   |---|---|
   | Radius | Starts at 42, decreases by `7 + (ringHash % 4)` per ring |
   | Stroke width | `(ringHash % 3) + 2` (range 2-4) |
   | Color | From brand palette: `['#ff3b3b', '#ffffff', '#1a1a1a', '#1DB954']`, index `(hash + i * 13) % 4` |
   | Dash pattern | Even rings: solid. Odd rings: dashed `[(ringHash % 8) + 4, (ringHash % 4) + 2]` |
   | Rotation | `ringHash2 * 3.6` degrees |
   | Opacity | `0.75 + (ringHash % 26) / 100` (range 0.75-1.0) |
   | Fill | None (stroke only) |

3. **Center glow:** Three concentric filled circles at center (50, 50):
   - r=12, fill=glowColor, opacity=0.25
   - r=8, fill=glowColor, opacity=0.5
   - r=5, fill=glowColor, opacity=1.0

   `glowColor` is derived from `getColorFromHash(hash, 0)`.

---

## 8. Scroll-Based Nav Visibility Behavior

**Flutter implementation:** `ScrollController` with listener, managed in a `StatefulWidget`

The navigation bar auto-hides when scrolling down and reappears when scrolling up.

### Architecture

The React source implements this as a custom hook (`useScrollNavVisibility`) that:
1. Creates a boolean state `isNavVisible` (initially `true`)
2. Stores a mutable `lastScrollY` ref (initially `0`)
3. Returns a `containerRef` that must be attached to the **inner scrollable container** (not the outer frame)

The listener is attached to the scrollable container's native `scroll` event — **not** the window or body. This is critical because the screen uses a nested scroll architecture (see Section 2): the outer frame clips and positions, while the inner `app-container` div actually scrolls.

### Listener Wiring & Lifecycle

#### Mount phase (React `useEffect` with `[]` deps = Flutter `initState`)

```
1. Get reference to the scroll container element
2. If null, bail out (container not yet rendered)
3. Define handleScroll callback (see Logic below)
4. Attach: container.addEventListener('scroll', handleScroll, { passive: true })
```

The `{ passive: true }` option tells the browser this listener will never call `preventDefault()`, enabling scroll performance optimizations. In Flutter, `ScrollController` listeners are inherently passive — no extra flag needed.

#### Unmount phase (React cleanup return = Flutter `dispose`)

```
1. Remove the listener: container.removeEventListener('scroll', handleScroll)
```

In Flutter, this maps to:

```dart
@override
void dispose() {
  _scrollController.removeListener(_handleScroll);
  _scrollController.dispose();
  super.dispose();
}
```

#### Which element the listener is attached to

The `containerRef` is placed on the inner scrollable `div` (the one with `overflowY: auto`), **not** on the outer `screen-frame` div:

```
screen-frame (position: relative, overflow: hidden)  ← NO listener here
  └── app-container (overflowY: auto, ref={containerRef})  ← Listener HERE
```

In Flutter, this means the `ScrollController` is passed to the `SingleChildScrollView` or `CustomScrollView` that sits inside the `Stack`, not to the `Stack` itself.

### Scroll Direction Logic

```
State:
  isNavVisible = true
  lastScrollY  = 0.0

onScroll(currentScrollY):
  isScrollingDown = currentScrollY > lastScrollY
  isAtTop = currentScrollY < 50

  if isAtTop:
    show nav                                       // always visible at top
  else if isScrollingDown AND currentScrollY > 100:
    hide nav                                       // hide after scrolling down past 100px
  else if NOT isScrollingDown:
    show nav                                       // show immediately on any upward scroll

  lastScrollY = currentScrollY
```

| Threshold | Value | Purpose |
|---|---|---|
| Near-top zone | `< 50px` | Always show nav regardless of direction |
| Hide threshold | `> 100px` | Don't hide until user has scrolled down at least 100px (prevents flicker on small bounces) |

### Flutter Implementation

```dart
class _FirstContactDScreenState extends State<FirstContactDScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isNavVisible = true;
  double _lastScrollY = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    final currentScrollY = _scrollController.offset;
    final isScrollingDown = currentScrollY > _lastScrollY;
    final isAtTop = currentScrollY < 50;

    bool shouldShow;
    if (isAtTop) {
      shouldShow = true;
    } else if (isScrollingDown && currentScrollY > 100) {
      shouldShow = false;
    } else if (!isScrollingDown) {
      shouldShow = true;
    } else {
      shouldShow = _isNavVisible; // no change
    }

    if (shouldShow != _isNavVisible) {
      setState(() => _isNavVisible = shouldShow);
    }
    _lastScrollY = currentScrollY;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scrollController,  // ← attached here
          child: /* ... scrollable content ... */,
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: _isNavVisible ? 1.0 : 0.0,
            duration: Duration(milliseconds: 300),
            curve: Curves.ease,
            child: IgnorePointer(
              ignoring: !_isNavVisible,
              child: NavigationBar(/* ... */),
            ),
          ),
        ),
      ],
    );
  }
}
```

### Visibility Transition

| Property | Hidden | Visible |
|---|---|---|
| Opacity | 0 | 1 |
| Pointer events | Disabled (`IgnorePointer`) | Enabled |
| Transition | 0.3s ease | 0.3s ease |

---

## 9. Theme / Color System

The screen supports theming via CSS custom properties. In Flutter, implement as a theme data class passed down via `InheritedWidget`, `Provider`, or similar mechanism.

### Theme Data Class

```dart
class MknoonTheme {
  final String id;
  final String name;
  final Color bg;
  final Color accent1;
  final Color accent2;
  final Color text;
  final Color textMuted;
  final Color glassBg;
  final Color glassBorder;
}
```

### Default Theme Values

| Field | Value |
|---|---|
| `id` | `'default'` |
| `name` | `'Current'` |
| `bg` | `#0a0a0f` |
| `accent1` | `#1DB954` |
| `accent2` | `#1ed760` |
| `text` | `#ffffff` |
| `textMuted` | `rgba(255, 255, 255, 0.6)` |
| `glassBg` | `rgba(30, 30, 35, 0.6)` |
| `glassBorder` | `rgba(255, 255, 255, 0.05)` |

### How Theme Values Flow at Runtime

In the React source, the screen component receives a `theme` object as a prop and maps each field to a CSS custom property on the outermost `screen-frame` `div`. All child elements then consume these variables.

#### Step 1: Theme object is mapped to inline CSS variables on the root element

```jsx
// src/FirstContactScreenD.jsx:440-448
const themeStyles = {
  '--theme-bg':           theme.bg,           // consumed by .app-container background
  '--theme-accent1':      theme.accent1,      // consumed by headline color, glow filters, action button bg/border
  '--theme-accent2':      theme.accent2,      // consumed by gradient endpoints (e.g. match-action-primary)
  '--theme-text':         theme.text,          // consumed by --text-primary fallback
  '--theme-text-muted':   theme.textMuted,     // consumed by --text-muted fallback
  '--theme-glass-bg':     theme.glassBg,       // consumed by nav bar, overlays
  '--theme-glass-border': theme.glassBorder,   // consumed by card/nav borders
};
```

These are set as inline `style` on the outermost `<div className="screen-frame">`:

```jsx
// src/FirstContactScreenD.jsx:465
<div className={`screen-frame theme-${theme.id}`}
     style={{...themeStyles, ...frameStyles}}>
```

#### Step 2: Root-level CSS variables provide fallback defaults

The `:root` block in `index.css` defines default values that apply when no theme variable is set:

| CSS variable | Default (`:root`) | Overridden by theme? |
|---|---|---|
| `--glass-bg` | `rgba(255, 255, 255, 0.08)` | Not directly — used as card background |
| `--glass-border` | `rgba(255, 255, 255, 0.12)` | Not directly — used as card border |
| `--glass-blur` | `24px` | No (constant) |
| `--text-primary` | `rgba(255, 255, 255, 0.95)` | No (constant in dark mode) |
| `--text-secondary` | `rgba(255, 255, 255, 0.6)` | No (constant in dark mode) |
| `--text-muted` | `rgba(255, 255, 255, 0.4)` | No (constant in dark mode) |

#### Step 3: Child components reference variables via `var()` with fallbacks

Throughout the CSS, child styles reference theme values with a fallback:

```css
/* Example: headline color */
color: var(--theme-accent1, #1DB954);

/* Example: action button glow */
box-shadow: 0 8px 30px color-mix(in srgb, var(--theme-accent1, #1DB954) 50%, transparent);

/* Example: card background */
background: var(--glass-bg);  /* uses root default, NOT theme override */
```

#### Complete consumer mapping

This table shows every theme field and exactly which components consume it:

| Theme field | CSS variable | Consumed by |
|---|---|---|
| `bg` | `--theme-bg` | `.app-container` background |
| `accent1` | `--theme-accent1` | "Connected!" h1 color + text-shadow, `.match-icon-burst svg` color + drop-shadow filter, `.burst` border color, `.match-action-compact` background tint + border + text color, `.match-action-primary` gradient start, `.first-message-card .friend-indicator::after` dot color |
| `accent2` | `--theme-accent2` | `.match-action-primary` gradient end |
| `text` | `--theme-text` | Not directly consumed in compact variant (uses `--text-primary` root default) |
| `textMuted` | `--theme-text-muted` | Not directly consumed in compact variant (uses `--text-muted` root default) |
| `glassBg` | `--theme-glass-bg` | Not directly consumed by card (card uses `--glass-bg` root default) |
| `glassBorder` | `--theme-glass-border` | Not directly consumed by card (card uses `--glass-border` root default) |

#### Flutter implementation

In Flutter, there is no CSS variable cascade. Instead:

1. Create the `MknoonTheme` instance at the top of the widget tree.
2. Pass it down via `InheritedWidget`, `Provider`, or constructor injection.
3. Each child widget reads from `theme.accent1`, `theme.bg`, etc. directly.
4. For the root-level constants (`glassBg`, `glassBorder`, `glassBlur`, `textPrimary`, `textMuted`), define them as static constants on the theme class or in a separate `AppColors` class, since they don't change with the theme in the current implementation:

```dart
class AppColors {
  static const glassBg     = Color.fromRGBO(255, 255, 255, 0.08);
  static const glassBorder = Color.fromRGBO(255, 255, 255, 0.12);
  static const glassBlur   = 24.0;
  static const textPrimary = Color.fromRGBO(255, 255, 255, 0.95);
  static const textSecondary = Color.fromRGBO(255, 255, 255, 0.6);
  static const textMuted   = Color.fromRGBO(255, 255, 255, 0.4);
}
```

5. The `theme-${theme.id}` class name in the source is used for theme-specific CSS overrides (e.g. `theme-daylight` swaps to light-mode colors). In Flutter, handle this with conditional logic in the theme class or by switching between theme instances.

---

## 10. Animations Reference

All animations used in the screen, with their Flutter equivalents.

### cardEnter

- Trigger: On widget mount
- Duration: 0.6s, ease
- From: `opacity: 0, translateY(30px), scale(0.95)`
- To: `opacity: 1, translateY(0), scale(1)`
- Flutter: `SlideTransition` + `ScaleTransition` + `FadeTransition` with `CurvedAnimation(curve: Curves.easeOut)`

### avatarEnter

- Trigger: On mount, **0.2s delay**
- Duration: 0.6s, `cubic-bezier(0.16, 1, 0.3, 1)`
- From: `opacity: 0, scale(0.5)`
- To: `opacity: 1, scale(1)`
- Flutter: `ScaleTransition` + `FadeTransition` with custom `Cubic(0.16, 1, 0.3, 1)` curve

### iconPop

- Trigger: On mount, **0.3s delay**
- Duration: 0.5s, `cubic-bezier(0.16, 1, 0.3, 1)`
- From: `opacity: 0, scale(0)`
- To: `opacity: 1, scale(1)`
- Flutter: Same as avatarEnter but from scale 0

### burstExpand (infinite, per ring)

- Duration: 1.5s, ease-out, infinite loop
- From: `scale(0.5), opacity: 0.8`
- To: `scale(2), opacity: 0`
- Stagger: ring 1 = 0s, ring 2 = 0.3s, ring 3 = 0.6s
- Flutter: `AnimationController(duration: 1500ms)..repeat()` with staggered `Interval`s

### fadeInUp

Used for headline, friend info, and action button with staggered delays.

- Duration: 0.5s, ease
- From: `opacity: 0, translateY(20px)` (implicit from CSS)
- To: `opacity: 1, translateY(0)`
- Delays: 0.4s (headline), 0.6s (friend info), 0.7s (action)
- Flutter: `SlideTransition` + `FadeTransition` with `Future.delayed` or `Interval`

### ambientFloat (infinite)

- Duration: 20s, ease-in-out, infinite
- Keyframes: slow drift translate + rotation (see Section 3)
- Flutter: `AnimationController(duration: 20s)..repeat()` driving a `Transform`

### Nav visibility fade

- Duration: 0.3s, ease
- Property: opacity only
- Flutter: `AnimatedOpacity(duration: 300ms)`

---

## Component Dependency Tree

```
FirstContactDScreen
├── theme: MknoonTheme
├── scrollNavVisibility: ScrollController logic
│
├── AmbientBackground
│     └── AnimatedGradientLayer (3 radial gradients, slow drift)
│
├── Header
│     ├── UsernameDisplay
│     │     ├── PrefixText ("mknoon/")
│     │     └── UsernameText ("@Username")
│     └── AvatarFrame
│           └── RingBrandedAvatar(peerId, size: 44)
│
├── ConnectionCard (Stack)
│     ├── CardShell (glass container, 28px radius, min-height 360px)
│     ├── CardGlow (top gradient overlay, absolute)
│     ├── AvatarSection (z-index 1, absolute centered)
│     │     ├── AvatarGlow (blurred backdrop, 150x150)
│     │     └── AvatarWrapper (circular clip + 3-layer shadow)
│     │           ├── NetworkImage (120x120, cover) OR
│     │           └── RingBrandedAvatar(peerId, size: 100)
│     └── ContentWrapper (z-index 2, Column, min-height 360px, justify: end)
│           ├── Headline (padding-top: 15, padding-bottom: 80)
│           │     ├── BurstAnimation (3 expanding rings)
│           │     ├── CheckmarkIcon (animated pop)
│           │     └── "Connected!" Text
│           ├── FriendInfo (margin-top: 80, margin-bottom: 4)
│           │     └── FriendName Text
│           └── ActionButton (margin-top: 8, "Send Message", pill shape)
│
└── NavigationBar(activeTab, isVisible, onSwitchView)
      └── GlassBarContainer
            ├── NavButton(icon: FeedIcon, label: "Feed", tab: "feed")
            ├── NavButton(icon: RememberIcon, label: "Remember", tab: "memories")
            └── NavButton(icon: OrbitIcon, label: "Orbit", tab: "circle")
```

Each box in this tree is a separate Flutter widget file for easy editing and reuse.
