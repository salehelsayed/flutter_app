# 212 - Orbit Search Trigger: Visual Upgrade + Bottom-Right Float  (Modification)

Status: executed-closed (2026-07-05, host-green; see Final Execution Verdict)
Spec: free-text intent (no formal spec) — user request 2026-07-05: "I want the simple one — improve the visuals and just move it to the bottom right of the screen", choosing the plain circular trigger over exploration 212's labeled-capsule/nav-fusion/top options. Exhibit: `212-orbit-search-placement-mockups.html`.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-05 | Evidence Collector (workflow `wf_111025fb-150`, 2 ground graphify-explorer agents) | orbit_screen.dart, orbit_search_trigger.dart, inner_circle_interactive_surface.dart, orbit_wired.dart, orbit_search_dock.dart, background_readable_colors.dart, 15 test files, run_test_gates.sh | All 9 seam claims CONFIRMED with file:line; band formula derived; full affected-test census | refute pass |
| 2026-07-05 | Refuters (same workflow, 2 adversarial agents, 10 claims) | + orbit_close_button.dart, l10n arbs, perf harnesses, goldens sweep | Position leg SURVIVES (5/5, with conditions); V3 type-reuse REFUTED; V4 free-semantics REFUTED | plan around refutations |
| 2026-07-05 | Planner | this document | 14 matrix rows, all widget/host tier, host-only closure | sufficiency check |
| 2026-07-05 | Reviewer (sufficiency) | sufficiency-checklist.md vs this plan | all gates pass; blind-spot sweep: 2 rows + 2 justified N/A | — |
| 2026-07-05 | Arbiter | | no structural blockers; coordination note w/ concurrent session 211 recorded | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-05 | contract extraction (git status --short) | — | snapshot matches Known-Failure list; session 211 docs present, NO 211 code in lib/ → no rebase needed | scope confirmed | E1 |
| 2026-07-05 | RED tests added | NEW orbit_search_trigger_placement_test.dart (TC-212-01..05); orbit_wired_test +TC-212-06/07; orbit_search_trigger_test rewrite (TC-212-08/09); orbit_find_pill_ux_test TC-205-01→52 + NEW TC-212-11; orbit_screen_loading_test :519-561→TC-212-12; parity newOrbitKeys pin; pump harness +persistent knobs | block-1 run: exactly 10 REDs, each for its documented reason (01 band, 03 band+size, 04 RTL, 05 height-52, 08 size-44, 09 no-Semantics, 205-01+212-11 size-44, 212-12 bottom 873≠796, parity "en ARB missing key"); TC-212-02 green-by-design; wired TC-212-06/07 sentinel-green on HEAD | RED for expected reason | E2-E5 |
| 2026-07-05 | implementation | E2 orbit_search_trigger.dart (52/24/shadow-outside-ClipOval/Semantics/opaque-hit); E3 orbit_screen.dart (Center rebalance + floated Layer 3b before dock); E4 inner_circle_interactive_surface.dart pill 52/24/border/shadow NO blur; E5 arbs ×3 + gen-l10n + parity reachability/baseline | scoped files only; no orbit_wired.dart controller/driver edits (stop-if never triggered) | scoped files only | E6 |
| 2026-07-05 | direct GREEN | — | direct block (placement+trigger+pill+loading+wired+test/l10n): all green after one TC-212-06 assert correction (see QA row) | reds now green | E7 |
| 2026-07-05 | mutation spot-checks | — | A un-float Layer 3b → TC-212-01/03/04 RED; B pill BackdropFilter → TC-212-11 RED; C drop IgnorePointer → TC-212-06 RED; all reverted, `git diff lib/ | grep MUTATION` = 0 | 3/3 headline mutations re-red | preservation |
| 2026-07-05 | preservation GREEN | — | `flutter test orbit_view_split_test.dart orbit_sculpt_summon_wired_test.dart` → 85/85 | sentinels green | named gates |
| 2026-07-05 | named gates | run_test_gates.sh (+GROUP_TESTS pin for placement test) | `./scripts/run_test_gates.sh groups` → 1139 pass (baseline 1110 + 212 additions); `feed` → 292 pass (=baseline); `flutter test test/l10n/` → 11 pass (integrity 7/7 + parity) | gate green | wide gate + hygiene |
| 2026-07-05 | QA (independent re-check) | orbit_wired_test TC-212-06 asserts corrected | Ground-truth correction: at the floated home the OPEN dock legitimately paints over the corner band (trigger declared before dock, per plan), so its own trailing control receives pass-through taps — the plan's "focus retained after second tap" assert was unsatisfiable-by-design there. Replaced with: fade Opacity==0 + structural IgnorePointer(ignoring)==true (kills the named mutation, verified) + pass-through tap harmless. `flutter analyze` on 212 files: 0 issues (fixed deprecated hasFlag→isSemantics in TC-212-09); `git diff --check` clean | blocking: none | verdict |
| 2026-07-05 | wide gate | — | `feature-host-all`: suites 1-351 → single FAIL = #351 group_conversation_wired_bg_task_test (the documented pre-existing red; script is fail-fast) + resume `--start-at 352 --continue-on-failure` → 288 PASS, 0 FAIL, exit 0. Only allowed red confirmed | gate green (allowed red only) | commit |
| 2026-07-05 | concurrency note | — | Session 211 landed its top-chrome work UNCOMMITTED on the shared tree mid-execution (orbit_screen p2pService/indicator Layer 4b, pump-harness p2pService param, gate-script pins, orbit_wired_test TC-211-34). 212 hunks verified intact; 212 commit staged surgically (HEAD+212-only blobs for the 4 shared files) so no 211 hunks ride along; nothing of theirs reverted | no interference | — |

## Source Of Truth
- Spec / intent: inline above + `212-orbit-search-placement-mockups.html` ("today" exhibit = the complaint; chosen remedy = simple circle, improved, bottom-right)
- Gate definitions: scripts/run_test_gates.sh  (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready

## Exact Problem Statement
The Orbit screen's search entry is a 44×44 icon-only glass circle with two inconsistent homes and the weakest visual presence of any chrome element. On the **all-chats list view** (persistent-nav mode — the only mode production hosts use) it is crammed *inline* into the right slot of the Feed/Orbit nav Row (`orbit_screen.dart:669-692`), riding the nav bar's vertical level instead of owning a corner. On the **rings view**, the collapsed find pill (`inner_circle_interactive_surface.dart:1028-1047`) is a bare borderless circle — the only chrome piece that draws neither border, blur, nor shadow (every sibling does: trigger `orbit_search_trigger.dart:26`, close button `orbit_close_button.dart:18-26`, steppers `:1081`, chips `:1121`).

What must improve:
1. **Position (list view):** the trigger leaves the nav Row and floats at the bottom-right of the screen — `Positioned(right: 16, bottom: _persistentNavBottomOffset(context) + 84)` in screen coordinates, which is *exactly* the rings pill's band (104px physical @ notched, derivation in Root Cause). One search affordance, one bottom-right home, both surfaces.
2. **Visuals (both surfaces):** 44 → **52px** circle, icon 20/22 → **24**, and full glass-chrome vocabulary: trigger keeps blur 12 + border and gains a soft drop shadow + a Semantics label; the rings pill gains border + the same shadow (**no blur** — see Refuted V3) at 52/24.

What must stay unchanged (→ preserved-green sentinels):
- Trigger opens the search dock (list view); find pill expands in place (rings view); expanded find bar geometry (≥56h, full-width, band 40/88/kb-10) untouched.
- `searchTriggerAnimation` reveal choreography: open/close inverse drive (`orbit_wired.dart:1981-1999`), scroll-hide (`:1963-1979`), TC-202-10 animation-identity.
- Standalone mode placement: trigger `bottom:88, right:16`, close button `bottom:36` (`orbit_screen.dart:591-623`).
- Rings view never mounts `OrbitSearchTrigger`; physical-right RTL stance; ≥44pt tap targets; band constants 28/40/88/96/144.

## Root Cause (verify → refute confirmed)
Not a bug — a placement/weight choice being revised. Grounded mechanism (all CONFIRMED, `wf_111025fb-150`):
- **Inline slot:** persistent band = `Positioned(bottom:_persistentNavBottomOffset)` > `Padding(h16)` > `Row[const Spacer (:667), _buildNavigationBar (:668), Expanded>Align(centerRight)>AnimatedBuilder>trigger|SizedBox.shrink (:669-692)]`. Nav centering is purely the flex-1 Spacer/Expanded balance (`:665-666` comment) — extracting the trigger REQUIRES rebalancing (simplest: `Center(child: _buildNavigationBar())`).
- **Band formula (C6):** rings pill screen-space bottom = `safeBottom + 40 + _bandLift` where `_bandLift = max(0, bottomClearance−28)` (`inner_circle_interactive_surface.dart:242,977-979`), `bottomClearance = max(0, _searchDockBottomOffset − safeBottom)` (`orbit_screen.dart:500-506`) ⇒ **`= max(16, safeBottom−14) + 84 = _persistentNavBottomOffset(context) + 84`** (104 @ safeBottom 34; 100 @ 0). Root Stack layers other than Layer 1 sit OUTSIDE the SafeArea (`:566-570` vs `:578-715`), so the floated trigger uses this formula directly.
- **Choreography is placement-agnostic (R3):** two independent controllers in `orbit_wired.dart` (`:436-450`), driven inversely by `_onSearchOpen/_onSearchClose` (`:1981-1999`) plus scroll-hide (`:1963-1979`); the standalone variant ALREADY drives a `Positioned` from the same animation (`:607-620`). Persistent transform set = Opacity + Scale + IgnorePointer(t<0.5) (`:676-685`), no translate.
- **Dock overlap is pre-solved (C9/R2):** dock rests at `bottom:_searchDockBottomOffset` (92 @ sb34) spanning ~[92,190) — it covers the trigger band whenever open, exactly as it already does in standalone; resolved by the kept fade + IgnorePointer, with the trigger layer declared BEFORE the dock in the Stack so the dock paints over it mid-transit.
- **Pill weakness deliberate-looking but not justified (V1):** `glassBorder` exists for both tones (`background_readable_colors.dart:67,:91`); the pill simply never references it; no comment defends the omission.

Refuted / do-NOT-re-introduce:
- **V3 (REFUTED): reusing `OrbitSearchTrigger` for the rings pill.** Flips 4 green locks RED (`orbit_view_split_test.dart:291`, `orbit_screen_loading_test.dart:380`, `feed_swipe_test.dart:896`, `feed_wired_test.dart:1115` — all assert `findsNothing` on rings); shrinks the hit region (deferToChild inside ClipOval vs the pill's opaque 44px square); and a permanently-mounted `BackdropFilter` above the continuously-animating rings canvas re-samples per frame (per-frame saveLayer) on exactly the view the ORBIT perf gates measure (202 repaint-isolation: `orbital_visualization.dart:169,240`). → Pill is restyled **in place**: border + shadow + 52/24, **NO BackdropFilter** (locked by TC-212-11).
- **V4 (REFUTED): "Semantics label is free."** No existing key fits (`orbit_find_pill_semantics` = circle-scoped copy; `orbit_search` = the dock hint, coupling a11y copy to placeholder copy). A correct label costs a new key in en/ar/de + gen-l10n + `newOrbitKeys` pin (`orbit_strings_parity_test.dart:18-52`), enforced by `l10n_integrity_test.dart:10-27`. → Planned explicitly as E5, not assumed free.
- **Ground-note correction:** `orbit_wired_test.dart:693-704` is NOT placement-sensitive (its `find.descendant` is scoped to the trigger itself, not the nav Row).
- **Not-a-defect:** standalone rings-pill band (sb+40 = 74) vs standalone trigger (88) — a pre-existing 14px mismatch on a surface with ZERO production hosts (R5: both `OrbitWired` hosts — `main.dart:4257`, `feed_wired.dart:2522` — are persistent-mode). Accepted, untouched.
- **Chip-strip bump NOT needed (V2 caveat resolved):** collapsed pill and chip strip never coexist — chips require a non-empty query (`_findActive`), which only exists while the pill is OPEN (`_closeFindInternal` clears the controller). The 52px collapsed pill's top (92) vs strip bottom (96) is a dead configuration. Strip constants 96/144 stay untouched; sculpt band tests unaffected.

## Real Scope
In scope: `orbit_search_trigger.dart` restyle (52/24/shadow/Semantics/opaque-hit), `orbit_screen.dart` persistent-band restructure (Center rebalance + new floated Layer 3b), `inner_circle_interactive_surface.dart` collapsed-pill restyle in place (52/24/border/shadow), 1 new l10n key ×3 arbs + gen-l10n + parity pin, test updates/additions listed below.
Out of scope: dock/expanded-bar changes; standalone offsets; scroll-hide thresholds; controller durations/curves; `OrbitCloseButton` (stays 44, `orbit_close_button_test.dart:28`); top chrome (view toggle, connection indicator, ExpandableFab) — **concurrent session 211 owns the top chrome** (`211-orbit-chrome-toggle-glyph-online-indicator-tdd-plan.md`); labeled-capsule / nav-fusion / top-bar options from the 212 exhibit (declined by user).

## Files To Inspect Next
Production: `lib/features/orbit/presentation/widgets/orbit_search_trigger.dart` (:15-36), `lib/features/orbit/presentation/screens/orbit_screen.dart` (:591-696 bands, :479-506 offsets), `lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart` (:1028-1047 collapsed branch), `lib/l10n/app_en.arb`/`app_ar.arb`/`app_de.arb`.
Direct tests: `test/features/orbit/presentation/widgets/orbit_search_trigger_test.dart`, `test/features/orbit/presentation/widgets/orbit_find_pill_ux_test.dart`, `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` (:519-561 REWRITE), NEW `test/features/orbit/presentation/screens/orbit_search_trigger_placement_test.dart`, `test/features/orbit/presentation/screens/orbit_wired_test.dart` (2 appended TCs), `test/l10n/orbit_strings_parity_test.dart`.
Dependency-only context: `orbit_wired.dart` (:436-450, :1963-1999 — read, do not edit), `orbit_search_dock.dart`, `background_readable_colors.dart` (:60-91 tone tokens), `orbit_screen_pump_harness.dart`.

## Existing Tests Covering This Area
- `orbit_screen_loading_test.dart:519-561` locks the INLINE placement (searchRect.left ≥ navRect.right; |ΔcenterDy| < 2) — **asserts the opposite of this plan; rewritten in place** (BREAKS).
- `orbit_search_trigger_test.dart` pins 44×44 (:20-21) + singular-Container/border structure (:47-53) — BREAKS (44 pin; shadow adds a 2nd Container); icon/tap tests survive.
- `orbit_find_pill_ux_test.dart` TC-205-01 (:110) pins pill `Size(44,44)` — BREAKS; TC-205-02/03/04 survive (bottom-anchored / expanded-branch / lens colors).
- SURVIVE (preservation sentinels): `orbit_sculpt_summon_wired_test.dart` (bands 40/88/kb, closeTo on pill.bottom — bottom-anchored, growth is upward; semantics sweep :1511; key-taps), `orbit_wired_test.dart` (:682-705 presence, :1635/:1706 tap-by-type, TC-202-10 :2145-2173 animation identity), `orbit_view_split_test.dart:291`, `feed_wired_test.dart:1066/:1115`, `feed_swipe_test.dart:896/:921`, `orbit_settings_entry_test.dart:397` (key-based), `orbit_search_dock_test.dart`, constructor-plumbing harnesses.
- Sims: `cold_start_message_render_simulator_test.dart:439` and `orbit_performance_harness.dart:509-515` tap the pill BY KEY — survive. **No sim touches the all-chats trigger at all.**
Missing coverage gaps (all filled below): no whole-screen trigger-position lock besides the inline one; no cross-surface band-parity test; no RTL placement test; no trigger Semantics test; no icon-size pin; no shadow/blur assert; no standalone-offset lock; no scroll-hide behavior test.
Already in curated family arrays?: GROUP_TESTS — orbit_wired (:229), orbit_settings_entry (:231), orbit_view_split (:245), orbit_sculpt_summon (:258, pin-only reachable); FEED_TESTS — feed_swipe (:178), feed_wired (:182); OPTIONAL_MANUAL — cold-start sim (:331). `orbit_search_trigger_test`, `orbit_find_pill_ux_test`, `orbit_screen_loading_test` are **auto-glob only** (feature-host-all).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
1. `test/features/orbit/presentation/screens/orbit_search_trigger_placement_test.dart::TC-212-01 persistent all-chats floats the trigger bottom-right in the find-pill band`
   - Tier: widget | Shape: `orbit_screen_pump_harness` persistent pump (activeTab+onSwitchView), allChats view, `searchTriggerAnimation: AlwaysStoppedAnimation(1)`.
   - RED on HEAD: trigger is inline in the nav Row (center-dy ≈ nav center, left of screen edge − 16 − 44 is nav-relative).
   - GREEN asserts: `rect.right == screenW − 16`; `rect.bottom == screenH − (max(16.0, sb−14.0) + 84)` (sb=0 in tests ⇒ bottom edge = H−100); `rect.height == 52`; trigger NOT vertically level with `FeedNavigationBar`.
   - Mutation: revert the floated `Positioned` (put trigger back in the Row) → RED.
2. same file::`TC-212-02 nav pill stays horizontally centered without the trigger slot`
   - Tier: widget | RED on HEAD: runs in the same pump as TC-212-01 (file is RED via 01; this assert alone is green pre+post by design — it exists to catch the rebalance regression).
   - GREEN asserts: `navRect.center.dx == screenW/2 ± 1.0`.
   - Mutation: replace `Center(child:_buildNavigationBar())` with a Row missing the balance (e.g. trailing-only Spacer) → RED.
3. same file::`TC-212-03 rings pill and list trigger share one bottom-right band (INV-212-1)`
   - Tier: widget | Shape: two pumps — allChats (trigger rect) and innerCircle (pill rect via `ValueKey('orbit-find-pill')`).
   - RED on HEAD: trigger inline (band mismatch: nav-level vs pill band; also 44 vs 52).
   - GREEN asserts: identical `rect.bottom` and `rect.right` (both `screenW−16` / band formula); both `Size(52,52)`.
   - Mutation: change floated `bottom:` to any other constant (e.g. +64) → RED.
4. same file::`TC-212-04 RTL keeps the physical bottom-right corner`
   - Tier: widget | Shape: same pump wrapped in `Localizations`/locale `ar` (Directionality rtl).
   - RED on HEAD: placement differs (inline). GREEN asserts: same physical asserts as TC-212-01 under RTL.
   - Mutation: swap `Positioned(right:16)` → `PositionedDirectional(end:16)` (mirrors under RTL) → RED.
5. same file::`TC-212-05 standalone geometry frozen (sentinel)`
   - Tier: widget | Shape: standalone pump (no activeTab/onSwitchView), allChats.
   - RED on HEAD: sentinel — green on HEAD by design EXCEPT `height==52` (RED via size). GREEN asserts: `rect.bottom == H−88`, `rect.right == W−16`, `height == 52`; close button top gap == 8 (close 44 @ bottom:36).
   - Mutation: change standalone `bottom:88` or `right:16` → RED.
6. `test/features/orbit/presentation/screens/orbit_wired_test.dart::TC-212-06 floated trigger is tap-inert while the dock is open`
   - Tier: widget (wired) | Shape: open search via trigger tap; pumpAndSettle; then `tester.tap(find.byType(OrbitSearchTrigger), warnIfMissed:false)`.
   - RED on HEAD: sentinel (property holds inline too) — locks the KEEP clause at the new home.
   - GREEN asserts: dock stays open, focus retained, no second `onSearchOpen` effect; trigger still mounted (faded).
   - Mutation: drop the `IgnorePointer(t<0.5)` from the floated builder → RED.
7. same file::`TC-212-07 scroll-down hides the floated trigger; scroll-up restores it`
   - Tier: widget (wired) | Shape: drag the all-chats list beyond offset 100; settle; then back below 50.
   - RED on HEAD: sentinel (scroll-hide exists today; previously untested — new lock). GREEN asserts: trigger Opacity → 0 after down-scroll (animation reversed), → 1 after up-scroll.
   - Mutation: remove the `AnimatedBuilder(searchTriggerAnimation)` wrapper from the floated layer → RED.
8. `test/features/orbit/presentation/widgets/orbit_search_trigger_test.dart::TC-212-08 trigger renders 52px glass circle with icon 24, border, blur and shadow` (rewrite of the 44px test + additions)
   - Tier: widget | RED on HEAD: size 44, icon 22, no BoxShadow, single Container.
   - GREEN asserts: outer box 52×52 with `boxShadow` non-empty; `BackdropFilter` present; inner decoration `Border.all(glassBorder)` (daylight + dark tone variants, keep :38-54 lens shape via descendant finders); `Icon(Icons.search).size == 24`; corner tap (`tapAt(rect.topLeft + Offset(2,2))`) fires `onSearchTap` (opaque hit square).
   - Mutation: revert E2 (restore 44/22/no-shadow widget) → RED.
9. same file::`TC-212-09 trigger exposes a Semantics button label`
   - Tier: widget | RED on HEAD: no Semantics wrapper exists.
   - GREEN asserts: `find.bySemanticsLabel(en.orbit_search_trigger_semantics)` findsOneWidget; `button: true`.
   - Mutation: remove the Semantics wrapper → RED.
10. `test/l10n/orbit_strings_parity_test.dart::newOrbitKeys += orbit_search_trigger_semantics` (TC-212-10)
    - Tier: unit (l10n) | RED on HEAD: pin the key into `newOrbitKeys` FIRST → test RED until the key lands in en+ar+de arbs and gen-l10n runs (198 two-step convention).
    - GREEN asserts: key present in all three arbs, non-empty; `l10n_integrity_test` 7/7 stays green.
    - Mutation: delete the key from `app_de.arb` → parity RED.
11. `test/features/orbit/presentation/widgets/orbit_find_pill_ux_test.dart::TC-212-11 collapsed pill is a 52px bordered, shadowed glass circle with NO BackdropFilter` (rewrite of TC-205-01 + additions)
    - Tier: widget | RED on HEAD: `Size(44,44)`, borderless, shadowless (the no-blur assert is green on HEAD — it is the INV-212-3 forward lock).
    - GREEN asserts: `Size(52,52)`; decoration `border != null` (glassBorder) and `boxShadow != null`; `Icon size 24`; `find.descendant(of: pill, matching: find.byType(BackdropFilter))` findsNothing.
    - Mutation: revert E4 → size/border asserts RED; wrap the pill in a BackdropFilter → no-blur assert RED.
12. `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart::rewrite of 'persistent nav inlines the search trigger…' (:519-561) → 'persistent nav centers the bar; search floats in the corner band'` (TC-212-12)
    - Tier: widget | RED on HEAD: the old asserts (`searchRect.left >= navRect.right`, ΔcenterDy < 2) hold on HEAD and contradict the new placement — rewritten to the TC-212-01 band asserts + nav-centered assert, RED until E3.
    - Mutation: revert E3 → RED.

Preserved-green sentinels (existing, zero-edit): TC-212-13 rings-view-never-mounts-trigger = `orbit_view_split_test.dart:291` + `orbit_screen_loading_test.dart:380` + `feed_swipe_test.dart:896` + `feed_wired_test.dart:1115` (the V3 guard); TC-212-14 pill band/keyboard/expanded contracts = `orbit_sculpt_summon_wired_test.dart` TC-198F-17/18 + TC-201-03/11 + semantics sweep :1511, `orbit_find_pill_ux_test` TC-205-02/03/04, `orbit_screen_loading_test` TC-201-04 + dock-lift :563-589; choreography = `orbit_wired_test` TC-202-10 + :1635 + :1706; shell path = `feed_wired_test.dart:1035-1087`.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-212-01 float bottom-right | UI placement | widget | orbit_search_trigger_placement_test.dart::TC-212-01 | trigger inline in nav Row | revert E3 floated Positioned | `flutter test test/features/orbit/presentation/screens/orbit_search_trigger_placement_test.dart` | AUTO (glob) + **add to GROUP_TESTS array** |
| TC-212-02 nav stays centered | UI layout | widget | same::TC-212-02 | sentinel in RED file (guards rebalance) | unbalance the Center rebalance | same cmd | same (one file) |
| TC-212-03 one band, both surfaces | cross-surface invariant | widget | same::TC-212-03 | band mismatch on HEAD | change floated `bottom:` constant | same cmd | same |
| TC-212-04 RTL physical right | RTL/UI | widget | same::TC-212-04 | inline placement on HEAD | PositionedDirectional swap | same cmd | same |
| TC-212-05 standalone frozen | preservation lock | widget | same::TC-212-05 | RED via height 52 (offsets sentinel) | alter standalone 88/16 | same cmd | same |
| TC-212-06 dock-open tap-inert | choreography | widget (wired) | orbit_wired_test.dart::TC-212-06 | sentinel (locks KEEP at new home) | drop IgnorePointer in floated builder | `./scripts/run_test_gates.sh groups` | already GROUP_TESTS (:229) |
| TC-212-07 scroll-hide works floated | choreography | widget (wired) | orbit_wired_test.dart::TC-212-07 | sentinel (gap: previously untested) | drop AnimatedBuilder wrapper | `./scripts/run_test_gates.sh groups` | already GROUP_TESTS (:229) |
| TC-212-08 trigger 52/24/border/blur/shadow + opaque hit | widget visual | widget | orbit_search_trigger_test.dart::TC-212-08 | 44/22, no shadow | revert E2 | `flutter test test/features/orbit/presentation/widgets/orbit_search_trigger_test.dart` | AUTO (glob) |
| TC-212-09 trigger Semantics | a11y | widget | orbit_search_trigger_test.dart::TC-212-09 | no Semantics on HEAD | remove Semantics wrapper | same cmd | AUTO (glob) |
| TC-212-10 l10n key ×3 + parity | l10n | unit | orbit_strings_parity_test.dart + l10n_integrity_test.dart | key pinned before arbs exist | delete key from app_de.arb | `flutter test test/l10n/` (expect 7/7 + parity green) | existing test/l10n suite (named gate) |
| TC-212-11 pill 52/24/border/shadow, NO blur | widget visual + perf lock | widget | orbit_find_pill_ux_test.dart::TC-212-11 | 44/20 borderless shadowless | revert E4 / add BackdropFilter | `flutter test test/features/orbit/presentation/widgets/orbit_find_pill_ux_test.dart` | AUTO (glob) |
| TC-212-12 loading-test rewrite | placement lock retarget | widget | orbit_screen_loading_test.dart::rewritten test | old inline asserts contradict plan | revert E3 | `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` | AUTO (glob) |
| TC-212-13 rings never mounts trigger | do-not-re-introduce (V3) | widget | 4 existing locks (view_split:291, loading:380, feed_swipe:896, feed_wired:1115) | n/a — preserved green | mount OrbitSearchTrigger on rings → RED | `./scripts/run_test_gates.sh groups` + `feed` | GROUP_TESTS:245 / FEED_TESTS:178,182 (existing) |
| TC-212-14 pill bands/expanded/semantics preserved | preservation | widget | orbit_sculpt_summon_wired_test.dart + orbit_find_pill_ux TC-205-02/03/04 (existing) | n/a — preserved green | change band constants 40/88 → RED | `./scripts/run_test_gates.sh groups` | GROUP_TESTS:258 (existing pin) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** N/A — pure stateless chrome; no persisted or derived state added. Animation controllers live in `OrbitWired` state and reconstruct on remount; view re-entry behavior already locked by `feed_wired_test.dart:1035-1087` (search reset on re-entry, preserved green).
- **Sibling-surface consistency:** TC-212-03 (one band across both surfaces) + TC-212-09/-10 (Semantics parity — the pill has had a label since 198; the trigger was the unlabeled sibling). Deliberate remaining asymmetry: `OrbitCloseButton` stays 44 (standalone-only surface, zero production hosts) — locked by existing `orbit_close_button_test.dart:28`.
- **Destructive-action side-effects:** N/A — nothing is deleted or cleaned up; the Row slot removal is covered by TC-212-02/-12 (layout, not data).
- **Invariant re-verification under new transitions:** no new state transitions introduced; the two existing transitions that now execute at a new position (dock open/close, scroll-hide) are re-verified there by TC-212-06/-07, and mid-transit paint order is pinned by keeping the trigger layer before the dock layer (E3; regression surfaces as TC-212-06 failure if IgnorePointer/stack order is broken).

## Invariants (locked by tests)
- INV-212-1 one bottom-right home: trigger and pill share `right:16` + band `navBottomOffset+84` → TC-212-03.
- INV-212-2 rings surface never mounts `OrbitSearchTrigger` → TC-212-13 (4 existing locks).
- INV-212-3 collapsed pill contains NO BackdropFilter (perf, 202-class) → TC-212-11.
- INV-212-4 nav pill horizontally centered → TC-212-02 (+ rewritten TC-212-12).
- INV-212-5 standalone geometry frozen (88/36/16) → TC-212-05.
- INV-212-6 physical-right under RTL → TC-212-04.
- INV-212-7 reveal choreography (open/close, scroll-hide, animation identity) preserved → TC-212-06/-07 + existing TC-202-10.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **E1 — RED tests.** Add the placement test file (TC-212-01..05), the two `orbit_wired_test` TCs, rewrite the trigger/pill/loading tests' target asserts, pin the l10n key into `newOrbitKeys`. Run the RED gate block; every listed test must fail for its documented reason (compile-RED is acceptable only for the Semantics/l10n getters, per 198/209 precedent).
2. **E2 — `orbit_search_trigger.dart` restyle.** New structure: `Semantics(button:true, label: l10n.orbit_search_trigger_semantics)` > `GestureDetector(behavior: HitTestBehavior.opaque)` > `Container(52×52, shape: circle, boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 18, offset: Offset(0,6))])` > `ClipOval` > `BackdropFilter(blur 12 — unchanged)` > `Container(shape: circle, color: readableColors.glassSurface, border: Border.all(readableColors.glassBorder))` > `Icon(Icons.search, size: 24, color: iconPrimary)`. Shadow sits OUTSIDE the ClipOval (a clipped shadow is invisible). Neutral black shadow reads on both tones (`background_readable_colors.dart:60-91`).
3. **E3 — `orbit_screen.dart` band restructure.** (a) Persistent Positioned (:656-696): drop the `Spacer` + trailing `Expanded(Align…)` pair, keep `Padding(h16)`, wrap `_buildNavigationBar()` in `Center` — update the :665-666 comment. (b) NEW Layer 3b, gated `if (_showsPersistentNav && viewMode == OrbitViewMode.allChats)`, declared BEFORE the Layer 4 dock (mirror the standalone :602-623 shape): `AnimatedBuilder(searchTriggerAnimation, builder: (_, child) { final t = …; return Positioned(right: 16, bottom: _persistentNavBottomOffset(context) + 84, child: Opacity(t, Transform.scale(scale: 0.985 + 0.015*t, child: IgnorePointer(ignoring: t < 0.5, child: child)))); }, child: OrbitSearchTrigger(onSearchTap: onSearchOpen))`. Keep the persistent transform set (opacity+scale, no translate — Accepted Difference vs standalone's +14 flourish). Standalone block (:602-623) untouched. Stop-if: any `orbit_wired` controller/driver edit looks necessary → replan; the drivers must not change.
4. **E4 — `inner_circle_interactive_surface.dart` collapsed branch (:1036-1045) in place.** Container 52×52, add `border: Border.all(color: colors.glassBorder)` + the same `boxShadow`, icon 24. Semantics/GestureDetector/`ValueKey('orbit-find-pill')`/opaque wrapper byte-identical. NO BackdropFilter (INV-212-3). Band constants untouched.
5. **E5 — l10n.** `orbit_search_trigger_semantics` in `app_en.arb` ("Search chats"), `app_ar.arb` ("البحث في الدردشات"), `app_de.arb` ("Chats durchsuchen"); `flutter gen-l10n`. (Key already pinned in `newOrbitKeys` from E1 — its RED flips green here.)
6. **E6 — direct GREEN.** Run the Direct block; all E1 reds green.
7. **E7 — preservation + named gates + hygiene.** Sentinels, `groups`, `feed`, `test/l10n/`, `feature-host-all`, analyze, diff-check. Register the new placement test in `GROUP_TESTS` (coordinate with session 211's E5, which edits the same array — append after their pin, whatever lands first).

## Risks And Edge Cases
- **Concurrent session 211** edits `orbit_screen.dart` (top chrome Layer 4b + optional `p2pService` param) and `GROUP_TESTS`. Regions are disjoint (top vs bottom band) but same files — take a `git status --short` snapshot first; if 211 has landed, rebase E3 over it; never revert their hunks. → pinned by the dirty-tree snapshot step.
- **Shadow clipped to invisibility** if placed inside ClipOval → pinned by TC-212-08 boxShadow assert (asserts the OUTER container's decoration).
- **Nav de-centers** if only the trailing Expanded is removed (flex imbalance) → TC-212-02/-12.
- **Trigger hit region shrinks** if `HitTestBehavior.opaque` is forgotten (deferToChild + ClipOval = dead corners) → TC-212-08 corner-tap assert.
- **Mid-transit paint order** (trigger visible through/over rising dock) → trigger layer before dock layer; behavioral lock TC-212-06.
- **Semantics double-count** — impossible: trigger and pill never coexist in one view (trigger allChats-only; sculpt semantics sweep pumps the surface alone).
- 52px pill top (92) nears strip bottom (96) — dead configuration (see Refuted: chips never coexist with the collapsed pill); no constant changes.

## Device/Relay Proof Profile
**Host-only for closure** (205/206/208/209/211 class: no DB/migration, no crypto, no transport, no OS boundary — pure Flutter chrome).
PROD-CRITICAL leg: `feed_wired_test.dart:1035-1087` (real shell host → toggle to all-chats → trigger tap → dock → filter → re-entry reset), already curated FEED_TESTS:182 — do NOT treat the widget-level rows as sufficient on their own.
Optional (non-gate) visual QA: launch on one iPhone sim and screenshot the all-chats view + rings view to eyeball the shared band (house habit per screenshot-verify memory).
No new sim scenarios → `check_reliability_simulation_discovery.sh` unaffected; `/sims` untouched.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# 0) Dirty-tree snapshot (coordinate with concurrent session 211)
git status --short

# 1) RED (after E1, before production edits) — each must FAIL for its documented reason
flutter test test/features/orbit/presentation/screens/orbit_search_trigger_placement_test.dart   # RED: inline placement (TC-212-01/03/04; 05 via height)
flutter test test/features/orbit/presentation/widgets/orbit_search_trigger_test.dart             # RED: 44px pin + no shadow + no Semantics (TC-212-08/09)
flutter test test/features/orbit/presentation/widgets/orbit_find_pill_ux_test.dart               # RED: TC-212-11 (44/borderless)
flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart             # RED: rewritten placement test (TC-212-12)
flutter test test/l10n/orbit_strings_parity_test.dart                                            # RED: newOrbitKeys pinned, key absent

# 2) Direct GREEN (after E2-E5)
flutter test \
  test/features/orbit/presentation/screens/orbit_search_trigger_placement_test.dart \
  test/features/orbit/presentation/widgets/orbit_search_trigger_test.dart \
  test/features/orbit/presentation/widgets/orbit_find_pill_ux_test.dart \
  test/features/orbit/presentation/screens/orbit_screen_loading_test.dart \
  test/features/orbit/presentation/screens/orbit_wired_test.dart                                 # expect: all pass incl. TC-212-06/07

# 3) Preservation sentinels
flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart                 # rings: trigger findsNothing (INV-212-2)
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart        # bands 40/88/kb + semantics sweep (TC-212-14)

# 4) Named gates (counts = last-known 2026-07-05 baselines; recount at execution)
./scripts/run_test_gates.sh groups        # expect all green; last-known 1110 (+2 wired TCs, +1 pinned file; +session-211 additions if landed)
./scripts/run_test_gates.sh feed          # expect all green; last-known 292
flutter test test/l10n/                   # expect: integrity 7/7 + parity green

# 5) Wide host + hygiene
./scripts/run_host_test_gates.sh feature-host-all   # only allowed red: pre-existing group_conversation_wired_bg_task_test
flutter analyze                                     # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED (pre-fix): the five block-1 commands above, each for its documented reason.
- Pre-existing dirty: `group_conversation_wired_bg_task_test` red under feature-host-all (fails at clean HEAD; predates 209 — NOT 212). Tree also carries graphify-arch regen files, `info.plist`, `integration_test/group_recovery_e2e_test.dart`, `lib/core/debug/intro_e2e_runner.dart`, `scripts/run_sims_detached.sh`, and session-211 docs — do not revert.
- Environment blocker (NOT product): none expected — host-only.
- Scope drift (BLOCKING): any red in dock tests, sculpt band tests, TC-202-10, standalone offsets, or top-chrome (session 211) tests caused by 212 edits.

## Done Criteria
- [x] RED added first, failed for the expected reason (block 1: exactly 10 REDs, each documented).
- [x] Mutation-verified: un-float E3 → TC-212-01/03/04 RED; pill BackdropFilter → TC-212-11 RED; drop IgnorePointer → TC-212-06 RED; all reverted clean.
- [x] Direct GREEN + preservation sentinels (85) + named gates pass (groups 1139 / feed 292 / l10n 11).
- [x] No migration (no schema change) — N/A by construction.
- [x] No OS-boundary path — host-only closure justified above.
- [x] Harness registration done: placement test pinned into GROUP_TESTS; groups gate run included it (1139 > 1110 baseline).
- [x] flutter analyze 0 new on 212 files; git diff --check clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not reuse `OrbitSearchTrigger` by type on the rings surface, and do not add a `BackdropFilter` anywhere inside the collapsed find pill (V3 refuted; INV-212-2/-3).
- Do not reuse `orbit_find_pill_semantics` or the `orbit_search` dock hint as the trigger's label (V4).
- Do not touch: dock (`orbit_search_dock.dart`), expanded find bar, band constants 28/40/88/96/144, standalone offsets 88/36, scroll-hide thresholds 100/50, `orbit_wired.dart` controllers/durations/curves, `OrbitCloseButton`.
- Do not touch top chrome (view toggle, connection indicator, ExpandableFab) — session 211 owns it; do not revert its hunks in shared files.
- Do not resurrect the declined 212-exhibit options (labeled capsule, nav-pill fusion, top placements).

## Accepted Differences / Intentionally Out Of Scope
- Persistent floated trigger keeps opacity+scale (no +14px translate); standalone keeps its translate flourish — unifying the transform sets is cosmetic follow-up, unowned.
- Standalone 14px band mismatch (pill 74 vs trigger 88) — pre-existing, zero production hosts, locked as-is by TC-212-05.
- `OrbitCloseButton` stays 44px — standalone-only; restyle owned by nobody (would follow the 212 vocabulary if standalone ever ships).
- Labeled "Find" capsule (exhibit Option A) — declined by user for the simple circle; the exhibit records the design rationale if revisited.

## Dependency Impact
- Session 211 (toggle glyph + connection indicator) shares `orbit_screen.dart` + `GROUP_TESTS`: disjoint regions, land-order-agnostic with the rebase note in Risks.
- The 207 intro-dock exploration (unratified) claims the centered under-rings band — unaffected: 212 keeps the corner, not the center.
- Future 196/198-family orbit work inherits INV-212-1 (one bottom-right search home) — any new bottom-band chrome must clear `navBottomOffset+84 .. +136`.

## Reviewer Findings
Sufficiency self-check (references/sufficiency-checklist.md) — all gates PASS: 14 spec cases → 14 matrix rows, zero empty tier/mutation/gate/registration cells; every INV has a named test; 3 headline mutations named for spot-verification; no vacuous coverage (sentinel rows carry explicit re-red mutations); no DB/migration; no OS boundary (host-only justified, PROD-CRITICAL leg named); preservation sentinels listed with gate commands; literal gates with last-known counts; registration stated per test (1 manual: GROUP_TESTS pin); known-failure interpretation + dirty-tree snapshot written; refuted findings (V3, V4, chip-strip bump, standalone mismatch) recorded as do-not-re-introduce. Blind-spot sweep: 2 rows (sibling-surface via TC-212-03/09; transition re-verification via TC-212-06/07) + 2 justified N/A (lifecycle, destructive).

## Arbiter Decision
Structural blockers: none. | Deferred details: exact shadow color/blur may be tuned at execution within TC-212-08/11's "boxShadow non-empty" assert; ar/de label copy may be adjusted (parity test only enforces presence/non-empty). | Accepted differences: as listed above.

## Final Execution Verdict
Verdict: CLOSED host-green (2026-07-05) | Files changed: lib ×3 (orbit_search_trigger, orbit_screen, inner_circle_interactive_surface) + arbs ×3 + gen-l10n ×4; tests: NEW orbit_search_trigger_placement_test + 6 edited (wired, trigger, pill-ux, loading, parity, pump-harness) + run_test_gates.sh GROUP_TESTS pin | Tests run: direct block green; sentinels 85; groups 1139; feed 292; l10n 11; feature-host-all green except pre-existing bg_task red; 3/3 headline mutations re-red | Blocking: none | QA verdict: pass — one plan deviation recorded (TC-212-06 post-tap asserts corrected to ground truth: open dock owns the corner band's pixels; inertness locked structurally via IgnorePointer(ignoring)==true, mutation-verified) | Non-blocking follow-ups: optional sim screenshot QA of the shared band (house habit, non-gate); status update to "Status:" header left as `awaiting-review` → superseded by this verdict.
