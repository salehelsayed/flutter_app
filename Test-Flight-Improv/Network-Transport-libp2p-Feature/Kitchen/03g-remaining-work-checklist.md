# 03b Remaining Work Checklist

> **What this is:** Everything from `03b-timing-improvement-plan.md` and `03e-simulator-timing-tests-tdd-plan.md` that is missing or partially done.
> **What's already done:** All 13 test scenarios (A–M) harnesses + unit tests, all 5 hazard fixes, most instrumentation.
> **Not yet started:** Routing-path benchmarks (03e §15), simulator routing benchmarks (03e §14o), two-simulator smoke tests (03e §16).

---

## 1. Missing Instrumentation (Section 3)

Two production code changes that add observability. No behavior change.

- [x] **Add `POST_SEND_DELIVERY_TIMING` summary event to post delivery runner**
  - File: `lib/features/posts/application/post_delivery_runner.dart`
  - Why: `POST_CREATE_LOCAL_TIMING` covers create, but delivery (direct send + inbox fallback per recipient) has no single `_TIMING` summary — only per-phase events like `POST_SEND_DIRECT_ERROR` and `POST_DIRECT_SEND_FALLBACK_TO_INBOX`
  - What: Add `Stopwatch` around the per-recipient delivery loop, emit `POST_SEND_DELIVERY_TIMING` with `elapsedMs`, `outcome`, `recipientCount`, `directSuccessCount`, `inboxFallbackCount`
  - Effort: ~20 lines Dart

- [x] **Add `messageId` to `CHAT_MSG_SEND_TIMING` success path**
  - File: `lib/features/conversation/domain/models/message_payload.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`
  - Why: Group messages have `messageId` for end-to-end tracing (sender→transport→receiver). 1:1 messages have no equivalent — can't correlate a sender's `CHAT_MSG_SEND_TIMING` with the receiver's `CHAT_MSG_RECEIVE_STORED`
  - What: Add `correlationId` (UUID) to `MessagePayload`, include in `CHAT_MSG_SEND_TIMING` and `CHAT_MSG_RECEIVE_STORED` events
  - Effort: ~30 lines Dart
  - Note: Wire format change — both sender and receiver must be on the new version. Use optional field to maintain backwards compatibility.

---

## 2. Missing Benchmark Harness (Section 2)

Group publish timing rows in the baseline table have no harness.

- [x] **Create group publish benchmark harness**
  - File: `integration_test/benchmark_group_publish_harness.dart`
  - What: Two nodes join the same group via orchestrator. Measure:
    - `GROUP_SEND_MSG_TIMING` with `prepareMs`, `publishMs`, `inboxMs`
    - `group:publish_debug` Go push: `encryptMs`, `signMs`, `topicPeers`
    - `group_message:received` Go push at receiver: `decryptMs`
  - Scenarios:
    - Publish with peers connected (GossipSub delivery)
    - Publish with 0 peers (inbox fallback)
  - Requires: Orchestrator starts two nodes, both join same group, exchanges fixture files
  - Effort: ~150 lines Dart + orchestrator changes
  - Baseline rows filled: `Group Publish (peers ready)`, `Group Publish (0 peers)`

- [x] **Update orchestrator to support group scenarios**
  - File: `integration_test/scripts/run_benchmark_suite.dart`
  - What: Add group scenario support — generate group ID, have both nodes join via `group:join`, exchange group key via fixture
  - Effort: ~80 lines Dart

---

## 3. Critical Blind Spots (Numbers We Don't Have)

These are the metrics that matter most for the user experience and routing strategy decisions. All four have harnesses already written — the gap is running them with the Go CLI test peer online.

### Why they're blocked

All four require a **live second node** (the Go CLI test peer) so the Flutter app can actually complete a send — discover a real peer, dial, get an ACK, transfer bytes. Without the test peer, the harnesses skip with `[SKIP] No CLI peer fixture`.

The orchestrator (`run_benchmark_suite.dart`) already handles starting the test peer, generating identity, writing the fixture, and passing it to harnesses via `--dart-define=CLI_PEER_FIXTURE`. The issue is that previous runs either didn't request the two-node scenarios (`--scenarios A,J,L`) or the test peer wasn't fully online (5s sleep instead of `wait_relay` + `wait_circuit`).

---

### Blind Spot 1: 1:1 Cold Send Latency

> This is the number users feel most. We don't know if it's 200ms or 5 seconds.

**Harness:** `integration_test/benchmark_1_1_send_harness.dart` (exists)
**Orchestrator scenario:** `A` (wired in `_twoNodeHarnesses`)

**What the harness does:**
- Reads CLI peer fixture (peerId, publicKey)
- Creates a `BenchmarkNode` (real `GoBridgeClient` + `P2PServiceImpl`)
- Adds CLI peer as contact
- Sends 5 messages sequentially — msg1 is cold (no prior connection), msg2–5 are warm
- Captures `CHAT_MSG_SEND_TIMING` for each with: `elapsedMs`, `sendPath`, `connectionReused`, `discoverMs`, `dialMs`, `sendMs`, `encryptMs`

**What it produces:**
```
[BENCHMARK] sim_1_1_cold_send_ms = <X>ms
[BENCHMARK] sim_1_1_warm_send_ms p50=<X>ms p95=<X>ms (n=4)
[BENCHMARK] sim_1_1_send_path_distribution direct=<N> relay=<N> inbox=<N> reuse=<N>
```

**How to run it:**
```bash
# 1. Build CLI test peer (one-time)
cd go-mknoon && go build -o bin/testpeer ./cmd/testpeer/ && cd ..

# 2. Boot primary simulator
xcrun simctl boot 38FECA55-03C1-4907-BD9D-8E64BF8E3469

# 3. Run via orchestrator (handles test peer lifecycle)
dart run integration_test/scripts/run_benchmark_suite.dart \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 \
  --scenarios A
```

**What to look for in the output:**
- `sim_1_1_cold_send_ms` < 3000ms would be good. > 5000ms means the direct race is timing out and falling to relay probe or inbox.
- `sendPath` on msg1: `direct` means discover+dial worked within 2s budget. `relay` means direct timed out, probe found the peer. `inbox` means everything failed and we stored offline.
- `discoverMs` vs `dialMs` vs `sendMs`: reveals which sub-step dominates cold send latency. If `discoverMs` ≈ 2000ms, that's the budget starvation from `04b`.

**Orchestrator fix needed:** The orchestrator currently sleeps 5s after `start` instead of waiting for the peer to be fully online. This should be changed to send `wait_relay` + `wait_circuit` commands so the test peer is discoverable before harnesses run. Without this, the first cold send may hit a peer that hasn't registered on rendezvous yet — producing misleadingly high numbers.

```dart
// In run_benchmark_suite.dart, after sending 'start':
testPeer.stdin.writeln(jsonEncode({'cmd': 'wait_relay', 'params': {'timeoutSec': 15}}));
// ... read response, confirm ok ...
testPeer.stdin.writeln(jsonEncode({'cmd': 'wait_circuit', 'params': {'timeoutSec': 15}}));
// ... read response, confirm ok ...
// THEN write fixture and run harnesses
```

---

### Blind Spot 2: Connection Reuse Hit Rate

> If reuse is 90%+, cold send latency matters less in practice. If it's 30%, cold sends dominate the experience.

**Harness:** `integration_test/benchmark_connection_reuse_harness.dart` (exists)
**Orchestrator scenario:** `J` (wired in `_twoNodeHarnesses`)

**What the harness does:**
- Sends 10 messages in a scripted workload: 6 sends (phase 1), 5s pause, 4 sends (phase 2)
- Captures `CHAT_MSG_SEND_TIMING` for each
- Counts `connectionReused=true` vs `false`
- Computes hit rate %, cold p50, warm p50

**What it produces:**
```
[BENCHMARK] sim_connection_reuse_hit_rate_pct = <X>%
[BENCHMARK] sim_reuse_cold_send_ms p50=<X>ms (n=<cold_count>)
[BENCHMARK] sim_reuse_warm_send_ms p50=<X>ms (n=<warm_count>)
```

**How to run it:**
```bash
dart run integration_test/scripts/run_benchmark_suite.dart \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 \
  --scenarios J
```

**What to look for:**
- Hit rate > 80%: connection reuse is working well — most interactive sends are fast. Cold send latency is a one-time cost per conversation session.
- Hit rate < 50%: connections are dropping between sends. Investigate: is `peer:disconnected` firing too aggressively? Is the 30s health check clearing live connections? The 5s pause between phases tests whether a short idle gap kills the connection.
- Cold vs warm latency split: if warm is <100ms and cold is >2000ms, connection reuse is the entire optimization — protecting it is the priority.

**Dependencies:** Same orchestrator fix as Blind Spot 1 (test peer must be online and discoverable).

---

### Blind Spot 3: Direct ACK Round-Trip

> If p95 is close to the 2s DirectConfirmTimeout, the timeout is too tight and messages will falsely fall to inbox.

**Harness:** `integration_test/benchmark_ack_harness.dart` (exists)
**Orchestrator scenario:** `L` (wired in `_twoNodeHarnesses`)

**What the harness does:**
- Sends 10 messages to CLI test peer with direct confirm path
- CLI test peer has `autoConfirmDirectAck: true` (configured at start) — it immediately ACKs each message
- Captures `ackRoundTripMs` from `CHAT_MSG_SEND_TIMING` details and `message:direct_ack_timing` Go push events
- Computes p50, p95 of ACK wait time

**What it produces:**
```
[BENCHMARK] sim_direct_ack_wait_ms p50=<X>ms p95=<X>ms (n=10)
```

**How to run it:**
```bash
dart run integration_test/scripts/run_benchmark_suite.dart \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 \
  --scenarios L
```

**What to look for:**
- p95 < 500ms: plenty of headroom within the 2s `DirectConfirmTimeout`. The timeout is fine.
- p95 between 1000ms–1800ms: tight — real-world latency variance could push some messages past the timeout, causing false inbox fallbacks. Consider widening `DirectConfirmTimeout` or the overall `interactiveDirectBudget`.
- p95 > 1800ms: the timeout is definitely too tight. Messages are racing the 2s deadline. The sender's `sendMessageWithReply` timeout and the ACK confirm timeout are both 2s — they can collide, causing the sender to time out at the same moment the ACK arrives.

**Orchestrator requirement:** The CLI test peer must be started with `autoConfirmDirectAck: true` in the `start` params. Check that the orchestrator passes this:
```dart
testPeer.stdin.writeln(jsonEncode({
  'cmd': 'start',
  'params': {'autoRegister': true, 'autoConfirmDirectAck': true},
}));
```

---

### Blind Spot 4: Media Throughput

> Unknown whether 5MB uploads take 2s or 30s over relay.

**Harness:** `integration_test/benchmark_media_harness.dart` (exists)
**Orchestrator scenario:** `E` (in `_singleNodeHarnesses` — but has two-node path inside)

**What the harness does (single-node / no test peer):**
- Creates 1MB and 5MB temp files
- Attempts `callP2PMediaUpload` — measures `media:stream_open_timing` and `media:upload_complete` Go push events
- Without a test peer, it only measures stream open (which fails because no peer to receive)

**What the harness does (with test peer):**
- Reads CLI peer fixture
- Uploads 1MB and 5MB files to the real test peer via relay
- CLI test peer has media handler running (accepts uploads via libp2p stream)
- Captures: `totalMs`, `totalBytes`, `throughputBytesPerSec`

**What it produces:**
```
[BENCHMARK] sim_media_1mb_upload_ms = <X>ms
[BENCHMARK] sim_media_5mb_upload_ms = <X>ms
[BENCHMARK] sim_media_stream_open_ms = <X>ms
[BENCHMARK] sim_media_throughput_bytes_per_sec = <X>
```

**How to run it:**
```bash
# E is in _singleNodeHarnesses but needs fixture for two-node path.
# Run A first (which starts the test peer), then E will find the fixture.
dart run integration_test/scripts/run_benchmark_suite.dart \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 \
  --scenarios A,E
```

**What to look for:**
- 5MB in < 5s (1+ MB/s): relay throughput is acceptable for images and short videos.
- 5MB in 10–30s: relay is a bottleneck. Consider: local WiFi path for co-located peers, compression before upload, or chunked upload with progress.
- `media_stream_open_ms` > 2000ms: the stream setup itself is slow — circuit relay negotiation is expensive. This is separate from transfer throughput and may warrant connection pre-warming for media.
- Compare 1MB vs 5MB: if 5MB is 5x the 1MB time, throughput is consistent. If 5MB is 10x+, there's a scaling issue (perhaps per-chunk overhead or relay throttling).

**Orchestrator fix needed:** Move `E` from `_singleNodeHarnesses` to `_twoNodeHarnesses` so it runs while the CLI test peer is alive and the fixture is available. Or run it after A/J/L in the two-node phase. Currently `E` runs in Phase 1 (single-node) where no test peer is running — it always hits the `[SKIP]` fallback for two-node media transfer.

```dart
// Fix: move E to _twoNodeHarnesses
const _twoNodeHarnesses = <String, String>{
  'A': 'integration_test/benchmark_1_1_send_harness.dart',
  'D': 'integration_test/benchmark_inbox_harness.dart',
  'E': 'integration_test/benchmark_media_harness.dart',     // ← move here
  'J': 'integration_test/benchmark_connection_reuse_harness.dart',
  'L': 'integration_test/benchmark_ack_harness.dart',
};
```

---

### Run All 4 Blind Spots at Once

```bash
# 1. Build test peer
cd go-mknoon && go build -o bin/testpeer ./cmd/testpeer/ && cd ..

# 2. Boot simulator
xcrun simctl boot 38FECA55-03C1-4907-BD9D-8E64BF8E3469

# 3. Run all 4 blind spots (A=cold send, J=reuse, L=ACK, E=media)
dart run integration_test/scripts/run_benchmark_suite.dart \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 \
  --scenarios A,J,L,E
```

### Orchestrator Fixes Required Before Running

| Fix | File | Change | Effort | Status |
|---|---|---|---|---|
| Wait for test peer to be online | `run_benchmark_suite.dart` | Replace 5s sleep with `wait_relay` + `wait_circuit` commands | ~15 lines | **DONE** |
| Pass `autoConfirmDirectAck` | `run_benchmark_suite.dart` | Add to `start` params | 1 line | **DONE** |
| Move E to two-node phase | `run_benchmark_suite.dart` | Move from `_singleNodeHarnesses` to `_twoNodeHarnesses` | 1 line | **DONE** |
| Include ML-KEM public key in fixture | `run_benchmark_suite.dart` | Call `mlkem_keygen`, add `mlKemPublicKey` to fixture JSON | ~10 lines | **DONE** |

All 4 fixes applied. Also refactored test peer I/O to use a broadcast stream with `peerCommand()` helper for proper multi-command sequencing (replaces raw `firstWhere` on single-subscription stream). Added `R` scenario for routing paths harness. After applying them, `--scenarios A,J,L,E,R` will produce all blind spot + routing numbers in a single run.

---

### Other Missing Baseline Numbers

These are less critical but still have no number:

| Baseline Row | Test | Why Missing | Blocked By |
|---|---|---|---|
| Group Publish (peers ready) | GP | Harness exists, needs two-node group run | Orchestrator group scenario |
| Group Discovery (join→connected) | — | Scoped to 04b routing plan | 04b |
| Inbox E2E Delivery | D-Sim-2 | Needs CLI peer to store then retrieve | Orchestrator run with `--scenarios D` |
| Voice Upload/Transport (primary device) | K-Sim-1 | iPhone 16 number exists (156ms/95ms) — needs iPhone 17 Pro re-run | Re-run `--scenarios K` on primary |
| Timeout Accuracy | H-Sim-1/2 | Returns instant error, not real timeout | Needs actual hanging peer (network sim) |

### Rows verified on primary device (iPhone 17 Pro)

| Baseline Row | Value | Status |
|---|---|---|
| Time-to-Online Badge | p50=152ms p95=157ms | Done |
| Relay Recovery | p50=9114ms p95=9315ms | Done |
| Event Queue Wait (idle) | p50=46ms p95=52ms | Done |
| Crypto: ML-KEM keygen | p50=1ms p95=7ms | Done |
| Crypto: ML-KEM encrypt 100KB | enc=2ms, dec=3ms | Done |

### Rows verified on iPhone 16 (secondary device)

| Baseline Row | Value | Status |
|---|---|---|
| Bridge: MethodChannel RT | p99=5ms | Done |
| Time-to-Online Badge | 193ms | Done |
| Relay Recovery | 9,113ms | Done |
| Event Queue Wait | p50=47ms p95=53ms | Done |
| Inbox Store | 104ms | Done |
| Voice Upload Phase | 156ms | Done |
| Voice Transport Phase | 95ms | Done |

---

## 4. Routing-Path Timing Benchmarks (03e §15 — Not Yet Started)

17 unit tests that force each distinct 1:1 routing path and capture timing. Creates a before/after baseline so any `04b` routing strategy change has a measurable impact.

**Source:** `03e-simulator-timing-tests-tdd-plan.md` Section 15

- [x] **Create `test/performance/benchmark_routing_paths_test.dart`** (~300 lines) — **DONE, 17/17 tests passing**
  - R1: WiFi local send
  - R2: Direct P2P cold (no WiFi)
  - R3: WiFi vs Direct race — WiFi wins
  - R4: WiFi vs Direct race — Direct wins
  - R5: WiFi fails, direct succeeds
  - R6: Relay probe — discover fails, probe finds peer on relay
  - R7: Relay probe — dial fails, probe finds peer
  - R8: Relay probe retry — first send fails, 250ms backoff, second succeeds
  - R9: Relay probe noReservation → inbox fallback
  - R10: Probe error → inbox fallback
  - R11: send_failed in race → inbox (no probe — probe ineligible)
  - R12: Budget starvation — slow discover consumes 2s budget (04b baseline)
  - R13: Unacked inbox handoff — sent=true, acked=false
  - R14: Stale connection — reuse fails, falls to race
  - R15: Worst-case cascade — all paths fail
  - R16: Interactive inbox timeout — 15s vs intended 3s (04b baseline)
  - R17: Probe eligibility matrix — 6 sub-cases
  - Also added to `FakeP2PService`: `probeRelayResult`, `dialAlwaysFails`, `discoverAlwaysFails`, `discoverDelay`, `dialDelay`, `sendDelay`

---

## 5. Simulator Routing Benchmarks (03e §14o — Not Yet Started)

Runs routing-path scenarios on a real simulator with the live Go bridge + Go CLI test peer to produce real timing numbers for each routing decision.

**Source:** `03e-simulator-timing-tests-tdd-plan.md` Section 14o

- [x] **Create `integration_test/benchmark_routing_paths_harness.dart`** (~250 lines) — **DONE, 8 scenarios, compiles cleanly**
  - R-Sim-1: Connection reuse — warm send to connected peer
  - R-Sim-2: Direct P2P — cold send to discoverable peer
  - R-Sim-3: Relay probe — peer behind relay, not directly discoverable
  - R-Sim-4: Inbox fallback — peer offline
  - R-Sim-5: Budget starvation — slow relay, discover takes >1.5s
  - R-Sim-6: Worst-case path cascade — total failure timing
  - R-Sim-7: Routing path distribution over realistic workload (cold → warm → offline → reconnect)
  - R-Sim-8: Before/after routing change comparison
  - Wired as scenario `R` in orchestrator `_twoNodeHarnesses`

### Baseline rows to fill (routing-specific)

| Baseline Row | Source | Status |
|---|---|---|
| Routing: Reuse (warm) p50/p95 | R-Sim-1 | Not started |
| Routing: Direct (cold) p50/p95 | R-Sim-2 | Not started |
| Routing: Relay Probe p50/p95 | R-Sim-3 | Not started |
| Routing: Inbox Fallback p50/p95 | R-Sim-4 | Not started |
| Routing: Budget Starvation p50 | R-Sim-5 | Not started |
| Routing: Worst-Case p50 | R-Sim-6 | Not started |
| Routing: Reconnect p50 | R-Sim-7 | Not started |
| Routing: Path Distribution | R-Sim-7 | Not started |

---

## 6. Two-Simulator Interactive Smoke Tests (03e §16 — Not Yet Started)

Two Flutter apps on two iOS simulators (Alice on iPhone 17 Pro, Bob on iPhone 17) chatting through every routing path. Verifies **actual message delivery on both sides** through the full Dart stack (listener → DB → UI). Measures true end-to-end latency with same-host clock sync.

**Source:** `03e-simulator-timing-tests-tdd-plan.md` Section 16
**Pattern:** `run_group_multi_device_real.dart` (proven two-simulator orchestrator)

- [x] **Create `integration_test/routing_smoke_alice_harness.dart`** (~370 lines) — **DONE, compiles cleanly**
  - Alice side of all 8 scenarios (sender-first role)
  - Full DI stack: GoBridgeClient, encrypted DB, P2PServiceImpl, ChatMessageListener, ContactRepositoryImpl, MessageRepositoryImpl

- [x] **Create `integration_test/routing_smoke_bob_harness.dart`** (~370 lines) — **DONE, compiles cleanly**
  - Bob side of all 8 scenarios (receiver-first role)
  - DB polling for incoming messages with e2e timing
  - Also sends in S5 (bidirectional) and S8 (lifecycle)
  - Real `warmBackground()` → `drainOfflineInbox()` in S3/S8

- [x] **Rewrite `integration_test/scripts/run_routing_smoke_e2e.dart`** (~290 lines) — **DONE, compiles cleanly**
  - Two-simulator orchestrator (replaces old CLI-peer version)
  - Launches Alice + Bob harnesses on two iOS simulators via `flutter drive`
  - Coordinates via shared signal files in `$E2E_SHARED_DIR/smoke_${runId}_*`
  - Combines sender + receiver timing in report

### Scenarios

| Scenario | What It Tests | What Only Two Sims Can Measure |
|---|---|---|
| S1: Cold send | First contact, cold discover+dial | Receiver's ChatMessageListener latency |
| S2: Warm send (×5) | Connection reuse | e2e latency: sender send → receiver DB write |
| S3: Offline → inbox | Bob stops node, inbox fallback, Bob restarts + real inbox drain | Real `warmBackground` → `drainOfflineInbox` → ChatMessageListener |
| S4: Reconnect | First send after Bob restarts | Routing recovery measured on both sides |
| S5: Bidirectional | Both sides send and receive | Symmetric routing (same code path, both directions) |
| S6: Stale connection | Bob killed abruptly | Real stale reuse → fallback with actual bridge failure |
| S7: All-paths-fail | Everything down | Verified failure + wireEnvelope retention |
| S8: Full lifecycle | 10-msg conversation through all paths | Complete routing timeline with sender AND receiver timing |

### Simulator devices

| Role | Device | Simulator ID |
|---|---|---|
| Alice | iPhone 17 Pro (iOS 26.1) | `38FECA55-03C1-4907-BD9D-8E64BF8E3469` |
| Bob | iPhone 17 (iOS 26.1) | `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` |

### Baseline rows to fill (two-simulator E2E)

| Baseline Row | Source | Status |
|---|---|---|
| E2E: Cold send (sender + receiver + e2e) | S1 | Not started |
| E2E: Warm send p50 (sender + receiver) | S2 | Not started |
| E2E: Inbox → drain → delivery | S3 | Not started |
| E2E: Reconnect send | S4 | Not started |
| E2E: Bidirectional | S5 | Not started |
| E2E: Stale connection recovery | S6 | Not started |
| E2E: Full lifecycle routing timeline | S8 | Not started |
| E2E: Full lifecycle e2e p50 | S8 | Not started |

Run via:
```bash
dart run integration_test/scripts/run_routing_smoke_2sim.dart \
  --alice-device 38FECA55-03C1-4907-BD9D-8E64BF8E3469 \
  --bob-device 5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

---

## 7. Structured TimingCollector (03b Section 5, Phase 2)

03b describes a structured timing collector that replaces `emitFlowEvent` for benchmarks.

- [ ] **Decide: is `[BENCHMARK]` stdout + `emitFlowEvent` sufficient?**
  - Current approach: harnesses capture `[FLOW]` events via `debugPrint` interception, print `[BENCHMARK]` lines, orchestrator scrapes stdout
  - 03b proposes: `TimingCollector` with `startSpan()`/`endSpan()`, export to SQLite/JSON, `traceId` for cross-layer correlation
  - The current approach works for CI and manual runs. The structured collector would be needed for:
    - Offline post-hoc analysis of multi-run data
    - Correlating Go-side and Dart-side timing for the same operation
    - Automated regression detection (compare runs programmatically)
  - If sufficient: close this item. If not: implement ~200 lines.

---

## 8. Run the Full Orchestrator on Primary Device

This is the "Phase 3" final step — actually filling in the baseline table.

- [x] **Build Go testpeer binary**
  ```bash
  cd go-mknoon && go build -o bin/testpeer ./cmd/testpeer/
  ```

- [x] **Boot primary benchmark device**
  ```bash
  xcrun simctl boot 38FECA55-03C1-4907-BD9D-8E64BF8E3469
  ```

- [x] **Run full benchmark suite on iPhone 17 Pro**
  ```bash
  dart run integration_test/scripts/run_benchmark_suite.dart \
    -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
  ```

- [x] **Run on secondary devices (spot-check for >2x variation)**
  ```bash
  # iPhone 16 (older device)
  dart run integration_test/scripts/run_benchmark_suite.dart \
    -d 8EF2F995-59DC-4B3D-9C2E-55FEF4B84DC4

  # iPhone Air (mid-range)
  dart run integration_test/scripts/run_benchmark_suite.dart \
    -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD
  ```

- [x] **Fill in the 03b Section 5 baseline table with real numbers** (see below)

- [x] **Flag any metric that varies >2x between primary and secondary devices** (no >2x variation found)

---

## Priority Order

| Priority | Item | Section | Effort | Status |
|---|---|---|---|---|
| — | Run full orchestrator on iPhone 17 Pro | §8 | 30 min | **DONE** |
| — | Group publish benchmark harness | §2 | ~230 lines | **DONE** |
| — | POST_SEND_DELIVERY_TIMING event | §1 | ~20 lines | **DONE** |
| — | 1:1 correlation ID | §1 | ~30 lines | **DONE** |
| — | Re-run on secondary devices | §8 | 30 min | **DONE** |
| **1** | **Fix orchestrator (4 fixes for blind spots)** | §3 | **~27 lines** | **DONE** |
| **2** | **Run blind spots: `--scenarios A,J,L,E`** | §3 | **~15 min** | Blocked by device |
| 3 | Routing-path unit tests (R1–R17) | §4 | ~300 lines | **DONE** |
| 4 | Simulator routing benchmarks (R-Sim-1–8) | §5 | ~250 lines | **DONE** |
| 5 | Two-simulator smoke tests (S1–S8) | §6 | ~1,000 lines | **DONE** |
| 6 | Decide on TimingCollector | §7 | 0 or ~200 lines | Open |

### Priorities 1–2: Fill the 4 blind spots (fastest path to impact)

Orchestrator fixes applied (Priority 1 DONE). Need to run on a booted simulator to collect the numbers (Priority 2).

```
Fix orchestrator (§3, ~27 lines)               ← DONE
  │  wait_relay + wait_circuit instead of 5s sleep
  │  autoConfirmDirectAck in start params
  │  move E to _twoNodeHarnesses
  │  add mlKemPublicKey to fixture
  │  refactored to broadcast stream + peerCommand()
  │  added R scenario for routing harness
  ▼
Run --scenarios A,J,L,E,R (~15 min)            ← NEXT (needs booted simulator)
  │  A = cold send latency (the #1 blind spot)
  │  J = connection reuse hit rate
  │  L = direct ACK round-trip
  │  E = media throughput
  │  R = routing path distribution
  ▼
All blind spot + routing baseline numbers filled
```

### Priorities 3–5: Routing coverage — ALL DONE

```
§4 Routing unit tests (R1–R17)                 ← DONE (17/17 passing)
  │  test/performance/benchmark_routing_paths_test.dart
  ▼
§5 Simulator routing benchmarks (R-Sim-1–8)    ← DONE (compiles, wired in orchestrator)
  │  integration_test/benchmark_routing_paths_harness.dart
  ▼
§6 Two-simulator smoke tests (S1–S8)           ← DONE (compiles, orchestrator rewritten)
  │  routing_smoke_alice_harness.dart + routing_smoke_bob_harness.dart
  │  run_routing_smoke_e2e.dart (two-simulator orchestrator)
  ▼
  Ready to run on two simulators
```

---

## Filled Baseline Table

```
=====================================================
  mknoon Transport Timing — Simulator Baseline
  Primary Device: iPhone 17 Pro (iOS 26.1)
  Secondary Device: iPhone 16 (iOS 18.6)
  Date: 2026-04-15
=====================================================
  ⚠ BLIND SPOTS (§3 — fix orchestrator + run)
  ─────────────────────────────────────────────
  1:1 Send (cold)             p50=???   p95=???    ← BLIND SPOT 1 (--scenarios A)
  1:1 Send (warm)             p50=???   p95=???    ← (same run)
  Connection Reuse Hit Rate   ???%                 ← BLIND SPOT 2 (--scenarios J)
  Direct ACK Round-Trip       p50=???   p95=???    ← BLIND SPOT 3 (--scenarios L)
  Media 5MB Upload            ???ms                ← BLIND SPOT 4 (--scenarios E)
  Media Stream Open           ???ms                ← (same run)
  Media Throughput (bytes/s)  ???                   ← (same run)
  ─────────────────────────────────────────────
  MEASURED
  ─────────────────────────────────────────────
  Time-to-Online Badge        p50=152ms p95=157ms  [17 Pro, n=5]
  Relay Recovery              p50=9114ms p95=9315ms [17 Pro, n=3]
  Relay Outage (total)        ~9590ms              [17 Pro]
  Inbox Store (warm)          104ms                [16]
  Event Queue Wait (idle)     p50=46ms  p95=52ms   [17 Pro, n=20]
  Event Queue Wait (loaded)   p50=44ms  p95=46ms   [17 Pro, n=10]
  Voice Upload Phase          156ms                [16]
  Voice Transport Phase       95ms                 [16]
  Voice Upload Share           62%                 [16]
  Bridge: MethodChannel RT    p50=0ms p95=0ms p99=5ms [16, n=1000]
  Crypto: ML-KEM keygen       p50=1ms  p95=7ms     [17 Pro, n=10]
  Crypto: ML-KEM encrypt 100KB 2ms                 [17 Pro]
  Crypto: ML-KEM decrypt 100KB 3ms                 [17 Pro]
  Crypto: Group encrypt       0ms                  [17 Pro]
  Crypto: Group decrypt       0ms                  [17 Pro]
  Source Distribution         relay_state_push=5/5 [17 Pro]
  ─────────────────────────────────────────────
  NEEDS CLI TEST PEER (not blind spots — lower priority)
  ─────────────────────────────────────────────
  Group Publish (peers ready) p50=___   p95=___    (needs two-node group)
  Group Publish (0 peers)     p50=___   p95=___    (needs two-node group)
  Group Discovery             p50=___   p95=___    (scoped to 04b)
  Node Startup (Go)           not broken out — see Time-to-Online
  Inbox E2E Delivery          ___                  (needs CLI test peer)
  Timeout Accuracy (max Δ%)   N/A — instant error, not real timeout
-----------------------------------------------------
  ROUTING PATH TIMING (§5 — not yet started)
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
  TWO-SIMULATOR SMOKE (§6 — not yet started)
-----------------------------------------------------
  E2E: Cold send               sender=___ receiver=___ e2e=___ms
  E2E: Warm send (5 msgs)      sender p50=___ e2e p50=___ms
  E2E: Inbox → drain → deliver sender=___ drain=___ e2e=___ms
  E2E: Reconnect send          sender=___ e2e=___ms
  E2E: Bidirectional           alice→bob=___ bob→alice=___ms
  E2E: Stale recovery          sender=___ e2e=___ms
  E2E: Full lifecycle (S8)     e2e p50=___ms total=___ms
  E2E: S8 path distribution    direct=_ reuse=_ relay=_ inbox=_
=====================================================
```

### Device Variation Check

| Metric | iPhone 17 Pro | iPhone 16 | Ratio |
|---|---|---|---|
| Time-to-Online | 152ms (p50) | 193ms | 1.3x |
| Relay Recovery | 9114ms (p50) | 9107ms (p50) | 1.0x |
| Event Queue Idle | 46ms (p50) | 47ms (p50) | 1.0x |

**No >2x variation found** between primary and secondary devices.

### Still Needs CLI Test Peer (orchestrator two-node run)

These 7 rows require the orchestrator to start the Go CLI test peer:
- 1:1 Send (cold/warm)
- Media Upload (5MB, stream open, throughput)
- Direct ACK Round-Trip
- Connection Reuse Hit Rate
- Inbox E2E Delivery

### Still Needs Implementation (03e §4–§6)

These rows require new test code that hasn't been written yet:
- **8 routing baseline rows** (§5) — need `benchmark_routing_paths_harness.dart` + CLI test peer
- **8 two-simulator E2E rows** (§6) — need `routing_smoke_alice_harness.dart` + `routing_smoke_bob_harness.dart` + `run_routing_smoke_2sim.dart` + two simulators
