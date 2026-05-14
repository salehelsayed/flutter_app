# GL-010 Leave Unknown Group No-Op Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 22:49 CEST - Local gap-closure pass reached GL-010 after GO-012 closure. Files inspected: source matrix GL-010 row, session-breakdown GL-010 row, adjacent lifecycle/pubsub tests, `go-mknoon/node/pubsub.go`, and `go-mknoon/node/pubsub_test.go`. Decision: keep GL-010 as `needs_tests_only`; the source row was `Open`, no adjacent GL-010 plan existed, and the repo needed an exact no-op proof for leaving an unknown group while another joined group remains intact.

## Original Source Row

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GL-010 | Leave unknown group is safe and no-op | Node is running but G is not joined. | 1. Call LeaveGroupTopic(G). 2. Inspect maps and validator calls. | Returns without panic and does not unregister unrelated topics or keys. | P1 | Open | Required | Recommended | N/A | N/A | N/A | Prevents cleanup regressions in bulk recovery. |

## Reconciliation Verdict

GL-010 was repo-owned because the row targets native group-topic lifecycle behavior and concrete test coverage in this repository. The missing piece was proof, not a product contract or external fixture. Existing leave tests covered joined-group cleanup, but did not pin the unknown-group no-op behavior against unrelated joined group state.

## Scope

Own exactly GL-010:

- Add an exact Go regression that joins a known group, snapshots its runtime state, calls `LeaveGroupTopic` for a different unknown group, and proves the known group still owns the same topic, subscription, config, key, subscription context, and discovery context.
- Prove the unknown group was not created by the leave call.
- Prove the still-joined known group remains publishable after the unknown leave.
- Update the source matrix, breakdown ledgers, and test inventory with concrete evidence.

## Out Of Scope

- Changing known-group leave cleanup semantics, which are covered by GL-008, GL-009, and GP-010.
- Stop/restart lifecycle cleanup, which remains GL-017 and GR rows.
- Bulk recovery concurrency, which remains GL-020.

## Owner Files

- `go-mknoon/node/pubsub_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-010-plan.md`

## Required Validation

```sh
gofmt -w go-mknoon/node/pubsub_test.go
cd go-mknoon && go test ./node -run 'TestGL010LeaveUnknownGroupIsNoOpForJoinedGroupState' -count=1
cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart
./scripts/run_test_gates.sh groups
git diff --check -- go-mknoon/node/pubsub_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-010-plan.md
```

## Done Criteria

- Source row GL-010 is `Covered` with concrete file/test/gate evidence.
- Exact row-owned Go proof exists and passes.
- The proof exercises a running node with one known joined group plus an unknown leave target.
- Known group state remains unchanged and publishable after the unknown leave.
- No `accepted_with_explicit_follow_up` is used for unresolved GL-010 gaps.

## Execution Evidence

- Exact test:
  - `go-mknoon/node/pubsub_test.go::TestGL010LeaveUnknownGroupIsNoOpForJoinedGroupState` starts a real local node, joins `gl010-joined-group`, snapshots the joined group's topic, subscription, config, key, subscription context, and discovery context, calls `LeaveGroupTopic("gl010-unknown-group")`, and proves each known-group state pointer is unchanged.
  - The same test proves the unknown group did not gain entries in `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, or `groupDiscoveryCtx`.
  - The same test publishes `gl010-known-message` to the known group after the unknown leave and expects success with `peerCount == 0`.
- Validation evidence:
  - `gofmt -w go-mknoon/node/pubsub_test.go` passed.
  - `cd go-mknoon && go test ./node -run 'TestGL010LeaveUnknownGroupIsNoOpForJoinedGroupState' -count=1` passed (`ok github.com/mknoon/go-mknoon/node 0.608s`).
  - `cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1` passed (`ok github.com/mknoon/go-mknoon/node 17.831s`).
  - `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart` passed (`+5 All tests passed`).
  - `./scripts/run_test_gates.sh groups` passed (`+159 All tests passed`).

## Final Verdict

GL-010 is accepted/closed. The source matrix row is `Covered` with exact no-op proof, adjacent native lifecycle proof, Flutter startup rejoin smoke, named groups gate, and diff hygiene. Residual-only: none. Continue from GL-020, the next unresolved session in ordered ledger order.
