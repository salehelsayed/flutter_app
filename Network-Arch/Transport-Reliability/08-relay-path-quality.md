# Relay-Path Quality (Cross-Network Latency & Reliability) — Problem & Tracking Doc

Prepared on: 2026-05-30
Status: **Proposed (scoping; no code changed)** — measurement-first; **justified by
the 2026-05-30 baseline** (cross-network ~100% relay @ ~1.1s — relay is the
cross-network lever). Phase 1 improvement is now baseline-justified, not gated.
Tracking ID: NET-REL-08

## Why this doc exists

The 2026-05-30 baseline gate (real-device harvest, N=50/condition, counted at
sender) found that **cross-network 1:1 is ~100% relay at ~1.1s median latency**
(1114 vs 297ms same-network — relay ≈ **3.8×** the same-network path), with
**0 direct, 0 hole-punch attempts, 0 relay→direct upgrades**. On that evidence:

- **NET-REL-02 (DCUtR)** production mobile relay→direct success remains unproven
  and is baseline-gated; **NET-REL-03 (relay springboard)** is deprioritized
  (RSD-001 *no-proceed*).
- **NET-REL-02 Option C** explicitly redirects effort to *"(1) LAN direct
  (NET-REL-01), (2) relay path latency/reliability, and (3) honest UX"*
  (`02-nat-traversal-dcutr.md:244-247`).

This doc scopes item (2): **the relay path is the dominant cross-network
experience, so its latency and reliability are the single highest-leverage
cross-network lever now that direct connections are ruled out for mobile-to-
mobile over cellular.** It is a *measurement-first* workstream: we cannot
improve the ~1.1s until we know where it goes.

**Binding safety rail (read first):** the relay is a **single shared host hard-
coded into every shipped app binary** with no version negotiation
(`go-mknoon/node/config.go:11,15`). Per **NET-REL-07**, every relay-touching
change must be **additive-only**; a genuinely breaking change must go via the
**multi-relay migration path**, never an in-place flip of the live host. This
constraint shapes every option below.

## Document Basis (evidence)

- `go-mknoon/node/config.go:11,15` — the two hard-coded relay endpoints
  (`mknoun.xyz` WSS `:4001`, QUIC `:4002`, fixed peer ID
  `12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`).
- `go-mknoon/node/config.go:21-25` — the frozen protocol-ID strings
  (rendezvous, inbox, chat, media, group-validation-feedback).
- `go-mknoon/node/config.go` — `DialTimeout = 15s` (relay connect),
  `RelayProbeTimeout = 5s`, `PeerDialTimeout = 2s`.
- `go-mknoon/node/relay_selector.go:20-56,206` — `RelaySelector`: groups
  multiaddrs by peer ID, preserves **insertion order**, provides try-each-relay-
  in-order **failover only**. No latency/health-based reordering, no per-relay
  scoring. `buildRelaySelector` (`:206`) is already wired into every inbox /
  group-inbox / media call site.
- `go-relay-server/metrics.go` — 40+ Prometheus metrics (served `/metrics:2112`),
  including the `relay_stream_duration_seconds` **histogram** (`:218-221`,
  buckets `0.01..30s`), `relay_connections_active/total`,
  `relay_inbox_stored/retrieved/expired/capped_total`, `relay_active_streams`,
  `relay_stream_errors_total`, media counters. **Aggregate, not per-send-leg.**
- `go-mknoon/node/relay_session.go` — relay reservation / refresh / watchdog
  state machine (the steady-state cost surface).
- `lib/features/conversation/application/send_chat_message_use_case.dart` —
  `relayProbeSendAttempts = 1` (post NET-REL-05 P5 consolidation); relay probe is
  the cross-network tail of the 1:1 send ladder.
- Cross-ref: **NET-REL-04** (client transport + per-leg latency census),
  **NET-REL-05** (send orchestration; the relay rung), **NET-REL-07** (the
  additive-only compatibility constraint), **NET-REL-06** (test doctrine).

## Current Behavior (Evidence)

- **One relay, multi-relay-capable client.** Only a single relay is shipped
  (`config.go`), but the client already supports N relays via `buildRelaySelector`
  + a shared Redis backend (the same mechanism NET-REL-07 designates for safe
  migration). So multi-relay is a *deployment* gap, not a client-code gap.
- **Selection is insertion-order, failover-only.** `RelaySelector` tries relays
  in the order they were added and merges addresses per peer ID; there is **no
  measured-latency or health-based reordering** and no per-relay success/RTT
  score (`relay_selector.go:20-65`).
- **Reservation/dial budgets are coarse.** `DialTimeout 15s` / `RelayProbeTimeout
  5s` / `PeerDialTimeout 2s` bound the path but are not decomposed or gated
  against a user-experience budget.
- **Observability is split and aggregate.** Relay-side Prometheus has a
  stream-duration histogram + connection/inbox counts, but nothing correlates a
  *single send's* relay sub-stages (reserve → circuit dial → first byte → relay
  queue). Client-side NET-REL-04 records the winning transport + per-leg latency
  but has **no relay-path decomposition**. So "where does the 1.1s go?" is
  currently unanswerable from telemetry.

## Problems Identified

### P1 — Relay-path latency is not decomposed
We measure total send latency (NET-REL-04) and relay stream duration (relay-side
histogram) but not the sub-components: reservation/refresh, circuit dial, first-
byte RTT, relay-side queueing. Without decomposition we cannot tell whether the
~1.1s is **path physics (RTT)** — i.e. largely irreducible — or **relay-side
processing/queueing** — i.e. tunable. This determines whether improvement is even
available.

### P2 — Single relay, no health/latency-based selection
One shared host is a single point of latency and failure. The selector is
insertion-order only, so a slow or overloaded relay degrades **all** cross-network
users with no client-side mitigation. Even with a second relay deployed, the
client would not currently prefer the faster/healthier one.

### P3 — Reservation/refresh cost on the steady-state path is unmeasured
Cross-network peers rest on relay for the conversation lifetime
(`03-relay-springboard.md:118`). Reservation refresh storms or churn
(`relay_session.go` watchdog) would add tail latency that is invisible today.

### P4 — Failover cost is unmeasured
The multi-relay migration path (NET-REL-07) and the failover helpers exist, but
the cost of failing over (detect-bad → re-reserve → re-dial) has no benchmark.
This number gates both reliability claims **and** the practicality of the
NET-REL-07 migration mechanism itself.

### P5 — No relay latency SLO / budget gate tied to UX
The relay-side metrics exist but there is no threshold/budget assertion (the Go
benchmarks `t.Logf` percentiles rather than `t.Fatalf`-gating them — NET-REL-06
§5 item 3). A relay-latency regression would ship silently.

## Impact

Cross-network is 100% relay, so **every millisecond of relay-path latency hits
every cross-network message**. At ~1.1s median (≈3.8× same-network) the relay
path is the largest cross-network UX cost remaining after direct connections were
ruled out. Reliability matters as much as latency: a relay outage or slowdown is a
total cross-network outage for un-updated users, which is exactly why NET-REL-07's
single-shared-host constraint makes the *client-side* levers (selection, failover)
and *additive* server levers the safe place to invest.

## Proposed Directions (options, measurement-first — NOT implementation)

### Phase 0 — MEASURE (all additive-only; no wire/contract change → NET-REL-07 SAFE)
- **M1 — Client relay-path decomposition.** Extend the NET-REL-04 census with
  additive per-stage timings (reservation, circuit dial, first byte) for the relay
  rung, so we can attribute the ~1.1s. Privacy-safe aggregate only (mirror the
  existing census discipline).
- **M2 — Relay-side per-stage histograms.** Leverage the existing
  `relay_stream_duration_seconds`; add (additive) stage histograms only if M1
  shows the cost is relay-side. Land the already-started `go-relay-server/
  metrics_test.go` asserting **deltas** on the global `promauto` counters
  (non-parallel; note `inbox.go` increments the store counter even on duplicates).
- **M3 — Failover & reservation-cost benchmarks → hard gates.** Use the in-process
  `integration/local_relay_harness_test.go` + `node/multi_relay_test.go` +
  `node/relay_session_test.go` + `node/benchmark_relay_recovery_test.go` seams to
  measure detect→re-reserve→re-dial cost and reservation/refresh churn, and
  **convert the benchmark `t.Logf` percentiles into `t.Fatalf` budget gates**
  (NET-REL-06 §5 item 3).

### Phase 1 — IMPROVE (only after Phase 0 shows headroom)
- **Option A — Client-side relay health/latency scoring (NET-REL-07 SAFE).**
  Add measured-RTT/success scoring to `RelaySelector` to **reorder already-known
  relays** and optionally probe relays in parallel for failover. This is pure
  client reordering of addresses the client already holds — **no protocol-ID,
  response-key, or framing change**, so it is additive and safe. *Caveat:* only
  meaningful once ≥2 relays exist (see Open Questions).
- **Option B — A second / faster relay via the multi-relay migration path
  (NET-REL-07).** Stand up a new relay (e.g. better-peered or geo-placed), ship it
  in **new** app builds alongside the old one, and retire the old relay only after
  telemetry shows old-app traffic has drained. **Never flip the live host.** This
  is the *only* NET-REL-07-compliant way to change "which relay" or its protocol.
- **Option C — Relay-side latency tuning (additive server config).** Tune limits
  (`limits.go`), connection/transport settings, or placement on the server without
  touching any wire contract. Additive/relaxing changes are NET-REL-07 SAFE.

### Explicitly OUT OF SCOPE (BREAKING per NET-REL-07 — would hit un-updated users)
Bumping any served **protocol-ID string** (`…/1.0.0`→`…/1.1.0`), renaming/retyping
any response key or `status` value, changing rendezvous protobuf field numbers, or
changing the 4-byte framing. Any of these must go via the **multi-relay migration
path**, never as an in-place change to the live relay.

## Acceptance Criteria / How We'll Know It's Fixed

1. **Decomposition:** we can attribute cross-network send latency to relay sub-
   stages (reservation / circuit dial / first byte / queue) from telemetry, and
   answer "is the ~1.1s RTT-bound or relay-bound?"
2. **Selection:** a deliberately slow relay is detected client-side and (when ≥2
   relays exist) deprioritized; the measured failover cost is under a defined
   budget. **Negative control:** a healthy relay stays primary (scoring is not
   always-reorder).
3. **Compatibility:** any relay change passes a NET-REL-07 **old-client contract
   test** (frozen protocol IDs + response keys + `status` values). **Negative
   control:** a renamed field/`status`/protocol-ID makes the contract test FAIL.
4. **Budget gates:** relay reservation/dial/first-byte have `t.Fatalf` threshold
   gates, not `t.Logf` — a regression past budget fails CI.
5. **No regression:** single-relay users are unaffected; selection reordering never
   drops a working relay; the NET-REL-05 relay rung still delivers.

## Test Plan (grounded in NET-REL-06)

Apply the **negative-control principle** and **path-pin the relay** throughout —
assert `conn.Stat().Limited == true` (a real circuit) for any relay-specific
claim; never accept the `{direct, relay, inbox}` set for a relay-path assertion.

- **Go (real-stack, isolated):** `integration/local_relay_harness_test.go` (in-
  process relay, no external dep), `node/multi_relay_test.go` (failover ordering),
  `node/relay_session_test.go` (reservation/refresh/watchdog),
  `node/benchmark_relay_recovery_test.go` (convert to budget gates),
  `integration/relay_test.go` (real relay, skip-if-unreachable).
- **Relay server:** `go-relay-server/metrics_test.go` — assert **deltas** on the
  global `promauto` metrics, run **non-parallel** (note `inbox.go` increments the
  store counter even on duplicate stores). PLUS the NET-REL-07 **frozen-contract
  snapshot test** (BUILD): pin the served protocol-ID set + response JSON keys +
  `status` values; a rename must fail it.
- **Latency budgets:** convert `benchmarkPercentile` p50/p95 `t.Logf` output into
  `t.Fatalf` threshold assertions for the budgets Phase 0 establishes.
- **Selection negative controls:** slow-relay injection must reorder/deprioritize
  it (control: a healthy relay stays primary); failover cost measured against a
  budget; an old-client request shape must still parse the new relay's responses.
- **Client (Dart):** extend the NET-REL-04 census assertions with exact per-stage
  expected values (not "counter > 0"); guard the default-to-`relay` bias (an
  *unknown* transport must not be silently bucketed as relay — NET-REL-04 §6).

## Hard Constraints (binding — NET-REL-07)

1. Treat **protocol-ID strings, `status`/action/response-key names, push `data`
   keys, and Redis record field names as FROZEN.** Only add, never rename/remove/
   retype.
2. **Additive-only** for every protocol and storage change. Adding Prometheus
   metrics, logging, optional fields, or relaxing limits is explicitly SAFE.
3. **Any genuinely breaking change uses the multi-relay migration path** (new
   relay shipped in new builds via `buildRelaySelector` + shared Redis; old relay
   retired only after old-app traffic drains). **Never flip the live single host.**
4. **Prove non-breaking with an old-client contract test** (frozen-contract
   snapshot + current-client-shape replay), with a negative control that fails on a
   deliberate rename.

## Dependencies / Sequencing

- **Justified by the 2026-05-30 baseline harvest** (real-device, N=50/condition):
  cross-network ~100% relay @ ~1.1s median (≈3.8× same-network) is exactly what makes
  relay-path quality the highest-ROI cross-network lever. A further discovery-enabled
  real-device read still gives the best before/after numbers, but 08 is **no longer
  gated** on it — both Phase 0 measurement and Phase 1 improvement are baseline-justified.
- **Builds on:** NET-REL-04 (census), NET-REL-05 (the relay rung;
  `relayProbeSendAttempts = 1`), NET-REL-07 (compatibility).
- **Supersedes** the deprioritized NET-REL-03 as *the* cross-network workstream;
  it is the concrete realization of NET-REL-02 Option C.

## Open Questions

1. **Single-relay today:** is client-side health-scoring (Option A) meaningful
   before a second relay exists, or is Phase 1 effectively gated on first standing
   up a 2nd relay via the migration path (Option B)?
2. **Where does the 1.1s go?** Is it dominated by path RTT (physics, largely
   irreducible) or relay-side processing/queueing (tunable)? M1/M2 answer this and
   decide whether *any* improvement is available — this is the pivotal measurement.
3. **Geo/placement:** if a second relay helps, where should it live for the user
   population, and how do we route to the nearest without a wire-contract change?
4. **Target budget:** what cross-network latency is "good enough" relative to the
   ~1.1s baseline, and what is the relay reservation/dial/first-byte budget?
5. **Migration ergonomics:** is the failover cost (P4) low enough that the
   NET-REL-07 multi-relay migration is operationally practical, or does it need
   work first?

## References

- Code anchors in **Document Basis** above.
- **NET-REL-02** (`02-nat-traversal-dcutr.md`, Option C = the redirect target;
  baseline gate), **NET-REL-03** (`03-relay-springboard.md`, RSD-001 no-proceed),
  **NET-REL-04** (transport census — the measurement substrate),
  **NET-REL-05** (`05-send-orchestration.md`, the relay rung / `relayProbeSendAttempts`),
  **NET-REL-06** (`06-test-and-simulation-strategy.md`, negative-control doctrine),
  **NET-REL-07** (`07-relay-backward-compatibility.md`, the binding additive-only rule).
- Relay-side metrics plan: `UI-Grafana/privacy-safe-business-graf.md` (HyperLogLog
  aggregate-only), `go-relay-server/metrics.go` (live Prometheus surface).

## Changelog

- **2026-05-30 — NET-REL-08 scoped (this doc created).** Authored as the cross-
  network workstream after the baseline gate (cross-network ~100% relay, ~1.1s
  median, 0 hole-punch upgrades) deprioritized DCUtR/NET-REL-03 (RSD-001) and
  NET-REL-02 Option C redirected effort to relay-path latency/reliability.
  Measurement-first; all directions constrained to additive-only per NET-REL-07.
- **2026-05-30 — Re-baselined from "gated" to "justified" + indexed.** The
  NET-REL-04 baseline harvest is done (cross-network ~100% relay @ ~1.1s), so 08 is
  now justified-by-baseline rather than gated on it. NET-REL-08 row + dependency-graph
  edge + changelog applied to `00-INDEX.md`.
