# 151 - Removed/dissolved-while-viewing: rely on the persistent read-only banner; scope the snackbar to hard-delete only  (Bug | Feature Improvement)

Status: IMPLEMENTED host-green 2026-06-23 (see Execution Progress + Final Execution Verdict; uncommitted on `new-feed`)
Spec: free-text intent (no formal spec) — chained from a UI/UX review of Group Messaging snackbars

> **Anchor note (2026-06-23 review):** all `file:line` refs below were re-grounded against the live `new-feed` tree. The plan's earlier draft was authored against an older tree; line numbers had drifted (production ~+7, test bodies +590–640, l10n +12, gate +2). Refs in this revision are current. If you read this after further edits to `group_conversation_wired_test.dart` (a concurrent 149/155 session is touching it), re-grep the test names — they are stable, the line numbers are not.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | group_conversation_wired.dart (`_handleCurrentGroupRemoved`, `_startListening` removed/dissolve subs, `_canWriteForGroup`, `_readOnlyBannerText`, `_canWrite`, members.isEmpty short-circuit, `_terminalSendReadOnly` set-sites), group_conversation_screen.dart (`_buildReadOnlyBanner`, `!canWrite` gate), app_en/ar/de.arb (`group_removed_snackbar`, `group_read_only_*`), group_conversation_wired_test.dart (hard-delete pop test, B5 retain test, NW-007 snackbar-absent), run_test_gates.sh (GROUP_TESTS) | verify→refute complete: passive-removal RETAINED path fires an UNCONDITIONAL snackbar that is REDUNDANT with the durable composer read-only banner (`group_read_only_not_active`); the snackbar is LOAD-BEARING only on the hard-delete/POP branch (no banner surface survives the pop). 144 is ALREADY IMPLEMENTED in-tree (the `_TerminalReadOnly` machinery exists) — this unit is independent of 144's send-path latch. NO migration, NO l10n, NO new banner. | Planner |
| 2026-06-23 | Planner | (as above) | Seam = hoist `getGroup` BEFORE the snackbar in `_handleCurrentGroupRemoved` so the snackbar fires ONLY in the POP (hard-delete) branch and is SUPPRESSED on the RETAINED branch (read-only banner carries the feedback). Keep `hideCurrentSnackBar` semantics. | Reviewer |
| 2026-06-23 | Reviewer (sufficiency) | Re-grounded every anchor on live `new-feed`. Confirmed: snackbar at `:1505-1510` fires before `getGroup` at `:1516` (root cause holds); banner text reachable via `_readOnlyBannerText` `none`-fall-through `:4280-4305`; `_canWriteForGroup` `:4260-4278`; dissolve text reachable via `_group.isDissolved` `:4292-4293`. | **3 corrections:** (1) ALL line numbers were stale → re-anchored. (2) **NEW TC-05**: a THIRD retained-path removed-stream test exists — `group_conversation_wired_test.dart:7571` "old group removal does not clear newer active group key" (`saveGroup` only → `getGroup` non-null → retained branch, no pop) — directly exercises the modified branch; add as preservation sentinel. (3) **TC-02 de-duplicated**: the existing `:7509` test IS the hard-delete sentinel — do NOT write a duplicate; designate it like TC-03 designates the existing B5 test. | Arbiter |
| 2026-06-23 | Arbiter | (as above) | APPROVED for execution: host-only; single-method restructure; load-bearing POP snackbar preserved (existing `:7509`); RED (TC-01) documented + mutation-verified by reverting the hoist; empty-membership fail-open trap pinned by the OTHER-members setup; retained-branch invariants pinned by 3 existing sentinels (`:6466`, `:7509`, `:7571`). | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-23 | contract extraction (git status --short) | (read-only) | tree dirty on `new-feed` (Feed/Orbit/144/149/155 uncommitted); `group_conversation_wired.dart` + `..._wired_test.dart` already `M` from the concurrent 149/155 session | scope confirmed: my edits are only `_handleCurrentGroupRemoved` + 2 new tests | RED |
| 2026-06-23 | RED tests added | `group_conversation_wired_test.dart` (+TC-01, +TC-04) | `flutter test --plain-name 'retained self-removal …'` → **+0 -1**, fails at the snackbar `findsNothing` (banner assertions all passed first) | RED for the documented reason (unconditional snackbar on retained path) | implement |
| 2026-06-23 | implementation | `group_conversation_wired.dart` `_handleCurrentGroupRemoved` `:1499-1530` | hoisted `getGroup` above the snackbar; snackbar now only in the POP branch, before `popUntil`; kept `clearIfActive`/`hideCurrentSnackBar`/both `mounted` guards | scoped to the one method (diff = 2 hunks) | GREEN |
| 2026-06-23 | direct GREEN | (above) | TC-01 + TC-04 both **All tests passed!** | reds now green | preservation |
| 2026-06-23 | preservation GREEN | (no edit) | `:7508` hard-delete, `:6466` B5 retain, `:7571` old-group-no-clear — all **All tests passed!** (also green pre-fix) | sentinels green | gate |
| 2026-06-23 | named gates | (no edit) | `./scripts/run_test_gates.sh groups` → **+689 -2**; the 2 fails are the pre-existing `GMAR-004 reopen-hydration` + `incoming group image refresh` (media hydration, NOT mine) | gate green (mine all pass) | QA |
| 2026-06-23 | QA (independent) | (no edit) | `flutter analyze` on both files → 5 issues, ALL pre-existing at unrelated lines (595/2219/2425/2948/test 900); **0-new**. `git diff --check` clean. Mutation = the pre-fix RED (unconditional snackbar) already observed. | blocking: none | verdict: SHIP |

## Source Of Truth
- Spec / intent: inline below (UX review of Group Messaging snackbars → user-locked decision: do NOT add a top banner; rely on the EXISTING composer read-only banner; scope the snackbar to the truly-deleted case).
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose). `group_conversation_wired_test.dart` is ALREADY in `GROUP_TESTS` (`:133`); `group_conversation_screen_test.dart` is at `:132`.
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no sim/device rows in this plan).
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (this file = 151).

## Session Classification
implementation-ready (host-only closure; no migration, no l10n, no device-proof — pure presentation/branch-restructure)

## Anchor Map (re-verified 2026-06-23 on `new-feed`)
**`lib/features/groups/presentation/screens/group_conversation_wired.dart`**
| Symbol | Line |
|---|---|
| `_handleCurrentGroupRemoved` (whole method) | `:1499-1526` |
| top `if (!mounted) return;` | `:1500` |
| `groupConversationTracker?.clearIfActive(...)` | `:1502` |
| `messenger = ScaffoldMessenger.maybeOf(context)` | `:1503` |
| `messenger?.hideCurrentSnackBar()` | `:1504` |
| **unconditional `showSnackBar(group_removed_snackbar)`** (the redundancy) | `:1505-1510` |
| `final retainedGroup = await widget.groupRepo.getGroup(...)` | `:1516` |
| post-await `if (!mounted) return;` | `:1517` |
| **RETAINED branch** (`_refreshVisibleGroup`/`_loadMessages`/`_loadSecurityStatus`; `return`) | `:1518-1523` |
| pre-pop `if (!mounted) return;` | `:1524` |
| **POP branch** `Navigator.of(context).popUntil((route) => route.isFirst)` | `:1525` |
| removed-stream subscription (`_removedSubscription`, postFrame → `_handleCurrentGroupRemoved`) | `:1445-1451` |
| `_startListening` message handler | `:1407` |
| dissolve branch (`message.id.startsWith('sys-group_dissolved:')` → `_refreshVisibleGroup`) | `:1414`, `:1418` |
| live membership-change block (`sys-member_removed:` etc → `_loadSecurityStatus`) | `:1420-1432` |
| `_canWriteForGroup` | `:4260-4278` |
| `_readOnlyBannerText` (note: `_terminalSendReadOnly` override checked first, then `none`-fall-through to membership/dissolve) | `:4280-4305` |
| `_canWrite` getter | `:4583-4585` |
| `members.isEmpty` fail-open short-circuit | `:1189` |
| `_terminalSendReadOnly` field decl / reset | `:234` / `:699` |

**`lib/features/groups/presentation/screens/group_conversation_screen.dart`**
| Symbol | Line |
|---|---|
| ctor `final bool canWrite;` | `:48` |
| ctor `final String? readOnlyBannerText;` | `:107` |
| `if (!canWrite) _buildReadOnlyBanner()` gate | `:253-254` |
| `_buildReadOnlyBanner` | `:949-951` |
| banner `key: const ValueKey('group-read-only-banner')` | `:958` |

**`test/features/groups/presentation/group_conversation_wired_test.dart`**
| Symbol | Line |
|---|---|
| hard-delete pop sentinel "current group removal shows a notice and exits the conversation route" | `:7508-7569` (deleteGroup `:7560`, add `:7561`, screen findsNothing `:7564`, **snackbar findsOneWidget `:7566`**, tracker false `:7567`) |
| B5 retain sentinel "B5 self member_removed while viewing keeps the conversation open …" | `:6466-6502` (removeMember `:6487`, add `:6488`, screen findsOneWidget `:6493`, TextField findsNothing `:6494`, banner findsOneWidget `:6495-6500`) |
| **NEW sentinel** "old group removal does not clear newer active group key" (retained path) | `:7571-7629` (saveGroup only `:7575`, setActive newer `:7619`, add `:7621`, screen findsOneWidget `:7627`, tracker newer isTrue `:7628`) |
| NW-007 zero-peers snackbar-absent | `:3665` (asserts `find.text('You were removed from this group.')` findsNothing at `:3764` and `:3789`) |
| helper `makeChatGroup` | `:730` |
| helper `saveActiveGroupMembers` (saves self + a second member → removing self leaves members non-empty) | `:753` |
| helper `buildWidget` (`removedStreamController:` param `:997`, wired to `removedStream:` `:1015`) | `:977` |

**`lib/l10n/app_en.arb`**
| Key | Line | Value |
|---|---|---|
| `group_removed_snackbar` | `:504` | "You were removed from this group." |
| `group_read_only_not_active` | `:882` | "You can read this group's history, but you are not an active member." |
| `group_read_only_dissolved` | `:498` | "This group has been dissolved. History stays available, but new messages are disabled." |

**`scripts/run_test_gates.sh`** — `GROUP_TESTS` lists `group_conversation_screen_test.dart` `:132` and `group_conversation_wired_test.dart` `:133`. No new registration needed.

## Exact Problem Statement
When a member is **passively removed** from a group **while they are viewing the conversation** and the group **row is retained** (the B3 "read-only shell"), `GroupConversationWired._handleCurrentGroupRemoved` (`group_conversation_wired.dart:1499-1526`) fires an **unconditional ~4s floating snackbar** ("You were removed from this group.", `app_en.arb:504` `group_removed_snackbar`, shown at `:1505-1510`) **and then** reads `getGroup` (`:1516`) and refreshes the group/messages/security gates (`:1518-1523`) so the **composer read-only banner** (`group_read_only_not_active`, `app_en.arb:882`) appears. The result is **double feedback**: a transient toast AND a durable banner that says the same thing. The banner is the correct, persistent surface; the snackbar is redundant noise on the retained path, and if it is missed (scrolled/backgrounded) it adds nothing the banner does not already carry.

The snackbar is **load-bearing only on the hard-delete branch**: when the group row is truly gone (`getGroup` returns `null`, `:1516`), the screen **pops** to the first route (`:1525`) and there is **no composer banner surface left** — the snackbar is the only feedback the user gets that the group disappeared. The existing test `group_conversation_wired_test.dart:7508` ("current group removal shows a notice and exits the conversation route") asserts exactly this at `:7564-7567` (`GroupConversationScreen` findsNothing + `find.text('You were removed from this group.')` findsOneWidget + tracker not viewing).

Separately, the **passive dissolve-while-viewing** path is **already banner-only** (no snackbar today): a `sys-group_dissolved:` message on the message stream triggers `_refreshVisibleGroup` (`group_conversation_wired.dart:1414`/`:1418`), which flips the composer to the `group_read_only_dissolved` banner with no toast. That path is correct but **uncovered by tests** — an optional wiring-lock is included (TC-04).

What must improve:
- The **retained passive-removal** path shows **only** the durable composer read-only banner (`group_read_only_not_active`) — **no** redundant `group_removed_snackbar`.
- The **hard-delete (POP)** path keeps the snackbar (the only feedback after the route pops).

What must stay unchanged (→ preserved-green sentinels):
- Hard-delete pop + snackbar (`group_conversation_wired_test.dart:7508` `:7564-7567`) — LOAD-BEARING; the snackbar MUST still fire on the POP branch.
- B5 retain test (`:6466-6502`) — stays on the conversation, composer flips to the `group_read_only_not_active` banner, `TextField` findsNothing. It is currently SILENT on the snackbar (no `findsNothing`/`findsOneWidget` assertion on it); it stays green after the fix.
- **"old group removal does not clear newer active group key" (`:7571-7629`)** — RETAINED path (`saveGroup` only, no removeMember/deleteGroup → `getGroup` non-null), asserts no-pop + `clearIfActive` scoping (newer key untouched). SILENT on the snackbar today → stays green after the fix.
- The passive dissolve banner-only path (`:1414`/`:1418`) — unchanged behavior; only newly locked.
- NW-007 zero-peers tests (`:3665`, asserts at `:3764`/`:3789`) — keep the group active, never trigger `removedStream`, already assert the removed snackbar `findsNothing`; stay green.
- 144's send-path terminal `_TerminalReadOnly` latch + its tests (the in-tree send-failed bubble work). NOT touched by this unit.

## Root Cause (verify → refute confirmed; re-verified 2026-06-23)
**Confirmed on HEAD (in-tree, `new-feed` dirty but this method is committed/stable):**
- `group_conversation_wired.dart:1499-1526` `_handleCurrentGroupRemoved` runs in **fixed order**: `clearIfActive` (`:1502`), capture `messenger` (`:1503`), `hideCurrentSnackBar` (`:1504`), **then the snackbar UNCONDITIONALLY** (`:1505-1510`), and **only after that** reads `getGroup` (`:1516`) to branch RETAINED (`:1518-1523`, refresh in place) vs POP (`:1525`, hard-delete). Because the snackbar is shown **before** the branch decision, it fires on **both** outcomes — including the retained path where the refreshed composer read-only banner (`group_read_only_not_active` via `_canWriteForGroup` returning false for a non-active member, `:4264-4266` + `_readOnlyBannerText` `:4295-4296`) already provides durable feedback.
- The retained-path banner is driven purely by the **membership refresh** (`_loadSecurityStatus` at `:1521` → `_isCurrentUserActiveMember=false` → `_canWriteForGroup` false at `:4264-4266` → `!canWrite` renders `_buildReadOnlyBanner`, `group_conversation_screen.dart:253-254`/`949-951`). `_handleCurrentGroupRemoved` does **NOT** set the `_terminalSendReadOnly` override (re-verified: every `_terminalSendReadOnly` write is OUTSIDE `:1499-1526` — field decl `:234`, reset `:699`, and the send/reaction setter sites; none inside `_handleCurrentGroupRemoved`). So on a passive removal `_readOnlyBannerText` takes the `none` branch (`:4289`) and falls through to the membership check (`:4295-4296`) → `group_read_only_not_active`. The banner is already independent of 144's machinery.
- `_emitGroupRemoved` (the producer of `groupRemovedStream`) fires ONLY for **self-removal** (retained shell) and **self-ban** in `group_message_listener.dart`. Empty-membership / admin dissolve does NOT use `groupRemovedStream` — it rides the message stream (`sys-group_dissolved:`) → `_refreshVisibleGroup` (`:1414`/`:1418`), already banner-only/snackbar-free.

Refuted / do-NOT-re-introduce:
- ❌ "the fix is a new top `MaterialBanner`" — **REJECTED by the UX review**. A top banner would DOUBLE the existing composer read-only banner. Do NOT add one.
- ❌ "blanket-remove the `_handleCurrentGroupRemoved` snackbar" — **WRONG**; the snackbar is load-bearing on the POP/hard-delete branch (`:7564-7567` asserts it). A blanket delete reds that test.
- ❌ "the empty-membership/dissolve path also needs a snackbar fix here" — **FALSE**; dissolve is already banner-only via `:1414`/`:1418` (no snackbar). The only snackbar-redundancy is the retained passive-removal path.
- ❌ "removing a member auto-flips read-only via membership" — TRUE here only because `saveActiveGroupMembers` (`:753`) keeps OTHER members (a second member) so `members.isEmpty` is false (`:1189`). If the test left the group empty, the active-member check would **fail open** (`members.isEmpty → active=true`) and the banner would NOT appear. The RED retain test MUST keep OTHER members (matches the existing B5 setup, `removeMember(group.id, testIdentity.peerId)` leaving the second member). *(Empirically confirmed: the B5 test is green on HEAD WITH the banner present, which is only possible if members are non-empty after removing self.)*
- ❌ "needs a migration / l10n key" — **FALSE**; pure presentation; reuses the EXISTING `group_removed_snackbar` (`:504`) and `group_read_only_not_active` (`:882`). DB stays v92; no new keys.

## Real Scope
In scope:
- **Restructure `_handleCurrentGroupRemoved` (`group_conversation_wired.dart:1499-1526`)**: hoist the `getGroup` read (`:1516`) **above** the snackbar (`:1505-1510`) so the snackbar is shown **only** in the POP/hard-delete branch (`retainedGroup == null`). On the RETAINED branch (`retainedGroup != null`), **do not** show the snackbar; keep the in-place refresh (`_refreshVisibleGroup`/`_loadMessages`/`_loadSecurityStatus`, `:1519-1521`) which drives the durable read-only banner. Keep `clearIfActive` (`:1502`) and `hideCurrentSnackBar` (`:1504`) as-is (clearing any stale snackbar is intentional and harmless on both branches).
- **Optional wiring-lock only** for the already-correct passive-dissolve path (`:1414`/`:1418`) — a test that locks "dissolve-while-viewing flips the read-only banner with NO snackbar" (no production change; closes a coverage gap).

Out of scope (owning work named):
- 144's send-path terminal `send_failed` bubble + `_TerminalReadOnly` latch + reaction parity (already in-tree; this unit does not touch the send/reaction branches or that latch). Owner: 144.
- Any new banner widget, l10n key, DB migration, or 1:1 conversation parity.
- Changing the snackbar copy/behavior on the POP branch (kept byte-identical).

## Files To Inspect Next
Production:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — `_handleCurrentGroupRemoved` `:1499-1526` (the seam: snackbar `:1505-1510`, `getGroup` `:1516`, retained branch `:1518-1523`, POP `:1525`); removed-stream sub `:1445-1451`; dissolve refresh `:1414`/`:1418`; `_canWriteForGroup` `:4260-4278`; `_readOnlyBannerText` `:4280-4305`; `_canWrite` `:4583-4585`; members.isEmpty short-circuit `:1189`.
- `lib/features/groups/presentation/screens/group_conversation_screen.dart` — `!canWrite` → `_buildReadOnlyBanner` gate `:253-254`; banner builder `:949-951` (key `ValueKey('group-read-only-banner')` `:958`); ctor params `canWrite` `:48`, `readOnlyBannerText` `:107`.
Direct tests:
- `test/features/groups/presentation/group_conversation_wired_test.dart` — hard-delete pop+snackbar `:7508-7569` (`:7564-7567` load-bearing, KEEP green); B5 retain `:6466-6502` (KEEP green); old-group-no-clear retained `:7571-7629` (KEEP green); NW-007 snackbar-absent `:3665`/`:3764`/`:3789`; helpers `makeChatGroup` `:730`, `saveActiveGroupMembers` `:753`, `buildWidget` `:977` (`removedStreamController:` param `:997`).
Dependency-only context (not edited):
- `lib/features/groups/application/group_message_listener.dart` — `_emitGroupRemoved` producers (self-removal / self-ban). *(Line numbers not re-grounded — dependency-only; verify the invariant "removedStream is self-removal/self-ban only" by reading `_emitGroupRemoved` callers if needed.)*
- `lib/l10n/app_en.arb`/`app_ar.arb`/`app_de.arb` — REUSED keys only (`group_removed_snackbar` en `:504`, `group_read_only_not_active` en `:882`, `group_read_only_dissolved` en `:498`).

## Existing Tests Covering This Area
- `group_conversation_wired_test.dart:7508` "current group removal shows a notice and exits the conversation route" — hard-delete: `deleteGroup` (`:7560`) + `removedStream.add` (`:7561`) → `GroupConversationScreen` findsNothing (`:7564`) + `find.text('You were removed from this group.')` findsOneWidget (`:7566`) + tracker not viewing (`:7567`). PASSES on HEAD. **LOAD-BEARING preservation sentinel — the snackbar MUST stay on the POP branch (= TC-02; no new test needed).**
- `group_conversation_wired_test.dart:6466` "B5 self member_removed while viewing keeps the conversation open read-only in place (no pop) when the group row is retained" — `removeMember(group.id, testIdentity.peerId)` (second member retained) (`:6487`) + `removedStream.add` (`:6488`) → screen stays (`:6493`), `TextField` findsNothing (`:6494`), banner text `group_read_only_not_active` findsOneWidget (`:6495-6500`). PASSES on HEAD. **SILENT on the snackbar today** (no assertion) → stays green after the fix (= TC-03 sentinel); my NEW RED (TC-01) adds the explicit `findsNothing` for the snackbar on this exact setup.
- `group_conversation_wired_test.dart:7571` "old group removal does not clear newer active group key" — RETAINED path: `saveGroup` only (no removeMember/deleteGroup, `:7575`) → `getGroup` returns non-null → retained branch → no pop; `setActive('group:newer-group')` (`:7619`); `removedStream.add` (`:7621`) → screen stays (`:7627`) + `tracker.isViewing('group:newer-group')` isTrue (`:7628`). PASSES on HEAD. **SILENT on the snackbar today** → stays green after the fix. **NEW preservation sentinel (= TC-05) — directly exercises the modified retained branch and the `clearIfActive` scoping.**
- `group_conversation_wired_test.dart:3665` (NW-007 zero-peers) — keep group active, never trigger `removedStream`; already assert removed snackbar `findsNothing` (`:3764`/`:3789`). PASS, unaffected.
- Passive **dissolve-while-viewing** banner flip (`:1414`/`:1418`): **NO test** (coverage gap) → TC-04 optional wiring-lock.

Missing coverage gaps: (1) retained passive-removal must NOT show the snackbar (the redundancy this unit removes) → TC-01; (2) passive dissolve banner-only is uncovered → TC-04.

Already in curated family arrays?: `group_conversation_wired_test.dart` ✅ in `GROUP_TESTS` (`scripts/run_test_gates.sh:133`). **No new registration needed.** `group_conversation_screen_test.dart` is at `:132` (not touched).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `group_conversation_wired_test.dart`::"retained self-removal shows the read-only banner and NO removed snackbar"  *(NEW — the one true RED)*
   - Tier: integration/widget (wired screen; fakes + in-memory repo, exactly the B5 setup)
   - Shape/setup: `makeChatGroup` + `saveActiveGroupMembers(groupRepo, group)` (self **and** a second member, so `members.isEmpty` is false); `buildWidget(group:, removedStreamController:)`; pump 20 frames; `removeMember(group.id, testIdentity.peerId)` (second member retained → row retained); `removedStreamController.add(group.id)`; pump 20 frames.
   - RED on HEAD because: `_handleCurrentGroupRemoved` shows the snackbar **unconditionally** at `:1505-1510` (before the `getGroup` retained/POP branch at `:1516`), so on the retained path `find.text('You were removed from this group.')` is **present** — asserting it `findsNothing` FAILS on HEAD.
   - GREEN after fix asserts: screen still present (`find.byType(GroupConversationScreen)` findsOneWidget); composer flipped read-only (`find.byType(TextField)` findsNothing + `find.byKey(const ValueKey('group-read-only-banner'))` findsOneWidget + `find.text("You can read this group's history, but you are not an active member.")` findsOneWidget); **`find.text('You were removed from this group.')` findsNothing** (the discriminator).
   - Mutation that re-reds: revert the `getGroup`-before-snackbar hoist (restore the unconditional snackbar at `:1505-1510` before the branch) → the snackbar fires on the retained path → `findsNothing` flips RED.
   - Distinct-event discriminator (banner-vs-toast, same string family): assert banner key `group-read-only-banner` `findsOneWidget` AND snackbar text `findsNothing` in the SAME pump — the banner (durable) is present, the toast (redundant) is absent.

2. `group_conversation_wired_test.dart:7508`::"current group removal shows a notice and exits the conversation route"  *(preservation sentinel — the EXISTING hard-delete test; do NOT write a duplicate)*
   - Tier: integration/widget
   - This is the LOAD-BEARING contract. No new test — the existing `:7508` test already asserts pop (`:7564`) + snackbar findsOneWidget (`:7566`) + tracker false (`:7567`). It must stay green after the snackbar is moved into the POP branch.
   - RED on HEAD: n/a (locks existing behavior).
   - Mutation that re-reds: blanket-remove the snackbar from `_handleCurrentGroupRemoved`, OR move it to AFTER `popUntil` (messenger detached) → no toast after pop → `:7566` flips RED.

3. `group_conversation_wired_test.dart:6466`::"B5 self member_removed while viewing keeps the conversation open …"  *(preservation sentinel — existing B5 test, kept green)*
   - Tier: integration/widget
   - Asserts (unchanged from `:6493-6500`): screen stays; `TextField` findsNothing; banner `group_read_only_not_active` findsOneWidget. Guards the in-place refresh path against regression when the snackbar is moved into the POP branch.
   - No new assertion required beyond the existing test; listed so the hoist is verified NOT to break the retain/refresh.
   - Mutation that re-reds: if the hoist accidentally drops `_loadSecurityStatus`/`_refreshVisibleGroup` from the retained branch → banner gone → `:6495-6500` reds.

4. `group_conversation_wired_test.dart`::"dissolve-while-viewing flips the read-only banner with no snackbar"  *(NEW optional wiring-lock — closes the dissolve coverage gap; NO production change)*
   - Tier: integration/widget
   - Shape/setup: active group; `buildWidget`; after `groupRepo.saveGroup(group.copyWith(isDissolved: true))`, push a `GroupMessage` with `groupId == group.id` and `id` starting `sys-group_dissolved:` onto `messageStreamController` (so the `_startListening` handler `:1414` matches groupId AND the dissolve prefix → `_refreshVisibleGroup` `:1418` reloads the dissolved row); pump.
   - RED on HEAD: n/a (locks existing correct behavior). Mutation-verifiable: remove the `sys-group_dissolved:` arm from `_startListening` (`:1414`) → no refresh → banner stays absent → reds.
   - GREEN asserts: banner key `group-read-only-banner` findsOneWidget with `group_read_only_dissolved` text ("This group has been dissolved. History stays available, but new messages are disabled."); `find.text('You were removed from this group.')` findsNothing; `TextField` findsNothing.
   - Banner-text reachability (verified): for a dissolved row with `_terminalSendReadOnly == none`, `_readOnlyBannerText` takes the `_group.isDissolved` fall-through (`:4292-4293`) → `group_read_only_dissolved`. ✓
   - Mutation that re-reds: drop the `sys-group_dissolved:` → `_refreshVisibleGroup` wiring at `:1414`/`:1418` → dissolve no longer flips the banner → reds.

5. `group_conversation_wired_test.dart:7571`::"old group removal does not clear newer active group key"  *(NEW-to-this-plan preservation sentinel — existing test, kept green)*
   - Tier: integration/widget
   - RETAINED-path coverage the earlier draft missed: `saveGroup` only (group row retained, `getGroup` non-null), `setActive('group:newer-group')`, `removedStream.add` → asserts screen stays (`:7627`) + newer-group active-tracking untouched (`:7628`). Locks two things the hoist must preserve: (a) the retained branch does NOT pop; (b) `clearIfActive(_activeGroupConversationKey)` (`:1502`) only clears the OLD group's key — it stays before the branch and must not start clearing the newer key.
   - RED on HEAD: n/a (locks existing behavior). SILENT on the snackbar → stays green after the fix.
   - Mutation that re-reds: if the hoist accidentally pops on the retained branch (e.g. inverted `retainedGroup == null` test) → `:7627` reds; if `clearIfActive` is moved/broadened to clear unconditionally → `:7628` reds.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 retained removal = banner only, NO toast | screen state + banner + snackbar-absent | integration/widget | wired::"retained self-removal shows the read-only banner and NO removed snackbar" *(NEW)* | HEAD shows snackbar unconditionally at `:1505-1510` before the retained/POP branch (`:1516`) → toast present on retained path | revert the `getGroup`-before-snackbar hoist (unconditional snackbar restored) → toast fires on retain → `findsNothing` reds | `./scripts/run_test_gates.sh groups` | ALREADY in `GROUP_TESTS` (`run_test_gates.sh:133`) |
| TC-02 hard-delete still pops + toast (load-bearing) | pop + snackbar present | integration/widget | wired:7508::"current group removal shows a notice and exits the conversation route" *(EXISTING — no new test)* | n/a (preservation) | blanket-remove snackbar from `_handleCurrentGroupRemoved`, or place it after `popUntil` → POP branch has no toast → `:7566` reds | `./scripts/run_test_gates.sh groups` | ALREADY in `GROUP_TESTS` (`:133`) |
| TC-03 retain refresh keeps banner (preservation) | banner + read-only in place | integration/widget | wired:6466::"B5 self member_removed while viewing keeps the conversation open …" *(EXISTING)* | n/a (sentinel) | drop `_loadSecurityStatus`/`_refreshVisibleGroup` from retained branch → banner gone → `:6495-6500` reds | `./scripts/run_test_gates.sh groups` | ALREADY in `GROUP_TESTS` (`:133`) |
| TC-04 dissolve banner-only (wiring-lock) | banner (dissolved) + no toast | integration/widget | wired::"dissolve-while-viewing flips the read-only banner with no snackbar" *(NEW, optional)* | n/a (locks existing `:1414`/`:1418`) | remove `sys-group_dissolved:`→`_refreshVisibleGroup` arm (`:1414`) → banner absent → reds | `./scripts/run_test_gates.sh groups` | ALREADY in `GROUP_TESTS` (`:133`) |
| TC-05 old-group retained removal: no pop + newer key untouched | no-pop on retained + clearIfActive scoping | integration/widget | wired:7571::"old group removal does not clear newer active group key" *(EXISTING — was missing from the earlier draft)* | n/a (preservation; exercises the modified retained branch) | invert/pop on retained branch → `:7627` reds; broaden `clearIfActive` to unconditional → `:7628` reds | `./scripts/run_test_gates.sh groups` | ALREADY in `GROUP_TESTS` (`:133`) |

### Blind-spot sweep (evergreen classes)
- **Lifecycle/derived-state durability (reopen/restart):** N/A to this unit — the fix only changes a live in-session transition (snackbar branch). On reopen, the read-only banner is recomputed from the durable membership row via `_canWriteForGroup` on load (the GMAR reopen-hydration tests, owned by 144, cover that path). The fix touches neither the load path nor any persisted state. Justified N/A.
- **Sibling-surface consistency:** covered — the retained-removal transition has THREE removed-stream surfaces in this file (B5 removeMember `:6466`, old-group retained `:7571`, hard-delete `:7508`); all three are now enumerated (TC-03/TC-05/TC-02). 1:1 conversation has no "removed from group" notion (no sibling); Feed/group-list reaction to removal is out of scope (named).
- **Destructive-action side-effects:** the only destructive branch is the hard-delete POP (`getGroup == null`). The fix preserves it byte-for-byte (TC-02 + the moved snackbar still fires before `popUntil`). No new deletion/side-effect introduced.
- **Invariant-re-verification under new transition:** the NEW transition is "retained removal suppresses the snackbar." Re-verified against all three retained/pop sentinels (TC-02/03/05) + the new RED (TC-01) + dissolve (TC-04) — every existing removed-stream invariant still holds.

## Invariants (locked by tests)
- INV-1: a **retained** passive-removal (group row survives) shows **only** the durable composer read-only banner (`group_read_only_not_active`) and **never** the `group_removed_snackbar` toast → TC-01.
- INV-2: a **hard-delete** removal (group row gone) still **pops** the route AND shows the `group_removed_snackbar` (the only feedback after pop) → TC-02 (existing `:7508`).
- INV-3: the retained path still flips the composer to read-only in place via the membership/group refresh (no behavior regression) → TC-03 (existing `:6466`).
- INV-4: passive dissolve-while-viewing flips the read-only banner with no snackbar (unchanged; newly locked) → TC-04.
- INV-5: a retained removal of a NON-active (older) group does NOT pop and does NOT clear a newer group's active-tracking (`clearIfActive` scoping preserved) → TC-05 (existing `:7571`).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short` (tree already dirty on `new-feed`); add the 2 NEW tests (TC-01 RED, TC-04 wiring-lock). Run the focused TC-01 RED and confirm it fails because the unconditional snackbar appears on the retained path. Confirm the 3 EXISTING sentinels (TC-02 `:7508`, TC-03 `:6466`, TC-05 `:7571`) are GREEN on HEAD (they lock existing behavior; only TC-01 is RED).
2. `group_conversation_wired.dart` `_handleCurrentGroupRemoved` (`:1499-1526`) — **hoist `getGroup` above the snackbar**: keep `clearIfActive` (`:1502`), capture `messenger` (`:1503`), and `messenger?.hideCurrentSnackBar()` (`:1504`); then read `final retainedGroup = await widget.groupRepo.getGroup(widget.group.id);` and the `if (!mounted) return;` guard FIRST; in the **retained** branch (`retainedGroup != null`) do **NOT** show the snackbar — only `_refreshVisibleGroup`/`_loadMessages`/`_loadSecurityStatus` then `return`; in the **POP** branch (`retainedGroup == null`) re-check `if (!mounted) return;`, show the `group_removed_snackbar` (move the `:1505-1510` `showSnackBar` here, using the captured `messenger` — still valid since `mounted` is guarded; re-resolving `ScaffoldMessenger.maybeOf(context)` after the guard is equally fine), then `Navigator.of(context).popUntil((route) => route.isFirst)`. **Keep the snackbar BEFORE `popUntil`** so it attaches to the still-mounted ancestor messenger. Stop-if: `groupRepo.getGroup` semantics differ for a retained-but-empty group → re-derive; do NOT add a membership read (members fail open at `:1189`).
3. Verify `_handleCurrentGroupRemoved` still does NOT set `_terminalSendReadOnly` (banner remains driven by the membership refresh; this unit is independent of 144's latch). No edit to `_canWrite`/`_canWriteForGroup`/`_readOnlyBannerText`.
4. No l10n, no migration, no screen-widget change, no new banner.
5. Rerun TC-01 → GREEN; rerun TC-04 → GREEN; rerun the 3 existing sentinels (`:7508`/`:6466`/`:7571`) → GREEN. Run the named groups gate; `flutter analyze`; `git diff --check`.

## Risks And Edge Cases
- **`mounted` after the new `await getGroup` boundary**: the snackbar/`Navigator` now run after the await on the POP branch — re-guard `if (!mounted) return;` before the POP block (the original already guards after `getGroup` at `:1517` and before pop at `:1524`; preserve both). → pinned by TC-02 (pop still works) and TC-01 (no toast on retain).
- **Captured `messenger` reuse after await**: `messenger` is captured at `:1503` before the await. On the POP branch it is reused after the `mounted` guard — valid because the messenger is an ancestor of the (still-mounted) widget. Re-resolving after the guard is an equivalent, slightly more defensive alternative. → pinned by TC-02 (`:7566` snackbar after pop).
- **Empty-membership retained group fails open**: a retained group with `members.isEmpty` would keep the composer writable (`:1189`). The RED retain test MUST keep OTHER members (a second member via `saveActiveGroupMembers` `:753`) so the banner actually appears — matches the existing B5 setup. → pinned by TC-01/TC-03 setup.
- **Stale-snackbar clear**: `hideCurrentSnackBar` (`:1504`) stays before the branch on BOTH paths (clears any prior toast); this is intentional and does not show a new one on the retained path. → asserted by TC-01 (`findsNothing`).
- **POP-branch toast regression**: moving the `showSnackBar` into the POP branch must keep it BEFORE the `popUntil` so the snackbar attaches to a still-mounted messenger. → pinned by TC-02 + `:7566`.
- **`clearIfActive` scoping**: stays before the branch and keyed to the OLD group's `_activeGroupConversationKey`; must not be broadened. → pinned by TC-05 (`:7628`).
- **WidgetSpan U+FFFC** is not in play here — all asserted strings are plain banner/snackbar `Text`, matched via `find.text`/`find.byKey`.
- **Concurrent test-file churn**: a 149/155 session is editing `group_conversation_wired_test.dart` in-tree. Re-grep test NAMES (stable) rather than trusting the line numbers in this plan before inserting TC-01/TC-04; a merge may shift them again.

## Device/Relay Proof Profile
host-only for closure. No OS-boundary / ML-KEM / relay / multi-device leg — all behavior is local screen-state + render (snackbar vs banner branch). No migration, no flag. No `/sims` rows; `check_reliability_simulation_discovery.sh` is unaffected.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'retained self-removal shows the read-only banner and NO removed snackbar'
# expect: 1 FAIL — the unconditional snackbar (:1505-1510) appears on the retained path

# Direct GREEN (after the getGroup-before-snackbar hoist)
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
# expect: prior pass count + the 2 NEW cases (TC-01, TC-04); the PRE-EXISTING wired
# fails (GMAR-004 reopen-hydration, incoming-group-image-refresh) are NOT mine

# Preservation sentinels (must stay green) — all EXISTING, no new test
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'current group removal shows a notice and exits the conversation route'   # TC-02 hard-delete pop+toast
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'B5 self member_removed while viewing keeps the conversation open'        # TC-03 retain banner
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'old group removal does not clear newer active group key'                 # TC-05 retained no-pop + key scoping

# Named gate for the touched subsystem
./scripts/run_test_gates.sh groups
# expect: prior groups green count UNCHANGED except the 2 new wired cases added;
# the pre-existing wired fails (GMAR-004 reopen-hydration, incoming-group-image-refresh)
# are pre-existing dirty — NOT introduced here

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: TC-01 ("retained self-removal … NO removed snackbar") before the fix — the unconditional snackbar at `:1505-1510` fires on the retained path.
- Pre-existing dirty (NOT mine): the Groups suite has PRE-EXISTING failing wired tests — `GMAR-004 reopen-hydration` and `incoming-group-image-refresh` (media reopen/hydration, unrelated). **Snapshot the exact pre-existing fail list with `./scripts/run_test_gates.sh groups` BEFORE adding tests** (the count may have shifted with the 149/155 churn) — do not "fix" by reverting.
- The wider tree is already dirty on `new-feed` (uncommitted Feed/Orbit/144/149/155 work per `git status`) — snapshot `git status --short` first; touch ONLY `group_conversation_wired.dart` (`_handleCurrentGroupRemoved`) + the test file.
- Environment blocker (NOT product): none (host-only).
- Scope drift (BLOCKING): any failure outside `group_conversation_wired.dart` `_handleCurrentGroupRemoved` and the wired test; any change to `_canWrite`/`_canWriteForGroup`/`_readOnlyBannerText`/`_terminalSendReadOnly` or to 144's send/reaction branches.

## Done Criteria
- [ ] TC-01 RED added first, failed because the snackbar appears on the retained path.
- [ ] Fix mutation-verified: revert the `getGroup`-before-snackbar hoist → TC-01 reds.
- [ ] Direct GREEN (TC-01 + TC-04) + the 3 preservation sentinels (`:7508` hard-delete pop+toast, `:6466` retain banner, `:7571` retained no-pop + key scoping) pass; the pre-existing wired fails unchanged.
- [ ] No new top banner; no l10n key; no migration; DB stays v92.
- [ ] `_handleCurrentGroupRemoved` still does NOT set `_terminalSendReadOnly` (banner driven by membership refresh; independent of 144).
- [ ] `flutter analyze` 0-new; `git diff --check` clean.
- [ ] `group_conversation_wired_test.dart` confirmed running in `./scripts/run_test_gates.sh groups` (already registered at `run_test_gates.sh:133`).

## Scope Guard (hard "Do not")
- Do NOT add a top `MaterialBanner` (it doubles the existing composer read-only banner — explicitly rejected by the UX review).
- Do NOT blanket-remove the `_handleCurrentGroupRemoved` snackbar — it is load-bearing on the POP/hard-delete branch (`:7564-7567`).
- Do NOT write a NEW duplicate hard-delete test — the existing `:7508` test IS the TC-02 sentinel.
- Do NOT add a DB migration, an l10n key, or bump `currentIdentityDatabaseVersion` (pure presentation; reuse existing keys).
- Do NOT touch 144's send-path terminal `_TerminalReadOnly` latch, its send/reaction branches, or its tests.
- Do NOT change the dissolve path's production code (`:1414`/`:1418`) — only optionally lock it with TC-04.
- Do NOT broaden `clearIfActive` (`:1502`) — it must stay scoped to the OLD group's key (TC-05).
- Do NOT remove OTHER members in the RED retain test (empty membership fails open → banner would not appear).

## Accepted Differences / Intentionally Out Of Scope
- Reactions / send-path terminal `send_failed` bubbles and the `_TerminalReadOnly` latch are owned by 144 (already in-tree) — this unit only restructures the passive-removal snackbar gate; it does not unify with that machinery.
- The retained-path read-only feedback remains the EXISTING composer banner (`group_read_only_not_active`) — no new surface; one durable banner is the intended single source of feedback.
- The dissolve path stays banner-only (already correct); TC-04 only adds coverage, no behavior change.
- Reopen/restart durability of the read-only banner is the membership-row load path (owned by 144's GMAR hydration tests); untouched here — justified N/A in the blind-spot sweep.

## Dependency Impact
- None outbound. This unit removes redundant UX (double feedback) on the retained passive-removal path; the hard-delete contract (`:7508`) is preserved byte-for-byte, so no consumer of `_handleCurrentGroupRemoved`'s pop/toast behavior is affected.

## Reviewer Findings
- **F1 (corrected — line drift):** every `file:line` in the earlier draft was stale on the live `new-feed` tree (production ~+7, test bodies +590–640, l10n +12, gate +2). Re-grounded in the new **Anchor Map** section and inline. The ROOT CAUSE and FIX DESIGN are unaffected — the snackbar at `:1505-1510` still fires before the `getGroup` branch at `:1516`, exactly as the draft argued.
- **F2 (gap — missing sentinel):** a THIRD retained-path removed-stream test exists — `:7571` "old group removal does not clear newer active group key" (`saveGroup` only → `getGroup` non-null → retained branch, no pop). It directly exercises the branch being modified and locks `clearIfActive` scoping. Added as **TC-05** (existing test, kept green) + **INV-5**.
- **F3 (cleanup — duplicate test):** the draft's TC-02 proposed re-implementing the hard-delete pop test that already exists at `:7509`. Changed TC-02 to **designate the existing `:7508` test** as the sentinel (parity with how TC-03 designates the existing B5 test) — avoids a redundant duplicate. Net NEW tests = 2 (TC-01 RED, TC-04 optional), not 4.
- **F4 (verified — banner reachability):** confirmed TC-01's `group_read_only_not_active` and TC-04's `group_read_only_dissolved` are reachable: on a passive removal/dissolve `_terminalSendReadOnly == none`, so `_readOnlyBannerText` (`:4280-4305`) falls through the override switch to the membership (`:4295-4296`) / dissolve (`:4292-4293`) checks. The banner is independent of 144's latch as the draft claimed.
- **F5 (verified — fail-open):** the `members.isEmpty → active=true` fail-open (`:1189`) is real; empirically the B5 test is green WITH the banner present, proving `saveActiveGroupMembers` (`:753`) leaves a second member after removing self. The RED-retain warning stands.
- **Sufficiency verdict:** PASS — every spec case maps to a tiered test with a documented RED reason (or sentinel) + a re-red mutation + a literal gate + a (already-satisfied) registration; the blind-spot sweep is run with TC-05 closing the sibling-surface/transition gap and reopen-durability justified N/A; no untested "stays unchanged" assumption remains.

## Arbiter Decision
APPROVED for execution. Host-only; no migration/l10n/device-proof; single-method restructure. Load-bearing POP-branch snackbar explicitly preserved (TC-02 = existing `:7508`). RED (TC-01) documented and mutation-verified by reverting the hoist. The empty-membership fail-open trap is called out and pinned by the OTHER-members setup. All THREE retained/pop sentinels (`:6466` removeMember, `:7571` saveGroup-only, `:7508` hard-delete) are enumerated, so the modified branch is fully fenced. Net change: 2 new tests + a one-method reorder. No structural blockers.

## Final Execution Verdict
**SHIPPED host-green (2026-06-23).** Single-method restructure in `group_conversation_wired.dart` `_handleCurrentGroupRemoved` (`:1499-1530`): `getGroup` hoisted above the snackbar so the `group_removed_snackbar` toast fires **only** on the POP/hard-delete branch (before `popUntil`, on the still-mounted ancestor messenger); the RETAINED passive-removal branch is now snackbar-free and relies solely on the durable composer read-only banner (`group_read_only_not_active`). `clearIfActive`, `hideCurrentSnackBar`, and both `mounted` guards preserved byte-for-behavior.

Evidence:
- **TC-01** ("retained self-removal … NO removed snackbar") RED-first (snackbar present on retained path) → GREEN after the hoist. The pre-fix RED IS the "revert the hoist" mutation, so the fix is mutation-verified.
- **TC-04** ("dissolve-while-viewing flips the read-only banner with no snackbar") — NEW wiring-lock, green (no production change; locks `:1414`/`:1418`).
- Preservation sentinels all green: `:7508` hard-delete pop+toast (INV-2, load-bearing), `:6466` B5 retain banner (INV-3), `:7571` old-group retained no-pop + `clearIfActive` scoping (INV-5).
- `./scripts/run_test_gates.sh groups` → **+689 -2**; the 2 fails are the pre-existing `GMAR-004 reopen-hydration` + `incoming group image refresh` (media hydration, unrelated — documented in Known-Failure Interpretation).
- `flutter analyze` 0-new (5 pre-existing infos at unrelated lines); `git diff --check` clean. No migration, no l10n key, DB stays v92, `_terminalSendReadOnly` untouched (independent of 144). Graphs refreshed (full `graphify update .` + `refresh_arch_graph.sh`).
- Uncommitted on `new-feed` (tree was already dirty with Feed/Orbit/144/149/155 work).
