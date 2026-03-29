# 22 - Media Transfer Size Limit Increase (100 MB -> 5 GB)

## Problem

The app offers users a setting to send media in either **compressed** or **original** quality. However, the maximum media transfer size is hardcoded to **100 MB** across the entire stack. This creates a contradiction: users who choose "Original" quality expect to send their raw media files, but the 100 MB cap silently prevents large files from being transferred.

### Impact by media type

| Media Type | Typical Size (Original) | Fits in 100 MB? |
|---|---|---|
| Photo (HEIC) | 2-5 MB | Yes |
| Photo (ProRAW) | 25-50 MB | Yes |
| Video 1080p@30fps | ~60 MB/min | ~1.5 min max |
| Video 4K@30fps | ~170 MB/min | ~35 sec max |
| Video 4K@60fps | ~400 MB/min | ~15 sec max |

A user who explicitly selects "Original" video quality can only send **15-35 seconds of 4K video** before hitting the limit. This is a poor experience and undermines the purpose of the quality setting.

### Current limits (all hardcoded to 100 MB)

| Location | File | Code |
|---|---|---|
| Relay server | `go-relay-server/media.go:20` | `maxMediaSize = 100 * 1024 * 1024` |
| Local media server | `lib/core/local_discovery/local_media_server.dart:43` | `static const int maxFileSize = 100 * 1024 * 1024` |
| Voice message use case | `lib/features/conversation/application/send_voice_message_use_case.dart:20` | `const _maxFileSizeBytes = 100 * 1024 * 1024` |

## Solution

Raise the media transfer size cap from **100 MB to 5 GB** for general media (images, videos, audio files sent as attachments). Voice messages recorded by the app itself are excluded from this change -- they are short recordings that remain well within the current 100 MB limit.

### Changes required

#### 1. Relay server (`go-relay-server/media.go`)

Update `maxMediaSize` from 100 MB to 5 GB:

```go
// Before
maxMediaSize = 100 * 1024 * 1024 // 100 MB

// After
maxMediaSize = 5 * 1024 * 1024 * 1024 // 5 GB
```

Consider storage and bandwidth implications on the relay server. The relay server's per-peer storage cap and TTL cleanup should be reviewed to ensure they can handle larger blobs without disk exhaustion.

#### 2. Local media server (`lib/core/local_discovery/local_media_server.dart`)

Update `maxFileSize` from 100 MB to 5 GB:

```dart
// Before
static const int maxFileSize = 100 * 1024 * 1024; // 100 MB

// After
static const int maxFileSize = 5 * 1024 * 1024 * 1024; // 5 GB
```

#### 3. Voice message use case -- NO CHANGE

The voice message limit in `send_voice_message_use_case.dart` stays at **100 MB**. This limit applies only to audio recordings made by the app's built-in recorder, which produce small files (typically under 1 MB per minute). This is not a media attachment limit -- it is a sanity check for the app's own recordings.

Audio files sent as media attachments (e.g., a user picking an audio file from their library) go through the general media path and benefit from the 5 GB limit.

#### 4. Over-limit warning at pick time (new)

When a user selects media that would cause the total attachments for a single message to exceed 5 GB, show a warning dialog **before** sending:

> "The attached media is X MB and exceeds the 5 GB limit. Would you like to compress and send, or cancel?"

This applies to:
- A single file exceeding 5 GB
- Multiple files (any mix of images, videos, audio) whose combined size exceeds 5 GB

The dialog should offer:
- **Compress**: Re-encode the attached media using the compressed quality setting and re-check the size
- **Cancel**: Return to the composer without attaching the file(s) that caused the overflow

This check runs at **attach time** (when the user selects media from gallery or camera), not at send time, so the user gets immediate feedback. The warning refers to the "attached" media -- which may be a single large file or multiple files of mixed types (images, videos, audio) whose combined size exceeds the limit.

### 5. Compression enforcement when "Compressed" is selected

When the user has selected "Compressed" in settings, the app must ensure that **all media is compressed before the size check**. The flow is:

1. User attaches media (image, video, or audio from library)
2. App reads the quality preference from SecureKeyStore
3. If preference is **Compressed**: process the media (quality 85 for images, MediumQuality for video) **first**, then check the resulting size against the 5 GB limit
4. If preference is **Original**: skip compression, check the raw file size against the 5 GB limit

This means the 5 GB warning dialog should rarely appear for users with "Compressed" selected, since compression significantly reduces file sizes. The dialog is primarily relevant for "Original" quality users.

### 6. Upload progress UX and screen wake lock

When uploading large media files, the app currently requires the user to keep it in the foreground. iOS suspends apps approximately 30 seconds after backgrounding, and Android is similarly aggressive with background process limits. For multi-gigabyte uploads, this means the transfer will stall or fail if the user locks their phone or switches to another app.

Two mechanisms are needed to handle this:

#### 6a. Upload progress banner with foreground warning

While a media upload is in progress, display a persistent progress banner at the top of the conversation screen. The banner should show:

- A progress bar indicating bytes transferred out of total bytes (e.g., "1.2 GB / 3.8 GB")
- A text warning: "Keep the app open until the upload completes"
- The banner remains visible until the upload succeeds, fails, or is cancelled

If the user attempts to navigate away from the conversation while an upload is active, show a confirmation dialog: "An upload is in progress. Leaving may interrupt it. Are you sure?"

#### 6b. Screen wake lock during upload

To prevent the phone from dimming the screen and auto-locking during a large upload, use a wake lock (e.g., the `wakelock_plus` Flutter package):

- Enable the wake lock when a media upload begins (any upload, not just large ones -- the overhead is negligible and the protection is valuable)
- Disable the wake lock when the upload completes, fails, or is cancelled
- No special permissions are required on either iOS or Android
- The wake lock keeps the screen on and prevents the OS from suspending the app due to inactivity
- If multiple uploads are active (e.g., 10 attachments uploading in sequence), the wake lock remains enabled until the last upload finishes

This does not guarantee the app stays alive if the user explicitly backgrounds it, but it prevents the common case of the phone auto-locking in the user's hand or on a table while a long upload runs.

## Scope clarification

| Media type | New limit | Notes |
|---|---|---|
| Images (picked from gallery/camera) | 5 GB | Applies to all image formats |
| Videos (picked from gallery/camera) | 5 GB | Applies to all video formats |
| Audio files (picked as attachment) | 5 GB | Audio files from user's library |
| Voice messages (recorded in-app) | 100 MB (unchanged) | App's built-in recorder only |
| Profile avatars | 512 KB (unchanged) | Server-enforced, separate path |
| Repost avatars | 64 KB (unchanged) | Separate path |

## Test cases

### Relay server

- TC-RS-01: Upload a media blob of exactly 5 GB -- should succeed.
- TC-RS-02: Upload a media blob of 5 GB + 1 byte -- should be rejected with a size error response.
- TC-RS-03: Upload a media blob of 500 MB -- should succeed (regression: existing sizes still work).
- TC-RS-04: Upload a media blob of 50 MB -- should succeed (regression: typical compressed video size).
- TC-RS-05: Upload a media blob of 1 byte -- should succeed (minimum valid size).
- TC-RS-06: Upload a media blob of 0 bytes -- should be rejected (invalid size).
- TC-RS-07: Upload a 2 GB blob, then download it -- downloaded file should match the source file byte-for-byte (checksum comparison).
- TC-RS-08: Upload 3 blobs of 2 GB each for the same peer -- verify per-peer storage cap behavior (oldest blob should be evicted or upload rejected depending on cap policy).
- TC-RS-09: Upload a 1 GB blob, wait for TTL to expire -- verify the blob is cleaned up and disk space is reclaimed.
- TC-RS-10: Upload a 3 GB blob while another upload for the same peer is already in progress -- verify both complete without corruption or interference.
- TC-RS-11: Start uploading a 2 GB blob, kill the connection at 50% -- verify the relay does not retain a partial/corrupt blob (no orphaned data).

### Local media server

- TC-LM-01: Offer a media file of exactly 5 GB -- should be accepted.
- TC-LM-02: Offer a media file of 5 GB + 1 byte -- should be rejected with `LOCAL_MEDIA_OFFER_REJECTED_SIZE` flow event.
- TC-LM-03: Offer a media file of 200 MB -- should succeed (regression: typical file size).
- TC-LM-04: Offer a media file of 0 bytes -- should be rejected.
- TC-LM-05: Transfer a 1 GB video over local discovery -- should complete and the received file should match the source checksum.
- TC-LM-06: Attempt to push a file exceeding 5 GB via HTTP -- should return `413 Request Entity Too Large`.
- TC-LM-07: Transfer a 500 MB file over local discovery while Wi-Fi is slow -- verify transfer completes without timeout and file is not corrupted.
- TC-LM-08: Start a 1 GB local transfer, disconnect Wi-Fi mid-transfer -- verify partial file is cleaned up on the receiver side (no corrupt file left behind).

### Voice message (unchanged -- regression)

- TC-VM-01: Record a 30-second voice message (typical ~500 KB) and send -- should succeed.
- TC-VM-02: Record a 10-minute voice message (~5 MB) and send -- should succeed.
- TC-VM-03: Simulate a voice message recording exceeding 100 MB -- should be rejected by the voice message size check.
- TC-VM-04: Verify that the voice message size limit constant in `send_voice_message_use_case.dart` is still 100 MB (has NOT been changed to 5 GB).
- TC-VM-05: Pick an audio file from the user's library (not a voice recording) that is 200 MB -- should go through the general media path and succeed (not blocked by the 100 MB voice message limit).

### Attach-time warning dialog

- TC-PW-01: Attach a single video file of 6 GB in 1:1 conversation -- warning dialog should appear: "The attached media is X GB and exceeds the 5 GB limit."
- TC-PW-02: Attach a single video file of 4 GB in 1:1 conversation -- no warning, file attaches normally.
- TC-PW-03: Attach a single video file of exactly 5 GB -- no warning (5 GB is the limit, not over it).
- TC-PW-04: Attach multiple files (2 images + 1 video) totaling 5.5 GB in 1:1 conversation -- warning dialog should appear when the file that pushes the total over 5 GB is attached.
- TC-PW-05: Attach multiple files (3 images + 2 videos) totaling 3 GB in 1:1 conversation -- no warning.
- TC-PW-06: In the warning dialog, tap "Compress" -- the overflow file(s) should be re-encoded at compressed quality and total size re-checked against 5 GB.
- TC-PW-07: In the warning dialog, tap "Cancel" -- return to composer, the overflow file is not attached, all previously attached files remain intact.
- TC-PW-08: Attach a single raw panorama image of 6 GB -- warning dialog should appear (not just videos trigger this).
- TC-PW-09: Attach a single audio file from the user's library (not a voice message) of 6 GB -- warning dialog should appear.
- TC-PW-10: Attach a video file of 6 GB in a group conversation -- warning dialog should appear (same behavior as 1:1).
- TC-PW-11: After compressing via the dialog, the compressed file is still over 5 GB -- show an error message indicating the media is too large even after compression.
- TC-PW-12: Attach 3 videos (2 GB each) -- warning dialog should appear on the 3rd video since combined total (6 GB) exceeds the limit.
- TC-PW-13: Attach 1 image (1 GB) + 1 video (4.5 GB) -- warning dialog should appear on the video since combined total (5.5 GB) exceeds the limit.
- TC-PW-14: Attach 2 files totaling 5.5 GB, then remove 1 file so total drops to 3 GB, then attach a new 1.5 GB file (total 4.5 GB) -- no warning should appear (removal correctly reduces the running total).
- TC-PW-15: Attach 10 files (max per message) totaling 4.8 GB -- all attach without warning. Verify that hitting the attachment count limit (10) does not interfere with the size limit check.

### Compression enforcement and quality setting interaction

- TC-IQ-01: With quality set to "Original", attach and send a 500 MB video in 1:1 chat -- the video should be sent without compression, at full resolution and bitrate.
- TC-IQ-02: With quality set to "Compressed", attach and send a 500 MB video in 1:1 chat -- the video should be compressed first (MediumQuality), and the smaller compressed file is what gets uploaded.
- TC-IQ-03: With quality set to "Original", attach and send a 50 MB ProRAW photo -- should send at quality 100 with EXIF stripped. Verify the sent file size is close to the original (not re-encoded smaller).
- TC-IQ-04: With quality set to "Compressed", attach and send a 50 MB ProRAW photo -- should compress to quality 85 with EXIF stripped. Verify the sent file is significantly smaller than the original.
- TC-IQ-05: With quality set to "Original", attach a 4.9 GB video -- should attach and send without warning.
- TC-IQ-06: With quality set to "Original", attach a 5.1 GB video -- warning dialog should appear (no compression was applied, raw size exceeds limit).
- TC-IQ-07: With quality set to "Compressed", attach a 6 GB raw video -- compression runs first and produces a file under 5 GB. No warning dialog appears. The compressed version is uploaded, not the original.
- TC-IQ-08: With quality set to "Compressed", attach an exceptionally large raw video where even the compressed output exceeds 5 GB -- warning dialog appears with an error indicating the media is too large even after compression.
- TC-IQ-09: With quality set to "Compressed", attach 5 images totaling 800 MB raw -- all are compressed first. Verify the uploaded files are the compressed outputs (quality 85, EXIF stripped) and the total uploaded size is less than 800 MB.
- TC-IQ-10: With quality set to "Compressed", verify the size check runs against the **compressed** output, not the original file size. E.g., a 5.5 GB raw video that compresses to 3 GB should NOT trigger the warning dialog.
- TC-IQ-11: With quality set to "Compressed", attach a mix of 3 images and 2 videos -- verify all 5 files are compressed before the cumulative size check, and the compressed total is what is compared against 5 GB.
- TC-IQ-12: With quality set to "Compressed", attach a GIF file -- verify the GIF is treated as a processable image and handled correctly (not skipped or corrupted by compression).

### End-to-end transfer

- TC-E2E-01: Alice sends a 1 GB original-quality video to Bob via relay -- Bob receives the video, it plays correctly, and the file size matches what Alice sent.
- TC-E2E-02: Alice sends a 1 GB original-quality video to Bob via local discovery -- Bob receives the video, it plays correctly, and the file size matches what Alice sent.
- TC-E2E-03: Alice sends a 3 GB video to a group chat with 3 members -- all members receive the video and can play it.
- TC-E2E-04: Alice sends 10 attachments (max per message) of mixed types (images + videos + audio) totaling 4.5 GB -- Bob receives all 10 attachments, each file is intact and playable/viewable.
- TC-E2E-05: Alice starts uploading a 2 GB video, network drops mid-transfer -- verify the message moves to "failed" status (not stuck in "sending"), and no corrupt partial file is delivered to Bob.
- TC-E2E-06: After TC-E2E-05, Alice reopens the app -- `retryIncompleteUploads` picks up the failed upload, re-uploads the file, and completes the send successfully.
- TC-E2E-07: Alice sends a 500 MB video with quality set to "Compressed" -- Bob receives the compressed version. Verify Bob's received file is smaller than Alice's original (compression was applied sender-side).
- TC-E2E-08: Alice sends a 500 MB video with quality set to "Original" -- Bob receives the original-quality version. Verify Bob's received file size matches Alice's original.
- TC-E2E-09: Alice sends a 200 MB image to Bob -- Bob's device has only 50 MB free disk space. Verify the download fails gracefully with an appropriate error (not a crash or silent corruption).
- TC-E2E-10: Alice sends a 1 GB video (encrypted with ML-KEM v2 envelope) to Bob -- Bob decrypts and receives the full video without corruption. Verify encryption does not introduce size limits or data loss for large payloads.

### Upload retry and recovery

- TC-UR-01: Alice sends a message with a 1 GB video attachment. The upload fails mid-way. Alice backgrounds and re-opens the app -- `retryIncompleteUploads` finds the pending attachment and re-uploads it. The message is sent successfully.
- TC-UR-02: Alice sends a message with 3 attachments (500 MB each). Upload #2 fails. On app resume, retry re-uploads only the failed attachment (#2), not the already-completed ones (#1 and #3). The message is sent once with all 3 attachments.
- TC-UR-03: Alice sends a message with a 2 GB video. The upload fails 3 times (reaching `kMaxUploadRetries`). The attachment is marked as `upload_failed` (permanently failed), not retried again.
- TC-UR-04: Alice sends a message with a 1 GB video. The upload fails, then Alice deletes the original video from her photo library. On retry, the upload fails with a "no local path" error and is marked as non-retryable.
- TC-UR-05: Alice sends 2 separate messages each with a 1 GB video. Both uploads fail. On app resume, both messages are retried independently -- failure of one does not block the other.

### Receiver-side download

- TC-DL-01: Bob receives a message with a 1 GB video attachment. Bob taps the attachment -- download starts, progress is visible, and the video plays after download completes.
- TC-DL-02: Bob receives a message with a 2 GB video. Download fails mid-way (network error). Attachment status shows "failed", not "downloading" forever. Bob can tap to retry.
- TC-DL-03: Bob receives a message with a 2 GB video. Download fails and leaves a partial file on disk. Verify the partial file is cleaned up (no corrupt files accumulate in the media directory).
- TC-DL-04: Bob receives a message with 5 image attachments (200 MB each). All 5 download successfully and are viewable.
- TC-DL-05: Bob receives two messages from different contacts, each with a 1 GB video. Both downloads should be able to proceed (one per contact via in-flight dedup) without interference.
- TC-DL-06: Bob receives a message with a 1 GB video while his device is on cellular data -- download should still work (no Wi-Fi-only restriction exists). Verify the wake lock and progress UX also apply during downloads.

### Upload progress banner and foreground warning

- TC-UP-01: Send a 500 MB video -- progress banner appears at the top of the conversation showing bytes transferred out of total (e.g., "120 MB / 500 MB") with a progress bar.
- TC-UP-02: Progress banner displays the text "Keep the app open until the upload completes" while upload is active.
- TC-UP-03: Upload completes successfully -- progress banner disappears within 2 seconds.
- TC-UP-04: Upload fails (e.g., network error) -- progress banner transitions to a failure state showing the error, not stuck at the last progress value.
- TC-UP-05: While upload is in progress, tap the back button to leave the conversation -- confirmation dialog appears: "An upload is in progress. Leaving may interrupt it. Are you sure?"
- TC-UP-06: In the leave-confirmation dialog, tap "Stay" -- remain in conversation, upload continues uninterrupted from where it was.
- TC-UP-07: In the leave-confirmation dialog, tap "Leave" -- navigate away, upload is cancelled, attachment is marked as `upload_pending` for retry on next app resume.
- TC-UP-08: Send a message with 5 attachments (200 MB each) -- progress banner shows aggregate progress across all attachments (e.g., "600 MB / 1.0 GB") updating as each attachment completes.
- TC-UP-09: Upload is active in a group conversation -- same progress banner and foreground warning behavior as 1:1.
- TC-UP-10: Send a small attachment (5 MB image) -- progress banner appears briefly and disappears quickly. Verify no visual glitch or flash.
- TC-UP-11: Send a 2 GB video, then send a text-only message while the upload is still in progress -- the text message sends immediately without waiting for the upload, and the progress banner remains for the media message.

### Screen wake lock during upload

- TC-WL-01: Start a media upload -- verify the screen wake lock is enabled (screen does not dim or auto-lock while upload is active).
- TC-WL-02: Upload completes -- verify the wake lock is disabled and normal auto-lock behavior resumes.
- TC-WL-03: Upload fails with a network error -- verify the wake lock is disabled (not left on indefinitely).
- TC-WL-04: Upload is cancelled by the user (via leave-confirmation dialog) -- verify the wake lock is disabled.
- TC-WL-05: Send a message with 5 attachments uploading in sequence -- wake lock remains enabled from the first upload start until the last upload finishes (no gap between sequential uploads).
- TC-WL-06: Leave the phone idle on the conversation screen during a 2 GB upload -- verify the screen stays on for the entire upload duration. After upload completes, screen dims and locks normally per OS auto-lock setting.
- TC-WL-07: Start an upload, then manually press the power button to lock the phone -- verify the wake lock does not prevent manual lock (it only prevents auto-lock from inactivity).
- TC-WL-08: Start a download of a 1 GB received attachment -- verify the wake lock is also enabled during downloads (not just uploads).
- TC-WL-09: Two uploads running for two different conversations (e.g., user started one, navigated back, started another) -- wake lock remains enabled until both complete.
- TC-WL-10: Upload completes while app is in the foreground, then user immediately starts another upload -- wake lock transitions seamlessly (no flicker of auto-lock between uploads).

### Share extension

- TC-SH-01: Share a 2 GB video from Photos app into mknoon via the share sheet -- should attach and send using the user's current quality preference.
- TC-SH-02: Share a 6 GB video from Photos app into mknoon via the share sheet -- warning dialog should appear with the "attached media exceeds 5 GB" message.
- TC-SH-03: Share 3 images (100 MB each) from Photos app into mknoon -- all 3 should attach and send. Verify compression is applied if the user's preference is "Compressed".
- TC-SH-04: Share a 4 GB video with quality set to "Compressed" -- compression runs, resulting file is under 5 GB, sends without warning.

### Edge cases and device constraints

- TC-EC-01: Device has less than 5 GB free storage and user tries to attach a 4 GB video -- verify the app handles the low-storage scenario gracefully (e.g., compression may fail if temp space is insufficient). No crash.
- TC-EC-02: User attaches a 3 GB video, the app processes/compresses it, but the device runs out of storage during compression -- verify a clear error message is shown, no partial/corrupt temp files are left behind.
- TC-EC-03: User attaches a 4.9 GB video and immediately puts the app to background before upload starts -- on foregrounding, the upload should either start or be queued for retry (not silently lost).
- TC-EC-04: User sends a 3 GB video on a slow cellular connection (e.g., 1 Mbps) -- upload takes ~40 minutes. Verify the wake lock keeps the screen on the entire time and the progress banner accurately tracks progress throughout.
