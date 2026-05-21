# INTEGRATE-UP-011 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-011-plan.md`
- Source row: `UP-011` / Muted group suppresses notifications but not delivery
- Row-owned source anchors:
  - `test/features/groups/application/set_group_muted_use_case_test.dart`: local mute persists without changing membership.
  - `test/features/groups/application/group_message_listener_test.dart`: muted incoming group messages persist and update unread state without local notifications.
  - `test/features/groups/integration/group_membership_smoke_test.dart`: fake-network churn proof for muted delivery/unread and suppressed notifications.
  - `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`: `up011MutedDeliveryProof` on `private_timeline_truth`.

Imported delta:
- Added row-owned UP-011 mute persistence, listener, fake-network churn, criteria, and live-harness proof surfaces.
- Existing production mute behavior stayed unchanged because current main already persists `GroupModel.isMuted`, `setGroupMuted` updates it, and `GroupMessageListener` suppresses local group notifications while still persisting muted delivery.

Out of scope:
- No original source worktree plan recreation or rerun.
- No unrelated source-worktree changes, source-doc rewrites, COMPLETE_1 doc updates, Android, physical iOS, notification route selection, removed-member notification privacy, share-target filtering, media/reaction routing, sender labels, OS push permission behavior, cross-device mute sync, adjacent UP rows, or shared fixture repair.

Verification evidence:
- `dart format --set-exit-if-changed test/features/groups/application/set_group_muted_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass with 0 changed.
- `flutter test --no-pub test/features/groups/application/set_group_muted_use_case_test.dart --plain-name "UP-011"` - pass.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "UP-011"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "UP-011"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "UP-011"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_timeline_truth"` - pass.
- Scoped `flutter analyze --no-pub` over the six touched Dart files - pass, `No issues found!`.
- Scoped `git diff --check` over the six touched Dart files - pass.
- Required iOS 26.2 `private_timeline_truth` live proof failed before UP-011 verdict: run `1779329038402`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_timeline_truth_DCCOPs`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Charlie repeatedly skipped offline inbox decode with `Bad state: Missing group replay key for group cd0631ff-a811-4597-a06b-b5503fd03693 at epoch 1`, then timed out waiting for self-removal; Bob timed out waiting for `gmp_1779329038402_rejoin_key.json`; Alice timed out waiting for `gmp_1779329038402_charlie_self_removed`; the orchestrator exited with `Bad state: charlie exited with code 1 before writing a verdict`.

Recovery evidence:
- Focused `private_timeline_truth` recovery repaired only the shared ML-015 live fixture wait: `_runMl015Charlie` now uses existing `_waitForRetainedSelfRemoval`, matching current retained-history behavior after self-removal and avoiding the stale expectation that the group row is deleted.
- Required iOS 26.2 proof run `1779393410061` passed in shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_timeline_truth_zlpp8m`, using Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Orchestrator verdict: `private_timeline_truth proof passed: private_timeline_truth verdicts valid for alice, bob, charlie`.
- Bob verdict file `gmp_1779393410061_bob_verdict.json` contains valid `up011MutedDeliveryProof` fields proving muted delivery, unread update, notification suppression, final membership, and final epoch `2`.
- Focused recovery preservation passed: row-owned format union, UP-011 mute persistence selector, UP-011 listener notification selector, UP-002/UP-004/UP-006/UP-011/GM-024 fake-network membership-smoke selectors, `private_timeline_truth` criteria selectors including UP-011, scoped analyzer over 19 affected files, and `git diff --check`.

Controller status:
- The row is `accepted`. Row-owned host, integration, criteria, format, analyzer, diff, and required iOS 26.2 `private_timeline_truth` proof evidence passed after the focused shared-fixture recovery.
- No row scope was broadened; unrelated `info.plist` stayed unstaged and untouched.
