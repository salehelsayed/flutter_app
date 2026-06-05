Status: accepted_with_explicit_follow_up

# Voice ID Stable Retry Session Plan

## Final Execution Output

- Execution verdict: `accepted_with_explicit_follow_up`.
- Spawned-agent isolation used: yes. Executor child `019e8eb7-8809-77b0-9fb2-ea2ee63c5b36` was spawned with `model: gpt-5.5`, `reasoning_effort: xhigh`, produced scoped code/test deltas, then remained active past the bounded wait plus extension and was closed before controller-side verification recovery. QA Reviewer child `019e8ece-9feb-79e2-a924-abbd45468556` was spawned separately with `model: gpt-5.5`, `reasoning_effort: xhigh`, and returned `accepted_with_explicit_follow_up`.
- Local sequential fallback used: yes, for Executor verification recovery only after the nested Executor did not materialize a final summary. QA remained isolated in a separate spawned child.
- Files changed for this session: `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`, `integration_test/group_recovery_e2e_test.dart`, and this plan file. Existing unrelated dirty worktree files were preserved and not counted as session-owned work.
- Tests added or updated: uploaded-audio same-id retry proof, message-scoped voice `upload_pending` retry proof, wired-screen upload-pending voice retry proof, durable voice prep cleanup proof, voice re-record continuation same-id proof, background-task protection proof for manual upload-pending voice retry, and a simulator-backed `failed voice re-record keeps one sender and receiver row id` scenario.
- Exact tests and gates run:
  - `dart format --output=none --set-exit-if-changed lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/application/retry_failed_group_messages_use_case_test.dart test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart integration_test/group_recovery_e2e_test.dart` passed with `Formatted 7 files (0 changed)`.
  - `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart` passed with `+15`.
  - `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` passed with `+19`.
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` passed with `+110`.
  - `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` passed with `+19`.
  - `./scripts/run_test_gates.sh groups` exited `1` only with the known carried `GCA-004 bridgeError recovery drains inbox after settled materialized invite` residual in `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`.
  - `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` resolved one-device simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, ran command `#8`, and passed with `+7`.
  - `git diff --check` passed.
- QA verdict: `accepted_with_explicit_follow_up`.
- Blocking issues remaining: none.
- Residual / non-blocking follow-up: carry forward known unrelated `GCA-004` broad-gate residual. Optional hardening later may add a dedicated wired-screen done-audio retry proof, but QA accepted the current use-case same-id proof plus generic wired media retry coverage as sufficient for this session.
- Session ready for closure: yes.

## Planning Progress

- 2026-06-03 20:18:13 CEST | Role: Arbiter completed | Files inspected since last update: reviewer pass and plan draft only | Decision/blocker: no structural blockers remain; incremental simulator-command detail accepted; plan is execution-ready | Next action: downstream execution/QA child may implement this session only.
- 2026-06-03 20:17:46 CEST | Role: Reviewer completed; Arbiter started | Files inspected since last update: plan draft only | Decision/blocker: no structural blocker; plan is sufficient with one incremental note that the simulator command may run the whole `group_recovery_e2e_test.dart` file while focused host proofs stay direct | Next action: classify reviewer findings and finalize execution readiness.
- 2026-06-03 20:14:12 CEST | Role: Planner completed; Reviewer started | Files inspected since last update: no new files; draft written from collected evidence | Decision/blocker: no blocker; draft maps all four voice contract items to direct regressions and includes a simulator-backed closure gate | Next action: review for missing files, stale assumptions, over-scope, and gate sufficiency.
- 2026-06-03 20:14:12 CEST | Role: Evidence Collector completed; Planner started | Files inspected since last update: `group_conversation_wired.dart` voice/retry/continuation/build ranges, retry failed/incomplete upload use cases, direct voice/retry tests, `group_recovery_e2e_test.dart`, `test-gate-definitions.md`, `scripts/run_test_gates.sh` | Decision/blocker: no blocker; draft can target a message-scoped upload retry seam, uploaded-voice same-id proof, pre-send cleanup, and a narrow simulator extension | Next action: draft mandatory plan sections, closure bar, regression contract, residual interpretation, and simulator/host gate requirements.
- 2026-06-03 20:12:02 CEST | Role: Evidence Collector in progress | Files inspected since last update: source doc, session breakdown, gate/simulator file discovery, broad retry/voice search output | Decision/blocker: no blocker; source confirms scope is recorded-voice stable retry/upload recovery and carried `GCA-004` must be treated as broad-gate residual | Next action: inspect current voice/retry code ranges, direct test fixtures, and named/simulator gate sources.

## Execution Progress

- 2026-06-03 20:48:15 CEST | Phase: parent controller heartbeat during QA wait | Files inspected or touched: this plan | Command running: QA Reviewer child `019e8ece-9feb-79e2-a924-abbd45468556` remains active | Decision/blocker: no blocker; no QA findings have been returned yet and closure is not being advanced without a review verdict | Next action: continue bounded wait for QA findings, then either accept execution or run the next fix-pass according to the execution/QA orchestrator.
- 2026-06-03 20:35:57 CEST | Phase: simulator proof added and format check passed | Files inspected or touched: `integration_test/group_recovery_e2e_test.dart`, edited Dart files, this plan | Command running: none | Decision/blocker: no blocker; added `failed voice re-record keeps one sender and receiver row id` simulator smoke and extended the mirroring bridge to carry media; direct `flutter test integration_test/group_recovery_e2e_test.dart --plain-name "failed voice re-record keeps one sender and receiver row id"` did not execute because Flutter required an explicit device among many connected devices, so simulator execution remains assigned to the required `run_with_devices.sh` command; `dart format --output=none --set-exit-if-changed lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/application/retry_failed_group_messages_use_case_test.dart test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart integration_test/group_recovery_e2e_test.dart` passed with 0 changed | Next action: run the four full direct suites serially.
- 2026-06-03 20:37:19 CEST | Phase: Executor child closed; controller verification recovery started | Files inspected or touched: this plan, `git status --short`, scoped diff/stat | Command running: none | Decision/blocker: Executor child remained running after the allowed bounded waits and was closed; repo contains scoped voice code/test/doc deltas plus focused GREEN entries, but no child final summary, so controller will verify exact required commands before QA instead of respawning blind | Next action: inspect landed diff for scope/compile shape, run full direct suites, group gate, simulator wrapper, `dart format --output=none --set-exit-if-changed`, and `git diff --check`, then spawn QA if evidence is sufficient.
- 2026-06-03 20:38:11 CEST | Phase: controller verification started | Files inspected or touched: scoped production/test diff for voice retry, this plan | Command running: `dart format --output=none --set-exit-if-changed lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/application/retry_failed_group_messages_use_case_test.dart test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart integration_test/group_recovery_e2e_test.dart` followed by the four full direct suites | Decision/blocker: pending verification; scoped diff appears within `voice-id-stable-retry` and no new schema/wire/doc-closure scope found | Next action: record exact format/direct-suite outcomes before named gate.
- 2026-06-03 20:39:35 CEST | Phase: format and full direct suites passed; named gate starting | Files inspected or touched: edited Dart files and direct test outputs | Command running: `./scripts/run_test_gates.sh groups` | Decision/blocker: no blocker in direct evidence; passed `dart format --output=none --set-exit-if-changed lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/application/retry_failed_group_messages_use_case_test.dart test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart integration_test/group_recovery_e2e_test.dart` with `Formatted 7 files (0 changed)`; passed `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart` (+15); passed `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` (+19); passed `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` (+110); passed `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` (+19) | Next action: classify `groups` gate; if it fails, write pending-triage entry before focused reproduction.
- 2026-06-03 20:41:09 CEST | Phase: groups gate failed; triage starting | Files inspected or touched: `/tmp/voice-id-stable-retry-groups.log`, this plan | Failing gate command: `./scripts/run_test_gates.sh groups 2>&1 | tee /tmp/voice-id-stable-retry-groups.log` exited 1 | Failing file/test name if known: live output indicates `test/features/groups/integration/group_messaging_smoke_test.dart`, `Multi-user group messaging smoke tests GE-017 seeded random membership operations preserve invariants`; this is not the known allowed `GCA-004` residual | Exact focused triage command about to run: inspect `/tmp/voice-id-stable-retry-groups.log` for the assertion, then run `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "GE-017 seeded random membership operations preserve invariants"` | Decision/blocker: `pending_triage` | Next action: classify as pre-existing/flaky/session-owned based on focused reproduction and log details.
- 2026-06-03 20:42:08 CEST | Phase: groups gate classified; simulator gate starting | Files inspected or touched: `/tmp/voice-id-stable-retry-groups.log`, `run-flutter-reliability-sims` skill, this plan | Command running: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` | Decision/blocker: `./scripts/run_test_gates.sh groups 2>&1 | tee /tmp/voice-id-stable-retry-groups.log` exited 1 only with the exact known carried residual `GCA-004 bridgeError recovery drains inbox after settled materialized invite` in `test/features/groups/integration/invite_round_trip_test.dart` at `invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`; no other `[E]` markers found, so no session-owned groups-gate failure | Next action: run required simulator wrapper and classify pass/failure.
- 2026-06-03 20:44:25 CEST | Phase: simulator gate passed; final local checks starting | Files inspected or touched: `/tmp/voice-id-stable-retry-group-sim.log`, this plan | Command running: `git diff --check` | Decision/blocker: no simulator blocker; `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` resolved one-device simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, ran command `#8`, and passed `integration_test/group_recovery_e2e_test.dart` with `+7` and final `PASS: reliability simulations completed for scope: group` | Next action: run `git diff --check`, inspect final scoped diff/status, then spawn QA Reviewer.
- 2026-06-03 20:45:20 CEST | Phase: QA Reviewer spawn pending | Files inspected or touched: scoped `git diff --stat`, `git status --short`, this plan | Command running: none | Decision/blocker: `git diff --check` passed; scoped voice session diff is limited to `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, and `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`; unrelated dirty files remain preserved | Next action: spawn fresh QA Reviewer child with `model: gpt-5.5`, `reasoning_effort: xhigh`.
- 2026-06-03 20:46:13 CEST | Phase: QA Reviewer spawned/running | Files inspected or touched: this plan | Command running: spawned QA Reviewer child `019e8ece-9feb-79e2-a924-abbd45468556` (`Einstein`) | Decision/blocker: no blocker; QA owns sufficiency review only and must not edit files | Next action: bounded wait for QA findings, then either finish or run a fix-pass if QA finds blocking issues.
- 2026-06-03 20:50:46 CEST | Phase: QA completed; final verdict written | Files inspected or touched: QA child result, this plan | Command running: none | Decision/blocker: final execution/QA verdict is `accepted_with_explicit_follow_up`; QA found no blocking issues, classified `GCA-004` as residual-only, and noted optional dedicated wired done-audio retry proof as non-blocking because use-case same-id and generic wired media retry coverage already exist | Next action: closure child may run next for session closure evidence; do not update whole-doc final verdict here.
- 2026-06-03 20:33:16 CEST | Phase: focused host regressions green after implementation | Files inspected or touched: focused test outputs, this plan | Command running: none | Decision/blocker: no blocker; passed serial focused commands: `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "message-scoped voice upload retry reuploads and resends only that failed row"`, `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "upload-pending failed voice retry uploads and publishes the same row immediately"`, `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "voice durable prep failure leaves no empty failed row or pending upload dir"`, `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "voice re-record after retryable publish failure reuses the failed row id"`, `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart --plain-name "upload-pending failed voice retry is background-task protected"`, and rerun `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "retries a failed uploaded audio row with the original message id and timestamp"` | Next action: add the narrow simulator-backed voice same-id proof in `integration_test/group_recovery_e2e_test.dart`, format edited Dart, then run full direct suites.
- 2026-06-03 20:32:11 CEST | Phase: scoped production implementation added | Files inspected or touched: `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, this plan | Command running: none | Decision/blocker: no blocker; incomplete-upload retry now accepts an optional `messageId` filter, failed audio upload-pending retry invokes that targeted path inside a background task, voice prep failure cleans generated unsent artifacts, uploaded voice attachment state is persisted before publish, and immediate re-record can reuse a verified failed voice row id/timestamp | Next action: rerun the focused voice regressions serially and fix compile or behavior gaps.
- 2026-06-03 20:28:52 CEST | Phase: focused regression baseline captured | Files inspected or touched: focused test outputs, this plan | Command running: none | Decision/blocker: no blocker; `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "retries a failed uploaded audio row with the original message id and timestamp"` passed, `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "message-scoped voice upload retry reuploads and resends only that failed row"` failed at compile time with missing `messageId` parameter as expected, `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "voice durable prep failure leaves no empty failed row or pending upload dir"` failed because no pending-upload cleanup ran, and two concurrent widget focused commands hit Flutter native-asset build conflicts rather than product assertions | Next action: implement the message-scoped upload retry, wired voice retry branch, prep cleanup, and voice re-record continuation, then rerun focused commands serially.
- 2026-06-03 20:28:07 CEST | Phase: voice regressions added before production edits | Files inspected or touched: `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`, this plan | Command running: none | Decision/blocker: no blocker; tests now pin uploaded-audio same-id retry, message-scoped upload-pending voice retry, wired immediate upload retry, durable-prep cleanup, re-record continuation, and background-task ordering; the use-case test intentionally references the planned `messageId` filter before production support exists | Next action: run focused regression names to capture current failures, then implement scoped production changes.
- 2026-06-03 20:21:30 CEST | Phase: Executor started and contract re-read | Files inspected or touched: this plan, session breakdown, source doc, dirty worktree snapshot, `group_conversation_wired.dart` diff, `group_conversation_wired_test.dart` diff, `integration_test/group_recovery_e2e_test.dart` diff, retry/voice search output | Command running: none | Decision/blocker: no blocker; preserving prior `text-retry-ui`, `text-continuation-id`, untracked plan/breakdown docs, and unrelated `info.plist` change; starting tests-first work for `voice-id-stable-retry` only | Next action: inspect the focused retry/upload/voice test fixtures and add voice-specific regressions before production edits.
- 2026-06-03 20:26:28 CEST | Phase: Executor bounded wait extended | Files inspected or touched: this plan, `git status --short`, scoped diff/stat | Command running: child `019e8eb7-8809-77b0-9fb2-ea2ee63c5b36` still active | Decision/blocker: no blocker yet; first wait timed out, but plan heartbeat shows assigned-step progress, so one additional bounded wait is allowed | Next action: wait once more for Executor completion, then inspect evidence and either spawn QA or classify child progress failure.
- 2026-06-03 20:20:23 CEST | Phase: contract extracted; Executor spawn pending | Files inspected or touched: this plan, session breakdown, execution orchestrator skill, `scripts/run_test_gates.sh` discovery output | Command running: none | Decision/blocker: no blocker; scope is only `voice-id-stable-retry`, required tests/gates and known `GCA-004` residual are explicit | Next action: spawn fresh Executor child with `model: gpt-5.5`, `reasoning_effort: xhigh`.
- 2026-06-03 20:20:59 CEST | Phase: Executor spawned/running | Files inspected or touched: this plan | Command running: spawned Executor child `019e8eb7-8809-77b0-9fb2-ea2ee63c5b36` (`Ampere`) | Decision/blocker: no blocker; child owns tests-first implementation and required gate evidence | Next action: bounded wait for Executor completion before QA spawn.

## Closure Progress

- 2026-06-03 20:54 CEST | Role: Completion Auditor completed | Files inspected: this plan, session breakdown, source proposal references, scoped execution diff/stat, and session-owned voice retry/upload tests. Decision/blocker: landed code and tests satisfy the voice retry contract; the only non-green named gate evidence is the carried `GCA-004` broad-gate residual, outside this session's owner files and behavior. Next action: write closure evidence into this plan and the breakdown ledger.
- 2026-06-03 20:54 CEST | Role: Closure Writer completed | Files touched: this plan and `01-P0-duplicate-delivery-cascade-session-breakdown.md`. Decision/blocker: recorded `accepted_with_explicit_follow_up` for `voice-id-stable-retry`, carried `GCA-004` as residual-only, and left whole-doc final verdict unset because later sessions remain pending. Next action: closure reviewer pass.
- 2026-06-03 20:54 CEST | Role: Closure Reviewer completed | Files inspected: patched plan and breakdown diff. Decision/blocker: no overclaim found; docs describe session closure, residual gate evidence, accepted optional hardening, and remaining sessions without reopening product scope. Next action: parent controller may continue to `timeout-pending-retry`.

## Closure Verdict

Verdict: `accepted_with_explicit_follow_up`.

Closed for this session:

- Uploaded failed voice rows with done audio attachments have explicit same-id retry coverage: retry publishes the original `messageId` and timestamp and updates one existing row.
- Failed outgoing voice rows with `upload_pending` audio now use a message-scoped upload retry path from the failed-media action, re-drive only that row's upload, then publish the same `messageId` after upload success.
- Manual upload-pending voice retry is background-task protected and refreshes the target row/media after retry.
- Durable voice prep failures clean up generated unsent state instead of leaving an empty retry-less failed row or orphan pending-upload directory.
- Immediate voice re-record after a retryable voice failure can reuse the failed row's `messageId` and timestamp through a narrow in-memory continuation guard.
- The simulator-backed group recovery proof now covers one sender row id and one receiver materialization for the voice re-record same-id path.

Verification recorded by execution:

- `dart format --output=none --set-exit-if-changed ...` passed with `Formatted 7 files (0 changed)`.
- Full direct suites passed: `retry_failed_group_messages_use_case_test.dart` (`+15`), `retry_incomplete_group_uploads_use_case_test.dart` (`+19`), `group_conversation_wired_test.dart` (`+110`), and `group_conversation_wired_bg_task_test.dart` (`+19`).
- `./scripts/run_test_gates.sh groups` exited `1` only with the known carried `GCA-004` residual at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` passed on one-device simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, command `#8`, with `+7`.
- `git diff --check` passed.

Residual-only / explicit follow-up:

- The broad `groups` gate still carries `GCA-004 bridgeError recovery drains inbox after settled materialized invite` in `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`. This remains outside `voice-id-stable-retry` and is carried forward for the parent controller or a later acceptance/gate session.
- Optional hardening only: a dedicated wired-screen done-audio retry proof can be added later if desired. QA accepted the current use-case same-id proof plus generic wired media retry coverage as sufficient, so this is not a blocking residual.

Still open outside this session:

- `timeout-pending-retry`, `local-status-broadcasts`, `status-timestamp-migration`, `live-replay-dedup`, and `acceptance-doc-closure` remain pending.
- The source proposal, final notification matrix, gate-definition final classification, and final whole-program verdict remain owned by `acceptance-doc-closure`.

Accepted differences:

- Non-voice `upload_pending` failed media may keep the existing pending-feedback behavior unless a later scoped session intentionally generalizes it with explicit non-regression tests.
- Voice continuation is intentionally in-memory and same-screen only; restart recovery remains owned by in-place failed-row retry and upload retry.
- If two different same-id voice byte streams race, recipients may keep whichever same-id delivery materializes first. The accepted contract is one logical voice message id and one bubble, not post-delivery byte replacement.
- No bridge timeout, pending retry-payload fallback, local status broadcast, DB schema/migration, receive-side live/replay dedup, notification behavior, source-doc final closure, or whole-program verdict changed here.

## real scope

This session owns only recorded-voice stable retry behavior in group conversations:

- Prove that a failed outgoing voice row whose audio attachment is already uploaded (`downloadStatus == 'done'`, `mediaType == 'audio'`) retries through the existing failed-media action with the original `messageId` and original timestamp.
- Change a failed outgoing voice row with `upload_pending` audio so tapping retry immediately re-drives that message's upload and then resends that same message id, instead of only showing the current pending-upload snackbar.
- Ensure pre-send durable voice prep failures do not leave an empty failed row with no retry affordance. The preferred behavior is cleanup: no empty local row, no orphan attachment, no owned pending-upload directory left behind, quote restored when applicable, and send flow released.
- Add a narrow in-memory voice re-record continuation guard so an immediate re-record after a retryable voice failure reuses the failed voice row's `messageId` and timestamp for that intended send.

This session does not change text retry, restored text continuation, reliable-send timeout values, pending retry-payload fallback, local status broadcasts, stuck-sending timestamp migration, receive-side live/replay dedup, notification behavior, or final matrix documentation.

## closure bar

Good enough for this session means every item below is covered by an independent proof:

| Contract item | Planned proof |
|---|---|
| Uploaded failed voice retries same id | Add/extend `retry_failed_group_messages_use_case_test.dart` and `group_conversation_wired_test.dart` to assert a failed audio row with done attachment publishes with the original `messageId` and timestamp, updates the existing row, and does not mint a second row. |
| `upload_pending` voice retry re-drives upload immediately | Add a message-scoped `retryIncompleteGroupUploads` proof and a wired-screen proof showing `onRetryFailedMedia(messageId)` for an audio pending row calls upload for that message only, preserves blob/attachment identity, publishes with the original `messageId` and timestamp after upload, refreshes hydrated media, and does not touch unrelated pending uploads. |
| Durable prep failure leaves no empty retry-less row | Add a voice stop test with a failing durable-prep seam that asserts no empty failed outgoing row remains, no orphan attachments remain for the generated id, the quote is restored when present, upload state clears, and the send guard releases. If current code already satisfies this, keep it as coverage and avoid production churn. |
| Re-record continuation keeps one stable id | Add a wired-screen regression where an immediate re-record after a retryable voice publish/upload failure consumes a voice continuation and sends under the original `messageId` and timestamp; local attachments for that id are replaced rather than duplicated. |
| User-visible group voice delivery does not duplicate | Extend a narrow group simulator proof, most likely in `integration_test/group_recovery_e2e_test.dart`, so a failed voice send followed by in-place retry or continuation produces one sender row id and one receiver materialization for the same id. Run it through `$run-flutter-reliability-sims`. |

Host tests prove the seams. The simulator proof is required for full closure because this is group messaging plus media delivery across sender/recipient instances. If simulators are unavailable during execution, the implementation can be accepted only with explicit simulator follow-up evidence, not called fully closed.

## source of truth

- Current production code and tests win over stale prose.
- Active session contract: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-breakdown.md`, session `voice-id-stable-retry`.
- Product/problem source: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`.
- Named gate source: `Test-Flight-Improv/test-gate-definitions.md`; it maps group send/retry changes to `./scripts/run_test_gates.sh groups`.
- Simulator closure source: `implementation-plan-orchestrator` reliability simulator rule; it overrides the breakdown's "optional simulator only if evidence shows" wording for final closure because this session touches group voice media delivery.

## session classification

`implementation-ready`

The implementation is narrow and evidence-backed. Closure is simulator-gated: host tests are necessary but not sufficient for a final "fully closed" verdict.

## exact problem statement

Group recorded voice currently uses `_onRecordStop()`, not `_onSend()`. Uploaded failed voice can likely retry through the existing media path, but there is no explicit voice same-id regression. A failed voice row whose attachment is still `upload_pending` currently enters `_onRetryFailedMedia`, refreshes media, shows `failed_media_upload_pending_retry`, and returns without re-uploading. `retryFailedGroupMessages` intentionally skips `upload_pending` media rows because `retryIncompleteGroupUploads` owns upload recovery, but that recovery only runs as a broad background sweep today.

The user-visible failure is that a sender can be pushed toward re-recording. Re-recording currently mints a fresh `messageId` and different audio bytes, so a late delivery of the first attempt can produce two distinct voice notes for recipients. This session must make the intended voice send keep one stable id and give the failed row a working in-place retry path.

What must stay unchanged: text sessions already closed, ordinary image/video media retry behavior unless required by a narrowly shared helper, group send wire format, DB schema, timeout policy, and notification docs.

## files and repos to inspect next

Production:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart` only if a repository contract change becomes unavoidable; the preferred plan does not require one.
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart` and `test/shared/fakes/in_memory_media_attachment_repository.dart` only if the implementation adds repository-level filtering; preferred plan filters inside the retry use case.

Tests:

- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md` read-only unless a new high-value test file is added.

## existing tests covering this area

- `group_conversation_wired_test.dart` already has voice stop/durable upload coverage: durable pending attachment creation, upload failure preserving retry data and quote, ACL membership at upload time, successful durable voice cleanup, zero-peer sent status, group-not-found cleanup, and quote restoration on upload/publish failure.
- `group_conversation_wired_test.dart` currently has a `GIRD-002 upload-pending failed-card retry shows pending feedback without publishing` test that pins the behavior this session must replace or narrow for audio rows.
- `retry_failed_group_messages_use_case_test.dart` already proves failed media rows with done attachments can retry and proves upload-pending rows are skipped by the failed-message retrier.
- `retry_incomplete_group_uploads_use_case_test.dart` already proves pending group uploads are re-uploaded, use blob ids, derive ACLs from active membership, skip invalid media, preserve done attachments, and abort the final send if the row was deleted or settled.
- `group_conversation_wired_bg_task_test.dart` already proves voice send is background-task protected; upload-pending manual retry should get equivalent protection if it performs upload plus publish work.
- `integration_test/group_recovery_e2e_test.dart` already has a simulator-backed restored text continuation proof and helper bridge that mirrors published group messages to a fake pubsub network; it likely needs media payload mirroring before it can prove voice.

## regression/tests to add first

Add these before production edits where feasible:

- `retry_failed_group_messages_use_case_test.dart`: failed outgoing audio row with done attachment retries once, publishes the original `messageId` and timestamp, carries the audio attachment id/media metadata, and marks the same row sent.
- `retry_incomplete_group_uploads_use_case_test.dart`: a new message-scoped retry path processes only the requested failed outgoing voice message's `upload_pending` attachment, preserves `blobId`, `durationMs`, `waveform`, ACLs, original `messageId`, and timestamp, and leaves unrelated pending uploads untouched.
- `group_conversation_wired_test.dart`: `onRetryFailedMedia` for an audio `upload_pending` failed row calls the message-scoped upload retry immediately and publishes the same id instead of showing only the pending snackbar; the existing non-audio pending-feedback behavior should remain pinned unless the implementation intentionally generalizes with tests.
- `group_conversation_wired_test.dart`: durable-prep failure does not leave an empty retry-less outgoing row or orphan attachment and restores quote state.
- `group_conversation_wired_test.dart`: immediate voice re-record after a retryable voice failure reuses the original voice row id/timestamp and replaces local attachments for that id.
- `group_conversation_wired_bg_task_test.dart`: upload-pending manual voice retry begins a background task before upload and ends it after publish/failure cleanup.
- `integration_test/group_recovery_e2e_test.dart`: failed voice retry or re-record continuation produces one sender row and one receiver row with the same id.

## step-by-step implementation plan

1. Add the uploaded-audio same-id regression. If it already passes with current `retryFailedGroupMessage`, keep the test and do not change that use case for done audio.
2. Add a message-scoped upload retry seam in `retry_incomplete_group_uploads_use_case.dart`. Preferred shape: add an optional `messageId` filter or a small `retryIncompleteGroupUploadForMessage(...)` wrapper that reuses the existing implementation and filters the existing `getUploadPendingAttachments()` result in memory. Do not change repository interfaces unless the existing API makes targeted retry impossible.
3. In `GroupConversationWired._onRetryFailedMedia`, detect failed outgoing voice rows with `upload_pending` audio attachments. For that case, run the targeted incomplete-upload retry with `widget.groupRepo`, `widget.msgRepo`, `widget.mediaAttachmentRepo`, `widget.bridge`, `widget.p2pService`, `widget.identityRepo`, `widget.uploadMediaFn`, and `widget.mediaFileManager`, then refresh the target media/message. Leave non-audio pending rows on existing pending-feedback behavior unless tests justify a safe shared generalization.
4. Wrap the manual upload-pending voice retry in the existing background task guard pattern so upload plus publish survives foreground interruptions consistently with `_onRecordStop()`.
5. Harden `_onRecordStop()` durable-prep catch so it cannot leave an empty failed row or orphan media if validation, copy, hash, attachment save, or pre-persist save fails. Cleanup should delete message/attachments/pending dir for that generated id and restore quote; no retry UI should be created for a recording that never produced durable bytes.
6. Add a narrow `_RestoredGroupVoiceContinuation` or equivalent state in `GroupConversationWired`. Track it only after retryable voice failures that produced a failed outgoing voice row. On the next record stop, if the same group/quote context still matches and the failed row is still retryable, consume the continuation and reuse its `messageId` and timestamp. Replace persisted attachments for that message id before saving the new voice attachment. Clear it on success, delete, in-place retry, group-not-found/dissolved/unauthorized cleanup, quote change, or if the row is missing/settled.
7. Extend the simulator helper bridge in `integration_test/group_recovery_e2e_test.dart` only as needed to mirror `media` payloads, then add the narrow voice proof. Do not broaden this file into full media fan-out acceptance.
8. Run focused tests first, then direct suites, then the named and simulator gates. Stop and re-scope if a test shows the current code already covers a listed item or if the implementation would require DB/schema/wire changes.

## risks and edge cases

- Upload retry must be message-targeted; a failed voice retry must not opportunistically process unrelated pending uploads.
- The existing incomplete-upload retrier has a global in-flight guard. A manual retry that collides with a background sweep may return 0; the UI should refresh and show failure/pending feedback without minting a new id.
- Re-recorded audio bytes may differ. Reusing the message id is intentional; whichever same-id delivery materializes first may be the one recipients keep. The closure requirement is one logical voice message, not byte replacement across already-delivered recipients.
- Deleting old attachments before a same-id re-record must not remove a successfully delivered/sent row. The continuation resolver must require a failed retryable row.
- Durable-prep cleanup must not delete unrelated attachments if the generated id collides unexpectedly; use the current generated/continuation message id only.
- Background task begin/end must run in finally blocks so upload failure, send failure, unmount, and bridge errors do not leak tasks.
- `upload_failed` terminal media should not be treated as retryable upload-pending voice.

## exact tests and gates to run

Focused direct tests after adding regressions:

```bash
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "<new uploaded voice same-id retry test>"
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "<new targeted voice upload-pending retry test>"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "<new upload-pending voice retry wired test>"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "<new voice durable-prep cleanup test>"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "<new voice re-record continuation same-id test>"
flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart --plain-name "<new upload-pending voice retry background task test>"
flutter test integration_test/group_recovery_e2e_test.dart --plain-name "<new failed voice retry/re-record same-id simulator smoke>"
```

Full direct suites:

```bash
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart
```

Named host gate:

```bash
./scripts/run_test_gates.sh groups
```

Simulator closure gate:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart
```

Run `dart format --output=none --set-exit-if-changed` on edited Dart files and `git diff --check`.

## known-failure interpretation

The known carried broad-gate residual is:

- `test/features/groups/integration/invite_round_trip_test.dart`
- Test: `GCA-004 bridgeError recovery drains inbox after settled materialized invite`
- Assertion around `invite_round_trip_test.dart:2930`
- `Expected: not null`, `Actual: <null>`

If `./scripts/run_test_gates.sh groups` fails only with that exact residual and all focused/direct voice tests plus the simulator proof pass, classify it as carried residual evidence rather than a new `voice-id-stable-retry` regression. Any failure in touched direct tests, the new simulator proof, upload retry behavior, or a different group-gate failure must be investigated as session-owned unless reproduced independently as pre-existing.

## done criteria

- Uploaded-audio failed retry publishes the same `messageId` and timestamp and updates one row.
- Upload-pending failed voice retry re-drives only that message's upload immediately, then publishes the same id after upload success.
- The old snackbar-only upload-pending behavior is no longer the audio voice retry path.
- Durable-prep failure leaves no empty retry-less row and no orphan attachment/pending dir for the attempted voice id.
- Immediate re-record continuation after retryable voice failure reuses the original id/timestamp and does not create a second local row.
- New/updated host regressions and full direct suites pass.
- `./scripts/run_test_gates.sh groups` passes or fails only with the known carried `GCA-004` residual.
- The group simulator command for `integration_test/group_recovery_e2e_test.dart` passes with the new voice proof. If unavailable, the session cannot be marked fully closed; record explicit follow-up.

## scope guard

Do not:

- Change the group message wire envelope, media encryption contract, or DB schema.
- Reopen text retry UI or restored text continuation.
- Change bridge timeout policy, pending retry-payload fallback, local status broadcast, stuck-sending timestamp recovery, receive-side dedup, or notification routing.
- Add broad media retry product behavior unless a tiny shared helper is unavoidable and has explicit tests for image/video non-regression.
- Add visible UI copy or new l10n unless an existing snackbar cannot represent a failed retry outcome.
- Make voice continuation durable across app restart; this session is an in-memory guard for immediate re-record after a same-screen retryable failure. Restart recovery remains owned by in-place retry and upload retry.

## accepted differences / intentionally out of scope

- For durable-prep failure before durable bytes exist, cleanup is acceptable. The plan does not require preserving an invalid or uncopied recording as retryable media.
- If a same-id re-record has different bytes and a late first attempt arrives first, recipients may keep the first bytes. The intentional contract is one stable message id and one bubble, not byte-level replacement after delivery.
- Non-voice `upload_pending` failed media may keep the existing pending-feedback behavior unless implementation chooses a safe shared targeted retry and proves it. The session's required behavior is recorded voice.
- Final notification matrix and source-doc closure updates remain owned by `acceptance-doc-closure`.

## dependency impact

This session unblocks later duplicate-cascade sessions that depend on voice recovery being a stable-id path:

- `local-status-broadcasts` should observe the status transitions hardened here.
- `live-replay-dedup` and `acceptance-doc-closure` can treat voice retry/re-record as same-id send behavior instead of a fresh-message duplicate source.
- If the targeted upload retry seam changes materially, later sessions should reuse the same message-scoped contract rather than invoking broad upload sweeps from UI actions.

## reviewer pass

Sufficiency: sufficient as-is for implementation, with one incremental execution detail.

- Missing files/tests/gates: none structurally. The plan includes the likely production files, direct host tests, `./scripts/run_test_gates.sh groups`, and the required `$run-flutter-reliability-sims` command for group voice media delivery.
- Stale assumptions: none found. The plan correctly treats current code/tests as source of truth and records that uploaded voice retry may already work but lacks explicit proof.
- Overengineering: avoided. The targeted upload retry is scoped to an optional filter/wrapper on the existing use case, not a new repository API or DB change. The voice continuation is in-memory only.
- Decomposition: sufficient. The plan separates done-audio retry proof, upload-pending manual retry, durable-prep cleanup, and re-record continuation, matching the session contract item by item.
- Minimum needed: keep the simulator proof narrow. The `$run-flutter-reliability-sims` command may execute the full `integration_test/group_recovery_e2e_test.dart` file; the new scenario should stay focused so the session does not become whole media acceptance.

## arbiter decision

Structural blockers: none.

Incremental details:

- The simulator command is intentionally file-scoped rather than scenario-name-scoped because the existing `$run-flutter-reliability-sims` wrapper accepts the file path. The new simulator scenario should remain narrow inside that file.

Accepted differences:

- Simulator closure is required by the planning skill's group/media rule even though the breakdown described simulator proof as optional. This is not a scope expansion into broad acceptance; it is the narrow proof that the voice-media same-id behavior materializes as one receiver row.
- Non-voice upload-pending media retry can remain unchanged unless implementation proves a shared helper is safer with explicit non-regression tests.
- Durable-prep failures before durable bytes exist are cleaned up rather than made retryable.

Planning verdict: execution-ready.

## exact docs/files used as evidence

- `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`
- `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`
- `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `integration_test/group_recovery_e2e_test.dart`
