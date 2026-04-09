# UI-22: GIF Support — TDD Plan

## Approach: Gallery / Keyboard-Native GIFs (No Third-Party API)

Users pick GIFs from their device gallery or receive them through OS-provided
keyboard/share surfaces when those surfaces hand the app a real image file.
The app treats GIFs as animated images flowing through the existing media
pipeline — no external GIF API, no attribution badges, no ongoing cost.

---

## Exact Problem Statement

The current media pipeline already handles image/video/audio transport well, but
GIFs still fall through as generic images in several user-visible places:

- the current media model exposes GIF only as generic `image`, so UI code has
  no central predicate to distinguish an animated GIF from a photo,
- preview text still says "Photo" instead of "GIF",
- app-generated foreground notification body still says "Photo" instead of
  "GIF",
- the shared thumbnail path still forces `cacheWidth` / `cacheHeight` through
  `MediaThumbnailImage`, which means grid, attachment-strip, and feed
  thumbnail callers can still freeze GIFs; the share target picker also has one
  direct cache-hinted preview outside that shared path,
- there is no explicit UI-side GIF file-size guard across both the wired
  composer seam and the share-intent batch seam,
- mixed share-intent batches have no current way to surface which oversized GIF
  was skipped while valid sibling media still sent,
- and the current tests do not pin GIF behavior across 1:1, groups,
  announcements, feed preview surfaces, and share-intent entry points.

This plan should improve GIF support by extending the existing media pipeline,
not by introducing a parallel GIF subsystem.

---

## Real Scope

What changes in this session:

- add explicit GIF-awareness to the existing media model, preview text,
  app-generated foreground notification text, and shared image widgets
- prove that GIFs stay on the animated-image path instead of the static
  optimization path, with one recorded device/simulator confirmation that
  picked and received GIFs actually animate
- add a UI-side file-size guard at the shared wired-screen media seam and the
  share-intent batch seam without broadening into unrelated feed composition
- add lightweight skipped-media reporting for mixed share-intent batches so the
  picker can surface that an oversized GIF was omitted while valid media still
  sent
- add direct regression coverage for relay upload/send/receive, same-LAN local
  transfer, failed retry, incomplete upload recovery, download-to-disk, 1:1,
  group, announcement-admin, feed preview, and share-intent GIF behavior

What does not change in this session:

- no third-party GIF API or search provider
- no new transport, persistence, or retry architecture
- no separate announcement media pipeline
- no feed UI redesign beyond the downstream preview-text vocabulary change
- no remote push-payload authoring changes outside repo-local foreground
  notification copy
- no lifecycle / transport / recovery work outside the narrow picker/share
  guard and existing media surfaces

---

## Closure Bar

Definition of "sufficient":

A GIF is **sufficient** when all of the following hold:

| # | Criterion | How to verify |
|---|-----------|---------------|
| S1 | User can pick a `.gif` from gallery and it appears in the attachment strip with the correct GIF affordance; actual animation is manually confirmed on one device/simulator run | Widget test + recorded manual/device check |
| S2 | GIF relay upload/send/receive preserves `mime: image/gif` on the receiver | Unit test on wire envelope + integration |
| S3 | GIF renders through the animated image path in the conversation letter card (not the static optimization path) and the same surface is manually confirmed animating on device/simulator | Widget proxy + recorded manual/device check |
| S4 | GIF renders through the animated image path in the full-screen viewer and is manually confirmed animating on device/simulator | Widget proxy + recorded manual/device check |
| S5 | A "GIF" badge is visible on the thumbnail (grid cell + preview strip) | Widget test: `find.text('GIF')` |
| S6 | GIF is **not re-encoded** by `ImageProcessor` (preserves animation) | Unit test: compressFn never called for `.gif` |
| S7 | Oversized GIFs (>25 MB) are rejected before upload; single-item flows show direct failure/error feedback, and mixed share-intent batches surface structured skipped-GIF warning text while valid sibling media still sends, with existing non-GIF media size behavior unchanged | Widget test on wired screen + share-batch test + picker summary test + non-GIF control |
| S8 | Works the same across **1:1 chat**, **group discussion**, and **announcement admin send** within the current shared media pipeline | Dedicated test groups per message type |
| S9 | App-generated foreground notification body says "GIF" (not "Photo") for GIF-only messages | Unit test on `notificationBodyForMessage` + local notification integration |
| S10 | Preview text says "GIF" (not "Photo") in feed / quoted messages | Unit test on `mediaPreviewText` + direct feed widget test |
| S11 | Retry-after-failure and incomplete-upload recovery re-upload the GIF correctly in both 1:1 and group flows | Unit test on retry use cases |
| S12 | Share-intent flow preserves the raw `.gif` path, applies the same oversize rejection, and downstream share-target flow passes it through unchanged | Direct share tests + share-batch test |
| S13 | 1:1 same-LAN local transfer preserves `image/gif` metadata and file delivery on the direct `sendLocalMedia()` branch before relay upload fallback | Conversation-level branch-selection test + local-discovery direct tests + 1:1 local integration proof |

---

## Source of Truth

Planning and implementation should use these as the authoritative sources:

- this plan: `UI-22-Gifs/01-TDD-plan.md`
- current production code and existing tests in the targeted media / send / share
  surfaces
- `Test-Flight-Improv/14-regression-test-strategy.md` for regression policy
- `Test-Flight-Improv/test-gate-definitions.md` for named-gate membership and
  known-failure interpretation

Conflict rules:

- current code and tests beat stale prose
- if this plan and `test-gate-definitions.md` disagree on named gates, the
  gate-definition doc and script contract win

---

## Session Classification

`implementation-ready`

Why:

- the feature is bounded to existing media-pipeline seams
- the targeted files already exist
- the test surfaces already exist
- no third-party API, new protocol, or architecture rewrite is required

---

## Files To Inspect First

Primary production files:

- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/core/media/image_processor.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
- `lib/shared/widgets/media/full_screen_image_viewer.dart`
- `lib/shared/widgets/media/media_preview_text.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/share/application/handle_share_intent_use_case.dart`
- `lib/features/share/application/share_batch_delivery_coordinator.dart`
- `lib/features/share/application/settle_share_intent_flow.dart`
- `lib/features/share/presentation/screens/share_target_picker_screen.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- `lib/core/local_discovery/local_media_sender.dart`
- `lib/core/local_discovery/local_media_server.dart`
- `lib/core/local_discovery/local_p2p_service.dart`

Primary tests to extend:

- `test/features/conversation/domain/models/media_attachment_test.dart`
- `test/core/media/image_processor_test.dart`
- `test/shared/widgets/media/media_thumbnail_image_test.dart`
- `test/shared/widgets/media/media_preview_text_test.dart`
- `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/shared/widgets/media/full_screen_image_viewer_test.dart`
- `test/features/conversation/application/upload_media_use_case_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/share/application/handle_share_intent_use_case_test.dart`
- `test/features/share/application/share_batch_delivery_coordinator_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`
- `test/features/share/presentation/share_target_picker_screen_test.dart`
- `test/features/share/presentation/share_target_picker_wired_test.dart`
- `test/core/local_discovery/local_media_integration_test.dart`
- `test/core/local_discovery/local_media_sender_test.dart`
- `test/core/local_discovery/local_media_server_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`
- `test/features/push/application/notification_body_for_message_test.dart`

---

## Existing Tests Covering This Area

Already useful:

- `media_attachment_test.dart` covers `MediaAttachment` serialization / mapping
- `image_processor_test.dart` covers processable-image behavior
- `media_preview_text_test.dart` covers current photo/video preview labels
- `notification_body_for_message_test.dart` already covers current
  notification-body helper behavior and `maybeShowNotification` integration
- `background_push_notification_fallback_test.dart` covers payload-title/body
  passthrough and visible-notification skip behavior, which is why remote /
  background push copy stays out of scope here
- `attachment_preview_strip_test.dart` covers preview-strip rendering and remove/upload affordances
- `conversation_wired_test.dart` already covers the top-level voice-only local
  transfer branch selection in the 1:1 composer, but it does not yet pin the
  same branch for GIF media
- `upload_media_use_case_test.dart` covers mime-agnostic upload behavior
- `send_chat_message_use_case_test.dart` and `send_group_message_use_case_test.dart` cover media propagation in 1:1 and group paths
- `retry_failed_messages_use_case_test.dart` and `retry_failed_group_messages_use_case_test.dart` cover retry behavior
- `retry_incomplete_group_uploads_use_case_test.dart` covers the separate
  group resume/recovery path for persisted `upload_pending` attachments, but it
  is not yet pinned with GIF-specific cases
- `media_attachment_flow_test.dart` covers 1:1 media integration flow
- `announcement_happy_path_test.dart` covers current announcement create/send/read-only/react acceptance
- `collapsed_mode_card_body_test.dart` already covers visible feed-card
  "Photo" labels on media-only cards
- `handle_share_intent_use_case_test.dart` and `share_to_contact_smoke_test.dart` already prove raw share-intent file-path pass-through for image/video shares
- `share_batch_delivery_coordinator_test.dart` already covers once-per-share
  media processing across contact/group fanout, which is the correct seam for a
  share-intent oversize guard
- `share_target_picker_screen_test.dart` already covers the current share
  preview image path
- `share_target_picker_wired_test.dart` already covers current per-target send
  summaries, which is the UI seam that must surface skipped-GIF warnings if
  mixed batches partially send
- `local_media_integration_test.dart`, `local_media_sender_test.dart`, and
  `local_media_server_test.dart` already cover local media transfer, but only
  with JPEG/PNG/audio-style fixtures today

Still missing:

- explicit GIF animation-path widget proof plus one recorded device/simulator
  animation check
- explicit GIF preview/foreground-notification labeling proof
- explicit GIF file-size guard proof at both wired-composer and share-batch
  seams
- explicit mixed-share skipped-GIF reporting proof at the picker summary layer
- explicit GIF announcement acceptance proof
- explicit raw `.gif` share-intent pass-through proof
- explicit direct feed-surface GIF label proof
- explicit 1:1 direct local-transfer GIF proof before relay upload fallback
- explicit group incomplete-upload recovery GIF proof on the persisted
  `retryIncompleteGroupUploads` path
- explicit top-level conversation GIF branch-selection proof before relay
  upload fallback

---

## Scope Guard

**Not in scope (and why):**
- GIF search/picker API (Tenor/Giphy) — deliberate decision to avoid third-party dependency
- GIF compression/frame reduction — GIFs are small-palette; re-encoding destroys quality
- keyboard-vendor integration / paste handler — repo scope starts only once the
  OS hands us a real file/image path
- GIF recording/creation — separate feature
- a new GIF-specific transport or persistence pipeline
- feed-surface redesign beyond the downstream `mediaPreviewText` change
- remote push-payload/body generation — this plan only owns repo-local
  foreground notification copy
- no new size cap for non-GIF photo/video/file media
- transport / lifecycle / retry architecture changes unrelated to GIF metadata and rendering

## Accepted Differences / Intentionally Out Of Scope

- actual visual animation is only partially automatable in widget tests; the
  automated proof here is still the proxy "use the animated image path and do
  not force `cacheWidth` on GIFs", and closure additionally requires one
  recorded device/simulator confirmation
- mixed share-intent warning copy may surface skipped oversized GIF count and
  reason rather than exact original filenames unless the implementation
  truthfully adds file-level disclosure metadata
- keyboard-native GIF insertion remains platform behavior, not a repo-local API
- announcements remain group-style sends with admin-only write gating, not a
  separate media pipeline

---

## Code Reuse Strategy

> **Principle: Extend, don't duplicate.** The media pipeline is already
> media-type-agnostic. GIF support adds targeted behavior at 6 pinch points
> rather than a parallel pipeline.

| Layer | Reuse | GIF-specific addition |
|-------|-------|-----------------------|
| `MediaPicker` | 100% reuse — `pickMultipleMedia()` already returns GIFs | None |
| `ImageProcessor` | 100% reuse — `isProcessableImage` already excludes `.gif` | Add explicit test documenting this |
| `uploadMedia` use case | 100% reuse — mime-agnostic blob upload | Add GIF verification test |
| `sendChatMessage` / `sendGroupMessage` | 100% reuse — media array in payload | Add GIF verification test |
| Wire format (v1/v2/v3 envelopes) | 100% reuse — `MediaAttachment.toJson()` | Add GIF verification test |
| Database | 100% reuse — all queries media-type-agnostic | None |
| Retry flows | 100% reuse — `retryFailedMessages`, `retryIncompleteUploads` | Add GIF verification test |
| Download flow | 100% reuse — `downloadMedia` mime-agnostic | Add GIF verification test |
| Local 1:1 transfer | Reuse + verify | Add direct GIF proof for `sendLocalMedia()` / local media sender/server |
| `MediaAttachment` model | Reuse + extend | Add `isAnimated` getter |
| `MediaThumbnailImage` | Reuse + extend | Suppress `cacheWidth` / `cacheHeight` for GIFs at the shared thumbnail seam |
| `MediaGridCell` | Reuse + extend | Add badge; rely on `MediaThumbnailImage` for GIF animated path |
| `AttachmentPreviewStrip` | Reuse + extend | Add badge; rely on `MediaThumbnailImage` for GIF animated path |
| `FullScreenImageViewer` | Reuse + verify | Confirm GIF animates (no `cacheWidth` present) |
| `mediaPreviewText` | Modify | "GIF" label instead of "Photo" |
| `notificationBodyForMessage` | Modify | "GIF" label for repo-local foreground notification copy |
| Conversation wired (1:1) | Reuse + extend | GIF-only file size guard |
| Group conversation wired | Reuse + extend | GIF-only file size guard |
| `ShareBatchDeliveryCoordinator` | Reuse + extend | Apply the same GIF-only oversize rejection at share-intent batch processing and record skipped-GIF warning metadata |
| `ShareTargetPickerWired` | Reuse + extend | Surface skipped-GIF warning text for mixed share batches |
| `ShareTargetPickerScreen` | Reuse + extend | Keep GIF preview on the animated path by avoiding forced cache hints on the direct preview branch |

**New files: 1 production file** (`lib/core/constants/media_constants.dart` for `kMaxGifFileSize`). All other changes are modifications to existing files.
**New test files: 3** (`media_thumbnail_image_test.dart`, `media_grid_cell_test.dart`, `conversation_wired_gif_test.dart`).

---

## Component Coverage Matrix

| Component | 1:1 Chat | Group Discussion | Announcement (admin) | Notes |
|-----------|----------|------------------|----------------------|-------|
| Gallery pick | Y | Y | Y | Same `MediaPicker` in both wired screens |
| Keyboard insert | Y | Y | Y | OS-provided path only once the app receives a real file/image |
| Image processing bypass | Y | Y | Y | Shared `ImageProcessor` |
| Upload | Y | Y | Y | Same `uploadMedia` use case |
| Wire envelope | v1/v2 | v3 | v3 | GIF in `media[]` array |
| Send | Y | Y | Y (admin only) | `_canWriteForGroup` gates non-admins |
| Receive + parse | Y | Y | Y | Listeners are mime-agnostic |
| Download | Y | Y | Y | Shared `downloadMedia` use case |
| Animated display | Y | Y | Y | Shared `MediaGridCell` |
| Full-screen viewer | Y | Y | Y | Shared `FullScreenImageViewer` |
| GIF badge | Y | Y | Y | Shared widget |
| Push notification | Y | Y | Y | Shared repo-local foreground notification body via `notificationBodyForMessage` |
| Preview text | Y | Y | Y | Shared `mediaPreviewText` |
| Retry on failure | Y | Y | Y | Shared retry use cases |
| File size guard | Y | Y | Y | Both wired screens and share-intent batch apply the same GIF-only 25 MB rule; non-GIF media keeps existing behavior |
| Share extension | Y | Y | — | Current share-target flow supports contacts and groups; GIF path stays unchanged and uses the same oversize rejection |

---

## Regression / Tests To Add First

Before broad implementation work, add the smallest direct proofs that pin the
intended GIF contract:

1. `media_attachment_test.dart`
   - add `isAnimated` coverage so later consumers share one GIF predicate
2. `image_processor_test.dart`
   - lock the explicit GIF bypass so animation-preserving behavior cannot drift
3. `media_preview_text_test.dart`,
   `collapsed_mode_card_body_test.dart`, and
   `notification_body_for_message_test.dart`
   - pin user-visible "GIF" vocabulary in helper, feed surface, and
     foreground notification copy before touching widgets
4. `media_thumbnail_image_test.dart`,
   `media_grid_cell_test.dart`,
   `attachment_preview_strip_test.dart`, and
   `share_target_picker_screen_test.dart`
   - pin the shared thumbnail seam plus the one remaining direct share-preview
     caller before changing GIF rendering behavior
5. `conversation_wired_gif_test.dart` and
   `share_batch_delivery_coordinator_test.dart` and
   `share_target_picker_wired_test.dart`
   - pin the GIF-only file-size guard at both the picker seam and the
     share-intent batch seam before implementation, including a non-GIF control
     so existing photo/video behavior cannot regress and a mixed-share warning
     proof so skipped oversized GIFs are surfaced truthfully
6. `announcement_happy_path_test.dart`, share-intent tests, local media
   discovery tests, and one top-level `conversation_wired_test.dart` GIF case
   - pin `S8`, `S12`, and `S13` directly so announcement/share/local-LAN proof
     is not left implicit and branch selection is proved at the actual 1:1
     composer seam

These regression-first steps keep the plan narrow and reduce hallucinated
implementation drift.

---

## Step-by-Step Implementation Plan

Each phase: **write failing test → implement → green → refactor**.

---

### Phase 1: `MediaAttachment.isAnimated` getter

**Why first:** Every later phase references this getter. Establish the API before consumers use it.

**Test file:** `test/features/conversation/domain/models/media_attachment_test.dart`

```
group('isAnimated')
  test('returns true for image/gif')
    → MediaAttachment(mime: 'image/gif', ...).isAnimated == true

  test('returns false for image/jpeg')
    → MediaAttachment(mime: 'image/jpeg', ...).isAnimated == false

  test('returns false for image/png')
    → .isAnimated == false

  test('returns false for video/mp4')
    → .isAnimated == false

  test('returns false for audio/m4a')
    → .isAnimated == false
```

**Production file:** `lib/features/conversation/domain/models/media_attachment.dart`

```dart
bool get isAnimated => mime == 'image/gif';
```

**Lines changed:** ~1

---

### Phase 2: `ImageProcessor` — Explicit GIF bypass documentation

**Why:** GIF bypass is currently implicit (`.gif` not in the processable set). Tests lock this behavior so nobody accidentally adds `'gif'` to the set and breaks animation.

**Test file:** `test/core/media/image_processor_test.dart`

```
group('isProcessableImage')
  test('returns false for .gif (preserves animation)')
    → expect(processor.isProcessableImage('photo.gif'), false)
    → expect(processor.isProcessableImage('animation.GIF'), false)

group('processImage')
  test('returns original path unchanged for .gif file')
    → result = processImage(inputPath: '/tmp/funny.gif', quality: compressed)
    → expect(result, '/tmp/funny.gif')

  test('does NOT invoke CompressFileFn for .gif files')
    → bool compressCalled = false
    → processImage with .gif path
    → expect(compressCalled, false)
```

**Production file:** None — tests only. Behavior already correct.

---

### Phase 3: `mediaPreviewText` + `notificationBodyForMessage` — "GIF" label

**Why:** Users still see "Photo" for GIFs in feed previews and repo-local
foreground notifications. Confusing — should say "GIF". Remote/background push
payload copy remains owned by its existing payload path and is out of scope for
this session.

**Prerequisite:** Phase 1 (`isAnimated` getter) must be complete. Both `mediaPreviewText` and `notificationBodyForMessage` currently switch on `mediaType` (a string), which is `'image'` for GIFs. Use the `isAnimated` getter to distinguish GIFs from static photos — do not duplicate `mime == 'image/gif'` checks.

**Downstream effect:** `collapsed_mode_card_body.dart:346` calls `mediaPreviewText(msg.media)` for feed card preview text. Changing `mediaPreviewText` to return `"GIF"` will automatically propagate to collapsed feed cards. This is desirable (no production change needed in that file), but must be verified by the test below.

**Implementation note for `mediaPreviewText`:** Separate GIF count from photo count using `isAnimated`:
```dart
final gifCount = media.where((a) => a.isAnimated).length;
final imageCount = media.where((a) => a.mediaType == 'image' && !a.isAnimated).length;
```

**Implementation note for `notificationBodyForMessage`:** In the `'image'` branch, check `media.every((a) => a.isAnimated)` to return `'GIF'` vs `'Photo'`. Mixed GIF+photo messages return `'Photo'` (acceptable — notification body doesn't need "GIF · Photo" granularity).

**Test file:** `test/shared/widgets/media/media_preview_text_test.dart` (add to existing)

```
group('GIF preview text')
  test('single GIF returns "GIF"')
    → mediaPreviewText([gifAttachment]) == 'GIF'

  test('multiple GIFs returns "N GIFs"')
    → mediaPreviewText([gif1, gif2]) == '2 GIFs'

  test('GIF + photo returns "GIF · Photo"')
    → mixed list → 'GIF · Photo'

  test('GIF + video returns "GIF · Video"')
    → mixed list → 'GIF · Video'

```

**Test file:** `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart` (add to existing)

```
group('GIF feed preview')
  testWidgets('media-only message shows thumbnail + GIF label')
    → use downloaded GIF attachment
    → expect(find.text('GIF'), findsOneWidget)

  testWidgets('group card media-only message shows thumbnail + GIF label')
    → use downloaded GIF attachment in group thread
    → expect(find.text('GIF'), findsOneWidget)
```

**Test file:** `test/features/push/application/notification_body_for_message_test.dart` (add to existing — NOT `show_notification_use_case_test.dart`)

```
group('GIF notification body')
  test('returns "GIF" for single GIF-only message')
    → notificationBodyForMessage('', [gifAttachment]) == 'GIF'

  test('returns text when message has text + GIF')
    → notificationBodyForMessage('check this out', [gifAttachment]) == 'check this out'

group('GIF foreground notification integration')
  test('maybeShowNotification uses "GIF" for GIF-only 1:1 messages')
    → verify shown notification body is 'GIF'
```

**Production files:**
- `lib/shared/widgets/media/media_preview_text.dart` — use `isAnimated` to separate GIF count from image count
- `lib/features/push/application/show_notification_use_case.dart` — add GIF detection in `'image'` branch

**Lines changed:** ~15

---

### Phase 4: `MediaThumbnailImage` + `MediaGridCell` — Animated display + GIF badge

**Why:** `MediaGridCell` is not the real cache-hint seam. It currently passes
`cacheWidth: 400` into `MediaThumbnailImage`, and feed collapsed thumbnails
also reuse `MediaThumbnailImage` with their own cache hints. The shared
thumbnail widget must suppress `cacheWidth` / `cacheHeight` for GIFs so grid,
feed, and attachment-strip callers inherit the animated path. `MediaGridCell`
still owns the visible GIF badge.

**Test file:** `test/shared/widgets/media/media_thumbnail_image_test.dart` (new)

```
group('GIF thumbnail cache hints')
  test('ignores cacheWidth/cacheHeight for GIF paths even when caller provides them')
    → pump MediaThumbnailImage(mediaPath: '/tmp/funny.gif', mediaType: 'image', cacheWidth: 400, cacheHeight: 400)
    → inspect Image widget → verify cacheWidth/cacheHeight are null

  test('retains cacheWidth/cacheHeight for JPEG paths')
    → pump MediaThumbnailImage(mediaPath: '/tmp/photo.jpg', mediaType: 'image', cacheWidth: 400, cacheHeight: 400)
    → inspect Image widget → verify cacheWidth/cacheHeight remain set
```

**Test file:** `test/shared/widgets/media/media_grid_cell_test.dart` (new)

```
group('GIF rendering')
  test('renders GIF attachment through MediaThumbnailImage and shows badge')
    → create GIF MediaAttachment (done, localPath exists)
    → pump MediaGridCell
    → expect(find.byType(MediaThumbnailImage), findsOneWidget)
    → expect(find.text('GIF'), findsOneWidget)

  test('shows "GIF" badge for GIF attachment when downloaded')
    → pump GIF attachment with downloadStatus: 'done'
    → expect(find.text('GIF'), findsOneWidget)

  test('does NOT show "GIF" badge for JPEG')
    → pump JPEG attachment
    → expect(find.text('GIF'), findsNothing)

  test('does NOT show "GIF" badge when download pending')
    → pump GIF with downloadStatus: 'pending'
    → expect(find.text('GIF'), findsNothing)

  test('does NOT show video overlay for GIF')
    → GIF mediaType is 'image', not 'video'
    → expect VideoThumbnailOverlay absent

  test('tapping GIF cell fires onTap callback')
    → pump with onTap
    → tap → verify callback
```

**Production files:**
- `lib/shared/widgets/media/media_thumbnail_image.dart` — suppress
  `cacheWidth` / `cacheHeight` for GIF image paths while retaining them for
  non-GIF images and video thumbnails
- `lib/shared/widgets/media/media_grid_cell.dart` — add GIF badge; rely on the
  shared thumbnail widget for the animated path

Changes:
- `MediaThumbnailImage._buildImage()`: if the image path is `.gif`, render
  without `cacheWidth` / `cacheHeight`
- `build()` Stack: add `if (attachment.isAnimated && isDone)` → "GIF" badge (bottom-left, semi-transparent background)

**Lines changed:** ~30

---

### Phase 5: `AttachmentPreviewStrip` — GIF thumbnail + badge

**Why:** Preview strip still needs a visible GIF badge. Its animated-image path
should now come from the shared `MediaThumbnailImage` fix in Phase 4 rather
than from strip-specific cache-hint logic.

**Test file:** `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`

```
group('GIF thumbnails')
  test('GIF file renders as thumbnail')
    → create temp .gif file
    → pump with [gifFile]
    → expect Image widget

  test('GIF thumbnail shows "GIF" badge')
    → pump with .gif file
    → expect(find.text('GIF'), findsOneWidget)

  test('JPEG thumbnail does NOT show "GIF" badge')
    → pump with .jpg file
    → expect(find.text('GIF'), findsNothing)

  test('GIF badge hidden during upload')
    → pump with isUploading: true
    → expect(find.text('GIF'), findsNothing)

  test('GIF thumbnail remove button works')
    → tap X → verify onRemove(index)
```

**Production file:** `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`

Changes:
- `_Thumbnail`: keep using `MediaThumbnailImage`; add "GIF" badge (small,
  bottom-left) hidden during upload overlay

**Lines changed:** ~20

---

### Phase 6: `FullScreenImageViewer` — Verify GIF animation

**Why:** Viewer uses `Image.file()` without `cacheWidth` — should animate
natively. Need test to lock this. Automated proof here stays a seam proxy; the
final closure still requires one recorded device/simulator confirmation that a
picked or received GIF visibly animates in the viewer.

**Test file:** `test/shared/widgets/media/full_screen_image_viewer_test.dart` (new or extend)

```
group('GIF full-screen')
  test('renders Image.file for GIF path without cacheWidth')
    → pump FullScreenImageViewer(localPath: '/tmp/funny.gif')
    → find Image widget → verify no cacheWidth set

  test('InteractiveViewer wraps GIF for pinch-to-zoom')
    → verify InteractiveViewer present

  test('swiping between GIF and JPEG works')
    → pump with allPaths: [gif, jpeg]
    → swipe → verify page changes
```

**Production file:** None expected — verify existing behavior. If `cacheWidth` is found, remove it for GIF paths.

---

### Phase 7: GIF-only file size guard

**Why:** GIFs can be 50MB+. Reject oversized GIFs before upload or share
fanout without introducing a new general cap for photo/video/file media.

**Guard placement:** The 25 MB rule should be enforced in the three
repo-local messaging entry seams that currently prepare/send pending media:
`_preparePendingMedia()` in `conversation_wired.dart`,
`_preparePendingMedia()` in `group_conversation_wired.dart`, and
`_processSharedMedia()` in `share_batch_delivery_coordinator.dart`.

Because those seams also handle normal image/video picks, the guard must be
behind a GIF-specific predicate, for example
`_mimeFromPath(path) == 'image/gif'` or one small shared helper with the same
meaning. Do not apply the 25 MB check to non-GIF media.

Do **not** place this guard inside `preparePendingComposerMedia()` itself:
`feed_wired.dart` also uses that helper, and broadening feed composition is out
of scope for this session.

**Mixed-share reporting note:** `deliver()` preprocesses files once before
fanout, while `ShareTargetPickerWired` currently only summarizes per-target
send/queue/failure counts. If a mixed batch drops one oversized GIF but still
sends a valid JPEG, the existing result contract cannot surface that omission.
This plan therefore includes one lightweight result-shape extension: record
skipped GIF count/reason metadata on the share-batch result and surface that in
the picker summary/snackbar. Do not promise exact per-file UI disclosure unless
the implementation genuinely adds it.

- `conversation_wired.dart`: `_pickFromGallery` (~line 2120), `_pickFromCamera` (~line 2180), `_pickVideoFromCamera` (~line 2199) — all call `_preparePendingMedia()` (~line 829)
- `group_conversation_wired.dart`: `_pickFromGallery` (~line 1673), `_pickFromCamera` (~line 1729), `_pickVideoFromCamera` (~line 1746) — all call `_preparePendingMedia()`
- `share_batch_delivery_coordinator.dart`: `_processSharedMedia()` (~line 184)
  is the share-intent seam that currently turns raw file paths into
  `PendingComposerMedia` before fanout to contacts/groups

**Note:** There is also a cumulative budget check in `_attemptAddPendingMedia()` against `maxAttachmentBudgetBytes` (5 GB default). The per-file guard here is a tighter, user-facing limit at a different layer.

**Constant file:** `lib/core/constants/media_constants.dart` (new, following pattern of `retry_constants.dart` and `network_constants.dart`):
```dart
const int kMaxGifFileSize = 25 * 1024 * 1024; // 25 MB
```

**Note:** The codebase has an existing 100 MB limit in `send_voice_message_use_case.dart:20` (voice message transport limit) and a 5 GB limit in `lib/core/local_discovery/local_media_server.dart:43` (local media server). The 25 MB `kMaxGifFileSize` is a GIF-only picker/share guard — a different layer with a tighter bound. Existing non-GIF media limits remain intentional and unchanged.

**Test file:** `test/features/conversation/presentation/screens/conversation_wired_gif_test.dart` (new)

```
group('file size guard — 1:1')
  test('file under 25MB accepted → appears in pending media')
    → configure FakeMediaPicker to return small .gif
    → trigger attach via gallery
    → verify attachment strip shows file

  test('file over 25MB rejected → not in pending media')
    → configure picker to return 30MB .gif
    → trigger attach via gallery
    → verify attachment strip empty
    → verify error shown (snackbar / callback)

  test('large JPEG over 25MB is not rejected by the GIF-only guard')
    → configure picker to return 30MB .jpg
    → trigger attach via gallery
    → verify existing non-GIF flow remains in effect

  test('mixed pick: oversized file rejected, valid JPEG kept')
    → pick [30MB.gif, 2MB.jpg]
    → verify only JPEG in pending media

group('file size guard — group')
  test('same guard applies in group conversation wired')
    → same pattern in group context

group('file size guard — share intent batch')
  test('oversized GIF is rejected before share fanout')
    → ShareIntent(filePaths: ['/tmp/30mb.gif'])
    → deliver(...)
    → verify no processed media is fanned out and skipped-GIF metadata is recorded

  test('mixed share keeps valid JPEG while rejecting oversized GIF')
    → ShareIntent(filePaths: ['/tmp/30mb.gif', '/tmp/ok.jpg'])
    → deliver(...)
    → verify JPEG is still processed, oversized GIF is rejected, and skipped-GIF metadata is recorded
```

**Test file:** `test/features/share/presentation/share_target_picker_wired_test.dart` (add to existing)

```
group('mixed share skipped GIF reporting')
  testWidgets('successful send with skipped oversized GIF surfaces warning text')
    → coordinator returns sent target result + skippedGifCount/skippedReason metadata
    → tap Send
    → verify snackbar mentions target success plus oversized GIF skipped warning
```

**Production files:**
- `lib/core/constants/media_constants.dart` — NEW: `kMaxGifFileSize` constant
- `lib/features/conversation/presentation/screens/conversation_wired.dart` — GIF-only guard at top of `_preparePendingMedia()`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — GIF-only guard at top of `_preparePendingMedia()`
- `lib/features/share/application/share_batch_delivery_coordinator.dart` —
  GIF-only guard at top of `_processSharedMedia()` plus skipped-GIF warning metadata
- `lib/features/share/presentation/screens/share_target_picker_wired.dart` —
  surface skipped-GIF warning text for mixed share batches

Changes in each `_preparePendingMedia()`:
```dart
if (_mimeFromPath(path) == 'image/gif' &&
    File(path).lengthSync() > kMaxGifFileSize) {
  // reject — throw or return null depending on return type
}
```

**Lines changed:** ~10 per wired screen + ~10 in share batch + 1 new constant
file

---

### Phase 8: Upload — GIF verification

**Why:** Upload is mime-agnostic but needs explicit GIF test to prevent regressions.

**Test file:** `test/features/conversation/application/upload_media_use_case_test.dart`

```
group('GIF upload')
  test('uploads GIF with mime image/gif to bridge')
    → create temp .gif file
    → uploadMedia(mime: 'image/gif', ...)
    → verify bridge received mime: 'image/gif'

  test('GIF copied to durable storage with .gif extension')
    → verify mediaFileManager path ends with .gif

  test('flow events include mime: image/gif')
    → capture events → verify MEDIA_UPLOAD_START has mime
```

**Production file:** None — verification tests only.

---

### Phase 9: Send — GIF in wire envelope (1:1 + group)

**Why:** Verify GIF metadata propagates correctly through serialization.

**Test file:** `test/features/conversation/application/send_chat_message_use_case_test.dart`

```
group('GIF in 1:1 wire envelope')
  test('v1 envelope media array includes mime: image/gif')
    → send with GIF attachment
    → parse wireEnvelope → media[0].mime == 'image/gif'

  test('GIF-only message (no text) passes validation')
    → sendChatMessage(text: '', media: [gifAttachment])
    → expect success (not rejected)
```

**Test file:** `test/features/groups/application/send_group_message_use_case_test.dart`

```
group('GIF in group wire envelope')
  test('group publish includes GIF in media array')
    → capture bridge callGroupPublish args
    → verify media[0].mime == 'image/gif'

  test('group inbox store includes GIF metadata')
    → verify inbox payload includes GIF
```

**Production file:** None — verification tests only.

---

### Phase 10: Receive — incoming GIF parsed correctly

**Test file:** `test/features/conversation/domain/models/media_attachment_test.dart`

```
group('GIF fromJson')
  test('parses GIF from wire payload')
    → fromJson({id, mime: 'image/gif', size: 500000})
    → verify .mime, .mediaType == 'image', .isAnimated == true

  test('defaults mediaType to image when omitted')
    → fromJson without mediaType field
    → verify mediaTypeFromMime fallback → 'image'
```

**Production file:** None — verification tests only.

---

### Phase 11: Retry — GIF survives failure recovery

**Why expanded:** The existing media retry suite has 80+ tests covering transient failure,
max-retry exhaustion, partial multi-attachment crash recovery, and inbox fallback — all
using JPEG/MP4 fixtures. GIF bypasses `ImageProcessor` (no re-compression on retry), so
the retry path is subtly different and needs explicit proof.

**Test file:** `test/features/conversation/application/retry_failed_messages_use_case_test.dart`

```
group('GIF retry')
  test('failed GIF message retries with correct mime')
    → create failed message with GIF attachment
    → retry → verify re-upload called with mime: 'image/gif'

  test('GIF retry via inbox fallback preserves media metadata in wire envelope')
    → create failed GIF message with wireEnvelope already set
    → retry → verify inbox store receives envelope with media[0].mime == 'image/gif'
    → verify no re-encrypt (envelope reused as-is)
```

**Test file:** `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`

```
group('GIF upload retry')
  test('GIF transient upload failure increments retryCount and stays upload_pending')
    → create upload_pending GIF attachment (retryCount: 0)
    → bridge returns transient error
    → verify retryCount incremented to 1, status still upload_pending

  test('GIF upload after kMaxUploadRetries exhaustion transitions to upload_failed')
    → create upload_pending GIF attachment (retryCount: kMaxUploadRetries)
    → bridge returns transient error
    → verify status transitions to upload_failed (terminal)

  test('partial multi-attachment GIF + JPEG: crash recovery re-uploads only pending GIF')
    → create message with 2 attachments:
      - JPEG: downloadStatus = 'done' (already uploaded)
      - GIF: downloadStatus = 'upload_pending'
    → trigger retryIncompleteUploads
    → verify upload called only for GIF (mime: 'image/gif')
    → verify JPEG not re-uploaded
    → on success: verify send called with both attachments
```

**Test file:** `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`

```
group('GIF group retry')
  test('failed group GIF retries correctly')
    → same pattern for group retry
```

**Test file:** `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`

```
group('GIF group incomplete upload recovery')
  test('reuploads only group upload_pending GIF attachments and reuses blobId')
    → create group message with one done JPEG + one upload_pending GIF
    → trigger retryIncompleteGroupUploads
    → verify upload called only for GIF with mime: 'image/gif'
    → verify final group publish/inbox store uses both attachments

  test('group GIF transient failure increments retryCount and reaches upload_failed at max')
    → create upload_pending GIF attachment on group message
    → first transient failure increments retryCount
    → max retry exhaustion transitions to upload_failed
```

**Production file:** None — verification tests only.

---

### Phase 12: Integration — end-to-end

**Why expanded:** The existing media integration suite (14 tests) covers send/receive,
multi-attachment, and stale upload recovery — all with JPEG/video. GIF needs proof that
the full lifecycle works, including download state transitions (the download use case
validates file size > 0 and actual size matches expected).

**Local-path note:** Direct 1:1 chat sends try `sendLocalMedia()` before relay
upload when the peer is local. That same-LAN branch must be pinned for GIFs, or
the plan can go green on relay/upload paths while local delivery still breaks.

**Branch-selection note:** The lower-level local media sender/server suites
prove helper behavior, but `S13` also needs one conversation-level proof that
the GIF send path in `conversation_wired.dart` actually chooses
`sendLocalMedia()` before relay upload when the peer is local.

**Test file:** `test/features/conversation/integration/media_attachment_flow_test.dart`

```
group('GIF end-to-end')
  test('1:1: pick GIF → upload → send → receive with mime image/gif')
    → full send/receive cycle with TestUser network
    → verify receiver MediaAttachment: mime, mediaType, isAnimated

  test('1:1: GIF + text both arrive')
    → send message with text + GIF
    → verify both present on receiver

  test('group: GIF arrives to all members')
    → group pubsub cycle
    → verify GIF attachment on receiver

  test('GIF download: pending → downloading → done with mime preserved')
    → receive message with GIF attachment (downloadStatus: 'pending')
    → trigger downloadMedia
    → verify status transitions: pending → downloading → done
    → verify downloaded attachment has mime: 'image/gif', isAnimated: true
    → verify file exists on disk with .gif extension

  test('GIF + JPEG multi-attachment: correct order preserved through send/receive')
    → send message with [GIF, JPEG] attachments
    → receive on other side
    → verify media[0].mime == 'image/gif', media[1].mime == 'image/jpeg'
    → verify ordering matches sender's original order
```

**Test file:** `test/core/local_discovery/local_media_integration_test.dart`

```
group('GIF local media integration')
  test('sender uploads GIF, receiver gets file at local path, SHA-256 matches')
    → send local media with mime: 'image/gif'
    → verify LocalMediaReady mime, hash, and .gif local path
```

**Test file:** `test/features/conversation/presentation/screens/conversation_wired_test.dart`

```
group('GIF local branch selection')
  testWidgets('local-peer GIF transport is attempted before relay upload')
    → configure local peer + tracking P2P service
    → send GIF attachment from conversation wired
    → verify sendLocalMedia called before relay upload fallback path
    → verify optimistic upload_pending persistence remains truthful for the branch
```

**Test file:** `test/core/local_discovery/local_media_sender_test.dart`

```
group('GIF local media sender')
  test('sends media_offer via WS with image/gif mime and required fields')
    → verify media_offer includes mime: 'image/gif', sha256, size, nonce
```

**Test file:** `test/core/local_discovery/local_media_server_test.dart`

```
group('GIF local media server')
  test('accepts image/gif among allowed MIME prefixes')
    → acceptOffer(mime: 'image/gif') == true
```

**Production file:** None — integration tests only.

---

### Phase 13: Announcement acceptance — GIF admin send / reader receive

**Why:** `S8` currently claims announcement-admin parity. That needs direct
announcement acceptance proof, not just shared group-envelope tests.

**Test file:** `test/features/groups/integration/announcement_happy_path_test.dart`

```
group('GIF announcement acceptance')
  test('admin can send GIF announcement and reader receives mime image/gif')
    → announcement happy-path setup
    → admin sends GIF-only message
    → reader receives message with media[0].mime == 'image/gif'

  test('reader remains read-only after GIF announcement arrives')
    → same setup
    → verify non-admin reader still sees read-only composer state
```

**Production file:** None — acceptance tests only.

---

### Phase 14: Share-intent pass-through — GIF unchanged

**Why:** `S12` is part of the closure bar. It needs direct proof that the raw
`.gif` path survives the share-intent path, lands unchanged in the picker /
compose flow, and still follows the same oversize-rejection rule at the share
batch seam. The share-target picker preview also has one direct thumbnail path
that currently bypasses `MediaThumbnailImage`, so the plan must pin that caller
too.

**Test file:** `test/features/share/application/handle_share_intent_use_case_test.dart`

```
group('GIF share pass-through')
  test('GIF shares pass raw file paths to the picker')
    → ShareIntent(filePaths: ['/tmp/funny.gif'])
    → tap share now
    → verify picker receives the same .gif path unchanged
```

**Test file:** `test/features/share/integration/share_to_contact_smoke_test.dart`

```
group('GIF share smoke')
  test('share GIF to 1:1 contact shows pending attachment unchanged')
    → ShareIntent(filePaths: ['/tmp/shared.gif'])
    → pick 1:1 target
    → verify pending attachment uses the same .gif path
```

**Test file:** `test/features/share/presentation/share_target_picker_screen_test.dart` (add to existing)

```
group('GIF share preview')
  testWidgets('GIF preview does not wrap FileImage in ResizeImage')
    → sharedFilePaths: ['/tmp/shared.gif']
    → inspect preview Image
    → verify GIF path avoids forced cacheWidth/cacheHeight
```

**Production files:**
- `lib/features/share/presentation/screens/share_target_picker_screen.dart` —
  keep the current preview UI but avoid forced cache hints on the direct GIF
  preview path
- `lib/features/share/application/handle_share_intent_use_case.dart` and
  friends — share-path verification only unless repo evidence proves otherwise

---

## Implementation Order Summary

| Step | Phase | Tests | Prod change | Effort |
|------|-------|-------|-------------|--------|
| 1 | Phase 1: `isAnimated` getter | 5 | 1 line | S |
| 2 | Phase 2: ImageProcessor GIF bypass | 3 | 0 lines | S |
| 3 | Phase 3: Preview text + notification label | 7 | ~15 lines | S |
| 4 | Phase 4: MediaThumbnailImage + MediaGridCell | 9 | ~30 lines | M |
| 5 | Phase 5: AttachmentPreviewStrip badge | 5 | ~20 lines | M |
| 6 | Phase 6: FullScreenImageViewer verify | 3 | 0 lines | S |
| 7 | Phase 7: GIF-only file size guard (wired seams + share batch) | 8 | ~36 lines + 1 new file | M |
| 8 | Phase 8: Upload verification | 3 | 0 lines | S |
| 9 | Phase 9: Send wire envelope | 4 | 0 lines | S |
| 10 | Phase 10: Receive parsing | 2 | 0 lines | S |
| 11 | Phase 11: Retry reliability | 6 | 0 lines | M |
| 12 | Phase 12: Integration e2e | 8 | 0 lines | M |
| 13 | Phase 13: Announcement acceptance | 2 | 0 lines | S |
| 14 | Phase 14: Share-intent pass-through | 3 | ~8 lines | S |
| **Total** | | **70 tests** | **~114 lines + 1 new file** | |

---

## Production Files Modified

| File | What changes |
|------|-------------|
| `lib/features/conversation/domain/models/media_attachment.dart` | `isAnimated` getter |
| `lib/shared/widgets/media/media_thumbnail_image.dart` | Suppress forced `cacheWidth` / `cacheHeight` for GIF paths |
| `lib/shared/widgets/media/media_grid_cell.dart` | GIF badge; rely on `MediaThumbnailImage` for the animated path |
| `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart` | GIF badge; rely on `MediaThumbnailImage` for the animated path |
| `lib/shared/widgets/media/media_preview_text.dart` | "GIF" / "N GIFs" label (also affects `collapsed_mode_card_body.dart` downstream) |
| `lib/features/push/application/show_notification_use_case.dart` | "GIF" in notification body |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | GIF-only file size guard in `_preparePendingMedia()` |
| `lib/features/groups/presentation/screens/group_conversation_wired.dart` | GIF-only file size guard in `_preparePendingMedia()` |
| `lib/features/share/application/share_batch_delivery_coordinator.dart` | GIF-only file size guard in `_processSharedMedia()` plus skipped-GIF warning metadata |
| `lib/features/share/presentation/screens/share_target_picker_wired.dart` | Surface skipped-GIF warning text for mixed share batches |
| `lib/features/share/presentation/screens/share_target_picker_screen.dart` | Avoid forced cache hints on the direct GIF preview path |
| `lib/core/constants/media_constants.dart` | **NEW:** `kMaxGifFileSize = 25 * 1024 * 1024` |

## New Test Files

| File | Purpose |
|------|---------|
| `test/shared/widgets/media/media_thumbnail_image_test.dart` | Shared GIF thumbnail cache-hint suppression |
| `test/shared/widgets/media/media_grid_cell_test.dart` | GIF rendering + badge |
| `test/features/conversation/presentation/screens/conversation_wired_gif_test.dart` | File size guard |

## Existing Test Files Extended

| File | Tests added |
|------|------------|
| `test/features/conversation/domain/models/media_attachment_test.dart` | `isAnimated`, GIF fromJson |
| `test/core/media/image_processor_test.dart` | GIF bypass |
| `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart` | GIF thumbnail + badge |
| `test/shared/widgets/media/media_preview_text_test.dart` | GIF label |
| `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart` | Direct feed-surface GIF label |
| `test/features/push/application/notification_body_for_message_test.dart` | GIF notification |
| `test/features/conversation/application/upload_media_use_case_test.dart` | GIF upload |
| `test/features/conversation/application/send_chat_message_use_case_test.dart` | GIF in envelope |
| `test/features/groups/application/send_group_message_use_case_test.dart` | GIF in group envelope |
| `test/features/conversation/application/retry_failed_messages_use_case_test.dart` | GIF retry + inbox fallback |
| `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart` | GIF transient failure, max retry exhaustion, partial multi-attachment recovery |
| `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` | GIF group retry |
| `test/features/conversation/integration/media_attachment_flow_test.dart` | GIF e2e + download state transitions + multi-attachment ordering |
| `test/shared/widgets/media/full_screen_image_viewer_test.dart` | GIF animation |
| `test/features/groups/integration/announcement_happy_path_test.dart` | GIF announcement admin-send / reader-receive acceptance |
| `test/features/share/application/handle_share_intent_use_case_test.dart` | Raw `.gif` share-intent path pass-through |
| `test/features/share/application/share_batch_delivery_coordinator_test.dart` | Share-batch oversize rejection + pass-through |
| `test/features/share/integration/share_to_contact_smoke_test.dart` | GIF share-to-contact pending attachment smoke |
| `test/features/share/presentation/share_target_picker_screen_test.dart` | Direct GIF share preview cache-hint suppression |
| `test/features/share/presentation/share_target_picker_wired_test.dart` | Mixed-share skipped-GIF warning summary |
| `test/features/conversation/presentation/screens/conversation_wired_test.dart` | Top-level GIF local-branch selection before relay fallback |
| `test/core/local_discovery/local_media_integration_test.dart` | GIF same-LAN file delivery |
| `test/core/local_discovery/local_media_sender_test.dart` | GIF local media offer metadata |
| `test/core/local_discovery/local_media_server_test.dart` | GIF local media MIME acceptance |

---

## Risk Register

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Shared thumbnail callers freeze GIF as static via forced cache hints | Medium | Phase 4 fixes `MediaThumbnailImage`, and Phase 14 fixes the remaining direct share-preview caller |
| Large GIFs cause OOM on low-end devices | Medium | Phase 7 GIF-only file size guard (25 MB cap) |
| Mixed share silently drops oversized GIF while valid sibling media still sends | Medium | Phase 7 adds skipped-GIF result metadata plus picker warning proof |
| `image_picker` doesn't return GIFs on some Android versions | Low | Depends on OS — out of our control; works on stock Android 10+ |
| GIF animation causes jank in conversation scroll | Low | `MediaGridCell` renders at grid size; only full-screen is full-res |
| Same-LAN 1:1 direct transfer diverges from relay/upload GIF behavior | Medium | Phase 12 adds direct local media sender/server/integration GIF proof |
| Re-encoding GIF via `flutter_image_compress` destroys animation | None | Phase 2 locks bypass behavior — `.gif` excluded from processable set |

---

## Exact Tests And Gates To Run

Direct suites from this plan:

- `test/features/conversation/domain/models/media_attachment_test.dart`
- `test/core/media/image_processor_test.dart`
- `test/shared/widgets/media/media_thumbnail_image_test.dart`
- `test/shared/widgets/media/media_preview_text_test.dart`
- `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
- `test/features/push/application/notification_body_for_message_test.dart`
- `test/shared/widgets/media/media_grid_cell_test.dart`
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `test/shared/widgets/media/full_screen_image_viewer_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_gif_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/application/upload_media_use_case_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`
- `test/features/share/application/handle_share_intent_use_case_test.dart`
- `test/features/share/application/share_batch_delivery_coordinator_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`
- `test/features/share/presentation/share_target_picker_screen_test.dart`
- `test/features/share/presentation/share_target_picker_wired_test.dart`
- `test/core/local_discovery/local_media_integration_test.dart`
- `test/core/local_discovery/local_media_sender_test.dart`
- `test/core/local_discovery/local_media_server_test.dart`

Required manual/device acceptance (not replaced by widget tests):

- on one simulator or device, pick a local GIF and confirm visible animation in
  the attachment strip/grid and the full-screen viewer
- on one simulator or device, receive a GIF message and confirm visible
  animation in the conversation media surface and the full-screen viewer

Named gates required by this plan:

- `./scripts/run_test_gates.sh 1to1`
  - required because this plan changes 1:1 attachment preview / wired picker
    behavior and 1:1 media send surfaces
- `./scripts/run_test_gates.sh groups`
  - required because this plan changes shared group-discussion / announcement
    media surfaces and file-size guard behavior
- `./scripts/run_test_gates.sh feed`
  - required because `mediaPreviewText` feeds collapsed feed-card preview text
- `./scripts/run_test_gates.sh baseline`
  - required because Flutter production files change

Not required by default:

- `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`
  - not required unless the actual implementation escapes into lifecycle,
    startup, transport, or recovery wiring

Notes:

- `announcement_happy_path_test.dart` stays outside the frozen named gate lists
  in `test-gate-definitions.md`, but it is still required as a direct suite
  because `S8` depends on announcement-admin acceptance proof
- `share_to_contact_smoke_test.dart` and
  `share_batch_delivery_coordinator_test.dart`,
  `share_target_picker_screen_test.dart`, and
  `share_target_picker_wired_test.dart` are also required direct suites even
  though they are not part of named gates, because `S7` and `S12` depend on
  them
- `conversation_wired_test.dart` is also a required direct suite even though it
  is not part of a named gate, because `S13` depends on top-level GIF branch
  selection before relay fallback
- the local media direct suites are required even though they are outside named
  gates, because `S13` depends on the same-LAN branch before relay upload

---

## Known-Failure Interpretation

- Use `Test-Flight-Improv/test-gate-definitions.md` as the source of truth for
  named-gate membership and known-failure handling
- Pre-existing red tests outside the touched GIF surfaces are not GIF
  regressions unless this change clearly caused or widened them
- No GIF-specific failures are accepted by default; if a GIF-focused direct test
  or named gate fails, treat it as a blocker unless repo evidence proves the
  failure is unrelated and pre-existing
- `announcement_happy_path_test.dart`,
  `share_to_contact_smoke_test.dart`,
  `share_batch_delivery_coordinator_test.dart`,
  `share_target_picker_screen_test.dart`,
  `share_target_picker_wired_test.dart`,
  `conversation_wired_test.dart`,
  `local_media_integration_test.dart`,
  `local_media_sender_test.dart`, and
  `local_media_server_test.dart` are required direct suites for this plan even
  though they are not frozen named gates
- the required manual/device animation check is a hard closure condition, not
  an optional demo step

---

## Dependency Impact

- Future sticker / richer animated-image work should reuse the same
  `MediaAttachment`, preview-text, notification, and widget seams rather than
  creating a parallel attachment type
- Feed preview correctness depends on the `mediaPreviewText` change staying
  aligned with the conversation / group / announcement media vocabulary
- Announcement GIF acceptance depends on the shared group media pipeline plus
  the existing admin-only announcement contract
- `S12` share-intent closure depends on the current raw-file-path share contract
  staying intact in `handle_share_intent_use_case.dart`, the share-target
  picker flow, `share_batch_delivery_coordinator.dart`, and
  `share_target_picker_wired.dart`
- `S13` local-transfer closure depends on the current 1:1 `sendLocalMedia()`
  branch plus the local media sender/server MIME handling staying aligned with
  `image/gif`

---

## Done Criteria

This plan is complete only when all of the following are true:

- the production changes listed in the plan are landed without introducing a
  parallel GIF subsystem
- all direct suites listed above are green
- required named gates (`1to1`, `groups`, `feed`, `baseline`) are green, or any
  unrelated pre-existing failure is explicitly identified per
  `test-gate-definitions.md`
- announcement-admin GIF send / reader-receive behavior is directly proved in
  `announcement_happy_path_test.dart`
- raw `.gif` share-intent pass-through is directly proved in both the share
  application test, the share-batch coordinator test, and the share-to-contact
  smoke test
- mixed-share skipped oversized GIFs are surfaced truthfully in the picker UI
  summary/snackbar without regressing valid sibling sends
- direct feed-surface GIF labeling is proved in
  `collapsed_mode_card_body_test.dart`
- direct share-preview GIF rendering is proved in
  `share_target_picker_screen_test.dart`
- 1:1 same-LAN direct local transfer is proved for `image/gif` in the local
  media sender/server/integration suites and one top-level
  `conversation_wired_test.dart` branch-selection case
- direct control coverage proves the GIF cap does not change existing non-GIF
  media size behavior
- one recorded device/simulator check confirms that a picked GIF and a received
  GIF both visibly animate in the attachment/viewer surfaces
- the implementation stays within the scope guard and accepted-differences
  sections above
