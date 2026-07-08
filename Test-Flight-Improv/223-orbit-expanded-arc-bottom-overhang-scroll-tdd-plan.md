# 223 - Orbit expanded-arc bottom nodes are painted below the canvas hit gate (Bug)

Status: awaiting-review (revised per `223-review-fixlist.md`, 2026-07-08)
Spec: free-text intent (no formal spec) — verified PARTIALLY-TRUE via adversarial verify→refute (9-agent workflow + direct source reads), then re-audited (8-agent workflow + empirical hit-test repro) → mechanism corrected.

## Planning Progress  (provenance / narrative — NON-GATING; the Acceptance Gates below are the verifiable contract)
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-08 | Evidence Collector | orbit_arc_layout.dart, orbital_visualization.dart, inner_circle_interactive_surface.dart, orbital_avatar.dart, orbit_sculpt_summon_wired_test.dart, orbit_geometry_prefs_use_cases.dart, run_test_gates.sh | Root cause confirmed on HEAD; long-press + horizontal-spill REFUTED | Build matrix |
| 2026-07-08 | Reviewer (fix-list) | 223-review-fixlist.md + source re-verify (dy=-r·cosφ :336, _tapTargetSize :468-473, kOrbitMinTapTarget :31, arcWrap∈[0.5,2.5]) | **Mechanism corrected**: spacer→grow boxHeight downward (hit gate); all-seats tap-box helper; arcWrap in scope; tap-based PROD gate | Re-emit plan |
| 2026-07-08 | Arbiter | — | implementation-ready, host-only closure | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-08 19:02:17 CEST | contract extraction | `Test-Flight-Improv/223-orbit-expanded-arc-bottom-overhang-scroll-tdd-plan.md`; `scripts/run_test_gates.sh`; `scripts/run_host_test_gates.sh`; `lib/features/orbit/domain/orbit_arc_layout.dart`; `lib/features/orbit/presentation/widgets/orbital_visualization.dart`; `lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart`; `test/features/orbit/domain/orbit_arc_layout_test.dart` | `git status --short`; `graphify query "Orbit expanded arc bottom overhang: relationship between orbit_arc_layout, OrbitalVisualization boxHeight, InnerCircleInteractiveSurface scroll compensation, and orbit_sculpt_summon_wired_test" --budget 1500`; gate definitions verified: `groups` pins `orbit_sculpt_summon_wired_test.dart`, `feature-host-all` runs all `test/features/**/*_test.dart` | scope confirmed: add RED tests first, add pure bottom-overhang helper, grow `boxHeight` downward only, remove scroll-compensation knob guard, preserve `cy`/top overhang/anchors; no blocker | spawn Executor agent |
| 2026-07-08 19:03:51 CEST | Executor contract + owner inspection | `Test-Flight-Improv/223-orbit-expanded-arc-bottom-overhang-scroll-tdd-plan.md`; `lib/features/orbit/domain/orbit_arc_layout.dart`; `lib/features/orbit/presentation/widgets/orbital_visualization.dart`; `lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart`; `test/features/orbit/domain/orbit_arc_layout_test.dart`; `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart`; `scripts/run_test_gates.sh`; `scripts/run_host_test_gates.sh` | `cd graphify-arch && graphify query "Orbit expanded arc bottom overhang scroll compensation: orbit_arc_layout OrbitalVisualization inner_circle_interactive_surface orbit_sculpt_summon_wired_test TC-223" --budget 1500`; `git status --short`; `rg -n ...`; `nl -ba ...` owner reads | Scope and gates reconfirmed. Dirty unrelated files present; assigned production/test owner files not dirty before this Executor pass. No production edits made. | Run baseline gates before test edits |
| 2026-07-08 19:04:06 CEST | baseline gates started | `Test-Flight-Improv/223-orbit-expanded-arc-bottom-overhang-scroll-tdd-plan.md` | Starting `./scripts/run_test_gates.sh groups`, then `./scripts/run_host_test_gates.sh feature-host-all` | pending | Record baseline outcomes before RED test edits |
| 2026-07-08 19:06:03 CEST | baseline gate result | `Test-Flight-Improv/223-orbit-expanded-arc-bottom-overhang-scroll-tdd-plan.md` | `./scripts/run_test_gates.sh groups` | PASS: `01:22 +1171: All tests passed!` | Run `./scripts/run_host_test_gates.sh feature-host-all` baseline |
| 2026-07-08 19:25:25 CEST | Executor child materialization failure; local fallback start | `Test-Flight-Improv/223-orbit-expanded-arc-bottom-overhang-scroll-tdd-plan.md` | Spawned Executor `019f42ae-99c5-79c1-b42f-1b46a443ccd3` produced owner-inspection and groups-baseline evidence, but stayed running through two bounded waits; child was closed. Assigned production/test files still had no child edits. Orphan check found no remaining `feature-host-all` process/output. | `spawn_or_tool_failure` for child completion only; local sequential fallback is safe because the plan remains concrete and no partial code/test delta exists | Locally run missing baseline: `./scripts/run_host_test_gates.sh feature-host-all` |
| 2026-07-08 19:48:00 CEST | baseline gate failure triage start | `Test-Flight-Improv/223-orbit-expanded-arc-bottom-overhang-scroll-tdd-plan.md` | `./scripts/run_host_test_gates.sh feature-host-all` failed before any orbit code/test edits at `#357 test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` (`Some tests failed`, exit 1). No log redirection was used; terminal output is truncated, so exact assertion is not yet known. | classification: `pending_triage`; failure occurred pre-edit and outside assigned orbit scope | Focused triage command: `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` |
| 2026-07-08 19:48:49 CEST | baseline gate triage result | `.codex-test-logs/223-group-conversation-wired-bg-task-focused.log`; `Test-Flight-Improv/223-orbit-expanded-arc-bottom-overhang-scroll-tdd-plan.md` | Focused file reproduced before any orbit edits. Failure: `ordinary media upload failure after unmount still persists failed parent status` expected `'sending'`, actual `'queued_offline'`. | classification: `pre-existing unrelated-but-required`; outside 223 orbit scope, no fix attempted. This blocks final acceptance unless the required `feature-host-all` gate becomes green or is documented as known. | Continue orbit RED tests; preserve final blocker evidence |
| 2026-07-08 19:51:20 CEST | RED test authoring start | `test/features/orbit/domain/orbit_arc_layout_test.dart`; `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart` | Owner snippets re-read after local fallback; assigned production/test files still clean except this plan file. | adding TC-223 tests before production edits; no production code touched yet | Run focused RED/guard commands |
| 2026-07-08 19:56:41 CEST | RED/guard focused evidence | `test/features/orbit/domain/orbit_arc_layout_test.dart`; `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart` | RED: `flutter test ...orbit_arc_layout_test.dart --plain-name 'TC-223-01'` and `--plain-name 'TC-223-05a'` fail because `orbitArcBottomOverhang` is missing; `TC-223-02` and `TC-223-05b` fail with `tappedFriends.single`/`No element` after node tap; `TC-223-03` fails with 39px spacing-drag drift. Guards: `TC-223-04` PASS; `TC-223-06` PASS after using the visible `orbitGap` planted handle at seeded `sp=1.5` because the originally specified spacing handle is itself hidden on HEAD. | expected RED/guard evidence complete; no production code touched yet | Implement helper, box-height growth, and compensation guard removal |
| 2026-07-08 19:59:05 CEST | implementation + direct GREEN | `lib/features/orbit/domain/orbit_arc_layout.dart`; `lib/features/orbit/presentation/widgets/orbital_visualization.dart`; `lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart`; `test/features/orbit/domain/orbit_arc_layout_test.dart`; `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart` | Implemented additive `orbitArcBottomOverhang`, grew expanded visualization `boxHeight` by top + bottom overhang while keeping `cy = _center + overhang`, and removed the knob-specific scroll-compensation gate. `flutter test test/features/orbit/domain/orbit_arc_layout_test.dart` PASS `00:00 +19`; `flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart` PASS `00:05 +73`; preservation `TC-198-71`, `TC-198-72`, `TC-198F-02`, `TC-198F-27` each PASS. | direct scope green; scope guard upheld (`orbitArcOverhang`, `cy`, anchors unchanged) | Run named gates, hygiene, graphify updates |
| 2026-07-08 20:08:04 CEST | named gates + hygiene + graph updates | `scripts/run_test_gates.sh`; `scripts/run_host_test_gates.sh`; `graphify-out/`; `graphify-arch/graphify-out/`; `graphify-arch/GRAPH_SELECTION.md`; `graphify-arch/comparison.json`; touched orbit files | `./scripts/run_test_gates.sh groups` PASS `01:19 +1176`; `./scripts/run_host_test_gates.sh feature-host-all` exited 0 (output huge/truncated; pre-edit failure did not reproduce); `git diff --check` PASS; repo-wide `flutter analyze` FAILS with 1625 pre-existing issues outside this orbit patch, while focused `flutter analyze` on the 5 touched orbit files PASS `No issues found`; `graphify update .` completed; `./graphify-arch/refresh_arch_graph.sh` completed. | all required test gates passed; repo-wide analyze remains blocked by existing backlog, but touched-file analyzer is clean | QA reviewer pass |
| 2026-07-08 20:10:20 CEST | QA review + closure | `lib/features/orbit/domain/orbit_arc_layout.dart`; `lib/features/orbit/presentation/widgets/orbital_visualization.dart`; `lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart`; `test/features/orbit/domain/orbit_arc_layout_test.dart`; `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart` | QA reviewer `019f42ea-4fcb-7c81-9deb-5e3f30f9105e` reported no blocking findings; verdict `pass-with-notes`. Reviewer independently reran focused TC-223 checks and `git diff --check` on touched orbit files, all pass. Note: formatter churn is non-blocking; `223...tdd-plan.md` remains untracked in this worktree. | implementation accepted with notes; no blocking follow-up | Finalize verdict |

## Source Of Truth
- Spec / intent: inline below (free-text bug, adversarially verified + fix-list-corrected)
- Gate definitions: `scripts/run_test_gates.sh` — `orbit_sculpt_summon_wired_test.dart` pinned at **line 274**; `feature-host-all` glob = all `test/features/**/*_test.dart` (`run_host_test_gates.sh:132`)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (N/A — no sim rows)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (highest existing = 222 → this is **223**)

## Session Classification
implementation-ready (host-only; deterministic widget + domain tiers; no DB migration, no sim/device proof).

## Exact Problem Statement
When the orbit inner-circle is **expanded** (overflow arcs shown), enlarging **ring spacing** (`spacingScale` → 1.5) and/or **arc wrap** (`arcWrap` → 2.5) seats nodes whose **center is painted below the bottom of the canvas box** (`SizedBox(320, boxHeight)`). Because the canvas `Stack` uses `clipBehavior: Clip.none`, those nodes still **paint**, but Flutter's `RenderBox.hitTest` gates on `size.contains(position)` — so the node is **not tappable at its center** (the pointer falls through to the opaque background). The user sees a friend/group node they **cannot open**. With a large friend count (~50) the same under-count of the box height also caps `maxScrollExtent`, so the node cannot even be scrolled fully into view ("feels rigid"). A secondary defect: while expanded, dragging the **spacing** (or any overhang-changing) handle shifts the whole circle **without scroll compensation** — unlike `orbitGap`/`arcWrap`, which are compensated.

Who experiences it: any user who expands the arcs and increases spacing/arc-wrap with a busy orbit (the exact combination the sculpt UI invites). Why it matters: a node the app renders is **dead to touch**.

**What must improve:** (1) the bottom-most node's 48px tap box must be **inside the canvas hit gate** (grow `boxHeight` downward) AND reachable by scroll; (2) spacing (and any overhang-changing) handle drags must scroll-compensate like `orbitGap`/`arcWrap`.

**What must stay unchanged (→ preserved-green sentinels):** the **top-shift overhang** `cy = _center + overhang` and every geometry-handle anchor (handles stay seated where they are today); short/fitting expanded populations must **not** gain a phantom scroll; `orbitGap`/`arcWrap` planted-drag; long-press-to-enter-edit (both background detector and center-avatar path).

**Note on `avatarScale`:** it does **not** drive the interactive bottom poke. Every node's tap box is floored to 48px (`orbital_visualization.dart:80,468-473`; `orbital_avatar.dart:105-107`) and the largest ring/arc avatar at max `avatarScale=1.4` is `34×1.4=47.6 < 48`, so the 48px tap-box bottom is **independent of `avatarScale`**; `avatarScale` moves only the top-overhang and the *visual* avatar. The interactive defect is **`spacingScale`-driven (ring-2) and `arcWrap`-driven (arc tips)**.

## Root Cause (verify → refute confirmed)
1. **`orbitArcOverhang` accounts for the TOP arc poke only.** `lib/features/orbit/domain/orbit_arc_layout.dart:227-245`: `topY = centerY − maxR − av/2 − 16`; returns `max(0, ceil(kOrbitOverhangMargin(30) − topY))`. It never considers the ring-2 BOTTOM extent (`r2 = kOrbitRing2Radius(108) × spacingScale`, `computeOrbitLayout` line ~256) nor arc-tip droop.
2. **Arc tips droop DOWN at high `arcWrap`.** Arc seat `dy = −r·cos(φ)` (`:336`); `φ = orbitArcPhi(r, arcWrap)` rises to `kOrbitPhiFull=2.9` as `arcWrap→2.5` (`:186-192`), so `cos(φ)<0` ⇒ `dy>0` ⇒ arc tips sit **+150–290px below** ring-2 and far below the box.
3. **The canvas grows only at the top; its inner Stack does not clip; and hit-testing is gated to `[0, boxHeight]`.** `lib/features/orbit/presentation/widgets/orbital_visualization.dart:143-145`: `boxHeight = _size(320) + overhang`, `cx = 160` (fixed), `cy = _center + overhang`. Canvas `SizedBox(320, boxHeight)` (`:319-322`) wraps `Stack(clipBehavior: Clip.none)` (`:327`). `Clip.none` clips **paint, not hit-test**: `RenderBox.hitTest` returns false unless `size.contains(position)`, so a node whose center is below `boxHeight` is **painted but untappable at its center** (empirically proven: a node centered at `boxHeight+1.4` is not tappable at center but is tappable at its top sliver; `getBottomRight` still reports the full rect). At av=1.4/sp=1.5/50 friends the bottom ring-2 node center `= cy + 161.4 = 160+overhang+161.4 = boxHeight+1.4` — its center sits **below the hit gate**; its 48px tap box pokes `161.4 + 24 − 160 = 25.4px` below the box.
4. **The host content height == `boxHeight`.** `inner_circle_interactive_surface.dart:646-694`: canvas in `Center → Column(mainAxisSize.min)` with no vertical padding, so `maxScrollExtent = max(0, boxHeight − viewport)` under-counts the bottom poke; the outer `Stack` (default `Clip.hardEdge`) clips the strip below `boxHeight`.
5. **Secondary — scroll compensation ignores every knob except `orbitGap`/`arcWrap`.** `inner_circle_interactive_surface.dart:509-524` (`_compensateScrollForOverhang`, single scroll writer, called from `_onHandlePanUpdate` `:459`) **early-returns at line 510** unless `knob ∈ {orbitGap, arcWrap}`, though `_overhangFor` (`:267-273`) changes with `spacingScale`/`avatarScale`/`maxPerArc` too. So a spacing drag moves `cy`/`boxHeight` with no compensating scroll jump → the circle drifts under the finger.

**Refuted / do-NOT-re-introduce (investigated, deliberately NOT planned):**
- **"Long-press stops re-opening the size controls" — REFUTED (not a functional break).** Two edit-entry paths stay armed when `!_editing` and are undisplaced by expansion: the full-bleed opaque `Positioned.fill` background `GestureDetector` (`:636-644`, `onLongPressStart → _enterEdit`) and the center self-avatar long-press (`:388-392`, wired `orbital_visualization.dart:215-217`). `Clip.none` is paint-not-hit, so horizontal-spill regions are background-backed and still enter edit. Do **not** add a long-press-break fix.
- **Horizontal spill past the 320px box — by-design, out of scope.** Arc pinch targets a 170px bezel (`:189`) > 160px box half-width; visual no-op on ≥412pt phones. Do **not** fix.
- **Feared "Center up-shift" on expansion — EMPIRICALLY REFUTED.** When expanded the canvas is **top-anchored** (scrollable content == `boxHeight`, no centering slack), verified by `TC-198F-27` GREEN on HEAD. So growing `boxHeight` downward needs **no** Center-recentering compensation. (Minor: for a *short* expanded population where `boxHeight < viewport`, `Center` still applies, so downward growth by `p` shifts the centered canvas up by `p/2` — a static reposition, not a jump, and `TC-198F-27` sits at sp=1.0 where `p=0`.)

## Real Scope
**In scope:** (a) **grow `boxHeight` DOWNWARD** in `OrbitalVisualization` by a new bottom-overhang term (leaving `cx`/`cy`/top-overhang/handle anchors fixed) so the bottom node's 48px tap box is inside the hit gate AND the scroll content grows; (b) a new pure `orbit_arc_layout` helper that scans **all** `computeOrbitLayout` seats with a 48px tap-box floor (covers ring-2 at high `spacingScale` AND arc tips at high `arcWrap`); (c) extend `_compensateScrollForOverhang` to fire for **any** overhang-changing knob (drop the knob-enum guard, keep the `delta==0` early-return); (d) regression tests (2 domain + 4 widget).
**Out of scope** (owning work named): long-press re-open / auto-scroll handles (future orbit-sculpt UX); horizontal-spill clipping on narrow phones; any change to `cy` / top-overhang / handle anchors (would regress 198-series).

## Files To Inspect Next
Production:
- `lib/features/orbit/domain/orbit_arc_layout.dart` — `orbitArcOverhang` (:227-245), `computeOrbitLayout` seats (:248-…, ring-2 `:256`, arc `dy` `:336`), consts `kOrbitMinTapTarget=48` (:31), `kOrbitCanvasSize=320`/`kOrbitCanvasCenter=160`; **add** `orbitArcBottomOverhang(...)`.
- `lib/features/orbit/presentation/widgets/orbital_visualization.dart` — `overhang`/`boxHeight`/`cy` (:136-145) **[edit `boxHeight` only]**; `_tapTargetSize` (:468-473), `_minTapTargetSize=48` (:80); node keys `orbit-node-${index}` (:251).
- `lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart` — `_overhangFor` (:267-273), `_compensateScrollForOverhang` (:509-524, line 510 guard, `delta` `:512-513`, clamp `:519-521`), `_onHandlePanUpdate` (:455-461).
Direct tests:
- `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart` — `host()` (:87-120), `_friends` (:74), `settle` (:122), `canvasOrigin` (:170), `overhangOf` (:172-176), `expectedCenter` (:198-210), `centreAvatarF` (:234), `expandBadge` (:236-238); patterns TC-198-71 (:684, scroll-to-reveal sp handle :724-733), TC-198-72 (:794, planted drift<8), TC-198-22 (:306, av drag saturates 1.4), TC-198F-02 (handle re-seat), TC-198F-27 (:~1560, short-stack pinned).
- `test/features/orbit/domain/orbit_arc_layout_test.dart` — existing pure-layout tests (add bottom-overhang + arcWrap cases).
Dependency-only context:
- `lib/features/orbit/application/orbit_geometry_prefs_use_cases.dart` — `saveOrbitGeometryPrefs({secureKeyStore, prefs})` (:20); bounds `avatarScale 0.6–1.4`, `spacingScale 0.7–1.5`, `arcWrap 0.5–2.5`.

## Existing Tests Covering This Area
- TC-198-71 (`:684`), TC-198-72 (`:794`), TC-198F-27 (`:~1560`) all run at **default geometry (sp=1.0)** where the new bottom term is 0 and the extended compensation branch is never taken → they do NOT exercise the changed code (see §Blind-Spot Sweep / TC-223-06).
- TC-198-22 (`:306`) avatar-handle drag saturates at 1.4 — no scroll/reachability/tappability assertion.
- `orbit_arc_layout_test.dart` — pure math, no bottom-overhang/arcWrap-droop case.
**Missing coverage gaps:** nothing asserts `maxScrollExtent` (grep = 0 hits); nothing asserts a bottom node is **tappable** under large expanded geometry; nothing asserts spacing planted-drag; nothing asserts arc-tip droop coverage.
**Already in curated family arrays?:** `orbit_sculpt_summon_wired_test.dart` pinned in the **groups** gate (`run_test_gates.sh:274`) + auto-globs `feature-host-all`. `orbit_arc_layout_test.dart` auto-globs `feature-host-all` only.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/features/orbit/domain/orbit_arc_layout_test.dart`::**`TC-223-01 bottom overhang = max tap-box poke over ALL seats`**
   - Tier: unit / domain
   - Shape/setup: call `orbitArcBottomOverhang(memberCount: 50, geometry: g, centerY: 160)` at `g = OrbitGeometryPrefs.defaults.copyWith(avatarScale: 1.4, spacingScale: 1.5)` and at `defaults`.
   - Oracle (independent, iterate-all-seats): `expected = max(0, maxSeat( seat.dy + max(seat.avatarSize, kOrbitMinTapTarget(48))/2 ) − centerY)` computed from `computeOrbitLayout(memberCount:50, geometry:g)`.
   - RED on HEAD because: helper absent → unresolved reference (compile-RED).
   - GREEN after fix asserts: `closeTo(25.4, 1)` at av1.4/sp1.5 (ring-2 tap-box floor 48 ⇒ `161.4 + 24 − 160`); `== 0` at defaults; and `closeTo(expected, 0.5)` (matches the seat oracle).
   - Mutation that re-reds: body `return 0` → the `>20` / oracle assertions red. Second mutation: size to `avatar/2` instead of `max(avatar,48)/2` → the `25.4` assertion reds (would give 22.4) — locks the tap-box floor.

2. `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart`::**`TC-223-02 bottom node is TAPPABLE under large expanded geometry`**  **[PROD-CRITICAL — proves the user-facing goal]**
   - Tier: widget
   - Shape/setup: `final store = _SpyStore(); await saveOrbitGeometryPrefs(secureKeyStore: store, prefs: OrbitGeometryPrefs.defaults.copyWith(avatarScale: 1.4, spacingScale: 1.5)); await tester.pumpWidget(host(_friends(50), store: store)); await settle(tester); await expandBadge(tester);`. Pick the bottom-most node by scanning **ALL** mounted `orbit-node-*` keys (`i in 0..items.length−1`) for the greatest `tester.getBottomRight(f).dy` → `idx`. Scroll the Scrollable to `maxScrollExtent`. `await tester.tap(find.byKey(ValueKey('orbit-node-$idx')), warnIfMissed: false); await settle(tester);`.
   - RED on HEAD because: assert BOTH `pos.maxScrollExtent > 0` (there IS scroll) AND, after scrolling to max + tapping the bottom node's **center**, `tappedFriends` is **empty** — the node center is below the `SizedBox(320,boxHeight)` hit gate (`Clip.none` = paint-not-hit), so the tap falls through to the opaque background (`:636-644`); a stray idle background tap is a no-op (`_onBackgroundTap` `:343-351`). This discriminates "scrollable-but-not-interactive" from "not scrollable at all."
   - GREEN after fix asserts: `tappedFriends` contains that node's friend id (the grown `boxHeight` now includes the tap box in the hit gate AND the taller content lets it scroll into view).
   - Mutation that re-reds: revert the `boxHeight += bottomOverhang` edit → `tappedFriends` stays empty (RED).

3. `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart`::**`TC-223-03 spacing-handle drag keeps the circle planted (scroll compensates)`**
   - Tier: widget
   - Shape/setup: mirror TC-198-72 for `spacingScale`. `host(_friends(80))`, settle, `expandBadge`, scroll to the bottom so the `spacingScale` handle enters the band (per TC-198-71 `:724-733`), `longPressBg`; record `userBefore = tester.getCenter(centreAvatarF())`; `startGesture` on `handleF(OrbitKnob.spacingScale)`; `moveBy(Offset(0, 8))` ×6 (grows sp).
   - RED on HEAD because: `_compensateScrollForOverhang` early-returns for `spacingScale` (`:510`) → `Δoverhang` (tens–hundreds px as sp→1.5) is not absorbed → `centreAvatarF` drift ≫ 8px.
   - GREEN after fix asserts: per-step `|getCenter(centreAvatarF()).dy − userBefore.dy| < 8` (planted, TC-198-72 threshold).
   - Mutation that re-reds: re-add `if (knob != orbitGap && knob != arcWrap) return;` at `:510` → drift returns, RED. (This one branch is what locks the whole "compensate any overhang-changing knob" behavior — see step 5 / INV-223-2.)

4. `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart`::**`TC-223-04 expanded-but-fitting population gains no phantom scroll`**  **[over-growth guard]**
   - Tier: widget
   - Shape/setup: `host(_friends(50))` at **default** geometry, `await settle; await expandBadge;` (expanded; `boxHeight ≈ 561 < 600` test viewport — arc tips poke UP, ring-2 fits ⇒ bottom overhang == 0). Read `pos.maxScrollExtent`.
   - RED on HEAD: N/A — GREEN on HEAD (`maxScrollExtent == 0`). Purpose: fail if the fix grows `boxHeight` unconditionally.
   - GREEN after fix asserts: `pos.maxScrollExtent == 0`.
   - Mutation that re-reds: grow `boxHeight` by an unconditional constant (e.g. `+48` ignoring the poke) → content `609 > 600` → `maxScrollExtent > 0` → RED. (The old 8-friend collapsed case could NOT re-red this — `overflowExpanded` gate + `ConstrainedBox(minHeight:viewport)` floored it green for any spacer — so INV-223-4 is only truly locked by the expanded-but-fitting case.)

5. **arcWrap coverage pair (the only tests that reject a ring-2-only helper):**
   - `test/features/orbit/domain/orbit_arc_layout_test.dart`::**`TC-223-05a arcWrap droop counted (all-seats)`** — Tier: unit. `orbitArcBottomOverhang(memberCount: 50, geometry: defaults.copyWith(arcWrap: 2.5), centerY: 160) > 100` (outer arc tips droop ~150–290px). RED on HEAD: helper absent; after a ring-2-only impl it returns ~0 → still RED → only an all-seats scan passes. Mutation: restrict the scan to ring-2 seats → reds.
   - `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart`::**`TC-223-05b bottom ARC node tappable at arcWrap=2.5`** — Tier: widget. Seed `arcWrap: 2.5`, `_friends(50)`, expand, scroll to max, tap the bottom-most **arc** node's center (scan all `orbit-node-*`), assert its friend fired. RED on HEAD: arc node center far below the hit gate. Mutation: ring-2-only helper → the arc node stays untappable → RED.

6. `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart`::**`TC-223-06 handles stay seated & circle planted at sp=1.5 with bottom-growth active`**  **[real preservation — the 198-series sentinels don't exercise the perturbed regime]**
   - Tier: widget
   - Shape/setup: `final store = _SpyStore(); await saveOrbitGeometryPrefs(..., prefs: defaults.copyWith(spacingScale: 1.5)); await tester.pumpWidget(host(_friends(80), store: store)); await settle; await expandBadge; await longPressBg;` scroll so the visible knobs are in-band. Assert each visible handle sits at `expectedCenter(tester, k, gLoaded, 80, expanded: true)` within 2px (reads live `canvasOrigin`, so downward growth that shifts nothing relative to the canvas keeps it green). Then drag the sp handle and assert `centreAvatarF` drift < 8px.
   - RED on HEAD: N/A on HEAD (green — but it exercises the sp=1.5 regime the other sentinels never reach). Its job is to fail if the fix moves `cy`/anchors or breaks compensation at large spacing.
   - Mutation that re-reds: change the `boxHeight` edit to also add the bottom term to `cy` (grow symmetrically) → handles/circle shift → `expectedCenter` distance and/or drift red. Locks "downward-only, cy fixed" (INV-223-3).

## Test Coverage Matrix  (zero empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-223-01 | pure all-seats tap-box math | unit/domain | `…/domain/orbit_arc_layout_test.dart::TC-223-01` | helper absent → 25.4 at sp1.5, 0 at defaults | `return 0` / size to `avatar/2` → reds | `flutter test test/features/orbit/domain/orbit_arc_layout_test.dart` | **AUTO (feature-host-all glob)** |
| TC-223-02 | widget **tappability** (PROD-CRITICAL) | widget | `…/orbit_sculpt_summon_wired_test.dart::TC-223-02` | bottom node center below hit gate → center tap does not reach friend | revert `boxHeight += bottomOverhang` → tap empty | `./scripts/run_test_gates.sh groups` | **AUTO (file pinned :274; feature-host-all)** |
| TC-223-03 | gesture scroll-compensation | widget | `…::TC-223-03` | `_compensateScrollForOverhang` skips spacingScale (:510) → drift ≫ 8px | re-add `:510` knob-enum guard → drift reds | `./scripts/run_test_gates.sh groups` | **AUTO (pinned :274)** |
| TC-223-04 | over-growth guard | widget | `…::TC-223-04` | green on HEAD (maxScrollExtent==0); guards fix | unconditional `boxHeight+=48` → phantom scroll reds | `./scripts/run_test_gates.sh groups` | **AUTO (pinned :274)** |
| TC-223-05a | arcWrap droop (all-seats) | unit/domain | `…/domain/orbit_arc_layout_test.dart::TC-223-05a` | helper absent / ring-2-only impl returns ~0 | restrict scan to ring-2 → reds | `flutter test test/features/orbit/domain/orbit_arc_layout_test.dart` | **AUTO (feature-host-all glob)** |
| TC-223-05b | arc node tappable @arcWrap2.5 | widget | `…::TC-223-05b` | arc node center far below hit gate | ring-2-only helper → arc node untappable → reds | `./scripts/run_test_gates.sh groups` | **AUTO (pinned :274)** |
| TC-223-06 | preservation @sp1.5 (anchors + planted) | widget | `…::TC-223-06` | green on HEAD (perturbed-regime guard) | add bottom term to `cy` (symmetric growth) → anchors/drift red | `./scripts/run_test_gates.sh groups` | **AUTO (pinned :274)** |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the overhang/bottom-overhang is derived (recomputed each build from `_geometry`); `_geometry` persists via `saveOrbitGeometryPrefs`. **Covered** — TC-223-02/06 seed geometry into the store and pump a **fresh** surface, reconstructing the grown layout through `initState → loadOrbitGeometryPrefs`.
- **Sibling-surface consistency:** the fix touches `OrbitalVisualization.boxHeight` (its **single** host is `InnerCircleInteractiveSurface`, `:652`) and adds a pure helper. `cy`/top-overhang unchanged → any read-only, non-scrolling host is unaffected; TC-223-04 locks no phantom scroll. Justified.
- **Destructive-action side-effects:** N/A — no delete/cleanup/cancel path.
- **Invariant re-verification under new transitions:** the new transitions are "downward box growth" and "compensate any overhang-changing knob." TC-223-06 re-verifies handle seating + planted circle at sp=1.5 **with the growth active** (the pre-transition invariant that the 198-series only proves at sp=1.0). TC-223-03 re-verifies planted-under-drag.

## Invariants (locked by tests)
- **INV-223-1:** the bottom-most node (ring-2 at high sp, arc at high arcWrap) is **tappable** under large expanded geometry → **TC-223-02**, **TC-223-05b**.
- **INV-223-2:** an **overhang-changing** handle drag keeps the circle planted (scroll-compensated) → **TC-223-03**. *Acknowledged residual (like TC-198F-27's og short-stack):* at the **bottom scroll edge under spacing-SHRINK**, the sp-coupled bottom-content change can exceed the top-overhang `delta` the single writer absorbs (`:512`, `delta = Δtop-overhang` only) and the position clamps (`:519-521`); recovery is the steppers. `TC-223-03` only *grows* sp, so shrink-at-bottom is not claimed as planted. (Execution MAY instead extend `delta` to include Δbottom-overhang and add a shrink assertion; not required for closure.)
- **INV-223-3:** `cy = _center + overhang`, the top-shift overhang, and every handle anchor are UNCHANGED — the fix grows `boxHeight` **below `cy` only** → **TC-223-06** (+ preserved TC-198-71/72/F-02/F-27).
- **INV-223-4:** an expanded-but-fitting population gains no phantom scroll (`maxScrollExtent == 0`) → **TC-223-04**.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot the tree: `git status --short`.
2. Add RED tests TC-223-01/02/03/05a/05b (fail for the documented reasons) + TC-223-04/06 (green guards). Run the focused RED commands.
3. **Add** `orbitArcBottomOverhang({required int memberCount, required OrbitGeometryPrefs geometry, required double centerY})` to `orbit_arc_layout.dart`: `final layout = computeOrbitLayout(memberCount: memberCount, geometry: geometry); return max(0, over layout.seats of (seat.dy + max(seat.avatarSize, kOrbitMinTapTarget)/2) − centerY)`. Scans **all** seats (ring-1/ring-2/arc); floors each half-extent to the **48px tap box**. Pure; independent of the top overhang (it cancels). **Do NOT modify `orbitArcOverhang`.**
4. In `orbital_visualization.dart:136-145`, add `final bottomOverhang = overflowExpanded ? orbitArcBottomOverhang(memberCount: items.length, geometry: geometry, centerY: _center) : 0.0;` and `final boxHeight = _size + overhang + bottomOverhang;` — grows the `SizedBox`/`Stack` **downward**, so the bottom node's tap box enters the hit gate and the host scroll content grows. Leave `cx = _center`, `cy = _center + overhang` untouched. Stop-if: any change forces `cy`/overhang/anchors to move → replan.
5. In `_compensateScrollForOverhang` (`:509-524`), **delete the line-510 knob-enum guard**. Compensation then fires for **any** knob whose overhang `delta` is non-zero (the existing `if (delta == 0) return;` at `:513` and the short-stack `maxScrollExtent <= 0` guard at `:519` stay). This covers spacingScale/avatarScale/maxPerArc via one branch (no per-knob clause to leave untested); `avatarScale`'s ~6.8px top-overhang swing rides the same path (covered by construction). Keep it the single scroll writer.
6. Rerun direct GREEN (01/02/03/05a/05b pass; 04/06 stay green) → preservation sentinels → named gates.
7. `flutter analyze` (0 new), `git diff --check`. Then `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (app-owned code changed).

## Risks And Edge Cases
- **Regressing handle seating / top overhang** (highest risk) → pinned by TC-223-06 (sp=1.5, perturbed regime) + preserved TC-198-71/72/F-02/F-27; mitigated by "grow `boxHeight` below `cy` only."
- **Over-growth (phantom scroll)** → TC-223-04.
- **Bottom-most seat identity is arcWrap-dependent** (arc, not ring-2, at high arcWrap) → tests scan ALL `orbit-node-*` for the max-bottom node; helper scans all seats; TC-223-05 locks it.
- **Short expanded surface (`boxHeight < viewport`)**: downward growth `p` shifts the centered canvas up by `p/2` (static reposition, not a jump; bounded; sp=1.0 ⇒ p=0). Acknowledged, not a regression (Center already repositions with geometry).
- **Spacing-shrink at the bottom scroll edge** → acknowledged residual (INV-223-2); not claimed planted.

## Device/Relay Proof Profile
**host-only for closure.** Justification: a pure, deterministic Flutter **hit-test + scroll layout** defect — no OS boundary, network, crypto, multi-device, or schema. The closure gate is the **real interaction** widget test (`tester.tap` reaches the friend) on the real production widget, plus the pure-domain seat-scan test. No `/sims` scenario / `*_proof_test.dart` applies; `check_reliability_simulation_discovery.sh` gets no new row. (Optional non-gating: on-device eyeball at sp=1.5/arcWrap=2.5 with ~50 friends.)

## Acceptance Gates  (literal — copy/paste; capture baseline counts first)
```bash
# 0. Baseline (record counts BEFORE edits)
./scripts/run_test_gates.sh groups                 # record: NNNN/NNNN pass (baseline)
./scripts/run_host_test_gates.sh feature-host-all  # record: NNNN/NNNN pass (baseline)

# 1. RED (before production edits) — must FAIL for the documented reason
flutter test test/features/orbit/domain/orbit_arc_layout_test.dart --plain-name 'TC-223-01'
flutter test test/features/orbit/domain/orbit_arc_layout_test.dart --plain-name 'TC-223-05a'
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart --plain-name 'TC-223-02'
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart --plain-name 'TC-223-03'
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart --plain-name 'TC-223-05b'
# Guards GREEN on HEAD (confirm they pass now):
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart --plain-name 'TC-223-04'
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart --plain-name 'TC-223-06'

# 2. Direct GREEN (after fix) — all pass
flutter test test/features/orbit/domain/orbit_arc_layout_test.dart
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart

# 3. Preservation sentinels (must stay green — 198-series handle/scroll invariants)
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart --plain-name 'TC-198-71'
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart --plain-name 'TC-198-72'
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart --plain-name 'TC-198F-02'
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart --plain-name 'TC-198F-27'

# 4. Named gate(s) (expect == baseline + new orbit tests, all pass)
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# 5. Hygiene
flutter analyze            # 0 new issues
git diff --check
```
(No migration gate — no `DB v##`. No `/sims` gate — host-only closure.)

## Known-Failure Interpretation
- **Expected RED:** TC-223-01, TC-223-05a (helper absent), TC-223-02, TC-223-05b (bottom node untappable), TC-223-03 (drift ≫ 8px) — before the fix only.
- **Pre-existing dirty:** the tree already carries unrelated modified files (graphify-arch regen, orbit light-bg reskin WIP, `feed_wired.dart`, `orbit_screen.dart`, etc.). Snapshot with `git status --short`; do not revert.
- **Environment blocker (NOT product):** none expected (host tier).
- **Scope drift (BLOCKING):** any failure in a preserved 198-series handle/anchor test, any diff touching `orbitArcOverhang`'s return / `cy` / handle anchors, or a long-press / horizontal-spill change.

## Done Criteria
- [x] RED added first (TC-223-01/02/03/05a/05b fail for the documented reason; TC-223-04/06 green).
- [x] Mutation-verified (each fix has a named re-red revert — §RED catalog).
- [x] Direct GREEN + preservation sentinels (TC-198-71/72/**F-02**/F-27) + `groups` gate pass.
- [x] No `DB v##` → no migration test required.
- [x] Host-only closure justified; PROD-CRITICAL leg is a real `tester.tap` (TC-223-02), not a geometry inequality.
- [x] Every new test auto-registers (feature-host-all glob; widget file pinned `run_test_gates.sh:274`) and is verified present in a gate run.
- [x] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations. Repo-wide `flutter analyze` still fails on a pre-existing analyzer backlog; focused analyze on all touched orbit files is clean.
- [x] `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` run after the code change.

## Scope Guard (hard "Do not")
- Do **not** change `cy = _center + overhang`, the top-overhang (`orbitArcOverhang`'s return), or any geometry-handle anchor. **Growing `boxHeight` DOWNWARD by the bottom overhang is required and is anchor-safe.**
- Do **not** re-introduce a host-`Column` spacer (moves the node into view but leaves its center outside the hit gate — does not fix tappability).
- Do **not** add a long-press re-open / auto-scroll-handles affordance (refuted).
- Do **not** touch horizontal-spill / arc pinch geometry.
- Do **not** grow `boxHeight` unconditionally (must be overflow-gated + poke-sized — TC-223-04).

## Accepted Differences / Intentionally Out Of Scope
- Long-press re-open friction on a dense expanded orbit: soft, not a break (refuted).
- Horizontal spill on narrow (<412pt) phones: by-design bezel pinch.
- Spacing-shrink planted-ness at the bottom scroll edge: acknowledged residual (INV-223-2); steppers are the recovery.

## Dependency Impact
- None. Self-contained orbit-surface layout fix; the new `orbitArcBottomOverhang` helper is additive.

## Reviewer Findings
Sufficiency checklist: spec-case totality ✔ (6 IDs → 7 rows); every INV has a test ✔; every fix mutation-verified ✔ (boxHeight edit → TC-223-02; tap-box floor → TC-223-01; knob-enum removal → TC-223-03; all-seats scan → TC-223-05); no vacuous coverage ✔ (TC-223-02 asserts scroll>0 AND tap-does-not-reach discriminator; PROD-CRITICAL leg is a real tap); migration — N/A ✔; boundaries — N/A host-only, justified ✔; preservation sentinels named with cmds (incl. TC-198F-02) ✔; literal gates ✔; harness-registration per test ✔; known-failure interpretation ✔; dirty-tree snapshot planned ✔; refuted findings recorded (long-press, horizontal spill, Center up-shift) ✔. Matrix gate: zero empty cells ✔. Blind-spot sweep: four addressed ✔. **Fix-list disposition:** §A/§B/§C/§D fully applied; §E1/§E2 applied; §E3 resolved by removing the knob-enum guard (one delta-gated branch, mutation-locked by TC-223-03 — stronger than drop-or-test); §F applied.

## Arbiter Decision
Structural blockers: none. Deferred details: exact `orbitArcBottomOverhang` signature + optional Δbottom compensation left to execution (constrained by INV-223-3). Accepted differences: long-press friction, horizontal spill, sp-shrink bottom edge. Verdict: **implementation-ready**, host-only closure.

## Final Execution Verdict
Verdict: complete / accepted-with-notes | Files changed: `lib/features/orbit/domain/orbit_arc_layout.dart`, `lib/features/orbit/presentation/widgets/orbital_visualization.dart`, `lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart`, `test/features/orbit/domain/orbit_arc_layout_test.dart`, `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart`, this plan file, and required graphify outputs | Tests run (+counts): RED focused commands as recorded; domain PASS `+19`; orbit sculpt widget PASS `+73`; preservation sentinels PASS; `groups` PASS `+1176`; `feature-host-all` exited 0; `git diff --check` PASS; focused analyzer on touched orbit files PASS | Blocking: none for this orbit patch; repo-wide `flutter analyze` still exits 1 on 1625 pre-existing issues outside scope | QA verdict: pass-with-notes | Non-blocking follow-ups (owner): formatter churn makes the touched Dart diffs larger; plan file remains untracked because it was untracked on handoff.
