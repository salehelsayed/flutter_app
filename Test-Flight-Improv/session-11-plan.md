# Session 11 Plan: Lightweight Timing Counters

## 1. Scope

- Session 11 is a measurement-only slice for send, retry, discovery, and media flows.
- Use the existing lightweight primitives already in repo: `lib/core/utils/flow_event_emitter.dart` and `lib/core/utils/startup_timing.dart`.
- Keep the change local and removable. Do not introduce `lib/core/observability/`, exporter plumbing, dashboards, or any broader metrics framework.
- Instrument the shared conversation and group use cases that already own the real work: send, upload, download, retry, rejoin, inbox drain, and the live group recovery callbacks already wired through startup/resume.
- Group retry/recovery is in scope for this session because the current app path already runs `recover_stuck_sending_group_messages`, `retry_incomplete_group_uploads`, `retry_failed_group_messages`, and `retry_failed_group_inbox_stores` through the recovery wiring in `lib/main.dart` and `lib/core/lifecycle/handle_app_resumed.dart`.
- Defer startup/resume instrumentation in this session. `lib/main.dart` already records startup milestones with `StartupTiming.instance.mark(...)`, and `lib/core/lifecycle/handle_app_resumed.dart` already has explicit resume-step timing and flow events. That is enough evidence to keep Session 11 focused on the send/retry/discovery/media gap called out in `10-network-measurement-strategy.md`.

## 2. Files To Inspect Next

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/features/conversation/application/recover_stuck_sending_messages_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/core/utils/flow_event_emitter.dart`
- `lib/core/utils/startup_timing.dart`
- `lib/main.dart` for confirmation only
- `lib/core/lifecycle/handle_app_resumed.dart` for confirmation only
- `scripts/run_test_gates.sh`

## 3. Existing Tests Covering This Area

- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/send_voice_message_use_case_test.dart`
- `test/features/conversation/application/upload_media_use_case_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_media_test.dart`
- `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`
- `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
- `test/features/conversation/application/retry_unacked_messages_null_guard_test.dart`
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `test/features/conversation/application/recover_stuck_sending_messages_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/integration/media_retry_smoke_test.dart`
- `test/features/conversation/integration/incomplete_upload_recovery_test.dart`
- `test/features/conversation/integration/voice_message_exchange_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/features/conversation/integration/stuck_sending_recovery_test.dart`
- `test/features/conversation/integration/quote_reply_thread_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `integration_test/background_reconnect_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/wifi_relay_fallback_smoke_test.dart`

## 4. Regressions / Tests To Add First

- If a shared timing helper is introduced, add one narrow unit test for that helper first. It should verify that timing capture returns the original result and does not swallow exceptions.
- If instrumentation stays inline inside the use cases, no new behavioral regression test is required before code changes. Existing use-case and integration tests already pin the message, retry, group recovery, and media flows.
- Do not start with device-backed tests. The first safety net should stay deterministic and local.

## 5. Step-By-Step Implementation Plan

1. Define the measurement boundaries and metric names before editing code. Keep the scope to total send time, retry time, upload/download time, group rejoin time, group inbox drain time, and group recovery retry timings.
2. Add timing capture only where the shared business logic already lives. Prefer short local stopwatch blocks and existing flow events over a new service layer.
3. Instrument the 1:1 send path in `send_chat_message_use_case.dart` and the voice send boundary in `send_voice_message_use_case.dart`, including the direct/reuse/local/inbox fallback branches if path labels are needed for analysis.
4. Instrument media upload and download in `upload_media_use_case.dart` and `download_media_use_case.dart`.
5. Instrument 1:1 retry and recovery flows in `retry_failed_messages_use_case.dart`, `retry_unacked_messages_use_case.dart`, `retry_incomplete_uploads_use_case.dart`, and `recover_stuck_sending_messages_use_case.dart`.
6. Instrument group send and discovery flows in `send_group_message_use_case.dart`, `rejoin_group_topics_use_case.dart`, and `drain_group_offline_inbox_use_case.dart`.
7. Instrument the live group recovery retry surfaces in `recover_stuck_sending_group_messages_use_case.dart`, `retry_incomplete_group_uploads_use_case.dart`, `retry_failed_group_messages_use_case.dart`, and `retry_failed_group_inbox_stores_use_case.dart`.
8. Keep startup/resume files read-only unless the review finds a direct dependency. The current repo already has startup marks and resume flow events, so this session should not expand into `main.dart` or `handle_app_resumed.dart`.
9. Preserve privacy: do not emit message content, full peer IDs, or anything that would make the logging materially more sensitive.
10. Run the targeted tests listed below, then run the relevant subsystem gate commands from `scripts/run_test_gates.sh`.

## 6. Risks And Edge Cases

- `emitFlowEvent()` is debug-only today, so any measurement added through it is diagnostic rather than production analytics. Keep that limitation explicit and do not turn this into an observability platform.
- Avoid double counting. Several retry paths call shared send/upload helpers, so counters should be attached at the outer use-case boundary unless the inner path is the actual measurement target.
- Do not change behavior while adding timings. Return values, persistence, retry ordering, and fallback decisions must remain identical.
- Keep the data low risk. Count/duration/path labels are fine; payload contents are not.
- Group retry scope drift is a risk in both directions: omitting live group recovery paths leaves the measurement slice incomplete, but moving into new startup/resume instrumentation would broaden scope unnecessarily.
- If any wrapper is added around a shared helper, exceptions must still propagate exactly as they do now.

## 7. Exact Tests To Run After Implementation

- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`
- `flutter test test/features/conversation/application/send_voice_message_use_case_test.dart`
- `flutter test test/features/conversation/application/upload_media_use_case_test.dart`
- `flutter test test/features/conversation/application/download_media_use_case_test.dart`
- `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `flutter test test/features/conversation/application/retry_failed_messages_media_test.dart`
- `flutter test test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`
- `flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
- `flutter test test/features/conversation/application/retry_unacked_messages_null_guard_test.dart`
- `flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `flutter test test/features/conversation/application/recover_stuck_sending_messages_use_case_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `flutter test test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh groups`
- `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh baseline`
- If and only if implementation edits `lib/main.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, or transport/bootstrap code: `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`

## 8. Subsystem Gate(s) And Whether Startup/Transport Tests Are Needed

- `scripts/run_test_gates.sh` is the source of truth for named gate membership in this repo.
- Baseline Gate: required, because this work touches shared messaging and recovery code paths.
- 1:1 Gate: required, because the measurement points include shared conversation send, retry, and media flows.
- Groups Gate: required, because group send, rejoin, inbox drain, and live group retry/recovery flows are in scope.
- Startup / Transport Gate: not required for the planned slice. Only add it if the implementation changes `lib/main.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, bridge startup, or transport fallback behavior.

## 9. Done Criteria

- Send, retry, discovery, and media paths have lightweight timing or counter output at the intended boundaries.
- The implementation stays local to the existing use cases or a tiny helper, with no new observability subsystem.
- Existing tests still pass, and any new helper has its own deterministic unit coverage.
- Startup/resume files remain unchanged unless a later review proves they are needed.
- No new log output includes message content or full peer identifiers.
- The required gate commands from `scripts/run_test_gates.sh` have been run, and any transport-gate requirement is triggered only by actual startup/transport file edits.

## 10. Explicit Assumptions For Review

- Session 11 is measurement-only and does not include exporter, dashboard, or analytics pipeline work.
- The safe slice is conversation and groups instrumentation, not startup/resume instrumentation.
- Existing startup timing and resume flow logging are sufficient evidence to defer `main.dart` and `handle_app_resumed.dart` in this session.
- `scripts/run_test_gates.sh` is the authoritative gate definition for Baseline, 1:1, Groups, and Transport in this repo.
- Any helper introduced here should be small enough to remove cleanly once the measurement question is answered.
