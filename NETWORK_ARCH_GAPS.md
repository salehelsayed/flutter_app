# Network Architecture — Identified Gaps

## Role 1: go-libp2p-resilience-implementer

### GAP-R1: warmRelayConnection has no retry on failure
- **File:** `go-mknoon/node/node.go:376-390`
- **Current:** Single dial attempt with 15s timeout. If it fails, relay is not connected. No retry.
- **Impact:** App starts without relay = no P2P connectivity until health check triggers reconnect (30s later).
- **Fix:** Exponential backoff retry (5s → 10s → 20s → 40s, max 60s) with jitter. Cap at 5 attempts before falling back to health-check-driven recovery.

### GAP-R2: Circuit address polling uses fixed 200ms interval
- **File:** `go-mknoon/node/node.go:638-658` (WaitForCircuitAddress)
- **Current:** Polls every 200ms for up to 10s. No backoff, no adaptation.
- **Impact:** Wastes CPU on mobile. No adaptive behavior when relay is slow.
- **Fix:** Exponential backoff polling (200ms → 400ms → 800ms → 1.6s). Return early on first address.

### GAP-R3: 30-second health check detection latency
- **File:** `lib/core/services/p2p_service_impl.dart:38` (healthCheckInterval: 30s)
- **Current:** App shows "online" for up to 30s after relay dies. No proactive detection.
- **Impact:** Users see phantom connectivity. Messages sent during gap are silently lost.
- **Fix:** Reduce to 15s. Add connection event listener (`EvtPeerConnectednessChanged`) for immediate relay-down detection. Emit degraded state to Flutter immediately.

### GAP-R4: ReconnectRelays is full stop/start
- **File:** `go-mknoon/node/node.go:392-447` (ReconnectRelays)
- **Current:** Calls full `Stop()` + `Start()`. Kills all in-flight streams, subscriptions, and GossipSub meshes.
- **Impact:** Messages in transit are lost. Group pubsub subscriptions must rejoin. Briefly shows as stopped.
- **Fix:** Implement soft reconnect: re-dial relay without tearing down libp2p host. Only full restart as last resort.

### GAP-R5: No structured error codes returned to Flutter for retry decisions
- **File:** `go-mknoon/bridge/bridge.go` (all command handlers)
- **Current:** Returns `{ "ok": false, "errorCode": "GROUP_ERROR", "errorMessage": "..." }`. Error codes are generic strings, not actionable.
- **Impact:** Dart can't distinguish "retry later" vs "permanent failure" vs "relay down". Blind retry loops.
- **Fix:** Define error code taxonomy: `RELAY_UNREACHABLE`, `PEER_OFFLINE`, `TIMEOUT`, `INVALID_INPUT`, `ENCRYPTION_FAILED`. Return `retryable: true/false` hint.

### GAP-R6: No jitter in retry/health-check timing
- **Files:** `p2p_service_impl.dart:38`, `node.go:172-179` (AutoRelay backoff)
- **Current:** Fixed intervals. All clients retry at the same time after relay bounce.
- **Impact:** Thundering herd — relay gets slammed by all clients reconnecting simultaneously.
- **Fix:** Add ±20% random jitter to all timers (health check, AutoRelay backoff, discovery interval).

### GAP-R7: `_hasEverBeenOnline` gates recovery logic
- **File:** `lib/core/services/p2p_service_impl.dart` (health check flow)
- **Current:** `relay:reconnect` only fires if `_hasEverBeenOnline == true`. First-time relay failure = no auto-recovery.
- **Impact:** New users who install during relay outage are stuck offline permanently until app restart.
- **Fix:** Remove the gate or add a separate "first connection attempt failed" recovery path with longer backoff.

### GAP-R8: PubSub timeout on publish with no peers
- **File:** `go-mknoon/node/pubsub.go:212` (topic.Publish)
- **Current:** 30s PubSubTimeout. If no peers in topic, publish blocks for 30s then fails.
- **Impact:** Sending a group message when peers are reconnecting hangs the UI for 30s.
- **Fix:** Check `topic.ListPeers()` before publish. If 0 peers, return immediately with `NO_PEERS` error. Let Dart show "waiting for connection" instead of hanging.

---

## Role 2: relay-shared-state-migration

### GAP-S1: All relay stores are in-memory only — data lost on restart
- **Files:** `go-relay-server/main.go:44-120`, `rendezvous.go:31-35`, `inbox.go:178-182`
- **Current:** `RendezvousStore`, `InboxStore`, `GroupInboxStore`, `PushService` are plain Go maps. Zero persistence.
- **Impact:** Relay restart (crash, deploy, EC2 reboot) loses ALL offline messages, push tokens, registrations, and group inbox.
- **Fix:** Add Redis or SQLite backing. Write-through on store, read-through on startup. Preserve existing in-memory interface for performance.

### GAP-S2: Offline inbox messages lost permanently on relay restart
- **File:** `go-relay-server/inbox.go` (InboxStore)
- **Current:** Messages stored in `map[string][]inboxMessage`. Max 7-day TTL, but purged entirely on process exit.
- **Impact:** User A sends while User B is offline. Relay restarts before B comes online. Message gone forever.
- **Fix:** Persist inbox to Redis (LPUSH/LRANGE with TTL). Atomic read-and-delete on drain.

### GAP-S3: Group inbox messages lost permanently on relay restart
- **File:** `go-relay-server/` (GroupInboxStore)
- **Current:** In-memory map. 500 messages/group, 7-day TTL. All purged on restart.
- **Impact:** Group members offline during relay restart lose all pending group messages.
- **Fix:** Persist to Redis sorted sets (score = timestamp). Same 7-day TTL via Redis EXPIRE.

### GAP-S4: Push tokens lost on relay restart
- **File:** `go-relay-server/inbox.go:33-36` (PushService)
- **Current:** `tokens sync.Map` (peerId → FCM token). Lost on restart.
- **Impact:** After relay restart, push notifications stop until each client re-registers (next health check or app resume).
- **Fix:** Persist to Redis hash (HSET push_tokens peerId token). Read on startup.

### GAP-S5: Rendezvous registrations lost on relay restart
- **File:** `go-relay-server/rendezvous.go:31-35`
- **Current:** In-memory map with 2-hour TTL. Lost on restart.
- **Impact:** Group peer discovery fails until all members re-register (up to 30s per member via discovery loop).
- **Fix:** Lowest priority — clients auto-re-register quickly. But Redis backing enables multi-relay clustering.

### GAP-S6: Media store index is in-memory
- **File:** `go-relay-server/media.go:41-48`
- **Current:** Blob files on disk (`/data/media/`), but the index (blobId → metadata) is in-memory.
- **Impact:** Relay restart = media files exist on disk but are unreachable (no index). 10-minute cleanup may delete them.
- **Fix:** Persist index to Redis or SQLite. Rebuild index from disk files on startup as fallback.

### GAP-S7: No relay clustering — single instance only
- **Current:** One EC2 instance at `13.60.15.36`. No load balancer, no failover.
- **Impact:** Single point of failure for the entire network.
- **Fix:** After GAP-S1 (shared state via Redis), deploy 2+ relay instances behind a load balancer. Shared Redis = consistent state. Requires GAP-S1 first.

### GAP-S8: No graceful shutdown — in-flight operations interrupted
- **File:** `go-relay-server/main.go`
- **Current:** No signal handling for SIGTERM/SIGINT. Process kill = immediate termination.
- **Impact:** In-flight inbox stores, media uploads, and pubsub operations are interrupted mid-write.
- **Fix:** Add signal handler with graceful drain period (5-10s). Stop accepting new connections, finish in-flight ops, then exit.

---

## Role 3: mobile-network-resilience-qa

### GAP-M1: No network connectivity monitoring
- **File:** `lib/core/services/p2p_service_impl.dart`, `pubspec.yaml`
- **Current:** No `connectivity_plus` or equivalent plugin. No WiFi/cellular/offline detection.
- **Impact:** App can't react proactively to network changes. Relies on 30s health check to detect drops.
- **Fix:** Add `connectivity_plus` package. Listen to connectivity changes. Trigger immediate health check on network change. Show "offline" banner instantly.

### GAP-M2: No WiFi ↔ cellular handoff handling
- **Current:** When user moves from WiFi to cellular (or vice versa), all TCP/WebSocket connections drop. App waits up to 30s for health check to detect.
- **Impact:** 30s+ message blackout on every network transition. Common on mobile.
- **Fix:** On network change event, immediately trigger `relay:reconnect` instead of waiting for health check. QUIC transport should handle migration better — verify it's being used as primary.

### GAP-M3: No offline banner or connection state UI
- **Current:** No visible indicator when P2P is disconnected. Messages silently fail.
- **Impact:** Users don't know they're offline. They type and send messages that never arrive.
- **Fix:** Expose `P2PService.connectionState` as a ValueListenable. Show a thin banner ("Reconnecting...") in FeedWired/ConversationWired when state is degraded.

### GAP-M4: App resume doesn't immediately check connectivity
- **File:** `lib/main.dart:952-963` (didChangeAppLifecycleState)
- **Current:** On resume, calls `handleAppResumed()` which triggers inbox drain but NOT immediate health check.
- **Impact:** App resumes from background with stale connection. User sends message that fails.
- **Fix:** On `AppLifecycleState.resumed`, immediately call `performImmediateHealthCheck()` before any other operation.

### GAP-M5: No chaos testing infrastructure
- **Current:** No network fault injection, no relay kill tests, no cellular simulation.
- **Impact:** Unknown failure modes in production. No confidence in recovery paths.
- **Fix:** Create test harness: (1) Kill relay mid-session, verify recovery. (2) Toggle airplane mode, verify reconnect. (3) Switch WiFi→cellular, verify handoff. (4) Start app with relay down, verify deferred startup. (5) Send messages during relay bounce, verify eventual delivery.

### GAP-M6: Cold start with relay down has no recovery path
- **File:** `lib/features/identity/presentation/startup_router.dart:370-408`
- **Current:** `_startP2PInBackground()` starts node, waits 10s for circuit addresses. If relay is down, node starts but has no circuits. Health check runs but `_hasEverBeenOnline` is false (see GAP-R7), so no reconnect.
- **Impact:** New user installs app during relay outage = permanently stuck offline until app restart.
- **Fix:** Add "initial connection retry" loop separate from health check. Retry relay connection with backoff even if `_hasEverBeenOnline` is false.

### GAP-M7: mDNS local discovery only restarts on app resume
- **File:** `lib/main.dart` (app lifecycle handler)
- **Current:** mDNS advertising restarts on `AppLifecycleState.resumed` but not on network change.
- **Impact:** If both users are on the same WiFi, mDNS discovery doesn't re-trigger after WiFi reconnect.
- **Fix:** Restart mDNS on network connectivity change events (WiFi connected/disconnected).

### GAP-M8: No background keepalive strategy
- **Current:** When app goes to background on iOS, connections are dropped after ~30s. On Android, doze mode kills background tasks.
- **Impact:** Users who switch away from app lose connectivity. Push notifications are the only fallback.
- **Fix:** On iOS, use background fetch or silent push to periodically drain inbox. On Android, use WorkManager for periodic sync. Accept that real-time P2P is foreground-only; optimize for fast reconnect on resume.

### GAP-M9: Inbox drain happens on every health check regardless
- **File:** `lib/core/services/p2p_service_impl.dart:665`
- **Current:** Every 30s health check triggers inbox drain — even when there are no new messages.
- **Impact:** Unnecessary network round-trips. Battery drain on mobile.
- **Fix:** Track last drain timestamp. Only drain if (a) push notification received since last drain, or (b) >5 minutes since last drain, or (c) app just resumed.

---

## Priority Matrix

### P0 — Fix before any scale (blocks production)

| Gap | Role | Why |
|-----|------|-----|
| GAP-S1 | relay-shared-state | Relay restart = total data loss |
| GAP-S2 | relay-shared-state | Offline messages permanently lost |
| GAP-S7 | relay-shared-state | Single point of failure |
| GAP-R1 | go-resilience | App starts without relay = dead |
| GAP-M1 | mobile-qa | Can't detect network state changes |

### P1 — Fix before 1K users

| Gap | Role | Why |
|-----|------|-----|
| GAP-S3 | relay-shared-state | Group offline messages lost |
| GAP-S4 | relay-shared-state | Push tokens lost on restart |
| GAP-R3 | go-resilience | 30s ghost online state |
| GAP-R4 | go-resilience | Full stop/start kills in-flight ops |
| GAP-R6 | go-resilience | Thundering herd on relay bounce |
| GAP-M2 | mobile-qa | WiFi↔cellular handoff blackout |
| GAP-M3 | mobile-qa | No offline indicator |
| GAP-M4 | mobile-qa | Resume doesn't check connectivity |
| GAP-M6 | mobile-qa | Cold start with relay down = stuck |

### P2 — Fix before 10K users

| Gap | Role | Why |
|-----|------|-----|
| GAP-R2 | go-resilience | Inefficient polling |
| GAP-R5 | go-resilience | Generic error codes |
| GAP-R7 | go-resilience | First-time failure = no recovery |
| GAP-R8 | go-resilience | 30s hang on empty topic publish |
| GAP-S5 | relay-shared-state | Rendezvous persistence |
| GAP-S6 | relay-shared-state | Media index persistence |
| GAP-S8 | relay-shared-state | Graceful shutdown |
| GAP-M5 | mobile-qa | Chaos testing |
| GAP-M7 | mobile-qa | mDNS on network change |
| GAP-M8 | mobile-qa | Background keepalive |
| GAP-M9 | mobile-qa | Unnecessary inbox drains |

---

## Implementation Dependencies

```
GAP-S1 (Redis backing)
    │
    ├── GAP-S2, S3, S4, S5, S6 (all depend on persistence layer)
    │
    └── GAP-S7 (relay clustering requires shared state)

GAP-R1 (retry/backoff)
    │
    └── GAP-R2, R6 (all use same backoff infrastructure)

GAP-M1 (connectivity monitoring)
    │
    ├── GAP-M2 (WiFi/cellular handoff)
    ├── GAP-M4 (resume check)
    └── GAP-M7 (mDNS restart)

GAP-R3 (faster detection) + GAP-M3 (UI banner)
    │
    └── Must be coordinated: Go emits degraded state, Dart shows banner
```
