# GL-020 Bulk Group Recovery Concurrency Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 23:06 CEST - Local gap-closure pass reached GL-020 after GL-016 closure. Files inspected: source matrix GL-020 row, session-breakdown GL-020 row, `go-mknoon/node/pubsub.go` recovery limiter and discovery cycle code, existing recovery limiter tests, Flutter startup rejoin smoke, and lifecycle rejoin code. Decision: keep GL-020 as `needs_tests_only`; production already owns the bounded `groupRecoverySem` / `GroupDiscoveryConcurrency` behavior, but the source row was `Open` and no exact row-owned proof showed a many-group recovery queue draining every group without starving an affected group.

## Original Source Row

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GL-020 | Bulk recovery of many groups respects group recovery concurrency | User has many private groups. | 1. Trigger relay/group recovery. 2. Rejoin/discover many groups. 3. Measure events and sem slots. | Recovery is bounded, eventually attempts every group, and does not starve the affected private group. | P1 | Open | Required | Required | N/A | Recommended | N/A | Uses groupRecoverySem and GroupDiscoveryConcurrency. |

## Reconciliation Verdict

GL-020 was repo-owned because the row targets native group discovery/recovery concurrency behavior implemented in this repository. Existing tests proved the limiter caps concurrent workers and jitters resumed bursts, but did not prove the row's missing acceptance condition: a saturated many-group recovery burst eventually attempts every queued group, including a specific affected group queued behind the active slots.

## Scope

Own exactly GL-020:

- Add an exact Go regression for many-group recovery limiter drain behavior.
- Saturate `GroupDiscoveryConcurrency` slots before queueing more groups.
- Queue an affected private group behind the saturated slots.
- Prove no queued group acquires before a slot is released.
- Prove every group registers/discovers exactly once after release.
- Prove `maxActive` never exceeds `GroupDiscoveryConcurrency`.
- Update the source matrix, breakdown ledgers, and test inventory with concrete evidence.

## Out Of Scope

- Changing `groupRecoverySem` or `GroupDiscoveryConcurrency`; current implementation already satisfies the limiter contract.
- Adding Flutter app-level rejoin parallelism; the row's explicit limiter surface is the Go group recovery semaphore, while Flutter startup rejoin smoke remains supporting app evidence.
- Device or relay-lab proof, because GL-020 3-Party E2E is N/A and Fake Network evidence is Recommended.

## Owner Files

- `go-mknoon/node/pubsub_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-020-plan.md`

## Required Validation

```sh
gofmt -w go-mknoon/node/pubsub_test.go
cd go-mknoon && go test ./node -run 'TestGL020GroupRecoveryLimiterDrainsManyGroupsWithoutStarvingAffectedGroup' -count=1
cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery|GroupDiscovery' -count=1
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart
./scripts/run_test_gates.sh groups
git diff --check -- go-mknoon/node/pubsub_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-020-plan.md
```

## Done Criteria

- Source row GL-020 is `Covered` with concrete file/test/gate evidence.
- Exact row-owned Go proof exists and passes.
- The proof forces queued group recovery work behind a saturated semaphore.
- Every queued group, including the affected group, is eventually registered/discovered.
- Concurrency is bounded at `GroupDiscoveryConcurrency`.
- No `accepted_with_explicit_follow_up` is used for unresolved GL-020 gaps.

## Execution Evidence

- Exact test:
  - `go-mknoon/node/pubsub_test.go::TestGL020GroupRecoveryLimiterDrainsManyGroupsWithoutStarvingAffectedGroup` creates `GroupDiscoveryConcurrency*3 + 1` group recovery cycles, launches the first `GroupDiscoveryConcurrency` cycles to saturate `groupRecoverySem`, queues the remaining cycles plus `gl020-affected-group`, and verifies no queued cycle starts until a slot is released.
  - The test uses rendezvous register/discover hooks to count per-group attempts, records `maxActive`, releases the saturated discover hooks, waits for the queue to drain, and proves every group registered/discovered exactly once.
  - The test proves `maxActive == GroupDiscoveryConcurrency` and the affected group was discovered exactly once, closing the bounded/no-starvation acceptance condition.
- Validation evidence:
  - `gofmt -w go-mknoon/node/pubsub_test.go` passed.
  - `cd go-mknoon && go test ./node -run 'TestGL020GroupRecoveryLimiterDrainsManyGroupsWithoutStarvingAffectedGroup' -count=1` passed (`ok github.com/mknoon/go-mknoon/node 0.760s`).
  - `cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery|GroupDiscovery' -count=1` passed (`ok github.com/mknoon/go-mknoon/node 19.205s`).
  - `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart` passed (`+5 All tests passed`).
  - `./scripts/run_test_gates.sh groups` passed (`+159 All tests passed`).

## Final Verdict

GL-020 is accepted/closed. The source matrix row is `Covered` with exact many-group recovery limiter drain/no-starvation proof, adjacent native group recovery/discovery proof, Flutter startup rejoin smoke, named groups gate, and diff hygiene. Residual-only: none. Continue from GM-032, the next unresolved session in ordered ledger order.
