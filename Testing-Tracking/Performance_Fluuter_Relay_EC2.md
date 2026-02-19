# Performance Monitoring: Flutter App + Relay Server + EC2

## 1. Tracking Relay Communication Lag

### Where to track

| What | Where | Why |
|---|---|---|
| Per-request RTT (register, discover, inbox store/retrieve) | Go client (`go-mknoon/node/`) | What the user experiences — includes network latency + server processing |
| Server-side processing time | Go relay (`go-relay-server/`) | Isolates server load from network — if server processing is fast but client RTT is high, it's the network |
| Queue depth & memory | Go relay only | Only the server knows its own state |

### How to ship analytics

#### Option A: Structured JSON logs -> CloudWatch (cheapest, start here)

- Change `log.Printf` calls on the relay server to JSON lines:
  ```
  {"ts":1708000000,"op":"register","peer":"12D3KooW...","elapsed_ms":12,"ok":true}
  ```
- CloudWatch Logs agent auto-ingests them
- Create CloudWatch Metric Filters to extract numeric fields (`elapsed_ms`, `inbox_depth`, etc.) into time-series metrics
- Set alarms on those metrics
- Cost: basically free (CloudWatch Logs + a few custom metrics)

#### Option B: Prometheus `/metrics` endpoint (best for dashboards)

- Add `net/http` + `github.com/prometheus/client_golang/prometheus` to the relay server
- Expose histograms and gauges on `:9090/metrics`
- Run a tiny Prometheus instance on the same EC2 (or use AWS Managed Prometheus)
- Grafana for dashboards
- Cost: ~50MB RAM for Prometheus, free Grafana Cloud tier

---

## 2. What to Add to `go-relay-server/`

### A. Request timing on every handler

Currently every handler logs the request but never measures how long it took.

**`rendezvous.go` — `HandleRendezvousStream()`:**
```go
func HandleRendezvousStream(s network.Stream, store *RendezvousStore) {
    start := time.Now()
    defer func() {
        log.Printf("[RENDEZVOUS] stream handled in %s", time.Since(start))
    }()
    defer s.Close()
    // ... rest unchanged ...
}
```

Same pattern for `HandleInboxStream()` in `inbox.go`.

### B. Concurrent stream tracking

No visibility into how many streams are being handled simultaneously.

```go
var activeStreams atomic.Int64

func HandleRendezvousStream(s network.Stream, store *RendezvousStore) {
    current := activeStreams.Add(1)
    defer activeStreams.Add(-1)
    log.Printf("[RENDEZVOUS] active_streams=%d", current)
    // ...
}
```

If `activeStreams` is consistently high, you're approaching capacity.

### C. Rendezvous store size tracking

`RendezvousStore` knows its data but never reports size. Add a `Stats()` method:

```go
func (s *RendezvousStore) Stats() (namespaces, totalPeers int) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    namespaces = len(s.registrations)
    for _, peers := range s.registrations {
        totalPeers += len(peers)
    }
    return
}
```

### D. Unified periodic stats log

`LogStatsPeriodically` currently only logs inbox and push token counts. Expand to a single unified status line covering everything:

```go
func logStatsPeriodically(ctx context.Context, inbox *InboxStore, store *RendezvousStore, h host.Host) {
    ticker := time.NewTicker(60 * time.Second)
    defer ticker.Stop()
    for {
        select {
        case <-ticker.C:
            inboxPeers, inboxMsgs := inbox.Stats()
            rzNamespaces, rzPeers := store.Stats()
            connCount := len(h.Network().Peers())
            tokenCount := inbox.push.TokenCount()
            var memStats runtime.MemStats
            runtime.ReadMemStats(&memStats)

            log.Printf("[STATS] conns=%d rz_ns=%d rz_peers=%d inbox_peers=%d inbox_msgs=%d push_tokens=%d heap_mb=%d goroutines=%d",
                connCount, rzNamespaces, rzPeers, inboxPeers, inboxMsgs, tokenCount,
                memStats.HeapAlloc/1024/1024, runtime.NumGoroutine())
        case <-ctx.Done():
            return
        }
    }
}
```

Requires passing `store` and `h` (host) to the stats logger from `main.go`.

### E. Connection count tracking

`main.go` logs connect/disconnect events but doesn't track the running total.

```go
var totalConnected atomic.Int64

// in the event goroutine:
case event.EvtPeerConnectednessChanged:
    if e.Connectedness == network.Connected {
        current := totalConnected.Add(1)
        log.Printf("[NODE] Peer connected: %s (total=%d)", shortPeerId(e.Peer), current)
    } else if e.Connectedness == network.NotConnected {
        current := totalConnected.Add(-1)
        log.Printf("[NODE] Peer disconnected: %s (total=%d)", shortPeerId(e.Peer), current)
    }
```

### F. Relay resource limits visibility

Currently running `relay.WithInfiniteLimits()` (main.go:69) — no rate limiting on circuit relay. Fine for dev, but for capacity measurement consider switching to `relay.WithResources(relay.Resources{...})` with specific limits so you can observe when the relay starts rejecting connections.

---

## 3. EC2 Capacity Testing

### Load test tool

Create `go-relay-server/cmd/loadtest/main.go` — a standalone binary that hammers the relay.

```
loadtest -relay <multiaddr> -nodes 100 -duration 5m -ops register,discover,inbox
```

**What it does:**
1. Generate N identities (`identity.GenerateIdentity()`)
2. Create N `node.Node` instances, all connecting to the relay
3. Phase 1 — **Connect ramp**: start nodes in batches of 10, measure connect time per batch
4. Phase 2 — **Register/Discover**: all nodes register on random namespaces, then discover
5. Phase 3 — **Inbox load**: each node stores messages for random other nodes, then retrieves
6. Phase 4 — **Sustained**: run mixed operations for `--duration`, collecting timing

**Output per operation:**
```
op=register      count=500   p50=45ms   p95=120ms  p99=380ms  errors=2
op=discover      count=500   p50=60ms   p95=200ms  p99=500ms  errors=0
op=inbox_store   count=1000  p50=30ms   p95=90ms   p99=250ms  errors=5
```

Can reuse all code from `go-mknoon/node/` directly — the load test client runs the same code as the app.

### How to run the tests

#### Step 1: Baseline (from your laptop)

```bash
# 10 nodes, 2 minutes — establish baseline
loadtest -relay /dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooW... -nodes 10 -duration 2m
```

#### Step 2: Ramp on a separate EC2

Spin up a cheap `t3.medium` as the load generator (different from your relay EC2):

```bash
# Ramp: 50, 100, 200, 500
for N in 50 100 200 500; do
  loadtest -relay <addr> -nodes $N -duration 3m | tee results_${N}.txt
  sleep 30  # cool down between runs
done
```

#### Step 3: Monitor the relay EC2 during the test

```bash
# Terminal 1: process stats
watch -n 5 'ps -p $(pgrep relay-server) -o pid,rss,vsz,%mem,%cpu'

# Terminal 2: OS-level
vmstat 5
# or: sar -u -r 5

# Terminal 3: relay logs (the structured stats line from section 2D)
journalctl -u relay-server -f | grep STATS

# Terminal 4: network connections
watch -n 5 'ss -s'               # socket summary
watch -n 10 'cat /proc/sys/fs/file-nr'  # FD usage
```

#### Step 4: Find the breaking point

Plot these against N (node count):

| N | Connect P95 | Register P95 | Discover P95 | RSS (MB) | CPU % | Errors |
|---|---|---|---|---|---|---|
| 50 | | | | | | |
| 100 | | | | | | |
| 200 | | | | | | |
| 500 | | | | | | |

**The breaking point** is where either:
- P95 latency exceeds your threshold (e.g. >2s for register)
- Error rate exceeds 5%
- RSS exceeds 80% of instance memory
- CPU sustains >80%

### Latency thresholds (healthy vs degraded)

| Metric | Healthy | Degraded |
|---|---|---|
| Relay connect time | < 2s | > 5s |
| Rendezvous register | < 500ms | > 2s |
| Rendezvous discover | < 1s | > 3s |
| Inbox store | < 500ms | > 2s |
| Inbox retrieve | < 1s | > 3s |
| Error rate | < 1% | > 5% |

### EC2 tuning to check before testing

```bash
# On the relay EC2:
ulimit -n                              # Should be 65535+, not 1024
sysctl net.core.somaxconn              # Should be 4096+
sysctl net.ipv4.tcp_max_syn_backlog    # Should be 4096+
```

If `ulimit -n` is 1024 (the default), the relay will hit FD exhaustion at ~500 connections regardless of CPU/memory.

### Memory growth vectors to watch

1. **Inbox messages accumulating** for offline peers (never retrieved = grows unbounded, capped at 100 per peer + 7-day expiry)
2. **Rendezvous registrations** with 2-hour TTL — stale entries pile up if peers don't unregister (cleaned every 60s by `cleanupExpired`)
3. **Push tokens** in `sync.Map` — grow with unique peers, never cleaned except on invalid token errors
