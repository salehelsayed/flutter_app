# 50 - Two-Simulator User Journey Coverage Gaps Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- Supporting matrix docs:
  - `Test-Flight-Improv/50-two-simulator-user-journey-tests.md`
  - `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- Decomposition date:
  `2026-04-03`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `10`
- The smallest safe split is:
  - `9` implementation-ready coverage sessions grouped by real seam and direct
    regression family
  - `1` closure-only matrix refresh session
- No separate plan is created for the TODO's Feed-targeted notification-open
  bucket because current repo evidence shows that expectation is stale against
  the live app-root routing contract.
- No infrastructure-first session is created for
  `Test-Flight-Improv/51-e2e-test-infrastructure-plan.md` because the proposed
  command-executor/orchestrator stack is not present in the repo and the live
  coverage work can be decomposed safely around the current deterministic
  direct suites instead.

## Overall closure bar

`50-two-simulator-user-journey-tests-todo.md` is only closed when all of the
following are true at the same time:

- every still-valid gap cell in
  `50-two-simulator-user-journey-tests-coverage-audit.md` has direct automated
  evidence in the repo or is explicitly reclassified as already covered or
  intentionally out of scope with current-code proof
- the remaining coverage work is split by real seam rather than by the TODO's
  P0/P1/P2 headings, so no session mixes contact bootstrap, 1:1 messaging,
  groups, posts, intro routing, and transport lifecycle in one plan
- the repo does not reopen stale notification-opened Feed assumptions that the
  current app no longer uses
- the repo does not block on a speculative multi-simulator harness when the
  current deterministic integration, widget, smoke, and `integration_test/`
  suites can close the gap more safely
- the stable matrix docs for this area
  (`50-two-simulator-user-journey-tests.md`,
  `50-two-simulator-user-journey-tests-coverage-audit.md`, and the TODO doc)
  are refreshed against landed evidence, and any stable maintenance docs that
  actually changed are updated once at closure time

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- `Test-Flight-Improv/50-two-simulator-user-journey-tests.md`
- `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/32-notification-card-interactions-session-breakdown.md`
- `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
- `Test-Flight-Improv/51-e2e-test-infrastructure-plan.md`

Current repo facts that governed the split:

- The current notification-open contract routes conversation targets directly to
  conversation surfaces, not to Feed-expanded stack cards.
  `test/integration/notification_tap_smoke_test.dart` repeatedly expects
  `NotificationRouteTargetKind.conversation`, and
  `Test-Flight-Improv/32-notification-card-interactions-session-breakdown.md`
  already records the old notification-opened Feed repro as
  `stale/already-covered`.
- The repo has current simulator bootstrap helpers
  (`reset_simulators.sh`, `smoke_test_friends.sh`,
  `lib/core/debug/smoke_test_runner.dart`, and
  `integration_test/setup_device.dart`), but it does not contain the command
  executor or host orchestrator proposed in
  `Test-Flight-Improv/51-e2e-test-infrastructure-plan.md`.
- The older generic `Test-Flight-Improv/session-51-plan.md` is not a live
  prerequisite for intro deferred-response handling anymore. Current code
  already contains pending intro response storage and replay seams in
  `lib/main.dart`,
  `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`,
  `lib/features/introduction/application/introduction_listener.dart`,
  `lib/features/introduction/domain/models/pending_introduction_response.dart`,
  `lib/features/introduction/domain/repositories/introduction_repository.dart`,
  `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`,
  `lib/core/database/migrations/046_pending_introduction_responses.dart`, and
  the matching repo-local tests.
- The coverage audit already distinguishes true zero-coverage or partial-coverage
  gaps from rows that are only missing one more direct integration proof.
  This matters for `10.6`, `11.1`, `11.3`, `11.4`, `16.3`, `17.2`, and `17.3`,
  where the TODO is asking for stronger direct evidence, not necessarily a
  missing product contract.
- The current named-gate source of truth keeps introduction, contact-request,
  and notification-routing suites mostly in direct optional/manual buckets
  rather than frozen named gates. The split therefore has to follow direct
  suite families, not invent new named gates.

Source-of-truth conflicts that materially affected decomposition:

- The TODO's first P0 item assumes `2.1`, `6.5`, `7.1`-`7.10`, and `8.6`
  should prove Feed-targeted notification opens. Current code, tests, and the
  existing Report `32` / Report `41` closure docs show the live product path is
  conversation/group/intros routing instead. That bucket stays out of the
  session set and is treated as a closure-time matrix refresh item.
- The unlanded command-executor architecture in
  `51-e2e-test-infrastructure-plan.md` is useful historical thinking, but
  current repo evidence does not justify making it a prerequisite for the
  remaining coverage gaps.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Initial status | Current status | Final execution verdict | Blocker class | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Contact bootstrap and request replay journey coverage` | `implementation-ready` | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-1-plan.md` | none | `pending` | `accepted` | `accepted` | none | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md` | Accepted on `2026-04-03` after bounded local plan, execution, and closure fallback. Landed direct coverage in `test/features/contact_request/integration/contact_request_flow_test.dart` for decline-then-rescan acceptance, mutual-scan race, and offline inbox replay. Direct proofs passed in `flutter test test/features/contact_request/integration/contact_request_flow_test.dart`, `flutter test test/features/contact_request/integration/key_exchange_retry_flow_test.dart`, `flutter test test/integration/onboarding_golden_path_test.dart`, and `flutter test test/integration/contact_request_notification_dedupe_integration_test.dart`. No named gate rerun was required because the landing stayed inside Session `1` direct suites and did not widen into shared startup or app-root wiring. |
| `2` | `1:1 text, active-conversation, and multi-thread journey coverage` | `implementation-ready` | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-2-plan.md` | none | `pending` | `accepted` | `accepted` | none | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md` | Accepted on `2026-04-03` after bounded local execution and closure fallback. Landed direct coverage in `test/features/conversation/integration/two_user_message_exchange_test.dart`, `test/features/conversation/presentation/screens/conversation_wired_test.dart`, and `test/features/conversation/presentation/widgets/letter_card_test.dart`, while current repo evidence in `test/features/feed/presentation/screens/feed_wired_test.dart` and `test/features/feed/domain/utils/group_messages_into_threads_test.dart` closed the remaining thread-isolation asks without feed production changes. Direct proofs passed in `flutter test --no-pub test/features/conversation/integration/two_user_message_exchange_test.dart test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name ""`, `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart`, `flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart`, `flutter test --no-pub test/features/feed/integration/feed_card_flow_test.dart`, `flutter test --no-pub test/features/feed/domain/utils/group_messages_into_threads_test.dart`, and `./scripts/run_test_gates.sh 1to1`. |
| `3` | `1:1 media viewer and large-upload journey coverage` | `implementation-ready` | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-3-plan.md` | none | `pending` | `accepted` | `accepted` | none | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md` | Accepted on `2026-04-03` after bounded local plan, execution, and closure fallback. Landed a narrow conversation-surface viewer injection seam in `lib/features/conversation/presentation/screens/conversation_screen.dart`, added direct viewer/index proofs in `test/features/conversation/presentation/screens/conversation_screen_test.dart`, and added large-video delivery metadata proof in `test/features/conversation/integration/media_attachment_flow_test.dart`. Current repo evidence in `test/features/conversation/presentation/screens/conversation_wired_test.dart` and `test/features/conversation/integration/media_retry_smoke_test.dart` already covered honest upload-progress and retry behavior, so no wider media-transport changes were required. Direct proofs passed in `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/conversation/integration/media_attachment_flow_test.dart test/shared/widgets/media/full_screen_image_viewer_test.dart test/shared/widgets/media/media_grid_test.dart`, `flutter test --no-pub test/features/conversation/integration/media_retry_smoke_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart`, and `./scripts/run_test_gates.sh 1to1`. |
| `4` | `Contact lifecycle and relay-race journey coverage` | `implementation-ready` | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-4-plan.md` | none | `pending` | `accepted` | `accepted` | none | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md` | Accepted on `2026-04-03` after bounded local plan, execution, and closure fallback. Landed direct lifecycle coverage in `test/features/conversation/application/chat_message_listener_test.dart`, `test/features/orbit/presentation/screens/orbit_wired_test.dart`, `test/features/conversation/integration/two_user_message_exchange_test.dart`, and `test/features/contact_request/integration/contact_request_flow_test.dart`. Current repo evidence in `test/features/contacts/application/delete_contact_use_case_test.dart`, `test/features/contacts/application/block_contact_use_case_test.dart`, `test/features/contacts/application/unblock_contact_use_case_test.dart`, and `test/features/conversation/integration/offline_inbox_roundtrip_test.dart` closed the remaining cleanup and queued-delivery baseline, while the already-landed Session `2` multi-contact isolation proof in `test/features/conversation/integration/two_user_message_exchange_test.dart` honestly satisfied `14.9` without new relay production work. |
| `5` | `Group reaction non-smoke proof and leave-path revalidation` | `implementation-ready` | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-5-plan.md` | none | `pending` | `accepted` | `accepted` | none | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md` | Accepted on `2026-04-03` after bounded local plan, execution, and closure fallback. Landed a normal chat-group reaction roundtrip proof in `test/features/groups/integration/group_reaction_roundtrip_test.dart` and test-only harness support in `test/shared/fakes/fake_group_pubsub_network.dart` plus `test/shared/fakes/group_test_user.dart`, while the already-green `test/features/groups/integration/group_edge_cases_smoke_test.dart` and `test/features/groups/integration/group_membership_smoke_test.dart` honestly kept `10.6` closed without extra leave-path production work. Direct proofs passed in `flutter test --no-pub test/features/groups/application/send_group_reaction_use_case_test.dart test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart test/features/groups/integration/announcement_happy_path_test.dart test/features/groups/integration/group_edge_cases_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_reaction_roundtrip_test.dart test/features/groups/presentation/group_conversation_wired_test.dart` and `./scripts/run_test_gates.sh groups`. |
| `6` | `Posts create, media, engagement, and comment direct integration proof` | `implementation-ready` | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-6-plan.md` | none | `pending` | `accepted` | `accepted` | none | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md` | Accepted on `2026-04-03` after bounded local plan, execution, and closure fallback. Landed a consolidated cross-user posts journey in `integration_test/posts_phase2_fake_test.dart`, while current repo evidence in `integration_test/posts_phase1_fake_test.dart`, `test/features/posts/phase1/post_notification_open_flow_test.dart`, `test/features/posts/phase2/posts_wired_comments_test.dart`, `test/features/posts/phase2/load_posts_feed_engagement_test.dart`, and `test/features/posts/phase2/post_card_media_test.dart` honestly covered the remaining discovery, UI, feed-projection, and media-rendering adjuncts without production edits. Direct proofs passed in `flutter test -d macos --no-pub integration_test/posts_phase1_fake_test.dart`, `flutter test -d macos --no-pub integration_test/posts_phase2_fake_test.dart`, `flutter test --no-pub test/features/posts/phase1/post_notification_open_flow_test.dart test/features/posts/phase2/posts_wired_comments_test.dart test/features/posts/phase2/load_posts_feed_engagement_test.dart test/features/posts/phase2/post_card_media_test.dart`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh posts`. |
| `7` | `1:1 lifecycle, offline-pairing, and transport-transition journey proof` | `implementation-ready` | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-7-plan.md` | none | `pending` | `accepted` | `accepted` | none | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md` | Accepted on `2026-04-03` after bounded local plan, execution, and closure fallback. Landed direct proofs in `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`, `test/core/database/integration/full_migration_chain_test.dart`, and `test/features/identity/application/restore_identity_use_case_test.dart`, while newer current repo evidence in `test/core/resilience/f1_wifi_relay_fallback_test.dart`, `test/core/lifecycle/background_reconnect_smoke_test.dart`, `test/core/lifecycle/connectivity_lifecycle_test.dart`, `test/core/resilience/network_chaos_test.dart`, `test/integration/rapid_lock_unlock_integration_test.dart`, `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`, and `test/features/identity/presentation/screens/startup_router_recovery_test.dart` honestly closed the remaining transport and suspend rows without production edits. The combined macOS `transport` gate remained flaky with `Error waiting for a debug connection`, so validation relied on green per-file macOS integration runs instead of that chained runner. |
| `8` | `Introduction multi-node happy-path, deferred-response, and offline replay coverage` | `implementation-ready` | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-8-plan.md` | none | `pending` | `accepted` | `accepted` | none | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md` | Accepted on `2026-04-03` after bounded local plan, execution, and closure fallback. Landed intro-core harness/proof expansion in `test/shared/fakes/intro_test_user.dart` and `test/features/introduction/integration/introduction_multi_node_test.dart`, while current repo evidence in `test/features/introduction/integration/introduction_smoke_test.dart`, `test/features/introduction/application/introduction_listener_test.dart`, `test/features/introduction/application/handle_incoming_introduction_test.dart`, and `test/features/introduction/application/mutual_acceptance_test.dart` closed the adjacent deferred-response and idempotency rows without production intro changes. Direct proofs passed in `flutter test --no-pub test/features/introduction/integration/introduction_multi_node_test.dart`, `flutter test --no-pub test/features/introduction/integration/introduction_smoke_test.dart test/features/introduction/application/introduction_listener_test.dart test/features/introduction/application/handle_incoming_introduction_test.dart test/features/introduction/application/mutual_acceptance_test.dart`, and `./scripts/run_test_gates.sh 1to1`. |
| `9` | `Introduction notification, conversation surfacing, and boundary matrix coverage` | `implementation-ready` | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-9-plan.md` | `8` | `prerequisite-blocked` | `accepted` | `accepted` | none | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md` | Accepted on `2026-04-03` after bounded local plan, execution, and closure fallback. Landed direct proof additions in `test/features/introduction/application/introduction_listener_test.dart`, `test/features/conversation/presentation/screens/conversation_screen_test.dart`, `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`, and `test/core/database/integration/full_migration_chain_test.dart`, while current repo evidence in `test/features/contacts/application/delete_contact_use_case_test.dart`, `test/features/push/application/intro_notification_orbit_route_test.dart`, `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`, `test/features/orbit/presentation/screens/orbit_wired_test.dart`, and `test/features/feed/presentation/screens/feed_wired_test.dart` honestly closed the delete/route/badge rows without broader production wiring changes. Direct proofs passed in `flutter test --no-pub test/features/introduction/integration/introduction_smoke_test.dart test/features/introduction/application/introduction_listener_test.dart test/features/introduction/application/handle_incoming_introduction_test.dart test/features/introduction/application/mutual_acceptance_test.dart`, `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart`, `flutter test --no-pub test/features/push/application/intro_notification_orbit_route_test.dart test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart test/features/feed/presentation/screens/feed_wired_test.dart`, `flutter test --no-pub test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`, and `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`. |
| `10` | `Journey-matrix closure refresh and accepted-difference audit` | `closure-only` | `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-10-plan.md` | `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9` | `prerequisite-blocked` | `accepted` | `accepted` | none | `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`, `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`, `Test-Flight-Improv/50-two-simulator-user-journey-tests.md`, `Test-Flight-Improv/00-INDEX.md`, `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md` | Accepted on `2026-04-03` after bounded local execution, closure fallback, and final closure-audit refresh. Landed the authoritative matrix refresh in the Report `50` audit/TODO/journey/index docs, explicitly recorded the accepted conversation/group/intros notification-open contract, and intentionally left stable closure refs `19`, `20`, and `21` unchanged because maintenance-time guidance did not materially change. Final closure validation reran the Session `1` through `9` direct batch commands from `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-10-plan.md`, the full host-side `flutter test --no-pub test` tree, the full macOS `integration_test/` tree in isolated per-file runs, and the optional closure gates `./scripts/run_test_gates.sh baseline`, `./scripts/run_test_gates.sh feed`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport`, and `./scripts/run_test_gates.sh completeness-check`; all passed after `scripts/run_test_gates.sh` was hardened to run macOS transport suites one file at a time and to classify `605/605` test files. `flutter test -d macos --no-pub integration_test/background_reconnect_test.dart` still exited `0` with the current macOS runner reporting all cases skipped. |

## Ordered session breakdown

### Session 1

- Title:
  `Contact bootstrap and request replay journey coverage`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-1-plan.md`
- Exact scope:
  - close the direct journey gaps for `1.1`, `1.2`, `1.3`, and `1.4`
  - prove one real bootstrap path that covers request arrival, accept/decline,
    reconnect replay, and truthful Orbit/Feed surfacing without requiring
    actual camera automation
  - reuse the current simulator bootstrap/smoke pattern only as setup help; do
    not make a command-executor harness a prerequisite
- Why it is its own session:
  - this is the contact-request/bootstrap seam, not the later 1:1 messaging,
    intro, or lifecycle seam
  - it has its own direct regression family around contact request flow,
    key-exchange retry, onboarding bootstrap, and post-accept surface truth
- Likely code-entry files:
  - `lib/core/debug/smoke_test_runner.dart`
  - `lib/features/contact_request/application/send_contact_request_use_case.dart`
  - `lib/features/contact_request/application/accept_contact_request_use_case.dart`
  - `lib/features/contact_request/application/decline_contact_request_use_case.dart`
  - `lib/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart`
  - `lib/features/contact_request/application/handle_incoming_message_use_case.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
- Likely direct tests/regressions:
  - `test/features/contact_request/integration/contact_request_flow_test.dart`
  - `test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
  - `test/integration/onboarding_golden_path_test.dart`
  - `test/integration/contact_request_notification_dedupe_integration_test.dart`
- Likely named gates:
  - no frozen named gate directly owns this seam
  - run the direct contact-request and onboarding suites above
  - run `./scripts/run_test_gates.sh baseline` only if final production edits
    touch app-root startup or shared notification/bootstrap wiring
- Matrix/closure docs to update when done:
  - update this breakdown artifact's ledger only
  - final authoritative matrix refresh stays with Session `10`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure verdict:
  `accepted`
- Closure note:
  - Session `1` now has an execution-safe plan in
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-1-plan.md`
    and landed the missing direct bootstrap coverage without widening into
    shared startup or notification-routing work.
  - The accepted landing stayed test-only in
    `test/features/contact_request/integration/contact_request_flow_test.dart`
    by adding decline-then-rescan acceptance, mutual-scan race, and offline
    inbox replay proof.
  - Direct proof passed in:
    - `flutter test test/features/contact_request/integration/contact_request_flow_test.dart`
    - `flutter test test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
    - `flutter test test/integration/onboarding_golden_path_test.dart`
    - `flutter test test/integration/contact_request_notification_dedupe_integration_test.dart`
  - No closure or matrix doc beyond this breakdown artifact changed in Session
    `1`; Session `10` still owns the authoritative matrix refresh.

### Session 2

- Title:
  `1:1 text, active-conversation, and multi-thread journey coverage`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-2-plan.md`
- Exact scope:
  - close the direct journey gaps for `2.2`, `2.3`, `2.4`, `18.1`, and `18.2`
  - prove rapid bilateral exchange, long-message rendering, live receive while
    a conversation is already open, and fast switching across concurrent 1:1
    threads
  - keep this session scoped to message ordering, visibility, unread/thread
    separation, and active-conversation behavior
- Why it is its own session:
  - this is the 1:1 text/thread-state seam, which is different from media
    transfer, contact bootstrap, and transport lifecycle transitions
  - it belongs to the direct `two_user_message_exchange` plus feed/thread
    regression family and the `1to1` gate
- Likely code-entry files:
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/conversation/application/mark_conversation_read_use_case.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/feed/application/feed_projection.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/core/notifications/active_conversation_tracker.dart`
- Likely direct tests/regressions:
  - `test/features/conversation/integration/two_user_message_exchange_test.dart`
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `test/features/conversation/presentation/widgets/letter_card_test.dart`
  - `test/features/feed/integration/feed_card_flow_test.dart`
  - `test/features/feed/domain/utils/group_messages_into_threads_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh feed` only if feed-thread presentation or
    cross-thread card behavior changes
  - `./scripts/run_test_gates.sh baseline` only if shared notification or
    startup routing is touched
- Matrix/closure docs to update when done:
  - update this breakdown artifact's ledger only
  - final authoritative matrix refresh stays with Session `10`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure verdict:
  `accepted`
- Closure note:
  - Session `2` reused the execution-safe plan in
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-2-plan.md`
    and closed the missing 1:1 text/thread coverage without widening into
    media-transfer, startup-routing, or feed production edits.
  - The accepted direct-proof additions landed in
    `test/features/conversation/integration/two_user_message_exchange_test.dart`
    for rapid five-round burst ordering/delivery truth and interleaved
    multi-contact isolation, in
    `test/features/conversation/presentation/widgets/letter_card_test.dart`
    for long-message rendering, and in
    `test/features/conversation/presentation/screens/conversation_wired_test.dart`
    for live receive while the conversation stays mounted via a controllable
    `_FakeIncomingConversationListener`.
  - Current repo evidence in
    `test/features/feed/presentation/screens/feed_wired_test.dart` and
    `test/features/feed/domain/utils/group_messages_into_threads_test.dart`
    already closed the remaining `18.1` / `18.2` thread-isolation asks, so
    Session `2` did not need extra feed coverage or feed-owned production
    changes.
  - The required `1to1` gate exposed a deterministic test-harness red in
    `test/features/conversation/integration/send_then_lock_delivery_test.dart`
    after the current repo's background notification dedupe delay change. The
    accepted fix stayed test-only by giving that harness a per-run
    `RecentRemoteNotificationGate` and
    `backgroundNotificationDuplicateGuardDelay: Duration.zero`, which restored
    the gate without changing production notification behavior.
  - Direct proof passed in:
    - `flutter test --no-pub test/features/conversation/integration/two_user_message_exchange_test.dart test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name ""`
    - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart`
    - `flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart`
    - `flutter test --no-pub test/features/feed/integration/feed_card_flow_test.dart`
    - `flutter test --no-pub test/features/feed/domain/utils/group_messages_into_threads_test.dart`
    - `./scripts/run_test_gates.sh 1to1`
  - No stable closure or matrix doc beyond this breakdown artifact changed in
    Session `2`; Session `10` still owns the authoritative matrix refresh.

### Session 3

- Title:
  `1:1 media viewer and large-upload journey coverage`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-3-plan.md`
- Exact scope:
  - close the direct journey gaps for `3.2`, `3.3`, `3.4`, and `3.5`
  - prove received image/video viewer behavior, multi-attachment rendering,
    per-item open behavior, and honest large-upload progress plus eventual
    delivery/playability
  - stay on the current shared viewer/upload architecture; do not reopen stale
    media-player redesign work
- Why it is its own session:
  - media send/view/download coverage is a different seam from pure text
    threading and from contact or intro state machines
  - it uses a distinct direct test family around media flow, viewer widgets,
    upload progress, and downloaded attachment routing
- Likely code-entry files:
  - `lib/features/conversation/application/upload_media_use_case.dart`
  - `lib/features/conversation/application/download_media_use_case.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
  - `lib/shared/widgets/media/full_screen_image_viewer.dart`
  - `lib/shared/widgets/media/media_grid.dart`
- Likely direct tests/regressions:
  - `test/features/conversation/integration/media_attachment_flow_test.dart`
  - `test/features/conversation/integration/media_retry_smoke_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `test/shared/widgets/media/full_screen_image_viewer_test.dart`
  - `test/shared/widgets/media/media_grid_test.dart`
  - `integration_test/media_stable_id_smoke_test.dart` if final planning needs
    a device-backed proof for large-media delivery truth
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh transport` only if final coverage relies on
    real transport-backed integration changes rather than deterministic direct
    suites
  - `./scripts/run_test_gates.sh baseline` only if shared production paths
    outside conversation/media are touched
- Matrix/closure docs to update when done:
  - update this breakdown artifact's ledger only
  - final authoritative matrix refresh stays with Session `10`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure verdict:
  `accepted`
- Closure note:
  - Session `3` now has an execution-safe plan in
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-3-plan.md`
    and closed the remaining 1:1 media viewer / large-upload gap without
    widening into transport failover, group media, or posts media work.
  - The accepted landing added a narrow conversation-surface viewer seam in
    `lib/features/conversation/presentation/screens/conversation_screen.dart`
    by allowing the existing media tap path to build the viewer through an
    injectable `ConversationMediaViewerBuilder`, keeping the default
    `FullScreenImageViewer` behavior intact while making the real open-mapping
    seam directly testable.
  - The accepted direct-proof additions landed in
    `test/features/conversation/presentation/screens/conversation_screen_test.dart`
    for received-image open behavior and visual-only multi-attachment index
    mapping, and in
    `test/features/conversation/integration/media_attachment_flow_test.dart`
    for large-video delivery metadata persistence across send and receive.
  - Current repo evidence in
    `test/features/conversation/presentation/screens/conversation_wired_test.dart`,
    `test/features/conversation/integration/media_retry_smoke_test.dart`,
    `test/shared/widgets/media/full_screen_image_viewer_test.dart`, and
    `test/shared/widgets/media/media_grid_test.dart` already closed the
    upload-progress, retry, viewer-branch, and downloaded-grid parts of the
    Session `3` ask, so no wider production upload or transport work was
    needed.
  - Direct proof passed in:
    - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/conversation/integration/media_attachment_flow_test.dart test/shared/widgets/media/full_screen_image_viewer_test.dart test/shared/widgets/media/media_grid_test.dart`
    - `flutter test --no-pub test/features/conversation/integration/media_retry_smoke_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart`
    - `./scripts/run_test_gates.sh 1to1`
  - No stable closure or matrix doc beyond this breakdown artifact changed in
    Session `3`; Session `10` still owns the authoritative matrix refresh.

### Session 4

- Title:
  `Contact lifecycle and relay-race journey coverage`
- Session id:
  `4`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-4-plan.md`
- Exact scope:
  - close the direct journey gaps for `13.1`, `13.2`, `13.3`, `13.4`,
    `14.6`, `14.7`, and `14.9`
  - prove block/unblock, archive, delete/re-add, delete-during-flight, queued
    offline-contact acceptance, and same-relay multi-conversation races at the
    smallest safe cross-feature level
  - keep the session focused on contact lifecycle truth, not on generic
    message-ordering or transport fallback coverage that belongs elsewhere
- Why it is its own session:
  - this is a contact-lifecycle and cross-feature race seam, not pure 1:1 send
    reliability and not intro orchestration
  - the direct tests span contacts, contact-request, Orbit, and message
    listener behavior, which is a different regression family from Sessions
    `1`, `2`, and `7`
- Likely code-entry files:
  - `lib/features/contacts/application/block_contact_use_case.dart`
  - `lib/features/contacts/application/unblock_contact_use_case.dart`
  - `lib/features/contacts/application/delete_contact_use_case.dart`
  - `lib/features/orbit/application/load_orbit_data_use_case.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/contact_request/application/contact_request_listener.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
- Likely direct tests/regressions:
  - `test/features/contacts/application/delete_contact_use_case_test.dart`
  - `test/features/contacts/application/block_contact_use_case_test.dart`
  - `test/features/contacts/application/unblock_contact_use_case_test.dart`
  - `test/features/contact_request/integration/contact_request_flow_test.dart`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - one new narrow cross-feature integration covering in-flight/delete or
    same-relay dual-thread behavior
- Likely named gates:
  - direct suites first
  - `./scripts/run_test_gates.sh 1to1` when message listener or shared 1:1
    delivery code changes
  - `./scripts/run_test_gates.sh baseline` only if app-root or startup wiring
    changes
- Matrix/closure docs to update when done:
  - update this breakdown artifact's ledger only
  - final authoritative matrix refresh stays with Session `10`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure verdict:
  `accepted`
- Closure note:
  - Session `4` now has an execution-safe plan in
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-4-plan.md`
    and closed the remaining contact-lifecycle gap without widening into
    startup routing, transport redesign, or later intro-matrix work.
  - The accepted direct-proof additions landed in
    `test/features/conversation/application/chat_message_listener_test.dart`
    for blocked-then-unblocked sender recovery,
    `test/features/orbit/presentation/screens/orbit_wired_test.dart` for
    archived-contact refresh that stays out of the active list,
    `test/features/conversation/integration/two_user_message_exchange_test.dart`
    for delete-before-inbox-replay and delete-then-readd clean-slate behavior,
    and `test/features/contact_request/integration/contact_request_flow_test.dart`
    for accept-while-chat-queued offline replay.
  - Current repo evidence in
    `test/features/contacts/application/delete_contact_use_case_test.dart`,
    `test/features/contacts/application/block_contact_use_case_test.dart`,
    `test/features/contacts/application/unblock_contact_use_case_test.dart`,
    and `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
    already closed the related cleanup, block/unblock use-case, and queued
    inbox baseline asks, so Session `4` did not need production lifecycle
    changes.
  - The remaining `14.9` same-relay dual-thread ask was honestly satisfied by
    the already-landed Session `2` interleaved multi-contact isolation proof in
    `test/features/conversation/integration/two_user_message_exchange_test.dart`,
    so Session `4` did not add redundant relay-only coverage.
  - Direct proof passed in:
    - `flutter test --no-pub test/features/conversation/application/chat_message_listener_test.dart`
    - `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart`
    - `flutter test --no-pub test/features/conversation/integration/two_user_message_exchange_test.dart`
    - `flutter test --no-pub test/features/contact_request/integration/contact_request_flow_test.dart`
    - `flutter test --no-pub test/features/contacts/application/delete_contact_use_case_test.dart test/features/contacts/application/block_contact_use_case_test.dart test/features/contacts/application/unblock_contact_use_case_test.dart test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  - No stable closure or matrix doc beyond this breakdown artifact changed in
    Session `4`; Session `10` still owns the authoritative matrix refresh.

### Session 5

- Title:
  `Group reaction non-smoke proof and leave-path revalidation`
- Session id:
  `5`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-5-plan.md`
- Exact scope:
  - add direct non-smoke proof for `10.5`
  - revalidate whether `10.6` needs new work at all or whether the current
    smoke/fake-network evidence already satisfies the matrix honestly
  - avoid reopening announcement reliability or broad group transport design
- Why it is its own session:
  - group sender-trust behavior has its own closure reference and its own
    frozen named gate
  - `10.5` uses a distinct group reaction and group conversation regression
    family that does not belong in posts or 1:1 sessions
- Likely code-entry files:
  - `lib/features/groups/application/send_group_reaction_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
  - `lib/features/groups/application/leave_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/send_group_reaction_use_case_test.dart`
  - `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_edge_cases_smoke_test.dart`
  - one new non-smoke integration for normal group reaction propagation and,
    only if justified, voluntary leave-group confirmation
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` only if shared Flutter production
    files beyond group surfaces change
- Matrix/closure docs to update when done:
  - update this breakdown artifact's ledger only
  - Session `10` should refresh
    `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
    only if the landed work changes maintenance guidance rather than merely
    adding evidence
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure verdict:
  `accepted`
- Closure note:
  - Session `5` now has an execution-safe plan in
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-5-plan.md`
    and landed the missing ordinary chat-group reaction roundtrip proof
    without widening into production group transport or announcement redesign.
  - The accepted landing stayed test-only in
    `test/features/groups/integration/group_reaction_roundtrip_test.dart`,
    `test/shared/fakes/fake_group_pubsub_network.dart`, and
    `test/shared/fakes/group_test_user.dart` by adding reaction fanout to the
    existing fake group harness and proving the original sender receives the
    reaction through `GroupMessageListener.groupReactionChangeStream`.
  - Current repo evidence in
    `test/features/groups/integration/group_edge_cases_smoke_test.dart` and
    `test/features/groups/integration/group_membership_smoke_test.dart`
    already covered `10.6` honestly, so no extra leave-group test or
    production change was required.
  - Direct proof passed in:
    - `flutter test --no-pub test/features/groups/application/send_group_reaction_use_case_test.dart test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart test/features/groups/integration/announcement_happy_path_test.dart test/features/groups/integration/group_edge_cases_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_reaction_roundtrip_test.dart test/features/groups/presentation/group_conversation_wired_test.dart`
    - `./scripts/run_test_gates.sh groups`
  - No closure or matrix doc beyond this breakdown artifact changed in Session
    `5`; Session `10` still owns the authoritative matrix refresh.

### Session 6

- Title:
  `Posts create, media, engagement, and comment direct integration proof`
- Session id:
  `6`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-6-plan.md`
- Exact scope:
  - add one concise direct integration proof that honestly covers `11.1`,
    `11.2`, `11.3`, and `11.4`
  - keep `11.5` explicitly out of scope because the audit already marks the
    pass-along path as sufficiently covered
  - prefer strengthening current posts integration evidence over inventing a
    new posts-only harness
- Why it is its own session:
  - posts have their own named gate and direct listener/use-case/screen
    regression family
  - combining posts with groups or 1:1 would blur different closure bars and
    different CI trigger rules
- Likely code-entry files:
  - `lib/features/posts/application/send_post_use_case.dart`
  - `lib/features/posts/application/attach_post_media_use_case.dart`
  - `lib/features/posts/application/send_post_reaction_use_case.dart`
  - `lib/features/posts/application/send_post_comment_use_case.dart`
  - `lib/features/posts/application/post_listener.dart`
  - `lib/features/posts/application/post_reaction_listener.dart`
  - `lib/features/posts/application/post_comment_listener.dart`
  - `lib/features/posts/presentation/screens/posts_wired.dart`
- Likely direct tests/regressions:
  - `integration_test/posts_phase1_fake_test.dart`
  - `integration_test/posts_phase2_fake_test.dart`
  - `test/features/posts/phase1/post_notification_open_flow_test.dart`
  - `test/features/posts/phase2/posts_wired_comments_test.dart`
  - one new direct cross-user posts happy-path regression if the current phase
    fake tests still leave the exact create/media/heart/comment sequence split
- Likely named gates:
  - `./scripts/run_test_gates.sh posts`
  - `./scripts/run_test_gates.sh baseline` only if shared app-root or startup
    code changes
- Matrix/closure docs to update when done:
  - update this breakdown artifact's ledger only
  - final authoritative matrix refresh stays with Session `10`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure verdict:
  `accepted`
- Closure note:
  - Session `6` now has an execution-safe plan in
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-6-plan.md`
    and landed the missing consolidated create/media/heart/comment posts proof
    without widening into production posts architecture or app-root routing.
  - The accepted landing stayed test-only in
    `integration_test/posts_phase2_fake_test.dart` by adding a cross-user
    image-post journey where the receiver discovers the post, hearts it, and
    comments through offline replay while the original sender observes the
    persisted engagement state.
  - Current repo evidence in
    `integration_test/posts_phase1_fake_test.dart`,
    `test/features/posts/phase1/post_notification_open_flow_test.dart`,
    `test/features/posts/phase2/posts_wired_comments_test.dart`,
    `test/features/posts/phase2/load_posts_feed_engagement_test.dart`, and
    `test/features/posts/phase2/post_card_media_test.dart`
    already covered the remaining discovery, routing, sheet refresh,
    engagement-projection, and media-rendering adjuncts honestly, so no
    production change was required.
  - Direct proof passed in:
    - `flutter test -d macos --no-pub integration_test/posts_phase1_fake_test.dart`
    - `flutter test -d macos --no-pub integration_test/posts_phase2_fake_test.dart`
    - `flutter test --no-pub test/features/posts/phase1/post_notification_open_flow_test.dart test/features/posts/phase2/posts_wired_comments_test.dart test/features/posts/phase2/load_posts_feed_engagement_test.dart test/features/posts/phase2/post_card_media_test.dart`
    - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh posts`
  - A combined macOS invocation of phase-1 plus phase-2 integration tests
    still hit the known `Error waiting for a debug connection` handoff after
    phase `1`, so validation was recorded as separate green per-file runs
    instead of relying on that flaky combined startup path.
  - No closure or matrix doc beyond this breakdown artifact changed in Session
    `6`; Session `10` still owns the authoritative matrix refresh.

### Session 7

- Title:
  `1:1 lifecycle, offline-pairing, and transport-transition journey proof`
- Session id:
  `7`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-7-plan.md`
- Exact scope:
  - close the scenario-specific evidence gaps for `5.4`, `6.3`, `15.4`,
    `16.1`, `16.3`, `16.4`, `17.2`, and `17.3`
  - prove offline-both-sides catch-up, lifecycle suspend/recover truth, direct
    to relay fallback, network flapping, slow-path latency, migration-time
    receive behavior, and post-restore receive behavior using the current
    lifecycle/resilience/transport seams
  - do not broaden into a new transport harness program unless the current
    direct suites and `integration_test/` scripts are proven insufficient
- Why it is its own session:
  - this is the lifecycle/startup/transport seam with a different closure bar
    and different named gate contract from ordinary 1:1 text/media sessions
  - it is the only session that should routinely consider `transport`
- Likely code-entry files:
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/core/lifecycle/handle_app_paused.dart`
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/core/services/incoming_message_router.dart`
  - `lib/main.dart`
  - `lib/features/identity/presentation/startup_router.dart`
- Likely direct tests/regressions:
  - `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  - `test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - `test/core/lifecycle/background_reconnect_smoke_test.dart`
  - `test/core/lifecycle/connectivity_lifecycle_test.dart`
  - `test/core/resilience/network_chaos_test.dart`
  - `test/core/resilience/soak_test.dart`
  - `test/integration/rapid_lock_unlock_integration_test.dart`
  - `integration_test/background_reconnect_test.dart`
  - `integration_test/wifi_relay_fallback_smoke_test.dart`
  - `integration_test/transport_e2e_test.dart`
  - `test/core/database/integration/full_migration_chain_test.dart`
  - `test/features/identity/application/restore_identity_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh transport`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - direct lifecycle/resilience suites above
- Matrix/closure docs to update when done:
  - update this breakdown artifact's ledger only
  - Session `10` should refresh
    `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    only if the landed work changes maintenance guidance rather than merely
    adding one more scenario proof
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure verdict:
  `accepted`
- Closure note:
  - Session `7` now has an execution-safe plan in
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-7-plan.md`
    and landed the missing direct lifecycle/startup proofs without widening
    into transport or startup production changes.
  - The accepted landing stayed test-only in
    `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
    by adding a true both-offline then both-online catch-up proof for `6.3`.
  - The accepted landing stayed test-only in
    `test/core/database/integration/full_migration_chain_test.dart`
    by adding a post-upgrade incoming-message persistence/load proof on the
    migrated schema for `17.2`.
  - The accepted landing stayed test-only in
    `test/features/identity/application/restore_identity_use_case_test.dart`
    by adding a post-restore queued receive proof tied to the restored peer ID
    for `17.3`.
  - Current repo evidence in
    `test/core/resilience/f1_wifi_relay_fallback_test.dart`,
    `test/core/lifecycle/background_reconnect_smoke_test.dart`,
    `test/core/lifecycle/connectivity_lifecycle_test.dart`,
    `test/core/resilience/network_chaos_test.dart`,
    `test/core/resilience/soak_test.dart`,
    `test/integration/rapid_lock_unlock_integration_test.dart`,
    `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`,
    and
    `test/features/identity/presentation/screens/startup_router_recovery_test.dart`
    honestly closed `5.4`, `15.4`, `16.1`, `16.3`, and `16.4` without further
    code changes. In particular, the surviving-secure-store auto-restore path
    is not a live startup-router contract, so `15.4` stays closed against the
    actual cold-start drain and resume behavior rather than that stale
    assumption.
  - Direct proof passed in:
    - `flutter test --no-pub test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
    - `flutter test --no-pub test/features/identity/application/restore_identity_use_case_test.dart`
    - `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`
    - `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/core/lifecycle/background_reconnect_smoke_test.dart test/core/lifecycle/connectivity_lifecycle_test.dart test/core/resilience/network_chaos_test.dart test/core/resilience/soak_test.dart test/core/resilience/f1_wifi_relay_fallback_test.dart test/integration/rapid_lock_unlock_integration_test.dart test/features/identity/presentation/screens/startup_router_notification_open_test.dart test/features/identity/presentation/screens/startup_router_recovery_test.dart`
    - `./scripts/run_test_gates.sh 1to1`
    - `flutter test -d macos --no-pub integration_test/background_reconnect_test.dart`
    - `flutter test -d macos --no-pub integration_test/wifi_relay_fallback_smoke_test.dart`
    - `flutter test -d macos --no-pub integration_test/transport_e2e_test.dart`
  - A combined macOS invocation through
    `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport`
    still hit the known `Error waiting for a debug connection` handoff while
    chaining macOS integration tests, so validation was recorded as green
    per-file macOS runs instead of that flaky combined runner.
  - No closure or matrix doc beyond this breakdown artifact changed in Session
    `7`; Session `10` still owns the authoritative matrix refresh.

### Session 8

- Title:
  `Introduction multi-node happy-path, deferred-response, and offline replay coverage`
- Session id:
  `8`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-8-plan.md`
- Exact scope:
  - close the direct intro coverage gaps for `9.1`, `9.4`, `I-1.1`, `I-1.4`,
    `I-3.1`, `I-3.2`, `I-5.2`, `I-5.4`, `I-5.5`, `I-9.1`, `I-9.2`, `I-9.3`,
    `I-9.4`, `I-9.5`, and `I-11.3`
  - reuse the already-landed pending-response storage/deferred-replay path
    rather than reopening the old generic intro durability plan
  - prove one honest multi-node arc that reaches contact creation and first
    encrypted B<->C chat after intro acceptance
  - keep the scope on intro state/replay/multi-node coverage, not UI copy or
    intro badge polish
- Why it is its own session:
  - this is the intro core state-machine seam and it is large enough to merit
    its own direct application/integration test family
  - it has no frozen named gate and therefore needs a clean direct-suite plan
    boundary separate from intro UI/boundary coverage
- Likely code-entry files:
  - `lib/features/introduction/application/send_introduction_use_case.dart`
  - `lib/features/introduction/application/accept_introduction_use_case.dart`
  - `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
  - `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
  - `lib/features/introduction/application/introduction_listener.dart`
  - `lib/features/introduction/application/resolve_unknown_inbox_sender_use_case.dart`
  - `lib/main.dart` only if intro replay/bootstrap plumbing needs narrow
    production adjustment during final planning
- Likely direct tests/regressions:
  - `test/features/introduction/application/handle_incoming_introduction_test.dart`
  - `test/features/introduction/application/introduction_listener_test.dart`
  - `test/features/introduction/application/mutual_acceptance_test.dart`
  - `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/features/conversation/integration/two_user_message_exchange_test.dart`
- Likely named gates:
  - direct intro suites first
  - `./scripts/run_test_gates.sh 1to1` when first-chat proof or shared inbox
    replay touches 1:1 messaging code
  - `./scripts/run_test_gates.sh baseline` only if final planning touches
    `lib/main.dart` or shared startup routing
  - `./scripts/run_test_gates.sh transport` only if intro replay work changes
    startup/resume/inbox-drain behavior materially
- Matrix/closure docs to update when done:
  - update this breakdown artifact's ledger only
  - final authoritative matrix refresh stays with Session `10`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure verdict:
  `accepted`
- Closure note:
  - Session `8` now has an execution-safe plan in
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-8-plan.md`
    and closed the intro core multi-node replay/offline gap without widening
    into intro UI polish, Orbit route changes, or startup plumbing.
  - The accepted harness extension landed in
    `test/shared/fakes/intro_test_user.dart`, which now carries the real
    intro listener plus chat listener/message repository seam so the session
    can prove post-intro conversation state and first encrypted chat truth
    instead of only intro status transitions.
  - The accepted direct-proof additions landed in
    `test/features/introduction/integration/introduction_multi_node_test.dart`
    for offline relay intro delivery with first encrypted chat, dual deferred
    remote-accept replay, accept-notification inbox fallback/drain recovery,
    same-pair different-introducer `alreadyConnected` handling, and one
    chain/circular arc progression proof.
  - Current repo evidence in
    `test/features/introduction/integration/introduction_smoke_test.dart`,
    `test/features/introduction/application/introduction_listener_test.dart`,
    `test/features/introduction/application/handle_incoming_introduction_test.dart`,
    and `test/features/introduction/application/mutual_acceptance_test.dart`
    already closed the adjacent intro-core happy-path, deferred-response, and
    idempotency asks, so Session `8` did not need production intro changes.
  - System-message insertion/order was intentionally held for Session `9`.
    Session `8` closed the intro-core state/replay contract and first-chat
    proof without widening into conversation-surface notification/presentation
    assertions.
  - Direct proof passed in:
    - `flutter test --no-pub test/features/introduction/integration/introduction_multi_node_test.dart`
    - `flutter test --no-pub test/features/introduction/integration/introduction_smoke_test.dart test/features/introduction/application/introduction_listener_test.dart test/features/introduction/application/handle_incoming_introduction_test.dart test/features/introduction/application/mutual_acceptance_test.dart`
    - `./scripts/run_test_gates.sh 1to1`
  - No stable closure or matrix doc beyond this breakdown artifact changed in
    Session `8`; Session `10` still owns the authoritative matrix refresh.

### Session 9

- Title:
  `Introduction notification, conversation surfacing, and boundary matrix coverage`
- Session id:
  `9`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-9-plan.md`
- Exact scope:
  - close the direct intro coverage gaps for `I-6.4`, `I-6.5`, `I-7.2`,
    `I-7.3`, `I-7.6`, `I-8.3`, `I-11.7`, `I-12.2`, `I-12.3`, `I-12.4`, and
    `I-13`
  - prove mutual-accept notifications, stacked intro notifications, system
    message insertion/order in the real conversation surface, delete-after-intro
    edges, key-mismatch handling, intro-during-migration handling, weird
    username rendering, and intro flow observability
  - stay out of broader push-architecture or unread-badge redesign work
- Why it is its own session:
  - this is the intro notification/presentation/boundary seam rather than the
    intro state-machine seam from Session `8`
  - it has a different direct regression family: intro routing, Orbit/Feed
    wiring, intro-system-message insertion, migration edges, and observability
- Likely code-entry files:
  - `lib/features/introduction/application/insert_intro_system_message.dart`
  - `lib/features/introduction/application/introduction_listener.dart`
  - `lib/features/introduction/application/expire_old_introductions_use_case.dart`
  - `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
  - `lib/features/introduction/presentation/widgets/intro_system_message.dart`
  - `lib/features/introduction/presentation/widgets/intro_row.dart`
  - `lib/features/introduction/presentation/widgets/intros_tab.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/main.dart` only if final planning proves intro-open routing needs
    narrow app-root coverage changes
- Likely direct tests/regressions:
  - `test/features/push/application/intro_notification_orbit_route_test.dart`
  - `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/introduction/presentation/widgets/intro_system_message_test.dart`
  - `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`
  - `test/features/introduction/application/handle_incoming_introduction_test.dart`
  - `test/core/database/integration/full_migration_chain_test.dart` if intro
    migration-arrival proof needs explicit coverage
- Likely named gates:
  - direct intro/orbit/feed suites first
  - `./scripts/run_test_gates.sh baseline` only if app-root intro route wiring
    changes
  - `./scripts/run_test_gates.sh feed` only if feed intro surfacing changes
  - companion `./scripts/run_test_gates.sh 1to1` only if conversation system
    message insertion changes shared 1:1 surface behavior materially
- Matrix/closure docs to update when done:
  - update this breakdown artifact's ledger only
  - final authoritative matrix refresh stays with Session `10`
- Dependency on earlier sessions:
  - Session `8`, because the boundary/UI matrix should plan against the final
    intro core helpers and multi-node proof shape rather than duplicating them
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure verdict:
  `accepted`
- Closure note:
  - Session `9` now has an execution-safe plan in
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-9-plan.md`
    and closed the intro notification/boundary gap without widening into push
    architecture redesign, unread-badge redesign, or startup refactors.
  - The accepted direct-proof additions landed in
    `test/features/introduction/application/introduction_listener_test.dart`
    for successful intro flow-event emission, intro system-message insertion,
    mutual-accept local notification, stacked intro notifications, and v2
    decrypt/key-mismatch rejection,
    `test/features/conversation/presentation/screens/conversation_screen_test.dart`
    for system-message conversation-surface rendering and order,
    `lib/features/introduction/presentation/widgets/intros_tab.dart` plus
    `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`
    for blank/null username fallback to peer IDs and long-username rendering,
    and `test/core/database/integration/full_migration_chain_test.dart` for
    migrated-schema introduction and deferred-response persistence.
  - The remaining delete-path rows were honestly satisfied by already-accepted
    repo evidence rather than new Session `9` code:
    `test/features/contacts/application/delete_contact_use_case_test.dart`
    already proves intro cleanup when the deleted peer is the introducer,
    recipient, or introduced party, and
    `test/features/orbit/presentation/screens/orbit_wired_test.dart`
    already proves live intro delete confirmation/badge refresh in the Orbit
    surface.
  - Current repo evidence in
    `test/features/push/application/intro_notification_orbit_route_test.dart`,
    `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`,
    `test/features/orbit/presentation/screens/orbit_wired_test.dart`, and
    `test/features/feed/presentation/screens/feed_wired_test.dart` already
    closed the adjacent intro route, badge, late mutual-accept surfacing, and
    accepted Feed/Orbit presentation difference asks, so Session `9` did not
    need broader production wiring changes.
  - Direct proof passed in:
    - `flutter test --no-pub test/features/introduction/application/introduction_listener_test.dart`
    - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart`
    - `flutter test --no-pub test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`
    - `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`
    - `flutter test --no-pub test/features/contacts/application/delete_contact_use_case_test.dart`
    - `flutter test --no-pub test/features/push/application/intro_notification_orbit_route_test.dart test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart test/features/feed/presentation/screens/feed_wired_test.dart`
  - No named Session `9` gate was required because the accepted landing stayed
    inside direct intro/conversation/widget/database proofs and did not change
    app-root or shared transport/runtime behavior.
  - No stable closure or matrix doc beyond this breakdown artifact changed in
    Session `9`; Session `10` still owns the authoritative matrix refresh and
    accepted-difference audit.

### Session 10

- Title:
  `Journey-matrix closure refresh and accepted-difference audit`
- Session id:
  `10`
- Session classification:
  `closure-only`
- Intended plan file:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-10-plan.md`
- Exact scope:
  - refresh the live matrix state after Sessions `1` through `9`
  - update the audit, TODO, and journey docs to record what is now directly
    covered, what remains intentionally stronger-evidence-only work, and what
    was a stale assumption
  - record the accepted difference that current notification opens are
    conversation/group/intros targeted rather than Feed-expanded-card targeted
  - refresh `00-INDEX.md` and any stable closure references only if the landed
    evidence materially changes maintenance guidance
- Why it is its own session:
  - the current proposal mixes live gaps, stronger-evidence asks, and stale
    assumptions; that needs a final closure pass instead of piecemeal doc edits
    inside every implementation session
  - this session validates the whole session set against the matrix and keeps
    the folder from accumulating contradictory prose again
- Likely code-entry files:
  - docs only
- Likely direct tests/regressions:
  - rerun the union of the touched direct suites from Sessions `1` through `9`
  - rerun the relevant frozen named gates based on landed changes:
    `baseline`, `1to1`, `feed`, `groups`, `posts`, and `transport` only when
    those gates were actually touched by the accepted sessions
  - rerun `./scripts/run_test_gates.sh completeness-check` only if any frozen
    gate definition changed
- Likely named gates:
  - union of the gates required by the accepted earlier sessions; no new gate
    ownership is created here
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
  - `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
  - `Test-Flight-Improv/50-two-simulator-user-journey-tests.md`
  - `Test-Flight-Improv/00-INDEX.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    only if Sessions `2`, `3`, `4`, `7`, `8`, or `9` changed maintenance-time
    guidance
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
    only if Session `5` changed maintenance-time guidance
  - `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
    only if Session `5` materially changed announcement maintenance guidance
- Dependency on earlier sessions:
  - Sessions `1` through `9`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure verdict:
  `accepted`
- Closure note:
  - Session `10` now has an execution-safe plan in
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-10-plan.md`
    and closed the matrix-refresh layer without reopening any earlier accepted
    implementation session.
  - The authoritative Report `50` refresh landed in
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`,
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`,
    `Test-Flight-Improv/50-two-simulator-user-journey-tests.md`, and
    `Test-Flight-Improv/00-INDEX.md`, while
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`
    now records Sessions `8`, `9`, and `10` as accepted.
  - The accepted current notification-open contract is now explicit in the
    stable docs: message notifications open the targeted conversation after
    inbox preparation, group notifications open the targeted group, and intro
    notifications open Orbit intros; the old Feed-expanded-card assumption is
    recorded as stale rather than left as open product work.
  - Stable closure refs
    `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`,
    `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`,
    and
    `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
    were intentionally left unchanged because the final closure pass did not
    materially change maintenance-time guidance.
  - Final validation reran the Session `1` through `9` direct batch commands
    recorded in
    `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-10-plan.md`;
    all required batches passed, while
    `flutter test -d macos --no-pub integration_test/background_reconnect_test.dart`
    exited `0` with the current macOS runner reporting all cases skipped.
  - Final closure validation then widened beyond the original doc-only Session
    `10` contract and passed:
    - `flutter test --no-pub test`
    - the full `integration_test/` tree on macOS via isolated per-file
      `flutter test -d macos --no-pub <file>` runs
  - Required named gates passed in:
    - `./scripts/run_test_gates.sh 1to1`
    - `./scripts/run_test_gates.sh groups`
    - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh posts`
  - Optional closure-time gates also passed in:
    - `./scripts/run_test_gates.sh baseline`
    - `./scripts/run_test_gates.sh feed`
    - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport`
    - `./scripts/run_test_gates.sh completeness-check`
  - The closure audit exposed a maintenance-only runner issue rather than a
    product gap: the combined macOS `transport` gate could still fail later
    suites with app-start/log-reader handoff flake even when isolated per-file
    runs were green. The accepted fix landed in `scripts/run_test_gates.sh`,
    which now runs transport-gate macOS files one at a time and classifies
    `605/605` test files during `completeness-check`.

## Why this is not fewer sessions

- Contact bootstrap (`1.x`) and contact lifecycle races (`13.x`, `14.6`,
  `14.7`, `14.9`) are different seams with different regressions. Merging them
  would mix new-contact creation, decline/replay, block/archive/delete, and
  cross-relay message races into one plan with no single closure bar.
- 1:1 text/thread-state coverage, 1:1 media coverage, and 1:1
  lifecycle/transport coverage all touch messaging, but they use different
  direct suites and different named gates. The first two sit mainly in
  `test/features/conversation/...`, while the lifecycle/transport work is the
  only slice that should routinely hit `transport`.
- Group and posts coverage cannot safely merge because
  `test-gate-definitions.md` treats them as separate named gates with separate
  maintenance contracts and because their direct suite families do not overlap
  enough to justify one shared plan.
- Intro core state-machine coverage and intro UI/boundary coverage should not
  be one session. The first is about multi-node replay, deferred responses, and
  first-chat truth; the second is about notifications, system-message
  surfacing, delete/migration edges, and observability. Combining them would
  invite a sprawling intro mega-plan.
- A closure-only doc refresh is required because this TODO already contains at
  least one stale product assumption and several rows that are "stronger direct
  evidence desired" rather than "missing product behavior."

## Why this is not more sessions

- No separate session is created for the TODO's Feed-targeted notification-open
  bucket because current repo evidence already classifies that assumption as
  stale. Splitting a stale assumption into its own implementation session would
  be bookkeeping and hallucination bait.
- No separate infrastructure-first session is created for
  `51-e2e-test-infrastructure-plan.md` because the proposed command
  executor/orchestrator is not landed and the current repo can make progress
  through existing deterministic suites.
- Session `5` intentionally keeps `10.6` as a revalidation adjunct rather than
  forcing a standalone "leave group non-smoke" plan when the audit already says
  current smoke/fake-network evidence is strong.
- Session `6` keeps posts create/media/heart/comment in one slice because they
  all belong to the same posts happy-path evidence family and the same `posts`
  gate; splitting them would create unnecessary bookkeeping.
- Sessions `8` and `9` already split the intro remainder at the smallest useful
  seam. Splitting them further into one session per intro subheading would
  create a long queue of tiny plans with overlapping helpers and no independent
  verification value.

## Regression and gate contract

- `Test-Flight-Improv/14-regression-test-strategy.md` remains the policy source
  of truth.
- `Test-Flight-Improv/test-gate-definitions.md` remains the execution source of
  truth for frozen named gates.
- Expected gate usage by session:
  - Session `1`: direct contact-request/onboarding suites; `baseline` only if
    shared app-root/bootstrap code changes
  - Session `2`: `1to1`; add `feed` only if feed-thread or feed-send behavior
    changes
  - Session `3`: `1to1`; add `transport` only if final proof really depends on
    device-backed transport integration
  - Session `4`: direct contact/Orbit suites first; add `1to1` only when shared
    message/listener code changes
  - Session `5`: `groups`
  - Session `6`: `posts`
  - Session `7`: `transport`, `1to1`, and `baseline`
  - Session `8`: direct intro suites first; add `1to1`, `baseline`, or
    `transport` only when the landed change really touches those shared seams
  - Session `9`: direct intro/orbit/feed suites first; add `baseline` or `feed`
    only if those shared seams are touched
  - Session `10`: rerun the union of only the gates touched by the accepted
    earlier sessions
- Do not create new frozen named gates for intro or contact-request coverage as
  part of this breakdown.
- Run `./scripts/run_test_gates.sh completeness-check` only if a session
  actually edits the frozen gate definitions.

## Matrix update contract

- The stable matrix set for this work already exists:
  - `Test-Flight-Improv/50-two-simulator-user-journey-tests.md`
  - `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
  - `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- Session `10` owns the authoritative refresh of those docs after all accepted
  implementation sessions land.
- Earlier sessions should update only this breakdown artifact's ledger or their
  own downstream plan/execution/closure artifacts, not the main matrix docs.
- `Test-Flight-Improv/00-INDEX.md` should be updated in Session `10` so the new
  breakdown becomes the durable controller for this area.
- Stable closure refs `19`, `20`, and `21` should only be updated in Session
  `10` if the landed work changes maintenance-time guidance, not merely because
  one more direct regression was added.

## Structural blockers remaining

- None after decomposition.
- The two major structural risks were handled during decomposition:
  - the stale Feed-targeted notification-open expectation was removed from the
    implementation session set and converted into a closure-time accepted
    difference
  - the unimplemented command-executor infrastructure plan was treated as
    historical context rather than as a prerequisite

## Accepted differences intentionally left unchanged

- Current notification-opened chat/group behavior remains direct
  conversation/group routing, not Feed-expanded-card routing. Session `10`
  should refresh the journey docs to reflect that current truth unless the user
  deliberately reopens product intent with new evidence.
- Actual camera-driven QR scanning is still not an automation prerequisite for
  Session `1`; the repo's current bootstrap pattern can prove the contact
  exchange result without inventing simulator camera control.
- The command-executor/orchestrator architecture proposed in
  `51-e2e-test-infrastructure-plan.md` remains intentionally unadopted here.
  If future work still wants it, it should start from a separate fresh doc
  rather than being smuggled into this coverage backlog.
- `10.6`, `11.1`, `11.3`, `11.4`, `16.3`, `17.2`, and `17.3` should be treated
  as "stronger direct evidence desired" rows, not as automatic proof of broken
  product behavior.

## Exact docs/files used as evidence

- `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- `Test-Flight-Improv/50-two-simulator-user-journey-tests.md`
- `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/32-notification-card-interactions-session-breakdown.md`
- `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
- `Test-Flight-Improv/51-e2e-test-infrastructure-plan.md`
- `Test-Flight-Improv/session-51-plan.md`
- `lib/main.dart`
- `lib/core/debug/smoke_test_runner.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/domain/models/pending_introduction_response.dart`
- `lib/features/introduction/domain/repositories/introduction_repository.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
- `lib/core/database/migrations/046_pending_introduction_responses.dart`
- `integration_test/setup_device.dart`
- `reset_simulators.sh`
- `smoke_test_friends.sh`
- `test/integration/notification_tap_smoke_test.dart`
- `test/features/contact_request/integration/contact_request_flow_test.dart`
- `test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
- `test/integration/onboarding_golden_path_test.dart`
- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `test/features/feed/integration/feed_card_flow_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`
- `integration_test/posts_phase1_fake_test.dart`
- `integration_test/posts_phase2_fake_test.dart`
- `integration_test/background_reconnect_test.dart`
- `integration_test/wifi_relay_fallback_smoke_test.dart`
- `integration_test/transport_e2e_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The split is anchored to current repo seams, current tests, and current gate
  ownership rather than to stale prose or missing infrastructure.
- Each implementation session ends in a meaningful verified state with a clear
  direct-suite family and a bounded named-gate contract.
- The decomposition avoids two common failure modes:
  - reopening settled notification-open behavior just because the journey doc
    still mentions Feed-expanded cards
  - forcing the whole backlog to wait for a speculative multi-simulator harness
- The closure-only session gives the backlog one authoritative place to refresh
  the matrix and record accepted differences, so the repo does not accumulate
  another layer of contradictory coverage docs.
