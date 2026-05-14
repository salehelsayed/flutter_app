# GO-010 Session Plan: Goroutine Leak Check After Join/Leave/Recovery Cycles

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GO-010`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 09:08 CEST | Controller | Source matrix GO-010 row; breakdown session ledger row 229; existing leave/stop/discovery cleanup tests; GR-019 recovery-slot cancellation proof; `go-mknoon/node/pubsub.go` subscription/discovery lifecycle code; app send/drain owner gates | The source row was still `Open` while the breakdown classified the row as `needs_code_and_tests`/`implementation-ready`. Existing code cancels group subscription and discovery contexts on leave/stop and defers recovery slot release, but no row-owned GO-010 test asserted that subscription, discovery, and recovery goroutines return to baseline after repeated join/leave/recovery cycles. | Keep GO-010 as code-plus-tests, add exact native leak-check test code using goroutine stack snapshots, and run exact, adjacent, selected race, app-facing, and diff hygiene gates before closing the row. |

## Scope

GO-010 owns a deterministic native leak check for the group PubSub lifecycle. The row closes when repeated group join/leave plus recovery cycles prove that the group subscription handler, group discovery loop, discovery/recovery cycle, and discover/connect goroutines exit back to baseline and leave no held recovery slots.

Out of scope: app-level persisted startup rejoin (`GL-018`), discovery missing-peer observability (`GO-006`), host versus topic-peer metrics (`GO-007`), and broader process-wide libp2p goroutine counts unrelated to group lifecycle ownership.

## Execution Contract

1. Add an exact Go test named `TestGO010JoinLeaveRecoveryCyclesDoNotLeakGroupGoroutines`.
2. Capture a baseline goroutine profile for group runtime stack frames.
3. Repeat group join, explicit recovery cycle, pre-leave publish sanity, and leave cleanup across multiple groups.
4. After each leave, assert group topic/subscription/config/key/context state is removed.
5. After each leave, poll goroutine stacks until group runtime goroutines are back at or below baseline.
6. After each recovery cycle, assert no `groupRecoverySem` slot remains held.
7. After final `Stop`, assert group runtime goroutines remain at or below baseline.
8. Run selected native race and app-facing send/drain gates.
9. Update the source matrix, breakdown ledger, and test inventory with concrete file/test/gate evidence.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` |
| Focused GO-010 proof | `(cd go-mknoon && go test ./node -run '^TestGO010JoinLeaveRecoveryCyclesDoNotLeakGroupGoroutines$' -count=1)` |
| Adjacent lifecycle/recovery proof | `(cd go-mknoon && go test ./node -run 'TestGO010|TestGP010DiscoveryLoopUnregistersOnceAndStopsAfterLeave|TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart|TestGR019GroupRecoveryLimiterReleasesSlotsOnCanceledContext' -count=1)` |
| Native race gate | `(cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1)` |
| App-facing send/drain gate | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before closure: worktree remained dirty with prior gap-closure rollout changes and accepted session artifacts. GO-010 scope is limited to `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`, this adjacent plan, source/breakdown closure updates, and test inventory entries.

## Execution Evidence

Implemented exact row coverage in `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`.

Production behavior inspected:

- `go-mknoon/node/pubsub.go::JoinGroupTopic` starts cancellable `handleGroupSubscription` and `groupPeerDiscoveryLoop` goroutines.
- `go-mknoon/node/pubsub.go::LeaveGroupTopic` cancels discovery and subscription contexts, cancels the subscription, closes the topic, unregisters the validator, and removes config/key state.
- `go-mknoon/node/node.go::Stop` cancels all group discovery/subscription contexts, cancels subscriptions, closes topics, clears group runtime maps, and resets the group recovery semaphore.
- `go-mknoon/node/pubsub.go::runGroupDiscoveryCycle` acquires a group recovery slot with the caller context and defers slot release.

Exact test:

- `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go::TestGO010JoinLeaveRecoveryCyclesDoNotLeakGroupGoroutines` captures a baseline goroutine profile for stack blocks containing `handleGroupSubscription`, `groupPeerDiscoveryLoop`, `runGroupDiscoveryCycle`, or `discoverAndConnectGroupPeers`. It then runs four cycles of `JoinGroupTopic`, `runGroupDiscoveryCycle`, pre-leave `PublishGroupMessage`, and `LeaveGroupTopic`, proves group runtime state is removed after every leave, polls goroutine stacks back to baseline after every cycle, asserts `groupRecoverySem` has no held slots, verifies all four register/discover recovery cycles ran, calls `Stop`, and polls group runtime goroutines back to baseline again.

Supporting test helpers:

- `go010GroupRuntimeGoroutineSnapshot` uses `runtime/pprof` goroutine stack snapshots and filters only repo-owned group runtime stack frames, avoiding process-wide libp2p background goroutine noise.
- `waitForGO010GroupRuntimeGoroutinesAtMost` polls the filtered stack count with a bounded timeout and prints matching stacks on failure.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` | Passed. |
| `(cd go-mknoon && go test ./node -run '^TestGO010JoinLeaveRecoveryCyclesDoNotLeakGroupGoroutines$' -count=1)` | Passed: `ok github.com/mknoon/go-mknoon/node 0.578s`. |
| `(cd go-mknoon && go test ./node -run 'TestGO010|TestGP010DiscoveryLoopUnregistersOnceAndStopsAfterLeave|TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart|TestGR019GroupRecoveryLimiterReleasesSlotsOnCanceledContext' -count=1)` | Passed: `ok github.com/mknoon/go-mknoon/node 10.316s`. |
| `(cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1)` | Passed: `ok github.com/mknoon/go-mknoon/node 96.500s`. |
| `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed: `+168 All tests passed!`. |
| `git diff --check` | Passed after final closure documentation updates. |

## Final Verdict

Accepted/closed. GO-010 is covered by exact native group goroutine leak proof, adjacent leave/stop/discovery/recovery proof, selected native race proof, app-facing send/drain gates, and diff hygiene after final closure documentation updates. Residual-only none for GO-010. All row-owned source rows in this breakdown are now covered, and the breakdown final program verdict is `closed`.
