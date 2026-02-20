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