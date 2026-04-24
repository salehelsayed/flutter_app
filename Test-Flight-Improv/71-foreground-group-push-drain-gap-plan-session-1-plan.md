# Session 1 Plan - Foreground route-aware drain implementation and deterministic seam coverage

## Final verdict

- Status:
  `accepted`
- Accepted on:
  `2026-04-22`
- Why:
  - `lib/main.dart` now delegates foreground FCM handling through the new
    `handleForegroundRemoteMessage(...)` use case instead of always draining
    only the 1:1 inbox.
  - The new foreground use case now routes chat/contact-request/intros through
    the 1:1 drain, routes group pushes through
    `drainGroupOfflineInboxForGroup(groupId)`, logs routed / unroutable /
    error flow events, and swallows drain failures so the stream stays alive.
  - The new direct foreground suite passed, the adjacent notification and
    resume regressions passed, and both required named gates
    `./scripts/run_test_gates.sh groups` and
    `./scripts/run_test_gates.sh baseline` passed.

## Final plan

### real scope

- Add the new foreground push routing use case under
  `lib/features/push/application/`.
- Replace the unconditional foreground `drainOfflineInbox()` bridge in
  `lib/main.dart` with a thin `unawaited(handleForegroundRemoteMessage(...))`
  bridge.
- Emit the foreground routed / unroutable / error flow events required by
  Report `71`.
- Add the direct unit and regression coverage needed to pin the foreground
  routing contract and protect adjacent notification seams.

Out of scope in this session:

- the foreground relay-backed integration proof in
  `integration_test/foreground_group_push_drain_test.dart`
- stable matrix and gate-doc updates
- manual two-device smoke attestation and post-TestFlight telemetry closure

### closure bar

- Foreground chat, contact-request, intros, and group-invite payloads preserve
  the current 1:1 drain behavior.
- Foreground group pushes call
  `drainGroupOfflineInboxForGroup(groupId)` exactly through the targeted group
  path.
- Foreground unroutable or malformed payloads do not drain either inbox.
- Drain errors are swallowed, logged, and do not crash the foreground stream.
- The direct tests below pass, and the required named gates are run honestly.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md`
  - `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan-session-breakdown.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code and tests beat stale prose when they disagree.
- Verified repo seams:
  - `lib/main.dart`
  - `lib/core/notifications/notification_route_target.dart`
  - `lib/features/push/application/background_message_handler.dart`
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `test/core/notifications/notification_route_target_test.dart`
  - `test/core/notifications/notification_route_contract_matrix_test.dart`
  - `test/features/push/application/background_message_handler_test.dart`
  - `test/features/push/application/prepare_notification_open_use_case_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- The current foreground FCM listener treats every message as a 1:1 inbox
  event, so a foregrounded client that receives `type: group_message` never
  hits the group inbox drain seam even though the payload already carries
  `groupId`.
- The repo already has a canonical route-target parser and a kind-aware
  notification-open preparation policy. The open bug is the missing foreground
  adapter, not a missing parser or missing group drain implementation.
- The foreground fix must preserve existing 1:1 behavior, keep posts and other
  unroutable payloads from triggering accidental drains, and avoid adding a new
  duplicate-suppression gate write.

### files and repos to inspect next

- Production files:
  - `lib/main.dart`
  - `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
  - `lib/core/notifications/notification_route_target.dart`
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/core/utils/flow_event_emitter.dart`
- Direct tests:
  - `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
  - `test/features/push/application/remote_message_fixtures.dart`
  - `test/core/notifications/notification_route_target_test.dart`
  - `test/core/notifications/notification_route_contract_matrix_test.dart`
  - `test/features/push/application/prepare_notification_open_use_case_test.dart`
  - `test/features/push/application/background_message_handler_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`

### existing tests covering this area

- `notification_route_target_test.dart` already proves the main payload parsing
  cases for chat, group, contact-request, intros, and group payloads.
- `notification_route_contract_matrix_test.dart` already proves the canonical
  remote-data parsing and drain policy for conversation, group, and post-like
  targets.
- `prepare_notification_open_use_case_test.dart` already proves the intended
  kind-aware 1:1 versus group drain policy.
- `background_message_handler_test.dart`, `show_notification_use_case_test.dart`,
  and `handle_app_resumed_group_recovery_test.dart` already pin the adjacent
  background, local-notification, and resume recovery seams.
- Missing today:
  - no foreground-specific use-case unit test for kind-aware routing
  - no direct proof that malformed/unroutable foreground payloads skip all
    drains safely
  - no direct proof that foreground drain failures are swallowed and logged

### regression/tests to add first

- Add `handle_foreground_remote_message_use_case_test.dart` first to pin U1-U9
  from Report `71` before moving the `main.dart` bridge.
- Add the small shared remote-message fixture helper so the foreground tests
  and any later background/notification contract tests share one wire shape.
- Extend `notification_route_target_test.dart` only for missing edge coverage
  discovered while writing the new foreground regression.

### step-by-step implementation plan

1. Add the new foreground routing use case with the existing
   `NotificationRouteTarget.fromRemoteMessageData(...)` parser as the only
   route-resolution source.
2. Add the new use-case unit test file plus shared remote-message fixtures and
   get the required cases red first.
3. Thread the new use case into `lib/main.dart` as a thin bridge, wiring the
   existing targeted group drain dependencies from `MyApp`.
4. Land any minimal route-target edge-case hardening needed by the new tests,
   but stop if the work expands beyond foreground routing.
5. Run the exact direct tests below, then the required named gates.
6. If the verified state is clean, refresh the Session `1` ledger entry in the
   breakdown artifact and stop; Session `2` owns the integration proof and
   stable-doc closure.

### risks and edge cases

- `group_message` without a valid `groupId` must stay unroutable; do not fall
  back to an all-groups drain in this session.
- Payload-only `group:<id>` fallback routing must still work.
- `group_invite` currently maps to `NotificationRouteTargetKind.intros`; keep
  that accepted difference and do not invent a new foreground invite route.
- Keep the new use case non-throwing so one bad push does not break the next
  foreground `onMessage` event.
- Do not widen into gossipsub rejoin logic, relay payload changes, or local
  notification policy changes.

### exact tests and gates to run

- Direct tests:
  - `flutter test test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
  - `flutter test test/core/notifications/notification_route_target_test.dart`
  - `flutter test test/core/notifications/notification_route_contract_matrix_test.dart`
  - `flutter test test/features/push/application/prepare_notification_open_use_case_test.dart`
  - `flutter test test/features/push/application/background_message_handler_test.dart`
  - `flutter test test/features/push/application/show_notification_use_case_test.dart`
  - `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
  - do not run `transport` unless the final code change broadens into
    startup/resume/transport behavior beyond the foreground listener seam

### known-failure interpretation

- The new foreground use-case suite has no accepted failure exemption.
- If `baseline` or `groups` fail, treat the result as a new blocker unless the
  exact same unrelated failure is already recorded in the touched breakdown or
  gate docs and the changed code clearly did not widen it.
- If the code change forces a broader lifecycle rewrite, stop and re-scope
  rather than hiding the expansion inside Session `1`.

### done criteria

- The foreground use case exists and is wired from `lib/main.dart`.
- U1-U9-equivalent direct coverage passes.
- The adjacent route-target, background, notification, and resume regressions
  listed above pass.
- `groups` and `baseline` are run honestly.
- The Session `1` breakdown ledger is refreshed with the verified result.

### scope guard

- Do not add the Session `2` integration harness in this session.
- Do not change relay payload shape, gossipsub subscription logic, or
  `recentRemoteNotificationGate` behavior.
- Do not widen into notification-open routing, resume sequencing, or unrelated
  UI cleanup.

### accepted differences / intentionally out of scope

- `group_invite` continues to route through `intros`, and foreground handling
  keeps that existing product contract.
- Posts and post comments remain foreground-unroutable in this session even if
  they parse into route targets elsewhere in the notification stack.
- Manual smoke and post-TestFlight telemetry remain Session `2` or final
  closure concerns, not Session `1` blockers.

### dependency impact

- Session `2` depends on this session landing the production foreground router
  and its deterministic direct proof first.
- If Session `1` has to widen beyond the foreground listener seam, Session `2`
  should pause and the breakdown should be refreshed before continuing.
