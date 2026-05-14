# GR-012 Session Plan: Stale Circuit Addresses Do Not Report Healthy

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-012`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 03:55 CEST | Controller | Source matrix GR-012 row; breakdown session ledger row 218; `go-mknoon/node/relay_session.go::CircuitAddressesAreStale`, `ReportsHealthyWithReservation`, `IgnoresStaleCircuitAddresses`, and `StatusFields`; existing relay-session tests | The source row is still `Open` and classified `needs_code_and_tests`/`implementation-ready`. Existing generic stale-circuit tests cover the helper in part, but no exact GR-012 row-owned proof starts from a host-reported circuit address with no reserved sessions and asserts stale detection, filtered trust, no healthy reservation report, and status remaining non-online. | Add exact GR-012 Go relay-session proof in `go-mknoon/node/relay_session_test.go`, then run focused and adjacent relay recovery gates plus Flutter lifecycle/resume proof and diff hygiene. |

## Scope

GR-012 owns reservation-aware stale circuit address health: a host-reported `/p2p-circuit` address must not make relay health online unless the relay session manager has an active reserved relay.

Out of scope: live libp2p reservation negotiation, AutoRelay event delivery, node restart recovery, app-side group rejoin, and UI behavior.

## Execution Contract

1. Add `go-mknoon/node/relay_session_test.go::TestGR012StaleCircuitAddressesDoNotReportHealthyWithoutReservation`.
2. Start with an initialized relay session but no reservation and a host-reported circuit address.
3. Prove `CircuitAddressesAreStale` returns true.
4. Prove `ReportsHealthyWithReservation` returns false and `IgnoresStaleCircuitAddresses` filters the stale circuit address.
5. Prove `StatusFields` does not report online health: `relayState` is not online, `healthyRelayCount == 0`, and no `lastReservationAt` is exposed.
6. Open a reservation as the positive control and prove stale detection clears, the circuit address becomes trusted, and status becomes online with one healthy relay.
7. End the reservation and prove stale detection returns, trusted circuit address filtering empties again, and status is no longer online.
8. Run focused GR-012, adjacent relay recovery owner selector, adjacent Flutter lifecycle/resume proof, formatting, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/relay_session_test.go` |
| Focused GR-012 native proof | `cd go-mknoon && go test ./node -run 'TestGR012StaleCircuitAddressesDoNotReportHealthyWithoutReservation' -count=1` |
| Adjacent relay recovery proof | `cd go-mknoon && go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession' -count=1` |
| Adjacent Flutter lifecycle/resume proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GR-012 scope is limited to the exact row-owned Go relay-session regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

Implemented the exact row-owned native proof in `go-mknoon/node/relay_session_test.go::TestGR012StaleCircuitAddressesDoNotReportHealthyWithoutReservation`.

The test starts from an initialized relay session with no active reservation and a host-reported `/p2p-circuit` address. It proves the address is stale, `ReportsHealthyWithReservation` stays false, `IgnoresStaleCircuitAddresses` returns no trusted address, and `StatusFields` does not report online health (`healthyRelayCount == 0`, `relayState` not online, and no `lastReservationAt`). It then opens a reservation as a positive control and proves stale detection clears, the address is trusted, and status becomes online with one healthy relay. Finally, it ends the reservation and proves stale detection returns, trusted address filtering empties again, and status is no longer online.

Production inspected only: `go-mknoon/node/relay_session.go::CircuitAddressesAreStale`, `ReportsHealthyWithReservation`, `IgnoresStaleCircuitAddresses`, and `StatusFields`. No production runtime change was required.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/relay_session_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run 'TestGR012StaleCircuitAddressesDoNotReportHealthyWithoutReservation' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 0.967s`. |
| `cd go-mknoon && go test ./node -run 'RefreshRelaySession\|ReconnectRelays\|Watchdog\|GroupRecovery\|RelaySession' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 21.974s`. |
| `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+68 All tests passed!`. |
| `git diff --check` | Passed after closure documentation updates. |

## Final Verdict

Accepted/closed. GR-012 is covered by exact row-owned Go relay-session evidence proving stale host-reported circuit addresses without reservations are detected and never reported as healthy/online. Residual-only none for GR-012. Continue from GR-013, the next unresolved session in ordered ledger order; no final program verdict is written because unresolved rows remain.
