# 226 - Settings navbar: remove Feed icon, glass Orbit button, swipe-right back to Orbit  (Modification)

Status: awaiting-review
Spec: free-text intent (no formal spec) — user request 2026-07-09: on the Settings page (1) remove the "Feed" icon from the navbar, (2) restyle the "Orbit" navbar icon to the transparent/glass look of the Orbit screen's search trigger, (3) swipe right (left→right) returns to the Orbit screen.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector (workflow `wf_194c8bc1-200`, 9 agents: scout + seam + test-inventory + 3×verify + 3×refute) | settings_screen.dart, settings_wired.dart, feed_navigation_bar.dart, nav_bar_button.dart, nav_bar_theme.dart, orbit_search_trigger.dart, background_readable_colors.dart, settings_route_transition.dart, orbit_wired.dart, feed_wired.dart, app_shell_controller.dart, posts_wired.dart + 20 test files | All 3 claims CONFIRMED on HEAD; none refuted. Shared-widget defaults heavily test-locked; Settings surface untested. | plan |
| 2026-07-09 | Planner | (this file) | Settings-local glass button widget replaces shared bar on Settings only; GestureDetector swipe on SettingsWired gated by showNavigationBar; route type unchanged | matrix + catalog |
| 2026-07-09 | Reviewer (sufficiency) | sufficiency-checklist gates | All gates pass; sentinels proven non-vacuous by named mutations | arbiter |
| 2026-07-09 | Arbiter | | No structural blockers. UI-only, host-closure, no DB, no crypto/OS boundary. | hand off to execution |
| 2026-07-09 | External audit (`226-review-fixlist.md`, workflow `wf_a05c3362-ab0`) + Planner (critical application) | settings_wired.dart:525-560/:693-718, app_shell_controller.dart:1-60, settings_screen_test.dart:140-152 (conflicting agent claims re-verified in source) | Applied M1, M2 (B2 mutation replaced with implementable `isCurrent`-guard design), T1, T2, T3-partial, T4, T5, N1–N5; REJECTED T3's 206-enter sub-claim (already bound twice) and N6 (redundant). Matrix 16→17 rows; File C 9→10 tests. | confirm 2 user decisions, then execute |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-09 22:10 CEST | contract extraction | Test-Flight-Improv/226-settings-navbar-orbit-glass-swipe-back-tdd-plan.md | `git status --short`; `cd graphify-arch && graphify query "Implementation context for Test-Flight-Improv/226-settings-navbar-orbit-glass-swipe-back-tdd-plan.md: settings navbar orbit glass swipe-back files tests gates" --budget 1500`; plan sections `Real Scope`, `RED Test Catalog`, `Acceptance Gates`, `Known-Failure Interpretation`, `Done Criteria`, `Scope Guard` extracted | scope confirmed; pre-existing dirty tree is unrelated and must not be reverted; graph query was low-signal so plan + direct source are source of truth | spawn isolated Executor |
| 2026-07-09 22:11 CEST | Executor spawned/running | Test-Flight-Improv/226-settings-navbar-orbit-glass-swipe-back-tdd-plan.md | spawned worker agent `019f4882-2fc2-7093-8d23-ef6b92450f40` (`Newton`) with `model:gpt-5.5`, `reasoning_effort:xhigh`; assigned RED-first implementation and exact required gates | pending Executor result | bounded wait, then inspect file-backed evidence |
| 2026-07-09 22:12 CEST | Executor local pass / contract extraction | Test-Flight-Improv/226-settings-navbar-orbit-glass-swipe-back-tdd-plan.md | `git status --short`; `cd graphify-arch && graphify query "Plan 226 settings navbar orbit glass button swipe right settings to orbit settings_screen settings_wired" --budget 1500`; plan sections through `Done Criteria` read | scope confirmed for plan 226 only; graph query low-signal; dirty tree includes unrelated existing changes and must be left intact | inspect scoped production/test/reference files |
| 2026-07-09 22:13 CEST | compile-anchor stub | lib/features/settings/presentation/widgets/settings_orbit_nav_button.dart | Added unmounted `SettingsOrbitNavButton` stub: 52x52 `SizedBox`, opaque `GestureDetector`, onTap wired only | no behavior-bearing production mount yet; RED tests can now compile against the type | add File A/B/C/D RED tests |
| 2026-07-09 22:16 CEST | Executor bounded wait closed | lib/features/settings/presentation/widgets/settings_orbit_nav_button.dart; Test-Flight-Improv/226-settings-navbar-orbit-glass-swipe-back-tdd-plan.md | first Executor `019f4882-2fc2-7093-8d23-ef6b92450f40` timed out after initial bounded wait + one extension; file-backed evidence shows only compile-anchor stub and progress entries, no RED tests/implementation/gates | classified `spawn_or_tool_failure` for first Executor attempt; partial state is limited and coherent | spawn fresh Executor recovery pass from stub state |
| 2026-07-09 22:17 CEST | Executor recovery spawned/running | lib/features/settings/presentation/widgets/settings_orbit_nav_button.dart; Test-Flight-Improv/226-settings-navbar-orbit-glass-swipe-back-tdd-plan.md | spawned worker agent `019f4885-f5ea-7311-b541-d965cb89e2eb` (`Linnaeus`) with `model:gpt-5.5`, `reasoning_effort:xhigh`; assigned continuation from stub state through RED tests, implementation, exact gates, graph updates | pending Executor recovery result | bounded wait, then inspect file-backed evidence |
| 2026-07-09 22:20 CEST | Executor recovery bounded wait closed | lib/features/settings/presentation/widgets/settings_orbit_nav_button.dart; Test-Flight-Improv/226-settings-navbar-orbit-glass-swipe-back-tdd-plan.md | recovery Executor `019f4885-f5ea-7311-b541-d965cb89e2eb` timed out after first bounded wait; inspection showed no new RED tests, implementation diffs, or heartbeat beyond the prior stub state | classified `spawn_or_tool_failure`; child materialization/no-progress repeated, but file-backed state remains coherent | use local sequential fallback for Executor responsibilities, then local QA pass |
| 2026-07-09 22:28 CEST | RED command triage | test/features/settings/presentation/screens/settings_swipe_back_test.dart | failing command: `flutter test test/features/settings/presentation/widgets/settings_orbit_nav_button_test.dart test/features/settings/presentation/screens/settings_navbar_test.dart test/features/settings/presentation/screens/settings_swipe_back_test.dart`; compile failure: `WidgetTester.flingAt` undefined; focused triage/fix: replace unavailable helper with raw `startGesture` coordinate fling equivalent | classification: caused-by-session RED harness authoring issue, not product behavior | patch File C harness and rerun RED |
| 2026-07-09 22:31 CEST | RED tests added | lib/features/settings/presentation/widgets/settings_orbit_nav_button.dart; test/features/settings/presentation/widgets/settings_orbit_nav_button_test.dart; test/features/settings/presentation/screens/settings_navbar_test.dart; test/features/settings/presentation/screens/settings_swipe_back_test.dart; test/features/settings/presentation/screens/settings_screen_test.dart; test/features/orbit/presentation/screens/orbit_settings_entry_test.dart | `flutter test test/features/settings/presentation/widgets/settings_orbit_nav_button_test.dart test/features/settings/presentation/screens/settings_navbar_test.dart test/features/settings/presentation/screens/settings_swipe_back_test.dart` failed as expected: 10 failures (TC-226-04/05/06 vs stub; TC-226-01/02 Feed bar still mounted; TC-226-07/08/09/14/15 no glass button/swipe) and 6 sentinel passes (TC-226-03/10/11/12/13/17); `flutter test test/features/orbit/presentation/screens/orbit_settings_entry_test.dart --plain-name 'TC-226-16'` failed because SettingsWired remained mounted after fling | RED confirmed for expected reasons after harness compile triage | implement scoped production changes |
| 2026-07-09 22:34 CEST | direct GREEN triage | test/features/settings/presentation/screens/settings_swipe_back_test.dart | failing command: `flutter test test/features/settings/presentation/widgets/settings_orbit_nav_button_test.dart test/features/settings/presentation/screens/settings_navbar_test.dart test/features/settings/presentation/screens/settings_swipe_back_test.dart`; failing tests: TC-226-09 and TC-226-15 slow-drag legs stayed on feed; focused triage/fix: increase slow test drag distance from 260/280 to 360px so delivered horizontal-drag delta remains above 0.28×800 after touch slop | classification: caused-by-session test harness distance fragility; production fast fling, navbar tap, RTL, and sentinels already green | patch slow drag distances and rerun direct GREEN |
| 2026-07-09 22:36 CEST | implementation | lib/features/settings/presentation/widgets/settings_orbit_nav_button.dart; lib/features/settings/presentation/screens/settings_screen.dart; lib/features/settings/presentation/screens/settings_wired.dart; test/features/settings/presentation/screens/settings_screen_test.dart; test/features/orbit/presentation/screens/orbit_settings_entry_test.dart | Implemented full SettingsOrbitNavButton glass recipe; swapped Settings bottom nav to SettingsOrbitNavButton only; added showNavigationBar-gated horizontal drag in SettingsWired with 0.28×width/900 velocity threshold and `ModalRoute.isCurrent` guard; updated existing settings/orbit tests | scoped files only; no guarded shared navbar/route/feed-swipe files touched | run direct GREEN commands |
| 2026-07-09 22:39 CEST | direct GREEN | new/updated File A/B/C/D tests | `flutter test test/features/settings/presentation/widgets/settings_orbit_nav_button_test.dart` passed 3/3; `flutter test test/features/settings/presentation/screens/settings_navbar_test.dart` passed 3/3; `flutter test test/features/settings/presentation/screens/settings_swipe_back_test.dart` passed 10/10; `flutter test test/features/orbit/presentation/screens/orbit_settings_entry_test.dart` passed 15/15 including TC-226-16 | direct reds now green | run preservation sentinels |
| 2026-07-09 22:44 CEST | preservation GREEN | settings/feed/orbit/push/theme sentinel tests | `flutter test test/features/settings/` passed 218/218; `flutter test test/features/feed/presentation/widgets/feed_navigation_bar_test.dart test/features/feed/presentation/widgets/nav_bar_button_test.dart test/features/feed/presentation/widgets/nav_bar_button_tone_test.dart` passed 28/28; `flutter test test/features/orbit/presentation/widgets/orbit_search_trigger_test.dart` passed 5/5; `flutter test test/features/push/application/intro_notification_orbit_route_test.dart test/features/theme/dark_preset_preservation_test.dart` passed 8/8 | sentinels green; shared defaults/reference trigger unchanged | run named gates `feed` and `groups` |
| 2026-07-09 22:58 CEST | named gates | scripts/run_test_gates.sh | `./scripts/run_test_gates.sh feed` passed 307/307; `./scripts/run_test_gates.sh groups` passed 1184/1184 | named gates green | run hygiene and graph updates |
| 2026-07-09 23:00 CEST | analyzer triage | test/features/settings/presentation/screens/settings_swipe_back_test.dart | failing command: `flutter analyze`; repo-wide output has 1626 existing issues, plus new infos in File C at line 275 (`unnecessary_underscores`); focused triage/fix: rename transparent route pageBuilder placeholder args | classification: caused-by-session analyzer hygiene issue within touched test; repo-wide analyzer debt is pre-existing/unrelated | patch new analyzer issue, then run focused analyze on touched files |
| 2026-07-09 23:03 CEST | hygiene | touched Dart files; working diff | `flutter analyze lib/features/settings/presentation/widgets/settings_orbit_nav_button.dart lib/features/settings/presentation/screens/settings_screen.dart lib/features/settings/presentation/screens/settings_wired.dart test/features/settings/presentation/widgets/settings_orbit_nav_button_test.dart test/features/settings/presentation/screens/settings_navbar_test.dart test/features/settings/presentation/screens/settings_swipe_back_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/orbit/presentation/screens/orbit_settings_entry_test.dart` passed with no issues; `flutter test test/features/settings/presentation/screens/settings_swipe_back_test.dart` rerun after test-format patch passed 10/10; `git diff --check` passed | no new analyzer/diff-check issues; repo-wide `flutter analyze` remains red from pre-existing unrelated debt | run `graphify update .` and `./graphify-arch/refresh_arch_graph.sh` |
| 2026-07-09 23:10 CEST | graph refresh | graphify-out; graphify-arch/graphify-out; graphify-arch/GRAPH_SELECTION.md; graphify-arch/comparison.json | `graphify update .` passed (`110161` nodes, `185695` edges); `./graphify-arch/refresh_arch_graph.sh` passed (`43920` nodes, `68975` edges; aggregated `graph.html` written) | required post-code graph updates complete; generated graph diffs expected | independent QA review |
| 2026-07-09 23:12 CEST | registration proof | scripts/run_host_test_gates.sh dry-run plan | `./scripts/run_host_test_gates.sh feature-host-all --list` passed discovery only; plan includes `orbit_settings_entry_test.dart` at item 463, `settings_navbar_test.dart` at item 651, `settings_swipe_back_test.dart` at item 655, and `settings_orbit_nav_button_test.dart` at item 661; full `feature-host-all` execution expands to 673 commands and was not part of the literal acceptance gate set | auto-glob registration verified without running the broad gate | finalize QA verdict |
| 2026-07-09 23:14 CEST | QA (independent) | Test-Flight-Improv/226-settings-navbar-orbit-glass-swipe-back-tdd-plan.md; scoped diff | QA Reviewer agent `019f4898-c199-7b70-9dbc-8caa809b261a` returned `accepted_with_explicit_follow_up`; no blocking findings; confirmed glass button recipe, Settings-only navbar swap, showNavigationBar-gated swipe, scope guard untouched, and direct/preservation/named-gate/focused-analyze/graph evidence | accepted with explicit follow-up because repo-wide `flutter analyze` remains pre-existing red and full `feature-host-all` execution was not run; both non-blocking for plan 226 closure | final verdict recorded |

## Source Of Truth
- Spec / intent: inline above (free-text; grounded by workflow `wf_194c8bc1-200`)
- Gate definitions: scripts/run_test_gates.sh  (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready

## Exact Problem Statement
The Settings page (SettingsWired → SettingsScreen) shows the shared shell navbar `FeedNavigationBar` at the bottom (`settings_screen.dart:297-308`, gated by `showNavigationBar`, default true on the main Orbit→Settings path). That bar hardcodes TWO buttons — Feed (`feed_navigation_bar.dart:70-76`) and Orbit (`:78-84`) — with no parameter to hide or restyle either. The user wants Settings to show only an Orbit affordance, restyled to the 52px transparent-glass circle of the Orbit screen's search trigger (`orbit_search_trigger.dart:26-57`), instead of the current 70px-wide pill `NavBarButton` (18px SVG + 11px label, active-pill gradient). Additionally, Settings is pushed via a bespoke bare `PageRouteBuilder` slide-up (`settings_route_transition.dart:7-34`) that carries **no** built-in iOS edge swipe-back, and the settings feature contains **zero** horizontal-gesture handling — so a left→right swipe on Settings does nothing today; the only ways back are the header chevron (`_onBack` → pop, `settings_wired.dart:165-167`) and the navbar Orbit tap (`_onSwitchView` → `switchTo(tab)` + pop, `:532-535`).

What must improve:
1. Settings navbar renders NO Feed destination.
2. Settings' Orbit affordance is the glass circle (ClipOval + BackdropFilter blur 12 + `glassSurface` fill + `glassBorder` ring + outer shadow + 24px icon), reusing `BackgroundReadableColors` tokens so it adapts to dark/daylight tones.
3. A qualifying left→right swipe anywhere on the (navbar-visible) Settings surface performs exactly what tapping the Orbit navbar button does: `appShellController.switchTo(orbit)` + single `Navigator.pop`.

What must stay unchanged (→ preserved-green sentinels):
- `FeedNavigationBar` / `NavBarButton` / `NavBarTheme` defaults on Feed, Orbit, and Posts surfaces (Feed button present, pill styling) — locked by `feed_navigation_bar_test.dart` (TC-205-10, positional badge/active tests, bar-chrome locks), `nav_bar_button_test.dart`, `nav_bar_button_tone_test.dart`, plus `orbit_wired_test.dart` / `feed_wired_test.dart` / `intro_notification_orbit_route_test.dart` / `dark_preset_preservation_test.dart` which tap/find `'Feed'` on those surfaces.
- The Settings slide-up enter animation (feature 206, TC-206-01) — route type is NOT swapped.
- Posts-entry Settings (`posts_wired.dart:554`, `showNavigationBar:false`): no navbar, and NO swipe surface (gate the gesture on the same flag).
- Vertical scrolling of Settings content (`settings_one_screen_layout_test.dart` T4).
- Orbit's `_settingsRouteActive` single-flight latch (`orbit_wired.dart:655-684`) — released via `whenComplete` on any pop, including swipe-dismiss.
- Feed↔Orbit host swipe (feature 30, `feed_wired.dart`) — untouched.

## Root Cause (verify → refute confirmed)
Not a bug — a modification. The three grounded mechanisms (all CONFIRMED, refute pass failed to kill any):
1. **Feed icon present:** `orbit_wired.dart:657-681` pushes SettingsWired without `showNavigationBar` → default true (`settings_wired.dart:87`) → forwarded (`:808-810`) → `settings_screen.dart:297-308` mounts `FeedNavigationBar` → Feed button hardcoded `feed_navigation_bar.dart:70-76`; constructor (`:15-21`) exposes no hide parameter.
2. **Orbit icon not glass:** the navbar Orbit affordance is `NavBarButton` (`nav_bar_button.dart:38-101`): Material>InkWell>AnimatedContainer(width 70, radius 19, active-only pill gradient `:55-68`) — zero ClipOval/BackdropFilter/glassSurface/glassBorder/Border.all/BoxShadow. The glass recipe lives only in `orbit_search_trigger.dart:26-57` with tokens at `background_readable_colors.dart:128-129` (dark) / `:183-184` (light). The bar-level blur (`feed_navigation_bar.dart:28-63`) is bar chrome, not per-icon glass.
3. **No swipe-back:** `buildSettingsSlideUpRoute` is a bare `PageRouteBuilder` (`settings_route_transition.dart:7-34`) — no `CupertinoRouteTransitionMixin`, so no built-in edge swipe; grep of `lib/features/settings/` for horizontal-drag/pan/Dismissible/PopScope/Listener/PageView returns nothing (tap-only GestureDetectors). The feature-30 host-swipe Listener sits below the opaque pushed route and is not hit-tested while Settings is up.

Refuted / do-NOT-re-introduce: **nothing was found already-fixed** — no uncommitted restyle/swipe work exists (dirty-tree hunks are orbit arc-layout + push-envelope staging, none in this seam). Investigated and ruled out: `hideShellNav` does NOT affect Settings (Orbit view-toggle only, `orbit_screen.dart:761-772`); the only `showNavigationBar:false` caller is the Posts entry; no default iOS back-swipe exists to "already satisfy" modification 3.

## Real Scope
In scope:
- New Settings-local widget `SettingsOrbitNavButton` (`lib/features/settings/presentation/widgets/settings_orbit_nav_button.dart`): Semantics(button, label = l10n `nav_orbit`) > GestureDetector(opaque) > 52×52 glass circle cloned from the `orbit_search_trigger.dart:26-57` recipe (shadow `0x59000000` blur 18 offset(0,6) OUTSIDE the ClipOval — a clipped shadow is invisible; ClipOval > BackdropFilter.blur(12,12) > circle with `readableColors.glassSurface` fill + `Border.all(readableColors.glassBorder)`), child `SvgPicture.asset('assets/icons/nav_orbit.svg', 24×24, colorFilter srcIn readableColors.iconPrimary)`. Resolve `BackgroundReadableColors` via the same accessor `OrbitSearchTrigger` uses.
- `settings_screen.dart:297-308`: replace `FeedNavigationBar(...)` with `SettingsOrbitNavButton(onTap: () => onSwitchView('orbit'))` inside the same `if (showNavigationBar) Positioned(... bottom: bottomInset + 8 ...) > Center`. Keep the `:259` scroll-padding branch as-is. Drop the now-unused `FeedNavigationBar` import. `activeTab` param stays (API stability; harnesses pass it).
- `settings_wired.dart`: when `widget.showNavigationBar`, wrap the `SettingsScreen` child inside the wired Scaffold body (`settings_wired.dart:779` — the Scaffold's body IS SettingsScreen; arena semantics hold either way) in `GestureDetector(behavior: translucent, onHorizontalDragStart/Update/End)`; accumulate `delta.dx` (single-axis recognizer: `delta == Offset(primaryDelta, 0)`); qualify ONLY in `onHorizontalDragEnd` — **end-firing is the committed design**: one callback per recognized gesture, NO latch — a NET-rightward gesture (`totalDx > 0` AND (`totalDx >= 0.28 × width-at-drag-end` (MediaQuery read at end, feed_wired `_hostViewportWidth` precedent) OR `primaryVelocity >= 900`, positive == rightward)) → fire the existing `_onSwitchView('orbit')`, guarded by `mounted` AND `ModalRoute.of(context)?.isCurrent == true`. The `isCurrent` guard is DESIGNED (not accidental-occlusion) protection: `_onSwitchView` pops the TOPMOST route, so a leaked gesture while a Settings sub-flow is up — Move-Account (`settings_wired.dart:700-717`), `_showSettingsSheet` modal sheet (`:553-557`), `_runQrEntry` QR (`:539`) — would pop the WRONG route. Thresholds mirror feature-30 (`feed_wired.dart:247-249`). Direction is PHYSICAL (dx), not text-direction-mirrored.
- Update `settings_screen_test.dart:150/:246/:307` — `find.byType(FeedNavigationBar)` → `find.byType(SettingsOrbitNavButton)` (+ import).
- New tests per the matrix; one added case in `orbit_settings_entry_test.dart` (already curated in GROUP_TESTS).

Out of scope (owners):
- Any change to `FeedNavigationBar`/`NavBarButton`/`NavBarTheme` defaults or the Feed/Orbit/Posts surfaces (their current look is the product decision; locked by existing tests).
- Route-type swap to MaterialPageRoute for free edge-swipe (would replace the deliberate 206 slide-up enter; the conversation route owns that pattern — `conversation_route_transition.dart:3-19`).
- Interactive drag-tracking of the route transition during the swipe (pop uses the existing 280ms exit); future polish session if wanted.
- Swipe/back changes on Posts-entry Settings (`showNavigationBar:false`) and any Feed/Orbit host-swipe change (feature 30).
- Extracting a shared GlassCircleButton from `orbit_search_trigger.dart` (nice-to-have refactor; not worth risking TC-212 locks here).

## Files To Inspect Next
Production: `lib/features/settings/presentation/screens/settings_screen.dart` (:259, :297-308), `lib/features/settings/presentation/screens/settings_wired.dart` (:87, :165-167, :532-535, :778-812), NEW `lib/features/settings/presentation/widgets/settings_orbit_nav_button.dart`; references (read-only): `lib/features/orbit/presentation/widgets/orbit_search_trigger.dart` (:19-57), `lib/core/theme/background_readable_colors.dart` (:122, :128-129, :177, :183-184), `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`, `lib/features/feed/application/app_shell_controller.dart` (:26-48), `lib/features/feed/presentation/screens/feed_wired.dart` (:247-249, :2376-2479) for threshold parity.
Direct tests: `test/features/settings/presentation/screens/settings_screen_test.dart`, `settings_wired_test.dart` (harness to clone), `settings_one_screen_layout_test.dart`, `test/features/orbit/presentation/widgets/orbit_search_trigger_test.dart` (glass-assertion pattern to clone, TC-212-08), `test/features/orbit/presentation/screens/orbit_settings_entry_test.dart` (route-stack harness), `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart` (sentinels).
Dependency-only context: `lib/features/orbit/presentation/screens/orbit_wired.dart` (:652-685 latch), `lib/features/posts/presentation/screens/posts_wired.dart` (:554), `lib/features/settings/presentation/navigation/settings_route_transition.dart`, `lib/main.dart` (:3524-3540 returnTab pattern).

## Existing Tests Covering This Area
- `settings_screen_test.dart` — navbar coverage is TYPE-ONLY (`find.byType(FeedNavigationBar)` ×3 at :150/:246/:307); no button-set, no tap, no `find.text('Feed')` (exists; must be UPDATED to the new type).
- `settings_wired_test.dart` — back-chevron pop (:881), identity/background behaviors; ZERO `_onSwitchView`/navbar-tap coverage (gap).
- `settings_one_screen_layout_test.dart` — layout fit/scroll/textScale/RTL; mounts navbar, never asserts its buttons (sentinel).
- `orbit_settings_entry_test.dart` — TC-206-01/02/03/06/29/27 entry + tap-back + reopen (curated GROUP_TESTS; extend here).
- `feed_navigation_bar_test.dart`, `nav_bar_button_test.dart`, `nav_bar_button_tone_test.dart` — heavy locks on the SHARED defaults (expectedButtons=2, positional Feed/Orbit, pill gradient, no-border/no-shadow, bar chrome) — preserved-green sentinels proving the change did NOT leak.
- `orbit_search_trigger_test.dart` — TC-212-08 glass-recipe assertion pattern (blur/border/shadow/size) to clone; stays green (file untouched).
- Swipe precedents: `feed_swipe_test.dart` (host-swipe, FEED_TESTS), `conversation_route_transition_test.dart` (route-level, ONE_TO_ONE_TESTS) — both sentinels, untouched.
Missing coverage gaps (all three modifications land in untested territory): no test asserts the Settings navbar button SET; no test taps a navbar button on Settings (`_onSwitchView` uncovered); no glass styling test for any navbar affordance; zero swipe/gesture coverage in settings tests; `showNavigationBar:false` branch untested.
Already in curated family arrays?: `orbit_settings_entry_test.dart`, `orbit_search_trigger_placement_test.dart`, `orbit_wired_test.dart` → GROUP_TESTS; `feed_swipe_test.dart`, `feed_wired_test.dart`, `feed_focus_test.dart`, `feed_reduced_motion_test.dart` → FEED_TESTS; `conversation_route_transition_test.dart` → ONE_TO_ONE_TESTS. All settings/* and feed widget tests are auto-glob only.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
File B — `test/features/settings/presentation/screens/settings_navbar_test.dart` (NEW; clone the `settings_screen_test.dart` pump harness incl. l10n wrap):
1. B1 `TC-226-01 settings navbar renders no Feed destination`
   - Tier: widget. Shape: pump SettingsScreen(showNavigationBar:true, onSwitchView captured).
   - RED on HEAD because: `FeedNavigationBar` hardcodes the Feed button → `expect(find.text('Feed'), findsNothing)` fails (findsOneWidget); also asserts no `'assets/icons/nav_feed.svg'` SvgPicture.
   - GREEN asserts: no Feed text/icon anywhere in the navbar slot.
   - Mutation that re-reds: restore the `FeedNavigationBar` mount at `settings_screen.dart:303` (revert swap) → red.
2. B2 `TC-226-02 settings navbar slot renders the glass orbit button, not FeedNavigationBar`
   - Tier: widget. RED on HEAD: `find.byType(SettingsOrbitNavButton)` findsNothing / file absent (compile once stub exists); `find.byType(FeedNavigationBar)` findsOneWidget.
   - GREEN asserts: `SettingsOrbitNavButton` findsOneWidget inside the bottom Positioned; `FeedNavigationBar` findsNothing.
   - Mutation: revert swap → red.
3. B3 `TC-226-03 showNavigationBar=false renders neither orbit button nor bar`
   - Tier: widget. Behavior-GREEN on HEAD once compiling (sentinel — locks the flag gate for the NEW widget).
   - GREEN asserts: with `showNavigationBar:false`, no `SettingsOrbitNavButton`, no `FeedNavigationBar`.
   - Mutation: drop the `if (showNavigationBar)` gate around the new mount → red.

File A — `test/features/settings/presentation/widgets/settings_orbit_nav_button_test.dart` (NEW; clone `orbit_search_trigger_test.dart` assertion style):
4. A1 `TC-226-04 renders 52px glass circle: ClipOval, blur 12, glassSurface fill, glassBorder ring, outer shadow, nav_orbit icon 24`
   - Tier: widget. RED on HEAD: new-widget case — red-for-behavior against the unmounted step-2 stub (recipe assertions fail); green only against the full recipe.
   - GREEN asserts (mirroring TC-212-08): SizedBox/Container 52×52; BoxShadow(0x59000000, blur 18, offset(0,6)) asserted SPECIFICALLY on the outer unclipped Container — the ANCESTOR of the ClipOval (mirror `orbit_search_trigger_test.dart:33-41` `.first` pattern) — because a clipped shadow is invisible; ClipOval present; BackdropFilter with ImageFilter.blur sigma 12/12; inner circle color == dark `glassSurface` (0xCC0A0A0F) and border color == `glassBorder` (0x66FFFFFF); SvgPicture asset `nav_orbit.svg` at 24×24 with iconPrimary colorFilter.
   - Mutation: remove the BackdropFilter (or replace glassSurface with a solid literal) → red. Second mutation (shadow-placement invariant): move the BoxShadow onto the INNER clipped Container → the outer decoration's boxShadow is empty → red.
5. A2 `TC-226-05 daylight tone uses light glass tokens`
   - Tier: widget. RED on HEAD: red vs stub (no tone-adaptive fill). GREEN: under the daylight/light tone, fill == 0xEEF7F8FB, border == 0x33463A96, icon color == light iconPrimary 0xFF16181F (same tone-injection the trigger test uses).
   - Mutation: hardcode dark glassSurface (ignore tone) → red.
6. A3 `TC-226-06 exposes Semantics button label and fires onTap`
   - Tier: widget. RED on HEAD: red vs stub if Semantics missing (stub wires onTap only). GREEN: Semantics button with label == l10n `nav_orbit`; tap fires callback once.
   - Mutation: remove the GestureDetector onTap wiring → red.

File C — `test/features/settings/presentation/screens/settings_swipe_back_test.dart` (NEW; wired harness cloned from `settings_wired_test.dart`, SettingsWired pushed via `buildSettingsSlideUpRoute` over a stub home so pops are observable; **`AppShellController(initialTab: AppShellTab.feed)`** — the controller DEFAULTS to orbit (`app_shell_controller.dart:26-33`) and `switchTo` no-ops on same-tab (`:41-48`), so a feed seed is REQUIRED for the tab-switch assertions to be non-vacuous):
7. C1 `TC-226-07 tapping the glass orbit button switches the shell to orbit and pops Settings`
   - Tier: widget (wired). RED on HEAD: the glass button does not exist → tap target not found.
   - GREEN asserts: tab is `AppShellTab.feed` BEFORE the tap and `AppShellTab.orbit` AFTER, and `find.byType(SettingsWired)` findsNothing (first-ever coverage of the `_onSwitchView` seam `settings_wired.dart:532-535` — the transition assertion is what makes the `switchTo` half real).
   - Mutation: make the new button's onTap a no-op → red. Second mutation (switchTo half): replace `_onSwitchView('orbit')` with a bare `Navigator.pop()` → tab stays feed → red.
8. C2 `TC-226-08 fast rightward fling pops Settings and lands the shell on orbit`
   - Tier: widget (wired). Shape: `tester.fling(find.byType(SettingsScreen), Offset(300, 0), 1200)`.
   - RED on HEAD because: no horizontal handler exists → route still mounted → findsNothing assertion fails.
   - GREEN asserts: SettingsWired popped AND tab transitioned `feed` → `orbit` (harness seeds feed, so `switchTo` is NOT entry-satisfied — a bare-pop handler cannot pass). Discriminator: pop + tab-TRANSITION together distinguish the full `_onSwitchView('orbit')` path from a bare `_onBack`-style pop.
   - Mutation: remove the GestureDetector wiring in `settings_wired.dart` → red. Second mutation (switchTo half): handler → bare `Navigator.pop()` → tab stays feed → red.
9. C3 `TC-226-09 slow long rightward drag (≥0.28 screen width) pops`
   - Tier: widget (wired). Shape: `tester.timedDrag` rightward > 0.28×width at low velocity. Authoring note: 0.28×viewport = **224px on the default 800-wide test viewport**; the production distance arm reads MediaQuery width AT drag-end; start drags/flings from inert chrome (not on buttons) to avoid environment fragility. RED on HEAD: same as C2.
   - GREEN: popped + feed→orbit. Mutation: remove the distance arm (keep velocity-only) → red.
10. C4 `TC-226-10 leftward fling does not pop`
    - Tier: widget (wired). Behavior-GREEN on HEAD (sentinel; guards overtrigger).
    - GREEN asserts: SettingsWired still mounted after `fling(..., Offset(-300, 0), 1200)`.
    - Mutation (non-vacuous proof): change the qualifier from `totalDx > 0 && …` to `totalDx.abs() >= …` → red.
11. C5 `TC-226-11 short under-threshold rightward drag does not pop`
    - Tier: widget (wired). Sentinel (GREEN on HEAD). Mutation: set completion fraction/velocity thresholds to 0 → red.
12. C6 `TC-226-12 vertical scroll still scrolls and does not pop`
    - Tier: widget (wired). Sentinel. GREEN: vertical drag scrolls content (scroll offset changes), SettingsWired mounted. Mutation: change GestureDetector to claim vertical drags (onPanUpdate popping on any drag) → red.
13. C7 `TC-226-13 showNavigationBar=false disables the swipe surface`
    - Tier: widget (wired). Sentinel (GREEN on HEAD). GREEN: with flag false, rightward fling leaves SettingsWired mounted. Mutation: remove the flag gate on the GestureDetector → red.
14. C8 `TC-226-14 RTL: physical rightward fling still pops (direction not text-direction-mirrored)`
    - Tier: widget (wired). RED on HEAD (no handler → no pop). GREEN: under `Directionality.rtl` (ar locale, cf. layout T7 harness), physical dx>0 fling pops + orbit. Locks the accepted physical-direction decision.
    - Mutation: mirror dx by text direction → red.
15. C9 `TC-226-15 one qualifying gesture fires exactly one pop`
    - Tier: widget (wired). RED on HEAD (zero pops → "exactly one" fails). GREEN: NavigatorObserver counts exactly 1 pop for one long over-threshold gesture; a second fling on the (already popped) stub must not pop the stub home.
    - Mutation: move the firing into `onHorizontalDragUpdate` on threshold-cross (fires on every further update) → observer counts >1 pop → red. (End-firing is the committed design: `onHorizontalDragEnd` fires exactly once per recognized gesture — there is deliberately NO latch, so "remove the latch" would not be a valid mutation.)
16. C10 `TC-226-17 swipe is inert while a Settings sub-flow is topmost (wrong-route-pop guard)`
    - Tier: widget (wired). Two scenarios: (a) modal sheet over Settings (`showModalBottomSheet`, mirroring `_showSettingsSheet` `settings_wired.dart:553-557`) → rightward fling → SettingsWired AND the sheet both still mounted (ModalBarrier absorbs — occlusion leg); (b) worst-case NON-occluding sub-route: push a transparent, barrier-free `PageRouteBuilder(opaque:false)` test route over Settings → fling on the exposed Settings body → NOTHING popped (hits DO reach the detector here; only the `isCurrent` guard saves it — designed-safety leg).
    - RED on HEAD: behavior-GREEN sentinel (no gesture exists on HEAD) — non-vacuous via the mutation.
    - Mutation: remove the `ModalRoute.isCurrent` guard from the drag-end handler → scenario (b) pops the TOPMOST route (the sub-route: the wrong-route-pop failure, since `_onSwitchView` pops whatever is on top) → red.

File D — `test/features/orbit/presentation/screens/orbit_settings_entry_test.dart` (EXISTING, curated GROUP_TESTS — add one case using its real Orbit→Settings route stack):
17. D1 `TC-226-16 swipe-right on Settings returns to orbit intact and center tap reopens Settings`  **[PROD-CRITICAL leg]**
    - Tier: widget (full route-stack integration on host). RED on HEAD: after the fling, Settings is still mounted.
    - GREEN asserts: fling pops back to the real Orbit surface (orbit widgets visible), then the center-avatar tap reopens Settings (proves the `_settingsRouteActive` latch released via `whenComplete`, `orbit_wired.dart:682-684`).
    - Mutation (fling leg): remove the GestureDetector wiring → red. Mutation (reopen leg, independent): neuter the `whenComplete` latch-release at `orbit_wired.dart:682-684` (leave `_settingsRouteActive` true) → the reopen assertion reds on its own — proving the reopen leg is not vacuous even though this plan never edits `orbit_wired.dart`.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| SC-1 no Feed icon | UI render | widget | settings_navbar_test.dart::TC-226-01 | Feed button hardcoded in FeedNavigationBar → findsOneWidget | restore FeedNavigationBar mount (settings_screen.dart:303) | `flutter test test/features/settings/presentation/screens/settings_navbar_test.dart` (3/3) | AUTO (glob) |
| SC-1/SC-2 swap | UI render | widget | settings_navbar_test.dart::TC-226-02 | SettingsOrbitNavButton absent; FeedNavigationBar present | restore FeedNavigationBar mount | same as above | AUTO (glob) |
| SC-1 flag gate | UI render (flag) | widget | settings_navbar_test.dart::TC-226-03 | sentinel — GREEN once compiling; non-vacuous via mutation | drop `if (showNavigationBar)` gate | same as above | AUTO (glob) |
| SC-2 glass recipe | UI styling | widget | settings_orbit_nav_button_test.dart::TC-226-04 | stub renders a bare box → recipe assertions fail (stub-first: file present at RED time) | remove BackdropFilter / solid fill; move BoxShadow inside the ClipOval (outer boxShadow empty) | `flutter test test/features/settings/presentation/widgets/settings_orbit_nav_button_test.dart` (3/3) | AUTO (glob) |
| SC-2 tone | UI styling (theme) | widget | settings_orbit_nav_button_test.dart::TC-226-05 | stub not tone-adaptive → light-token assertions fail | hardcode dark glassSurface | same as above | AUTO (glob) |
| SC-2 a11y+tap | UI semantics | widget | settings_orbit_nav_button_test.dart::TC-226-06 | stub lacks Semantics → label leg red (onTap leg green vs stub) | remove onTap wiring | same as above | AUTO (glob) |
| SC-2/SC-3 shared action | wiring | widget (wired) | settings_swipe_back_test.dart::TC-226-07 | glass button absent → no tap target (first `_onSwitchView` coverage) | button onTap → no-op; handler → bare pop (tab stays feed) | `flutter test test/features/settings/presentation/screens/settings_swipe_back_test.dart` (10/10) | AUTO (glob) |
| SC-3 fling | gesture→nav | widget (wired) | settings_swipe_back_test.dart::TC-226-08 | zero horizontal handlers in settings → route stays mounted | remove GestureDetector in settings_wired.dart; handler → bare pop (tab stays feed) | same as above | AUTO (glob) |
| SC-3 slow drag | gesture threshold | widget (wired) | settings_swipe_back_test.dart::TC-226-09 | same as TC-226-08 | remove distance arm of qualifier | same as above | AUTO (glob) |
| SC-3 direction guard | gesture guard | widget (wired) | settings_swipe_back_test.dart::TC-226-10 | sentinel (GREEN on HEAD) — non-vacuous via mutation | qualifier `dx > 0` → `dx.abs()` | same as above | AUTO (glob) |
| SC-3 threshold guard | gesture guard | widget (wired) | settings_swipe_back_test.dart::TC-226-11 | sentinel — non-vacuous via mutation | thresholds → 0 | same as above | AUTO (glob) |
| SC-3 scroll coexistence | gesture arena | widget (wired) | settings_swipe_back_test.dart::TC-226-12 | sentinel — non-vacuous via mutation | claim vertical drags too | same as above | AUTO (glob) |
| SC-3 flag gate | gesture (flag) | widget (wired) | settings_swipe_back_test.dart::TC-226-13 | sentinel — non-vacuous via mutation | remove flag gate on GestureDetector | same as above | AUTO (glob) |
| SC-3 RTL lock | gesture (RTL) | widget (wired) | settings_swipe_back_test.dart::TC-226-14 | no handler → no pop under RTL either | mirror dx by text direction | same as above | AUTO (glob) |
| SC-3 single-fire | gesture idempotency | widget (wired) | settings_swipe_back_test.dart::TC-226-15 | zero pops on HEAD → "exactly one" fails | fire in onHorizontalDragUpdate on threshold-cross → >1 pop | same as above | AUTO (glob) |
| SC-3 sub-flow guard | gesture (route topmost) | widget (wired) | settings_swipe_back_test.dart::TC-226-17 | sentinel (GREEN on HEAD: no gesture exists) — non-vacuous via mutation | remove the `isCurrent` guard → transparent-sub-route leg pops the WRONG (topmost) route | same as above | AUTO (glob) |
| SC-3 end-to-end + reopen | route stack + latch | widget (integration, host) | orbit_settings_entry_test.dart::TC-226-16 | fling does nothing → Settings still mounted | fling leg: remove GestureDetector; reopen leg: neuter whenComplete latch-release (orbit_wired.dart:682-684) | `./scripts/run_test_gates.sh groups` (0 failures) | already in GROUP_TESTS array (no action) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** N/A — no persisted or derived state introduced (stateless styling; the drag accumulator resets on drag start and end-firing carries no cross-gesture state). Cross-mount reopen behavior IS covered anyway by TC-226-16 (swipe-dismiss → reopen) and existing TC-206-29.
- **Sibling-surface consistency:** deliberate asymmetry — Feed/Orbit/Posts keep the two-button pill bar; test-locked by `feed_navigation_bar_test.dart` (expectedButtons=2, TC-205-10), `nav_bar_button_test.dart`, `nav_bar_button_tone_test.dart`, `feed_wired_test.dart:809`, `orbit_wired_test.dart:961/:1318/:3479`, `intro_notification_orbit_route_test.dart:108/:139`, `dark_preset_preservation_test.dart:276` (all named preservation sentinels). The real sibling surfaces WITHIN Settings are its pushed sub-flows — Move-Account (`settings_wired.dart:700-717` pushes `AccountMigrationJourneyWired.oldPhone`, NOT a nested SettingsWired; an earlier draft's ":702 nested Settings" claim was source-refuted), `_showSettingsSheet` modal sheets (`:553-557`), `_runQrEntry` QR routes (`:539-547`) — where a leaked body-gesture pop would pop the WRONG route; guarded by the designed `isCurrent` check and locked by TC-226-17. Only two `SettingsWired(` construction sites exist repo-wide: `orbit_wired.dart:660` and `posts_wired.dart:540`.
- **Destructive-action side-effects:** the "removal" is UI-only; TC-226-01 asserts what is removed (Feed affordance) and TC-226-02 what is preserved (orbit affordance in the same slot). No data/file deletion → no further row.
- **Invariant re-verification under new transitions:** the new exit transition (swipe-dismiss) re-verifies the pre-existing invariants: shell tab == orbit after exit (TC-226-08), exactly one pop (TC-226-15), and the Orbit entry latch still permits reopen (TC-226-16). Covered.

## Invariants (locked by tests)
- INV-1: Settings navbar never renders a Feed destination → TC-226-01.
- INV-2: Settings orbit affordance uses the glass tokens in BOTH tones → TC-226-04/05.
- INV-3: Swipe-right and orbit-button tap converge on the identical shell action (switchTo orbit + exactly one pop) → TC-226-07/08/15, made non-vacuous by the feed-seeded harness (controller defaults to orbit, where `switchTo('orbit')` is a no-op) + the bare-pop mutation.
- INV-4: Both the affordance AND the swipe surface are gated by `showNavigationBar` → TC-226-03/13.
- INV-5: Shared navbar defaults on Feed/Orbit/Posts unchanged → existing sentinel suites (named above; the two out-of-dir sentinels now bound to a literal preservation command).
- INV-6: The swipe fires only while the Settings route is TOPMOST — it never pops a Settings sub-flow (Move-Account / sheet / QR) → TC-226-17 (designed `isCurrent` guard).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Record `git status --short` (dirty tree pre-exists: orbit arc-layout, graphify meta, 224/225 docs — do not revert).
2. Create the `SettingsOrbitNavButton` STUB first (empty 52×52 box, onTap wired; compile anchor ONLY — mounted NOWHERE in production, so it carries zero behavior). Files A/B/C reference the type and need it to compile.
3. Add RED tests: Files A, B, C + the File D case. Run the RED gate below; confirm each fails for its documented BEHAVIORAL reason (A recipe assertions red vs the stub; B1/B2 red because Settings still mounts FeedNavigationBar; C/D red because no swipe handler exists; sentinels TC-226-03/10/11/12/13 must be GREEN).
4. Implement the full glass recipe in `SettingsOrbitNavButton` (clone `orbit_search_trigger.dart:26-57`; shadow OUTSIDE ClipOval; tone-adaptive tokens). File A → GREEN.
5. Swap the Settings mount (`settings_screen.dart:297-308`) to `SettingsOrbitNavButton(onTap: () => onSwitchView('orbit'))`; keep the flag gate + Positioned geometry + `:259` padding; remove unused import. Update `settings_screen_test.dart` :150/:246/:307 to the new type AND rename the `'renders FeedNavigationBar'` test at `:147` to match its new target. File B → GREEN. Stop-if: any OTHER existing settings test asserts FeedNavigationBar internals → replan (inventory says none do).
6. Add the swipe seam in `settings_wired.dart` (GestureDetector wrapping the SettingsScreen child of the Scaffold body, gated by `widget.showNavigationBar`; accumulate dx; qualify in onHorizontalDragEnd ONLY: net-rightward AND (≥0.28×width-at-drag-end OR velocity ≥900); fire `_onSwitchView('orbit')` guarded by `mounted` && `ModalRoute.of(context)?.isCurrent == true`). File C + D → GREEN. Stop-if (a): gesture-arena conflict makes vertical scroll flaky (TC-226-12) → switch to the feature-30 raw-Listener pattern (`feed_wired.dart:2376-2479`) instead of GestureDetector — a passive Listener never joins the arena, so it REQUIRES the manual axis-dominance guard (`dx.abs() <= dy.abs() → return`, cf. `:2403`); do not hack thresholds. Stop-if (b): any Settings sub-flow (Move-Account `:700`, `_showSettingsSheet` `:553`, `_runQrEntry` `:539`) is found not to fully occlude the body in TC-226-17(a) → additionally gate the detector off via the existing `_moveRouteActive`/`_qrRouteActive`-style latches; do not rely on occlusion alone.
7. Rerun direct → preservation → named gates (commands below).
8. `graphify update .` AND `./graphify-arch/refresh_arch_graph.sh` (app-owned lib/ changed).
9. Manual visual sanity on an iOS simulator (screenshot): glass render over the settings background + swipe feel. Non-gating but recommended (BackdropFilter look can't be judged on host).

## Risks And Edge Cases
- **Wrong-route pop under Settings sub-flows (TOP consequence risk):** `_onSwitchView` pops the TOPMOST route (`settings_wired.dart:534`), so a swipe handler firing while Move-Account (`:700-717`), a settings modal sheet (`:553-557`), or a QR route (`:539`) is up would pop the sub-flow, not Settings. Occlusion (opaque route / ModalBarrier) already blocks the gesture on today's sub-flows, but safety is made DESIGNED, not accidental: the drag-end handler no-ops unless `ModalRoute.of(context)?.isCurrent == true` — pinned by TC-226-17 including a worst-case non-occluding transparent sub-route leg.
- **Gesture-arena coexistence:** vertical `SingleChildScrollView` vs horizontal recognizer — independent axes, precedent `swipeable_friend_row.dart:236-238`; pinned by TC-226-12 (with the Listener fallback named in step 6).
- **Glass assertion brittleness on host:** assert via `find.byType(SettingsOrbitNavButton)` + descendant matchers, NOT global BackdropFilter counts — Settings has other glass elements (header `settings_screen.dart:206`, copy button `:340`). TC-212-08 proves blur/shadow params are host-assertable.
- **Shared-widget leak:** any edit to `feed_navigation_bar.dart`/`nav_bar_button.dart` breaks 5 locked suites — scope guard forbids it; sentinels catch it.
- **Ripple loss:** the glass button uses GestureDetector (no InkWell ripple) — matches the search trigger's behavior; deliberate.
- **`activeTab` becomes decorative on SettingsScreen** — kept for API stability; remove in a later cleanup if desired.

## Device/Relay Proof Profile
host-only for closure (pure Flutter UI + in-app gesture; no OS boundary — the swipe is our own GestureDetector, fully exercisable by WidgetTester; no DB, no crypto, no relay).
Closure scenario: none required. Manual (non-gating) visual sanity: build to an iOS sim, screenshot Settings (dark + daylight), verify glass look + swipe feel.
Deferred device work → none.

## Acceptance Gates  (literal — copy/paste)
```bash
# RED (after the unmounted stub widget exists, before any behavior-bearing production edit) — must FAIL for the documented reasons
flutter test test/features/settings/presentation/widgets/settings_orbit_nav_button_test.dart \
             test/features/settings/presentation/screens/settings_navbar_test.dart \
             test/features/settings/presentation/screens/settings_swipe_back_test.dart
# expect: TC-226-04/05 red vs stub (recipe absent); TC-226-06 label-leg red; TC-226-01/02 red (Feed present / glass button unmounted); TC-226-07/08/09/14/15 red (no pop); sentinels TC-226-03/10/11/12/13/17 GREEN
flutter test test/features/orbit/presentation/screens/orbit_settings_entry_test.dart --plain-name 'TC-226-16'
# expect: FAIL (Settings still mounted after fling)

# Direct GREEN (after fix)
flutter test test/features/settings/presentation/widgets/settings_orbit_nav_button_test.dart   # expect 3/3
flutter test test/features/settings/presentation/screens/settings_navbar_test.dart             # expect 3/3
flutter test test/features/settings/presentation/screens/settings_swipe_back_test.dart         # expect 10/10
flutter test test/features/orbit/presentation/screens/orbit_settings_entry_test.dart           # inventory pre-existing count N at execution; expect N+1 (existing + TC-226-16)

# Preservation sentinels (must stay green, zero edits to these production widgets)
flutter test test/features/settings/                                                           # expect 0 failures (incl. updated settings_screen_test)
flutter test test/features/feed/presentation/widgets/feed_navigation_bar_test.dart \
             test/features/feed/presentation/widgets/nav_bar_button_test.dart \
             test/features/feed/presentation/widgets/nav_bar_button_tone_test.dart             # expect 0 failures (shared defaults untouched)
flutter test test/features/orbit/presentation/widgets/orbit_search_trigger_test.dart           # expect 0 failures (reference untouched)
flutter test test/features/push/application/intro_notification_orbit_route_test.dart \
             test/features/theme/dark_preset_preservation_test.dart                            # expect 0 failures (INV-5 leak sentinels — these live outside settings/feed dirs and in NO curated array, so no other listed command runs them)

# Named gates for the touched surfaces
./scripts/run_test_gates.sh feed      # FEED_TESTS: expect 0 failures
./scripts/run_test_gates.sh groups    # GROUP_TESTS (orbit_settings_entry etc.): expect 0 failures

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED before fix: TC-226-01/02/04/05/06/07/08/09/14/15/16 (File A red vs the unmounted step-2 stub — recipe assertions fail; the stub itself is a compile anchor with zero production behavior).
- Expected test UPDATE (not regression): `settings_screen_test.dart` :150/:246/:307 go red at step 5 until their `byType` target is updated — part of the planned edit, not scope drift.
- Pre-existing dirty tree: orbit arc-layout/visualization, graphify meta files, 224/225 docs, main.dart push-envelope staging — unrelated; do not revert.
- Environment blocker (NOT product): no iOS simulator available for the optional visual sanity — does not block host closure.
- Scope drift (BLOCKING): ANY diff in `feed_navigation_bar.dart`, `nav_bar_button.dart`, `nav_bar_theme.dart`, `orbit_search_trigger.dart`, `settings_route_transition.dart`, or `feed_wired.dart` swipe code.

## Done Criteria
- [x] RED added first, failed for the expected reasons (catalog above).
- [x] Mutation-verified: every production edit has a named re-red revert (matrix column).
- [x] Direct GREEN (A 3/3, B 3/3, C 10/10, D at N+1) + preservation sentinels (incl. the push/theme leak-sentinel line) + `feed`/`groups` gates pass.
- [x] No DB change (no migration test needed) — confirmed.
- [x] Host-only closure justified (no OS boundary); optional sim screenshot explicitly skipped.
- [x] All new tests auto-glob (`test/features/**`) — verified present in `./scripts/run_host_test_gates.sh feature-host-all --list`; D1 rides the existing GROUP_TESTS entry.
- [x] flutter analyze 0 new in touched files; git diff --check clean; no Scope Guard violations. Repo-wide `flutter analyze` remains red from pre-existing unrelated debt.
- [x] graphify full graph updated + arch graph refreshed after code changes.

## Scope Guard (hard "Do not")
- Do not modify `FeedNavigationBar`, `NavBarButton`, or `NavBarTheme` (shared defaults; 5 suites lock them).
- Do not remove the Feed button for Feed/Orbit/Posts surfaces — Settings-only via the widget swap.
- Do not swap `buildSettingsSlideUpRoute` to MaterialPageRoute/CupertinoPageRoute (206 slide-up enter is deliberate).
- Do not touch `orbit_search_trigger.dart` (read-only reference) or feature-30 host-swipe code in `feed_wired.dart`.
- Do not add swipe or navbar behavior to the Posts-entry Settings (`showNavigationBar:false` path stays inert).
- Do not add interactive drag-tracking of the route transition (out of scope; future polish).

## Accepted Differences / Intentionally Out Of Scope
- Icon-only glass button (no 11px 'Orbit' label, unlike NavBarButton) — mirrors the search trigger; a11y preserved via Semantics label (locked by TC-226-06).
- No badge on the Settings orbit affordance — Settings never passed badge counts (defaults 0), so behavior is identical; if orbit badges are later wanted on Settings, a follow-up owns it.
- Swipe direction is PHYSICAL left→right, incl. RTL (locked by TC-226-14) — revisit only if RTL UX feedback demands mirroring.
- Pop uses the existing 280ms exit animation, not finger-tracked (future polish session).
- No shared GlassCircleButton extraction (avoids risking TC-212 locks); duplication of ~20 styling lines accepted, source-commented to the trigger recipe.

## Dependency Impact
- None inbound: no session depends on the Settings navbar shape. Outbound: any future "Settings badge/notification" work must target `SettingsOrbitNavButton` instead of FeedNavigationBar badge params. The 221/222 background-tone work is compatible — the button consumes `BackgroundReadableColors`, so tone changes flow through automatically.

## Reviewer Findings
**External audit applied (2026-07-09, `226-review-fixlist.md`, 7-agent workflow `wf_a05c3362-ab0`, verdict READY-WITH-TIGHTENING — both material findings and one nit re-verified in real source before applying, since the audit contradicted the original grounding workflow's `:702` claim):**
- **APPLIED M1 (was material):** the TC-226-07/08 tab discriminator was vacuous — `AppShellController` defaults `initialTab` to orbit (`app_shell_controller.dart:26-33`) and `switchTo` no-ops on same-tab (`:41-48`), so "tab == orbit" was entry-satisfied and a bare-pop handler passed identically. Fixed: harness seeds `initialTab: AppShellTab.feed`, assertions require the feed→orbit TRANSITION, bare-pop mutation added.
- **APPLIED M2 (was material; source-confirmed):** the plan's "nested SettingsWired at `settings_wired.dart:702`" claim was FALSE — `:700-717` pushes `AccountMigrationJourneyWired.oldPhone`. Real sub-flows (Move-Account / `_showSettingsSheet` sheets `:553-557` / `_runQrEntry` `:539`) create a wrong-route-pop hazard since `_onSwitchView` pops the topmost route. Fixed: false claim deleted (Blind-Spot + Risks rewritten), designed `ModalRoute.isCurrent` guard added to the handler, TC-226-17 guard test added (occlusion leg + non-occluding transparent-route leg), step-6 Stop-if (b) added. NOTE: the audit's literal B2 mutation ("move the GestureDetector above the sub-route barrier") is not an implementable mutation of this code — replaced with the implementable "remove the `isCurrent` guard → transparent-route leg pops the wrong route".
- **APPLIED T1:** end-firing committed (latch language dropped — `onHorizontalDragEnd` fires once per gesture, so "remove the latch" could never re-red); TC-226-15 mutation rewritten to fire-on-update.
- **APPLIED T2:** TC-226-04 now asserts the BoxShadow on the outer UNCLIPPED ancestor of the ClipOval + shadow-moved-inside mutation.
- **APPLIED T3 (partial):** `intro_notification_orbit_route_test.dart` + `dark_preset_preservation_test.dart` bound to a literal preservation command (they live outside settings/feed dirs and in no curated array). **REJECTED the T3 sub-claim** that the 206 slide-up-enter test is unbound — `orbit_settings_entry_test.dart` (which contains TC-206-01) already runs in the Direct-GREEN full-file command AND in `./scripts/run_test_gates.sh groups`.
- **APPLIED T4:** the three File-A matrix RED cells rewritten to behavioral stub-first reasons.
- **APPLIED T5:** TC-226-16 reopen leg got its own mutation (neuter the `whenComplete` latch-release, `orbit_wired.dart:682-684`).
- **APPLIED N1–N5:** `:147` test rename in step 5; orbit_settings_entry pinned to N+1 at execution; TC-226-06 half-red noted; wrap point clarified (SettingsScreen inside the wired Scaffold body); 224px/MediaQuery-at-drag-end authoring note on TC-226-09.
- **REJECTED N6 (tap-through sentinel):** redundant — existing `settings_wired_test.dart` tap tests (copy peer ID `:414`, back button `:881`) pump SettingsWired and therefore exercise the wrapped tree in the `flutter test test/features/settings/` preservation run; a dedicated sentinel adds no new failure mode. The fling-start-point hint was folded into TC-226-09's authoring note.
- Two user-owned product decisions surfaced by the audit remain OPEN for confirmation before execution (recorded in Accepted Differences): discrete over-threshold gesture (not finger-tracked interactive pop) and PHYSICAL swipe direction under RTL.

Sufficiency checklist run 2026-07-09 (planner self-check, all gates; re-run after audit application): spec-case totality — SC-1/2/3 each map to ≥1 named row (17 rows total); every INV locked; every edit mutation-verified (matrix column complete); sentinels (TC-226-03/10/11/12/13) are documented GREEN-on-HEAD guards with named non-vacuous mutations; no DB → migration gate N/A; no OS-boundary/crypto/relay → host closure justified, PROD-CRITICAL end-to-end leg named (TC-226-16 full route stack; no wire/transport leg exists in a UI-only change); preservation sentinels named with commands; gates literal; registration column complete (all AUTO-glob; D1 pre-registered in GROUP_TESTS); known-failure interpretation + dirty-tree snapshot planned; blind-spot sweep: 4/4 answered (2 covered by rows, 2 justified N/A); refuted-findings section records the ruled-out mechanisms (none already-fixed). Zero empty matrix cells. Verdict: SUFFICIENT.

## Arbiter Decision
Structural blockers: none. | Deferred details: exact accessor for BackgroundReadableColors in the new widget (executor mirrors OrbitSearchTrigger). RESOLVED during audit application: AppShellController tabs are `String` constants via `AppShellTab` with an `initialTab` ctor param (`app_shell_controller.dart:21-48`). | Accepted differences: as listed above; two user-owned decisions (discrete vs finger-tracked swipe; physical vs mirrored RTL direction) to confirm before execution.

## Final Execution Verdict
Verdict: `accepted_with_explicit_follow_up`.

Files changed for plan 226:
- Production: `lib/features/settings/presentation/widgets/settings_orbit_nav_button.dart`, `lib/features/settings/presentation/screens/settings_screen.dart`, `lib/features/settings/presentation/screens/settings_wired.dart`.
- Tests: `test/features/settings/presentation/widgets/settings_orbit_nav_button_test.dart`, `test/features/settings/presentation/screens/settings_navbar_test.dart`, `test/features/settings/presentation/screens/settings_swipe_back_test.dart`, `test/features/settings/presentation/screens/settings_screen_test.dart`, `test/features/orbit/presentation/screens/orbit_settings_entry_test.dart`.
- Documentation/graphs: this plan ledger plus required generated graph outputs from `graphify update .` and `./graphify-arch/refresh_arch_graph.sh`.

Tests/gates run:
- RED: combined new Settings suites failed for expected reasons after the compile-anchor stub; `orbit_settings_entry_test.dart --plain-name 'TC-226-16'` failed because Settings stayed mounted after fling.
- Direct GREEN: File A `3/3`, File B `3/3`, File C `10/10`, full `orbit_settings_entry_test.dart` `15/15`.
- Preservation: `flutter test test/features/settings/` `218/218`; feed navbar/nav-button suites `28/28`; `orbit_search_trigger_test.dart` `5/5`; push/theme leak sentinels `8/8`.
- Named gates: `./scripts/run_test_gates.sh feed` `307/307`; `./scripts/run_test_gates.sh groups` `1184/1184`.
- Hygiene: focused `flutter analyze` on touched Dart files passed; `flutter test test/features/settings/presentation/screens/settings_swipe_back_test.dart` rerun after formatting passed `10/10`; `git diff --check` passed.
- Registration: `./scripts/run_host_test_gates.sh feature-host-all --list` passed discovery and lists the new auto-glob tests; full `feature-host-all` execution was not run because it expands to 673 commands and was not a literal acceptance gate.

QA verdict: independent QA Reviewer agent `019f4898-c199-7b70-9dbc-8caa809b261a` accepted with explicit follow-up and found no blocking issues. Spawned Executor isolation was attempted twice; both Executor agents timed out after bounded waits and left only a coherent compile-anchor stub/no-progress state, so local sequential fallback completed RED-first implementation and verification before QA.

Blocking issues: none.

Non-blocking follow-ups:
- Repo-wide `flutter analyze` still fails with pre-existing unrelated debt; touched-file focused analyze is clean.
- Optional manual iOS visual sanity screenshot was skipped under host-only closure.
- Full `feature-host-all` execution remains optional broad proof beyond the plan's literal acceptance gate set.
