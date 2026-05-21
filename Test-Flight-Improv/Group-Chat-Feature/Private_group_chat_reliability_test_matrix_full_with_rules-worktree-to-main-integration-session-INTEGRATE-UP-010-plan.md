# INTEGRATE-UP-010 Worktree-to-Main Integration Contract

Status: blocked_external_fixture

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-010-plan.md`
- Source row: `UP-010` / Opening from notification routes to correct current group state
- Row-owned source anchors:
  - `lib/features/push/application/prepare_notification_route_target_use_case.dart`: notification route preparation drains the group offline inbox with the local peer id when available.
  - `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`: group route resolution only opens an existing group when the local peer is currently a member; pending invites remain safe route targets; drain then re-resolve covers re-add recovery.
  - `lib/main.dart` and `lib/features/identity/presentation/startup_router.dart`: notification route preparation and startup routing pass the current identity peer id into the route prep/resolution use cases.
  - `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`: direct route-target tests for active member, stale removed member, re-add drain recovery, and pending invite fallback.
  - `test/integration/notification_deeplink_integration_test.dart`: notification deep-link integration proof for routing only after current local membership is resolved.
  - `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`: `up010NotificationRouteProof` on `private_timeline_truth`.

Imported delta:
- Added optional local peer id propagation to group notification route preparation and route resolution.
- Added current-local-membership checks before returning an existing group from notification resolution, while preserving pending invite routing and drain/re-resolve behavior for re-add recovery.
- Wired current identity peer id through `main.dart` and `StartupRouter` notification route paths.
- Added the row-owned route-target application tests, notification deep-link integration test, live-harness proof fields, and criteria validation/rejection tests.

Out of scope:
- No original source worktree plan recreation or rerun.
- No unrelated source-worktree changes, source-doc rewrites, COMPLETE_1 doc updates, Android, physical iOS, notification dedupe, mute behavior, foreground display, unread counts, sender labels, media/reaction routing, post notifications, contact-request routes, removed-member notification privacy, share targets, adjacent UP rows, or shared fixture repair.

Verification evidence:
- `dart format --set-exit-if-changed lib/features/push/application/prepare_notification_route_target_use_case.dart lib/features/push/application/resolve_group_notification_route_target_use_case.dart lib/main.dart lib/features/identity/presentation/startup_router.dart test/features/push/application/resolve_group_notification_route_target_use_case_test.dart test/integration/notification_deeplink_integration_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass with 0 changed.
- `flutter test --no-pub test/features/push/application/resolve_group_notification_route_target_use_case_test.dart --plain-name "UP-010"` - pass.
- `flutter test --no-pub test/integration/notification_deeplink_integration_test.dart --plain-name "UP-010"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "UP-010"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_timeline_truth"` - pass.
- Scoped `flutter analyze --no-pub` over the nine touched Dart files - pass, `No issues found!`.
- Scoped `git diff --check` over the nine touched Dart files - pass.
- Required iOS 26.2 `private_timeline_truth` live proof failed before UP-010 verdict: run `1779327964029`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_timeline_truth_2lnqcg`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Charlie repeatedly skipped offline inbox decode with `Bad state: Missing group replay key for group f641590f-abf2-4ed5-aa33-932734bb3e64 at epoch 1`, then timed out waiting for self-removal; Bob timed out waiting for `gmp_1779327964029_rejoin_key.json`; Alice timed out waiting for `gmp_1779327964029_charlie_self_removed`; the orchestrator exited with `Bad state: charlie exited with code 1 before writing a verdict`.

Controller status:
- The row is `blocked_external_fixture`. Row-owned host, integration, criteria, format, analyzer, and diff evidence passed, but required iOS 26.2 `private_timeline_truth` live proof could not reach UP-010 verdict because the shared self-removal/rejoin fixture failed before the row-owned proof.
- Safe next action is `INTEGRATE-UP-011` after ledger sanity and dirty-state safety checks because UP-011 is muted-delivery notification suppression work that can be inspected independently, while preserving the shared `private_timeline_truth` blocker evidence.
