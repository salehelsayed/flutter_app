# 180 - Android native mDNS resolver — make Pixel resolve iOS `.local` adverts (TDD plan)  (Bug)

Status: awaiting-review
Spec: `Test-Flight-Improv/180-android-nsdmanager-ios-mdns-completion-spec.md` (verified root cause + Device Spike Result).

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-30 | Evidence Collector | spec 180; bonsoir_discovery_service.dart (42-58/116-149/294-367/417-504); p2p_service_impl.dart:474-503; main.dart:1915-1917; local_discovery_service.dart:196-244; GoBridge.kt (EventChannel template); fake_local_discovery_service.dart | root cause verified (AOSP + device spike, 3-lens survived); Option 1 multicast_dns device-FALSIFIED | design the native-resolver composition |
| 2026-06-30 | Planner | + tier-matrix.md, sufficiency-checklist.md, plan-template.md | COMPOSE (no interface change): inject Android-only NativeMdnsResolver into BonsoirDiscoveryService → shared `_commitResolvedPeer`. Native Kotlin = device-proof-only | emit plan |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation (Dart wiring) | | | scoped files only | |
| | implementation (native Kotlin) | | | device-proof only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | device-proof | | (manual two-phone) | TC-180-07/08 | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: `Test-Flight-Improv/180-android-nsdmanager-ios-mdns-completion-spec.md` (root cause + Device Spike Result).
- Gate definitions: scripts/run_test_gates.sh (script wins over prose).
- Numbering / index: Test-Flight-Improv/00-INDEX.md (reuse spec NN=180).
- Device-proof rig: `Test-Flight-Improv/179-cv34-pixel-iphone-lan-media-device-proof-runsheet.md` (same Pixel 6 + iPhone 11 rig).

## Session Classification
implementation-ready (Dart wiring is host-RED→GREEN runnable in-env; the native Kotlin resolver + MulticastLock are device-proof-only — TC-180-07 is the PROD-CRITICAL closure gate).

## Exact Problem Statement
On the Android-discovers-iOS LAN direction, the Pixel's upstream `bonsoir_android`→`NsdManager` intermittently never fires
`onServiceFound` for the iPhone's `_mknoon._tcp` service (Android-12+ `MdnsServiceTypeClient` requires `MdnsResponse.isComplete()`
= SRV + TXT + ≥1 A/AAAA, and the iOS `.local`-hostname SRV target's A-record isn't reliably attached → `serviceBecomesComplete:FALSE`).
The Pixel never resolves the iPhone → zero `LOCAL_MDNS_PEER_FOUND` → Pixel→iPhone 1:1 LAN media falls back to relay-CDN. The device
spike (spec) FALSIFIED the cheap pure-Dart `multicast_dns` fix (Dart `RawDatagramSocket` can't do Android multicast send+receive at once).
The OS-level native mDNS stack DOES work (NsdManager received both services in the spike).

What must improve: the Pixel must obtain a usable NUMERIC address for the iPhone's `_mknoon._tcp` service via a NATIVE resolver
(which controls the multicast socket) and surface it as a `LOCAL_MDNS_PEER_FOUND`, so the existing 179 forward/dial chain lights up.
What must stay unchanged (→ preserved-green sentinels): the working iPhone→Pixel direction; the iOS `bonsoir_darwin` discovery/advertise
path; the iOS-only 175/177/178 watchdog gates + the 179 forward chain; the `LocalDiscoveryService` interface (and its 8 implementers).

## Root Cause (verify → refute confirmed — do NOT re-derive)
SURVIVED a 3-lens adversarial workflow + an on-device spike (spec 180). Locus HIGH confidence (AOSP-grounded); exact transition
sub-mechanism MEDIUM (intermittent — a prior run completed it):
- `bonsoir_android` 5.1.x is the upstream NsdManager wrapper; `onServiceFound` (the sole emitter of `discoveryServiceFound`) only
  fires when `MdnsServiceTypeClient` sees `response.isComplete()` (SRV+TXT+A/AAAA). The iOS `.local` SRV target's A isn't reliably
  attached → `serviceBecomesComplete:FALSE` → never resolved (device: zero `LOCAL_MDNS_PEER_FOUND`, `discoveredPeerCount:0`).
- Asymmetry is resolver-direction-specific (Android's NsdManager is the unreliable resolver), NOT an advert-format difference (BOTH
  sides advertise `.local` hostnames; iOS completes Android's). **Do NOT repeat the advert-format framing.**

Refuted / do-NOT-re-introduce:
- **pure-Dart `multicast_dns` / any Dart `RawDatagramSocket` mDNS** — device-FALSIFIED (3 configs, 0 records: send EPERM / receive-dead;
  Dart can't set `IP_MULTICAST_IF` independent of the bind).
- The "Android numeric vs iOS hostname" advert-format asymmetry; "Android never completes a `.local` advert" (intermittent, not absolute).
- Forking/bumping `bonsoir_android` (same NsdManager gate); changing the iOS advert (Option 4); reverting 175/177/178/179.

## Real Scope
In scope (Android-only, platform-gated):
- A NATIVE (Kotlin) mDNS resolver (`MdnsResolver.kt`): MulticastSocket bound with `IP_MULTICAST_IF`=wlan0, `WifiManager.MulticastLock`
  held, periodic `PTR(_mknoon._tcp.local)→SRV→TXT→A/AAAA`, emitting resolved peers (peerId, numeric host, quic/tcp ports) over an
  EventChannel (mirror `GoBridge.kt`). MethodChannel `mknoon/mdns_resolver` start/stop; EventChannel `mknoon/mdns_resolver/events`.
- A Dart `NativeMdnsResolver` abstraction (+ `PlatformChannelMdnsResolver` impl + `FakeNativeMdnsResolver` for tests) injected into
  `BonsoirDiscoveryService`; on Android, started in `startAdvertising`, stopped in `stopAdvertising`/`dispose`.
- A shared `_commitResolvedPeer(peerId, host, attributes, port)` (extracted from the existing `discoveryServiceResolved` handler) that
  BOTH the bonsoir resolved-event AND the native resolver feed — so native-resolved peers reuse the EXACT `_buildLibp2pAddresses`
  (numeric→/ip4) → `_peers`/`_peersController`/`_pendingResolves` → `_forwardLanPeersToLibp2pDial` → `lan:peer_found` chain + dedup +
  staleness. Runs ALONGSIDE bonsoir (NsdManager is intermittent; dedup collapses overlap).
- Platform gate: the native resolver is NEVER started on iOS. AndroidManifest: add `ACCESS_WIFI_STATE`.
Out of scope (owning work named):
- iOS discovery/advertising/broadcast; the `bonsoir_darwin` fork; the iOS-only 175/177/178 watchdog gates (do NOT revert).
- The 179 portless-TXT forward chain (committed, host-proven) — reused, not modified.
- Forking `bonsoir_android`; pure-Dart `multicast_dns`; Go libp2p native mDNS; the relay fallback.

## Files To Inspect Next
Production:
- `lib/core/local_discovery/bonsoir_discovery_service.dart` — constructor (42-58, add `nativeResolver` param); `discoveryServiceResolved`
  (311-367 → extract `_commitResolvedPeer`); `_buildLibp2pAddresses` (116-149); `startAdvertising`/`stopAdvertising` (151-260/417-450);
  `_pendingResolves` wake (341-342); `_markPeerLost`/staleness (380-399/485-504).
- `lib/core/local_discovery/native_mdns_resolver.dart` (NEW) — abstraction + `NativeResolvedPeer` + `PlatformChannelMdnsResolver`.
- `lib/main.dart:1915-1917` — inject `Platform.isAndroid ? PlatformChannelMdnsResolver() : null`.
- `android/app/src/main/kotlin/com/mknoon/app/MdnsResolver.kt` (NEW) + `MainActivity.kt` configureFlutterEngine wiring; `AndroidManifest.xml`.
Tests:
- `test/core/local_discovery/bonsoir_discovery_native_resolver_test.dart` (NEW); `fake_native_mdns_resolver.dart` (NEW).
Dependency-only: `lib/core/services/p2p_service_impl.dart:474-503` (forward listener — unchanged); `GoBridge.kt` (EventChannel template).

## Existing Tests Covering This Area
- `test/core/local_discovery/bonsoir_discovery_service_contract_test.dart` — bonsoir resolve/advertise/178-gate (exists; no native-resolver path).
- `test/core/local_discovery/bonsoir_discovery_getlocalpeer_eviction_test.dart` — staleness eviction pattern (reuse for TC-180-09).
- `test/core/local_discovery/local_peer_ttl_test.dart`, `local_p2p_service_test.dart`, `fake_local_discovery_service.dart` — exist.
Missing coverage gaps: the entire native-resolver→`_commitResolvedPeer` path; platform-gate; dedup of native vs bonsoir peer; native-peer
resolvePeer-wake + staleness/refresh. Native Kotlin multicast = NO host coverage possible (device-proof only).
Already in curated arrays?: local_discovery tests auto-glob into `core-host-all` (classify_path); none are in `ONE_TO_ONE_TESTS`.

## RED Test Catalog  (add BEFORE production code — INV-RED-FIRST)
Scaffold (behavior-neutral, lands first so the file compiles): the `NativeMdnsResolver` abstraction + `NativeResolvedPeer` + the
`BonsoirDiscoveryService({NativeMdnsResolver? nativeResolver})` param STORED-BUT-NOT-WIRED (never started/subscribed). The
behavior-bearing edit is the start/subscribe/`_commitResolvedPeer` wiring — that is what flips each RED→GREEN.
1. `bonsoir_discovery_native_resolver_test.dart`::`a native-resolved peer (numeric host + ports) becomes a LocalPeer with /ip4 addresses and LOCAL_MDNS_PEER_FOUND`
   - Tier: integration/contract host (factory-faked). Setup: `BonsoirDiscoveryService(nativeResolver: FakeNativeMdnsResolver(), createBroadcast/createDiscovery: fakes)`;
     `startAdvertising`; `fake.emit(NativeResolvedPeer(peerId:'iphone', host:'192.168.0.211', port:1, attributes:{'quicPort':'4001','tcpPort':'4002'}))`.
   - RED on HEAD because: the stored resolver is never subscribed → no `_peers` entry, no `LOCAL_MDNS_PEER_FOUND`.
   - GREEN asserts: `discoveredPeers['iphone']` exists with `host=='192.168.0.211'` and `libp2pAddresses` containing `/ip4/192.168.0.211/udp/4001/quic-v1` + `/ip4/192.168.0.211/tcp/4002`; one `LOCAL_MDNS_PEER_FOUND`.
   - Mutation: revert the native subscribe→`_commitResolvedPeer` wiring → red.
2. `…::`native-resolved peer feeds the SAME forward chain (LocalPeer with /ip4 → discoveredPeersStream emits)`
   - Tier: host. RED on HEAD: no emission. GREEN: `_peersController` emits a map containing 'iphone' with non-empty `libp2pAddresses` (proves the p2p forward listener would fire). Mutation: revert wiring → red.
3. `…::`a native-resolved and a bonsoir-resolved peer for the SAME peerId collapse to ONE entry`
   - Tier: host. Setup: emit the native peer AND drive a bonsoir `discoveryServiceResolved` for the same 'iphone'.
   - RED on HEAD: native path absent (only bonsoir entry). GREEN: `discoveredPeers` has exactly ONE 'iphone'; `_peersController` does not duplicate it. Mutation: revert the shared-`_commitResolvedPeer` dedup → red (two paths / duplicate).
4. `…::`platform gate — the native resolver is NOT started on iOS`
   - Tier: host. Setup: `debugDefaultTargetPlatformOverride = TargetPlatform.iOS`; inject fake; `startAdvertising`.
   - RED on HEAD: (n/a — never started anywhere). GREEN: `fake.startCallCount == 0` on iOS; with `TargetPlatform.android`, `fake.startCallCount == 1`. Mutation: drop the `defaultTargetPlatform==android` guard → iOS starts it (red).
5. `…::`MulticastLock/resolver lifecycle — started on advertise, stopped on stopAdvertising + dispose`
   - Tier: host. RED on HEAD: never started/stopped. GREEN: `startAdvertising`→`fake.startCallCount==1`; `stopAdvertising`→`fake.stopCallCount==1`; a restart (`stop`+`start`) re-subscribes (startCount==2, no leaked subscription). Mutation: revert stop-on-stopAdvertising → red (lock/socket leak proxy).
6. `…::`resolvePeer (discover-on-send) completes from a native-resolved peer`
   - Tier: host. Setup: `final f = service.resolvePeer('iphone', timeout: 2s)`; then `fake.emit(...'iphone'...)`.
   - RED on HEAD: native emission never wakes `_pendingResolves` → resolvePeer times out null. GREEN: `await f` returns the 'iphone' LocalPeer with /ip4 addresses. Mutation: revert the `_pendingResolves` completion in `_commitResolvedPeer` → red.
7. **DEVICE-PROOF (PROD-CRITICAL)** `integration_test`/manual two-phone::`Pixel resolves the iPhone via the native resolver and LAN media completes`
   - Tier: device-proof (manual; the native multicast leg is ONLY provable on device). Build `--dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_LIBP2P_LAN_MEDIA=true`.
   - GREEN asserts: Pixel logs `LOCAL_MDNS_PEER_FOUND` for the iPhone with a NUMERIC host AND `P2P_LAN_MEDIA_SEND_RESPONSE{ok:true}` (proves the Android Go libp2p dial of the numeric `/ip4` LAN multiaddr end-to-end — NOT just discovery). Mutation: n/a (real-device).
8. **DEVICE-PROOF** manual::`no regression — iPhone→Pixel still works`
   - Tier: device-proof. GREEN: iPhone→Pixel `P2P_LAN_MEDIA_SEND_RESPONSE{ok:true}` (the additive Android resolver didn't disturb the working direction).
9. `…::`native-resolved peers use the SAME staleness eviction + refresh as bonsoir peers`
   - Tier: host. Setup: emit a native peer with a back-dated `discoveredAt` (via the resolver event) → `getLocalPeer('iphone')` evicts it (mirrors `bonsoir_discovery_getlocalpeer_eviction_test`); a fresh re-emit re-adds it.
   - RED on HEAD: native path absent. GREEN: stale native peer evicted by the shared `getLocalPeer`; re-emit refreshes `discoveredAt`. Mutation: commit native peers outside the shared `_peers`/staleness → red.

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-180-01 | numeric→/ip4 build (pure) | host | bonsoir_discovery_native_resolver_test.dart::`…/ip4 addresses and LOCAL_MDNS_PEER_FOUND` (asserts the /ip4 build) | native path absent → no /ip4 peer | revert `_buildLibp2pAddresses` numeric branch → red | `flutter test test/core/local_discovery/bonsoir_discovery_native_resolver_test.dart` | AUTO (classify_path:603 local_discovery → core-host-all) |
| TC-180-02 | native→LocalPeer→stream | host | …::`a native-resolved peer … becomes a LocalPeer … LOCAL_MDNS_PEER_FOUND` (#1/#2) | resolver stored-not-subscribed | revert subscribe→`_commitResolvedPeer` wiring | same | AUTO (core-host-all) |
| TC-180-03 | dedup native vs bonsoir | host | …::`… SAME peerId collapse to ONE entry` (#3) | native path absent | revert shared-commit dedup | same | AUTO |
| TC-180-04 | platform gate (iOS off) | host | …::`platform gate — NOT started on iOS` (#4) | guard absent | drop `defaultTargetPlatform==android` guard | same | AUTO |
| TC-180-05 | resolver lifecycle | host | …::`… started on advertise, stopped on stopAdvertising + dispose` (#5) | never started/stopped | revert stop-on-stopAdvertising | same | AUTO |
| TC-180-06 | resolvePeer wake | host | …::`resolvePeer … completes from a native-resolved peer` (#6) | native emit never wakes `_pendingResolves` | revert `_pendingResolves` completion | same | AUTO |
| TC-180-07 | OS-boundary / cross-device / native multicast | **device-proof** | manual two-phone (Pixel+iPhone), post-build | n/a (real device) | n/a | `flutter build apk --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_LIBP2P_LAN_MEDIA=true`; see Device/Relay Proof Profile | MANUAL (no classify_path/`/sims`) |
| TC-180-08 | no-regression (working dir) | device-proof | manual two-phone | n/a | n/a | (same build) | MANUAL |
| TC-180-09 | staleness/refresh parity | host | …::`native peers use the SAME staleness eviction + refresh` (#9) | native path absent | commit native peers outside shared `_peers`/staleness | same | AUTO |

## Blind-Spot Sweep  (row OR justified N/A)
- **Lifecycle / derived-state durability:** the native resolver subscription across stop/start (restartAdvertising) re-subscribes
  without leaking — TC-180-05 (startCount==2 after restart). On process restart the resolver re-starts from `startAdvertising`
  (no persisted derived state). Covered.
- **Sibling-surface consistency:** native-resolved peers must traverse the SAME forward / dedup / staleness / resolvePeer surfaces as
  bonsoir peers — by construction (shared `_commitResolvedPeer` + same `_peers`), locked by TC-180-02/03/06/09.
- **Destructive-action side-effects:** `stopAdvertising`/`dispose` must STOP the native resolver (release the MulticastLock + close the
  socket) — TC-180-05 asserts the stop call (host); the real lock/socket release is part of the device-proof TC-180-07.
- **Invariant re-verification under new transitions:** the native resolver is Android-only → cannot affect the iOS 175/178 watchdog
  gates; TC-180-04 proves it is never started on iOS. It runs ALONGSIDE the bonsoir browse without disturbing it (TC-180-03 dedup +
  TC-180-08 device no-regression).

## Invariants (locked by tests)
- INV-1: a native-resolved peer (numeric host + ports) yields a `LocalPeer` with `/ip4` `libp2pAddresses` + `LOCAL_MDNS_PEER_FOUND` → TC-180-01/02.
- INV-2: native + bonsoir resolves of the same peerId = ONE `_peers` entry (dedup) → TC-180-03.
- INV-3: the native resolver is NEVER started on iOS (platform gate) → TC-180-04.
- INV-4: the native resolver is started on advertise and stopped on stopAdvertising/dispose (no lock/socket leak) → TC-180-05.
- INV-5: native-resolved peers wake `resolvePeer`/discover-on-send and share staleness eviction → TC-180-06/09.
- INV-6 (device, PROD-CRITICAL): the Pixel resolves the iPhone via the native resolver and LAN media completes both ways → TC-180-07/08.
- INV-RED-FIRST + INV-MUTATION-VERIFIED apply to every host row.

## Step-By-Step Implementation Plan
1. Add the SCAFFOLD (behavior-neutral): `lib/core/local_discovery/native_mdns_resolver.dart` (`NativeMdnsResolver` abstract +
   `NativeResolvedPeer` + `PlatformChannelMdnsResolver`), `test/core/local_discovery/fake_native_mdns_resolver.dart`, and the
   `BonsoirDiscoveryService({NativeMdnsResolver? nativeResolver})` param STORED-not-wired. Add the RED tests (#1-6, #9); run focused → confirm RED.
2. Extract `_commitResolvedPeer(peerId, host, attributes, port)` from the `discoveryServiceResolved` case (bonsoir_discovery_service.dart:311-367);
   make the bonsoir handler call it. (Pure refactor — preservation suites must stay green.) Stop-if: any bonsoir contract test flips → the extraction changed behavior, fix before proceeding.
3. Wire the native resolver: in `startAdvertising`, `if (_nativeResolver != null && defaultTargetPlatform == TargetPlatform.android) { _nativeResolver.start(_serviceType); subscribe resolvedPeers → _commitResolvedPeer }`; in `stopAdvertising`/`dispose`, stop + cancel the subscription. → flips #1-6, #9 GREEN.
4. `lib/main.dart:1915-1917`: inject `Platform.isAndroid ? PlatformChannelMdnsResolver() : null` into `BonsoirDiscoveryService`.
5. NATIVE (device-proof only): `android/app/src/main/kotlin/com/mknoon/app/MdnsResolver.kt` (MulticastSocket + `IP_MULTICAST_IF`=wlan0 +
   `MulticastLock` + periodic PTR→SRV→TXT→A parse → EventChannel emit, mirror `GoBridge.kt`); wire in `MainActivity.kt` configureFlutterEngine;
   add `ACCESS_WIFI_STATE` to AndroidManifest. Stop-if: any iOS path or 175/178 behavior changes → out of scope.
6. Rerun direct → preservation → core-host-all. `graphify update .` + `./graphify-arch/refresh_arch_graph.sh`.
7. Device-proof TC-180-07/08 on the Pixel 6 + iPhone 11 rig.

## Risks And Edge Cases
- Native multicast send/receive not working on some OEM → pinned by TC-180-07 (device); the spike already proved the OS native stack receives, and native code controls `IP_MULTICAST_IF` (the Dart limitation that killed Option 1) — but only the device-proof closes it.
- Double-handling native + bonsoir for the same peer → pinned by TC-180-03 dedup + the 179 `_lanDialForwardedPeerIds` forward-dedup.
- Native-peer staleness drift (bonsoir `_refreshTimer` only refreshes bonsoir `_resolvable`) → the native resolver re-queries periodically and re-emits, refreshing via the shared commit; TC-180-09 locks the parity.
- The `_commitResolvedPeer` extraction altering bonsoir behavior → preservation: the full bonsoir contract suite must stay green.

## Device/Relay Proof Profile
requires manual two-phone device for closure (the native Kotlin multicast leg is NOT host-testable).
**PROD-CRITICAL leg:** TC-180-07 (manual two-phone Pixel→iPhone, native resolver build) is the ONLY path that proves the native
multicast resolve + the Android Go libp2p `/ip4` dial end-to-end. Host coverage proves the Dart wiring only — do NOT treat host GREEN
as closure.
Closure scenario: reuse `179-…-device-proof-runsheet.md` rig (Pixel 6 `adb -s 21071FDF600CSC` + iPhone 11 `00008030-001A6D2801BB802E`,
Vodafone-CA38, both apps foreground). Capture on the Pixel: `LOCAL_MDNS_PEER_FOUND{host=<numeric>}` (NOT `serviceBecomesComplete:FALSE`-only),
`P2P_LAN_PEER_FOUND_REQUEST`, `P2P_LAN_MEDIA_SEND_RESPONSE{ok:true}`. Flag stays dart-define only (do not flip defaults).
Deferred device work → none beyond TC-180-07/08.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before the native-subscribe wiring) — must FAIL for the documented reason
flutter test test/core/local_discovery/bonsoir_discovery_native_resolver_test.dart   # #1-6,#9 RED

# Direct GREEN (after the Dart wiring)
flutter test test/core/local_discovery/bonsoir_discovery_native_resolver_test.dart

# Preservation sentinels (must stay green — the _commitResolvedPeer extraction must not change bonsoir behavior)
flutter test test/core/local_discovery/bonsoir_discovery_service_contract_test.dart      # 178 gate + resolve contract
flutter test test/core/local_discovery/bonsoir_discovery_getlocalpeer_eviction_test.dart test/core/local_discovery/local_peer_ttl_test.dart
flutter test test/core/services/p2p_service_lan_forward_test.dart                          # 179 forward chain unaffected
./scripts/run_test_gates.sh core-host-all                                                  # expect: all files PASS

# Hygiene
flutter analyze            # 0 new issues
git diff --check

# Post-land graph refresh (lib/ + android/ changed)
graphify update . && ./graphify-arch/refresh_arch_graph.sh                                 # never with cwd inside graphify-arch/

# Device-proof (manual; not runnable in CI) — the CLOSURE gate
flutter build apk --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_LIBP2P_LAN_MEDIA=true
#   → install on Pixel; iPhone foreground; send Pixel→iPhone media; confirm LOCAL_MDNS_PEER_FOUND{numeric host} + P2P_LAN_MEDIA_SEND_RESPONSE{ok:true}
```

## Known-Failure Interpretation
- Expected RED: #1-6,#9 before the native-subscribe wiring.
- Pre-existing dirty: `info.plist` + `ios/Runner.xcodeproj/project.pbxproj` (unrelated drift — leave; never bundle).
- Environment blocker (NOT product): TC-180-07/08 device-proof not runnable in CI — manual closure.
- Scope drift (BLOCKING): any iOS path / `bonsoir_darwin` / 175-178 / 179 change; any `LocalDiscoveryService` interface-method addition.

## Done Criteria
- [ ] RED added first (#1-6,#9), failed for the documented reason.
- [ ] Mutation-verified (each host fix has a re-red revert).
- [ ] Direct GREEN + preservation sentinels (bonsoir contract, eviction/ttl, 179 forward) + `core-host-all` pass.
- [ ] No DB migration (none — N/A).
- [ ] Device-proof TC-180-07 (PROD-CRITICAL) + TC-180-08 confirm Pixel→iPhone resolves + LAN media both ways.
- [ ] New test auto-globs into core-host-all (no array edit needed); `flutter analyze` 0 new; `git diff --check` clean; graphs refreshed.

## Scope Guard (hard "Do not")
- Do NOT add a method to the `LocalDiscoveryService` interface (breaks ~8 implementers incl. 5 inline `_SharedFakeDiscovery` fakes) — the native resolver is an INTERNAL injected dependency of `BonsoirDiscoveryService`.
- Do NOT re-introduce `multicast_dns` / any pure-Dart `RawDatagramSocket` mDNS (device-FALSIFIED).
- Do NOT touch the iOS `bonsoir_darwin` path, the iOS-only 175/177/178 watchdog gates, or the 179 forward chain.
- Do NOT fork/bump `bonsoir_android`; do NOT change the iOS advert; do NOT flip feature-flag defaults.

## Accepted Differences / Intentionally Out Of Scope
- Native resolver runs ALONGSIDE bonsoir on Android (belt-and-suspenders for the intermittent NsdManager), not as a replacement — accepted (dedup collapses overlap).
- The native Kotlin multicast resolver has NO host coverage — accepted; TC-180-07 is its only proof (the boundary is faked in host tests).

## Dependency Impact
- Closes the Android-discovers-iOS half of CV-34 / FDC-15 / FDC-S6 i→A that 179 could not reach (discovery dies upstream of 179's forward chain). 179 remains the portless-TXT fix for the cases where discovery DOES complete.

## Reviewer Findings
(pending sufficiency review)

## Arbiter Decision
(pending) — Structural blockers: … | Deferred details: native Kotlin device-proof | Accepted differences: as above.

## Final Execution Verdict
Verdict: (pending execution) | Files changed: (planned) 2 prod Dart (`bonsoir_discovery_service.dart`, new `native_mdns_resolver.dart`) +
`main.dart` + 2 native (`MdnsResolver.kt`, `MainActivity.kt`) + `AndroidManifest.xml` + 2 test (new contract + fake) | Tests run: (pending) |
Blocking: (pending) | QA verdict: (pending) | Non-blocking follow-ups (owner): device-proof TC-180-07/08 (manual two-phone).
