# INTEGRATE-RA-005 - Already-Present Integration Contract

Status: skipped_already_present

Skipped: 2026-05-19 12:43 CEST

## Source Row Contract

Source row: `RA-005 | Old removal event delivered after re-add is ignored as stale | P0 | Remove and Re-add Regression Suite`

Historical source plan:
`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-005-plan.md`

The source contract covers delayed stale removal after a newer re-add:

- Alice/Bob/Charlie start active in the private group.
- Charlie is removed.
- Charlie is re-added with a newer membership version.
- The older `member_removed` event is delivered after the newer re-add.
- Alice, Bob, and Charlie keep Charlie active after that stale event.
- Charlie sees zero removed-window plaintext and can continue current-epoch send/receive.

The source worktree accepted RA-005 on 2026-05-13 with no production-code ownership. Its row-owned artifacts were RA-005-labeled host selectors, `private_duplicate_remove` live-harness/criteria proof fields, criteria tests, and docs. Historical source proof passed on iOS 26.2 with scenario `private_duplicate_remove`, run id `1778636624369`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_duplicate_remove_vEDxyb`, Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, and Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`.

## Controller Classification

Classification: `skipped_already_present`.

Current main already has equivalent or stronger stale-remove-after-readd behavior and proof through accepted COMPLETE_1/current-main `GM-012`, with adjacent duplicate-remove idempotence through `GM-009` and prior worktree-to-main `ML-011` skip evidence. Importing the source `RA-005` labels, `private_duplicate_remove` selector, or `ra005DelayedOldRemovalAfterReaddProof` fields would duplicate current-main proof coverage without adding a missing meaningful row-owned behavior.

No production code, unit test, widget test, integration test, criteria, harness, runner, fixture, helper, or source-worktree document was imported for RA-005.

## Already-Present Evidence

- `lib/features/groups/application/group_message_listener.dart` routes `member_removed` through `_shouldIgnoreStaleMemberRemovedEvent`, which ignores remove events at or before the membership watermark when the current member row joined after that remove event.
- `test/features/groups/application/group_message_listener_test.dart` contains `GM-012 stale member_removed delivered after newer re-add keeps Charlie current after restart`, proving delayed stale removal after re-add preserves Charlie and current config state.
- `test/features/groups/integration/group_membership_smoke_test.dart` contains `GM-012 add then stale remove arrives out of order`, proving fake-network remove/re-add convergence, stale remove replay after re-add, Alice/Bob/Charlie current membership, and post-stale delivery.
- `integration_test/scripts/group_multi_party_device_criteria.dart` validates `gm012StaleRemoveReaddProof`, requiring stale removal ignored, Charlie in member/config state, one Charlie member row/device binding, zero removed-window plaintext on Charlie, and epoch convergence.
- `test/integration/group_multi_party_device_criteria_test.dart` has GM-012 positive and negative criteria coverage, including missing proof, stranding/config rollback, duplicate Charlie state, stale durable recipients or missing delivery, false proof fields, stale key rollback, and role mismatch.
- `integration_test/group_multi_party_device_real_harness.dart` implements the `gm012` live path by removing Charlie, re-adding Charlie, delivering the stale old remove after re-add, and proving Alice/Bob/Charlie post-stale delivery.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` marks `GM-012 | Add then stale remove arrives out of order` as `Covered`.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-ML-011-plan.md` previously classified the duplicate old remove/re-add behavior as already present through `GM-012` plus `GM-009`, intentionally not importing duplicate `private_duplicate_remove` labels or proof fields.

## Verification

Controller verification against current main passed:

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-012'` -> PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-012 add then stale remove arrives out of order'` -> PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-012'` -> PASS (`+7`).
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm012 --list-scenarios` -> PASS (`gm012`).
- `git diff --check` -> PASS after RA-005 ledger/documentation updates.
- Fresh iOS 26.2 live proof passed:
  - Command scenario: `gm012`.
  - Run id: `1779187043759`.
  - Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm012_yJoeAN`.
  - Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`.
  - Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`.
  - Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
  - Orchestrator verdict: `gm012 verdicts valid for alice, bob, charlie`.
  - Alice proof: remove v2 applied, re-add v3 applied, stale remove v2 delivered and ignored, Charlie kept in member/config state, one Charlie member row, one active Charlie device binding, Alice sent post-stale traffic, received Bob/Charlie post-stale traffic, final epoch `2`.
  - Bob proof: stale remove delivered and ignored, Charlie kept in member/config state, one Charlie member row, one active Charlie device binding, Bob sent post-stale traffic, received Alice/Charlie post-stale traffic, final epoch `2`.
  - Charlie proof: stale remove delivered and ignored, group/member state stayed current after stale remove, Charlie post-readd publish accepted, received Alice/Bob post-stale traffic, `removedWindowPlaintextCount=0`, no stale epoch after stale remove, final epoch `2`.

Initial parallel reruns of the GM-012 listener and fake-network selectors hit Flutter native-asset `lipo` startup races before test execution. Both selectors were rerun sequentially and passed.

## Scope Guard

No RA-005 code, tests, criteria, live harness, runner, fixture, helper, or source-worktree document deltas were imported. The source `RA-005` row labels, `private_duplicate_remove` route, and `ra005DelayedOldRemovalAfterReaddProof` shape were intentionally not duplicated because `GM-012` already covers the same stale-remove-after-readd contract and was freshly reverified on the current checkout.

Rows RA-006 and later remain pending and were not executed or modified by this skip contract.

## Residuals

No RA-005 residual remains. Existing non-RA-005 residuals are preserved unchanged, including `BB-007`, `BB-012`, accepted-row `IR-018` fixed-date replay fixture aging, `GM-029`, sampled retained-history drain follow-up behavior, sampled `ML-008`, sampled COMPLETE_1 `GI-017`, replay-window residuals, listener/drain residuals, and completeness classification residuals. `KE-007` and `KE-009` remain recorded as `blocked_conflict` until explicitly re-reconciled.
