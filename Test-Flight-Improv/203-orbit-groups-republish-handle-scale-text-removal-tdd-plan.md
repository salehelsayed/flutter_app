# 203 - Orbit small-fix triad: group ring republish (B2) + edit-handle scaling (B3) + Close-Friends/Inner-Circle text removal (B5)  (Bug ×2 + Modification)

Status: IMPLEMENTED + CLOSED 2026-07-04 (d1687eca / 8f6b8502 / 50e07f7d / eeaff05f — see Final Execution Verdict)
Spec: free-text intent (no formal spec) — the three remaining fixes from the 2026-07-03 seven-bug Orbit debug (B1/B4/B6/B7 own plans 200/201/202). Root causes adversarially verified in workflow `wf_0396f589-131` (B2 confirmed, B3 confirmed, B5 confirmed); plan grounding `wf_c0efa6c4-5fa` (3 agents, HEAD 959b0543, anchors re-verified with 3 corrections). Dossier: memory `project_orbit_seven_bug_debug_2026_07_03.md`.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-03 | Evidence Collector (wf_0396f589 B2/B3/B5 + verify) | orbit_wired.dart, inner_circle_items.dart, orbit_edit_handle.dart, inner_circle_interactive_surface.dart, orbital_visualization.dart, friends_list_header.dart, ARBs | B2 = publish asymmetry (197 IS in-tree); B3 = zero scale input; B5 = 2 keys / 3 sites, pure presentation | ground test mechanics |
| 2026-07-04 | Evidence Collector (wf_c0efa6c4 G-B2/B3/B5) | all target suites, fakes, run_test_gates.sh, l10n.yaml, generated l10n | 3 anchor corrections (publish-all body :380-383; header OUTSIDE searchActive guard; measure signature keys on items.LENGTH); Completer-gate shape; seeding shape `'1.4|1.0|1.0|9|1.0'`; complete B5 test-edit list | write plan |
| 2026-07-04 | Planner (this session) | grounding dossiers | B2-R1 in view_split, R2-R5 in wired; B3 raw-scale param + shared effectiveDiscSize; B5 full 3-site removal with recorded ring-view-only fork | reviewer pass |
| 2026-07-04 | Reviewer (sufficiency) | | (pending) | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-04 | contract extraction (git status --short) | — | HEAD == 959b0543 (exact grounding commit); pre-existing dirty: graphify-arch/* meta, info.plist, 00-INDEX, spec-doc SKILL, untracked plan docs 199-203; 6 live sessions on the shared tree → per-slice narrow staging | scope confirmed | baselines |
| 2026-07-04 | fresh gate baselines (step-1 requirement) | — | `./scripts/run_test_gates.sh groups` → **1013 pass**; orbit cluster `flutter test test/features/orbit/ test/l10n/orbit_strings_parity_test.dart` → **437 pass**; `./scripts/run_test_gates.sh feed` → **285 pass** | recorded | B2 RED |
| 2026-07-04 | B2 RED | orbit_view_split_test (+_GatedGroupRepository, TC-203-01 gated.saveGroup direct), orbit_wired_test (TC-203-02..05 + GroupAvatar/GroupRow imports) | all 5 red for documented reasons (GroupAvatar 0-where-1 / 1-where-0 / stale label / stale initials). DEVIATION: group ring node semantics MERGE the initials fallback (`'Open group Alpha Group\nAG'`) — exact `bySemanticsLabel` can never match; TC-203-04 asserts `tester.getSemantics(GroupAvatar).label` `startsWith(...)` (house 198-F12 prefix idiom), contract identical (arb `=1` branch pinned) | RED for expected reason | flip |
| 2026-07-04 | B2 implementation + GREEN | orbit_wired.dart (six flips :652/:676/:680/:699/:703/:850) | view_split 17 pass; wired 78 pass; orbit cluster **442** pass (sentinels :1710/:2003-2013/:4581/197-rows green) | committed **d1687eca** | B3 |
| 2026-07-04 | B3 RED | orbit_edit_handle_test (TC-203-07/08 + handle() scale passthrough), sculpt wired (TC-203-09..11) | widget tier compile-red (`No named parameter 'scale'` — documented new-API red); wired 30≠42, 30≠42, bubble 21≠27 | RED for expected reason | implement |
| 2026-07-04 | B3 implementation + GREEN | orbit_edit_handle.dart (scale param + effectiveDiscSize + ×factor glow/icon + doc comments), inner_circle_interactive_surface.dart (host `scale:` + bubble clamp), 198 plan pins :118/:223 | handle suite 6 pass; sculpt suite 52 pass; orbit cluster **447** pass | committed **8f6b8502** | B5 |
| 2026-07-04 | B5 RED + churn (row 18) | parity (TC-203-13), viz test (TC-203-14 + overflow-only trim), loading (TC-203-15/16 + :525 line), wired (TC-203-17), view_split (TC-203-18 re-anchor + import/assert churn), qr (surface rename + toggle anchor), feed_focus (comment) | TC-203-13..17 all red. NOTE: churn edits landed BEFORE the widget deletion, so TC-203-18's documented compile-red never manifested (equivalent protection — deletion without the churn would compile-break) | RED for expected reason | strip |
| 2026-07-04 | B5 implementation + GREEN | viz title block, surface caption, orbit_screen mount+import, friends_list_header.dart DELETED, 3 ARBs atomic, gen-l10n (4 generated files) | orbit+parity+feed_focus **463** pass; `grep -rn 'orbit_close_friends\|orbit_inner_circle_title' lib/` = 0 hits; analyze: 0 new (2 pre-existing errors in untouched integration_test/*). CHURN BEYOND PLAN: TC-198F-04's band-crossing sweep is absolute-viewport-dependent (plan's "nothing pins absolute canvas y" missed it) — removed ~41px title lifts the top-anchored canvas, saturated cv tip bottoms at ~366 < 380 band; re-anchored to a 340px band + bounded until-hidden sweep, invariant unchanged | committed **50e07f7d** | gates |
| 2026-07-04 | QA mutation verification | temp reverts, each restored | B2: :850 revert → TC-203-02..05 all red; whole-funnel `_loadGroupData` revert → TC-203-01 red. FINDING (narrows the reviewer note): a **:676-alone** revert is GREEN-masked — the archived leg's publish-all (:699) flushes `_activeGroups` set by the active leg; the enforced INV-203-1 lock is "the funnel publishes-all by exit" (whole-funnel revert), not per-site. B3: host-wiring drop → TC-203-09 red (widget tier stays green — wiring lock proven); bubble discSize/2 → TC-203-11 red; clamp removal → TC-203-07 red (0.6 row); glow/icon unscaled → TC-203-08 red; settle-only → TC-203-10 red. TC-203-10 STRENGTHENED first (eeaff05f): original tester.drag shape completed the gesture pre-pump so settle-only was indistinguishable — now asserts mid-gesture (F15 two-step slop+update). B5: ARB re-add → TC-203-13 red; title/caption/header literal restores → TC-203-14/15/16/17 red | 12/12 mutations re-red | named gates |
| 2026-07-04 | named gates (final) | — | groups gate **1022** pass exit 0 (baseline 1013 + 9 new pinned rows); orbit cluster+parity+feed_focus 463; feed gate **285** pass exit 0; feature-host-all **exit 0, all 642 targets PASS** (its pinned scope excludes test/l10n — every 203-touched suite passed inside the sweep); `flutter test test/l10n/l10n_integrity_test.dart` = **+1 −1: 3-locale parity leg GREEN, literal-scan leg red PRE-EXISTING** (orbit3 literals, git-blamed to 17a32bef/c03af765 of 2026-06-25 — red on the grounding HEAD, in NO gate incl. feature-host-all, out of 203 scope); `git diff --check` clean; both graphs refreshed, `graphify explain "FriendsListHeader"` (arch) → "No node matching" | all gates green | verdict |

## Source Of Truth
- Spec / intent: inline below
- Gate definitions: scripts/run_test_gates.sh
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh (not needed — no integration_test/ additions)
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready (three independently committable slices)

## Exact Problem Statement
**B2 (bug):** a joined group's avatar never appears on the Orbit inner-circle rings (and a seated group's unread badge, name, avatar, and removal never refresh) unless an unrelated friend/identity refresh happens to publish afterwards. 197 groups-on-rings IS fully in-tree; the group data paths simply never republish the ring projection.
**B3 (bug):** in Orbit edit mode, dragging the "Avatar size" handle grows the avatars but the five edit-handle discs stay fixed 30px — visually inconsistent; the user asked for all setting circles to scale with the avatar-size knob.
**B5 (modification):** remove the texts "Close Friends" and "Your Inner Circle" from the Orbit screen — all three render sites (ring-view title + caption, all-chats header), the two ARB keys (3 locales atomically), and the now-empty `FriendsListHeader` widget.

What must improve: group ring nodes seat/refresh/deposit deterministically on group events alone (B2); handle discs+glow+icon scale live with `avatarScale`, clamped [24,42], hit target fixed 44 (B3); zero occurrences of either string on any Orbit view, dead keys removed from all ARBs, l10n regenerated (B5).
What must stay unchanged (→ preserved-green sentinels): search-typing does NOT rebuild the header (`orbit_wired_test.dart:1710` — the other list-only publish sites are deliberately untouched); repo-call counts per group event (`:2003-2013` — projections are pure, `orbit_wired.dart:295-370`); 197 ring rows (`orbit_view_split_test.dart:300-345`); all handle anchor/geometry locks (anchors use `hitTarget/2` only, `inner_circle_interactive_surface.dart:751-754`; oracle `orbit_sculpt_summon_wired_test.dart:180`); ≥44pt handle targets; TC-198F-25 anchor-tap, TC-198F-13 pulse, TC-198-20R at defaults; near-miss l10n keys (`orbit_inner_circle_badge` @ friend_row.dart:102, `orbit_inner_circle_empty_hint` @ surface :561, `orbit_view_toggle_*`); the `orbit_wired_test.dart:4615` all-chats `OrbitalVisualization findsNothing` lock; 196 chrome vertical clearance (re-anchored, not weakened).

## Root Cause (verify → refute confirmed — wf_0396f589; anchors re-verified on HEAD 959b0543 by wf_c0efa6c4)
**B2:** `_loadGroupData` publishes list-only at `orbit_wired.dart:652/676/680/699/703` (spans :646-711) and `_refreshOrbitGroup` at `:850` (spans :809-859), while friend/identity paths call `_publishAllProjections()` (`:577/:604/:608/:632/:636/:798`, initState `:411`; **body at `:380-383`** = header + list — grounding correction). The rings' ONLY feed is `OrbitHeaderProjection.innerItems` (`mergeInnerCircleItems(friends: _activeFriends, groups: _activeGroups)` at `:303-305`; `_headerProjectionNotifier.value` written ONLY at `:373`; consumed `orbit_screen.dart:544→:551-554`). Funnel is airtight: `_activeGroups`/`_archivedGroups` are mutated ONLY at `:668/:697` and `:848/:849`; every group entry point reaches one of the two functions (invite accept :1295, groupJoinedStream :1041, groupMessageStream :1648, dirty replay :539, route return :2126/:2128, conversation pop :2534, group actions :2369/:2386/:2424/:2455/:2480, init :436, error retry :857). The 197 tests pass by fake-ordering luck (groups seeded pre-pump; a later friend-side publish-all flushes them).
**B3:** `OrbitEditHandle` has zero scale input — `discSize 30` (:49), `hitTarget 44` (:46), icon `Size(16,16)` (:184), armed glow 20/4 (:167-171), unarmed `10+12*wave / 1+4*wave` (:175-176), tip-pill `top: hitTarget+4` (:200); host ctor site `inner_circle_interactive_surface.dart:761-770` (inside the `:686-688` loop — ONE site serves collapsed and expanded modes) passes nothing; bubble clamp hard-codes `OrbitEditHandle.discSize/2` at `:794` (formula :793-794). Positioned centering uses `hitTarget/2` ONLY (`:751-754` — keeping hitTarget 44 leaves ALL position math and anchor locks untouched). Icon painter already normalizes by `size.width/24` (:242-248) — no painter change.
**B5:** `orbit_inner_circle_title` rendered ONLY at `orbital_visualization.dart:234-245`; `orbit_close_friends` at `inner_circle_interactive_surface.dart:547-556` (caption) + `friends_list_header.dart:21` (all-chats title, mounted at `orbit_screen.dart:593`, import :26 — **UNCONDITIONAL: the `if (!projection.searchActive)` at :594 wraps only the SizedBox+FriendsFilterToggle :595-602**, grounding correction). ARB lines: en :185/:1252, ar :185/:1203, de :185/:1203; no @-metadata. Empty-hint independent sibling (:557-570). Measure signature has no caption/title term; the 198 handle layer re-measures the real canvasKey origin post-frame (`:494-500`, `:241-260`) so the ~78px column shrink self-corrects (~2px net canvas center shift; nothing pins absolute canvas y).

Refuted / do-NOT-re-introduce:
- B2: "197 was never implemented / a dropped wire" — REFUTED (in-tree since d34f6499). "The view toggle or tab re-entry flushes the stale header" — REFUTED (setState-only). Do NOT flip the OTHER list-only publish sites (:718/:742 invites, :915 intros, :1086-1223, :1487, :1857-1890 search/tab) — they are deliberately list-only; flipping breaks the `:1710` typing lock.
- B3: "anchor math depends on disc size" — REFUTED (radius/hitTarget only). "Drag can hit arbitrary scales deterministically" — REFUTED (~18px tester slop; only clamp-saturating drags are deterministic — mid-range scales come from store seeding).
- B5: "caption/title removal breaks handle anchoring or chrome clearance" — REFUTED (post-frame re-measure; the 196 clearance mechanism is the sliver Padding 56 at orbit_screen.dart:589, not the header). "Header hides during search" — REFUTED (unconditional; corrected above).
- Grounding precision fix (do not cite the old form): a same-count header republish mid-sculpt does NOT re-measure — `_measureSignature` keys on `widget.items.length` (:226-227), not list identity; a COUNT change re-seats handles same-frame by design (TC-198F-02).

## Real Scope
In scope:
1. **B2:** replace exactly six `_publishListProjection()` calls with `_publishAllProjections()` — `orbit_wired.dart:652, :676, :680, :699, :703` (_loadGroupData) and `:850` (_refreshOrbitGroup). Nothing else. **Mutation-lock scope (reviewer-corrected):** the behavior-bearing flips are `:676` (locked by TC-203-01) and `:850` (locked by TC-203-02..05); `:652` (null-repo early return), `:699/:703` (archived leg — `_buildHeaderProjection` :295-307 reads only `_activeFriends`+`_activeGroups`, so this leg is header-inert), and `:680`'s error path are **uniformity-only flips** (behaviorally inert by construction, no test CAN pin their reverts — explicit INV-MUTATION-VERIFIED exemption).
2. **B3:** `OrbitEditHandle` gains `final double scale` (default 1.0, RAW avatarScale) + `static double effectiveDiscSize(double scale) => (discSize * scale).clamp(24.0, 42.0)` — the ONE shared helper; disc Container uses it (:156-157), icon `Size` × factor (factor = effective/30), glow blur/spread × factor (armed and unarmed constants); `hitTarget` STAYS 44; tip-pill offset STAYS `hitTarget+4`. Host passes `scale: _geometry.avatarScale` at `:761-770`; bubble clamp `:793-794` switches `discSize/2` → `OrbitEditHandle.effectiveDiscSize(_geometry.avatarScale)/2`. Live application (flows through the drag's own setState `:375` → build; no lag). Amend the "30px" pins in `Test-Flight-Improv/198-orbit-sculpt-handles-fidelity-tdd-plan.md:118/:223` + in-source doc comments (`orbit_edit_handle.dart:6-7/:48-49`).
3. **B5 (full 3-site scope):** delete title block `orbital_visualization.dart:234-245`; delete caption block `inner_circle_interactive_surface.dart:547-556`; remove `FriendsListHeader` mount (`orbit_screen.dart:593`) + import (:26) + delete `lib/features/orbit/presentation/widgets/friends_list_header.dart`; remove BOTH keys from `app_en.arb:185/:1252`, `app_ar.arb:185/:1203`, `app_de.arb:185/:1203` (3-locale atomic; mind trailing commas — `orbit_inner_circle_badge` sits IMMEDIATELY above the title key and must survive); `flutter gen-l10n` (rewrites the 4 checked-in `lib/l10n/app_localizations*.dart`; getters at :775-779/:3689-3693 + locale overrides vanish). **Order: strip the 3 lib call sites FIRST, then ARBs, then gen-l10n** — regenerating first compile-breaks every suite. Test edits per the churn list below.
Out of scope (owners named): tap-away ~300ms disambiguation delay (spec-pinned gestures — needs its own product-reviewed slice; recorded in plan 202 Accepted Differences); sculpt decode quantization (follow-up after plan 200's provider helper; recorded in 202); orbit refresh coalescer (plan 202 — B2's publish-all rides it when 202 lands); find-pill/label keys (plan 201); avatar aspect (plan 200); RTL find geometry (follow-up).

## Files To Inspect Next
Production: lib/features/orbit/presentation/screens/orbit_wired.dart (B2); lib/features/orbit/presentation/widgets/orbit_edit_handle.dart + inner_circle_interactive_surface.dart (B3, B5 caption); lib/features/orbit/presentation/widgets/orbital_visualization.dart + friends_list_header.dart + lib/features/orbit/presentation/screens/orbit_screen.dart (B5); lib/l10n/app_{en,ar,de}.arb + generated app_localizations*.dart (B5).
Direct tests: test/features/orbit/presentation/screens/orbit_view_split_test.dart, orbit_wired_test.dart, orbit_sculpt_summon_wired_test.dart, orbit_screen_loading_test.dart; test/features/orbit/presentation/widgets/orbit_edit_handle_test.dart, orbital_visualization_test.dart; test/l10n/orbit_strings_parity_test.dart; test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart.
Dependency-only context: lib/features/orbit/application/{inner_circle_items.dart, load_orbit_groups_use_case.dart, orbit_geometry_prefs_use_cases.dart}; lib/features/orbit/domain/models/orbit_geometry_prefs.dart (reviewer-corrected path); test/shared/fakes/in_memory_group_repository.dart (archiveGroup @override :137, updateGroup :120); test/core/secure_storage/fake_secure_key_store.dart; test/l10n/l10n_integrity_test.dart; test/features/feed/presentation/screens/feed_focus_test.dart (comment-only).

## Existing Tests Covering This Area
- orbit_view_split_test.dart (**GROUP_TESTS :241**): 197 ring rows :300-323 (seeded group seats — luck-ordering) + :325-345 (archived excluded); harness `buildOrbitWired(groupRepository: InMemoryGroupRepository?)` :182/:190, seedGroup :247-260, pumpOrbitFrames :236-240, setLargeTestSurface :148-155, switchToAllChats :242-245; friends_list_header import :25 (B5 compile-break), FriendsFilterToggle import :24.
- orbit_wired_test.dart (**GROUP_TESTS :227**): the ONLY group-message stream fixture — `groupMessageStreamController` (broadcast; declared :120, created :165, closed :200) auto-wired via `_FakeGroupMessageListener` (:299-301, class :5121-5129); `_FakeGroupInviteListener` :4654; typing header lock :1710; friend-side ring re-rank template :4515-4590 (headerBuilds GREW :4581, unread semantics :4584, ensureSemantics :4518); spy repo-call counts :2003-2013; 'Close Friends' anchor :604 (identity test :591-605; OrbitalVisualization import :49); all-chats findsNothing lock :4615.
- orbit_unread_indicator_wired_test.dart (**GROUP_TESTS :246**): 194 suite; NO group listener seam (grounding-verified) — group rows belong in orbit_wired_test.
- orbit_sculpt_summon_wired_test.dart (**GROUP_TESTS :254**): host() :82-111 (secureKeyStore param), settle() 16×90ms :113-117, longPressBg :128-133, expandBadge :227-230, handleF :152-153, handleAnyF skipOffstage:false :158-159; store-seeding precedent :415-416 (TC-198-36); disc-key read :927-928; TC-198-22 saturating av drag :297-310; TC-198-20R :954-985; TC-198F-15 :987-1012; anchor oracle :180; slop comment :647; TC-198F-26 :1407, TC-198F-27 :1447, TC-198F-25 :1521-1531.
- orbit_edit_handle_test.dart (auto-glob): wrap() :21-37, handle() builder :39-47, discF :49-50, discDeco :52-53; ≥44 target :66-67; disc getSize :70 closeTo(30,0.5) :71-72; armed deco reads :108-113; unarmed first-frame blur read :119-120.
- orbit_screen_loading_test.dart (auto-glob): buildOrbitScreen default allChats :108; 'Close Friends' color-set :338-347; daylight caption test :358-393 (OrbitSearchTrigger findsNothing :392); chrome-visible :525.
- orbital_visualization_test.dart (auto-glob): 'renders YOUR INNER CIRCLE' :130-136; daylight heading/overflow :201-222; group ring rows TC-197-03/05 :556-629.
- test/l10n/orbit_strings_parity_test.dart (**GROUP_TESTS :255** — test/l10n is OUTSIDE feature-host-all): loadArb helper :48-52, per-locale containsKey loop :55-71, generated-API block :73-109.
- test/l10n/l10n_integrity_test.dart (host-all sweep ONLY — **not in any curated gate**): 3-locale key parity :16-25 (forces atomic removal), literal scan :45-64.

Missing coverage gaps: no test drives a group ring seat without friend-side luck; no ring-removal/-unread/-metadata group assertions; no handle test at scale ≠ 1.0; no removal locks for the two strings; no FriendsListHeader widget test exists (nothing to delete test-side).
Already in curated family arrays?: as annotated above; loading/viz/handle files auto-glob only; inner_circle_items_test.dart glob-only (no edits needed).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST; bounded pumps EVERYWHERE — unread rotation + edit pulse forbid pumpAndSettle)
**Slice B2** (rows 1-5; fixtures: keep `unread: 0` unless unread is the assert target — the 194 suffix changes semantics labels):
1. `orbit_view_split_test.dart` :: `'TC-203-01 group load completing AFTER friend publishes still seats the ring node'`
   - Shape: in-file `_GatedGroupRepository extends InMemoryGroupRepository` overriding `getActiveGroups()` to await an optional `Completer` (house in-file-subclass style; the harness param is typed `InMemoryGroupRepository?` :182/:190; gate target = getActiveGroups — the FIRST await in _loadGroupData, parks the whole function; complete it in addTearDown as leak-safety). Seed by calling **`gated.saveGroup(...)` DIRECTLY** (reviewer-caught: the shared seedGroup helper is hard-wired to the file-level `groupRepo` instance, :247-248 — using it would seed the WRONG repo and GREEN would be unreachable); pump `buildOrbitWired(groupRepository: gated)`; pumpOrbitFrames(4) → identity+friend publishes settle while group load is parked; PRECONDITION `find.byType(GroupAvatar)` findsNothing; `gate.complete()`; pumpOrbitFrames(4); assert `find.byType(GroupAvatar)` findsOneWidget + `find.byType(GroupRow)` findsNothing (default view is inner-circle, orbit_wired.dart:404-406).
   - RED on HEAD: after the gate releases, `_loadGroupData` sets `_activeGroups` (:668) then list-publishes only (:676) — the header notifier (:373) never rewrites, innerItems stays groupless, no GroupAvatar mounts.
   - Mutation that re-reds: revert `:676` (or `:680`) to `_publishListProjection()` → red.
2. `orbit_wired_test.dart` ('193 orbit view split (wired)' group :4514) :: `'TC-203-02 a group materialized post-startup seats on the rings with zero friend events'`
   - Shape: default harness (gmListener auto-wired); pump; pumpOrbitFrames(4); assert GroupAvatar findsNothing; `await groupRepo.saveGroup(GroupModel(...))`; `groupMessageStreamController.add(GroupMessage(groupId: 'g-1', isIncoming: true, ...))` (emission idiom :1983-1995; do NOT save to groupMsgRepo — keeps unread 0, no rotation); pumpOrbitFrames(4); assert GroupAvatar findsOneWidget, GroupRow findsNothing.
   - RED on HEAD: `_refreshOrbitGroup` adds to `_activeGroups` (:848) then `:850` list-publishes only; no friend event ever flushes the header. Mutation: revert `:850` → red.
3. `orbit_wired_test.dart` :: `'TC-203-03 archiving a seated group removes its ring node without friend events'`
   - Shape: seed group pre-pump (seats via luck on HEAD, deterministic post-fix); pumpOrbitFrames; assert GroupAvatar findsOneWidget; `await groupRepo.archiveGroup('g-1')` (in_memory_group_repository.dart:138-146); emit a GroupMessage for g-1 → `_refreshOrbitGroup` isArchived branch (orbit_wired.dart:839-840); pumpOrbitFrames; assert GroupAvatar **findsNothing**. (Repo-mutation+stream is the clean driver — `_onArchiveGroup` :2362-2377 needs the all-chats row UI, off-surface here.)
   - RED on HEAD: the stale header still carries the archived group — ring node LINGERS (findsOneWidget where findsNothing expected). Mutation: revert `:850` → red. Note: the precondition itself passes by the same luck-ordering; if fake ordering ever shifts, the precondition fails first — still red, acceptable.
4. `orbit_wired_test.dart` :: `'TC-203-04 an incoming group message lights the group ring node (unread badge + semantics)'`
   - Shape: seed group ('Alpha Group') pre-pump; `final handle = tester.ensureSemantics()` (idiom :4518, dispose at end); pumpOrbitFrames; SAVE the message to groupMsgRepo THEN emit (save+emit :1994-1995 so `getGroupThreadSummary` returns unread 1); **bounded** pumpOrbitFrames (lit node hosts the ~9s rotation); assert `find.bySemanticsLabel('Open group Alpha Group, 1 unread message')` findsOneWidget (arb en:266 `=1` branch; wired at orbital_visualization.dart:303-308; friend-side mirror :4584). Structural fallback: UnreadOrbitIndicator descendant of the group node's OrbitalAvatar (mounts at orbital_avatar.dart:139-146).
   - RED on HEAD: header innerItems keeps the unreadCount=0 snapshot — label stays 'Open group Alpha Group' (arb :258). Mutation: revert `:850` → red.
5. `orbit_wired_test.dart` :: `'TC-203-05 a group rename reaches the ring node after a group refresh'`
   - Shape: seed 'Alpha Group'; pump; `await groupRepo.updateGroup(model.copyWith(name: 'Renamed Group', lastMetadataEventAt: ...))` (:121-123); emit GroupMessage → refresh; pumpOrbitFrames; assert semantics label matches 'Open group Renamed Group' (or initials `find.text('RG')`, idiom view_split :343); optional: `tester.widget<GroupAvatar>().cacheBustKey` reflects the new lastMetadataEventAt (viz :319).
   - RED on HEAD: renamed model reaches `_activeGroups` but the header snapshot keeps the old OrbitGroup forever. Mutation: revert `:850` → red.
6. **B2 preservation sentinels** (no edits — grounding verified NONE of these churn): `:1710` typing header-count (search sites stay list-only); `:2003-2013` repo-call counts (publish-all does ZERO repo calls — projections pure :295-370); `:4581` friend header-builds; 197 rows :300-345; inner_circle_items_test; mid-sculpt guards TC-198F-26 (:1407) + TC-198F-27 (:1447) + same-frame re-seat TC-198F-02 (count-change re-measure is designed behavior).

**Slice B3** (rows 7-11):
7. `orbit_edit_handle_test.dart` :: `'TC-203-07 disc scales with avatarScale: 42 at 1.4, floor 24 at 0.6, hit target stays 44'`
   - Shape: extend the shared handle() builder (:39-47) with `double scale = 1.0` → new ctor param; `tester.getSize(discF(knob))` closeTo(42, 0.5) at scale 1.4; closeTo(24, 0.5) at 0.6 (30×0.6=18 clamps to floor — **the ONLY observable clamp end**: 30×1.4=42 == ceiling exactly, so the ceiling never binds; the 'remove clamp' mutation MUST be asserted against the 0.6 row); gesture key ≥44 both axes at both scales.
   - RED on HEAD: compile-red — no `scale` param (house new-API-red convention, fidelity plan precedent). Mutations: remove `scale` wiring → compile/assert red; remove the clamp → the 0.6 row red (18 ≠ 24).
8. `orbit_edit_handle_test.dart` :: `'TC-203-08 glow and icon scale by the disc factor'`
   - Shape: `armed: true, scale: 1.4` (armed freezes the pulse :97-101 → STATIC blur/spread): `discDeco(...).boxShadow!.first.blurRadius` closeTo(20×1.4) + spread closeTo(4×1.4); icon `tester.widget<CustomPaint>(find.byKey(ValueKey('orbit-handle-icon-avatarScale'))).size == Size(22.4, 22.4)` (painter normalizes by size/24 :242 — no painter change); unarmed leg reads blur on the FIRST un-advanced frame (wave=0 → 10×1.4, precedent :119-120).
   - RED on HEAD: compile-red on the param, then assert-red until glow/icon multiply by the shared factor. Mutation: scale disc only (not glow/icon) → red. NOTE (202 interplay): these glow asserts target the CURRENT blur mechanism — if plan 202's opacity-halo pulse lands first, re-map onto the static halo's dimensions (contract identical: ×factor).
9. `orbit_sculpt_summon_wired_test.dart` :: `'TC-203-09 seeded avatarScale 1.4 renders 42px discs — collapsed av AND expanded og handles'`
   - Shape: **seed BEFORE pump** (silent no-op after — `_restoreGeometry` runs once from initState :124-128/:157-166): `final store = FakeSecureKeyStore(); await store.write(OrbitGeometryPrefs.storageKey, '1.4|1.0|1.0|9|1.0');` → `host(_friends(8), store: store)`; settle; longPressBg; assert av disc getSize closeTo(42, 0.5). Second leg: `_friends(20)` + expandBadge + longPressBg → assert the orbitGap disc == 42 (one ctor site serves both modes, but the test must WITNESS the expanded-only path too; _collapsedKnobs :120, _visibleKnobs :202-203).
   - RED on HEAD: no compile dependency at this tier — host passes nothing, disc renders 30 ≠ 42. Mutation: drop `scale:` at the host ctor site (:761-770) → red (the widget-tier rows stay green — this row is the WIRING lock).
10. `orbit_sculpt_summon_wired_test.dart` :: `'TC-203-10 live application: av clamp-drag grows the disc same-pump'`
    - Shape: default host; longPressBg; arm av handle; `tester.drag(handleF(av), const Offset(0, -80))` (saturates the 1.4 clamp regardless of ~18px slop — TC-198-22 precedent :297-310); ONE `tester.pump()`; assert disc getSize == 42 same-pump (scale flows synchronously through the drag setState :375 → build; matches TC-198F-02's no-lag bar) + value-bubble corroboration (precedent :293).
    - RED on HEAD: disc stays 30 after the drag. Mutation: make scaling settle-only (apply on pan-end) → same-pump assert red.
11. `orbit_sculpt_summon_wired_test.dart` :: `'TC-203-11 bubble hugs the SCALED disc at 1.4 (shared effectiveDiscSize lock)'`
    - Shape: seed `'1.4|1.0|1.0|9|1.0'`; longPressBg; arm av; `bubble.bottom` closeTo(`avCenter.dy - 27`, 2.0) — effective half = 42/2 = 21, +6 gap per the `:793-794` formula. Do NOT reuse the old 15-based shape of :965-970 (at 1.4 the old `gap <= 12` form lands exactly ON its boundary — vacuous/flaky).
    - RED on HEAD: bubble.bottom = avCenter.dy − 21 (hard-coded discSize/2 + 6). **This is the mutation lock for the ONE shared helper**: a partial fix that scales the widget but leaves the bubble clamp at `discSize/2` stays red here (bottom = center−21 ≠ center−27).
12. **B3 preservation sentinels + mandatory edits**: existing disc closeTo(30) rows run at scale 1.0 — survive byte-identical (only the `:69` comment amends to '30px at default scale'); handle() builder gains the `scale` passthrough (:39-47 — the only mandatory existing-test edit); anchors (:629-673/:846-918, oracle :180), TC-198-20R (:963-970 defaults), TC-198F-15, TC-198F-25, perf-harness key (orbit_performance_harness.dart:504-505) all verified untouched. Doc churn: fidelity plan :118/:223 + orbit_edit_handle.dart :6-7/:48-49 '30px' pins amended.

**Slice B5** (rows 13-19; ordering: lib sites → ARBs → gen-l10n):
13. `test/l10n/orbit_strings_parity_test.dart` :: `'TC-203-13 removed orbit keys are absent from every ARB locale'`
    - Shape: reuse loadArb (:48-52); `const removedOrbitKeys = ['orbit_close_friends', 'orbit_inner_circle_title'];` per-locale `expect(bundle.containsKey(key), isFalse)`. Permanent re-introduction guard (pinned GROUP_TESTS :255).
    - RED on HEAD: both keys present in all 3 ARBs. Mutation: re-add either key to any ARB → red.
14. `orbital_visualization_test.dart:130-136` :: repurpose → `'TC-203-14 renders no inner-circle heading'` — same pump, `find.text('YOUR INNER CIRCLE')` **findsNothing**. RED on HEAD (:237 renders it). Mutation: restore the title block → red. Companion edit :201-222: DELETE heading asserts :215/:218/:220, KEEP '+2' overflow asserts :216/:219/:221, rename to overflow-only.
15. `orbit_screen_loading_test.dart:358-393` :: repurpose → `'TC-203-15 Inner-Circle view: no Close Friends caption, no search affordance (daylight)'` — keep fixture+bounded pump (:378); replace caption-color asserts :384-391 with `find.text('Close Friends')` findsNothing; **KEEP :392** OrbitSearchTrigger findsNothing. RED on HEAD (surface :550). Mutation: restore caption → red.
16. `orbit_screen_loading_test.dart:338-347` :: `'TC-203-16 all-chats view renders no Close Friends header text'` — replace the closeFriendColors block with findsNothing; keep chevrons :349-355 (default allChats harness :108). RED on HEAD (header :21 via orbit_screen :593). Mutation: restore FriendsListHeader mount → red. Also :525 chrome test: DELETE the `find.text('Close Friends')` line (chrome still asserted by :526-528; avoids a new import — loading test has no friends_filter_toggle import).
17. `orbit_wired_test.dart:604` :: `'TC-203-17 wired identity anchor swap + absence lock'` — replace with `find.byType(OrbitalVisualization)` findsOneWidget (import :49 exists) + `find.text('Close Friends')` findsNothing; update the stale comment :601-602. **NEGATIVE OBLIGATION: do NOT touch :4615** (all-chats route-pop `OrbitalVisualization findsNothing` lock). RED on HEAD (the caption matches). Mutation: restore caption → red.
18. `orbit_view_split_test.dart:441-487` :: `'TC-203-18 all-chats FIRST CONTENT clears the top chrome strip (LTR+RTL)'` — re-anchor :469 `getRect(FriendsListHeader)` → `getRect(FriendsFilterToggle)` (import :24 exists); keep both clearance asserts :476-485; update reason strings :479/:484. NOT red on unmodified HEAD — compile-RED once `friends_list_header.dart` is deleted; this is the mandatory churn preserving the 196 vertical-clearance invariant. Remaining view_split edits: DELETE import :25; DELETE :292 + :366 (class ceases to exist; leakage/all-chats proofs remain via :289-291/:364-365/:367); :592 → FriendsFilterToggle findsOneWidget; :501-507 and :585 NO EDIT (anchors survive). qr_entry_migration: DELETE import :23; :567 → FriendsFilterToggle findsOneWidget (import :22 exists), rename 'header'→'surface'. feed_focus_test :289-291 comment-only reword.
19. `'TC-203-19 generated-API removal proof'` — after lib-sites→ARBs→gen-l10n: `flutter analyze` = 0 new (any missed call site of the deleted getters compile-breaks); `GRAPH_OK=1 grep -rn 'orbit_close_friends\|orbit_inner_circle_title' lib/` = zero hits. Static/compile tier; the parity test's generated-API block (:73-109) must NOT gain the removed getters.

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-203-01 | ring seat vs load ordering | wired widget | orbit_view_split_test.dart::TC-203-01 (gated repo) | list-only publish at :676/:680 — header never rewrites | revert :676/:680 to list-publish | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS (:241) |
| TC-203-02 | post-startup group add | wired widget | orbit_wired_test.dart::TC-203-02 | list-only :850 | revert :850 | same | already in GROUP_TESTS (:227) |
| TC-203-03 | ring removal (archive) | wired widget | orbit_wired_test.dart::TC-203-03 | stale header — node lingers | revert :850 | same | already in GROUP_TESTS |
| TC-203-04 | group ring unread live | wired widget | orbit_wired_test.dart::TC-203-04 | header keeps unread=0 snapshot | revert :850 | same | already in GROUP_TESTS |
| TC-203-05 | group ring metadata refresh | wired widget | orbit_wired_test.dart::TC-203-05 | header keeps old name/avatar key | revert :850 | same | already in GROUP_TESTS |
| TC-203-06 | B2 preservation set | wired widget | :1710, :2003-2013, :4581, view_split :300-345, TC-198F-02/26/27 (sentinels) | n/a | any drift → red | same + `flutter test test/features/orbit/` | existing |
| TC-203-07 | disc scale + clamp floor + 44pt | widget | orbit_edit_handle_test.dart::TC-203-07 | compile-red (no scale param); 0.6 row locks the clamp | remove scale wiring / remove clamp (0.6 row) | `flutter test test/features/orbit/presentation/widgets/orbit_edit_handle_test.dart` | AUTO (feature-host-all) |
| TC-203-08 | glow+icon scale | widget | orbit_edit_handle_test.dart::TC-203-08 | compile→assert red (constants unscaled) | scale disc only | same | AUTO |
| TC-203-09 | host wiring at seeded scale (both modes) | wired widget | orbit_sculpt_summon_wired_test.dart::TC-203-09 | host passes nothing — disc 30 ≠ 42 | drop `scale:` at ctor :761-770 | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS (:254) |
| TC-203-10 | live same-pump application | wired widget | sculpt wired::TC-203-10 | disc stays 30 after clamp-drag | settle-only application | same | already in GROUP_TESTS |
| TC-203-11 | shared effectiveDiscSize (bubble) | wired widget | sculpt wired::TC-203-11 | bubble at center−21 (hard-coded half) | keep bubble clamp on discSize/2 | same | already in GROUP_TESTS |
| TC-203-12 | B3 preservation (defaults + anchors + docs churn) | widget/wired | existing handle/anchor/bubble locks at 1.0 (sentinels) | n/a | any drift → red | same + handle file cmd | existing |
| TC-203-13 | ARB absence (re-introduction guard) | l10n/static | orbit_strings_parity_test.dart::TC-203-13 | keys present in all 3 ARBs | re-add a key to any ARB | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS (:255) |
| TC-203-14 | viz heading removed | widget | orbital_visualization_test.dart::TC-203-14 (+ :201-222 trim) | :237 renders the title | restore title block | `flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart` | AUTO |
| TC-203-15 | inner view: no caption + no search affordance | widget (screen) | orbit_screen_loading_test.dart::TC-203-15 | caption at surface :550 | restore caption block | `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` | AUTO |
| TC-203-16 | all-chats: no header text (+ :525 line delete) | widget (screen) | orbit_screen_loading_test.dart::TC-203-16 | header renders unconditionally | restore header mount | same | AUTO |
| TC-203-17 | wired anchor swap + absence (NOT :4615) | wired widget | orbit_wired_test.dart::TC-203-17 | caption matches on inner view | restore caption | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS |
| TC-203-18 | 196 chrome clearance re-anchored + header deletion churn | widget (geometry) | orbit_view_split_test.dart::TC-203-18 (+ import/assert edits, qr :567) | compile-red after friends_list_header.dart deletion | regress first-content below chrome | same (view_split GROUP_TESTS :241; qr :250) | already in GROUP_TESTS |
| TC-203-19 | generated-API removal proof | static/compile | flutter analyze + lib grep + parity :73-109 | getters exist + 3 call sites on HEAD | re-add key/getter reference | `flutter analyze` + grep | compile-level (all suites) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** B2 — the ring set is derived in-memory from repo state; TC-203-01 proves cold-construction under adverse ordering, and the existing rising-edge dirty-replay lock (TC-194-12; replay :539 → `_refreshOrbitGroup` → now publish-all) covers tab re-entry. B3 — TC-203-09 IS the reopen test (scale reconstructs from the persisted store on fresh mount). Covered.
- **Sibling-surface consistency:** B2 — the list surface was already live; the fix makes rings consistent with it; the OTHER list-only publish sites stay deliberately asymmetric AND test-locked (:1710). B3 — corner steppers stay fixed 48 (chrome, outside the reported symptom — Accepted Difference). B5 — near-miss keys survive with live consumers (badge friend_row:102, empty-hint surface:561, toggle strings) locked by existing tests + the parity suite.
- **Destructive-action side-effects:** B5 deletes `friends_list_header.dart` — the churn list asserts what is removed (imports :25/:23, asserts :292/:366/:592/:567) AND what is preserved (toggle mount, chrome clearance TC-203-18, chevrons, empty-hint). B2/B3: N/A (no deletions).
- **Invariant re-verification under new transitions:** B2's archive transition re-verifies the ring-set invariant (TC-203-03 asserts the FULL post-transition state: node gone, list row state per existing locks); B3 re-verifies the ≥44pt and anchor invariants at non-default scale (TC-203-07/09 assert hit target + rely on centering that uses hitTarget only — grounding-verified); B5's header deletion re-verifies the 196 chrome-clearance invariant on the NEW first content (TC-203-18).

## Invariants (locked by tests)
- INV-203-1: every behavior-bearing group-funnel publish flips to publish-all — `:676` pinned by TC-203-01, `:850` by TC-203-02..05; the remaining four sites are uniformity-only flips (header-inert legs, mutation-exempt — reviewer-narrowed wording).
- INV-203-2: search/typing and intro/invite publish paths remain list-only → :1710 sentinel.
- INV-203-3: disc/glow/icon derive from ONE `effectiveDiscSize(scale)`, clamp [24,42], hitTarget 44, live → TC-203-07..11.
- INV-203-4: neither removed string renders on any Orbit view; keys absent from all ARBs → TC-203-13..17.
- INV-203-5: 196 chrome vertical clearance holds for the post-header first content → TC-203-18.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row (TC-203-18's RED is compile-tier by design, documented).

## Step-By-Step Implementation Plan
1. `git status --short` snapshot; re-derive gate baselines (groups; orbit cluster; feed untouched-sentinel) and **RECORD the fresh counts in the Execution Progress table** (reviewer requirement — the approximate 'last recorded + growth' numbers are not a preservation gate until pinned).
2. **B2:** add RED rows 1-5; confirm red for documented reasons. Flip the six sites (`:652/:676/:680/:699/:703/:850`) to `_publishAllProjections()`. Direct green; run B2 sentinels (row 6). Commit slice.
3. **B3:** add RED rows 7-11 (rows 7-8 compile-red first — add the `scale` param + `effectiveDiscSize` helper to compile, then watch asserts red→green as constants are wired). Wire host `scale:` + bubble clamp swap. Amend the two doc pins + in-source comments. Direct green; sentinels (row 12). Commit slice.
4. **B5:** add RED rows 13-17 + the churn edits of row 18. Strip the 3 lib render sites; delete FriendsListHeader mount+import+file; ARB removal (3 locales atomically, mind the badge key adjacency + trailing commas); `flutter gen-l10n`; row 19 checks. Direct green; full l10n gates. Commit slice.
5. Rerun named gates; `graphify update .` && `./graphify-arch/refresh_arch_graph.sh` from repo root (both graphs still index friends_list_header.dart until refreshed).
6. Stop-ifs: any `:1710`/`:2003-2013` red in B2 → a non-funnel site was flipped, revert it; any anchor-lock red in B3 → scale leaked into hitTarget/centering, re-scope; any compile red after gen-l10n → a missed getter call site, fix the site (never re-add the key).

## Risks And Edge Cases
- pumpAndSettle FORBIDDEN in every touched suite (lit-node rotation ~9s; edit pulse 1600ms) — bounded pumpOrbitFrames/settle() only; TC-203-04 creates an unread node deliberately.
- Semantics-label suffix: unread>0 rewrites group labels to the arb `:266` plural form — save-to-repo ONLY when the badge is the assert target (TC-203-04); elsewhere emit-without-save.
- Group message stream drives `_refreshOrbitGroup` only while `_isOrbitActive` — keep B2 tests on the bare orbit host (route pushes divert to `_dirtyGroupIds` :1645 → replay :539).
- Completer gate: gate `getActiveGroups` only; complete in addTearDown (pending-future leak).
- B3 clamp ceiling is DEAD in the legal range (42 == 30×1.4) — the clamp mutation MUST use the 0.6 row.
- Seeding after pumpWidget is a silent no-op (initState-once restore) — always write-then-pump-then-settle.
- Drag slop ~18px — only clamp-saturating drags (Offset(0,-80)); mid-range scales via seeding.
- B5 ARB adjacency: `orbit_inner_circle_badge` (en:1251/ar:1202/de:1202) sits immediately above the title key — must survive; JSON trailing commas.
- l10n_integrity_test is NOT in any curated gate (host-all sweep only) — a partial ARB removal will NOT surface in the groups gate; run it directly (gate block below).
- 202 interplay: TC-203-08's glow asserts target the current blur mechanism; if 202's opacity-halo lands first, re-map onto the static halo dimensions (same ×factor contract). Recommended order avoids this: 203-B3 before 202.
- Tip-pill offset stays `hitTarget+4` — at scale 1.4 the 42px disc leaves ~1px visual gap to the pill (nothing pins pill-to-disc distance; flagged to product as optional polish — Accepted Difference).

## Device/Relay Proof Profile
host-only for closure (pure projection publishing + widget geometry + string removal; no OS boundary, crypto, relay, or DB migration). No /sims row. **PROD-CRITICAL-leg gate: justified N/A** — there is no wire/transport leg in this plan; the headline wired-path locks are TC-203-01 (adverse-ordering ring seat) and TC-203-09 (persisted-scale wiring), and the retained 197 sentinel (orbit_view_split_test.dart:314) carries the existing wired-path coverage. Optional sim spot-check: join a group → ring node appears live; long-press → drag avatar-size → handles grow.

## Acceptance Gates  (literal)
```bash
# RED (per slice, before its production edits) — must FAIL for the documented reasons
flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart      # B2 TC-203-01 (+ B5 churn later)
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart           # B2 TC-203-02..05, B5 TC-203-17
flutter test test/features/orbit/presentation/widgets/orbit_edit_handle_test.dart     # B3 TC-203-07/08 (compile-red first)
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart  # B3 TC-203-09..11
flutter test test/l10n/orbit_strings_parity_test.dart                                 # B5 TC-203-13
flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart # B5 TC-203-14
flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart  # B5 TC-203-15/16

# Direct GREEN (after each slice) — same commands, all pass

# Preservation sentinels + named gates
./scripts/run_test_gates.sh groups          # expect: all pass; re-derive baseline BEFORE the RED batch (last recorded 1010 at the 198 close-out + growth since; ML-004 flake passes standalone)
flutter test test/features/orbit/ test/l10n/orbit_strings_parity_test.dart            # orbit cluster (last recorded 437 + growth)
./scripts/run_test_gates.sh feed            # expect: 285 (untouched; feed_focus edit is comment-only)
flutter test test/l10n/l10n_integrity_test.dart   # 3-locale parity — NOT in any curated gate; run directly after the ARB removal
./scripts/run_host_test_gates.sh feature-host-all # exit 0

# B5 static proof
flutter gen-l10n && flutter analyze         # 0 new issues (5 pre-existing in untouched files)
GRAPH_OK=1 grep -rn 'orbit_close_friends\|orbit_inner_circle_title' lib/ ; test $? -eq 1   # zero hits

# Mutation verification (QA) — per matrix: each publish-site revert re-reds its TC row; drop host scale wiring → TC-203-09 red; bubble clamp on discSize/2 → TC-203-11 red; clamp removal → TC-203-07's 0.6 row red; re-add an ARB key → TC-203-13 red

# Hygiene
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the seven focused commands above before each slice's production edits (B3 rows 7-8 fail at COMPILE first — the documented new-API-red).
- Expected CHURN (not weaken): B5's enumerated test edits (anchor swaps, polarity flips, import deletions) + B3's handle() builder passthrough + the two doc-pin amendments.
- Pre-existing dirty: graphify-arch/* meta + info.plist at repo root (do not revert).
- Environment blocker (NOT product): none (host-only).
- Scope drift (BLOCKING): any red in `:1710`/`:2003-2013` (wrong publish site flipped), anchor/geometry F-suite (scale leaked into hitTarget), feed gate, or 194 read-clear suite.

## Done Criteria
- [x] Per-slice RED first (B3 compile-red documented), GREEN after, mutation-verified per matrix (12/12; INV-203-1 lock = whole-funnel revert, see Execution Progress).
- [x] B2: all five group-event classes proven on the rings (seat/add/remove/unread/metadata) with zero friend-side events.
- [x] B3: disc/glow/icon scale from ONE helper; hit target + anchors byte-stable; doc pins amended.
- [x] B5: zero string occurrences (grep + analyze clean), 3-locale ARB parity green, chrome clearance re-anchored.
- [x] groups gate (1022) + orbit cluster (463) + feed sentinel (285) + l10n integrity (parity leg green; literal-scan leg = pre-existing orbit3 debt, red since 2026-06-25, in no gate) + feature-host-all (exit 0, 642 targets) pass.
- [x] flutter analyze 0 new; git diff --check clean; BOTH graphs refreshed (FriendsListHeader node gone from the arch graph — `graphify explain` confirms).

## Scope Guard (hard "Do not")
- Do not flip any list-only publish site outside the six named ones (search/typing/intro/invite sites are deliberately list-only — `:1710` locks it).
- Do not scale `hitTarget`, the Positioned centering, the tip-pill offset, or the stepper size (44/48 contracts + every position lock key off them).
- Do not touch `orbit_wired_test.dart:4615`, the `orbit_inner_circle_badge`/`orbit_inner_circle_empty_hint`/`orbit_view_toggle_*` keys, or `l10n_integrity_test.dart`.
- Do not run `flutter gen-l10n` before stripping the three lib call sites.
- Do not touch plans 200/201/202 territory: avatar decode sites, find-pill/label keys, RepaintBoundaries, coalescer, pulse mechanism.
- Do not use pumpAndSettle in any touched suite.

## Accepted Differences / Intentionally Out Of Scope
- Corner steppers stay fixed 48×48 (chrome, not "handle discs" — outside the reported symptom).
- Clamp ceiling (42) never binds in the legal 0.6-1.4 range — dead by construction, documented.
- Tip-pill gap shrinks to ~1px at scale 1.4 (nothing pins it; optional product polish).
- Ring-view-only SCOPE FORK (recorded): if the user narrows B5 later — keep `friends_list_header.dart` + `orbit_screen.dart:26/:593` + `orbit_close_friends` in all 3 ARBs; remove only the viz title + surface caption; skip the header-related test edits (view_split :25/:292/:366/:469/:592, qr :23/:567, loading :338-347/:525) and TC-203-16/18; TC-203-13 then covers only `orbit_inner_circle_title`.
- The two 202-deferred perf follow-ups remain parked with named owners (recorded here so they are not lost): tap-away ~300ms disambiguation removal (spec-pinned gestures — own product-reviewed slice) and sculpt decode quantization (after plan 200's shared provider).
- groupJoinedStream-driven ring test omitted: it funnels to the same `_refreshOrbitGroup` as the message stream (:1041 vs :1648) — one driver + the verified funnel table suffice.

## Dependency Impact
- **Recommended global execution order: 203-B2 → 200 → 201 → 203-B3 → 203-B5 → 202.** B2 first (smallest, highest user value; 202's coalescer then rides publish-all). B3 before 202 (else TC-203-08's glow asserts must re-map onto the opacity-halo). B5 anytime (touches the same surface file as 201's caption-adjacent edits — trivial merge either order, coordinate if concurrent).
- Plan 202's TC-202-08 group-burst row assumes B2's publish-all has landed (its load-count semantics hold either way).
- 201's find-chip GroupAvatar and the ring group nodes only refresh live once B2 lands.

## Reviewer Findings
Two independent reviewers (workflow `wf_ddc43d40-779`, 2026-07-04; 29 + 33 claims spot-verified on HEAD 959b0543, incl. the Completer-gate mechanics, the seeding codec string, the TC-203-11 bubble arithmetic, the loadArb reuse, and the TC-203-18 compile-red claim — all held). Both returned **sufficient-with-minor-fixes, ZERO blocking**; all findings applied in place:
- INV-203-1 overstated mutation coverage — `:652/:699/:703` (+ `:680`'s error path) are header-inert legs no test CAN pin. FIXED: annotated as uniformity-only flips with an explicit INV-MUTATION-VERIFIED exemption; behavior-bearing locks are `:676` (TC-203-01) and `:850` (TC-203-02..05).
- TC-203-01 seeding trap — the shared seedGroup helper closes over the file-level `groupRepo` (:247-248); a literal reading would seed the wrong repo and GREEN would be unreachable. FIXED: row now mandates `gated.saveGroup(...)` directly.
- PROD-CRITICAL-leg checklist gate recorded as an explicit justified N/A (host-only; headline wired locks named).
- Step 1 now requires RECORDING the freshly derived gate baselines in the Execution Progress table.
- Cosmetics: `orbit_geometry_prefs.dart` lives in domain/models (not application/); InMemoryGroupRepository @override anchors :137/:120.

## Arbiter Decision
Structural blockers: none (both reviewers, zero blocking; every checklist gate passes with the applied fixes). | Deferred details: optional throwing-repo variant for the `:680` error leg (uniformity flip, low value); TC-203-15's repurposed daylight test kept rather than folded into view_split :293 (keeps the daylight-background context). | Accepted differences: as listed (incl. the recorded ring-view-only B5 scope fork and the two 202-parked perf follow-ups). Plan is **implementation-ready**; recommended global order 203-B2 → 200 → 201 → 203-B3 → 203-B5 → 202.

## Final Execution Verdict
**IMPLEMENTED + CLOSED 2026-07-04** — all three slices landed in plan order B2 → B3 → B5 on top of grounding HEAD 959b0543:
- **d1687eca** fix(203): B2 six-site publish-all flip (+ TC-203-01..05)
- **8f6b8502** feat(203): B3 scale param + `effectiveDiscSize` + host wiring + bubble clamp (+ TC-203-07..11, 198 doc pins)
- **50e07f7d** refactor(203): B5 three render sites + FriendsListHeader deletion + 3-locale ARB removal + gen-l10n (+ TC-203-13..18 and the full churn list)
- **eeaff05f** test(203): QA — TC-203-10 strengthened to a mid-gesture assert (original `tester.drag` shape could not distinguish settle-only application)

19/19 matrix rows executed; 12/12 mutation reverts re-red; all named gates green (groups 1022 / orbit cluster 463 / feed 285 / feature-host-all 642 targets exit 0); Scope Guard clean (`:4615` untouched, near-miss keys live, no pumpAndSettle, plans 200/201/202 territory untouched).

Execution deviations (all documented in the Execution Progress table): (1) group-node semantics asserts use `getSemantics(...).label` + `startsWith` — the ring node MERGES the initials fallback into its label, exact `bySemanticsLabel` is structurally unmatchable (house 198-F12 prefix idiom; contract identical). (2) INV-203-1's per-site mutation claim narrowed: a `:676`-alone revert is masked by the archived leg's publish-all; the enforced lock is the whole-funnel revert (TC-203-01) + `:850` (TC-203-02..05). (3) TC-198F-04 re-anchored to a 340px band + bounded until-hidden sweep — B5's title removal (~41px) lifts the top-anchored canvas on small surfaces and the saturated arcWrap tip bottoms out at ~366, a blind spot in the plan's "nothing pins absolute canvas y" claim (invariant preserved, not weakened). (4) TC-203-18's compile-red never manifested because the churn edits landed before the deletion (equivalent protection). (5) `l10n_integrity_test` literal-scan leg is red PRE-EXISTING (orbit3 hardcoded strings, 2026-06-25 commits 17a32bef/c03af765; in no gate) — its 3-locale parity leg, the one this plan could affect, is green. Follow-up owner recorded in the 7-bug memory: orbit3 strings need keys (or a scan amendment) before any gate ever adopts l10n_integrity.
