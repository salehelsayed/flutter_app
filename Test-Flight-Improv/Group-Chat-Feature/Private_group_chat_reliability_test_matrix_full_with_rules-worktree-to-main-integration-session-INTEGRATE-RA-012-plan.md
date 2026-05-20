# INTEGRATE-RA-012 Minimal Integration Contract

Status: accepted

## Source Row

`RA-012 | Re-add same peer id with rotated device keys updates identity material | P0 | Remove and Re-add Regression Suite`

Historical source of truth:

- Source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-012-plan.md`

Do not recreate or rerun the historical implementation plan. This contract only governs importing and verifying the already-accepted RA-012 row delta into the main checkout.

## Controller Classification

RA-012 is partially present in main through adjacent GM-021/GK/GA device-material behavior, but the exact row-owned RA-012 proof artifacts are missing. This row is not `skipped_already_present`.

Import only the missing meaningful RA-012 delta:

- same-peer rotated signing/ML-KEM/key-package fixture support in `GroupTestUser`
- direct RA-012 rotated-fanout selector
- fake-network RA-012 same-peer rotated-material convergence selector
- `private_rotated_device_readd` runner/live-harness/criteria support
- RA-012 criteria positive and rejection tests
- row-owned `test-inventory.md` entry

## Allowed Write Set

- `test/shared/fakes/group_test_user.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

The controller owns this contract, the integration breakdown ledger, row ordering, final status, and final verdict. The execution worker must not edit those files.

## Verification Contract

Focused checks:

```bash
dart analyze test/shared/fakes/group_test_user.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'RA-012'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-012'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-012'
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_rotated_device_readd --list-scenarios
```

Required live proof uses only iOS 26.2 CoreSimulator app peers:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_rotated_device_readd -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Known residuals from RA-011 may remain unrelated unless the RA-012 import changes their owner surfaces: `BB-007`, `BB-012`, accepted-row `IR-018` fixture aging, non-RA `IR-003`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, and the unrelated completeness classification miss for `test/shared/fakes/fake_group_pubsub_network_test.dart`.

## Scope Guard

Do not import RA-013 simultaneous multi-device policy, sender-device revocation policy, UI, notifications, media, network, relay architecture, Android, physical iOS, macOS app-peer proof, KE-007/KE-009 re-reconciliation, ML-012 fixture repair, or unrelated tests from later rows. If a file already contains equivalent or stronger main coverage, merge only the missing RA-012 assertion/helper instead of overwriting main.

## Execution Result

RA-012 was accepted on 2026-05-19 after importing only the missing row-owned rotated-device same-peer re-add proof delta.

Imported row-owned artifacts:

- `GroupTestUser` same-peer rotated signing/ML-KEM/key-package fixture overrides while preserving current-main helper behavior.
- Direct selector `RA-012 re-added same peer uses rotated device material for future keys`.
- Fake-network selector `RA-012 rotated device keys replace old material on same-peer re-add`.
- `private_rotated_device_readd` runner, live-harness, criteria, and criteria-test support.
- RA-012 `test-inventory.md` row.

Focused verification passed:

```bash
dart analyze test/shared/fakes/group_test_user.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'RA-012'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-012'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-012'
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_rotated_device_readd --list-scenarios
```

Affected preservation checks passed:

```bash
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'targets active registered recipient devices and skips revoked devices'
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'KE-021 removed member is excluded'
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'skips members without mlKemPublicKey'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-021'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-021'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-011'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'
```

iOS 26.2 live proof passed:

- Scenario: `private_rotated_device_readd`
- Run id: `1779200721237`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_rotated_device_readd_1UZBh5`
- Alice device: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob device: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie device: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Orchestrator verdict: `private_rotated_device_readd verdicts valid for alice, bob, charlie`

Live proof facts recorded:

- Alice removed Charlie, re-added Charlie with rotated material, received Charlie post-rotated-readd traffic, used rotated member config material, did not retain old device material, and ended at epoch `2`.
- Bob observed Charlie removed/re-added with rotated material, received Alice and Charlie post-rotated-readd traffic, used rotated member config material, did not retain old device material, and ended at epoch `2`.
- Charlie imported rotated material, accepted post-rotated-readd publish, received Alice post-rotated-readd traffic, saw Alice/Bob/Charlie membership, used rotated member config material, did not retain old device material, and ended at epoch `2`.
- Rotated material ids: `ra012-rotated-mlkem-1779200721237` and `ra012-rotated-key-package-1779200721237`.

Named gates and hygiene:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+225 -8` on preserved residuals: `BB-007`, `BB-012`, accepted-row `IR-018` fixture aging, non-RA `IR-003`, `GE-017`, `GE-019`, `GE-020`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).
- `git diff --check` passed.

No source worktree docs, COMPLETE_1 docs, original worktree plans, unrelated rows, RA-013 multi-device behavior, Go code, production code, UI, notification, relay, Android, physical iOS, KE-007/KE-009 re-reconciliation, or residual gate repairs were imported.
