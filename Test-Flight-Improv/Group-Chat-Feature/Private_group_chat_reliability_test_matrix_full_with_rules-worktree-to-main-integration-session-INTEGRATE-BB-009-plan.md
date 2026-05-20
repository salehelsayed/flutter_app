Status: accepted

# INTEGRATE-BB-009 Standard Integration Plan

## Planning Progress

- 2026-05-17T04:58:00+02:00 - Spawned planner fallback invoked. Files inspected since last update: integration breakdown, source BB-009 matrix row, source BB-009 session breakdown entry, source BB-009 plan, source commit `904b4316`, main COMPLETE_1 compatibility rows, current main duplicate searches, and dirty status. Decision/blocker: spawned planner did not leave a reusable plan file after bounded waits; local plan fallback is artifact-only and current-session-only. Next action: write execution-safe integration contract.
- 2026-05-17T05:03:00+02:00 - Local planner completed. Files inspected since last update: source commit changed-file list/stat, source plan final execution result, main exact-symbol searches, COMPLETE_1 GL-008/GL-009/GL-010/GM-016/GM-017/GP-010 overlap evidence. Decision/blocker: BB-009 source delta is tests-only and importable; no production source file should change unless source tests expose a main-only regression. Next action: execute BB-009 only.

## Execution Progress

- 2026-05-17T03:57:44+02:00 - Executor in progress. Inspected this integration plan, source BB-009 matrix row/breakdown/plan/test-inventory evidence, source commit `904b4316`, current main duplicate selectors, integration ledger status, COMPLETE_1 overlap evidence, and dirty candidate-file state. Main exact selectors were absent before editing. Added `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go::TestBB009LeaveRemovesTopicSubscriptionForValidatorsAndPubSub` plus local helper `assertBB009NoPostLeaveTopicEventsAfter`. No production files changed. `go-mknoon/bridge/bridge_test.go::TestGroupLeaveTopic_BB009RemovesNativeTopicAndBlocksPublish` is not added yet. Test status: not run yet in this executor. Integration breakdown not edited per current-session instruction.
- 2026-05-17T04:01:02+02:00 - Executor completed. Added `go-mknoon/bridge/bridge_test.go::TestGroupLeaveTopic_BB009RemovesNativeTopicAndBlocksPublish`, ran `gofmt` on the two BB-009 Go test files, and ran all required focused, affected, and smoke/backstop commands. No production files changed. The broad baseline gate was not run because this session touched only Go tests plus this plan. Integration breakdown not edited per current-session instruction.

## Final Execution Result

Verdict: `accepted`

Changed files owned by BB-009 execution:

- `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`
  - Added `TestBB009LeaveRemovesTopicSubscriptionForValidatorsAndPubSub`.
  - Added helper `assertBB009NoPostLeaveTopicEventsAfter`.
- `go-mknoon/bridge/bridge_test.go`
  - Added `TestGroupLeaveTopic_BB009RemovesNativeTopicAndBlocksPublish`.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-009-plan.md`
  - Added execution progress and this final execution result.

Tests and gates run:

- `cd go-mknoon && go test ./node -run 'TestBB009LeaveRemovesTopicSubscriptionForValidatorsAndPubSub' -count=1` => PASS (`ok github.com/mknoon/go-mknoon/node 6.309s`).
- `cd go-mknoon && go test ./bridge -run 'TestGroupLeaveTopic_BB009|TestGroupLeaveTopic_NodeNotInitialized|TestGroupLeaveTopic_InvalidJSON|TestGroupLeaveTopic_MissingGroupId' -count=1` => PASS (`ok github.com/mknoon/go-mknoon/bridge 0.455s`).
- `cd go-mknoon && go test ./node -run 'TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit|TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey|TestGL010LeaveUnknownGroupIsNoOpForJoinedGroupState|TestGP010DiscoveryLoopUnregistersOnceAndStopsAfterLeave|TestLeaveGroupTopic_CancelsDiscoveryContext|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish' -count=1` => PASS (`ok github.com/mknoon/go-mknoon/node 14.558s`).
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupLeave'` => PASS (`+3`).
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group:leave'` => PASS (`+1`).
- `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart` => PASS (`+8`).
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` => PASS (`+165`).
- `git diff --check` => PASS.

Skipped or intentionally not changed:

- Did not copy source docs or edit COMPLETE_1 docs.
- Did not edit the integration breakdown ledger per current-session instruction.
- Did not import BB-010+, RA-015, fake-network/device/relay harness, UI, notification, media, observability, or broad security work.
- Did not run baseline because no production code or broad Flutter/Dart surfaces were touched.

Conflicts/blockers: none found. Existing unrelated dirty worktree changes remain preserved.

## Real Scope

This is a standard worktree-to-main integration contract for exactly `INTEGRATE-BB-009` / source row `BB-009`: leave removes the topic subscription used by validators and pubsub.

The executor must import, reconcile, or skip only the meaningful BB-009 delta already implemented in the source worktree. Do not recreate the source implementation plan, do not rerun the original rollout plan, and do not broaden into new gap closure.

In scope:

- Inspect the source BB-009 row, source BB-009 plan/evidence/closure, source commit, and main duplicate state before editing.
- Import only missing BB-009-owned test delta into main:
  - `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`
  - `go-mknoon/bridge/bridge_test.go`
- Preserve accepted main integration rows BB-001 through BB-008.
- Preserve overlapping COMPLETE_1 behavior for GL-008, GL-009, GL-010, GM-016, GM-017, and GP-010.
- Update only this integration plan and the integration breakdown ledger after execution.

Out of scope:

- Do not copy source matrix, source session breakdown, source test-inventory, or the historical source BB-009 plan into main.
- Do not edit main COMPLETE_1 docs for this row.
- Do not import BB-010, BB-011+, RA-015, re-add convergence, recovery acknowledgement ordering, device/relay/3-party harness, UI, notifications, media, observability, or broad security work.
- Do not change production files unless the imported source BB-009 tests fail on a true current-main product regression inside the BB-009 leave/unsubscribe contract.

## Closure Bar

The row is good enough when main contains the BB-009 source proof or proves it was already present:

1. A BB-009-named Go node test proves A, B, and C have live delivery before C leaves.
2. C leaves through `LeaveGroupTopic`, and C's topic, subscription, subscription context, discovery context, config, and key state are removed.
3. A and B can still publish/receive after C leaves.
4. C receives no post-leave group message, reaction, parse-failure, decrypt-failure, validation-reject, or discovery-work events for that group.
5. C cannot publish message or reaction after leave and gets a `group not joined` style failure.
6. A BB-009-named Go bridge test proves `group:leave` reaches native cleanup and subsequent group publish fails closed.
7. The focused BB-009 tests and affected COMPLETE_1/main leave preservation tests pass.
8. The integration ledger records one terminal status: `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture`.

## Source Of Truth

- Source row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-009`.
- Source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` session `BB-009`.
- Historical worktree plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-009-plan.md`.
- Source closure evidence: source `test-inventory.md` BB-009 row and source matrix BB-009 covered note.
- Source commit evidence: `904b4316` (`BB-009: prove leave removes subscriptions`).
- Main integration controller: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Main compatibility artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current code and tests in main win over stale prose when they conflict.

## Session Classification

`implementation-ready`

Reason: the source BB-009 code delta is limited to two Go test files, main currently lacks the exact BB-009 selectors, and the integration can be bounded to importing missing row-owned proof without copying source docs or touching production code.

## Source Commit And File Evidence

Source commit:

```text
904b4316 BB-009: prove leave removes subscriptions
```

Changed files in that commit:

```text
A Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-009-plan.md
M Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md
M Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md
M Test-Flight-Improv/Group-Chat-Feature/test-inventory.md
M go-mknoon/bridge/bridge_test.go
M go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go
```

Meaningful integration files are the two Go test files. The four source docs are historical evidence only and must not be copied into main.

Source code/test evidence:

- `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` adds `TestBB009LeaveRemovesTopicSubscriptionForValidatorsAndPubSub`.
- `go-mknoon/bridge/bridge_test.go` adds `TestGroupLeaveTopic_BB009RemovesNativeTopicAndBlocksPublish`.
- Source closure reports no production files changed.

## Duplicate Presence In Main

Observed main state during planning:

- Searches found no `TestBB009LeaveRemovesTopicSubscriptionForValidatorsAndPubSub`.
- Searches found no `TestGroupLeaveTopic_BB009RemovesNativeTopicAndBlocksPublish`.
- Main already has adjacent leave/unsubscribe proof including `TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit`, `TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave`, and `TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey`; do not duplicate or rewrite those selectors.
- Main already has Flutter leave command/application coverage around `callGroupLeave`, `group:leave`, and `leave_group_use_case_test.dart`; use those as preservation checks.

If execution-time searches show BB-009 has landed since this plan was written, skip code/test edits and classify the row `skipped_already_present` with exact file/selector evidence.

## COMPLETE_1 Overlap Rows

Inspect these before resolving conflicts:

- `GL-008`: leave cancels subscription and discovery before deleting state.
- `GL-009`: leave unregisters the topic validator for the group.
- `GL-010`: leave unknown group is safe and no-op.
- `GM-016`: removed member remains unsubscribed from topic.
- `GM-017`: removed member with stale subscription cannot publish accepted messages.
- `GP-010`: discovery loop exits and unregisters on leave.

These rows are compatibility constraints, not an invitation to import their broader harness/device work.

## Files To Inspect Or Update

Before editing, inspect:

```bash
git status --short
git diff -- go-mknoon/bridge/bridge_test.go go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go
git -C /Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline show --name-status --no-renames 904b4316
rg -n "BB-009|BB009|TestBB009LeaveRemovesTopicSubscriptionForValidatorsAndPubSub|TestGroupLeaveTopic_BB009|LeaveGroupTopic|group:leave" go-mknoon test lib Test-Flight-Improv/Group-Chat-Feature
```

Source files to compare:

```text
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/go-mknoon/bridge/bridge_test.go
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go
```

Main files to update only if missing the BB-009 delta:

```text
go-mknoon/bridge/bridge_test.go
go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go
```

Docs to update after execution:

```text
Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-009-plan.md
Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md
```

## Device/Relay Proof Profile

Required closure profile: `host-only`.

BB-009 source closure did not require a simulator, paired device, external relay, or 3-party device-lab run. The required proof is Go host-side node/bridge selectors plus Flutter host preservation selectors and the host macOS `groups` gate.

Recommended but unclaimed proof: focused fake-network selectors and 3-party real-device/relay proof. Do not mark the row blocked on those fixtures unless execution unexpectedly makes them required by a current-main conflict.

## Step-By-Step Integration Plan

1. Reconfirm `INTEGRATE-BB-008` is accepted in the integration breakdown and BB-009 is still `pending_integration`.
2. Re-run duplicate searches for the two exact BB-009 selectors.
3. Inspect uncommitted main diffs in the two candidate files. If an uncommitted change overlaps the exact source BB-009 hunks, stop and classify `blocked_conflict` unless the overlap is plainly the same BB-009 delta.
4. Compare source commit `904b4316` hunks against current main:
   - Bring over `TestBB009LeaveRemovesTopicSubscriptionForValidatorsAndPubSub` only if absent.
   - Bring over `TestGroupLeaveTopic_BB009RemovesNativeTopicAndBlocksPublish` only if absent.
5. Preserve line drift and existing accepted tests. Use source semantics as the source of truth, not a blind patch.
6. Do not import source doc changes.
7. Run focused BB-009 tests and affected preservation tests below.
8. Assign one terminal status:
   - `accepted`: missing meaningful BB-009 delta imported and required tests/gates pass.
   - `skipped_already_present`: all meaningful BB-009 delta was already present in main with concrete selector evidence.
   - `blocked_conflict`: main has overlapping unmerged changes or COMPLETE_1 behavior that cannot be reconciled within row scope.
   - `blocked_external_fixture`: only if execution discovers a truly required external fixture is unavailable.

## Conflict Stop/Map Rule

Stop before editing and map conflicts if any of these are true:

- `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` already has a differently named BB-009-equivalent test with incompatible helper assumptions.
- `go-mknoon/bridge/bridge_test.go` already has a differently named BB-009-equivalent bridge leave success test with incompatible expectations.
- Imported BB-009 tests fail because current main intentionally changed leave semantics outside the source row's contract.
- COMPLETE_1 GL-008, GL-009, GL-010, GM-016, GM-017, or GP-010 behavior would be weakened by the import.
- Passing BB-009 would require RA-015 re-add convergence, BB-010 leave-failure semantics, or device/relay harness work.

When stopped, record:

- exact conflicting files/hunks
- source rows implicated: `BB-009` and any adjacent source rows
- main/COMPLETE_1 rows implicated: at minimum the overlap rows above if touched
- recommended next action

Do not resolve such conflicts inside this row without a new controller decision.

## Tests And Gates To Run

Focused BB-009 proof:

```bash
cd go-mknoon && go test ./node -run 'TestBB009LeaveRemovesTopicSubscriptionForValidatorsAndPubSub' -count=1
cd go-mknoon && go test ./bridge -run 'TestGroupLeaveTopic_BB009|TestGroupLeaveTopic_NodeNotInitialized|TestGroupLeaveTopic_InvalidJSON|TestGroupLeaveTopic_MissingGroupId' -count=1
```

Affected COMPLETE_1/main preservation:

```bash
cd go-mknoon && go test ./node -run 'TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit|TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey|TestGL010LeaveUnknownGroupIsNoOpForJoinedGroupState|TestGP010DiscoveryLoopUnregistersOnceAndStopsAfterLeave|TestLeaveGroupTopic_CancelsDiscoveryContext|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish' -count=1
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupLeave'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group:leave'
flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart
```

Smoke/backstop:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
git diff --check
```

Run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` only if execution touches production code or broad Flutter/Dart surfaces. Source BB-009 closure did not require baseline.

## Known-Failure Interpretation

- Failures in `TestBB009LeaveRemovesTopicSubscriptionForValidatorsAndPubSub` or `TestGroupLeaveTopic_BB009*` are in scope.
- Failures in GL-008, GL-009, GL-010, GM-016/GM-017-adjacent leave semantics, GP-010, `callGroupLeave`, `group:leave`, or leave use-case preservation are integration blockers unless proven pre-existing from unchanged main.
- Missing device/relay fixtures should not block BB-009 unless a current-main conflict makes external proof required.

## Done Criteria

- Source BB-009 row, source plan/closure, source commit, exact changed files, duplicate presence, and COMPLETE_1 overlaps were inspected.
- Main contains the row-owned BB-009 selectors, or the row is explicitly `skipped_already_present`.
- No duplicate adjacent GL/GM/GP work was imported.
- Required focused tests and affected preservation selectors pass.
- `git diff --check` passes.
- Integration breakdown ledger is updated with one terminal status and concrete evidence.
- This plan records execution outcome, changed files, tests run, skipped duplicate/unrelated work, conflicts, and next session.

## Scope Guard

Do not:

- Rewrite `LeaveGroupTopic`, `GroupLeaveTopic`, validators, discovery loops, or topic lifecycle unless the source BB-009 tests expose a true current-main BB-009 product regression.
- Add new fake-network or device-lab harness support.
- Implement BB-010, BB-011+, RA-015, GM-016, GM-017, GL-008, GL-009, GL-010, or GP-010 work inside this row.
- Touch COMPLETE_1 docs.
- Use this row to fix unrelated dirty worktree changes.

## Accepted Differences / Intentionally Out Of Scope

- Source BB-009 closure was tests-only; production files staying untouched is acceptable if the imported tests pass.
- Fake-network and 3-party real-device/relay proof remain recommended and unclaimed.
- COMPLETE_1 GL/GM/GP rows remain authoritative for their own broader contracts; BB-009 adds source-row traceability around leave removing live subscription state.

## Dependency Impact

BB-010+ and recovery ordering rows may rely on BB-009 only for the invariant that a successful native leave removes the live topic/subscription state and blocks post-leave publish. They must not assume leave-failure semantics, re-add convergence, recovery acknowledgement ordering, device/relay proof, or UI behavior was integrated here.

If BB-009 blocks, keep `INTEGRATE-BB-010+` pending until the conflict is mapped and resolved or explicitly accepted by the integration controller.

## Reviewer Pass

Verdict: sufficient for a standard integration execution pass.

Findings:

- The plan names the source row, source closure, source commit, exact changed files, duplicate state in main, and COMPLETE_1 overlap rows.
- The plan prevents source doc copying and gap-closure expansion.
- The plan has an explicit conflict stop/map rule and terminal status contract.
- The plan requires focused BB-009 tests plus affected GL-008/GL-009/GL-010/GP-010 and Flutter leave preservation.

## Arbiter Decision

Final verdict: `execution-ready`.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact helper placement in main test files because line numbers have drifted.
- Whether the broad `baseline` gate is required; it is conditional on production or broad Flutter changes.

Accepted differences intentionally left unchanged:

- No fake-network or 3-party proof.
- No BB-010 or RA-015 import.
- No COMPLETE_1 doc edits.
