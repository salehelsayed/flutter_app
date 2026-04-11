# Session SC-001 Plan

## Final verdict

- Safe to execute now with the current repo-local evidence and row-owned scope guard.
- Exact row proof now exists in `integration_test/notification_open_ui_smoke_test.dart` (`relaunch open rebuilds stored quote edit delete and reaction state without stale pre-restart UI`).

## Final plan

### real scope

- Close source row `SC-001` for "App restart reconstructs quote, edit, delete, and reaction state from durable storage without stale UI" without merging it into adjacent rows.
- Prove the relaunch contract only: after full app recreate and reopen, the first readable conversation frame already reflects stored reply, edit, delete, and reaction truth.
- Execution ownership for this session remains code changes, but only after the shared prerequisite harness exists.

### closure bar

- Source row `SC-001` is updated in `message_context_overlay_test_matrix_full_with_rules.md` to Covered or Closed with exact relaunch file-and-test evidence.
- This session does not finish accepted while the row is backed only by screen-level dispose or rebuild tests such as `SC-008`.

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

- `SC-008` now proves conversation and feed screens can dispose and rebuild from the same stored truth.
- No current test proves a full app relaunch and reopen path reconstructs quote, edit, delete, and reaction state before the user-visible conversation frame appears.
- The blocker is narrower than "no restart harness exists": the repo has restart-capable direct-thread rebuild evidence, but it does not yet prove app-entry re-open behavior.

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
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `integration_test/notification_open_ui_smoke_test.dart`

### existing tests covering this area

- `conversation_screen_test.dart` and `feed_screen_test.dart` already prove `SC-008` screen-level restart rebuild, but they do not route through app startup or notification open.
- Notification-open sequencing tests prove preparation before route, but they do not assert restart-time conversation truth.
- No current relaunch test reuses durable stores, recreates the app shell, opens the conversation, and checks the first readable frame for quote, edit, delete, and reaction state together.

### regression/tests to add first

- Add the shared state-aware notification-open first-render harness from `message_context_overlay_blocked_startup_deeplink_unblock_plan.md`.
- Then add one direct `SC-001` regression that recreates the app with persisted stores, reopens the conversation through startup or app shell, and asserts quote, edit, delete, and reaction truth on the first readable frame.

### step-by-step implementation plan

1. Land the shared startup and deep-link first-render harness.
2. Seed durable conversation state containing reply, edit, delete, and reaction mutations before relaunch.
3. Recreate the app shell with the same persisted stores.
4. Open the conversation through the real startup or app-root path.
5. Assert the first readable conversation frame already reflects stored overlay state.
6. Only if that regression fails, patch the smallest preparation, materialization, or route-open seam.
7. Update the row, ledger, and inventory with exact evidence.

### risks and edge cases

- `durable_state_rebuild`
- `stream_convergence`
- `sender_identity_alignment`
- `delete_wins_conflict_resolution`
- `schema_overlay_state_migration`
- A passing `SC-008` rebuild test could hide a failing app-entry relaunch flow.

### exact tests and gates to run

- `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test --no-pub test/features/feed/presentation/screens/feed_screen_test.dart`
- `flutter test --no-pub test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `flutter test --no-pub test/core/notifications/app_root_notification_open_test.dart`
- `flutter test --no-pub integration_test/notification_open_ui_smoke_test.dart`
- Named gate: `durable_state_rebuild`
- Named gate: `stream_convergence`
- Named gate: `sender_identity_alignment`
- Named gate: `delete_wins_conflict_resolution`
- Named gate: `schema_overlay_state_migration`

### known-failure interpretation

- If screen-level rebuild tests pass but the new relaunch regression fails, keep the session blocked or open and do not mark the row covered.
- Ignore unrelated pre-existing failures outside startup, relaunch, and direct-thread conversation seams, but record them if they block direct proof.

### done criteria

- Repo-local evidence proves the exact relaunch contract for stored reply, edit, delete, and reaction state.
- The source matrix row is updated with concrete relaunch evidence and this session ledger is refreshed accordingly.

### scope guard

- Do not broaden this session into group restart behavior or notification payload redesign.
- Do not settle for eventual listener convergence after open; the row is about the first readable frame after restart.

### accepted differences / intentionally out of scope

- Neighboring matrix rows stay unchanged unless their own proof is directly affected and separately recorded.
- Feed restart parity is already handled by `SC-008`; revisit feed here only if the shared harness needs it to prove a common direct-thread load path.

### dependency impact

- This session depends on the shared startup and deep-link first-render prerequisite in `message_context_overlay_blocked_startup_deeplink_unblock_plan.md`; refresh this plan if that prerequisite changes materially.

## Structural blockers remaining

- None. The shared startup and deep-link first-render prerequisite landed through `integration_test/notification_open_ui_smoke_test.dart`.

## Incremental details intentionally deferred

- Whether the final relaunch proof lives in a widget-style recreate test, integration-style harness, or both.

## Accepted differences intentionally left unchanged

- The session remains row-owned even though the shared prerequisite harness also unblocks `DL-010`, `DL-020`, and `SC-009`.

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
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `integration_test/notification_open_ui_smoke_test.dart`

## Why the plan is safe or unsafe to implement now

- Safe for row execution because the shared first-render harness has landed and direct relaunch-time first-frame proof already exists for `SC-001`.
