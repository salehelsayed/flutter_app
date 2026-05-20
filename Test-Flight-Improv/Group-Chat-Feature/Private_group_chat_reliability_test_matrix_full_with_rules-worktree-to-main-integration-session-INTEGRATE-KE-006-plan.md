# INTEGRATE-KE-006 Integration Contract - Removal Key Rotation Exclusion

Status: accepted

Created: 2026-05-18

## Source Row

- Source plan: `worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-006-plan.md`
- Row: `KE-006`
- Title: `Removal rotates key and excludes removed peer from new key distribution`
- Source status: `accepted` / `Covered`
- Reused live scenario: `private_online_remove`

## Integration Decision

Current main already contains the production removal and rotation behavior:

- `removeGroupMember` removes the target and syncs the remaining-member config.
- `rotateAndDistributeGroupKey` distributes a generated key only to current active member devices and promotes the sender key only after successful distribution.
- Existing ML-005/GM-004 coverage proves online removal convergence and post-removal delivery, but current main does not have the KE-006-named host proof or the `ke006RemovalKeyRotationProof` criteria/live verdict fields.

This session must not change production semantics. It may only import the missing KE-006 row-owned proof delta:

- KE-006-named host proof by strengthening the existing removed-member rotation test.
- `ke006RemovalKeyRotationProof` validation for `private_online_remove`.
- KE-006 criteria fixture fields and negative criteria tests.
- KE-006 live-harness verdict fields in the existing `private_online_remove` Alice/Bob/Charlie blocks.
- Integration ledger/doc evidence for this row only.

## Owned Files

- `test/features/groups/application/member_removal_integration_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Scope Guard

Do not import adjacent `private_online_remove` proof fields for KE-007, ST-006, PL-006, media, notification, UI, re-add current epoch, config/key ordering, partial distribution, first-post-rotation timing, stale lower epoch, or repair rows. Do not copy source matrix, source session-breakdown, or source test-inventory rewrites.

## Required Evidence

- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'KE-006'`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_online_remove'`
- full `test/integration/group_multi_party_device_criteria_test.dart`
- runner discovery for `private_online_remove`
- scoped format/analyzer/diff hygiene
- preservation selectors for the existing removal/rotation host proof, ML-005/GM-004 behavior, and private-online-remove criteria
- named `groups` and `completeness-check` gates, preserving known non-KE-006 residuals
- iOS 26.2 `private_online_remove` live proof if device fixtures are available

## Final Execution Verdict

Verdict: accepted.

Imported only the missing KE-006 proof surface into current main. Production removal/key-rotation semantics were already present and stayed unchanged. The existing removed-member rotation host test was strengthened and KE-006-named; `private_online_remove` criteria, criteria fixtures, negative criteria assertions, and live harness verdict fields now include `ke006RemovalKeyRotationProof`.

Accepted files:

- `test/features/groups/application/member_removal_integration_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'KE-006'` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_online_remove'` PASS (`+7`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` PASS (`+277`).
- `dart analyze test/features/groups/application/member_removal_integration_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/group_multi_party_device_real_harness.dart` PASS (`No issues found!`).
- `dart format --set-exit-if-changed ...` PASS (`Formatted 4 files (0 changed)` after initial formatting).
- Scoped `git diff --check` PASS.
- Runner discovery for `private_online_remove` PASS.
- Existing removed-member rotation selector preservation PASS (`+1`).
- Existing first-post-removal rotated-epoch selector preservation PASS (`+1`).
- ML-005 preservation selector PASS on rerun (`+1`; first attempt hit a native-asset install-name race while multiple Flutter processes were starting).
- GM-004 fake-network preservation selector PASS (`+1`).
- Group-info P2P rotated-key distribution preservation selector PASS (`+1`).
- GM-004 criteria preservation selector PASS (`+6`).

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+185 -2` only on preserved non-KE-006 residuals: `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`) and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`).
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).

Live proof evidence:

- iOS 26.2 runtime: `com.apple.CoreSimulator.SimRuntime.iOS-26-2`.
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- `private_online_remove` exact-relay live proof PASS with run id `1779110366683`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_online_remove_plW8Zn`, and orchestrator detail `private_online_remove verdicts valid for alice, bob, charlie`.

Skipped/out-of-scope:

- No production files changed.
- Adjacent `private_online_remove` proof fields for KE-007, ST-006, PL-006, media, notification, UI, re-add current epoch, config/key ordering, partial distribution, first-post-rotation timing, stale lower epoch, and repair rows were not imported.
- Source matrix, source session-breakdown, source `test-inventory.md`, COMPLETE_1 docs, BB-007 repair, GM-029 repair, and ML-012 external-fixture repair stayed out of scope.

Safe next action: continue with `INTEGRATE-KE-007` with ML-012 external fixture blocker, BB-007 and GM-029 residual gate failures, and the completeness classification gap preserved.
