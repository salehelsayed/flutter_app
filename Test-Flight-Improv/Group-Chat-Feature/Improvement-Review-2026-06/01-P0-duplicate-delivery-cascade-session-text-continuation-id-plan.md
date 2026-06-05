# Id-stable restored text continuation plan

Status: accepted_with_explicit_follow_up

Source doc: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`

Breakdown artifact: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-breakdown.md`

Session id: `text-continuation-id`

## Final Execution Output

- Execution verdict: `accepted_with_explicit_follow_up`.
- Spawned-agent isolation used: yes. Executor child `019e8e91-49ae-7320-b231-20ac2a8148cd` was spawned with `model: gpt-5.5`, `reasoning_effort: xhigh`, timed out after the bounded wait plus one extension, and was closed as `spawn_or_tool_failure`; local controller-side verification recovery completed the Executor evidence. QA Reviewer child `019e8ea5-be40-75d3-b154-00ced312d63e` was spawned separately with `model: gpt-5.5`, `reasoning_effort: xhigh`, and returned `accepted_with_explicit_follow_up`.
- Local sequential fallback used: yes, for Executor verification recovery only after nested Executor materialization failure; QA remained isolated in a separate spawned child.
- Files changed for this session: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `integration_test/group_recovery_e2e_test.dart`, and this plan file. Existing unrelated dirty worktree files were preserved and not counted as session-owned work.
- Tests added or updated: restored text-only same-id widget regression, edited restored text fresh-id widget regression, send-use-case edited failed text collision guard regression, and a simulator-backed restored text continuation proof in `integration_test/group_recovery_e2e_test.dart`.
- Exact tests and gates run:
  - `dart format --output=none --set-exit-if-changed lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/application/send_group_message_use_case_test.dart integration_test/group_recovery_e2e_test.dart` passed.
  - Five focused direct tests passed: restored text-only same-id, edited restored text fresh-id, send-use-case edited failed text guard, existing text-only in-place retry, and GIRD-002 restored media continuation.
  - Full direct suites passed: `group_conversation_wired_test.dart` 107 tests, `send_group_message_use_case_test.dart` 132 tests, `retry_failed_group_messages_use_case_test.dart` 14 tests.
  - `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` passed; `integration_test/group_recovery_e2e_test.dart` was command `#8`.
  - `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` passed.
  - `./scripts/run_test_gates.sh groups` initially failed with a transient `ST-003` broad-gate failure; focused `ST-003` rerun passed.
  - Logged rerun `./scripts/run_test_gates.sh groups > /tmp/text-continuation-groups-rerun.log 2>&1` exited 1 only with the known `GCA-004 bridgeError recovery drains inbox after settled materialized invite` residual at `invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`.
  - QA reran the five focused tests and `git diff --check`; all passed.
- QA verdict: `accepted_with_explicit_follow_up`.
- Blocking issues remaining: none.
- Residual / non-blocking follow-up: carry forward known unrelated `GCA-004` broad-gate residual; QA also noted an optional timestamp-only failed-row id collision guard variant as non-blocking because production and required guard coverage already verify the predicate.
- Session ready for closure: yes.

## Execution Progress

- `2026-06-03 20:05:06 CEST` - Phase: QA Reviewer final verification complete. Files inspected/touched: scoped production/test diffs, plan progress only, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `/tmp/text-continuation-groups-rerun.log`. Command/result: `dart format --output=none --set-exit-if-changed ...` passed; personally reran the restored same-text widget regression, edited-text widget regression, send-use-case edited failed-text guard, existing text-only retry, and GIRD-002 media continuation focused tests, all passed; `git diff --check` passed. Decision/blocker: no blocking issue found; session safe to accept with the recorded known `GCA-004` groups-gate residual. Non-blocking follow-up: a timestamp-only failed-row id collision guard variant would make the existing `_canReuseOutgoingMessageId` timestamp check explicit in tests, but the required edited/mismatched failed-text guard and production timestamp predicate were verified. Next action: parent controller may close the session.
- `2026-06-03 20:03:30 CEST` - Phase: QA Reviewer completed scoped review. Files inspected/touched: scoped production/test diffs, `send_group_message_use_case.dart` guard, `/tmp/text-continuation-groups-rerun.log`, and plan progress only. Command/evidence checked: format entry, five focused tests, three direct suites, `run_with_devices.sh group --list`, `run_with_devices.sh group --only integration_test/group_recovery_e2e_test.dart`, and `./scripts/run_test_gates.sh groups` rerun log. Decision/blocker: accepted_with_explicit_follow_up; no blocking issue found. Known residual: groups gate failed only with allowed `GCA-004 bridgeError recovery drains inbox after settled materialized invite` at `invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`. Next action: session ready for closure by the parent controller.
- `2026-06-03 20:01:49 CEST` - Phase: QA Reviewer scoped review started. Files inspected/touched: plan progress section, implementation-execution QA skill, `git status --short`. Command currently running: scoped diff and evidence inspection for `text-continuation-id`. Decision/blocker: pending QA; no blocking issue established. Next action: inspect session-owned diffs, required regression tests, simulator/gate logs, and then record final QA verdict.
- `2026-06-03 20:00:45 CEST` - Phase: QA Reviewer running. Files inspected/touched: plan progress section. Command currently running: nested QA Reviewer agent `019e8ea5-a610-79d3-bc16-0c848bc605ea`. Decision/blocker: pending QA; no fix pass started. Next action: bounded wait for QA verdict.
- `2026-06-03 20:00:35 CEST` - Phase: named gate rerun classified and QA spawn ready. Files inspected/touched: `/tmp/text-continuation-groups-rerun.log` lines 2088-2100, plan progress. Command/result: `./scripts/run_test_gates.sh groups > /tmp/text-continuation-groups-rerun.log 2>&1` exited with `+317 -1`; focused `ST-003` triage passed and the rerun's single failure is `test/features/groups/integration/invite_round_trip_test.dart`, `GCA-004 bridgeError recovery drains inbox after settled materialized invite`, `invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`. Decision/blocker: classified as the known unrelated residual allowed by the plan because all session-owned direct and simulator proofs passed. Next action: spawn separate QA Reviewer with `model: gpt-5.5`, `reasoning_effort: xhigh`.
- `2026-06-03 19:59:11 CEST` - Phase: controller gate evidence reconciliation. Files inspected/touched: plan progress only. Failing/rerun gate command: `./scripts/run_test_gates.sh groups > /tmp/text-continuation-groups-rerun.log 2>&1` per latest Executor progress. Log path: `/tmp/text-continuation-groups-rerun.log`. Focused triage already recorded by Executor: `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-003 fake-network randomized key epoch monotonicity keeps active epoch"` passed. Classification state: `pending_triage` until log/process inspection confirms the full rerun result. Next action: inspect process/log state before QA handoff.
- `2026-06-03 20:00:05 CEST` - Phase: controller gate rerun wait. Files inspected/touched: process list and `/tmp/text-continuation-groups-rerun.log`. Command currently running: `./scripts/run_test_gates.sh groups` PID 58378. Decision/blocker: required named gate evidence still pending; QA not spawned yet. Next action: wait for PID 58378 to exit, then classify the rerun log before QA handoff.
- 2026-06-03 19:59:11 CEST | phase: named gate failure triage | files inspected/touched: `test/features/groups/integration/group_messaging_smoke_test.dart` output | command/result: focused triage `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-003 fake-network randomized key epoch monotonicity keeps active epoch"` passed | classification: transient broad-gate failure pending full-gate confirmation | command currently running: `./scripts/run_test_gates.sh groups > /tmp/text-continuation-groups-rerun.log 2>&1` | decision/blocker: still pending because the required named gate has not yet passed or failed with the known residual | next action: classify the logged full-gate rerun result.
- 2026-06-03 19:58:12 CEST | phase: named gate failure triage | files inspected/touched: `./scripts/run_test_gates.sh groups` output | failing gate command: `./scripts/run_test_gates.sh groups` exited 1 | failing file/test: `test/features/groups/integration/group_messaging_smoke_test.dart`, `Multi-user group messaging smoke tests ST-003 fake-network randomized key epoch monotonicity keeps active epoch` | log path: none, console output only | exact focused triage command about to run: `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-003 fake-network randomized key epoch monotonicity keeps active epoch"` | classification state: pending_triage | next action: run focused failing slice before any fix attempt or full rerun.
- 2026-06-03 19:56:42 CEST | phase: named gate verification | files inspected/touched: simulator command output | command/result: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` passed; command `#8` and reliability scope `group` completed for the targeted file | command currently running: `./scripts/run_test_gates.sh groups` | decision/blocker: no blocker | next action: triage any groups-gate failure against the known `GCA-004` residual; otherwise spawn QA Reviewer.
- 2026-06-03 19:54:35 CEST | phase: simulator verification | files inspected/touched: simulator list output | command/result: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` passed; one-device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, two-device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,38FECA55-03C1-4907-BD9D-8E64BF8E3469`; `integration_test/group_recovery_e2e_test.dart` is group command `#8` | command currently running: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` | decision/blocker: no blocker | next action: run named `groups` gate if targeted simulator proof passes.
- 2026-06-03 19:53:57 CEST | phase: simulator verification | files inspected/touched: `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, run-flutter-reliability-sims skill instructions | command/result: `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart` passed, 14 tests | command currently running: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` | decision/blocker: no blocker | next action: run targeted `integration_test/group_recovery_e2e_test.dart` simulator proof if list resolves.
- 2026-06-03 19:53:18 CEST | phase: direct suite verification | files inspected/touched: `test/features/groups/application/send_group_message_use_case_test.dart` | command/result: `flutter test test/features/groups/application/send_group_message_use_case_test.dart` passed, 132 tests | command currently running: `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart` | decision/blocker: no blocker | next action: run simulator list and group recovery simulator proof if retry suite passes.
- 2026-06-03 19:52:28 CEST | phase: direct suite verification | files inspected/touched: `test/features/groups/presentation/group_conversation_wired_test.dart` | command/result: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` passed, 107 tests | command currently running: `flutter test test/features/groups/application/send_group_message_use_case_test.dart` | decision/blocker: no blocker | next action: run retry failed group messages suite after this result.
- 2026-06-03 19:50:43 CEST | phase: direct suite verification | files inspected/touched: `test/features/groups/presentation/group_conversation_wired_test.dart` | command currently running: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` | decision/blocker: pending suite result | next action: run application direct suites if this passes.
- 2026-06-03 19:50:30 CEST | phase: local focused verification complete | files inspected/touched: `group_conversation_wired_test.dart`, `send_group_message_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart` | command/result: all five focused tests passed locally: restored text-only same-id, edited restored text fresh-id, send-use-case edited failed text guard, existing text-only in-place retry, and GIRD-002 restored media continuation | decision/blocker: no blocker | next action: run the full required direct suites.
- 2026-06-03 19:49:37 CEST | phase: local verification recovery | files inspected/touched: contract Dart files | command/result: format validation passed with 0 changed files | command currently running: focused direct test `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "restored text-only composer continuation reuses the failed group row id"` | decision/blocker: no blocker | next action: run remaining focused tests after this result.
- 2026-06-03 19:49:15 CEST | phase: local verification recovery | files inspected/touched: `group_conversation_wired.dart`, `group_conversation_wired_test.dart`, `send_group_message_use_case_test.dart`, `integration_test/group_recovery_e2e_test.dart` | command currently running: `dart format --output=none --set-exit-if-changed lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/application/send_group_message_use_case_test.dart integration_test/group_recovery_e2e_test.dart` | decision/blocker: pending local verification after nested Executor `spawn_or_tool_failure` | next action: run exact focused/direct tests from the current worktree after format validation.
- 2026-06-03 19:48:03 CEST | phase: Executor child recovery | files inspected/touched: plan progress tail, scoped git diff, process list | command/result: Executor child `019e8e91-49ae-7320-b231-20ac2a8148cd` timed out after the initial bounded wait and one allowed wait extension; no final child result materialized and child was closed while still running | decision/blocker: nested Executor classified `spawn_or_tool_failure`; existing file-backed progress from the plan plus scoped diffs will be verified locally under controller-side verification recovery | next action: run remaining required direct suites, simulator command, and groups gate from the current worktree if coherent.
- 2026-06-03 19:38:24 CEST | phase: initial heartbeat | last completed result: prior-session residual known only from controller prompt; no session-local command completed yet | current action: starting isolated execution/QA workflow for `text-continuation-id` and preparing to extract the plan contract | blocker state: pending_triage, no blocker established | next action: spawn the fresh Executor child with model `gpt-5.5` and reasoning_effort `xhigh`.
- `2026-06-03 19:48:00 CEST` - Phase: executor-verified focused direct regressions passed. Files inspected/touched: `group_conversation_wired_test.dart`, `send_group_message_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart`. Commands finished: restored text-only same-id widget test passed; edited restored text fresh-id widget test passed; send-use-case edited failed text collision guard passed; text-only failed row in-place retry passed; GIRD-002 restored media continuation passed. Decision/blocker: no blocker. Next action: run full direct suites.
- `2026-06-03 19:47:43 CEST` - Phase: focused direct test 3 passed; focused direct test 4 starting. Files inspected/touched: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`. Command finished: `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "message id collision guard treats edited restored failed text as a new message"` passed. Command currently running: `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "retries a text-only failed row in place using the original ids"`. Decision/blocker: no blocker. Next action: verify existing in-place text retry behavior still passes.
- `2026-06-03 19:46:45 CEST` - Phase: focused direct test 2 passed; focused direct test 3 starting. Files inspected/touched: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`. Command finished: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "editing restored text-only composer continuation creates a new group row id"` passed. Command currently running: `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "message id collision guard treats edited restored failed text as a new message"`. Decision/blocker: no blocker; current simulator proof remains in `integration_test/group_recovery_e2e_test.dart`. Next action: verify the application collision guard regression.
- `2026-06-03 19:47:01 CEST` - Phase: format validation passed. Files inspected/touched: contract Dart files. Command finished: `dart format --output=none --set-exit-if-changed lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/application/send_group_message_use_case_test.dart integration_test/group_recovery_e2e_test.dart` passed, formatted 4 files with 0 changed. Decision/blocker: no blocker. Next action: run focused direct regressions.
- `2026-06-03 19:46:43 CEST` - Phase: nested Executor reconciliation. Files inspected/touched: `integration_test/group_recovery_e2e_test.dart`, plan progress, current diffs. Decision/blocker: no blocker; concurrent progress already landed the text-only continuation edit and simulator proof, and I removed only my duplicate simulator test block while preserving the existing proof. Next action: run required format and direct gates from the current worktree for executor-verifiable evidence.
- `2026-06-03 19:46:24 CEST` - Phase: focused direct test 1 passed; focused direct test 2 starting. Files inspected/touched: `test/features/groups/presentation/group_conversation_wired_test.dart`. Command finished: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "restored text-only composer continuation reuses the failed group row id"` passed. Command currently running: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "editing restored text-only composer continuation creates a new group row id"`. Decision/blocker: no blocker. Next action: verify edited restored text remains a fresh send.
- `2026-06-03 19:45:51 CEST` - Phase: format validation passed; focused direct tests starting. Files inspected/touched: contract Dart files. Command finished: `dart format --output=none --set-exit-if-changed ...` passed with 0 changed. Command currently running: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "restored text-only composer continuation reuses the failed group row id"`. Decision/blocker: no blocker. Next action: run the remaining focused direct regressions sequentially.
- `2026-06-03 19:45:26 CEST` - Phase: formatting applied; format validation starting. Files inspected/touched: `test/features/groups/presentation/group_conversation_wired_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`. Command finished: `dart format lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/application/send_group_message_use_case_test.dart integration_test/group_recovery_e2e_test.dart` formatted 2 of 4 files. Command currently running: contract `dart format --output=none --set-exit-if-changed ...`. Decision/blocker: no blocker. Next action: run focused direct regressions after format validation.
- `2026-06-03 19:44:58 CEST` - Phase: simulator proof added; formatting starting. Files inspected/touched: `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`. Command currently running: `dart format lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/application/send_group_message_use_case_test.dart integration_test/group_recovery_e2e_test.dart`. Decision/blocker: no blocker; simulator proof uses existing `integration_test/group_recovery_e2e_test.dart` and does not require gate-definition churn. Next action: run focused simulator/host regressions after formatting.
- `2026-06-03 19:41:41 CEST` - Phase: production edit applied; focused validation starting. Files inspected/touched: `lib/features/groups/presentation/screens/group_conversation_wired.dart`. Command currently running: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "restored text-only composer continuation reuses the failed group row id"`. Decision/blocker: smallest behavior change tracks restored continuation for non-empty text-only failed snapshots while preserving attachment cleanup for media snapshots. Next action: verify same-text focused regression passes.
- `2026-06-03 19:41:22 CEST` - Phase: RED focused test finished. Files inspected/touched: `test/features/groups/presentation/group_conversation_wired_test.dart`. Command finished: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "restored text-only composer continuation reuses the failed group row id"` failed as expected at `group_conversation_wired_test.dart:6336` because two rows existed for the same restored text. Decision/blocker: no blocker; RED confirms implementation gap. Next action: update `group_conversation_wired.dart` to track text-only restored continuation without changing send-use-case guards or media retry semantics.
- `2026-06-03 19:40:47 CEST` - Phase: owner files inspected; RED focused test starting. Files inspected/touched: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `integration_test/group_recovery_e2e_test.dart`. Command currently running: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "restored text-only composer continuation reuses the failed group row id"`. Decision/blocker: target host regressions already exist in dirty state; production still clears text-only continuation, so confirming expected RED before implementation. Next action: implement only restored text-only continuation if the focused regression fails as expected.
- `2026-06-03 19:39:54 CEST` - Phase: spawned Executor contract extracted. Files inspected/touched: plan, breakdown artifact, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, run-flutter-reliability-sims skill instructions, `git status --short`. Decision/blocker: no blocker; executing only `text-continuation-id`, preserving prior text-retry-ui worktree changes and not touching later-session docs. Next action: inspect owner production/test files and add RED regressions before production changes.
- `2026-06-03 19:37:13 CEST` - Phase: nested Executor started. Files inspected/touched: plan, breakdown artifact, implementation-execution and Flutter test skill instructions. Decision/blocker: no blocker; executing only restored text-only composer continuation behavior with host regressions first and simulator proof. Next action: inspect owner code/tests and current dirty worktree without reverting unrelated changes.
- `2026-06-03 19:36:07 CEST` - Phase: contract extracted. Files inspected/touched: plan, breakdown artifact, skill instructions, `git status --short`. Decision/blocker: no blocker; scope is restored text-only composer continuation in `group_conversation_wired.dart`, optional guard-only use-case change, host regressions, simulator proof, and `./scripts/run_test_gates.sh groups` with known `GCA-004` residual interpretation. Existing unrelated dirty state includes prior text-retry-ui code/l10n/test edits plus untracked plan docs. Next action: spawn fresh nested Executor with `model: gpt-5.5`, `reasoning_effort: xhigh`.
- `2026-06-03 19:36:30 CEST` - Phase: Executor spawn requested. Files inspected/touched: plan progress section. Command currently running: nested Executor agent startup. Decision/blocker: no blocker; Executor must add RED host/simulator regressions first, implement only the text-only restored-composer continuation seam, run required direct tests/gates, and record exact evidence. Next action: wait bounded interval for Executor completion/progress.
- `2026-06-03 19:36:42 CEST` - Phase: Executor running. Files inspected/touched: plan progress section. Command currently running: nested Executor agent `019e8e8f-38ae-7a61-8c06-073872e434de`. Decision/blocker: no blocker; strict sequence prevents QA spawn until Executor returns. Next action: bounded wait for Executor result.
- `2026-06-03 19:46:42 CEST` - Phase: Executor bounded wait expired. Files inspected/touched: plan progress section. Command currently running: nested Executor agent `019e8e8f-38ae-7a61-8c06-073872e434de` still has no final result. Decision/blocker: pending child-progress inspection; if assigned files or plan progress show real Executor progress, allow one more bounded wait, otherwise classify `spawn_or_tool_failure` and use local sequential fallback if safe. Next action: inspect worktree and plan progress for Executor evidence.
- `2026-06-03 19:47:10 CEST` - Phase: Executor progress confirmed. Files inspected/touched: `git status --short`, plan progress, diffs for `group_conversation_wired.dart`, `group_conversation_wired_test.dart`, `send_group_message_use_case_test.dart`, `integration_test/group_recovery_e2e_test.dart`. Decision/blocker: no blocker; Executor landed assigned code/test progress and plan entries include RED confirmation plus focused test runs. Next action: allow one additional bounded wait for Executor final result.

## Planning Progress

- `2026-06-03 19:33:41 CEST` - Role: Arbiter completed. Files inspected since last update: reviewer findings and complete plan. Decision/blocker: no structural blockers; incremental details are documented and do not require a patch loop. Next action: plan is execution-ready for the downstream implementation/QA agent.
- `2026-06-03 19:33:41 CEST` - Role: Arbiter started. Files inspected since last update: reviewer findings and complete plan. Decision/blocker: no blocker; classifying findings into structural blockers, incremental details, and accepted differences. Next action: persist final arbiter verdict.
- `2026-06-03 19:33:07 CEST` - Role: Reviewer completed. Files inspected since last update: completed draft plan. Decision/blocker: plan is sufficient as-is; no structural blocker found. Next action: Arbiter will classify reviewer findings and decide whether a patch loop is needed.
- `2026-06-03 19:33:07 CEST` - Role: Reviewer started. Files inspected since last update: completed draft plan and mandatory-section ledger. Decision/blocker: no blocker; review will check simulator closure, edited-text proof, direct tests, known failure handling, and scope guard. Next action: complete sufficiency review.
- `2026-06-03 19:30:58 CEST` - Role: Planner completed. Files inspected since last update: no new files; draft built from Evidence Collector findings. Decision/blocker: no blocker; plan keeps implementation to text-only restored composer id/timestamp reuse and requires simulator-backed proof before closure. Next action: Reviewer will check closure bar, test contract, simulator gate, source freshness, and scope guard.

## Evidence Collector Findings

- The active session contract is `text-continuation-id`: make restored text-only composer continuation reuse the failed row's original `messageId` and timestamp when the user continues the same failed send, while edited text remains a new message.
- `text-retry-ui` is already landed in current code: `GroupConversationScreen` has `onRetryFailedMessage`, text-only failed row gating, and `LetterCard.onRetryFailedMessage`; `GroupConversationWired` passes `_onRetryFailedMessage`.
- `GroupConversationWired` already has continuation machinery, but it is still named and applied as media-only: `_RestoredGroupMediaContinuation`, `_restoredMediaContinuation`, `_resolveRestoredMediaContinuationForSend`, `_trackRestoredMediaContinuation`, and `_clearRestoredMediaContinuationTracking`.
- `_onSend` already consumes a restored continuation by using `restoredContinuation?.messageId` and `restoredContinuation?.timestamp`; it then passes both into `sendGroupMessage`.
- `_onDraftChanged` clears continuation tracking when the current draft diverges from the restored draft, which is the existing edited-content guard.
- `_restoreComposerSnapshot` restores text and quote for all failures, marks the row failed, but calls `_trackRestoredMediaContinuation` only when `snapshot.pendingAttachments.isNotEmpty`; the text-only `else` clears tracking. This is the direct implementation gap.
- `send_group_message_use_case.dart` already protects id reuse with `_canReuseOutgoingMessageId`: existing row must be outgoing, `sending` or `failed`, same group/sender/text/quote, and same timestamp. `_resolveOutgoingMessageId` treats any mismatch as a collision and asks `messageIdFactory` for a fresh id.
- Existing tests already cover in-place failed text retry (`retry_failed_group_messages_use_case_test.dart`) and targeted group wired text retry (`group_conversation_wired_test.dart`), plus media restored composer id reuse. They do not cover restored text-only composer continuation or the edited-text new-id path.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define `./scripts/run_test_gates.sh groups` as the named gate for group send/retry changes.
- `$run-flutter-reliability-sims` list mode resolved devices and showed `integration_test/group_recovery_e2e_test.dart` as group reliability command `#8`; no listed scenario specifically proves failed text-only restored composer continuation, so this session's closure must add or extend a narrow simulator-backed proof before claiming full closure.
- Known carry-forward broad-gate residual remains unrelated unless it changes shape: `./scripts/run_test_gates.sh groups` fails in `test/features/groups/integration/invite_round_trip_test.dart`, test `GCA-004 bridgeError recovery drains inbox after settled materialized invite`, at `invite_round_trip_test.dart:2930` with `Expected: not null`, `Actual: <null>`.

## Reviewer Findings

- Sufficiency verdict: sufficient as-is.
- Missing files, tests, regressions, or gates: none structurally. The plan names the production seam, direct host regressions, existing retry/media guard tests, named groups gate, simulator list pass, and a `$run-flutter-reliability-sims` group closure command.
- Stale or incorrect assumptions: none found. The plan explicitly treats the source doc's "no group text retry" statement as stale after `text-retry-ui`.
- Overengineering: none found. The plan rejects DB, dedup, bridge timeout, voice, media upload retry, and final matrix work.
- Decomposition quality: sufficient. The executor can make one narrow `GroupConversationWired` behavior change and add focused tests without inventing architecture.
- Minimum needed to make the plan sufficient: no mandatory changes.
- Checklist/session-contract parity: covered. Same failed text id reuse, same timestamp reuse, edited text fresh id, send-use-case guard, existing retry preservation, simulator closure, and known-failure handling each have planned proof or an accepted difference.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: helper renaming from media-specific to composer-neutral is optional; extending `integration_test/group_recovery_e2e_test.dart` is preferred but a new classified simulator file is acceptable if the existing file cannot host the proof cleanly.
- Accepted differences: unchanged draft only means exact restored text/quote/attachment state with no edit event; voice/media/timeout/local-status/dedup/final-doc closure remain separate sessions.
- Final verdict: execution-ready. No patch loop required.

## real scope

Change only restored-composer continuation behavior for failed outgoing group text-only sends:

- A failed text-only row whose composer snapshot is restored can reuse its original `messageId` and original timestamp when the user sends the unchanged restored draft in the same group with the same quote state.
- Edited restored text, quote changes, attachment changes, incoming rows, non-failed rows, and rows whose stored text/timestamp no longer match must remain new sends with fresh ids.
- Keep the already-landed text in-place retry UI and retry use case behavior unchanged.
- Keep media restored continuation behavior unchanged except for local helper naming if the executor chooses to rename media-specific helpers to composer-neutral names.

Do not change voice, media upload retry, bridge timeout values, local status broadcasts, database schema or migrations, receive-side live/replay dedup, notification behavior, final source-doc closure, or matrix closure.

## closure bar

This session is good enough when:

- A regression fails before the implementation and passes after it, proving same-text restored text-only retry publishes under the original failed row id and timestamp.
- A separate regression proves edited restored text creates a new message id and does not overwrite the original failed row.
- A `sendGroupMessage` guard regression proves an explicit old failed-row id with mismatched text or timestamp is treated as a collision and resolved to a fresh id.
- Existing text retry and media restored-continuation tests still pass.
- The group simulator closure rule is satisfied by adding or extending a narrow simulator-backed group scenario, preferably in the already-classified `integration_test/group_recovery_e2e_test.dart`, and running it through `$run-flutter-reliability-sims`.
- `./scripts/run_test_gates.sh groups` is run and interpreted against the known carry-forward `GCA-004` invite residual. The session may close with explicit follow-up only if the groups gate failure is exactly that known unrelated failure and all direct/simulator tests for this session pass.

Coverage ledger for the session contract:

| Requirement | Planned proof |
|---|---|
| Failed text-only restored composer can reuse original `messageId` | New `group_conversation_wired_test.dart` regression inspects stored rows and publish payload ids after fail-then-same-text send. |
| Failed text-only restored composer can reuse original timestamp | Same widget regression captures failed row timestamp and asserts the resent stored row and publish payload retain it. |
| Edited text remains a new message | New widget regression edits the restored draft before sending and asserts old failed row remains under the old id while a new sent row uses a different id. |
| Send use-case guard does not blindly reuse stale explicit ids | New `send_group_message_use_case_test.dart` regression for mismatched restored text/timestamp resolving to `messageIdFactory` id. |
| Current in-place text retry remains intact | Existing `retry_failed_group_messages_use_case_test.dart` and `group_conversation_wired_test.dart` targeted retry tests rerun. |
| Simulator-backed group closure is not skipped | Extend/add a narrow group simulator proof and run `run_with_devices.sh group --only integration_test/group_recovery_e2e_test.dart`. |

## source of truth

- Current code and direct tests are authoritative where the June 2026 source prose is stale.
- The active session contract is the `text-continuation-id` row in `01-P0-duplicate-delivery-cascade-session-breakdown.md`.
- Product intent and non-goals come from `01-P0-duplicate-delivery-cascade.md`, corrected by current code and the previous `text-retry-ui` closure.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define the named gates; if they disagree, the script wins.
- `$run-flutter-reliability-sims` rules require simulator-backed closure for group messaging behavior; host widget/application tests are not enough for final closure.

## session classification

implementation-ready

## exact problem statement

Current group text failure handling restores the failed text into the composer, but `_restoreComposerSnapshot` clears restored continuation tracking when there are no pending attachments. If the user sends that restored unchanged text, `_onSend` generates a fresh UUID and fresh timestamp, creating a second logical message instead of continuing the failed row. Recipients dedupe by `messageId`, so a late delivery of the original failed send plus the retyped fresh-id send can materialize as duplicates.

The user-visible improvement is that continuing the same restored failed text send should stay id-stable. Edited restored text must remain an intentional new message. The existing in-place retry button, failed-media retry behavior, and send-use-case collision guard must stay unchanged.

## files and repos to inspect next

Production:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`

Direct tests:

- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`

Simulator/gate references:

- `integration_test/group_recovery_e2e_test.dart`
- `/Users/I560101/.codex/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

Read-only references only if needed:

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`

## existing tests covering this area

- `test/features/groups/presentation/group_conversation_wired_test.dart` has `retry control re-sends the targeted failed outgoing text row`, proving the previous session's text retry callback path calls `retryFailedGroupMessage` and refreshes the row.
- `test/features/groups/presentation/group_conversation_wired_test.dart` has `GIRD-002 restored media composer continuation reuses the failed group row id`, proving the media restored continuation pattern this session should mirror for text-only.
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` has `retries a text-only failed row in place using the original ids`, proving application-level text retry id stability already exists.
- `test/features/groups/application/send_group_message_use_case_test.dart` has `message id collision guard still allows failed retry in place`, proving same text and timestamp can reuse a failed id.
- Missing: restored text-only composer same-text resend, edited restored text fresh-id behavior, and simulator-backed text continuation proof.

## regression/tests to add first

Add these before production changes:

- `test/features/groups/presentation/group_conversation_wired_test.dart`: `restored text-only composer continuation reuses the failed group row id`
  - Arrange a group with active members and a sequential bridge whose first `group:publish` fails and second succeeds.
  - Send a text-only draft through `GroupConversationScreen.onSend`.
  - Assert a single failed row exists, capture its id and timestamp, and assert the text is restored into the composer.
  - Send the unchanged restored text.
  - Assert only one row exists for that text, the row id is the original id, timestamp is the original timestamp, status is `sent`, and both publish payloads used the original id and timestamp.
- `test/features/groups/presentation/group_conversation_wired_test.dart`: `editing restored text-only composer continuation creates a new group row id`
  - Use the same fail-then-success setup.
  - After the failed text is restored, edit the draft through the real draft-change path (`tester.enterText` or `GroupConversationScreen.onDraftChanged`) before sending.
  - Assert the original row remains failed under the original id and the edited row is sent under a different id. This proves edited text is a new message.
- `test/features/groups/application/send_group_message_use_case_test.dart`: `message id collision guard treats edited restored failed text as a new message`
  - Pre-save a failed outgoing row.
  - Call `sendGroupMessage` with the old `messageId` but mismatched text or timestamp and a deterministic `messageIdFactory`.
  - Assert the old row is not overwritten and the new row uses the factory id. This is a guard test; it may already pass before the UI fix.
- `integration_test/group_recovery_e2e_test.dart`: add or extend one narrow simulator-backed test for failed text restored continuation. Prefer extending this existing classified file to avoid new gate-definition churn. If implementation evidence proves this file cannot exercise the required UI/send journey without broad harness work, add the smallest new simulator test file and update `Test-Flight-Improv/test-gate-definitions.md` plus `./scripts/run_test_gates.sh completeness-check`.

## step-by-step implementation plan

1. Add the host widget and application regressions above. Confirm the same-text restored text widget regression fails before production changes; if it already passes, stop and reclassify the session as `stale/already-covered` with evidence.
2. In `group_conversation_wired.dart`, generalize the restored continuation concept from media-only to composer continuation. Either rename `_RestoredGroupMediaContinuation` and related helpers to composer-neutral names, or keep names if the executor chooses the smallest diff; behavior matters more than naming.
3. In `_restoreComposerSnapshot`, after persisting the failed row:
   - For snapshots with pending attachments, preserve existing cleanup and tracking behavior.
   - For text-only snapshots with non-empty restored draft text, track a continuation using the failed row's `messageId`, stored timestamp, restored text, restored quote id, and an empty attachment fingerprint.
   - For empty text with no attachments, clear tracking.
4. Keep `_resolveRestored...ForSend` strict: group id, draft text, quote id, attachment fingerprint, outgoing row, `failed` status, stored text, stored quote, and stored timestamp must all match before it returns a continuation.
5. Keep `_onDraftChanged` clearing continuation when the draft diverges from the restored text. Quote or attachment changes should also fail the existing match check and create a fresh send.
6. Do not weaken `_canReuseOutgoingMessageId`. Only touch `send_group_message_use_case.dart` if the new guard regression exposes an actual missing guard.
7. Add the simulator-backed proof in the narrowest existing group reliability file. Prefer `integration_test/group_recovery_e2e_test.dart` and a test name that makes the text continuation journey explicit.
8. Run formatting, direct tests, simulator command, and named gate. Classify any `./scripts/run_test_gates.sh groups` failure using the known-failure rules below.

## risks and edge cases

- Edited text accidentally reuses the original id. The edit-path widget test and send-use-case guard test catch this.
- Quote state changes reuse the original id. The continuation match includes `quotedMessageId`; include quote state in the same-text test setup only if needed, but do not add broad quote-feature work.
- Media restored continuation regresses while generalizing names. Rerun the existing GIRD-002 media restored continuation test and the full wired suite.
- A late self-echo settles the failed row while the composer is restored. Existing `_clearRestoredComposerAfterSettledContinuation` handles non-failed rows; do not change it except for helper renaming.
- Stale continuation leaks across groups or rows. Existing group id and row lookup checks must remain.
- Simulator proof could balloon. If an existing integration file cannot host a narrow proof, add the smallest new simulator test and classify it; do not broaden into multi-party acceptance or notification matrices.

## exact tests and gates to run

Formatting:

```bash
dart format --output=none --set-exit-if-changed lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/application/send_group_message_use_case_test.dart integration_test/group_recovery_e2e_test.dart
```

Focused direct tests:

```bash
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "restored text-only composer continuation reuses the failed group row id"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "editing restored text-only composer continuation creates a new group row id"
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "message id collision guard treats edited restored failed text as a new message"
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "retries a text-only failed row in place using the original ids"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GIRD-002 restored media composer continuation reuses the failed group row id"
```

Direct suites:

```bash
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/groups/application/send_group_message_use_case_test.dart
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart
```

Simulator-backed group closure:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart
```

Named gate:

```bash
./scripts/run_test_gates.sh groups
```

If a new simulator test file is added instead of extending `integration_test/group_recovery_e2e_test.dart`, also run:

```bash
./scripts/run_test_gates.sh completeness-check
```

## known-failure interpretation

Known unrelated residual:

```text
./scripts/run_test_gates.sh groups
test/features/groups/integration/invite_round_trip_test.dart
GCA-004 bridgeError recovery drains inbox after settled materialized invite
invite_round_trip_test.dart:2930
Expected: not null
Actual: <null>
```

Interpretation:

- If all focused tests, direct suites, and the simulator proof pass, and `./scripts/run_test_gates.sh groups` fails only with the exact `GCA-004` assertion above, record it as a pre-existing broad-gate residual and do not fix it in this session.
- Any failure in `group_conversation_wired_test.dart`, `send_group_message_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart`, the new/extended simulator proof, or any new/different groups-gate failure is a session regression until proven otherwise.

## done criteria

- `group_conversation_wired.dart` tracks restored continuation for failed text-only snapshots and reuses original id/timestamp only for unchanged restored text.
- Edited restored text, quote mismatch, attachment mismatch, incoming rows, settled rows, and textless/no-attachment rows do not reuse the old id.
- Existing failed text in-place retry behavior remains unchanged.
- Existing media restored continuation behavior remains unchanged.
- New host regressions pass.
- Existing direct suites listed above pass.
- The simulator-backed group proof runs through `$run-flutter-reliability-sims` and passes, or the executor records a concrete device/harness blocker and does not claim full closure.
- `./scripts/run_test_gates.sh groups` is run and either passes or fails only with the known `GCA-004` residual.

Coverage ledger:

| Contract item | Done evidence |
|---|---|
| Same failed text continues with same `messageId` | Passing focused widget regression plus publish-payload assertion. |
| Same failed text continues with same timestamp | Passing focused widget regression plus stored row/payload timestamp assertion. |
| Edited text is new | Passing edited-text widget regression and send-use-case guard regression. |
| Previous text retry remains accepted | Passing targeted retry focused test and retry use-case suite. |
| Simulator closure | Passing `run_with_devices.sh group --only integration_test/group_recovery_e2e_test.dart` or concrete blocker recorded. |

## scope guard

Non-goals:

- No voice retry/upload-pending/re-record work.
- No media retry semantic changes beyond preserving existing restored-media behavior.
- No bridge timeout changes.
- No local status broadcast or background sweep changes.
- No database columns, migrations, or schema work.
- No receive-side dedup, notification, APNs, or live/replay changes.
- No final source-doc or notification-matrix closure.
- No fix for the known `GCA-004` invite-round-trip failure.

Overengineering signals:

- Adding a persistent continuation table or DB column.
- Introducing content-hash or body-text dedup for text sends.
- Changing recipient dedup rules.
- Reworking the entire composer state model.
- Adding a broad multi-party harness when a focused host widget plus existing simulator file can prove this slice.

## accepted differences / intentionally out of scope

- In-place failed text retry remains the preferred recovery path from the previous session; this session only fixes the restored-composer fallback path when the user sends the unchanged restored draft.
- A draft edit clears continuation tracking, matching current media behavior. If the user edits and later manually reverts to the original text after tracking has been cleared, treating that as a new send is acceptable for this session unless current code already supports safe re-matching without extra scope.
- Voice is intentionally separate because it uses `_onRecordStop()` rather than `_onSend`.
- Final proposal, gate-definition matrix, notification matrix, and whole-program verdict updates remain owned by `acceptance-doc-closure`, except a narrow gate-definition classification if this session must add a new simulator test file.

## dependency impact

- `acceptance-doc-closure` depends on this session to claim the text restored-composer duplicate path is closed.
- Later sessions for voice, timeout/pending retry payloads, local status broadcasts, status timestamp migration, and live/replay dedup should not depend on implementation details here beyond the guarantee that unchanged restored text either reuses the failed row id/timestamp or is explicitly blocked with evidence.
- If implementation proves this behavior is already covered or infeasible without broader composer architecture work, update this plan's classification and have downstream sessions skip any assumption that text continuation is closed.
