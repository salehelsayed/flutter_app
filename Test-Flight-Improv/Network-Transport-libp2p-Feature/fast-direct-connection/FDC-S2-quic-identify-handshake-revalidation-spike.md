# FDC-S2 - QUIC identify-handshake re-validation  (Spike / Measurement)

Status: **closed — Option A (QUIC LAN-direct reliable). Budget = 750ms.** (executed 2026-06-27, see Verdict below)

---

## ✅ VERDICT / RESULTS  (EXECUTED 2026-06-27 — go-libp2p v0.39.1 / quic-go v0.49.0)

**Verdict: Option A — direct LAN QUIC + identify is reliable (no hang) on v0.39.1.**
The historical *"QUIC identify handshake hang"* **does NOT reproduce** on the current stack.

> Standalone results doc (full tables + raw-data format): **`FDC-S2-quic-identify-handshake-revalidation-RESULTS.md`**.

**The single number FDC-11/FDC-12 consume — direct-LAN identify budget = `750ms`.**
(`= max(p95_identify rounded up to 250ms, 750ms) = max(250, 750)`; QUIC M1 p95 was 2ms — orders of
magnitude under budget, so the `750ms` floor governs, not the measurement.)

**Relay-QUIC control fact:** `defaultQUICRelayAddress` in the client defaults
(`p2p_bridge_client.dart:13-14`) is **sound** — relay-QUIC identify completes well within budget.

| Measurement | Result | Threshold | Pass |
|---|---|---|---|
| **M0** relay-QUIC control (hermetic local QUIC relay) | identify **4ms** | ≤ `ForegroundRelayDialTimeout` 3000ms | ✅ |
| **M1 QUIC / private** (production config) — N=100 | hang **0/100**, p50 1ms / **p95 2ms** / max 2ms | hang==0 ∧ p95≤1500ms | ✅ |
| **M1 QUIC / public** — N=100 | hang **0/100**, p95 2ms / max 2ms | — (reachability isolation) | ✅ |
| **M1 TCP / private** — N=100 | hang **0/100**, p50 2ms / **p95 2ms** / max 3ms | hang==0 ∧ p95≤2000ms | ✅ |
| **M1 TCP / public** — N=100 | hang **0/100**, p95 4ms / max 10ms | — | ✅ |
| **M2** cross-version (prod relay **v0.38.2** ← client **v0.39.1**, real network, QUIC) | identify **137ms** (run-to-run 137–164ms) | completes, no skew stall | ✅ |

**Decision-criteria trace (spike §"Decision Criteria"):** Option A iff QUIC M1 `hang_rate==0/100`
**and** `p95_identify ≤ 1500ms` **and** M0 + M2 both GREEN → `0/100` ✅, `2ms ≤ 1500ms` ✅, M0 4ms ✅,
M2 137ms ✅ ⇒ **Option A**. (Option B/TCP-only would also have qualified — TCP-direct is independently
reliable, `0/100` @ p95 2ms — but QUIC wins, so the LAN leg dials QUIC with a TCP fallback lane.)

**Reachability-private NOT implicated:** the `ForceReachabilityPublic` M1 variant is identical to the
`ForceReachabilityPrivate` (production) variant (both `0/100`, p95 2ms). No `ForceReachabilityPublic`-vs-
`Private` escalation is needed; FDC-11 keeps `ForceReachabilityPrivate()` for the LAN dial.

**Root-cause of the original hang (corroborates spike Risks):** since QUIC identify completes in single-
digit ms across 100 iters and the relay-QUIC default already ships, the historical hang was almost
certainly the **config bug the spike flagged** — `startAdvertising(peerId, wsPort)`
(`local_discovery_service.dart:169`) advertises the **wsPort, not the libp2p QUIC port**, so the intended
`dialPeer(peerId, [localMultiaddr])` dialed the **wrong port → hang**, not a transport-stack defect.
**FDC-11 MUST advertise the QUIC (libp2p) listen port, or the "hang" recurs as a config bug.**

**Harness:** `go-mknoon/node/quic_identify_revalidation_test.go` (standalone; mirrors production
`node.go:355-364` host options; does NOT modify production code). Reproduce:
```
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run TestQuicIdentifyRevalidation -count=1 -v
```
(`GOTOOLCHAIN=go1.25.0` is required — Go 1.26.x panics `crypto/tls bug: where's my session ticket?`
on quic-go v0.49.0. N overridable via `FDC_S2_ITERS`; `-short` skips all three.) `M1-quic-private` is a
durable **regression lock**: if a future go-libp2p/quic-go bump reintroduces the indefinite hang, it goes
RED. The QUIC-vs-TCP evidence comes from raw `conn` transport selection (per-variant dial addr), not the
production `classifyStreamTransport` label (which can't distinguish QUIC-direct from TCP-direct).

**Residual (NOT closed by this spike — by design):** M3 device confirmation (two physical phones, real
multicast, iOS-QUIC over real WiFi NIC) is scheduled as **FDC-11's device gate**, per Exit Gate. In-process
loopback proves the *identify/handshake protocol*; it does not prove iOS UDP path-MTU / NAT-hairpin / UDP
throttling behaviour.

---

Gates:
- **FDC-11 (libp2p LAN-direct dial, bonsoir-discovered)** — cannot be finalized until we know a libp2p
  QUIC/TCP LAN dial + `identify` completes reliably within budget. FDC-11 plans to feed
  bonsoir-discovered LAN addresses to the Go host and, via `HandleLanPeerFound`, `host.Connect` the
  discovered `AddrInfo` so a same-WiFi peer becomes a **direct libp2p dial** (proposal §6.5 / P2-1,
  L276-286). If the historical *"QUIC identify handshake hang"* (proposal §5, L147-149;
  `UI-15-WS-Server/plan.md` L42-48) still reproduces on go-libp2p v0.39.1, that plan would
  ship a LAN path that hangs instead of acking — so FDC-11 is blocked on this spike's verdict
  and on the per-step `identify` budget this spike measures.
- **FDC-12 (DCUtR relay→direct upgrade, flagged)** — the proposal's relay→direct upgrade
  (§6.5 L282-283, P2-3 L360) hands the peer a **second, freshly-dialed direct connection** that
  must complete `identify` before it can carry a stream. If direct QUIC `identify` is the thing
  that hangs, the upgraded connection never becomes usable and DCUtR "succeeds" at the swarm
  level while the app sees a dead leg. FDC-12 needs this spike to confirm a direct QUIC (and TCP)
  connection reaches usable-identify state, and to set the timeout after which the upgrade is
  abandoned back to relay.

---

## Question

On the **current** stack — go-mknoon `go-libp2p v0.39.1` / `quic-go v0.49.0`
(`go-mknoon/go.mod:9,:108`), relay `go-libp2p v0.38.2` / `quic-go v0.48.2`
(`go-relay-server/go.mod:10,:118`) — does the historical *"QUIC identify handshake hang"*
(proposal §5, L147-149) still occur? Concretely, two sub-questions:

1. **Relay-QUIC (already shipping):** Does a client dial to the relay's QUIC listener
   (`/dns/mknoun.xyz/udp/4002/quic-v1/...`, `config.go:15`, `p2p_bridge_client.dart:14`) reach a
   usable, `identify`-complete connection within budget? (This is *de facto* in production today —
   `defaultQUICRelayAddress` is back in the client defaults at `p2p_bridge_client.dart:13-14` and
   returned by the default relay list at `:28` — so confirm it, don't assume it.)
2. **Peer-to-peer LAN QUIC/TCP (never shipped):** Does `dialPeer(peerId, [localMultiaddr])` over
   a same-WiFi `/ip4/<lan>/udp/<port>/quic-v1` (and the `/tcp/<port>` fallback) reach an
   `identify`-complete, stream-usable connection within a single-digit-second budget — without the
   indefinite hang that made the team ship bonsoir+WebSocket instead (`native-p2p-go-libp2p.md`
   L415-421)?

The number this spike produces: **a yes/no on direct-LAN QUIC + identify reliability, plus a
measured p95 time-to-usable-identify** that becomes FDC-11/FDC-12's per-step budget.

## Why it blocks

The proposal makes the QUIC-identify re-validation an explicit **precondition** for the LAN-direct
unification (§6.5 L284-286: *"Precondition: the §5 QUIC-identify-hang re-validation"*) and
open-question #4 (L415-416). Without this measurement, FDC-11/FDC-12 would have to **invent** one of
two assumptions:

- *Optimistic:* "QUIC identify is fine now, dial LAN-direct and rank it ahead of relay." If the hang
  persists, every same-WiFi send stalls on a never-completing direct leg until its budget expires,
  then falls to relay/inbox — **strictly worse** than today's bonsoir+WS path, which the proposal
  warns is "the proven foreground LAN path" until re-validated (§5 L159-160).
- *Pessimistic:* "QUIC is still broken, keep only bonsoir+WS." If the hang is in fact gone (likely,
  given relay-QUIC already ships), we permanently forgo the clean libp2p `DefaultDialRanker`
  LAN-races-relay end-state (§6.5) for no reason.

Either invented assumption is load-bearing for a Go-host change and device-only to disprove later, so
it must be measured **before** FDC-11/FDC-12 are written, not during.

## Background  (grounded in real source)

**The host already speaks QUIC, TCP, and WS on the LAN — it just never dials a *peer* over them.**
- Node listen addrs include QUIC, WS, and bare TCP on both v4/v6 (`go-mknoon/node/node.go:298-315`):
  `/ip4/0.0.0.0/udp/0/quic-v1`, `/ip4/0.0.0.0/tcp/0/ws`, `/ip4/0.0.0.0/tcp/0` (and v6 mirrors).
- Host options carry **no explicit transport list and no explicit identify/mDNS option**
  (`node.go:338-347`): `Identity`, `ListenAddrStrings`, `ConnectionManager`, `EnableRelay`,
  `EnableHolePunching`, `NATPortMap`, `ForceReachabilityPrivate` (`:330`), `AddrsFactory`. So the
  host uses libp2p **defaults**: QUIC-v1 + TCP + WS transports, Noise/TLS security, and `identify`
  auto-runs on every new connection. There is **no `mdns.NewMdnsService`** (the §6.5 gap) and **no
  `WithForceDirectDial`**.
- Stream transport is labeled only `relay` vs `direct` by `classifyStreamTransport`
  (`node.go:123-136`) — it keys off `isCircuitAddr` on local/remote multiaddr; it does **not**
  distinguish QUIC-direct from TCP-direct. The spike's instrumentation must read the raw multiaddr,
  not this label.

**Relay-QUIC is de facto already re-validated in production — confirm, don't re-litigate.**
- `defaultQUICRelayAddress` is **back in the client defaults**: `p2p_bridge_client.dart:13-14`
  defines it, and `getDefaultRelayAddresses()` returns `[defaultRendezvousAddress,
  defaultQUICRelayAddress]` at `:28`. The Go side mirrors it: `config.go:15` `DefaultQUICRelay`,
  returned at `config.go:131`. So the very action the UI-15 note gated on (*"Once confirmed working,
  re-add defaultQUICRelayAddress to the client defaults"*, `UI-15-WS-Server/plan.md` L47-48)
  **has already happened** — meaning relay reservations over QUIC complete `identify` in the field.
  This is the strongest existing evidence the original hang was transport-stack-specific and is gone
  on v0.39.1. The spike should still *measure* it as the control/baseline.
- Relay server listens QUIC + TCP + WS and runs `EnableRelayService` (`go-relay-server/main.go:57-72`),
  advertising `/dns4/<dns>/udp/<QUICPort>/quic-v1` (`:58`).

**The peer-to-peer LAN QUIC dial is the genuinely-unvalidated path.**
- The migration plan *intended* bonsoir-for-discovery → `bridge.dialPeer(peerId, addresses:
  [localMultiaddr])` for a **direct QUIC connection on the LAN** (`native-p2p-go-libp2p.md`
  L415-421, listing "Port: Go node's QUIC listen port" at L413). **That never shipped.** The LAN
  service today advertises a **`wsPort`**, not the libp2p QUIC port:
  `startAdvertising(peerId, wsPort)` (`local_discovery_service.dart:169`), and the LAN transport is
  the bespoke `LocalWsServer` WebSocket+nonce-ACK stack, not a libp2p dial (proposal §5 L141-160).
- Why it never shipped (proposal §5 L147-149, `UI-15-WS-Server/plan.md` L42-48): a live *"QUIC
  identify handshake hang"* on the QUIC connection; `defaultQUICRelayAddress` had been *removed* and
  was to be re-added "only after verifying the handshake didn't hang" — and the explicit ask was to
  *"test Quick connection to make sure the identify handshake does not hang"* with *"a client"*
  (`UI-15-WS-Server/plan.md` L43, L46).

**Budgets that bound "within budget."**
- `PeerDialTimeout = 2s` (peer-to-peer dial, `config.go:29`), `DialTimeout = 15s` (relay,
  `config.go:28`), `RelayProbeTimeout = 5s` (`:30`), and the foreground-tightened
  `ForegroundRelayDialTimeout = 3s` (`:39`). A LAN identify that needs more than ~`PeerDialTimeout`
  to become usable would miss the send-path local budget (`interactiveLocalBudget` 1500ms,
  `send_chat_message_use_case.dart:21`).

## Options  (what the verdict can be, and what each implies)

This is primarily a **measurement** spike; the "options" are the outcomes the measurement selects.

### Option A — Direct LAN QUIC + identify is reliable (no hang) on v0.39.1
- **Implies:** FDC-11 can feed bonsoir-discovered LAN peers into `host.Connect` for a direct dial over
  QUIC, letting `DefaultDialRanker` race LAN ahead of relay (proposal §6.5). FDC-12 can treat a
  DCUtR-upgraded direct QUIC conn as usable once identify completes.
- **Pros:** clean end-state; one connectivity system; relay→direct upgrade becomes real.
- **Cons / cost:** the Go host change (the bonsoir-fed LAN dial, behind `EnableLibp2pLanDial`) is
  device-only to validate (the iOS sim shares a host mDNS/bonsoir stack → isolate via the flag, not
  `DISABLE_LOCAL_DISCOVERY` which disables bonsoir entirely; proposal §6.5 L285-286). Still keep
  bonsoir+WS as the proven fallback and dedupe by `messageId` (§6.5 L283).
- **Additive-only / NET-REL-07:** bonsoir-fed direct dialing of LAN peers is **client-host-only**;
  it does **not** touch the relay wire protocol, so NET-REL-07 (no relay break for old clients,
  proposal §1 L38) is **unaffected**. No relay deploy required for FDC-11's QUIC LAN dial.
- **iOS/Android:** QUIC dial itself is entitlement-free; the *discovery* that feeds it is the
  entitlement-sensitive part (raw multicast → bonsoir wraps OS-blessed multicast,
  `native-p2p-go-libp2p.md` L401-407). LAN QUIC dial works on both once a multiaddr is in hand.

### Option B — Direct LAN QUIC still hangs, but **TCP-direct** identify is reliable
- **Implies:** FDC-11 dials the `/tcp/<port>` LAN multiaddr (`node.go:301`) instead of QUIC; the
  proposal's P2-3 already mandates "include a TCP-direct lane (punchr: TCP==QUIC)" (L360). FDC-12's
  upgrade prefers TCP.
- **Pros:** still a real libp2p LAN-direct path, dodging the QUIC-specific hang.
- **Cons:** TCP handshake (TCP + Noise + identify) is RTT-heavier than QUIC's 1-RTT; budget must be
  larger. No QUIC connection-migration benefit on WiFi↔cellular (proposal §12 L466).
- **Additive-only:** same as A — client-host-only, NET-REL-07 unaffected.

### Option C — All libp2p direct-LAN identify is unreliable on v0.39.1 (hang persists broadly)
- **Implies:** **FDC-11 is shelved / de-scoped to bonsoir+WS only** (keep the proven foreground LAN
  path, proposal §5 L159-160); **FDC-12 is gated/flagged-off** because a DCUtR upgrade that can't
  finish identify is worse than staying on relay. The §6.2 ranked race ranks LAN = bonsoir+WS, not a
  libp2p direct leg.
- **Pros:** no regression; we keep what works.
- **Cons:** permanent two-system fragmentation (proposal §2 L67-70 root cause stays).
- **Note:** Given relay-QUIC already ships in defaults, Option C for *QUIC specifically* is
  **unlikely**; C is most plausible only if the hang is identify-on-inbound-LAN-dial-specific
  (e.g. AddrsFactory / reachability-private interaction), which the method below isolates.

## Method  (exactly how to measure)

A standalone Go test client is the right instrument (matches the original ask: *"test ... with a
client"*, `UI-15-WS-Server/plan.md` L46). **Do not** modify production `node.go`/relay for the
measurement — build a separate harness binary/test that imports the same go-libp2p v0.39.1.

**M0 — Relay-QUIC control (baseline, host-runnable).**
- New Go test (e.g. `go-mknoon/node/quic_identify_revalidation_test.go`) builds a libp2p host with
  the **production transport/security defaults mirrored from `node.go:338-347`** (QUIC-v1 + TCP + WS,
  Noise/TLS, `ForceReachabilityPrivate`, AddrsFactory `filterAddresses`).
- Dial `DefaultQUICRelay` (`config.go:15`). Assert: `host.Connect` returns, and `identify` completes
  — verified by `host.Peerstore().Get(peerID, "AgentVersion")` becoming non-empty **OR** an
  `event.EvtPeerIdentificationCompleted` arriving on an `EventBus().Subscribe`. Record
  `time-to-connect`, `time-to-identify-completed`, `time-to-first-usable-stream` (open a
  `RendezvousProtocol` stream).
- **Threshold:** identify completes ≤ `ForegroundRelayDialTimeout` (3s, `config.go:39`) for the
  relay. This is the sanity control — if M0 fails, the harness is wrong, not the stack.

**M1 — Peer↔peer **direct LAN QUIC** identify (the headline; two hosts, same machine = loopback LAN).**
- Spin up **two** libp2p hosts in-process (hostA, hostB), each with the production-mirrored options
  above, listening on `/ip4/127.0.0.1/udp/0/quic-v1` (+ `/tcp/0`). This reproduces a same-LAN
  direct dial without needing two physical devices for the *protocol* question (it does **not** test
  real multicast — that's FDC-11's device-only concern, proposal §6.5 L285-286).
- hostA dials hostB **by an explicit QUIC multiaddr** (mirroring the intended
  `dialPeer(peerId, [localMultiaddr])`, `native-p2p-go-libp2p.md` L419): add B's
  `/ip4/127.0.0.1/udp/<port>/quic-v1/p2p/<Bid>` to A's peerstore, then `host.Connect(ctx, addrInfo)`.
- Assert identify completes **both directions** (subscribe to `EvtPeerIdentificationCompleted` on
  both; the original hang was the *handshake* not completing). Then open a `ChatProtocol`
  (`config.go:23`) stream A→B, write a frame, assert B's handler reads it.
- Run **N = 100 iterations** with fresh hosts each time to catch an *intermittent* hang (the original
  was a "hang", i.e. sometimes-never-completes, not a hard error). Record per-iteration
  time-to-identify and the **count of iterations that exceed `PeerDialTimeout` (2s, `config.go:29`)
  or never complete within a hard 10s ctx**.
- **Variants to isolate Option B vs C:** repeat M1 dialing the **`/tcp/<port>` LAN multiaddr** only
  (`node.go:301`), and repeat with `ForceReachabilityPublic` swapped in (the existing test seam
  `forcePublicReachabilityForTests`, `node.go:331-332`) to check whether
  `ForceReachabilityPrivate` + AddrsFactory filtering is implicated in the hang.

**M2 — Cross-version skew check (relay v0.38.2 ↔ client v0.39.1).**
- The relay runs an **older** go-libp2p (`go-relay-server/go.mod:10` v0.38.2) than the client
  (v0.39.1). Build a second harness host pinned to v0.38.2's identify and dial it from a v0.39.1
  client over QUIC to confirm no identify-protocol-version skew reintroduces a stall. (Mirrors M0 but
  against a version-pinned peer; cheap, host-runnable.)

**M3 — Device confirmation (only if M1 is GREEN; gates the FDC-11 device milestone, not this spike).**
- On two physical phones on one WiFi, advertise the **QUIC port** (not wsPort) via a throwaway
  bonsoir TXT, then `dialPeer(peerId, [lanMultiaddr])` through the real bridge. Capture the
  `node:*` flow-events. This is the only place real-NIC/iOS-QUIC behavior is observable
  (`e2e_test_mode.dart:2` `kDisableLocalDiscovery`; sim shares host mDNS so it's host-disabled).
  **Out of scope for closing this spike** — record as the FDC-11 device gate.

**Instruments / flow-events to add (test-only, do not ship in send path):**
- Subscribe to `event.EvtPeerIdentificationCompleted` / `EvtPeerIdentificationFailed` and
  `EvtPeerConnectednessChanged` (the node already subscribes to connectedness at `node.go:395-398`).
- Emit `quic_identify_probe` records: `{transport: quic|tcp, direction, dialMs, identifyMs,
  firstStreamMs, hung: bool, iteration}` to test stdout/JSON.

**Commands (author-time note — DO NOT run in this planning pass):**
- `cd go-mknoon && go test ./node -run QuicIdentifyRevalidation -count=1 -v` (M0/M1/M2).
- M3 is `scripts/run_test_gates.sh`-adjacent device smoke, two-phone, manual.

## Decision Criteria  (concrete thresholds)

Let `p95_identify` = 95th-percentile time-to-`EvtPeerIdentificationCompleted` over M1's 100 iters,
and `hang_rate` = fraction of iters that never complete within a 10s hard ctx OR exceed
`PeerDialTimeout`=2s (`config.go:29`).

- **Pick Option A (QUIC LAN reliable)** iff, for the **QUIC** M1 variant: `hang_rate == 0/100`
  **and** `p95_identify ≤ 1500ms` (fits `interactiveLocalBudget`, `send_chat_message_use_case.dart:21`)
  **and** M0 + M2 both GREEN. The FDC-11/FDC-12 per-step direct-identify budget is then set to
  `max(p95_identify rounded up to 250ms, 750ms)`.
- **Pick Option B (TCP-direct only)** iff QUIC M1 fails the above but the **TCP** M1 variant has
  `hang_rate == 0/100` and `p95_identify ≤ 2000ms` (`PeerDialTimeout`). FDC-11 dials TCP; budget =
  `max(p95_tcp rounded to 250ms, 1500ms)`.
- **Pick Option C (no libp2p direct-LAN; keep bonsoir+WS)** iff **both** QUIC and TCP M1 variants
  show `hang_rate > 0` OR `p95_identify > 2000ms`. FDC-11 de-scopes to bonsoir+WS; FDC-12 stays
  flag-off.
- **Reachability-private implicated:** if the `ForceReachabilityPublic` M1 variant is GREEN but the
  `ForceReachabilityPrivate` variant hangs, escalate — the fix is a host-config nuance (e.g. an
  explicit direct-dial allowance), recorded as a sub-task on FDC-11, and Option A/B is conditional on
  that nuance.

## Expected Output  (what FDC-11 / FDC-12 consume)

1. **A verdict: Option A | B | C** — i.e. "enable the libp2p LAN-direct dial (bonsoir-discovered)?"
   yes-QUIC / yes-TCP-only / no.
2. **A single number:** the **direct-LAN identify budget in ms** (`p95_identify` rounded), which
   becomes FDC-11's per-leg dial+identify budget in the §6.2 ranked race and FDC-12's
   upgrade-abandon timeout. If Option C, the output is "N/A — LAN leg = bonsoir+WS".
3. **A confirmed control fact:** relay-QUIC identify p95 (M0) — documents that
   `defaultQUICRelayAddress` in defaults (`p2p_bridge_client.dart:13-14`) is sound, or flags a
   latent relay-QUIC regression.

## Exit Gate

- [x] M0 GREEN (relay-QUIC identify ≤ 3s) — control passes. **(4ms ≤ 3000ms)**
- [x] M1 run at N=100 for both QUIC and TCP variants, plus the reachability-private/public pair, with
  `hang_rate` and `p95_identify` recorded. **(all 4 variants 0/100 hang; QUIC p95 2ms, TCP p95 2ms)**
- [x] M2 cross-version (v0.38.2 ↔ v0.39.1) GREEN or its failure characterized. **(GREEN, prod relay
  identify 137ms over real network)**
- [x] A written verdict (A/B/C) + the budget number + the relay-QUIC control number captured in this doc
  and referenced by the FDC-11 and FDC-12 plan docs. **(Option A, 750ms, M0 4ms / M2 137ms — see
  Verdict above; FDC-11 §"Resolved by FDC-S2", FDC-12 §"Resolved by FDC-S2".)**
- [ ] M3 device confirmation is **scheduled as FDC-11's device gate**, not required to close this spike
  (the spike answers the *protocol* question; the device answers the *real-multicast/iOS-QUIC*
  question). **(deferred to FDC-11 device gate — NOT a blocker for closing this spike.)**

## Risks / Unknowns

- **In-process loopback ≠ real LAN NIC.** M1 proves the *identify/handshake protocol* completes; it
  does **not** prove iOS QUIC-over-real-WiFi behaves (UDP path MTU, NAT hairpin, iOS UDP throttling).
  That residue is explicitly M3/device-only (proposal §6.5 L285-286) and must not be over-claimed.
- **The original hang may have been environment-specific** (a since-fixed quic-go version, a TXT/port
  mismatch advertising wsPort vs QUIC port — note today's `startAdvertising(peerId, wsPort)`
  `local_discovery_service.dart:169` would itself cause a "dial the wrong port → hang"). If M1 is
  GREEN, FDC-11 must also fix the advertised port, or the "hang" recurs as a config bug, not a
  transport bug.
- **`classifyStreamTransport` can't distinguish QUIC-direct from TCP-direct** (`node.go:129-135`),
  so Option A-vs-B evidence must come from raw `conn.RemoteMultiaddr()` inspection in the harness,
  not from the production transport label.
- **Cross-version skew is real** (relay v0.38.2 vs client v0.39.1, `go.mod` deltas) — M2 covers the
  identify-protocol surface, but a future relay upgrade could shift the answer; the verdict is pinned
  to these exact versions and must be re-checked on any go-libp2p bump.
- **No `mdns.NewMdnsService` exists today** (`node.go:338-347`), so M1 deliberately supplies the
  multiaddr manually; it does not exercise the discovery half. Discovery reliability is FDC-11's
  separate concern (entitlement / bonsoir-wrapped multicast, `native-p2p-go-libp2p.md` L401-407).
