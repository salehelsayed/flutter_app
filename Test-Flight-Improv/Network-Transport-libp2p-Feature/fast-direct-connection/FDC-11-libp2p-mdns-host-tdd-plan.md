# FDC-11 - libp2p LAN-direct dial fed by bonsoir discovery (unify LAN-direct)  (New Feature)

Status: awaiting-review

Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.5 "Unified LAN-direct over libp2p"; P2-1 table row L358; §8 / §9 Phase 3; open-question #4 L415-416)

> # ⚠ DRAFT — finalize after FDC-S2
> This plan is **gated by spike FDC-S2 (QUIC identify-handshake re-validation)** and is a
> **DRAFT**. Every value tagged **`<from FDC-S2>`** (which transport the LAN leg dials — QUIC
> vs TCP, and the per-leg dial+identify budget) is **provisional** and MUST be replaced by
> FDC-S2's written verdict (Option A / B / C + the `p95_identify` budget number) before this
> plan moves to `implementation-ready`. If FDC-S2 returns **Option C** (no reliable libp2p
> direct-LAN identify on v0.39.1), this entire plan is **shelved / de-scoped to bonsoir+WS
> only** (proposal §5 L159-160) and the RED catalog below is discarded. The **host-testable**
> Go-unit portion is detailed fully (RED catalog + matrix); all **real-multicast / iOS-QUIC**
> rows are flagged as the **device-only closure gate**, not host-closable.

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

**evidence-gated** (DRAFT). The protocol question is answered by FDC-S2; the real-world
question (iOS QUIC over real WiFi NIC, real multicast discovery) is **device-only** and is the
closure gate. The Go-unit tier below is implementation-ready *conditional on* FDC-S2 = Option A
or B.

## Exact Problem Statement

**What's missing.** The Go libp2p host runs with **no mDNS service** — `node.go:338-347` lists
`Identity`, `ListenAddrStrings`, `ConnectionManager`, `EnableRelay`, `EnableHolePunching`,
`NATPortMap`, `ForceReachabilityPrivate` (`:330`), `AddrsFactory(filterAddresses)` and **nothing
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
- **Relay-first reachability stays `ForceReachabilityPrivate()` in production** (`node.go:330`).
  mDNS adds a *direct LAN lane*; it does **not** flip reachability. PRESERVE: production host opts
  still carry `ForceReachabilityPrivate` and `AutoRelay` (`node.go:330,:348-358`).
- **bonsoir+WS stays as the proven foreground/iOS fast path and fallback** (proposal §5 L159-160,
  §6.5 L283). PRESERVE: Dart LAN stack (`local_discovery_service.dart`, `LocalWsServer`) is
  untouched by this plan; both paths run; **receiver dedupes by `messageId`** so the LAN double
  is harmless (proposal §10 L397-398).
- **`classifyStreamTransport` label contract** (`node.go:123-136`) — a LAN-direct stream must
  still classify as `"direct"` (it is non-circuit), preserving the Dart path-decision contract
  (the decision lives in Dart `sendChatMessage`; Go only labels transport).
- **NET-REL-07** (no relay-wire change for older clients, proposal §1 L38): this is a
  **client-host-only** change — it touches **no relay protocol** and needs **no relay deploy**
  (FDC-S2 Option-A note L123-125). PRESERVE: `go-relay-server/` unmodified.
- **`AddrsFactory filterAddresses` already keeps private LAN ranges** (`node.go:172-187` keeps
  anything not loopback/link-local/unspecified, and always keeps circuit) — do NOT re-touch it;
  it is the precondition that lets a LAN `/ip4/<rfc1918>/…` address be announced.

## Root Cause (verify→refute confirmed)

- **No mDNS service is registered.** Verified by Read of `node.go:338-347` (host opts) — there is
  **no `mdns.NewMdnsService`** and **no `mdns` import** in `node.go` (import block L19-30 has no
  `p2p/discovery/mdns`). Confirmed by FDC-S2 background L68-73 and roadmap R4 L113.
- **Same-WiFi therefore routes via relay rendezvous → circuit conn.** `classifyStreamTransport`
  labels any circuit local/remote multiaddr `"relay"` (`node.go:129-135`); a relay circuit is the
  only path a same-LAN peer gets without mDNS.
- **DCUtR is observation-only** under `ForceReachabilityPrivate()` (`node.go:330`; tracer is
  pure-observation `node.go:317-327`, `holepunch_tracer.go:15-17`), so a relay conn **never**
  auto-upgrades to direct — confirming the need for an explicit `WithForceDirectDial` upgrade once
  a LAN addr is known (proposal §6.5 L282-283).

**Refuted / do-NOT-re-introduce:**
- **Do NOT add idempotency/dedup to the relay store** — store dedup by `messageId` already exists
  (`backend_memory.go:121-142`, `backend_redis.go:272-295`, `inbox_store.go:7,14`); the LAN-double
  guarantee leans on the **receiver's** existing `messageId` dedup, not new server code.
- **Do NOT flip `ForceReachabilityPrivate` → public in production** — the test seam
  `forcePublicReachabilityForTests` (`node.go:331-332`) exists for protocol-feasibility tests only;
  production reachability is preserved.
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

## Real Scope

**In scope**
- **bonsoir discovery feeds the libp2p dial on BOTH iOS and Android** (no libp2p-native
  `mdns.NewMdnsService` registered on either platform): bonsoir's discovered LAN `AddrInfo` is
  bridged to Go → `HandleLANPeerFound` → peerstore + `host.Connect(ctx, pi)`, so both platforms get
  the identical libp2p direct LAN dial via OS-blessed discovery. (Bridge a `lan:peer_found`
  event → the Go `HandleLANPeerFound` handler, or call `dialPeer` with the LAN multiaddr from Dart.)
- A `HandleLANPeerFound(pi peer.AddrInfo)` handler: skip self; **debounced per-peer cooldown** (avoid
  swarm 5s→5m backoff on a flapping/offline LAN peer, proposal §6.1 L188-191, §10 L387-388);
  add `pi.Addrs` to peerstore (`AddressTTL`/`ConnectedAddrTTL`); `host.Connect(ctx, pi)` with the
  **`<from FDC-S2>` per-leg dial+identify budget**. Emit a `node:lan_dial_ready` flow-event.
- `WithForceDirectDial`-based **relay→direct upgrade** when a LAN addr is learned for a peer we
  already hold a relay circuit to (proposal §6.5 L282-283).
- New config constants (warm cooldown, LAN identify budget = `<from FDC-S2>`), the feature flag
  (`EnableLibp2pLANDial`), and a `lanDialHandler` field holding the bonsoir-bridge state.
- Keep `classifyStreamTransport` semantics: a LAN dial is `"direct"`.

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
- `go-mknoon/node/node.go` — host opts `:338-347` (wire the bonsoir-bridge LAN-dial handler +
  `WithForceDirectDial`), reachability `:330`, listen addrs `:298-315`, `AddrsFactory filterAddresses`
  `:172-187`, event subscribe `:395-404` (mirror for identify events), `classifyStreamTransport`
  `:123-136`, `emitEvent` `:1896`, `Node` struct fields `:39-109` (add cooldown map + `lanDialHandler`
  field), `Stop` `:471+` (tear down the LAN-dial handler).
- **NEW** `go-mknoon/node/lan_dial.go` (production) — the bonsoir-bridge handler implementing
  `HandleLANPeerFound`, the per-peer cooldown, the `host.Connect` call, the relay→direct upgrade
  helper.
- `go-mknoon/node/config.go` — add `LANDialWarmCooldown`,
  `LANDirectIdentifyBudget = <from FDC-S2>`; existing `PeerDialTimeout=2s :29`,
  `InteractiveDialTimeout=4s :76`.
- `go-mknoon/node/feature_flags.go` — add `EnableLibp2pLANDial` to `FeatureFlags` +
  `DefaultFeatureFlags()` (default = **`<from FDC-S2>`**: true iff Option A/B).

**Dart (verify untouched — preserved sentinels)**
- `lib/core/debug/e2e_test_mode.dart:2` `kDisableLocalDiscovery` — the iOS-sim guard the device gate
  uses (sim shares a host mDNS stack). NOTE: `DISABLE_LOCAL_DISCOVERY` disables the **bonsoir stack
  entirely** — and bonsoir now feeds **both** the WS path **and** the libp2p LAN dial — so it can
  **not** isolate one LAN leg from the other; use the `EnableLibp2pLANDial` flag for that (see D1).
- `lib/core/local_discovery/{local_discovery_service,local_ws_server,bonsoir_discovery_service}.dart`
  — bonsoir discovery + WS path (must stay functional + parallel; dedup by `messageId`).

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
- **MISSING (this plan adds):** `go-mknoon/node/lan_dial_test.go` (Go-unit) and a device
  smoke scenario.

## RED Test Catalog

> All Go-unit tests below are **host-runnable** and form the implementation-ready core (gated only
> by FDC-S2 picking Option A/B, which fixes the dialed transport + budget). Device rows are the
> **closure gate**, not host-closable. New file: `go-mknoon/node/lan_dial_test.go`.

### T1 — bonsoir-found-peer is wired to a libp2p LAN dial when the flag is on (discovery→dial wiring)
- **file::name** `go-mknoon/node/lan_dial_test.go::TestLANPeerFound_DialsWhenFlagEnabled`
- **Tier:** Go unit
- **Shape/setup:** Start a node with `FeatureFlags{EnableLibp2pLANDial:true}` (mirror
  `TestNodeStartStop` L105). Deliver a synthetic `lan:peer_found` `AddrInfo` through the bridge to
  `HandleLANPeerFound`; assert the node holds a non-nil `lanDialHandler` (new struct field), that the
  found peer is dialed (`host.Connect` issued), and that a `node:lan_dial_ready` flow-event is emitted
  (via the test `EventCallback`).
- **RED-on-HEAD-because:** `node.go:338-347` wires no LAN-dial handler — there is no `lanDialHandler`
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
- **Tier:** Go unit (two in-process hosts, loopback LAN — mirrors FDC-S2 M1, `holepunch_feasibility_test.go` style)
- **Shape/setup:** hostA = production-mirrored node; hostB = second host listening on
  `/ip4/127.0.0.1/udp/0/quic-v1` (+`/tcp/0`). Subscribe A to `EvtPeerIdentificationCompleted`.
  Call A's `HandleLANPeerFound(peer.AddrInfo{ID:Bid, Addrs:[B's <from FDC-S2> multiaddr]})`.
- **RED-on-HEAD-because:** there is no `HandleLANPeerFound` handler — the symbol doesn't exist.
- **GREEN-asserts:** A↔B connected (`host.Network().Connectedness(Bid)==Connected`);
  `EvtPeerIdentificationCompleted` for Bid arrives ≤ `LANDirectIdentifyBudget` (`<from FDC-S2>`);
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
- **GREEN-asserts:** `host.Peerstore().Addrs(Bid)` contains the LAN multiaddr (so a later
  ranked-race or warm dial can use it even if this Connect failed).
- **Mutation-that-re-reds:** add to peerstore with a **zero TTL** (or skip `AddAddrs`) → addr
  absent → RED.

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
  `ForceReachabilityPrivate`, `node.go:330`).
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
| bonsoir-found peer dials when flag on | `lanDialHandler` wired + dial + `node:lan_dial_ready` | Go unit | `lan_dial_test.go::TestLANPeerFound_DialsWhenFlagEnabled` | no LAN-dial wiring in `node.go:338-347` | drop `host.Connect` in `HandleLANPeerFound` | `cd go-mknoon && go test ./...` | Go auto-discovered (`./...`) |
| Flag off ⇒ no LAN dial | gate preserved, baseline start intact | Go unit | `…::TestLANPeerFound_NoDial_WhenFlagDisabled` | flag field absent | make the LAN dial unconditional | `cd go-mknoon && go test ./...` | Go `./...` |
| Found peer dials direct | Connected + identify ≤ budget + non-circuit | Go unit | `…::TestHandleLANPeerFound_ConnectsDirect_IdentifyCompletes` | no `HandleLANPeerFound` symbol | drop `host.Connect` | `cd go-mknoon && go test ./...` | Go `./...` |
| Peerstore seeded | LAN addr retained for ranker | Go unit | `…::TestHandleLANPeerFound_SeedsPeerstore_PrivateAddr` | no handler | zero-TTL / skip `AddAddrs` | `cd go-mknoon && go test ./...` | Go `./...` |
| Self ignored | no self-dial | Go unit | `…::TestHandleLANPeerFound_IgnoresSelf` | no handler | remove self early-return | `cd go-mknoon && go test ./...` | Go `./...` |
| Per-peer cooldown | ≤1 dial within window | Go unit | `…::TestHandleLANPeerFound_DebouncesRepeatedFinds_WithinCooldown` | no cooldown map | remove cooldown check | `cd go-mknoon && go test ./...` | Go `./...` |
| Relay→direct upgrade | non-circuit conn after find (or `WithForceDirectDial` issued) | Go unit + **device** | `…::TestHandleLANPeerFound_UpgradesRelayConnToDirect` | no upgrade path; DCUtR inert | drop `WithForceDirectDial` | `cd go-mknoon && go test ./...` + manual 2-phone | Go `./...`; device manual |
| Label contract | LAN stream = `"direct"` | Go unit | `…::TestLANDirectStream_ClassifiesDirect` | preservation | mislabel LAN as `"relay"` | `cd go-mknoon && go test ./...` | Go `./...` |
| Stop tears down handler | teardown + clean restart | Go unit | `…::TestStop_TearsDownLANDialHandler` | no handler field | remove handler teardown in `Stop` | `cd go-mknoon && go test ./...` | Go `./...` |
| Concurrent finds, no racy map write | guarded `lanWarmCooldown`, no DATA RACE | Go unit (`-race`) | `…::TestHandleLANPeerFound_ConcurrentDistinctPeers_NoRace` | no handler/map; unguarded map races | drop the mutex (raw map write) | `cd go-mknoon && go test -race ./node/...` | Go `./...` |
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
  false (mirror `probeRelay`/`warmPeer`; parallels FDC-04/08/09). **Lock:** a RED test (Dart unit) — with the
  runtime gate paused (`migrationExportingNetworkPaused`/`migratedOut`/fail-closed), a delivered
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
   `<from FDC-S2>` budget (T3); its addr is seeded to the peerstore even if the dial fails (T4).
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

1. **Author the RED catalog** `go-mknoon/node/lan_dial_test.go` (T1-T9). Confirm each fails
   for the stated reason (missing symbols/fields). Seam names: `Node.lanDialHandler` field,
   `Node.HandleLANPeerFound`, `Node.lanWarmCooldown` map, `EnableLibp2pLANDial` flag.
2. **Add the feature flag** — `feature_flags.go`: `EnableLibp2pLANDial` + `DefaultFeatureFlags()`
   default = `<from FDC-S2>` (true iff Option A/B). Greens T2's compile; T1 still RED.
3. **Add config constants** — `config.go`: `LANDialWarmCooldown`,
   `LANDirectIdentifyBudget = <from FDC-S2>`.
4. **Create `lan_dial.go`** — a `lanDialHandler` type wrapping `*Node`; `HandleLANPeerFound(pi)`:
   self-skip (T5) → cooldown check (T6) → `host.Peerstore().AddAddrs(pi.ID, pi.Addrs, ttl)` (T4) →
   context with `LANDirectIdentifyBudget`, `host.Connect` (T3). Emit `node:lan_peer_found`. Greens
   T3/T4/T5/T6.
5. **Wire in `Start`** — `node.go:~347`: if `flags.EnableLibp2pLANDial`, wire the `lan:peer_found`
   bridge event to `HandleLANPeerFound` after `n.host` is set (post `libp2p.New`, ~`:367`); store the
   handler on `n.lanDialHandler`; emit `node:lan_dial_ready`. Greens T1.
6. **Relay→direct upgrade** — in `HandleLANPeerFound`, if already connected via a circuit addr to
   `pi.ID` and a non-circuit LAN addr is now known, dial with `network.WithForceDirectDial(ctx,
   "lan-upgrade")`. Greens T7 (host-seam half).
7. **Tear down on Stop** — `node.go` `Stop` (`:471+`): tear down `n.lanDialHandler` (unwire the
   `lan:peer_found` bridge event); nil the field; clear `lanWarmCooldown`. Greens T9.
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
# Go host (the core gate for this plan) — expected: PASS, +9 new Go-unit tests, 0 regress
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && go test ./...   # expected count: go1.25.0 all-pass (~1171 baseline) <from impl>
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && make lint   # expected: clean (vet/lint over node/ + bridge/)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && go test -race ./node/...   # lanWarmCooldown shared map — expected: PASS, no DATA RACE

# Relay must be UNTOUCHED (preserved) — expected: PASS, 0 changed
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go test ./...

# Transport family (host-side; the live-LAN row is device-only) — expected: PASS
./scripts/run_test_gates.sh transport   # expected: device/fixture-gated baseline (skips on lone sim) <from run>

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

- [ ] FDC-S2 verdict written (A/B/C) + budget number consumed (every `<from FDC-S2>` replaced).
- [ ] (If A/B) T1-T9 authored RED-first, GREEN, each mutation re-reds.
- [ ] (If A/B) T10 authored (concurrent-finds `-race` lock); `cd go-mknoon && go test -race ./node/...` PASS (no DATA RACE on `lanWarmCooldown`) and `cd go-mknoon && make lint` clean.
- [ ] New exported identifiers carry Go doc comments — `HandleLANPeerFound`, `EnableLibp2pLANDial`, `LANDialWarmCooldown` (each comment begins with the identifier name, per Go convention).
- [ ] `cd go-mknoon && go test ./...` PASS; `go-relay-server` unchanged + PASS.
- [ ] `./scripts/run_test_gates.sh transport` host-side PASS.
- [ ] `flutter analyze` 0-new; `git diff --check` clean.
- [ ] Production `ForceReachabilityPrivate`, AutoRelay, `filterAddresses`, bonsoir+WS, relay wire
      all unchanged (preserved-sentinel diff review).
- [ ] D1 device smoke scheduled (two-phone, toggle `EnableLibp2pLANDial` ON/OFF) — DEFERRED-not-waived.
- [ ] (If C) plan shelved; bonsoir+WS remains the LAN path; doc marked superseded.

## Scope Guard (hard Do-not)

- **Do NOT** change group pubsub or shared-host connection behavior — `HandleLANPeerFound`→`host.Connect` reaches **group members** on the same WiFi; the new bonsoir-fed libp2p LAN dial is **additive only** (`messageId` dedup) and must leave `pubsub_delivery_test.go` and group connection counts unchanged (**group-safety floor:** `cd go-mknoon && go test ./...` green).
- Do **NOT** flip `ForceReachabilityPrivate` in production (test seam only, `node.go:331-332`).
- Do **NOT** edit `go-relay-server/` (NET-REL-07; no relay deploy).
- Do **NOT** add store dedup/idempotency — it already exists (`backend_memory.go:121-142`,
  `backend_redis.go:272-295`, `inbox_store.go:7,14`).
- Do **NOT** remove or alter bonsoir+WS (`local_discovery_service.dart`, `LocalWsServer`).
- Do **NOT** feed the **wsPort** into the libp2p LAN dial — hand `host.Connect` the libp2p host's own LAN multiaddr (`host.Addrs()`).
- **DO** guard `lanWarmCooldown` with a `sync.Mutex` (or use a `sync.Map`) — the bonsoir bridge fires `HandleLANPeerFound` from a goroutine off the bridge channel while node lifecycle runs, so the shared cooldown map must never take a racy write (verified by `go test -race ./node/...`; T10).
- **DO** derive `host.Connect`'s context from `n.ctx` (`context.WithTimeout(n.ctx, budget)`, per the `node.go` pattern) so `Stop`'s `n.cancel()` cancels any in-flight LAN dial — do **NOT** pass a bare `context.Background()`.
- **DO** put the new bonsoir bridge forwarder in a **NEW** `go-mknoon/bridge/bridge_lan.go` — do **NOT** add it to `bridge.go`.
- Do **NOT** implement DCUtR cross-NAT upgrade / TCP-punch lane / stable-session layer (→ FDC-12).
- Do **NOT** re-time the cold relay dial / change `DialTimeout` (→ FDC-07).
- Do **NOT** "race everything" — rank LAN ahead of relay via `DefaultDialRanker`, relay races-but-loses.
- **Naming contract (LAN convention):** the acronym is ALL-CAPS in Go **exported** identifiers and Go **test** names — the canonical symbols are `HandleLANPeerFound`, `EnableLibp2pLANDial`, `LANDirectIdentifyBudget`, and `LANDialWarmCooldown`. The new bonsoir bridge event is the colon-namespaced snake string `lan:peer_found` (matching `transport:upgraded` / `node:startup_timing`). Keep lowercase: Go **unexported** leading-acronym identifiers (`lanDialHandler`, `lanWarmCooldown`) and snake_case Go **filenames** (`lan_dial.go`, `lan_dial_test.go`, `bridge_lan.go`).

## Accepted Differences

- The Go-unit T3/T7 use **loopback two-host** dials (FDC-S2 M1 shape), which prove the
  identify/handshake **protocol** but **not** real-NIC/iOS behavior — that residue is D1 by design.
- T7's relay→direct upgrade is host-proven at the **seam** (`WithForceDirectDial` issued); the
  full circuit-v2-in-loop upgrade is device.
- The transport label can't distinguish QUIC-direct vs TCP-direct (`node.go:129-135`) — tests read
  the **raw multiaddr** (`isCircuitAddr`) for the direct-vs-relay assertion.

## Dependency Impact

- **Gated by FDC-S2** (verdict A/B/C + identify budget) — **hard precondition**; this draft cannot
  finalize without it.
- **Shares Go-host files** `node.go` / `config.go` / `feature_flags.go` with **FDC-12** (DCUtR) and
  **FDC-07** (cold-start bonsoir-advertise/reserve timing) → **collision; run sequentially** (roadmap
  Phase 3 ordering; FDC-07 P1 lands before Phase 3 FDC-11/12). New `lan_dial.go` is this plan's own file.
- **Downstream:** FDC-12 builds its DCUtR upgrade + stable-session layer **on top of** this plan's
  `HandleLANPeerFound`/peerstore-seeding + `WithForceDirectDial` upgrade seam.
- **No migration**, **no relay deploy**, **no Dart `sendChatMessage` change** (path decision stays
  in Dart; Go only adds a LAN-direct lane the existing ranker prefers).
