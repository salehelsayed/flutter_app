# Session 10 Plan: Journey-matrix closure refresh and accepted-difference audit

## Real scope

- Refresh the Report `50` matrix docs against the accepted Session `1`
  through `9` landings recorded in
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`.
- Update the audit, TODO, and manual journey docs so they stop claiming
  already-closed gaps and stop carrying the stale Feed-expanded-card
  notification-open assumption.
- Record the accepted current notification-open contract:
  message notifications open the directly targeted conversation after inbox
  preparation; group notifications open the group; intro notifications open
  Orbit intros.
- Refresh `Test-Flight-Improv/00-INDEX.md` so Report `50` has a durable
  closure/controller entry.
- Leave `19`, `20`, and `21` untouched unless the final doc refresh exposes a
  real maintenance-guidance change rather than just stronger direct evidence.

## Closure bar

Session 10 is good enough when:

- `50-two-simulator-user-journey-tests-coverage-audit.md` reflects the
  accepted Session `1` through `9` evidence instead of the pre-rollout state,
- `50-two-simulator-user-journey-tests-todo.md` stops acting like an active
  implementation backlog and clearly separates closed work, accepted
  differences, and residual stronger-evidence-only asks,
- `50-two-simulator-user-journey-tests.md` uses the current notification-open
  product contract instead of the stale Feed-expanded-card contract,
- `00-INDEX.md` points readers at the Report `50` breakdown as the durable
  controller, and
- the final validation union for the accepted sessions is green.

## Source of truth

- Active controller doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`
- Proposal/source doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- Coverage matrix:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- Manual journey doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests.md`
- Folder closure index:
  `Test-Flight-Improv/00-INDEX.md`
- Notification-open contract evidence:
  `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  `test/core/notifications/app_root_notification_open_test.dart`
  `test/integration/notification_tap_smoke_test.dart`

When the old docs disagree with current repo evidence, current repo evidence
wins.

## Session classification

`closure-only`

## Exact problem statement

The implementation sessions are accepted, but the docs are still contradictory:

- the audit still marks multiple Session `1` through `9` rows as missing,
- the TODO still treats already-landed work as open P0/P1/P2 backlog, and
- the manual journey doc still says message notification taps open Feed with an
  expanded stack card even though the current app-root contract routes to the
  directly targeted conversation/group/intros surface instead.

The goal is to close the documentation layer without inventing new product
work and without reopening stable closure references unless the maintenance bar
actually changed.

## Files to update

- `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- `Test-Flight-Improv/50-two-simulator-user-journey-tests.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`

## Step-by-step implementation plan

1. Re-read the Session `1` through `9` closure notes in the breakdown ledger.
2. Patch the coverage audit rows touched by Sessions `1` through `9` and
   refresh the high-level read so it matches current evidence.
3. Rewrite the TODO doc into a closure/residual-watchlist artifact instead of a
   stale active backlog.
4. Patch the manual journey doc sections that still assume Feed-expanded-card
   notification opens.
5. Refresh `00-INDEX.md` so Report `50` is discoverable from the folder index.
6. Re-run the final validation union.
7. Record the accepted Session `10` outcome in the breakdown ledger.

## Validation contract

Required final direct suites:

```bash
flutter test --no-pub test/features/contact_request/integration/contact_request_flow_test.dart
flutter test --no-pub test/features/contact_request/integration/key_exchange_retry_flow_test.dart
flutter test --no-pub test/integration/onboarding_golden_path_test.dart
flutter test --no-pub test/integration/contact_request_notification_dedupe_integration_test.dart
flutter test --no-pub test/features/conversation/integration/two_user_message_exchange_test.dart
flutter test --no-pub test/features/conversation/presentation/widgets/letter_card_test.dart
flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart
flutter test --no-pub test/features/feed/integration/feed_card_flow_test.dart
flutter test --no-pub test/features/feed/domain/utils/group_messages_into_threads_test.dart
flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart
flutter test --no-pub test/features/conversation/integration/media_attachment_flow_test.dart
flutter test --no-pub test/features/conversation/integration/media_retry_smoke_test.dart
flutter test --no-pub test/shared/widgets/media/full_screen_image_viewer_test.dart
flutter test --no-pub test/shared/widgets/media/media_grid_test.dart
flutter test --no-pub test/features/conversation/application/chat_message_listener_test.dart
flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test --no-pub test/features/contacts/application/delete_contact_use_case_test.dart test/features/contacts/application/block_contact_use_case_test.dart test/features/contacts/application/unblock_contact_use_case_test.dart
flutter test --no-pub test/features/conversation/integration/offline_inbox_roundtrip_test.dart
flutter test --no-pub test/features/groups/application/send_group_reaction_use_case_test.dart test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart test/features/groups/integration/announcement_happy_path_test.dart test/features/groups/integration/group_edge_cases_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_reaction_roundtrip_test.dart test/features/groups/presentation/group_conversation_wired_test.dart
flutter test -d macos --no-pub integration_test/posts_phase1_fake_test.dart
flutter test -d macos --no-pub integration_test/posts_phase2_fake_test.dart
flutter test --no-pub test/features/posts/phase1/post_notification_open_flow_test.dart test/features/posts/phase2/posts_wired_comments_test.dart test/features/posts/phase2/load_posts_feed_engagement_test.dart test/features/posts/phase2/post_card_media_test.dart
flutter test --no-pub test/features/identity/application/restore_identity_use_case_test.dart
flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart
flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/core/lifecycle/background_reconnect_smoke_test.dart test/core/lifecycle/connectivity_lifecycle_test.dart test/core/resilience/network_chaos_test.dart test/core/resilience/soak_test.dart test/core/resilience/f1_wifi_relay_fallback_test.dart test/integration/rapid_lock_unlock_integration_test.dart test/features/identity/presentation/screens/startup_router_notification_open_test.dart test/features/identity/presentation/screens/startup_router_recovery_test.dart
flutter test -d macos --no-pub integration_test/background_reconnect_test.dart
flutter test -d macos --no-pub integration_test/wifi_relay_fallback_smoke_test.dart
flutter test -d macos --no-pub integration_test/transport_e2e_test.dart
flutter test --no-pub test/features/introduction/integration/introduction_multi_node_test.dart
flutter test --no-pub test/features/introduction/integration/introduction_smoke_test.dart test/features/introduction/application/introduction_listener_test.dart test/features/introduction/application/handle_incoming_introduction_test.dart test/features/introduction/application/mutual_acceptance_test.dart
flutter test --no-pub test/features/push/application/intro_notification_orbit_route_test.dart test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart test/features/feed/presentation/screens/feed_wired_test.dart
flutter test --no-pub test/features/introduction/presentation/widgets/intros_tab_extended_test.dart
```

Required named gates:

```bash
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh posts
```

Do not run `baseline`, `feed`, `transport`, or `completeness-check` unless the
Session `10` doc refresh unexpectedly changes a file that widens into those
contracts.

## Known-failure interpretation

- The combined macOS `transport` gate is still a known flaky runner because of
  `Error waiting for a debug connection`; the accepted validation path remains
  the green per-file macOS integration runs listed above.
- Flutter test invocations should stay sequential; parallel launches can trip
  Flutter startup locks and native-asset temp-file collisions.
- If the closure-doc refresh does not change maintenance-time guidance, do not
  touch stable closure references `19`, `20`, or `21`.

## Done criteria

- The Report `50` audit/todo/journey docs are internally consistent.
- `00-INDEX.md` points readers at the closed Report `50` controller docs.
- The accepted notification-open difference is recorded explicitly.
- The final validation union is green.
- The breakdown ledger records Session `10` as accepted with exact evidence.
