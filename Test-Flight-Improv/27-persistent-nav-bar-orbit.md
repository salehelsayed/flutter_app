# 27 - Persistent Bottom Navigation Bar Across Feed and Orbit

**Bug**

---

## 1. Problem Statement

The bottom navigation bar (Feed / Orbit) is visible on the Feed screen but
**disappears entirely** when the user taps "Orbit". The Orbit screen slides up
as a full-screen modal route that covers the Feed screen, and since the nav bar
is owned by `FeedScreen`, it is no longer visible.

**Current behavior:**

1. User is on the Feed screen. The bottom nav bar shows "Feed" (active) and
   "Orbit" (inactive).
2. User taps "Orbit" in the nav bar.
3. `AppShellController.switchTo('orbit')` fires, which triggers
   `FeedWired._openOrbitRoute()`.
4. `Navigator.push(buildOrbitSlideUpRoute(OrbitWired))` pushes the Orbit screen
   as a new route on top of the Feed screen.
5. The Orbit screen slides up (420ms easeOutCubic) and **covers the entire
   screen**, including the nav bar.
6. The Orbit screen has no bottom nav bar of its own. It has only an
   `OrbitCloseButton` (X button) to return.
7. User taps X → `Navigator.pop()` → Orbit slides down, Feed with nav bar
   reappears.

**What is wrong:**

- The nav bar disappears when navigating to Orbit, so the user loses the
  persistent tab-switching affordance.
- There is no visual indication on the Orbit screen that the user is on the
  "Orbit" tab — the nav bar is gone and no other indicator exists.
- To return to Feed, the user must find and tap the close (X) button in the
  bottom-right corner of the Orbit screen, which is not the same interaction
  pattern as tapping "Feed" in a nav bar.
- Standard mobile app convention (Instagram, Signal, WhatsApp, etc.) is for
  the bottom tab bar to persist across all top-level tabs.

**Who is affected:** All users, every time they navigate between Feed and Orbit.

**Reproduction steps:**

1. Open the app → land on Feed screen with bottom nav bar visible.
2. Tap "Orbit" button in the bottom nav bar.
3. Observe: Orbit screen slides up, nav bar disappears.

---

## 2. Impact Analysis

| Dimension | Assessment |
|-----------|-----------|
| Severity | Degrades experience — breaks standard mobile navigation convention |
| Frequency | Every time a user navigates to Orbit (100% reproducible) |
| User consequence | Nav bar disappears; user must use X button to return; no tab indicator on Orbit screen |
| Workaround | Tap X button on Orbit screen to return to Feed |
| Platform scope | iOS and Android (Flutter) |

---

## 3. Current State

### 3.1 Bottom Navigation Bar

| File | Purpose | Key Lines |
|------|---------|-----------|
| `lib/features/feed/presentation/widgets/feed_navigation_bar.dart` | Glass-morphism nav bar with Feed/Orbit buttons | Lines 8–73 |
| `lib/features/feed/presentation/widgets/nav_bar_button.dart` | Individual nav button with active gradient pill, badge | Lines 24–87 |
| `lib/features/feed/presentation/widgets/nav_bar_theme.dart` | Design tokens (border radius, blur, colors, animation) | Lines 9–56 |

**`FeedNavigationBar`** (feed_navigation_bar.dart):
- Props: `activeTab` (String), `onSwitchView` callback, `feedBadgeCount` (int) (lines 9–17)
- Two `NavBarButton` children: "Feed" (`nav_feed` label, `nav_feed.svg` icon)
  and "Orbit" (`nav_orbit` label, `nav_orbit.svg` icon) (lines 52–65)
- Active state: `isActive: activeTab == 'feed'` / `isActive: activeTab == 'orbit'` (lines 55, 63)
- Styling: `BackdropFilter` blur, gradient background, border, shadow (lines 22–46)

**`NavBarButton`** (nav_bar_button.dart):
- Active: gradient pill background (`activePillGradient`), `FontWeight.w600`, full opacity (lines 37–51)
- Inactive: no pill, `FontWeight.w500`, 60% icon opacity, 55% text opacity (lines 24–27)
- 220ms animation duration for state transitions (nav_bar_theme.dart line 36)

### 3.2 Nav Bar Hosting in FeedScreen

| File | Key Lines |
|------|-----------|
| `lib/features/feed/presentation/screens/feed_screen.dart` | Lines 175–192, 228–246 |

- Nav bar is rendered inside `FeedScreen.build()` as a `Positioned` widget at
  the bottom of a `Stack` (lines 175–182).
- Positioned at `bottom: bottomInset - 14` (line 180).
- Hidden only when reply input is focused AND keyboard is visible (line 189–192):
  `activeFocusPeerId != null && keyboardVisible`.
- `_buildNavigationBar()` passes `activeTab` and `onSwitchView` to
  `FeedNavigationBar` (lines 228–246).

**Key constraint:** The nav bar exists only within `FeedScreen`'s widget tree.
When `FeedScreen` is covered by a pushed route, its nav bar is not visible.

### 3.3 Feed → Orbit Navigation

| File | Key Lines |
|------|-----------|
| `lib/features/feed/presentation/screens/feed_wired.dart` | Lines 1985–2041 |
| `lib/features/feed/application/app_shell_controller.dart` | Lines 1–22 |
| `lib/features/feed/domain/models/app_shell_tab.dart` | Lines 2–5 |
| `lib/features/orbit/presentation/navigation/orbit_route_transition.dart` | Lines 1–34 |

**Navigation flow:**

1. User taps "Orbit" → `onSwitchView('orbit')` → `AppShellController.switchTo('orbit')` (feed_wired.dart:2043–2044)
2. Controller notifies listeners → `FeedWired._onShellChanged()` (line 1977)
3. If `activeTab == AppShellTab.orbit && !_orbitRouteOpen` → `_openOrbitRoute()` (lines 1988–1989)
4. `Navigator.of(context).push(buildOrbitSlideUpRoute(OrbitWired))` (lines 1998–2032)
5. **Orbit is a modal route pushed on top of Feed** — it covers the full screen including the nav bar
6. On close: `.then()` callback sets `_orbitRouteOpen = false`, switches back to `_orbitReturnTab` (lines 2033–2040)

**`AppShellController`** (app_shell_controller.dart): Simple `ChangeNotifier`
managing a `_activeTab` string. `switchTo(tab)` validates and notifies. Only
two valid tabs: `'feed'` and `'orbit'` (app_shell_tab.dart lines 2–3).

**Route transition** (orbit_route_transition.dart): `buildOrbitSlideUpRoute()`
creates a `PageRouteBuilder` with 420ms easeOutCubic slide-up from
`Offset(0, 1)` to `Offset.zero`, plus fade 0.92→1.0. Reverse: 280ms
easeInCubic (lines 7–34).

### 3.4 Orbit Screen

| File | Purpose | Key Lines |
|------|---------|-----------|
| `lib/features/orbit/presentation/screens/orbit_screen.dart` | Orbit UI | Lines 128, 309–313 |
| `lib/features/orbit/presentation/screens/orbit_wired.dart` | Orbit wiring | Line 2026: receives `appShellController` |

- `OrbitScreen` is a full-screen `Scaffold` with a `Stack`.
- Has `onClose` callback (line 128) wired to `Navigator.pop()`.
- Has `OrbitCloseButton` at bottom-right (lines 309–313) — the only way back.
- **No `FeedNavigationBar` or equivalent is rendered on the Orbit screen.**
- `OrbitWired` receives `appShellController` (line 2026) but does not use it to render a nav bar.

### 3.5 Return-to-Feed State Tracking

- `FeedWired` tracks `_orbitRouteOpen` (bool, line 186) and `_orbitReturnTab`
  (String, line 187).
- On shell change, if not orbit, stores current tab as `_orbitReturnTab`
  (line 1985–1986).
- After Orbit route pops, `.then()` handler checks if controller is still on
  orbit tab and switches back to `_orbitReturnTab` (lines 2035–2036).

### 3.6 Notification Deep-Link to Orbit

- `main.dart` line ~1423: Intro notifications push `OrbitWired` via
  `Navigator.push(buildOrbitSlideUpRoute(...))` — same pattern, same nav bar
  disappearance.

---

## 4. Scope Clarification

| Area | Status | Notes |
|------|--------|-------|
| Nav bar visible on both Feed and Orbit screens | **In scope** | Core bug fix |
| "Orbit" button shows active state when on Orbit screen | **In scope** | Visual indicator requirement |
| "Feed" button tappable from Orbit to switch back | **In scope** | Must work from Orbit |
| "Orbit" button tappable from Feed to switch to Orbit | **Unchanged** | Already works |
| Feed badge count visible on Orbit screen's nav bar | **In scope** | Badge should persist |
| `OrbitCloseButton` (X button) removal or retention | **Out of scope** | May coexist or be removed; not specified |
| Nav bar hides when keyboard is open (existing behavior) | **Unchanged** | Current hide logic stays |
| Orbit slide-up animation timing and style | **Out of scope** | Transition visual may change as an implementation consequence but is not the goal |
| Feed screen content, cards, scrolling | **Unchanged** | No changes to Feed content |
| Orbit screen content (friends, groups, intros tabs) | **Unchanged** | No changes to Orbit content |
| Notification deep-link to Orbit | **In scope** | Nav bar should also be visible when arriving via notification |
| Third tab additions | **Out of scope** | Only Feed and Orbit exist today |

---

## 5. Test Cases

### Group A: Nav Bar Persistence

**TC-27-A01** — Nav bar is visible on the Feed screen
Given the user opens the app and lands on the Feed screen,
when the screen finishes loading,
then the bottom navigation bar is visible with "Feed" and "Orbit" buttons.

**TC-27-A02** — Nav bar remains visible after navigating to Orbit
Given the user is on the Feed screen with the nav bar visible,
when the user taps the "Orbit" button,
then the Orbit screen content appears AND the bottom navigation bar remains
visible at the bottom of the screen.

**TC-27-A03** — Nav bar remains visible after navigating back to Feed from Orbit
Given the user is on the Orbit screen with the nav bar visible,
when the user taps the "Feed" button in the nav bar,
then the Feed screen content appears AND the bottom navigation bar remains
visible at the bottom of the screen.

**TC-27-A04** — Nav bar is visible when navigating to Orbit via notification deep-link
Given the app receives an introduction notification,
when the user taps the notification and the app navigates to the Orbit screen,
then the bottom navigation bar is visible with "Orbit" shown as the active tab.

### Group B: Active Tab Indicator

**TC-27-B01** — "Feed" shows as active when on the Feed screen
Given the user is on the Feed screen,
when the user looks at the bottom navigation bar,
then the "Feed" button has the active visual treatment (gradient pill
background, full opacity icon and text) and the "Orbit" button has the inactive
treatment (no pill, dimmed icon and text).

**TC-27-B02** — "Orbit" shows as active when on the Orbit screen
Given the user navigated to the Orbit screen,
when the user looks at the bottom navigation bar,
then the "Orbit" button has the active visual treatment (gradient pill
background, full opacity icon and text) and the "Feed" button has the inactive
treatment (no pill, dimmed icon and text).

**TC-27-B03** — Active indicator transitions when switching tabs
Given the user is on the Feed screen with "Feed" active,
when the user taps "Orbit",
then the active indicator animates from "Feed" to "Orbit" (the gradient pill
moves from one button to the other).

**TC-27-B04** — Active indicator transitions back when switching to Feed
Given the user is on the Orbit screen with "Orbit" active,
when the user taps "Feed",
then the active indicator animates from "Orbit" to "Feed".

### Group C: Tab Switching Behavior

**TC-27-C01** — Tapping "Feed" while on Feed does nothing
Given the user is on the Feed screen with "Feed" active,
when the user taps "Feed" again,
then nothing happens — the screen does not reload, flicker, or scroll.

**TC-27-C02** — Tapping "Orbit" while on Orbit does nothing
Given the user is on the Orbit screen with "Orbit" active,
when the user taps "Orbit" again,
then nothing happens — the screen does not reload or flicker.

**TC-27-C03** — Rapid switching between Feed and Orbit
Given the user is on the Feed screen,
when the user taps "Orbit" then immediately taps "Feed" then "Orbit" again in
quick succession,
then the final screen shown matches the last tab tapped, the nav bar is visible,
and the correct tab is active. No crash, no stuck state.

**TC-27-C04** — Feed scroll position preserved after switching to Orbit and back
Given the user scrolled down in the Feed to see card #15,
when the user switches to Orbit, then switches back to Feed,
then the Feed is still scrolled to approximately the same position (card #15
visible), not reset to the top.

**TC-27-C05** — Orbit state preserved after switching to Feed and back
Given the user is on the Orbit screen, has switched to the "Groups" tab and
scrolled down,
when the user switches to Feed and then back to Orbit,
then the Orbit screen shows the "Groups" tab at approximately the same scroll
position.

### Group D: Nav Bar and Keyboard Interaction

**TC-27-D01** — Nav bar hides when keyboard opens on Feed
Given the user is on the Feed screen and taps a reply input to open the keyboard,
when the keyboard finishes animating open,
then the nav bar is hidden (existing behavior preserved).

**TC-27-D02** — Nav bar reappears when keyboard closes on Feed
Given the keyboard is open on the Feed screen and the nav bar is hidden,
when the user dismisses the keyboard,
then the nav bar reappears.

**TC-27-D03** — Nav bar behavior with keyboard on Orbit
Given the user is on the Orbit screen and opens the search input (keyboard appears),
when the keyboard is open,
then the nav bar hides or remains visible as appropriate for the Orbit screen
context (consistent behavior with Feed).

### Group E: Nav Bar Visual and Layout

**TC-27-E01** — Nav bar does not overlap Orbit screen content
Given the user is on the Orbit screen,
when the user scrolls to the bottom of the friends/groups/intros list,
then the last item in the list is fully visible and not obscured by the nav bar
(appropriate bottom padding exists).

**TC-27-E02** — Nav bar does not overlap Feed screen content
Given the user is on the Feed screen,
when the user scrolls to the bottom of the feed,
then the last feed card is fully visible and not obscured by the nav bar
(this already works; regression check).

**TC-27-E03** — Nav bar styling is consistent on both screens
Given the user switches between Feed and Orbit,
when the user compares the nav bar appearance on each screen,
then the nav bar has the same glassmorphic styling (blur, gradient, border,
shadow, size, position) on both screens.

**TC-27-E04** — Feed badge count is visible on Orbit screen
Given the user has 3 unread conversations on the Feed,
when the user is on the Orbit screen,
then the "Feed" button in the nav bar shows a badge with the count "3".

### Group F: Edge Cases

**TC-27-F01** — App backgrounded and resumed while on Orbit
Given the user is on the Orbit screen with the nav bar visible,
when the user backgrounds the app and returns to it,
then the Orbit screen is showing, the nav bar is visible, and "Orbit" is
the active tab.

**TC-27-F02** — Screen rotation (if supported) preserves nav bar
Given the user is on the Orbit screen in portrait mode,
when the device rotates to landscape (if rotation is enabled),
then the nav bar remains visible and properly positioned at the bottom.

**TC-27-F03** — Safe area / notch handling
Given a device with a bottom home indicator (iPhone X+) or navigation bar (Android),
when the user is on either Feed or Orbit,
then the nav bar is positioned above the system UI (safe area respected) on both
screens identically.

### Group G: Regression — Existing Features

**TC-27-G01** — Orbit close button still works (if retained)
Given the Orbit screen has both the nav bar and the X close button visible,
when the user taps the X close button,
then the app navigates back to the Feed screen with the nav bar showing "Feed"
as active.

**TC-27-G02** — Feed card interactions are not affected
Given the user is on the Feed screen with the nav bar visible,
when the user taps a feed card to open a conversation,
then the conversation opens normally (nav bar may hide during conversation).

**TC-27-G03** — Orbit friend/group tap navigation works
Given the user is on the Orbit screen with the nav bar visible,
when the user taps a friend to open a 1:1 conversation,
then the conversation opens normally.

**TC-27-G04** — Orbit tab switching (Friends, Groups, Intros) still works
Given the user is on the Orbit screen,
when the user taps between Friends, Groups, and Intros tabs within Orbit,
then each sub-tab renders correctly and the bottom nav bar continues to show
"Orbit" as active throughout.
