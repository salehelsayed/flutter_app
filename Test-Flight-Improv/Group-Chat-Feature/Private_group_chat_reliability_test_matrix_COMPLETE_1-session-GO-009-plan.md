# GO-009 Group Race Detector Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 22:17 CEST - Local gap-closure pass reached GO-009 after the GO-008 privacy proof required the selected Go race gate. Files inspected: source matrix GO-009 row, session-breakdown GO-009 row, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub.go`, and the failing race output in `/tmp/go008-node-race.log`. Decision: reclassify as active `needs_code_and_tests` work because `go test -race ./node -run 'Group|PubSub|Relay'` failed on repo-owned node lifecycle races.

## Original Source Row

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GO-009 | Test suite runs with race detector for group paths | Go tests available. | 1. Run go test -race for pubsub/inbox/relay. 2. Include concurrent join/update/send tests. | No races in maps, callbacks, recovery manager, or subscription handlers. | P0 | Open | Required | Required | N/A | N/A | N/A | Mandatory for intermittent bugs. |

## Reconciliation Verdict

GO-009 was repo-owned because the source row was `Open` and the required selected race detector command failed. The failure was not an external fixture issue: `TestRefreshRelaySession_ReRegistersPersonalNamespaceOnSuccess`, `TestReconnectRelays_WatchdogRestart_ReRegistersPersonalNamespace`, and `TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart` detected races between old startup/discovery goroutines and later lifecycle resets of `relayReadyOnce` and `relayReady`.

## Device/Relay Proof Profile

- Profile: host Go race proof.
- Source matrix requires Unit and Integration and marks Smoke, Fake Network, and 3-Party E2E as N/A.
- No live device, simulator, relay, OS notification, or multi-relay proof is required for GO-009 closure.
- Supporting named gate: `./scripts/run_test_gates.sh groups`.

## Scope

Own exactly GO-009:

- Fix repo-owned lifecycle races exposed by `go test -race ./node -run 'Group|PubSub|Relay'`.
- Keep node startup relay readiness and group discovery behavior unchanged except for race-safe ownership of per-start state.
- Prove the previously failing tests pass under `-race`.
- Prove the selected group/pubsub/relay race suite passes under `-race`.

## Out Of Scope

- Adding a broader leak checker, which remains GO-010.
- Adding fake-clock flake-budget loops, which remains GO-012.
- Adding device/relay proof, because GO-009 device proof is N/A.
- Refactoring group discovery or relay recovery beyond the race-owning fields.

## Owner Files

- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-009-plan.md`

## Required Validation

```sh
gofmt -w go-mknoon/node/node.go go-mknoon/node/pubsub.go
cd go-mknoon && go test -race ./node -run 'TestRefreshRelaySession_ReRegistersPersonalNamespaceOnSuccess|TestReconnectRelays_WatchdogRestart_ReRegistersPersonalNamespace|TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart' -count=1
cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1
./scripts/run_test_gates.sh groups
git diff --check -- go-mknoon/node/node.go go-mknoon/node/pubsub.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-009-plan.md
```

## Done Criteria

- Source row GO-009 is `Covered` with concrete race-gate evidence.
- Previously failing race tests pass under `-race`.
- Selected group/pubsub/relay race suite passes under `-race`.
- Node lifecycle startup goroutines no longer race with later Start/Stop resets of relay readiness fields.
- No `accepted_with_explicit_follow_up` is used for unresolved GO-009 gaps.

## Execution Evidence

- RED evidence:
  - `cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1` initially failed after 91.339s. Filtered `/tmp/go008-node-race.log` showed `WARNING: DATA RACE` and failures in `TestRefreshRelaySession_ReRegistersPersonalNamespaceOnSuccess`, `TestReconnectRelays_WatchdogRestart_ReRegistersPersonalNamespace`, and `TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart`.
  - Race site 1: `Node.Stop` reset `n.relayReadyOnce` while a startup warm-relay goroutine was still executing `n.relayReadyOnce.Do(...)`.
  - Race site 2: `Node.Start` reset `n.relayReady` while an old `groupPeerDiscoveryLoop` goroutine was still selecting on `n.relayReady`.
- Runtime hardening:
  - `go-mknoon/node/node.go` now stores `relayReadyOnce` as `*sync.Once`, allocates a new once per start cycle, and captures the current `relayReady` channel plus once pointer into warm-relay goroutines.
  - `go-mknoon/node/pubsub.go` now passes the current start-scoped `relayReady` channel into `groupPeerDiscoveryLoop`, so discovery loops select on their own cycle's channel instead of reading a mutable node field after restart.
- Passed validation:
  - `gofmt -w go-mknoon/node/node.go go-mknoon/node/pubsub.go`
  - `cd go-mknoon && go test -race ./node -run 'TestRefreshRelaySession_ReRegistersPersonalNamespaceOnSuccess|TestReconnectRelays_WatchdogRestart_ReRegistersPersonalNamespace|TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart' -count=1` (`ok github.com/mknoon/go-mknoon/node 1.695s`)
  - `cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1` (`ok github.com/mknoon/go-mknoon/node 94.663s`)
  - `./scripts/run_test_gates.sh groups` (`+159 All tests passed`)

## Final Verdict

GO-009 is accepted/closed. The source matrix row is `Covered` with the required selected group/pubsub/relay race detector passing after a narrow repo-owned lifecycle fix. Residual-only: none. Continue from GO-012, the next unresolved P0 session.
