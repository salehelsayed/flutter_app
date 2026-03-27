# Network Observability & Measurement Strategy

## Executive Summary

The project already has more instrumentation than the first pass credited: structured flow events, startup timing, bridge diagnostics, relay health state, and dedicated frame/performance tests exist today. The highest-value lean follow-up from this report is now also landed in the current Flutter tree: local flow-event-based timing/counter coverage for message send, media throughput, retry effectiveness, and connection/recovery timing was added without building a large metrics/export/dashboard stack too early.

---

## Existing Capabilities

### What's Already Instrumented

| Capability | Location | Scope |
|-----------|----------|-------|
| `emitFlowEvent()` | Widespread across app layers | Structured JSON-ish flow events |
| `StartupTiming` | `lib/core/utils/startup_timing.dart` | Marks + elapsed calculations |
| Push diagnostics | `logPushDiagnostic()` / push utils | Token/open/diagnostic events |
| Bridge diagnostics | Bridge + group discovery/publish debug events | Native/Go-facing diagnostics |
| Relay state metrics | Node state / relay health tracking | Transport health signals |
| Frame performance tests | `integration_test/feed_performance_test.dart`, `integration_test/identity_progress_performance_test.dart` | Render/perf regression checks |

### Limitations

- Logging is still mostly developer-facing
- Correlation across send → encrypt → transport → receive is light
- No small session-level aggregation for easy inspection
- No production-safe timing summary layer yet
- No reason yet to jump directly to exporter/dashboard infrastructure

---

## Historical Critical Measurement Gaps

| Gap | What's Missing | Impact |
|-----|---------------|--------|
| **E2E Message Latency** | Correlated send/receive timing slices | Narrow representative local timing/correlation is now landed; full-path rollout remains intentionally deferred |
| **Media Throughput** | Simple upload/download duration + size counters | Landed locally via the flow-event layer |
| **Retry Effectiveness** | Failed/unacked → recovered counters | Landed locally via the flow-event layer |
| **Connection / Discovery Timing** | Per-step discovery/rejoin timing | Landed locally for the targeted messaging/recovery seams |
| **Decrypt / Error Visibility** | Clear counters for decrypt failures | Already landed through the decrypt-failure visibility work before Session 29 |
| **DB Helper Hotspots** | Small timing probes around heavy helpers | Hard to rank DB cleanup work |

---

## Proposed Architecture: Three-Layer Observability Stack

```
┌───────────────────────────────────────────────┐
│ Layer 1: STRUCTURED LOGGING (Already in place)│
│ emitFlowEvent(), StartupTiming, bridge logs   │
└───────────────────────────────────────────────┘
                    ↓
┌───────────────────────────────────────────────┐
│ Layer 2: LIGHTWEIGHT LOCAL TIMING / COUNTERS  │
│ Small flow-event-based timings and counters   │
│ Local inspection first                        │
│ LANDED LEAN NEXT STEP                         │
└───────────────────────────────────────────────┘
                    ↓
┌───────────────────────────────────────────────┐
│ Layer 3: EXPORT / DASHBOARDS                  │
│ Opt-in analytics, batching, alerting          │
│ DEFER until Layer 2 proves value              │
└───────────────────────────────────────────────┘
```

---

## New Infrastructure to Build

### 1. TimingProbe (`lib/core/observability/timing_probe.dart`)

```dart
await recordTiming('message.send.total', () async {
  // ... code ...
});
```

- Minimal wrapper
- No large framework required
- Useful immediately for send/retry/discovery/media timings

### 2. SessionMetrics (`lib/core/observability/session_metrics.dart`)

```dart
SessionMetrics
├── recordTiming(name, duration, tags)
├── increment(name, [tags])
├── snapshot()
└── reset()
```

- Historical proposal only
- Session 29 intentionally did **not** build this
- The current repo instead uses the existing `emitFlowEvent(...)` layer for the lean local timing/counter step

### 3. AnalyticsExporter (`lib/core/observability/analytics_exporter.dart`)

- **Deferred**
- Only consider after the local/session layer proves useful
- Do not build this first

---

## Instrumentation Points

### A. Message Delivery Latency

| Point | Location | Metric |
|-------|----------|--------|
| Send initiation | chat send entry points | `message.send.start` |
| Encryption | bridge/helper boundary | `message.encrypt` |
| Transport completion | P2P/relay bridge send path | `message.transport` |
| Retry path | retry use cases | `message.retry` |
| Receive/decrypt | incoming handlers/listeners | `message.receive` / `message.decrypt` |

### B. Media Throughput

| Point | Metric | Tags |
|-------|--------|------|
| Upload complete | `media.upload.total` | size, mime |
| Download complete | `media.download.total` | size, mime |
| Retry | `media.retry` | reason, attempt |

### C. Discovery / Rejoin

| Metric | Tags |
|--------|------|
| `group.discovery.cycle` | group size / group id class |
| `group.rejoin.total` | group count |
| `relay.failover.events` | reason |
| `relay.healthy.count` | — |

### D. Database Performance

```dart
await recordTiming('db.posts.load', () async {
  // heavy helper call
});
```

### E. UI Frame Rate

Keep the existing integration/performance tests and only add live timing if product evidence requires it.

---

## Baseline Benchmarks

| Metric | Target | Conditions |
|--------|--------|-----------|
| Text message send path | Track by path, compare direct vs relay | Real device / representative network |
| Media upload | Track duration by size/type | Representative file sizes |
| Media download | Track duration by size/type | Representative file sizes |
| Group rejoin | Bound resume/rejoin path | App resume / reconnect |
| Retry success rate | High recovered / total retryable | Over representative sessions |

Targets should be derived from observed device data, not guessed first.

---

## A/B Testing Infrastructure

Defer. There is no need to build experiment-tagged metrics infrastructure before the app has a small reliable local/session metrics layer.

---

## Implementation Roadmap (Historical / Remaining)

### Landed Lean Local Layer
- [x] Add or normalize local flow-event timing/counter coverage for the highest-value messaging gaps
- [x] Start with send/retry/discovery/media timings
- [x] Keep the implementation local and production-safe without creating a second observability subsystem

### Remaining Optional Local Follow-Up
- [ ] Add small DB-helper hotspot timing probes only if DB cleanup work is reopened with fresh evidence
- [ ] Tighten local event correlation further only if a real debugging blind spot remains after the landed Session 29 layer

### Deferred By Design
- [ ] `TimingProbe` infrastructure
- [ ] `SessionMetrics` buffer
- [ ] exporter/dashboard/analytics work

### Export / Dashboards (Later, only if needed)
- [ ] Revisit opt-in export
- [ ] Revisit privacy/sampling
- [ ] Revisit dashboards/alerts

---

## Alerting Rules

Only relevant **if** export is added later.

| Alert | Condition | Severity |
|-------|-----------|----------|
| Message latency regression | Sustained p95/p99 increase | Warning |
| Media upload failure spike | Sustained elevated failure rate | Warning/Critical |
| Relay failover spike | Repeated failovers in window | Info/Warning |
| Group rejoin slowdown | Resume/rejoin exceeds budget | Warning |

---

## Privacy & Sampling

- Keep local/session metrics non-content-bearing
- Export, if ever added, should be opt-in
- No message content
- Shortened peer/message identifiers only where needed
- Aggregate before export
- Do not build the exporter before the local layer proves useful
