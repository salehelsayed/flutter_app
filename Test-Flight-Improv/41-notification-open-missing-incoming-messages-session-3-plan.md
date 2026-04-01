# Session 3 Plan - Notification-open parity, acceptance proof, and Report 41 closure

## Final verdict

`implementation-ready`

Current repo evidence after accepted Sessions `1` and `2` shows the remaining
open Report `41` seam is now the app-root notification-open contract:

- `lib/features/identity/presentation/startup_router.dart` already applies
  `prepareNotificationOpen(...)` on the terminated remote-push path via
  `_prepareNotificationRouteTarget(...)`.
- `lib/main.dart` still handles:
  - warm remote push opens through `FirebaseMessaging.onMessageOpenedApp`
  - terminated local notification launches through
    `_handleInitialLocalNotificationLaunch()`
  - warm local notification taps through `_onNotificationTap(...)`
  without any `onBeforeRouteTarget` preparation callback.
- The current direct notification tests mostly prove the helper-level dispatch
  contract, not the real app-root handlers that users actually hit outside the
  terminated remote path.

The durable inbox recovery prerequisite is now accepted, so Report `41`
progresses only if every real notification-open entry point routes through the
same truthful prepare-before-route contract and the maintenance docs are
refreshed to reflect that accepted state.

## Final plan

### real scope

- Make the real app-root notification-open handlers in `lib/main.dart` use the
  same prepare-before-route contract already used by the terminated remote
  startup path.
- Centralize that app-root preparation seam into a narrow testable helper or
  coordinator instead of leaving three separate ad hoc call sites in `MyApp`.
- Keep the existing route-target contract unchanged for conversations, groups,
  intros, and posts; this session is about truthful preparation order, not a
  payload redesign.
- Preserve post-notification routing behavior and the existing
  `PostNotificationOpenCoordinator` flow while making sure shared root
  notification wiring stays coherent.
- Add direct proof for warm remote taps, terminated local launches, and warm
  local taps at the real app-root seam, then refresh closure docs only if the
  final verified state now satisfies Report `41`.

### closure bar

- Warm remote push opens, terminated local notification launches, and warm
  local notification taps all prepare conversation/group targets before route.
- The terminated remote path stays on that same contract and does not regress.
- The real app-root handler seam has direct regression coverage rather than
  relying only on lower-level notification-route helper tests.
- Posts/intros/shared notification routing behavior remains truthful and does
  not regress while chat/group notification opens are tightened.
- Report `41` closure docs are updated only if the verified state actually
  reaches the user-visible acceptance bar.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/00-INDEX.md`
- Current code and tests beat stale prose when they disagree.
- Verified repo seams:
  - `lib/main.dart`
  - `lib/features/identity/presentation/startup_router.dart`
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
  - `lib/core/notifications/notification_route_dispatch.dart`
  - `lib/features/posts/application/post_notification_open_coordinator.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/integration/notification_deeplink_integration_test.dart`
  - `test/core/notifications/notification_push_tap_navigate_test.dart`
  - `test/features/posts/phase1/post_notification_open_flow_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- Report `41` now has accepted staged inbox retrieval plus accepted durable
  client replay, but users can still open the app through warm remote or local
  notification handlers that navigate before the target thread's required
  catch-up is prepared.
- Because the terminated remote startup path already uses preparation, the
  remaining risk is inconsistent app-root notification wiring rather than a
  missing preparation contract.
- The repo still lacks direct proof for the real `lib/main.dart` notification
  handlers, so helper-level dispatch tests alone are not enough to close the
  report honestly.

### files and repos to inspect next

- Production files:
  - `lib/main.dart`
  - one new or existing narrow notification-open helper under `lib/core/notifications/`
    or `lib/features/push/application/` if extraction is required for testability
  - `lib/features/identity/presentation/startup_router.dart`
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
  - `lib/features/posts/application/post_notification_open_coordinator.dart`
- Direct tests:
  - one new direct app-root notification-open regression proving preparation
    order for:
    - warm remote push open
    - terminated local notification launch
    - warm local notification tap
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/integration/notification_deeplink_integration_test.dart`
  - `test/core/notifications/notification_push_tap_navigate_test.dart`
  - `test/features/posts/phase1/post_notification_open_flow_test.dart`
- Closure docs:
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    only if final wording about inbox recovery / notification-open trust needs
    a stable maintenance refresh

### existing tests covering this area

- `prepare_notification_open_use_case_test.dart` already proves the
  conversation/group/intros/posts preparation contract itself.
- `chat_and_group_push_open_flow_test.dart` and
  `notification_deeplink_integration_test.dart` already prove the dispatch
  helpers can enforce prepare-before-route when the callback is provided.
- `post_notification_open_flow_test.dart` already acts as adjacent evidence
  that fully covered notification-open coordination exists elsewhere in the
  app.
- Missing today:
  - no direct regression proving the real `MyApp` warm remote listener passes
    the preparation callback
  - no direct regression proving terminated local launch uses preparation
    before route
  - no direct regression proving warm local tap uses preparation before route

### regression/tests to add first

- Add the narrow app-root handler regression first so the real `lib/main.dart`
  seam is pinned before the code moves.
- Refresh existing helper/integration notification tests only as needed to
  match any small extraction or shared helper reuse.
- Keep a direct post-notification open guard in the proof set so shared root
  routing changes do not regress post behavior.

### step-by-step implementation plan

1. Extract the `lib/main.dart` notification-open entry points into a narrow
   shared helper or coordinator if needed so the real app-root behavior is
   directly testable.
2. Thread one shared preparation callback through:
   - `_handleInitialLocalNotificationLaunch()`
   - `_onNotificationTap(...)`
   - the `FirebaseMessaging.onMessageOpenedApp` listener
3. Keep `StartupRouter` on the same preparation contract and reuse the same
   helper only if that simplifies the contract without widening scope.
4. Add direct regressions for warm remote, terminated local, and warm local
   open ordering at the real app-root seam.
5. Run the direct notification suites and the required named gates below.
6. If the verified state closes Report `41`, refresh the breakdown ledger and
   maintenance docs in the same session.

### risks and edge cases

- Do not double-prepare a route target after it was already prepared on the
  terminated remote startup path.
- Keep missing-route handling unchanged for malformed payloads or unroutable
  remote data.
- Do not regress post notification opens while tightening chat/group app-root
  handling.
- Keep the session scoped to notification-open parity and closure; do not
  reopen relay protocol, DB schema, or general unread-state work.

### exact tests and gates to run

- Direct tests:
  - the new direct app-root notification-open regression
  - `flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `flutter test test/integration/notification_deeplink_integration_test.dart`
  - `flutter test test/core/notifications/notification_push_tap_navigate_test.dart`
  - `flutter test test/features/posts/phase1/post_notification_open_flow_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
  - do not rerun `transport` unless execution unexpectedly changes broader
    startup/resume ordering beyond threading the existing preparation callback

### known-failure interpretation

- The new direct app-root notification-open regression has no accepted failure
  exemption in this session.
- If `baseline` still reports the known unrelated macOS harness noise already
  recorded in this report, record it honestly only if the exact failure is
  unchanged.
- If execution unexpectedly forces a broader startup-lifecycle rewrite, stop
  and re-scope rather than pretending this session stayed narrow.

### done criteria

- All real notification-open entry points that can route chat/group targets
  now prepare before route.
- Direct proof exists at the app-root handler seam.
- The required direct suites pass.
- `1to1` and `baseline` are run honestly.
- The breakdown ledger and maintenance docs reflect the final accepted state.
