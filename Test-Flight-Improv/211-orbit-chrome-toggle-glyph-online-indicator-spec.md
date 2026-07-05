# 211 - Orbit Chrome: View-Toggle Glyph per 207 Mockup + Online Indicator Migration from Feed

**Feature Improvement**

User request (2026-07-05), two Orbit-screen chrome changes:

1. The top-left button on the Orbit screen should look like the one in the 207 mockup (`Test-Flight-Improv/207-orbit-intros-under-orbit-mockups.html`): a circular dark button with a **bullet-list glyph** (user supplied a screenshot of exactly that button).
2. The **"Online" connection-status indicator** currently shown in the Feed screen header should be **migrated** to the Orbit screen, top-right, **next to the "+" button**.

---

## 2. Problem Statement

### 2.1 Top-left Orbit button does not match the ratified chrome vocabulary

The Orbit screen's top-left chrome element is the inner-circle ⇄ all-chats **view toggle** (`OrbitViewToggleButton`). Today it renders:

- `Icons.chat_bubble_outline` while on the inner-circle view ("show all chats"), and
- `Icons.blur_on` while on the all-chats view ("show inner circle"),

on a 40×40 circle filled with `readableColors.surfaceSubtle` and a 0.5 px `readableColors.border` hairline.

The 207 mockup — the design exhibit the user is standardizing on — renders the same top-left slot differently:

- **Glyph**: on the inner-circle view, a **bullet-list icon** (three horizontal lines, each preceded by a small filled dot; mockup `IC.list`, html L408); on the all-chats view, a **dashed-orbit icon** (filled center dot inside a dashed ring; mockup `IC.orbit`, html L409).
- **Container**: 40 px circle, **dark fill `rgba(16,18,24,0.75)`** with a 0.5 px `rgba(255,255,255,0.50)` hairline border (mockup `.chrome-btn`, html L107-108), glyph stroke near-white (`#F8FAFC`), 20 px glyph.

The current glyphs (`chat_bubble_outline` / `blur_on`) communicate the destination view poorly — a chat bubble reads as "open a chat", not "switch to the list view" — and the container styling no longer matches the chrome vocabulary the mockups have converged on.

**Behavioral scope note:** in the 207 mockup this slot participates in an intros-discoverability exploration, but the user's request here is strictly visual — the button remains the **view toggle** with unchanged tap behavior and unchanged semantics labels. The intros affordances of 207 (intro dock, ghost nodes, tray) are explicitly NOT part of this change.

### 2.2 The Online indicator lives on the wrong screen

`ConnectionStatusIndicator` — the pill that shows `Offline` / `Connecting` / `Online` / `Online.` / `Online ✦` from the node's `BadgeReadinessState` — renders **only** in the Feed header (`feed_header.dart:38-41`). Since 206 removed the Feed header avatar and 209 moved QR/Scan into Settings, the app's identity/connectivity "home" has been consolidating onto the Orbit screen (Orbit center avatar → Settings). The connectivity badge is the last piece of status chrome still stranded on Feed:

- A user on the Orbit screen (the app's primary navigation surface) has **no visibility** into whether the node is offline, connecting, or fully ready. They must switch tabs to Feed to check.
- The Orbit top-right currently hosts only the `ExpandableFab` "+" (new group / new announce). The mockup chrome places status/action chrome along the top edge; the top-right slot next to "+" is the requested destination.

"Migrate" means **move**: after this change the indicator appears on Orbit and **no longer** appears in the Feed header. (This deliberately revises 206's "preserve `ConnectionStatusIndicator` in Feed header" invariant — see Scope.)

### 2.3 Who is affected

All users, both platforms, every session — this is default-view chrome on the two primary screens.

---

## 3. Impact Analysis

| Aspect | Assessment |
|---|---|
| Severity | Cosmetic-to-UX. No functional loss today, but connectivity state is invisible from the primary (Orbit) screen, and the toggle glyph miscommunicates its action. |
| Frequency | Every session — both elements are always-on default-view chrome. |
| User-visible consequence | (1) Top-left button reads as "chat" rather than "list view"; visual style diverges from the ratified mockup vocabulary. (2) Users cannot see Offline/Connecting/Online from Orbit; during degraded connectivity they compose sends without any ambient warning until a snackbar fires. |
| Workarounds | Switch to the Feed tab to read the badge. None for the glyph mismatch. |
| Risk of the change | Chrome-inventory and header tests pin the current layout (see Current State §4.4); the Feed-header removal breaks a 206-era assertion by design. |

---

## 4. Current State

### 4.1 Orbit top-left button (change target #1)

| Item | Location | Detail |
|---|---|---|
| Widget | `lib/features/orbit/presentation/widgets/orbit_view_toggle_button.dart` | 40×40 circle; `ValueKey('orbit-view-toggle')` (L45) |
| Glyph selection | same file, L36 | `isInnerCircle ? Icons.chat_bubble_outline : Icons.blur_on` |
| Styling | L48-56 | fill `readableColors.surfaceSubtle`, 0.5 px `readableColors.border`, `Icon(size: 20, color: readableColors.textPrimary)` |
| Positioning | L38-40 | **physical** `Positioned(top: safeTop + 8, left: 16)` — deliberately not `PositionedDirectional` (L9-13 doc comment: top-right FAB does not mirror in RTL; physical positioning avoids collision) |
| Semantics | L33-35 | label flips `orbit_view_toggle_to_list` / `orbit_view_toggle_to_circle` (l10n: `app_en.arb:185-186`, plus `app_ar.arb` / `app_de.arb`; parity enforced by `test/l10n/orbit_strings_parity_test.dart`) |
| Mount point | `lib/features/orbit/presentation/screens/orbit_screen.dart:572-582` (Layer 1b) | mounted only when `onToggleView != null && !innerEditing` (hidden during inner-circle sculpt-edit) |
| Tap flow | `orbit_wired.dart:2021` (`_onToggleView`, wired :2468) | flips `viewMode` between `OrbitViewMode.innerCircle` and `OrbitViewMode.allChats`; pure local view switch — no navigation |

### 4.2 The 207 mockup's top-left button (the requested look)

| Item | Mockup location | Detail |
|---|---|---|
| Container | `.chrome-btn`, html L107-108 | 40×40, `border-radius: 50%`, `background: rgba(16,18,24,0.75)`, `border: 0.5px solid rgba(255,255,255,0.50)` |
| Glyph per view | `topChrome(view)`, html L462 | inner view → `IC.list`; all-chats view → `IC.orbit` |
| `IC.list` | html L408 | 20 px, three horizontal lines (x 8→20 at y 6/12/18) each with a filled `r=1` bullet at x=4; stroke `#F8FAFC`, width 1.8 — a bullet-list glyph |
| `IC.orbit` | html L409 | 20 px, filled center circle `r=3` inside a dashed ring `r=9` (`stroke-dasharray 4 3`), stroke width 1.6 |
| Stale content | html L463 | the mockup still renders the QR/Scan center pair that 209 retired — that part of the mockup is stale and must not be reintroduced |

### 4.3 Online indicator (change target #2)

| Item | Location | Detail |
|---|---|---|
| Widget | `lib/features/p2p/presentation/widgets/connection_status_indicator.dart` | Stateful pill: 8 px colored dot + label, padding 10×5, radius 16 |
| Data flow | L103-107, L110-140 | seeds from `p2pService.currentState.badgeReadinessState`, then subscribes to `p2pService.stateStream`; renders 5 states: `Offline` / `Connecting` / `Online` / `Online.` / `Online ✦` (Phase-6 `BadgeReadinessState` contract) |
| Interactivity | L179-182 | **passive** — `Semantics(container: true)` + `ExcludeSemantics`; no `onTap` |
| Telemetry | L124-134 | emits `TIME_TO_ONLINE_BADGE_WIDGET` flow event on first ready transition |
| Current host | `lib/features/feed/presentation/widgets/feed_header.dart:38-41` | `if (p2pService != null) ... ConnectionStatusIndicator(p2pService: p2pService!)`; the only remaining header chrome after 206 removed the avatar |
| Feed wiring | `lib/features/feed/presentation/screens/feed_screen.dart:207-211` | `FeedHeader(... p2pService: widget.p2pService)` |
| Signal availability on Orbit | `lib/features/orbit/presentation/screens/orbit_wired.dart:113, 174` | `OrbitWired` already owns the same `P2PService` instance; `OrbitScreen` itself currently takes **no** `p2pService` parameter |

### 4.4 Orbit top-right (insertion site) and adjacent constraints

| Item | Location | Detail |
|---|---|---|
| "+" button | `orbit_screen.dart:698-715` (Layer 5) | `ExpandableFab(anchor: ExpandableFabAnchor.topRight, fabSize: 40)` with items `orbit_new_group`, `orbit_new_announce`; opens with a scrim |
| Chrome conventions (196/209) | index rows / retired `orbit_qr_chrome_buttons.dart` | 40 px chrome circles at `top: safeTop + 8`; chrome near the FAB must be ordered so the ExpandableFab open-scrim wins |
| Sculpt-edit hide | `orbit_screen.dart:578`; locked by `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart:2082` | all Orbit chrome hides while `innerEditing` |
| RTL | `orbit_view_toggle_button.dart:9-13` | top chrome uses physical positioning; the FAB does not mirror |

### 4.5 Existing tests touching these surfaces

| Test file | What it pins | Affected by this change? |
|---|---|---|
| `test/features/feed/presentation/widgets/feed_header_test.dart:41` | `ConnectionStatusIndicator` present in Feed header when `p2pService` non-null (206) | **Breaks by design** (indicator removed from Feed) |
| `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart` (L265-553) | full state/label/color/semantics/flow-event contract of the pill | Unaffected by relocation; remains the widget contract |
| `test/features/orbit/presentation/screens/orbit_view_split_test.dart` (L242, 405-513) | toggle behavior via `find.byKey(ValueKey('orbit-view-toggle'))` + semantics labels | Key/semantics unchanged → must stay green |
| `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart:2074, 2082` | toggle present normally, hidden during sculpt-edit | Must stay green; new top-right chrome must follow the same hide rule |
| `test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart` (L298, 324) | current chrome inventory (post-209) | Inventory grows by one top-right element |
| `orbit_unread_indicator_wired_test.dart`, `orbit_wired_test.dart`, `feed_swipe_test.dart`, `feed_wired_test.dart`, 2 integration tests | locate the toggle by key as a landmark | Key unchanged → must stay green |
| No existing test | expects an Online indicator on Orbit | New coverage required |

No test asserts `Icons.chat_bubble_outline` / `Icons.blur_on` for the toggle (those constants appear only in the widget itself), so the glyph swap has no existing icon-level breakage surface.

---

## 5. Scope Clarification

| Area | Status | Notes |
|---|---|---|
| Top-left toggle **glyphs** (both views) | **In scope** | inner view → bullet-list glyph; all-chats view → dashed-orbit glyph, per mockup L462 mapping |
| Top-left toggle **container styling** | **In scope** | match the mockup `.chrome-btn` dark-circle look (dark fill + light hairline) within the app's theming system |
| Top-left toggle **behavior, key, semantics, position, hide rules** | **Unchanged** | still the view toggle; `ValueKey('orbit-view-toggle')`, `orbit_view_toggle_to_*` labels, `Positioned(top: safeTop+8, left: 16)`, hidden during sculpt-edit and when `onToggleView == null` |
| Online indicator **on Orbit top-right next to "+"** | **In scope** | same `ConnectionStatusIndicator` contract (states, passivity, telemetry), new host |
| Online indicator **removed from Feed header** | **In scope** | "migrate" = move; revises 206's preserve-invariant deliberately |
| Feed header username editing | **Unchanged** | must survive the indicator's removal |
| `ConnectionStatusIndicator` internal contract (states, colors, labels, flow event, passivity) | **Unchanged** | relocation only |
| `BadgeReadinessState` / `P2PService` / transport stack | **Out of scope** | no signal changes |
| 207's intros affordances (intro dock, ghost nodes, tray, relocated banner) | **Out of scope** | 207 remains an unratified mockup; only its top-left button *look* is borrowed |
| QR/Scan chrome | **Out of scope** | retired by 209; the mockup's center pair is stale — do not reintroduce |
| `ExpandableFab` behavior (items, scrim, animation) | **Unchanged** | the indicator is a sibling, not a FAB item |
| Bottom nav, Feed body, other screens | **Out of scope** | |

---

## 6. Test Cases

### Group A — Top-left toggle appearance (TC-211-01 … 06)

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-211-01 | Open Orbit on the default inner-circle view; inspect the top-left button. | The button renders the **bullet-list glyph** (mockup `IC.list` equivalent), not `Icons.chat_bubble_outline`. |
| TC-211-02 | Toggle to the all-chats view; inspect the top-left button. | The button renders the **dashed-orbit glyph** (mockup `IC.orbit` equivalent), not `Icons.blur_on`. |
| TC-211-03 | Inspect the button container on either view. | 40×40 circle with the mockup's dark-chrome treatment: dark translucent fill and a light 0.5 px hairline border; glyph rendered ~20 px in a near-white/high-contrast tone. |
| TC-211-04 | Render Orbit over both a bright and a dark user-chosen background (the `backgroundReadableColors` extremes). | The dark-chrome button and its glyph remain visible/legible on both (no invisible-on-dark regression). |
| TC-211-05 | Locate the button by `ValueKey('orbit-view-toggle')` on both views. | Key unchanged; exactly one match on each view. |
| TC-211-06 | Render in an RTL locale (ar). | Button stays at physical top-left (`left: 16`); no mirroring, no overlap with top-right chrome. |

### Group B — Top-left toggle behavior regression (TC-211-07 … 10)

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-211-07 | Tap the button on the inner-circle view; tap again on the all-chats view. | View flips inner-circle → all-chats → inner-circle exactly as today; glyph tracks the view per TC-211-01/02. |
| TC-211-08 | Read the button's semantics label on each view. | Still `orbit_view_toggle_to_list` ("Show all chats") on inner view and `orbit_view_toggle_to_circle` ("Show inner circle") on all-chats view, in en/ar/de (l10n parity intact). |
| TC-211-09 | Enter inner-circle sculpt-edit mode. | Button hidden (existing `!innerEditing` gate still holds — `orbit_sculpt_summon_wired_test` locks stay green). |
| TC-211-10 | Build `OrbitScreen` with `onToggleView == null`. | No top-left button rendered (existing conditional mount preserved). |

### Group C — Online indicator placement on Orbit (TC-211-11 … 17)

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-211-11 | Open Orbit (inner-circle view) with a wired `P2PService`. | Exactly one `ConnectionStatusIndicator` renders in the top-right region, horizontally adjacent to (left of) the "+" button, vertically aligned with the top chrome row (`top: safeTop + 8` band). |
| TC-211-12 | Toggle to the all-chats view. | Indicator still present and unchanged (renders on both views). |
| TC-211-13 | Enter inner-circle sculpt-edit mode. | Indicator hides along with the rest of the Orbit chrome; reappears on exit. |
| TC-211-14 | Open the "+" ExpandableFab (tap it). | FAB items and scrim render above/over the indicator (scrim precedence per 196/209 convention); the indicator does not intercept FAB taps; closing the FAB restores normal chrome. |
| TC-211-15 | Render in an RTL locale (ar). | Indicator keeps its physical top-right position next to the non-mirroring "+"; no overlap with the top-left toggle. |
| TC-211-16 | Render Orbit with no `P2PService` available (whatever the wired-nullability of the new plumbing allows, e.g. bare `OrbitScreen` in tests without the new param). | No indicator, no crash — graceful absence like `FeedHeader`'s `if (p2pService != null)` guard today. |
| TC-211-17 | Long node display-state (`Online ✦`) at 1.5× text scale on a 390-pt-wide device. | Indicator pill and "+" do not overlap or overflow; both remain fully tappable/visible. |

### Group D — Online indicator behavior on Orbit (TC-211-18 … 23)

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-211-18 | Node state is `ready` **before** Orbit is opened; open Orbit. | Indicator seeds from `currentState` and shows the correct `Online` variant immediately (no flash of `Offline`). |
| TC-211-19 | While Orbit is visible, drive `stateStream` through offline → connecting → ready (all five badge states). | Indicator updates live through `Offline` / `Connecting` / `Online` / `Online.` / `Online ✦` with the same labels/colors as the existing widget contract. |
| TC-211-20 | Tap the indicator. | Nothing happens — it remains a passive, non-tappable badge (no button semantics). |
| TC-211-21 | First transition to ready while the Orbit indicator is mounted. | `TIME_TO_ONLINE_BADGE_WIDGET` flow event emitted exactly once (contract preserved at the new host). |
| TC-211-22 | Toggle inner ⇄ all-chats views repeatedly while online. | Indicator state persists correctly across toggles; no duplicate flow-event emission, no stream-subscription leak (no "stream already listened" errors). |
| TC-211-23 | Background and resume the app (lifecycle pause/resume) while on Orbit. | Indicator reflects the current node state after resume (stale state is refreshed by the stream as today on Feed). |

### Group E — Feed header after the migration (TC-211-24 … 26)

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-211-24 | Open Feed with a wired `P2PService`. | **No** `ConnectionStatusIndicator` anywhere on the Feed screen. |
| TC-211-25 | Use Feed-header username editing after the change. | Editing flow works exactly as before (206 behavior preserved); header lays out cleanly without a leftover gap or overflow. |
| TC-211-26 | Feed with `p2pService == null` (existing guard path). | Identical rendering to TC-211-24's header (guard removal leaves no behavioral fork). |

### Group F — Cross-screen and state transitions (TC-211-27 … 29)

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-211-27 | Node goes offline while user is on Feed; user switches to the Orbit tab. | Orbit indicator shows `Offline` immediately on arrival (seeded from `currentState`, not from a stale default). |
| TC-211-28 | Rapidly switch Feed ⇄ Orbit tabs several times while state changes are streaming. | No crash, no duplicate indicators, indicator on Orbit always converges to the latest state. |
| TC-211-29 | Node state changes while sculpt-edit has the indicator hidden; user exits edit mode. | Re-shown indicator displays the **current** state, not the pre-edit state. |

### Group G — Regression locks (TC-211-30 … 33)

| ID | Scenario | Expected outcome |
|---|---|---|
| TC-211-30 | Run the existing toggle-behavior suite (`orbit_view_split_test.dart`) and key-landmark suites (`orbit_unread_indicator_wired_test`, `orbit_wired_test`, `feed_swipe_test`, `feed_wired_test`, the two integration tests). | All green — key, semantics, and toggle behavior unchanged. |
| TC-211-31 | Run the `ConnectionStatusIndicator` widget contract suite (`connection_status_indicator_test.dart`). | All green — the widget itself is untouched. |
| TC-211-32 | Run the post-209 chrome-inventory suite (`orbit_qr_entry_migration_test.dart`). | Green, with the inventory updated to include exactly one new top-right element and NO reintroduced QR/Scan chrome. |
| TC-211-33 | Run l10n parity (`orbit_strings_parity_test.dart`) across en/ar/de. | Green — no orphaned or missing keys introduced by the chrome changes. |

---

## 7. Evidence Gaps / Open Points

- **Exact glyph assets**: Flutter has no built-in icon identical to the mockup's `IC.list` (bulleted list) and `IC.orbit` (dot in dashed ring). Nearest material equivalents exist (`Icons.format_list_bulleted`; no close `IC.orbit` match). Whether to use material approximations or custom `CustomPainter`/SVG-derived glyphs is a solution decision for the TDD plan — the spec only requires "reads as the mockup glyph" (TC-211-01/02).
- **Dark-chrome fill vs. theming**: the mockup hardcodes `rgba(16,18,24,0.75)`; the app themes chrome via `backgroundReadableColors`. TC-211-04 pins the requirement (legible on both background extremes); how the dark treatment integrates with the theme system is a solution decision.
- **206 invariant revision**: 206 explicitly preserved the indicator in the Feed header; this spec supersedes that single point (indicator moves). The rest of 206 (center-avatar Settings entry, username editing) is untouched.

## 8. AMENDMENTS (same-day, post verify→refute — workflow `wf_080d7669-809`, 4 verify + 4 refute agents)

1. **The container restyle is a no-op on the dark tone.** `background_readable_colors.dart:65` `surfaceSubtle` (dark tone) is `Color(0xBF101218)` — exactly the mockup's `rgba(16,18,24,0.75)` — and `:68` `border` is `Color(0x80FFFFFF)` — exactly `rgba(255,255,255,0.50)`. The toggle already renders the 207 chrome container on dark backgrounds; the user-visible difference is the **glyph only**. TC-211-03 is reinterpreted as a **token lock**: the container must keep using `readableColors.surfaceSubtle`/`readableColors.border` (NOT hardcoded rgba). TC-211-04 pins the light-tone inversion (`representativeLight`: fill `0xE8EEF2F7`, border `0x8A101318`) still applies — a hardcoded dark fill on `daylightLagoon` backgrounds would ship undetected otherwise (no existing test asserts the toggle's colors).
2. **Feed header is NOT the only production host** (spec §2.2/§4.3 "renders only in the Feed header" corrected): `FirstTimeExperienceScreen` also mounts `ConnectionStatusIndicator` top-right (`first_time_experience_screen.dart:143-149`, wired at `first_time_experience_wired.dart:678-690`). The FTE usage is **untouched** by this change. Additionally, `integration_test/_support/node_readiness.dart:15` and `group_multi_party_device_real_harness.dart:72` import the widget FILE for its pure helpers (`ConnectionHealth`/`healthFromState`) — the file must stay at its current path.
3. **"All Orbit chrome hides during sculpt-edit" was wrong**: only the Layer 1b toggle is gated on `!innerEditing` (`orbit_screen.dart:578`); the `ExpandableFab` is unconditional. TC-211-13 stands on its own justification: the sculpt-edit banner spans the full top width (`inner_circle_interactive_surface.dart:691-695`, `top:12 left:0 right:0`), so a top-right indicator must hide during editing to avoid occluding it. The FAB's own overlap with the edit banner is pre-existing and out of scope.
4. **TC-211-21 wording tightened**: the flow event has no global latch — it fires on every not-ready→ready transition seen by a mounted State instance (instance re-seeds from `currentState` on mount, so remount-while-ready does NOT re-emit). "Exactly once" in TC-211-21/22 means: one event for one readiness transition while mounted, and no duplicate from view-toggle rebuilds. Its only external consumer (`benchmark_node_startup_harness.dart:98-106`) is a non-asserting, headless print loop — relocation cannot break a gate.
