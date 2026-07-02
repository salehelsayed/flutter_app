# 193 - Orbit Screen Split: Inner-Circle Default View + Toggleable Classic "All Chats" View (Feature Improvement)

Status: awaiting-review
Spec: Test-Flight-Improv/193-orbit-inner-circle-default-view-split-spec.md

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-02 | Evidence Collector (4-sweep workflow + critic) | orbit_wired.dart, orbit_screen.dart, feed_wired.dart, main.dart, orbital_visualization.dart, expandable_fab.dart, all orbit/feed test files, run_test_gates.sh, run_host_test_gates.sh, check_reliability_simulation_discovery.sh | live target = lib/features/orbit/ (orbit2/3 are kDebugMode mock prototypes); top-left virgin in LTR+RTL; reset seam = initState + `_onAppShellChanged` rising edge :466 | verify→refute |
| 2026-07-02 | Verifier/Refuter (10 claims × verify + adversarial refute) | same + l10n, theme, sims | ALL 10 claims verified, 0 refuted; corrections folded in (see Root Cause) | derive obligations |
| 2026-07-02 | Reviewer (sufficiency) | this plan vs references/sufficiency-checklist.md | 42/42 spec TCs mapped; 0 empty matrix cells; no DB migration; no device-proof needed | hand off |
| 2026-07-02 | Arbiter | — | design decisions fixed below (ValueKey, l10n keys, param defaults, design locks); no structural blockers | hand off to execution |

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
- Spec / intent: Test-Flight-Improv/193-orbit-inner-circle-default-view-split-spec.md
- Gate definitions: scripts/run_test_gates.sh (script wins over prose — gate docs verified STALE: test-gates-reference.md:187 counts predate current arrays; definitions:31 contradicts run_test_gates.sh:227)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready

## Exact Problem Statement

The shipped Orbit tab (`OrbitWired` → `OrbitScreen`, the only production Orbit — orbit2/orbit3 are `kDebugMode` mock prototypes, orbit2_prototype.dart:14 / orbit3_prototype.dart:16) welds two surfaces into one Column (orbit_screen.dart:338-453): the Inner-Circle visualization header (collapsible block :342-393 hosting `OrbitalVisualization` :367-374 + "Close Friends" caption :375-388) and the classic all-chats list (`Expanded > CustomScrollView` :396-453 with `FriendsListHeader` QR pills :417, `FriendsFilterToggle` :424-430, intro banner :433-435, merged friend+group `SliverList` :696-711). Product decision (user-confirmed): the Orbit screen shows ONLY the Inner-Circle view by default; the all-chats list becomes a separate alternative view; a top-left button toggles bidirectionally; EVERY entry into Orbit (cold start, nav tap, edge swipe, tab re-entry) resets to Inner-Circle — no persistence, in-session or across launches. Exception (hard constraint): the intro-notification route (`initialFilterTab: 'intros'`, main.dart:4291) must land on the all-chats/intros surface or pending intros become unreachable from notifications.

What must improve: default Orbit = Inner-Circle only; toggle at top-left; all list-coupled affordances (rows, filters, intro banner, QR pills, search, swipe actions, empty states) travel to the all-chats view; reset on every entry.
What must stay unchanged (→ preserved-green sentinels): `OrbitalVisualization` internals (rings 5/8/13, overflow badge, avatar-tap-opens-chat); plan-163 off-screen invariants (dirty buckets + `_replayDirtyOrbitWork`); Feed↔Orbit host-swipe + row-action gating contracts; orbit nav badge via BOTH producer paths; contact-request modal (surface-independent); conversation-notification routing (never through Orbit); feed scroll survival; orbit2/orbit3 prototypes + source guards.

## Root Cause (verify → refute confirmed)

Not a bug — a structural feature change. The mechanism that must change, all claims verified on HEAD and survived adversarial refutation (10/10, 0 refuted):

- **Welded surfaces**: both surfaces render unconditionally in one Column (orbit_screen.dart:338-453); the ONLY header-hide mechanism is the search-bound `_collapseController` (`Align(heightFactor: t)` :349-351; writers exactly `_onSearchOpen` animateTo(0) orbit_wired.dart:1764 and `_onSearchClose` animateTo(1.0) :1776; `_onScroll` :1743-1759 touches only the search trigger). NO view-mode state exists anywhere in lib/features/orbit (exhaustive grep).
- **Reset seam** (the exact hook points for "every entry"): the embedded OrbitWired is latched-alive forever (`_hasMountedOrbitHost`, feed_wired.dart:305/375/2287-2294/2481-2484 — three monotonic-true writers, no unmount), so initState fires ONCE; tab re-entry is observable ONLY at the rising edge `if (isActive && !_wasOrbitActive)` in `_onAppShellChanged` (orbit_wired.dart:466), which currently calls `_replayDirtyOrbitWork()` (:467, replay bodies :476-499). Mount-while-active seeds `_wasOrbitActive = _isOrbitActive` at initState:413 (no edge on first entry) → the reset must ALSO be the initState default. The standalone intro route constructs a fresh OrbitWired per push (main.dart:3423-3425, no key) with `initialFilterTab: 'intros'` (:4291) — construction-time signal suffices there; `widget.initialFilterTab` is read exactly once (initState :374).
- **Top-left is virgin in LTR AND RTL**: no AppBar anywhere in the chain; `ExpandableFab` uses plain physical `Positioned(top: safeAreaPadding.top + 8, right: 16)` (expandable_fab.dart:123-132, zero `PositionedDirectional` in file) so it does NOT mirror under RTL. Consequence: the new toggle must be plain physical `Positioned(left: 16)` — a directional position would land on physical right under RTL and collide with the non-mirroring FAB. When the FAB menu is open, its full-screen scrim (`Key('expandable_fab_scrim')`, expandable_fab.dart:146-155) covers the toggle — accepted.
- **Persistent nav is universal in production**: both mounts (feed_wired.dart:2528-2529; main.dart:4287-4288) pass non-null `appShellController` + `feedUnreadCountListenable` → `showPersistentNav` true (orbit_wired.dart:2186-2188) → `_showsPersistentNav` true (orbit_screen.dart:265). The X-close/floating-search branch (:461-492) is production-unreachable (reachable in tests via bare OrbitScreen or shell-less OrbitWired pumps).
- **Badge topology**: Path A = `projection.reviewCount` (computed orbit_wired.dart:319, consumed orbit_screen.dart:295-325); Path B = `_refreshOrbitBadgeCount` (feed_wired.dart:528-589, six ungated triggers :433/:597/:608/:1307/:1724/:1736). The intros route is a THIRD consumer of Path A (nav+badge render there too).
- **Background-kind notifications**: `_onAppShellChanged` fires on every controller notification, but the :466 edge requires an actual inactive→active transition, so a background-kind notify while orbit is active cannot spuriously reset — lock it anyway (pure-additive, mutation-verified).

Refuted / do-NOT-re-introduce (corrections found during verify→refute — do not plan against these wrong beliefs):
- "The intro-notification standalone Orbit shows an X-close and no nav" — FALSE on HEAD; it shows persistent nav + badge (locked by intro_notification_orbit_route_test.dart:98,133-134).
- "The intros route never shows the nav badge" (a verifier sub-claim) — FALSE; refuter disproved it (main.dart:3416/4287-4288 → showPersistentNav true).
- "RTL mirrors the FAB to the left" — FALSE (physical Positioned).
- "Line range 291-337 for the dual-caption lock" — actual test body 291-346; assertions 331-337; it is a color-SET containment (`textPrimary` AND `textMuted`), not findsNWidgets(2).
- intro_notification_orbit_route_test CANNOT lock TC-193-06 — its harness hardcodes `OrbitViewProjection(filterTab: 'intros')` on a bare OrbitScreen (:214-216, :247-279); the real lock must pump the REAL OrbitWired.

## Real Scope

In scope (design decisions FIXED by this plan):
1. `lib/features/orbit/domain/models/orbit_view_mode.dart` — NEW `enum OrbitViewMode { innerCircle, allChats }` (precedent: orbit2_view_mode.dart dedicated domain enum).
2. `orbit_wired.dart` — NEW `_viewMode` field in `_OrbitWiredState`; initState: `_viewMode = widget.initialFilterTab != null ? OrbitViewMode.allChats : OrbitViewMode.innerCircle` (**DESIGN LOCK: `initialFilterTab != null` ⇒ all-chats view** — carries the intro route, ~24 `initialFilterTab:'intros'/'archived'` tests, and the INVITE_ACCEPT_SPINNER sim); NEW `_onToggleView()`; rising-edge reset inside the existing `:466` block: `_viewMode = OrbitViewMode.innerCircle` + close/clear search state, WITHOUT skipping `_replayDirtyOrbitWork()`; `_filterTab` deliberately NOT reset (test-locked asymmetry); pass `viewMode` + `onToggleView` into OrbitScreen.
3. `orbit_screen.dart` — OPTIONAL ctor params `OrbitViewMode viewMode = OrbitViewMode.allChats` (bare-pump compile+behavior compat: 4 direct constructors exist — orbit_screen_loading_test.dart:85-176, orbit_screen_archived_groups_test.dart:56-115, intro_notification_orbit_route_test.dart:247-279, orbit_performance_harness.dart:192-221) and `VoidCallback? onToggleView` (toggle renders only when non-null → bare pumps unaffected). innerCircle mode: header surface (expanded; collapse animation ignored/inert), toggle, FAB, nav, contact-request dialog reachable; NO list/search/QR/filters/banner. allChats mode: list surface + toggle; NO viz header.
4. `lib/features/orbit/presentation/widgets/orbit_view_toggle_button.dart` — NEW 40px button, **`ValueKey('orbit-view-toggle')`** (precedent `orbit3-view-toggle`), plain physical `Positioned(top: MediaQuery.padding.top + 8, left: 16)`, Semantics label flips per state.
5. l10n — NEW keys `orbit_view_toggle_to_list`, `orbit_view_toggle_to_circle`, `orbit_inner_circle_empty_hint` in app_en.arb + app_ar.arb + app_de.arb, then `flutter gen-l10n` (generated AppLocalizations are committed — feed_strings_parity_test imports them). Hardcoded literals would fail l10n_integrity_test's lib/features scan.
6. Zero-contacts empty state on the Inner-Circle view (`orbit_inner_circle_empty_hint` under the circle) — 'all' tab has NO empty state today (childCount-0 fallthrough orbit_screen.dart:696-711); the Inner-Circle view must not be a blank screen.
7. Test updates: 1 new widget test file, 2 superseded-lock rewrites, ~30 mechanical preambles via ONE shared helper, 2 sim insertions, perf harness passes `viewMode: OrbitViewMode.innerCircle` explicitly.

Out of scope (Scope Guard below): inner-circle membership semantics (positional top-13 unchanged), OrbitalVisualization internals, AppShellTab model/nav-bar buttons, orbit2/orbit3, view-mode persistence (explicitly rejected), conversation-notification routing, feed screen, removing the production-unreachable X-close branch (flag as follow-up, do not delete here).

## Files To Inspect Next
Production: lib/features/orbit/presentation/screens/orbit_wired.dart (:216, :372-418, :447-499, :1743-1797, :2184-2244), orbit_screen.dart (:265, :328-584, :662-712), lib/features/orbit/presentation/widgets/ (new toggle), lib/features/orbit/domain/models/ (new enum), lib/l10n/app_{en,ar,de}.arb.
Direct tests: test/features/orbit/presentation/screens/orbit_wired_test.dart (helpers :250-371), NEW orbit_view_split_test.dart, orbit_screen_loading_test.dart (:291-346, :444-460), test/features/feed/presentation/screens/feed_wired_test.dart (:274-288 helpers, :926-989), feed_swipe_test.dart, test/l10n/ (new parity test).
Integration: integration_test/cold_start_message_render_simulator_test.dart (:259, :339-377), group_delete_preserves_friends_simulator_test.dart (:282-304), group_invite_accept_spinner_simulator_test.dart (:200-201), orbit_performance_harness.dart (:192-221).
Dependency-only: feed_wired.dart (:2481-2541, :2692-2754), main.dart (:3406-3432, :4248-4297), expandable_fab.dart (:123-155).

## Existing Tests Covering This Area
- orbit_wired_test.dart (70 testWidgets; GROUP_TESTS run_test_gates.sh:227): ~30 default-view list tests need the toggle preamble; ~24 `initialFilterTab` tests survive via the design lock; TC-163-10/10b + avatar-semantics + dialog tests unaffected.
- feed_wired_test.dart (48; FEED_TESTS :182): search-survival lock :926-989 SUPERSEDED (rewrite); :859 feed-scroll + :555-856 badge tests are sentinels; :1075 row-swipe needs preamble.
- orbit_screen_loading_test.dart (10; auto-glob only): 'daylight lagoon…readable' :291-346 SUPERSEDED (dual-caption color set :331-337); :444-460 partial restatement.
- orbit_screen_archived_groups_test.dart (10, bare OrbitScreen): green via the allChats param default.
- intro_notification_orbit_route_test.dart (2; NO curated array — auto-glob only): kept as chrome sentinels; cannot lock TC-193-06 (harness hardcodes the projection).
- orbital_visualization_test.dart (11): isolated, safe — TC-193-20 sentinel.
- Sims: cold_start (classify_path :284-289, BOTH 1to1+group suites); group-lifecycle scenario libs are `support` (:328-334) dispatched via harness (:313-316) + GROUP_LIFECYCLE_SIM_SCENARIOS (run_test_gates.sh:348-353); ORBIT perf target (:339, dispatch :472-474).
Missing coverage gaps: no test exists for any view-mode behavior (feature is new); no OrbitWired-level lock that `initialFilterTab:'intros'` lands on the intros surface with zero taps.
Already in curated arrays: orbit_wired_test→GROUP_TESTS:227; feed_wired_test→FEED_TESTS:182; feed_swipe_test→FEED_TESTS:178; app_shell_controller_test→FEED_TESTS:190.

## RED Test Catalog (add BEFORE any production code — INV-RED-FIRST)

New file **test/features/orbit/presentation/screens/orbit_view_split_test.dart** (copy `buildOrbitWired`/`pumpOrbitFrames` idioms from orbit_wired_test.dart:250-371; do NOT bloat the 4904-line file). Shared helper to add beside pumpOrbitFrames in orbit_wired_test.dart: `Future<void> switchToAllChats(WidgetTester t) async { await t.tap(find.byKey(const ValueKey('orbit-view-toggle'))); await pumpOrbitFrames(t); }`.

1. `orbit_view_split_test.dart::'default entry shows only the Inner-Circle surface'` (TC-193-25 — **purest RED, no key dependency**)
   - Tier: widget. Shape: buildOrbitWired with friends+groups+intros loaded.
   - RED on HEAD: `find.byType(FriendRow)/GroupRow/FriendsFilterToggle/FriendsListHeader/OrbitSearchTrigger` all findsNothing + intro-banner text findsNothing — every findsNothing FAILS (all mounted in one Column, orbit_screen.dart:338-453).
   - GREEN: those absent + `find.byType(OrbitalVisualization)` findsOneWidget.
   - Mutation: revert OrbitWired passing `viewMode` (or OrbitScreen branching) → red.
2. `orbit_view_split_test.dart::'top-left toggle switches to the all-chats view'` (TC-193-10)
   - RED: `find.byKey(ValueKey('orbit-view-toggle'))` findsNothing on HEAD.
   - GREEN: tap toggle → FriendRow/FriendsFilterToggle/FriendsListHeader visible, OrbitalVisualization findsNothing; toggle rect top-left (dx < screen/2, dy < 120).
   - Mutation: revert toggle mount → red.
3. `orbit_view_split_test.dart::'toggle returns to the Inner-Circle view'` (TC-193-11) — RED: key missing. GREEN: second tap restores viz, list gone. Mutation: revert `_onToggleView` flip → red.
4. `orbit_view_split_test.dart::'rapid toggling lands deterministically'` (TC-193-12) — 5 taps without settling → parity = allChats; no exception. RED: key missing. Mutation: revert toggle handler → red.
5. `orbit_view_split_test.dart::'RTL keeps the toggle clear of the FAB'` (TC-193-13) — `buildOrbitWired(locale: Locale('ar'))` (param :273); assert toggle rect does NOT intersect ExpandableFab rect and toggle dx < FAB dx. RED: key missing. Mutation: change toggle to `PositionedDirectional` → red (rects collide under RTL).
6. `orbit_view_split_test.dart::'toggle semantics label flips per view'` (TC-193-15) — `find.bySemanticsLabel` for the to-list label on innerCircle, to-circle label after toggling (idiom: 'Open chat with Bob', orbit_wired_test:2532). RED: no such semantics on HEAD. Mutation: swap the two l10n keys → red.
7. `orbit_view_split_test.dart::'create-group FAB lives on the Inner-Circle view'` (TC-193-23) — RED via conjunction: `ExpandableFab findsOneWidget AND FriendRow findsNothing` (2nd conjunct fails on HEAD). Mutation: drop FAB from innerCircle branch → red.
8. `orbit_view_split_test.dart::'nav badge is live on the Inner-Circle view'` (TC-193-24) — appShellController+feedUnreadCountListenable, 2 pending intros → orbit NavBarButton badgeCount 2 AND FriendRow findsNothing. RED: conjunction. Mutation: gate `_buildNavigationBar` on allChats → red.
9. `orbit_view_split_test.dart::'zero contacts shows a meaningful Inner-Circle state'` (TC-193-26) — 0 friends/groups, loaded flags true (note: `_activeGroupsLoaded = !hasGroupSurfaces` orbit_wired.dart:375-378). RED: `orbit_inner_circle_empty_hint` text findsNothing on HEAD (key doesn't exist). GREEN: hint + toggle functional + no exceptions. Mutation: revert hint → red.
10. `orbit_view_split_test.dart::'incoming message re-ranks the rings while the list stays absent'` (TC-193-27) — stream idiom from orbit_wired_test:1324; friend outside top-13 messages → its `'Open chat with <name>'` semantics appears AND FriendRow findsNothing. RED: 2nd conjunct fails on HEAD. Mutation: revert header-projection publish on refresh → red.
11. `orbit_view_split_test.dart::'non-null initialFilterTab forces the all-chats view'` (design lock + TC-193-06) — `buildOrbitWired(initialFilterTab: 'intros', appShellController…, feedUnreadCountListenable…)`; assert intro row visible with ZERO taps AND `OrbitalVisualization` findsNothing.
    - RED on HEAD: OrbitalVisualization IS present on the intros surface today (stacked header) — findsNothing fails.
    - Mutation: revert the initState `initialFilterTab != null` branch → red. Discriminator: viz-absence distinguishes "landed on all-chats view" from today's "intros filter under a stacked header".
12. `orbit_view_split_test.dart::'a fresh mount defaults to Inner-Circle even after a prior toggle'` (TC-193-05) — pump, toggle to allChats, `pumpWidget` a brand-new OrbitWired → Inner-Circle. RED: key missing + list-on-default. Mutation: persist/lift `_viewMode` out of State → red. (Real cold-restart proof = catalog #20.)
13. `orbit_view_split_test.dart::'re-entry reset preserves the filter tab'` (deliberate asymmetry lock; blind-spot row) — appShellController; toggle→allChats→tap 'Archived'→switchTo(feed)→switchTo(orbit) ⇒ Inner-Circle; toggle again ⇒ archived filter still active. RED: key missing. Mutation: reset `_filterTab` in the rising edge → red.
14. `orbit_view_split_test.dart::'background-kind controller notify does not reset the view'` (TC-193-43 additive) — toggle→allChats; fire a background-kind notification (AppShellChangeKind.background) while orbit active ⇒ still allChats. No feasible RED (no view exists on HEAD) — **mutation-verified instead**: mutate the reset to run on EVERY `_onAppShellChanged` call (drop the :466 edge guard) → this test red.
15. `orbit_wired_test.dart::'pop back from a conversation stays on the all-chats view'` (TC-193-04) — extend friend-tap-pushes-route idiom (:2465) with wrapInNavigator; toggle→tap Bob→pop ⇒ FriendRow still visible, viz absent. RED: key missing + post-pop viz-absence fails on HEAD. Mutation: reset view in route-pop path → red.
16. **REWRITE** `feed_wired_test.dart:926 'orbit search state survives an inline host tab round trip'` → `'orbit re-entry resets to the Inner-Circle view (search state does not survive)'` (TC-193-50 + TC-193-03)
    - Shape: buildFeedWired → Orbit → toggle → open search, type 'Bo' → Feed → Orbit.
    - RED on HEAD twice: no toggle key AND the old behavior holds (final asserts :985-988 pass — Bob findsWidgets / TextField 'Bo').
    - GREEN: Inner-Circle view on re-entry; `orbitSearchField()` findsNothing; `orbitScopedText('Bob')` findsNothing (list absent).
    - Mutation: revert the rising-edge reset (:466 block) → red. **This is the ONLY test that proves the reset fires on the inline-tab-switch path (latched host, feed_wired.dart:2481-2484) — initState alone cannot satisfy it.**
17. `feed_wired_test.dart::'orbit nav tap lands on the Inner-Circle view'` (TC-193-01) — after `feedOrbitNavLabel()` tap: viz findsOneWidget inside OrbitWired, FriendsFilterToggle/FriendRow findsNothing. RED on HEAD: list present. Mutation: revert initState default → red.
18. `feed_swipe_test.dart::'swipe entry lands on the Inner-Circle view'` (TC-193-02) + `::'toggle tap does not move the Feed↔Orbit pane'` (TC-193-16 — tap toggle, assert host translate unchanged + view flipped; drag from toggle follows host contract). RED: list-on-entry / key missing. Mutation: revert reset / toggle mount → red.
19. **REWRITE** `orbit_screen_loading_test.dart:291 'daylight lagoon keeps visible orbit content readable'` (TC-193-52) — split per view: innerCircle pump ⇒ exactly the textMuted caption; allChats pump ⇒ exactly the textPrimary header title. The HEAD assertion (:331-337 color-SET contains BOTH) is impossible post-split. Also restate :444-460 chrome expectations per-view. Mutation: render caption on allChats too → the "exactly one" assertion red.
20. **SIM INSERTION** `integration_test/cold_start_message_render_simulator_test.dart` `_runOrbitSessionAndOpenThreads` (:259 — single insertion point, covers both sessions) (TC-193-51, **PROD-CRITICAL closure leg**)
    - After the populate loop (:339-342): `expect(find.text(aliceContactName), findsNothing, reason: 'default entry must be the Inner-Circle view');` then `await tester.tap(find.byKey(const ValueKey('orbit-view-toggle'))); await tester.pumpAndSettle();` — rest unchanged (:344-377). Toggle is mandatory: group names have no orbital avatar (viz is friends-only, orbital_visualization.dart:20).
    - RED on HEAD: the findsNothing pre-assert fails (names visible on default).
    - Mutation: revert initState default → red.
21. NEW `test/l10n/orbit_strings_parity_test.dart` (TC-193-14) — lock `orbit_view_toggle_to_list` / `orbit_view_toggle_to_circle` / `orbit_inner_circle_empty_hint` into generated AppLocalizations en/ar/de (precedent feed_strings_parity_test). RED: keys absent from all 3 ARBs + generated files on HEAD. Mutation: delete the ar value → red (parity).
22. `orbit_wired_test.dart` 163-group extension `::'the re-entry view reset does not starve the dirty replay'` (TC-193-40) — feed-active → buffer message from outside-top-13 friend → switchTo(orbit) ⇒ replay ran (spy/`debugOnHeaderBuild` + new friend's semantics in viz) AND view == Inner-Circle. RED: view conjunct fails on HEAD. Mutation: make the reset `return` before `_replayDirtyOrbitWork()` → red (replay starved).
23. `orbit_wired_test.dart` avatar-tap extension `::'avatar-opened chat pops back to the Inner-Circle view'` (TC-193-22) — existing `find.bySemanticsLabel('Open chat with Bob')` idiom (:2532) + post-pop `FriendRow findsNothing`. RED: post-pop conjunct fails on HEAD. Mutation: reset-to-allChats on pop → red.

## Test Coverage Matrix (zero empty cells)

Gate cmd abbreviations: `G` = `./scripts/run_test_gates.sh groups`, `F` = `./scripts/run_test_gates.sh feed`, `FH` = `./scripts/run_host_test_gates.sh feature-host-all`, `HA` = `./scripts/run_host_test_gates.sh host-all`, `SIM1` = `./scripts/run_test_gates.sh reliability-sim 1to1`, `SIMG` = `./scripts/run_test_gates.sh reliability-sim group`, `PERF` = `flutter test --dart-define="PERF_TARGET=ORBIT" integration_test/performance_harness.dart`, `GSIM(X)` = `flutter test --dart-define="GROUP_SIM_SCENARIO=X" -d $FLUTTER_DEVICE_ID integration_test/group_lifecycle_simulator_harness.dart`. Registration: `AUTO` = feature-host-all glob; `GT+` = ADD path to GROUP_TESTS array (run_test_gates.sh:209-238); `in GT/FT` = already listed (GROUP_TESTS:227 / FEED_TESTS:178,182,190).

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Gate | Registration |
|---|---|---|---|---|---|---|---|
| TC-193-01 | shell entry → default view | widget | feed_wired_test::'orbit nav tap lands on the Inner-Circle view' (cat.17) | list present on entry | revert initState `_viewMode` default | F | in FT:182 |
| TC-193-02 | swipe entry → default view | widget | feed_swipe_test::'swipe entry lands on the Inner-Circle view' (cat.18) | list present on entry | revert initState default | F | in FT:178 |
| TC-193-03 | tab re-entry reset | widget | feed_wired_test rewrite (cat.16) | no toggle + search survives today | revert :466 rising-edge reset | F | in FT:182 |
| TC-193-04 | pop-back ≠ entry | widget | orbit_wired_test::'pop back…stays on all-chats' (cat.15) | no toggle; post-pop viz-absence fails | add reset-on-pop → red | G | in GT:227 |
| TC-193-05 | fresh mount default | widget | orbit_view_split_test cat.12 (+ sim cat.20 as real restart) | no toggle; list on fresh mount | persist `_viewMode` → red | G / SIM1 | GT+ / registered :284-289 |
| TC-193-06 | intros route lands on list | widget (real OrbitWired) | orbit_view_split_test cat.11 | viz present on intros surface today | revert `initialFilterTab != null` branch | G | GT+ (existing route test = chrome sentinel, auto-glob) |
| TC-193-07 | conv-notif untouched | integration (existing) | notification_open_ui_smoke_test (classify_path :290-294) — preserved-green sentinel | no feasible RED (path untouched, main.dart:4202-4241) | n/a — sentinel | SIM1 | registered |
| TC-193-10 | toggle → all-chats | widget | orbit_view_split_test cat.2 | toggle key findsNothing | revert toggle mount | G | GT+ |
| TC-193-11 | toggle bidirectional | widget | cat.3 | toggle key findsNothing | revert `_onToggleView` flip | G | GT+ |
| TC-193-12 | rapid-tap safety | widget | cat.4 | toggle key findsNothing | revert handler | G | GT+ |
| TC-193-13 | RTL / FAB clearance | widget | cat.5 (locale ar) | toggle key findsNothing | toggle → PositionedDirectional | G | GT+ |
| TC-193-14 | l10n parity | unit host | test/l10n/orbit_strings_parity_test (cat.21); l10n_integrity_test = preserved-green literal-scan | keys absent in 3 ARBs | delete ar value | G (after GT+) + HA | **GT+ (test/l10n is OUTSIDE feature-host-all — run_host_test_gates.sh:177 only)** |
| TC-193-15 | a11y semantics | widget | cat.6 | no semantics node | swap the two keys | G | GT+ |
| TC-193-16 | gesture arena | widget | feed_swipe_test::'toggle tap does not move the pane' (cat.18) | toggle key findsNothing | make toggle a horizontal-drag consumer | F | in FT:178 |
| TC-193-20 | ring layout unchanged | widget sentinel | orbital_visualization_test (11 tests, isolated) | no feasible RED (out of scope) | n/a — sentinel | FH | AUTO |
| TC-193-21 | blocked excluded | widget sentinel | orbit_wired_test blocked-semantics-absence (~:2638) | no feasible RED (existing) | n/a — sentinel | G | in GT:227 |
| TC-193-22 | avatar tap + pop-back | widget | orbit_wired_test extension (cat.23) | post-pop viz-only conjunct fails | reset-to-allChats on pop | G | in GT:227 |
| TC-193-23 | FAB on inner view | widget | cat.7 | FriendRow-absence conjunct fails | drop FAB from innerCircle branch | G | GT+ |
| TC-193-24 | badge on inner view | widget | cat.8 | list-absence conjunct fails | gate nav on allChats | G | GT+ |
| TC-193-25 | no list-surface leakage | widget | cat.1 (**purest RED**) | all findsNothing fail (welded Column) | revert view branching | G | GT+ |
| TC-193-26 | zero-contacts state | widget | cat.9 | hint key/text absent | revert hint | G | GT+ |
| TC-193-27 | live re-rank on inner view | widget | cat.10 | list-absence conjunct fails | revert header publish on refresh | G | GT+ |
| TC-193-28 | contact-request modal | widget sentinel | orbit_wired_test dialog test (~:1687; ungated, orbit_wired.dart:451-454) | no feasible RED (surface-independent) | n/a — sentinel | G | in GT:227 |
| TC-193-30 | merged list parity | widget regression | orbit_wired_test 'interleaves groups and friends…' (:2035) + `switchToAllChats` preamble | not a RED — preamble row, must stay green | revert toggle → preamble itself fails (guards wiring) | G | in GT:227 |
| TC-193-31 | filter tabs | widget regression | orbit_wired_test :693/:1417/:4115/:4154/:2680 (+ archived_groups bare pumps green via param default) + design-lock test cat.11 | preamble/param rows | revert design lock → cat.11 red | G | in GT:227 |
| TC-193-32 | intro banner | widget regression | archived_groups banner tests (:409/:456) + onIntroBannerTap wiring (orbit_wired.dart:2237) | preamble/param rows | revert banner from allChats view → red | G/FH | AUTO |
| TC-193-33 | QR pills | widget regression | orbit_wired_test 'friends list header shows QR buttons' (:847) + preamble | preamble row | drop FriendsListHeader from allChats → red | G | in GT:227 |
| TC-193-34 | search on all-chats only | widget | orbit_wired_test search tests (:669/:1570/:1646) + preamble; absence half lives in cat.1 (OrbitSearchTrigger findsNothing on inner view) | absence conjunct REDs on HEAD | re-mount trigger on inner view → cat.1 red | G | in GT:227 |
| TC-193-35 | swipe actions + host gating | widget regression | orbit_wired_test delete trio (:2092/:2188/:2403) + feed_wired_test:1075, both preambled | preamble rows | drop rows/`onRowActionOpenChanged` → red | G + F | in GT:227 / FT:182 |
| TC-193-36 | row content | widget regression | orbit_wired_test :2597 (+preamble); friend_row/group_row isolated tests safe | preamble row | n/a — sentinel + preamble | G | in GT:227 |
| TC-193-37 | targeted refresh | widget regression | orbit_wired_test :1324/:1499/:1904 + preamble | preamble rows | break targeted refresh → red (existing locks) | G | in GT:227 |
| TC-193-38 | group lifecycle rows | widget regression | pending-invite set (:3050-:3777, `initialFilterTab:'intros'` → design lock); :742/:1825 preambled | design-lock/preamble rows | revert design lock → set breaks | G | in GT:227 |
| TC-193-40 | off-screen → fresh inner view | widget | 163-group extension (cat.22) | view conjunct fails on HEAD | reset returns before replay → red | G | in GT:227 |
| TC-193-41 | off-screen → fresh list | widget | 163-group extension: re-entry → toggle → buffered rows present | toggle key findsNothing | drop replay of dirty buckets → red | G | in GT:227 |
| TC-193-42 | badge while unmounted | widget sentinel | feed_wired_test badge tests (:555-856; `_refreshOrbitBadgeCount` six ungated triggers) | no feasible RED (path untouched) | n/a — sentinel | F | in FT:182 |
| TC-193-43 | off-screen pause + no spurious reset | widget | TC-163-10/10b (:4255/:4340) + app_shell_controller_test sentinels; NEW cat.14 background-kind lock | cat.14 pure-additive | drop :466 edge guard → cat.14 red | G + F | in GT:227 / FT:190 |
| TC-193-44 | feed scroll survives | widget sentinel | feed_wired_test:859 | no feasible RED | n/a — sentinel | F | in FT:182 |
| TC-193-45 | host swipe thresholds | widget sentinel | feed_swipe_test existing locks | no feasible RED | n/a — sentinel | F | in FT:178 |
| TC-193-50 | superseded search lock | widget rewrite | cat.16 (feed_wired_test:926 rewrite) | old behavior passes on HEAD (inverted) | revert :466 reset → red | F | in FT:182 |
| TC-193-51 | cold-start E2E (real bridge+SQLCipher) | **simulator — PROD-CRITICAL** | cat.20 (cold_start sim, `_runOrbitSessionAndOpenThreads`) | pre-toggle findsNothing fails on HEAD | revert initState default → red | SIM1 + SIMG | registered (classify_path :284-289, both suites); NO new case |
| TC-193-52 | superseded caption lock | widget rewrite | cat.19 (loading_test:291 rewrite + :444 restatement) | dual-caption color set passes on HEAD | render caption on both views → red | FH | AUTO |
| TC-193-53 | perf + lifecycle sims | simulator sentinels | PERF (harness passes `viewMode: innerCircle` explicitly, ctor :192-221); GSIM(DELETE_PRESERVES_FRIENDS) with toggle preamble (:282-304); GSIM(INVITE_ACCEPT_SPINNER) green via design lock (:200-201) | no RED — closure gates | required-param mutation → compile-red proves ctor compat | PERF + GSIM | registered (PERFORMANCE_TARGETS :339; GROUP_LIFECYCLE_SIM_SCENARIOS :350-351; scenario libs stay `support` :328-334 — no classify_path change) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability**: view mode is deliberately non-persisted derived state; fresh-mount reconstruction locked by cat.12 (TC-193-05) and the real two-session cold-restart sim cat.20 (TC-193-51). Covered.
- **Sibling-surface consistency**: the surface gate must apply uniformly to ALL list-coupled affordances — cat.1 locks the full absence set on the inner view (rows, filter toggle, QR header, search trigger, banner); TC-193-30…38 lock the full presence set on the all-chats view; cat.11 locks the third entry path (initialFilterTab). Covered.
- **Destructive-action side-effects**: no new destructive action is added; existing swipe archive/block/delete regressions preambled (TC-193-35). Justified N/A for new rows.
- **Invariant re-verification under new transitions**: the NEW transition (rising-edge view reset) re-verifies its pre-transition invariants — dirty replay still runs (cat.22, mutation = starve), search force-closed (cat.16 asserts no TextField), filter deliberately preserved (cat.13), background-kind cannot fire it (cat.14), hidden-embedded-instance reset during an intro push is expected and harmless (noted in Risks). Covered.

## Invariants (locked by tests)
- INV-1 default-entry = Inner-Circle on every activation path (nav tap / swipe / fresh mount / re-entry) → cat.17, 18, 12, 16.
- INV-2 `initialFilterTab != null` ⇒ all-chats view (intros reachable from notifications with zero taps) → cat.11.
- INV-3 the rising-edge reset never starves `_replayDirtyOrbitWork()` → cat.22.
- INV-4 background-kind controller notifications never reset the view → cat.14 (mutation-verified).
- INV-5 surfaces are disjoint (no list-affordance leakage onto the inner view; no viz header on the all-chats view) → cat.1, 19.
- INV-6 toggle is physically top-left in LTR and RTL and never overlaps the FAB → cat.5.
- INV-7 nav badge (Path A) live on both views; Path B untouched → cat.8 + feed_wired badge sentinels.
- INV-8 filter tab survives the view reset (deliberate asymmetry) → cat.13.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (expect only `info.plist` dirty — pre-existing).
2. Add the 3 l10n keys to app_en/ar/de.arb; run `flutter gen-l10n`; commit generated files. Write cat.21 RED FIRST against HEAD ARBs to prove it fails, then apply keys.
3. Add all RED tests (catalog 1-23; key name `orbit-view-toggle` is FIXED by this plan — no AWAITS-KEY blockers remain). Run the RED gate commands; each must fail for its documented reason.
4. Production edit A — `orbit_view_mode.dart`: new enum.
5. Production edit B — `orbit_screen.dart`: optional `viewMode` (default allChats) + `onToggleView`; branch the SafeArea Column (innerCircle: expanded header block + empty-hint when friends empty; allChats: list block only); mount `OrbitViewToggleButton` in the Stack when `onToggleView != null`. Do NOT delete the collapse machinery or the `!_showsPersistentNav` branch.
6. Production edit C — `orbit_view_toggle_button.dart`: 40px, ValueKey('orbit-view-toggle'), physical Positioned(top: padding.top+8, left: 16), Semantics label per state.
7. Production edit D — `orbit_wired.dart`: `_viewMode` field; initState seed (`initialFilterTab != null` ⇒ allChats); `_onToggleView()` (flip + close search when leaving allChats + publish); rising-edge block :466 → reset `_viewMode` + force-close search state BEFORE/WITHOUT skipping `_replayDirtyOrbitWork()`; pass `viewMode:`/`onToggleView:` into OrbitScreen (:2189 wiring).
   Stop-if: the rising-edge reset requires touching `AppShellChangeKind` semantics or FeedWired's `_onShellChanged` → replan; the edge condition at :466 must remain sufficient on its own.
8. Test-suite mechanics: add `switchToAllChats` helper; apply preambles (~30 orbit_wired_test tests, feed_wired_test:1075, delete-preserves sim :282); rewrite the two superseded locks (cat.16, 19); perf harness `viewMode: OrbitViewMode.innerCircle` explicit.
9. Harness registration: append `test/features/orbit/presentation/screens/orbit_view_split_test.dart` AND `test/l10n/orbit_strings_parity_test.dart` to `GROUP_TESTS` (run_test_gates.sh:209-238). No classify_path or dart-define changes (verified: cold-start already dual-suite :284-289; scenario libs stay `support`).
10. Rerun direct → preservation → named gates (commands below). Run graphify refresh (`graphify update .` + `./graphify-arch/refresh_arch_graph.sh`) after code lands.

## Risks And Edge Cases
- Rising-edge reset ordering vs dirty replay → pinned by cat.22 (mutation: early-return starves replay).
- Intro push resets the HIDDEN embedded instance (route force-switches tab to orbit, main.dart:3418-3420 → rising edge fires on the latched pane underneath) — harmless by design; feed_wired-level tests must not assert list state on the hidden pane after an intro push.
- Bare-OrbitScreen compile/behavior compat: 4 direct ctor sites (loading/archived/route-harness/perf) → optional params, default allChats; perf harness updated explicitly. Pinned by TC-193-53 compile gate.
- FAB scrim covers the toggle while the FAB menu is open (expandable_fab.dart:146-155) — accepted; no test taps the toggle with the menu open.
- Search-open state carried into a reset (dock animating while surface unmounts) → force-close search in the reset; pinned by cat.16 (no TextField post-re-entry).
- `orbit_screen_loading_test:444` 'keeps orbit chrome visible…' becomes view-dependent — restated per-view in cat.19, not deleted.
- RTL: toggle uses plain physical Positioned — pinned by cat.5 with the PositionedDirectional mutation.
- Two pre-existing orbit_wired group-invite failures were recorded on branch new-feed 2026-06-21 (138 doc execution log) — run a clean-HEAD control of `./scripts/run_test_gates.sh groups` BEFORE the RED batch to baseline.

## Device/Relay Proof Profile
host-only for closure, plus the three ALREADY-REGISTERED simulator lanes (no OS boundary, no crypto, no relay, no multi-device, no persistence — spec explicitly rejects persistence, so no storage boundary exists).
Closure scenario (PROD-CRITICAL leg): cold_start_message_render_simulator_test via `./scripts/run_test_gates.sh reliability-sim 1to1 --list` → note its `--only N` → run that N (also appears in the `group` suite). No new device work; no relay config needed.

## Acceptance Gates (literal — copy/paste)
```bash
# 0. Baseline control (BEFORE any edits — catch pre-existing dirt)
git status --short                              # expect: only "M info.plist"
./scripts/run_test_gates.sh groups              # record baseline counts

# 1. RED (after adding catalog tests, before production edits) — each must FAIL as documented
flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart                       # expect: ALL RED
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name 'orbit re-entry resets to the Inner-Circle view'   # expect: RED (no toggle; old behavior holds)
flutter test test/l10n/orbit_strings_parity_test.dart                                                  # expect: RED (keys absent)
flutter test integration_test/cold_start_message_render_simulator_test.dart -d "$FLUTTER_DEVICE_ID"    # expect: RED at the pre-toggle findsNothing

# 2. Direct GREEN (after implementation)
flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart                       # expect: ~14/14 pass
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart                            # expect: 70+new/70+new pass (73 total: cat.15, 22, 23 additions)
flutter test test/features/feed/presentation/screens/feed_wired_test.dart                              # expect: 48+1/49 pass (cat.17 addition, cat.16 rewrite in place)
flutter test test/features/feed/presentation/screens/feed_swipe_test.dart                              # expect: all + 2 new pass
flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart                   # expect: 10/10 (cat.19 rewrite in place)
flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart           # expect: 10/10 untouched
flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart                  # expect: 11/11 untouched
flutter test test/l10n/orbit_strings_parity_test.dart test/l10n/l10n_integrity_test.dart               # expect: all pass

# 3. Preservation + named gates (counts vs step-0 baseline + additions; gate docs are stale — script wins)
./scripts/run_test_gates.sh groups              # includes orbit_wired_test + the 2 GT+ additions
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh completeness-check  # every file classifies (new test files must not be unclassified)

# 4. Simulator / perf lanes
./scripts/check_reliability_simulation_discovery.sh                          # 0 unclassified
./scripts/run_test_gates.sh reliability-sim 1to1 --list                      # cold_start present with its --only N
flutter test --dart-define="PERF_TARGET=ORBIT" integration_test/performance_harness.dart               # ORBIT lane green on the inner-circle surface
flutter test --dart-define="GROUP_SIM_SCENARIO=DELETE_PRESERVES_FRIENDS" -d "$FLUTTER_DEVICE_ID" integration_test/group_lifecycle_simulator_harness.dart
flutter test --dart-define="GROUP_SIM_SCENARIO=INVITE_ACCEPT_SPINNER"    -d "$FLUTTER_DEVICE_ID" integration_test/group_lifecycle_simulator_harness.dart

# 5. Hygiene
flutter analyze                                 # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED (pre-implementation): every command in gate block 1, for exactly the documented reasons (toggle key absent / welded surfaces / keys absent / names visible on default).
- Pre-existing dirty: `info.plist` (uncommitted, unrelated — do not revert); possible pre-existing orbit_wired group-invite failures (138 doc, new-feed 2026-06-21) — compare against the step-0 baseline before attributing.
- Environment blocker (NOT product): no simulator/device available for gate blocks with `-d` — host gates still close everything except TC-193-51/53.
- Scope drift (BLOCKING): any failure in orbit2/orbit3 suites, prototype source guards, conversation/notification routing tests, or posts/transport gates.

## Done Criteria
- [ ] RED added first; every catalog entry failed for its documented reason (block-1 evidence recorded).
- [ ] Mutation-verified: each production edit has its named re-red revert (matrix column 6).
- [ ] Direct GREEN + preservation sentinels + `groups`/`feed`/completeness gates pass.
- [ ] No DB migration (none — no schema change; view mode deliberately unpersisted).
- [ ] TC-193-51 sim green on a simulator (PROD-CRITICAL leg) + ORBIT perf lane + 2 group-lifecycle scenarios.
- [ ] Harness registration done: 2 files appended to GROUP_TESTS; completeness-check + discovery checker green.
- [ ] flutter analyze 0 new; git diff --check clean; no Scope Guard violations.
- [ ] 00-INDEX.md row added; `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` run after landing.

## Scope Guard (hard "Do not")
- Do not touch inner-circle membership semantics (positional top-13, `_sortFriends` :810-816, ring constants 5/8/13) or OrbitalVisualization internals.
- Do not add an AppShellTab value or touch FeedNavigationBar buttons/`_onShellChanged` switch arms (feed_wired.dart:2386-2413).
- Do not persist the view mode (no SecureKeyStore key, no prefs) — explicitly rejected by product decision.
- Do not reset `_filterTab` in the rising-edge block (locked asymmetry, cat.13).
- Do not delete the `!_showsPersistentNav` X-close branch or the collapse machinery (follow-up owns cleanup).
- Do not modify orbit2/orbit3 code, flags, or their source-guard tests.
- Do not add classify_path cases or dart-define scenarios (nothing new to register at sim tier).
- Do not modify conversation-notification routing (main.dart:4202-4241) or FeedWired badge path B (:528-589).

## Accepted Differences / Intentionally Out Of Scope
- Filter tab persists across the view reset (deliberate; test-locked by cat.13) — a "reset filter too" variant is a product follow-up if wanted.
- The toggle sits under the FAB scrim while the FAB menu is open — accepted; menu-open is a transient modal state.
- The production-unreachable X-close/floating-search branch stays in code — cleanup session owns removal.
- Groups vanish from the list during search (orbit_wired.dart:301) — pre-existing latent UX gap inherited unchanged.
- `OrbitFriend` doc-comment says "sorted by messageCount" but sort is by timestamp (orbit_friend.dart:6) — pre-existing doc/code mismatch; fix-as-you-go one-liner allowed but not required.
- orbit3 One-Circle scalability work (156 two-prototype lab) is unrelated to this split.

## Dependency Impact
- The `/sims` cold-start, group-lifecycle, and ORBIT perf lanes depend on this plan's toggle preambles landing WITH the production change in the same session — a partial land breaks reliability-sim 1to1/group wholesale (cold_start is a direct `test` member of both suites).
- Any future "curated inner circle" (orbit2/3 promote-demote graduation) builds on `OrbitViewMode` — keep the enum in domain/models so it is reusable.
- The 163 off-screen contract now has a second rising-edge consumer (reset + replay); future edge consumers must preserve the cat.22 ordering lock.

## Reviewer Findings
Sufficiency self-check (references/sufficiency-checklist.md) — all gates YES: 42/42 spec TCs have matrix rows with zero empty tier/mutation/gate/registration cells; every INV has a named test; every production edit (A-D + hint + reset) has a named re-red revert; no vacuous coverage (conjunction REDs documented where half the assertion is green on HEAD; cat.11 carries a distinct discriminator — viz-absence vs filter-state); no DB migration required (none claimed); boundary rule respected (pure Flutter UI — host floor everywhere; the three sim lanes are inherited E2E closure gates, not fakes standing in for a boundary); PROD-CRITICAL leg named (TC-193-51); preservation sentinels named with gate commands; acceptance gates literal (counts stated per-file; family-gate totals against a step-0 baseline because gate docs are verifiably stale); harness registration named per test incl. the non-obvious `test/l10n` glob gap; known-failure interpretation + dirty-tree snapshot planned; refuted/corrected findings recorded (5 items). Blind-spot sweep: 4/4 classes have rows or justified N/A.

## Arbiter Decision
Structural blockers: none. Deferred details: exact copy for `orbit_inner_circle_empty_hint` (any reasonable string; ar/de translations required by parity test); whether the toggle is icon-only or icon+label (must satisfy cat.5 geometry + cat.6 semantics either way). Accepted differences: as listed above.

## Final Execution Verdict
Verdict: pending execution | Files changed: — | Tests run: — | Blocking: — | QA verdict: — | Non-blocking follow-ups: X-close-branch cleanup (owner: future session); orbit_friend.dart doc fix (fix-as-you-go).
