# GR-010 Session Plan: Refresh Success Resets Failure State

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-010`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 03:37 CEST | Controller | Source matrix GR-010 row; breakdown session ledger row 216; `go-mknoon/node/relay_session.go::OnRefreshSucceeded`; existing `TestWatchdog_SingleSuccessfulRefreshResetsFailureCounter` | The source row is still `Open` and classified `implementation-ready`. Existing adjacent test proves the counter reset, but it does not own GR-010 by name and does not prove reserved state, stale `LastError` clearing, aggregate/status state, or relay-state status omission of `lastError`. | Add exact GR-010 Go proof in `go-mknoon/node/relay_session_test.go`, then run focused and adjacent relay recovery gates plus Flutter lifecycle/resume proof and diff hygiene. |

## Scope

GR-010 owns the per-relay state after a failed refresh streak is followed by `OnRefreshSucceeded`.

Out of scope: multi-relay threshold behavior, watchdog restart execution, app-side rejoin acknowledgement, and foreground recovery timing.

## Execution Contract

1. Add `go-mknoon/node/relay_session_test.go::TestGR010RefreshSuccessResetsFailureCounterAndStaleError`.
2. Open one relay reservation.
3. Record refresh failures below the watchdog threshold.
4. Prove the session has non-zero consecutive failures and a stored last error before success.
5. Call `OnRefreshSucceeded`.
6. Prove consecutive failures reset to zero, state is reserved, stale last error is cleared, aggregate state is online, no group recovery is needed, and `StatusFields()` reports no stale relay `lastError`.
7. Run focused GR-010, adjacent relay recovery owner selector, adjacent Flutter lifecycle/resume proof, formatting, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/relay_session_test.go` |
| Focused GR-010 native proof | `cd go-mknoon && go test ./node -run 'TestGR010RefreshSuccessResetsFailureCounterAndStaleError' -count=1` |
| Adjacent relay recovery proof | `cd go-mknoon && go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession' -count=1` |
| Adjacent Flutter lifecycle/resume proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GR-010 scope is limited to the exact row-owned Go recovery regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

Closed on 2026-05-14. Added `go-mknoon/node/relay_session_test.go::TestGR010RefreshSuccessResetsFailureCounterAndStaleError`.

The test opens a relay reservation, records refresh failures below the watchdog threshold, proves the session has non-zero consecutive failures and a stored last error, then calls `OnRefreshSucceeded`. It proves consecutive failures reset to zero, state is `reserved`, `LastError` clears, `LastReservedAt` is set, `needsGroupRecovery` remains false, aggregate state returns to `online`, and `StatusFields()` reports `online`/healthy state without a stale relay `lastError`.

Production inspection found `go-mknoon/node/relay_session.go::OnRefreshSucceeded` already resets the consecutive counter, restores `RelayStateReserved`, updates reservation time, clears `LastError`, and recomputes aggregate state, so no production runtime change was required.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/relay_session_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run 'TestGR010RefreshSuccessResetsFailureCounterAndStaleError' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 0.469s`. |
| `cd go-mknoon && go test ./node -run 'RefreshRelaySession\|ReconnectRelays\|Watchdog\|GroupRecovery\|RelaySession' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 21.766s`. |
| `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+68 All tests passed!`. |
| `git diff --check` | Passed after closure docs. |

## Final Verdict

Accepted/closed. GR-010 is `Covered` by exact row-owned native evidence under existing refresh-success reset behavior. Residual-only: none for GR-010. GR-011 is the next unresolved session in ordered ledger order; no final program verdict was written.
