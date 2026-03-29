# 24 - Cancel Media Upload

## Problem

When a media upload is in progress or has failed, the user has **no way to cancel or stop it**. The app retries failed uploads automatically on every app resume (up to 3 times via `kMaxUploadRetries`), with no user-facing control to abort. This creates frustration when:

1. **An upload is stuck or slow** -- the user cannot cancel and must wait for the 5-minute per-file timeout
2. **An upload has failed and is retrying** -- the user has no way to stop the retry cycle; the app keeps re-uploading on every app resume until the retry count is exhausted
3. **The user wants to remove/re-attach media during upload** -- the remove (X) button on the attachment preview strip is hidden while `isUploading=true`

### Current behavior

| Scenario | What happens | What the user can do |
|---|---|---|
| Upload in progress | Progress banner shown, no cancel button | Wait (up to 5 min per file) or leave the screen (gets a warning dialog, but leaving just defers the upload to retry later) |
| Upload failed | Snackbar "Failed to upload media. Try again." shown, media restored to composer | Tap send again (creates a duplicate optimistic message) |
| Upload retrying on app resume | `PendingMessageRetrier` picks up `upload_pending` attachments silently | Nothing -- no UI indication or cancel mechanism |
| Navigation during upload | Warning dialog "An upload is in progress. Leaving may interrupt it." | Can tap "Leave" but attachment stays `upload_pending` and retries on next resume |

### Current upload state machine

```
[user taps send]
    │
    ▼
upload_pending  ──(bridge upload)──▶  done  ──▶  sendChatMessage()
    │                                              │
    │ (upload fails)                               ▼
    ▼                                           message sent
upload_pending  ──(app resume, retry)──▶  ...retry up to 3x...
    │
    │ (retryCount >= 3)
    ▼
upload_failed  (terminal -- no further retries, but user cannot trigger this manually)
```

### Relevant code locations

| File | Role |
|---|---|
| `conversation_wired.dart:1025-1116` | Sequential upload loop for 1:1 messages |
| `conversation_wired.dart:1238-1267` | `_restoreComposerSnapshot()` -- restores composer on failure |
| `upload_media_use_case.dart:85-107` | `callP2PMediaUpload()` with 5-min timeout, returns null on failure |
| `upload_progress_banner.dart` | Shows upload progress, no cancel button |
| `attachment_preview_strip.dart:129-173` | Hides remove (X) button during upload |
| `retry_incomplete_uploads_use_case.dart` | Retries `upload_pending` attachments on app resume |
| `retry_incomplete_group_uploads_use_case.dart` | Same for group messages |
| `pending_message_retrier.dart` | Orchestrates retry on app resume / online transition |
| `p2p_bridge_client.dart:491-529` | `callP2PMediaUpload()` -- bridge call, not cancellable mid-stream |
| `retry_constants.dart` | `kMaxUploadRetries = 3` |
| `media_attachment_repository.dart` | Persistence interface for attachment status |
| `media_attachments_db_helpers.dart` | DB queries for `upload_pending` attachments |

## Solution

Add cancel/stop controls at three points in the upload lifecycle: during active upload, after failure, and for pending retries.

### 1. Cancel button on the upload progress banner

**File:** `upload_progress_banner.dart`

Add a cancel (X) button to the right side of the upload progress banner. Tapping it cancels the current upload batch.

**Wiring in `conversation_wired.dart`:**

Add a `_uploadCancelled` flag (a `bool` or a `Completer`) that the upload loop checks **between files** in the sequential upload loop (line ~1025-1116). The flow becomes:

```
for each file in mediaToUpload:
    if (_uploadCancelled) break;       // ← NEW: check before each file
    result = await uploadMediaFn(...)
    if (result == null) ...            // existing failure handling
```

When the cancel button is tapped:
1. Set `_uploadCancelled = true`
2. The current in-flight `bridge.send()` call **cannot be interrupted** (it will complete or timeout on its own). The loop exits at the next iteration boundary.
3. Call `_restoreComposerSnapshot()` to put media back in the composer
4. Mark the optimistic message as `'cancelled'` (new status, or reuse `'failed'`)
5. Mark all `upload_pending` attachments for this message as `'upload_failed'` (terminal -- prevents auto-retry)
6. Stop relay upload tracking and release wake lock
7. Show snackbar: "Upload cancelled"
8. Reset `_uploadCancelled = false`

**For the in-flight file that cannot be interrupted:** The already-uploaded blob on the relay becomes orphaned. This is acceptable -- the relay's TTL cleanup handles orphans. No special cleanup is needed.

### 2. Cancel/delete failed messages with pending uploads

**Where:** The failed message bubble in the conversation list.

Currently, when an upload fails, the optimistic message stays in the chat list with status `'failed'` and attachments in `upload_pending` state. The user must tap send again (creating a duplicate), and the original failed message persists.

Add two actions to failed message bubbles that have `upload_pending` attachments:

#### "Retry" action
- Manually re-trigger upload for this specific message
- Same logic as `retryIncompleteUploads()` but scoped to one messageId
- Does not wait for app resume -- immediate retry on tap

#### "Delete" action
- Mark all `upload_pending` attachments for this message as `upload_failed` (prevents auto-retry on resume)
- Delete the failed message from the message list and DB
- Clean up any persisted pending-upload files from the media directory
- Show snackbar: "Message deleted"

This prevents the `PendingMessageRetrier` from silently re-uploading on every app resume when the user has already decided to abandon the message.

### 3. Stop retrying on app resume (user-initiated terminal failure)

**File:** `retry_incomplete_uploads_use_case.dart`

The retry use case already skips `upload_failed` attachments. The changes in sections 1 and 2 mark cancelled/deleted attachments as `upload_failed`, so no change to the retry logic itself is needed.

However, add a convenience method to the media attachment repository:

```dart
Future<void> markMessageAttachmentsAsFailed(String messageId);
```

This atomically marks all `upload_pending` attachments for a given message as `upload_failed` in one DB operation. Used by both the cancel button (section 1) and the delete action (section 2).

### 4. Mirror for group uploads

Apply the same cancel button and failed-message actions to `group_conversation_wired.dart`. The group upload flow uses `Future.wait()` (parallel uploads), so cancellation works slightly differently:

- Set `_uploadCancelled = true`
- The parallel uploads that are already in-flight will complete or fail on their own
- After `Future.wait()` resolves, check the flag and discard results if cancelled
- Same cleanup: mark as `upload_failed`, restore composer, release wake lock

## Updated upload state machine

```
[user taps send]
    │
    ▼
upload_pending  ──(bridge upload)──▶  done  ──▶  sendChatMessage()
    │       │                                      │
    │       │ (user taps cancel)                   ▼
    │       ▼                                   message sent
    │   upload_failed  (terminal, immediate)
    │
    │ (upload fails)
    ▼
upload_pending  ──(app resume, retry)──▶  ...retry up to 3x...
    │       │
    │       │ (user taps delete on failed message)
    │       ▼
    │   upload_failed + message deleted
    │
    │ (retryCount >= 3)
    ▼
upload_failed  (terminal -- automatic)
```

## Files to modify

| File | Change |
|---|---|
| `upload_progress_banner.dart` | Add cancel (X) button, expose `onCancel` callback |
| `conversation_wired.dart` | Add `_uploadCancelled` flag, check in upload loop, wire cancel handler, add failed-message retry/delete actions |
| `conversation_screen.dart` | Pass cancel callback to progress banner, show retry/delete actions on failed messages with pending uploads |
| `group_conversation_wired.dart` | Mirror cancel support for group uploads |
| `group_conversation_screen.dart` | Mirror UI changes for group conversations |
| `media_attachment_repository.dart` | Add `markMessageAttachmentsAsFailed(messageId)` method |
| `media_attachments_db_helpers.dart` | Implement the bulk status update query |
| `media_file_manager.dart` | Add cleanup helper to delete pending-upload files for a message |
| `app_localizations_en.dart` | Add strings: "Upload cancelled", "Message deleted", "Retry", "Delete" |

## Edge cases

| Scenario | Behavior |
|---|---|
| Cancel tapped but current file upload completes before loop checks flag | Uploaded blob is orphaned on relay (TTL cleanup handles it). Message is still cancelled. |
| Cancel tapped during the only file in the batch | Same as above -- blob may be orphaned, message cancelled. |
| Multi-file batch: 2 of 5 uploaded, then cancelled | 2 blobs orphaned on relay. All 5 attachments marked `upload_failed`. Composer restored with all 5 files. |
| User cancels, then immediately taps send again | New optimistic message created with fresh UUIDs. Old cancelled message stays as `'failed'` in chat (or can be deleted via the delete action). |
| App killed during upload (before cancel is possible) | No change from current behavior: attachments stay `upload_pending`, retry on resume. User can delete the failed message after resume. |
| Cancel during local WiFi transfer (not relay) | Same mechanism: `_uploadCancelled` flag checked between files. In-flight local transfer completes or fails on its own. |
| User taps "Delete" on a message whose retry is actively running | The retry use case should check attachment status before sending `sendChatMessage()`. If attachments were marked `upload_failed` mid-retry, skip the send. |
| Offline user taps "Retry" | Upload will fail immediately (no connectivity). Attachment stays `upload_pending`. User can retry again later or delete. |

## Test cases

### Cancel during active upload

- TC-CU-01: Send a message with a 500 MB video. While upload is in progress, tap the cancel button on the progress banner -- upload is cancelled, media returns to composer, snackbar shows "Upload cancelled".
- TC-CU-02: After TC-CU-01, verify the cancelled message appears as "failed" in the chat list (not stuck in "sending").
- TC-CU-03: After TC-CU-01, close and reopen the app -- verify the cancelled upload does NOT retry automatically (attachments are `upload_failed`, not `upload_pending`).
- TC-CU-04: Send a message with 5 attachments (100 MB each). Cancel after the 2nd file finishes uploading -- verify all 5 files return to the composer, message is marked failed.
- TC-CU-05: Send a message with a 50 MB image (fast upload). Tap cancel -- verify cancel works even for quick uploads (race condition test).
- TC-CU-06: Cancel an upload, then tap send again with the same media -- verify a new message is created and uploads successfully (no stale state from cancellation).
- TC-CU-07: Cancel an upload in a group conversation -- same behavior as 1:1.
- TC-CU-08: While upload progress banner shows cancel button, verify the progress percentage is still visible and updating (cancel button does not obscure progress info).
- TC-CU-09: Cancel an upload that is going through local WiFi transfer (not relay) -- media returns to composer, message marked failed.
- TC-CU-10: Verify the wake lock is released when upload is cancelled.

### Failed message actions (retry/delete)

- TC-FM-01: Send a message with media that fails to upload. Verify the failed message shows "Retry" and "Delete" action buttons.
- TC-FM-02: Tap "Retry" on a failed message -- upload restarts immediately, progress banner appears.
- TC-FM-03: Tap "Delete" on a failed message -- message and its attachments are removed from the chat list and DB. Snackbar shows "Message deleted".
- TC-FM-04: After TC-FM-03, close and reopen the app -- verify the deleted message does not reappear and its attachments are not retried.
- TC-FM-05: Send 3 messages with media. All 3 fail. Tap "Delete" on message #2 -- only message #2 is deleted, messages #1 and #3 remain with their retry/delete actions.
- TC-FM-06: Send a message with media that fails. Tap "Retry" -- upload succeeds, message moves to "sent" status, retry/delete actions disappear.
- TC-FM-07: Send a message with media that fails. Tap "Retry" while offline -- upload fails again, retry/delete actions remain visible.
- TC-FM-08: A failed message with `upload_pending` attachments exists. Close and reopen app. Before auto-retry runs, tap "Delete" -- message is deleted, auto-retry skips it.
- TC-FM-09: Failed message in a group conversation shows the same retry/delete actions.
- TC-FM-10: A text-only failed message (no media) does NOT show retry/delete actions (these actions are only for media upload failures).

### Retry prevention after cancel/delete

- TC-RP-01: Cancel an upload. Close and reopen the app 5 times -- verify no retry attempts occur for the cancelled message (attachments are `upload_failed`).
- TC-RP-02: Delete a failed message. Monitor `PendingMessageRetrier` on next app resume -- verify it does not attempt to retry the deleted message's attachments.
- TC-RP-03: Cancel upload for message A, let message B succeed normally -- verify message B is unaffected by the cancellation of message A.
- TC-RP-04: Delete a failed message while another message's upload is actively in progress -- verify the active upload is unaffected.
- TC-RP-05: The `retryIncompleteUploads` use case encounters attachments marked `upload_failed` -- verify it skips them completely (no upload attempt, no retry count increment).
