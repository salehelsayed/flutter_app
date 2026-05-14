# GR-008 Session Plan: Watchdog Restart Signal Survives Reset

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-008`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 05:55:00 CEST | Controller | Source matrix GR-008 row; breakdown row 155; `go-mknoon/node/relay_session.go::RecordWatchdogRestart`, `Reset`, `StatusFields`, `AcknowledgeGroupRecovery`; existing watchdog and reset tests; GR-005/GR-006 closure evidence | The source row was `Open` and the breakdown marked GR-008 `needs_code_and_tests` / `implementation-ready`. Production already increments `watchdogRestartCount` and sets `needsGroupRecovery` in `RecordWatchdogRestart`, while `Reset` clears relay sessions and aggregate state without clearing the restart counter or recovery signal. Existing tests covered pieces separately but not the exact call sequence `RecordWatchdogRestart` then `Reset` then status inspection. | Add exact row-owned Go relay-session proof for `RecordWatchdogRestart` followed by `Reset`, proving the counter and recovery signal survive until explicit acknowledgment while sessions are cleared. |

## Scope

GR-008 owns native relay-session persistence of the watchdog restart telemetry and group recovery signal across a full host reset. The contract is that `Reset()` may clear relay session state, but it must not erase `watchdogRestartCount` or `needsGroupRecovery` before Flutter has rejoined and acknowledged recovery.

Out of scope: app-side acknowledgment gating, watchdog full restart group rejoin delivery, relay recovery thresholds, and relay-ready discovery. Those are covered by GR-006 or later GR rows.

## Execution Contract

1. Add a row-named Go test in `relay_session_test.go`.
2. Call `RecordWatchdogRestart`, assert `watchdogRestartCount == 1` and `needsGroupRecovery == true`.
3. Call `Reset`, assert relay sessions/healthy count are cleared and aggregate state returns to starting, while `watchdogRestartCount` and `needsGroupRecovery` remain visible in direct methods and `StatusFields`.
4. Call `AcknowledgeGroupRecovery` and assert only explicit acknowledgment clears the recovery signal.
5. Run focused GR-008, adjacent reset/watchdog/recovery selectors, race, gofmt, and `git diff --check`.
6. Update the source matrix, breakdown ledgers, and this plan with concrete evidence before acceptance.

## Required Gates

| Gate | Command |
|---|---|
| Focused Go proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR008'` from `go-mknoon` |
| Adjacent reset/watchdog proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR008|RecordWatchdogRestart|Reset|WatchdogRestartCount|NeedsGroupRecovery'` from `go-mknoon` |
| Adjacent relay recovery proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR005|TestGR008|ReconnectRelays|Watchdog|GroupRecovery|RelaySession'` from `go-mknoon` |
| Race selector | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test -race ./node -run 'TestGR008|RecordWatchdogRestart|Reset|Watchdog'` from `go-mknoon` |
| Hygiene | `gofmt -w go-mknoon/node/relay_session_test.go`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree already contained prior rollout edits and the accepted GR-004 through GR-006 changes. GR-008 scope is limited to `go-mknoon/node/relay_session_test.go`, this plan, the source matrix row GR-008, and breakdown closure documentation unless focused gates expose a production defect.

## Execution Evidence

- Added `go-mknoon/node/relay_session_test.go::TestGR008RecordWatchdogRestartPreservesRecoverySignalAcrossReset`.
- No production code changed for GR-008. Existing `RecordWatchdogRestart` and `Reset` already satisfy the row contract.
- The test opens a relay reservation, calls `RecordWatchdogRestart`, proves `watchdogRestartCount == 1` and `needsGroupRecovery == true`, calls `Reset`, proves sessions/healthy count are cleared and aggregate state is `starting`, then proves direct methods and `StatusFields` still report `watchdogRestartCount == 1` and `needsGroupRecovery == true`.
- The test finally calls `AcknowledgeGroupRecovery` and proves the recovery signal clears only on explicit acknowledgment.

## Verification

- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR008'` passed (`ok github.com/mknoon/go-mknoon/node 0.515s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR008|RecordWatchdogRestart|Reset|WatchdogRestartCount|NeedsGroupRecovery'` passed (`ok github.com/mknoon/go-mknoon/node 2.878s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR005|TestGR008|ReconnectRelays|Watchdog|GroupRecovery|RelaySession'` passed (`ok github.com/mknoon/go-mknoon/node 21.707s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test -race ./node -run 'TestGR008|RecordWatchdogRestart|Reset|Watchdog'` passed (`ok github.com/mknoon/go-mknoon/node 4.176s`).
- `gofmt -l go-mknoon/node/relay_session_test.go` passed with no output.
- `git diff --check` passed.

## Final Verdict

Accepted/closed. GR-008 is `Covered` by row-owned Go relay-session evidence proving `RecordWatchdogRestart` preserves `watchdogRestartCount` and `needsGroupRecovery` across `Reset`, and only explicit acknowledgment clears the recovery signal. Residual-only: none for GR-008. GR-014 is the next unresolved P0 session in ledger order; no final program verdict was written.
