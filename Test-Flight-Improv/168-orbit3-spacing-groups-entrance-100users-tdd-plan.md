# 168 - Orbit3: spacing stepper, group-avatar parity, rise-up entrance, no circle re-entrance, 100 users  (Feature batch / Modification)

Status: IMPLEMENTED host-green (2026-06-25) — WF-1 (this plan) + WF-2 (executed)
Spec: free-text intent (no formal spec) — 5 user changes; follow-up to [167](167-orbit3-arch-unified-scroll-record.md) / 165 / 166.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| t0 | Evidence Collector | orbit3_screen.dart, orbit3_one_circle.dart, orbit3_one_circle_layout.dart, orbit3_arch_panel.dart, **orbital_avatar.dart (read in full)**, orbit3_mock_data.dart, orbit3_screen_test.dart | Entrance = scale+fade staggered globalIndex*40ms, NO translate (→ left-right); circle re-mounts on expand (new instance) → re-entrance; groups use flat glyphs (≠ OrbitalAvatar); mock cap 52. | Additive params on OrbitalAvatar + Orbit3OneCircle; Orbit3 arch composes them. |
| t0 | Planner | (above) | All 5 land via ADDITIVE params (defaults preserve InnerSky/Fisheye/Orbit/Orbit2/feed). | RED catalog + matrix |
| t0 | Reviewer (sufficiency) | this doc | Each change has a falsifiable RED; reduce-motion + InnerSky preservation pinned. | — |
| t0 | Arbiter | this doc | Host-only; AUTO-glob; no migration/device. | hand off to execution (WF-2) |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | | reds now green | |
| | preservation GREEN | | | sentinels green | |
| | visual proof | | preview capture | | |
| | QA (independent) | | | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline (C1–C5 below)
- Gate definitions: scripts/run_test_gates.sh (Orbit3 NOT listed → host-glob only)
- Host glob gate: scripts/run_host_test_gates.sh `feature-host-all`
- Numbering / index: Test-Flight-Improv/00-INDEX.md (next-free = 168)

## Session Classification
implementation-ready (visuals-only prototype; host-only closure; no migration, no device-proof)

## Exact Problem Statement
Five Orbit3 changes (Classic + Circle, One Circle / unified arch scroll):
- **C1 spacing stepper**: a SECOND ＋/－ control (independent of avatar-size) to tune the gap between orbit rings AND between arches, so size × spacing can be tuned separately.
- **C2 group-avatar parity**: in the expanded arches, group members render as flat teal `_PanelGroupGlyph` while friends render as colourful `OrbitalAvatar` — inconsistent. Groups must look the SAME as the 1:1 avatars and stay adjacent.
- **C3 rise-up entrance**: the expand entrance reads LEFT→RIGHT (scale+fade staggered by globalIndex, no translation). Want BOTTOM→UP + fast — avatars rising from below toward the user ("commits from a far distance").
- **C4 no circle re-entrance**: expanding builds a NEW `Orbit3OneCircle` → its avatars replay the entrance. The inner circle must stay steady on open (only arches animate).
- **C5 100 users**: add a 100-user population option (mock data caps at 52 today).

What must improve: a spacing knob; consistent group avatars; a bottom-up fast entrance; a steady circle on expand; a 100-user option.
What must stay unchanged (→ preserved-green sentinels): InnerSky/Fisheye (`Orbit3OneCircle` + `OrbitalAvatar` defaults), Orbit/Orbit2/feed (shared `OrbitalAvatar` default entrance), constellation, layout math, reduce-motion behavior, and all 165/166/167 behaviors.

## Root Cause / Mechanism (verify → refute confirmed — direct authoritative grounding)
- **Entrance (C3/C4)**: `lib/features/orbit/presentation/widgets/orbital_avatar.dart:38-55,103-112` — `initState` schedules `Future.delayed(globalIndex*40ms, ()=>_controller.forward())` (or `value=1.0` when `!motionEnabled`); `build` wraps the avatar in `Transform.scale(_scaleAnimation.value)` + `Opacity(...)`. So entrance = in-place scale+fade, 500ms, staggered by globalIndex → reads LEFT→RIGHT, NO translation. REFUTE: searched — this is the ONLY avatar entrance; arch + circle both use `OrbitalAvatar`. So C3 (add a rise/translate + reorder) and C4 (suppress on the open circle) both seam at `OrbitalAvatar` (additively) + the Orbit3 consumers.
- **Circle re-mount (C4)**: the open path builds a fresh `Orbit3OneCircle` inside `_buildUnifiedArchScroll` (a different subtree than the collapsed `else`-Stack), with no shared identity → new `OrbitalAvatar` State → entrance replays. REFUTE: Flutter cannot reuse the collapsed elements across the conditional branch without a GlobalKey; confirmed re-mount.
- **Group divergence (C2)**: friends → `OrbitalAvatar` (bordered circle, photo, entrance); groups → `_PanelGroupGlyph` (orbit3_arch_panel.dart, flat teal disc, NO border-parity, NO entrance) in the arch, and `_Orbit3GroupGlyph` (orbit3_one_circle.dart) in the circle. Confirmed visual divergence.
- **Ring radii (C1)**: `Orbit3OneCircle` consumes `computeOrbit3RingLayout(...).radii` (62/108…). Scaling at the consumer (additive `ringSpacingScale`) avoids editing the shared `computeOrbit3RingLayout`/InnerSky.
- **Mock cap (C5)**: `orbit3_mock_data.dart` `n = count.clamp(0, _names.length + 2)` → 52.
Refuted / do-NOT: editing `computeOrbit3RingLayout` (InnerSky breakage) — scale at the consumer; changing `OrbitalAvatar`'s DEFAULT entrance (breaks Orbit/Orbit2/feed) — all new behavior is opt-in via defaulted params.

## Real Scope
In scope (ADDITIVE everywhere shared):
- `OrbitalAvatar`: + `Widget? child` (default null → UserAvatar) [C2]; + `bool riseUp` (default false: adds a vertical slide + faster ~200ms duration) [C3]; + `int? entranceDelayMs` (default null → globalIndex*40) [C3 ordering]; + `bool animateEntrance` (default true; false → `value=1.0`, no entrance) [C4]. Defaults = today's behavior exactly.
- `Orbit3OneCircle`: + `double ringSpacingScale` (default 1.0; scales `radii` AND `boxSize` at the consumer) [C1]; + `bool animateEntrance` (default true; threaded to its OrbitalAvatars) [C4].
- NEW pure helper `orbit3ArchEntranceDelayMs({required int rowFromBottom, required int col, ...})` in orbit3_arch_layout.dart → deterministic BOTTOM-UP delay schedule [C3].
- `Orbit3ArcRow` (orbit3_arch_panel.dart): friends AND groups now render via `OrbitalAvatar` (group → `OrbitalAvatar(child: groupGlyphContent, key 'orbit3-arch-group-<id>', riseUp:true, entranceDelayMs:…)`); delete `_PanelGroupGlyph` use; pass `riseUp:true` + bottom-up `entranceDelayMs` to all arch avatars [C2/C3].
- `orbit3_screen.dart`: + `_spacingScale` (0.7–1.5, step 0.1) + `_incSpacing`/`_decSpacing` + a SECOND stepper (generalize `_SizeStepper` to take inc/dec keys+icon; instantiate size + spacing, stacked bottom-left) [C1]; thread `ringSpacingScale:_spacingScale` to BOTH circles; scale arch `rowHeight` + the 16px gap by `_spacingScale` [C1]; pass `animateEntrance:false` to the OPEN-path `Orbit3OneCircle` [C4]; `_populations` → `[5,13,24,50,100]` [C5].
- `orbit3_mock_data.dart`: lift the 52 cap → deterministic names past the pool (`'User N'` suffix) up to 100; keep ≥2 groups at the tail [C5].

Out of scope (Accepted Differences): the COLLAPSED circle's `_Orbit3GroupGlyph` stays (tiny on-ring; C2 targets the expanded arches the user flagged); per-avatar (not per-row) entrance physics tuning beyond the slide+scale+fade; persisting `_spacingScale`.

## Files To Inspect Next
Production: orbital_avatar.dart (entrance), orbit3_one_circle.dart (radii/box/group glyph + avatar wiring), orbit3_arch_panel.dart (Orbit3ArcRow friend/group render), orbit3_screen.dart (_SizeStepper, _buildUnifiedArchScroll, populations, routing), orbit3_arch_layout.dart (new delay helper), orbit3_mock_data.dart (cap).
Tests: orbit3_screen_test.dart, orbit3_one_circle_arch_test.dart, orbit3_arch_layout_test.dart, orbit3_prototype_smoke_test.dart (InnerSky/Fisheye sentinel), orbit3_one_circle_layout_test.dart.

## Existing Tests Covering This Area
- orbit3_screen_test.dart: population cycler, arch/scroll/overlap/collapse/stepper/single-Scrollable/pinned-controls — extended, none rewritten destructively.
- orbit3_prototype_smoke_test.dart: InnerSky/Fisheye — PRESERVATION sentinel for the additive OrbitalAvatar/Orbit3OneCircle params.
- orbit3_one_circle_layout_test.dart, orbit3_arch_layout_test.dart: pure — unchanged + new delay-helper test added.
Missing coverage this plan adds: spacing-scales-ring+arch; group-avatar parity + adjacency; rise-up translation + bottom-up order; circle-no-re-entrance; pop100 seats+scrolls; OrbitalAvatar additive-default preservation.
Already in curated arrays?: NO — all AUTO-glob (`feature-host-all`).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/features/orbit3/orbit3_screen_test.dart`::`spacing stepper widens the orbit rings AND the arch row pitch` (C1)
   - Tier: widget (screen). Setup: goTo('50'); openArch; measure ring-1 OrbitalAvatar-centre→"You"(UserAvatar centre) distance D0 and arc-row pitch P0 (row1.center.dy − row0.center.dy); tap 'orbit3-spacing-inc' ×2; remeasure D1,P1.
   - RED on HEAD: keys 'orbit3-spacing-inc/-dec' don't exist (tap fails) + `ringSpacingScale` absent.
   - GREEN: D1 > D0 and P1 > P0; then 'orbit3-spacing-dec' ×3 → both shrink below D0/P0.
   - Mutation: revert the `ringSpacingScale` radii multiply → D unchanged on inc → reds; revert `rowHeight*_spacingScale` → P unchanged → reds.

2. `test/features/orbit3/orbit3_screen_test.dart`::`spacing stepper does NOT change avatar size; size stepper does NOT change ring spacing` (C1 orthogonality)
   - Tier: widget (screen). Setup: goTo('50'); openArch; record a circle OrbitalAvatar.size and ring-1 distance; tap 'orbit3-spacing-inc' → size unchanged, distance grew; tap 'orbit3-avatar-size-inc' → size grew, distance (ring radius) unchanged.
   - RED on HEAD: spacing keys absent.
   - GREEN: orthogonal as stated. Mutation: make `_spacingScale` also feed avatarScale → size changes on spacing-inc → reds.

3. `test/features/orbit3/orbit3_screen_test.dart`::`expanded group members render as OrbitalAvatars (parity) and stay adjacent` (C2)
   - Tier: widget (screen). Setup: goTo('50'); openArch.
   - RED on HEAD: groups are `_PanelGroupGlyph`, so `archAvatars()` (OrbitalAvatar in Orbit3ArcRow) == 35, not 37; group keys 'orbit3-arch-group-*' absent.
   - GREEN: `archAvatars()` == 37 (35 friends + 2 groups, all OrbitalAvatar); both `orbit3-arch-group-<id>` present, same row (equal .dy) and adjacent (|Δx| ≈ one slot pitch).
   - Mutation: revert groups to `_PanelGroupGlyph` → count 35 → reds.

4. `test/features/orbit3/orbit3_one_circle_arch_test.dart`::`OrbitalAvatar riseUp slides up during entrance; default does not` (C3 translation)
   - Tier: widget. Setup: pump `OrbitalAvatar(riseUp:true, animateEntrance:true, motionEnabled:true, entranceDelayMs:0, …)`; pump 60ms (mid); record child global dy = Ymid; pump 400ms (settle) → Yend.
   - RED on HEAD: `riseUp`/`animateEntrance`/`entranceDelayMs` params absent (compile-fail).
   - GREEN: Ymid > Yend (started below, slid UP); a control `OrbitalAvatar(riseUp:false)` shows Ymid ≈ Yend (no vertical slide — today's in-place scale).
   - Mutation: drop the `Transform.translate` in the riseUp branch → Ymid ≈ Yend → reds.

5. `test/features/orbit3/orbit3_arch_layout_test.dart`::`orbit3ArchEntranceDelayMs is bottom-up monotonic and fast` (C3 order)
   - Tier: unit. Setup: call the helper for rows 0..3.
   - RED on HEAD: helper absent (compile-fail).
   - GREEN: delay(rowFromBottom:0) < delay(1) < delay(2) (lower/nearer rows animate FIRST → bottom-up); within a row delays increase by col; max delay across a dense page ≤ a fast bound (e.g. ≤ ~600ms).
   - Mutation: invert to `(maxRow-rowFromBottom)` → monotonicity flips → reds.

6. `test/features/orbit3/orbit3_screen_test.dart`::`opening the arch does NOT re-animate the inner-circle avatars` (C4)
   - Tier: widget (screen). Setup: goTo('50'); openArch; pump only ~60ms (NOT a full drain); read the painted scale of `circleAvatars().first` via its `Transform` (getMaxScaleOnAxis).
   - RED on HEAD: open circle re-enters → at 60ms a low-index avatar is mid-scale (~0.2–0.4) < 0.95.
   - GREEN: open-path `Orbit3OneCircle(animateEntrance:false)` → circle avatars are at scale ≈ 1.0 immediately (≥ 0.95). Then drain.
   - Mutation: revert `animateEntrance:false` on the open circle → mid-scale at 60ms → reds.

7. `test/features/orbit3/orbit3_one_circle_arch_test.dart`::`Orbit3OneCircle animateEntrance:false shows avatars fully at first frame` (C4 contract, lowest tier)
   - Tier: widget. Setup: pump `Orbit3OneCircle(items:13, animateEntrance:false, motionEnabled:true)`; pump 1 frame; read a member OrbitalAvatar Transform scale.
   - RED on HEAD: `animateEntrance` param absent (compile-fail).
   - GREEN: scale ≈ 1.0 at frame 1; with `animateEntrance:true` (default) + a short pump, scale < 1 (entrance running).
   - Mutation: make `animateEntrance` ignored → scale < 1 at frame 1 → reds.

8. `test/features/orbit3/orbit3_screen_test.dart`::`100-user population seats 100 and the arch opens + scrolls` (C5)
   - Tier: widget (screen). Setup: goTo('100').
   - RED on HEAD: '100' not in `_populations` (cycler never shows it → goTo loops without reaching) + mock caps at 52.
   - GREEN: circle shows 13 OrbitalAvatars + '+87' arch; openArch → archAvatars() == 87 (across many rows), one Scrollable, `pos.maxScrollExtent > 0`, `tester.takeException()` isNull. Drain (bump to ~3000ms for ~100 avatars).
   - Mutation: revert the mock-cap lift → build(count:100) returns 52 → seat/overflow counts wrong → reds.

9. `test/features/orbit3/orbit3_mock_data_test.dart` (NEW)::`build(count:100) returns 100 deterministic items incl. groups` (C5 unit)
   - Tier: unit. RED on HEAD: file absent + cap 52.
   - GREEN: `Orbit3MockData.build(count:100).length == 100`; ≥2 groups; first 13 friends-only; deterministic (two calls equal); names unique enough that search still works.
   - Mutation: revert cap lift → length 52 → reds.

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| C1 ring+arch spacing | UI sizing | widget(screen) | orbit3_screen_test::spacing widens rings + pitch | spacing keys/param absent | revert ringSpacingScale / rowHeight*spacing | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| C1 orthogonality | UI sizing | widget(screen) | orbit3_screen_test::spacing≠size, size≠spacing | spacing keys absent | feed _spacingScale→avatarScale | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| C2 group parity+adjacency | UI render | widget(screen) | orbit3_screen_test::group members are OrbitalAvatars, adjacent | groups are _PanelGroupGlyph (35≠37) | revert groups→_PanelGroupGlyph | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| C3 rise translation | UI anim | widget | orbit3_one_circle_arch_test::riseUp slides up | params absent (compile-fail) | drop Transform.translate | `flutter test test/features/orbit3/orbit3_one_circle_arch_test.dart` | AUTO (glob) |
| C3 bottom-up order | pure logic | unit | orbit3_arch_layout_test::entranceDelayMs bottom-up | helper absent | invert row term | `flutter test test/features/orbit3/orbit3_arch_layout_test.dart` | AUTO (glob) |
| C4 no circle re-entrance | UI anim | widget(screen) | orbit3_screen_test::open does not re-animate circle | re-entrance mid-scale<0.95 | revert animateEntrance:false on open circle | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| C4 animateEntrance contract | UI anim | widget | orbit3_one_circle_arch_test::animateEntrance:false full at frame 1 | param absent | ignore animateEntrance | `flutter test test/features/orbit3/orbit3_one_circle_arch_test.dart` | AUTO (glob) |
| C5 pop100 seats+scrolls | UI render | widget(screen) | orbit3_screen_test::pop100 seats 100 + scrolls | 100 absent + cap 52 | revert cap lift | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| C5 mock 100 | pure logic | unit | orbit3_mock_data_test::build(100)==100 incl groups | file absent + cap | revert cap | `flutter test test/features/orbit3/orbit3_mock_data_test.dart` | AUTO (glob) |
| Preservation: InnerSky/Fisheye | preservation | widget(screen) | orbit3_prototype_smoke_test (UNCHANGED) | n/a (sentinel) | flip an OrbitalAvatar default | `flutter test test/features/orbit3/orbit3_prototype_smoke_test.dart` | AUTO (glob) |
| Preservation: layout math | preservation | unit | orbit3_one_circle_layout_test (UNCHANGED) | n/a (sentinel) | n/a | `flutter test test/features/orbit3/` | AUTO (glob) |
| Preservation: 165/166/167 | preservation | widget(screen) | orbit3_screen_test kept cases | n/a (sentinel) | n/a | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability**: `_spacingScale`/`_archOpen` ephemeral, no persistence — N/A.
- **Sibling-surface consistency**: the additive OrbitalAvatar params default to today's behavior — assert OTHER consumers unchanged via the InnerSky/Fisheye sentinel + a default-preservation widget test (`OrbitalAvatar()` with no new params behaves identically: scale+fade 500ms, no translate). C1 spacing applies to BOTH ring + arch (the two spacing surfaces) — locked by TC-1.
- **Destructive-action side-effects**: none (no delete/cleanup) — N/A.
- **Invariant re-verification under new transitions**: the collapsed→open transition now (a) does NOT re-enter the circle (TC-6) AND (b) the arches rise bottom-up (TC-4/5); cycling population/lab still closes the arch (kept 167 case re-verified under pop100). reduce-motion: with `motionEnabled:false`, riseUp + animateEntrance are inert (avatars appear instantly) — add a widget assertion (OrbitalAvatar(riseUp:true, motionEnabled:false) → settled at frame 1, no translate).

## Invariants (locked by tests)
- INV-1: spacing stepper scales ring radii AND arch pitch, orthogonal to avatar-size → TC-1, TC-2.
- INV-2: arch group members render with avatar parity + stay adjacent → TC-3.
- INV-3: opt-in `riseUp` adds a vertical slide; default unchanged; order is bottom-up → TC-4, TC-5.
- INV-4: the open inner circle does NOT re-animate (`animateEntrance:false`) → TC-6, TC-7.
- INV-5: pop100 seats 100 (13 + 87) and the arch scrolls without error → TC-8, TC-9.
- INV-6 (preservation): OrbitalAvatar/Orbit3OneCircle defaults keep InnerSky/Fisheye/other screens byte-identical → sentinel + default-preservation test.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot. Add RED tests (1–9); run focused cmds; confirm RED for the documented reasons (compile-fail for new params/helpers; assertion-fail for behavior).
2. `OrbitalAvatar`: add `child`/`riseUp`/`entranceDelayMs`/`animateEntrance` (defaults null/false/null/true). `effectiveAnimate = motionEnabled && animateEntrance`; if not → `value=1.0`. Duration `riseUp?200:500`. Delay `entranceDelayMs ?? globalIndex*40`. Render `child ?? UserAvatar(...)` inside the bordered circle. If `riseUp`, wrap the scale+fade in `Transform.translate(Offset(0, riseDist*(1 - value)))` (riseDist ≈ size*0.9). Defaults reproduce today's tree exactly.
3. `orbit3_arch_layout.dart`: add `orbit3ArchEntranceDelayMs({rowFromBottom, col, rowMs=55, colMs=8})` → `rowFromBottom*rowMs + col*colMs` (bottom-up, fast).
4. `Orbit3OneCircle`: add `ringSpacingScale`(1.0) → `radii = layout.radii.map(*scale)`, `box = layout.boxSize*scale`, painter + member positions use scaled radii; add `animateEntrance`(true) → thread to each `OrbitalAvatar`. Defaults preserve InnerSky/Fisheye.
5. `Orbit3ArcRow`: render friends AND groups via `OrbitalAvatar` (group → `OrbitalAvatar(peerId: it.id, child: <teal group glyph content>, key ValueKey('orbit3-arch-group-${it.id}'), borderColor: teal, riseUp:true, entranceDelayMs: orbit3ArchEntranceDelayMs(rowFromBottom: …, col: i), …)`; friends → `OrbitalAvatar(riseUp:true, entranceDelayMs: …)`); remove `_PanelGroupGlyph` use (keep or delete the class). The row needs its `rowFromBottom` (thread from the screen's descending-emit index).
6. `orbit3_screen.dart`: generalize `_SizeStepper` to take inc/dec keys + icon; add a `_spacingScale`(0.7–1.5,step .1) + `_incSpacing`/`_decSpacing`; render a SECOND stepper (keys 'orbit3-spacing-inc/-dec', distinct icon e.g. `Icons.unfold_more_rounded`) stacked above the size stepper bottom-left. Thread `ringSpacingScale:_spacingScale` to BOTH the collapsed + open `Orbit3OneCircle`; scale arch `rowHeight` (`base + 14*_spacingScale`) and the 16px gap (`16*_spacingScale`). Pass `animateEntrance:false` to the OPEN-path circle only. `_populations = [5,13,24,50,100]`.
7. `orbit3_mock_data.dart`: lift the cap — friends beyond the 50-name pool use a deterministic `'User ${i+1}'`; support up to 100; keep ≥2 groups at the tail. `build(count:100).length==100`.
8. Rerun direct → preservation (orbit3_prototype_smoke_test, orbit3_one_circle_layout_test) → full `test/features/orbit3/` → `feature-host-all` → `flutter analyze`.
9. Visual proof: extend `orbit3_arch_preview_capture.dart` to also capture pop100 + a spacing-bumped frame; eyeball.
10. `graphify update .` + `./graphify-arch/refresh_arch_graph.sh`.
   Stop-if: any change forces editing `computeOrbit3RingLayout` or a non-additive change to OrbitalAvatar/InnerSky → replan.

## Risks And Edge Cases
- **Entrance-timer storm at pop100**: eager build of ~100 avatars → up to ~100 `Future.delayed` timers; drain ≥ ~3000ms in pop100 tests to avoid pending-timer at teardown (bottom-up delays are bounded fast, but the per-avatar Future.delayed still schedules).
- **Reading painted scale/translation**: tests read the `OrbitalAvatar`'s `Transform` matrix (`getMaxScaleOnAxis` / translation) — pin the specific Transform (the entrance one) to avoid matching unrelated Transforms.
- **ringSpacingScale box growth**: scaling radii without the box overflows; the box is scaled by `ringSpacingScale` too (avatars stay inside; FittedBox handles the collapsed path; the open path scrolls).
- **Group adjacency at 100**: with only 2 groups at the tail they share the last (top) row; if a future group count splits a row, assert-and-document — for now lock "2 groups, same row".
- **Reduce-motion**: `motionEnabled:false` must zero both riseUp + animateEntrance → instant; locked by a widget assertion.
- **goTo('100')**: the cycler helper loops up to 6 times — with 5 populations, ensure goTo reaches 100 (bump the loop bound if needed).

## Device/Relay Proof Profile
host-only for closure (visuals-only; no OS boundary/relay/crypto/DB). No device-proof. Visual: `flutter test test/features/orbit3/orbit3_arch_preview_capture.dart`.

## Acceptance Gates  (literal)
```bash
# RED (before edits) — must FAIL for the documented reason
flutter test test/features/orbit3/orbit3_one_circle_arch_test.dart   # compile-fail: new params
flutter test test/features/orbit3/orbit3_arch_layout_test.dart       # compile-fail: delay helper
flutter test test/features/orbit3/orbit3_screen_test.dart --plain-name 'spacing'   # keys absent

# Direct GREEN (after fix)
flutter test test/features/orbit3/orbit3_screen_test.dart
flutter test test/features/orbit3/orbit3_one_circle_arch_test.dart
flutter test test/features/orbit3/orbit3_arch_layout_test.dart
flutter test test/features/orbit3/orbit3_mock_data_test.dart

# Preservation sentinels
flutter test test/features/orbit3/orbit3_prototype_smoke_test.dart   # InnerSky/Fisheye unchanged
flutter test test/features/orbit3/orbit3_one_circle_layout_test.dart # layout math unchanged
flutter test test/features/orbit3/                                   # whole slice green

# Host glob gate
./scripts/run_host_test_gates.sh feature-host-all                    # 0 failures

# Visual proof
flutter test test/features/orbit3/orbit3_arch_preview_capture.dart   # build/orbit3_previews/*.png

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```
(No migration; no `/sims`.)

## Known-Failure Interpretation
- Expected RED: catalog 1–9 before the fix.
- Pre-existing dirty: graphify-out refresh churn (step 10).
- Environment blocker: none (host-only).
- Scope drift (BLOCKING): any red in non-Orbit3 tests, or any edit to `computeOrbit3RingLayout` / a NON-additive OrbitalAvatar/Orbit3OneCircle change.

## Done Criteria
- [ ] RED added first, failed for the expected reason.
- [ ] Mutation-verified (each fix has a re-red revert).
- [ ] Direct GREEN + preservation sentinels + `feature-host-all` pass.
- [ ] OrbitalAvatar/Orbit3OneCircle defaults proven unchanged (sentinel + default-preservation test); reduce-motion inert.
- [ ] pop100 builds + scrolls without pending-timer/exception.
- [ ] flutter analyze 0 new; git diff --check clean; no Scope Guard violations; both graphs refreshed.

## Scope Guard (hard "Do not")
- Do NOT edit `computeOrbit3RingLayout`, InnerSky, Fisheye, constellation, non-Orbit3 files, or OrbitalAvatar's DEFAULT behavior (all new params default to today).
- Do NOT scale the box without scaling radii together (overflow).
- Do NOT make the spacing stepper touch avatar size, nor the size stepper touch ring/arch spacing.

## Accepted Differences / Intentionally Out Of Scope
- Collapsed circle group glyph (`_Orbit3GroupGlyph`) unchanged (C2 targets the expanded arches).
- `_spacingScale`/`_avatarScale` not persisted.
- Group count fixed at 2 (adjacency lock); broader group simulation deferred.

## Dependency Impact
- Touches the SHARED `OrbitalAvatar` (additive). Orbit/Orbit2/Orbit3/feed depend on its DEFAULT behavior → preserved by defaults + the default-preservation test + InnerSky/Fisheye sentinel.

## Reviewer Findings
Sufficiency: each of the 5 changes has a falsifiable RED at the lowest tier that fails for the real reason (compile-fail for new params/helpers; measurable assertions for spacing/entrance/scale/counts). The single biggest risk — regressing the SHARED OrbitalAvatar — is double-locked (defaults reproduce the tree + InnerSky/Fisheye sentinel + a default-preservation test). Entrance tests read the actual painted Transform (scale/translate) rather than proxies. Thin spot: the rise "feel" (duration/curve/riseDist) is visually tuned — locked structurally (slide occurs, order is bottom-up, fast bound) but not pixel-exact; acceptable for a prototype.

## Arbiter Decision
Structural blockers: none. Deferred: exact rise distance/curve/stagger constants (visual). Verdict: implementation-ready (hand to WF-2).

## Final Execution Verdict
Verdict: ACCEPTED (host-green) | Files changed: `orbital_avatar.dart` (additive `child`/`riseUp`/`entranceDelayMs`/`animateEntrance` — defaults reproduce today's tree), `orbit3_arch_layout.dart` (`orbit3ArchEntranceDelayMs` rowMs60/colMs4), `orbit3_one_circle.dart` (`ringSpacingScale` scales radii+box, `animateEntrance` threaded), `orbit3_arch_panel.dart` (`Orbit3ArcRow`: friends+groups both `OrbitalAvatar`, group child = teal glyph keyed `orbit3-arch-group-*`, `riseUp`+bottom-up delay; deleted `_PanelGroupGlyph`), `orbit3_screen.dart` (`_spacingScale`+`_inc/_decSpacing`+second stepper via generalized `_SizeStepper`+`_buildSteppers`; thread `ringSpacingScale` to both circles; arch `rowHeight`/gap ×`_spacingScale`; open circle `animateEntrance:false`; `_populations`+=100), `orbit3_mock_data.dart` (cap 52→100, `'User N'`). | Tests: `flutter test test/features/orbit3/` **61/61**; orbit+orbit2 consumers **298/298** (shared OrbitalAvatar default preserved); `flutter analyze` 0. RED demonstrated for the new params (compile-fail) + assertions; mutation-verified: ignoring `animateEntrance`/dropping the rise translate re-reds TC-4. | Blocking: none. | QA verdict: clean; graphs refreshed. | Non-blocking follow-ups (owner): group adjacency holds while the last arch row has ≥2 slots (true on the tested surfaces); visual capture pop100.
