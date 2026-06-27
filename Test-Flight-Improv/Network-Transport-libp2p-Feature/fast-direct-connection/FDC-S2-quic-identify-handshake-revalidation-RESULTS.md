# FDC-S2 — QUIC identify-handshake re-validation — RESULTS

**Spike:** [`FDC-S2-quic-identify-handshake-revalidation-spike.md`](./FDC-S2-quic-identify-handshake-revalidation-spike.md)
**Executed:** 2026-06-27 · **Status:** closed
**Stack:** go-mknoon `go-libp2p v0.39.1` / `quic-go v0.49.0` · relay `go-libp2p v0.38.2` / `quic-go v0.48.2`
**Harness:** `go-mknoon/node/quic_identify_revalidation_test.go` (standalone; mirrors production
`node.go:355-364` host options; modifies **no** production code)

---

## TL;DR

> ## ✅ Verdict: **Option A** — direct LAN **QUIC** + identify is reliable on v0.39.1. The historical "QUIC identify handshake hang" did **NOT** reproduce.
>
> ## 📏 Budget consumed by FDC-11 / FDC-12: **`750ms`** per-leg dial+identify.
>
> ## 🛰 Relay-QUIC control: sound — `defaultQUICRelayAddress` in client defaults is confirmed (M0 4ms, M2 real prod relay 137ms).

`budget = max(p95_identify rounded↑250ms, 750ms) = max(250, 750) = 750ms`. QUIC M1 p95 was **2ms** —
orders of magnitude under budget, so the **750ms floor governs**, not the measurement.

---

## Measurements

Run command (Go 1.26.x panics `crypto/tls bug: where's my session ticket?` on quic-go v0.49.0 — pin
the declared toolchain):

```
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run TestQuicIdentifyRevalidation -count=1 -v
```

(`FDC_S2_ITERS` overrides N for M1; default 100. `-short` skips all three. Re-run across 3 passes was
stable: total wall-clock 0.8–3.8s.)

| Measurement | What | Result | Threshold | Pass |
|---|---|---|---|---|
| **M0** | relay-QUIC control — hermetic local QUIC relay (EnableRelayService), client dials over QUIC | identify **4ms** | ≤ `ForegroundRelayDialTimeout` 3000ms | ✅ |
| **M1 QUIC / private** | **production config** — 2 in-process hosts, A dials B by explicit `/ip4/127.0.0.1/udp/<port>/quic-v1`, identify **both directions** + `ChatProtocol` stream A→B. N=100 | hang **0/100** · p50 1ms / **p95 2ms** / max 2ms · dialP95 1ms | `hang==0` ∧ `p95 ≤ 1500ms` | ✅ |
| **M1 QUIC / public** | same, `ForceReachabilityPublic` seam | hang **0/100** · p95 2ms / max 2ms | reachability isolation | ✅ |
| **M1 TCP / private** | dial the `/tcp/<port>` LAN multiaddr instead of QUIC. N=100 | hang **0/100** · p50 2ms / **p95 2ms** / max 3ms · streamP95 4ms | `hang==0` ∧ `p95 ≤ 2000ms` | ✅ |
| **M1 TCP / public** | TCP + `ForceReachabilityPublic`. N=100 | hang **0/100** · p95 4ms / max 10ms | — | ✅ |
| **M2** | cross-version skew — v0.39.1 client dials the **production relay (v0.38.2)** over QUIC, **real network** | identify **137ms** (run-to-run 137–164ms) | completes, no skew stall | ✅ |

**Definitions** (per spike Decision Criteria): `hang_rate` = fraction of iters that never complete
identify within a 10s hard ctx **OR** exceed `PeerDialTimeout`=2s. `p95_identify` = 95th-percentile
time from dial start to `EvtPeerIdentificationCompleted` (max of both directions). Evidence comes from
raw per-variant dial addr (QUIC vs TCP), **not** the production `classifyStreamTransport` label (which
can't distinguish QUIC-direct from TCP-direct).

---

## Decision-criteria trace

**Pick Option A** iff, for the QUIC M1 variant: `hang_rate == 0/100` **and** `p95_identify ≤ 1500ms`
**and** M0 + M2 both GREEN.

| Condition | Required | Observed | Met |
|---|---|---|---|
| QUIC M1 hang_rate | `0/100` | `0/100` | ✅ |
| QUIC M1 p95_identify | `≤ 1500ms` | `2ms` | ✅ |
| M0 relay-QUIC control | GREEN (≤ 3s) | `4ms` | ✅ |
| M2 cross-version | GREEN | `137ms` | ✅ |

⇒ **Option A.** (Option B / TCP-only would also have qualified — TCP-direct is independently reliable,
`0/100` @ p95 2ms — but QUIC wins, so the LAN leg dials **QUIC with a TCP fallback lane**, P2-3.)

**Reachability-private NOT implicated:** the `ForceReachabilityPublic` M1 variant is identical to the
production `ForceReachabilityPrivate` variant (both `0/100`, p95 2ms). No escalation; FDC-11 keeps
`ForceReachabilityPrivate()` for the LAN dial.

---

## Why the original hang is gone (root cause)

QUIC identify completes in single-digit ms across 100 iters, and relay-QUIC already ships in the client
defaults. So the historical hang was almost certainly the **config bug the spike flagged**, not a
transport-stack defect: `startAdvertising(peerId, wsPort)` (`local_discovery_service.dart:169`)
advertises the **wsPort, not the libp2p QUIC port**, so the intended `dialPeer(peerId, [localMultiaddr])`
dialed the **wrong port → hang**.

> ⚠ **HARD REQUIREMENT for FDC-11:** advertise the **libp2p QUIC listen port**, NOT `wsPort`. If FDC-11
> feeds the wsPort into the libp2p dial, the "hang" recurs as a **config bug**, not a transport bug.

---

## What FDC-11 / FDC-12 consume

**FDC-11 (libp2p LAN-direct dial):**
- LAN leg dials **QUIC** (`/ip4/<lan>/udp/<quicPort>/quic-v1`), `/tcp/<port>` lane as fallback.
- Per-leg dial+identify budget = **`750ms`** (fits `interactiveLocalBudget` 1500ms with margin).
- Keep `ForceReachabilityPrivate()`.
- Advertise the QUIC port, not wsPort (above).

**FDC-12 (DCUtR relay→direct upgrade) — identify portion only:**
- An upgraded direct QUIC conn reaches usable, identify-complete, **stream-usable** state — **YES** (M1
  proves connect → identify-both-ways → `ChatProtocol` stream).
- Upgrade-abandon timeout (abandon back to relay) = **`750ms`**.
- **Still device-only (`<from FDC-S2>`, NOT closed here):** real-device punch-rate on our relay+NAT mix,
  RTT-sync window, TCP-vs-QUIC *upgrade-success* delta, UPnP/PMP reversal payoff, and whether flipping
  production reachability off `ForceReachabilityPrivate()` is safe to ship. Keep the flag default-off.

---

## Residual / out of scope (by design)

**M3 device confirmation** — two physical phones on one WiFi, real multicast (advertise the QUIC port via
a bonsoir TXT), `dialPeer(peerId, [lanMultiaddr])` through the real bridge — is **scheduled as FDC-11's
device gate**, not required to close this spike. In-process loopback proves the *identify/handshake
protocol*; it does **not** prove iOS QUIC-over-real-WiFi behaviour (UDP path-MTU, NAT hairpin, iOS UDP
throttling). The verdict is pinned to go-libp2p v0.39.1 / quic-go v0.49.0 and must be re-checked on any
go-libp2p bump (M2 cross-version covers only today's v0.38.2 ↔ v0.39.1 skew).

---

## Regression lock

`TestQuicIdentifyRevalidation_M1DirectLAN` (the `M1-quic-private` variant) is a durable lock: if a future
go-libp2p / quic-go bump reintroduces the indefinite hang (an iter that never completes identify within
10s), it turns **RED**. M0 is the harness sanity control; M2 skips (does not fail) when the prod relay is
unreachable, so offline CI still runs the hermetic protocol verdict.

---

## Raw probe data

The harness emits, to test stdout:
- `S2_PROBE_JSON {summary, probes[]}` — one line per M1 variant, every per-iteration record
  (`{transport, reachability, iteration, dialMs, identifyMs, firstStreamMs, completed, neverCompleted, hung, err}`).
- `S2_VARIANT <name> N=… hang=… neverDone=… p50/p95/max … dialP95 … streamP95 …` — per-variant summary.
- `S2_VERDICT …` · `S2_M0 …` · `S2_M2 …` — the computed verdict line and the two control numbers.

Re-run the command above with `-v` to regenerate.
