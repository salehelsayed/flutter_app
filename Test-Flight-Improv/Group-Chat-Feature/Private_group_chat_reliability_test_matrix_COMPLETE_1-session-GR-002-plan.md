# GR-002 Session Plan: Concurrent RefreshRelaySession Coalescing

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-002`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 03:12 CEST | Controller | Source matrix GR-002 row; breakdown session ledger row 212; adjacent relay recovery implementation in `go-mknoon/node/node.go` and `go-mknoon/node/relay_session.go`; existing manager-only and `ReconnectRelays` coalescing tests in `go-mknoon/node/relay_session_test.go` and `go-mknoon/node/node_test.go` | At reconciliation time, the source row lacked closure evidence. Existing tests proved manager-level coalescing and `ReconnectRelays` coalescing, but no exact row-owned proof started a node, blocked the public `RefreshRelaySession` owner hook, fanned in concurrent public `RefreshRelaySession` callers, and verified all callers received the same in-place result with the expected coalesced count. | Add exact public-node Go proof in `go-mknoon/node/node_test.go`, then run focused GR-002 and adjacent relay recovery gates plus Flutter lifecycle/resume proof and diff hygiene. |

## Scope

GR-002 owns public native `RefreshRelaySession` singleflight behavior while the node is already started and the in-place recovery hook is blocked.

Out of scope: manager-only coalescing, watchdog restart fallback, stalled recovery timeout, group topic preservation, app-level rejoin acknowledgement, and simulator/device recovery flows.

## Execution Contract

1. Add `go-mknoon/node/node_test.go::TestGR002ConcurrentRefreshRelaySessionCallsCoalesce`.
2. Start a node with relay hooks that avoid real network dependency.
3. Block the first `refreshRelaySessionHook` invocation so it owns the recovery.
4. Invoke multiple concurrent public `RefreshRelaySession` calls.
5. Prove the shared recovery promise records the expected waiter count before releasing the owner hook.
6. Prove only one refresh hook invocation ran.
7. Prove every caller receives the same successful in-place result with `ReusedHost == true` and `CoalescedRecoveryRequests == waiters`.
8. Prove the shared recovery gate clears after completion.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/node_test.go` |
| Focused GR-002 native proof | `cd go-mknoon && go test ./node -run 'TestGR002ConcurrentRefreshRelaySessionCallsCoalesce' -count=1` |
| Adjacent relay recovery proof | `cd go-mknoon && go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession' -count=1` |
| Adjacent Flutter lifecycle/resume proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GR-002 scope is limited to the exact row-owned Go recovery regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-14 03:16 CEST | Executor | Added `go-mknoon/node/node_test.go::TestGR002ConcurrentRefreshRelaySessionCallsCoalesce`. The test starts a node with fake relay hooks, blocks the first public `RefreshRelaySession` owner in `refreshRelaySessionHook`, starts four concurrent public `RefreshRelaySession` callers, waits until the shared recovery promise records three coalesced waiters, releases the owner, and proves every caller receives the same successful in-place result with `ReusedHost == true` and `CoalescedRecoveryRequests == 3`. It also proves only one refresh hook invocation ran and the shared recovery gate clears after completion. | Covered the row-owned public relay refresh coalescing contract with tests-only native evidence; no production code change required because existing `RefreshRelaySession` plus `RelaySessionManager.BeginRecovery`/`CompleteRecovery` already satisfy the contract once exact proof exists. |

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/node_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run 'TestGR002ConcurrentRefreshRelaySessionCallsCoalesce' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 0.582s`). |
| `cd go-mknoon && go test ./node -run 'RefreshRelaySession\|ReconnectRelays\|Watchdog\|GroupRecovery\|RelaySession' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 21.607s`). |
| `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed (`+68 All tests passed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GR-002 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GR-002; GR-003 is the next unresolved session in ordered ledger order.
