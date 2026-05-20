# INTEGRATE-ML-019 Integration Contract

Status: accepted

## Scope

Import and verify only source row `ML-019` into current main: accepting a stale invite after removal must reject the old invite or preserve/upgrade to the latest re-add package, with no removed-window plaintext exposure and no key downgrade.

This is standard integration mode. The historical source worktree remains the source of truth; this plan is only the minimal import/reconcile/verify contract for current main. Do not update or recreate the original worktree implementation plan.

## Source Evidence

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Source plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-019-plan.md`
- Historical accepted source proof: source focused store/accept/invite selectors passed, `private_stale_invite_readd` criteria passed, scoped hygiene passed, and source live iOS 26.2 proof run `1778589267973` passed for Alice/Bob/Charlie.

## Import Contract

- Reconcile pending-invite storage so a delayed lower-epoch or older-freshness invite cannot replace a newer pending re-add invite for the same group.
- Reconcile pending-invite accept so a locally stale pending invite is rejected against newer local group/key/membership state before materialization.
- Import row-owned ML-019 assertions for stale delayed invite replacement, stale accept against newer local removal/key state, and latest re-add package acceptance.
- Import row-owned `private_stale_invite_readd` criteria, runner selection, and live harness proof plumbing only.
- Preserve existing main/COMPLETE_1 overlap rows as preservation evidence; do not import unrelated KE-016 or RA-004 source proof validators, broader stale-reinvite repair work, iOS project metadata, BB-007 repair, GM-029 repair, or ML-012 external-fixture repair.

## Device Reality

Current iOS 26.2 devices used by the controller:

- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`

Live proof used only those IDs and the source relay profile through `MKNOON_RELAY_ADDRESSES`.

## Verification Log

- PASS: `flutter test --no-pub test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/invite_round_trip_test.dart --plain-name 'ML-019'` (`+3`).
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_stale_invite_readd'` (`+3`).
- PASS: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios --scenario private_stale_invite_readd`.
- PASS: `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart lib/features/groups/application/handle_incoming_group_invite_use_case.dart lib/features/groups/application/accept_pending_group_invite_use_case.dart`.
- PASS: `dart format` on touched ML-019 Dart files (`0 changed` after final label cleanup).
- PASS: scoped `git diff --check` on touched ML-019 code/test/harness files.
- PASS: ML-018 preservation selectors for `store_pending_group_invite_use_case_test.dart`, `accept_pending_group_invite_use_case_test.dart`, and `invite_round_trip_test.dart` with `--plain-name 'ML-018'` (`+3`).
- PASS: ML-018 `private_invite_terminal_states` criteria selector (`+4`).
- PASS: GM-021/GE-014/GE-015 preservation selectors across `member_removal_integration_test.dart`, `group_membership_smoke_test.dart`, and `group_messaging_smoke_test.dart` (`+4`).
- PASS: full `test/integration/group_multi_party_device_criteria_test.dart` (`+267`).
- PASS: live iOS 26.2 `private_stale_invite_readd` proof run `1779103399438` using Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_stale_invite_readd_Rgg1Lj`; orchestrator detail `private_stale_invite_readd verdicts valid for alice, bob, charlie`.
- LIVE PROOF DETAIL: Alice recorded old invite sent, Charlie removed after old invite, key rotation after removal, removed-window message sent, latest invite sent, post-readd message sent, Bob and Charlie post-readd messages received, final epoch `2`, and Charlie included only in final member list. Bob recorded old add observed, removal observed before re-add, removed-window message received, final member list includes Charlie, current epoch present, Alice and Charlie post-readd messages received, Bob post-readd message sent, and final epoch `2`. Charlie recorded old invite received, latest invite received, delayed old invite rejected, pending invite remained latest before accept, latest invite accepted, stale accept rejected, no key downgrade after stale accept, Alice/Bob/Charlie final membership, Alice/Bob post-readd messages received, Charlie post-readd message sent, old invite epoch `1`, latest/accepted epoch `2`, delayed store result `invalidPayload`, stale accept result `invalidPayload`, and removed-window plaintext count `0`.
- GATE RESIDUAL: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red only on residual `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`) and residual `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:7960` in the fresh run).
- GATE RESIDUAL: `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Final Integration Verdict

`accepted` for `INTEGRATE-ML-019`.

The row-owned production stale-invite guards, focused tests, criteria, runner, and live harness proof are present in main. Focused selectors, affected preservation selectors, full criteria regression, scoped analyzer/format/diff hygiene, and fresh iOS 26.2 live proof all passed. The remaining red gates are classified as non-ML-019 residuals: prior `BB-007`, known `GM-029`, and the existing completeness classification gap for `fake_group_pubsub_network_test.dart`.
