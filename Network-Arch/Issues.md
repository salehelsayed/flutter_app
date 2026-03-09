 Go-libp2p Architecture Review

  Current Stack

  - go-libp2p v0.39.1, go-libp2p-pubsub v0.15.0, Go 1.25
  - Single relay server: mknoun.xyz (WSS :4001 + QUIC :4002)
  - AutoRelay with static relays, ForceReachabilityPrivate
  - GossipSub with FloodPublish for group messaging
  - Bridge: gomobile → MethodChannel (req/resp) + EventChannel (push events)

  ---
  What Works Well

  1. Mobile-first defaults are correct
  - ForceReachabilityPrivate() — mobile is always behind NAT, no wasted autonat probing
  - EnableHolePunching() + NATPortMap() — opportunistic direct upgrades when possible
  - 3 transport listeners (QUIC, WS, TCP) — maximum compatibility

  2. AutoRelay tuning is aggressive in the right way
  - WithBootDelay(0) — relays are static, no candidate search needed
  - WithBackoff(5s) / WithMinInterval(5s) — vs defaults of 1h/30s
  - Warm relay connection at startup bypasses the 20s identify timeout

  3. Event-driven address tracking
  - Subscribes to EvtPeerConnectednessChanged + EvtLocalAddressesUpdated
  - Push events flow Go → Dart immediately (no polling needed for happy path)
  - sinceStartMs in address events gives good startup timing telemetry

  4. GossipSub + FloodPublish
  - Correct for small groups (2-10) over relay circuits where mesh formation is slow
  - Topic validators enforce membership + signatures before acceptance
  - v3 envelope: encrypted (AES-256-GCM) + signed (Ed25519) — solid

  5. Dual discovery strategy for groups
  - Direct relay dial of known members (primary, fast)
  - Rendezvous register/discover (secondary, catches new members)
  - Best-effort semantics — individual failures don't block others

  6. Store-and-forward inbox
  - Separate from GossipSub — covers the offline delivery gap
  - Group inbox with sinceTimestamp retrieval — good for catch-up

  7. Structured telemetry
  - FLOW events at every layer (Go → Dart → UI)
  - group:discovery step events, group:publish_debug peer counts
  - Good foundation for production observability

  ---
  Critical Issues (Ordered by Impact)

  Issue 1: Full node restart is the ONLY recovery path

  Where: node.go:392-447 (ReconnectRelays)

  // go-libp2p's AutoRelay (v0.38.2) does NOT reliably re-reserve circuit
  // addresses after a relay disconnection.
  func (n *Node) ReconnectRelays() error {
      n.Stop()   // closes host, cancels ALL contexts, destroys ALL state
      n.Start()  // creates entirely new host, new AutoRelay, new PubSub
  }

  Impact: Every relay hiccup destroys the entire libp2p host. This means:
  - All GossipSub topics/subscriptions are destroyed (Dart must call rejoinGroupTopics)
  - All peer connections are dropped (including healthy ones to other peers)
  - All in-flight streams are killed
  - PubSub mesh state is lost — takes time to reform
  - The peer ID stays the same but the host is brand new — peers see disconnect+reconnect

  Your ideal #1 and #8: This is exactly the anti-pattern. Recovery should preserve the host and only fix the relay transport. Restart should be a last-resort watchdog.

  Issue 2: No relay session state machine

  Where: There is no relay state concept at all. The node is binary: isStarted or not.

  Current state model:
  stopped ←→ started (host exists)

  Missing states:
  disconnected → reconnecting → reserving → reserved/online → degraded

  Impact:
  - No distinction between "relay TCP is down" vs "reservation expired" vs "relay unreachable"
  - Can't trigger targeted recovery (just re-reserve vs re-dial vs restart)
  - Health check uses coarse proxy: circuitAddresses.isEmpty from h.Addrs()
  - AutoRelay internally manages reservation but exposes nothing to your code

  Your ideal #2: You need an explicit state machine tracking reservation state, TTL, and connection health independently.

  Issue 3: Health determined by address presence, not reservation truth

  Where: p2p_service_impl.dart:590-592

  if (freshState.isStarted &&
      freshState.circuitAddresses.isEmpty &&
      _hasEverBeenOnline) {
    // DEGRADED — trigger relay:reconnect
  }

  And in Go node.go:313-321:
  for _, addr := range n.host.Addrs() {
      if strings.Contains(s, "/p2p-circuit") {
          circuitAddrs = append(circuitAddrs, s)
      }
  }

  Impact:
  - h.Addrs() can show stale circuit addresses after the relay has actually dropped the reservation
  - A circuit address in the address set does NOT mean the reservation is still valid
  - No keepalive or liveness probe to the relay
  - You could think you're "online" while the relay has already expired your reservation

  Your ideal #5: Health needs to be based on active reservation state + relay connectedness + recent successful keepalive, not just address set inspection.

  Issue 4: 30-second polling — too slow for mobile resume

  Where: p2p_service_impl.dart:38,544

  static const healthCheckInterval = Duration(seconds: 30);
  _healthCheckTimer = Timer.periodic(healthCheckInterval, (_) {
      _performHealthCheck();
  });

  And group discovery: config.go:36
  GroupDiscoveryInterval = 30 * time.Second

  Impact:
  - User opens app after background → worst case 30s before relay recovery starts
  - The 2s "fast circuit check" in warmBackground() only polls node:status — it doesn't trigger reconnection
  - handleAppResumed does call performImmediateHealthCheck(), which helps, but it goes through the same _performHealthCheck that does a full relay:reconnect (Stop+Start) — very heavy for a resume

  Your ideal #6: Resume should be event-driven (lifecycle event → immediate relay recovery), not dependent on timer alignment.

  Issue 5: Single relay = single point of failure

  Where: config.go:10-13

  DefaultRelayAddress = "/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3..."
  DefaultQUICRelay    = "/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3..."

  Both addresses point to the same server (mknoun.xyz). The code already supports multiple relays (relayInfoMap merges by peer ID), but there's only one relay peer.

  Impact:
  - If mknoun.xyz goes down, ALL users are offline
  - If the relay restarts, ALL reservations are lost simultaneously
  - DNS resolution failure = total outage
  - No geographic diversity = high latency for distant users

  Your ideal #3: Need at least 2 geographically diverse relays. The code already handles multiple — you just need to deploy them.

  Issue 6: DialPeerViaRelay only uses the first relay address

  Where: node.go:504-505

  relayMaddr, err := ma.NewMultiaddr(relayAddrs[0])

  When dialing peers via relay circuit, only relayAddrs[0] is tried. If you had multiple relays, peer dialing would still only go through the first one.

  Impact: Even with multiple relays, peer connectivity would only work through relay[0]. Should try all relays or use the one where the peer has a reservation.

  Issue 7: Group rejoin after restart has no retry

  Where: After ReconnectRelays() does Stop+Start, all GossipSub state is destroyed. The Dart side calls rejoinGroupTopics at app startup, but NOT after a relay:reconnect mid-session.

  Looking at _performHealthCheck (line 604):
  await callP2PRelayReconnect(_bridge);
  // ... re-registers push token, but does NOT rejoin group topics

  Impact: After a mid-session relay reconnect, all group subscriptions are gone. Users stop receiving group messages until they restart the app.

  Issue 8: GossipSub publish with 0 peers succeeds silently

  Where: pubsub.go:220-224

  topicPeers := topic.ListPeers()
  log.Printf("peers in topic: %d", len(topicPeers))  // logged but not acted on
  if err := topic.Publish(ctx, []byte(envelopeJSON)); err != nil {
      return "", fmt.Errorf("publish to topic: %w", err)
  }

  Impact: User sends a message, gets a success response, but nobody received it. The group:publish_debug event includes peer count but Dart doesn't act on it. No retry, no queuing, no user feedback.

  ---
  Moderate Issues

  Issue 9: Rendezvous TTL is static 2h, no proactive refresh

  Where: rendezvous.go — registers with TTL: 7200 (2 hours)

  The 30s discovery loop calls dialKnownGroupMembers + discoverAndConnectGroupPeers but does NOT re-register. Registration only happens once when joining the group topic (groupPeerDiscoveryLoop line 680).

  Impact: After 2 hours, the node disappears from rendezvous discovery for new members. Existing connections still work (GossipSub), but no new peers can find this node.

  Issue 10: No reconnect for relay connection loss mid-session

  The watchConnectionEvents goroutine sees peer:disconnected for the relay peer, but doesn't trigger any recovery. It just removes the connection from the map and emits an event.

  Recovery only happens when the 30s health check fires, notices empty circuit addresses, and does a full restart.

  Issue 11: PeerDialTimeout is 2s — too aggressive for relay circuits

  Where: config.go:26

  PeerDialTimeout = 2 * time.Second

  Relay circuit dials go through: local → relay → relay → remote. On mobile networks with 200-500ms RTT, 2s is tight. This could cause false "peer offline" results, especially under load.

  Issue 12: Connection manager limits may be too low

  connmgr.NewConnManager(10, 100, connmgr.WithGracePeriod(time.Minute))

  Low watermark of 10 means the connection manager starts trimming aggressively. For a user in multiple groups with many members, 10 connections could mean important group peers get pruned.

  Issue 13: No stream deadlines on incoming chat handler

  Where: node.go:608

  func (n *Node) handleIncomingMessage(s network.Stream) {
      defer s.Close()
      // No s.SetDeadline() — relies on remote closing stream
      msgBytes, err := readFrame(s)

  The sender sets a deadline, but the receiver doesn't. A malicious or stuck peer could hold the stream open indefinitely.

  ---
  Alignment with Your Ideal Architecture

  ┌──────────────────────────────────────────┬─────────────────────────────────────────┬───────────────────────────────────────────────────────────┐
  │                   Goal                   │              Current State              │                            Gap                            │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ 1. No full restart as primary recovery   │ Stop+Start is the ONLY path             │ Major — need in-place relay recovery                      │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ 2. Relay Session Manager (state machine) │ Binary started/not-started              │ Major — no state machine at all                           │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ 3. Multi-relay active set (2+)           │ 1 relay, 2 transports (same host)       │ Medium — code supports it, need deployment                │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ 4. Relay-first, direct-upgrade           │ Already doing this correctly            │ Good — ForceReachabilityPrivate + HolePunching            │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ 5. Health based on reservation truth     │ Based on h.Addrs() circuit presence     │ Major — can show stale addresses                          │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ 6. Fast resume (event-driven)            │ 30s polling + immediate check on resume │ Medium — resume exists but triggers full restart          │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ 7. Modern autorelay model                │ v0.39.1 with customized autorelay       │ Minor — already fairly recent, could use newer event APIs │
  ├──────────────────────────────────────────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ 8. Restart as last-resort watchdog       │ Restart is the ONLY recovery            │ Major — exactly backwards                                 │
  └──────────────────────────────────────────┴─────────────────────────────────────────┴───────────────────────────────────────────────────────────┘

  ---
  Recommended Priority Order

  1. Relay Session Manager (addresses #1, #2, #5, #8) — This is the foundational change. Build a state machine that tracks reservation state explicitly, recovers transport in-place, and only restarts as a watchdog fallback.
  2. Group rejoin after relay reconnect (addresses #7) — Quick win: after any relay recovery, re-subscribe all active group topics. Without this, mid-session reconnects break groups silently.
  3. Multi-relay deployment (addresses #3, #6) — Deploy a second relay server. Fix DialPeerViaRelay to try all known relays. Low code change, high resilience gain.
  4. Event-driven resume (addresses #6, #10) — On relay peer disconnect event, immediately trigger re-reservation (not full restart). On app resume, trigger relay session recovery, not full health check.
  5. Publish reliability (addresses #8) — When topic.ListPeers() == 0, queue the message and retry after peer discovery. Surface "pending" state to the user.
