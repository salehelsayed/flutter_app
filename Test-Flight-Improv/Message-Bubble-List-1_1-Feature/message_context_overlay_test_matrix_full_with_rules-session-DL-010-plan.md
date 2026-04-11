# Session DL-010 Plan

## Final verdict

- Safe to execute now with the current repo-local evidence and row-owned scope guard.
- Exact row proof now exists in `integration_test/notification_open_ui_smoke_test.dart` (`cold remote open applies a pre-open delete before the first readable conversation frame`).

## Final plan

### real scope

- Close source row `DL-010` for "Critical regression: delete-for-everyone before the recipient opens the app" without merging it into adjacent rows.
- Prove only the recipient-first-open contract: once delete is already stored before first open, the conversation never exposes original plaintext on its first meaningful render.
- Execution ownership for this session remains code changes, but only after the shared prerequisite harness exists.

### closure bar

- Source row `DL-010` is updated in `message_context_overlay_test_matrix_full_with_rules.md` to Covered or Closed with exact first-frame file-and-test evidence.
- This session does not finish accepted while the row is still backed only by delete convergence tests or notification sequencing tests.

### source of truth

- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_blocked_startup_deeplink_unblock_plan.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- Current code and repo-local tests beat stale prose when they disagree.

### session classification

- implementation-ready

### exact problem statement

- Existing repo tests already prove delete convergence and startup or notification sequencing.
- No current test seeds a delete before recipient first open, routes through startup or app-root open, and asserts that the first readable conversation frame already shows the tombstone rather than stale plaintext.
- The blocker is narrower than "no harness exists": existing route-preparation seams exist, but they do not yet prove `DL-010`'s first-render contract.

### files and repos to inspect next

- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `test/core/notifications/app_root_notification_open_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `integration_test/notification_open_ui_smoke_test.dart`
- `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`

### existing tests covering this area

- `message_deletion_roundtrip_test.dart` and `offline_inbox_roundtrip_test.dart` prove delete and inbox convergence, but not recipient first render after cold open.
- `startup_router_notification_open_test.dart`, `chat_and_group_push_open_flow_test.dart`, and `app_root_notification_open_test.dart` prove prepare or drain happens before route, but they stop before conversation UI truth.
- `integration_test/notification_open_ui_smoke_test.dart` proves a fake harness list becomes visible after preparation, but it does not assert real tombstone rendering on first readable frame.

### regression/tests to add first

- Add the shared state-aware notification-open first-render harness from `message_context_overlay_blocked_startup_deeplink_unblock_plan.md`.
- Then add one direct `DL-010` regression that seeds original-plus-delete before first open and asserts original body text is absent on the first readable conversation frame after startup or initial notification open.

### step-by-step implementation plan

1. Land the shared startup and deep-link first-render harness.
2. Seed a recipient store with an already-deleted conversation row before first open.
3. Open through the terminated startup or initial-notification path.
4. Assert the first readable conversation frame shows tombstone truth and never shows the deleted plaintext.
5. Only if that regression fails, patch the smallest preparation or conversation-open seam.
6. Update the row, ledger, and inventory with exact evidence.

### risks and edge cases

- `startup_delete_before_render`
- `deep_link_latest_state`
- A first-frame plaintext flash that disappears after later listener or inbox settling.
- Warm and terminated entry paths diverging even when they share deletion persistence.

### exact tests and gates to run

- `flutter test --no-pub test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `flutter test --no-pub test/core/notifications/app_root_notification_open_test.dart`
- `flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `flutter test --no-pub integration_test/notification_open_ui_smoke_test.dart`
- `flutter test --no-pub test/features/conversation/integration/message_deletion_roundtrip_test.dart`
- `flutter test --no-pub test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- Named gate: `startup_delete_before_render`
- Named gate: `deep_link_latest_state`

### known-failure interpretation

- If delete convergence tests keep passing but the new first-render regression fails, keep the session blocked or open and do not mark the row covered.
- Ignore unrelated pre-existing failures outside startup, notification-open, and direct-thread conversation seams, but record them if they block direct proof.

### done criteria

- Repo-local evidence proves the exact recipient-first-open tombstone contract.
- The source matrix row is updated with concrete first-frame evidence and this session ledger is refreshed accordingly.

### scope guard

- Do not broaden this session into generic notification routing cleanup or group-open behavior.
- Do not accept eventual tombstone state after extra pumps if the first meaningful render still showed plaintext.

### accepted differences / intentionally out of scope

- Neighboring matrix rows stay unchanged unless their own proof is directly affected and separately recorded.
- OS push text remains out of scope; this row is about in-app render after open.

### dependency impact

- This session depends on the shared startup and deep-link first-render prerequisite in `message_context_overlay_blocked_startup_deeplink_unblock_plan.md`; refresh this plan if that prerequisite changes materially.

## Structural blockers remaining

- None. The shared startup and deep-link first-render prerequisite landed through `integration_test/notification_open_ui_smoke_test.dart`.

## Incremental details intentionally deferred

- Whether the final proof lives in the existing notification-open UI smoke harness or a sibling test file.

## Accepted differences intentionally left unchanged

- The session remains row-owned even though the shared prerequisite harness also unblocks `DL-020`, `SC-001`, and `SC-009`.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_blocked_startup_deeplink_unblock_plan.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `test/core/notifications/app_root_notification_open_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `integration_test/notification_open_ui_smoke_test.dart`
- `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`

## Why the plan is safe or unsafe to implement now

- Safe for row execution because the shared first-render harness has landed and direct first-frame conversation proof already exists for `DL-010`.
