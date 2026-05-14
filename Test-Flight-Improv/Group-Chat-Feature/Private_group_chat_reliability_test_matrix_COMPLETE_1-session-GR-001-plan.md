# GR-001 Session Plan: RefreshRelaySession Not Started

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-001`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 03:00 CEST | Controller | Source matrix GR-001 row; breakdown session ledger row 211; absence of adjacent GR-001 plan; `go-mknoon/node/node.go::RefreshRelaySession`; existing relay recovery tests in `go-mknoon/node/node_test.go`; required source expectation `NOT_STARTED` with `reusedHost: true` and no panic | At reconciliation time, the source row lacked closure evidence and no adjacent GR-001 plan existed. Production code already has a not-started branch in `refreshRelaySessionOwned`, but no exact GR-001-owned selector proved the public `RefreshRelaySession` call returned the expected structured failure and cleared the shared recovery gate for a later call. | Add exact row-owned Go proof in `go-mknoon/node/node_test.go`, then run focused and adjacent relay recovery gates plus diff hygiene. |

## Scope

GR-001 owns the public native `RefreshRelaySession` behavior before the node is started. It should fail clearly, avoid panic, report `ErrorCode == "NOT_STARTED"`, preserve `RecoveryMode == "in_place"`, and report `ReusedHost == true`.

Out of scope: successful relay recovery, watchdog restart fallback, app-side group rejoin acknowledgement, relay connection health updates, and simulator/device recovery flows.

## Execution Contract

1. Add `go-mknoon/node/node_test.go::TestGR001RefreshRelaySessionNotStartedReturnsStructuredFailure`.
2. Call `RefreshRelaySession` on a fresh unstarted node.
3. Assert a non-nil failed result with `RecoveryMode == "in_place"`, `ErrorCode == "NOT_STARTED"`, reason `node not started`, and `ReusedHost == true`.
4. Assert no host is created as a side effect.
5. Call `RefreshRelaySession` a second time and assert it returns the same structured not-started failure, proving the recovery gate is cleared and reusable.
6. Run focused GR-001, adjacent relay recovery owner selector, named groups gate if needed by closure, gofmt, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/node_test.go` |
| Focused GR-001 native proof | `cd go-mknoon && go test ./node -run 'TestGR001RefreshRelaySessionNotStartedReturnsStructuredFailure' -count=1` |
| Adjacent relay recovery proof | `cd go-mknoon && go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession' -count=1` |
| Adjacent Flutter lifecycle/resume proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GR-001 scope is limited to the exact row-owned Go recovery regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-14 03:04 CEST | Executor | Added `go-mknoon/node/node_test.go::TestGR001RefreshRelaySessionNotStartedReturnsStructuredFailure`. The test calls `RefreshRelaySession` on a fresh unstarted node, proves the returned `RecoveryResult` is non-nil, unsuccessful, `RecoveryMode == "in_place"`, `ErrorCode == "NOT_STARTED"`, `Reason == "node not started"`, and `ReusedHost == true`, then proves no host was created, the node was not marked started, the shared recovery gate is cleared, and a second call returns the same structured not-started failure. | Covered the row-owned public not-started relay refresh contract with tests-only native evidence; no production code change required because existing `refreshRelaySessionOwned` behavior already satisfies the contract once exact proof exists. |

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/node_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run 'TestGR001RefreshRelaySessionNotStartedReturnsStructuredFailure' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 0.534s`). |
| `cd go-mknoon && go test ./node -run 'RefreshRelaySession\|ReconnectRelays\|Watchdog\|GroupRecovery\|RelaySession' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 21.543s`). |
| `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed (`+68 All tests passed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GR-001 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GR-001; GR-002 is the next unresolved session in ordered ledger order.
