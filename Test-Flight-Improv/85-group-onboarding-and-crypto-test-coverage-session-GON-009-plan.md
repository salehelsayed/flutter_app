# GON-009 Plan: Group Notification, Deep-Link, Stale Access, and Admin Removal Boundaries

## real scope

- Add focused host-side regressions for stale removed-group notification access denial and no post-removal local notification after self-removal cleanup.
- Use existing notification-open and route-target seams instead of introducing new simulator orchestration in this session.
- Keep foreground/background/terminated OS-state simulator proof as residual coverage.

## closure bar

- `TC-29` has automated evidence that local self-removal cleanup deletes group access and later group traffic does not create a local notification.
- `TC-31` has automated route-target evidence that a stale group notification tap cannot recover or open a removed group when the local group row is gone.
- Existing background and terminated group-message notification-open tests remain the route sequencing baseline.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-009`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-29 and TC-31.

## session classification

`implementation-ready`

## exact problem statement

Report 85 marks admin add/remove notification and stale deep-link access as partial because existing tests prove membership cleanup and notification-open sequencing separately, but do not pin the removed-user stale route denial and no-notification boundary in one focused place.

## files and repos to inspect next

- `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`

## existing tests covering this area

- `group_message_listener_test.dart` already proves self-removal calls `leaveGroup`, deletes local group state, and emits `groupRemovedStream`.
- `resolve_group_notification_route_target_use_case_test.dart` already proves route recovery for existing groups, pending invites, and missing groups.
- `chat_and_group_push_open_flow_test.dart` proves background and terminated group pushes drain targeted group inbox before routing.
- `show_notification_use_case_test.dart` and group listener notification tests already prove active group suppression and mute suppression.

## regression/tests to add first

- Add a stale removed-group route denial test to `resolve_group_notification_route_target_use_case_test.dart`.
- Add a self-removal plus post-removal group traffic notification suppression test to `group_message_listener_test.dart`.

## step-by-step implementation plan

1. Create the GON-009 plan artifact.
2. Add a route-target regression that starts with a known group, deletes it as a removed-user cleanup proxy, drains once, and returns `missing` instead of a group or pending invite.
3. Add a group listener regression that processes a self-removal system event, then receives later group traffic and asserts no message or local notification is created.
4. Run the two focused test files.
5. Update Report 85, gate definitions if needed, closure references, and the session breakdown ledger.

## risks and edge cases

- This does not prove full OS notification behavior across physical foreground/background/terminated app states.
- Dissolved groups intentionally keep read-only history available, so this session should not convert dissolved notification taps into missing routes.

## exact tests and gates to run

- `flutter test test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
- `flutter test test/features/groups/application/group_message_listener_test.dart`
- `./scripts/run_test_gates.sh completeness-check`

## known-failure interpretation

- A resolved group for the stale removed route means a notification tap can reopen a locally removed group.
- A saved message or notification after self-removal means post-removal traffic can still surface to a removed member.

## done criteria

- Focused tests pass.
- Source doc and session breakdown classify TC-29/TC-31 as host-side covered/partial for simulator/OS-state residuals.

## scope guard

- Do not build a new paired simulator harness in this session.
- Do not change dissolved-group read-only history behavior.

## accepted differences / intentionally out of scope

- Full OS background/terminated notification delivery, stale tap UI assertions on paired simulators, and route exit screenshots remain simulator-matrix work for later sessions.

## dependency impact

- Later simulator sessions can use these host-side route and notification-denial checks as a stable precondition.
