# GR-019 Session Plan: Group Recovery Slot Cancellation Does Not Deadlock

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-019`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 04:18 CEST | Controller | Source matrix GR-019 row; breakdown session ledger row 221; `go-mknoon/node/pubsub.go::acquireGroupRecoverySlot`; `runGroupDiscoveryCycle`; existing group recovery limiter tests | The source row is still `Open` and classified `needs_repo_evidence`/`evidence-gated`. Existing limiter tests prove concurrency caps and queued work draining, but no exact GR-019 proof saturates every slot, cancels the context while one cycle is queued, and proves all active/queued cycles exit without leaking slots. | Add exact GR-019 Go PubSub proof in `go-mknoon/node/pubsub_test.go`, then run focused and adjacent recovery gates plus Flutter lifecycle/resume proof and diff hygiene. |

## Scope

GR-019 owns the group recovery limiter cancellation contract: when many group recovery cycles saturate `groupRecoverySem` and the controlling context is canceled, active and queued cycles must exit and every slot must be released so later recovery can proceed.

Out of scope: real rendezvous network behavior, live group delivery, relay reservation recovery, and Flutter UI behavior.

## Execution Contract

1. Add `go-mknoon/node/pubsub_test.go::TestGR019GroupRecoveryLimiterReleasesSlotsOnCanceledContext`.
2. Start `GroupDiscoveryConcurrency` recovery cycles whose discovery hook blocks on a shared context.
3. Prove all slots are saturated and an extra queued group cannot start before cancellation.
4. Cancel the context and prove active cycles and the queued cycle all exit within a bounded timeout.
5. Inspect `groupRecoverySem` to prove no recovery slots remain held.
6. Run a fresh recovery cycle with a fresh context and prove it can register/discover, then verify the slot count returns to zero.
7. Run focused GR-019, adjacent relay/group recovery owner selector, adjacent Flutter lifecycle/resume proof, formatting, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/pubsub_test.go` |
| Focused GR-019 native proof | `cd go-mknoon && go test ./node -run 'TestGR019GroupRecoveryLimiterReleasesSlotsOnCanceledContext' -count=1` |
| Adjacent relay/group recovery proof | `cd go-mknoon && go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession' -count=1` |
| Adjacent Flutter lifecycle/resume proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GR-019 scope is limited to the exact row-owned Go PubSub regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

Implemented the exact row-owned native proof in `go-mknoon/node/pubsub_test.go::TestGR019GroupRecoveryLimiterReleasesSlotsOnCanceledContext`.

The test starts `GroupDiscoveryConcurrency` group discovery cycles whose rendezvous discovery hooks block on a shared context, proving every slot in `groupRecoverySem` is occupied. It launches one extra queued group and proves that queued cycle cannot start while the limiter is saturated. After canceling the shared context, the test proves every active recovery cycle exits, the queued cycle exits, and no slot remains held.

The same proof then swaps in a fresh discovery hook and runs a fresh recovery cycle with a fresh context, proving new recovery work can still register/discover and that the slot count returns to zero afterward.

Production inspected only: `go-mknoon/node/pubsub.go::acquireGroupRecoverySlot` and `runGroupDiscoveryCycle`. No production runtime change was required.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/pubsub_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run 'TestGR019GroupRecoveryLimiterReleasesSlotsOnCanceledContext' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 0.741s`. |
| `cd go-mknoon && go test ./node -run 'RefreshRelaySession\|ReconnectRelays\|Watchdog\|GroupRecovery\|RelaySession' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 21.636s`. |
| `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+68 All tests passed!`. |
| `git diff --check` | Passed after closure documentation updates. |

## Final Verdict

Accepted/closed. GR-019 is covered by exact row-owned Go PubSub evidence proving saturated group recovery slots are released on context cancellation, queued work exits without deadlock, and later recovery can acquire a fresh slot. Residual-only none for GR-019. Continue from GR-020, the next unresolved session in ordered ledger order; no final program verdict is written because unresolved rows remain.
