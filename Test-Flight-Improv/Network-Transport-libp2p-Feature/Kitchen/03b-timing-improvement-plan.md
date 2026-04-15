# Timing Improvement Plan

> **Scope:** Instrumentation gaps, hazard fixes, simulator timing tests, and benchmark roadmap.
> **Depends on:** `03-timing-and-performance.md` (timing data, blind spots, hazards, timeout reference).
> **See also:** `04b-routing-improvement-plan.md` for routing-level changes (budget starvation, relay selection, connection pre-warming).

---

## 1. What We Learn (Timing & Instrumentation)

**The system is instrumented broadly but shallowly.** Dart measures 15+ flows end-to-end, but every measurement is a single number — you know *how long* a send took, never *which step* was slow. Go measures almost nothing.

### Active Hazards (No Mitigation)

| Hazard | Impact |
|---|---|
| `recoveryPromise.Wait()` blocks with no timeout | If recovery goroutine stalls, all coalescers block permanently |
| Media `io.Copy` has no stall detection | 5-min absolute deadline only — 1 byte/s is indistinguishable from a slow transfer |
| `callP2PInboxStore` has no Dart-side `.timeout()` | Bridge hang = Dart blocks indefinitely (Go's 15s timeout won't fire if call never reaches Go) |
| `callP2PRelayProbe` has no Dart-side `.timeout()` | Same bridge-hang risk (Go's 5s timeout is Go-side only) |
| Profile upload uses bare `io.Copy` — no progress events | Can stall 5 min invisibly with no UI feedback |

### Instrumentation Gaps

| Gap | Impact |
|---|---|
| No per-step breakdown in 1:1 send | `CHAT_MSG_SEND_TIMING` reports total time — can't tell if discover, dial, or send is slow |
| No per-step breakdown in group send | `GROUP_SEND_MSG_TIMING` reports total time — can't tell if publish, inbox store, or settle wait is slow |
| No GossipSub publish-to-receive latency | Time from `topic.Publish` to `group_message:received` at recipient is unmeasured — can't tell if pubsub delivery or peer discovery is the bottleneck |
| No group encrypt/decrypt timing | Group v3 envelope encryption (AES-256-GCM + Ed25519 sign) happens Go-side during `callGroupPublish` — overhead unknown |
| No Go-side latency measurement | Stream open, relay warm-up, rendezvous RTT, event queue wait — all unmeasured |
| No event dispatcher queue-wait measurement | Can't tell whether transport time is actually spent in the network path or waiting for Go event delivery/callback dispatch |
| No MethodChannel bridge crossing measurement | Dart-to-Go serialization + channel latency is a blind spot |
| No 1:1 encryption/decryption timing | ML-KEM keygen, encrypt, decrypt overhead unknown |
| No correlation IDs for 1:1 messages | Can't trace sender -> transport -> receiver (group messages DO have this via messageId) |
| No connection reuse hit-rate metric | Can't quantify how often the fast path (`isAlreadyConnected`) actually avoids the cold-start race in real workloads |
| Local WiFi path has no `_TIMING` summary | 20+ per-phase flow events but no Stopwatch-based end-to-end metric |
| Post path has no `_TIMING` summary | Per-phase events with elapsed-since-start exist but no single summary event |
| Voice send path has no sub-step timing | `VOICE_SEND_TIMING` reports total duration only — can't tell whether upload or send dominates |
| No deferred direct ACK round-trip timing | The 2s confirm window exists, but actual receiver confirm latency and sender unblock latency are unmeasured |
| Sequential relay failover adds 10s per dead relay | Latency multiplier, not measured as a distinct metric |

---

## 2. Tests to Implement (Simulator-Based Timing Measurement)

These tests run on simulators to fill the blind spots. Each test measures latency under controlled conditions.

> **Instrumentation dependency:** Each test below lists the `03c` / `03d` sections that must be implemented first — those sections add the events the benchmark harness collects.

### A. Per-Step 1:1 Send Breakdown

**Instrumentation:** `03c` §4 (Go per-step timing), §7 (connection reuse counters), §10 (per-step 1:1 send)

```
Scenario: Send message to peer with no prior connection
Measure:  discoverMs, dialMs, sendMs, total elapsedMs
          -> also: sendPath (direct / relay / inbox)
Collect:  CHAT_MSG_SEND_TIMING with details.discoverMs, details.dialMs,
          details.sendMs, details.sendPath, details.connectionReused
          SendMessageResult.StreamOpenMs, .WriteMs, .AckWaitMs (Go-side)

Scenario: Send message to peer with warm connection
Measure:  sendMs (should be <100ms with reuse)
Collect:  CHAT_MSG_SEND_TIMING with sendPath='reuse', connectionReused=true

Scenario: Send 10 messages sequentially to same peer
Measure:  first_send_ms vs subsequent_send_ms (connection reuse effect)
Collect:  10× CHAT_MSG_SEND_TIMING — first has connectionReused=false,
          subsequent have connectionReused=true. Compare elapsedMs.
```

### B. Node Startup Timing

**Instrumentation:** `03c` §4 (relay warm timing), §11 (circuit address delay), §18 (node startup timing summary), §24 (time-to-online badge)

```
Scenario: Cold start node, measure each phase
Measure:  libp2pNewMs, pubsubInitMs, relayWarmMs, circuitAddressMs,
          rendezvousRegisterMs, totalToDiscoverableMs,
          timeToOnlineBadgeMs (user-perceived)
Collect:  node:startup_timing (phase=host_ready): libp2pNewMs, pubsubInitMs
          node:startup_timing (phase=relay_warm): relayWarmMs, relaysAttempted
          node:startup_timing (phase=discoverable): circuitAddressMs,
              rendezvousRegisterMs, totalToDiscoverableMs
          circuit_address:timing: elapsedMs, pollCount
          TIME_TO_ONLINE_BADGE: totalMs, phase='cold_start', source
          TIME_TO_ONLINE_BADGE_WIDGET: widgetTransitionMs
Assert:   totalToDiscoverableMs < 5s on simulator
          TIME_TO_ONLINE_BADGE.totalMs < 6s on simulator
              (5s Go + 1s delivery margin)
```

### C. Relay Reconnect / Recovery

**Instrumentation:** `03c` §19 (relay outage timing), §24 (time-to-online badge recovery phase). **Hazard fix:** `03d` §4 (recovery promise timeout)

```
Scenario: Kill relay connection, measure recovery
Measure:  detectionMs (health check cycle or push event),
          recoveryMs (relay:reconnect duration),
          totalOutageMs (last healthy → first healthy),
          timeToOnlineBadgeMs (degraded badge → green badge)
Collect:  RELAY_OUTAGE_TIMING (phase=detected): detectionMs, detectionSource
          RELAY_OUTAGE_TIMING (phase=recovered): recoveryMs, totalOutageMs,
              recoveryMode
          TIME_TO_ONLINE_BADGE: totalMs, phase='recovery'
          TIME_TO_ONLINE_BADGE_WIDGET: widgetTransitionMs

Scenario: Kill relay, recovery goroutine stalls (03d §4 timeout path)
Measure:  time until RECOVERY_TIMEOUT fires (~30s),
          time until next recovery attempt starts
Collect:  timeout:fired with timeoutName='RecoveryWaitTimeout'
          Second RELAY_OUTAGE_TIMING (phase=detected) after gate clears
```

### D. Inbox Store/Retrieve Round-Trip

**Instrumentation:** `03c` §12 (inbox round-trip timing), §20 (inbox end-to-end delivery)

```
Scenario: Peer offline, send via inbox, peer comes online, retrieves
Measure:  store_ms (sender side, per-step: connectMs, streamOpenMs,
              writeMs, readMs, totalMs),
          retrieve_ms (receiver side, per-step: totalMs, messageCount),
          end_to_end_delivery_ms (storedAtNano → receiver Dart delivery)
Collect:  inbox:store_timing: connectMs, streamOpenMs, writeMs, readMs,
              totalMs, outcome
          inbox:retrieve_timing: totalMs, messageCount, outcome
          INBOX_DELIVERY_TIMING: deliveryMs, messageId
Assert:   inbox:store_timing.totalMs < 200ms with warm relay
```

### E. Media Transfer Timing

**Instrumentation:** `03c` §2 (local WiFi timing), §21 (media stream open + throughput). **Hazard fixes:** `03d` §3 (profile upload progress), §5 (media idle timeout)

```
Scenario: Upload 1MB, 5MB, 20MB files
Measure:  stream_open_ms (connect + NewStream),
          upload_throughput_bytes_per_sec,
          total_ms, progress_event_count
Collect:  media:stream_open_timing: connectMs, newStreamMs, totalMs, outcome
          media:upload_complete: totalBytes, totalMs, throughputBytesPerSec
          media:upload_progress events (count them)
          profile:upload_progress events (for profile uploads, 03d §3)

Scenario: Same over local WiFi path
Measure:  offer_to_accept_ms, transfer_throughput, total_ms
Collect:  LOCAL_MEDIA_SEND_TIMING: elapsedMs, outcome, mediaId, sizeBytes

Scenario: Stalled upload fails fast (03d §5)
Measure:  time from stall start to ErrStallTimeout
Collect:  Error propagation within MediaIdleTimeout (10s),
          NOT full MediaTimeout (5 min)
```

### F. MethodChannel Bridge Crossing

**Instrumentation:** `03c` §14 (bridge crossing time)

```
Scenario: 1000 round-trip bridge calls (e.g., encrypt/decrypt)
Measure:  per_call_ms (p50, p95, p99)
Collect:  1000× BRIDGE_CALL_TIMING: cmd, bridgeMs, outcome
          Compute percentiles from bridgeMs distribution.
Purpose:  Establish baseline for bridge overhead — currently unmeasured
```

### G. Encryption Overhead

**Instrumentation:** `03c` §15 (1:1 encryption timing), §16 (group encrypt/decrypt), §22 (ML-KEM keygen timing)

```
Scenario: ML-KEM keygen
Measure:  keygenMs
Collect:  MLKEM_KEYGEN_TIMING: keygenMs
          MlKemKeygen bridge response: keygenMs

Scenario: Encrypt/decrypt with various payload sizes (100B, 1KB, 10KB, 100KB)
Measure:  encrypt_ms, decrypt_ms per size bucket
Collect:  CHAT_MSG_SEND_TIMING: encryptMs (per message, §15)
          EncryptMessage response: encryptMs, payloadSizeBytes (§22)
          DecryptMessage response: decryptMs, payloadSizeBytes (§22)
          group:publish_debug: encryptMs, signMs (§16)
          group_message:received: decryptMs (§16)
Purpose:  Determine if crypto is a meaningful contributor to send latency.
          Correlate encryptMs with payloadSizeBytes to find scaling curve.
```

### H. Timeout Accuracy

**Instrumentation:** `03c` §23 (pre-existing timeout accuracy). **Hazard fixes:** `03d` §1–§5 (new timeouts)

```
Scenario: Force each timeout to fire (simulate unresponsive peer/relay)
Measure:  actualMs vs configuredMs for each constant
Collect:  timeout:fired events for each timeout:
          - DialTimeout (15s)
          - PeerDialTimeout (2s)
          - RelayProbeTimeout (5s) — 03d §2 adds Dart-side
          - SendTimeout (15s)
          - DiscoverTimeout (10s)
          - InboxTimeout (15s) — 03d §1 adds Dart-side
          - MediaTimeout (5 min)
          - PubSubTimeout (30s)
          - DirectConfirmTimeout (2s)
          - InteractiveDialTimeout (4s)
          - InteractiveSendTimeout (3s)
          - InteractiveDiscoverTimeout (2s)
          - InteractiveInboxTimeout (3s)
          - RecoveryWaitTimeout (30s) — 03d §4
          - MediaIdleTimeout (10s) — 03d §5
          Each: timeout:fired { timeoutName, configuredMs, actualMs }
Purpose:  Verify timeouts fire when expected, detect stacking.
Assert:   actualMs is within 10% of configuredMs for each timeout.
```

### I. Event Queue Wait

**Instrumentation:** `03c` §6 (event queue wait timing)

```
Scenario: Emit transport events under idle and loaded conditions
Measure:  emit_to_callback_ms (p50, p95, p99),
          callback_backlog_depth if available
Collect:  All delivered events include queueWaitMs field.
          Under idle: expect queueWaitMs < 50ms.
          Under load (slow callback): expect queueWaitMs to increase
              proportionally to callback delay × queue depth.
Purpose:  Determine whether Go event dispatch is adding hidden latency
```

### J. Connection Reuse Hit Rate

**Instrumentation:** `03c` §7 (connection reuse counters), §10 (per-step 1:1 send)

```
Scenario: Scripted conversation workload (first send, warm follow-up sends, resume)
Measure:  reuse_hit_rate_pct, cold_send_count, warm_send_count,
          latency split for reused vs cold sends
Collect:  N× CHAT_MSG_SEND_TIMING with:
          - connectionReused (true/false) → compute hit rate
          - sendPath ('reuse' vs 'direct'/'relay'/'inbox') → count by path
          - elapsedMs → split by connectionReused for latency comparison
Purpose:  Quantify how often the fast path is actually carrying interactive traffic
```

### K. Voice Send Sub-Step Breakdown

**Instrumentation:** `03c` §8 (voice send sub-steps)

```
Scenario: Send voice notes across size buckets
Measure:  upload_ms, send_ms, total_ms,
          upload_share_pct_of_total
Collect:  VOICE_SEND_TIMING: uploadMs, sendMs, elapsedMs
          upload_share = uploadMs / elapsedMs × 100
Purpose:  Distinguish media preparation cost from transport delivery cost
```

### L. Deferred Direct ACK Timing

**Instrumentation:** `03c` §9 (deferred ACK timing events)

```
Scenario: Warm direct send that requires receiver-side confirm
Measure:  message_received_to_confirm_call_ms,
          confirm_call_to_sender_unblock_ms,
          total_ack_round_trip_ms
Collect:  message:direct_ack_timing (Go): waitMs, ackWriteMs, outcome
          CHAT_MSG_SEND_TIMING (Dart): ackRoundTripMs (if broken out)
Assert:   p95 waitMs stays within DirectConfirmTimeout (2s) on simulator
Purpose:  Verify the ACK path is not silently consuming the full 2s budget
```

### M. Time-to-Online Badge (User-Perceived Startup Latency)

**Instrumentation:** `03c` §18 (node startup timing), §24 (time-to-online badge)

```
Scenario: Cold start — measure wall-clock from app launch to green badge
Measure:  time_to_online_badge_ms (service layer),
          widget_transition_ms (render layer),
          total_user_perceived_ms = badge_ms + widget_ms
Collect:  TIME_TO_ONLINE_BADGE: totalMs, phase='cold_start', source
          TIME_TO_ONLINE_BADGE_WIDGET: widgetTransitionMs
          node:startup_timing (all 3 phases for Go-side decomposition)
Assert:   total_user_perceived_ms < 6s on simulator

Scenario: Recovery — measure wall-clock from degraded badge to green badge
Measure:  time_to_online_badge_ms (recovery phase),
          widget_transition_ms
Collect:  TIME_TO_ONLINE_BADGE: totalMs, phase='recovery', source
          TIME_TO_ONLINE_BADGE_WIDGET: widgetTransitionMs
          RELAY_OUTAGE_TIMING: detectionMs, recoveryMs, totalOutageMs

Scenario: Hot restart — measure resync to green badge
Measure:  time_to_online_badge_ms
Collect:  TIME_TO_ONLINE_BADGE: totalMs, phase='hot_restart', source

Scenario: Which delivery path wins the race?
Measure:  source distribution across N cold starts
Collect:  TIME_TO_ONLINE_BADGE.source across runs:
          'start_response' (Go returned online in Start() response),
          'relay_state_push' (EventChannel push won),
          'health_check_poll' (2s fast check or 30s periodic won),
          'addresses_push' (circuit address push won)
Purpose:  Identify whether push or poll dominates, and whether the 2s
          fast circuit check is still necessary
```

### Cross-reference: Tests with routing implications

- **Group discovery + first message timing** — see `04b-routing-improvement-plan.md` Test A
- **Deferred direct ACK timing under routing stress** — see `04b-routing-improvement-plan.md` Test B

### Instrumentation Coverage Summary

Every test above has full instrumentation coverage from `03c` §1–§24 + `03d` §1–§5:

| Test | Instrumentation (03c) | Hazard Fixes (03d) |
|---|---|---|
| **A** Per-Step 1:1 Send | §4, §7, §10 | — |
| **B** Node Startup | §4, §11, §18, §24 | — |
| **C** Relay Recovery | §19, §24 | §4 |
| **D** Inbox Round-Trip | §12, §20 | — |
| **E** Media Transfer | §2, §21 | §3, §5 |
| **F** Bridge Crossing | §14 | — |
| **G** Encryption Overhead | §15, §16, §22 | — |
| **H** Timeout Accuracy | §23 | §1, §2, §4, §5 |
| **I** Event Queue Wait | §6 | — |
| **J** Connection Reuse | §7, §10 | — |
| **K** Voice Sub-Steps | §8 | — |
| **L** Deferred ACK | §9 | — |
| **M** Time-to-Online | §18, §24 | — |

---

## 3. Instrumentation to Add (Code Changes to Measure Things)

These are code changes that add observability — they don't change behavior, they let us fill in the baseline table.

| Change | What It Measures | Effort |
|---|---|---|
| **Add `_TIMING` summary event for Post delivery** | End-to-end post send latency (currently per-phase events only, no single metric) | ~20 lines |
| **Add `_TIMING` summary event for Local WiFi transfer** | End-to-end local media transfer latency (currently 20+ events, no single metric) | ~20 lines |
| **Add `_TIMING` summary event for group send per-step** | Publish vs inbox store vs settle wait breakdown (currently single total number) | ~20 lines |
| **Per-step timing instrumentation in Go** | Stream open, relay warm, rendezvous RTT, event queue wait | ~50 lines Go |
| **Add correlation ID to 1:1 messages** | End-to-end tracing from sender to receiver (group messages already have this) | ~30 lines |
| **Add event queue wait timing to Go `EventDispatcher`** | `Emit()` -> callback delivery latency under idle and loaded conditions | ~20 lines Go |
| **Add connection reuse counters to 1:1 send path** | Reuse hit rate, cold-send frequency, and latency split by path | ~15 lines Dart |
| **Split `VOICE_SEND_TIMING` into upload/send sub-steps** | Upload time vs transport send time for voice messages | ~20 lines Dart |
| **Add deferred direct ACK timing events** | Receiver confirm latency and sender unblock latency | ~20 lines Dart/Go |

---

## 4. Hazard Fixes (Code Changes to Fix Real Risks)

These don't make the happy path faster. They prevent the app from **hanging indefinitely** or **stalling silently** when something breaks. The fix is: fail fast instead of freeze, then let existing retry mechanisms recover.

### Ready to Implement

These have clean failure paths — existing resilience handles the aftermath.

| Change | What Happens Today | What Happens After Fix | User Sees | Auto Retry? | Effort |
|---|---|---|---|---|---|
| **Add Dart-side `.timeout()` to `callP2PInboxStore`** | Bridge hang = Dart blocks **forever** | Timeout after 15s → status: `failed`, wireEnvelope retained | Failed indicator on message | YES — `PendingMessageRetrier` (5 min periodic or 5s after online) retries via inbox fast-path, then full sendChatMessage | 2 lines |
| **Add Dart-side `.timeout()` to `callP2PRelayProbe`** | Bridge hang = Dart blocks **forever** | Timeout after 5s → send path falls through to inbox fallback (next step) | Nothing — send continues | N/A — inbox is the next step, not a retry | 2 lines |
| **Profile upload progress events** | Profile upload can stall 5 min with no UI feedback | Same behavior, but user sees progress bar instead of nothing | Progress bar instead of blank | No (user-initiated, not queued) | ~10 lines Go |

### Needs Design Before Implementing

These need explicit post-timeout behavior. The first-pass designs below are sufficient and fit the current codebase.

**`recoveryPromise.Wait()` — add timeout to Go relay recovery coalescing**

| | |
|---|---|
| **Today** | If recovery goroutine stalls, all coalescers block permanently. Node's relay functionality is dead until app restart. |
| **After adding timeout** | Shared recovery wait fails after e.g. 30s instead of blocking forever. |
| **Sufficient first-pass design** | Return a structured recovery failure such as `RECOVERY_TIMEOUT`. Clear the shared recovery gate when the timeout fires so the next recovery attempt can start fresh. Ignore any late completion from the timed-out attempt. Do **not** add a second Go retry loop in this first pass. Do **not** add a new relay state in this first pass — existing `relayState != online` already means degraded. |
| **Retry owner** | Dart remains the single retry owner. `relay:reconnect` timeout must surface to Flutter as a real failure, not as a successful response. The existing degraded `relay:state` push and periodic health check will retry later. |
| **User sees** | No new user-facing warning in the first pass. Existing degraded/offline behavior is enough. |
| **Why this is sufficient** | The app already has reservation-aware relay health, immediate degraded push recovery, and periodic health checks. The missing piece is bounded failure + gate release, not a new recovery framework. |

**Media idle timeout — add throughput floor to `io.Copy`**

| | |
|---|---|
| **Today** | Stalled connection trickling 1 byte/s runs for 5 min before the absolute deadline kills it. |
| **After adding idle timeout** | Stalled transfer fails after e.g. 10s of no bytes, while the existing 5-min absolute deadline remains the outer guard. |
| **Sufficient first-pass design** | Treat idle timeout as a normal transient upload failure. Reuse the current `upload_pending` -> retry flow for images/video/files and the existing failed-message path for voice. In the first pass, define stall as "no bytes copied for 10s" rather than introducing a more complex adaptive throughput model. |
| **Auto retry** | YES — reuse the existing upload retriers. Keep the current retry ceiling (`kMaxUploadRetries = 3`), then mark the attachment `upload_failed` and stop auto-retrying. |
| **User sees** | Keep the existing progress + failed indicator behavior. No special "connection too slow" UI is needed in the first pass. |
| **Why this is sufficient** | The app already persists `upload_pending`, shows upload progress, retries on resume/online, and terminalizes repeated failures after a bounded retry count. The missing piece is failing fast on a stalled stream, not a new retry system. |

### Cross-reference: Routing fixes

These fix real risks but are routing-level changes — see `04b-routing-improvement-plan.md` Section 3:
- **Use `InteractiveInboxTimeout` (3s)** — inbox fallback takes 15s instead of intended 3s
- **Parallel relay failover** — dead relay adds 10s before next is tried

---

## 5. Benchmark System Roadmap

### Phase 1: Instrument (Fill the Blind Spots)

Add per-step timing to the Go side. Minimal approach:

```go
// In each critical function, wrap with timing:
start := time.Now()
// ... operation ...
n.emitTiming("stream_open", time.Since(start))
```

Target the blind spots listed above. Priority order:
1. Go stream open latency
2. Relay warm-up time
3. Rendezvous round-trip
4. Event queue wait
5. MethodChannel bridge crossing
6. Encryption/decryption time
7. Deferred direct ACK timing

### Phase 2: Collect (Structured Timing Export)

Replace debug-only `emitFlowEvent` with a structured timing collector:

```
TimingCollector
  +-- records: List<TimingRecord>  {path, step, duration_ms, metadata, timestamp}
  +-- startSpan(path, step) -> SpanHandle
  +-- endSpan(handle)
  +-- export() -> JSON / CSV / SQLite
```

- Each `TimingRecord` has a `traceId` for end-to-end correlation
- Export to a local SQLite table or JSON file on the simulator
- Can be queried post-test for analysis

### Phase 3: Baseline (Measure the Current Build)

Run the tests from section 2 on the current build and record the numbers. This is the single snapshot that tells us where time actually goes — which steps are slow, which hazards are real, and which improvements from `04b-routing-improvement-plan.md` are worth pursuing first.

```
=====================================================
  mknoon Transport Timing — Current Build
=====================================================
  1:1 Send (cold)             p50=___   p95=___    (Test A)
  1:1 Send (warm)             p50=___   p95=___    (Test A)
  Group Publish (peers ready) p50=___   p95=___
  Group Publish (0 peers)     p50=___   p95=___
  Group Discovery (join→connected) p50=___   p95=___
  Node Startup (Go)           p50=___   p95=___    (Test B)
  Time-to-Online Badge        p50=___   p95=___    (Test M)
  Relay Recovery              p50=___   p95=___    (Test C)
  Relay Outage (total)        p50=___   p95=___    (Test C)
  Inbox Store (warm)          p50=___   p95=___    (Test D)
  Inbox E2E Delivery          p50=___   p95=___    (Test D)
  Event Queue Wait            p50=___   p95=___    (Test I)
  Media 5MB Upload            p50=___   p95=___    (Test E)
  Media Stream Open           p50=___   p95=___    (Test E)
  Media Throughput (bytes/s)  p50=___   p95=___    (Test E)
  Voice Upload Phase          p50=___   p95=___    (Test K)
  Voice Transport Phase       p50=___   p95=___    (Test K)
  Direct ACK Round-Trip       p50=___   p95=___    (Test L)
  Bridge: MethodChannel RT    p50=___   p95=___    (Test F)
  Crypto: ML-KEM keygen       p50=___   p95=___    (Test G)
  Crypto: ML-KEM encrypt      p50=___   p95=___    (Test G)
  Connection Reuse Hit Rate   ___%                 (Test J)
  Timeout Accuracy (max Δ%)   ___%                 (Test H)
=====================================================
```

After applying a fix, re-run the relevant test to confirm the improvement. The baseline numbers are the "before" — each fix gets a "after" comparison on the same build.

---

## Recommended Immediate Next Steps

1. Add per-step timing to both transport paths (must instrument before measuring):
   - **1:1 send path** (Dart + Go) — discover, dial, send, relay probe, inbox fallback per step
   - **Group send path** (Dart + Go) — GossipSub publish latency, inbox store latency, pre-publish settle wait, peer discovery loop timing, publish-to-receive latency
2. Add the missing benchmark probes:
   - **Event queue wait** — `Emit()` to callback delivery timing in Go
   - **Connection reuse hit rate** — count reused vs cold sends in scripted workloads
   - **Voice send sub-steps** — upload vs send phase timing
   - **Deferred direct ACK timing** — receiver confirm and sender unblock timing
3. Build the simulator tests from section 2 (start with A: cold vs warm 1:1 send, then group discovery + first message)
4. **Run the tests and produce the baseline output** — fill in the table from Phase 3 with real numbers from the current build
5. Use the baseline to decide which fixes matter most — if inbox fallback is 15s in practice, the `InteractiveInboxTimeout` fix is urgent; if bridge crossing is <5ms, skip that investigation
6. Apply fixes (hazard fixes from section 4, routing changes from `04b`), re-run the relevant tests, compare before/after
