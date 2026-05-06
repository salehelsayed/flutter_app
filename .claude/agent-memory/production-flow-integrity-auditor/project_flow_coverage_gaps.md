---
name: Flow coverage gaps in flows.md
description: 1:1 chat send/receive and group message send/receive flows are not registered in flows.md as of 2026-05-05
type: project
---

As of 2026-05-05 the registered flows in `Test-Flight-Improv/Production-Flow-Audits/flows.md` are:
- notification-tap-to-route
- post-photo-upload-to-feed
- deep-link-share-receive

There is NO flow covering:
- 1:1 chat message send path (user types → encrypt → p2p send → remote peer receives → listener → UI)
- 1:1 chat message receive path (incoming → listener → decrypt → DB → UI stream → screen)
- Group message send path (user types → encrypt → GossipSub publish → remote peers receive)
- Group message receive path (GossipSub → group_message_listener → persist → UI stream)

**Why this matters:** The Android notification work (onNewIntent) and group pubsub changes on the new-background branch directly touch the OS-boundary parts of these flows. The only coverage for group/1:1 messaging is the notification-tap-to-route flow, which only covers the notification→route leg, not the message itself being sent or received.

**How to apply:** When the user asks to add flows to flows.md, suggest these four as the highest-value additions given the active branch work.
