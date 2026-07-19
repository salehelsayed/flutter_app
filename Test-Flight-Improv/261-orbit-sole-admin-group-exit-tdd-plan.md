# 261 - Orbit Sole-Admin Group Exit Guidance

Status: execution-ready
Type: Feature Improvement
Spec: `Test-Flight-Improv/orbit-sole-admin-leave-ux-mockup-codex.html`
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-19 11:54 CEST | Evidence Collector | mockup HTML; `Test-Flight-Improv/00-INDEX.md`; Graphify compact context | Allocate Plan 261; the silent sole-admin failure is a real Orbit bug. | Verify the source, tests, and gates behind the proposed recovery paths. |
| 2026-07-19 12:08 CEST | Evidence Collector | Orbit row/handler/widgets; leave/delete/dissolve/role use cases; Group Info wired/screen | The last-admin guard is valid, but Orbit swallows it and its active path bypasses Group Info's signed voluntary-leave workflow. | Design a reusable active-leave action and Orbit-only recovery UI. |
| 2026-07-19 12:17 CEST | Reviewer | invite-status derivation/tests; role distribution; lifecycle rollback; copy/a11y surfaces | A roster row is not proof of joining; local-only delete can fall through to active leave; promotion must not permit leave after incomplete distribution. | Encode causal tests and destructive-state guards. |
| 2026-07-19 review | Independent `$tdd-review` | three bounded audits, current source/tests/gates, and final patched counterexample sweep | Core direction confirmed. Remove the umbrella coordinator/unrelated UX; prepare-sign promotion before mutation; treat native timeout as uncertain; close the existing pending-broadcast lifecycle. | Execute the lean contract below. |
| 2026-07-19 fix-list review | Critical plan reviewer | `261-review-fixlist.md`; current Dart/Go/native sources; tests and gate arrays | Keep the concrete gate and queue checks, but reject the fix-list's blanket offline block, universal `leaveGroup` cleanup, temporary dissolve-only UI, and unrelated identity-state fixture. | Execute the corrected, scoped contract below. |

## Audit Resolution

- The fix-list's open offline decision is resolved from the existing delivery contract: a soft live-topic publish failure does not block leave when the required signed inbox replay is stored for every remaining peer. Inbox/prework failure still blocks before native leave. No self-removal queue or new product decision is needed.
- Pending-row cleanup is guaranteed only at Plan 261's migrated boundaries: the shared active-exit action, committed Orbit dissolve, and strict dissolved-local deletion. Moving it into `leaveGroup` would broaden dependencies yet still miss direct native-leave callers; legacy stuck/remote exits remain explicit debt.
- The temporary “not yet available” dissolve-only slice is rejected. It adds throwaway state/copy and cannot close the final dissolve contract before queue cleanup exists; build the final recovery sheet once.
- The useful test tightening is retained: production-like archived-row exclusivity, first-tap sole-admin wiring, exact `GROUP_TESTS` membership, real pending-row round-trip/non-empty recipients, row-absence unlock, localized getter assertions, and leaner state/a11y checks.

## Problem And Evidence

- Behavior to improve: in Orbit's classic All chats view, swiping an active group exposes **Delete** even though the action first leaves the group. When the current user is the sole admin, confirming it leaves the row in place and shows no explanation or recovery path.
- Confirmed root cause: `_onDeleteGroup` in `lib/features/orbit/presentation/screens/orbit_wired.dart` calls `deleteGroupAndMessages` and only logs the sole-admin `StateError`. `leaveGroup` in `lib/features/groups/application/leave_group_use_case.dart` intentionally blocks the sole admin before bridge or local cleanup.
- Confirmed adjacent gap: Orbit's active path calls bare `deleteGroupAndMessages`, while Group Info first publishes signed self-removal, stores offline replay, rotates the key, handles native-leave failure, and deletes only target history after success (`group_info_wired.dart:447-487,766-893`; `broadcast_voluntary_leave_use_case.dart:60-232`). Orbit must reuse a narrow full active-leave action; a sheet over the current call is insufficient.
- Confirmed successor gap: invitees are rostered before acceptance (`contact_picker_wired.dart:305-341`; `create_group_with_members_use_case.dart:196-218`). A newly selected successor therefore needs current `member_joined` or invite-attempt `joined` evidence. `joinedAt`, a roster row, or an admin-authored add alone is not acceptance.
- Preserved existing-admin policy: the current lower invariant counts authoritative `MemberRole.admin` rows (`leave_group_use_case.dart:25-32`). The mockup restricts eligibility when choosing a **new** admin, not whether an already-existing peer admin counts. This plan does not invent a second legacy-admin policy.
- Confirmed destructive-scope gap: `deleteGroupAndMessages(deleteLocallyIfDissolved: true)` falls through to active `leaveGroup` for active or missing fresh state (`delete_group_and_messages_use_case.dart:23-34`). Its local branch also omits `clearGroupRejoinState`, whose row has no cascade.
- Confirmed delivery-result gap: `callGroupPublish` returns `{ok:false}` on bridge failures/timeouts (`bridge_group_helpers.dart`, `callGroupPublish`). Promotion cannot treat that result as distributed. Voluntary leave is different: after live publish it awaits signed inbox replay for every remaining peer, and `callGroupInboxStore` throws on failure. A soft live-publish failure plus successful inbox replay still has durable peer-delivery custody; inbox failure is the blocking prework failure.
- Confirmed partial-promotion gap: `updateGroupMemberRole` commits the role/native config before signed publish and inbox storage (`update_group_member_role_use_case.dart:205-239`; `group_info_wired.dart:1401-1493`). The existing durable `GroupPendingBroadcast` queue retains an already-signed transition and clears it only after publish plus inbox succeed (`group_pending_broadcast.dart:3-40`; `group_pending_broadcast_repush.dart:11-85`; `group_pending_broadcast_runner.dart:7-67`). Reuse it; do not create another retry framework.
- Confirmed promotion-ordering gap: signing currently happens after the role/config commit (`group_info_wired.dart`, `_onToggleAdminRole`). The role use case already accepts an explicit event time and runs its stale gate before its first write (`update_group_member_role_use_case.dart`, `updateGroupMemberRole`), so the extracted action can prepare/sign first and abort stale instead of leaving an unsigned committed promotion.
- Confirmed rollback gap: Group Info snapshots only the latest and previous keys, then deletes all keys during native-leave rollback (`group_info_wired.dart:788-810,863-892`), while the repository retains eight generations (`group_key_retention_policy.dart:1-7`). Its current sentinel seeds only two.
- Confirmed stage ambiguity: failures before native leave, a definite native rejection, a native timeout, and failures after native success mean different things. `callGroupLeave` wraps the bridge future in `.timeout(...)` and rethrows `TimeoutException` (`bridge_group_helpers.dart:246-294`), so timeout is not proof the underlying operation did not commit. After confirmed `group:leave` success, a later local cleanup error must never be presented or retried as if the user did not leave.
- Confirmed queue-lifecycle gap: `pending_group_broadcasts` has no group foreign key or cascade (`086_pending_group_broadcasts.dart`). Plan-owned committed active leave, Orbit dissolve, and strict local deletion must discard obsolete target-group rows so the foreground runner cannot retry them against a left/deleted group.
- Refuted user theory: being an admin does not prevent leaving. Only being the last admin blocks leaving. Group-wide removal is **Dissolve**; active local removal is **Leave** followed by local-history cleanup.
- Truthful-copy corrections: use “device,” not “phone.” After dissolve, say history already stored on each device remains read-only; do not promise every member received it when `DissolveGroupResult.bridgeError` can represent a replay recovery gap.
- Deliberately deferred: Group Info already shows a visible sole-admin error, and stuck-rejoin Leave is a separate transport-recovery flow with a sibling in Group List. This plan does not replace those sibling UIs with the Orbit recovery sheet; it only gives Orbit's stuck-row catch the same existing localized failure snackbar as Group List.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `e63dcd7d2eb9bfed`; `stale:test/features/conversation/presentation/screens/conversation_wired_test.dart` (unrelated dirty file; review conclusions were verified in current source).
- Review query / profile: `python3 graphify-arch/tdd_context.py query "Plan 261 counterexamples: Orbit _onDeleteGroup DeleteGroupAndMessagesUseCase GroupInfoWired _onToggleAdminRole BroadcastVoluntaryLeaveUseCase last admin successor eligibility group:leave callers rollback strict dissolved local delete orbit_wired_test group_info_wired_test GROUP_TESTS" --profile review --budget 800`.
- Fix-list query / profile: `python3 graphify-arch/tdd_context.py query "Critically verify Test-Flight-Improv/261-review-fixlist.md against Plan 261: updateGroupMemberRole signing eventAt canonicalMembershipEventId GroupPendingBroadcast drain cleanup callGroupLeave TimeoutException nativeLeaveUncertain dissolveGroup deleteGroupAndMessages GROUP_TESTS counterexamples" --profile review --budget 800`.
- Anchors: `_onToggleAdminRole` -> `lib/features/groups/presentation/screens/group_info_wired.dart:1342`; `_onDeleteGroup` -> `lib/features/orbit/presentation/screens/orbit_wired.dart:2744`.
- Targeted source verification added the pending-broadcast queue, full key-retention policy, Group List stuck-rejoin sibling, direct `leaveGroup` callers, and literal gate registrations. The graph was not refreshed for this read-only review.

## Scope Contract And Guard

In scope:

- Render a localized, semantic **Leave** action with an exit icon for active Orbit group rows. Retain **Delete** with a trash icon only for dissolved rows and **Unarchive** for archived rows. Orbit group rows reuse `SwipeableFriendRow`; extend that shared API deliberately rather than inventing a `SwipeableGroupRow`.
- Re-read the group and members when exit starts and before a destructive commit. Map fresh state to ordinary leave, sole-admin recovery, dissolved local cleanup, or no-op/not-found. Existing peer-admin roles remain authoritative.
- Use one pure group-exit policy for newly chosen successors. Candidates are current, non-self, non-admin roster members with current `member_joined` or invite-attempt `joined` evidence. Without a current membership event, only `GroupInviteDeliveryStatus.joined` qualifies; `sent`, `queued`, `needsResend`, `cannotSend`, `revoked`, `declined`, and `unknown` do not. Stale-before-removal/re-invite, admin-add-only, and `joinedAt`-only rows are excluded.
- Extract Group Info's complete role transition into `change_group_member_role_and_broadcast_use_case.dart`. Revalidate join evidence, prepare and sign the proposed transition before mutation, pass the explicit event time into the locked role/config commit, and abort a stale commit with zero writes. Inspect the actual publish result and require inbox storage before returning `readyToLeave`.
- If a signed `member_role_updated` transition cannot finish publish/inbox storage, enqueue that exact transition in the existing `GroupPendingBroadcast` queue and return `pendingSync`. Persist non-empty recipients with the exact signed payload and canonical event identity. Continue stays disabled across close/reopen while that exact role row exists. Retry awaits the existing per-group runner, then re-reads the row and unlocks only when it is absent; the runner's returned drain count and unrelated pending metadata broadcasts are not unlock signals.
- Extract Group Info's voluntary-leave sequence into `leave_group_and_delete_local_history_use_case.dart`, used by Orbit and Group Info. Record the live publish outcome but preserve the existing durable fallback: required signed inbox replay must succeed for every remaining peer, and a live `{ok:false}` alone does not block. Preserve ordinary-member deferred key rotation, snapshot the complete retained key window, and return stage-specific results: `blockedLastAdmin`, `preworkFailed`, `nativeLeaveFailed`, `nativeLeaveUncertain`, `left`, or `leftCleanupIncomplete`.
- Keep rollback claims local: restore tentative local timeline/key artifacts on pre-native or definite native rejection. On native timeout retain local state and do no automatic rollback, purge, publish, or leave retry; surface an uncertain result for an explicit later retry after refresh. A signed event already published to peers cannot be recalled by this plan.
- Reuse the existing dissolve action. Preserve read-only history after dissolve, discard obsolete target-group pending broadcasts only after Orbit's dissolve commits, and offer local deletion separately.
- Harden `deleteGroupAndMessages` in place when `deleteLocallyIfDissolved` is true. Active/missing state must refuse with an explicit error and zero `group:leave`; dissolved success clears messages, members, keys, group, rejoin state, and target-group pending broadcasts. Preserve the flag-false active-leave behavior. Successful shared active-leave cleanup uses the same target-local queue cleanup.
- Build a pure localized recovery sheet and keep its in-flight latch/presentation state in the sheet or `OrbitWired`. Do not add an all-purpose `group_exit_coordinator.dart`.
- While touching `OrbitWired`, add only failure-copy parity to stuck-row Leave: reuse `_showSnackBar` with `group_info_leave_failed`; do not route that flow through the recovery sheet.

Must preserve:

- Last-admin safety and valid peer-admin leave -> `leave_group_use_case_test.dart::blocks sole admin from leaving` and `::allows admin to leave when another admin exists`.
- Signed role and Group Info behavior -> `group_info_wired_test.dart::EK004 promote member stores signed member_role_updated replay envelope` plus the existing sole-admin and native-failure tests.
- Ordinary-member deferred rotation -> `member_removal_integration_test.dart` voluntary-leave writer coverage.
- Signed dissolve and retained history -> `dissolve_group_use_case_test.dart::EK004 dissolve stores signed group_dissolved replay envelope`.
- Target-only cleanup, friends, introductions, unrelated groups, and both 1:1 threads -> existing Orbit deletion/user-B tests.
- Dissolved local cleanup sends no second leave -> `delete_group_and_messages_use_case_test.dart::LP003 dissolved local cleanup does not publish a second group leave`.
- Friend/introduction rows remain Delete; archived rows remain Unarchive.

Hard `Do not`:

- Do not weaken the last-admin invariant or redefine whether already-existing admin rows count in this Orbit UX plan.
- Do not promote a newly selected successor from cached picker state; revalidate current joined evidence at commit.
- Do not return `readyToLeave` from command presence alone. Require `publishResult['ok'] == true`, successful inbox storage, and no pending role-transition row.
- Do not commit role/config before the proposed transition is signed, or let a stale prepared event mutate current membership.
- Do not auto-leave after promotion `pendingSync`/error, inbox/prework failure, definite native rejection, or native timeout.
- Do not block active leave solely because live publish returns `{ok:false}` when the required signed inbox replay succeeds; do not reach native leave when that durable inbox step fails.
- Do not classify a native timeout as definite failure or success. Preserve local state and do not automatically retry or purge.
- Within the current action/session, do not retry publish or `group:leave` after confirmed native leave; report `leftCleanupIncomplete` and retry only local cleanup.
- Do not claim remote rollback after a signed removal has already left the device.
- Do not let dissolved-local deletion fall through to active leave or leave orphaned rejoin/pending-broadcast state; do not move a universal pending-repository dependency into `leaveGroup` in this plan.
- Do not introduce a second pending-broadcast store, a general exit state machine/coordinator, schema/wire/native changes, or device/relay closure.
- Do not replace Group Info or stuck-rejoin UX in this plan beyond the existing-key Orbit snackbar parity above.
- Do not hand-edit generated localization Dart files.

Accepted differences:

- A successfully distributed promotion remains committed if the initiator chooses Stay or a later leave fails.
- A pending promotion may remain locally committed, but it does not unlock Leave until its existing queued signed transition clears.
- A live-topic voluntary-leave publish may soft-fail without blocking when signed inbox replay succeeds for every remaining peer; this preserves durable delivery without adding a self-removal queue.
- A native timeout is reported as unconfirmed and keeps local history. This plan adds no native status API; it performs no automatic destructive follow-up.
- Successor eligibility reads only current group membership/join evidence. Identity-warning and pending-sibling-device presentation state are not policy inputs and must not be coupled into the policy merely to create a fixture.
- Definite native-rejection rollback restores local artifacts only; timeout does not pretend to know the native outcome, and honest copy never promises already-published peer state was reversed.
- The no-second-publish/leave guarantee is in-session. A process death after native success but before local cleanup remains ambiguous without a durable commit marker, which is outside this no-schema plan.
- Pending-row cleanup is closed for the shared active-exit action, Orbit dissolve, and strict local delete only. Pre-existing bare stuck/remote leave paths remain follow-up debt rather than a false global Done claim.

Dependencies:

- Execution starts from the current dirty tree with Plan-259 production copy edits and Plans 259/260/index artifacts uncommitted. Overlaps exist in `orbit_wired.dart`, `group_info_wired.dart`, ARBs/generated l10n, `orbit_wired_test.dart`, and `scripts/run_test_gates.sh`; preserve and merge them.

## Test Contract

Use zero empty cells. Add or retarget four headline files in `GROUP_TESTS`: `group_exit_policy_test.dart`, `group_exit_actions_test.dart`, `group_exit_recovery_sheet_test.dart`, and existing `swipeable_group_row_test.dart`. Orbit, Group Info, and Orbit l10n suites are already registered.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | Fresh repository state maps active ordinary member, sole admin, authoritative peer-admin, dissolved, missing, and pending-role-sync states correctly; a captured row is never authoritative. | `test/features/groups/application/group_exit_policy_test.dart::fresh repository state maps every Orbit exit disposition` | Application unit / in-memory group, invite, message, and pending-broadcast fakes | Compile RED: policy absent -> GREEN: table assertions select normal leave, recovery, local delete, pending sync, or no-op from fresh reads. | Use the row snapshot, require join evidence for an existing admin, or let an unrelated metadata queue row block -> TC-01 red. | `flutter test test/features/groups/application/group_exit_policy_test.dart --plain-name "fresh repository state maps every Orbit exit disposition"`; AUTO + add file to `GROUP_TESTS`. |
| TC-02 | Successor evidence uses one compact truth table: with no current `member_joined`, only invite status `joined` qualifies and the other seven enum values do not; current join, stale-before-removal/re-invite, admin-add-only, and `joinedAt`-only cases cover event precedence. | `test/features/groups/application/group_exit_policy_test.dart::successor candidates require current joined evidence` | Application unit / all eight `GroupInviteDeliveryStatus` values plus four timestamped membership cases | Compile RED -> GREEN: only current `member_joined` or attempt-`joined` evidence remains. | Trust roster presence or Group Info's display-only admin-add fallback -> TC-02 red. | `flutter test test/features/groups/application/group_exit_policy_test.dart --plain-name "successor candidates require current joined evidence"`; same AUTO and registration as TC-01. |
| TC-03 | Actual Orbit wiring exposes semantic Leave/exit for active groups and Delete/trash for dissolved groups, with exclusive dispatch. Group fixtures exercise the reused `SwipeableFriendRow`; Orbit stuck-row Leave failure reuses the localized Group List snackbar. | `swipeable_group_row_test.dart::Leave and Delete expose distinct button semantics`; `orbit_wired_test.dart::active Leave and dissolved Delete dispatch distinct exit branches`; expand Orbit G2 with the failure snackbar | Widget + wired host / localized shared rows and callback/bridge spies | Assertion RED: both active/dissolved states expose Delete and stuck failure is silent -> GREEN: labels, role, icon, exclusive commands, and localized snackbar pass. | Copy Delete's inaccessible presentation into Leave, wire both branches alike, or leave the stuck catch silent -> TC-03 red. | Exact proofs; group-row file added to `GROUP_TESTS`, Orbit file already registered. |
| TC-04 | Friend/introduction actions stay unchanged; an archived group passed production-like active callbacks exposes only Unarchive and invokes only `onUnarchive`. | Existing friend-row swipe sentinel plus `swipeable_group_row_test.dart::archived group shows Unarchive on swipe` | Widget / shared-row harness with `onArchive`, `onLeave`, `onDelete`, and `onUnarchive` spies | GREEN sentinels -> remain GREEN after the shared API change; assert no Leave/Delete/Archive and zero active-callback calls. | Expose any active action on the archived fixture -> mandatory sentinel re-red. | `flutter test test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart && flutter test test/features/orbit/presentation/widgets/swipeable_group_row_test.dart --plain-name "archived group shows Unarchive on swipe"`; AUTO; group-row file in `GROUP_TESTS`. |
| TC-05 | Sole-admin Leave shows localized rationale and two valid paths; close/back/Keep is a zero-op, and no-candidate state explains wait-or-dissolve without enabling promotion. Visible copy is compared with generated l10n getters. | `test/features/groups/presentation/widgets/group_exit_recovery_sheet_test.dart::sole admin guidance is non-destructive and handles no eligible successor` | Widget / localized sheet, callback spies, empty and populated candidates | Compile RED while the new sheet is absent, then assertion RED -> GREEN: getter-backed scopes/actions render and dismiss calls nothing. | Wire dismiss to leave, hardcode English, or enable promotion with no candidate -> TC-05 red. | `flutter test test/features/groups/presentation/widgets/group_exit_recovery_sheet_test.dart --plain-name "sole admin guidance is non-destructive and handles no eligible successor"`; AUTO + add to `GROUP_TESTS`. |
| TC-06 | Promotion starts once under rapid taps. Continue stays blocked while the exact durable role row exists across dispose/re-pump; Retry drains rather than promotes, then unlocks from row absence even if the awaited drain returns zero. Stay after readiness keeps the new admin. | `test/features/groups/presentation/widgets/group_exit_recovery_sheet_test.dart::promotion UI waits for durable sync without promoting twice` | Widget / delayed promotion, durable-row, concurrent-drain, and rebuilt-sheet fixtures | Compile RED while the new sheet is absent, then assertion RED -> GREEN: one promotion, blocked persisted sync, row-based unlock, and Stay behavior pass without exhaustive per-state counters. | Unlock from drain count, rerun promotion on Retry, clear the latch early, or demote on Stay -> TC-06 red. | Exact test; AUTO + `GROUP_TESTS`. |
| TC-07 | Promotion revalidates joined evidence, signs before mutation, aborts stale with zero writes, and returns `readyToLeave` only after successful live publish/inbox and no exact pending row. On incomplete distribution it queues the exact signed transition with non-empty recipients and remains blocked until that row disappears. | `test/features/groups/application/group_exit_actions_test.dart::promotion readiness requires current candidate and completed signed distribution` | Application host / mutable evidence, fake bridge, real pending model, runner, identity/P2P fakes | Compile RED: shared role action absent -> GREEN: ordering, stale/signing zero-write, outcomes, and `GroupPendingBroadcast.fromMap(row.toMap())` assertions cover kind, exact sysText, eventAt/sourceMessageId, and recipients containing the promoted peer. | Mutate before signing, ignore `{ok:false}`, persist empty recipients, unlock from drain count, rerun promotion, or trust cached eligibility -> TC-07 red. | `flutter test test/features/groups/application/group_exit_actions_test.dart --plain-name "promotion readiness requires current candidate and completed signed distribution"`; AUTO + add file to `GROUP_TESTS`. |
| TC-08 | After failed/stale promotion Orbit retains the group row/history and visible localized recovery; a candidate that loses eligibility causes zero role/config/publish/leave calls, including no leave hidden in `finally`. | `test/features/orbit/presentation/screens/orbit_wired_test.dart::failed or stale successor promotion stays visible and never leaves` | Wired widget / mutable evidence and bridge-failure fixtures | Assertion RED -> GREEN: durable user state and actionable recovery remain while destructive sibling calls stay zero. | Call leave from `finally` or promote the cached row -> TC-08 red. | Exact focused test; existing `GROUP_TESTS`. |
| TC-09 | Active exit completes signed self-removal, required inbox replay, and key work before one native leave, then deletes only target history/pending rows. Live publish `{ok:false}` plus successful durable inbox replay still proceeds; ordinary-member rotation may remain explicitly deferred. | `test/features/groups/application/group_exit_actions_test.dart::active exit completes durable prework before native leave and target cleanup` | Application host / live-success, live-soft-failure, two-admin, writer, and repository-order fixtures | Compile RED: shared active-exit action absent -> GREEN: both live outcomes reach one leave only after inbox custody; cleanup and unrelated-state assertions pass. | Block solely on live `{ok:false}`, skip inbox replay, use bare deletion, retain a target queue row, or block writer deferral -> TC-09 red. | Exact test; AUTO + `GROUP_TESTS`; run existing member-removal integration sentinel directly. |
| TC-10 | Failures are stage-aware: inbox/prework failure does not leave and removes tentative local artifacts; definite native rejection restores the exact eight-key window/draft; timeout returns `nativeLeaveUncertain` without automatic rollback/purge/retry; post-native cleanup returns `leftCleanupIncomplete` without an in-session second publish/leave. Orbit maps prework failure to the existing localized retry copy. | Application action test `::active exit distinguishes prework native and post-commit cleanup failures` plus Orbit wired `::active exit prework failure stays in group and shows localized retry` | Application + wired host / inbox failure, native rejection, late timeout completion, cleanup failure, eight keys, generated l10n | Compile/assertion RED -> GREEN: exact stage state/commands, snapshot equality, localized getter comparison, and zero automatic destructive follow-up pass. | Treat live soft-failure alone as prework failure, reach native leave after inbox failure, classify timeout as definite, restore two keys, or report cleanup as not-left -> TC-10 red. | Exact tests; action file AUTO + `GROUP_TESTS`, Orbit already registered. |
| TC-11 | Ordinary members/admins with a peer admin get normal Leave confirmation. A sole admin's first swipe-Leave opens localized recovery directly—with zero generic destructive confirmation, bridge leave, or purge—and a final sole/zero-admin race reopens it. | Orbit wired tests `::first sole-admin Leave opens recovery without destructive work` and `::normal exit confirms once and last-admin race reopens guidance` | Wired widget / sole-admin, member, two-admin, mutable final state, l10n getters | Assertion RED -> GREEN: first-tap and race guidance use getter-backed copy; cancel is zero-op; ordinary success invokes one full exit. | Route the first tap through generic Delete confirmation, reuse initial counts, or check only `adminCount == 1` -> TC-11 red. | Exact tests; existing `GROUP_TESTS`. |
| TC-12 | Dissolve stays separately confirmed, uses the existing signed transition, preserves local read-only history, reports replay gaps honestly, clears target pending rows only after Orbit's commit, and offers getter-backed local deletion afterward using existing `group_info_delete_local_*` strings. | `orbit_wired_test.dart::sole admin dissolve preserves history before optional local delete` plus existing EK004 dissolve sentinel | Wired + application host / success, bridge-recovery-gap, pending row, generated l10n | Assertion RED for Orbit branch -> GREEN: retained history, honest result, post-commit queue cleanup, and exact existing getter values pass. | Chain deletion to dissolve, clear queue before commit, retain stale target rows, hardcode the dialog, or claim universal delivery on `bridgeError` -> TC-12 red. | Orbit exact test plus `dissolve_group_use_case_test.dart` EK004; existing/AUTO gates. |
| TC-13 | Hardened `deleteGroupAndMessages(deleteLocallyIfDissolved: true)` refuses active/missing/stale state with an explicit error and zero leave; dissolved success clears messages, members, keys, group, orphaned rejoin state, and target pending rows. Flag-false active behavior is preserved. | `test/features/groups/application/delete_group_and_messages_use_case_test.dart::strict local-only cleanup refuses active state and clears dissolved local state` | Application host / dissolved, active, missing, state-flip, rejoin, pending row, and flag-false sentinel | Assertion RED: current mode falls through and omits non-cascading state -> GREEN: refusal and exact removals pass without a new result enum/helper. | Retain fallback to `leaveGroup`, change flag-false behavior, or omit rejoin/pending cleanup -> TC-13 red. | Exact test; AUTO direct sentinel; existing dissolved Orbit/Group Info tests remain green. |
| TC-14 | Every genuinely new recovery key/placeholder exists in en/ar/de and generated APIs; UI has no new hardcoded English. Orbit's retained dissolved-delete dialog reuses and explicitly asserts existing `group_info_delete_local_title/body/action` getters. | `test/l10n/orbit_strings_parity_test.dart::group exit keys exist in every locale and generated API`, direct Orbit getter assertions, and `l10n_integrity_test.dart` | L10n host / real ARBs, generated classes, source scan | Compile/assertion RED -> GREEN after necessary ARB edits and `flutter gen-l10n`; do not add duplicate Orbit delete-local keys. | Omit a locale/getter, hardcode dialog/sheet copy, or duplicate existing keys -> TC-14 red. | Exact parity, wired, and integrity tests; parity already in `GROUP_TESTS`. |
| TC-15 | Recovery controls have button/radio semantics and are keyboard-focusable; close/back works; Arabic RTL and 200% text remain operable without overflow. | `test/features/groups/presentation/widgets/group_exit_recovery_sheet_test.dart::exit guidance is semantic RTL and large-text safe` | Widget / SemanticsTester, Arabic locale, text scale 2.0 | Compile RED while the new sheet is absent, then assertion RED -> GREEN: roles, labels, focusability, back, scrolling, and layout pass; no brittle exact focus-order sequence. | Remove semantics/focusability or use fixed-height copy rows -> TC-15 red. | Exact test; AUTO + `GROUP_TESTS`. |
| TC-16 | Existing signed role/dissolve behavior, sole-admin guard, local rollback, target-only cleanup, friends, other groups, and both 1:1 threads remain intact after extraction. | Existing EK004 role/dissolve, GCA-010, leave/delete sentinels, and Orbit user-B preservation tests | GREEN sentinels / existing in-memory and wired fixtures, with GCA-010 expanded to eight keys | GREEN -> remains GREEN; only fixture evidence needed for stricter promotion is added. | Drop signed replay, broaden cleanup, weaken the guard, or lose retained keys -> a named sentinel turns red. | Exact commands in Acceptance Gates; existing `GROUP_TESTS`/AUTO registrations. |

### Test Notes

- TC-01/07: pending-role blocking is limited to queued `member_role_updated` transitions for this group. Do not let unrelated metadata rows block exit.
- TC-02: exhaust the eight existing invite-status enum values in one table, not a combinatorial matrix. Eligibility intentionally has no dependency on identity-warning or sibling-device presentation state.
- TC-07: assert the returned promotion publish map contains `ok == true`; command-log presence is not success. Prepare/sign first and assert that a successful locked mutation returns the same canonical event. Do not manufacture an unreachable canonical-mismatch failure test. Schedule direct P2P only after required publish/inbox completion; it remains supplemental.
- TC-07: round-trip the queued transition through `GroupPendingBroadcast.fromMap(row.toMap())`. Keep promotion locally committed but block Leave while that exact row exists. After Retry, re-query the row even when `drainForGroup` returns zero because a concurrent resume drain may have removed it; do not assert FIFO or add a mutex.
- TC-09/10: the voluntary-leave action does not create a second retry framework. Live publish failure alone is tolerated only because the required inbox replay supplies durable custody; inbox/pre-native failure keeps the user in the group and restores local tentative artifacts. Already-published peer state is not claimed to roll back.
- TC-10: capture every generation in the repository's retained window, not only latest/previous. A timeout is uncertain and non-destructive; after confirmed native success, retries target local cleanup only.
- TC-10: “no second publish/leave” is asserted for the current action/session. Crash-after-native-success recovery needs a durable marker and remains outside this no-schema plan.
- TC-12/13: clear target pending broadcasts only after Plan 261's Orbit dissolve/local-delete state is committed; refusal/failure before that boundary preserves them. Shared active exit does the same after confirmed leave. Do not generalize this claim to legacy bare/remote leave callers.
- TC-12: `DissolveGroupResult.bridgeError` may coexist with `isDissolved == true`; refresh before choosing copy/state.
- TC-14: `l10n_integrity_test.dart` does not scan raw `showConfirmationDialog` arguments, so TC-05/10/11/12 compare visible copy directly with `AppLocalizations` getters.
- TC-16: add current joined evidence to the EK004 promotion fixture because the shared promotion action revalidates at commit. Do not change the visible Group Info recovery UX.

## Implementation Steps

1. Snapshot `git status --short` and inspect every overlapping dirty diff. Re-anchor implementation work by symbols (`updateGroupMemberRole`, `callGroupPublish`, `_onDeleteGroup`) rather than stale line spans. Add the first policy and actual-Orbit action REDs before production edits, then work red-green by vertical slice.
2. Add `group_exit_policy.dart`: fresh state mapping, strict successor evidence, and pending-role-sync detection. Preserve authoritative existing peer admins; do not add legacy-admin heuristics.
3. Extend the `SwipeableFriendRow` API used by Orbit groups with explicit localized group Leave/Delete presentation. Prove semantic button role and actual Orbit active/dissolved wiring while keeping friend/introduction actions and production-like archived exclusivity intact. Add the existing-key stuck-row failure snackbar while `OrbitWired` is open.
4. Extract `change_group_member_role_and_broadcast_use_case.dart` from Group Info. Revalidate and prepare/sign the candidate transition first, then pass its explicit event time into the locked mutation and assert the successful canonical event matches. Inspect `publishResult['ok']`, require inbox storage for ready, and persist an incomplete transition through the real `GroupPendingBroadcast` model with non-empty recipients. Retry awaits the existing runner and rechecks exact-row absence, independent of drain count. Migrate Group Info without replacing its UI.
5. Extract `leave_group_and_delete_local_history_use_case.dart`. Preserve the established delivery contract: live soft failure may proceed only after required signed inbox replay succeeds; inbox failure returns `preworkFailed` before native leave. Capture the complete retained key window/draft, preserve ordinary-member rotation deferral, and return stage-specific results including uncertain timeout. Definite rejection rolls back; timeout keeps local state; confirmed native success permits target-local cleanup only. Migrate Group Info first, then Orbit.
6. Harden `deleteGroupAndMessages` in place for `deleteLocallyIfDissolved: true`. Refuse active/missing state without changing flag-false behavior, clear rejoin and target pending rows after dissolved success, and never fall through to `leaveGroup`. Reuse the same narrow target-row cleanup after the shared active-exit commit; do not add a helper or universal `leaveGroup` dependency.
7. Build the final pure localized recovery sheet and wire it only into normal Orbit group swipe. Keep one in-flight flag, refresh before commits/after results, and never create a general exit coordinator or temporary dissolve-only mode/copy. Leave Group Info and stuck-rejoin presentation on their existing UX apart from snackbar parity.
8. Reuse `dissolveGroup`, retain history, discard obsolete target pending rows only after Orbit's dissolve commits, and map success/recovery-gap outcomes truthfully. Reuse `group_info_delete_local_title/body/action`, add only genuinely new en/ar/de recovery keys, and run `flutter gen-l10n`.
9. Add the four headline paths exactly once to `GROUP_TESTS` with a Plan-261 comment and document them under the Group Messaging Gate. Run the scoped array-membership check; treat completeness and feature discovery as separate checks, not proof of curated registration.
10. Run focused GREEN, the exact preservation sentinels, `groups`, the justified `feature-host-all`, analyzer/l10n/diff hygiene, and representative mutation re-reds. Refresh the architecture graph once after the coherent implementation.

## Risks And Blind Spots

- Promotion is locally committed before distribution -> TC-07 uses the existing durable signed-broadcast queue and TC-01 blocks only pending role transitions across re-entry.
- Promotion signing currently follows mutation -> TC-07 prepares/signs first and makes a stale or signing failure a zero-write path.
- `callGroupPublish` soft-fails by return value -> TC-07 requires `ok` for promotion readiness; TC-09 records the voluntary-leave result but permits live failure only when required signed inbox replay succeeds.
- Voluntary removal may already be visible to peers when a later step fails -> TC-10 restores local artifacts only for prework/definite rejection, keeps timeout non-destructive, and makes no remote rollback claim.
- Key rotation rollback can destroy decryptable history -> TC-10/16 require exact eight-generation restoration.
- Native leave is the commit point -> TC-10 distinguishes pre-commit, native-failure, and post-commit cleanup outcomes so a cleanup retry cannot send a second leave.
- Native timeout has no trustworthy acknowledgement -> TC-10 returns `nativeLeaveUncertain`, preserves local state, and performs no automatic rollback/purge/retry.
- Process death can erase `leftCleanupIncomplete` -> TC-10 scopes no-second-leave proof to the current action/session; no durable marker/schema is added.
- Pending broadcasts do not cascade -> TC-09/12/13 clear obsolete target rows only at the three migrated leave/dissolve/delete boundaries; legacy bare/remote exits remain deferred instead of gaining a broad cleanup coordinator.
- Concurrent pending drains have no mutex -> TC-06/07 unlock from exact durable-row absence after the awaited drain, not its integer count; no FIFO/mutex contract is invented.
- Strict local deletion is destructive -> TC-13 rechecks dissolved state and clears the non-cascading rejoin and pending-broadcast state.
- Concurrent changes -> TC-01, TC-07, TC-08, TC-11, and TC-13 re-read at the actual boundary; one presentation latch covers duplicate taps.
- Dirty overlapping files -> execution preserves Plan-259/260 and unrelated user changes; unexpected overlap blocks the edit until reconciled.

## Gate Cadence

- Per-plan closure: exact TC commands, full focused policy/actions/sheet/Orbit/Group Info files, named preservation sentinels, explicit `GROUP_TESTS` membership, `./scripts/run_test_gates.sh completeness-check`, affected curated lane `./scripts/run_test_gates.sh groups`, and the justified `feature-host-all` sweep because production changes span Groups and Orbit application/presentation.
- Do not run full `host-all` for this plan. Run it once after the **Groups/Orbit Exit UX Wave** and once at final rollout/release closure.
- Run l10n parity/integrity directly; Orbit parity is also already in `GROUP_TESTS`.

## Acceptance Gates

```bash
# Baseline and first causal REDs.
git status --short
flutter test test/features/groups/application/group_exit_policy_test.dart \
  --plain-name "fresh repository state maps every Orbit exit disposition"
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart \
  --plain-name "active Leave and dissolved Delete dispatch distinct exit branches"

# Focused GREEN.
flutter test test/features/groups/application/group_exit_policy_test.dart
flutter test test/features/groups/application/group_exit_actions_test.dart
flutter test test/features/groups/presentation/widgets/group_exit_recovery_sheet_test.dart
flutter test test/features/orbit/presentation/widgets/swipeable_group_row_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test test/features/groups/presentation/group_info_wired_test.dart

# Existing causal/preservation suites.
flutter test test/features/groups/application/leave_group_use_case_test.dart
flutter test test/features/groups/application/delete_group_and_messages_use_case_test.dart
flutter test test/features/groups/application/dissolve_group_use_case_test.dart
flutter test test/features/groups/application/member_removal_integration_test.dart
flutter test test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart

# Localization.
flutter gen-l10n
flutter test test/l10n/orbit_strings_parity_test.dart
flutter test test/l10n/l10n_integrity_test.dart

# Registration/discovery and per-plan gates.
./scripts/run_test_gates.sh completeness-check
./scripts/run_host_test_gates.sh feature-host-all --list

# Curated registration: completeness/AUTO discovery do not prove GROUP_TESTS membership.
plan261_group_tests="$(sed -n '/^readonly GROUP_TESTS=(/,/^)/p' scripts/run_test_gates.sh)"
plan261_missing_group_test=0
for plan261_test_path in \
  test/features/groups/application/group_exit_policy_test.dart \
  test/features/groups/application/group_exit_actions_test.dart \
  test/features/groups/presentation/widgets/group_exit_recovery_sheet_test.dart \
  test/features/orbit/presentation/widgets/swipeable_group_row_test.dart; do
  plan261_match_count="$(printf '%s\n' "$plan261_group_tests" | \
    rg -Fxc "  \"$plan261_test_path\"" || true)"
  test "${plan261_match_count:-0}" -eq 1 || plan261_missing_group_test=1
done
test "$plan261_missing_group_test" -eq 0

./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Hygiene and graph refresh after implementation.
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

Pass interpretation: every closure command exits `0`; the scoped loop proves each headline path occurs exactly once in `GROUP_TESTS`, and `groups` executes that curated array. `completeness-check` and `feature-host-all --list` prove only completeness/discovery, not registration. Analyzer/l10n commands report no new issues. The two first-RED commands must fail for their named missing behavior before production edits, not because of an environment or unrelated baseline failure.

## Execution Interpretation And Done Criteria

- Expected RED: TC-01/02/05/06/07/09/10/14/15 may first fail to compile while their new type/file/getter is absent, then must reach assertion RED; TC-03/08/11/12/13 must fail on their missing behavior. TC-04 and TC-16 are GREEN preservation sentinels, not invented REDs.
- Green sentinels: existing last-admin/peer-admin, signed role/dissolve, ordinary-member deferred rotation, local rollback, dissolved no-second-leave, neighboring swipe, and user-B DM-preservation tests.
- Pre-existing dirty tree: Plan-259 edits and Plan-259/260/mockup artifacts are present; Graphify reports an unrelated stale conversation test. Baseline failures are recorded separately and cannot count as causal RED/GREEN evidence.
- Environment blocker: none expected. The plan reuses existing protocol/storage mechanisms and changes no wire/native/relay/device boundary.
- Scope drift: a new schema/retry framework, universal exit/cleanup coordinator, temporary dissolve-only UI, redefinition of existing-admin policy, Group Info/stuck-rejoin UX replacement beyond snackbar parity, or inability to distinguish native commit from local cleanup requires plan amendment.

- [ ] TC-01 through TC-03 and TC-05 through TC-15 record causal RED, focused GREEN, and a representative mutation re-red; TC-04 and TC-16 sentinels remain GREEN.
- [ ] Active Orbit groups say Leave and dissolved groups say Delete with localized button semantics and correct exclusive callbacks.
- [ ] A sole admin's first swipe-Leave opens localized recovery with zero generic destructive confirmation, bridge leave, or purge.
- [ ] An archived row passed every active callback exposes and invokes only Unarchive; friend/introduction actions remain unchanged.
- [ ] Only a currently confirmed-joined new successor can be promoted.
- [ ] Continue requires completed signed distribution; a queued role transition round-trips with its exact signed event and non-empty recipients, and remains blocked across re-entry until that exact durable row is absent.
- [ ] Promotion signing/stale failure performs zero role, config, watermark, publish, or leave writes; pending Retry drains rather than promotes again.
- [ ] Promotion cannot pass on command presence or `{ok:false}`; voluntary leave permits live `{ok:false}` only after required signed inbox replay succeeds, while inbox failure performs zero native leave.
- [ ] Active-exit prework/definite native rejection preserves local state and the complete retained key window.
- [ ] Native timeout reports an uncertain, non-destructive outcome with no automatic rollback, purge, publish, or leave retry.
- [ ] Post-native cleanup failure is reported as already-left and never triggers an in-session second publish/leave; crash-after-commit ambiguity is recorded, not falsely signed off.
- [ ] Shared active leave, committed Orbit dissolve, and strict local deletion remove obsolete target pending rows; refusal/failure before commit preserves them, with no global claim over legacy bare/remote exits.
- [ ] Dissolve preserves read-only history; strict local deletion never leaves and clears rejoin state.
- [ ] Existing peer-admin policy, Group Info UX, stuck-rejoin transport behavior, other groups, and 1:1 messages remain unchanged; Orbit stuck-row failure now matches Group List's existing localized snackbar.
- [ ] en/ar/de, generated getter comparisons, RTL, 200% text, semantics, focusability, and back behavior pass without an exact focus-order contract.
- [ ] All four headline files occur exactly once in `GROUP_TESTS`; completeness, groups, and feature discovery pass for their distinct purposes.
- [ ] No migration, wire-format, native, relay, device-proof, second retry store, or general exit coordinator was introduced.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean; the incremental graph refresh completes after implementation.

## Handoff

- First RED: `flutter test test/features/groups/application/group_exit_policy_test.dart --plain-name "fresh repository state maps every Orbit exit disposition"`.
- Preservation: `flutter test test/features/groups/application/leave_group_use_case_test.dart && flutter test test/features/groups/presentation/group_info_wired_test.dart && flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`.
- Manual registration: add `group_exit_policy_test.dart`, `group_exit_actions_test.dart`, `group_exit_recovery_sheet_test.dart`, and `swipeable_group_row_test.dart` to `GROUP_TESTS`.
- Migration/boundary: none; host-only, reusing existing signed payloads and pending-broadcast storage.
- Review disposition after applied fixes: execute.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting implementation authorization | contract extraction |
