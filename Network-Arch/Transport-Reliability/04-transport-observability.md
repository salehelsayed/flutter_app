# Transport Observability & Metrics — Problem & Tracking Doc

Prepared on: 2026-05-29
Status: Proposed (investigation complete, no code changed)
Tracking ID: NET-REL-04

## Executive Summary

We cannot currently **see**, in aggregate, which transport our messages use.
There is a per-message `transport` label (`direct` / `relay` / `wifi` / `inbox`)
flowing from Go to Dart and persisted on the `messages` table, but there is **no
counter, ratio, time-series, or telemetry** that answers "what fraction of
messages go direct vs relay vs LAN vs inbox, and how does that change over time."
Worse, the Dart layer **defaults a missing transport label to `'relay'`**
(`p2p_service_impl.dart:159`), which biases any post-hoc tally toward relay.

This is foundational: every other workstream in this folder (LAN reliability,
NAT traversal, relay springboard, send orchestration) proposes changes whose
success is defined in terms of *transport mix and latency*. We cannot tell if any
of them work without first being able to measure the baseline. This doc
catalogs what telemetry exists, what's missing, and how to add privacy-safe
visibility — consistent with the app's E2E/privacy posture and the **already
implemented** relay-side metrics suite (`go-relay-server/metrics.go`, served live
on `/metrics` port 2112; the `UI-Grafana/privacy-safe-business-graf.md` plan has
since shipped). The gap is on the **client**, not the relay.

> **QA correction (2026-05-29):** An earlier draft described the relay metrics as
> "a plan." That is wrong — `go-relay-server/metrics.go` declares 40+ Prometheus
> metrics (including a `relay_stream_duration_seconds` latency histogram,
> `relay_connections_active`, inbox store/retrieve/expire counters, media bytes,
> rendezvous, stream errors), `business_metrics.go` implements the HLL DAU/WAU/MAU,
> and `main.go:204-211` serves them. Relay-side observability largely **exists**;
> the real gap is (a) no **client-side** transport census/latency aggregation and
> (b) no metric that classifies relay traffic as 1:1-circuit vs group-circuit.

## Why This Is Foundational

- **NET-REL-01** success = "same-WiFi pairs use the `wifi` transport within a
  bounded window." Needs a transport census + LAN-hit-rate.
- **NET-REL-02 / NET-REL-03** success = "relayed connections upgrade to direct
  where feasible" and "we know how often we're stuck on relay." Needs a
  direct/relay census + hole-punch attempt/outcome counts.
- **NET-REL-05** success = "unhappy-path latency drops." Needs per-transport
  send-latency timing.

You cannot improve what you cannot see. Instrumentation should arguably ship
first.

## Document Basis

- `go-mknoon/node/node.go` — transport label set on inbound (`:1510`), conn
  watcher emits `peer:connected` with `limited` (`:1612-1690`),
  `classifyStreamTransport` (`:111-124`).
- `go-mknoon/bridge/bridge.go` — `node:send` response includes `transport`
  (~838-860).
- `go-mknoon/node/event_dispatcher.go` — event queue; `transport` is a
  critical-event identifier field (`:224-246`); critical vs coalesced events
  (`:63`, `:72`, `:126-134`).
- `go-mknoon/node/pubsub.go` — group diagnostic events `group:discovery`,
  `group:publish_debug`; group `transport` labels.
- `lib/core/services/p2p_service_impl.dart` — `transport` consumption,
  **default-to-`'relay'`** (`:159`), send transport read (`:1210-1221`).
- `lib/features/conversation/domain/models/conversation_message.dart` — `transport`
  persisted (`:54`, `:102-124`); migration `012_transport_column.dart`.
- `lib/features/conversation/application/retry_failed_messages_use_case.dart` —
  reads `transport == 'inbox'` for retry routing (`:190`).
- `emitFlowEvent` — structured FLOW logging used throughout Dart (the de-facto
  client log channel; sinks to logs, not a metrics backend).
- `go-relay-server/metrics.go` — **implemented** Prometheus metrics (40+:
  `relay_connections_active/total`, `relay_active_streams{proto}`,
  `relay_inbox_stored/retrieved/expired/capped_total`, `relay_media_*`,
  `relay_rendezvous_*`, `relay_group_inbox_*`, `relay_stream_errors_total{proto,kind}`,
  latency histogram `relay_stream_duration_seconds{proto,result}`).
- `go-relay-server/business_metrics.go` — HLL DAU/WAU/MAU (the Grafana plan, shipped).
- `go-relay-server/main.go:204-211` — live `/metrics` endpoint on :2112.
- `UI-Grafana/privacy-safe-business-graf.md` — the original (now-shipped) plan.
- Per-send latency components: Go returns `streamOpenMs`/`writeMs`/`ackWaitMs`
  in the `node:send` response (`bridge.go:853-855`), carried in
  `SendMessageResult` (`lib/features/p2p/domain/models/send_message_result.dart:7-9`)
  and folded into `stepTimings` in `send_chat_message_use_case.dart` (~323, ~835,
  ~924) — but **logged via emitFlowEvent, never aggregated/bucketed**.
- `message:direct_ack_timing` event (`node.go:1525`, `waitMs`/`outcome`) — existing
  latency-adjacent diagnostic not previously listed.
- `lib/core/debug/` — `e2e_test_mode.dart`, `intro_e2e_runner.dart`,
  `smoke_test_runner.dart` (debug harnesses, no transport dashboard).

## Current Behavior (Evidence)

### The transport label flow
- **Go sets it:** outbound `node:send` response carries
  `"transport": sendResult.Transport` (`bridge.go` ~852); inbound
  `message:received` sets `transport` (`node.go:1510`). Value from
  `classifyStreamTransport` (`/p2p-circuit` → `relay` else `direct`).
- **Group/LAN variants:** group events carry transport labels; local incoming
  messages are tagged `transport:'wifi'` (`p2p_service_impl.dart:168-179`).
- **Dispatcher treats it as critical:** `event_dispatcher.go:231` lists
  `transport` among critical identifier fields preserved even under queue
  pressure.
- **Dart consumes per-message only:** `p2p_service_impl.dart:159`
  `msg.transport ?? _inferTransportForPeer(msg.from) ?? 'relay'` — **defaults to
  `'relay'`** when unknown; read on send (`:1210-1221`); persisted to
  `messages.transport`; used in retry routing (`retry_failed_messages:190`).

### What does NOT exist
- No counter/gauge/histogram of transport mix on the **client**.
- No hole-punch attempt/outcome observation (NET-REL-02).
- No per-transport send-latency measurement.
- No LAN-discovery hit-rate or permission-denied signal (NET-REL-01).
- No client-side metrics backend. `emitFlowEvent`
  (`lib/core/utils/flow_event_emitter.dart:166-183`) only `debugPrint('[FLOW]…')`,
  gated by `kDebugMode` — diagnostic text, not aggregated, and off in release.
- Note: the **relay** already exposes transport/operational quality metrics
  (stream duration histogram, active streams by proto, stream errors by kind,
  connection churn, inbox rates) — so observability is missing on the **client**,
  and the relay lacks only a 1:1-vs-group circuit classification. This is a
  narrower gap than "no metrics anywhere."

## Problems Identified

**P1 — No aggregate transport census.** Can't answer direct/relay/wifi/inbox
split. *Impact:* baseline unknown; improvements unmeasurable.

**P2 — Default-to-`'relay'` biases any tally.** `p2p_service_impl.dart:159`.
*Impact:* even a manual SQL count over `messages.transport` over-reports relay
and under-reports direct/unknown.

**P3 — No hole-punch / upgrade observability.** (Shared with NET-REL-02/03.)
*Impact:* can't tell if direct upgrades ever happen.

**P4 — Per-send latency components exist but are never aggregated or bucketed by
transport.** Go already returns `streamOpenMs`/`writeMs`/`ackWaitMs` and the relay
has a `relay_stream_duration_seconds` histogram, but on the client these values
flow into `emitFlowEvent` step-timing logs and vanish — no per-transport median/
p95, no persistence. *Impact:* can't quantify the UX cost of relay vs direct vs
the unhappy-path ladder (NET-REL-05) without re-deriving from scattered logs.

**P5 — No LAN availability signal.** Can't detect denied iOS Local Network
permission or discovery failures (NET-REL-01 P4). *Impact:* silent LAN outages.

**P6 — Telemetry is per-event text, not queryable.** FLOW logs aren't aggregated
into anything we can chart. *Impact:* analysis is manual log-grepping.

## Metrics We Need (and feasibility today)

| Metric | Why | Obtainable now? | What's missing |
|---|---|---|---|
| Transport mix per message (direct/relay/wifi/inbox) | Baseline for all workstreams | Partial (label exists, biased) | Remove default-to-relay bias; aggregate counter |
| Connection-level direct/relay census | NET-REL-02/03 | No | Track per-connection transport over lifetime, not per-send sample |
| Hole-punch attempts & successes | NET-REL-02/03 | No | Subscribe to holepunch tracer/events (go-libp2p v0.39.1 `holepunch.WithTracer`) |
| Relay→direct upgrade transitions | NET-REL-03 | No | New event on transition; connection lifetime tracking |
| Send latency by transport | NET-REL-05 | No | Time send start→ack, bucket by transport |
| LAN discovery hit-rate / permission-denied | NET-REL-01 | No | Count discovered-peer presence, detect denied Local Network permission |
| Relay reservation health over time | NET-REL-02 | Partial (state machine exists) | Surface `relay_session.go` aggregate state as a time-series |
| Unhappy-path fallback rate (race-fail → relay-probe → inbox) | NET-REL-05 | No | Count which rung delivered each message |

## Privacy Constraints

This is a privacy-focused E2E app. Any telemetry **must**:
- Carry **no message content** and **no recipient/sender identity** beyond what
  is operationally necessary; transport metrics should be **aggregate-only**
  (counts, ratios, histograms) — never per-conversation traces leaving the device.
- Prefer **local-only** diagnostics (on-device counters surfaced in a debug
  screen) or **opt-in** anonymous aggregates.
- Follow the precedent already set by `UI-Grafana/privacy-safe-business-graf.md`:
  hash-and-discard identifiers, HyperLogLog for uniques, no stored peer IDs, no
  behavioral profiles. Transport-quality metrics fit naturally as
  **relay-side aggregate gauges/counters** (e.g. `relay_circuit_active`,
  `relay_messages_relayed_total`) and **client-side local counters**.

## Impact

Without this, the other four docs are unfalsifiable: we'd be changing connection
policy and discovery on intuition with no feedback loop. With it, we can (a)
establish a baseline transport mix, (b) decide whether NAT traversal effort is
worthwhile (NET-REL-02 Option C vs B), and (c) prove LAN and orchestration
improvements actually moved the numbers.

## Proposed Directions (options, NOT implementation)

**Option A — On-device diagnostics first (cheapest, fully private).** Add local
counters for transport mix, fallback-rung-used, send latency by transport, and
LAN availability; surface in a developer/debug screen (`lib/core/debug/`).
*Tradeoffs:* visible only to the user/dev, but zero privacy risk and unblocks
internal/TestFlight measurement immediately.

**Option B — Relay-side aggregate gauges (mostly already done).** The relay
metrics suite (`go-relay-server/metrics.go`) already exposes active connections,
streams by proto, inbox store/retrieve/expire rates, media bytes, and a stream
duration histogram. The remaining work is narrow: add a label/metric that
distinguishes **1:1-circuit vs group-circuit** traffic (the relay currently
can't tell them apart without learning who's talking to whom — a privacy
constraint). *Tradeoffs:* the relay can't see LAN/direct traffic (by definition
it doesn't transit the relay), so this measures relay load, not the full mix —
complementary to A, not a replacement.

**Option C — Opt-in anonymous client aggregates.** For users who opt in, send
periodic aggregate-only transport histograms (no identities) to a collector.
*Tradeoffs:* gives the full mix including LAN/direct, but requires an opt-in
flow and careful privacy review; do only if A/B prove insufficient.

**Option D — Fix the bias regardless.** Remove/replace the default-to-`'relay'`
in `p2p_service_impl.dart:159` with an explicit `unknown` so tallies aren't
skewed. *Tradeoffs:* tiny change, but must verify nothing downstream relies on
the relay default (retry routing checks `== 'inbox'`, so likely safe).

## Acceptance Criteria / How We'll Know It's Fixed

1. A developer can read, on-device, the current session's transport mix
   (direct/relay/wifi/inbox counts), fallback-rung distribution, and median send
   latency per transport.
2. The relay exposes aggregate circuit/inbox load gauges in the existing Grafana
   setup (largely **already met** — see `metrics.go`); the only addition is a
   privacy-safe 1:1-vs-group circuit classification.
3. The `transport` label no longer silently defaults to `relay`; unknown is
   distinguishable from relay.
4. Hole-punch attempts/outcomes are countable (enables NET-REL-02/03 decisions).
5. We can produce a baseline report: "X% direct, Y% relay, Z% wifi, W% inbox;
   median latency per transport" — the input to prioritizing the other docs.

## Test Plan

See **NET-REL-06** for harness inventory and the negative-control principle. For
metrics, the false-result risk is **mislabeling** — a census that counts the wrong
bucket but still increments will pass a naive "> 0" test. Every metric test must
drive a **known forced mix** and assert **exact counts**.

### Unit (Dart) — client census
- **U1 (happy):** drive a known sequence via `FakeP2PService.sendMessageTransport`
  (e.g. 2×`direct`, 1×`relay`, 1×`inbox`) and assert the census reports exactly
  {direct:2, relay:1, inbox:1} — not "relay > 0".
- **U2 (the default-bias guard — CRITICAL; bind to the RECEIVE path):** `:159` is in
  `onMessageReceived`, NOT the send path — so driving `FakeP2PService.sendMessageTransport`
  does NOT exercise it. Inject an inbound `ChatMessage` with `transport: null` through
  the real `P2PServiceImpl.onMessageReceived` (or the `_bridge.onMessageReceived`
  callback) and assert the surfaced/persisted transport is `unknown`, NOT `relay`. Also
  note `:159` rewrites the message before anything downstream sees it (`copyWith(transport:…)`),
  so the census must read the *post-`:159`* value — meaning the fix (`?? 'unknown'`) has
  to live at `:159` itself. NEGATIVE CONTROL: a genuine `relay` message stays `relay`.
  Watch the second fallback too: `_inferTransportForPeer(msg.from)` (`:2115`) can supply
  a value before the literal default, so the guard must defeat the *inferred* value, not
  just the literal `'relay'` constant.
- **U3 (latency bucketing):** feed known `streamOpenMs`/`writeMs`/`ackWaitMs` and
  assert per-transport buckets; assert a slow path lands in the right bucket.

### Unit/Integration (Go) — relay + holepunch
- **G1 (BUILD `metrics_test.go`):** the existing Prometheus surface
  (`go-relay-server/metrics.go`) increments correctly — `relay_inbox_stored_total` on
  store (`inbox.go:702`), `relay_connections_active` on connect/disconnect,
  `relay_stream_duration_seconds` observes. Drive `InboxStore.Store()` directly (as
  `inbox_test.go` does) or via mocknet. **Constraints (or G1 gives false results):**
  these are global `promauto` counters — assert the **delta** via
  `testutil.ToFloat64(...)` before/after, NOT the absolute value; tests touching the
  same global must NOT run `t.Parallel()`; and use a **distinct messageId** because
  `inbox.go:699` increments the counter even on a duplicate store (so "+1 per store"
  only holds for distinct messages).
- **G2:** holepunch tracer events captured (shared with NET-REL-02 U1).
- **NEGATIVE CONTROL G-N1:** an operation that should NOT touch a metric leaves it
  unchanged (e.g. a direct send does not increment relay-circuit counters).

### Integration — full mix census
- **I1 (happy):** drive a send over each transport using the forcing primitives
  (LAN via `wifi_transport_test.dart`; relay via NW002; inbox via offline) and assert
  the census reflects each exactly. Cross-check the client census against the relay's
  `/metrics` for the relay-transiting subset.
- **I1 NEGATIVE CONTROL:** a LAN-only exchange must NOT appear in relay metrics
  (proves the relay can't see — and isn't double-counting — direct/LAN traffic).

### Privacy (mandatory gate)
- **PR1 (feasible — a real seam exists):** `flow_event_emitter.dart` provides
  `debugSetFlowEventSink` (`:37-40`) which receives the **post-sanitization** payload
  regardless of `kDebugMode`, and `sanitizeFlowEventDetails` (`:42-101`) already redacts
  sensitive keys, peer-IDs (>12 chars / `_isPeerIdKey`), multiaddrs and PEM keys. So:
  install a sink, emit, snapshot the captured map; assert NO peer IDs / content /
  per-conversation traces. NEGATIVE CONTROL: feed a payload containing a `peerId` /
  multiaddr / private key and assert it comes out `[redacted]`.
  **CAVEAT (real false-confidence risk):** the sanitizer only redacts *known* key
  names — a new metric payload using an unanticipated key (`conversationId`,
  `remotePeer`, `topic`) would pass through unredacted. So PR1 must assert on the
  **actual emitted keys**, not assume the sanitizer is exhaustive. And if Option A's
  counters are surfaced outside `emitFlowEvent` (e.g. a debug screen), the sanitizer
  does NOT apply — those need their own privacy assertion.
- **PR2:** relay 1:1-vs-group circuit label is aggregate-only and does not reveal
  who is talking to whom.

## Open Questions

1. Local-only diagnostics (Option A) sufficient for now, or do we need
   opt-in aggregates (Option C) to understand the real-world user network mix?
2. Where should the on-device transport dashboard live — settings debug card or
   a hidden dev screen?
3. Can the relay distinguish 1:1 circuit traffic from group circuit traffic for
   the load gauges without learning who's talking to whom?
4. Is removing the default-to-`'relay'` (Option D) safe across all consumers of
   `messages.transport`?

## References

- Code anchors in Document Basis.
- `UI-Grafana/privacy-safe-business-graf.md` — privacy-safe metrics precedent.
- Cross-ref **NET-REL-01/02/03/05** — every one defines success in terms of the
  metrics this doc would provide.
