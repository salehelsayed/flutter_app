# INTEGRATE-RA-015 Minimal Integration Contract

Status: accepted

## Source Row

`RA-015 | Go and Flutter config converge after ALREADY_JOINED on re-add | P0 | Remove and Re-add Regression Suite`

Historical source of truth:

- Source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-015-plan.md`

Do not recreate or rerun the historical implementation plan. This contract only governs importing and verifying the already-accepted RA-015 row delta into the main checkout.

## Controller Classification

RA-015 is partially present in main through BB-008/generic already-joined refresh behavior: `go-mknoon/bridge/bridge.go` invokes `RefreshJoinedGroupStateIfNewer`, `go-mknoon/node/pubsub.go` atomically refreshes newer config/key material, and existing tests prove generic `ALREADY_JOINED` refresh and same/older epoch preservation. It is not `skipped_already_present` because the exact row-owned RA-015 remove/re-add convergence proof is missing from main: successful join-note diagnostic exposure in Flutter bridge evidence, direct Flutter RA-015 selector, fake-network RA-015 selector, row-named Go bridge/node selectors, `private_readd_current` `ra015AlreadyJoinedReaddRefreshProof` live-harness and criteria support, criteria tests, and test-inventory row.

Import only the missing meaningful RA-015 delta:

- successful `group:join` response `note` propagation in `GROUP_FL_BRIDGE_JOIN_CONFIG_RESPONSE` diagnostics without changing failure semantics
- direct selector proving Flutter sends current re-add config/key including Charlie and records `ALREADY_JOINED`
- fake-network selector proving the already-joined re-add refresh payload and Alice/Bob/Charlie current-epoch post-refresh delivery
- row-named Go bridge and node selectors proving the already-joined re-add refresh updates native config/key and permits latest-epoch delivery
- `private_readd_current` `ra015AlreadyJoinedReaddRefreshProof` live-harness and criteria support
- RA-015 criteria positive, missing-proof, and missing-current-delivery rejection tests
- row-owned `test-inventory.md` entry

Do not reimplement the BB-008 refresh primitive or duplicate generic refresh tests already present in main.

## Allowed Write Set

- `lib/core/bridge/bridge_group_helpers.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/node/pubsub_test.go`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

The controller owns this contract, the integration breakdown ledger, row ordering, final status, and final verdict. The execution worker must not edit those controller-owned files.

## Verification Contract

Focused checks:

```bash
dart analyze lib/core/bridge/bridge_group_helpers.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'RA-015'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-015'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-015'
(cd go-mknoon && go test ./bridge -run 'TestRA015' -count=1)
(cd go-mknoon && go test ./node -run 'TestRA015' -count=1)
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios
```

Affected preservation checks:

```bash
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'ALREADY_JOINED'
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'latest full config'
(cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic|TestBB008' -count=1)
(cd go-mknoon && go test ./node -run 'TestRefreshJoinedGroupStateIfNewer|TestBB008' -count=1)
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'RA-014|private_readd_current'
```

Required live proof uses only iOS 26.2 CoreSimulator app peers and three distinct devices. The public app path cannot deterministically force an `ALREADY_JOINED` native note; direct Flutter, fake-network, and native Go selectors must cover the forced already-joined refresh, while live proof covers current post-refresh delivery and consumes those host/native/fake-network proof flags through `ra015AlreadyJoinedReaddRefreshProof`.

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current -d <alice>,<bob>,<charlie>
```

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Known residuals from RA-014 may remain unrelated unless the RA-015 import changes their owner surfaces: `BB-007`, `BB-012`, accepted-row `IR-018`, non-RA `IR-003`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, and the unrelated completeness classification miss for `test/shared/fakes/fake_group_pubsub_network_test.dart`.

## Scope Guard

Do not import RA-013 simultaneous multi-device policy, RA-014 stale old-key rejection changes, RA-016 old-interval inbox replay, RA-017/RA-018 churn breadth, UI, notifications, media, network, relay architecture, Android, physical iOS, macOS app-peer proof, KE-007/KE-009 re-reconciliation, ML-012 fixture repair, or unrelated tests from later rows. If a file already contains equivalent or stronger main coverage, merge only the missing RA-015 assertion/helper instead of overwriting main.

## Execution Result

Accepted on 2026-05-19 in standard integration mode.

Imported only the missing row-owned RA-015 delta into the allowed write set: successful `group:join` response `note` propagation in Flutter bridge diagnostics, direct Flutter RA-015 already-joined re-add selector, fake-network already-joined re-add refresh selector, row-named Go bridge and node selectors, `private_readd_current` `ra015AlreadyJoinedReaddRefreshProof` live-harness and criteria support, RA-015 criteria positive/missing-proof/missing-current-delivery tests, and one `test-inventory.md` row.

Controller focused checks passed:

```bash
dart analyze lib/core/bridge/bridge_group_helpers.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'RA-015'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-015'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-015'
(cd go-mknoon && go test ./bridge -run 'TestRA015' -count=1)
(cd go-mknoon && go test ./node -run 'TestRA015' -count=1)
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios
```

Affected preservation checks passed:

```bash
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'ALREADY_JOINED'
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'latest full config'
(cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic|TestBB008' -count=1)
(cd go-mknoon && go test ./node -run 'TestRefreshJoinedGroupStateIfNewer|TestBB008' -count=1)
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'RA-014|private_readd_current'
```

iOS 26.2 live proof passed:

- Scenario: `private_readd_current`
- Run id: `1779207623338`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_k2YAso`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Orchestrator verdict: `private_readd_current verdicts valid for alice, bob, charlie`
- Verdict evidence: all three roles recorded `ra015AlreadyJoinedReaddRefreshProof` with `rowId=RA-015`, Flutter host, native Go, fake-network, and live delivery coverage flags true, and `finalEpoch=2`; Alice re-added Charlie, sent current traffic after refresh, and received Charlie's post-refresh current traffic; Bob observed Charlie re-added, sent current traffic after refresh, and received Alice/Charlie post-refresh current traffic; Charlie accepted the already-joined re-add refresh, imported current config before rejoin ack, accepted post-refresh publish, received Alice/Bob post-refresh current traffic, and saw Alice/Bob/Charlie membership.

Named gates:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+228 -8` on preserved residuals: `BB-007`, `BB-012`, non-RA `IR-003`, accepted-row `IR-018`, `GE-017`, `GE-019`, `GE-020`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).
- `git diff --check` passed before this ledger update and must be run again after it.
