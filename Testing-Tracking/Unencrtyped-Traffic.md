 Here's the full audit. There are two layers to consider — transport and application — and there are findings in both.

  ---
  Transport Layer (libp2p): All Encrypted

  The libp2p host at go-mknoon/node/node.go:153-167 uses default security options — no NoSecurity or plaintext transport is configured. This means:

  - TCP (/tcp/0): Noise protocol negotiated before any data flows
  - WebSocket (/tcp/0/ws): Noise protocol on top of WS (libp2p security, not TLS-over-WS)
  - QUIC (/udp/0/quic-v1): Mandatory TLS 1.3 built into the protocol
  - Relay (Circuit v2): Both legs (A→Relay, Relay→B) are individually Noise/TLS-encrypted

  Every h.NewStream() call in SendMessage, InboxStore, InboxRetrieve, rendezvous, and media protocols runs over an already-encrypted connection. No unencrypted bytes hit the wire on the libp2p side.

  ---
  Application Layer: Two Issues

  1. V1 Plaintext Envelope Fallback (chat messages)

  send_chat_message_use_case.dart:121-158:

  // 4. Serialize (v2 encrypted envelope if ML-KEM key available, v1 plaintext otherwise)
  if (bridge != null && recipientMlKemPublicKey != null) {
      // ... ML-KEM encrypt → V2 envelope
  } else {
      jsonString = payload.toJson();  // ← V1 plaintext envelope
  }

  If a contact's mlKemPublicKey is null (e.g., they were added before ML-KEM was implemented, or key exchange failed), the message payload is sent as a V1 plaintext JSON envelope. The content is still protected by libp2p's Noise/TLS at
  the transport layer, so it isn't readable on the wire by a passive eavesdropper. However:

  - The relay server can read V1 messages. The relay terminates the Noise/TLS connection on each leg — it decrypts from A, then re-encrypts to B. For direct connections this doesn't matter, but for relayed and inbox-stored messages, the
   relay operator (your server) can read V1 content in plaintext.
  - The inbox stores the message string as-is at inbox.go:69: Message: message. If V1, the relay has the plaintext content sitting in memory/storage.

  2. Contact Requests — Always V1 Plaintext

  send_contact_request_use_case.dart:122-128:

  final message = {
      'type': 'contact_request',
      'version': '1',
      'payload': signedPayload,  // username, publicKey, peerId, mlkem key
  };

  Contact requests are always sent as V1 plaintext envelopes. This is by design (you need to exchange ML-KEM keys in the contact request to enable V2 later), but it means the relay can see usernames, public keys, and peer IDs of contact
   request exchanges.

  3. Local WiFi WebSocket — Plain ws://

  local_ws_server.dart:207:

  final ws = await WebSocket.connect('ws://$host:$port')

  The local WiFi discovery path uses unencrypted WebSocket (ws://, not wss://). The content sent over it is the same V1/V2 envelope (so chat messages with ML-KEM are still encrypted at the application level), but:

  - V1 messages are fully readable by anyone on the same WiFi network
  - Contact requests are fully readable on the local network
  - Even V2 encrypted messages leak metadata (from/to peer IDs, envelope structure)

  ---
  Summary

  ┌─────────────────────────────┬──────────────────────┬──────────────────────┬────────────────────────────────────────────────┐
  │            Path             │ Transport Encrypted? │  Payload Encrypted?  │                      Risk                      │
  ├─────────────────────────────┼──────────────────────┼──────────────────────┼────────────────────────────────────────────────┤
  │ Direct peer (libp2p) + V2   │ Noise/TLS            │ ML-KEM + AES-256-GCM │ None                                           │
  ├─────────────────────────────┼──────────────────────┼──────────────────────┼────────────────────────────────────────────────┤
  │ Direct peer (libp2p) + V1   │ Noise/TLS            │ No                   │ Low — relay can't see, but no defense-in-depth │
  ├─────────────────────────────┼──────────────────────┼──────────────────────┼────────────────────────────────────────────────┤
  │ Relayed/Inbox + V1          │ Noise/TLS (per leg)  │ No                   │ Medium — relay server sees plaintext           │
  ├─────────────────────────────┼──────────────────────┼──────────────────────┼────────────────────────────────────────────────┤
  │ Local WiFi + V1             │ No (plain ws://)     │ No                   │ High — anyone on WiFi sees plaintext           │
  ├─────────────────────────────┼──────────────────────┼──────────────────────┼────────────────────────────────────────────────┤
  │ Local WiFi + V2             │ No (plain ws://)     │ ML-KEM + AES-256-GCM │ Low — content encrypted but metadata exposed   │
  ├─────────────────────────────┼──────────────────────┼──────────────────────┼────────────────────────────────────────────────┤
  │ Contact requests (any path) │ Depends on path      │ No (always V1)       │ Medium — metadata always visible to relay/WiFi │
  └─────────────────────────────┴──────────────────────┴──────────────────────┴────────────────────────────────────────────────┘

  The main concerns:
  1. V1 messages via relay/inbox — the relay server can read them
  2. Local WiFi path is entirely unencrypted at the transport level — V1 messages and contact requests are fully exposed to LAN sniffing
  3. Contact requests can never be V2 since they carry the ML-KEM key exchange itself

✻ Churned for 2m 43s

❯ answer only:
  1- what do we need to have ( Relayed/Inbox + V2 ) ? do we need to change the relay code or only the app code?
  2- Local WiFi + V2 --> can we use wss:// instead ? and  What metadata is being exposed?
  3- for Contact requests (any path) , what metadata that is being visible to relay/wifi?

⏺ 1. Relayed/Inbox + V2

  Only the app code needs to change. The relay is already envelope-agnostic — it stores and forwards the message string as an opaque blob (inbox.go:69):

  req := inboxRequest{
      Message: message,  // just a string — relay doesn't parse it
  }

  The relay never inspects the envelope content. If the app sends a V2 encrypted envelope to inbox, the relay stores it encrypted and the recipient decrypts it on retrieval. The only requirement is that both peers have exchanged ML-KEM
  keys before the inbox store happens — which already happens during the contact request flow (the mlkem field). So any contact that was added via QR scan already has a ML-KEM public key.

  The app-side fix is in send_chat_message_use_case.dart:123 — when recipientMlKemPublicKey is null, instead of falling back to V1, you could either refuse to send or force ML-KEM key re-exchange. The V1 fallback only exists for
  contacts created before ML-KEM was added (migration edge case).

  2. Local WiFi + V2

  wss:// is impractical for local discovery. TLS requires either a CA-signed certificate (impossible for 192.168.x.x addresses) or a self-signed cert (which the connecting peer has no way to trust/verify). You'd need to either:
  - Do a TLS-PSK or Noise handshake using the libp2p identity keys you already have (custom protocol, significant work)
  - Pin self-signed certs via the contact exchange (complex)
  - Accept the tradeoff that local WiFi relies on application-layer encryption (V2) for confidentiality

  Metadata exposed in V2 over local WiFi — the WebSocket wrapper at local_ws_server.dart:139-144:

  final payload = jsonEncode({
      'from': fromPeerId,    // ← sender peer ID in plaintext
      'to': toPeerId,        // ← recipient peer ID in plaintext
      'content': content,    // ← this is the V2 envelope (encrypted, opaque)
      'nonce': nonce,        // ← ack correlation nonce
  });

  So an attacker on the same WiFi sees: who is talking to whom (peer IDs), when (timing), and message size — but not the content if V2.

  3. Contact Request Metadata

  The contact request payload (send_contact_request_use_case.dart:80-87) is always V1 plaintext:

  {
      'mlkem': identity.mlKemPublicKey,   // ML-KEM public key
      'ns': identity.peerId,              // peer ID
      'pk': identity.publicKey,           // Ed25519 public key
      'rv': RENDEZVOUS_ADDRESS,           // relay server address
      'ts': timestamp,                    // timestamp
      'un': identity.username,            // username in plaintext
      'sig': signature,                   // signature
  }

### Note:

    3. Contact Request Metadata

  The contact request payload (send_contact_request_use_case.dart:80-87) is always V1 plaintext:

  {
      'mlkem': identity.mlKemPublicKey,   // ML-KEM public key
      'ns': identity.peerId,              // peer ID
      'pk': identity.publicKey,           // Ed25519 public key
      'rv': RENDEZVOUS_ADDRESS,           // relay server address
      'ts': timestamp,                    // timestamp
      'un': identity.username,            // username in plaintext
      'sig': signature,                   // signature
  }

  Visible to relay/WiFi: username, peer ID, public keys, which relay server they use, and when the request was sent. This is inherent — you can't encrypt a contact request with ML-KEM because the request is the ML-KEM key exchange. The
  only way to protect this would be encrypting with the recipient's Ed25519 key (convert to X25519 for Diffie-Hellman), but that's a different design.

