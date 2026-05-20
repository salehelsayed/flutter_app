# INTEGRATE-RA-016 Minimal Integration Contract

Status: accepted

## Source Row

`RA-016 | Delayed group inbox item from old removed interval is ignored after re-add | P0 | Remove and Re-add Regression Suite`

Historical source of truth:

- Source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-016-plan.md`

Do not recreate or rerun the historical implementation plan. This contract only governs importing and verifying the already-accepted RA-016 row delta into the main checkout.

## Controller Classification

RA-016 is partially present in main through current replay-window behavior: `drain_group_offline_inbox_use_case.dart` passes `selfPeerId` into incoming-message validation, replay envelopes already reject recipient-excluded records, and `handle_incoming_group_message_use_case.dart` rejects local removed-interval replay after rejoin using persisted `member_removed` cutoff and current `joinedAt`. It is not `skipped_already_present` because the row-owned RA-016 direct selector, fake-network selector, `private_readd_current` `ra016RemovedIntervalReplayProof` criteria/live-harness support, criteria tests, and test-inventory row are missing from main.

Current main's production diagnostic is intentionally not an exact source clone: same-account recipient rejection may emit `GROUP_HANDLE_INCOMING_MSG_SELF_REMOVED_WINDOW_AFTER_REJOIN`, while device/account-mapped recipient rejection emits `GROUP_HANDLE_INCOMING_MSG_LOCAL_REMOVED_INTERVAL_REPLAY_REJECTED`. Preserve this stronger main diagnostic split unless a focused RA-016 selector proves a real behavioral gap.

Import only the missing meaningful RA-016 delta:

- direct selector proving addressed pre-removal and post-readd replay persists while removed-window replay is rejected after Charlie re-add
- fake-network selector proving forced removed-interval replay is absent for Charlie after re-add while Alice/Bob/Charlie current post-readd delivery remains converged
- `private_readd_current` `ra016RemovedIntervalReplayProof` live-harness and criteria support
- RA-016 criteria positive, missing-proof, removed-window-leakage, missing host coverage, missing live current delivery, and final-epoch mismatch rejection tests
- row-owned `test-inventory.md` entry

Do not reimplement broad replay-window behavior already present in main. Do not import NW long-offline replay rows, RA-017 active-member breadth, or RA-018 alternating churn.

## Allowed Write Set

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart` only if a focused RA-016 selector exposes an implementation-owned gap; otherwise preserve current main behavior
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` only if a focused RA-016 selector exposes an implementation-owned gap; otherwise preserve current main behavior
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Read but do not edit `integration_test/scripts/run_group_multi_party_device_real.dart` unless runner discovery fails and the controller explicitly re-authorizes a script edit.

The controller owns this contract, the integration breakdown ledger, row ordering, final status, and final verdict. The execution worker must not edit those controller-owned files.

## Verification Contract

Focused checks:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'RA-016'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-016'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-016'
dart analyze lib/features/groups/application/handle_incoming_group_message_use_case.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios
```

Affected preservation checks:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GM-033|GK-023|GI-019|IR-005|KE-018'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'RA-014|RA-015|private_readd_current'
```

Required live proof uses only iOS 26.2 CoreSimulator app peers and three distinct devices. The public app path does not deterministically force an old removed-interval relay item; direct and fake-network selectors must cover the forced replay rejection, while live proof covers zero removed-window plaintext, current post-readd delivery, final active membership, and final epoch through `ra016RemovedIntervalReplayProof`.

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current -d <alice>,<bob>,<charlie>
```

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Known residuals from RA-015 may remain unrelated unless the RA-016 import changes their owner surfaces: `BB-007`, `BB-012`, non-RA `IR-003`, accepted-row `IR-018`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, and the unrelated completeness classification miss for `test/shared/fakes/fake_group_pubsub_network_test.dart`.

## Execution Result

Accepted on 2026-05-19. Production replay-window behavior and runner scenario registration were already present in main and were not modified. The integration imported only the missing RA-016 proof surfaces: the direct drain selector, fake-network selector, `private_readd_current` `ra016RemovedIntervalReplayProof` live-harness/criteria support, criteria tests, and the row-owned test-inventory entry. The direct selector was adapted to preserve current main's stronger lower-bound behavior: old pre-readd and removed-window replay remain invisible after Charlie re-add while post-readd replay persists.

Focused checks passed:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'RA-016'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-016'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-016'
dart analyze lib/features/groups/application/handle_incoming_group_message_use_case.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios
```

Affected preservation checks passed for accumulated `RA-014|RA-015|private_readd_current` criteria and isolated `IR-005 KE-018 drains only replay windows addressed to re-added member`. The broader preservation bundle `GM-033|GK-023|GI-019|IR-005|KE-018` remains red only on the pre-existing replay-window residuals `GM-033`, `GK-023`, and `GI-019`; the in-bundle `IR-005 KE-018` selector passed and was rerun green in isolation.

iOS 26.2 live proof passed:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Run id `1779209254582`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_ZCgPjJ`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Orchestrator verdict: `private_readd_current verdicts valid for alice, bob, charlie`. Alice/Bob/Charlie verdicts recorded `rowId=RA-016`, direct/fake-network removed-interval replay coverage, recipient-interval rejection, live current delivery, Alice/Bob/Charlie membership, and final epoch `2`; Charlie recorded `removedWindowPlaintextCount=0` and accepted post-readd publish.

Named gates:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+229 -8`, only on preserved residuals `BB-007`, `BB-012`, non-RA `IR-003`, accepted-row `IR-018`, `GE-017`, `GE-019`, `GE-020`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).
- `git diff --check` passed.

## Scope Guard

Do not import source matrix docs, COMPLETE_1 docs, source session breakdown docs, NW replay-window breadth, RA-017 active-member delivery breadth, RA-018 alternating churn, UI, notifications, media, network, relay architecture, Android, physical iOS, macOS app-peer role work, BB-007 repair, BB-012 fixture repair, accepted-row IR-018 fixture-aging repair, non-RA IR-003 replay-boundary repair, GE-017/GE-019/GE-020 seeded/churn repairs, GM-029 repair, ML-012 external-fixture repair, KE-007/KE-009 re-reconciliation, or unrelated tests from later rows. If a file already contains equivalent or stronger main behavior, merge only the missing RA-016 assertion/helper instead of overwriting main.
