# GR-003 Session Plan: Stalled Recovery Timeout Clears Gate

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-003`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 03:22 CEST | Controller | Source matrix GR-003 row; breakdown session ledger row 213; `go-mknoon/node/relay_session.go::recoveryPromise.Wait` and `ClearStalledRecovery`; existing timeout tests in `go-mknoon/node/relay_session_test.go` | At reconciliation time, the source row lacked closure evidence. Existing manager timeout tests proved the production 30s timeout path, but there was no exact GR-003 row-owned selector with a shortened timeout seam that could prove the stalled recovery gate clears quickly and allows the next recovery to start. | Add a narrow unexported timeout seam on the relay session manager plus exact `GR-003` Go proof, then run focused and adjacent relay recovery gates plus Flutter lifecycle/resume proof and diff hygiene. |

## Scope

GR-003 owns the relay-session manager timeout path for a stalled shared recovery promise: a waiter must receive `RECOVERY_TIMEOUT`, the stuck gate must clear, and a later `BeginRecovery` must be able to start a fresh recovery.

Out of scope: public `RefreshRelaySession` success/failure behavior, watchdog restart fallback policy, group rejoin acknowledgement, and device/simulator recovery flows.

## Execution Contract

1. Add a narrowly scoped manager timeout seam that defaults to `RecoveryWaitTimeout` in production.
2. Add `go-mknoon/node/relay_session_test.go::TestGR003RelaySessionStalledRecoveryClearsGateAfterTimeout`.
3. Start a recovery and intentionally never complete it.
4. Join as a waiter, wait through the shortened timeout, and assert `RECOVERY_TIMEOUT` plus `RecoveryMode == "timeout"`.
5. Assert `IsRecovering()` is false after timeout.
6. Start a fresh recovery and prove it is new, separate from the stalled promise, and can complete successfully.
7. Run focused GR-003, adjacent relay recovery owner selector, adjacent Flutter lifecycle/resume proof, formatting, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/relay_session.go go-mknoon/node/relay_session_test.go` |
| Focused GR-003 native proof | `cd go-mknoon && go test ./node -run 'TestGR003RelaySessionStalledRecoveryClearsGateAfterTimeout' -count=1` |
| Adjacent relay recovery proof | `cd go-mknoon && go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession' -count=1` |
| Adjacent Flutter lifecycle/resume proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GR-003 scope is limited to the relay-session timeout seam, exact row-owned Go recovery regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a broader defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-14 03:23 CEST | Executor | Added an unexported `RelaySessionManager.recoveryWaitTimeout` seam that defaults to `RecoveryWaitTimeout`, copies the timeout into each new `recoveryPromise`, and leaves production behavior at the existing 30s default. Added `go-mknoon/node/relay_session_test.go::TestGR003RelaySessionStalledRecoveryClearsGateAfterTimeout`, which shortens the timeout to 20ms, starts a recovery that never completes, joins as a waiter, proves `RECOVERY_TIMEOUT` plus `RecoveryMode == "timeout"`, proves `IsRecovering()` is false after timeout, starts a fresh recovery, proves it uses a new promise, and completes that fresh recovery successfully. | Covered the row-owned stalled recovery timeout contract with narrow production seam plus exact native proof. |

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/relay_session.go go-mknoon/node/relay_session_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run 'TestGR003RelaySessionStalledRecoveryClearsGateAfterTimeout' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 0.627s`). |
| `cd go-mknoon && go test ./node -run 'RefreshRelaySession\|ReconnectRelays\|Watchdog\|GroupRecovery\|RelaySession' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 21.944s`). |
| `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed (`+68 All tests passed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GR-003 is covered by a narrow timeout seam plus exact Go relay-session evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GR-003; GR-007 is the next unresolved session in ordered ledger order.
