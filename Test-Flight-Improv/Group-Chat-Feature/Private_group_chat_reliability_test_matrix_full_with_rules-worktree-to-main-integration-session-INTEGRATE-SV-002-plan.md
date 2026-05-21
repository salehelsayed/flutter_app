# INTEGRATE-SV-002 Removed Member Old-Key Publish Rejection Integration Contract

Status: accepted

## Source Of Truth

- Source row: `SV-002` - Removed member cannot publish with old key.
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-002-plan.md`.
- Mode: standard worktree-to-main import/reconcile/verify integration. This is not gap-closure mode. The historical worktree plan and closure evidence were reused as source-of-truth and were not regenerated.

## Classification

`partial_present`

Current main already had overlapping removed-member authorization coverage through COMPLETE_1/current-main `GA-003` and `GM-017` behavior. It did not have the exact SV-002 row-owned proof shape across raw PubSub injection, listener buffering, direct timeline/unread mutation, fake-network reaction mutation, criteria validation, runner registration, and iOS 26.2 live harness evidence.

## Imported Scope

- `go-mknoon/node/pubsub_authorization_forward_test.go`
- `lib/features/groups/application/group_message_listener.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-SV-002-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## Guarded Out Of Scope

SV-008 unauthorized config update artifacts, adjacent SV rows, source worktree docs, source matrix docs, COMPLETE_1 docs, Android, physical iOS, notification/media/share rows, and unrelated live-fixture or residual repair work stayed out of scope. Existing unrelated `info.plist` changes were preserved and not staged.

## Integration Result

- Added native raw PubSub proof `TestSV002RemovedMemberOldKeyRawPubSubRejectsBeforeAcceptAndForward`.
- Added a narrow listener guard so unknown/non-member traffic with an older key epoch than the latest local group key generation bypasses membership-dependent buffering and fails closed through the existing removed-after-cutoff path.
- Added direct, listener, fake-network, criteria, runner, and live-harness SV-002 proofs for timeline/latest/unread/notification/reaction non-mutation after a removed old-key publish attempt.
- Preserved COMPLETE_1/current-main GA-003 and GM-017 overlap instead of duplicating broader removed-member coverage.

## Verification

- `gofmt -w go-mknoon/node/pubsub_authorization_forward_test.go`
- `dart format --set-exit-if-changed ...`
- `cd go-mknoon && go test ./node -run 'TestSV002RemovedMemberOldKeyRawPubSubRejectsBeforeAcceptAndForward|TestGA003RemovedMemberCannotPublishWithOldConfigKey|TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators|TestGA002NonMemberCannotPublishValidEnvelope|TestGA026ValidationRejectDiagnosticsArePrivacySafeForAllReasons' -count=1` passed.
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart --plain-name SV-002` passed with `+7`.
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_removed_old_key_publish_rejected --list-scenarios` listed `private_removed_old_key_publish_rejected`.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name SV-001` passed with `+1`.
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-017` passed with `+7`.
- `dart analyze lib/features/groups/application/group_message_listener.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` passed with `No issues found!`.
- `git diff --check` passed before live proof and must pass again before commit.

## Live Proof

Required iOS 26.2 proof passed:

```sh
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_removed_old_key_publish_rejected -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

- Run id: `1779335139616`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_removed_old_key_publish_rejected_fApKDh`
- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Verdict: `private_removed_old_key_publish_rejected proof passed: private_removed_old_key_publish_rejected verdicts valid for alice, bob, charlie`

## Closure

SV-002 is accepted. Next safe action is `INTEGRATE-SV-003` after ledger sanity, dirty-state safety check, and fresh row-specific scout revalidation.
