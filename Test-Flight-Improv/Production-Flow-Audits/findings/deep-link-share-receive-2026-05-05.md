# Findings: deep-link-share-receive — 2026-05-05

Audit basis: commit `5fec83b3` on branch `new-background`.

---

```yaml
id: share-2026-05-05-001
severity: medium
what-user-sees: >
  On Android, a user shares a file from another app while the mknoon app is
  already running in the background. The share sheet completes and the user
  expects mknoon to open the share target picker. Instead, mknoon comes to the
  foreground but no share picker appears — the share is silently dropped.
chain-break-at: >
  Android OS SEND intent → singleTask MainActivity → receive_sharing_intent
  plugin EventChannel → Dart intentStream → handleShareIntent →
  shareIntentService.bufferIntent. The break is in handleShareIntent
  (lib/features/share/application/handle_share_intent_use_case.dart:15-18):
  when isSettled is false, the intent is buffered. After _MyAppState.initState
  completes (main.dart:2207), _captureInitialShareIntent runs once and calls
  _routeBufferedShareIfSettled once. If the warm-start share arrives after that
  point but before isSettled has been set (e.g., the user is mid-onboarding
  with identity but no contacts, or the startup router has not yet resolved),
  the buffered intent is never re-checked by _MyAppState — _routeBufferedShare
  IfSettled is only called from _captureInitialShareIntent, not from the
  intentStream listener callback. The intent stays in _pendingIntent
  indefinitely until FTE or QRScanner calls settleShareIntentFlow, which may
  never happen if the user already has contacts.
production-files:
  - lib/features/share/application/handle_share_intent_use_case.dart:15
  - lib/main.dart:2234
  - lib/main.dart:2248
  - lib/main.dart:2262
  - lib/features/identity/presentation/startup_router.dart:373
flow-files-touched:
  - lib/features/share/application/handle_share_intent_use_case.dart
  - lib/features/share/application/settle_share_intent_flow.dart
  - lib/core/services/share_intent_service.dart
  - lib/main.dart
  - lib/features/identity/presentation/startup_router.dart
  - android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt
  - android/app/src/main/AndroidManifest.xml
evidence: >
  main.dart line 2234-2245: intentStream listener calls handleShareIntent
  unawaited. handle_share_intent_use_case.dart lines 15-18: if not settled,
  bufferIntent and return — no subsequent trigger.
  main.dart line 2207: _captureInitialShareIntent called once in initState.
  main.dart lines 2248-2276: _captureInitialShareIntent calls
  _routeBufferedShareIfSettled — only once at startup.
  startup_router.dart line 373: settleShareIntentFlow called only when
  StartupRouter resolves to the feed (hasIdentityWithContacts path). If the
  user already has identity + contacts, startup_router routes directly to
  FeedWired on cold start — so settleShareIntentFlow is called at cold start.
  But for a warm-start share (app already in FeedWired), isSettled is already
  true (set during the cold-start routing), so the warm-start path works
  correctly for users who completed onboarding on their last cold start.
  The window where this breaks is narrow: user has identity but zero contacts
  (onboarding in progress) and receives a warm-start share. The intent is
  buffered, _captureInitialShareIntent has already run, and the FTE/QR path
  that calls settleShareIntentFlow will drain it only if the user completes
  onboarding in the same session.
suggested-fix: >
  In the intentStream listener (main.dart _setupShareIntentHandling), after
  handleShareIntent returns with a buffered result, check if isSettled has
  since become true and call _routeBufferedShareIfSettled immediately. A
  simpler alternative: after handleShareIntent buffers, attach a one-shot
  listener on a future/stream that fires when isSettled flips to true, then
  call _routeBufferedShareIfSettled. The current architecture is close to
  correct for settled users; the gap is the one-shot initial-capture vs
  ongoing listener mismatch.
verifiable-only-by: manual-qa
status: open
related-docs:
  - Test-Flight-Improv/Production-Flow-Audits/flows.md
```

---

```yaml
id: share-2026-05-05-002
severity: low
what-user-sees: >
  On iOS, a user shares a photo from Photos.app into mknoon for a contact or
  group. If the photo's file extension happens to be missing from the extension
  map in share_batch_delivery_coordinator.dart (e.g., .heif, .avif, .bmp),
  the file is uploaded with MIME type 'application/octet-stream'. The recipient
  receives the message and sees a generic file attachment rather than an inline
  image.
chain-break-at: >
  ShareBatchDeliveryCoordinator._processSharedMedia → _mimeFromPath
  (share_batch_delivery_coordinator.dart:470-488). The map covers common
  extensions but not .heif, .avif, .bmp, .tiff, .webm, .flac, etc. A file
  arriving with one of those extensions gets 'application/octet-stream', which
  _kindFromMime (via uploadMedia) stores as kind 'file', not 'image'. The
  recipient's conversation renders it as a file attachment, not an image.
production-files:
  - lib/features/share/application/share_batch_delivery_coordinator.dart:470
flow-files-touched:
  - lib/features/share/application/share_batch_delivery_coordinator.dart
  - lib/core/media/media_file_manager.dart
  - lib/features/conversation/application/upload_media_use_case.dart
evidence: >
  share_batch_delivery_coordinator.dart _mimeFromPath (line 470): covers jpg,
  jpeg, png, gif, webp, heic, mp4, mov, avi, mkv, m4v, m4a, aac. Missing:
  .heif (modern HEIF, distinct from .heic on some devices), .avif, .bmp,
  .tiff, .webm. iOS ShareViewController.swift uses url.mimeType() (line 226)
  which calls UTType — that correctly identifies heif as image/heif. But by
  the time the file path reaches Dart, the MIME is re-derived from the
  extension by Dart's _mimeFromPath, which doesn't know heif.
suggested-fix: >
  Add .heif → 'image/heif' (and .avif → 'image/avif') to the extension map in
  _mimeFromPath. Longer-term, consolidate into a single shared mimeFromPath
  utility to avoid the duplicate maps in posts_wired.dart and
  share_batch_delivery_coordinator.dart diverging further.
verifiable-only-by: manual-qa
status: open
related-docs:
  - Test-Flight-Improv/Production-Flow-Audits/flows.md
  - Test-Flight-Improv/Production-Flow-Audits/findings/post-photo-upload-to-feed-2026-05-05.md
```
