# GR-007 Session Plan: Stopped Node Group Recovery Acknowledgement

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-007`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 03:27 CEST | Controller | Source matrix GR-007 row; breakdown session ledger row 214; `go-mknoon/node/node.go::AcknowledgeGroupRecovery`; existing relay-session manager acknowledgement tests | The source row is still `Open`. Existing manager tests prove direct `RelaySessionManager.AcknowledgeGroupRecovery`, but no exact row-owned node-level proof calls `Node.AcknowledgeGroupRecovery` while stopped and proves it returns `node not started` without clearing the pending group recovery signal. | Add exact stopped-node Go proof in `go-mknoon/node/node_test.go`, then run focused and adjacent relay recovery gates plus Flutter lifecycle/resume proof and diff hygiene. |

## Scope

GR-007 owns the public native `Node.AcknowledgeGroupRecovery` guard when the node is stopped or has not started.

Out of scope: successful acknowledgement while running, app-side partial rejoin gating, watchdog restart production behavior, and simulator/device recovery flows.

## Execution Contract

1. Add `go-mknoon/node/node_test.go::TestGR007AcknowledgeGroupRecoveryStoppedNodeFailsWithoutMutatingState`.
2. Seed the node's relay-session manager with a pending group recovery signal.
3. Call public `AcknowledgeGroupRecovery` while the node is stopped.
4. Assert the error is `node not started`.
5. Assert `needsGroupRecovery` remains true and watchdog restart count remains unchanged.
6. Assert no `group_recovery_acknowledged` relay state event is emitted.
7. Run focused GR-007, adjacent relay recovery owner selector, adjacent Flutter lifecycle/resume proof, formatting, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/node_test.go` |
| Focused GR-007 native proof | `cd go-mknoon && go test ./node -run 'TestGR007AcknowledgeGroupRecoveryStoppedNodeFailsWithoutMutatingState' -count=1` |
| Adjacent relay recovery proof | `cd go-mknoon && go test ./node -run 'AcknowledgeGroupRecovery|GroupRecovery|RelaySession|Watchdog' -count=1` |
| Adjacent Flutter lifecycle/resume proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GR-007 scope is limited to the exact row-owned Go recovery regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

Closed on 2026-05-14. Added `go-mknoon/node/node_test.go::TestGR007AcknowledgeGroupRecoveryStoppedNodeFailsWithoutMutatingState`.

The test seeds a pending group-recovery signal with `RecordWatchdogRestart`, verifies `watchdogRestartCount == 1` and `NeedsGroupRecovery() == true`, stops the node, calls public `Node.AcknowledgeGroupRecovery`, and proves the call returns `node not started`. It then proves the failed acknowledgement does not clear `needsGroupRecovery`, does not decrement the watchdog restart count, and does not emit any relay recovery acknowledgement event.

Production inspection found `go-mknoon/node/node.go::AcknowledgeGroupRecovery` already checks `!started || mgr == nil` and returns before mutating relay-session manager state or emitting `group_recovery_acknowledged`, so no production runtime change was required.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/node_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run 'TestGR007AcknowledgeGroupRecoveryStoppedNodeFailsWithoutMutatingState' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 0.595s`. |
| `cd go-mknoon && go test ./node -run 'AcknowledgeGroupRecovery\|GroupRecovery\|RelaySession\|Watchdog' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 21.520s`. |
| `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+68 All tests passed!`. |
| `git diff --check` | Passed after closure docs. |

## Final Verdict

Accepted/closed. GR-007 is `Covered` by exact row-owned native evidence under existing stopped-node guard behavior. Residual-only: none for GR-007. GR-009 is the next unresolved session in ordered ledger order; no final program verdict was written.
