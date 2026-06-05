# Live/Replay Dedup Implementation Plan

Status: execution-ready

Session id: live-replay-dedup

Source doc: Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md

Breakdown artifact: Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-breakdown.md

## Planning Progress

- 2026-06-03 23:21:22 CEST - Current role: Arbiter completed. Files inspected since last update: reviewer findings and final plan content. Decision/blocker: no structural blockers remain; incremental details are non-blocking; plan is execution-ready. Next action: hand off to execution/QA without updating breakdown ledger or source-doc verdict.
- 2026-06-03 23:21:01 CEST - Current role: Arbiter started. Files inspected since last update: reviewer findings and plan progress. Decision/blocker: reviewer reported no structural blocker; applying stop rule after classification. Next action: persist arbiter decision and final execution-ready status.
- 2026-06-03 23:20:25 CEST - Current role: Reviewer completed. Files inspected since last update: plan section index, ASCII scan, drafted plan content. Decision/blocker: sufficient as-is; no structural blocker found. Next action: Arbiter classifies reviewer findings and decides whether one patch/final review loop is required.
- 2026-06-03 23:19:37 CEST - Current role: Reviewer started. Files inspected since last update: drafted plan file. Decision/blocker: no blocker yet; reviewing for missing simulator closure, regression-first proof, scope drift, stale assumptions, and checklist coverage. Next action: record sufficiency findings.
- 2026-06-03 23:19:08 CEST - Current role: Planner completed. Files inspected since last update: no new files; drafted from collected evidence. Decision/blocker: no blocker; draft now contains mandatory plan sections, scope guard, regression contract, simulator closure, and GCA-004 known-failure handling. Next action: Reviewer checks sufficiency and structural risks.

## Execution Progress

- 2026-06-03 23:49:21 CEST - Phase: final execution verdict written. Files inspected or touched: this plan, QA Reviewer result. Command currently running: none. Decision/blocker: final verdict `accepted`; QA found no blocking issues and no non-blocking follow-ups. Next action: final controller diff-hygiene check and close execution/QA loop.
- 2026-06-03 23:48:33 CEST - Phase: QA Reviewer completed. Files inspected or touched: this plan, `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, `/tmp/live_replay_dedup_groups_gate.log`; plan file execution progress updated only. Command currently running: none. Decision/blocker: blocking issues none; non-blocking follow-ups none. QA accepted scoped implementation: live and replay now share a listener-owned per-user-message queue, `handleReplayEnvelope` still forwards `msgRepoOverride`, `rethrowOnError`, and `allowMembershipBuffer`, system payloads bypass the new user-message queue, live work remains `_trackInFlight` tracked, and stop/dispose stream guards remain intact. QA accepted required regression coverage: one visible row, one stream emit, one local notification, and unread count one for raced `live-replay-race-message`; QA spot check `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "live and replay delivery for one message id emit and notify once when raced"` passed. QA accepted recorded evidence for full listener, receive use-case, offline drain, notification dedupe, simulator closure command #2, format check, and `git diff --check`. Groups gate failure was triaged before classification and matches only known GCA-004 residual at `test/features/groups/integration/invite_round_trip_test.dart:2930` (`Expected: not null` / `Actual: <null>`). Scope guard accepted for this session: no send/retry, DB schema/migration, UI retry, local outgoing status broadcast, source doc, breakdown ledger, notification matrix, or gate-definition change was part of the scoped live-replay-dedup diff. Final QA recommendation: accepted. Next action: controller may close this execution session and update outer breakdown/source artifacts if it owns those steps.
- 2026-06-03 23:46:19 CEST - Phase: QA Reviewer spawned/running. Files inspected or touched: this plan, Executor result summary, scoped git status. Command currently running: spawned QA Reviewer `019e8f73-e1d5-71e0-96a1-175a7dbda0ad`. Decision/blocker: no blocker; isolated QA owns sufficiency review and must not edit code. Next action: wait bounded interval for QA blocking/non-blocking classification.
- 2026-06-03 23:45:20 CEST - Phase: Executor completed. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan, `/tmp/live_replay_dedup_groups_gate.log`, `git status --short`, `git diff --check`. Command currently running: none. Decision/blocker: implementation and required validation are complete for Executor role. `git diff --check` passed. Scoped session changes are limited to listener receive-side queue, direct listener race regression, and this plan's execution notes; existing unrelated dirty worktree files remain untouched. Groups gate is accepted only with the exact known non-session-owned GCA-004 residual. Next action: hand off to QA Reviewer role; do not update breakdown ledger/source-doc verdict/matrix/gate docs.
- 2026-06-03 23:45:20 CEST - Phase: diff hygiene finished. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: `git diff --check` passed. `git status --short` still shows many pre-existing dirty files from other sessions plus this session's touched listener/test/plan; no unrelated dirty work was reverted or modified by this session. Next action: record Executor completion.
- 2026-06-03 23:44:55 CEST - Phase: format applied and check passed. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: `dart format` applied formatting to both touched Dart files, then `dart format --output=none --set-exit-if-changed lib/features/groups/application/group_message_listener.dart test/features/groups/application/group_message_listener_test.dart` passed with 0 changed. Next action: run `git diff --check`.
- 2026-06-03 23:44:24 CEST - Phase: format check failed before applying format. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: `dart format --output=none --set-exit-if-changed lib/features/groups/application/group_message_listener.dart test/features/groups/application/group_message_listener_test.dart` exited 1 and reported both touched Dart files would change. Next action: apply `dart format` to those two files, then rerun the required no-output format check.
- 2026-06-03 23:43:52 CEST - Phase: simulator closure finished. Files inspected or touched: `run-flutter-reliability-sims/SKILL.md`, this plan. Command currently running: none. Decision/blocker: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/foreground_group_push_drain_test.dart` passed; resolved one-device simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, command `#2`, `integration_test/foreground_group_push_drain_test.dart`, all 8 tests passed. Next action: run `dart format --output=none --set-exit-if-changed` for touched Dart files.
- 2026-06-03 23:41:51 CEST - Phase: simulator closure started. Files inspected or touched: `run-flutter-reliability-sims/SKILL.md`, this plan. Command currently running: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/foreground_group_push_drain_test.dart`. Decision/blocker: groups gate only has known non-session-owned GCA-004 residual; proceeding to required actual simulator execution. Next action: capture simulator result or device-resolution blocker.
- 2026-06-03 23:41:30 CEST - Phase: groups gate classified. Files inspected or touched: `/tmp/live_replay_dedup_groups_gate.log`, `run-flutter-reliability-sims/SKILL.md`, this plan. Command currently running: none. Decision/blocker: second `./scripts/run_test_gates.sh groups` rerun with redirected log also exited 1, and log lines 1862-1868 show exactly the known carried residual: `test/features/groups/integration/invite_round_trip_test.dart:2930`, test `GCA-004 bridgeError recovery drains inbox after settled materialized invite`, `Expected: not null`, `Actual: <null>`. Classification: known non-session-owned residual per plan; no live-replay-dedup blocker. Next action: run required simulator-backed closure `run_with_devices.sh group --only integration_test/foreground_group_push_drain_test.dart`.
- 2026-06-03 23:39:48 CEST - Phase: groups gate triage continuing. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: focused triage command `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "ML-004 mixed batch invite failure lets delivered recipients accept while failed recipient stays pending"` passed, so the first visible `-1` context was not the failing slice. Classification remains `pending_triage`; because the original gate output was truncated, a full gate rerun with redirected log is required to capture the exact failure block. Next action: run `./scripts/run_test_gates.sh groups > /tmp/live_replay_dedup_groups_gate.log 2>&1`, then inspect that log for the failure.
- 2026-06-03 23:39:15 CEST - Phase: groups gate failed, pending triage. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: `./scripts/run_test_gates.sh groups` exited 1; stdout was very large and the preserved tail did not include a compact failure block. First visible failure counter appeared during group integration smoke output, not the documented GCA-004 residual, so classification is `pending_triage`. Next action: run focused triage command `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "ML-004 mixed batch invite failure lets delivered recipients accept while failed recipient stays pending"` based on the first visible `-1` context, then broaden only if that slice is not the failing one.
- 2026-06-03 23:37:49 CEST - Phase: groups gate started. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: `./scripts/run_test_gates.sh groups`. Decision/blocker: no blocker after direct tests; known-failure rule applies only to exact GCA-004 residual at `invite_round_trip_test.dart:2930`. Next action: capture groups gate result and triage/classify any failure.
- 2026-06-03 23:37:35 CEST - Phase: notification dedupe integration finished. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: `flutter test test/integration/group_notification_dedupe_integration_test.dart` passed; `integration_test/foreground_group_push_drain_test.dart` was not edited, so the conditional direct host run is not required. Next action: run `./scripts/run_test_gates.sh groups`.
- 2026-06-03 23:37:12 CEST - Phase: notification dedupe integration started. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: `flutter test test/integration/group_notification_dedupe_integration_test.dart`. Decision/blocker: no blocker after offline drain pass. Next action: capture notification dedupe result.
- 2026-06-03 23:36:58 CEST - Phase: offline drain suite finished. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` passed. Next action: run `test/integration/group_notification_dedupe_integration_test.dart`.
- 2026-06-03 23:36:36 CEST - Phase: offline drain suite started. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Decision/blocker: no blocker after receive use-case pass. Next action: capture offline drain result.
- 2026-06-03 23:36:22 CEST - Phase: receive use-case suite finished. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart` passed. Next action: run `drain_group_offline_inbox_use_case_test.dart`.
- 2026-06-03 23:36:01 CEST - Phase: receive use-case suite started. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart`. Decision/blocker: no blocker after full listener pass. Next action: capture receive use-case result.
- 2026-06-03 23:35:45 CEST - Phase: full listener suite finished. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: `flutter test test/features/groups/application/group_message_listener_test.dart` passed, including the new race regression and existing sequential/system/self-echo/media/notification cases. Next action: run `handle_incoming_group_message_use_case_test.dart`.
- 2026-06-03 23:35:08 CEST - Phase: full listener suite started. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: `flutter test test/features/groups/application/group_message_listener_test.dart`. Decision/blocker: no blocker after focused fix pass. Next action: capture full listener result and triage any failure inside receive-side scope.
- 2026-06-03 23:34:51 CEST - Phase: focused regression passed after fix. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "live and replay delivery for one message id emit and notify once when raced"` passed after the listener queue fix. Next action: run full `group_message_listener_test.dart`.
- 2026-06-03 23:34:05 CEST - Phase: production fix applied. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: added listener-owned `_userMessageWorkQueue` keyed by non-system `messageId`; `_handleLiveMessage` and `handleReplayEnvelope(...)` now share the queue while preserving replay parameters and leaving system/message-id-less events on existing handling. Next action: rerun the focused race regression and fix compile or behavior issues only inside receive-side scope.
- 2026-06-03 23:33:19 CEST - Phase: RED focused regression finished with expected failure. Files inspected or touched: `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: after improving the harness to hold live's first target save until replay attempts the second target save, `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "live and replay delivery for one message id emit and notify once when raced"` failed as required: expected one emitted row for `live-replay-race-message`, actual `WhereIterable<GroupMessage>` length 2. Next action: implement the smallest listener-owned per-user-message queue in `group_message_listener.dart`, then rerun the focused regression.
- 2026-06-03 23:29:26 CEST - Phase: RED focused regression finished unexpectedly green. Files inspected or touched: `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: none. Decision/blocker: `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "live and replay delivery for one message id emit and notify once when raced"` passed before production changes, so the first harness did not expose overlap and cannot count as RED evidence. Next action: improve the test barrier per plan step 1, rerun the focused regression, and require a true pre-fix failure before production changes.
- 2026-06-03 23:28:27 CEST - Phase: RED focused regression started. Files inspected or touched: `test/features/groups/application/group_message_listener_test.dart`, this plan. Command currently running: `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "live and replay delivery for one message id emit and notify once when raced"`. Decision/blocker: production code is still untouched; expecting the new race regression to fail by showing more than one emit and/or notification for the raced `messageId`. Next action: capture expected failure evidence, then implement the listener-owned receive-side serialization fix.
- 2026-06-03 23:27:05 CEST - Phase: owner files inspected. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`, `test/shared/fakes/fake_notification_service.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/domain/repositories/group_message_repository.dart`. Command currently running: none. Decision/blocker: current listener has live tracked through `_handleLiveMessage` while replay calls `_handleMessage` directly; direct test can expose the pre-save race with a target-id save barrier. Next action: add the required RED regression in `group_message_listener_test.dart` before production changes.
- 2026-06-03 23:25:03 CEST - Phase: Executor started. Files inspected or touched: this plan, `git status --short`, `implementation-execution-qa-orchestrator/SKILL.md`. Command currently running: none. Decision/blocker: scope confirmed as isolated Executor implementation only; preserving existing dirty worktree changes and not taking QA Reviewer role. Next action: inspect owner production/test files, then add the required RED race regression before production changes.
- 2026-06-03 23:24:07 CEST - Phase: contract extraction. Files inspected or touched: this plan, breakdown context, `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, `git status --short`. Command currently running: none. Decision/blocker: execution contract is concrete and scoped to live/replay receive dedup; no blocker. Next action: spawn isolated Executor agent with model `gpt-5.5` and reasoning effort `xhigh`.
- 2026-06-03 23:24:51 CEST - Phase: Executor spawned/running. Files inspected or touched: this plan. Command currently running: spawned Executor `019e8f5f-daec-7a33-9096-129bd9c8be8b`. Decision/blocker: no blocker; isolated Executor owns the RED test, receive-side fix, required tests, and gate evidence. Next action: wait bounded interval for Executor result, then spawn isolated QA Reviewer.

## real scope

This session owns one receive-side correctness fix: concurrent handling of the same user-message `messageId` through live listener traffic and replay/drain traffic must not produce two `groupMessageStream` emits or two local notifications.

Production scope is limited to one of these equivalent narrow approaches:

- Preferred: route `GroupMessageListener.handleReplayEnvelope(...)` through the same listener-owned message work queue/serialization used by live stream handling, so live and replay/drain processing of a user message with the same `messageId` cannot overlap inside `handleIncomingGroupMessage`.
- Accepted alternative: add a listener-owned idempotent emit/notify guard keyed by `messageId` that treats the first completed persisted incoming message as the only side-effect owner, while allowing duplicate enrichment and self-echo reconciliation behavior to stay intact.

This session may touch only receive/drain/listener behavior and direct tests needed to prove one emit plus one notification. It must not change send retry behavior, text or voice id-stability, reliable-send timeout, local outgoing status broadcasts, DB schema/migrations, source-doc final verdicts, or matrix/gate documentation.

## closure bar

Good enough for this session means all of the following are true:

- A concurrent live-plus-replay delivery of the same incoming user message id saves at most one visible row, emits exactly one `GroupMessage` on `GroupMessageListener.groupMessageStream`, and calls the local notification path at most once.
- Existing sequential duplicate behavior still passes: repeated live duplicates, replay after live, repeated replay page entries, self-echo reconciliation, reminted media retry dedupe, and remote-push announcement suppression are not weakened.
- Replay/drain still uses listener handling for system payload cleanup and normal user payload side effects where it currently does.
- The implementation is scoped to a listener-level guard/queue or an equivalent idempotent side-effect guard; no repository-wide API migration is required unless evidence during implementation proves the listener-level guard cannot preserve existing behavior.
- Simulator-backed closure is required because this touches group messaging, replay/drain, foreground push, and notification-facing behavior. Host tests alone cannot fully close this session.

Coverage ledger for the session contract:

| Requirement | Planned proof |
|---|---|
| Route replay/drain and live group message handling through shared serialization or idempotent guard | Add a direct listener regression that starts live handling and `handleReplayEnvelope(...)` for the same user `messageId` concurrently, using a controllable repository/use-case delay to expose the pre-save race. |
| One `messageId` cannot produce two stream emits | Same listener regression asserts `groupMessageStream` receives exactly one message for the raced id. |
| One `messageId` cannot produce two local notifications | Same listener regression and foreground push drain regression assert the fake notification service has exactly one shown entry for the raced/duplicated id. |
| Keep session narrow to live/replay receive dedup and one-notification proof | Scope guard forbids send/retry, migration, UI retry, matrix, and source-doc closure changes. |
| Include simulator-backed closure | Required command is listed in exact gates: `$run-flutter-reliability-sims` group `--only integration_test/foreground_group_push_drain_test.dart`; reliability-sim list evidence identifies it as group command `#2`. |

## source of truth

- Current code and tests are authoritative when they conflict with proposal prose.
- `Test-Flight-Improv/test-gate-definitions.md` is the named-gate source of truth.
- Active session contract comes from `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-breakdown.md`.
- Product problem context comes from `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`, specifically receive-side item 7.
- Earlier dependencies `timeout-pending-retry` and `status-timestamp-migration` are accepted with explicit follow-up in the breakdown and must not be reopened here.

## session classification

implementation-ready

## exact problem statement

`GroupMessageListener.start(...)` processes live stream messages through `incomingGroupMessages.asyncMap(_handleLiveMessage)`, which serializes live events in stream order. `GroupMessageListener.handleReplayEnvelope(...)` calls `_handleMessage(...)` directly. Foreground push drain and offline inbox drain call `handleReplayEnvelope(...)`, so replay can overlap with a live handler for the same `messageId`.

`handleIncomingGroupMessage(...)` dedupes by doing `msgRepo.getMessage(messageId)` before `msgRepo.saveMessage(...)`. The DB helper protects the row with an id unique conflict merge, but neither the use case nor repository reports whether this invocation inserted or lost a concurrent race. If two handlers both pass the pre-save check, both can receive non-null results and both can emit and notify.

User-visible behavior to improve: one delivered group message must appear once and notify once even when live delivery and replay/drain deliver the same message at nearly the same time.

Must stay unchanged: existing accepted duplicate semantics, remote-push notification gate consumption, self-echo reconciliation, system message handling, media attachment enrichment, cursor/receipt behavior, and all earlier session changes.

## files and repos to inspect next

Production files:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/features/push/application/show_notification_use_case.dart` only if the idempotent-notify option is chosen
- `lib/core/notifications/recent_remote_notification_gate.dart` only if the notification gate must be extended

Direct tests:

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/integration/group_notification_dedupe_integration_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`

Gate/test infra:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh`

## existing tests covering this area

- `test/features/groups/application/group_message_listener_test.dart` covers sequential incoming notification, replay-after-live no second notification, repeated live duplicate preservation, self-echo reconciliation, reminted media retry dedupe, and remote announcement notification suppression.
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` covers sequential duplicate by `messageId`, replay enrichment, conflicting content/timestamp duplicate rejection, self-echo reconciliation, and media retry dedupe.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` covers replay page duplicate idempotency, cursor retry idempotency, read-state preservation, notification spam avoidance for sequential replay duplicates, and remote-push replay suppression.
- `test/integration/group_notification_dedupe_integration_test.dart` covers background remote announcement suppressing a later local group notification for the same id.
- `integration_test/foreground_group_push_drain_test.dart` covers foreground push targeted drain, repeat push for the same media id, push after live delivery, and background announcement suppression.

Missing today: a direct concurrent live-plus-replay race where both handlers enter the receive use case before either has saved the row, with assertions on stream emits and local notifications.

## regression/tests to add first

Add the direct RED regression before production changes:

1. In `test/features/groups/application/group_message_listener_test.dart`, add a test named like `live and replay delivery for one message id emit and notify once when raced`.
2. Build a `GroupMessageListener` with `FakeNotificationService`, `ActiveConversationTracker`, `getAppLifecycleState: () => AppLifecycleState.paused`, and a self member different from the sender.
3. Use either a small test-only repository wrapper around `InMemoryGroupMessageRepository` or an injected fake that delays/barriers `saveMessage(...)` or `getMessage(...)` for the target `messageId`, so a live `sourceController.add(message)` and `listener.handleReplayEnvelope(message)` can overlap before the first save completes.
4. Assert after both operations settle that:
   - repository has one visible row for the target `messageId`;
   - `groupMessageStream` emitted exactly one row for that id;
   - fake notification service has exactly one shown notification for that id;
   - unread count is one.
5. Keep existing sequential duplicate tests passing; do not replace them with the new race test.

If the implementation chooses idempotent emit/notify instead of serialization, add a focused unit proof that the duplicate handler may still persist/enrich a duplicate row as needed but cannot own emit/notify after the first handler claims the side-effect key.

## step-by-step implementation plan

1. Confirm the new race test fails or is skipped only because the existing harness cannot expose overlap; if it cannot fail, improve the fake barrier rather than weakening the assertion.
2. Implement the smallest listener-owned guard:
   - Preferred path: add a private `Map<String, Future<void>>` or per-key work queue in `GroupMessageListener`, keyed by stable user message id when present, and route both `_handleLiveMessage` and `handleReplayEnvelope(...)` through it before `_handleMessage(...)`.
   - For events without a stable user `messageId`, preserve existing live serialization and avoid adding a broad global lock unless tests prove it is necessary.
   - Do not serialize unrelated groups/messages globally if a per-`messageId` queue is enough.
3. Ensure `handleReplayEnvelope(...)` still honors `msgRepoOverride`, `rethrowOnError`, and `allowMembershipBuffer`.
4. Ensure `_trackInFlight(...)`, `stop()`, and `dispose()` still wait for queued live work and do not emit after stop/dispose.
5. Keep system payload behavior intact. If the per-message guard applies to system messages with source ids, do not break signed transition idempotency or group removal cleanup tests.
6. Run the new listener race regression. Fix only receive-side guard issues.
7. Run existing direct suites around listener, use case, drain, and notification dedupe. If a failure reveals stale assumptions in the plan, stop and revise evidence rather than broadening scope.
8. Extend `integration_test/foreground_group_push_drain_test.dart` only if the current simulator proof cannot represent the one-notification live/replay/drain journey. The expected extension is a narrow scenario that starts a live delivery and foreground push drain for the same id close together and asserts one row plus one notification.
9. Run the required gates and classify known residuals exactly as documented below.

## risks and edge cases

- Deadlock or dropped work if a per-message queue awaits itself through replay callbacks.
- `dispose()` or `stop()` racing with queued replay work could emit after the listener is stopping.
- System messages use `messageId` as source event id in several paths; the guard must not suppress legitimate cleanup side effects for signed membership/config transitions.
- Self-echo reconciliation returns an outgoing row and should still emit once so open sender screens refresh status.
- Remote notification gate consumption must stay exactly once: a duplicate local replay should not consume an unrelated remote announcement and should not notify.
- Media attachment enrichment on duplicate replay must still happen where existing tests expect it.
- Broad serialization could slow inbox drain or live traffic; prefer per-`messageId` or per-group/user-message work where feasible.
- Existing dirty worktree changes from prior sessions must be preserved, including `info.plist`, DB migration/status timestamp changes, local status broadcast changes, and untracked prior plan files.

## exact tests and gates to run

Regression/direct tests:

```bash
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "live and replay delivery for one message id emit and notify once when raced"
flutter test test/features/groups/application/group_message_listener_test.dart
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
flutter test test/integration/group_notification_dedupe_integration_test.dart
```

If `integration_test/foreground_group_push_drain_test.dart` is edited or extended, run the host/direct integration target before simulator closure:

```bash
flutter test integration_test/foreground_group_push_drain_test.dart
```

Named host gate:

```bash
./scripts/run_test_gates.sh groups
```

Required simulator-backed closure gate:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/foreground_group_push_drain_test.dart
```

List-only evidence from planning shows this is reliability-sim group command `#2`, so this equivalent rerun is also acceptable after a fresh list pass:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 2
```

Formatting/diff hygiene:

```bash
dart format --output=none --set-exit-if-changed lib/features/groups/application/group_message_listener.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/integration/group_notification_dedupe_integration_test.dart integration_test/foreground_group_push_drain_test.dart
git diff --check
```

Only include files actually touched in the `dart format` command.

## known-failure interpretation

If `./scripts/run_test_gates.sh groups` fails exactly at:

```text
test/features/groups/integration/invite_round_trip_test.dart:2930
Expected: not null
Actual: <null>
```

in the `GCA-004 bridgeError recovery drains inbox after settled materialized invite` path, classify it as the known carried groups-gate residual from earlier accepted sessions, not a `live-replay-dedup` regression. Preserve the full failing test name and assertion in execution notes.

Any other groups-gate failure, any changed line for the GCA-004 failure, any additional assertion in the same file, or any failure in the direct listener/drain/notification/simulator tests must be treated as session-blocking until triaged.

If the simulator wrapper cannot resolve required devices, do not mark the session fully closed on host tests alone. Record the device-resolution blocker and classify execution as evidence-gated or accepted only with explicit follow-up per the parent pipeline rules.

## done criteria

- Plan-owned production changes are limited to receive-side live/replay dedup and notification side-effect control.
- The new concurrent live-plus-replay listener regression fails before the implementation and passes after it.
- Direct listener, receive use-case, drain, and notification dedupe tests listed above pass.
- `./scripts/run_test_gates.sh groups` passes or fails only with the exact known GCA-004 residual at `invite_round_trip_test.dart:2930`.
- Required simulator closure passes via `run_with_devices.sh group --only integration_test/foreground_group_push_drain_test.dart` or equivalent command `#2` after a fresh list pass.
- Existing sequential duplicate, self-echo, media retry dedupe, remote announcement suppression, system replay, cursor/receipt, and local status broadcast behavior are not regressed.
- No source-doc final verdict, breakdown ledger, notification matrix, or gate-definition doc is changed in this session.

## scope guard

Do not implement or alter:

- failed text retry/delete UI;
- restored text continuation id semantics;
- recorded-voice retry/upload-pending behavior;
- reliable-send timeout or pending retry-payload fallback;
- local outgoing status broadcast surfaces;
- `last_send_attempt_at` migration or stuck-sending predicates;
- database schema or migration version;
- broad repository API rewrites;
- notification copy, notification routing, deep-link behavior, APNs/FCM payloads, or OS notification project config;
- source-doc final closure, session breakdown ledger, gate-definition docs, or notification matrix docs.

Overengineering for this session includes a global receive mutex for every group message if a per-message queue suffices, a new cross-repo dedupe service, schema-level insert-result plumbing without evidence it is required, or changes to send/retry paths to compensate for receive-side duplication.

## accepted differences / intentionally out of scope

- The plan accepts listener-level serialization as sufficient even though repository/DB insert-result signaling could be architecturally cleaner; this session only needs to prevent duplicate listener side effects for one message id.
- Host direct tests can prove the race and side-effect guard, but simulator closure is still required because the user-visible path involves foreground push/drain and notifications.
- Existing sequential duplicate tests are not proof of the race; they remain regression coverage only.
- Updating the source proposal, session breakdown ledger, notification matrix, and final program verdict is intentionally deferred to `acceptance-doc-closure`.

## dependency impact

This session depends on `timeout-pending-retry` being accepted, and the current breakdown records it as `accepted_with_explicit_follow_up`. `status-timestamp-migration` is also now accepted with explicit follow-up and must be preserved as dirty worktree context.

`acceptance-doc-closure` depends on this session's final evidence. If this plan changes from listener-level serialization to repository insert-result plumbing, acceptance closure should re-check the notification and foreground push matrix wording before claiming full duplicate-delivery cascade closure.

If the simulator gate is unavailable, downstream acceptance-doc closure must not record this session as fully closed without an explicit evidence-gated follow-up.

## evidence collected

- `group_message_listener.dart`: `handleReplayEnvelope(...)` calls `_handleMessage(...)` directly, while `start(...)` uses `incomingGroupMessages.asyncMap(_handleLiveMessage)`. `_handleMessage(...)` emits and notifies only when `handleIncomingGroupMessage(...)` returns non-null.
- `handle_incoming_group_message_use_case.dart`: message-id dedupe checks `msgRepo.getMessage(...)` before building/saving the message, then saves through `msgRepo.saveMessage(...)`; duplicate sequential calls return null.
- `group_messages_db_helpers.dart`: duplicate `group_messages.id` insert conflicts are merged/ignored for same identity, protecting the row but not reporting insert ownership to listener side effects.
- `drain_group_offline_inbox_use_case.dart`: offline drain routes normal user replay payloads through `groupMessageListener.handleReplayEnvelope(...)` when a listener is provided.
- Existing tests cover sequential duplicate live/replay/drain and notification suppression but not concurrent live-plus-replay overlap.
- `test-gate-definitions.md`: `./scripts/run_test_gates.sh groups` is required for group receive changes; `test/integration/group_notification_dedupe_integration_test.dart` and `integration_test/foreground_group_push_drain_test.dart` are optional/manual direct suites relevant to notification/foreground push dedupe.
- Reliability-sim list-only command confirms `integration_test/foreground_group_push_drain_test.dart` is group command `#2`.

## reviewer findings

Sufficiency verdict: sufficient as-is.

- Missing files, tests, or gates: none structural. The plan names likely production files, direct listener/use-case/drain/notification tests, the groups named gate, and the required simulator closure gate.
- Missing simulator closure: none. The plan explicitly requires `$run-flutter-reliability-sims` with `group --only integration_test/foreground_group_push_drain_test.dart` and records the equivalent command `#2`.
- Stale assumptions: none found. The plan treats current code/tests as authoritative and records that existing tests cover sequential duplicates but not concurrent live-plus-replay overlap.
- Overengineering: none in the plan. Repository insert-result plumbing is kept as a fallback only if listener-level serialization/idempotent side-effect guarding cannot preserve behavior.
- Decomposition safety: sufficient. The plan forbids send/retry/UI/migration/doc-closure scope and requires a RED race regression before production changes.
- Minimum needed to implement safely: add the direct race regression, implement a listener-level per-message queue or equivalent idempotent emit/notify guard, run the listed direct suites, groups gate, and simulator closure.
- Checklist coverage: complete. Every user-provided contract item maps to a planned proof, gate, scope guard, or known-failure classification.

## arbiter decision

Final verdict: execution-ready.

Structural blockers: none.

Incremental details:

- A future executor may choose the listener queue or idempotent emit/notify option based on the first RED race test. This is an implementation detail, not a planning blocker.
- If the foreground push simulator test already proves the final journey after implementation, no simulator test extension is required. If it does not, the plan requires extending only that target before closure.

Accepted differences:

- The plan intentionally does not change repository save APIs or DB helper return values unless listener-level serialization cannot preserve current behavior.
- The plan intentionally does not update the session breakdown ledger, source-doc final verdict, notification matrix, or gate-definition docs; those remain owned by `acceptance-doc-closure`.

Stop-rule result: reviewer found no structural blocker, so no patch/re-review loop is required.

## Final Execution Verdict

Final verdict: accepted.

Completed at: 2026-06-03 23:49:21 CEST.

Spawned-agent isolation used: yes. Executor `019e8f5f-daec-7a33-9096-129bd9c8be8b` completed first; QA Reviewer `019e8f73-e1d5-71e0-96a1-175a7dbda0ad` completed second.

Local sequential fallback used: no.

Files changed for this session:

- `lib/features/groups/application/group_message_listener.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-live-replay-dedup-plan.md`

Tests added or updated:

- Added `live and replay delivery for one message id emit and notify once when raced` in `test/features/groups/application/group_message_listener_test.dart`.

Evidence accepted:

- The focused race regression failed before the production fix with two stream emits for `live-replay-race-message`.
- The listener-owned per-user-message queue fix made the focused regression pass.
- Required direct listener, receive use-case, offline drain, notification dedupe, groups gate, simulator closure, format, and diff hygiene evidence is recorded in `## Execution Progress`.
- `./scripts/run_test_gates.sh groups` failed only with the known carried non-session-owned GCA-004 residual at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`.
- QA reran the focused race regression after the Executor handoff and it passed.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none.

Why the session is safe to consider complete: the plan-owned behavior now serializes live/replay receive handling for the same non-system user `messageId`, the direct race proves one visible row, one stream emit, one local notification, and unread count one, required gates are satisfied or classified exactly under the plan's known-residual rule, and QA accepted the landed scope without findings.
