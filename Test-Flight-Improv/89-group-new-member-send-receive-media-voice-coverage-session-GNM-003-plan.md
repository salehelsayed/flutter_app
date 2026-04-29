# GNM-003 Plan - Visible Media Recovery Retry Inbox Duplicate And Restart Behavior

## real scope

- Prove group media rows remain visible and truthful at the conversation surface and in recovery paths.
- Add a focused widget assertion for post-join text plus video/voice/failure affordances if current screen tests do not directly cover them.
- Reuse existing inbox, retry, duplicate, and foreground-push tests where they already prove the recovery behavior.
- Do not change product behavior unless a direct test exposes a real defect.

## closure bar

- The group conversation screen visibly renders post-join text, video, voice, and failed media states.
- Offline inbox drain persists media attachments, including video and audio metadata.
- Foreground group push media drain deduplicates and triggers media download for a representative media row.
- Failed outgoing group media rows keep retry/delete controls, and application retry suites preserve upload/download retry truthfulness.
- Simulator playback/restart evidence remains truthfully classified as residual if no device-backed fixture is run.

## source of truth

- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-breakdown.md`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`

Current code and passing tests beat stale prose.

## session classification

`implementation-ready`

## exact problem statement

Descriptor-level tests can pass while a user still sees no video, no voice affordance, a silent failed media row, duplicate inbox/live rows, or no recovery after foreground push/inbox drain. This session closes the host-side visible and recovery proof without claiming full simulator playback/restart closure.

## files and repos to inspect next

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/audio_player_widget.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`

## existing tests covering this area

- `group_conversation_screen_test.dart` covers failed outgoing media retry/delete controls.
- `drain_group_offline_inbox_use_case_test.dart` covers inbox media persistence, including encrypted replay with image/video/audio attachments.
- `retry_incomplete_group_uploads_use_case_test.dart` covers incomplete upload retry and terminal upload failure state.
- `retry_failed_group_messages_use_case_test.dart` covers failed media row resend decisions.
- `foreground_group_push_drain_test.dart` covers foreground group media drain, descriptor preservation, download trigger, and duplicate prevention.

## regression/tests to add first

- Add one `group_conversation_screen_test.dart` case for the reported visible class: a user can see text, a video row with play/duration affordance, a voice row with audio player, and a failed media row rather than silent omission.

## step-by-step implementation plan

1. Add video/audio helper attachments to `group_conversation_screen_test.dart` if needed.
2. Add the focused visible media row test.
3. Run the screen test.
4. Run inbox/retry/foreground direct suites listed below.
5. Update source doc, closure references, and breakdown ledger.

## risks and edge cases

- Host widget affordance evidence is not real simulator playback evidence.
- Foreground push coverage is representative image media, not every media type.
- Retry suites prove generic group media rows, not exclusively newly-added-member-origin rows.

## exact tests and gates to run

- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
- `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test integration_test/foreground_group_push_drain_test.dart`

Run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` only if production listener/inbox/retry behavior changes.

## known-failure interpretation

No known failure is allowed for the listed direct suites. Simulator playback/restart gaps are residual evidence gaps, not failures of these host-side tests.

## done criteria

- Direct suites pass or a real blocker is recorded.
- Source doc distinguishes host-side visible/recovery closure from simulator playback/restart residuals.
- Breakdown ledger marks `GNM-003` accepted or accepted with explicit simulator follow-up.

## scope guard

- Do not alter media rendering architecture.
- Do not add product policy for codecs, background downloads, or simulator fixtures.
- Do not widen named gates.

## accepted differences / intentionally out of scope

- Full device-backed playback and restart validation stays in `GNM-005` final acceptance.
- Real-network group recovery remains covered by the existing Report 85 real-network residual classification.

## dependency impact

- `GNM-005` must include these host-side results and decide whether remaining simulator playback/restart evidence is residual-only.
