# Use Case Audit: 1:1 Chat

**Total Implemented:** 34 use cases (conversation + contacts + encryption/crypto)
**Test Coverage:** Implemented core use cases have meaningful test coverage
**Missing Features:** Product/UX features still intentionally absent

---

## Category 1: Sending Messages

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 1 | Send text chat message | `send_chat_message_use_case.dart` | YES | Good |
| 2 | Send voice message | `send_voice_message_use_case.dart` | YES | Good |
| 3 | Upload media (image/video/audio) | `upload_media_use_case.dart` | YES | Good |
| 4 | Send with quoted message | Embedded in `send_chat_message` | YES | Partial |
| 5 | Send with media attachments | Embedded in `send_chat_message` | YES | Partial |

**Important nuance:** the earlier feed-inline durable-send mismatch is now
closed; conversation and feed-originated inline reply use the same durable
pre-persist contract in the current Flutter tree. The sender-visible 1:1
transport-truth seams are also now closed for new rows: outgoing Go/libp2p
sends persist actual `direct` vs `relay`, reuse-fast-path/local semantics stay
honest, and legacy `reuse` remains old-row fallback only.

---

## Category 2: Receiving Messages

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 6 | Handle incoming chat message | `handle_incoming_chat_message_use_case.dart` | YES | Good |
| 7 | Chat message listener (broadcast) | `chat_message_listener.dart` | YES | Good |
| 8 | Download media from relay | `download_media_use_case.dart` | YES | Good |
| 9 | Auto-download media on receive | Embedded in `chat_message_listener` | YES | Partial |
| 10 | Handle incoming emoji reaction | `handle_incoming_reaction_use_case.dart` | YES | Good |
| 11 | Reaction listener (broadcast) | `reaction_listener.dart` | YES | Good |

**Current behavior note:** the earlier “lazy-only media download” description
was too narrow; the main current receive path already attempts auto-download.
Incoming Go-backed 1:1 rows now also carry additive transport truth, so mixed
direct+relay peer state no longer forces a relay icon when the actual inbound
stream was direct.

---

## Category 3: Message Lifecycle

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 12 | Retry failed messages | `retry_failed_messages_use_case.dart` | YES | Good |
| 13 | Retry unacked messages | `retry_unacked_messages_use_case.dart` | YES | Good |
| 14 | Recover stuck sending messages | `recover_stuck_sending_messages_use_case.dart` | YES | Good |
| 15 | Retry incomplete uploads | `retry_incomplete_uploads_use_case.dart` | YES | Good |
| 16 | Mark conversation as read | `mark_conversation_read_use_case.dart` | YES | Good |
| 17 | Load conversation (with pagination) | `load_conversation_use_case.dart` | YES | Good |

**Important nuance:** `markConversationRead` is local unread-state management, not a sender-visible read-receipt protocol.

---

## Category 4: Contact Management

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 18 | Add contact | `add_contact_use_case.dart` | YES | Good |
| 19 | Block contact | `block_contact_use_case.dart` | YES | Good |
| 20 | Unblock contact | `unblock_contact_use_case.dart` | YES | Good |
| 21 | Archive contact | `archive_contact_use_case.dart` | YES | Good |
| 22 | Unarchive contact | `unarchive_contact_use_case.dart` | YES | Good |
| 23 | Delete contact | `delete_contact_use_case.dart` | YES | Good |

---

## Category 5: Encryption

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| 24 | ML-KEM key generation | bridge / identity generation path | YES | Good |
| 25 | ML-KEM public key exchange | `send_contact_request_use_case.dart` | YES | Good |
| 26 | Encrypt message (v2) | `send_chat_message_use_case.dart` | YES | Good |
| 27 | Decrypt message (v2) | `handle_incoming_chat_message_use_case.dart` | YES | Good |
| 28 | V1 plaintext fallback | send + handle paths | YES | Partial |
| 29 | Encrypt reaction (v2 only) | `send_reaction_use_case.dart` | YES | Good |
| 30 | Decrypt reaction (v2 only) | `handle_incoming_reaction_use_case.dart` | YES | Good |
| 31 | Encrypt contact request | `send_contact_request_use_case.dart` | YES | Good |
| 32 | Decrypt contact request | `handle_incoming_message_use_case.dart` | YES | Good |
| 33 | Sign contact request | `send_contact_request_use_case.dart` | YES | Good |
| 34 | Verify contact request signature | `handle_incoming_message_use_case.dart` | YES | Good |

---

## Category 6: Media Handling

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| — | Image compression | `image_processor.dart` | YES | Good |
| — | EXIF stripping | `image_processor.dart` | YES | Partial |
| — | Persistent media directory | upload/download paths | YES | Good |
| — | Media stable-ID contract (retry) | retry upload paths | YES | Good |
| — | Waveform generation (audio) | voice-message send path | YES | Partial |
| — | Optimistic upload persistence | conversation + retry flows | YES | Good |

---

## Category 7: Notifications

| # | Use Case | File | Test | Quality |
|---|----------|------|------|---------|
| — | Local notification on message | chat listener / push flow | YES | Good |
| — | Suppress if viewing conversation | active conversation tracker | YES | Partial |
| — | Suppress if archived/blocked | chat listener path | YES | Good |
| — | Avatar download on message | chat listener path | YES | Partial |

---

## Missing Features (NOT IMPLEMENTED)

| # | Feature | Severity | Notes |
|---|---------|----------|-------|
| 35 | **Message deletion** | HIGH | No unsend / soft-delete / tombstone flow |
| 36 | **Message editing** | HIGH | Messages remain immutable after send |
| 37 | **Message search** | MEDIUM | No full-text search |
| 38 | **Typing indicators** | MEDIUM | No live typing signal |
| 39 | **Read receipts (per-message)** | MEDIUM | Local read state exists; sender-visible receipts do not |
| 40 | **Mute conversation** | MEDIUM | Archive is not the same as mute |
| 41 | **Contact presence surfaced in UI** | MEDIUM | Low-level connectivity exists, but product binding is limited |
| 42 | **Voice/video calls** | LOW | Voice messages exist; real-time calling does not |
| 43 | **URL preview/unfurl** | LOW | No preview cards |
| 44 | **Message pinning** | LOW | No 1:1 pin flow |
| 45 | **Thread replies UI** | LOW | Quote exists, thread view does not |
| 46 | **Auto-download settings** | LOW | No WiFi-only / policy control |
| 47 | **Persistent message drafts** | LOW | Drafts are not a durable cross-restart feature |
| 48 | **Encryption status indicator** | LOW | No product-facing v1/v2 indicator |

---

## Verdict

**The 1:1 system is strong for core messaging, retry/recovery, encryption,
contact management, and media handling.** The earlier feed-inline durable-send
gap, the sender-visible reuse transport-label mismatch, and the broader
direct-vs-relay transport-truth seam for new Go-backed 1:1 rows are now
closed, and the medium-priority operability follow-ups from report `08` around
decrypt-failure visibility and media-download dedup are also landed in the
current Flutter tree. The remaining gaps are mostly product features such as
deletion, editing, search, typing, and read receipts, plus narrower residual
edge cases like local-file-missing retry behavior. Legacy `reuse` rows remain
an intentional old-row fallback rather than an active correctness gap.
