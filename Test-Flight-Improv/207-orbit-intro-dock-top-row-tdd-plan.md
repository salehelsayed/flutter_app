# 207 - Orbit Intro Dock — top chrome row, unseen-count semantics  (Feature Improvement)

Status: awaiting-review
Spec: free-text intent (user request 2026-07-05) + ratified mockup `Test-Flight-Improv/207-orbit-intros-under-orbit-mockups.html` (revised 2026-07-05: dock in the TOP chrome row beside the view toggle, folds intros + group invites, ignore-path remnant)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-05 | Evidence Collector | Workflow `wf_7e1b0fcc-6cc` (18 agents: scout → 2×ground → 7×verify + 7×refute → obligations); orbit_screen.dart, orbit_wired.dart, feed_wired.dart, migrations 020/051/094, l10n ARBs + parity tests, run_test_gates.sh arrays | All 7 claims C1–C7 CONFIRMED and survived refute; host-only closure justified; migration 095 required | Planner builds matrix |
| 2026-07-05 | Planner | seam trace + test inventory + obligations (this doc §Root Cause, §Matrix) | 24 TCs, 1 supersede, 12+ raw-count sentinels pinned via empty-seen-set parity invariant | Reviewer sufficiency pass |
| 2026-07-05 | Reviewer (sufficiency) | this plan vs references/sufficiency-checklist.md | see §Reviewer Findings | Arbiter |
| 2026-07-05 | Arbiter | | final structural verdict: see §Arbiter Decision | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-06 00:23 CEST | contract extraction | `Test-Flight-Improv/207-orbit-intro-dock-top-row-tdd-plan.md`; `git status --short`; graphify-arch query for Orbit projection/badge/gate relationships | Dirty tree snapshot captured; uncommitted 211 chrome files present as documented; scope is dock widget + Orbit/Feed unseen projection + migration 095 + l10n/tests/gates; required direct tests and named gates copied from §Acceptance Gates | scope confirmed; no blocker | spawn isolated Executor |
| 2026-07-06 00:23 CEST | Executor spawned | plan file | Spawned worker `019f3461-09bb-7da2-867e-fbca7624d743` with model `gpt-5.5`, reasoning `xhigh`; assigned full plan-207 implementation scope and required evidence contract | running | bounded wait for Executor result |
| 2026-07-06 00:23 CEST | Executor contract/baseline | plan; `git status --short`; `graphify-arch && graphify query ...`; `test/features/orbit/presentation/screens/orbit_connection_indicator_test.dart` | `flutter test test/features/orbit/presentation/screens/orbit_connection_indicator_test.dart` → PASS 12/12; dirty 211 chrome baseline is green before 207 edits | no blocker | add RED tests |
| 2026-07-06 00:23 CEST | RED tests added | `test/features/orbit/presentation/screens/orbit_intro_dock_test.dart`; `test/features/orbit/presentation/widgets/orbit_intro_dock_test.dart`; `test/core/database/migrations/095_intro_review_seen_test.dart`; `test/features/introduction/domain/repositories/intro_review_seen_repository_test.dart`; `test/features/introduction/application/unseen_review_count_test.dart`; `test/features/feed/presentation/screens/feed_wired_test.dart`; `test/l10n/orbit_strings_parity_test.dart` | RED commands run: screen dock test → FAIL missing `OrbitViewProjection.unseenReviewCount`; widget dock test → FAIL missing `orbit_intro_dock.dart`/`OrbitIntroDock`; migration test → FAIL missing `095_intro_review_seen.dart`; repository test → FAIL missing helper/migration/repository impl; unseen unit test → FAIL missing `unseen_review_count.dart`; l10n parity → FAIL `en ARB is missing new orbit key "orbit_intro_dock_label"`; feed `--plain-name TC-207-19` → FAIL missing `IntroReviewSeenRepository` and `FeedWired.introReviewSeenRepository` | RED captured for expected missing 207 APIs; screen RED is compile-shape rather than runtime dock-absent because the new projection field is part of the contract | implement production slice |
| 2026-07-06 00:36 CEST | TAKEOVER | — | gpt-5.5 executor killed mid-flight (user decision; live file collision risk); claude session re-baselined the partial state | worker had finished steps 1–6 (migration 095 + registry, repo+impl, use-case, dock widget, screen mount, wired plumbing) but NOT steps 7–9 (feed_wired filter, ARB keys, GROUP_TESTS append), NOT TC-207-05/06/07/10..15/20-orbit/22 tests, and had NOT wired `onIntroDockTap`/`onIntroDockDismissed` into the OrbitScreen construction | finish from current state |
| 2026-07-06 00:45 CEST | RED re-confirmed | — | `flutter test test/l10n/orbit_strings_parity_test.dart` → FAIL (en ARB missing orbit_intro_dock_label); `feed_wired_test --plain-name TC-207-19` → COMPILE FAIL (missing l10n getters / FeedWired param) | RED for the documented reasons | implement remaining slices |
| 2026-07-06 00:50 CEST | implementation | `app_en/de/ar.arb` (+3 keys each), `feed_wired.dart` (param + unseen filter), `load_introductions_use_case.dart` (fold-set extract, count delegates), `orbit_screen.dart` (mount null-tolerance, reserve 168→206×textScale, stray comment), `orbit_intro_dock.dart` (container Semantics + ExcludeSemantics, Flexible label), `orbit_wired.dart` (**pass handlers into OrbitScreen — the worker never wired them; dock rendered but taps no-op'd, caught by TC-207-10 exactly as C2 predicted**), `run_test_gates.sh` (GROUP_TESTS append) | scoped files only | write missing tests |
| 2026-07-06 01:10 CEST | missing tests written | file A +TC-05/06/07 (harness recipes from TC-211-13/14/17/21); `orbit_wired_test.dart` new sub-group '207 intro dock (wired)' TC-10/11/12/13/14/15/20 + builder `introReviewSeenRepository` param + `_InMemoryIntroReviewSeenRepository` + `emitIntroReceived`; `orbit_view_split_test.dart:262` REWRITE (TC-22) | placement deviation: wired tier lives in orbit_wired_test.dart (already GROUP_TESTS; reuses the 200-line fixture stack) — file A stays harness-only 7 tests | direct GREEN |
| 2026-07-06 01:15 CEST | direct GREEN | all seven direct commands | file A 7/7; widget B 2/2; migration 2/2 (TC-17+TC-23); repo 2/2; unseen unit 4/4; orbit_wired `--plain-name TC-207` 7/7; feed `--plain-name TC-207` 2/2; parity 5/5; `l10n_integrity_test` 2/2 | reds now green | mutation spot-check |
| 2026-07-06 01:15 CEST | mutation check | `orbit_wired.dart` `_onIntroDockTap` viewMode write reverted → TC-207-10 RED → restored → GREEN | PROD-CRITICAL row re-red verified live (TC-207-05 reserve mutation observed red during impl: reserve 168 overlapped the real widest pill) | mutation contract holds | preservation |
| 2026-07-06 01:16 CEST | preservation GREEN | `flutter test orbit_connection_indicator_test.dart orbit_qr_entry_migration_test.dart orbit_screen_archived_groups_test.dart` → 32/32; `orbit_view_split_test.dart` → 17/17 (TC-22 rewrite inside) | sentinels green UNMODIFIED | named gates |
| 2026-07-06 01:20 CEST | hygiene | `flutter analyze` → 0 new (only the standard numbered-migration file_names info ×2, house pattern shared by all 147 migration lints); `git diff --check` clean | no scope-guard violations | gates + closure |
| 2026-07-06 01:50 CEST | named gates | — | `groups` **1170 green exit 0** (1152 baseline + the 14 new dock tests, TC-207 wired suite visible in-run); `feed` **299 green exit 0** (TC-207-19/20 in-run); `feature-host-all` exit 1 from ONLY the documented pre-existing `group_conversation_wired_bg_task_test` red (211/212 plans: ≠ this slice; 207 touches no group-media code) — every other suite green incl. all new 207 files; `core-host-all` exit 1 from `gate_classification_completeness_test` → REAL 207 gap: the repo test sat in unclassified `test/features/introduction/data/` → MOVED to house-pattern `domain/repositories/` (mirrors `group_message_repository_impl_test`), completeness re-run **1028/1028 green** + moved test 2/2 green | gates green modulo the documented pre-existing red | QA verdict |
| 2026-07-06 01:55 CEST | QA (this session, post-takeover) | — | direct suites re-verified green after every fix; mutation TC-207-10 re-red live; sentinels 32/32 unmodified; analyze 0 new; diff --check clean; graphs refreshed (full + arch) | blocking: none | CLOSED — commit |

## Source Of Truth
- Spec / intent: mockup `207-orbit-intros-under-orbit-mockups.html` (Option A + ignore path, revised 2026-07-05) + inline behaviors B1–B6 below
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no new sim scenarios in this plan)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`

## Session Classification
implementation-ready

## Exact Problem Statement
The red badge on the **Orbit** nav button counts pending introductions **and** pending group invitations (`reviewCount`), but the default Orbit view — the Inner-Circle rings — renders **nothing** about them (C1 CONFIRMED: the intro banner and Intros tab are built exclusively inside `_buildAllChatsListSurface`; `InnerCircleInteractiveSurface` has zero intro/reviewCount references). The review surface hides behind the top-left view toggle, which most users never flip. The badge points at a blank room.

Per the ratified 207 mockup, a green **intro dock** joins the top chrome row on the inner-circle view — immediately right of the view toggle, in the band the 209 QR/Scan→Settings migration freed — showing the pending people's (and groups') faces + an **unseen** count; tap opens the existing Intros review tab. Dismissing the dock collapses it to a calm 32px dashed **remnant** in the same slot (persisted), clears the nav badge (badge = unseen, not pending), and only genuinely **new** items re-inflate the dock.

What must improve: B1 dock renders on inner-circle iff pending exists (nothing at 0); B2 dock folds friend intros + group invites (the badge's fold); B3 dock/remnant tap lands on all-chats + Intros tab in one tap; B4 dismissal → persisted remnant; B5 badge/dock count = unseen; B6 dock behaves like sibling chrome (sculpt-edit hide, physical RTL, Semantics, l10n).
What must stay unchanged (→ preserved-green sentinels): 211 pill geometry/identity/scrim locks, 209 T3 top-center background tap, 193 initialFilterTab single-shot lock, all 12+ raw-count badge locks (via the empty-seen-set parity invariant INV-4), list-view banner + Intros tab behavior (dock is an **additional** entrance — C7).

## Root Cause (verify → refute confirmed — workflow `wf_7e1b0fcc-6cc`, 7/7 claims survived)
- **C1** Inner-circle view has zero intro affordance; reachability = toggle→list or notification `initialFilterTab` only. Banner gate: `orbit_screen.dart:895-897` (all-chats only). 
- **C2** `_onFilterChanged('intros')` (`orbit_wired.dart:2012-2016`) clears `_openRowNotifier`, sets `_filterTab`, republishes — and nothing else: never flips `_viewMode`, never setStates. Only `_viewMode` writes on HEAD: `initState` :418 (193 lock), `_resetToInnerCircleView` :559, `_onToggleView` :2023-2031. **A dock tap must set `_viewMode = allChats` AND `_filterTab = 'intros'` together — net-new handler.**
- **C3** Badge semantics are RAW pending on both sides: `orbit_wired.dart:358` `reviewCount = _introsCount + _pendingGroupInvites.length`; `feed_wired.dart:527-589` same fold → `:581`. **No seen/unseen/dismissed state exists anywhere** (exhaustive grep + migration audit: 019 intro statuses are action states; 051 `pending_group_invites` has no seen column).
- **C4** The only dismissal precedent — `dismissIntroBanner` / migration `020_intro_banner_columns.dart` (`contacts.intros_banner_dismissed`, `contacts_db_helpers.dart:343-355`) — is a per-contact chat-banner gate, keyed by peer_id; **not reusable** (can't represent group invites or global dock state). **New store + migration required; next-free number: 095** (directory tops at `094_group_messages_group_ts_index.dart`).
- **C5** Top band post-211 (uncommitted): toggle = physical `Positioned(left:16, top: safeTop+8)` 40×40 (`orbit_view_toggle_button.dart:43-55`); 211 pill = `Positioned(right:64, top: safeTop+8, height:40)` **intrinsic width growing leftward** (`orbit_screen.dart:786-795`); FAB LAST child (:798-814; trailing-scan trap comment :781-785). Dock slot = `left:64`, right-bounded by the pill's floating left edge (widest state = 'Online' + debug `($connectionCount)`).
- **C6** The Intros tab reviews BOTH folds: `_buildIntroEntries` (`orbit_screen.dart:1074-1112`) renders `PendingGroupInviteCard` (:1179-1190) per invite + `IntroRow` (:1219/:1257) per intro — same data as the count. **No destination gap; no descope needed.**
- **C7** List banner already count-gated (:895) with factored copy builders (`orbit_pending_items`, `_buildIntroBannerSubtitle` :978-991 mixed/invites/intros) — reusable vocabulary; banner + tab remain.

Refuted / do-NOT-re-introduce: *(none of C1–C7 was refuted; refute pass confirmed additionally:)* (a) nothing in the uncommitted 211/212 diffs adds any intro affordance — planning the dock duplicates nothing; (b) the "212 dock" in orbit_screen comments is the SEARCH dock (bottom band), unrelated — do not conflate; (c) `PendingGroupInvite` carries **no avatar** (groupName snapshot only, `pending_group_invite_card.dart:25-34`) — do NOT plan a real group image in the facepile; use the group glyph.

## Real Scope
In scope: new `OrbitIntroDock` widget (dock + remnant states); Layer 4c mount in `orbit_screen.dart` (inner view, keyed, before FAB); `_onIntroDockTap`/`_onIntroDockDismissed` handlers + unseen plumbing in `orbit_wired.dart`; `unseenReviewCount` projection field; seen-set store (migration 095 + repository + pure use-case); `feed_wired.dart` badge switches to unseen; 3 l10n keys ×3 ARBs + parity list; supersede `orbit_view_split_test.dart:262-294`; append new test file to `GROUP_TESTS`.
Out of scope (owner in §Accepted Differences): long-press total-hide, Undo snackbar, Option D in-place tray, seen-set garbage collection, list-banner unseen migration, real group-invite avatars.

## Files To Inspect Next
Production: `lib/features/orbit/presentation/screens/orbit_screen.dart` (Stack :606-816, banner :895-991, intro sliver :997-1112), `lib/features/orbit/presentation/screens/orbit_wired.dart` (:279-283, :323-397, :413-420, :802-836, :1002-1048, :2013-2031, :2476), `lib/features/feed/presentation/screens/feed_wired.dart` (:527-589), `lib/features/orbit/presentation/widgets/orbit_view_toggle_button.dart` (sibling pattern), `lib/features/orbit/presentation/widgets/pending_group_invite_card.dart`, `lib/features/introduction/presentation/widgets/intro_row.dart` (:75 UserAvatar usage), `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/core/database/migrations/020_intro_banner_columns.dart` (idempotency pattern), the migration registry = `lib/core/database/app_database_version.dart:1` (`currentIdentityDatabaseVersion = 94`) + the inline `onUpgrade` closure `lib/main.dart:579+`, `lib/l10n/app_en.arb` / `app_de.arb` / `app_ar.arb`, `main.dart:4252-4295` (intro route).
Direct tests: `test/features/orbit/presentation/screens/{orbit_screen_pump_harness.dart, orbit_wired_test.dart (:184-329 builder, :474-589 invite fixtures), orbit_view_split_test.dart (:262-294 supersede, :639/:701 sentinels), orbit_connection_indicator_test.dart (TC-211-11/13/14/15/17/21/22 recipes), orbit_qr_entry_migration_test.dart (:349 T3, :375 T4), orbit_screen_archived_groups_test.dart (:387 gate precedent), orbit_sculpt_summon_wired_test.dart (TC-198-33/36/38 persistence template)}`, `test/features/feed/presentation/screens/feed_wired_test.dart` (:647-:915 badge locks), `test/l10n/orbit_strings_parity_test.dart` (:18-57), `test/l10n/l10n_integrity_test.dart`.
Dependency-only: `lib/core/notifications/notification_route_target.dart:40`, `friends_filter_toggle.dart:46-53`, `check_intro_banner_use_case.dart` (do not touch), `scripts/run_test_gates.sh` (:212-279 GROUP_TESTS).

## Existing Tests Covering This Area
- `orbit_view_split_test.dart:262-294` — **the only inner-view intro-absence lock** (asserts `find.text('1 item pending')` findsNothing on inner view with a seeded intro) → SUPERSEDED in-slice (TC-207-22).
- `orbit_connection_indicator_test.dart` (211, uncommitted) — pill geometry/right-half pin :143-168, edit-hide :188-231, scrim :233, RTL :259, textScale :296, element identity :411-458 → sentinels, must pass UNMODIFIED.
- `orbit_qr_entry_migration_test.dart:349` (T3 top-center background tap), `:375` (T4 intros deep-link) → sentinels.
- `orbit_view_split_test.dart:639/:701/:570`, `orbit_screen_archived_groups_test.dart:387/:407/:454` (banner gating + copy), `orbit_intros_wiring_test.dart`, `orbit_wired_test.dart:964/:1004/:1052/:3320` → sentinels.
- `feed_wired_test.dart:647/:683/:716/:737/:782/:843/:870/:915` — 8 raw-count badge locks → stay green via INV-4 (none seeds a dismissal).
- **`onIntroBannerTap` is tapped by ZERO tests today** — B3 tap semantics have no coverage at all.
Missing coverage gaps: B1–B6 all net-new (inventory §Coverage GAPS). Already in curated arrays: `orbit_wired_test`, `orbit_view_split_test`, `orbit_qr_entry_migration_test`, `orbit_connection_indicator_test`, `orbit_sculpt_summon_wired_test`, `orbit_search_trigger_placement_test`, `orbit_strings_parity_test` = GROUP_TESTS; `feed_wired_test` = FEED_TESTS; INTRO_TESTS holds zero orbit-surface files (by design, unchanged).

## Design (seam-level, verified anchors — re-anchor at diff time, orbit_screen.dart is under concurrent edit)
1. **Widget** `lib/features/orbit/presentation/widgets/orbit_intro_dock.dart`: one widget, two states. *Dock*: 40px-high green capsule (`0xFF157A39`-family fill/border per banner vocabulary), facepile = up to 2 `UserAvatar(peerId: foldedReviewItems[i].targetPeerId, size: 26)` + one group **glyph** chip when `pendingGroupInviteCount > 0`, label = `l10n.orbit_intro_dock_label(unseenCount)`, chevron; `Dismissible` (horizontal) → `onDismissed`. *Remnant*: 32px dashed monochrome chip, no count. Both: `Semantics(button: true, label: …)`.
2. **Mount** (`orbit_screen.dart`, new Layer 4c adjacent to Layer 4b, **before** the FAB — FAB stays LAST child per :781-785): `if (viewMode == innerCircle && !innerEditing && listProjection.reviewCount > 0) Positioned(key: ValueKey('orbit-intro-dock-slot'), top: safeTop+8, left: 64, right: kIntroDockRightReserve, height: 40, child: Align(alignment: Alignment.centerLeft, child: OrbitIntroDock(...)))`. `kIntroDockRightReserve = 168` (= 64 pill anchor + 96 widest-pill reserve + 8 gap; TC-207-05 pins clearance at the widest pill state — adjust constant, not the test, if the pill grows). Physical `Positioned` (non-directional), matching toggle/pill RTL stance. Dock state = `unseenReviewCount > 0 ? dock : remnant`.
3. **Data**: dock reads the **list projection** on the inner view — already published unconditionally; the nav band already consumes `projection.reviewCount` on both surfaces (`orbit_screen.dart:598`). Add `unseenReviewCount` to `OrbitViewProjection`; nav badge (`:598`) switches `reviewCount` → `unseenReviewCount`.
4. **Tap** (`orbit_wired.dart`): new `_onIntroDockTap()` = `setState(() { _viewMode = OrbitViewMode.allChats; }); _onFilterChanged('intros');` + `emitFlowEvent(ORBIT_INTRO_DOCK_TAP)` (discriminator vs the initialFilterTab route, which must NOT emit it). Remnant tap → same handler. Note: routing through `_onFilterChanged` also nulls `_openRowNotifier` (closes any open swipe-row) — harmless and desirable on surface entry.
5. **Seen-set store**: migration `095_intro_review_seen.dart` — `CREATE TABLE IF NOT EXISTS intro_review_seen (item_key TEXT PRIMARY KEY, seen_at TEXT NOT NULL)` (020's PRAGMA-idempotent shape). **Registry = TWO files** (reviewer finding 1): bump `currentIdentityDatabaseVersion` 94→95 in `lib/core/database/app_database_version.dart:1` AND add the `oldVersion < 95` dispatch entry to the inline `onUpgrade` closure at `lib/main.dart:579+`. Item identity: `intro:<targetPeerId>` / `invite:<groupId>`. Repository `IntroReviewSeenRepository` (`markAllSeen(Set<String>)`, `loadSeenKeys()`). Pure use-case `computeUnseenReviewKeys(currentKeys, seenKeys)` → unseen = current − seen (stale seen keys ignored; **empty seen ⇒ unseen == raw**).
6. **Dismissal** = `markAllSeen(currentKeys)`. It must NOT touch introduction/invite rows (no pass/decline side-effects — `pass_introduction_use_case.dart:12-13` notifies the introducer; dismiss is silent).
7. **feed_wired** `_refreshOrbitBadgeCount` (:527-589): subtract seen keys via the same repo (injected, nullable → raw semantics when absent, preserving every existing construction).
8. **Intros tab count + list banner stay RAW** (deliberate asymmetry, test-locked): the tab is the always-on fallback listing the full backlog.
9. **l10n**: `orbit_intro_dock_label` (plural), `orbit_intro_dock_semantics`, `orbit_intro_remnant_semantics` in en/de/ar + `newOrbitKeys` parity list.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
New file A = `test/features/orbit/presentation/screens/orbit_intro_dock_test.dart` (harness + wired; **append to GROUP_TESTS**). New file B = `test/features/orbit/presentation/widgets/orbit_intro_dock_test.dart` (pure widget; AUTO). Recipes: harness `buildOrbitScreenHarness` for geometry; `buildOrbitWired` (orbit_wired_test.dart:184-329 pattern + :474-589 invite fixtures) for behavior; `pumpOrbitFrames`.

1. **A::'TC-207-01 dock renders on inner-circle when reviewCount>0'** — Tier: widget(harness). Setup: list projection reviewCount=3 (2 intros + 1 invite), viewMode=innerCircle. RED on HEAD: no dock layer exists — `find.byKey(ValueKey('orbit-intro-dock'))` findsNothing. GREEN: dock present, within top band (`top ≈ safeTop+8`, `left == 64`). Mutation: revert Layer 4c mount → red.
2. **A::'TC-207-02 count-gated: present at >0 then nothing at 0'** — widget(harness). Two-pump structure (non-vacuous: first half is RED on HEAD). GREEN: at reviewCount=0 neither dock nor remnant. Mutation: drop the `reviewCount > 0` gate → red.
3. **A::'TC-207-03 all-chats keeps banner, no dock; dock returns on toggle back'** — widget(harness). RED via dock-present half. Mutation: remove `viewMode == innerCircle` gate → red (dock over banner).
4. **B::'TC-207-04 facepile = intro avatars + group glyph; label = plural unseen count'** — widget(pure). RED: widget file absent (compile). GREEN: ≤2 `UserAvatar` by targetPeerId, group glyph iff invites>0 (NO image expectation — C-refute: invites have no avatar), label from `orbit_intro_dock_label`. Mutation: revert facepile builder → red.
5. **A::'TC-207-05 geometry: clears widest pill @390dp; textScale 1.5; p2pService null'** — widget(harness). Widest pill state ('Online' + debug count). RED: dock absent. GREEN: dock.right ≤ pill.left − 8; band top; no overlap at textScale 1.5; null-service case dock still capped at the reserve. Mutation: set `kIntroDockRightReserve = 64` → overlap → red.
6. **A::'TC-207-06 FAB scrim covers dock; keyed element survives view flips'** — widget(harness). Mirror TC-211-14 :233 + TC-211-21 :411 (`tester.element` + `identical`). RED: dock absent. Mutation: mount dock AFTER the FAB → scrim assert red; strip the ValueKey → identity assert red.
7. **A::'TC-207-07 sculpt-edit hides dock and remnant'** — widget(harness). Recipe TC-211-13 (:188-231, `orbit-edit-banner`). RED: dock absent. Mutation: drop `!innerEditing` → red.
8. **A::'TC-207-08 RTL: dock stays physical left band'** — widget(harness). Recipe TC-211-15 :259. RED: dock absent. Mutation: `Positioned` → `PositionedDirectional` → red.
9. **B::'TC-207-09 dock + remnant expose button Semantics with l10n labels'** — widget(pure). RED: compile. Mutation: remove `Semantics` wrapper → red.
10. **A::'TC-207-10 dock tap → allChats + Intros tab with IntroRow AND PendingGroupInviteCard; emits ORBIT_INTRO_DOCK_TAP; route path does not emit'** — Tier: wired-host (the ONLY tier that can fail for the real reason — C2: no setState/no view flip is invisible to a callback test). Seed 1 intro + 1 invite, tap dock from inner view. RED: no dock/handler on HEAD. GREEN: all-chats surface + both row types + event exactly once; second scenario pumps `initialFilterTab:'intros'` and asserts NOT emitted (discriminator). Mutation: revert the `_viewMode = allChats` write inside `_onIntroDockTap` → surface stays inner → red.
11. **A::'TC-207-11 remnant tap opens the same review'** — wired-host. Dismiss first, tap remnant. RED: no remnant. Mutation: detach remnant onTap → red.
12. **A::'TC-207-12 dock count = folded intros + joined-filtered invites'** — wired-host. Fixtures: duplicate-target intros fold to 1; an already-joined invite excluded (`:818-824`). RED: dock absent. Mutation: bind label to `_introsCount` only → red.
13. **A::'TC-207-13 swipe-dismiss → 32px remnant; nav badge clears; pending rows PRESERVED; no pass/decline side-effects'** — wired-host. RED: no dismiss machinery. GREEN: remnant key present (size 32), `unseenReviewCount == 0` (nav badge 0), introduction repo + invite repo rows unchanged, no pass/decline calls recorded by fakes (destructive-action sweep). Mutation: make dismiss call the pass path → red.
14. **A::'TC-207-14 dismissal survives full remount (remnant reconstructs from store)'** — wired-host + in-memory seen repo shared across two `buildOrbitWired` mounts (template TC-198-33/36/38; includes "no store write until first dismissal"). RED: nothing persists. Mutation: skip `loadSeenKeys()` on init → red. *(Lifecycle blind-spot row.)*
15. **A::'TC-207-15 only news re-inflates: new intro after dismissal → dock at unseen=1; tab keeps raw backlog=3; badge=1'** — wired-host. RED: no unseen machinery. GREEN asserts the FULL post-transition state: dock label 1 (not 3), remnant gone, nav badge 1, `FriendsFilterToggle` intros count 3, banner (on allChats) still raw. Mutation: recompute unseen as raw → label 3 → red. *(Invariant-re-verification blind-spot row.)*
16. **`test/features/introduction/domain/repositories/intro_review_seen_repository_test.dart::'TC-207-16 seen keys persist across reopen; markAllSeen records intro+invite keys'`** — Tier: repo integration, **real SQLCipher** (`sqfliteFfiInit()` + `databaseFactoryFfi.openDatabase(inMemoryDatabasePath)` + migration 095 in setUp). RED: repo/migration absent (compile). Mutation: revert the INSERT in markAllSeen → red.
17. **`test/core/database/migrations/095_intro_review_seen_test.dart::'TC-207-17 v95 creates intro_review_seen; run-twice idempotent; preserves rows'`** — Tier: migration host, **real SQLCipher**, migration function called DIRECTLY (house pattern: 094/intro migration tests import + call, no dispatcher). `PRAGMA table_info` columns (item_key PK, seen_at), run twice, pre-seeded row survives. RED: migration file absent. Mutation: revert the `CREATE TABLE` in 095's body → PRAGMA assert red.
23. **Same file::'TC-207-23 identity DB version is 95'** — Tier: migration host. Imports `app_database_version.dart`, asserts `currentIdentityDatabaseVersion == 95` — pins the registry bump the direct-call pattern cannot see. RED on HEAD: constant is 94. Mutation: revert the version bump → red. (The `oldVersion < 95` dispatch closure in `main.dart:579+` stays direct-call-tested only — justified Accepted Difference, house precedent.)
18. **`test/features/introduction/application/unseen_review_count_test.dart::'TC-207-18 unseen fold math'`** — Tier: unit. Cases: empty seen ⇒ unseen==raw (INV-4 at unit tier); seen subset subtracts; NEW key re-inflates; stale seen keys (expired/accepted items) ignored. RED: use-case absent. Mutation: return raw unconditionally → red.
19. **`test/features/feed/presentation/screens/feed_wired_test.dart::'TC-207-19 orbit badge = unseen (dismissed→0; new invite→1)'`** — Tier: wired-host (feed side; cross-feature obligation). Seed dismissal via injected seen repo. RED on HEAD: `feed_wired.dart:581` raw sum — badge shows 2, expected 0 (compile-RED first: repo param absent). Mutation: revert the seen filter in `_refreshOrbitBadgeCount` → red.
20. **A + feed::'TC-207-20 empty-seen parity: unseen == raw on both wireds; tab + banner stay raw after dismissal'** — wired-host ×2. RED: `unseenReviewCount` field absent (compile). GREEN: with NO dismissal, unseen equals raw on orbit and feed (this is the sentinel that keeps all 12+ raw-count locks green); after dismissal, tab count and banner copy remain raw (deliberate asymmetry locked — sibling-surface sweep). Mutation: subtract seen from the tab count → red.
21. **`test/l10n/orbit_strings_parity_test.dart` (edit)::'TC-207-21 dock keys in newOrbitKeys, present + non-empty in en/de/ar'** — l10n tier. Write the key-list edit FIRST → RED (keys not yet in ARBs); GREEN after ARB additions (+ `l10n_integrity_test` placeholder parity for the plural). Mutation: delete keys from `app_ar.arb` → red.
22. **`test/features/orbit/presentation/screens/orbit_view_split_test.dart:262-294` (REWRITE — supersede)::'TC-207-22 default entry: inner surface, no list-coupled affordances, intro dock present'** — wired-host, already in GROUP_TESTS. Keeps the FriendRow/GroupRow/FriendsFilterToggle/OrbitSearchTrigger findsNothing asserts; REPLACES `find.text('1 item pending') findsNothing` with dock-present. RED on HEAD: dock absent. Mutation: revert dock mount → red.

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-207-01 | UI render gate | widget | A::TC-207-01 | no dock layer in orbit_screen Stack | revert Layer 4c mount | `flutter test test/features/orbit/presentation/screens/orbit_intro_dock_test.dart` | AUTO + **append to GROUP_TESTS** |
| TC-207-02 | UI count gate | widget | A::TC-207-02 | dock-present half fails (no dock) | drop `reviewCount > 0` gate | same | AUTO + GROUP_TESTS |
| TC-207-03 | surface exclusivity | widget | A::TC-207-03 | dock-present half fails | drop `viewMode == innerCircle` gate | same | AUTO + GROUP_TESTS |
| TC-207-04 | UI content | widget | B::TC-207-04 | widget file absent (compile) | revert facepile builder | `flutter test test/features/orbit/presentation/widgets/orbit_intro_dock_test.dart` | AUTO (glob) |
| TC-207-05 | geometry vs pill (S1) | widget | A::TC-207-05 | dock absent | reserve → 64 (overlap) | file A + `./scripts/run_test_gates.sh groups` | AUTO + GROUP_TESTS |
| TC-207-06 | mount order/identity (S2) | widget | A::TC-207-06 | dock absent | mount after FAB / strip key | file A + groups | AUTO + GROUP_TESTS |
| TC-207-07 | edit-hide (B6) | widget | A::TC-207-07 | dock absent | drop `!innerEditing` | file A | AUTO + GROUP_TESTS |
| TC-207-08 | RTL (B6) | widget | A::TC-207-08 | dock absent | PositionedDirectional swap | file A | AUTO + GROUP_TESTS |
| TC-207-09 | semantics (B6) | widget | B::TC-207-09 | compile | remove Semantics | file B | AUTO (glob) |
| TC-207-10 | tap flip + discriminator (B3) | wired-host | A::TC-207-10 | no handler; no view+tab flip path at runtime | revert `_viewMode` write in handler | file A + groups | AUTO + GROUP_TESTS |
| TC-207-11 | remnant tap (B4) | wired-host | A::TC-207-11 | no remnant | detach remnant onTap | file A | AUTO + GROUP_TESTS |
| TC-207-12 | fold binding (B2) | wired-host | A::TC-207-12 | dock absent | bind to `_introsCount` only | file A + groups | AUTO + GROUP_TESTS |
| TC-207-13 | dismiss→remnant, rows preserved (B4) | wired-host | A::TC-207-13 | no dismiss machinery | dismiss calls pass path | file A + groups | AUTO + GROUP_TESTS |
| TC-207-14 | persistence across remount (B4) | wired-host | A::TC-207-14 | nothing persists | skip loadSeenKeys on init | file A | AUTO + GROUP_TESTS |
| TC-207-15 | re-inflate on news only (B5) | wired-host | A::TC-207-15 | no unseen machinery | unseen := raw | file A + groups | AUTO + GROUP_TESTS |
| TC-207-16 | repo durability (B4/B5) | repo integration (real SQLCipher) | intro_review_seen_repository_test::TC-207-16 | repo absent (compile) | revert markAllSeen INSERT | `flutter test test/features/introduction/domain/repositories/intro_review_seen_repository_test.dart` | AUTO (glob) |
| TC-207-17 | migration DB v95 | migration host (real SQLCipher) | 095_intro_review_seen_test::TC-207-17 | migration absent | revert CREATE TABLE in 095 body | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (test/core/**) |
| TC-207-23 | registry version pin | migration host | 095_intro_review_seen_test::TC-207-23 | `currentIdentityDatabaseVersion` is 94 | revert 94→95 bump | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (test/core/**) |
| TC-207-18 | unseen fold math (B5) | unit | unseen_review_count_test::TC-207-18 | use-case absent | return raw unconditionally | `flutter test test/features/introduction/application/unseen_review_count_test.dart` | AUTO (glob) |
| TC-207-19 | feed badge unseen (B5) | wired-host | feed_wired_test::TC-207-19 | feed_wired:581 raw sum; no repo param | revert seen filter | `./scripts/run_test_gates.sh feed` | rides FEED_TESTS (existing) |
| TC-207-20 | empty-seen parity + raw tab/banner (INV-4) | wired-host ×2 | A + feed_wired_test::TC-207-20 | `unseenReviewCount` absent (compile) | subtract seen from tab count | groups + feed gates | AUTO + GROUP_TESTS / FEED_TESTS |
| TC-207-21 | l10n keys ×3 ARBs (B6) | l10n host | orbit_strings_parity_test::TC-207-21 | keys in list, not in ARBs (list-first) | delete keys from app_ar.arb | groups gate (parity test in GROUP_TESTS) | rides GROUP_TESTS (existing) |
| TC-207-22 | supersede inner-view absence lock (B1) | wired-host | orbit_view_split_test::TC-207-22 (rewrite :262-294) | dock absent on HEAD | revert dock mount | groups gate | rides GROUP_TESTS (existing) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** TC-207-14 (remnant reconstructs from the persisted seen-set on full remount; store not written until first dismissal) + TC-207-16 (reopen).
- **Sibling-surface consistency:** badge consumers enumerated — orbit nav badge (TC-207-13/15), feed nav badge (TC-207-19), Intros tab count + list banner **deliberately stay raw** and the asymmetry is test-locked (TC-207-20).
- **Destructive-action side-effects:** TC-207-13 asserts dismissal writes ONLY seen keys — introduction + invite rows preserved, no pass/decline (introducer notification) side-effects. TC-207-16 asserts exactly which keys are written.
- **Invariant re-verification under new transitions:** TC-207-15 asserts the FULL post-re-inflate state (dock label, remnant gone, badge, raw tab count, raw banner) — not just the headline flag.

## Invariants (locked by tests)
- INV-1: inner-circle view shows the dock iff `reviewCount > 0` and never on all-chats → TC-207-01/02/03/22.
- INV-2: one tap from the rings reaches the full review surface (both item kinds) → TC-207-10/11 (+C6 destination completeness).
- INV-3: dismissal is silent and non-destructive (no pass/decline, rows preserved) → TC-207-13/16.
- INV-4: **empty seen-set ⇒ unseen == raw** — the parity invariant that keeps all 12+ existing raw-count badge locks green unmodified → TC-207-18(unit)/20(wired). Any of those sentinel files going red = invariant violated, not a test to rewrite.
- INV-5: 211 chrome contracts untouched — pill geometry/right-half, element identity, scrim order, FAB last child → sentinels TC-211-11/14/21/22 + TC-207-05/06.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every matrix row.

## Step-By-Step Implementation Plan
0. Contract extraction: `git status --short` snapshot (tree already carries uncommitted 211 — coordinate; see Risks). **Re-anchor every orbit_screen.dart/orbit_wired.dart line** (concurrent session live-edits it).
1. RED wave 1 (compile-level): parity key-list edit (TC-207-21); migration test (TC-207-17); repo test (TC-207-16); unit test (TC-207-18). Run each — confirm RED for the documented reason.
2. RED wave 2 (behavior): files A + B (TC-207-01..15 minus implemented), feed_wired additions (TC-207-19/20), view-split rewrite (TC-207-22). Confirm RED.
3. Migration 095 + BOTH registry edits (`app_database_version.dart` 94→95; `main.dart:579+` onUpgrade `oldVersion < 95` entry); `IntroReviewSeenRepository`; `computeUnseenReviewKeys` use-case. → TC-207-16/17/18/23 GREEN.
4. `OrbitIntroDock` widget (dock + remnant + Semantics + Dismissible). → TC-207-04/09 GREEN.
5. `orbit_wired.dart`: inject seen repo (nullable → raw semantics); load seen keys with `_loadIntroductions`/`_loadPendingGroupInvites`; compute + publish `unseenReviewCount`; `_onIntroDockTap` (setState viewMode + `_onFilterChanged('intros')` + flow event); `_onIntroDockDismissed`. Stop-if: `_publishListProjection` is notifier-only (no setState) — the dock re-render on unseen change must come through the projection listenable, NOT a setState; if a setState turns out to be required for the surface flip only, keep it scoped to `_viewMode`.
6. `orbit_screen.dart`: `OrbitViewProjection.unseenReviewCount`; Layer 4c mount (keyed, before FAB); nav badge :598 switches to `unseenReviewCount`. → TC-207-01..15, 22 GREEN.
7. `feed_wired.dart`: seen repo param + filter in `_refreshOrbitBadgeCount`. → TC-207-19/20 GREEN.
8. l10n: 3 keys × en/de/ar. → TC-207-21 GREEN.
9. `scripts/run_test_gates.sh`: append file A to GROUP_TESTS (after :269, `# 207` comment).
10. Rerun direct → preservation sentinels → named gates (below). Screenshot the running app's inner view (per house mockup-fidelity habit) — optional, non-gating.

## Risks And Edge Cases
- **Concurrent session on orbit_screen.dart/orbit_wired.dart** (observed live during grounding; +10-line drift mid-scan) → re-anchor before diffing; do not revert others' hunks; check for other live claude sessions before starting.
- Pill width is intrinsic/dynamic → dock reserve constant + TC-207-05 widest-state pin; if the pill vocabulary grows, adjust `kIntroDockRightReserve`, never overlap.
- Element remount hazard when inserting a Stack child → keyed Positioned + sentinel TC-211-21/22 must pass unmodified (TC-207-06).
- Unseen key identity drift (folded intros fold multiple introducers into one target) → identity = `intro:<targetPeerId>` exactly matching the fold at `countFoldedPendingIntroductionTargets`; TC-207-12/18 pin.
- Dismissible inside a 40px band vs horizontal feed↔orbit host swipe → set `direction: DismissDirection.up` if horizontal conflicts (decide at impl; TC-207-13 drives whichever gesture ships).
- expireOldIntroductions (30d) shrinking raw while seen-set holds stale keys → TC-207-18 stale-key case.

## Device/Relay Proof Profile
**host-only for closure** — justified: no OS boundary (in-process Flutter chrome; the notification route is untouched), no crypto (counts derive from already-persisted local rows), no relay (seen-set is device-local, never transmitted); persistence durability proven with real SQLCipher on host (TC-207-16/17). PROD-CRITICAL leg: **TC-207-10** (repos → projection → dock → tap → review surface, end-to-end on the wired tier) — do NOT treat the pure-widget rows as sufficient on their own. No `/sims` scenario, no classify_path, no dart-define. Optional non-gating: manual sim screenshot for visual QA.

## Acceptance Gates  (literal — copy/paste)
```bash
# RED (before production edits) — each must FAIL for the documented reason
flutter test test/features/orbit/presentation/screens/orbit_intro_dock_test.dart          # expect: FAILS (no dock)
flutter test test/features/orbit/presentation/widgets/orbit_intro_dock_test.dart           # expect: COMPILE FAIL
flutter test test/core/database/migrations/095_intro_review_seen_test.dart                 # expect: FAILS ×2 (no migration file; version constant still 94)
flutter test test/features/introduction/domain/repositories/intro_review_seen_repository_test.dart        # expect: COMPILE FAIL
flutter test test/features/introduction/application/unseen_review_count_test.dart          # expect: COMPILE FAIL
flutter test test/l10n/orbit_strings_parity_test.dart                                      # expect: FAILS (keys not in ARBs)
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name 'TC-207-19'  # expect: COMPILE/RED

# Direct GREEN (after fix) — expected NEW-test counts are determined by the catalog:
flutter test test/features/orbit/presentation/screens/orbit_intro_dock_test.dart           # expect: 14/14 pass (TC-01/02/03/05/06/07/08/10/11/12/13/14/15 + orbit half of TC-20)
flutter test test/features/orbit/presentation/widgets/orbit_intro_dock_test.dart           # expect: 2/2 pass (TC-04, TC-09)
flutter test test/core/database/migrations/095_intro_review_seen_test.dart                 # expect: 2/2 pass (TC-17, TC-23)
flutter test test/features/introduction/domain/repositories/intro_review_seen_repository_test.dart        # expect: 2/2 pass (reopen persistence; records intro+invite keys)
flutter test test/features/introduction/application/unseen_review_count_test.dart          # expect: 4/4 pass (empty-seen parity; subset; new-key re-inflate; stale keys)
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name 'TC-207'  # expect: 2/2 pass (TC-19 + feed half of TC-20)
flutter test test/l10n/l10n_integrity_test.dart                                            # expect: pass (plural placeholder parity across en/de/ar — NOT in any curated gate, run directly)

# Preservation sentinels (must stay green, UNMODIFIED)
flutter test test/features/orbit/presentation/screens/orbit_connection_indicator_test.dart # 211 pill locks
flutter test test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart   # T3/T4
flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart

# Modified-file direct run (contains the in-slice REWRITE TC-207-22; its other tests are sentinels)
flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart

# Named gates for the touched subsystems (record baseline counts at step 0 on the dirty-211 tree; all green)
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh feed
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_host_test_gates.sh core-host-all      # migration 095

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the seven RED-block commands above, each for its documented reason, before implementation only.
- Pre-existing dirty: uncommitted 211 slice (orbit_screen/orbit_wired/feed_header + 2 new test files) — reported host-green 2026-07-05; re-verify `orbit_connection_indicator_test` green BEFORE starting (if red, 211 regressed independently — stop, do not absorb).
- Environment blocker (NOT product): none expected — host-only plan.
- Scope drift (BLOCKING): any failure in INTRO_TESTS, sculpt suite, or search/212 tests → stop and re-anchor (likely concurrent-session collision, not this slice).

## Done Criteria
- [x] RED added first, failed for the expected reasons (7 RED commands — executor's RED wave + takeover re-confirmation of the l10n/feed reds).
- [x] Mutation-verified (every matrix row names its re-red revert; TC-207-10 viewMode-write revert re-red live; TC-207-05 reserve mutation observed red during impl).
- [x] Direct GREEN + sentinels + groups (1170) / feed (299) green; feature-host-all green modulo the documented pre-existing bg_task red (≠ 207); core-host-all green after the repo-test relocation (completeness 1028/1028).
- [x] Migration 095 has the real-SQLCipher test (TC-207-17).
- [x] Host-only closure justification stands (no new OS/crypto/relay paths added during impl).
- [x] File A appended to GROUP_TESTS and visible in `./scripts/run_test_gates.sh groups` output (ran in-gate, exit 0).
- [x] flutter analyze 0 new (only the numbered-migration file_names info shared by all 147 migration lints); git diff --check clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not modify `onIntroBannerTap`/banner behavior on the all-chats surface, the Intros tab row builders, or `initialFilterTab` routing (193 lock).
- Do not touch accept/pass/decline flows or `pass_introduction_use_case` (dismiss ≠ pass).
- Do not reuse/extend `contacts.intros_banner_dismissed` (C4: wrong keying) or add columns to `contacts`/`pending_group_invites`.
- Do not move/resize the 211 pill, reorder existing Stack children, or mount anything after the FAB.
- Do not modify TC-211-* tests, T3/T4, or any raw-count badge lock — they are sentinels; a red there means the change is wrong.
- Do not add `/sims` scenarios, feature flags, or relay/Go changes.

## Accepted Differences / Intentionally Out Of Scope
- **Execution deviations (recorded at takeover-completion, 2026-07-06):**
  - Wired-host TC-207-10..15/20-orbit live in `orbit_wired_test.dart` (sub-group '207 intro dock (wired)'), NOT in file A — reuses the existing fixture stack (`makePendingInvite` + fakes) instead of duplicating ~200 lines; the file already rides GROUP_TESTS so gate coverage is identical. File A holds the 7 harness-tier tests (01/02/03/05/06/07/08). Per-file counts: A 7, B 2, wired 7, migration 2, repo 2, unit 4, feed 2.
  - `kIntroDockRightReserve` = **206 × ambient textScale** (not the planned 168 constant): TC-207-05 measured the real widest pill ('Online ✦' + debug count, Ahem) at 134px — 64+134+8 = 206 — and no fixed constant survives 1.5× text scale, so the mount scales the reserve; the dock label is `Flexible` (ellipsizes when clamped).
  - TC-207-01 pins `top == 8` (safeTop 0 + 8 in the test env) — the executor's original 32 was wrong.
  - TC-207-12 drives the joined-invite exclusion through the join-event + orphan-re-delivery path (deterministic); mount-time filtering races `_loadGroupData` vs `_loadPendingGroupInvites` by design (B2 filter is event-driven resilience, tolerant of unloaded groups).
  - Dock/remnant a11y: `Semantics(container: true)` + `ExcludeSemantics` so each is ONE clean button node (the Dismissible's drag actions and the facepile/label text stay out of the announced node).
  - Repo test lives at `test/features/introduction/domain/repositories/` (not the planned `data/`): the gate-classification completeness check recognizes no `data/` subdir, and the house pattern for repository tests is `domain/repositories/` (cf. `group_message_repository_impl_test.dart`). Caught by `core-host-all` → completeness now 1028/1028.
- Long-press total-hide + Undo snackbar (mockup ignore-path extras) — follow-up slice once the dock ships; the seen-set store already supports them.
- Option D in-place review tray — future; the dock tap handler is its hook.
- Seen-set garbage collection (stale keys are inert by construction, TC-207-18) — follow-up hygiene.
- List banner staying raw-count (not unseen) — deliberate, locked by TC-207-20.
- Real avatars for group invites — data does not exist pre-join (refute finding); glyph only.
- The `main.dart:579+` onUpgrade dispatch entry for 095 is direct-call-tested only (TC-207-17 calls the migration function; TC-207-23 pins the version constant) — house precedent: no migration dispatch entry is dispatcher-tested (094/intro migration tests all import + call directly).

## Dependency Impact
- 211 (uncommitted) must land or stay stable first — the dock geometry test pins against the pill; sequence 207 AFTER 211 commits.
- Future Option-D tray and notification-deep-link retarget depend on `_onIntroDockTap` + `ORBIT_INTRO_DOCK_TAP` event contract.
- Feed badge consumers (`feed_wired`) now share the seen repo — Move/backup flows that wipe DB get remnant reset for free (documented, untested here).

## Reviewer Findings
Independent sufficiency review (agent a297aa861d2b268ad, read-only, 2026-07-05): initial verdict **DRAFT** — 2 BLOCKING + 3 MINOR; all five applied in-document:
1. BLOCKING — TC-207-17's original mutation ("deregister 095") could not re-red the test (house pattern calls migrations directly, no dispatcher coverage) and the registry edit had no coverage → mutation changed to CREATE-TABLE revert; NEW TC-207-23 pins `currentIdentityDatabaseVersion == 95`; registry files named (`app_database_version.dart:1`, `main.dart:579+`); dispatch closure recorded as justified Accepted Difference.
2. BLOCKING — no expected pass counts in Acceptance Gates → per-file counts pinned for all new/direct tests (14/2/2/2/4/2); wide-gate counts remain step-0 baseline (dirty concurrent-211 tree, deliberate).
3. MINOR — `orbit_view_split_test.dart` was listed under "UNMODIFIED" sentinels while TC-207-22 rewrites one of its tests → moved to its own modified-file block.
4. MINOR — C2 omitted `_openRowNotifier.value = null` → corrected (+ design note that dock tap closes open rows).
5. MINOR — `l10n_integrity_test` runs in no curated gate → added as a direct command.
Anchor spot-check: all cited anchors verified essentially exact on the live tree (±1 line); migrations next-free 095 CONFIRMED; GROUP_TESTS/FEED_TESTS membership CONFIRMED; `onIntroBannerTap` zero-test-coverage CONFIRMED; sibling-surface enumeration of `reviewCount` consumers CONFIRMED complete.

## Arbiter Decision
Structural blockers: none remaining (both blocking findings fixed in-document; verdict after fixes: sufficient). | Deferred details: exact dismiss gesture direction (Dismissible axis) decided at impl, driven by TC-207-13; `kIntroDockRightReserve` exact value pinned by TC-207-05, not by this doc. | Accepted differences: see §Accepted Differences (incl. dispatch-closure direct-call precedent). | Sequencing constraint: execute only after the 211 slice commits (or with explicit coordination) — orbit_screen.dart/orbit_wired.dart are under live concurrent edit; re-anchor all line numbers at step 0.

## Final Execution Verdict
**CLOSED — implemented, host-green, 2026-07-06.** Split execution: gpt-5.5 worker (steps 1–6 + 13 of 24 TCs) was killed mid-flight at user direction (live-collision takeover); this claude session finished steps 7–9, wrote the 11 missing TCs, and fixed two worker defects — the un-wired `onIntroDockTap`/`onIntroDockDismissed` OrbitScreen params (dock rendered, taps no-op'd — TC-207-10 caught it) and the too-small 168 reserve (real widest pill = 134px → reserve 206 × textScale). All 28 direct 207 tests green (A 7, B 2, wired 7, migration 2, repo 2, unit 4, feed 2, +TC-22 rewrite + parity + l10n-integrity); sentinels unmodified green; gates green modulo the documented pre-existing bg_task red. Deviations recorded in §Accepted Differences (test placement, reserve scaling, TC-207-01 top==8, TC-207-12 event-path B2, a11y node fencing, repo-test dir `domain/repositories/`).
