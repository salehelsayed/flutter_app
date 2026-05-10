# GL-001 Session Plan: Join Rejects When PubSub Has Not Been Initialized

Status: execution-ready

## Planning Progress
- 2026-05-10 01:53:42 CEST | Evidence Collector started | Inspected: `implementation-plan-orchestrator` skill, source matrix row `GL-001`, session breakdown row `GL-001`, intended plan path existence | Decision/blocker: source row and intended plan path confirmed; no blocker | Next action: inspect owner code and direct tests for current behavior and coverage
- 2026-05-10 01:55:10 CEST | Evidence Collector completed | Inspected: `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/app_lifecycle_recovery_test.dart`, `Test-Flight-Improv/test-gate-definitions.md`, `git status --short` | Decision/blocker: current Go code returns `pubsub not initialized` before topic/state mutation; existing test covers the error only, not the no-side-effects contract; dirty worktree exists; no blocker | Next action: draft tests-only execution plan
- 2026-05-10 01:55:10 CEST | Planner completed | Inspected: evidence collected above | Decision/blocker: GL-001 should be executed as a host-only Go unit regression plus the row-required host Flutter smoke; no product-code, device, relay, or named gate proof is required unless execution evidence contradicts the row | Next action: run reviewer sufficiency pass
- 2026-05-10 01:56:50 CEST | Reviewer completed | Inspected: drafted plan sections, row-required commands, dirty-worktree note, scope guard, regression contract | Decision/blocker: sufficient as drafted after clarifying that lifecycle test files are context unless touched; no structural blocker | Next action: arbiter classification
- 2026-05-10 01:56:50 CEST | Arbiter completed | Inspected: reviewer finding and final plan | Decision/blocker: no structural blockers; plan is execution-ready for GL-001 only | Next action: hand off to `$implementation-execution-qa-orchestrator`

## Execution Progress
- 2026-05-10 01:58:43 CEST | Contract extraction started | Inspected: `implementation-execution-qa-orchestrator` skill, this GL-001 plan, `git status --short`, `git diff -- go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `Test-Flight-Improv/test-gate-definitions.md`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | Decision/blocker: plan is concrete, tests-only, host-only; no blocker | Next action: extract scope/tests/gates and spawn Executor
- 2026-05-10 01:58:43 CEST | Contract extracted | Scope: tighten GL-001 no-side-effects regression only in `go-mknoon/node/pubsub_test.go`; preserve unrelated dirty work; do not edit product code, source matrix, or breakdown | Commands required: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_FailsWithoutPubSub$')`; `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery')`; `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | Decision/blocker: no named gates required; no GL-001 known failure accepted | Next action: spawn Executor with model `gpt-5.5` and reasoning effort `xhigh`
- 2026-05-10 01:58:43 CEST | Executor spawn attempted | Spawn command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -a never` | Files allowed: `go-mknoon/node/pubsub_test.go`, this plan's `## Execution Progress` | Decision/blocker: child did not start because installed CLI requires approval options before the `exec` subcommand | Next action: retry Executor spawn with corrected CLI option order
- 2026-05-10 01:59:39 CEST | Executor spawned/running | Spawn command: `codex -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -a never exec` | Files allowed: `go-mknoon/node/pubsub_test.go`, this plan's `## Execution Progress` | Decision/blocker: retrying with corrected CLI option order; no code/test child work existed before retry | Next action: wait for Executor completion and inspect evidence
- 2026-05-10 02:00:42 CEST | Executor local pass running | Inspected: `implementation-execution-qa-orchestrator` skill, this GL-001 plan | Files allowed: `go-mknoon/node/pubsub_test.go`, this plan's `## Execution Progress` | Decision/blocker: contract confirms tests-only host-only GL-001 work; no blocker | Next action: inspect allowed owner/context files before editing the Go test
- 2026-05-10 02:01:24 CEST | Owner/context files inspected | Inspected: `git status --short`, `git diff -- go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `Test-Flight-Improv/test-gate-definitions.md` | Decision/blocker: unrelated dirty work exists; `go-mknoon/node/pubsub_test.go` has no pre-existing diff; production guard returns before group-state mutation; no product-code change needed | Next action: tighten `TestJoinGroupTopic_FailsWithoutPubSub`
- 2026-05-10 02:01:59 CEST | Owner test touched | Touched: `go-mknoon/node/pubsub_test.go` | Decision/blocker: `TestJoinGroupTopic_FailsWithoutPubSub` now owns GL-001, asserts exact `pubsub not initialized`, checks `n.pubsub` remains nil, and verifies no attempted-group entries in `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, or `groupDiscoveryCtx` under `n.mu.RLock()`; no blocker | Next action: format the touched Go test and run required commands
- 2026-05-10 02:02:20 CEST | Required command started | Command: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_FailsWithoutPubSub$')` | Decision/blocker: running fast direct GL-001 regression | Next action: record exact result
- 2026-05-10 02:02:46 CEST | Required command finished | Command: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_FailsWithoutPubSub$')` | Result: PASS, exit code 0, output `ok  	github.com/mknoon/go-mknoon/node	0.563s` | Decision/blocker: no blocker | Next action: run row-required Go direct command
- 2026-05-10 02:03:03 CEST | Required command started | Command: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery')` | Decision/blocker: running row-required Go direct command | Next action: record exact result
- 2026-05-10 02:03:26 CEST | Required command finished | Command: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery')` | Result: PASS, exit code 0, output `ok  	github.com/mknoon/go-mknoon/node	4.270s` | Decision/blocker: no blocker | Next action: run row-required Flutter host smoke
- 2026-05-10 02:03:40 CEST | Required command started | Command: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | Decision/blocker: running row-required Flutter host smoke | Next action: record exact result
- 2026-05-10 02:04:22 CEST | Required command finished | Command: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | Result: PASS, exit code 0, final output `00:00 +3: All tests passed!` | Decision/blocker: no blocker | Next action: inspect final diff/scope and record Executor completion
- 2026-05-10 02:04:44 CEST | Executor completed | Inspected: final `git diff -- go-mknoon/node/pubsub_test.go`, final `git status --short` | Touched: `go-mknoon/node/pubsub_test.go`, this plan's `## Execution Progress` | Decision/blocker: final diff is limited to GL-001 test assertions plus allowed progress entries; all required commands passed; no blocker | Next action: hand off to QA Reviewer
- 2026-05-10 02:05:23 CEST | QA Reviewer spawned/running | Spawn command: `codex -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -a never exec` | Scope to review: `go-mknoon/node/pubsub_test.go` and this plan's `## Execution Progress`; no code edits allowed | Decision/blocker: separate QA child starting after Executor completion; no blocker | Next action: wait for QA completion and inspect findings
- 2026-05-10 02:06:40 CEST | QA Reviewer started | Inspected: this GL-001 plan, `git status --short`, final `git diff -- go-mknoon/node/pubsub_test.go`, recorded required-command evidence | Decision/blocker: review in progress; no blocker identified yet | Next action: inspect test body and rerun required commands
- 2026-05-10 02:07:42 CEST | QA Reviewer completed | Inspected: `go-mknoon/node/pubsub_test.go` body/diff, relevant `git status --short`, recorded executor evidence, QA reruns of all required commands | QA rerun results: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_FailsWithoutPubSub$')` PASS exit 0 cached; `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery')` PASS exit 0 cached; `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` PASS exit 0, final output `00:00 +3: All tests passed!` | Decision/blocker: no blocking issues; QA accepted GL-001 | Next action: safe to close this session
- 2026-05-10 02:08:27 CEST | Final verdict written | Verdict: accepted | Files changed for GL-001: `go-mknoon/node/pubsub_test.go`, this plan's `## Execution Progress` | Decision/blocker: no blockers and no non-blocking follow-ups; spawned Executor and spawned QA completed sequentially | Next action: report closure verdict

## real scope
Own exactly source row `GL-001`: `JoinGroupTopic` must reject when `n.pubsub` has not been initialized and must not create topic, subscription, config, key, subscription context, validator, or discovery-loop state for the requested group.

This session is tests-only. The expected edit is to tighten the existing Go unit coverage in `go-mknoon/node/pubsub_test.go`, most likely `TestJoinGroupTopic_FailsWithoutPubSub`, so it proves both the clear error and the no-side-effects contract.

Out of scope: changing product behavior, Flutter rejoin/resume behavior, group discovery behavior, relay/device flows, source matrix rows other than `GL-001`, and breakdown ledger updates.

## closure bar
Good enough for GL-001 means:

- The Go unit regression explicitly names or otherwise clearly owns `GL-001`.
- Calling `JoinGroupTopic` on `NewNode()` without `Start` returns exactly `pubsub not initialized`.
- The regression proves no group-local state was created for the attempted group: `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, and `groupDiscoveryCtx` have no entry for that group.
- The regression avoids flaky goroutine counting. Absence of `groupSubCtx` and `groupDiscoveryCtx` entries is the stable proof that no managed subscription/discovery loop was started.
- The required host commands in this plan pass, or any failure is triaged as blocking before completion is claimed.

## source of truth
Authoritative inputs, in order when they disagree:

1. Current code and tests in `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, and `go-mknoon/node/pubsub_test.go`.
2. Source matrix row `GL-001` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
3. Ordered session entry for `GL-001` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
4. Named gate policy in `Test-Flight-Improv/test-gate-definitions.md`.

The active session contract is this plan once it reaches `Status: execution-ready`.

## session classification
`implementation-ready`

Subclassification: `needs_tests_only`, host-only.

## exact problem statement
The product path already rejects a join when PubSub is nil:

- `go-mknoon/node/pubsub.go` checks `if n.pubsub == nil` at the start of `JoinGroupTopic` and returns `pubsub not initialized`.
- `go-mknoon/node/node.go` initializes PubSub only through `Start` -> `initPubSub`.
- `go-mknoon/node/pubsub_test.go` has `TestJoinGroupTopic_FailsWithoutPubSub`, but that test currently asserts only that an error is returned and that the error string matches.

The missing reliability proof is that the rejected join leaves local group state untouched. A regression should catch future changes that accidentally allocate or store topic, subscription, config, key, cancel-context, or discovery-loop state before returning the nil-PubSub error.

User-visible behavior to preserve: startup/resume rejoin flows should continue to use normal initialized PubSub paths; this row only pins the lower-level Go guard for an unstarted node.

## owner files
Production owner files for context only:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`

Expected write file:

- `go-mknoon/node/pubsub_test.go`

Row test files considered:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`

Required direct commands are listed under `exact tests and gates to run`. `test/core/lifecycle/app_lifecycle_recovery_test.dart` is context only for this GL-001 tests-only plan unless execution touches resume code, which the scope guard forbids.

## files and repos to inspect next
Executor should inspect only:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub_test.go`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `git status --short`
- `git diff -- go-mknoon/node/pubsub_test.go`

Inspect Flutter owner files only if the direct Flutter smoke fails in a way that appears caused by this session; otherwise they are context only.

## existing tests covering this area
Current relevant coverage:

- `TestJoinGroupTopic_FailsWithoutPubSub` in `go-mknoon/node/pubsub_test.go` covers the nil-PubSub error string but not the absence of state mutation.
- `TestJoinGroupTopic_WithMultiMemberConfig` proves a successful join creates topic, subscription, config, key, and discovery context after `Start/initPubSub`.
- `TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish` proves cleanup after a successful join/leave.
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` covers Flutter startup rejoin command behavior using fake infrastructure.
- `test/core/lifecycle/app_lifecycle_recovery_test.dart` covers resume group-recovery orchestration, including `group:join` and `group:acknowledgeRecovery` command expectations.

Missing row-owned coverage: exact `GL-001` proof that the nil-PubSub join rejection leaves all group-topic local state absent.

## regression/tests to add first
Add or tighten one Go regression in `go-mknoon/node/pubsub_test.go` before any product-code consideration:

- Prefer extending `TestJoinGroupTopic_FailsWithoutPubSub` instead of adding a duplicate test.
- Use a stable `groupId`, call `JoinGroupTopic` on `NewNode()` without `Start`, and assert `err.Error() == "pubsub not initialized"`.
- Under `n.mu.RLock()`, assert no entry exists for that `groupId` in `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, or `groupDiscoveryCtx`.
- Assert `n.pubsub` remains nil. This is the stable proxy that no topic validator could have been registered.
- Do not count goroutines or sleep to infer discovery behavior.

If this tightened regression fails against current product code, stop and report the session as stale or no longer tests-only. Do not broaden into production fixes under this GL-001 tests-only plan.

## step-by-step implementation plan
1. Record `## Execution Progress` in this same plan file before editing, per `$implementation-execution-qa-orchestrator`.
2. Check `git status --short` and `git diff -- go-mknoon/node/pubsub_test.go` to avoid overwriting unrelated dirty work.
3. Inspect `TestJoinGroupTopic_FailsWithoutPubSub` and nearby `JoinGroupTopic` tests.
4. Tighten `TestJoinGroupTopic_FailsWithoutPubSub` with the no-side-effects assertions listed above. Keep the edit local to `go-mknoon/node/pubsub_test.go`.
5. Run the fast direct regression:

```bash
(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_FailsWithoutPubSub$')
```

6. Run the row-required Go direct command:

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery')
```

7. Run the row-required host Flutter smoke:

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

8. QA must review the diff, verify no product/test files outside GL-001 scope were modified, and confirm all required commands above have exact results recorded.

## risks and edge cases
- `NewNode()` intentionally does not initialize PubSub maps that `initPubSub` owns. The regression should treat no map entry as the required behavior; it may also assert maps remain nil where that is clear and stable.
- Validator registration is not directly inspectable when `n.pubsub` is nil. The regression should use `n.pubsub == nil` plus absence of topic state as the proof that registration was unreachable.
- Goroutine counts are noisy and should not be used. `groupSubCtx` and `groupDiscoveryCtx` absence is the deterministic proof that no managed loops were started.
- A dirty worktree is present. Execution must not revert, format, or "clean up" unrelated files.

## exact tests and gates to run
Fast direct regression:

```bash
(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_FailsWithoutPubSub$')
```

Required row Go command:

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery')
```

Required row Flutter host command:

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Named gates: none required for GL-001 because the planned change is a Go unit-test-only assertion and does not change Flutter production group behavior. Do not run device, relay, or real-network gates for this row.

## known-failure interpretation
No GL-001 known failure is accepted.

All commands listed under `exact tests and gates to run` must pass for acceptance. If a command fails, the Executor must triage it before any fix attempt as one of: caused by this session, pre-existing, flaky, unrelated-but-required, or environment/tooling-related. Because no pre-existing GL-001 exception is documented, an unresolved failure in any required command remains blocking.

## done criteria
- The GL-001 regression is present in `go-mknoon/node/pubsub_test.go`.
- The regression proves the nil-PubSub error and absence of topic/subscription/config/key/subscription-context/discovery-context state for the attempted group.
- No production files are changed.
- Source matrix and session breakdown files are not edited.
- Fast direct regression passes.
- Row-required Go direct command passes.
- Row-required Flutter host smoke passes.
- QA finds no blocking scope, test, or evidence gaps.

## scope guard
Do not:

- Modify `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, Dart production code, bridge code, lifecycle code, relay code, or device/integration fixtures under this tests-only plan.
- Add new feature behavior, retry behavior, discovery behavior, or recovery orchestration.
- Add broad sleeps, goroutine-count assertions, real relay/device proof, or new named-gate requirements.
- Edit `Private_group_chat_reliability_test_matrix_COMPLETE_1.md` or the session breakdown.
- Address any row other than `GL-001`.

If execution evidence shows product code must change, stop and return `blocked` with recommended replan focus instead of widening this session.

## accepted differences / intentionally out of scope
- Flutter startup/rejoin and resume recovery tests are supporting host smoke evidence, not the primary GL-001 regression.
- Device-backed, relay-backed, and real-network behavior are intentionally out of scope.
- A direct validator-registration assertion is intentionally out of scope because nil PubSub makes validator registration unreachable; `n.pubsub == nil` and no topic state are the correct stable proof.
- Broader group lifecycle rows for successful join, leave, config updates, key updates, stop cleanup, and recovery are intentionally left to their own rows.

## dependency impact
GL-001 protects later group lifecycle and resume-rejoin work from accidentally letting an uninitialized Go node create partial local PubSub state. If this plan changes from tests-only to product-code work, downstream rows that assume the current guard semantics should be revisited before execution.

## dirty-worktree note
At planning time, `git status --short` showed many unrelated modified and untracked files, including untracked source matrix and breakdown artifacts plus unrelated group reliability work. This planning step created only this plan file. Executor and QA must preserve unrelated dirty work and must not revert or format files outside the GL-001 write scope.

## execution instructions for $implementation-execution-qa-orchestrator
- Treat this file as the execution contract.
- Use strict Executor then QA sequencing.
- Maintain compact `## Execution Progress` entries in this same file.
- Executor write scope is `go-mknoon/node/pubsub_test.go` only.
- QA should inspect the final diff and exact command output for the three required commands.
- Final verdict may be `accepted` only when the done criteria and required command evidence are complete.

## reviewer sufficiency pass
Reviewer verdict: sufficient as-is after the context-only lifecycle-test clarification now included above.

Answers:

- Missing files, regressions, or gates: none for GL-001. The required regression is the no-side-effects assertion in `go-mknoon/node/pubsub_test.go`; the required commands are explicit.
- Stale assumptions: none found. Current code has the nil-PubSub guard before any join state mutation.
- Overengineering: none. The plan avoids goroutine counting, device proof, relay proof, named gates, and product-code changes.
- Decomposition sufficiency: sufficient. The implementation surface is one existing Go test, with stop rules if evidence disproves tests-only scope.
- Minimum needed for safe execution: add/tighten the GL-001 Go regression and run the three required host commands.

## arbiter decision
Structural blockers remaining: none.

Incremental details intentionally deferred:

- Running `test/core/lifecycle/app_lifecycle_recovery_test.dart` directly is deferred because GL-001 does not touch resume code and the row-required command list does not require it.

Accepted differences intentionally left unchanged:

- No device, relay, real-network, or named-gate proof is required for this host-only tests-only row.
- Direct validator introspection is intentionally not required because `n.pubsub == nil` makes validator registration unreachable.
