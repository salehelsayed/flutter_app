# INTEGRATE-SV-003 Re-Added Member Current Config/Key Publish Gate Integration Contract

Status: accepted

## Source Of Truth

- Source row: `SV-003 | Re-added member cannot publish until current key/config is installed`
- Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical row plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-003-plan.md`
- Source closure status: accepted / Covered.
- Integration mode: standard import/reconcile/verify. This contract did not regenerate the historical implementation plan and did not reimplement the row from scratch.

## Reconciliation Classification

`partial_present`: current main already had the production sender-side current membership/config/key gate in `lib/features/groups/application/send_group_message_use_case.dart`, including current-main recipient filtering and membership cutoff behavior. The integration imported only the missing row-owned proof surfaces for SV-003: Go validation, direct send use case, fake-network smoke, criteria validation, criteria tests, and live harness proof output.

## Integrated Artifacts

- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## Explicitly Unchanged

- `lib/features/groups/application/send_group_message_use_case.dart` was inspected and left unchanged because the row's production send guard was already present in main.
- Source docs, COMPLETE_1 docs, source session plans, adjacent SV rows, notification/media/share rows, Android, physical iOS, and unrelated live-fixture repairs were out of scope.

## Verification

- `gofmt -w go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/group_multi_party_device_real_harness.dart`
- `cd go-mknoon && go test ./node -run 'TestSV003PublishBlockedUntilCurrentConfigAndKeyInstalled|TestGA003RemovedMemberCannotPublishWithOldConfigKey|TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators' -count=1`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart --plain-name SV-003`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart --plain-name UP-003`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'private_readd_current|RA-014|RA-015|RA-016|KE-008'`
- `dart analyze lib/features/groups/application/send_group_message_use_case.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios`
- `git diff --check`

Required iOS 26.2 live proof passed:

- Scenario: `private_readd_current`
- Run id: `1779336387722`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_r9dt84`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Verdict: `private_readd_current proof passed: private_readd_current verdicts valid for alice, bob, charlie`
