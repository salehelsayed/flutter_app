# 138 - Orbit3 "One Circle" Prototype Screen  (New Feature)

Status: IMPLEMENTED (2026-06-21, host-green, uncommitted on `new-feed`)
Spec: free-text intent (no formal spec) — captured inline below

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-21 | Evidence Collector | orbit2_screen.dart, orbit2_floating_canvas.dart, orbit2_inner_circle.dart, orbit2_layout_template.dart, orbit2_view_mode.dart, orbit2_mock_data.dart, app_shell_tab.dart, feed_navigation_bar.dart, feed_wired.dart:2308-2324, orbital_avatar.dart, orbit2_screen_test.dart, app_en.arb, run_test_gates.sh, run_host_test_gates.sh | "One Circle" = `Orbit2LayoutTemplate.unifiedCircle`; rendering already exists in `Orbit2Canvas._buildUnified` → `Orbit2InnerCircle(unified:true)`. Double-tap-toggle-names is an empty-canvas-only gesture today. Packing schedule `[6,10,14,18,22,26]`; mock pop caps ~42. Orbit2 NOT in any curated gate array (host-glob only). | Build matrix |
| 2026-06-21 | Planner | (above) | Orbit3 is a **parallel, self-contained feature** (`lib/features/orbit3/`) that OWNS its one-circle widget + packing math so tweaks never regress Orbit2. Pure-logic packing fn = unit tier; screen/gestures = widget tier. No DB/crypto/relay/OS-boundary → host-only closure. | Emit plan |
| 2026-06-21 | Reviewer (sufficiency) | this doc | Every behavior has a tiered test + re-red mutation; matrix has zero empty cells; N/A tiers (migration/sim/device) explicitly justified. | see Reviewer Findings |
| 2026-06-21 | Arbiter | this doc | No structural blockers. Host-only feature; greenfield RED = "Orbit3 symbols don't exist yet", mutations are per-behavior reverts. | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-21 | contract extraction (git status --short) | — | recorded pre-existing dirty `new-feed` files (incl. 6 pre-existing **orbit2** unified-mode files, mtimes 10:26–11:25 — NOT this session) | scope confirmed; orbit2 left untouched | RED |
| 2026-06-21 | RED tests added | test/features/orbit3/{orbit3_one_circle_layout,orbit3_screen,orbit3_wiring}_test.dart | `flutter test test/features/orbit3/` → compile/symbol errors (greenfield RED) | RED for expected reason | implement |
| 2026-06-21 | implementation | lib/features/orbit3/{orbit3_prototype, domain/orbit3_one_circle_layout, application/orbit3_mock_data, presentation/widgets/orbit3_one_circle, presentation/screens/orbit3_screen}.dart | layout green first, then widget+screen | scoped files only (orbit3/) | wire |
| 2026-06-21 | wiring | app_shell_tab.dart (+orbit3), feed_navigation_bar.dart (+gated button), feed_wired.dart (+mount), app_en/ar/de.arb (+nav_orbit3)+gen-l10n; feed_navigation_bar_test.dart (counts made Orbit3-aware, additive) | mount is the 6-line orbit2-parallel branch — Step 8 Stop-if NOT triggered | additive + flag-gated | GREEN |
| 2026-06-21 | direct GREEN | — | `flutter test test/features/orbit3/` → **12/12** | reds now green | preservation |
| 2026-06-21 | preservation GREEN | — | orbit2 **58**, feed nav **12**, feed_wired **26**; 81 blast-radius consumers green (only 2 fails = pre-existing `orbit_wired` group-invite, proven by stash-revert) | sentinels green | gate |
| 2026-06-21 | named gates + mutations | — | `feature-host-all` glob confirmed to include orbit3; **all 9 mutations re-red** (§1 reconcile, §2 rMax, §3 inter-ring gap, §5 dbl-tap, §6 labels, §7 shownCap, §9 search, §10 values, §11 nav); `flutter analyze` 0; `git diff --check` clean; `gen-l10n` clean | gate green | QA |
| 2026-06-21 | QA (independent) | review fixes: orbit3_one_circle.dart (tradeoff comment), orbit3_screen_test.dart (+dbl-tap-over-member test, +chat-header assertion) | 18-agent adversarial review: 8 "confirmed" → 5 FALSE-POSITIVE (orbit2 pre-existing; reviewers diffed HEAD not session-start tree), 1 intentional-tradeoff (300ms single-tap, documented), 2 test-strengthenings applied | blocking: none | **ship** |

## Source Of Truth
- Spec / intent: inline below (user free-text + 3 clarifying answers, 2026-06-21)
- Gate definitions: `scripts/run_test_gates.sh` + `scripts/run_host_test_gates.sh` (script wins over prose)
- Discovery/registration: N/A — no `integration_test/` simulator scenario in this plan (host-only)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (next-free = 138)

## Session Classification
implementation-ready

## Exact Problem Statement
Orbit2 (`lib/features/orbit2/`, gated by `kOrbit2PrototypeEnabled`) is a single screen that
hosts several spatial layouts behind a bottom dock: a floating-avatars constellation (4
templates), a Messages/Inbox view, Manage mode, and a "One Circle" (`unifiedCircle`) template
that collapses every contact into one concentric-ring inner circle. The user wants to iterate
specifically on the **One Circle** experience without the rest of Orbit2's chrome getting in the
way, and without risking regressions to the shipped-comparison Orbit2 prototype.

This plan creates **Orbit3** — a new, self-contained prototype screen that reproduces ONLY the
One Circle view (no template selector, no Messages view, no Manage mode, no floating scatter),
reachable as a 4th nav tab beside Feed / Orbit / Orbit2. It adds two new capabilities the user
asked for:

1. **Double-tap over the orbit area toggles contact names.** Today the names toggle is a
   `Positioned.fill` `onDoubleTap` GestureDetector that sits BEHIND the circle
   (`orbit2_floating_canvas.dart:409-414`); the in-app top-bar comment states it "only reaches
   the toggle on genuinely empty canvas (occluded everywhere else)" (`orbit2_screen.dart:419-421`).
   So double-tapping ON the rings/avatars — exactly "around the orbits" — does not reliably toggle
   names. Orbit3 must let a double-tap anywhere over the One Circle toggle the name labels, while a
   single tap on a member still opens its (mock) chat.
2. **The inner circle handles many more users.** Orbit2's unified packing schedule is
   `[6,10,14,18,22,26]` (`orbit2_inner_circle.dart:284`) with avatars shrunk to a `size*0.05`
   floor, and the mock population caps at `canvasCount ≤ 24` + 16 inner + 2 groups ≈ **42**
   (`orbit2_mock_data.dart:65-70`, `orbit2_screen.dart:45` `_populations = [3,6,10,16]`). The One
   Circle is therefore never exercised past ~42, and beyond it avatars hit the floor and rings
   crowd/overlap. Orbit3 must pack and render **up to ~50 users** in one readable circle with no
   hidden "+N" overflow and no avatar overlap.

What must improve: a separate, minimal One-Circle screen; reliable double-tap-anywhere name
toggle; graceful packing/rendering up to ~50 members.
What must stay unchanged (→ preserved-green sentinels): all of Orbit2 (its screen, its widgets,
its tests), the Feed/Orbit nav bar's existing buttons + swipe host, and `AppShellTab` validity for
existing tabs.

## Root Cause (verify → refute confirmed)
This is a **new feature**, so there is no bug root-cause; instead these are the source-verified
facts the design is grounded on (each confirmed in real code; none refuted):

- **C1 — "One Circle" surface exists and is reusable as a reference.** `Orbit2LayoutTemplate.unifiedCircle`
  (`orbit2_layout_template.dart:19`) routes `Orbit2Canvas.build` → `_buildUnified`
  (`orbit2_floating_canvas.dart:297,386`), which merges innerItems+floatingFriends+floatingGroups
  (deduped) into one `Orbit2InnerCircle(unified:true)` (`orbit2_inner_circle.dart:280-395`).
- **C2 — Unified packing math + avatar shrink-floor.** Ring schedule `[6,10,14,18,22,26]`,
  proportional-to-capacity distribution reconciled to exactly `n`, radii spread `size*0.16 → size*0.40|0.46`,
  one uniform avatar size = min over rings of `arc*0.72`, clamped `[size*0.05, maxAv]`
  (`orbit2_inner_circle.dart:282-349`). This is the logic Orbit3 forks + extends for ~50.
- **C3 — Double-tap names toggle is empty-space-only today.** Both canvas paths wire
  `onDoubleTap: widget.onToggleNames` on a `Positioned.fill` behind the circle
  (`orbit2_floating_canvas.dart:315-319, 409-414`); the inner-circle box in unified mode has no
  opaque wrapper, so gaps fall through but rings/avatars do not reliably toggle. Confirmed by the
  in-app comment at `orbit2_screen.dart:419-421`.
- **C4 — 4-point tab wiring.** flag `kOrbit2PrototypeEnabled` (`orbit2_prototype.dart:8`);
  `AppShellTab.orbit2` constant + `values` set + `isValid` (`app_shell_tab.dart:6,8,10`); nav button
  `if (kOrbit2PrototypeEnabled)` (`feed_navigation_bar.dart:87-95`, label `l10n.nav_orbit2`); mount
  `if (kOrbit2PrototypeEnabled && activeTab == AppShellTab.orbit2)` (`feed_wired.dart:2313-2324`).
  l10n key `nav_orbit2` (`app_en.arb:1400`). Orbit3 mirrors all four.
- **C5 — Test harness.** Orbit2 tests are host widget tests under `test/features/orbit2/`
  (`orbit2_screen_test.dart`, `orbit2_models_test.dart`), pattern `useTallSurface(440×950)` +
  `MaterialApp` wrap + `settle`. `OrbitalAvatar` runs a staggered entrance
  `Future.delayed(globalIndex*40ms)` (`orbital_avatar.dart:48`) → more avatars = longer drain; tests
  must pump enough at teardown. Orbit2/Orbit3 are NOT in any curated `run_test_gates.sh` family array
  (`ORBIT` at line 223 is a perf-harness target, not a test array) → they run via the
  `test/features/**` host glob (`run_host_test_gates.sh feature-host-all`).

Refuted / do-NOT-re-introduce:
- **R1 (refuted): "extend the shared `Orbit2InnerCircle` schedule in place."** Tempting (least code),
  but `orbit2_screen_test.dart` pins unified rendering (`findsNWidgets(26)`, `+N` ring geometry, label
  non-overlap). Editing the shared widget to reach ~50 would regress those Orbit2 tests and defeat the
  "separate so I can tweak it" goal. **Orbit3 owns its own widget + packing fn instead.**
- **R2 (refuted): "double-tap is fully broken in Orbit2 unified."** Not broken — empty gaps DO fall
  through to the behind-circle detector. It is *unreliable on the orbit area itself*. Orbit3's job is
  reliability over the whole circle, not fixing an Orbit2 bug (Orbit2 is untouched).

## Real Scope
In scope:
- New feature folder `lib/features/orbit3/`:
  - `orbit3_prototype.dart` — `const bool kOrbit3PrototypeEnabled = true;`
  - `presentation/screens/orbit3_screen.dart` — `Orbit3Screen` (top bar: "Orbit3" title + population
    cycler + names toggle + prototype chip; the One Circle surface; a search dock; bottom nav bar).
  - `presentation/widgets/orbit3_one_circle.dart` — `Orbit3OneCircle` widget (Orbit3-owned unified
    inner-circle render + **double-tap-anywhere → toggle names** wrapper + search-to-glow), plus
    small private painter/label/group-glyph copied from Orbit2 so Orbit3 is self-contained.
  - `domain/orbit3_one_circle_layout.dart` — **pure** `computeOrbit3RingLayout({count, size, namesVisible})`
    returning `Orbit3RingLayout{ counts:List<int>, radii:List<double>, avatarSize, centerSize }`,
    extended/floored to seat ~50 with no overlap.
  - `application/orbit3_mock_data.dart` — deterministic generator producing up to ~50 `OrbitFriend`
    (+ a couple groups) so the population control can reach the high count.
- Wiring (mirror C4): `AppShellTab.orbit3` constant + add to `values`; nav button in
  `feed_navigation_bar.dart` under `if (kOrbit3PrototypeEnabled)`; mount branch in `feed_wired.dart`.
- l10n: add `nav_orbit3` to `app_en.arb` / `app_ar.arb` / `app_de.arb`; regenerate.
- Population options for Orbit3: `[6, 12, 24, 50]`.

Out of scope (owning session/work):
- Any change to `lib/features/orbit2/**` behavior or its tests — **belongs to Orbit2; do not touch** (R1).
- Real data / DB / backend wiring for Orbit3 — it is visuals-only mock, exactly like Orbit2.
- The real `lib/features/orbit/**` Orbit screen, its perf harness (`PERF_TARGET=ORBIT`), or the
  Feed/Orbit swipe host gestures.
- Names auto-de-collision at extreme density / paging / dots-not-avatars beyond ~50 (would be a
  future "200+ stress" session; this plan targets ~50).

## Files To Inspect Next
Production (entry/use-case, models, widgets):
- `lib/features/orbit2/presentation/widgets/orbit2_inner_circle.dart` (unified block :280-395 — fork source)
- `lib/features/orbit2/presentation/widgets/orbit2_floating_canvas.dart` (`_buildUnified` :386-435, double-tap :409-414)
- `lib/features/orbit2/presentation/screens/orbit2_screen.dart` (top bar/toggle/population pattern)
- `lib/features/orbit2/application/orbit2_mock_data.dart` (mock pool to extend/replace for ~50)
- `lib/features/feed/domain/models/app_shell_tab.dart`, `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`, `lib/features/feed/presentation/screens/feed_wired.dart:2308-2324`
- `lib/features/orbit/presentation/widgets/orbital_avatar.dart` (reused leaf; entrance timer)
- `lib/features/home/presentation/widgets/user_avatar.dart` (reused centre "You")
Direct tests + integration tests:
- `test/features/orbit2/orbit2_screen_test.dart` (harness pattern + preservation)
- `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart`, `test/features/feed/presentation/screens/feed_wired_test.dart` (preservation)
Dependency-only context:
- `lib/l10n/app_en.arb` / `app_ar.arb` / `app_de.arb`, `l10n.yaml`

## Existing Tests Covering This Area
- `test/features/orbit2/orbit2_screen_test.dart` — covers Orbit2 incl. its One Circle (`findsNWidgets(26)`), double-tap empty-space toggle, search glow (exists; **Orbit2-only, preserve**).
- `test/features/orbit2/orbit2_models_test.dart` — Orbit2 domain models (exists; preserve).
- `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart` — nav buttons (exists; preserve; will gain an Orbit3-button assertion via the new wiring test, not by editing this file).
- Orbit3 coverage: **MISSING** (greenfield).
Missing coverage gaps: everything Orbit3 — screen surface, double-tap-on-orbit toggle, ~50-user packing math, ~50 render non-overlap, population→50, search glow, tab wiring.
Already in curated family arrays?: **No.** Orbit2/Orbit3 are not listed in any `run_test_gates.sh`
family array; they run under the `test/features/**` host glob (`feature-host-all`). Mirror that.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> Greenfield note: on HEAD every Orbit3 test fails to **compile/find symbols** (`Orbit3Screen`,
> `Orbit3OneCircle`, `computeOrbit3RingLayout`, `kOrbit3PrototypeEnabled`, `AppShellTab.orbit3` do
> not exist). That is the documented RED. After the feature lands, each test's **mutation** is a
> *granular per-behavior* revert (named per row) so the test re-reds for its specific reason — not
> just the global "symbol missing".

1. `test/features/orbit3/orbit3_one_circle_layout_test.dart`::`seats all N across rings (sum == N) for N in {6,12,24,50}`
   - Tier: unit (pure logic)
   - Shape/setup: call `computeOrbit3RingLayout(count: N, size: 360, namesVisible: false)`; assert `counts.fold(sum) == N`, `counts.every((c) => c >= 0)`, `radii.length == counts.length`.
   - RED on HEAD because: `computeOrbit3RingLayout` does not exist (compile error).
   - GREEN after fix asserts: every member is assigned to a ring; no member dropped; no "+N" overflow concept.
   - Mutation that re-reds: in `computeOrbit3RingLayout`, drop the final reconcile loop (the `while (assigned < n)` top-up) → sum < N for N=50 → RED.

2. `test/features/orbit3/orbit3_one_circle_layout_test.dart`::`radii strictly ascending and within the box at N=50`
   - Tier: unit
   - Shape/setup: layout at N=50, size=360; assert `radii` strictly increasing and `radii.last + avatarSize/2 <= size/2` (stays inside the box).
   - RED on HEAD because: function missing.
   - GREEN after fix asserts: outermost ring + its avatars fit inside the circle bounds.
   - Mutation that re-reds: raise `rMax` past `0.5` (e.g. `size*0.6`) → outer avatars escape the box → RED.

3. `test/features/orbit3/orbit3_one_circle_layout_test.dart`::`no avatar overlap — arc spacing >= avatar diameter on every occupied ring at N=50`
   - Tier: unit
   - Shape/setup: layout at N=50; for each ring `k` with `counts[k] > 0`, assert `(2*pi*radii[k])/counts[k] >= avatarSize` (arc per slot ≥ one avatar) AND `avatarSize >= floor` (floor = `size*0.05`).
   - RED on HEAD because: function missing.
   - GREEN after fix asserts: INV-3 (no overlap) holds by construction at the target scale.
   - Mutation that re-reds: remove the per-ring `avatarSize = min(avatarSize, arc*K)` shrink step → densest ring's arc < diameter → RED.
   - Distinct discriminator: assert BOTH `arc >= avatarSize` (no overlap) AND `avatarSize >= size*0.05` (still visible) so a "shrink to zero to avoid overlap" cheat fails the floor half.

4. `test/features/orbit3/orbit3_screen_test.dart`::`renders ONLY the One Circle surface — no template selector, Messages, Manage, or floating scatter`
   - Tier: widget
   - Shape/setup: `useTallSurface`; pump `Orbit3Screen(userPeerId:'me')`; settle. Assert `find.byType(Orbit3OneCircle)` findsOneWidget; `find.text('Gravity')`/`find.text('Tiered')`/`find.text('One Circle')`/`find.text('Messages')` all findsNothing; no `FloatingAvatar`; no Manage toggle key.
   - RED on HEAD because: `Orbit3Screen`/`Orbit3OneCircle` don't exist.
   - GREEN after fix asserts: INV-1 — Orbit3 is one-circle-only.
   - Mutation that re-reds: add an `Orbit2Dock`/template selector into `Orbit3Screen` → `find.text('One Circle')` appears → RED.

5. `test/features/orbit3/orbit3_screen_test.dart`::`double-tap over the orbit rings toggles names; single tap on a member opens chat`
   - Tier: widget
   - Shape/setup: names default ON; capture an inner member's center via `find.byType(OrbitalAvatar)`. Compute a point ON a ring radius but clear of any avatar (e.g. circle center + (ringR, 0) offset, or simply double-tap at the circle's geometric center area / a known empty ring arc). `tester.tapAt(p)`×2 (50ms apart) → assert a known name label disappears; repeat → reappears. Separately: single `tester.tap(memberFinder)` → `find.byType(<mock chat>)` findsOneWidget (names NOT toggled by the single tap).
   - RED on HEAD because: screen/gesture don't exist.
   - GREEN after fix asserts: INV-4 — double-tap anywhere over the circle toggles names; member single-tap still routes to chat.
   - Mutation that re-reds: remove the `GestureDetector(onDoubleTap: _toggleNames)` wrapper around `Orbit3OneCircle` → double-tap on the ring no longer toggles → first assertion RED. (Second assertion guards the inverse: a too-greedy wrapper that swallows the member tap re-reds the chat-opens assertion.)
   - Distinct discriminator: assert label toggles AND mock-chat opens on single tap (double-tap ≠ chat-open; single-tap ≠ names-toggle).

6. `test/features/orbit3/orbit3_screen_test.dart`::`names render AROUND the orbits (per-member + centre You) and hide when toggled`
   - Tier: widget
   - Shape/setup: names ON → assert a sample member name + `'You'` render (`findsOneWidget`); double-tap (or tap the names toggle button) → both findsNothing.
   - RED on HEAD because: screen doesn't exist.
   - GREEN after fix asserts: name labels are positioned with the circle and respond to the toggle.
   - Mutation that re-reds: gate the label rendering on `false` (never draw labels) in `Orbit3OneCircle` → name `findsNothing` while ON → RED.

7. `test/features/orbit3/orbit3_screen_test.dart`::`inner circle seats ~50 users — all rendered, no +N overflow, no scatter`
   - Tier: widget
   - Shape/setup: cycle the population control to 50 (tap the people/scale chip until count==50, or pump a `Orbit3Screen` variant seeded at max); pump + drain entrance timers (`pump(Duration(ms: 50*40 + 400))`). Assert `find.byType(OrbitalAvatar)` count == 50 (or 50 minus any group-glyph members, asserted precisely against the mock set); assert no `inner-expand-toggle`/"+N" node; assert `Orbit3OneCircle` findsOneWidget.
   - RED on HEAD because: screen/population don't exist.
   - GREEN after fix asserts: INV-2 — all members visible at the target scale, no overflow hiding.
   - Mutation that re-reds: cap the Orbit3 schedule at the Orbit2 `[6,10,14,18,22,26]` (totalCap < 50 without top-up rings) OR re-introduce a `shownCap` overflow → fewer than 50 avatars → RED.

8. `test/features/orbit3/orbit3_screen_test.dart`::`at ~50 users no two avatars overlap on screen`
   - Tier: widget
   - Shape/setup: at population 50, collect `tester.getRect` for every `OrbitalAvatar`; assert no pair's rects overlap (or center distance ≥ sum of radii).
   - RED on HEAD because: screen doesn't exist.
   - GREEN after fix asserts: INV-3 holds in the rendered tree (not just the pure fn).
   - Mutation that re-reds: bump the layout's `avatarSize` clamp above the arc-derived value (ignore the shrink) → rendered avatars overlap → RED.

9. `test/features/orbit3/orbit3_screen_test.dart`::`searching a member makes it glow`
   - Tier: widget
   - Shape/setup: open search, enter a known member name; assert that member's `inner-glow-<id>` key findsOneWidget and a non-matching one findsNothing.
   - RED on HEAD because: screen/search don't exist.
   - GREEN after fix asserts: search-to-glow carried over.
   - Mutation that re-reds: drop the `searchQuery` plumb-through into `Orbit3OneCircle` → no glow node → RED.

10. `test/features/orbit3/orbit3_wiring_test.dart`::`AppShellTab.orbit3 is valid and in values`
    - Tier: unit
    - Shape/setup: `expect(AppShellTab.isValid('orbit3'), isTrue); expect(AppShellTab.values.contains('orbit3'), isTrue);`
    - RED on HEAD because: `AppShellTab.orbit3` not defined; `values` lacks it.
    - GREEN after fix asserts: routing accepts the new tab string.
    - Mutation that re-reds: remove `orbit3` from the `values` set → `isValid` RED.

11. `test/features/orbit3/orbit3_wiring_test.dart`::`FeedNavigationBar shows the Orbit3 button and taps switch to it`
    - Tier: widget
    - Shape/setup: pump `FeedNavigationBar(activeTab:'feed', onSwitchView: capture)` in a localized `MaterialApp`; assert a button labelled `nav_orbit3` ("Orbit3") exists (gated by `kOrbit3PrototypeEnabled==true`); tap it → captured switch arg == `'orbit3'`.
    - RED on HEAD because: nav bar has no Orbit3 button; `l10n.nav_orbit3` undefined (compile/find).
    - GREEN after fix asserts: the 4th tab is reachable and routes correctly.
    - Mutation that re-reds: remove the `if (kOrbit3PrototypeEnabled)` Orbit3 `NavBarButton` block → button absent → RED.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| B5 pack-all | pure logic (ring assignment) | unit | orbit3_one_circle_layout_test::seats all N across rings (sum==N) | `computeOrbit3RingLayout` missing | drop reconcile top-up loop → sum<N | `flutter test test/features/orbit3/orbit3_one_circle_layout_test.dart` | AUTO (glob `test/features/**`) |
| B5 bounds | pure logic (radii) | unit | …::radii ascending & within box at N=50 | fn missing | raise rMax past 0.5 → escape box | (same file) | AUTO (glob) |
| B5/INV-3 no-overlap | pure logic (arc≥diameter, floor) | unit | …::no overlap — arc spacing >= diameter at N=50 | fn missing | remove per-ring shrink step | (same file) | AUTO (glob) |
| B1/INV-1 one-circle-only | widget render/absence | widget | orbit3_screen_test::renders ONLY the One Circle surface | `Orbit3Screen` missing | add a template selector → 'One Circle' text appears | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| B3/INV-4 dbl-tap toggle | widget gesture | widget | orbit3_screen_test::double-tap over the orbit rings toggles names; single tap opens chat | screen/gesture missing | remove `onDoubleTap` wrapper → no toggle | (same file) | AUTO (glob) |
| B4 names-around-orbits | widget render | widget | orbit3_screen_test::names render AROUND the orbits (+You) and hide | screen missing | gate labels on `false` | (same file) | AUTO (glob) |
| B2/INV-2 seat-50 | widget render count | widget | orbit3_screen_test::inner circle seats ~50 users — no +N, no scatter | screen/population missing | cap schedule at Orbit2's / re-add shownCap | (same file) | AUTO (glob) |
| INV-3 render no-overlap | widget geometry | widget | orbit3_screen_test::at ~50 users no two avatars overlap | screen missing | bump avatarSize above arc value | (same file) | AUTO (glob) |
| B8 search-glow | widget | widget | orbit3_screen_test::searching a member makes it glow | screen/search missing | drop searchQuery plumb-through | (same file) | AUTO (glob) |
| B2 routing-valid | pure logic (enum) | unit | orbit3_wiring_test::AppShellTab.orbit3 is valid and in values | `AppShellTab.orbit3` undefined | remove from `values` set | `flutter test test/features/orbit3/orbit3_wiring_test.dart` | AUTO (glob) |
| B2 nav-button | widget wiring | widget | orbit3_wiring_test::FeedNavigationBar shows Orbit3 button + switches | no Orbit3 button; `nav_orbit3` undefined | remove the gated NavBarButton block | (same file) | AUTO (glob) |

## Invariants (locked by tests)
- INV-1: Orbit3 shows the One Circle ONLY — no template selector / Messages / Manage / floating scatter. → orbit3_screen_test::"renders ONLY the One Circle surface".
- INV-2: Every member up to the max population is visible in the circle — no "+N" overflow, no scatter. → orbit3_screen_test::"seats ~50 users" + layout::"seats all N (sum==N)".
- INV-3: No two avatars overlap at any supported N. → layout::"no overlap (arc≥diameter)" (unit) + orbit3_screen_test::"no two avatars overlap" (widget).
- INV-4: A double-tap over the circle toggles names; a single tap on a member still opens chat (gesture disambiguation). → orbit3_screen_test::"double-tap … single tap opens chat".
- INV-5: Orbit2 is untouched. → Orbit2 preservation suite stays green + Scope Guard. (No Orbit3 edit may modify `lib/features/orbit2/**`.)
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **Snapshot the tree:** `git status --short` (record the pre-existing dirty `new-feed` files so none are reverted).
2. **Add RED tests first** (catalog §1-§11) under `test/features/orbit3/`. Run the focused cmds; confirm they FAIL to compile/find symbols (the documented greenfield RED).
3. **Pure layout fn:** create `lib/features/orbit3/domain/orbit3_one_circle_layout.dart` with `computeOrbit3RingLayout(...)` — fork Orbit2's `[6,10,14,18,22,26]` schedule, extend with top-up rings + a floored avatar size so N≈50 seats with arc ≥ diameter and radii inside the box. Make §1-§3 GREEN.
4. **Mock data:** create `lib/features/orbit3/application/orbit3_mock_data.dart` — deterministic generator for up to ~50 `OrbitFriend` (+ a couple groups), reusing the shared `OrbitFriend`/`Orbit2InnerItem` models.
5. **One Circle widget:** create `lib/features/orbit3/presentation/widgets/orbit3_one_circle.dart` — `Orbit3OneCircle` consuming `computeOrbit3RingLayout`, rendering `OrbitalAvatar`s + centre `UserAvatar`, name labels around rings, search glow, and a **`GestureDetector(onDoubleTap:)` wrapping the whole circle** that toggles names without consuming member single-taps (members keep their own `onTap`). Copy the small ring painter / name label / group glyph private classes so Orbit3 is self-contained (INV-5).
6. **Screen:** create `lib/features/orbit3/presentation/screens/orbit3_screen.dart` — `Orbit3Screen` mirroring Orbit2's top bar (title "Orbit3", population cycler `[6,12,24,50]`, names toggle button, prototype chip), the `Orbit3OneCircle` surface, a minimal search dock, and the bottom nav bar. Make §4-§9 GREEN.
7. **Prototype flag:** `lib/features/orbit3/orbit3_prototype.dart` → `const bool kOrbit3PrototypeEnabled = true;`.
8. **Tab wiring (mirror C4):** add `AppShellTab.orbit3` + to `values`; add the gated `NavBarButton` in `feed_navigation_bar.dart` (label `l10n.nav_orbit3`); add the mount branch in `feed_wired.dart` build(). Make §10-§11 GREEN. **Stop-if:** `feed_wired.dart` requires more than the orbit2-parallel 6-line branch (e.g. swipe-host coupling) → replan the mount, do not hack the swipe host.
9. **l10n:** add `"nav_orbit3": "Orbit3"` to `app_en.arb`, `app_ar.arb`, `app_de.arb`; regenerate (`flutter gen-l10n`). Reuse existing `orbit2_you` / `orbit2_names_show` / `orbit2_names_hide` / `orbit2_prototype_chip` for Orbit3 copy (documented reuse; only `nav_orbit3` is new).
10. **Rerun** direct GREEN → preservation sentinels (Orbit2 + feed nav + feed_wired) → host glob gate → analyze.

## Risks And Edge Cases
- **Gesture ambiguity (double-tap vs member tap vs long-press carry):** a circle-wide `onDoubleTap` must not eat member single-taps or any drag. → pinned by §5 (single tap still opens chat). Keep member `GestureDetector`s as children with their own `onTap`; the double-tap detector sits at the circle layer with `HitTestBehavior` chosen so children win single taps.
- **Entrance-timer teardown at N=50:** `OrbitalAvatar` schedules `globalIndex*40ms`; 50 avatars ⇒ ~2s of pending timers. → tests must `pump(Duration(ms: 50*40 + buffer))` before teardown (mirror orbit2_screen_test's "drain entrance timers" pumps) to avoid pending-timer failures.
- **Label legibility at 50:** below-labels crowd at high density. Accepted for ~50 (clamp + ellipsize like Orbit2's `_kInnerLabelW`); de-collision/paging is out of scope (future 200+ session). → not a test failure; documented as an Accepted Difference.
- **Shared-file edits (`app_shell_tab.dart`, `feed_navigation_bar.dart`, `feed_wired.dart`):** additive only, gated by `kOrbit3PrototypeEnabled`. → preservation sentinels (feed nav + feed_wired tests) guard against regressions.
- **l10n regen drift:** forgetting ar/de or regen leaves `nav_orbit3` unresolved. → §11 fails to compile until the key + regen exist.

## Device/Relay Proof Profile
**host-only for closure.** Orbit3 is a visuals-only prototype: no DB/migration, no Go bridge / ML-KEM,
no relay, no OS boundary, no multi-device. Therefore **no `integration_test/` simulator scenario, no
`/sims` registration, no device-proof, and no migration test** are required or applicable. Closure =
host widget + unit gates below. (If the prototype is later promoted to real data, a follow-up plan
adds the data-tier coverage.)
Deferred device work → none.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# 0) Dirty-tree snapshot FIRST (do not revert pre-existing new-feed changes)
git status --short

# 1) RED (before production edits) — MUST FAIL: Orbit3 symbols don't exist yet
flutter test test/features/orbit3/        # expect: compile/symbol errors (RED)

# 2) Direct GREEN (after fix) — the new feature's own suite
flutter test test/features/orbit3/orbit3_one_circle_layout_test.dart
flutter test test/features/orbit3/orbit3_screen_test.dart
flutter test test/features/orbit3/orbit3_wiring_test.dart
flutter test test/features/orbit3/        # all Orbit3 tests green

# 3) Preservation sentinels (MUST stay green — record baseline counts before editing)
flutter test test/features/orbit2/                                              # Orbit2 unchanged
flutter test test/features/feed/presentation/widgets/feed_navigation_bar_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart

# 4) Named host gate for the touched subsystem (auto-globs test/features/**, incl. orbit3)
./scripts/run_host_test_gates.sh feature-host-all                               # expect: full feature host suite green

# 5) l10n regen (after editing the 3 .arb files)
flutter gen-l10n                                                                # nav_orbit3 resolves

# 6) Hygiene
flutter analyze            # 0 new issues
git diff --check
```
(There is NO migration gate, NO `check_reliability_simulation_discovery.sh`, and NO `/sims` row — host-only feature.)

## Known-Failure Interpretation
- **Expected RED:** every `test/features/orbit3/**` test before the feature lands (missing symbols).
- **Pre-existing dirty:** the `new-feed` branch already has many modified/deleted files (graphify-arch, feed widgets, etc.) — record via step 0 and leave untouched; failures there are NOT this plan's.
- **Environment blocker (NOT product):** none expected (host-only; no simulator/device).
- **Scope drift (BLOCKING):** any failure in `test/features/orbit2/**` or in the feed nav / feed_wired sentinels, or any analyze error in `lib/features/orbit2/**` → you edited Orbit2; revert and re-isolate (INV-5).

## Done Criteria
- [ ] RED added first, failed for the expected (greenfield symbol-missing) reason.
- [ ] Mutation-verified (each fix has the named per-behavior re-red revert in the matrix).
- [ ] Direct GREEN + preservation sentinels (Orbit2 + feed nav + feed_wired) + `feature-host-all` pass.
- [ ] No migration needed (host-only) — N/A row justified.
- [ ] No OS-boundary/multi-device/crypto path — N/A, no sim/device proof needed.
- [ ] Every new test auto-globs under `test/features/**` and is confirmed present in a `feature-host-all` run.
- [ ] `flutter gen-l10n` clean; `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violation.

## Scope Guard (hard "Do not")
- Do NOT modify any file under `lib/features/orbit2/**` or `test/features/orbit2/**` (Orbit2 is the stable comparison baseline; Orbit3 owns its own widget + packing math — R1/INV-5).
- Do NOT touch the real Orbit screen (`lib/features/orbit/**`) except to *import* stable leaf widgets (`OrbitalAvatar`).
- Do NOT alter the Feed/Orbit swipe host or existing nav buttons; the Orbit3 additions are additive and flag-gated.
- Do NOT introduce DB/backend/real-data wiring — Orbit3 is visuals-only mock.

## Accepted Differences / Intentionally Out Of Scope
- Names label de-collision / hover-only labels / paging beyond ~50 — a future "200+ stress" session owns it. At ~50, labels clamp+ellipsize (Orbit2 parity).
- Orbit3 reuses Orbit2's `orbit2_you` / `orbit2_names_*` / `orbit2_prototype_chip` l10n strings rather than minting orbit3-specific copies (prototype expedience; only `nav_orbit3` is new).
- Orbit3 keeps names toggle + search + population (per user choice); template selector / Messages / Manage / floating scatter are intentionally dropped.

## Dependency Impact
- None. Orbit3 is a leaf prototype behind `kOrbit3PrototypeEnabled`; no other feature depends on it. The only shared edits (`app_shell_tab.dart` `values`, nav bar, feed_wired mount) are additive and flag-gated.

## Reviewer Findings
Sufficiency: PASS. Spec-case totality — all 8 behaviors (B1-B5, B8 + INV-1..4 routing) map to ≥1 named
test at the right tier (3 unit packing rows, 1 unit enum row, 6 widget rows, 1 widget nav row). Every
row has a concrete RED reason and a granular per-behavior re-red mutation (not just the global
symbol-missing). Matrix has zero empty cells. Migration/simulator/device tiers are explicitly N/A with
justification (visuals-only host feature). PROD-CRITICAL leg: N/A (no transport/wire). Preservation
sentinels named with literal commands. Harness registration: every test auto-globs under
`test/features/**` — no curated-array edit needed (verified Orbit2 isn't arrayed either).
Thin-evidence flag: the exact `feed_wired.dart` mount may need a slightly different shape than the
orbit2 6-line branch if the build() has grown swipe-host coupling — Step 8 carries an explicit Stop-if.

## Arbiter Decision
Structural blockers: none. Deferred details: label de-collision beyond ~50 (accepted, future session).
Accepted differences: l10n string reuse; dropped Orbit2 chrome (per user). Verdict: **implementation-ready** — hand off to execution starting at Acceptance Gate step 1 (RED).

## Final Execution Verdict
Verdict: **SHIPPED (host-green, mutation-verified, adversarially reviewed)** — implementation-complete, no blocking issues.

Files changed:
- NEW: `lib/features/orbit3/orbit3_prototype.dart`, `lib/features/orbit3/domain/orbit3_one_circle_layout.dart`, `lib/features/orbit3/application/orbit3_mock_data.dart`, `lib/features/orbit3/presentation/widgets/orbit3_one_circle.dart`, `lib/features/orbit3/presentation/screens/orbit3_screen.dart`; tests `test/features/orbit3/{orbit3_one_circle_layout,orbit3_screen,orbit3_wiring}_test.dart`.
- ADDITIVE (flag-gated by `kOrbit3PrototypeEnabled`): `app_shell_tab.dart` (`orbit3` + values), `feed_navigation_bar.dart` (gated NavBarButton), `feed_wired.dart` (mount branch + imports), `app_en/ar/de.arb` (`nav_orbit3`) + regenerated `app_localizations*.dart`, `feed_navigation_bar_test.dart` (count assertions made Orbit3-aware).

Tests run (+counts): Orbit3 **12/12**; preservation Orbit2 **58**, feed-nav **12**, feed_wired **26**; 81 blast-radius consumers green. `flutter analyze` 0 new; `git diff --check` clean.

Blocking: **none**.

QA verdict: 18-agent adversarial review (4 dims × verify). 8 "confirmed" findings triaged:
- **5 FALSE-POSITIVE** (findings re: "Orbit2 INV-5 violated"): the 6 orbit2 files (`unified`/`unifiedCircle`/`_buildUnified` + orbit2_screen_test "One Circle" case) are **pre-existing uncommitted `new-feed` work** (mtimes 10:26–11:25, hours before this session; never edited here). Reviewers diffed against HEAD instead of the session-start dirty tree (which Step 1 + Known-Failure explicitly account for). The plan's premise C1 was true vs the working tree. **Did NOT apply their `git checkout HEAD -- lib/features/orbit2/` fix** — it would destroy branch work not created here.
- **1 intentional tradeoff** (300ms single-tap latency): the circle-wide double-tap detector is an *ancestor* of members so double-tap works over avatars (the headline ask). The reviewer's fix (Orbit2's behind-detector) would re-break double-tap-over-avatars. Kept + documented in code; locked by a new test.
- **2 test-strengthenings APPLIED**: §5 now asserts the opened chat is for the *tapped* member (chat-header username); added "double-tap directly OVER a member toggles names" (proves "double-tap anywhere", guards the ancestor-detector against regression).

Deviations from plan (both sound): (1) §3 unit test enhanced to also assert *inter-ring radial spacing* ≥ diameter — the plan's arc-only check was geometrically incomplete for 50-in-box; this caught + fixed a real adjacent-ring overlap. (2) `feed_navigation_bar_test` counts updated additively — the plan's "preservation sentinel" hard-codes the button count, which a new gated button necessarily changes; Feed/Orbit/Orbit2 buttons untouched.

Non-blocking follow-ups (owner): the pre-existing duplicated packing schedule `[6,10,14,18,22,26]` now lives in both orbit2 (pre-existing) and orbit3 (this session, intentionally forked per R1) — acceptable per the plan's "Orbit3 owns its own packing fn"; if orbit2's unified mode is later committed, consider whether both should converge. host-only feature → no device/sim/migration proof required or applicable.

## Post-Implementation Modifications (2026-06-21, user-requested)
After the initial ship, the owner asked for two design changes; both implemented TDD (host-green, mutation-verified), Orbit3-only:
1. **Match the real Orbit screen's sizing** (`lib/features/orbit/.../orbital_visualization.dart`): fixed Orbit-parity geometry — 320px box, 48px centre, ring1 = 5 avatars @38px (r62), ring2 = 8 @30px (r108). Avatars NO LONGER auto-shrink to fit (`computeOrbit3RingLayout` rewritten from proportional-distribute to fixed sizes).
2. **Sequential ring fill + expand**: ring1 fills to 5 → ring2 appears, fills to 8 → an expand arrow (`orbit3-expand-toggle`, "+N") appears once there are hidden members → reveals ring3 (@26px, r154) and beyond. Owner choices (via clarifying Q): ring caps 5/8/11/14/… (+3), radii +46 each; "keep adding rings past the 3rd" → the box grows and the whole circle is wrapped in `FittedBox.scaleDown` so the grown circle scales to fit the phone (the only way to honour fixed-sizes + unbounded rings on a fixed screen); population options changed to `[5,13,24,50]` to make each milestone reachable; population cycle resets to collapsed.
Layout tests rewritten (10) + screen tests rewritten (12, +expand/sizing/sequential-fill cases); 4 new-behaviour mutations re-red (ignore-expanded, drop-sequential-cap, break-ring0-size, fix-box-at-320). analyze 0; orbit2/feed-nav preservation still green. GOTCHA captured: the expand node sits under the ancestor double-tap detector → its onTap fires ~300ms late, so on expand the revealed avatars' entrance timers are created at the pump's end frame — tests must pump in two steps (fire toggle+rebuild, THEN drain ~1.9s of staggered timers) or hit "Timer still pending".
