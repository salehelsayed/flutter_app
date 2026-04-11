# Session SC-009 Plan

## Final verdict

- Safe to execute now with the current repo-local evidence and row-owned scope guard.
- Exact row proof now exists in `integration_test/notification_open_ui_smoke_test.dart` (`warm remote open after background edit and delete shows only the latest stored state on first render`).

## Final plan

### real scope

- Close source row `SC-009` for "In-app deep-link render after background edit or delete resolves to the latest state" without merging it into adjacent rows.
- Prove only the background-open contract: if edit or delete lands while the app is backgrounded, the route-entry conversation frame must already show latest state.
- Execution ownership for this session remains code changes, but only after the shared prerequisite harness exists.

### closure bar

- Source row `SC-009` is updated in `message_context_overlay_test_matrix_full_with_rules.md` to Covered or Closed with exact background-open first-frame evidence.
- This session does not finish accepted while the row is backed only by sequencing tests or eventual listener convergence after open.

### source of truth

- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_blocked_startup_deeplink_unblock_plan.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `lib/features/conversation/application/load_conversation_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/reaction_listener.dart`
- Current code and repo-local tests beat stale prose when they disagree.

### session classification

- implementation-ready

### exact problem statement

- Existing repo tests already prove notification-open sequencing for background and terminated paths.
- No current test proves that an app reopened from background after an edit or delete routes into a conversation whose first readable frame already reflects the latest stored state.
- The blocker is narrower than "missing deep-link harness": the route-open seams exist, but they do not yet prove `SC-009`'s route-entry render contract.

### files and repos to inspect next

- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `lib/features/conversation/application/load_conversation_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/reaction_listener.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/core/notifications/app_root_notification_open_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/integration/notification_tap_smoke_test.dart`
- `integration_test/notification_open_ui_smoke_test.dart`

### existing tests covering this area

- `chat_and_group_push_open_flow_test.dart`, `app_root_notification_open_test.dart`, `notification_deeplink_integration_test.dart`, and `notification_tap_smoke_test.dart` prove prepare and route sequencing, but not actual conversation render truth.
- `conversation_screen_test.dart` and `feed_screen_test.dart` prove stored-state rebuild, but not background-open deep-link entry.
- No current test opens the conversation from a backgrounded state after edit or delete and asserts the first visible frame on entry.

### regression/tests to add first

- Add the shared state-aware notification-open first-render harness from `message_context_overlay_blocked_startup_deeplink_unblock_plan.md`.
- Then add one direct `SC-009` regression that delivers edit or delete while backgrounded, reopens through the existing route path, and asserts the first readable conversation frame already reflects latest state.

### step-by-step implementation plan

1. Land the shared startup and deep-link first-render harness.
2. Seed or deliver edit or delete while the app is in a background-equivalent state.
3. Reopen through the existing app route or notification path.
4. Assert the route-entry conversation frame already shows edited or deleted truth.
5. Only if that regression fails, patch the smallest preparation, materialization, or route-open seam.
6. Update the row, ledger, and inventory with exact evidence.

### risks and edge cases

- `durable_state_rebuild`
- `stream_convergence`
- `sender_identity_alignment`
- `delete_wins_conflict_resolution`
- `schema_overlay_state_migration`
- Background-open and terminated-open behavior may diverge even if they share the same preparation helper.

### exact tests and gates to run

- `flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `flutter test --no-pub test/core/notifications/app_root_notification_open_test.dart`
- `flutter test --no-pub test/integration/notification_deeplink_integration_test.dart`
- `flutter test --no-pub test/integration/notification_tap_smoke_test.dart`
- `flutter test --no-pub integration_test/notification_open_ui_smoke_test.dart`
- `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test --no-pub test/features/feed/presentation/screens/feed_screen_test.dart`
- Named gate: `durable_state_rebuild`
- Named gate: `stream_convergence`
- Named gate: `sender_identity_alignment`
- Named gate: `delete_wins_conflict_resolution`
- Named gate: `schema_overlay_state_migration`

### known-failure interpretation

- If sequencing tests pass but the new route-entry render regression fails, keep the session blocked or open and do not mark the row covered.
- Ignore unrelated pre-existing failures outside startup, notification-open, and direct-thread conversation seams, but record them if they block direct proof.

### done criteria

- Repo-local evidence proves the exact background-open render contract for edit and delete.
- The source matrix row is updated with concrete first-frame evidence and this session ledger is refreshed accordingly.

### scope guard

- Do not broaden this session into full relaunch durability work that belongs to `SC-001`.
- Do not accept eventual listener convergence after open if the first meaningful frame still showed stale pre-sync UI.

### accepted differences / intentionally out of scope

- Neighboring matrix rows stay unchanged unless their own proof is directly affected and separately recorded.
- OS push banner or body text stays out of scope; this row is about the in-app route-entry render.

### dependency impact

- This session depends on the shared startup and deep-link first-render prerequisite in `message_context_overlay_blocked_startup_deeplink_unblock_plan.md`; refresh this plan if that prerequisite changes materially.

## Structural blockers remaining

- None. The shared startup and deep-link first-render prerequisite landed through `integration_test/notification_open_ui_smoke_test.dart`.

## Incremental details intentionally deferred

- Whether edit and delete share one background-open regression or need separate assertions inside the same harness.

## Accepted differences intentionally left unchanged

- The session remains row-owned even though the shared prerequisite harness also unblocks `DL-010`, `DL-020`, and `SC-001`.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_blocked_startup_deeplink_unblock_plan.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `lib/features/conversation/application/load_conversation_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/reaction_listener.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/core/notifications/app_root_notification_open_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/integration/notification_tap_smoke_test.dart`
- `integration_test/notification_open_ui_smoke_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`

## Why the plan is safe or unsafe to implement now

- Safe for row execution because the shared first-render harness has landed and direct background-open first-frame proof already exists for `SC-009`.
