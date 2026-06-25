# 167 - Orbit3 Arch: unified full-screen scroll  (Modification — workflow-designed)

Status: IMPLEMENTED host-green (2026-06-25)
Design: workflow `orbit3-unified-scroll-design` (run wf_73085ae0-7d0) — 3 independent
`code-architect` proposals (minimal-diff / best-UX / most-testable) + adversarial
synthesis. Implemented in the main loop (read-only agents never touched the tree).
Builds on [165](165-orbit3-arch-overflow-and-avatar-size-tdd-plan.md) / [166](166-orbit3-arch-anchor-cap-collapse-resize-tdd-plan.md).

## User intent (verbatim)
"the inner circle and the archs are not on the same screen. I want to be able to
scroll the entire screen." Today (166) the circle was PINNED (glided down) while the
arches scrolled INDEPENDENTLY in a capped band above it — you could not move through
all arches + the circle as one surface.

## Change
The OPEN arch state is now ONE continuously-scrollable surface (the winning design:
single `SingleChildScrollView` + `Column`; one `Scrollable` by construction):
- `_buildUnifiedArchScroll` (new): `Stack[ Positioned.fill(LayoutBuilder > SingleChildScrollView(key 'orbit3-arch-panel', controller `_archScroll`, `ClampingScrollPhysics`, padding top:48) > Column[ arch rows (emitted FARTHEST-first so row 0 is the lowest, just above the circle), SizedBox(16) gap, Center>Padding>Orbit3OneCircle (plain — NO FittedBox/AnimatedAlign), SizedBox(96) trailing ]), pinned _SizeStepper (bottom-left), pinned _Orbit3SearchPill (bottom-right), pinned Orbit3ArchCollapsePill (top-centre) ]`.
- Routing: `if (oneCircle && _archOpen && overflow>0) _buildUnifiedArchScroll else <today's Stack>` (collapsed + constellation paths unchanged; AnimatedAlign glide simplified to centre; the old `if(_archOpen){Orbit3ArchPanel...}` band sub-branch deleted).
- `_toggleArch`: on open, post-frame `jumpTo(maxScrollExtent)` → opens anchored on the circle; `jumpTo` (not animateTo) is reduce-motion safe.
- Refactor: `_ArcRow`→public `Orbit3ArcRow`, `_CollapsePill`→public `Orbit3ArchCollapsePill` (screen composes them directly); DELETED `Orbit3ArchPanel` + `_kArchPanelAvatar`; NEW public const `kOrbit3ArchRowAvatar=36` in orbit3_arch_layout.dart.

## Tests (test/features/orbit3/, AUTO-glob feature-host-all)
- NEW (load-bearing, RED on HEAD): `orbit3_screen_test.dart::the inner circle and the arches live in ONE scrollable surface` — (a) exactly one Scrollable under archPanel(); (b) a circle avatar and an arch avatar resolve to the IDENTICAL `ScrollableState` (`identical()`); (c) one drag of `orbit3-arch-arc-row-0` translates BOTH the circle and the arches by the same delta; plus opened-anchored-at-bottom (`pos.pixels≈maxScrollExtent`). RED on HEAD: circle was in a sibling AnimatedAlign outside the band's ListView → `circleSc` null / `identical` false / drag leaves the pinned circle stationary. Mutation revert = re-pin the circle outside the scroll → reds.
- Retargeted: the two no-overlap geom tests now use `archAvatars()` (descendants of `Orbit3ArcRow`, NOT the circle which now lives inside the same scroll) + a gap assertion `minTop(circle)-maxBottom(arch) >= 8`; member-chat taps `archAvatars().first`.
- Kept: ring sizes, pop5/13 (no arch), pop24 +11, pop50 +37 opens, collapse button, cycling-closes, avatar-size stepper + sibling-scale, short-screen scroll, names/search/chat; bar-compact; pure geometry.
- Result: `flutter test test/features/orbit3/` **51/51**; `flutter analyze` 0 issues. Visual proof `build/orbit3_previews/arch_pop50_expanded.png` (390×720): collapse pill pinned, arch rows above, circle visible at the bottom, all one scroll.

## Adversarial review (workflow wf_c4d6e403-990, 4 read-only `code-reviewer` agents) → ship-with-nits, NO must-fix. All 3 confirmed nits FIXED:
- N1 (UX, real): `jumpTo(maxScrollExtent)` no-ops when content fits (default pop24 on a tall phone) → circle shifted up + dead space. FIX: `ConstrainedBox(minHeight: viewport−56)` + `Column(mainAxisSize.min, mainAxisAlignment.end)` → circle bottom-anchored in BOTH fit and overflow cases.
- N2 (test, near-vacuous): the gap assertion measured the inset ring avatar (always ~44px) so deleting the spacer was undetectable. FIX: measure `minTop(find.byType(Orbit3OneCircle))` (the box) − `maxBottom(archAvatars())` ∈ [12,30] (≈23 = 7 row remainder + 16 spacer).
- N3 (coverage gap): nothing locked the pinned controls. FIX: NEW test drags `arch-arc-row-0` and asserts `orbit3-arch-collapse`/`orbit3-avatar-size-inc` centres move <1px while the circle moves >5px.
- Dismissed (verified non-defects): no ScrollController leak (disposed + guarded), `_archOpen` reset on all context changes, collapsed/constellation/InnerSky/Fisheye unchanged.

## Watch-outs honored
Eager build of ~50 avatars on open (no lazy ListView) — entrance timers drained by `openArch`'s 2400ms pump; no FittedBox on the open-state circle (320 fits the padded widths); top:48 padding keeps the first row clear of the pinned collapse pill; dropped the old tap-to-dismiss (a scroll can't double as tap-to-dismiss) — dismissal is solely the collapse pill; `r = rows.length-1-i` keeps arc-row keys correct by actual r.

## Scope guard / accepted differences
Orbit3 only; no InnerSky/Fisheye/constellation/Orbit3OneCircle-contract/non-Orbit3 edits. Scroll-offset-coupled circle reposition still OUT (circle is part of the scroll now, so it moves with it — the original concern is moot).
