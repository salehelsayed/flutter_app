# 201 - Orbit element identity + find UX (find-pill remount/size/avatar + label-toggle avatar blink)  (Bug)

Status: IMPLEMENTED + host-green 2026-07-04 (8e655c3b feat, 3a46d093 test)
Spec: free-text intent (no formal spec) — user reports 2026-07-03 (#4 "search bar tiny, collapses on first keystroke, result shows name only — avatar missing"; #6 "double-tap shows names but avatars blink — names should simply appear"), root-caused + adversarially verified in workflow `wf_0396f589-131` (B4 + B6, both **confirmed**); plan grounding `wf_0e48db0b-199` (G201). Dossier: memory `project_orbit_seven_bug_debug_2026_07_03.md`.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-03 | Evidence Collector (wf_0396f589 B4/B6 + verify) | inner_circle_interactive_surface.dart, orbital_visualization.dart, orbital_avatar.dart, overflow_badge.dart, orbit_find_matches.dart, orbit_search_dock.dart | Both root causes = unkeyed conditional Positioned slot shifts; pill fixed 200px; chip ignores available item data; verified incl. reverse-edge + edit-exit re-fires and nav-band overlap risk | ground test mechanics |
| 2026-07-04 | Evidence Collector (wf_0e48db0b G201) | sculpt wired suite, unread wired suite, arcs/viz/avatar/badge tests, run_test_gates.sh, ARBs | identical(state) precedent TC-194-11; TC-198F-17/18 literal geometry pins must churn in-slice; enterText cannot prove focus (state identity is the oracle); node0 false-green trap | write plan |
| 2026-07-04 | Planner (this session) | grounding dossiers | Keys on ALL conditional Positioned slots; surface gains a host-supplied bottom-clearance param; NO label fade (user wants instant); badge keying = deliberate behavior change row | reviewer pass |
| 2026-07-04 | Reviewer (sufficiency) | | (pending) | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-04 | contract extraction | git status --short | tree clean after feat(200) landed+committed; only pre-existing dirt (graphify-arch/*, info.plist, spec-doc SKILL, 00-INDEX) + untracked 199/201/202 plan docs | scope confirmed — orbit files disjoint from 200's avatar files | RED |
| 2026-07-04 | RED tests added | sculpt_wired (+9), orbital_arcs (+1), screen_loading (+1) | 11 rows RED for documented reasons: identity `false` (01/02/08/09); geom `584.0`/`198.0` vs 16 (03/04); `0` avatar descendants (05/06); RenderFlex overflow 1516px (07); opacity `0.0` vs 1.0 (10); size `40.0` vs ≥44 (11) | RED for expected reason. TC-201-10 finder switched to `byWidgetPredicate(globalIndex)` — an `Opacity(0)` drops its child from semantics, exactly the HEAD state the row catches | implement |
| 2026-07-04 | implementation | orbital_visualization.dart; inner_circle_interactive_surface.dart; orbit_screen.dart | viz: node/label/badge slot keys + `:207` reduce-motion → `motionEnabled`. surface: 7 conditional-Positioned slot keys, full-width ≥48 pill (collapsed 44), `bottomClearance` param + `bottomInset+max(base,clearance)` bands, `_FindChip` avatar + Flexible/ellipsis. screen: `_innerCircleBottomClearance` wiring | scoped files only (3 production) | GREEN |
| 2026-07-04 | direct GREEN | 3 target test files | `flutter test <3 files>` → **+91 All passed** | reds now green. **F17/F18/20S pins stay green with NO churn** — preserving Positioned `bottom` anchors kept every `surface.bottom - el.bottom` band valid (plan's churn obligation was a conservative prediction that did not materialize) | sentinels |
| 2026-07-04 | preservation GREEN | orbit cluster + cross-feature importers | orbit cluster **+459**; ambient_background + intro_notification_orbit_route + feed_swipe + feed_wired **+91**; `flutter analyze` 6 files **0 issues** | sentinels green (orbital_visualization_test, orbital_avatar_test, overflow_badge_test, view_split :293, unread TC-194, l10n parity, handles F-suite) | gates |
| 2026-07-04 | named gates | run_test_gates.sh groups/feed | **groups +1032 −1** (only ML-004, the documented flake — passes standalone `+1`); **feed +285** (untouched); feature-host-all is a 441-file superset (>10min) — every importer of the 3 changed files was run green individually, so it adds no orbit-adjacent coverage | gate green | QA |
| 2026-07-04 | QA (mutation, worktree-clean reverts) | git-checkout-restored reverts | node-key→**TC-201-08 RED**; bottomClearance→**TC-201-04 nav-overlap RED** (the previously-masked assertion, now proven); compound find-region(pill+banner)→**TC-201-01 RED**; compound viz-seat(badge+node+label)→**TC-201-09 RED**; geom/avatar/reduce-motion/overflow/size rows isolated by the RED-first HEAD revert | blocking: none. Finding: pill/badge single keys are individually redundant (Flutter bottom-up matches the last Stack child) — middle-slot keys are load-bearing; both kept as belt-and-braces | IMPLEMENTED |

## Source Of Truth
- Spec / intent: inline below
- Gate definitions: scripts/run_test_gates.sh
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh (not needed — no integration_test/ additions)
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready

## Exact Problem Statement
On the Orbit inner-circle view: (a) tapping the find pill opens a **200px-wide, height-unconstrained** input bar that looks tiny and out of proportion; (b) the **first matching keystroke collapses it** — the TextField subtree is remounted, dropping focus and the IME, and this re-fires on every matches empty↔non-empty edge and on edit enter/exit while find is open; (c) a matched contact renders as a **name-only chip** although the match carries the full item (avatar data unused). Separately (d): double-tapping to show name labels makes **every avatar blink** — each node is torn down and re-inflated, replaying its 500ms staggered entrance; the overflow badge goes invisible for its full 1.5s entrance (and already does so on every arc expand/collapse today).

What must improve: the find field NEVER remounts while open (typing, matches appearing/disappearing, edit enter/exit); the expanded pill is proportional (full-width bar, ≥48 high) and clears the persistent-nav band on zero-safe-area devices; chips show the member's avatar above the name with ellipsised labels; labels simply appear/disappear with avatars bit-identical (no entrance replay, no badge blink); ring-node entrances honor OS reduce-motion (today hard-coded ON at `orbital_visualization.dart:207`).
What must stay unchanged (→ preserved-green sentinels): tap-away semantics ordering (edit ends first, else find closes — TC-198-48/50/52); find open/close type-swap (open/close SHOULD rebuild the pill child); all handle-geometry locks (TC-198F-01/02/06/07/09); 193 gating (no OrbitSearchTrigger on innerCircle — `orbit_view_split_test.dart:293`); 194 read-clear suite; arc-node entrance on badge expand (arc seats are NEW — fresh inflation is correct); l10n parity (no new strings needed).

## Root Cause (verify → refute confirmed — wf_0396f589 B4+B6, both confirmed)
**B4a (tiny bar):** expanded pill = corner-anchored `Positioned(right:16, bottom: bottomInset+(lifted?88:40))` with hard `width: 200`, no height, `isDense` borderless TextField (`inner_circle_interactive_surface.dart:862-894`) — vs. the all-chats full-width `OrbitSearchDock` (`orbit_search_dock.dart:32-84`). Collapsed pill is 40×40 (`:903-911`), below the 44 convention (`OrbitSearchTrigger` is 44×44).
**B4b (collapse on keystroke):** `if (find.chips.isNotEmpty) Positioned(...)` (`:836-859`) is conditionally inserted before the pill's **unkeyed** `Positioned` (`:862`) in the list spread into the outer Stack (`:589`). Flutter's positional child matching hands the pill's slot to the chip strip; the keyed inner Container (`'orbit-find-pill'` `:867`) cannot rescue it (sibling key matching happens per parent Element) → EditableText deactivated → focus/IME drop; text survives via state-owned `_findController/_findFocus` (`:90-91`). Same mechanism re-fires on the reverse chips edge and on `if (_editing) ...` overlay insertion/removal (`:582-583`; banner `:605`, Reset `:635`, handle layer `:675`, steppers `:702/:713`).
**B4c (no avatar):** `_FindChip` renders label+provenance Texts only (`:986-1002`); `OrbitFindMatch.item` carries the full `OrbitItem` (`orbit_find_matches.dart:18-29`); `OrbitFriend.peerId/avatarPath` (`orbit_friend.dart:37/:40`), `OrbitGroup.groupId/name` + `group.avatarPath` available — construction shapes proven at `orbital_visualization.dart:169` (UserAvatar) and `:313-320` (GroupAvatar).
**B6 (blink):** each label is an **unkeyed** `Positioned` interleaved right after its node's **unkeyed** `Positioned` in the seat loop (`orbital_visualization.dart:188, :211-213`, `_buildLabel :337`); toggling `labelsVisible` shifts every subsequent slot → the inner keyed `Opacity('orbit-node-dim-N')` (`:193-194`) mismatches → every `OrbitalAvatar` after node 0 re-inflates → `_OrbitalAvatarState` re-runs its 500ms + `globalIndex*40ms` staggered entrance (`orbital_avatar.dart:77-95`) = the blink. Badge `Positioned` (`:221-229`) sits at the shifting tail → re-inflates → invisible 1000+500ms (`overflow_badge.dart:50-66`); arc expand/collapse (`:178-210` insertions) already re-inflates it today. Ring entrances ignore reduce-motion: `:207` passes `entranceMotionEnabled: isArc ? motionEnabled : true` (the `orbital_arcs_test.dart:196` "drain the pre-198 ring entrance timers" comment documents this live bug).

Refuted / do-NOT-re-introduce:
- "The pill collapses because state resets `_findOpen`" — REFUTED: `_findOpen` stays true; only the element is remounted. Do not add open/close state patching.
- "Inner ValueKeys are enough" — REFUTED twice on HEAD (pill Container `:867` and node-dim Opacity `:194` both remount today): keys MUST go on the Positioned wrappers themselves.
- "It fires exactly once per open" — REFUTED: reverse chips edge (`'f'→'fz'`) and edit enter/exit re-fire it.
- "A label fade is wanted" — user explicitly wants names to "simply appear": NO fade (Accepted Difference).

## Real Scope
In scope (production):
1. `orbital_visualization.dart`: `ValueKey('orbit-node-${seat.index}')` on each node Positioned (`:188`), `ValueKey('orbit-label-${seat.index}')` on each label Positioned (`_buildLabel :337`), `const ValueKey('orbit-overflow-badge-seat')` on the badge Positioned (`:221`). Keep the inner `'orbit-node-dim-N'` Opacity key (INV-5 asserts read it). Fix `:207` → `entranceMotionEnabled: motionEnabled` for ALL seats.
2. `inner_circle_interactive_surface.dart`: slot ValueKeys on ALL conditional Positioned children spread into the outer Stack — find chip strip (`:836`), find pill (`:862`), edit banner (`:605`), Reset (`:635`), handle layer (`:675`), both steppers (`:702/:713`) — new keys on the Positioned wrappers ONLY (inner keys untouched).
3. Find pill sizing: expanded state `left: 16, right: 16` (drop `width: 200`), `BoxConstraints(minHeight: 48)`, vertical padding, fontSize 15 (mirroring `orbit_search_dock.dart:45-84` input treatment); collapsed pill 40→44 square.
4. Nav-band clearance: new surface param `double bottomClearance` (default 0) added to `InnerCircleInteractiveSurface`; `OrbitScreen` passes its persistent-nav reservation (mirror `_searchDockBottomOffset` mechanics, `orbit_screen.dart:315-320`, nav band `:306-313`) at the mount site (`:551-560`); the pill/chips/steppers bottom bands become `bottomInset + max(band, bottomClearance)`-style so the widened pill cannot sit under the centered nav (today they coexist only because the 200px pill is right-anchored).
5. `_FindChip`: accept the `OrbitItem` (+ `cacheBustKey` for groups); render leading `UserAvatar(peerId:, size: 40)` / `GroupAvatar(groupId:, name:, avatarPath:, borderRadius: circular, cacheBustKey:)` above the name; `Flexible` + `TextOverflow.ellipsis` on the label Row (`:841-858` currently overflows with 4 long names).
Out of scope (owners named): RepaintBoundary/perf work (plan 202); avatar aspect correctness inside chips (plan 200 — land 200 first); RTL find-pill geometry rows (follow-up; RTL currently covers handles only, TC-198F-06); group publish-asymmetry (B2 — separate small fix); any new l10n strings (none needed).

## Files To Inspect Next
Production: lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart; lib/features/orbit/presentation/widgets/orbital_visualization.dart; lib/features/orbit/presentation/screens/orbit_screen.dart (mount site + clearance source); lib/features/orbit/application/orbit_find_matches.dart (read-only); lib/features/orbit/domain models orbit_friend.dart/orbit_group.dart (read-only).
Direct tests: test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart; test/features/orbit/presentation/widgets/orbital_arcs_test.dart; orbital_visualization_test.dart; orbital_avatar_test.dart; overflow_badge_test.dart; NEW rows in orbit_screen-level test for nav clearance.
Dependency-only context: orbit_search_dock.dart (reference look); orbit_unread_indicator_wired_test.dart (identity precedent :296-329); user_avatar.dart/group_avatar.dart ctors; test/l10n/l10n_integrity_test.dart (literal scan); orbit_view_split_test.dart:293.

## Existing Tests Covering This Area
- orbit_sculpt_summon_wired_test.dart (49 tests; **GROUP_TESTS** run_test_gates.sh:254): host() direct-mount harness (:82-111), bounded settle() 16×90ms (:113-117 — pumpAndSettle FORBIDDEN while editing), bgPoint/longPressBg/doubleTapBg (:119-143). Find locks TC-198-39/40/41/44/46/48 (:451-536), edit×find TC-198-50/52 (:554-581), pill/chips band pins TC-198F-17 (:1051-1060: pill bottom closeTo(40), lifted closeTo(88)), TC-198F-18 (:1129-1134 incl. chips 120+144 + pairwise disjointness), steppers TC-198-20S (:1026-1039).
- orbit_unread_indicator_wired_test.dart (**GROUP_TESTS** :246): **the element-identity precedent** TC-194-11 (:296-329) — `tester.state(find.byType(OrbitalAvatar))` before/after + `identical(...)` ("no entrance replay").
- orbital_visualization_test.dart (auto-glob): ring/badge render, TC-197-03 GroupAvatar on ring (:556-575), TC-197-05 initials fallback (:607-629), TC-194-24 reduce-motion satellite freeze (:534-552).
- orbital_arcs_test.dart (auto-glob): bounded settle rationale (:76-83), TC-198-09 arc-entrance-instant-under-reduce-motion (:180-197) — its `:196` drain comment documents the live `:207` ring bug; labelsVisible renders names (:349).
- orbital_avatar_test.dart (auto-glob): satellite rotation doesn't rebuild child subtree (:102).
- overflow_badge_test.dart (auto-glob): 1000ms+500ms entrance (:24-34); reduce-motion instant (:111-123).
- Sentinels: orbit_view_split_test.dart (GROUP_TESTS :241), orbit_wired_test.dart (:227), feed_swipe_test.dart (FEED_TESTS :178), test/l10n/orbit_strings_parity_test.dart (GROUP_TESTS :255), l10n_integrity_test.dart (host-all only).

Missing coverage gaps (all confirmed by grounding): NO element-identity test for the find TextField across any edge; NO pill width/height pin; NO chip-content-beyond-text assert; NO node/badge identity across label toggle or find typing; NO ring reduce-motion entrance test; NO test mounts the nav band together with the surface; NO RTL find geometry.
Already in curated family arrays?: sculpt wired + unread wired + view_split + wired + qr_entry + strings_parity in GROUP_TESTS; viz/arcs/avatar/badge files auto-glob only.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
All wired rows extend `orbit_sculpt_summon_wired_test.dart` (already GROUP_TESTS-pinned; bounded pumps; end every test with `settle()` to drain timers). Widget rows extend the auto-globbed viz/arcs/handle files.
1. `orbit_sculpt_summon_wired_test.dart` :: `'TC-201-01 find TextField State survives edit enter and exit'`
   - Shape: `host(_friends(8))`; settle; tap pill (`ValueKey('orbit-find-pill')`); pump; `s1 = tester.state(find.byType(EditableText))`; `longPressBg` (edit enters — 3 unkeyed Positioneds inserted before the find slots on HEAD); assert `identical(tester.state(find.byType(EditableText)), s1)`; then END the edit via a background tap while editing (`tapAwayBg` — `_onBackgroundTap` ends edit FIRST and leaves find open, `:284-286`). **Reviewer-corrected:** the banner has NO done affordance (IgnorePointer-wrapped text, `:609-620`) and a second long-press is a no-op (`_setEditing` early-returns on same value, `:182`) — background-tap-while-editing IS the exit path, and it deliberately does not clear the query (the else-if at `:286` is not reached). Re-assert identity after exit + assert the pill/text still present. Secondary: `tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus` after the enter pump (the surface passes state-owned `_findFocus` at `:881` — publicly reachable via the widget).
   - RED on HEAD: positional rematch re-inflates EditableText on the `_editing` spread edge → `identical` false.
   - GREEN: slot keys on all conditional Positioneds → element survives.
   - Mutation that re-reds: remove the ValueKey from any edit-overlay Positioned → red.
2. `orbit_sculpt_summon_wired_test.dart` :: `'TC-201-02 find TextField State survives the chips empty↔non-empty edges'`
   - Shape: open pill; `s1 = tester.state(find.byType(EditableText))`; `enterText 'friend'` + pump (empty→non-empty); assert identity; `enterText 'friendzz'` + pump (non-empty→empty); assert identity again. CAVEAT (grounded): `enterText` replaces text AND re-requests focus — state identity is the honest remount oracle; assert `focusNode.hasFocus` only after the rebuild pump as a secondary check.
   - RED on HEAD: chip-strip Positioned `:836` insertion re-slots the pill both directions. Mutation: remove chip-strip slot key → red.
3. `orbit_sculpt_summon_wired_test.dart` :: `'TC-201-03 expanded find pill is a full-width ≥48-high bar'`
   - Shape: open pill; `r = tester.getRect(find.byKey(ValueKey('orbit-find-pill')))`; `s = tester.getRect(find.byType(InnerCircleInteractiveSurface))`; assert `r.left - s.left` within 16±2 AND `s.right - r.right` within 16±2 AND `r.height >= 48`.
   - RED on HEAD: width fixed 200 right-anchored → left gap ≈ surface.width−216. Mutation: restore `width: 200` → red.
   - ALSO assert NON-ARMED pill × chip-strip disjointness in this row (reviewer-caught: with pill minHeight 48 on band 40 vs the chip strip band 96, only ~8px slack remains, and TC-198F-18's pairwise-disjointness sweep runs ARMED-only `:1082-1137` — a padded/taller pill could overlap chips with no test red). `getRect` overlap check pill vs chip strip with chips visible, non-armed.
   - CHURN OBLIGATION (same slice, not weakened): update TC-198F-17 (:1055/:1060), TC-198F-18 (:1129-1134), and the disjointness sweep to the new bands.
4. NEW orbit_screen-level test (place beside the loading test, auto-glob) :: `'TC-201-04 expanded find pill clears the persistent-nav band at zero safe-area'`
   - Shape: pump `OrbitScreen` in persistent-nav mode (bare-ctor precedent: orbit_screen_loading_test) with `tester.view.physicalSize` set and zero padding; open find; assert `tester.getRect(pill)` does not intersect the nav band rect (nav Row is a later Stack child, `orbit_screen.dart:472-512`; band bottom `max(16, safeBottom-14)` height ~64 `:306-313`).
   - RED on HEAD: widened pill (post-row-3 geometry) overlaps the band at safeBottom=0 — NOTE: this row goes RED only against the row-3 target geometry; on unmodified HEAD the 200px pill doesn't overlap. Sequence: land row-3 geometry + this guard in the same slice; the RED proof for this row is against the naive full-width implementation WITHOUT the clearance param (implement row 3 first without clearance → row 4 red → add clearance → green). Mutation: drop the `bottomClearance` wiring → red.
   - Reviewer-strengthened: fold a HEAD-red assertion into this SAME test — assert the pill spans full width (left/right 16) at screen level, which IS red on unmodified HEAD — so the test file is red-on-HEAD outright; AND record the intermediate no-clearance overlap RED in the Execution Progress table (auditable proof, reviewer requirement).
5. `orbit_sculpt_summon_wired_test.dart` :: `'TC-201-05 friend find chip shows the member avatar'` + `'TC-201-06 group find chip shows the group avatar'`
   - Shape: `host([..._friends(5), _group('Book Club')])`; open pill; enterText 'friend0' → `expect(find.descendant(of: find.byKey(ValueKey('orbit-find-chip-0')), matching: find.byType(UserAvatar)), findsOneWidget)`; enterText 'book' → GroupAvatar descendant in its chip. MUST use descendant scoping (viz already mounts UserAvatars/GroupAvatars). Fixture note: keep `unread: 0` (the 194 label suffix breaks exact bySemanticsLabel elsewhere).
   - RED on HEAD: `_FindChip` is text-only. Mutation: drop the avatar child → red.
6. `orbit_sculpt_summon_wired_test.dart` :: `'TC-201-07 four long-name chips lay out without overflow'`
   - Shape: 4 friends with 40-char names matching one query; open+type; `expect(tester.takeException(), isNull)` + assert label `Text.overflow == TextOverflow.ellipsis` and each label sits inside a `Flexible`. (Overflow-throw oracle decision at impl time — grounded as open; structural asserts are primary.)
   - RED on HEAD: Row `:841-858` is unconstrained — no Flexible/ellipsis (structural asserts red; exception oracle possibly also red). Mutation: remove Flexible/ellipsis → red.
7. `orbit_sculpt_summon_wired_test.dart` :: `'TC-201-08 label double-tap does not remount orbit nodes (no entrance replay)'`
   - Shape: `host(_friends(8))`; settle; `before = tester.stateList(find.byType(OrbitalAvatar)).toList()`; `doubleTapBg`; pump; `after = ...`; assert pairwise `identical` over the WHOLE list AND repeat for toggle-off. **Assert on index ≥1** (node 0 keeps its slot on HEAD — node0-only would be falsely green). Harm oracle: on HEAD, a re-inflated node's inner entrance Opacity is 0.0 right after the toggle (finder shape `orbital_arcs_test.dart:186-194`).
   - RED on HEAD: unkeyed interleave shifts slots for i≥1. Mutation: remove node/label Positioned keys → red. Precedent: TC-194-11 identical-state pattern.
8. `orbit_sculpt_summon_wired_test.dart` :: `'TC-201-09 OverflowBadge survives label toggle and arc expand/collapse'`
   - Shape: `host(_friends(20))`; `b1 = tester.state(find.byType(OverflowBadge))`; doubleTapBg + pump → identity; `expandBadge` + pump → identity; collapse → identity. End with settle (drains the 1000ms timer if a remount ever occurs — pending-timer hygiene).
   - RED on HEAD: both legs re-inflate the badge (labels shift its tail slot; arc seats are inserted before it). NOTE: the expand/collapse leg is a **deliberate behavior change** — the badge's entrance replay on every toggle (shipped today) stops; grounded: NO existing test pins the replay (arcs settle helper drains it; find.text succeeds at opacity 0). Mutation: remove the badge Positioned key → red.
9. `orbital_arcs_test.dart` :: `'TC-201-10 ring-node entrance honors reduce-motion'`
   - Shape: `expandable(_friends(8), disableAnimations: true)`; ONE pump; locate a RING node's entrance Opacity via the TC-198-09 finder shape (:186-194); `expect(opacity.opacity, 1.0)`; assert no pending entrance timers leak.
   - RED on HEAD: `:207` hard-codes `entranceMotionEnabled: true` for non-arc → opacity 0 on first frame + staggered timers. Grounded: the fix flips NO existing assertion (TC-198-09 asserts arcs only; `:196` drain stays harmless). Mutation: restore `isArc ? motionEnabled : true` → red.
10. `orbit_sculpt_summon_wired_test.dart` :: `'TC-201-11 collapsed find pill is a 44px tap target'`
    - Shape: closed state; `tester.getSize(find.byKey(ValueKey('orbit-find-pill')))` ≥ 44×44. RED on HEAD: 40×40 (`:903-911`). Mutation: restore 40 → red.
11. Preservation sentinels (no edits): TC-198-39/40/41/44/46 (find behavior), TC-198-48/50/52 (tap-away ordering — a background tap while only find is open clears the query, `:454-458`; identity tests must avoid stray background taps), TC-198F-01/02/06/07/09 + TC-198-71/72 (handles), TC-194 suite, orbit_view_split_test.dart:293, orbital_avatar_test.dart:102, overflow_badge_test.dart:111-123.

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-201-01 | element identity across edit edges | wired widget | orbit_sculpt_summon_wired_test.dart::TC-201-01 | unkeyed `_editing` spread re-slots pill | remove an edit-overlay slot key | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS (:254) |
| TC-201-02 | element identity across chips edges | wired widget | same::TC-201-02 | unkeyed chip-strip insertion | remove chip-strip slot key | same | already in GROUP_TESTS |
| TC-201-03 | pill proportional geometry | wired widget | same::TC-201-03 | width:200 corner pill | restore `width: 200` | same | already in GROUP_TESTS |
| TC-201-04 | pill vs nav band disjoint (zero safe-area) | widget (screen-level) | orbit_screen-level test::TC-201-04 | full-width pill without clearance overlaps nav | drop `bottomClearance` wiring | `flutter test test/features/orbit/presentation/screens/` | AUTO (feature-host-all glob) |
| TC-201-05 | friend chip avatar | wired widget | sculpt wired::TC-201-05 | text-only `_FindChip` | drop UserAvatar child | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS |
| TC-201-06 | group chip avatar | wired widget | same::TC-201-06 | text-only `_FindChip` | drop GroupAvatar child | same | already in GROUP_TESTS |
| TC-201-07 | chip label ellipsis/Flexible | wired widget | same::TC-201-07 | unconstrained Row | remove Flexible/ellipsis | same | already in GROUP_TESTS |
| TC-201-08 | node identity across label toggle | wired widget | same::TC-201-08 | unkeyed node/label interleave (i≥1) | remove node/label keys | same | already in GROUP_TESTS |
| TC-201-09 | badge identity (toggle + expand/collapse) | wired widget | same::TC-201-09 | unkeyed tail badge | remove badge key | same | already in GROUP_TESTS |
| TC-201-10 | ring entrance reduce-motion | widget | orbital_arcs_test.dart::TC-201-10 | `:207` hard-codes true | restore `isArc ? … : true` | `flutter test test/features/orbit/presentation/widgets/orbital_arcs_test.dart` | AUTO (glob) |
| TC-201-11 | collapsed pill 44pt target | wired widget | sculpt wired::TC-201-11 | 40×40 | restore 40 | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS |
| TC-201-12 | geometry-pin churn (F17/F18/20S) | wired widget | sculpt wired::TC-198F-17/18, TC-198-20S updated | n/a — deliberate re-pin to new bands | restore `width: 200` or the `bottomInset+(lifted?88:40)` band → updated pins red | same | already in GROUP_TESTS |
| TC-201-13 | preservation: tap-away ordering + find behavior + handles | wired widget | existing TC-198-39..52, F-suite (sentinels) | n/a | any scope drift → red | same + `flutter test test/features/orbit/` | existing |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** labels/find state across surface re-entry — existing reset seam locks (TC-198-63 labels off on re-entry; find cleared on tap-away TC-198-48) stay green; keys add no new derived state. Covered by sentinels; no new row needed (justified).
- **Sibling-surface consistency:** the all-chats search dock is the sibling find surface — untouched, locked by orbit_view_split_test.dart:293 + dock tests (sentinel). The slot-key treatment is applied to **ALL** conditional Positioneds in BOTH builders (`_buildFind` + `_buildEditOverlay`) — TC-201-01/02 lock both; a sweep step in the implementation confirms no conditional sibling remains unkeyed in the two Stacks.
- **Destructive-action side-effects:** N/A — no delete/cleanup paths. Query-clear on tap-away is existing behavior (TC-198-48 sentinel).
- **Invariant re-verification under new transitions:** the badge-key change removes the expand/collapse entrance replay — TC-201-09 asserts the FULL post-transition state (identity + no invisibility window); arc-node fresh inflation on expansion is deliberately preserved (arc keys are new when appended) and pinned by existing arc entrance tests (:360-361).

## Invariants (locked by tests)
- INV-201-1: the find TextField element is never remounted while `_findOpen` → TC-201-01/02.
- INV-201-2: node/label/badge element identity is independent of `labelsVisible` and `overflowExpanded` → TC-201-08/09.
- INV-201-3: no avatar entrance replays on the label toggle (names "simply appear") → TC-201-08 harm oracle.
- INV-201-4: all entrance animation honors reduce-motion (rings included) → TC-201-10 (+ existing arc/badge/satellite locks).
- INV-201-5 (inherited INV-5): dim asserts keep reading `ValueKey('orbit-node-dim-N')` on the Opacity — keys added at the Positioned level only.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (re-check for concurrent sessions — shared-tree memory). Add all RED rows; run focused commands; confirm each red for its documented reason.
2. `orbital_visualization.dart`: Positioned keys (node/label/badge); `:207` reduce-motion fix. Stop-if: any INV-5 dim assert reds → keys leaked onto the Opacity; fix placement.
3. `inner_circle_interactive_surface.dart`: slot keys on all conditional Positioneds (both builders); do NOT touch inner keys.
4. Pill geometry: expanded `left/right:16` + `minHeight 48` + font 15; collapsed 44; `bottomClearance` param + band math; `OrbitScreen` passes the persistent-nav reservation at `:551-560`. Update TC-198F-17/18/20S pins to the new bands in the SAME commit (churn, not weaken — keep the pairwise-disjointness sweep intact).
5. `_FindChip`: item param + avatars + Flexible/ellipsis. No new strings (l10n literal scan unaffected — avatar widgets take model data).
6. Rerun direct REDs → GREEN; sentinels; named gates. Then `graphify update .` && `./graphify-arch/refresh_arch_graph.sh`.

## Risks And Edge Cases
- pumpAndSettle FORBIDDEN while editing / while unread nodes rotate — bounded pumps only; every new test ends with `settle()` (pending-timer hygiene: badge 1000ms, entrance staggers).
- Do NOT pin pill identity across open/close — the GestureDetector↔Container type-swap is intended (`:865-913`).
- Keys are per `seat.index` — element state follows the INDEX (same as today's positional pairing). Flag for 197-interleave future: a recency re-rank reuses avatar elements across items; safe today (all item visuals derive from build-time props; GroupAvatar has didUpdateWidget re-resolve `group_avatar.dart:44-49`).
- Fixtures with `unread > 0` change semantics labels (194 suffix) → keep unread 0 or RegExp-prefix finders (9c1177a4 lesson).
- Stray background taps in identity tests clear the find query (`:454-458`) — choreograph taps away from bgPoint.
- Chip avatars inherit plan 200's aspect fix — land 200 first (Dependency Impact).

## Device/Relay Proof Profile
host-only for closure (pure widget identity/geometry; no OS boundary, crypto, relay, or DB). No /sims row. Optional visual spot-check on sim after landing.

## Acceptance Gates  (literal)
```bash
# RED (before production edits) — must FAIL for the documented reasons
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart
flutter test test/features/orbit/presentation/widgets/orbital_arcs_test.dart
flutter test test/features/orbit/presentation/screens/   # includes the new TC-201-04 screen-level test

# Direct GREEN (after fix) — same commands, all pass; sculpt wired suite grows 49 → 49+~9

# Preservation sentinels + named gates
./scripts/run_test_gates.sh groups          # expect: all pass; last recorded 1010 at fidelity close-out (re-derive BEFORE the RED batch; ML-004 flake passes standalone)
flutter test test/features/orbit/ test/l10n/orbit_strings_parity_test.dart   # orbit cluster; last recorded 437 → grows by the new rows
./scripts/run_test_gates.sh feed            # expect: 285 (untouched)
./scripts/run_host_test_gates.sh feature-host-all   # exit 0

# Mutation verification (QA) — each key/geometry revert re-reds its row (see matrix)

# Hygiene
flutter analyze            # 0 new (5 pre-existing in untouched files)
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the three focused commands before implementation (identity/geometry/avatar/reduce-motion rows).
- Expected CHURN (not weaken): TC-198F-17/18, TC-198-20S re-pinned to the new pill bands in-slice.
- Pre-existing dirty: graphify-arch/* meta + info.plist (do not revert).
- Environment blocker: none (host-only).
- Scope drift (BLOCKING): any red in handles/geometry F-suite, 193/194/196 suites, feed gate.

## Done Criteria
- [ ] RED first, failed for documented reasons (incl. the i≥1 node-identity trap avoided).
- [ ] Mutation-verified per matrix.
- [ ] Direct GREEN + sentinels + groups gate + orbit cluster + feed gate pass.
- [ ] No DB migration / no device leg (host-only closure).
- [ ] New screen-level test auto-globs (verify in feature-host-all output).
- [ ] flutter analyze 0 new; git diff --check clean; graphs refreshed.

## Scope Guard (hard "Do not")
- Do not move keys onto inner widgets or change existing inner ValueKeys (`orbit-find-pill`, `orbit-find-chip-N`, `orbit-node-dim-N`, `orbit-edit-banner`, `orbit-edit-reset`, handle keys).
- Do not add a label fade or any new animation (user wants instant labels).
- Do not change tap-away ordering, find matching logic (`orbit_find_matches.dart`), or 193 view gating.
- Do not touch orbit_wired.dart refresh paths (B2/202 own those) or RepaintBoundaries (202).
- Do not add l10n strings.

## Accepted Differences / Intentionally Out Of Scope
- No label fade — instant appearance is the requested behavior (reduce-motion moot for labels).
- Badge entrance replay on arc expand/collapse STOPS (deliberate improvement, TC-201-09) — flagged as shipped-behavior change.
- Arc-node entrance on badge expand still runs (new elements — correct).
- RTL find-pill geometry rows deferred (follow-up).
- `fontSize 15` on the pill input is not pinned by any row (cosmetic; the one production sub-edit without a mutation lock — reviewer note, accepted).

## Dependency Impact
- Plan 202's node-RepaintBoundary row prefers the Positioned keys added here (its finder falls back to the dim-Opacity key, but sequencing 201 → 202 is recommended).
- Plan 200 should land first so chip avatars render un-stretched.
- B2 (group publish-all) is independent but makes group chips/ring nodes actually refresh — recommended before user-facing validation.

## Reviewer Findings
Two independent reviewers (workflow `wf_a8091cae-3b0`, 2026-07-04; 26 + 32 claims spot-verified). Both returned **sufficient-with-minor-fixes**; all findings applied in place:
- TC-201-01's edit-exit choreography was wrong (no banner "done" affordance — IgnorePointer text `:609-620`; second long-press is a no-op — `_setEditing` early-return `:182`). FIXED: exit = background tap while editing (`:284-286`, find survives).
- TC-201-04 is honestly not-RED-on-unmodified-HEAD. STRENGTHENED: fold a HEAD-red full-width assert into the same test + record the intermediate no-clearance overlap RED in the execution log.
- Non-armed pill × chip-strip disjointness had ~8px of unpinned slack (F18 sweep runs armed-only). FIXED: added to TC-201-03.
- TC-201-12 mutation cell made literal (`width: 200` / `bottomInset+(lifted?88:40)` restores).
- `fontSize 15` unpinned → recorded as Accepted Difference. Cosmetic anchor drift corrected (`group_avatar.dart:44-49`; TC-198-20S declaration at :1014).

## Arbiter Decision
Structural blockers: none. | Deferred details: exact clearance constant is host-supplied at implementation (mirrors `_searchDockBottomOffset`); RTL find geometry follow-up. | Accepted differences: as listed (no label fade — user-requested instant labels; badge replay stops on expand/collapse — deliberate, TC-201-09). Plan is **implementation-ready**.

## Final Execution Verdict
**IMPLEMENTED + host-green 2026-07-04** — commits `8e655c3b` feat(201), `3a46d093` test(201), + this docs record. On branch `new-orbit`, on top of feat(200).

All 11 TC-201 rows RED-first (documented failure reasons) → GREEN after the fix. **Mutation-verified per matrix:** node-key→TC-201-08; bottomClearance→TC-201-04 nav-overlap (the previously-masked assertion, now proven real); compound find-region keys→TC-201-01; compound viz-seat keys→TC-201-09; the geometry/avatar/reduce-motion/overflow/size rows are isolated by the RED-first HEAD revert (each a single-cause diff on HEAD). **Gates:** orbit cluster 459, groups 1032 (−1 known ML-004 flake, passes standalone), feed 285 (untouched), cross-feature importers 91, `flutter analyze` 0 new, `git diff --check` clean.

**Verified deviations from the plan:**
1. **No F17/F18/20S churn needed.** The plan's churn obligation was a conservative prediction. Preserving the Positioned `bottom` anchors (only changing left/right/width/minHeight, which grow the pill *upward*) keeps every `surface.bottom - element.bottom` band assertion valid — F17/F18/20S stayed green untouched. The full-width pill is still vertically disjoint from steppers (12px) and chips (8px).
2. **TC-201-10 finder.** Switched from `bySemanticsLabel` to `byWidgetPredicate(globalIndex)`: an `Opacity(0)` drops its child from the semantics tree, which is exactly the HEAD (ring-entrance-ignores-reduce-motion) state the row exists to catch — the semantic finder would `StateError` instead of asserting.
3. **Redundant keys.** The plan's per-key mutation cells (remove one edit-overlay/badge key → row reds) don't hold: Flutter's *bidirectional* reconciliation bottom-up-matches the last Stack child, so the pill and badge keys are individually redundant given the middle-slot keys (edit-overlay/chip-strip for the pill; node/label for the badge). The fix keeps both as belt-and-braces; the middle keys are the load-bearing set (proven by the compound mutations above).

**Closure:** host-only (no device/relay/DB leg). feature-host-all not run to completion (441-file superset, exceeds 10-min cap); every test file importing the three changed production files was run green individually, so the superset adds no orbit-adjacent coverage. Group chips will only visibly refresh once B2 (group publish-all) lands — independent, not blocking this host-closable slice.
