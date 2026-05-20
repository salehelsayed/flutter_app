# INTEGRATE-RA-014 Minimal Integration Contract

Status: accepted

## Source Row

`RA-014 | Removed member sending with old key after re-add does not poison the group | P0 | Remove and Re-add Regression Suite`

Historical source of truth:

- Source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-014-plan.md`

Do not recreate or rerun the historical implementation plan. This contract only governs importing and verifying the already-accepted RA-014 row delta into the main checkout.

## Controller Classification

RA-014 is partially present in main through adjacent GM-017/GM-018 stale-publish validator behavior, GL-009 rejoin/latest-key native validator behavior, and RA-006/KE-011 delayed-old-key-after-readd coverage. It is not `skipped_already_present` because the exact row-owned RA-014 Flutter stale-epoch-after-readd guard, direct proof, fake-network proof, row-named native selector, criteria validator/tests, live-harness verdict fields, and test-inventory row are missing from the main checkout.

Import only the missing meaningful RA-014 delta:

- re-add-aware stale old-epoch rejection in `handle_incoming_group_message_use_case.dart` for active senders with a prior removal cutoff, current `joinedAt`, and an incoming positive `keyEpoch` lower than the latest local key epoch
- direct selector proving the stale post-readd message is rejected with diagnostic and a later current-epoch message persists
- fake-network selector proving Alice/Bob reject Charlie's old-epoch post-readd publish and still receive Charlie's current-epoch publish
- row-named Go native selector for the already-present GL-009 old-key/old-signer rejection and latest-epoch delivery proof
- `private_readd_current` `ra014OldKeyPublishAfterReaddProof` live-harness and criteria support
- RA-014 criteria positive, missing-proof, and stale-acceptance rejection tests
- row-owned `test-inventory.md` entry

## Allowed Write Set

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `go-mknoon/node/pubsub_delivery_test.go`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

The controller owns this contract, the integration breakdown ledger, row ordering, final status, and final verdict. The execution worker must not edit those controller-owned files.

## Verification Contract

Focused checks:

```bash
dart analyze lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'RA-014'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-014'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-014'
(cd go-mknoon && go test ./node -run 'TestRA014' -count=1)
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios
```

Affected preservation checks:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'IR-005 GM-007 KE-018 preserves allowed pre-removal and post-readd messages while excluding removed-window messages'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-016 removed member remains unsubscribed from topic'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-017 removal installs remaining-member config without invoking stale member leave'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-017 stale member stays subscribed while A/B configs exclude them'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-018 repeated post-removal sends keep durable recipients Bob-only'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-018 remaining members keep live and inbox delivery under stale removed-member pressure'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-019 removed-window durable recipients exclude re-added member until re-add'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-024 member display state converges after Charlie remove and re-add'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'accepts valid GM-007|accepts valid GM-016|accepts valid GM-017|accepts valid GM-018|accepts valid GM-019|GM-024 accepts'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'RA-006 KE-011 delayed old key after re-add stays historical and current delivery remains on re-add epoch'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-006 KE-011 delayed old key after re-add does not downgrade Charlie'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'
```

Required live proof uses only iOS 26.2 CoreSimulator app peers and three distinct devices. The public app path cannot force an old cached-key publish; direct Flutter, fake-network, and native Go selectors must cover forced stale publish, while live proof covers current post-rejection delivery and consumes those host/native proof flags through `ra014OldKeyPublishAfterReaddProof`.

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current -d <alice>,<bob>,<charlie>
```

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Known residuals from RA-013 may remain unrelated unless the RA-014 import changes their owner surfaces: `BB-007`, `BB-012`, accepted-row `IR-018`, non-RA `IR-003`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, and the unrelated completeness classification miss for `test/shared/fakes/fake_group_pubsub_network_test.dart`.

## Scope Guard

Do not import RA-013 simultaneous multi-device policy, RA-015 `ALREADY_JOINED` refresh, RA-016 replay leakage, RA-017/RA-018 churn breadth, SV-002 removed-member old-key publish scenario, UI, notifications, media, network, relay architecture, Android, physical iOS, macOS app-peer proof, KE-007/KE-009 re-reconciliation, ML-012 fixture repair, or unrelated tests from later rows. If a file already contains equivalent or stronger main coverage, merge only the missing RA-014 assertion/helper instead of overwriting main.

## Execution Result

Accepted on 2026-05-19 in standard integration mode.

Imported only the missing row-owned RA-014 delta into the allowed write set: re-add-aware stale old-epoch rejection in `handle_incoming_group_message_use_case.dart`, direct and fake-network RA-014 selectors, row-named native Go stale-validator selector, `private_readd_current` `ra014OldKeyPublishAfterReaddProof` live-harness and criteria support, RA-014 criteria positive/missing-proof/stale-acceptance tests, and one `test-inventory.md` row.

Controller focused checks passed:

```bash
dart analyze lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'RA-014'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-014'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-014'
(cd go-mknoon && go test ./node -run 'TestRA014' -count=1)
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios
```

Affected preservation checks passed for GM-007, GM-016, GM-017 direct/fake-network, GM-018 direct/fake-network, GM-019, GM-024 direct/fake-network, the GM-007/GM-016/GM-017/GM-018/GM-019/GM-024 criteria bundle, RA-006/KE-011 direct/fake-network, and the accumulated `private_readd_current` criteria suite. The first parallel GM-007 attempt failed only on a macOS native-assets race while renaming `objective_c.dylib`; the isolated rerun passed.

iOS 26.2 live proof passed:

- Scenario: `private_readd_current`
- Run id: `1779206034235`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_lkdrvV`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Orchestrator verdict: `private_readd_current verdicts valid for alice, bob, charlie`
- Verdict evidence: all three roles recorded `ra014OldKeyPublishAfterReaddProof` with `rowId=RA-014`, `staleOldPublishRejectionCoveredByFakeNetwork=true`, `nativeOldKeyPublishRejectionCovered=true`, `livePostRejectDeliveryCovered=true`, `staleEpoch=1`, and `finalEpoch=2`; Alice/Bob rejected Charlie's old-key publish and received current-epoch post-reject traffic; Charlie's old-key publish was rejected, current publish was accepted, and Alice/Bob post-reject current-epoch traffic was received.

Named gates:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+227 -8` on preserved residuals: `BB-007`, `BB-012`, non-RA `IR-003`, accepted-row `IR-018`, `GE-017`, `GE-019`, `GE-020`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).
- `git diff --check` must be run after this ledger update.
