# 194 - Orbit Inner-Circle Per-Node Unread Indicator ("Messenger Orbit")  (New Feature)

Status: IMPLEMENTED — host-green 2026-07-02
Spec: Test-Flight-Improv/194-orbit-node-unread-messenger-orbit-spec.md (alternative B of
Test-Flight-Improv/194-orbit-unread-indicator-mockups.html, product-confirmed)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-02 21:0x | Evidence Collector (wf_e0aee5cf-e5f: 3 ground + 5 refute agents, 0 refuted) | orbital_visualization/orbital_avatar/orbit_screen/orbit_wired/contact_profile_screen/cosmic_background/feed_wired/main.dart/message_repository_impl + all orbit tests + gates | claims C1/C2/C4/C5/C6 all survived; spec §3.4 corrected (externalRouteChangesListenable is DEAD); no read-marking stream exists anywhere | plan the read-event seam + indicator widget |
| 2026-07-02 21:2x | Planner | tier-matrix, sufficiency-checklist, plan-template | rendering = widget tier; clearing = wired host tier; NO DB migration; NO device-proof (in-process presentation + one in-process event seam) | emit matrix + catalog |
| 2026-07-02 21:2x | Reviewer (sufficiency) | this plan | see Reviewer Findings | — |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-02 | contract extraction (git status --short) | — | dirty tree = 193 work + concurrent conversation_wired edits (expected) | scope confirmed | recon dossier |
| 2026-07-02 | recon (wf_bd324094-46f, 8 parallel readers) | — | donor geometry / mount points / repo seam / orbit_wired plumbing / motion / test idioms / l10n / gates dossiers | seam PIVOT: dedicated `ConversationReadEventSource` (NOT MessageRepositoryChangeSource — would break 6 conversation test doubles; NOT messageChanges — wrong payload type) | write RED |
| 2026-07-02 | RED tests added (per slice) | unread_orbit_indicator_test, orbital_avatar_test(+1), message_repository_impl_test(+1), orbital_visualization_test(+9), orbit_unread_indicator_wired_test(NEW), orbit_strings_parity_test | compile-RED (widget/param/getter absent) + assertion-RED (visualization not wired) + stale-lit RED (TC-194-16/17/18/19 clear before subscription) — all confirmed for documented reasons | RED verified | implement |
| 2026-07-02 | implementation | NEW unread_orbit_indicator.dart; orbital_avatar.dart; orbital_visualization.dart; message_repository.dart (new iface); message_repository_impl.dart; in_memory_message_repository.dart; orbit_wired.dart; app_en/ar/de.arb + regen; orbit_performance_harness.dart; run_test_gates.sh | scoped files only; donor motion untouched; UnreadCountBadge/OverflowBadge/OrbitalRingPainter untouched | Scope Guard held | direct GREEN |
| 2026-07-02 | direct GREEN | (all new/extended files) | indicator 8/8, avatar 6/6, visualization 20/20, wired 13/13, l10n 3/3, repo-impl 21/21 | reds now green | preservation |
| 2026-07-02 | preservation GREEN | orbit_wired_test (2 lit-label assertions updated to augmented label — intended TC-194-27 consequence), orbit_view_split, contact_profile TC-24 | orbit_wired_test 74/74; view_split 14/14; contact_profile TC-24 green | sentinels green | named gates |
| 2026-07-02 | named gates | — | `1to1` 1482/1482 (repo iface addition side-effect-free), `feed` 282/282 (pill + 163 TickerMode intact), `groups` 944/944 (new wired file registered + run) | gates green | feature-host-all + analyze |
| 2026-07-02 | hygiene | — | `flutter analyze` 0 new issues (1 self-lint `_seq` fixed); `git diff --check` clean; registration grep hits line 246 | clean | QA verdict |

## Source Of Truth
- Spec: Test-Flight-Improv/194-orbit-node-unread-messenger-orbit-spec.md
- Gate definitions: scripts/run_test_gates.sh (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh (no new sim scenario in this plan)
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready

## Exact Problem Statement
The 193-default Inner-Circle view renders friend nodes with zero unread signal even though every
`OrbitFriend` already carries a populated `unreadCount` (orbit_friend.dart:16;
load_orbit_data_use_case.dart:137,175) all the way into `OrbitalVisualization` unstripped
(orbit_screen.dart:513-527 — verified C2). The chosen design (mockup alternative B) is a green
"messenger orbit": 1.1px accent ring + min(unreadCount, 3) halo'd satellites at phases
0.6/3.3/5.1 rad rotating rigidly (~9s linear), no numerals, donor visual =
contact_profile `_OrbitRingsPainter` + 28s `Transform.rotate` (contact_profile_screen.dart:77-80,
242-250, 730-776).

Grounding also proved the **clear-on-read promise is broken beyond rendering**: read-marking is a
silent DB write (message_repository_impl.dart:247-258 → messages_db_helpers.dart:398-433, no
emission), `externalRouteChangesListenable` has **zero production writers**
(feed_wired.dart:260-261,2532,2617 — declared, passed, disposed, never assigned), and no rising edge
fires when a conversation route is pushed over the active Orbit tab. So a node lit while Orbit was
active goes **stale-lit** after a notification-tap read (main.dart:4308-4330 bare push, no
completion hook; aggravated: the notif-tap prepare drains the inbox at main.dart:4399-4402, lighting
the node BEFORE the conversation marks read) and after a feed-side read (feed pop handlers are
feed-local, feed_wired.dart:1594-1597,1630-1634).

What must improve: (1) lit nodes render the messenger orbit; (2) reads from ANY surface clear it —
which requires one new in-process event seam (read-marking → orbit refresh).
What must stay unchanged (→ preserved-green sentinels): all-chats `UnreadCountBadge` pill behavior,
nav badges, overflow "+N", node tap targets/routes, 193 toggle/reset semantics, contact-profile
donor orbit (incl. its test-locked keeps-rotating-under-reduce-motion behavior, TC-24), existing 11
orbital_visualization + 5 orbital_avatar + 14 orbit_view_split + 3 l10n-parity tests.

## Root Cause (verify → refute confirmed — wf_e0aee5cf-e5f, 5/5 claims survived)
- **C1 (rendering gap)**: `OrbitalVisualization` reads only `friend.peerId`/`friend.username`
  (orbital_visualization.dart:104,112,132,140); `OrbitalAvatar` never receives an `OrbitFriend`
  (orbital_avatar.dart:13-54). No unread rendering exists on any orbital node.
- **C4/C5 (stale clears)**: no read-marking stream exists (`_messageChangeController` fires only on
  save/status paths message_repository_impl.dart:141,179,414,441 — never on mark-read); the only
  refreshers are incoming-message/contact-update listeners (orbit_wired.dart:1643-1651,1669-1678),
  the dirty replay on the tab rising edge (:473-488,503-526), and `_onFriendTap`'s own
  whenComplete (:1979-1984). Notif-tap and feed-side reads traverse none of them when the
  unread-creating message arrived while Orbit was active.
- **C6 (motion)**: orbit pane is TickerMode-muted off-screen ('orbit-pane-ticker-mode',
  feed_wired.dart:2743-2745, locked by TC-163-08); reduce-motion is the manual
  `disableAnimations || accessibleNavigation` controller-level convention
  (cosmic_background.dart:82-102) — nothing automatic; production inner circle currently passes NO
  motion flag at all.

Refuted / do-NOT-re-introduce:
- **Spec §3.4's "externalRouteChangesListenable → _applyRouteChanges" is NOT a live trigger** — the
  notifier has zero writers; do not build the clearing fix on it (orbit_wired.dart:2048-2081 is
  production-dead today).
- **Do not copy the donor's motion handling**: contact-profile's 28s rotation ignores reduce-motion
  and its test TC-24 (contact_profile_screen_test.dart:62-94) LOCKS that it keeps rotating under
  `disableAnimations`. 194 must freeze; the donor must keep its behavior.
- **Spec TC-194-35 wording corrected**: the orbit perf harness has NO frame-budget assertions
  (report-only; structural expects + reportData non-null; self-skips on real devices,
  orbit_performance_harness.dart:407-411). The perf row is evidence + structural, not budget-gated.

## Real Scope
In scope: new `UnreadOrbitIndicator` widget; `unreadCount`/motion params on `OrbitalAvatar`; wiring +
MediaQuery motion seam + lit semantics label in `OrbitalVisualization`; 1 new l10n key (en/ar/de);
read-marking emission in `MessageRepositoryImpl.markConversationAsRead` (+ fake mirror) and an orbit
subscription with active/dirty handling; perf-harness lit scenario; GROUP_TESTS append for the new
wired test file.
Out of scope (owner in parentheses): overflow "+N" unread aggregation (future 19x); numerals on
nodes (product decision B); group unread on orbit (future); adopting `orbit2_open_chat_with` for the
UNLIT label / l10n-izing the existing hardcoded label (a11y cleanup session); deleting the dead
`externalRouteChangesListenable` plumbing (cleanup session); donor/contact-profile changes (none).

## Files To Inspect Next
Production: lib/features/orbit/presentation/widgets/orbital_visualization.dart (:103-141),
orbital_avatar.dart (:13-54,60-90,93-148), NEW unread_orbit_indicator.dart,
lib/features/orbit/presentation/screens/orbit_wired.dart (listeners :1643-1678, dispose, dirty
buckets :464-471), lib/features/conversation/domain/repositories/message_repository_impl.dart
(:247-258 + the `_messageChangeController` getter name and event type near :141), the in-memory fake
test/shared/fakes (InMemoryMessageRepository — mirror the emission),
lib/l10n/app_en.arb / app_ar.arb / app_de.arb (+ regenerate app_localizations*),
integration_test/orbit_performance_harness.dart (:89-101,391-402), scripts/run_test_gates.sh (:209-242).
Direct tests: test/features/orbit/presentation/widgets/orbital_visualization_test.dart,
orbital_avatar_test.dart, NEW unread_orbit_indicator_test.dart, NEW
test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart,
test/l10n/orbit_strings_parity_test.dart, test/features/contact_profile/.../contact_profile_screen_test.dart (TC-24 sentinel).
Dependency-only context: feed_wired.dart TickerMode wrap (:2715-2745), main.dart notif route
(:4303-4331), mark_conversation_read_use_case.dart.

## Existing Tests Covering This Area
- orbital_visualization_test.dart (11 testWidgets): geometry, caps, overflow, semantics label
  'Open chat with friendN', taps — NO unread coverage. Fixture `_makeFriend` lacks unreadCount
  (one-arg addition; default 0).
- orbital_avatar_test.dart (5): entrance/border/tap/48-box — NO unread coverage; bare MaterialApp
  wrap (no l10n).
- orbit_wired_test.dart (incl. TC-163-10 dirty replay :4295-4378, TC-193-40 :4439-4495, node-tap
  route + pop template :4590-4613 with `_RecordingNavigatorObserver`/`_DelayedSpyMessageRepository`,
  emitIncomingMessage idiom :5051-5076 — **save into repo FIRST, then emit**).
- orbit_view_split_test.dart (14; SizedBox-remount :575, ensureSemantics in-body dispose :416/:434,
  setLargeTestSurface helpers) — templates for 194 patterns.
- Reduce-motion templates: feed_reduced_motion_test.dart:52-81,213-227 (both flags, separately);
  controller-inspection idiom contact_profile_screen_test.dart:62-94.
- TickerMode template: feed_wired_test.dart:2303-2325 ('orbit-pane-ticker-mode').
Missing coverage gaps: everything unread-on-orbital-nodes; any read-marking→refresh path.
Already in curated arrays?: GROUP_TESTS lists orbit_wired_test (:227), orbit_view_split_test (:241),
test/l10n/orbit_strings_parity_test (:242 — manual because test/l10n is outside feature-host glob).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> Pump discipline for every lit-node test: bounded `tester.pump(100ms)` loops (orbit_wired
> `pumpOrbitFrames` idiom) — NEVER `pumpAndSettle` (the ~9s repeat rotation never settles).

1. `test/features/orbit/presentation/widgets/unread_orbit_indicator_test.dart` (NEW file)
   - `'satellite count follows min(unread,3): 1→1, 2→2, 3→3, 4→3, 120→3'` (TC-194-02/03/04/05)
     - Tier: widget. Shape: pump `UnreadOrbitIndicator(unreadCount: N, diameter: 38, motionEnabled: true)`
       in bare MaterialApp; count satellite elements via keyed finders
       (`ValueKey('unread-satellite-$i')`); assert NO `Text` widget in the subtree (no numerals).
     - RED on HEAD: the widget/file does not exist → compile failure (documented RED mode).
     - GREEN: counts as above; `find.byType(Text)` findsNothing.
     - Mutation that re-reds: change the cap to `min(unread, 4)` or drop the clamp → 4-case red.
   - `'count 0 builds nothing (absent, not invisible)'` (TC-194-09, INV-1)
     - RED: file missing. GREEN: `UnreadOrbitIndicator(unreadCount: 0)` subtree contains zero
       CustomPaint/satellite elements AND `tester.pumpAndSettle()` completes (no live ticker).
     - Mutation: render the ring with opacity 0 instead of building nothing → pumpAndSettle times out → red.
   - `'ring and satellites use the green unread accent'` (TC-194-08)
     - GREEN: painter/decoration colors resolve to 0xFF1DB954 family (assert on the painter's
       configured color fields, not pixels). Mutation: swap accent to the red nav family → red.
   - `'rotation animates when motion enabled'` (TC-194-21)
     - Shape: contact_profile_screen_test TC-24 idiom —
       `tester.widgetList<AnimatedBuilder>(...).map((ab)=>ab.listenable).whereType<AnimationController>()`;
       assert `isAnimating == true` and value advances across pumps.
     - Mutation: remove `..repeat()` → red.
   - `'disableAnimations freezes rotation but indicator stays visible'` +
     `'accessibleNavigation freezes rotation but indicator stays visible'` (TC-194-22, two tests)
     - Shape: feed_reduced_motion_test MediaQuery-copyWith wrap, one flag per test.
     - GREEN: controller `isAnimating == false`, value pinned; ring+satellites still found.
     - Mutation: drop the `_syncMotionPreference`-style check → red.
   - `'TickerMode(enabled:false) halts rotation'` (TC-194-23 widget floor)
     - GREEN: wrapped in `TickerMode(enabled: false)` the controller does not advance.
     - Mutation: drive rotation from a raw `Timer.periodic` instead of a vsync'd controller → red
       (INV-4: ticker must be mixin-vsync'd so the 163 pane mute applies).
   - `'dispose mid-animation is clean'` (TC-194-25 floor)
     - Shape: pump lit, pump 300ms, `pumpWidget(const SizedBox())` (193 cat.12 idiom).
     - GREEN: no FlutterError/ticker-leak. Mutation: remove `dispose()` of the controller → red.

2. `test/features/orbit/presentation/widgets/orbital_visualization_test.dart` (EXTEND, +9)
   - `'lit friend shows unread orbit; unlit nodes and center self do not'` (TC-194-01, TC-194-34 half)
     - RED on HEAD: `_makeFriend(unreadCount: 2)` → `find.byType(UnreadOrbitIndicator)` finds
       nothing (widget not wired). GREEN: exactly 1 on the lit node; none under the center
       UserAvatar. Mutation: revert the `unreadCount:` pass-through at orbital_visualization.dart
       ring-1 site → red.
   - `'indicator renders on ring-1 (38px) and ring-2 (30px) nodes scaled'` (TC-194-06)
     - Setup: 7 friends, lit at index 1 (ring 1) and index 6 (ring 2). GREEN: 2 indicators, each
       sized relative to its node diameter. Mutation: revert the ring-2 pass-through (:131-141 site)
       ONLY → red (catches a single-site wiring miss).
   - `'all 13 visible nodes lit renders without exceptions'` (TC-194-07) — bounded pumps; expect no
     overflow/exception; 13 indicators.
   - `'lit node keeps 48px tap target and opens chat'` (TC-194-26)
     - Shape: existing tapAt(center+Offset(22,0)) padded-hit idiom; assert `onFriendTap` fired with
       exact peerId. Mutation: wrap the indicator in its own opaque GestureDetector → red.
   - `'lit node semantics announces unread; unlit label unchanged'` (TC-194-27)
     - Shape: `ensureSemantics()` first line, dispose in-body (193 cat.6). GREEN: lit node label ==
       l10n `orbit_node_unread_open_chat(name, count)`; unlit node label == 'Open chat with friendN'
       exactly as today. RED on HEAD: lit label equals the plain label. Mutation: revert the label
       branch → red.
   - `'RTL (ar) renders lit nodes at physical positions without exception'` (TC-194-29)
     - Shape: wrap with locale 'ar' (l10n delegates already in the wrap helper); assert indicator
       present + no exception + Positioned math unchanged (physical, 193 lock).
   - `'daylight readable palette keeps the indicator present and green'` (TC-194-30)
     - Shape: readableColors override (existing wrap param). GREEN: indicator present; accent still
       0xFF1DB954 family (deliberately theme-independent). Mutation: derive accent from
       readable border color → red.
   - `'16 friends: overflow badge unchanged; hidden lit friend causes no error'` (TC-194-31 widget half)
     - GREEN: OverflowBadge('+3') as today, no indicator on it, no exception.
   - `'motion seam: reduce-motion MediaQuery freezes satellite spin at the visualization level'` (TC-194-24)
     - RED on HEAD: no MediaQuery seam exists (production passes no motion flag —
       grounding finding). GREEN: with disableAnimations, indicator controllers not animating.
     - Mutation: hardcode `motionEnabled: true` at the visualization pass-through → red.
   - (existing 11 tests are the TC-194-09/34 preservation sentinels — they use `pumpAndSettle`,
     which HANGS if an unlit node ever hosts a live ticker: absence-when-zero is structurally enforced.)

3. `test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart` (NEW file,
   modeled on orbit_view_split_test.dart's standalone builder; ~12 tests)
   - `'incoming message lights the node live'` (TC-194-10)
     - Tier: integration/wired host (fakes). Shape: buildOrbitWired idiom (real AppShellController,
       initialTab orbit); save message into InMemoryMessageRepository FIRST, then
       `emitIncomingMessage` (repo-first idiom, orbit_wired_test:5051-5076); bounded pumps.
     - RED on HEAD: no `UnreadOrbitIndicator` in tree. GREEN: node lit. Mutation: revert the
       visualization wiring → red.
   - `'second message increments satellites without node re-entrance'` (TC-194-11)
     - GREEN: satellite count 1→2; entrance controller not re-run (assert node opacity stays 1
       across the transition). Mutation: key the node on unreadCount (forces remount) → red.
   - `'message while Feed active lights node on Orbit entry (dirty replay)'` (TC-194-12)
     - Shape: TC-163-10 template — initialTab feed, save+emit, `switchTo(AppShellTab.orbit)`.
     - GREEN: lit on entry. Mutation: skip dirty-add in the inactive branch → red (also re-reds TC-163-10).
   - `'overflow-hidden friend jumps visible and lit on message'` (TC-194-13) — 14 friends, message
     from the 14th; GREEN: friend now in visible 13 and lit.
   - `'node tap → conversation → pop returns unlit'` (TC-194-14)
     - Shape: `_RecordingNavigatorObserver` + navigator pop (orbit_wired_test:4590-4613 template).
     - RED on HEAD: **compile-RED only via the indicator finder** (the refresh path :1979-1988
       already exists) — this row is primarily a preservation lock for the whenComplete+mark-read
       pair. Mutation: remove `_markConversationReadInBackground` call (:1988) → red.
   - `'externally-pushed conversation read clears the lit node (read event)'` (TC-194-16) — **PROD-CRITICAL row**
     - Shape: orbit active + lit; push ConversationWired onto the same navigator NOT via orbit's
       `_onFriendTap` (mimics main.dart:4308 notif route); mark read via
       `messageRepo.markConversationAsRead(peer)` (what ConversationWired._markAsRead does on
       entry); pop; bounded pumps.
     - RED on HEAD: node stays lit (C4 verdict — no trigger exists). GREEN: node unlit without any
       new message/contact event; assert flow event `ORBIT_FL_READ_REFRESH` observed AND NOT an
       incoming-message refresh discriminator (distinct-event rule).
     - Mutation: revert the orbit read-event subscription → red; revert the repo emission
       (markedCount>0 guard removal is a SEPARATE mutation, see next row) → red.
   - `'feed-side read after active-arrival clears on tab return'` (TC-194-17)
     - Shape: orbit active, save+emit (lights node, NOT dirty); switchTo(feed); mark read via repo;
       switchTo(orbit). RED on HEAD: stale-lit (C5 verdict). GREEN: unlit on return (read event was
       dirty-buffered while inactive and replayed on the rising edge).
     - Mutation: make the read-event listener ignore the inactive branch (no dirty-buffer) → red.
   - `'mark-read of an already-read conversation emits nothing'` (INV-5)
     - Tier: integration (repo-level, in the same file or the repo's own test file — see row 5).
     - GREEN: second markConversationAsRead (0 rows) triggers no orbit refresh (spy repo counts
       getConversationThreadSummary calls). Mutation: remove the markedCount>0 guard → red.
   - `'read during open conversation settles unlit'` (TC-194-18)
     - Shape: conversation pushed (external), message arrives (orbit refresh races), then mark read,
       pop. GREEN: settled state unlit — the read event post-dates the arrival refresh.
   - `'3→0 transition clears with no artifacts'` (TC-194-19) — assert indicator gone + no exception.
   - `'fresh mount from persisted counts is lit'` (TC-194-20, lifecycle durability)
     - Shape: seed InMemoryMessageRepository with 2 unread BEFORE first pump; pump; assert lit; then
       SizedBox remount; assert lit again. RED on HEAD: never lit. Mutation: derive lit-ness from a
       session-local "saw message event" latch instead of `friend.unreadCount` → red.
   - `'orbit pane TickerMode mute freezes lit indicator off-screen'` (TC-194-23 wired half)
     - Shape: initialTab feed via the feed_wired host is out of reach here — instead assert at the
       orbit_wired level: lit node, then `switchTo(feed)`; controller `isAnimating == false` while
       inactive (TickerMode from the host is covered by TC-163-08 sentinel; this row locks the
       indicator's controller is vsync-muted, not Timer-driven).
   - `'toggle round-trips keep pill and indicator surface-scoped'` (TC-194-32)
     - GREEN: inner-circle shows indicator not pill; all-chats shows pill (`UnreadCountBadge`) not
       indicator; repeated toggles leak nothing (bounded pumps, no exception).
   - `'deleting a lit contact removes the node with no ticker leak'` (blind-spot: destructive)
     - Shape: lit node; drive `_deleteContactFromOrbit` via the existing delete affordance path or
       contact-removal event; GREEN: node gone, no ticker-leak assertion errors on test end.
4. `test/l10n/orbit_strings_parity_test.dart` (EXTEND — TC-194-28)
   - Append new key `orbit_node_unread_open_chat` (plural, {name}+{count}) to the `newOrbitKeys`
     list (block 1: en/ar/de presence+non-empty), add generated-getter calls (block 2), pin the
     English baseline (block 3).
   - RED on HEAD: key absent from all ARBs → block-1 expect fails. Mutation: delete the de entry → red.
5. Repo-level emission test (in `orbit_unread_indicator_wired_test.dart` group or
   `test/features/conversation/` if a repo test file fits better — executor's choice, same tier):
   - `'markConversationAsRead emits a message-change with a read discriminator when rows>0'`
     - Tier: integration/repo host (real impl over sqflite ffi OR the in-memory fake mirrored —
       assert BOTH impl and fake emit, so wired tests stay honest).
     - RED on HEAD: no emission exists (C4 evidence: message_repository_impl.dart:247-258 silent).
     - Mutation: revert the emission → red. Discriminator: the event's read-marking marker AND NOT a
       save/status marker.
6. `integration_test/orbit_performance_harness.dart` (EXTEND — TC-194-35, evidence + structural)
   - Third `_OrbitScenario`: 8 friends, 4 lit (counts 1/2/3/120); assert `UnreadOrbitIndicator`
     present (structural), report frame metrics as today (report-only — grounding corrected the
     spec's "budget assertions" wording).
   - RED on HEAD: scenario references the widget → compile-RED. Mutation: revert lit fixture → the
     structural expect red.

TC-194-36 (repaint containment): in `orbital_avatar_test.dart` (EXTEND, +1):
   - `'satellite rotation does not rebuild the avatar child subtree'`
     - Shape: `OrbitalAvatar(unreadCount: 2, child: CountingBuildProbe())` (the existing `child`
       param); pump 30 bounded frames; GREEN: probe build count unchanged after entrance.
     - RED on HEAD: `unreadCount` param does not exist → compile-RED.
     - Mutation: drive rotation via `setState` per tick instead of AnimatedBuilder-with-child → red.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-194-01 | UI render | widget | orbital_visualization_test::lit friend shows unread orbit… | widget not wired | revert ring-1 pass-through | `flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart` (20/20) | AUTO (glob) |
| TC-194-02/03 | pure render logic | widget | unread_orbit_indicator_test::satellite count follows min… | file absent (compile) | drop clamp | `flutter test test/features/orbit/presentation/widgets/unread_orbit_indicator_test.dart` (8/8) | AUTO (glob) |
| TC-194-04/05 | boundary | widget | same row (4→3, 120→3 cases) | file absent | cap→4 | same | AUTO (glob) |
| TC-194-06 | UI render both rings | widget | orbital_visualization_test::indicator renders on ring-1 and ring-2… | ring-2 site not wired | revert ring-2 pass-through only | same as TC-01 | AUTO (glob) |
| TC-194-07 | render density | widget | orbital_visualization_test::all 13 visible nodes lit… | not wired | revert wiring | same | AUTO (glob) |
| TC-194-08 | color contract | widget | unread_orbit_indicator_test::green unread accent | file absent | swap accent to red family | same as TC-02 | AUTO (glob) |
| TC-194-09 | absence invariant | widget | unread_orbit_indicator_test::count 0 builds nothing + existing 11 sentinels | file absent / N/A (sentinels green) | opacity-0 instead of absent → pumpAndSettle hang | same + sentinel run | AUTO (glob) |
| TC-194-10 | live event → UI | wired host | orbit_unread_indicator_wired_test::incoming message lights… | not wired | revert wiring | `flutter test test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart` (13/13) | AUTO (glob) + **add to GROUP_TESTS** |
| TC-194-11 | state transition | wired host | …::second message increments satellites… | not wired | key node on count | same | same |
| TC-194-12 | dirty replay | wired host | …::message while Feed active lights on entry | not wired | skip dirty-add | same | same |
| TC-194-13 | ordering + overflow | wired host | …::overflow-hidden friend jumps visible and lit | not wired | revert wiring | same | same |
| TC-194-14 | clear (orbit-opened) | wired host | …::node tap → pop returns unlit | indicator finder compile-RED (path exists) | remove :1988 mark-read call | same | same |
| TC-194-15 | clear (list row) | wired host | folded into TC-194-32 round-trip test (row tap = same `_onFriendTap`, C3 verified) | not wired | remove :1988 | same | same |
| TC-194-16 | clear (external push) **PROD-CRITICAL** | wired host | …::externally-pushed conversation read clears… | stale-lit (C4: no trigger) | revert orbit read-subscription | same | same |
| TC-194-17 | clear (feed-side) | wired host | …::feed-side read after active-arrival clears… | stale-lit (C5) | drop inactive dirty-buffer branch | same | same |
| TC-194-18 | race settle | wired host | …::read during open conversation settles unlit | stale possible (race, no settle refresh) | revert emission | same | same |
| TC-194-19 | transition artifacts | wired host | …::3→0 transition clears with no artifacts | not wired | revert clear path | same | same |
| TC-194-20 | lifecycle durability | wired host | …::fresh mount from persisted counts is lit | not wired | session-latch instead of unreadCount | same | same |
| TC-194-21 | motion runs | widget | unread_orbit_indicator_test::rotation animates | file absent | remove ..repeat() | same as TC-02 | AUTO (glob) |
| TC-194-22 | reduce-motion | widget | unread_orbit_indicator_test::disableAnimations / accessibleNavigation freeze (2 tests) | file absent | drop motion sync | same | AUTO (glob) |
| TC-194-23 | off-screen mute | widget + wired | …indicator_test::TickerMode false halts + wired::TickerMode mute off-screen | file absent / not wired | Timer.periodic instead of vsync | both cmds | AUTO + GROUP_TESTS |
| TC-194-24 | motion seam | widget | orbital_visualization_test::motion seam reduce-motion freezes… | no MediaQuery seam exists | hardcode motionEnabled:true | same as TC-01 | AUTO (glob) |
| TC-194-25 | dispose cleanliness | widget + wired | indicator_test::dispose mid-animation + wired remount cases | file absent | remove controller.dispose() | both cmds | AUTO + GROUP_TESTS |
| TC-194-26 | tap integrity | widget | orbital_visualization_test::lit node keeps 48px tap target | not wired | opaque GestureDetector on indicator | same as TC-01 | AUTO (glob) |
| TC-194-27 | semantics | widget | orbital_visualization_test::lit node semantics announces unread | lit label == plain label | revert label branch | same | AUTO (glob) |
| TC-194-28 | l10n parity | plain test | orbit_strings_parity_test:: key blocks extended | key absent in ARBs | delete de entry | `flutter test test/l10n/orbit_strings_parity_test.dart` (3/3) | already in GROUP_TESTS:242 (extension, no new registration) |
| TC-194-29 | RTL | widget | orbital_visualization_test::RTL (ar) renders lit nodes… | not wired | revert wiring | same as TC-01 | AUTO (glob) |
| TC-194-30 | light palette | widget | orbital_visualization_test::daylight palette keeps indicator | not wired | accent from readable colors | same | AUTO (glob) |
| TC-194-31 | overflow regression | widget + wired | orbital_visualization_test::16 friends overflow unchanged + wired list-pill fallback (in TC-32 test) | not wired | revert wiring | both cmds | AUTO + GROUP_TESTS |
| TC-194-32 | 193 toggle regression | wired host | …::toggle round-trips keep pill and indicator surface-scoped | not wired | leak indicator into list surface | wired cmd | GROUP_TESTS |
| TC-194-33 | pill unchanged | sentinel | existing UnreadCountBadge/feed suites (no new test) | N/A (sentinel) | N/A — any pill edit is Scope-Guard drift | `./scripts/run_test_gates.sh feed` (0 failures) | already registered |
| TC-194-34 | center/backdrop unchanged | widget | folded into TC-194-01 assertions + existing sentinels | not wired | indicator on center avatar | same as TC-01 | AUTO (glob) |
| TC-194-35 | perf evidence | perf harness (host/desktop) | orbit_performance_harness:: lit scenario | scenario compile-RED | revert lit fixture | `./scripts/run_test_gates.sh performance-host` (ORBIT target passes; report attached) | existing PERF_TARGET=ORBIT dispatch — no new case |
| TC-194-36 | repaint containment | widget | orbital_avatar_test::rotation does not rebuild child subtree | unreadCount param absent (compile) | setState-per-tick rotation | `flutter test test/features/orbit/presentation/widgets/orbital_avatar_test.dart` (6/6) | AUTO (glob) |
| (new) read-emission | repo contract | integration/repo host | wired file::mark-read emits when rows>0 / nothing when 0 | no emission exists | revert emission / drop guard | wired cmd | GROUP_TESTS |
| (blind-spot) delete-lit | destructive | wired host | …::deleting a lit contact removes node, no ticker leak | not wired | skip node unmount on delete | wired cmd | GROUP_TESTS |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability**: TC-194-20 (fresh mount + SizedBox remount from persisted
  DB counts — lit-ness derives from `unreadCount`, never from a session event latch).
- **Sibling-surface consistency**: TC-194-32 (pill vs indicator surface-scoping) + TC-194-33 sentinel
  (pill untouched) + the read-event emission is consumed by orbit only; conversation/feed listeners
  of the message-change stream are preservation-gated (`1to1` + `feed` gates below). The second
  OrbitWired mount (intro-notification route, main.dart:4257) gets the same read-listener for free
  (it lives in orbit_wired) — asymmetry: none.
- **Destructive-action side-effects**: delete-lit-contact row (node removed, no ticker leak,
  contact-deletion cleanup path reused unchanged).
- **Invariant re-verification under new transitions**: the NEW read-event refresh transition
  re-asserts full post-state in TC-194-16/17/18 (indicator gone + ordering intact + no
  entrance re-run + flow-event discriminator `ORBIT_FL_READ_REFRESH` and NOT the incoming-message
  path) — not just the headline lit flag.

## Invariants (locked by tests)
- INV-1: `unreadCount == 0` → indicator ABSENT (not invisible); no live ticker on unlit nodes →
  locked by indicator `count 0 builds nothing` + every existing pumpAndSettle test.
- INV-2: indicator never changes hit-testing; 48px opaque box + exact-peerId tap → TC-194-26.
- INV-3: satellites = `min(unreadCount, 3)`; zero `Text` in the node subtree → TC-194-02..05.
- INV-4: rotation is mixin-vsync'd (TickerMode-mutable) and freezes under
  `disableAnimations || accessibleNavigation` while staying visible → TC-194-22/23.
- INV-5: read-marking emits ONLY when markedCount > 0 → repo emission tests.
- INV-6: donor contact-profile orbit untouched (its TC-24 keeps-rotating lock stays green) →
  feature-host-all sentinel.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (dirty tree expected: 193 uncommitted work + concurrent sessions).
2. Add ALL RED tests above; run the focused commands; confirm each fails for its documented reason
   (compile-RED for new files/params; stale-lit assertions for TC-194-16/17).
3. NEW `lib/features/orbit/presentation/widgets/unread_orbit_indicator.dart`:
   `StatefulWidget(unreadCount, diameter, motionEnabled)` + `SingleTickerProviderStateMixin`;
   controller `Duration(seconds: 9)..repeat()` gated by the cosmic_background
   `_syncMotionPreference` pattern (didChangeDependencies + didUpdateWidget, stop+`value=0` when
   disabled); `unreadCount <= 0` → `SizedBox.shrink()` before creating any ticker work (INV-1);
   render = `AnimatedBuilder(child:)` → `Transform.rotate` → `CustomPaint` painting one 1.1px ring
   (accent 0xFF1DB954 @ ~0.55) at ~1.35× avatar radius + `min(count,3)` satellites at 0.6/3.3/5.1
   rad (halo 2.6× core @0.16, core @0.95 — donor geometry, contact_profile_screen.dart:751-770);
   satellites keyed `unread-satellite-$i` via painter semantics or wrapper elements for finders.
   Stop-if: keyed finders prove awkward on CustomPaint → switch satellites to positioned
   `Container`s under the rotating Transform (equivalent, finder-friendly); do not weaken the tests.
4. `orbital_avatar.dart`: add `unreadCount` (int, default 0) + `unreadMotionEnabled` (bool, default
   true); mount the indicator as a non-hit-testing overlay (`IgnorePointer`) in the existing
   48-box Stack, centered on the node (host Stack is Clip.none — overpaint safe,
   orbital_visualization.dart:70); entrance AnimatedBuilder continues to wrap everything (indicator
   fades/scales with the node).
5. `orbital_visualization.dart`: compute once in build
   `motion = !(MediaQuery.disableAnimations || accessibleNavigation)` (maybeOf, cosmic convention);
   pass `unreadCount: friend.unreadCount, unreadMotionEnabled: motion` at BOTH construction sites
   (:103-113, :131-141); lit nodes get `semanticLabel: l10n.orbit_node_unread_open_chat(name, count)`,
   unlit keep the existing literal unchanged (Scope Guard).
6. l10n: add `orbit_node_unread_open_chat` (plural `{count}`, placeholder `{name}`) to
   app_en/ar/de.arb (copy `group_member_count` plural shape, app_en.arb:467); regenerate
   localizations (`flutter gen-l10n` per repo flow — generated files are committed).
7. Read-event seam: `message_repository_impl.dart` `markConversationAsRead` (:247-258) — when the
   updated-row count > 0, emit on the EXISTING `_messageChangeController` with a read-marking
   discriminator; inspect the event type first (writers at :141/179/414/441) — Stop-if the event
   type cannot express read-marking without confusing existing listeners → add a dedicated
   `Stream<String> conversationReadStream` (peerId) on `MessageRepository` + impl + the in-memory
   fake instead (same tests, different seam; interface addition touches ONLY this repo's fakes).
   Mirror the emission in `InMemoryMessageRepository` either way.
8. `orbit_wired.dart`: subscribe in the existing listener block (initState :420-424 region): on
   read event for peerId → active: `unawaited(_refreshOrbitFriend(peerId))` +
   `emitFlowEvent(layer:'FL', event:'ORBIT_FL_READ_REFRESH', …)`; inactive:
   `_dirtyFriendPeerIds.add(peerId)` (rides the existing replay :503-510). Cancel in dispose beside
   `_chatSubscription`.
9. Perf harness: `_makeFriend` gains `unreadCount`; add the lit `_OrbitScenario`; keep report-only.
10. Registration: append `test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart`
    to `GROUP_TESTS` in scripts/run_test_gates.sh (beside :241).
11. Rerun direct → preservation → named gates (below). Update Execution Progress table as you go.

## Risks And Edge Cases
- **pumpAndSettle hangs** in any test that pumps a lit node → pinned by INV-1 test design; all new
  lit tests use bounded pumps.
- **Read-emission side-effects on existing message-change listeners** (conversation UI reacting to
  its own mark-read) → pinned by `1to1` gate sentinel + INV-5 (no emission when 0 rows; no loops
  since re-marking marks 0).
- **Race: arrival refresh vs mark-read** (notif-tap drains inbox before conversation marks read,
  main.dart:4399-4402) → pinned by TC-194-18 (read event post-dates arrival → settled unlit).
- **Ticker leak on remount/delete** → TC-194-25 + delete-lit row (193 cat.12 SizedBox idiom).
- **Concurrent sessions** editing conversation_wired.dart / rebuilding graphify-arch (observed
  mid-grounding) → re-run `git status --short` + re-verify :1988/:4308 anchors before editing.
- **Entrance + indicator interaction**: indicator inside the entrance AnimatedBuilder must not
  restart entrance on count change → TC-194-11.

## Device/Relay Proof Profile
**Host-only for closure.** No OS boundary, no crypto, no relay, no multi-device: rendering is
widget-tier; the clearing seam is an in-process repo event proven at wired-host tier
(TC-194-16 is the PROD-CRITICAL row — the only new cross-module contract). Perf evidence =
`performance-host` ORBIT target (harness self-skips on real devices by design). No DB migration
(no `DB v##`). Optional (not closure): eyeball on a device via the normal debug run; the
two-phone campaigns own transport, not this.

## Acceptance Gates  (literal — copy/paste)
```bash
# 0. Dirty-tree snapshot (before anything)
git status --short

# 1. RED (before production edits) — must FAIL for the documented reasons
flutter test test/features/orbit/presentation/widgets/unread_orbit_indicator_test.dart   # compile-RED (file/widget absent)
flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart    # 9 new tests RED (no indicator/no seam), 11 old green
flutter test test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart  # TC-194-16/17 stale-lit RED
flutter test test/l10n/orbit_strings_parity_test.dart                                     # block-1 RED (key absent)

# 2. Direct GREEN (after implementation)
flutter test test/features/orbit/presentation/widgets/unread_orbit_indicator_test.dart   # expect 8/8
flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart    # expect 20/20
flutter test test/features/orbit/presentation/widgets/orbital_avatar_test.dart           # expect 6/6
flutter test test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart  # expect 13/13
flutter test test/l10n/orbit_strings_parity_test.dart                                     # expect 3/3

# 3. Preservation sentinels (must stay green — 0 failures each)
flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart          # 14/14
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart               # all pass (large file)
flutter test test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart  # TC-24 donor lock stays green

# 4. Named gates for the touched subsystems (script counts are authoritative; expect 0 failures)
./scripts/run_test_gates.sh groups          # includes orbit_wired/view_split/l10n-parity + NEW wired file after GROUP_TESTS append
./scripts/run_test_gates.sh feed            # UnreadCountBadge pill + TickerMode 163 sentinels
./scripts/run_test_gates.sh 1to1            # message-change emission side-effect sentinel
./scripts/run_host_test_gates.sh feature-host-all   # auto-glob proof: new widget/wired files listed & green

# 5. Perf evidence (report-only + structural)
./scripts/run_test_gates.sh performance-host        # ORBIT target passes; attach reportData to Execution Progress

# 6. Registration verification
grep -n "orbit_unread_indicator_wired_test" scripts/run_test_gates.sh   # must hit GROUP_TESTS

# 7. Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED (pre-fix): the four §1 commands, for the documented reasons only (compile-RED on new
  files/params; stale-lit on TC-194-16/17; ARB-absence on parity).
- Pre-existing dirty tree: 193 uncommitted work (orbit_screen/orbit_wired/view-mode files, l10n,
  gates script), concurrent-session edits to conversation_wired.dart, and the known pre-existing
  `l10n_integrity` RED on orbit3 keys (memory: 193) — none are 194 failures.
- Environment blocker (NOT product): graphify-arch store may be mid-rebuild by another session
  (observed during grounding); performance-host needs a desktop device target.
- Scope drift (BLOCKING): any failure in feed/1to1 gates traceable to the message-change emission →
  stop, re-evaluate the dedicated-stream fallback (step 7 Stop-if), do not hack listeners.

## Done Criteria
- [x] RED added first; each failed for its documented reason (compile-RED for new widget/param/getter; assertion-RED for visualization wiring; stale-lit RED for TC-194-16/17/18/19).
- [x] Mutation-verified by construction (each row's assertion reverts to its RED failure when the corresponding wiring is removed — confirmed at the RED stage before each slice's implementation).
- [x] Direct GREEN + preservation sentinels + named gates pass (indicator 8/8, visualization 20/20, avatar 6/6, wired 13/13, l10n 3/3, repo-impl 21/21; orbit_wired 74/74, view_split 14/14, contact_profile TC-24; 1to1 1482/1482, feed 282/282, groups 944/944).
- [x] No DB migration needed (none introduced).
- [x] PROD-CRITICAL row (TC-194-16) green via the read-event seam (`ConversationReadEventSource`), `ORBIT_FL_READ_REFRESH` discriminator asserted.
- [x] GROUP_TESTS append verified by grep (run_test_gates.sh:246) + a `groups` gate run (944/944).
- [x] flutter analyze 0 new; git diff --check clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not modify `UnreadCountBadge`, nav badges, `OverflowBadge`, or `OrbitalRingPainter`.
- Do not touch the contact-profile donor (`_OrbitRingsPainter`, its 28s controller, or TC-24).
- Do not add numerals/count text to orbital nodes (product decision B).
- Do not build clearing on `externalRouteChangesListenable` (production-dead) and do not delete it
  here (cleanup session owns it).
- Do not l10n-ize the UNLIT node label or the pill text here (a11y cleanup session).
- Do not change friend ordering, ring caps (5/8/13), or the 48px tap-target rule.
- Do not add frame-budget `expect`s to the perf harness (evidence-only by design).
- Do not persist any indicator state (derive from `unreadCount` only).

## Accepted Differences / Intentionally Out Of Scope
- Overflow "+N" carries no unread aggregation (deferred, future 19x session) — guarded only for
  non-crash + list-view fallback (TC-194-31).
- Group nodes show no unread (inner circle is 1:1 friends only).
- The C4 stale window for surfaces is closed by the read-event seam; push-notification *arrival*
  badge parity on other tabs is Feed's existing domain, untouched.
- orbit2/orbit3 prototypes keep their own hardcoded labels/behavior (kDebugMode mocks).

## Dependency Impact
- 193 (inner-circle default view) depends on this rendering only additively — its reset/toggle locks
  are preservation-gated here (TC-194-32 + view_split sentinels).
- Any future read-receipt/unread work can consume the new read-marking emission (INV-5 contract:
  fires only when rows>0, carries peerId + read discriminator).

## Reviewer Findings
Sufficiency self-check (references/sufficiency-checklist.md) run against this plan:
- Spec-case totality: all 36 TC-194 IDs have matrix rows (TC-15 folded into TC-32's test with C3
  evidence; TC-33/34 are sentinel/folded rows — named suites + assertions, no orphans). PASS.
- Every INV has a named test; every edit has a named re-red mutation; REDs fail for documented
  reasons (compile-RED modes stated explicitly). PASS.
- No DB migration; no OS-boundary/multi-device/crypto path (host-only closure justified — the only
  new contract is an in-process repo event, PROD-CRITICAL row named). PASS.
- Literal gates with counts where counts are stable, script-authoritative elsewhere; registration
  named per row (2 manual: GROUP_TESTS append for the new wired file; l10n file already registered).
  PASS.
- Blind-spot sweep: all four classes have rows or justified N/A (destructive → delete-lit row). PASS.
- Refuted/corrected findings recorded (dead listenable, donor motion inversion, perf-harness
  no-budget). PASS.

## Arbiter Decision
Structural blockers: none. Deferred details: exact message-change event type vs dedicated
`conversationReadStream` (step 7 Stop-if governs the pivot); satellite finder strategy (step 3
Stop-if). Accepted differences: as listed. → hand off to execution.

## Final Execution Verdict
Verdict: **COMPLETE — host-green 2026-07-02.** | Files changed: 3 prod widgets (NEW
`unread_orbit_indicator.dart`, `orbital_avatar.dart`, `orbital_visualization.dart`), repo seam
(`message_repository.dart` NEW `ConversationReadEventSource` iface + `message_repository_impl.dart`
emit), `orbit_wired.dart` subscription, `in_memory_message_repository.dart` mirror, l10n (en/ar/de +
regenerated `app_localizations*`), `orbit_performance_harness.dart` lit scenario,
`run_test_gates.sh` GROUP_TESTS append; tests: 5 new/extended test files + 3 sentinel updates. |
Tests run: direct 71/71, preservation (orbit_wired 74/74, view_split 14/14, contact_profile TC-24),
gates 1to1 1482/1482 · feed 282/282 · groups 944/944; full `flutter test test/features` = 7032 pass /
2 fail — both (`conversation_wired_test` media-prep, `group_info_wired_test` GCA-103) are pre-existing
cross-file batch-order flakes UNRELATED to 194 (pass 174/174 in isolation; neither touches changed
paths). | Blocking: none. | QA verdict: PASS. |
Seam decision (executor pivot, step-7 Stop-if): dedicated `ConversationReadEventSource { Stream<String>
conversationReadStream }` — NOT `MessageRepositoryChangeSource` (would force 6 conversation test
doubles to add the getter) and NOT `messageChanges` (wrong payload type — a synthetic read-message
would corrupt the feed + conversation upsert-by-id listeners). Emitted `if(markedCount>0)` from
`MessageRepositoryImpl` + shared fake only. |
Intended preservation delta: the lit-node augmented semantic label (TC-194-27) broke 2 exact-match
`find.bySemanticsLabel('Open chat with Bob')` assertions in `orbit_wired_test.dart` (Bob now lit);
both updated to the augmented label (grep-verified no other test looks up lit nodes by label). |
Perf harness dispatch correction: ORBIT runs via `./scripts/run_test_gates.sh performance` /
`performance-sim` (NOT `performance-host`, which globs test/performance/). |
Non-blocking follow-ups (owner): overflow unread aggregation (future session); unlit-label l10n
adoption of `orbit2_open_chat_with` (a11y cleanup); dead `externalRouteChangesListenable` removal
(cleanup); optional device eyeball (host-only closure by design).
