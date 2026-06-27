# FDC-11 - libp2p LAN-direct dial fed by bonsoir discovery (unify LAN-direct)  (New Feature)

Status: **implementation-ready (with corrections)** (FDC-S2 resolved 2026-06-27 → Option A, QUIC, 750ms; `<from FDC-S2>` values threaded). Device-proof (D1) remains the closure gate.

> ## 🔎 Review update (2026-06-27, verify→refute grounding)
> A grounding pass (6-agent verify→refute + direct source reads) found the Go-unit tier sound but surfaced
> **three must-fix gaps before this is truly implementation-ready** — all folded in below:
> 1. **The Dart half was missing (CRITICAL).** The libp2p QUIC listen port is **ephemeral** (`node.go:316`
>    `udp/0`) and bonsoir advertises **only `wsPort`** (`bonsoir_discovery_service.dart:75-80`), so the
>    `peer.AddrInfo` the Go handler consumes **cannot materialise** without new Dart advertise+parse+forward
>    wiring. The "bonsoir / `local_discovery_service.dart` untouched" sentinel was **self-contradictory**
>    with FDC-S2's "advertise the QUIC port, NOT wsPort" hard requirement (and roadmap L86). New section
>    **"Discovery → libp2p multiaddr wiring"** + Dart scope/steps/tests (T11–T13) added.
> 2. **The mandated move-feature RED test was never cataloged (CRITICAL).** The blind-spot sweep *requires*
>    a Dart `_allowsAccountNetworkSideEffects('p2p_lan_dial')` lock but it was absent from the RED catalog,
>    matrix, and gates → added as **T11** + matrix row + `flutter test` gate.
> 3. **`preferQuic` ownership (FDC-04 → "FDC-11/12") fell through the cracks** → now explicitly resolved
>    (QUIC-by-multiaddr for LAN; generic `peer:dial` preferQuic deferred to FDC-12).
> Also: **all `node.go` anchors were ~17–53 lines stale** (corrected inline); **`AddressTTL`,
> `bridge_lan.go`, and `WithForceDirectDial` re-confirmed VALID** (three agent "refutations" were false
> positives — see Accepted Differences); **`GOTOOLCHAIN=go1.25.0`** pin added to the Go gates; the
> **default-ON flag** flagged as the lone Phase-3 sibling outlier (recommend OFF-until-D1). The genuinely-new
> Go behaviors are thin: **reuse the existing `DialPeerWithTimeout` connect core** (`node.go:1177`).

Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.5 "Unified LAN-direct over libp2p"; P2-1 table row L358; §8 / §9 Phase 3; open-question #4 L415-416)

> # ✅ RESOLVED by FDC-S2 (Option A, 750ms) — implementation-ready
> FDC-S2 closed **Option A** (direct LAN **QUIC** + identify reliable on v0.39.1; budget **750ms**); the
> `<from FDC-S2>` values are now threaded through the body/RED catalog/matrix below and Status is flipped to
> `implementation-ready`. The Go-unit RED catalog is the host-runnable core; the **real-multicast / iOS-QUIC**
> rows (D1) remain the **device-only closure gate**. Detailed verdict in the banner just below + the RESULTS
> doc (`FDC-S2-quic-identify-handshake-revalidation-RESULTS.md`).

> ## ✅ Resolved by FDC-S2 (executed 2026-06-27) — **Option A, budget 750ms**
> FDC-S2 closed with **Option A**: direct LAN **QUIC** + identify is **reliable** on go-libp2p
> v0.39.1 / quic-go v0.49.0 (M1 QUIC `hang_rate = 0/100`, `p95_identify = 2ms`; M0 relay-QUIC control
> 4ms; M2 cross-version v0.38.2-relay ← v0.39.1-client 137ms). The historical hang did **not**
> reproduce. **Resolve the `<from FDC-S2>` placeholders:**
> - **LAN leg dials QUIC** (`/ip4/<lan>/udp/<quicPort>/quic-v1`), with the **`/tcp/<port>` lane as
>   fallback** (TCP-direct is independently reliable: `0/100`, p95 2ms — P2-3 "TCP==QUIC" lane).
> - **Per-leg dial+identify budget = `750ms`** (`= max(p95 rounded↑250ms, 750ms)`; p95 was 2ms so the
>   750ms floor governs). Fits `interactiveLocalBudget` 1500ms with margin.
> - **Keep `ForceReachabilityPrivate()`** for the LAN dial — FDC-S2's public-vs-private M1 pair was
>   identical (`0/100`, p95 2ms), so private reachability is **not** implicated; no host-config nuance.
> - **HARD REQUIREMENT (FDC-S2 Risks):** advertise the **libp2p QUIC listen port**, NOT `wsPort`.
>   `startAdvertising(peerId, wsPort)` (`local_discovery_service.dart:169`) is the most likely cause of
>   the *original* "hang" (dialing the wrong port). If FDC-11 feeds the wsPort to the libp2p dial, the
>   "hang" recurs as a **config bug**, not a transport bug.
>
> ✅ Values threaded through the RED catalog/matrix and Status flipped to `implementation-ready` (2026-06-27);
> the **device-only** rows (real multicast, iOS-QUIC over real NIC) remain the **M3 / FDC-11 device closure
> gate** FDC-S2 deferred. Harness: `go-mknoon/node/quic_identify_revalidation_test.go`.

---

## Source Of Truth

- **Proposal** §6.5 (L276-286), P2-1 (L358), §9 Phase 3 (L378), §10 "LAN double-delivery"
  (L397-398), §12 `DefaultDialRanker` row (L438) and "WiFi↔cellular closes all-but-QUIC"
  (L466).
- **This epic's roadmap** `FDC-00-roadmap.md` row FDC-11: "Bonsoir discovery feeds
  LAN-discovered peer addresses to the Go host; add `AddrInfo` to peerstore + `host.Connect` → …
  `DefaultDialRanker` races ahead of relay; `IdentifyPush` keeps the LAN addr hot. Keep bonsoir+WS …
  dedup by `messageId`. **Gated by FDC-S2.** Device-only validation (sim shares host bonsoir stack →
  `DISABLE_LOCAL_DISCOVERY` disables both bonsoir and the libp2p LAN dial)." Sequencing:
  `FDC-S2 → FDC-11` (roadmap); Phase 3 device-only.
- **FDC-S2 spike** (sibling doc) — supplies the verdict (Option A/B/C), the **direct-LAN
  identify budget**, and the relay-QUIC control number this plan consumes.
- `scripts/run_test_gates.sh` wins over prose for which tests run in which family (transport
  array L164-169; Go gate is `cd go-mknoon && go test ./...`).

## Session Classification

**implementation-ready** (FDC-S2 = Option A, 2026-06-27). The protocol question is answered by FDC-S2; the
real-world question (iOS QUIC over real WiFi NIC, real multicast discovery) is **device-only** and is the
closure gate (D1). The Go-unit tier below is implementation-ready.

## Exact Problem Statement

**What's missing.** The Go libp2p host runs with **no mDNS service** — `node.go:355-363` lists
`Identity`, `ListenAddrStrings`, `ConnectionManager`, `EnableRelay`, `EnableHolePunching`,
`NATPortMap`, `ForceReachabilityPrivate` (`:347`), `AddrsFactory(filterAddresses)` and **nothing
that discovers same-WiFi libp2p peers**. So two phones on one WiFi are only ever discovered via
**relay rendezvous**, and a same-WiFi peer becomes a **`/p2p-circuit` relay connection** rather
than a LAN-private direct dial. The separate Dart bonsoir+`LocalWsServer` stack carries "same
WiFi → direct" entirely outside libp2p (proposal §2 L67-70, §5 L141-160), so libp2p's connection
manager and the LAN stack **don't share state** — the structural root cause of the perceived
slowness (proposal §2).

**Who feels it.** Two users on one WiFi whose cold-open bonsoir map is empty (proposal §3
L99-102) miss the 1500 ms LAN budget and fall to the relay; once on a relay circuit, libp2p
**never auto-upgrades to direct** (`ForceReachabilityPrivate` makes DCUtR observation-only,
proposal §1 L35, R4 L113). The relay-live circuit is a *limited* pipe (2 min / 128 KB, proposal
§6.2 L222-224) — so even when "online on one LAN," the pair is stuck on the relay path.

**What must improve.** bonsoir discovers same-WiFi peer LAN addresses on **both iOS and Android**;
feed the discovered `AddrInfo` to the libp2p peerstore and `host.Connect` so a same-WiFi peer
becomes a **direct libp2p dial that `DefaultDialRanker` ranks ahead of the relay** (private/LAN
~30 ms vs `RelayDelay` ~500 ms, proposal §6.5 L280-281, §12 L438); `identify`/`IdentifyPush`
keep the LAN address hot; `WithForceDirectDial` upgrades an existing relay conn to direct once a
LAN address is known (the relay→direct upgrade DCUtR cannot deliver under `ForceReachabilityPrivate`,
proposal §6.5 L282-283). Flag the libp2p-direct LAN dial behind `EnableLibp2pLANDial` for safe rollout.

**What must stay unchanged → preserved sentinels.**
- **Relay-first reachability stays `ForceReachabilityPrivate()` in production** (`node.go:347`).
  mDNS adds a *direct LAN lane*; it does **not** flip reachability. PRESERVE: production host opts
  still carry `ForceReachabilityPrivate` (`:347,:362`) and `AutoRelay` (`:366-367`).
- **bonsoir+WS stays as the proven foreground/iOS fast path and fallback** (proposal §5 L159-160,
  §6.5 L283). PRESERVE: the **WS byte path** (`LocalWsServer`) and **`messageId`-dedup** are untouched;
  both LAN legs run; the LAN double is harmless (proposal §10 L397-398). **CORRECTION (review 2026-06-27):**
  `local_discovery_service.dart` / `bonsoir_discovery_service.dart` are **NOT** untouched — they are
  **additively extended** to advertise + parse the libp2p QUIC/TCP listen ports (the `wsPort` advert stays
  for the WS leg). Leaving them untouched is **incompatible** with FDC-S2's "advertise the QUIC port, NOT
  wsPort" hard requirement (the ephemeral `udp/0` port can't be guessed). See "Discovery → libp2p multiaddr
  wiring" + the Dart RED rows T12/T13.
- **`classifyStreamTransport` label contract** (`node.go:129-138`, `isCircuitAddr` `:125`) — a LAN-direct stream must
  still classify as `"direct"` (it is non-circuit), preserving the Dart path-decision contract
  (the decision lives in Dart `sendChatMessage`; Go only labels transport).
- **NET-REL-07** (no relay-wire change for older clients, proposal §1 L38): this is a
  **client-host-only** change — it touches **no relay protocol** and needs **no relay deploy**
  (FDC-S2 Option-A note L123-125). PRESERVE: `go-relay-server/` unmodified.
- **`AddrsFactory filterAddresses` already keeps private LAN ranges** (`node.go:~170-190`, `isCircuitAddr` use `:183`, keeps
  anything not loopback/link-local/unspecified, and always keeps circuit) — do NOT re-touch it;
  it is the precondition that lets a LAN `/ip4/<rfc1918>/…` address be announced.

## Root Cause (verify→refute confirmed)

- **No mDNS service is registered.** Verified by Read of `node.go:355-363` (host opts; `libp2p.New`
  `:378`) — there is **no `mdns.NewMdnsService`** and **no `mdns` import** in `node.go` (`grep -r mdns
  node/` = 0 matches). Confirmed by FDC-S2 background and roadmap R4.
- **Same-WiFi therefore routes via relay rendezvous → circuit conn.** `classifyStreamTransport`
  labels any circuit local/remote multiaddr `"relay"` (`node.go:129-135`); a relay circuit is the
  only path a same-LAN peer gets without mDNS.
- **DCUtR is observation-only** under `ForceReachabilityPrivate()` (`node.go:347`; tracer is
  pure-observation `node.go:341-343` `newNodeHolePunchTracer`, `holepunch_tracer.go:18`), so a relay conn
  **never** auto-upgrades to direct — confirming the need for an explicit `WithForceDirectDial` (v0.39.1
  `core/network/context.go:28`, sig `(ctx, reason string)`) upgrade once a LAN addr is known (proposal §6.5 L282-283).

**Refuted / do-NOT-re-introduce:**
- **Do NOT add idempotency/dedup to the relay store** — store dedup by `messageId` already exists
  (`backend_memory.go:121-142`, `backend_redis.go:272-295`, `inbox_store.go:7,14`); the LAN-double
  guarantee leans on the **receiver's** existing `messageId` dedup, not new server code.
- **Do NOT flip `ForceReachabilityPrivate` → public in production** — the test seam
  `forcePublicReachabilityForTests` (field `node.go:114`, applied `:348`, setter `:1985-1989`) exists for
  protocol-feasibility tests only; production reachability is preserved.
- **Do NOT "race everything"** — proposal §6.2 L202-206: blind fan-out is the v0.28 anti-pattern.
  This plan ranks LAN ahead of relay **by `DefaultDialRanker` priority**, letting the relay leg
  *race but lose*, not by suppressing it.
- **Do NOT feed the `wsPort` into the libp2p dial** — FDC-S2 risk L260-263: `startAdvertising(
  peerId, wsPort)` (`local_discovery_service.dart:169`) advertises the **WebSocket** port; the
  bonsoir-discovered `AddrInfo` handed to `host.Connect` must carry the **libp2p host's own** LAN
  addresses (its QUIC/TCP listen addrs from `host.Addrs()`), **not** the wsPort.

## ⚠ iOS / Android discovery constraint — discovery is bonsoir on BOTH platforms (READ FIRST)

Discovery uses **bonsoir uniformly on BOTH iOS and Android** (bonsoir = Bonjour on iOS / NSD on
Android; both implement the same mDNS/DNS-SD standard and interoperate). go-libp2p's native
`mdns.NewMdnsService` (raw UDP multicast) is **NOT registered on either platform** (proposal §5
L135-160; `native-p2p-go-libp2p/native-p2p-go-libp2p.md` "Why not go-libp2p's built-in mDNS?"):

- **Android:** raw UDP multicast is technically permitted (`CHANGE_WIFI_MULTICAST_STATE`,
  `AndroidManifest.xml:2`), but registering `mdns.NewMdnsService` would be a **redundant second
  discovery mechanism** — bonsoir already discovers the same-WiFi peers and is the proven foreground
  path (proposal §5 L141-160).
- **iOS:** raw UDP multicast needs Apple's `com.apple.developer.networking.multicast` entitlement,
  which the app does **NOT** hold (no multicast key in any `ios/*.entitlements`;
  `ios/Runner/Info.plist:42-50` ships only `NSBonjourServices`/`NSLocalNetworkUsageDescription`). On
  iOS `mdns.NewMdnsService` discovers **nothing** — the reason the app uses **bonsoir** today.

**Flow (UNIFORM on both platforms):** bonsoir discovers the LAN peer → the `lan:peer_found`
event is bridged to Go → `HandleLANPeerFound` adds the discovered `AddrInfo` to the peerstore and
`host.Connect`s it (a libp2p direct dial) → `DefaultDialRanker` ranks the LAN leg ahead of relay.
There is **no discovery platform-split**: a single discovery source (bonsoir) feeds one libp2p dial
path. The libp2p win (a `"direct"` LAN stream the ranker prefers over relay) is identical on both
platforms. The iOS Local-Network permission prompt (`NSLocalNetworkUsageDescription`) and iOS
dropping multicast in the background (→ LAN is foreground-only) remain unchanged caveats, true
regardless of discovery source.

## ⚠ Discovery → libp2p multiaddr wiring — the missing Dart half (READ SECOND, review 2026-06-27)

**The gap.** The Go side (`HandleLANPeerFound(pi peer.AddrInfo)`) assumes a `peer.AddrInfo` carrying the
remote's **libp2p QUIC multiaddr** simply *arrives*. It does not — constructing it is **Dart-side work
this plan must own**:

- The libp2p **QUIC listen port is ephemeral** — `node.go:316` listens on `/ip4/0.0.0.0/udp/0/quic-v1`
  (port `0` = OS-assigned) unless `cfg.ListenPort > 0` (`config.go:157` `// 0 for random`; default build =
  random). So the remote's QUIC port **cannot be guessed**.
- bonsoir today advertises **only the wsPort** (`bonsoir_discovery_service.dart:75-80`
  `BonsoirService(port: wsPort, attributes:{'peerId'})`); the resolved peer carries **`host`(IP) +
  `port`(=wsPort) + `peerId`** (`bonsoir_discovery_service.dart:146-162` → `LocalPeer`). **Nothing carries
  the libp2p QUIC port.**
- FDC-S2's **HARD REQUIREMENT** is "advertise the libp2p QUIC port, **NOT** wsPort" (S2 RESULTS L82-84;
  roadmap L86) — feeding the wsPort to the libp2p dial re-triggers the historical "hang" as a **config bug**.

⇒ **The "bonsoir / `local_discovery_service.dart` untouched" sentinel is FALSE as written.** FDC-11 must
**additively extend** advertise + parse. The WS path and `messageId`-dedup stay; the `wsPort` advert stays
(the WS leg still needs it); but the libp2p QUIC (+TCP) listen ports must be **added** to the bonsoir TXT
and **parsed** back into the `addresses` fed to the dial.

**Required Dart wiring (Option A — recommended; robust to ephemeral ports):**
1. **Learn the local libp2p listen ports.** Dart obtains the host's own LAN listen multiaddrs from Go
   (`host.Addrs()` — `node.go:388`). The `EventCallback` already emits `addresses:updated
   {listenAddresses, circuitAddresses}` (`bridge/events.go`); verify whether `node:start`/`getState`
   already returns `listenAddresses` before adding a getter. Extract the `/udp/<p>/quic-v1` (+ `/tcp/<p>`) ports.
2. **Advertise them.** Extend the bonsoir TXT to carry `quicPort` (+ `tcpPort`) alongside the existing
   `peerId`/`wsPort` (extend `startAdvertising` — `local_discovery_service.dart:165-169` — **additively**;
   do NOT drop `wsPort`).  → **T12**
3. **Parse on discovery.** On `discoveryServiceResolved` (`bonsoir_discovery_service.dart:146`) read the
   remote `quicPort`/`tcpPort` from the TXT and build `/ip4/<host>/udp/<quicPort>/quic-v1` (+ `/tcp/<tcpPort>`
   fallback).  → **T13**
4. **Forward to Go** (see "Dart forwarder" below) as `{peerId, addresses:[quicMa, tcpMa]}`.  → **T1 / T11**

**Option B (lighter, fragile):** pin a fixed `cfg.ListenPort` so the discoverer derives
`/ip4/<resolvedIP>/udp/<fixedPort>/quic-v1` from the resolved IP alone (no TXT change) — but a fixed UDP
port can collide and is not robust; **Option A preferred.** Whichever is chosen, **state it explicitly** —
the current plan silently assumed the multiaddr materialises.

**Dart forwarder (also missing).** `p2p_service_impl.dart:409-420` already subscribes to
`discoveredPeersStream` but **only records metrics** (`_recordLanAvailability`). The new forwarder hooks the
same stream: for each resolved peer (with parsed QUIC/TCP multiaddrs) it **gates on
`_allowsAccountNetworkSideEffects('p2p_lan_dial')`** (`p2p_service_impl.dart:447`) then sends a NEW
`lan:peer_found` bridge command (add to `go_bridge_client.dart` `_CmdSpec` map next to `'peer:dial'` `:116`,
+ a `p2p_bridge_client.dart` send method).

**Reuse the existing dial core — `HandleLANPeerFound` is thin.** `DialPeerWithTimeout` (`node.go:1177-1214`)
already: decodes the peer, parses `addresses`→multiaddrs, builds `peer.AddrInfo`, derives ctx from `n.ctx`
(`context.WithTimeout(n.ctx, …)` — **exactly** the Scope-Guard pattern), and `h.Connect`s. The `peer:dial`
bridge command (`bridge.go:946` `DialPeer` → `n.DialPeerWithTimeout`) already accepts `{peerId, addresses,
timeoutMs}`. So `HandleLANPeerFound`'s genuinely-NEW behaviors are only: **self-skip (T5), per-peer cooldown
(T6), the `WithForceDirectDial` relay→direct upgrade (T7), the explicit long-TTL `AddAddrs` (T4 —
`h.Connect`'s own peerstore-add is `TempAddrTTL`=2min, too short to survive for a later ranked race), and
the `node:lan_dial_ready` event (T1)**. Frame the handler as **wrapping the `DialPeerWithTimeout` connect
core**, not reinventing peer-decode/multiaddr-parse/ctx.

## Real Scope

**In scope**
- **bonsoir discovery feeds the libp2p dial on BOTH iOS and Android** (no libp2p-native
  `mdns.NewMdnsService` registered on either platform): bonsoir's discovered LAN `AddrInfo` is
  bridged to Go → `HandleLANPeerFound` → peerstore + `host.Connect(ctx, pi)`, so both platforms get
  the identical libp2p direct LAN dial via OS-blessed discovery. (Bridge a `lan:peer_found`
  event → the Go `HandleLANPeerFound` handler, or call `dialPeer` with the LAN multiaddr from Dart.)
- A `HandleLANPeerFound(pi peer.AddrInfo)` handler: skip self; **debounced per-peer cooldown** (avoid
  swarm 5s→5m backoff on a flapping/offline LAN peer, proposal §6.1 L188-191, §10 L387-388);
  add `pi.Addrs` to peerstore (`peerstore.AddressTTL` = 1h — survives a failed dial for a later ranked
  race; **NOT** `ConnectedAddrTTL`, which is connection-scoped and cleared on disconnect);
  `host.Connect(ctx, pi)` with the **`750ms` (FDC-S2 Option A) per-leg dial+identify budget** (reuse the
  `DialPeerWithTimeout` connect core, `node.go:1177`). Emit a `node:lan_dial_ready` flow-event.
- `WithForceDirectDial`-based **relay→direct upgrade** when a LAN addr is learned for a peer we
  already hold a relay circuit to (proposal §6.5 L282-283).
- New config constants (warm cooldown, LAN identify budget = `750ms` (FDC-S2)), the feature flag
  (`EnableLibp2pLANDial`), and a `lanDialHandler` field holding the bonsoir-bridge state.
- Keep `classifyStreamTransport` semantics: a LAN dial is `"direct"`.
- **Dart advertise/parse (NEW — see "Discovery → libp2p multiaddr wiring"):** additively advertise the
  libp2p **QUIC (+TCP) listen ports** in the bonsoir TXT and parse the remote's back into the dial
  `addresses`; the `wsPort` advert + WS path stay. Without this the Go handler has no real QUIC multiaddr.
- **Dart forwarder (NEW):** a `discoveredPeersStream` listener in `p2p_service_impl.dart` that gates on
  `_allowsAccountNetworkSideEffects('p2p_lan_dial')` (`:447`) then sends a new `lan:peer_found` bridge
  command; the Go side reuses the existing `DialPeerWithTimeout` connect core (`node.go:1177`).
- **`preferQuic` resolution:** the LAN dial is QUIC-by-multiaddr (so `preferQuic` is moot for LAN); the
  generic `warmPeer`→`peer:dial({preferQuic})` stays Go-inert and its consumption is **deferred to FDC-12**
  (QUIC-first ordering on a non-LAN re-warm). Retarget the `p2p_bridge_client.dart:362` comment to "FDC-12".

**Out of scope → owning FDC-xx**
- DCUtR relay→direct *hole-punch* upgrade across networks + stable peer-identity session layer +
  TCP-direct lane for the punch → **FDC-12** (P2-3). (This plan's `WithForceDirectDial` upgrade is
  *same-LAN, addr-known*; FDC-12 is *cross-NAT, DCUtR-driven*.)
- Cold-start *earlier* mDNS advertise/reserve timing → **FDC-07** (P1-3, gated FDC-S1).
- Dart `warmPeer` / LAN-aware reuse-gating → **FDC-01/02** (P0-1, §6.1).
- Generalized concurrent inbox / ranked race in Dart `sendChatMessage` → **FDC-02/03** (P0-2/3).
- Durable Redis inbox backend → **FDC-10** (P2-2). Relay presence lookup → **FDC-08** (P1-1).

## Files To Inspect Next

**Production entry / host setup**
- `go-mknoon/node/node.go` — **(anchors corrected 2026-06-27; verify by SYMBOL, not line — the file drifts)**
  host opts `:355-363` (`hostOpts := []libp2p.Option{…}`; `libp2p.New` `:378`) — wire the LAN-dial handler +
  `WithForceDirectDial`; reachability `:347` (`reachabilityOpt := libp2p.ForceReachabilityPrivate()`; public
  seam `:349`); listen addrs `:314-332` (`/ip4/0.0.0.0/udp/0/quic-v1` ephemeral); `AddrsFactory filterAddresses`
  `~:170-190` (`isCircuitAddr` use `:183`); event subscribe `:412-415` (conn+addr events only — **does NOT
  subscribe `EvtPeerIdentificationCompleted`**; T3 subscribes in-test); `classifyStreamTransport` `:129`
  (`isCircuitAddr` `:125`); `emitEvent` `:1949`; `Node` struct fields `:39-115` (add cooldown map +
  `lanDialHandler` after the test-seam fields ~`:114`); `Stop` `:508` (tear down the LAN-dial handler).
- **Existing dial core to REUSE** — `DialPeerWithTimeout` (`node.go:1177-1214`: decode peer → parse
  `addresses` → `peer.AddrInfo` → `n.ctx`-derived ctx → `h.Connect`) and its bridge entry `DialPeer`
  (`bridge/bridge.go:946`, command `peer:dial` accepting `{peerId, addresses, timeoutMs}`).
  `HandleLANPeerFound` should WRAP this core; only self-skip/cooldown/`WithForceDirectDial`/long-TTL-`AddAddrs`/
  `lan_dial_ready` are new. `h.Connect`'s own peerstore-add is `TempAddrTTL`(2min) — too short to survive
  for a later ranked race, so T4's explicit `AddAddrs(…, peerstore.AddressTTL)` is load-bearing.
- **NEW** `go-mknoon/node/lan_dial.go` (production) — the bonsoir-bridge handler implementing
  `HandleLANPeerFound`, the per-peer cooldown, the `host.Connect` call, the relay→direct upgrade
  helper.
- `go-mknoon/node/config.go` — add `LANDialWarmCooldown`,
  `LANDirectIdentifyBudget = 750ms` (FDC-S2 Option A); existing `PeerDialTimeout=2s`,
  `InteractiveDialTimeout=4s`, `ListenPort int // 0 for random :157`.
- `go-mknoon/node/feature_flags.go` — add `EnableLibp2pLANDial` to `FeatureFlags` +
  `DefaultFeatureFlags()` (existing flags all default `true`, `:7-42`). **DEFAULT DECISION (review):**
  FDC-S2 = Option A answers *which transport* (QUIC), not *whether to ship default-ON*. Both Phase-3
  siblings keep their new libp2p flags **OFF until device-proven** (FDC-12 `EnableDcutrUpgrade` off;
  FDC-15 `EnableLibp2pLANMedia` off "until FDC-11 ships + is device-proven"). Since FDC-11's own D1 is
  **deferred-not-waived** AND the new advertise/parse wiring is itself unproven (a wrong port re-triggers
  the S2 hang), **recommend default = `false` until D1 GREEN, then flip true** — matching sibling
  discipline. (Counter-argument for default-true: the LAN dial is additive/fail-safe — peers fall back to
  relay. State whichever you choose explicitly.)

**Dart (NEW wiring — this plan owns these; see "Discovery → libp2p multiaddr wiring")**
- `lib/core/local_discovery/bonsoir_discovery_service.dart` — `startAdvertising` `:70-92` (advertises
  `wsPort` + `peerId` TXT today): **additively advertise the libp2p `quicPort`(+`tcpPort`)** (T12); resolve
  handler `:146-162` (builds `LocalPeer{host, port=wsPort}`): **parse the remote `quicPort`/`tcpPort`** and
  build the QUIC/TCP multiaddrs (T13). Test factory seam `:21-25` already exposes a fake `BonsoirBroadcast`.
- `lib/core/local_discovery/local_discovery_service.dart:165-169` — `startAdvertising(peerId, wsPort)`
  abstract: **extend the signature/advert additively** (do NOT drop `wsPort`).
- `lib/core/services/p2p_service_impl.dart` — `discoveredPeersStream` listener `:409-420` (metrics-only
  today): **add the bridge forwarder** gated by `_allowsAccountNetworkSideEffects('p2p_lan_dial')` (`:447`;
  existing labels incl. `'p2p_lan_discovery'` `:738` gate startup ONLY — runtime forward needs its own gate).
- `lib/core/bridge/go_bridge_client.dart:116` — `_CmdSpec` map: **add `'lan:peer_found'`** next to
  `'peer:dial'`; `lib/core/bridge/p2p_bridge_client.dart` — add the send method; `:359-364` `preferQuic`
  comment → "FDC-12".

**Dart (verify untouched — preserved sentinels)**
- `lib/core/debug/e2e_test_mode.dart:2` `kDisableLocalDiscovery` — the iOS-sim guard the device gate
  uses (sim shares a host mDNS stack). NOTE: `DISABLE_LOCAL_DISCOVERY` disables the **bonsoir stack
  entirely** — and bonsoir now feeds **both** the WS path **and** the libp2p LAN dial — so it can
  **not** isolate one LAN leg from the other; use the `EnableLibp2pLANDial` flag for that (see D1).
- `LocalWsServer` (`local_ws_server.dart`) + `messageId`-dedup — WS byte path stays functional + parallel.

**Tests (context / siblings)**
- `go-mknoon/node/node_test.go` — node start/stop + test-host build patterns (`TestNodeStartStop`
  L105, `configureRefreshRelayAddresses` L54). Mirror these to spin **two in-process hosts**.
- `go-mknoon/node/transport_label_test.go` — `classifyStreamTransport` label assertions to
  preserve.
- `go-mknoon/node/holepunch_feasibility_test.go` — pattern for two-host loopback dial + event
  subscription (`EvtPeerIdentificationCompleted`) the RED catalog reuses.
- `go-mknoon/node/feature_flags_runtime_test.go` — flag-gating test pattern.
- Integration (device/transport family): `integration_test/transport_e2e_test.dart`,
  `integration_test/wifi_relay_fallback_smoke_test.dart` (transport gate, `run_test_gates.sh`
  L164-169).

## Existing Tests Covering This Area

- `go-mknoon/node/node_test.go` — **exists**; covers start/stop, relay warm, rendezvous; **does
  NOT** cover the LAN-dial path (none exists). Runs under `cd go-mknoon && go test ./...`.
- `go-mknoon/node/transport_label_test.go` — **exists**; locks `classifyStreamTransport`
  direct-vs-relay; this plan must keep it green (LAN = direct).
- `go-mknoon/node/holepunch_feasibility_test.go` / `holepunch_negative_control_test.go` —
  **exist**; two-host loopback + identify-event harness to mirror.
- `go-mknoon/node/feature_flags_runtime_test.go` — **exists**; flag default + gating pattern.
- `integration_test/transport_e2e_test.dart`, `wifi_relay_fallback_smoke_test.dart`,
  `background_reconnect_test.dart`, `media_stable_id_smoke_test.dart` — **exist**; listed in the
  **transport** array (`run_test_gates.sh` L164-169). The LAN-direct **device** assertion is
  **MISSING** (device-only; see closure gate).
- **MISSING (this plan adds):** `go-mknoon/node/lan_dial_test.go` (Go-unit, T1-T10); **Dart**
  `test/core/services/p2p_service_impl_test.dart` (T11 move-feature gate — extend the existing
  account-migration group `:567-661`, `blockedOperations` `:603-619`) +
  `test/core/local_discovery/bonsoir_discovery_service_test.dart` (T12/T13 advertise/parse); and a device
  smoke scenario (D1).

## RED Test Catalog

> All Go-unit tests below are **host-runnable** and form the implementation-ready core (gated only
> by FDC-S2 picking Option A/B, which fixes the dialed transport + budget). Device rows are the
> **closure gate**, not host-closable. New files: `go-mknoon/node/lan_dial_test.go` (T1-T10, Go), plus the
> **Dart** RED rows **T11-T13** (`test/core/services/p2p_service_impl_test.dart`,
> `test/core/local_discovery/bonsoir_discovery_service_test.dart`) — host-runnable, AUTO-glob (`test/core/**`).
> **Run Go tests under `GOTOOLCHAIN=go1.25.0`** (the QUIC two-host tests T3/T7/T8 panic on Go 1.26.x).

### T1 — bonsoir-found-peer is wired to a libp2p LAN dial when the flag is on (discovery→dial wiring)
- **file::name** `go-mknoon/node/lan_dial_test.go::TestLANPeerFound_DialsWhenFlagEnabled`
- **Tier:** Go unit
- **Shape/setup:** Start a node with `FeatureFlags{EnableLibp2pLANDial:true}` (mirror
  `TestNodeStartStop` L105). Deliver a synthetic `lan:peer_found` `AddrInfo` through the bridge to
  `HandleLANPeerFound`; assert the node holds a non-nil `lanDialHandler` (new struct field), that the
  found peer is dialed (`host.Connect` issued), and that a `node:lan_dial_ready` flow-event is emitted
  (via the test `EventCallback`).
- **RED-on-HEAD-because:** `node.go:355-363` wires no LAN-dial handler — there is no `lanDialHandler`
  field, no `HandleLANPeerFound`, and no `node:lan_dial_ready` event; the seam doesn't exist, so the
  assertion can't compile/pass.
- **GREEN-asserts:** `lanDialHandler` non-nil; a bonsoir-found peer triggers `host.Connect`;
  `node:lan_dial_ready` emitted exactly once.
- **Mutation-that-re-reds:** drop the `host.Connect` in `HandleLANPeerFound` (or unwire the
  bonsoir-bridge event) → never dialed, event never fires → RED.
- **Distinct-event discriminator:** `node:lan_dial_ready` (vs relay `node:startup_timing`).

### T2 — flag OFF ⇒ no libp2p LAN dial (gate preservation / rollout safety)
- **file::name** `…::TestLANPeerFound_NoDial_WhenFlagDisabled`
- **Tier:** Go unit
- **Shape/setup:** Start with `FeatureFlags{EnableLibp2pLANDial:false}`; deliver a `lan:peer_found`
  `AddrInfo` through the bridge.
- **RED-on-HEAD-because:** the flag field doesn't exist yet (won't compile until added); after the
  flag exists but the LAN dial is unconditional it stays RED.
- **GREEN-asserts:** no LAN dial issued (`host.Connect` not called for the found peer); **no**
  `node:lan_dial_ready` event; node still starts and warms relay normally; bonsoir+WS baseline intact.
- **Mutation-that-re-reds:** make the LAN dial unconditional (ignore the flag) → a dial fires
  under flag-off → RED.
- **Discriminator:** absence of `node:lan_dial_ready` + no `host.Connect` for the found peer.

### T3 — HandleLANPeerFound on a same-LAN AddrInfo dials direct and identify completes (headline)
- **file::name** `…::TestHandleLANPeerFound_ConnectsDirect_IdentifyCompletes`
- **Tier:** Go unit (two in-process hosts, loopback LAN — **reuse the FDC-S2 M1 harness**, not the
  relay/tracer-coupled holepunch one)
- **Shape/setup:** Reuse `quic_identify_revalidation_test.go` helpers — `s2BuildHost` (`:58`, mirrors prod
  opts) for both hosts, `s2PickListenAddr` (`:95`) for B's `/udp/0/quic-v1` (+`/tcp/0`), and `s2WaitIdentify`
  (`:120`, subscribes the **test's** `hostA.EventBus()` to `EvtPeerIdentificationCompleted` **before**
  dialing — production `node.go:412-415` does NOT subscribe this event, so the assertion lives in the test,
  not prod). Call A's `HandleLANPeerFound(peer.AddrInfo{ID:Bid, Addrs:[B's QUIC multiaddr]})` (QUIC per
  FDC-S2 Option A; the `/tcp` lane is the fallback).
- **RED-on-HEAD-because:** there is no `HandleLANPeerFound` handler — the symbol doesn't exist.
- **GREEN-asserts:** A↔B connected (`host.Network().Connectedness(Bid)==Connected`);
  `EvtPeerIdentificationCompleted` for Bid arrives ≤ `LANDirectIdentifyBudget` (`750ms`, FDC-S2);
  the resulting conn's `RemoteMultiaddr()` is **non-circuit** (a raw `/ip4/127.0.0.1/…`, asserted
  by `!isCircuitAddr`, since `classifyStreamTransport` can't distinguish QUIC vs TCP — read the raw
  multiaddr per FDC-S2 risk L265-267).
- **Mutation-that-re-reds:** drop the `host.Connect` call in `HandleLANPeerFound` (only add to
  peerstore) → never Connected → RED.
- **Discriminator:** non-circuit `RemoteMultiaddr` distinguishes a LAN-direct win from a relay conn.

### T4 — HandleLANPeerFound adds addrs to the peerstore before dialing (ranker can rank LAN)
- **file::name** `…::TestHandleLANPeerFound_SeedsPeerstore_PrivateAddr`
- **Tier:** Go unit
- **Shape/setup:** Call `HandleLANPeerFound` with a LAN AddrInfo for a peer **not yet dialable**
  (point at a closed port so Connect fails fast). Assert the peerstore retains B's addr afterwards.
- **RED-on-HEAD-because:** no handler adds to the peerstore.
- **GREEN-asserts:** `host.Peerstore().Addrs(Bid)` contains the LAN multiaddr **with a non-transient TTL**
  (`peerstore.AddressTTL`), so a later ranked-race/warm dial can use it even though this Connect failed —
  `h.Connect`'s own add uses `TempAddrTTL` (2min) and is cleared on disconnect, so the explicit `AddAddrs`
  is what makes the seed durable.
- **Mutation-that-re-reds:** add to peerstore with a **zero/`TempAddrTTL`** (or skip `AddAddrs`, relying on
  `h.Connect`'s short-lived add) → addr absent/expired → RED.

### T5 — self-peer is ignored (no self-dial loop)
- **file::name** `…::TestHandleLANPeerFound_IgnoresSelf`
- **Tier:** Go unit
- **Shape/setup:** Call `HandleLANPeerFound` with the node's own `peer.AddrInfo`.
- **RED-on-HEAD-because:** no handler → no self-skip logic.
- **GREEN-asserts:** no Connect attempt, no peerstore mutation, no `node:lan_peer_found` event for
  self.
- **Mutation-that-re-reds:** remove the `pi.ID == host.ID()` early-return → self processed → RED.

### T6 — per-peer warm cooldown debounces repeated finds (swarm-backoff guard)
- **file::name** `…::TestHandleLANPeerFound_DebouncesRepeatedFinds_WithinCooldown`
- **Tier:** Go unit
- **Shape/setup:** Inject a fake clock / counting dial hook. Call `HandleLANPeerFound` twice for the
  same offline peer within `LANDialWarmCooldown`.
- **RED-on-HEAD-because:** no handler, no cooldown map.
- **GREEN-asserts:** exactly **one** dial attempt within the cooldown window; a second find after
  the cooldown elapses dials again.
- **Mutation-that-re-reds:** remove the cooldown check (always dial) → two dials → RED. This locks
  proposal §6.1 L188-191 / §10 L387-388 (offline peer must not tight-loop into 5s→5m backoff).
- **Discriminator:** dial-attempt count via the counting hook.

### T7 — a known LAN addr upgrades an existing relay conn to direct (WithForceDirectDial)
- **file::name** `…::TestHandleLANPeerFound_UpgradesRelayConnToDirect`
- **Tier:** Go unit (two hosts + a loopback "relay-like" circuit OR a pre-seeded relay conn; if a
  full circuit harness is infeasible host-side, assert the **upgrade is attempted with
  `WithForceDirectDial` context** via a dial-option spy — mark this row **device-confirmed**)
- **Shape/setup:** A already holds a (circuit/limited) conn to B; `HandleLANPeerFound` delivers B's
  LAN addr.
- **RED-on-HEAD-because:** no upgrade path exists; relay stays relay (DCUtR inert under
  `ForceReachabilityPrivate`, `node.go:347`).
- **GREEN-asserts:** after `HandleLANPeerFound`, a **non-circuit** conn to B exists (or the dial was
  issued with `network.WithForceDirectDial`), proving the relay→direct upgrade DCUtR can't deliver.
- **Mutation-that-re-reds:** drop `WithForceDirectDial` (plain Connect = no-op when already
  connected via relay) → no direct conn appears → RED.
- **NOTE:** the *real-wire* half of this is **device-only** (a true circuit-v2 relay in the loop);
  host-side proves the **upgrade-attempt seam**. Flagged in the Device/Relay Proof Profile.

### T8 — LAN-direct stream still classifies as "direct" (label contract preserved)
- **file::name** `…::TestLANDirectStream_ClassifiesDirect`
- **Tier:** Go unit
- **Shape/setup:** After T3's direct conn, open a `ChatProtocol` stream A→B and run
  `classifyStreamTransport`.
- **RED-on-HEAD-because:** N/A on HEAD (no LAN dial exists to classify) — this is a **preservation
  lock**; it goes RED only under a mutation that mislabels.
- **GREEN-asserts:** returns `"direct"` (non-circuit), preserving the Dart path-decision contract.
- **Mutation-that-re-reds:** make the handler tag LAN conns as `"relay"` (or route them through a
  circuit addr) → label `"relay"` → RED.

### T9 — Stop tears down the LAN-dial handler (lifecycle durability)
- **file::name** `…::TestStop_TearsDownLANDialHandler`
- **Tier:** Go unit
- **Shape/setup:** Start (flag on) → `Stop()`.
- **RED-on-HEAD-because:** no handler to tear down; field doesn't exist.
- **GREEN-asserts:** the `lanDialHandler` is torn down (spy) and the field nilled, the
  `lanWarmCooldown` map cleared; a subsequent Start re-wires cleanly (no double-wire panic),
  mirroring the Stop/Start hygiene in `node_test.go` reconnect tests.
- **Mutation-that-re-reds:** remove the handler teardown in `Stop` → leak / double-wire on restart → RED.

### T10 — concurrent HandleLANPeerFound for distinct peers issues no racy map write (`-race`)
- **file::name** `…::TestHandleLANPeerFound_ConcurrentDistinctPeers_NoRace`
- **Tier:** Go unit (run under `-race`)
- **Shape/setup:** Start (flag on); fire `HandleLANPeerFound` concurrently (N goroutines + `sync.WaitGroup`) for N **distinct** offline peers, each touching the shared `lanWarmCooldown` map.
- **RED-on-HEAD-because:** no handler/map exists; once added, an **unguarded** `lanWarmCooldown` write trips `go test -race ./node/...` with a DATA RACE.
- **GREEN-asserts:** all finds processed; **no** race report (map guarded by `sync.Mutex`/`sync.Map`); each distinct peer recorded once in the cooldown map.
- **Mutation-that-re-reds:** drop the mutex (raw map write) → `-race` reports a DATA RACE → RED.
- **Discriminator:** the `-race` detector (vs the count-based T6).

### T11 — **(Dart)** LAN peer-found forward is blocked during account migration (move-feature gate lock)
- **file::name** `test/core/services/p2p_service_impl_test.dart::'lan:peer_found forward blocked when account network side-effects paused'`
- **Tier:** Dart unit (host)
- **Shape/setup:** Build `P2PServiceImpl` with a fake bridge + a runtime account-migration gate that
  **blocks** `'p2p_lan_dial'` (mirror the existing blocked-operations group `p2p_service_impl_test.dart:567-661`,
  `blockedOperations` list `:603-619`). Deliver a resolved LAN peer (with QUIC multiaddrs) through the
  `discoveredPeersStream` the forwarder listens to.
- **RED-on-HEAD-because:** the forwarder + the `_allowsAccountNetworkSideEffects('p2p_lan_dial')` gate don't
  exist yet (and `'p2p_lan_dial'` is absent from the gate's known labels), so the assertion can't pass.
- **GREEN-asserts:** with the gate paused, **no** `lan:peer_found` bridge command is sent (fake bridge
  records zero crossings) and **no** dial; with the gate open, exactly one `lan:peer_found` fires.
- **Mutation-that-re-reds:** drop the `_allowsAccountNetworkSideEffects('p2p_lan_dial')` check from the
  forwarder → command sent under migration-paused → RED. Locks the blind-spot-sweep mandate.
- **Harness:** AUTO-glob (`test/core/**`); add `flutter test test/core/services/p2p_service_impl_test.dart` to the gates.

### T12 — **(Dart)** the bonsoir advertisement carries the libp2p QUIC port (not just wsPort)
- **file::name** `test/core/local_discovery/bonsoir_discovery_service_test.dart::'startAdvertising publishes libp2p quicPort in the TXT'`
- **Tier:** Dart unit (host; fake `BonsoirBroadcast` factory seam — `bonsoir_discovery_service.dart:21-25`)
- **Shape/setup:** call `startAdvertising` with a known libp2p QUIC (+TCP) port; capture the constructed
  `BonsoirService` attributes/port.
- **RED-on-HEAD-because:** `startAdvertising` advertises only `wsPort` (`:75-80`), no `quicPort` attribute.
- **GREEN-asserts:** the advertised TXT carries `quicPort` (+`tcpPort`) distinct from `wsPort`.
- **Mutation-that-re-reds:** drop the `quicPort` attribute → absent → RED. (Locks FDC-S2's "advertise the
  QUIC port, NOT wsPort" hard requirement at its source.)
- **Harness:** AUTO-glob (`test/core/**`).

### T13 — **(Dart)** discovery parses the remote's QUIC multiaddr into the dial addresses
- **file::name** `…bonsoir_discovery_service_test.dart::'resolved peer carries libp2p QUIC multiaddr built from TXT'`
- **Tier:** Dart unit (host)
- **Shape/setup:** drive a `discoveryServiceResolved` for a remote advertising `host`+`quicPort`+`tcpPort`;
  inspect the `LocalPeer` / forwarded addresses.
- **RED-on-HEAD-because:** the resolve handler (`:146-162`) builds `LocalPeer{host, port=wsPort}` only — no
  QUIC multiaddr; the forwarder would hand the dial the wrong port (the FDC-S2 hang as a config bug).
- **GREEN-asserts:** the forwarded `addresses` include `/ip4/<host>/udp/<quicPort>/quic-v1`
  (+`/tcp/<tcpPort>`), **never** `/…/<wsPort>/…`.
- **Mutation-that-re-reds:** build the multiaddr from `service.port` (wsPort) instead of the parsed
  `quicPort` → wrong-port addr → RED.
- **Harness:** AUTO-glob (`test/core/**`).

### D1 — **DEVICE-ONLY** two-phone same-WiFi LAN-direct win (closure gate)
- **file::name** device smoke scenario (e.g. `transport_e2e` LAN variant) — **MISSING**, authored
  at FDC-S2-GREEN
- **Tier:** device-proof (two physical phones, one WiFi). Discovery is **bonsoir on both platforms**,
  so `DISABLE_LOCAL_DISCOVERY` can **not** isolate the libp2p-direct leg — it disables the bonsoir feed
  that drives *both* LAN legs (the WS path and the bonsoir-fed libp2p dial). Isolate instead by
  **toggling `EnableLibp2pLANDial`** (bonsoir stays ON in both cases): flag **ON** = bonsoir-fed
  libp2p-direct LAN leg active; flag **OFF** = WS-only baseline. Run both ways on both platforms and
  compare the transport label.
- **Why device-only:** the iOS sim shares the host's mDNS/bonsoir stack (proposal §6.5 L285-286,
  roadmap); real multicast + iOS-QUIC-over-WiFi NIC behavior (UDP path MTU / NAT hairpin / iOS
  UDP throttling, FDC-S2 risk L257-259) is unobservable host-side.
- **Asserts (closure):** with the flag ON, B is discovered by bonsoir within budget; the resulting send
  classifies `"direct"` (non-circuit) and `DefaultDialRanker` chose LAN over the relay leg; with the
  flag OFF the same send falls back to the WS LAN leg; **no duplicate delivered** in either case
  (receiver `messageId` dedup, proposal §10).
- **Closure scenario:** `/sims 1to1 --only <D1>` is **N/A** (sim shares the bonsoir stack) →
  **manual two-phone** run; record `node:lan_peer_found` / `node:lan_dial_ready` / identify /
  transport-label flow-events.

## Test Coverage Matrix

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| bonsoir-found peer dials when flag on | `lanDialHandler` wired + dial + `node:lan_dial_ready` | Go unit | `lan_dial_test.go::TestLANPeerFound_DialsWhenFlagEnabled` | no LAN-dial wiring in `node.go:355-363` | drop `host.Connect` in `HandleLANPeerFound` | `GOTOOLCHAIN=go1.25.0 go test ./...` | Go auto-discovered (`./...`) |
| Flag off ⇒ no LAN dial | gate preserved, baseline start intact | Go unit | `…::TestLANPeerFound_NoDial_WhenFlagDisabled` | flag field absent | make the LAN dial unconditional | `cd go-mknoon && go test ./...` | Go `./...` |
| Found peer dials direct | Connected + identify ≤ budget + non-circuit | Go unit | `…::TestHandleLANPeerFound_ConnectsDirect_IdentifyCompletes` | no `HandleLANPeerFound` symbol | drop `host.Connect` | `cd go-mknoon && go test ./...` | Go `./...` |
| Peerstore seeded | LAN addr retained for ranker | Go unit | `…::TestHandleLANPeerFound_SeedsPeerstore_PrivateAddr` | no handler | zero-TTL / skip `AddAddrs` | `cd go-mknoon && go test ./...` | Go `./...` |
| Self ignored | no self-dial | Go unit | `…::TestHandleLANPeerFound_IgnoresSelf` | no handler | remove self early-return | `cd go-mknoon && go test ./...` | Go `./...` |
| Per-peer cooldown | ≤1 dial within window | Go unit | `…::TestHandleLANPeerFound_DebouncesRepeatedFinds_WithinCooldown` | no cooldown map | remove cooldown check | `cd go-mknoon && go test ./...` | Go `./...` |
| Relay→direct upgrade | non-circuit conn after find (or `WithForceDirectDial` issued) | Go unit + **device** | `…::TestHandleLANPeerFound_UpgradesRelayConnToDirect` | no upgrade path; DCUtR inert | drop `WithForceDirectDial` | `cd go-mknoon && go test ./...` + manual 2-phone | Go `./...`; device manual |
| Label contract | LAN stream = `"direct"` | Go unit | `…::TestLANDirectStream_ClassifiesDirect` | preservation | mislabel LAN as `"relay"` | `cd go-mknoon && go test ./...` | Go `./...` |
| Stop tears down handler | teardown + clean restart | Go unit | `…::TestStop_TearsDownLANDialHandler` | no handler field | remove handler teardown in `Stop` | `cd go-mknoon && go test ./...` | Go `./...` |
| Concurrent finds, no racy map write | guarded `lanWarmCooldown`, no DATA RACE | Go unit (`-race`) | `…::TestHandleLANPeerFound_ConcurrentDistinctPeers_NoRace` | no handler/map; unguarded map races | drop the mutex (raw map write) | `GOTOOLCHAIN=go1.25.0 go test -race ./node/...` | Go `./...` |
| **(Dart)** move-feature gate blocks forward | no `lan:peer_found` under migration-pause | Dart unit | `p2p_service_impl_test.dart::'lan:peer_found forward blocked…'` (T11) | no forwarder/gate; `'p2p_lan_dial'` unknown label | drop the `_allowsAccountNetworkSideEffects('p2p_lan_dial')` check | `flutter test test/core/services/p2p_service_impl_test.dart` | AUTO-glob (`test/core/**`) |
| **(Dart)** advert carries QUIC port | TXT has `quicPort` ≠ `wsPort` | Dart unit | `bonsoir_discovery_service_test.dart::'startAdvertising publishes…quicPort'` (T12) | advert is wsPort-only (`:75-80`) | drop the `quicPort` attribute | `flutter test test/core/local_discovery/` | AUTO-glob (`test/core/**`) |
| **(Dart)** discovery parses remote QUIC ma | forwarded addrs use `quicPort`, not `wsPort` | Dart unit | `bonsoir_discovery_service_test.dart::'resolved peer carries…QUIC multiaddr'` (T13) | resolve builds wsPort `LocalPeer` only (`:146-162`) | build ma from `service.port`(wsPort) | `flutter test test/core/local_discovery/` | AUTO-glob (`test/core/**`) |
| **Two-phone LAN-direct win** | discovered + direct + ranked>relay + no dup | **device-proof** | device smoke (MISSING; author at S2-GREEN) | host can't see real multicast/NIC | n/a (device) | manual 2-phone, toggle `EnableLibp2pLANDial`; transport gate green host-side | transport array (`run_test_gates.sh` L164-169) + `classify_path()` case if a sim variant is added |

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** the LAN-dial handler must be **torn down on `Stop`** and
  **re-wired on Start** (Stop/Start cycle is a known node behavior, `node_test.go` reconnect
  tests) → T9. The per-peer **cooldown map** must be reset/bounded across Stop so it doesn't leak →
  covered by T6 + T9 (assert map cleared on Stop). 
- **Sibling-surface consistency:** bonsoir+WS LAN stack runs **in parallel**; both may deliver →
  **receiver `messageId` dedup** keeps it correct (proposal §10 L397-398) — locked at the device
  row D1 (host fakes can pass via dedup even if the live path never fired — proposal §9 L370
  false-positive risk, so the *live-wins* claim is device-only).
- **Destructive-action side-effects:** none (additive lane); `ForceReachabilityPrivate`, AutoRelay,
  `filterAddresses`, relay wire all **preserved** — T2 + T8 + manual diff guard.
- **Move-feature (account-migration) gate (REQUIRED):** the `lan:peer_found`→Go `HandleLANPeerFound`→
  `host.Connect` path is a NEW wire op the **continuous** bonsoir stream can fire while the node is already
  running, so node-start gating alone does **not** cover an in-progress migration. The Dart-side bridge
  forwarder MUST call `_allowsAccountNetworkSideEffects('p2p_lan_dial')` and drop the event when it returns
  false (mirror `probeRelay`/`warmPeer`; parallels FDC-04/08/09). **Gate-point distinction (review):** the
  existing `'p2p_lan_discovery'` gate (`p2p_service_impl.dart:738`) guards discovery **startup** (fires
  once); bonsoir then emits peer-found events **continuously** for the app lifetime, so a delivered event
  can reach the forward **after** a migration starts — hence a **distinct runtime gate** `'p2p_lan_dial'` at
  the forward point is genuinely additive, **not** redundant. **Lock = T11** (`p2p_service_impl_test.dart`) —
  with the runtime gate paused (`migrationExportingNetworkPaused`/`migratedOut`/fail-closed), a delivered
  `lan:peer_found` event issues **no** bridge crossing and **no** `host.Connect`; mutation = drop the gate
  check ⇒ event forwarded/dialed ⇒ RED.
- **Invariant re-verification under new transitions:** the **NET-REL** transport-label invariant
  (`classifyStreamTransport` direct-vs-relay) is re-verified under the new LAN-direct transition →
  T8. NET-REL-07 (relay-wire unchanged) → no relay file edited (Scope Guard + `git diff --check`).
- **Bridge serialization (proposal §10 L389-392):** the `lan:peer_found` event crosses the
  Dart→Go bridge as a small control message, then the LAN-dial `host.Connect` runs **inside Go**, off
  the single Dart→Go bridge channel, so the dial itself does **not** head-of-line-block the user's send
  on the bridge — justified N/A for a Dart-bridge contention test here (that risk is owned by the Dart
  warm plans FDC-01/05).

## Invariants (locked by tests)

1. The libp2p LAN dial is **flag-gated** (`EnableLibp2pLANDial`) — on⇒wired+dials (T1), off⇒no dial (T2).
2. A found same-LAN peer becomes a **non-circuit direct conn** with completed identify within the
   `750ms` (FDC-S2) budget (T3); its addr is seeded to the peerstore even if the dial fails (T4).
3. **Self is never dialed** (T5); repeated finds are **debounced per-peer** to dodge swarm backoff (T6).
4. A known LAN addr **upgrades a relay conn to direct** via `WithForceDirectDial` (T7; device-confirmed).
5. A LAN-direct stream still classifies **`"direct"`** (T8) — Dart path-decision contract preserved.
6. The LAN-dial handler is **torn down on Stop** and re-wires cleanly (T9).
7. **Production reachability stays `ForceReachabilityPrivate`**, bonsoir+WS untouched, relay wire
   unchanged (T2/T8 + Scope Guard).

## Step-By-Step Implementation Plan

> RED-first. Do not write any production line before its RED test is failing for the real reason.
> **Stop-if:** FDC-S2 has not produced a written verdict — if Option C, **halt and shelve** (this
> plan does not ship). If Option B, set the dialed multiaddr to `/tcp/<port>` and the budget per S2.
> **FDC-S2 = Option A (2026-06-27): proceed — dial QUIC (`/tcp` fallback lane), budget 750ms; neither Stop-if triggers.**

1. **Author the RED catalog** — Go `go-mknoon/node/lan_dial_test.go` (T1-T10) **and** the Dart RED rows
   T11-T13 (`test/core/services/p2p_service_impl_test.dart`,
   `test/core/local_discovery/bonsoir_discovery_service_test.dart`). Confirm each fails for the stated
   reason (missing symbols/fields). Seam names: `Node.lanDialHandler` field, `Node.HandleLANPeerFound`,
   `Node.lanWarmCooldown` map, `EnableLibp2pLANDial` flag, `'lan:peer_found'` bridge command,
   `'p2p_lan_dial'` gate label.
2. **Add the feature flag** — `feature_flags.go`: `EnableLibp2pLANDial` + `DefaultFeatureFlags()`
   default per the DEFAULT DECISION above (**recommend `false` until D1 GREEN**, then flip true). Greens
   T2's compile; T1 still RED.
3. **Add config constants** — `config.go`: `LANDialWarmCooldown`,
   `LANDirectIdentifyBudget = 750ms` (FDC-S2).
4. **Create `lan_dial.go`** — a `lanDialHandler` type wrapping `*Node`; `HandleLANPeerFound(pi)`:
   self-skip (T5) → cooldown check (T6) → `host.Peerstore().AddAddrs(pi.ID, pi.Addrs, ttl)` (T4) →
   context with `LANDirectIdentifyBudget`, `host.Connect` (T3). Emit `node:lan_peer_found`. Greens
   T3/T4/T5/T6.
5. **Wire the Dart half** — (a) **advertise/parse:** extend `startAdvertising`
   (`local_discovery_service.dart:165-169`, `bonsoir_discovery_service.dart:70-92`) to additively publish
   the libp2p `quicPort`(+`tcpPort`) in the TXT, and the resolve handler (`:146-162`) to parse them into
   QUIC/TCP multiaddrs (Greens T12/T13); (b) **forward:** add `'lan:peer_found'` to `go_bridge_client.dart`
   `_CmdSpec` (`:116`) + a `p2p_bridge_client` send method, and hook the `p2p_service_impl.dart`
   `discoveredPeersStream` listener (`:409-420`) to gate (`_allowsAccountNetworkSideEffects('p2p_lan_dial')`)
   + forward the `addresses` (Greens T11); (c) **Go:** the exported `bridge_lan.go` handler resolves
   `singletonNode` and (if `flags.EnableLibp2pLANDial`) calls `HandleLANPeerFound` — wired after `n.host` is
   set (post `libp2p.New` `node.go:378`); store on `n.lanDialHandler`; emit `node:lan_dial_ready` (Greens T1).
6. **Relay→direct upgrade** — in `HandleLANPeerFound`, if already connected via a circuit addr to
   `pi.ID` and a non-circuit LAN addr is now known, dial with `network.WithForceDirectDial(ctx,
   "lan-upgrade")`. Greens T7 (host-seam half).
7. **Tear down on Stop** — `node.go` `Stop` (`:508`): tear down `n.lanDialHandler`; nil the field; clear
   `lanWarmCooldown`. Greens T9.
8. **Preserve the label** — confirm no change to `classifyStreamTransport`; T8 green by virtue of
   the LAN conn being non-circuit.
9. **Mutation pass** — for each test apply its catalogued mutation, confirm RED, revert.
10. **Gates** — `cd go-mknoon && go test ./...`; `flutter analyze`; `git diff --check`; transport
    family host-side. **Device D1** scheduled as the closure gate (manual two-phone).

## Risks And Edge Cases

- **QUIC-identify hang re-appears on a real iOS NIC** (host loopback can't prove it) — pinned by
  **D1 device gate** + FDC-S2's M3; if S2 = Option B, dial TCP instead (config swap only).
- **Offline-peer dial storms → swarm backoff (5s→5m)** — pinned by **T6** cooldown.
- **LAN port-mismatch recurrence** (feeding the wsPort instead of the libp2p LAN port, FDC-S2 risk
  L260-263) — avoided by handing `host.Connect` the libp2p host's own LAN multiaddr (`host.Addrs()`),
  never the wsPort; asserted indirectly by T3 (a real direct conn forms) + the Scope Guard "do not
  feed wsPort".
- **LAN double-delivery** (the bonsoir+WS leg *and* the bonsoir-fed libp2p LAN dial both deliver) —
  pinned by **D1** (no-dup assert; receiver `messageId` dedup, proposal §10). Host fakes can pass via
  dedup even if the live path never fired (proposal §9 L370) → **device-only** truth.
- **Stop/Start handler leak / double-wire panic** — pinned by **T9**.
- **`ForceReachabilityPrivate` interaction** (S2's "reachability-private implicated" escalation,
  spike L227-230) — if S2 flags it, add the host-config nuance as a sub-task before Step 5; T3
  would otherwise stay RED on the private-reachability variant.

## Device/Relay Proof Profile

- **Host-only closure:** T1-T6, T8, T9 fully close host-side (`cd go-mknoon && go test ./...`). T7's
  upgrade **seam** closes host-side; its real-circuit half is device.
- **Requires device:** **D1** — two physical phones, one WiFi. Discovery is **bonsoir on both
  platforms**, so `DISABLE_LOCAL_DISCOVERY` can **not** isolate the libp2p-direct leg — it disables the
  bonsoir feed that drives *both* LAN legs (the WS path and the bonsoir-fed libp2p dial). Isolate
  instead by **toggling `EnableLibp2pLANDial`** (ON = bonsoir-fed libp2p-direct leg; OFF = WS-only
  baseline), bonsoir staying ON in both cases. Also FDC-S2's **M3** real-NIC QUIC identify confirmation.
  **The sim cannot run this at all** (shares the host mDNS/bonsoir stack → forced
  `DISABLE_LOCAL_DISCOVERY`, proposal §6.5 L285-286, roadmap).
- **Closure scenario:** `/sims 1to1 --only <D1>` is **N/A** (sim shares mDNS) → **manual
  two-phone smoke**, capturing `node:lan_peer_found` / `EvtPeerIdentificationCompleted` /
  transport-label events; relay deploy **not required** (client-host-only, NET-REL-07 unaffected).

## Acceptance Gates

```bash
# Go host (the core gate for this plan) — expected: PASS, +10 Go-unit tests (T1-T10), 0 regress.
# GOTOOLCHAIN=go1.25.0 is REQUIRED: the QUIC two-host tests (T3/T7/T8) panic
#   "crypto/tls bug: where's my session ticket?" under Go 1.26.x (quic-go v0.49.0).
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...   # expected: all-pass (~1171 baseline) <from impl>
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && make lint   # expected: clean (vet/lint over node/ + bridge/)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && GOTOOLCHAIN=go1.25.0 go test -race ./node/...   # lanWarmCooldown shared map — expected: PASS, no DATA RACE
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && make verify-bindings   # NEW bridge_lan.go exported fn must bind (gomobile binds the whole `bridge` pkg)

# Relay must be UNTOUCHED (preserved) — expected: PASS, 0 changed
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go test ./...

# Transport family (host-side; the live-LAN row is device-only) — expected: PASS
./scripts/run_test_gates.sh transport   # expected: device/fixture-gated baseline (skips on lone sim) <from run>

# Dart host (NEW — the move-feature gate + advertise/parse rows: T11/T12/T13)
flutter test test/core/services/p2p_service_impl_test.dart test/core/local_discovery/   # expected: PASS, +3 new

# Hygiene
flutter analyze            # expected: 0 new
git diff --check           # expected: clean

# DEVICE CLOSURE (manual, two phones, one WiFi) — NOT host-closable:
#   Both platforms: keep DISABLE_LOCAL_DISCOVERY unset (bonsoir feeds the libp2p LAN dial on both;
#   disabling discovery breaks the path). Isolate the leg by toggling the EnableLibp2pLANDial feature
#   flag: ON = libp2p-direct, OFF = WS-only baseline (see D1). Send one message, assert transport-label
#   "direct" with the flag on + single delivery. (FDC-S2 M3 + D1.)
```

## Known-Failure Interpretation

- A **host-green** run does **NOT** validate LAN-direct in the field — proposal §9 L370: host fakes
  can pass via `messageId` dedup even if the live LAN path never fired. "Host-green" here means the
  **wiring / handler / cooldown / label / lifecycle** logic is correct; the **live-wins** and
  **iOS-QUIC-over-WiFi** claims are **only** closed by D1.
- If T3 is RED **only** on the `ForceReachabilityPrivate` variant but GREEN on public, that is the
  FDC-S2 "reachability-private implicated" escalation (spike L227-230), not a test bug.
- Pre-existing transport-array flakes (if any) are interpreted per the run's baseline, not this plan.

## Done Criteria

- [x] FDC-S2 verdict written (**Option A**) + budget **750ms** consumed (every `<from FDC-S2>` replaced).
- [ ] (If A/B) T1-T9 authored RED-first, GREEN, each mutation re-reds.
- [ ] (If A/B) T10 authored (concurrent-finds `-race` lock); `GOTOOLCHAIN=go1.25.0 go test -race ./node/...` PASS (no DATA RACE on `lanWarmCooldown`) and `cd go-mknoon && make lint` clean.
- [ ] **(NEW) Dart half landed:** advertise/parse the libp2p QUIC(+TCP) ports (T12/T13) + the
      `discoveredPeersStream`→bridge forwarder gated by `_allowsAccountNetworkSideEffects('p2p_lan_dial')`
      (T11); `flutter test test/core/services/p2p_service_impl_test.dart test/core/local_discovery/` PASS.
- [ ] **(NEW) Flag-default decision recorded** (recommend `false` until D1; flip on D1-GREEN) and the
      `p2p_bridge_client.dart:362` `preferQuic` comment retargeted to "FDC-12".
- [ ] **(NEW)** `make verify-bindings` PASS (the exported `bridge_lan.go` handler binds).
- [ ] New exported identifiers carry Go doc comments — `HandleLANPeerFound`, `EnableLibp2pLANDial`, `LANDialWarmCooldown` (each comment begins with the identifier name, per Go convention).
- [ ] `GOTOOLCHAIN=go1.25.0 go test ./...` PASS; `go-relay-server` unchanged + PASS.
- [ ] `./scripts/run_test_gates.sh transport` host-side PASS.
- [ ] `flutter analyze` 0-new; `git diff --check` clean.
- [ ] Production `ForceReachabilityPrivate`, AutoRelay, `filterAddresses`, bonsoir+WS, relay wire
      all unchanged (preserved-sentinel diff review).
- [ ] D1 device smoke scheduled (two-phone, toggle `EnableLibp2pLANDial` ON/OFF) — DEFERRED-not-waived.
- [ ] (If C) plan shelved; bonsoir+WS remains the LAN path; doc marked superseded.

## Scope Guard (hard Do-not)

- **Do NOT** change group pubsub or shared-host connection behavior — `HandleLANPeerFound`→`host.Connect` reaches **group members** on the same WiFi; the new bonsoir-fed libp2p LAN dial is **additive only** (`messageId` dedup) and must leave `pubsub_delivery_test.go` and group connection counts unchanged (**group-safety floor:** `cd go-mknoon && go test ./...` green).
- Do **NOT** flip `ForceReachabilityPrivate` in production (test seam only — field `node.go:114`, applied `:348`).
- Do **NOT** edit `go-relay-server/` (NET-REL-07; no relay deploy).
- Do **NOT** add store dedup/idempotency — it already exists (`backend_memory.go:121-142`,
  `backend_redis.go:272-295`, `inbox_store.go:7,14`).
- Do **NOT** remove the WS byte path or `messageId`-dedup (`LocalWsServer`); the `wsPort` advert STAYS.
  **DO** additively extend `startAdvertising` + the resolve parse to carry/read the libp2p QUIC(+TCP)
  ports (see "Discovery → libp2p multiaddr wiring") — `local_discovery_service.dart`/`bonsoir_*` are
  **extended, not untouched** (the original "untouched" claim was wrong).
- Do **NOT** feed the **wsPort** into the libp2p LAN dial — the discovered `addresses` must be built from
  the remote's advertised **libp2p QUIC/TCP port** (T13), never `service.port`(=wsPort). Feeding wsPort
  re-triggers the FDC-S2 "hang" as a config bug.
- **DO** reuse the existing connect core `DialPeerWithTimeout` (`node.go:1177`) / `peer:dial` bridge
  command (`bridge.go:946`) for the dial itself; `HandleLANPeerFound` only ADDS self-skip/cooldown/
  `WithForceDirectDial`/long-TTL-`AddAddrs`/`lan_dial_ready`. Do not reinvent peer-decode/multiaddr-parse/ctx.
- **`preferQuic` (FDC-04 → "FDC-11/12"):** the LAN dial is QUIC-by-multiaddr, so `preferQuic` is **moot for
  the LAN path**. The generic `warmPeer`→`peer:dial({preferQuic})` stays Go-inert; its consumption
  (QUIC-first ordering on a non-LAN re-warm) is **deferred to FDC-12**. Retarget the
  `p2p_bridge_client.dart:362` comment to "FDC-12".
- **DO** guard `lanWarmCooldown` with a `sync.Mutex` (or use a `sync.Map`) — the bonsoir bridge fires `HandleLANPeerFound` from a goroutine off the bridge channel while node lifecycle runs, so the shared cooldown map must never take a racy write (verified by `go test -race ./node/...`; T10).
- **DO** derive `host.Connect`'s context from `n.ctx` (`context.WithTimeout(n.ctx, budget)`, per the `node.go` pattern) so `Stop`'s `n.cancel()` cancels any in-flight LAN dial — do **NOT** pass a bare `context.Background()`.
- **DO** put the new bonsoir bridge handler in a **NEW** `go-mknoon/bridge/bridge_lan.go` (same `package
  bridge`). gomobile binds the **whole package** (`Makefile` `BIND_PKG := …/bridge`; `events.go` is already
  a second file in the package), so an **exported** `func HandleLANPeerFound(paramsJSON string) string` in
  `bridge_lan.go` **is** bound — confirmed; `make verify-bindings` guards it. (A review agent wrongly
  claimed gomobile needs all handlers in `bridge.go` — refuted, see Accepted Differences.)
- Do **NOT** implement DCUtR cross-NAT upgrade / TCP-punch lane / stable-session layer (→ FDC-12).
- Do **NOT** re-time the cold relay dial / change `DialTimeout` (→ FDC-07).
- Do **NOT** "race everything" — rank LAN ahead of relay via `DefaultDialRanker`, relay races-but-loses.
- **Naming contract (LAN convention):** the acronym is ALL-CAPS in Go **exported** identifiers and Go **test** names — the canonical symbols are `HandleLANPeerFound`, `EnableLibp2pLANDial`, `LANDirectIdentifyBudget`, and `LANDialWarmCooldown`. The new bonsoir bridge event is the colon-namespaced snake string `lan:peer_found` (matching `transport:upgraded` / `node:startup_timing`). Keep lowercase: Go **unexported** leading-acronym identifiers (`lanDialHandler`, `lanWarmCooldown`) and snake_case Go **filenames** (`lan_dial.go`, `lan_dial_test.go`, `bridge_lan.go`).

## Accepted Differences

- The Go-unit T3/T7 use **loopback two-host** dials (FDC-S2 M1 shape), which prove the
  identify/handshake **protocol** but **not** real-NIC/iOS behavior — that residue is D1 by design.
- T7's relay→direct upgrade is host-proven at the **seam** (`WithForceDirectDial` issued); the
  full circuit-v2-in-loop upgrade is device.
- The transport label can't distinguish QUIC-direct vs TCP-direct (`node.go:129-138`) — tests read
  the **raw multiaddr** (`isCircuitAddr`) for the direct-vs-relay assertion.
- **Refuted review-agent claims (verified VALID by direct source read, kept as-is):** (1)
  `peerstore.AddressTTL` **exists** in go-libp2p v0.39.1 (`core/peerstore/peerstore.go:24` = `time.Hour`) —
  an agent grepped only vendored *usage* and wrongly concluded it was absent. (2) A NEW `bridge_lan.go` is
  **valid** — gomobile binds the whole `bridge` package, not a single file (`Makefile BIND_PKG`; `events.go`
  precedent). (3) `network.WithForceDirectDial` **exists** in v0.39.1 (`core/network/context.go:28`, sig
  `(ctx, reason string)`) — load-bearing for T7, confirmed despite zero current in-repo usage.

## Dependency Impact

- **Gated by FDC-S2** — **RESOLVED 2026-06-27** (Option A; QUIC `/tcp`-fallback; identify budget **750ms**).
  M3 real-NIC confirmation deferred to **D1** (this plan's device gate).
- **Shares Go-host files** `node.go` / `config.go` / `feature_flags.go` with **FDC-12** (DCUtR) and
  **FDC-07** (cold-start bonsoir-advertise/reserve timing) → **collision; run sequentially** (roadmap
  Phase 3 ordering; FDC-07 P1 lands before Phase 3 FDC-11/12). New `lan_dial.go` is this plan's own file.
- **Cross-plan coordination (review 2026-06-27):** (1) this plan **CREATES** `bridge/bridge_lan.go`;
  **FDC-15 ADDS** its media-send entrypoint to it (FDC-15:662 must not re-"create"). (2) **FDC-12** inserts
  its reachability-flag branch **after** FDC-11's preserved `ForceReachabilityPrivate()` (`node.go:347`) — it
  must not re-edit that line. (3) **FDC-12 & FDC-15 inherit** FDC-11's `'p2p_lan_dial'` move-feature gate
  (their work runs inside the Go host on top of FDC-11's gated bridge entry) — document the inheritance in
  those plans' blind-spot sweeps. (4) The advertise/parse extension (T12/T13) is **also** the precondition
  FDC-15's media stream + FDC-S6's WS-retirement decision build on.
- **Downstream:** FDC-12 builds its DCUtR upgrade + stable-session layer **on top of** this plan's
  `HandleLANPeerFound`/peerstore-seeding + `WithForceDirectDial` upgrade seam.
- **No migration**, **no relay deploy**, **no Dart `sendChatMessage` change** (path decision stays
  in Dart; Go only adds a LAN-direct lane the existing ranker prefers).
