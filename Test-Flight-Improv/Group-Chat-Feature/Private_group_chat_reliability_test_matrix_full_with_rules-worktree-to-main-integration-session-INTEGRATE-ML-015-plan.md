# INTEGRATE-ML-015 Integration Contract

Status: accepted

## Scope

Import and verify only source row `ML-015` into current main: membership event timeline order matches structural membership state across Alice, Bob, and Charlie after Alice adds, removes, and re-adds Charlie with messages around each interval.

This is standard integration mode. The historical source worktree remains the source of truth; this plan is only the minimal import/reconcile/verify contract for current main. Do not update the integration breakdown ledger from this row executor.

## Source Evidence

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Source plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-015-plan.md`
- Historical accepted source proof: focused ML-015 fake-network selector passed, `private_timeline_truth` criteria tests passed, group gate/completeness/diff passed, and live proof run `1778545892822` passed.
- Historical live temp artifact path from the source docs is no longer usable because its temp artifact directory is now empty.

## Import Contract

- Fake-network selector: add only `ML-015 shuffled membership timeline matches structural intervals` to `test/features/groups/integration/group_membership_smoke_test.dart`.
- Criteria: add `private_timeline_truth`, proof field `ml015TimelineTruthProof`, expected proof messages, and row-owned rejection coverage only.
- Runner: add `private_timeline_truth` to scenario parsing, listing, and usage.
- Harness: add `private_timeline_truth` roles Alice/Bob/Charlie, map the flow to `gm015`, dispatch to `_runMl015Alice`, `_runMl015Bob`, `_runMl015Charlie`, and emit `ml015TimelineTruthProof`.
- Production listener: inspect-only unless focused ML-015 tests prove a current production gap. Current target already has `_shouldIgnoreStaleMembershipEvent`, `_membershipAddAdvancesLocalMember`, and `_membershipAddTimelineExists` in `lib/features/groups/application/group_message_listener.dart`.

## Device Reality

Historical source iOS 26.2 device IDs are unavailable in this checkout. Current Flutter-visible iOS 26.2 candidates supplied by the controller:

- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`

If live proof runs, use only those IDs and the source relay profile through
`MKNOON_RELAY_ADDRESSES`.

## Verification Log

- PASS: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-015'` (`+1`).
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_timeline_truth'` (`+5`).
- PASS: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_timeline_truth --list-scenarios` printed `private_timeline_truth`.
- PASS: `dart analyze lib/features/groups/application/group_message_listener.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart` (`No issues found!`).
- PASS: `git diff --check -- test/features/groups/integration/group_membership_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart`.
- PASS: controller rerun `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-015'` (`+1`).
- PASS: controller rerun `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_timeline_truth'` (`+5`).
- PASS: controller rerun `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_timeline_truth --list-scenarios` printed `private_timeline_truth`.
- PASS: controller rerun `dart analyze lib/features/groups/application/group_message_listener.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart` (`No issues found!`).
- PASS: controller rerun `git diff --check -- test/features/groups/integration/group_membership_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-ML-015-plan.md`.
- PASS: live iOS 26.2 `private_timeline_truth` proof run `1779095800387` using Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_timeline_truth_o661Jl`; orchestrator detail `private_timeline_truth verdicts valid for alice, bob, charlie`.
- PASS: preservation reruns for listener duplicate/stale selectors (`+4`), membership smoke GM-012/GM-014/GM-034 selectors (`+3`), criteria preservation for GM-012/GM-014/GM-034/GE-004/GE-008/private re-add scenarios/concurrent admin edits (`+44`), plus isolated GE-019 (`+1`) and ML-004 (`+1`) after gate triage.
- GATE RESIDUAL: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red outside ML-015. Rerun evidence shows `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails in isolation with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:678`, and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails in isolation with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:7798`.
- GATE RESIDUAL: `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Final Integration Verdict

`accepted` for `INTEGRATE-ML-015`.

The row-owned code/test/harness delta is present in main, the production
listener delta was skipped as already present, focused host and criteria tests
passed, preservation selectors passed, and fresh iOS 26.2 live proof run
`1779095800387` passed. The remaining red gates are explicitly classified as
non-ML-015 residuals: prior accepted `BB-007`, known `GM-029`, and the existing
completeness classification gap for `fake_group_pubsub_network_test.dart`.
