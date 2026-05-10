# GL-018 Restart Rejoin Recovery Plan

Status: execution-ready

## Current Row

`GL-018 | Restart followed by app rejoin restores all groups from persisted app state | Node stopped/restarted after having groups A/B/C. | 1. Restart node. 2. Rejoin persisted groups with config/key. 3. Send messages in each group. | Every group rejoins exactly once with current config/key and can receive; no group is silently missing after restart. | P0 | Open | Recommended | Required | Required | Recommended | Required | Covers the app-layer recovery contract missing from Go runtime state.`

## Planning Progress

- 2026-05-10 07:46:30 CEST - Evidence Collector completed. Files inspected since last update: GL-018/GL-017/GL-016/GL-019 source rows and breakdown entries, `rejoin_group_topics_use_case.dart`, `handle_app_resumed.dart`, `startup_router.dart`, `rejoin_group_topics_use_case_test.dart`, `group_startup_rejoin_smoke_test.dart`, `group_messaging_smoke_test.dart`, `group_resume_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `C4-05-Recovery-And-Reliability.md`, `pubsub.go`, `node.go`, `pubsub_test.go`, `pubsub_delivery_test.go`, `test-gate-definitions.md`, and `scripts/run_test_gates.sh`. Decision/blocker: existing tests cover adjacent pieces but not the exact A/B/C persisted restart rejoin contract; row-owned regression is required. Next action: draft implementation-ready plan with regression-first stop point.
- 2026-05-10 07:46:30 CEST - Planner started. Files inspected since last update: none. Decision/blocker: plan will stay host-only unless the direct host regression cannot prove fake-network delivery after app-layer rejoin. Next action: write exact scope, owner files, tests, gates, dirty-worktree guard, and closure instructions.
- 2026-05-10 07:47:34 CEST - Planner completed. Files inspected since last update: none. Decision/blocker: draft plan classifies GL-018 as implementation-ready with required row-owned host regression; production code changes are conditional on that regression failing for app-layer reasons. Next action: run Reviewer pass for sufficiency, stale assumptions, and scope drift.
- 2026-05-10 07:49:52 CEST - Reviewer started/completed. Files inspected since last update: current plan draft and `group_config_payload.dart`. Decision/blocker: plan is sufficient with adjustments; add `group_config_payload.dart` as conditional owner and require one multi-member/current-config payload proof instead of optional Charlie coverage. Next action: run Arbiter pass and decide whether adjustments remove all structural blockers.
- 2026-05-10 07:50:29 CEST - Arbiter started/completed. Files inspected since last update: current reviewer-pass plan. Decision/blocker: no structural blockers remain after reviewer adjustments; incremental details are documented as deferred and accepted differences are scoped. Next action: execute the plan regression-first in a separate implementation pass.

## Execution Progress

- 2026-05-10 07:52:11 CEST - Execution started. Files inspected or touched: `git status --short`, current GL-018 plan. Command/result: `git status --short` showed:

  ```text
   M Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md
   M Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-copy-and-actions-plan.md
   M Test-Flight-Improv/Group-Chat-Feature/test-inventory.md
   M Test-Flight-Improv/test-gate-definitions.md
   M go-mknoon/node/node.go
   M go-mknoon/node/pubsub.go
   M go-mknoon/node/pubsub_decryption_failure_test.go
   M go-mknoon/node/pubsub_delivery_test.go
   M go-mknoon/node/pubsub_key_rotation_grace_test.go
   M go-mknoon/node/pubsub_test.go
   M go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go
   M info.plist
   M integration_test/group_invite_status_matrix_harness.dart
   M lib/features/groups/application/drain_group_offline_inbox_use_case.dart
   M lib/features/groups/application/group_key_update_listener.dart
   M lib/features/groups/application/group_pending_key_repair_service.dart
   M lib/features/groups/presentation/screens/group_info_screen.dart
   M lib/features/groups/presentation/screens/group_info_wired.dart
   M lib/features/groups/presentation/widgets/group_member_row.dart
   M test/features/groups/application/create_group_with_members_use_case_test.dart
   M test/features/groups/application/drain_followup_invariants_test.dart
   M test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
   M test/features/groups/application/group_key_update_listener_test.dart
   M test/features/groups/presentation/group_info_screen_test.dart
   M test/features/groups/presentation/group_info_wired_test.dart
  ?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-001-plan.md
  ?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-002-plan.md
  ?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-003-plan.md
  ?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-004-plan.md
  ?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-005-plan.md
  ?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md
  ?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-001-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-002-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-003-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-004-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-005-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-006-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-007-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-008-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-009-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-011-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-012-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-013-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-014-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-015-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-017-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-018-plan.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md
  ?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md
  ?? lib/features/groups/presentation/group_invite_status_presentation.dart
  ```

  Decision/blocker: worktree is dirty before GL-018 execution; preserve all unrelated edits. Next action: extract execution contract and inspect owner files before adding the regression.

- 2026-05-10 07:54:20 CEST - Contract extracted. Files inspected or touched: current GL-018 plan. Command/result: no command. Decision/blocker: scope is GL-018 only; add a row-owned host regression in `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` first, proving persisted groups A/B/C emit exactly one current `group:join` each and receive post-rejoin messages; production edits are allowed only if that regression fails for a real app-layer issue in the named owner files. Required checks remain the exact `--plain-name` direct test, adjacent Flutter checks, `./scripts/run_test_gates.sh groups`, and `git diff --check`. Next action: spawn Executor to inspect owner files, add the regression, and run required checks.

- 2026-05-10 07:54:48 CEST - Executor spawned/running. Files inspected or touched: current GL-018 plan. Command currently running: `codex exec` with `model: gpt-5.5` and `reasoning_effort: xhigh`. Decision/blocker: Executor must add the GL-018 regression first and stop as tests-only if it passes without production edits. Next action: wait for Executor result.

- 2026-05-10 07:55:26 CEST - Executor spawn retry. Files inspected or touched: current GL-018 plan. Command/result: first `codex exec` invocation exited before materializing because this CLI build rejected the `-a` subcommand flag. Decision/blocker: no child work or file edits occurred from that attempt; retry with config overrides for approval policy and sandbox. Next action: spawn Executor again and wait for result.

- 2026-05-10 07:54:39 CEST - Executor owner inspection started. Files inspected or touched: current GL-018 plan, `git status --short`, `flutter-test-orchestrator` skill. Command/result: `git status --short` confirmed the pre-existing dirty worktree listed above; no source/test implementation files touched yet. Decision/blocker: proceed with GL-018 only and preserve unrelated changes. Next action: inspect owner files and adjacent suites before adding the regression.

- 2026-05-10 07:56:05 CEST - Executor owner inspection completed. Files inspected or touched: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `lib/features/identity/presentation/startup_router.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/app_lifecycle_recovery_test.dart`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`. Command/result: file reads only. Decision/blocker: existing app-layer code already iterates persisted groups and existing receive-after-rejoin coverage is single-group, so add only the row-owned GL-018 regression first. Next action: implement the test in `group_startup_rejoin_smoke_test.dart`.

- 2026-05-10 07:56:47 CEST - Executor implementation started. Files inspected or touched: `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, current GL-018 plan. Command/result: no test command yet. Decision/blocker: add the required regression only; production edits remain conditional on a real failing app-layer issue. Next action: patch the startup rejoin smoke test.

- 2026-05-10 07:58:18 CEST - Executor implementation completed. Files inspected or touched: `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, current GL-018 plan. Command/result: `dart format test/features/groups/integration/group_startup_rejoin_smoke_test.dart` passed and formatted the touched test file. Decision/blocker: GL-018 regression added; no production files changed. Next action: run the exact direct GL-018 test.

- 2026-05-10 07:58:31 CEST - Direct GL-018 test started. Files inspected or touched: current GL-018 plan. Command running: `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018 restart rejoin restores all persisted groups exactly once and resumes delivery'`. Decision/blocker: none. Next action: record result.

- 2026-05-10 07:58:54 CEST - Direct GL-018 test completed. Files inspected or touched: current GL-018 plan. Command/result: `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018 restart rejoin restores all persisted groups exactly once and resumes delivery'` passed (`00:00 +1: All tests passed!`). Decision/blocker: regression passed without production changes; keep session tests-only. Next action: run the full startup rejoin smoke suite.

- 2026-05-10 07:59:05 CEST - Full startup rejoin smoke suite started. Files inspected or touched: current GL-018 plan. Command running: `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart`. Decision/blocker: none. Next action: record result.

- 2026-05-10 07:59:22 CEST - Full startup rejoin smoke suite completed. Files inspected or touched: current GL-018 plan. Command/result: `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart` passed (`00:00 +4: All tests passed!`). Decision/blocker: none. Next action: run `rejoin_group_topics_use_case_test.dart`.

- 2026-05-10 07:59:31 CEST - Rejoin group topics application suite started. Files inspected or touched: current GL-018 plan. Command running: `flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart`. Decision/blocker: none. Next action: record result.

- 2026-05-10 07:59:46 CEST - Rejoin group topics application suite completed. Files inspected or touched: current GL-018 plan. Command/result: `flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart` passed (`00:00 +18: All tests passed!`). Decision/blocker: none. Next action: run the post-restart group messaging plain-name check.

- 2026-05-10 07:59:56 CEST - Group messaging restart plain-name check started. Files inspected or touched: current GL-018 plan. Command running: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'message is received after app restart with rejoin'`. Decision/blocker: none. Next action: record result.

- 2026-05-10 08:00:11 CEST - Group messaging restart plain-name check completed. Files inspected or touched: current GL-018 plan. Command/result: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'message is received after app restart with rejoin'` passed (`00:00 +1: All tests passed!`). Decision/blocker: none. Next action: run the watchdog restart plain-name check.

- 2026-05-10 08:00:20 CEST - Watchdog restart plain-name check started. Files inspected or touched: current GL-018 plan. Command running: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and receives subsequent live messages'`. Decision/blocker: none. Next action: record result.

- 2026-05-10 08:00:41 CEST - Watchdog restart plain-name check completed. Files inspected or touched: current GL-018 plan. Command/result: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and receives subsequent live messages'` passed (`00:00 +1: All tests passed!`). Decision/blocker: none. Next action: run the lifecycle recovery plain-name check.

- 2026-05-10 08:00:52 CEST - Lifecycle recovery plain-name check started. Files inspected or touched: current GL-018 plan. Command running: `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'rejoins and acknowledges when Go signals group recovery'`. Decision/blocker: none. Next action: record result.

- 2026-05-10 08:01:09 CEST - Lifecycle recovery plain-name check completed. Files inspected or touched: current GL-018 plan. Command/result: `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'rejoins and acknowledges when Go signals group recovery'` passed (`00:00 +1: All tests passed!`). Decision/blocker: none. Next action: run `./scripts/run_test_gates.sh groups`.

- 2026-05-10 08:01:19 CEST - Group Messaging Gate started. Files inspected or touched: current GL-018 plan. Command running: `./scripts/run_test_gates.sh groups`. Decision/blocker: none. Next action: record result.

- 2026-05-10 08:01:48 CEST - Group Messaging Gate completed. Files inspected or touched: current GL-018 plan. Command/result: `./scripts/run_test_gates.sh groups` passed (`00:05 +104: All tests passed!`). Decision/blocker: none. Next action: run `git diff --check`.

- 2026-05-10 08:01:57 CEST - Diff whitespace check started. Files inspected or touched: current GL-018 plan. Command running: `git diff --check`. Decision/blocker: none. Next action: record result.

- 2026-05-10 08:02:23 CEST - Diff whitespace check completed. Files inspected or touched: current GL-018 plan, `git status --short`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`. Command/result: `git diff --check` passed with no output. Decision/blocker: worktree still contains the pre-existing unrelated dirty files plus this session's test file and plan updates; no Go checks were run because no Go files were touched for GL-018 and no direct failure pointed into Go runtime behavior. Next action: record executor verdict.

- 2026-05-10 08:02:23 CEST - Executor verdict started. Files inspected or touched: current GL-018 plan, `git status --short`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`. Command/result: no command. Decision/blocker: all required Flutter checks and the groups gate passed; production code unchanged. Next action: mark GL-018 executor result ready for QA.

- 2026-05-10 08:02:23 CEST - Executor verdict completed. Files inspected or touched: current GL-018 plan. Command/result: no command. Decision/blocker: GL-018 closes as tests-only evidence in this executor pass; production changed: no; blockers: none; ready for QA: yes. Next action: hand off compact Executor result.

- 2026-05-10 08:04:12 CEST - QA Reviewer spawned/running. Files inspected or touched: current GL-018 plan. Command currently running: `codex exec` with `model: gpt-5.5` and `reasoning_effort: xhigh`. Decision/blocker: QA must inspect landed GL-018 diff and execution evidence, then return pass/fail with blocking findings only. Next action: wait for QA Reviewer result.

- 2026-05-10 08:05:10 CEST - QA Reviewer inspection started. Files inspected or touched: current GL-018 plan, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/shared/fakes/group_test_user.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `test/core/bridge/fake_bridge.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `git status --short`, `git diff --stat`, `git diff --name-only`, `git diff -- test/features/groups/integration/group_startup_rejoin_smoke_test.dart`. Command/result: file/diff reads confirmed the GL-018 landed test adds groups A/B/C, clears bridge history, calls startup rejoin once, asserts exactly one `group:join` payload per group with current key/epoch/config/member public keys, then resubscribes and verifies post-rejoin incoming message storage in each group. Decision/blocker: no blocking gap found in the regression shape; ambient production-code dirty files were already present in the plan's initial status and were not GL-018-owned changes. Next action: run lightweight QA verification commands.

- 2026-05-10 08:05:33 CEST - QA Reviewer lightweight verification completed. Files inspected or touched: current GL-018 plan, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`. Command/result: `git diff --check` passed with no output; `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018 restart rejoin restores all persisted groups exactly once and resumes delivery'` passed (`00:00 +1: All tests passed!`). Decision/blocker: no full gate rerun needed because Executor evidence already records the exact direct test, adjacent checks, `./scripts/run_test_gates.sh groups`, and `git diff --check` as passed, and the QA direct rerun is green. Next action: write QA verdict.

- 2026-05-10 08:05:33 CEST - QA Reviewer verdict completed. Files inspected or touched: current GL-018 plan. Command/result: no command. Decision/blocker: QA verdict pass; blocking findings: none; non-blocking observations: the worktree remains dirty with unrelated pre-existing production/test/doc edits, but GL-018 is tests-only and does not require production changes. GL-018 can be marked `Covered` by the separate closure workflow. Next action: return compact QA result.

- 2026-05-10 08:06:24 CEST - Final execution verdict written. Files inspected or touched: current GL-018 plan. Command/result: no command. Decision/blocker: GL-018 execution+QA accepted as tests-only; production changed: no; blockers: none; closure can mark GL-018 `Covered` using the row-owned regression and recorded green gates. Next action: final controller hygiene/status check and user handoff.

## Final verdict

Execution-ready.

GL-018 requires a row-owned host regression and is not acceptance-only or already-covered. The final plan is safe to execute regression-first: add the exact A/B/C restart rejoin proof, then make production changes only if that regression exposes a missing, duplicate, or stale app-layer rejoin path.

## Final plan

Use the sections below as the implementation contract. The executor should start at `files and repos to inspect next`, add `regression/tests to add first`, and stop at the tests-only closure point if the row-owned regression passes without production changes.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- A simulator/device proof is not required unless implementation unexpectedly touches real transport, real relay, or simulator-bound startup behavior.
- A new test file is not required; the regression belongs in the existing group gate file, so completeness-check is only conditional.
- Full Go package/race sweeps are conditional on Go edits or direct evidence that Go explicit rejoin behavior is failing.

## Accepted differences intentionally left unchanged

- GL-018 stays host-only because the row targets persisted app state rejoining group topics, not real relay drain or simulator lifecycle.
- GL-017 remains the Go runtime-state clearing proof.
- GL-019 concurrent join/leave/update stress and GL-016 key clone behavior remain separate rows.

## real scope

Own exactly GL-018: after the Go node has been stopped/restarted and runtime group topic state is gone, the Flutter/app recovery path must restore all persisted eligible groups A/B/C from local app state by issuing one current `group:join` command per group, then live group delivery must work for every group after the rejoin.

This session may touch only these execution owner files:

- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` for the row-owned host regression.
- `lib/features/groups/application/rejoin_group_topics_use_case.dart` only if the row-owned regression fails because `rejoinGroupTopics()` skips an eligible persisted group, uses stale key/config payload, or emits duplicate joins.
- `lib/features/groups/application/group_config_payload.dart` only if the row-owned regression proves current persisted config is read but serialized incorrectly into the `group:join` payload.
- `lib/core/lifecycle/handle_app_resumed.dart` only if the failure is specifically in resume/watchdog reason routing or acknowledgement around app-layer rejoin.
- `lib/features/identity/presentation/startup_router.dart` only if the failure is specifically in startup-triggered rejoin orchestration after `startP2PNode()` succeeds.
- `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, and `go-mknoon/node/pubsub_delivery_test.go` only if a direct Go failure proves `JoinGroupTopic`/publish behavior cannot support explicit post-restart app rejoin. GL-017 currently makes this unlikely.

Do not edit source matrix, breakdown, closure docs, unrelated tests, presentation UI, invite/key-clone logic, or concurrent mutation behavior during implementation. Closure docs are handled only after implementation evidence exists.

## closure bar

GL-018 is closeable only when a row-owned regression proves all of the following in one restart/rejoin scenario:

- Three persisted eligible groups A/B/C are present before simulated app/node restart.
- The restarted member is unsubscribed from all three fake pubsub topics to represent lost Go runtime topic state.
- `rejoinGroupTopics(reason: RejoinReason.startup)` or the equivalent startup app path emits exactly three `group:join` commands after bridge command history is cleared.
- Each group id appears exactly once; no group is missing and no duplicate join is accepted as closure proof.
- Every join payload carries the current persisted group key and key epoch for that group.
- Every join payload carries the current persisted group config, including expected group id/name/type/member public-key data needed by the Go validator.
- After fake-network resubscribe that stands in for Go topic subscription, one post-rejoin live message sent in each group is received and stored by the restarted member.

If the row-owned regression passes before any production edit, implementation may close as tests-only despite the breakdown's original `needs_code_and_tests` disposition, because the source row was still Open and the session added exact row-owned coverage. If it fails, make the smallest code change required to satisfy the same regression.

## source of truth

Authoritative sources for this session:

- Source row GL-018 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
- Breakdown GL-018 entry in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current code and tests in the owner files listed above.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`; if they disagree, the script wins.

Conflict rule: current code/tests beat stale prose; the source row remains Open until row-owned evidence exists; GL-017 closure evidence is accepted only for Go runtime clearing and explicit rejoin support, not for app-layer persisted recovery.

## session classification

`implementation-ready`

This is not acceptance-only and not already-covered. Existing tests prove adjacent behaviors but not the exact GL-018 row. The execution posture is code-and-tests with regression-first implementation: add the exact row-owned regression first, then code only if the regression fails for a real app-layer reason.

## exact problem statement

GL-017 proves `Node.Stop()` clears runtime group topic/config/key/subscription state and that Go publish fails until an explicit rejoin rebuilds state. GL-018 owns the next layer up: after app restart, persisted group state must drive explicit rejoin for every eligible local group.

Current evidence shows `rejoinGroupTopics()` iterates `groupRepo.getAllGroups()`, skips dissolved/no-key groups, builds `groupConfig`, and calls `group:join`; `StartupRouter._doStartP2P()` invokes it after successful node start; `handleAppResumed()` invokes it after resume/watchdog recovery. The remaining risk is that no single row-owned test proves the A/B/C restart contract end to end: exactly once per persisted group, current key/config payload, and live receive recovery in every group without silent omission.

User-visible behavior that must improve: after cold restart or watchdog restart, a user who belongs to groups A/B/C must not silently miss live messages in one of those groups because the app failed to rejoin that topic.

Behavior that must stay unchanged: dissolved groups remain skipped, groups without key material remain skipped, individual join errors must not stop later groups from being attempted, and GL-017's Go runtime clearing contract must remain true.

## files and repos to inspect next

Before implementation, re-read these exact files because the worktree is dirty and parallel edits exist:

- `git status --short`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

Covered adjacent behavior:

- `test/features/groups/application/rejoin_group_topics_use_case_test.dart` has startup/watchdog/in-place tests that verify multiple persisted groups cause multiple `group:join` commands, no-key groups are skipped, errors do not stop later attempts, archived groups rejoin, and dissolved groups skip.
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` proves a single simulated restarted member can rejoin one group with the expected key/config and then receive live messages after fake-network resubscribe.
- `test/features/groups/integration/group_messaging_smoke_test.dart` has a single-group app restart with rejoin and post-restart receive proof.
- `test/features/groups/integration/group_resume_recovery_test.dart` has single-group watchdog rejoin/live receive and broader resume/drain scenarios.
- `integration_test/group_recovery_e2e_test.dart` has simulator/nightly adjacent watchdog and multi-group drain evidence, but it is not the row-owned GL-018 closure test.
- `go-mknoon/node/pubsub_test.go::TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart` proves Go runtime clears group state after stop and supports explicit rejoin/publish after restart.

Missing exact GL-018 coverage:

- No row-owned test combines groups A/B/C in one simulated restart and asserts exactly one current `group:join` per group.
- No row-owned test asserts current key/config payload for each of A/B/C and then proves post-rejoin live delivery in every group.
- Existing multi-group command-count tests do not prove receive after restart; existing receive-after-restart tests are single-group.

## regression/tests to add first

Add a focused GL-018 regression to `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`.

Suggested test name:

`GL-018 restart rejoin restores all persisted groups exactly once and resumes delivery`

Required shape:

- Create `alice`, `bob`, and `charlie` with `GroupTestUser` and a shared `FakeGroupPubSubNetwork`.
- Create three groups, for example `gl018-group-a`, `gl018-group-b`, and `gl018-group-c`, where Bob is a persisted member of each.
- Make at least one group contain all three members so the current config proof is not just a two-member happy path.
- Persist distinct current keys for Bob for every group, for example `gl018-key-a` epoch 11, `gl018-key-b` epoch 22, and `gl018-key-c` epoch 33.
- Start Alice and Bob listeners.
- Send a pre-restart message in each group and verify Bob receives one incoming message per group, proving the setup is live before restart.
- Simulate Bob's restarted Go node by unsubscribing Bob from all three fake-network topics.
- Clear Bob bridge command history, then call `rejoinGroupTopics(bridge: bob.bridge, groupRepo: bob.groupRepo, reason: RejoinReason.startup)`.
- Decode only `group:join` commands and assert total length is exactly three, grouped by payload `groupId`, with count exactly one for each of A/B/C.
- Assert each payload's `groupKey`, `keyEpoch`, and `groupConfig` match the current persisted state for that group. At minimum assert group name/type and member public keys for Alice/Bob in every group and Charlie in the three-member group.
- Fake-network subscribe Bob back to each group to model Go topic subscription after successful join.
- Send one post-rejoin message in each group from Alice and verify Bob receives/stores that group's post-rejoin text exactly once.

This regression should be red before code only if the current app-layer recovery path is actually missing, stale, or duplicative. If it passes immediately, keep the test as the GL-018 row-owned proof and do not invent production changes.

## step-by-step implementation plan

1. Re-read the files listed in `files and repos to inspect next`; note any parallel changes in the owner files and avoid reverting them.
2. Add the GL-018 regression in `group_startup_rejoin_smoke_test.dart` using existing fake-network and `GroupTestUser` patterns.
3. Run the direct GL-018 test by exact `--plain-name`.
4. If the test passes without production changes, stop implementation and treat GL-018 as tests-only closure.
5. If the test fails because a persisted group is missing, inspect `rejoinGroupTopics()` and the fake repository ordering/state. Fix only the iteration/filtering issue needed to include all eligible persisted groups.
6. If the test fails because a join is duplicated, fix only the duplicate trigger that belongs to this path. Prefer eliminating duplicate caller invocation if the duplicate is orchestration-driven; add local de-duplication in `rejoinGroupTopics()` only if persisted duplicates are the concrete cause.
7. If the test fails because key/config payloads are stale, fix only the persisted current-state read or payload construction path in `rejoinGroupTopics()`/`buildGroupConfigPayload()`. Do not change key rotation semantics; GL-016 and key-clone behavior stay out of scope.
8. If the test fails only because fake-network resubscribe is not automatic, keep that manual resubscribe in the test with an explicit comment; production Go performs topic subscription through `group:join`.
9. If a failure points into Go `JoinGroupTopic` or publish-after-rejoin behavior, first rerun the GL-017 Go regression. Touch Go files only after a direct Go reproduction confirms the problem is not already covered by GL-017.
10. Re-run the direct and gate commands listed below. Do not update source matrix/breakdown until direct row evidence and required gates are green or documented with a known pre-existing failure.

## likely code/test changes

Likely test change:

- Add one row-owned test in `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`.

Conditional production changes:

- `lib/features/groups/application/rejoin_group_topics_use_case.dart`: only if the row-owned test exposes missing, duplicate, or stale `group:join` behavior from persisted app state.
- `lib/features/groups/application/group_config_payload.dart`: only if current persisted group/member state is correct but serialized incorrectly for `group:join`.
- `lib/core/lifecycle/handle_app_resumed.dart` or `lib/features/identity/presentation/startup_router.dart`: only if the direct evidence shows the wrong recovery entry point is calling or skipping rejoin.
- Go node files: not expected; only allowed if a focused Go reproduction disproves GL-017's explicit rejoin support.

## risks and edge cases

- `groupRepo.getAllGroups()` may include archived groups and should continue to rejoin them; dissolved groups must remain skipped.
- Missing key material must continue to skip a group; GL-018's A/B/C setup must persist keys for all groups so no-key skip behavior is not confused with missing recovery.
- Join error handling must continue attempting later groups and counting errors; GL-018's happy-path proof should not weaken that behavior.
- Fake-network resubscribe is a test harness stand-in for Go topic subscription after `group:join`; do not mistake it for production code responsibility.
- Dirty worktree changes in `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, and related tests may belong to other sessions; do not overwrite or normalize them while implementing GL-018.
- App startup uses `unawaited(runWithGroupRecoveryGate(...))`; this plan does not require changing startup blocking/UX behavior unless the direct regression proves a startup call is missing.

## exact tests and gates to run

Minimum direct regression:

```bash
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018 restart rejoin restores all persisted groups exactly once and resumes delivery'
```

Adjacent direct Flutter checks:

```bash
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'message is received after app restart with rejoin'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and receives subsequent live messages'
flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'rejoins and acknowledges when Go signals group recovery'
```

Named gate required for group send/receive/recovery behavior:

```bash
./scripts/run_test_gates.sh groups
```

Go checks only if Go files are touched or a direct failure points into Go runtime rejoin/publish behavior:

```bash
(cd go-mknoon && go test ./node -run '^TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart$|JoinGroupTopic|PublishGroupMessage_ReturnsErrorForUnjoinedGroup|GroupRecovery' -count=1)
(cd go-mknoon && go test -race ./node -run '^TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart$|JoinGroupTopic|PublishGroupMessage_ReturnsErrorForUnjoinedGroup|GroupRecovery' -count=1)
```

Hygiene:

```bash
git diff --check
```

Run `./scripts/run_test_gates.sh completeness-check` only if a new test file is added or gate classification changes. This plan prefers adding the regression to an existing classified group gate file, so completeness-check is not required by default.

## known-failure interpretation

No current GL-018-specific known failure is accepted. The direct GL-018 regression must pass before closure.

If a broad gate fails in an unrelated dirty-worktree area, capture:

- the failing command,
- the failing test names,
- whether the same failure reproduces without GL-018 changes or is already present in files not touched by GL-018,
- the direct GL-018 regression result.

Do not mark GL-018 covered if the direct row regression is red. Do not use unrelated pre-existing failures to avoid running the direct regression.

## done criteria

- A row-owned GL-018 test exists and passes.
- The test proves exactly one current `group:join` for each persisted group A/B/C.
- The test proves post-rejoin receive/storage in every group.
- Any production changes are limited to the owner files and are justified by the row-owned regression failure.
- Required direct tests and the `groups` gate pass, or any non-GL-018 failure is documented as pre-existing with evidence.
- `git diff --check` passes.
- No GL-019 concurrent stress or GL-016 key clone behavior is changed or claimed.

## scope guard

Non-goals:

- Do not implement GL-019 concurrent join/leave/update stress.
- Do not implement GL-016 `GetGroupKeyInfo` clone behavior.
- Do not change key rotation, key repair, invite, announcement, media, notification, or retry policies.
- Do not change Go `Stop()` semantics beyond direct evidence; GL-017 already owns runtime clearing.
- Do not widen named gate definitions or add device-only requirements for a host-provable app-layer contract.
- Do not edit source matrix, breakdown, or closure docs during implementation; closure happens after accepted evidence.

Overengineering triggers:

- Adding a new recovery coordinator, persistent recovery queue, retry scheduler, or device/relay harness for this row without direct failure evidence.
- Changing all startup/resume ordering when the direct gap is a missing or stale group join payload.
- Adding broad de-duplication across unrelated recovery callers without a concrete duplicate reproduction in GL-018.

Dirty-worktree guard:

- Start execution with `git status --short`.
- Re-read any file before editing it.
- Preserve unrelated changes in modified Go/Dart/test/docs files.
- Do not run destructive git commands.
- If an owner file has parallel edits in the exact block needed for GL-018, adapt locally and keep the diff limited; ask only if the conflict makes the GL-018 regression impossible to add.

## accepted differences / intentionally out of scope

- Device/simulator proof is intentionally out of scope because the direct contract is app-layer persisted state -> bridge join payload -> fake pubsub receive proof, and existing group gate infrastructure classifies `group_startup_rejoin_smoke_test.dart` as the host group-topic rejoin suite.
- Real relay/inbox drain is intentionally out of scope for GL-018. Adjacent drain coverage lives in resume recovery and `integration_test/group_recovery_e2e_test.dart`; GL-018 is about live topic rejoin restoration after restart.
- GL-017 remains the Go runtime clearing proof; GL-018 should not duplicate all GL-017 runtime map assertions.

## dependency impact

Closing GL-018 provides the app-layer recovery proof that GL-017 explicitly left open. Later lifecycle/reliability rows can rely on persisted group topics being rejoined after restart before testing more complex stress conditions.

If the GL-018 regression reveals a real production issue, do not advance GL-019 until the missing/duplicate/stale app-layer rejoin behavior is fixed and covered. If the regression passes without production code, later rows should treat persisted restart rejoin as covered by the row-owned test and focus only on their separate concurrency/key semantics.

## Device/Relay Proof Profile

Host-only.

This plan does not rely on device, simulator, real-network, or `integration_test` evidence for closure. The row's core contract is app-layer persisted group state driving bridge `group:join` commands after runtime topic state is lost, plus fake-network live receive after rejoin. Existing host fakes already isolate that contract:

- `FakeBridge` captures exact bridge commands and payloads.
- `FakeGroupPubSubNetwork` simulates topic unsubscribe/resubscribe and live fan-out.
- `GroupTestUser` composes persisted group state, listeners, and fake delivery.

`integration_test/group_recovery_e2e_test.dart` was inspected as adjacent/nightly recovery evidence only. It is not required unless implementation unexpectedly touches simulator-bound startup/transport or real relay behavior.

## closure instructions

After implementation and verification, run the closure workflow separately. Do not update these files during execution before evidence exists:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`

Closure should record:

- GL-018 source row status changed from `Open` to `Covered`.
- The exact row-owned test name and file.
- Whether the accepted implementation was tests-only or included production changes.
- Exact direct/gate command results.
- Explicit note that GL-019 concurrent stress and GL-016 key clone behavior remain separate unresolved rows.

## Reviewer findings

- Sufficiency: sufficient with adjustments.
- Missing files/tests/gates: the draft needed `lib/features/groups/application/group_config_payload.dart` as a conditional owner because `rejoinGroupTopics()` delegates payload construction there; no additional named gate is required when the regression is added to the existing group gate file.
- Stale or incorrect assumptions: treating the third member as optional weakened the "current config" proof; the plan now requires a three-member group so payload membership can be checked concretely.
- Overengineering: none after keeping production edits conditional on the row-owned regression.
- Decomposition: sufficient. The executor can add one focused regression first and stop if it passes.
- Minimum needed: keep the row-owned regression host-only, assert exact join counts/payloads, and run the listed direct tests plus `./scripts/run_test_gates.sh groups`.

## Arbiter decision

- Structural blockers: none.
- Incremental details: direct simulator/nightly proof, completeness-check, and Go race sweeps are intentionally conditional rather than required for the base host-only plan.
- Accepted differences: host-only proof, no real relay drain, no GL-017 runtime-map duplication, and no GL-016/GL-019 scope are intentionally left unchanged.
- Final classification: `execution-ready`.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/C4-05-Recovery-And-Reliability.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`

## Why the plan is safe or unsafe to implement now

Safe to implement now because the reviewer adjustment was applied, the arbiter found no structural blockers, the plan is regression-first, production edits are conditional on concrete row evidence, the dirty-worktree guard is explicit, and the new row-owned proof belongs in an already classified host group gate file.
