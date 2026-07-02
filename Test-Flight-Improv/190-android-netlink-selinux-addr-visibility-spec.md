# 190 - Android netlink SELinux denial: Go node announces 0 local addresses (identify/peer-records/DCUtR starve; 5s error spam)  (Bug — Spec)

Status: awaiting-review (spec only — problem + impact + current state + test cases; no solution design).

Relation to earlier work:
- **174 (FDC-11)** built the symptom-level workaround this spec must PRESERVE: when the address list is empty, the libp2p listen **port** is mined from the bound sockets and paired with the bonsoir/mDNS-supplied IP, so same-WiFi LAN-dial adverts still work. 174 fixed the *advert* lane; it did not (and could not) restore the node's own address visibility.
- **176 (CV-09)** graduated `EnableLibp2pLANDial` default-ON — the LAN-dial path that currently depends entirely on the mDNS advert lane.
- **177** owns LAN address classification; **175/178** own iOS bonsoir behavior — none of that changes here.
- **189** owns the degraded-relay drain starvation + 30s restart loop. The netlink denial is a **co-symptom on the same device, NOT the cause of 189's loop** (adversarially verified there) — circuit-address production is out of scope here.
- Root-cause #4 of the 2026-07-02 Pixel↔iPhone delivery RCA (live-debugged on Pixel 6 / Android 16, build 1.0.0+106).

---

## Problem Statement

On Android, the OS denies the Go runtime's netlink route socket (`SELinux avc: denied { bind } … tclass=netlink_route_socket … bug=b/155595000`, enforced for apps targeting SDK ≥ 30). go-libp2p's basichost cannot enumerate local interface addresses, so:

1. Every 5 seconds (basichost's `addrChangeTickrInterval`), the node logs `ERROR basichost … failed to resolve local interface addresses {"error": "route ip+net: netlinkrib: permission denied"}` — captured live on the Pixel 6 at exactly 5 s cadence, indefinitely, for the life of the process.
2. Interface-address resolution falls back to loopback-only; the app's `AddrsFactory` then filters loopback/link-local, so the node **announces 0 addresses** (`[NODE] Announcing 0 addresses (loopback/link-local filtered out)` — captured live).
3. Because `h.Addrs()` has no LAN entries: **identify** advertises no direct addresses to connected peers; **signed peer records** (rendezvous registration) carry zero addresses; **DCUtR hole-punching** has no local (non-relay-observed) address candidates on the Android side.
4. Inbound same-WiFi dialing works ONLY via the FDC-11 advert lane (mDNS TXT `quicPort`/`tcpPort` + discoverer-supplied IP). Any path that needs the node's own address set — a peer dialing from an identify/peer-record exchange, DCUtR candidate lists, address-based diagnostics — sees an empty set.

This is a **long-standing platform condition, not a regression**: `targetSdk` has been delegated to `flutter.targetSdkVersion` since the initial commit and resolves to 36 with the installed Flutter SDK; the restriction applies at targetSdk ≥ 30 on Android 11+. It affects **every Android install on Android 11+** (all production Android users), on every process, on both WiFi and cellular. The Kotlin side is NOT affected — `NetworkInterface.getNetworkInterfaces()` works in-app (proven by `MdnsResolver.kt`) — the denial is specific to the Go runtime's netlink bind.

Reproduction: install on any Android 11+ device, run the app, `adb logcat | grep -E "netlinkrib|avc.*netlink_route_socket|Announcing"` → the 5 s error spam, the SELinux denials, and `Announcing 0 addresses`.

---

## Impact Analysis

| Concern | Today (with FDC-11 workaround) | Severity |
|---|---|---|
| Same-WiFi LAN-direct dial (bonsoir-discovered) | WORKS — port mined from bound sockets + mDNS IP (174) | mitigated |
| Peer dialing Android node from identify / signed peer record / rendezvous record | BROKEN — record has zero addresses; relay-only | degrades direct-connect rate |
| DCUtR hole-punch local candidates (Android side) | DEGRADED — no self-enumerated addrs; only relay-observed addresses available | fewer punch candidates; lower upgrade odds (188's domain measures this) |
| `node:status` `addresses` field / diagnostics / FLOW events | Empty on Android — misleading during debugging (cost real time in the 2026-07-02 RCA) | observability |
| Log noise | 1 ERROR line / 5 s / process, forever (~17k lines per 24 h foreground) + SELinux audit spam | noise, masks real errors |
| Battery/CPU | One failed netlink syscall cycle per 5 s | negligible |

- Frequency: **always**, all Android ≥ 11 devices, both networks.
- User-visible consequence: indirect — fewer direct connections (more relay dependence) in exactly the scenarios where direct paths should win; and the mDNS advert lane is a **single point of failure** for LAN-direct (if bonsoir fails — see 178's gate hazards — there is no address-based fallback).
- Workaround: none available to users; FDC-11 is the in-code mitigation for the advert lane only.

---

## Current State (verified file:line, 2026-07-02)

### Android build config
| Item | Value | Evidence |
|---|---|---|
| targetSdk | `flutter.targetSdkVersion` → 36 | `android/app/build.gradle.kts:77`; delegated since initial commit (git log -S) |
| compileSdk | `flutter.compileSdkVersion` → 36 | `build.gradle.kts:50` |
| minSdk | 24 | `build.gradle.kts:76` |

### Go side (go-mknoon + module cache)
| Item | Location |
|---|---|
| Listen on `0.0.0.0`/`::` ephemeral ports (quic-v1, tcp, tcp/ws) | `go-mknoon/node/node.go:338-355` |
| `filterAddresses` (drops loopback/link-local/unspecified; keeps `/p2p-circuit`) | `node.go:203-216`, registered as `AddrsFactory` at `:389` |
| "Announcing N addresses" log | `node.go:430-434` |
| `splitHostAddresses` + FDC-11 port-mining fallback + b/155595000 comment | `node.go:1932-1969` (fallback `:1959-1967`) |
| `node:status` `Addresses` from `h.Addrs()` (empty on Android) | `node.go:706-708` |
| `EvtLocalAddressesUpdated` → `addresses:updated` push | `node.go:1918-1927` |
| Signed peer record for rendezvous registration (zero addrs when `h.Addrs()` empty) | `go-mknoon/node/rendezvous.go:54` |
| go-libp2p pin v0.39.1 | `go-mknoon/go.mod:17` |
| Failing enumeration: basichost `updateLocalIpAddr` on 5 s ticker → `manet.InterfaceMultiaddrs` → `net.InterfaceAddrs` → `syscall.NetlinkRIB` (bind denied) → ERROR at `basic_host.go:396`; loopback-only fallback `:395-403`; `go-netroute` (`netroute_linux.go:27`) hits the same denial (Debug-level) | module cache `go-libp2p@v0.39.1` |
| `go-multiaddr v0.14.0` `manet.InterfaceMultiaddrs` = raw `net.InterfaceAddrs` wrapper | `go.mod:20` |
| `github.com/wlynxg/anet v0.0.5` present transitively (via pion/ice, which uses it for exactly this Android restriction); go-libp2p itself never imports it (verified through v0.47) | `go.mod:121` |

### Dart side (advert lane consumers — must keep working)
| Item | Location |
|---|---|
| Port extraction `_libp2pListenPort` (null when list empty) + test seam | `lib/core/services/p2p_service_impl.dart:866-885`, `:887-896` |
| Cold-start advert start with derived ports | `:850-864` |
| `addresses:updated` re-derive + self-heal re-advertise (174) | `:4159-4283` (re-derive `:4280-4281`), `_maybePublishLibp2pAdvertPorts` `:4303-4337` |
| Advert cache + `updateLibp2pPorts` | `lib/core/local_discovery/local_p2p_service.dart:34-62`, `:98-147` |
| TXT `quicPort`/`tcpPort` → peer builds dial multiaddrs | `lib/core/local_discovery/bonsoir_discovery_service.dart:121-159`, `:205-217` |
| Kotlin interface enumeration works (no netlink) | `android/app/src/main/kotlin/com/mknoon/app/MdnsResolver.kt:162-175` |

### Observability anchors
`FDC_LAN_ADVERT_PORTS` / `…_DEFERRED` / `…_DEFERRED_GATED` (`p2p_service_impl.dart:4314-4337`, `local_p2p_service.dart:117-147`), `P2P_LAN_PEER_FOUND_REQUEST/RESPONSE` (`p2p_bridge_client.dart:661`, `:689`), `addresses:updated` payload (`go_bridge_client.dart:683-697`), Go announce log (`node.go:430-434`).

### Existing tests and the gap
- Go: `filterAddresses` filtering (`node_test.go:4254-4272`); `splitHostAddresses` with a fake host (`:4314-4351`) — **neither seeds the empty-`h.Addrs()` denial shape end-to-end**.
- Dart: 174's re-derive/re-advertise TCs (`p2p_service_impl` tests :1425-1472) and `debugLibp2pListenPort` extraction (:194-195).
- **Gaps:** no test anywhere asserts (1) node addresses survive blocked interface enumeration, (2) signed peer records are non-empty on Android, (3) the 5 s error cadence is bounded, (4) DCUtR local-candidate population on Android.

---

## Scope Clarification

| Area | Status |
|---|---|
| Android Go-node local-address visibility (announce/identify/peer-records/status) under netlink denial | **In scope** |
| The 5 s basichost error spam on Android | **In scope** |
| DCUtR local-candidate availability on Android (candidate *presence*, not punch success rates) | **In scope** |
| FDC-11 port-mining advert lane | **Unchanged — regression-guarded** (must keep working, including when addresses are genuinely absent) |
| iOS / macOS address behavior | **Unchanged — regression-guarded** |
| 189's drain starvation / restart loop / circuit addresses | **Out of scope** (spec 189 owns; netlink is a co-symptom, refuted as 189's cause) |
| DCUtR flag graduation / punch-success measurement | **Out of scope** (188 owns) |
| bonsoir/iOS Local Network gates (175/178), LAN classifier (177) | **Out of scope** |
| Relay server | **Out of scope / unchanged** |
| targetSdk changes (lowering targetSdk is not an acceptable direction) | **Out of scope by decision** |

---

## Test Cases

### Group A — Android node address visibility under blocked enumeration
- **TC-190-01** — Go host running where OS-level interface enumeration fails exactly like Android (netlink bind denied / enumeration returns error): the node's announced address set (`Announcing N addresses`, `node:status.addresses`, identify) contains ≥1 real routable LAN address with the correct bound port. Falsifier: 0 announced addresses (today's behavior).
- **TC-190-02** — same fixture: the signed peer record used for rendezvous registration (`rendezvous.go:54`) carries ≥1 address. Falsifier: zero-address record.
- **TC-190-03** — a second node that learns the Android node's addresses via identify/peer-record (NOT via mDNS TXT) can dial it directly on the same network. Falsifier: dial impossible without the bonsoir advert lane.
- **TC-190-04** — interface set changes at runtime (WiFi→cellular, address change): the announced set updates within one address-update cycle; no stale LAN address persists after leaving the network.
- **TC-190-05** — genuinely no usable interface (airplane mode / only loopback): announced set is empty WITHOUT error-spam regression, and the FDC-11 port-mining fallback (`node.go:1959-1967`) still yields the bound port for the advert lane (existing 174 behavior preserved).

### Group B — error-spam bound
- **TC-190-10** — on the denial fixture, the `failed to resolve local interface addresses` ERROR does not repeat unbounded at 5 s: over a 5-minute window the occurrence count is bounded (≤ a handful total, or demoted below error), while address updates keep functioning. Falsifier: ~60 occurrences / 5 min (today).
- **TC-190-11** — the bound does not suppress OTHER basichost errors (only this failure mode is bounded/handled).

### Group C — DCUtR candidates (presence only)
- **TC-190-20** — on the denial fixture with a relay connection, the hole-punch candidate address set offered by the Android side includes its local LAN/WAN-local addresses (not only relay-observed ones). Falsifier: candidates = relay-observed only. (Punch success rates stay 188's domain.)

### Group D — platform regression guards
- **TC-190-30** — iOS/macOS (where enumeration succeeds natively): announced address set byte-equivalent to today's behavior for the same interfaces; no new code path taken. (Host-runnable on macOS: enumeration works there.)
- **TC-190-31** — Android Kotlin lanes untouched: `MdnsResolver.wifiInetAddress()` and the bonsoir TXT advert continue to function identically (174's TC suite stays green, no re-baseline).
- **TC-190-32** — circuit/relay addresses unaffected: `/p2p-circuit` entries pass `filterAddresses` exactly as today (`node.go:206-208`), and 189's fixtures see no behavior change from this work.
- **TC-190-33** — `filterAddresses` still drops loopback/link-local/unspecified from the announced set (no over-broadening: restoring LAN addrs must not leak `127.0.0.1`/`fe80::`/`0.0.0.0` into adverts or identify).

### Group E — device proof (closure)
- **TC-190-40** — Pixel 6 (`21071FDF600CSC`, Android 16, build under test): `adb logcat` over 10 min foreground shows (a) NO recurring `netlinkrib: permission denied` ERROR cadence, (b) `Announcing N addresses` with N ≥ 1 including the device's WiFi IP when on WiFi, (c) `node:status.addresses` non-empty in FLOW logs.
- **TC-190-41** — two-phone same-WiFi (Pixel + iPhone 11 `00008030-001A6D2801BB802E`): with the bonsoir advert lane artificially disabled on the Pixel (or TXT ports stripped), the iPhone can still establish a LAN-direct connection to the Pixel via addresses learned from identify/peer records. Falsifier: relay-only when mDNS is unavailable (today).
- **TC-190-42** — cellular Pixel: no announced-address regression (cellular IP handling per `filterAddresses` policy unchanged), no error spam, node behavior otherwise identical.

---

## Scope guard (non-goals)

- Do NOT weaken or remove the FDC-11 port-mining fallback — it remains the safety net whenever addresses are genuinely absent.
- Do NOT change `filterAddresses` policy (what counts as announceable) beyond making real LAN addresses *available* to it on Android.
- Do NOT touch 189's recovery/drain/circuit logic, the DCUtR flag, bonsoir gates, or the relay server.
- Do NOT lower targetSdk or request privileged Android permissions as a "fix" direction.
- iOS/macOS must be byte-for-byte behavior-neutral.
