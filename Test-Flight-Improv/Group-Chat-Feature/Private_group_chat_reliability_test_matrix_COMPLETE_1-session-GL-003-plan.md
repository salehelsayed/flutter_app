# GL-003 Join Failure Validator Cleanup Plan

Status: execution-ready

## Planning Progress

- 2026-05-10 02:33:33 CEST | Evidence Collector started | Inspected: skill contract and intended plan path | Decision/blocker: GL-003 plan artifact created as the only planning progress file | Next action: inspect source row, breakdown row, code seams, tests, gates, and dirty worktree state.
- 2026-05-10 02:35:22 CEST | Evidence Collector completed | Inspected: source GL-003 row, session breakdown GL-003 row, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, Dart rejoin/resume files, Go and Flutter direct tests, libp2p pubsub implementation, `Test-Flight-Improv/test-gate-definitions.md`, and `scripts/run_test_gates.sh` | Decision/blocker: current Go code confirms a validator cleanup gap on the `RegisterTopicValidator` success then `Join` failure path; no device or relay proof is required | Next action: draft the narrow GL-003 implementation contract.
- 2026-05-10 02:35:22 CEST | Planner completed | Inspected: GL-001/GL-002 nearby tests and dirty diffs in `go-mknoon/node/pubsub_test.go` and `go-mknoon/node/pubsub_delivery_test.go` | Decision/blocker: plan is regression-first, expected product edit is only `go-mknoon/node/pubsub.go`, expected test edit is only `go-mknoon/node/pubsub_test.go` | Next action: reviewer sufficiency pass.
- 2026-05-10 02:35:22 CEST | Reviewer completed | Inspected: mandatory plan sections, gate contract, source ownership, and dirty-worktree guard | Decision/blocker: sufficient after explicitly making Dart/group gate conditional on Dart production edits and preserving unrelated dirty files | Next action: arbiter classification.
- 2026-05-10 02:35:22 CEST | Arbiter completed | Inspected: reviewer findings and final plan | Decision/blocker: no structural blockers remain; GL-003 is execution-ready | Next action: hand off to `$implementation-execution-qa-orchestrator`.

## Execution Progress

- 2026-05-10 02:39:31 CEST | Contract extraction started | Inspected: GL-003 plan, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, dirty worktree status | Decision/blocker: extracting exact scope, regression-first rule, required commands, scope guard, and dirty-worktree constraints before coding | Next action: complete contract extraction and spawn Executor.
- 2026-05-10 02:39:31 CEST | Contract extracted | Inspected: this GL-003 plan and required file/diff context | Decision/blocker: scope is limited to `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, and this progress section; required RED test is `TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry`; required final commands are the single GL-003 Go test, row Go test command, and Flutter startup rejoin test; named `groups` gate is conditional on Flutter/Dart production edits and not triggered by the expected Go-only fix | Next action: spawn Executor with the bounded GL-003 contract.
- 2026-05-10 02:39:31 CEST | Executor spawn started | Inspected/touched: this plan progress section only | Command: `codex exec -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app -s danger-full-access -a never` | Decision/blocker: use spawned Executor first per isolation rule | Next action: wait for Executor result, then spawn QA Reviewer.
- 2026-05-10 02:40:15 CEST | Executor spawn retry | Inspected/touched: this plan progress section only | Command: first `codex exec ... -a never` attempt exited 2 because this CLI accepts approval policy as a top-level option; retrying with `codex -a never exec ...` | Decision/blocker: no child work materialized before the CLI argument error | Next action: rerun Executor spawn with corrected CLI option order.
- 2026-05-10 02:42:16 CEST | Executor contract extraction started | Inspected: GL-003 plan and scoped file/diff context | Decision/blocker: operating as Executor only; no nested agents or QA role; extracting scope, RED test, implementation point, required commands, and dirty-worktree guard before coding | Next action: complete contract extraction and add the regression.
- 2026-05-10 02:42:16 CEST | Executor contract extracted | Inspected: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/node.go` lifecycle/field references, and dirty diffs for scoped files | Decision/blocker: existing `JoinGroupTopic` registers a validator before `pubsub.Join` and does not unregister on join failure; `LeaveGroupTopic` unregisters validators during normal cleanup; `node.go` has no separate validator registry; pre-existing GL-001/GL-002 test edits must be preserved | Next action: add `TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry` near existing join tests.
- 2026-05-10 02:42:55 CEST | RED regression added | Inspected/touched: `go-mknoon/node/pubsub_test.go` | Decision/blocker: added `TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry` near the JoinGroupTopic tests; product code is not changed yet | Next action: run the required single GL-003 test and confirm the expected duplicate-validator retry failure.
- 2026-05-10 02:42:55 CEST | RED test started | Inspected/touched: `go-mknoon/node/pubsub_test.go` | Command: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry$')` | Decision/blocker: expecting failure before product fix if the stale validator remains registered after the failed join | Next action: record exact result.
- 2026-05-10 02:43:24 CEST | RED test finished | Inspected/touched: `go-mknoon/node/pubsub_test.go` | Command: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry$')` | Result: exit 1; `--- FAIL: TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry`; `pubsub_test.go:2450: retry JoinGroupTopic: register topic validator: duplicate validator for topic /mknoon/group/gl-003-join-failure-retry`; package result `FAIL github.com/mknoon/go-mknoon/node 0.554s` | Decision/blocker: expected RED confirmed on old code; stale validator from failed join blocks retry | Next action: implement minimal `JoinGroupTopic` join-failure validator unregister.
- 2026-05-10 02:43:44 CEST | Implementation started | Inspected/touched: `go-mknoon/node/pubsub.go` | Decision/blocker: applying only the scoped join-failure cleanup after a successful validator registration and failed `pubsub.Join` | Next action: patch the `JoinGroupTopic` join error path.
- 2026-05-10 02:44:06 CEST | Implementation finished | Inspected/touched: `go-mknoon/node/pubsub.go` | Decision/blocker: `JoinGroupTopic` now calls `_ = n.pubsub.UnregisterTopicValidator(topicName)` before returning a `pubsub.Join` failure; no Dart, bridge, relay, duplicate-join, or subscription cleanup behavior changed | Next action: re-run the single GL-003 test.
- 2026-05-10 02:44:06 CEST | Single GL-003 test started | Inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go` | Command: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry$')` | Decision/blocker: validating the regression is GREEN after the scoped cleanup | Next action: record exact result.
- 2026-05-10 02:44:43 CEST | Single GL-003 test finished | Inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go` | Command: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry$')` | Result: exit 0; `ok github.com/mknoon/go-mknoon/node 0.532s` | Decision/blocker: GL-003 regression passes after the cleanup | Next action: run row-required Go command.
- 2026-05-10 02:44:43 CEST | Row Go command started | Inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go` | Command: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery')` | Decision/blocker: validating related join/leave/update/stop/recovery behavior | Next action: record exact result.
- 2026-05-10 02:45:12 CEST | Row Go command finished | Inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go` | Command: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery')` | Result: exit 0; `ok github.com/mknoon/go-mknoon/node 4.327s` | Decision/blocker: related Go behavior passes | Next action: run required Flutter startup rejoin smoke test.
- 2026-05-10 02:45:12 CEST | Flutter startup rejoin smoke started | Inspected/touched: no Flutter files touched | Command: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | Decision/blocker: required direct Flutter proof despite Go-only implementation; `./scripts/run_test_gates.sh groups` remains conditional and is not triggered because no Flutter/Dart production code changed | Next action: record exact result.
- 2026-05-10 02:45:55 CEST | Flutter startup rejoin smoke finished | Inspected/touched: no Flutter files touched | Command: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | Result: exit 0; `00:00 +3: All tests passed!` | Decision/blocker: required Flutter direct proof passes; dependency resolution reported available package updates but no test failure | Next action: record gate completion status.
- 2026-05-10 02:45:55 CEST | Required tests/gates completed | Inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, this plan progress section | Decision/blocker: all required direct commands passed after the fix; `./scripts/run_test_gates.sh groups` was not run because no Flutter/Dart group production code changed and the plan marks it conditional | Next action: inspect scoped final diff and write Executor completion.
- 2026-05-10 02:46:35 CEST | Executor completion | Inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, this plan progress section | Decision/blocker: Executor scope complete; final scoped diff contains the minimal `JoinGroupTopic` validator cleanup, the GL-003 regression, and this progress log; required direct commands passed; no required gate remains missing; QA Reviewer role not performed by this Executor | Next action: hand off to QA Reviewer.
- 2026-05-10 02:47:23 CEST | QA Reviewer spawn started | Inspected/touched: this plan progress section | Command: `codex -a never exec -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app -s danger-full-access` | Decision/blocker: strict separate QA Reviewer pass after Executor completion | Next action: wait for QA Reviewer result and run fix loop only if QA reports blocking issues.
- 2026-05-10 02:48:53 CEST | QA Reviewer started | Inspected/touched: this plan progress section, GL-003 plan contract, scoped `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_test.go` diffs, dirty worktree status | Decision/blocker: reviewing scope adherence, regression quality, recorded RED/GREEN evidence, conditional gate interpretation, and dirty-worktree preservation without modifying implementation files | Next action: inspect final code/test snippets and complete QA verdict.
- 2026-05-10 02:49:24 CEST | QA Reviewer completed | Inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, this plan progress section, dirty worktree status, and recorded required command evidence | Decision/blocker: accepted; no blocking issues found. The final scoped implementation unregisters the validator only after the current call's validator registration succeeds and `pubsub.Join` fails; the GL-003 regression covers expected RED duplicate-validator retry failure, no stored Mknoon group state, retry success, and publish success; required direct Go and Flutter evidence is present and consistent; `./scripts/run_test_gates.sh groups` was correctly not triggered because no Flutter/Dart production code changed; pre-existing GL-001/GL-002 and unrelated dirty worktree changes were preserved | Next action: controller may close GL-003 without a fix pass.
- 2026-05-10 02:50:25 CEST | Final verdict started | Inspected/touched: QA result and this plan progress section | Decision/blocker: QA reported no blocking issues and no follow-ups; no fix pass required | Next action: write final execution verdict.
- 2026-05-10 02:50:25 CEST | Final verdict written | Inspected/touched: this plan final verdict and progress section | Decision/blocker: accepted; strict Executor then QA sequencing completed with spawned-agent isolation; local sequential fallback was not used; all required direct evidence is recorded and passing | Next action: close GL-003.

## Final verdict

accepted

Execution completed for GL-003. Strict Executor then QA sequencing completed with spawned-agent isolation, no local fallback, no fix pass, no blocking issues, and no non-blocking follow-ups.

## real scope

Own exactly source row GL-003: `Join failure after validator registration unregisters validator`.

In scope:

- Add a direct Go regression proving that when `JoinGroupTopic` registers a topic validator and then `pubsub.Join` fails, the failed attempt leaves no stale validator.
- Fix the `JoinGroupTopic` error path in `go-mknoon/node/pubsub.go` so a retry can register exactly one validator and complete the join.
- Preserve existing successful join, duplicate join, leave, update config/key, stop node, and group recovery behavior.
- Run host-only direct proof. No simulator, device, relay, or real-network proof is required for this row.

Out of scope:

- Do not edit the source matrix, session breakdown, or any plan other than this file.
- Do not change bridge command payloads, Dart rejoin orchestration, lifecycle recovery semantics, database schema, relay behavior, or validator authorization rules unless the GL-003 regression proves the Go-only fix is impossible.
- Do not reopen GL-001 or GL-002.

Expected write scope:

- Production: `go-mknoon/node/pubsub.go`.
- Tests: `go-mknoon/node/pubsub_test.go`.

Expected inspect-only files:

- `go-mknoon/node/node.go`.
- `go-mknoon/node/pubsub_delivery_test.go`.
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`.
- `lib/core/lifecycle/handle_app_resumed.dart`.
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`.
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`.

## closure bar

The session is good enough when a failed partial join that occurs after validator registration but before topic join completion cleans up the validator, stores no group state, and allows a subsequent retry to join the same group successfully with one active validator for the topic. Existing duplicate-join behavior must remain unchanged: an already joined group still returns the existing `already joined group topic` error from `JoinGroupTopic`, and the bridge may continue mapping that error to idempotent success.

## source of truth

- Primary row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GL-003`.
- Session ledger and ordered entry: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row/session `GL-003`.
- Current code wins over stale prose.
- For named Flutter gates, `scripts/run_test_gates.sh` wins over `Test-Flight-Improv/test-gate-definitions.md` if they disagree.
- This plan is the active execution contract for GL-003.

## session classification

`implementation-ready`.

## exact problem statement

`go-mknoon/node/pubsub.go` currently registers a validator before joining the libp2p topic:

- `JoinGroupTopic` calls `n.pubsub.RegisterTopicValidator(topicName, ...)`.
- If `n.pubsub.Join(topicName)` then fails, the function returns `join topic ...` without calling `UnregisterTopicValidator`.
- libp2p stores validators by topic and rejects a second registration with `duplicate validator for topic ...`.

The user-visible risk is that a transient or stale-topic join failure can poison a group topic retry. Startup or resume rejoin can keep failing even after the underlying topic condition is fixed, leaving group chat unable to receive live messages for that topic.

The fix must improve retry correctness without changing group authorization, publish encryption/signing, key epoch handling, group config persistence, Dart retry loops, bridge command shapes, or duplicate-join idempotency.

## files and repos to inspect next

Before editing, the Executor must inspect:

- `go-mknoon/node/pubsub.go`: `JoinGroupTopic`, `LeaveGroupTopic`, and any local cleanup pattern around validator/topic/subscription ownership.
- `go-mknoon/node/node.go`: confirm no separate validator registry or lifecycle cleanup exists there.
- `go-mknoon/node/pubsub_test.go`: place the GL-003 regression near the existing `JoinGroupTopic` tests and preserve current GL-001/GL-002 dirty changes.
- `go-mknoon/node/pubsub_delivery_test.go`: inspect only if delivery proof is considered; do not edit unless the direct GL-003 regression cannot prove publish/retry.
- `lib/features/groups/application/rejoin_group_topics_use_case.dart` and `lib/core/lifecycle/handle_app_resumed.dart`: inspect only to confirm no Dart retry contract change is required.
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` and `test/core/lifecycle/app_lifecycle_recovery_test.dart`: inspect only if Dart files are touched or Flutter direct proof fails.

## existing tests covering this area

- `go-mknoon/node/pubsub_test.go` already covers basic join success, no-pubsub failure, duplicate join rejection, duplicate join preserving state, leave cleanup, stop cleanup, config/key update, and group recovery state preservation.
- `go-mknoon/node/pubsub_delivery_test.go` currently includes a dirty-worktree GL-002 delivery regression proving duplicate join does not break delivery.
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` covers Flutter startup rejoin command construction and fake-network live-message recovery.
- `test/core/lifecycle/app_lifecycle_recovery_test.dart` covers resume-triggered group rejoin and recovery acknowledgement behavior.
- Missing before GL-003: no test forces `RegisterTopicValidator` to succeed and `pubsub.Join` to fail, then verifies validator cleanup and retry success.

## regression/tests to add first

Add the direct Go regression first in `go-mknoon/node/pubsub_test.go`, near the existing `JoinGroupTopic` tests:

Proposed test name:

```go
func TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry(t *testing.T)
```

Regression shape:

1. Start a node normally.
2. Choose a GL-003-specific group id and build a config containing `n.PeerId()` as an allowed member with a generated public key and valid generated group key.
3. Create a stale libp2p topic handle directly with `staleTopic, err := n.pubsub.Join(GroupTopicPrefix + groupId)` while leaving `n.groupTopics[groupId]` empty. This makes `RegisterTopicValidator` succeed inside `JoinGroupTopic`, then makes `n.pubsub.Join(topicName)` fail with `topic already exists`.
4. Call `n.JoinGroupTopic(groupId, config, keyInfo)` and assert the error contains `join topic` and `topic already exists`.
5. Assert no Mknoon group state was stored for the failed attempt: no `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, or `groupDiscoveryCtx` entry for the group.
6. Close `staleTopic`.
7. Retry `n.JoinGroupTopic(groupId, config, keyInfo)`.
8. Assert retry succeeds. On current broken code this should fail at `RegisterTopicValidator` with a duplicate validator error.
9. Publish a valid local group message using the matching private/public key and generated group key. Assert publish succeeds. Peer count can be zero because this is host-only single-node proof.

Run this test before the product fix and expect it to fail. If it passes before the product change, stop and re-check whether current dirty state already fixed GL-003 or whether the regression did not actually hit the intended failure path.

## step-by-step implementation plan

1. Record execution progress in this same plan file under `## Execution Progress`.
2. Inspect dirty diffs before editing `go-mknoon/node/pubsub_test.go` or `go-mknoon/node/pubsub_delivery_test.go`; preserve unrelated user changes.
3. Add the GL-003 regression in `go-mknoon/node/pubsub_test.go`.
4. Run the single new test and confirm it is RED for the expected duplicate-validator retry failure.
5. In `go-mknoon/node/pubsub.go`, update the `JoinGroupTopic` error path after `n.pubsub.Join(topicName)` fails to call `_ = n.pubsub.UnregisterTopicValidator(topicName)` before returning the wrapped join error.
6. Keep the cleanup local and minimal. Do not add a new pubsub abstraction, do not change the node lock strategy, and do not convert duplicate joins into successful `JoinGroupTopic` returns.
7. Re-run the single GL-003 test and confirm it is GREEN.
8. Run the row-required Go command.
9. Run the row-required Flutter startup rejoin direct test.
10. Run any conditional gates below only if their trigger condition is met.
11. QA must review scope, dirty-worktree preservation, behavior, regression quality, and exact test evidence before accepting.

Stop conditions:

- If the single GL-003 regression cannot be made to fail before product changes, stop and report the stale/evidence blocker.
- If fixing `JoinGroupTopic` requires changing Dart rejoin or bridge contracts, stop and reclassify before widening scope.
- If required tests fail, triage before any fix attempt and classify each failure as caused by GL-003, pre-existing, flaky, unrelated-but-required, or environment/tooling.

## risks and edge cases

- A validator leak after partial join blocks retry because libp2p rejects duplicate validators by topic.
- A stale topic handle can make `pubsub.Join` fail while Mknoon `groupTopics` has no entry, which is different from the normal duplicate-join guard.
- Cleanup must not remove validators for already joined groups; the change belongs only after a new validator registration succeeded in the current call and topic join then failed.
- The new test must avoid racing subscription/discovery goroutines because the failed attempt should never create them.
- Single-node publish after retry may report zero topic peers; that is acceptable for GL-003 because the proof is validator cleanup and local retry health, not network delivery.

## exact tests and gates to run

Required direct tests:

```bash
(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry$')
```

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery')
```

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Conditional direct tests:

```bash
flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart
```

Run only if `lib/core/lifecycle/handle_app_resumed.dart` or Dart resume/rejoin behavior is changed.

Conditional named gate:

```bash
./scripts/run_test_gates.sh groups
```

Run only if Flutter/Dart group production code is changed. If the implementation stays Go-only as expected, the row-required direct Flutter startup-rejoin test is sufficient and no named Flutter gate is mandatory.

Not required:

- `./scripts/run_test_gates.sh transport`.
- `./scripts/run_test_gates.sh group-real-network-nightly`.
- Any simulator, device, relay, or multi-relay command.

## known-failure interpretation

- The initial single GL-003 test is expected to fail before the product fix if it correctly reproduces the bug.
- Final required direct tests must pass, or failures must be triaged before any fix attempt.
- Existing dirty-worktree changes include `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `Test-Flight-Improv/test-gate-definitions.md`, and many unrelated Flutter files. Do not classify unrelated failures from those files as GL-003 regressions without evidence.
- If a required command fails outside GL-003, capture the exact failing test and output, rerun the narrow failing test when useful, and report whether it is pre-existing, unrelated-but-required, flaky, or environment/tooling-related. Do not broaden the code change to fix unrelated failures.

## done criteria

- GL-003 regression is added in `go-mknoon/node/pubsub_test.go`.
- The regression fails before the product fix for the intended stale-validator retry reason, unless current code is proven already fixed and the session is reclassified.
- `go-mknoon/node/pubsub.go` unregisters the validator when the current `JoinGroupTopic` call registers it and then `pubsub.Join` fails.
- Failed partial join stores no Mknoon group topic, subscription, config, key, subscription context, or discovery context state.
- Retry after removing the stale topic succeeds.
- Valid publish after retry succeeds.
- Required direct tests pass or any non-GL-003 failures are explicitly triaged.
- No source matrix, breakdown, unrelated plans, Dart product code, bridge contracts, relay behavior, or device-only tests are changed for this row.

## scope guard

Do not:

- Change `GroupJoinTopic` bridge idempotency.
- Treat duplicate `JoinGroupTopic` calls as success inside Go node code.
- Change `rejoinGroupTopics` retry policy, lifecycle recovery acknowledgement, group database state, or fake network test helpers.
- Add a PubSub wrapper solely for test injection if the stale-topic handle creates the needed failure deterministically.
- Touch relay discovery, peer scoring, key rotation, authorization validation, or offline inbox behavior.
- Edit `Private_group_chat_reliability_test_matrix_COMPLETE_1.md` or `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.

## accepted differences / intentionally out of scope

- GL-003 is a Go node lifecycle cleanup fix, not a Flutter UX or bridge idempotency change.
- The test may prove "exactly one validator" indirectly through retry success and valid publish because libp2p itself enforces one validator per topic and rejects duplicates.
- Network delivery to another peer is out of scope; GL-002 already owns duplicate-join delivery preservation, and GL-003 only needs host-side validator cleanup plus retry health.
- Subscribe-failure cleanup after a successful topic join is not required by GL-003 unless the Executor introduces a tiny local cleanup helper and can keep the behavior within this same partial-join cleanup path.

## dependency impact

Later group reliability rows that rely on startup/resume rejoin should assume GL-003 closes only the partial Go join validator leak. If GL-003 is blocked or reclassified, later rejoin/recovery sessions should not assume retry failures are fixed after a `RegisterTopicValidator` success followed by `Join` failure.

## dirty-worktree note

The worktree was dirty before this plan was written. Relevant dirty files include:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `Test-Flight-Improv/test-gate-definitions.md`
- Multiple unrelated Flutter production and test files

Executor must inspect existing diffs before editing any dirty file and must preserve unrelated user changes. For the expected GL-003 implementation, only `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_test.go` should need edits.

## reviewer pass

Plan sufficiency: sufficient as-is.

Reviewer checks:

- Scope is limited to GL-003 and does not bundle GL-001, GL-002, Dart rejoin changes, bridge behavior, relay, or simulator proof.
- The regression-first rule is explicit and names a deterministic failure path in current libp2p behavior.
- Closure bar includes cleanup, no stored state, retry success, and valid publish.
- Tests and gates are exact, host-only, and conditional where Dart production edits would widen proof needs.
- Dirty-worktree handling is explicit.

Missing items: none blocking.

## arbiter pass

Structural blockers: none.

Incremental details intentionally deferred:

- Full Group Messaging Gate is conditional rather than mandatory for the expected Go-only fix.
- Additional subscription-error cleanup is optional only if it remains a local partial-registration cleanup and does not broaden the test contract.

Accepted differences intentionally left unchanged:

- Bridge-level duplicate join idempotency remains in `go-mknoon/bridge/bridge.go`.
- Flutter rejoin/lifecycle code remains inspect-only unless evidence disproves the Go-only fix.

## execution instructions for `$implementation-execution-qa-orchestrator`

Use this file as the execution contract and as the execution progress artifact.

Executor:

- Extract this contract before coding.
- Add `## Execution Progress` to this file and update it with compact timestamped entries.
- Add the GL-003 regression first and prove it fails for the expected reason.
- Implement only the minimal `JoinGroupTopic` cleanup in `go-mknoon/node/pubsub.go`.
- Run the exact required direct tests and any conditional gates whose trigger was met.
- Triage any failed required test before fixing.

QA Reviewer:

- Verify the regression would fail on the old code path.
- Verify the product change unregisters only the validator registered by the failing current call.
- Verify no unrelated dirty-worktree changes were overwritten.
- Verify all required direct tests and triggered gates were run.
- Classify any remaining issue as blocking or non-blocking according to the execution QA skill.
