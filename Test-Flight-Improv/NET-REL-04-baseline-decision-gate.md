# NET-REL-04 — Baseline Decision-Gate

**Type:** Decision-gate procedure (consumes the harvested transport census; orders NET-REL-01/02/03/05)
**Status:** Pre-harvest. Hypothesis pre-filled from confirmed code posture; final decision pending the harvested number.
**Scope of the census this gate reads:** 1:1 conversation sends/receives + LAN wifi only. Group (GossipSub/pubsub) traffic contributes **zero** samples (TOM-004, by design). Treat every number below as **"1:1 transport mix,"** never "app transport mix."

## DCUTR-004 Closure Note

Recorded: 2026-05-30 CEST

This decision gate remains **pre-harvest / unavailable** for NET-REL-02 and
NET-REL-03 product decisions. DCUTR-001/002/003 provide accepted evidence for
Go hole-punch tracing, Dart aggregate diagnostics, and relay-only/no-upgrade
relay/recovery behavior, but no concrete valid repo-local baseline artifact was
found that proves production mobile relay-to-direct DCUtR success.

A valid artifact for this gate must be a real-device, discovery-enabled,
debug-mode, 1:1-focused `baselineReport()`/decision-gate capture with raw
counts, hole-punch attempt/success/failure counts, relay-to-direct upgrade
count, and enough metadata to satisfy the validity rules below. Simulator, CLI,
loopback, LAN direct, and reliability-sim evidence is relay/recovery liveness
or protocol-feasibility evidence only; it is not physical mobile NAT traversal
proof.

Do not reorder NET-REL-01/02/03/05 from the hypotheses in this document until a
valid harvest fills the table below. The repeated DCUTR-003
`run_transport_e2e.dart` E8 media metadata residual is tracked as an external
orchestrator residual: attempted twice; Flutter `33/33 passed`; 69-byte blob
downloaded; external summary `29/30 passed` with `messageSeen=false`,
`attachmentReferenced=false`, and `blobInList=false`.

## RSD-001 NET-REL-03 Decision Check

Recorded: 2026-05-30 CEST.

RSD-001 checked this gate for relay springboard direct-escalation readiness.
`flutter devices --machine` showed physical mobile devices are available, but
device availability is not a harvested census. No repo-local valid
real-device, discovery-enabled, debug-mode, 1:1-focused `baselineReport()` or
filled decision-gate artifact was found. Therefore NET-REL-03 has no proceed
verdict, and RSD-002/RSD-003 remain prerequisite-blocked until this table is
filled from a valid harvest.

---

## 1. The Gate

The census is the single in-memory, session-scoped `TransportMetrics.baselineReport()` read on-device from the (kDebugMode-only) settings diagnostics card. Once it has been harvested per the runbook's results template, fill the table below and then apply the rules.

### 1.1 Harvested census (fill from runbook results template)

| Field | Value | Source |
|---|---|---|
| Run environment (sim/CI vs **two real devices, one WiFi**) | `____` | runbook |
| `DISABLE_LOCAL_DISCOVERY` | `____` (must be `false` for any wifi reading) | runbook |
| Census tier | `____` (T1 fake / T3 real-wire) | runbook |
| N (`totalTransportSamples`, delivered 1:1 only) | `____` | baselineReport mix line |
| direct % / count | `____` | mix line |
| relay % / count | `____` | mix line |
| wifi % / count | `____` | mix line |
| inbox % / count | `____` | mix line |
| unknown % / count | `____` | mix line |
| Rungs: reuse / local_race / direct_race / relay_probe / inbox_fallback / **failed** | `____` | rungDistribution |
| Median (p95) latency: direct / relay / wifi / inbox | `____` | latency line |
| LAN snapshot: discoveryActive, discoveredPeerCount | `____` | LAN line |
| iOS Local Network permission denied? (any fraction) | `____` | NET-REL-01 P4 signal |
| Sessions summed (count + per-session N) | `____` | cross-session sum of raw COUNTS |
| Cross-network sub-slice harvested? (deliveries where peers were NOT co-located) | `____` | runbook |

### 1.2 Gate rules (apply in order)

1. **Validity gate first.** If any "What could invalidate the gate" condition (§4) holds — sim/CI run, `DISABLE_LOCAL_DISCOVERY=true`, T1 fake tier, N below the minimum-N floor, group-heavy session, single short session not summed across launches — then **do not act on the number.** Re-harvest under a valid configuration. A failed validity gate produces no reordering.
2. **Minimum N.** Require N ≥ 50 before reading any percentage (N ≥ 100 if a decision turns on a <10pt gap). Below the floor, report raw **counts only** and treat the mix as low-confidence. One message moves a bucket by ~100/N points; the largest bucket absorbs all rounding remainder (reads slightly high by construction).
3. **Read percentages as delivered-traffic share, not transport health.** Always co-report the `failed`, `relay_probe`, and `inbox_fallback` rung counts next to the mix. Failed sends and the losing legs of a successful race are recorded nowhere, so a transport that always fails before fallback looks invisible/healthy. A low direct share does NOT prove direct is unneeded.
4. **Apply the decision matrix (§2)** per NET-REL item using the validated signals.
5. **Cross-check the relay/inbox slice** against the relay `/metrics` on `:2112` (relay duration histogram, inbox stored/retrieved/expired). The relay is structurally blind to direct/LAN, so it can only corroborate the relay-transiting subset.

---

## 2. Decision Matrix

Each row encodes the user's logic explicitly. Actions: **prioritize / proceed / deprioritize / skip.**

| NET-REL item | Census signal | Threshold that flips the decision | Resulting action | Rationale |
|---|---|---|---|---|
| **04 — Observability (this doc / the census itself)** | It IS the census; not a consumer. | N/A — it is the decision-maker, ships first. Internal-only tradeoff: if on-device diagnostics prove insufficient to read the real network mix, escalate to Option C opt-in aggregates. | **Prioritize (unconditionally first)** + finish residuals | "You cannot improve what you cannot see." Options A/D and the DCUTR hole-punch tracer counters are accepted as repo evidence, but THIS gate still needs a valid real-device harvest of those counts before 02/03 decisions can act on them. The relay **1:1-vs-group circuit label** remains outside this DCUTR closure. |
| **02 — NAT traversal / DCUtR (direct)** | Cross-network 1:1 **direct vs relay** split + hole-punch attempt/success counts. | If cross-network deliveries are **almost all relay** (expected: `ForceReachabilityPrivate()` at node.go:315 self-suppresses DCUtR + cellular CGNAT symmetric NAT cannot hole-punch) → the expensive **Option B** (relax `ForceReachabilityPrivate`) and **Option D** (WebRTC) are not worth it. **Flip the other way only** if a non-trivial fraction of cross-network pairs sit on WiFi/cone-NAT where upgrades would succeed if attempted. | **Deprioritize / skip → adopt Option C "accept relay as steady state"** for cross-network. **Proceed regardless** with Option A (cheap hole-punch instrumentation — "do regardless"). | The user's primary lever. Relay-first + CGNAT means direct is structurally rare cross-network; chasing it earns its risk (AutoRelay churn / mis-detection) only if the census surfaces a real upgradeable population. The negative control (zero hole-punch success, no reachable address) is the dominant expected case. |
| **03 — Relay springboard → direct (escalation)** | Same direct/relay cross-network split as 02, plus a new `peer:transport_upgraded` telemetry + time-on-relay. | **Tied to 02.** If cross-network is almost all relay due to symmetric/CGNAT → no escalation option reliably yields direct → deprioritize. Flips toward implementation only if the census shows a **material population of upgradeable (cone-NAT / port-mapped) cross-network peers** where springboarding cuts latency and relay egress. | **Deprioritize / skip (inherits 02's gate)**; if it ever proceeds, **Option D bounded backoff ledger is non-negotiable** (battery guardrail). | Downstream of 02 — shares the `ForceReachabilityPrivate` relax decision. Relay is correct for symmetric-NAT peers; the only win is concentrated on LAN/port-mapped/cone-NAT peers. Adds a standalone relay-cost-at-scale argument (relay carries all cross-network 1:1 bytes indefinitely). |
| **01 — LAN / same-WiFi reliability** | LAN hit-rate (% of **co-located** pairs that actually deliver as `transport:'wifi'` within the discovery window) + `LanAvailabilitySnapshot` (discoveryActive, discoveredPeerCount) + iOS permission-denied fraction. | If **wifi is rarely used even when peers are co-located** (low wifi share / low discovered-peer count despite co-location) → high fixable headroom → **rises**. If wifi share is already high whenever co-located → marginal value small → drops. A meaningful permission-denied fraction (silent LAN outage) **by itself** justifies P4. | **Prioritize if low co-located wifi usage; deprioritize if already high.** Requires a **two-real-device, discovery-enabled** harvest — a sim wifi figure is N/A, not 0%. | The item the user singled out as "quantifies how much NET-REL-01 helps." LAN is the only direct transport that physically works today, and the gap (discover-on-send, TTL, media wiring, permission detection) is contained and fixable. |
| **05 — 1:1 send-path orchestration (unhappy path / latency)** | Per-transport send latency (median/p95) **and** the fallback-rung distribution (reuse / local_race / direct_race / relay_probe / inbox_fallback / failed). | If the **happy path** (reuse/local_race/direct_race) dominates and the unhappy tail (relay_probe → inbox_fallback) is rare and/or already fast → unhappy-path work (P1 concurrent durable fallback, P2 grace window) is low-value. **Rises** if a meaningful share of sends fall to the sequential relay-probe→inbox tail with high p95 (the visible "long sending…"). | **Deprioritize tail work if tail is rare/fast; prioritize if tail is frequent/slow.** **P3 (sticky/learned per-peer transport) is the most census-robust sub-item** — prioritize independently if median first-message latency to repeat peers is high (full race/discovery re-runs each time), regardless of the direct/relay verdict. | "The latency split tells whether the unhappy-path work matters." P3's win exists whatever the mix shows, so it is the safest bet under census uncertainty. |

---

## 3. Pre-Filled Hypothesis (to be confirmed by the harvested number)

**Confirmed code posture:** `ForceReachabilityPrivate()` **IS set** in production (go-mknoon/node/node.go:315), with AutoRelay always seeking reservations, every 1:1 send opening its stream `WithAllowLimitedConn` (happy to ride a circuit), and self-heal re-dialing the relay circuit rather than a direct address. `EnableHolePunching()` is on but, per the docs, "configured against itself" — `ForceReachabilityPrivate` prevents advertising reachable addresses, so DCUtR self-suppresses. The default-to-relay census bias is fixed (`p2p_service_impl.dart:165` now defaults to `'unknown'`), so the census itself is unbiased.

**Expected outcome (HYPOTHESIS — not yet a finding):**

- **Cross-network 1:1 traffic will be almost entirely `relay`**, with `direct` cross-network near zero, driven by `ForceReachabilityPrivate` + cellular CGNAT symmetric NAT. Hole-punch success counts are expected to be ≈ 0 cross-network, but only a valid harvest can confirm that.
- **`direct` that does appear will be LAN/loopback-adjacent**, i.e. the pre-relay LAN address dial of NET-REL-01, **not** a DCUtR upgrade.
- **`wifi` will read ≈ 0% in any sim/discovery-disabled harvest** — this is a structural artifact (missing data), NOT evidence LAN is unused. A true wifi figure requires the two-real-device discovery-enabled run.
- **`unknown` should be ≈ 0%** if labels survive the bridge; any nonzero unknown is itself a useful signal of a non-Go source or dropped transport field.

**Likely resulting reordering, IF the hypothesis is confirmed by the number:**

1. **NET-REL-02 and NET-REL-03 deprioritize / skip** toward "accept relay as steady state" (02 Option C) only if the valid harvest confirms the relay-dominant hypothesis. Hole-punch instrumentation exists; the remaining work is harvesting trustworthy counts, not inferring them from simulator or loopback proof.
2. **NET-REL-01 rises** — pending the co-located wifi hit-rate and permission signal from a real-device run, which the current posture cannot pre-decide.
3. **NET-REL-05 P3 (sticky transport) rises** independently; the rest of NET-REL-05's tail work is sized by the rung/latency split.

**This is a hypothesis, not a verdict.** It must be confirmed by the harvested number under a valid configuration. In particular, the cross-network relay-dominance claim and the NET-REL-01 sizing **cannot** be settled by the confirmed code posture alone — only the real-device census with the now-available hole-punch tracer counts can confirm or refute them.

---

## 4. What Could Invalidate the Gate

Any one of these means the harvested number must **NOT** be acted on yet.

1. **Invisible in release / TestFlight.** The diagnostics card is gated behind `kDebugMode` (settings_wired.dart:493) and `baselineReport()` is never emitted via flow events. A TestFlight/release tester cannot read the four percentages or per-transport median, and nothing logs them. → A real-world dogfood census requires a **debug-mode build** (or shipping a release-visible surface) before any number can be harvested at all.

2. **Sim/CI census produces structurally false buckets.** Every sim build sets `DISABLE_LOCAL_DISCOVERY=true`, so `_localP2P` is inactive and the **wifi bucket is unreachable** — `wifi==0` from a sim is "not measured," **not** "0% LAN usage." A rigged T1 fake (`'local'→wifi`) is a decision-logic artifact, not a real wire. → Refuse any wifi% from a discovery-disabled or T1 run. A trustworthy wifi/LAN figure requires **two real physical devices on one WiFi with mDNS enabled**, plus the negative control (LAN blocked, relay reachable → must NOT report local).

3. **Delivered-only mix hides failing transports — now instrumented (NET-REL-04 patch).** The delivered mix still only counts successfully-delivered sends with a concrete transport. The blind spot it used to create is now covered by **per-leg attempt/failure counts** (`attemptCounts()` / `attemptFailureCounts()`, surfaced in the report's "Send attempts (tried/failed)" line): a `direct` leg tried and failed before `relay` won is now counted. → Do not read the delivered mix as a success rate. **Read the per-leg `direct` tried/failed before applying the 02/03 deprioritization:** a low delivered-`direct` share with a *high direct attempt-failure ratio* means direct is failing, not unneeded — that strengthens, not weakens, the case to keep direct/NAT work. Only deprioritize 02/03 when direct is both rarely delivered AND rarely/never failing-when-tried (i.e. relay is genuinely the steady state, not masking a broken direct path). Still corroborate with `relay_probe`/`inbox_fallback`/`failed` rungs and relay-side counters.

4. **Census is 1:1-only; group traffic excluded.** No `TransportMetrics` recording site fires on the group path (TOM-004, by design). A group-heavy tester yields a misleadingly low/skewed N that reflects only 1:1 traffic. → Require a deliberate **1:1 send/receive mix** during the baseline session and label all gating numbers "1:1," never "app."

5. **Small N / percentage rounding.** No minimum-N guard exists; one message swings a bucket by ~100/N points (N=3 → 17pt per message), and the largest bucket absorbs the rounding remainder (up to ~4pt, reads slightly high). → Enforce N ≥ 50 (≥100 for <10pt gaps); below that, raw counts only. Treat sub-(100/N) differences as noise.

6. **Session-scoped, lost on restart; no persistence.** `TransportMetrics` is recreated each `main()` and zeroed on every relaunch; latency is a ring-buffer capped at the **last 256 samples per transport**. A multi-day dogfood yields per-launch numbers, not cumulative totals. → Capture `baselineReport()` before each kill/restart; approximate multi-day by **summing raw COUNTS across sessions and recomputing percentages** (never average per-session percentages). Treat latency as per-session, windowed to the last 256 samples — collect it from long-lived sessions only and do not aggregate it across restarts.

7. **Relay cross-check is partial by construction.** The relay `/metrics` on `:2112` is blind to direct/LAN traffic and cannot distinguish 1:1-circuit vs group-circuit; its inbox store counter over-counts duplicate stores. → Use it to corroborate the relay/inbox slice only; never treat it as the full mix.

**Bottom line:** the number is actionable only when harvested in a **real-device, discovery-enabled, real-network, debug-mode** session with N above the minimum-N floor, with 1:1 traffic deliberately driven, counts summed across launches, the rung distribution reported alongside the mix, and the hole-punch tracer counts available to settle the 02/03 cross-network question. Absent those, fill the table, fail the validity gate, and re-harvest — do not reorder NET-REL-01/02/03/05.
