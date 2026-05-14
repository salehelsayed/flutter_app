# GR-004 Session Plan: In-Place Relay Recovery Preserves Group Topics

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-004`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 05:28:00 CEST | Controller | Source matrix GR-004 row; breakdown row 152; `go-mknoon/node/node.go::RefreshRelaySession`, `ReconnectRelays`, and `Stop`; existing `TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh`; app lifecycle resume tests | The source row was `Open` and the breakdown marked GR-004 `needs_repo_evidence` / `evidence-gated`. Production already separates successful in-place refresh from the `Stop()` fallback that clears `groupTopics`/`groupSubs`, but the existing test only inspected state without actually calling `RefreshRelaySession` or proving post-refresh delivery. | Add exact row-owned Go proof that calls successful `RefreshRelaySession`, proves the host/topic/subscription/config/key are preserved, and proves a message delivers to an already-joined peer without rejoin. Run adjacent relay/app recovery selectors and close as tests-only if no production gap appears. |

## Scope

GR-004 owns the successful in-place relay recovery path where the libp2p host is reused and already-joined private group PubSub state must remain active.

Out of scope: watchdog/full restart fallback behavior, app rejoin gating after restart, relay outage inbox repair, relay observability, and recovery-budget metrics. Those are owned by later GR rows.

## Execution Contract

1. Add a row-named Go node regression that starts two local nodes, joins both to the same private group, and records the sender host, group topic, subscription, config, and key.
2. Drive `RefreshRelaySession` through a successful in-place recovery hook and assert it returns `RecoveryMode == in_place`, `ReusedHost == true`, and does not replace the host or joined group runtime objects.
3. Publish a message after recovery without calling `JoinGroupTopic` again and assert the already-joined receiver emits the decrypted `group_message:received` event.
4. Run focused GR-004, adjacent relay-recovery, race, app lifecycle, fake-network resume, gofmt, and `git diff --check` gates.
5. Update the source matrix, breakdown ledgers, and this plan with concrete evidence before acceptance.

## Required Gates

| Gate | Command |
|---|---|
| Focused Go proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR004'` from `go-mknoon` |
| Adjacent relay recovery proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR004|RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession'` from `go-mknoon` |
| Adjacent publish/group proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR004|GroupRecovery|PublishGroupMessage'` from `go-mknoon` |
| Race selector | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test -race ./node -run 'TestGR004|RefreshRelaySession|GroupRecovery'` from `go-mknoon` |
| App lifecycle selectors | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'in-place recovery without Go signal rejoins but does not ack'`; `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'rejoins and acknowledges when Go signals group recovery'`; `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, retryFailed, then retryFailedGroupInboxStores'` |
| Fake-network resume selectors | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'group discovery remains live across ttl refresh window without manual rejoin'`; `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and receives subsequent live messages'` |
| Hygiene | `gofmt -w go-mknoon/node/pubsub_test.go`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree already contained many prior rollout code, test, source-matrix, and session-breakdown edits. GR-004 scope is limited to `go-mknoon/node/pubsub_test.go`, this plan, the source matrix row GR-004, and breakdown closure documentation unless focused gates expose a production defect.

## Execution Evidence

- Added `go-mknoon/node/pubsub_test.go::TestGR004InPlaceRelayRecoveryPreservesGroupTopicsAndDeliveryWithoutRejoin`.
- No production code changed for GR-004. Existing production already routes successful `RefreshRelaySession` through in-place host reuse, while `ReconnectRelays` calls `Stop()` only after in-place failure; `Stop()` is the path that clears joined group topics and subscriptions.
- The row-owned test starts two local libp2p nodes, joins both to one private group, records the sender host/topic/subscription/config/key, forces successful in-place `RefreshRelaySession`, proves all recorded runtime objects are preserved, then publishes `gr004-post-refresh-message` without rejoin and verifies the receiver emits the decrypted `group_message:received` event.

## Verification

- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR004'` passed (`ok node 1.053s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR004|RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession'` passed (`ok node 22.000s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR004|GroupRecovery|PublishGroupMessage'` passed (`ok node 2.029s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test -race ./node -run 'TestGR004|RefreshRelaySession|GroupRecovery'` passed (`ok node 23.162s`).
- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'in-place recovery without Go signal rejoins but does not ack'` passed (`+1`).
- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'rejoins and acknowledges when Go signals group recovery'` passed (`+1`).
- `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, retryFailed, then retryFailedGroupInboxStores'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'group discovery remains live across ttl refresh window without manual rejoin'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and receives subsequent live messages'` passed (`+1`).
- `gofmt -l go-mknoon/node/pubsub_test.go` passed with no output.
- `git diff --check` passed.

## Final Verdict

Accepted/closed. GR-004 is `Covered` by row-owned Go node evidence proving successful in-place relay recovery reuses the host, preserves the existing group topic/subscription/config/key objects, and supports post-refresh message delivery to an already-joined peer without rejoin. Residual-only: none for GR-004. GR-005 is the next unresolved P0 row in session order; no final program verdict was written.
