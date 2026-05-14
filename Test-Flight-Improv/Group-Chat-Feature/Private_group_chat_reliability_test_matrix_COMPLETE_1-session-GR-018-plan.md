# GR-018 Session Plan: Recovery Events Are Diagnostic And Privacy-Safe

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-018`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 04:11 CEST | Controller | Source matrix GR-018 row; breakdown session ledger row 220; `go-mknoon/node/node.go::emitRelayStateEvent`; `go-mknoon/node/autorelay_metrics.go::syncRelaySessionFromRuntime`; `go-mknoon/node/relay_session.go::StatusFields`; existing relay recovery and privacy tests | The source row is still `Open` and classified `needs_repo_evidence`/`evidence-gated`. Existing relay recovery tests cover success/failure mechanics, and broader privacy tests cover group-message diagnostics, but no exact GR-018 row-owned proof triggers relay recovery success and failure event paths while proving the relay event payload has useful diagnostics and does not include group plaintext or key material. | Add exact GR-018 Go node proof in `go-mknoon/node/node_test.go`, then run focused and adjacent relay recovery gates plus Flutter lifecycle/resume proof and diff hygiene. |

## Scope

GR-018 owns relay recovery event observability: `relay:state` events emitted during successful relay session sync and watchdog failure must include enough relay diagnostics for app recovery while excluding private group content and key material.

Out of scope: real relay reservation negotiation, Flutter event routing, group topic rejoin behavior, inbox drain behavior, and production logging changes unless the exact proof exposes leaked sensitive fields.

## Execution Contract

1. Add `go-mknoon/node/node_test.go::TestGR018RecoveryEventsAreDiagnosticAndPrivacySafe`.
2. Seed private group plaintext/key sentinels in node-owned group state so the proof can detect accidental relay-event leakage.
3. Trigger the successful runtime relay sync event path with a connected configured relay and a matching circuit address.
4. Trigger the failure event path by driving relay refresh failures to the watchdog threshold and emitting relay state.
5. Assert success events include reason, aggregate online state, healthy relay count, relay peer state, and reservation timestamp diagnostics.
6. Assert failure events include reason, watchdog aggregate state, group-recovery signal, relay peer state, and last-error diagnostics.
7. Recursively assert both event payloads omit sensitive group content/key fields and sentinel values.
8. Run focused GR-018, adjacent relay recovery owner selector, adjacent Flutter lifecycle/resume proof, formatting, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/node_test.go` |
| Focused GR-018 native proof | `cd go-mknoon && go test ./node -run 'TestGR018RecoveryEventsAreDiagnosticAndPrivacySafe' -count=1` |
| Adjacent relay recovery proof | `cd go-mknoon && go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession' -count=1` |
| Adjacent Flutter lifecycle/resume proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GR-018 scope is limited to the exact row-owned Go node regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

Implemented the exact row-owned native proof in `go-mknoon/node/node_test.go::TestGR018RecoveryEventsAreDiagnosticAndPrivacySafe`.

The test seeds node-owned private group state with plaintext and key sentinels, then triggers the successful relay runtime sync event path with a connected configured relay and matching circuit address. It proves the success `relay:state` event reports `reason == refresh_relay_session`, aggregate `relayState == online`, `healthyRelayCount == 1`, `needsGroupRecovery == false`, the relay peer state as `reserved`, and a `lastReservedAt` diagnostic.

The same test drives relay refresh failures to the watchdog threshold and emits the failure `relay:state` event. It proves the failure event reports `reason == watchdog_restart`, aggregate `relayState == watchdog_restart`, `needsGroupRecovery == true`, watchdog count before full restart, relay peer state, and a bounded `lastError` diagnostic. Both event payloads are recursively checked for forbidden sensitive field names and for the seeded private group plaintext/key values.

Production inspected only: `go-mknoon/node/node.go::emitRelayStateEvent`, `go-mknoon/node/autorelay_metrics.go::syncRelaySessionFromRuntime`, and `go-mknoon/node/relay_session.go::StatusFields`. No production runtime change was required.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/node_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run 'TestGR018RecoveryEventsAreDiagnosticAndPrivacySafe' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 0.542s`. |
| `cd go-mknoon && go test ./node -run 'RefreshRelaySession\|ReconnectRelays\|Watchdog\|GroupRecovery\|RelaySession' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 21.646s`. |
| `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+68 All tests passed!`. |
| `git diff --check` | Passed after closure documentation updates. |

## Final Verdict

Accepted/closed. GR-018 is covered by exact row-owned Go node evidence proving relay recovery success/failure events include bounded diagnostics and omit private group content/key material. Residual-only none for GR-018. GR-019 is now covered separately; continue from GR-020, the next unresolved session in ordered ledger order; no final program verdict is written because unresolved rows remain.
