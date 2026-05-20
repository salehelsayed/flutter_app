# INTEGRATE-NW-003 Minimal Integration Contract

Status: accepted

Session id: `INTEGRATE-NW-003`

Source row: `NW-003 | Partition during removal and re-add heals to latest state | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle`

Historical source of truth:

- Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-003-plan.md`
- Source inventory evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Do not recreate or rerun the historical implementation plan. This contract governs only importing and verifying the already-accepted NW-003 row delta into the main checkout.

## Current-Main Classification

NW-003 was missing as an exact row-owned import in main. Current main had accepted NW-001 full-mesh and NW-002 relay/circuit coverage, but it did not contain the exact NW-003 row anchors before this integration:

- `private_partition_readd_heal`
- `nw003PartitionReaddHealProof`
- `TestNW003PartitionDuringRemoveReaddHealsToLatestTopicState`
- focused host tests for partitioned remove/re-add healing and removed-window entitlement filtering
- criteria rejection coverage for fake-only or incomplete partition-heal proof

Therefore this row was not `skipped_already_present`. Only the missing meaningful NW-003 row-owned delta was imported.

## Import Scope

Allowed row-owned imports:

- `handle_app_resumed.dart` self-peer-id propagation into group offline inbox draining
- NW-003 durable-recipient application selector in `send_group_message_use_case_test.dart`
- NW-003 membership and resume-recovery integration selectors
- NW-003 Go local partition/re-add topic-state selector
- `private_partition_readd_heal` runner/live-harness/criteria support and strict `nw003PartitionReaddHealProof` validation
- NW-003 criteria accept/reject tests
- one concise `test-inventory.md` row

Not imported: NW-004 reconnect repair, NW-005 rediscovery, NW-006 disconnect semantics, broad relay shared-state architecture, lifecycle rows beyond the row-owned `selfPeerId` drain propagation, UI, notifications, media, Android, physical iOS, source docs, COMPLETE_1 docs, or unrelated worktree changes.

## Verification

Focused checks run:

```sh
dart analyze test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart lib/core/lifecycle/handle_app_resumed.dart lib/features/groups/application/send_group_message_use_case.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_recovery_gate.dart lib/features/groups/application/rejoin_group_topics_use_case.dart lib/core/bridge/bridge_group_helpers.dart
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'NW-003'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'NW-003'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-003'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'NW-003'
(cd go-mknoon && go test ./node -run 'TestNW003|TestNW001FullMeshDirectGroupDeliveryWithoutRelayFallback|TestNW002RelayOnlyOrCircuitRoutedPeerReceivesGroupMessages|TestPublishGroupMessage_EmitsLiveFanoutDiagnosticWithoutFailingDurableSend' -count=1)
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_partition_readd_heal --list-scenarios
git diff --check
```

Results:

- scoped analyzer: PASS with only pre-existing `handle_app_resumed.dart` style infos
- NW-003 durable-recipient selector: PASS (`+1`)
- NW-003 membership smoke selector: PASS (`+1`)
- NW-003 resume-recovery selector: PASS (`+1`)
- NW-003 criteria selectors: PASS (`+9`)
- Go selector bundle: PASS (`ok github.com/mknoon/go-mknoon/node 3.844s`)
- runner discovery: PASS (`private_partition_readd_heal`)
- post-run stale runner process check: PASS
- `git diff --check`: PASS

Required live proof:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_partition_readd_heal -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Live proof result: PASS.

- Run id: `1779223496207`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_partition_readd_heal_IrYeIA`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Orchestrator verdict: `private_partition_readd_heal verdicts valid for alice, bob, charlie`

Role verdicts recorded `nw003PartitionReaddHealProof` with `rowId=NW-003`, `scenario=private_partition_readd_heal`, `appPeerPlatform=ios_26_2_core_simulator`, `partitionProofSource=app_peer_core_simulator`, `fakeNetworkOnly=false`, Alice partitioned from Bob and Charlie, Bob and Charlie partitioned from Alice, removed-window sent while Charlie was removed, removed-window live delivery blocked during the partition, Bob received the removed-window after heal, Charlie did not receive the removed-window, final Alice/Bob/Charlie membership convergence, final key epoch convergence at epoch `2`, and post-heal live delivery from Alice, Bob, and Charlie.

## Final Execution Verdict

Verdict: `accepted`

NW-003 is accepted in main. The imported row-owned delta proves partition during removal and re-add heals to latest state through host, Go, criteria, runner, and iOS 26.2 live evidence without importing NW-004+ reconnect/disconnect/lifecycle scope.

Residual classifications from earlier integration rows are preserved unchanged: non-row `BB-007`, `BB-012`, accepted-row `IR-018` fixture aging, `GM-029`, non-RA `IR-003`, `GE-017`, `GE-019`, `GE-020`, sampled retained-history drain follow-up invariant, sampled `ML-008`, sampled COMPLETE_1 `GI-017`, sampled replay-window residuals `GM-033`/`GK-023`/`GI-019`, drain `GEK003` and `GE-018`, full-listener notification/self-peer-cache failures, strict-analyzer pre-existing infos/warnings, completeness classification failure, and `KE-007`/`KE-009` blocked-conflict records remain for future row-owned/follow-up work.
