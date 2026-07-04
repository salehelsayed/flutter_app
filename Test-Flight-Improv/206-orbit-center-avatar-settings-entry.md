# 206 - Settings Entry Point Migration: Orbit Center Avatar Opens Settings, Feed Header Avatar Removed

**Feature Improvement**

User request (2026-07-04): on the Orbit screen, tapping the main user's profile picture
in the middle of the circle does nothing today. The settings screen — currently opened
from the Feed screen's top-right avatar — must instead open from that Orbit center
avatar. The Feed screen's top-right avatar is removed entirely; the Orbit center avatar
becomes the only avatar-based settings entry point.

---

## 2. Problem Statement

Two related deficiencies, one migration:

1. **Dead tap target on the Orbit screen.** The current user's profile picture renders
   as a static 48×48 avatar at the exact center of the orbit rings
   (`lib/features/orbit/presentation/widgets/orbital_visualization.dart:171-180`). It
   has no gesture handler and no button semantics. A tap on it falls through to the
   full-surface background `GestureDetector` behind it
   (`lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart:573-581`),
   whose idle-state tap handler is a no-op. To a user, the most prominent, most
   personal element on the Orbit screen — their own face in the middle of their social
   circle — is inert. Every *other* avatar on the rings is tappable (opens the 1:1
   chat or group), which makes the center avatar's inertness feel broken rather than
   intentional.

2. **The settings entry point lives on the screen being de-emphasized.** Today the
   only avatar-based path to Settings is the Feed header's top-right avatar
   (`lib/features/feed/presentation/widgets/feed_header.dart:51-58` →
   `feed_wired._onAvatarTap`, `lib/features/feed/presentation/screens/feed_wired.dart:1869-1898`).
   The product direction is to consolidate self-representation on the Orbit screen:
   the Feed header avatar is redundant chrome and must be removed.

**Who is affected:** all users, both platforms (iOS + Android). The behavior is pure
Flutter UI/navigation; no Go, bridge, or relay code participates.

**Conditions:** always — the center avatar renders whenever an identity exists
(`userPeerId != null`), and it never responds to taps.

## 3. Impact Analysis

| Aspect | Assessment |
|---|---|
| Severity | UX gap / product-direction migration. Nothing crashes; Settings remains reachable from Feed today and from the Posts screen. |
| Frequency | Every session — the center avatar is permanently visible on the Orbit tab and permanently inert. |
| User-visible consequence (before) | Tapping own avatar on Orbit does nothing (violates learned expectation set by the tappable ring avatars). Settings discoverable only via Feed header / Posts screen. |
| User-visible consequence (after, if done wrong) | If the Feed avatar is removed **before** the Orbit entry works, users lose their primary Settings path (Posts-screen entry is secondary and not broadly discovered). The two changes must land as one behavioral unit. |
| Workarounds | Settings via Feed avatar (until removed) or via Posts screen. |
| Regression surface | Orbit gesture arena (background tap / long-press-to-edit / double-tap-labels), doc-202 repaint isolation invariants, Feed header layout, three existing test files that assert the old behaviors (see §4). |

A specific migration hazard: the Feed's settings-return refresh. Today, Feed reloads
identity, background, and media-quality preferences in the `.then` continuation of the
settings route push (`feed_wired.dart:1892-1897`). CORRECTED (verify→refute pass): the
**background** preference does NOT depend on that continuation — `SettingsWired`
pushes it into the shared `AppShellController` on save (`settings_wired.dart:230`),
and `FeedWired` listens and rebuilds (`feed_wired.dart:387`, `:2508-2521`), reading it
live at build (`:2706`). But **identity/username/avatar bytes and image/video quality
preferences have NO passive channel** — they are loaded only at `initState` and in
that `.then` continuation (`feed_wired.dart:425-466`). If Settings is opened from
Orbit, those reloads never run — the changes silently stop propagating to Feed (and
the Orbit center avatar itself goes stale on a photo *change*, since `UserAvatar`'s
bytes-first path bypasses the avatar-path notifier, `user_avatar.dart:122-136`). The
test cases in §6 pin this behavior regardless of entry point.

A second hazard: **functional parity of the Settings screen itself.** `SettingsWired`
takes 13 dependencies (`lib/features/settings/presentation/screens/settings_wired.dart:59-76`).
`OrbitWired` already holds most of them, but today has **no**
`NearbyLocationService` field at all (grep: zero hits in `orbit_wired.dart`), and its
`appShellController` / `postsPrivacySettingsRepository` fields are nullable
(`orbit_wired.dart:137,148`) while `SettingsWired` requires them non-null
(`settings_wired.dart:67-68`). A Settings screen opened from Orbit that is missing
these would render but be *functionally degraded* (e.g. the posts-nearby interactive
refresh, `settings_wired.dart:295`, would be inert). §6 Group E pins parity.

## 4. Current State

### 4.1 Settings opening today (end-to-end)

`FeedScreen` renders `FeedHeader` (`lib/features/feed/presentation/screens/feed_screen.dart:211-217`,
plumbing fields `userAvatarBytes`:33, `onAvatarTap`:37) → user taps the 42px
`UserAvatar` wrapped in a bare `GestureDetector` (`feed_header.dart:51-58`) → fires
`onAvatarTap` = `feed_wired._onAvatarTap` (wired at `feed_wired.dart:2694`, defined at
`feed_wired.dart:1869-1898`) → clears composer focus, then
`Navigator.of(context).push(buildSettingsSlideUpRoute(builder: (_) => SettingsWired(…13 deps…)))`
→ on pop, `.then` reloads identity, background preference, media-quality and
video-quality preferences so changes made in Settings are reflected on Feed.

### 4.2 Key files and facts

| File | Lines | Fact |
|---|---|---|
| `lib/features/feed/presentation/widgets/feed_header.dart` | 51-58 | The top-right avatar: `GestureDetector(onTap: onAvatarTap, child: UserAvatar(size: 42))`. No badge, unread count, or presence dot of its own. No `Semantics` label. |
| `lib/features/feed/presentation/widgets/feed_header.dart` | 44-50 | Sibling `ConnectionStatusIndicator(p2pService)` + 8px spacer sit to the avatar's left in the same right-side `Row`. Separate widget; not part of the avatar tap. |
| `lib/features/feed/presentation/widgets/feed_header.dart` | 12-16, 21-25 | `avatarBytes`, `peerId`, `onAvatarTap` constructor fields exist solely to serve the avatar. |
| `lib/features/feed/presentation/screens/feed_wired.dart` | 1869-1898 | `_onAvatarTap()` — the canonical "open Settings" call: `buildSettingsSlideUpRoute` + `SettingsWired` with 13 deps + `.then` preference-reload continuation. |
| `lib/features/feed/presentation/screens/feed_wired.dart` | 430-437 | Feed avatar bytes come from `IdentityAvatarResolver.resolve(identity)`. |
| `lib/features/orbit/presentation/widgets/orbital_visualization.dart` | 171-180 | Center avatar: `if (userPeerId != null) Positioned(left: cx-24, top: cy-24, child: UserAvatar(size: 48))`. **No GestureDetector, no Semantics, no onTap.** |
| `lib/features/orbit/presentation/widgets/orbital_visualization.dart` | 150-170, 194-217 | Doc-202 repaint isolation: blurred ring painter inside `RepaintBoundary('orbit-ring-boundary')`; each ring node's raster inside its own `RepaintBoundary` inside its dim `Opacity`. The center avatar is a plain `Positioned` sibling **outside** these boundaries. |
| `lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart` | 573-581 | Full-surface background `GestureDetector('orbit-inner-circle-background')`, `HitTestBehavior.opaque`, owning `onTap: _onBackgroundTap`, `onLongPressStart: _enterEdit` (when not editing), `onDoubleTap: _toggleLabels`. CORRECTED: it receives only taps on empty space OUTSIDE the hit-opaque canvas — center-avatar taps never reach it (see §4.3). |
| `lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart` | 318-326 | `_onBackgroundTap`: exits edit mode / closes the find overlay; a plain tap on the idle surface does nothing. |
| `lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart` | 589-591 | `userPeerId` / `userAvatarBytes` passed into `OrbitalVisualization`. |
| `lib/features/orbit/presentation/screens/orbit_screen.dart` | 77-78, 744-746 | `userPeerId` / `userAvatarBytes` fields threaded into `InnerCircleInteractiveSurface`. Existing callback-threading precedent: `onFriendTap` (:200), `onGroupTap` (:218), `onFriendAvatarTap` (:204, :336). |
| `lib/features/orbit/presentation/screens/orbit_wired.dart` | 594-599 | Orbit avatar bytes come from the **same** `IdentityAvatarResolver.resolve(identity)` as Feed — no data divergence. |
| `lib/features/orbit/presentation/screens/orbit_wired.dart` | 101-154 | Holds most `SettingsWired` deps already; `appShellController` (:137) and `postsPrivacySettingsRepository` (:148) are **nullable**; **no `NearbyLocationService` field exists**. |
| `lib/features/settings/presentation/screens/settings_wired.dart` | 42-76 | `SettingsWired` deps: 8 required (incl. non-null `appShellController`, `postsPrivacySettingsRepository`), 5+ optional (incl. `nearbyLocationService`, whose absence makes the posts-nearby interactive refresh at :295 inert). |
| `lib/features/settings/presentation/navigation/settings_route_transition.dart` | 7 | `buildSettingsSlideUpRoute<T>` — 420ms easeOutCubic slide-up. Shared by Feed (:1873), Posts (`posts_wired.dart:539`), and Settings→move-account (`settings_wired.dart:507`). |
| `lib/main.dart` / `feed_wired.dart` | 4257 / 2542 | The **two** `OrbitWired` construction sites — both must supply anything new the Orbit-side Settings entry needs. |

### 4.3 Constraints inventory

- **Hit target:** the center avatar is already 48×48 (`orbital_visualization.dart:178`),
  meeting the 48px minimum the orbit code enforces for satellite avatars
  (`orbital_avatar.dart:105-107`, `_tapTargetSize` in `orbital_visualization.dart:387`).
- **Hit-testing reality (CORRECTED 2026-07-04 by the verify→refute pass — the
  original "gesture arena fall-through" model was wrong):** the entire 320px canvas is
  already **hit-opaque**. The `Positioned.fill` ring `CustomPaint` uses
  `OrbitalRingPainter` with no `hitTest` override (`orbital_ring_painter.dart:35`;
  `RenderCustomPaint.hitTestSelf` defaults to true), and `UserAvatar` renders
  hit-positive `Container`/`BoxDecoration`/`Image` render objects
  (`user_avatar.dart:186-220`). `RenderStack` hit-testing stops at the first topmost
  hit child, so pointers over the canvas — including the center avatar — **never reach
  the background detector** (`inner_circle_interactive_surface.dart:573-581`). The
  repo's own tests encode this: `bgPoint` deliberately taps left of the circle column
  "so the sibling background gesture layer receives it"
  (`orbit_sculpt_summon_wired_test.dart:128-135`). Consequences: today, a tap on the
  center avatar does nothing **in any mode** (it does NOT exit edit, does NOT close
  find), a long-press on the center does NOT enter edit mode, and a double-tap on the
  center does NOT toggle labels. Any modal-dismiss or edit-entry behavior on the
  center avatar is therefore **new, deliberate behavior**, not preservation. The only
  recognizer that genuinely competes with a new center tap handler is the ancestor
  scrollable's vertical-drag recognizer, which loses to a stationary tap.
- **Perf isolation (doc 202, INV-202-1):** ring painter and per-node rasters are
  repaint-isolated. The center avatar sits outside those boundaries; changes around it
  must not add rebuild/repaint paths into the isolated rasters.
- **Accessibility:** neither today's Feed header avatar nor the Orbit center avatar has
  `Semantics(button: true, label: …)`. Ring satellite avatars DO
  (`orbital_avatar.dart:157-164`; labels built at `orbital_visualization.dart:293-299`).
- **Reduce-motion:** `OrbitalVisualization` gates entrance animation on
  `disableAnimations`/`accessibleNavigation` (:109-111); the center avatar itself has
  no animation.

### 4.4 Other Settings entry points (unchanged inventory)

- Posts screen: `lib/features/posts/presentation/screens/posts_wired.dart:539-540`
  pushes `SettingsWired` via the same slide-up route.
- Settings self-pushes the move-account route (`settings_wired.dart:507`).
- No named routes / deep links / go_router in this flow — all imperative `Navigator.push`.
- Integration smoke `integration_test/settings_background_choice_smoke_test.dart` opens
  Settings via a test-only `open-settings-smoke` button, not the Feed avatar.

### 4.5 Existing tests touching this area

| Test | Current assertion | Fate under this change |
|---|---|---|
| `test/features/feed/presentation/screens/feed_wired_test.dart:409-441` `'refreshes background preference after returning from Settings'` | Taps `find.byType(UserAvatar).first` in the Feed, expects the Settings title, flips background, pops, asserts Feed's `CosmicBackground` refreshed. | **Breaks** — the Feed avatar it taps will no longer exist. The behavior it pins (settings-return background refresh) must survive via the new entry point. |
| `test/features/orbit/presentation/widgets/orbital_visualization_test.dart:192-197` `'renders center UserAvatar'` | Center `UserAvatar` present in an empty orbit. | Must stay green. |
| `test/features/orbit/presentation/widgets/orbital_visualization_test.dart:319-347` `TC-198-67` | Taps the center avatar (`warnIfMissed: false` — no hit target exists) and asserts `friendTaps == 0 && badgeTaps == 1`. | CORRECTED: **survives unmodified** under a nullable-callback implementation (the test passes no self-tap callback, so no detector mounts and the assertions hold). It remains the live lock that the center never opens a chat. |
| `test/features/orbit/presentation/widgets/orbital_visualization_test.dart:405-424` `TC-194-01/34` | Asserts only `UnreadOrbitIndicator findsOneWidget`; "plain UserAvatar" is comment-only. | CORRECTED: **survives unmodified** (no inertness assertion). Comment wording may be refreshed, not required. |
| `test/features/orbit/presentation/widgets/orbital_visualization_test.dart:464-486` `TC-194-26` | REFUTE-PASS DISCOVERY: unscoped `find.byType(GestureDetector)` fed to `tester.getSize` — requires exactly ONE detector in a 1-friend tree. | **Breaks if the center detector is mounted unconditionally.** Survives if the detector mounts only when the new callback is non-null (the `OrbitalAvatar` precedent, `orbital_avatar.dart:155-165`). This is a hard implementation constraint. |
| `orbit_sculpt_summon_wired_test.dart:234, 809-824` + `orbital_arcs_test.dart:123` | Geometry locks: `getCenter/getRect(find.byType(UserAvatar).first)` position anchors. | Survive unless the wrapper shifts the center avatar's painted position — the wrapper must not alter `Positioned(left: cx-24, top: cy-24)` or the 48px box. |
| Feed letter-card avatar tests (`feed_swipe_test.dart:495`, `letter_card_*` tests) | Tap avatars **inside cards**, scoped via `find.descendant(of: LetterCardSystem…)`. | Unaffected. |
| `test/features/settings/...` (settings_wired_test, settings_screen_test, settings_wired_posts_nearby_test) | Construct Settings directly. | Unaffected. |

**Coverage gap:** no test anywhere asserts that the Orbit center avatar opens Settings
(the behavior does not exist yet). That is the new RED surface.

### 4.6 Known issues / TODOs

None. No `TODO`/`FIXME`/`HACK` markers in `orbital_visualization.dart`,
`feed_header.dart`, or `inner_circle_interactive_surface.dart`; no known failing gates
in this area.

## 5. Scope Clarification

| Area | Status | Notes |
|---|---|---|
| Orbit center avatar tap → opens Settings | **In scope** | The core new behavior. |
| Feed header top-right avatar (the `GestureDetector` + `UserAvatar` at `feed_header.dart:51-58`) | **In scope — removed** | Including any plumbing that exists solely to serve it. |
| Settings-return preference refresh (background / identity / media quality reflected after Settings pop) | **In scope** | Must keep working when Settings is opened from Orbit; currently rides Feed's `.then` continuation. |
| Functional parity of Settings opened from Orbit (incl. posts-nearby refresh) | **In scope** | Settings must not be silently degraded relative to today's Feed-opened Settings. |
| Migration of the three test files in §4.5 | **In scope** | Behaviors they pin must survive at the new entry point. |
| `ConnectionStatusIndicator` in the Feed header (`feed_header.dart:47-49`) | **Out of scope — unchanged** | User asked to remove the avatar only. The connection dot is a separate widget and stays. |
| Username display/editing in the Feed header (`EditableUsernameWidget`) | **Out of scope — unchanged** | |
| Settings screen content, layout, and its own flows (recovery phrase, move-account, posts-nearby UI) | **Out of scope — unchanged** | Only the entry point moves. |
| Posts-screen Settings entry (`posts_wired.dart:539`) | **Out of scope — unchanged** | Second entry point stays. |
| Orbit ring/arc satellite tap behavior (friend/group open, badge tap, edit handles, find UX) | **Out of scope — unchanged** | Regression-guarded in §6. |
| Orbit surface gestures: long-press-to-edit, double-tap-labels, background-tap-to-dismiss | **Out of scope — behavior preserved** | The new center tap must coexist without changing these (see TC-206-08..12 for the pinned expectations). |
| Doc-202 repaint-isolation invariants (INV-202-1) | **Out of scope — must not regress** | |
| Go / bridge / relay code | **Out of scope** | Pure Flutter UI/navigation change; confirmed nothing in `go-mknoon/` participates. |

**Deliberate spec decision — modal-state precedence:** while the orbit surface is in a
transient mode (edit/sculpt mode active, or the find overlay open), a tap on the
center avatar must dismiss the mode and must NOT open Settings. Settings opens only
from the idle surface. CORRECTED framing: this is **new, deliberate behavior** (today
a center tap does nothing even in edit/find mode — see §4.3), chosen for consistency
with the existing node-tap tap-away precedent (`_onNodeFriendTap`,
`inner_circle_interactive_surface.dart:330-336`, TC-198-19: mid-edit node taps end
edit and do not navigate). Rationale: least-surprise; a user tapping to escape edit
mode must not be teleported into Settings.

## 6. Test Cases

### Group A — Orbit center avatar opens Settings (happy path)

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-206-01 | Identity loaded (center avatar visible), orbit surface idle. Tap the center avatar (48×48 at canvas center). | The Settings screen opens (localized title "Settings" visible) via the standard slide-up transition. No chat, group, or other screen opens. |
| TC-206-02 | After TC-206-01, inspect the opened Settings screen. | It is the full Settings screen: profile section (username + avatar), peer ID, posts privacy/nearby section, move-account entry, recovery-phrase card — identical content to Settings as opened from the Posts screen. |
| TC-206-03 | From Settings opened via the center avatar, navigate back (chevron / system back). | Returns to the Orbit screen exactly as left: same tab, same ring layout, find overlay closed, not in edit mode. No full entrance-animation replay of the ring nodes. |
| TC-206-04 | Current user has no profile photo (`avatarBytes` null → placeholder rendering). Tap the center avatar. | Settings opens. The tap target is the avatar widget, not the presence of image bytes. |
| TC-206-05 | Pre-identity state: `userPeerId` is null, so no center avatar renders. Tap the canvas center. | No crash, no route pushed; the tap falls through to the background handler (idle no-op), as today. |
| TC-206-06 | Rapidly tap the center avatar twice (double-tap cadence) and also 5 taps in quick succession. | At most one Settings route is pushed; after popping once, the user is back on Orbit (no stacked Settings screens). |

### Group B — Gesture-arena coexistence on the Orbit surface

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-206-07 | Long-press the center avatar on the idle surface. | Edit (sculpt) mode is entered. RE-SCOPED (verify→refute): today a center long-press does NOTHING (the canvas is hit-opaque; the background's long-press recognizer never receives center pointers) — this is a NEW behavior added for surface-wide sculpt-entry uniformity, and it must respect the existing edit gate (no re-entry while already editing). Long-press on empty space outside the canvas still enters edit as today (preserved). |
| TC-206-08 | While edit (sculpt) mode is active, tap the center avatar. | Settings does NOT open. Edit mode exits — NEW deliberate behavior matching the node-tap tap-away precedent (TC-198-19); today a mid-edit center tap does nothing at all. |
| TC-206-09 | While the find overlay/pill is open, tap the center avatar. | Settings does NOT open. The find overlay is dismissed — NEW deliberate behavior matching the background-tap dismissal semantics (today a center tap does not close find). A subsequent tap on the now-idle center avatar DOES open Settings. |
| TC-206-10 | Tap a ring-node satellite avatar (friend) and a merged group node. | The 1:1 conversation / group opens as today. The center tap handler intercepts nothing outside its own 48×48 bounds. |
| TC-206-11 | Double-tap the background away from center. | Labels toggle as today (no Settings push, no label regression). |
| TC-206-12 | Start dragging an edit handle, and mid-drag the finger crosses the canvas center; release. | No Settings route is pushed during or after the drag; the drag completes normally. |

### Group C — Feed header avatar removal

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-206-13 | Open the Feed screen with an identity that has a profile photo. | The header shows NO user avatar in the top-right. The username and the connection status indicator still render. |
| TC-206-14 | Probe the Feed header for any tap target that opens Settings. | None exists: no tap anywhere in the Feed header pushes the Settings route. |
| TC-206-15 | Edit the username from the Feed header (existing `EditableUsernameWidget` flow). | Username editing works exactly as before the avatar removal. |
| TC-206-16 | Render the Feed header at a narrow phone width (e.g. 320 logical px) with a long username. | No overflow errors, no orphaned gap where the avatar used to be; the header row lays out cleanly. |

### Group D — Settings-return state refresh (entry-point-independent)

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-206-17 | Open Settings from the Orbit center avatar, change the cosmic background choice, navigate back, switch to the Feed tab. | The Feed shows the NEW background without app restart. (CORRECTED: this already propagates via the shared `AppShellController` — `settings_wired.dart:230` → `feed_wired.dart:2508-2521` — provided Settings receives the SHARED controller instance; the test pins that the Orbit-opened Settings gets that shared instance, not a fallback.) |
| TC-206-18 | Open Settings from the Orbit center avatar, change the profile photo, navigate back to Orbit. | The Orbit center avatar shows the NEW photo without app restart. |
| TC-206-19 | Open Settings from the Orbit center avatar, change the username, navigate back; visit the Feed tab. | The Feed header shows the NEW username. |
| TC-206-20 | Open Settings from the Orbit center avatar, change the media-quality (and video-quality) preference, navigate back. | The next media send honors the new preference (the preference reload that Feed's continuation performed still happens). |

### Group E — Functional parity and other entry points

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-206-21 | Open Settings from the Posts screen entry. | Unchanged: Settings opens exactly as today. |
| TC-206-22 | Open Settings from the Orbit center avatar; exercise the posts-nearby interactive refresh in the posts privacy section. | The refresh is functional — NOT silently inert. Settings opened from Orbit must be functionally equivalent to Settings opened from the Feed avatar today (which received a live `NearbyLocationService`). |
| TC-206-23 | Open Settings from the Orbit center avatar; enter the move-account flow; back out. | Move-account is reachable and returns to Settings, then back to Orbit. |
| TC-206-24 | Open Settings from the Orbit center avatar on the `main.dart` construction path AND on the `feed_wired.dart` embedded-tab construction path (both `OrbitWired` call sites). | Both paths open a fully functional Settings screen (no null-dependency crash, no degraded sections on either path). |

### Group F — Accessibility and ergonomics

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-206-25 | Inspect the center avatar with the semantics tree / a screen reader. | It exposes button semantics with a meaningful settings-related label (parity with ring satellite avatars, which expose `button: true` + a label). |
| TC-206-26 | Measure the center avatar's effective tap target. | ≥ 48×48 logical px. |
| TC-206-27 | Enable reduce-motion (`disableAnimations`) and tap the center avatar; then return. | Settings opens and returns without animation-dependent breakage; ring entrance does not replay on return; no reduce-motion regression on the orbit surface. |

### Group G — Lifecycle and state transitions

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-206-28 | With Settings open (entered from Orbit), background the app, then resume. | Settings is still displayed; back navigation still returns to the Orbit screen in its pre-Settings state. |
| TC-206-29 | Open Settings from Orbit, pop back, immediately tap the center avatar again. | Settings opens again cleanly (no stale state, no dead second tap). |
| TC-206-30 | Doc-202 invariant guard: with the new tap wiring in place, trigger a drag/dim/pulse cycle on the orbit surface. | The repaint-isolation invariants from doc 202 still hold (ring raster and per-node rasters are not invalidated by the center avatar's presence or its tap handling). |

---

*Evidence gathered 2026-07-04 (graphify arch graph + source verification). All file:line
references verified against the working tree on branch `new-orbit`.*
