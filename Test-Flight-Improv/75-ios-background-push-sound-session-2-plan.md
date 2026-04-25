# Report 75 Session 2 Plan - Flutter Local Fallback Sound and Quiet Suppression Proof

## Final verdict

- Status:
  `accepted`
- Accepted on:
  `2026-04-24`
- Execution mode:
  `local bounded fallback after fresh child materialization failed because codex could not access /Users/I560101/.codex/sessions`
- Why:
  - `test/features/push/application/background_message_handler_test.dart` now
    proves the fallback plugin `show(...)` seam carries the shared Android and
    iOS sound-capable platform specifics, not just the title/body/payload.
  - `test/features/push/application/ios_push_project_config_test.dart` now
    pins the `lib/main.dart` foreground remote presentation contract to
    `alert: false`, `badge: false`, and `sound: false`.
  - No Flutter production code change was needed; the direct suppression and
    routing suites remained green once tests ran through the writable Flutter
    SDK overlay at `/tmp/flutter-sdk-report75`.

## real scope

- Strengthen deterministic Flutter-side proof for the Report 75 sound contract without widening into unrelated push/product work.
- Keep production behavior unchanged unless a current seam fails the new proof and requires the smallest scoped fix.
- Focus on:
  - background local fallback using `mknoonMessagesNotificationDetails`
  - foreground remote presentation staying quiet in `lib/main.dart`
  - active-conversation suppression and recent-remote duplicate suppression staying intact
  - existing chat/group tap-routing tests continuing to pass

Out of scope for this session:

- relay/APNs payload shaping already handled in Session 1
- manual simulator or TestFlight audible verification
- new notification product settings or copy changes

## closure bar

Session 2 is good enough only when repo-local tests prove that the fallback local notification show path uses the shared audible iOS/Android details, the app-open remote presentation contract remains `sound: false`, and the existing suppression plus tap-routing suites still pass without introducing noisy duplicate behavior.

## source of truth

- Active session contract: `Test-Flight-Improv/75-ios-background-push-sound-session-breakdown.md`
- Proposal context: `Test-Flight-Improv/75-ios-background-push-sound.md`
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win on disagreement:
  - `lib/core/notifications/local_notification_support.dart`
  - `lib/main.dart`
  - `lib/features/push/application/background_message_handler.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `test/core/notifications/local_notification_support_test.dart`
  - `test/features/push/application/background_message_handler_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/integration/notification_tap_smoke_test.dart`
  - `test/features/push/application/ios_push_project_config_test.dart`

## session classification

`implementation-ready`

## exact problem statement

The Flutter side already appears to keep message notification details audible and foreground remote presentation quiet, but the current tests do not pin the exact background fallback detail object on the show seam and do not explicitly protect the `setForegroundNotificationPresentationOptions(sound: false)` contract. This session should add only the smallest proof needed to make those seams deterministic and keep the existing suppression and routing tests green.

## files and repos to inspect next

- Production files:
  - `lib/core/notifications/local_notification_support.dart`
  - `lib/main.dart`
  - `lib/features/push/application/background_message_handler.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
- Direct tests:
  - `test/core/notifications/local_notification_support_test.dart`
  - `test/features/push/application/background_message_handler_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/integration/notification_tap_smoke_test.dart`
  - `test/features/push/application/ios_push_project_config_test.dart`

## existing tests covering this area

- `local_notification_support_test.dart` already proves the shared notification detail constant carries Android `playSound: true` and iOS `presentSound: true`.
- `background_message_handler_test.dart` already proves the fallback path initializes the plugin, shows a fallback notification, preserves route payloads, and suppresses duplicate background fallback announcements.
- `show_notification_use_case_test.dart` already proves active-conversation suppression and recent-remote duplicate suppression.
- `chat_and_group_push_open_flow_test.dart` and `notification_tap_smoke_test.dart` already prove warm/cold notification routing and prepare-before-route ordering.
- `ios_push_project_config_test.dart` already proves iOS push project configuration and APNs registration diagnostics.

Missing coverage:

- no current assertion proves the background handler show call uses the shared audible platform specifics on the actual plugin show seam
- no current direct assertion pins `lib/main.dart` foreground remote presentation to `sound: false`

## regression/tests to add first

- Extend `test/features/push/application/background_message_handler_test.dart` first to assert the `show` method uses the expected platform specifics from `mknoonMessagesNotificationDetails` for Android and iOS fallback display.
- Extend `test/features/push/application/ios_push_project_config_test.dart` with a narrow static contract test that pins the `setForegroundNotificationPresentationOptions(alert: false, badge: false, sound: false)` call in `lib/main.dart`.
- Reuse the existing suppression and routing suites as direct regression proof; do not add a new integration harness in this session.

## step-by-step implementation plan

1. Confirm the current background handler still passes `mknoonMessagesNotificationDetails` into `_backgroundNotificationsPlugin.show(...)`.
2. Add the smallest new assertions in `background_message_handler_test.dart` that prove the emitted plugin `show` call carries the expected Android and iOS sound-capable platform specifics.
3. Add the narrow `lib/main.dart` foreground presentation contract assertion to `ios_push_project_config_test.dart`.
4. Do not change Flutter production code unless one of the new tests exposes a real gap.
5. Run the exact direct tests below.
6. If those tests pass without production edits, close the session as accepted proof-strengthening rather than forcing a no-op code change.

## risks and edge cases

- Background fallback proof must not accidentally hard-code a platform-specific detail shape that the plugin does not actually emit; keep assertions to stable fields.
- The session must not weaken active-conversation suppression or route payload behavior while strengthening sound proof.
- `lib/main.dart` assertions should pin the quiet foreground contract without turning a formatting-only change into a false failure; assert the important literal contract, not line spacing.

## exact tests and gates to run

Direct tests:

- `flutter test test/core/notifications/local_notification_support_test.dart`
- `flutter test test/features/push/application/background_message_handler_test.dart`
- `flutter test test/features/push/application/show_notification_use_case_test.dart`
- `flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `flutter test test/integration/notification_tap_smoke_test.dart`
- `flutter test test/features/push/application/ios_push_project_config_test.dart`

Named gates:

- none by default for this session
- run `./scripts/run_test_gates.sh baseline` only if Flutter production code changes in a way that touches startup, foreground push handling, or notification routing behavior

## known-failure interpretation

- Treat a failure in any of the direct tests above as blocking unless the failure is clearly pre-existing and unrelated to the touched proof additions.
- No known-red exception for this notification proof bundle is documented in `Test-Flight-Improv/test-gate-definitions.md`.

## done criteria

- `background_message_handler_test.dart` proves the fallback plugin show call uses the shared audible Android/iOS message notification details.
- `ios_push_project_config_test.dart` proves foreground remote presentation still sets `sound: false`.
- The direct notification suppression and routing suites listed above pass.
- No Flutter production behavior regresses.

## scope guard

- Do not change relay code, iOS native Notification Service Extension code, or smoke harnesses in this session.
- Do not add a new named gate.
- Do not rewrite the notification architecture or duplicate existing suppression/routing tests under new file names.

## accepted differences / intentionally out of scope

- Manual iOS audio observation remains an external follow-up for Session 3 acceptance; this session only strengthens deterministic repo-owned proof.
- Existing notification permission request tests remain sufficient for this session unless the new proof reveals a real gap tied directly to Report 75 behavior.

## dependency impact

- Session 3 should reuse these direct Flutter test results and document the manual iOS audible follow-up honestly.
- If Session 2 reveals a real Flutter production bug, Session 3 must not close the report until that fix and its direct tests land.
