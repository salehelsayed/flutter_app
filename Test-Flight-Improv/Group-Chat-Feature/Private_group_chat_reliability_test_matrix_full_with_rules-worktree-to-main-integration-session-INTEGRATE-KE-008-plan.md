# INTEGRATE-KE-008 Integration Contract - Re-add Current Epoch Activation

Status: accepted

Created: 2026-05-18

## Source Row

- Source plan: `worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-008-plan.md`
- Row: `KE-008`
- Title: `Re-added member receives the current epoch before being marked active`
- Source status: `accepted` / `Covered`
- Reused live scenario: `private_readd_current`

## Integration Decision

Current main already contains the ML-007 `private_readd_current` foundation and the accepted key-epoch rows through KE-006. KE-008 is independent of the KE-007 blocker because it validates re-add activation at the current epoch, not first-message delivery before a pending higher-epoch receive repair. It is also independent of pending KE-017 higher-epoch receive repair.

This session imported only the missing KE-008 row-owned proof delta:

- A host test proving a repair-pending re-add does not create active group, member, key, or publish state before current epoch key material arrives.
- `ke008ReaddActivationProof` validation for `private_readd_current`.
- KE-008 criteria fixture fields and negative criteria tests.
- KE-008 live-harness verdict fields in the existing `private_readd_current` Alice/Bob/Charlie blocks.
- Integration ledger/doc evidence for this row only.

## Owned Files

- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Scope Guard

Do not import adjacent `private_readd_current` proof fields or tests for KE-009, KE-010, KE-011, KE-012, stale old config/invite ordering, UI compose, notification, media, key repair, KE-017, KE-007 first-post-rotation timing, or broader lifecycle work. Do not copy source matrix, source session-breakdown, or source test-inventory rewrites.

## Required Evidence

- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'KE-008'`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'`
- full `test/integration/group_multi_party_device_criteria_test.dart`
- runner discovery for `private_readd_current`
- scoped format/analyzer/diff hygiene
- preservation selector for `IJ014 repaired pending invite can retry successfully after key material refresh`
- named `groups` and `completeness-check` gates, preserving known non-KE-008 residuals
- iOS 26.2 `private_readd_current` live proof

## Final Execution Verdict

Verdict: accepted.

Imported only the missing KE-008 proof surface into current main. No production files changed. The existing `private_readd_current` scenario now proves that a re-added Charlie is not considered writable/active for post-readd traffic until current epoch key material is available and acknowledged.

Accepted files:

- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'KE-008'` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'` PASS (`+7`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` PASS (`+279`).
- `flutter analyze --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/group_multi_party_device_real_harness.dart` PASS (`No issues found!`).
- `dart format --set-exit-if-changed test/features/groups/application/accept_pending_group_invite_use_case_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/group_multi_party_device_real_harness.dart` PASS (`Formatted 4 files (0 changed)` after formatting).
- Scoped `git diff --check` PASS before and after doc closure.
- Runner discovery for `private_readd_current` PASS.
- `IJ014 repaired pending invite can retry successfully after key material refresh` preservation selector PASS (`+1`).

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+185 -2` only on preserved non-KE-008 residuals: `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`) and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`).
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).

Live proof evidence:

- iOS 26.2 runtime: `com.apple.CoreSimulator.SimRuntime.iOS-26-2`.
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- `private_readd_current` exact-relay live proof PASS with run id `1779111755687`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_GdLz6Z`, and orchestrator detail `private_readd_current verdicts valid for alice, bob, charlie`.
- Alice verdict recorded `ke008ReaddActivationProof.rowId=KE-008`, current key available before fixture, current key fixture written, Charlie current-key rejoin waited before post-readd sends, Charlie acknowledged rejoin at current epoch, and final epoch `2`.
- Bob verdict recorded Charlie re-added, Charlie post-readd received at current epoch, Bob post-readd sent at current epoch, and final epoch `2`.
- Charlie verdict recorded current epoch imported before rejoin ack, rejoin acknowledged after current key, post-readd publish accepted at epoch `2`, Alice and Bob post-readd messages received at current epoch, zero removed-window plaintext, no stale epoch after readd, and final epoch `2`.

Skipped/out-of-scope:

- No production files changed.
- KE-009+, stale old config/invite ordering, UI compose, notification, media, key repair, KE-017, KE-007 first-post-rotation timing, BB-007 repair, GM-029 repair, ML-012 external-fixture repair, source matrix, source session-breakdown, source `test-inventory.md`, and COMPLETE_1 docs stayed out of scope.

Safe next action: continue with `INTEGRATE-KE-009` with KE-007 conflict blocker, ML-012 external fixture blocker, BB-007 and GM-029 residual gate failures, and the completeness classification gap preserved.
