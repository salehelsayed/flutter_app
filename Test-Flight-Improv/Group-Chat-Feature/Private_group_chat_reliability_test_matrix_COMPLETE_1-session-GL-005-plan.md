# GL-005 Plan: Atomic Group Join State

Status: execution-ready

Source matrix: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
Session breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Source row: GL-005

## Planning Progress

- `2026-05-10T01:24:08Z` - Planner completed. Files inspected since last update: draft plan content and evidence notes. Decision/blocker: draft is tests-only with conditional code fallback if the direct regression disproves current code; no blocker. Next action: Reviewer checks sufficiency, missing gates/files, stale assumptions, and overengineering.
- `2026-05-10T01:24:08Z` - Reviewer started. Files inspected since last update: draft plan content. Decision/blocker: no blocker yet. Next action: run sufficiency review against mandatory sections and GL-005 row contract.
- `2026-05-10T01:24:40Z` - Reviewer completed. Files inspected since last update: full draft plan, mandatory section inventory, GL-005 source row, current `JoinGroupTopic`/`GetGroupKeyInfo`/`PublishGroupMessage` evidence, adjacent GL-001..GL-004 tests, and gate policy excerpts. Decision/blocker: sufficient as-is; no structural blocker. Next action: Arbiter classifies reviewer findings and finalizes the plan.
- `2026-05-10T01:24:40Z` - Arbiter started. Files inspected since last update: reviewer sufficiency notes. Decision/blocker: no blocker yet. Next action: classify structural blockers, incremental details, and accepted differences.
- `2026-05-10T01:25:16Z` - Arbiter completed. Files inspected since last update: reviewer sufficiency notes and final plan sections. Decision/blocker: no structural blockers; GL-005 is execution-ready as tests-only with mandatory stop/reclassification if the direct regression fails for a product reason. Next action: hand off for execution in a later session.

## real scope

Own exactly source row `GL-005`: after a successful `JoinGroupTopic(G, config, keyInfo)` with valid inputs, the local join state must be observable as all present, not partially present. The row-owned proof must include:

- `groupTopics[groupId]`
- `groupSubs[groupId]`
- `groupConfigs[groupId]`
- `groupKeys[groupId]`
- `groupSubCtx[groupId]`
- `groupDiscoveryCtx[groupId]`
- immediate `GetGroupKeyInfo(groupId)`
- immediate `PublishGroupMessage(groupId, ...)`

This session is tests-only based on current evidence. The expected edit is a single Go regression in `go-mknoon/node/pubsub_test.go`. `go-mknoon/node/pubsub_delivery_test.go` is not expected to be needed because `PublishGroupMessage` already supports a single joined node with zero topic peers. `go-mknoon/node/pubsub.go` and `go-mknoon/node/node.go` are inspection-only unless the new regression unexpectedly fails against current code.

Do not edit the source matrix or session breakdown in this session. Do not change Dart/Flutter group rejoin behavior, bridge semantics, libp2p retry policy, duplicate-join semantics, validator behavior, or key-rotation behavior.

## closure bar

GL-005 is good enough when a row-owned Go regression proves that a successful join with valid config/key:

- returns no `JoinGroupTopic` error,
- stores all six local state entries listed in the source row,
- stores a joined key snapshot matching the supplied key and epoch,
- allows `GetGroupKeyInfo` immediately after join to return the same key/epoch,
- allows `PublishGroupMessage` immediately after join to return a non-empty message id without `group not joined`,
- passes the direct regression, the row Go gate, and the required Flutter startup-rejoin host smoke.

The closure bar does not require multi-node delivery for this row; GL-005 is about local successful-join atomicity, while adjacent delivery coverage belongs to GL-002 and existing `pubsub_delivery_test.go` publish/delivery suites.

## source of truth

Authoritative sources for this plan:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GL-005`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row `GL-005`
- Current code in `go-mknoon/node/pubsub.go` and `go-mknoon/node/node.go`
- Current adjacent tests in `go-mknoon/node/pubsub_test.go` and `go-mknoon/node/pubsub_delivery_test.go`
- `Test-Flight-Improv/test-gate-definitions.md` for named gate policy
- `scripts/run_test_gates.sh` if a named Flutter gate is run; the script wins over docs if they disagree

Current code and tests win over stale prose. The active session plan wins for execution scope unless direct repo evidence disproves it.

## session classification

`implementation-ready`

Disposition: tests-only. Current code holds `n.mu.Lock()` for the full successful `JoinGroupTopic` path and writes topic, subscription, config, key, subscription cancel, and discovery cancel before returning. `GetGroupKeyInfo` and `PublishGroupMessage` use the same mutex via read locks, so they cannot observe the intermediate writes while the join is still in progress. The uncovered gap is a row-named regression proving the complete successful-join invariant.

## exact problem statement

GL-005 is open because the repository does not have a direct test that combines the source row's success path: join a group, immediately read key info, immediately publish, and inspect the full local map/context state through the Go test seam.

Existing tests prove pieces of the behavior, but not the row contract as one atomic local truth:

- `TestJoinGroupTopic_WithMultiMemberConfig` checks topic, subscription, config, key, and discovery context after join, but does not check `groupSubCtx`, immediate `GetGroupKeyInfo`, or immediate publish.
- `TestGetGroupKeyInfo_ReturnsCurrentKey` checks key retrieval after join and update, but not the complete join state.
- `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` checks publish can succeed for a joined single node, but not complete join state.
- GL-001..GL-004 tests cover nil-PubSub, duplicate join, join failure cleanup, and subscribe failure cleanup, not the successful atomic all-present invariant.

The user-visible behavior protected by GL-005 is that a newly joined group is immediately usable for key lookup and sending, with no local state shape where publish/key lookup sees only part of the join. Existing successful join, duplicate rejection, failure cleanup, key snapshot, and publish semantics must stay unchanged.

## files and repos to inspect next

Primary owner file:

- `go-mknoon/node/pubsub_test.go`

Inspection-only unless evidence changes:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `Test-Flight-Improv/test-gate-definitions.md`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`

Do not edit:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`

## existing tests covering this area

- `go-mknoon/node/pubsub_test.go::TestJoinGroupTopic_FailsWithoutPubSub` covers nil-PubSub rejection and no attempted group state for GL-001.
- `go-mknoon/node/pubsub_test.go::TestJoinGroupTopic_DuplicateJoinPreservesExistingState` covers duplicate join preserving the first topic, subscription, config, key, and handler/discovery entries for GL-002.
- `go-mknoon/node/pubsub_delivery_test.go::TestJoinGroupTopic_DuplicateJoinPreservesDelivery` covers delivery after duplicate-join rejection for GL-002.
- `go-mknoon/node/pubsub_test.go::TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry` covers join-failure cleanup and retry for GL-003.
- `go-mknoon/node/pubsub_test.go::TestJoinGroupTopic_SubscribeFailureUnregistersValidatorClosesTopicAndAllowsRetry` covers subscribe-failure cleanup and retry for GL-004.
- `go-mknoon/node/pubsub_test.go::TestJoinGroupTopic_WithMultiMemberConfig` covers successful join storage, but misses `groupSubCtx`, immediate `GetGroupKeyInfo`, and immediate `PublishGroupMessage`.
- `go-mknoon/node/pubsub_test.go::TestGetGroupKeyInfo_ReturnsCurrentKey` covers key retrieval and update behavior, but not complete join atomicity.
- `go-mknoon/node/pubsub_delivery_test.go::TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` covers publish success with zero peers, but not the GL-005 state invariant.
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` covers Flutter startup rejoin command behavior with fake infrastructure, not Go map atomicity.

## regression/tests to add first

Add this direct regression first in `go-mknoon/node/pubsub_test.go`, near the existing `JoinGroupTopic` tests:

```go
func TestJoinGroupTopic_SuccessStoresAtomicStateAndSupportsImmediateKeyInfoAndPublish(t *testing.T)
```

Test shape:

1. Start a `NewNode()` with `AutoRegister: false`.
2. Generate a valid Ed25519 sender keypair and group key.
3. Build a `GroupConfig` whose member list contains `n.PeerId()` as an admin/writer with the generated public key.
4. Call `JoinGroupTopic` with `groupId := "gl-005-success-atomic-state"` and `keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}`.
5. Under `n.mu.RLock()`, capture all six state entries for `groupId`: topic, subscription, config, key, subscription cancel, and discovery cancel.
6. Fail with one diagnostic if any of the six are missing. Also assert the stored config is the supplied config and the stored key has the supplied key/epoch.
7. Assert the stored key pointer is not the caller's `keyInfo` pointer, matching the existing joined-key snapshot behavior from `joinedGroupKeyInfo`.
8. Call `GetGroupKeyInfo(groupId)` immediately after join and assert it returns a non-nil clone with the supplied key/epoch.
9. Call `PublishGroupMessage` immediately with the generated private/public key and `n.PeerId()` as sender. Assert no error and a non-empty message id. Do not require `topicPeerCount > 0`; zero peers is valid for a single-node local publish path.

If this test passes before product changes, keep the session tests-only. If it fails because current code leaves one of the six state entries absent after a successful join, or because immediate key lookup/publish returns `group not joined` with valid inputs, stop and reclassify before editing production code.

## step-by-step implementation plan

1. Recheck scoped status before editing:

```bash
git status --short
```

2. Inspect the current `JoinGroupTopic` tests around GL-001..GL-004 and preserve all unrelated dirty work in `go-mknoon/node/pubsub_test.go`.
3. Add `TestJoinGroupTopic_SuccessStoresAtomicStateAndSupportsImmediateKeyInfoAndPublish` in `go-mknoon/node/pubsub_test.go`.
4. Run the new direct regression before considering product-code edits:

```bash
(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_SuccessStoresAtomicStateAndSupportsImmediateKeyInfoAndPublish$' -count=1)
```

5. If the direct regression passes, do not edit `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, or `go-mknoon/node/pubsub_delivery_test.go`.
6. If the direct regression fails for a real product reason, stop and update the plan/session classification before widening scope. The likely product owner would be `go-mknoon/node/pubsub.go::JoinGroupTopic`; the likely invariant is to ensure state is either fully stored before return or not stored on error. Do not implement that fallback without reclassification.
7. Run the row Go gate, Flutter host smoke, and diff hygiene command listed below.
8. Record exact command results in the plan progress section during execution. Do not update the source matrix or breakdown in this session.

## risks and edge cases

- A test that uses placeholder group keys can fail in `PublishGroupMessage` encryption. Use `mcrypto.GenerateGroupKey()` for the GL-005 regression.
- `PublishGroupMessage` write authorization depends on the sender being an allowed writer in the stored config. Use `n.PeerId()` with admin or writer role and the generated public key.
- Single-node publish can legitimately report zero topic peers. Do not make peer count part of the GL-005 closure bar.
- `JoinGroupTopic` currently stores the config pointer but snapshots key info through `joinedGroupKeyInfo`. Do not convert config storage to deep-copy behavior in this session.
- `GetGroupKeyInfo` returns a clone, so the regression should compare key/epoch values and may assert it is not the internal stored pointer.
- Existing dirty work includes unrelated docs, Go files, Flutter files, and prior GL plan artifacts. Preserve it; only GL-005 plan/progress and the row-owned test should change during execution.

## exact tests and gates to run

Mandatory direct GL-005 regression:

```bash
(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_SuccessStoresAtomicStateAndSupportsImmediateKeyInfoAndPublish$' -count=1)
```

Mandatory row Go gate:

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)
```

Mandatory Flutter host confirmation from the session breakdown:

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Mandatory diff hygiene:

```bash
git diff --check
```

Conditional named gate only if production group behavior, Dart/Flutter group code, or bridge/rejoin behavior is changed despite the tests-only plan:

```bash
./scripts/run_test_gates.sh groups
```

No simulator/device gate is required for the planned tests-only Go coverage.

## known-failure interpretation

No GL-005 known failure is accepted. The new direct regression failing on current code is either a test construction bug or evidence that GL-005 must be reclassified to code+tests.

Do not treat unrelated dirty-worktree failures as GL-005 regressions unless they reproduce in one of the mandatory commands above and are causally tied to `JoinGroupTopic`, `GetGroupKeyInfo`, or `PublishGroupMessage`.

If the Flutter startup-rejoin smoke fails without any Dart/Flutter edits, record the exact failure and inspect whether it is a pre-existing workspace issue before widening GL-005. If `git diff --check` fails on unrelated pre-existing files, record the paths and do not fix unrelated whitespace in this session.

## done criteria

- `go-mknoon/node/pubsub_test.go` contains the GL-005 row-owned regression named above.
- The test asserts all six successful-join local state entries exist for the joined group.
- The test asserts immediate `GetGroupKeyInfo` returns the joined key/epoch.
- The test asserts immediate `PublishGroupMessage` succeeds and returns a non-empty message id.
- No production code is changed unless the direct regression proves the current tests-only classification wrong and the session is explicitly reclassified.
- All mandatory commands pass, or any failure is recorded with a clear known-failure/product-failure interpretation.
- The source matrix and session breakdown remain untouched.

## scope guard

Non-goals:

- Do not redesign `JoinGroupTopic`, `LeaveGroupTopic`, validators, discovery loops, retry policy, or topic lifecycle.
- Do not change duplicate-join behavior from error to success/no-op.
- Do not change `GroupConfig` storage semantics or introduce a config deep copy.
- Do not change key rotation, grace-period behavior, `UpdateGroupKey`, or `GetGroupKeyInfo` clone semantics.
- Do not add new public APIs, exported test seams, sleeps, goroutine counters, or multi-node delivery requirements.
- Do not edit Flutter app code, bridge helpers, source matrix, session breakdown, or test gate definitions for GL-005.

Overengineering for this session would be adding a generic join-state abstraction, a transaction wrapper, new synchronization primitives, an exported state inspector, or broad refactors outside the row-owned regression.

## accepted differences / intentionally out of scope

- GL-005 accepts that `JoinGroupTopic` performs several map writes sequentially while holding `n.mu.Lock()`; it does not require a new transaction object because readers cannot observe the intermediate state through `GetGroupKeyInfo`, `PublishGroupMessage`, or direct test inspection after return.
- GL-005 accepts that single-node publish can have zero peers. Multi-node delivery is already covered elsewhere and is not the proof target.
- GL-005 accepts that validator registry identity is not directly introspected. Adjacent GL-003/GL-004 own validator cleanup; GL-005 owns local successful-join state and immediate usability.
- GL-005 accepts current config pointer storage. The row's "joined key snapshot" applies to `GroupKeyInfo`, which current code snapshots through `joinedGroupKeyInfo`.

## dependency impact

Closing GL-005 gives later group lifecycle/local-truth sessions a row-owned proof that successful joins produce a complete local state baseline before leave, recovery, update, and publish workflows operate on that group.

If GL-005 is reclassified to code+tests because the direct regression fails for a product reason, downstream sessions that assume complete successful-join state should not close until the join-state invariant is fixed and the GL-005 commands pass.

## reviewer sufficiency review

Review verdict: sufficient as-is.

- Missing files, tests, or gates: none structurally. `go-mknoon/node/pubsub_test.go` is the correct owner for the row-owned local-state regression. `go-mknoon/node/pubsub_delivery_test.go` and production files are correctly conditional. The mandatory direct Go regression, row Go gate, startup-rejoin host smoke, and diff hygiene command are explicit.
- Stale or incorrect assumptions: none found. The tests-only classification matches current `JoinGroupTopic` evidence because the successful path holds `n.mu.Lock()` until all six entries are stored and `GetGroupKeyInfo`/`PublishGroupMessage` use read locks.
- Overengineering: none. The plan explicitly rejects transaction wrappers, exported seams, new synchronization primitives, multi-node delivery, and product refactors.
- Decomposition sufficiency: sufficient. The plan is one row, one primary test file, one direct regression, and conditional stop/reclassification if product behavior disproves the classification.
- Minimum needed to make sufficient: already present. No patch loop is needed before arbiter.

## arbiter decision

Final arbiter verdict: execution-ready.

Structural blockers:

- None.

Incremental details intentionally deferred:

- Exact local variable names and diagnostic wording inside the Go test are left to the executor, provided the test keeps the specified name and assertions.
- `go-mknoon/node/pubsub_delivery_test.go` remains optional and should stay untouched unless the executor finds single-node publish cannot prove immediate publish health.
- `./scripts/run_test_gates.sh groups` remains conditional because the accepted plan is Go tests-only and does not change production group behavior or Flutter/Dart code.

Accepted differences intentionally left unchanged:

- Sequential map writes under `n.mu.Lock()` are accepted as the current atomicity mechanism.
- Current config pointer storage is accepted; GL-005 only requires the joined key snapshot behavior already implemented through `joinedGroupKeyInfo`.
- Multi-node delivery and validator registry introspection remain out of scope because adjacent rows/tests own those behaviors.

Stop rule outcome:

- The reviewer found no structural blocker, so the arbiter stops without a patch loop.

## Execution Progress

- `2026-05-10T01:27:26Z` - Controller extracted contract. Files inspected since last update: GL-005 plan, scoped `git status --short`, scoped diff for `go-mknoon/node/pubsub_test.go` and this plan, `go-mknoon/node/pubsub_test.go` join-topic test area, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, adjacent Go test references, gate definitions, and Flutter startup-rejoin smoke reference. Decision/blocker: execution contract is concrete and tests-only; existing dirty work is present and must be preserved. Next action: spawn Executor for the row-owned regression and required direct test sequence.
- `2026-05-10T01:27:38Z` - Executor spawned. Files inspected or touched since last update: this progress section only. Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh"`. Decision/blocker: no blocker. Next action: wait for Executor result, then run QA Reviewer as a separate child.
- `2026-05-10T01:29:03Z` - Executor started. Files inspected/touched: scoped `git status --short`, scoped diff for `go-mknoon/node/pubsub_test.go`, scoped diff for this plan, plan contract, adjacent `JoinGroupTopic`/`GetGroupKeyInfo` tests, and `go-mknoon/node/pubsub.go`; touched `go-mknoon/node/pubsub_test.go`. Decision/blocker: broad pre-existing dirty work present; GL-005 remains tests-only. Next action: run mandatory direct GL-005 regression.
- `2026-05-10T01:30:33Z` - Executor completed. Files touched: `go-mknoon/node/pubsub_test.go` and this execution-progress section only. Commands: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_SuccessStoresAtomicStateAndSupportsImmediateKeyInfoAndPublish$' -count=1)` passed (`ok github.com/mknoon/go-mknoon/node 0.555s`); `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)` passed (`ok github.com/mknoon/go-mknoon/node 4.299s`); `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` passed (`+3: All tests passed!`); `git diff --check` passed. Decision/blocker: no product-code failure; production untouched by GL-005 executor. Next action: QA Reviewer should inspect the added regression and confirm scope/test evidence.
- `2026-05-10T01:32:12Z` - QA Reviewer spawned. Files inspected or touched since last update: this progress section only. Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh"`. Decision/blocker: no blocker. Next action: wait for QA sufficiency result.
- `2026-05-10T01:33:51Z` - QA Reviewer completed. Files inspected since last update: GL-005 plan contract and execution progress, scoped diff for `go-mknoon/node/pubsub_test.go`, exact GL-005 regression body, and changed-file list. Commands verified from Executor record: mandatory direct GL-005 regression passed, row Go gate passed, Flutter startup-rejoin smoke passed, and `git diff --check` passed. Decision/blocker: no blocking issues and no non-blocking follow-ups; `./scripts/run_test_gates.sh groups` is not required because GL-005 landed as tests-only coverage with no row-owned production, Dart/Flutter, bridge, or rejoin behavior change. Next action: accept GL-005.
- `2026-05-10T01:34:43Z` - Final verdict written. Files touched since last update: this execution-progress section only. Decision/blocker: accepted; no blocking issues remain and no follow-ups are deferred. Next action: none for GL-005.
