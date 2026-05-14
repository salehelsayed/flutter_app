# GR-013 Session Plan: Foreground Relay Recovery Reports Budgeted Success

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-013`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 04:02 CEST | Controller | Source matrix GR-013 row; breakdown session ledger row 219; `go-mknoon/node/node.go::refreshRelaySessionOwned`; existing foreground refresh tests | The source row is still `Open` and classified `needs_repo_evidence`/`evidence-gated`. Existing foreground tests separately cover cadence, parallelism, fallback, and attribution, but no exact GR-013 row-owned proof closes the matrix row by asserting foreground success, configured warm/wait budgets, and the returned `relayWarmMs`/`circuitAddressWaitMs` fields together. | Add exact GR-013 Go node proof in `go-mknoon/node/node_test.go`, then run focused and adjacent relay recovery gates plus Flutter lifecycle/resume proof and diff hygiene. |

## Scope

GR-013 owns the foreground in-place relay recovery success path: a successful foreground refresh must use the configured foreground relay dial and circuit-address wait budgets and return timing/path attribution fields.

Out of scope: real relay reservation negotiation, background fallback behavior, watchdog restart behavior, group topic rejoin, and UI behavior.

## Execution Contract

1. Add `go-mknoon/node/node_test.go::TestGR013ForegroundRelayRecoveryCompletesWithinConfiguredBudget`.
2. Start a node with a configured fake relay address and `AutoRegister: false`.
3. Capture the timeout passed to `warmRelayConnectionWithTimeoutHook` and the timeout passed to `waitForCircuitAddressHook`.
4. Return immediate success from the foreground circuit-address wait hook.
5. Assert `RefreshRelaySession` succeeds, uses `RecoveryMode == "in_place"` and `ReusedHost == true`, reports `ForegroundRecoveryPath == "foreground_success"`, reports `relayWarmMs`/`circuitAddressWaitMs` as non-negative values within the configured foreground budgets, and includes the configured timeout/cadence fields.
6. Run focused GR-013, adjacent relay recovery owner selector, adjacent Flutter lifecycle/resume proof, formatting, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/node_test.go` |
| Focused GR-013 native proof | `cd go-mknoon && go test ./node -run 'TestGR013ForegroundRelayRecoveryCompletesWithinConfiguredBudget' -count=1` |
| Adjacent relay recovery proof | `cd go-mknoon && go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession' -count=1` |
| Adjacent Flutter lifecycle/resume proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GR-013 scope is limited to the exact row-owned Go node regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

Implemented the exact row-owned native proof in `go-mknoon/node/node_test.go::TestGR013ForegroundRelayRecoveryCompletesWithinConfiguredBudget`.

The test starts a node with a configured fake relay address and captures both foreground budget hooks. It proves `RefreshRelaySession` succeeds in-place without host replacement, passes `ForegroundRelayDialTimeout` to the relay warm path, calls `waitForCircuitAddress` exactly once with `ForegroundCircuitAddressWaitTimeout`, reports `ForegroundRecoveryPath == "foreground_success"`, includes the configured foreground timeout/cadence fields, and returns non-negative `RelayWarmMs`, `CircuitAddressWaitMs`, and `RelayRefreshMs` values. The exact proof also asserts `RelayWarmMs` and `CircuitAddressWaitMs` stay within the configured foreground budgets for the immediate-success hook path.

Production inspected only: `go-mknoon/node/node.go::refreshRelaySessionOwned`. No production runtime change was required.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/node_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run 'TestGR013ForegroundRelayRecoveryCompletesWithinConfiguredBudget' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 0.624s`. |
| `cd go-mknoon && go test ./node -run 'RefreshRelaySession\|ReconnectRelays\|Watchdog\|GroupRecovery\|RelaySession' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 22.169s`. |
| `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+68 All tests passed!`. |
| `git diff --check` | Passed after closure documentation updates. |

## Final Verdict

Accepted/closed. GR-013 is covered by exact row-owned Go node evidence proving foreground relay recovery reports the configured foreground budgets, timing fields, and foreground success path. Residual-only none for GR-013. GR-018 and GR-019 are now covered separately; continue from GR-020, the next unresolved session in ordered ledger order. No final program verdict is written because unresolved rows remain.
