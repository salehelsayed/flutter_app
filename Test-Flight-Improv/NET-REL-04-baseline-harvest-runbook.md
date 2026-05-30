# NET-REL-04 AC#5 — Baseline Transport Census Harvest Runbook

> Status: decision gate. Run this BEFORE starting NET-REL-01/02/03/05. The numbers harvested here are the input that decides how those four workstreams are prioritized. Do not skip.

---

## 1. Goal

**AC#5 (NET-REL-04):** Produce the on-device baseline transport census — the report a maintainer can read that states the transport mix (`X% direct, Y% relay, Z% wifi, W% inbox`), the per-transport median send latency, the fallback-rung distribution, and the LAN-availability snapshot — and use it as **the explicit input to prioritizing NET-REL-01..05**.

This is a **decision gate, not a nice-to-have.** The whole NET-REL program is structured around it:

- If the census shows cross-network traffic is **almost all relay** (the expected outcome given `ForceReachabilityPrivate()` is set in production at `go-mknoon/node/node.go:315`, plus cellular CGNAT), then chasing direct/DCUtR (NET-REL-02 Option B, NET-REL-03) **deprioritizes** toward "accept relay as steady state," and effort shifts to LAN (NET-REL-01) and orchestration (NET-REL-05).
- If the census shows **low wifi share among co-located peers**, NET-REL-01 (LAN) **rises** — it is the only direct transport that physically works today.
- If the **fallback-rung** distribution shows a meaningful share of sends falling to the slow sequential relay-probe→inbox tail, NET-REL-05's unhappy-path work **rises**; if the happy path dominates, it drops.

Because every downstream decision keys off these four numbers, a census harvested from the wrong session (simulator, group-heavy, tiny N, single launch read as multi-day) will **misdirect the entire program**. The rest of this runbook exists to prevent that.

---

## 2. What the Census Measures (and What It Does NOT)

> **SCOPE BANNER — read before harvesting:** This census covers **1:1 conversation sends/receives and LAN wifi only**. Group (GossipSub/pubsub) messages are **NOT counted** (TOM-004, by design). It reflects **successfully-delivered traffic only** for the current **single app launch (in-memory, session-scoped)**. A **simulator cannot prove LAN/wifi**.

### Measures
- **Transport mix** across five buckets: `direct`, `relay`, `wifi`, `inbox`, `unknown`.
- **Per-transport send latency** (median / p95 / n), end-to-end from send-use-case entry.
- **Fallback-rung distribution**: `reuse`, `local_race`, `direct_race`, `relay_probe`, `inbox_fallback`, `failed`.
- **LAN-availability snapshot**: discovery active/inactive + discovered-peer count.

### Does NOT measure / structural limits (from confirmed risks)
- **1:1 only.** Every recording site fires only on the 1:1 path (`p2p_service_impl.dart:166`, `:176`; `send_chat_message_use_case.dart:150-155`). Group receive flows through a separate channel (`group_message:received` → `groupMessageStream`) that never touches `recordTransport`. A group-heavy session produces a misleadingly low/skewed `N`. Always label results "**1:1 transport mix**," never "app transport mix."
- **Delivered-only — NOT a success/health rate.** The mix counts only successfully-delivered sends with a concrete transport. A **failed** send increments only the `failed` rung — **no transport bucket, no denominator N** (`send_chat_message_use_case.dart:155` gates `recordTransport` behind `if (transport != null)`; failed exit at `:617` passes `transport: null`). **There is no per-attempt recording**: a direct/local race leg that fails before a relay/inbox win leaves **zero footprint**. A transport that always fails before falling back looks healthy or invisible. **Do not read a low direct share as "direct isn't needed."**
- **Session-scoped, lost on restart.** `TransportMetrics` is a plain in-memory object created once at `main.dart:1386`. App kill/restart/background-eviction zeroes everything. No persistence, no cross-launch aggregation. A multi-day dogfood yields **per-launch** numbers, not cumulative totals.
- **Latency is a sliding window.** Per-transport latency caps at the most recent **256 samples** (`transport_metrics.dart:143-149`); on long/high-volume sessions the median reflects only recent traffic, not the lifetime distribution.
- **Simulator cannot prove LAN/wifi.** The `wifi` bucket is fed **only** by the LAN WebSocket stream (`p2p_service_impl.dart:175-187`). Every simulator harness sets `DISABLE_LOCAL_DISCOVERY=true` (`reset_simulators.sh:39`, `:93`), so `_localP2P` is inactive and the wifi bucket is **structurally unreachable**. A sim `wifi=0` means **"not measured," not "LAN unused."** The Go-bridge receive path only ever yields `direct`/`relay`/`unknown` (`_inferTransportForPeer`, `:2172-2186`); it never produces `wifi`.

---

## 3. Where to Read the Numbers

On a **real build**, the only human-readable surface for the four percentages + per-transport median is the **Transport Diagnostics card** in Settings:

- Widget: `SettingsTransportDiagnosticsCard` (`lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`).
- It renders the full `baselineReport()` string inside a **copyable** `SelectableText` (`:204`, key `settings-transport-debug-report`), plus transport-mix counts, rungs, latency (median/p95/n), and LAN.
- **It snapshots metrics on `initState` and on the Refresh button only (`:40-51`) — values are NOT live. You MUST tap Refresh after sending, then copy.**

> **CRITICAL VISIBILITY GAP:** the card is gated behind `kDebugMode` (`settings_wired.dart:492-495`, `_buildDebugSection()` early-returns when `!kDebugMode`). In a **TestFlight / Play release build (`kDebugMode == false`) the card is NEVER shown** — a release tester has no way to read the census. The metrics are still recorded in memory, but `baselineReport()` is never emitted via flow events, so it is also **invisible in logs** on release. **Consequence:** to read the census you MUST run a **debug build** of the app on the device. Plan harvest sessions accordingly (see §5).

`baselineReport()` output looks like:
```
Transport mix (N=42): 50% direct, 20% relay, 25% wifi, 5% inbox, 0% unknown
Median latency: direct 120ms, relay 340ms, wifi 45ms, inbox -, unknown -
Fallback rungs: reuse 10, local_race 8, direct_race 18, relay_probe 4, inbox_fallback 2, failed 0
LAN: discovery active, 2 peers
```

---

## 4. Harvest Sources

Each row states what a source **credibly fills**, its setup/command, and its limitations. **Only a real-device run can fill `wifi` and real CGNAT `direct`-vs-`relay`. No simulator test or relay metric can fill those honestly.**

| Source | Credibly fills | Setup / command | Limitations |
|---|---|---|---|
| **Real-device dogfood (debug build, 2+ physical devices, same WiFi, mDNS enabled)** | **`wifi`/LAN (ONLY here)**, real CGNAT `direct` vs `relay` (ONLY here), `inbox`, `relay`, latency, rungs, LAN snapshot — the full census | Two real devices, debug build (so the diagnostics card is visible), local discovery ENABLED (do NOT set `DISABLE_LOCAL_DISCOVERY`). Drive a deliberate **1:1** send/receive mix across WiFi-co-located AND cross-network (cellular) sessions. Read via Settings → Transport Diagnostics → Refresh → copy. | Session-scoped/per-launch (capture before each kill). Delivered-only. 1:1 only. Latency windowed to last 256. |
| **TestFlight / Play release** | In principle the same real-world buckets | Release build distributed to testers | **CANNOT read the census** — card is `kDebugMode`-gated (`settings_wired.dart:493`) and report is never logged. Use TestFlight only to recruit dogfooders, then have them run the **debug** build for the actual read. Not a usable read surface as-is. |
| **Local integration tests** (`transport_e2e_test.dart`, `wifi_relay_fallback_smoke_test.dart`) | Validate **labeling + fallback logic** for `relay` and `inbox` (and opportunistic `direct`); corroborate that inbox store-and-forward works | `dart run integration_test/scripts/run_transport_e2e.dart -d <sim>` (real relay + Go CLI peer, fixture-coordinated); `dart run integration_test/scripts/run_wifi_relay_fallback_smoke.dart -p ios` | **Emit NO census.** Assert per-message labels with **set-acceptance** (`{direct,relay}` or `{direct,relay,inbox}`), so a `direct` that was actually `relay` still passes. `DISABLE_LOCAL_DISCOVERY=true` → **cannot fill wifi.** `direct` here is opportunistic loopback reachability, not a reliable direct census. |
| **Transport gate** (`scripts/run_test_gates.sh` → `run_transport_gate`) | Pass/fail of `TRANSPORT_TESTS` (background_reconnect, wifi_relay_fallback_smoke, transport_e2e, media_stable_id_smoke) | `scripts/run_test_gates.sh` (honors `FLUTTER_DEVICE_ID`) | **No aggregation, no census, no `TransportMetrics` readout.** `wifi_transport_test.dart` is NOT in this gate (it is NIGHTLY_ONLY). |
| **`wifi_transport_test.dart`** (NIGHTLY_ONLY) | Proves the LAN `LocalWsServer` WebSocket **mechanism** works in isolation (loopback) | `flutter test integration_test/wifi_transport_test.dart -d <device>` | **Useless as a wifi census source.** Never routes through `sendChatMessage`, never sets `transport=='wifi'`, never touches `TransportMetrics`. Proves the socket, not that mDNS discovered a peer or that LAN beat relay end-to-end. |
| **Relay `/metrics` cross-check** (`go-relay-server`, `:2112/metrics`) | **Corroborates the relay-transiting subset only:** `relay` bucket (`relay_active_streams`, `relay_stream_duration_seconds`, connection counters) and `inbox` bucket (`relay_inbox_stored/retrieved/expired/capped_total`, `relay_inbox_messages_pending`); failure rungs via `relay_stream_errors_total` | Relay serves `:2112/metrics` live (promhttp). Contract test: `cd go-relay-server && go test ./...` (runs `metrics_test.go`). | **Structurally blind to `direct` and `wifi`** (that traffic never transits the relay). Cannot tell what fraction went direct instead. Cannot distinguish 1:1-circuit vs group-circuit. `relay_inbox_stored_total` over-counts duplicate stores. It corroborates load, not the full mix. |

**Buckets ONLY a real-device run can fill:** `wifi`/LAN, and real cellular/CGNAT `direct`-vs-`relay` rates. Until a discovery-enabled multi-device debug session exists, `wifi` reads ~0% and **that zero is an artifact, not a finding.**

---

## 5. Recommended Harvest Procedure

Lead with real-device dogfood — the simulator cannot fill `wifi` or real CGNAT `direct`/`relay` credibly, and the only read surface (the diagnostics card) requires a debug build.

### Step 0 — Confirm prerequisites
1. Build a **debug build** (`kDebugMode == true`) so the Transport Diagnostics card is visible. A release/TestFlight build cannot be read.
2. Ensure local discovery is **enabled** (do NOT set `DISABLE_LOCAL_DISCOVERY=true`). Record this fact with every capture.
3. Recruit **two or more real physical devices** for the WiFi/LAN portion. Confirm they are on the **same WiFi** with mDNS permitted (and on iOS, Local Network permission granted — a denied permission is a silent LAN outage worth recording).

### Step 1 — Real-device dogfood (primary source)
4. On each device pair, drive a **deliberate 1:1 send/receive mix** (group messages do not count). Cover:
   - **WiFi-co-located** sessions (to populate `wifi` and LAN snapshot), and
   - **cross-network / cellular** sessions (to populate real `direct` vs `relay`).
5. Keep each session running long enough to accumulate samples (see minimum N below).

### Step 2 — Read & capture per launch (no persistence)
6. In each session, go to **Settings → Transport Diagnostics → tap Refresh → copy** the `baselineReport()` text (key `settings-transport-debug-report`).
7. **Capture the report immediately before every app kill, restart, or potential background-eviction** — a relaunch zeroes all counters. Treat each read as a **single-launch sample**.
8. Record alongside each capture: **device, network (wifi/cellular), `DISABLE_LOCAL_DISCOVERY` value, launch duration, approximate 1:1 message volume**, and whether iOS Local Network permission was granted.

### Step 3 — Aggregate across launches correctly
9. To approximate a multi-day census, **manually sum the raw transport and rung COUNTS** across all captures, then **recompute percentages from the summed counts.** Do **NOT** average per-session percentages (small-N sessions distort the mix).
10. Treat latency medians as **per-session and windowed to the last 256 samples** — do **NOT** aggregate latency across sessions from the rendered report (underlying samples are unrecoverable post-restart). Collect latency only from long-lived sessions.

### Step 4 — Cross-check the relay slice
11. Scrape the relay `/metrics` on `:2112` during/after the dogfood window. Confirm the client `relay`/`inbox` counts move in step with `relay_active_streams` / `relay_inbox_stored_total` / `relay_inbox_retrieved_total`. Note: relay metrics are **blind to `direct`/`wifi`** and `relay_inbox_stored_total` over-counts duplicates.

### Step 5 — Gate readiness check
12. Verify the **summed N** meets the minimum below before drawing any prioritization conclusion.

**Minimum N before trusting the gate**
- One message moves a bucket by ~`100/N` points.
- **N ≥ 50** for ±2pt-per-message resolution (general gating).
- **N ≥ 100** when a decision hinges on a `<10pt` gap between two transports.
- **Below N=50:** report **raw COUNTS only, never percentages**, and annotate the read as **low-confidence / insufficient N**.
- N is the count of successfully-delivered, transport-labeled **1:1** sends only. If the observed send attempts in logs materially exceed N, flag the delta as failed/unattributed sends and **exclude that run from direct-vs-relay prioritization** until attempt-level instrumentation exists.

---

## 6. Results Template

Fill one block per aggregation (summed across captured launches; see §5 Step 3). Attach the raw per-launch captures.

```
NET-REL-04 BASELINE CENSUS — RESULTS
=====================================
Aggregation window: ____ (date range)
Captures summed: ____ launches across ____ devices
Build type: debug  |  Local discovery enabled: YES / NO
Scope: 1:1 ONLY (group excluded by design); delivered-only

TRANSPORT MIX (recomputed from SUMMED COUNTS):
  ____% direct, ____% relay, ____% wifi, ____% inbox, ____% unknown   (N=____)
  Raw counts: direct ____, relay ____, wifi ____, inbox ____, unknown ____

MEDIAN SEND LATENCY (per transport; per-session, last-256 windowed — do NOT sum):
  direct ____ms, relay ____ms, wifi ____ms, inbox ____ms

FALLBACK RUNGS (summed counts):
  reuse ____, local_race ____, direct_race ____, relay_probe ____, inbox_fallback ____, failed ____

SEND ATTEMPTS (tried/failed per leg — the direct-vs-relay disambiguator):
  reuse ____/____, local ____/____, direct ____/____, relay_probe ____/____, inbox ____/____
  --> direct attempted but failing a lot (high direct failed/tried) means direct
      IS needed even if the delivered mix shows little/no direct.

LAN:
  discovery active/inactive: ____, discovered peers (max observed): ____
  iOS Local Network permission denied on any device? YES / NO

RELAY /metrics CROSS-CHECK (:2112):
  relay bucket vs relay_active_streams / relay_stream_duration_seconds: consistent? YES / NO
  inbox bucket vs relay_inbox_stored_total (note: over-counts dupes) / relay_inbox_retrieved_total: consistent? YES / NO

CONFIDENCE:
  N >= 50? ____   N >= 100 (if gap <10pt)? ____
  wifi measured (real-device, discovery-enabled)? YES / NO  [if NO, wifi% = N/A, NOT 0%]
```

---

## 7. Trust Caveats

- **Delivered-only mix hides failing transports** — **now instrumented (NET-REL-04 patch).** The transport *mix* is still a delivered-traffic share, not a success rate. But `TransportMetrics` now records a **per-leg attempt/failure count** for `reuse`/`local`/`direct`/`relay_probe`/`inbox` (the "Send attempts (tried/failed)" line in `baselineReport()`), so a `direct` leg that was tried and failed before relay won is no longer invisible. **Mitigation / how to read it:** read the per-leg `direct` tried/failed alongside the delivered mix — a high `direct` failure ratio means direct connectivity is failing and direct work is NOT unneeded, even when the delivered mix shows little/no direct. Still co-report `failed`, `relay_probe`, and `inbox_fallback` rungs. Note the attempt counters are aggregate-only (counts, no peer/latency per attempt); for per-attempt latency, cross-reference `CHAT_MSG_SEND_*` FLOW events.

- **Group traffic excluded (1:1 only).** Group/pubsub contributes zero samples. **Mitigation:** lead the report with the scope banner; require a deliberate 1:1 mix during harvest; report N prominently; always label the numbers "1:1 transport mix." A group transport-family census needs new native signal (TOM-004 residual) before group traffic can appear.

- **Simulator produces structurally false buckets.** Sims set `DISABLE_LOCAL_DISCOVERY=true` so `wifi` is unreachable; a fake-tier harness could only ever produce a synthetic `wifi`. **Mitigation:** record the run environment with every census; refuse to report `wifi%` from a discovery-disabled run (treat as N/A / "not measured," never "0% LAN usage"); tag T1-fake vs T3-real-wire and never cite a fake-tier wifi count as real-wire evidence; only harvest a trustworthy wifi figure from a discovery-enabled multi-device build. Cross-check `relay`/`direct` against Go `classifyStreamTransport` / `conn.Stat().Limited` before treating the split as ground truth (the receive path can emit `unknown`, and direct/relay come from multiaddr inference).

- **Percentage rounding & small N.** Integer percentages with no minimum-N guard; one message swings a bucket by ~`100/N` points, and the largest bucket absorbs all rounding remainder (reads slightly high). **Mitigation:** enforce N ≥ 50 (≥ 100 for `<10pt` gaps); below that report raw counts only; treat differences smaller than the per-message quantum and the ~4pt remainder-dump bias as noise; aggregate across sessions before reading the mix; annotate low-N reads as low-confidence; near a threshold, prefer raw counts.

- **In-memory, session-scoped, lost on restart.** No persistence, no cross-launch aggregation; a multi-day dogfood yields per-launch numbers and the largest aggregation windows are discarded on relaunch. **Mitigation:** capture `baselineReport()` before every kill/background-eviction; record launch duration / message volume per capture; approximate multi-day totals by **summing raw counts then recomputing percentages** (never average per-session percentages); treat latency as per-session, last-256-windowed, and non-aggregatable; flag in the prioritization writeup that any single read under-represents cumulative usage. The only robust scale fix is persistence (NET-REL-04 Option C opt-in aggregates), which does not exist today.

- **Release builds are unreadable (visibility gap).** The diagnostics card is `kDebugMode`-gated and the report is never logged, so TestFlight/Play testers cannot read or export the census. **Mitigation:** harvest from a **debug build** on real devices; use TestFlight only to recruit dogfooders, not as a read surface.
