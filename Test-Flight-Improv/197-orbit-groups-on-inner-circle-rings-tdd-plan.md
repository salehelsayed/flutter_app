# 197 - Group chats on the Orbit Inner-Circle rings (interleaved by recency, with image + unread)  (New Feature)

Status: awaiting-review
Spec: free-text intent (no formal spec) — bug report "Group chats do not show up on the Inner Circle under Orbit; their avatar is expected to show up on the orbits with notifications and images." Root cause verified by the 5-investigator debug workflow (2026-07-02).

> Reverses the deliberate friend-only scope of **193** (inner-circle default-view split) and **194** ("Group nodes / group unread — OUT OF SCOPE — inner circle renders 1:1 friends only"). Product decision to include groups was made by the user on 2026-07-02 (placement: **interleave with friends by recency**).

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-02 | Evidence Collector | orbital_visualization.dart, orbit_screen.dart, orbit_wired.dart, orbit_friend/group/item.dart, orbital_avatar.dart, group_model.dart, group_avatar.dart, load_orbit_data_use_case.dart, orbital_visualization_test.dart, orbit_view_split_test.dart, orbit_performance_harness.dart | Root cause = inner circle is structurally friend-only (`List<OrbitFriend>` end-to-end); parts to render groups already exist; recency ordering already solved by `OrbitItem.sortKey`; tap wiring `_onGroupTap` already exists but not threaded into the rings | Build matrix |
| 2026-07-02 | Planner | (this doc) | Reuse production `OrbitItem` union for the rings; merge in one host-tested helper; closure = host widget tier (no device-proof) | Emit RED catalog + gates |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | | reds now green | |
| | preservation GREEN | | | sentinels green | |
| | named gates | | | gate green | |
| | QA (independent) | | | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline (this doc) + user placement decision (interleave-by-recency)
- Gate definitions: `scripts/run_test_gates.sh` and `scripts/run_host_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (197 = next free after 196)

## Session Classification
implementation-ready (host-tier closure; no sim/device required)

## Exact Problem Statement
On the Orbit **Inner Circle** surface (the default view since 193), the orbital rings render **only 1:1 friends**. Group chats — even with unread messages and a group avatar — never appear as satellite nodes. A user who is mostly active in group chats sees an inner circle that omits their most-active conversations; group chats are only reachable by toggling to the all-chats **list** view.

Expected: the rings display **both** 1:1 friends and group chats as avatar nodes, **merged into one most-recent-activity ordering** (both competing for the 13 seats: 5 inner @62px/38px + 8 outer @108px/30px, then the overflow badge for >13). Each group node shows the **real group avatar** (`GroupModel.avatarPath` via `GroupAvatar`, initials fallback) and, when unread, the same **messenger-orbit unread indicator** (194) that friend nodes use. Tapping a group node opens that group's conversation.

What must improve: group chats appear on the inner-circle rings, interleaved by recency, with image + unread badge + tap-to-open.
What must stay unchanged (→ preserved-green sentinels): 1:1 friend nodes render/tap/unread exactly as today; the all-chats list surface (`OrbitViewProjection.mergedItems`) is untouched; friend ring ordering (recency desc) is unchanged; blocked friends stay excluded; the overflow badge geometry is unchanged; 193 view-split + 194 unread-on-friend behavior stays green.

## Root Cause (verify → refute confirmed)
The inner-circle visualization is friend-only through three independent, type-enforced barriers (all survived the adversarial refute pass; git history confirms it was **never** wired and is **not** a regression — inception commit `c90b9fcf`):

1. `lib/features/orbit/presentation/widgets/orbital_visualization.dart:17-37` — `OrbitalVisualization` takes only `friends: List<OrbitFriend>`. Ring nodes built from `friends.take(5)` / `friends.skip(5).take(8)` (L51-52); overflow `friends.length > 13` (L53). Only production instantiation: `orbit_screen.dart:522`.
2. `lib/features/orbit/presentation/screens/orbit_screen.dart:75-85` — `OrbitHeaderProjection` carries only `userPeerId`/`userAvatarBytes`/`allFriends:List<OrbitFriend>`; **no groups field**. Sole consumer is `_buildInnerCircleSurface` (`:508-527`), which passes `projection.allFriends.where(!isBlocked)` to the widget.
3. `lib/features/orbit/presentation/screens/orbit_wired.dart:284-290` — `_buildHeaderProjection` fills `allFriends: _activeFriends` only. Groups (`_activeGroups`, loaded fine at `:626-691`) flow **exclusively** into `OrbitViewProjection.mergedItems` via `OrbitGroupItem` (`:305-323`) — the **list** surface, never the header.

Enabling facts (parts already exist — the gap is data-plumbing, not rendering):
- Image: `GroupModel.avatarPath` (`group_model.dart:72`) + `GroupAvatar` widget (`group_avatar.dart`) — same source used at `group_card.dart:52-57` and `group_conversation_screen.dart:309-315`. Pass `cacheBustKey: group.lastMetadataEventAt`.
- Circular clip: `OrbitalAvatar` `ClipOval`s its `child` (`orbital_avatar.dart:130-136`) → pass `GroupAvatar(borderRadius: BorderRadius.circular(size))` to avoid a doubled/mismatched border.
- Unread: `OrbitGroup.unreadCount` (`orbit_group.dart:13`) → `OrbitalAvatar.unreadCount` (`orbital_avatar.dart:42-43`) → `UnreadOrbitIndicator` (node-type-agnostic, no `peerId`).
- Render seam: `OrbitalAvatar.child` (`orbital_avatar.dart:24-26`) is explicitly documented "render a group glyph instead of the peer photo … (168 C2)". A group node passes `peerId: group.groupId` (placeholder, unused when `child` set) + a `semanticLabel`.
- Ordering already unified: `OrbitItem`/`OrbitFriendItem`/`OrbitGroupItem` with `sortKey` (`orbit_item.dart:8-33`) — friend `lastMessageTimestamp` and group `lastActivityTimestamp.toUtc().toIso8601String()` are both ISO strings; the list already sorts them together (`orbit_wired.dart:307-310`). Friends already arrive recency-desc from `_sortOrbitFriends` (`load_orbit_data_use_case.dart:204-210`).
- Tap wiring already exists: `_onGroupTap(OrbitGroup)` → `_openGroupConversationFromModel(group.group)` (`orbit_wired.dart:2460-2467`), passed to `OrbitScreen.onGroupTap` (`:2313`); currently consumed only by list rows (`orbit_screen.dart:1071`).

Refuted / do-NOT-re-introduce:
- "A merge was dropped / regression" — **false**. `git log -S OrbitGroup -- orbital_visualization.dart` is empty; the "add groups to orbit screen" commit `aec0b5f7` had an empty diff for that file (groups went to the list only). Do not hunt for a lost wire.
- "orbit3 is the reference for image + unread" — **partly false**. orbit3 (`kOrbit3PrototypeEnabled = kDebugMode`, mock-data, no real friends/groups) renders groups as a static teal glyph with **no image and no unread**. Reuse only its **merge/render-fork shape**, not its glyph or data path. Do not import orbit2/orbit3 prototype types into production; use the production `OrbitItem` union.
- "OrbitFriend could be synthesized from a group" — **false**. `loadOrbitData` sources contacts only; `OrbitFriend` requires a `ContactModel`.

## Real Scope
In scope:
- Merge helper (host-pure) that produces the inner-circle `List<OrbitItem>` from active friends + active groups, filtering blocked friends, sorted by `sortKey` desc.
- Thread the merged items into the header projection and `OrbitalVisualization`; render a group node (image + unread) and route its tap to `onGroupTap`.
- Overflow badge counts friends+groups combined.
- Update the four friend-only tests + add new coverage; extend the perf harness with a mixed friends+groups scenario.
- If a group-specific a11y string is needed, add `orbit_node_open_group` / `orbit_node_unread_open_group` l10n keys (en/ar/de) and regenerate.

Out of scope (owning work named):
- Search "inner circle badge" semantics for groups (`orbit_screen.dart:1023` `projection.allFriends.indexOf(friend) < 13`) — that is the **list/search** surface, friend-only; see Accepted Differences. A follow-up (call it 198) owns extending it if desired.
- Any change to group loading, group avatar download, or the all-chats list ordering.
- Group creation/QR/entry-point work (196 owns Orbit entry points).
- Curated group-messaging E2E/device gates — this feature has no transport/crypto/OS leg.

## Files To Inspect Next
Production (entry/use-case, models, helpers):
- `lib/features/orbit/domain/models/orbit_item.dart` (reuse union + `sortKey`)
- `lib/features/orbit/domain/models/orbit_group.dart`, `orbit_friend.dart`
- NEW `lib/features/orbit/application/inner_circle_items.dart` (merge helper) — or a static on `OrbitItem`
- `lib/features/orbit/presentation/screens/orbit_screen.dart` (`OrbitHeaderProjection` 75-85; `_buildInnerCircleSurface` 507-559)
- `lib/features/orbit/presentation/screens/orbit_wired.dart` (`_buildHeaderProjection` 284-290; `_onGroupTap` 2460-2467)
- `lib/features/orbit/presentation/widgets/orbital_visualization.dart`, `orbital_avatar.dart`
- `lib/features/groups/presentation/widgets/group_avatar.dart`
Direct tests + harness:
- `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`
- `test/features/orbit/presentation/screens/orbit_view_split_test.dart`
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
- `test/features/orbit/application/` (new merge-helper test lands here)
- `integration_test/orbit_performance_harness.dart`
Dependency-only context: `group_card.dart`, `group_conversation_screen.dart` (GroupAvatar call shape).

## Existing Tests Covering This Area
- `orbital_visualization_test.dart` — friend-only ring counts/taps (exact `OrbitalAvatar` counts = friend count; tap returns `OrbitFriend`). MUST extend (mixed counts, group render/tap/unread/overflow).
- `orbit_view_split_test.dart:258-292` — inner-circle default surface seeds a group and asserts `GroupRow findsNothing`; `:294-321` all-chats view. MUST update intent: group now renders as a ring node (not a `GroupRow`).
- `orbit_screen_loading_test.dart:108-116` — header builder groups-absent. MUST update to feed groups to header.
- `orbit_performance_harness.dart:169-174` — `OrbitHeaderProjection(allFriends: friends)` no groups. MUST extend one scenario.
- `load_orbit_data_use_case_test.dart`, `load_orbit_groups_use_case_test.dart` — unaffected (preserve green).
Missing coverage gaps: interleave-by-recency ordering; group image render + fallback; group unread overlay; group tap→open; combined overflow; archived-group exclusion.
Already in curated family arrays?: No — orbit host/widget tests are **AUTO-globbed** under `feature-host-all`; none are hardcoded in `run_test_gates.sh` family arrays. The perf harness is registered in `check_reliability_simulation_discovery.sh`.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/features/orbit/application/inner_circle_items_test.dart`::`interleaves friends and groups by recency (most-recent first)`
   - Tier: unit/application
   - Shape/setup: build 3 `OrbitFriend` + 2 `OrbitGroup` with known `lastMessageTimestamp` / `lastActivityTimestamp`; call `mergeInnerCircleItems(friends:…, groups:…)`; assert returned `List<OrbitItem>` order matches recency-desc by `sortKey`, with a group correctly interleaved between friends.
   - RED on HEAD because: `mergeInnerCircleItems` / `inner_circle_items.dart` does not exist (compile-fail).
   - GREEN after fix asserts: exact interleaved order; group at the expected index.
   - Mutation that re-reds: change the comparator to `a.sortKey.compareTo(b.sortKey)` (asc) → order flips → red.

2. `test/features/orbit/application/inner_circle_items_test.dart`::`excludes blocked friends and keeps active groups`
   - Tier: unit/application
   - Shape/setup: friends incl. one `isBlocked`; assert blocked friend absent, others + groups present.
   - RED on HEAD because: helper absent.
   - GREEN asserts: blocked friend filtered; count = unblocked friends + groups.
   - Mutation: remove the `where(!isBlocked)` filter → blocked friend reappears → red.

3. `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`::`renders a group node with GroupAvatar on the ring`
   - Tier: widget
   - Shape/setup: feed the widget merged items = 2 friends + 1 group (`avatarPath` set); pump; assert `find.byType(GroupAvatar)` findsOneWidget inside the ring Stack AND total `OrbitalAvatar` count == 3 (2 friend + 1 group node).
   - RED on HEAD because: widget takes only `friends: List<OrbitFriend>`; no group input, `GroupAvatar` never built (compile-fail once the test passes `items:`/`groups:`).
   - GREEN asserts: group node present; friend nodes intact; combined count exact.
   - Mutation: in the widget's per-item fork, skip group items → GroupAvatar findsNothing → red.

4. `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`::`group node with unread overlays UnreadOrbitIndicator`
   - Tier: widget
   - Shape/setup: one group item with `unreadCount: 3`; assert `find.byType(UnreadOrbitIndicator)` present on the group node; a zero-unread group asserts none.
   - RED on HEAD because: no group path exists to pass `unreadCount`.
   - GREEN asserts: indicator present iff unread>0.
   - Mutation: hardcode group `unreadCount: 0` in the fork → indicator gone → red.

5. `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`::`group node falls back to initials when avatarPath is null`
   - Tier: widget
   - Shape/setup: group with `avatarPath: null`, `name: 'Alpha Group'`; assert `GroupAvatar` renders its initials fallback (`find.text('AG')` or the fallback key), not an Image.file.
   - RED on HEAD because: no group node rendered.
   - GREEN asserts: fallback initials shown.
   - Mutation: pass empty `name` → fallback text changes → red (guards name plumbing).

6. `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`::`tapping a group node invokes onGroupTap with that group`
   - Tier: widget
   - Shape/setup: capture `onGroupTap`; tap the group node's 48px target; assert callback fired with the seeded `OrbitGroup` (by `groupId`); tapping a friend still fires `onFriendTap` with the `OrbitFriend`.
   - RED on HEAD because: widget has no `onGroupTap` param / no group tap target.
   - GREEN asserts: `tappedGroup.groupId == 'g-1'`; friend tap path unbroken.
   - Mutation: wire the group node's `onTap` to `onFriendTap` → group callback never fires → red.

7. `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`::`overflow badge counts friends and groups combined`
   - Tier: widget
   - Shape/setup: 12 friends + 3 groups (15 total); assert `OverflowBadge` shows `2` (15 − 13) and exactly 13 nodes seated.
   - RED on HEAD because: `overflowCount = friends.length > 13 ? …` counts friends only → with 12 friends shows no overflow.
   - GREEN asserts: overflow == 2; 13 seated.
   - Mutation: revert overflow to `friends.length` → badge wrong/absent → red.

8. `test/features/orbit/presentation/screens/orbit_view_split_test.dart`::`inner-circle default surface shows a seeded group as a ring node (not a list row)`
   - Tier: widget (screen wiring — projection → surface → visualization)
   - Shape/setup: seed friend + `seedGroup('g-1','Alpha Group')` (reuse existing helper at ~L267); enter default inner-circle view; assert `OrbitalVisualization findsOneWidget`, a `GroupAvatar` for `g-1` **is present on the rings**, AND `GroupRow findsNothing` (still not a list row on the inner surface).
   - RED on HEAD because: current test asserts the group is absent from the inner surface; header projection carries no groups so no group node renders (flip the existing assertion).
   - GREEN asserts: group ring node present; no `GroupRow`; all-chats list assertions (`:294-321`) unchanged.
   - Mutation: revert `_buildHeaderProjection` to `allFriends`-only (drop groups) → group ring node gone → red. **This is the PROD-CRITICAL wiring test** (proves `orbit_wired → OrbitHeaderProjection → _buildInnerCircleSurface → OrbitalVisualization`).

9. `test/features/orbit/presentation/screens/orbit_view_split_test.dart`::`archived group is not shown on the inner circle`
   - Tier: widget (screen wiring)
   - Shape/setup: seed one active + one archived group; assert only the active group's node appears on the rings.
   - RED on HEAD because: no group nodes at all today (once wiring lands, guards that the header feed uses active groups only).
   - GREEN asserts: archived group absent; active present.
   - Mutation: feed `_archivedGroups` into the merge → archived node appears → red.

10. `integration_test/orbit_performance_harness.dart` (scenario extension) + its perf assertion
    - Tier: integration (widget perf harness; host, no real bridge)
    - Shape/setup: add a mixed `friends + groups` inner-circle scenario (e.g. 8 friends + 5 groups) feeding `OrbitHeaderProjection(groups:/innerItems:)`; keep the existing frame-budget assertion.
    - RED on HEAD because: harness builds `OrbitHeaderProjection(allFriends: friends)` with no groups field → compile-fail once it passes groups.
    - GREEN asserts: mixed scenario builds and meets the existing frame budget (guards Image.file group avatars don't blow the ring's paint budget).
    - Mutation: n/a for perf (guardrail row) — non-blocking for closure; see Device/Relay Proof Profile.

## Test Coverage Matrix  (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-197-01 interleave-by-recency | pure logic (comparator/merge) | unit/application | inner_circle_items_test::interleaves…by recency | helper absent (compile-fail) | comparator→asc flips order | `flutter test test/features/orbit/application/inner_circle_items_test.dart` | AUTO (glob `test/features/**`) |
| TC-197-02 exclude blocked / active-only | pure logic (filter) | unit/application | inner_circle_items_test::excludes blocked friends… | helper absent | drop `!isBlocked` → blocked reappears | same as TC-01 | AUTO (glob) |
| TC-197-03 group image on ring | UI render fork | widget | orbital_visualization_test::renders a group node with GroupAvatar | widget friend-only, no GroupAvatar | skip group items → GroupAvatar gone | `flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart` | AUTO (glob) |
| TC-197-04 group unread overlay | UI conditional | widget | orbital_visualization_test::group node…UnreadOrbitIndicator | no group path passes unreadCount | force group unread 0 → indicator gone | same as TC-03 | AUTO (glob) |
| TC-197-05 initials fallback | UI fallback | widget | orbital_visualization_test::…falls back to initials | no group node rendered | empty name → fallback text changes | same as TC-03 | AUTO (glob) |
| TC-197-06 group tap→open | UI gesture routing | widget | orbital_visualization_test::tapping a group node invokes onGroupTap | widget has no onGroupTap | route group onTap→onFriendTap → no fire | same as TC-03 | AUTO (glob) |
| TC-197-07 combined overflow | UI count math | widget | orbital_visualization_test::overflow badge counts friends and groups | overflow uses friends.length | revert to friends.length → wrong badge | same as TC-03 | AUTO (glob) |
| TC-197-08 wired header→rings (PROD-CRITICAL) | screen wiring | widget | orbit_view_split_test::inner-circle default surface shows a seeded group as a ring node | header carries no groups; test asserts absent | revert `_buildHeaderProjection` to friends-only → node gone | `flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart` | AUTO (glob) |
| TC-197-09 archived excluded | screen wiring / filter | widget | orbit_view_split_test::archived group is not shown on the inner circle | no group nodes today | feed `_archivedGroups` → archived appears | same as TC-08 | AUTO (glob) |
| TC-197-10 mixed perf guardrail | render perf | integration (widget harness) | orbit_performance_harness (mixed friends+groups scenario) | harness header has no groups field (compile-fail) | n/a (perf guardrail) | `flutter test integration_test/orbit_performance_harness.dart` | register scenario in `check_reliability_simulation_discovery.sh` `classify_path()` if it gates via `/sims`; else AUTO under integration_test perf run — **verify in discovery run** |
| TC-197-11 loading-test header carries groups | wiring regression | widget | orbit_screen_loading_test (updated header builder) | builder feeds `allFriends` only | drop groups from builder → group assertion red | `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` | AUTO (glob) |

## Blind-Spot Sweep  (evergreen classes)
- **Lifecycle / derived-state durability:** N/A — no new persisted/derived latch. Group membership on the rings is recomputed each build from `_activeGroups` (already reloaded on entry via `_loadGroupData` + the `_replayDirtyOrbitWork` group path, `orbit_wired.dart:515-521`). The 193 view-reset on Feed→Orbit rising edge is unchanged. **Guarded indirectly** by TC-197-08 (fresh build renders the group node from the projection).
- **Sibling-surface consistency:** The change adds groups to the **rings** surface. Parallel surface = the all-chats **list**, which already shows groups (`mergedItems`) — no asymmetry introduced. The one genuine asymmetry: the search "inner circle badge" (`orbit_screen.dart:1023`, friend-only `indexOf`) does **not** account for group ring seats. This is a **deliberate, documented Accepted Difference** (below), owned by a follow-up; not test-locked here because it is an existing list/search cosmetic outside this feature's surface.
- **Destructive-action side-effects:** N/A — no delete/cleanup/cancel path added or changed.
- **Invariant re-verification under new transitions:** No new state transition. Existing transitions (blocked/archive) re-verified: TC-197-02 (blocked friend excluded), TC-197-09 (archived group excluded) assert the post-condition on the merged ring set.

## Invariants (locked by tests)
- INV-1: inner-circle ring order == recency-desc by `OrbitItem.sortKey`, friends and groups interleaved → TC-197-01.
- INV-2: blocked friends never seated; archived groups never seated → TC-197-02, TC-197-09.
- INV-3: a group node renders its `GroupAvatar` (image or initials) and its unread indicator iff `unreadCount>0` → TC-197-03/04/05.
- INV-4: a group node tap opens the group conversation (routes to `onGroupTap`), friend tap unchanged → TC-197-06.
- INV-5: overflow counts friends+groups combined; exactly 13 seated → TC-197-07.
- INV-6: the wired path `orbit_wired → OrbitHeaderProjection → _buildInnerCircleSurface → OrbitalVisualization` actually delivers a seeded group to the rings → TC-197-08 (PROD-CRITICAL).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **Snapshot dirty tree:** `git status --short` (record — the tree already has unrelated M/D files from the branch; do not revert them).
2. **RED first:** add TC-197-01..09 + the updated assertions in TC-197-08/11; run the focused gates below; confirm each fails **for its documented reason** (compile-fail for the helper/widget-API rows; assertion-flip for the screen rows).
3. **Merge helper (seam):** add `lib/features/orbit/application/inner_circle_items.dart` — `List<OrbitItem> mergeInnerCircleItems({required List<OrbitFriend> friends, required List<OrbitGroup> groups})`: map friends→`OrbitFriendItem`, groups→`OrbitGroupItem`, drop `friend.isBlocked`, `..sort((a,b)=>b.sortKey.compareTo(a.sortKey))`. (Reuse `OrbitItem`; do NOT import orbit2/orbit3 types.) → GREEN TC-01/02.
4. **Header projection (seam):** in `orbit_screen.dart` add `final List<OrbitItem> innerItems;` to `OrbitHeaderProjection` (default `const []`); in `orbit_wired.dart` `_buildHeaderProjection`, set `innerItems: mergeInnerCircleItems(friends: _activeFriends, groups: _activeGroups)`. (Keep `allFriends` field for compatibility, or remove after confirming its sole consumer is the surface.)
5. **Visualization (seam):** change `OrbitalVisualization` to accept `List<OrbitItem> items` + `onGroupTap` alongside `onFriendTap`. Replace `ring1/ring2` slicing over `friends` with slicing over `items`; per item, `switch`: `OrbitFriendItem`→existing `OrbitalAvatar(peerId: friend.peerId, unreadCount: friend.unreadCount, onTap: onFriendTap)`; `OrbitGroupItem`→`OrbitalAvatar(peerId: g.groupId, child: GroupAvatar(groupId: g.groupId, name: g.name, avatarPath: g.group.avatarPath, cacheBustKey: g.group.lastMetadataEventAt?.toIso8601String(), borderRadius: BorderRadius.circular(size)), unreadCount: g.unreadCount, unreadMotionEnabled: …, onTap: () => onGroupTap(g), semanticLabel: …)`. Overflow uses `items.length`. → GREEN TC-03..07.
6. **Surface wiring (seam):** in `_buildInnerCircleSurface` pass `items: projection.innerItems` + `onGroupTap: onGroupTap` (already a widget field, `orbit_screen.dart:205`); empty-hint condition becomes `projection.innerItems.isEmpty`. → GREEN TC-08/09/11.
7. **a11y (if needed):** add `orbit_node_open_group` / `orbit_node_unread_open_group` to `app_en/ar/de.arb`; `flutter gen-l10n`. (Stop-if: cannot reuse an existing string cleanly → add the keys; do not ship an English literal.)
8. **Perf harness:** extend one scenario with mixed friends+groups feeding the new header field. → GREEN TC-10.
9. Rerun direct → preservation → named gates (below). **Stop-if:** any orbit host test outside this feature's assertions goes red for a non-obvious reason → replan, do not force-edit the test.
10. `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (app-owned `lib/` changed).

## Risks And Edge Cases
- **Timestamp format skew across types** (friend `lastMessageTimestamp` raw string vs group `toUtc().toIso8601String()`): the all-chats list already relies on this comparison, so the rings inherit shipped behavior; **pinned** by TC-197-01 with explicit known timestamps. If the interleave order surprises, fix the `sortKey` normalization in `OrbitItem`, not in the widget.
- **ClipOval double-border on GroupAvatar**: pass `borderRadius: BorderRadius.circular(size)`; visually verify via `/run` after host green (screenshot the inner circle).
- **Required non-null `peerId` on a group node**: pass `group.groupId`; it is unused for rendering when `child` is set (`orbital_avatar.dart:131`) but must be non-null — do not pass `''` (breaks the entrance-key/semantics); use the real groupId.
- **13-seat contention**: with many groups, friends can be pushed to overflow. This is the intended "interleave by recency" behavior (user-chosen); TC-197-07 locks the combined cap.

## Device/Relay Proof Profile
host-only for closure. This is a pure presentation change (projection + widget); no OS callback, no crypto/ML-KEM convergence, no relay custody, no multi-device. **No device-proof or `/sims` scenario is required for closure.** TC-197-10 (perf harness) is a guardrail, not a closure gate. Recommended manual confirmation after host-green: `/run` the app and screenshot the inner circle with ≥1 group present (image + unread visible).
Deferred device work: none.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# 0. Dirty-tree snapshot (do NOT revert unrelated branch changes)
git status --short

# 1. RED (BEFORE production edits) — each must FAIL for its documented reason
flutter test test/features/orbit/application/inner_circle_items_test.dart          # compile-fail: helper absent
flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart --plain-name 'renders a group node'   # fails: no group input
flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart --plain-name 'ring node'                    # fails: group absent from rings

# 2. Direct GREEN (after fix)
flutter test test/features/orbit/application/inner_circle_items_test.dart
flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart
flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart
flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart

# 3. Preservation sentinels (must stay green) — all orbit host/widget tests + 194 unread
./scripts/run_host_test_gates.sh feature-host-all        # expect: full suite pass (record baseline count first)

# 4. Perf harness (guardrail)
flutter test integration_test/orbit_performance_harness.dart

# 5. Discovery (only if TC-10 registers a /sims scenario)
./scripts/check_reliability_simulation_discovery.sh      # confirm the mixed scenario lists (or confirm no new registration needed)

# 6. Hygiene
flutter analyze            # 0 new issues
git diff --check
```
Expected-count note: capture the `feature-host-all` baseline pass count on HEAD **before** step 1 so step 3 can prove +N added, 0 regressed.

## Known-Failure Interpretation
- Expected RED: TC-197-01..09 + updated 08/11 before the fix.
- Pre-existing dirty: the branch tree already carries unrelated M/D files (orbit2 deletions, l10n, graphify-out) — leave them; they are not this feature.
- Environment blocker (NOT product): none — host-only feature; no sim/device needed.
- Scope drift (BLOCKING): any red in `run_host_test_gates.sh feature-host-all` outside the orbit inner-circle assertions, or any change to the all-chats list ordering / group loading.

## Done Criteria
- [ ] RED added first, failed for the expected reason (compile-fail for helper/widget-API; assertion-flip for screen).
- [ ] Mutation-verified (each fix has a re-red revert per the matrix).
- [ ] Direct GREEN + `feature-host-all` preservation + perf harness pass.
- [ ] No migration (no schema change) — N/A row confirmed.
- [ ] No OS-boundary/multi-device path — closure is host-tier (documented).
- [ ] Every new test is AUTO-globbed and shows up in `feature-host-all`; perf scenario verified in discovery (or confirmed AUTO).
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.
- [ ] `graphify update .` + `refresh_arch_graph.sh` run after code changes.

## Scope Guard (hard "Do not")
- Do not import `lib/features/orbit2/**` or `lib/features/orbit3/**` types into production orbit code (they are debug/mock prototypes).
- Do not change the all-chats list surface (`OrbitViewProjection.mergedItems`), group loading (`_loadGroupData`/`loadOrbitGroups`), or friend ring recency ordering.
- Do not add a device-proof / `/sims` gate — this feature has no transport/crypto/OS leg.
- Do not extend the search "inner circle badge" (`orbit_screen.dart:1023`) here — Accepted Difference / follow-up owns it.

## Accepted Differences / Intentionally Out Of Scope
- **Search "inner circle badge" for groups** (`orbit_screen.dart:1023` `projection.allFriends.indexOf(friend) < 13`): stays friend-only. Once groups occupy ring seats, this list/search cosmetic no longer mirrors ring membership exactly. Deliberately deferred — a follow-up (198) owns extending "inner circle" membership to the merged set if the product wants the badge to track group seats.
- **orbit3/orbit2 prototypes**: unchanged; they keep their static-glyph mock rendering. This feature does not unify production and prototype.

## Dependency Impact
- None depends on this contract. It consumes existing `OrbitItem`, `OrbitGroup`, `GroupAvatar`, `_onGroupTap` — all already shipped. The new `mergeInnerCircleItems` helper is additive.

## Reviewer Findings
(pending sufficiency review)

## Arbiter Decision
(pending)

## Final Execution Verdict
(pending execution)
