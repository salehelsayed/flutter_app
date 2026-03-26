# Network Architecture: 1:1 Messaging (Text / Media / Voice)

## Executive Summary

Sophisticated 1:1 messaging with ML-KEM encryption, relay-backed fallback, offline inbox storage, and multiple delivery paths. The earlier pass was too optimistic about durability: crash-safe wire-envelope persistence is strong in the conversation screen path, but **not yet uniform across every send entry point**. The clearest current gap is inline feed reply durability.

---

## Send Flow (Text Message)

### Path: UI → Use Case → Bridge → Go → Network

1. **Validation** — sanitize text, check P2P node running
2. **Payload Construction** — UUID v4 ID, ISO-8601 timestamp, sender info, optional media/quote
3. **Encryption & Envelope**
   - **V2 (encrypted):** `callEncryptMessage(bridge, recipientMlKemPk, payload)` → ML-KEM-768 + AES-256-GCM
   - **V1 (plaintext):** fallback when recipient has no ML-KEM key
4. **Wire Envelope Persistence**
   - **Conversation screen path:** saved to DB before send (durable recovery path)
   - **Feed inline reply path:** currently weaker; it does not use the same pre-persist contract consistently
5. **Connection Reuse Fast Path** — if peer already connected, direct send
6. **Send Race** — Local WiFi vs direct P2P
7. **Relay Probe Fallback**
8. **Offline Inbox Fallback**

### Timeouts

| Path | Budget |
|------|--------|
| Local WiFi | ~1.5s |
| Direct P2P (discover + dial + send) | ~4s |
| Relay probe retry | ~250ms × 2 |
| Bridge crypto | ~10s |

---

## Receive Flow

1. Go bridge emits incoming message callback
2. `IncomingMessageRouter` parses JSON and routes by `type`
3. `handleIncomingChatMessage()`:
   - V2: decrypt with own ML-KEM secret key
   - V1: parse plaintext
   - Sanitize text
   - Validate sender
   - Deduplicate by message ID
   - Persist to DB
4. Media attachments are persisted and receive-side download is attempted by the listener path

---

## Media Send Flow

1. **Upload first** — `media:upload` bridge command
2. **Then send message** — media metadata travels in payload
3. **Persistent storage** — file copied to persistent media dir with relative path

### Encoding

| Type | Format | Processing |
|------|--------|-----------|
| Images | JPEG/PNG | Compressed, EXIF stripped |
| Video | Pass-through / feature-dependent | No heavy Dart-side re-encode path assumed here |
| Voice | M4A (AAC) | Platform handles codec |

### Chunking

No explicit Dart-side chunking. Large-file handling is delegated to the bridge/native side.

---

## Media Receive & Download

1. Attachment metadata is stored on receive
2. Listener-driven auto-download currently exists for incoming media
3. Relative paths are stored so files survive container path changes
4. Failed downloads can be retried from the app

### Current Reality

- The earlier “lazy download on UI demand” description was inaccurate for the main current receive path
- The more relevant current issue is **download deduplication/control**, not missing lazy-download architecture

---

## Delivery Semantics

### Message Status State Machine

```
sending → failed → sent → delivered
   ↑        ↓       ↓
   └── crash recovery ──┘
```

| Status | Meaning |
|--------|---------|
| `sending` | Pre-send / in-flight |
| `sent` | Sent but still retry-relevant |
| `delivered` | ACK received or inbox-stored |
| `failed` | All paths exhausted |

### ACK Mechanism

- Bridge/network ACK confirms receipt by the transport path
- It is **not** a sender-visible read receipt

### No Explicit Read Receipts

- `markConversationRead` updates local unread/read state only
- There is no networked “seen” event for the sender side today

---

## Offline Handling

### When Peer is Offline

1. Direct/WiFi paths fail
2. Relay probe confirms no active reservation
3. Message stored in relay inbox
4. Sender status reflects delivery fallback state

### Receiver Coming Online

1. Node startup / warm tasks run
2. Offline inbox drain retrieves stored messages
3. Handlers process and persist each message

### Retry Pipeline

1. Recover stuck `sending` messages
2. Retry incomplete uploads
3. Retry failed messages
4. Retry unacked/inbox-backed messages when envelope data is available

---

## Encryption: ML-KEM-768 + AES-256-GCM

### Send

1. ML-KEM encapsulation derives shared secret
2. AES-256-GCM encrypts payload
3. V2 envelope carries encrypted payload

### Receive

1. ML-KEM decapsulation derives shared secret
2. AES-256-GCM decrypts payload
3. Decrypted payload is parsed and validated

### Fallback

V1 plaintext remains as compatibility fallback when the recipient lacks ML-KEM material.

---

## Identified Issues

### Reliability Concerns

| Issue | Severity | Description |
|-------|----------|-------------|
| **Inline feed reply durability gap** | High | Feed inline replies do not use the same durable pre-persist send contract as the conversation screen |
| V2 decryption failure handling | Medium | Missing/invalid crypto state can still fail too quietly from a user-visibility perspective |
| Media download deduplication | Medium | Multiple callers can still race or duplicate work around attachment download |
| Sender-visible undelivered/read semantics | Medium | No proper read receipts and limited age/visibility around long-undelivered messages |
| Local file missing during retry | Low | Retry path still depends on local media presence for some flows |

### Missing Features

| Feature | Impact |
|---------|--------|
| Typing indicators | UX |
| Proper read receipts | UX |
| Message search | UX |
| Message expiry | Storage / UX |
| Auto-download policy controls | UX / bandwidth |
| Message editing/deletion | UX |
| Peer presence surfaced in UI | UX |
| **Media blob encryption on relay** | **Security** |

---

## Regression Gate Recommendation

Smoke is not enough protection for shared 1:1 delivery changes. A startup or text-only smoke can still pass while media upload, voice send, retry recovery, or a secondary send surface regresses.

The safer model is a named **1:1 reliability gate** that runs whenever shared send/retry/upload/inbox code changes.

### Minimum Coverage Matrix

| Axis | Required Coverage |
|------|-------------------|
| **Payload** | Text, media, voice |
| **State** | Online, offline inbox fallback, retry after failure, resume-after-interruption |
| **Surface** | Conversation screen plus any other active send surface using shared delivery logic |

### Suggested Gate Contents

| Test | Coverage |
|------|----------|
| `two_user_message_exchange_test` | Baseline direct 1:1 send/receive |
| `offline_inbox_roundtrip_test` | Offline inbox fallback |
| `media_attachment_flow_test` | Media upload/send/receive/persist |
| `media_retry_smoke_test` | Media retry path |
| `voice_message_exchange_test` | Voice record/send/receive |
| `incomplete_upload_recovery_test` | Resume recovery for partial uploads |
| `send_then_lock_delivery_test` | Lifecycle interruption during send |
| `stuck_sending_recovery_test` | Recovery of orphaned sending state |

If feed inline reply or any future non-conversation surface remains active, keep at least one regression test that enters the send path from that surface too. Otherwise durability can diverge silently even when conversation tests still pass.

### Trigger Points

Run the gate automatically when changes touch:

- `send_chat_message_use_case`
- `upload_media_use_case`
- `send_voice_message_use_case`
- `retry_incomplete_uploads_use_case`
- `retry_failed_messages_use_case`
- `chat_message_listener`
- `feed_wired`
- transport/bootstrap code that changes direct send, relay fallback, or inbox drain semantics

---

## How to Measure Performance

### Key Metrics

| Metric | How to Measure | Target |
|--------|---------------|--------|
| **E2E message latency** | Timer from send entry to delivered/received state | Track by transport path |
| **Media upload speed** | File size / upload duration | Track by mime/file class |
| **Media download speed** | File size / download duration | Track by attachment type |
| **Retry effectiveness** | Failed/unacked → delivered conversion | High recovery rate |
| **Encryption overhead** | Timer around encrypt/decrypt calls | Keep bounded by payload class |

### Instrumentation Points

1. Send entry (`sendChatMessage`)
2. Encrypt complete
3. Bridge send complete
4. ACK or inbox fallback complete
5. Receive/decrypt complete
6. Download start/finish for attachments

Start with lightweight local timers/counters rather than a full observability stack.

---

## Recommended Improvements (Prioritized)

### P0 — Correctness / Reliability
1. **Define and enforce a named 1:1 reliability regression gate** — run text + media + voice + retry/recovery coverage when shared delivery code changes
2. **Align all send entry points with the durable pre-persist contract** — especially feed inline reply
3. **Surface V2 decryption failures more clearly** — log/report/drop with explicit handling, not silent disappearance

### P1 — Operability
4. **Media download deduplication** — centralize in a small download coordinator or guard
5. **Add lightweight timers around encrypt/send/retry/download** — local counters first

### P2 — Product / Security
6. **Proper read receipts**
7. **Typing indicators**
8. **Media blob encryption on relay**
