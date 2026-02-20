# Media Transfer — Go Relay Server Spec

**Protocol:** `/mknoon/media/1.0.0`
**File:** `go-relay-server/media.go`
**Depends on:** existing inbox protocol for message references, existing ML-KEM + AES-256-GCM encryption

---

## Overview

Media (images, video, audio, files) is transferred as encrypted blobs through the relay server. The server is a dumb pipe — it stores and serves opaque encrypted bytes. All compression and encryption happen client-side before upload. The server never sees or processes the original content.

---

## Quality Tiers (Client-Side, Before Encryption)

Users choose a tier before sending. The server is unaware of which tier was used.

### Standard (default)

Reduces file size for faster transfer. Applied **before** encryption.

| Media type | Processing | Typical result |
|---|---|---|
| **Image** | Resize longest edge to 2048px, JPEG quality 85% | 5 MB photo → ~800 KB |
| **Video** | Transcode H.264, 720p, 30fps, ~2 Mbps bitrate | 350 MB 4K clip → ~15 MB |
| **Audio** | No compression — sent as-is | Unchanged |

Audio is excluded from compression. Voice messages are already small (Opus/AAC). Music and audio files should preserve original quality.

### Original

No processing. The raw file is encrypted and uploaded as-is. User explicitly opts in, understanding upload will be slower and use more data.

| Media type | Processing |
|---|---|
| **Image** | None |
| **Video** | None |
| **Audio** | None |

---

## Size Limits

| Constant | Value | Rationale |
|---|---|---|
| `maxMediaSize` | **100 MB** | Matches WhatsApp/Signal general limit. Covers 99% of photos and reasonable-length video |
| `maxMediaPerPeer` | **50** | Pending blobs per recipient before oldest are pruned |
| `mediaTTL` | **7 days** | Same as inbox message TTL. Unclaimed blobs are deleted |

---

## Storage

Blobs are written to disk, not held in memory.

```
/data/media/
  └── <recipientPeerId>/
      └── <uuid>.enc          ← opaque encrypted bytes
```

- Directory created on first upload per recipient
- Cleanup goroutine runs every 10 minutes, deletes expired blobs
- Disk usage exposed via `[STATS]` log line: `media_blobs=N media_disk_mb=N`

---

## Protocol — Stream Framing

Uses the same 4-byte big-endian length-prefixed framing as the inbox protocol for the JSON control messages. The media payload itself is streamed as raw bytes (no framing) after the control exchange.

```
Client → Server:  [4-byte len][JSON header]  then  [raw bytes stream]
Server → Client:  [4-byte len][JSON response]
```

For downloads, the server streams raw bytes back after the JSON response.

---

## Protocol — Actions

### 1. Upload

Client sends a JSON header, then streams the encrypted bytes.

**Request header:**
```json
{
  "action": "upload",
  "id": "<uuid-v4>",
  "to": "<recipientPeerId>",
  "size": 3200000,
  "mime": "image/jpeg"
}
```

**Server behavior:**
1. Validate `size` ≤ `maxMediaSize` (reject with error if exceeded)
2. Check `maxMediaPerPeer` for recipient (prune oldest if exceeded)
3. Create file at `/data/media/<to>/<id>.enc`
4. Read exactly `size` bytes from stream, write to file
5. If bytes received ≠ `size`, delete partial file, return error
6. Write metadata to in-memory index (id, to, mime, size, createdAt)

**Response:**
```json
{
  "status": "OK",
  "id": "<uuid>"
}
```

**Error responses:**
```json
{ "status": "ERROR", "error": "file too large: 150000000 > 104857600" }
{ "status": "ERROR", "error": "size mismatch: received 1024, expected 3200000" }
```

### 2. Download

Client requests a blob by ID. Server streams it back.

**Request:**
```json
{
  "action": "download",
  "id": "<uuid>"
}
```

**Server behavior:**
1. Look up blob by ID, verify the requesting peer matches the `to` field
2. If not found or not authorized, return error
3. Send JSON response with metadata
4. Stream raw encrypted bytes from disk

**Response (before byte stream):**
```json
{
  "status": "OK",
  "id": "<uuid>",
  "mime": "image/jpeg",
  "size": 3200000
}
```

Then server writes `size` raw bytes to the stream.

**Error:**
```json
{ "status": "ERROR", "error": "not found" }
{ "status": "ERROR", "error": "not authorized" }
```

### 3. Delete

Explicitly remove a blob after successful download.

**Request:**
```json
{
  "action": "delete",
  "id": "<uuid>"
}
```

**Server behavior:**
1. Verify requesting peer matches `to` field
2. Delete file from disk and metadata from index

**Response:**
```json
{ "status": "OK" }
```

### 4. List

Check what blobs are pending for the requesting peer.

**Request:**
```json
{
  "action": "list"
}
```

**Response:**
```json
{
  "status": "OK",
  "blobs": [
    { "id": "<uuid>", "from": "<senderPeerId>", "mime": "image/jpeg", "size": 3200000, "created_at": 1708000000000 },
    { "id": "<uuid>", "from": "<senderPeerId>", "mime": "video/mp4", "size": 52000000, "created_at": 1708000060000 }
  ]
}
```

---

## Message Integration

Media is referenced in normal chat messages via the existing inbox/P2P message protocol. The media blob is uploaded first, then the message is sent with a reference.

### Wire format — media reference in message payload

```json
{
  "type": "chat_message",
  "version": "2",
  "senderPeerId": "12D3KooW...",
  "encrypted": {
    "kem": "...",
    "ciphertext": "...",
    "nonce": "..."
  }
}
```

**Decrypted payload (inside ciphertext):**
```json
{
  "id": "msg-uuid-v4",
  "text": "Check out this photo",
  "senderPeerId": "12D3KooW...",
  "senderUsername": "Alex",
  "timestamp": "2026-02-20T12:34:56.789Z",
  "media": {
    "id": "media-uuid-v4",
    "node": "12D3KooWGMYM...",
    "mime": "image/jpeg",
    "size": 3200000
  }
}
```

The `media` field is optional. When present, the recipient downloads the blob from the specified `node` peer ID using the media protocol.

The `node` field defaults to the relay server's peer ID today. When users run their own nodes in the future, this field points to whichever node hosts the blob.

---

## Send Flow (Client-Side)

```
1. User picks media from gallery
2. Apply quality tier (standard: resize/transcode, original: no-op)
   — Audio is never compressed regardless of tier
3. Encrypt processed bytes (ML-KEM + AES-256-GCM, per-recipient)
4. Open /mknoon/media/1.0.0 stream to relay
5. Upload encrypted blob → get back blob ID
6. Build chat message with media reference (blob ID, node, mime, size)
7. Send message via existing path (direct P2P → relay → inbox fallback)
```

## Receive Flow (Client-Side)

```
1. Receive chat message (via P2P stream, inbox retrieve, or push wake)
2. Decrypt message → see media reference
3. Open /mknoon/media/1.0.0 stream to node specified in media.node
4. Download encrypted blob by ID
5. Decrypt blob
6. Cache to local storage
7. Display in conversation (thumbnail → full resolution)
8. (Optional) Send delete action to server to free disk
```

---

## Go Server — Data Structures

```go
const (
    MediaProtocol    = "/mknoon/media/1.0.0"
    maxMediaSize     = 100 * 1024 * 1024  // 100 MB
    maxMediaPerPeer  = 50
    mediaTTL         = 7 * 24 * time.Hour
    mediaCleanupInterval = 10 * time.Minute
    mediaDataDir     = "/data/media"
)

type mediaMeta struct {
    ID        string `json:"id"`
    From      string `json:"from"`
    To        string `json:"to"`
    Mime      string `json:"mime"`
    Size      int64  `json:"size"`
    CreatedAt int64  `json:"created_at"`
}

type MediaStore struct {
    mu      sync.RWMutex
    index   map[string]*mediaMeta   // blob ID → metadata
    byPeer  map[string][]string     // recipient peerId → list of blob IDs
    dataDir string
}
```

---

## Stats Integration

The unified `logStatsPeriodically` in `main.go` adds:

```
[STATS] conns=4 ... media_blobs=12 media_disk_mb=847 active_media_streams=3
```

New atomic counter:
```go
var activeMediaStreams atomic.Int64
```

`MediaStore.Stats()` returns blob count and total disk usage.

---

## Scaling Path

| Phase | Storage | Notes |
|---|---|---|
| **Focus group (now)** | Local EBS disk on EC2 | Simple, no extra infra. 20-50 GB is plenty |
| **Growth** | Swap disk backend to S3 | Same protocol, change `MediaStore` internals to `PutObject`/`GetObject`. No client changes |
| **User-chosen nodes** | Each user points `media.node` to their preferred node | Protocol is identical. Relay is just the default node. Users who self-host store their own blobs |

---

## Files to Create/Modify

| File | Change |
|---|---|
| `go-relay-server/media.go` | **New.** `MediaStore`, `HandleMediaStream`, upload/download/delete/list handlers, cleanup goroutine |
| `go-relay-server/main.go` | Register `/mknoon/media/1.0.0` stream handler, wire `MediaStore` into DI, add media stats to `logStatsPeriodically` |
| `go-relay-server/inbox.go` | No changes — media references travel as normal message payloads |
| `go-relay-server/rendezvous.go` | No changes |
