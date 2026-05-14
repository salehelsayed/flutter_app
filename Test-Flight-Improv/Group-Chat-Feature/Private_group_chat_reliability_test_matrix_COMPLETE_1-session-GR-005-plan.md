# GR-005 Session Plan: Watchdog Restart Clears Runtime Groups

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-005`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 05:42:00 CEST | Controller | Source matrix GR-005 row; breakdown row 153; GR-004 closure evidence; `go-mknoon/node/node.go::Stop` and `ReconnectRelays`; `go-mknoon/node/relay_session.go::CompleteRecovery`; existing Flutter app lifecycle/rejoin tests | The source row was `Open` and the breakdown marked GR-005 `needs_code_and_tests` / `implementation-ready`. Production already uses the full `Stop()` / `Start()` fallback after in-place recovery failure, and `Stop()` clears group topic/subscription/config/key maps while `CompleteRecovery` sets `needsGroupRecovery`; however no exact row-owned test drove the fallback, inspected the cleared runtime maps, and proved publish fails until explicit app rejoin. | Add exact row-owned Go proof for forced watchdog restart, cleared runtime group maps, `needsGroupRecovery`, blocked pre-rejoin publish, and successful explicit rejoin publish. Run adjacent native relay recovery and Flutter lifecycle/rejoin selectors before closing. |

## Scope

GR-005 owns the full restart fallback path after in-place relay recovery fails. The row requires the native runtime group maps to be empty after restart, the recovery signal to remain visible to the app, and sends to fail honestly until the app explicitly rejoins the group topic.

Out of scope: acknowledging recovery only after all app topics rejoin, watchdog signal persistence helper tests, relay outage delivery repair, and multi-group watchdog recovery delivery. Those are owned by later GR rows.

## Execution Contract

1. Add a row-named Go node regression that joins a private group, forces `ReconnectRelays` to fall back from failed in-place recovery to watchdog/full restart, and records native group runtime state before and after.
2. Assert the fallback returns `RecoveryMode == watchdog_restart`, does not reuse the host, rebuilds PubSub, clears the joined group topic/subscription/config/key maps, increments the watchdog restart count, and sets `needsGroupRecovery == true`.
3. Attempt `PublishGroupMessage` before app rejoin and assert it fails with `group not joined`, empty message id, and peer count zero.
4. Explicitly call `JoinGroupTopic` with the saved app-owned config/key and assert a publish succeeds after rejoin.
5. Run focused GR-005, adjacent relay recovery, combined GR-004/GR-005 native recovery, race, app lifecycle/rejoin, fake-network watchdog resume, gofmt, and `git diff --check` gates.
6. Update the source matrix, breakdown ledgers, and this plan with concrete evidence before acceptance.

## Required Gates

| Gate | Command |
|---|---|
| Focused Go proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR005'` from `go-mknoon` |
| Adjacent relay recovery proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR005|ReconnectRelays|Watchdog|GroupRecovery|RelaySession'` from `go-mknoon` |
| Combined GR-004/GR-005 proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR004|TestGR005|RefreshRelaySession|ReconnectRelays|GroupRecovery'` from `go-mknoon` |
| Race selector | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test -race ./node -run 'TestGR005|ReconnectRelays|Watchdog'` from `go-mknoon` |
| App lifecycle selectors | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'rejoins and acknowledges when Go signals group recovery'`; `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, retryFailed, then retryFailedGroupInboxStores'` |
| Fake-network resume selectors | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and receives subsequent live messages'`; `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and resumes live delivery'` |
| Hygiene | `gofmt -w go-mknoon/node/pubsub_test.go`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree already contained many prior rollout code, test, source-matrix, and session-breakdown edits. GR-005 scope is limited to `go-mknoon/node/pubsub_test.go`, this plan, the source matrix row GR-005, and breakdown closure documentation unless focused gates expose a production defect.

## Execution Evidence

- Added `go-mknoon/node/pubsub_test.go::TestGR005WatchdogRestartClearsGroupTopicsAndRequiresExplicitRejoin`.
- No production code changed for GR-005. Existing production already routes failed in-place relay refresh through `ReconnectRelays` full restart, where `Stop()` clears `groupTopics`, `groupSubs`, `groupConfigs`, and `groupKeys`; `relay_session.go::CompleteRecovery` marks `needsGroupRecovery` for watchdog restarts.
- The row-owned test starts a node, joins one private group, records host/topic/subscription/config/key state, forces `ReconnectRelays` through failed in-place recovery into watchdog restart, proves the host is replaced, PubSub is rebuilt, all group runtime maps are empty, `needsGroupRecovery` is true, and `watchdogRestartCount == 1`.
- The test then proves `PublishGroupMessage` fails before explicit rejoin with `group not joined`, empty message id, and peer count zero, then calls `JoinGroupTopic` with the saved app-owned config/key and proves publish succeeds after rejoin.

## Verification

- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR005'` passed (`ok node 1.158s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR005|ReconnectRelays|Watchdog|GroupRecovery|RelaySession'` passed (`ok node 21.636s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR004|TestGR005|RefreshRelaySession|ReconnectRelays|GroupRecovery'` passed (`ok node 21.838s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test -race ./node -run 'TestGR005|ReconnectRelays|Watchdog'` passed (`ok node 2.151s`).
- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'rejoins and acknowledges when Go signals group recovery'` passed (`+1`).
- `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, retryFailed, then retryFailedGroupInboxStores'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and receives subsequent live messages'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and resumes live delivery'` passed (`+1`).
- `gofmt -l go-mknoon/node/pubsub_test.go` passed with no output.
- `git diff --check` passed.

## Final Verdict

Accepted/closed. GR-005 is `Covered` by row-owned Go node evidence proving watchdog/full restart clears native runtime group topics, subscriptions, configs, and keys; signals `needsGroupRecovery`; rejects sends before app rejoin; and accepts sends after explicit rejoin. Existing production satisfied the row once exact proof was added, so no production change was required. Residual-only: none for GR-005. GR-006 is the next unresolved P0 row in session order; no final program verdict was written.
