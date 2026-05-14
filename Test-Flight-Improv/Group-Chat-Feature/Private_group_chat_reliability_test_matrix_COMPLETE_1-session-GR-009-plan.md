# GR-009 Session Plan: Multi-Relay Watchdog Threshold

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-009`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 03:32 CEST | Controller | Source matrix GR-009 row; breakdown session ledger row 215; `go-mknoon/node/relay_session.go::OnRefreshFailed`; existing single-relay watchdog tests | The source row is still `Open` and classified `implementation-ready`. Existing watchdog tests cover one relay and success-reset behavior, but no exact row-owned proof covers multiple relay sessions where one relay reaches the threshold while another tracked relay remains reserved/below threshold. | Add exact multi-relay watchdog threshold proof in `go-mknoon/node/relay_session_test.go`, then run focused and adjacent relay recovery gates plus Flutter lifecycle/resume proof and diff hygiene. |

## Scope

GR-009 owns the relay-session manager watchdog policy for multiple tracked relay sessions with mixed refresh-failure counts.

Out of scope: successful refresh reset behavior, app-side rejoin acknowledgement, node restart execution, stale circuit-address health reporting, and foreground recovery timing.

## Execution Contract

1. Add `go-mknoon/node/relay_session_test.go::TestGR009RefreshFailuresTriggerWatchdogOnlyAfterAllRelaysReachThreshold`.
2. Open two relay reservations.
3. Fail one relay just below the watchdog threshold and prove no group recovery signal.
4. Fail that relay through the threshold while the second relay remains reserved/below threshold and prove no group recovery signal.
5. Fail the second relay just below the threshold and prove no group recovery signal.
6. Fail the second relay through the threshold and prove `needsGroupRecovery == true` plus aggregate `watchdog_restart`.
7. Run focused GR-009, adjacent relay recovery owner selector, adjacent Flutter lifecycle/resume proof, formatting, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/relay_session_test.go` |
| Focused GR-009 native proof | `cd go-mknoon && go test ./node -run 'TestGR009RefreshFailuresTriggerWatchdogOnlyAfterAllRelaysReachThreshold' -count=1` |
| Adjacent relay recovery proof | `cd go-mknoon && go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession' -count=1` |
| Adjacent Flutter lifecycle/resume proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GR-009 scope is limited to the exact row-owned Go recovery regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

Closed on 2026-05-14. Added `go-mknoon/node/relay_session_test.go::TestGR009RefreshFailuresTriggerWatchdogOnlyAfterAllRelaysReachThreshold`.

The test opens two relay reservations, fails relay A to just below the watchdog threshold, proves `needsGroupRecovery` remains false and aggregate state is not `watchdog_restart`, then fails relay A through the threshold while relay B remains reserved with zero failures and proves watchdog still does not trigger. It then fails relay B to just below threshold and proves no watchdog signal, finally fails relay B through the threshold and proves `needsGroupRecovery == true`, aggregate state is `watchdog_restart`, and `StatusFields()` reports the same recovery facts.

Production inspection found `go-mknoon/node/relay_session.go::OnRefreshFailed` already blocks watchdog transition while any reserved relay remains below `WatchdogMaxConsecutiveFailures`, so no production runtime change was required.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/relay_session_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run 'TestGR009RefreshFailuresTriggerWatchdogOnlyAfterAllRelaysReachThreshold' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 0.569s`. |
| `cd go-mknoon && go test ./node -run 'RefreshRelaySession\|ReconnectRelays\|Watchdog\|GroupRecovery\|RelaySession' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 21.640s`. |
| `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+68 All tests passed!`. |
| `git diff --check` | Passed after closure docs. |

## Final Verdict

Accepted/closed. GR-009 is `Covered` by exact row-owned native evidence under existing multi-relay watchdog threshold behavior. Residual-only: none for GR-009. GR-010 is the next unresolved session in ordered ledger order; no final program verdict was written.
