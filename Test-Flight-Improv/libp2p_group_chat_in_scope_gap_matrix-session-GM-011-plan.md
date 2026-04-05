# Session GM-011 Plan - Notification deep link

## Final verdict

`implementation-ready`

Current repo evidence shows `GM-011` is a narrow route-contract gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `GM-011` as `implementation-ready` with `code changes and tests`
  ownership.
- The repo already routes group notifications to the correct group only after
  targeted group catch-up.
- The missing behavior is narrower: the notification payload and route target
  do not currently preserve a message anchor, so the group screen cannot land
  on the relevant message context after the user taps the notification.

The smallest safe session is therefore to extend the group notification route
contract with an optional message anchor, keep old payloads compatible, surface
that anchor as visible context in the group screen, verify the direct tests and
the named gates, and then update the row-owned docs truthfully.

## Final plan

### real scope

- Close source row `GM-011` only: preserve a group message anchor through local
  notification payloads, push-open route resolution, and the group conversation
  screen so the app can open the correct group with the relevant message
  context highlighted.
- Keep the change bounded to the notification route contract, local payload
  display path, and group-screen context presentation.
- Preferred code-entry files:
  - `lib/core/notifications/notification_route_target.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/main.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- Update only the row-owned closure docs named by the breakdown after the proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`

### closure bar

- Group notification payloads can carry a message anchor without breaking older
  unanchored payloads.
- Group push-open routing preserves that anchor through prepare and route handoff.
- Opening a group from the anchored route highlights the targeted message
  context on the group screen.
- Direct proof passes, and the named gates pass or are recorded truthfully if
  unrelated failures remain outside this row's write scope.
- `GM-011` is updated to `Closed` or `Covered` only after the docs cite the
  landed evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Skill guidance:
  - `mobile-notification-routing-and-deep-linking`
- Current code/tests win over stale prose when they disagree.

### session classification

`implementation-ready`

### exact problem statement

- Group notifications already route to the correct group after targeted
  catch-up.
- The repo drops the tapped message identity before the route target reaches
  the group screen, so the app cannot prove it lands on the relevant message
  context.
- This session should not widen into a generalized notification coordinator or
  a broad group-navigation rewrite.

### regression/tests to add first

- Add route-contract tests proving group route targets preserve an optional
  message anchor through remote-data parsing and local payload round-trips.
- Add notification payload tests proving local group notifications emit the
  anchored payload contract.
- Add a group screen regression proving the targeted message is highlighted when
  the route opens that group with a message anchor.

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on the group notification
   route contract only.
2. Extend the group notification route target with an optional message anchor
   while keeping old `group:<groupId>` payloads valid.
3. Thread the anchored payload through local group notification display and
   group push-open routing.
4. Surface the anchor in `GroupConversationWired` and
   `GroupConversationScreen` as visible message context.
5. Run the direct suites and named gates below.
6. Update the matrix row, breakdown ledger/notes, and
   `09-network-group-messaging.md` only after the landed proof passes.

### risks and edge cases

- Keep old group payloads valid so existing notification taps do not regress.
- Do not couple the route contract to notification-delivery dedupe logic more
  than necessary.
- Do not widen into a scroll-position coordinator unless the highlight-based
  context path disproves itself.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/core/notifications/notification_route_target_test.dart test/core/notifications/app_root_notification_open_test.dart test/features/push/application/chat_and_group_push_open_flow_test.dart test/features/push/application/show_notification_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/core/notifications/flutter_notification_service_test.dart test/features/push/application/background_push_notification_fallback_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

### known-failure interpretation

- If the anchored route target cannot survive local payload parsing or remote
  push-open handoff, the repo still has a real notification deep-link gap.
- If the group screen cannot show the targeted message context after route
  open, the row remains open even if the payload contract is richer.
- If `baseline` fails in unrelated existing seams, keep those failures separate
  unless they touch notification routing or the group screen highlight change.

### done criteria

- Group notification payloads and push-open routing preserve an optional
  message anchor.
- Opening the anchored group route shows the targeted message context on the
  group screen.
- The direct suite above passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` is run and
  recorded truthfully.
- `GM-011` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `09-network-group-messaging.md` no longer treats
  the row as missing a message anchor contract.

### scope guard

- Do not widen into contact-request, post, or 1:1 message anchor contracts.
- Do not invent a second notification payload format for local vs remote group
  notifications.
- Do not rewrite the whole navigation stack; keep routing centralized in the
  existing notification-open path.

### accepted differences / intentionally out of scope

- Rich historical scrolling beyond the loaded group page remains outside this
  session.
- Full notification-center UX beyond preserving the tapped group message
  context remains outside this row.

### dependency impact

- `GM-011` can close independently once the anchored route contract and group
  screen proof land.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
