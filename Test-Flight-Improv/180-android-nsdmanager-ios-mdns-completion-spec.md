# 180 - Android NsdManager never resolves iOS `.local`-hostname mDNS adverts (Pixel→iPhone LAN discovery wall)  (Bug — Spec)

Status: awaiting-review (spec only — no implementation. Device spike DONE 2026-06-30: Option 1 pure-Dart `multicast_dns`
FALSIFIED on-device → recommended fix is a NATIVE Kotlin mDNS resolver; feeds a `/tdd-plan`.)
Origin: device proof of plan 179 (2026-06-30) surfaced this as a SEPARATE, upstream blocker. Investigation: 8-agent
adversarial workflow (wf_98051b3d-dad, recommended fix survived all 3 verifier lenses). Evidence brief +
raw logs: `<scratchpad>/cv34/android-mdns-completion-evidence.md`, `cv34/pixel_179.log`, `cv34/iphone_179.log`.

## Exact Problem Statement
On the **Android-discovers-iOS** LAN direction, a Pixel (Android, upstream `bonsoir_android` 5.1.6 → `NsdManager`)
**intermittently never receives `onServiceFound`** for an iPhone's `_mknoon._tcp` service. The iPhone advert is healthy and
ported (SRV target `Salehs-iPhone.local`, TXT `quicPort`/`tcpPort` present — the Mac resolves it fine). Android's
Android-12+ `MdnsServiceTypeClient` caches the response (`responseIsComplete:true`) but the dispatch transition never fires
(`serviceBecomesComplete:FALSE`), so the OS callback is never delivered → `bonsoir` never emits `discoveryServiceFound` →
the app never resolves the iPhone → **zero `LOCAL_MDNS_PEER_FOUND`**, the 12s probe raises
`LOCAL_MDNS_SUSPECTED_PERMISSION_DENIED{discoveredPeerCount:0}`, and Pixel→iPhone 1:1 LAN media silently falls back to
relay-CDN.

Reproduced **4×** on Pixel 6 + iPhone 11 (plan-179 build) across WiFi toggles, removing colliding devices, and an iPhone
reboot to a clean hostname. **Important — it is RACE/INTERMITTENT, not absolute:** a prior post-178 run DID complete the
iPhone's `.local` advert (resolved to numeric `192.168.0.211`). So the bug is "Android's NsdManager **unreliably** completes
an iOS `.local`-hostname service," not "never." The exact AOSP sub-mechanism that yields
`newInCache:true + responseIsComplete:true + serviceBecomesComplete:FALSE → no dispatch` is **not fully explained** by the
read AOSP source (MEDIUM confidence on the precise transition logic; HIGH confidence on the locus).

This is a **NEW issue, distinct from plan 179** (which fixed the portless-TXT "resolved-but-empty" forward-chain case and is
committed + host-proven). 179 can't even be exercised on this device pair because discovery dies upstream of its forward chain.

What must improve: Android must obtain a usable (numeric) address for the iPhone's `_mknoon._tcp` service and surface it as a
`LOCAL_MDNS_PEER_FOUND`, so the existing forward/dial chain lights up. What must stay unchanged: the working **iPhone→Pixel**
direction, the iOS `bonsoir_darwin` discovery/advertise path, and the iOS-only 175/177/178 watchdog gates + 179 forward chain.

## Impact
Pixel→iPhone LAN fast-path is **effectively dead on the Android-discovers-iOS combo** — all such 1:1 media and any libp2p
LAN-direct dial degrade to relay, defeating **FDC-15** (1:1 media over libp2p LAN) and **FDC-S6** (libp2p-LAN soak) for half
the device matrix. This is the discovery-side root behind the **CV-34** "LAN media not engaging" class for the Android→iOS
direction (distinct from the 179 portless-TXT cause). **iPhone→Pixel is UNAFFECTED** — so the failure is one-directional and
easy to miss in same-direction testing.

## Investigation Findings (verified)
### Root cause locus (HIGH confidence — AOSP-grounded)
- Android browse = **upstream, un-forked** `bonsoir_android` 5.1.6 (`source: hosted`, pubspec.lock:44-51; only
  `bonsoir_darwin` is the path fork). It is a thin `NsdManager` wrapper: `nsdManager.discoverServices(...)`
  (`BonsoirServiceDiscovery.kt:69`), and it emits `discoveryServiceFound` **solely** from the OS
  `DiscoveryListener.onServiceFound` callback (`kt:108-115`); `nsdManager.resolveService` (`kt:181/231`) is only reachable
  AFTER that callback fires.
- AOSP gate: `MdnsServiceTypeClient` dispatches `onServiceFound` only inside
  `if (response.isComplete()) { if (newServiceFound || serviceBecomesComplete) listener.onServiceFound(...) }`, and
  `MdnsResponse.isComplete()` requires **SRV + TXT + (≥1 A/AAAA)**. For the iPhone's `.local`-hostname advert the
  A/AAAA-for-the-SRV-target is not reliably attached to the Pixel's per-service response, so the transition never fires.
- **Consequence:** the failure is OS-level — *nothing downstream of `onServiceFound` is fixable* (not the app Dart path, not
  `bonsoir`'s `resolveService`, not the `createDiscovery`/`createBroadcast` test seams; all are `NsdManager`-bound). A fix
  must either bypass the `NsdManager` completion gate (client-side SRV→A resolution) or recover the transition.

### Asymmetry — CORRECTED (do NOT repeat the wrong version)
The naive framing "Android advertises a numeric/direct IP so iOS completes it, iOS advertises a hostname so Android can't" is
**false** and must not appear in any downstream plan: `iphone_179.log` shows iOS resolves the **Android** peer to a `.local`
HOSTNAME too (`Android_*.local`) and completes it; the code comment at `bonsoir_discovery_service.dart:120-122` documents the
inverse mapping (iOS→`.local`, Android NsdManager→numeric). **Both sides advertise `.local` hostnames.** The real asymmetry is
**resolver/direction-specific: Android's `NsdManager` unreliably completes the iPhone's service; iOS's resolver completes
Android's.** Not an advert-format difference.

### Reusable downstream chain (healthy, unchanged by any fix)
`discoveryServiceResolved → service.host → _buildLibp2pAddresses(host, attrs) → LocalPeer(libp2pAddresses) →
discoveredPeersStream → p2p_service_impl.dart:474-503 listener → _forwardLanPeersToLibp2pDial → callP2PLanPeerFound
(lan:peer_found)`. Crucially `_buildLibp2pAddresses` (`bonsoir_discovery_service.dart:116-149`) **already** maps a numeric
IPv4 host → `/ip4`, so a resolver that yields a numeric A-record IP feeds it with no new multiaddr logic.

## Current State (data flow with anchors)
- Browse: `bonsoir_android-5.1.6/.../discovery/BonsoirServiceDiscovery.kt:69` (discoverServices) → `:108-115`
  (onServiceFound emits) → `:181/231` (resolveService). OS gate: AOSP `MdnsServiceTypeClient.java` + `MdnsResponse.java`.
- App resolved-path (never reached for the iPhone today): `bonsoir_discovery_service.dart:294` `_handleDiscoveryEvent` →
  `:311-367` discoveryServiceResolved → `_buildLibp2pAddresses` `:116-149` → `LocalPeer` → `_peersController`.
- Forward/dial: `p2p_service_impl.dart:474-503` listener → `_forwardLanPeersToLibp2pDial` (with the 179 self-heal) →
  `callP2PLanPeerFound` (`p2p_bridge_client.dart:611-651`, `lan:peer_found`).
- Impl-selection seam: `main.dart:1915-1917` picks `BonsoirDiscoveryService()` vs `DisabledLocalDiscoveryService()`.
- Interface contract any fix must keep: `local_discovery_service.dart:196-244`.
- Manifest today: `CHANGE_WIFI_MULTICAST_STATE` present; **`ACCESS_WIFI_STATE` and `NEARBY_WIFI_DEVICES` need verifying/adding**
  (a `WifiManager.MulticastLock` requires `ACCESS_WIFI_STATE`).

## Real Scope
In scope:
- Android-only (`defaultTargetPlatform==android`) secondary mDNS resolution that obtains a NUMERIC A/AAAA for the iPhone's
  `_mknoon._tcp` SRV target and surfaces it through the existing `_peers`/`_peersController`/`_pendingResolves`/`_resolvable`
  plumbing so the forward/dedup/staleness/refresh + `resolvePeer`/discover-on-send chains light up unchanged.
- Dedupe so a secondary-resolved peer and a `bonsoir`-resolved peer for the same `peerId` collapse to one entry.
- Platform gate keeping the iOS path and BOTH broadcast directions untouched.
Out of scope (owning work named):
- iOS discovery/advertising/broadcast changes; the `bonsoir_darwin` advert direction.
- plan-179 portless-TXT forward chain incl. `LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR` (committed, host-proven).
- iOS Local-Network watchdog / suspected-denial gate (175/177/178) — iOS-only; **do NOT revert**.
- Go libp2p native mDNS on Android; the relay fallback; iOS multicast entitlement (avoided by the Android-only gate).
- Forking `bonsoir_android` or bumping it (same `NsdManager` gate).

## Test Cases
| ID | Tier | What it asserts |
|---|---|---|
| TC-180-01 | host | `_buildLibp2pAddresses(<numeric IPv4>, {quicPort,tcpPort})` emits `/ip4/…/udp/<quic>/quic-v1` + `/ip4/…/tcp/<tcp>` (regression-lock the numeric→/ip4 branch the resolver depends on). |
| TC-180-02 | host | A fake secondary resolver yielding SRV target `<name>.local` + A `192.168.x.y` + TXT`{quic,tcp,peerId}` produces a `LocalPeer` with NUMERIC host + non-empty `/ip4` `libp2pAddresses`, pushed to `_peersController` → `LOCAL_MDNS_PEER_FOUND`. |
| TC-180-03 | host | Dedupe: a secondary-resolved peer and a `bonsoir`-resolved peer for the SAME `peerId` collapse to ONE `_peers` entry — no duplicate `lan:peer_found`. |
| TC-180-04 | host | Platform gate: on iOS the secondary resolver / multicast socket is NEVER created; 175/178 broadcast-gate behavior unchanged. |
| TC-180-05 | integration | `MulticastLock` (or equivalent) lifecycle: acquired on discovery start, released on stop/dispose (injected lock seam); not held while idle. |
| TC-180-06 | integration | `resolvePeer`/discover-on-send returns a secondary-resolved peer within budget when ONLY the secondary path produced it (proves `_pendingResolves` wakes from the new source). |
| TC-180-07 | **device-proof** | **DECISIVE:** Pixel + iPhone on one WiFi → app logs `LOCAL_MDNS_PEER_FOUND` for the iPhone with a numeric host AND completes `P2P_LAN_MEDIA_SEND_RESPONSE{ok:true}` (proves the Android Go libp2p dial of a numeric `/ip4` LAN multiaddr works end-to-end — NOT just discovery). |
| TC-180-08 | device-proof | No regression: iPhone→Pixel still works (`P2P_LAN_MEDIA_SEND_RESPONSE{ok:true}`), confirming the additive Android resolver didn't disturb the working direction. |

## Fix Direction (UPDATED by the 2026-06-30 device spike — see result below)
~~Option 1 — pure-Dart `multicast_dns` parallel resolver~~ **REJECTED — device-disproven (see Device Spike Result).**
**Recommended fix (post-spike): a NATIVE (Kotlin) mDNS resolver** — a small multicast send/receive socket with
`IP_MULTICAST_IF` set to the WiFi interface (wlan0), doing `PTR(_mknoon._tcp.local)→SRV→TXT→A/AAAA` itself and surfacing the
resolved peer (numeric host + ports) to Dart via a MethodChannel, feeding the EXISTING `_peers`/`_buildLibp2pAddresses`
(numeric→/ip4)/forward chain. This bypasses BOTH the NsdManager completion gate AND the Dart-socket limitation. Android-only,
platform-isolated. Effort L (native code), but it is the only approach proven able to send+receive mDNS on the target device.

### Device Spike Result (2026-06-30 — Pixel 6 + iPhone 11, MKNOON_MDNS_SPIKE build) — Option 1 FALSIFIED
A pure-Dart `multicast_dns` probe with a native `WifiManager.MulticastLock` held (lockHeld:true) was run on the Pixel in 3
socket configurations; ALL received **zero** records (ptrCount/srvCount/aCount = 0):
1. Default (`bind 0.0.0.0:5353`, reusePort:true) → multicast **SEND fails: `SocketException: Operation not permitted (errno 1)`**.
2. reusePort:false + broadcastEnabled + multicastHops:255 (`0.0.0.0`) → **same SEND EPERM**.
3. Bind to the WiFi IP `192.168.0.240` → send succeeds (no EPERM) but **RECEIVE = 0** (unicast bind can't receive multicast).
**Root:** Dart `RawDatagramSocket` cannot set the outgoing multicast interface (`IP_MULTICAST_IF`) independently of the bind
address → it can do multicast send OR receive, never both, on Android. **Native works:** the OS `MdnsDiscoveryManager` was
observed receiving responses from BOTH `_mknoon._tcp` services the entire time, and the Pixel advertises via NsdManager — so
the native mDNS stack sends+receives fine; only the app-level Dart socket is blocked (flutter/flutter#155499, confirmed).
The "cheaper stop/restart-browse" option is also effectively ruled out: discovery restarted 5–6× during the device session
and never completed the iPhone. Logs: `<scratchpad>/cv34/mdns_spike_run{,2,3}.txt`, `build_spike*.log`.

→ The `/tdd-plan` proceeds on the **native Kotlin mDNS resolver**, NOT `multicast_dns`. Manifest prereqs still apply
(`ACCESS_WIFI_STATE` + `CHANGE_WIFI_MULTICAST_STATE`; MulticastLock for receive). The throwaway spike code was reverted.

### Prereqs / open risks the /tdd-plan must carry
- AndroidManifest: add **`ACCESS_WIFI_STATE`** (required for `MulticastLock`); verify `NEARBY_WIFI_DEVICES`.
- `multicast_dns` is **one-shot** (RFC 6762 §5.1) — the resolver must **periodically re-issue** PTR/SRV/A, and the
  `_refreshTimer` staleness path (`bonsoir_discovery_service.dart:246-257`) only re-resolves `bonsoir` `_resolvable` peers, so
  secondary-only peers need their own refresh + a `resolvePeer` active-nudge hook.
- iOS multicast-entitlement safety: the Android gate must wrap **socket creation** (never call `MDnsClient.start()` on iOS).
- Battery: `MulticastLock` is held while discovery is active (continuous), not just send windows — bound it sensibly.
- Re-capture the decisive native evidence (`serviceBecomesComplete:FALSE` + `discoveredPeerCount:0`) to a **saved logcat file**,
  time-correlated with the missing `onServiceFound`, as the plan's RED baseline.

## Known-Failure / Confidence
- Root-cause LOCUS: HIGH (AOSP-grounded). Exact transition sub-mechanism: MEDIUM (intermittent; a prior run completed it).
- Recommended fix: **NATIVE Kotlin mDNS resolver** (Option 1 pure-Dart `multicast_dns` was device-FALSIFIED — see Device Spike
  Result). The native resolver still needs its own device-proof (TC-180-07).
- Refuted / do-NOT-re-introduce: pure-Dart `multicast_dns` (Dart socket can't do Android multicast send+receive); the
  advert-format asymmetry framing; "Android never completes a `.local` advert"; reverting 175/177/178/179; forking `bonsoir_android`.
