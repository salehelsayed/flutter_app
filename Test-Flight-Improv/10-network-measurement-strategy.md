# Network Observability & Measurement Strategy

## Executive Summary

The project already has more instrumentation than the first pass credited: structured flow events, startup timing, bridge diagnostics, relay health state, and dedicated frame/performance tests exist today. The real current gap is **not** “no observability”; it is the lack of a small production-safe layer for correlating send/retry/discovery/media timing without building a large metrics/export/dashboard stack too early.

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

## Critical Measurement Gaps

| Gap | What's Missing | Impact |
|-----|---------------|--------|
| **E2E Message Latency** | Correlated send → transport → receive timing | Hard to compare paths quickly |
| **Media Throughput** | Simple upload/download duration + size counters | Hard to diagnose media slowness |
| **Retry Effectiveness** | Failed/unacked → recovered counters | Hard to quantify recovery quality |
| **Connection / Discovery Timing** | Per-step discovery/rejoin timing | Hard to tune group/network flows |
| **Decrypt / Error Visibility** | Clear counters for decrypt failures | Hard to see crypto-path pain points |
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
│ Layer 2: LIGHTWEIGHT SESSION METRICS          │
│ Small timers/counters, ring-buffer snapshots  │
│ Local inspection first                        │
│ RECOMMENDED NEXT STEP                         │
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

- Small in-memory buffer
- Local debug/support output first
- No exporter required to get value

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

## Implementation Roadmap

### Phase 1: Foundation (Week 1)
- [ ] Add `TimingProbe`
- [ ] Add a tiny `SessionMetrics` buffer
- [ ] Start with send/retry/discovery/media timings

### Phase 2: Targeted Instrumentation (Week 1-2)
- [ ] Instrument 1:1 send flow
- [ ] Instrument group publish/rejoin/discovery
- [ ] Instrument upload/download durations
- [ ] Instrument decrypt failures and retry outcomes

### Phase 3: Developer Output (Week 2)
- [ ] Add human-readable snapshot dump for local debugging
- [ ] Keep it local/offline first

### Phase 4: Export / Dashboards (Later, only if needed)
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
