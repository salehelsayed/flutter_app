Status: execution-ready

# GL-004 Plan - Subscribe Failure Cleanup After Topic Join

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 02:59:13 CEST | Evidence Collector completed | `go-mknoon/node/pubsub.go`; `go-mknoon/node/node.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/third_party/go-libp2p-pubsub/topic.go`; `go-mknoon/third_party/go-libp2p-pubsub/validation.go`; `Test-Flight-Improv/test-gate-definitions.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`; `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` | Current code closes the topic on `topic.Subscribe()` failure but does not unregister the validator; GL-004 must be reclassified from tests-only to code+tests. | Draft the narrow execution contract. |
| 2026-05-10 02:59:13 CEST | Planner started | Evidence set above. | Plan will keep GL-004 host-only and Go-owned unless new evidence appears. | Write scope, regression contract, gates, and execution instructions. |
| 2026-05-10 02:59:13 CEST | Planner completed | Same evidence set; no new files inspected. | Draft reclassifies row to code+tests with a narrow subscribe-failure regression. | Run reviewer sufficiency pass. |
| 2026-05-10 03:02:26 CEST | Reviewer completed | Full draft plan. | Sufficient with one adjustment: make owner files explicit. No stale assumption or overengineering found. | Apply owner-file clarification and run arbiter pass. |
| 2026-05-10 03:02:55 CEST | Arbiter completed | Reviewer-adjusted plan. | No structural blockers remain. Reclassification to code+tests is accepted because current code leaves a validator leak on subscribe failure. | Execute with `$implementation-execution-qa-orchestrator`. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Command | Decision/blocker | Next action |
| --- | --- | --- | --- | --- | --- |
| 2026-05-10 03:06:04 CEST | Controller contract extracted | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-004-plan.md`; scoped dirty diff for `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go` | `git status --short`; `git diff -- go-mknoon/node/pubsub.go go-mknoon/node/node.go go-mknoon/node/pubsub_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-004-plan.md` | GL-004 scope is code+tests; preserve prior dirty GL-001/002/003 edits; run strict Executor then QA via spawned `codex exec` child agents. | Spawn Executor for RED test, minimal cleanup fix, required GREEN commands, and progress recording. |
| 2026-05-10 03:08:59 CEST | Executor RED captured | `go-mknoon/node/node.go`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go` | `(cd go-mknoon && go test ./node -run TestJoinGroupTopic_SubscribeFailureUnregistersValidatorClosesTopicAndAllowsRetry -count=1)` -> failed | Added private nil-default subscribe hook and GL-004 regression only. Expected RED reproduced: retry failed with `register topic validator: duplicate validator for topic /mknoon/group/gl-004-subscribe-failure-retry` after first subscribe failure. | Add minimal subscribe-error cleanup in `JoinGroupTopic`: close topic and unregister validator before returning wrapped subscribe error. |
| 2026-05-10 03:10:17 CEST | Executor GREEN complete | `go-mknoon/node/pubsub.go`; `go-mknoon/node/node.go`; `go-mknoon/node/pubsub_test.go`; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-004-plan.md` | `(cd go-mknoon && go test ./node -run TestJoinGroupTopic_SubscribeFailureUnregistersValidatorClosesTopicAndAllowsRetry -count=1)` -> passed (`ok github.com/mknoon/go-mknoon/node 0.525s`)<br>`(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)` -> passed (`ok github.com/mknoon/go-mknoon/node 4.326s`)<br>`flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` -> passed (`00:00 +3: All tests passed!`)<br>`./scripts/run_test_gates.sh groups` -> passed (`00:10 +103: All tests passed!`)<br>`git diff --check` -> passed | Implemented minimal subscribe-error cleanup: `_ = topic.Close()` followed by `_ = n.pubsub.UnregisterTopicValidator(topicName)` before returning the wrapped subscribe error. Retry now reaches the second subscribe attempt, succeeds, and publish-after-retry returns a message id. No untriaged failures. | Executor handoff to QA Reviewer. |
| 2026-05-10 03:13:13 CEST | QA Reviewer complete | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-004-plan.md`; `/tmp/gl004-executor-final.md`; `go-mknoon/node/node.go`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; scoped diff/status | `go test ./node -run TestJoinGroupTopic_SubscribeFailureUnregistersValidatorClosesTopicAndAllowsRetry -count=1` from `go-mknoon` -> passed (`ok github.com/mknoon/go-mknoon/node 0.680s`)<br>`git diff --check` -> passed | Accepted: GL-004 hook is private nil-default, normal subscribe still delegates to `topic.Subscribe()`, subscribe failure closes topic and unregisters validator before the wrapped error, successful state storage remains post-subscribe, required RED/GREEN evidence is present, and unrelated dirty files are pre-existing scope context. | Return accepted QA verdict. |
| 2026-05-10 03:14:07 CEST | Controller final verdict written | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-004-plan.md`; QA handoff | Final controller `git diff --check` -> passed | Final verdict `accepted`; no blocking issues and no non-blocking GL-004 follow-ups remain. | Return final execution verdict. |

## real scope

Own exactly source row `GL-004`: `JoinGroupTopic` when `pubsub.Join(topicName)` succeeds but `topic.Subscribe()` fails.

This session may change:

- `go-mknoon/node/pubsub.go`: the `topic.Subscribe()` error branch in `JoinGroupTopic`.
- `go-mknoon/node/node.go`: only if a private, unexported test seam is needed to inject a deterministic subscribe failure.
- `go-mknoon/node/pubsub_test.go`: the row-owned GL-004 regression.
- This plan file's `## Execution Progress` section during execution.

This session must not change Dart production code, bridge APIs, relay/discovery algorithms, encryption/key semantics, group membership semantics, the source matrix, the breakdown artifact, or unrelated GL rows.

## owner files

Write-owned for execution:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`, only for the private subscribe-failure test seam if needed
- `go-mknoon/node/pubsub_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-004-plan.md`, only for `## Execution Progress`

Read-only unless execution evidence proves a same-scope compile/test need:

- `go-mknoon/node/pubsub_delivery_test.go`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`

## closure bar

GL-004 is good enough when a deterministic subscribe-failure regression proves all of the following:

- the first `JoinGroupTopic` attempt returns a subscribe error after validator registration and topic join,
- the failed attempt leaves no `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, or `groupDiscoveryCtx` state for the group,
- the joined topic is closed so a retry can join the same topic name,
- the validator is unregistered so the retry does not fail with libp2p's duplicate-validator error,
- the retry succeeds and the joined topic remains usable for a valid publish path,
- required host commands pass with no untriaged new failures.

## source of truth

Authoritative inputs:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GL-004`.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` ordered row `GL-004`.
- Current code in `go-mknoon/node/pubsub.go` and `go-mknoon/node/node.go`.
- Current tests in `go-mknoon/node/pubsub_test.go` and `go-mknoon/node/pubsub_delivery_test.go`.
- `Test-Flight-Improv/test-gate-definitions.md` and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` for gate expectations.

Current code wins over stale prose. The breakdown's `needs_tests_only` disposition is stale for GL-004 because `JoinGroupTopic` currently calls `topic.Close()` on subscribe failure but does not call `UnregisterTopicValidator(topicName)`.

## session classification

`implementation-ready`

Row disposition for execution: `needs_code_and_tests`.

This is a host-only Go topic-lifecycle session. It does not require device, relay, or 3-party E2E proof. Flutter/Dart files are read-only unless execution evidence proves the Go change requires a Dart-visible contract update.

## exact problem statement

`JoinGroupTopic` registers a topic validator, joins the pubsub topic, then subscribes. If `topic.Subscribe()` fails, the current code closes the topic and returns the error, but leaves the validator registered. A later retry can then fail at `RegisterTopicValidator` with a duplicate-validator error even though the prior topic handle was closed and no group state was stored.

User-visible impact: a transient subscribe failure can make group topic rejoin unrecoverable for that group in the running node. The fix must preserve successful join behavior, GL-003 join-failure cleanup, duplicate-join rejection behavior, and leave cleanup behavior.

## files and repos to inspect next

Executor must inspect before editing:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `Test-Flight-Improv/test-gate-definitions.md`

Read-only reference if needed:

- `go-mknoon/third_party/go-libp2p-pubsub/topic.go`
- `go-mknoon/third_party/go-libp2p-pubsub/validation.go`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`

## existing tests covering this area

Existing adjacent coverage:

- `TestJoinGroupTopic_FailsWithoutPubSub` covers nil PubSub rejection and no attempted group state.
- `TestJoinGroupTopic_DuplicateJoinPreservesExistingState` covers duplicate join preserving the existing topic, subscription, config, key, and handler/discovery entries.
- `TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry` covers validator cleanup when `pubsub.Join(topicName)` fails after validator registration.
- `TestLeaveGroupTopic_CancelsDiscoveryContext` and `TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish` cover normal leave cleanup.
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` covers normal app-layer rejoin, not injected Go subscribe failure.

Missing coverage:

- No row-owned test currently injects failure after `Join` but before subscription setup.
- No existing test proves retry success after a subscribe failure, which is the only practical proof that both topic close and validator unregister happened.

## regression/tests to add first

Add `go-mknoon/node/pubsub_test.go::TestJoinGroupTopic_SubscribeFailureUnregistersValidatorClosesTopicAndAllowsRetry`.

Because `topic.Subscribe()` is not currently injectable, the executor may first add the smallest private test seam needed to force this error path, for example an unexported `Node` hook used only by `JoinGroupTopic`:

```go
joinGroupTopicSubscribeHook func(*pubsub.Topic) (*pubsub.Subscription, error)
```

The hook must default to nil and preserve production behavior by calling `topic.Subscribe()` when unset. This seam is allowed only to make the GL-004 regression observable; it must not change exported APIs or normal runtime behavior.

RED order:

1. Add the private test seam and the GL-004 regression, but do not add validator cleanup in the subscribe-failure branch yet.
2. Run the single new test and confirm it fails because retry cannot register the validator or otherwise cannot rejoin after the first subscribe failure.

Regression proof requirements:

- Start a node normally.
- Configure the hook to fail the first subscribe attempt with a deterministic error and delegate to `topic.Subscribe()` on retry.
- Assert the first `JoinGroupTopic` error contains `subscribe to topic`.
- Assert no partial group state exists after the failed attempt.
- Retry `JoinGroupTopic` for the same group and assert success.
- Publish a valid group message after retry and assert a non-empty message id.

## step-by-step implementation plan

1. Add `## Execution Progress` to this same plan file and record contract extraction.
2. Inspect `git status --short` and `git diff -- go-mknoon/node/pubsub.go go-mknoon/node/node.go go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_delivery_test.go` before editing. Preserve existing dirty-worktree changes.
3. Add only the minimal private subscribe hook needed for the RED regression if no existing deterministic subscribe-failure seam exists.
4. Add `TestJoinGroupTopic_SubscribeFailureUnregistersValidatorClosesTopicAndAllowsRetry` in `go-mknoon/node/pubsub_test.go`.
5. Run the single new Go test and capture the expected RED failure before the cleanup fix.
6. Fix `JoinGroupTopic` by unregistering the topic validator in the `topic.Subscribe()` error branch after closing the topic and before returning the wrapped subscribe error. Do not move config/key/topic/subscription storage earlier.
7. Rerun the single new Go regression and then the required direct commands and gates.
8. Stop. Do not update source matrix, breakdown, inventory, or unrelated docs in this execution session.

## risks and edge cases

- Validator leak: libp2p rejects a second validator registration for the same topic, so retry success is the main cleanup proof.
- Topic leak: if `topic.Close()` is removed or fails unnoticed, retry can fail with `topic already exists`.
- Partial state: config, key, subscription, subscription context, and discovery context are intentionally stored only after subscribe succeeds; the regression must keep proving that remains true.
- Goroutine leak: subscribe failure must not start `handleGroupSubscription` or `groupPeerDiscoveryLoop`.
- Dirty worktree: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, and `go-mknoon/node/pubsub_delivery_test.go` already have user/prior-session edits. Executor must not revert or normalize them.
- Test seam risk: the hook must stay private, nil by default, and limited to `JoinGroupTopic`.

## exact tests and gates to run

Required RED command before the cleanup fix:

```bash
(cd go-mknoon && go test ./node -run TestJoinGroupTopic_SubscribeFailureUnregistersValidatorClosesTopicAndAllowsRetry -count=1)
```

Required GREEN commands after the cleanup fix:

```bash
(cd go-mknoon && go test ./node -run TestJoinGroupTopic_SubscribeFailureUnregistersValidatorClosesTopicAndAllowsRetry -count=1)
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
./scripts/run_test_gates.sh groups
git diff --check
```

Not required unless scope changes:

- `./scripts/run_test_gates.sh baseline` is required only if Flutter production code changes.
- `./scripts/run_test_gates.sh transport` is required only if lifecycle, startup, resume, reconnect, relay, or device-backed recovery wiring changes.
- Device, relay, fake-network, and 3-party E2E proof are not required for GL-004.

## known-failure interpretation

The new single-test command must fail before the cleanup fix for the GL-004 reason and pass after the fix. It cannot be accepted red.

The row Go command, startup rejoin smoke, `groups` gate, and `git diff --check` are required post-fix evidence. Any failure must be triaged before fixing or deferring it as:

- caused by this session,
- pre-existing and documented,
- flaky with rerun evidence,
- unrelated-but-required,
- environment/tooling-related.

Do not classify an old red test as a new regression unless the GL-004 diff caused or widened it. Do not accept a missing required command as a known failure.

## done criteria

- Plan file records execution progress and final verdict.
- GL-004 regression was observed RED before the cleanup fix, then GREEN after it.
- `JoinGroupTopic` unregisters the topic validator on subscribe failure.
- Failed subscribe attempts leave no stored topic, subscription, config, key, subscription context, or discovery context.
- Retry join succeeds and publish after retry returns a non-empty message id.
- Required commands in `exact tests and gates to run` complete with no untriaged new failures.
- No source matrix, breakdown, inventory, Dart production, bridge, relay, or unrelated GL-row changes are included.

## scope guard

Non-goals:

- Do not solve GL-005 or later atomicity/nil-config/nil-key rows.
- Do not redesign `JoinGroupTopic`, topic lifecycle, discovery loops, validator semantics, or retry policy.
- Do not change exported Go APIs or bridge contracts.
- Do not edit vendored libp2p pubsub code.
- Do not edit Flutter rejoin/resume code unless the new Go test evidence proves the row cannot close without it.
- Do not broaden into device, relay, simulator, or multi-party E2E validation.
- Do not update the source matrix or breakdown during execution; closure documentation belongs to a separate closure step.

Overengineering examples:

- replacing concrete libp2p PubSub with a broad interface,
- adding general retry/backoff behavior,
- adding new lifecycle recovery flows,
- introspecting libp2p private validator maps through unsafe/reflection.

## accepted differences / intentionally out of scope

- Direct validator registry identity is not introspected. Retry success after the injected failure is the accepted proof because libp2p rejects duplicate validators and `Join` rejects an unclosed topic handle.
- App-layer rejoin tests do not inject this Go failure path; they remain smoke proof that normal startup rejoin still works after the Go fix.
- No device or relay proof is required for this host-only topic-lifecycle row.

## dependency impact

GL-004 protects later group topic lifecycle rows from inheriting stale validator or topic handles after a failed join attempt. If this plan changes to avoid code changes, later GL rows that assume retryable topic join cleanup should be revisited. GL-005 and later rows remain open and must not be closed by this session.

## dirty-worktree note

Planning observed a dirty worktree before this plan was created. Relevant existing dirty files include:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- the source matrix and breakdown artifacts

Executor must treat these as user/prior-session changes, inspect relevant diffs before editing, and avoid reverting unrelated changes.

## reviewer pass

Reviewer verdict: sufficient with adjustment, now applied.

Answers:

- Missing files/tests/gates: owner files needed an explicit section; added above. Required RED/GREEN single regression, row Go command, startup rejoin smoke, `groups` gate, and `git diff --check` are present.
- Stale assumptions: the breakdown's tests-only row disposition is stale; the plan correctly reclassifies GL-004 to code+tests.
- Overengineering: no broad interface or retry redesign is required; the only allowed seam is a private hook for deterministic subscribe-failure injection.
- Decomposition: one row, one failure branch, one regression, one cleanup fix.
- Minimum needed: private test seam if needed, RED regression, unregister validator on subscribe failure, required host evidence.

## arbiter decision

Final planning verdict: execution-ready.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact hook name may be chosen by the Executor, provided it stays private, nil by default, and scoped to `JoinGroupTopic`.
- Closure updates to the source matrix, breakdown, and inventory are deferred to a separate closure step.

Accepted differences intentionally left unchanged:

- Retry success is the validator/topic cleanup proof instead of private libp2p validator-map introspection.
- Device, relay, simulator, fake-network, and 3-party E2E proof are out of scope for this host-only row.

Why safe to implement now:

- The plan is bounded to GL-004, has explicit owner files, requires a RED regression before the cleanup fix, names exact host commands, and blocks on any missing required evidence.

## execution instructions for $implementation-execution-qa-orchestrator

Use this plan as the execution contract and as the file-backed progress artifact. Follow the skill's strict Executor then QA Reviewer sequence. The Executor owns only the GL-004 code/test changes above. The QA Reviewer must verify scope adherence, RED/GREEN evidence for the new regression, required command evidence, and that no source matrix or breakdown edits were made.

If the Executor cannot add a deterministic subscribe-failure regression without a wider abstraction than the private hook described here, stop as `blocked` instead of broadening the design.
