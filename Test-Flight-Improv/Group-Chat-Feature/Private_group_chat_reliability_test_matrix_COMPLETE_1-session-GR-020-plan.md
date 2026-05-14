# GR-020 Session Plan: ReconnectRelays Preserves AutoRegister

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-020`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 04:29 CEST | Controller | Source matrix GR-020 row; breakdown session ledger row 230; `go-mknoon/node/node.go::reconnectRelaysOwned`; existing watchdog restart registration tests | The source row was still `Open` and classified `needs_repo_evidence`/`evidence-gated`. Existing watchdog restart tests proved `AutoRegister=true` re-registers and restores `lastConfig`, but did not prove the paired `true`/`false` contract or that `AutoRegister=false` avoids personal registration and refresh-loop restart after the full restart path. | Add exact GR-020 Go node proof in `go-mknoon/node/node_test.go`, then run focused and adjacent recovery gates plus Flutter lifecycle/resume proof and diff hygiene. |

## Scope

GR-020 owns the `ReconnectRelays` full-restart contract for the original `AutoRegister` setting. The restart path may suppress startup auto-registration while rebuilding the host, but must restore the caller's original setting in `lastConfig` and must only perform personal registration behavior when the original setting was `true`.

Out of scope: live relay server behavior, real rendezvous registration I/O, group topic rejoin behavior, and Flutter UI behavior.

## Execution Contract

1. Add `go-mknoon/node/node_test.go::TestGR020ReconnectRelaysPreservesOriginalAutoRegisterSetting`.
2. Force in-place relay recovery to fail so `ReconnectRelays` takes the watchdog full-restart path.
3. Cover both `AutoRegister=true` and `AutoRegister=false`.
4. For `true`, prove initial and watchdog personal registration use the configured namespace, `lastConfig.AutoRegister` is restored to `true`, and the personal refresh loop is restored.
5. For `false`, prove no personal registration fires before or after the restart, `lastConfig.AutoRegister` is restored to `false`, and no personal refresh loop starts.
6. Run focused GR-020, adjacent relay/group recovery owner selector, adjacent Flutter lifecycle/resume proof, formatting, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/node_test.go` |
| Focused GR-020 native proof | `cd go-mknoon && go test ./node -run 'TestGR020ReconnectRelaysPreservesOriginalAutoRegisterSetting' -count=1` |
| Adjacent relay/group recovery proof | `cd go-mknoon && go test ./node -run 'RefreshRelaySession\|ReconnectRelays\|Watchdog\|GroupRecovery\|RelaySession' -count=1` |
| Adjacent Flutter lifecycle/resume proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GR-020 scope is limited to the exact row-owned Go node regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

Implemented the exact row-owned native proof in `go-mknoon/node/node_test.go::TestGR020ReconnectRelaysPreservesOriginalAutoRegisterSetting`.

The test runs the watchdog full-restart path twice with fake relay and rendezvous hooks: once with `AutoRegister=true` and once with `AutoRegister=false`. Both cases force in-place recovery failure, make the restart obtain a circuit address, and then inspect the restored `lastConfig`.

The `AutoRegister=true` case proves the initial startup registration and watchdog recovery registration both use the configured namespace, the failed in-place refresh runs exactly once before restart, `lastConfig.AutoRegister` is restored to `true`, and the personal refresh loop is restored. The `AutoRegister=false` case proves no personal registration occurs before or after the restart, `lastConfig.AutoRegister` is restored to `false`, and no personal refresh loop starts.

Production inspected only: `go-mknoon/node/node.go::reconnectRelaysOwned` and `go-mknoon/node/personal_rendezvous_refresh.go::recoverPersonalRendezvousRegistration`. No production runtime change was required.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/node_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run 'TestGR020ReconnectRelaysPreservesOriginalAutoRegisterSetting' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 0.751s`. |
| `cd go-mknoon && go test ./node -run 'RefreshRelaySession\|ReconnectRelays\|Watchdog\|GroupRecovery\|RelaySession' -count=1` | Passed: `ok github.com/mknoon/go-mknoon/node 21.908s`. |
| `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+68 All tests passed!`. |
| `git diff --check` | Passed after closure documentation updates. |

## Final Verdict

Accepted/closed. GR-020 is covered by exact row-owned Go node evidence proving `ReconnectRelays` preserves the original `AutoRegister` setting across the watchdog full-restart path and gates personal registration behavior accordingly. Residual-only none for GR-020. No final program verdict is written because unresolved rows remain.
