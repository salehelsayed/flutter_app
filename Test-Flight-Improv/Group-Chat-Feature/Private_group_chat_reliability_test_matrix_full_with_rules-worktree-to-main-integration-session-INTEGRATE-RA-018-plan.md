# INTEGRATE-RA-018 Minimal Integration Contract

Status: accepted

## Source Row

`RA-018 | Churn with alternating senders remains deterministic | P0 | Remove and Re-add Regression Suite`

Historical source of truth:

- Source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-018-plan.md`

Do not recreate or rerun the historical implementation plan. This contract only governs importing and verifying the already-accepted RA-018 row delta into the main checkout.

## Controller Classification

RA-018 is partially present in main through adjacent broad churn coverage: RA-017 proves Alice/Bob/Dana stay live while only Charlie churns, and GE/GM rows provide broader randomized or property-style churn coverage. It is not `skipped_already_present` because the exact RA-018 alternating Charlie/Dana churn proof surfaces are missing from the target checkout: row-named direct selectors, the four-member fake-network selector, `private_readd_alternating_churn` runner/live-harness/criteria support, RA-018 criteria tests, and the row-owned `test-inventory.md` entry.

Import only the missing meaningful RA-018 delta:

- direct key-distribution selector proving alternating Charlie/Dana churn keeps key distribution deterministic for each active interval
- direct durable-recipient selector proving durable inbox recipients match active members minus sender for every rotating sender
- four-member fake-network selector proving three complete Charlie/Dana alternation cycles with rotating active senders, exact active-interval visibility, no removed-window plaintext, no duplicate visible messages, and no inactive sender attempts
- `private_readd_alternating_churn` runner/live-harness support and `ra018AlternatingChurnProof` criteria validation
- RA-018 criteria positive and rejection tests for weak RA-017-only/ML-008-only proof, missing churn targets, missing A/B/C/D sender coverage, inactive sender use, inactive-window plaintext, duplicates, insufficient cycles, and final membership/key divergence
- row-owned `test-inventory.md` entry

Do not import source production files. The historical RA-018 closure says no production code changes were required. Do not import source matrix/session-breakdown doc rewrites, COMPLETE_1 docs, RA-017 rewrites, GE/NW/ST broader churn work, UI, notifications, media, relay shared-state, Android, physical iOS, or unrelated tests.

## Allowed Write Set

- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Read but do not edit unless the controller explicitly re-authorizes after a focused RA-018 failure:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- Go/native files
- source matrix docs, source session breakdown docs, COMPLETE_1 docs, and this integration breakdown ledger

The controller owns this contract, the integration breakdown ledger, row ordering, final status, and final verdict. The execution worker must not edit those controller-owned files.

## Verification Contract

Focused checks:

```bash
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'RA-018'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'RA-018'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-018'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-018'
dart analyze lib/features/groups/application/send_group_message_use_case.dart lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/remove_group_member_use_case.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_key_update_listener.dart lib/features/groups/application/rejoin_group_topics_use_case.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_alternating_churn --list-scenarios
```

Affected preservation checks:

```bash
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'RA-017'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'RA-017'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-017'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-008'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'RA-017|private_readd_active_members|private_readd_cycles'
```

Required live proof uses only iOS 26.2 CoreSimulator app peers and four distinct devices for Alice, Bob, Charlie, and Dana:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_alternating_churn -d <alice>,<bob>,<charlie>,<dana>
```

Expected verdict: `ra018AlternatingChurnProof`, `rowId=RA-018`, three churn cycles, churn targets `charlie` and `dana`, active senders and receivers including Alice/Bob/Charlie/Dana, active interval evidence, Charlie and Dana removed-window plaintext counts `0`, duplicate visible message count `0`, inactive sender attempt count `0`, final Alice/Bob/Charlie/Dana membership convergence, final epoch `13`, and final epoch convergence.

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Known residuals from RA-017 may remain unrelated unless the RA-018 import changes their owner surfaces: `BB-007`, `BB-012`, non-RA `IR-003`, accepted-row `IR-018`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, and the unrelated completeness classification miss for `test/shared/fakes/fake_group_pubsub_network_test.dart`.

## Scope Guard

Do not broaden RA-018 into RA-017 active-member breadth, RA-013 same-user multi-device policy, ML-008 repeated-cycle stress, GE-020 long-soak repair, NW/ST chaos or soak rows, product UI, notification, media, relay shared-state, Android, physical iOS, or simulator-device management outside the required four-role proof. If a test file already contains equivalent or stronger coverage, merge only the missing RA-018 assertion/helper instead of overwriting current main.

## Execution Result

Final status: `accepted`

The RA-018 row-owned delta was imported only into the allowed test/harness/criteria/runner/test-inventory files. No production files, Go/native files, source matrix docs, COMPLETE_1 docs, or broader churn rows were imported.

Focused and preservation checks passed:

- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'RA-018'` PASS (`+1`)
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'RA-018'` PASS (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-018'` PASS (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-018'` PASS (`+8`)
- `dart analyze ...` scoped RA-018 owner files PASS (`No issues found!`)
- runner discovery for `private_readd_alternating_churn` PASS
- RA-017 direct/fake-network preservation selectors PASS (`+1`, `+1`, `+1`)
- ML-008 repeated-cycle preservation selector PASS (`+1`)
- RA-017/private re-add criteria preservation bundle PASS (`+16`)

The first required iOS 26.2 live proof did not produce a valid RA-018 verdict in main:

- command: `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_alternating_churn -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- run id: `1779213742336`
- shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_alternating_churn_EpQeim`
- devices were all iOS 26.2 CoreSimulator devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- failure signature: Bob exited before writing a verdict; Bob timed out in `_waitForKeyEpoch` after `ra018_charlie_removed_key_c3.json`, Alice timed out waiting for `gmp_1779213742336_bob_ra018_charlie_removed_key_c3`, and Charlie/Dana timed out waiting for `gmp_1779213742336_alice_sent_ra018Cycle3_charlieRemoved_alice.json`
- evidence also shows repeated relay recovery and group inbox cursor retry events (`GROUP_INBOX_ERROR`) during the run; the imported RA-018 harness body for the failing path matches the historical source row body, with only unrelated current-main conditional proof fields for other scenarios

Fixture recovery rerun accepted RA-018 without code or test changes:

- preflight: no stale `run_group_multi_party_device_real`, `group_multi_party_device_real_harness`, `private_readd_alternating_churn`, `flutter_tester`, `xcodebuild`, or stale `simctl` runner processes were active; all four specified iOS 26.2 CoreSimulator devices were booted and available in both `simctl` and `flutter devices --machine`; no ambient `MKNOON_` environment variables were set
- command: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_alternating_churn -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- run id: `1779216477110`
- shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_alternating_churn_UMfABf`
- devices were all iOS 26.2 CoreSimulator devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- orchestrator verdict: `ok=true`, `private_readd_alternating_churn verdicts valid for alice, bob, charlie, dana`
- role verdicts wrote `ra018AlternatingChurnProof` with `rowId=RA-018`, `churnCycles=3`, churn targets `charlie` and `dana`, active senders and receivers `alice`, `bob`, `charlie`, and `dana`, twelve active-interval records, Charlie and Dana removed-window plaintext counts `0`, duplicate visible message count `0`, inactive sender attempt count `0`, final Alice/Bob/Charlie/Dana membership convergence, final epoch `13`, and final epoch convergence true
- cycle-3 recovery evidence is present in the shared dir, including `gmp_1779216477110_bob_ra018_charlie_removed_key_c3`, `gmp_1779216477110_alice_sent_ra018Cycle3_charlieRemoved_alice.json`, all cycle-3 send/receive proof files, four role verdict JSON files, and `gmp_1779216477110_private_readd_alternating_churn_orchestrator_verdict.json`

Named gates after import:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` red at `+231 -8` only on the preserved residual set: `BB-007`, `BB-012`, non-RA `IR-003`, accepted-row `IR-018`, `GE-017`, `GE-019`, `GE-020`, and `GM-029`
- `./scripts/run_test_gates.sh completeness-check` red only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`)
- `git diff --check` PASS

Controller closure decision: RA-018 is accepted after fixture recovery because the fresh iOS 26.2 `private_readd_alternating_churn` proof run `1779216477110` produced valid role and orchestrator verdicts for Alice, Bob, Charlie, and Dana. The earlier run `1779213742336` remains recorded as blocked external fixture evidence, but the recovery pass proves the blocker was not reproducible after a clean shared fixture. Existing residual gate classifications are preserved, and the safe pipeline resume point is `INTEGRATE-NW-001` after ledger sanity; NW-001 was not executed in this recovery pass.
