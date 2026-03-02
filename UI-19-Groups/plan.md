We're using GossipSub (line 20: pubsub.NewGossipSub), which is the right choice from the plan. But there's a key problem
  you're spotting:

  GossipSub requires peers to discover each other to form a mesh. Currently the implementation joins topics and publishes,
  but there's no peer discovery mechanism for group members to find each other on the topic. In your existing 1:1 setup,
  peers connect via relay circuits (rendezvous). For GossipSub to work, group members need to be connected to each other
  (directly or via relay) so the gossip mesh can form.

  There are two approaches:

  1. Rendezvous-based discovery — Use go-libp2p-rendezvous to register/discover peers on a per-group namespace (e.g.,
  /mknoon/group/<groupId>). Members register with the relay as a rendezvous point, discover other online members, and
  connect. GossipSub then handles message fan-out over those connections.
  2. Rely on existing relay connections — Since all peers already connect through your relay, if they're connected to the
  same relay host, GossipSub should be able to propagate through that shared connection — but this depends on the relay
  supporting pubsub message forwarding, which circuit-relay v2 does not do natively.

  The current implementation will only work if group members are already directly connected to each other. For a real
  deployment, you'd need rendezvous discovery or explicit peer dialing for group members.

  Want me to add rendezvous-based group peer discovery so GossipSub actually works in your relay topology?
