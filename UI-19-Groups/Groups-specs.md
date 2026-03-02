

GossipSub can also be a "private" group chat?

⏺ Yes — but GossipSub itself has no built-in privacy. Topics are just named strings, and any peer who knows the name can subscribe and see messages. So you layer privacy on top.

  Two approaches

  1. Application-level encryption (most common)
  - Create a shared symmetric key for the group (e.g. AES-256-GCM)
  - Distribute that key only to group members (via your existing encrypted 1:1 channels)
  - Publish encrypted payloads to the topic — anyone can subscribe, but only members with the key can decrypt
  - Topic name itself can be a random hash so it's not guessable

  Practical choice for your case

  Approach 1 is what most apps do (including Signal groups, Matrix rooms, etc.):

  - The topic is "public" at the transport level — GossipSub routes it normally
  - The content is encrypted — non-members see gibberish
  - You manage group membership by sharing/rotating the group key
  - When someone is removed, you rotate the key and redistribute to remaining members

  This fits well with your existing ML-KEM/AES-256-GCM setup — you'd just use a shared group key instead of a per-recipient key.

  The tradeoff

  - Metadata leaks: non-members can still see that messages are being published to a topic (frequency, size, timing), even if they can't read them
  - If that matters, you'd use random/opaque topic names and potentially pad message sizes


  

❯ lets say I will use (Application-level encryption (most common)) ... where do I actually "publish" to this group? is that a node or is this a message sent to all users?

⏺ In GossipSub, there's no central node — when you publish, the message propagates peer-to-peer through the mesh.

  What actually happens

  1. You call topic.Publish(message) on your node
  2. Your node sends it to the few peers it's directly connected to that are subscribed to that topic (your "mesh peers" — typically 6-12)
  3. Each of those peers forwards it to their mesh peers
  4. Within a few hops, every subscriber has it

  There's no "destination" — it fans out through the network like gossip.

  So where does the group "live"?

  Nowhere and everywhere. The group is just:

  - A topic name (a string)
  - A shared key (for encryption)
  - A set of peers who happen to be subscribed to that topic

  No server, no special node, no fixed location.

  The catch: what if a member is offline?

  GossipSub is live delivery only. If a peer isn't connected when a message is published, they miss it. For a group chat, you'd need to solve this. Common approaches:

  ┌───────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │     Approach      │                                                                           How                                                                            │
  ├───────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Store nodes       │ Some always-online peers (could be your relay server) subscribe to the topic and cache messages. When a peer comes online, they request missed messages. │
  ├───────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Peer-to-peer sync │ When a peer reconnects, they ask other group members "what did I miss since timestamp X?"                                                                │
  ├───────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Hybrid            │ Use your existing relay server as a "store-and-forward" participant in the group topic                                                                   │
  └───────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  For your project specifically

  Your relay server (go-relay-server) is already always-online. The simplest path would be having the relay also subscribe to group topics and store messages — then offline members pull missed messages from the relay when they
  reconnect. The relay still can't read anything (encrypted with the group key it doesn't have).


❯ if I would use Gossip sub, can I utilize my online inbox to save the messages for offline users and later they can retrieve it from the inbox ?

⏺ Yes — that's a natural fit. Your relay server already has an inbox system for 1:1 messages. You'd extend it the same way:

  How it works

  1. Relay subscribes to the group topic like any other peer
  2. When a message is published, the relay receives it (still encrypted — it can't read it)
  3. Relay stores it in the inbox keyed by topic + timestamp
  4. When an offline member comes online, they pull missed messages from the relay (e.g. "give me everything on topic X since my last seen timestamp")

  What changes in your relay

  Not much — you'd basically add:

  - A topic inbox alongside your existing per-peer inbox (or just tag inbox messages with a topic ID)
  - An endpoint for peers to fetch by topic + since timestamp
  - The relay subscribes to group topics so it naturally receives everything

  Why this works well

  - The relay already stores and forwards encrypted blobs — group messages are just more encrypted blobs
  - The relay can't read them (no group key) — same trust model you already have
  - Offline members get caught up from one source (the relay) instead of asking every peer "what did I miss?"
  - You avoid the complexity of peer-to-peer history sync

  One thing to decide

  Who tells the relay which topics to subscribe to? Two options:

  ┌─────────────────────────┬─────────────────────────────────────────────────────────────────────────────┐
  │         Option          │                                     How                                     │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ Members register topics │ A group creator sends a request to the relay: "please subscribe to topic X" │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────┤
  │ Relay auto-discovers    │ Relay uses pubsub discovery to join any topic its known peers are on        │
  └─────────────────────────┴─────────────────────────────────────────────────────────────────────────────┘

  The first is simpler and more explicit — fits your current relay design better.


❯ how would the group key rotation work when removing a member?

⏺ The problem

  When you remove a member, they still have the old group key. So they can read any future messages encrypted with that key. You must rotate.

  The process

  1. Admin removes member C from the group
  2. Admin generates a new group key
  3. Admin sends the new key to every remaining member via their existing 1:1 encrypted channels (you already have this with ML-KEM)
  4. From that point, all messages use the new key
  5. Removed member C still has the old key — they can read history, but nothing new

  What each peer stores per group

  - topic name
  - current group key
  - previous group keys (to decrypt old messages)
  - member list + roles
  - key generation number (so peers know which key to use)

  Message envelope would include a key generation

  {
    "topic": "abc123",
    "keyGen": 3,
    "ciphertext": "..."
  }

  Receivers look up the right key by keyGen to decrypt. This way old and new messages are all readable from history.

  Edge case: race condition during rotation

  After rotation, some peers might not have received the new key yet and still publish with the old one. Two ways to handle:

  ┌──────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │         Approach         │                                                            Trade-off                                                            │
  ├──────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Accept both keys briefly │ Receivers try current key, fall back to previous. Simple but the removed member could sneak in a message during the window.     │
  ├──────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Strict cutoff            │ Reject old-key messages after rotation. Clean, but some legitimate messages might get dropped if the sender was slow to update. │
  └──────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  Most apps (Signal, Matrix) go with the first — accept a brief overlap.

  What you can't prevent

  - Removed member already saw past messages — they had the key, they could have saved the plaintext. Key rotation protects the future, not the past.
  - A remaining member could leak the new key to the removed member — this is a social problem, not a crypto one.

  For your setup specifically

  The nice part is you already have the building blocks:

  - 1:1 encrypted channels → for distributing new group keys
  - Relay inbox → the new-key messages land in offline members' inboxes, so they get the rotation even if they weren't online when it happened
  - ML-KEM per contact → each key distribution message is encrypted to that specific member

❯ what about adding a new member to an existing group?

⏺ Simpler than removal — no rotation needed.

  The process

  1. Admin adds member D to the group
  2. Admin sends member D (via 1:1 encrypted channel):
    - Topic name
    - Current group key
    - Member list + roles
    - Key generation number
  3. Member D subscribes to the topic
  4. Member D can decrypt all future messages

  The decision: can they see history?

  ┌─────────────────┬────────────────────────────────┬──────────────────────────────────────────────────────────────────────────┐
  │     Option      │              How               │                                Trade-off                                 │
  ├─────────────────┼────────────────────────────────┼──────────────────────────────────────────────────────────────────────────┤
  │ No history      │ Only send the current key      │ Simple, more private — existing members' past conversations stay private │
  ├─────────────────┼────────────────────────────────┼──────────────────────────────────────────────────────────────────────────┤
  │ Full history    │ Send all previous keys too     │ New member can decrypt everything from the relay inbox                   │
  ├─────────────────┼────────────────────────────────┼──────────────────────────────────────────────────────────────────────────┤
  │ Partial history │ Send keys from a certain point │ Middle ground — "you can see the last 30 days"                           │
  └─────────────────┴────────────────────────────────┴──────────────────────────────────────────────────────────────────────────┘

  This is a product decision, not a technical one. You can support any of these since the relay already stores the encrypted messages — it's just a question of which keys you hand over.

  What the new member does

  1. Receives group info via 1:1 channel
  2. Subscribes to the topic on GossipSub
  3. Pulls missed messages from the relay inbox (if given historical keys)
  4. Starts receiving live messages

  No rotation needed because

  - The new member didn't have the old key before — nothing to protect
  - Existing members' keys are unchanged — no disruption
  - The only exception: if a previously removed member is being re-added, you might want to rotate anyway out of caution (they still have old keys from before their removal)

  Summary

  ┌───────────────────────┬───────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────┐
  │         Event         │  Rotate key?  │                                               Why                                                │
  ├───────────────────────┼───────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Remove member         │ Yes           │ They still have the key                                                                          │
  ├───────────────────────┼───────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Add new member        │ No            │ They never had it                                                                                │
  ├───────────────────────┼───────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Re-add removed member │ Optional      │ They have stale keys from before, but current key is already rotated from when they were removed │
  ├───────────────────────┼───────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Periodic rotation     │ Good practice │ Limits damage if a key leaks                                                                     │
  └───────────────────────┴───────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────┘
