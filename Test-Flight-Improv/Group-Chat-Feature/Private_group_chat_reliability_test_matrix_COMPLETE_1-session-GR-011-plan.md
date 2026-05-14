# GR-011 Session Plan: Relay Connectedness Filters Non-Relay Peers

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-011`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 03:43 CEST | Controller | Source matrix GR-011 row; breakdown session ledger row 217; `go-mknoon/node/node.go::handleRelayConnectednessChanged`; `go-mknoon/node/autorelay_metrics.go::syncRelaySessionFromRuntime`; existing node/relay tests | The source row is still `Open` and classified `evidence-gated`. Existing relay-session tests cover manager state transitions directly, but no exact row-owned node-level proof drives connectedness changes through the configured-relay filter and proves non-relay peers do not create or mutate relay-session state. | Add exact GR-011 Go node proof in `go-mknoon/node/node_test.go`, then run focused and adjacent relay recovery gates plus Flutter lifecycle/resume proof and diff hygiene. |

## Scope

GR-011 owns node-level relay connectedness filtering: only peers configured as relays may update relay-session state when connectedness changes.

Out of scope: actual libp2p event bus delivery, reservation-aware circuit address success, relay refresh/reconnect behavior, app-side recovery, and group topic rejoin.

## Execution Contract

1. Add `go-mknoon/node/node_test.go::TestGR011RelayConnectednessUpdatesOnlyConfiguredRelayPeers`.
2. Configure one relay peer in `relayPeerOrder` and initialize its relay-session state.
3. Simulate a non-relay connectedness change and prove no non-relay relay session is created, no configured relay state changes, and no relay state event is emitted.
4. Simulate a configured relay connectedness change and prove relay-session state updates to connected while status remains scoped to the configured relay.
5. Simulate a non-relay disconnect and prove configured relay state remains unchanged.
6. Simulate a configured relay disconnect and prove relay-session state updates.
7. Run focused GR-011, adjacent relay recovery owner selector, adjacent Flutter lifecycle/resume proof, formatting, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/node_test.go` |
| Focused GR-011 native proof | `cd go-mknoon && go test ./node -run 'TestGR011RelayConnectednessUpdatesOnlyConfiguredRelayPeers' -count=1` |
| Adjacent relay recovery proof | `cd go-mknoon && go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession' -count=1` |
| Adjacent Flutter lifecycle/resume proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GR-011 scope is limited to the exact row-owned Go recovery regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

Implemented the exact row-owned native proof in `go-mknoon/node/node_test.go::TestGR011RelayConnectednessUpdatesOnlyConfiguredRelayPeers`.

The test configures one relay peer in `relayPeerOrder`, initializes only that relay's session state, and then drives `handleRelayConnectednessChanged` directly for both a non-relay peer and the configured relay peer. It proves a non-relay connectedness change creates no relay session, leaves the configured relay disconnected, and emits no relay-state event. It then proves the configured relay connect updates state to `connected` and the status surface contains only that configured relay peer. Finally, it proves a non-relay disconnect still leaves relay state unchanged/no non-relay session, while a configured relay disconnect degrades the configured relay and drops healthy relay count to zero.

Production inspected only: `go-mknoon/node/node.go::handleRelayConnectednessChanged`, which returns unless `isRelayPeer(pid)`, and `go-mknoon/node/autorelay_metrics.go::syncRelaySessionFromRuntime`, which syncs only configured relay peers from `relayPeerOrder`. No production runtime change was required.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/node_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run 'TestGR011RelayConnectednessUpdatesOnlyConfiguredRelayPeers' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 0.545s`. |
| `cd go-mknoon && go test ./node -run 'RefreshRelaySession\|ReconnectRelays\|Watchdog\|GroupRecovery\|RelaySession' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 21.613s`. |
| `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+68 All tests passed!`. |
| `git diff --check` | Passed after closure documentation updates. |

## Final Verdict

Accepted/closed. GR-011 is covered by exact row-owned Go node evidence proving connectedness changes update relay-session state only for configured relay peers. Residual-only none for GR-011. Continue from GR-012, the next unresolved session in ordered ledger order; no final program verdict is written because unresolved rows remain.
