# GL-019 Concurrent Group Join/Leave/Update Race Plan

Status: execution-ready

## Current Row

`GL-019 | Concurrent join/leave/update for same group is race-free | G is being rapidly mutated by app recovery and user actions. | 1. Run join, leave, UpdateGroupConfig, UpdateGroupKey concurrently. 2. Run under race detector. 3. Assert final state. | No data race, panic, leaked goroutine, or impossible final map state occurs. | P0 | Open | Required | Required | N/A | Recommended | N/A | Targets symptoms that appear only under add/remove/re-add stress.`

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision / blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 08:16:37 CEST | Evidence Collector completed | `go-mknoon/node/pubsub.go`; `go-mknoon/node/node.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_delivery_test.go`; `lib/features/groups/application/rejoin_group_topics_use_case.dart`; `lib/core/lifecycle/handle_app_resumed.dart`; `lib/features/groups/application/group_recovery_gate.dart`; `lib/features/groups/application/leave_group_use_case.dart`; `lib/core/bridge/bridge_group_helpers.dart`; `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`; `test/core/lifecycle/app_lifecycle_recovery_test.dart`; `Test-Flight-Improv/test-gate-definitions.md`; `scripts/run_test_gates.sh`; full `git status --short` | Current code serializes join/leave/config/key updates with `n.mu`, but no existing row-owned test runs all four same-group operations concurrently under `go test -race` or asserts the post-stress map invariant. Row-owned Go regression is required; production code is conditional on that regression exposing a real bug. | Draft the execution-safe GL-019 plan with host-only proof by default and Dart/app checks only if Dart orchestration changes become necessary. |
| 2026-05-10 08:16:37 CEST | Planner started | none | Plan will own exactly GL-019, keep GL-016 clone behavior, GL-020 bulk recovery concurrency, and GM membership rows out of scope, and preserve the dirty worktree. | Write exact scope, regression-first steps, race commands, proof profile, and closure instructions. |
| 2026-05-10 08:17:31 CEST | Planner completed | current draft plan | Draft classifies GL-019 as implementation-ready, not already-covered. The first implementation step is a row-owned Go stress regression in `go-mknoon/node/pubsub_test.go`; Go production changes remain conditional on exact red evidence. | Run Reviewer pass for missing gates, stale assumptions, and scope drift. |
| 2026-05-10 08:19:39 CEST | Reviewer started/completed | current plan draft | Sufficient with adjustments: final status/output sections needed, but scope, row-owned regression, race commands, conditional Dart gates, dirty-worktree guard, and host-only proof profile are adequate. No missing structural owner or gate. | Run Arbiter pass and finalize execution-ready artifact. |
| 2026-05-10 08:19:39 CEST | Arbiter started/completed | reviewer-adjusted plan | No structural blockers remain. Incremental details are documented as deferred; accepted differences are explicit. | Execute this plan in a later implementation pass. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision / blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 08:21:32 CEST | Initial dirty-worktree snapshot | `git status --short` | Starting status recorded before GL-019 execution. Existing modified and untracked files are treated as user/other-agent work; no reverts. Status output: <br><br>```text<br> M Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md<br> M Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-copy-and-actions-plan.md<br> M Test-Flight-Improv/Group-Chat-Feature/test-inventory.md<br> M Test-Flight-Improv/test-gate-definitions.md<br> M go-mknoon/node/node.go<br> M go-mknoon/node/pubsub.go<br> M go-mknoon/node/pubsub_decryption_failure_test.go<br> M go-mknoon/node/pubsub_delivery_test.go<br> M go-mknoon/node/pubsub_key_rotation_grace_test.go<br> M go-mknoon/node/pubsub_test.go<br> M go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go<br> M info.plist<br> M integration_test/group_invite_status_matrix_harness.dart<br> M lib/features/groups/application/drain_group_offline_inbox_use_case.dart<br> M lib/features/groups/application/group_key_update_listener.dart<br> M lib/features/groups/application/group_pending_key_repair_service.dart<br> M lib/features/groups/presentation/screens/group_info_screen.dart<br> M lib/features/groups/presentation/screens/group_info_wired.dart<br> M lib/features/groups/presentation/widgets/group_member_row.dart<br> M test/features/groups/application/create_group_with_members_use_case_test.dart<br> M test/features/groups/application/drain_followup_invariants_test.dart<br> M test/features/groups/application/drain_group_offline_inbox_use_case_test.dart<br> M test/features/groups/application/group_key_update_listener_test.dart<br> M test/features/groups/integration/group_startup_rejoin_smoke_test.dart<br> M test/features/groups/presentation/group_info_screen_test.dart<br> M test/features/groups/presentation/group_info_wired_test.dart<br>?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-001-plan.md<br>?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-002-plan.md<br>?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-003-plan.md<br>?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-004-plan.md<br>?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-005-plan.md<br>?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md<br>?? Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-001-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-002-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-003-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-004-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-005-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-006-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-007-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-008-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-009-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-011-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-012-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-013-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-014-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-015-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-017-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-018-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-019-plan.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md<br>?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md<br>?? lib/features/groups/presentation/group_invite_status_presentation.dart<br>``` | Extract the GL-019 execution contract and inspect owner files before any test edit. |
| 2026-05-10 08:22:35 CEST | Contract extraction completed | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-019-plan.md` | Scope is GL-019 only. Required first change is `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree` in `go-mknoon/node/pubsub_test.go`; production edits are conditional on exact red evidence in `go-mknoon/node/pubsub.go` or `go-mknoon/node/node.go`. Required gates are the focused Go test, focused Go race test, row Go sweep, and `git diff --check`; conditional delivery/app gates only if corresponding files are touched. | Spawn Executor agent with the plan path, dirty-worktree guard, and exact required commands. |
| 2026-05-10 08:23:19 CEST | Executor spawned/running | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-019-plan.md`; expected owner `go-mknoon/node/pubsub_test.go` | Fresh Executor requested with `model: gpt-5.5` and `reasoning_effort: xhigh`. It must add the GL-019 regression first, run required Go checks, and avoid production edits unless the new regression fails for a real runtime issue. | Wait for Executor result, then spawn QA Reviewer. |
| 2026-05-10 08:24:56 CEST | Executor contract re-read / pre-implementation | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-019-plan.md`; `git status --short` | Executor confirms GL-019-only scope, dirty worktree preservation, regression-first edit in `go-mknoon/node/pubsub_test.go`, and required command list. No production or Dart edits are justified before row-owned test evidence. | Re-read owner files before patching the GL-019 regression. |
| 2026-05-10 08:25:57 CEST | Owner inspection completed / implementation starting | `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/node.go`; `go-mknoon/node/pubsub_delivery_test.go`; `lib/features/groups/application/rejoin_group_topics_use_case.dart`; `lib/core/lifecycle/handle_app_resumed.dart`; `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`; `test/core/lifecycle/app_lifecycle_recovery_test.dart`; `Test-Flight-Improv/test-gate-definitions.md`; `scripts/run_test_gates.sh` | Current Go runtime serializes target methods with `n.mu`; existing dirty Go production changes are from prior work and not GL-019. App orchestration files only confirm conditional scope. | Add only `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree` to `go-mknoon/node/pubsub_test.go`. |
| 2026-05-10 08:27:45 CEST | Implementation completed | `go-mknoon/node/pubsub_test.go` | Added `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree` as a tests-only GL-019 regression. No production, delivery, or Dart/app file was edited by this Executor. | Run required focused non-race GL-019 command. |
| 2026-05-10 08:28:01 CEST | Focused GL-019 non-race started | `go-mknoon/node/pubsub_test.go` | Running `(cd go-mknoon && go test ./node -run '^TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree$' -count=1)`. | Record result, then run focused race command if it passes. |
| 2026-05-10 08:28:27 CEST | Focused GL-019 non-race completed | `go-mknoon/node/pubsub_test.go` | PASS: `ok github.com/mknoon/go-mknoon/node 0.562s`. No production change triggered. | Run required focused GL-019 race command. |
| 2026-05-10 08:28:38 CEST | Focused GL-019 race started | `go-mknoon/node/pubsub_test.go` | Running `(cd go-mknoon && go test -race ./node -run '^TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree$' -count=1)`. | Record race result, then run row Go sweep if it passes. |
| 2026-05-10 08:29:01 CEST | Focused GL-019 race completed | `go-mknoon/node/pubsub_test.go` | PASS: `ok github.com/mknoon/go-mknoon/node 1.606s`. Race detector reported no GL-019 race. No production change triggered. | Run required row Go sweep. |
| 2026-05-10 08:29:12 CEST | Row Go sweep started | `go-mknoon/node/pubsub_test.go` | Running `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)`. | Record result, then run `git diff --check` if it passes. |
| 2026-05-10 08:29:48 CEST | Row Go sweep completed | `go-mknoon/node/pubsub_test.go` | PASS: `ok github.com/mknoon/go-mknoon/node 17.764s`. | Run required `git diff --check`. |
| 2026-05-10 08:30:00 CEST | Whitespace check started | `go-mknoon/node/pubsub_test.go`; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-019-plan.md` | Running `git diff --check`. | Record result, then inspect final diff/status. |
| 2026-05-10 08:30:26 CEST | Whitespace check completed | `go-mknoon/node/pubsub_test.go`; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-019-plan.md` | PASS: `git diff --check` returned no output. Conditional production, delivery, and Flutter/app checks are not required because this Executor changed only the GL-019 test and plan progress. | Inspect final diff/status and hand off to QA Reviewer. |
| 2026-05-10 08:30:50 CEST | Executor completed | `go-mknoon/node/pubsub_test.go`; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-019-plan.md`; `git status --short` | GL-019 is tests-only in this Executor pass. Required focused non-race, focused race, row Go sweep, and whitespace check all passed. Existing unrelated dirty files remain preserved. | Ready for separate QA Reviewer. |
| 2026-05-10 08:31:44 CEST | QA Reviewer spawned/running | `go-mknoon/node/pubsub_test.go`; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-019-plan.md` | Fresh QA Reviewer requested with `model: gpt-5.5` and `reasoning_effort: xhigh`. It must review scope adherence, GL-019 closure-bar coverage, required command evidence, and whether tests-only execution is sufficient. | Wait for QA verdict; run fix pass only if QA reports blocking issues. |
| 2026-05-10 08:33:23 CEST | QA Reviewer started | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-019-plan.md`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/node.go`; `git status --short`; `git diff --name-only` | Re-read the plan and GL-019 test implementation. Test covers same-group concurrent `JoinGroupTopic`, `LeaveGroupTopic`, `UpdateGroupConfig`, and `UpdateGroupKey`; narrowly permits duplicate-join errors; checks post-stress map invariants, deterministic cleanup, deterministic rejoin, final cleanup, and scoped retained-state leak proof through cancel/runtime maps plus `Stop()` cleanup. Current status still contains broad preexisting dirty production/Dart/delivery files from the initial snapshot; this Executor's recorded GL-019 touched files are limited to `pubsub_test.go` and this plan progress. | Re-run the required GL-019 commands as QA evidence. |
| 2026-05-10 08:34:06 CEST | QA Reviewer completed | `go-mknoon/node/pubsub_test.go`; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-019-plan.md` | ACCEPTED. QA reran and passed `(cd go-mknoon && go test ./node -run '^TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree$' -count=1)` with `ok github.com/mknoon/go-mknoon/node 0.500s`; `(cd go-mknoon && go test -race ./node -run '^TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree$' -count=1)` with `ok github.com/mknoon/go-mknoon/node 1.459s`; `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)` with `ok github.com/mknoon/go-mknoon/node 17.548s`; and `git diff --check` with no output. No blocking issues found. Conditional production, delivery, and Dart/app checks remain not required for this Executor pass. | Closure may mark GL-019 Covered based on this execution. |
| 2026-05-10 08:35:30 CEST | Final execution verdict written | `go-mknoon/node/pubsub_test.go`; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-019-plan.md` | ACCEPTED. GL-019 completed tests-only with no production, delivery-test, or Dart/app edits from this execution. Executor and QA both passed the required focused non-race test, focused race test, row Go sweep, and `git diff --check`; no blocking issues remain. | Separate closure pass can mark GL-019 Covered. |

## Final verdict

Execution-ready.

GL-019 is not currently covered by exact row-owned evidence. The execution-safe path is regression-first: add the GL-019 same-group concurrent join/leave/config/key stress test, run it under the Go race detector, then change production code only if that exact proof exposes a race, panic, leaked runtime state, or impossible runtime-map combination.

## Final plan

Use the sections below as the implementation contract. The executor should start at `files and repos to inspect next`, add `regression/tests to add first`, and stop as tests-only if the row-owned Go race regression passes without production changes.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- A global goroutine-count leak detector is not required unless a reliable repo-local helper already exists; GL-019 uses retained runtime cancel/subscription state plus `Stop()` return as the bounded leak proof.
- Device, simulator, and relay proof are not required unless execution touches Dart lifecycle orchestration, bridge command serialization, or real transport recovery.
- Flutter/app gates remain conditional because the source row explicitly requires Go race-detector evidence.

## Accepted differences intentionally left unchanged

- Metadata-only config/key state for a non-joined group remains an accepted current behavior unless the GL-019 regression proves it breaks deterministic cleanup, rejoin, or fail-closed publish semantics.
- GL-016 clone behavior, GL-020 bulk recovery concurrency, and GM membership mutation rows remain separate work.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/groups/application/group_recovery_gate.dart`
- `lib/features/groups/application/leave_group_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## Why the plan is safe to implement now

The plan is narrow, regression-first, and bounded to exactly GL-019. It does not presume a production bug before adding row-owned race evidence, but it allows the smallest Go runtime fix if that evidence fails. It names the owner files, exact race commands, conditional Flutter gates, dirty-worktree constraints, and closure bar needed to prevent scope drift.

## real scope

Own exactly GL-019: the Go runtime behavior for one group while `JoinGroupTopic`, `LeaveGroupTopic`, `UpdateGroupConfig`, and `UpdateGroupKey` are invoked concurrently by app recovery and user action paths.

Allowed execution owner files:

- `go-mknoon/node/pubsub_test.go` for the row-owned GL-019 regression.
- `go-mknoon/node/pubsub.go` only if the GL-019 regression fails because same-group join/leave/update operations leave impossible runtime state, race, panic, or cannot cleanly rejoin after stress.
- `go-mknoon/node/node.go` only if the failure is specifically lifecycle-map initialization or started/stopped state interacting with the same-group race. This is not expected from the current source row.
- `go-mknoon/node/pubsub_delivery_test.go` only if a minimal live-delivery assertion after deterministic rejoin cannot fit in `pubsub_test.go`; prefer keeping the GL-019 proof in `pubsub_test.go`.
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, and `test/core/lifecycle/app_lifecycle_recovery_test.dart` are inspection and conditional Dart/app surfaces only. Do not edit them unless implementation evidence shows the race is actually caused by Flutter orchestration rather than Go runtime state.

Do not edit source matrix, breakdown, closure docs, GL-016 clone behavior, GL-020 bulk recovery concurrency, GM membership mutation rows, unrelated Go tests, bridge command mapping, or UI/application flows during GL-019 execution.

## closure bar

GL-019 can close only when row-owned evidence proves all of the following:

- A focused `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree` or equivalently named regression runs same-group `JoinGroupTopic`, `LeaveGroupTopic`, `UpdateGroupConfig`, and `UpdateGroupKey` concurrently.
- The focused test passes normally and under `go test -race`.
- Expected ordering errors are allowed and asserted narrowly: duplicate joins may return `already joined group topic`, and leave may be idempotent; unexpected errors fail the test.
- The post-stress runtime maps are not impossible: group topic, subscription, subscription cancel, and discovery cancel entries are either all present for a joined runtime or all absent after deterministic cleanup; a topic must never remain without config/key, subscription, and cancel state.
- The test performs deterministic final cleanup with `LeaveGroupTopic(groupId)` and proves `groupTopics`, `groupSubs`, `groupSubCtx`, `groupDiscoveryCtx`, `groupConfigs`, and `groupKeys` contain no entry for that group afterward.
- The test performs deterministic rejoin with a latest config/key after the stress and proves the full runtime state is rebuilt, then leaves cleanly again.
- Leaked goroutine proof is scoped to retained runtime state: subscription and discovery cancel maps must be empty after final leave and `Stop()` must return. Do not use global goroutine counts as a hard assertion unless a reliable repo-local helper already exists, because libp2p background goroutines are noisy.

If this regression passes without production edits, GL-019 may close as tests-only despite the breakdown's `needs_code_and_tests` classification because the Open source row lacked exact row-owned race evidence. If it fails, make the smallest production fix required by the same test and re-run the race proof.

## source of truth

Authoritative inputs:

- Source row GL-019 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
- Breakdown GL-019 inventory, disposition, ordered-session entry, and likely owner/test surfaces in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current worktree code and tests in the owner files listed above.
- Accepted prior-session context: GL-011/GL-012 fixed config snapshot and nil config behavior; GL-013 fixed nil key removal; GL-014/GL-015 cover key epoch semantics; GL-017 covers `Stop()` clearing runtime state; GL-018 covers persisted app restart rejoin.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` for named Flutter host gates if Dart changes become necessary.

Conflict rule: current code/tests beat stale prose. The source row remains Open until GL-019-owned evidence exists. Prior closures are accepted only for their rows and must not be stretched to cover concurrent join/leave/update stress.

## session classification

`implementation-ready`

This is not acceptance-only, not stale, and not already-covered. Current code likely has the right lock shape, but there is no exact GL-019 race-detector regression. The required implementation posture is code-and-tests with a regression-first stop point: add row-owned Go test evidence first; production code is conditional on red evidence from that test.

## exact problem statement

App recovery can try to rejoin group topics while user actions or membership/key updates are also mutating the same group. Current Go methods protect their maps with `n.mu`, and adjacent tests cover config-only races, nil config/key behavior, leave cleanup, stop/rejoin, and app restart rejoin. Missing exact coverage remains: no test runs join, leave, config update, and key update for the same group concurrently under the Go race detector and then proves the runtime maps can end in a valid, recoverable state.

User-visible behavior at risk: after a rapid add/remove/re-add or recovery/user-action overlap, the app could silently lose a group topic, retain stale subscription/discovery state, fail to rejoin, or panic/race in Go.

Behavior that must stay unchanged:

- `JoinGroupTopic` still rejects duplicate joins without replacing the original topic state.
- `LeaveGroupTopic` remains safe and clears runtime state for the group.
- `UpdateGroupConfig(nil)` remains the GL-012 fail-closed behavior.
- `UpdateGroupKey(nil)` remains the GL-013 key removal behavior.
- Key stale/same-epoch semantics from GL-014/GL-015 remain untouched.
- Config/key snapshots and clone behavior from GL-011 and GL-016 remain untouched.

## files and repos to inspect next

Before implementation, re-read these exact files because the worktree is dirty and other agents have edits in owner areas:

- `git status --short`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

Adjacent Go coverage:

- `go-mknoon/node/pubsub_test.go::TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree` covers validator reads racing config updates, not join/leave/key updates.
- `go-mknoon/node/pubsub_test.go::TestGL012UpdateGroupConfigNilConcurrentReadersAreRaceFree` covers nil/valid config update races against validator/discovery/counter reads, not join/leave/key updates.
- `go-mknoon/node/pubsub_test.go::TestUpdateGroupConfig_ConcurrentUpdates` covers config-only concurrent updates with manually initialized maps, not a started node, topic join/leave, subscription/discovery maps, or key updates.
- `go-mknoon/node/pubsub_test.go::TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish` covers serial leave cleanup.
- `go-mknoon/node/pubsub_test.go::TestJoinGroupTopic_DuplicateJoinPreservesExistingState` covers serial duplicate join safety.
- `go-mknoon/node/pubsub_test.go::TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart` covers stop/restart clearing and explicit rejoin, not concurrent same-group mutations.
- `go-mknoon/node/pubsub_delivery_test.go::TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey` and `TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription` cover serial leave/rejoin and active config replacement behavior.

Adjacent Flutter/app coverage:

- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` covers persisted startup rejoin and exact-once group join payloads from GL-018.
- `test/core/lifecycle/app_lifecycle_recovery_test.dart` covers resume-driven group recovery acknowledgement.
- These app tests do not run Go `JoinGroupTopic`, `LeaveGroupTopic`, `UpdateGroupConfig`, and `UpdateGroupKey` concurrently and cannot satisfy the GL-019 race-detector requirement.

Missing exact GL-019 coverage:

- No row-owned test exercises all four same-group Go operations concurrently.
- No GL-019 test is required to pass under `go test -race`.
- No current test asserts post-stress same-group runtime-map invariants and deterministic cleanup/rejoin recovery.

## regression/tests to add first

Add `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree` to `go-mknoon/node/pubsub_test.go`.

The test should:

- Start a real local `Node` with pubsub initialized and no relay addresses.
- Build valid config/key inputs using the node's peer id and generated signing/group keys.
- Perform an initial successful join for the target group.
- Use a start barrier plus `sync.WaitGroup` to run concurrent workers for the same `groupId`:
  - repeated `JoinGroupTopic(groupId, configVariant, keyVariant)` attempts,
  - repeated `LeaveGroupTopic(groupId)` calls,
  - repeated `UpdateGroupConfig(groupId, configVariant)` calls,
  - repeated `UpdateGroupKey(groupId, keyVariant)` calls with non-nil keys and increasing epochs.
- Treat duplicate-join errors as expected; fail on unexpected join errors. `LeaveGroupTopic`, `UpdateGroupConfig`, and `UpdateGroupKey` should not panic.
- After workers complete, inspect state under `n.mu` and fail on impossible runtime combinations, especially topic without sub/subCtx/discoveryCtx/config/key.
- Call `LeaveGroupTopic(groupId)` deterministically and assert no group-specific entries remain in `groupTopics`, `groupSubs`, `groupSubCtx`, `groupDiscoveryCtx`, `groupConfigs`, or `groupKeys`.
- Call `JoinGroupTopic(groupId, latestConfig, latestKey)` deterministically and assert topic/sub/subCtx/discoveryCtx/config/key are all present and reflect the latest rejoin inputs.
- Call `LeaveGroupTopic(groupId)` once more and assert clean final state.

Keep nil config/key updates out of this GL-019 regression; GL-012 and GL-013 already own nil behavior. Keep multi-group concurrency out; GL-020 owns bulk recovery concurrency.

## step-by-step implementation plan

1. Run `git status --short` and re-read the owner files listed above. If any owner file has changed since this plan, work with the current contents and do not revert other edits.
2. Add the GL-019 regression to `go-mknoon/node/pubsub_test.go`.
3. Run the focused non-race test. If it fails for a test-shape issue, fix only the test. If it fails because current code leaves an impossible runtime state or cannot cleanly rejoin, keep the RED evidence and proceed to the smallest production fix.
4. Run the focused race test. If the race detector reports a race in GL-019-owned code, fix the raced access with the smallest lock/snapshot/lifecycle-map change that preserves prior GL-011 through GL-018 contracts.
5. If production code changes are needed, prefer local fixes in `pubsub.go` around same-group runtime state consistency. Touch `node.go` only for lifecycle-map initialization/stopped-state evidence. Do not add broad generation tokens, new orchestration layers, or app-level queues unless the focused test proves the simple invariant cannot hold otherwise.
6. Re-run the focused non-race and race tests after each fix.
7. Run the row Go sweep and whitespace check. Run Flutter/app gates only if Dart files were touched.
8. Record the final execution evidence in this plan's execution section during the later implementation pass, then hand off to closure.

## risks and edge cases

- Join/leave order is intentionally nondeterministic. The test should assert valid state classes and deterministic cleanup/rejoin, not a single arbitrary winner from the concurrent batch.
- Existing code allows `UpdateGroupConfig` and `UpdateGroupKey` to store metadata even when no topic is currently joined. Do not redefine that behavior as impossible unless the GL-019 regression proves it breaks cleanup, rejoin, or publish semantics; `TestUpdateGroupConfig_NonExistentGroup` currently pins config storage for non-joined groups.
- `JoinGroupTopic` starts subscription and discovery goroutines. GL-019 must assert cancel/runtime-map cleanup after final leave rather than use brittle process-wide goroutine counts.
- Race detector failures from libp2p internals or unrelated dirty worktree edits must be separated from GL-019 code before changing behavior.
- The test must be bounded and deterministic enough for local and CI runs; avoid long sleeps and avoid relying on real relay rendezvous.

## exact tests and gates to run

Required GL-019 Go checks:

```bash
(cd go-mknoon && go test ./node -run '^TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree$' -count=1)
(cd go-mknoon && go test -race ./node -run '^TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree$' -count=1)
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)
git diff --check
```

If `go-mknoon/node/pubsub.go` or `go-mknoon/node/node.go` changes, also run:

```bash
(cd go-mknoon && go test -race ./node -run '^TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree$|^TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree$|^TestGL012UpdateGroupConfigNilConcurrentReadersAreRaceFree$' -count=1)
```

If `go-mknoon/node/pubsub_delivery_test.go` changes, also run the relevant focused delivery checks:

```bash
(cd go-mknoon && go test ./node -run '^TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey$|^TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription$' -count=1)
```

Flutter/app checks are conditional. Run them only if Dart/app orchestration files are touched:

```bash
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart
flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'rejoins and acknowledges when Go signals group recovery'
./scripts/run_test_gates.sh groups
git diff --check
```

## Device/Relay Proof Profile

Host-only.

GL-019's explicit requirement is a Go race-detector proof for concurrent same-group runtime operations. A simulator, physical device, or real relay proof is not required unless execution unexpectedly changes Dart lifecycle orchestration, bridge command serialization, real relay recovery, or simulator-only startup behavior. The default proof should use a local started Go node with no relay addresses and `go test -race`.

## known-failure interpretation

The worktree is dirty before GL-019 planning. Many Go, Dart, test, and doc files already have unrelated modifications or are untracked. The executor must preserve them and avoid using broad reverts.

Interpretation rules:

- A failure in the focused GL-019 non-race or race command is a GL-019 blocker unless the executor can prove it reproduces before adding the GL-019 test and is unrelated to the session.
- A race-detector report involving `JoinGroupTopic`, `LeaveGroupTopic`, `UpdateGroupConfig`, `UpdateGroupKey`, or the maps they mutate is GL-019-owned.
- A failure in a conditional Flutter/app check is GL-019-owned only if Dart files were touched or the failure is causally tied to the GL-019 change.
- Pre-existing failures in unrelated gates should be captured with exact output and not silently reclassified as GL-019 regressions.

## done criteria

- The GL-019 row-owned regression exists and is named clearly.
- Focused non-race and race-detector GL-019 commands pass.
- Required row Go sweep passes.
- `git diff --check` passes.
- Any conditional Go delivery or Flutter/app checks required by touched files pass.
- No source matrix, breakdown, closure doc, GL-016, GL-020, or GM row edits are included in the implementation diff.
- The plan's later execution notes state whether production code changed and list exact commands/results.

## scope guard

Do not broaden this session into:

- GL-016 clone/deep-copy behavior.
- GL-020 bulk recovery or multi-group concurrency.
- GM membership mutation/add/remove flows.
- Nil config/key semantics already owned by GL-012 and GL-013.
- Key stale/same-epoch semantics already owned by GL-014 and GL-015.
- New app-level recovery queues, bridge serialization layers, global goroutine-leak frameworks, or relay/device proofs without direct GL-019 evidence.
- Matrix/breakdown/closure edits during implementation; closure is a separate post-evidence step.

## accepted differences / intentionally out of scope

- Config/key metadata without a joined topic can exist today because `UpdateGroupConfig_NonExistentGroup` intentionally stores config for a non-existent group and `UpdateGroupKey` can seed key info. GL-019 should not treat metadata-only state as impossible unless it prevents deterministic cleanup/rejoin or publish fail-closed behavior.
- Flutter recovery and resume tests remain conditional because the source row explicitly requires Go race-detector evidence.
- Real relay and simulator coverage are intentionally out of scope for the default proof profile.

## dependency impact

GL-019 provides the same-group race-safety base for later bulk recovery and membership stress rows. If GL-019 requires production changes, GL-020 and GM mutation sessions should re-read the changed invariants before planning. If GL-019 closes tests-only, later sessions can rely on the Go runtime's current lock/state model but must still add their own row-owned evidence.

## dirty-worktree / scope guard

Before implementation, `git status --short` showed pre-existing modified files including `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, Flutter group files, gate docs, and many untracked plan docs. Treat all such edits as user/other-agent work.

Execution must:

- Re-read any file before editing it.
- Patch only GL-019-owned hunks.
- Avoid formatting unrelated files.
- Avoid `git checkout`, `git reset`, or any command that discards other edits.
- Stop and report if a required owner file has incompatible concurrent edits that make a safe patch impossible.

## closure instructions

After implementation and QA, a separate closure pass may update the source matrix and breakdown. Do not do that during implementation unless explicitly assigned.

Closure can mark GL-019 `Covered` only if it cites:

- The GL-019 row-owned test name and file.
- Passing focused non-race and `go test -race` evidence.
- Passing row Go sweep and `git diff --check`.
- Whether production code changed.
- Any conditional Flutter/app gates if Dart files changed.

If the GL-019 test passes without production edits, closure should explicitly say `tests-only accepted after row-owned race evidence` and should not claim GL-020 bulk recovery, GL-016 clone behavior, or GM membership mutation coverage.

## reviewer notes

Reviewer verdict: sufficient as-is after final status/output adjustments.

Review answers:

- Sufficiency: sufficient. The plan is decomposed enough for implementation because it starts with one focused Go regression and has a clear tests-only stop point.
- Missing files/tests/gates: none structurally. Dart files and Flutter gates are correctly conditional.
- Stale assumptions: none found. Current code/tests beat stale prose, and current evidence does not already cover GL-019.
- Overengineering: no required new framework, global goroutine detector, app queue, or relay/device proof.
- Minimum needed: add the GL-019 Go regression, run focused non-race and race commands, then make production changes only on exact red evidence.

## arbiter decision

No structural blockers.

Incremental details are already captured in `Incremental details intentionally deferred`. Accepted differences are captured in `Accepted differences intentionally left unchanged`. Stop here; do not reopen GL-016, GL-020, GM membership, or app-level orchestration work during GL-019 execution.
