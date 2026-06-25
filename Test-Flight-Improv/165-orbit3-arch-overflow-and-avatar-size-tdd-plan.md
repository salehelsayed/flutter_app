# 165 - Orbit3 "Arch" Overflow + Avatar-Size Stepper  (New Feature)

Status: IMPLEMENTED host-green (2026-06-25)

Post-implementation refinements (user-driven, all host-green, 44/44):
- R1: arch hugs the circle's outer ring (anchored via LayoutBuilder to `areaH·frac − ring1·scale`), not pinned to the screen top.
- R2: arch panel is a transparent band ABOVE the circle (circle stays visible/tappable), not a full-screen overlay.
- R3: at dense populations the whole tail fits on ONE screen — the inner circle glides DOWN (`AnimatedAlign`, centre 0.5→0.65 when open) and the panel ADAPTIVELY packs (perRow from width, row height compresses to fit) so all overflow shows without scrolling. pop50 test now asserts all 35 panel `OrbitalAvatar`s (not a fixed row count). Visual proof: `build/orbit3_previews/arch_*.png` via `orbit3_arch_preview_capture.dart`.
Spec: free-text intent (no formal spec) — user request + reference Images 1–5, design forks resolved via AskUserQuestion (Replace-the-rings + Continuous-arcs)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| t0 | Evidence Collector | orbit3_screen.dart, orbit3_one_circle.dart, orbit3_one_circle_layout.dart, orbit3_mock_data.dart, orbit3_inner_sky_prototype.dart, orbit3_fisheye_prototype.dart (grep), orbit3_screen_test.dart, orbit3_one_circle_layout_test.dart, orbit3_wiring_test.dart, orbit3_prototype_smoke_test.dart | `Orbit3OneCircle` is SHARED by classic + InnerSky only (Fisheye does not use it). `orbit3-expand-toggle` is tap-locked for InnerSky by smoke test:74 → node must survive. Orbit3 has NO gate-array/classify_path/dart-define registration → host tests AUTO-glob. | Plan additive `showOverflowNode`+`avatarScale`; arch/panel/stepper as classic-only siblings |
| t0 | Planner | (above) | Arch is a SCREEN-level sibling above the circle; circle hard-caps at 2 rings; pure arc-geometry helper mirrors `orbit3_one_circle_layout.dart`. | Emit RED catalog + matrix |
| t0 | Reviewer (sufficiency) | this doc | zero empty matrix cells; blind-spot sweep done (panel-reset-on-cycle = invariant-under-transition; scale applies to both surfaces = sibling-consistency). | — |
| t0 | Arbiter | this doc | No structural blockers; host-only closure (visuals-only prototype). | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | | reds now green | |
| | preservation GREEN | | | sentinels green | |
| | named gates | | | gate green | |
| | QA (independent) | | | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline below (user request + Images 1–5; forks resolved: Replace-the-rings, Continuous-arcs, +/- scales both surfaces)
- Gate definitions: scripts/run_test_gates.sh (Orbit3 is NOT listed → host-glob only)
- Host glob gate: scripts/run_host_test_gates.sh `feature-host-all` (auto-globs `test/features/**`)
- Numbering / index: Test-Flight-Improv/00-INDEX.md (next-free = 165)

## Session Classification
implementation-ready (visuals-only prototype; host-only closure; no migration, no device-proof)

## Exact Problem Statement
The Orbit3 "One Circle" (Classic lab + Circle view) renders members on fixed Orbit-parity rings. Today, once population exceeds the two inner orbits (13 = ring0 5 + ring1 8), the green "+N" node (`_Orbit3ExpandNode`, `ValueKey('orbit3-expand-toggle')`) on the outer ring grows the box into a 3rd/4th/5th ring (`orbit3_one_circle.dart:240-260` + `_expanded`/`_toggleExpand` in `orbit3_screen.dart`). At 24–50 people this "gets messy" (user Image 2): too many concentric rings, labels collide, the circle balloons.

User-confirmed redesign (Images 1–5):
1. **Arch replaces ring-growth.** The inner circle is hard-capped at 2 orbits and never grows. When population > 13, a new **arch** affordance appears ABOVE the circle showing `+N` and a people icon (N = overflow). (Image 3's "+37 with its icon" promoted onto the arch.)
2. **Arch panel (continuous arcs).** Tapping the arch opens a scrollable panel of stacked shallow **semi-circle arc rows** (~8 avatars each, no tier labels), with a "MORE" header + up-chevron to close; tapping a member opens the mock chat. (Images 4–5.)
3. **Avatar-size +/- stepper.** A simple two-button control scales avatar diameters across BOTH the inner circle and the arch panel so the user can play with sizing.

What must improve: overflow beyond 2 rings is shown as one arch + an arc panel, NOT messy concentric rings; an avatar-size stepper is available on the One Circle.

What must stay unchanged (→ preserved-green sentinels):
- **InnerSky prototype** (`Orbit3InnerSkyPrototype`) reuses `Orbit3OneCircle` with `cappedRings: 3` + `onToggleExpand: _launch` and DEPENDS on the in-ring `orbit3-expand-toggle` node (tap-locked by `orbit3_prototype_smoke_test.dart:74`). Must be byte-identical.
- **Fisheye prototype**, constellation/Map view, names double-tap, search-glow, member-chat-open, population cycler, layout math (`computeOrbit3RingLayout`), and all non-Orbit3 code.

## Root Cause (verify → refute confirmed)
Not a bug — a deliberate feature swap of the overflow treatment. The exact seams:
- **Overflow node draw**: `orbit3_one_circle.dart:104` (`showExpand`), `:108` (`hasNode`), `:240-260` (the `_Orbit3ExpandNode` Positioned). This widget is SHARED — only `orbit3_screen.dart:372` (classic) and `orbit3_inner_sky_prototype.dart:247` (InnerSky) construct it (`grep Orbit3OneCircle lib` → exactly those two; Fisheye does not). So the node CANNOT be deleted; it must be gated by a new flag defaulting to the current behavior.
- **Classic grow-rings state**: `orbit3_screen.dart:70` (`_expanded`), `:184`/`:216` (resets), `:226-229` (`_toggleExpand`), `:377` (`expanded:`), `:382` (`onToggleExpand:`) — all classic-only; InnerSky owns its own `onToggleExpand:_launch`. These are removed for classic and replaced by arch/panel/scale state.
- **+N math**: `computeOrbit3RingLayout(count, expanded:false, maxVisibleRings:2).hiddenCount` already equals `count − 13` for count>13 (`orbit3_one_circle_layout.dart:104-105`); the new arch count helper must equal this (asserted by a test, not by coincidence).

Refuted / do-NOT-re-introduce:
- *"Delete the `_Orbit3ExpandNode` / `onToggleExpand` / `cappedRings`."* REFUTED — InnerSky relies on all three; deletion red-greens nothing and breaks `orbit3_prototype_smoke_test.dart`. Keep them; gate the draw with `showOverflowNode` (default true).
- *"Scale avatars AND radii uniformly."* REFUTED — the classic circle is wrapped in `FittedBox(fit: scaleDown)` (`orbit3_screen.dart:370`); uniform scaling is undone by fit-to-width, so the user would see NO change. Scale avatars only (radii fixed) so avatars grow relative to the rings.
- *"Fisheye also needs the flag."* REFUTED — Fisheye does not construct `Orbit3OneCircle` (grep clean).

## Real Scope
In scope:
- NEW pure helper `lib/features/orbit3/domain/orbit3_arch_layout.dart`: `orbit3ArchOverflowCount(population)` + `computeOrbit3ArcRow(...)`/`computeOrbit3ArchArcs(...)` (shallow-arc geometry).
- NEW widget `lib/features/orbit3/presentation/widgets/orbit3_arch_panel.dart`: `Orbit3ArchBar` (the `+N 👥` arch) + `Orbit3ArchPanel` (MORE header + scrollable arc rows).
- MODIFY `orbit3_one_circle.dart`: add `bool showOverflowNode = true` (gate the in-ring node) + `double avatarScale = 1.0` (multiply member avatars + centre).
- MODIFY `orbit3_screen.dart` (classic oneCircle branch only): drop `_expanded`/`_toggleExpand`; add `_archOpen`/`_avatarScale`; pass `cappedRings: kOrbit3CollapsedRings, showOverflowNode: false, avatarScale: _avatarScale`; render arch bar (top) + panel (overlay) + size stepper (bottom-left, mirroring `_ZoomControls`); reset `_archOpen=false` on population/lab/view change.
- MODIFY `orbit3_screen_test.dart`: rewrite the 3 grow-rings cases to the arch behavior; add arch/panel/stepper cases.
- NEW tests `orbit3_arch_layout_test.dart`, `orbit3_one_circle_arch_test.dart`.

Out of scope (Accepted Differences below): wiring the size stepper into InnerSky/Fisheye; real contacts data; persisting `_avatarScale`/`_archOpen`; tier labels (user chose Continuous arcs); any non-Orbit3 file.

## Files To Inspect Next
Production: orbit3_screen.dart (classic branch ~308-409 + state ~65-229), orbit3_one_circle.dart (~82-283), orbit3_one_circle_layout.dart (constants/capacities), orbit3_mock_data.dart (overflow membership), orbit3_inner_sky_prototype.dart:247-259 (preserve contract).
Direct tests: orbit3_screen_test.dart, orbit3_one_circle_layout_test.dart, orbit3_prototype_smoke_test.dart.
Dependency-only context: orbital_avatar.dart (entrance timers), orbit2_mock_chat_screen.dart (chat open), background_readable_colors.dart, app_colors.dart.

## Existing Tests Covering This Area
- `orbit3_one_circle_layout_test.dart` covers `computeOrbit3RingLayout` math — UNCHANGED (helper not modified) → stays green.
- `orbit3_screen_test.dart` covers the One Circle surface, Orbit-parity sizes, sequential fill, **grow-rings expand/collapse (pop24/pop50)**, names, search, chat, zoom — the grow-rings cases get REWRITTEN; the rest stay.
- `orbit3_prototype_smoke_test.dart` covers InnerSky launch via `orbit3-expand-toggle` + Fisheye — must stay green (preservation of the shared node).
- `orbit3_wiring_test.dart` covers tab wiring — unaffected.
Missing coverage gaps (this plan adds): arch presence/absence + count; arch→panel open/close; panel arc rows + member chat; avatar-size stepper on both surfaces; `showOverflowNode` gate; panel-reset on population cycle.
Already in curated family arrays?: NO — Orbit3 is absent from `run_test_gates.sh`; all rows are AUTO-glob (`feature-host-all`).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/features/orbit3/orbit3_arch_layout_test.dart`::`orbit3ArchOverflowCount = max(0, pop-13) and matches layout.hiddenCount`
   - Tier: unit/application
   - Shape/setup: call `orbit3ArchOverflowCount(n)` for n∈{5,13,14,24,50}; cross-check `computeOrbit3RingLayout(count:n, expanded:false, maxVisibleRings:2).hiddenCount`.
   - RED on HEAD because: `orbit3_arch_layout.dart` / `orbit3ArchOverflowCount` does not exist (compile-fail).
   - GREEN asserts: 0,0,1,11,37 respectively AND equal to the layout's hiddenCount.
   - Mutation that re-reds: change formula to `pop-14` → 24→10 ≠ 11 reds.

2. `test/features/orbit3/orbit3_arch_layout_test.dart`::`computeOrbit3ArcRow places n avatars on a symmetric non-overlapping shallow arc`
   - Tier: unit/application
   - Shape/setup: `computeOrbit3ArcRow(n: 8, width: 360, avatar: 38)`.
   - RED on HEAD because: helper does not exist (compile-fail).
   - GREEN asserts: length==8; x strictly increasing and within [0,width]; arc symmetric (`y.first == y.last`, centre is the extremum); adjacent x-gap ≥ avatar (no horizontal overlap).
   - Mutation that re-reds: make all y equal (flat row) → symmetry/extremum assertion still holds but replace with "centre y differs from edge y" → reverting the arc dip reds it; OR return constant x → monotonic-x assertion reds.

3. `test/features/orbit3/orbit3_arch_layout_test.dart`::`computeOrbit3ArchArcs splits count into rows of <=8, total preserved`
   - Tier: unit/application
   - Shape/setup: `computeOrbit3ArchArcs(count: 37, width: 360)`.
   - RED on HEAD because: helper does not exist.
   - GREEN asserts: rows.length == 5; each row.length ≤ 8; sum == 37; row sizes [8,8,8,8,5].
   - Mutation that re-reds: change perRow to 10 → 4 rows reds the `==5` assertion.

4. `test/features/orbit3/orbit3_one_circle_arch_test.dart`::`showOverflowNode:false suppresses the in-ring expand node even with hidden members`
   - Tier: widget
   - Shape/setup: pump `Orbit3OneCircle(items: 24, cappedRings: 2, showOverflowNode: false)` in a MaterialApp wrap; drain timers.
   - RED on HEAD because: `showOverflowNode` param does not exist (compile-fail); once added-but-unwired the node still draws.
   - GREEN asserts: `find.byKey(ValueKey('orbit3-expand-toggle'))` findsNothing; exactly 13 `OrbitalAvatar`.
   - Mutation that re-reds: revert the `hasNode = showOverflowNode && …` gate (always draw) → node reappears, findsNothing reds.

5. `test/features/orbit3/orbit3_one_circle_arch_test.dart`::`showOverflowNode default true preserves InnerSky node (cappedRings:3)`
   - Tier: widget
   - Shape/setup: pump `Orbit3OneCircle(items: 50, cappedRings: 3, onToggleExpand: () {})` (defaults → showOverflowNode true).
   - RED on HEAD because: compile-fail until param added; after adding, locks the default so the gate can't silently flip.
   - GREEN asserts: `orbit3-expand-toggle` findsOneWidget (preservation twin of InnerSky).
   - Mutation that re-reds: flip default to `false` → reds (and would break the InnerSky smoke test).

6. `test/features/orbit3/orbit3_one_circle_arch_test.dart`::`avatarScale multiplies member avatar diameters`
   - Tier: widget
   - Shape/setup: pump `Orbit3OneCircle(items: 13, avatarScale: 1.4)`; read `OrbitalAvatar.size` set.
   - RED on HEAD because: `avatarScale` param does not exist (compile-fail).
   - GREEN asserts: sizes == {38*1.4, 30*1.4} (i.e. {53.2, 42.0}); and at `avatarScale:1.0` sizes == {38,30}.
   - Mutation that re-reds: drop the `* avatarScale` factor → sizes stay {38,30}, the 1.4 assertion reds.

7. `test/features/orbit3/orbit3_screen_test.dart`::`past two rings (pop 24) shows the ARCH (+11) above the circle, not an in-ring node` (REWRITE of the old "expand arrow" case)
   - Tier: widget (screen)
   - Shape/setup: pump `Orbit3Screen`; `goTo('24')`; drain.
   - RED on HEAD because: `orbit3-arch-overflow` key + `+11` arch text don't exist yet; today HEAD draws `orbit3-expand-toggle` instead.
   - GREEN asserts: 13 `OrbitalAvatar` in the circle; `find.byKey(ValueKey('orbit3-expand-toggle'))` findsNothing; `find.byKey(ValueKey('orbit3-arch-overflow'))` findsOneWidget; `find.text('+11')` findsOneWidget.
   - Mutation that re-reds: revert the screen's `showOverflowNode:false` (node returns) OR revert arch render (arch gone) → asserts red.

8. `test/features/orbit3/orbit3_screen_test.dart`::`tapping the arch opens the arc panel; a member tap opens that chat`
   - Tier: widget (screen)
   - Shape/setup: `goTo('24')`; tap `orbit3-arch-overflow`; pump+drain; assert panel; tap first panel `OrbitalAvatar`; pump > double-tap timeout + drain.
   - RED on HEAD because: no `orbit3-arch-panel` exists.
   - GREEN asserts: `find.byKey(ValueKey('orbit3-arch-panel'))` findsOneWidget; ≥1 `orbit3-arch-arc-row-0`; a `Scrollable` is present in the panel subtree; after member tap `find.byType(Orbit2MockChatScreen)` findsOneWidget.
   - Mutation that re-reds: revert the `onTap → _toggleArch`/`_archOpen` wiring → panel never appears, reds.

9. `test/features/orbit3/orbit3_screen_test.dart`::`pop 50 arch shows +37 and the panel lists all 37 overflow members`
   - Tier: widget (screen)
   - Shape/setup: `goTo('50')`; assert `+37`; open panel; count panel members across rows.
   - RED on HEAD because: arch/panel absent on HEAD.
   - GREEN asserts: `find.text('+37')` findsOneWidget; panel renders the 37 overflow items (35 `OrbitalAvatar` + 2 group glyphs `orbit3-inner-group-*` OR a panel-scoped group key) — assert total overflow widgets == 37 within the panel subtree (scroll to materialize if needed, or assert the model count the panel was built from via a row-count check rows==5).
   - Mutation that re-reds: revert overflow slicing (`items.skip(13)`) → wrong membership reds the count.

10. `test/features/orbit3/orbit3_screen_test.dart`::`avatar-size stepper grows/shrinks BOTH circle and panel avatars` (sibling-surface consistency)
    - Tier: widget (screen)
    - Shape/setup: `goTo('24')`; read circle `OrbitalAvatar.size` set; tap `orbit3-avatar-size-inc`; re-read (bigger); tap `orbit3-avatar-size-dec` twice; re-read (smaller); then open panel and assert panel avatars also reflect the scale.
    - RED on HEAD because: stepper keys + `_avatarScale` don't exist.
    - GREEN asserts: after `inc`, max circle `OrbitalAvatar.size` > 38; after two `dec`, max < 38; panel `OrbitalAvatar.size` tracks the same scale (panel max size == circle max size at equal ring/avatar base, or simply panel size != default-38 after scaling).
    - Mutation that re-reds: revert `avatarScale` plumb-through to the panel → panel sizes stay fixed, the panel assertion reds.

11. `test/features/orbit3/orbit3_screen_test.dart`::`cycling population keeps 2 rings, updates the arch count, and CLOSES an open panel` (invariant-under-transition; REWRITE of the old "resets to collapsed two-ring" case)
    - Tier: widget (screen)
    - Shape/setup: `goTo('24')`; open panel; `goTo('50')`.
    - RED on HEAD because: arch/panel/reset don't exist; HEAD asserts the old collapse-of-rings.
    - GREEN asserts: after cycling, `orbit3-arch-panel` findsNothing (auto-closed); `find.text('+37')` findsOneWidget; still 13 `OrbitalAvatar` in the circle (never a 3rd ring).
    - Mutation that re-reds: remove the `_archOpen=false` reset in `_cyclePopulation` → stale panel lingers, `findsNothing` reds.

12. `test/features/orbit3/orbit3_screen_test.dart`::`pop 13 and pop 5 show NO arch and NO in-ring node` (preserved/extended)
    - Tier: widget (screen)
    - Shape/setup: `goTo('13')` then `goTo('5')`.
    - RED on HEAD because: `orbit3-arch-overflow` key absent (the findsNothing direction passes today, but the assertion compiles only after the key type exists in the tree at other pops; primarily this LOCKS the no-arch-at-≤13 invariant).
    - GREEN asserts: `orbit3-arch-overflow` findsNothing at both; `orbit3-expand-toggle` findsNothing; avatar counts 13 and 5.
    - Mutation that re-reds: change arch visibility to `overflow >= 0` (show at 0) → arch appears at pop13, findsNothing reds.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Arch count = overflow | pure logic | unit | orbit3_arch_layout_test.dart::overflow=max(0,pop-13)…matches hiddenCount | helper absent (compile-fail) | formula→pop-14 reds | `flutter test test/features/orbit3/orbit3_arch_layout_test.dart` | AUTO (glob) |
| Arc row geometry | pure logic | unit | orbit3_arch_layout_test.dart::computeOrbit3ArcRow symmetric non-overlap | helper absent | flatten arc / const x reds | `flutter test test/features/orbit3/orbit3_arch_layout_test.dart` | AUTO (glob) |
| Rows of ≤8 | pure logic | unit | orbit3_arch_layout_test.dart::computeOrbit3ArchArcs split | helper absent | perRow→10 reds rows==5 | `flutter test test/features/orbit3/orbit3_arch_layout_test.dart` | AUTO (glob) |
| Classic suppresses node | UI gate | widget | orbit3_one_circle_arch_test.dart::showOverflowNode:false suppresses node | param absent (compile-fail) | revert `showOverflowNode && …` gate | `flutter test test/features/orbit3/orbit3_one_circle_arch_test.dart` | AUTO (glob) |
| InnerSky node preserved | UI gate default | widget | orbit3_one_circle_arch_test.dart::default true preserves node | param absent | default→false reds | `flutter test test/features/orbit3/orbit3_one_circle_arch_test.dart` | AUTO (glob) |
| Avatar scale (widget) | UI sizing | widget | orbit3_one_circle_arch_test.dart::avatarScale multiplies diameters | param absent | drop `* avatarScale` reds | `flutter test test/features/orbit3/orbit3_one_circle_arch_test.dart` | AUTO (glob) |
| Arch shows +N (pop24) | UI render | widget(screen) | orbit3_screen_test.dart::arch (+11) not in-ring node | arch key absent; node drawn today | revert showOverflowNode:false / arch render | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| Arch→panel + member chat | UI gesture/nav | widget(screen) | orbit3_screen_test.dart::tap arch opens panel; member opens chat | panel absent | revert _toggleArch wiring | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| Dense overflow (pop50) | UI render | widget(screen) | orbit3_screen_test.dart::+37 panel lists 37 | arch/panel absent | revert `items.skip(13)` | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| Size stepper both surfaces | UI sizing+consistency | widget(screen) | orbit3_screen_test.dart::stepper grows/shrinks circle AND panel | stepper keys absent | revert avatarScale→panel | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| Cycle keeps 2 rings + closes panel | UI transition | widget(screen) | orbit3_screen_test.dart::cycling updates count, closes panel | arch/reset absent | remove `_archOpen=false` reset | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| No arch ≤13 | UI render | widget(screen) | orbit3_screen_test.dart::pop13/pop5 no arch/no node | arch key absent | visibility→`>=0` reds | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| InnerSky/Fisheye preserved | preservation | widget(screen) | orbit3_prototype_smoke_test.dart (UNCHANGED) | n/a (sentinel) | flip showOverflowNode default → smoke reds | `flutter test test/features/orbit3/orbit3_prototype_smoke_test.dart` | AUTO (glob) |
| Layout math preserved | preservation | unit | orbit3_one_circle_layout_test.dart (UNCHANGED) | n/a (sentinel) | n/a | `flutter test test/features/orbit3/orbit3_one_circle_layout_test.dart` | AUTO (glob) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability**: `_archOpen`/`_avatarScale` are ephemeral prototype UI state with NO persistence and no event-derived latch — N/A (nothing to reconstruct on reopen). Documented, not silently skipped.
- **Sibling-surface consistency**: the avatar-size scale is a capability that must apply to EVERY avatar surface it owns — covered by TC-10 asserting BOTH the inner circle and the arch panel scale together (a divergent copy that scaled only the circle is the exact failure guarded).
- **Destructive-action side-effects**: no delete/cleanup/cancel added — N/A.
- **Invariant re-verification under new transitions**: the new arch↔panel↔population-cycle transition — covered by TC-11 (opening the panel then cycling population must close the panel and recompute `+N`, never leave a stale panel for the prior population); TC-12 re-verifies the no-arch-≤13 invariant across cycles.

## Invariants (locked by tests)
- INV-1: classic One Circle NEVER draws the in-ring `orbit3-expand-toggle` (overflow lives on the arch) → TC-4, TC-7.
- INV-2: InnerSky's in-ring node + launch behavior is unchanged → TC-5, `orbit3_prototype_smoke_test.dart`.
- INV-3: arch `+N` == `max(0, pop-13)` == layout.hiddenCount → TC-1, TC-7, TC-9.
- INV-4: avatar-size scale applies to circle AND panel uniformly → TC-6, TC-10.
- INV-5: cycling population/lab/view closes any open arch panel and keeps the circle at 2 rings → TC-11.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (dirty-tree baseline). Add the RED tests (catalog 1–12); run the focused cmds; confirm each fails for the documented reason (compile-fail for new helpers/params, assertion-fail for rewrites).
2. NEW `lib/features/orbit3/domain/orbit3_arch_layout.dart`:
   - `const int kOrbit3InnerSeats = …` derived as `orbit3RingCapacity(0)+orbit3RingCapacity(1)` (=13) — import from `orbit3_one_circle_layout.dart`, do NOT hardcode 13.
   - `int orbit3ArchOverflowCount(int population) => max(0, population - kOrbit3InnerSeats);`
   - `List<Offset> computeOrbit3ArcRow({required int n, required double width, required double avatar, double dip})` — even x across width, shallow symmetric arc in y.
   - `Orbit3ArchArcLayout computeOrbit3ArchArcs({required int count, required double width, int perRow = 8, double avatar = 38, double dip})` — chunk into rows, each via `computeOrbit3ArcRow`.
3. MODIFY `orbit3_one_circle.dart`: add `final bool showOverflowNode` (default `true`) and `final double avatarScale` (default `1.0`). Gate `final hasNode = showOverflowNode && (showExpand || showCollapse);` (line ~108). Multiply per-ring `av` and `layout.centerSize` (the "You" avatar + its Positioned offsets) by `avatarScale` at the consumption sites (do NOT scale radii). InnerSky passes neither → defaults preserve behavior.
4. NEW `lib/features/orbit3/presentation/widgets/orbit3_arch_panel.dart`:
   - `Orbit3ArchBar` — a glassy curved band with `Icons.people_alt_rounded` + `+$count`, `ValueKey('orbit3-arch-overflow')`, `onTap`.
   - `Orbit3ArchPanel` — `Positioned.fill` overlay (BackdropFilter), a centred "MORE" header (up-chevron, tap → `onClose`), then a `ListView`/`SingleChildScrollView` of arc rows built from `computeOrbit3ArchArcs`; each row a `SizedBox`+`Stack` keyed `orbit3-arch-arc-row-$i`; each avatar an `OrbitalAvatar` (friend, `size: avatar*avatarScale`) or the group glyph, tappable → `onFriendTap`/`onGroupTap`. Root key `ValueKey('orbit3-arch-panel')`.
5. MODIFY `orbit3_screen.dart` (classic oneCircle branch only):
   - Remove `_expanded` (`:70`), its resets (`:184`,`:216`), `_toggleExpand` (`:226-229`); add `bool _archOpen=false;`, `double _avatarScale=1.0;`, `_toggleArch()`, `_setArchOpen(false)` calls in `_cyclePopulation`/`_cycleLab`/`_toggleView`, and `_incAvatarSize()/_decAvatarSize()` (clamp 0.6–1.4, step 0.2).
   - In the classic `Stack` children: pass `Orbit3OneCircle(cappedRings: kOrbit3CollapsedRings, showOverflowNode: false, avatarScale: _avatarScale, …)` (drop `expanded`/`onToggleExpand`). Compute `overflow = orbit3ArchOverflowCount(_items.length)` and `overflowItems = _items.skip(kOrbit3InnerSeats).toList()`.
   - Add (gated on `_viewMode == oneCircle`): the arch bar `Positioned(top, centred)` when `overflow>0 && !_archOpen`; the `Orbit3ArchPanel` when `_archOpen`; the `_SizeStepper` `Positioned(left:12, bottom:12)` (mirrors `_ZoomControls`; bottom-right stays the search pill).
6. REWRITE/extend `orbit3_screen_test.dart` per catalog (TC-7,8,9,10,11,12); delete the old "no two avatars overlap when a 3rd ring is shown" case (no 3rd ring exists — its no-overlap concern moves to TC-2 arc geometry).
   Stop-if: making classic green forces an edit to `computeOrbit3RingLayout` or to InnerSky/Fisheye → replan (the seam is wrong); the helper must stay untouched.
7. Rerun direct → preservation (`orbit3_prototype_smoke_test.dart`, `orbit3_one_circle_layout_test.dart`) → full `test/features/orbit3/` → `feature-host-all` → `flutter analyze`.
8. After the lib edits land: `graphify update .` then `./graphify-arch/refresh_arch_graph.sh` (keep both graphs current per CLAUDE.md).

## Risks And Edge Cases
- **Shared widget regression** (highest): gating must default to current behavior — pinned by TC-5 + the InnerSky smoke sentinel.
- **Avatar overlap at max scale**: radii are fixed, so at `avatarScale` 1.4 the ring0/ring1 radial gap (46) is slightly under the scaled mean diameter (~47.6) — a ~1.6px cosmetic touch. Accepted for a prototype; clamp caps it at 1.4; no-overlap is asserted only at scale 1.0 (TC-6 base) and on the arc rows (TC-2).
- **Entrance timers**: panel `OrbitalAvatar`s schedule `globalIndex*40ms` timers — every panel test pumps ~2400ms before teardown (reuse the existing `tapExpand`/`drain` pattern) to avoid pending-timer failures.
- **Group items in overflow**: at pop24/50 the 2 groups land in the overflow slice → the panel must render group glyphs and route `onGroupTap` (mirrors the circle). Covered by TC-9.
- **FittedBox undoing scale**: mitigated by scaling avatars only (Refuted note); a regression to scaling radii would silently no-op the stepper — TC-6/TC-10 assert the diameter actually changes.

## Device/Relay Proof Profile
host-only for closure (visuals-only prototype; no OS boundary, no relay, no crypto, no DB). No device-proof. Optional visual confirmation: run the app to the Orbit3 tab (Classic → Circle), cycle population to 24/50, tap the arch, scroll, and exercise +/- — or capture a headless PNG following the existing `orbit3_constellation_preview_capture.dart` pattern (non-`_test`, not a gate).

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/orbit3/orbit3_arch_layout_test.dart        # compile-fail: helper missing
flutter test test/features/orbit3/orbit3_one_circle_arch_test.dart    # compile-fail: params missing
flutter test test/features/orbit3/orbit3_screen_test.dart --plain-name 'arch'   # assertion-fail: arch absent

# Direct GREEN (after fix)
flutter test test/features/orbit3/orbit3_arch_layout_test.dart
flutter test test/features/orbit3/orbit3_one_circle_arch_test.dart
flutter test test/features/orbit3/orbit3_screen_test.dart

# Preservation sentinels (must stay green)
flutter test test/features/orbit3/orbit3_prototype_smoke_test.dart    # InnerSky/Fisheye unchanged
flutter test test/features/orbit3/orbit3_one_circle_layout_test.dart  # layout math unchanged
flutter test test/features/orbit3/                                    # whole Orbit3 slice green

# Host glob gate for the touched subsystem
./scripts/run_host_test_gates.sh feature-host-all                     # 0 failures (Orbit3 auto-globbed)

# Hygiene
flutter analyze          # 0 new issues
git diff --check
```
(No migration gate — no schema change. No `/sims` / discovery — no simulator/device rows.)

## Known-Failure Interpretation
- Expected RED: catalog tests 1–12 before the fix (compile-fail for new helpers/params; assertion-fail for rewrites).
- Pre-existing dirty: none expected on the `new-orbit` branch (clean tree at session start); record `git status --short` before editing so the graphify-out refresh churn (step 8) is not mistaken for product change.
- Environment blocker (NOT product): none (host-only).
- Scope drift (BLOCKING): any red outside `test/features/orbit3/**` or any edit to a non-Orbit3 file, `computeOrbit3RingLayout`, or InnerSky/Fisheye behavior.

## Done Criteria
- [ ] RED added first, failed for the expected reason.
- [ ] Mutation-verified (each fix has a re-red revert per the matrix).
- [ ] Direct GREEN + preservation sentinels + `feature-host-all` pass.
- [ ] No migration (confirmed: no schema change).
- [ ] No OS-boundary/multi-device path (confirmed: visuals-only host prototype).
- [ ] Every new test auto-globbed and verified present in `feature-host-all`.
- [ ] flutter analyze 0 new; git diff --check clean; no Scope Guard violations.
- [ ] Both graphs refreshed (`graphify update .` + `refresh_arch_graph.sh`).

## Scope Guard (hard "Do not")
- Do NOT edit any non-Orbit3 file, `computeOrbit3RingLayout`, `orbit3_one_circle_layout_test.dart`, InnerSky, Fisheye, the constellation, or `Orbit2MockChatScreen`.
- Do NOT delete `onToggleExpand`/`cappedRings`/`_Orbit3ExpandNode` (InnerSky depends on them).
- Do NOT scale ring radii (only avatar diameters).
- Do NOT add tier labels to the panel (user chose Continuous arcs).

## Accepted Differences / Intentionally Out Of Scope
- Size stepper wired only into the Classic One Circle (not InnerSky/Fisheye/constellation) — those labs are throwaway comparison directions; a future session can thread `avatarScale` if a winner is chosen.
- `_avatarScale`/`_archOpen` are not persisted across app restarts — prototype, ephemeral by design (Blind-Spot lifecycle N/A).
- Panel uses continuous unlabeled arcs (no CREW/CIRCLE/FRIENDS/CLOSE tiers) — explicit user choice.

## Dependency Impact
- None. Self-contained Orbit3 prototype; no other session/work depends on this contract.

## Reviewer Findings
Sufficiency: every behavior has a RED at the lowest tier that fails for the real reason; the shared-widget regression is double-locked (TC-5 + smoke sentinel); the +N math is cross-checked against the existing layout rather than asserted in isolation; sibling-consistency (scale on both surfaces) and invariant-under-transition (panel reset on cycle) are explicit rows. No empty matrix cells. No simulator/migration obligations (correctly host-only). Thin spot: the panel "lists all 37" assertion may need a scroll-to-materialize or a row-count proxy because off-screen `ListView` children aren't built — TC-9 notes both options.

## Arbiter Decision
Structural blockers: none. Deferred details: exact arc `dip` curve + panel backdrop styling are visual params (tune at execution, locked only for symmetry/no-overlap, not exact px). Accepted differences: as listed. Verdict: implementation-ready.

## Final Execution Verdict
Verdict: ACCEPTED (host-green) | Files changed: +`lib/features/orbit3/domain/orbit3_arch_layout.dart`, +`lib/features/orbit3/presentation/widgets/orbit3_arch_panel.dart`, ~`orbit3_one_circle.dart` (additive `showOverflowNode`/`avatarScale` + scale-avatars-not-radii + gated node), ~`orbit3_screen.dart` (drop `_expanded`/`_toggleExpand`; add `_archOpen`/`_avatarScale` + `_toggleArch`/`_inc`/`_decAvatarSize` + `_SizeStepper` + classic arch/panel/stepper siblings, `cappedRings:2`+`showOverflowNode:false`); +2 new test files; ~`orbit3_screen_test.dart` (3 grow-rings cases rewritten to arch + 3 new). | Tests run: `flutter test test/features/orbit3/` **44/44 pass** (incl. preservation: InnerSky/Fisheye smoke, layout math, wiring). RED confirmed pre-fix (8 screen reds "could not find orbit3-arch-overflow"); GREEN post-fix. Mutation-verified: removing the `showOverflowNode &&` gate re-reds 4 tests. | Blocking: none. | QA verdict: `flutter analyze` 0-new (1633 pre-existing baseline, none in orbit3). Both graphs refreshed. | Non-blocking follow-ups (owner): visual on-device confirmation deferred (host-only closure); size-stepper not wired into InnerSky/Fisheye by design.
