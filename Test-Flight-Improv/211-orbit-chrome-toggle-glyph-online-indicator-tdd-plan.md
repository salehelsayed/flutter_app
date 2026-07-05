# 211 - Orbit Chrome: View-Toggle Glyph per 207 Mockup + Online Indicator Migration from Feed  (Feature Improvement)

Status: implemented (host-green 2026-07-05 — see Final Execution Verdict)
Spec: Test-Flight-Improv/211-orbit-chrome-toggle-glyph-online-indicator-spec.md (AMENDED §8 post verify→refute)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-05 | Evidence Collector | Explore agent (spec) + workflow `wf_080d7669-809` (4 verify + 4 refute graphify-explorer agents, 431k tokens) | all spec claims grounded; 3 corrections (§8 amendments) | plan |
| 2026-07-05 | Planner | orbit_view_toggle_button.dart, orbit_screen.dart:552-720, expandable_fab.dart, connection_status_indicator.dart, feed_header.dart, feed_screen.dart, run_test_gates.sh:155-260 | design fixed: glyph-only swap + nullable p2pService param + Layer 4b mount before FAB | emit plan |
| 2026-07-05 | Reviewer (sufficiency) | this plan vs sufficiency-checklist | all gates pass; host-only closure (205/206/208/209 class) | hand off |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-05 | contract extraction (git status --short) | — | snapshot taken; tree SHARED with live 212 session (7 claude PIDs, same cwd) — 212 later committed a47a7eaf mid-execution, staging surgically around 211's edits; contested files hash-stable 45s + no write fds before editing | scope confirmed; multi-session flagged | RED |
| 2026-07-05 | RED tests added | orbit_view_toggle_button_test.dart (NEW), orbit_connection_indicator_test.dart (NEW), feed_header_test.dart (rewrite), orbit_wired_test.dart (append TC-211-34) | 4 RED cmds: glyph test red at byIcon(format_list_bulleted) findsNothing; indicator suite compile-RED `No named parameter with the name 'p2pService'` (harness:109); feed_header red at :41 (indicator findsOneWidget on HEAD, pumped with FakeP2PService — arg deleted at E4 with the param); TC-211-34 red findsNothing (:5137) | RED for expected reasons | E1-E6 |
| 2026-07-05 | implementation | E1 orbit_view_toggle_button.dart; E2 orbit_screen.dart (param+thread+Layer 4b before FAB); E3 orbit_wired.dart one-arg; E4 feed_header.dart+feed_screen.dart; E5 run_test_gates.sh (GROUP_TESTS pin + 2 comment fixes); E6 pump harness | scoped files only; FAB stayed LAST Stack child | none | GREEN |
| 2026-07-05 | direct GREEN | — | all 4 direct cmds green (toggle 5, indicator 12, feed_header 3, orbit_wired 85). 2 test-recipe fixes en route: TC-211-13 needed the wide default surface (phone-width canvas puts sculpt bgPoint on a ring node) + settle 16; TC-211-18 offline variant needs a FRESH mount (keyed element survives a repump; a service is a stable identity in production) | reds now green | sentinels |
| 2026-07-05 | preservation GREEN | — | connection_status_indicator_test + orbit_view_split_test + orbit_strings_parity (41) green; orbit_sculpt_summon_wired_test 68 green; INV-211-3 grep gate OK (indicator widget + FTE byte-untouched) | sentinels green | mutations/gates |
| 2026-07-05 | mutation verification | — | live-verified: hardcode 0xBF101218 → light-tone TC-211-03/04 red; drop !innerEditing → TC-211-13 red; move Layer 4b AFTER FAB → TC-211-14 red; remove mount → TC-211-11 red. RED-phase-equivalent (documented): E1 revert ≡ RED cmd 1; E3 revert ≡ RED cmd 4; FeedHeader re-add ≡ RED cmd 3 | all named mutations re-red | named gates |
| 2026-07-05 | named gates | — | `./scripts/run_test_gates.sh feed` 292 green (= 209/210 baseline); `./scripts/run_test_gates.sh groups` 1152 green (1110 baseline + 212 suite + 211 tests); feature-host-all + analyze noted below | gates green | QA |
| 2026-07-05 | QA (independent) | — | analyzer-baseline gate: 211 files contribute ZERO new rows (fixed own hasFlag deprecation → flagsCollection); gate exit 1 ONLY from pre-existing intro_e2e_runner.dart live-session breakage (dbExistsMessageByContent in integration_test/smoke_test.dart + transport_census_harness.dart — NOT 211, see Known-Failure). git diff --check clean | blocking: none | verdict |

## Source Of Truth
- Spec / intent: Test-Flight-Improv/211-orbit-chrome-toggle-glyph-online-indicator-spec.md
- Gate definitions: scripts/run_test_gates.sh (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh (no sim rows in this plan)
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready

## Exact Problem Statement
Two Orbit chrome deltas (user request 2026-07-05). (1) The top-left view-toggle button renders `Icons.chat_bubble_outline` / `Icons.blur_on`, while the ratified 207-mockup chrome vocabulary uses a bullet-list glyph on the inner-circle view and a dot-in-dashed-ring glyph on the all-chats view. Verify→refute established the **container already matches the mockup on the dark tone** (tokens `surfaceSubtle`=0xBF101218, `border`=0x80FFFFFF are exactly the mockup rgba values) — so change 1 is a **glyph-only** swap. (2) The `ConnectionStatusIndicator` ("Offline/Connecting/Online/Online./Online ✦" pill) is stranded on the Feed header while Orbit — the primary surface since 206/209 consolidated identity there — has zero connectivity visibility. It must **move** to Orbit top-right, next to the ExpandableFab "+".

What must improve: toggle glyphs match the 207 vocabulary; the connectivity pill renders on Orbit (both views) next to the "+"; the Feed header no longer shows it.
What must stay unchanged (→ preserved-green sentinels): toggle behavior/key/semantics/position/hide-rules (`orbit_view_split_test`, `orbit_sculpt_summon_wired_test`); toggle container **tokens** (theme-adaptive, NOT hardcoded); `ConnectionStatusIndicator` widget file, API, and full state/telemetry contract (`connection_status_indicator_test`); the FTE screen's own indicator mount; Feed username editing + 206 no-avatar lock; ExpandableFab items/scrim behavior; l10n parity.

## Root Cause (verify → refute confirmed)
Not a bug — a placement/vocabulary gap. Confirmed seams:
- Glyph selection: `lib/features/orbit/presentation/widgets/orbit_view_toggle_button.dart:36` (`isInnerCircle ? Icons.chat_bubble_outline : Icons.blur_on`), sole mount `orbit_screen.dart:578-582` gated `onToggleView != null && !innerEditing`.
- Indicator host: `lib/features/feed/presentation/widgets/feed_header.dart:38-41` (guarded by `p2pService != null`); `feed_screen.dart:210` forwards `widget.p2pService` (its ONLY use in that file). `OrbitScreen` (ctor `orbit_screen.dart:258-303`) has **no** `p2pService` param; `OrbitWired` owns one (`orbit_wired.dart:113`) in scope at the `OrbitScreen(` call (`:2437`). Nullable-param threading precedent: `secureKeyStore` (`orbit_screen.dart:244/299`).
- Insertion site: outer Stack `orbit_screen.dart:560-717`; `ExpandableFab` is the LAST, unconditional child (`:698-715`), renders its own `Positioned.fill` scrim inside its subtree (`expandable_fab.dart:143-158`) → any sibling mounted BEFORE it is dimmed/tap-blocked while the menu is open (the desired precedence). FAB rect: `top: safeTop+8, right: 16`, 40 px (`expandable_fab.dart:123-131`). Top-right is provably free on both views (edit banner is top-CENTER, Reset pill top-LEFT, steppers/find-chips bottom).

Refuted / do-NOT-re-introduce:
1. **Do NOT hardcode the mockup rgba** (`rgba(16,18,24,0.75)` fill / white-0.50 hairline). Dark-tone tokens already equal those values exactly (`background_readable_colors.dart:65,:68`); hardcoding silently breaks the `representativeLight` tone (`:81-92`, picked for `daylightLagoon` `:123-124`) with zero test coverage. Keep `readableColors.surfaceSubtle`/`.border`.
2. **"FeedHeader is the only production host" is FALSE** — `first_time_experience_screen.dart:143-149` also mounts the indicator (live, wired at `first_time_experience_wired.dart:678-690`). Do NOT delete/move/rename `connection_status_indicator.dart` (also imported for `healthFromState`/`ConnectionHealth` by `integration_test/_support/node_readiness.dart:15` and `group_multi_party_device_real_harness.dart:72` — 7+ harnesses).
3. **"All Orbit chrome hides during sculpt-edit" is FALSE** — only Layer 1b hides (`orbit_screen.dart:578` is the single `innerEditing` build gate; the FAB is unconditional). The indicator hides during edit for its own reason: the edit banner spans the full top width (`inner_circle_interactive_surface.dart:691-695`).
4. **No flow-event latch exists** — the TIME_TO_ONLINE_BADGE_WIDGET emit is an instance-level transition check (`connection_status_indicator.dart:121-134`; sink `flow_event_emitter.dart:202-219` does not dedupe). Remount-while-ready does NOT re-emit (initState re-seeds from `currentState`). Only consumer outside the widget suite is a non-asserting headless print loop (`benchmark_node_startup_harness.dart:98-106`) — no gate can break.
5. **No golden tests exist repo-wide; no test pins the toggle's icons or colors** (exhaustive: zero `chat_bubble_outline|blur_on|matchesGoldenFile` hits in test/ + integration_test/) — the glyph swap is test-invisible; key/position/semantics are the only load-bearing contracts.

## Real Scope
In scope: `orbit_view_toggle_button.dart` glyph ternary (+doc comment); `orbit_screen.dart` optional `p2pService` param + Layer 4b indicator mount; `orbit_wired.dart:2437` one-arg pass; `feed_header.dart` indicator + param removal; `feed_screen.dart:210` stop forwarding; test files below; `run_test_gates.sh` GROUP_TESTS pin + 2 comment fixes.
Out of scope (owner): 207's intros affordances (future 207 spec, if ratified); QR/Scan chrome (209 retired it); `BadgeReadinessState`/transport (FDC program); FTE screen chrome (untouched); removing the now-dead `FeedScreen.p2pService` param (optional follow-up — kept to avoid churning 4+ test constructor sites for zero behavior); FAB-vs-edit-banner overlap (pre-existing).

## Files To Inspect Next
Production: `lib/features/orbit/presentation/widgets/orbit_view_toggle_button.dart` (:36), `lib/features/orbit/presentation/screens/orbit_screen.dart` (:258-303 ctor, :378+ _OrbitScreenView threading, :560-717 Stack), `lib/features/orbit/presentation/screens/orbit_wired.dart` (:2437), `lib/features/feed/presentation/widgets/feed_header.dart`, `lib/features/feed/presentation/screens/feed_screen.dart` (:210), `lib/features/p2p/presentation/widgets/connection_status_indicator.dart` (read-only — MUST NOT change).
Direct tests: `test/features/orbit/presentation/screens/orbit_screen_pump_harness.dart` (:27 — extend with pass-through), `test/features/feed/presentation/widgets/feed_header_test.dart` (rewrite in place), `test/features/orbit/presentation/screens/orbit_wired_test.dart` (append), `orbit_view_split_test.dart` / `orbit_sculpt_summon_wired_test.dart` (sentinels, no edits), `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart` (sentinel, no edits; note analyzer-baseline TSV rows :7/:335 pin lint fingerprints — don't reformat).
Dependency-only context: `expandable_fab.dart`, `background_readable_colors.dart`, `inner_circle_interactive_surface.dart:691-724`.

## Existing Tests Covering This Area
- `orbit_view_split_test.dart` (GROUP_TESTS `run_test_gates.sh:245`) — toggle key/position/behavior/RTL/semantics ('Show all chats'/'Show inner circle' pinned :532-552). No icon/color asserts. EXISTS, stays green untouched.
- `orbit_sculpt_summon_wired_test.dart` (GROUP_TESTS :258) — toggle hidden during edit (:2082). EXISTS, sentinel.
- `orbit_qr_entry_migration_test.dart` (GROUP_TESTS :254) — post-209 chrome walk; T3 taps `(width/2 − 24, 28)` expecting background-only → the indicator must stay right-aligned (right:64 band; pill left edge ≥ ~200 px on 390-wide even at 1.5× scale). EXISTS, sentinel.
- `feed_header_test.dart` (FEED_TESTS :184) — 3 tests; `:41` asserts indicator present (breaks BY DESIGN → rewritten in place, stays pinned).
- `connection_status_indicator_test.dart` (glob-only) — full widget contract incl. §24 flow-event tests (host-agnostic `_pumpIndicator`, zero FeedHeader coupling). EXISTS, sentinel, zero edits.
- Sim landmarks: `integration_test/cold_start_message_render_simulator_test.dart:557`, `group_delete_preserves_friends_simulator_test.dart:283` tap the toggle KEY only — unaffected (key preserved).
Missing coverage gaps: no test anywhere expects an indicator on Orbit; no test pins the toggle glyphs; no test guards against hardcoding chrome colors (light-tone).
Already in curated family arrays?: FEED_TESTS: feed_header/feed_wired/feed_swipe (:184/:182/:178). GROUP_TESTS: orbit_wired/orbit_view_split/orbit_qr_entry_migration/orbit_sculpt_summon (:229/:245/:254/:258).

## Design (the fix)
- **E1 — glyphs**: `orbit_view_toggle_button.dart:36` → `final icon = isInnerCircle ? Icons.format_list_bulleted : Icons.motion_photos_on;` (`format_list_bulleted` = three lines + bullets ≡ mockup `IC.list`; `motion_photos_on` = dot centered in dashed ring ≡ mockup `IC.orbit` — closest stock glyphs; keeps the `Icon(size:20, color: textPrimary)` call and the `Semantics(button:true,label:…)` wrapper byte-identical). Fallback if design review rejects fidelity: 20×20 `CustomPaint` reusing `overflow_badge.dart:153` `_DashedBorderPainter` arc math (precedent: `orbit_close_button.dart:39` `_XPainter`) — Semantics wrapper must survive (`orbit_view_split_test.dart:544` finds bySemanticsLabel). Container decoration untouched (tokens already = mockup on dark tone).
- **E2 — OrbitScreen param + mount**: add `final P2PService? p2pService;` (ctor default null, threaded to `_OrbitScreenView` like `secureKeyStore`). New **Layer 4b**, inserted immediately BEFORE the Layer 5 `ExpandableFab` (so the FAB stays LAST → its scrim covers the pill; trailing-scan element matching keeps `_ExpandableFabState` alive across `viewMode`/`innerEditing` flips):
  ```dart
  // Layer 4b: connection-status pill (211) — migrated from the Feed header.
  // Physical right (RTL-safe, same rationale as the toggle); right = 16 (FAB
  // inset) + 40 (FAB) + 8 gap. height:40 + Center keeps the pill vertically
  // aligned with the FAB at any text scale. Hidden during sculpt-edit because
  // the edit banner spans the full top width. Mounted BEFORE the FAB so the
  // open-menu scrim covers it (196/209 precedence convention).
  if (p2pService != null && !innerEditing)
    Positioned(
      key: const ValueKey('orbit-connection-indicator'),
      top: MediaQuery.of(context).padding.top + 8,
      right: 64,
      height: 40,
      child: Center(child: ConnectionStatusIndicator(p2pService: p2pService!)),
    ),
  ```
  Outside the `viewMode` conditional → present on both views, element persists across toggles (no remount ⇒ no flow-event re-emit vector).
- **E3 — wiring**: `orbit_wired.dart:2437` call gains `p2pService: widget.p2pService,`. Zero other call-site edits (4 test files construct OrbitScreen via single helpers; optional param compiles unchanged).
- **E4 — Feed removal**: `feed_header.dart` — delete the `p2pService` field/ctor param, the `if (p2pService != null) …` block, and the now-unused import; doc comment updated ("211 — connection dot migrated to Orbit top-right; 206 locks (no avatar, username editor) unchanged"). `feed_screen.dart:210` — stop passing `p2pService` (FeedScreen keeps its param; add a one-line comment that the dot now lives on Orbit).
- **E5 — harness**: pin the new `orbit_connection_indicator_test.dart` into GROUP_TESTS (after :258, following the 194/196 pin-comment convention). Comment hygiene: fix the stale claim at `run_test_gates.sh:255-257` ("the glob does NOT add it" — the feature-host-all rg glob DOES include it on HEAD) and update the FEED_TESTS `:183` comment ("206: … connection dot preserved" → "206 avatar removal + 211 dot migrated to Orbit").
- **E6 — pump harness**: `orbit_screen_pump_harness.dart:27` gains an optional `P2PService? p2pService` pass-through (1 line).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
1. `test/features/orbit/presentation/widgets/orbit_view_toggle_button_test.dart` (NEW file)
   - `TC-211-01/02 glyphs match 207 vocabulary` — Tier: widget. Pump `OrbitViewToggleButton(viewMode: innerCircle …)` inside `MaterialApp`+`Stack`; expect `find.byIcon(Icons.format_list_bulleted)` findsOneWidget; repump `allChats` → `find.byIcon(Icons.motion_photos_on)`. RED on HEAD: renders `chat_bubble_outline`/`blur_on` → findsNothing. GREEN after E1. Mutation: revert E1 ternary → red.
   - `TC-211-03/04 token lock (light + dark tones)` — pump with a light `readableToneOverride`/theme extension carrying `representativeLight`; assert the `Container` `BoxDecoration.color == readableColors.surfaceSubtle` resolved value (`0xE8EEF2F7`) and border `0x8A101318`; dark-tone variant asserts `0xBF101218`/`0x80FFFFFF`. GREEN on HEAD and after (preservation lock). Mutation: hardcode `Color(0xBF101218)` in the widget → light-tone assert red (guards refuted finding #1).
   - `TC-211-05/08 key + destination semantics` — `ValueKey('orbit-view-toggle')` findsOneWidget; semantics label = l10n `orbit_view_toggle_to_list` on inner / `_to_circle` on list. GREEN sentinel (also pinned in orbit_view_split_test:532-552). Mutation: E1 accidentally dropping the Semantics wrapper → red.
   - `TC-211-10 no handler → no button` — pump bare `OrbitScreen` via harness without `onToggleView` → key findsNothing. GREEN sentinel; mutation: remove the `onToggleView != null` gate → red.
2. `test/features/orbit/presentation/screens/orbit_connection_indicator_test.dart` (NEW file; via `orbit_screen_pump_harness` + `FakeP2PService`)
   - **Whole file is compile-RED on HEAD** (passes `p2pService:` to OrbitScreen — param doesn't exist; document as compile-RED, 209-style).
   - `TC-211-11 renders next to +` — pump with fake service; `find.byType(ConnectionStatusIndicator)` findsOneWidget; geometry: `indicatorRect.right <= fabRect.left` (GlowFab), gap ≤ 12, vertical centers within 2 px, `top < 120`, `center.dx > width/2`. Mutation: remove Layer 4b → red; change `right: 64` → geometry red.
   - `TC-211-12 both views` — repump `viewMode: allChats` → still findsOneWidget. Mutation: move mount inside the innerCircle branch → red.
   - `TC-211-13/29 sculpt-edit hide + re-show with CURRENT state` — drive edit-session-active (recipe from `orbit_sculpt_summon_wired_test` / harness `onInnerCircleEditSessionChanged` path) → indicator findsNothing; emit `ready` while hidden; exit edit → findsOneWidget AND shows `Online` (re-seed from `currentState`, not pre-edit `Offline`). RED (compile). Mutation: drop `!innerEditing` → hide assert red.
   - `TC-211-14 scrim precedence` — tap GlowFab (menu opens, `Key('expandable_fab_scrim')` present); tap at the indicator's center → menu CLOSES (scrim above the pill consumed the tap). Mutation: move Layer 4b AFTER the FAB → pill absorbs the tap, menu stays open → red. (Locks INV-211-4 mount order.)
   - `TC-211-15 RTL` — pump `locale: ar`; indicator stays physical top-right (`center.dx > width/2`), no overlap with toggle. Mutation: switch to `PositionedDirectional` → red.
   - `TC-211-16 no service → absent` — pump without `p2pService` → findsNothing, no crash.
   - `TC-211-17 text-scale 1.5 + 'Online ✦'` — `tester.platformDispatcher.textScaleFactorTestValue = 1.5` (209 precedent), state `onlineDirect`; no overlap with FAB (`indicatorRect.right <= fabRect.left`), `tester.takeException()` isNull.
   - `TC-211-18/27 seeds from currentState` — fake pre-set to `onlineDotted` BEFORE pump → first frame shows `Online.` (no Offline flash); variant: pre-set offline → shows `Offline` on arrival.
   - `TC-211-19 five-state live updates` — stream offline→connecting→online→onlineDotted→onlineDirect; labels track (same strings as widget suite).
   - `TC-211-20 passive` — no `SemanticsFlag.isButton` / no tap handlers on the pill; tapping it (menu closed) triggers nothing (no exception, no state change).
   - `TC-211-21/22 flow event exactly once across toggles` — install flow-event test sink (pattern from `connection_status_indicator_test.dart` §24); mount offline → toggle view (rebuild) → emit ready → toggle again → exactly ONE `TIME_TO_ONLINE_BADGE_WIDGET`; `find.byType(ConnectionStatusIndicator)` findsOneWidget throughout. Mutation: mount one indicator per view branch (two instances) → 2 events → red. (Distinct-event discriminator: assert count==1 of `TIME_TO_ONLINE_BADGE_WIDGET`, and NOT any second emission after rebuilds.)
   - `TC-211-28 remount storm` — repump/unmount ×5 while stream emits → converges to latest state, no "already listened" errors, takeException isNull.
3. `test/features/orbit/presentation/screens/orbit_wired_test.dart` (APPEND — file already GROUP_TESTS :229)
   - `TC-211-34 PROD-CRITICAL wired chain` — pump `OrbitWired` (existing fixture) → `find.byType(ConnectionStatusIndicator)` findsOneWidget seeded from the fixture's `FakeP2PService.currentState`. RED on HEAD: findsNothing (OrbitWired doesn't pass the param yet). Mutation: revert E3 one-arg pass → red. This is the single row proving the production wiring leg (OrbitWired→OrbitScreen→indicator); unit rows alone are NOT sufficient.
4. `test/features/feed/presentation/widgets/feed_header_test.dart` (REWRITE IN PLACE — stays FEED_TESTS :184; never delete/rename)
   - `TC-211-24/26 header has NO connection dot (211), keeps 206 locks` — pump FeedHeader → `find.byType(ConnectionStatusIndicator)` findsNothing; `UserAvatar` findsNothing (206); `EditableUsernameWidget` findsOneWidget. RED on HEAD: indicator present. Mutation: re-add the indicator to FeedHeader → red.
   - `TC-211-25 username editing works` (port of TC-206-15) + narrow-width no-overflow (port of TC-206-16) — GREEN before and after (constructors lose the `p2pService:` arg).
- TC-211-23 (background/resume): justified N/A as a new test — the widget has no lifecycle observer; resume freshness is the existing stream contract, locked by `connection_status_indicator_test` §24 + TC-211-19. TC-211-06/07/09/30/31/32/33 map to preservation sentinels (matrix).

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-211-01 | UI glyph | widget | orbit_view_toggle_button_test.dart::TC-211-01/02 | byIcon(format_list_bulleted) findsNothing (HEAD: chat_bubble_outline) | revert E1 ternary | `flutter test test/features/orbit/presentation/widgets/orbit_view_toggle_button_test.dart` | AUTO (glob) |
| TC-211-02 | UI glyph | widget | same::TC-211-01/02 (allChats leg) | byIcon(motion_photos_on) findsNothing (HEAD: blur_on) | revert E1 ternary | same | AUTO (glob) |
| TC-211-03 | theming lock | widget | same::TC-211-03/04 | n/a — preservation lock (green on HEAD) | hardcode 0xBF101218 fill → light-tone assert red | same | AUTO (glob) |
| TC-211-04 | theming lock | widget | same::TC-211-03/04 (light tone) | n/a — preservation lock | same mutation | same | AUTO (glob) |
| TC-211-05 | key contract | widget | same::TC-211-05/08 + sentinel orbit_view_split_test:405 | n/a — sentinel | rename key → both red | `./scripts/run_test_gates.sh groups` | AUTO + already GROUP_TESTS:245 |
| TC-211-06 | RTL | widget | sentinel orbit_view_split_test:474-483 | n/a — sentinel | PositionedDirectional in toggle → red | `./scripts/run_test_gates.sh groups` | already GROUP_TESTS:245 |
| TC-211-07 | behavior | widget | sentinel orbit_view_split_test:242,434,453 | n/a — sentinel | break onToggle wiring → red | `./scripts/run_test_gates.sh groups` | already GROUP_TESTS:245 |
| TC-211-08 | a11y | widget | orbit_view_toggle_button_test.dart::TC-211-05/08 + orbit_view_split_test:532-552 + l10n parity | n/a — sentinel | drop Semantics wrapper → red | same + `flutter test test/l10n/orbit_strings_parity_test.dart` | AUTO / GROUP_TESTS:245 / GROUP_TESTS:259 |
| TC-211-09 | edit-hide (toggle) | widget | sentinel orbit_sculpt_summon_wired_test:2074/2082 | n/a — sentinel | drop !innerEditing on toggle → red | `./scripts/run_test_gates.sh groups` | already GROUP_TESTS:258 |
| TC-211-10 | conditional mount | widget | orbit_view_toggle_button_test.dart::TC-211-10 | n/a — sentinel | drop null-gate → red | file cmd above | AUTO (glob) |
| TC-211-11 | placement | widget | orbit_connection_indicator_test.dart::TC-211-11 | compile-RED (no p2pService param) + findsNothing | remove Layer 4b / change right:64 | `flutter test test/features/orbit/presentation/screens/orbit_connection_indicator_test.dart` | AUTO + **add to GROUP_TESTS array** (E5) |
| TC-211-12 | both views | widget | same::TC-211-12 | compile-RED | mount inside innerCircle branch only | same | AUTO + GROUP_TESTS (E5) |
| TC-211-13 | edit-hide (pill) | widget | same::TC-211-13/29 | compile-RED | drop !innerEditing on pill | same | AUTO + GROUP_TESTS (E5) |
| TC-211-14 | z-order/scrim | widget | same::TC-211-14 | compile-RED | move mount AFTER FAB | same | AUTO + GROUP_TESTS (E5) |
| TC-211-15 | RTL | widget | same::TC-211-15 | compile-RED | PositionedDirectional | same | AUTO + GROUP_TESTS (E5) |
| TC-211-16 | null-guard | widget | same::TC-211-16 | compile-RED | make param required / mount unconditionally | same | AUTO + GROUP_TESTS (E5) |
| TC-211-17 | text-scale overlap | widget | same::TC-211-17 | compile-RED | remove height:40+Center wrapper | same | AUTO + GROUP_TESTS (E5) |
| TC-211-18 | seed | widget | same::TC-211-18/27 | compile-RED | (indicator internals untouched — mutation = pass a fresh service with default state instead of the wired one at E2 mount) | same | AUTO + GROUP_TESTS (E5) |
| TC-211-19 | live states | widget | same::TC-211-19 | compile-RED | disconnect stream (pass service but render static) | same | AUTO + GROUP_TESTS (E5) |
| TC-211-20 | passivity | widget | same::TC-211-20 | compile-RED | wrap pill in GestureDetector/button semantics | same | AUTO + GROUP_TESTS (E5) |
| TC-211-21 | telemetry once | widget | same::TC-211-21/22 | compile-RED | double-mount (per-view instances) → 2 events | same | AUTO + GROUP_TESTS (E5) |
| TC-211-22 | toggle stability | widget | same::TC-211-21/22 | compile-RED | same double-mount mutation | same | AUTO + GROUP_TESTS (E5) |
| TC-211-23 | lifecycle resume | widget | N/A-justified → covered by connection_status_indicator_test §24 + TC-211-19 (stream contract; widget has no lifecycle observer; identical to Feed-era behavior) | n/a | n/a — sentinel suite | `flutter test test/features/p2p/presentation/widgets/connection_status_indicator_test.dart` | AUTO (glob) |
| TC-211-24 | Feed removal | widget | feed_header_test.dart::TC-211-24/26 | indicator still present on HEAD → findsNothing assert RED | re-add indicator to FeedHeader | `flutter test test/features/feed/presentation/widgets/feed_header_test.dart` | already FEED_TESTS:184 |
| TC-211-25 | Feed preserved | widget | feed_header_test.dart::TC-211-25 | n/a — stays green | break EditableUsernameWidget pass-through | same | FEED_TESTS:184 |
| TC-211-26 | guard path | widget | folded into TC-211-24 (param removed ⇒ single layout path) | see TC-211-24 | same | same | FEED_TESTS:184 |
| TC-211-27 | cross-screen seed | widget | orbit_connection_indicator_test.dart::TC-211-18/27 (offline pre-seed variant) | compile-RED | remove seed usage at mount | file cmd | AUTO + GROUP_TESTS (E5) |
| TC-211-28 | remount storm | widget | same::TC-211-28 | compile-RED | (guards regressions in E2 mount) | file cmd | AUTO + GROUP_TESTS (E5) |
| TC-211-29 | re-show current | widget | same::TC-211-13/29 | compile-RED | cache pre-edit state instead of remount | file cmd | AUTO + GROUP_TESTS (E5) |
| TC-211-30 | regression | widget | sentinels: orbit_view_split/orbit_unread_indicator_wired/orbit_wired/feed_swipe/feed_wired + 2 sim key-taps | n/a | any key/behavior break | `./scripts/run_test_gates.sh groups && ./scripts/run_test_gates.sh feed` | arrays as listed |
| TC-211-31 | widget contract | widget | sentinel connection_status_indicator_test.dart (ZERO edits) | n/a | any edit to the widget file | `flutter test test/features/p2p/presentation/widgets/connection_status_indicator_test.dart` | AUTO (glob) |
| TC-211-32 | chrome inventory | widget | sentinel orbit_qr_entry_migration_test.dart (T3 background-tap must stay clean) | n/a | pill extending toward top-center | `./scripts/run_test_gates.sh groups` | GROUP_TESTS:254 |
| TC-211-33 | l10n parity | unit | sentinel orbit_strings_parity_test.dart (no key changes) | n/a | any arb edit | `flutter test test/l10n/orbit_strings_parity_test.dart` | GROUP_TESTS:259 |
| PROD-CRITICAL | wiring chain | widget (wired host) | orbit_wired_test.dart::TC-211-34 | findsNothing on HEAD | revert E3 | `./scripts/run_test_gates.sh groups` | already GROUP_TESTS:229 |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability**: TC-211-13/29 (re-show after edit re-seeds from `currentState`) + TC-211-18/27/28 (fresh-mount reconstructs). No persisted data involved (pure stream-derived UI) → no process-restart row needed beyond seed tests.
- **Sibling-surface consistency**: glyph mapping applied to BOTH views (TC-211-01/02); indicator on BOTH views (TC-211-12); the third indicator host (FTE screen) deliberately keeps its own mount — asymmetry locked by INV-211-3 (widget file untouched) + Scope Guard grep gate (no diff in `first_time_experience_*`).
- **Destructive-action side-effects**: the removal (TC-211-24) asserts what is REMOVED (indicator) and what is PRESERVED (username editor, 206 no-avatar lock, no-overflow) — TC-211-24/25.
- **Invariant re-verification under new transitions**: edit-exit re-shows with full current state (TC-211-29); FAB open/close cycle leaves pill visible/aligned (TC-211-14 closes the menu and re-asserts); view-toggle transition re-verified for single-instance + single-event (TC-211-21/22).

## Invariants (locked by tests)
- INV-211-1: toggle key/position/destination-semantics/behavior unchanged → orbit_view_split_test (+l10n parity) sentinels.
- INV-211-2: toggle chrome stays TOKEN-driven (no hardcoded rgba) → TC-211-03/04 light-tone lock.
- INV-211-3: `connection_status_indicator.dart` byte-untouched (FTE + `node_readiness.dart` + device-real harness importers) → grep gate in Acceptance Gates + TC-211-31 suite green.
- INV-211-4: pill mounts BEFORE ExpandableFab (scrim wins; FAB stays LAST Stack child) → TC-211-14.
- INV-211-5: exactly one pill on Orbit, zero on Feed → TC-211-21 (findsOneWidget) + TC-211-24.
- INV-211-6: 206 Feed-header locks (no avatar, username editing) survive → TC-211-24/25.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (pre-existing dirty: graphify-arch/*, info.plist, integration_test/group_recovery_e2e_test.dart, lib/core/debug/intro_e2e_runner.dart, scripts/run_sims_detached.sh — do not revert).
2. Add RED tests (catalog §1-4; new indicator file is compile-RED — document the compile error text). Run the four RED commands below; confirm each fails for the documented reason.
3. E1 glyph ternary + widget doc comment (`orbit_view_toggle_button.dart:36`).
4. E6 pump-harness pass-through, then E2 OrbitScreen param + Layer 4b mount (insert between the persistent-nav Row and Layer 5; FAB must remain the LAST child — Stop-if: any need to reorder the FAB → replan, do not hack around the scrim).
5. E3 one-arg pass at `orbit_wired.dart:2437`.
6. E4 Feed removal (feed_header.dart + feed_screen.dart:210 + doc comments).
7. E5 harness pin (GROUP_TESTS entry + comment) + the two comment fixes (run_test_gates.sh:183, :255-257).
8. Rerun direct GREEN → preservation sentinels → named gates (below). `flutter analyze` (analyzer-baseline TSV rows for connection_status_indicator_test/orbit_wired_test must not shift — don't reformat those regions).
9. `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (app-owned lib/ changed).

## Risks And Edge Cases
- Hardcoded-color regression on light backgrounds → pinned by TC-211-03/04.
- Pill drifting toward top-center breaks the qr-migration T3 background tap → pinned by TC-211-32 sentinel + TC-211-11 geometry.
- Double-mount per view (re-emit + double subscription) → pinned by TC-211-21/22.
- FAB State recreation from Stack-suffix churn → pinned by TC-211-14 (menu open/close across the conditional pill) + trailing-scan design note (pill BEFORE FAB, FAB always last).
- Readiness flap across a Feed⇄Orbit pane switch re-emits the flow event (instance semantics, unchanged from Feed era; consumer is print-only) → accepted, documented in spec §8.4.
- `motion_photos_on` fidelity vs mockup `IC.orbit` → user eyeballs on sim after GREEN; fallback CustomPainter route named in E1.

## Device/Relay Proof Profile
**Host-only for closure** (205/206/208/209 class): pure presentation relocation; no OS boundary, no crypto, no relay, no DB (`DB v##`: none), no migration. The nearest transport-touching leg is the unchanged `P2PService.stateStream` contract — already device-proven by the FDC program; the moved mount is proven at wired tier (TC-211-34 PROD-CRITICAL). No new sim scenario ⇒ no classify_path/dart-define changes; `/sims` dry-run not required. Deferred device work: none.

## Acceptance Gates  (literal — copy/paste)
```bash
# RED (before production edits) — must FAIL for the documented reasons
flutter test test/features/orbit/presentation/widgets/orbit_view_toggle_button_test.dart   # RED: byIcon(format_list_bulleted/motion_photos_on) findsNothing
flutter test test/features/orbit/presentation/screens/orbit_connection_indicator_test.dart # RED: compile error — no 'p2pService' named param on OrbitScreen
flutter test test/features/feed/presentation/widgets/feed_header_test.dart                 # RED: ConnectionStatusIndicator findsOneWidget on HEAD (rewritten assert expects none)
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name 'TC-211-34' # RED: findsNothing

# Direct GREEN (after E1-E6)
flutter test test/features/orbit/presentation/widgets/orbit_view_toggle_button_test.dart
flutter test test/features/orbit/presentation/screens/orbit_connection_indicator_test.dart
flutter test test/features/feed/presentation/widgets/feed_header_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart

# Preservation sentinels (must stay green, ZERO edits to these)
flutter test test/features/p2p/presentation/widgets/connection_status_indicator_test.dart  # expect: all pass, file untouched
flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart
flutter test test/l10n/orbit_strings_parity_test.dart                                      # expect: 7/7 (no l10n changes)

# INV-211-3 grep gate — the indicator widget file and FTE screen are byte-untouched
git diff --name-only | grep -E 'connection_status_indicator\.dart|first_time_experience' && echo 'SCOPE VIOLATION' || echo OK

# Named gates for the touched subsystems (baselines at 209/210 close: feed 292, groups 1110 — expect those plus the new 211 tests, all passing; group_conversation_wired_bg_task_test red is PRE-EXISTING at clean HEAD)
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# Hygiene
flutter analyze            # 0 new issues (baseline TSV rows must not shift)
git diff --check
```

## Known-Failure Interpretation
- Expected RED (pre-fix): the four RED commands above, each for its documented reason (one is a compile-RED).
- Pre-existing dirty tree: graphify-arch/* regen artifacts, info.plist, integration_test/group_recovery_e2e_test.dart, lib/core/debug/intro_e2e_runner.dart, scripts/run_sims_detached.sh — NOT ours, do not revert.
- Pre-existing red: `group_conversation_wired_bg_task_test` fails at clean HEAD (recorded at 209 execution) — NOT 211 scope drift.
- Pre-existing red (recorded at 211 execution): a live session's dirty `lib/core/debug/intro_e2e_runner.dart` added a required `dbExistsMessageByContent` param → analyzer errors in `integration_test/smoke_test.dart:149` + `integration_test/transport_census_harness.dart:214`; the analyzer-baseline gate exits 1 on those two rows only. 211 touches neither file; owner = the intro-e2e session.
- Environment blocker (NOT product): none expected (host-only).
- Scope drift (BLOCKING): any diff in `connection_status_indicator.dart`, `first_time_experience_*`, l10n arbs, `expandable_fab.dart`, or any failure in the sentinel suites.

## Done Criteria
- [x] RED added first, failed for the documented reasons (incl. documented compile-RED).
- [x] Mutation-verified: E1 revert / Layer 4b removal / E3 revert / FeedHeader re-add / !innerEditing drop / after-FAB move each re-red their named test (4 live runs + 3 RED-phase-equivalent, see Execution Progress).
- [x] Direct GREEN + preservation sentinels + feed (292) / groups (1152) / feature-host-all (639/640 PASS; sole fail = pre-existing group_conversation_wired_bg_task_test #351) gates pass.
- [x] No DB change (no migration test needed) — confirmed.
- [x] Host-only closure justified (no OS-boundary/multi-device/crypto path touched); PROD-CRITICAL wired-chain row green (TC-211-34).
- [x] New test registered: orbit_connection_indicator_test pinned in GROUP_TESTS; both new suites AUTO-globbed in feature-host-all (#439, #462, PASS).
- [x] flutter analyze 0 new from 211 (own hasFlag deprecation fixed; baseline-gate reds = pre-existing intro_e2e_runner live-session breakage, see Known-Failure); git diff --check clean; INV-211-3 grep gate OK.
- [x] graphify update . + refresh_arch_graph.sh run.

## Scope Guard (hard "Do not")
- Do not edit `lib/features/p2p/presentation/widgets/connection_status_indicator.dart` (API, file path, exports) — FTE + 7 sim/device harnesses depend on it.
- Do not touch `first_time_experience_screen.dart` / `first_time_experience_wired.dart`.
- Do not hardcode chrome colors — tokens only (refuted finding #1).
- Do not change the toggle's key, semantics labels, position, or l10n keys.
- Do not reorder/condition the ExpandableFab or alter `expandable_fab.dart`.
- Do not add intros affordances, QR/Scan chrome, or any 207-mockup element beyond the two requested.
- Do not remove `FeedScreen.p2pService` (kept; follow-up owns it) or edit sim tests / classify_path (no sim surface changed).

## Accepted Differences / Intentionally Out Of Scope
- Pill dims under the FAB scrim while the menu is open (consistent with all Orbit chrome; deliberate, locked by TC-211-14).
- Indicator hides during sculpt-edit while the FAB does not (edit banner spans the top; FAB asymmetry pre-dates 211).
- Readiness-flap re-emit across pane switches (instance semantics unchanged from Feed era; consumer is print-only).
- `FeedScreen.p2pService` becomes a dead param (kept to avoid 4+ test-constructor churn; optional cleanup follow-up).
- `sim_time_to_online_widget_ms` (benchmark print) now reflects the Orbit mount in any full-app run — metric is non-asserting and currently never fires in the headless benchmark anyway.

## Dependency Impact
- 206 (center-avatar Settings entry): its Feed-header lock "connection dot preserved" is deliberately superseded for the dot only; avatar/username locks re-asserted by TC-211-24/25.
- 207 (intros exploration, unratified): this plan consumes only the mockup's top-left glyph vocabulary; a future 207 spec inherits a toggle that already matches its chrome.
- FDC program: consumes `BadgeReadinessState` unchanged; the badge's user-visible home moves to Orbit (update any future FDC device-campaign screenshots/instructions accordingly).

## Reviewer Findings
Sufficiency self-check (references/sufficiency-checklist.md): spec-case totality — all 33 TCs + PROD-CRITICAL row mapped, zero orphans (TC-211-23/26 carry justified merges); every INV locked; every edit mutation-named; no vacuous coverage (token locks are declared preservation locks with named mutations; compile-RED documented); no DB v## (gate N/A); boundaries real-not-faked N/A (host-only class, justified); PROD-CRITICAL named (TC-211-34); sentinels named with commands; gates literal; registration column complete (1 manual pin, rest AUTO/array-existing); known-failure table written; dirty-tree snapshot step 1; refuted findings recorded (§Root Cause). Blind-spot sweep: all four classes have rows or justified N/A. Matrix gate: zero empty cells.

## Arbiter Decision
Structural blockers: none. Deferred details: exact edit-session drive recipe in TC-211-13 (borrow from orbit_sculpt_summon_wired_test at execution); FeedScreen dead-param follow-up. Accepted differences: as listed. Verdict: ready for execution.

## Final Execution Verdict
Verdict: IMPLEMENTED, host-green (2026-07-05). All Done Criteria checked. Glyphs = format_list_bulleted / motion_photos_on (user to eyeball fidelity on sim; CustomPainter fallback named in E1 remains available). Executed on the shared new-orbit tree concurrently with the 212 session (which committed a47a7eaf mid-run); 211's diff is the sole remaining working-tree delta on its files. Uncommitted — commit owned by the user.
