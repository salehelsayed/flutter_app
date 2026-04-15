# Simulator-Based Timing Tests — TDD Plan

> **Scope:** Test-driven implementation plan for all 13 simulator benchmark tests from `03b-timing-improvement-plan.md` Section 2 (Tests A–M), plus the shared harness infrastructure they require.
> **Depends on:** `03c-timing-instrumentation-tdd-plan.md` (events to collect), `03d-hazard-fixes-tdd-plan.md` (timeout paths to exercise).
> **Does not cover:** Instrumentation implementation (see `03c`), hazard fix implementation (see `03d`), routing changes (see `04b`).

---

## Two Layers of Testing

This plan has two distinct layers, each serving a different purpose:

| Layer | Runs On | Purpose | Produces Real Timing? |
|---|---|---|---|
| **Instrumentation verification** (Sections 1–13, Phases 1–2) | Host machine (`flutter test`, `go test`) | Verify events are emitted with correct fields, types, and on all code paths. Uses fakes and mocks. | No — timing values are synthetic |
| **Simulator benchmarks** (Section 14, Phase 4) | iOS/Android simulator (`flutter test integration_test/...`) | Run each scenario A–M with the live Go bridge, real MethodChannel, real libp2p over real network. Produce the actual p50/p95 numbers for the baseline table. | **Yes** — these fill in 03b Section 5 |

Both layers are necessary. Instrumentation verification catches missing fields, wrong event names, and broken code paths quickly on the host. Simulator benchmarks produce the real numbers that drive optimization decisions.

---

## Conventions Used Throughout

### Test Infrastructure Reuse

All tests build on existing fakes and test harnesses. No new fake types are introduced unless strictly necessary — the benchmark harness wraps the existing stack.

| Existing Infrastructure | Location | Used By |
|---|---|---|
| `TestUser` | `test/shared/fakes/test_user.dart` | Tests A, D, J, L |
| `GroupTestUser` | `test/shared/fakes/group_test_user.dart` | (Group discovery tests in `04b`) |
| `FakeBridge` / `PassthroughCryptoBridge` | `test/core/bridge/fake_bridge.dart` | All tests |
| `FakeP2PService` / `FakeP2PServiceIntegration` | `test/shared/fakes/fake_p2p_service_integration.dart` | Tests A, B, C, D, J |
| `FakeGroupPubSubNetwork` | `test/shared/fakes/fake_group_pubsub_network.dart` | (Group tests in `04b`) |
| `LifecycleBridge` | `test/shared/fakes/lifecycle_bridge.dart` | Tests B, C, M |
| `ChaosP2PNetwork` | `test/shared/fakes/chaos_p2p_network.dart` | Tests I, J (loaded conditions) |
| `captureFlowEvents` helper | `test/core/services/p2p_service_impl_test.dart` (pattern) | All Dart tests |
| `testEventCollector` + `waitForCollectedEvent` | `go-mknoon/node/node_test.go:1222`, `group_security_harness_test.go:13` | All Go tests |
| `_FrameTimingCollector` | `integration_test/conversation_wired_performance_harness.dart:48` | Test M (widget timing) |
| `_EventRecorder` | `integration_test/conversation_wired_performance_harness.dart:97` | Harness report template |

### Dart Benchmark Test Pattern

Every benchmark test follows this structure:

```dart
group('Benchmark: <Scenario Name>', () {
  late BenchmarkHarness harness;

  setUp(() {
    harness = BenchmarkHarness();
  });

  tearDown(() {
    harness.dispose();
  });

  test('<scenario description>', () async {
    final events = await harness.captureFlowEvents(() async {
      // ... trigger the operation ...
    });

    final timings = events.where((e) => e['event'] == 'EVENT_NAME').toList();
    expect(timings, isNotEmpty);

    for (final t in timings) {
      final details = t['details'] as Map<String, dynamic>;
      expect(details['elapsedMs'], isA<int>());
      expect(details['elapsedMs'], greaterThanOrEqualTo(0));
    }

    // Record for baseline table
    harness.record('<metric_name>', timings);
  });
});
```

### Go Benchmark Test Pattern

```go
func TestBenchmark_<ScenarioName>(t *testing.T) {
    collector := &testEventCollector{}
    node := startTestNodeWithCollector(t, collector)
    defer node.Stop()

    // ... trigger the operation ...

    data := waitForCollectedEvent(t, collector, "event:name", 5*time.Second)
    if data["elapsedMs"] == nil {
        t.Fatal("missing elapsedMs")
    }
    elapsedMs := int(data["elapsedMs"].(float64))
    t.Logf("BENCHMARK %s = %dms", "metric_name", elapsedMs)
}
```

### Baseline Table Output

Every test writes its results to stdout in a parseable format. The harness collects these into the Phase 3 baseline table from `03b` Section 5.

```
[BENCHMARK] <metric_name> p50=<ms> p95=<ms> (n=<count>)
```

### Simulator Device Matrix

Phase 1–2 tests (instrumentation verification) run on the host machine via `flutter test` and `go test` — no simulator needed.

Phase 3–4 tests (simulator spot-checks and benchmarks) require real iOS simulators with the Go native framework. The project targets **iOS 13.0+** (`platform :ios, '13.0'` in Podfile) and **Android API 24+** (`minSdk = 24`).

**Primary benchmark device (produce the baseline table):**

| Device | iOS Version | Simulator ID | Role |
|---|---|---|---|
| iPhone 17 Pro | iOS 26.1 | `38FECA55-03C1-4907-BD9D-8E64BF8E3469` | Primary benchmark device — high-end, consistent perf |

**Second device (two-simulator smoke tests):**

| Device | iOS Version | Simulator ID | Role |
|---|---|---|---|
| iPhone 17 | iOS 26.1 | `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` | Bob (receiver-first) in Phase 5 two-simulator smoke tests |

These two devices (iPhone 17 Pro + iPhone 17) match the default primary/sibling devices from `run_group_multi_device_real.dart`, which is the proven two-simulator orchestrator.

**Secondary devices (spot-check for device-class variation):**

| Device | iOS Version | Simulator ID | Role |
|---|---|---|---|
| iPhone 16 | iOS 18.6 | `8EF2F995-59DC-4B3D-9C2E-55FEF4B84DC4` | Older device / older iOS — catches perf regressions on lower-end |
| iPhone Air | iOS 26.1 | `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` | Mid-range — closest to typical user device |
| iPad Pro 13-inch (M5) | iOS 26.1 | `EED48C4D-3A7F-4A79-B1DB-E6220ABBEBFC` | Tablet form factor — catches layout + perf edge cases |

**Device selection rules:**
1. All baseline numbers in the 03b Section 5 table come from the **primary device** (iPhone 17 Pro, iOS 26.1). This gives a single consistent reference point.
2. After the baseline is established, re-run on secondary devices to detect device-class outliers. If a metric varies >2x between primary and secondary, flag it for investigation.
3. Use `FLUTTER_DEVICE_ID` env var or `--device` / `-d` flag to select the device:
   ```bash
   # Primary benchmark run
   dart run integration_test/scripts/run_benchmark_suite.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469

   # Or via env var (existing pattern from run_test_gates.sh)
   export FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469
   ./scripts/run_test_gates.sh benchmark-sim
   ```
4. The orchestrator script records the device name and iOS version in the baseline output header so results are traceable.

**Android:** Benchmarks focus on iOS simulators first (TestFlight release pipeline). Android emulator benchmarks are deferred — emulator I/O perf is less representative than iOS simulator, and the Go bridge requires patched `wlynxg/anet` on Go < 1.25 (known issue).

---

## 0. Shared Benchmark Harness

Before implementing individual tests, build the shared harness that all tests use.

### 0a. `BenchmarkHarness` (Dart)

**File:** `test/performance/benchmark_harness.dart`

**What:** A reusable test helper that:
1. Captures flow events during an operation (wraps `captureFlowEvents` pattern)
2. Filters events by name
3. Computes percentiles (p50, p95, p99) from a list of `elapsedMs` values
4. Formats results in the `[BENCHMARK]` output format
5. Optionally asserts timing budgets (`expect(p95, lessThan(budget))`)

### Tests (write first)

**Test file:** `test/performance/benchmark_harness_test.dart`

**Test 1: captureFlowEvents collects events emitted during action**
```
Setup:   flowEventLoggingEnabled = true.
Act:     harness.captureFlowEvents(() async {
           emitFlowEvent(layer: 'FL', event: 'TEST_EVENT',
                         details: {'elapsedMs': 42});
         }).
Assert:  Returns list with 1 event.
         event['event'] == 'TEST_EVENT'.
         event['details']['elapsedMs'] == 42.
```

**Test 2: filterEvents returns only matching events**
```
Setup:   List of 5 events, 3 with event == 'TARGET', 2 with event == 'OTHER'.
Act:     harness.filterEvents(events, 'TARGET').
Assert:  Returns 3 events.
```

**Test 3: percentile computes p50 correctly**
```
Setup:   [10, 20, 30, 40, 50, 60, 70, 80, 90, 100].
Act:     harness.percentile(values, 50).
Assert:  Returns 55 (median of even-length list).
```

**Test 4: percentile computes p95 correctly**
```
Setup:   100 values from 1 to 100.
Act:     harness.percentile(values, 95).
Assert:  Returns 95 (or 96, depending on interpolation — document choice).
```

**Test 5: percentile handles single value**
```
Setup:   [42].
Act:     harness.percentile(values, 50).
Assert:  Returns 42.
```

**Test 6: formatBenchmarkLine produces parseable output**
```
Setup:   metric='cold_send', p50=120, p95=340, n=10.
Act:     harness.formatBenchmarkLine('cold_send', p50: 120, p95: 340, n: 10).
Assert:  Returns '[BENCHMARK] cold_send p50=120ms p95=340ms (n=10)'.
```

**Test 7: assertBudget passes when p95 is within budget**
```
Setup:   values where p95 = 200.
Act:     harness.assertBudget(values, p95Budget: 500).
Assert:  No assertion failure.
```

**Test 8: assertBudget fails when p95 exceeds budget**
```
Setup:   values where p95 = 600.
Act:     harness.assertBudget(values, p95Budget: 500).
Assert:  Throws TestFailure.
```

### Implementation

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

class BenchmarkHarness {
  /// Captures [FLOW] events emitted during [action].
  /// Matches the captureFlowEvents pattern from p2p_service_impl_test.dart.
  Future<List<Map<String, dynamic>>> captureFlowEvents(
    Future<void> Function() action,
  ) async {
    final printed = <String>[];
    final previousLogging = flowEventLoggingEnabled;
    final originalDebugPrint = debugPrint;
    flowEventLoggingEnabled = true;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
    try {
      await action();
    } finally {
      debugPrint = originalDebugPrint;
      flowEventLoggingEnabled = previousLogging;
    }
    return printed
        .where((line) => line.startsWith('[FLOW]'))
        .map((line) {
          final json = line.substring('[FLOW] '.length);
          return jsonDecode(json) as Map<String, dynamic>;
        })
        .toList();
  }

  /// Filters events by event name.
  List<Map<String, dynamic>> filterEvents(
    List<Map<String, dynamic>> events,
    String eventName,
  ) => events.where((e) => e['event'] == eventName).toList();

  /// Extracts elapsedMs from a list of timing events.
  List<int> extractElapsedMs(List<Map<String, dynamic>> events) =>
      events
          .map((e) => (e['details'] as Map<String, dynamic>)['elapsedMs'] as int)
          .toList()
        ..sort();

  /// Computes the given percentile (0-100) from a sorted list.
  int percentile(List<int> sortedValues, int p) {
    if (sortedValues.isEmpty) return 0;
    if (sortedValues.length == 1) return sortedValues.first;
    final rank = (p / 100.0) * (sortedValues.length - 1);
    final lower = rank.floor();
    final upper = rank.ceil();
    if (lower == upper) return sortedValues[lower];
    return ((sortedValues[lower] + sortedValues[upper]) / 2).round();
  }

  /// Formats a benchmark result line for stdout.
  String formatBenchmarkLine(String metric, {
    required int p50,
    required int p95,
    required int n,
  }) => '[BENCHMARK] $metric p50=${p50}ms p95=${p95}ms (n=$n)';

  void dispose() {}
}
```

~50 lines Dart.

---

### 0b. `BenchmarkEventCollector` (Go)

**File:** `go-mknoon/node/benchmark_harness_test.go`

**What:** Extends `testEventCollector` with:
1. Filtered event collection by event name
2. Percentile computation from `elapsedMs` fields
3. Parseable benchmark output

### Tests (write first)

**Test file:** Same file (Go convention: test helpers + tests in one file)

**Test 1: collectEvents filters by event name**
```
Setup:   Collector with 5 events: 3 "stream:open_timing", 2 "relay:state".
Act:     collector.collectEvents("stream:open_timing").
Assert:  Returns 3 events.
```

**Test 2: extractElapsedMs parses float64 from data map**
```
Setup:   Events with data["elapsedMs"] = 42.0, 100.0, 200.0.
Act:     collector.extractElapsedMs(events).
Assert:  Returns [42, 100, 200].
```

**Test 3: percentile computes correctly**
```
Setup:   [10, 20, 30, 40, 50, 60, 70, 80, 90, 100].
Act:     percentile(values, 50), percentile(values, 95).
Assert:  p50 = 55, p95 = 96.
```

### Implementation

```go
// In benchmark_harness_test.go (test-only helper, not shipped)

func (c *testEventCollector) collectEvents(eventName string) []map[string]interface{} {
    var result []map[string]interface{}
    for _, raw := range c.snapshot() {
        var ev map[string]interface{}
        if err := json.Unmarshal([]byte(raw), &ev); err != nil {
            continue
        }
        if evName, _ := ev["event"].(string); evName == eventName {
            if data, ok := ev["data"].(map[string]interface{}); ok {
                result = append(result, data)
            }
        }
    }
    return result
}

func extractElapsedMs(events []map[string]interface{}) []int {
    var result []int
    for _, ev := range events {
        if ms, ok := ev["elapsedMs"].(float64); ok {
            result = append(result, int(ms))
        }
    }
    sort.Ints(result)
    return result
}

func benchmarkPercentile(sorted []int, p int) int {
    if len(sorted) == 0 { return 0 }
    if len(sorted) == 1 { return sorted[0] }
    rank := float64(p) / 100.0 * float64(len(sorted)-1)
    lower := int(rank)
    upper := lower + 1
    if upper >= len(sorted) { upper = len(sorted) - 1 }
    return (sorted[lower] + sorted[upper]) / 2
}
```

~40 lines Go.

---

### 0c. `TimingTestBridge` (Dart)

**File:** `test/performance/timing_test_bridge.dart`

**What:** A `FakeBridge` subclass with configurable per-command delays and timing injection for simulating Go-side latency in Dart-only tests.

### Tests (write first)

**Test file:** `test/performance/timing_test_bridge_test.dart`

**Test 1: Default behavior matches FakeBridge (no delays)**
```
Setup:   TimingTestBridge with no delays configured.
Act:     bridge.send('{"cmd":"node:status"}').
Assert:  Returns immediately (< 10ms).
```

**Test 2: Per-command delay is applied**
```
Setup:   TimingTestBridge with commandDelays = {'peer:dial': Duration(ms: 200)}.
Act:     Stopwatch around bridge.send('{"cmd":"peer:dial",...}').
Assert:  elapsedMs >= 200.
```

**Test 3: Delay only applies to matching command**
```
Setup:   TimingTestBridge with commandDelays = {'peer:dial': Duration(ms: 200)}.
Act:     bridge.send('{"cmd":"node:status"}').
Assert:  Returns immediately (< 10ms).
```

**Test 4: Go-side timing fields injected into response**
```
Setup:   TimingTestBridge with responseTimingFields = {
           'message:send': {'streamOpenMs': 15, 'writeMs': 8, 'ackWaitMs': 12}
         }.
Act:     bridge.send('{"cmd":"message:send",...}').
Assert:  Response JSON includes streamOpenMs, writeMs, ackWaitMs fields.
```

### Implementation

```dart
class TimingTestBridge extends FakeBridge {
  /// Per-command artificial delays (simulates Go processing time).
  final Map<String, Duration> commandDelays;

  /// Per-command extra fields merged into response (simulates Go timing fields).
  final Map<String, Map<String, dynamic>> responseTimingFields;

  TimingTestBridge({
    this.commandDelays = const {},
    this.responseTimingFields = const {},
  });

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    final delay = cmd != null ? commandDelays[cmd] : null;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }

    final baseResponse = await super.send(message);

    if (cmd != null && responseTimingFields.containsKey(cmd)) {
      final responseMap = jsonDecode(baseResponse) as Map<String, dynamic>;
      responseMap.addAll(responseTimingFields[cmd]!);
      return jsonEncode(responseMap);
    }

    return baseResponse;
  }
}
```

~30 lines Dart.

---

### 0d. Test Gate Registration

**File to modify:** `scripts/run_test_gates.sh`

Add a `benchmark` gate that runs all `test/performance/` tests:

```bash
benchmark)
  echo "=== Benchmark Tests ==="
  flutter test test/performance/ --reporter expanded
  ;;
```

~3 lines.

---

## 1. Test A: Per-Step 1:1 Send Breakdown

**Instrumentation required:** `03c` §4 (Go per-step timing), §7 (connection reuse counters), §10 (per-step 1:1 send)

**Test file:** `test/performance/benchmark_1_1_send_test.dart`

### What We're Measuring

The 1:1 send path from `sendChatMessage` has multiple sub-phases: discover, dial, send, relay probe, inbox fallback. Today `CHAT_MSG_SEND_TIMING` reports a single `elapsedMs`. After `03c` §10, it will include `discoverMs`, `dialMs`, `sendMs`, `sendPath`, and `connectionReused`. These tests verify those sub-fields exist and measure latency under controlled conditions.

### Tests (write first)

**Test A1: Cold send emits per-step breakdown**
```
Setup:   TestUser alice, TestUser bob on shared FakeP2PNetwork.
         alice has bob as contact. No prior connection (cold start).
         TimingTestBridge with peer:dial delay = 100ms.
Act:     alice sends message to bob.
Assert:  captureFlowEvents contains 'CHAT_MSG_SEND_TIMING' with:
         - details.elapsedMs is int >= 0
         - details.outcome == 'success'
         - details.sendPath is String (one of: 'direct', 'relay', 'reuse', 'inbox')
         - details.connectionReused == false
         - details.discoverMs is int >= 0 (if path involves discovery)
         - details.dialMs is int >= 0 (if path involves dial)
         - details.sendMs is int >= 0
```

**Test A2: Warm send shows connectionReused = true**
```
Setup:   TestUser alice, TestUser bob. Bob already connected (simulated).
         FakeP2PService with alice.p2pService.currentState.connections
         containing bob's peerId with status 'connected'.
Act:     alice sends message to bob.
Assert:  'CHAT_MSG_SEND_TIMING' with:
         - details.connectionReused == true
         - details.sendPath == 'reuse'
         - details.elapsedMs is int (expect < cold send)
```

**Test A3: Warm send is faster than cold send**
```
Setup:   TestUser alice, TestUser bob.
         TimingTestBridge with peer:dial delay = 150ms.
Act:     Cold send (no prior connection), then warm send (connection exists).
         Capture both CHAT_MSG_SEND_TIMING events.
Assert:  cold_timing.details.elapsedMs > warm_timing.details.elapsedMs.
         warm_timing.details.connectionReused == true.
         cold_timing.details.connectionReused == false.
```

**Test A4: Sequential sends show connection reuse effect**
```
Setup:   TestUser alice, TestUser bob.
         TimingTestBridge with peer:dial delay = 150ms.
         After first send, simulate bob becoming 'connected' in alice's state.
Act:     Send 10 messages sequentially from alice to bob.
         After first send, set connectionReused = true path.
Assert:  10 CHAT_MSG_SEND_TIMING events captured.
         First event: connectionReused == false.
         Events 2-10: connectionReused == true.
         Compute: first_send_ms = events[0].elapsedMs.
                  avg_subsequent_ms = mean(events[1..9].elapsedMs).
         Print: [BENCHMARK] 1_1_cold_send_ms p50=<X>ms p95=<X>ms (n=1)
                [BENCHMARK] 1_1_warm_send_ms p50=<X>ms p95=<X>ms (n=9)
```

**Test A5: Inbox fallback path reports sendPath = 'inbox'**
```
Setup:   TestUser alice, TestUser bob.
         FakeP2PService where: direct send fails, relay probe fails,
         storeInInbox succeeds.
Act:     alice sends message to bob.
Assert:  'CHAT_MSG_SEND_TIMING' with:
         - details.sendPath == 'inbox'
         - details.outcome == 'success'
         - details.elapsedMs is int >= 0
```

**Test A6: Send path includes encryptMs when contact has ML-KEM key**
```
Setup:   TestUser alice, TestUser bob.
         Bob's contact has ml_kem_public_key set.
         FakeBridge with message.encrypt returning encryptMs in response.
Act:     alice sends message to bob.
Assert:  'CHAT_MSG_SEND_TIMING' with:
         - details.encryptMs is int >= 0
```

### Implementation Notes

- Uses `TestUser.create()` factory with `FakeP2PNetwork`
- `TimingTestBridge` controls per-command latency
- `FakeP2PService` controls connection state (warm vs cold path)
- Tests are Dart-only — Go sub-step fields (`streamOpenMs`, `writeMs`, `ackWaitMs`) are tested in Go (see Test A-Go below)

### Go-Side Tests (companion)

**Test file:** `go-mknoon/node/benchmark_send_test.go`

**Test A-Go-1: SendMessage returns per-step timing in result**
```
Setup:   Two test nodes connected via local transport.
         collector attached to sender node.
Act:     nodeA.SendMessage(peerIdB, payload).
Assert:  waitForCollectedEvent "message:send_timing" with:
         - data.streamOpenMs is number >= 0
         - data.writeMs is number >= 0
         - data.ackWaitMs is number >= 0
         - data.totalMs == streamOpenMs + writeMs + ackWaitMs (± 5ms)
```

**Test A-Go-2: SendMessage timing with connection reuse**
```
Setup:   Two test nodes, already connected.
Act:     nodeA.SendMessage(peerIdB, payload) — second call (reuse path).
Assert:  "message:send_timing" with streamOpenMs < first call's streamOpenMs
         (reuse skips full dial).
```

---

## 2. Test B: Node Startup Timing

**Instrumentation required:** `03c` §4 (relay warm timing), §11 (circuit address delay), §18 (node startup timing summary), §24 (time-to-online badge)

**Test file:** `test/performance/benchmark_node_startup_test.dart`

### What We're Measuring

The sequence from `startNodeCore()` call to the node being discoverable. Phases: libp2p host creation, pubsub init, relay warm, circuit address acquisition, rendezvous registration. Go emits `node:startup_timing` events per phase. Dart emits `TIME_TO_ONLINE_BADGE` when the first healthy relay state arrives.

### Tests (write first)

**Test B1: Cold start emits TIME_TO_ONLINE_BADGE**
```
Setup:   LifecycleBridge starting in 'startup' phase.
         P2PServiceImpl with real startNodeCore() wiring.
Act:     Call startNodeCore().
         After 50ms, simulate relay:state push with relayState='online'.
Assert:  captureFlowEvents contains 'TIME_TO_ONLINE_BADGE' with:
         - details.totalMs is int >= 0
         - details.phase == 'cold_start'
         - details.source is String (one of: 'start_response',
           'relay_state_push', 'health_check_poll', 'addresses_push')
```

**Test B2: TIME_TO_ONLINE_BADGE.totalMs reflects actual wait**
```
Setup:   LifecycleBridge with nodeStatusDelay = 100ms.
         Relay comes online 200ms after startNodeCore().
Act:     Call startNodeCore(). Push relay online after 200ms delay.
Assert:  TIME_TO_ONLINE_BADGE.totalMs >= 200.
         TIME_TO_ONLINE_BADGE.totalMs < 500 (generous margin on simulator).
```

**Test B3: Cold start respects 6s budget on simulator**
```
Setup:   LifecycleBridge with realistic delays:
         - node:start response delay = 500ms
         - relay:state push after 2s
         - addresses:updated push after 3s
Act:     Call startNodeCore().
         Simulate push events at configured delays.
Assert:  TIME_TO_ONLINE_BADGE.totalMs < 6000.
         Print: [BENCHMARK] time_to_online_cold_start_ms p50=<X>ms (n=1)
```

**Test B4: Hot restart path emits with phase='hot_restart'**
```
Setup:   LifecycleBridge with simulateAlreadyStarted = true.
         node:start returns 'already started', then node:status returns
         isStarted with circuitAddresses.
Act:     Call startNodeCore().
Assert:  TIME_TO_ONLINE_BADGE with:
         - details.phase == 'hot_restart'
         - details.totalMs >= 0
```

**Test B5: Source field tracks which delivery path won**
```
Setup:   LifecycleBridge where start response includes relayState='online'.
Act:     Call startNodeCore().
Assert:  TIME_TO_ONLINE_BADGE.source == 'start_response'.
         (The Go start response itself carried the online state.)
```

**Test B6: Source field tracks relay:state push winning**
```
Setup:   LifecycleBridge where start response has relayState='connecting',
         then relay:state push fires with relayState='online' after 100ms.
Act:     Call startNodeCore().
Assert:  TIME_TO_ONLINE_BADGE.source == 'relay_state_push'.
```

### Go-Side Tests (companion)

**Test file:** `go-mknoon/node/benchmark_startup_test.go`

**Test B-Go-1: Node Start emits per-phase startup timing**
```
Setup:   testEventCollector. Start node with valid key + relay addresses.
Act:     node.Start(config).
Assert:  waitForCollectedEvent "node:startup_timing" (phase=host_ready) with:
         - data.libp2pNewMs is number >= 0
         - data.pubsubInitMs is number >= 0
         waitForCollectedEvent "node:startup_timing" (phase=relay_warm) with:
         - data.relayWarmMs is number >= 0
         - data.relaysAttempted is number >= 1
         Print: [BENCHMARK] startup_host_ready_ms = <X>ms
                [BENCHMARK] startup_relay_warm_ms = <X>ms
```

**Test B-Go-2: totalToDiscoverableMs < 5s on simulator**
```
Setup:   Node with local relay (short latency).
Act:     node.Start(config).
Assert:  waitForCollectedEvent "node:startup_timing" (phase=discoverable) with:
         - data.totalToDiscoverableMs < 5000
```

**Test B-Go-3: Circuit address timing emitted**
```
Setup:   testEventCollector.
Act:     node.Start(config). Wait for circuit address.
Assert:  waitForCollectedEvent "circuit_address:timing" with:
         - data.elapsedMs is number >= 0
         - data.pollCount is number >= 1
```

---

## 3. Test C: Relay Reconnect / Recovery

**Instrumentation required:** `03c` §19 (relay outage timing), §24 (time-to-online badge recovery phase).
**Hazard fix required:** `03d` §4 (recovery promise timeout)

**Test file:** `test/performance/benchmark_relay_recovery_test.dart`

### What We're Measuring

The wall-clock time from relay failure detection to recovery, and the timeout behavior when recovery stalls.

### Tests (write first)

**Test C1: Relay recovery emits RELAY_OUTAGE_TIMING detected + recovered**
```
Setup:   P2PServiceImpl with LifecycleBridge.
         Bridge in 'online' phase. Set _hasEverBeenOnline = true.
Act:     Transition to 'degraded' phase (relay health drops).
         After 500ms, transition back to 'online' (relay:reconnect succeeds).
Assert:  captureFlowEvents contains:
         1. 'RELAY_OUTAGE_TIMING' with phase='detected', detectionMs >= 0
         2. 'RELAY_OUTAGE_TIMING' with phase='recovered', recoveryMs >= 500,
            totalOutageMs >= detectionMs + recoveryMs
```

**Test C2: Detection source is 'push' for relay:state event**
```
Setup:   P2PServiceImpl with LifecycleBridge, online.
Act:     Simulate relay:state push with relayState='recovering'.
Assert:  RELAY_OUTAGE_TIMING with:
         - phase='detected'
         - detectionSource='push'
```

**Test C3: Detection source is 'poll' for health check cycle**
```
Setup:   P2PServiceImpl with LifecycleBridge, online.
Act:     Trigger health check that finds relay unhealthy.
         (Call _performHealthCheck with degraded response.)
Assert:  RELAY_OUTAGE_TIMING with:
         - phase='detected'
         - detectionSource='poll'
```

**Test C4: Recovery emits TIME_TO_ONLINE_BADGE with phase='recovery'**
```
Setup:   P2PServiceImpl, online → degraded → recovered.
Act:     Full cycle: degrade, detect, recover.
Assert:  TIME_TO_ONLINE_BADGE with:
         - phase='recovery'
         - totalMs >= 0
```

**Test C5: Recovery stall fires RecoveryWaitTimeout (03d §4 path)**
```
Setup:   LifecycleBridge where relay:reconnect hangs indefinitely.
         P2PServiceImpl triggers reconnect.
Act:     Wait for timeout (30s in production; shorten for test using
         a configurable timeout or by testing the Go side directly).
Assert:  Either:
         (a) Go-side: timeout:fired with timeoutName='RecoveryWaitTimeout'
         (b) Dart-side: reconnect call returns failure within timeout
         Next recovery attempt can start (gate cleared).
```

**Test C6: Multiple outage-recovery cycles emit distinct events**
```
Setup:   P2PServiceImpl, online.
Act:     Cycle 1: degrade → recover (200ms).
         Cycle 2: degrade → recover (300ms).
Assert:  4 RELAY_OUTAGE_TIMING events:
         - cycle 1 detected, cycle 1 recovered
         - cycle 2 detected, cycle 2 recovered
         Each recovered event has its own totalOutageMs.
```

### Go-Side Tests (companion)

**Test file:** `go-mknoon/node/benchmark_relay_recovery_test.go`

**Test C-Go-1: Recovery promise timeout emits timeout:fired**
```
Setup:   RelaySessionManager. Start recovery, never complete.
Act:     Wait() with RecoveryWaitTimeout.
Assert:  waitForCollectedEvent "timeout:fired" with:
         - data.timeoutName == "RecoveryWaitTimeout"
         - data.configuredMs == 30000
         - data.actualMs is within 10% of 30000
```

**Test C-Go-2: Normal recovery does NOT emit timeout:fired**
```
Setup:   RelaySessionManager. Start recovery, complete after 100ms.
Act:     Wait() returns success.
Assert:  No "timeout:fired" event in collector.
```

---

## 4. Test D: Inbox Store/Retrieve Round-Trip

**Instrumentation required:** `03c` §12 (inbox round-trip timing), §20 (inbox end-to-end delivery)

**Test file:** `test/performance/benchmark_inbox_roundtrip_test.dart`

### What We're Measuring

The latency of storing a message in a peer's inbox (sender side), and the end-to-end latency from store to delivery at the receiver.

### Tests (write first)

**Test D1: Inbox store emits per-step timing**
```
Setup:   TestUser alice, TestUser bob.
         FakeP2PService where direct send fails, relay probe fails,
         storeInInbox succeeds (bridge returns inbox:store_timing fields).
         TimingTestBridge with responseTimingFields for 'inbox:store':
         { connectMs: 10, streamOpenMs: 5, writeMs: 8, readMs: 3, totalMs: 26 }.
Act:     alice sends message to bob (falls through to inbox).
Assert:  captureFlowEvents contains 'CHAT_MSG_SEND_TIMING' with:
         - details.sendPath == 'inbox'
         - details.outcome == 'success'
```

**Test D2: Inbox retrieve emits timing**
```
Setup:   TestUser bob with messages in inbox staging.
         FakeBridge returning inbox:retrieve response with timing.
Act:     bob.p2pService.drainOfflineInbox().
Assert:  captureFlowEvents contains event matching inbox retrieve timing
         (event name depends on §20 implementation).
```

**Test D3: End-to-end inbox delivery timing from store to receiver**
```
Setup:   TestUser alice, TestUser bob (bob offline initially).
         Alice stores message via inbox.
         Then bob comes online and drains inbox.
Act:     Full cycle: alice stores, bob retrieves.
Assert:  If §20 INBOX_DELIVERY_TIMING is emitted:
         - details.deliveryMs is int >= 0
         - details.messageId matches the sent message
```

**Test D4: Inbox store timing < 200ms with warm relay**
```
Setup:   TimingTestBridge with minimal delays (simulating warm relay).
         storeInInbox bridge call returns { ok: true, stored: true }.
Act:     alice stores message in bob's inbox.
Assert:  CHAT_MSG_SEND_TIMING.elapsedMs < 200 (Dart-side budget).
         Print: [BENCHMARK] inbox_store_warm_ms p50=<X>ms (n=1)
```

### Go-Side Tests (companion)

**Test file:** `go-mknoon/node/benchmark_inbox_test.go`

**Test D-Go-1: InboxStore emits per-step timing**
```
Setup:   Two test nodes, one with inbox handler.
         collector on sender.
Act:     nodeA.InboxStore(peerIdB, message).
Assert:  waitForCollectedEvent "inbox:store_timing" with:
         - data.connectMs is number >= 0
         - data.streamOpenMs is number >= 0
         - data.writeMs is number >= 0
         - data.readMs is number >= 0
         - data.totalMs >= data.connectMs + data.streamOpenMs +
           data.writeMs + data.readMs (± 5ms)
         - data.outcome == "success"
```

**Test D-Go-2: InboxRetrieve emits timing**
```
Setup:   Messages stored in node B's inbox.
         collector on node B.
Act:     nodeB.InboxRetrieve().
Assert:  waitForCollectedEvent "inbox:retrieve_timing" with:
         - data.totalMs is number >= 0
         - data.messageCount is number >= 1
         - data.outcome == "success"
```

---

## 5. Test E: Media Transfer Timing

**Instrumentation required:** `03c` §2 (local WiFi timing), §21 (media stream open + throughput).
**Hazard fixes required:** `03d` §3 (profile upload progress), §5 (media idle timeout)

**Test file:** `test/performance/benchmark_media_transfer_test.dart` (Dart)
**Test file:** `go-mknoon/node/benchmark_media_test.go` (Go)

### What We're Measuring

Media upload latency, throughput, and stall detection across file sizes.

### Dart Tests (write first)

**Test E1: Media upload emits timing event**
```
Setup:   TestUser alice, TestUser bob.
         FakeBridge returning upload success with timing fields.
Act:     Upload 1MB test file from alice to bob.
Assert:  captureFlowEvents 'CHAT_MSG_SEND_TIMING' (or media-specific event) with:
         - details.hasAttachments == true
         - details.elapsedMs is int >= 0
         - details.outcome == 'success'
```

**Test E2: Local WiFi transfer emits LOCAL_MEDIA_SEND_TIMING**
```
Setup:   FakeP2PServiceIntegration with transportMode='wifi',
         local peer configured, local send succeeds.
Act:     Send media over local path.
Assert:  'LOCAL_MEDIA_SEND_TIMING' with:
         - details.elapsedMs is int >= 0
         - details.outcome == 'success'
         - details.mediaId is String
         - details.sizeBytes is int > 0
```

### Go Tests (write first)

**Test E-Go-1: Media stream open emits timing**
```
Setup:   Two nodes with media handler. collector on sender.
         Create 100 KB test file.
Act:     nodeA.MediaUpload(id, peerIdB, "image/jpeg", filePath, nil).
Assert:  waitForCollectedEvent "media:stream_open_timing" with:
         - data.connectMs is number >= 0
         - data.newStreamMs is number >= 0
         - data.totalMs >= data.connectMs + data.newStreamMs
         - data.outcome == "success"
```

**Test E-Go-2: Media upload emits throughput event**
```
Setup:   Two nodes. Create 1 MB test file.
Act:     nodeA.MediaUpload(...).
Assert:  waitForCollectedEvent "media:upload_complete" with:
         - data.totalBytes == 1048576
         - data.totalMs is number > 0
         - data.throughputBytesPerSec is number > 0
         Print: [BENCHMARK] media_1mb_upload_ms = <totalMs>ms
                [BENCHMARK] media_throughput_bytes_per_sec = <throughputBytesPerSec>
```

**Test E-Go-3: Multiple file sizes produce proportional timing**
```
Setup:   Two nodes. Create 1 MB, 5 MB, 20 MB test files.
Act:     Upload each sequentially. Collect "media:upload_complete" events.
Assert:  3 events. totalMs increases with file size.
         Print: [BENCHMARK] media_1mb_ms=<X> media_5mb_ms=<X> media_20mb_ms=<X>
```

**Test E-Go-4: Profile upload emits progress events (03d §3)**
```
Setup:   Two nodes. Create 1 MB test file.
Act:     nodeA.ProfileUpload("image/jpeg", filePath).
Assert:  At least 3 "profile:upload_progress" events:
         - First: sentBytes == 0
         - Last: sentBytes == totalBytes
```

**Test E-Go-5: Stalled upload fails within MediaIdleTimeout (03d §5)**
```
Setup:   Custom io.Reader that writes 1 KB then blocks forever.
         idleTimeoutReader with 1s timeout (shortened for test).
Act:     io.Copy(writer, idleTimeoutReader).
Assert:  Returns ErrStallTimeout after ~1s.
         NOT after 5 minutes (MediaTimeout).
```

**Test E-Go-6: Slow but steady upload completes (no false positive)**
```
Setup:   Custom io.Reader writing 100 bytes every 500ms.
         idleTimeoutReader with 2s timeout.
Act:     io.Copy(writer, idleTimeoutReader) until exhausted.
Assert:  Completes without error.
```

---

## 6. Test F: MethodChannel Bridge Crossing

**Instrumentation required:** `03c` §14 (bridge crossing time)

**Test file:** `test/performance/benchmark_bridge_crossing_test.dart`

### What We're Measuring

The raw round-trip latency of a Dart→Go→Dart bridge call, independent of the operation performed. This is the floor latency added to every bridge interaction.

### Tests (write first)

**Test F1: Single bridge call emits BRIDGE_CALL_TIMING**
```
Setup:   FakeBridge (or live GoBridgeClient on simulator).
Act:     bridge.send('{"cmd":"node:status"}').
Assert:  captureFlowEvents 'BRIDGE_CALL_TIMING' with:
         - details.cmd == 'node:status'
         - details.bridgeMs is int >= 0
         - details.outcome == 'success'
```

**Test F2: 100 sequential bridge calls produce timing distribution**
```
Setup:   FakeBridge with 0ms delay (measuring framework overhead only).
Act:     100 sequential bridge.send() calls.
Assert:  100 BRIDGE_CALL_TIMING events.
         Compute: p50, p95, p99 of bridgeMs.
         Print: [BENCHMARK] bridge_crossing_ms p50=<X>ms p95=<X>ms p99=<X>ms (n=100)
```

**Test F3: Bridge crossing under concurrent load**
```
Setup:   FakeBridge with 1ms delay per call.
Act:     10 concurrent bridge.send() calls (Future.wait).
Assert:  All 10 succeed.
         bridgeMs values should be ~1ms each (not stacked).
```

**Note:** The real benchmark value of Test F requires running on a real simulator/device with `GoBridgeClient` (live MethodChannel). The Dart-only tests above verify the instrumentation exists. A separate integration test file should run the actual measurement:

**Integration test file:** `integration_test/benchmark_bridge_crossing_test.dart`

**Test F-Int-1: 1000 round-trip bridge calls on simulator**
```
Setup:   IntegrationTestWidgetsFlutterBinding.
         Live GoBridgeClient (real MethodChannel to Go).
Act:     1000 sequential calls to bridge.send('{"cmd":"node:status"}').
         Collect all BRIDGE_CALL_TIMING events.
Assert:  1000 events.
         Compute p50, p95, p99.
         Print: [BENCHMARK] bridge_crossing_real_ms p50=<X>ms p95=<X>ms p99=<X>ms (n=1000)
         Assert p99 < 50ms (reasonable simulator budget).
```

---

## 7. Test G: Encryption Overhead

**Instrumentation required:** `03c` §15 (1:1 encryption timing), §16 (group encrypt/decrypt), §22 (ML-KEM keygen timing)

**Test file:** `test/performance/benchmark_encryption_test.dart`

### What We're Measuring

Whether crypto operations (ML-KEM keygen, AES-256-GCM encrypt/decrypt, Ed25519 sign/verify) are a meaningful contributor to send latency.

### Tests (write first)

**Test G1: ML-KEM keygen emits timing**
```
Setup:   FakeBridge returning mlkem.keygen response with keygenMs field.
Act:     callMlKemKeygen(bridge).
Assert:  captureFlowEvents 'MLKEM_KEYGEN_TIMING' (or bridge response parsing) with:
         - keygenMs is int >= 0
         Print: [BENCHMARK] mlkem_keygen_ms = <X>ms
```

**Test G2: Encrypt emits timing per message**
```
Setup:   FakeBridge returning message.encrypt response with encryptMs.
Act:     callEncryptMessage(bridge, payload: '100 bytes', publicKey: key).
Assert:  Response contains encryptMs field.
         CHAT_MSG_SEND_TIMING.encryptMs is int >= 0.
```

**Test G3: Decrypt emits timing per message**
```
Setup:   FakeBridge returning message.decrypt response with decryptMs.
Act:     callDecryptMessage(bridge, encrypted: blob, secretKey: key).
Assert:  Response contains decryptMs field.
```

**Test G4: Encryption time scales with payload size**
```
Setup:   FakeBridge with per-size encryptMs:
         100B → 1ms, 1KB → 2ms, 10KB → 5ms, 100KB → 20ms.
Act:     Encrypt each size bucket.
Assert:  encryptMs increases with payload size.
         Print: [BENCHMARK] encrypt_100b_ms=1 encrypt_1kb_ms=2 encrypt_10kb_ms=5 encrypt_100kb_ms=20
```

**Test G5: Group encrypt/decrypt emits timing (Go-side)**
```
Setup:   GroupTestUser alice, GroupTestUser bob on FakeGroupPubSubNetwork.
         FakeBridge returning group:publish_debug with encryptMs, signMs.
Act:     alice sends group message.
Assert:  captureFlowEvents 'GROUP_SEND_MSG_TIMING' with:
         - details.encryptMs is int >= 0 (if exposed through bridge)
```

### Go-Side Tests (companion)

**Test file:** `go-mknoon/node/benchmark_crypto_test.go`

**Test G-Go-1: ML-KEM keygen timing**
```
Setup:   Direct call to crypto.MlKemKeygen().
Act:     Time 100 invocations.
Assert:  All succeed.
         Compute p50, p95.
         Print: [BENCHMARK] mlkem_keygen_go_ms p50=<X>ms p95=<X>ms (n=100)
```

**Test G-Go-2: Group message encrypt includes encryptMs + signMs**
```
Setup:   Two nodes, group joined, collector on sender.
Act:     nodeA.PublishGroupMessage(groupId, text, ...).
Assert:  waitForCollectedEvent "group:publish_debug" with:
         - data.encryptMs is number >= 0
         - data.signMs is number >= 0
```

**Test G-Go-3: Group message decrypt includes decryptMs**
```
Setup:   Two nodes, group joined, collector on receiver.
Act:     nodeA publishes, nodeB receives.
Assert:  waitForCollectedEvent "group_message:received" with:
         - data.decryptMs is number >= 0
```

---

## 8. Test H: Timeout Accuracy

**Instrumentation required:** `03c` §23 (pre-existing timeout accuracy).
**Hazard fixes required:** `03d` §1–§5 (new timeouts — these must exist to be tested)

**Test file:** `go-mknoon/node/benchmark_timeout_accuracy_test.go` (Go — timeouts fire Go-side)
**Test file:** `test/performance/benchmark_timeout_accuracy_test.dart` (Dart — Dart-side timeouts)

### What We're Measuring

Whether each configured timeout fires at the expected time. Stacked timeouts or timer drift would show up as actualMs >> configuredMs.

### Dart Tests (write first)

**Test H-Dart-1: callP2PInboxStore timeout fires at ~15s (03d §1)**
```
Setup:   _HangingBridge (never completes).
Act:     Stopwatch around callP2PInboxStore(bridge, toPeerId: 'abc', message: 'x').
Assert:  Throws TimeoutException.
         Stopwatch.elapsedMilliseconds is between 14500 and 16500 (15s ± 10%).
         Print: [BENCHMARK] inbox_store_timeout_accuracy_ms = <actual>ms (configured=15000ms)
```

**Test H-Dart-2: callP2PRelayProbe timeout fires at ~5s (03d §2)**
```
Setup:   _HangingBridge.
Act:     Stopwatch around callP2PRelayProbe(bridge, peerId: 'abc').
Assert:  Throws TimeoutException.
         elapsedMs between 4500 and 5500 (5s ± 10%).
```

**Test H-Dart-3: Interactive send budget fires at ~2s**
```
Setup:   FakeP2PService where sendMessageWithReply hangs.
         Simulate connected peer (reuse path).
Act:     Stopwatch around sendChatMessage() (reuse path attempt).
Assert:  Reuse attempt times out within 2s budget.
         Falls through to next path within 2500ms.
```

### Go Tests (write first)

**Test H-Go-1: DialTimeout fires at ~15s**
```
Setup:   Node with unreachable relay address.
         collector attached.
Act:     Trigger dial to unreachable address.
Assert:  waitForCollectedEvent "timeout:fired" with:
         - data.timeoutName == "DialTimeout"
         - data.configuredMs == 15000
         - data.actualMs between 13500 and 16500 (± 10%)
```

**Test H-Go-2: PeerDialTimeout fires at ~2s**
```
Setup:   Node, peer dial to unreachable peer.
         collector attached.
Act:     node.DialPeer(unreachablePeerId).
Assert:  "timeout:fired" with timeoutName="PeerDialTimeout",
         configuredMs=2000, actualMs within 10%.
```

**Test H-Go-3: RelayProbeTimeout fires at ~5s**
```
Setup:   Node, relay probe to unresponsive peer.
Act:     node.RelayProbe(peerId).
Assert:  "timeout:fired" with timeoutName="RelayProbeTimeout",
         configuredMs=5000, actualMs within 10%.
```

**Test H-Go-4: SendTimeout fires at ~15s**
```
Setup:   Node connected to peer that accepts stream but never reads.
Act:     node.SendMessage(peerId, payload).
Assert:  "timeout:fired" with timeoutName="SendTimeout",
         configuredMs=15000, actualMs within 10%.
```

**Test H-Go-5: DiscoverTimeout fires at ~10s**
```
Setup:   Node, rendezvous discover to non-existent namespace.
Act:     Trigger discovery.
Assert:  "timeout:fired" with timeoutName="DiscoverTimeout",
         configuredMs=10000, actualMs within 10%.
```

**Test H-Go-6: RecoveryWaitTimeout fires at ~30s (03d §4)**
```
Setup:   RelaySessionManager, start recovery, never complete.
Act:     Wait() on promise.
Assert:  "timeout:fired" with timeoutName="RecoveryWaitTimeout",
         configuredMs=30000, actualMs within 10%.
```

**Test H-Go-7: MediaIdleTimeout fires at ~10s (03d §5)**
```
Setup:   idleTimeoutReader wrapping a reader that writes 1KB then blocks.
Act:     io.Copy(writer, idleReader).
Assert:  Fails after ~10s (or shortened test timeout).
         Error is ErrStallTimeout.
```

**Test H-Go-8: DirectConfirmTimeout fires at ~2s**
```
Setup:   Node sends to peer that receives but never confirms.
Act:     SendMessage with direct confirm path.
Assert:  waitForCollectedEvent "message:direct_ack_timing" with:
         - data.waitMs close to 2000
         - data.outcome == "timeout"
```

**Test H-Go-9: All timeouts — max deviation summary**
```
Setup:   Run tests H-Go-1 through H-Go-8. Collect all actualMs/configuredMs.
Act:     Compute maxDeviation = max(|actualMs - configuredMs| / configuredMs * 100).
Assert:  maxDeviation < 10%.
         Print: [BENCHMARK] timeout_max_deviation_pct = <X>%
```

---

## 9. Test I: Event Queue Wait

**Instrumentation required:** `03c` §6 (event queue wait timing)

**Test file:** `go-mknoon/node/benchmark_event_queue_test.go` (Go — measures queue-side latency)
**Test file:** `test/performance/benchmark_event_queue_test.dart` (Dart — measures end-to-end delivery)

### What We're Measuring

The latency from `Emit()` call in Go to callback delivery. Under idle conditions, this should be < 50ms. Under load (slow callback), it should grow proportionally.

### Go Tests (write first)

**Test I-Go-1: Idle queue wait is < 50ms**
```
Setup:   EventDispatcher with fast callback (no-op).
         collector attached.
Act:     Emit 100 events sequentially, each including queueWaitMs.
Assert:  All events' queueWaitMs < 50.
         Compute p50, p95.
         Print: [BENCHMARK] event_queue_idle_ms p50=<X>ms p95=<X>ms (n=100)
```

**Test I-Go-2: Loaded queue shows proportional wait increase**
```
Setup:   EventDispatcher with slow callback (50ms sleep per event).
Act:     Emit 20 events in burst.
Assert:  First event queueWaitMs ≈ 0.
         Last event queueWaitMs ≈ 20 * 50ms = 1000ms.
         queueWaitMs generally increases with position in burst.
```

**Test I-Go-3: Message events are never dropped under load**
```
Setup:   EventDispatcher with slow callback (100ms per event).
         Burst of 50 events, mix of coalesced (relay:state) and lossless (group_message:received).
Act:     Emit all 50 events.
         Wait for drain.
Assert:  All group_message:received events delivered (lossless FIFO).
         relay:state may be coalesced (fewer delivered than emitted).
```

### Dart Tests (write first)

**Test I-Dart-1: Events arrive at Dart within idle budget**
```
Setup:   LifecycleBridge, P2PServiceImpl.
Act:     Push 10 events via bridge.onRelayStateChanged.
         Capture timestamps at Dart delivery vs event emission.
Assert:  Delivery lag < 100ms per event on simulator.
```

---

## 10. Test J: Connection Reuse Hit Rate

**Instrumentation required:** `03c` §7 (connection reuse counters), §10 (per-step 1:1 send)

**Test file:** `test/performance/benchmark_connection_reuse_test.dart`

### What We're Measuring

How often the fast path (`isAlreadyConnected`) carries interactive traffic, and the latency difference between reused vs cold sends.

### Tests (write first)

**Test J1: Scripted workload — first send is cold, subsequent are warm**
```
Setup:   TestUser alice, TestUser bob.
         FakeP2PService: first send has no connection, subsequent sends
         have bob in connections list.
         TimingTestBridge with peer:dial delay = 200ms.
Act:     Send 10 messages: msg1 (cold), msg2-10 (warm).
Assert:  10 CHAT_MSG_SEND_TIMING events.
         events[0].connectionReused == false.
         events[1..9].connectionReused == true.
         Hit rate = 9/10 = 90%.
         Print: [BENCHMARK] connection_reuse_hit_rate = 90%
```

**Test J2: Resume scenario — cold → warm → disconnect → cold → warm**
```
Setup:   TestUser alice, TestUser bob.
Act:     Phase 1: cold send (no connection), 2 warm sends.
         Phase 2: disconnect bob (remove from connections).
         Phase 3: cold send (reconnect), 2 warm sends.
Assert:  6 CHAT_MSG_SEND_TIMING events.
         Cold sends: events[0], events[3] → connectionReused == false.
         Warm sends: events[1,2,4,5] → connectionReused == true.
         Hit rate = 4/6 = 67%.
```

**Test J3: Latency comparison: reused vs cold**
```
Setup:   TestUser alice, TestUser bob.
         TimingTestBridge: peer:dial = 200ms (cold adds dial latency).
Act:     5 cold sends (clear connection between each), 5 warm sends.
Assert:  cold_p50 = percentile of cold sends' elapsedMs.
         warm_p50 = percentile of warm sends' elapsedMs.
         cold_p50 > warm_p50 (cold sends include dial overhead).
         Print: [BENCHMARK] reuse_cold_send_ms p50=<X>ms (n=5)
                [BENCHMARK] reuse_warm_send_ms p50=<X>ms (n=5)
```

---

## 11. Test K: Voice Send Sub-Step Breakdown

**Instrumentation required:** `03c` §8 (voice send sub-steps)

**Test file:** `test/performance/benchmark_voice_send_test.dart`

### What We're Measuring

Whether the voice send path's latency is dominated by media upload or transport send.

### Tests (write first)

**Test K1: VOICE_SEND_TIMING includes uploadMs and sendMs**
```
Setup:   TestUser alice, TestUser bob.
         FakeBridge for media upload (returns uploadMs in response).
         FakeP2PService for message send.
Act:     Send voice message from alice to bob.
Assert:  captureFlowEvents 'VOICE_SEND_TIMING' with:
         - details.elapsedMs is int >= 0
         - details.uploadMs is int >= 0
         - details.sendMs is int >= 0
         - details.elapsedMs >= details.uploadMs + details.sendMs (approx)
```

**Test K2: Upload-dominated voice send**
```
Setup:   TimingTestBridge: media upload delay = 500ms, message send = 10ms.
Act:     Send voice message.
Assert:  VOICE_SEND_TIMING with:
         - uploadMs >= 500
         - sendMs < 100
         - upload_share = uploadMs / elapsedMs > 80%
         Print: [BENCHMARK] voice_upload_ms = <X>ms
                [BENCHMARK] voice_send_ms = <X>ms
                [BENCHMARK] voice_upload_share_pct = <X>%
```

**Test K3: Send-dominated voice send (small recording)**
```
Setup:   TimingTestBridge: media upload delay = 10ms (tiny file),
         message send via slow relay = 300ms.
Act:     Send voice message.
Assert:  VOICE_SEND_TIMING with:
         - sendMs > uploadMs
         - upload_share < 20%
```

---

## 12. Test L: Deferred Direct ACK Timing

**Instrumentation required:** `03c` §9 (deferred ACK timing events)

**Test file:** `test/performance/benchmark_deferred_ack_test.dart` (Dart)
**Test file:** `go-mknoon/node/benchmark_ack_test.go` (Go)

### What We're Measuring

How much of the DirectConfirmTimeout (2s) budget the ACK path actually consumes. If p95 is close to 2s, the timeout is too tight; if p95 is < 200ms, there's headroom.

### Go Tests (write first)

**Test L-Go-1: Fast confirm emits timing with low waitMs**
```
Setup:   Two nodes connected. collector on sender.
         Receiver confirms immediately.
Act:     nodeA.SendMessage(peerIdB, payload) with direct confirm.
Assert:  waitForCollectedEvent "message:direct_ack_timing" with:
         - data.waitMs < 500
         - data.ackWriteMs >= 0
         - data.outcome == "success"
```

**Test L-Go-2: Slow confirm still within budget**
```
Setup:   Two nodes. Receiver delays confirm by 1500ms.
Act:     nodeA.SendMessage(peerIdB, payload).
Assert:  "message:direct_ack_timing" with:
         - data.waitMs >= 1500
         - data.waitMs < 2000 (within DirectConfirmTimeout)
         - data.outcome == "success"
```

**Test L-Go-3: Confirm timeout emits with outcome='timeout'**
```
Setup:   Two nodes. Receiver never confirms.
Act:     nodeA.SendMessage(peerIdB, payload).
Assert:  "message:direct_ack_timing" with:
         - data.waitMs close to 2000 (DirectConfirmTimeout)
         - data.outcome == "timeout"
```

**Test L-Go-4: p95 waitMs stays within DirectConfirmTimeout on simulator**
```
Setup:   Two nodes. Receiver confirms with random 0-100ms delay.
Act:     Send 20 messages, collect all "message:direct_ack_timing" events.
Assert:  p95 of waitMs < 2000.
         Print: [BENCHMARK] direct_ack_wait_ms p50=<X>ms p95=<X>ms (n=20)
```

### Dart Tests

**Test L-Dart-1: Send use case reports ACK timing in CHAT_MSG_SEND_TIMING**
```
Setup:   TestUser alice, TestUser bob. Bob connected (reuse path).
         TimingTestBridge returns ackRoundTripMs in send response.
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.ackRoundTripMs is int >= 0 (if exposed)
```

---

## 13. Test M: Time-to-Online Badge (User-Perceived Startup Latency)

**Instrumentation required:** `03c` §18 (node startup timing), §24 (time-to-online badge)

**Test file:** `test/performance/benchmark_time_to_online_test.dart` (unit)
**Test file:** `integration_test/benchmark_time_to_online_test.dart` (integration/widget)

### What We're Measuring

The full user-perceived latency from app launch to the green "online" badge appearing. This combines Go startup, Dart state propagation, and widget render.

### Unit Tests (write first)

**Test M1: Cold start — service-level timing**
```
Setup:   LifecycleBridge, P2PServiceImpl.
Act:     Call startNodeCore(). Push relay online after 300ms.
Assert:  TIME_TO_ONLINE_BADGE with:
         - phase='cold_start'
         - totalMs >= 300
         - source tracks which delivery path won
```

**Test M2: Recovery — service-level timing**
```
Setup:   P2PServiceImpl online. Degrade relay. Recover after 500ms.
Act:     Full cycle: online → degraded → recovered.
Assert:  TIME_TO_ONLINE_BADGE with:
         - phase='recovery'
         - totalMs >= 500
```

**Test M3: Hot restart — service-level timing**
```
Setup:   LifecycleBridge with simulateAlreadyStarted = true.
Act:     Call startNodeCore().
Assert:  TIME_TO_ONLINE_BADGE with:
         - phase='hot_restart'
         - totalMs >= 0 (fast — just resync)
```

**Test M4: Source distribution across N cold starts**
```
Setup:   LifecycleBridge.
Act:     5 cold starts with varying relay response timings:
         - Run 1: start_response includes relay online → source='start_response'
         - Run 2: start_response has connecting, push wins → source='relay_state_push'
         - Run 3: start_response has connecting, health check wins → source='health_check_poll'
         - Run 4: addresses push wins → source='addresses_push'
         - Run 5: relay_state_push again
Assert:  Each run's TIME_TO_ONLINE_BADGE.source matches expected winner.
         Print distribution: start_response=1, relay_state_push=2,
                             health_check_poll=1, addresses_push=1
```

**Test M5: No duplicate timing on transient flicker**
```
Setup:   P2PServiceImpl online.
Act:     Push degraded then online within 100ms.
Assert:  Only ONE TIME_TO_ONLINE_BADGE event (not one per flicker).
```

**Test M6: Total user-perceived < 6s budget on simulator**
```
Setup:   LifecycleBridge with realistic cold-start delays.
Act:     Cold start.
Assert:  TIME_TO_ONLINE_BADGE.totalMs < 6000.
         Print: [BENCHMARK] time_to_online_cold_start_ms = <X>ms
```

### Integration/Widget Tests

**Test file:** `integration_test/benchmark_time_to_online_test.dart`

**Test M-Int-1: Widget transition timing on cold start**
```
Setup:   IntegrationTestWidgetsFlutterBinding.
         ConnectionStatusIndicator widget mounted.
         Feed from P2PServiceImpl state stream.
Act:     Cold start → wait for green badge.
Assert:  TIME_TO_ONLINE_BADGE_WIDGET emitted with:
         - details.widgetTransitionMs is int >= 0
         - details.previousHealth is String
         Print: [BENCHMARK] online_badge_widget_transition_ms = <X>ms
```

**Test M-Int-2: Widget transition timing on recovery**
```
Setup:   Widget showing degraded. State transitions to online.
Act:     Push online state.
Assert:  TIME_TO_ONLINE_BADGE_WIDGET with widgetTransitionMs >= 0.
```

---

## 15. Routing-Path Timing Benchmarks (1:1 Send — All Paths)

**Instrumentation required:** `03c` §4 (Go per-step timing), §7 (connection reuse counters), §10 (per-step 1:1 send)
**Routing doc:** `04-transport-routing-strategy.md` (decision tree, race strategy, relay probe eligibility, budget allocation)
**Routing improvements:** `04b-routing-improvement-plan.md` (budget starvation, InteractiveInboxTimeout, parallel relay failover)

### What This Section Adds

Tests A1–A6 in Section 1 cover basic cold/warm/inbox breakdowns. This section adds **per-routing-path benchmarks** that measure timing for every distinct path a 1:1 message can take through the routing decision tree. The purpose is to create a before/after baseline so that any routing strategy change (from `04b`) has a measurable impact.

Each test simulates a specific network condition that forces the send path into a particular routing branch, then captures timing for that path. When we later change a routing parameter (e.g., elapsed-budget-aware timeouts, parallel relay failover), we re-run the same tests and compare.

### Routing Paths Covered

| Path | Decision Point | What Forces This Path | Current Test Coverage |
|---|---|---|---|
| **Connection Reuse** | `isAlreadyConnected == true` | Peer in connections list | A2 (exists) |
| **WiFi Local Send** | `isLocalPeer == true`, WiFi wins race | Local peer discovery | **None in Test A** — added below |
| **Direct P2P (race winner)** | discover → dial → send succeeds first | Peer discoverable, no local | A1 (partial) |
| **WiFi vs Direct Race** | Both legs run, one wins | Both paths available | **None** — added below |
| **Relay Probe (connected)** | `relayProbeEligible`, probe returns connected | discover/dial fail, peer has relay reservation | **None** — added below |
| **Relay Probe (noReservation → inbox)** | probe returns NO_RESERVATION | peer truly offline | **None** — added below |
| **Relay Probe retry** | First relay send fails, second succeeds | Transient send failure on relay | **None** — added below |
| **Inbox Fallback (direct)** | Race fails, probe ineligible | send_failed or timeout in race | A5 (exists) |
| **Inbox Fallback (after probe)** | Probe fails, inbox succeeds | probe error + inbox ok | **None** — added below |
| **Budget Starvation** | discover consumes entire 2s budget | Slow discover (>1.5s) | **None** — added below |
| **Unacked Inbox Handoff** | sent==true, acked==false | peer received but didn't ACK | **None** — added below |
| **Stale Connection Recovery** | Reuse fails, falls to race | connection list stale | **None** — added below |
| **Worst-case cascade** | all paths fail sequentially | everything down | **None** — added below |

### Tests (write first)

**Test file:** `test/performance/benchmark_routing_paths_test.dart`

**Test R1: WiFi local send — timing when peer is on LAN**
```
Setup:   TestUser alice, TestUser bob.
         FakeP2PService with isLocalPeer(bob) = true.
         sendLocalMessage returns true after 50ms (simulated WiFi latency).
         Direct path also available but slower (200ms dial).
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.sendPath == 'local'
         - details.elapsedMs < 200 (WiFi should win the race)
         - details.outcome == 'success'
Output:  [BENCHMARK] routing_wifi_local_ms = <elapsedMs>
```

**Test R2: Direct P2P wins race — peer discoverable, no WiFi**
```
Setup:   TestUser alice, TestUser bob.
         isLocalPeer = false (no WiFi path).
         Direct path: discover=50ms, dial=100ms, send=30ms.
         No connection reuse (cold).
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.sendPath == 'direct'
         - details.connectionReused == false
         - details.discoverMs >= 50
         - details.dialMs >= 100
         - details.sendMs >= 30
         - details.elapsedMs >= 180
Output:  [BENCHMARK] routing_direct_cold_ms = <elapsedMs>
```

**Test R3: WiFi vs Direct race — WiFi wins**
```
Setup:   TestUser alice, TestUser bob.
         isLocalPeer = true. WiFi send delay = 30ms.
         Direct path: discover=200ms (slower than WiFi).
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.sendPath == 'local' (WiFi won the race)
         - details.elapsedMs < 100 (WiFi is faster)
Output:  [BENCHMARK] routing_race_wifi_wins_ms = <elapsedMs>
```

**Test R4: WiFi vs Direct race — Direct wins**
```
Setup:   TestUser alice, TestUser bob.
         isLocalPeer = true. WiFi send delay = 1200ms (slow WiFi).
         Direct path: discover=50ms, dial=100ms, send=30ms (total ~180ms).
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.sendPath == 'direct' (direct won the race)
         - details.elapsedMs < 500
Output:  [BENCHMARK] routing_race_direct_wins_ms = <elapsedMs>
```

**Test R5: WiFi fails, direct succeeds — race fallback within race**
```
Setup:   TestUser alice, TestUser bob.
         isLocalPeer = true. WiFi send fails immediately.
         Direct path succeeds after 150ms.
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.sendPath == 'direct' (WiFi failed, direct won)
         - details.outcome == 'success'
Output:  [BENCHMARK] routing_wifi_fail_direct_win_ms = <elapsedMs>
```

**Test R6: Relay probe path — discover fails, probe finds peer on relay**
```
Setup:   TestUser alice, TestUser bob.
         isLocalPeer = false. No connection reuse.
         Direct path: discover returns 'peer_not_found' (relayProbeEligible=true).
         probeRelay returns RelayProbeResult.connected.
         dialPeer succeeds. sendMessageWithReply succeeds.
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.sendPath == 'relay'
         - details.outcome == 'success'
         - details.elapsedMs captures: race budget (2s) + probe + dial + send
Output:  [BENCHMARK] routing_relay_probe_success_ms = <elapsedMs>
```

**Test R7: Relay probe path — dial fails, probe finds peer, relay send works**
```
Setup:   TestUser alice, TestUser bob.
         Direct path: discover succeeds, dial returns 'dial_failed'
         (relayProbeEligible=true).
         probeRelay returns connected. Send succeeds.
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.sendPath == 'relay'
         - details.outcome == 'success'
Output:  [BENCHMARK] routing_relay_after_dial_fail_ms = <elapsedMs>
```

**Test R8: Relay probe — first send fails, retry succeeds**
```
Setup:   TestUser alice, TestUser bob.
         Direct path: discover fails (relayProbeEligible=true).
         probeRelay returns connected.
         First sendMessageWithReply returns sent=false.
         Second sendMessageWithReply (after 250ms backoff) returns sent=true.
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.sendPath == 'relay'
         - details.outcome == 'success'
         - details.elapsedMs >= 250 (includes retry backoff)
Output:  [BENCHMARK] routing_relay_retry_success_ms = <elapsedMs>
```

**Test R9: Relay probe — noReservation → falls to inbox**
```
Setup:   TestUser alice, TestUser bob.
         Direct path: discover fails (relayProbeEligible=true).
         probeRelay returns RelayProbeResult.noReservation.
         storeInInbox succeeds.
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.sendPath == 'inbox'
         - details.outcome == 'success'
Output:  [BENCHMARK] routing_probe_no_reservation_to_inbox_ms = <elapsedMs>
```

**Test R10: Inbox fallback after probe error**
```
Setup:   TestUser alice, TestUser bob.
         Direct path: discover fails (relayProbeEligible=true).
         probeRelay returns RelayProbeResult.error.
         storeInInbox succeeds.
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.sendPath == 'inbox'
         - details.outcome == 'success'
Output:  [BENCHMARK] routing_probe_error_to_inbox_ms = <elapsedMs>
```

**Test R11: Inbox fallback — probe ineligible (send_failed in race)**
```
Setup:   TestUser alice, TestUser bob.
         Direct path: discover succeeds, dial succeeds,
         send returns 'send_failed' (relayProbeEligible=false).
         storeInInbox succeeds.
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.sendPath == 'inbox'
         - details.outcome == 'success'
         (Probe was NOT attempted — send failure doesn't set eligibility)
Output:  [BENCHMARK] routing_send_fail_direct_inbox_ms = <elapsedMs>
```

**Test R12: Budget starvation — slow discover consumes 2s budget**
```
Setup:   TestUser alice, TestUser bob.
         isLocalPeer = false. No connection reuse.
         TimingTestBridge with discover delay = 1800ms.
         Direct path: discover takes 1800ms, outer timeout fires at 2000ms.
         Dial and send never execute.
         storeInInbox succeeds.
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.elapsedMs >= 2000 (hit the wall-clock cap)
         - details.discoverMs >= 1800 (if captured before timeout)
         - details.dialMs is null or 0 (never reached)
         - details.sendMs is null or 0 (never reached)
         - details.sendPath == 'inbox' (or 'relay' if probe eligible)
         (This reproduces the budget starvation from 04b Section 1)
Output:  [BENCHMARK] routing_budget_starvation_ms = <elapsedMs>
Purpose: Baseline for elapsed-budget-aware timeout fix (04b §3)
```

**Test R13: Unacked inbox handoff — sent but no ACK**
```
Setup:   TestUser alice, TestUser bob. Bob connected (reuse path).
         sendMessageWithReply returns sent=true, acked=false.
         storeInInbox succeeds (handoff).
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.sendPath == 'reuse'
         - details.outcome == 'success'
         Message status in DB = 'delivered' (inbox handoff succeeded).
         Transport = 'inbox' (overridden by handoff).
Output:  [BENCHMARK] routing_unacked_handoff_ms = <elapsedMs>
```

**Test R14: Stale connection — reuse fails, falls to race**
```
Setup:   TestUser alice, TestUser bob.
         bob in connections list (stale — connection actually dead).
         sendMessageWithReply throws exception (connection gone).
         Race direct path succeeds.
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.connectionReused == false (reset after reuse failure)
         - details.sendPath == 'direct' (fell through to race)
         - details.outcome == 'success'
         - details.elapsedMs includes wasted reuse attempt
Output:  [BENCHMARK] routing_stale_reuse_fallback_ms = <elapsedMs>
Purpose: Measures cost of stale connection entry (wasted attempt + recovery)
```

**Test R15: Worst-case cascade — all paths fail sequentially**
```
Setup:   TestUser alice, TestUser bob.
         Connection reuse: not connected.
         WiFi: not local peer.
         Direct: discover returns 'peer_not_found' (relayProbeEligible=true).
         Relay probe: returns RelayProbeResult.error.
         Inbox: storeInInbox fails.
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.outcome == 'failed'
         - details.sendPath == 'unknown' or last attempted path
         - details.elapsedMs captures total cascade time
         Message status = 'failed' with wireEnvelope retained.
Output:  [BENCHMARK] routing_worst_case_cascade_ms = <elapsedMs>
Purpose: Upper-bound latency when everything is down
```

**Test R16: Interactive inbox timeout — 15s vs intended 3s**
```
Setup:   TestUser alice, TestUser bob.
         All paths fail, falls to inbox.
         storeInInbox hangs for 10s then succeeds.
         (Simulates the 04b §1 issue: InboxTimeout=15s used instead of
          InteractiveInboxTimeout=3s)
Act:     alice sends message to bob.
Assert:  CHAT_MSG_SEND_TIMING with:
         - details.elapsedMs >= 10000 (inbox waited the full 10s)
         - details.sendPath == 'inbox'
Output:  [BENCHMARK] routing_inbox_timeout_current_ms = <elapsedMs>
Purpose: Baseline for InteractiveInboxTimeout fix (04b §1).
         After fix, same test should complete in ~3s, not 10s+.
```

**Test R17: Relay probe eligibility matrix**
```
Setup:   6 sub-tests, each forcing a different failure reason:
         a) discover → 'peer_not_found' (expected: probe eligible)
         b) dial → 'dial_failed' (expected: probe eligible)
         c) send → 'send_failed' (expected: probe NOT eligible)
         d) race timeout (expected: probe NOT eligible)
         e) WiFi fail only (expected: probe NOT eligible)
         f) discover fail + WiFi fail combined (expected: probe eligible — OR logic)
Act:     alice sends message to bob in each sub-case.
Assert:  For each sub-case, verify whether relay probe was attempted
         by checking for 'CHAT_MSG_SEND_RELAY_PROBE_BEGIN' event.
         a) probe attempted
         b) probe attempted
         c) probe NOT attempted → inbox directly
         d) probe NOT attempted → inbox directly
         e) probe NOT attempted → inbox directly
         f) probe attempted (any failure with eligible=true triggers)
Output:  [BENCHMARK] routing_probe_eligibility a=<ms> b=<ms> c=<ms> d=<ms> e=<ms> f=<ms>
Purpose: Documents current probe eligibility behavior. If the routing
         strategy changes which failures trigger probes, this test
         detects the change.
```

### Implementation Notes

- All tests use `TimingTestBridge` with per-command delays to simulate specific network conditions
- `FakeP2PService` (or `FakeP2PServiceIntegration`) controls connection state, local peer status, and send/inbox outcomes
- Each test forces a single routing path by configuring exactly one combination of success/failure outcomes
- Tests are Dart-only (Phase 1) — they validate routing decision behavior and capture timing for each path
- The same scenarios are repeated on the simulator in Section 14o for real timing numbers

---

## 16. Two-Simulator Interactive Smoke Tests (1:1 Routing End-to-End)

**Depends on:** `04-transport-routing-strategy.md` (all routing paths)
**Pattern:** `group_multi_device_real_harness.dart` + `run_group_multi_device_real.dart` (two Flutter instances on two simulators)

### Why Two Simulators, Not Flutter + Go CLI Peer

| | Flutter + Go CLI Peer | **Two Flutter Simulators** |
|---|---|---|
| Sender Dart stack | Yes | Yes |
| **Receiver Dart stack** | No (Go only) | **Yes (full: listener → DB → UI)** |
| **Receiver timing events** | No FLOW events | **Yes — receiver emits own CHAT_MSG_SEND_TIMING, incoming message listener timing** |
| **MethodChannel overhead on receive** | None (Go native) | **Yes — real bridge event → Dart callback → listener → DB write** |
| **End-to-end latency** | send → Go CLI receipt | **send → receiver's `ChatMessageListener` fires → message in receiver's DB** |
| **Bidirectional symmetry** | Asymmetric (different stacks) | **Symmetric — both sides are identical Flutter apps** |
| **Inbox drain on receive** | CLI calls `inbox_retrieve` | **Real `warmBackground` → `drainOfflineInbox` → `ChatMessageListener`** |
| **UI rendering on receive** | None | **Real widget rebuild on incoming message (if conversation is open)** |

The Go CLI peer is useful for controlled orchestration (stop/start/unregister commands), but it cannot measure what happens on the receiver's Dart side. With two simulators, both sides run the full app — the same code path that production users run.

### Architecture

Follows the proven `run_group_multi_device_real.dart` pattern — two Flutter instances on two iOS simulators, coordinated via shared signal files:

```
Orchestrator (host machine)
  │
  ├─ Build Go CLI test peer (for relay probe / unregister control only)
  │
  ├─ Launch ALICE harness on Simulator 1 (process A)
  │   ├─ Role: 'alice' via --dart-define=ROUTING_SMOKE_ROLE=alice
  │   ├─ Generates identity, starts P2P node
  │   ├─ Writes alice_identity.json to E2E_SHARED_DIR
  │   └─ Polls for bob_identity.json → adds Bob as contact
  │
  ├─ Launch BOB harness on Simulator 2 (process B)
  │   ├─ Role: 'bob' via --dart-define=ROUTING_SMOKE_ROLE=bob
  │   ├─ Generates identity, starts P2P node
  │   ├─ Writes bob_identity.json to E2E_SHARED_DIR
  │   └─ Polls for alice_identity.json → adds Alice as contact
  │
  └─ Both processes coordinate via shared signal files:
      ├─ Alice sends → writes signal "s1_alice_sent"
      ├─ Bob polls for incoming message in DB → writes signal "s1_bob_received"
      │   with receive timestamp and timing details
      ├─ Bob sends reply → writes signal "s1_bob_replied"
      ├─ Alice polls for incoming message → writes signal "s1_alice_received"
      └─ Both write timing results to shared results.json
```

**Simulator assignments (from device matrix):**

| Role | Device | Simulator ID |
|---|---|---|
| Alice (sender-first) | iPhone 17 Pro (iOS 26.1) | `38FECA55-03C1-4907-BD9D-8E64BF8E3469` |
| Bob (receiver-first) | iPhone 17 (iOS 26.1) | `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` |

These match the default primary/sibling devices from `run_group_multi_device_real.dart`.

### Test Files

**Alice harness:** `integration_test/routing_smoke_alice_harness.dart`
**Bob harness:** `integration_test/routing_smoke_bob_harness.dart`
**Orchestrator:** `integration_test/scripts/run_routing_smoke_2sim.dart`

Both harnesses are separate `testWidgets` entry points launched on different simulators by the orchestrator. Each harness:
1. Reads its role from `--dart-define=ROUTING_SMOKE_ROLE`
2. Creates a real `GoBridgeClient`, generates identity, starts P2P node
3. Exchanges identity fixtures via shared directory
4. Adds the other device as a contact
5. Runs its half of each scenario (sending or receiving), coordinated by signals
6. Captures FLOW events from its own `debugPrint` output
7. Writes timing results to shared results directory

### Timing Measurement: Both Sides

Each message exchange produces timing from **both** perspectives:

```
Alice sends msg1 to Bob:

  ALICE (sender):
    CHAT_MSG_SEND_TIMING: elapsedMs, sendPath, connectionReused, outcome
    encryptMs, discoverMs, dialMs, sendMs (per-step if instrumented)
    Timestamp: aliceSentAt = DateTime.now() before send

  BOB (receiver):
    ChatMessageListener fires → message appears in messageRepository
    Timestamp: bobReceivedAt = DateTime.now() when listener callback fires
    INCOMING_MESSAGE_TIMING (if instrumented): bridgeEventMs, listenerMs, dbWriteMs

  END-TO-END:
    e2e_latency_ms = bobReceivedAt - aliceSentAt
    (Requires clock sync — both simulators on same host, clock skew is ~0)
```

Because both simulators run on the **same host machine**, their clocks are synchronized. The end-to-end latency `bobReceivedAt - aliceSentAt` is meaningful (no NTP skew).

### Scenarios (write first)

**Scenario S1: Cold send — both sides measure**
```
ALICE:   Sends msg1 to Bob (cold, no prior connection).
         Captures CHAT_MSG_SEND_TIMING. Writes aliceSentAt timestamp.
         Writes signal: s1_alice_sent (with aliceSentAt, elapsedMs, sendPath).
BOB:     Polls messageRepository for incoming message from Alice.
         When found: captures bobReceivedAt, message content, transport label.
         Writes signal: s1_bob_received (with bobReceivedAt, content).
Assert:  Bob's message content matches what Alice sent.
         sendPath is one of: direct, relay, reuse.
Output:  [SMOKE] S1_alice_send_ms = <elapsedMs>
         [SMOKE] S1_alice_send_path = <sendPath>
         [SMOKE] S1_bob_receive_latency_ms = <bobReceivedAt - aliceSentAt>
         [SMOKE] S1_e2e_cold_send_ms = <total end-to-end>
```

**Scenario S2: Warm send — 5 messages, connection reused**
```
ALICE:   Sends msg2–msg6 sequentially (connection from S1 should be warm).
         Captures 5 CHAT_MSG_SEND_TIMING events.
BOB:     Receives 5 messages. Captures bobReceivedAt for each.
Assert:  All 5 connectionReused == true, sendPath == 'reuse'.
         All 5 messages delivered in order.
Output:  [SMOKE] S2_alice_warm_send_ms p50=<X>ms p95=<X>ms (n=5)
         [SMOKE] S2_bob_receive_latency_ms p50=<X>ms p95=<X>ms (n=5)
         [SMOKE] S2_e2e_warm_ms p50=<X>ms p95=<X>ms (n=5)
```

**Scenario S3: Bob goes offline — inbox fallback + drain**
```
BOB:     Stops P2P node (simulates going offline). Writes signal: s3_bob_offline.
ALICE:   Reads s3_bob_offline signal. Sends msg7 to Bob.
         CHAT_MSG_SEND_TIMING with sendPath='inbox'.
         Writes signal: s3_alice_inbox_sent (with timing).
BOB:     Restarts P2P node. Goes online. Automatic warmBackground drains inbox.
         ChatMessageListener fires with msg7.
         Writes signal: s3_bob_inbox_received (with bobReceivedAt, content).
Assert:  msg7 content matches. sendPath == 'inbox'.
         Bob's listener received the message through real inbox drain path.
Output:  [SMOKE] S3_alice_inbox_send_ms = <elapsedMs>
         [SMOKE] S3_bob_inbox_drain_ms = <time from node start to msg received>
         [SMOKE] S3_e2e_inbox_ms = <aliceSentAt to bobReceivedAt>
```

**Scenario S4: Reconnect — first send after Bob comes back**
```
ALICE:   Sends msg8 to Bob (Bob just restarted in S3).
         Connection may or may not be warm — measures routing decision.
BOB:     Receives msg8. Captures timing.
Output:  [SMOKE] S4_alice_reconnect_ms = <elapsedMs>
         [SMOKE] S4_alice_reconnect_path = <sendPath>
         [SMOKE] S4_bob_reconnect_receive_ms = <bobReceivedAt - aliceSentAt>
```

**Scenario S5: Bidirectional — Bob sends to Alice**
```
BOB:     Sends msg9 to Alice (Bob is now the sender).
         Captures BOB's CHAT_MSG_SEND_TIMING.
ALICE:   Receives msg9 via ChatMessageListener → messageRepository.
         Captures aliceReceivedAt.
BOB:     Sends msg10 to Alice.
ALICE:   Receives msg10.
ALICE:   Sends msg11 to Bob.
BOB:     Receives msg11.
Assert:  All 3 messages delivered. Both sides have timing.
Output:  [SMOKE] S5_bob_send_ms p50=<X>ms (n=2)
         [SMOKE] S5_alice_receive_latency_ms p50=<X>ms (n=2)
         [SMOKE] S5_alice_send_ms = <elapsedMs> (msg11)
         [SMOKE] S5_bob_receive_latency_ms = <bobReceivedAt - aliceSentAt> (msg11)
Purpose: Verifies routing works symmetrically — both sides can send and receive
         through the full Dart stack.
```

**Scenario S6: Stale connection — Alice's connection list has stale entry**
```
BOB:     Stops P2P node WITHOUT disconnecting (kills process abruptly).
         Writes signal: s6_bob_killed.
ALICE:   Reads signal. Bob is still in Alice's connections list (stale).
         Sends msg12 to Bob (reuse attempt on stale connection).
         Reuse fails → falls to race → discover + dial or inbox.
         Captures CHAT_MSG_SEND_TIMING with connectionReused=false.
BOB:     Restarts. Receives msg12 (via inbox or direct after reconnect).
Output:  [SMOKE] S6_alice_stale_send_ms = <elapsedMs>
         [SMOKE] S6_alice_stale_path = <sendPath>
         [SMOKE] S6_alice_wasted_reuse_ms = <time in failed reuse before fallback>
         [SMOKE] S6_bob_stale_receive_ms = <bobReceivedAt - aliceSentAt>
```

**Scenario S7: All-paths-fail — both offline at different times**
```
BOB:     Stops P2P node. Writes signal: s7_bob_offline.
ALICE:   Sends msg13 to Bob. All paths fail (Bob offline, inbox may also fail
         if relay is also down for Bob).
Assert:  CHAT_MSG_SEND_TIMING with outcome='failed'.
         Message status='failed', wireEnvelope retained.
Output:  [SMOKE] S7_all_fail_ms = <elapsedMs>
         [SMOKE] S7_all_fail_path = <last attempted path>
```

**Scenario S8: Full conversation lifecycle — complete routing sweep**
```
Setup:   Both start fresh (after cleanup from S1–S7 or new identities).
Phase 1: [COLD] Alice sends msg1 → Bob receives (cold discover+dial).
Phase 2: [WARM×3] Alice sends msg2–msg4 → Bob receives (connection reused).
Phase 3: [OFFLINE] Bob stops. Alice sends msg5 → inbox.
Phase 4: [DRAIN] Bob starts. Inbox drains → msg5 received via listener.
Phase 5: [RECONNECT] Alice sends msg6 → Bob receives (re-route).
Phase 6: [BIDIR] Bob sends msg7 → Alice receives.
         Alice sends msg8 → Bob receives.
Phase 7: [WARM×2] Alice sends msg9–msg10 → Bob receives.
Assert:  All 10 messages delivered. Both sides have timing for every message.
Output:
  [SMOKE] S8_routing_timeline:
    msg1:  COLD      alice→bob  send=<X>ms path=direct   e2e=<X>ms
    msg2:  WARM      alice→bob  send=<X>ms path=reuse    e2e=<X>ms
    msg3:  WARM      alice→bob  send=<X>ms path=reuse    e2e=<X>ms
    msg4:  WARM      alice→bob  send=<X>ms path=reuse    e2e=<X>ms
    msg5:  OFFLINE   alice→bob  send=<X>ms path=inbox    e2e=<X>ms (inbox drain)
    msg6:  RECONNECT alice→bob  send=<X>ms path=<X>      e2e=<X>ms
    msg7:  BIDIR     bob→alice  send=<X>ms path=<X>      e2e=<X>ms
    msg8:  BIDIR     alice→bob  send=<X>ms path=<X>      e2e=<X>ms
    msg9:  WARM      alice→bob  send=<X>ms path=reuse    e2e=<X>ms
    msg10: WARM      alice→bob  send=<X>ms path=reuse    e2e=<X>ms
  [SMOKE] S8_path_distribution direct=<N> reuse=<N> relay=<N> inbox=<N>
  [SMOKE] S8_total_conversation_ms = <wall-clock for all 10 messages>
  [SMOKE] S8_alice_send_p50 = <X>ms (n=8)
  [SMOKE] S8_bob_receive_p50 = <X>ms (n=8)
  [SMOKE] S8_e2e_p50 = <X>ms (n=10)
Purpose: The definitive routing regression test. Run before and after
         any 04b routing change. Both sides report timing — the
         timeline shows sender latency AND receiver processing time
         for every routing path the real app takes.
```

### Orchestrator Implementation

**File:** `integration_test/scripts/run_routing_smoke_2sim.dart`

Follows `run_group_multi_device_real.dart` — launches two Flutter processes on two simulators:

```dart
// Pseudo-code
void main(List<String> args) async {
  final aliceDevice = args['--alice-device'] ?? '38FECA55-03C1-4907-BD9D-8E64BF8E3469';
  final bobDevice = args['--bob-device'] ?? '5BA69F1C-B112-47BE-B1FF-8C1003728C8F';
  final sharedDir = Directory.systemTemp.createTempSync('routing_smoke_');
  final runId = DateTime.now().millisecondsSinceEpoch.toString();

  // 1. Launch Alice harness on Simulator 1
  final alice = await _startHarnessRole(
    role: 'alice',
    deviceId: aliceDevice,
    harnessPath: 'integration_test/routing_smoke_alice_harness.dart',
    sharedDir: sharedDir,
    runId: runId,
  );

  // 2. Launch Bob harness on Simulator 2
  final bob = await _startHarnessRole(
    role: 'bob',
    deviceId: bobDevice,
    harnessPath: 'integration_test/routing_smoke_bob_harness.dart',
    sharedDir: sharedDir,
    runId: runId,
  );

  // 3. Pipe output, wait for both to complete
  _pipeOutput(alice.stdout, 'ALICE', logFile);
  _pipeOutput(bob.stdout, 'BOB', logFile);

  // 4. Wait for completion signal from both sides
  await _waitForSignal('${sharedDir.path}/rs_${runId}_alice_complete');
  await _waitForSignal('${sharedDir.path}/rs_${runId}_bob_complete');

  // 5. Read and merge results from both sides
  final aliceResults = await _readJson('${sharedDir.path}/rs_${runId}_alice_results.json');
  final bobResults = await _readJson('${sharedDir.path}/rs_${runId}_bob_results.json');
  final merged = mergeTimingResults(aliceResults, bobResults);

  // 6. Print combined smoke report
  printRoutingSmokeReport(merged);

  // 7. Cleanup
  alice.kill();
  bob.kill();
}
```

Run via:
```bash
dart run integration_test/scripts/run_routing_smoke_2sim.dart \
  --alice-device 38FECA55-03C1-4907-BD9D-8E64BF8E3469 \
  --bob-device 5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

### Signal Protocol (shared directory)

```
rs_<runId>_alice_identity.json     ← Alice writes (peerId, publicKey, mlKemPublicKey)
rs_<runId>_bob_identity.json       ← Bob writes (peerId, publicKey, mlKemPublicKey)
rs_<runId>_alice_ready             ← Alice writes (node online, Bob added as contact)
rs_<runId>_bob_ready               ← Bob writes (node online, Alice added as contact)
rs_<runId>_s1_alice_sent           ← Alice writes (msg1 sent, with timing)
rs_<runId>_s1_bob_received         ← Bob writes (msg1 received, with timestamp)
rs_<runId>_s3_bob_offline          ← Bob writes (P2P node stopped)
rs_<runId>_s3_alice_inbox_sent     ← Alice writes (inbox send complete)
rs_<runId>_s3_bob_online           ← Bob writes (P2P node restarted, inbox drained)
rs_<runId>_s3_bob_inbox_received   ← Bob writes (msg received via inbox drain)
rs_<runId>_s6_bob_killed           ← Bob writes (process killed, connection stale)
rs_<runId>_s6_bob_restarted        ← Bob writes (restarted)
rs_<runId>_alice_complete          ← Alice writes (all scenarios done)
rs_<runId>_bob_complete            ← Bob writes (all scenarios done)
rs_<runId>_alice_results.json      ← Alice writes (all timing metrics)
rs_<runId>_bob_results.json        ← Bob writes (all timing metrics)
```

### What This Catches That No Other Layer Does

| Issue | Unit (R1–R17) | Sim bench (14o) | Two-Sim Smoke (S1–S8) |
|---|---|---|---|
| Event fields correct | Yes | Yes | Yes |
| Timing values realistic | No (fakes) | Yes (one side) | **Yes (both sides)** |
| Message actually delivered | No | One side (CLI Go) | **Both sides (full Dart stack)** |
| Receiver MethodChannel + listener | No | No | **Yes** |
| Receiver DB write timing | No | No | **Yes** |
| True end-to-end latency (send → receiver DB) | No | No | **Yes (same-host clock sync)** |
| Bidirectional symmetry | No | No | **Yes (both sides identical)** |
| Inbox drain through real warmBackground | No | No | **Yes (S3)** |
| Connection staleness with real bridge | No | Partially | **Yes (S6 — real process kill)** |
| Routing path after real node restart | No | Partially | **Yes (S4)** |

---

## 14. Simulator Benchmark Harness (Phase 4 — Real Timing on Simulators)

Sections 1–13 verify instrumentation correctness using fakes. This section runs each 03b scenario on a **real iOS simulator** with the **live Go bridge** (`GoBridgeClient`), **real MethodChannel**, and **real libp2p networking** to produce the actual p50/p95 numbers for the baseline table.

### Architecture

Each simulator benchmark follows the pattern established by `background_reconnect_test.dart` and `transport_e2e_test.dart`:

```dart
@Tags(['device'])
library;

import 'package:integration_test/integration_test.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ... platform-specific DB init ...

  testWidgets('Benchmark: <scenario>', (tester) async {
    // 1. Initialize live Go bridge
    final bridge = GoBridgeClient();
    await bridge.initialize();

    // 2. Generate identity
    final identity = await callIdentityGenerate(bridge);

    // 3. Start real P2P node (connects to relay server)
    final p2pService = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
    await p2pService.startNode(identity.privateKey, identity.peerId);

    // 4. Wait for Online (real relay connection)
    await _waitForOnline(p2pService, timeout: Duration(seconds: 30));

    // 5. Run scenario, collect FLOW events from debugPrint
    final events = <Map<String, dynamic>>[];
    // ... capture events ...

    // 6. Compute percentiles, print [BENCHMARK] lines
    // 7. Assert budgets

    // Teardown
    await p2pService.stopNode();
    p2pService.dispose();
    bridge.dispose();
  });
}
```

**Key difference from unit tests:** These use `GoBridgeClient()` (real native bridge), not `FakeBridge`. They connect to the actual relay server. Timing values reflect real network + native code latency.

**Run command:**
```bash
flutter test integration_test/benchmark_<scenario>_harness.dart -d <SIMULATOR_ID>
```

**Orchestrator script** (runs all benchmarks sequentially, aggregates results):
```bash
dart run integration_test/scripts/run_benchmark_suite.dart -d <SIMULATOR_ID>
```

### Two-Node Scenarios

Tests A, D, E, G (encrypt/decrypt), and L require **two peers**. These use the existing Go CLI test peer process coordinated via fixture files, matching the pattern from `transport_e2e_test.dart`:

```bash
# Terminal 1: Start Go CLI test peer
cd go-mknoon && go run cmd/testpeer/main.go --fixture-dir /tmp/benchmark_fixtures

# Terminal 2: Run Flutter benchmark on simulator
dart run integration_test/scripts/run_benchmark_suite.dart \
  -d <SIMULATOR_ID> \
  --fixture-dir /tmp/benchmark_fixtures \
  --scenarios A,D,E,L
```

The orchestrator script in `integration_test/scripts/run_benchmark_suite.dart` handles:
1. Starting the Go CLI test peer in the background
2. Exchanging peer IDs and addresses via fixture files
3. Running each scenario sequentially
4. Collecting all `[BENCHMARK]` lines
5. Printing the final baseline table

### 14a. Simulator Benchmark: Per-Step 1:1 Send (Test A)

**File:** `integration_test/benchmark_1_1_send_harness.dart`

**Scenario A-Sim-1: Cold send to test peer (first contact, no prior connection)**
```
Setup:   Live GoBridgeClient → real node online.
         Go CLI test peer running, exchanged peer IDs via fixtures.
         No prior connection between the two nodes.
Act:     Send 5 messages (first is cold, subsequent are warm).
         Collect all CHAT_MSG_SEND_TIMING events from FLOW log.
Assert:  Each event has: elapsedMs, sendPath, connectionReused, outcome.
         events[0].connectionReused == false (cold).
         events[1..4].connectionReused == true (warm, if connection held).
Output:  [BENCHMARK] sim_1_1_cold_send_ms p50=<X>ms p95=<X>ms (n=<cold_count>)
         [BENCHMARK] sim_1_1_warm_send_ms p50=<X>ms p95=<X>ms (n=<warm_count>)
         [BENCHMARK] sim_1_1_send_path_distribution direct=<N> relay=<N> inbox=<N> reuse=<N>
```

**Scenario A-Sim-2: Warm send (10 sequential messages to same peer)**
```
Setup:   Same as A-Sim-1, after first cold connection established.
Act:     Send 10 messages sequentially.
Assert:  All 10 have connectionReused == true (if connection reuse works).
         Per-step breakdown: discoverMs, dialMs, sendMs present.
Output:  [BENCHMARK] sim_1_1_sequential_warm_ms p50=<X>ms p95=<X>ms (n=10)
```

**Scenario A-Sim-3: Inbox fallback (peer offline)**
```
Setup:   Go CLI test peer stopped (offline).
Act:     Send message — relay probe fails, falls through to inbox.
Assert:  sendPath == 'inbox'.
Output:  [BENCHMARK] sim_1_1_inbox_fallback_ms p50=<X>ms (n=1)
```

### 14b. Simulator Benchmark: Node Startup (Test B)

**File:** `integration_test/benchmark_node_startup_harness.dart`

**Scenario B-Sim-1: Cold start — measure each phase**
```
Setup:   Fresh GoBridgeClient, no prior node state.
Act:     Generate identity. Start node. Wait for Online.
         Capture: node:startup_timing (Go push events),
                  TIME_TO_ONLINE_BADGE (Dart service event),
                  circuit_address:timing (Go push event).
Assert:  node:startup_timing has phases: host_ready, relay_warm, discoverable.
         TIME_TO_ONLINE_BADGE.totalMs < 6000ms (simulator budget).
Output:  [BENCHMARK] sim_startup_host_ready_ms = <X>ms
         [BENCHMARK] sim_startup_relay_warm_ms = <X>ms
         [BENCHMARK] sim_startup_circuit_address_ms = <X>ms
         [BENCHMARK] sim_startup_total_discoverable_ms = <X>ms
         [BENCHMARK] sim_time_to_online_badge_ms = <X>ms
         [BENCHMARK] sim_time_to_online_source = <source>
```

**Scenario B-Sim-2: Repeated cold starts (5 runs for percentiles)**
```
Setup:   Loop: stop node, dispose bridge, re-create, cold start.
Act:     5 iterations of full cold start cycle.
         Collect TIME_TO_ONLINE_BADGE.totalMs from each.
Assert:  All 5 complete within 30s each.
Output:  [BENCHMARK] sim_cold_start_ms p50=<X>ms p95=<X>ms (n=5)
```

**Scenario B-Sim-3: Hot restart**
```
Setup:   Node already started and online.
Act:     Call startNodeCore() again (triggers 'already started' resync).
         Capture TIME_TO_ONLINE_BADGE with phase='hot_restart'.
Output:  [BENCHMARK] sim_hot_restart_ms = <X>ms
```

### 14c. Simulator Benchmark: Relay Reconnect / Recovery (Test C)

**File:** `integration_test/benchmark_relay_recovery_harness.dart`

**Scenario C-Sim-1: Kill relay, measure recovery**
```
Setup:   Live node online.
Act:     Disconnect relay peer (bridge.send peer:disconnect to relay).
         Wait for degraded state.
         Trigger recovery (handleAppResumed or automatic health check).
         Wait for online state.
         Collect RELAY_OUTAGE_TIMING events.
Assert:  RELAY_OUTAGE_TIMING with phase='detected' and phase='recovered'.
         TIME_TO_ONLINE_BADGE with phase='recovery'.
Output:  [BENCHMARK] sim_relay_detection_ms = <detectionMs>
         [BENCHMARK] sim_relay_recovery_ms = <recoveryMs>
         [BENCHMARK] sim_relay_total_outage_ms = <totalOutageMs>
         [BENCHMARK] sim_recovery_time_to_online_ms = <TIME_TO_ONLINE_BADGE.totalMs>
```

**Scenario C-Sim-2: Repeated recovery cycles (3 runs)**
```
Setup:   Live node online.
Act:     3 cycles: disconnect relay → detect → recover.
Output:  [BENCHMARK] sim_relay_recovery_ms p50=<X>ms p95=<X>ms (n=3)
         [BENCHMARK] sim_relay_outage_ms p50=<X>ms p95=<X>ms (n=3)
```

### 14d. Simulator Benchmark: Inbox Store/Retrieve Round-Trip (Test D)

**File:** `integration_test/benchmark_inbox_harness.dart`

**Scenario D-Sim-1: Store message in offline peer's inbox**
```
Setup:   Live node online. Go CLI test peer stopped (offline).
Act:     Send message via inbox (storeInInbox path).
         Collect CHAT_MSG_SEND_TIMING with sendPath='inbox'.
         Capture any inbox:store_timing Go push events.
Output:  [BENCHMARK] sim_inbox_store_ms = <elapsedMs>
```

**Scenario D-Sim-2: Retrieve + end-to-end delivery**
```
Setup:   Messages stored in inbox from D-Sim-1.
         Start Go CLI test peer (comes online).
Act:     Test peer retrieves inbox, receives messages.
         Measure from store timestamp to receiver delivery.
Output:  [BENCHMARK] sim_inbox_retrieve_ms = <retrieve time>
         [BENCHMARK] sim_inbox_e2e_delivery_ms = <store to delivery>
```

### 14e. Simulator Benchmark: Media Transfer (Test E)

**File:** `integration_test/benchmark_media_harness.dart`

**Scenario E-Sim-1: Upload file to test peer (1MB, 5MB)**
```
Setup:   Both nodes online. Create test files.
Act:     Upload each file. Collect media:upload_complete events.
Output:  [BENCHMARK] sim_media_1mb_upload_ms = <X>ms
         [BENCHMARK] sim_media_5mb_upload_ms = <X>ms
         [BENCHMARK] sim_media_stream_open_ms = <X>ms
         [BENCHMARK] sim_media_throughput_bytes_per_sec = <X>
```

**Scenario E-Sim-2: Profile upload with progress events**
```
Setup:   Node online. Create 1MB test image.
Act:     Upload profile. Collect profile:upload_progress events.
Assert:  At least 3 progress events (initial, intermediate, final).
Output:  [BENCHMARK] sim_profile_upload_ms = <X>ms
         [BENCHMARK] sim_profile_progress_event_count = <N>
```

### 14f. Simulator Benchmark: Bridge Crossing (Test F)

**File:** `integration_test/benchmark_bridge_crossing_harness.dart`

**Scenario F-Sim-1: 1000 round-trip bridge calls**
```
Setup:   Live GoBridgeClient.
Act:     1000 sequential calls to bridge.send('{"cmd":"node:status"}').
         Collect all BRIDGE_CALL_TIMING events.
Output:  [BENCHMARK] sim_bridge_crossing_ms p50=<X>ms p95=<X>ms p99=<X>ms (n=1000)
Assert:  p99 < 50ms (reasonable simulator budget).
```

### 14g. Simulator Benchmark: Encryption Overhead (Test G)

**File:** `integration_test/benchmark_encryption_harness.dart`

**Scenario G-Sim-1: ML-KEM keygen (10 iterations)**
```
Setup:   Live GoBridgeClient.
Act:     10 calls to callMlKemKeygen(bridge).
         Capture keygenMs from each response.
Output:  [BENCHMARK] sim_mlkem_keygen_ms p50=<X>ms p95=<X>ms (n=10)
```

**Scenario G-Sim-2: Encrypt/decrypt with payload sizes**
```
Setup:   Live GoBridgeClient. ML-KEM key pair generated.
Act:     Encrypt + decrypt at 100B, 1KB, 10KB, 100KB.
         Capture encryptMs, decryptMs from each.
Output:  [BENCHMARK] sim_encrypt_100b_ms=<X> sim_encrypt_1kb_ms=<X> ...
         [BENCHMARK] sim_decrypt_100b_ms=<X> sim_decrypt_1kb_ms=<X> ...
```

**Scenario G-Sim-3: Group message encrypt+sign + decrypt (Go-side)**
```
Setup:   Two nodes in same group, both online.
Act:     Publish group message. Capture group:publish_debug (encryptMs, signMs)
         on sender, group_message:received (decryptMs) on receiver.
Output:  [BENCHMARK] sim_group_encrypt_ms = <X>ms
         [BENCHMARK] sim_group_sign_ms = <X>ms
         [BENCHMARK] sim_group_decrypt_ms = <X>ms
```

### 14h. Simulator Benchmark: Timeout Accuracy (Test H)

**File:** `integration_test/benchmark_timeout_accuracy_harness.dart`

**Scenario H-Sim-1: Force each Dart-side timeout to fire**
```
Setup:   Live GoBridgeClient. Node started.
         For callP2PInboxStore: send to unreachable peer (inbox handler absent).
         For callP2PRelayProbe: probe unreachable peer.
Act:     Trigger each timeout. Measure actual wall-clock vs configured.
Collect: Stopwatch per call.
Output:  [BENCHMARK] sim_inbox_timeout_actual_ms = <X> (configured=15000)
         [BENCHMARK] sim_relay_probe_timeout_actual_ms = <X> (configured=5000)
         [BENCHMARK] sim_timeout_max_deviation_pct = <X>%
```

**Scenario H-Sim-2: Force Go-side timeouts via push events**
```
Setup:   Live node. Trigger operations that hit Go-side timeouts
         (dial unreachable, send to unresponsive peer, etc.).
Act:     Collect timeout:fired events from Go push.
Output:  [BENCHMARK] sim_dial_timeout_actual_ms = <X> (configured=15000)
         [BENCHMARK] sim_peer_dial_timeout_actual_ms = <X> (configured=2000)
         [BENCHMARK] sim_send_timeout_actual_ms = <X> (configured=15000)
         [BENCHMARK] sim_discover_timeout_actual_ms = <X> (configured=10000)
```

### 14i. Simulator Benchmark: Event Queue Wait (Test I)

**File:** `integration_test/benchmark_event_queue_harness.dart`

**Scenario I-Sim-1: Idle event delivery latency**
```
Setup:   Live node online, idle.
Act:     Trigger 20 relay:state push events (via health check cycle).
         Capture queueWaitMs from each delivered event.
Output:  [BENCHMARK] sim_event_queue_idle_ms p50=<X>ms p95=<X>ms (n=20)
Assert:  p95 < 50ms.
```

### 14j. Simulator Benchmark: Connection Reuse Hit Rate (Test J)

**File:** `integration_test/benchmark_connection_reuse_harness.dart`

**Scenario J-Sim-1: Scripted conversation workload**
```
Setup:   Live node online. Go CLI test peer online.
Act:     Phase 1: 1 cold send (first ever), then 5 warm sends.
         Phase 2: Wait 60s (connection may drop). 1 send (cold or warm?), then 3 sends.
         Collect all CHAT_MSG_SEND_TIMING events.
Assert:  Count connectionReused=true vs false.
Output:  [BENCHMARK] sim_connection_reuse_hit_rate_pct = <X>%
         [BENCHMARK] sim_reuse_cold_send_ms p50=<X>ms (n=<cold_count>)
         [BENCHMARK] sim_reuse_warm_send_ms p50=<X>ms (n=<warm_count>)
```

### 14k. Simulator Benchmark: Voice Send Sub-Steps (Test K)

**File:** `integration_test/benchmark_voice_harness.dart`

**Scenario K-Sim-1: Voice note send to test peer**
```
Setup:   Live node online. Go CLI test peer online.
         Create test audio file (simulated recording).
Act:     Send voice message. Collect VOICE_SEND_TIMING.
Output:  [BENCHMARK] sim_voice_upload_ms = <X>ms
         [BENCHMARK] sim_voice_send_ms = <X>ms
         [BENCHMARK] sim_voice_upload_share_pct = <X>%
         [BENCHMARK] sim_voice_total_ms = <X>ms
```

### 14l. Simulator Benchmark: Deferred Direct ACK (Test L)

**File:** `integration_test/benchmark_ack_harness.dart`

**Scenario L-Sim-1: Direct send with ACK from test peer**
```
Setup:   Both nodes online, direct connection established.
Act:     Send 10 messages. Go CLI test peer confirms each.
         Collect message:direct_ack_timing events from Go push.
Output:  [BENCHMARK] sim_direct_ack_wait_ms p50=<X>ms p95=<X>ms (n=10)
Assert:  p95 < 2000ms (within DirectConfirmTimeout).
```

### 14m. Simulator Benchmark: Time-to-Online Badge (Test M)

**File:** `integration_test/benchmark_time_to_online_harness.dart`

**Scenario M-Sim-1: Cold start — wall-clock to green badge**
```
Setup:   Widget tree mounted with ConnectionStatusIndicator.
Act:     Cold start node. Wait for green badge.
         Collect TIME_TO_ONLINE_BADGE + TIME_TO_ONLINE_BADGE_WIDGET.
Assert:  Total user-perceived < 6s.
Output:  [BENCHMARK] sim_time_to_online_badge_ms = <X>ms
         [BENCHMARK] sim_time_to_online_widget_ms = <X>ms
         [BENCHMARK] sim_time_to_online_total_ms = <badge + widget>ms
         [BENCHMARK] sim_time_to_online_source = <source>
```

**Scenario M-Sim-2: Recovery — wall-clock from degraded to green**
```
Setup:   Node online. Disconnect relay.
Act:     Wait for degraded badge. Trigger recovery. Wait for green.
Output:  [BENCHMARK] sim_recovery_to_online_badge_ms = <X>ms
         [BENCHMARK] sim_recovery_to_online_widget_ms = <X>ms
```

**Scenario M-Sim-3: 5 cold starts for source distribution**
```
Setup:   5 fresh cold starts.
Act:     Collect TIME_TO_ONLINE_BADGE.source from each.
Output:  [BENCHMARK] sim_online_source_distribution start_response=<N> relay_state_push=<N> health_check_poll=<N> addresses_push=<N>
```

### 14o. Simulator Benchmark: Routing Path Matrix (Test R — All 1:1 Paths)

**File:** `integration_test/benchmark_routing_paths_harness.dart`

Runs the routing-path scenarios from Section 15 on a real simulator with the live Go bridge to produce real timing numbers for each routing decision. Uses the Go CLI test peer to control which paths succeed or fail.

**Scenario R-Sim-1: Connection reuse — warm send to connected peer**
```
Setup:   Both nodes online. Send one message (cold), establishing connection.
Act:     Send 5 more messages (warm, connection reused).
         Collect CHAT_MSG_SEND_TIMING for each.
Output:  [BENCHMARK] sim_routing_reuse_ms p50=<X>ms p95=<X>ms (n=5)
         [BENCHMARK] sim_routing_reuse_path = reuse (100%)
```

**Scenario R-Sim-2: Direct P2P — cold send to discoverable peer**
```
Setup:   Both nodes online. No prior connection (fresh identity each run).
Act:     Send 1 message (cold discover → dial → send).
Output:  [BENCHMARK] sim_routing_direct_cold_ms = <X>ms
         [BENCHMARK] sim_routing_direct_discoverMs = <X>ms
         [BENCHMARK] sim_routing_direct_dialMs = <X>ms
         [BENCHMARK] sim_routing_direct_sendMs = <X>ms
```

**Scenario R-Sim-3: Relay probe — peer behind relay, not directly discoverable**
```
Setup:   Both nodes online. Configure Go CLI test peer so it is reachable
         via relay but NOT via direct rendezvous discover.
         (Test peer registers on relay but does NOT register on rendezvous.)
Act:     Send message. Discover fails → relay probe → dial via relay → send.
Output:  [BENCHMARK] sim_routing_relay_probe_ms = <X>ms
         [BENCHMARK] sim_routing_relay_probe_path = relay
```

**Scenario R-Sim-4: Inbox fallback — peer offline**
```
Setup:   Go CLI test peer stopped (offline, no relay reservation).
Act:     Send message. Discover fails → probe noReservation → inbox.
Output:  [BENCHMARK] sim_routing_inbox_fallback_ms = <X>ms
         [BENCHMARK] sim_routing_inbox_path = inbox
```

**Scenario R-Sim-5: Budget starvation — slow relay, discover takes >1.5s**
```
Setup:   Both nodes online. Configure relay with artificial latency
         (or test peer registers late, making discover slow).
Act:     Send message. Track whether discover consumes the full 2s budget.
Output:  [BENCHMARK] sim_routing_budget_starvation_ms = <X>ms
         [BENCHMARK] sim_routing_budget_starvation_discover_ms = <X>ms
         [BENCHMARK] sim_routing_budget_starvation_dial_ms = <X>ms (0 if never reached)
Purpose: Real-world measurement of the budget starvation from 04b §1.
         Re-run after elapsed-budget-aware fix to measure improvement.
```

**Scenario R-Sim-6: Worst-case path cascade — total failure timing**
```
Setup:   Go CLI test peer offline. Relay unresponsive.
         Inbox store fails (relay down for inbox too).
Act:     Send message. All paths fail.
Output:  [BENCHMARK] sim_routing_worst_case_ms = <X>ms
         [BENCHMARK] sim_routing_worst_case_path_sequence = direct→relay→inbox→failed
Purpose: Upper-bound latency when everything is down.
```

**Scenario R-Sim-7: Routing path distribution over realistic workload**
```
Setup:   Both nodes online. Simulate a conversation:
         - 1 cold send (fresh connection)
         - 5 warm sends (connection reused)
         - Stop test peer. 1 send (offline → inbox)
         - Start test peer. 1 send (reconnect → direct or relay)
         - 3 warm sends
Act:     Collect all 11 CHAT_MSG_SEND_TIMING events.
         Count sendPath distribution.
Output:  [BENCHMARK] sim_routing_distribution direct=<N> reuse=<N> relay=<N> inbox=<N> local=<N>
         [BENCHMARK] sim_routing_cold_ms = <X>ms (first send)
         [BENCHMARK] sim_routing_warm_ms p50=<X>ms (warm sends)
         [BENCHMARK] sim_routing_reconnect_ms = <X>ms (after peer restart)
         [BENCHMARK] sim_routing_offline_inbox_ms = <X>ms (peer offline)
Purpose: Realistic routing profile. Re-run after routing changes
         to see if the distribution shifts (e.g., more reuse, fewer inbox).
```

**Scenario R-Sim-8: Before/after routing change comparison**
```
Setup:   Run R-Sim-7 on current build → save as "before" baseline.
         Apply routing change (e.g., InteractiveInboxTimeout fix from 04b).
         Re-run R-Sim-7 → save as "after".
Act:     Compare before/after for each metric.
Output:  [BENCHMARK] sim_routing_before_after_delta_<metric> = <before>ms → <after>ms (<change>%)
Purpose: This is the core regression/improvement test for routing changes.
         Any 04b change should be validated by running this scenario.
```

---

### 14n. Benchmark Suite Orchestrator

**File:** `integration_test/scripts/run_benchmark_suite.dart`

Automates running all simulator benchmarks (13 timing tests A–M + routing path matrix R) and aggregating results into the baseline table.

**Implementation:**

```dart
// Pseudo-code — actual orchestrator script
void main(List<String> args) async {
  final simulatorId = parseArgs(args, '--device');
  final fixtureDir = parseArgs(args, '--fixture-dir') ?? '/tmp/benchmark_fixtures';
  final scenarios = parseArgs(args, '--scenarios')?.split(',') ?? allScenarios;

  // 1. Start Go CLI test peer (for two-node tests)
  final testPeer = await startGoTestPeer(fixtureDir);

  // 2. Run each harness, collect [BENCHMARK] lines from stdout
  final results = <String, Map<String, dynamic>>{};
  for (final scenario in scenarios) {
    final output = await runFlutterTest(
      'integration_test/benchmark_${scenario}_harness.dart',
      device: simulatorId,
    );
    results[scenario] = parseBenchmarkLines(output);
  }

  // 3. Stop test peer
  await testPeer.kill();

  // 4. Print baseline table
  printBaselineTable(results);
}
```

**Output:** The final baseline table from 03b Section 5, with real numbers:

```
=====================================================
  mknoon Transport Timing — Simulator Baseline
  Device: iPhone 17 Pro (iOS 26.1)
  UDID: 38FECA55-03C1-4907-BD9D-8E64BF8E3469
  Date: 2026-04-XX
=====================================================
  1:1 Send (cold)             p50=___   p95=___
  1:1 Send (warm)             p50=___   p95=___
  Node Startup (Go)           p50=___   p95=___
  Time-to-Online Badge        p50=___   p95=___
  Relay Recovery              p50=___   p95=___
  Relay Outage (total)        p50=___   p95=___
  Inbox Store (warm)          p50=___   p95=___
  Inbox E2E Delivery          p50=___   p95=___
  Event Queue Wait            p50=___   p95=___
  Media 5MB Upload            p50=___   p95=___
  Media Stream Open           p50=___   p95=___
  Media Throughput (bytes/s)  p50=___   p95=___
  Voice Upload Phase          p50=___   p95=___
  Voice Transport Phase       p50=___   p95=___
  Direct ACK Round-Trip       p50=___   p95=___
  Bridge: MethodChannel RT    p50=___   p95=___
  Crypto: ML-KEM keygen       p50=___   p95=___
  Crypto: ML-KEM encrypt      p50=___   p95=___
  Connection Reuse Hit Rate   ___%
  Timeout Accuracy (max Δ%)   ___%
-----------------------------------------------------
  ROUTING PATH TIMING (1:1 Send)
-----------------------------------------------------
  Routing: Reuse (warm)       p50=___   p95=___
  Routing: Direct (cold)      p50=___   p95=___
  Routing: Relay Probe        p50=___   p95=___
  Routing: Inbox Fallback     p50=___   p95=___
  Routing: Budget Starvation  p50=___   p95=___
  Routing: Worst-Case         p50=___   p95=___
  Routing: Reconnect          p50=___   p95=___
  Routing: Path Distribution  direct=_ reuse=_ relay=_ inbox=_
-----------------------------------------------------
  TWO-SIMULATOR SMOKE (Both Sides Measured)
-----------------------------------------------------
  E2E: Cold send               sender=___  receiver=___  e2e=___ms
  E2E: Warm send (5 msgs)      sender p50=___  e2e p50=___ms
  E2E: Inbox → drain → deliver sender=___  drain=___  e2e=___ms
  E2E: Reconnect send          sender=___  e2e=___ms
  E2E: Bidirectional (3 exch)  alice→bob=___  bob→alice=___ms
  E2E: Stale recovery          sender=___  e2e=___ms
  E2E: Full lifecycle (S8)     e2e p50=___ms  total=___ms
  E2E: S8 path distribution    direct=_ reuse=_ relay=_ inbox=_
=====================================================
```

---

## Implementation Order

### Phase 0: Shared Harness (prerequisite for all tests)

| Item | Effort | Files |
|---|---|---|
| **0a** BenchmarkHarness (Dart) | ~50 lines | `test/performance/benchmark_harness.dart` + `_test.dart` |
| **0b** BenchmarkEventCollector (Go) | ~40 lines | `go-mknoon/node/benchmark_harness_test.go` |
| **0c** TimingTestBridge (Dart) | ~30 lines | `test/performance/timing_test_bridge.dart` + `_test.dart` |
| **0d** Test gate registration | ~3 lines | `scripts/run_test_gates.sh` |

### Phase 1: Tests That Need Only Dart-Side Instrumentation (03c §1–§10, §14–§15, §19, §24)

These can run on existing fakes with `captureFlowEvents`, no Go rebuild needed.

| Priority | Test | Instrumentation Dependency | Effort | Why first |
|---|---|---|---|---|
| 1 | **M** Time-to-Online Badge | §24 | ~60 lines | Most user-visible metric; validates cold/recovery/hot paths |
| 2 | **A** Per-Step 1:1 Send | §7, §10 | ~80 lines | Fills #1 blind spot — cold vs warm send |
| 3 | **J** Connection Reuse Hit Rate | §7, §10 | ~50 lines | Quantifies fast-path effectiveness |
| 4 | **K** Voice Sub-Steps | §8 | ~40 lines | Simple, high-value split |
| 5 | **F** Bridge Crossing (Dart-side) | §14 | ~40 lines | Establishes bridge overhead baseline |
| 6 | **C** Relay Recovery (Dart-side) | §19, §24, 03d §4 | ~60 lines | Recovery timing + timeout path |
| 7 | **D** Inbox Round-Trip (Dart-side) | §12 | ~40 lines | Inbox fallback latency |
| 8 | **G** Encryption (Dart-side) | §15 | ~40 lines | Crypto overhead baseline |
| 9 | **R** Routing Path Matrix | §7, §10 | ~300 lines | Covers every 1:1 routing path — baseline for 04b changes |

### Phase 2: Tests That Need Go-Side Instrumentation (03c §4, §6, §11, §16–§18, §21–§23)

Require `make all` + `pod install` rebuild.

| Priority | Test | Instrumentation Dependency | Effort | Why first |
|---|---|---|---|---|
| 10 | **B** Node Startup (Go-side) | §4, §11, §18 | ~50 lines Go | Startup breakdown — validates Go per-phase timing |
| 11 | **I** Event Queue Wait | §6 | ~50 lines Go | Reveals hidden dispatch latency |
| 12 | **E** Media Transfer (Go-side) | §21, 03d §3, §5 | ~80 lines Go | Media stream open + throughput + stall detection |
| 13 | **H** Timeout Accuracy | §23, 03d §1–§5 | ~100 lines Go | Validates all timeout constants |
| 14 | **L** Deferred ACK (Go-side) | §9 | ~50 lines Go | ACK budget consumption |
| 15 | **G** Encryption (Go-side) | §16, §22 | ~50 lines Go | ML-KEM + group crypto timing |

### Phase 3: Instrumentation Verification on Simulator (spot-checks)

These run the same `flutter test integration_test/...` path but focus on verifying specific instrumentation works end-to-end with the real bridge. They are a stepping stone — if these pass, Phase 4 will produce valid numbers.

| Priority | Test | Effort | Why here |
|---|---|---|---|
| 16 | **F** Bridge Crossing (integration) | ~30 lines | Validates BRIDGE_CALL_TIMING with real MethodChannel |
| 17 | **M** Time-to-Online Widget (integration) | ~40 lines | Validates TIME_TO_ONLINE_BADGE_WIDGET with real widget |
| 18 | **E** Media Transfer (integration) | ~40 lines | Validates media:upload_complete with real Go media handler |

### Phase 4: Simulator Benchmarks (produce real baseline numbers)

**This is the phase that fills in the 03b Section 5 baseline table.** Each harness runs on a real iOS simulator with the live Go bridge and real network.

Requires: all 03c instrumentation + 03d hazard fixes implemented, `make all` + `pod install` done, simulator available.

| Priority | Test | File | Scenarios | Effort |
|---|---|---|---|---|
| 19 | **A** 1:1 Send | `benchmark_1_1_send_harness.dart` | A-Sim-1, A-Sim-2, A-Sim-3 | ~150 lines |
| 20 | **B** Node Startup | `benchmark_node_startup_harness.dart` | B-Sim-1, B-Sim-2, B-Sim-3 | ~120 lines |
| 21 | **C** Relay Recovery | `benchmark_relay_recovery_harness.dart` | C-Sim-1, C-Sim-2 | ~120 lines |
| 22 | **D** Inbox Round-Trip | `benchmark_inbox_harness.dart` | D-Sim-1, D-Sim-2 | ~100 lines |
| 23 | **E** Media Transfer | `benchmark_media_harness.dart` | E-Sim-1, E-Sim-2 | ~120 lines |
| 24 | **F** Bridge Crossing | `benchmark_bridge_crossing_harness.dart` | F-Sim-1 | ~60 lines |
| 25 | **G** Encryption | `benchmark_encryption_harness.dart` | G-Sim-1, G-Sim-2, G-Sim-3 | ~120 lines |
| 26 | **H** Timeout Accuracy | `benchmark_timeout_accuracy_harness.dart` | H-Sim-1, H-Sim-2 | ~100 lines |
| 27 | **I** Event Queue Wait | `benchmark_event_queue_harness.dart` | I-Sim-1 | ~60 lines |
| 28 | **J** Connection Reuse | `benchmark_connection_reuse_harness.dart` | J-Sim-1 | ~80 lines |
| 29 | **K** Voice Sub-Steps | `benchmark_voice_harness.dart` | K-Sim-1 | ~60 lines |
| 30 | **L** Deferred ACK | `benchmark_ack_harness.dart` | L-Sim-1 | ~60 lines |
| 31 | **M** Time-to-Online | `benchmark_time_to_online_harness.dart` | M-Sim-1, M-Sim-2, M-Sim-3 | ~120 lines |
| 32 | **R** Routing Paths | `benchmark_routing_paths_harness.dart` | R-Sim-1 through R-Sim-8 | ~250 lines |
| 33 | Orchestrator Script | `scripts/run_benchmark_suite.dart` | All | ~200 lines |

All files in `integration_test/` directory. Run via:
```bash
dart run integration_test/scripts/run_benchmark_suite.dart -d <SIMULATOR_ID>
```

### Phase 5: Two-Simulator Interactive Smoke Tests (end-to-end delivery + timing)

**This is the phase that verifies messages actually arrive through the full Dart stack on both sides.** Two Flutter apps run on two iOS simulators, coordinated via shared signal files. Both sides report timing — sender latency AND receiver processing time.

Requires: all 03c instrumentation implemented, `make all` + `pod install` done, **two simulators** available.

| Priority | Scenario | Description | Effort |
|---|---|---|---|
| 34 | **S1** Cold send | Both sides measure — cold discover+dial, e2e delivery | Part of harness |
| 35 | **S2** Warm send | Connection reuse, 5 messages, both sides timed | Part of harness |
| 36 | **S3** Offline → inbox | Bob stops node, Alice sends to inbox, Bob restarts + drains | Part of harness |
| 37 | **S4** Reconnect | First send after Bob restarts — routing recovery | Part of harness |
| 38 | **S5** Bidirectional | Both sides send and receive — symmetric routing | Part of harness |
| 39 | **S6** Stale connection | Bob killed abruptly, Alice's stale reuse → fallback | Part of harness |
| 40 | **S7** All-paths-fail | Bob offline, all paths fail, wireEnvelope retained | Part of harness |
| 41 | **S8** Full lifecycle | 10-message conversation through every routing path | Part of harness |
| 42 | Orchestrator | `run_routing_smoke_2sim.dart` | ~300 lines |

Run via:
```bash
dart run integration_test/scripts/run_routing_smoke_2sim.dart \
  --alice-device 38FECA55-03C1-4907-BD9D-8E64BF8E3469 \
  --bob-device 5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

---

## Dependencies Graph

```
                       ┌──────────────┐
                       │  0. Harness  │
                       │  (0a-0d)     │
                       └──────┬───────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
     ┌─────────────┐  ┌───────────┐   ┌────────────┐
     │ Phase 1     │  │ Phase 2   │   │ Phase 3    │
     │ Dart unit   │  │ Go unit   │   │ Sim spot-  │
     │ (fakes)     │  │ (go test) │   │ checks     │
     │ A,C,D,F,    │  │ B,E,G,    │   │ F,M,E      │
     │ G,J,K,M,R   │  │ H,I,L     │   │            │
     └──────┬──────┘  └─────┬─────┘   └──────┬─────┘
            │                │                │
            │  Validates     │  Validates      │  Validates
            │  event fields  │  Go events      │  end-to-end
            │  + code paths  │  + timeout fire  │  w/ real bridge
            │                │                │
            └────────────────┼────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │    Phase 4      │
                    │  Simulator      │
                    │  Benchmarks     │
                    │  (A–M + R       │
                    │  + orchestrator)│
                    └────────┬────────┘
                             │
                             │  Live GoBridgeClient
                             │  + real relay server
                             │  + real MethodChannel
                             │  + Go CLI test peer
                             ▼
                    ┌─────────────────┐
                    │  Baseline Table │
                    │  (03b §5 — real │
                    │   p50/p95 nums) │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │    Phase 5      │
                    │  Two-Device     │
                    │  Smoke Tests    │
                    │  (S1–S10 +      │
                    │  orchestrator)  │
                    └────────┬────────┘
                             │
                             │  Flutter on simulator
                             │  + Go CLI test peer
                             │  + signal file protocol
                             │  + delivery verification
                             ▼
                    ┌─────────────────┐
                    │  Routing        │
                    │  Regression     │
                    │  Report (S10    │
                    │  timeline)      │
                    └─────────────────┘
```

### Cross-Cutting Dependencies

| Test | Needs 03c Sections | Needs 03d Sections | Needs Go Rebuild |
|---|---|---|---|
| **A** | §4, §7, §10 | — | Yes (§4) |
| **B** | §4, §11, §18, §24 | — | Yes |
| **C** | §19, §24 | §4 | Yes (§4) |
| **D** | §12, §20 | — | Yes |
| **E** | §2, §21 | §3, §5 | Yes |
| **F** | §14 | — | No (Dart) / Yes (integration) |
| **G** | §15, §16, §22 | — | Yes (§16, §22) |
| **H** | §23 | §1, §2, §4, §5 | Yes |
| **I** | §6 | — | Yes |
| **J** | §7, §10 | — | No (Dart-only) |
| **K** | §8 | — | No (Dart-only) |
| **L** | §9 | — | Yes |
| **M** | §18, §24 | — | Yes (§18) / No (§24 Dart-only) |
| **R** | §7, §10 | — | No (Dart-only unit) / Yes (simulator) |

---

## File Inventory

### New Test Files (Dart)

| File | Tests | Lines (est.) |
|---|---|---|
| `test/performance/benchmark_harness.dart` | — (helper) | ~50 |
| `test/performance/benchmark_harness_test.dart` | 8 tests | ~80 |
| `test/performance/timing_test_bridge.dart` | — (helper) | ~30 |
| `test/performance/timing_test_bridge_test.dart` | 4 tests | ~40 |
| `test/performance/benchmark_1_1_send_test.dart` | 6 tests (A1–A6) | ~120 |
| `test/performance/benchmark_node_startup_test.dart` | 6 tests (B1–B6) | ~100 |
| `test/performance/benchmark_relay_recovery_test.dart` | 6 tests (C1–C6) | ~120 |
| `test/performance/benchmark_inbox_roundtrip_test.dart` | 4 tests (D1–D4) | ~80 |
| `test/performance/benchmark_media_transfer_test.dart` | 2 tests (E1–E2) | ~40 |
| `test/performance/benchmark_bridge_crossing_test.dart` | 3 tests (F1–F3) | ~60 |
| `test/performance/benchmark_encryption_test.dart` | 5 tests (G1–G5) | ~80 |
| `test/performance/benchmark_timeout_accuracy_test.dart` | 3 tests (H-Dart-1–3) | ~60 |
| `test/performance/benchmark_event_queue_test.dart` | 1 test (I-Dart-1) | ~30 |
| `test/performance/benchmark_connection_reuse_test.dart` | 3 tests (J1–J3) | ~80 |
| `test/performance/benchmark_voice_send_test.dart` | 3 tests (K1–K3) | ~60 |
| `test/performance/benchmark_deferred_ack_test.dart` | 1 test (L-Dart-1) | ~30 |
| `test/performance/benchmark_time_to_online_test.dart` | 6 tests (M1–M6) | ~100 |
| `test/performance/benchmark_routing_paths_test.dart` | 17 tests (R1–R17) | ~300 |

### New Test Files (Go)

| File | Tests | Lines (est.) |
|---|---|---|
| `go-mknoon/node/benchmark_harness_test.go` | 3 tests + helpers | ~60 |
| `go-mknoon/node/benchmark_send_test.go` | 2 tests (A-Go-1–2) | ~50 |
| `go-mknoon/node/benchmark_startup_test.go` | 3 tests (B-Go-1–3) | ~60 |
| `go-mknoon/node/benchmark_relay_recovery_test.go` | 2 tests (C-Go-1–2) | ~40 |
| `go-mknoon/node/benchmark_inbox_test.go` | 2 tests (D-Go-1–2) | ~50 |
| `go-mknoon/node/benchmark_media_test.go` | 6 tests (E-Go-1–6) | ~100 |
| `go-mknoon/node/benchmark_crypto_test.go` | 3 tests (G-Go-1–3) | ~50 |
| `go-mknoon/node/benchmark_timeout_accuracy_test.go` | 9 tests (H-Go-1–9) | ~150 |
| `go-mknoon/node/benchmark_event_queue_test.go` | 3 tests (I-Go-1–3) | ~60 |
| `go-mknoon/node/benchmark_ack_test.go` | 4 tests (L-Go-1–4) | ~70 |

### New Integration Test Files (Phase 3 — spot-checks)

| File | Tests | Lines (est.) |
|---|---|---|
| `integration_test/benchmark_bridge_crossing_test.dart` | 1 test (F-Int-1) | ~40 |
| `integration_test/benchmark_time_to_online_test.dart` | 2 tests (M-Int-1–2) | ~60 |
| `integration_test/benchmark_media_test.dart` | 1 test (E-Int-1) | ~40 |

### New Simulator Benchmark Files (Phase 4 — real timing)

| File | Scenarios | Lines (est.) |
|---|---|---|
| `integration_test/benchmark_1_1_send_harness.dart` | A-Sim-1, A-Sim-2, A-Sim-3 | ~150 |
| `integration_test/benchmark_node_startup_harness.dart` | B-Sim-1, B-Sim-2, B-Sim-3 | ~120 |
| `integration_test/benchmark_relay_recovery_harness.dart` | C-Sim-1, C-Sim-2 | ~120 |
| `integration_test/benchmark_inbox_harness.dart` | D-Sim-1, D-Sim-2 | ~100 |
| `integration_test/benchmark_media_harness.dart` | E-Sim-1, E-Sim-2 | ~120 |
| `integration_test/benchmark_bridge_crossing_harness.dart` | F-Sim-1 | ~60 |
| `integration_test/benchmark_encryption_harness.dart` | G-Sim-1, G-Sim-2, G-Sim-3 | ~120 |
| `integration_test/benchmark_timeout_accuracy_harness.dart` | H-Sim-1, H-Sim-2 | ~100 |
| `integration_test/benchmark_event_queue_harness.dart` | I-Sim-1 | ~60 |
| `integration_test/benchmark_connection_reuse_harness.dart` | J-Sim-1 | ~80 |
| `integration_test/benchmark_voice_harness.dart` | K-Sim-1 | ~60 |
| `integration_test/benchmark_ack_harness.dart` | L-Sim-1 | ~60 |
| `integration_test/benchmark_time_to_online_harness.dart` | M-Sim-1, M-Sim-2, M-Sim-3 | ~120 |
| `integration_test/benchmark_routing_paths_harness.dart` | R-Sim-1 through R-Sim-8 | ~250 |
| `integration_test/scripts/run_benchmark_suite.dart` | Orchestrator | ~200 |

### New Two-Simulator Smoke Test Files (Phase 5 — end-to-end delivery)

| File | Role | Lines (est.) |
|---|---|---|
| `integration_test/routing_smoke_alice_harness.dart` | Alice (Simulator 1) — S1–S8 sender-first side | ~350 |
| `integration_test/routing_smoke_bob_harness.dart` | Bob (Simulator 2) — S1–S8 receiver-first side | ~350 |
| `integration_test/scripts/run_routing_smoke_2sim.dart` | Orchestrator — launches both, merges results | ~300 |

### Modified Files

| File | Change |
|---|---|
| `scripts/run_test_gates.sh` | Add `benchmark` and `benchmark-sim` gates |

---

## Total Scope

| Category | Tests | Files | Estimated Lines |
|---|---|---|---|
| Shared harness (Dart) | 12 | 4 | ~200 |
| Shared harness (Go) | 3 | 1 | ~60 |
| Phase 1: Instrumentation verification (Dart) | 66 | 14 | ~1,260 |
| Phase 2: Instrumentation verification (Go) | 34 | 8 | ~630 |
| Phase 3: Simulator spot-checks | 4 | 3 | ~140 |
| Phase 4: Simulator benchmarks | 35 scenarios | 15 | ~1,720 |
| **Phase 5: Two-simulator smoke tests** | **8 scenarios** | **3** | **~1,000** |
| Script changes | — | 1 | ~5 |
| **Total** | **162+ tests/scenarios** | **49** | **~5,015** |

---

## Baseline Table Mapping

The baseline table from 03b Section 5 is filled **exclusively from Phase 4 simulator benchmarks** — these are the only tests that produce real timing numbers.

Phase 1–2 unit tests verify instrumentation correctness (right fields, right code paths) but produce synthetic timing values and do NOT feed the baseline table.

| Baseline Metric | Phase 4 Source | Benchmark Key |
|---|---|---|
| 1:1 Send (cold) p50, p95 | A-Sim-1 | `sim_1_1_cold_send_ms` |
| 1:1 Send (warm) p50, p95 | A-Sim-2 | `sim_1_1_warm_send_ms` |
| Node Startup (Go) p50, p95 | B-Sim-1, B-Sim-2 | `sim_startup_total_discoverable_ms` |
| Time-to-Online Badge p50, p95 | M-Sim-1, B-Sim-2 | `sim_time_to_online_badge_ms` |
| Relay Recovery p50, p95 | C-Sim-1, C-Sim-2 | `sim_relay_recovery_ms` |
| Relay Outage (total) p50, p95 | C-Sim-1 | `sim_relay_total_outage_ms` |
| Inbox Store (warm) p50, p95 | D-Sim-1 | `sim_inbox_store_ms` |
| Inbox E2E Delivery p50, p95 | D-Sim-2 | `sim_inbox_e2e_delivery_ms` |
| Event Queue Wait p50, p95 | I-Sim-1 | `sim_event_queue_idle_ms` |
| Media 5MB Upload p50, p95 | E-Sim-1 | `sim_media_5mb_upload_ms` |
| Media Stream Open p50, p95 | E-Sim-1 | `sim_media_stream_open_ms` |
| Media Throughput (bytes/s) p50, p95 | E-Sim-1 | `sim_media_throughput_bytes_per_sec` |
| Voice Upload Phase p50, p95 | K-Sim-1 | `sim_voice_upload_ms` |
| Voice Transport Phase p50, p95 | K-Sim-1 | `sim_voice_send_ms` |
| Direct ACK Round-Trip p50, p95 | L-Sim-1 | `sim_direct_ack_wait_ms` |
| Bridge: MethodChannel RT p50, p95 | F-Sim-1 | `sim_bridge_crossing_ms` |
| Crypto: ML-KEM keygen p50, p95 | G-Sim-1 | `sim_mlkem_keygen_ms` |
| Crypto: ML-KEM encrypt p50, p95 | G-Sim-2 | `sim_encrypt_*_ms` |
| Connection Reuse Hit Rate % | J-Sim-1 | `sim_connection_reuse_hit_rate_pct` |
| Timeout Accuracy (max delta %) | H-Sim-1, H-Sim-2 | `sim_timeout_max_deviation_pct` |
| **Routing Path Timing** | | |
| Routing: Reuse (warm) p50, p95 | R-Sim-1 | `sim_routing_reuse_ms` |
| Routing: Direct (cold) p50, p95 | R-Sim-2 | `sim_routing_direct_cold_ms` |
| Routing: Relay Probe p50, p95 | R-Sim-3 | `sim_routing_relay_probe_ms` |
| Routing: Inbox Fallback p50, p95 | R-Sim-4 | `sim_routing_inbox_fallback_ms` |
| Routing: Budget Starvation p50 | R-Sim-5 | `sim_routing_budget_starvation_ms` |
| Routing: Worst-Case p50 | R-Sim-6 | `sim_routing_worst_case_ms` |
| Routing: Reconnect p50 | R-Sim-7 | `sim_routing_reconnect_ms` |
| Routing: Path Distribution | R-Sim-7 | `sim_routing_distribution` |
| **Two-Simulator Smoke Tests (E2E Delivery — Both Sides)** | | |
| E2E: Cold send (sender + receiver + e2e) | S1 | `S1_e2e_cold_send_ms` |
| E2E: Warm send p50 (sender + receiver) | S2 | `S2_e2e_warm_ms` |
| E2E: Inbox store → drain → delivery | S3 | `S3_e2e_inbox_ms` |
| E2E: Reconnect send (sender + receiver) | S4 | `S4_bob_reconnect_receive_ms` |
| E2E: Bidirectional (both sides send+recv) | S5 | `S5_bob_send_ms`, `S5_alice_receive_latency_ms` |
| E2E: Stale connection recovery | S6 | `S6_bob_stale_receive_ms` |
| E2E: Full lifecycle routing timeline | S8 | `S8_routing_timeline` |
| E2E: Full lifecycle e2e p50 | S8 | `S8_e2e_p50` |
