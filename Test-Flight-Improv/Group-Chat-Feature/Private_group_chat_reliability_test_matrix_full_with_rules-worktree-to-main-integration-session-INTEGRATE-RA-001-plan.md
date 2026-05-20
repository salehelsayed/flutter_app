# INTEGRATE-RA-001 - Already-Present Integration Contract

Status: skipped_already_present

Skipped: 2026-05-19 10:43 CEST

## Source Row Contract

Source row: `RA-001 | Canonical remove-readd path preserves delivery for all active members | P0 | Remove and Re-add Regression Suite`

Historical source plan:
`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-001-plan.md`

The source contract covers the canonical A/B/C remove and re-add path:

- A, B, and C start active in the private group.
- A sends M0 before removing C.
- A removes C.
- A sends M1 while C is removed.
- A re-adds C.
- A sends M2 after re-add.
- B sees M0, M1, and M2.
- C may retain M0, must not see M1, must see M2 after re-add, and must remain able to send and receive future messages.

The source row was accepted in its worktree with no production code changes. Its owned artifacts were host tests, device criteria, live-harness support, and documentation. Historical source live proof passed on iOS 26.2 with scenario `private_readd_current`, run id `1778631963310`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_B2wqFv`, Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, and Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`.

## Controller Classification

Classification: `skipped_already_present`.

Current main already has equivalent or stronger coverage through the accepted COMPLETE_1/current-main GM-006 and GM-007 paths plus the current IR-005 `gm007` live proof evidence. Importing the source RA-001 row marker, `ra001CanonicalReaddProof`, or duplicate host/criteria/harness scenario would duplicate already-present coverage rather than add a meaningful missing row-owned delta.

No production, unit test, widget test, integration test, criteria, harness, script, fixture, helper, or source-worktree document was imported for RA-001.

## Already-Present Evidence

- `test/features/groups/integration/group_membership_smoke_test.dart:4382` contains `GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic`. It proves removed-window exclusion, current epoch convergence, Charlie's post-readd publish acceptance, and post-readd delivery to Alice/Bob/Charlie.
- `test/features/groups/integration/group_membership_smoke_test.dart:4783` contains `IR-005 GM-007 KE-018 preserves allowed pre-removal and post-readd messages while excluding removed-window messages`. It proves M0 before removal, M1-M3 during removal, and M4 after re-add; Bob receives the full active-member stream while Charlie receives only M0/M4 and zero removed-window plaintext.
- `integration_test/scripts/group_multi_party_device_criteria.dart:10566` validates `gm006ImmediateReaddProof`, including post-readd publish and receive continuity plus zero removed-window plaintext for the removed member.
- `integration_test/scripts/group_multi_party_device_criteria.dart:11579` validates `gm007HistoryBoundaryProof`, including pre-removal visibility, removed-window exclusion, post-readd visibility, remaining-member delivery continuity, and final epoch convergence.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md:2149` records accepted GM-006 iOS 26.2 proof run `1778421144199` on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md:2150` records accepted GM-007 iOS 26.2 proof run `1778422910998` on the same devices, with verdict dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm007_Yp12M1`.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md:253` records current worktree-to-main IR-005 acceptance on the current integrated checkout with iOS 26.2 `gm007` proof run `1779161721700`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, and shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm007_zTSoIb`.

## Verification

Controller verification against current main passed:

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic'` -> PASS (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'IR-005 GM-007 KE-018 preserves allowed pre-removal and post-readd messages while excluding removed-window messages'` -> PASS (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-006'` -> PASS (`+5`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-007'` -> PASS (`+8`)
- `flutter analyze --no-pub test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` -> PASS (`No issues found!`)

No fresh iOS 26.2 simulator proof was required for RA-001 integration because the row is skipped as already present and exact current/equivalent GM-006, GM-007, and IR-005 iOS 26.2 proof evidence is already recorded.

## Scope Guard

No RA-001 code, tests, criteria, live harness, fixture, helper, or script deltas were imported. The source RA-001 row marker and proof shape were intentionally not duplicated in main because GM-006, GM-007, and IR-005 already cover the same or stronger behavior.

Rows RA-002 and later remain pending and were not inspected for execution or modified by this skip contract.

## Residuals

No RA-001 residual remains. Existing non-RA-001 residuals are preserved unchanged, including `BB-007`, `BB-012`, `GM-029`, sampled retained-history drain follow-up behavior, sampled `ML-008`, sampled COMPLETE_1 `GI-017`, replay-window residuals, listener/drain residuals, and completeness classification residuals. `KE-007` and `KE-009` remain recorded as `blocked_conflict` until explicitly re-reconciled.
