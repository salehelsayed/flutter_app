# 30 - Swipe Navigation Between Feed and Orbit Screens

**New Feature**

---

## 1. Problem Statement

The only way to navigate between the Feed and Orbit screens is by tapping
buttons in the bottom navigation bar. There is no swipe gesture to switch
between these two top-level screens, unlike standard mobile apps (Instagram,
Twitter/X, Snapchat) where horizontal swipe between main tabs is a common
interaction pattern.

**Current behavior:**

- Feed → Orbit: User taps "Orbit" in the bottom nav bar.
- Orbit → Feed: User taps the X close button (bottom-right) or "Feed" in the
  nav bar (if Report 27 is implemented).
- No horizontal swipe gesture exists at the screen level for switching between
  Feed and Orbit.
- Orbit is pushed as a modal route via `Navigator.push()` with a vertical
  slide-up animation (feed_wired.dart:1998–2032), not rendered as a sibling
  tab.

**What is missing:**

- A left-swipe gesture on the Feed screen to navigate to Orbit.
- A right-swipe gesture on the Orbit screen to navigate back to Feed.
- The current vertical slide-up transition feels modal, not tab-like; a
  horizontal transition would better convey sibling-tab navigation.

**Who is affected:** All users navigating between Feed and Orbit.

---

## 2. Impact Analysis

| Dimension | Assessment |
|-----------|-----------|
| Severity | Low-moderate — navigation works via buttons; swipe is a UX enhancement |
| Frequency | Every time a user switches between Feed and Orbit |
| User consequence | Less intuitive/efficient navigation; users expect swipe between tabs |
| Workaround | Tap nav bar buttons or close button |
| Platform scope | iOS and Android (Flutter) |

### Gesture Conflict Risk

There are existing horizontal swipe gestures on both screens that must
coexist with the proposed screen-level swipe:

| Existing Gesture | Screen | Direction | Trigger Threshold | Conflict Risk |
|-----------------|--------|-----------|-------------------|---------------|
| Swipe-to-reply (quote) | Feed | Right-swipe on received messages | 36px (50% of 72px) | **High** — same direction as Orbit→Feed swipe |
| Swipeable friend row | Orbit | Left-swipe on friend/group rows | 50% of action width (65–90px) | **Medium** — same direction as Feed→Orbit swipe |

---

## 3. Current State

### 3.1 Navigation Architecture

| File | Purpose | Key Lines |
|------|---------|-----------|
| `lib/features/feed/presentation/screens/feed_wired.dart` | Wires Feed; pushes Orbit as modal route | Lines 1995–2041 |
| `lib/features/feed/application/app_shell_controller.dart` | ChangeNotifier tracking `activeTab` | Lines 1–22 |
| `lib/features/feed/domain/models/app_shell_tab.dart` | Constants: `'feed'`, `'orbit'` | Lines 2–3 |
| `lib/features/orbit/presentation/navigation/orbit_route_transition.dart` | Vertical slide-up transition (420ms) | Lines 7–34 |

**Feed → Orbit:** `_onSwitchView('orbit')` → `AppShellController.switchTo('orbit')` →
`_onShellChanged()` → `_openOrbitRoute()` → `Navigator.push(buildOrbitSlideUpRoute(OrbitWired))`
(feed_wired.dart:1988–2000).

**Orbit → Feed:** `OrbitCloseButton.onTap` → `Navigator.pop()` → `.then()` handler
→ `AppShellController.switchTo(_orbitReturnTab)` (feed_wired.dart:2033–2040).

**Transition:** Vertical slide-up from `Offset(0, 1)` to `Offset.zero`, 420ms
easeOutCubic open, 280ms easeInCubic close. Fade 0.92→1.0. This is a modal
transition, not a horizontal tab transition.

### 3.2 Feed Screen Gesture Handling

| File | Key Lines |
|------|-----------|
| `lib/features/feed/presentation/screens/feed_screen.dart` | Lines 107–109, 211–225 |

- Top-level `GestureDetector(onTap: FocusScope.unfocus)` wraps the entire screen
  (line 107–109). `HitTestBehavior.translucent` — allows propagation.
- No horizontal drag handler at screen level.
- `CustomScrollView` with `BouncingScrollPhysics()` (line 213) handles vertical
  scrolling.
- Feed cards are rendered in a `SliverList`.

### 3.3 Feed Message Swipe-to-Reply (Conflict Zone)

| File | Key Lines |
|------|-----------|
| `lib/features/feed/presentation/widgets/swipe_to_quote_bubble.dart` | Lines 24–25, 54–96 |

- **Direction:** Right-swipe only (positive dx).
- **Direction lock:** 8px threshold; locks horizontal if `dx.abs() > dy.abs()` at
  8px movement (line 100).
- **Trigger:** 50% of 72px = 36px threshold fires `onQuoteTriggered()` (line 91–93).
- **Scope:** Only wraps incoming messages (conversation_screen.dart:478,
  scrollable_message_preview.dart:311).
- **Conflict:** A right-swipe to go from Orbit→Feed or at feed level would
  conflict with this gesture on incoming message bubbles.

### 3.4 Orbit Screen Gesture Handling

| File | Key Lines |
|------|-----------|
| `lib/features/orbit/presentation/screens/orbit_screen.dart` | Lines 254–300 |

- `CustomScrollView` with `BouncingScrollPhysics()` (line 256) for vertical
  scrolling.
- No screen-level horizontal gesture handler.
- `OrbitCloseButton` positioned bottom-right (lines 309–313) for return.

### 3.5 Orbit Swipeable Friend Rows (Conflict Zone)

| File | Key Lines |
|------|-----------|
| `lib/features/orbit/presentation/widgets/swipeable_friend_row.dart` | Lines 86–143 |

- **Direction:** Left-swipe only (negative dx reveals action buttons).
- **Direction lock:** 8px threshold; same pattern as swipe-to-reply.
- **Action widths:** 130px (no block) or 180px (with block/archived).
- **Snap:** 50% of action width threshold.
- **Scope:** Wraps all friend and group rows in Orbit.
- **Constraint:** `openRowNotifier` ensures only one row open at a time.
- **Conflict:** A left-swipe to go from Feed→Orbit would conflict with this
  gesture on friend rows.

### 3.6 Current Route Transition

| File | Key Lines |
|------|-----------|
| `lib/features/orbit/presentation/navigation/orbit_route_transition.dart` | Lines 7–34 |

- `PageRouteBuilder` with vertical slide-up.
- `transitionDuration: 420ms`, `reverseTransitionDuration: 280ms`.
- Slide: `Offset(0, 1)` → `Offset.zero` (vertical).
- Fade: 0.92 → 1.0.
- This is a push route, not a PageView/TabBarView page.

### 3.7 Existing Tests

| File | Coverage |
|------|----------|
| `test/features/feed/presentation/widgets/swipe_to_quote_bubble_test.dart` | Right-swipe threshold, snap-back, callback |
| `test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart` | Left-swipe reveal, action buttons, state |
| `test/features/feed/application/app_shell_controller_test.dart` | Tab switching, validation |

- No tests exist for screen-level horizontal swipe navigation.
- No tests for gesture conflict resolution between screen swipe and widget swipe.

---

## 4. Scope Clarification

| Area | Status | Notes |
|------|--------|-------|
| Left-swipe on Feed to go to Orbit | **In scope** | New screen-level gesture |
| Right-swipe on Orbit to go to Feed | **In scope** | New screen-level gesture |
| Horizontal transition animation (instead of vertical) | **In scope** | Matches swipe direction |
| Gesture conflict resolution with swipe-to-reply | **In scope** | Must coexist |
| Gesture conflict resolution with swipeable friend rows | **In scope** | Must coexist |
| Bottom nav bar active tab update on swipe | **In scope** | Tab indicator must reflect screen shown |
| Swipe-to-reply functionality | **Unchanged** | Must continue to work on message bubbles |
| Swipeable friend row functionality | **Unchanged** | Must continue to work on Orbit rows |
| Bottom nav bar button tapping | **Unchanged** | Buttons still work as before |
| Feed vertical scrolling | **Unchanged** | Must not be affected |
| Orbit vertical scrolling | **Unchanged** | Must not be affected |
| Three-finger or multi-touch gestures | **Out of scope** | Single-finger swipe only |
| Swipe between Orbit sub-tabs (Friends/Groups/Intros) | **Out of scope** | Only Feed ↔ Orbit |

---

## 5. Test Cases

### Group A: Basic Swipe Navigation

**TC-30-A01** — Swipe left on Feed navigates to Orbit
Given the user is on the Feed screen,
when the user swipes left (finger moves from right to left) across the screen
with sufficient horizontal distance,
then the Orbit screen slides in from the right and becomes the active screen.

**TC-30-A02** — Swipe right on Orbit navigates to Feed
Given the user is on the Orbit screen,
when the user swipes right (finger moves from left to right) across the screen
with sufficient horizontal distance,
then the Feed screen slides in from the left and becomes the active screen.

**TC-30-A03** — Insufficient swipe distance snaps back
Given the user is on the Feed screen,
when the user swipes left but releases before reaching the threshold distance,
then the screen snaps back to the Feed position (no navigation occurs).

**TC-30-A04** — Swipe velocity triggers navigation even with less distance
Given the user is on the Feed screen,
when the user performs a quick/fast left-swipe flick (high velocity) even with
less than the threshold distance,
then the navigation to Orbit occurs (velocity-based trigger).

### Group B: Nav Bar State Synchronization

**TC-30-B01** — Nav bar "Orbit" becomes active after swiping left from Feed
Given the user swipes left on Feed to reach Orbit,
when the Orbit screen finishes transitioning in,
then the bottom nav bar shows "Orbit" as the active tab (gradient pill on
Orbit button, dimmed Feed button).

**TC-30-B02** — Nav bar "Feed" becomes active after swiping right from Orbit
Given the user swipes right on Orbit to return to Feed,
when the Feed screen finishes transitioning in,
then the bottom nav bar shows "Feed" as the active tab.

**TC-30-B03** — Swipe and button navigation are interchangeable
Given the user swipes left to go to Orbit,
when the user taps the "Feed" button in the nav bar,
then the user returns to Feed. Then swiping left again returns to Orbit.
All combinations of swipe and tap work consistently.

### Group C: Gesture Conflict — Swipe-to-Reply on Feed

**TC-30-C01** — Right-swiping on a received message still triggers reply
Given the user is on the Feed screen with an open card showing received messages,
when the user right-swipes directly on a received message bubble,
then the swipe-to-reply (quote) gesture fires at the 36px threshold — **not**
screen-level Orbit→Feed navigation.

**TC-30-C02** — Right-swipe on empty Feed area does NOT trigger reply
Given the user is on the Feed screen,
when the user right-swipes on an area with no message bubbles (e.g., feed
header, empty space, collapsed card),
then no quote reply is triggered (there is no message to reply to), and any
screen-level behavior applies normally.

**TC-30-C03** — Left-swipe on Feed navigates to Orbit even with open cards
Given the user has expanded feed cards with message bubbles visible,
when the user left-swipes on the feed (not on a specific message),
then screen-level navigation to Orbit occurs (left-swipe has no quote reply
conflict since quote reply is right-swipe only).

### Group D: Gesture Conflict — Swipeable Friend Rows on Orbit

**TC-30-D01** — Left-swiping on a friend row reveals action buttons
Given the user is on the Orbit screen,
when the user left-swipes directly on a friend row,
then the swipeable row reveals its action buttons (Archive, Delete, etc.) —
**not** screen-level navigation to Feed.

**TC-30-D02** — Right-swipe on Orbit navigates to Feed even with friend rows
Given the user is on the Orbit screen with friend rows visible,
when the user right-swipes on an area between rows, on a header, or on a row
that has no right-swipe gesture,
then screen-level navigation to Feed occurs.

**TC-30-D03** — Closing an open friend row does not trigger screen navigation
Given a friend row is swiped open showing action buttons,
when the user right-swipes to close the row (snap it back),
then the row closes but screen-level navigation to Feed does NOT trigger
(the row gesture consumes the swipe).

### Group E: Vertical Scroll Interaction

**TC-30-E01** — Vertical scroll on Feed is not affected by horizontal swipe
Given the user is on the Feed screen with a long list of cards,
when the user scrolls vertically (up or down),
then the feed scrolls normally with no horizontal interference or jitter.

**TC-30-E02** — Diagonal gesture resolves to scroll, not swipe
Given the user is on the Feed screen,
when the user drags at approximately 45 degrees (equal vertical and horizontal
movement),
then the gesture resolves as a vertical scroll (vertical takes priority for
ambiguous gestures), and no screen navigation occurs.

**TC-30-E03** — Vertical scroll on Orbit is not affected
Given the user is on the Orbit screen with a long friends list,
when the user scrolls vertically,
then the list scrolls normally with no horizontal interference.

### Group F: Transition Animation

**TC-30-F01** — Swipe-driven transition follows the finger
Given the user begins swiping left on Feed,
when the user drags their finger,
then the Feed screen slides left and the Orbit screen slides in from the right,
tracking the finger position (interactive drag, not a fixed animation).

**TC-30-F02** — Releasing mid-swipe either completes or reverts smoothly
Given the user has swiped left past the threshold,
when the user lifts their finger,
then the transition completes with a smooth animation to the Orbit screen
(no jump or stutter).

**TC-30-F03** — Releasing mid-swipe before threshold reverts smoothly
Given the user has swiped left but NOT past the threshold,
when the user lifts their finger,
then the screens smoothly animate back to their original positions.

### Group G: State Preservation

**TC-30-G01** — Feed scroll position preserved after swiping to Orbit and back
Given the user has scrolled down in the Feed to card #15,
when the user swipes left to Orbit, then swipes right back to Feed,
then the Feed is still scrolled to approximately card #15.

**TC-30-G02** — Orbit state preserved after swiping to Feed and back
Given the user is on Orbit's "Groups" sub-tab scrolled to group #8,
when the user swipes right to Feed, then swipes left back to Orbit,
then Orbit shows the "Groups" sub-tab at approximately the same scroll position.

**TC-30-G03** — Keyboard dismisses on swipe navigation
Given the user has the keyboard open on the Feed screen (e.g., reply input),
when the user swipes left to Orbit,
then the keyboard dismisses during or before the transition.

### Group H: Edge Cases

**TC-30-H01** — Swiping left on Orbit does nothing (no screen to the right)
Given the user is on the Orbit screen,
when the user swipes left,
then nothing happens (Orbit is the rightmost screen; there is no screen
to navigate to).

**TC-30-H02** — Swiping right on Feed does nothing (no screen to the left)
Given the user is on the Feed screen,
when the user swipes right,
then nothing happens (Feed is the leftmost screen; there is no screen
to navigate to). Note: right-swipe on message bubbles still triggers reply.

**TC-30-H03** — Rapid swipe back-and-forth
Given the user swipes left to Orbit,
when the user immediately swipes right before the transition completes,
then the app handles the interruption gracefully — either completing the
first transition before accepting the second, or smoothly reversing.

**TC-30-H04** — Swipe during app state transitions
Given a new message notification arrives while the user is mid-swipe,
when the UI updates to show a new badge,
then the swipe transition continues without interruption or crash.

### Group I: Regression

**TC-30-I01** — Tap navigation still works after swipe feature is added
Given the user is on the Feed screen,
when the user taps the "Orbit" button in the nav bar,
then navigation to Orbit occurs normally (tap-based navigation unchanged).

**TC-30-I02** — Orbit close button still works
Given the user is on the Orbit screen,
when the user taps the X close button (if retained),
then the user returns to Feed normally.

**TC-30-I03** — Feed card interactions are not affected
Given the user is on the Feed screen,
when the user taps a feed card to expand or open a conversation,
then the card interaction works normally.

**TC-30-I04** — Orbit row tapping still works
Given the user is on the Orbit screen,
when the user taps a friend row to open a conversation,
then the conversation opens normally.
