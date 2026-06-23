# 151 - Removed/dissolved-while-viewing: rely on the persistent read-only banner; scope the snackbar to hard-delete only  (Bug | Feature Improvement)

Status: awaiting-review
Spec: free-text intent (no formal spec) — chained from a UI/UX review of Group Messaging snackbars

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | group_conversation_wired.dart (`_handleCurrentGroupRemoved` 1492-1519, `_startListening` removed/dissolve subs 1400-1445, `_canWriteForGroup` 4234-4252, `_readOnlyBannerText` 4254-4279, `_canWrite` 4497-4499, members.isEmpty short-circuit 1186-1189, `_terminalSendReadOnly` set-sites), group_conversation_screen.dart (`_buildReadOnlyBanner` 925-950, `!canWrite` gate 250-252), app_en/ar/de.arb (`group_removed_snackbar`, `group_read_only_*`), group_conversation_wired_test.dart (hard-delete pop test 6869-6929, B5 retain test 5875-5912, NW-007 snackbar-absent 3227/3252), run_test_gates.sh (GROUP_TESTS 130-131) | verify→refute complete: passive-removal RETAINED path fires an UNCONDITIONAL snackbar (`:1498`) that is REDUNDANT with the durable composer read-only banner (`group_read_only_not_active`); the snackbar is LOAD-BEARING only on the hard-delete/POP branch (no banner surface survives the pop). 144 is ALREADY IMPLEMENTED in-tree (the `_TerminalReadOnly` machinery exists) — this unit is independent of 144's send-path latch. NO migration, NO l10n, NO new banner. | Planner |
| 2026-06-23 | Planner | (as above) | Seam = hoist `getGroup` BEFORE the snackbar in `_handleCurrentGroupRemoved` so the snackbar fires ONLY in the POP (hard-delete) branch and is SUPPRESSED on the RETAINED branch (read-only banner carries the feedback). Keep `hideCurrentSnackBar` semantics. | Reviewer |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

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
- Spec / intent: inline below (UX review of Group Messaging snackbars → user-locked decision: do NOT add a top banner; rely on the EXISTING composer read-only banner; scope the snackbar to the truly-deleted case).
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose). `group_conversation_wired_test.dart` is ALREADY in `GROUP_TESTS` (`:131`); `group_conversation_screen_test.dart` is at `:130`.
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no sim/device rows in this plan).
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (this file = 151).

## Session Classification
implementation-ready (host-only closure; no migration, no l10n, no device-proof — pure presentation/branch-restructure)

## Exact Problem Statement
When a member is **passively removed** from a group **while they are viewing the conversation** and the group **row is retained** (the B3 "read-only shell"), `GroupConversationWired._handleCurrentGroupRemoved` (`group_conversation_wired.dart:1492-1519`) fires an **unconditional ~4s floating snackbar** ("You were removed from this group.", `app_en.arb:492` `group_removed_snackbar`, shown at `:1498-1503`) **and then** refreshes the group/messages/security gates (`:1511-1516`) so the **composer read-only banner** (`group_read_only_not_active`, `app_en.arb:870`) appears. The result is **double feedback**: a transient toast AND a durable banner that says the same thing. The banner is the correct, persistent surface; the snackbar is redundant noise on the retained path, and if it is missed (scrolled/backgrounded) it adds nothing the banner does not already carry.

The snackbar is **load-bearing only on the hard-delete branch**: when the group row is truly gone (`getGroup` returns `null`, `:1509`), the screen **pops** to the first route (`:1518`) and there is **no composer banner surface left** — the snackbar is the only feedback the user gets that the group disappeared. The existing test `group_conversation_wired_test.dart:6869` ("current group removal shows a notice and exits the conversation route") asserts exactly this at `:6925-6928` (`GroupConversationScreen` findsNothing + `find.text('You were removed from this group.')` findsOneWidget + tracker not viewing).

Separately, the **passive dissolve-while-viewing** path is **already banner-only** (no snackbar today): a `sys-group_dissolved:` message on the message stream triggers `_refreshVisibleGroup` (`group_conversation_wired.dart:1407-1411`), which flips the composer to the `group_read_only_dissolved` banner with no toast. That path is correct but **uncovered by tests** — an optional wiring-lock is included (TC-04).

What must improve:
- The **retained passive-removal** path shows **only** the durable composer read-only banner (`group_read_only_not_active`) — **no** redundant `group_removed_snackbar`.
- The **hard-delete (POP)** path keeps the snackbar (the only feedback after the route pops).

What must stay unchanged (→ preserved-green sentinels):
- Hard-delete pop + snackbar (`group_conversation_wired_test.dart:6869` `:6921-6928`) — LOAD-BEARING; the snackbar MUST still fire on the POP branch.
- B5 retain test (`:5875-5912`) — stays on the conversation, composer flips to the `group_read_only_not_active` banner, `TextField` findsNothing. It is currently SILENT on the snackbar (no `findsNothing`/`findsOneWidget` assertion on it); it stays green after the fix.
- The passive dissolve banner-only path (`:1407-1411`) — unchanged behavior; only newly locked.
- NW-007 zero-peers tests (`:3227`/`:3252`) — keep the group active, never trigger `removedStream`, already assert the removed snackbar `findsNothing`; stay green.
- 144's send-path terminal `_TerminalReadOnly` latch + its tests (the in-tree send-failed bubble work; `:5855-5872`, `:5875-5912`, INV-5 SnackBar `findsNothing`). NOT touched by this unit.

## Root Cause (verify → refute confirmed)
**Confirmed on HEAD (in-tree, `new-feed` dirty but this method is committed/stable):**
- `group_conversation_wired.dart:1492-1519` `_handleCurrentGroupRemoved` runs in **fixed order**: `clearIfActive` (`:1495`), `hideCurrentSnackBar` (`:1497`), **then the snackbar UNCONDITIONALLY** (`:1498-1503`), and **only after that** reads `getGroup` (`:1509`) to branch RETAINED (`:1511-1516`, refresh in place) vs POP (`:1518`, hard-delete). Because the snackbar is shown **before** the branch decision, it fires on **both** outcomes — including the retained path where the refreshed composer read-only banner (`group_read_only_not_active` via `_canWriteForGroup` returning false for a non-active member, `:4234-4252` + `_readOnlyBannerText` `:4254-4279`) already provides durable feedback.
- The retained-path banner is driven purely by the **membership refresh** (`_loadSecurityStatus` at `:1514` → `_isCurrentUserActiveMember=false` → `_canWriteForGroup` false at `:4238-4240` → `!canWrite` renders `_buildReadOnlyBanner`, `group_conversation_screen.dart:250-252`/`925-950`). `_handleCurrentGroupRemoved` does **NOT** set the `_terminalSendReadOnly` override (verified: that field is set only at send/reaction sites `:4701/:4704/:4772/:4775/:4804`, reset at `:690/:4351/:4355` — none inside `_handleCurrentGroupRemoved`). So the banner is already independent of 144's machinery.
- `_emitGroupRemoved` (the producer of `groupRemovedStream`) fires ONLY for **self-removal** (`group_message_listener.dart:3514`, retained shell) and **self-ban** (`:3981`). Empty-membership / admin dissolve does NOT use `groupRemovedStream` — it rides the message stream (`sys-group_dissolved:`) → `_refreshVisibleGroup` (`:1407-1411`), already banner-only/snackbar-free.

Refuted / do-NOT-re-introduce:
- ❌ "the fix is a new top `MaterialBanner`" — **REJECTED by the UX review**. A top banner would DOUBLE the existing composer read-only banner. Do NOT add one.
- ❌ "blanket-remove the `_handleCurrentGroupRemoved` snackbar" — **WRONG**; the snackbar is load-bearing on the POP/hard-delete branch (`:6921-6928` asserts it). A blanket delete reds that test.
- ❌ "the empty-membership/dissolve path also needs a snackbar fix here" — **FALSE**; dissolve is already banner-only via `:1407-1411` (no snackbar). The only snackbar-redundancy is the retained passive-removal path.
- ❌ "removing a member auto-flips read-only via membership" — TRUE here only because `saveActiveGroupMembers` keeps OTHER members (peer-bob) so `members.isEmpty` is false (`:1186-1189`). If the test left the group empty, the active-member check would **fail open** (`members.isEmpty → active=true`) and the banner would NOT appear. The RED retain test MUST keep OTHER members (matches the existing B5 setup `:5897`, `removeMember(group.id, testIdentity.peerId)` leaving peer-bob).
- ❌ "needs a migration / l10n key" — **FALSE**; pure presentation; reuses the EXISTING `group_removed_snackbar` (`:492`) and `group_read_only_not_active` (`:870`). DB stays v92; no new keys.

## Real Scope
In scope:
- **Restructure `_handleCurrentGroupRemoved` (`group_conversation_wired.dart:1492-1519`)**: hoist the `getGroup` read (`:1509`) **above** the snackbar (`:1498-1503`) so the snackbar is shown **only** in the POP/hard-delete branch (`retainedGroup == null`). On the RETAINED branch (`retainedGroup != null`), **do not** show the snackbar; keep the in-place refresh (`_refreshVisibleGroup`/`_loadMessages`/`_loadSecurityStatus`, `:1512-1514`) which drives the durable read-only banner. Keep `clearIfActive` (`:1495`) and `hideCurrentSnackBar` (`:1497`) as-is (clearing any stale snackbar is intentional and harmless on both branches).
- **Optional wiring-lock only** for the already-correct passive-dissolve path (`:1407-1411`) — a test that locks "dissolve-while-viewing flips the read-only banner with NO snackbar" (no production change; closes a coverage gap).

Out of scope (owning work named):
- 144's send-path terminal `send_failed` bubble + `_TerminalReadOnly` latch + reaction parity (already in-tree; this unit does not touch the send/reaction branches or that latch). Owner: 144.
- Any new banner widget, l10n key, DB migration, or 1:1 conversation parity.
- Changing the snackbar copy/behavior on the POP branch (kept byte-identical).

## Files To Inspect Next
Production:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — `_handleCurrentGroupRemoved` `:1492-1519` (the seam: snackbar `:1498-1503`, `getGroup` `:1509`, retained branch `:1511-1516`, POP `:1518`); removed-stream sub `:1438-1444`; dissolve refresh `:1407-1411`; `_canWriteForGroup` `:4234-4252`; `_readOnlyBannerText` `:4254-4279`; `_canWrite` `:4497-4499`; members.isEmpty short-circuit `:1186-1189`.
- `lib/features/groups/presentation/screens/group_conversation_screen.dart` — `!canWrite` → `_buildReadOnlyBanner` gate `:250-252`; banner builder `:925-950` (key `ValueKey('group-read-only-banner')`); ctor params `canWrite` `:48`, `readOnlyBannerText` `:107`.
Direct tests:
- `test/features/groups/presentation/group_conversation_wired_test.dart` — hard-delete pop+snackbar `:6869-6929` (`:6921-6928` load-bearing, KEEP green); B5 retain `:5875-5912` (KEEP green); NW-007 snackbar-absent `:3227`/`:3252`; helpers `makeChatGroup` `:730`, `saveActiveGroupMembers` `:753`, `buildWidget` `:977` (`removedStreamController:` param `:997`).
Dependency-only context (not edited):
- `lib/features/groups/application/group_message_listener.dart` — `_emitGroupRemoved` producers `:3514` (self-removal) / `:3981` (self-ban).
- `lib/l10n/app_en.arb`/`app_ar.arb`/`app_de.arb` — REUSED keys only (`group_removed_snackbar` `:492`, `group_read_only_not_active` `:870`/ar `:863`/de `:863`).

## Existing Tests Covering This Area
- `group_conversation_wired_test.dart:6869` "current group removal shows a notice and exits the conversation route" — hard-delete: `deleteGroup` + `removedStream.add` → `GroupConversationScreen` findsNothing (`:6925`) + `find.text('You were removed from this group.')` findsOneWidget (`:6927`) + tracker not viewing (`:6928`). PASSES on HEAD. **LOAD-BEARING preservation sentinel — the snackbar MUST stay on the POP branch.**
- `group_conversation_wired_test.dart:5875` "B5 self member_removed while viewing keeps the conversation open read-only in place (no pop) when the group row is retained" — `removeMember(group.id, testIdentity.peerId)` (peer-bob retained) + `removedStream.add` → screen stays (`:5903`), `TextField` findsNothing (`:5904`), banner text `group_read_only_not_active` findsOneWidget (`:5905-5910`). PASSES on HEAD. **SILENT on the snackbar today** (no assertion) → stays green after the fix; my NEW RED adds the explicit `findsNothing` for the snackbar on this exact setup.
- `group_conversation_wired_test.dart:3227`/`:3252` (NW-007 zero-peers) — keep group active, never trigger `removedStream`; already assert removed snackbar `findsNothing`. PASS, unaffected.
- Passive **dissolve-while-viewing** banner flip (`:1407-1411`): **NO test** (coverage gap) → TC-04 optional wiring-lock.

Missing coverage gaps: (1) retained passive-removal must NOT show the snackbar (the redundancy this unit removes); (2) passive dissolve banner-only is uncovered.

Already in curated family arrays?: `group_conversation_wired_test.dart` ✅ in `GROUP_TESTS` (`scripts/run_test_gates.sh:131`). **No new registration needed.** `group_conversation_screen_test.dart` is at `:130` (not touched).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `group_conversation_wired_test.dart`::"retained self-removal shows the read-only banner and NO removed snackbar"
   - Tier: integration/widget (wired screen; fakes + in-memory repo, exactly the B5 setup)
   - Shape/setup: `makeChatGroup` + `saveActiveGroupMembers(groupRepo, group)` (self **and** peer-bob, so `members.isEmpty` is false); `buildWidget(group:, removedStreamController:)`; pump 20 frames; `removeMember(group.id, testIdentity.peerId)` (peer-bob retained → row retained); `removedStreamController.add(group.id)`; pump 20 frames.
   - RED on HEAD because: `_handleCurrentGroupRemoved` shows the snackbar **unconditionally** at `:1498` (before the `getGroup` retained/POP branch), so on the retained path `find.text('You were removed from this group.')` is **present** — asserting it `findsNothing` FAILS on HEAD.
   - GREEN after fix asserts: screen still present (`find.byType(GroupConversationScreen)` findsOneWidget); composer flipped read-only (`find.byType(TextField)` findsNothing + `find.byKey(const ValueKey('group-read-only-banner'))` findsOneWidget + `find.text("You can read this group's history, but you are not an active member.")` findsOneWidget); **`find.text('You were removed from this group.')` findsNothing** (the discriminator).
   - Mutation that re-reds: revert the `getGroup`-before-snackbar hoist (restore the unconditional snackbar at `:1498` before the branch) → the snackbar fires on the retained path → `findsNothing` flips RED.
   - Distinct-event discriminator (banner-vs-toast, same string family): assert banner key `group-read-only-banner` `findsOneWidget` AND snackbar text `findsNothing` in the SAME pump — the banner (durable) is present, the toast (redundant) is absent.

2. `group_conversation_wired_test.dart`::"hard-deleted group removal still pops and shows the removed snackbar"  *(preservation sentinel — mirrors the existing `:6869` contract; kept green)*
   - Tier: integration/widget
   - Shape/setup: open the conversation via a pushed route (parity with `:6869`); `groupRepo.deleteGroup(group.id)`; `removedStreamController.add(group.id)`; pump.
   - RED on HEAD: n/a (locks existing behavior). Becomes mutation-verifiable: if the fix blanket-removes the snackbar from `_handleCurrentGroupRemoved`, this test (and the existing `:6927`) reds.
   - GREEN asserts: `GroupConversationScreen` findsNothing (popped); `find.text('You were removed from this group.')` findsOneWidget; tracker not viewing.
   - Mutation that re-reds: delete the snackbar from the POP branch → no toast after pop → `findsOneWidget` flips RED. (The existing `:6869` test already enforces this; TC-02 is the explicit sentinel row.)

3. `group_conversation_wired_test.dart`::"B5 retain keeps composer read-only banner in place (preservation)"  *(sentinel — existing `:5875` kept green)*
   - Tier: integration/widget
   - Asserts (unchanged from `:5903-5910`): screen stays; `TextField` findsNothing; banner `group_read_only_not_active` findsOneWidget. Guards the in-place refresh path against regression when the snackbar is moved into the POP branch.
   - No new assertion required beyond the existing test; listed so the hoist is verified NOT to break the retain/refresh.
   - Mutation that re-reds: if the hoist accidentally drops `_loadSecurityStatus`/`_refreshVisibleGroup` from the retained branch → banner gone → `:5905-5910` reds.

4. `group_conversation_wired_test.dart`::"dissolve-while-viewing flips the read-only banner with no snackbar"  *(optional wiring-lock — closes the dissolve coverage gap; NO production change)*
   - Tier: integration/widget
   - Shape/setup: active group; `buildWidget`; push a `sys-group_dissolved:` message onto the message stream after `groupRepo.saveGroup(group.copyWith(isDissolved: true))` (so `_refreshVisibleGroup` `:1407-1411` reloads the dissolved row); pump.
   - RED on HEAD: n/a (locks existing correct behavior). Mutation-verifiable: remove the `sys-group_dissolved:` branch from `_startListening` (`:1407`) → no refresh → banner stays absent → reds.
   - GREEN asserts: banner key `group-read-only-banner` findsOneWidget with `group_read_only_dissolved` text; `find.text('You were removed from this group.')` findsNothing; `TextField` findsNothing.
   - Mutation that re-reds: drop the `sys-group_dissolved:` → `_refreshVisibleGroup` wiring at `:1407-1411` → dissolve no longer flips the banner → reds.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 retained removal = banner only, NO toast | screen state + banner + snackbar-absent | integration/widget | wired::"retained self-removal shows the read-only banner and NO removed snackbar" | HEAD shows snackbar unconditionally at `:1498` before the retained/POP branch → toast present on retained path | revert the `getGroup`-before-snackbar hoist (unconditional snackbar restored) → toast fires on retain → `findsNothing` reds | `./scripts/run_test_gates.sh groups` | ALREADY in `GROUP_TESTS` (`run_test_gates.sh:131`) |
| TC-02 hard-delete still pops + toast (load-bearing) | pop + snackbar present | integration/widget | wired::"hard-deleted group removal still pops and shows the removed snackbar" | n/a (preservation; mirrors existing `:6869`) | blanket-remove snackbar from `_handleCurrentGroupRemoved` → POP branch has no toast → `findsOneWidget` reds | `./scripts/run_test_gates.sh groups` | ALREADY in `GROUP_TESTS` (`:131`) |
| TC-03 retain refresh keeps banner (preservation) | banner + read-only in place | integration/widget | wired::"B5 retain keeps composer read-only banner in place (preservation)" (existing `:5875`) | n/a (sentinel) | drop `_loadSecurityStatus`/`_refreshVisibleGroup` from retained branch → banner gone → `:5905-5910` reds | `./scripts/run_test_gates.sh groups` | ALREADY in `GROUP_TESTS` (`:131`) |
| TC-04 dissolve banner-only (wiring-lock) | banner (dissolved) + no toast | integration/widget | wired::"dissolve-while-viewing flips the read-only banner with no snackbar" | n/a (locks existing `:1407-1411`) | remove `sys-group_dissolved:`→`_refreshVisibleGroup` branch (`:1407`) → banner absent → reds | `./scripts/run_test_gates.sh groups` | ALREADY in `GROUP_TESTS` (`:131`) |

## Invariants (locked by tests)
- INV-1: a **retained** passive-removal (group row survives) shows **only** the durable composer read-only banner (`group_read_only_not_active`) and **never** the `group_removed_snackbar` toast → TC-01.
- INV-2: a **hard-delete** removal (group row gone) still **pops** the route AND shows the `group_removed_snackbar` (the only feedback after pop) → TC-02 + existing `:6869`.
- INV-3: the retained path still flips the composer to read-only in place via the membership/group refresh (no behavior regression) → TC-03 (`:5875`).
- INV-4: passive dissolve-while-viewing flips the read-only banner with no snackbar (unchanged; newly locked) → TC-04.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short` (tree already dirty on `new-feed`); add the 4 catalog tests; run the focused TC-01 RED and confirm it fails because the unconditional snackbar appears on the retained path. Confirm TC-02/03/04 are GREEN on HEAD (they lock existing behavior; only TC-01 is RED).
2. `group_conversation_wired.dart` `_handleCurrentGroupRemoved` (`:1492-1519`) — **hoist `getGroup` above the snackbar**: keep `clearIfActive` (`:1495`) and `messenger?.hideCurrentSnackBar()` (`:1497`); then read `final retainedGroup = await widget.groupRepo.getGroup(widget.group.id);` and the `if (!mounted) return;` guard FIRST; in the **retained** branch (`retainedGroup != null`) do **NOT** show the snackbar — only `_refreshVisibleGroup`/`_loadMessages`/`_loadSecurityStatus` then `return`; in the **POP** branch (`retainedGroup == null`) show the `group_removed_snackbar` (move the `:1498-1503` `showSnackBar` here) then `Navigator.of(context).popUntil((route) => route.isFirst)`. Re-check `mounted` before `showSnackBar`/`Navigator` (an `await getGroup` boundary now precedes them). Stop-if: `groupRepo.getGroup` semantics differ for a retained-but-empty group → re-derive; do NOT add a membership read (members fail open).
3. Verify `_handleCurrentGroupRemoved` still does NOT set `_terminalSendReadOnly` (banner remains driven by the membership refresh; this unit is independent of 144's latch). No edit to `_canWrite`/`_canWriteForGroup`/`_readOnlyBannerText`.
4. No l10n, no migration, no screen-widget change, no new banner.
5. Rerun TC-01 → GREEN; rerun TC-02/03/04 + the existing `:6869`/`:5875` → GREEN. Run the named groups gate; `flutter analyze`; `git diff --check`.

## Risks And Edge Cases
- **`mounted` after the new `await getGroup` boundary**: the snackbar/`Navigator` now run after an extra await on the POP branch — re-guard `if (!mounted) return;` before each (the original already guards after `getGroup` at `:1510`; preserve that). → pinned by TC-02 (pop still works) and TC-01 (no toast on retain).
- **Empty-membership retained group fails open**: a retained group with `members.isEmpty` would keep the composer writable (`:1186-1189`). The RED retain test MUST keep OTHER members (peer-bob via `saveActiveGroupMembers`) so the banner actually appears — matches the existing B5 setup (`:5897`). → pinned by TC-01/TC-03 setup.
- **Stale-snackbar clear**: `hideCurrentSnackBar` (`:1497`) stays before the branch on BOTH paths (clears any prior toast); this is intentional and does not show a new one on the retained path. → asserted by TC-01 (`findsNothing`).
- **POP-branch toast regression**: moving the `showSnackBar` into the POP branch must keep it BEFORE the `popUntil` so the snackbar attaches to a still-mounted messenger. → pinned by TC-02 + existing `:6927`.
- **WidgetSpan U+FFFC** is not in play here — all asserted strings are plain banner/snackbar `Text`, matched via `find.text`/`find.byKey`.

## Device/Relay Proof Profile
host-only for closure. No OS-boundary / ML-KEM / relay / multi-device leg — all behavior is local screen-state + render (snackbar vs banner branch). No migration, no flag. No `/sims` rows; `check_reliability_simulation_discovery.sh` is unaffected.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'retained self-removal shows the read-only banner and NO removed snackbar'
# expect: 1 FAIL — the unconditional snackbar (:1498) appears on the retained path

# Direct GREEN (after the getGroup-before-snackbar hoist)
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
# expect: prior pass count + the up-to-4 new cases; the 2 PRE-EXISTING wired fails
# (GMAR-004 reopen-hydration, incoming-group-image-refresh) are NOT mine

# Preservation sentinels (must stay green)
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'current group removal shows a notice and exits the conversation route'   # hard-delete pop+toast
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'B5 self member_removed while viewing keeps the conversation open'        # retain banner

# Named gate for the touched subsystem
./scripts/run_test_gates.sh groups
# expect: prior groups green count UNCHANGED except the new wired cases added;
# the 2 pre-existing wired fails (GMAR-004 reopen-hydration, incoming-group-image-refresh)
# are pre-existing dirty — NOT introduced here

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: TC-01 ("retained self-removal … NO removed snackbar") before the fix — the unconditional snackbar at `:1498` fires on the retained path.
- Pre-existing dirty (NOT mine): the Groups suite has **2 PRE-EXISTING failing wired tests** — `GMAR-004 reopen-hydration` and `incoming-group-image-refresh` (media reopen/hydration, unrelated). Record before execution; do not "fix" by reverting.
- The wider tree is already dirty on `new-feed` (uncommitted Feed/Orbit/144 work per `git status`) — snapshot `git status --short` first; touch ONLY `group_conversation_wired.dart` (`_handleCurrentGroupRemoved`) + the test file.
- Environment blocker (NOT product): none (host-only).
- Scope drift (BLOCKING): any failure outside `group_conversation_wired.dart` `_handleCurrentGroupRemoved` and the wired test; any change to `_canWrite`/`_canWriteForGroup`/`_readOnlyBannerText`/`_terminalSendReadOnly` or to 144's send/reaction branches.

## Done Criteria
- [ ] TC-01 RED added first, failed because the snackbar appears on the retained path.
- [ ] Fix mutation-verified: revert the `getGroup`-before-snackbar hoist → TC-01 reds.
- [ ] Direct GREEN (TC-01) + preservation sentinels (`:6869` hard-delete pop+toast, `:5875` retain banner) pass; the 2 pre-existing wired fails unchanged.
- [ ] No new top banner; no l10n key; no migration; DB stays v92.
- [ ] `_handleCurrentGroupRemoved` still does NOT set `_terminalSendReadOnly` (banner driven by membership refresh; independent of 144).
- [ ] `flutter analyze` 0-new; `git diff --check` clean.
- [ ] `group_conversation_wired_test.dart` confirmed running in `./scripts/run_test_gates.sh groups` (already registered at `run_test_gates.sh:131`).

## Scope Guard (hard "Do not")
- Do NOT add a top `MaterialBanner` (it doubles the existing composer read-only banner — explicitly rejected by the UX review).
- Do NOT blanket-remove the `_handleCurrentGroupRemoved` snackbar — it is load-bearing on the POP/hard-delete branch (`:6921-6928`).
- Do NOT add a DB migration, an l10n key, or bump `currentIdentityDatabaseVersion` (pure presentation; reuse existing keys).
- Do NOT touch 144's send-path terminal `_TerminalReadOnly` latch, its send/reaction branches, or its tests.
- Do NOT change the dissolve path's production code (`:1407-1411`) — only optionally lock it with TC-04.
- Do NOT remove OTHER members in the RED retain test (empty membership fails open → banner would not appear).

## Accepted Differences / Intentionally Out Of Scope
- Reactions / send-path terminal `send_failed` bubbles and the `_TerminalReadOnly` latch are owned by 144 (already in-tree) — this unit only restructures the passive-removal snackbar gate; it does not unify with that machinery.
- The retained-path read-only feedback remains the EXISTING composer banner (`group_read_only_not_active`) — no new surface; one durable banner is the intended single source of feedback.
- The dissolve path stays banner-only (already correct); TC-04 only adds coverage, no behavior change.

## Dependency Impact
- None outbound. This unit removes redundant UX (double feedback) on the retained passive-removal path; the hard-delete contract (`:6869`) is preserved byte-for-byte, so no consumer of `_handleCurrentGroupRemoved`'s pop/toast behavior is affected.

## Reviewer Findings
(awaiting-review)

## Arbiter Decision
(awaiting-review) — Structural pre-check: host-only; no migration/l10n/device-proof; single-method restructure; load-bearing POP-branch snackbar explicitly preserved (TC-02 + existing `:6869`); RED (TC-01) documented and mutation-verified by reverting the hoist; the empty-membership fail-open trap is called out and pinned by the OTHER-members test setup.

## Final Execution Verdict
(pending execution)
