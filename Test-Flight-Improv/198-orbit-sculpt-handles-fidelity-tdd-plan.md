# 198 - Orbit "Sculpt & Summon" edit-mode mockup fidelity — geometry-anchored handles  (Modification)

Status: awaiting-review
Spec: [198-orbit-sculpt-and-summon-spec.md](198-orbit-sculpt-and-summon-spec.md) (re-opened Group B rows) + mockup contract [198-orbit-arch-overflow-edit-find-mockups.html](198-orbit-arch-overflow-edit-find-mockups.html) (handles build: html:192-228, 971-1073) + 12 adversarially verified mismatches (workflow `wf_b3a2d45a-f09`, 17 agents; full detail archived in this plan §Root Cause)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-03 | Evidence Collector (wf_b3a2d45a-f09, 17 agents) | mockup html, spec, orig plan, inner_circle_interactive_surface.dart, orbital_visualization.dart, orbit_arc_layout.dart, wired test | 12 mismatches confirmed (M1 critical), M10-jiggle refuted, escape RC = presence-only tests + TC-198-71/72 never written | ground fix mechanics |
| 2026-07-03 | Planner ground+refute (wf_f2875564-e7f, 7 agents) | seam/tests/style ground + 4 adversarial refutes (anchor, chrome, l10n, motion) | all 4 mechanisms feasible-with-changes; constraints encoded below | emit plan |
| 2026-07-03 | Reviewer (sufficiency) | this plan vs sufficiency checklist | see §Reviewer Findings | hand to arbiter |
| 2026-07-03 | Arbiter | | see §Arbiter Decision | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-03 | contract extraction (git status --short) | — | HEAD `4b4ba9fc`; dirty = docs/graphify + `info.plist` (pre-existing, untouched) | scope confirmed | RED |
| 2026-07-03 | RED tests added | wired (+22), orbit_arc_layout_test (+2), orbit_edit_handle_test (NEW, 4) | full wired run: `+24 -22` — every new row red for its documented HEAD mechanism (canvas key absent / bubble fixed bottom-center 551.5 / steppers centered 305.5 / pill 40 not 88 / editDim never lifts / NoSuchMethod editEmphasis / banner border null / semantics sweep 0); LAYOUT + HANDLE compile-red (new APIs). **Probe found a REAL HEAD bug the test-gap predicted: `_HandleChip` captured the pan origin in a build-local closure, so the arming rebuild reset it to `Offset.zero` and every chip drag slammed the knob to a clamp (og drag → 0.5). Also: chips rendered as full-width stacked bars (`Container(alignment:)` expansion), not a centered Wrap row.** | RED for expected reasons | impl |
| 2026-07-03 | implementation | orbit_arc_layout.dart (consts + 3 pure helpers), orbital_visualization.dart (canvasKey + editEmphasis + node-dim keys), orbit_edit_handle.dart (NEW), inner_circle_interactive_surface.dart (overlay rework; drag deltas accumulated in STATE — fixes the closure bug) | — | scoped files only; ARBs untouched | GREEN |
| 2026-07-03 | direct GREEN | + churn: TC-198-19 taps friend2 (friend0's seat hosts the av handle; overlap pinned by TC-198F-25) — no assertion weakened | `flutter test .../orbit_sculpt_summon_wired_test.dart` → **46/46**; `orbit_edit_handle_test.dart` → 4/4; `orbit_arc_layout_test.dart` → 17/17 | reds now green | preservation |
| 2026-07-03 | preservation GREEN | — | `flutter test test/features/orbit/ test/l10n/orbit_strings_parity_test.dart` → **434 passed** (was 403+3 parity; +28 new); `./scripts/run_test_gates.sh feed` → 285 passed (F9 yield rows green); parity file byte-identical; `l10n_integrity_test` scan = exactly the 3 orbit3 literals (0 production-orbit) | sentinels green | gates |
| 2026-07-03 | named gates | — | `./scripts/run_test_gates.sh groups` → green (orbit wired pin now 46; see QA row); `flutter analyze lib/features/orbit test/features/orbit` → 5 pre-existing only (0 new); `git diff --check` clean | gate green | QA |
| 2026-07-03 | QA (independent) | — | mutation-verification workflow (worktree-isolated, named matrix reverts) + independent review agents | see Final Execution Verdict | verdict |

## Source Of Truth
- Spec / intent: 198-orbit-sculpt-and-summon-spec.md §1.B + contract table :42-43 + Group B TCs; mockup html (handles variant) is the visual contract
- Gate definitions: scripts/run_test_gates.sh (GROUP_TESTS pins: orbit_sculpt_summon_wired_test.dart :254, orbit_strings_parity_test.dart :251)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh (no new sim scenarios in this slice)
- Numbering / index: Test-Flight-Improv/00-INDEX.md (chained to spec 198)

## Session Classification
implementation-ready

## Exact Problem Statement
The shipped 198 edit mode is functionally correct (knob math, persistence, yield gate, find composition — all host-green) but **visually and interactionally diverges from the mockup/spec**: the five geometry handles render as flat text chips in a bottom-center `Wrap` (`inner_circle_interactive_surface.dart:472-496`) instead of glowing circular icon handles seated ON the orbit geometry; the value bubble is a fixed bottom-center readout instead of floating above the armed handle; the −/+ steppers hug the bubble instead of flanking the nav band; there is no glow/pulse/icon/tip-pill vocabulary at all; two drag mappings (cv angle-follow, og ÷sp) were simplified; stepper presses never flash-lift the dim; the edit-entry ring-brighten is missing; and the edit overlay stacks below the find layer. The user long-pressed on device, compared against the mockup screenshots, and correctly reported "the editing part doesn't match".

What must improve: the twelve confirmed mismatches M1–M9, M10(ring-brighten half only), M11, M13 — the edit mode must read as the mockup's "sculpt the thing you're looking at".
What must stay unchanged (→ preserved-green sentinels): all knob semantics/ranges/persistence (Slice P/D, 30 pure + TC-33/36/38), the INV-8 host-swipe yield gate (F9 feed_swipe 19), find matching/chips (Group E), reset seam (TC-198-63), FAB-scrim contract (TC-198-65), l10n parity (3 locales), F12 sim case, node-tap latency contract (TC-198-54), the existing 24 wired tests (mechanical churn allowed, behavior identical).

## Root Cause (verify → refute confirmed)
**Why the implementation diverged (impl-gap):** the original plan's "Handle hosting" bullet (198-orbit-sculpt-and-summon-tdd-plan.md:75 — "hosted OUTSIDE the re-rendered/scrolled canvas, re-seated after every render and on scroll, hidden when the seat leaves the visible band") was implemented only in its first clause: the chips were hosted outside the canvas, but never seated on geometry. Spec :23 names all five seats verbatim; TC-198-14 (spec:197) says "five handles appear at their geometry seats"; TC-198-20 (spec:203) pins the bubble "directly above it" and steppers "on the nav-bar line (− left of the pill, + right)".

**Why it escaped host-green (test-gap):** all 24 wired tests assert presence-by-key only (`handleF()`/`bubbleF()` finders, zero `getRect`-based positional assertions — verified across orbit_sculpt_summon_wired_test.dart:144-524); TC-198-71 (handles anchored while scrolling) and the wired half of TC-198-72 (planted circle) **were never written** — only TC-72's overhang math exists (orbit_arc_layout_test.dart:148-162). F6 landed 24 of the ~36 planned tests with no record of what was dropped.

Confirmed mismatches (workflow `wf_b3a2d45a-f09`; each verified against BOTH the mockup HTML and the Dart source):
- **M1 (critical)** handles = bottom text-chip Wrap, not geometry-anchored discs (mockup positionHandles html:1047-1073; impl :472-496)
- **M2** no glow/pulse (mockup pulseH html:192-200, armed teal halo :202; impl has zero BoxShadow)
- **M3** no per-handle icons (mockup 16px SVG glyphs html:1025-1038)
- **M4** no tip-pill below each handle (mockup .h-tip html:197-199, always visible)
- **M5** value bubble fixed bottom-center, not floating above armed handle (mockup .h-val html:216-219; TC-198-20)
- **M6** −/+ centered next to bubble, not corner-flanking the nav band (mockup .nav-step html:205-212; spec :23)
- **M7** cv drag linear −dy/90, not atan2 angle-follow (mockup html:1031-1035; plan Drag-sensitivities bullet :69)
- **M8** og sensitivity −dy/46, missing ÷sp (mockup html:1038-1040; impl :226)
- **M9** stepper press never flash-lifts the dim 650ms (mockup flashDim html:998-1003; TC-198-21)
- **M10 (half)** edit-entry ring-brighten missing (mockup .edit-glow drop-shadow on .ring-svg)
- **M11** banner/Reset default-themed, not green terminal chrome (mockup html:170-172, 225-228)
- **M13** edit overlay stacks below the find layer (mockup z: handles 46/steppers 47 > pill/chips 44; impl :407-412)

Refuted / do-NOT-re-introduce:
- **Mockup jiggle** — never runs even in the mockup (`html:169` selector `.edit-glow .canvas` vs class added to `.canvas` itself). Do not port.
- **Analytic-y origin** — refuted by wf_f2875564-e7f: canvas y depends on `max(0,(contentH−colH)/2)` with two font-metric/textScaler/locale-dependent text heights (viz title :217-228; caption/empty-hint surface:374-397). Origin must be **measured**, not computed.
- **Right-corner stepper at `right:22, bottom:28` as-is** — collides with the find pill (right:16, bottom:bottomInset+40; 40×40 collapsed / ~200×44 expanded). Requires the armed-state bottom re-flow (§Plan step 5) — never ship the corner stepper without it.
- **M12 slop (18px vs ~8px)** — stays a recorded Accepted Difference (original plan); product call, not re-planned here.
- **ARB value rewrite to lowercase+glyph copy** — refuted as planned mechanism: reds orbit_strings_parity_test.dart:132, forces gen-l10n + 3-locale translation churn, and pushes ↕/⟷ into VoiceOver labels ("Increase ring spacing ↕"). Chosen design keeps ARBs untouched (§Plan step 4).

## Real Scope
In scope: `inner_circle_interactive_surface.dart` (edit overlay rework: geometry-anchored handle layer, armed bubble, corner steppers + bottom re-flow, dim-flash, z-order, banner/Reset styling, pulse lifecycle), `orbital_visualization.dart` (canvasKey param; editEmphasis ring-brighten prop), `orbital_ring_painter.dart` (only if brighten lands in paint — prefer the Opacity wrapper at viz:140), `orbit_arc_layout.dart` (hoist canvas consts 320/160; pure anchor + cv-pointer-mapping helpers), the missing TC-198-72 scroll-compensation seam, tests in 3 files (1 new).
Out of scope (owner): knob model/persistence/Move registry (198 Slice D — done); F12 sim case + device proof (198 close-out session); feed_wired yield-gate internals (F9 — done); find matching (Slice C — done); M12 slop (product); orbit3 lab anything.

## Files To Inspect Next
Production: lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart (:221-279 drag, :350 entry, :370 editDim, :407-543 overlay, :472-496 Wrap→handles, :499-543 bubble/steppers, :582-633 pill); lib/features/orbit/presentation/widgets/orbital_visualization.dart (:59-60 consts, :100-149 layout/painter/editDim, :217-233 root Column/canvas SizedBox); lib/features/orbit/domain/orbit_arc_layout.dart (:19-36 consts, :155-156 seat angles, :167-182 arc radius/phi, :217-235 overhang, :238 computeOrbitLayout); lib/features/orbit/presentation/widgets/unread_orbit_indicator.dart (:79-95 motion-gate donor); lib/features/orbit/presentation/screens/orbit_screen.dart (:306-313 nav offsets — context only).
Direct tests: test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart (24 existing; helpers :100-141); test/features/orbit/domain/orbit_arc_layout_test.dart (15 pure; :148 TC-72 math); NEW test/features/orbit/presentation/widgets/orbit_edit_handle_test.dart.
Dependency-only context: integration_test/orbit_performance_harness.dart (:334-337 pops route mid-edit — ticker-leak trap; :489-519 F13 interaction); test/l10n/orbit_strings_parity_test.dart (:111-137 block-3 baselines — must NOT need edits); test/features/orbit/presentation/widgets/unread_orbit_indicator_test.dart (:144-176 reduce-motion test donor); lib/core/theme/background_readable_colors.dart.

## Existing Tests Covering This Area
- orbit_sculpt_summon_wired_test.dart — 24 wired tests: gesture lifecycle, arm/step/drag/clamp, Reset, tap-away, persistence, find, composition, reset seam (**all presence-by-key; zero positional**) — exists, pinned GROUP_TESTS run_test_gates.sh:254
- orbit_arc_layout_test.dart — 15 pure-math locks incl. TC-72 overhang (:148) — exists
- orbit_strings_parity_test.dart — 3-locale key parity + en baselines (:132 pins 'Ring spacing') — exists, pinned :251
- orbital_visualization_test.dart :316-322 — the house positional-assert idiom (getRect + overlaps + reason) — donor
- unread_orbit_indicator_test.dart :144-176 — reduce-motion freeze idiom — donor
Missing coverage gaps: TC-198-71 (anchor/scroll/band-hide) — NO test anywhere; TC-198-72 wired half (scroll compensation) — seam itself absent; TC-198-56 ensureSemantics sweep — original matrix row :231 claims F6 coverage that does not exist; TC-198-59 edit-pulse reduce-motion — no test (nothing to gate on HEAD); every visual property (glow, icon, tip-pill, bubble position, stepper position) — untested.
Already in curated family arrays?: wired + parity + arc-layout files run under `./scripts/run_test_gates.sh groups` (orbit gate, 403 green at 198 close-out).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

Helpers to add once in orbit_sculpt_summon_wired_test.dart: `Offset canvasOrigin(tester)` (getTopLeft of the new canvas key), `Offset anchorOf(knob, geometry, itemCount)` (pure formulas below), `Rect handleRect(knob)`. Anchor formulas (centre-local; canvas = origin + (160+dx, 160+overhang+dy)): sp=(0,+108·sp) · av=(0,−62·sp) · og=(0,−r0) · cv=(+r0·sinφ0,−r0·cosφ0) · pr=(−r0·sinφ0,−r0·cosφ0), r0=(108+46·og)·sp, φ0=orbitArcPhi(r0,cv). NOTE: sp/arc anchors sit on painted geometry, NOT on seats (ring2 seats are offset +15°) — assert against formulas, never against seat rects. All new tests use bounded pumps (`settle()` = 16×90ms); **never `pumpAndSettle` while `_editing`** (repeating pulse controller ⇒ timeout).

1. orbit_sculpt_summon_wired_test.dart::'TC-198F-01 five handles seated at geometry anchors (expanded)'
   - Tier: wired widget (host). Shape: 20 friends → expand badge → long-press → for each knob: `tester.getCenter(handleF(k))` within 2px of `canvasOrigin + (160+dx, 160+overhang+dy)`.
   - RED on HEAD: handles sit in the bottom Wrap at bottom:96 — every position assert fails.
   - GREEN: five discs at formula anchors. Mutation: replace anchor math with any constant offset → red.
2. orbit_sculpt_summon_wired_test.dart::'TC-198F-02 handles re-seat same-frame on knob change; Reset re-seats to defaults'
   - Tier: wired. Drag sp by −40 → sp/av/og/cv/pr positions match formulas at the NEW geometry on the next pump (no 1-frame lag: assert immediately after the drag-update pump); tap Reset → positions match default-geometry formulas.
   - RED: no anchored handles. Mutation: seat anchors from post-frame-measured geometry only (introduce lag) → red.
3. orbit_sculpt_summon_wired_test.dart::'TC-198-71 handles track scroll; off-band hidden not unmounted; armed survives'
   - Tier: wired. 50 friends expanded (deep stack) → edit → arm og → `_scroll.jumpTo(+120)` via drag: every visible handle's center shifts by exactly −120 in y; scroll until og's anchor exits the viewport → its render object reports hidden (Offstage/Visibility) but `handleF(og)` still finds the widget (maintained state) and `_armed` unchanged (bubble/steppers still present); scroll back → visible at the correct anchor.
   - RED on HEAD: no scroll listener exists — chips do not move at all (delta assert fails).
   - GREEN as above. Mutation: remove the scroll listener → red; replace Offstage-hide with conditional removal → the "still finds widget" assert red.
4. orbit_sculpt_summon_wired_test.dart::'TC-198F-04 live drag never interrupted by re-seat/band-hide; yield gate held'
   - Tier: wired. Start a cv drag; mid-gesture push the anchor off-band (large og swing via the same drag's geometry updates); the gesture continues to full clamp range (extends TC-198-23) and `editEvents` (onEditSessionActiveChanged) never emits false mid-drag (INV-8 re-verified under the new hide transition).
   - RED: no anchored/band-hide machinery. Mutation: hide via subtree removal (disposes recognizer) → red.
5. orbit_sculpt_summon_wired_test.dart::'TC-198-72 planted circle: og/cv drag on a deep stack keeps the circle stationary (scroll compensates)'
   - Tier: wired. 50 friends expanded, scrolled so the circle is on-screen; drag og through a large delta: the user-avatar center's viewport y (getCenter on the center-avatar key) moves <8px across the drag (scroll offset absorbs Δoverhang, math half already locked at orbit_arc_layout_test.dart:148).
   - RED on HEAD: **the compensation seam does not exist** (viz:110's comment notwithstanding) — circle displaces by Δoverhang.
   - GREEN as above. Mutation: drop the compensation jumpTo → red. Constraint: the re-seat path is READ-ONLY on _scroll; only this drag handler writes; scheduler-phase guard on the listener.
6. orbit_sculpt_summon_wired_test.dart::'TC-198F-06 RTL: tip↔knob assignment pinned in screen space'
   - Tier: wired. Wrap host in `Directionality(rtl)` + ar locale: cv handle sits at the screen-RIGHT tip in LTR; under RTL assert the DEFINED contract: anchors use layout-signed dx via `Positioned(left:)` (never PositionedDirectional), so cv follows the mirrored +φ tip to screen-left and pr to screen-right — and the two never swap mid-session. No overflow errors (extends TC-198-58).
   - RED: no anchored handles. Mutation: double-flip via PositionedDirectional → red.
7. orbit_sculpt_summon_wired_test.dart::'TC-198F-07 collapsed edit: av/sp at ring anchors; cv/pr/og absent'  (position-upgrade of green TC-198-26)
   - Tier: wired. ≤13 items → edit → av at (0,−62·sp), sp at (0,+108·sp) from formulas; other three absent. RED: Wrap positions. Mutation: mount all 5 while collapsed → red (existing) + anchor mutation → red.
8. orbit_sculpt_summon_wired_test.dart::'TC-198F-08 keyboard during edit+find does not desync handles'
   - Tier: wired. Edit → open find (keyboard: pump with `viewInsets` via MediaQuery override or TestWindow) → constraints change → handle centers still match formulas against the re-measured origin.
   - RED: no measurement/invalidation machinery. Mutation: cache origin unkeyed by constraints → red.
9. orbit_sculpt_summon_wired_test.dart::'TC-198F-09 first frame after long-press: no crash, handles appear only positioned'
   - Tier: wired. Immediately after `longPressBg` first pump: either handles absent/Offstage or already at valid anchors — never at (0,0)/top-left cluster; no exceptions (`tester.takeException()` null).
   - RED: N/A-on-HEAD structurally (Wrap never at (0,0)) — this row is GREEN-guard for the new machinery; RED proven by temporarily asserting anchored positions on first frame during execution. Mutation: drop the first-frame guard (render before measurement) → red.
10. orbit_edit_handle_test.dart::'handle visual contract: circular disc in ≥44pt target, per-knob icon, tip-pill below'  (NEW file, widget tier)
    - Tier: widget. Pump the extracted `OrbitEditHandle` (new public widget) for each knob: hit target ≥44×44 (getSize), disc decoration `shape: BoxShape.circle` ~30px, per-knob icon present (each knob's own `ValueKey('orbit-handle-icon-<name>')`), tip-pill Text == l10n `orbit_handle_*` value + separate letter-free glyph Text (↕/⟷) below the disc (tip center.dy > disc center.dy).
    - RED on HEAD: widget does not exist (compile-level red documented as "new-API red").
    - GREEN as above. Mutation: drop the 44pt floor → red (INV-F7, closes spec decision #9's uncovered handle case); swap two icons → red.
11. orbit_edit_handle_test.dart::'TC-198F-11 armed treatment: teal halo; unarmed: green border'
    - Tier: widget. armed:false → border 0xFF1ED760, boxShadow non-empty green; armed:true → border/halo 0xFF4ECDC4 + translucent teal fill. RED: no such widget/decoration. Mutation: remove boxShadow → red.
12. orbit_edit_handle_test.dart::'TC-198-59 pulse animates; frozen under disableAnimations AND accessibleNavigation'
    - Tier: widget ×2 tests. Unarmed handle: BoxShadow blur differs across two pumps half a period apart; with `MediaQuery(disableAnimations:true)` (and separately `accessibleNavigation:true`) decoration identical across the same pumps while the handle stays visible (donor idiom unread_orbit_indicator_test.dart:144-176; production via `_syncMotionPreference` re-evaluated in didChangeDependencies).
    - RED: no pulse exists (first half); gate half reds until gate implemented. Mutation: drop the reduce-motion gate → red.
13. orbit_sculpt_summon_wired_test.dart::'TC-198F-13 pulse/timer lifecycle: stops on session end; survives route-pop mid-edit'
    - Tier: wired. Enter edit (pulse running: decoration changes across pumps) → tap-away → decoration static + no pending timers; re-enter edit → `pumpWidget(const SizedBox())` while editing → no exception, no ticker-leak teardown error (mirrors the F13 harness popping the route mid-edit, orbit_performance_harness.dart:334-337).
    - RED: pulse absent (first assert). Mutation: remove controller dispose → teardown red; start pulse outside `_setEditing(true)` → "static after tap-away" red.
14. orbit_sculpt_summon_wired_test.dart::'TC-198-20R value bubble floats above the ARMED handle and moves on re-arm'
    - Tier: wired. Arm av → bubble (existing key) horizontally centered on av's handle center ±2px and bottom-edge above the disc top (gap ≤12px); arm sp → bubble relocates above sp; teal text color. Existing '1.0×' content asserts stay.
    - RED on HEAD: bubble is fixed at bottom:40 center. Mutation: reattach bubble to a fixed Positioned → red.
15. orbit_sculpt_summon_wired_test.dart::'TC-198F-15 bubble tracks the handle and updates live mid-drag'
    - Tier: wired. Drag av (which arms it): mid-drag pump — bubble text ≠ '1.0×' AND bubble stays above the moving handle's current anchor. RED: position half. Mutation: update bubble only on drag-end → red.
16. orbit_sculpt_summon_wired_test.dart::'TC-198-20S −/+ steppers land at the bottom corners while armed'
    - Tier: wired. Arm any knob: decrease at left:22 (getTopLeft.dx ≈ 22±2), increase at right (getTopLeft.dx ≈ maxWidth−22−48±2), both bottom: `bottomInset+28` band, 48×48; absent when nothing armed (existing assert kept).
    - RED on HEAD: both steppers sit in a centered Row at bottom:40. Mutation: recentre steppers → red.
17. orbit_sculpt_summon_wired_test.dart::'TC-198F-17 armed-state bottom re-flow: find pill lifts and stays usable'
    - Tier: wired. Arm a knob → find pill (collapsed) rises to the `bottomInset+88` band (clear of the + stepper's 28..76 band +4px slop) and its tap still opens find WITHOUT ending edit (banner persists — extends TC-198-50/51); disarm → pill returns to bottomInset+40. With find OPEN (expanded 200px pill) + armed: TextField tap focuses, edit persists.
    - RED: no re-flow exists (and on HEAD no corner stepper to clear — reds on the lift assert). Mutation: drop the lift → disjointness row 18 red; drop "pill tap keeps edit" → this red.
18. orbit_sculpt_summon_wired_test.dart::'TC-198F-18 bottom-band disjointness sweep (armed × find × chips × keyboard)'
    - Tier: wired. Armed + find open + 2 chips + simulated keyboard inset: pairwise `getRect(...).overlaps(...)` false across {−, +, pill, each chip}; chip strip lifts to its armed-state band; steppers/pill/chips all carry the `bottomInset +` term (house idiom orbital_visualization_test.dart:316-322).
    - RED: centered stepper row lacks the bottomInset term (latent keyboard gap) AND no re-flow. Mutation: remove bottomInset from steppers → red.
19. orbit_sculpt_summon_wired_test.dart::'TC-198-21R stepper press flash-lifts the dim 650ms; cancels safely'
    - Tier: wired. Arm av → press + → `editDim` prop on OrbitalVisualization flips false (read the widget's editDim/emphasis props); pump 650ms (bounded) → true again; rapid double-press re-arms (still lifted at t=900ms from first press); press then tap-away inside the window → pump past 650ms → no dim flip after session end, no pending-timer teardown failure. Timer = cancellable field, cancelled in dispose AND `_setEditing(false)`, `!mounted` guard.
    - RED on HEAD: `_dimFlash` does not exist — dim never lifts on a stepper press. Mutation: revert `editDim: _editing && !_draggingHandle && !_dimFlash` → red; remove timer cancel → teardown red.
20. orbit_sculpt_summon_wired_test.dart::'TC-198F-20 ring emphasis while editing; find-lit nodes stay full-bright through the flash'
    - Tier: wired. Pin values: new `editEmphasis` prop drives ring layer Opacity {edit-idle: brightened value, dragging: 1.0, flash: 1.0} independent of node dim (0.22); active find match node opacity 1.0 during dim-flash (INV-5 re-verified under the new flash transition). Seam: Opacity wrapper at orbital_visualization.dart:140 (if painter fields change instead, extend shouldRepaint orbital_ring_painter.dart:114-118).
    - RED on HEAD: no editEmphasis prop; ring fixed at 0.45 while editing. Mutation: key brighten to editDim (drops to 1.0-discontinuity mid-drag) → the pinned-triple assert red.
21. orbit_arc_layout_test.dart::'og drag sensitivity scales with spacing (÷46·sp)' + wired twin 'TC-198F-21 same dy, sp=1.5 → og delta ÷1.5'
    - Tier: unit (extract `orbitGapDragDelta(dy, spAtDragStart)` pure) + wired (drag og same dy at sp 1.0 vs 1.5 → knob deltas ratio 1.5±ε; sp snapshotted at drag start `_dragStart.spacingScale`).
    - RED on HEAD: fixed −dy/46 (inner_circle_interactive_surface.dart:226). Mutation: drop the ÷sp → both red.
22. orbit_arc_layout_test.dart::'cv pointer-angle mapping: cv = clamp(|atan2(px−cx, cy−py)|/1.25, 0.5, 2.5)' + wired twin 'TC-198F-22 horizontal drag on the cv handle changes the wrap'
    - Tier: unit (new pure `orbitArcWrapFromPointer(centre, pointer)`) + wired (pure-HORIZONTAL drag on the anchored cv handle changes arcWrap — impossible on HEAD where cv uses −dy/90 only; assert the knob lands at the atan2 prediction for the final pointer position).
    - RED on HEAD: dx is ignored for cv. Mutation: revert to −dy/90 → both red.
23. orbit_sculpt_summon_wired_test.dart::'TC-198F-23 banner + Reset wear the green terminal chrome'
    - Tier: wired. Banner Text color 0xFF1ED760 with a green-tinted bordered pill decoration; Reset wrapped in the dark bordered pill treatment (assert decoration border non-null + colors), copy/position unchanged ('TAP AWAY TO FINISH', top-center; Reset top-left).
    - RED on HEAD: glassSurface/no-border banner (:437-449), bare TextButton Reset (:462-466). Mutation: swap back to TextButton → red.
24. orbit_sculpt_summon_wired_test.dart::'TC-198-56 ensureSemantics sweep: exactly one labeled button per handle; steppers/Reset/pill labeled'
    - Tier: wired. `tester.ensureSemantics()`: per visible handle exactly ONE button node labeled with the l10n handle name (tip-pill inside the handle's Semantics subtree or ExcludeSemantics — no double announcement; glyphs NEVER in labels); stepper decrease/increase labels glyph-free; Reset + pill buttons present.
    - RED on HEAD: the sweep does not exist (original matrix row :231 claimed it falsely); glyph-free assert also guards the M4 design. Mutation: move tip-pill outside the Semantics subtree → "exactly one node" red.
25. orbit_sculpt_summon_wired_test.dart::'TC-198F-25 z-order: armed steppers/handles win pointer events over underlying seats; find layer contract preserved'
    - Tier: wired. A handle whose disc overlaps a seat (sp≥1.4 crowding): tapping the handle arms it and does NOT open a chat (pins the intentional overlap: node-tap-in-edit is tap-away anyway); the find pill/chips remain tappable per rows 17/18 — the surface keeps find ABOVE edit for shared bands (mockup z honored only for spatially disjoint elements, per refute C4).
    - RED: no anchored handles to overlap. Mutation: reorder find below edit for the shared band → row 17 pill-tap red.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

`WIRED` = test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart (pinned GROUP_TESTS run_test_gates.sh:254) · `HANDLE` = test/features/orbit/presentation/widgets/orbit_edit_handle_test.dart (NEW) · `LAYOUT` = test/features/orbit/domain/orbit_arc_layout_test.dart · gate `G` = `./scripts/run_test_gates.sh groups` · gate `H` = `./scripts/run_host_test_gates.sh feature-host-all`

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| M1 / TC-198-14R | UI geometry | wired | WIRED::TC-198F-01 | handles in bottom Wrap | anchor math → constant | G | already pinned :254 |
| M1 / re-seat | UI geometry | wired | WIRED::TC-198F-02 | no anchored handles | post-frame-only seating (lag) | G | already pinned |
| TC-198-71 | scroll/anchor | wired | WIRED::TC-198-71 | no scroll listener; chips fixed | remove listener / unmount-hide | G | already pinned |
| INV-F2 + INV-8 | drag continuity | wired | WIRED::TC-198F-04 | no band-hide machinery | hide by subtree removal | G | already pinned |
| TC-198-72 (wired) | scroll compensation | wired | WIRED::TC-198-72 | seam absent — circle displaces | drop compensation jumpTo | G | already pinned |
| TC-198-58R | RTL | wired | WIRED::TC-198F-06 | no anchored handles | PositionedDirectional double-flip | G | already pinned |
| TC-198-26R | collapsed anchors | wired | WIRED::TC-198F-07 | Wrap positions | mount 5 collapsed / anchor const | G | already pinned |
| keyboard sync | constraints invalidation | wired | WIRED::TC-198F-08 | no origin re-measure | unkeyed origin cache | G | already pinned |
| first-frame | measurement guard | wired | WIRED::TC-198F-09 | guard absent (new-machinery) | render before measurement | G | already pinned |
| M3+M4+44pt | widget visual | widget | HANDLE::visual contract | widget absent (new-API red) | drop 44pt floor / swap icons | H + G | AUTO (glob) |
| M2 armed | widget visual | widget | HANDLE::TC-198F-11 | no BoxShadow anywhere | remove boxShadow | H | AUTO (glob) |
| M2 pulse / TC-198-59 | motion + a11y | widget ×2 | HANDLE::TC-198-59 pair | no pulse; no gate | drop reduce-motion gate | H | AUTO (glob) |
| ticker lifecycle | perf/leak | wired | WIRED::TC-198F-13 | pulse absent; F13 pops mid-edit | remove dispose / start outside choke | G | already pinned |
| M5 / TC-198-20R | bubble position | wired | WIRED::TC-198-20R | bubble fixed bottom-center | fixed Positioned | G | already pinned |
| M5 live | bubble tracking | wired | WIRED::TC-198F-15 | position half missing | update on drag-end only | G | already pinned |
| M6 / TC-198-20S | stepper corners | wired | WIRED::TC-198-20S | centered Row at bottom:40 | recentre steppers | G | already pinned |
| find keep-out | composition | wired | WIRED::TC-198F-17 | no armed re-flow | drop pill lift | G | already pinned |
| bottom band | collision + keyboard | wired | WIRED::TC-198F-18 | no bottomInset on steppers | remove bottomInset term | G | already pinned |
| M9 / TC-198-21R | dim flash | wired | WIRED::TC-198-21R | `_dimFlash` absent | revert editDim expr / uncancel timer | G | already pinned |
| M10-half + INV-5 | ring emphasis | wired | WIRED::TC-198F-20 | no editEmphasis prop | key brighten to editDim | G | already pinned |
| M8 | drag math | unit + wired | LAYOUT::og÷sp + WIRED::TC-198F-21 | fixed −dy/46 (:226) | drop ÷sp | H + G | AUTO + already pinned |
| M7 | drag math | unit + wired | LAYOUT::cv atan2 + WIRED::TC-198F-22 | dx ignored (−dy/90) | revert to −dy/90 | H + G | AUTO + already pinned |
| M11 | chrome styling | wired | WIRED::TC-198F-23 | default-themed banner/Reset | revert to TextButton | G | already pinned |
| TC-198-56 | a11y sweep | wired | WIRED::TC-198-56 | sweep never existed | tip-pill outside Semantics subtree | G | already pinned |
| M13 | z-order/hit | wired | WIRED::TC-198F-25 | no anchored handles overlap seats | find below edit in shared band | G | already pinned |
| preservation | 24 existing wired | wired | WIRED (all 24, churned not weakened) | n/a (GREEN sentinels) | any regression | G (orbit count grows 403→403+~27) | already pinned |
| preservation | knob math/persist | unit | Slice-P pure 30 + TC-33/36/38 | n/a GREEN | any regression | G + H | already pinned / AUTO |
| preservation | yield gate INV-8 | wired | feed_swipe suite (19) | n/a GREEN | any regression | `./scripts/run_test_gates.sh feed` (or the pinned feed_swipe file) | already registered (198 F9) |
| preservation | l10n | parity | orbit_strings_parity_test.dart (UNTOUCHED — no ARB edits) | n/a GREEN | any ARB value edit | G | already pinned :251 |
| preservation | FAB scrim TC-198-65 | wired + preservation | existing rows + orbit_qr_entry_migration_test.dart | n/a GREEN | re-parent FAB | G | already pinned |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the measured canvas origin is derived state — reconstructed on constraints change (TC-198F-08) and first frame (TC-198F-09); knob persistence across remount already locked (TC-198-33, stays green). Edit session is transient by design (reset seam TC-198-63 sentinel). Covered.
- **Sibling-surface consistency:** no capability gate changes. The LTR/RTL tip↔knob symmetry is the sibling-symmetry analog → TC-198F-06. The five handles get identical treatment (one widget, per-knob params) → HANDLE::visual contract iterates all knobs. Covered.
- **Destructive-action side-effects:** Reset asserts values + persisted deletion (existing TC-198-25/36 green) AND re-seats handles to default anchors (TC-198F-02); session end / widget dispose asserts tickers+timers actually cancelled (TC-198F-13, TC-198-21R) — what is removed, not just the affordance. Covered.
- **Invariant re-verification under new transitions:** dim-flash (new transition) re-verifies INV-5 find-lit brightness (TC-198F-20); band-hide (new transition) re-verifies armed-state + INV-8 yield gate mid-drag (TC-198F-04, TC-198-71); armed re-flow re-verifies TC-198-50/51 find-usable-during-edit (TC-198F-17/18/25). Covered.

## Invariants (locked by tests)
- INV-F1 handles are geometry-anchored, formula-verifiable → TC-198F-01/02/07 + TC-198-71
- INV-F2 a live drag is never interrupted by re-seat/hide/rebuild → TC-198F-04 (+existing TC-198-23)
- INV-F3 (=INV-8) edit session yields the host swipe; unaffected by hide/re-flow → TC-198F-04 + feed_swipe sentinels
- INV-F4 find fully usable during edit at every armed/keyboard state → TC-198F-17/18/25 (+existing TC-198-50/51)
- INV-F5 (=INV-5) find-lit nodes stay full-bright through dim-flash/drag → TC-198F-20
- INV-F6 no ticker/timer outlives the session or the widget → TC-198F-13 + TC-198-21R
- INV-F7 every handle/stepper ≥44pt (spec decision #9 — previously untested for handles) → HANDLE::visual contract
- INV-F8 knob semantics/persistence byte-identical → Slice-P/D sentinels
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **RED tests** — add catalog rows 1–25 (skip 9's red-half note); run the focused commands (§Acceptance Gates) and record each failing for its documented reason. New-API reds (HANDLE file) recorded as compile-level.
2. **Pure layer** (`orbit_arc_layout.dart`): hoist `kOrbitCanvasSize=320` / `kOrbitCanvasCenter=160` (replace VIZ privates); add pure helpers `orbitHandleAnchor(knob, geometry, {mirrored})` (five formulas), `orbitGapDragDelta(dy, sp)`, `orbitArcWrapFromPointer(centre, pointer)`. Unit rows go green.
3. **Viz seam** (`orbital_visualization.dart`): new `canvasKey` param placed on the canvas SizedBox (:229) — a key on the viz root is WRONG by titleHeight+24; new `editEmphasis` bool driving the ring-layer Opacity at :140 independently of `editDim` (extend `shouldRepaint` only if painter fields change).
4. **Handle widget** (extract `OrbitEditHandle` into the surface file or its own widget file): 30px disc in a ≥44pt hit target, per-knob icon (CustomPaint strokes mirroring the five glyphs, `ValueKey('orbit-handle-icon-<name>')`), tip-pill = l10n `orbit_handle_*` value + separate letter-free glyph literal (scan-exempt per l10n_integrity_test.dart:121-134; **ARBs untouched**; glyph in ExcludeSemantics), pulse via `_syncMotionPreference` idiom (unread_orbit_indicator.dart:79-95) re-evaluated in didChangeDependencies, armed teal halo. **Preserve `ValueKey('orbit-handle-${knob.name}')` on the pan/tap GestureDetector itself** (tests + F13 perf harness target it, orbit_performance_harness.dart:505).
5. **Surface rework** (`inner_circle_interactive_surface.dart`): TickerProviderStateMixin; pulse start/stop ONLY in `_setEditing` (:128-133 choke point covers reset/tap-away/node-tap/chip-open); dispose controllers+timers in dispose (F13 pops the route mid-edit). Replace the Wrap (:472-496) with the anchored handle layer: per-build analytic anchors from current `_geometry` + measured origin (localToGlobal with `is RenderBox && hasSize` guard, donor conversation_screen.dart:896-898) re-measured post-frame on scroll/constraints/items/expanded change with analytic Δoverhang correction; ListenableBuilder on `_scroll` scoped to the handle layer (read-only listener, scheduler-phase guard); Offstage+IgnorePointer+ExcludeSemantics band-hide (both axes; viewport = constraints, **never minus viewInsets**); first-frame guard. Bubble → floats above the armed handle (teal). Steppers → `Positioned(left:22 / right:maxWidth−22−48, bottom: bottomInset+28)` (physical left/right per house RTL convention, orbit_view_toggle_button.dart:9-13). Armed-state bottom re-flow: pill lifts to bottomInset+88, chip strip lifts clear, ALL bottom-anchored edit elements carry `bottomInset +` (fixes the shipping centered row's latent keyboard gap). Dim-flash Timer + `editDim: _editing && !_draggingHandle && !_dimFlash` (:370); `editEmphasis: _editing`. cv/og drag mappings → the new pure helpers (cv needs absolute pointer position relative to the measured centre). Banner/Reset chrome per row 23. Stack order: find layer stays above edit for shared bands (refute C4) — mockup z honored only where spatially disjoint. Implement the TC-198-72 compensation write in the og/cv drag handler (single scroll writer).
   Stop-if: origin measurement proves unstable inside the wired harness (fake fonts change metrics) → re-plan the assert tolerances, do not loosen to presence-only.
6. Churn the 24 existing wired tests only where mechanics moved (chips→discs); never weaken an assertion.
7. Rerun direct → preservation → named gates (§Acceptance Gates). Update the orbit gate expected count in this plan's Execution Progress.
8. Hygiene: `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (repo rule — the 198 close-out skipped it once already).

## Risks And Edge Cases
- Anchor jitter during og/cv drags (canvas height changes) → hybrid frame-sync + TC-198F-02's same-frame assert pins it
- Scroll-listener feedback loop with the TC-72 compensation writer → single-writer rule + scheduler-phase guard, pinned by TC-198-72/TC-198-71 together
- Handle unmount mid-drag kills the recognizer → Offstage-hide, TC-198F-04
- φ0 > π/2 puts tips below centre / off-canvas x (og=2.5·sp=1.5 → r0≈334) → band-hide both axes; steppers remain the recovery path (mockup parity)
- Keyboard/SafeArea: constraints.maxHeight GROWS when the keyboard opens (resizeToAvoidBottomInset:false) → origin cache keyed on constraints, TC-198F-08
- Pending-timer/ticker teardown in short tests → cancellable fields + bounded pumps, TC-198F-13/TC-198-21R
- 3-button kOrbit3PrototypeEnabled nav pill overlaps left:22 at 320pt → debug-only lab flag; recorded Accepted Difference
- ring2 6-o'clock anchor is on the painted ring, not a seat (+15° offset) → tests assert formulas, never seat rects

## Device/Relay Proof Profile
host-only for closure (pure UI geometry/styling/gesture — no OS/crypto/transport boundary).
Recommended belt-and-braces (not closure-blocking): one iOS-sim run of the F13 perf harness (`ORBIT` target) — it long-presses, drags a handle, and pops the route mid-edit, which exercises the ticker lifecycle on a real device pipeline; fold into the already-pending 198 F12/SIM-PC session.
Deferred device work → 198 close-out session: F12 cold-start sim case (unchanged by this slice).

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# 0. Dirty-tree snapshot (before anything)
git status --short

# 1. RED (before production edits) — each must FAIL for its documented reason
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart \
  --plain-name 'TC-198F-01 five handles seated at geometry anchors (expanded)'   # RED: Wrap positions
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart \
  --plain-name 'TC-198-71 handles track scroll; off-band hidden not unmounted; armed survives'  # RED: no scroll listener
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart \
  --plain-name 'TC-198-72 planted circle: og/cv drag on a deep stack keeps the circle stationary (scroll compensates)'  # RED: seam absent
flutter test test/features/orbit/domain/orbit_arc_layout_test.dart               # RED: 2 new pure tests (og÷sp, cv atan2)
flutter test test/features/orbit/presentation/widgets/orbit_edit_handle_test.dart # RED: new-API/compile

# 2. Direct GREEN (after fix)
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart   # expect: 24 existing + ~19 new, all pass
flutter test test/features/orbit/presentation/widgets/orbit_edit_handle_test.dart           # expect: ~4 pass
flutter test test/features/orbit/domain/orbit_arc_layout_test.dart                          # expect: 15 + 2 pass

# 3. Preservation sentinels
flutter test test/l10n/orbit_strings_parity_test.dart          # UNTOUCHED, stays green (no ARB edits in this slice)
flutter test test/features/orbit/ test/l10n/orbit_strings_parity_test.dart   # orbit host cluster: 403 + new, 0 regressions
# feed↔orbit yield gate (198 F9):
flutter test test/features/feed/presentation/screens/feed_swipe_* 2>/dev/null || ./scripts/run_test_gates.sh feed   # expect: 19 (F9 rows green)

# 4. Named gate for the touched subsystem
./scripts/run_test_gates.sh groups            # GROUP_TESTS incl. wired pin :254 + parity :251 — expect prior green + new count (record in Execution Progress)

# 5. l10n literal-scan budget (must NOT grow: 3 orbit3 / 0 production-orbit)
GRAPH_OK=1 grep -rn "'[A-Za-z]" lib/features/orbit --include='*.dart' | grep -v "ValueKey\|debugPrint\|//" | wc -l  # eyeball vs baseline; authoritative pair = orig plan §gates (198-orbit-sculpt-and-summon-tdd-plan.md:131-133)

# 6. Perf/leak belt-and-braces (optional, sim required)
# /sims → run the ORBIT perf target once; watch for ticker-leak teardown errors

# 7. Hygiene
flutter analyze            # 0 new issues (5 pre-existing in untouched files at 198 close-out)
git diff --check
```

## Known-Failure Interpretation
- Expected RED (pre-fix): every catalog row 1–25 per its documented reason; HANDLE file reds at compile (new API).
- Pre-existing dirty: `info.plist` modified in the working tree (unrelated — do not revert); 1 flaky ML-004 in the groups gate (passes standalone, documented at 198 close-out); 5 pre-existing analyze issues in untouched files; l10n literal-scan carries exactly 3 orbit3 literals (pre-existing RED budget — must not grow).
- Environment blocker (NOT product): no booted iOS simulator for the optional F13 leg.
- Scope drift (BLOCKING): any red in Slice-P pure tests, persistence rows (TC-33/36/38), find Group E, feed_swipe, parity, or account_migration — those subsystems must not be touched.

## Done Criteria
- [ ] RED added first; each failed for its documented reason (recorded in Execution Progress).
- [ ] Mutation-verified: every production edit has its named re-red revert (matrix column 6).
- [ ] Direct GREEN + preservation sentinels + `groups` gate pass; new orbit count recorded.
- [ ] No DB change (no migration test needed — none in scope).
- [ ] Host-only closure; optional F13 sim leg noted, not blocking.
- [ ] All new tests visible in gates: wired/pure/parity files already pinned; HANDLE file auto-globbed (verify it appears in `run_host_test_gates.sh feature-host-all` output).
- [ ] flutter analyze 0 new; git diff --check clean; no Scope Guard violations.
- [ ] graphify full update + arch refresh run after code changes.

## Scope Guard (hard "Do not")
- Do not touch `orbit_geometry_prefs.dart` model/ranges/persistence, the Move registry entry, or `orbit_geometry_prefs_use_cases.dart` (198 Slice D owns; sentinels lock).
- Do not edit ARB files or regenerate l10n — the glyphs are Dart-side letter-free literals; `orbit_strings_parity_test.dart` stays byte-identical.
- Do not modify feed_wired yield-gate internals, `orbit_find_matches.dart`, the F12 sim case, F13 perf budgets, or `overflow_badge.dart` behavior.
- Do not change the long-press slop (M12 = Accepted Difference; product owns).
- Do not port the mockup jiggle (refuted — never runs in the mockup itself).
- Do not remove/rename `ValueKey('orbit-handle-${knob.name}')`, `orbit-edit-value-bubble`, `orbit-edit-step-*`, `orbit-edit-banner`, `orbit-edit-reset` keys (tests + F13 harness target them).
- Do not use `PositionedDirectional` for handle/stepper placement (RTL double-flip); do not subtract viewInsets from the band-hide viewport.
- Do not weaken any of the 24 existing wired assertions while churning.

## Accepted Differences / Intentionally Out Of Scope
- Tip-pill copy keeps the existing Title-case l10n values ('Ring spacing' + separate ↕ glyph) vs the mockup's lowercase 'ring spacing ↕' — avoids ARB churn/translation round-trip and keeps German noun capitalization; **flag to product**, revisit via new `orbit_handle_*_tip` keys if rejected.
- "−/+ flank the nav pill" is expressed in surface coordinates (`bottomInset+28`, left/right 22) — the surface is SafeArea-inset while the nav pill is screen-space (`max(16, safeBottom−14)`), so pixel-perfect alignment with the nav line is device-dependent by construction (refute C6).
- Find pill lifts while a knob is armed (bottomInset+40 → +88) — a deliberate deviation from the mockup (whose pill sits higher by default) to honor BOTH the corner steppers and TC-198-50/51; the mockup z-order (edit above find) is honored only for spatially disjoint elements.
- Off-viewport tips (horizontal) are hidden like vertical band exits; steppers remain the recovery path (mockup lets them clip off-bezel too).
- 3-button `kOrbit3PrototypeEnabled` nav pill overlaps the left stepper at 320pt — debug-only lab flag, not shipped chrome.
- M12 long-press slop 18px (framework) vs mockup ~8px — pre-existing Accepted Difference, unchanged.

## Dependency Impact
- 198 close-out session (device proof F12/SIM-PC) depends on this slice: run it AFTER this lands so the sim exercises the final edit UI; the F13 ORBIT perf interaction (drag via `orbit-handle-spacingScale` key) keeps working because the key is preserved.
- Any future 197/196 orbit chrome work must respect the armed-state bottom re-flow contract (TC-198F-17/18).

## Reviewer Findings
(to be filled by the sufficiency reviewer at execution handoff — plan self-check below)
Self-check against references/sufficiency-checklist.md: spec-case totality ✔ (all 12 confirmed mismatches + reopened TC-198-14/20/21/26/56/58/59/71/72 have matrix rows); every INV locked ✔; every edit mutation-named ✔; no vacuous coverage ✔ (each RED reason cites the HEAD mechanism); no DB change ✔ (row N/A); no OS/crypto boundary → host closure justified ✔; PROD-CRITICAL leg: unchanged F12 sim (pre-existing) + optional F13 leg named ✔; preservation sentinels named with gates ✔; literal gates ✔; registration per test ✔ (one NEW auto-glob file, rest already pinned); known-failure interpretation ✔; dirty-tree snapshot step ✔; refuted findings recorded ✔; blind-spot sweep: 4/4 rows or justified ✔; zero empty matrix cells ✔.

## Arbiter Decision
Structural blockers: none identified at planning time. | Deferred details: exact new-test count for the `groups` gate expected number (record at execution); assert-tolerance tuning for measured origins under test fonts (Stop-if in step 5). | Accepted differences: listed above, all recorded with owners.

## Final Execution Verdict
Verdict: (pending execution) | Files changed: — | Tests run: — | Blocking: — | QA verdict: — | Non-blocking follow-ups: —
