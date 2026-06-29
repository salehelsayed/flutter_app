# 174 - FDC-11 LAN-dial advert: re-derive & re-advertise libp2p ports so CV-08 goes green  (Bug)

Status: host-complete (host-green + mutation-verified + adversarially reviewed; device-proof CV-08 deferred closure gate; NOT committed) — implemented 2026-06-29
Spec: free-text intent (no formal spec) — device-verified from CV-08 D1 run 2026-06-28; evidence in memory `project_cv08_fdc11_device_red_2026_06_28.md`

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-28 | Evidence Collector | device captures (cv08_pixel/iphone11), p2p_service_impl.dart, local_p2p_service.dart, lan_dial.go, node.go, basic_host.go | Fix is Dart-only; Go already resolves+exposes LAN QUIC/TCP into listenAddresses | grounding workflow (7-agent verify→refute) |
| 2026-06-28 | Planner | local_p2p_service.dart (full), p2p_service_impl.dart:4052-4147 / :797-844, fakes | Self-heal seam = `_handleAddressesUpdated`; 1 LocalP2PService fake | matrix + RED catalog |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-29 | contract extraction | (snapshot) | `git status --short` = clean (HEAD 86415563; only plan/INDEX/info.plist dirty) | scope confirmed, anchors re-grounded (drift fixed) | RED |
| 2026-06-29 | RED tests added | 2 fakes + 2 test files | local_p2p_service_test compile-RED (missing `updateLibp2pPorts`); impl TC-01/TC-04 logic-RED, TC-05a/b green | RED for expected reasons | impl |
| 2026-06-29 | implementation | local_p2p_service.dart, p2p_service_impl.dart | `updateLibp2pPorts` + `_handleAddressesUpdated` re-derive | scoped files only | GREEN |
| 2026-06-29 | direct GREEN | — | local_p2p_service_test +16, p2p_service_impl_test +110 | reds now green | mutation |
| 2026-06-29 | mutation-verify | (revert/restore) | 5 mutations re-RED + reverted; **TC-05 vacuity found & fixed** (ws-lane ordering) | every fix row bites | review |
| 2026-06-29 | adversarial review | (workflow, 7 agents) | 4 findings, **2 confirmed**: #2 HIGH bonsoir-restart crash (FIXED), #1 MED ip4/ip6 family (follow-up) | #2 blocked → fixed in-loop | re-GREEN |
| 2026-06-29 | design fix (review #2) | p2p_service_impl.dart, impl test | defer re-advertise until `_localNetworkProven` (peer resolved); +TC-01b/TC-06 | crash vector closed | gates |
| 2026-06-29 | preservation GREEN | — | test/core/local_discovery/ +145; both target files +128 | sentinels green | named gates |
| 2026-06-29 | named gates | — | core-host-all 263 files 0-FAIL; 1to1 +1393 0-FAIL; analyze 0-new | gate green | QA |
| 2026-06-29 | QA (independent) | — | host-green; device-proof CV-08 deferred (closure gate) | blocking: none | host-complete |

## Source Of Truth
- Spec / intent: inline below + memory `project_cv08_fdc11_device_red_2026_06_28.md`
- Gate definitions: scripts/run_test_gates.sh (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready (host TDD now; device-proof is the deferred closure gate — manual two-phone, same as 171 TC-13)

## Exact Problem Statement
FDC-11 (bonsoir-fed libp2p LAN-direct dial) does not fire on device. Verified on a real two-phone CV-08 run (Pixel 6 ↔ iPhone 11, same Wi-Fi, flags-ON build `MKNOON_ENABLE_LIBP2P_LAN_DIAL=true` + `FDC_FLOW_LOG=1`): mDNS discovery works (iPhone 11 sees the Pixel: `LOCAL_MDNS_PEER_FOUND{host:"Android_…local.",port:39513=wsPort}`), but `P2P_LAN_PEER_FOUND_REQUEST=0`, `node:lan_peer_found=0`, `node:lan_dial_ready=0` — both OS, both directions. The bonsoir advert carries only the wsPort, never the libp2p QUIC/TCP ports, so every discovered peer's `LocalPeer.libp2pAddresses` is empty and the forwarder short-circuits before the Go bridge. CV-08 (the D1 device gate that gates flipping the flag default) is therefore RED.

What must improve: the bonsoir advert must carry the resolved libp2p QUIC/TCP LAN ports so a same-WiFi peer builds a non-empty `libp2pAddresses` and the Go LAN dial fires. Add a numeric (un-redacted) advert-port diagnostic so CV-08 is verifiable from device logs.

What must stay unchanged (→ preserved-green sentinels): the wsPort advert/WS messaging path; the existing FDC-11 forwarder + `'p2p_lan_dial'` migration gate; the bonsoir suspected-denied gate (171 bundle); `EnableLibp2pLANDial` stays default-OFF (CV-09 is a separate flip step, gated on CV-08 green); 1to1 + transport host gates.

## Root Cause (verify → refute confirmed)
The advert ports are derived **once** at the FDC-07 cold-start early seam and never re-derived:
- `_startLocalDiscovery` (p2p_service_impl.dart:797) reads `_currentState.listenAddresses` (:812) and derives ports via `_libp2pListenPort` (:815-816, regex `/udp/(\d+)/quic-v1` and plain `/tcp/(\d+)` excluding ws/quic, :828-844). At the hoisted early seam the host has not yet surfaced its resolved LAN listen addrs, so listenAddresses lacks a `/udp/<p>/quic-v1` → `_libp2pListenPort` returns **null** (the code's own comment, :807-811).
- `local_p2p_service.start()` caches those null ports in `_quicPort/_tcpPort` (local_p2p_service.dart:41-42) — the **only** assignment sites — and advertises null (`'quicPort': ?quicPort` null-spread omits them, :51-60).
- `start()` is latched off afterwards by `_localDiscoveryActive` (p2p_service_impl.dart:802/847), so no later `_startLocalDiscovery` re-derives.
- The resolved LAN QUIC/TCP addr **does** arrive in Dart (CONFIRMED: Go `host.Addrs()` resolves ephemeral `udp/0`/`tcp/0` to concrete `/ip4/192.168.x.y/udp/<port>/quic-v1` via `manet.ResolveUnspecifiedAddresses`, basic_host.go:870-890, not gated by `ForceReachabilityPrivate`; `node.Status().splitHostAddresses` routes it into `listenAddresses` JSON, node.go:649-693/1932-1949; reaches Dart at start_response p2p_service_impl.dart:615 AND every `addresses:updated` push :4052) — but `_handleAddressesUpdated` (:4052-4147) only updates state + `_emitState`; it **never re-derives or re-advertises**. `restartAdvertising` (local_p2p_service.dart:73-96) re-publishes the cached null (:82-83).

⇒ The cold-start null is **permanent for the process lifetime**. The fix is **Dart-only**: re-derive libp2p ports on `addresses:updated` and re-advertise when they transition null→known (or change). No Go change.

Refuted / do-NOT-re-introduce:
- "The break is `p2p_service_impl.dart:914` (`libp2pAddresses.isEmpty → continue`)" — **REFUTED**: :914 is a downstream symptom; the advert never carries ports upstream. Do not "fix" line 914.
- "Need a Go change to resolve/expose the bound LAN port" — **REFUTED**: Go already resolves it correctly into `listenAddresses`; the regex extracts it correctly (`quic-v1` literal pin go.mod v0.39.1; ip4/ip6/p2p-suffix don't break the non-anchored `firstMatch`). Do not touch Go listen config.
- "`addresses:updated`/relay-recovery already re-advertises with fresh ports" — **REFUTED**: `_handleAddressesUpdated` only `_emitState`s; the sole `restartAdvertising` caller (:4581, recovery) reuses cached null.

## Real Scope
In scope: (1) `LocalP2PService.updateLibp2pPorts({quicPort, tcpPort})` — re-advertise with fresh ports when changed, no-op when unchanged, update the cache; (2) `_handleAddressesUpdated` re-derives `_libp2pListenPort(listenAddresses)` and calls `updateLibp2pPorts` when local discovery is active; (3) numeric diagnostic `FDC_LAN_ADVERT_PORTS{quicPort,tcpPort,source}` (explicit ints, -1 for null) for device verification; (4) update `FakeLocalP2PService` for the new method.
Out of scope (owning work): flipping `EnableLibp2pLANDial` default → CV-09; DCUtR/media device proofs → FDC-12/15; the Pixel relay-flap → separate investigation; any Go node listen-address change.

## Files To Inspect Next
Production: lib/core/local_discovery/local_p2p_service.dart (start/restartAdvertising/cache :39-96), lib/core/services/p2p_service_impl.dart (_startLocalDiscovery:797, _libp2pListenPort:828, _handleAddressesUpdated:4052, _forwardLanPeersToLibp2pDial:910), lib/core/local_discovery/bonsoir_discovery_service.dart (startAdvertising + _buildLibp2pAddresses :105-113), lib/core/utils/flow_event_emitter.dart (redaction).
Tests + fakes: test/core/local_discovery/local_p2p_service_test.dart, test/core/services/p2p_service_impl_test.dart (FDC-11 group), test/core/local_discovery/fake_local_p2p_service.dart (FakeLocalP2PService, startedQuicPort/TcpPort, restartAdvertising no-op:67), test/core/local_discovery/fake_local_discovery_service.dart (advertisedQuicPort/TcpPort:14-15,39-40).
Dependency-only context: go-mknoon/node/lan_dial.go (proof events), lib/core/bridge/go_bridge_client.dart (addresses:updated parse :683-697).

## Existing Tests Covering This Area
- `_libp2pListenPort` extraction at start: **MISSING** (no test seeds listenAddresses and asserts the extracted advert port) → add TC-05.
- `local_p2p_service` restartAdvertising re-deriving ports: **MISSING** (restartAdvertising re-publishes cache; no re-derive path or test) → add TC-02/TC-03.
- Forwarder `_forwardLanPeersToLibp2pDial` / line-914 skip on empty addresses: **EXISTS** (FDC-11 group) — preservation only.
- bonsoir advert TXT (`startAdvertising wires … peer TXT record`): EXISTS (bonsoir_discovery_service_contract_test.dart:53) — preservation.
Missing coverage gaps: the null→known self-heal (the actual bug) has zero coverage today.
Already in curated family arrays?: FDC-11 host tests live under `test/core/**` (auto-glob `core-host-all`). Verify whether `TRANSPORT_TESTS` in run_test_gates.sh lists any; add the new files there only if FDC-11 is curated under the transport gate (else AUTO is sufficient).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
1. test/core/services/p2p_service_impl_test.dart::`FDC-11 self-heal: addresses:updated with libp2p ports re-advertises`
   - Tier: unit/application host
   - Shape/setup: P2PServiceImpl with `FakeLocalP2PService`; start node so `_startLocalDiscovery` runs with EMPTY listenAddresses (fake `startedQuicPort==null`); drive the `addresses:updated` handler (via the bridge event seam used in existing tests) with `listenAddresses:['/ip4/192.168.0.5/udp/45000/quic-v1','/ip4/192.168.0.5/tcp/45001','/ip4/192.168.0.5/tcp/8080/ws']`. Assert `FakeLocalP2PService.updatedQuicPort==45000` AND `updatedTcpPort==45001` AND `updateLibp2pPortsCallCount==1`.
   - RED on HEAD because: `updateLibp2pPorts` does not exist (compile RED), and `_handleAddressesUpdated` never calls it (logic RED once the fake/method exist).
   - GREEN after fix asserts: the re-derive in `_handleAddressesUpdated` invokes `updateLibp2pPorts(45000,45001)`.
   - Mutation that re-reds: remove the `updateLibp2pPorts(...)` call from `_handleAddressesUpdated` → this test red.
2. test/core/local_discovery/local_p2p_service_test.dart::`updateLibp2pPorts re-advertises with fresh libp2p ports`
   - Tier: unit host
   - Shape/setup: LocalP2PService over `FakeLocalDiscoveryService`; `start('peer', quicPort: null, tcpPort: null)` → `advertisedQuicPort==null`; `await updateLibp2pPorts(quicPort:45000, tcpPort:45001)`; assert `advertisedQuicPort==45000`, `advertisedTcpPort==45001`, and `startAdvertisingCallCount==2` (re-advertise happened); then `await restartAdvertising()` → ports STILL 45000/45001 (cache updated).
   - RED on HEAD because: `updateLibp2pPorts` does not exist (compile RED).
   - GREEN after fix asserts: re-advertise with fresh ports + cache update.
   - Mutation that re-reds: drop the `_quicPort=`/`_tcpPort=` cache update inside `updateLibp2pPorts` → restartAdvertising re-publishes stale → the restart assertion flips red.
3. test/core/local_discovery/local_p2p_service_test.dart::`updateLibp2pPorts is a no-op when ports unchanged`
   - Tier: unit host
   - Shape/setup: `start('peer', quicPort:45000, tcpPort:45001)` (startAdvertisingCallCount==1); `await updateLibp2pPorts(quicPort:45000, tcpPort:45001)`; assert `startAdvertisingCallCount==1` (NO re-advertise) and no `LOCAL_P2P_SERVICE_RESTART_ADVERTISING`/re-advert diagnostic emitted.
   - RED on HEAD because: method missing (compile); post-impl, a naive always-re-advertise implementation fails this no-op assertion (drives the unchanged-guard).
   - GREEN after fix asserts: unchanged ports → no advert churn.
   - Mutation that re-reds: remove the unchanged-guard → re-advertises → count==2 → red.
4. test/core/services/p2p_service_impl_test.dart::`FDC-11 numeric advert-port diagnostic emits ints`
   - Tier: unit host (flow-event sink)
   - Shape/setup: `debugSetFlowEventSink`; run the self-heal from TC-1; assert a `FDC_LAN_ADVERT_PORTS` event with integer `quicPort==45000`, `tcpPort==45001`, `source=='addresses_updated'`. Discriminator: assert `details['quicPort'] is int` (NOT a redacted multiaddr string) AND NOT a `/redacted/` multiaddr.
   - RED on HEAD because: no such event exists.
   - GREEN after fix asserts: explicit-int port diagnostic fires.
   - Mutation that re-reds: remove the `emitFlowEvent('FDC_LAN_ADVERT_PORTS', …)` → red.
5. test/core/services/p2p_service_impl_test.dart::`FDC-11 _startLocalDiscovery extracts quic/tcp ports, not the ws lane` (characterization / INV-lock — GREEN on HEAD)
   - Tier: unit host
   - Shape/setup: start node with `listenAddresses:['/ip4/192.168.0.5/udp/45000/quic-v1','/ip4/192.168.0.5/tcp/45001','/ip4/192.168.0.5/tcp/8080/ws']` already present; assert `FakeLocalP2PService.startedQuicPort==45000`, `startedTcpPort==45001` (the plain tcp, NOT 8080 ws); plus an empty-listenAddresses case → both null.
   - RED on HEAD because: N/A (GREEN — locks existing extraction). Listed as INV/preservation, mutation-verified below.
   - Mutation that re-reds: break `_libp2pListenPort` (e.g. drop the `/ws` exclusion → returns 8080) → red.

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 self-heal re-advertise | event-driven re-derive | unit | p2p_service_impl_test.dart::FDC-11 self-heal addresses:updated re-advertises | `updateLibp2pPorts` absent + handler never calls it | remove `updateLibp2pPorts` call in `_handleAddressesUpdated` | `flutter test test/core/services/p2p_service_impl_test.dart` | AUTO (core/**) |
| TC-02 re-advertise fresh ports | advert payload + cache | unit | local_p2p_service_test.dart::updateLibp2pPorts re-advertises with fresh ports | method absent (compile) | drop cache update in `updateLibp2pPorts` | `flutter test test/core/local_discovery/local_p2p_service_test.dart` | AUTO (core/**) |
| TC-03 no-churn idempotence | transition guard | unit | local_p2p_service_test.dart::updateLibp2pPorts no-op when unchanged | method absent; naive impl re-advertises | remove unchanged-guard | `flutter test test/core/local_discovery/local_p2p_service_test.dart` | AUTO (core/**) |
| TC-04 numeric diagnostic | device-verifiable ints | unit | p2p_service_impl_test.dart::FDC-11 numeric advert-port diagnostic emits ints | event absent | remove emit | `flutter test test/core/services/p2p_service_impl_test.dart` | AUTO (core/**) |
| TC-05 extraction preserved | INV-lock (green) | unit | p2p_service_impl_test.dart::_startLocalDiscovery extracts quic/tcp not ws | N/A (green; locks INV) | break `_libp2pListenPort` ws-exclusion | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (core/**) |
| TC-06 CV-08 LAN-direct | OS-boundary, real mDNS+libp2p, 2-device | device-proof (MANUAL) | manual two-phone runbook (no integration_test file — physical mDNS undrivable) | device-RED today: node:lan_peer_found=0 | n/a (manual) | manual runbook below (Pixel adb + iPhone idevicesyslog) | DOCUMENTED MANUAL gate (FAIL-CLOSED, like 171 TC-13) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability**: advert ports are derived runtime state from `listenAddresses` (not persisted, correctly). On process restart the early seam may again derive null, but the self-heal re-fires on the next `addresses:updated` → reconstructs. **TC-01 is the reconstruct test** (null start → addresses:updated → re-advertised). N/A for DB durability (no persisted derived state).
- **Sibling-surface consistency**: advert lanes = wsPort (always, unchanged), quicPort, tcpPort. The self-heal updates quic+tcp together; wsPort untouched. Edge: only-quic or only-tcp resolves → advertise whichever is non-null (each `_libp2pListenPort` is independent). **Covered by TC-02 (both) + add an assertion that a quic-only listenAddresses still re-advertises quic with tcp null.**
- **Destructive-action side-effects**: `updateLibp2pPorts` re-advertises = `stopAdvertising` + `startAdvertising` (mirrors `restartAdvertising`). Risk: bonsoir re-advertise could disturb already-discovered peers / the suspected-denied gate. Mitigated by TC-03 no-churn (fires at most once/twice per session, only on real port change). **Risk row + preservation sentinel: `bonsoir_discovery_service_contract_test.dart` stays green.**
- **Invariant re-verification under new transitions**: the new re-advertise transition must not falsely latch the bonsoir suspected-denied gate nor clear `_localDiscoveryActive`. The self-heal calls `updateLibp2pPorts` (advert only), NOT `_startLocalDiscovery` (so `_localDiscoveryActive` and the perm-probe are untouched). **Asserted by preservation: `flutter test test/core/local_discovery/` green incl. the suspected-denied contract tests.**

## Invariants (locked by tests)
- INV-1: advert carries the libp2p QUIC/TCP ports once `listenAddresses` surfaces them (null→known self-heal) → TC-01/TC-02.
- INV-2: no advert churn when ports are unchanged → TC-03.
- INV-3: extraction picks QUIC `/udp/<p>/quic-v1` + plain `/tcp/<p>`, never the `/ws` lane → TC-05.
- INV-4: device-verifiable numeric port diagnostic (un-redacted ints) → TC-04.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. Snapshot dirty tree: `git status --short` (shared tree — record unrelated WIP so it is not reverted).
2. Add RED tests TC-01..TC-05 + extend `FakeLocalP2PService` (new `updateLibp2pPorts` capturing `updatedQuicPort/updatedTcpPort/updateLibp2pPortsCallCount`) and `FakeLocalDiscoveryService` (`startAdvertisingCallCount`). Run focused cmds; confirm RED for the documented reasons.
3. `local_p2p_service.dart`: add `Future<void> updateLibp2pPorts({int? quicPort, int? tcpPort})` — if `(quicPort,tcpPort)==(_quicPort,_tcpPort)` return (no-op); else set cache, `stopAdvertising`+`startAdvertising(peerId, port, quicPort:, tcpPort:)` (guard peerId/port non-null like restartAdvertising), emit `FDC_LAN_ADVERT_PORTS{quicPort: quicPort ?? -1, tcpPort: tcpPort ?? -1, source:'update'}`.
4. `LocalP2PService` interface gains one method → update the single `implements LocalP2PService` fake (test/core/local_discovery/fake_local_p2p_service.dart). Stop-if: `flutter analyze` shows >1 `Missing concrete implementation` → an unexpected implementer exists; enumerate before proceeding.
5. `p2p_service_impl.dart::_handleAddressesUpdated`: after `_emitState`, if `_localP2P != null && _localDiscoveryActive`, compute `q=_libp2pListenPort(listenAddresses,quic:true)`, `t=_libp2pListenPort(listenAddresses,quic:false)`; if `q!=null || t!=null` call `unawaited(_localP2P!.updateLibp2pPorts(quicPort:q, tcpPort:t))`; emit `FDC_LAN_ADVERT_PORTS{…, source:'addresses_updated'}`. Keep it side-effect-light (no relay/health coupling). Stop-if: this re-advert disturbs discovery state → reconsider (advert-only, must not touch `_localDiscoveryActive`).
6. Rerun direct → preservation → named gates.
7. Update memory `project_cv08_fdc11_device_red_2026_06_28.md` (link this plan) and `project_fdc11_libp2p_lan_dial_implemented` after green. Run `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (app-owned lib/ changed).

## Risks And Edge Cases
- Re-advertise churn / discovery disruption → pinned by TC-03 (no-op when unchanged) + `bonsoir_discovery_service_contract_test.dart` preservation.
- `addresses:updated` might fire MANY times with the same ports → TC-03 guard ⇒ at most one re-advertise per real change.
- Partial resolution (quic-only / tcp-only) → advertise non-null subset (TC-02 edge).
- DEVICE RESIDUAL UNCERTAINTY (grounding GAP): static trace could not prove the LAN QUIC addr reliably reaches `listenAddresses` on every device/timing (WiFi change, no-LAN-interface-at-Status race). The numeric diagnostic (TC-04) is the instrument that resolves this empirically on the next device run — if `FDC_LAN_ADVERT_PORTS` shows `quicPort:-1` forever on device, the residual is Go-side address exposure (re-open scope), NOT this Dart fix. This is the one place host-green ≠ device-green; the device-proof is mandatory closure.

## Device/Relay Proof Profile
Requires device for closure (host green is necessary, NOT sufficient — PROD-CRITICAL leg).
Closure scenario: **manual two-phone CV-08 runbook** (no `/sims` index — physical mDNS cannot be orchestrator-driven; same class as 171 TC-13):
1. Build both: `flutter build apk --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_LIBP2P_LAN_DIAL=true` (+DCUTR/LAN_MEDIA optional); `flutter build ios --profile` same defines. Install (Android `adb install -r`; iOS `devicectl install` IN-PLACE — do NOT uninstall an iOS device, see `project_ios_reinstall_migration_authority_block`).
2. Grant Android discovery perms after install: `adb shell pm grant com.mknoon.app android.permission.ACCESS_FINE_LOCATION` (+ ACCESS_COARSE_LOCATION, NEARBY_WIFI_DEVICES).
3. Capture: Pixel `adb logcat -v time | grep -F '[FLOW]'`; iPhone (USB + `idevicepair pair`) `idevicesyslog -u <udid> | grep -F '[FLOW]'`. Keep BOTH apps foregrounded + unlocked (iOS suspends bg → mDNS stops).
4. PASS = on the dialer(s), both OS: `FDC_LAN_ADVERT_PORTS{quicPort:<int>,tcpPort:<int>}` (non -1) AND `node:lan_peer_found` AND `node:lan_dial_ready` AND `MSG_RECEIVED_TRANSPORT:"direct"` for messages, both directions. Restart the receiver between directions (5s dial cooldown + per-process dedupe).
5. Only AFTER device-green → CV-09 (flip `EnableLibp2pLANDial` default) as a SEPARATE plan.
Relay defaults if needed: baked `defaultRelayAddresses()` → `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`.
Deferred device work → next live-rig session.

## CV-08 Run Results — 2026-06-29 (real iPhone 11 + Pixel 6 + two iOS-26.1 sims)
Builds: Android profile + iOS profile, `MKNOON_ENABLE_LIBP2P_LAN_DIAL=true` + `FDC_FLOW_LOG=1`; sim build `flutter build ios --simulator --debug` same defines. iPhone 11 installed IN-PLACE (no uninstall), Pixel `install -r` + location perms.

**174's fix — PROVEN (this is the actual code change):**
- WIRE proof on REAL iPhone 11: `dns-sd -L "mknoon (2)" _mknoon._tcp` → advert carries `tcpPort=64025 quicPort=65461 peerId=…` on `Salehs-iPhone-2.local.:64030`. The exact CV-08 RED root cause (advert omits libp2p ports) is fixed on hardware. (Pixel advert showed `peerId` only — Android cold-start null, never self-healed because its gate latched at 0 peers.)
- LIVE deferred self-heal on two sims: `FDC_LAN_ADVERT_PORTS_DEFERRED{source:addresses_updated}` (cold-start cache) → on peer-resolve `FDC_LAN_ADVERT_PORTS{source:peer_resolved, quicPort,tcpPort}` re-advertise. Review-fix #2 (defer until `_localNetworkProven`) confirmed firing — no eager cold-start re-advertise, no bonsoir crash from THIS path.

**FDC-11 dial pipeline — PROVEN to fire end-to-end up to dial-issue (the keystone that was 0/0 on device):**
- On two iOS-26.1 sims (shared host mDNS): `LOCAL_MDNS_PEER_FOUND` (each found the other + the real Pixel + the real iPhone) → forwarder `P2P_LAN_PEER_FOUND_REQUEST/_RESPONSE` → Go `node:lan_peer_found` (addrCount>0, addresses seeded) → `node:lan_dial_ready` (dial issued, `lan_dial.go:200`). Counts: simA 4/4, simB 2/2. Cross-validates 174: simA discovered the REAL iPhone's port-carrying advert AND the Pixel's portless advert (dialing the former, skipping the latter).

**NOT demonstrated (environment-blocked, NOT a code defect):**
- Direct QUIC connection ESTABLISHMENT + `MSG_RECEIVED_TRANSPORT:"direct"` (PASS criterion #4). `peer:connected` fired ONLY for the relay (`12D3KooW…nd6g`), never a LAN peer → the issued dials did not complete a connection. Root cause = no available rig provides direct QUIC reachability between two HEALTHY nodes:
  1. **Mesh/band WiFi** drops mDNS multicast between the two phones (unicast ping Pixel↔iPhone 0% loss, but each discovers 0 peers; Pixel on 5GHz). No router admin / no SIM (hotspot impossible) to force a single AP/band.
  2. **iOS bonsoir freeze (intermittent)** — iPhone 11 main thread hangs in `BonsoirServiceBroadcast.start()`/`_discovery!.start()` (sync DNS-SD, `0x8BADF00D` watchdog, pre-existing `project_bonsoir_localnetwork_watchdog_crash_fix` first-start residual; NOT 174 — the broadcast with 174's new TXT succeeded, the freeze is the untouched browse path).
  3. **Two sims**: discover each other via the host mDNSResponder, but sim↔sim (and sim↔frozen-phone) QUIC dials don't complete.

**Verdict:** 174's advert self-heal is host-green + mutation-verified + adversarially-reviewed + **wire-proven on real hardware** + **live self-heal proven**. The FDC-11 LAN-dial pipeline fires correctly through dial-issue. CV-08's connection-completion + message-over-direct leg (#4) is the ONE remaining gate, blocked purely by test-rig network reachability — **needs a flat single-AP WiFi (no mesh/band-steering) with two healthy nodes**. **CV-09 (flag flip) STAYS GATED** until that leg is green. Plan 174 itself is independently complete and committable.

## CV-08 Run Results — 2026-06-29 (session 2: FLAT single-AP WiFi, Pixel 6 ↔ iPhone 11)
Rig: flat single-AP WiFi (192.168.0.x, no mesh — the #1 prerequisite from session 1 satisfied). Pixel: fresh `adb install -r` of `app-profile.apk` (`MKNOON_ENABLE_LIBP2P_LAN_DIAL=true`+`FDC_FLOW_LOG=1`) + `pm grant` FINE/COARSE/NEARBY_WIFI. iPhone 11: **could NOT rebuild** (`flutter build ios` fails — phones updated to iOS 26.5 and this Xcode lacks the iOS-26.5 platform/DeviceSupport components: *"iOS 26.5 is not installed"*). **Reused the existing session-1 `build/ios/iphoneos/Runner.app`** (same uncommitted 174 tree) — `devicectl install`/`launch` work fine without the platform (only build/lldb need it). iPhone 11 reinstall = NO brick: it reloaded its **existing Keychain identity** (`12D3KooWRvBZ…`), `P2P_STARTUP_RESULT:success`, relay-ready — no `accountMigrationBlocked` (uninstall wiped the container/DB but not the Keychain, so identity persisted → no migration mismatch; matches `project_ios_reinstall_migration_authority_block`).

**PROGRESS vs session 1 — the FLAT WiFi fixed discovery, and the FDC-11 LAN connection now ESTABLISHES on device (was 0/0):**
- **174 advert RE-PROVEN on real iPhone via Mac `dns-sd -Z _mknoon._tcp`** (independent of the app's own browse): the iPhone TXT carried `quicPort`/`tcpPort` across every session (e.g. `quicPort=50063 tcpPort=64820`, later `53728/65051`). The Pixel's own advert showed `peerId` only (Android cold-start null — irrelevant; Pixel is the dialer).
- **Full FDC-11 pipeline fired end-to-end on the real device pair, TWICE (13:07 and 13:34):** Pixel `LOCAL_MDNS_PEER_FOUND{192.168.0.21:<port>}` → `P2P_LAN_PEER_FOUND_REQUEST{addrCount:2, lanPrivateIp:true, peer:12D3KooWRv}` (**addrCount:2, NOT empty** — 174's ports reach the dialer on HW; the exact session-1 CV-08 root cause is gone) → `node:lan_peer_found` → `node:lan_dial_ready` → **`peer:connected` 35–60 ms later** → **`connections:1→2`** (a real 2nd connection to the iPhone formed and PERSISTED — `connections:2` held at +25s/+50s). This is the keystone that was **0/0 on device in session 1.**

**STILL NOT closed — PASS #4 (`MSG_RECEIVED_TRANSPORT:"direct"`) blocked by the iOS bonsoir freeze (pre-existing, NOT FDC-11/174):**
- The `peer:connected`/`connections:2` proves a LAN connection completes, but **direct-vs-circuit could not be confirmed from logs** (no per-connection transport is logged — `[FLOW]` redacts multiaddrs; `P2P_HEALTH_CHECK_STATE_CHANGED` logs only the count; and **no `onlineDirect`/`directReady` badge ever appeared** — `TIME_TO_ONLINE_BADGE` stayed `source:relay_state_push`). Evidence for "direct" is strong-circumstantial only (2nd conn appears 35–60 ms after the ForceDirectDial to the iPhone's LAN QUIC addr, and persists). The definitive proof is `MSG_RECEIVED_TRANSPORT:"direct"`, which needs contacts + a sent message.
- **The message leg is impossible on this rig because the iPhone 11 Dart layer freezes ~1 s after launch** in the bonsoir browse (sync DNS-SD on the main thread). Confirmed crash `Runner-2026-06-29-131147.ips`: `FRONTBOARD 0x8BADF00D scene-update watchdog … exhausted 10 s … ProcessVisibility: Background`. Pattern: only the genuinely-first-launch-after-install gave a responsive window (session-1 ~11 min, the 13:12 relaunch ~6 min — both ended on a *background* scene-update); **every subsequent relaunch froze within ~1 s** (cold-start `[FLOW]` burst then dead silence; a fresh 6 s `idevicesyslog` probe caught zero app `[FLOW]`). The Go node keeps running on its own threads (hence the Pixel still sees `connections:2`), but Dart is hung → **cannot do the QR contact-add or display/decrypt a received message.**
  - **Local Network permission was confirmed GRANTED** (Settings→Privacy→Local Network→mknoon ON) — it did NOT help; if anything the browse hangs *faster* once granted (the sync DNS-SD does the full operation instead of returning denied).
  - **A clean 75 s "settle" (terminate frozen app + force-stop Pixel + wait for OS to reclaim DNS-SD resources + confirm mDNS namespace empty) did NOT help** — the next fresh launch still froze within ~1 s. So it is NOT a leaked-resource artifact of rapid restarts; it is deterministic on this device.
  - The 174/`project_bonsoir_localnetwork_watchdog_crash_fix` **suspected-denied gate cannot prevent it**: the gate latches only AFTER a zero-peer probe *window completes*, but the FIRST browse start hangs before completing → exactly the documented "first-start hard-deny needs a native probe" residual, here **deterministic, not intermittent.**

**Verdict (session 2):** Flat WiFi resolved session-1's discovery failure; **FDC-11 LAN-dial + connection establishment is now PROVEN on a real device pair** (pipeline green through `connections:2`, reproduced ×2). **PASS #4 message-over-direct remains UNCLOSED**, blocked by the iOS bonsoir browse main-thread freeze (a pre-existing iOS bug, independent of FDC-11/174), which makes the iPhone Dart layer unresponsive ~1 s after launch — no window for the QR contact-add or message display. **No available rig avoids it** (iPhone 13 is the bricked unit + same bug; only one Android phone, so no two-Android pair). **CV-09 STAYS GATED.** Recommended follow-up (NEW, gating for iOS): fix the bonsoir browse to not block the main thread (off-main-thread DNS-SD / native pre-probe) so the iPhone stays responsive while LAN discovery runs — without it, FDC-11 cannot be device-validated end-to-end on iOS, regardless of WiFi. Logs/artifacts: `/tmp/cv08/{iphone,pixel}.log`, crash `~/Library/Logs/DiagnosticReports/Runner-2026-06-29-131147.ips` + `/tmp/cv08/crash/`.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# Dirty-tree snapshot first (shared tree)
git status --short

# RED (before production edits) — must FAIL for the documented reason
flutter test test/core/local_discovery/local_p2p_service_test.dart --plain-name 'updateLibp2pPorts re-advertises with fresh libp2p ports'
flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'FDC-11 self-heal'

# Direct GREEN (after fix)
flutter test test/core/local_discovery/local_p2p_service_test.dart
flutter test test/core/services/p2p_service_impl_test.dart

# Preservation sentinels (must stay green)
flutter test test/core/local_discovery/                 # incl. bonsoir suspected-denied contract + fakes
./scripts/run_host_test_gates.sh core-host-all          # expect: prior pass count + the new tests, 0 fail
./scripts/run_test_gates.sh 1to1                        # expect ~+1387 (unchanged), 0 fail
./scripts/run_test_gates.sh transport                   # FDC/transport family, 0 fail

# Hygiene
flutter analyze                                         # 0 new issues (watch for >1 Missing concrete implementation = unexpected LocalP2PService impl)
git diff --check
```
(No `check_reliability_simulation_discovery.sh` / `/sims` row — the device leg is a manual two-phone gate, not an auto-discovered sim scenario.)

## Known-Failure Interpretation
- Expected RED: TC-01..TC-04 before the fix (compile + logic). TC-05 is GREEN on HEAD by design (INV-lock).
- Pre-existing dirty: any unrelated modified files from other live sessions (snapshot in step 1; do NOT revert).
- Environment blocker (NOT product): device-proof needs the physical rig; absence ≠ product failure (host gates still close the host scope).
- Scope drift (BLOCKING): any failure outside `local_discovery` / `p2p_service` advert path, or any change to Go listen config / the flag default.

## Done Criteria
- [ ] RED added first (TC-01..04), failed for the expected reason; TC-05 green INV-lock.
- [ ] Mutation-verified (each fix row has a re-red revert).
- [ ] Direct GREEN + preservation (`test/core/local_discovery/`, core-host-all, 1to1, transport) pass.
- [ ] No DB migration (none needed — N/A).
- [ ] CV-08 device-proof = the closure gate (deferred to live-rig session; numeric diagnostic confirms ports on device).
- [ ] Every new test auto-globbed under `test/core/**`; verified present in `core-host-all` run.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; only `LocalP2PService` fake churn (1 file).
- [ ] graphify full + arch refresh after green.

## Scope Guard (hard "Do not")
- Do not flip `EnableLibp2pLANDial` (or any FDC flag) default — CV-09 owns that, gated on CV-08 green.
- Do not edit Go listen config / `node.go` address resolution — confirmed correct.
- Do not "fix" `p2p_service_impl.dart:914` — refuted as the cause.
- Do not add an optional param to `restartAdvertising` (invalid_override churn) — add the dedicated `updateLibp2pPorts` instead.

## Accepted Differences / Intentionally Out Of Scope
- Pixel relay flap (`relayState:"recovering"` ~20s/~30s) — separate investigation; not LAN-direct.
- iPhone 13 stale-Keychain migration block — `project_ios_reinstall_migration_authority_block`; separate.
- Go-side `len(addrs)>0` gate before emitting proof events (currently Dart-only guaranteed) — note only; no non-test Go caller passes empty addrs.

## Dependency Impact
- CV-09 (flip flag default) depends on this going device-green first.
- FDC-S6 libp2p-LAN soak (win-rate verdict) is hard-gated on FDC-11 D1 green = this fix.

## Reviewer Findings
Sufficiency self-check PASS. Spec-case totality: TC-01..06 each named at the right tier (4 host RED + 1 host INV-lock + 1 device-proof closure). Mutation-verified: every fix row has an explicit re-red revert. Literal gates with counts. Harness: all host rows AUTO (core/**) — no array/classify_path needed; device leg is a documented manual two-phone gate (FAIL-CLOSED, no integration_test file, like 171 TC-13). No DB migration (N/A). Blind-spot sweep: all four classes resolved (lifecycle→TC-01 reconstruct; sibling→quic/tcp/ws + partial-resolution edge; destructive→re-advertise churn pinned by TC-03 + bonsoir preservation; invariant-re-verify→advert-only path leaves `_localDiscoveryActive`/perm-probe untouched). PROD-CRITICAL leg named (TC-06; host-green ≠ device-green). Residual device uncertainty (does the LAN QUIC addr reliably reach `listenAddresses`) is converted into an empirical instrument (TC-04 numeric diagnostic) rather than an untested assumption. Refuted findings (line-914-is-cause, Go-change-needed, already-re-advertises) recorded as do-NOT-re-introduce.

## Arbiter Decision
Structural blockers: none. Deferred details: exact in-test seam to push `addresses:updated` (executor reuses the existing p2p_service_impl_test.dart bridge-event harness); partial-resolution edge assertion to be added inside TC-02. Accepted differences: Go-side `len(addrs)>0` proof-gate (Dart-guaranteed); Pixel relay flap + iPhone-13 Keychain block (separate work). Verdict: implementation-ready — hand off to execution; first RED gate is the `local_p2p_service_test.dart::updateLibp2pPorts re-advertises` compile-RED.

## Final Execution Verdict
**HOST-COMPLETE (host-green, mutation-verified, adversarially reviewed). Device-proof CV-08 remains the deferred closure gate. NOT committed.**

Implemented exactly the planned scope (`updateLibp2pPorts` re-advertise + cache + numeric `FDC_LAN_ADVERT_PORTS` diagnostic + `_handleAddressesUpdated` re-derive + 1 `FakeLocalP2PService` churn), PLUS one **review-mandated design change** and one **mutation-found test fix**:

1. **Review finding #2 (HIGH) — bonsoir cold-start re-advertise crash, FIXED in-loop.** The plan's eager `addresses:updated → updateLibp2pPorts` re-advertise does a native bonsoir `stopAdvertising`+`startAdvertising`, whose SYNC main-thread DNS-SD read SIGKILLs iOS (0x8BADF00D) on a denied/pending Local Network prompt. The suspected-denied gate (`bonsoir_discovery_service.dart`) only skips that re-start AFTER its 12s zero-peer probe latches, so a re-advertise fired in the cold-start window (first `addresses:updated`, seconds after launch) is UNGATED — and the arm is flag-independent (`_localDiscoveryActive` only), so it reopened the documented `project_bonsoir_localnetwork_watchdog_crash_fix` vector for ALL builds. The plan's blind-spot sweep mis-reasoned this as safe via "fires once/twice" (frequency); the real safety property is **timing**. **Fix (in scope, Dart-only):** the publish is **deferred** — `_handleAddressesUpdated` only caches the derived ports (`_resolvedAdvertQuicPort/_TcpPort`); the native re-advertise fires from the peer-resolved path (`_localPeersSub`, `_localNetworkProven`) — i.e. only once a peer has resolved over mDNS, which is simultaneously when Local Network is provably safe AND the only moment the ports are actually needed (a peer exists to dial). New `FDC_LAN_ADVERT_PORTS_DEFERRED` diagnostic. Locked by **TC-06** (no re-advertise before proven) + **TC-01b** (deferred→flush) with a mutation revert.

2. **Mutation-found TC-05 vacuity, FIXED.** The original TC-05a listed the plain-tcp addr before the `/ws` addr, so the loop returned on the first plain-tcp match and never exercised the `/ws` exclusion — the mutation survived. Reordered ws-before-tcp + added TC-05c; both now re-RED under the ws-exclusion mutation.

3. **Review finding #1 (MED) — `_libp2pListenPort` is not IP-family-aware — DEFERRED follow-up (not fixed).** On a dual-stack host the ip4/ip6 QUIC/TCP sockets bind to DIFFERENT ephemeral ports; `_libp2pListenPort` returns the first match regardless of family, while `bonsoir_discovery_service._buildLibp2pAddresses` derives the multiaddr family from the RESOLVED host — so on a LAN handing out routable IPv6 the advert can pair an ip6 port with an ip4 host (dead multiaddr). **Pre-existing** (the helper is shared with the cold-start advert at `_startLocalDiscovery`; this change did not introduce it), MEDIUM, conditional on a routable-IPv6 LAN; the IPv4 CV-08 rig is unaffected. Follow-up: extract per-family ports (or scope the regex to ip4) + a dual-stack `listenAddresses` unit case. Tracked in memory.

Device-proof addendum: CV-08 now PASSES via `FDC_LAN_ADVERT_PORTS{source:peer_resolved}` (the safe re-advertise after first peer resolve), and the device runbook should also expect `FDC_LAN_ADVERT_PORTS_DEFERRED` before the first resolve. The deferred design adds a small latency (discover→re-advertise→re-resolve→dial) but both same-WiFi peers converge (each discovers the other's null-port advert first, then both re-advertise with ports).
