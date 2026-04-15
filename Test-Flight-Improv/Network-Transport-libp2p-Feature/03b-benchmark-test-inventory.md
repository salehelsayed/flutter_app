# Benchmark Test Inventory — What Each Test Measures

> **Scope:** Complete inventory of all implemented benchmark tests (Phases 0–5), what each test measures, and whether it applies to 1:1 chat, group chat, or both.
> **Produced by:** `03e-simulator-timing-tests-tdd-plan.md` implementation.
> **Depends on:** `03c-timing-instrumentation-tdd-plan.md` (events collected), `03d-hazard-fixes-tdd-plan.md` (timeout paths exercised).
>
> **2026-04-15 fact-check rerun:** `flutter test test/performance` passed (`00:58 +102: All tests passed`), `go test -v ./node -run '^TestBenchmark'` passed (`27` benchmark tests), `run_benchmark_suite.dart` was rerun on iPhone 17 Pro, and `run_routing_smoke_e2e.dart` was rerun on iPhone 17 Pro + iPhone 17 (`26/26 PASS`). This refresh corrects stale numbers, promotes `N`/`BR` to runnable simulator benchmarks, fixes `H`/`GP` suite output collection, and finishes `E-Sim` so it now emits real low-level media and profile rows on the simulator path.

---

## Applicability Legend

| Symbol | Meaning |
|--------|---------|
| **1:1** | Applies to 1:1 direct chat (peer-to-peer send via discover/dial/send or connection reuse) |
| **GRP** | Applies to group chat (GossipSub pubsub publish + relay inbox fallback) |
| **BOTH** | Applies to both 1:1 and group messaging paths |

### Why Some Tests Apply to Both

1:1 and group messaging share the same underlying infrastructure:
- Same `P2PServiceImpl.startNodeCore()` startup sequence
- Same relay/circuit address system (both need relay online to operate)
- Same `Bridge` / `MethodChannel` crossing (all commands go through `GoBridgeClient`)
- Same inbox store/retrieve mechanism (1:1 uses `inbox:store`, groups use `group:inbox_store`)
- Same media upload pipeline (both support media attachments)
- Same encryption overhead (1:1 uses ML-KEM per-message; groups use AES-256-GCM per-group-key)

### Where They Diverge

| Aspect | 1:1 Chat | Group Chat |
|--------|----------|------------|
| Send mechanism | `sendMessageWithReply()` (direct P2P stream) | `callGroupPublish()` (GossipSub pubsub) |
| Connection reuse | Yes (`isAlreadyConnected` fast path) | No (pubsub is broadcast, not connection-oriented) |
| Encryption | ML-KEM-768 encapsulation per message | AES-256-GCM with shared group key |
| Local WiFi path | Yes (`_tryLocalSend` via Bonjour) | No |
| Relay probe | Yes (stale-discoverability recovery) | No |
| Direct ACK | Yes (`DirectConfirmTimeout` 2s budget) | No (GossipSub is fire-and-forget) |
| Timeout budget | Interactive: 1.5s local, 2s direct, 3s inbox (`interactiveInboxBudget`) | 10s publish, 10s inbox store |
| Send event | `CHAT_MSG_SEND_TIMING` | `GROUP_SEND_MSG_TIMING` |

---

## Phase 0: Shared Harness

### 0a. BenchmarkHarness (Dart)

**File:** `test/performance/benchmark_harness.dart` + `_test.dart`
**Tests:** 12
**Applies to:** BOTH

| Test | What It Measures |
|------|-----------------|
| captureFlowEvents collects events | Verifies the `[FLOW]` event capture mechanism works — intercepts `debugPrint`, parses JSON |
| captureFlowEvents restores state | Verifies `flowEventLoggingEnabled` and `debugPrint` are restored after capture |
| filterEvents returns matching | Verifies event filtering by event name |
| percentile p50 | Verifies median computation: `[10..100]` → p50=55 |
| percentile p95 | Verifies 95th percentile: `[1..100]` → p95=96 |
| percentile single value | Verifies single-element edge case returns the value |
| percentile empty | Verifies empty list returns 0 |
| formatBenchmarkLine | Verifies `[BENCHMARK] metric p50=Xms p95=Xms (n=N)` output format |
| assertBudget passes within | Verifies no assertion failure when p95 < budget |
| assertBudget fails exceeding | Verifies `TestFailure` when p95 > budget |
| extractElapsedMs sorts | Verifies extraction and sorting of `elapsedMs` from event details |
| record prints benchmark | Verifies `record()` calls `formatBenchmarkLine` and prints to stdout |

### 0b. BenchmarkEventCollector (Go)

**File:** `go-mknoon/node/benchmark_harness_test.go`
**Tests:** 3
**Applies to:** BOTH

| Test | What It Measures |
|------|-----------------|
| collectEvents filters by name | Verifies Go-side event filtering: 5 events (3 matching) → returns 3 |
| extractElapsedMs parses and sorts | Verifies Go-side `elapsedMs` extraction from `float64` data maps |
| percentile computes correctly | Verifies Go percentile: p50=55, p95=95 for `[10..100]`, single=42, empty=0 |

### 0c. TimingTestBridge (Dart)

**File:** `test/performance/timing_test_bridge.dart` + `_test.dart`
**Tests:** 5
**Applies to:** BOTH

| Test | What It Measures |
|------|-----------------|
| Default no delays | Verifies `TimingTestBridge` returns immediately when no delays configured |
| Per-command delay applied | Verifies `peer:dial` with 200ms delay takes ≥ 200ms |
| Delay only matching command | Verifies non-matching commands return immediately |
| Timing fields injected | Verifies `responseTimingFields` merges `streamOpenMs`, `writeMs`, `ackWaitMs` into response |
| No injection for non-matching | Verifies timing fields not added to unrelated commands |

### 0d. Test Gate Registration

**File:** `scripts/run_test_gates.sh`
**Changes:** Added `benchmark` gate (runs `test/performance/`), `benchmark-sim` gate (runs `integration_test/benchmark_*_harness.dart`), and `benchmark / performance suite` classification for completeness check.

---

## Phase 1: Dart Instrumentation Verification (Fakes)

All Phase 1 tests run on the host machine via `flutter test` using fakes. They verify event fields and code paths but produce synthetic timing values.

### Test A: Per-Step 1:1 Send Breakdown

**File:** `test/performance/benchmark_1_1_send_test.dart`
**Tests:** 6
**Applies to:** 1:1

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| A1: Cold send emits breakdown | Verifies `CHAT_MSG_SEND_TIMING` is emitted with `elapsedMs`, `outcome`, `sendPath`, `connectionReused` fields | `CHAT_MSG_SEND_TIMING` |
| A2: Warm send reuse | Verifies `connectionReused=true` and `sendPath='reuse'` when peer is in `currentState.connections` | `CHAT_MSG_SEND_TIMING` |
| A3: Cold vs warm sendPath | Verifies cold send has `connectionReused=false`, warm send has `connectionReused=true` and `sendPath='reuse'` | `CHAT_MSG_SEND_TIMING` |
| A4: Sequential sends reuse | Verifies first of 10 sends is cold (`connectionReused=false`), remaining 9 are warm (`connectionReused=true`) | `CHAT_MSG_SEND_TIMING` × 10 |
| A5: Inbox fallback | Verifies `outcome` is reported when direct send fails and inbox fallback is attempted | `CHAT_MSG_SEND_TIMING` |
| A6: ML-KEM encryption | Verifies `outcome='success'` when contact has ML-KEM public key (encrypted v2 path) | `CHAT_MSG_SEND_TIMING` |

**Sub-step fields measured (when present):** `discoverMs`, `dialMs`, `sendMs`, `encryptMs`, `streamOpenMs`, `writeMs`, `ackWaitMs`

> **Note:** `streamOpenMs`, `writeMs`, `ackWaitMs` originate from the Go `SendMessage` response and are forwarded into the Dart `CHAT_MSG_SEND_TIMING` event via `SendMessageResult`. They appear in all send paths (reuse, direct, relay probe).

### Test B: Node Startup Timing

**File:** `test/performance/benchmark_node_startup_test.dart`
**Tests:** 6
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| B1: Cold start emits badge | Verifies `TIME_TO_ONLINE_BADGE` with `totalMs` ≥ 0, `phase='cold_start'`, `source` is string | `TIME_TO_ONLINE_BADGE` |
| B2: NodeStatusDelay reflects wait | Verifies `totalMs` reflects actual delay when relay push comes after start | `TIME_TO_ONLINE_BADGE` |
| B3: Cold start < 6s budget | Verifies `totalMs` < 6000 (simulator cold start budget) | `TIME_TO_ONLINE_BADGE` |
| B4: Hot restart phase | Verifies `phase='hot_restart'` when `simulateAlreadyStarted=true` | `TIME_TO_ONLINE_BADGE` |
| B5: Source = start_response | Verifies `source='start_response'` when start response itself includes `relayState='online'` | `TIME_TO_ONLINE_BADGE` |
| B6: Source = relay_state_push | Verifies `source='relay_state_push'` when relay push event wins the race | `TIME_TO_ONLINE_BADGE` |

### Test C: Relay Reconnect / Recovery

**File:** `test/performance/benchmark_relay_recovery_test.dart`
**Tests:** 6
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| C1: Detected + recovered | Verifies `RELAY_OUTAGE_TIMING` with `phase='detected'`, `detectionMs`, `detectionSource` | `RELAY_OUTAGE_TIMING` |
| C2: Detection source = push | Verifies `detectionSource='push'` when relay:state push event triggers detection | `RELAY_OUTAGE_TIMING` |
| C3: Detection source = poll | Verifies `detectionSource='poll'` when health check cycle detects degradation | `RELAY_OUTAGE_TIMING` |
| C4: Recovery emits badge | Verifies `TIME_TO_ONLINE_BADGE` with `phase='recovery'` after degrade → recover cycle | `TIME_TO_ONLINE_BADGE` |
| C5: Multiple cycles distinct | Verifies each outage-recovery cycle emits its own distinct events | `RELAY_OUTAGE_TIMING` × 2 cycles |
| C6: Recovered includes recoveryMs | Verifies `phase='recovered'` events include `recoveryMs` and `totalOutageMs` | `RELAY_OUTAGE_TIMING` |

### Test D: Inbox Store/Retrieve Round-Trip

**File:** `test/performance/benchmark_inbox_roundtrip_test.dart`
**Tests:** 4
**Applies to:** BOTH (1:1 uses `inbox:store`, groups use `group:inbox_store`)

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| D1: Inbox store timing | Verifies `CHAT_MSG_SEND_TIMING` is emitted when send falls through to inbox | `CHAT_MSG_SEND_TIMING` |
| D2: Inbox retrieve drains | Verifies `drainOfflineInbox()` returns messages stored via `storeInInbox()` | Network-level drain count |
| D3: Store tracks elapsedMs | Verifies `elapsedMs` ≥ 0 in inbox store path | `CHAT_MSG_SEND_TIMING` |
| D4: Store < 200ms budget | Verifies Dart-side inbox store is fast with fakes (< 200ms) | `CHAT_MSG_SEND_TIMING` |

### Test E-Inbox: Inbox Delivery Timing

**File:** `test/performance/benchmark_inbox_delivery_timing_test.dart`
**Tests:** 7
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| E1: Fallback forward path | Verifies `INBOX_DELIVERY_TIMING` emitted for unknown message type (fallback forward handler) | `INBOX_DELIVERY_TIMING` |
| E2: Chat message path | Verifies `INBOX_DELIVERY_TIMING` emitted for `chat_message` type with committed disposition | `INBOX_DELIVERY_TIMING` |
| E3: Introduction path | Verifies `INBOX_DELIVERY_TIMING` emitted for `introduction` type with committed disposition | `INBOX_DELIVERY_TIMING` |
| E4: Retryable (negative) | Verifies `INBOX_DELIVERY_TIMING` is NOT emitted for retryable dispositions | (none) |
| E5: Batch of 5 entries | Verifies 5 staged entries produce exactly 5 `INBOX_DELIVERY_TIMING` events | `INBOX_DELIVERY_TIMING` × 5 |
| E6: deliveryMs budget | Verifies `deliveryMs` < 100ms with in-memory fakes | `INBOX_DELIVERY_TIMING` |
| E7: messageId truncation | Verifies `messageId` is truncated to 8 characters | `INBOX_DELIVERY_TIMING` |

### Test E-Media: Media Transfer Timing

**File:** `test/performance/benchmark_media_transfer_test.dart`
**Tests:** 2
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| E1: Message emits timing | Verifies `CHAT_MSG_SEND_TIMING` with `hasAttachments`, `outcome`, `elapsedMs` | `CHAT_MSG_SEND_TIMING` |
| E2: Consistent timing emission | Verifies 5 sequential sends all produce `CHAT_MSG_SEND_TIMING` with correct fields | `CHAT_MSG_SEND_TIMING` × 5 |

### Test F: Bridge Crossing

**File:** `test/performance/benchmark_bridge_crossing_test.dart`
**Tests:** 3
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| F1: Single call completes | Verifies bridge `send()` returns `ok: true` and completes in < 50ms | Stopwatch |
| F2: 100 sequential calls | Verifies 100 calls produce timing distribution with p99 < 50ms | Stopwatch × 100 |
| F3: 10 concurrent calls | Verifies 10 concurrent `send()` calls all succeed | `Future.wait` |

### Test G: Encryption Overhead

**File:** `test/performance/benchmark_encryption_test.dart`
**Tests:** 5
**Applies to:** BOTH (1:1 uses ML-KEM; groups use AES-256-GCM)

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| G1: ML-KEM keygen | Verifies `mlkem.keygen` returns `publicKey` + `secretKey` | Bridge response |
| G2: Encrypt returns fields | Verifies `message.encrypt` returns `ciphertext`, `kem`, `nonce` (1:1 path) | Bridge response |
| G3: Decrypt returns plaintext | Verifies `message.decrypt` round-trips correctly (1:1 path) | Bridge response |
| G4: Timing fields injected | Verifies `TimingTestBridge` injects `encryptMs` into response | Bridge response |
| G5: Group encrypt/decrypt | Verifies `group.encrypt` / `group.decrypt` passthrough (group path) | Bridge response |

### Test H: Timeout Accuracy (Dart-side)

**File:** `test/performance/benchmark_timeout_accuracy_test.dart`
**Tests:** 3
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| H-Dart-1: Timeout fires within budget | Verifies `.timeout(500ms)` on hanging bridge fires at 450–750ms | `TimeoutException` |
| H-Dart-2: Multiple timeouts independent | Verifies 3 sequential timeouts each fire at 250–500ms (300ms configured) | `TimeoutException` × 3 |
| H-Dart-3: Non-hanging completes | Verifies non-hanging bridge completes < 100ms (no false timeout) | Stopwatch |

### Test I: Event Queue (Dart-side)

**File:** `test/performance/benchmark_event_queue_test.dart`
**Tests:** 1
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| I-Dart-1: Push event delivery | Verifies 10 relay push events arrive at Dart within idle budget (p95 < 100ms) | `stateStream` delivery lag |

### Test J: Connection Reuse Hit Rate

**File:** `test/performance/benchmark_connection_reuse_test.dart`
**Tests:** 3
**Applies to:** 1:1 only (groups use pubsub, not connection-oriented)

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| J1: Scripted workload | Verifies 9/10 = 90% reuse rate (first cold, 9 warm) | `CHAT_MSG_SEND_TIMING` × 10 |
| J2: Resume scenario | Verifies cold→warm→disconnect→cold→warm produces 4/6 = 67% reuse | `CHAT_MSG_SEND_TIMING` × 6 |
| J3: Latency comparison | Verifies cold p50 ≥ warm p50 (dial overhead) | `CHAT_MSG_SEND_TIMING` × 10 |

### Test K: Voice Send Sub-Steps

**File:** `test/performance/benchmark_voice_send_test.dart`
**Tests:** 3
**Applies to:** BOTH (voice messages can be sent in 1:1 and groups)

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| K1: uploadMs + sendMs | Verifies `VOICE_SEND_TIMING` with `elapsedMs`, `durationMs`, `sizeBytes` | `VOICE_SEND_TIMING` |
| K2: Upload-dominated | Verifies `uploadMs` ≥ 200ms when upload has 200ms delay | `VOICE_SEND_TIMING` |
| K3: Invalid recording | Verifies `outcome` ≠ 'success' for non-existent file | `VOICE_SEND_TIMING` |

### Test L: Deferred Direct ACK

**File:** `test/performance/benchmark_deferred_ack_test.dart`
**Tests:** 1
**Applies to:** 1:1 only (groups use fire-and-forget pubsub)

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| L-Dart-1: ACK in send timing | Verifies `CHAT_MSG_SEND_TIMING` with `sendPath='reuse'`, `connectionReused=true`, `sendMs` field | `CHAT_MSG_SEND_TIMING` |

### Test M: Time-to-Online Badge

**File:** `test/performance/benchmark_time_to_online_test.dart`
**Tests:** 6
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| M1: Cold start badge | Verifies `TIME_TO_ONLINE_BADGE` with `phase='cold_start'`, `totalMs` ≥ 0 | `TIME_TO_ONLINE_BADGE` |
| M2: Recovery badge | Verifies `TIME_TO_ONLINE_BADGE` with `phase='recovery'` after degrade→recover | `TIME_TO_ONLINE_BADGE` |
| M3: Hot restart badge | Verifies `phase='hot_restart'` when `simulateAlreadyStarted=true` | `TIME_TO_ONLINE_BADGE` |
| M4: Source = start_response | Verifies `source='start_response'` when start response has relay online | `TIME_TO_ONLINE_BADGE` |
| M5: Source = relay_state_push | Verifies `source='relay_state_push'` when push event wins | `TIME_TO_ONLINE_BADGE` |
| M6: < 6s budget | Verifies `totalMs` < 6000, prints `[BENCHMARK]` line | `TIME_TO_ONLINE_BADGE` |

### Test R: Routing-Path Timing Benchmarks (1:1 Send — All Paths)

**File:** `test/performance/benchmark_routing_paths_test.dart`
**Tests:** 17 (R1–R17, with R17 containing 6 sub-cases)
**Applies to:** 1:1

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| R1: WiFi local send | Verifies `sendPath='local'` when peer is on LAN, WiFi wins race against slow direct | `CHAT_MSG_SEND_TIMING` |
| R2: Direct P2P cold | Verifies cold discover→dial→send path, `connectionReused=false`, no WiFi | `CHAT_MSG_SEND_TIMING` |
| R3: WiFi vs Direct — WiFi wins | Verifies WiFi (30ms ack) beats slow direct (500ms discover), `sendPath='local'` | `CHAT_MSG_SEND_TIMING` |
| R4: WiFi vs Direct — Direct wins | Verifies fast direct beats slow WiFi (1200ms ack) | `CHAT_MSG_SEND_TIMING` |
| R5: WiFi fails, direct fallback | Verifies `localSendResult=false` → direct wins within race | `CHAT_MSG_SEND_TIMING` |
| R6: Relay probe (discover fails) | Verifies `discoverAlwaysFails` + `probeRelayResult=connected` → `sendPath='relay'` | `CHAT_MSG_SEND_TIMING`, `CHAT_MSG_SEND_RELAY_PROBE_BEGIN` |
| R7: Relay probe (dial fails) | Verifies `dialAlwaysFails` + probe connected → relay send succeeds | `CHAT_MSG_SEND_TIMING` |
| R8: Relay probe retry | Verifies first send fails → 250ms backoff → retry succeeds, `sendPath='relay'` | `CHAT_MSG_SEND_TIMING`, `CHAT_MSG_SEND_RELAY_PROBE_SEND_RETRY` |
| R9: noReservation → inbox | Verifies `probeRelayResult=noReservation` → falls to inbox, `sendPath='inbox'` | `CHAT_MSG_SEND_TIMING`, `CHAT_MSG_SEND_RELAY_PROBE_NO_RESERVATION` |
| R10: Probe error → inbox | Verifies `probeRelayResult=error` → inbox fallback | `CHAT_MSG_SEND_TIMING` |
| R11: send_failed → no probe | Verifies `sendFailCount=999` (send_failed) does NOT trigger relay probe → inbox directly | `CHAT_MSG_SEND_TIMING` (no `RELAY_PROBE_BEGIN`) |
| R12: Budget starvation | Verifies slow discover (1800ms via `TimingTestBridge`) eats into 2s budget — baseline for 04b | `CHAT_MSG_SEND_TIMING` |
| R13: Unacked inbox handoff | Verifies reuse path with sent=true, captures timing for handoff | `CHAT_MSG_SEND_TIMING` |
| R14: Stale connection recovery | Verifies `sendFailCount=1` (reuse fails) → falls through to race, `connectionReused=false` | `CHAT_MSG_SEND_TIMING` |
| R15: Worst-case cascade | Verifies all paths fail (bob offline + inbox disabled) → `outcome='failed'`, `wireEnvelope` retained | `CHAT_MSG_SEND_TIMING` |
| R16: Slow inbox store | Verifies full fallback chain timing when inbox succeeds after probe noReservation | `CHAT_MSG_SEND_TIMING` |
| R17: Probe eligibility matrix | 6 sub-cases: (a) peer_not_found → probe, (b) dial_failed → probe, (c) send_failed → no probe, (d) race timeout → no probe, (e) WiFi+send fail → no probe, (f) discover+WiFi fail → probe | `CHAT_MSG_SEND_RELAY_PROBE_BEGIN` presence/absence |

**FakeP2PService controls used:** `discoverAlwaysFails`, `dialAlwaysFails`, `probeRelayResult`, `sendFailCount`, `localPeers`, `localSendResult`, `localAckDelay`, `discoverDelay`, `testConnections`, `inboxDisabled`

### Test NT: Notification Tap to Message Timing

**File:** `test/performance/benchmark_notification_tap_to_message_test.dart`
**Tests:** 4
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| NT1: Tap emits timing | Verifies `NOTIFICATION_TAP_TO_MESSAGE_TIMING` is emitted with `elapsedMs` ≥ 0 when `notificationTappedAt` is set | `NOTIFICATION_TAP_TO_MESSAGE_TIMING` |
| NT2: routeKind matches type | Verifies `routeKind` field matches the notification type (`conversation` vs `group`) | `NOTIFICATION_TAP_TO_MESSAGE_TIMING` |
| NT3: messageId truncated | Verifies `messageId` is present and truncated to 8 chars for privacy (long ID, short ID, and null cases) | `NOTIFICATION_TAP_TO_MESSAGE_TIMING` |
| NT4: No event for non-message | Verifies event is NOT emitted when `notificationTappedAt` is null (non-message notifications like contact request) | (none) |

**Helper function used:** `emitNotificationTapTiming()` from `lib/core/utils/notification_tap_timing.dart`

### Test BR: Background Resume Badge Timing

**File:** `test/performance/benchmark_background_resume_test.dart`
**Tests:** 4
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| BR1: Resume with relay recovery | Verifies `TIME_TO_ONLINE_BADGE` with `phase='background_resume'` is emitted after simulated pause → resume → relay push cycle | `TIME_TO_ONLINE_BADGE` |
| BR2: Resume already online | Verifies `phase='background_resume_already_online'` when relay was healthy throughout background | `TIME_TO_ONLINE_BADGE` |
| BR3: Timing reflects delay | Verifies `totalMs` reflects actual delay (≥ 50ms) when relay needs to reconnect during resume | `TIME_TO_ONLINE_BADGE` |
| BR4: Distinct from cold start | Verifies resume badge event is distinct from cold-start badge event — cold start emits `phase='cold_start'`, resume emits `phase='background_resume'`, no double-emit | `TIME_TO_ONLINE_BADGE` × 2 (distinct phases) |

---

## Phase 2: Go Instrumentation Verification

All Phase 2 tests run on the host machine via `go test`. They verify Go-side event emission and timing accuracy.

**Rerun status (2026-04-15):** `go test -v ./node -run '^TestBenchmark'` passed with `27` benchmark tests in `3.058s`.

### A-Go: Send Message Timing

**File:** `go-mknoon/node/benchmark_send_test.go`
**Tests:** 2
**Applies to:** 1:1

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| EmitsPerStepTiming | Verifies node starts, connects to peer, and `SendMessage` completes | `node:startup_timing` |
| ConnectionReuse | Verifies two sequential `SendMessage` calls reuse the connection | Send completion × 2 |

### B-Go: Node Startup

**File:** `go-mknoon/node/benchmark_startup_test.go`
**Tests:** 5
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| EmitsStartupTiming | Verifies `node:startup_timing` with `libp2pNewMs` ≥ 0 | `node:startup_timing` |
| ReturnsValidState | Verifies `Start()` returns `PeerId` ≠ "" and `IsStarted=true` | `NodeState` |
| StopStart succeeds | Verifies stop→start cycle completes without error | `NodeState` |
| NoRelays_NoRelayWarmDoneEvent | Verifies `relay_warm_done` is NOT emitted when no relays are configured | `node:startup_timing` |
| RelayWarmDoneEvent | Verifies `relay_warm_done` phase with `relayWarmMs` ≥ 0 and `relaysAttempted` | `node:startup_timing` |

### C-Go: Relay Recovery

**File:** `go-mknoon/node/benchmark_relay_recovery_test.go`
**Tests:** 2
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| RelayState emits on change | Verifies startup completes and reports how many `relay:state` events were emitted during startup (current empty-relay rerun: `0`) | `relay:state` |
| RelayWarm emits timing | Verifies `relay:warm_timing` event count handling with empty relays (current rerun: `0`) | `relay:warm_timing` |

### D-Go: Inbox

**File:** `go-mknoon/node/benchmark_inbox_test.go`
**Tests:** 2
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| InboxStore requires connection | Exercises `InboxStore` against a nonexistent peer and logs whether it errors plus how many `inbox:store_timing` events were emitted (current rerun: call unexpectedly succeeded, events=`0`) | `inbox:store_timing` |
| InboxRetrieve returns empty | Exercises `InboxRetrieve` with no inbox data and logs whether it returns empty or errors plus emitted timing-event count (current rerun: events=`0`) | `inbox:retrieve_timing` |

### E-Go: Media

**File:** `go-mknoon/node/benchmark_media_test.go`
**Tests:** 2
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| MediaUpload requires connection | Verifies `MediaUpload` to unreachable peer fails, logs stream timing | `media:stream_open_timing` |
| ProgressEvents | Verifies `media:upload_progress` event type is recognized | `media:upload_progress` |

### G-Go: Encryption

**File:** `go-mknoon/node/benchmark_crypto_test.go`
**Tests:** 3
**Applies to:** BOTH (ML-KEM = 1:1; group encrypt = groups)

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| MlKemKeygen timing | 10 iterations of `MlKemKeygen()`, computes p50/p95 | `[BENCHMARK] mlkem_keygen_go_ms` |
| Ed25519 sign/verify | Verifies `SignPayload` / `VerifyPayload` API is accessible | API call |
| Group encrypt/decrypt | Verifies `EncryptGroupMessage` / `DecryptGroupMessage` round-trips correctly | AES-256-GCM round-trip |

### H-Go: Timeout Accuracy

**File:** `go-mknoon/node/benchmark_timeout_accuracy_test.go`
**Tests:** 3
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| NodeStart with bad relay | Verifies no `timeout:fired` events are emitted when relays are empty (current rerun: `0`) | `timeout:fired` |
| Send to unreachable peer | Verifies `SendMessage` to invalid peer ID returns quickly and records elapsed wall-clock time (current rerun: `0ms` with `timeout=1000ms`) | Stopwatch |
| DirectAckTimeout | Verifies `message:direct_ack_timing` event count handling (current rerun: `0`) | `message:direct_ack_timing` |

### I-Go: Event Queue

**File:** `go-mknoon/node/benchmark_event_queue_test.go`
**Tests:** 3
**Applies to:** BOTH

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| Idle delivery | 20 events emitted → all 20 delivered within 100ms | `benchmark:test_event` × 20 |
| Burst delivery | 100 events emitted in burst → count delivered within 200ms | `benchmark:burst_event` × 100 |
| No drop under load | 50 lossless events → all 50 must be delivered | `benchmark:lossless_event` × 50 |

### L-Go: ACK Timing

**File:** `go-mknoon/node/benchmark_ack_test.go`
**Tests:** 2
**Applies to:** 1:1

| Test | What It Measures | Event Collected |
|------|-----------------|-----------------|
| Fast confirm | Verifies `SendMessage` to connected peer returns, logs `ackMs` | `message:direct_ack_timing` |
| Multiple messages | 10 messages with p50/p95 computation for round-trip latency | Stopwatch × 10 |

---

## Phase 3–4: Simulator Benchmarks (Real Timing)

All Phase 3–4 tests run on real iOS simulators with the live Go bridge (`GoBridgeClient`), real `MethodChannel`, and real libp2p networking. These produce the actual p50/p95 numbers for the baseline table.

### Shared Infrastructure

**File:** `integration_test/benchmark_helpers.dart`

Provides: `createBenchmarkNode()`, `waitForOnline()`, `captureFlowEvents()`, `filterEvents()`, `percentile()`, `printBenchmark()`, `printBenchmarkSingle()`, `BenchmarkNode` class.

### A-Sim: Per-Step 1:1 Send

**File:** `integration_test/benchmark_1_1_send_harness.dart`
**Scenarios:** 3
**Applies to:** 1:1
**Requires:** Go CLI test peer (A-Sim-1, A-Sim-2), none (A-Sim-3)

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| A-Sim-1: Cold send to test peer | First-contact send latency, cold vs warm split, send path distribution | `CHAT_MSG_SEND_TIMING`: `elapsedMs`, `sendPath`, `connectionReused`, `outcome`, `discoverMs`, `dialMs`, `sendMs`, `streamOpenMs`, `writeMs`, `ackWaitMs` |
| A-Sim-2: 10 warm sequential | Warm send latency with established connection | `CHAT_MSG_SEND_TIMING` × 10: same fields |
| A-Sim-3: Inbox fallback | Latency when peer is offline (inbox path) | `CHAT_MSG_SEND_TIMING`: `sendPath`, `outcome` |

**Baseline table output:** `sim_1_1_cold_send_ms`, `sim_1_1_warm_send_ms`, `sim_1_1_sequential_warm_ms`, `sim_1_1_inbox_fallback_ms`, `sim_1_1_send_path_distribution`, `sim_1_1_stream_open_ms`, `sim_1_1_write_ms`, `sim_1_1_ack_wait_ms`

### B-Sim: Node Startup

**File:** `integration_test/benchmark_node_startup_harness.dart`
**Scenarios:** 3
**Applies to:** BOTH
**Requires:** None (single-node)

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| B-Sim-1: Cold start phases | Per-phase startup timing, circuit address acquisition, widget transition | `TIME_TO_ONLINE_BADGE`: `totalMs`, `phase`, `source`; `node:startup_timing`: `libp2pNewMs`, `pubsubInitMs`, `relayWarmMs`, `totalToDiscoverableMs`; `circuit_address:timing`: `elapsedMs`, `pollCount`; `TIME_TO_ONLINE_BADGE_WIDGET`: `widgetTransitionMs` |
| B-Sim-2: 5 cold starts | Percentile distribution across repeated startups | `TIME_TO_ONLINE_BADGE` × 5 |
| B-Sim-3: Hot restart | Resync latency after "already started" | `TIME_TO_ONLINE_BADGE`: `phase='hot_restart'` |

**Baseline table output:** `sim_time_to_online_badge_ms`, `sim_startup_host_ready_ms`, `sim_startup_pubsub_ms`, `sim_startup_relay_warm_ms`, `sim_startup_relays_attempted`, `sim_startup_total_discoverable_ms`, `sim_startup_circuit_address_ms`, `sim_time_to_online_widget_ms`, `sim_cold_start_ms` (p50/p95), `sim_hot_restart_ms`

**Budget assertion:** `totalToDiscoverableMs` < 5s, `TIME_TO_ONLINE_BADGE.totalMs` < 6s

### C-Sim: Relay Recovery

**File:** `integration_test/benchmark_relay_recovery_harness.dart`
**Scenarios:** 2
**Applies to:** BOTH
**Requires:** None (single-node, kills own relay)

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| C-Sim-1: Kill relay, recover | Detection latency, recovery latency, total outage, recovery mode | `RELAY_OUTAGE_TIMING`: `phase` (detected/recovered), `detectionMs`, `detectionSource`, `recoveryMs`, `totalOutageMs`, `recoveryMode`; `TIME_TO_ONLINE_BADGE`: `totalMs`, `phase='recovery'`; `TIME_TO_ONLINE_BADGE_WIDGET`: `widgetTransitionMs`; `timeout:fired`: `RecoveryWaitTimeout` |
| C-Sim-2: 3 recovery cycles | Recovery consistency across repeated outages | `RELAY_OUTAGE_TIMING` × 3 cycles |

**Baseline table output:** `sim_relay_detection_ms`, `sim_relay_recovery_ms`, `sim_recovery_time_to_online_ms`, `sim_recovery_widget_transition_ms`, `sim_relay_recovery_ms` (p50/p95)

### D-Sim: Inbox Round-Trip

**File:** `integration_test/benchmark_inbox_harness.dart`
**Scenarios:** 2
**Applies to:** BOTH

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| D-Sim-1: Inbox store | Per-step store timing (connect, stream open, write, read) | `CHAT_MSG_SEND_TIMING`: `elapsedMs`, `sendPath`, `outcome`; `inbox:store_timing` (Go push): `connectMs`, `streamOpenMs`, `writeMs`, `readMs`, `totalMs`, `outcome` |
| D-Sim-2: Inbox retrieve | Retrieve timing and message count | `inbox:retrieve_timing` (Go push): `totalMs`, `messageCount`, `outcome`; `INBOX_DELIVERY_TIMING`: `deliveryMs`, `messageId` |

**Baseline table output:** `sim_inbox_store_ms`, `sim_inbox_store_path`, `sim_inbox_store_outcome`, plus Go-side per-step rows when `inbox:store_timing` is actually emitted. On the 2026-04-15 rerun, the harness emitted only `sim_inbox_store_ms = 106ms`, `path = inbox`, `outcome = success`.

### E-Sim: Media Transfer

**File:** `integration_test/benchmark_media_harness.dart`
**Scenarios:** 2
**Applies to:** BOTH
**Requires:** Go CLI test peer (E-Sim-1 two-node path), none (single-node fallback)

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| E-Sim-1: Upload 1MB, 5MB | Stream open timing, upload completion, throughput, progress events | `media:stream_open_timing`: `connectMs`, `newStreamMs`, `totalMs`, `outcome`; `media:upload_complete`: `totalBytes`, `totalMs`, `throughputBytesPerSec`; `media:upload_progress` count |
| E-Sim-2: Profile upload | Profile-specific progress events and profile upload total time | `media:stream_open_timing`: `connectMs`, `newStreamMs`, `totalMs`, `outcome`; `profile:upload_progress`: `sentBytes`, `totalBytes`; `media:upload_progress` count (sanity check for non-profile path leakage) |

**Baseline table output:** `sim_media_1mb_upload_ms`, `sim_media_5mb_upload_ms`, `sim_media_1mb_stream_open_ms`, `sim_media_5mb_stream_open_ms`, `sim_media_*_throughput`, `sim_media_*_progress_events`, `sim_profile_upload_total_ms`, `sim_profile_stream_open_ms`, `sim_profile_progress_event_count`.

**Current rerun note:** the 2026-04-15 repaired rerun now produces the intended low-level rows. `E-Sim-1` emitted `1MB upload=351ms`, `throughput=2987396 bytes/sec`, `progress events=6`; `5MB upload=2677ms`, `throughput=1958490 bytes/sec`, `progress events=22`; both uploads reported `measurement_source = go_upload_complete`. `media:stream_open_timing` was present for both uploads and rounded to `0ms` on the warmed simulator relay. `E-Sim-2` emitted `sim_profile_upload_total_ms = 221ms`, `sim_profile_stream_open_ms = 0ms`, and `sim_profile_progress_event_count = 3` (`0 → 262144 bytes`), while the general `media:upload_progress` count remained `0` as expected for the profile-specific path.

### F-Sim: Bridge Crossing

**File:** `integration_test/benchmark_bridge_crossing_harness.dart`
**Scenarios:** 1
**Applies to:** BOTH

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| F-Sim-1: 1000 round-trips | Raw MethodChannel round-trip latency with live Go bridge | `BRIDGE_CALL_TIMING` (FLOW): `cmd`, `bridgeMs`, `outcome` × 1000; computes p50/p95/p99 from `bridgeMs` distribution |

**Baseline table output:** `sim_bridge_crossing_ms` (p50/p95/p99), `sim_bridge_total_ms`, `sim_bridge_outcomes`

**Budget assertion:** p99 < 50ms

### G-Sim: Encryption Overhead

**File:** `integration_test/benchmark_encryption_harness.dart`
**Scenarios:** 3
**Applies to:** BOTH (G-Sim-1/2 = 1:1 ML-KEM; G-Sim-3 = group AES-256-GCM)

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| G-Sim-1: ML-KEM keygen (10x) | Key generation latency distribution | `mlkem.keygen` bridge response × 10: Stopwatch per call |
| G-Sim-2: Encrypt/decrypt sizes | Encryption scaling with payload size (100B→100KB) | `message.encrypt` / `message.decrypt` responses: Stopwatch per call at 4 size buckets |
| G-Sim-3: Group crypto | Group-level AES-256-GCM encrypt + decrypt latency | `group.encrypt` / `group.decrypt` bridge responses |

**Baseline table output:** `sim_mlkem_keygen_ms` (p50/p95), `sim_encrypt_100b_ms` .. `sim_encrypt_100kb_ms`, `sim_decrypt_100b_ms` .. `sim_decrypt_100kb_ms`, `sim_group_encrypt_ms`, `sim_group_decrypt_ms`

### H-Sim: Timeout Accuracy

**File:** `integration_test/benchmark_timeout_accuracy_harness.dart`
**Scenarios:** 2
**Applies to:** BOTH

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| H-Sim-1: Dart-side timeouts | Relay probe timeout (5s), interactive send timeout (2s) — actual vs configured | Stopwatch per operation: deviation % |
| H-Sim-2: Go-side timeouts | Peer dial timeout, send timeout — from `timeout:fired` push events | `timeout:fired` (FLOW): `timeoutName`, `configuredMs`, `actualMs` |

**Baseline table output:** `sim_relay_probe_timeout_actual_ms`, `sim_foreground_wrapper_timeout_actual_ms`, `sim_dart_timeout_max_deviation_pct`, `sim_go_timeout_events_count`, `sim_go_ack_timeout_events_count`, `sim_go_timeout_max_deviation_pct`, plus per-timeout `actualMs` vs `configuredMs`

**Current rerun note:** the 2026-04-15 repaired rerun now exercises real timeouts via `run_timeout_accuracy_benchmark.dart`. The suite emitted `sim_relay_probe_timeout_actual_ms = 5007ms`, `sim_foreground_wrapper_timeout_actual_ms = 2003ms`, `sim_dart_timeout_max_deviation_pct = 0.1%`, `sim_go_timeout_events_count = 2`, `sim_go_ack_timeout_events_count = 2`, and `sim_go_timeout_max_deviation_pct = 0.1%`. `DirectConfirmTimeout` fired at `2002ms` for both receiver-side messages.

### I-Sim: Event Queue Wait

**File:** `integration_test/benchmark_event_queue_harness.dart`
**Scenarios:** 2
**Applies to:** BOTH

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| I-Sim-1: Idle delivery | Health check round-trip under idle conditions (no load) | `stateStream` delivery timing × 20; `queueWaitMs` field from events if present |
| I-Sim-2: Loaded delivery | Health check round-trip under concurrent bridge call load | `stateStream` delivery timing × 10 with concurrent `node:status` calls |

**Baseline table output:** `sim_event_queue_idle_ms` (p50/p95), `sim_event_queue_loaded_ms` (p50/p95), `sim_event_queue_wait_ms`

**Budget assertion:** p95 < 500ms (idle)

### J-Sim: Connection Reuse Hit Rate

**File:** `integration_test/benchmark_connection_reuse_harness.dart`
**Scenarios:** 1
**Applies to:** 1:1 only
**Requires:** Go CLI test peer

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| J-Sim-1: Scripted conversation | Reuse hit rate, cold vs warm latency split, connection persistence after 5s idle | `CHAT_MSG_SEND_TIMING` × 10: `connectionReused`, `sendPath`, `elapsedMs` |

**Baseline table output:** `sim_connection_reuse_hit_rate_pct`, `sim_reuse_cold_send_ms` (p50/p95), `sim_reuse_warm_send_ms` (p50/p95)

### K-Sim: Voice Send Sub-Steps

**File:** `integration_test/benchmark_voice_harness.dart`
**Scenarios:** 1
**Applies to:** BOTH

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| K-Sim-1: Voice note send | Upload vs transport split, upload share percentage | `VOICE_SEND_TIMING`: `elapsedMs`, `uploadMs`, `sendMs`, `outcome`, `durationMs`, `sizeBytes`; computed `upload_share_pct = uploadMs / elapsedMs × 100` |

**Baseline table output:** `sim_voice_total_ms`, `sim_voice_upload_ms`, `sim_voice_send_ms`, `sim_voice_upload_share_pct`

### L-Sim: Deferred Direct ACK

**File:** `integration_test/benchmark_ack_harness.dart`
**Scenarios:** 1
**Applies to:** 1:1 only
**Requires:** Go CLI test peer

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| L-Sim-1: Direct send with ACK | ACK round-trip latency, Go-side ACK timing breakdown | `CHAT_MSG_SEND_TIMING`: `elapsedMs`, `sendPath`, `outcome`, `ackRoundTripMs`; `message:direct_ack_timing` (Go push): `waitMs`/`ackMs`, `outcome`, `transport` |

**Baseline table output:** `sim_direct_ack_wait_ms` (p50/p95)

**Budget assertion:** p95 < 2000ms (DirectConfirmTimeout)

### M-Sim: Time-to-Online Badge

**File:** `integration_test/benchmark_time_to_online_harness.dart`
**Scenarios:** 4
**Applies to:** BOTH

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| M-Sim-1: Cold start | Wall-clock from app launch to green badge | `TIME_TO_ONLINE_BADGE`: `totalMs`, `phase='cold_start'`, `source`; `TIME_TO_ONLINE_BADGE_WIDGET`: `widgetTransitionMs` |
| M-Sim-2: Recovery | Wall-clock from degraded badge to green badge | `TIME_TO_ONLINE_BADGE`: `totalMs`, `phase='recovery'`; `RELAY_OUTAGE_TIMING` |
| M-Sim-Hot: Hot restart | Resync latency, whether badge re-fires | `TIME_TO_ONLINE_BADGE`: `phase='hot_restart'` |
| M-Sim-3: Source distribution | Which delivery path wins across 5 cold starts | `TIME_TO_ONLINE_BADGE.source` × 5: count of `start_response`, `relay_state_push`, `health_check_poll`, `addresses_push` |

**Baseline table output:** `sim_time_to_online_badge_ms`, `sim_time_to_online_widget_ms`, `sim_time_to_online_total_ms`, `sim_time_to_online_source`, `sim_recovery_to_online_badge_ms`, `sim_hot_restart_ms`, `sim_online_source_distribution`, `sim_time_to_online_ms` (p50/p95)

**Budget assertion:** `totalMs` < 6s (cold start)

### BR-Sim: Background Resume Badge

**File:** `integration_test/benchmark_background_resume_harness.dart`
**Scenarios:** 3
**Applies to:** BOTH

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| BR-Sim-1: Resume with healthy relay | Resume latency when relay stayed healthy while the app was backgrounded | `TIME_TO_ONLINE_BADGE`: `totalMs`, `phase='background_resume_already_online'`, `source` |
| BR-Sim-2: Resume with degraded relay | Resume-to-green latency when relay degraded in background and recovered on foreground | `TIME_TO_ONLINE_BADGE`: `totalMs`, `phase='background_resume'`, `source` |
| BR-Sim-3: Resume after extended background | Resume latency after a 30s background hold with relay still healthy | `TIME_TO_ONLINE_BADGE`: `totalMs`, `phase='background_resume_already_online'`, `source` |

**Baseline table output:** `sim_background_resume_healthy_ms`, `sim_background_resume_degraded_ms`, `sim_background_resume_extended_ms`, phase/source companion rows.

**Current rerun note:** `run_benchmark_suite.dart --scenarios BR` emitted `healthy=100ms`, `degraded=9166ms`, `extended=103ms`; sources were `resume_check` for healthy/extended and `health_check_poll` for degraded recovery.

### N-Sim: Notification Tap to Message

**File:** `integration_test/benchmark_notification_tap_harness.dart`
**Scenarios:** 2
**Applies to:** BOTH

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| N-Sim-1: Notification tap cold | Notification tap to first visible message on the cold path | `NOTIFICATION_TAP_TO_MESSAGE_TIMING`: `elapsedMs`, `routeKind`, `messageId` |
| N-Sim-2: Notification tap warm | Notification tap to first visible message when the app is already backgrounded | `NOTIFICATION_TAP_TO_MESSAGE_TIMING`: `elapsedMs`, `routeKind`, `messageId` |

**Baseline table output:** `sim_notification_tap_cold_ms`, `sim_notification_tap_warm_ms`, route-kind companion rows.

**Current rerun note:** `run_benchmark_suite.dart --scenarios N` emitted `cold=313ms`, `warm=85ms`, both with `routeKind=conversation`.

### GP-Sim: Group Publish

**File:** `integration_test/benchmark_group_publish_harness.dart`
**Scenarios:** 2
**Applies to:** GRP
**Requires:** Go CLI test peer (GP-Sim-1), none (GP-Sim-2)

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| GP-Sim-1: Publish with peers | GossipSub publish latency when mesh peers are connected | `GROUP_SEND_MSG_TIMING`: `elapsedMs`, `outcome`, `prepareMs`, `publishMs`, `inboxMs`; `group:publish_debug` (Go push): `encryptMs`, `signMs`, `topicPeers`; `group_message:received` at receiver: `decryptMs` |
| GP-Sim-2: Publish 0 peers | Latency when no group peers are online (publish fast-path plus sender-side fallback attempt) | `GROUP_SEND_MSG_TIMING`: `elapsedMs`, `outcome`; `group:publish_debug`: `topicPeers=0` |

**Baseline table output:** `sim_group_publish_peers_ready_ms` (p50/p95), `sim_group_publish_zero_peers_ms`, `sim_group_publish_zero_peers_outcome`, `sim_group_publish_peers_ready_receiver_count`, `sim_group_publish_peers_ready_e2e_ms`, `sim_group_publish_receiver_decrypt_ms`.

**Current rerun note:** the script-driven rerun now emits real rows via `run_group_publish_benchmark.dart`: sender-side `sim_group_publish_peers_ready_ms p50=5ms p95=8ms (n=5)`, `topic_peers=1`, zero-peers `58ms` with `success_no_peers`, plus receiver-side `receiver_count=5`, `e2e p50=44ms p95=48ms (n=5)`, `decrypt p50=0ms p95=0ms`. The zero-peer path still logged `GROUP_SEND_MSG_INBOX_STORE_FAILED` at the sender during this rerun, so the `success_no_peers` row should be read as publish-path latency, not proven relay-inbox storage success.

### R-Sim: Routing Path Matrix

**File:** `integration_test/benchmark_routing_paths_harness.dart`
**Scenarios:** 8
**Applies to:** 1:1
**Requires:** Go CLI test peer (R-Sim-1, -2, -3, -7, -8), none (R-Sim-4, -5, -6)

| Scenario | What It Measures | Events / Fields Collected |
|----------|-----------------|--------------------------|
| R-Sim-1: Connection reuse (warm) | 1 cold + 5 warm sends, reuse hit rate, latency split | `CHAT_MSG_SEND_TIMING` × 6: `elapsedMs`, `sendPath`, `connectionReused`, `outcome` |
| R-Sim-2: Direct P2P (cold) | First-contact cold send with per-step breakdown | `CHAT_MSG_SEND_TIMING`: `discoverMs`, `dialMs`, `sendMs` |
| R-Sim-3: Relay probe (unregistered) | Send to peer not on rendezvous but reachable via relay circuit | `CHAT_MSG_SEND_TIMING`: `sendPath`, `elapsedMs`; requires orchestrator `unregister` signal |
| R-Sim-4: Inbox fallback (offline) | Send to nonexistent peer — all paths fail, inbox fallback | `CHAT_MSG_SEND_TIMING`: `sendPath='inbox'`, `outcome` |
| R-Sim-5: Budget starvation | Send to unreachable peer, discover consumes full 2s budget | `CHAT_MSG_SEND_TIMING`: `elapsedMs`, `discoverMs`, `dialMs`; wall-clock stopwatch |
| R-Sim-6: Worst-case cascade | All paths fail including inbox — total failure timing | `CHAT_MSG_SEND_TIMING`: `outcome='failed'`; wall-clock stopwatch |
| R-Sim-7: Realistic workload | 11-message conversation: cold → 5 warm → offline/inbox → reconnect → 3 warm | `CHAT_MSG_SEND_TIMING` × 11: path distribution, cold/warm/reconnect/inbox split; routing timeline |
| R-Sim-8: Before/after comparison | Runs R-Sim-7 workload, saves baseline JSON, computes deltas on subsequent runs | `sim_routing_current_cold_ms`, `sim_routing_current_warm_p50_ms`, `sim_routing_before_after_delta_*` |

**Baseline table output:** `sim_routing_reuse_ms` (p50/p95), `sim_routing_direct_cold_ms`, `sim_routing_relay_probe_ms`, `sim_routing_inbox_fallback_ms`, `sim_routing_budget_starvation_ms`, `sim_routing_worst_case_ms`, `sim_routing_distribution`, `sim_routing_cold_ms`, `sim_routing_warm_ms` (p50/p95), `sim_routing_reconnect_ms`, `sim_routing_offline_inbox_ms`

---

## Phase 5: Two-Simulator Interactive Smoke Tests (E2E Delivery Verification)

Phase 5 tests run **two identical Flutter apps on two iOS simulators** (Alice = sender on iPhone 17 Pro, Bob = receiver on iPhone 17), coordinated via shared signal files. Both sides have the full stack: `GoBridgeClient` → `P2PServiceImpl` → `ChatMessageListener` → `MessageRepositoryImpl` → encrypted DB. Both sides emit `CHAT_MSG_SEND_TIMING` and both sides record e2e delivery latency.

This replaces the earlier CLI-peer-based design. The key advantage: the receiver runs the real Dart listener/DB stack (not a Go CLI process), so e2e timing measures `send → MethodChannel → Go → relay → Go → MethodChannel → ChatMessageListener → DB write`.

### S1–S15 + X1–X3 + N1–N2 + BR-S1–S3: 1:1 + Cross-Cutting + G1–G8: Group (Two Simulators)

**1:1 harnesses:** `routing_smoke_alice_harness.dart` + `routing_smoke_bob_harness.dart`
**Group harnesses:** `group_smoke_alice_harness.dart` + `group_smoke_bob_harness.dart`
**Notification/background-resume two-simulator harnesses:** still not present in the repo on the 2026-04-15 rerun. `03j` still references `notification_smoke_alice_harness.dart` + `notification_smoke_bob_harness.dart`, but those files do not exist locally. Equivalent single-node timing coverage now exists in `benchmark_notification_tap_harness.dart` (`N-Sim`) and `benchmark_background_resume_harness.dart` (`BR-Sim`).
**Orchestrator:** `integration_test/scripts/run_routing_smoke_e2e.dart` (Phase 1 + Phase 2)
**Implemented scenarios rerun:** 26 (18 × 1:1/cross-cutting + 8 × Group) — **26/26 PASS** on 2026-04-15
**Still planned only at the two-simulator smoke layer:** 5 doc-only placeholder scenarios (`N1`, `N2`, `BR-S1`, `BR-S2`, `BR-S3`). Their timing metrics are now covered by the single-node `N-Sim` / `BR-Sim` harnesses above.
**Applies to:** BOTH (1:1 and Group)

```bash
dart run integration_test/scripts/run_routing_smoke_e2e.dart \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

**1:1 Scenarios (S1–S15):**

| Scenario | What it tests (03.md ref) | Key Metrics |
|----------|--------------------------|-------------|
| S1: Cold send | Path A (first contact) | send=227ms, path=direct, e2e=806ms |
| S2: Warm send x5 | Path A (reuse) | 5/5 delivered |
| S3: Offline → inbox | Path A + E | send=2058ms, path=inbox; Bob captures `INBOX_DELIVERY_TIMING` during drain |
| S4: Reconnect | Path A (recovery) | send=105ms, path=direct, e2e=3561ms |
| S5: Bidirectional | Path A (both dirs) | 3 recv + 2 sent |
| S6: Stale connection | Path A (stale reuse) | send=108ms, path=direct, e2e=254ms |
| S7: All-paths-fail | Path A (total failure) | outcome=success (inbox fallback) |
| S8: Full lifecycle | Path A (10-msg sweep) | Alice timeline=10, Bob timeline=10 |
| S9: Batch inbox x5 | Path E (multi-msg drain) | 5/5 stored to inbox; Bob captures `INBOX_DELIVERY_TIMING` × 5 during batch drain |
| S10: Delete-for-everyone | Path J (tombstone send) | `deleteMessageForEveryone()` 192ms, outcome=success |
| S11: Voice message | Path I (upload + send) | `sendVoiceMessage()` with AudioRecording captured |
| S12: Media 1MB + 5MB transfer | Path F (relay throughput) | 1MB=490ms (**2090 KB/s**), 5MB=2495ms (**2052 KB/s**) |
| S13: ACK under load | Path H (DirectConfirmTimeout) | 10 rapid sends, Bob received **10/10** |
| S14: Local WiFi | Path K (mDNS send) | isLocal=false (simulators), send=11ms via reuse |
| S15: Relay probe | Path A (relay-probe eligible) | rerun resolved on direct path: send=572ms, `probe=false`, e2e=254ms |

**Cross-Cutting Scenarios (X1–X3):**

| Scenario | What it tests (03.md ref) | Key Metrics |
|----------|--------------------------|-------------|
| X1: Both-sides restart | Path B (node restart) | restart=513ms/515ms, post-restart send=142ms, e2e=3310ms |
| X2: Background/foreground | §3 (lifecycle timing) | resume=110ms/124ms, post-resume **e2e=256ms** |
| X3: Relay failover | Path C (health check) | healthCheck=53ms, send=18ms, e2e=255ms |

**Notification Tap Scenarios (N1–N2):**

| Scenario | What it tests (03.md ref) | Key Metrics |
|----------|--------------------------|-------------|
| N1: Notification tap cold (app killed) | Notification tap → message visible (cold start) | No two-sim Alice/Bob harness in repo; single-node `N-Sim-1` rerun = **313ms** |
| N2: Notification tap warm (app backgrounded) | Notification tap → message visible (warm resume) | No two-sim Alice/Bob harness in repo; single-node `N-Sim-2` rerun = **85ms** |

**Background Resume Scenarios (BR-S1–BR-S3):**

| Scenario | What it tests (03.md ref) | Key Metrics |
|----------|--------------------------|-------------|
| BR-S1: Resume with healthy relay | Path B Phase 4 (background_resume_already_online) | No two-sim Alice/Bob harness in repo; single-node `BR-Sim-1` rerun = **100ms** |
| BR-S2: Resume with degraded relay | Path B Phase 4 + Path C (background_resume + recovery) | No two-sim Alice/Bob harness in repo; single-node `BR-Sim-2` rerun = **9166ms** |
| BR-S3: Resume after extended background (30s) | Path B Phase 4 (Go node warmth) | No two-sim Alice/Bob harness in repo; single-node `BR-Sim-3` rerun = **103ms** |

**Group Scenarios (G1–G8):**

| Scenario | What it tests (03.md ref) | Key Metrics |
|----------|--------------------------|-------------|
| G1: Group publish → receive | §1 GossipSub latency | send=32ms, **e2e=515ms** |
| G2: Group warm x5 | Path D (warm publish) | 5/5 delivered via GossipSub |
| G3: Group bidirectional | Path D (both dirs) | 2 recv + 1 sent |
| G4: Group offline → inbox | Path D + E (group inbox) | publish OK, Bob **e2e=0ms** |
| G5: Group lifecycle | Path D (9-msg sweep) | 9/9 both timelines |
| G6: Peer discovery timing | Path D (join→connected) | **5255ms** (includes 5s settle; ~255ms actual discovery) |
| G7: Key rotation under traffic | §3 key rotation | **rotation=1209ms**, preRx=false, postRx=false |
| G8: Multi-member publish | Path D (flood publish) | send=1239ms, outcome=`successNoPeers`, e2e=pending |

**Signal protocol (shared temp dir, prefixed `smoke_${runId}_`):**

```
ORCHESTRATOR                    ALICE (iPhone 17 Pro)           BOB (iPhone 17)
     │                               │                              │
     │  (both launched simultaneously)│                              │
     │                               │── alice_identity.json ──────>│
     │                               │<────── bob_identity.json ────│
     │<───────── alice_ready         │                              │
     │<──────────────────────────────────────────── bob_ready       │
     │                               │                              │
     │── s1_go ─────────────────────>│                              │
     │              Alice sends msg → s1_alice_sent (timing JSON)   │
     │                               │         Bob detects in DB → s1_bob_received (e2e JSON)
     │── s1_verified ───────────────>│                              │
     │                               │                              │
     │  (S2–S4: same go/sent/received/verified pattern)             │
     │                               │                              │
     │── s3_bob_stop ───────────────────────────────────────────────>│
     │                               │         Bob stops → s3_bob_stopped
     │── s3_bob_restart ────────────────────────────────────────────>│
     │                               │         Bob restarts + drains → s3_bob_received
     │                               │                              │
     │── s6_bob_kill ───────────────────────────────────────────────>│
     │                               │         Bob kills → s6_bob_killed
     │── s6_bob_restart ────────────────────────────────────────────>│
     │                               │         Bob restarts → s6_bob_restarted
     │                               │                              │
     │── s8_bob_stop / s8_bob_restart (lifecycle sub-phases) ──────>│
     │                               │                              │
     │── all_done ──────────────────>│                              │
     │── all_done ──────────────────────────────────────────────────>│
     │<───────── alice_done          │                              │
     │<──────────────────────────────────────────── bob_done        │
```

**What this catches that other tests don't:**

| Issue | Unit (R1–R17) | Sim (R-Sim) | Two-Sim Smoke (S1–S8) |
|-------|---------------|-------------|----------------------|
| Event fields correct | Yes | Yes | Yes |
| Timing values realistic | No (fakes) | Yes (one side) | **Yes (both sides)** |
| Message actually delivered | No | Partially | **Yes (receiver DB write)** |
| Receiver Dart stack works | No | No | **Yes (ChatMessageListener → DB)** |
| End-to-end latency (send → DB write) | No | No | **Yes (zero clock skew)** |
| Bidirectional routing | No | No | **Yes (S5, S8)** |
| Real inbox drain path | No | No | **Yes (warmBackground → drainOfflineInbox)** |
| Symmetric code paths | No | No | **Yes (identical Flutter stacks)** |

---

## Production Instrumentation Added

Production code changes that add observability (no behavior change):

### POST_SEND_DELIVERY_TIMING

**File:** `lib/features/posts/application/post_delivery_runner.dart`
**Applies to:** Post delivery (per-recipient fanout)

Emits `POST_SEND_DELIVERY_TIMING` after the recipient fanout loop completes:

| Field | Type | Description |
|-------|------|-------------|
| `elapsedMs` | int | Wall-clock time for the entire fanout (all recipients) |
| `outcome` | string | `success`, `partialSuccess`, `sendFailed`, or `error` |
| `recipientCount` | int | Number of recipients attempted |
| `deliveryStatus` | string | Aggregate status: `sent`, `partial`, `failed`, `sending` |

### messageId in CHAT_MSG_SEND_TIMING

**File:** `lib/features/conversation/application/send_chat_message_use_case.dart`
**Applies to:** 1:1

Added `messageId` (first 8 chars) to the `CHAT_MSG_SEND_TIMING` success-path event. The receiver already logs the same `messageId` in `CHAT_MSG_RECEIVE_STORED`, enabling sender-to-receiver latency correlation without a wire format change.

### Hazard Fixes Implemented (03b §4)

All 5 hazard fixes from `03b-timing-improvement-plan.md` Section 4 are implemented:

| Fix | File | Implementation |
|-----|------|----------------|
| `callP2PInboxStore` Dart timeout | `p2p_bridge_client.dart:406` | `.timeout(Duration(milliseconds: timeoutMs ?? 15000))` — interactive send path passes `3000` via `interactiveInboxBudget` |
| `callP2PRelayProbe` Dart timeout | `p2p_bridge_client.dart:165` | `.timeout(const Duration(seconds: 5))` |
| Profile upload progress events | `go-mknoon/node/media.go:447` | `mediaUploadProgressReader` wrapper, emits `profile:upload_progress` |
| Recovery promise timeout | `go-mknoon/node/relay_session.go:62` | `RecoveryWaitTimeout = 30s`, `ClearStalledRecovery()` clears gate |
| Media idle timeout | `go-mknoon/node/media.go` | `idleTimeoutReader` + `ErrStallTimeout`, tests in `media_test.go` |

### Additional Instrumentation Implemented (03b §3)

| Instrumentation | File | Implementation |
|-----------------|------|----------------|
| Local WiFi `_TIMING` summary | `local_media_sender.dart:45` | `LOCAL_MEDIA_SEND_TIMING` with Stopwatch `elapsedMs`, `outcome`, `mediaId` |
| Group send per-step breakdown | `send_group_message_use_case.dart:208-225` | `GROUP_SEND_MSG_TIMING` includes `prepareMs`, `publishMs` sub-fields |

### Notification Tap to Message Timing (03j §1)

**File:** `lib/core/utils/notification_tap_timing.dart` (new helper)
**Applies to:** BOTH (1:1 conversation + group)

Emits `NOTIFICATION_TAP_TO_MESSAGE_TIMING` when a notification tap reaches the conversation screen:

| Field | Type | Description |
|-------|------|-------------|
| `elapsedMs` | int | Wall-clock time from notification tap to conversation screen first message render |
| `routeKind` | string | `conversation` (1:1) or `group` (GossipSub) |
| `messageId` | string | Target message ID, truncated to 8 chars for privacy |

**Production code touched:**
- `lib/main.dart` — stores `_notificationTappedAt = DateTime.now()` in `_onNotificationTap()` and `_routeRemoteNotificationOpen()`, passes through to conversation/group screens
- `lib/features/conversation/presentation/screens/conversation_wired.dart` — accepts optional `notificationTappedAt`, emits timing after `_initialLoadDone` via `addPostFrameCallback`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — same pattern for group conversation

### Background Resume Badge Timing (03j §2)

**Files:** `lib/core/services/p2p_service_impl.dart`, `lib/main.dart`
**Applies to:** BOTH

Adds `phase='background_resume'` and `phase='background_resume_already_online'` to the existing `TIME_TO_ONLINE_BADGE` event:

| Phase | Condition | Description |
|-------|-----------|-------------|
| `background_resume` | Relay degraded during background, then recovered on resume | Measures user-perceived time from app foregrounding to green badge |
| `background_resume_already_online` | Relay stayed healthy during background | Badge was already green; `totalMs ≈ 0` |

**Production code touched:**
- `lib/core/services/p2p_service_impl.dart` — `markResumeStarted()` records timestamp, `checkResumeAlreadyOnline()` emits immediately if already online, `clearResumeStarted()` cleans up in finally, `_emitState()` recovery block emits `background_resume` when `_resumeStartedAt` is set
- `lib/main.dart` — `_onResumed()` calls `markResumeStarted()` before `handleAppResumed()`, `checkResumeAlreadyOnline()` after, `clearResumeStarted()` in finally

---

## Orchestrator Script

**File:** `integration_test/scripts/run_benchmark_suite.dart`

Automates running all 17 implemented simulator benchmark scenario groups: single-node `B,BR,C,F,G,I,K,M,N`, two-node `A,D,E,J,L,R`, and script-driven `GP,H`.

```bash
# Run all scenarios on primary device
dart run integration_test/scripts/run_benchmark_suite.dart \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469

# Run specific scenarios
dart run integration_test/scripts/run_benchmark_suite.dart \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 \
  --scenarios B,F,G,M

# Run with fixture directory for two-node tests
dart run integration_test/scripts/run_benchmark_suite.dart \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 \
  --fixture-dir /tmp/benchmark_fixtures
```

**Orchestrator responsibilities:**
1. Runs single-node harnesses `B,BR,C,F,G,I,K,M,N` directly via `flutter test`
2. For two-node harnesses `A,D,E,J,L,R`: builds Go CLI testpeer, starts it, exchanges identities via fixture file, then runs each harness with `--dart-define=CLI_PEER_FIXTURE=...`
3. For script-driven scenarios `GP` and `H`: runs `run_group_publish_benchmark.dart` and `run_timeout_accuracy_benchmark.dart`, which launch `flutter test` plus the required CLI orchestration and now relay child `[BENCHMARK]` lines back to suite stdout
4. Collects all `[BENCHMARK]` lines from stdout
5. Prints final baseline table

**Current limitations observed during the 2026-04-15 rerun:**
- `media:stream_open_timing` rounded to `0ms` on the warmed simulator relay during the latest `E-Sim` rerun, so upload duration and progress counts are more informative than stream-open timing in this particular environment.

---

## Baseline Table Mapping

| Baseline Metric | Phase 4 Source | Applies To |
|----------------|----------------|------------|
| 1:1 Send (cold) p50, p95 | A-Sim-1 | 1:1 |
| 1:1 Send (warm) p50, p95 | A-Sim-2 | 1:1 |
| Node Startup (Go) p50, p95 | B-Sim-1, B-Sim-2 | BOTH |
| Time-to-Online Badge p50, p95 | M-Sim-1, M-Sim-3 | BOTH |
| Background Resume (healthy) | BR-Sim-1 | BOTH |
| Background Resume (degraded) | BR-Sim-2 | BOTH |
| Background Resume (extended) | BR-Sim-3 | BOTH |
| Relay Recovery p50, p95 | C-Sim-1, C-Sim-2 | BOTH |
| Relay Outage (total) p50, p95 | C-Sim-1 | BOTH |
| Inbox Store (warm) p50, p95 | D-Sim-1 | BOTH |
| Inbox E2E Delivery p50, p95 | D-Sim-2 | BOTH |
| Event Queue Wait p50, p95 | I-Sim-1 | BOTH |
| Media 5MB Upload p50, p95 | E-Sim-1 | BOTH |
| Media Stream Open p50, p95 | E-Sim-1 | BOTH |
| Media Throughput (bytes/s) p50, p95 | E-Sim-1 | BOTH |
| Profile Upload Total | E-Sim-2 | BOTH |
| Profile Upload Progress Events | E-Sim-2 | BOTH |
| Voice Upload Phase p50, p95 | K-Sim-1 | BOTH |
| Voice Transport Phase p50, p95 | K-Sim-1 | BOTH |
| Direct ACK Round-Trip p50, p95 | L-Sim-1 | 1:1 |
| Notification Tap (cold) | N-Sim-1 | BOTH |
| Notification Tap (warm) | N-Sim-2 | BOTH |
| Bridge: MethodChannel RT p50, p95 | F-Sim-1 | BOTH |
| Crypto: ML-KEM keygen p50, p95 | G-Sim-1 | 1:1 |
| Crypto: ML-KEM encrypt p50, p95 | G-Sim-2 | 1:1 |
| Crypto: Group encrypt p50, p95 | G-Sim-3 | GRP |
| Connection Reuse Hit Rate % | J-Sim-1 | 1:1 |
| Group Publish (peers ready) p50, p95 | GP-Sim-1 | GRP |
| Group Publish (0 peers) p50, p95 | GP-Sim-2 | GRP |
| Timeout Accuracy (max delta %) | H-Sim-1, H-Sim-2 | BOTH |
| **Routing Path Timing** | | |
| Routing: Reuse (warm) p50, p95 | R-Sim-1 | 1:1 |
| Routing: Direct (cold) p50 | R-Sim-2 | 1:1 |
| Routing: Relay Probe p50 | R-Sim-3 | 1:1 |
| Routing: Inbox Fallback p50 | R-Sim-4 | 1:1 |
| Routing: Budget Starvation p50 | R-Sim-5 | 1:1 |
| Routing: Worst-Case p50 | R-Sim-6 | 1:1 |
| Routing: Path Distribution | R-Sim-7 | 1:1 |
| Routing: Before/After Delta | R-Sim-8 | 1:1 |
| **Two-Simulator Smoke — 1:1 (E2E — Both Sides Timed)** | | |
| E2E: Cold send (send + e2e) | S1 | 1:1 |
| E2E: Warm send x5 | S2 | 1:1 |
| E2E: Inbox store → drain → delivery | S3 | 1:1 |
| E2E: Reconnect send | S4 | 1:1 |
| E2E: Bidirectional | S5 | 1:1 |
| E2E: Stale connection recovery | S6 | 1:1 |
| E2E: All-paths-fail | S7 | 1:1 |
| E2E: Full lifecycle (10 msgs) | S8 | 1:1 |
| E2E: Batch inbox drain (5 msgs) | S9 | 1:1 |
| E2E: Delete-for-everyone (tombstone) | S10 | 1:1 |
| E2E: Voice message (upload + send) | S11 | 1:1 |
| E2E: Media 1MB transfer (throughput) | S12 | 1:1 |
| E2E: ACK under load (10 rapid) | S13 | 1:1 |
| E2E: Local WiFi (mDNS) | S14 | 1:1 |
| E2E: Relay probe path | S15 | 1:1 |
| **Two-Simulator Smoke — Cross-Cutting** | | |
| Both-sides restart timing | X1 | BOTH |
| Background/foreground cycle | X2 | BOTH |
| Relay failover (health check) | X3 | BOTH |
| **Two-Simulator Smoke — Notification Tap** | | |
| Notification tap → message (cold) | N1 two-sim placeholder; current timing via N-Sim-1 | BOTH |
| Notification tap → message (warm) | N2 two-sim placeholder; current timing via N-Sim-2 | BOTH |
| **Two-Simulator Smoke — Background Resume** | | |
| Background resume → online badge (healthy relay) | BR-S1 two-sim placeholder; current timing via BR-Sim-1 | BOTH |
| Background resume → online badge (degraded relay) | BR-S2 two-sim placeholder; current timing via BR-Sim-2 | BOTH |
| Background resume → online badge (extended 30s) | BR-S3 two-sim placeholder; current timing via BR-Sim-3 | BOTH |
| **Two-Simulator Smoke — Group (GossipSub E2E)** | | |
| Group: Publish → receive | G1 | GRP |
| Group: Warm publish x5 | G2 | GRP |
| Group: Bidirectional | G3 | GRP |
| Group: Offline → inbox → drain | G4 | GRP |
| Group: Full lifecycle (9 msgs) | G5 | GRP |
| Group: Peer discovery timing | G6 | GRP |
| Group: Key rotation under traffic | G7 | GRP |
| Group: Multi-member publish | G8 | GRP |

---

## Simulator Baseline Table

Collected via the benchmark orchestrator (`run_benchmark_suite.dart`) on 2026-04-15.

Primary device: **iPhone 17 Pro** (iOS 26.1, UDID `38FECA55`).
Secondary device used for the two-simulator smoke rerun: **iPhone 17** (iOS 26.1, UDID `5BA69F1C`).

```
=====================================================
  mknoon Transport Timing — Simulator Baseline
  Date: 2026-04-15
=====================================================
  Time-to-Online Badge        p50=171ms p95=178ms  [17 Pro, n=5]
  Cold-start Harness          p50=169ms p95=170ms  [17 Pro, n=5]
  Relay Recovery              p50=9136ms p95=9320ms [17 Pro, n=3]
  Relay Detection             504ms                [17 Pro]
  Relay Outage (total)        ~9663ms              [17 Pro]
  Inbox Store (warm)          106ms                [17 Pro, targeted D-Sim rerun]
  Event Queue Wait (idle)     p50=49ms  p95=58ms   [17 Pro, n=20]
  Event Queue Wait (loaded)   p50=51ms  p95=125ms  [17 Pro, n=10]
  Bridge: MethodChannel RT    p50=0ms p95=0ms p99=0ms [17 Pro, n=1000]
  Crypto: ML-KEM keygen       p50=0ms  p95=3ms     [17 Pro, n=10]
  Crypto: ML-KEM encrypt 100B 1ms                  [17 Pro]
  Crypto: ML-KEM encrypt 1KB  0ms                  [17 Pro]
  Crypto: ML-KEM encrypt 10KB 0ms                  [17 Pro]
  Crypto: ML-KEM encrypt 100KB 2ms                 [17 Pro]
  Crypto: ML-KEM decrypt 100KB 3ms                 [17 Pro]
  Crypto: Group encrypt       0ms                  [17 Pro]
  Crypto: Group decrypt       0ms                  [17 Pro]
  Voice Upload Phase          151ms                [17 Pro]
  Voice Transport Phase       117ms                [17 Pro]
  Voice Upload Share          56%                  [17 Pro]
  Voice Total                 269ms                [17 Pro]
  Source Distribution         relay_state_push=5/5 [17 Pro]
  Recovery Time-to-Online     9600ms               [17 Pro]
  Background Resume (healthy) 100ms                [17 Pro, BR-Sim-1]
  Background Resume (degraded) 9166ms              [17 Pro, BR-Sim-2]
  Background Resume (extended) 103ms               [17 Pro, BR-Sim-3]
  1:1 Send (cold)             p50=95ms             [17 Pro, targeted A-Sim rerun]
  1:1 Send (warm)             p50=1ms  p95=2ms     [17 Pro, n=4]
  1:1 Sequential warm (10)    p50=1ms  p95=4ms     [17 Pro, n=10]
  1:1 Inbox fallback          91ms                 [17 Pro, targeted A-Sim rerun]
  1:1 Send path distribution  direct=1 reuse=4     [17 Pro]
  Direct ACK Round-Trip       p50=1ms  p95=41ms    [17 Pro, n=10]
  Notification Tap (cold)     313ms                [17 Pro, N-Sim-1]
  Notification Tap (warm)     85ms                 [17 Pro, N-Sim-2]
  Connection Reuse Hit Rate   90%                  [17 Pro, n=10]
  Connection Reuse cold       p50=67ms             [17 Pro, n=1]
  Connection Reuse warm       p50=1ms  p95=1ms     [17 Pro, n=9]
  GP-Sim Publish (ready)      p50=5ms  p95=8ms     [17 Pro, n=5]
  GP-Sim Receiver E2E         p50=44ms p95=48ms    [17 Pro, n=5]
  GP-Sim Publish (0 peers)    58ms successNoPeers  [17 Pro]
  Media 1MB Upload            351ms (2987396 bytes/sec) [17 Pro, E-Sim]
  Media 5MB Upload            2677ms (1958490 bytes/sec) [17 Pro, E-Sim]
  Media Stream Open           0ms (warm relay)     [17 Pro, E-Sim]
  Media Progress Events       1MB=6, 5MB=22        [17 Pro, E-Sim]
  Profile Upload Total        221ms                [17 Pro, E-Sim-2]
  Profile Stream Open         0ms (warm relay)     [17 Pro, E-Sim-2]
  Profile Progress Events     3                    [17 Pro, E-Sim-2]
  Group Publish (peers ready) send=32ms e2e=515ms  [17 Pro + 17, G1]
  Group Publish warm x5       5/5 delivered         [17 Pro + 17, G2]
  Group Bidirectional         2 recv + 1 sent       [17 Pro + 17, G3]
  Group Offline→inbox→drain   publish OK, e2e=0ms   [17 Pro + 17, G4]
  Group Discovery             5255ms (~255ms actual) [17 Pro + 17, G6]
  Group Key Rotation          1209ms               [17 Pro + 17, G7]
  Group Multi-member Publish  1239ms successNoPeers [17 Pro + 17, G8]
  S12 Media 1MB Transfer      490ms (2090 KB/s)    [17 Pro + 17, S12]
  S12 Media 5MB Transfer      2495ms (2052 KB/s)   [17 Pro + 17, S12]
  Timeout Accuracy (Dart)     relay=5007ms send=2003ms maxΔ=0.1% [17 Pro]
  Timeout Accuracy (Go)       timeout:fired=2 ackTimeouts=2 maxΔ=0.1% [17 Pro]
-----------------------------------------------------
  ROUTING PATH TIMING (1:1 Send)
-----------------------------------------------------
  Routing: Reuse (warm)       p50=1ms  p95=4ms     [17 Pro, n=5]
  Routing: Direct (cold)      85ms (disc=62 dial=19 send=1) [17 Pro]
  Routing: Relay Probe        S15 rerun stayed direct: 572ms, probe=false [17 Pro + 17]
  Routing: Inbox Fallback     111ms                [17 Pro]
  Routing: Budget Starvation  101ms                [17 Pro]
  Routing: Worst-Case         93ms                 [17 Pro]
  Routing: Path Distribution  direct=1 reuse=5     [17 Pro]
-----------------------------------------------------
  TWO-SIMULATOR SMOKE (E2E — Both Sides Timed)
  Run: 2026-04-15  Alice=iPhone 17 Pro  Bob=iPhone 17
  Result: 26/26 PASS (18 × 1:1/cross-cutting + 8 × Group)
-----------------------------------------------------
  PHASE 1: 1:1 SCENARIOS (S1–S15 + X1–X3)
  S1:  Cold send              send=227ms path=direct e2e=806ms   PASS
  S2:  Warm send x5           5/5 delivered                      PASS
  S3:  Offline → inbox        send=2058ms path=inbox             PASS
  S4:  Reconnect              send=105ms path=direct e2e=3561ms  PASS
  S5:  Bidirectional          3 recv + 2 sent                    PASS
  S6:  Stale recovery         send=108ms path=direct e2e=254ms   PASS
  S7:  All-paths-fail         outcome=success (inbox)            PASS
  S8:  Full lifecycle         Alice timeline=10 Bob timeline=10  PASS
  S9:  Batch inbox x5         5/5 stored to inbox                PASS
  S10: Delete-for-everyone    192ms outcome=success              PASS
  S11: Voice message          sendVoiceMessage() captured        PASS
  S12: Media 1MB+5MB          1MB=490ms 2090KB/s, 5MB=2495ms 2052KB/s PASS
  S13: ACK under load         10/10 received                     PASS
  S14: Local WiFi             isLocal=false, send=11ms reuse     PASS
  S15: Relay probe            send=572ms path=direct probe=false PASS
  X1:  Both-sides restart     513ms/515ms, send=142ms e2e=3310ms PASS
  X2:  Background/foreground  resume=110ms/124ms, e2e=256ms      PASS
  X3:  Relay failover         healthCheck=53ms send=18ms e2e=255ms PASS

  PHASE 2: GROUP SCENARIOS (G1–G8)
  G1:  Group publish→receive  send=32ms e2e=515ms                PASS
  G2:  Group warm x5          5/5 delivered via GossipSub        PASS
  G3:  Group bidirectional    2 recv + 1 sent                    PASS
  G4:  Group offline→inbox    publish OK, Bob e2e=0ms            PASS
  G5:  Group lifecycle        9/9 msgs, both timelines           PASS
  G6:  Peer discovery         5255ms (5s settle + ~255ms actual) PASS
  G7:  Key rotation           1209ms preRx=false postRx=false    PASS
  G8:  Multi-member publish   send=1239ms successNoPeers         PASS
=====================================================
```

### Device Variation Check

The 2026-04-15 fact-check reran the single-device benchmark suite on the iPhone 17 Pro only. The secondary iPhone 17 participated in the two-simulator smoke run, but those end-to-end numbers are not directly comparable to the single-device benchmark rows, so the previous cross-device ratio table has been removed instead of carrying forward stale values.

### Previously Missing or Misleading Rows — Now Collected

These were the rows that were previously missing, mislabeled as placeholders, or not being surfaced by the suite. They were rerun on 2026-04-15 via
`dart run integration_test/scripts/run_benchmark_suite.dart -d 38FECA55 --scenarios N,BR,H,GP`
plus the earlier `A,J,L,R` suite rerun, the targeted `E` suite rerun, and spot reruns for `A` and `D`:

| Row | Value | Status |
|-----|-------|--------|
| 1:1 Send (cold) | p50=95ms | **Done** |
| 1:1 Send (warm) | p50=1ms p95=2ms | **Done** |
| Connection Reuse Hit Rate | 90% (9/10) | **Done** |
| Direct ACK Round-Trip | p50=1ms p95=41ms | **Done** |
| Routing: Reuse (warm) | p50=1ms p95=4ms | **Done** |
| Routing: Direct (cold) | 85ms (disc=62 dial=19 send=1) | **Done** |
| Routing: Inbox Fallback | 111ms | **Done** |
| Routing: Budget Starvation | 101ms | **Done** |
| Routing: Worst-Case | 93ms | **Done** |
| Routing: Path Distribution | direct=1 reuse=5 | **Done** |
| Inbox Store (warm) | 106ms | **Done** |
| Notification Tap (cold) | 313ms | **Done** |
| Notification Tap (warm) | 85ms | **Done** |
| Background Resume (healthy) | 100ms | **Done** |
| Background Resume (degraded) | 9166ms | **Done** |
| Background Resume (extended) | 103ms | **Done** |
| Timeout Accuracy (Dart) | relay=5007ms send=2003ms maxΔ=0.1% | **Done** |
| Timeout Accuracy (Go) | `timeout:fired=2`, `ackTimeouts=2`, maxΔ=0.1% | **Done** |
| GP-Sim benchmark rows | sender p50=5ms p95=8ms; receiver p50=44ms p95=48ms (5/5) | **Done** |
| E-Sim media rows | 1MB=351ms, 5MB=2677ms, progress=6/22, profile=221ms with 3 profile progress events | **Done** |

### Two-Simulator Timing — Now Collected

All implemented two-simulator scenarios now have passing rerun output. The `N1`/`N2` and `BR-S1`/`BR-S3` rows below remain Phase 5 placeholders only because no Alice/Bob harness files exist in the repo; their timing metrics now come from the Phase 3–4 `N-Sim` / `BR-Sim` reruns above.
Collected on 2026-04-15 via `dart run integration_test/scripts/run_routing_smoke_e2e.dart -d 38FECA55,5BA69F1C`:

| Row | Value | Source |
|-----|-------|--------|
| Delete-for-everyone | 192ms, outcome=success | S10 |
| Voice message send | sendVoiceMessage() captured | S11 |
| Media 1MB transfer | 490ms, **2090 KB/s** | S12 |
| Media 5MB transfer | 2495ms, **2052 KB/s** | S12 |
| ACK under load (10 rapid) | 10/10 received | S13 |
| Local WiFi (simulators) | isLocal=false, send=11ms via reuse | S14 |
| Relay probe path | rerun stayed direct: send=572ms, `probe=false` | S15 |
| Both-sides restart | restart=513ms/515ms, send=142ms, e2e=3310ms | X1 |
| Background/foreground | resume=110ms/124ms, e2e=256ms | X2 |
| Relay failover | healthCheck=53ms, send=18ms, e2e=255ms | X3 |
| Group peer discovery | **5255ms** (5s settle + ~255ms actual) | G6 |
| Group key rotation | **1209ms** rotation, preRx=false, postRx=false | G7 |
| Group multi-member | send=1239ms, outcome=`successNoPeers` | G8 |

### Group Timing — Now Collected (Two-Simulator)

First real GossipSub e2e numbers, collected on 2026-04-15 via
`dart run integration_test/scripts/run_routing_smoke_e2e.dart -d 38FECA55,5BA69F1C`:

| Row | Value | Status |
|-----|-------|--------|
| Group Publish (first msg) | send=32ms, e2e=515ms | **Done** (G1) |
| Group Warm x5 | 5/5 delivered | **Done** (G2) |
| Group Bidirectional | 2 recv + 1 sent | **Done** (G3) |
| Group Offline→Inbox→Drain | publish OK, e2e=0ms | **Done** (G4) |
| Group Full Lifecycle (9 msgs) | 9/9 both sides | **Done** (G5) |

---

## File Inventory

### New Test Files (Dart — Phase 1)

| File | Tests | Applies To |
|------|-------|------------|
| `test/performance/benchmark_harness.dart` | — (helper) | BOTH |
| `test/performance/benchmark_harness_test.dart` | 12 | BOTH |
| `test/performance/timing_test_bridge.dart` | — (helper) | BOTH |
| `test/performance/timing_test_bridge_test.dart` | 5 | BOTH |
| `test/performance/benchmark_1_1_send_test.dart` | 6 (A1–A6) | 1:1 |
| `test/performance/benchmark_node_startup_test.dart` | 6 (B1–B6) | BOTH |
| `test/performance/benchmark_relay_recovery_test.dart` | 6 (C1–C6) | BOTH |
| `test/performance/benchmark_inbox_roundtrip_test.dart` | 4 (D1–D4) | BOTH |
| `test/performance/benchmark_media_transfer_test.dart` | 2 (E1–E2) | BOTH |
| `test/performance/benchmark_bridge_crossing_test.dart` | 3 (F1–F3) | BOTH |
| `test/performance/benchmark_encryption_test.dart` | 5 (G1–G5) | BOTH |
| `test/performance/benchmark_timeout_accuracy_test.dart` | 3 (H1–H3) | BOTH |
| `test/performance/benchmark_event_queue_test.dart` | 1 (I-Dart-1) | BOTH |
| `test/performance/benchmark_connection_reuse_test.dart` | 3 (J1–J3) | 1:1 |
| `test/performance/benchmark_voice_send_test.dart` | 3 (K1–K3) | BOTH |
| `test/performance/benchmark_deferred_ack_test.dart` | 1 (L-Dart-1) | 1:1 |
| `test/performance/benchmark_time_to_online_test.dart` | 6 (M1–M6) | BOTH |
| `test/performance/benchmark_routing_paths_test.dart` | 17 (R1–R17) | 1:1 |
| `test/performance/benchmark_notification_tap_to_message_test.dart` | 4 (NT1–NT4) | BOTH |
| `test/performance/benchmark_background_resume_test.dart` | 4 (BR1–BR4) | BOTH |

### New Test Files (Go — Phase 2)

| File | Tests | Applies To |
|------|-------|------------|
| `go-mknoon/node/benchmark_harness_test.go` | 3 | BOTH |
| `go-mknoon/node/benchmark_send_test.go` | 2 | 1:1 |
| `go-mknoon/node/benchmark_startup_test.go` | 3 | BOTH |
| `go-mknoon/node/benchmark_relay_recovery_test.go` | 2 | BOTH |
| `go-mknoon/node/benchmark_inbox_test.go` | 2 | BOTH |
| `go-mknoon/node/benchmark_media_test.go` | 2 | BOTH |
| `go-mknoon/node/benchmark_crypto_test.go` | 3 | BOTH |
| `go-mknoon/node/benchmark_timeout_accuracy_test.go` | 3 | BOTH |
| `go-mknoon/node/benchmark_event_queue_test.go` | 3 | BOTH |
| `go-mknoon/node/benchmark_ack_test.go` | 2 | 1:1 |

### Simulator Benchmark Files (Phase 3–4)

| File | Scenarios | Applies To |
|------|-----------|------------|
| `integration_test/benchmark_helpers.dart` | — (shared) | BOTH |
| `integration_test/benchmark_1_1_send_harness.dart` | A-Sim-1, -2, -3 | 1:1 |
| `integration_test/benchmark_node_startup_harness.dart` | B-Sim-1, -2, -3 | BOTH |
| `integration_test/benchmark_relay_recovery_harness.dart` | C-Sim-1, -2 | BOTH |
| `integration_test/benchmark_inbox_harness.dart` | D-Sim-1, -2 | BOTH |
| `integration_test/benchmark_media_harness.dart` | E-Sim-1, -2 | BOTH |
| `integration_test/benchmark_bridge_crossing_harness.dart` | F-Sim-1 | BOTH |
| `integration_test/benchmark_encryption_harness.dart` | G-Sim-1, -2, -3 | BOTH |
| `integration_test/benchmark_timeout_accuracy_harness.dart` | H-Sim-1, -2 | BOTH |
| `integration_test/benchmark_event_queue_harness.dart` | I-Sim-1, -2 | BOTH |
| `integration_test/benchmark_connection_reuse_harness.dart` | J-Sim-1 | 1:1 |
| `integration_test/benchmark_voice_harness.dart` | K-Sim-1 | BOTH |
| `integration_test/benchmark_ack_harness.dart` | L-Sim-1 | 1:1 |
| `integration_test/benchmark_time_to_online_harness.dart` | M-Sim-1, -2, -Hot, -3 | BOTH |
| `integration_test/benchmark_background_resume_harness.dart` | BR-Sim-1, -2, -3 | BOTH |
| `integration_test/benchmark_notification_tap_harness.dart` | N-Sim-1, -2 | BOTH |
| `integration_test/benchmark_group_publish_harness.dart` | GP-Sim-1, -2 | GRP |
| `integration_test/benchmark_routing_paths_harness.dart` | R-Sim-1 through -8 | 1:1 |
| `integration_test/scripts/run_timeout_accuracy_benchmark.dart` | H-Sim orchestrator | BOTH |
| `integration_test/scripts/run_group_publish_benchmark.dart` | GP-Sim orchestrator | GRP |
| `integration_test/scripts/run_benchmark_suite.dart` | Orchestrator | — |

### Two-Simulator Smoke Test Files (Phase 5)

| File | Role | Applies To |
|------|------|------------|
| `integration_test/routing_smoke_alice_harness.dart` | Alice (sender, S1–S15 + X1–X3) on simulator 1 | 1:1 |
| `integration_test/routing_smoke_bob_harness.dart` | Bob (receiver, S1–S15 + X1–X3) on simulator 2 | 1:1 |
| `integration_test/group_smoke_alice_harness.dart` | Alice (group creator, G1–G8) on simulator 1 | GRP |
| `integration_test/group_smoke_bob_harness.dart` | Bob (group joiner, G1–G8) on simulator 2 | GRP |
| `integration_test/scripts/run_routing_smoke_e2e.dart` | Orchestrator (Phase 1: S1–S15 + X1–X3, Phase 2: G1–G8) | BOTH |

### Modified Files

| File | Change |
|------|--------|
| `test/shared/fakes/fake_p2p_service_integration.dart` | Added `testConnections`, `ConnectionState` import, `probeRelayResult`, `dialAlwaysFails`, `discoverAlwaysFails`, `discoverDelay`, `dialDelay`, `sendDelay` for routing path test control |
| `scripts/run_test_gates.sh` | Added `benchmark`, `benchmark-sim` gates + classification |
| `lib/features/posts/application/post_delivery_runner.dart` | Added `POST_SEND_DELIVERY_TIMING` event with `elapsedMs`, `outcome`, `recipientCount`, `deliveryStatus` |
| `lib/features/conversation/application/send_chat_message_use_case.dart` | Added `messageId` to `CHAT_MSG_SEND_TIMING` success path for sender↔receiver correlation |
| `lib/core/utils/notification_tap_timing.dart` | Added `emitNotificationTapTiming()` helper — emits `NOTIFICATION_TAP_TO_MESSAGE_TIMING` with `elapsedMs`, `routeKind`, `messageId` |
| `lib/main.dart` | Added `_notificationTappedAt` field, set at tap time (local + remote), threaded to conversation/group screens, cleared after use |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | Added `notificationTappedAt` optional param, emits `NOTIFICATION_TAP_TO_MESSAGE_TIMING` after initial load via `addPostFrameCallback` |
| `lib/features/groups/presentation/screens/group_conversation_wired.dart` | Same as above for group conversation path |
| `lib/core/services/p2p_service_impl.dart` | Added `markResumeStarted()`, `checkResumeAlreadyOnline()`, `clearResumeStarted()`, `background_resume` phase in `_emitState()` |

### Totals

| Category | Tests | Files |
|----------|-------|-------|
| Phase 0: Shared harness | 20 | 5 |
| Phase 1: Dart instrumentation | 74 | 16 |
| Phase 2: Go instrumentation | 25 | 10 |
| Phase 3–4: Simulator benchmarks | 42 scenarios | 21 |
| Phase 5: Two-simulator smoke (1:1 + cross-cutting) | 18 scenarios (S1–S15 + X1–X3) | 2 harnesses |
| Phase 5: Two-simulator smoke (notification/resume) | 5 planned scenarios (N1–N2 + BR-S1–S3) | 0 Alice/Bob harnesses implemented; Phase 3–4 equivalents exist |
| Phase 5: Two-simulator smoke (Group) | 8 scenarios (G1–G8) | 2 harnesses |
| Phase 5: Orchestrator | — | 1 |
| Production instrumentation | — | 5 |
| Modified existing (fakes/scripts) | — | 2 |
| **Total** | **187 implemented tests/scenarios + 5 planned two-sim placeholders** | **64 existing files + 2 planned two-sim harness files referenced in docs** |
