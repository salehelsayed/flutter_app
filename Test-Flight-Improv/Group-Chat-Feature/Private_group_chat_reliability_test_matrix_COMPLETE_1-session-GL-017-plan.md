# GL-017 Execution Plan - Stop Clears Group Runtime State

Status: execution-ready

## Execution Progress

| Timestamp | Role | Files inspected or touched | Decision / evidence | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 07:32:10 CEST | Execution QA Orchestrator | `implementation-execution-qa-orchestrator` skill; this GL-017 plan; `git status --short`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/node.go`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_delivery_test.go`; `go-mknoon/node/node_test.go` | Contract extracted. Child-agent spawn tool is unavailable in this session, so execution will use a local sequential Executor then QA pass. Scope remains tests-only unless the focused regression proves a row-owned production gap. Worktree already dirty in relevant files; preserve unrelated/user-owned changes. | Add the row-owned GL-017 regression in `go-mknoon/node/pubsub_test.go`. |
| 2026-05-10 07:34:06 CEST | Local Executor | `go-mknoon/node/pubsub_test.go` | Added `TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart` and ran `gofmt` on the touched Go test file. Production code not changed. | Run the focused GL-017 Go test. |
| 2026-05-10 07:34:32 CEST | Local Executor | `go-mknoon/node/pubsub_test.go` | PASS: `(cd go-mknoon && go test ./node -run '^TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart$' -count=1 -v)`. Current production behavior satisfies the focused row contract; no production fallback taken. | Run the required focused race check. |
| 2026-05-10 07:34:55 CEST | Local Executor | `go-mknoon/node/pubsub_test.go` | PASS: `(cd go-mknoon && go test -race ./node -run '^TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart$' -count=1 -v)`. | Run adjacent Go lifecycle and pubsub sweep. |
| 2026-05-10 07:35:25 CEST | Local Executor | `go-mknoon/node/pubsub_test.go`; existing node tests | PASS: `(cd go-mknoon && go test ./node -run 'TestStopNode_CancelsAllDiscoveryContexts|TestRefreshRelaySession_PreservesPubSubMaps|TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh|TestJoinGroupTopic_SuccessStoresAtomicStateAndSupportsImmediateKeyInfoAndPublish|TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup' -count=1 -v)`. | Run the broader row Go sweep. |
| 2026-05-10 07:36:17 CEST | Local Executor | `go-mknoon/node/pubsub_test.go`; existing node tests | PASS: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|StopNode|GroupRecovery|RefreshRelaySession|WatchdogRestart|PublishGroupMessage_ReturnsErrorForUnjoinedGroup' -count=1 -v)`. | Run Flutter startup rejoin smoke. |
| 2026-05-10 07:36:44 CEST | Local Executor | `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | PASS: `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'rejoin topics then receive live messages after simulated restart'`. | Run `git diff --check`. |
| 2026-05-10 07:37:03 CEST | Local Executor | worktree diff | PASS: `git diff --check`. Required commands complete. Production behavior did not change, so conditional Go package, bridge, and group gate commands were not required. | Run local QA review for scope, evidence, and diff sufficiency. |
| 2026-05-10 07:37:58 CEST | Local QA Reviewer | `go-mknoon/node/pubsub_test.go`; this GL-017 plan; required command results; `git status --short`; scoped diffs | QA verdict: accepted. Regression is row-named and proves multi-group runtime state before `Stop()`, full cleanup including dispatcher/pubsub/config/key state, idempotent `Stop()`, restart with empty fresh pubsub maps, publish-before-rejoin failure, explicit rejoin state rebuild, and publish success. Scope stayed GL-017-owned; no production code changed by this execution; no required evidence missing. | GL-017 execution complete; final chat response can report accepted. |

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision / blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 07:28:35 CEST | Planner completed | `go-mknoon/node/node.go`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_delivery_test.go`; `go-mknoon/node/node_test.go`; `go-mknoon/bridge/bridge_test.go`; `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`; `scripts/run_test_gates.sh` | Drafted tests-only plan. Current disk already clears group runtime state on `Stop()` and recreates pubsub maps during `Start()`, so GL-017 needs direct row proof, not broad app recovery work. | Run Reviewer sufficiency pass. |
| 2026-05-10 07:28:35 CEST | Reviewer started | Draft plan sections | Reviewer focus: classification, missing tests/gates, stale assumptions, overreach into GL-018, and exact closure bar. | Check whether plan is sufficient as-is. |
| 2026-05-10 07:28:35 CEST | Reviewer completed | Draft plan sections; source matrix row GL-017; session breakdown row GL-017 | Sufficient with adjustments applied: add explicit event dispatcher assertion, require publish-before-rejoin failure, make race gate required because the test starts subscription/discovery goroutines, and keep full Group Messaging Gate conditional on production behavior changes. | Run Arbiter classification. |
| 2026-05-10 07:28:35 CEST | Arbiter started | Reviewer findings | No structural blocker identified after adjustments. Remaining nuances are incremental or accepted differences. | Finalize final plan and status. |
| 2026-05-10 07:28:35 CEST | Arbiter completed | Final plan | `Status: execution-ready`. GL-017 is safe to execute as tests-only proof on current disk, with narrow code+tests fallback only if the focused regression fails. | Execute in a later implementation phase; do not close the source row from this planning phase. |

## real scope

GL-017 owns a direct proof that full `Node.Stop()` clears all group runtime state and that a restarted node cannot publish or receive group traffic until Flutter/app explicitly rejoins group topics.

Planned change on current disk is tests-only:

- Add one row-named Go node regression, preferably in `go-mknoon/node/pubsub_test.go`, named `TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart`.
- The regression should start a node with an event callback, join several group topics, inspect topic/subscription/config/key/subscription-context/discovery-context state before `Stop()`, call `Stop()`, inspect cleared runtime state and stopped event dispatcher, restart the same node, prove publish before explicit rejoin fails with `group not joined`, then explicitly rejoin and prove publish succeeds.

Narrow code fallback only if the new regression disproves current evidence:

- If stale group entries survive `Stop()`, patch only `go-mknoon/node/node.go::Stop`.
- If restart leaves pubsub maps unusable for explicit rejoin, patch only `go-mknoon/node/pubsub.go` map initialization or `JoinGroupTopic` defensive initialization.
- If event dispatcher survives `Stop()`, patch only the existing dispatcher stop/reset block in `go-mknoon/node/node.go::Stop`.

Out of scope: broad Flutter recovery implementation, persisted rejoin-all behavior, group offline inbox drain, pending retrier behavior, relay watchdog architecture, source matrix closure, and session-breakdown edits. GL-018 owns persisted app rejoin restoring all groups.

## closure bar

Good enough for GL-017 means the implementation can prove all of the following in direct tests:

- A node with at least three joined groups has populated `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, and `groupDiscoveryCtx` before `Stop()`.
- `Stop()` leaves no group ids in `groupTopics`, `groupSubs`, `groupSubCtx`, or `groupDiscoveryCtx`; sets `groupConfigs`, `groupKeys`, and `pubsub` to `nil`; sets `isStarted` false; and stops/clears `eventDispatcher` when an event callback created one.
- A subsequent `Start()` creates a fresh pubsub instance and fresh empty group maps.
- Publishing to a previously joined group before explicit rejoin fails with `group not joined`, returns empty message id, and returns peer count `0`.
- Explicit `JoinGroupTopic` after restart repopulates state and allows `PublishGroupMessage` to succeed. A zero live-peer count is acceptable for the local-only test; success is the proof that the node is explicitly rejoined.
- Existing startup rejoin smoke still proves the Flutter-side call sequence for fake app restart; no app contract expansion is required in GL-017.

## source of truth

Authoritative sources, in order:

- Current source and tests on disk win over stale matrix or breakdown labels.
- Source row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GL-017`.
- Breakdown row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row `GL-017`.
- Gate source: `scripts/run_test_gates.sh` wins over `Test-Flight-Improv/test-gate-definitions.md` if they disagree.

The current worktree is already dirty in relevant Go and Flutter files. Treat those edits as user-owned; do not revert or normalize unrelated changes during execution.

## session classification

`implementation-ready`

Execution classification: tests-only proof on current disk.

Fallback classification: narrow code+tests only if the focused GL-017 regression fails and shows that `Stop()`, `Start()`, or `JoinGroupTopic` violates the row contract.

Not prerequisite-blocked: the app already has explicit rejoin entry points in `rejoinGroupTopics`, `StartupRouter`, resume handling, and `PendingMessageRetrier`. GL-018 remains responsible for proving persisted app rejoin restores all groups; GL-017 only proves the node clears runtime state and requires explicit rejoin.

## exact problem statement

The P0 gap is not that current code obviously fails; the gap is that there is no direct row-owned regression proving the full Stop/restart lifecycle for group pubsub state.

Current code evidence:

- `go-mknoon/node/node.go::Stop` cancels group discovery contexts, group subscription contexts, subscriptions, and topics; deletes entries; sets `groupConfigs = nil`, `groupKeys = nil`, and `pubsub = nil`; closes the host; marks the node stopped; and stops/clears `eventDispatcher`.
- `go-mknoon/node/pubsub.go::initPubSub` recreates `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, and `groupDiscoveryCtx` during `Start()`.
- `go-mknoon/node/pubsub.go::PublishGroupMessage` fails with `group not joined` when topic/config/key state is absent.
- Current disk does not contain an `ensureGroupPubSubMapsLocked` helper; explicit rejoin after restart is safe because `Start()` calls `initPubSub`.

User-visible risk if unproved or regressed: after a watchdog/full restart, the app could believe stale group topic state remains active, causing publishes or receives to rely on dead subscriptions instead of explicitly rejoining.

Must stay unchanged: in-place relay recovery should preserve group pubsub maps; full `Stop()` should clear them.

## files and repos to inspect next

Production files:

- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/relay_session.go`
- `go-mknoon/bridge/bridge.go` only if bridge lifecycle behavior changes
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/main.dart`

Test and gate files:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/node_test.go`
- `go-mknoon/bridge/bridge_test.go` only if bridge code changes
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

- `TestStopNode_CancelsAllDiscoveryContexts` joins several groups and proves `Stop()` clears `groupDiscoveryCtx`, but it does not inspect topics, subscriptions, configs, keys, subscription contexts, event dispatcher, restart, or publish-before-rejoin behavior.
- `TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish` proves leave-topic cleanup and publish blocking for one explicit leave path, not full node stop/restart.
- `TestJoinGroupTopic_SuccessStoresAtomicStateAndSupportsImmediateKeyInfoAndPublish` proves join stores topic/sub/config/key/context state and immediate publish works.
- `TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup` proves generic unjoined publish failure.
- `TestRefreshRelaySession_PreservesPubSubMaps` and `TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh` intentionally prove the opposite path: in-place relay recovery preserves pubsub maps.
- Bridge tests cover `StopNode` success/full lifecycle and idempotent `GroupJoinTopic`, but not group runtime clearing across stop/restart.
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` proves fake Flutter startup rejoin sends the group join command and restores fake-network receive behavior after simulated restart.

Missing: a row-named GL-017 full node lifecycle regression that combines several joined groups, all runtime maps, event dispatcher stop, restart, explicit rejoin requirement, and publish restoration.

## regression/tests to add first

Add `TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart` in `go-mknoon/node/pubsub_test.go`.

Required test shape:

1. Generate a stable node private key with existing `generateTestKey(t)`.
2. Create `n := New(&testEventCollector{})` so `Start()` creates an `eventDispatcher`.
3. Start with local-only `NodeConfig{PrivateKeyHex: hexKey, RelayAddresses: []string{}, AutoRegister: false}`.
4. Generate sender signing keys and a valid group key with existing helpers.
5. Build a group config whose admin/member peer id is `n.PeerId()` and public key is the generated sender public key.
6. Join at least three group ids, such as `gl017-stop-a`, `gl017-stop-b`, and `gl017-stop-c`.
7. Under `n.mu.RLock()`, assert `pubsub` and `eventDispatcher` are nonnil, and every group id has nonnil entries in `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, and `groupDiscoveryCtx`.
8. Call `n.Stop()` and assert no error.
9. Under lock, assert `isStarted == false`, `pubsub == nil`, `groupConfigs == nil`, `groupKeys == nil`, `eventDispatcher == nil`, and the topic/subscription/context maps contain none of the joined group ids and have length `0`.
10. Restart with the same `hexKey` and local-only config. The peer id should remain stable.
11. Under lock, assert fresh `pubsub`, `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, `groupDiscoveryCtx`, and `eventDispatcher` are nonnil and group maps are empty.
12. Call `PublishGroupMessage` for a previously joined group before rejoin using valid sender credentials and `n.PeerId()`. Assert error contains `group not joined`, message id is empty, and peer count is `0`.
13. Explicitly call `JoinGroupTopic` for the previous groups.
14. Call `PublishGroupMessage` again for at least one rejoined group. Assert no error and nonempty message id. Peer count may be `0` because this is local-only.

The first implementation step is to add this test and run it before touching production code. If it passes, GL-017 remains tests-only.

## step-by-step implementation plan

1. Re-check `git status --short` and do not revert unrelated dirty files.
2. Add the GL-017 test in `go-mknoon/node/pubsub_test.go` using existing helpers and same-package access to `Node` internals.
3. Run the focused GL-017 Go test.
4. If the focused test passes, make no production Go or Dart changes.
5. If it fails because stale group runtime entries survive `Stop()`, patch only `go-mknoon/node/node.go::Stop` so every group runtime container is cleared without changing in-place recovery.
6. If it fails because restart cannot explicitly rejoin due nil group maps, patch only the smallest pubsub map initialization point in `go-mknoon/node/pubsub.go`. Prefer proving `Start()` calls `initPubSub`; add `JoinGroupTopic` defensive map initialization only if the failure demonstrates a real reachable nil-map path while `pubsub` is nonnil.
7. If it fails because publish before explicit rejoin succeeds, treat that as stale state retention and patch `Stop()` cleanup only.
8. If it fails because `eventDispatcher` survives `Stop()`, patch only the dispatcher stop/reset block in `Stop()`.
9. Run the direct and adjacent Go gates, the required race check, the Flutter startup rejoin smoke, and `git diff --check`.
10. Run `./scripts/run_test_gates.sh groups` and broader Go node package tests only if production behavior changed.
11. Do not edit the source matrix, session breakdown, or close GL-017 in this execution session unless a later closure-specific instruction asks for it.

## risks and edge cases

- Same peer id after restart depends on reusing the same private key. The test must restart with the same `hexKey`.
- The test starts subscription and discovery goroutines. Assert map cleanup and cancellation entries, not goroutine counts.
- `Stop()` differs intentionally from in-place relay recovery. Do not make `RefreshRelaySession` clear group pubsub maps.
- `PublishGroupMessage` requires a config whose sender peer id is authorized and a valid signing key. Use `n.PeerId()` and the matching generated public key in the test config.
- Event dispatcher assertions require `New(&testEventCollector{})`; `NewNode()` alone will not create an event dispatcher.
- Current dirty worktree may already contain unrelated source/test edits. Failures outside the focused GL-017 path need baseline classification before attributing them to this session.

## exact tests and gates to run

Focused GL-017 regression:

```bash
(cd go-mknoon && go test ./node -run '^TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart$' -count=1 -v)
```

Required race check, because the regression starts real group subscription and discovery goroutines:

```bash
(cd go-mknoon && go test -race ./node -run '^TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart$' -count=1 -v)
```

Adjacent Go lifecycle and pubsub sweep:

```bash
(cd go-mknoon && go test ./node -run 'TestStopNode_CancelsAllDiscoveryContexts|TestRefreshRelaySession_PreservesPubSubMaps|TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh|TestJoinGroupTopic_SuccessStoresAtomicStateAndSupportsImmediateKeyInfoAndPublish|TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup' -count=1 -v)
```

Row Go sweep:

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|StopNode|GroupRecovery|RefreshRelaySession|WatchdogRestart|PublishGroupMessage_ReturnsErrorForUnjoinedGroup' -count=1 -v)
```

Flutter startup rejoin smoke:

```bash
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'rejoin topics then receive live messages after simulated restart'
```

Diff hygiene:

```bash
git diff --check
```

Only if production Go, bridge, or Dart behavior changes:

```bash
(cd go-mknoon && go test ./node -count=1)
```

```bash
(cd go-mknoon && go test ./bridge -run 'TestStopNode_Success|TestStartNode_StopNode_FullCycle|TestGroupJoinTopic_AlreadyJoinedIsIdempotent' -count=1 -v)
```

```bash
./scripts/run_test_gates.sh groups
```

## known-failure interpretation

- The focused GL-017 test should fail before code changes only if current behavior is actually missing the row contract. That failure is actionable for this session.
- Existing unrelated failures from the dirty worktree are not GL-017 regressions unless the new test or narrow GL-017 code change causes them.
- If the Flutter startup rejoin smoke fails outside the rejoin command or fake-network receive path, record the failure as an existing app-side blocker unless GL-017 touched Flutter code.
- Race detector failures in the focused GL-017 lifecycle are actionable because the row explicitly covers subscription/discovery loop cleanup.
- Do not mark GL-017 covered from partial evidence. The row requires the combined Stop, inspect, restart, publish-before-rejoin, and explicit-rejoin proof.

## done criteria

- `TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart` exists and passes.
- The test proves several joined groups, all relevant runtime maps, event dispatcher stop, restart with fresh empty pubsub maps, publish-before-rejoin failure, and explicit rejoin restoring publish.
- Required focused, race, adjacent Go, row Go sweep, Flutter startup rejoin smoke, and `git diff --check` pass or have clearly documented unrelated pre-existing failures.
- No broad app recovery implementation is added.
- No source matrix, session breakdown, or row closure edits are made as part of this planning artifact.

## scope guard

Do not implement GL-018 persisted app rejoin behavior in GL-017.

Do not change `rejoinGroupTopics`, `StartupRouter`, resume handling, pending retrier behavior, group offline inbox drain, group key repair, invite handling, membership logic, or notification routing unless the focused GL-017 test proves a direct dependency and the change is the smallest possible fix.

Do not change in-place relay recovery semantics to match full `Stop()`. In-place recovery intentionally preserves pubsub state.

Do not require group maps themselves to be nil after `Stop()` unless current code already does so for a specific map. Empty maps with no group runtime entries satisfy the row for `groupTopics`, `groupSubs`, `groupSubCtx`, and `groupDiscoveryCtx`; `groupConfigs`, `groupKeys`, and `pubsub` are currently nilled and should be asserted that way.

Do not add real-network simulator orchestration for this row. The node lifecycle test plus existing Flutter fake startup rejoin smoke are the right closure level unless production behavior changes expose a broader gap.

## accepted differences / intentionally out of scope

- Full `Stop()` clears group runtime state; `RefreshRelaySession` and in-place recovery preserve it. This is an intentional architecture difference, not a parity gap.
- Flutter startup/resume has existing explicit rejoin paths, but GL-017 does not need to prove every persisted group is restored after app restart. GL-018 owns that broader app contract.
- The Flutter startup rejoin smoke uses fake infrastructure and does not prove real libp2p mesh delivery. GL-017's Go node regression proves the libp2p runtime state contract directly.
- The new test may assert map emptiness rather than nilness for topic/subscription/context maps. The row asks for no retained runtime state, not a specific container representation.

## dependency impact

- GL-018 depends on GL-017's proof that a full node restart has no retained group runtime subscriptions and therefore requires app-driven rejoin.
- Watchdog restart and `needsGroupRecovery` flows depend on this distinction: node restart clears runtime topics, while app recovery is responsible for rejoin and later acknowledgement.
- If GL-017 execution discovers that restart rejoin fails, GL-018 should not proceed until the narrow node/pubsub fix lands and the GL-017 gates pass.

## Reviewer

Verdict: sufficient with adjustments applied.

Reviewer checks:

- Missing files/tests/gates: added event dispatcher coverage, focused race gate, direct Flutter startup rejoin smoke, row Go sweep, and conditional named Group Messaging Gate.
- Stale assumptions: corrected the known-evidence note about `ensureGroupPubSubMapsLocked`; current disk has no such helper, and restart safety comes from `Start()` calling `initPubSub`.
- Overengineering: broad app recovery and GL-018 persisted rejoin behavior are explicitly out of scope.
- Decomposition: one row-named Go regression first; production code changes happen only if that test fails.
- Minimum sufficient plan: add the direct lifecycle test and run the exact gates above.

## Arbiter

Structural blockers: none.

Incremental details intentionally deferred:

- Bridge-level StopNode group-state proof is not required unless bridge code changes.
- Full `./scripts/run_test_gates.sh groups` is conditional on production behavior changes because tests-only Go proof should not require a broad Flutter named gate.

Accepted differences:

- Stop clears; in-place recovery preserves.
- GL-017 proves the node contract; GL-018 proves persisted app rejoin restoration.

Final arbiter decision: execution-ready.
