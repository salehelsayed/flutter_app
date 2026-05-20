# INTEGRATE-RA-017 Minimal Integration Contract

Status: accepted

## Source Row

`RA-017 | Every active member can still receive after C churn, not only C | P0 | Remove and Re-add Regression Suite`

Historical source of truth:

- Source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-017-plan.md`

Do not recreate or rerun the historical implementation plan. This contract only governs importing and verifying the already-accepted RA-017 row delta into the main checkout.

## Controller Classification

RA-017 is partially present in main through stronger broad churn coverage in adjacent accepted rows: GE-004 and GE-005 cover A/B/C post-readd and repeated churn delivery, GE-020 covers A/B/C/D fixed-seed churn with no permanent deaf active member and no entitled message loss, and GM rows cover duplicate re-add, recipient targeting, and key/window invariants. It is not `skipped_already_present` because the exact RA-017 row-owned direct key-distribution selector, durable-recipient selector, four-member fake-network selector, `private_readd_active_members` runner/live-harness/criteria support, RA-017 criteria tests, and test-inventory row are missing from the target checkout.

Import only the missing meaningful RA-017 delta:

- `RA-017` direct key-distribution selector proving repeated Charlie churn keeps key distribution targeting Bob and Dana while excluding Charlie during removed windows
- `RA-017` direct durable-recipient selector proving Alice/Bob/Dana active-recipient durable inbox targeting across three Charlie churn cycles
- `RA-017` four-member fake-network selector proving Alice/Bob/Dana continue sending and receiving while Charlie churns and Charlie receives zero removed-window plaintext
- `private_readd_active_members` runner/live-harness support and `ra017ActiveMemberChurnProof` criteria validation
- RA-017 criteria positive and rejection tests for missing/weak proof, missing Dana coverage, fewer than three cycles, removed-window leakage, final membership divergence, and final epoch divergence
- row-owned `test-inventory.md` entry

Do not import source production files. `group_key_update_listener.dart` cleanup is already present in main, and source `remove_group_member_use_case.dart` is stale against current main and must not be copied. Do not import RA-018 alternating churn, RA-013 same-user multi-device policy, GE-020 long-soak refactors, broad product UX, notification, media, schema migration, relay shared-state, Android, physical iOS, or unrelated tests.

## Allowed Write Set

- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Read but do not edit unless the controller explicitly re-authorizes after a focused RA-017 failure:

- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- Go/native files
- source matrix docs, source session breakdown docs, COMPLETE_1 docs, and this integration breakdown ledger

The controller owns this contract, the integration breakdown ledger, row ordering, final status, and final verdict. The execution worker must not edit those controller-owned files.

## Verification Contract

Focused checks:

```bash
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'RA-017'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'RA-017'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-017'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-017'
dart analyze test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_active_members --list-scenarios
```

Affected preservation checks:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --name 'GM-007|GM-016|GM-017|GM-018|GM-024|GM-025'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --name 'GM-017|GM-018|GM-019|GM-024'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-019'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/application/leave_group_use_case_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart --name 'GM-016'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'GM-007|GM-016|GM-017|GM-018|GM-019|GM-024|private_readd_current|private_readd_cycles'
```

Run Go preservation only if native/Go membership or validator files are touched:

```bash
(cd go-mknoon && go test ./node -run 'TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators|TestGM018RemainingMembersDeliverySurvivesRemovedMemberStalePressure' -count=1)
```

Required live proof uses only iOS 26.2 CoreSimulator app peers and four distinct devices for Alice, Bob, Charlie, and Dana:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_active_members -d <alice>,<bob>,<charlie>,<dana>
```

Expected verdict: `ra017ActiveMemberChurnProof`, `rowId=RA-017`, at least three churn cycles, Alice/Bob/Dana active send and receive coverage, explicit Dana coverage, Charlie removed-window plaintext count `0`, final Alice/Bob/Charlie/Dana membership convergence, and final epoch convergence.

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Known residuals from RA-016 may remain unrelated unless the RA-017 import changes their owner surfaces: `BB-007`, `BB-012`, non-RA `IR-003`, accepted-row `IR-018`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, and the unrelated completeness classification miss for `test/shared/fakes/fake_group_pubsub_network_test.dart`.

## Scope Guard

Do not broaden RA-017 into RA-018 alternating churn, GE-020 long soak repair, old blocked KE-007/KE-009 re-reconciliation, ML-012 external-fixture recovery, product UI, notification, media, relay shared-state, Android, physical iOS, or simulator-device management outside the required four-role proof. If a test file already contains equivalent or stronger coverage, merge only the missing RA-017 assertion/helper instead of overwriting current main.

## Execution Result

Accepted on 2026-05-19. The integration imported only the missing row-owned RA-017 proof artifacts: the direct key-distribution selector, the direct durable-recipient selector, the four-member fake-network selector, `private_readd_active_members` runner/live-harness/criteria support, RA-017 criteria tests, and the row-owned `test-inventory.md` entry. Production code, Go/native files, `group_key_update_listener.dart`, and `remove_group_member_use_case.dart` were not modified; `group_key_update_listener.dart` remains a pre-existing unrelated dirty file in the checkout.

Focused verification passed:

- `dart format --set-exit-if-changed ...` on touched Dart files: PASS (`Formatted 7 files (0 changed)`)
- `dart analyze ...` scoped to RA-017 touched Dart files: PASS (`No issues found!`)
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'RA-017'`: PASS (`+1`)
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'RA-017'`: PASS (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-017'`: PASS (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-017'`: PASS (`+7`)
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_active_members --list-scenarios`: PASS; scenario listed

Affected preservation passed:

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --name 'GM-007|GM-016|GM-017|GM-018|GM-024|GM-025'`: PASS (`+6`)
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --name 'GM-017|GM-018|GM-019|GM-024'`: PASS (`+4`)
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-019'`: PASS (`+1`)
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/application/leave_group_use_case_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart --name 'GM-016'`: PASS (`+3`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'GM-007|GM-016|GM-017|GM-018|GM-019|GM-024|private_readd_current|private_readd_cycles'`: PASS (`+81`)

Go/native preservation was not run because RA-017 did not modify Go/native files.

iOS 26.2 live proof passed with `private_readd_active_members` run id `1779211119484`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_active_members_lfg7fL`, Alice device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob device `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie device `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, and Dana device `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`. Orchestrator verdict: `private_readd_active_members verdicts valid for alice, bob, charlie, dana`. Each role verdict recorded `ra017ActiveMemberChurnProof` with `rowId=RA-017`, `churnCycles=3`, active senders and receivers `alice`, `bob`, and `dana`, `danaActiveMemberCovered=true`, `charlieRemovedWindowPlaintextCount=0`, final roles `alice`, `bob`, `charlie`, and `dana`, final member-list convergence true, final epoch `7`, and final epoch convergence true.

Named gates:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`: red at `+230 -8` only on preserved residuals `BB-007`, `BB-012`, non-RA `IR-003`, accepted-row `IR-018`, `GE-017`, `GE-019`, `GE-020`, and `GM-029`
- `./scripts/run_test_gates.sh completeness-check`: red at `733/734` only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart`
- `git diff --check`: PASS
