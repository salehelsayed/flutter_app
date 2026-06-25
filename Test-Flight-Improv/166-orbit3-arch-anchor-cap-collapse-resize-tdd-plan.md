# 166 - Orbit3 Arch: anchor-above-circle, cap+scroll (no overlap), collapse button, smaller +N  (Modification)

Status: IMPLEMENTED host-green (2026-06-25)
Spec: free-text intent (no formal spec) — 5 user refinements to [165](165-orbit3-arch-overflow-and-avatar-size-tdd-plan.md) (Images #9 overlap, #10 oversized +37)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| t0 | Evidence Collector | orbit3_arch_panel.dart, orbit3_screen.dart (arch LayoutBuilder + AnimatedAlign), orbit3_arch_layout.dart, orbit3_one_circle_layout.dart, orbit3_screen_test.dart | Overlap = band bottom `ringTopY-8` ignores the top member's avatar radius `15·scale`; arcs are TOP-anchored + over-compressed. ArchBar is 188×52 (too big). | Plan band-bottom raise + bottom-anchored cap+scroll + collapse pill + bar shrink |
| t0 | Planner | (above) | Screen owns the no-overlap band geometry; panel owns comfortable-size + reverse(bottom-anchored) cap+scroll + collapse pill; ArchBar → compact chip. | Emit RED catalog + matrix |
| t0 | Reviewer (sufficiency) | this doc | no-overlap is a geometric INV locked under BOTH population and avatarScale; cap+scroll via lazy reverse ListView. | — |
| t0 | Arbiter | this doc | No structural blockers; host-only closure; AUTO-glob. | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | | reds now green | |
| | preservation GREEN | | | sentinels green | |
| | visual proof | | preview capture PNGs | no overlap, fits | |
| | QA (independent) | | | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline (5 refinements R1–R5 below)
- Gate definitions: scripts/run_test_gates.sh (Orbit3 NOT listed → host-glob only)
- Host glob gate: scripts/run_host_test_gates.sh `feature-host-all` (auto-globs `test/features/**`)
- Numbering / index: Test-Flight-Improv/00-INDEX.md (next-free = 166)

## Session Classification
implementation-ready (visuals-only prototype; host-only closure; no migration, no device-proof)

## Exact Problem Statement
Five refinements to the 165 Orbit3 arch (Classic + Circle, One Circle view):

- **R1 — no overlap + cap+scroll**: at dense populations the arc rows OVERLAP the inner circle (Image #9). Arcs must never cover the circle. Stop over-compressing to cram all rows; render arcs at a comfortable size; show only the rows that FIT in the band above the outer ring (cap ~3–4) and SCROLL for the rest.
- **R2 — anchor above the circle, bottom-up**: the nearest arc must sit just above the outer ring and rows stack UPWARD (bottom-anchored), not drawn from the top of the screen down. Scrolling up reveals farther rows.
- **R3 — scroll up + circle eases down**: keep the circle's downward glide on expand for room; the band scrolls for more arcs. (True scroll-offset-coupled circle reposition is OUT — Accepted Difference.)
- **R4 — explicit collapse button**: when open, a small distinct button (`orbit3-arch-collapse`) collapses back to just the inner circle.
- **R5 — smaller +N**: the `Orbit3ArchBar` (188×52, font 15) is too big (Image #10); shrink to match the top-bar chips (compact pill, height ≲ 38, font 12, icon 14).

What must improve: arcs never overlap the circle; bottom-anchored cap+scroll; a clear collapse button; a compact +N.
What must stay unchanged (→ preserved-green sentinels): the 165 behaviors — arch presence/absence by overflow, tap-arch→panel→member-chat, avatar-size stepper (circle + sibling panel scale), cycling-closes-panel, no-arch ≤13; InnerSky/Fisheye; layout math.

## Root Cause (verify → refute confirmed)
- **Overlap**: `orbit3_screen.dart` arch `LayoutBuilder` sets the expanded panel to `Positioned(top:0, left:0, right:0, height: ringTopY - 8)` where `ringTopY = c.maxHeight*circleCenterFrac - orbit3RingRadius(kOrbit3CollapsedRings-1)*scale` is the TOP ring member's CENTER y. The top member's avatar extends UP by `orbit3RingAvatar(1)*avatarScale/2 = 15·scale`, so its top edge is `ringTopY - 15·scale`. Band bottom `ringTopY - 8` is BELOW that (8 < 15·scale ∀ scale ≥ 0.6) → the lowest arc row covers the top member. Compounded by `Orbit3ArchPanel`'s adaptive packing compressing ALL rows into the band (`rowHeight=min(base+12, bodyH/rows)`) and TOP-anchoring them.
- **Oversize**: `orbit3_arch_panel.dart::Orbit3ArchBar` is a `SizedBox(188×52)` with `_ArchPainter` dome + glassy `Container` (font 15, icon 18, padding 14×7).

Refuted / do-NOT-re-introduce:
- *"Overlap is an AnimatedAlign timing artifact."* REFUTED — the geometry overlaps even settled (8 < 15·scale); timing only worsens it transiently.
- *"Compress harder to fit all rows."* REFUTED by the user — that produced tiny avatars; the fix is comfortable size + cap + scroll, not more compression.
- *"Bottom-anchor by reversing the Column children with a normal scroll."* REFUTED — short content won't bottom-align in a `SingleChildScrollView`; use `ListView(reverse:true)` (anchors index 0 to the bottom).

## Real Scope
In scope:
- `orbit3_screen.dart` arch `LayoutBuilder`: compute `bandBottomY = ringTopY - orbit3RingAvatar(kOrbit3CollapsedRings-1)*_avatarScale/2 - kArchClearance` (clearance ~16); expanded panel `Positioned(top: 8, height: (bandBottomY - 8))`; collapsed `Orbit3ArchBar` `top = bandBottomY - <compact bar h> - 4`.
- `orbit3_arch_panel.dart::Orbit3ArchPanel`: comfortable fixed avatar (`base ≈ 36*avatarScale`, NO compression), `perRow` from width, `rowHeight = base + 14`; BOTTOM-anchored `ListView(reverse:true)` with row0 nearest the circle (cap = whatever fits; scroll for the rest); a small fixed collapse pill (`orbit3-arch-collapse`) at the band top. Keep root `orbit3-arch-panel` key + backdrop-tap close.
- `orbit3_arch_panel.dart::Orbit3ArchBar`: shrink to a compact chip (height ≲ 38, font 12, icon 14, padding 9×5, radius 12; drop/subdue the dome). Keep `orbit3-arch-overflow` key + `+$count` + people icon.
- Tests: rework the pop50 case; add no-overlap (geom), collapse-button, bar-size; keep the rest.

Out of scope (Accepted Differences): scroll-offset-coupled circle reposition (circle moves down on OPEN only); arc shape/curve math (`computeOrbit3ArcRow` unchanged); any non-Orbit3 file; InnerSky/Fisheye/constellation.

## Files To Inspect Next
Production: orbit3_screen.dart (arch LayoutBuilder ~445-500 + AnimatedAlign ~337), orbit3_arch_panel.dart (Orbit3ArchBar ~23-97, Orbit3ArchPanel ~150-220, _ArcRow, _MoreHeader), orbit3_one_circle_layout.dart (`orbit3RingAvatar`, `orbit3RingRadius`, `kOrbit3CollapsedRings`).
Direct tests: orbit3_screen_test.dart, orbit3_one_circle_arch_test.dart.
Dependency-only: orbital_avatar.dart (entrance timers), user_avatar.dart ("You").

## Existing Tests Covering This Area
- orbit3_screen_test.dart: 165 arch/panel/stepper/cycling cases — pop50 case REWORKED; others KEPT.
- orbit3_one_circle_arch_test.dart, orbit3_arch_layout_test.dart: UNCHANGED (widget knobs + pure geometry) → stay green.
- orbit3_prototype_smoke_test.dart, orbit3_one_circle_layout_test.dart: preservation sentinels.
Missing coverage this plan adds: no-overlap geometry; collapse button; compact bar size; cap+scroll (Scrollable + not-all-built).
Already in curated arrays?: NO — all AUTO-glob (`feature-host-all`).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/features/orbit3/orbit3_screen_test.dart`::`pop 50 expanded arcs never overlap the inner circle` (NO-OVERLAP, headline)
   - Tier: widget (screen)
   - Shape/setup: `goTo('50')`; `openArch`; collect panel `OrbitalAvatar` global rects (descendants of `orbit3-arch-panel`) and circle `OrbitalAvatar` rects (descendants of `Orbit3OneCircle`).
   - RED on HEAD because: band bottom `ringTopY-8` overlaps the top member by `15·scale-8`; the lowest panel avatar's bottom is BELOW the highest circle avatar's top.
   - GREEN asserts: `max(panelAvatar.bottom) <= min(circleAvatar.top) + 0.5` (panel strictly above the circle).
   - Mutation that re-reds: revert band bottom to `ringTopY - 8` → panel dips into the circle, assertion reds.

2. `test/features/orbit3/orbit3_screen_test.dart`::`no overlap holds when avatars are scaled up` (INV under avatarScale)
   - Tier: widget (screen)
   - Shape/setup: `goTo('50')`; tap `orbit3-avatar-size-inc` twice (scale→1.4); `openArch`; same rect comparison.
   - RED on HEAD because: bigger members push their tops further up (`15·1.4=21`), worsening the `ringTopY-8` overlap.
   - GREEN asserts: panel bottom ≤ circle top still holds at scale 1.4.
   - Mutation that re-reds: drop `*_avatarScale` from the band-bottom member-radius term → overlap returns at scale>1.

3. `test/features/orbit3/orbit3_screen_test.dart`::`pop 50 arcs are bottom-anchored & scrollable (cap, not all built)` (R1/R2)
   - Tier: widget (screen)
   - Shape/setup: `goTo('50')`; `openArch`.
   - RED on HEAD because: HEAD uses a non-lazy `SingleChildScrollView` building all 37; and there is no reverse/bottom anchor — the assertion on a lazy reverse ListView + capped build doesn't hold.
   - GREEN asserts: `find.byKey('orbit3-arch-arc-row-0')` present (nearest, at the bottom); a `Scrollable` exists in the panel; the count of panel `OrbitalAvatar` is `< 35` (lazy cap — not the whole tail materialised at once).
   - Mutation that re-reds: switch the panel back to `SingleChildScrollView` (non-lazy) → all 35 build, `<35` reds.

4. `test/features/orbit3/orbit3_screen_test.dart`::`open arch shows a collapse button that closes back to the circle` (R4)
   - Tier: widget (screen)
   - Shape/setup: `goTo('24')`; `openArch`; assert `orbit3-arch-collapse` present; tap it; pump.
   - RED on HEAD because: no `orbit3-arch-collapse` widget exists.
   - GREEN asserts: after tap, `find.byKey('orbit3-arch-panel')` findsNothing AND the circle (13 `OrbitalAvatar`) is back.
   - Mutation that re-reds: remove the collapse pill's `onTap:_toggleArch` wiring → panel stays open, findsNothing reds.

5. `test/features/orbit3/orbit3_one_circle_arch_test.dart`::`Orbit3ArchBar renders compact (height <= 38)` (R5)
   - Tier: widget
   - Shape/setup: pump `Orbit3ArchBar(count: 37, onTap: () {})` in a wrap; read `tester.getSize(find.byType(Orbit3ArchBar))`.
   - RED on HEAD because: the bar is `SizedBox(height:52)` → 52 > 38.
   - GREEN asserts: rendered height ≤ 38 AND `find.text('+37')` present AND a people `Icon` present.
   - Mutation that re-reds: restore `height: 52` → assertion reds.

6. `test/features/orbit3/orbit3_screen_test.dart`::`pop 50 arch shows +37; tapping opens the bottom-anchored panel` (REWORK of the 165 pop50 case)
   - Tier: widget (screen)
   - Shape/setup: `goTo('50')`; assert `+37`; `openArch`; assert `orbit3-arch-panel` + `orbit3-arch-arc-row-0`.
   - RED on HEAD because: this replaces the old `findsNWidgets(35)` assertion which no longer holds under cap+scroll.
   - GREEN asserts: `+37`; panel present; row-0 present.
   - Mutation that re-reds: revert overflow slicing (`items.skip(13)`) → wrong membership reds row-0/badge.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| R1 no overlap | UI geometry INV | widget(screen) | orbit3_screen_test.dart::pop 50 arcs never overlap | band bottom dips into top member | band bottom→`ringTopY-8` | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| R1 no overlap @scale | UI geometry INV | widget(screen) | orbit3_screen_test.dart::no overlap when scaled up | bigger members worsen overlap | drop `*_avatarScale` term | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| R1/R2 cap+scroll bottom-anchor | UI scroll/anchor | widget(screen) | orbit3_screen_test.dart::bottom-anchored & scrollable | non-lazy builds all 37; no reverse | back to SingleChildScrollView | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| R4 collapse button | UI gesture | widget(screen) | orbit3_screen_test.dart::collapse button closes | key absent | remove collapse onTap | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| R5 smaller +N | UI sizing | widget | orbit3_one_circle_arch_test.dart::ArchBar compact ≤38 | bar is 52 tall | restore height 52 | `flutter test test/features/orbit3/orbit3_one_circle_arch_test.dart` | AUTO (glob) |
| pop50 rework | UI render/nav | widget(screen) | orbit3_screen_test.dart::pop50 +37 opens panel | old 35-count no longer holds | revert `items.skip(13)` | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| 165 preserved (arch/chat/stepper/cycle) | preservation | widget(screen) | orbit3_screen_test.dart (kept cases) | n/a (sentinel) | n/a | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| InnerSky/Fisheye preserved | preservation | widget(screen) | orbit3_prototype_smoke_test.dart | n/a (sentinel) | flip showOverflowNode default | `flutter test test/features/orbit3/orbit3_prototype_smoke_test.dart` | AUTO (glob) |
| Geometry/widget knobs preserved | preservation | unit/widget | orbit3_arch_layout_test.dart / orbit3_one_circle_arch_test.dart | n/a (sentinel) | n/a | `flutter test test/features/orbit3/` | AUTO (glob) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability**: `_archOpen`/`_avatarScale` ephemeral, no persistence — N/A.
- **Sibling-surface consistency**: avatar scale already applies to circle + panel (165 INV-4); preserved by keeping `avatarScale` plumbed and the panel's comfortable `base*avatarScale`.
- **Destructive-action side-effects**: none added — N/A.
- **Invariant re-verification under new transitions**: the NO-OVERLAP invariant is re-verified under BOTH a new avatarScale (TC-2) and population (TC-1 at 50); collapse (TC-4) and cycling (kept 165 case) re-verify the panel closes and the circle returns.

## Invariants (locked by tests)
- INV-1: expanded arcs never overlap the inner circle (panel bottom ≤ circle top) at any population AND any avatarScale → TC-1, TC-2.
- INV-2: arcs are bottom-anchored above the circle and the band scrolls (cap, not all built) → TC-3.
- INV-3: an explicit collapse button closes to just the circle → TC-4.
- INV-4: the +N arch is compact (≤38 tall) → TC-5.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot. Add RED tests (catalog 1–6); run focused cmds; confirm RED for the documented reasons.
2. `orbit3_screen.dart` arch `LayoutBuilder`: add `final memberR = orbit3RingAvatar(kOrbit3CollapsedRings - 1) * _avatarScale / 2;` and `final bandBottomY = ringTopY - memberR - 16;`. Expanded: `Positioned(top: 8, left:0, right:0, height: (bandBottomY - 8) < 80 ? 80 : bandBottomY - 8, child: Orbit3ArchPanel(...))`. Collapsed bar: `top: (bandBottomY - 38)` (compact bar height + gap). Keep `circleCenterFrac` glide.
3. `orbit3_arch_panel.dart::Orbit3ArchPanel`: replace adaptive compression with COMFORTABLE fixed sizing (`base = (36*avatarScale).clamp(20,60)`, `perRow = (W/(base+6)).floor().clamp(6,11)`, `rowHeight = base + 14`). Layout = `computeOrbit3ArchArcs(count, W, base, perRow)`. Render `Column[_CollapsePill(key 'orbit3-arch-collapse', onTap:onClose), Expanded(ListView(reverse:true, children:[for r row r → _ArcRow(key arc-row-$r, ...)]))]`. row0 = nearest circle (reverse anchors index 0 to bottom). Keep root `orbit3-arch-panel` GestureDetector(onTap:onClose).
4. `orbit3_arch_panel.dart::Orbit3ArchBar`: replace the 188×52 Stack/dome with a compact glassy pill — `Container(padding: EdgeInsets.symmetric(horizontal:9, vertical:5), borderRadius:12, border accent)` + `Row[Icon(people, size14), SizedBox(4), Text('+$count', fontSize12 w700)]`. Keep key `orbit3-arch-overflow`, Semantics. Drop `_ArchPainter` (or keep a subtle 1px arc, ≤38 tall). Remove now-dead `_MoreHeader` if replaced by `_CollapsePill`.
   Stop-if: making no-overlap green forces editing `Orbit3OneCircle`/`computeOrbit3RingLayout`/InnerSky → replan (the band geometry must live in the screen).
5. Rerun direct → preservation (`flutter test test/features/orbit3/`) → `feature-host-all` → `flutter analyze`.
6. Visual proof: re-run `orbit3_arch_preview_capture.dart`; eyeball `arch_pop50_expanded.png` (no overlap, bottom-anchored, compact +N) — extend the harness to also capture a scrolled frame if useful.
7. After lib edits: `graphify update .` + `./graphify-arch/refresh_arch_graph.sh`.

## Risks And Edge Cases
- **Lazy reverse ListView + entrance timers**: panel `OrbitalAvatar`s schedule `globalIndex*40ms` timers; only built (visible) ones fire — drain with stepped pumps in any capture; tests pump enough but assert only on built rows.
- **`getSize`/rect on off-screen avatars**: TC-1/2 compare only BUILT panel avatars (the nearest, visible ones) vs circle avatars — sufficient since the LOWEST arc (row0, visible) is the overlap risk.
- **Collapse pill vs backdrop tap**: both call `onClose`; the pill is the headline (TC-4), backdrop kept as a convenience (not asserted).
- **avatarScale extremes**: band-bottom term uses `_avatarScale`, so the clearance grows with bigger members (TC-2); comfortable base also scales, fewer per row — still bottom-anchored, scroll covers the rest.
- **Member name label**: sits BELOW the top member (toward centre), so it does not push the no-overlap threshold up; 16px clearance covers the glow.

## Device/Relay Proof Profile
host-only for closure (visuals-only; no OS boundary/relay/crypto/DB). No device-proof. Visual confirmation: `flutter test test/features/orbit3/orbit3_arch_preview_capture.dart` → `build/orbit3_previews/arch_*.png`.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before edits) — must FAIL for the documented reason
flutter test test/features/orbit3/orbit3_screen_test.dart --plain-name 'overlap'        # no-overlap reds
flutter test test/features/orbit3/orbit3_one_circle_arch_test.dart --plain-name 'compact' # 52>38 reds
flutter test test/features/orbit3/orbit3_screen_test.dart --plain-name 'collapse'        # key absent

# Direct GREEN (after fix)
flutter test test/features/orbit3/orbit3_screen_test.dart
flutter test test/features/orbit3/orbit3_one_circle_arch_test.dart

# Preservation sentinels (must stay green)
flutter test test/features/orbit3/orbit3_prototype_smoke_test.dart
flutter test test/features/orbit3/orbit3_one_circle_layout_test.dart
flutter test test/features/orbit3/                       # whole Orbit3 slice green

# Host glob gate
./scripts/run_host_test_gates.sh feature-host-all        # 0 failures

# Visual proof (non-gated harness)
flutter test test/features/orbit3/orbit3_arch_preview_capture.dart   # writes build/orbit3_previews/arch_*.png

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```
(No migration gate — no schema change. No `/sims` — no simulator/device rows.)

## Known-Failure Interpretation
- Expected RED: catalog 1–6 before the fix (overlap geom, 52>38, missing collapse key, reworked pop50).
- Pre-existing dirty: graphify-out refresh churn (step 7) — not product change.
- Environment blocker: none (host-only).
- Scope drift (BLOCKING): any red outside `test/features/orbit3/**` or edits to non-Orbit3 / `computeOrbit3RingLayout` / InnerSky / Fisheye.

## Done Criteria
- [ ] RED added first, failed for the expected reason.
- [ ] Mutation-verified (each fix has a re-red revert per the matrix).
- [ ] Direct GREEN + preservation sentinels + `feature-host-all` pass.
- [ ] No migration; no OS-boundary/device path (host-only).
- [ ] Visual proof PNG shows no overlap + bottom-anchored arcs + compact +N.
- [ ] flutter analyze 0 new; git diff --check clean; no Scope Guard violations.
- [ ] Both graphs refreshed.

## Scope Guard (hard "Do not")
- Do NOT edit non-Orbit3 files, `computeOrbit3RingLayout`, InnerSky, Fisheye, constellation, or `Orbit2MockChatScreen`.
- Do NOT compress avatars to cram all rows (comfortable size + cap + scroll only).
- Do NOT let the panel band extend below `ringTopY - memberRadius - clearance`.

## Accepted Differences / Intentionally Out Of Scope
- Scroll-offset-coupled circle reposition — circle moves down on OPEN only; arcs scroll independently (R3 pragmatic).
- Arc curve math (`computeOrbit3ArcRow`) unchanged.
- Size stepper still Classic-One-Circle-only (from 165).

## Dependency Impact
- None. Self-contained Orbit3 prototype refinement.

## Reviewer Findings
Sufficiency: the no-overlap invariant is locked geometrically at the lowest tier that fails for the real reason, and RE-verified under avatarScale (the exact axis that worsens it) — not just one population. cap+scroll uses a falsifiable discriminator (`<35` built via lazy reverse ListView vs the old non-lazy build-all). collapse + bar-size are independently mutation-verified. No empty matrix cells; host-only (correct). Thin spot: rect comparisons use only BUILT panel avatars — acceptable because the lowest (row0) arc is always built and is the sole overlap risk.

## Arbiter Decision
Structural blockers: none. Deferred: exact comfortable `base`/clearance px are visual params (locked only by the ≤38 bar bound and the no-overlap inequality, not exact px). Verdict: implementation-ready.

## Final Execution Verdict
Verdict: ACCEPTED (host-green) | Files changed: ~`orbit3_screen.dart` (arch band geometry now MIRRORS the real circle layout — `scale=min(innerW,innerH,1)/320`, `youY` from Padding(12)+AnimatedAlign(0.30)+FittedBox, `memberTop = youY − scale·(ring1R + ring1Av·avatarScale/2)`, `bandBottomY = memberTop − 16`; panel `top:8,height:bandBottomY−8`; collapsed bar `top:bandBottomY−38`), ~`orbit3_arch_panel.dart` (comfortable fixed sizing — NO compression; bottom-anchored lazy `ListView.builder(reverse:true)`; `_MoreHeader`→`_CollapsePill` key `orbit3-arch-collapse`; `Orbit3ArchBar` 188×52→compact chip; dropped `_ArchPainter` + `dart:math`/`dart:ui`), ~2 test files (5 new/reworked cases + helpers). | Tests run: `flutter test test/features/orbit3/` **49/49 pass**. RED confirmed pre-fix (5 reds: overlap, overlap@scale, no cap/scroll, missing collapse key, 52>38). KEY GOTCHA: first fix still overlapped ~18px because the band guessed `You = frac·maxHeight` — the circle is in `Padding(12)` + `AnimatedAlign` (places by `parentH−childH`), so `ringTopY` was ~50px off; corrected by mirroring the exact layout math. Mutation-verified: `bandBottomY = memberTop + 30` re-reds both no-overlap tests. | Blocking: none. | QA verdict: `flutter analyze` orbit3 0 issues. Visual proof `build/orbit3_previews/arch_*.png` on a 390×720 surface: compact +N, bottom-anchored arcs cap at ~3 + scroll, circle visible with NO overlap, collapse pill. Both graphs refreshed. | Non-blocking follow-ups (owner): scroll-coupled circle reposition deferred (R3 pragmatic — circle moves on OPEN only).
