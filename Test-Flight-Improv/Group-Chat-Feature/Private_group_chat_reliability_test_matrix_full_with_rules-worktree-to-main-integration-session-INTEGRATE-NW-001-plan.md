# INTEGRATE-NW-001 Minimal Integration Contract

Status: accepted

## Source Row

`NW-001 | Full-mesh online group delivery works without relay fallback | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle`

Historical source of truth:

- Source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-001-plan.md`
- Historical accepted session block: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`

Do not recreate or rerun the historical implementation plan. This contract only governs importing and verifying the already-accepted NW-001 row delta into the main checkout.

## Controller Classification

NW-001 is missing as an exact row-owned import in main. Current main has supporting full-fanout, topic-peer, and `private_abc_create` coverage, but it does not contain the exact NW-001 row anchors:

- `NW-001 full-mesh online A/B/C delivery works without relay fallback`
- `TestNW001FullMeshDirectGroupDeliveryWithoutRelayFallback`
- `private_full_mesh_online`
- `nw001FullMeshProof`

Therefore this row is not `skipped_already_present`. Import only the missing meaningful NW-001 delta from the historical source row:

- fake-network selector proving Alice, Bob, and Charlie each publish once in a stable online full mesh, every non-sender receives live exactly once, no duplicates appear, and topic peer counts are plausible
- Go direct-topology selector proving a three-node direct peerstore full mesh can publish without waiting for relay fallback and each publish observes at least two topic peers
- `private_full_mesh_online` live-harness/runner/criteria support and strict `nw001FullMeshProof` validation
- NW-001 criteria accept/reject tests for Alice-only proof, missing Bob/Charlie publish, missing or partial topic peer counts, missing receiver tuples, duplicates, and wrong row id
- row-owned `test-inventory.md` entry after green proof

Do not import NW-002 relay-only/circuit routing, NW-003 partition healing, NW-004 reconnect, lifecycle, UI, notification, media, stress, soak, chaos, multi-relay, source matrix rewrites, COMPLETE_1 docs, or unrelated test inventory changes.

## Allowed Write Set

Execution may edit only these row-owned files:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `go-mknoon/node/pubsub_delivery_test.go`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Read but do not edit unless the controller explicitly re-authorizes after a focused NW-001 failure:

- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/utils/flow_event_emitter.dart`
- `go-mknoon/node/pubsub.go`
- source matrix docs, source session breakdown docs, COMPLETE_1 docs, and the integration breakdown ledger

Controller-owned docs may be updated only by the controller or closure step:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

The execution worker may update only this plan's `Execution Progress`, `Execution Result`, and `QA Result` sections while executing the current contract.

## Device/Relay Proof Profile

Profile: `three-party/device-lab` plus host fake-network and Go direct-topology proof.

NW-001 requires real iOS 26.2 CoreSimulator app-peer evidence for Alice, Bob, and Charlie. A single `FLUTTER_DEVICE_ID` gate is not sufficient closure evidence.

Fresh preflight before this contract confirmed no stale live runner processes and these available iOS 26.2 devices:

- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Dana/spare: `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`

Before live proof, execution must rerun:

```bash
flutter devices --machine
xcrun simctl list devices available
```

Each selected app-peer role must be supported, `targetPlatform == ios`, `emulator == true`, and `sdk == com.apple.CoreSimulator.SimRuntime.iOS-26-2`, and must appear under the `-- iOS 26.2 --` `simctl` section.

Required relay env for the live harness:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
```

Required live command for this integration run:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_full_mesh_online -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Expected verdict: `private_full_mesh_online` with `nw001FullMeshProof`, `rowId=NW-001`, `activeRoles=[alice,bob,charlie]`, `senderRoles=[alice,bob,charlie]`, `allRolePublishesCovered=true`, `allActiveReceiversCovered=true`, `duplicateVisibleMessageCount=0`, `successNoPeersCount=0`, `partialPeerPublishCount=0`, `topicPeerCountsBySender` all at least `2`, and live-only receipt of the two non-sender messages by every role.

The historical source proof used older iOS 26.2 UDIDs and run `1778663232583`; this integration run must record the fresh run id, shared dir, and current device ids.

## Verification Contract

Focused checks:

```bash
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'NW-001'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'NW-001'
(cd go-mknoon && go test ./node -run 'TestNW001FullMeshDirectGroupDeliveryWithoutRelayFallback|TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeRelayReadyWhenDirectAddrsKnown|TestPublishGroupMessage_ReturnsPeerCountPositive_WhenPeersConnected' -count=1)
dart analyze test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart
```

Formatting:

```bash
dart format --output=none --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart
(cd go-mknoon && gofmt -w node/pubsub_delivery_test.go && git diff --check -- node/pubsub_delivery_test.go)
```

Affected preservation checks:

```bash
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-018'
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_full_mesh_online --list-scenarios
```

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Known residuals from prior accepted rows may remain unrelated unless the NW-001 import changes their owner surfaces: `BB-007`, `BB-012`, non-RA `IR-003`, accepted-row `IR-018`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, and the unrelated completeness classification miss for `test/shared/fakes/fake_group_pubsub_network_test.dart`.

## Scope Guard

Do not broaden NW-001 into:

- NW-002 relay-only/circuit-routed delivery
- NW-003 partition during removal/re-add
- NW-004 relay reconnect or topic-subscription repair
- NW-006 disconnect versus membership truth
- NW-010 lifecycle/background/foreground delivery
- GE zero-peer or partial-peer inbox fallback rows
- APNs, foreground push, notification tap routing, media, voice, reactions, UI, unread badges, stress, soak, chaos, multi-relay failover, or shared relay-state work

Do not copy whole files from the historical worktree. The current main files contain many accepted later-row changes; merge only the NW-001 row-owned blocks.

## Execution Progress

| timestamp | phase | files inspected or touched | decision/blocker | next action |
|---|---|---|---|---|
| 2026-05-19 | local plan fallback completed | Historical NW-001 source row/plan/breakdown; current integration breakdown; current main row-owned anchor search; read-only scout findings; iOS 26.2 device preflight | Minimal integration contract created because the spawned planning child did not materialize the intended plan file under bounded wait. NW-001 is classified as missing exact row-owned import in main. | Spawn one write-active execution worker for NW-001 only. |
| 2026-05-19 | import completed | `test/features/groups/integration/group_messaging_smoke_test.dart`; `go-mknoon/node/pubsub_delivery_test.go`; `integration_test/group_multi_party_device_real_harness.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart`; `test/integration/group_multi_party_device_criteria_test.dart` | Imported only the missing NW-001 row-owned fake-network selector, Go full-mesh selector, `private_full_mesh_online` runner/live-harness/criteria support, and strict criteria positive/rejection tests. Existing main support for full fanout/topic-peer diagnostics was reused. | Run focused host/native checks and iOS 26.2 live proof. |
| 2026-05-19 | verification accepted | Row-owned files above; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`; integration ledger | Focused checks passed: `dart analyze` on row-owned Dart files (`No issues found!`), `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'NW-001'` (`+1` after a first parallel native-assets build race was rerun serially), `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'NW-001'` (`+7`), `(cd go-mknoon && go test ./node -run 'TestNW001FullMeshDirectGroupDeliveryWithoutRelayFallback|TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeRelayReadyWhenDirectAddrsKnown|TestPublishGroupMessage_ReturnsPeerCountPositive_WhenPeersConnected' -count=1)` (`ok github.com/mknoon/go-mknoon/node 2.221s`), runner discovery printed `private_full_mesh_online`, and `git diff --check` passed. iOS 26.2 live proof run `1779219623746` passed in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_full_mesh_online_ui6Wkx` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; orchestrator verdict: `private_full_mesh_online verdicts valid for alice, bob, charlie`. | Update integration breakdown and continue to INTEGRATE-NW-002 after ledger sanity. |

## Final Verdict

Accepted. NW-001 was imported as a row-owned reconciliation only; original worktree plans were not recreated and unrelated NW/RA/GE/ST work stayed out of scope. The live proof recorded `nw001FullMeshProof` on Alice, Bob, and Charlie with `rowId=NW-001`, `allRolePublishesCovered=true`, `allActiveReceiversCovered=true`, `duplicateVisibleMessageCount=0`, `successNoPeersCount=0`, `partialPeerPublishCount=0`, and `topicPeerCountsBySender` of `2` for Alice, Bob, and Charlie.
