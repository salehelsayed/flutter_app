# GL-002 Session Plan: Join Is Idempotence-Safe For An Already Joined Group

Status: execution-ready

## Planning Progress

- 2026-05-10 02:14:46 CEST | Evidence Collector started | Files inspected since last update: `implementation-plan-orchestrator/SKILL.md`, `git status --short`, user-provided GL-002 ledger row | Decision/blocker: intended plan path confirmed; dirty worktree has unrelated pre-existing changes and will be treated as user-owned | Next action: inspect source row, breakdown entry, owner files, and existing tests.
- 2026-05-10 02:16:19 CEST | Evidence Collector completed | Files inspected since last update: source matrix GL-002, session breakdown GL-002, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/app_lifecycle_recovery_test.dart`, `lib/core/bridge/bridge_group_helpers.dart`, `test/core/bridge/fake_bridge.dart` | Decision/blocker: current code rejects duplicate joins before validator/join/subscription setup, but existing row coverage only checks the error and does not prove first-join state preservation/usability | Next action: draft a tests-only plan scoped to GL-002.
- 2026-05-10 02:17:43 CEST | Planner completed | Files inspected since last update: GL-002 evidence set only | Decision/blocker: plan is tests-only; no product code, matrix, or breakdown edits are in scope for execution | Next action: reviewer checks direct tests, gates, and scope guard.
- 2026-05-10 02:18:45 CEST | Reviewer completed | Files inspected since last update: drafted plan contract | Decision/blocker: sufficient with explicit Go delivery proof added because source row requires publish/receive after the failed second join | Next action: arbiter classifies no structural blocker.
- 2026-05-10 02:18:45 CEST | Arbiter completed | Files inspected since last update: reviewer findings and final plan | Decision/blocker: no structural blockers remain; direct test/gate contract is host-only and execution-safe | Next action: hand off to `$implementation-execution-qa-orchestrator`.

## real scope

Own exactly source row `GL-002`: duplicate `JoinGroupTopic(G)` after a successful first join must return an `already joined` error without replacing the first join's topic, subscription, config, key, validator inputs, or active handler/discovery state, and the first join must still deliver a group message.

This session is tests-only. The intended execution delta is limited to:

- `go-mknoon/node/pubsub_test.go`: add a GL-002 state-preservation regression adjacent to the existing double-join test.
- `go-mknoon/node/pubsub_delivery_test.go`: add a GL-002 delivery regression proving publish/receive still works after the rejected duplicate join.

No production code, Flutter code, source matrix, or breakdown edits are in scope for this execution session.

## closure bar

GL-002 is complete when host-side tests prove both halves of the row:

- Duplicate join fails clearly with `already joined`.
- The successful first join remains the active usable join: topic/subscription pointers and stored config/key are not replaced, group state remains present, and a post-failure message published from the first join is received by another joined peer.

If either regression fails against current product code, stop and return `blocked`; do not convert this tests-only row into product implementation work inside GL-002.

## source of truth

Authoritative sources, in priority order:

1. Current code and tests in `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, and `go-mknoon/node/pubsub_delivery_test.go`.
2. Source matrix row `GL-002` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
3. Session breakdown row `GL-002` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
4. Flutter rejoin/lifecycle tests only as host confirmation that higher layers still issue expected join calls.

If prose and code disagree, current code/tests win for implementation details, while the GL-002 source row wins for the expected behavior to prove.

## session classification

`implementation-ready`

Row disposition: `needs_tests_only`

Execution ownership: tests only, host-only. No device, simulator, relay-service, or 3-party E2E proof is required unless execution evidence directly contradicts this plan.

## exact problem statement

`JoinGroupTopic` currently returns early when `groupTopics[groupId]` already exists. Existing coverage has `TestJoinGroupTopic_RejectsDoubleJoin`, but that test only asserts the duplicate call errors. It does not prove the row-owned safety contract that the second call leaves the first join's topic, subscription, config, key, validator inputs, and active delivery path intact.

User-visible behavior protected by this row: app startup/resume/recovery may attempt to join a topic that is already live. Even when Go rejects the duplicate join, that rejection must not tear down or replace the live group topic, or ongoing group chat delivery can be interrupted.

## files and repos to inspect next

Production/owner files to inspect only:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`

Tests to edit or inspect:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`

Dirty-worktree note: this workspace already has user-owned modifications in several files, including `go-mknoon/node/pubsub_test.go` and docs/test files. Execution must inspect the current diff before editing and must not revert or overwrite unrelated existing changes, especially the adjacent GL-001 updates already present in `pubsub_test.go`.

## existing tests covering this area

- `go-mknoon/node/pubsub_test.go::TestJoinGroupTopic_RejectsDoubleJoin` asserts the duplicate call returns an error containing `already joined`, but it does not assert state preservation or delivery after the failure.
- `go-mknoon/node/pubsub_test.go::TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh` proves in-place recovery does not clear existing state, but it does not exercise duplicate join.
- `go-mknoon/node/pubsub_delivery_test.go` has publish/receive coverage for joined peers, but no row-specific duplicate-join delivery proof.
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` proves Flutter sends expected `group:join` payloads through `FakeBridge`.
- `test/core/lifecycle/app_lifecycle_recovery_test.dart` proves resume/recovery calls `group:join` and acknowledgement paths, but it does not simulate Go's `already joined` rejection.

## regression/tests to add first

Add the GL-002 regressions before considering any product change:

1. In `go-mknoon/node/pubsub_test.go`, add `TestJoinGroupTopic_DuplicateJoinPreservesExistingState`.
   - Start a node.
   - Join `groupId := "gl-002-double-join"` once with a config whose writer/admin member is `n.PeerId()` and whose public key comes from `generateEd25519KeyPair`.
   - Snapshot under lock: `groupTopics[groupId]`, `groupSubs[groupId]`, `groupConfigs[groupId]`, `groupKeys[groupId]`, and the presence/length of `groupSubCtx` and `groupDiscoveryCtx`.
   - Call `JoinGroupTopic` again with a visibly different config/key.
   - Assert the error contains `already joined`.
   - Re-snapshot and assert the topic/sub/config/key pointers are unchanged, stored key epoch/key did not become the second key, and all expected state entries remain present.
   - Do not compare `context.CancelFunc` values directly; function values are not safely comparable. Use map presence/length plus preserved topic/subscription and delivery proof.

2. In `go-mknoon/node/pubsub_delivery_test.go`, add `TestJoinGroupTopic_DuplicateJoinPreservesDelivery`.
   - Use existing local-node delivery helpers and a `testEventCollector`.
   - Join node A and node B to the same group.
   - Dial/wait until node A sees node B as a live topic peer.
   - Call duplicate `JoinGroupTopic` on node A with different config/key and assert `already joined`.
   - Publish from node A using the original key/config.
   - Assert node B receives `group_message:received` with the expected text/message id/key epoch.

These tests should pass on the current implementation. If they fail, execution must classify the failure and stop as `blocked` because this row is tests-only.

## step-by-step implementation plan

1. Read the current dirty diff for `go-mknoon/node/pubsub_test.go` and `go-mknoon/node/pubsub_delivery_test.go`; preserve unrelated user-owned edits.
2. Add the state-preservation regression in `pubsub_test.go` using existing test helpers and a custom config with a real generated public key.
3. Add the delivery regression in `pubsub_delivery_test.go` using existing local-node and collector helpers; keep it row-named and narrow.
4. Run the targeted GL-002 Go tests first.
5. Run the required row Go gate from the breakdown.
6. Run the required Flutter host confirmation tests.
7. If all required tests pass, record exact results in this plan file under `## Execution Progress` during execution.
8. If a regression fails because product code does not satisfy GL-002, stop with `blocked` and recommend reclassifying the row to code+tests; do not patch product code in this session.

## risks and edge cases

- Duplicate join using a different config/key must not replace the original config/key or the validator's backing inputs.
- Delivery after duplicate failure must use the original group key and original membership.
- Function-valued cancel handlers cannot be compared directly; avoid brittle function pointer tricks.
- Two-node pubsub delivery can be timing-sensitive; use existing wait helpers rather than fixed sleeps where helpers already exist.
- Flutter rejoin comments describe the call as idempotent; for GL-002, idempotence means non-destructive duplicate rejection, not success/no-op semantics.

## exact tests and gates to run

Targeted tests after adding regressions:

```sh
(cd go-mknoon && go test ./node -run 'TestJoinGroupTopic_DuplicateJoinPreservesExistingState|TestJoinGroupTopic_DuplicateJoinPreservesDelivery|TestJoinGroupTopic_RejectsDoubleJoin')
```

Required row Go gate from the breakdown:

```sh
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery')
```

Required Flutter host confirmation:

```sh
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart
```

No device, simulator, relay server, baseline, or broad Flutter production gate is required because this session changes only Go tests unless execution evidence proves otherwise.

## known-failure interpretation

There are no accepted known failures for GL-002 in this plan. Any failure in the targeted tests or required gates must be triaged before fixing or closing:

- `caused_by_GL-002`: regression addition exposed product behavior that violates GL-002; stop blocked because product changes are out of scope.
- `pre_existing`: failure is already present on unchanged code and unrelated to the new GL-002 tests; record exact command/output and do not hide it.
- `unrelated_but_required`: failure is outside GL-002 but in a required command; execution cannot be accepted unless the failure is documented as known by the current gate definitions or the user explicitly narrows acceptance.
- `environment/tooling`: command cannot run due local environment; record exact blocker and retry focus.

## done criteria

- GL-002 state-preservation regression exists in `go-mknoon/node/pubsub_test.go`.
- GL-002 delivery regression exists in `go-mknoon/node/pubsub_delivery_test.go`.
- No production code, Flutter code, source matrix, or breakdown file was changed during execution.
- Targeted Go tests pass.
- Required row Go gate passes or any failure is explicitly triaged and accepted by the governing known-failure rules.
- Required Flutter host confirmation tests pass or any failure is explicitly triaged and accepted by the governing known-failure rules.
- Execution progress and exact command results are recorded in this plan file.

## scope guard

Do not change `JoinGroupTopic` semantics from duplicate rejection to success/no-op in GL-002.

Do not modify bridge error handling, Flutter rejoin behavior, lifecycle recovery logic, relay/session behavior, durable inbox logic, group config update behavior, key rotation, validator cleanup for join/subscribe failures, or any later GL row.

Do not add a new test seam just to introspect the registered pubsub validator identity. Prove validator-input preservation through unchanged stored config/key and delivery after duplicate rejection.

Do not update the source matrix or session breakdown in this execution step; closure/index updates belong to a later closure-audit step unless the user explicitly requests them.

## accepted differences / intentionally out of scope

- Direct validator registry identity is not asserted because `go-libp2p-pubsub` does not expose a stable row-local assertion seam here. GL-002 accepts indirect proof through unchanged config/key backing state and successful post-failure delivery.
- Flutter does not need to treat `already joined` as success in this row; changing that would be a product behavior decision outside GL-002.
- Device, relay, and 3-party E2E proof are intentionally omitted because the row is host-only and the breakdown lists no dependency requiring live infrastructure.
- GL-003/GL-004 validator cleanup after partial join failures is intentionally separate.

## dependency impact

Closing GL-002 gives later Group Topic Lifecycle rows a stable duplicate-join baseline: a rejected duplicate join is non-destructive. If GL-002 fails and needs product code, later rows that assume preserved first-join state should pause until this row is replanned and executed as code+tests.

## reviewer pass

Reviewer verdict: sufficient with adjustments already applied.

Missing item found during review: the initial draft's unit-only proof would not fully satisfy the source row's publish/receive wording. The final plan requires a companion Go delivery regression, still host-only and still tests-only.

No overengineering found after constraining the delivery proof to existing helpers and a single post-duplicate publish.

## arbiter decision

Structural blockers: none.

Incremental details intentionally deferred: exact helper names inside the Go test body may follow local style during execution.

Accepted differences: no direct validator registry identity assertion; no Flutter semantic change for duplicate Go join errors.

Final planning verdict: execution-safe for `$implementation-execution-qa-orchestrator`.

## execution instructions for implementation-execution-qa-orchestrator

Extract this contract exactly:

- Scope: GL-002 only, tests-only, host-only.
- Regression first: add the two Go regressions listed above before considering any other change.
- Product code stop rule: if the new tests expose a product bug, stop blocked rather than widening scope.
- Required commands: run the targeted Go tests, the row Go gate, and the two Flutter host tests exactly as listed.
- QA focus: verify no production code, source matrix, or breakdown edits occurred; verify dirty worktree changes in edited test files were preserved; verify exact command results are recorded under `## Execution Progress`.

## Execution Progress

- 2026-05-10 02:21:15 CEST | Contract extraction started | Files inspected or touched: `implementation-execution-qa-orchestrator/SKILL.md`, this GL-002 plan, `git status --short`, dirty diff for `go-mknoon/node/pubsub_test.go` and `go-mknoon/node/pubsub_delivery_test.go` | Command: none running | Decision/blocker: no spawned child-agent tool is exposed in this session; current agent is treated as the isolated execution-orchestrator invocation and will use the skill's local sequential fallback | Next action: complete contract extraction and start the local Executor pass.
- 2026-05-10 02:21:15 CEST | Contract extraction completed | Files inspected or touched: this GL-002 plan | Command: none running | Decision/blocker: scope is GL-002 tests-only and host-only; write scope is `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, and this plan's execution progress; required commands are the targeted Go tests, row Go gate, and two Flutter host confirmation tests exactly as listed | Next action: local Executor inspects owner tests and adds the two required regressions without touching production code.
- 2026-05-10 02:21:59 CEST | Local Executor started | Files inspected or touched: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go` | Command: none running | Decision/blocker: existing GL-001 change in `pubsub_test.go` is preserved; local helpers support the required state and delivery proofs | Next action: add `TestJoinGroupTopic_DuplicateJoinPreservesExistingState` and `TestJoinGroupTopic_DuplicateJoinPreservesDelivery`.
- 2026-05-10 02:23:43 CEST | Local Executor completed implementation | Files inspected or touched: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go` | Command: `gofmt -w go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_delivery_test.go` finished with exit 0 | Decision/blocker: added the two GL-002 tests only; no production, Flutter, source matrix, or breakdown files were edited by the Executor | Next action: run the targeted Go tests exactly as required.
- 2026-05-10 02:23:43 CEST | Required targeted Go tests started | Files inspected or touched: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go` | Command: `(cd go-mknoon && go test ./node -run 'TestJoinGroupTopic_DuplicateJoinPreservesExistingState|TestJoinGroupTopic_DuplicateJoinPreservesDelivery|TestJoinGroupTopic_RejectsDoubleJoin')` | Decision/blocker: pending | Next action: record exact result before running the row Go gate.
- 2026-05-10 02:24:11 CEST | Required targeted Go tests finished | Files inspected or touched: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go` | Command: `(cd go-mknoon && go test ./node -run 'TestJoinGroupTopic_DuplicateJoinPreservesExistingState|TestJoinGroupTopic_DuplicateJoinPreservesDelivery|TestJoinGroupTopic_RejectsDoubleJoin')` | Result: exit 0, `ok  	github.com/mknoon/go-mknoon/node	0.645s` | Decision/blocker: targeted GL-002 regressions and existing double-join test pass | Next action: run required row Go gate.
- 2026-05-10 02:24:11 CEST | Required row Go gate started | Files inspected or touched: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go` | Command: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery')` | Decision/blocker: pending | Next action: record exact result before Flutter host confirmation.
- 2026-05-10 02:24:38 CEST | Required row Go gate finished | Files inspected or touched: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go` | Command: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery')` | Result: exit 0, `ok  	github.com/mknoon/go-mknoon/node	4.311s` | Decision/blocker: required row Go gate passes | Next action: run first Flutter host confirmation test.
- 2026-05-10 02:24:38 CEST | Required Flutter host confirmation started | Files inspected or touched: none | Command: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | Decision/blocker: pending | Next action: record exact result before the second Flutter host confirmation test.
- 2026-05-10 02:25:01 CEST | Required Flutter host confirmation finished | Files inspected or touched: none | Command: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | Result: exit 0, `00:00 +3: All tests passed!` | Decision/blocker: startup rejoin host confirmation passes | Next action: run second Flutter host confirmation test.
- 2026-05-10 02:25:01 CEST | Required Flutter lifecycle host confirmation started | Files inspected or touched: none | Command: `flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart` | Decision/blocker: pending | Next action: record exact result before QA review.
- 2026-05-10 02:25:23 CEST | Required Flutter lifecycle host confirmation finished | Files inspected or touched: none | Command: `flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart` | Result: exit 0, `00:00 +22: All tests passed!` | Decision/blocker: lifecycle recovery host confirmation passes; all required commands passed | Next action: start local QA Reviewer pass.
- 2026-05-10 02:25:23 CEST | Local QA Reviewer started | Files inspected or touched: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, this GL-002 plan | Command: none running | Decision/blocker: pending strict review for scope adherence, required regressions, exact command evidence, and preservation of unrelated dirty work | Next action: inspect final diff/status and classify blocking issues, if any.
- 2026-05-10 02:26:03 CEST | Local QA Reviewer completed | Files inspected or touched: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, this GL-002 plan | Command: `git diff --check -- go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_delivery_test.go` finished with exit 0 | Decision/blocker: no blocking issues; scope adhered to tests-only write guard, required regressions are present, required commands are recorded, and unrelated dirty work including GL-001 in `pubsub_test.go` was preserved | Next action: write final execution verdict.
- 2026-05-10 02:26:03 CEST | Final execution verdict written | Files inspected or touched: this GL-002 plan | Command: none running | Decision/blocker: accepted; no blocking issues and no non-blocking follow-ups deferred | Next action: ready for closure-audit handoff.

## Final Execution Verdict

Final verdict: `accepted`

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none.

Why safe to consider complete: GL-002 is tests-only and host-only; the two required Go regressions were added, all required Go and Flutter host commands passed, no production code or Flutter source was edited, and the source matrix/breakdown were not modified during execution.
