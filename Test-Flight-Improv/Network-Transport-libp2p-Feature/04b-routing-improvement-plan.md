# Routing Improvement Plan

> **Scope:** Routing strategy changes — budget allocation, relay selection, connection management, group delivery guarantees.
> **Depends on:** `04-transport-routing-strategy.md` (decision trees, race strategy, blast radius, test coverage).
> **See also:** `03b-timing-improvement-plan.md` for instrumentation, hazard fixes, and benchmark infrastructure.

---

## 1. What We Learn (Routing)

### First-Send Budget Starvation

The 2s `interactiveDirectBudget` is a wall-clock `.timeout()` on `_tryDirectSend`, but internally each step (discover, dial, send) receives `budgetMs = interactiveDirectBudget.inMilliseconds` as its own independent timeout — they don't subtract elapsed time. The outer `.timeout()` kills the chain after 2s wall-clock, so if discover takes 2s, dial and send get 0ms.

**Result:** First-send to a new peer almost always falls through to relay probe (+5s) or inbox (+15s). The race strategy depends entirely on connection reuse for responsive subsequent sends. This is a routing design issue, not a measurement gap.

### Inbox Fallback Uses Wrong Timeout

`InteractiveInboxTimeout = 3s` exists in Go but is never used. Dart's `storeInInbox` doesn't pass `timeoutMs`, so Go defaults to `InboxTimeout = 15s`. In the interactive send path (04 Section 1, inbox fallback at the bottom of the decision tree), this means a single inbox attempt can add up to 15s instead of the intended 3s.

### Sequential Relay Selection

Rendezvous register/discover tries relays sequentially. Each failed relay adds a full `DiscoverTimeout = 10s` before the next is tried. This is a relay selection strategy issue — the routing layer picks relays one at a time instead of racing them.

---

## 2. Tests to Implement (Routing-Focused)

These tests exercise routing decisions and path selection, not just raw latency.

### A. Group Discovery + First Message

```
Scenario: 3-node group, one node joins fresh
Measure:  join_to_first_peer_connected_ms, join_to_all_peers_ms,
          first_publish_latency_ms
Assert:   verify pre-publish settle wait (150ms / 500ms) is measured
Purpose:  Exercises group peer discovery routing (04 Section 2)
          and measures timing (03 Path D)
```

### B. Deferred Direct ACK Under Load

```
Scenario: Send message with deferred ACK, measure Dart confirm latency
Measure:  message_received_to_confirm_call_ms
Assert:   < 2s (must fit within DirectConfirmTimeout)
Hazard:   Verify what happens when Dart is slow (>1.5s)
Purpose:  The 2s ACK timeout interacts with sender's interactiveDirectBudget (also 2s).
          If Dart confirm is slow, sender's send times out simultaneously.
```

### C. Race Path Selection Verification

```
Scenario: Vary network conditions, verify correct path wins
Cases:
  - Both peers on LAN → WiFi should win (<100ms)
  - Peer behind NAT, relay warm → direct should win
  - Peer behind NAT, no relay → relay probe should trigger
  - Peer offline → inbox should be reached
Measure:  which transport label is assigned, total_ms per path
Purpose:  Validates race aggregation logic and relay probe eligibility (04 Section 1)
```

### D. Budget Starvation Reproduction

```
Scenario: Peer registered on relay but discover is slow (>1.5s)
Measure:  discover_ms, dial_ms (expected: 0 — never reached), send_ms (expected: 0)
Assert:   outer timeout fires at 2s, discover consumed the budget
Purpose:  Confirms the starvation behavior documented in 04 Section 1
          and validates any elapsed-budget fix
```

### E. Relay Failover Timing

```
Scenario: First relay unresponsive, second relay healthy
Measure:  time_to_first_relay_failure, time_to_second_relay_success, total_ms
Assert:   sequential: ~10s + success. parallel (after fix): ~success time only
Purpose:  Validates sequential penalty and measures improvement from parallel failover
```

### F. Connection Reuse Staleness

```
Scenario: Connection drops without peer:disconnected event
Measure:  time_until_health_check_clears_stale_entry (should be <=30s)
          wasted_send_attempt_ms during stale window
Purpose:  Validates staleness window behavior documented in 04 Section 1
```

---

## 3. Improvements (Routing Strategy)

### Quick Wins

| Change | Impact | Effort |
|---|---|---|
| **Pass `InteractiveInboxTimeout` (3s) to Go in `storeInInbox`** — Dart already imports the constant path, just needs to add `timeoutMs` param | Inbox fallback in interactive send path drops from 15s to 3s | 1 line in Dart, Go already supports the param |
| **Parallel relay failover for rendezvous** — try all relays concurrently, take first success | Eliminates sequential 10s-per-failure penalty when first relay is down | ~30 lines Go in `rendezvous.go` |

**Blast radius (from 04 Section 7):**
- `InteractiveInboxTimeout` change affects all 1:1 send paths that fall through to inbox (chat, delete, introductions, retry)
- Parallel relay failover affects rendezvous register/discover globally (personal + group namespaces)

### Medium Effort

| Change | Impact |
|---|---|
| **Elapsed-budget-aware step timeouts** — pass remaining wall-clock budget to each step in `_tryDirectSend` instead of giving each step the full budget independently | Prevents budget starvation. If discover takes 500ms, dial gets 1500ms. Currently each gets 2000ms but outer cap kills at 2000ms total. |
| **Connection pre-warming** — when a conversation is opened, proactively dial the peer before the user types | Eliminates first-send penalty for interactive use. Connection reuse path is already fast (<100ms) — the win is moving the cold-start cost out of the send path. |

**Blast radius:**
- Budget-aware timeouts: affects `send_chat_message_use_case.dart` race directly. Delete and introduction race copies (04 Section 7) must be updated separately — they import constants but have independent logic. Run: `send_chat_message_use_case_test.dart`, `delete_message_use_case_test.dart`
- Connection pre-warming: new code in conversation open path. No change to existing race logic. Reuse path already tested (04 Section 5, lines 1275-1424).

### Larger Efforts

| Change | Impact |
|---|---|
| **Relay health scoring** — track per-relay latency and failure rate, prefer faster relays, deprioritize slow/failing ones | Reduces relay path latency. Currently relays are tried in fixed order. Scoring would reorder dynamically. Affects rendezvous (personal + group), relay probe, inbox store — any operation that selects a relay. |
| **Rendezvous result caching** — cache discover results with TTL instead of live network call every time | Reduces discovery latency on repeated lookups. Currently every discover is a live roundtrip (03 Path G, ~20-120ms). Cache hit would be ~0ms. Affects the discover step inside the race (04 Section 1 direct path). |
| **GossipSub publish confirmation** — add application-level ACK for group messages since `topic.Publish` is fire-and-forget | Changes the group routing model. Currently "publish is the authority" (04 Section 2) — publish success = delivered. With ACK, publish success = peers received. Affects group dual-path coordination, the 4-way result matrix, and the BRIDGE_TIMEOUT special case. |

**Blast radius:**
- Relay health scoring: touches Go relay selection across all transport operations. Test via relay reconnect/recovery tests.
- Rendezvous caching: touches Go `rendezvous.go`. Invalidation must account for `PersonalRendezvousRegistrationTTL = 2h`. Test via rendezvous round-trip test (03b Section 2D).
- GossipSub ACK: fundamental change to group delivery semantics. Requires rethinking the publish-fail/inbox-ok matrix (04 Section 2). All group send tests must be rewritten.

---

## 4. Implementation Priority

### Priority 1 — Fix known routing deficiencies

1. **Pass `InteractiveInboxTimeout`** — 1 line, eliminates 12s of unnecessary wait in the interactive send path
2. **Parallel relay failover** — ~30 lines Go, eliminates the worst-case relay selection penalty

### Priority 2 — Fix budget starvation

3. **Elapsed-budget-aware step timeouts** — this is the single biggest improvement to first-send latency. With budget awareness, discover taking 500ms leaves 1500ms for dial+send instead of killing the chain.

### Priority 3 — Proactive routing

4. **Connection pre-warming** — moves the cold-start cost out of the user's send path entirely. Requires conversation-open hook.

### Priority 4 — Adaptive routing (requires benchmarks from 03b)

5. **Relay health scoring** — needs baseline timing data to calibrate scoring thresholds
6. **Rendezvous result caching** — needs rendezvous RTT measurements to justify cache TTL
7. **GossipSub ACK** — needs group delivery reliability data to justify the complexity

---

## 5. Relationship to Existing Test Coverage

Changes in this document affect branches already covered in 04 Section 5. Key test groups to re-run after each change:

| Change | Tests to Re-Run |
|---|---|
| InteractiveInboxTimeout | Inbox fallback tests in `send_chat_message_use_case_test.dart` (lines 738-786, 1543-1563) |
| Parallel relay failover | No existing unit tests (Go-side change). Add integration test (Section 2E above). |
| Budget-aware timeouts | Entire race test group in `send_chat_message_use_case_test.dart` (lines 959-1248). Also `delete_message_use_case_test.dart` race tests. |
| Connection pre-warming | Connection reuse tests (lines 1275-1424). Add new test for conversation-open trigger. |
| Relay health scoring | No existing unit tests. Add integration test (Section 2E above). |
| GossipSub ACK | Entire group send test group in `send_group_message_use_case_test.dart` (lines 1647-2088). |
