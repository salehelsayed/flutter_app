# INTEGRATE-IR-001 Minimal Integration Contract

## Status

accepted

## Historical Source Of Truth

- Worktree row plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-001-plan.md`
- Source row: `IR-001 Offline active member receives missed messages on reconnect`
- Source closure verdict: accepted, with required iOS 26.2 3-party proof run `1778618344630`

## Integration Scope

Import only missing row-owned IR-001 evidence artifacts into the current main checkout:

- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- this integration breakdown ledger

The current fake-network selector `temporary partition replays missed backlog in cursor order and resumes live delivery after heal` is equivalent or stronger than the source IR-001 host fake-network selector, so that source test is skipped as already present rather than duplicated.

## Verification Contract

- Run focused IR-001 criteria tests.
- Verify the runner lists `ir001`.
- Run focused adjacent fake-network preservation for the already-present row behavior.
- Run scoped analyzer/format/diff hygiene.
- Attempt the required IR-001 iOS 26.2 live proof with available iOS 26.2 simulators. If the external fixture is unavailable or the live proof fails outside a repo-owned import issue, record `blocked_external_fixture` rather than overclaiming acceptance.

## Final Execution Verdict

Accepted on 2026-05-19. Imported only missing row-owned IR-001 criteria, runner, and live-harness artifacts; production code stayed untouched. The source fake-network selector was skipped as already present because current main's `temporary partition replays missed backlog in cursor order and resumes live delivery after heal` proves equivalent or stronger active-member backlog replay and post-heal live delivery.

Verification passed:

- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'IR-001'` (`+4`)
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios --scenario ir001` (`ir001`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'temporary partition replays missed backlog in cursor order and resumes live delivery after heal'` (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'all scenario list includes device-backed GE and GM coverage|scenario requirements map GM roles to device counts'` (`+2`)
- `flutter analyze --no-pub integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` (`No issues found!`)
- iOS 26.2 `ir001` live proof run `1779156694294`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ir001_kXLN8r`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, verdict `ir001 proof passed: ir001 verdicts valid for alice, bob, charlie`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+209 -3` only on preserved `BB-007`, `BB-012`, and `GM-029`
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`)
