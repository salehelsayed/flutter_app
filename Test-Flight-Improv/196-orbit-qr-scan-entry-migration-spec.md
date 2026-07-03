# 196 - Migrate "My QR" / "Scan" entry points to Orbit top chrome

**Feature Improvement** (product-confirmed 2026-07-02: user selected alternative **B "Quiet Chrome"** from [196-orbit-qr-scan-entry-mockups.html](196-orbit-qr-scan-entry-mockups.html); evidence workflows `wf_1bb47e62-6cf` (mockup research) + `wf_3bf64e03-e20` (spec evidence), all file:line claims source-verified on branch `new-orbit`).

---

## 1. Problem Statement

Since the 193 view split, the Orbit tab opens on the **Inner-Circle surface** by default (`orbit_wired.dart:383-389`), and every Feed→Orbit re-activation resets back to it (`orbit_wired.dart:477-492`). The only entry points to the app's two contact-growth actions — **My QR** (show my code) and **Scan** (scan a friend's code) — are two pills inside `FriendsListHeader` (`friends_list_header.dart:37-49`), which is mounted **only on the all-chats list surface** (`orbit_screen.dart:594-598`).

Consequences today:

- From the default surface there is **no path** to My QR or Scan. The user must know to tap the view toggle (an unlabeled 40px chrome circle), land on the list, and then find the pills — two taps plus discovery of a mode switch, for the primary mechanism by which this serverless P2P app adds contacts.
- The pills hide while list search is active (`friends_list_header.dart:37`), further narrowing availability.
- The pills are plain `GestureDetector`s with **no `Semantics` and no `Tooltip`** (grep-verified zero hits in `friends_list_header.dart`); their accessible name comes only from the visible label text.

This is a migration, not a new capability: both actions and their destination screens already exist and work.

### Chosen product design (approved mockup, alternative B)

Twin **40×40 circular chrome buttons** at the **top-center** of the Orbit screen — the same chrome species as the 193 view toggle (`orbit_view_toggle_button.dart:38-57`): `readableColors.surfaceSubtle` fill, 0.5px `readableColors.border` hairline, 20px glyph in `readableColors.textPrimary`, top offset `safeTop + 8`, i.e. the same row as the toggle (physical left:16) and the create FAB (physical right:16). My QR keeps `Icons.qr_code`; Scan keeps `Icons.camera_alt_outlined`. The pills are removed from `FriendsListHeader`.

Product decisions recorded for this spec (approved-design interpretation; flag to product if wrong):

1. **Both surfaces.** The buttons are persistent top chrome like the toggle and the FAB — visible on the Inner-Circle surface AND the all-chats list surface. (Rationale: the intros deep link `main.dart:4295` lands directly on the list surface; chrome that vanishes per-surface reads as flicker; the list surface must not lose QR access it has today.)
2. **No search-hiding rule.** Unlike the old pills, the buttons stay mounted while list search is active — consistent with the toggle, which never hides.
3. **Physical, non-mirroring placement.** The pair is horizontally centered and keeps a fixed visual order (My QR left of Scan) in LTR and RTL, matching the documented physical-placement rationale of the toggle/FAB chrome row (`orbit_view_toggle_button.dart:6-13`).
4. **Accessibility floor.** Icon-only buttons must expose `Semantics(button: true)` with localized labels; the existing l10n keys `orbit_my_qr` / `orbit_scan` (en/ar/de `app_*.arb:202-203`) are the labels' source of truth. Net accessibility must not regress versus the labeled pills.
5. **Destinations unchanged.** Both actions keep their existing full-screen `MaterialPageRoute` pushes to `QRDisplayWired` / `QRScannerWired` via the already-threaded `onMyQR` / `onScanQR` callbacks (`orbit_wired.dart:2079-2093`, `:2130+`). No sheets, no new routes.

## 2. Impact Analysis

- **Severity:** degrades onboarding/growth, not data safety. In a P2P app with no server directory, the QR handshake is the *only* way to add a friend (Orbit surface) besides the first-time-experience screen; burying it behind a mode toggle suppresses the core loop.
- **Frequency:** every user, every time they want to add a contact from the main app shell.
- **Workaround:** exists (toggle → pills) but requires discovering the unlabeled toggle.

| Scenario | Taps to reach action today | After migration |
|---|---|---|
| Default entry (Inner Circle) → My QR | 2 (toggle, pill) + mode discovery | 1 |
| Default entry → Scan | 2 + mode discovery | 1 |
| List surface, search active → either | unavailable (pills hidden) | 1 |
| Intros deep link (lands on list, `main.dart:4295`) → either | 1 (pill) | 1 (chrome button) |
| Screen-reader user → either | pills reachable but unlabeled container semantics | labeled buttons (`orbit_my_qr`/`orbit_scan`) |

## 3. Current State

### 3.1 Production wiring

| File | Role | Key facts |
|---|---|---|
| `lib/features/orbit/presentation/widgets/friends_list_header.dart` | Migration source | `onMyQR`/`onScanQR`/`searchActive` params (:9-11); pills hidden when `searchActive` (:37); My QR = `Icons.qr_code` + `l10n.orbit_my_qr` (:38-42), Scan = `Icons.camera_alt_outlined` + `l10n.orbit_scan` (:44-48); `_PillButton` (:56-105) accent `#157A39`, fill `0x261DB954` dark / `0xFFE5F4EA` light, radius 10, **no Semantics/Tooltip**. Sole ctor site: `orbit_screen.dart:594-598`. |
| `lib/features/orbit/presentation/screens/orbit_screen.dart` | Presentation host | `onMyQR`/`onScanQR` required (:192-193, :245-246); `viewMode` default `allChats` (:265); disjoint surfaces branch (:353-357); toggle mounted on both surfaces when `onToggleView != null` (:359-367); list header sliver with 48px physical-left RTL inset when toggle present (:583-593); FAB layer (:480-496). Inner-circle surface (:507-559) has **no QR affordance; top-center is empty**. |
| `lib/features/orbit/presentation/widgets/orbit_view_toggle_button.dart` | Chrome-species donor | `Positioned(top: safeTop+8, left: 16)` **physical, not directional** with documented RTL rationale (:6-13, :38-40); 40×40 circle, `surfaceSubtle` fill, 0.5 border, icon 20 `textPrimary` (:48-56); `Semantics(button: true, label: …)` flipping per view (:33-43); `ValueKey('orbit-view-toggle')` (:45). |
| `lib/features/orbit/presentation/screens/orbit_wired.dart` | Handlers | `_onMyQR` (:2079-2093) pushes `QRDisplayWired(repo, bridgeClient, onClose, onScanPressed: _onScanQR, backgroundPreference)`; no identity guard (absorbed by `QRDisplayWired`'s internal `noIdentity` state, `qr_display_wired.dart:211-214`). `_onScanQR` (:2130+) pushes `QRScannerWired` with ~25 deps incl. `feedClearedRepository` (B6 lock) and `ownPeerId: _identity?.peerId ?? ''` (:2149 — empty-string window if tapped before identity load). Threaded into `OrbitScreen` (:2300-2301). |
| `lib/features/groups/presentation/widgets/expandable_fab.dart` | Adjacent chrome | Top-right at `safeTop+8, right:16`, fabSize 40 (`orbit_screen.dart:482`); open state = downward menu + full-screen scrim that eats taps (:111-126). |
| `lib/features/conversation/presentation/navigation/conversation_route_transition.dart` | Route builder | `buildConversationRoute` = plain `MaterialPageRoute` (:14-19). |
| `lib/core/theme/background_readable_colors.dart` | Color system | dark `surfaceSubtle 0xBF101218` / light `0xE8EEF2F7`; `textPrimary 0xFFF8FAFC` / `0xFF101318`; tone driven by `backgroundPreference` (:57-141). |
| `lib/l10n/app_{en,ar,de}.arb` | Strings | `orbit_my_qr` "My QR"/"رمزي"/"Mein QR", `orbit_scan` "Scan"/"مسح"/"Scannen" (:202-203); consumed today only by `friends_list_header.dart:39,45`. |

Other QR entry points (unchanged by this migration): first-time-experience home pushes `QRScannerWired` with an identity guard (`first_time_experience_wired.dart:547-552`); `ScanFriendCard` inside the QR display screen re-fires `onScanPressed` → orbit `_onScanQR` (`qr_display_screen.dart:157-158`, threaded `qr_display_wired.dart:199/207`). `QRActionCards` (`lib/features/orbit/presentation/widgets/qr_action_cards.dart`) duplicates the `onMyQR`/`onScanQR` contract but is **dead production code** — mounted nowhere in `lib/`, consumed only by its own test.

### 3.2 Geometry envelope (top strip, y = safeTop+8, height 40)

Toggle occupies physical x = 16..56; FAB occupies x = width−56..width−16. On the **inner-circle surface** the top-center strip is genuinely empty (content is vertically centered, `orbit_screen.dart:516-518`). On the **list surface** the header row is **in the same band**: the first sliver's padding is `fromLTRB(16, 8, 16, 0)` under `SafeArea` (`orbit_screen.dart:577-579`), so the "Close Friends" row's top edge is exactly `safeTop+8` — that in-band collision is *why* the 48px physical-left inset exists (`orbit_screen.dart:583-593`). Verified consequences (refute pass `wf_e3934c6d-a77`):

- A centered 88px chrome pair would intersect the header title at **every supported width** in en (title spans x≈68..~190 at 16px w600; pair spans 116..204 at 320dp, 171..259 at the 430dp orbit test surface), worse in de and under user text scaling (no textScale clamp exists); in ar the right-anchored title (ends at W−20) intersects the pair's right half. Any top-center chrome requires the list header to leave the strip band (or equivalent de-collision) — the RTL lock test's premise changes with it.
- **Pre-existing overlap bug**: the Scan pill's right edge (W−20) already sits inside the FAB's footprint (W−56..W−16) in LTR — the FAB (topmost Stack child) steals taps on the pill's right ~36px; at 320dp with prod fonts the header row already overflows (the orbit/feed suites carry overflow suppressions for exactly this header, `feed_focus_test.dart:289-296`). Removing the pills incidentally removes both.

### 3.3 State seams (193/194)

`_viewMode` not persisted; `initialFilterTab != null` forces `allChats` (intros notification route, `main.dart:4295`); Feed→Orbit rising edge resets to inner circle *before* dirty replay (`orbit_wired.dart:483-488`); entering inner circle force-closes search (`:497-502`, `:1880-1882`) — **the inner-circle surface can never have search active**. 194 unread indicators render inside Layer 1 (below chrome layers); orbit tests must use bounded pumps (`pumpAndSettle` hangs on lit-node animation).

### 3.4 Existing tests and gates

| Test | What it locks today | Fate under this spec |
|---|---|---|
| `orbit_wired_test.dart:859` 'friends list header shows QR buttons' (GROUP_TESTS:227) | `find.text('My QR')`/`find.text('Scan')` after toggling to list | **Superseded** — pills leave the header |
| `orbit_view_split_test.dart:388` 'all-chats header clears the top-left toggle in RTL' (GROUP_TESTS:241) | RTL: header's left edge ≥ toggle's right edge, justified by the pills (:401-403) | **Superseded/rewritten** — pill rationale gone; title-vs-toggle clearance must survive |
| `orbit_view_split_test.dart:259/:294/:415/:557/:584` | Inner-circle default, toggle round-trip, semantics flip, fresh-mount default, re-entry reset | Must stay green (regression) |
| `orbit_wired_test.dart:404` B6 | `feedClearedRepository` → `QRScannerWired` handoff | Must stay green |
| Bare-pump `OrbitScreen` ctor sites: `orbit_screen_loading_test.dart:153-154`, `orbit_screen_archived_groups_test.dart:95-96`, `intro_notification_orbit_route_test.dart:258-259`, `integration_test/orbit_performance_harness.dart:210-211` | Pass `onMyQR`/`onScanQR` no-ops | Compile-coupled to any signature change |
| `test/l10n/orbit_strings_parity_test.dart` (GROUP_TESTS:247) | ARB parity for 4 orbit keys — `orbit_my_qr`/`orbit_scan` **not yet listed** | Extension point |
| `test/l10n/l10n_integrity_test.dart:45` | No hardcoded UI literals | **Pre-existing RED**: exactly 3 orbit3-prototype literals (`orbit3_screen.dart:1113,:1131`, `orbit3_arch_panel.dart:67`); must not grow |
| `qr_display_wired_test.dart` / `qr_scanner_wired_test.dart` (BASELINE_TESTS:10) | Destination screens | Must stay green |
| Sims: `cold_start_message_render_simulator_test.dart:344-356`, `group_delete_preserves_friends_simulator_test.dart:282-286` | Tap `ValueKey('orbit-view-toggle')` in preambles | Must stay green |
| `PERF_TARGET=ORBIT` (`run_test_gates.sh:344-351`) | Inner-circle frame budgets | Must stay green |

### Test harness registration conventions (for the plan that follows)

New `test/features/**` files auto-register in `feature-host-all` (`run_host_test_gates.sh:183-184`); orbit wired-tier files are additionally **curated into GROUP_TESTS** (`run_test_gates.sh:209-248` — 193/194 precedent at :241/:246); `test/l10n/*` is outside the feature glob and must be pinned (comment :238-240); every new test file must classify in `completeness-check` (`classify_path` :569-742). Orbit suites: `setLargeTestSurface`, bounded `pumpOrbitFrames` (never `pumpAndSettle`), cat.12 `pumpWidget(SizedBox())` remount, cat.6 in-body semantics-handle dispose.

### 3.5 Branch context / hazards

Working tree on `new-orbit` is dirty with uncommitted 194 work touching `orbit_screen.dart`, `orbit_wired.dart`, `orbit_wired_test.dart`, l10n files, and `run_test_gates.sh`; 3 concurrent sessions have previously edited shared files. `orbit_wired_test.dart` is a ~5100-line shared file with high collision risk. Line numbers cited here are working-tree values and may drift.

**Tree-blocking (verified 2026-07-03):** a concurrent **197** session ("orbit groups on inner-circle rings", untracked plan doc) left `integration_test/orbit_performance_harness.dart:16,:204` and `test/features/orbit/application/inner_circle_items_test.dart:5` importing `package:flutter_app/features/orbit/application/inner_circle_items.dart`, which does not exist yet — `PERF_TARGET=ORBIT` and full `feature-host-all` sweeps cannot compile on the current tree for reasons unrelated to 196. Acceptance gates must quarantine these failures (baseline-control step) or sequence after 197 goes green.

## 4. Scope Clarification

| Area | Status |
|---|---|
| Twin 40px QR/Scan chrome buttons on Orbit top-center, both surfaces | **In scope** |
| Removal of the My QR / Scan pills from `FriendsListHeader` | **In scope** |
| Semantics labels for the new icon-only buttons (reusing `orbit_my_qr`/`orbit_scan`) | **In scope** |
| RTL behavior of the new chrome + the header's toggle-clearance guarantee | **In scope** |
| Supersession/rewrite of the two pill-coupled test locks | **In scope** |
| l10n parity coverage for `orbit_my_qr`/`orbit_scan` | **In scope** |
| `QRDisplayWired` / `QRScannerWired` internals, their tests | **Unchanged** |
| `_onMyQR`/`_onScanQR` handler bodies (guards, deps, migration-QR path, flow events) | **Unchanged** (behavior carries over; robustness locked by tests) |
| First-time-experience scan entry, `ScanFriendCard` | **Unchanged** |
| View toggle, ExpandableFab, search dock/trigger, 194 unread indicators | **Unchanged** |
| `buildConversationRoute` (full-screen push) | **Unchanged** |
| Pill visual tokens (`#157A39` accent etc.) | **Removed with the pills**; not re-styled elsewhere |
| `QRActionCards` dead widget + its test | **Out of scope** (flagged as separate cleanup candidate) |
| Persisting `_viewMode`, intros-route landing surface | **Out of scope** (193 design locks stand) |
| orbit3 prototype l10n literals (pre-existing RED) | **Out of scope** (must not grow) |

## 5. Test Cases

IDs: `TC-196-NN`. "Chrome buttons" = the two new 40×40 circles (My QR, Scan). "Pills" = the removed header buttons. "Toggle" = `ValueKey('orbit-view-toggle')`. Tags: *(boundary)*, *(regression)*.

### Group A — Presence & geometry (TC-196-01..06)

- **TC-196-01** — Default entry to Orbit (inner-circle surface). Expected: both chrome buttons visible; each renders a 40×40 circular container with the toggle's chrome tokens (`surfaceSubtle` fill, 0.5 hairline, 20px icon in `textPrimary`); icons are `Icons.qr_code` (My QR) and `Icons.camera_alt_outlined` (Scan).
- **TC-196-02** — Measure positions on a standard surface. Expected: pair horizontally centered as a unit (8px gap); top edge at `safeTop + 8` — same row as toggle and FAB; My QR left of Scan.
- **TC-196-03** — 320dp-wide logical viewport *(boundary)*. Expected: no overlap between chrome buttons and the toggle (x=16..56) or the FAB (right 16..56); all four chrome elements individually hit-testable.
- **TC-196-04** — Arabic locale (RTL). Expected: pair remains horizontally centered; visual order unchanged (My QR center.dx < Scan center.dx); no overlap with the physical-left toggle or physical-right FAB.
- **TC-196-05** — Daylight/light `backgroundPreference`. Expected: buttons resolve the light readable tone (light `surfaceSubtle` fill, dark `textPrimary` icon), same as the toggle's behavior on that preference.
- **TC-196-06** — Bare `OrbitScreen` pump with `viewMode: innerCircle` and `onToggleView: null` (standalone/no-toggle host). Expected: chrome buttons still present and tappable (they are not coupled to the toggle's nullability).

### Group B — Tap behavior, wired (TC-196-07..12)

- **TC-196-07** — Tap My QR on the inner-circle surface. Expected: full-screen QR display screen is pushed (existing `QRDisplayWired` contract); popping returns to the inner-circle surface with view state intact.
- **TC-196-08** — Tap Scan on the inner-circle surface. Expected: full-screen scanner is pushed with the full dependency set; the B6 `feedClearedRepository` → scanner handoff lock still holds *(regression)*.
- **TC-196-09** — From the pushed QR display, tap its `ScanFriendCard`. Expected: scanner opens (the `onScanPressed → _onScanQR` thread survives the migration) *(regression)*.
- **TC-196-10** — Tap Scan before identity has loaded (identity repo still pending) *(boundary)*. Expected: no crash; scanner opens under the existing `ownPeerId ''`-fallback contract (current behavior locked, not redesigned).
- **TC-196-11** — Tap My QR with no identity available *(boundary)*. Expected: QR display opens and shows its internal no-identity error state (`qr_display_wired.dart:211-214`); no crash.
- **TC-196-12** — Open the create FAB (scrim up), then tap at the chrome buttons' coordinates. Expected: the tap is consumed by the scrim (menu closes); **no** QR route is pushed *(regression of existing z-order)*.

### Group C — All-chats surface & pill removal (TC-196-13..17)

- **TC-196-13** — Toggle to the all-chats list. Expected: header contains no "My QR"/"Scan" pill (texts absent from the header row); "Close Friends" title still renders.
- **TC-196-14** — On the all-chats surface. Expected: both chrome buttons are present and functional (tap My QR → QR display), identical placement to the inner-circle surface.
- **TC-196-15** — Activate list search. Expected: chrome buttons remain mounted and tappable while the search dock is open (no pill-style hiding); search itself still filters *(regression)*.
- **TC-196-16** — English and Arabic locales, all-chats surface. Expected: the header title never intersects any top-strip chrome (toggle, QR pair, FAB) — successor of the RTL pill lock `orbit_view_split_test.dart:388-413`, whose same-band premise changes with the migration (§3.2) *(regression)*.
- **TC-196-17** — Launch via intros deep link (`initialFilterTab: 'intros'` forces all-chats). Expected: chrome buttons visible and functional on the landing surface *(covers `main.dart:4295` route)*.

### Group D — Accessibility & l10n (TC-196-18..20)

- **TC-196-18** — Semantics tree with `ensureSemantics()`. Expected: two button-flagged nodes labeled with localized `orbit_my_qr` / `orbit_scan` values ("My QR"/"Scan" in en); labels switch with locale (ar: "رمزي"/"مسح").
- **TC-196-19** — ARB parity for `orbit_my_qr`/`orbit_scan`. Expected: keys present and non-empty in en/ar/de and reachable via the generated localization API (extends `orbit_strings_parity_test.dart`, which does not cover them today).
- **TC-196-20** — l10n integrity literal scan. Expected: violation list does not grow beyond the 3 pre-existing orbit3 literals — the migration introduces no hardcoded UI strings *(regression)*.

### Group E — State-transition regressions (TC-196-21..24)

- **TC-196-21** — Feed→Orbit re-entry (rising edge) after having toggled to the list. Expected: view resets to inner circle (193 lock) and chrome buttons are present post-reset *(regression)*.
- **TC-196-22** — Rapid toggle round-trips innerCircle↔allChats. Expected: exactly one instance of each chrome button ever mounted; no flicker-driven duplicate keys, no disappearance on either surface.
- **TC-196-23** — Fresh remount (pump `SizedBox`, then remount the Orbit host — cat.12). Expected: default inner-circle surface with chrome buttons present.
- **TC-196-24** — Scroll the all-chats list under the chrome. Expected: list content scrolls beneath; chrome buttons stay fixed and remain tappable mid-scroll.

### Group F — Perf & simulator lanes (TC-196-25..26)

- **TC-196-25** — `PERF_TARGET=ORBIT` harness on the inner-circle surface with the chrome mounted. Expected: existing frame-budget assertions still pass (buttons are static chrome; no per-frame work added).
- **TC-196-26** — Cold-start simulator preamble (asserts inner-circle default, then taps the toggle). Expected: sim still passes end-to-end; the new chrome does not obstruct the toggle's tap target *(regression)*.

---

*No solution content in this document by design; implementation belongs to the 196 TDD plan.*
