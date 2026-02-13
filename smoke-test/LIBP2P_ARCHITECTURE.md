# libp2p P2P Messaging Architecture

How two peers discover each other via a rendezvous server and exchange JSON messages over libp2p.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Components](#components)
3. [Transport Stack](#transport-stack)
4. [Protocols](#protocols)
5. [Peer Identity](#peer-identity)
6. [Step-by-Step: How User A Finds User B](#step-by-step-how-user-a-finds-user-b)
7. [Step-by-Step: How User A Sends a Message to User B](#step-by-step-how-user-a-sends-a-message-to-user-b)
8. [JSON Chat Message Schema](#json-chat-message-schema)
9. [Wire Format](#wire-format)
10. [Offline Messaging (Inbox)](#offline-messaging-inbox)

---

## System Overview

```
                     +---------------------------+
                     |    Relay + Rendezvous      |
                     |        Server              |
                     |  mknoun.xyz:4001 (WSS)     |
                     |  PeerId: 12D3KooWGMY...    |
                     +---------------------------+
                        /          |          \
                  WSS  /    relay  |  relay    \  WSS
                      /    circuit |  circuit   \
            +--------+            |            +--------+
            | Node A |  <--- p2p-circuit --->  | Node B |
            | User A |    (or direct WebRTC)   | User B |
            +--------+                        +--------+
```

Three actors participate in the system:

1. **Relay + Rendezvous Server** -- a public node that (a) stores peer registrations so peers can find each other, and (b) relays traffic between peers that cannot connect directly.
2. **Node A (User A)** -- wants to find and message Node B.
3. **Node B (User B)** -- registers its reachable address on the rendezvous server so others can discover it.

---

## Components

### Relay + Rendezvous Server

| Property | Value |
|----------|-------|
| Hostname | `mknoun.xyz` / `13.60.15.36` |
| WSS port (browsers) | `4001` (Nginx TLS termination) |
| WS local port | `4000` |
| TCP port | `4005` |
| PeerId | `12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` |

The server runs two protocol handlers:

- `/canvas/rendezvous/1.0.0` -- peer registration and discovery
- Circuit Relay v2 -- relays connections between peers behind NATs

### Client Nodes (A and B)

Both nodes are identical in capability. Each can:

- **Register** on the rendezvous server (so others can find it)
- **Discover** other peers from the rendezvous server
- **Send** JSON chat messages
- **Receive** JSON chat messages and reply with an acknowledgement

---

## Transport Stack

Each client node configures three libp2p transports:

| Transport | Role | When Used |
|-----------|------|-----------|
| **WebSocket** (`webSockets()`) | Connect to the relay server | Always -- the initial connection to `mknoun.xyz:4001/wss` |
| **WebRTC** (`webRTC()`) | Direct peer-to-peer data channel | When STUN/TURN hole punching succeeds between peers |
| **Circuit Relay** (`circuitRelayTransport()`) | Virtual transport through the server | When direct WebRTC fails (both peers behind symmetric NATs) |

WebRTC ICE servers:

```
STUN: stun:mknoun.xyz:3478
TURN: turn:mknoun.xyz:3478?transport=udp
TURN: turn:mknoun.xyz:3478?transport=tcp
```

Listen addresses:

```
/p2p-circuit     -- accept relayed connections
/webrtc          -- accept direct WebRTC connections
```

---

## Protocols

| Protocol ID | Purpose | Encoding |
|------------|---------|----------|
| `/canvas/rendezvous/1.0.0` | Peer registration & discovery | Protobuf + varint length-prefix (`it-length-prefixed`) |
| `/mknoon/chat/1.0.0` | Chat messaging | JSON + 4-byte BE length-prefix |
| `/mknoon/inbox/1.0.0` | Offline message storage | JSON + varint length-prefix |

---

## Peer Identity

Each node has an Ed25519 keypair. The PeerId is derived from the public key.

| User | Identity Source | PeerId |
|------|----------------|--------|
| User A | Loaded from `Creds_User_A.txt` (64-byte hex private key) | `12D3KooWDto5miiRBpfUcZg1uozYNXUALGetBjtwmUEvuftMmRBc` |
| User B | Hardcoded in source code | `12D3KooWCP1pBwwH1WoyqF6scuBny9T6JsdsEnDLQwVSpD6SJ8XR` |

The **rendezvous namespace** for each peer follows the convention:

```
mknoon:chat:<peer-id>
```

For example, User B's namespace is:

```
mknoon:chat:12D3KooWCP1pBwwH1WoyqF6scuBny9T6JsdsEnDLQwVSpD6SJ8XR
```

---

## Step-by-Step: How User A Finds User B

This is the full flow from cold start to User A having User B's routable multiaddress.

### Phase 1: Node B Registers on Rendezvous

Before User A can find User B, User B must register its address.

```
Node B                         Relay Server
  |                                 |
  |--- WSS dial ------------------->|  1. Connect via WebSocket
  |<-- connection established ------|
  |                                 |
  |   (circuit relay reservation)   |  2. Server grants B a relay address
  |<-- /p2p-circuit address --------|
  |                                 |
  |--- REGISTER ------------------->|  3. Send registration
  |    protocol: /canvas/rendezvous/1.0.0
  |    namespace: mknoon:chat:<B-peer-id>
  |    signedPeerRecord: [B's circuit address, signed by B's key]
  |    ttl: 7200 (2 hours)
  |                                 |
  |<-- REGISTER_RESPONSE -----------|  4. Server stores registration
  |    status: OK                   |
  |    ttl: 7200                    |
```

**What happens in detail:**

1. Node B dials `mknoun.xyz:4001/wss` using the WebSocket transport.
2. The server's Circuit Relay v2 service automatically grants B a **relay reservation**. This gives B a routable address like:
   ```
   /dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMY.../p2p-circuit/p2p/12D3KooWCP1...
   ```
   This address means: "connect to the relay server, then ask it to relay to Node B."
3. Node B creates a **signed peer record** containing its circuit relay multiaddress(es), sealed with its Ed25519 private key. It sends a `REGISTER` message to the server's rendezvous protocol handler.
4. The server verifies the signature on the peer record, stores the registration under the namespace `mknoon:chat:<B-peer-id>` with a TTL, and responds with `OK`.
5. Node B re-registers every `TTL * 0.8` seconds (about 96 minutes) to stay discoverable.

### Phase 2: Node A Discovers Node B

```
Node A                         Relay Server
  |                                 |
  |--- WSS dial ------------------->|  1. Connect via WebSocket
  |<-- connection established ------|
  |                                 |
  |--- DISCOVER ------------------->|  2. Send discovery request
  |    protocol: /canvas/rendezvous/1.0.0
  |    namespace: mknoon:chat:<B-peer-id>
  |    limit: 100
  |                                 |
  |<-- DISCOVER_RESPONSE -----------|  3. Server returns B's registration
  |    status: OK                   |
  |    registrations: [             |
  |      {                          |
  |        ns: mknoon:chat:<B-peer-id>
  |        signedPeerRecord: [...]  |  <-- contains B's multiaddresses
  |      }                          |
  |    ]                            |
```

**What happens in detail:**

1. Node A dials the relay server via WebSocket (it may already be connected).
2. Node A opens a stream on `/canvas/rendezvous/1.0.0` and sends a `DISCOVER` message with the namespace `mknoon:chat:<B-peer-id>`.
3. The server looks up all non-expired registrations under that namespace and returns them.
4. Node A receives the response, opens the signed peer record envelope, cryptographically verifies the signature, and extracts User B's multiaddresses.
5. If no registrations are found, Node A retries every 2 seconds (configurable via `DISCOVER_POLL_MS`) up to a 60-second timeout.

### Phase 3: Node A Connects to Node B

After discovery, Node A has one or more multiaddresses for Node B. These are typically circuit relay addresses:

```
/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMY.../p2p-circuit/p2p/12D3KooWCP1...
```

Node A dials this address:

```
Node A                    Relay Server                  Node B
  |                            |                            |
  |--- dial circuit addr ----->|                            |
  |                            |--- relay to B ------------>|
  |<====== relayed connection (through server) ============>|
  |                                                         |
  |  (connection established -- can now open streams)       |
```

The relay server forwards all bytes between A and B. This is a **limited connection** (the relay may enforce bandwidth/duration limits), but it is sufficient for chat messages.

If both peers support WebRTC and STUN/TURN succeeds, libp2p may automatically upgrade to a **direct WebRTC connection**, bypassing the relay entirely.

---

## Step-by-Step: How User A Sends a Message to User B

Once connected (via relay or direct), Node A opens a new stream to send each message.

```
Node A                                             Node B
  |                                                    |
  |--- dialProtocol(B, /mknoon/chat/1.0.0) ---------->|  1. Open stream
  |                                                    |
  |--- [4-byte len][JSON message] -------------------->|  2. Send framed JSON
  |                                                    |
  |                               (handler fires)      |  3. B parses JSON
  |                               (calls onMessage)    |
  |                                                    |
  |<-- [4-byte len][JSON ack] -------------------------|  4. B sends ack
  |                                                    |
  |--- stream.close() -------- stream.close() ---------|  5. Both close stream
```

### Detailed Breakdown

**Step 1 -- Open Stream**

Node A calls `node.dialProtocol(peerIdFromString(B_PEER_ID), '/mknoon/chat/1.0.0')`. libp2p uses the existing connection (relay or direct) and opens a new multiplexed yamux stream for this protocol.

**Step 2 -- Send Message**

Node A constructs a JSON message object, serializes it with `JSON.stringify()`, encodes to UTF-8 bytes, prepends a 4-byte big-endian length header, and sends via `stream.send()`.

**Step 3 -- Receive and Process**

Node B's chat protocol handler fires. It reads bytes from the stream, accumulates them in a buffer, reads the 4-byte length, extracts the payload, and deserializes the JSON. The `onMessage` callback is invoked with the parsed message.

**Step 4 -- Send Ack**

Node B constructs a JSON acknowledgement object (with `replyTo` referencing the original message ID), serializes and frames it the same way, and sends it back on the same stream.

**Step 5 -- Close Stream**

Both sides close the stream. The underlying connection remains open for future messages.

---

## JSON Chat Message Schema

All chat messages use the schema version `mknoon.chat.v1`. There are two message types: `message` and `ack`.

### Message (type: `message`)

Sent by the initiator to deliver a chat message.

```json
{
  "schema": "mknoon.chat.v1",
  "type": "message",
  "id": "986a50da-8822-4cf2-ae8b-424e3ce077d3",
  "from": "12D3KooWDto5miiRBpfUcZg1uozYNXUALGetBjtwmUEvuftMmRBc",
  "to": "12D3KooWCP1pBwwH1WoyqF6scuBny9T6JsdsEnDLQwVSpD6SJ8XR",
  "body": "Hello from Node A!",
  "timestamp": "2026-02-09T20:48:33.856Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `schema` | `string` | Always `"mknoon.chat.v1"` |
| `type` | `string` | Always `"message"` for chat messages |
| `id` | `string` | UUID v4, unique identifier for this message |
| `from` | `string` | Sender's libp2p PeerId |
| `to` | `string` | Recipient's libp2p PeerId |
| `body` | `string` | The message text content |
| `timestamp` | `string` | ISO 8601 timestamp of when the message was created |

### Acknowledgement (type: `ack`)

Sent by the receiver to confirm receipt.

```json
{
  "schema": "mknoon.chat.v1",
  "type": "ack",
  "id": "bf3bf37f-1385-45f5-943a-71e45dfd942b",
  "replyTo": "986a50da-8822-4cf2-ae8b-424e3ce077d3",
  "from": "12D3KooWCP1pBwwH1WoyqF6scuBny9T6JsdsEnDLQwVSpD6SJ8XR",
  "to": "12D3KooWDto5miiRBpfUcZg1uozYNXUALGetBjtwmUEvuftMmRBc",
  "body": "received: Hello from Node A!",
  "timestamp": "2026-02-09T20:48:33.858Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `schema` | `string` | Always `"mknoon.chat.v1"` |
| `type` | `string` | Always `"ack"` for acknowledgements |
| `id` | `string` | UUID v4, unique identifier for this ack |
| `replyTo` | `string` | The `id` of the original message being acknowledged |
| `from` | `string` | Acknowledger's libp2p PeerId |
| `to` | `string` | Original sender's libp2p PeerId |
| `body` | `string` | `"received: "` followed by the original message body |
| `timestamp` | `string` | ISO 8601 timestamp of when the ack was created |

---

## Wire Format

Every chat message on the `/mknoon/chat/1.0.0` protocol is framed with a **4-byte big-endian length prefix**:

```
+--------+--------+--------+--------+-------- ... --------+
| byte 0 | byte 1 | byte 2 | byte 3 |     JSON payload    |
|  (MSB) |        |        |  (LSB) |   (UTF-8 encoded)   |
+--------+--------+--------+--------+-------- ... --------+
|<-------- 4 bytes: length -------->|<--- length bytes --->|
```

**Encoding:**

```
length = payload.length
byte[0] = (length >>> 24) & 0xFF
byte[1] = (length >>> 16) & 0xFF
byte[2] = (length >>>  8) & 0xFF
byte[3] = (length >>>  0) & 0xFF
```

**Decoding:**

```
length = (byte[0] << 24) | (byte[1] << 16) | (byte[2] << 8) | byte[3]
payload = bytes[4 .. 4 + length]
json    = JSON.parse(UTF8.decode(payload))
```

Maximum frame size: **128 KB** (131,072 bytes).

This framing is distinct from the rendezvous protocol which uses **varint length-prefixed** encoding via `it-length-prefixed`.

---

## Offline Messaging (Inbox)

When the target peer is offline (direct send fails), the sender can store the message on the relay server's inbox for later retrieval.

**Protocol:** `/mknoon/inbox/1.0.0`

### Store Flow

```
Node A                         Relay Server
  |                                 |
  |--- STORE ---------------------->|
  |    type: 0                      |
  |    to: <B-peer-id>             |
  |    message: "Hello"            |
  |                                 |
  |<-- RESPONSE --------------------|
  |    status: 0 (OK)              |
```

### Retrieve Flow

```
Node B                         Relay Server
  |                                 |
  |--- RETRIEVE ------------------->|
  |    type: 1                      |
  |                                 |
  |<-- RESPONSE --------------------|
  |    status: 0 (OK)              |
  |    messages: [                  |
  |      { from, message, timestamp }
  |    ]                            |
```

Messages are stored in-memory with a maximum of **100 messages per peer** and a **7-day expiration**.

---

## Timeouts and Intervals

| Constant | Value | Purpose |
|----------|-------|---------|
| `REGISTER_TTL_S` | 7200s (2h) | How long the rendezvous registration lives |
| `REGISTER_RETRY_MS` | 5000ms | Retry delay after failed registration |
| `DISCOVER_POLL_MS` | 2000ms | Polling interval during peer discovery |
| `DISCOVER_TIMEOUT_MS` | 60000ms (1m) | Total discovery timeout |
| `CHAT_TIMEOUT_MS` | 10000ms (10s) | Timeout for sending a single chat message |
| `RELAY_TIMEOUT_MS` | 30000ms (30s) | Timeout waiting for circuit relay address |
| `MAX_FRAME_LEN` | 131072 (128KB) | Maximum chat message frame size |
