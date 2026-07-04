# 208 - Remove the post-accept "Joined <name>" snackbar on group-invite acceptance  (Modification)

Status: IMPLEMENTED 2026-07-04 (host-green; Part C l10n prune done)
Spec: free-text intent (no formal spec) — "when a user accepts a group invitation, the user is immediately moved to the group chat (correct); a snackbar slides up from the bottom as soon as they're moved to the group chat — remove that snackbar, keep the navigation."

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-04 | Evidence Collector | group_list_wired.dart, orbit_wired.dart, feed_wired.dart, main.dart, group_conversation_wired.dart, app_*.arb, group_list_wired_test.dart, orbit_wired_test.dart, run_test_gates.sh, l10n_integrity_test.dart | TWO live accept→navigate→snackbar surfaces (group list + Orbit), not one | Ground with verify→refute workflow |
| 2026-07-04 | Planner (verify→refute wf_45df4905-604) | 4 agents: entry-census, test-inventory, verify-on-HEAD, refute | `onlySeamIsGroupList=false`; Orbit is the PRIMARY live accept UI on `new-orbit`; snackbar rides root ScaffoldMessenger over the pushed chat; group-list-only scope = "correct but INCOMPLETE" | Build matrix (app-wide, 3 call sites) |
| 2026-07-04 | Reviewer (sufficiency) | this plan | widget-tier only; no DB/crypto/relay/OS-boundary; both test files already in GROUP_TESTS | Confirm blind-spot sweep |
| 2026-07-04 | Arbiter | — | Structurally sufficient host-only; app-wide required to satisfy the goal | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | record baseline test counts | scope confirmed | |
| | RED tests added (invert assertions + delete TC-03a) | group_list_wired_test.dart, orbit_wired_test.dart | (cmd proving they FAIL on HEAD) | RED for expected reason | |
| | implementation (remove 3 snackbar calls) | group_list_wired.dart, orbit_wired.dart | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | (optional) Part C l10n prune | app_en/de/ar.arb + regen | flutter test test/l10n/l10n_integrity_test.dart | parity holds | |
| | named gates | | ./scripts/run_test_gates.sh groups | gate green | |
| | QA (independent) | | flutter analyze; git diff --check | blocking: none | verdict |

## Source Of Truth
- Spec / intent: inline above (free-text).
- Gate definitions: scripts/run_test_gates.sh (GROUP_TESTS array @L211; group_list_wired_test.dart @L227, orbit_wired_test.dart @L229).
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh (N/A — no sim/device rows).
- Numbering / index: Test-Flight-Improv/00-INDEX.md (next-free = 208).
- Grounding: workflow wf_45df4905-604 (entry-census + test-inventory + verify + refute).

## Session Classification
implementation-ready (host-only closure; no device/sim/DB/migration).

## Exact Problem Statement
When a user accepts a group invitation, the app immediately navigates them into the group chat (correct, desired behavior). At the same instant, a bottom `SnackBar` reading **"Joined <group name>"** slides up over the group-chat screen and lingers for the default 4 seconds. The user wants this transient confirmation removed while keeping the immediate navigation.

The snackbar appears over the *group chat* (not the list/orbit the user came from) because both accept handlers call `_showSnackBar(...)` synchronously and then push the group-chat route in the same run; `_showSnackBar` resolves to the app-root `ScaffoldMessenger` (`MyApp.scaffoldMessengerKey`, `main.dart:4843`) which sits **above** the Navigator, so the queued SnackBar re-presents on whichever Scaffold is front-most — the just-pushed `GroupConversationWired`. (verify agent, wf_45df4905-604.)

The behavior originates on **two** live surfaces:
1. **Group list** (`group_list_wired.dart`) — `success` and `bridgeError` shape-b (join-with-recovery) navigating outcomes.
2. **Orbit / Intros** (`orbit_wired.dart`) — `success` navigating outcome. **This is the PRIMARY live accept UI on the `new-orbit` branch** (OrbitWired is embedded in the Feed at `feed_wired.dart:2516` and built at `main.dart:4257`; recent commits 204/205/206 are all Orbit work). The user most plausibly accepts through Orbit.

What must improve: no confirmation snackbar on a navigating group-invite accept, on **either** surface.
What must stay unchanged (→ preserved-green sentinels):
- Immediate navigation into the group chat on accept (both surfaces).
- The snackbar-free inline row states for **non-navigating** group-list outcomes (repairPending / terminal ghost rows / keep-pending retryable — TC-01/04/05/06/09).
- The **informational** non-navigating Orbit snackbars (e.g. "Invite expired", "Failed to accept invite") — those do NOT follow a move into the chat, so they are out of scope.
- `_showSnackBar` itself (7 other callers: decline/leave/accept-failed on group list; informational cases on orbit).

## Root Cause (verify → refute confirmed)
Not a bug — an intentional behavior (Plan 150 "DECISION-2": "the 2 navigating outcomes keep a single navigate-time confirmation snackbar", `group_list_wired.dart:367-371`) that the user now wants reversed. Three live call sites:
- `group_list_wired.dart:375-377` — `_showSnackBar(l10n.group_invite_joined(group?.name ?? invite.groupName))` (success), then `_onGroupTap(group)` :379.
- `group_list_wired.dart:390-392` — `_showSnackBar(l10n.group_invite_joined_recovery(group.name))` (bridgeError shape-b), then `_onGroupTap(group)` :394.
- `orbit_wired.dart:1422` — `_showSnackBar('Joined ${group?.name ?? invite.groupName}')` (success, HARDCODED string — this is why a grep for the l10n key `group_invite_joined` missed it), then `_openGroupConversationFromModel(group)` :1424.

Confirmed present & unconditional on HEAD (c433462f); no feature flag gates them. Removing the three `_showSnackBar(...)` calls while keeping the navigation calls is the correct, complete fix (verify + refute agents).

**Refuted / do-NOT-re-introduce (investigated, deliberately NOT the target):**
- `group_conversation_wired.dart:1578-1584` `group_removed_snackbar` "You were removed from this group." — fires only on group **removal**, not on join. NOT this.
- Read-only composer banner (`group_conversation_wired.dart:5186` + `:4443-4452`) — a persistent **MaterialBanner**, not a bottom SnackBar; fires on dissolved/removed groups. NOT this.
- `group_notification_catching_up` (`main.dart:4147`) — notification routing; routes HOME, not into a chat. `conversation_catching_up` (`conversation_screen.dart:1156`) — 1:1 screen. Neither is a group-invite-accept path. NOT this.
- Notification-tap / deep-link / QR / share / Feed — none auto-accept a group invite or show an entry snackbar into the chat (entry-census). The Feed only refreshes the orbit badge on `groupJoinedStream` (`feed_wired.dart:591-616`). No sim/device/OS-boundary leg.
- **INCOMPLETE-scope trap (do NOT re-introduce):** removing only the two `group_list` calls leaves the identical Orbit snackbar (`orbit_wired.dart:1422`) firing — the user would still see the toast. The fix MUST be app-wide.

## Real Scope
In scope (app-wide, 3 production edits + 2 test files, all host/widget tier):
- **P1** `group_list_wired.dart:375-377` — delete the `_showSnackBar(l10n.group_invite_joined(...))` call; keep `_onGroupTap(group)`.
- **P2** `group_list_wired.dart:390-392` — delete the `_showSnackBar(l10n.group_invite_joined_recovery(...))` call; keep `_onGroupTap(group)`.
- **P3** `orbit_wired.dart:1422` — delete the `_showSnackBar('Joined ...')` call; keep `_openGroupConversationFromModel(group)`.
- Update the DECISION-2 rationale comments (`group_list_wired.dart:367-371`; any Orbit accept comment) to record the reversal.
- Test updates in `group_list_wired_test.dart` + `orbit_wired_test.dart` (see RED catalog): invert "snackbar appears" assertions to "no snackbar", KEEP every navigation assertion, DELETE the now-void TC-03a.
- **Part C (hygiene, in-scope but safely deferrable):** prune the now-dead l10n keys `group_invite_joined` + `group_invite_joined_recovery` from `app_en.arb`, `app_de.arb`, `app_ar.arb` (value + `@`-metadata blocks) and regenerate l10n. Guarded by the l10n parity test + compile.

Out of scope (owning work):
- The informational non-navigating Orbit snackbars (`orbit_wired.dart:1427-1456`) — not "after a move"; leave as-is.
- The group-list non-navigating inline row states / ghost rows (Plan 150) — unchanged.
- Any change to the navigation itself, `_showSnackBar`, decline/leave/accept-failed snackbars, or the group-removed / read-only / catching-up surfaces.
- Refactoring the duplicated group_list-vs-Orbit accept handlers into one (future cleanup; not this change).

## Files To Inspect Next
Production: `lib/features/groups/presentation/screens/group_list_wired.dart` (`_onAcceptPendingInvite` :333, switch :372-436, `_showSnackBar` :752-764, `_onGroupTap` :295-327); `lib/features/orbit/presentation/screens/orbit_wired.dart` (`_onAcceptPendingInvite` :~1375, switch :1420-1457, `_showSnackBar` :1732-1744, `_openGroupConversationFromModel` :2609-2645).
Direct tests: `test/features/groups/presentation/group_list_wired_test.dart`; `test/features/orbit/presentation/screens/orbit_wired_test.dart`.
Optional Part C: `lib/l10n/app_en.arb` (:1408/:1428), `app_de.arb` (:1314/:1334), `app_ar.arb` (:1314/:1334); `test/l10n/l10n_integrity_test.dart` (parity @L10).
Dependency-only context: `lib/main.dart:4843` (root ScaffoldMessenger); `scripts/run_test_gates.sh` (GROUP_TESTS).

## Existing Tests Covering This Area
Assert the snackbar APPEARS (will be INVERTED):
- `group_list_wired_test.dart`: `accepting a pending invite joins the group and removes the row` (L1034), `accept retries rollback until latest metadata is recovered` (L1158), `EK011 accepts a key-package-bound pending invite through wired local package id` (L1199), `TC-03 bridgeError with materialized group navigates and reports join-with-recovery (not failure)` (L1280), `accept drains all inbox cursor pages before clearing spinner` (L1502), `TC-08 success accept still navigates and removes the row (preservation)` (L2008).
- `group_list_wired_test.dart`: `TC-03a l10n source-wiring lock: group_invite_joined_recovery ... (de locale)` (L1304) — **whole test's premise is void** → DELETE.
- `orbit_wired_test.dart`: `accepting a pending group invite from Intros joins the group` (L3364), `accepting a stale pending group invite drains latest invite before materializing group` (L3813-3814), `pending group invite accept waits for direct membership update idle before materializing group` (L3908-3909), `EK011 accepts a key-package-bound pending group invite from Intros` (L3974), `accepting a pending group invite from Intros clears spinner on cursor backlog` (L4047).

Assert NO snackbar / navigation-only (PRESERVATION — must stay green, unchanged):
- `group_list_wired_test.dart`: TC-04 (L1515), TC-01 terminal ghost x4 (L1747), TC-05 no-snackbar lock (L1816), TC-06 stuck-rejoin (L1933), TC-09 lifecycle (L1565); plus the kept navigation asserts in the inverted tests (L1019, L1273, L2006).
- `orbit_wired_test.dart`: `orbit entry keeps group long-press actions aligned...` (L4157/L4215), `orbit entry keeps group reaction inspection aligned...` (L4230/L4311); plus kept navigation asserts (L3367, L3817-3819, and orbit group-identity discriminators L3810-3812).

Missing coverage gaps: none — behavior is fully covered by inverting existing widget assertions. No new tier needed.
Already in curated family arrays?: **Yes** — both files are in `GROUP_TESTS` (`run_test_gates.sh` L227 & L229) AND auto-globbed under `feature-host-all`. No registration change (editing existing files).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
> Uniform invert form: replace each `expect(find.text('Joined <name>'), findsOneWidget)` with `expect(find.byType(SnackBar), findsNothing)` (matches the TC-05 idiom already in the file). This asserts NO snackbar of any kind on the navigating accept. Every navigation assertion in the same test STAYS. On HEAD each inverted assertion FAILS because the "Joined <name>" SnackBar is present → documented RED. After P1/P2/P3 → GREEN.

**group_list_wired_test.dart**
1. `accepting a pending invite joins the group and removes the row` (L1034)
   - Tier: widget. Shape/setup: taps accept on a success invite; L1019 already asserts `GroupConversationScreen findsOneWidget`.
   - RED on HEAD because: `find.byType(SnackBar), findsNothing` fails — the "Joined Book Club" SnackBar is shown.
   - GREEN after fix asserts: no SnackBar; navigation (L1019) still present.
   - Mutation that re-reds: revert P1 → this assertion red.
2. `accept retries rollback until latest metadata is recovered` (L1158)
   - Tier: widget. RED on HEAD: "Joined test 3" SnackBar present. GREEN: no SnackBar; metadata-recovery asserts unchanged. Re-red: revert P1.
3. `EK011 accepts a key-package-bound pending invite through wired local package id` (L1199)
   - Tier: widget. RED on HEAD: "Joined Package Room" present. Re-red: revert P1.
4. `TC-03 bridgeError with materialized group navigates and reports join-with-recovery (not failure)` (L1280)
   - Tier: widget. Keep L1273 `GroupConversationScreen findsOneWidget` (navigation) and L1284 `'Failed to accept invite' findsNothing`.
   - RED on HEAD: `find.text('Joined Book Club, but recovery is still catching up'), findsNothing` fails.
   - **Distinct-event discriminator (shared nav result):** assert `GroupConversationScreen` (navigated, INV-NAV) AND `SnackBar findsNothing` (no recovery toast) AND `'Failed to accept invite' findsNothing` (still the success-like path, NOT the error path).
   - Mutation that re-reds: revert P2 → recovery SnackBar returns → red.
   - Comment update: rewrite the L1211-1217/L1275-1278 comments (which describe the recovery snackbar as kept) to state it is intentionally removed.
5. `accept drains all inbox cursor pages before clearing spinner` (L1502)
   - Tier: widget. RED on HEAD: "Joined Cursor Room" present. Keep the 2×`group:inboxRetrieveCursor` assertion. Re-red: revert P1.
6. `TC-08 success accept still navigates and removes the row (preservation)` (L2008)
   - Tier: widget. This is the PROD-CRITICAL nav-preservation lock. Keep L2006 `GroupConversationScreen findsOneWidget`.
   - RED on HEAD: "Joined Preserve Room" present. GREEN: navigates, row removed, **no snackbar**. Re-red: revert P1.
   - Comment update: L1970-1972 currently says "AND still shows the kept snackbar (DECISION-2)" → change to "AND shows NO snackbar (208 reverses DECISION-2)".
7. `TC-03a l10n source-wiring lock ... (de locale)` (L1304) — **DELETE the entire test.**
   - Rationale: its sole purpose is to prove `group_invite_joined_recovery` stays wired/reachable; P2 deliberately un-wires it, so the German "…beigetreten, aber die Wiederherstellung…" snackbar no longer renders → the test would red with no meaningful contract left. Deleting it IS the correct reflection of the reversed decision (not a coverage loss — TC-03's inverted assert #4 covers the shape-b navigating path).

**orbit_wired_test.dart**
8. `accepting a pending group invite from Intros joins the group` (L3364)
   - Tier: widget. Keep L3367 `GroupConversationWired findsOneWidget`. RED on HEAD: "Joined Writers Room" present. Re-red: revert P3.
9. `accepting a stale pending group invite drains latest invite before materializing group` (L3813-3814)
   - Tier: widget. Replace L3813-3814 with `expect(find.byType(SnackBar), findsNothing)`.
   - **Discriminator preserved WITHOUT the snackbar:** L3810-3812 (`group!.name == 'test 3'`) + L3817-3819 (`GroupConversationWired` + conversation title `'test 3'` present, `'test 2'` absent) already lock "latest invite materialized, not the stale one". Removing the snackbar text does NOT weaken the latest-vs-stale discriminator.
   - RED on HEAD: SnackBar present. Re-red: revert P3.
10. `pending group invite accept waits for direct membership update idle before materializing group` (L3908-3909)
    - Tier: widget. Same treatment as #9; the analogous `group.name`/conversation-title asserts preserve the discriminator. RED on HEAD: SnackBar present. Re-red: revert P3.
11. `EK011 accepts a key-package-bound pending group invite from Intros` (L3974)
    - Tier: widget. RED on HEAD: "Joined Package Writers" present. Re-red: revert P3.
12. `accepting a pending group invite from Intros clears spinner on cursor backlog` (L4047)
    - Tier: widget. RED on HEAD: "Joined Cursor Writers" present. Keep spinner/backlog asserts. Re-red: revert P3.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| S1 group-list success: navigate, no snackbar | UI/widget | widget | group_list_wired_test.dart::`accepting a pending invite joins the group and removes the row` (invert L1034; keep L1019 nav) | "Joined Book Club" SnackBar present | revert P1 (:375-377) | `flutter test test/features/groups/presentation/group_list_wired_test.dart` | AUTO (glob) + already in GROUP_TESTS (L227) |
| S2 group-list success (metadata-recovery path) | UI/widget | widget | group_list_wired_test.dart::`accept retries rollback until latest metadata is recovered` (invert L1158) | "Joined test 3" present | revert P1 | same file gate | AUTO + GROUP_TESTS |
| S3 group-list success (key-package) | UI/widget | widget | group_list_wired_test.dart::`EK011 accepts a key-package-bound pending invite through wired local package id` (invert L1199) | "Joined Package Room" present | revert P1 | same file gate | AUTO + GROUP_TESTS |
| S4 group-list bridgeError shape-b: navigate + NO recovery snackbar | UI/widget; shared nav result → discriminator | widget | group_list_wired_test.dart::`TC-03 bridgeError with materialized group navigates and reports join-with-recovery (not failure)` (invert L1280; keep L1273 nav + L1284 'Failed…' findsNothing) | recovery SnackBar present | revert P2 (:390-392) | same file gate | AUTO + GROUP_TESTS |
| S5 group-list success (cursor drain) | UI/widget | widget | group_list_wired_test.dart::`accept drains all inbox cursor pages before clearing spinner` (invert L1502) | "Joined Cursor Room" present | revert P1 | same file gate | AUTO + GROUP_TESTS |
| S6 group-list success PRESERVES navigation, drops snackbar (PROD-CRITICAL nav lock) | UI/widget | widget | group_list_wired_test.dart::`TC-08 success accept still navigates and removes the row (preservation)` (invert L2008; keep L2006 nav) | "Joined Preserve Room" present | revert P1 | same file gate | AUTO + GROUP_TESTS |
| S7 recovery-key wiring lock is void | test-removal | widget | group_list_wired_test.dart::`TC-03a l10n source-wiring lock … (de locale)` → DELETED | (n/a — test deleted; would red once P2 un-wires the de recovery snackbar) | revert P2 → German recovery snackbar returns (covered by S4) | same file gate | AUTO + GROUP_TESTS |
| S8 orbit success: navigate, no snackbar | UI/widget | widget | orbit_wired_test.dart::`accepting a pending group invite from Intros joins the group` (invert L3364; keep L3367 nav) | "Joined Writers Room" present | revert P3 (:1422) | `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart` | AUTO + already in GROUP_TESTS (L229) |
| S9 orbit success (stale-drain) keeps latest-invite discriminator w/o snackbar | UI/widget; shared result → discriminator | widget | orbit_wired_test.dart::`accepting a stale pending group invite drains latest invite before materializing group` (L3813-3814 → `SnackBar findsNothing`; keep L3810-3812 group.name=='test 3' + L3817-3819 title) | "Joined test 3" SnackBar present | revert P3 | same file gate | AUTO + GROUP_TESTS |
| S10 orbit success (membership-idle) | UI/widget | widget | orbit_wired_test.dart::`pending group invite accept waits for direct membership update idle before materializing group` (invert L3908-3909; keep group-identity asserts) | "Joined test 3" present | revert P3 | same file gate | AUTO + GROUP_TESTS |
| S11 orbit success (key-package) | UI/widget | widget | orbit_wired_test.dart::`EK011 accepts a key-package-bound pending group invite from Intros` (invert L3974) | "Joined Package Writers" present | revert P3 | same file gate | AUTO + GROUP_TESTS |
| S12 orbit success (cursor backlog) | UI/widget | widget | orbit_wired_test.dart::`accepting a pending group invite from Intros clears spinner on cursor backlog` (invert L4047) | "Joined Cursor Writers" present | revert P3 | same file gate | AUTO + GROUP_TESTS |
| S13 (Part C) l10n parity holds after key prune | l10n parity | host | test/l10n/l10n_integrity_test.dart::`ARB files have identical non-empty key and placeholder sets` (unchanged; must stay green) | (green now; would red if keys pruned from only some locales) | prune key from only 1–2 of en/de/ar → parity red | `flutter test test/l10n/l10n_integrity_test.dart` | AUTO (test/l10n auto-glob) |

## Blind-Spot Sweep  (evergreen classes the spec cases above don't name — row added OR justified N/A)
- **Lifecycle / derived-state durability:** N/A — the change REMOVES a transient UI side-effect; it adds no persisted or in-memory derived state to reconstruct on reopen/restart. TC-09 (`group_list_wired_test.dart:1565`, repairPending row reverts to idle after resume) is unaffected and stays green. No reopen test needed.
- **Sibling-surface consistency:** COVERED and is the crux of this plan. The "sibling gates" are the parallel accept surfaces. Removal is applied to BOTH group_list (S1-S6) and Orbit (S8-S12); after it, the navigating outcomes match the already-snackbar-free non-navigating outcomes (TC-01/04/05/06). Note: TC-05's comment (`:1811-1815`) that "navigating outcomes keep a snackbar" becomes stale → update it (non-behavioral). The two group-list navigating outcomes (`success`, `bridgeError` shape-b) AND the one Orbit navigating outcome (`success`) are all covered — no navigating accept path is left showing a snackbar.
- **Destructive-action side-effects:** The removals are (a) 3 snackbar wirings, (b) 1 test (TC-03a), (c) optional 2 l10n keys. Asserted removed: `SnackBar findsNothing` on every navigating accept (S1-S6, S8-S12). Asserted preserved: navigation (L1019/L1273/L2006/L3367/L3817), non-navigating snackbar-free rows (TC-01/04/05/06 stay green), and `_showSnackBar` still functioning for decline/leave/accept-failed (existing decline/leave tests stay green — S-preserve). TC-03a deletion justified (premise reversed; S4 covers the shape-b path). Dead l10n keys: pruned in Part C from all 3 locales (parity-guarded, S13) or left harmless (analyzer does not flag unused generated getters — refute agent).
- **Invariant re-verification under new transitions:** N/A — no new state transition is introduced (a UI side-effect is deleted). The one invariant at risk (navigation still fires) is explicitly re-verified by the KEPT `GroupConversationScreen`/`GroupConversationWired findsOneWidget` assertions in S1/S4/S6/S8/S9/S10 (INV-NAV).

## Invariants (locked by tests)
- **INV-NAV** (navigation preserved): every navigating accept still pushes the group chat → locked by kept `GroupConversationScreen findsOneWidget` (S1/S4/S6) and `GroupConversationWired findsOneWidget` (S8/S9/S10 + orbit nav-only tests L4157/L4230). Reverting a `_onGroupTap`/`_openGroupConversationFromModel` (NOT in scope) would red these.
- **INV-NO-JOIN-SNACK** (the change): no SnackBar on any navigating accept → locked by S1-S6, S8-S12 (`SnackBar findsNothing`). Reverting any of P1/P2/P3 re-reds the mapped rows.
- **INV-NONNAV-UNCHANGED**: non-navigating group-list outcomes still show no snackbar → TC-01/04/05/06 stay green (untouched).
- **INV-SHOWSNACK-KEPT**: `_showSnackBar` still serves decline/leave/accept-failed → existing decline/leave tests stay green (untouched).
- **INV-L10N-PARITY** (Part C): en/de/ar key & placeholder sets stay identical → S13.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **Baseline snapshot:** `git status --short` (record the pre-existing dirty files listed in Scope Guard); capture baseline counts: `flutter test test/features/groups/presentation/group_list_wired_test.dart` and `.../orbit_wired_test.dart` (note N/N passing).
2. **RED (tests first):** in `group_list_wired_test.dart` invert S1-S6 assertions to `expect(find.byType(SnackBar), findsNothing)` (keep every nav assert; keep `'Failed to accept invite' findsNothing` in S4) and DELETE TC-03a (S7); in `orbit_wired_test.dart` invert S8-S12 (keep the group-identity/nav asserts that preserve the latest-invite discriminator in S9/S10). Run both files → confirm they FAIL exactly on the inverted assertions (snackbar still present). Stop-if: any inverted assertion PASSES on HEAD → the snackbar isn't firing there; re-verify the call site before proceeding.
3. **Implementation (production):** delete P1 (`group_list_wired.dart:375-377`), P2 (`:390-392`), P3 (`orbit_wired.dart:1422`); keep the navigation calls. Update the DECISION-2 comments (group_list `:367-371`, `:1211-1217`, `:1970-1972`; orbit accept comment) to record the reversal. Stop-if: removing a call orphans a local/import → re-check (per refute agent, `l10n`, `group`, `_showSnackBar`, imports all remain used; nothing should orphan).
4. **Direct GREEN:** rerun both test files → all inverted rows green; all kept nav asserts + preservation sentinels green.
5. **(Optional) Part C — l10n hygiene:** delete `group_invite_joined` + `group_invite_joined_recovery` (value + `@`-metadata) from `app_en.arb`, `app_de.arb`, `app_ar.arb`; regenerate l10n (project's `flutter gen-l10n` / build). Run `test/l10n/l10n_integrity_test.dart` (parity) + `flutter analyze` (compile catches any stray reference). Stop-if: compile error → a reference was missed; restore and re-audit. Skippable without affecting the behavior fix.
6. **Preservation + named gates:** `./scripts/run_test_gates.sh groups`; `flutter analyze`; `git diff --check`.

## Risks And Edge Cases
- **Missed surface (primary risk, already mitigated):** Orbit is the main accept UI; group-list-only removal would leave the toast. Pinned by S8-S12 across `orbit_wired.dart`. → app-wide scope.
- **Discriminator loss on the stale-drain orbit tests:** using the snackbar text to prove "latest invite (test 3) not stale (test 2)". Mitigated — S9/S10 keep the `group.name`/conversation-title asserts that independently lock it.
- **`SnackBar findsNothing` over-broad:** if a test triggered an unrelated snackbar it would false-red. Audited — the only snackbar in each of these accept tests was the join toast. If a specific test surfaces another snackbar, fall back to `expect(find.textContaining('Joined'), findsNothing)` for that row.
- **Recovery variant (group_list bridgeError shape-b):** it navigates too, so its snackbar must go (P2/S4). Do not confuse with the Orbit `bridgeError` which does NOT navigate and stays.
- **Stale comments:** DECISION-2 rationale + TC-05 comment describe the old contract; update to avoid future confusion (non-behavioral).

## Device/Relay Proof Profile
**host-only for closure.** Pure UI/widget change; no OS boundary, crypto/ML-KEM, real relay, SQLCipher, or DB migration. Entry-census confirmed no notification/deep-link/QR/share accept-snackbar path. **No `/sims` or device-proof row required** (and none would add signal). Closure = the host gates below green.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# 0) Baseline (record N/N so the only delta is inverted asserts flipping green)
git status --short
flutter test test/features/groups/presentation/group_list_wired_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart

# 1) RED — after inverting asserts + deleting TC-03a, BEFORE removing production calls
#    EXPECT: FAILURES on exactly the inverted `SnackBar findsNothing` assertions (snackbar still present).
flutter test test/features/groups/presentation/group_list_wired_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart

# 2) Direct GREEN — after removing P1/P2/P3
#    EXPECT: both files fully green (baseline total, previously-passing still passing, inverted asserts now green).
flutter test test/features/groups/presentation/group_list_wired_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart

# 3) l10n integrity (mandatory if Part C done; harmless otherwise)
flutter test test/l10n/l10n_integrity_test.dart          # EXPECT: all green (parity holds)

# 4) Named curated gate — both files live in GROUP_TESTS
./scripts/run_test_gates.sh groups                        # EXPECT: Group Messaging Gate green

# 5) Hygiene
flutter analyze                                           # EXPECT: 0 new issues
git diff --check
```

## Known-Failure Interpretation
- **Expected RED:** the inverted `SnackBar findsNothing` assertions (S1-S6, S8-S12) before P1/P2/P3 land.
- **Pre-existing dirty (do NOT revert):** the files already modified in the working tree at session start (see Scope Guard) — `.claude/skills/spec-doc/SKILL.md`, `Test-Flight-Improv/00-INDEX.md`, `graphify-arch/*` (regenerated), `info.plist`, and untracked `Test-Flight-Improv/199-*.md`, `207-*.html`.
- **Environment blocker (NOT product):** n/a — host-only; no sim/device.
- **Scope drift (BLOCKING):** any failure outside `group_list_wired*.dart`, `orbit_wired*.dart`, the 3 `.arb` files (Part C), or the regenerated l10n — investigate before proceeding.

## Done Criteria
- [x] RED added first (inverted asserts + TC-03a deleted), failed for the expected reason (snackbar present on HEAD) — group_list −6 (S1–S6, each `Found 1 widget "SnackBar"`), orbit −5 (S8–S12).
- [x] Mutation-verified (isolated): revert P1 → S1/S2/S3/S5/S6 red (S4 green); revert P2 → S4 red only; revert P3 → S8-S12 red.
- [x] Direct GREEN (group_list 42/42, orbit 82/82) + preservation sentinels (TC-01/04/05/06/09, orbit nav-only) + `run_test_gates.sh groups` (+1060) pass.
- [x] Every kept navigation assertion (INV-NAV) still green (navigation preserved on both surfaces).
- [x] Part C: l10n keys pruned from all 3 locales; `flutter gen-l10n` regenerated getters removed; `l10n_integrity_test` green (+2).
- [x] No migration (none needed).
- [x] Every touched test auto-globs AND runs in GROUP_TESTS (verified via the +1060 groups gate run).
- [x] `flutter analyze` 0 issues; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not remove or alter `_onGroupTap` / `_openGroupConversationFromModel` or any navigation — the move into the group chat MUST stay.
- Do not delete `_showSnackBar` (7 other callers) or touch decline/leave/accept-failed snackbars.
- Do not remove the informational NON-navigating Orbit snackbars (`orbit_wired.dart:1427-1456`) or the group-list inline row/ghost states.
- Do not touch `group_removed_snackbar`, the read-only composer banner, or the notification `catching_up` snackbar (refuted — not this bug).
- Do not revert the pre-existing dirty files: `.claude/skills/spec-doc/SKILL.md`, `Test-Flight-Improv/00-INDEX.md`, `graphify-arch/**`, `info.plist`, `Test-Flight-Improv/199-*.md`, `Test-Flight-Improv/207-*.html`.
- Do not refactor the duplicated group_list/Orbit accept handlers into one here.

## Accepted Differences / Intentionally Out Of Scope
- **Dead l10n keys if Part C skipped:** `group_invite_joined` / `group_invite_joined_recovery` remain in the `.arb`/generated files unused. Harmless (analyzer never flags unused generated getters; `l10n_integrity_test` only checks parity, not usage) — behavior fix is complete without pruning. Owner: this plan's optional Part C, or a future hygiene pass.
- **Handler duplication:** group_list and Orbit each carry their own `_onAcceptPendingInvite`. Consolidating them is a separate refactor.

## Dependency Impact
- None outbound. This reverses Plan 150 "DECISION-2" for the navigating outcomes; the DECISION-2 comments and TC-03a (the recovery-key wiring lock) are updated/removed to match. Any later work relying on a post-accept confirmation toast must not reintroduce it (INV-NO-JOIN-SNACK).

## Reviewer Findings
Sufficiency (self-check vs references/sufficiency-checklist.md): PASS. Every spec case (S1-S13) has ≥1 named widget test at the right (lowest) tier; each production edit (P1/P2/P3) has a mutation revert that re-reds specific rows; gates are literal with a baseline-count protocol; both test files' registration is stated (AUTO + GROUP_TESTS, no change). Blind-spot sweep: sibling-surface (the app-wide crux) and destructive-action (TC-03a + dead keys) rows added; lifecycle & new-transition justified N/A. No untested "stays unchanged" assumption: navigation preservation is locked by kept nav asserts (INV-NAV), not left as prose. Refuted alternatives recorded as do-NOT-re-introduce (Orbit-incomplete trap; removed/read-only/catching-up snackbars).

## Arbiter Decision
Structural blockers: none. Deferred details: exact baseline pass counts (captured at execution step 1); Part C l10n prune (optional, parity-guarded). Accepted differences: dead l10n keys if Part C skipped; handler duplication. Host-only closure — hand off to execution.

## Final Execution Verdict
Verdict: PASS (host-only closure, 2026-07-04) | Files changed: group_list_wired.dart, orbit_wired.dart, group_list_wired_test.dart, orbit_wired_test.dart, app_en/de/ar.arb + regenerated app_localizations{,_en,_de,_ar}.dart (Part C done) | Tests run (+counts): group_list 42/42, orbit 82/82, l10n_integrity +2, `run_test_gates.sh groups` +1060 all green; baselines were 43/82 (group_list −1 = TC-03a deleted) | Mutation: P1↔{S1,S2,S3,S5,S6}, P2↔S4, P3↔{S8–S12} all isolated-verified | Blocking: none | QA verdict: `flutter analyze` 0 issues, `git diff --check` clean, scope = the 11 files above (no Scope Guard violation) | Non-blocking follow-ups (owner): accept-handler de-duplication (group_list vs Orbit) — separate refactor.
