# INTEGRATE-UP-006 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-006-plan.md`
- Source row: `UP-006` / Re-add banner or system row never reuses stale removed state
- Row-owned source anchors:
  - `lib/features/groups/presentation/screens/group_info_wired.dart`: Group Info member rows use the latest add/join evidence instead of stale removed or pending-invite state.
  - `test/features/groups/application/group_membership_timeline_message_test.dart`: durable add/remove/re-add timeline row proof.
  - `test/features/groups/presentation/group_info_wired_test.dart`: re-added member renders joined/active, not removed or pending.
  - `test/features/groups/integration/group_membership_smoke_test.dart`: fake-network reopen proof for remove/re-add timeline and visible member state.
  - `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`: `up006ReaddUiStateProof` on `private_timeline_truth`.

Imported delta:
- Added the missing Group Info latest-add-evidence lookup for `member_joined`, `member_added`, and `members_added` timeline events, preserving current-main invite-state rendering.
- Added the row-owned direct timeline-message proof that a re-add row is the latest active event after removal.
- Added the row-owned Group Info widget proof that a re-added member renders joined/active and does not reuse stale removed or pending-invite state.
- Added the row-owned fake-network proof that reopening the group after remove/re-add shows active Charlie and ordered remove-before-readd system rows.
- Added `up006ReaddUiStateProof` live-harness emission and criteria validation for `private_timeline_truth`, including stale removed and stale pending-invite rejection checks.

Out of scope:
- No original source worktree plan recreation or rerun.
- No unrelated source-worktree changes, source-doc rewrites, COMPLETE_1 doc updates, Android, physical iOS, notification rows, share-target rows, media/reaction rows, security/privacy rows, or adjacent UP rows.
- No attempt to repair the shared `private_timeline_truth` live fixture or ML-015 self-removal/rejoin path in this row.

Verification evidence:
- `dart format lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/application/group_membership_timeline_message_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass.
- `dart format --set-exit-if-changed lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/application/group_membership_timeline_message_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass with 0 changed.
- `flutter test --no-pub test/features/groups/application/group_membership_timeline_message_test.dart --plain-name "UP-006"` - pass.
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "UP-006"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "UP-006"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "UP-006"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_timeline_truth"` - pass.
- `dart analyze lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/application/group_membership_timeline_message_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass, `No issues found!`.
- Preservation passed: UP-002 timeline selector, UP-005 Group Info selector, UP-001 Group Info selector, UP-002 fake-network selector, UP-004 fake-network selector, GM-024 fake-network selector, ML-004 combined selector bundle, and GM-036 contact-picker/group-info/fake-network selectors.
- Required iOS 26.2 `private_timeline_truth` live proof failed before UP-006 verdict: run `1779324592018`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_timeline_truth_E9x4di`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Charlie repeatedly skipped offline inbox decode with `Bad state: Missing group replay key for group c3b4a456-2438-4c72-938d-6f34759474d7 at epoch 1`, then timed out waiting for self-removal; Bob timed out waiting for `gmp_1779324592018_rejoin_key.json`; Alice timed out waiting for `gmp_1779324592018_charlie_self_removed`; the orchestrator exited with `Bad state: charlie exited with code 1 before writing a verdict`.

Recovery evidence:
- Focused `private_timeline_truth` recovery repaired only the shared ML-015 live fixture wait: `_runMl015Charlie` now uses existing `_waitForRetainedSelfRemoval`, matching current retained-history behavior after self-removal and avoiding the stale expectation that the group row is deleted.
- Required iOS 26.2 proof run `1779393410061` passed in shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_timeline_truth_zlpp8m`, using Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Orchestrator verdict: `private_timeline_truth proof passed: private_timeline_truth verdicts valid for alice, bob, charlie`.
- Verdict files `gmp_1779393410061_alice_verdict.json`, `gmp_1779393410061_bob_verdict.json`, and `gmp_1779393410061_charlie_verdict.json` contain valid `up006ReaddUiStateProof` fields proving active re-add UI state, stale removed/pending rejection, and final member convergence.
- Focused recovery preservation passed: row-owned format union, UP-002/UP-006 timeline-message selectors, UP-001/UP-005/UP-006/GM-036 Group Info selectors, UP-002/UP-004/UP-006/UP-011/GM-024 fake-network membership-smoke selectors, `private_timeline_truth` criteria selectors including UP-006, scoped analyzer over 19 affected files, and `git diff --check`.

Controller status:
- The row is `accepted`. Row-owned host, widget, fake-network, criteria, preservation, format, analyzer, diff, and required iOS 26.2 `private_timeline_truth` proof evidence passed after the focused shared-fixture recovery.
- No row scope was broadened; unrelated `info.plist` stayed unstaged and untouched.
