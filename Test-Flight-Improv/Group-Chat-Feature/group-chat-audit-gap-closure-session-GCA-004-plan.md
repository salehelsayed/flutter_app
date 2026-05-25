# GCA-004 Invite Accept Bridge-Error Retry Affordance Plan

Status: execution-ready

## Planning Progress

- 2026-05-23T17:43:00Z - Planner completed. Files inspected since last update: `lib/features/groups/presentation/screens/group_list_wired.dart`, `lib/features/groups/presentation/widgets/pending_group_invite_card.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/core/bridge/fake_bridge.dart`. Decision/blocker: no blocker; current UI reloads pending invites after accept, so preserving the row exposes the retry affordance without a UI edit. Next action: reviewer sufficiency pass.
- 2026-05-23T17:44:00Z - Reviewer started. Files inspected since last update: current draft plan. Decision/blocker: review in progress. Next action: check plan sufficiency against mandatory sections, security guard, hard cap, and gate contract.
- 2026-05-23T17:47:00Z - Reviewer completed. Files inspected since last update: current draft plan, gate definitions, bridge-error integration evidence. Decision/blocker: sufficient with adjustments; no structural blocker. Next action: arbiter classify reviewer findings and finalize status.
- 2026-05-23T17:48:00Z - Arbiter started. Files inspected since last update: reviewer findings and adjusted plan. Decision/blocker: arbitration in progress. Next action: classify findings as structural blockers, incremental details, or accepted differences.
- 2026-05-23T17:49:00Z - Arbiter completed. Files inspected since last update: final adjusted plan. Decision/blocker: no structural blockers remain; plan is execution-ready. Next action: implementation agent can run TDD first and execute the scoped file edits.

## Execution Progress

- 2026-05-23T17:32:20Z - Contract extracted. Files inspected since last update: this plan, session breakdown, source matrix row, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`. Decision/blocker: no nested agent tool is exposed, so this fresh execution agent is using the local sequential fallback authorized by the user. Next action: add focused GCA-004 use-case expectations first and run the RED command.
- 2026-05-23T17:32:20Z - Executor local fallback started. Files inspected or touched: plan heartbeat only so far. Command currently running: none. Decision/blocker: existing bridge-error tests still assert pending deletion/consumption. Next action: patch focused tests within the allowed write set.
- 2026-05-23T17:34:33Z - Focused RED completed. Files touched: `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`. Command finished: `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name "GCA-004"` exited 1. Decision/blocker: expected failure confirmed; both new GCA-004 tests fail because the pending invite is deleted on bridge error. Next action: implement minimal use-case commit-point and compatible duplicate retry changes.
- 2026-05-23T17:36:05Z - Executor implementation pass completed. Files touched: `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`. Command finished: focused `GCA-004` use-case test exited 0. Decision/blocker: bridge join and inbox-drain bridge errors now leave pending invite/consumption/tombstone state retryable, then compatible retry commits. Next action: run direct suite and integration alignment.
- 2026-05-23T17:38:11Z - Direct suite run completed. Command finished: `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart` exited 1. Decision/blocker: GCA-004, duplicate-group, and stale newer-key focused checks pass; remaining failure is `accept replays backlog reactions when reactionRepo is provided`, where the test listener self peer id `peer-self` is not a materialized group member and `GROUP_HANDLE_INCOMING_MSG_LOCAL_MEMBERSHIP_MISSING` rejects the replay message. Next action: update required bridge-error integration expectation and continue scoped verification.
- 2026-05-23T17:40:59Z - Integration alignment completed. Files touched: `test/features/groups/integration/invite_round_trip_test.dart`. Command finished: `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name "GCA-004"` exited 0. Decision/blocker: integration now preserves background rejoin/drain recovery while pending stays retryable, then proves explicit accept retry clears pending and records consumption. Next action: supplemental gate and whitespace check.
- 2026-05-23T17:39:26Z - Supplemental and whitespace checks completed. Commands finished: `flutter test --no-pub test/features/contact_request/integration/contact_request_flow_test.dart` exited 0; `git diff --check` exited 0. Decision/blocker: no GCA-004 blocker; full group gate not run in this bounded session because direct, integration, supplemental, and whitespace checks covered the plan-required paths, and the broader direct accept suite has one unrelated residual noted above. Next action: local QA review.
- 2026-05-23T17:41:00Z - Local QA Reviewer fallback completed. Files inspected: touched use-case diff, focused use-case tests, bridge-error integration diff, current dirty status. Decision/blocker: no blocking GCA-004 issues found; write scope stayed within the allowed non-doc files plus this plan; unrelated dirty picker/group-list/create-group/go/pubspec/test-upload state was not edited by this session. Final verdict: `accepted_with_explicit_follow_up` because GCA-004 targeted closure passes, while the broader accept-pending suite still has the unrelated reaction replay fixture failure recorded above.

## Real Scope

Change invite acceptance so bridge transport failures do not consume the pending invite or write single-use/key-package tombstones until the bridge join plus accepted inbox drain has actually succeeded.

The implementation should handle both bridge-error shapes already present in `acceptPendingGroupInvite`:

- `materializeAcceptedGroupInvitePayload` returns `HandleGroupInviteResult.bridgeError` after local group/key/member state was persisted but `group:join` failed.
- `materializeAcceptedGroupInvitePayload` succeeds, but `_drainAcceptedGroupInboxBestEffort` returns `false`.

The retry path should be a second call to `acceptPendingGroupInvite` against the same pending row. If compatible local group/key state already exists from a prior bridge-error attempt, the second call should retry bridge join plus inbox drain, then consume/delete/tombstone only after that retry succeeds.

Do not change security rejections for expired, revoked, invalid, wrong-identity, already-used, stale, or repair-pending invites.

## Closure Bar

GCA-004 is closed when a focused use-case test proves that a bridge error leaves the same pending invite visible/retryable and does not create consumed invite or welcome-key-package tombstones, while a later successful retry removes the pending row and records the same consumed/tombstone state normal success records today.

The normal success path, repair-pending key-material path, duplicate-group path without compatible retry state, and security rejection paths must keep their existing behavior.

## Source Of Truth

- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md:21` is the row contract: GCA-004 is open and targets invite accept bridge errors consuming/deleting retry affordance.
- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md:145`-`161` is the session contract and hard scope.
- Current code wins over stale prose. `acceptPendingGroupInvite` is the behavior owner for pending invite consumption/deletion.
- `scripts/run_test_gates.sh` wins over `Test-Flight-Improv/test-gate-definitions.md` if gate membership differs.
- Do not overwrite unrelated dirty worktree changes. Current `git status --short` shows existing modified presentation files and untracked docs outside this plan's implementation target.

## Session Classification

`implementation-ready`

## Exact Problem Statement

Current pending-invite accept bridge-error paths return `AcceptPendingGroupInviteResult.bridgeError`, but remove the pending invite and record used-key state. That makes the group partially materialized locally while the pending invite card disappears, so the user loses the obvious "Accept" retry.

The user-visible behavior must improve by keeping or exposing an accept retry when bridge join or inbox drain fails transiently. The retry must not let rejected invites survive, and must not allow expired, revoked, wrong-identity, invalid, already-used, or active tombstone cases through.

## Files And Repos To Inspect Next

Planned non-doc edit set, staying under the hard cap of 3 files:

- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `test/features/groups/integration/invite_round_trip_test.dart` only if the named group gate's existing bridge-error integration assertion needs to be aligned with the new retry affordance

Supporting files already inspected and useful for implementation:

- `test/shared/fakes/in_memory_pending_group_invite_repository.dart`
- `test/core/bridge/fake_bridge.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/widgets/pending_group_invite_card.dart`
- `scripts/run_test_gates.sh`

Treat `lib/features/groups/application/handle_incoming_group_invite_use_case.dart` as inspect-only for this session. If implementation evidence proves it must be edited, stop and re-evaluate the 3-file cap before touching integration or UI files.

## Existing Tests Covering This Area

- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart:493`-`522` currently proves inbox-drain failure returns `bridgeError`, preserves local group/key state, but expects the pending invite to be deleted and consumed.
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart:847`-`885` currently proves `group:join` bridge error returns `bridgeError`, preserves local group/key state and timeline behavior, but expects the pending invite to be deleted and consumed.
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart:1014`-`1107` proves repairable join-material errors keep the invite pending without local group state and can retry after key material is repaired. This must stay distinct from generic bridge errors.
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart:1837`-`1865` proves pre-existing duplicate group deletes the pending row. Preserve this for non-compatible duplicate state.
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart:2085`-`2124` proves welcome key-package tombstones are recorded after accepted materialization; extend bridge-error coverage so tombstones are not recorded before bridge recovery succeeds.
- `test/features/groups/integration/invite_round_trip_test.dart:2788`-`2995` proves background rejoin/drain can recover after bridge error without a pending row. This remains useful but is not enough for the user-visible retry affordance.

## Regression/Tests To Add First

Add or update focused use-case tests before production edits:

1. Update the inbox-drain bridge-error test so the first attempt expects `bridgeError`, `group != null`, group/key state present, pending invite still present, no consumed invite, and no welcome-key-package tombstone if the fixture includes one. Then set `group:inboxRetrieveCursor` to success and call `acceptPendingGroupInvite` again; expect `success`, pending invite deleted, consumed invite recorded for single-use, tombstone recorded for welcome package, and no duplicate-group result.
2. Update or add a `GCA-004` `group:join` bridge-error test using a device-bound welcome-key-package invite. First attempt should expect `bridgeError`, compatible local group/key state present, pending invite still present, no consumed invite, no welcome-key-package tombstone. Then set `group:join` and inbox retrieval to success and call accept again; expect the retry path to return `success`, delete the pending row, record consumed/tombstone state, and show two `group:join` calls.
3. Re-run the existing duplicate-group test to prove an unrelated pre-existing group without compatible retry state still returns `duplicateGroup` and deletes the pending row.
4. After the direct use-case behavior is implemented, update `invite_round_trip_test.dart` only if the existing bridge-error integration proof still asserts the old pending-row deletion behavior. Keep any integration edit expectation-only and in the same bridge-error test.

The first focused test run should fail against current code because the pending row is deleted and consumed/tombstoned on bridge error.

## Step-By-Step Implementation Plan

1. Add the failing use-case test changes in `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` only. Run the direct test with the new/updated plain name and confirm it fails for the current deletion/consumption behavior.
2. In `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, keep every pre-materialization rejection branch unchanged: revoked, expired, invalid payload/security failure, invalid welcome package, wrong identity, stale local state, consumed invite, active welcome package tombstone, and invalid attestation should still delete or preserve exactly as they do now.
3. Add a small local helper for the "accepted and recovered" commit point, e.g. record consumed invite for single-use, record welcome-key-package tombstone, then delete the pending invite. Call it only after bridge join plus accepted inbox drain succeed.
4. Change the `HandleGroupInviteResult.success` branch so inbox drain failure returns `bridgeError` with the group but leaves the pending invite, consumed invite, and welcome-key-package tombstone untouched. On inbox drain success, use the helper to consume/tombstone/delete.
5. Change the `HandleGroupInviteResult.bridgeError` branch so generic bridge join/timeout errors leave pending invite, consumed invite, and welcome-key-package tombstone untouched while preserving local group/key state and existing best-effort timeline behavior.
6. In the `HandleGroupInviteResult.duplicateGroup` branch, add a narrow retry path only when local group/key state is compatible with the pending invite payload. Compatibility should at minimum require an existing group and latest key for the same group whose generation/key match the payload. If incompatible, keep the current duplicate behavior.
7. For the compatible duplicate retry path, call `callGroupJoinWithConfig` with the pending payload's group config, group key, and key epoch, then call `_drainAcceptedGroupInboxBestEffort`. If either fails, return `bridgeError` with the existing group and keep the pending invite unconsumed. If both succeed, use the commit helper and return `success` with the existing group.
8. Do not publish a second join timeline message from the duplicate retry branch; the retry branch is for bridge join/inbox recovery, not membership timeline fanout.
9. If `test/features/groups/integration/invite_round_trip_test.dart` fails because it asserts the old no-pending-row behavior, update only that existing bridge-error proof to expect the pending row after the first bridge error and, if cheap, verify the explicit accept retry before the existing rejoin/drain convergence. This is the only planned third non-doc implementation file.
10. Stop and document a blocker if this cannot be implemented within the hard cap of 3 non-doc files or if implementation evidence requires a schema/new-state model.

## Risks And Edge Cases

- Generic bridge errors and repairable join-material errors must stay different. Repairable join-material errors should still produce `repairPending` and avoid local group activation.
- A pre-existing duplicate group with no matching key state must not be treated as a successful retry.
- Repeated bridge errors should leave the same pending row retryable without repeatedly writing consumed/tombstone state.
- Inbox drain failure after a successful bridge join should not consume the invite until a later retry drains successfully.
- Expired or revoked pending rows should still be deleted before bridge retry logic can run.
- Active consumed-invite and welcome-key-package tombstones should still reject before any bridge retry.
- The existing background rejoin/drain recovery path must remain valid; this session adds an explicit accept retry affordance, not a replacement for startup/resume recovery.

## Exact Tests And Gates To Run

TDD proof:

```bash
flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name "GCA-004"
```

Direct regression suite:

```bash
flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart
```

Named-gate invite integration proof, especially if the group gate is not run in full:

```bash
flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name "bridgeError accept later rejoin and drain converge without the pending invite row"
```

Supplemental direct suite from the group gate definition when invite/contact-entry flows are touched:

```bash
flutter test --no-pub test/features/contact_request/integration/contact_request_flow_test.dart
```

Gate/checks after implementation:

```bash
git diff --check
./scripts/run_test_gates.sh groups
```

If `./scripts/run_test_gates.sh groups` is too expensive for the bounded implementation run, record that and run the direct suite plus the invite integration proof and supplemental contact-request suite above.

## Reviewer Findings

Reviewer verdict: sufficient with adjustments now applied.

- Missing gate coverage found: the group gate lists `invite_round_trip_test.dart`, and the inspected bridge-error integration currently asserts the old pending-row deletion behavior. The plan now allows an expectation-only update to that existing test as the third non-doc file.
- Missing supplemental gate found: the gate definition calls out `test/features/contact_request/integration/contact_request_flow_test.dart` for invite/contact-entry changes. The plan now includes it.
- No stale source-of-truth issue found: the matrix, breakdown, current code, direct tests, gate definitions, and gate script are all represented.
- No overengineering found: the plan keeps behavior local to `acceptPendingGroupInvite` and rejects new storage, scheduler, or UI state.
- Minimum needed for sufficiency: keep the duplicate retry path compatibility-checked so a generic pre-existing group does not become an unintended success path.

## Arbiter Decision

Final verdict: `execution-ready`.

Structural blockers: none.

Incremental details intentionally deferred:

- The exact plain-name for the invite bridge-error integration command may need to change if the test is renamed while updating the stale expectation.
- If the implementation agent proves the integration test does not fail under the new direct behavior, the optional third non-doc edit should be skipped.

Accepted differences intentionally left unchanged:

- No UI file is planned because preserving the pending row should already keep the existing pending invite card and `Accept` action visible after `_loadGroups`.
- Existing startup/resume rejoin recovery remains a background safety net, not the primary GCA-004 closure affordance.

## Known-Failure Interpretation

The source matrix records that `./scripts/run_test_gates.sh groups` was already red on unrelated isolated `group_membership_smoke_test.dart` `GM-028` during GCA-001 closure. If the group gate still fails only on that same known issue while the direct accept-pending suite and invite bridge-error integration proof pass, do not classify it as a GCA-004 regression.

Any failure in `accept_pending_group_invite_use_case_test.dart`, `invite_round_trip_test.dart` bridge-error coverage, or a changed failure in group invite accept/retry behavior is in scope and must be fixed before closure.

## Done Criteria

- The direct use-case test fails before implementation and passes after implementation.
- Bridge join failure and inbox drain failure both leave the pending invite retryable and do not record consumed invite or welcome-key-package tombstone state until recovery succeeds.
- A second accept against compatible materialized local group/key state retries join/drain and commits normal success state.
- Existing security rejection tests still pass.
- Existing non-compatible duplicate-group behavior still passes.
- Non-doc implementation touches no more than 3 files.
- `git diff --check` passes.
- Matrix row `GCA-004` and this breakdown ledger are updated only after implementation and verification evidence exists.

## Scope Guard

Non-goals:

- No new database columns, new repositories, new dependencies, or schema migrations.
- No broad rewrite of invite storage, group materialization, rejoin, drain, or group list presentation.
- No changes to send, create group, member add/remove, leave, notification, or routing behavior.
- No pending invite UI edit unless direct evidence proves preserving the pending row does not surface the card after `_loadGroups`.
- No attempt to solve duplicate join timeline idempotence beyond avoiding a second publish in the compatible duplicate retry branch.

Overengineering would be adding a new retry-state enum, scheduler, background job, or bridge recovery queue for this row.

## Accepted Differences / Intentionally Out Of Scope

- The existing background `rejoinGroupTopics` plus offline inbox drain path remains as-is. It can recover a materialized group after a bridge error, but it is not an obvious pending-invite retry affordance.
- Pending invite UI copy can remain unchanged for this session because `GroupListWired` reloads pending invites after accept and `PendingGroupInviteCard` already exposes the `Accept` action.
- Existing integration coverage that expects recovery "without the pending invite row" may need expectation review only if direct behavior changes conflict; do not broaden integration scope unless the direct use-case change breaks that proof.

## Dependency Impact

This plan closes only row `GCA-004`. Later closure work should depend on it only for the invariant that bridge-error invite accept does not consume key material or remove retry affordance until bridge recovery succeeds.

If this plan changes during implementation because compatible duplicate retry cannot be proven safely, skip matrix closure and mark `GCA-004` blocked with evidence rather than widening into UI or persistence redesign.

## Evidence Summary

- `acceptPendingGroupInvite` records consumed invite, records welcome-key-package tombstone, deletes pending invite, then returns `bridgeError` on inbox drain failure in the success branch (`accept_pending_group_invite_use_case.dart:278`-`324`).
- `acceptPendingGroupInvite` also records consumed/tombstone state and deletes the pending invite on generic materialization `bridgeError` (`accept_pending_group_invite_use_case.dart:325`-`354`).
- Existing duplicate handling deletes the pending row whenever materialization reports `duplicateGroup` (`accept_pending_group_invite_use_case.dart:355`-`357`), so simply preserving the pending row would not be enough without a compatible duplicate retry path.
- `materializeAcceptedGroupInvitePayload` persists group/member/key state before calling `group:join`, and returns `bridgeError` with a group id on generic join bridge failures (`handle_incoming_group_invite_use_case.dart:858`-`965`).
- `GroupListWired` reloads pending invites after accept (`group_list_wired.dart:310`) and the pending card already has an accept action, so preserving the pending row exposes the retry affordance without a UI edit.
