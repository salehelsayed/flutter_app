# 28 - Notification Badge on Orbit Nav Button for Pending Introductions

**New Feature**

---

## 1. Problem Statement

When a user receives an introduction notification, there is no visual indicator
on the bottom navigation bar to tell them they have pending introductions
waiting in Orbit. The user must tap into the Orbit screen to discover new
intros.

**Current behavior:**

1. User receives an introduction via P2P. `IntroductionListener` emits on
   `introReceivedStream` and fires a local notification ("New Introduction").
2. If the user is on the Feed screen, the bottom nav bar shows "Feed" (with an
   unread message badge) and "Orbit" (no badge, no indicator).
3. The user has no way to know from the Feed screen that there are pending
   introductions waiting in Orbit.
4. The Orbit button in the nav bar never shows any badge or dot.

**What is missing:**

- No badge/dot indicator on the "Orbit" nav button when pending introductions
  exist.
- `FeedWired` subscribes to `introReceivedStream` but the listener is a no-op
  (`listen((_) {})` at feed_wired.dart:1453).
- `FeedNavigationBar` only passes `feedBadgeCount` to the Feed button (line 57);
  the Orbit button receives no badge count (line 60–65).
- The `NavBarButton` widget already supports `badgeCount` (line 11, default 0)
  but it is never provided for the Orbit button.

**Who is affected:** All users who receive introductions while viewing the Feed
screen.

---

## 2. Impact Analysis

| Dimension | Assessment |
|-----------|-----------|
| Severity | Moderate — intros are missed or discovered late |
| Frequency | Every time a new introduction is received while on the Feed screen |
| User consequence | User does not know to check Orbit for new intros; intros may expire (30-day limit) |
| Workaround | User must periodically open Orbit to check, or notice the system notification |
| Platform scope | iOS and Android (Flutter) |

---

## 3. Current State

### 3.1 Badge System (Already Working for Feed)

| File | Purpose | Key Lines |
|------|---------|-----------|
| `lib/features/feed/presentation/widgets/nav_bar_button.dart` | Button with badge support | Lines 11, 82–87: `badgeCount` prop; renders `_NavBadge` if > 0 |
| `lib/features/feed/presentation/widgets/nav_bar_button.dart` | `_NavBadge` widget | Lines 93–129: red gradient pill, "99+" cap, shadow |
| `lib/features/feed/presentation/widgets/nav_bar_theme.dart` | Badge design tokens | Lines 60–64: `badgeGradientColors` (red `#FF3B30` → `#E0342A`), `badgeShadowColor` |
| `lib/features/feed/presentation/widgets/feed_navigation_bar.dart` | Nav bar assembly | Line 57: `badgeCount: feedBadgeCount` for Feed button; Line 60–65: Orbit button has no `badgeCount` |

**Feed badge wiring** (feed_wired.dart):
- `_totalUnreadCountNotifier` (`ValueNotifier<int>`, line 166) tracks unread messages.
- `_loadTotalUnreadCount()` queries `messageRepository.getTotalUnreadCountExcludingArchived()`.
- `_buildNavigationBar()` (feed_screen.dart:228–246) uses `ValueListenableBuilder`
  to reactively pass unread count to `FeedNavigationBar(feedBadgeCount: unreadCount)`.

**Orbit button currently:** `NavBarButton(label: l10n.nav_orbit, svgAsset: 'assets/icons/nav_orbit.svg', isActive: activeTab == 'orbit', onTap: ...)` — no `badgeCount` parameter passed (defaults to 0).

### 3.2 Introduction Listener & Streams

| File | Purpose | Key Lines |
|------|---------|-----------|
| `lib/features/introduction/application/introduction_listener.dart` | P2P intro message handler | Lines 21–303 |

- `introReceivedStream` — emits `IntroductionModel` when a new intro arrives (line 224).
- `introStatusChangedStream` — emits when an intro is accepted/passed (lines 230–240).
- Fires local notification on receipt: `showNotification(title: 'New Introduction', payload: 'intros')` (lines 255–259).

### 3.3 FeedWired Introduction Subscriptions

| File | Key Lines |
|------|-----------|
| `lib/features/feed/presentation/screens/feed_wired.dart` | Lines 1449–1469 |

- `_introReceivedSubscription` — subscribed but **listener is empty no-op**: `listen((_) {})` (line 1453).
- `_introStatusSubscription` — only handles `mutualAccepted` to refresh a contact feed item (lines 1455–1468). Does not update any badge count.
- Both subscriptions are properly disposed (lines 2191–2192).
- `FeedWired` already has `widget.introductionRepository` and `widget.introductionListener` properties wired in.

### 3.4 Intro Count in Orbit (Separate, Not Shared)

| File | Key Lines |
|------|-----------|
| `lib/features/orbit/presentation/screens/orbit_wired.dart` | Line 186: `_introsCount`; Line 567–599: `_loadIntroductions()` |
| `lib/core/database/helpers/introductions_db_helpers.dart` | Lines 428–457: `dbCountPendingIntroductions()` |
| `lib/features/introduction/domain/repositories/introduction_repository.dart` | Line 52: `countPendingIntroductions(String peerId)` |

- `OrbitWired` independently loads and tracks `_introsCount` (line 186).
- `countPendingIntroductions()` exists in the repository interface (line 52)
  and returns `int` — the count of intros with `status = 'pending'`.
- This count is never queried from `FeedWired`.

### 3.5 Badge Visual Design

`_NavBadge` (nav_bar_button.dart:93–129):
- Red gradient pill (`#FF3B30` → `#E0342A`)
- Min width 18px, `horizontal: 5, vertical: 1` padding
- 10px border radius
- Text: 10px, weight 700, white, "99+" cap
- Positioned `top: -4, right: -2` relative to the button Stack

The user's request mentions a "small dot" — this may differ visually from the
existing numeric badge (a dot is typically a small circle with no number). The
current `_NavBadge` always shows a number. The spec captures both the
count-based badge (existing pattern) and the dot indicator (user's stated
preference) as behaviors to test.

---

## 4. Scope Clarification

| Area | Status | Notes |
|------|--------|-------|
| Badge/dot on Orbit nav button for pending intros | **In scope** | Core feature |
| Badge updates when new intro received | **In scope** | Real-time via `introReceivedStream` |
| Badge updates when intro accepted/passed/deleted | **In scope** | Count decreases on action |
| Badge clears when no pending intros remain | **In scope** | Badge/dot disappears at 0 |
| Initial badge load on app startup | **In scope** | Query pending count on `FeedWired` init |
| Badge visible from Feed screen | **In scope** | Primary use case |
| Badge visible from Orbit screen (if nav bar persists per Report 27) | **In scope** | Depends on Report 27 implementation |
| Feed unread message badge | **Unchanged** | Existing badge on Feed button stays |
| Intro notification (system notification) | **Unchanged** | Already fires; not related to nav badge |
| Badge on Orbit sub-tabs (Friends, Groups, Intros) | **Out of scope** | Only the bottom nav bar button |
| Badge styling (dot vs. count) | **In scope** | User asked for "small dot"; test both possibilities |

---

## 5. Test Cases

### Group A: Badge Appearance on New Introduction

**TC-28-A01** — Badge appears on Orbit button when a new intro is received
Given the user is on the Feed screen with no pending introductions,
when a new introduction arrives via P2P (introReceivedStream emits),
then a badge/dot indicator appears on the "Orbit" button in the bottom nav bar.

**TC-28-A02** — Badge appears on app startup with existing pending intros
Given the user has 3 pending introductions in the database,
when the user opens the app and lands on the Feed screen,
then the Orbit button shows a badge/dot indicator immediately (without needing
to receive a new intro first).

**TC-28-A03** — Badge does not appear when there are zero pending intros
Given the user has no pending introductions,
when the user is on the Feed screen,
then the Orbit button has no badge/dot indicator.

**TC-28-A04** — Badge appears after receiving multiple intros
Given the user has 0 pending intros,
when 3 new introductions arrive in sequence,
then the Orbit button shows a badge/dot after the first intro and continues to
show it after each subsequent intro.

### Group B: Badge Updates on Intro Status Changes

**TC-28-B01** — Badge clears after all pending intros are acted on
Given the user has 1 pending introduction and the Orbit badge/dot is showing,
when the user goes to Orbit, accepts (or passes) the intro, and returns to Feed,
then the Orbit button no longer shows a badge/dot.

**TC-28-B02** — Badge decreases but persists when some intros remain
Given the user has 3 pending introductions,
when the user accepts 1 intro,
then the badge/dot still appears on the Orbit button (2 pending remain).

**TC-28-B03** — Badge clears when the user deletes a pending intro (per Report 25)
Given the user has 1 pending introduction and the badge is showing,
when the user deletes the intro (swipe-to-delete per Report 25),
then the badge/dot disappears from the Orbit button.

**TC-28-B04** — Badge updates when an intro expires (30-day expiry)
Given the user has 1 pending introduction that is about to expire,
when the intro's 30-day expiry elapses and `expireOldIntroductions` runs,
then the badge/dot disappears (the intro is no longer pending).

### Group C: Badge Updates from Remote Status Changes

**TC-28-C01** — Badge updates when the other party accepts/passes
Given the user has 2 pending intros (one where user already accepted, waiting
for other party),
when the other party accepts (intro becomes mutualAccepted via
introStatusChangedStream),
then the badge count reflects only the remaining pending intros.

**TC-28-C02** — Badge updates in real-time without needing to visit Orbit
Given the user stays on the Feed screen with 2 pending intros,
when 1 intro's status changes to "passed" via remote notification,
then the badge updates to reflect 1 pending intro, all without leaving Feed.

### Group D: Badge and Feed Badge Coexistence

**TC-28-D01** — Both Feed and Orbit badges can show simultaneously
Given the user has 5 unread messages (Feed badge) and 2 pending intros (Orbit badge),
when the user is on the Feed screen,
then the Feed button shows a "5" badge AND the Orbit button shows a badge/dot,
both visible at the same time.

**TC-28-D02** — Feed badge and Orbit badge update independently
Given both badges are showing,
when the user reads all messages (Feed badge should clear),
then the Feed badge disappears but the Orbit badge remains (intros still pending).

**TC-28-D03** — Orbit badge does not affect Feed badge count
Given the user has 3 pending intros,
when the Orbit badge appears,
then the Feed button's badge count does not change (intro count is not
mixed into unread message count).

### Group E: Edge Cases

**TC-28-E01** — Badge appears for intro received while app is backgrounded
Given the app is backgrounded and a new introduction arrives,
when the user returns to the app on the Feed screen,
then the Orbit button shows a badge/dot for the new pending intro.

**TC-28-E02** — Badge correct after app restart
Given the user has 2 pending intros, closes the app completely, and reopens it,
when the Feed screen loads,
then the Orbit button shows a badge/dot (count loaded from DB on init).

**TC-28-E03** — Badge for intro where user is the introduced party (not recipient)
Given user-A introduces user-B to user-C,
when user-C is on the Feed screen and the intro arrives,
then user-C sees the badge/dot on Orbit (user is the introduced party, not
the recipient, but both roles receive pending intros).

**TC-28-E04** — Badge does not show for already-connected intros
Given user-A introduces user-B to user-C but user-B and user-C are already
friends,
when the intro arrives with status "alreadyConnected",
then no badge/dot appears on the Orbit button (already-connected intros are
not "pending").

**TC-28-E05** — Badge does not show for intros from blocked users
Given user-B has blocked user-A,
when user-A sends an introduction to user-B,
then no badge/dot appears (blocked intros are filtered by the listener).

### Group F: Regression

**TC-28-F01** — Feed unread badge still works correctly
Given the user has 10 unread messages and 0 pending intros,
when the user is on the Feed screen,
then the Feed button shows "10" badge and the Orbit button shows no badge.

**TC-28-F02** — Tapping Orbit button still navigates to Orbit
Given the Orbit button has a badge/dot showing,
when the user taps the Orbit button,
then navigation to the Orbit screen occurs normally (badge does not interfere
with tap target).

**TC-28-F03** — Intro accept/pass flow is unchanged
Given the user navigates to Orbit and sees a pending intro,
when the user accepts or passes on the intro,
then the accept/pass flow works as before (P2P notification sent, status
updated, UI refreshed).

**TC-28-F04** — System notification for new intros still fires
Given the user receives a new introduction,
when the intro is processed by `IntroductionListener`,
then the system notification "New Introduction" still fires in addition to the
badge appearing on the nav bar.
