# INTEGRATE-UP-012 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-012-plan.md`
- Source row: `UP-012` / Removed member receives no notifications for post-removal messages
- Row-owned source anchors:
  - `test/features/groups/application/send_group_message_use_case_test.dart`: post-removal durable notification recipients exclude removed members.
  - `test/features/groups/integration/group_membership_smoke_test.dart`: fake-network removed member gets no post-removal delivery or notifications.
  - `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`: `private_removed_notification_privacy` scenario and `up012NotificationPrivacyProof`.

Imported delta:
- Added row-owned UP-012 direct recipient-targeting proof, fake-network notification privacy assertions, live-harness scenario/proof fields, runner registration, criteria validation, and criteria tests.
- Existing production recipient filtering and local listener notification gating stayed unchanged because current main already excludes removed members from durable group recipients and suppresses local notifications for non-current/absent group recipients.

Out of scope:
- No original source worktree plan recreation or rerun.
- No unrelated source-worktree changes, source-doc rewrites, COMPLETE_1 doc updates, Android, physical iOS, background push fallback redesign, notification route resolution, mute behavior, share-target filtering, unread counts, sender labels, media/reaction rows, security/privacy rows, adjacent UP rows, or shared fixture repair.

Verification evidence:
- `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass with 0 changed.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "UP-012"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "UP-012"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "UP-012"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "all scenario list includes device-backed GE and GM coverage"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_online_remove"` - pass.
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios | rg '^private_removed_notification_privacy$'` - pass.
- Scoped `flutter analyze --no-pub` over the six touched Dart files - pass, `No issues found!`.
- Scoped `git diff --check` over the six touched Dart files - pass.
- Required iOS 26.2 `private_removed_notification_privacy` live proof passed: run `1779330599692`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_removed_notification_privacy_ggTtmI`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Orchestrator verdict: `private_removed_notification_privacy proof passed: private_removed_notification_privacy verdicts valid for alice, bob, charlie`. Alice and Bob proof fields showed current member-list exclusion for Charlie plus one legitimate post-removal notification for active-member traffic; Charlie proof fields showed `groupPresentAfterRemoval=false`, `receivedAliceAfterRemoval=false`, `receivedBobAfterRemoval=false`, `postRemovalPlaintextCount=0`, `postRemovalNotificationCount=0`, `noLocalNotificationsAfterRemoval=true`, `noPostRemovalNotificationPreviews=true`, and empty notification snapshots.

Controller status:
- The row is `accepted`. Row-owned host, fake-network, criteria, runner discovery, format, analyzer, diff, and required iOS 26.2 live proof evidence passed.
- Safe next action is `INTEGRATE-UP-013` after ledger sanity, dirty-state safety checks, and fresh row-specific revalidation because UP-013 owns route/widget lifecycle event retention and is independent from the accepted UP-012 notification privacy contract.
