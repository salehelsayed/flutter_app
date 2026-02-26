The ideal long-term architecture is:

  1. No full node restart as primary recovery path
     Keep one libp2p host alive and recover transport/relay state in place.
  2. Relay Session Manager (state machine)
     Manage disconnected → reconnecting → reserved → online explicitly, with:

  - immediate reconnect on app resume
  - explicit Reserve() acquisition
  - proactive reservation refresh before TTL expiry
  - jittered backoff retries

  3. Multi-relay active set (at least 2)
     Use geographically diverse static relays (prefer QUIC + WSS) so one relay drop does not degrade the node.
  4. Relay-first, direct-upgrade-second
     Come online immediately via relay, then attempt DCUtR hole punching to upgrade to direct peer paths when possible.
  5. Health based on reservation truth, not just h.Addrs()
     Track online state from successful reservations + relay connectedness + recent keepalive, not only /p2p-circuit address presence.
  6. Fast resume worker (event-driven, not 30s polling)
     Trigger relay recovery instantly on lifecycle resume and connectedness/address events.
  7. Upgrade and align with modern go-libp2p autorelay model
     Move to a newer libp2p release and consume EvtAutoRelayAddrsUpdated/addrs-manager semantics cleanly.
  8. Restart as last-resort watchdog only
     If the session manager is stuck beyond a strict SLO (for example 5–10s), then do controlled restart as fallback, not normal path.