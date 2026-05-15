
  1. The relay server itself — we document what the client sends to it, but the relay is a separate codebase. Its protocols, capacity, storage, push notification fanout, Redis state — none of that is mapped.

  2. Network conditions and failure modes — what happens under packet loss, high latency, NAT type variations, cellular vs WiFi transitions, backgrounded app. The docs show the happy-path architecture, not the failure matrix.

  3. Timing and performance characteristics — no latency numbers, throughput limits, connection setup times, relay hop overhead, GossipSub propagation delay. This is what I was calling "baseline metrics" earlier.

  4. Connection lifecycle over time — how connections degrade, when reconnects happen, how the watchdog behaves in practice, how long a peer stays discoverable after going offline, TTL expiry behavior.

  5. Concurrency and ordering guarantees — what happens when two messages race (send vs receive, two senders to same inbox), message ordering across direct vs inbox vs GossipSub paths, dedup behavior at each layer.

  6. Push notification delivery path — FCM token registration is documented, but the full path (relay stores message -> relay sends push -> device wakes -> app retrieves inbox) isn't traced end-to-end.

  7. Bandwidth and data usage — frame sizes, overhead per message, rendezvous poll frequency cost (every 30s per group), relay keep-alive traffic.
  
  8. Multi-device / multi-relay topology — the docs cover single-device single-relay. Multi-relay failover flags exist but the actual topology and routing behavior isn't detailed.