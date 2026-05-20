# INTEGRATE-ML-020 Integration Contract

Status: accepted

## Scope

Import and verify only source row `ML-020` into current main: group creator/admin role changes must not make private delivery creator-bound or admin-only. Active private-group delivery must remain membership-bound after Bob is promoted to admin, Alice is demoted while still active, Charlie is removed, Charlie is re-added, and all active members send again.

This is standard integration mode. The historical source worktree remains the source of truth; this plan is only the minimal import/reconcile/verify contract for current main. Do not update or recreate the original worktree implementation plan.

## Source Evidence

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Source plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-020-plan.md`
- Historical accepted source proof: source focused ML-020 selector passed `+5`, `private_admin_role_transfer_delivery` criteria selector passed `+3`, scoped analyze/format/diff hygiene passed, and source live iOS 26.2 proof run `1778869162972` passed for Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, and Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`.

## Import Contract

- Preserve current production role/delivery semantics where already equivalent; no ML-020 production code import was needed because send recipients are already active-membership based rather than creator/admin based.
- Import row-owned ML-020 unit and fake-network assertions for admin transfer, Alice demotion, Charlie remove/re-add, removed-window exclusion, post-readd delivery, and role/member convergence.
- Import row-owned `private_admin_role_transfer_delivery` criteria, runner selection, and live harness proof plumbing only.
- Preserve existing main/COMPLETE_1 overlap rows as preservation evidence; do not import adjacent ML-012 concurrent-admin conflict work, UP-009 re-add identity work, key-rotation rows, media, notification, reaction, relay-chaos, BB-007 repair, GM-029 repair, or ML-012 external-fixture repair.

## Device Reality

Current iOS 26.2 devices used by the controller:

- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`

Live proof used only those IDs and the source relay profile through `MKNOON_RELAY_ADDRESSES`.

## Verification Log

- PASS: `flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart --plain-name "ML-020"` (`+5`).
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_admin_role_transfer_delivery"` (`+3`).
- PASS: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios --scenario private_admin_role_transfer_delivery`.
- PASS: affected main-row preservation selector using corrected `--name` regex for `member_role_updated`, demoted-creator rejection, `RP005`, `GM-015`, `GM-025`, and `GE-016` (`+26`). The earlier `--plain-name` pipe expression selected no tests and exited `79`; it was treated as an invocation error and corrected.
- PASS: full `test/integration/group_multi_party_device_criteria_test.dart` (`+270`).
- PASS: `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/application/update_group_member_role_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart`.
- PASS: `dart format --set-exit-if-changed` on the six touched ML-020 Dart files (`0 changed`).
- PASS: scoped `git diff --check` on the six touched ML-020 Dart files.
- PASS: live iOS 26.2 `private_admin_role_transfer_delivery` proof run `1779104683961` using Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_admin_role_transfer_delivery_6myeSQ`; orchestrator detail `private_admin_role_transfer_delivery verdicts valid for alice, bob, charlie`.
- LIVE PROOF DETAIL: Alice, Bob, and Charlie role verdicts recorded `rowId=ML-020`, `scenario=private_admin_role_transfer_delivery`, `appPeerPlatform=ios_26_2_core_simulator`, `roleChangeProofSource=app_peer_core_simulator`, `bobPromotedToAdmin=true`, `aliceDemotedButActive=true`, `charlieRemovedBeforeReadd=true`, `charlieReaddedAfterRemoval=true`, `removedWindowDeliveryExcludedCharlie=true`, `postReaddDeliveryToAllActiveMembers=true`, `roleStateConverged=true`, `memberStateConverged=true`, `finalKeyConverged=true`, `creatorRequiredForDelivery=false`, `adminOnlyDelivery=false`, `charlieReceivedRemovedWindow=false`, `removedWindowPlaintextCount=0`, `finalEpoch=1`, and final roles Alice writer, Bob admin, Charlie writer.
- GATE RESIDUAL: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red only on residual `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`) and residual `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144` in the diagnostic JSON run).
- GATE RESIDUAL: `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Final Integration Verdict

`accepted` for `INTEGRATE-ML-020`.

The row-owned ML-020 unit, fake-network, criteria, runner, and live harness proof are present in main. Focused selectors, affected preservation selectors, full criteria regression, scoped analyzer/format/diff hygiene, and fresh iOS 26.2 live proof all passed. The remaining red gates are classified as non-ML-020 residuals: prior `BB-007`, known `GM-029`, and the existing completeness classification gap for `fake_group_pubsub_network_test.dart`.
