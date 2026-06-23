# 153 - Destructive admin actions get a safety net: decline Undo, revoke pre-confirm, remove stays pre-confirm  (Feature Improvement | Bug)  [HIGHEST-RISK unit — double-commit]

Status: awaiting-review
Spec: free-text intent (no formal spec) — chained from a UI/UX review of Group Messaging snackbars

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | group_info_wired.dart (`_confirmDissolveGroup`:539, `_confirmDeleteGroupLocally`:684, `_confirmRemoveMember`:1302, `_confirmRoleChange`:1549, `_onRevokeInvite`:2151, build wiring :2280), group_list_wired.dart (`_onDeclinePendingInvite`:498, `_loadGroups` visibleInvites :150-152, `_processingInviteIds`:108, dispose :614), decline_pending_group_invite_use_case.dart (`_maybeSendDeclineAck`:81, swallowed-error :119), revoke_pending_group_invite_use_case.dart (`sendMessage`:224 / `storeInInbox`:242), feed_store.dart (`markClearedLocally`:46/`clearClearedLocally`:53), app_en/ar/de.arb, run_test_gates.sh GROUP_TESTS :116-132, group_info_screen_test.dart:239, group_info_wired_test.dart:2176, group_list_wired_test.dart:1315 | verify→refute complete: REMOVE already pre-confirms (lock only); REVOKE has NO confirm + ships a signed envelope the recipient acts on immediately → pre-confirm, no Undo; DECLINE is the only reversible-ish action but is double-commit-HAZARDOUS (peer ack + 5 reactive `_loadGroups` triggers) → optimistic + Undo with hard guards | Planner |
| 2026-06-23 | Planner | (as above) | Three seams: (a) `_confirmRevokeInvite` mirroring `_confirmRoleChange`, swap call site :2281; (b) decline optimistic-hide via `_optimisticallyDeclinedInviteIds` filtered inside `_loadGroups` :150-152 + per-invite committed latch + Timer + SnackBarAction; (c) lock test for remove. Distinct flow-event discriminator `GROUP_INVITE_DECLINE_COMMITTED` vs `GROUP_INVITE_DECLINE_UNDONE` makes once-only non-vacuous. No migration | Reviewer |
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
- Spec / intent: inline below (UX review → user-locked design decisions)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no sim rows in this plan — host-only)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (this file = 153)

## Session Classification
implementation-ready (host-only closure; no migration, no device-proof — all behavior is local screen-state + dialog/snackbar + a deferred commit Timer)

## Exact Problem Statement
Three group **admin/invite** destructive actions have inconsistent and unsafe confirmation UX, surfaced by the Group Messaging snackbar review:

1. **REVOKE invite** (`group_info_wired.dart:2151` `_onRevokeInvite`) fires the **instant** an admin taps the per-member revoke control (call site `:2280-2281`, gated only by the `_revokingInvitePeerIds` re-entrancy guard `:2153`). It immediately calls `sendGroupInviteRevocation` (`:2170`), which ships a **signed revocation envelope** the recipient acts on **immediately** (`revoke_pending_group_invite_use_case.dart:224` `sendMessage` → fallback `:242` `storeInInbox`) and then `markRevoked` (`:2183`). There is **no confirm dialog** and an "Undo" would be a **lie** (the wire message is already out). A mis-tap silently kills a pending invite.

2. **DECLINE invite** (`group_list_wired.dart:498` `_onDeclinePendingInvite`) also fires instantly (gated only by `_processingInviteIds` `:501/:505`). It `await`s `declinePendingGroupInvite` (`:509`) which tombstones+deletes the invite AND best-effort broadcasts a **peer decline-ack** (`decline_pending_group_invite_use_case.dart:56` `_maybeSendDeclineAck`, send error-swallowed `:119-126` but **not network-idempotent**), then `_loadGroups()` (`:518`) and a post-hoc "Invite declined" snackbar (`:526`). Decline is the one place an **Undo** fits (the local invite row could be re-surfaced), BUT it is **double-commit-HAZARDOUS**: `_loadGroups` re-reads pending invites on **five** reactive triggers (`pendingInviteStream` `:248`, `groupJoinedStream` `:236`, `groupMessageStream` `:223`, `_onGroupTap.then` `:289`, app-resume `:131`), so an optimistic hide can re-surface mid-window; and a careless commit could fire the decline-ack **twice**.

3. **REMOVE member** (`group_info_wired.dart:1302` `_confirmRemoveMember`) **already** pre-confirms with a `showDialog<bool>` (`:1305`, title `group_info_remove_member_title` `:1311`, body `group_info_remove_member_body` `:1315`, keys `group-remove-cancel` `:1318` / `group-remove-confirm` `:1323`). Removal is **irreversible** (broadcasts `member_removed` then rotates+distributes a new key; INV-R2 forbids re-add; locked by `group_remove_member_roundtrip_test.dart`). It must **stay pre-confirm with NO Undo** — but there is no lock test asserting that the dialog is not accidentally dropped or "improved" into an Undo.

What must improve:
- REVOKE gains a **pre-confirm dialog** (`_confirmRevokeInvite`) mirroring `_confirmRoleChange`; the signed envelope is sent **only** after confirm. **No Undo.**
- DECLINE gains **optimistic-hide + Undo** done **carefully**: the row hides instantly, a SnackBar with an "Undo" action stays up longer than a `kDeclineUndoWindow` Timer; the real `declinePendingGroupInvite` (and its peer ack) commits **exactly once on timeout** and **not at all on Undo**, surviving double-tap, re-entrant `_loadGroups`, and dispose.
- REMOVE keeps its existing pre-confirm; a **lock test** pins "pre-confirm dialog present, NO Undo".

What must stay unchanged (→ preserved-green sentinels):
- `_confirmRemoveMember` dialog + keys + the remove round-trip behavior (`group_remove_member_roundtrip_test.dart`).
- The SCREEN-layer `onRevokeInvite`/`onDeclinePendingInvite` forwarding contract (`group_info_screen_test.dart:239`, `group_list_screen` wiring) — inserting the confirm/optimistic logic at the WIRED layer keeps the screen pass-through identical.
- The error / `notFound` / `expired` decline result snackbars and the revoke failure snackbar.
- Existing `_confirmDissolveGroup`/`_confirmDeleteGroupLocally`/`_confirmRoleChange` dialogs.

## Root Cause (verify → refute confirmed)
Confirmed on HEAD (tree dirty on `new-feed`, but these handlers are committed — NOT build-skew):
- **No `_confirmRevokeInvite` exists.** Only four `_confirm*` wrappers exist: `_confirmDissolveGroup` (`:539`), `_confirmDeleteGroupLocally` (`:684`), `_confirmRemoveMember` (`:1302`), `_confirmRoleChange` (`:1549`). The revoke call site (`:2280-2281`) wires `_onRevokeInvite` **directly** with no dialog → instant signed send (`:2170`).
- **No `_confirmDeclineInvite` exists.** `_onDeclinePendingInvite` (`:498`) commits immediately and shows the snackbar post-hoc; the optimistic-hide computation point is `_loadGroups`'s `visibleInvites` filter (`:150-152`) — currently filters only on joined-group membership, with no suppression set.
- **Decline ack is not network-idempotent.** `_maybeSendDeclineAck` (`decline_pending_group_invite_use_case.dart:81`) sends a signed ack on the wire; calling `declinePendingGroupInvite` twice would attempt the ack twice (its only guard is the local `getPendingInvite==null` notFound short-circuit `:36-44`, which races with re-surfacing).

Refuted / do-NOT-re-introduce:
- ❌ "REMOVE needs a confirm dialog added" — **FALSE**; `_confirmRemoveMember` (`:1302`) already pre-confirms (showDialog<bool> `:1305`, keys `:1318`/`:1323`). This unit only **locks** it; do not re-author a dialog.
- ❌ "REVOKE can offer an Undo" — **FALSE/UNSAFE**; `sendGroupInviteRevocation` already put a signed envelope on the wire (`:224`/`:242`) before any window could elapse; an Undo cannot recall it. Pre-confirm is the only honest affordance.
- ❌ "DECLINE Undo can just re-call a `declinePendingGroupInvite(undo:true)`" — **FALSE**; there is no undo entrypoint and the ack is not idempotent. The correct shape is **defer the whole commit** behind a one-shot latch+Timer, mirroring project 141's `_pendingStartupDrain` one-shot, and the feed_store optimistic precedent `markClearedLocally`:46 / `clearClearedLocally`:53 (note: there is **no** `undoMarkClearedLocally` — restore is "drop the suppression", not "call an undo API").
- ❌ "the optimistic hide is safe because `_processingInviteIds` already blocks re-entry" — **PARTIAL**; `_processingInviteIds` blocks a second `_onDeclinePendingInvite`, but the **five reactive `_loadGroups` triggers** would re-surface the row unless `visibleInvites` (`:150-152`) also filters the suppression set. Do not rely on the processing guard alone.
- ❌ "read-only-banner overlap with unit 147 / 144" — **WRONG PREMISE**; 144 is the terminal-send-inline-bubble unit; there is no read-only-banner overlap here. Ignore any "unit 147 banner" note.
- ❌ "build-skew" — **REFUTED**; the missing-confirm logic is on HEAD; the dirty tree is unrelated Feed/Orbit work.

## Real Scope
In scope:
- **(a) REVOKE pre-confirm** — add `_confirmRevokeInvite(GroupMember member)` to `group_info_wired.dart` (mirroring `_confirmRoleChange` `:1549`): `showDialog<bool>` with cancel key `group-revoke-cancel` / confirm key `group-revoke-confirm`, reusing existing copy where possible; on `true` → `_onRevokeInvite(member)`. Swap the build call site (`:2281`) from `_onRevokeInvite` to `_confirmRevokeInvite`. **No Undo.**
- **(b) DECLINE optimistic + Undo** — add to `group_list_wired.dart`:
  - `static const kDeclineUndoWindow = Duration(seconds: 4)` (Timer) and the SnackBar duration **strictly greater** (e.g. 6s) so the Undo action outlives the commit window's start but the commit fires at the Timer, not at SnackBar dismissal.
  - `final Set<String> _optimisticallyDeclinedInviteIds = <String>{}` — **filtered inside** `_loadGroups` `visibleInvites` (`:150-152`): `.where((i) => !joinedGroupIds.contains(i.groupId) && !_optimisticallyDeclinedInviteIds.contains(i.groupId))`.
  - `final Set<String> _committedDeclineInviteIds = <String>{}` — a per-invite **one-shot committed latch** added **before** awaiting the use-case (so a re-entrant timer/dispose cannot double-commit), mirroring 141's `_pendingStartupDrain`.
  - `final Map<String, Timer> _declineCommitTimers = {}` — per-invite Timer; cancelled on Undo and in `dispose`.
  - Rewrite `_onDeclinePendingInvite` (`:498`) to: add to `_optimisticallyDeclinedInviteIds`, `setState` to hide, show a SnackBar (`SnackBarAction(label: l10n.feed_undo, onPressed: _undoDecline)` + duration > window), and start the commit Timer. Do **not** clear `_processingInviteIds` until the deferred commit (or undo) completes.
  - `_undoDecline(inviteId)`: cancel Timer, drop from `_optimisticallyDeclinedInviteIds`, drop `_processingInviteIds`, `emitFlowEvent('GROUP_INVITE_DECLINE_UNDONE')`, `_loadGroups()` to re-surface.
  - `_commitDecline(invite)`: guard `if (!_committedDeclineInviteIds.add(invite.groupId)) return;` (one-shot), then the existing `declinePendingGroupInvite(...)` + result snackbar mapping + `_loadGroups`, then drop `_processingInviteIds`; `emitFlowEvent('GROUP_INVITE_DECLINE_COMMITTED')` on the real commit.
  - `dispose` (`:614`): cancel every Timer in `_declineCommitTimers` (NO commit on dispose — leaving the local invite intact is the safe failure; a missed decline simply re-surfaces, an over-eager commit-on-dispose would double the ack).
- **(c) REMOVE lock** — add a `group_info_wired_test.dart` test asserting the existing `_confirmRemoveMember` pre-confirm dialog is present (keys `group-remove-cancel`/`group-remove-confirm`) and that tapping the revoke/remove control does **not** show an "Undo" SnackBarAction. No production change.
- **Harness**: `group_info_wired_test.dart` and `group_list_wired_test.dart` are **NOT** in `GROUP_TESTS` → **add BOTH** (registration). They currently run only via the whole-dir auto-glob outside the curated gate.
- **l10n**: reuse `feed_undo` (`app_en.arb:1207`, ar `:1164`, de `:1164`) for the Undo label; `group_invite_declined` (`:1310`) stays as the post-decline snackbar text; revoke confirm copy reuses existing dialog strings (see step 2). **No new keys required** (revoke confirm can reuse `group_info_remove_member_body`-style existing copy; if the owner wants a bespoke revoke title/body, append-by-key — but the plan ships with reuse so it stays migration-free and key-free).

Out of scope (owning work named):
- Any change to the **wire idempotency** of the decline-ack or revocation envelope (decline ack non-idempotency is mitigated here only by the once-only commit latch; a true wire-level dedup of decline-acks is a future "invite-ack reliability" session).
- REMOVE getting an Undo (impossible per INV-R2 — out forever).
- 1:1 / Feed / Orbit confirmation UX (groups admin/invite only).
- The terminal-send inline bubble (owned by 144).

## Files To Inspect Next
Production:
- `lib/features/groups/presentation/screens/group_info_wired.dart` — `_confirmRoleChange` `:1549` (template to mirror), `_onRevokeInvite` `:2151`, `_revokeInviteMessage` `:2222`, build call site `:2280-2281`, existing `_confirmRemoveMember` `:1302`.
- `lib/features/groups/presentation/screens/group_list_wired.dart` — `_loadGroups` visibleInvites `:150-152`, `_onDeclinePendingInvite` `:498`, `_processingInviteIds` `:108`, `_showSnackBar` `:559`, `dispose` `:614`, reactive triggers `:131/:223/:236/:248/:289`.
Direct tests:
- `test/features/groups/presentation/group_info_wired_test.dart` — revoke test `:2176` (asserts immediate `sendMessageCallCount==1` → must drive the confirm dialog first); add `_confirmRevokeInvite` gate test + remove lock test.
- `test/features/groups/presentation/group_list_wired_test.dart` — decline test `:1315` (asserts immediate removal + "Invite declined" → rewrite to optimistic+commit-on-timeout); add Undo-cancels + once-only-under-double-tap/dispose tests.
Dependency-only context (NOT edited):
- `lib/features/groups/application/decline_pending_group_invite_use_case.dart` (`_maybeSendDeclineAck` `:81`, swallowed error `:119`).
- `lib/features/groups/application/revoke_pending_group_invite_use_case.dart` (`sendMessage` `:224` / `storeInInbox` `:242`).
- `lib/features/feed/application/feed_store.dart` (optimistic precedent `:46/:53`).

## Existing Tests Covering This Area
- `group_info_wired_test.dart:2176` "C: revoking a pending invite sends a revocation carrying the persisted invite_id (HOLE-4) and marks the row revoked" — taps `group-member-revoke-invite-peer-alice` and asserts `sendMessageCallCount == 1` immediately. PASSES on HEAD. **Must be updated** to tap-then-confirm (`group-revoke-confirm`) before the send assertion holds; without the confirm tap the send is 0 → it becomes the RED that proves the pre-confirm gate.
- `group_list_wired_test.dart:1315` "declining a pending invite removes the row without joining" — taps decline, asserts `getPendingInvite==null` + row gone + "Invite declined" **immediately**. PASSES on HEAD. **Locks OLD immediate-commit behavior → must be rewritten** to: row hidden immediately but `getPendingInvite` still non-null until the window elapses; after pumping past `kDeclineUndoWindow`, the invite is deleted + "Invite declined" shown.
- `group_info_screen_test.dart:239` "…onRevokeInvite forwards…" — SCREEN-layer forward of `onRevokeInvite`. PASSES; the WIRED-layer confirm insertion does not touch the screen's pass-through → **stays green** (preservation sentinel).
- `group_remove_member_roundtrip_test.dart` — remove round-trip (irreversible). PASSES; **preservation sentinel** (remove behavior unchanged).
- Remove confirm flow exercised at `group_info_wired_test.dart:594` (taps `group-remove-confirm`). PASSES; reused by the new remove lock test.

Missing coverage gaps: revoke **pre-confirm** (none today — fires immediately); decline **optimistic-hide**; decline **Undo cancels the commit**; decline **commits EXACTLY ONCE** under double-tap / dispose / re-entrant `_loadGroups`; remove **stays pre-confirm-no-Undo** lock; distinct commit-vs-undo discriminator.

Already in curated family arrays?: `letter_card_test.dart` ✅ and `group_conversation_*_test.dart` ✅ in `GROUP_TESTS` (`run_test_gates.sh:128/130/131`). **`group_info_wired_test.dart` ❌ NOT in `GROUP_TESTS`** and **`group_list_wired_test.dart` ❌ NOT in `GROUP_TESTS`** (array is `:116-132`, the closing `)` at `:132`; they run only via whole-dir auto-glob). → **two registration steps required.**

## RED Test Catalog  (add/rewrite BEFORE any production code — INV-RED-FIRST)

1. `group_info_wired_test.dart`::"revoke shows a pre-confirm dialog and sends only after confirm"  *(rewrite/augment of `:2176`)*
   - Tier: integration/widget (wired screen, in-memory repos + FakeP2PService)
   - Shape/setup: admin group, pending `sent` invite to peer-alice (as `:2176`); `FakeP2PService(sendMessageResult:true)`.
   - RED on HEAD because: HEAD `_onRevokeInvite` fires on the raw tap with no dialog → asserting that immediately after tap a dialog with key `group-revoke-confirm` is present (`findsOneWidget`) and `sendMessageCallCount == 0` until it is tapped **fails** (HEAD already sent, count==1, no dialog).
   - GREEN after fix asserts: after tapping the revoke control, `find.byKey(group-revoke-confirm) findsOneWidget` AND `p2pService.sendMessageCallCount == 0`; tap `group-revoke-cancel` → still 0 and the row is unchanged; tap revoke again then `group-revoke-confirm` → `sendMessageCallCount == 1` + row flips `revoked` (the original `:2176` assertions). **No** "Undo" SnackBarAction ever appears.
   - Mutation that re-reds: revert the call site `:2281` back to `_onRevokeInvite` (drop `_confirmRevokeInvite`) → revoke fires on tap, no dialog → red.
   - Distinct-event discriminator: assert the revoke-send count gate (`== 0` pre-confirm) — this is the load-bearing pre-confirm proof, not merely "a dialog widget exists".

2. `group_list_wired_test.dart`::"declining optimistically hides the row but keeps the invite until the undo window elapses"  *(rewrite of `:1315`)*
   - Tier: integration/widget (wired screen, in-memory repos, `pumpFrames`)
   - Shape/setup: save one pending invite; pump; tap `pending-group-invite-decline-<groupId>`.
   - RED on HEAD because: HEAD deletes the invite + shows "Invite declined" immediately; asserting that **right after the tap** the row is hidden (`pending-group-invite-<id>` findsNothing) **AND** `getPendingInvite != null` (not yet committed) fails on HEAD (it's already null).
   - GREEN after fix asserts: immediately post-tap → row hidden + `getPendingInvite(groupId) != null`; an Undo SnackBarAction (`find.text(<feed_undo 'Undo'>)`) is visible; after pumping past `kDeclineUndoWindow` → `getPendingInvite == null` + "Invite declined" shown + row stays gone.
   - Mutation that re-reds: restore the immediate `await declinePendingGroupInvite(...)` in `_onDeclinePendingInvite` (drop the deferral) → invite null immediately → the "still non-null right after tap" assertion reds.

3. `group_list_wired_test.dart`::"undo cancels the decline — invite re-surfaces and is never committed"
   - Tier: integration/widget
   - Shape/setup: save invite; tap decline; tap the Undo action before the window elapses; pump well past `kDeclineUndoWindow`.
   - RED on HEAD because: there is no Undo action on HEAD; `find.text('Undo')` findsNothing and the invite is already deleted → asserting Undo present + invite re-surfaced fails.
   - GREEN after fix asserts: after Undo → `getPendingInvite != null`, row visible again (`pending-group-invite-<id>` findsOneWidget); after pumping past the window the invite is **still** present (commit was cancelled); a `GROUP_INVITE_DECLINE_UNDONE` flow-event was emitted and **NO** `GROUP_INVITE_DECLINE_COMMITTED`.
   - Mutation that re-reds: make `_undoDecline` not cancel the Timer (drop `timer.cancel()`) → the commit still fires after the window → invite null → red.
   - Distinct-event discriminator: assert `GROUP_INVITE_DECLINE_UNDONE` emitted **AND NOT** `GROUP_INVITE_DECLINE_COMMITTED` (the two paths otherwise both touch `_loadGroups`).

4. `group_list_wired_test.dart`::"decline commits EXACTLY ONCE under double-tap and a re-entrant load"  *(double-commit guard — the highest-risk row)*
   - Tier: integration/widget
   - Shape/setup: `FakeP2PService` / spy that counts decline-ack sends (or a `_TrackingDeclineUseCase`/counter on the pending-invite repo's delete); tap decline twice rapidly; fire a `pendingInviteStream`/`groupMessageStream` event to force a re-entrant `_loadGroups`; pump past the window.
   - RED on HEAD because: n/a pre-feature (no deferral). Becomes **mutation-verifiable**: weaken the latch (`_committedDeclineInviteIds.add` → unconditional commit, i.e. remove the `if (!...add()) return;` guard) and the test reds because the decline use-case / ack fires twice (`committedCount == 2`).
   - GREEN after fix asserts: exactly **one** `GROUP_INVITE_DECLINE_COMMITTED` emitted; the decline use-case ran exactly once (delete/ack count == 1); the second tap and the re-entrant `_loadGroups` did not re-commit nor re-surface the row.
   - Mutation that re-reds: remove the one-shot `_committedDeclineInviteIds` guard in `_commitDecline` → double-commit → `committedCount == 2` → red. (Companion: drop the `_optimisticallyDeclinedInviteIds` filter in `_loadGroups` `:150-152` → re-entrant load re-surfaces the row mid-window → row-hidden assertion reds.)
   - Distinct-event discriminator: count `GROUP_INVITE_DECLINE_COMMITTED == 1` (NOT just "invite is null") — proves once-only, not merely eventually-committed.

5. `group_list_wired_test.dart`::"disposing during the undo window cancels the pending commit (no double-ack, invite kept)"
   - Tier: integration/widget
   - Shape/setup: tap decline; dispose the widget (`tester.pumpWidget(SizedBox())`) before the window; pump past the window.
   - RED on HEAD because: n/a pre-feature; mutation-verifiable — if `dispose` does not cancel `_declineCommitTimers`, the Timer fires after unmount (commit on a disposed State) → either a "setState after dispose" exception or a stray `GROUP_INVITE_DECLINE_COMMITTED`.
   - GREEN after fix asserts: no exception after disposal; the invite remains present (`getPendingInvite != null`); **no** `GROUP_INVITE_DECLINE_COMMITTED` emitted after unmount.
   - Mutation that re-reds: drop the `_declineCommitTimers` cancellation in `dispose` (`:614`) → timer fires post-unmount → red (exception / stray commit event).

6. `group_info_wired_test.dart`::"remove member stays a pre-confirm dialog with no Undo (lock)"  *(lock — no production change)*
   - Tier: integration/widget
   - Shape/setup: admin group with a removable member; tap the per-member remove control.
   - RED on HEAD because: n/a (HEAD already passes) — this is a **lock**; it goes red only under a regression mutation.
   - GREEN asserts: tapping remove shows `group-remove-cancel` + `group-remove-confirm` (`findsOneWidget` each); `member_removed` is **not** broadcast until `group-remove-confirm` is tapped; **no** `SnackBarAction` labelled "Undo" appears at any point (no `find.text(<feed_undo>)` inside a SnackBar after confirm).
   - Mutation that re-reds: bypass `_confirmRemoveMember` (wire the build call site directly to `_onRemoveMember`) → remove fires on tap, no dialog → red.

## Test Coverage Matrix  (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 revoke pre-confirm (no Undo) | dialog gate + send-after-confirm | integration/widget | group_info_wired_test::"revoke shows a pre-confirm dialog and sends only after confirm" | HEAD sends on raw tap, no dialog (count==1) | revert call site `:2281` → `_onRevokeInvite` | `./scripts/run_test_gates.sh groups` | **add group_info_wired_test to `GROUP_TESTS`** |
| TC-02 decline optimistic-hide, invite kept till window | optimistic state + deferred commit | integration/widget | group_list_wired_test::"declining optimistically hides the row but keeps the invite…" | HEAD deletes immediately; "hidden but still present" fails | restore immediate `await declinePendingGroupInvite` | `./scripts/run_test_gates.sh groups` | **add group_list_wired_test to `GROUP_TESTS`** |
| TC-03 decline Undo cancels commit | undo path + discriminator | integration/widget | group_list_wired_test::"undo cancels the decline — invite re-surfaces…" | no Undo on HEAD; invite already deleted | drop `timer.cancel()` in `_undoDecline` | `./scripts/run_test_gates.sh groups` | add group_list_wired_test to `GROUP_TESTS` |
| TC-04 decline commits EXACTLY ONCE (double-tap + re-entrant load) | once-only latch | integration/widget | group_list_wired_test::"decline commits EXACTLY ONCE under double-tap and a re-entrant load" | post-feature guard; mutate latch → double-commit | remove `_committedDeclineInviteIds` one-shot guard | `./scripts/run_test_gates.sh groups` | add group_list_wired_test to `GROUP_TESTS` |
| TC-05 dispose cancels pending commit | lifecycle safety | integration/widget | group_list_wired_test::"disposing during the undo window cancels the pending commit…" | post-feature guard; mutate dispose → post-unmount fire | drop `_declineCommitTimers` cancel in `dispose` | `./scripts/run_test_gates.sh groups` | add group_list_wired_test to `GROUP_TESTS` |
| TC-06 remove stays pre-confirm-no-Undo | lock | integration/widget | group_info_wired_test::"remove member stays a pre-confirm dialog with no Undo (lock)" | n/a (lock; reds only on regression mutation) | bypass `_confirmRemoveMember` → direct `_onRemoveMember` | `./scripts/run_test_gates.sh groups` | add group_info_wired_test to `GROUP_TESTS` |

## Invariants (locked by tests)
- INV-1: REVOKE puts **nothing** on the wire until the pre-confirm dialog is confirmed (`sendMessageCallCount == 0` pre-confirm) → TC-01.
- INV-2: REVOKE offers **no Undo** (an irrevocable signed envelope cannot be recalled) → TC-01.
- INV-3: DECLINE hides the row **optimistically** while keeping the local invite intact until `kDeclineUndoWindow` elapses → TC-02.
- INV-4: DECLINE **Undo** cancels the commit; the invite re-surfaces and `GROUP_INVITE_DECLINE_COMMITTED` is never emitted → TC-03.
- INV-5: DECLINE commits **exactly once** — double-tap, a re-entrant `_loadGroups`, and dispose can never double-fire the decline / ack (`GROUP_INVITE_DECLINE_COMMITTED == 1`, or 0 on Undo/dispose) → TC-04/TC-05.
- INV-6: DECLINE never commits **after dispose** (safe-failure = invite kept, no stray ack) → TC-05.
- INV-7: REMOVE keeps its pre-confirm dialog and offers **no Undo**; removal fires only after `group-remove-confirm` → TC-06.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short`; add/rewrite the 6 RED tests; run the focused cmds; confirm each fails for its documented reason (TC-01/02/03 RED on HEAD; TC-04/05 mutation-verifiable; TC-06 is a lock — verify it passes on HEAD and reds under its mutation).
2. `group_info_wired.dart`: add `Future<void> _confirmRevokeInvite(GroupMember member)` modeled on `_confirmRoleChange` (`:1549`) — `showDialog<bool>` with `TextButton(key: ValueKey('group-revoke-cancel'), child: Text(l10n.btn_cancel))` and `FilledButton(key: ValueKey('group-revoke-confirm'), …)`; reuse existing copy for title/body (e.g. a "Revoke this invite?" line — reuse `group_info_remove_member_body`-style existing strings to stay key-free; if the owner wants bespoke copy, append-by-key in en/ar/de, plain-string, no @-metadata). On `true` → `await _onRevokeInvite(member)`. **Do not** add any Undo.
3. `group_info_wired.dart` build call site `:2281`: change `onRevokeInvite: … ? _onRevokeInvite : null` → `… ? _confirmRevokeInvite : null`. (Screen-layer forward unchanged → `group_info_screen_test.dart:239` stays green.)
4. `group_list_wired.dart` state: add `static const kDeclineUndoWindow = Duration(seconds: 4)`; `final Set<String> _optimisticallyDeclinedInviteIds = {}`; `final Set<String> _committedDeclineInviteIds = {}`; `final Map<String, Timer> _declineCommitTimers = {}`.
5. `group_list_wired.dart` `_loadGroups` `:150-152`: extend `visibleInvites` to also exclude `_optimisticallyDeclinedInviteIds` (so all five reactive triggers respect the optimistic hide). Stop-if: the suppression set is read but the filter is not applied here → re-surface race returns; this filter is the single load-bearing point.
6. `group_list_wired.dart` rewrite `_onDeclinePendingInvite` `:498`: keep the `_processingInviteIds` re-entrancy guard; add the groupId to `_optimisticallyDeclinedInviteIds`; `setState` to hide; `_showSnackBar`-equivalent with `SnackBarAction(label: l10n.feed_undo, onPressed: () => _undoDecline(invite))` and `duration` **>** `kDeclineUndoWindow` (e.g. 6s); start `_declineCommitTimers[groupId] = Timer(kDeclineUndoWindow, () => _commitDecline(invite))`. Do **not** await the use-case here; do **not** clear `_processingInviteIds` yet.
7. `group_list_wired.dart` add `_undoDecline(invite)`: cancel+remove the Timer, drop from `_optimisticallyDeclinedInviteIds` and `_processingInviteIds`, `emitFlowEvent(layer:'FL', event:'GROUP_INVITE_DECLINE_UNDONE', details:{groupId})`, `await _loadGroups()` to re-surface.
8. `group_list_wired.dart` add `_commitDecline(invite)`: `if (!_committedDeclineInviteIds.add(invite.groupId)) return;` (one-shot); remove the Timer entry; run the existing `declinePendingGroupInvite(...)` + result→snackbar mapping (`group_invite_declined`/`group_invite_no_longer_available`/`group_invite_expired`) + `_loadGroups`; on the real `success`/`expired` path `emitFlowEvent('GROUP_INVITE_DECLINE_COMMITTED', details:{groupId})`; finally drop `_processingInviteIds`. Stop-if: the latch is added **after** the await (instead of before) → a re-entrant timer could double-commit → keep the `add()`-before-await ordering.
9. `group_list_wired.dart` `dispose` `:614`: `for (final t in _declineCommitTimers.values) t.cancel();` BEFORE `super.dispose()`. **No commit on dispose** (safe-failure).
10. `scripts/run_test_gates.sh`: add `test/features/groups/presentation/group_info_wired_test.dart` AND `test/features/groups/presentation/group_list_wired_test.dart` to the `GROUP_TESTS` array (`:116-132`).
11. Rerun direct → preservation → named gates; `flutter analyze`; `git diff --check`.

## Risks And Edge Cases
- **Double-commit of the decline-ack** (the headline risk): the ack send (`_maybeSendDeclineAck` `:81`) is **not** network-idempotent → a second commit re-broadcasts. Pinned by the one-shot `_committedDeclineInviteIds` latch (added before the await) → TC-04.
- **Re-surface race**: five reactive `_loadGroups` triggers (`:131/:223/:236/:248/:289`) could repaint the optimistically-hidden row mid-window. Pinned by the `_optimisticallyDeclinedInviteIds` filter inside `visibleInvites` (`:150-152`) → TC-04 companion mutation.
- **Commit-after-dispose**: a fired Timer touching a disposed State → setState-after-dispose. Pinned by `dispose` cancelling all Timers → TC-05.
- **SnackBar dismissed before window**: the SnackBar duration is set **>** `kDeclineUndoWindow` so the Undo affordance never disappears before the commit fires; the commit is driven by the **Timer**, not by SnackBar dismissal (a swiped-away SnackBar still commits at the Timer).
- **Revoke "Undo would be a lie"**: deliberately **no** Undo — the signed envelope is already sent (`:224`/`:242`). Pinned by TC-01 asserting no Undo SnackBarAction.
- **fakeAsync vs Timer**: the decline window tests pump real `Duration`s via `tester.pump(kDeclineUndoWindow + buffer)` (widget tests advance the fake clock on `pump(duration)`); do not use `Future.delayed`-only assertions.

## Device/Relay Proof Profile
host-only for closure. No OS-boundary / ML-KEM / relay / multi-device leg — the confirm dialog, optimistic hide, Undo Timer, and one-shot commit latch are all local screen-state + a Dart `Timer`. The underlying revoke/decline **wire** sends are pre-existing and already device-proven by their owning sessions; this unit only gates *when* they fire. No migration, no feature flag.

Deferred device work → none (no new wire behavior).

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/groups/presentation/group_info_wired_test.dart \
  --plain-name 'revoke shows a pre-confirm dialog and sends only after confirm'
flutter test test/features/groups/presentation/group_list_wired_test.dart \
  --plain-name 'declining optimistically hides the row but keeps the invite'
flutter test test/features/groups/presentation/group_list_wired_test.dart \
  --plain-name 'undo cancels the decline'

# Direct GREEN (after fix)
flutter test test/features/groups/presentation/group_info_wired_test.dart
flutter test test/features/groups/presentation/group_list_wired_test.dart

# Preservation sentinels (must stay green)
flutter test test/features/groups/presentation/group_info_screen_test.dart   # onRevokeInvite screen-forward :239 unchanged
flutter test test/features/groups/group_remove_member_roundtrip_test.dart     # remove round-trip unchanged

# Named gate (after adding BOTH wired tests to GROUP_TESTS)
./scripts/run_test_gates.sh groups   # prior green count + the 6 new cases; the 2 PRE-EXISTING wired fails (GMAR-004 reopen-hydration, incoming-group-image-refresh) are NOT mine

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: TC-01/02/03 before the fix (revoke fires on tap with no dialog; decline deletes immediately; no Undo). TC-04/05 are mutation-verifiable (their named latch/dispose mutation reds them); TC-06 is a lock (passes on HEAD, reds under its bypass mutation).
- Pre-existing dirty (NOT mine): the Groups suite has **2 PRE-EXISTING failing wired tests** — `GMAR-004` reopen-hydration and incoming-group-image-refresh — record before execution; do not "fix" by reverting.
- The wider tree is already dirty on `new-feed` (uncommitted Feed/Orbit work per `git status`) — snapshot `git status --short` first; touch only the files in Real Scope.
- Environment blocker (NOT product): none (host-only, no sim/device).
- Scope drift (BLOCKING): any failure outside the listed files/tests.

## Done Criteria
- [ ] RED added/rewritten first, failed for the expected reason (TC-01/02/03); TC-04/05 mutation-reds confirmed; TC-06 lock passes on HEAD and reds under its mutation.
- [ ] Each fix mutation-verified (re-red revert named in the matrix).
- [ ] Direct GREEN (`group_info_wired_test`, `group_list_wired_test`) + preservation sentinels (`group_info_screen_test:239`, `group_remove_member_roundtrip_test`) pass; the 2 pre-existing wired fails unchanged.
- [ ] No migration introduced (no schema change — pure presentation + a Dart Timer).
- [ ] **BOTH** `group_info_wired_test.dart` and `group_list_wired_test.dart` added to `GROUP_TESTS` and confirmed running in `./scripts/run_test_gates.sh groups`.
- [ ] No new l10n keys required (reused `feed_undo` / `group_invite_declined`); if any bespoke revoke copy is added, present in en/ar/de + l10n regenerated.
- [ ] `flutter analyze` 0-new; `git diff --check` clean.

## Scope Guard (hard "Do not")
- Do not add a DB migration or bump the identity DB version (no schema change needed).
- Do not give REVOKE or REMOVE an Undo (both are irrevocable on the wire / by INV-R2).
- Do not commit the decline on dispose (safe-failure = invite kept; commit-on-dispose would double the ack).
- Do not clear `_processingInviteIds` before the deferred commit/undo resolves.
- Do not move the optimistic-hide filter out of `_loadGroups` `:150-152` (it must guard all five reactive triggers).
- Do not touch the decline-ack/revocation **wire idempotency**, the use-case result enums, or 1:1/Feed/Orbit confirmation UX.

## Accepted Differences / Intentionally Out Of Scope
- The decline-ack is made commit-once at the **UI** layer (one-shot latch), not at the **wire** layer — accepted; a true wire-level decline-ack dedup is a future "invite-ack reliability" session. The UI latch fully covers the double-tap / re-entrant-load / dispose vectors this unit owns.
- REVOKE confirm copy **reuses** existing strings to stay migration- and key-free; a bespoke "Revoke this invite?" title/body is a could-do (append-by-key, plain-string) the owner may add without changing the test contract (tests key on `group-revoke-confirm`/`group-revoke-cancel`, not on copy).
- REMOVE keeps its existing dialog verbatim (lock only) — no copy or behavior change.

## Dependency Impact
- None outbound. The harness-registration fix (adding `group_info_wired_test.dart` + `group_list_wired_test.dart` to `GROUP_TESTS`) also retroactively gates ALL pre-existing revoke/decline/remove/role/dissolve wired behavior under the curated Group gate — a standalone hardening win (those large wired suites currently run only via whole-dir auto-glob).

## Reviewer Findings
(awaiting-review — to be filled by the sufficiency reviewer)

## Arbiter Decision
(awaiting-review — final structural verdict before execution)

## Final Execution Verdict
(pending execution)
