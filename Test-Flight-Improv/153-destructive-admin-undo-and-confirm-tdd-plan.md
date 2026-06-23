# 153 - Destructive admin/invite actions get a safety net: REVOKE pre-confirm, DECLINE optimistic-Undo (group-list **and** orbit), REMOVE stays pre-confirm  (Feature Improvement | Bug)  [HIGHEST-RISK unit — deferred-commit lifecycle]

Status: IMPLEMENTED host-green (2026-06-23) — RED-first, all 11 cases mutation-verified; see Execution Progress + Final Execution Verdict
Spec: free-text intent (no formal spec) — chained from a UI/UX review of Group Messaging snackbars

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | group_info_wired.dart, group_list_wired.dart, decline_pending_group_invite_use_case.dart, revoke_pending_group_invite_use_case.dart, feed_store.dart, app_en/ar/de.arb, run_test_gates.sh, group_info_screen_test.dart, group_info_wired_test.dart, group_list_wired_test.dart | verify→refute v1 complete | Planner |
| 2026-06-23 | Planner (v1) | (as above) | Three seams; single decline surface; one-shot `_committedDeclineInviteIds` latch; "no l10n keys" | Reviewer |
| 2026-06-23 | **Reviewer (source-verified, 5-agent workflow + direct reads)** | + orbit_wired.dart, orbit_screen.dart, pending_group_invite_card.dart, feed_wired.dart, flow_event_emitter.dart | **REVISED PLAN. Findings: (1) decline use-case is ALREADY idempotent (getPendingInvite==null short-circuit BEFORE delete BEFORE ack) → "double-ack hazard" root cause is WRONG; the `_committedDeclineInviteIds` latch is redundant & non-mutation-verifiable → DROPPED. (2) SECOND identical decline surface `orbit_wired._onDeclinePendingInvite` (:1314) exists with hardcoded English snackbars → owner chose PARITY (both surfaces). (3) ALL `group_list_wired` line numbers were ~81 lines stale; corrected. (4) `group_list_wired_test.dart` is ALREADY in GROUP_TESTS (:134) → plan's "add both" was wrong; add `group_info_wired_test.dart` + `orbit_wired_test.dart`. (5) flow-event discriminator needs NEW `debugSetFlowEventSink` test infra. (6) bespoke revoke l10n keys (owner choice). (7) NEW risks: SnackBar-vs-window race, throwing-commit `_processingInviteIds` leak, feed-badge sibling surface.** | Arbiter |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-23 | baseline | (none) | `flutter test` per file: group_info 67/67, group_list 37/37, orbit 60/3 | orbit's 3 fails are pre-existing ACCEPT flakes (A2 / EK011 / clears-spinner) — none decline | RED |
| 2026-06-23 | live-source verify | (read-only) | 5-agent Explore workshop + direct reads | `group_info_wired` line#s match; `group_list` decline test now :1894 (off-10), setUp :462 (off-12); **orbit had NO decline test** → TC-8..11 are NEW not rewrites; all 3 prod files already import `dart:async` | RED tests |
| 2026-06-23 | RED tests added | group_info_wired_test, group_list_wired_test (+flow sink, +_ThrowingIdentityRepository), orbit_wired_test (+flow sink, +`Locale` param to buildOrbitWired) | TC-1 RED (no `group-revoke-confirm`, sends on raw tap); group_list TC-3/4/5/6/7 RED (`getPendingInvite` non-null fails, no Undo, COMMITTED==0); orbit TC-8/9/10/11 RED | RED for documented reasons; TC-2 green-on-HEAD (lock) | implement |
| 2026-06-23 | implementation | l10n en/ar/de (+3 revoke keys) + `flutter gen-l10n`; group_info_wired (`_confirmRevokeInvite`+callsite); group_list_wired (const+2 fields, loader filter, sync `_onDeclinePendingInvite`+`_undoDecline`+`_commitDecline`, `_showSnackBar` action, dispose); orbit_wired (parity + localize 4 snackbars + projection); run_test_gates.sh (+2 GROUP_TESTS) | scoped to Real-Scope files only | scoped | direct GREEN |
| 2026-06-23 | direct GREEN | (as above) | group_info **68/68**, group_list **41/41**, orbit **64/3-preexisting** (my 4 decline tests pass; TC-11 needed `ensureVisible` — German layout pushed the button under the nav) | reds now green | preservation |
| 2026-06-23 | preservation GREEN | (none) | `group_info_screen_test` 22/22; `group_remove_member_roundtrip_test` 1/1 | sentinels green (onRevokeInvite screen-forward + remove round-trip unchanged) | gate |
| 2026-06-23 | named gate | run_test_gates.sh | `./scripts/run_test_gates.sh groups` → **+617 / -6**. ALL my new tests RAN+PASSED inside it. -6 = pre-existing only: `group_conversation_wired_test`+`group_resume_recovery_test` **152 `micPermissionGateway` compile crash** (cascades to siblings; `group_messaging_smoke` 88/88 in isolation) + 3 orbit ACCEPT flakes | gate RED is 100% pre-existing (152 + orbit-accept); NOT mine — Scope Guard forbids touching 152 files | mutation + QA |
| 2026-06-23 | mutation-verify | (mutate→run→revert) | RED-on-HEAD already proves TC-1/3/4/8/9/11. Explicit mutations: TC-2 (bypass `_confirmRemoveMember`)→RED; TC-5A (drop loader filter)→RED; TC-6 (drop dispose cancel)→RED; TC-7 (drop finally processing-id cleanup)→RED; TC-10 (drop orbit dispose cancel)→RED. All reverted, re-green | every fix mutation-verified | QA |
| 2026-06-23 | hygiene + QA | (none) | `flutter analyze` 3 prod files = 0 NEW (4 pre-existing infos in untouched `group_info_wired` lines); `git diff --check` clean; no leftover mutation markers; adversarial review workflow run | blocking: none | verdict |

## Source Of Truth
- Spec / intent: inline below (UX review → user-locked design decisions)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: host-only — no sim rows in this plan
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (this file = 153)

## Session Classification
implementation-ready (host-only closure; no migration, no device-proof — all behavior is local screen-state + dialog/snackbar + a deferred-commit `Timer`; the underlying revoke/decline **wire** sends are pre-existing & already owner-proven). Adds **bespoke l10n keys** (en/ar/de + `flutter gen-l10n`) for the revoke confirm dialog — **key-only, NOT a DB migration.**

## Exact Problem Statement
Three group **admin/invite** destructive actions have inconsistent and unsafe confirmation UX, surfaced by the Group Messaging snackbar review:

1. **REVOKE invite** (`group_info_wired.dart:2151` `_onRevokeInvite(GroupMember)`) fires the **instant** an admin taps the per-member revoke control (build call site `:2280-2282`, gated only by the `_revokingInvitePeerIds` re-entrancy guard `:2152-2155`). It immediately calls `sendGroupInviteRevocation` (`:2170`) — the wire-sending function in `revoke_pending_group_invite_use_case.dart` (`sendMessage:224`, fallback `storeInInbox:242`) — then `markRevoked` (`:2183`). There is **no confirm dialog**; a mis-tap silently kills a pending invite and an "Undo" would be a **lie** (the signed envelope is already on the wire).

2. **DECLINE invite** fires instantly on **two** surfaces:
   - `group_list_wired.dart:576` `_onDeclinePendingInvite(PendingGroupInvite)` — gated only by `_processingInviteIds` (`:579/:583`); awaits `declinePendingGroupInvite` (`:587-595`), `_loadGroups()` (`:596`), then an "Invite declined" snackbar (`:604`).
   - `orbit_wired.dart:1314` `_onDeclinePendingInvite(PendingGroupInvite)` — a **near-identical copy** gated by `_processingPendingInviteIds` (`:1317/:1321`); awaits the same use-case (`:1325-1333`), `_loadPendingGroupInvites()` (`:1335`), then a **hardcoded English** "Invite declined" snackbar (`:1340`).
   Decline is the one place an **Undo** fits (the local invite row can be re-surfaced). The improvement is to defer the commit behind an Undo window — but the deferral introduces **new lifecycle risks** (re-surface during the window via reactive reloads, commit-after-dispose, the irreversible decline-ack firing despite an Undo) that must be guarded on **both** surfaces.

3. **REMOVE member** (`group_info_wired.dart:1302` `_confirmRemoveMember(GroupMember)`) **already** pre-confirms with `showDialog<bool>` (`:1305`, title `group_info_remove_member_title` `:1311`, body `group_info_remove_member_body` `:1315`, keys `group-remove-cancel` `:1318` / `group-remove-confirm` `:1323`). Removal is **irreversible** (broadcasts `member_removed` + rotates/distributes a new key; INV-R2 forbids re-add; locked by `group_remove_member_roundtrip_test.dart`). It must **stay pre-confirm with NO Undo** — but no lock test pins that it is not accidentally dropped or "improved" into an Undo.

What must improve:
- REVOKE gains a **pre-confirm dialog** (`_confirmRevokeInvite`) mirroring `_confirmRoleChange`; the signed envelope is sent **only** after confirm. **No Undo.** New **bespoke** l10n copy.
- DECLINE gains **optimistic-hide + Undo** on **both** `group_list_wired` and `orbit_wired`: the row hides instantly, a SnackBar with an "Undo" action is shown for the `kDeclineUndoWindow`; the real `declinePendingGroupInvite` (and its peer ack) commits **exactly once on timeout** and **not at all on Undo / dispose / re-mount**, surviving double-tap and re-entrant reloads. Orbit's hardcoded snackbars are **localized** as part of the parity work.
- REMOVE keeps its existing pre-confirm; a **lock test** pins "pre-confirm dialog present, NO Undo".

What must stay unchanged (→ preserved-green sentinels):
- `_confirmRemoveMember` dialog + keys + the remove round-trip (`group_remove_member_roundtrip_test.dart`).
- The SCREEN-layer `onRevokeInvite`/`onDeclinePendingInvite` pass-through contract (`group_info_screen_test.dart:213-266`, `group_list_screen.dart:303-311`, `orbit_screen.dart:846-860`) — confirm/optimistic logic lives at the WIRED layer, so the screen pass-through stays identical.
- The error / `notFound` / `expired` decline result snackbars and the revoke failure snackbar (`_revokeInviteMessage:2222`).
- Existing `_confirmDissolveGroup`/`_confirmDeleteGroupLocally`/`_confirmRoleChange` dialogs.

## Root Cause (verify → refute confirmed — REVISED)
Confirmed on HEAD (tree dirty on `new-feed`; `group_info_wired.dart` line numbers are exact; `group_list_wired.dart` shifted ~81 lines from the dirty Feed work — NOT build-skew, the handlers exist):

- **No `_confirmRevokeInvite` exists.** Only four `_confirm*` wrappers exist: `_confirmDissolveGroup` (`:539`), `_confirmDeleteGroupLocally` (`:684`), `_confirmRemoveMember` (`:1302`), `_confirmRoleChange` (`:1549`). The revoke call site (`:2280-2282`) wires `_onRevokeInvite` **directly**, no dialog → instant signed send via `sendGroupInviteRevocation` (`:2170`).
- **Two un-deferred decline handlers exist** — `group_list_wired.dart:576` and `orbit_wired.dart:1314` — both commit immediately and show the snackbar post-hoc. The optimistic-hide computation points are each loader's membership filter: `group_list_wired._loadGroups` `visibleInvites` (`:157-159`) and `orbit_wired._loadPendingGroupInvites` (`:616-618`) — currently both filter only on joined-group membership, no suppression set.
- **The deferred-commit window is the new risk surface.** Re-reads of pending invites fire on multiple reactive triggers (group_list: `groupMessageStream:241`, `groupJoinedStream:253`, `pendingInviteStream:265`, `_onGroupTap.then:306`, app-resume:138; orbit: init:391, `:894`, `pendingInviteStream:906`), so an optimistic hide can re-surface mid-window unless the loader's filter also excludes the suppression set; and a fired `Timer` could touch a disposed `State`.

Refuted / do-NOT-re-introduce:
- ❌ **"DECLINE is double-ack-HAZARDOUS because the ack is not network-idempotent"** — **WRONG / OVERSTATED.** `declinePendingGroupInvite` is **already idempotent**: `getPendingInvite` (`:36`) returns null on a second call (the first call deleted the invite at `:52`), so it short-circuits to `notFound` at `:37-44` **BEFORE** tombstone/delete/`_maybeSendDeclineAck` (`:56`). The decline-ack therefore **cannot** be sent twice on sequential commits. Consequence: the v1 plan's dedicated one-shot **`_committedDeclineInviteIds` latch is REDUNDANT** (nothing double-invokes `_commitDecline`: one synchronous `_processingInviteIds` guard + one-shot `Timer` + the use-case's own idempotency already make it once-only). It is **DROPPED** — a guard whose removal re-reds no test is non-mutation-verifiable theater. The genuine "exactly once" lock is the held `_processingInviteIds` guard (see TC-G5).
- ❌ **"REMOVE needs a confirm dialog added"** — **FALSE**; `_confirmRemoveMember` (`:1302`) already pre-confirms. This unit only **locks** it; do not re-author a dialog.
- ❌ **"REVOKE can offer an Undo"** — **FALSE/UNSAFE**; `sendGroupInviteRevocation` puts a signed envelope on the wire (`:224`/`:242`) synchronously inside `_onRevokeInvite`. Pre-confirm is the only honest affordance. (Note: the use-case ALSO exposes a separate local-only `revokePendingGroupInvite()`; the UI does **not** call that — it calls the wire-sending `sendGroupInviteRevocation`. The "no Undo" premise is correct for the path the UI actually takes.)
- ❌ **"add both wired tests to GROUP_TESTS"** — **PARTLY WRONG**; `group_list_wired_test.dart` is **already** in `GROUP_TESTS` (`run_test_gates.sh:134`). Only `group_info_wired_test.dart` and `orbit_wired_test.dart` are unregistered (run via host-all glob only).
- ❌ **"reuse existing l10n for the revoke confirm copy"** — **REPLACED**; there is no existing "Revoke this invite?" string and reusing remove-member copy is semantically wrong. Owner chose **bespoke keys** (matches the per-dialog convention of every other confirm dialog).
- ❌ "SnackBar duration strictly > window is sufficient" — **INSUFFICIENT**; that leaves a zone where Undo is visible but the commit already fired. The robust design makes `_undoDecline` a **no-op if the Timer is already gone** and has `_commitDecline` **dismiss the SnackBar** when it fires (see Real Scope (b)).
- ❌ "build-skew" — **REFUTED**; handlers are on HEAD; the dirty tree is unrelated Feed/Orbit work.

## Real Scope
In scope:
- **(a) REVOKE pre-confirm** — add `Future<void> _confirmRevokeInvite(GroupMember member)` to `group_info_wired.dart` (mirroring `_confirmRoleChange` `:1549`): `if (!mounted) return;` → `showDialog<bool>` → `AlertDialog` with `title: Text(l10n.group_info_revoke_invite_title(name))`, `content: Text(l10n.group_info_revoke_invite_body)`, `TextButton(key: ValueKey('group-revoke-cancel'), child: Text(l10n.btn_cancel))`, `FilledButton(key: ValueKey('group-revoke-confirm'), child: Text(l10n.group_info_revoke_invite_action))`; on `true` → `await _onRevokeInvite(member)`. Swap the build call site (`:2282`) from `_onRevokeInvite` → `_confirmRevokeInvite` (condition `canManageGroup && widget.inviteDeliveryAttemptRepo != null` unchanged). **No Undo.**
- **(b) DECLINE optimistic + Undo — applied identically to BOTH surfaces.** Per surface (`group_list_wired` and `orbit_wired`):
  - `@visibleForTesting static const kDeclineUndoWindow = Duration(seconds: 4)`.
  - `final Set<String> _optimisticallyDeclinedInviteIds = <String>{}` — **filtered inside the loader** (group_list `_loadGroups` `:157-159`; orbit `_loadPendingGroupInvites` `:616-618`): add `&& !_optimisticallyDeclinedInviteIds.contains(invite.groupId)` so all reactive triggers respect the hide.
  - `final Map<String, Timer> _declineCommitTimers = <String, Timer>{}` — per-invite Timer; cancelled on Undo and in `dispose`.
  - Extend the surface's `_showSnackBar` with an optional `SnackBarAction? action` param (group_list already has `{Duration? duration}` at `:637`; orbit's is String-only at `:1371` and must gain both `duration` and `action`).
  - Rewrite `_onDeclinePendingInvite` to run **synchronously** (no `await` in this method body): keep the existing re-entrancy guard; `setState` to add the groupId to **both** `_processingInviteIds`/`_processingPendingInviteIds` **and** `_optimisticallyDeclinedInviteIds`; show the "Invite declined" snackbar (`l10n.group_invite_declined`) with `SnackBarAction(label: l10n.feed_undo, onPressed: () => _undoDecline(invite))` and `duration: kDeclineUndoWindow + const Duration(seconds: 1)`; start `_declineCommitTimers[invite.groupId] = Timer(kDeclineUndoWindow, () => _commitDecline(invite))`. Do **not** clear the processing-id here.
  - `_undoDecline(PendingGroupInvite invite)`: `final timer = _declineCommitTimers.remove(invite.groupId); if (timer == null) return;` (**no-op if already committed/cancelled** — closes the late-tap race) → `timer.cancel()` → `setState` to drop the groupId from `_optimisticallyDeclinedInviteIds` + the processing set → `ScaffoldMessenger.of(context).hideCurrentSnackBar()` → `emitFlowEvent(layer:'FL', event:'GROUP_INVITE_DECLINE_UNDONE', details:{'surface': '<group_list|orbit>', 'groupId': <short>})` → `await _load…()` to re-surface.
  - `_commitDecline(PendingGroupInvite invite)`: `if (_declineCommitTimers.remove(invite.groupId) == null) return;` (already undone) → `emitFlowEvent('GROUP_INVITE_DECLINE_COMMITTED', {'surface':…,'groupId':…})` → `ScaffoldMessenger.of(context).hideCurrentSnackBar()` → run the existing `declinePendingGroupInvite(...)` body (identity load → use-case → loader reload → result→snackbar for the `notFound`/`expired`/error/failed cases; the optimistic snackbar already covered `success`) wrapped in `try/catch/**finally**`. **The `finally` clears the processing-id AND drops `_optimisticallyDeclinedInviteIds`** (so a throwing commit cannot leak the processing-id forever — see TC-G6). The error path re-surfaces via the loader + shows `group_invite_decline_failed`.
  - `dispose`: `for (final t in _declineCommitTimers.values) t.cancel();` before `super.dispose()` (group_list `:695`; orbit `:1933`). **No commit on dispose** (safe-failure = invite kept; re-mount = implicit undo).
  - **Orbit localization (parity):** replace orbit's hardcoded `'Invite declined'` / `'Invite no longer available'` / `'Invite expired'` / `'Failed to decline invite'` (`:1340/:1343/:1346/:1362`) with `l10n.group_invite_declined` / `group_invite_no_longer_available` / `group_invite_expired` / `group_invite_decline_failed` (all already exist).
- **(c) REMOVE lock** — add a `group_info_wired_test.dart` test asserting the existing `_confirmRemoveMember` pre-confirm dialog (`group-remove-cancel`/`group-remove-confirm`) and that the remove path shows **no** "Undo" `SnackBarAction`. No production change.
- **l10n**: **add 3 bespoke keys** — `group_info_revoke_invite_title` (with `{name}` placeholder, like `group_info_remove_member_title`), `group_info_revoke_invite_body`, `group_info_revoke_invite_action` — in `app_en.arb` (+ `@`-metadata for the placeholder), `app_ar.arb`, `app_de.arb`; run `flutter gen-l10n`. Reuse `btn_cancel` (`:337`), `feed_undo` (`:1219`), and the four decline-result keys. No DB migration.
- **Harness**: add `test/features/groups/presentation/group_info_wired_test.dart` AND `test/features/orbit/presentation/screens/orbit_wired_test.dart` to `GROUP_TESTS` (`run_test_gates.sh:118-136`). `group_list_wired_test.dart` is **already** registered (`:134`).
- **Test infra**: install `debugSetFlowEventSink` (from `flow_event_emitter.dart:37`) in the group_list/orbit wired test `setUp`/`tearDown` (capture payloads to a `List<Map<String,dynamic>>`, clear with `debugSetFlowEventSink(null)` in teardown) so the COMMITTED/UNDONE discriminator is observable. No existing group/orbit presentation test installs it.

Out of scope (owning work named):
- Any change to the **wire idempotency** of the decline-ack or revocation envelope (a true wire-level dedup is a future "invite-ack reliability" session — though the use-case is already idempotent for sequential calls, a concurrent repo-layer race is not in scope).
- REMOVE getting an Undo (impossible per INV-R2 — out forever).
- The **feed orbit-badge** cross-screen count (`feed_wired.dart:543-564`) and **cross-screen** optimistic propagation — accepted transient (≤window), see Blind-Spot Sweep; a shared "optimistic-decline controller" unifying the two surfaces is an explicit could-do (owner chose duplicate-per-surface over a shared refactor to bound blast radius).
- 1:1 / Feed confirmation UX; the terminal-send inline bubble (owned by 144).

## Files To Inspect Next
Production:
- `lib/features/groups/presentation/screens/group_info_wired.dart` — `_confirmRoleChange` `:1549` (template), `_onRevokeInvite` `:2151`, `_revokeInviteMessage` `:2222`, build call site `:2280-2282`, existing `_confirmRemoveMember` `:1302`.
- `lib/features/groups/presentation/screens/group_list_wired.dart` — `_loadGroups` visibleInvites `:157-159`, `_onDeclinePendingInvite` `:576`, `_processingInviteIds` `:109`, `_showSnackBar` `:637`, `dispose` `:695`, reactive triggers `:138/:241/:253/:265/:306`, wired `:718`.
- `lib/features/orbit/presentation/screens/orbit_wired.dart` — `_loadPendingGroupInvites` `:596` (filter `:616-618`), `_onDeclinePendingInvite` `:1314`, `_processingPendingInviteIds` `:252`, `_showSnackBar` `:1371`, `dispose` `:1933`, reactive triggers `:391/:894/:906`, wired `:323`.
- `lib/l10n/app_en.arb` (+ ar/de) — add the 3 revoke keys; existing `feed_undo:1219`, `group_invite_declined:1323`, `group_invite_no_longer_available:1301`, `group_invite_expired:1302`, `group_invite_decline_failed`, `btn_cancel:337`.
Direct tests:
- `test/features/groups/presentation/group_info_wired_test.dart` — revoke test `:2176`; remove confirm at `:594`; harness uses `FakeP2PService` + in-memory repos + `pumpFrames` (real `pump(50ms)`).
- `test/features/groups/presentation/group_list_wired_test.dart` — decline test `:1884`; in-memory repos via `setUp` `:450-456`.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` — locate the existing decline test (taps `pending-group-invite-decline-…`) to rewrite.
Dependency-only context (NOT edited):
- `lib/features/groups/application/decline_pending_group_invite_use_case.dart` (idempotent: `getPendingInvite:36`, notFound `:37-44`, delete `:52`, `_maybeSendDeclineAck:56`/def`:81`, enum `:10`).
- `lib/features/groups/application/revoke_pending_group_invite_use_case.dart` (`sendGroupInviteRevocation` wire send: `:224`/`:242`).
- `lib/features/groups/presentation/widgets/pending_group_invite_card.dart` (row key `pending-group-invite-${groupId}` `:85`, decline key `pending-group-invite-decline-${groupId}` `:161-162`, `isProcessing` disables) — **shared by both surfaces** (`group_list_screen:303-311`, `orbit_screen:846-860`).
- `lib/features/feed/presentation/screens/feed_wired.dart:543-564` (orbit-badge count — sibling surface).
- `lib/core/utils/flow_event_emitter.dart` (`debugSetFlowEventSink:37`, `emitFlowEvent:202` — sink fires before the `flowEventLoggingEnabled` gate, so it works in tests).

## Existing Tests Covering This Area
- `group_info_wired_test.dart:2176` "C: revoking a pending invite sends a revocation carrying the persisted invite_id (HOLE-4) and marks the row revoked" — taps `group-member-revoke-invite-peer-alice`, asserts `sendMessageCallCount == 1` immediately. PASSES on HEAD. **Rewrite** to tap→assert dialog + `sendMessageCallCount == 0` → tap `group-revoke-confirm` → `== 1` + row revoked.
- `group_list_wired_test.dart:1884` "declining a pending invite removes the row without joining" — taps decline, asserts `getPendingInvite==null` + row gone + "Invite declined" **immediately**. PASSES on HEAD. **Rewrite** to: row hidden immediately but `getPendingInvite != null` until the window elapses; after `pump(kDeclineUndoWindow + 1s)` → deleted + "Invite declined" still shown.
- `orbit_wired_test.dart` (existing decline test) — same immediate-commit shape. **Rewrite** mirroring the group_list optimistic/commit contract.
- `group_info_screen_test.dart:213-266` (line 239 = the `onRevokeInvite` callback capture) — SCREEN-layer forward. PASSES; WIRED-layer confirm insertion does not touch it → **preservation sentinel**.
- `group_remove_member_roundtrip_test.dart` — remove round-trip (irreversible). PASSES; **preservation sentinel**.
- Remove confirm flow at `group_info_wired_test.dart:594` (taps `group-remove-confirm`). PASSES; reused by the new remove lock test.

Missing coverage gaps: revoke **pre-confirm**; decline **optimistic-hide** (×2 surfaces); decline **Undo cancels commit** (×2); decline **re-entrant reload does not re-surface** (×2); decline **dispose/re-mount cancels commit** (×2); decline **throwing-commit releases the processing-id** (×2); decline **exactly-once under double-tap** (×2); orbit decline **localized** copy; remove **stays pre-confirm-no-Undo** lock.

Already in curated family arrays?: `group_list_wired_test.dart` ✅ (`run_test_gates.sh:134`), `letter_card_test.dart` ✅, `group_conversation_*_test.dart` ✅. **`group_info_wired_test.dart` ❌** and **`orbit_wired_test.dart` ❌** (no ORBIT family exists; orbit runs via host-all glob only). → **two registration steps.**

## RED Test Catalog  (add/rewrite BEFORE any production code — INV-RED-FIRST)

> Flow-event assertions below require the `debugSetFlowEventSink` capture installed in `setUp`. Timer-window assertions use a single `await tester.pump(kDeclineUndoWindow + const Duration(seconds: 1))` (a `pump(duration)` advances the test fake-clock and fires the `Timer`); the optimistic-hide assertions run after `pumpFrames(tester, count: …)` only (≪ window).

**REVOKE (group_info_wired):**
1. `group_info_wired_test.dart`::"revoke shows a pre-confirm dialog and sends only after confirm"  *(rewrite of `:2176`)*
   - Tier: integration/widget (wired screen, in-memory repos + `FakeP2PService(sendMessageResult:true)`).
   - RED on HEAD: HEAD `_onRevokeInvite` fires on the raw tap → asserting `find.byKey(ValueKey('group-revoke-confirm')) findsOneWidget` AND `sendMessageCallCount == 0` right after the tap **fails** (HEAD already sent, count==1, no dialog).
   - GREEN: after tapping revoke → dialog present + `sendMessageCallCount == 0`; tap `group-revoke-cancel` → still 0, row unchanged; tap revoke→`group-revoke-confirm` → `== 1` + row flips `revoked` (original `:2176` assertions). **No** "Undo" `SnackBarAction` ever (`find.widgetWithText(SnackBarAction, l10n.feed_undo) findsNothing`).
   - Mutation: revert call site `:2282` → `_onRevokeInvite` → fires on tap, no dialog → red.
   - Discriminator: the `sendMessageCallCount == 0` pre-confirm gate (load-bearing, not "a dialog widget exists").

**REMOVE (group_info_wired):**
2. `group_info_wired_test.dart`::"remove member stays a pre-confirm dialog with no Undo (lock)"
   - Tier: integration/widget. RED on HEAD: n/a (lock; reds only under its mutation).
   - GREEN: tapping remove shows `group-remove-cancel` + `group-remove-confirm`; `member_removed` not broadcast until `group-remove-confirm`; **no** `SnackBarAction` labelled `feed_undo` at any point.
   - Mutation: bypass `_confirmRemoveMember` (wire build call site to `_onRemoveMember`) → fires on tap, no dialog → red.

**DECLINE — group_list_wired:**
3. `group_list_wired_test.dart`::"declining optimistically hides the row but keeps the invite until the undo window elapses"  *(rewrite of `:1884`)*
   - RED on HEAD: HEAD deletes immediately; asserting right after tap that the row is hidden AND `getPendingInvite(groupId) != null` fails (already null on HEAD).
   - GREEN: immediately post-tap → row hidden (`find.byKey(ValueKey('pending-group-invite-$groupId')) findsNothing`) + `getPendingInvite != null` + Undo `SnackBarAction` visible; after `pump(window+1s)` → `getPendingInvite == null` + "Invite declined" shown + row stays gone + one `GROUP_INVITE_DECLINE_COMMITTED{surface:group_list}`.
   - Mutation: restore the immediate `await declinePendingGroupInvite(...)` in `_onDeclinePendingInvite` → invite null immediately → "still non-null right after tap" reds.
4. `group_list_wired_test.dart`::"undo cancels the decline — invite re-surfaces, ack never sent, never committed"
   - Shape: tap decline; tap Undo before the window; pump well past the window.
   - RED on HEAD: no Undo action; invite already deleted → asserting Undo present + invite re-surfaced fails.
   - GREEN: after Undo → `getPendingInvite != null`, row visible again; after `pump(window+1s)` the invite is **still** present; `FakeP2PService` decline-ack send count == **0**; sink shows `GROUP_INVITE_DECLINE_UNDONE{group_list}` **AND NOT** `…_COMMITTED`.
   - Mutation: drop `timer.cancel()` (or the `_declineCommitTimers.remove`) in `_undoDecline` → commit still fires → invite null → red.
   - Discriminator: `UNDONE` emitted AND `COMMITTED` not (both otherwise touch `_loadGroups`); ack-send-count==0 proves the irreversible side-effect was averted.
5. `group_list_wired_test.dart`::"re-entrant load does not re-surface a hidden row; double-tap commits exactly once"
   - Shape: tap decline; fire a `pendingInviteStream`/`groupMessageStream` event forcing a re-entrant `_loadGroups`; tap decline again rapidly (same frame, no pump); pump past the window.
   - RED on HEAD: n/a pre-feature; **mutation-verifiable** two ways (companion mutations below).
   - GREEN: after the re-entrant load the row stays hidden (filter respected); exactly **one** `GROUP_INVITE_DECLINE_COMMITTED{group_list}`; exactly one decline-ack send; the second tap was a no-op.
   - Mutation A (re-surface): drop the `_optimisticallyDeclinedInviteIds` exclusion in `_loadGroups` `:157-159` → reactive load repaints the hidden row → row-hidden assertion reds.
   - Mutation B (double-commit): remove the `_processingInviteIds.contains` re-entry guard → the second tap schedules a second `Timer` → two `_commitDecline` → `COMMITTED` count == 2 → red. *(Proves the held processing-id — not a separate latch — is the once-only guard.)*
6. `group_list_wired_test.dart`::"disposing / re-mounting during the undo window cancels the pending commit (invite kept, no stray commit)"
   - Shape: tap decline; `tester.pumpWidget(const SizedBox())` (dispose) before the window; pump past the window.
   - RED on HEAD: n/a pre-feature; mutation-verifiable.
   - GREEN: no "setState after dispose" exception; `getPendingInvite != null`; **no** `GROUP_INVITE_DECLINE_COMMITTED` after unmount.
   - Mutation: drop the `_declineCommitTimers` cancellation in `dispose` `:695` → Timer fires post-unmount → red (exception / stray commit).
7. `group_list_wired_test.dart`::"a throwing commit releases the processing-id and re-surfaces the invite (finally cleanup)"
   - Shape: inject an `identityRepo`/use-case dependency that throws inside the deferred commit; tap decline; pump past the window.
   - RED on HEAD: n/a pre-feature; mutation-verifiable.
   - GREEN: after the throw → `group_invite_decline_failed` snackbar + invite re-surfaced (`getPendingInvite != null`, row visible) + `groupId` **not** stuck in `_processingInviteIds` (a second decline of the same row is accepted, not silently dropped).
   - Mutation: move the processing-id cleanup out of `_commitDecline`'s `finally` → the id leaks → the second decline returns early → "row can be re-declined" reds.

**DECLINE — orbit_wired (parity):**
8. `orbit_wired_test.dart`::"declining optimistically hides the row but keeps the invite until the window elapses"  *(rewrite of the existing orbit decline test)* — mirrors TC-3; mutation = restore immediate `await`.
9. `orbit_wired_test.dart`::"undo cancels the decline — invite re-surfaces, ack never sent, never committed" — mirrors TC-4; `GROUP_INVITE_DECLINE_UNDONE{surface:orbit}`; mutation = drop `timer.cancel()`.
10. `orbit_wired_test.dart`::"re-entrant load does not re-surface; dispose cancels the pending commit" — folds TC-5A + TC-6 for orbit (filter at `:616-618`; dispose `:1933`); mutations = drop the optimistic exclusion / drop the dispose cancel.
11. `orbit_wired_test.dart`::"orbit decline snackbars are localized" — pump the wired screen under a **non-English** locale wrapper (e.g. `de`); tap decline; assert the localized "Invite declined" string (German) appears, not the old hardcoded English. Mutation: revert orbit `:1340` to the hardcoded `'Invite declined'` → under `de` the localized assertion reds.

## Test Coverage Matrix  (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-1 revoke pre-confirm (no Undo) | dialog gate + send-after-confirm | integration/widget | group_info_wired_test::"revoke shows a pre-confirm dialog…" | HEAD sends on raw tap, no dialog (count==1) | revert call site `:2282` → `_onRevokeInvite` | `./scripts/run_test_gates.sh groups` | **add group_info_wired_test to GROUP_TESTS** |
| TC-2 remove stays pre-confirm-no-Undo | lock | integration/widget | group_info_wired_test::"remove member stays a pre-confirm dialog with no Undo (lock)" | n/a (lock; reds under mutation) | bypass `_confirmRemoveMember` → direct `_onRemoveMember` | `./scripts/run_test_gates.sh groups` | add group_info_wired_test to GROUP_TESTS |
| TC-3 group_list optimistic-hide, invite kept till window | optimistic state + deferred commit | integration/widget | group_list_wired_test::"declining optimistically hides the row…" | HEAD deletes immediately; "hidden but still present" fails | restore immediate `await declinePendingGroupInvite` | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS (:134) |
| TC-4 group_list Undo cancels commit + no ack | undo path + ack-averted discriminator | integration/widget | group_list_wired_test::"undo cancels the decline…" | no Undo on HEAD; invite already deleted | drop `timer.cancel()`/`_declineCommitTimers.remove` in `_undoDecline` | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS |
| TC-5 group_list re-entrant-no-resurface + double-tap once | filter + once-only via held processing-id | integration/widget | group_list_wired_test::"re-entrant load does not re-surface…" | post-feature; mutation-verifiable | A: drop `_optimisticallyDeclinedInviteIds` filter; B: drop `_processingInviteIds` re-entry guard | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS |
| TC-6 group_list dispose/re-mount cancels commit | lifecycle safety | integration/widget | group_list_wired_test::"disposing / re-mounting during the undo window…" | post-feature; mutation-verifiable | drop `_declineCommitTimers` cancel in `dispose` `:695` | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS |
| TC-7 group_list throwing-commit releases processing-id | finally cleanup / no permanent stuck row | integration/widget | group_list_wired_test::"a throwing commit releases the processing-id…" | post-feature; mutation-verifiable | move processing-id cleanup out of `_commitDecline` `finally` | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS |
| TC-8 orbit optimistic-hide, invite kept | optimistic state (parity) | integration/widget | orbit_wired_test::"declining optimistically hides the row…" | HEAD deletes immediately | restore immediate `await` in orbit `_onDeclinePendingInvite` | `./scripts/run_test_gates.sh groups` | **add orbit_wired_test to GROUP_TESTS** |
| TC-9 orbit Undo cancels commit + no ack | undo path (parity) | integration/widget | orbit_wired_test::"undo cancels the decline…" | no Undo on HEAD | drop `timer.cancel()` in orbit `_undoDecline` | `./scripts/run_test_gates.sh groups` | add orbit_wired_test to GROUP_TESTS |
| TC-10 orbit re-entrant-no-resurface + dispose | filter + lifecycle (parity) | integration/widget | orbit_wired_test::"re-entrant load does not re-surface; dispose cancels…" | post-feature; mutation-verifiable | drop orbit optimistic exclusion `:616-618` / drop orbit dispose cancel `:1933` | `./scripts/run_test_gates.sh groups` | add orbit_wired_test to GROUP_TESTS |
| TC-11 orbit decline snackbars localized | l10n parity | integration/widget | orbit_wired_test::"orbit decline snackbars are localized" | under a `de` wrapper HEAD shows hardcoded English → the German-string assertion fails on HEAD | revert orbit `:1340` to hardcoded `'Invite declined'` | `./scripts/run_test_gates.sh groups` | add orbit_wired_test to GROUP_TESTS |

## Blind-Spot Sweep  (evergreen classes — row added OR justified)
- **Lifecycle / derived-state durability** — the optimistic sets + Timers are in-memory; a full re-mount / process-restart mid-window drops them. Because `dispose` cancels the Timer **without** committing and the repo still holds the invite, a re-mount **re-surfaces the invite undeleted** (navigate-away = implicit safe undo). → **TC-6 / TC-10** assert dispose-mid-window keeps the invite + emits no COMMITTED; the re-mount path is the same mechanism (Timer cancelled, no persisted derived state to reconstruct). No persisted derived state ⇒ no reopen-reconstruction obligation.
- **Sibling-surface consistency** — decline now exists on **two** wired surfaces (group_list + orbit), **both covered** (TC-3..7 / TC-8..11). The **feed orbit-badge** (`feed_wired.dart:543-564`) is repo-authoritative and during the ≤`kDeclineUndoWindow` window will transiently over-count by 1 (row hidden in-memory, repo not yet deleted); it self-corrects on commit (repo delete → badge drops) and on undo (repo never changed → badge already correct). **Accepted transient**, documented (Accepted Differences). Cross-screen optimistic state is **not** shared (each surface owns its set) → a decline started on one surface is still visible on the other until commit (≤window). Accepted.
- **Destructive-action side-effects** — the single irreversible effect of decline is the **decline-ack to the inviter** (`_maybeSendDeclineAck`). → **TC-4 / TC-9** assert the `FakeP2PService` decline-ack send count is **0** while the window is open and on Undo, and exactly **1** after a real commit. (Removal side-effects of REMOVE are unchanged and locked by the preservation sentinel.)
- **Invariant re-verification under new transitions** — the new optimistic→committed and optimistic→undone transitions must survive reactive reload, app-resume, and a concurrent decline/accept of **another** invite. → **TC-5 / TC-10** force a reactive `_loadGroups`/`_loadPendingGroupInvites` mid-window; the per-invite keying (sets/Timers keyed by `groupId`) guarantees declining/undoing A leaves B untouched (asserted by the row-B-still-visible check inside TC-5). Multi-invite SnackBar replacement is an accepted UX limitation (see Risks).

## Invariants (locked by tests)
- INV-1: REVOKE puts **nothing** on the wire until the pre-confirm dialog is confirmed (`sendMessageCallCount == 0` pre-confirm) → TC-1.
- INV-2: REVOKE offers **no Undo** → TC-1.
- INV-3: DECLINE hides the row **optimistically** while keeping the local invite until `kDeclineUndoWindow` elapses, on **both** surfaces → TC-3 / TC-8.
- INV-4: DECLINE **Undo** cancels the commit; the invite re-surfaces, the decline-ack is **never sent**, and `…_COMMITTED` is never emitted → TC-4 / TC-9.
- INV-5: DECLINE commits **exactly once** — a re-entrant reload never re-surfaces a hidden row and never double-fires; double-tap is blocked by the held processing-id (`…_COMMITTED == 1`, ack == 1) → TC-5 / TC-10.
- INV-6: DECLINE never commits **after dispose / re-mount** (safe-failure = invite kept) → TC-6 / TC-10.
- INV-7: A **throwing** deferred commit releases the processing-id and re-surfaces the invite (no permanently-stuck row) → TC-7.
- INV-8: REMOVE keeps its pre-confirm dialog and offers **no Undo** → TC-2.
- INV-9: Orbit decline result snackbars are **localized** (no hardcoded English) → TC-11.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short`. Install the `debugSetFlowEventSink` capture in the group_list + orbit wired test `setUp`/`tearDown`. Add/rewrite the 11 RED tests; run the focused cmds; confirm each fails for its documented reason (TC-1/3/4/8/9/11 RED on HEAD; TC-2 lock passes-on-HEAD-reds-under-mutation; TC-5/6/7/10 mutation-verifiable).
2. l10n: add `group_info_revoke_invite_title`/`_body`/`_action` to `app_en.arb` (+ `@`-metadata for the `{name}` placeholder), `app_ar.arb`, `app_de.arb`; `flutter gen-l10n`.
3. `group_info_wired.dart`: add `_confirmRevokeInvite(GroupMember)` mirroring `_confirmRoleChange` (`if (!mounted) return;` + `showDialog<bool>` + keys `group-revoke-cancel`/`group-revoke-confirm`); on `true` → `await _onRevokeInvite(member)`. Swap build call site `:2282` `_onRevokeInvite` → `_confirmRevokeInvite`.
4. `group_list_wired.dart`: add `kDeclineUndoWindow`, `_optimisticallyDeclinedInviteIds`, `_declineCommitTimers`; extend `_showSnackBar` with `SnackBarAction? action`; extend `visibleInvites` filter (`:157-159`) to exclude the optimistic set; rewrite `_onDeclinePendingInvite` (synchronous: setState both sets, snackbar+Undo, start Timer); add `_undoDecline` (no-op-if-timer-gone) + `_commitDecline` (timer-gone guard → emit COMMITTED → hide snackbar → use-case body in try/catch/**finally**-cleanup); cancel Timers in `dispose` `:695`. **No `_committedDeclineInviteIds` latch.**
5. `orbit_wired.dart`: mirror step 4 against `_loadPendingGroupInvites` filter (`:616-618`), `_processingPendingInviteIds`, dispose `:1933`; extend `_showSnackBar` (`:1371`) with `duration` + `action`; **localize** the four decline snackbars.
   Stop-if: orbit's list is published via `_publishListProjection()` — ensure the optimistic exclusion is applied where the projected list is built (the loader filter `:616-618`), not only in a transient local. Re-run the reactive-reload TC to confirm no flash-back.
6. `scripts/run_test_gates.sh`: add `test/features/groups/presentation/group_info_wired_test.dart` AND `test/features/orbit/presentation/screens/orbit_wired_test.dart` to `GROUP_TESTS` (`:118-136`). (`group_list_wired_test.dart` already present `:134`.)
7. Rerun direct → preservation → named gates; `flutter analyze`; `git diff --check`.

## Risks And Edge Cases
- **Late Undo race** (Undo tapped just as the Timer fires): `_undoDecline` no-ops when `_declineCommitTimers.remove(groupId) == null`, and `_commitDecline` hides the snackbar on fire → the Undo affordance disappears at commit and a late tap is a safe no-op. Pinned implicitly by TC-4/TC-9 (Undo-before-window) + the no-op guard; do **not** rely on "duration strictly > window" alone.
- **Throwing deferred commit leaking the processing-id** → row permanently un-declinable. Pinned by the `finally` cleanup → TC-7.
- **Re-surface race** (reactive reloads repaint the hidden row) → the optimistic filter inside each loader → TC-5 / TC-10.
- **Commit-after-dispose** (Timer touches a disposed State) → `dispose` cancels all Timers → TC-6 / TC-10.
- **Multi-invite SnackBar replacement**: only one SnackBar shows at a time; declining a second invite within the window replaces the first SnackBar, so the first invite's Undo affordance vanishes early — but its Timer still commits correctly after its own window (per-`groupId` Timer). **Accepted UX limitation** (rare); data-layer correctness (each commits exactly once, sets are per-invite) is locked by the per-`groupId` keying in TC-5.
- **`debugSetFlowEventSink` global**: install in `setUp`, clear (`debugSetFlowEventSink(null)`) in `tearDown` so it does not leak across tests in the same file/run.
- **fakeAsync vs Timer**: window tests use a single `await tester.pump(kDeclineUndoWindow + const Duration(seconds: 1))` (the test binding fires the `Timer` when the fake clock advances past it); the existing `pumpFrames(count:20)` = 1000 ms ≪ 4 s, which is why the rewritten TC-3/TC-8 see "not yet committed".

## Device/Relay Proof Profile
host-only for closure. No OS-boundary / ML-KEM / relay / multi-device leg — the confirm dialog, optimistic hide, Undo Timer, and deferred commit are local screen-state + a Dart `Timer`. The revoke/decline **wire** sends are pre-existing and already proven by their owning sessions; this unit only gates *when* they fire. No migration, no feature flag. Deferred device work → none.

## Acceptance Gates  (literal — copy/paste)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/groups/presentation/group_info_wired_test.dart \
  --plain-name 'revoke shows a pre-confirm dialog and sends only after confirm'
flutter test test/features/groups/presentation/group_list_wired_test.dart \
  --plain-name 'declining optimistically hides the row but keeps the invite'
flutter test test/features/groups/presentation/group_list_wired_test.dart \
  --plain-name 'undo cancels the decline'
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart \
  --plain-name 'declining optimistically hides the row but keeps the invite'

# l10n regenerated after adding the 3 revoke keys
flutter gen-l10n

# Direct GREEN (after fix)
flutter test test/features/groups/presentation/group_info_wired_test.dart
flutter test test/features/groups/presentation/group_list_wired_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart

# Preservation sentinels (must stay green)
flutter test test/features/groups/presentation/group_info_screen_test.dart   # onRevokeInvite screen-forward :213-266 unchanged
flutter test test/features/groups/group_remove_member_roundtrip_test.dart     # remove round-trip unchanged

# Named gate (after adding group_info_wired_test + orbit_wired_test to GROUP_TESTS)
./scripts/run_test_gates.sh groups   # prior green + the 11 new cases; the 2 PRE-EXISTING group wired fails (GMAR-004 reopen-hydration, incoming-group-image-refresh) + any PRE-EXISTING orbit-invite flakes are NOT mine

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: TC-1/3/4/8/9 before the fix; TC-11 under `de` locale pre-fix; TC-2 is a lock (passes on HEAD, reds under its bypass mutation); TC-5/6/7/10 mutation-verifiable.
- Pre-existing dirty (NOT mine): the Groups suite has **2 PRE-EXISTING failing wired tests** — `GMAR-004` reopen-hydration and incoming-group-image-refresh — and adding `orbit_wired_test.dart` to the gate may surface **pre-existing orbit-invite flakes** (noted in prior sessions). Record the baseline before execution; do not "fix" by reverting.
- The wider tree is already dirty on `new-feed` (uncommitted Feed/Orbit work) — snapshot `git status --short` first; touch only Real-Scope files.
- Environment blocker (NOT product): none (host-only).
- Scope drift (BLOCKING): any failure outside the listed files/tests.

## Done Criteria
- [ ] RED added/rewritten first, failed for the expected reason (TC-1/3/4/8/9/11); TC-2 lock + TC-5/6/7/10 mutation-reds confirmed.
- [ ] Each fix mutation-verified (re-red revert named in the matrix); the **dropped** `_committedDeclineInviteIds` latch is confirmed absent (no dead non-mutation-verifiable guard).
- [ ] Direct GREEN (`group_info_wired_test`, `group_list_wired_test`, `orbit_wired_test`) + preservation sentinels (`group_info_screen_test:213-266`, `group_remove_member_roundtrip_test`) pass; the 2 pre-existing group fails + any pre-existing orbit flakes unchanged.
- [ ] No DB migration (pure presentation + a Dart Timer).
- [ ] 3 bespoke revoke l10n keys present in en/ar/de + `flutter gen-l10n` run; orbit decline snackbars localized.
- [ ] **`group_info_wired_test.dart` AND `orbit_wired_test.dart`** added to `GROUP_TESTS` and confirmed running under `./scripts/run_test_gates.sh groups` (`group_list_wired_test.dart` already present).
- [ ] `flutter analyze` 0-new; `git diff --check` clean.

## Scope Guard (hard "Do not")
- Do not add a DB migration or bump the identity DB version.
- Do not give REVOKE or REMOVE an Undo (irrevocable on the wire / by INV-R2).
- Do not re-introduce a `_committedDeclineInviteIds` latch — the use-case is already idempotent and the held `_processingInviteIds` + one-shot Timer make `_commitDecline` once-only; a redundant latch is non-mutation-verifiable.
- Do not commit the decline on dispose (safe-failure = invite kept).
- Do not clear the processing-id before the deferred commit/undo resolves; do not move the commit cleanup out of the `finally`.
- Do not move the optimistic-hide filter out of the loader (`group_list:157-159` / `orbit:616-618`) — it must guard every reactive trigger.
- Do not touch the decline-ack/revocation **wire idempotency**, the use-case result enums, or 1:1/Feed confirmation UX.

## Accepted Differences / Intentionally Out Of Scope
- The decline commit-once is enforced at the **UI** layer by the held `_processingInviteIds` + one-shot Timer; the use-case is **already** idempotent for sequential calls (a concurrent repo-layer race is not addressed here — future "invite-ack reliability" session).
- The two decline surfaces use **duplicated** per-screen logic rather than a shared controller (owner choice — bounds blast radius for a HIGHEST-RISK unit). A shared "optimistic-decline" mixin is a could-do follow-up.
- The **feed orbit-badge** (`feed_wired:543-564`) may transiently over-count by 1 for ≤`kDeclineUndoWindow`; repo-authoritative, self-corrects on commit/undo. Cross-screen optimistic state is per-surface (not shared). Accepted.
- Multi-invite SnackBar replacement (second decline within the window hides the first invite's Undo affordance early) — accepted; data-layer correctness preserved.
- REVOKE confirm copy is **bespoke** (new keys) per the per-dialog convention; tests key on `group-revoke-confirm`/`group-revoke-cancel`, not on copy.
- REMOVE keeps its existing dialog verbatim (lock only).

## Dependency Impact
- None outbound. The harness-registration fix (adding `group_info_wired_test.dart` + `orbit_wired_test.dart` to `GROUP_TESTS`) retroactively gates ALL pre-existing revoke/decline/remove/role/dissolve **and orbit pending-invite** wired behavior under the curated Group gate — a standalone hardening win (these suites currently run only via host-all glob).

## Reviewer Findings
Source-verified review (2026-06-23, 5-agent verify→refute workflow + direct source reads) found the v1 plan **structurally sound in intent but materially wrong in fact**; revised in place. Blocking corrections applied:
1. **Root cause wrong** — decline use-case is already idempotent (`getPendingInvite==null` short-circuit before delete before ack). The "double-ack hazard" framing and the `_committedDeclineInviteIds` latch are removed; the once-only guard is re-grounded on the held `_processingInviteIds` + one-shot Timer, with a real flow-event-sink discriminator.
2. **Missing second surface** — `orbit_wired._onDeclinePendingInvite` (:1314) is an identical un-deferred decline with hardcoded English snackbars; owner chose **parity** → orbit now in scope (TC-8..11) incl. localization.
3. **Stale anchors** — every `group_list_wired` line number was ~81 lines off; all corrected and re-verified.
4. **Harness claim wrong** — `group_list_wired_test.dart` is already in `GROUP_TESTS`; only `group_info_wired_test.dart` + `orbit_wired_test.dart` need adding.
5. **New risks pinned** — late-Undo race (no-op-if-timer-gone), throwing-commit processing-id leak (`finally`), SnackBar-vs-window, feed-badge sibling surface.
6. **l10n** — bespoke revoke keys (owner choice) replace the "no new keys" stance.
Remaining for the sufficiency reviewer: confirm the orbit test-harness can pump the orbit wired screen with in-memory invite repos (mirror group_list's `setUp`) and that a `de`-locale wrapper is available for TC-11.

## Arbiter Decision
APPROVED & EXECUTED (2026-06-23). Plan was structurally sound; two source-corrections applied at execution: (1) orbit had **no** existing decline test → TC-8..11 authored fresh (the accept test was the template); (2) `_onDeclinePendingInvite` made `void` (both screen callbacks are `void Function(PendingGroupInvite)?`) rather than `Future<void> async`-no-await. Exactly-once is enforced by **per-`groupId` timer keying + the `_declineCommitTimers.remove()==null` guard** (a re-fire/double-tap is a no-op) — stronger than the plan's processing-id-only framing; the held `_processingInviteIds` remains the re-entry guard. Tests pin window timing with a literal `Duration(seconds: 5)` (= window 4s + 1s) to keep the test files compilable on HEAD for a clean behavioral RED.

## Final Execution Verdict
**IMPLEMENTED — host-green (2026-06-23).** RED-first honoured; all 11 cases pass; every fix mutation-verified.

Results:
- **Direct GREEN:** `group_info_wired_test` **68/68** (TC-1 revoke pre-confirm rewrite + TC-2 remove lock added), `group_list_wired_test` **41/41** (TC-3 rewrite + TC-4/5/6/7), `orbit_wired_test` **64 pass / 3 pre-existing ACCEPT flakes** (TC-8/9/10/11 all pass).
- **Mutation-verified:** RED-on-HEAD proves TC-1/3/4/8/9/11; explicit revert→red for TC-2 (bypass `_confirmRemoveMember`), TC-5A (drop loader filter), TC-6 (drop dispose cancel), TC-7 (drop finally processing-id cleanup), TC-10 (drop orbit dispose cancel). All reverted/re-green. No leftover markers.
- **Preservation sentinels GREEN:** `group_info_screen_test` 22/22, `group_remove_member_roundtrip_test` 1/1.
- **Hygiene:** `flutter analyze` **0 new** (4 pre-existing infos live only in untouched `group_info_wired` lines; the 2 decline files + the 2 decline test files are issue-free); `git diff --check` clean; no DB migration; 3 bespoke revoke l10n keys in en/ar/de + `flutter gen-l10n`; orbit decline snackbars localized.
- **Named gate** `./scripts/run_test_gates.sh groups` = +617/-6, but **all 6 failures are PRE-EXISTING, none from 153**: `group_conversation_wired_test.dart` + `group_resume_recovery_test.dart` carry a concurrent **plan-152 `micPermissionGateway` compile error** (their prod param doesn't exist yet) which crashes the shared host-batch compiler and cascades a "loading [E]" to siblings (`group_messaging_smoke` passes **88/88 in isolation**); plus the **3 pre-existing orbit ACCEPT flakes** (A2 / EK011 / clears-spinner — baselined, unrelated to decline). Every 153 test RAN and PASSED inside the gate. Per Scope Guard the 152 files were NOT touched.

Execution deviations from plan (source-corrected):
- Orbit had **no** existing decline test → TC-8..11 authored fresh (accept test = template); added optional `Locale` param to `buildOrbitWired` for TC-11 + `ensureVisible` (the longer German layout pushed the decline control under the nav bar).
- `_onDeclinePendingInvite` made **`void`** on both surfaces (the screen callbacks are `void Function(PendingGroupInvite)?`).
- **Exactly-once** is enforced by per-`groupId` timer keying + the `_declineCommitTimers.remove()==null` guard (a re-fire / double-tap is a no-op) — strictly stronger than the plan's processing-id-only framing; `_processingInviteIds` stays as the re-entry guard. Hence TC-5's load-bearing mutation is the loader-filter (5A), not the re-entry guard.
- Tests pin the window with a literal `Duration(seconds: 5)` (window 4s + 1s) to keep test files compilable on HEAD for a clean behavioral RED.

Adversarial review (23-agent verify→refute workflow): 20 raw findings → 11 "confirmed" → triaged against real control flow. **Zero real blocker/major in the 153 code.** Disposed-notifier "blocker" (orbit `_loadPendingGroupInvites`) is a FALSE POSITIVE — no `await` between the `if(!mounted)return` and `_publishListProjection()`, and the null-branch republish is unreachable mid-decline (listener is a non-null final field; reactive subs cancelled in dispose). "Missing publish after reload" is a double-fault-only transient that self-heals on the next reactive reload and is identical on group_list (not orbit-specific). Late-Undo no-op, no-undo-confirmation, and per-surface coverage are accepted-by-design per the plan. **One genuine test-coverage gain applied:** TC-11 now also asserts the localized Undo label (`Rückgängig`).

Deferred / not-mine: the `groups` gate cannot go fully green until concurrent plan-152 lands `micPermissionGateway` on the conversation screens (out of 153 scope). The 3 orbit ACCEPT flakes pre-date this unit.

### Review follow-up — P1/P2 (2026-06-23, post-review)
Two real lifecycle defects flagged in a second review, fixed RED-first on **both** surfaces:
- **P1 (crash):** the decline SnackBar lives on the app-level messenger and outlives the screen; `dispose` cancelled timers but did NOT clear `_declineCommitTimers` or dismiss the SnackBar, so a stale Undo tapped after teardown passed `_undoDecline`'s `timer != null` guard and hit `setState` on a dead State → `setState() called after dispose()`. Fix: `if (!mounted) return` atop `_undoDecline`, `dispose` now clears the map AND dismisses the SnackBar via a captured `ScaffoldMessengerState` (`_declineScaffoldMessenger`). RED reproduced via a `ValueNotifier` toggle that disposes the screen synchronously while the messenger survives (the crash was caught by `takeException`).
- **P2 (stale no-op Undo):** `_commitDecline` removed the timer at the top but only hid the SnackBar in the `finally` after the (possibly slow) use-case + reload, so during a slow commit the Undo lingered as a no-op. Fix: hide the SnackBar immediately at the top of `_commitDecline` when the timer fires. RED reproduced with a `_SlowIdentityRepository` (2s) holding the commit in-flight.
- Tests: group_list **+2** (P1 crash-safe no-op, P2 hide-on-commit) → **43/43**; orbit **+1** (P2 parity, mutation-verified) → **65 pass / 3 pre-existing accept**. Both fixes mutation-verified (RED-on-original + orbit top-hide revert). `analyze` 0-new.
- **Orbit P1 is fixed defensively but not separately tested:** unlike group_list (whose decline SnackBar persists on the root messenger, so the stale tap reproduces the crash), orbit's SnackBar is tied to the orbit Scaffold and is removed when the screen tears down — so the stale-Undo-tap is not reproducible, "no commit post-dispose" is already locked by TC-10, and a parity test would be non-mutation-verifiable (double-guarded by timer-cancel + map-clear). The orbit guards (`!mounted` in `_undoDecline`, dispose map-clear + SnackBar-dismiss) are kept as belt-and-suspenders for embeddings where the SnackBar could outlive the orbit Scaffold.
