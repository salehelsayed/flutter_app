# Message Context Overlay Startup And Deep-Link First-Render Unblock Plan

## Final verdict

- Completed on 2026-04-10 in degraded local continuation after fresh-child execution no-progressed in this environment.
- The shared prerequisite is now satisfied by the landed state-aware notification-open first-render harness in `integration_test/notification_open_ui_smoke_test.dart`.
- The harness now closes `DL-010`, `DL-020`, `SC-001`, and `SC-009` with exact first-frame conversation proof rather than sequencing-only evidence.

## Final plan

### real scope

- Extend the existing startup, app-root notification-open, and restart test harnesses so they can seed stored 1:1 conversation state and assert the first meaningful conversation frame after open.
- Cover only the blocked row contracts: pre-open delete, notification/deep-link open after delete, full restart relaunch from durable state, and backgrounded open after edit/delete.
- Leave group routing, post routing, OS notification text, and unrelated message flows unchanged unless one of the new regressions proves a shared startup bug.

### closure bar

- This prerequisite is satisfied only when repo-local tests prove that a 1:1 conversation opened from cold start, local or remote notification tap, or relaunch never shows stale plaintext or stale pre-mutation UI before the latest stored delete, edit, reply, and reaction truth is visible.
- Sequencing-only tests that stop at `NotificationRouteTarget` or fake route markers are not sufficient.
- Once this prerequisite lands, each blocked row must either close with exact test evidence or downgrade to a narrower row-owned product bug; none may stay blocked on generic "missing harness" wording.

### source of truth

- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `test/core/notifications/app_root_notification_open_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/integration/notification_tap_smoke_test.dart`
- `integration_test/notification_open_ui_smoke_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- Current code and tests beat stale prose when they disagree.
- `Test-Flight-Improv/test-gate-definitions.md` has no dedicated entries for these row-owned gate names as of `2026-04-10`, so the row plans and this shared prerequisite plan are the working closure contract.

### session classification

- implementation-ready

### exact problem statement

- The repo already proves `prepare -> drain -> route` ordering for startup, background, terminated, and local notification opens.
- The repo does not yet prove that the first readable 1:1 conversation frame opened through those paths already reflects the latest stored delete, edit, reaction, and reply truth.
- Existing UI smoke coverage uses a fake notification-open harness with pending and visible string lists, not the real conversation shell or a state-aware equivalent that can express deleted, edited, quoted, and reacted message states.
- `SC-008` now proves screen-level dispose/rebuild from stored truth; what remains missing is app-entry and open proof.

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
- `test/integration/notification_deeplink_integration_test.dart`
- `test/integration/notification_tap_smoke_test.dart`
- `integration_test/notification_open_ui_smoke_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`

### existing tests covering this area

- `startup_router_notification_open_test.dart` proves cold-start push recovery drains before routing for contact-request and intros opens, but it does not assert conversation UI truth.
- `chat_and_group_push_open_flow_test.dart` proves background and terminated 1:1 push opens route only after inbox preparation, but it stops before rendered conversation assertions.
- `app_root_notification_open_test.dart` proves warm remote and local notification opens prepare before route, but it only checks event order and route target kind.
- `notification_deeplink_integration_test.dart` and `notification_tap_smoke_test.dart` prove payload parsing and prepare/drain/route sequencing across entry points, not first-frame conversation truth.
- `notification_open_ui_smoke_test.dart` proves preparation changes visible fake lists inside a harness app, but it does not exercise the real conversation shell or overlay-driven state variants.
- `conversation_screen_test.dart` and `feed_screen_test.dart` already prove `SC-008` screen rebuild from stored state, which narrows the remaining gap to app-entry and route-open behavior.
- `message_deletion_roundtrip_test.dart` and `offline_inbox_roundtrip_test.dart` prove delete and inbox convergence, but not first render on startup or deep-link open.

### regression/tests to add first

- Add a state-aware notification-open UI regression harness, preferably by extending `integration_test/notification_open_ui_smoke_test.dart` or creating a sibling, so a conversation target can open with seeded deleted, edited, quoted, and reacted message state and assert the first visible frame.
- Add a terminated-open regression for pre-open delete (`DL-010`).
- Add a notification or app-shell-open regression for post-delete route entry (`DL-020`).
- Add a backgrounded-open regression for edit or delete route entry (`SC-009`).
- Add a full restart relaunch regression for stored quote, edit, delete, and reaction state (`SC-001`).
- If a lighter harness than full `ConversationWired` is used, it must still exercise the same load and read path as the actual conversation screen; do not accept a pure string-list fake as final proof.

### step-by-step implementation plan

1. Reuse the existing route entry points in `startup_router.dart` and `main.dart`; do not build new routing infrastructure.
2. Extend the notification-open UI harness or create a sibling harness that can seed persisted conversation rows and expose a first-frame assertion surface for deleted, edited, quoted, and reacted messages.
3. Add the `DL-010` cold-start regression where delete is already stored before recipient open and assert the original body never appears on the first readable frame.
4. Add the `DL-020` notification deep-link or app-shell regression through the existing app-root local or remote tap path and assert the opened conversation is already tombstoned.
5. Add the `SC-009` background-open regression where an edit or delete lands while the app is backgrounded and the route-entry frame shows latest state immediately.
6. Add the `SC-001` full relaunch regression by recreating the app with persisted stores, reopening the conversation through startup or app shell, and asserting quote, edit, delete, and reaction state before post-open settling.
7. Run the targeted notification-open and conversation screen suites.
8. Only if a new regression fails, patch the smallest relevant seam: preparation timing, conversation-open sequencing, or load or materialization logic.
9. Retighten the four row plans and update the matrix, inventory, and breakdown with exact evidence.

### risks and edge cases

- A first-frame plaintext flash that disappears only after later listener delivery.
- Different behavior between warm remote tap, terminated remote open, warm local tap, and terminated local launch.
- `main.dart` conversation routing opens `ConversationWired` after contact lookup, while group routing already carries `initialHighlightedMessageId`; do not accidentally broaden the 1:1 fix into group-navigation redesign.
- Missing contact or invalid payload should keep current fallback behavior.
- `SC-008`-style rebuild tests can hide startup bugs if the new regressions assert only eventual settle rather than the first meaningful frame.

### exact tests and gates to run

- `flutter test --no-pub test/core/notifications/app_root_notification_open_test.dart`
- `flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `flutter test --no-pub test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `flutter test --no-pub test/integration/notification_deeplink_integration_test.dart`
- `flutter test --no-pub test/integration/notification_tap_smoke_test.dart`
- `flutter test --no-pub integration_test/notification_open_ui_smoke_test.dart`
- `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test --no-pub test/features/feed/presentation/screens/feed_screen_test.dart`
- Row-owned closure labels: `startup_delete_before_render`, `deep_link_latest_state`, `durable_state_rebuild`, `stream_convergence`, `delete_wins_conflict_resolution`, `schema_overlay_state_migration`

### known-failure interpretation

- If sequencing tests keep passing but the new first-frame regression fails, treat that as the real blocker and do not mark the row covered.
- If only the old fake harness passes, do not accept it as proof for these four blocked rows.
- Ignore unrelated pre-existing failures outside notification-open and direct-thread conversation seams, but record them if they block the new regression.

### done criteria

- There is at least one exact repo-local test proving each blocked journey or the shared harness necessary to prove it.
- The four blocked row plans no longer cite a generic missing harness; they point to concrete regressions or a narrower product bug.
- The matrix and breakdown can reference exact file-and-test evidence instead of prerequisite-only notes.

### scope guard

- Do not redesign notification payload shapes, P2P transport semantics, or group and post navigation unless a new regression proves the existing path cannot express the row.
- Do not broaden into OS push banner or body correctness; these rows are about in-app render.
- Do not accept eventual state after extra pumps if the row contract is about first meaningful render.

### accepted differences / intentionally out of scope

- Group message notification highlighting already carries `messageId` and is not the target of this unblock plan.
- Feed host parity after restart is already covered by `SC-008`; this plan only revisits feed if a shared direct-thread load path is needed to close one of the blocked rows.

### dependency impact

- `DL-010`, `DL-020`, `SC-001`, and `SC-009` depend on this prerequisite plan landing or being disproven by stronger existing evidence.
- If the new harness proves the rows without product changes, the next pass should reclassify them as `stale/already-covered` or `implementation-ready` and run them normally.
- If the harness exposes product bugs, later implementation sessions should change only the smallest failing startup or deep-link seam.

### recommended execution skills

- `flutter-test-orchestrator` for the new startup, deep-link, and relaunch regressions.
- `mobile-notification-routing-and-deep-linking` if conversation-open preparation or route sequencing needs product changes.
- `mobile-network-resilience-qa` to validate user-visible cold-start, background-open, and relaunch behavior after the regressions land.

## Structural blockers remaining

- None at the planning level. The remaining blocker is implementation of the shared state-aware first-render test harness and regressions described above.

## Incremental details intentionally deferred

- Whether the final proof lives in `integration_test/notification_open_ui_smoke_test.dart` or a new sibling file can be decided during implementation.
- Formal gate-definition entries can be added later if this area becomes a recurring release gate.

## Accepted differences intentionally left unchanged

- The breakdown remains strict row-owned decomposition; this shared plan is a prerequisite artifact, not a new execution session.
- Existing sequencing tests remain valuable and should not be rewritten unless they conflict with the new first-frame coverage.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-010-plan.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-020-plan.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-001-plan.md`
- `Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-009-plan.md`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `integration_test/notification_open_ui_smoke_test.dart`
- `test/core/notifications/app_root_notification_open_test.dart`
- `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/integration/notification_tap_smoke_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`

## Why the plan is safe or unsafe to implement now

- Safe to implement now because code evidence shows real notification-open preparation and routing seams already exist in `main.dart`, `startup_router.dart`, and `prepare_notification_route_target_use_case.dart`. The plan adds the smallest missing proof surface first and only allows product changes if those proofs fail.
