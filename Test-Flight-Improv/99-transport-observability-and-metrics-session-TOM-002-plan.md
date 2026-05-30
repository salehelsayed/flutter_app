# TOM-002 - LAN Availability Production Snapshot Wiring Plan

Status: accepted

## Planning Progress

- 2026-05-29 21:03:04 CEST - Evidence/planning/reviewer/arbiter completed locally under the batch fallback. Files inspected: `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`, `lib/core/services/p2p_service_impl.dart`, `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/local_discovery/local_discovery_service.dart`, `lib/core/local_discovery/disabled_local_discovery_service.dart`, `lib/core/debug/transport_metrics.dart`, `test/core/local_discovery/fake_local_p2p_service.dart`, existing transport metric tests. Decision/blocker: no structural blocker; the narrow safe seam is a `P2PServiceImpl` subscription to `LocalP2PService.discoveredPeersStream` plus explicit active/inactive updates around start/stop/restart. Next action: execute this plan.

## real scope

Wire `TransportMetrics.updateLanAvailability` to production local-discovery state in `P2PServiceImpl`.

In scope:
- Track whether local discovery is active inside `P2PServiceImpl`.
- Update `TransportMetrics` with inactive/zero when no local discovery is running.
- Update active/zero after local discovery starts with no peers.
- Update active/nonzero when `LocalP2PService.discoveredPeersStream` emits peers.
- Update inactive/zero after local discovery stops or disposal.
- Add focused host-side service tests using the existing fake local P2P service.

Out of scope:
- mDNS implementation changes, OS permission handling, physical-device LAN acceptance, routing behavior, send fallback policy, settings UI changes, and simulator claims of true LAN success.

## closure bar

TOM-002 is closed when:
- A production `P2PServiceImpl` with shared `TransportMetrics` reflects inactive discovery as `discoveryActive=false, discoveredPeerCount=0`.
- Starting local discovery records `discoveryActive=true` with the current safe peer count.
- Discovered peer stream changes update only aggregate peer count, never peer IDs, hosts, ports, or multiaddrs.
- Stopping or disposing the service records inactive/zero.
- Focused tests prove inactive, active-zero, active-nonzero, and stop transitions.
- Existing transport metric and inbound transport tests still pass.

## source of truth

- Active session contract: TOM-002 in `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`.
- Current code/tests beat stale prose.
- `TransportMetrics` remains the aggregate-only diagnostics model.
- `LocalP2PService.discoveredPeersStream` and `discoveredPeers` are the only source for LAN availability counts in this session.

## session classification

`implementation-ready`

The production seam is local and host-testable. No simulator/physical-device LAN claim is made by this session.

## exact problem statement

`TransportMetrics` exposes a LAN availability snapshot, but production code does not update it from local discovery. TestFlight diagnostics can therefore show the default inactive/zero LAN line even when local discovery is active or has discovered peers.

## files and repos to inspect next

- `lib/core/services/p2p_service_impl.dart`
- `lib/core/debug/transport_metrics.dart`
- `test/core/services/p2p_service_lan_availability_test.dart`
- `test/core/local_discovery/fake_local_p2p_service.dart`

## step-by-step implementation plan

1. Add a `_localPeersSub` subscription and `_localDiscoveryActive` flag to `P2PServiceImpl`.
2. Add a helper that writes `LanAvailabilitySnapshot(discoveryActive: active, discoveredPeerCount: active ? count : 0)` to `_transportMetrics`.
3. Subscribe to `LocalP2PService.discoveredPeersStream` in the constructor and update the helper with the current active flag.
4. Replace the direct `localP2P.start` future in `warmBackground` with a helper that starts local discovery, marks it active, and records the current aggregate peer count.
5. After stop/dispose, mark local discovery inactive and record zero peers.
6. After successful restart advertising, mark active and record the current aggregate peer count; on restart failure, record inactive/zero.
7. Add focused service tests proving inactive, active-zero, active-nonzero, pre-start peer emissions remain inactive, and stop transitions.
8. Run direct tests and the `transport` named gate.

## exact tests and gates to run

```bash
flutter test test/core/services/p2p_service_lan_availability_test.dart
flutter test test/core/debug/transport_metrics_test.dart
flutter test test/core/services/p2p_service_inbound_transport_test.dart
./scripts/run_test_gates.sh transport
```

Final hygiene:

```bash
git diff --check
```

## accepted differences / intentionally out of scope

- This session does not prove true LAN discovery on simulators. It proves production diagnostics reflect the local-discovery service state without identifiers.
- Disabled or absent local discovery is represented as inactive/zero, not as an active zero-peer LAN scan.
- OS-denied discovery still requires platform/device evidence outside this host-side session.

## Execution Verdict

Verdict: accepted.

Landed TOM-002 evidence:
- `lib/core/services/p2p_service_impl.dart` now subscribes to `LocalP2PService.discoveredPeersStream` and records `LanAvailabilitySnapshot` updates through the shared `TransportMetrics`.
- Local discovery startup records active discovery with the current aggregate peer count; stop/dispose record inactive/zero.
- Peer stream changes update only count/state, never peer IDs, hosts, ports, or multiaddrs.
- `test/core/services/p2p_service_lan_availability_test.dart` covers inactive, active zero-peer, active nonzero, pre-start inactive, privacy, and stop transitions.

Tests/gates:
- `flutter test test/core/services/p2p_service_lan_availability_test.dart` passed.
- `flutter test test/core/debug/transport_metrics_test.dart` passed.
- `flutter test test/core/services/p2p_service_inbound_transport_test.dart` passed.
- `./scripts/run_test_gates.sh transport` initially failed before tests because multiple Flutter devices were attached and no device was selected.
- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport` passed.

Residuals: no TOM-002 code residual. True LAN discovery on a physical/device-capable environment remains outside this session and must not be claimed from standard simulator evidence.
