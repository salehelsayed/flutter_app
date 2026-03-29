# Video Upload & Playback — Bug Spec

**Date:** 2026-03-29
**Severity:** High — videos are unusable in conversations
**Reported from:** TestFlight (user-a sends 6 videos to user-b)

---

## Bugs Overview

Three related bugs, all rooted in missing video thumbnail extraction and missing video playback support.

| # | Bug | Impact |
|---|-----|--------|
| 1 | Processing card flickers N times when uploading N videos | Confusing UX — user doesn't know processing is happening |
| 2 | Sender sees black thumbnails for sent videos | Sender can't verify what they sent |
| 3 | Receiver sees black thumbnails and can't play videos | Videos are completely unusable for the receiver |

---

## Bug 1: Processing Card Flickers for Each Video

### What happens

When the user selects 6 videos from the gallery, they see the processing card appear and disappear 6 times in quick succession. Each appearance shows progress 0% → 100% for one video, then vanishes, then reappears for the next. It looks like broken flickering.

### Root cause

`conversation_wired.dart:1493-1506` — `_pickFromGallery()` processes videos **sequentially** in a `for` loop:

```dart
for (final xf in selectedFiles) {
  final result = await _preparePendingMedia(xf.path);  // one at a time
  media.add(result);
}
```

Each call to `_preparePendingMedia()` (`conversation_wired.dart:616-646`) toggles the **single** `isProcessing` boolean:

```dart
// Line 624: start
_updateComposerState(isProcessing: true, processingProgress: 0.0);
// ... process video ...
// Line 643: end
_updateComposerState(isProcessing: false, processingProgress: 0.0);
```

The UI state (`ConversationComposerViewState` at `conversation_screen.dart:27-67`) has only **one** `isProcessing` flag and **one** `processingProgress` value. There's no concept of "processing video 3 of 6".

### What the user sees

```
[Processing 0%→100%] → [Gone] → [Processing 0%→100%] → [Gone] → ... (6 times)
```

### What the user should see

A single persistent card:

```
Processing videos (3/6) — 45%
```

### Fix approach

**A. Add batch processing state to `ConversationComposerViewState`**

File: `conversation_screen.dart`

```dart
class ConversationComposerViewState {
  // ... existing fields ...
  final bool isProcessing;
  final double processingProgress;
  final int processingCurrent;     // NEW — e.g. 3
  final int processingTotal;       // NEW — e.g. 6
}
```

**B. Wrap the processing loop with batch-level state**

File: `conversation_wired.dart` — `_pickFromGallery()`

```dart
Future<void> _pickFromGallery() async {
  final picked = await _mediaPicker.pickMultipleMedia();
  if (picked.isEmpty || !mounted) return;

  final selectedFiles = picked.take(remaining).toList();
  final videoCount = selectedFiles.where(
    (xf) => widget.imageProcessor?.isProcessableVideo(xf.path) ?? false,
  ).length;

  if (videoCount > 0) {
    _updateComposerState(
      isProcessing: true,
      processingProgress: 0.0,
      processingCurrent: 0,
      processingTotal: videoCount,
    );
  }

  final media = <PendingComposerMedia>[];
  var videoIndex = 0;
  for (final xf in selectedFiles) {
    final isVideo = widget.imageProcessor?.isProcessableVideo(xf.path) ?? false;
    if (isVideo) {
      videoIndex++;
      _updateComposerState(processingCurrent: videoIndex);
    }
    final result = await _preparePendingMedia(xf.path);
    media.add(result);
  }

  if (videoCount > 0 && mounted) {
    _updateComposerState(
      isProcessing: false,
      processingProgress: 0.0,
      processingCurrent: 0,
      processingTotal: 0,
    );
  }

  if (!mounted) return;
  await _attemptAddPendingMedia(media);
}
```

**C. Update `_preparePendingMedia` — remove per-video isProcessing toggle**

The batch-level state in `_pickFromGallery` now owns the `isProcessing` lifecycle. `_preparePendingMedia` should only update `processingProgress`, not toggle `isProcessing`. Guard: when called from single-video paths (camera), keep the existing toggle.

**D. Update `_ProcessingThumbnail` widget**

File: `attachment_preview_strip.dart`

Show batch context:

```
Processing (3/6)
45%
```

Or for single video:

```
Processing
45%
```

### Files to modify

| File | Change |
|------|--------|
| `conversation_screen.dart` | Add `processingCurrent`, `processingTotal` to `ConversationComposerViewState` |
| `conversation_wired.dart` | Batch-level `isProcessing` lifecycle in `_pickFromGallery()`, remove per-video toggle from `_preparePendingMedia` when called in batch |
| `attachment_preview_strip.dart` | Show "Processing (N/M)" in `_ProcessingThumbnail` |

---

## Bug 2: Sender Sees Black Thumbnails for Sent Videos

### What happens

After uploading 6 videos, the sender's message bubble shows all video cells as solid black rectangles. The play icon and duration overlay render on top, but the background is dark/empty.

### Root cause

**No thumbnail extraction.** The video processing pipeline (`image_processor.dart:85-101`) re-encodes the video via `video_compress` but never extracts a thumbnail image frame. `VideoProcessResult` contains only `path`, `width`, `height`, `durationMs` — no thumbnail data.

When the message is sent, the optimistic `MediaAttachment` (`conversation_wired.dart:1018-1033`) sets:

```dart
localPath: m.file.path,  // This is the VIDEO file (mp4)
```

Then `media_grid_cell.dart:49-55` tries to render it:

```dart
if ((isImage || isVideo) && isDone && hasPath) {
  return Image.file(
    File(attachment.localPath!),  // VIDEO FILE — not an image!
    fit: BoxFit.cover,
    ...
    errorBuilder: (_, __, ___) => _buildFailedPlaceholder(),
  );
}
```

Flutter's `Image.file()` **cannot render video files**. It either:
- Falls into `errorBuilder` → shows broken image icon
- Or on some platforms, renders a black/empty area

The `media-client-spec.md` (line 48) originally planned for a `thumbnail` field (base64 JPEG embedded in the wire format) and `blurhash`, but these were never implemented.

### What the user sees

Black rectangles with play icons and durations for all videos in the message grid.

### What the user should see

A thumbnail frame from each video (typically the first frame or a frame at ~1 second) displayed in the grid cell.

### Fix approach

**A. Extract video thumbnail during processing**

File: `image_processor.dart`

Add a thumbnail extraction step. The `video_compress` package already supports this:

```dart
import 'package:video_compress/video_compress.dart';

Future<File?> getVideoThumbnail(String videoPath) async {
  return await VideoCompress.getFileThumbnail(
    videoPath,
    quality: 70,
    position: -1,  // auto-select frame
  );
}
```

**B. Extend `VideoProcessResult` to include thumbnail path**

File: `video_process_result.dart`

```dart
class VideoProcessResult {
  final String path;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? thumbnailPath;  // NEW — path to extracted JPEG thumbnail
}
```

**C. Extend `PendingComposerMedia` to carry thumbnail**

File: `pending_composer_media.dart`

```dart
class PendingComposerMedia {
  final File file;
  final int budgetBytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final File? thumbnail;  // NEW — extracted video thumbnail
}
```

**D. Extend `MediaAttachment` to store thumbnail path**

File: `media_attachment.dart`

```dart
final String? thumbnailPath;  // NEW — local path to thumbnail image
```

Database migration: add `thumbnail_path TEXT` column to `media_attachments` table.

**E. Wire thumbnail through optimistic attachment creation**

File: `conversation_wired.dart` (around line 1018-1033)

```dart
optimisticMedia = mediaToUpload.map((m) {
  final mime = _mimeFromPath(m.file.path);
  return MediaAttachment(
    ...
    localPath: m.file.path,
    thumbnailPath: m.thumbnail?.path,  // NEW
    ...
  );
}).toList();
```

**F. Update `MediaGridCell` to prefer thumbnail for videos**

File: `media_grid_cell.dart`

```dart
Widget _buildContent() {
  final isVideo = attachment.mediaType == 'video';
  final isDone = attachment.downloadStatus == 'done';
  final hasPath = attachment.localPath != null;

  if (isVideo && isDone && hasPath) {
    // Prefer thumbnail, fall back to dark placeholder
    final thumbPath = attachment.thumbnailPath;
    if (thumbPath != null) {
      return Image.file(
        File(thumbPath),
        fit: BoxFit.cover,
        cacheWidth: 400,
        errorBuilder: (_, __, ___) => _buildDarkVideoPlaceholder(),
      );
    }
    return _buildDarkVideoPlaceholder();
  }

  if (isImage && isDone && hasPath) {
    return Image.file(
      File(attachment.localPath!),
      fit: BoxFit.cover,
      cacheWidth: 400,
      errorBuilder: (_, __, ___) => _buildFailedPlaceholder(),
    );
  }
  // ... rest unchanged ...
}
```

**G. Save thumbnail alongside video in media directory**

File: `upload_media_use_case.dart` or `media_file_manager.dart`

When persisting the video locally, also copy the thumbnail to:
```
media/<contactPeerId>/<blobId>_thumb.jpg
```

Store the relative path in the `thumbnailPath` column.

### Files to modify

| File | Change |
|------|--------|
| `video_process_result.dart` | Add `thumbnailPath` field |
| `image_processor.dart` | Extract thumbnail via `VideoCompress.getFileThumbnail()` after compression |
| `pending_composer_media.dart` | Add `thumbnail` field |
| `media_attachment.dart` | Add `thumbnailPath` field |
| `media_grid_cell.dart` | Use `thumbnailPath` for video cells instead of `localPath` |
| `conversation_wired.dart` | Wire `thumbnail` through optimistic media creation |
| `media_attachment_repository_impl.dart` | Persist `thumbnailPath` |
| DB migration | Add `thumbnail_path` column to `media_attachments` |

---

## Bug 3: Receiver Sees Black Thumbnails and Can't Play Videos

### What happens

User-b receives the message with 6 videos. All video cells show black thumbnails. Tapping a video opens `FullScreenImageViewer` which shows a broken image icon — no video plays.

### Root cause — Black thumbnails

Two compounding issues:

1. **No thumbnail in wire payload.** The `media-client-spec.md` planned for a `thumbnail` (base64 JPEG) field in the wire format, but it was never implemented. The receiver gets `MediaAttachment` records with no thumbnail data.

2. **After download, same `Image.file()` on video.** Even after the receiver downloads the video file, `media_grid_cell.dart` tries `Image.file(File(videoPath))` which fails identically to the sender case.

### Root cause — Can't play videos

The `onMediaTap` handler (`conversation_screen.dart:435-464`) opens `FullScreenImageViewer` for ALL media types:

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => FullScreenImageViewer(  // IMAGE viewer only!
      localPath: tappedPath,
      allPaths: allPaths,
      initialIndex: startIndex,
    ),
  ),
);
```

`FullScreenImageViewer` (`full_screen_image_viewer.dart:79`) only uses `Image.file()` — there is **no video player** anywhere in the tap-to-open flow. The app has no video playback widget.

### What the user sees

- Black thumbnails (identical to Bug 2)
- Tapping a video → opens a black/broken screen (image viewer trying to render mp4)

### What the user should see

- Thumbnail frames for each video in the grid
- Tapping a video → opens a full-screen video player with play/pause, seek, and close

### Fix approach

**A. Include thumbnail in wire payload (send side)**

File: `conversation_wired.dart` or send use case

After extracting the thumbnail (Bug 2 fix), base64-encode it and include in the `MediaAttachment` wire format:

```dart
MediaAttachment(
  ...
  thumbnail: base64Encode(thumbnailFile.readAsBytesSync()),
  ...
);
```

The thumbnail travels with the message — no extra download needed for the receiver.

**B. Store received thumbnail locally (receive side)**

File: `handle_incoming_chat_message_use_case.dart`

When creating `MediaAttachment` records from the incoming payload, decode the base64 thumbnail and write it to disk:

```dart
if (wireAttachment.thumbnail != null) {
  final thumbFile = File('${mediaDir}/${wireAttachment.id}_thumb.jpg');
  await thumbFile.writeAsBytes(base64Decode(wireAttachment.thumbnail!));
  // Save thumbFile.path as thumbnailPath
}
```

**C. Also extract thumbnail after download**

As a fallback (for messages sent before this fix), when the receiver downloads the video, extract a thumbnail locally using `VideoCompress.getFileThumbnail()`.

**D. Create a video player screen**

New file: `lib/shared/widgets/media/full_screen_video_player.dart`

Use `video_player` (or `chewie` for controls) package:

```dart
class FullScreenVideoPlayer extends StatefulWidget {
  final String localPath;
  // ...
}
```

Features:
- Play/pause button
- Seek bar with elapsed/total time
- Full-screen with dark background
- Close button (back arrow)
- Auto-play on open

**E. Route video taps to video player**

File: `conversation_screen.dart` — `onMediaTap` callback

```dart
onMediaTap: (index) {
  final visual = message.media.where(
    (a) => a.mediaType == 'image' || a.mediaType == 'video',
  ).toList();
  if (index >= visual.length) return;

  final tapped = visual[index];
  if (tapped.localPath == null || tapped.downloadStatus != 'done') return;

  if (tapped.mediaType == 'video') {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenVideoPlayer(
          localPath: tapped.localPath!,
        ),
      ),
    );
  } else {
    // Existing image viewer logic
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenImageViewer(
          localPath: tapped.localPath!,
          allPaths: allImagePaths,
          initialIndex: startIndex,
        ),
      ),
    );
  }
},
```

**F. Add `video_player` dependency**

File: `pubspec.yaml`

```yaml
dependencies:
  video_player: ^2.8.0  # or latest
  chewie: ^1.7.0         # optional — provides Material controls
```

### Files to create

| File | Purpose |
|------|---------|
| `lib/shared/widgets/media/full_screen_video_player.dart` | Full-screen video player with controls |

### Files to modify

| File | Change |
|------|--------|
| `conversation_screen.dart` | Route video taps to `FullScreenVideoPlayer` instead of `FullScreenImageViewer` |
| `handle_incoming_chat_message_use_case.dart` | Decode and store received thumbnail locally |
| `media_attachment.dart` | Add `thumbnail` field to wire format (base64) |
| `message_payload.dart` | Include `thumbnail` in media serialization |
| `download_media_use_case.dart` | Extract thumbnail after download as fallback |
| `pubspec.yaml` | Add `video_player` (and optionally `chewie`) dependency |

---

## Summary: Shared Root Causes

```
Missing video thumbnail extraction
  → Bug 2 (sender black thumbnails)
  → Bug 3 (receiver black thumbnails)

Single-value processing state (no batch awareness)
  → Bug 1 (flickering processing card)

Missing video player
  → Bug 3 (can't play videos)

Image.file() used for all media types
  → Bug 2 + Bug 3 (video file can't render as image)
```

---

## Implementation Order

1. **Video thumbnail extraction** (Bugs 2 + 3) — core fix, unblocks everything
   - Extend `VideoProcessResult` with `thumbnailPath`
   - Extract thumbnail in `image_processor.dart`
   - Wire through `PendingComposerMedia` → `MediaAttachment`
   - Update `MediaGridCell` to use thumbnail for videos

2. **Batch processing state** (Bug 1) — UX fix
   - Add `processingCurrent`/`processingTotal` to composer state
   - Batch-level `isProcessing` lifecycle in `_pickFromGallery`
   - Update `_ProcessingThumbnail` widget

3. **Video player** (Bug 3) — enables video playback
   - Add `video_player` dependency
   - Create `FullScreenVideoPlayer` widget
   - Route video taps from `onMediaTap`

4. **Wire thumbnail in payload** (Bug 3 receiver) — enables receiver thumbnails
   - Include base64 thumbnail in `MediaAttachment` wire format
   - Decode and store on receive side
   - Fallback: extract thumbnail after download

---

## Testing Checklist

- [ ] Select 6 videos → single processing card with "Processing (N/6)" counter
- [ ] Processing card shows continuous progress, never flickers
- [ ] After send, sender sees thumbnail frames for all 6 videos (not black)
- [ ] Sender taps a video → full-screen video player opens, video plays
- [ ] Receiver sees thumbnail frames (not black) immediately on message arrival
- [ ] Receiver taps a video → downloads if needed, then opens video player
- [ ] Single video upload still works (camera capture path)
- [ ] Mixed message (3 images + 2 videos) — images show as before, videos show thumbnails
- [ ] Video player has play/pause, seek, and close controls
- [ ] Large video (>100 MB) — processing card stays visible throughout
