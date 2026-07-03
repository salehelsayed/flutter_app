# 198 - Orbit "Sculpt & Summon": concentric arcs, orbit handles, result chips — TDD plan  (New Feature)

Status: awaiting-review
Spec: [198-orbit-sculpt-and-summon-spec.md](198-orbit-sculpt-and-summon-spec.md) · Mockup contract: [198-orbit-arch-overflow-edit-find-mockups.html](198-orbit-arch-overflow-edit-find-mockups.html) (featured combined build `phone-hero` = arcs + handles + chips, html:1208)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-03 | Evidence Collector | Workflow `wf_e1760c56-da6` (21 agents: 5 ground explorers + 8 verify→refute claim pairs) over the live `new-orbit` working tree + mockup HTML | All 8 load-bearing claims verified; **C2 "gestures are free" REFUTED** (feed↔orbit host-swipe Listener); Move round-trip harness EXISTS; enum-compat hazard found | hand to Planner |
| 2026-07-03 | Planner | spec §1–5, tier-matrix, all workflow evidence | 73 TCs + 3 plan-added obligations (YIELD-1/2, SIM-PC) mapped to 6 new + 8 extended test files across unit/widget/wired/migration-host/sim/perf tiers | emit matrix + catalog |
| 2026-07-03 | Reviewer (sufficiency) | this plan vs `references/sufficiency-checklist.md` | see §Reviewer Findings | Arbiter |
| 2026-07-03 | Arbiter | — | plan structurally sufficient; open product flags listed in Accepted Differences | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec: `Test-Flight-Improv/198-orbit-sculpt-and-summon-spec.md` (73 TCs, groups A–I; §1 design-contract table)
- Mockup math (where the spec table under-specifies): `Test-Flight-Improv/198-orbit-arch-overflow-edit-find-mockups.html` — see §Design Contract Addendum below
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`

## Session Classification
implementation-ready

## Exact Problem Statement
The production Orbit Inner-Circle surface seats exactly 13 merged chats (5+8, `orbital_visualization.dart:32-38,61-63`); items beyond the 13th are never rendered and are represented only by a display-only 28×28 `+N` badge with no gesture handler, no Semantics, and a slot computed with count=9 against seats computed with count=8 — its center sits 2·108·sin(2.5°) ≈ 9.42px from seat 13's center, and its opaque 28px box sits essentially inside seat 13's 48px tap target, swallowing taps (verified C1). Geometry is compile-time consts duplicated across `orbital_visualization.dart` and `orbital_ring_painter.dart:8-9` (verified C4) with no tuning affordance. Search never reaches the Inner-Circle surface, and the all-chats list search drops groups whenever the dock is active (verified C3) — an overflow group has no chat-navigation search path anywhere.

198 ships the product-approved "Sculpt & Summon" build: (A) the badge becomes a toggle revealing overflow on concentric arcs (ring-2 re-spread 8→9 slots, ≥44pt, chevron, localized Semantics; arch nodes are first-class — tap-to-chat, 194 unread, 197 groups, ≥44pt); (B) 500ms long-press on empty space enters an edit mode with 5 geometry handles (av/sp/cv/pr/og) — tap-to-arm → value bubble + −/+ 48px nav-line steppers, drag for coarse moves, Reset, tap-away exit; the 5 knobs persist via SecureKeyStore AND survive account Move; (C) a find pill lights matches in place (dim 0.28), chips the first 4 in merged-recency order with ring/arc provenance, includes groups, never auto-expands.

What must improve: overflow reachability/visibility/a11y; geometry tunability (persisted, Move-proof); inner-circle find incl. groups.
What must stay unchanged (→ preserved-green sentinels): all-chats list search behavior; 193 toggle/reset seam; 196 chrome + FAB scrim precedence; 194 indicator internals; 197 merge/ordering; orbit3 lab (untouched, debug-gated); default geometry at knobs=1.0 (byte-identical seating, INV-6).

## Root Cause / Grounded Mechanism (verify → refute confirmed)
All current line numbers re-verified on the dirty `new-orbit` tree 2026-07-03 (workflow `wf_e1760c56-da6`):

1. **Badge inert + overlapping** — `overflow_badge.dart` (135 lines, zero GestureDetector/onTap/Semantics; sole param `count`; fixed 1000ms `Future.delayed` + 500ms entrance with no reduce-motion gate :25-33); mounted bare `Positioned` at `orbital_visualization.dart:158-172`, slot `index: ring2Items.length, count: ring2Items.length+1` (:161-162) vs seats' count=8; inertness test-locked by `orbital_visualization_test.dart:268-289`. The 9-slot re-spread mechanism already exists in embryo: `_positionOnRing` takes dynamic counts (:112,:138).
2. **No knobs** — consts `_size 320/_ring1Radius 62/_ring2Radius 108/_ring1Count 5/_ring2Count 8/_minTapTargetSize 48` (:32-38); radii independently re-declared in `orbital_ring_painter.dart:8-9` (only the radii are duplicated; colors/dash/glow :20,:30,:45-49,:58-59); production construction site passes no geometry (`orbit_screen.dart:541-547`).
3. **No inner-circle find** — trigger/dock render-gated `viewMode == OrbitViewMode.allChats` (`orbit_screen.dart:402,:428,:487-489`, comments :400-401,:425-427); list projection filters friends only and includes groups only `if (!_searchActive)` (`orbit_wired.dart:303-317`).
4. **Persistence/Move seam** — `SecureKeyStore` (4 async methods, no enumeration; `secure_key_store.dart:6-11`) already a required `OrbitWired` field (:112,:165, used at :539-551). Move exports ONLY registry-resolved keys (`account_migration_bundle_transfer.dart:325-353`; `_collectSecureEntries` loop :332, optional-missing silently skipped :348); import stages then promotes via `migration_secure_storage_staging.dart:75`; promotion keys derive from the bundle itself (:1918-1942) → **a newly registered key needs zero import-side wiring**. `orbit3_dimension_preferences_v1` is unregistered (grep: zero) and no completeness test exists (registry test = additive `containsAll` :21-37; source-audit test = hardcoded 10-key one-way set :25-36).
5. **Reset hook** — single-call-site `_resetToInnerCircleView()` (`orbit_wired.dart:504-509`) on the shell inactive→active rising edge (:489-494) — the one place 198's session-transient state (expansion/edit/find/labels) must also reset. Its search-force-close half (:506-508) has NO direct test today.
6. **Host-swipe conflict (REFUTED C2 — the plan-changing find)** — the whole Orbit pane lives inside the raw pointer `Listener` `ValueKey('feed-orbit-swipe-host')` (`feed_wired.dart:2722`) which claims ≥12px horizontal-dominant pointer travel and live-drags to Feed (velocity threshold 900 px/s, :249). Raw Listeners bypass the gesture arena; the codebase's own yield protocol is `_orbitRowActionOpen` (:311, set :2348) and `_feedCardSwipeActive` (:321, :2291-2296), consumed in the bail at :2397-2402. **198's handle drags (TC-198-22/23) and edit session must join this yield protocol** or a rightward handle drag slides the tab to Feed mid-sculpt.

Refuted / do-NOT-re-introduce:
- **"The 198 gestures are free / no arena conflicts"** (spec :15 prose) — REFUTED. Long-press/double-tap grep-clean claims hold, but the host-swipe Listener and the inner-circle `SingleChildScrollView`'s vertical-drag recognizer (`orbit_screen.dart:536`) both cover the canvas. Do not ship handle drags without the yield gate (rows YIELD-1/2).
- **"A group beyond seat 13 is findable by search nowhere in the app"** (spec :13/:72 prose) — overreach: the share/forward target picker searches groups by name (`share_target_picker_screen.dart:106-114`, production-reachable). It is a send-destination picker, not chat navigation, so the 198 design stands unchanged; do not cite the "nowhere" phrasing in code comments.
- **"Painter duplicates radii + colors + sizes"** maximal reading — only radii 62/108 are duplicated (`orbital_ring_painter.dart:8-9`); canvas/avatar/seat values live solely in the visualization. The reconciliation obligation (TC-198-29) is real but scoped to radii + painted paths.
- **Spec :147 "5 minor pre-existing lints"** — stale; `dart analyze lib/features/orbit` is clean today.
- The mockup's own deviations from the spec (chip tap focus-down html:1179-1184; node-tap-in-edit-exits-without-opening html:1221-1222) are spec-recorded product decisions #10/#7 — implement the SPEC, not the mockup, at those two points.

## Design Contract Addendum (mockup math the spec table omits — normative for implementation)
From the mockup recon (file:line into the HTML):
- **Wrap interpolation (exact)**: `phi(r,cv)`: base = min(2.9, 1.25·cv); if r ≤ 170 → base; else pinch = asin(min(1, 170/r)); release = clamp((cv−1.6)/0.9, 0, 1); result = min(base, pinch + (2.9 − pinch)·release) (html:731-736). Release target is PHI_FULL 2.9, not base.
- **Capacity divisor**: uses the CLAMPED pixel size — `cap = max(4, min(⌊2φr/(avPx+10)⌋, round(pr)))` with avPx = clamp(34·av, 20, 52) (html:742,:749-750). Equivalent to the spec's 34·av+10 inside the legal knob range.
- **Arc glow does NOT alternate**: crisp dash stroke alternates teal `0x4081E6D9`/purple `0x33A78BFA` (1.5px, dash 8/4) but the 8px blur-4 glow sublayer is always teal `rgba(129,230,217,0.08)` (html:753-756) — mirror `orbital_ring_painter.dart`'s fixed-teal glow convention.
- **Overhang / planted circle**: headroom MARGIN 30; arcs stack-top = cy₀ − maxR − avPx/2 − 16; overhang = max(0, ⌈30 − topY⌉) added to canvas height AND circle top; on expand/collapse compensate scroll offset by the headroom delta so the circle stays visually planted (html:769-806). Collapse is instant (stagger only on expand, html:807-809).
- **Drag sensitivities** (canvas px): sp = dy/108; av = −dy/90; cv = angle-follow |atan2(px−cx, cy−py)|/1.25 clamped 0.5–2.5; pr = round(dx/34); og = −dy/(46·sp) (html:1025-1040).
- **Pan/tap disambiguation**: 6px drag threshold before capture; a 350ms `justPanned` window rejects the release as tap/double-tap/tap-away/find-close (html:830-841,:852) → TC-198-69's mechanism.
- **Entrance must relinquish opacity to dim**: entering nodes shed their entrance animation state on completion and edit-entry strips in-flight entrances before dimming (html:820-822,:863) — the Flutter port must not let an entrance animation pin opacity above the 0.22/0.28 dims.
- **Auto-scroll reveal**: topmost lit match; fire when y < scrollTop+70 or y > scrollTop+stageH−90; scroll to max(0, y−140) (html:1161-1164) — treat 70/90/140 as tunable, assert only "off-view match becomes visible".
- **Chips-without-dim middle case**: matches exist but none on-canvas (collapsed overflow) → chips WITHOUT the 0.28 dim (dim gated on lit-count, html:1171-1174). Folded into TC-198-42/70 assertions.
- **Chip strip hit-testing**: the strip container must be hit-transparent; only chips tappable (html:267-269) — folded into TC-198-51.
- **Handle hosting**: handles are built once per edit session in a layer OUTSIDE the re-rendered/scrolled canvas, re-seated after every render and on scroll, hidden when their seat leaves the visible band, stacked above pill/chips (html:971-987,:1047-1054) → TC-198-23/71's mechanism.
- **Value formats**: `toFixed(1)×` for scalars, integer for pr (html:853-860). Handle tip strings → the 5 localized handle names.
- **Badge visuals**: chevron `⌄` in open state; hit target via inset −8px around the 28px visual (html:136-141).

## Real Scope
In scope (production edits):
1. **`lib/features/orbit/domain/models/orbit_geometry_prefs.dart`** (NEW) — 5-knob model: `avatarScale` 0.6–1.4/±0.2/1.0, `spacingScale` 0.7–1.5/±0.1/1.0, `arcWrap` 0.5–2.5/±0.1/1.0, `maxPerArc` 4–9/±1/**9**, `orbitGap` 0.5–2.5/±0.1/1.0; `storageKey = 'orbit_geometry_prefs_v1'` (NEW key — the orbit3 arity-4 key is unusable and stays orphaned); pipe codec arity-5, defaults on null/empty/wrong-arity/unparseable, per-field clamp on decode (shape donor: `orbit3_dimension_preferences.dart:43-66`; REBUILT, never imported).
2. **`lib/features/orbit/application/orbit_geometry_prefs_use_cases.dart`** (NEW) — load/save/clear trio over `SecureKeyStore` (donors: `background_preference_use_cases.dart:7-23`, orbit3 trio :8-33). Call-site change detection: no write when the value didn't change (bans the lab's write-on-noop, `orbit3_screen.dart:346-396`).
3. **`lib/features/orbit/domain/orbit_arc_layout.dart`** (NEW, pure) — arc radius rₖ=(108+46·og+46k)·sp; avPx clamp; exact phi pinch-release; capacity; pitch + partial centering; 12-o'clock polar seats; RTL mirror of fill order; badge 9-slot re-spread angle; overflow→(arc,seat) assignment in merged-recency order; overhang; entrance delay arcI·60+seat·5ms; provenance (`ring 1`/`ring 2`/`arc N`).
4. **`lib/features/orbit/application/orbit_find_matches.dart`** (NEW, pure) — trimmed case-insensitive substring on display name over merged items (friends + groups); first-4 chips in merged-recency order; provenance via layout.
5. **`overflow_badge.dart`** — `onTap`, `expanded` chevron state, localized plural Semantics, ≥44pt hit target, reduce-motion gate on the entrance; doc fix ("friends" → merged).
6. **`orbital_visualization.dart`** — accepts `geometry`, `overflowExpanded`, `onBadgeTap`, `labelsVisible`, find state; 9-slot ring-2 re-spread on overflow; arc layers (nodes = same `OrbitalAvatar` species: 194 indicator, 197 group avatars, 48px floor, localized labels); knob-scaled radii/avatar sizes; passes `motionEnabled` (closing the entrance reduce-motion gap for NEW motion).
7. **`orbital_ring_painter.dart`** — parameterized radii (knob-scaled from one source of truth) + arc path painting (alternating dash, fixed teal glow).
8. **`orbit_screen.dart`** — inner-circle surface gains: `ScrollController` + top-anchored layout on the scroll view (NEW seam — today `Center > SingleChildScrollView` has no controller, :535-537); background gesture layer (long-press enter-edit, double-tap labels, tap-away); edit overlay (banner "TAP AWAY TO FINISH", Reset top-left, dim 0.22 nodes / 0.45 rings, 5 handles hosted OUTSIDE the scrolled canvas, value bubble, −/+ 48px steppers flanking the nav pill); find pill (bottom-right, 40→~200px) + chip strip; scroll compensation (planted circle); ALL new layers mounted BEFORE the ExpandableFab (scrim-wins-taps inherited for free, :499-515).
9. **`orbit_wired.dart`** — knob state (async restore on mount; write-through with change detection; Reset = clear key); expansion/labels/find session state; `_resetToInnerCircleView` extension (collapse arcs + exit edit + clear find + labels off, :504-509); chip/node tap → existing friend (:1997-2043) / group (:2467-2519) routes; spec decision #7 (open-while-editing ends edit, knobs persisted); edit-session-active callback up to the host.
10. **`feed_wired.dart` + `orbit_wired.dart` callback** — `_orbitEditSessionActive` yield gate mirroring `_orbitRowActionOpen` (:311,:2348) / `_feedCardSwipeActive` (:321,:2291-2296) into the host-swipe bail (:2397-2402). Channel: new `OrbitWired` param `onEditSessionActiveChanged` (precedent: `onRowActionOpenChanged`, `orbit_wired.dart:142,:189`, invoked :379/:383/:2274), invoked on edit enter/exit/dispose, wired at the `OrbitWired` construction site `feed_wired.dart:2568`.
11. **Move registry** — `migration_secure_storage_key.dart`: new closed-enum member `orbitGeometryPreferences`; `migration_secure_storage_registry.dart` `_fixedKeys`: entry (scope primary, activeKey `OrbitGeometryPrefs.storageKey`, policy **migrate**, criticality **optional** — optional is forced: critical would break every Move from a never-sculpted phone, bundle :342-348).
12. **l10n** en/ar/de + regen: `orbit_edit_banner`, `orbit_edit_reset`, `orbit_handle_ring_spacing`, `orbit_handle_avatar_size`, `orbit_handle_arc_wrap`, `orbit_handle_max_per_arc`, `orbit_handle_orbit_gap`, `orbit_edit_step_increase`/`orbit_edit_step_decrease` (placeholder = handle name), `orbit_overflow_badge_open` (plural "{count} more people — tap to open"), `orbit_overflow_badge_collapse`, `orbit_find_placeholder`, `orbit_find_pill_semantics`, `orbit_chip_provenance_ring`/`orbit_chip_provenance_arc` (int placeholder), `orbit_chip_open` ({name}).
13. **Perf harness** — 5th `_OrbitScenario` (50 items → expand → one knob drag → one find query; report-only) PLUS the struct/host extension it needs: an optional per-scenario `interaction` hook run by `_runScenario`, and the `_OrbitRouteScreen` host extended to thread the new 198 params (see F13 — a bare list append at :435-471 cannot express the actions).
14. **Sim fold (0 new builds)** — new testWidgets case in `integration_test/cold_start_message_render_simulator_test.dart` (already registered: discovery :284-288, OPTIONAL_MANUAL_TESTS run_test_gates.sh:315; seeds via `FakeContactRepository.seed`, :119): seed 14+ chats → badge visible → tap → arc node → tap → conversation opens → back → find pill query → chip → group chat opens. **PROD-CRITICAL leg** (real render/gesture/route pipeline on the iOS simulator).
15. Fix-as-you-go stale docs: cold-start sim :346 pre-197 comment; `orbit_search_trigger.dart:5` "36x36".
16. **`scripts/run_test_gates.sh`** — add `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart` to the readonly `GROUP_TESTS` array (:209-251) so the new headline wired suite runs under the curated `groups` gate (glob will NOT add it).

Out of scope (owner):
- All-chats list search changes; 193/194/196/197 internals (their sessions own them; regression-locked here).
- orbit3 lab: untouched, incl. NOT extracting `orbit3_arch_layout.dart` (arc math is new; dome math unused) and NOT registering `orbit3_dimension_preferences_v1`.
- Tolerant `_enumByName` import hardening (skip-unknown-category) — flagged follow-up, future migration-hardening session (see Accepted Differences).
- Fixing the 3 pre-existing orbit3 literal-scan violations; the hardcoded `'Open chat with …'` at `orbital_visualization.dart:208` globally (new 198 call sites are localized; the old one stays).
- Frame-budget asserts in the perf harness (report-only per 194 precedent).
- Persisting view mode / expansion / labels (193 doc lock, `orbit_view_mode.dart:8-9`).

## Files To Inspect Next
Production: `orbital_visualization.dart`, `overflow_badge.dart`, `orbital_avatar.dart`, `orbital_ring_painter.dart`, `orbit_screen.dart`, `orbit_wired.dart`, `feed_wired.dart` (:249,:311,:321,:2291-2296,:2348,:2397-2402,:2722), `inner_circle_items.dart`, `orbit_item.dart`, `unread_orbit_indicator.dart`, `secure_key_store.dart`, `background_preference_use_cases.dart`, `migration_secure_storage_registry.dart`, `migration_secure_storage_key.dart`, `account_migration_bundle_transfer.dart` (:325-353,:1918-1942), `migration_secure_storage_staging.dart` (:56-94), l10n ARBs.
Direct tests + integration: the 8 extended files in §RED catalog; `orbit_unread_indicator_wired_test.dart` harness helpers (`buildOrbitWired` :196, `pumpOrbitFrames` :245, `setLargeTestSurface` :164); `orbital_visualization_test.dart` builders (`_makeFriend` :19, `_makeGroup` :40, `pumpBounded` :85, `wrapMq` :92); `account_migration_bundle_transfer_test.dart` round-trip donor (:1016-1212, `_requiredSourceKeys` :2394-2399); `feed_swipe_test.dart`.
Dependency-only: `expandable_fab.dart` (:123-155), `orbit_search_dock.dart` (viewInsets self-padding donor :30-33), `orbit3_one_circle.dart` (:157-242 lit/dim constants donor), `orbit3_screen.dart` (:346-396 anti-donor).

## Existing Tests Covering This Area
- `orbital_visualization_test.dart` (26 testWidgets) — seating/badge-visibility/tap-routing/194/197 TCs; **:268-289 actively locks badge inertness (superseded by TC-198-67)**.
- `overflow_badge_test.dart` (4, render-only; every test drains the 1000ms entrance timer).
- `orbit_view_split_test.dart` (16) — 193 locks incl. re-entry reset :658-703, rising-edge-only :705-739. Search-force-close on reset: NO direct test today (TC-198-49/63 add it).
- `orbit_unread_indicator_wired_test.dart` (12+1) — TC-194-13 :372-420, TC-194-16 PROD-CRITICAL :422-456; bounded `pumpOrbitFrames` convention.
- `orbit_qr_entry_migration_test.dart` (18) + `orbit_qr_chrome_buttons_test.dart` (9) — 196 locks incl. FAB scrim :528, scroll-fixed chrome :724.
- `inner_circle_items_test.dart` (2) — 197 merge order/blocked-drop (TC-198-13 builds on it).
- `orbit_wired_test.dart` (74 testWidgets, 5146 lines) — wired host + list-search plumbing (TC-198-49's regression half); only `longPress` is :4059 (chat bubble).
- `feed_swipe_test.dart` + `feed_wired_test.dart` — host-swipe coverage (YIELD rows extend the former).
- Migration: `migration_secure_storage_registry_test.dart` (:10-87 additive containsAll), `migration_secure_storage_source_audit_test.dart` (:25-36 hardcoded set), `account_migration_bundle_transfer_test.dart` (27 tests; full round-trip :1016-1212 — **no preference-category key round-tripped anywhere today**), `account_migration_full_transfer_test.dart` (:388-396).
- l10n: `orbit_strings_parity_test.dart` (3 tests over `newOrbitKeys` :18-29, pinned in GROUP_TESTS :251); `l10n_integrity_test.dart` literal-scan :45-64 — **pre-existing RED with exactly 3 orbit3 literals** (`orbit3_screen.dart:1113` 'Reset dimensions to default', `:1132` 'Reset', `orbit3_arch_panel.dart:68` 'Collapse'); no waiver mechanism (verified: `semanticLabel:` forms don't match the scan regex, so the set is exactly 3).
- Perf: `orbit_performance_harness.dart` — 4 scenarios :435-471, report-only :300, dispatch `performance_harness.dart:54-56`; analyzer-clean on the working tree (quarantine lifted).
- Sims: `cold_start_message_render_simulator_test.dart` (orbit preamble :344-353; FakeContactRepository seeding :119) — the 198 sim fold target.
Missing coverage gaps (greenfield): badge tap; long-press/double-tap on canvas; production knob geometry; find-lights-nodes; chips; drag/scroll interplay (no `startGesture` on any orbit canvas test); textScaler in orbit tests; golden infra ABSENT repo-wide → all geometry assertions are coordinate-math (`getRect`/`getTopLeft`), house style.
Already in curated family arrays: `orbit_wired_test.dart`, `orbit_view_split_test.dart`, `orbit_unread_indicator_wired_test.dart`, `orbit_qr_entry_migration_test.dart`, `test/l10n/orbit_strings_parity_test.dart` in `GROUP_TESTS` (`run_test_gates.sh:227,:241,:246,:250,:251`).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
Convention: for brand-new APIs, the same commit that adds a RED file adds the minimal inert skeleton (types/params exist, behavior absent) so REDs fail on ASSERTIONS, not compilation. All orbit widget/wired tests use bounded pumps (`pumpBounded`/`pumpOrbitFrames`), never `pumpAndSettle` with lit nodes; badge tests drain the 1000ms entrance timer; wired tests reuse `setLargeTestSurface`/`suppressOverflowErrors`/`buildOrbitWired`.

**F1. `test/features/orbit/domain/orbit_arc_layout_test.dart` (NEW, ~13 tests, unit, AUTO)**
Pure-math locks: radius formula (og scales first gap only — TC-32); avPx clamp (TC-28 math); exact phi pinch/release incl. cv 1.6/2.5 boundaries and never-meet-at-bottom (TC-30); capacity max(4, min(⌊2φr/(avPx+10)⌋, pr)) (TC-31); pitch + partial-arc centering and 24→[9,2] distribution (TC-06); 50→37-over-4+-arcs, nothing culled (TC-07 math); merged-recency seat assignment (TC-13); RTL fill mirror (TC-58 math); on-surface containment for cv ≤ 1.6 at 390px (TC-30); overhang/planted-circle delta (TC-72 math); entrance delays (TC-198-09's non-motion half); provenance mapping incl. beyond-envelope rule (chips). RED: functions absent/skeleton returns empty. Mutations: per-row below (e.g. drop the asin pinch → TC-30 red; drop `max(4,…)` → TC-31 red; center partial arcs at edge → TC-06 red).

**F2. `test/features/orbit/domain/orbit_geometry_prefs_test.dart` (NEW, ~6 tests, unit, AUTO)**
Codec round-trip (arity-5); defaults on null/empty/wrong-arity/unparseable (TC-34); per-field clamp on decode (av 9.0→1.4, pr 99→9 — TC-35); defaults 1.0/1.0/1.0/9/1.0 + coarse steps as consts (TC-21 math); step-and-clamp helper (bounds saturate, no throw — TC-21 math). RED: model absent. Mutation: remove decode clamp → TC-35 red; change pr default to 7 → defaults test red.

**F3. `test/features/orbit/application/orbit_geometry_prefs_use_cases_test.dart` (NEW, ~4 tests, unit, AUTO)**
Save/load round-trip; empty store → defaults; clear deletes key → defaults (TC-36's persistence half); corrupt stored string → defaults, no throw (TC-34's store half). Donor: `orbit3_dimension_preferences_use_cases_test.dart` + `FakeSecureKeyStore` (`test/core/secure_storage/fake_secure_key_store.dart:4-22`). RED: trio absent. Mutation: make clear() write defaults instead of delete → clear test red.

**F4. `test/features/orbit/application/orbit_find_matches_test.dart` (NEW, ~6 tests, unit, AUTO)**
Case-insensitive substring on display name; trimmed/empty query = no find state; groups included (TC-44 math); first-4 chips in merged-recency order (TC-41 math); zero matches (TC-46 math); provenance strings. RED: function absent. Mutation: filter groups out → TC-44 red; slice by name order → TC-41 red.

**F5. `test/features/orbit/presentation/widgets/orbital_arcs_test.dart` (NEW, ~17 tests, widget, AUTO)**
Reuses `_makeFriend`/`_makeGroup`/`wrapMq`/`pumpBounded` donors. TC-198-01 badge tap seats item 14 on arc 1 + chevron; TC-02 no badge/arcs at 13; TC-05 collapse round-trip twice; TC-06 render half (11 nodes once each; alternating dash paint, fixed teal glow); TC-09 reduce-motion expansion (no intermediate entrance frames under `disableAnimations`); TC-10 group arc node renders `GroupAvatar` + fires group tap callback; TC-11's render half (unread indicator on arc node); TC-12 arc hit areas ≥44px; TC-13 seat-14 = most recent overflow item (`getRect` vs layout); TC-28 avatar scaling at 0.6/1.4 with 44px floors; TC-29 ring+arc painted paths scale with sp (painter predicate asserts knob-scaled radii); TC-58 RTL mirrored fill; TC-61 arc friend nodes reuse ring-node semantic labels; TC-62 default parity (positions at knobs=1.0 equal today's 62/108/5+8 values, no badge ≤13); plus label-toggle render (TC-53's per-node half) and entrance-relinquishes-opacity-to-dim. RED on HEAD: `OrbitalVisualization` accepts no geometry/expansion params; badge untappable; finders find nothing. Mutations per matrix.

**F6. `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart` (NEW, ~36 tests, wired widget — ADD TO `GROUP_TESTS`)**
Harness cloned from `orbit_unread_indicator_wired_test.dart` (buildOrbitWired + FakeSecureKeyStore + fake repos + pumpOrbitFrames) **PLUS a `GroupMessageListener`** (construction donor: `cold_start_message_render_simulator_test.dart:304-308,:326`) — the donor harness omits it and `_openGroupConversationFromModel` returns early when it is null (`orbit_wired.dart:2475-2482`), which would silently dead-end every group-route assertion (TC-198-10/44/52). Carries: Group B TC-14..27 (gesture lifecycle, arm/step/drag, Reset, tap-away, release-click, badge-mid-edit); TC-07 deep-stack scroll reachability; TC-08 expansion transient across Feed→Orbit; TC-11 read-event clears arc-lit node while expanded (conversationReadStream donor :422-456); Group D TC-33 remount restore / TC-36 Reset persists / TC-38 fresh-state-writes-nothing (spy store counts writes); Group E TC-39..49; Group F TC-50..55; TC-56 semantics sweep (ensureSemantics); TC-60 textScaler 2.0; TC-63 rising-edge reset extension + 194 dirty-replay parity; TC-65 FAB scrim wins over badge/handles/pill; Group I TC-69..73. RED on HEAD: none of the surfaces/gestures exist. Mutations per matrix.

**F7. EXTEND `test/features/orbit/presentation/widgets/orbital_visualization_test.dart` (+4, widget, AUTO)**
TC-03 9-slot re-spread with disjoint badge/seat-13 targets (both individually hit-testable; RED: centers 9.42px apart, badge box inside seat-13's 48px target); TC-04 badge ≥44pt + localized plural Semantics (RED: 28px, zero Semantics); **TC-67 REWRITE of :268-289**: center avatar never opens chat AND badge tap toggles arcs but never opens chat (RED: toggle half fails — badge does nothing); keep all 25 other tests green (sentinel).

**F8. EXTEND `test/features/orbit/presentation/widgets/overflow_badge_test.dart` (+3, widget, AUTO)**
Chevron open-state swap; onTap fires once per tap; reduce-motion entrance (no scale/fade frames under disableAnimations). RED: no onTap/expanded params; entrance unconditional (:25-33).

**F9. EXTEND `test/features/feed/presentation/screens/feed_swipe_test.dart` (+2, wired widget, AUTO)**
The suite already mounts the REAL `FeedWired` (:170-194) and drags the host to the orbit pane finding `OrbitalVisualization` inside it (:873-895) — activate the edit session by long-pressing empty canvas on the FeedWired-hosted orbit pane (inner-circle default view). YIELD-1: with the edit session active, a rightward-dominant drag on the orbit pane does NOT slide toward Feed (and the armed knob drag still applies). YIELD-2: after edit exits, the host swipe works again. RED: no `onEditSessionActiveChanged`/`_orbitEditSessionActive` channel exists — drag slides to Feed. Mutation: remove the gate from the `_onHostPointerMove` bail (:2397-2402) → YIELD-1 red.

**F10. EXTEND migration suites (host, AUTO + move-feature glob)**
(a) `migration_secure_storage_registry_test.dart`: pin `orbit_geometry_prefs_v1` (scope primary, category orbitGeometryPreferences, policy migrate, criticality optional). RED: entry absent. Mutation: remove registry entry → red (THE TC-37 mutation).
(b) `migration_secure_storage_source_audit_test.dart`: add the key to `expectedFixedKeys` (:25-36). RED immediately on HEAD: the test asserts BOTH the source literal exists in lib AND registry membership per key — the source-literal assert fails first.
(c) `account_migration_bundle_transfer_test.dart` (+2): clone :1016-1212 round-trip — seed `orbit_geometry_prefs_v1` = '0.8|1.2|1.3|5|1.5' on sourceStore → assemble → stream → complete → acceptOldBlockProof → assert destinationStore.read == the sculpted string (promotion writes it, staging :75; note the ACTIVE key is observable only AFTER `acceptOldBlockProof` — after `complete` alone only the staging-prefixed key exists, donor :1081-1089); second test: never-sculpted source → bundle metadata carries NO entry for the key and import succeeds (optional skip :348). RED: unregistered key never enters the bundle → destination read null.

**F11. EXTEND `test/l10n/orbit_strings_parity_test.dart` (3 tests, keys list +16 — registration: already pinned in GROUP_TESTS :251)**
Sequenced in two steps (only block 1 of the test iterates `newOrbitKeys`; blocks 2–3 are hardcoded generated-API getter calls, :56-91): **RED step** = add all §Real-Scope-12 keys to `newOrbitKeys` (:18-29) only — block 1 fails on assertions (keys absent from ARBs) while the file still compiles. **GREEN step (Slice A, after `flutter gen-l10n`)** = add the 16 per-key generated-API invocations to blocks 2–3 with correct plural/placeholder arities (`orbit_overflow_badge_open` plural, `orbit_edit_step_*`/`orbit_chip_provenance_arc`/`orbit_chip_open` placeholders). Adding block-2 getters before regen breaks compilation — do not. Mutation: drop the ar translation of any key → block-1 parity red.

**F12. EXTEND `integration_test/cold_start_message_render_simulator_test.dart` (+1 testWidgets, simulator, PROD-CRITICAL — registration: NONE NEEDED, file already classified (discovery :284-288) + pinned (run_test_gates.sh:315); build-cost delta: 0)**
'198 orbit overflow: badge expands arcs, an overflow chat opens, find chips a hidden group': seed 14 friends + 1 group via `contactRepo.seed`/`groupRepo.saveGroup` (:119,:154) → badge "+2" visible → tap → arc nodes present → tap overflow node → conversation route pushed → back → pill query → chip with provenance → group conversation opens. RED: badge tap does nothing on HEAD. Mutation: revert badge onTap wiring → red. Bounded pump loops per the file's convention (:340-356).

**F13. EXTEND `integration_test/orbit_performance_harness.dart` (+1 scenario + struct/host extension, perf, registration: NONE — `*_performance_harness.dart` self-classifies ignored, discovery :151)**
`orbit_open_arcs_expanded_sculpt_find`: 50 items → expand → one knob drag → one find query; report-only. **NOT a bare list append**: `_OrbitScenario` is data-only (id/friends/groups/expectOverflow/expectUnreadIndicator, harness :81-95) and `_runScenario` is a fixed open→assert→close script (:284-323) over a host that builds `OrbitScreen` directly, bypassing `OrbitWired` (:229-263). Required: (a) add an optional `Future<void> Function(WidgetTester)? interaction` field to `_OrbitScenario`, executed inside `_runScenario` between open and close; (b) extend the `_OrbitRouteScreen` host state to own the new geometry/expansion/find params + callbacks (or swap the host to `OrbitWired`). RED-ish: scenario id absent (structural). Mutation: remove the scenario entry → harness reports 4 scenarios again (gate output count).

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
Gate shorthands (literal commands in §Acceptance Gates): **[U]**=`flutter test <file>` (direct), **[FH]**=`./scripts/run_host_test_gates.sh feature-host-all`, **[GR]**=`./scripts/run_test_gates.sh groups`, **[MV]**=`./scripts/run_test_gates.sh move-feature`, **[PF]**=`./scripts/run_test_gates.sh performance`, **[SIM]**=`flutter test integration_test/cold_start_message_render_simulator_test.dart -d "$FLUTTER_DEVICE_ID"`. Registration: **AUTO**=glob; **GT**=add to `GROUP_TESTS` array; **NONE**=already registered.

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Gate | Registration |
|---|---|---|---|---|---|---|---|
| TC-198-01 | badge gesture→arc render | widget | F5::'TC-198-01 badge tap seats item 14 on arc 1 + chevron' | badge has no onTap; arc finder findsNothing | remove onBadgeTap wiring | [U] F5 | AUTO |
| TC-198-02 | boundary 13 | widget | F5::'TC-198-02 thirteen items: no badge, no arcs' + F6::'TC-198-26/02 edit at ≤13 shows only av/sp handles' | overflow gate/edit absent | render badge at 13 (`>13`→`>=13`) | [U] F5+F6 | AUTO / GT |
| TC-198-03 | seat geometry | widget | F7::'TC-198-03 overflow re-spreads ring 2 across 9 slots; badge and seat 13 disjoint' | badge count=9 vs seats count=8 → 9.42px apart, overlapping hit boxes | restore `count: ring2Items.length` w/o re-spread | [U] F7 | AUTO |
| TC-198-04 | a11y | widget | F7::'TC-198-04 badge ≥44pt + localized plural semantics' | 28px, zero Semantics in file | drop Semantics wrapper | [U] F7 | AUTO |
| TC-198-05 | state round-trip | widget | F5::'TC-198-05 collapse round-trip ×2' | no toggle exists | latch expansion one-shot | [U] F5 | AUTO |
| TC-198-06 | pure math + render | unit+widget | F1::'24→[9,2] centered partial' + F5::'TC-198-06 24 items: 11 arc nodes once each, alternating paint' | layout fn absent; nodes never rendered | edge-pack partial arcs / double-seat a member | [U] F1+F5 | AUTO |
| TC-198-07 | deep stack + scroll | wired | F6::'TC-198-07 50 items: 4+ arcs, circle reachable, canvas scrolls' (math: F1) | items[13:] never rendered; no ScrollController on surface (orbit_screen:536) | cull arcs beyond viewport | [U] F6 | GT |
| TC-198-08 | lifecycle transient | wired | F6::'TC-198-08 expansion resets on Feed→Orbit rising edge' | expansion state doesn't exist | persist/skip reset of expansion in `_resetToInnerCircleView` | [U] F6 | GT |
| TC-198-09 | reduce-motion | widget | F5::'TC-198-09 expansion under disableAnimations is instant' | no arcs; entrance would be unconditional (badge precedent :25-33) | drop motion gate on arc entrance | [U] F5 | AUTO |
| TC-198-10 | 197 parity on arcs | widget | F5::'TC-198-10 overflow group node renders GroupAvatar, tap fires group callback' (initials-fallback clause rides GroupAvatar's own suite — composition) | no arc rendering | fork arc nodes friend-only | [U] F5 | AUTO |
| TC-198-11 | 194 parity on arcs | wired | F6::'TC-198-11 unread indicator on arc node; external read clears while expanded' | no arc nodes; read-seam untested on arcs | stop threading unreadCount to arc nodes | [U] F6 | GT |
| TC-198-12 | tap floor | widget | F5::'TC-198-12 every arc hit area ≥44px' | lab's ~22px targets are the donor hazard; no floor exists | remove 44px floor on arc nodes | [U] F5 | AUTO |
| TC-198-13 | ordering | unit+widget | F1::'overflow seats fill merged-recency' + F5::'TC-198-13 seat 14 = most recent overflow item' | assignment fn absent | sort overflow by name | [U] F1+F5 | AUTO |
| TC-198-14 | gesture entry | wired | F6::'TC-198-14 500ms empty-space long-press enters edit once (banner, Reset, dim, 5 handles, haptic)' | zero long-press in production orbit (C2 verify) | remove onLongPressStart | [U] F6 | GT |
| TC-198-15 | gesture scoping | wired | F6::'TC-198-15 long-press on node/badge does not enter edit; taps keep primary behavior' | RED on HEAD via the "plain badge tap still toggles the arcs" assert (badge inert today); the negative asserts guard the fix | attach long-press to node hit boxes too | [U] F6 | GT |
| TC-198-16 | slop cancel | wired | F6::'TC-198-16 move past slop before 500ms cancels; canvas pans' | no gesture layer | disable slop cancel (custom recognizer accepting drift) | [U] F6 | GT |
| TC-198-17 | release-click hazard | wired | F6::'TC-198-17 release after entry does not exit' | edit mode absent | make tap-away listen to the long-press release (pointer-up) | [U] F6 | GT |
| TC-198-18 | tap-away exit | wired | F6::'TC-198-18 empty-space tap exits; overlay unmounts; dim lifts' | edit mode absent | leave banner mounted on exit | [U] F6 | GT |
| TC-198-19 | dimmed-node tap-away | wired | F6::'TC-198-19 dimmed avatar tap exits edit, does NOT open chat' | edit mode absent | route node tap to chat during edit | [U] F6 | GT |
| TC-198-20 | arm affordance | wired | F6::'TC-198-20 handle tap arms: teal state, value bubble, −/+ on nav line' | handles absent | arm without mounting steppers | [U] F6 | GT |
| TC-198-21 | step + clamp | unit+wired | F2::'step saturates at bounds' + F6::'TC-198-21 + steps by coarse step, bubble updates, dim flashes, max saturates' | model/steppers absent | remove clamp in step helper | [U] F2+F6 | AUTO / GT |
| TC-198-22 | drag | wired | F6::'TC-198-22 handle drag changes knob continuously; dim lifts during drag' | handles absent | re-apply dim mid-drag | [U] F6 | GT |
| TC-198-23 | drag survives rebuild | wired | F6::'TC-198-23 one continuous drag spans full range across live re-renders' | handles absent; hazard = handle rebuilt mid-drag (mockup html:971-973) | host handles inside the rebuilt canvas subtree | [U] F6 | GT |
| TC-198-24 | disarm on collapse | wired | F6::'TC-198-24 collapsing arcs removes cv/pr/og handles, disarms, hides steppers' | edit mode absent | keep armed state after handle unmount | [U] F6 | GT |
| TC-198-25 | Reset semantics | wired | F6::'TC-198-25 Reset restores 5 defaults, session stays active' | Reset absent | make Reset exit the session | [U] F6 | GT |
| TC-198-26 | collapsed edit | wired | F6::'TC-198-26 collapsed: only av/sp handles; both arm/step/drag' | edit mode absent | mount all 5 handles while collapsed | [U] F6 | GT |
| TC-198-27 | badge×edit | wired | F6::'TC-198-27 badge toggles arcs mid-edit without exiting' | edit mode absent | treat badge tap as tap-away | [U] F6 | GT |
| TC-198-28 | knob semantics | unit+widget | F1::'avPx clamp' + F5::'TC-198-28 av 0.6/1.4 scales visuals, 44px floors hold' | no knob plumbing (C4) | drop tap-floor at extremes | [U] F1+F5 | AUTO |
| TC-198-29 | painter reconciliation | widget | F5::'TC-198-29 sp 1.5 scales node seats AND painted ring/arc paths' | painter re-declares radii 62/108 (:8-9), takes no scale | leave painter radii const while seats scale | [U] F5 | AUTO |
| TC-198-30 | wrap boundary | unit | F1::'phi pinch holds to cv 1.6, releases to 2.9 at 2.5; ends never meet' + F1::'cv≤1.6 all seats within 390px' | phi fn absent | drop the asin pinch term | [U] F1 | AUTO |
| TC-198-31 | capacity boundary | unit | F1::'pr=4: no arc >4, all seated' | capacity fn absent | drop `min(…, pr)` | [U] F1 | AUTO |
| TC-198-32 | og isolation | unit | F1::'og 2.5 scales first gap only; arc-to-arc stays 46·sp' | radius fn absent | multiply og into every gap | [U] F1 | AUTO |
| TC-198-33 | restore durability | wired | F6::'TC-198-33 sculpt→exit→remount restores 5 values (async ok)' | no persistence exists | skip load on mount | [U] F6 | GT |
| TC-198-34 | corrupt fallback | unit | F2::'defaults on null/empty/arity/garbage' + F3::'corrupt store value loads defaults' | codec absent | remove tryParse-null fallback | [U] F2+F3 | AUTO |
| TC-198-35 | clamp on load | unit | F2::'av 9.0→1.4, pr 99→9 on decode' | codec absent | remove decode clamp | [U] F2 | AUTO |
| TC-198-36 | Reset persists | unit+wired | F3::'clear deletes key→defaults' + F6::'TC-198-36 Reset+exit → fresh mount renders defaults' | trio absent | Reset only mutates in-memory state | [U] F3+F6 | AUTO / GT |
| TC-198-37 | account Move | migration host ×3 | F10a::registry pin; F10c::'sculpted knob key promotes to destination' + F10c::'never-sculpted source: no bundle entry, import ok' (spec's "destination RENDERS sculpted geometry" closes by composition F10c ∘ TC-198-33) | key unregistered → structurally absent from bundle (C5); no preference key round-trips today | **remove the registry entry** → F10a red AND F10c destination read null | [U] F10 + [MV] | AUTO (+move-feature glob) |
| TC-198-38 | no write until edit | wired | F6::'TC-198-38 view/expand writes nothing; first write on first edit' (write-counting spy store) | anti-donor: lab writes on every tap (orbit3_screen:346-396) | remove change-detection (write on no-op step) | [U] F6 | GT |
| TC-198-39 | pill presence | wired | F6::'TC-198-39 40px pill bottom-right, semantics, expands ~200px with focus' | no search affordance on inner circle (C3) | drop pill Semantics | [U] F6 | GT |
| TC-198-40 | single match | wired | F6::'TC-198-40 match lights + label; others dim 0.28; one chip with ring provenance' | find state absent | dim matches too (invert predicate) | [U] F6 | GT |
| TC-198-41 | chip cap | unit+wired | F4::'first-4 merged-recency' + F6::'TC-198-41 six matches: all light, exactly 4 chips, no re-seat' | matcher absent | slice(0,4) after name-sort | [U] F4+F6 | AUTO / GT |
| TC-198-42 | collapsed overflow match | wired | F6::'TC-198-42 no auto-expand; chip with arc provenance opens chat; chips-without-dim' | find absent | auto-expand on match (declined option B) | [U] F6 | GT |
| TC-198-43 | reveal scroll | wired | F6::'TC-198-43 off-view match auto-scrolls into view' | no ScrollController on surface | remove reveal call | [U] F6 | GT |
| TC-198-44 | groups in find | unit+wired | F4::'groups match' + F6::'TC-198-44 group match lights, chips, opens group conversation' | list search drops groups (orbit_wired:316); no circle find | filter groups from matcher | [U] F4+F6 | AUTO / GT |
| TC-198-45 | clear/close restore | wired | F6::'TC-198-45 clearing removes lighting/dim/chips' | find absent | leave dim applied after clear | [U] F6 | GT |
| TC-198-46 | zero-match anti-signal | wired | F6::'TC-198-46 zero matches → no dim, no chips' | find absent (lab anti-signal is the donor hazard) | dim on zero matches | [U] F6 | GT |
| TC-198-47 | keyboard inset | wired | F6::'TC-198-47 pill visible+editable with viewInsets.bottom set; per-keystroke updates' | screen is resizeToAvoidBottomInset:false (:357); pill absent | drop the viewInsets self-padding (dock donor :30-33) | [U] F6 | GT |
| TC-198-48 | tap-away close | wired | F6::'TC-198-48 tap outside pill/chips closes+clears' | find absent | leave query after close | [U] F6 | GT |
| TC-198-49 | surface interplay (regression) | wired | F6::'TC-198-49 toggle closes circle find; list search unchanged (groups still dropped); re-entry lands clean' | circle find absent; list-search half must stay green | make circle find leak into all-chats projection | [U] F6 + sentinel `orbit_wired_test.dart` | GT |
| TC-198-50 | edit×find | wired | F6::'TC-198-50 typing does not exit edit; lit match full-bright over 22% dim; survives knob drag' | neither mode exists | let find-open call edit-exit | [U] F6 | GT |
| TC-198-51 | pill/chip not tap-away | wired | F6::'TC-198-51 pill/chip taps never end edit; strip is hit-transparent; empty-canvas tap ends both' | modes absent | make strip container opaque to taps | [U] F6 | GT |
| TC-198-52 | chip during edit | wired | F6::'TC-198-52 chip tap opens chat, edit ends, knobs persisted (spec decision 7)' | modes absent | keep edit overlay mounted behind pushed route | [U] F6 | GT |
| TC-198-53 | labels toggle | wired | F6::'TC-198-53 double-tap shows labels everywhere, alternate-seat stagger; second hides; off on re-entry' (+F5 render half) | no double-tap in production orbit | drop `j%2` stagger | [U] F6+F5 | GT / AUTO |
| TC-198-54 | no tap latency | wired | F6::'TC-198-54 single node tap opens chat with no double-tap-timeout wait' (pump < kDoubleTapTimeout then assert route) | hazard = lab's per-node doubletap arena (orbit3_screen:511-517) | wrap nodes in the double-tap detector | [U] F6 | GT |
| TC-198-55 | gesture isolation | wired | F6::'TC-198-55 double-tap on node/badge keeps primary behaviors, no label toggle' | modes absent | put onDoubleTap on node detectors | [U] F6 | GT |
| TC-198-56 | semantics sweep | wired+widget | F6::'TC-198-56 ensureSemantics: badge/pill/handles/steppers/Reset/chips labeled; arc==ring node semantics' | none of the elements exist | strip Semantics off steppers | [U] F6 | GT |
| TC-198-57 | l10n parity + literal-scan | l10n host | F11::parity over `newOrbitKeys`+16; literal-scan half = the machine-checkable grep gate in §Acceptance Gates §8 (scan output must list only the 3 orbit3 paths) | keys absent in ARBs | delete an ar key / hardcode one 198 string (scan output grows) | [U] F11 + [GR] + §8 grep gate | NONE (pinned :251) |
| TC-198-58 | RTL | widget+wired | F5::'TC-198-58 arc fill mirrors under RTL' + F6::'TC-198-58 ar locale: chrome/pill/chips/steppers no collision, no overflow errors' | no arcs; chrome physical convention must hold | mirror-blind fill (drop directionality param) | [U] F5+F6 | AUTO / GT |
| TC-198-59 | reduce-motion sweep | wired | F6::'TC-198-59 disableAnimations: no arc bloom/edit pulse/dim fade/chip entrance; 194 ring frozen-visible' | new motion absent; 194 half is sentinel | drop motion gate on chip entrance | [U] F6 | GT |
| TC-198-60 | large text | wired | F6::'TC-198-60 textScaler 2.0: banner/bubble/chips no RenderFlex overflow' | elements absent | fix-width the value bubble | [U] F6 | GT |
| TC-198-61 | label-gap containment | widget | F5::'TC-198-61 arc friend nodes reuse ring semantic labels (localized unread; :208 gap does not spread)' | arc nodes absent | hardcode English label at the new call site | [U] F5 | AUTO |
| TC-198-62 | default parity INV-6 | widget | F5::'TC-198-62 knobs=1.0, ≤13 items: geometry identical to HEAD consts' | guard (mutation-verified) — green by design once params exist; asserts positions == 62/108-derived values | scale ring radii by sp≠1 default | [U] F5 | AUTO |
| TC-198-63 | 193 reset extension | wired | F6::'TC-198-63 rising edge collapses arcs + exits edit + clears find + labels off; read-during-Feed still clears after reset (TC-194-16 parity)' | reset seam doesn't touch new state (it doesn't exist) | drop find-clear from `_resetToInnerCircleView` | [U] F6 | GT |
| TC-198-64 | 194 locks | preservation | existing `orbit_unread_indicator_wired_test.dart` (12+1) stays green + F7's 25 kept tests incl. TC-194-26 48px lit target (sentinel) | N/A — preservation sentinel | (mutation owned by those suites) | [GR] + [FH] | NONE |
| TC-198-65 | 196 chrome | wired + preservation | F6::'TC-198-65 expanded+scrolled: chrome fixed; OPEN FAB scrim beats badge/handles/pill' + `orbit_qr_entry_migration_test.dart` green | new layers must mount before FAB (orbit_screen:499-515) | mount pill after ExpandableFab | [U] F6 + [GR] | GT / NONE |
| TC-198-66 | 197 locks | preservation | existing `inner_circle_items_test.dart` (2) + F7 197 TCs stay green | N/A — preservation sentinel | (owned by those suites) | [FH]+[GR] | NONE |
| TC-198-67 | badge-lock supersession | widget | F7::REWRITE :268-289 → 'center avatar never opens chat; badge toggles arcs, never opens chat' | old test asserts tap-does-nothing; new toggle half fails on HEAD | remove badge onTap | [U] F7 | AUTO |
| TC-198-68 | perf lane | perf harness | F13::scenario `orbit_open_arcs_expanded_sculpt_find` via the new `interaction` hook + host param threading (report-only) | scenario absent (4 in list); struct has no interaction hook (:81-95,:284-323) | delete the scenario entry | [PF] | NONE (internal list + hook) |
| TC-198-69 | pan-release ≠ tap | wired | F6::'TC-198-69 drag-scroll release over node/edit/find/labels fires none of tap-open/tap-away/close/toggle' | no scroll surface; justPanned mechanism absent (html:852) | drop the pan-release rejection window | [U] F6 | GT |
| TC-198-70 | badge×find re-apply | wired | F6::'TC-198-70 expanding under active query lights the arc match + dim; collapsing falls back to chips-only, no half-state' | find absent | skip find re-evaluation on layout change | [U] F6 | GT |
| TC-198-71 | handles track scroll | wired | F6::'TC-198-71 handles anchored while scrolling; hidden outside stage band; armed state survives scroll' | handles absent (hosting contract html:1047-1054) | leave handles unpositioned on scroll | [U] F6 | GT |
| TC-198-72 | planted circle | wired | F6::'TC-198-72 og/cv drag on deep stack does not displace the on-screen circle (scroll compensates)' (math: F1 overhang) | no compensation seam | drop scroll compensation delta | [U] F6 | GT |
| TC-198-73 | dimmed ≠ disabled | wired | F6::'TC-198-73 lit and dimmed node taps both open chat; find cleared on return' | find absent | block taps on dimmed nodes | [U] F6 | GT |
| YIELD-1 (plan-added, from refuted C2) | host-swipe conflict | wired | F9::'orbit edit session suppresses feed↔orbit host swipe; knob drag still applies' | no yield gate — rightward drag slides to Feed (feed_wired:2397-2402) | remove `_orbitEditSessionActive` from the bail | [U] F9 | AUTO |
| YIELD-2 (plan-added) | invariant re-verification | wired | F9::'host swipe restores after edit exits' | gate absent | latch the gate (never clear) | [U] F9 | AUTO |
| SIM-PC (plan-added, PROD-CRITICAL) | real-surface E2E | simulator | F12::'198 orbit overflow: badge expands arcs, overflow chat opens, find chips a hidden group' | badge tap does nothing on a real boot | revert badge onTap wiring | [SIM] | NONE (already classified+pinned; 0 new builds) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability**: TC-198-33 (remount reconstructs sculpted geometry from the persisted row, async restore), TC-198-08/63 (session-transient state re-derives to defaults on re-entry). Covered.
- **Sibling-surface consistency**: find applies to friends AND groups on rings AND arcs (TC-40/41/42/44); arc nodes get identical semantics/tap floors/unread treatment to ring nodes (TC-10/11/12/56/61); the all-chats sibling search deliberately stays asymmetric and is test-locked unchanged (TC-49). Covered.
- **Destructive-action side-effects**: Reset asserts all five values restored + persisted deletion (fresh mount default, TC-25/36); find clear asserts full removal of lighting/dim/chips (TC-45); collapse asserts arc-node removal + seat restore + no half-state under find (TC-05/70). Covered.
- **Invariant re-verification under new transitions**: the extended 193 reset re-verifies 194 dirty-replay after the rising edge (TC-63, per TC-194-16's contract); route-push-during-edit re-verifies persistence + overlay teardown (TC-52); arc collapse re-verifies disarm (TC-24); edit exit re-verifies host-swipe restoration (YIELD-2). Covered.

## Invariants (locked by tests)
- INV-1: the badge NEVER opens a chat (it only toggles) → TC-198-67.
- INV-2: no overflow member is ever culled while expanded → TC-198-06/07/31 (F1 math + F5/F6 render).
- INV-3: ONLY the five knobs persist; view mode/expansion/labels/find are session-transient → TC-198-08/38/63 (+ `orbit_view_mode.dart:8-9` doc lock stands).
- INV-4: every interactive orbit element ≥44pt → TC-198-03/04/12/28.
- INV-5: no "everything dimmed, nothing highlighted" state ever renders → TC-198-46/70 (+ chips-without-dim middle case in TC-42).
- INV-6: knobs at defaults ⇒ geometry identical to pre-198 production → TC-198-62.
- INV-7: all NEW motion honors disableAnimations/accessibleNavigation → TC-198-09/59 (gate donor: `orbital_visualization.dart:58-60`, `unread_orbit_indicator.dart:79-95`).
- INV-8: edit-session drags never leave the Orbit tab → YIELD-1/2.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
0. `git status --short > /tmp/198-pre.txt` (dirty-tree snapshot); confirm no other live session is editing `lib/features/orbit` / `feed_wired.dart` (3 other claude sessions are live on this host).
1. **Slice P (pure)** — add F1–F4 REDs + inert skeletons (`OrbitGeometryPrefs`, `orbit_arc_layout`, `orbit_find_matches`, use-case trio); prove RED (`flutter test` the 4 files); implement to GREEN. Stop-if: any formula can't satisfy both TC-198-30 containment and TC-198-62 parity → re-derive against the mockup addendum, do not fudge constants.
2. **Slice A (badge + arcs)** — F5/F7/F8 REDs (incl. the TC-198-67 rewrite of `orbital_visualization_test.dart:268-289`); prove RED; implement: badge onTap/Semantics/chevron/44pt/motion-gate → 9-slot re-spread → geometry params + arc layers in `orbital_visualization.dart` → painter parameterization → l10n keys (F11 RED→GREEN alongside). Keep the other 25 F7 tests green throughout.
3. **Slice SCROLL** — ScrollController + top-anchored inner-circle scroll view + overhang/planted compensation in `orbit_screen.dart` (TC-198-07/72 halves).
4. **Slice B (edit)** — F6 Group-B REDs + F9 YIELD REDs; prove RED; implement: background gesture layer (long-press w/ slop, release-click suppression) → edit overlay/handles (hosted outside the scrolled canvas)/bubble/steppers/Reset/banner → dim rules → `feed_wired.dart` yield gate → knob write-through w/ change detection + async restore in `orbit_wired.dart`. Register F6 in `GROUP_TESTS` (Real Scope 16) as soon as the file exists. Stop-if: handle drags and the vertical scrollable fight in the arena → resolve with an edit-mode scroll lock (document), never by removing the yield gate.
5. **Slice D (persistence + Move)** — F3/F6-D REDs; F10 REDs (registry pin, source-audit set, bundle round-trip ×2); implement model registration (`orbitGeometryPreferences` enum member + `_fixedKeys` entry).
6. **Slice C (find)** — F6 Group-E REDs; implement pill/lighting/chips/reveal/keyboard/clear + group inclusion + chip routes.
7. **Slice F (composition + labels)** — F6 Group-F/I REDs; implement double-tap labels (background-only detector, TC-54), edit×find rules, justPanned rejection, badge×find re-apply, handles-track-scroll.
8. **Slice R (resets + regressions)** — TC-198-08/49/63/65 REDs; extend `_resetToInnerCircleView`; verify preservation sentinels ([GR] families).
9. **Slice S (sim + perf)** — F12 sim case (RED on badge-tap-does-nothing against a stubbed-out flag build is impractical on sim — prove RED by running the case before Slice A lands OR by reverting badge wiring locally once; document which); F13 perf scenario; stale-doc fixes.
10. Rerun direct → preservation → named gates (§Acceptance Gates); `flutter analyze`; `git diff --check`; update `00-INDEX.md` execution note.

## Risks And Edge Cases
- **Host-swipe fight mid-sculpt** (refuted C2) → YIELD-1/2; the raw Listener bypasses the arena, so the yield flag is the ONLY mechanism (precedent `_orbitRowActionOpen`).
- **Handle destroyed mid-drag by canvas rebuild** (mockup html:971-973) → TC-198-23; handles live outside the rebuilt subtree.
- **Entrance animation pinning opacity above dims** (html:820-822) → F5 entrance-relinquish test; TC-198-50.
- **Badge slot vs seat-13 overlap regression** → TC-198-03 asserts disjoint hit boxes, not just distance.
- **`pumpAndSettle` hangs with lit nodes** (9s repeat rotation) → all suites use bounded pumps; badge's 1000ms timer must be drained.
- **Slop constant mismatch**: spec says ~8px; Flutter's `kTouchSlop` is 18 logical px → TC-198-16 moves >18px so it passes under either; constant recorded in Accepted Differences.
- **Optional-vs-critical Move entry**: critical would throw on every never-sculpted export (bundle:342-347) → criticality MUST be optional; locked by F10c's absent-key test.
- **New category enum breaks old-importer Move bundles** → Accepted Differences (product flag); F10c asserts the same-version round-trip.
- **l10n literal-scan is already RED (3 orbit3 literals)** → Known-Failure Interpretation; any new hardcoded 198 string grows the list from 3 → the gate check is "list unchanged".
- **iOS perf-sim lane self-skips capture** (harness :476-481) → TC-198-68 data comes from the host `performance` lane; the sim lane only proves compile/run.

## Device/Relay Proof Profile
Host-green + one iOS-simulator run of F12 (the extended cold-start sim case) = closure. No relay, no multi-device, no crypto, no OS-callback boundary is touched (haptics excluded as untestable-by-convention). Account-Move closure is at host tier via the proven bundle round-trip harness — justified: 198 adds a data row to a transport that is device-proven and unchanged; the registry/promotion mechanism is exactly what F10 exercises. Deferred device work: none blocking; optional follow-up = run `/sims move-feature` scope after landing for belt-and-braces.
Closure scenario: `flutter test integration_test/cold_start_message_render_simulator_test.dart -d "$FLUTTER_DEVICE_ID"` (build-cost delta 0 — case folded into the already-built suite).

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# 0. Snapshot + discovery sanity (no new integration_test FILE → discovery must stay green)
git status --short > /tmp/198-pre.txt
./scripts/check_reliability_simulation_discovery.sh          # expect: PASS, no unclassified

# 1. RED (before production edits) — each must FAIL for the documented reason
flutter test test/features/orbit/domain/orbit_arc_layout_test.dart                       # expect: compile-with-skeleton, 13/13 FAIL
flutter test test/features/orbit/domain/orbit_geometry_prefs_test.dart                   # expect: 6/6 FAIL
flutter test test/features/orbit/application/orbit_geometry_prefs_use_cases_test.dart    # expect: 4/4 FAIL
flutter test test/features/orbit/application/orbit_find_matches_test.dart                # expect: 6/6 FAIL
flutter test test/features/orbit/presentation/widgets/orbital_arcs_test.dart             # expect: ~17 FAIL
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart # expect: ~36 FAIL
flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart    # expect: 25 pass + 4 new FAIL (incl. rewritten TC-198-67)
flutter test test/features/orbit/presentation/widgets/overflow_badge_test.dart           # expect: 4 pass + 3 FAIL
flutter test test/features/feed/presentation/screens/feed_swipe_test.dart                # expect: 17 pass + 2 FAIL
flutter test test/features/account_migration/application/migration_secure_storage_registry_test.dart  # expect: 3 pass + 1 FAIL
flutter test test/features/account_migration/application/migration_secure_storage_source_audit_test.dart  # expect: FAIL (new expectedFixedKeys entry; source literal absent on HEAD)
flutter test test/features/account_migration/application/account_migration_bundle_transfer_test.dart  # expect: 27 pass + 2 FAIL
flutter test test/l10n/orbit_strings_parity_test.dart                                    # expect: FAIL (16 new keys absent)

# 2. Direct GREEN (after each slice, then all)
flutter test test/features/orbit/ test/features/feed/presentation/screens/feed_swipe_test.dart \
  test/features/account_migration/ test/l10n/orbit_strings_parity_test.dart
# expect: all pass — orbit tree ≈ 26+4 viz, 7 badge, ~17 arcs, ~36 wired, 16 split, 13 unread, 18+9 QR, 2 merge, 74 wired-host, 13+6+4+6 pure = no failures

# 3. Preservation sentinels + named family gate (GROUP_TESTS incl. the NEW orbit_sculpt_summon_wired_test.dart pin)
./scripts/run_test_gates.sh groups            # expect: exit 0; verify the new pin is listed in the run header
./scripts/run_host_test_gates.sh feature-host-all   # expect: exit 0 (new files auto-globbed)

# 4. Move gate
./scripts/run_test_gates.sh move-feature      # expect: exit 0 (registry+round-trip additions included)

# 5. Perf lane (report-only; ORBIT target now runs 5 scenarios)
./scripts/run_test_gates.sh performance       # expect: exit 0; ORBIT report lists orbit_open_arcs_expanded_sculpt_find

# 6. Simulator PROD-CRITICAL leg (0 new builds; iOS sim primary)
flutter test integration_test/cold_start_message_render_simulator_test.dart -d "$FLUTTER_DEVICE_ID"
# expect: exit 0 incl. the new '198 orbit overflow…' case  (resolve device id per /sims; dry-run: /sims --list)

# 7. DB migration: N/A — no schema change; secure-storage registry is not a DB migration (no DB v## consumed)

# 8. Hygiene
flutter analyze                               # expect: 0 new issues
git diff --check                              # expect: clean
flutter test test/l10n/l10n_integrity_test.dart 2>&1 | tee /tmp/198-l10n-scan.txt || true
grep -c 'lib/features/orbit3/' /tmp/198-l10n-scan.txt        # expect: 3 (the pre-existing lab literals, unchanged)
! grep -q 'lib/features/orbit/'  /tmp/198-l10n-scan.txt       # expect: exit 0 — ANY production-orbit path in the scan output = 198 regression (BLOCKING)
```

## Known-Failure Interpretation
- **Expected RED**: every §1 command above, before its slice lands.
- **Pre-existing dirty**: `test/l10n/l10n_integrity_test.dart` literal-scan FAILS today with exactly 3 orbit3 literals (`orbit3_screen.dart:1113`,`:1132`, `orbit3_arch_panel.dart:68`) — unchanged-list = pass-equivalent for 198; growth = 198 regression (BLOCKING). Two pre-existing analyzer ERRORS exist in `integration_test/smoke_test.dart:149` and `transport_census_harness.dart:214` (missing `dbExistsMessageByContent` arg) — OUTSIDE the ORBIT compile unit, not 198's to fix (flag if they block a full-tree analyze).
- **Environment blocker (NOT product)**: missing iOS simulator for §6; `performance-sim` records nothing on device/sim (`Platform.isIOS` early-return, harness :476-481) — host `performance` lane is the data source.
- **Scope drift (BLOCKING)**: any failure in orbit3 lab tests, all-chats search tests, or 193/194/196/197 suites.

## Done Criteria
- [ ] RED added first per slice; failed for the documented reason.
- [ ] Mutation-verified: every production edit has its named re-red revert (matrix column).
- [ ] Direct GREEN + preservation sentinels + [GR]/[FH]/[MV]/[PF] gates pass.
- [ ] No DB migration needed (verified N/A).
- [ ] SIM-PC leg green on an iOS simulator (real render/gesture/route pipeline) — do NOT treat host coverage as sufficient on its own.
- [ ] Harness registration done & verified: `orbit_sculpt_summon_wired_test.dart` visible in the `groups` gate run; sim case runs inside the already-registered cold-start suite; perf report lists 5 ORBIT scenarios; parity keys in `newOrbitKeys`.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; zero Scope Guard violations.
- [ ] Post-land (non-blocking): one `/sims move-feature` scope run as belt-and-braces on the Move rows.

## Scope Guard (hard "Do not")
- Do not touch `lib/features/orbit3/**` or its tests (stays debug-gated; not deleted; not imported — rebuild, don't extract).
- Do not import orbit2/orbit3 prototype types into `lib/features/orbit` (197 plan lock).
- Do not modify all-chats list-search behavior (`orbit_wired.dart:303-317` semantics stay), the 193 toggle, 196 chrome positions, 194 indicator internals, or 197 merge.
- Do not persist view mode, expansion state, or label visibility (`orbit_view_mode.dart:8-9`).
- Do not register `orbit3_dimension_preferences_v1` for Move.
- Do not add frame-budget asserts to the perf harness.
- Do not remove or weaken the host-swipe yield for feed cards / orbit rows while adding the edit gate (`feed_wired.dart:2397-2402`).
- Do not use `pumpAndSettle` in any test that can have a lit node; do not leave the badge's 1000ms timer undrained.
- Do not harden `_enumByName`/bundle parsing in this session (follow-up owns it).

## Accepted Differences / Intentionally Out Of Scope
- **Move cross-version skew (product flag)**: registering the knob key adds closed-enum member `orbitGeometryPreferences`; a bundle exported by a 198+ build FAILS metadata parse on a pre-198 importer (`_enumByName` throws, `account_migration_bundle_transfer.dart:2278-2302`). Same property held for every historical key addition; real-world direction (old phone exports → new phone imports) is unaffected. Follow-up candidate: tolerant fromJson skipping unknown-category entries (future migration-hardening session).
- **Long-press slop = framework `kTouchSlop` (18 logical px)**, not the mockup's ~8 client px — framework-recognizer convention; flag to product only if the feel is wrong on device.
- **Banner copy** ships as "TAP AWAY TO FINISH" (live mockup, spec decision #11); the earlier "EDITING ORBIT · …" iteration remains flagged to product.
- **Default-collapsed on entry** (spec contract) vs the hero's `startExpanded:true` demo convenience — already spec-flagged.
- **Reveal-scroll constants** (70/90/140, html:1161-1164) are treated as tunable; tests assert visibility outcomes only.
- **Provenance past the 12-arc envelope**: layout provenance is exact for all computed arcs; the mockup's 'arc 6+' fallback is replaced by the real arc index (nothing is culled, so every seat has one).
- **Populations beyond the 12-arc envelope** (>~100 at defaults): F1 asserts nothing culled at 50; the envelope bound stays a spec-recorded product flag.
- The share-target picker's group search stays as-is (C3 nuance; different affordance).

## Dependency Impact
- **199+ orbit work** builds on: `OrbitGeometryPrefs` (5-knob contract), `orbit_arc_layout` pure API, the edit-session yield-gate channel in `feed_wired.dart`, and the extended `_resetToInnerCircleView` (any future session-transient orbit state must reset there too).
- **Migration-hardening follow-up** depends on this plan's Accepted-Differences record of the `_enumByName` skew hazard.
- The rewritten TC-198-67 replaces the badge-inertness lock other sessions may cite (`orbital_visualization_test.dart:268-289`) — INV-1 (never opens a chat) is preserved.

## Reviewer Findings
Two independent read-only reviewers, 2026-07-03 (both ran AFTER the plan was written; all findings applied in place):

**Reviewer 1 — sufficiency-checklist audit**: "SUFFICIENT — all blocking gates pass. 10 MINOR findings, 0 BLOCKING." Verified: 73/73 spec TCs present with zero empty matrix cells; every INV-1..8 test-named; mutations named per production edit; gates literal with counts; blind-spot sweep 4/4; refuted findings recorded; known-failure interpretation covers the pre-existing l10n literal-scan RED. The 10 minors (missing F10b RED command; eyeball-enforced literal-scan → now a grep gate; TC-64 gate cell; TC-15/62 RED-cell wording; GROUP_TESTS edit not in Real Scope → now item 16; feed_swipe baseline 17; orbit3 literal line drift; composition notes for TC-37/TC-10; /sims move-feature promoted to post-land Done Criteria) — ALL APPLIED.

**Reviewer 2 — adversarial executability spot-check**: 1 BLOCKING + 3 MINOR, rest verified sound against source. BLOCKING: F13 was written as a bare `_OrbitScenario` list append, but the struct is data-only (:81-95) with a fixed run script (:284-323) over a host that bypasses `OrbitWired` (:229-263) → F13/Real-Scope-13/TC-68 REWRITTEN to require the `interaction` hook + host param threading. MINORS (all applied): F11 two-step sequencing (block-1 list RED first; generated-API getters only after `flutter gen-l10n`, else compile failure); F6 harness must add a `GroupMessageListener` (donor omits it; `orbit_wired.dart:2475-2482` silently dead-ends group routes); F9/Real-Scope-10 now name the `onEditSessionActiveChanged` callback + the `feed_wired.dart:2568` construction-site edit. Verified-sound: GROUP_TESTS registration mechanics incl. the path-pattern completeness check (no extra edit needed, `run_test_gates.sh:706,:748-776`); the sim fold (F12) executable as described; the Move rows (F10) survive end-to-end incl. the promotion-only-after-`acceptOldBlockProof` nuance (added to F10c).

## Arbiter Decision
Structural blockers: none remaining (the one BLOCKING reviewer finding is fixed in place). Deferred details: exact widget decomposition of the edit overlay (contract is test-locked; internals free); reveal-scroll constants tunable. Accepted differences: as listed above (Move enum skew, kTouchSlop, banner copy, default-collapsed, 12-arc envelope).

## Final Execution Verdict
Verdict: (pending execution) | Files changed: — | Tests run: — | Blocking: — | QA verdict: — | Non-blocking follow-ups: tolerant bundle-import parsing (migration-hardening); orbit3 literal-scan cleanup (lab session); `test-gate-definitions.md:735` stale filename.
