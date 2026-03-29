# Media Transfer — Flutter Client Spec

**Companion to:** `media-server-spec.md` (Go relay server protocol)
**Consumes:** UI-9 `spec-card-1on1.md` (card display layer — grid layouts, thumbnails, preview text)

This spec covers the plumbing: picking, compressing, encrypting, uploading, downloading, caching, and wiring media into the existing architecture. The UI-9 card spec covers rendering.

---

## Quality Tiers

The user chooses a tier before sending. Default is Standard.

### Standard (default)

| Media type | Processing | Output |
|---|---|---|
| **Image** | Resize longest edge to 2048px, JPEG quality 85% | ~800 KB from a 5 MB photo |
| **Video** | H.264, 720p, 30fps, ~2 Mbps | ~15 MB from a 350 MB 4K clip |
| **Audio** | No compression | Unchanged |

### Original

No processing. File is encrypted and uploaded as-is.

Tier selection is **per-send**, not a global setting. A small toggle (e.g. "HD" pill) appears in the media preview before send. Default is Standard. Audio always sends as original regardless of tier.

---

## Data Models

### MediaAttachment (wire format)

**New file:** `lib/features/conversation/domain/models/media_attachment.dart`

Lives inside the decrypted message payload alongside text. This is the reference that tells the recipient where to download the blob.

```dart
class MediaAttachment {
  final String id;          // UUID v4 — matches blob ID on server
  final String node;        // Peer ID of the node hosting the blob
  final String mime;        // e.g. "image/jpeg", "video/mp4", "audio/aac"
  final int size;           // Encrypted blob size in bytes
  final int? width;         // Original width (images/video only)
  final int? height;        // Original height (images/video only)
  final double? duration;   // Seconds (video/audio only)
  final String? blurhash;   // Placeholder blur hash for progressive loading
  final String? thumbnail;  // Base64-encoded JPEG thumbnail (≤ 10 KB)

  Map<String, dynamic> toJson();
  static MediaAttachment? fromJson(Map<String, dynamic> json);
}
```

The `thumbnail` field is a small base64 JPEG (≤ 10 KB, ~100px wide) embedded directly in the message. It travels with the text message through inbox/P2P — no extra download needed for the preview. The full-resolution blob is downloaded separately via the media protocol.

### Wire format — message payload with media

The `media` field is added to `MessagePayload` as optional. Existing text-only messages are unaffected.

**Decrypted inner JSON (inside v2 ciphertext):**
```json
{
  "id": "msg-uuid",
  "text": "Check out this view",
  "senderPeerId": "12D3KooW...",
  "senderUsername": "Alex",
  "timestamp": "2026-02-20T12:34:56.789Z",
  "quotedMessageId": null,
  "media": [
    {
      "id": "blob-uuid-1",
      "node": "12D3KooWGMYM...",
      "mime": "image/jpeg",
      "size": 820000,
      "width": 2048,
      "height": 1536,
      "blurhash": "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
      "thumbnail": "/9j/4AAQSkZJRg..."
    }
  ]
}
```

`media` is an array — supports multi-image sends. When `text` is empty and `media` is present, it's a media-only message. When both are present, `text` is the caption.

### Changes to MessagePayload

**File:** `lib/features/conversation/domain/models/message_payload.dart`

Add an optional `media` field:

```dart
class MessagePayload {
  // ... existing fields ...
  final List<MediaAttachment>? media;  // NEW — null for text-only messages

  // Update toInnerJson() to include media
  // Update fromDecryptedJson() to parse media
  // Update fromJson() (v1) to parse media
  // Update toJson() (v1) to include media
}
```

### Changes to ConversationMessage

**File:** `lib/features/conversation/domain/models/conversation_message.dart`

No changes to the model itself. Media metadata lives in a separate table linked by `message_id`. The `ConversationMessage` stays focused on the message row.

### MediaRecord (local persistence)

**New file:** `lib/features/conversation/domain/models/media_record.dart`

Represents a row in the local `media_attachments` table.

```dart
class MediaRecord {
  final String id;              // Blob UUID (same as MediaAttachment.id)
  final String messageId;       // FK to messages.id
  final String contactPeerId;   // For cleanup when deleting conversation
  final String node;            // Hosting node peer ID
  final String mime;            // MIME type
  final int size;               // Encrypted blob size
  final int? width;
  final int? height;
  final double? duration;
  final String? blurhash;
  final String? thumbnail;      // Base64 thumbnail
  final String? localPath;      // Path to decrypted file on disk (null = not downloaded)
  final String uploadStatus;    // 'pending' | 'uploading' | 'uploaded' | 'failed'
  final String downloadStatus;  // 'none' | 'downloading' | 'downloaded' | 'failed'
  final String createdAt;

  factory MediaRecord.fromMap(Map<String, dynamic> map);
  Map<String, dynamic> toMap();
}
```

---

## Database Migration

**New file:** `lib/core/database/migrations/010_media_attachments.dart`

DB version bumps from 9 → 10.

```sql
CREATE TABLE IF NOT EXISTS media_attachments (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL,
  contact_peer_id TEXT NOT NULL,
  node TEXT NOT NULL,
  mime TEXT NOT NULL,
  size INTEGER NOT NULL,
  width INTEGER,
  height INTEGER,
  duration REAL,
  blurhash TEXT,
  thumbnail TEXT,
  local_path TEXT,
  upload_status TEXT NOT NULL DEFAULT 'pending',
  download_status TEXT NOT NULL DEFAULT 'none',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_media_message ON media_attachments(message_id);
CREATE INDEX IF NOT EXISTS idx_media_contact ON media_attachments(contact_peer_id);
CREATE INDEX IF NOT EXISTS idx_media_upload ON media_attachments(upload_status);
CREATE INDEX IF NOT EXISTS idx_media_download ON media_attachments(download_status);
```

Follow the pattern in `009_quoted_message_id.dart`: check `PRAGMA table_info`, only create if not exists, emit flow events.

---

## DB Helpers

**New file:** `lib/core/database/helpers/media_db_helpers.dart`

Plain functions taking `Database db` + args (same pattern as `messages_db_helpers.dart`):

```dart
Future<void> dbInsertMediaAttachment(Database db, Map<String, dynamic> row);
Future<MediaRecord?> dbGetMediaAttachment(Database db, String id);
Future<List<MediaRecord>> dbGetMediaForMessage(Database db, String messageId);
Future<void> dbUpdateMediaUploadStatus(Database db, String id, String status);
Future<void> dbUpdateMediaDownloadStatus(Database db, String id, String status, {String? localPath});
Future<void> dbDeleteMediaForContact(Database db, String contactPeerId);
Future<List<MediaRecord>> dbGetPendingUploads(Database db, {int limit = 10});
Future<List<MediaRecord>> dbGetPendingDownloads(Database db, {int limit = 10});
```

---

## Repository

**New file:** `lib/features/conversation/domain/repositories/media_repository.dart`

```dart
abstract class MediaRepository {
  Future<void> saveAttachment(MediaRecord record);
  Future<MediaRecord?> getAttachment(String id);
  Future<List<MediaRecord>> getAttachmentsForMessage(String messageId);
  Future<void> updateUploadStatus(String id, String status);
  Future<void> updateDownloadStatus(String id, String status, {String? localPath});
  Future<void> deleteAttachmentsForContact(String contactPeerId);
  Future<List<MediaRecord>> getPendingUploads({int limit = 10});
  Future<List<MediaRecord>> getPendingDownloads({int limit = 10});
}
```

**New file:** `lib/features/conversation/infrastructure/media_repository_impl.dart`

Constructor-injected DB helper functions (same pattern as `MessageRepositoryImpl`).

---

## Bridge Commands

### New commands

Add to `_cmdMap` in `go_bridge_client.dart`:

| Dart command | Go method | Purpose |
|---|---|---|
| `media:upload` | `BridgeMediaUpload` | Upload encrypted blob to node |
| `media:download` | `BridgeMediaDownload` | Download encrypted blob from node |
| `media:delete` | `BridgeMediaDelete` | Delete blob from node after download |
| `media:list` | `BridgeMediaList` | List pending blobs for this peer |

### Command payloads

**Upload:**
```json
{
  "command": "media:upload",
  "id": "blob-uuid",
  "to": "recipientPeerId",
  "mime": "image/jpeg",
  "size": 820000,
  "filePath": "/tmp/encrypted-blob-uuid.enc"
}
```

The bridge reads the encrypted file from `filePath`, opens a `/mknoon/media/1.0.0` stream to the relay, sends the header + bytes.

Response:
```json
{ "ok": true, "id": "blob-uuid" }
```

**Download:**
```json
{
  "command": "media:download",
  "id": "blob-uuid",
  "node": "12D3KooWGMYM...",
  "outputPath": "/tmp/encrypted-blob-uuid.enc"
}
```

The bridge opens a stream to the specified node, downloads the blob, writes to `outputPath`.

Response:
```json
{ "ok": true, "id": "blob-uuid", "mime": "image/jpeg", "size": 820000 }
```

### Platform wrappers

**iOS** (`ios/Runner/GoBridge.swift`) — add cases in `handleMethodCall`:
```swift
case "mediaUpload":
    runOnBackground({ BridgeMediaUpload(args ?? "") }, result: result)
case "mediaDownload":
    runOnBackground({ BridgeMediaDownload(args ?? "") }, result: result)
case "mediaDelete":
    runOnBackground({ BridgeMediaDelete(args ?? "") }, result: result)
case "mediaList":
    runOnBackground({ BridgeMediaList(args ?? "") }, result: result)
```

**Android** (`android/.../GoBridge.kt`) — same pattern in `onMethodCall`.

### Helper functions

**File:** `lib/core/bridge/bridge.dart` — add after existing `callDecryptMessage`:

```dart
Future<Map<String, dynamic>> callMediaUpload({
  required Bridge bridge,
  required String id,
  required String toPeerId,
  required String mime,
  required int size,
  required String filePath,
});

Future<Map<String, dynamic>> callMediaDownload({
  required Bridge bridge,
  required String id,
  required String node,
  required String outputPath,
});

Future<Map<String, dynamic>> callMediaDelete({
  required Bridge bridge,
  required String id,
});

Future<Map<String, dynamic>> callMediaList({
  required Bridge bridge,
});
```

---

## File Encryption

Media encryption reuses the same ML-KEM-768 + AES-256-GCM pipeline but operates on file bytes instead of JSON strings.

### Encrypt (before upload)

1. Read processed media file into bytes
2. Call `callEncryptMessage(bridge, recipientMlKemPublicKey, base64Encode(bytes))`
3. Write the encrypted output (`kem`, `ciphertext`, `nonce`) as a single binary blob to a temp file
4. Upload the temp file via `media:upload`

**Blob format on disk:**
```
[4 bytes: kem length][kem bytes][4 bytes: nonce length][nonce bytes][ciphertext bytes]
```

This is a simple binary container. The recipient reads the lengths, splits the fields, and calls decrypt.

### Decrypt (after download)

1. Read encrypted blob from disk
2. Parse out `kem`, `nonce`, `ciphertext` using the length prefixes
3. Call `callDecryptMessage(bridge, ownMlKemSecretKey, kem, ciphertext, nonce)`
4. Base64-decode the plaintext to get original file bytes
5. Write to final cache path

### Large file consideration

The live ordinary-media transfer cap is now `5 GB`, but the current bridge
encryption/decryption path still works on whole-file payloads. That means the
repo accepts multi-gigabyte attachments at the transport and selection layers
without claiming that every device can process them cheaply in memory. A
chunked encrypt/decrypt bridge command (`media.encryptChunk` /
`media.decryptChunk`) remains the future scaling path.

---

## Send Flow

**New file:** `lib/features/conversation/application/send_media_message_use_case.dart`

Top-level function (same pattern as `sendChatMessage`).

```
sendMediaMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required MediaRepository mediaRepo,
  required Bridge bridge,
  required String targetPeerId,
  required String senderPeerId,
  required String senderUsername,
  required List<File> files,
  required String tier,                    // 'standard' | 'original'
  required String? recipientMlKemPublicKey,
  String? text,                            // Caption
  String? quotedMessageId,
})
```

### Step-by-step

```
1. VALIDATE
   - At least 1 file
   - The settled ordinary-media budget for the message stays within `5 GB`
     after the current quality-processing path runs
   - App-recorded voice messages keep their separate `100 MB` sanity limit in
     `send_voice_message_use_case.dart`; they are not redefined by this
     ordinary-media path
   - P2P node is running
   - Recipient ML-KEM public key available (required — media always encrypted)

2. PROCESS (client-side, per file)
   For each file:
   a. Read MIME type from file header
   b. If tier == 'standard':
      - Image: resize to 2048px longest edge, JPEG 85%
      - Video: transcode H.264 720p 30fps ~2Mbps
      - Audio: no-op
   c. If tier == 'original': no-op
   d. Generate thumbnail (JPEG, ~100px wide, ≤ 10 KB)
   e. Compute blurhash from thumbnail
   f. Read width/height (images: from decoded image, video: from metadata)
   g. Read duration (video/audio only)
   h. Generate blob UUID v4

3. ENCRYPT (per file)
   a. Encrypt processed file bytes with recipient's ML-KEM public key
   b. Write encrypted blob to temp file: {appTempDir}/{blobId}.enc
   c. Record encrypted size

4. PERSIST OPTIMISTICALLY
   a. Save ConversationMessage with status 'sending', text = caption
   b. Save MediaRecord per file with uploadStatus = 'pending'
   c. Notify UI — message appears immediately with local thumbnails

5. UPLOAD (per file, sequential)
   a. Call media:upload bridge command with temp file path
   b. On success: update MediaRecord.uploadStatus = 'uploaded'
   c. On failure: update MediaRecord.uploadStatus = 'failed', continue with next file
   d. Delete temp .enc file after upload

6. BUILD MESSAGE PAYLOAD
   a. Create MessagePayload with media array (MediaAttachment per file)
   b. Only include files where uploadStatus == 'uploaded'
   c. Encrypt message payload (text + media references) with recipient ML-KEM key
   d. Build v2 envelope

7. SEND MESSAGE (same retry logic as sendChatMessage)
   a. Try local WiFi
   b. Try relay with 3x retries + exponential backoff
   c. Fall back to inbox
   d. Update ConversationMessage status: 'delivered' | 'sent' | 'failed'

8. CLEANUP
   a. Delete temp .enc files
   b. If all uploads failed: update message status to 'failed'
```

### Current foreground upload contract

The live conversation and group send surfaces now provide honest
foreground-only upload protection for active relay uploads:

- aggregate byte progress is surfaced in the composer screen
- the banner warns: `Keep the app open until the upload completes`
- leaving the conversation while a relay upload is active requires explicit
  confirmation
- a wake lock stays enabled until the last active relay upload finishes, fails,
  or is cancelled

This is **not** a true background-upload architecture claim, and it does not
promise download-side wake-lock behavior.

### Result type

```dart
enum SendMediaResult {
  success,
  nodeNotRunning,
  invalidFiles,
  encryptionFailed,
  allUploadsFailed,
  partialUpload,     // Some files uploaded, others failed
  sendFailed,
}
```

Returns `(SendMediaResult, ConversationMessage?)`.

---

## Receive Flow

Receiving is handled by the existing `ChatMessageListener` pipeline. When a message has a `media` field, extra steps kick in.

### Changes to handleIncomingChatMessage

**File:** `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`

After persisting the ConversationMessage (existing step), add:

```
IF payload.media is not null and not empty:
  FOR each MediaAttachment in payload.media:
    1. Save MediaRecord with downloadStatus = 'none', localPath = null
    2. Store thumbnail from payload (already in message, no download needed)
  Notify UI — message renders immediately with thumbnails/blurhash
```

No changes to the use case return type. The download happens asynchronously after.

### Media Download Service

**New file:** `lib/core/services/media_download_service.dart`

A service that runs in the background, processing pending downloads.

```dart
class MediaDownloadService {
  final MediaRepository mediaRepo;
  final Bridge bridge;
  final String ownMlKemSecretKey;

  /// Called when a new message with media arrives, and periodically on app resume.
  Future<void> processPendingDownloads();

  /// Downloads and decrypts a single media blob.
  Future<bool> downloadAndDecrypt(MediaRecord record);
}
```

### Download step-by-step (per blob)

```
1. Update downloadStatus = 'downloading'
2. Call media:download bridge command
   - node = record.node
   - id = record.id
   - outputPath = {appTempDir}/{id}.enc
3. If download fails: update downloadStatus = 'failed', return
4. Decrypt blob:
   a. Read encrypted blob from outputPath
   b. Parse kem, nonce, ciphertext
   c. Call callDecryptMessage with own ML-KEM secret key
   d. Write decrypted bytes to cache: {appCacheDir}/media/{contactPeerId}/{id}.{ext}
5. Update downloadStatus = 'downloaded', localPath = cache path
6. Delete temp .enc file
7. Notify UI — replace thumbnail/blurhash with full image
8. (Optional) Call media:delete to free server disk
```

### Triggering downloads

| Trigger | What happens |
|---|---|
| **Message received** | Immediately queue download for visible media |
| **App resume / warm background** | `processPendingDownloads()` — picks up any `none` or `failed` downloads |
| **User scrolls to message** | If `downloadStatus == 'none'`, trigger on-demand |
| **Manual retry** | User taps "Retry" on failed download |

### Auto-download rules

| Condition | Auto-download? |
|---|---|
| Image ≤ 5 MB | Yes |
| Image > 5 MB | Yes on WiFi, prompt on cellular |
| Video ≤ 15 MB | Yes on WiFi, prompt on cellular |
| Video > 15 MB | Always prompt ("Tap to download · 47 MB") |
| Audio ≤ 5 MB | Yes |
| Audio > 5 MB | Prompt |

For the focus group: auto-download everything. Add the conditional logic when cellular usage matters.

---

## Local Cache

### Directory structure

```
{appDocumentsDir}/media/
  └── {contactPeerId}/
      ├── {blobId}.jpg
      ├── {blobId}.mp4
      └── {blobId}.aac
```

Using `appDocumentsDir` (not `appCacheDir`) so media persists across app updates and isn't evicted by the OS.

### Cache management

- **Per-contact cleanup:** When a conversation is deleted (`dbDeleteMediaForContact`), delete the contact's media directory
- **Total cache size:** Track via `MediaRepository.totalCacheSize()`. Display in settings.
- **Manual clear:** Settings → Storage → "Clear media cache" — deletes all local files, resets `downloadStatus` to `none`, keeps metadata so thumbnails still render
- **No automatic eviction** for the focus group. Add LRU eviction later when storage becomes a concern.

---

## Image Processing

For the Standard tier, image resizing runs client-side before encryption.

### Implementation

Use Flutter's `dart:ui` (or `image` package) for resize:

```dart
Future<File> processImageStandard(File input) async {
  // 1. Decode image
  // 2. If longest edge > 2048: resize proportionally to 2048px
  // 3. Re-encode as JPEG quality 85%
  // 4. Write to temp file
  // Return temp file
}
```

### Thumbnail generation

```dart
Future<String> generateThumbnail(File imageFile) async {
  // 1. Decode image
  // 2. Resize to ~100px wide (proportional)
  // 3. Encode as JPEG quality 60%
  // 4. Base64 encode
  // 5. Verify ≤ 10 KB (reduce quality if needed)
  // Return base64 string
}
```

### Blurhash

Use the `blurhash_dart` package to compute a blurhash from the thumbnail. 4x3 components. The hash is a short string (~30 chars) that encodes a blurred placeholder.

---

## Video Processing

### Focus group phase

No transcoding. Send as original. Extract thumbnail and duration only:

```dart
Future<(String thumbnail, double duration, int width, int height)>
    extractVideoMetadata(File videoFile) async {
  // 1. Extract first frame as thumbnail (via video_thumbnail package or platform channel)
  // 2. Read duration from metadata
  // 3. Read dimensions from metadata
  // Return (base64Thumbnail, durationSeconds, width, height)
}
```

### Future: Standard tier transcode

Use `ffmpeg_kit_flutter` or platform VideoToolbox/MediaCodec:

```dart
Future<File> processVideoStandard(File input) async {
  // 1. Probe input dimensions and duration
  // 2. If already ≤ 720p and ≤ 2 Mbps: skip transcode
  // 3. Transcode: H.264, 720p, 30fps, ~2 Mbps, AAC audio 128kbps
  // 4. Write to temp file
  // Return temp file
}
```

Defer this. Ship original-only for video in the focus group.

---

## P2P Service Changes

**File:** `lib/core/services/p2p_service.dart` — add to interface:

```dart
/// Upload encrypted media blob to a node.
Future<bool> uploadMedia({
  required String id,
  required String toPeerId,
  required String mime,
  required int size,
  required String filePath,
});

/// Download encrypted media blob from a node.
Future<bool> downloadMedia({
  required String id,
  required String node,
  required String outputPath,
});

/// Delete a media blob from a node.
Future<bool> deleteMedia({required String id});

/// List pending media blobs for this peer.
Future<List<Map<String, dynamic>>> listMedia();
```

**File:** `lib/core/services/p2p_service_impl.dart` — implement using bridge helper calls.

---

## DI Wiring

**File:** `lib/main.dart`

Add after `MessageRepository` setup (line ~185):

```dart
// Media repository
final mediaRepo = MediaRepositoryImpl(
  insertAttachment: dbInsertMediaAttachment,
  getAttachment: dbGetMediaAttachment,
  getForMessage: dbGetMediaForMessage,
  updateUploadStatus: dbUpdateMediaUploadStatus,
  updateDownloadStatus: dbUpdateMediaDownloadStatus,
  deleteForContact: dbDeleteMediaForContact,
  getPendingUploads: dbGetPendingUploads,
  getPendingDownloads: dbGetPendingDownloads,
  db: db,
);
```

Add after `ChatMessageListener` setup (line ~230):

```dart
// Media download service
final mediaDownloadService = MediaDownloadService(
  mediaRepo: mediaRepo,
  bridge: bridge,
  ownMlKemSecretKey: ownMlKemSecretKey,
);
```

Thread through: `main.dart` → `MyApp` → `StartupRouter` → `FeedWired` → conversation screens.

---

## Progress & UI Events

### Upload progress

The bridge streams progress events via EventChannel:

```json
{ "event": "media:upload:progress", "id": "blob-uuid", "bytes": 410000, "total": 820000 }
```

Flutter side: `MediaUploadProgressStream` that the UI subscribes to for progress bars.

### Download progress

Same pattern:

```json
{ "event": "media:download:progress", "id": "blob-uuid", "bytes": 200000, "total": 820000 }
```

### UI states per media item

| State | What renders | Source |
|---|---|---|
| **Picked** | Local file preview + "Sending..." | Before upload |
| **Uploading** | Local preview + progress bar | During upload |
| **Uploaded** | Local preview + checkmark | Upload complete |
| **Upload failed** | Local preview + retry button | Upload error |
| **Received (not downloaded)** | Thumbnail/blurhash + "Tap to download · 2.3 MB" | Message received |
| **Downloading** | Thumbnail + progress bar | During download |
| **Downloaded** | Full resolution from local cache | Decrypted on disk |
| **Download failed** | Thumbnail + retry button | Download error |

---

## Flow Events

Follow existing `emitFlowEvent` pattern:

| Event | Layer | When |
|---|---|---|
| `MEDIA_SEND_START` | FL | User taps send with media |
| `MEDIA_PROCESS_START` | FL | Compression/resize begins |
| `MEDIA_PROCESS_DONE` | FL | Compression complete, includes output size |
| `MEDIA_ENCRYPT_START` | FL | Encryption begins |
| `MEDIA_ENCRYPT_DONE` | FL | Encrypted blob written to temp |
| `MEDIA_UPLOAD_START` | FL | Upload stream opened |
| `MEDIA_UPLOAD_PROGRESS` | FL | Every 25% (avoid log spam) |
| `MEDIA_UPLOAD_SUCCESS` | FL | Blob accepted by server |
| `MEDIA_UPLOAD_FAILED` | FL | Upload error |
| `MEDIA_SEND_SUCCESS` | FL | Message with media refs sent |
| `MEDIA_SEND_FAILED` | FL | All retries exhausted |
| `MEDIA_DOWNLOAD_START` | FL | Download stream opened |
| `MEDIA_DOWNLOAD_PROGRESS` | FL | Every 25% |
| `MEDIA_DOWNLOAD_SUCCESS` | FL | Blob downloaded |
| `MEDIA_DOWNLOAD_FAILED` | FL | Download error |
| `MEDIA_DECRYPT_START` | FL | Decryption begins |
| `MEDIA_DECRYPT_DONE` | FL | Decrypted file written to cache |

---

## Error Handling

| Failure | Behavior |
|---|---|
| **Compression fails** | Skip compression, fall back to original. Log warning. |
| **Encryption fails** | Abort send entirely. Media must always be encrypted. |
| **Upload fails (network)** | Retry 3x with backoff. Then mark `upload_status = 'failed'`. User sees retry button. |
| **Upload fails (size rejected)** | Show an over-limit error for the settled `5 GB` ordinary-media budget. Don't retry. |
| **Message send fails but uploads succeeded** | Blobs are on server. Retry message send (inbox fallback). Blobs have 7-day TTL. |
| **Download fails (network)** | Mark `download_status = 'failed'`. User sees retry. Auto-retry on next app resume. |
| **Download fails (blob expired)** | Show "Media no longer available" in place of thumbnail. |
| **Decryption fails** | Log error. Show "Unable to decrypt" placeholder. Likely key mismatch — don't retry. |
| **Disk full** | Check available space before download. Show "Not enough storage" if < blob size + 50 MB buffer. |

---

## Files Summary

| File | Status | Purpose |
|---|---|---|
| `lib/features/conversation/domain/models/media_attachment.dart` | **New** | Wire format model (in message payload) |
| `lib/features/conversation/domain/models/media_record.dart` | **New** | Local persistence model (DB row) |
| `lib/features/conversation/domain/models/message_payload.dart` | **Modify** | Add optional `media` field |
| `lib/features/conversation/domain/repositories/media_repository.dart` | **New** | Repository interface |
| `lib/features/conversation/infrastructure/media_repository_impl.dart` | **New** | Repository implementation |
| `lib/core/database/migrations/010_media_attachments.dart` | **New** | DB migration |
| `lib/core/database/helpers/media_db_helpers.dart` | **New** | DB helper functions |
| `lib/features/conversation/application/send_media_message_use_case.dart` | **New** | Send orchestration |
| `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` | **Modify** | Parse media from payload, save MediaRecords |
| `lib/core/services/media_download_service.dart` | **New** | Background download + decrypt |
| `lib/core/services/p2p_service.dart` | **Modify** | Add media methods to interface |
| `lib/core/services/p2p_service_impl.dart` | **Modify** | Implement media methods |
| `lib/core/bridge/bridge.dart` | **Modify** | Add media helper functions |
| `lib/core/bridge/go_bridge_client.dart` | **Modify** | Add media commands to `_cmdMap` |
| `ios/Runner/GoBridge.swift` | **Modify** | Add media method cases |
| `android/.../GoBridge.kt` | **Modify** | Add media method cases |
| `lib/main.dart` | **Modify** | Wire MediaRepository + MediaDownloadService |

---

## Implementation Order

1. **Models + migration** — `MediaAttachment`, `MediaRecord`, migration 010
2. **DB helpers + repository** — persistence layer
3. **MessagePayload changes** — add `media` field to wire format
4. **Bridge commands** — Go side first (`go-mknoon/`), then platform wrappers, then Dart helpers
5. **Send use case** — pick → process → encrypt → upload → send message
6. **Receive changes** — parse media from payload, save records
7. **Download service** — background download + decrypt + cache
8. **DI wiring** — thread everything through main.dart
9. **UI integration** — connect to card spec rendering (UI-9)
