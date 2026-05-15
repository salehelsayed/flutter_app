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



Currently We're using GossipSub (line 20: pubsub.NewGossipSub), which is the right choice from the plan. But there's a key problem you're spotting:
GossipSub requires peers to discover each other to form a mesh. Currently the implementation joins topics and publishes, but there's no peer discovery mechanism for group members to find each other on the topic. In your existing 1:1 setup, peers connect via relay circuits (rendezvous). For GossipSub to work, group members need to be connected to each othe (directly or via relay) so the gossip mesh can form.

Use go-libp2p-rendezvous to register/discover peers on a per-group namespace (e.g.,/mknoon/group/<groupId>). Members register with the relay as a rendezvous point, discover other online members, and connect. GossipSub then handles message fan-out over those connections.


---
Regarding adding friends to a group — currently there's no UI for inviting members. Here's how it would need to work based
  on the existing architecture:

  1. Group info screen (group_info_screen.dart) would need an "Add Member" button
  2. Tapping it would show your contacts list (from ContactRepository)
  3. Selecting a contact would call callGroupUpdateConfig() bridge helper, which sends the updated GroupConfig (with the new
  member added) to the Go node via group:updateConfig
  4. The Go side (GroupUpdateConfig) updates the in-memory config so the new member's messages pass the topic validator
  5. You'd also need to share the group key with the new member (via an encrypted 1:1 message containing the groupId,
  groupKey, keyEpoch, and groupConfig) so they can decrypt messages and call group:join on their end

  The bridge commands (group:updateConfig, group:join) already exist — what's missing is the invite flow UI and the
  key-sharing protocol over 1:1 messages.

==

 Good question. The current architecture already supports this naturally:

  Orbit screen — shows your contacts list. Groups should appear here alongside contacts (they're both "connections"). A group
   card in the orbit list would open the group conversation, just like tapping a contact opens a 1:1 conversation.

  Feed screen — shows incoming messages. Group messages should appear as FeedItems in the feed, just like 1:1 messages do
  today. The FeedItem model already has a type system (ConnectionFeedItem, MessageFeedItem) — a GroupMessageFeedItem would
  slot right in.

  Why it wasn't done that way: The group feature was built in isolation as a separate vertical (its own list screen, own
  conversation screen, own nav tab). This was likely a "get it working first" approach before integrating into the existing
  screens.

  What should happen:
  - Groups appear as rows in Orbit (alongside contacts) — tapping opens the group conversation
  - Group messages appear as cards in the Feed — mixed in chronologically with 1:1 messages
  - The separate "Groups" nav tab and GroupListScreen become unnecessary
  - The GroupConversationScreen stays, but is navigated to from Orbit/Feed rather than from its own list

===







Recommended Approach: Bottom-Up, One Integration at a Time

  Phase 1: Orbit Integration (do first — smallest blast radius)

  1. Move the FAB from GroupListScreen to OrbitScreen — pure UI move, easy to verify visually
  2. Add groups to Orbit — create OrbitGroup model, extend loadOrbitData, add group rows alongside friend rows. Orbit is a simpler screen (list of rows) so this is the safest place to start mixing 1:1 and groups.

  Phase 2: Feed Integration (do second — most complex, benefits from Phase 1 learnings)

  3. Create GroupThreadFeedItem — new FeedItem subclass, keeping the existing ones untouched
  4. Extend loadFeed() — merge group threads into the existing feed chronologically
  5. Add group card rendering to FeedScreen — reuse as much of the existing card structure as possible, with a group indicator (name/avatar)

  Phase 3: Clean Up Groups Tab

  6. Decide what the Groups tab becomes — it could become a "group management" screen (create, archive, settings) rather than a message list, since messages now live in Feed/Orbit. Or remove the tab entirely if redundant.

  Why This Order

  - Orbit first because it's a flat list of rows — lower complexity than Feed's threaded card system with inline compose, reactions, and multiple card modes
  - Feed second because by then you'll have the group-in-mixed-list pattern working and can apply the same model adaptation
  - Each phase is independently shippable — the app works after each phase, just with progressively more integration
  - Tests follow each phase — write/update tests for what you changed before moving on, not all at the end




  Use $future-mobile-chat-social-ux to redesign a Gen Z group-chat app with a 3-phase evolution roadmap.