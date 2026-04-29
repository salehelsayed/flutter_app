# GON-012 Plan: Group Media Matrix And Failure/Recovery UI States

## real scope

- Revalidate existing host-side group retry and media-recovery suites that back TC-34.
- Keep TC-30 full simulator media matrix and TC-34 simulator UI-state breadth as explicit residuals.
- Avoid claiming simulator media/render/restart coverage from host-only tests.

## closure bar

- Host retry/recovery suites for failed group sends, incomplete uploads, and retry controls pass.
- The source doc distinguishes host evidence from missing simulator UI breadth.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-012`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-30 and TC-34.

## session classification

`implementation-ready`

## exact problem statement

The repo has meaningful host-side evidence for group media retry, upload failure, zero-peer fallback, and recovery behavior, but Report 85 asks for simulator-visible media descriptors, render/download retry, restart visibility, and UI failure states. Those simulator rows should remain open unless a device run proves them.

## files and repos to inspect next

- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `integration_test/media_stable_id_smoke_test.dart`
- `integration_test/media_message_journey_e2e_test.dart`

## existing tests covering this area

- `retry_incomplete_group_uploads_use_case_test.dart` covers upload-pending recovery and terminal retry behavior.
- `retry_failed_group_messages_use_case_test.dart` covers failed text/media retry rows, zero-peer plus inbox-fail ownership, and targeted retry.
- `group_conversation_screen_test.dart` covers failed outgoing media retry/delete controls.
- `group_media_fanout_test.dart` and `announcement_new_reader_onboarding_test.dart` cover app-layer descriptors for image/video/voice.

## regression/tests to add first

- No new code seam is needed for this local pass. Re-run the focused host suites and update the coverage ledger.

## step-by-step implementation plan

1. Run the focused retry/upload host tests.
2. Run the focused failed-media retry UI test file.
3. Update Report 85 and closure references to reflect host evidence versus simulator residuals.
4. Mark the session as locally accepted with simulator residuals.

## risks and edge cases

- Host widget/use-case tests do not prove simulator render/download behavior, app restart visibility, or OS lifecycle behavior.

## exact tests and gates to run

- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`

## known-failure interpretation

- Retry test failures indicate the host-side TC-34 safety net regressed.
- Passing host tests still leave TC-30 and TC-34 simulator rows open.

## done criteria

- The host suites pass.
- Docs record simulator residuals explicitly.

## scope guard

- Do not promote `integration_test/media_*` simulator scripts without running them on a device.

## accepted differences / intentionally out of scope

- Full image/video/GIF/audio Discussion + Announcement simulator matrix remains device-lab work.

## dependency impact

- Later simulator media sessions can rely on these host retry contracts as preconditions.
