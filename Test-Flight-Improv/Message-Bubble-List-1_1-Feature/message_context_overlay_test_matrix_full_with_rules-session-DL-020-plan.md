# Session DL-020 Plan

## Final verdict

- Safe to execute now with the current repo-local evidence and row-owned scope guard.
- Exact row proof now exists in `integration_test/notification_open_ui_smoke_test.dart` (`warm local notification open after delete never surfaces the original body inside the app shell`).

## Final plan

### real scope

- Close source row `DL-020` for "Notification deep-link / cold-start open after delete never shows the original inside the app shell" without merging it into adjacent rows.
- Prove only the app-shell open contract: opening the conversation through the existing notification or deep-link path must already land on deleted state.
- Execution ownership for this session remains code changes, but only after the shared prerequisite harness exists.

### closure bar

- Source row `DL-020` is updated in `message_context_overlay_test_matrix_full_with_rules.md` to Covered or Closed with exact in-app first-frame file-and-test evidence.
- This session does not finish accepted while the row is still backed only by notification sequencing tests or eventual post-open tombstone convergence.

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

- Existing repo tests already prove that notification payloads parse and that prepare or drain happens before route dispatch.
- No current test routes into a state-aware 1:1 conversation shell after delete and asserts the first in-app conversation frame already hides the original body.
- The blocker is narrower than "missing app-shell harness": the app-root and startup seams exist, but they do not yet prove `DL-020`'s render contract.

### files and repos to inspect next

- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `test/core/notifications/app_root_notification_open_test.dart`
- `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/integration/notification_tap_smoke_test.dart`
- `integration_test/notification_open_ui_smoke_test.dart`
- `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`

### existing tests covering this area

- `app_root_notification_open_test.dart`, `startup_router_notification_open_test.dart`, `notification_deeplink_integration_test.dart`, and `notification_tap_smoke_test.dart` prove payload and route sequencing, but not actual conversation render truth.
- `integration_test/notification_open_ui_smoke_test.dart` proves a harness screen opens after preparation, but it uses fake visible messages and cannot express real tombstone or edit state.
- `message_deletion_roundtrip_test.dart` and `offline_inbox_roundtrip_test.dart` prove delete persistence and later convergence, but not notification-open first frame inside the app shell.

### regression/tests to add first

- Add the shared state-aware notification-open first-render harness from `message_context_overlay_blocked_startup_deeplink_unblock_plan.md`.
- Then add one direct `DL-020` regression that opens the conversation via the existing notification or deep-link path after delete is already stored and asserts the first visible in-app frame is already tombstoned.

### step-by-step implementation plan

1. Land the shared startup and deep-link first-render harness.
2. Seed a deleted conversation state before the notification-open path begins.
3. Open through the existing app-root local or remote notification route.
4. Assert the first readable conversation frame never exposes the deleted plaintext.
5. Only if that regression fails, patch the smallest preparation or conversation-open seam.
6. Update the row, ledger, and inventory with exact evidence.

### risks and edge cases

- `startup_delete_before_render`
- `deep_link_latest_state`
- App-root warm opens and startup-router cold opens may diverge.
- A fake harness could appear green while the real conversation frame still flashes stale text.

### exact tests and gates to run

- `flutter test --no-pub test/core/notifications/app_root_notification_open_test.dart`
- `flutter test --no-pub test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `flutter test --no-pub test/integration/notification_deeplink_integration_test.dart`
- `flutter test --no-pub test/integration/notification_tap_smoke_test.dart`
- `flutter test --no-pub integration_test/notification_open_ui_smoke_test.dart`
- `flutter test --no-pub test/features/conversation/integration/message_deletion_roundtrip_test.dart`
- `flutter test --no-pub test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- Named gate: `startup_delete_before_render`
- Named gate: `deep_link_latest_state`

### known-failure interpretation

- If sequencing tests keep passing but the new first-frame regression fails, keep the session blocked or open and do not mark the row covered.
- Ignore unrelated pre-existing failures outside notification-open and direct-thread conversation seams, but record them if they block direct proof.

### done criteria

- Repo-local evidence proves the exact app-shell deep-link or notification-open contract for delete-before-render.
- The source matrix row is updated with concrete first-frame evidence and this session ledger is refreshed accordingly.

### scope guard

- Do not broaden this session into generic startup recovery or restart work that belongs to `SC-001`.
- Do not accept eventual tombstone state after open if the first meaningful frame still showed original content.

### accepted differences / intentionally out of scope

- Neighboring matrix rows stay unchanged unless their own proof is directly affected and separately recorded.
- OS push banner text stays out of scope; this row is about the in-app conversation shell.

### dependency impact

- This session depends on the shared startup and deep-link first-render prerequisite in `message_context_overlay_blocked_startup_deeplink_unblock_plan.md`; refresh this plan if that prerequisite changes materially.

## Structural blockers remaining

- None. The shared startup and deep-link first-render prerequisite landed through `integration_test/notification_open_ui_smoke_test.dart`.

## Incremental details intentionally deferred

- Whether the final proof belongs in the current notification-open UI smoke harness or a dedicated sibling.

## Accepted differences intentionally left unchanged

- The session remains row-owned even though the shared prerequisite harness also unblocks `DL-010`, `SC-001`, and `SC-009`.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_blocked_startup_deeplink_unblock_plan.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `test/core/notifications/app_root_notification_open_test.dart`
- `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/integration/notification_tap_smoke_test.dart`
- `integration_test/notification_open_ui_smoke_test.dart`
- `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`

## Why the plan is safe or unsafe to implement now

- Safe for row execution because the shared first-render harness has landed and direct app-shell first-frame proof already exists for `DL-020`.
