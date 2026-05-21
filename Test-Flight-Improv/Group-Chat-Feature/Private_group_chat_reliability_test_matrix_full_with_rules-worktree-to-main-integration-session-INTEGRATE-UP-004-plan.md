# INTEGRATE-UP-004 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-004-plan.md`
- Source row: `UP-004` / Unread counts update correctly through removal and re-add
- Row-owned source anchors:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`: removed-window messages do not increase unread counts and post-readd unread clears on open
  - `test/features/groups/integration/group_membership_smoke_test.dart`: fake-network removal/re-add unread-count churn proof
  - `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`: `up004UnreadChurnProof` on `private_timeline_truth`

Imported delta:
- Production unread behavior was already present in current main, so no production code changed.
- Added the row-owned application proof that removed-window traffic is ignored for a removed recipient's unread count and that post-readd unread clears after opening the group.
- Added the row-owned fake-network proof that active recipients count removed-window traffic, removed Charlie does not count or display removed-window traffic, post-readd traffic counts for Charlie, and unread clears after open.
- Added the row-owned criteria and live-harness proof fields for `up004UnreadChurnProof` on `private_timeline_truth`, requiring Alice/Bob/Charlie proof maps, post-readd unread evidence, open-to-clear evidence, Bob active removed-window unread coverage, and Charlie removed-window unread/plaintext exclusion.

Out of scope:
- No original source worktree plan recreation or rerun.
- No UP-005 invite state, UP-006 stale banner/system-row proof, UP-007+ transaction/notification rows, source-doc, COMPLETE_1 doc, Android, physical iOS, production rewrite, or unrelated residual repair.
- The UP-002 `private_timeline_truth` live fixture blocker stayed preserved and was not repaired or hidden by this row.

Verification evidence:
- `dart format --set-exit-if-changed test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass with 0 changed after formatting.
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "UP-004"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "UP-004"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "UP-004"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_timeline_truth"` - pass.
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "rejects unknown sender when persisted removal cutoff belongs to another peer"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-024"` - pass.
- Scoped `dart analyze test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass, `No issues found!`.
- Scoped `git diff --check` over the touched UP-004 code/test/harness files - pass before doc closure.

Live proof blocker:
- Required current iOS 26.2 proof `private_timeline_truth` failed before any UP-004 proof map could be emitted.
- Current-main run `1779322181727`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_timeline_truth_OZYti4`, used Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Charlie repeatedly skipped offline inbox decode with `Bad state: Missing group replay key ... at epoch 1`, then exited with code 1 before writing a verdict. Alice timed out waiting for `gmp_1779322181727_charlie_self_removed`; Bob timed out waiting for `gmp_1779322181727_rejoin_key.json`; orchestrator exited before verdict.

Recovery evidence:
- Focused `private_timeline_truth` recovery repaired only the shared ML-015 live fixture wait: `_runMl015Charlie` now uses existing `_waitForRetainedSelfRemoval`, matching current retained-history behavior after self-removal and avoiding the stale expectation that the group row is deleted.
- Required iOS 26.2 proof run `1779393410061` passed in shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_timeline_truth_zlpp8m`, using Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Orchestrator verdict: `private_timeline_truth proof passed: private_timeline_truth verdicts valid for alice, bob, charlie`.
- Verdict files `gmp_1779393410061_alice_verdict.json`, `gmp_1779393410061_bob_verdict.json`, and `gmp_1779393410061_charlie_verdict.json` contain valid `up004UnreadChurnProof` fields proving removed-window unread exclusion, post-readd unread, open-to-clear behavior, and final member convergence.
- Focused recovery preservation passed: row-owned format union, UP-004 application selector plus unknown-sender preservation, UP-002/UP-004/UP-006/UP-011/GM-024 fake-network membership-smoke selectors, `private_timeline_truth` criteria selectors including UP-004, scoped analyzer over 19 affected files, and `git diff --check`.

Controller status:
- Host, fake-network, criteria, format, analyzer, diff, unknown-sender preservation, and GM-024 preservation evidence passed.
- The row is `accepted` after focused shared-fixture recovery and successful iOS 26.2 `private_timeline_truth` proof run `1779393410061`.
- No row scope was broadened; unrelated `info.plist` stayed unstaged and untouched.
