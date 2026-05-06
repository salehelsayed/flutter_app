# Findings: post-photo-upload-to-feed — 2026-05-05

Audit basis: commit `5fec83b3` on branch `new-background`.

---

```yaml
id: post-photo-2026-05-05-001
severity: medium
what-user-sees: >
  A user picks a photo from the camera roll using the compose sheet, taps
  publish, and sees the post appear in the feed — but with no photo.
  The post is sent as text-only with no error message or indication that
  the attachment was silently dropped.
chain-break-at: >
  PostsWired._pickMediaDrafts → _mimeFromPath → _kindFromMime → ComposePostSheet
  → PostsWired._startBackgroundDelivery → attachPostMedia invalidSelection guard.
  _mimeFromPath (in posts_wired.dart) has a hardcoded extension list.  Any photo
  whose extension is not in that list (e.g. .heif, .gif, .bmp, .tiff, .webp from
  camera roll on certain iOS versions) maps to 'application/octet-stream'.
  _kindFromMime maps that to 'other'. In attach_post_media_use_case.dart the
  isValidSelection switch covers 'image', 'video', 'voice' and _ → false.
  AttachPostMediaResult.invalidSelection is returned, prepareCreatedLocalPostMedia
  returns (SendPostResult.sendFailed, …), and _startBackgroundDelivery returns
  without any user-visible feedback because it is unawaited and its error path
  is silent.
production-files:
  - lib/features/posts/presentation/screens/posts_wired.dart:1008
  - lib/features/posts/presentation/screens/posts_wired.dart:1076
  - lib/features/posts/presentation/screens/posts_wired.dart:1089
  - lib/features/posts/application/attach_post_media_use_case.dart:66
  - lib/features/posts/application/attach_post_media_use_case.dart:72
  - lib/features/posts/presentation/screens/posts_wired.dart:460
flow-files-touched:
  - lib/features/posts/presentation/screens/posts_wired.dart
  - lib/features/posts/application/attach_post_media_use_case.dart
  - lib/features/posts/application/send_post_use_case.dart
  - lib/features/posts/domain/repositories/post_repository.dart
  - lib/core/media/media_picker.dart
  - lib/core/media/image_processor.dart
evidence: >
  posts_wired.dart:_mimeFromPath handles: jpg, jpeg, png, webp, heic, mp4, mov,
  m4a, mp3, ogg — nothing else. posts_wired.dart:_kindFromMime maps anything
  not starting with 'image/', 'video/', or 'audio/' to 'other'.
  attach_post_media_use_case.dart lines 67-74: isValidSelection is false for
  kind == 'other'. The function returns (invalidSelection, []).
  prepareCreatedLocalPostMedia (lines 199-208) maps any non-success result to
  (sendFailed, …). posts_wired.dart _startBackgroundDelivery (line 460):
  unawaited(_startBackgroundDelivery(created)) — errors are swallowed silently.
  Concrete affected extensions: .heif (modern iOS HEIF variant delivered by
  some iOS 17/18 camera apps as .heif not .heic), .gif (animated GIFs from
  Messages/Photos), .bmp, .tiff.
suggested-fix: >
  Extend _mimeFromPath in posts_wired.dart to cover .heif → 'image/heif', .gif
  → 'image/gif', .bmp → 'image/bmp', .tiff → 'image/tiff', .avif → 'image/avif'.
  Then extend _kindFromMime to treat all 'image/*' mimes (not just the known
  list) as 'image'. A simpler alternative: replace the extension-only lookup
  with the shared _mimeFromPath from share_batch_delivery_coordinator.dart which
  has broader coverage. Also add a user-visible error toast in
  _startBackgroundDelivery when prepareResult != success so the user knows the
  attachment was not sent.
verifiable-only-by: manual-qa
status: open
related-docs:
  - Test-Flight-Improv/Production-Flow-Audits/flows.md
```

---

```yaml
id: post-photo-2026-05-05-002
severity: low
what-user-sees: >
  A user publishes a post with a photo. The photo appears in their own feed
  immediately. But if the upload fails (bridge error, network issue, or the
  p2p node is not yet running), the user sees no error — the post shows as
  sent, with no photo, and no indication anything went wrong. There is no
  retry prompt.
chain-break-at: >
  PostsWired._startBackgroundDelivery is invoked with unawaited() from
  _compose() (posts_wired.dart:456). If prepareCreatedLocalPostMedia returns
  sendFailed, _startBackgroundDelivery returns silently. No setState, no
  snackbar, no status message is emitted.  The post's DB deliveryStatus
  is set to 'failed' by _persistFailedMediaPreparationPost but the UI
  only re-renders from postChanges stream events — which are emitted —
  so the UI will eventually show 'failed'. However, the failure state
  is a low-contrast "failed" label with no call-to-action, and the photo
  is gone from the compose result with no explicit "your photo was not
  attached" message.
production-files:
  - lib/features/posts/presentation/screens/posts_wired.dart:456
  - lib/features/posts/application/attach_post_media_use_case.dart:178
  - lib/features/posts/application/attach_post_media_use_case.dart:307
flow-files-touched:
  - lib/features/posts/presentation/screens/posts_wired.dart
  - lib/features/posts/application/attach_post_media_use_case.dart
evidence: >
  posts_wired.dart line 456: unawaited(_startBackgroundDelivery(created)).
  _startBackgroundDelivery (lines 460-480): on prepareResult != success, the
  function returns without touching any UI state. _persistFailedMediaPreparationPost
  (attach_post_media_use_case.dart:307) sets deliveryStatus='failed' in DB
  and calls postRepo.savePost, which triggers the postChanges stream, so the
  post card eventually updates to failed. But there is no proactive user-facing
  message at the moment of failure.
suggested-fix: >
  Propagate the result of _startBackgroundDelivery back to the compose flow.
  The cleanest approach is to show a snackbar in _compose() if
  _startBackgroundDelivery completes with an error, similar to the
  _passAlongStatusMessage pattern already in PostsWired. Alternatively, add
  a status message emission via setState when prepareResult != success inside
  _startBackgroundDelivery.
verifiable-only-by: manual-qa
status: open
related-docs:
  - Test-Flight-Improv/Production-Flow-Audits/flows.md
```
