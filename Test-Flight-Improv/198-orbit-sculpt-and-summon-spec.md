# 198 - Orbit overflow "Sculpt & Summon": concentric arcs, long-press geometry handles, find with result chips

**New Feature** (product-confirmed 2026-07-03: user selected the featured combined build **"Sculpt & Summon"** from [198-orbit-arch-overflow-edit-find-mockups.html](198-orbit-arch-overflow-edit-find-mockups.html) — Concentric Arcs (Q1 option B, design pick) carrying Orbit Handles (Q2 option B) and Result Chips (Q3 option C) on one surface; evidence workflows `wf_1679788b-fae` (mockup recon) + `wf_afb8aa1c-a93` (spec evidence, 5 explorers), all file:line claims source-verified on the live `new-orbit` tree with the untracked 196/197 code present).

---

## 1. Problem Statement

The production Orbit Inner-Circle surface (the 193 default view) seats exactly **13** chats — 5 on ring 1, 8 on ring 2 (`orbital_visualization.dart:32-38,61-63`). Post-197 those 13 seats are the recency-merged union of friends **and** groups (`orbit_wired.dart:293-295`, `inner_circle_items.dart:18-28`), so the cap is hit sooner than before. Three connected gaps:

1. **Overflow members are unreachable and invisible.** Items beyond the 13th are never rendered — only counted into a **+N badge that does nothing**: `OverflowBadge` is a 28×28 display-only widget with no `GestureDetector`, no `onTap` param, and no `Semantics` anywhere in the file (`overflow_badge.dart:8-93`), mounted via a bare `Positioned` (`orbital_visualization.dart:157-172`). Its inertness is actively test-locked (`orbital_visualization_test.dart:268-289`). A screen-reader user gets no announcement that hidden members exist at all. Worse, the badge's slot is computed with `count = 9` while the 8 ring-2 seats use `count = 8`, so its 245° center sits ≈9.4px from seat 13's 240° center — geometric overlap (29px separation needed; derived from the verified formulas at `orbital_visualization.dart:157-172,253-263`).
2. **The orbit's geometry cannot be tuned.** Every layout number is a compile-time const (canvas 320, radii 62/108, avatars 38/30, seats 5+8 — `orbital_visualization.dart:32-38`, duplicated in `orbital_ring_painter.dart:8-33`). The only geometry-knob precedent (4 steppers + SecureKeyStore persistence) lives in the **orbit3 lab**, which is `kDebugMode`-gated, mock-data-only, and never ships (`orbit3_prototype.dart:16`), with always-on stepper chrome covering the canvas (`orbit3_screen.dart:851-877`).
3. **Search cannot find circle members.** Production search is hard-gated to the all-chats list surface ("Search is an all-chats affordance — never shown on the Inner-Circle surface", `orbit_screen.dart:398-428`), *removes* non-matches instead of highlighting, and **drops all groups while active** (`orbit_wired.dart:303-316`) — a group beyond seat 13 is findable by search nowhere in the app. The orbit3 lab's search is arch-blind by construction (`Orbit3ArcRow` has no `searchQuery` param, `orbit3_arch_panel.dart:154-187`): the people hardest to spot are exactly the ones search ignores.

There is no long-press or double-tap gesture anywhere in `lib/features/orbit` (grep: zero hits) — the gestures the design needs are free.

### Chosen product design (approved mockup — the featured "Sculpt & Summon" build)

One surface, three composable capabilities (the mockup's `phone-hero`: arcs + handles + chips):

**A. Concentric arcs (overflow).** Tapping the +N badge reveals the overflow on true arcs that share the circle's center and visual vocabulary (dashed teal/purple, alternating per arc) — "the orbit simply keeps going". The badge becomes the toggle: on overflow, ring 2's 8 members re-spread across **9 slots** so the badge gets a real seat, a ≥44pt hit target, a chevron while open, and a localized Semantics label ("N more people — tap to open"). The circle takes its expanded seat instantly; only the arriving arc nodes animate in (staggered). **No arc is ever culled**: deep stacks push the circle down and the canvas scrolls. Arch members are the same node species as ring members — 194 unread indicators, 197 group avatars, and tap-to-open all carry up into the arcs.

**B. Orbit Handles (edit).** A **500ms long-press on empty orbit space** enters edit mode: haptic, rings brighten, the crowd dims to 22% so the handles pop (the dim lifts while dragging/stepping), and a top banner reads "TAP AWAY TO FINISH" with **Reset** top-left. Five grab handles sit **on the geometry itself**: ring spacing (ring 2's 6 o'clock), avatar size (ring 1's 12 o'clock), arc wrap (first arc's tip), max-per-arc (the tip's twin on the far end), orbit gap (first arc's apex). Drag = continuous coarse moves. **Tap a handle to arm it**: its glow flips green → teal, its live value floats in a bubble directly above it, and −/+ 48px steppers land on the nav-bar line flanking the nav pill (− left, + right). **No Done button — tap-away exits**: tapping any empty space (including dimmed avatars; NOT handles/badge/steppers/Reset) ends the session. The long-press-release click must be suppressed or it instantly exits the mode it just entered. Arch-only handles (wrap, max-per-arc, orbit gap) exist only while the arcs are open; collapsing auto-disarms them. The five knob values persist across app launches — corrupt or out-of-range stored data must fall back safely to defaults, and Reset returns a fresh mount to default geometry — **and they must survive account Move** (the orbit3 lab's tuned values are silently dropped on Move today; mechanism inventory in §3.3).

**C. Result Chips (find).** A search pill (bottom-right, above the nav band; 40px circle expanding to ~200px with keyboard focus) drives find: as the user types, **every on-canvas match lights in place** (green glow + forced name label) while the rest of the orbit fades to 28%, and the matching faces appear as a **chip strip above the pill** — avatar, name, and provenance ("ring 1", "arc 2"). Chips include matches the collapsed view has swallowed (overflow members, with arc provenance) and **groups** (unlike list search). Tapping a chip opens that chat. Matches outside the scrolled viewport auto-scroll into view. Clearing/closing restores everything. Zero matches → **no dimming, no chips** (bans the lab's "dim everything, highlight nothing" anti-signal).

**Composition.** Editing lives on the long-press, finding lives in the pill — they never fight over a gesture. The pill and chips sit outside the canvas, so searching never ends edit mode; a lit match stays at full brightness while the crowd holds the 22% edit dim. **Double-tap on empty space** toggles name labels under every node (staggered on alternate seats so 44px-apart neighbors' labels never collide); the gesture must not add double-tap-timeout latency to plain node taps (a documented lab weakness, `orbit3_screen.dart:511-517`).

#### Approved geometry & interaction constants (from the mockup, recorded as the design contract)

| Element | Value |
|---|---|
| Arc radii | rₖ = (108 + 46·og + 46·k)·sp for arc k=0,1,… — `og` scales only the circle→first-arc gap; arc-to-arc stays 46·sp |
| Arc avatars | 34·av px, clamped 20–52 (follows ONLY the avatar knob, so spacing visibly moves arcs) |
| Arc span (wrap) | φ = min(2.9 rad, 1.25·cv) per side; width pinch φ ≤ asin(170/r) for r > 170 holds up to cv 1.6, then releases linearly to full wrap at cv 2.5; 2.9 rad ≈ 166°/side keeps the two arc ends from ever meeting at the bottom |
| Arc capacity | max(4, min(⌊2φr/(34·av+10)⌋, pr)) — self-limits so tap targets stay legal; the pr knob can only lower it |
| Seat pitch | 2φ/(cap−1); partial arcs centered at full-row pitch |
| Arc paint | alternating teal `0x4081E6D9` / purple `0x33A78BFA`, dash 8/4, 8px glow blur 4 — the rings' exact vocabulary (`orbital_ring_painter.dart:8-59`) |
| Arc entrance | stagger arcIndex×60ms + seat×5ms; circle does NOT glide (takes its seat instantly) |
| Arc count | every overflow member must be seated and reachable at any supported population; the mockup renders up to 12 arcs (covers 100+ members at default knobs; 48 overflow at the pr=4 minimum). Populations beyond that envelope must still not silently cull — flag to product if a hard cap is preferred |
| Badge | ring-2 re-spread 8→9 slots on overflow; ≥44pt hit; `+N` ↔ chevron; localized Semantics |
| Knobs (range / step / default) | avatar `av` 0.6–1.4 / ±0.2 / 1.0 · spacing `sp` 0.7–1.5 / ±0.1 / 1.0 · wrap `cv` 0.5–2.5 / ±0.1 / 1.0 · max-per-arc `pr` 4–9 / ±1 / **9** · orbit gap `og` 0.5–2.5 / ±0.1 / 1.0 |
| Edit mode | 500ms hold, ~8px slop cancels; dim 22% nodes / 45% ring paint; value bubble above armed handle; −/+ 48px circles on the nav line; Reset top-left flanking the banner; tap-away = done; release-click suppressed |
| Find | pill 40px → ~200px; **match = case-insensitive substring on the display name** (trimmed query; empty query = no find state); match glow `#1DB954` (blur 16 vocabulary of the lab's proven treatment); non-match dim 0.28; ≤4 chips (36px avatar + name + provenance) — **the first 4 matches in merged-recency (seating) order**; auto-scroll-to-reveal for off-view matches |
| Default view | arcs **collapsed** on every entry (consistent with the 193 reset-everything-on-entry contract); the mockup hero's "starts expanded" is demo convenience — flag to product if wrong |

Product decisions recorded for this spec (approved-design interpretation; flag to product if wrong):

1. **This reverses the 193 "search is all-chats-only" asymmetry** — the Inner-Circle surface gets its own find affordance. The all-chats list search (filter-style, groups-dropped) is untouched.
2. **Groups participate in find results** — matching a group lights its node and chips it; tap opens the group conversation.
3. **Expansion state and label visibility are session-transient** (never persisted; reset with the 193 rising edge). Only the five knobs persist.
4. **Chrome untouched**: 193 toggle (top-left), 196 QR twins (top-center), FAB (top-right), nav pill all keep their seats; the arcs live strictly between the chrome band and the nav; the expanded canvas scrolls beneath both.
5. **Default geometry must stay fully on-screen** on narrow devices; past cv 1.6 the sculpted wrap may deliberately clip edge avatars at the bezel.
6. **Find does not auto-expand the arcs** (that was declined option B "Open The Sky"); collapsed overflow matches are served by chips + provenance + tap-to-open.
7. **Opening any conversation (node, chip) while editing ends the edit session** with the knobs persisted — no stale edit overlay behind a pushed route.
8. **Verdict override**: the mockup's own verdict recommended B-arcs + A-dock + A-summon; product chose the combined B+C build (consistent with 194/196 history of picking against verdicts). A "Tune Dock" and "Summoned Steppers" remain documented fallbacks; "Come To Me" and "Open The Sky" are considered-and-declined for find.
9. **Lab weaknesses must NOT be reproduced**: sub-44pt arch targets (`orbit3_arch_panel.dart:266-272`), double-tap-arena tap latency (`orbit3_screen.dart:511-517`), label/row collisions, circle marooned below the fold with no way back (`orbit3_screen.dart:320-344`), LTR-only positioning, storage writes on every no-op tap (`orbit3_screen.dart:346-396`).
10. **Chip tap opens the chat directly.** The mockup card offers "tap = spotlight or open" and its code both focuses down to the single match and opens; the intermediate focus-down step is declined as redundant with opening.
11. **Banner copy** = "TAP AWAY TO FINISH" (the live mockup's handles build); an earlier user-approved iteration specified "EDITING ORBIT · TAP AWAY TO FINISH" — flag to product which copy ships.

## 2. Impact Analysis

- **Severity:** degrades the app's primary social surface, not data safety. The Inner-Circle view is the default landing surface post-193; for any user whose merged friends+groups exceed 13, part of their social graph is invisible, unreachable, and unannounced (a11y) from the default screen.
- **Frequency:** every session for every user past 13 chats — and 197 made the threshold easier to hit by seating groups in the same 13.
- **Workarounds:** overflow *reach* has one (toggle to the all-chats list — requires discovering the unlabeled toggle); overflow *search for a group* has none (list search drops groups); geometry tuning has none (consts).

| Scenario | Today | After 198 |
|---|---|---|
| 14th chat's node (overflow=1) | never rendered; +N badge inert and overlapping seat 13 | tap +N → seated on arc 1, tappable, unread-capable |
| 50 chats | 37 invisible on the default surface | 5+ arcs, circle slides down, canvas scrolls, all reachable |
| Screen-reader user with overflow | zero signal that hidden members exist | badge announces "N more people — tap to open"; arch nodes are labeled buttons |
| Find a group not in the top 13 | impossible by search anywhere (list search excludes groups) | type in the pill → chip with provenance → tap to open |
| Find an overflow friend from the default surface | toggle → list → search (3 steps + mode discovery) | type in the pill (1 step) |
| Orbit too dense/sparse for taste or hand size | no remedy | long-press → sculpt 5 dimensions, persisted |
| Sculpted geometry after account Move | n/a (orbit3 precedent: silently dropped — key unregistered) | survives Move (registry entry required by this spec) |

## 3. Current State

### 3.1 Production wiring (the host surface)

| File | Role | Key facts |
|---|---|---|
| `lib/features/orbit/presentation/widgets/orbital_visualization.dart` | The circle | Fixed 320×320 Stack (`Clip.none`), consts `_ring1Radius 62/_ring2Radius 108/_ring1Count 5/_ring2Count 8/_minTapTargetSize 48` (:32-38); seating `take(5)/skip(5).take(8)`, `overflowCount = length>13 ? length-13 : 0` (:61-63) — items[13:] never rendered; seat math `angle=(i·360/count + ringIndex·15 − 90)°` (:253-263), pure physical trig (direction-agnostic); badge slot laid with count=9 vs seats' count=8 → ≈9.4px from seat 13 (:157-172); `_buildNode` forks friend/group, group Semantics localized, **non-unread friend label hardcoded English** `'Open chat with ${username}'` (:203-208); friend/group border colors identical (:200-220, no teal group ring); `unreadMotionEnabled` threaded ONLY to the 194 indicator (:58-60) — node entrances ignore reduce-motion |
| `lib/features/orbit/presentation/widgets/overflow_badge.dart` | The dead +N | 28×28 ClipOval + BackdropFilter(4) + dashed CustomPaint + `'+$count'` 10px; sole param `count`; **no GestureDetector / onTap / Semantics in the whole file** (:8-93); entrance = fixed 1000ms delay + 500ms scale/fade with no reduce-motion gate (:25-33); doc comment "friends exceed 13" is stale post-197 (count is the merged set) |
| `lib/features/orbit/presentation/screens/orbit_screen.dart` | Surface host | `resizeToAvoidBottomInset: false` (:355-357); layer order: surface → 193 toggle → 196 QR twins → … → ExpandableFab LAST (open-scrim wins taps) (:374-386, :499-515); inner-circle surface = `Center > SingleChildScrollView > Column[OrbitalVisualization, caption, hint]` — **no gesture handler on empty space** (:526-579); search trigger/dock hard-gated `viewMode == allChats` with explicit never-on-Inner-Circle comments (:398-428); all-chats first sliver top-padding 56 clears the chrome band (:592-605); bottom geometry: nav offset `max(16, viewPadding.bottom−14)`, reserved +64, dock at reserved+8 (:288-316); list-search "Inner Circle" provenance chip precedent (:1033,1052) |
| `lib/features/orbit/presentation/screens/orbit_wired.dart` | State host | 193 seam: `_viewMode` seeded innerCircle unless `initialFilterTab` (:389-396), reset + search force-close on every Feed→Orbit rising edge (:484-509), toggle (:1880-1893); 197 merge call (:293-295); list search filters friends only, **drops groups while active** (:299-317); 194 read-event subscription with active-refresh/dirty-replay (:1687-1720); friend tap → `buildConversationRoute(ConversationWired(...))` with re-entrancy guard (:1997-2043); group tap → `MaterialPageRoute(GroupConversationWired(...))` (:2467-2518); **already holds `SecureKeyStore`** (:112,:165) and reads quality prefs with it (:539-551); animation budgets: collapse 580ms / dock 560ms / trigger 340ms (:407-420) |
| `lib/features/orbit/presentation/widgets/orbital_avatar.dart` | Node species | `Semantics(button) > GestureDetector(opaque, onTap)` — onTap only, no onLongPress (:155-165); 48px tap floor when tappable (:105-110); entrance 500ms staggered `globalIndex×40ms`, has a `motionEnabled` param the production visualization never passes (:77-94); 194 indicator mounted `ExcludeSemantics + IgnorePointer` (:139-151) |
| `lib/features/orbit/presentation/widgets/unread_orbit_indicator.dart` | 194 | `#1DB954` ring at 1.35×radius, ≤3 satellites, 9s rotation (never settles — `pumpAndSettle` hangs); renders nothing at 0; freezes (stays visible) under reduce-motion (:82-85) |
| `lib/features/orbit/application/inner_circle_items.dart` + `domain/models/orbit_item.dart` | 197 merge | blocked-friends dropped, recency-desc lexical sort on ISO-8601 `sortKey`, **no cap applied here** (:18-28; orbit_item.dart:8-33) — overflow order is already defined for the arcs |
| `lib/features/orbit/presentation/widgets/orbital_ring_painter.dart` | Ring paint | duplicates radii 62/108 + teal/purple colors + dash 8/4 + glow stroke 8 blur 4 (:8-59) — a second hardcoded geometry copy any knob-driven change must reconcile |
| `orbit_search_trigger.dart` / `orbit_search_dock.dart` | Today's search UI | trigger 44×44 glass circle, **no Semantics**, stale 36×36 doc comment (:15-33); dock = plain TextField pill that self-pads by `viewInsets.bottom` for the keyboard (:28-83); no chips/highlight/provenance anywhere |
| `orbit_view_toggle_button.dart` / `orbit_qr_chrome_buttons.dart` / `expandable_fab.dart` | Chrome band | all at `safeTop+8`, all deliberately **physical/non-mirroring** with documented RTL rationale (toggle :9-13,38-56; QR row pinned `TextDirection.ltr` :33-56; FAB topRight) — new chrome must respect this collision-avoidance convention |
| `friends_list_header.dart` | List header | title-only post-196 (:5-31) |
| `lib/features/orbit/domain/models/orbit_view_mode.dart` | 193 lock | "deliberately NOT persisted — in-session or across launches" (:1-10) — 198's persisted knobs must not ride view-mode state |

### 3.2 Orbit3 lab prior art (source of the ported ideas — and its documented weaknesses)

| Area | Facts |
|---|---|
| Knob model | `Orbit3DimensionPreferences`: 4 knobs (`avatarScale/spacingScale/curveScale` doubles + `perRow` int); ranges as consts (:24-31 — avatar 0.6-1.4, spacing 0.7-1.5, curve 0.5-2.5, perRow 4-9); defaults 1.0/1.0/1.0/**7** (:34-39); versioned key `orbit3_dimension_preferences_v1` (:43); pipe-delimited codec, defaults on null/empty/wrong-arity/unparseable, per-field clamp on decode (:49-66). Factual delta: the lab model has 4 knobs with default perRow **7**; the approved design has **5** knobs (adds orbit gap) with default max-per-arc **9** |
| Persistence behavior | trio of top-level use cases load/save/**clear** over `SecureKeyStore` (`orbit3_dimension_preferences_use_cases.dart:8-33`); screen writes on EVERY stepper tap unconditionally — no change-detection, no debounce (`orbit3_screen.dart:346-396`); restore is fire-and-forget in initState so a slow read visibly snaps geometry after first paint (:141-159) |
| Arch math | `orbit3_arch_layout.dart`: 13 inner seats (:10-14), arch avatar base 36px (:18), stagger rowFromBottom×60 + col×4ms (:23-29), row math with dome dip (:57-83); screen derives `rowHeight = base + 14·spacing`, `dip = (base·0.32·curve).clamp(4, rowHeight/2)` (`orbit3_screen.dart:484-498`). Dotted connector `0x9981E6D9`, stroke 1.6, dash 1.4/5 (`orbit3_arch_panel.dart:336-367`). The lab has **rows/domes, not concentric arcs** — the arc math exists only in the 198 mockup |
| Search | reaches only the inner circle + constellation; `Orbit3ArcRow` has no `searchQuery` param (`orbit3_arch_panel.dart:154-187`, ctor site `orbit3_screen.dart:535-552`); match = glow blur 16 + forced label, non-match = opacity 0.28 (`orbit3_one_circle.dart:157-242`) — the proven lit/dim treatment 198 reuses; scroll-to-reveal machinery exists (`getOffsetToReveal`, `orbit3_screen.dart:306-344`) but deliberately maroons the circle below the fold |
| Known weaknesses | arch avatars have NO tap floor (bare `SizedBox`, down to ~22px — `orbit3_arch_panel.dart:266-272`); steppers always-on covering the canvas (:851-877); double-tap-anywhere costs every member tap one double-tap timeout (:511-517); all positioning physical/LTR-frozen (zero `PositionedDirectional` in orbit3); circle↔arch gap hardcoded `2·spacingScale` — no independent gap knob (:560) |
| Reachability | `kOrbit3PrototypeEnabled = kDebugMode` (`orbit3_prototype.dart:16`, source-guard-tested); mock data only (populations 5/13/24/50/100); nothing 198 needs is production-wired — porting means building against `lib/features/orbit` |
| Kept orbit2 models | `orbit2_inner_item`/`orbit2_friend`/`orbit2_group`/`avatar_tier` etc. survive for orbit3's use only; 197's plan doc locks "do NOT import orbit2/orbit3 prototype types" into production |

### 3.3 Persistence & account-Move machinery

- `SecureKeyStore` (fully async read/write/delete/containsKey, `secure_key_store.dart:6-11`) backed by iOS Keychain / Android EncryptedSharedPreferences (`flutter_secure_key_store.dart:13-38`); single instance built at `main.dart:462` and constructor-threaded (no locator).
- The canonical preference shape: model owns `storageKey` + codec with defaults-on-corrupt; top-level use-case functions taking `required SecureKeyStore` (`background_preference_use_cases.dart:7-23` = the pair archetype; the orbit3 trio adds `clear` = the Reset archetype).
- **Move registry**: keys register as `MigrationSecureStorageKey` entries in `_fixedKeys` (`migration_secure_storage_registry.dart:16-114`; example entry :53-59 — `policy: migrate, criticality: optional`) plus a new member in the CLOSED `MigrationSecureStorageKeyCategory` enum (`migration_secure_storage_key.dart:5-20`). Export iterates **registry-resolved keys only** (`account_migration_bundle_transfer.dart:325-353`); the only discovered additions come from DB rows. **An unregistered key is never read, never enters the bundle, and is simply absent on the new phone.** `orbit3_dimension_preferences_v1` is NOT registered (grep: zero orbit3 references under `lib/features/account_migration`) — the 198 knobs inherit silent-drop-on-Move unless registered. Existing preference-key registrations ARE test-locked (`migration_secure_storage_registry_test.dart:10-70` pins background/image/video-quality keys with policy/criticality), but no test enforces registration **completeness** — nothing fails when a new preference key is never added to the registry, which is exactly how the orbit3 key fell through.
- 193's `OrbitViewMode` is doc-locked non-persistent — 198's knobs would be the **first persisted state on the production Orbit screen**.
- UI feature gating precedent is compile-time only (`kOrbit3PrototypeEnabled = kDebugMode`); the Dart-map feature flags are transport-only (sent to Go on node:start).

### 3.4 Motion, haptics, accessibility, l10n conventions

- **Reduce-motion is only partially honored today**: `disableAnimations || accessibleNavigation` gates the 194 rotation only; node entrances and the badge entrance always animate (`orbital_visualization.dart:58-60` vs `orbital_avatar.dart:86-94`, `overflow_badge.dart:31-33`). `orbit3_screen.dart:713` and the 194 `_syncMotionPreference` pattern show the correct seam. All NEW 198 motion (arc bloom, edit jiggle/pulse, dim fades, chip entrances) must honor it.
- **Haptics**: production orbit has ZERO haptic call sites; the app-wide vocabulary is `HapticFeedback.selectionClick` (incl. every orbit3 stepper) + `mediumImpact` (prototypes) only.
- **Tap floor**: 48px enforced twice for circle nodes (`orbital_visualization.dart:265-270`, `orbital_avatar.dart:105-110`); the badge (28px, no tap) and the lab's arch avatars are today's violators.
- **l10n**: full orbit key set exists en/ar/de (`app_en.arb:185-228,1186-1205`; ar carries full plural categories). Known gap: hardcoded `'Open chat with ${username}'` for non-unread friend nodes (`orbital_visualization.dart:208`). The design introduces new user-facing strings that must localize (en/ar/de + parity registration): edit banner, 5 handle names, badge Semantics ("N more people — tap to open"), −/+ stepper semantics, Reset, find placeholder, chip provenance ("ring 1"/"ring 2"/"arc N"), chip open-chat semantics. The l10n literal-scan test carries a pre-existing RED of exactly 3 orbit3 literals that must not grow.
- **RTL**: ring/arc trig is direction-agnostic; chrome is deliberately physical; the mockup's shared card requires **arc fill order to mirror under RTL** (the lab is LTR-frozen).

### 3.5 Existing tests and gates

| Test | What it locks today | Fate under this spec |
|---|---|---|
| `orbital_visualization_test.dart:268-289` 'center avatar and overflow badge do not open chat' | taps `OverflowBadge`, expects 0 callbacks — **actively locks the badge as inert** | **Superseded/rewritten** — badge becomes the arcs toggle (still must never open a chat); center-avatar half stays |
| `orbital_visualization_test.dart` (rest, 25 tests; 26 total in the file) | 5+8 seating, badge shows >13 / hides ≤13, per-ring tap routing, all 194 lit-node TCs (incl. TC-194-26 48px lit target, TC-194-24 reduce-motion freeze), 197 group-node TCs (incl. TC-197-07 combined overflow count) | Must stay green *(regression)* |
| `overflow_badge_test.dart` (4 render-only tests) | +N text, 28px circle, dashed paint, frosted glass | Extended — behavior tests become possible for the first time |
| `orbit_view_split_test.dart` (16 tests) | 193 default entry, toggle both ways, rapid-toggle determinism, RTL/FAB clearance, re-entry reset, initialFilterTab override, 2 197 ring-node tests | Must stay green |
| `orbit_unread_indicator_wired_test.dart` (13 tests) | 194 wired: live light, dirty replay, TC-194-13 overflow-hidden lit friend jumps visible, TC-194-16 external-read clear [PROD-CRITICAL], INV-5, ticker hygiene | Must stay green |
| `orbit_qr_entry_migration_test.dart` + `orbit_qr_chrome_buttons_test.dart` | 196 chrome on both surfaces, FAB scrim precedence, RTL, intros deep-link | Must stay green |
| `inner_circle_items_test.dart` (2 tests) | 197 recency interleave + blocked-drop | Must stay green; overflow ordering builds on it |
| `orbit_wired_test.dart` (~74 tests, ~5100-line shared file) | wired host incl. list-search plumbing; its ONLY `longPress` targets a chat bubble (:4059), not the canvas | Must stay green; high collision risk |
| `orbit3_dimension_preferences{,_use_cases}_test.dart` | codec round-trip/clamp/defaults; save/load/clear trio | Untouched (lab stays); pattern donor for the 5-knob tests |
| `orbit3_arch_layout_test.dart`, `orbit3_screen_test.dart`, `orbit3_one_circle_arch_test.dart` | lab arch math, steppers, in-circle search glow | Untouched |
| `integration_test/orbit_performance_harness.dart` (`PERF_TARGET=ORBIT`) | **report-only** frame/timeline capture, 4 scenarios (8 no-overflow / 15 overflow badge window / 4-lit unread / 8+5 mixed); NO frame-budget asserts; 196-era quarantine **LIFTED** (tree compiles, verified 2026-07-03) | Must keep compiling; natural extension point (arches-open scenario) |
| Sims: `cold_start_message_render_simulator_test.dart:344-353` (asserts inner-circle default, taps `orbit-view-toggle`), `group_delete_preserves_friends_simulator_test.dart:283` | orbit preambles | Must stay green; :344-347 carries a stale pre-197 "viz is friends-only" comment |
| Gates | GROUP_TESTS pins 5 orbit files today (`run_test_gates.sh:227-251`, among them the 193/194/196 wired suites); `feature-host-all` auto-globs `test/features/**/*_test.dart` (`run_host_test_gates.sh:183-184`); `test/l10n/*` sits OUTSIDE that glob; perf gates `performance`/`performance-sim` (`run_test_gates.sh:344-355,463-491`) | Inventory for the plan's gate registration |
| Known absences | zero coverage (and zero behavior) for: badge tap, long-press on canvas, search-lights-nodes, geometry knobs on production, golden/screenshot tests (none exist orbit-wide); no fake-clock seam — timing tests drive `tester.pump(Duration)` against real timers | The 198 test surface is greenfield |

### 3.6 Branch context / hazards

- Working tree on `new-orbit` is dirty with uncommitted 193/194/196/197 work across `orbit_screen.dart`, `orbit_wired.dart`, `orbit_wired_test.dart`, l10n files, and `run_test_gates.sh`; check for other live sessions before editing shared files. Line numbers cited here are working-tree values and may drift.
- The graphify arch graph is **stale for the untracked 196/197 files** (no node for the current `orbit_wired.dart`); all claims in this spec were grep/read-verified in source. Run `./graphify-arch/refresh_arch_graph.sh` before graph-driven work on these files.
- The 196-era `PERF_TARGET=ORBIT` quarantine is lifted: `inner_circle_items.dart` exists and `dart analyze` over the harness + the orbit lib/test tree reports zero errors (5 minor pre-existing lints).
- Stale references that predate this spec (fix-as-you-go candidates, not 198 obligations): `test-gate-definitions.md:735` lists the old `orbit_performance_test.dart` filename; the cold-start sim comment claims the viz is friends-only; `OverflowBadge`'s doc says "friends" for a merged count; `orbit_search_trigger.dart` doc says 36×36.
- The 320×320 canvas is vertically centered with no reserved headroom; arcs above the circle depend on the documented slide-down + scroll behavior, and the "YOUR INNER CIRCLE" title (`orbital_visualization.dart:68-79`) occupies the band the first arc will use.

## 4. Scope Clarification

| Area | Status |
|---|---|
| +N badge: tap-to-toggle, 9-slot ring-2 re-spread, ≥44pt hit, chevron, Semantics | **In scope** |
| Concentric-arcs overflow rendering (radii/wrap/capacity per the design contract), collapse/expand, slide-down + scroll, entrance stagger | **In scope** |
| Arch nodes as first-class citizens: tap-to-chat, 194 unread, 197 groups, ≥44pt targets, labels | **In scope** |
| Long-press edit mode: entry/exit, dim, banner, Reset, 5 handles, arm + value bubble + −/+ nav-line steppers, tap-away | **In scope** |
| 5-knob model: ranges/steps/defaults; persistence across launches with safe fallback on corrupt/out-of-range stored data; Reset-to-defaults; **survival across account Move** | **In scope** |
| Inner-circle find: search pill, in-place lighting + 0.28 dim, ≤4 chip strip with provenance, groups included, auto-scroll reveal, zero-match no-dim | **In scope** |
| Edit × find composition; double-tap label toggle (no tap-latency regression) | **In scope** |
| New-string l10n (en/ar/de) + parity registration; Semantics for every new interactive element | **In scope** |
| Reduce-motion compliance for ALL new animation; haptic on edit entry (app vocabulary: selectionClick/mediumImpact) | **In scope** |
| Supersession of the badge-inertness test lock | **In scope** |
| All-chats list search behavior (filter-style, groups-dropped, dock/trigger) | **Unchanged** |
| 193 toggle + reset seam; 196 QR chrome; ExpandableFab; nav pill; conversation routes | **Unchanged** (regression-locked) |
| 194 indicator internals; 197 merge/ordering | **Unchanged** (arch nodes consume them as-is) |
| orbit3 lab code + its tests | **Unchanged** (stays debug-gated; NOT deleted, NOT shipped, NOT imported into production) |
| Persisting view mode, expansion state, or label visibility | **Out of scope** (193 design locks stand) |
| Stacked Domes (Q1-A), Tune Dock (Q2-A), Summoned Steppers (Q2-C), Come To Me (Q3-A), Open The Sky (Q3-B) | **Out of scope** — documented fallbacks/declined |
| Pre-existing hardcoded `'Open chat with…'` label (`orbital_visualization.dart:208`) | **Out of scope to fix globally**, but the gap must not spread: new 198 UI strings are all localized |
| Registering the ORPHANED `orbit3_dimension_preferences_v1` key for Move | **Out of scope** (lab-only data; flagged as cleanup candidate) |
| Frame-budget assertions in the perf harness | **Out of scope** (harness stays report-only per 194 precedent) |

## 5. Test Cases

IDs: `TC-198-NN`. "Badge" = the +N/chevron toggle. "Knobs" = av/sp/cv/pr/og. "Pill" = the inner-circle search pill. "Chips" = the result strip. Population fixtures use the 197 merged species (friends + groups). Geometry assertions assume the 390×844 logical reference surface unless stated. Tags: *(boundary)*, *(regression)*. Orbit suites must use bounded pumps (never `pumpAndSettle` with lit nodes) and the deterministic fixture builders per house convention.

### Group A — Badge & arc expansion (TC-198-01..13)

- **TC-198-01** — 14 merged items *(boundary: 13+1)*. Expected: badge renders "+1"; tapping it seats the 14th member on the first arc (r ≈ 154·sp band above the circle) and the badge shows its open/chevron state.
- **TC-198-02** — Exactly 13 items *(boundary)*. Expected: no badge, no arcs; all 13 seated; long-press edit still enters but only the two ring handles (av, sp) exist.
- **TC-198-03** — Overflow present, collapsed. Expected: ring 2's 8 members occupy 9 slots with the badge in the 9th — the badge's and seat-13's tap targets are disjoint and both individually hit-testable (today they overlap at ≈9.4px separation).
- **TC-198-04** — Badge accessibility. Expected: hit target ≥44pt (up from a 28px un-tappable visual); Semantics reports a button with the localized "N more people — tap to open" label (correct N; en/ar/de).
- **TC-198-05** — Collapse round-trip. Expected: tapping the open badge removes all arc nodes, restores the circle's default seat, and the badge shows "+N" again; a second expand works identically *(no one-shot state)*.
- **TC-198-06** — 24 items at default knobs. Expected: 11 overflow members distributed across arcs by the capacity formula — exactly 9 on arc 1, 2 on arc 2; the partial second arc's 2 seats are centered on its apex at full-arc pitch (not edge-packed); every arch avatar rendered exactly once; arcs alternate the teal/purple dashed ring vocabulary; nothing culled.
- **TC-198-07** — 50 items at default knobs *(boundary: deep stack)*. Expected: 37 overflow members over 4+ arcs; the circle slides down; the canvas scrolls (drag and/or scroll) so every arc AND the circle remain reachable — the circle is never marooned off-view with no way back.
- **TC-198-08** — Expansion is session-transient. Expected: expand → switch to Feed → return to Orbit: inner-circle view (193 reset) with arcs **collapsed**; no persistence of expansion.
- **TC-198-09** — Expansion under reduce-motion (`disableAnimations`). Expected: arc nodes appear without entrance animation frames (no staggered bloom); the surface reaches its final layout immediately.
- **TC-198-10** — Overflow group node (e.g. 12 friends + 3 groups, groups ranked 14th+). Expected: badge counts the merged overflow; the group's arc node renders its `GroupAvatar` (initials fallback included) and tapping it opens the group conversation *(197 parity on arcs)*.
- **TC-198-11** — Unread on an arc. Expected: an expanded overflow member with unreadCount > 0 shows the 194 indicator (ring + satellites) on its arc node; an externally-emitted conversation-read event for that member clears it while expanded *(194 parity on arcs)*.
- **TC-198-12** — Arch tap targets *(boundary at default knobs)*. Expected: every arc node's hit area ≥44 logical px despite 34px visuals — the lab's ~22px targets must not reappear.
- **TC-198-13** — Overflow ordering. Expected: arc seats fill in merged-recency order — seat 14 (arc 1, first seat) is the most recent overflow item, matching the `sortKey` ordering that seats the 13.

### Group B — Edit-mode lifecycle (TC-198-14..27)

- **TC-198-14** — Long-press 500ms on empty orbit space (expanded, overflow present). Expected: edit mode enters exactly once — banner ("TAP AWAY TO FINISH", localized; see product decision 11), Reset top-left, crowd dims to ~22%, five handles appear at their geometry seats, a haptic fires (app vocabulary).
- **TC-198-15** — Long-press directly on a node, and separately on the badge. Expected: neither enters edit mode; a plain tap on that node still opens its chat, and a plain badge tap still toggles the arcs.
- **TC-198-16** — Press, then move past the slop (~8px) before 500ms. Expected: long-press cancels; the gesture pans/scrolls the canvas instead; no edit mode.
- **TC-198-17** — Release the finger right after edit mode enters *(boundary: the release-click hazard)*. Expected: edit mode stays — the long-press-release must not count as the tap-away that exits.
- **TC-198-18** — Tap empty space while editing. Expected: edit exits — banner, handles, steppers, Reset all unmount; the dim lifts; the orbit is interactive again.
- **TC-198-19** — Tap a dimmed avatar while editing. Expected: exits edit mode; does NOT open that avatar's chat.
- **TC-198-20** — Tap a handle. Expected: it arms — visual state flips to the teal armed treatment, a live value bubble appears directly above it showing the current value, and the −/+ steppers appear on the nav-bar line (− left of the pill, + right).
- **TC-198-21** — Stepper stepping and clamping *(boundary)*. Expected: + increments the armed knob by its coarse step (av 0.2 / sp 0.1 / cv 0.1 / pr 1 / og 0.1), the bubble updates, the canvas re-renders, and each tap momentarily lifts the crowd dim (restoring afterward); at the range maximum, + leaves the value at the maximum (and − at the minimum) with no error.
- **TC-198-22** — Drag a handle. Expected: the knob changes continuously with the drag, the canvas re-renders live, the 22% dim lifts for the duration of the drag and restores afterward.
- **TC-198-23** — One continuous drag across the full range *(the rebuild hazard)*. Expected: a single uninterrupted gesture can take a knob from one bound to the other — live canvas re-renders never interrupt or cancel the in-flight drag.
- **TC-198-24** — Collapse the arcs while the wrap handle is armed. Expected: cv/pr/og handles disappear with the arcs, the armed state clears, the −/+ steppers hide; av/sp handles remain.
- **TC-198-25** — Reset. Expected: all five knobs return to defaults (1.0/1.0/1.0/9/1.0), the canvas re-renders to default geometry, and the edit session remains active (banner and handles still mounted — Reset is not the tap-away).
- **TC-198-26** — Edit while collapsed (≤13 or overflow-collapsed). Expected: only av and sp handles exist; both arm, step, and drag correctly.
- **TC-198-27** — Badge during edit. Expected: tapping the badge mid-edit expands/collapses the arcs WITHOUT exiting edit mode (the arch handles appear/disappear accordingly).

### Group C — Knob geometry semantics (TC-198-28..32)

- **TC-198-28** — Avatar knob at 0.6 and 1.4 *(boundary)*. Expected: ring and arc avatar visuals scale accordingly (arc = 34·av clamped 20–52); every tappable node keeps its ≥44px floor at both extremes.
- **TC-198-29** — Spacing knob at 1.5 *(boundary)*. Expected: ring radii and arc radii all scale by sp (arc-to-arc gap 46·sp) — **including the painted dashed ring/arc paths, not just the node seats** (the painter duplicates the geometry, §3.1); the layout stays collision-free at default av.
- **TC-198-30** — Wrap knob *(boundary at the pinch release)*. Expected: at cv ≤ 1.6 every arc avatar lies fully inside the 390×844 reference surface's width (width pinch φ ≤ asin(170/r)); at cv = 2.5 arcs reach up to 166°/side (a ~332° shell) whose two ends never meet at the bottom; edge avatars may clip the bezel only past 1.6.
- **TC-198-31** — Max-per-arc knob at 4 *(boundary)*. Expected: no arc holds more than 4 members; the same overflow total redistributes across more arcs; nothing culled.
- **TC-198-32** — Orbit-gap knob at 2.5 *(boundary)*. Expected: the circle→first-arc distance scales with og while the arc-to-arc spacing is unchanged (og multiplies only the first gap).

### Group D — Persistence & account Move (TC-198-33..38)

- **TC-198-33** — Sculpt, exit, remount the Orbit host. Expected: the sculpted five values are restored and applied to the rendered geometry (async restore permitted; no crash, no corrupt intermediate values).
- **TC-198-34** — Corrupt stored value (garbage / wrong arity / empty) *(boundary)*. Expected: defaults load; no exception; the surface renders normally.
- **TC-198-35** — Out-of-range stored values (e.g. av 9.0, pr 99) *(boundary)*. Expected: each field clamps into its range on load.
- **TC-198-36** — Reset persists. Expected: after Reset + exit, a fresh mount renders default geometry.
- **TC-198-37** — Account Move. Expected: sculpt on the source device, assemble a Move bundle, import on the destination — the destination renders the sculpted geometry (closing the silent-drop gap the orbit3 values demonstrate, §3.3); a never-sculpted source contributes no knob payload to the bundle.
- **TC-198-38** — Fresh state writes nothing. Expected: merely viewing/expanding the orbit (no edit session) creates no stored value; the first write happens only once the user actually edits.

### Group E — Find: pill, lighting, chips (TC-198-39..49)

- **TC-198-39** — Pill presence. Expected: the inner-circle surface shows the collapsed 40px search pill (bottom-right, above the nav band) with button Semantics and a localized label; tapping expands it (~200px) with keyboard focus in the field.
- **TC-198-40** — Single match within the 13. Expected: the matching node lights in place (glow + its name label forced visible) while every other node/badge dims to ~0.28; the strip shows one chip (avatar, name, "ring 1"/"ring 2" provenance).
- **TC-198-41** — Multiple matches *(boundary at the chip cap)*. Fixture: six members matching the query (case-insensitive substring — e.g. "na" matching Nadia/Rania/Dina/Hana/…), spanning rings and arcs. Expected: every on-canvas match lights simultaneously; exactly 4 chips render — the 4 most recent matches in merged-recency order; the orbit itself never re-seats.
- **TC-198-42** — Overflow match while collapsed. Expected: no auto-expand; the chip lists the hidden member with arc provenance ("arc 2"); tapping the chip opens that member's chat.
- **TC-198-43** — Overflow match while expanded, off-view (50 items, match on the farthest arc). Expected: the match lights on its arc AND the canvas auto-scrolls to reveal the topmost lit match.
- **TC-198-44** — Group match. Expected: typing a group's name lights its node (ring or arc), chips it with provenance, and tapping opens the group conversation — groups are first-class in find (unlike list search).
- **TC-198-45** — Clear and close. Expected: clearing the query (or closing the pill) removes all lighting, dim, and chips; the orbit returns to its normal state.
- **TC-198-46** — Zero matches *(the anti-signal ban)*. Expected: no node dims, no chips render — the surface must never show "everything dimmed, nothing highlighted".
- **TC-198-47** — Keyboard interplay. Expected: with the software keyboard up, the pill's input remains visible and editable (the screen's `resizeToAvoidBottomInset:false` + manual inset handling must cover the new input); results update per keystroke.
- **TC-198-48** — Tap-away from search. Expected: tapping outside the pill/chips closes and clears the search.
- **TC-198-49** — Surface interplay *(regression)*. Expected: toggling to all-chats closes/clears the circle find; the all-chats list search behaves exactly as today (filter-style, groups dropped); Feed→Orbit re-entry lands with find closed and cleared.

### Group F — Composition & labels (TC-198-50..55)

- **TC-198-50** — Search while editing. Expected: typing in the pill does NOT exit edit mode; the lit match renders at full brightness while the rest of the crowd holds the 22% edit dim; the match stays lit across a knob drag's re-renders.
- **TC-198-51** — Pill/chip interaction during edit. Expected: tapping the pill, typing, and tapping chips never count as the edit tap-away; tapping empty canvas space ends BOTH the edit session and the search.
- **TC-198-52** — Chip tap during edit. Expected: the chat opens; the edit session ends with the current knob values persisted (no edit overlay behind the pushed route; values present after return + remount).
- **TC-198-53** — Double-tap empty space. Expected: name labels appear under every node (rings and arcs, friends and groups), staggered on alternate seats so adjacent labels don't overlap; a second double-tap hides them; labels default off and reset on re-entry.
- **TC-198-54** — No tap latency from the double-tap arena *(the lab's documented weakness)*. Expected: a single tap on a node opens its chat without waiting out a double-tap timeout.
- **TC-198-55** — Double-tap on a node or the badge. Expected: does not toggle labels via those elements' own gestures being swallowed — node taps and badge taps keep their primary behaviors.

### Group G — Accessibility, l10n, RTL, motion (TC-198-56..61)

- **TC-198-56** — Semantics sweep with `ensureSemantics()`. Expected: badge (button, localized count label), pill (button/textfield), each visible handle (labeled control), −/+ steppers (buttons, decrease/increase semantics), Reset (button), each chip (button naming the member) all present; arch nodes expose the same button semantics as ring nodes.
- **TC-198-57** — l10n parity. Expected: every new user-facing string resolves via localization in en/ar/de (banner, handle names, badge label, provenance, placeholder, Reset); the parity test covers the new keys; the l10n literal-scan violation list does not grow beyond the 3 pre-existing orbit3 literals.
- **TC-198-58** — Arabic locale (RTL). Expected: chrome stays physical per convention (no collisions among toggle/QR/FAB/pill/chips/steppers); **arc seat fill order mirrors** (first seat starts from the mirrored side); all layers render without overflow errors.
- **TC-198-59** — Reduce-motion sweep. Expected: with `disableAnimations`, the arc bloom, edit-mode pulse/jiggle, dim fades, and chip entrances are suppressed (instant states); the 194 unread ring stays frozen-but-visible *(regression)*.
- **TC-198-60** — Large text scale (2.0×) *(boundary)*. Expected: banner, value bubbles, chips, and provenance labels render without RenderFlex overflow errors.
- **TC-198-61** — Label-gap containment. Expected: arch friend nodes reuse the exact ring-node semantic labels (the pre-existing hardcoded-English gap at `orbital_visualization.dart:208` does not spread to new call sites; unread labels stay localized).

### Group H — Regression & performance (TC-198-62..68)

- **TC-198-62** — ≤13 default parity *(regression)*. Expected: with all knobs at defaults and ≤13 items, the rendered geometry is identical to today's (radii 62/108, avatars 38/30, 5+8 seating, no badge, no arcs); the only additions are the inert-until-used pill and gestures.
- **TC-198-63** — 193 locks *(regression)*. Expected: default entry inner-circle; toggle round-trips; Feed→Orbit rising edge resets view AND collapses arcs AND exits edit AND clears find — and a conversation-read event received while Feed was foregrounded still clears the lit node after that re-entry reset (194 dirty-replay parity, per TC-194-16's contract).
- **TC-198-64** — 194 locks *(regression)*. Expected: TC-194-13 (overflow-hidden lit friend jumps into the 13) and TC-194-16 (external read clears the lit node) still pass; lit ring nodes keep 48px targets.
- **TC-198-65** — 196 chrome *(regression)*. Expected: with arcs expanded and the canvas scrolled, the QR twins/toggle/FAB remain fixed and tappable; an OPEN FAB scrim still wins taps over the badge, handles, and pill.
- **TC-198-66** — 197 locks *(regression)*. Expected: merged ordering, group ring nodes, and the combined overflow count (TC-197-07) still pass.
- **TC-198-67** — Badge-lock supersession. Expected: the rewritten inertness test asserts the center avatar still never opens a chat AND the badge toggles the arcs but never opens a chat itself.
- **TC-198-68** — Perf lane. Expected: `PERF_TARGET=ORBIT` compiles and its 4 existing scenarios run; an added arches-open scenario (e.g. 50 items expanded, one knob drag, one search) reports frame timings (report-only — no budget asserts, per harness convention).

### Group I — Scroll interplay & composition hardening (TC-198-69..73)

- **TC-198-69** — Pan-release is not a tap *(boundary: the pan-release-as-tap hazard)*. 50 items expanded. Expected, for a drag-scroll whose release lands over interactive elements: (a) no chat opens for the node under the finger; (b) an active edit session does NOT exit; (c) an active find is NOT closed or cleared; (d) name labels do NOT toggle. Scrolling is the primary gesture on a deep stack — none of the tap-away/tap-to-open behaviors may fire from a scroll release.
- **TC-198-70** — Badge toggle while find is active. Query active with a collapsed overflow match (chip-only). Expected: tapping the badge to expand re-applies the find state to the new layout — the overflow match now lights on its arc with the 0.28 dim around it and its chip provenance stays correct; collapsing again falls back to chip-only with no half-state (never chips without the corresponding lighting/dim treatment).
- **TC-198-71** — Handles track the scrolling canvas. 50 items expanded, edit mode active. Expected: while scrolling, every visible handle stays anchored to its geometry seat; a handle whose seat leaves the visible stage band is hidden (never floats over the chrome or nav) and reappears anchored when scrolled back; an armed handle's armed state is unaffected by scroll visibility (only arc collapse disarms).
- **TC-198-72** — The circle stays visually planted while sculpting a deep stack. 50 items expanded, scrolled so the circle is on-screen. Expected: dragging og (or cv) so the arch stack grows or shrinks above the circle does not visibly displace the circle under the user's thumb — the scroll position compensates for the changing headroom.
- **TC-198-73** — Tapping nodes while find is active. Matches lit, others dimmed. Expected: tapping a lit node opens its chat; tapping a dimmed node opens that node's chat as well (dimmed ≠ disabled); in both cases the find state is closed and cleared by the time the user returns to the orbit.

---

*No solution content in this document by design; implementation belongs to the 198 TDD plan.*
