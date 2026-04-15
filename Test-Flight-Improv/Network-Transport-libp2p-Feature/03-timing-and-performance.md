# Timing and Performance Characteristics

> **Scope:** Runtime timing behavior across all transport paths.
> **Includes:** Current instrumentation state (Dart + Go), measured baseline, critical path timing analysis (12 paths with exact blocking steps), complete timeout reference table (including local discovery and media constants), architectural observations.
> **Excludes:** What components exist (see `00`), Dart data flow wiring (see `01`), UI layer (see `02`), routing decision logic and test coverage (see `04`).
> **Method note:** Timing figures marked **Measured** come from the simulator baseline collected on 2026-04-15 (see `03b-benchmark-test-inventory.md`). All other `~ms`, `0-N s`, `Typical`, or `Worst case` figures are inferred estimates from control flow + configured timeouts. The current baseline now has runnable measurements for the previously missing simulator paths, including low-level media upload/profile rows from `E-Sim`.

---

## 1. Current Instrumentation State

### What We Already Measure (Dart side)

Dart has broad timing coverage via `Stopwatch` + `emitFlowEvent`. All measurements are local debug-print only (gated behind `kDebugMode`). No export/dashboard layer.

| Flow Event | What It Measures | Granularity |
|---|---|---|
| `CHAT_MSG_SEND_TIMING` | 1:1 send latency with per-step breakdown | `elapsedMs`, `outcome`, `sendPath`, `connectionReused`, `messageId`, sub-steps: `discoverMs`, `dialMs`, `sendMs`, `encryptMs`, `streamOpenMs`, `writeMs`, `ackWaitMs` |
| `GROUP_SEND_MSG_TIMING` | Group send latency with per-step breakdown | `elapsedMs`, `outcome`, sub-steps: `prepareMs`, `publishMs`, `inboxMs` |
| `MEDIA_UPLOAD_TIMING` | Upload duration + file size | Single number + metadata |
| `MEDIA_DOWNLOAD_TIMING` | Download duration + file size | Single number + metadata |
| `RETRY_FAILED_MESSAGES_TIMING` | Retry batch duration + counts | Batch-level |
| `RETRY_UNACKED_MESSAGES_TIMING` | Unacked retry duration | Batch-level |
| `RETRY_FAILED_GROUP_MESSAGES_TIMING` | Group retry duration | Batch-level |
| `RETRY_INCOMPLETE_UPLOADS_TIMING` | Upload recovery duration | Batch-level |
| `RETRY_INCOMPLETE_GROUP_UPLOADS_TIMING` | Group upload recovery | Batch-level |
| `RECOVER_STUCK_SENDING_TIMING` | Stuck message recovery | Batch-level |
| `RECOVER_STUCK_SENDING_GROUP_TIMING` | Stuck group recovery | Batch-level |
| `GROUP_REJOIN_TOPICS_TIMING` | Per-group and batch rejoin | Per-group + batch |
| `GROUP_DRAIN_OFFLINE_INBOX_TIMING` | Offline inbox drain | Batch-level |
| `RETRY_FAILED_GROUP_INBOX_STORES_TIMING` | Inbox store retry | Batch-level |
| `CHAT_MSG_DELETE_FOR_EVERYONE_TIMING` | Delete-for-everyone send latency | Single number: start-to-outcome |
| `VOICE_SEND_TIMING` | Voice message send latency with sub-steps | `elapsedMs`, `uploadMs`, `sendMs`, `outcome`, `durationMs`, `sizeBytes`, `result` (failure path only) |
| `POST_CREATE_LOCAL_*` | Post creation phases (START, RECIPIENTS_READY, POST_SAVED, DELIVERIES_SAVED, SUCCESS, ABORT) | Per-phase with elapsed since start |
| `POST_SEND_DELIVERY_TIMING` | Post delivery fanout latency | `elapsedMs`, `outcome`, `recipientCount`, `deliveryStatus` |
| `LOCAL_MEDIA_SEND_TIMING` | Local WiFi media transfer end-to-end | `elapsedMs`, `outcome`, `mediaId` |
| `NOTIFICATION_TAP_TO_MESSAGE_TIMING` | Notification tap to message visible | `elapsedMs`, `routeKind` (conversation/group), `messageId` (truncated 8 chars) |
| `TIME_TO_ONLINE_BADGE` | User-perceived startup/resume latency (service layer) | `totalMs`, `phase` (cold_start/recovery/hot_restart/background_resume/background_resume_already_online), `source` |
| `TIME_TO_ONLINE_BADGE_WIDGET` | Widget render transition latency | `widgetTransitionMs`, `previousHealth` |
| `RELAY_OUTAGE_TIMING` | Relay outage detection and recovery | `phase` (detected/recovered), `detectionMs`, `detectionSource` (push/poll), `recoveryMs`, `totalOutageMs`, `recoveryMode` |
| `BRIDGE_CALL_TIMING` | MethodChannel round-trip latency | `cmd`, `bridgeMs`, `outcome` |
| `INBOX_DELIVERY_TIMING` | Inbox end-to-end delivery latency (per-entry replay timing) | `deliveryMs`, `messageId` |
| `REPOST_CREATE_LOCAL_SUCCESS` | Repost (pass-along) creation | Single event on success |
| `KEY_EXCHANGE_RETRY_COORDINATOR_*` | Key exchange cooldown | Per-attempt |

**Infrastructure files:**
- `lib/core/utils/startup_timing.dart` — startup phase marks (mark/elapsed/printSummary)
- `lib/core/utils/flow_event_emitter.dart` — structured flow events with ISO8601 timestamps

### What We Already Measure (Go side)

Go now has per-step timing instrumentation across startup, inbox, media, crypto, relay, ACK, and event delivery paths. Events are emitted via `EventDispatcher` and forwarded to Dart as `FLOW` events.

| Event | What It Measures | Granularity |
|---|---|---|
| `node:startup_timing` | Per-phase startup: phase `host_ready` emits `libp2pNewMs`, `pubsubInitMs`; phase `relay_warm_done` emits `relayWarmMs`, `relaysAttempted`; phase `discoverable` emits `circuitAddressMs`, `circuitAddressOutcome`, `rendezvousRegisterMs`, `totalToDiscoverableMs` | Per-phase |
| `relay:warm_timing` | Relay warm-up latency | Per-relay |
| `relay:state` | Relay state transitions (online/degraded/offline) | Per-transition |
| `circuit_address:timing` | Circuit address acquisition: `elapsedMs`, `pollCount` | Single number + metadata |
| `inbox:store_timing` | Per-step inbox store: `connectMs`, `streamOpenMs`, `writeMs`, `readMs`, `totalMs` | Per-step |
| `inbox:retrieve_timing` | Inbox retrieve: `totalMs`, `messageCount` | Single number + metadata |
| `media:stream_open_timing` | Media stream open: `connectMs`, `newStreamMs`, `totalMs` | Per-step |
| `media:upload_progress` | Upload progress: every 256 KB or 250 ms | Periodic |
| `profile:upload_progress` | Profile upload progress: `sentBytes`, `totalBytes` | Periodic |
| `message:direct_ack_timing` | Deferred ACK: `waitMs`, `ackWriteMs`, `outcome` | Per-message |
| `timeout:fired` | Timeout events: `timeoutName`, `configuredMs`, `actualMs` | Per-timeout |
| `group:publish_debug` | GossipSub publish (sender): `encryptMs`, `signMs`, `topicPeers` | Per-publish |
| `group_message:received` | GossipSub receive (receiver): `decryptMs`, `messageId` | Per-message |
| `group:discovery` | Group peer discovery: register/discover/dial steps | Per-cycle |
| `media:upload_complete` | Upload finish: `totalBytes`, `totalMs`, `throughputBytesPerSec` | Per-upload |
| `idleTimeoutReader` | Media stall detection: `ErrStallTimeout` after 10s idle (`MediaIdleTimeout`) | Behavioral guard (not an event) |
| `EventDispatcher` timestamps | Stamps each event at `time.Now()` | Per-event |
| `EventDispatcher` counters | Tracks delivered/coalesced/dropped counts | Aggregate |
| `TimeoutProfile` | Go struct (`config.go`) that bundles per-operation timeout durations; not an emitted event — see `InteractiveTimeouts()` / `BackgroundTimeouts()` in §3 | Config (struct, not event) |

### Measured Baseline (Simulator)

Every path listed above has production events emitting timing data. See `03b-benchmark-test-inventory.md` for the full baseline table (collected 2026-04-15). Key numbers:

| Metric | Value | Source |
|---|---|---|
| 1:1 cold send | p50≈100ms | A-Sim |
| 1:1 warm send | p50=1ms, p95=2ms | A-Sim |
| Connection reuse hit rate | 90% | J-Sim |
| Time-to-Online Badge | p50≈170ms, p95≈180ms | M-Sim |
| Relay recovery | p50≈9.1s | C-Sim |
| Inbox store (warm) | ~107ms | D-Sim |
| Bridge crossing | p99=0ms (n=1000) | F-Sim |
| ML-KEM keygen | p95=3ms | G-Sim |
| ML-KEM encrypt 100KB | 2ms | G-Sim |
| Event queue idle | p50=49ms | I-Sim |
| Voice total | 269ms (56% upload) | K-Sim |
| Direct ACK round-trip | p50=1ms, p95=41ms | L-Sim |
| Group publish (scripted sim) | send p50=5ms, p95=8ms; receiver e2e p50=44ms, p95=48ms | GP-Sim |
| Group publish e2e (two-sim smoke) | send=32ms, e2e=515ms | G1 two-sim smoke |
| Media 5MB upload | 2677ms (1958490 bytes/sec) | E-Sim |
| Profile upload | 221ms, 3 progress events | E-Sim |
| Media 5MB transfer e2e | 2495ms (2052 KB/s) | S12 two-sim |
| Notification tap → message visible | cold=313ms, warm=85ms | N-Sim |
| Background resume → online badge (healthy) | 100ms | BR-Sim |
| Background resume → online badge (degraded) | 9166ms | BR-Sim |

---

## 2. Critical Path Timing Analysis

### Path A: 1:1 Message Send (the race strategy)

**File:** `lib/features/conversation/application/send_chat_message_use_case.dart`

```
Total worst case: ~18 s (but typically <2 s with connection reuse)
Measured (03b): cold p50=95-101ms (sim), 227ms send / 806ms e2e (two-sim S1)
               warm p50=1ms p95=2ms (sim), 4-23ms send in S8
               inbox fallback: 91-98ms (sim), 2058ms send (two-sim S3)

Step 1: Validate + build payload ...................... ~0 ms
Step 2: Encrypt (if ML-KEM key) ...................... ~5-50 ms  (MethodChannel to Go)
        Measured: encrypt 100B=1ms, 100KB=2ms (G-Sim)
Step 3: Persist wireEnvelope to DB ................... ~1-5 ms   (SQLite write, only if messageId != null — edits/retries)
Step 4: Check connection reuse ....................... ~0 ms     (local state read)
        Measured: 90% reuse hit rate (J-Sim), cold=67ms vs warm=1ms
  |
  +-- IF already connected:
  |     sendMessageWithReply(timeout: 2s) ........... 0-2 s
  |     DONE (fast path)
  |
  +-- IF not connected: RACE two futures:
        |
        +-- Local WiFi (if local peer):
        |     timeout: 1.5 s ........................ 0-1.5 s
        |     Measured: 11ms via reuse on simulator (S14)
        |
        +-- Direct P2P:
        |     discover (2s) → dial (2s) → send (2s)
        |     BUT outer timeout: 2 s ............... 0-2 s
        |     (discover alone can consume entire budget)
        |     Measured: disc=62ms dial=19ms send=1ms (R-Sim-2)
        |
        Race winner: ................................... 0-2 s
        |
        +-- IF both fail AND relay-probe eligible:
              probeRelay (5s timeout) ............... 0-5 s
              dial (2s) ............................. 0-2 s
              send attempt 1 (2s) ................... 0-2 s
              backoff (250ms) ....................... 250 ms
              send attempt 2 (2s) ................... 0-2 s
              Relay probe total: .................... 0-11.25 s
              Measured: S15 rerun completed in 572ms on the direct path (`probe=false`);
                        the relay-probe branch was not exercised in the 2026-04-15 two-sim run
              |
              +-- IF still fails:
                    inbox:store (3s interactive) ..... 0-3 s
                    Measured: 106-108ms warm (D-Sim reruns)
```

**Key bottleneck:** The 2s `interactiveDirectBudget` is a wall-clock `.timeout()` on the entire `_tryDirectSend` Future, but internally each step (discover, dial, send) receives `budgetMs = interactiveDirectBudget.inMilliseconds` as its own independent timeout — they don't subtract elapsed time. This means each step *could* individually run for 2s, but the outer `.timeout()` kills the whole chain after 2s wall-clock regardless. In practice, if discover takes 2s, the outer timeout fires and dial/send get 0ms. The design relies on **connection reuse** to skip this on subsequent sends to the same peer.

**Constants (Dart side):**

| Constant | Value | Purpose |
|---|---|---|
| `interactiveLocalBudget` | 1.5 s | Local WiFi send cap |
| `interactiveDirectBudget` | 2 s | Direct P2P race cap |
| `relayProbeSendAttempts` | 2 | Retry count after probe |
| `relayProbeRetryBackoff` | 250 ms | Between probe retries |

### Path B: Node Startup to First Usable Connection

**Go file:** `go-mknoon/node/node.go`, `Start()` at line 192

```
Typical: 2-5 s to fully discoverable
Worst case: ~25 s
Measured (03b): Time-to-Online Badge p50=171ms p95=178ms (M-Sim, n=5)
               Cold-start harness: p50=169ms p95=170ms (B-Sim, n=5)
               Source distribution: relay_state_push wins 5/5 cold starts (M-Sim-3)
               Recovery badge: 9600ms; relay recovery p50=9136ms (C-Sim)
               Hot restart: captured (M-Sim-Hot)

Phase 1 — Synchronous (blocks Start() return):
  Key decode + libp2p.New() ....................... ~100-500 ms
  initPubSub() ................................... ~10 ms
  Set stream handler + event bus .................. ~1 ms
  Start() returns to Dart ........................ total: <500 ms

Phase 2 — Concurrent goroutines (after Start returns):
  warmRelayConnection (DialTimeout: 15s) ......... 200-800 ms typical
    → relayReady channel closes .................. signals discovery loops
    Measured: relay:warm_timing emitted per relay (B-Sim)
  AutoRelay identify + reservation ............... 1-3 s after warm
    → circuit address appears .................... signals rendezvous
    Measured: circuit_address:timing with pollCount (B-Sim)
  autoRegisterPersonalNamespaceForStart:
    waitForCircuitAddress (polls 200ms, max 10s) . 0-10 s
    RendezvousRegister (DiscoverTimeout: 10s) .... 50-200 ms typical
    → peer is discoverable ....................... total: 2-5 s

Phase 3 — Dart warm background (unawaited):
  2 s delayed relay health check ................. 2 s
  drainOfflineInbox (warmTaskTimeout: 5s) ........ 0-5 s
  mDNS start (warmTaskTimeout: 5s) ............... 0-5 s

Phase 4 — Dart background resume:
  markResumeStarted() ............................ records timestamp
  handleAppResumed() ............................ bridge health + P2P health check
  If relay stayed healthy:
    checkResumeAlreadyOnline() .................. emits background_resume_already_online, totalMs ≈ 100 ms on rerun
  If relay degraded during background:
    _emitState() on recovery transition ......... emits background_resume, totalMs = resume-to-green
```

**Observation:** `Start()` returns to Dart in <500ms but the node isn't usable yet. The relay connection + circuit address + rendezvous registration happen concurrently in background goroutines. The `TIME_TO_ONLINE_BADGE` event tracks user-perceived startup latency — the `relay_state_push` source wins the race in all measured cold starts (5/5), suggesting the EventChannel push path is the dominant delivery mechanism. The 2s fast circuit check may be unnecessary. Phase 4 adds background resume timing: `background_resume_already_online` when the relay stayed healthy (measured at `100-103ms` on the latest rerun), `background_resume` when recovery was needed (measured at `9166ms` resume-to-green).

### Path C: Relay Reconnect / Recovery

**Go files:** `go-mknoon/node/node.go` (refresh / reconnect execution), `go-mknoon/node/relay_session.go` (state + coalescing)

```
In-place recovery (first attempt):
  warmRelayConnection (DialTimeout: 15s) ......... 0-15 s
  waitForCircuitAddress (10s) ..................... 0-10 s
  Total: .......................................... 0-25 s
  Measured (03b): p50=9136ms p95=9320ms (C-Sim, n=3)
                 detection=504ms, total outage ~9663ms

Full restart (if in-place fails):
  Stop() .......................................... ~1 s
  Start(restartCfg) ............................... <500 ms
  waitForCircuitAddress (10s) ..................... 0-10 s
  Total: .......................................... 0-36 s
  Measured: both-sides restart=513ms/515ms (X1)

Watchdog trigger:
  5 consecutive refresh failures on all relays
  → needsGroupRecovery = true
  → Dart health check (every 30s) calls relay:reconnect
  → Recovery starts

Recovery coalescing:
  RecoveryWaitTimeout = 30s
  → If recovery goroutine stalls, coalescers unblock after 30s
  → ClearStalledRecovery() clears the gate for next attempt
```

### Path D: Group Peer Discovery Loop

**Go file:** `go-mknoon/node/pubsub.go`, line 1553
**Measured (03b):** Group discovery 5255ms (5s settle + ~255ms actual discovery, G6). The repaired scripted group benchmark now measures sender publish at `p50=5ms, p95=8ms` with receiver e2e `p50=44ms, p95=48ms` (`GP-Sim`), while the two-simulator `G1` smoke rerun measured `send=32ms, e2e=515ms`.

```
Phase 1 — Immediate direct dial ................... 0-2 s per peer
Phase 2 — Wait for relayReady ..................... 0-∞ (no timer, but ctx.Done cancels on group leave/node stop)
Phase 3 — First discovery cycle:
  dial known members (PeerDialTimeout: 2s each) .. 0-2 s × N
  discover via rendezvous (current call site falls back to DiscoverTimeout: 10s)
Phase 4 — Wait for circuit address (10s) .......... 0-10 s
Phase 5 — Initial jitter .......................... 0-3 s
Phase 6 — Initial registration cycle:
  RendezvousRegister (DiscoverTimeout: 10s) ...... 0-10 s
  discover + dial peers .......................... 0-10 s
Phase 7 — Periodic loop:
  Normal interval: 30s ± 25% (22.5-37.5s)
  Warm interval: 3s (when partially connected)
  Warm retries: 3 consecutive before failure
  Backoff: 3s → 6s → 12s → 24s → 48s → 60s cap
  Resets on new peer connection
```

**Concurrency limit:** 5 simultaneous discovery goroutines across all groups.

**Pre-publish settle:** When publishing, if topic has fewer peers than expected:
- 0 peers: wait up to 150ms (poll every 25ms)
- Some peers: wait up to 500ms (poll every 25ms)

### Path E: Inbox Store/Retrieve Round-Trip

**Go file:** `go-mknoon/node/inbox.go`

```
h.Connect (if needed, DialTimeout: 15s) ........... 0-15 s (usually 0ms if warm)
h.NewStream (InboxProtocol) ....................... ~10 ms
writeFrame (4-byte BE + JSON, max 128 KB) ......... ~1-10 ms
readFrame (response) .............................. ~10-100 ms (network RTT)
Total with warm connection: ....................... ~20-120 ms
Total timeout: InboxTimeout = 15 s
Measured (03b): store 106-108ms warm on the iPhone 17 Pro reruns (D-Sim)
              Per-step: inbox:store_timing with connectMs, streamOpenMs, writeMs, readMs
```

**Retrieve:** Returns up to 50 messages per page. Single request/response, no streaming.

### Path F: Media Upload/Download

**Go file:** `go-mknoon/node/media.go`

```
Upload:
  openMediaStream (MediaTimeout: 5 min) ........... ~10-50 ms
  sendMediaRequest (JSON header + "READY") ........ ~20-100 ms
  io.Copy (raw byte stream, no chunks) ............ depends on file size
    Idle timeout: 10s (MediaIdleTimeout) — stall → ErrStallTimeout → retry
  Progress: every 256 KB or 250 ms ................ UI callback (MediaUpload + ProfileUpload)
  readFrame (confirmation) ........................ ~10-50 ms
  Total timeout: 5 min absolute (outer guard)
  Measured (03b): E-Sim low-level upload measured 1MB=351ms (2987396 bytes/sec),
                  5MB=2677ms (1958490 bytes/sec), stream-open=0ms on warmed relay;
                  S12 two-sim end-to-end transfer measured 1MB=490ms (2090 KB/s),
                  5MB=2495ms (2052 KB/s)

Download:
  openMediaStream ................................. ~10-50 ms
  sendMediaRequest (request + JSON response) ...... ~20-100 ms
  io.CopyN (exact bytes, no progress events) ...... depends on file size
  Total timeout: 5 min absolute
```


### Path G: Rendezvous Register/Discover

**Go file:** `go-mknoon/node/rendezvous.go`

```
Register:
  h.NewStream (RendezvousProtocol) ................ ~10 ms (warm connection)
  varint-prefixed write (protobuf) ................ ~1-5 ms
  varint-prefixed read (response) ................. ~10-100 ms (network RTT)
  Total: .......................................... ~20-120 ms
  Timeout: DiscoverTimeout = 10 s

Discover:
  Same structure as register ...................... ~20-120 ms
  Interactive timeout: 2 s (when called from send path)
  Background timeout: 10 s (when called from discovery loop)
```

**No caching.** Every discover is a live network roundtrip. Personal registration TTL: 2h, refreshed every 30 min.

**Multi-relay:** Relays are tried sequentially, not in parallel. Each failure adds a full timeout before trying the next relay.

### Path H: Deferred Direct ACK

**Go file:** `go-mknoon/node/node.go`, `handleIncomingMessage`
**Go config:** `go-mknoon/node/config.go`, `DirectConfirmTimeout = 2 s`
**Measured (03b):** p50=1ms, p95=41ms (L-Sim, n=10). 10/10 ACKs received under load (S13).

```
Incoming message arrives on stream:
  Parse frame + identify type ........................ ~1 ms
  IF shouldDeferDirectAck (chat_message + flag):
    Generate confirmNonce (UUID) ..................... ~0 ms
    Emit "message:received" with confirmNonce ........ ~0 ms (async to Dart)
    Wait for Dart to call confirmDirectAck ........... 0-2 s (DirectConfirmTimeout)
    |
    +-- IF Dart confirms in time:
    |     writeFrame({"ack":true}) ................... ~1-10 ms
    |     Stream closed — sender gets ACK
    |
    +-- IF timeout expires:
          Log warning, return without ACK
          Sender sees send failure / timeout
  ELSE (immediate ACK path):
    writeFrame({"ack":true}) immediately ............. ~1-10 ms
```

**Key detail:** The current `DirectConfirmTimeout` (2s) happens to match Dart's current `interactiveDirectBudget` (2s), so a slow Flutter confirm can collide with the sender's foreground timeout in practice. However, the Go-side invariant enforced in tests is `DirectConfirmTimeout < InteractiveSendTimeout` (3s), not "must equal / stay within Dart's 2s budget."

### Path I: Voice Message Send

**File:** `lib/features/conversation/application/send_voice_message_use_case.dart`

```
Total: media upload time + text send time

Step 1: Validate recording (size 0-100 MB, file exists) ... ~0 ms
Step 2: Upload media via bridge (callP2PMediaUpload) ....... 0-5 min (MediaTimeout)
  Progress events: every 256 KB or 250 ms
Step 3: Send chat message with MediaAttachment ............. (same as Path A)
  Includes waveform + durationMs metadata
```

**Measured (03b):** Total=269ms, upload=151ms (56% share), transport=117ms (K-Sim). `VOICE_SEND_TIMING` now includes `uploadMs` and `sendMs` sub-steps.

### Path J: Delete-for-Everyone

**File:** `lib/features/conversation/application/delete_message_use_case.dart`

```
Total: same timing profile as Path A (1:1 message send)

Step 1: Validate (outgoing, not already deleted) ........... ~0 ms
Step 2: Build MessageDeletionPayload ....................... ~0 ms
Step 3: Encrypt with ML-KEM (if available) ................. ~5-50 ms
Step 4: Create tombstone (status: 'sending') + persist ..... ~1-5 ms
Step 5: Send via race strategy (identical to Path A) ....... 0-18 s
  Connection reuse → local WiFi vs direct → relay probe → inbox
```

**Observation:** Delete-for-everyone follows the exact same transport path as a regular 1:1 send. The payload is a deletion tombstone instead of a chat message. Timing event: `CHAT_MSG_DELETE_FOR_EVERYONE_TIMING`.

### Path K: Local WiFi Media Transfer

**Files:** `lib/core/local_discovery/local_media_sender.dart`, `lib/core/local_discovery/local_media_server.dart`

```
Sender side:
  Compute SHA-256 of file (streaming) .................. ~5-100 ms
  Generate token + nonce ............................... ~0 ms
  Send media_offer via WebSocket ....................... ~1-10 ms
  Wait for media_offer_accepted (_offerTimeout: 5s) .... 0-5 s
  HTTP PUT file to receiver /media/<id> ................ depends on file size
  Wait for media_uploaded (_uploadedTimeout: 30s) ...... 0-30 s
  Total worst case: ................................... ~35 s + transfer time

Receiver side:
  Accept media_offer, validate MIME + size ............. ~0 ms
  Receive HTTP PUT body → temp file .................... depends on file size
    Incremental SHA-256 verification during receive
  Verify size + hash match ............................. ~0 ms
  Emit MediaUploadResult (LocalMediaReady) ............. ~0 ms
  Move temp → persistent media/<peerId>/<id>.<ext> ..... ~1-10 ms

Cleanup: expired transfers purged every 1 min (pendingTtl: 5 min)
```

**Timing:** `LOCAL_MEDIA_SEND_TIMING` emits Stopwatch-based `elapsedMs`, `outcome`, `mediaId` for end-to-end transfer measurement. **Measured (03b):** S14 shows `isLocal=false` on simulators (no real LAN), send=11ms via connection reuse path.

### Path L: Notification Tap to Message Visible

**Files:** `lib/core/notifications/flutter_notification_service.dart`, `lib/core/utils/notification_tap_timing.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`

```
User taps notification (local or remote):
  _onNotificationTap / _routeRemoteNotificationOpen
    Record _notificationTappedAt = DateTime.now() ......... ~0 ms
    clearDeliveredNotifications ........................... ~1-5 ms
    NotificationRouteTarget.fromPayload .................. ~0 ms
    _handleNotificationRouteTarget → Navigator.push ....... ~10-50 ms
    ConversationWired.initState → load messages from DB ... ~10-100 ms
    First frame with messages rendered:
      addPostFrameCallback → emitNotificationTapTiming() .. ~1 ms
      Emits: NOTIFICATION_TAP_TO_MESSAGE_TIMING
        elapsedMs = now - _notificationTappedAt
        routeKind = conversation | group
        messageId = first 8 chars

Total: ~20-150 ms (warm) to ~500ms+ (cold, if app was killed)
Measured: single-node benchmark rerun `cold=313ms`, `warm=85ms` (`N-Sim`); the Alice/Bob two-simulator notification smoke harness remains unimplemented in the repo
```

**Observation:** This is a Dart-only path — no bridge calls or network operations. The dominant cost is DB query + widget build. Cold start (app killed) adds the full Phase 1-2 startup before the conversation screen can load.

---

## 3. Complete Timeout Reference

### Go Constants (`go-mknoon/node/config.go`)

| Constant | Value | Used By |
|---|---|---|
| `DialTimeout` | 15 s | Relay warm connection, relay session refresh |
| `PeerDialTimeout` | 2 s | `DialPeer`, `DialPeerWithTimeout` default |
| `RelayProbeTimeout` | 5 s | `DialPeerViaRelay` |
| `SendTimeout` | 15 s | `SendMessageWithTransport` default |
| `DiscoverTimeout` | 10 s | Rendezvous register/discover default |
| `InboxTimeout` | 15 s | All inbox operations default |
| `MediaTimeout` | 5 min | All media operations |
| `PubSubTimeout` | 30 s | `topic.Publish` |
| `StreamWriteDeadline` | 10 s | Defined in config/tests; current runtime deadlines are mostly per-call via `setStreamDeadline(timeout)` |
| `StreamReadDeadline` | 10 s | Defined in config/tests; current runtime reads mostly use per-call deadlines or `InboundReadDeadline` |
| `InboundReadDeadline` | 15 s | `handleIncomingMessage` |
| `DirectConfirmTimeout` | 2 s | Deferred direct ACK wait |
| `RecoveryWaitTimeout` | 30 s | Recovery promise coalescer timeout (`relay_session.go`) |
| `MediaIdleTimeout` | 10 s | Media idle stall detection — no bytes for 10s → `ErrStallTimeout` (`media.go`) |
| `MaxFrameLen` | 128 KB | Frame size cap (chat + inbox) |

### Go Interactive Timeout Profile

These constants are defined in Go config/tests, but the current Dart-driven 1:1 send flow passes explicit `timeoutMs` values into discover/dial/send instead of relying on these defaults.

| Constant | Value | Used By |
|---|---|---|
| `InteractiveDialTimeout` | 4 s | Defined in Go profile; current Dart 1:1 send path passes explicit dial timeout values |
| `InteractiveSendTimeout` | 3 s | Defined in Go profile; also the Go-side bound checked by `DirectConfirmTimeout` tests |
| `InteractiveDiscoverTimeout` | 2 s | Defined in Go profile; current Dart 1:1 send path passes explicit discover timeout values |
| `InteractiveInboxTimeout` | 3 s | Wired into the 1:1 inbox-store fallback via `interactiveInboxBudget`; also used by retrieve/ack call sites that pass `timeoutMs` |

### Go Background Timeout Profile

`BackgroundDiscoverTimeout` exists in the Go timeout profile, but the current group discovery code reaches rendezvous via `RendezvousDiscover()`, which falls back to `DiscoverTimeout = 10 s`. The runtime value matches today, but it is not currently plumbed from this constant.

| Constant | Value | Used By |
|---|---|---|
| `BackgroundDiscoverTimeout` | 10 s | Defined in Go profile; current group discovery rendezvous calls currently inherit `DiscoverTimeout = 10 s` |

### Go Group Discovery Constants

| Constant | Value | Purpose |
|---|---|---|
| `GroupDiscoveryInterval` | 30 s | Normal periodic cadence |
| `GroupDiscoveryWarmInterval` | 3 s | Fast cadence when partially connected |
| `GroupDiscoveryWarmRetries` | 3 | Warm retry budget before backoff |
| `MaxGroupDiscoveryBackoff` | 1 min | Backoff cap |
| `GroupDiscoveryConcurrency` | 5 | Max concurrent discovery goroutines |
| `GroupDiscoveryJitterFactor` | 4 | ±25% jitter on normal interval |
| `GroupRecoveryInitialJitter` | 3 s | Stagger on join |
| `GroupPublishZeroPeerSettleWait` | 150 ms | Pre-publish wait (0 peers) |
| `GroupPublishPartialPeerSettleWait` | 500 ms | Pre-publish wait (partial peers) |
| `GroupPublishPeerPoll` | 25 ms | Peer count poll tick |
| Peerstore address TTL (inline) | 1 h | Discovered group peer addresses cached in peerstore before requiring re-discovery (`pubsub.go`) |

### Go Relay/Rendezvous Constants

| Constant | Value | Purpose |
|---|---|---|
| `PersonalRendezvousRegistrationTTL` | 2 h | Registration lifetime on relay |
| `DefaultPersonalRendezvousRefreshEvery` | 30 min | Re-register interval (TTL/4) |
| `KeyRotationGracePeriod` | 30 s | Old group key accepted after rotation |
| `WatchdogMaxConsecutiveFailures` | 5 | Failures before watchdog restart (defined in `relay_session.go`, not config.go) |
| AutoRelay `WithBackoff` | 5 s | AutoRelay retry on failure |
| AutoRelay `WithMinInterval` | 5 s | AutoRelay peer source re-query |
| `waitForCircuitAddress` poll | 200 ms | Circuit address detection slack |
| `connmgr.WithGracePeriod` | 1 min | Connection manager hold time before pruning (inline in `node.go`) |

### Go Media Constants

| Constant | Value | Purpose |
|---|---|---|
| `mediaUploadProgressEmitChunkBytes` | 256 KB | Progress event trigger (bytes) |
| `mediaUploadProgressEmitInterval` | 250 ms | Progress event trigger (time) |

### Dart Constants

| Constant | Value | File | Purpose |
|---|---|---|---|
| `interactiveLocalBudget` | 1.5 s | send_chat_message_use_case.dart | Local WiFi send cap |
| `interactiveDirectBudget` | 2 s | send_chat_message_use_case.dart | Direct P2P race cap |
| `relayProbeSendAttempts` | 2 | send_chat_message_use_case.dart | Relay probe retry count |
| `relayProbeRetryBackoff` | 250 ms | send_chat_message_use_case.dart | Between relay probe sends |
| `healthCheckInterval` | 30 s | p2p_service_impl.dart | Dart-side health check timer |
| `warmTaskTimeout` | 5 s | p2p_service_impl.dart | Inbox drain + mDNS start cap |
| `defaultRetryDebounce` | 5 s | pending_message_retrier.dart | Debounce after online transition before retry sweep |
| `defaultPeriodicRetryInterval` | 5 min | pending_message_retrier.dart | Periodic retry sweep interval |
| `defaultGroupContinuitySweepInterval` | 30 s | pending_message_retrier.dart | Group continuity sweep interval |
| `cooldown` (KeyExchangeRetryCoordinator) | 10 s | key_exchange_retry_coordinator.dart | Cooldown between key exchange retry attempts |
| `foregroundInboxTimeout` | 3 s | p2p_service_impl.dart | Foreground budget for first inbox page during startup/resume |
| Fast relay check delay | 2 s | p2p_service_impl.dart | `Future.delayed` before early relay health check after warm |
| `callGroupPublish` default timeout | 10 s | bridge_group_helpers.dart | Dart-side timeout for `group:publish` bridge call (triggers BRIDGE_TIMEOUT) |
| `callGroupInboxStore` default timeout | 10 s | bridge_group_helpers.dart | Dart-side timeout for `group:inboxStore` bridge call |
| All other `callGroup*` helpers | 10 s | bridge_group_helpers.dart | `callGroupPublishReaction`, `callGroupUpdateConfig`, `callGroupGenerateNextKey`, `callGroupRotateKey`, `callGroupUpdateKey`, `callGroupAcknowledgeRecovery`, `callGroupInboxRetrieve`, `callGroupInboxRetrieveWithCursor`, `callGroupKeygen`, `callGroupEncrypt`, `callGroupDecrypt` |
| `callGroupCreate` default timeout | 30 s | bridge_group_helpers.dart | Dart-side timeout for `group:create` bridge call |
| `callGroupJoin` / `callGroupJoinWithConfig` default timeout | 30 s | bridge_group_helpers.dart | Dart-side timeout for `group:join` bridge call |
| `callGroupLeave` default timeout | 30 s | bridge_group_helpers.dart | Dart-side timeout for `group:leave` bridge call |
| `maxInboxPages` | 10 | p2p_service_impl.dart | Max pages drained per inbox pass |
| `maxRecoverableInboxReplayEntries` | 500 | p2p_service_impl.dart | Replay window bound for stuck message recovery |
| `callP2PMediaUpload` / `callP2PMediaDownload` timeout | 5 min | p2p_bridge_client.dart | Dart-layer `.timeout()` on media upload/download bridge calls (independent from Go's MediaTimeout) |
| `callP2PProfileUpload` / `callP2PProfileDownload` timeout | 5 min | p2p_bridge_client.dart | Dart-layer `.timeout()` on profile upload/download bridge calls |
| `callP2PMediaDelete` / `callP2PMediaList` timeout | 15 s | p2p_bridge_client.dart | Dart-layer `.timeout()` on media delete/list bridge calls |
| `callP2PInboxStore` | 3 s (interactive) / 15 s (default) | p2p_bridge_client.dart | Dart-side `.timeout(timeoutMs ?? 15000)` — interactive send path passes `3000` via `interactiveInboxBudget`; Go `InboxStore` respects `timeoutMs` when > 0 |
| `callP2PRelayProbe` | 5 s | p2p_bridge_client.dart | Dart-side `.timeout(5s)` — matches Go's `RelayProbeTimeout` |
| Bridge health check timeout | 5 s | go_bridge_client.dart | `.timeout()` on bridge `checkHealth()` call |

### Dart Local Discovery Constants

| Constant | Value | File | Purpose |
|---|---|---|---|
| `_ackTimeout` | 5 s | local_ws_server.dart | WebSocket ACK wait timeout |
| `idleTimeout` | 60 s | local_ws_server.dart | Idle connection timeout before disconnect |
| Connect timeout (inline) | 5 s | local_ws_server.dart | WebSocket connect timeout |
| `_offerTimeout` | 5 s | local_media_sender.dart | Wait for `media_offer_accepted` |
| `_uploadedTimeout` | 30 s | local_media_sender.dart | Wait for `media_uploaded` confirmation |
| `pendingTtl` | 5 min | local_media_server.dart | Pending transfer expiry |
| Cleanup interval (inline) | 1 min | local_media_server.dart | Periodic cleanup of expired transfers |

### Dart Post Delivery Constants

| Constant | Value | File | Purpose |
|---|---|---|---|
| `_interactivePostBudget` | 4 s | post_delivery_runner.dart | Post send path timeout budget (analogous to `interactiveDirectBudget` for 1:1) |
| `interactivePostPinBudget` | 4 s | post_pin_delivery_support.dart | Post pin delivery timeout budget |
| `interactivePostFollowOnBudget` | 4 s | post_follow_on_delivery.dart | Post follow-on delivery timeout budget |
| `_postPresenceInteractiveBudget` | 4 s | publish_post_presence_update_use_case.dart | Post presence update timeout budget |

### Dart Group Key Rotation Constants

| Constant | Value | File | Purpose |
|---|---|---|---|
| `perRecipientTimeout` | 5 s | rotate_and_distribute_group_key_use_case.dart | Timeout per recipient during key distribution |
| `distributionTimeout` | 15 s | rotate_and_distribute_group_key_use_case.dart | Overall timeout for key distribution batch |

### Dart Recovery Constants

| Constant | Value | File | Purpose |
|---|---|---|---|
| `kStuckSendingThreshold` | 30 s | recover_stuck_sending_messages_use_case.dart | Age threshold for messages to be considered "stuck" and eligible for recovery |

### Dart Other Constants

| Constant | Value | File | Purpose |
|---|---|---|---|
| Key exchange debounce | 5 s | key_exchange_retrier.dart | Debounce timer before key exchange retry |
| `_maxDuration` | 5 min | record_audio_recorder_service.dart | Maximum voice recording duration |
| `_tickInterval` | 100 ms | record_audio_recorder_service.dart | Amplitude sampling interval during recording |
| Recorder cancel timeout (inline) | 2 s | record_audio_recorder_service.dart | `.timeout()` on recorder cancel/cleanup |

---

## 4. Architectural Observations

### 1:1 Send Path Budget Starvation

The 2s `interactiveDirectBudget` is a wall-clock `.timeout()` on the `_tryDirectSend` Future, but internally each step (discover, dial, send) receives `budgetMs = interactiveDirectBudget.inMilliseconds` as its own independent timeout parameter — they don't subtract elapsed time from the budget. The outer `.timeout()` kills the chain after 2s wall-clock regardless, so if discover takes its full 2s, dial and send get 0ms. The race strategy depends entirely on **connection reuse** for responsive second-send performance. First-send to a new peer will almost always fall through to relay probe or inbox, adding 5-15s. **Measured:** Budget starvation scenario = 101ms on simulator (R-Sim-5), but real-world discover latency varies.

### Group Discovery Blocks on Relay (bounded)

`groupPeerDiscoveryLoop` waits on `relayReady` with no timer-based timeout. The `select` has a `ctx.Done()` escape — the context cancels on group leave or node stop, so this is **not truly unbounded**. However, if relay never connects and the group is never left, discovery for that group is blocked for the duration of the group membership. No fallback discovery path, no event emitted to surface the stall. The `dialKnownGroupMembersDirectOnly` call before the wait provides a partial mitigation for same-network peers.

### Sequential Multi-Relay Failover

Rendezvous register/discover tries relays sequentially. Each failed relay adds a full `DiscoverTimeout = 10s` before trying the next. Two relays with the first down = 10s before the second is even tried.

### Inbox Store Fallback Uses Interactive 3s Timeout

The 1:1 inbox-store fallback now passes `timeoutMs: 3000` (via `interactiveInboxBudget`) to both the Dart `.timeout()` and the Go `InboxStore` method. This aligns the interactive send path with `InteractiveInboxTimeout = 3s`, making the timeout ceiling predictable. **Measured:** Inbox store = 106-108ms warm on the 2026-04-15 reruns (D-Sim), so the 3s budget is sufficient with wide margin. Non-interactive callers (e.g., test CLI commands) use the default `InboxTimeout = 15s`.
