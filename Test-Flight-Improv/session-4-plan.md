# Session 4 Plan

## Final Verdict

`sufficient with adjustments`

This plan follows the Sufficiency Boundary from
`14-regression-test-strategy.md`, uses `01-unit-test-coverage.md` and
`02-integration-test-coverage.md` as the Session 4 gap source, and uses the
Review Exit Rule from `15-session-todo-roadmap.md`.

## 1. Scope

Session 4 stays strictly on the notification adapter boundary:

- `lib/core/notifications/flutter_notification_service.dart`
- `lib/core/notifications/local_notification_support.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`
- narrow execution awareness of
  `lib/features/push/application/background_message_handler.dart`

The goal is to add direct coverage for the plugin/channel boundary that is still
light in the current repo. This session must not broaden into notification
architecture work, deep-link redesign, bootstrap work, or startup/transport
testing.

## 2. Files To Inspect Next

- `lib/core/notifications/notification_service.dart`
- `lib/core/notifications/notification_route_target.dart`
- `lib/core/notifications/notification_route_dispatch.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/push/application/background_message_handler.dart`
- `test/shared/fakes/fake_notification_service.dart`
- `test/core/notifications/notification_route_dispatch_test.dart`
- `test/core/notifications/notification_push_tap_navigate_test.dart`
- `test/core/notifications/notification_route_target_test.dart`
- `test/core/notifications/notification_route_target_sender_id_test.dart`
- `test/features/push/application/show_notification_use_case_test.dart`
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/features/posts/phase1/post_notification_open_flow_test.dart`

## 3. Existing Tests Covering This Area

The repo already covers the higher-level notification flow:

- `test/core/notifications/notification_route_dispatch_test.dart`
- `test/core/notifications/notification_push_tap_navigate_test.dart`
- `test/core/notifications/notification_route_target_test.dart`
- `test/core/notifications/notification_route_target_sender_id_test.dart`
- `test/features/push/application/show_notification_use_case_test.dart`
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/features/posts/phase1/post_notification_open_flow_test.dart`

What is not directly covered yet is the plugin-facing behavior in
`flutter_notification_service.dart` and `local_notification_support.dart`:

- plugin initialization
- channel creation
- one-shot initial payload consumption
- notification display wiring
- tap callback forwarding
- one narrow background-handler adapter assertion proving the fallback branch is
  still reachable without duplicating the full fallback matrix

## 4. Regression / Tests To Add First

Add these first:

- `test/core/notifications/flutter_notification_service_test.dart`
- `test/core/notifications/local_notification_support_test.dart`
- extend `test/features/push/application/background_message_handler_test.dart`
  with one narrow background adapter assertion

Primary coverage targets:

- `FlutterNotificationService.initialize()`
- `FlutterNotificationService.consumeInitialPayload()`
- `FlutterNotificationService.onNotificationTap`
- `FlutterNotificationService.showNotification()`
- `FlutterNotificationService.showMessageNotification()`
- `ensureMknoonNotificationChannel()`
- `mknoonMessagesNotificationDetails`
- `firebaseMessagingBackgroundHandler()` on a routable data-only message enters
  the local-notification fallback branch without broad re-testing of the
  fallback matrix

Keep `background_push_notification_fallback_test.dart` as the existing fallback
decision and payload contract. Use `background_message_handler_test.dart` for
one narrow adapter-boundary assertion only; do not rebuild the fallback matrix
there.

## 5. Step-By-Step Implementation Plan

1. Reconfirm from `01-unit-test-coverage.md`,
   `02-integration-test-coverage.md`, and the existing tests that route
   parsing, tap/open sequencing, deep-link flow, and post-notification open
   flow are already covered so Session 4 does not duplicate them.
2. Add `flutter_notification_service_test.dart` with a focused plugin harness.
   Use a mock-binary-messenger or method-channel test seam for
   `FlutterLocalNotificationsPlugin`.
3. Verify `initialize()` calls plugin initialization, captures launch payload,
   and triggers notification channel setup.
4. Verify `consumeInitialPayload()` is one-shot: first call returns the stored
   payload, second call returns `null`.
5. Verify tap callback forwarding through `onNotificationTap` for non-empty
   payloads and no callback on `null` or empty payload.
6. Verify `showNotification()` and `showMessageNotification()` forward title,
   body, payload, and notification details correctly.
7. Add `local_notification_support_test.dart` to verify
   `ensureMknoonNotificationChannel()` and the static notification details
   contract.
8. Extend `background_message_handler_test.dart` with one narrow assertion that
   a routable data-only push still reaches the fallback notification branch.
   Reuse `background_push_notification_fallback_test.dart` for the payload and
   title/body matrix instead of duplicating that matrix in the handler test.
9. Distinguish Android channel creation from the non-Android no-op path.
10. Keep production changes minimal. Prefer the smallest test harness rather
    than broad code refactoring.
11. Run targeted tests first, then the broader notification suites, then the
    Baseline Gate.

## 6. Risks And Edge Cases

- `flutter_local_notifications` is a plugin boundary and may require careful
  mock-messenger cleanup between tests.
- `String.hashCode` should not be asserted exactly; verify payload, title, body,
  and notification details instead.
- `consumeInitialPayload()` is intentionally one-shot.
- `ensureMknoonNotificationChannel()` is platform-specific.
- `background_message_handler.dart` uses global/plugin state and Firebase init,
  so any extension there should stay narrow.
- `flutter test test/core/notifications` may currently hit a macOS native-assets
  / `lipo` build issue in this workspace before Dart tests run; if it persists,
  record it explicitly as an environment blocker instead of weakening the test
  plan.
- Route/open coverage already exists; re-testing it as if uncovered would be
  overengineering.

## 7. Exact Tests To Run After Implementation

Run the new direct tests first:

```bash
flutter test test/core/notifications/flutter_notification_service_test.dart
flutter test test/core/notifications/local_notification_support_test.dart
flutter test test/features/push/application/background_message_handler_test.dart
```

Then run the relevant suites:

```bash
flutter test test/core/notifications
flutter test test/features/push/application
```

If `flutter test test/core/notifications` still fails before Dart execution
because of the current macOS native-assets / `lipo` issue, record that as an
environment blocker and keep the new file-level notification tests as the
required direct evidence.

Run this only if execution touches tap/open payload wiring beyond the pure
adapter harness:

```bash
flutter test test/integration/notification_deeplink_integration_test.dart
```

Then run the canonical Baseline Gate from `test-gate-definitions.md` /
`scripts/run_test_gates.sh`:

```bash
./scripts/run_test_gates.sh baseline
```

If multiple Flutter targets are attached, set an explicit device for the
integration-backed leg:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
```

## 8. Subsystem Gate(s) And Whether Startup / Transport Tests Are Needed

Required:

- direct notification adapter tests
- `flutter test test/core/notifications`
- `flutter test test/features/push/application`
- Baseline Gate

Not required by default:

- Startup / Transport Gate

Reason:

- Session 4 is bounded to plugin-adapter and local-notification correctness.
- It does not target bootstrap, resume, transport fallback, or device-backed
  media behavior.
- Existing routing/open-flow coverage already exists at the right layer.

## 9. Done Criteria

Session 4 is done when:

- `test/core/notifications/flutter_notification_service_test.dart` exists and
  proves plugin-boundary behavior.
- `test/core/notifications/local_notification_support_test.dart` exists and
  proves channel/details behavior.
- `background_push_notification_fallback_test.dart` remains the fallback logic
  matrix and `background_message_handler_test.dart` contains one narrow
  background adapter assertion instead of a second broad matrix.
- Existing route/open/fallback tests remain green.
- Targeted notification and push suites pass.
- The Baseline Gate passes.
- Any suite-level environment blocker is documented explicitly rather than
  silently skipping the gate.
- No startup/transport scope was pulled in.
- No broader notification architecture work was bundled.

## Structural Blockers Remaining

None.

## Incremental Details Intentionally Deferred

- Exact harness choice between method-channel mocking and mock-binary-messenger
  wiring.
- Exact assertion shape inside `background_message_handler_test.dart` as long as
  it proves the fallback branch without recreating the full fallback matrix.
- Whether `notification_deeplink_integration_test.dart` must be rerun based on
  the actual adapter seam touched during execution.

## Why It Is Safe To Execute Now

This is safe to execute now because the planner, reviewer, and arbiter found no
new structural blocker. The repo already has strong route/open-flow coverage
across chat, group, local open, and post notification flows; the remaining gap
is a narrow adapter/plugin boundary gap plus one explicit background-handler
adapter assertion. The only follow-up items left are harness details and
environment-blocker handling, not missing structural work.
