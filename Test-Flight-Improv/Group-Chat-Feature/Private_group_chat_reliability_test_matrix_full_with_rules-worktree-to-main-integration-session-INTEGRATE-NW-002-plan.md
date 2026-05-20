# INTEGRATE-NW-002 Minimal Integration Contract

Status: accepted

Session id: `INTEGRATE-NW-002`

Source row: `NW-002 | Relay-only or circuit-routed peers receive group messages | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle`

Historical source of truth:

- Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-002-plan.md`
- Source inventory evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Do not recreate or rerun the historical implementation plan. This contract governs only importing and verifying the already-accepted NW-002 row delta into the main checkout.

## Current-Main Classification

NW-002 is missing as an exact row-owned import in main. Current main has accepted NW-001 full-mesh support and generic group-discovery route diagnostics, but it does not contain the exact NW-002 row anchors:

- `NW-002 relay-only or circuit-routed peer receives group messages`
- `TestNW002RelayOnlyOrCircuitRoutedPeerReceivesGroupMessages`
- `private_relay_only_delivery`
- `nw002RelayOnlyDeliveryProof`
- criteria rejection coverage for fabricated route booleans without diagnostics

Therefore this row is not `skipped_already_present`. Import only the missing meaningful NW-002 delta from the historical source row.

## Import Scope

Allowed row-owned imports:

- fake-network route-mode metadata and delivery-record test support
- NW-002 fake-network selector in `group_messaging_smoke_test.dart`
- Go sanitized route diagnostic `peerIdPrefix` emission and NW-002 local relay/circuit selector in `pubsub.go` / `pubsub_delivery_test.go`
- `private_relay_only_delivery` runner/live-harness/criteria support and strict `nw002RelayOnlyDeliveryProof` validation
- NW-002 criteria accept/reject tests
- one concise `test-inventory.md` row

Do not import NW-003 partition heal, NW-004 reconnect, NW-006 disconnect semantics, broad relay failover, lifecycle, UI, notification, media, privacy, stress, source docs, COMPLETE_1 docs, or unrelated worktree changes.

## Required Verification

Focused host/native checks:

```sh
dart analyze test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'NW-002'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'NW-002'
(cd go-mknoon && go test ./node -run 'TestNW002|TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeCircuitAddressWait|TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeRelayReadyWhenDirectAddrsKnown|TestPublishGroupMessage_EmitsLiveFanoutDiagnosticWithoutFailingDurableSend' -count=1)
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_relay_only_delivery --list-scenarios
```

Required live proof:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_relay_only_delivery -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Expected verdict: `private_relay_only_delivery` with `nw002RelayOnlyDeliveryProof`, `rowId=NW-002`, Alice-to-Bob and Bob publish-back delivery, preserved active membership, duplicate visible message count `0`, membership mutation count `0`, and at least one role truthfully proving `circuitOrRelayRouteProven=true` plus `directPathSuppressed=true` from sanitized Bob route diagnostics containing a bounded peer prefix, relay path, `attemptedDirect=false`, and `directAddrCount=0`.

Run `git diff --check` before closure. Run broader named gates only if focused verification requires or if touched production/native route code requires preservation classification.

## Progress

| Date | Status | Evidence | Decision | Next Action |
|---|---|---|---|---|
| 2026-05-19 | local plan fallback completed | Historical NW-002 plan/source inventory; current integration breakdown; current-main row-owned anchor search; read-only scout kickoff | NW-002 is classified as missing exact row-owned import in main. | Import only missing NW-002 row-owned deltas, then run focused checks and live proof. |
| 2026-05-19 | accepted | Imported the missing row-owned NW-002 fake-network route-mode support, Go sanitized `peerIdPrefix` diagnostics and local relay/circuit selector, `private_relay_only_delivery` runner/live-harness/criteria support, NW-002 criteria accept/reject tests, and one test-inventory row. Focused checks passed: scoped analyzer (`No issues found!`), fake-network selector (`+1`), criteria selector (`+8`), Go selector bundle (`ok github.com/mknoon/go-mknoon/node 1.688s` after fixing the imported collector reference), runner discovery (`private_relay_only_delivery`), and iOS 26.2 live proof run `1779221526301` in shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_relay_only_delivery_ZTdoSK`. | NW-002 is accepted. | Update integration breakdown ledger, rerun diff hygiene, then continue with INTEGRATE-NW-003 after ledger sanity and fresh row validation. |

## Final Execution Verdict

Verdict: `accepted`

NW-002 is accepted in main. The imported row-owned delta proves relay-only or circuit-routed peers receive group messages through host, Go, criteria, runner, and iOS 26.2 live evidence without importing NW-003+ partition/reconnect/lifecycle scope.

Live proof evidence: run id `1779221526301`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_relay_only_delivery_ZTdoSK`, Alice device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob device `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie device `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, orchestrator verdict `private_relay_only_delivery verdicts valid for alice, bob, charlie`. The Charlie role verdict recorded `nw002RelayOnlyDeliveryProof` with `rowId=NW-002`, `relayOnlyRoles=['bob']`, `circuitOrRelayRouteProven=true`, `directPathSuppressed=true`, Bob-targeted diagnostics `peerIdPrefix=12D3KooWGwRy`, `path=relay`, `attemptedDirect=false`, `directAddrCount=0`, Alice-to-Bob and Bob publish-back live delivery, duplicate visible message count `0`, membership mutation count `0`, and active membership preserved.
