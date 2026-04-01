# 35 - Cancelled Video Upload Still Sends

## 1. Title and Type

- Title: Cancelled video upload still sends
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/35-cancelled-video-upload-still-sends.md`

## 2. Problem Statement

Users are trying to abandon a direct-message video send after the upload has already started by pressing `Cancel` on the active upload banner.

Instead of treating that action as a final stop, the current behavior can continue running the in-flight upload, surface the ordinary failure message `Failed to upload media. Try again.`, leave a visible outgoing row with the caption in the sender chat, and, per the user report, still allow the canceled attempt to reach the recipient.

From the user perspective, that breaks the meaning of `Cancel`. A canceled video send is expected to stop the send attempt, avoid later delivery, and leave the sender in a clear state rather than a mixed draft / failed-row / later-retry situation.

## 3. Impact Analysis

- Affected users: senders in the 1:1 conversation flow who cancel an in-progress video upload, especially large videos or videos sent with a caption.
- Trigger moment: while the upload banner is visible and the upload future is still in flight.
- Severity: high from a trust and privacy perspective because a user-rejected media send may still remain eligible for retry or delivery.
- Frequency: repo evidence suggests timing-sensitive behavior around in-flight upload completion or failure; the user report indicates the issue is user-visible in TestFlight.
- User cost:
  - the cancel action does not behave as a final stop
  - the sender can see conflicting UI states such as restored composer content plus a failed outgoing row
  - a canceled attempt may still remain retryable and later deliverable

## 4. Current State

- `lib/features/conversation/presentation/widgets/upload_progress_banner.dart:25-99` renders the active upload banner and exposes a `Cancel` button when `onCancel` is provided.
- `lib/features/conversation/presentation/screens/conversation_wired.dart:2917-2922` removes the banner cancel callback as soon as `_activeAttachmentUpload.cancelRequested` becomes true, so the visible cancel affordance disappears immediately after tap even though the upload future may still be running.
- `lib/features/conversation/presentation/screens/conversation_wired.dart:1288-1318` clears the composer, creates an optimistic outgoing `ConversationMessage`, and persists optimistic attachment rows before the actual upload completes. That explains why a later failure path can still leave behind a sender-side row with the caption text.
- `lib/features/conversation/presentation/screens/conversation_wired.dart:1338-1445` only honors cancellation at explicit boundary checks before each attachment, after each attachment, and once again after the loop.
- `lib/features/conversation/presentation/screens/conversation_wired.dart:1399-1421` takes the ordinary upload-failure path when `uploadMediaFn(...)` returns `null`, restoring the composer with `Failed to upload media. Try again.` before any cancel-specific terminalization happens.
- `lib/features/conversation/presentation/screens/conversation_wired.dart:493-510` shows that a cancel request only becomes a terminal canceled state when `_cancelActiveAttachmentUploadIfRequested(...)` runs and marks pending attachments failed for that message.
- `lib/features/conversation/presentation/screens/conversation_wired.dart:1630-1658` restores the draft and pending attachments, marks the optimistic message `failed`, persists that status, and shows the chosen snackbar text. This is consistent with the sender seeing a failed bubble after the composer is restored.
- `lib/features/conversation/presentation/screens/conversation_wired.dart:668-705` and `lib/features/conversation/presentation/screens/conversation_wired.dart:1661-1676` show that videos are prepared and typed inside the same conversation attachment send flow as other media; there is no separate video-only cancellation branch.
- `lib/core/services/pending_message_retrier.dart:13-18` and `lib/core/services/pending_message_retrier.dart:33-38` define automatic retry behavior for failed outgoing work, including incomplete uploads.
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart:261-307` proves that transient upload failures remain `upload_pending` and are retried again on a later pass. That creates a plausible path for later delivery if a user-initiated cancel falls into the ordinary failure path instead of the cancel-terminal path.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart:3139-3248` covers the sender-side happy-path cancel flow, but the test uses `cancel.jpg`, releases the upload gate to a successful upload result, and only asserts local UI/state such as the `Upload cancelled.` snackbar, retry/delete affordances, and `upload_failed` attachments.
- No current direct conversation widget or integration test found in repo search proves the reported outcome that a canceled video upload with caption never reaches `sendChatMessage(...)` and never appears on the recipient side.

## 5. Scope Clarification

- In scope:
  - 1:1 conversation video uploads canceled from the active upload banner
  - video sends with or without caption text
  - sender-visible state after cancel
  - whether a canceled attempt remains retryable or deliverable after reconnect, resume, or later recovery
  - recipient-visible outcome for the same canceled attempt
- Explicit non-goals:
  - generic media upload performance work
  - thumbnail or playback bugs covered by other media reports
  - group conversation or announcement upload parity unless the same direct-message bug is later confirmed there
  - broader transport or storage redesign beyond the user-visible cancel outcome
- Accepted ambiguities for later implementation work:
  - whether a canceled attempt leaves no row at all or a clearly terminal local-only canceled indication
  - whether already-started network transfer can continue internally after cancel, as long as the user-visible outcome is that the canceled attempt is not sent and cannot later deliver
  - the exact copy shown after cancel, as long as it does not present the action as an ordinary upload failure

## 6. Test Cases

### Happy Path

- HP-01: In a 1:1 conversation, after selecting a single video and entering a caption, pressing `Cancel` while the upload banner is active keeps the caption and selected video in the composer and resolves the send attempt as canceled rather than failed.
- HP-02: After the sender cancels an in-progress single-video upload, the conversation list does not retain a retryable outgoing row from that canceled attempt.
- HP-03: After the sender cancels an in-progress single-video upload, the recipient does not receive any new message or caption from that canceled attempt.
- HP-04: After canceling a video upload, leaving the conversation, backgrounding the app, resuming it, or reconnecting the node does not revive that canceled send.
- HP-05: Canceling a video-only send and canceling a video-plus-caption send both preserve the same user intent: the canceled attempt is not delivered.

### Edge Cases

- EC-01: If the user taps `Cancel` while a single large video upload is still in flight and the upload later resolves as a transport failure, the final user-visible outcome is still cancellation rather than `Failed to upload media. Try again.`.
- EC-02: If the user taps `Cancel` very near upload completion, the app still suppresses any later send for that attempt once the cancel tap has been accepted.
- EC-03: If the user taps `Cancel` and immediately leaves the screen or backgrounds the app, the canceled video does not reappear later as a failed or delivered outgoing message.
- EC-04: If the sender has a caption draft plus video selected, cancel restores both together and does not drop only one part of the compose state.
- EC-05: The cancel outcome is consistent for direct-message video transfer regardless of whether the upload uses local-peer transfer or relay upload.

### Regressions To Preserve

- RG-01: Ordinary non-canceled media upload failures still surface as upload failures and remain covered by the existing failed-media retry/delete behavior.
- RG-02: The active upload banner continues to expose a visible cancel affordance while a cancelable upload is in progress.
- RG-03: Existing sender-side cancel expectations already covered in `test/features/conversation/presentation/screens/conversation_wired_test.dart:3139-3248` remain valid for the final user-visible state.
- RG-04: Existing retry-layer behavior for genuine transient upload failures, as covered in `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart:261-307`, is preserved for real failures and does not get conflated with explicit user cancellation.

### Existing Coverage And Gaps

- Existing partial coverage:
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart:3139-3248`
  - `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart:261-307`
- Coverage gaps:
  - no video-specific cancel test in the direct conversation screen flow
  - no assertion that a cancel request suppresses the later `sendChatMessage(...)` call for that same attempt
  - no recipient-side integration proof that a canceled video never arrives
  - no direct test for the cancel-then-upload-failure ordering reported by the user
