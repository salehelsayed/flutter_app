# Connection Manager: Problem & Proposed Solution

## 1. Current Problem: Two Disconnected Connection Systems

We have two independent systems tracking peer connectivity, and neither knows about the other:

**libp2p Connection Manager**
- Tracks connections established via relay, DCUtR hole-punch, or libp2p-level WiFi connections.
- Checked via `isConnectedToPeer()` in the fast path (step 3 of the send flow).
- When no connection exists, the send path falls into the discover/dial loop which tries all 9 discovered addresses with a 15-second `DialTimeout`. For offline peers, this burns ~10s on the first attempt and ~5s on retries (TCP/QUIC timeouts), totaling ~24s across 3 attempts before falling through to inbox.

**Bonsoir/WebSocket (Local WiFi)**
- Tracks peers discovered via mDNS (Bonsoir package: Bonjour on iOS, NSD on Android).
- Checked via `isLocalPeer()` in the WiFi path (step 2 of the send flow).
- Uses a separate WebSocket server for message delivery, completely outside of libp2p.
- Peers are stored in a `Map<String, LocalPeer>` inside `LocalDiscoveryService`, invisible to libp2p's connection manager.

**The result:** The send path checks these systems independently and sequentially. When both return "not connected," it enters the expensive discover/dial loop — even though the peer may simply be offline. There is no fast signal to determine "this peer is unreachable, go straight to inbox."

## 2. Both Systems Already Provide ACKs

Both connection systems confirm message delivery — the problem is not missing ACKs, it's that they don't share connectivity state.

**Bonsoir/WebSocket ACKs:**
- Each message includes a unique nonce (microseconds since epoch, base-36).
- The receiving WebSocket server echoes back `{"ack": true, "nonce": "..."}`.
- The sender waits for a matching nonce response (5-second timeout).
- Delivery is confirmed per-message with correlation.

**libp2p Stream Protocol ACKs:**
- `sendMessageWithReply()` returns a `SendMessageResult` with `.sent` and `.acknowledged` fields.
- The receiver writes an ACK back on the same libp2p stream.
- Works identically across all libp2p transports: relay circuit, DCUtR direct, or WiFi-routed.

## 3. Proposed Solution: Unified Connection Awareness

If we align both connection systems into a single connectivity check, the send path can make fast decisions without the expensive dial loop:

**Unified check before sending:**

```
Has ANY active connection to this peer?
  - Bonsoir mDNS peer map → WiFi connection exists?
  - libp2p connection manager → relay/DCUtR/libp2p connection exists?

YES (from any source) → send on that connection, get ACK.
NO  → check relay reservation:
        - NO_RESERVATION → peer app is not running → go straight to inbox (~1.5s total).
        - Reservation exists → peer is online but we lost connection → single dial attempt with short timeout.
```

**Why this works:**

- The relay `NO_RESERVATION` response takes ~100ms and definitively tells us the peer's app is not running (peers maintain relay reservations as long as the app is open).
- If no Bonsoir peer, no libp2p connection, AND no relay reservation — the peer is offline. There is zero benefit in dialing 9 addresses and waiting for TCP timeouts.
- We skip the entire discover/dial loop (3 attempts x 5-10s timeouts) and go straight to inbox.

**Expected improvement for offline peers:**

| Scenario | Current | Proposed |
|----------|---------|----------|
| Peer offline, no connections | ~24s (3 dial attempts + inbox) | ~1.5s (reservation check + inbox) |
| Peer online, already connected | ~100-500ms (fast path) | ~100-500ms (no change) |
| Peer online, not yet connected | ~10s (discover + dial) | ~5s (single attempt, lower timeout) |
| Peer on same WiFi (Bonsoir) | ~ms + relay fallthrough | ~ms (same, with unified awareness) |
