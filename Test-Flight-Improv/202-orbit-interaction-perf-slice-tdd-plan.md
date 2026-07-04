# 202 - Orbit interaction performance slice (repaint isolation, drag single-rebuild, constant-cost pulse, refresh coalescer, animation hygiene)  (Feature Improvement)

Status: IMPLEMENTED (host-green 2026-07-04)
Spec: free-text intent (no formal spec) — user request 2026-07-03 ("review how we can make orbit interaction faster without removing features"), audited by two perf lenses + adversarial verification in workflow `wf_0396f589-131` (B7, verdict **partial→corrected**: repaint-scope mechanism corrected by the verifier — see Root Cause); plan grounding `wf_0e48db0b-199` (G202). Dossier: memory `project_orbit_seven_bug_debug_2026_07_03.md`.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-03 | Evidence Collector (wf_0396f589 B7, 2 lenses + verify) | orbit_wired.dart, inner_circle_interactive_surface.dart, orbital_visualization.dart, orbit_edit_handle.dart, unread_orbit_indicator.dart, orbital_ring_painter.dart, feed_wired.dart, friend_row.dart, SDK | Verifier CORRECTED the repaint story: scroll viewport + AmbientBackground ARE boundaries → TWO independent per-frame repaint streams; "scope dim-flash out of node rebuilds" REFUTED-as-unattainable | ground test mechanics |
| 2026-07-04 | Evidence Collector (wf_0e48db0b G202) | sculpt/wired/unread suites, feed 162 locks, perf harness, run_test_gates.sh, orbit_edit_handle_test | 3 blur-reading tests must re-baseline under pulse redesign; transientCallbackCount = NEW pattern (0 repo hits); collapseAnimation has NO consumer (leak is real, repaint isn't); coalescer window ≤100ms is pump-transparent | write plan |
| 2026-07-04 | Planner (this session) | grounding dossiers | Node boundary INSIDE the dim Opacity; 32ms window (feed precedent); debugOnSurfaceBuild hook (debugOnHeaderBuild precedent); sequence after 201 | reviewer pass |
| 2026-07-04 | Reviewer (sufficiency) | | (pending) | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-04 | contract extraction | (git status) | orbit tree clean on top of 201 (`8e655c3b`/`3a46d093`/`7242cb9d`) | scope confirmed; re-grounded post-201 (stale line #s) | RED |
| 2026-07-04 | perf BEFORE capture | — | `flutter test -d macos --dart-define=PERF_TARGET=ORBIT` → **BUILD FAILED** (ObjC Pods-Runner-dummy.o) | ENV blocker (not product; Dart-only changes can't affect ObjC build) | proceed (report-only lane) |
| 2026-07-04 | RED tests added | 5 test files + debugOnSurfaceBuild hook | `--plain-name TC-202` → +1 -9 | 9 red for documented reasons; TC-202-09d passes on HEAD (fix-contract guard, by design) | edits |
| 2026-07-04 | implementation | orbital_visualization / inner_circle_surface / orbit_edit_handle / orbit_wired / friend_row | 6 edits + hook, per-edit verified | scoped files only | GREEN |
| 2026-07-04 | direct GREEN | — | edit1→01/02/03; edit2→04; edit3→05/06+3 re-baselines; edit4→07/08/09; edit5→10; edit6→11/12 | all direct reds green | sentinels |
| 2026-07-04 | preservation GREEN | — | orbit cluster **472**; TC-198F-02/09/11/13, TC-203-07/08, TC-194 pins, :1431 single-event pin all green | sentinels green | gates |
| 2026-07-04 | named gates + perf AFTER | — | groups **1041**, feed **285**, `flutter analyze` 0 new, `git diff --check` clean; perf AFTER = same ENV blocker | gates green | QA |
| 2026-07-04 | QA / mutation | orbit_wired (temp) | TC-202-09d dispose-cancel removed → pending 32ms Timer (red); reverted. Others = RED-first HEAD revert (single-cause) | blocking: none | verdict |

## Source Of Truth
- Spec / intent: inline below
- Gate definitions: scripts/run_test_gates.sh
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh (perf harness already 'ignored' there :141-144)
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready (sequence AFTER plan 201 — see Dependency Impact)

## Exact Problem Statement
Orbit-screen interaction carries avoidable per-frame and per-event cost. Verified hot spots: (1) with any unread node present, the 9s satellite rotation re-rasterizes the ENTIRE scrolled canvas layer every frame — blurred rings (`orbital_ring_painter.dart:82-109` MaskFilter), every avatar's glow BoxShadow, and the per-node dim saveLayers; (2) in edit mode, 2–5 handle pulses re-rasterize animated BoxShadows every frame for the whole session — **even when band-hidden** (Offstage does not stop tickers); (3) every sculpt-drag pointer frame triggers a SECOND full surface rebuild (post-frame measure `setState` on a pure signature change); (4) every incoming message/contact event does a full DB snapshot + two sorts + whole-projection publish with zero coalescing (feed has the 162 coalescer; orbit has none; group refreshes do TWO DB roundtrips each); (5) `OrbitWired.build` constructs three `CurvedAnimation`s per rebuild, each registering a never-removed status listener on shared controllers (leak); (6) all-chats rows animate in with an unbounded `index*20ms` stagger and NO reduce-motion path (deep rows invisible up to ~2s on fling; one ticker per row).

What must improve: steady-state and interaction frame cost drops measurably (perf lane before/after) with **zero feature or visual removal** (subtle timing changes allowed per user request).
What must stay unchanged (→ preserved-green sentinels): same-frame handle re-seat (TC-198F-02), first-frame guard (TC-198F-09), hidden-not-unmounted band-hide + mid-drag survival (TC-198-71/72), armed/reduce-motion pulse freeze contracts, 194 read-clear liveness (TC-194-17/18/19), rising-edge dirty replay order (TC-194-12 / cat.22), single-event 1-DB-load pin (`orbit_wired_test.dart:4578-4580`), INV-5 dim asserts, all 193/196/197/198 behavior.

## Root Cause (verify → refute confirmed — wf_0396f589 B7 with verifier corrections)
Corrected repaint model (the verifier REFUTED the pane-wide-repaint story): the scroll viewport IS a repaint boundary (SDK `single_child_scroll_view.dart:429`) and `AmbientBackground` wraps content + glows in RepaintBoundaries (`ambient_background.dart:191/220/248`) → **two independent per-frame repaint streams**: the **canvas layer** (unread rotation `unread_orbit_indicator.dart:84-94` invalidates the scrolled canvas: blurred rings + avatar glows + dim saveLayers) and the **chrome layer** (handle pulses `orbit_edit_handle.dart:167-176`; `_syncMotionPreference :93-106` has no visibility input, so band-hidden handles keep ticking — `Offstage` is a bare RenderOffstage, no TickerMode). Zero `RepaintBoundary` exists inside `lib/features/orbit/` (grep-verified) — but framework `_ModalScope` route boundaries DO exist above the surface (SDK `routes.dart:1206/:1231`), so structure tests must use feature-scoped/keyed finders, never bare ancestor checks (reviewer-verified hazard).
Double rebuild per drag frame: drag `setState` (`inner_circle_interactive_surface.dart:370-376`) + build schedules post-frame measure when `_measureSignature` differs (`:497-500`); signature includes `_geometry` (`:226-227`) so a pure knob change triggers the measure-compare `setState` (`:254-258`) even when origin+scrollOffset are unchanged.
Zero coalescing: `_chatSubscription` dispatches `_refreshOrbitFriend` per event (`orbit_wired.dart:1668-1674`) → `loadOrbitFriendSnapshot` + two sorts + `_publishAllProjections` (`:766-798`) per event; `_refreshOrbitGroup` does TWO DB roundtrips (`:809-826`). Feed precedent: `_PendingContactFeedFlush` trailing-flush coalescer (`feed_wired.dart:~2811`, window 32ms `:246`), locked by TC-162-04/05/06 (`feed_wired_test.dart:1697-2200`).
CurvedAnimation leak: three per-build constructions (`orbit_wired.dart:2306-2317`); constructor registers a status listener on its controller; never disposed; consumers are AnimatedBuilders in orbit_screen (`:419-439, :445-470, :488-506`) — `collapseAnimation` currently has NO consumer (leak real, repaint cost nil).
friend_row: `Future.delayed(index*20ms)` unbounded, no MediaQuery motion check (`friend_row.dart:183-198`); AnimatedFriendRow has ZERO test coverage; cacheExtent 600 mounts rows ~600px early (`orbit_screen.dart:579`).

Refuted / do-NOT-re-introduce:
- "The whole orbit pane repaints on every animation frame" (`feed_wired.dart:2728` as nearest boundary) — REFUTED: viewport + AmbientBackground boundaries exist; do not justify changes with the pane-wide story.
- "Pulsing handles force the canvas dim saveLayers to re-execute" — REFUTED: pulses live in the chrome layer; the canvas stream is driven by unread rotation/drag/arm rebuilds.
- "Scope `_dimFlash` and find keystrokes out of node rebuilds" — REFUTED-as-unattainable: `editDim`/`litIndices` feed every node's Opacity via `_dimFor` (`orbital_visualization.dart:94-99`) — any dim tick must rebuild all nodes. Only `_armed` is viz-independent. NOT planned.
- "Drop `_geometry` from `_measureSignature`" — UNSAFE with arcs expanded (avatarScale/maxPerArc change overhang → canvas height/scroll extent). Only the silent-update variant ships.

## Real Scope
In scope (production; six edits):
1. **RepaintBoundary isolation**: (a) per ring/arc node — INSIDE the keyed dim Opacity (`Positioned > Opacity('orbit-node-dim-N') > RepaintBoundary > node`, wrap point `orbital_visualization.dart:188-210`) so dim-value changes recomposite the cached node raster instead of re-rasterizing it, and the unread rotation invalidates only its own node; (b) per edit handle (between Positioned/Offstage and OrbitEditHandle, `inner_circle_interactive_surface.dart:752-774`); (c) around the ring CustomPaint (inside the editDim Opacity, `orbital_visualization.dart:150-164`).
2. **Silent measure update**: in `_measureCanvasNow` (`:248-258`), when `prev != null` and origin+scrollOffset are unchanged, update the stored `_CanvasMeasurement` field WITHOUT `setState` (signature-only refresh); keep the post-frame measure itself and the `prev == null` first-frame path untouched (TC-198F-09).
3. **Constant-cost pulse**: `orbit_edit_handle.dart:148-192` — render the halo as a pre-rasterized max-size shadow layer and animate its **opacity** (cross-fade/FadeTransition), keeping: resting values blur 10/spread 1 at wave=0, armed static halo (blur 20/spread 4 `:167-171`), reduce-motion/armed freeze (`_pulse.value=0` `:98-101`), disc key `'orbit-handle-disc-<knob>'` (`:155`), gesture key `:140`. Plus **freeze the pulse while band-hidden**: thread the `visible` flag (computed `:746-750`) into the handle (or stop/start `_pulse` on Offstage flip) — element stays mounted (TC-198-71).
4. **162-style trailing-flush coalescer** in `orbit_wired.dart`: per-key pending map (peers + groups) with a 32ms trailing window (feed precedent `feed_wired.dart:246`; pump-transparent for the 100ms-step orbit suites); dedupe same-key bursts → ONE snapshot load (+ ONE rejoin-states load per group) → ONE projection publish per flush; flush immediately on the rising edge (before `_replayDirtyOrbitWork` consumers — preserve cat.22 order) and on dispose; `_replayDirtyOrbitWork` enqueues into the same coalescer.
5. **CurvedAnimation hoist**: the three wrappers (`orbit_wired.dart:2306-2317`) become `late final` initState fields (controllers already initState-created `:417-426`), disposed with their controllers.
6. **friend_row motion hygiene**: clamp the stagger (`min(index, 12) * 20ms`) and jump-to-end under `MediaQuery.disableAnimations`/`accessibleNavigation` (house convention: `orbit_edit_handle.dart:93-106`, `unread_orbit_indicator.dart:79-95`); both call sites (`orbit_screen.dart:1022/:1053`) unchanged.
Plus: NEW `debugOnSurfaceBuild` hook on `InnerCircleInteractiveSurface` (test-only counter; precedent `debugOnHeaderBuild`/`debugOnListBuild`, `orbit_wired.dart:150-151/:198-199` → `orbit_screen.dart:239-240/:295-296`).
Out of scope (owners named): the ~300ms tap-away disambiguation delay (spec-pinned gesture semantics — needs its own product-reviewed slice); decode quantization during sculpt drags (interacts with plan 200's provider helper — follow-up after 200 lands); AmbientBackground loop (156 QW-2 design); `_dimFlash`/find-keystroke rebuild scoping (refuted-as-unattainable); B2 group publish-all fix itself (separate small fix — but the coalescer must not conflict with it; see Dependency Impact).

## Files To Inspect Next
Production: lib/features/orbit/presentation/widgets/orbital_visualization.dart; inner_circle_interactive_surface.dart; orbit_edit_handle.dart; lib/features/orbit/presentation/screens/orbit_wired.dart; lib/features/orbit/presentation/widgets/friend_row.dart; (reference only) lib/features/feed/presentation/screens/feed_wired.dart `_PendingContactFeedFlush`; lib/features/identity/presentation/widgets/ambient_background.dart (do not modify).
Direct tests: orbit_sculpt_summon_wired_test.dart; orbit_wired_test.dart; orbit_unread_indicator_wired_test.dart; orbit_edit_handle_test.dart; orbital_visualization_test.dart; friend_row_test.dart; integration_test/orbit_performance_harness.dart (evidence lane).
Dependency-only context: feed_wired_test.dart 162 locks (:1697-2200); run_test_gates.sh PERFORMANCE_TARGETS (:352-359); orbital_arcs_test.dart settle rationale.

## Existing Tests Covering This Area
- orbit_sculpt_summon_wired_test.dart (**GROUP_TESTS** :254): TC-198F-01/02 (same-frame re-seat, :637-673), TC-198-71 (scroll-tracking + Offstage hidden-not-unmounted + armed survives, :676-712), TC-198F-09 (first-frame guard, :894-918), TC-198F-13 (pulse blur CHANGES over 800ms, :920-952 — **re-baseline under edit 3**).
- orbit_wired_test.dart (**GROUP_TESTS** :227): debug-hook rebuild scoping (:1691-1711), 193 live re-rank + **exact 1-getContact-per-event pin** (:4515-4590, spies :4523-4547) — the coalescer's single-event preservation row.
- orbit_unread_indicator_wired_test.dart (**GROUP_TESTS** :246): TC-194-10..19 read-clear/liveness (100ms-step pumps :245-249) — coalescer re-baseline checkpoints; TC-194-12 = the cat.22 rising-edge behavioral lock (:331-370).
- orbit_edit_handle_test.dart (auto-glob): TC-198F-11 halo colors (:99-116); TC-198-59 pulse animates (:118-127) + freeze under reduce-motion (:129-148) — **both re-baseline under edit 3** (anchors reviewer-corrected; test NAMES are the stable keys).
- feed_wired_test.dart (FEED_TESTS :182): the 162 coalescer lock template (TC-162-04 burst→one :1778; per-key :1995; escalation :1837/:2026; preservation-within-window :2167).
- friend_row_test.dart (auto-glob): FriendRow CONTENT only — AnimatedFriendRow entrance has ZERO coverage (greenfield).
- integration_test/orbit_performance_harness.dart: 5 ORBIT scenarios, **report-only** (`:307` comment; structural expects only :304-320); PERF_TARGET dispatch (performance_harness.dart:33-58); ORBIT in PERFORMANCE_TARGETS (run_test_gates.sh:357); harness in OPTIONAL_MANUAL_TESTS (:340); 'ignored' in sim discovery (:141-144). NB: harness pumps OrbitScreen directly with `AlwaysStoppedAnimation` (:244-246) — it structurally CANNOT evidence edits 4/5 (OrbitWired-level); host tests carry those.

Missing coverage gaps: no RepaintBoundary structure test in orbit; no surface build-count hook; `transientCallbackCount` used nowhere in test/ (NEW pattern); no N-event burst DB-count lock on orbit; no AnimatedFriendRow tests; perf lane cannot gate (report-only).
Already in curated family arrays?: sculpt/wired/unread wired suites in GROUP_TESTS; handle/viz/friend_row files auto-glob; perf harness manual lane.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
1. `orbital_visualization_test.dart` :: `'TC-202-01 every node subtree is isolated by a RepaintBoundary inside its dim layer'`
   - Shape: pump viz with N friends; per seat: `expect(find.descendant(of: find.byKey(ValueKey('orbit-node-dim-$i')), matching: find.byType(RepaintBoundary)), findsOneWidget)` (key-independent of 201's Positioned keys; boundary INSIDE the keyed Opacity per placement decision).
   - RED on HEAD: no RepaintBoundary anywhere in the node subtree. Mutation: remove the boundary → red.
2. `orbit_sculpt_summon_wired_test.dart` :: `'TC-202-02 each edit handle is isolated by a keyed RepaintBoundary'`
   - Shape: production gives each handle boundary a KEY — `RepaintBoundary(key: ValueKey('orbit-handle-boundary-<knob>'))` at the wrap point (`:752-774`); test: enter edit; `expect(find.byKey(const ValueKey('orbit-handle-boundary-spacingScale'), skipOffstage: false), findsOneWidget)` per visible knob. **Reviewer-caught BLOCKER (fixed here):** an unscoped `findAncestorWidgetOfExactType<RepaintBoundary>() != null` is vacuously TRUE on HEAD — every route page sits under TWO framework RepaintBoundaries from `_ModalScope` (SDK `routes.dart:1206/:1231`); keyed boundaries make the finder unambiguous and the mutation mechanical.
   - RED on HEAD: boundary key absent → findsNothing. Mutation: remove the keyed boundary → red.
3. `orbital_visualization_test.dart` :: `'TC-202-03 the ring CustomPaint is isolated by a keyed RepaintBoundary'`
   - Shape: production keys the boundary — `RepaintBoundary(key: ValueKey('orbit-ring-boundary'))` inside the editDim Opacity (`:150-164`); test: `expect(find.descendant(of: find.byType(OrbitalVisualization), matching: find.byKey(const ValueKey('orbit-ring-boundary'))), findsOneWidget)` + structural check that the OrbitalRingPainter CustomPaint is a descendant of that boundary. **Reviewer-caught BLOCKER (fixed here):** the originally sketched unscoped `find.ancestor(... RepaintBoundary) findsOneWidget` finds the TWO framework `_ModalScope` boundaries on HEAD (red for the WRONG reason) and 3 after the fix (never green). Feature-scoped keyed finder is the fix.
   - RED on HEAD: boundary key absent → findsNothing. Mutation: remove → red.
4. `orbit_sculpt_summon_wired_test.dart` :: `'TC-202-04 a pure-geometry sculpt-drag frame rebuilds the surface exactly once'`
   - Shape: NEW `debugOnSurfaceBuild` hook (production edit, threaded through host() at :100-111); enter edit; startGesture on `handleF(OrbitKnob.spacingScale)`; consume slop (moveBy + pump); reset counter; ONE `moveBy(0,-60)` + TWO pumps (drag frame + post-frame measure frame); expect buildCount == 1.
   - RED on HEAD: == 2 (drag setState `:370-376` + signature-diff measure setState `:254-258` via `:497-500`). Mutation: restore unconditional measure setState → red. Guards: TC-198F-02 + TC-198F-09 must stay green (suppression must not skip the `prev == null` path or same-frame re-seat — safe because handle anchors derive from `_geometry` in the drag's own frame; `_canvasOriginNow` reads only origin+scrollOffset `:265-270`).
5. `orbit_sculpt_summon_wired_test.dart` :: `'TC-202-05 band-hidden handles stop their pulse tickers'`
   - Shape: `host(_friends(80))` (deep stack, **zero unread** — no rotation tickers); expandBadge + longPressBg + bounded settle (drains entrance timers); `c0 = tester.binding.transientCallbackCount`; scroll `tester.dragFrom(Offset(60,300), Offset(0,-120))` + pump (TC-198-71 choreography) so K handles leave the band; expect `transientCallbackCount == c0 - K`. Count DELTAS, not absolutes (grounded hazard: other tickers pollute absolutes). NEVER pumpAndSettle.
   - RED on HEAD: count unchanged (Offstage keeps `_pulse.repeat()` ticking; `:93-106` has no visibility input). Mutation: remove the freeze-on-hidden wiring → red. NEW pattern (0 repo hits for transientCallbackCount) — stock TestWidgetsFlutterBinding getter; feasibility grounded. Sample the count only AFTER a bounded settle following the drag release (reviewer-caught: the fling's ballistic-scroll ticker can still be live at sampling time and skew the delta by +1).
6. `orbit_edit_handle_test.dart` :: `'TC-202-06 pulse animates opacity over a constant-shadow disc'`
   - Shape: pump unarmed handle (wrap() :23-31); read disc decoration via `ValueKey('orbit-handle-disc-<knob>')` at t=0 and t=800ms; assert `boxShadow.first.blurRadius` CONSTANT (resting 10/spread 1) while the halo layer's opacity value CHANGES (keyed halo widget for findability).
   - RED on HEAD: blur = 10+12*wave, CHANGES (`:173-177`). Expected FIRST failure mode on HEAD is the missing keyed halo widget (finder findsNothing), not a blur-value mismatch — still red for the fix reason (executor note, reviewer-flagged). Mutation: revert to animated BoxShadow → red.
   - CHURN OBLIGATION (same slice, not weaken): re-baseline TC-198-59 animate (:116-125) + freeze (:127-146) and TC-198F-13 (:929-936) onto the opacity mechanism, preserving the armed-static and reduce-motion-freeze CONTRACTS (assert halo-opacity constant when frozen; blur constant always).
7. `orbit_wired_test.dart` :: `'TC-202-07 a same-peer event burst coalesces to ONE snapshot load and publish'`
   - Shape: buildOrbitWired + `_SpyContactRepository`/`_SpyMessageRepository`/`_FakeChatMessageListener` (:4523-4547); settle; resetTracking(); emit 3 incoming messages for one peer back-to-back (NO pump between); `pumpOrbitFrames` (100ms steps flush the 32ms window); expect `getContactCallCountByPeerId == {'contact-peer-id': 1}`.
   - RED on HEAD: per-event dispatch → count 3 (`orbit_wired.dart:1668-1674`). Mutation: remove the coalescer (direct dispatch) → red. Template: TC-162-04 (`feed_wired_test.dart:1778`).
8. `orbit_wired_test.dart` :: `'TC-202-08 group burst: one snapshot + one rejoin-states load per group per flush'`
   - Shape: same harness with group fakes; 3 group events for one groupId; expect ONE `loadOrbitGroupSnapshot` + ONE `loadGroupRejoinStates` (spy counters; extend spies if a group-side counter is missing).
   - RED on HEAD: 3× TWO roundtrips (`:809-826`). Mutation: bypass coalescer for groups → red.
9. `orbit_wired_test.dart` / `orbit_unread_indicator_wired_test.dart` :: `'TC-202-09 coalescer preservation set'`
   - (a) single event still → exactly 1 load (existing :4578-4580 stays green — the pin, unchanged); (b) TC-194-17/18/19 read-clear stay green (100ms pumps absorb the 32ms window); (c) TC-194-12 rising-edge replay refreshes once, order preserved (flush-on-rising-edge before consumers); (d) NEW: dispose with a pending flush → no exception, no pending-timer leak (pump widget away mid-window).
   - RED reason: (d) is RED only against a naive implementation (timer outlives state) — write it with the fix; (a-c) are sentinels. Mutation: drop dispose-flush → (d) red.
10. `orbit_wired_test.dart` :: `'TC-202-10 the three OrbitScreen animations are identical objects across OrbitWired rebuilds'`
    - Shape: buildOrbitWired(appShellController: shell); capture `a1 = tester.widget<OrbitScreen>(find.byType(OrbitScreen)).searchDockAnimation` (+ searchTriggerAnimation, collapseAnimation — public fields `orbit_screen.dart:195-197`); **`shell.switchTo(AppShellTab.orbit)`** + pump — a REAL tab transition. **Reviewer-caught BLOCKER (fixed here):** `AppShellController` defaults `initialTab = AppShellTab.feed` (`app_shell_controller.dart:17`) and `switchTo` EARLY-RETURNS on same-tab (`:31-34`) — the originally sketched `switchTo(feed)` fires no notify, no rebuild, and the test would be vacuously GREEN on HEAD. The feed→orbit transition drives `_onAppShellChanged` → setState (`orbit_wired.dart:494-508`; precedent orbit_unread_indicator_wired_test.dart:365). Capture a2; expect identical for all three. Do NOT hunt for FadeTransition (consumers are AnimatedBuilders; collapseAnimation has no consumer).
    - RED on HEAD: fresh CurvedAnimations per build (`:2306-2317`). Mutation: move construction back into build → red.
11. `friend_row_test.dart` :: `'TC-202-11 AnimatedFriendRow is instant under reduce-motion'` + `'TC-202-12 entrance stagger is clamped'`
    - Shape (11): pump `MediaQuery(data: MediaQueryData(disableAnimations: true), child: AnimatedFriendRow(index: 40, ...))`; ONE pump; `tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value == 1.0`. (12): index 100 WITHOUT reduce-motion; STEPPED bounded pumps past clampCeiling+400ms (several pump(100ms) steps — reviewer-caught: a single long pump can leave opacity near 0 because the ticker bases elapsed time from its first tick after the delayed `forward()`); then opacity == 1.0. Outlive own timers (arcs_test :76 precedent).
    - RED on HEAD: no motion check + `index*20ms` unbounded (`friend_row.dart:183-198`) → 0.0 at both checkpoints. Mutations: drop motion check → 11 red; drop clamp → 12 red.
12. Perf evidence lane (NOT a test row): `flutter test --dart-define="PERF_TARGET=ORBIT" integration_test/performance_harness.dart` BEFORE the RED batch and AFTER GREEN; record averageBuild/RasterMs, worst*, missedBudgetCounts per scenario (reportData `_printReportEntry :377-384`) in the Final Execution Verdict — especially `orbit_open_unread_indicators` (canvas stream) and `orbit_open_arcs_expanded_sculpt_find` (chrome/drag stream). Report-only per harness convention; pin `backgroundPreference`/reduce-motion consistently across the A/B runs (ambient loop pollutes rasterMs).

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-202-01 | node repaint isolation | widget | orbital_visualization_test.dart::TC-202-01 | no boundary in node subtree | remove node RepaintBoundary | `flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart` | AUTO (feature-host-all glob) |
| TC-202-02 | handle repaint isolation | wired widget | orbit_sculpt_summon_wired_test.dart::TC-202-02 | keyed boundary absent (bare ancestor checks vacuous — `_ModalScope` route boundaries) | remove keyed handle boundary | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS (:254) |
| TC-202-03 | ring-paint isolation | widget | orbital_visualization_test.dart::TC-202-03 | keyed boundary absent (feature-scoped finder) | remove keyed ring boundary | same as TC-202-01 | AUTO |
| TC-202-04 | drag single-rebuild | wired widget | sculpt wired::TC-202-04 (+ debugOnSurfaceBuild hook) | 2 rebuilds per drag frame | restore unconditional measure setState | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS |
| TC-202-05 | band-hidden pulse freeze | wired widget | sculpt wired::TC-202-05 | Offstage keeps tickers | drop freeze wiring | same | already in GROUP_TESTS |
| TC-202-06 | constant-cost pulse | widget | orbit_edit_handle_test.dart::TC-202-06 (+ re-baselined TC-198-59×2, TC-198F-13) | blur animates per frame | revert to animated BoxShadow | `flutter test test/features/orbit/presentation/widgets/orbit_edit_handle_test.dart` | AUTO |
| TC-202-07 | friend burst coalesce | wired widget | orbit_wired_test.dart::TC-202-07 | per-event dispatch (3 loads) | remove coalescer | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS (:227) |
| TC-202-08 | group burst coalesce | wired widget | orbit_wired_test.dart::TC-202-08 | 3× two roundtrips | bypass coalescer for groups | same | already in GROUP_TESTS |
| TC-202-09 | coalescer preservation + dispose | wired widget | orbit_wired_test.dart + orbit_unread_indicator_wired_test.dart::TC-202-09a-d | (d) naive timer outlives state | drop dispose flush | same + `flutter test test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart` | already in GROUP_TESTS (:227/:246) |
| TC-202-10 | animation identity/no-leak | wired widget | orbit_wired_test.dart::TC-202-10 | new CurvedAnimation per build | construct in build again | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS |
| TC-202-11 | row reduce-motion | widget | friend_row_test.dart::TC-202-11 | no motion check | drop motion check | `flutter test test/features/orbit/presentation/widgets/friend_row_test.dart` | AUTO |
| TC-202-12 | row stagger clamp | widget | friend_row_test.dart::TC-202-12 | unbounded index*20ms | drop clamp | same | AUTO |
| TC-202-13 | preservation: F02/F09/71 + 194 + 193 | wired widget | existing suites (sentinels) | n/a | any regression → red | `./scripts/run_test_gates.sh groups` + orbit cluster | existing |
| TC-202-14 | perf before/after evidence | perf harness (report-only) | integration_test/performance_harness.dart (ORBIT scenarios) | n/a — evidence lane | n/a (numbers recorded in verdict) | `flutter test --dart-define="PERF_TARGET=ORBIT" integration_test/performance_harness.dart` | existing PERF_TARGET=ORBIT dispatch (run_test_gates.sh:357; OPTIONAL_MANUAL :340) — no new case |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the coalescer's pending map is new derived state — TC-202-09d (dispose mid-window) + TC-202-09c (rising-edge flush reconstructs liveness) cover teardown/re-entry; no persistence involved.
- **Sibling-surface consistency:** ticker freezing applies ONLY to band-hidden handle pulses — the sibling animated surfaces (unread satellite rotation, ambient background, badge timers) must keep running: locked by TC-194 sentinels + overflow_badge tests + TC-202-05's delta-based count (which would fail if sibling tickers were frozen too). Feed's coalescer siblings untouched (FEED gate sentinel).
- **Destructive-action side-effects:** N/A — no delete/cleanup paths; dispose row (TC-202-09d) covers resource teardown (timers/listeners).
- **Invariant re-verification under new transitions:** the silent-measure transition re-verifies the pre-transition invariants that justified the old behavior — same-frame re-seat (TC-198F-02) and first-frame guard (TC-198F-09) re-run as named sentinels; the pulse redesign re-verifies armed-static + reduce-motion-freeze contracts in the re-baselined tests (contract preserved, mechanism changed).

## Invariants (locked by tests)
- INV-202-1: unread rotation invalidates only its node's boundary; handle pulses only their handle's → TC-202-01/02/03 (structure) + perf lane (evidence).
- INV-202-2: one surface rebuild per pure-geometry drag frame → TC-202-04.
- INV-202-3: no ticker runs for a band-hidden handle; hidden handles stay mounted → TC-202-05 + TC-198-71 sentinel.
- INV-202-4: N same-key events in one window → exactly one DB snapshot (+rejoin) + one publish; single events unchanged → TC-202-07/08/09.
- INV-202-5: animation objects are per-State, not per-build → TC-202-10.
- INV-202-6: all-chats entrance honors reduce-motion and bounded stagger → TC-202-11/12.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot; capture perf BEFORE numbers (PERF_TARGET=ORBIT).
2. Add RED rows 1-11 (+ the debugOnSurfaceBuild hook is a production prerequisite for TC-202-04 — add hook + test together; hook is behavior-inert). Confirm each red for its documented reason — EXCEPT TC-202-09a-c (sentinels) and TC-202-09d (explicit INV-RED-FIRST exemption: fix-contract guard, mutation-backed, written with the fix — QA must not flag it in the confirm-red pass).
3. Edit 1 (boundaries) → rows 1-3 green. Stop-if: INV-5 dim asserts red → boundary landed outside the keyed Opacity; fix placement.
4. Edit 2 (silent measure) → row 4 green; TC-198F-02/09 must stay green (stop-if red → replan, do not widen suppression).
5. Edit 3 (pulse) → rows 5-6 green + re-baseline the three blur tests in the same commit (contracts preserved).
6. Edit 4 (coalescer; 32ms) → rows 7-9 green; TC-194 suite + :4578 pin + TC-194-12 order stay green. Stop-if: TC-194-12 order breaks → flush placement wrong (must run before replay consumers).
7. Edits 5-6 (hoist, friend_row) → rows 10-12 green.
8. Named gates; perf AFTER capture; record numbers. `graphify update .` && `./graphify-arch/refresh_arch_graph.sh`.

## Risks And Edge Cases
- pumpAndSettle DEADLOCKS (repeating pulse, rotation) — bounded pumps everywhere; timer hygiene at test end.
- transientCallbackCount absolutes are polluted (rotation/entrance/badge tickers) — delta-based asserts; zero-unread fixtures; drain entrances first. Visible-knob count differs by mode (collapsed edit = 2 handles).
- RepaintBoundary layer-memory increase (dozens of small layers) — accepted; pixel-identical output.
- Boundary placement: INSIDE the dim Opacity (dim recomposites cached raster). If Opacity==0/1 optimizations complicate compositing, fallback = boundary directly around `_buildNode`'s child; decide at impl with the same TC-202-01 finder.
- Coalescer must not starve immediacy: 32ms trailing window; flush on rising edge + dispose; per-key map (feed :1995 precedent).
- Group-side spy counters may need extending (grounded open) — extend `_Spy*` fakes in-file, no production seam change.
- The perf harness cannot evidence edits 4/5 (bypasses OrbitWired with AlwaysStoppedAnimation) — host rows are their proof; device-leg evidence optional (Accepted Difference).
- Another live session may share the tree — re-check `git status` before implementing; graphify-arch meta + info.plist pre-dirty (do not revert).

## Device/Relay Proof Profile
host-only for closure + the report-only PERF_TARGET=ORBIT before/after lane (host-desktop run; self-skips on mobile). No /sims row, no device-proof (no OS/crypto/transport boundary). Optional F13-style on-device timeline capture deferred (owner: follow-up perf session).

## Acceptance Gates  (literal)
```bash
# Perf BEFORE (evidence lane — record numbers)
flutter test --dart-define="PERF_TARGET=ORBIT" integration_test/performance_harness.dart

# RED (before production edits) — must FAIL for the documented reasons
flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart
flutter test test/features/orbit/presentation/widgets/orbit_edit_handle_test.dart
flutter test test/features/orbit/presentation/widgets/friend_row_test.dart
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart

# Direct GREEN (after fix) — same five commands, all pass

# Preservation sentinels + named gates
./scripts/run_test_gates.sh groups          # expect: all pass; re-derive baseline BEFORE the RED batch (last recorded 1010 + fidelity/201 growth; ML-004 flake passes standalone)
flutter test test/features/orbit/ test/l10n/orbit_strings_parity_test.dart   # orbit cluster (last recorded 437 + 201 growth)
./scripts/run_test_gates.sh feed            # expect: 285 — proves the feed coalescer siblings untouched
flutter test test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart   # 194 suite green
./scripts/run_host_test_gates.sh feature-host-all   # exit 0

# Perf AFTER (same pinned background/motion config; record numbers side-by-side)
flutter test --dart-define="PERF_TARGET=ORBIT" integration_test/performance_harness.dart

# Mutation verification (QA) — per matrix (boundary removals, measure-setState restore, blur revert, coalescer bypass, build-time construction, motion-check drop)

# Hygiene
flutter analyze            # 0 new (5 pre-existing in untouched files)
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the five focused commands before implementation.
- Expected CHURN (not weaken): TC-198-59 ×2 + TC-198F-13 re-baselined onto the opacity-halo mechanism (contracts preserved: resting values, armed static, reduce-motion freeze).
- Pre-existing dirty: graphify-arch/* meta + info.plist.
- Environment blocker (NOT product): perf harness self-skips on mobile devices; host-desktop run required for the evidence lane.
- Scope drift (BLOCKING): any red in feed gate, 193/196 suites, or handle-geometry F-suite beyond the three named re-baselines.

## Done Criteria
- [ ] Perf BEFORE captured, then RED first (documented reasons), then GREEN.
- [ ] Mutation-verified per matrix.
- [ ] Direct GREEN + sentinels + groups/feed gates + orbit cluster pass; the three re-baselined tests preserve their contracts.
- [ ] Perf AFTER captured and recorded next to BEFORE in the verdict.
- [ ] No DB migration / no device leg (host-only closure + report lane).
- [ ] flutter analyze 0 new; git diff --check clean; graphs refreshed.

## Scope Guard (hard "Do not")
- Do not remove or restructure any feature/visual (glow look, pulse breathing feel beyond subtle timing, labels, unread, presence, find, edit).
- Do not touch the tap-away/double-tap gesture arena (300ms disambiguation stays — follow-up owns it).
- Do not drop `_geometry` from `_measureSignature` (unsafe with arcs expanded — refuted variant).
- Do not scope `_dimFlash`/find keystrokes out of node rebuilds (refuted-as-unattainable).
- Do not modify AmbientBackground, feed_wired's coalescer, or MediaThumbnailImage/avatar decode sites (200 owns decode).
- Do not freeze the unread satellite rotation or badge timers.
- Do not change `ValueKey('orbit-handle-disc-<knob>')`/gesture keys or the wave=0 resting values.

## Accepted Differences / Intentionally Out Of Scope
- Pulse breathing curve differs subtly (blur-animate → opacity-animate) — allowed ("subtle timing changes OK").
- Tap-away ~300ms disambiguation delay remains (spec-pinned; follow-up).
- Decode quantization during sculpt drags — follow-up after plan 200.
- Device-leg perf evidence for the coalescer/hoist (harness bypasses OrbitWired) — host rows carry proof.
- cacheExtent 600 early-mount behavior unchanged — safe as an untested no-change claim ONLY because no planned edit touches `orbit_screen.dart:579` (reviewer-required rationale).

## Dependency Impact
- **Sequence after plan 201**: TC-202-01's finder is key-independent, but 201 rewrites the same Stack children (node/label/badge keys) — landing 202's boundaries first would force 201 to re-touch them.
- **B2 (group publish-all) interplay**: the coalescer routes group refreshes; if B2 has landed, its publish-all flows through the coalescer unchanged (one publish per flush). If B2 has NOT landed, TC-202-08 still holds (load-count semantics) — but land B2 first so ring-visible group updates are what the coalescer batches.
- Plan 200 is independent of 202 (different files) — any order.

## Reviewer Findings
Two independent reviewers (workflow `wf_a8091cae-3b0`, 2026-07-04; 30 + 25 claims spot-verified incl. SDK). Reviewer #1 returned **draft-blocking-findings**, reviewer #2 **sufficient-with-minor-fixes**; ALL findings applied in place:
- **BLOCKING: TC-202-10 vacuous as first drafted** — `AppShellController` defaults to feed (`app_shell_controller.dart:17`) and `switchTo` early-returns on same-tab (`:31-34`), so `switchTo(feed)` triggered nothing and the identity test passed on HEAD. FIXED: real feed→orbit transition (`switchTo(AppShellTab.orbit)`).
- **BLOCKING: TC-202-02/03 finders matched framework boundaries** — `_ModalScope` wraps every route page in RepaintBoundary (SDK `routes.dart:1206/:1231`): the bare ancestor check was vacuously true on HEAD, and the unscoped findsOneWidget could never go green (2 on HEAD → 3 after fix). FIXED: production boundaries get keys (`orbit-handle-boundary-<knob>`, `orbit-ring-boundary`) + feature-scoped keyed finders; root-cause section now records the route-boundary hazard.
- MINOR (applied): TC-202-05 samples the ticker count only after a bounded settle post-drag (ballistic ticker skew); TC-202-06's expected first failure = missing halo key finder; TC-202-12's GREEN leg uses stepped bounded pumps (single long pump leaves opacity ~0); TC-202-09d explicitly exempted from the confirm-red pass (mutation-backed fix-contract guard); cacheExtent Accepted Difference now carries its rationale (no edit touches `orbit_screen.dart:579`); orbit_edit_handle_test anchors corrected (+2 lines); baselines must be re-derived and recorded pre-RED.

## Arbiter Decision
Structural blockers: none remaining (both blocking findings fixed in place; keyed boundaries also make every boundary mutation mechanically verifiable). | Deferred details: coalescer window value confirmation (32ms reuse vs justified alternative) at implementation; group-side spy counter extension shape. | Accepted differences: as listed. Plan is **implementation-ready**, sequenced AFTER plan 201 (and ideally after the B2 publish-all fix).

## Final Execution Verdict
**IMPLEMENTED + host-green 2026-07-04** — on branch `new-orbit`, sequenced on top of plan 201 (`8e655c3b`/`3a46d093`/`7242cb9d`) and B2 (`d1687eca`) + plan 200 (`36a85abb`).

All six production edits + the behavior-inert `debugOnSurfaceBuild` hook landed: (1) RepaintBoundary isolation — per-node (inside the keyed dim Opacity), keyed `orbit-ring-boundary` (inside the editDim Opacity), keyed `orbit-handle-boundary-<knob>`; (2) silent measure update (`_measureCanvasNow` splits first-frame / origin-moved / signature-only); (3) constant-cost pulse — constant resting/armed disc shadow + keyed animated-opacity `orbit-handle-halo-<knob>` layer + `visible` band-hidden freeze threaded from the surface; (4) 32ms trailing-flush refresh coalescer in `orbit_wired` (chat + group message streams + dirty replay enqueue; dispose cancels); (5) three `CurvedAnimation`s hoisted to `late final` initState fields, disposed; (6) `friend_row` motion hygiene (clamp `min(index,12)*20ms` + reduce-motion jump, moved to `didChangeDependencies` with a once-guard).

**RED-first:** the RED batch showed **+1 -9** — nine rows red for their documented reasons (01/02/03 `Found 0 widgets`; 04 `<2>` rebuilds; 05 transient count doesn't track band membership `<6>≠<5>`; 06 `Bad state: No element` on the missing halo key; 07/08 `{...:3}` per-event dispatch; 10 `identical false`; 11/12 opacity `0.0`). TC-202-09d passes on HEAD by design (fix-contract guard — no coalescer timer to leak yet).

**Mutation-verified:** TC-202-09d explicitly (dispose-cancel removed → *"A Timer is still pending … 0:00:00.032000"*, then reverted). Every other row is isolated by its RED-first HEAD revert (single-cause diff, per matrix): node/ring/handle boundary removals, measure-setState restore, blur revert, coalescer bypass, build-time construction, motion-check/clamp drop.

**Gates:** orbit cluster **472**, groups **1041**, feed **285** (untouched — feed coalescer siblings intact), `flutter analyze lib/features/orbit` clean, touched test files **0 new** (1 pre-existing `_textFor` info in the un-touched FriendRow group), `git diff --check` clean. Graphs refreshed (full 108811 nodes; arch 43634 nodes / 926 communities).

**Contracts preserved (churn, not weaken):** TC-198-59 ×2 (edit_handle) + TC-198F-13 (sculpt) re-baselined onto the halo-opacity mechanism; TC-198F-11 (halo colours), TC-203-07/08 (disc size + resting/armed blur) stayed green untouched — resting green halo `0xCC1DB954` blur 10/spread 1 and armed teal `0xCC4ECDC4` blur 20/spread 4 kept.

**Verified deviations from the plan:**
1. **TC-202-05 assertion.** The plan's `visAfter < visBefore` guard is wrong-directioned: a `-400` scroll brings `spacingScale` INTO the band (TC-198-71 documents sp starting below the fold). Replaced with the direction-agnostic identity `transientCallbackCount == c0 + (visAfter − visBefore)` + `visAfter != visBefore` — red on HEAD (count never tracks membership), green on fix, for both enter and leave.
2. **TC-202-08 rejoin counter.** `_SpyGroupRepository` had no `loadGroupRejoinStates` counter (the plan anticipated this) — extended in-file (no production seam change); asserts `getGroupCallCountById == {'g-1':1}` AND `loadGroupRejoinStatesCallCount == 1`.
3. **Node RepaintBoundary is unkeyed** — TC-202-01's by-type finder scoped to the `orbit-node-dim-N` key is unambiguous (grep- and run-verified: zero other RepaintBoundary in the node subtree, incl. `UserAvatar`/`GroupAvatar`/`UnreadOrbitIndicator`). The ring + handle boundaries ARE keyed per the reviewer's `_ModalScope` route-boundary hazard.

**Environment blocker (NOT product):** the report-only PERF_TARGET=ORBIT before/after evidence could NOT run — the macOS desktop build fails at the ObjC Pods layer (`Pods-Runner-dummy.o`, `** BUILD FAILED **`), which pure-Dart changes cannot affect. Per the harness convention the perf lane is report-only and structurally cannot evidence edits 4/5 anyway; the host widget rows carry the behavioral proof (Accepted Difference — device-leg perf capture deferred to a follow-up perf session).

**Closure:** host-only (no DB migration, no device/relay/crypto boundary). Done Criteria met except the perf before/after numbers (environment-blocked, recorded above).
