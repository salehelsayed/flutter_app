# UI-22: GIF Support — TDD Plan

## Approach: Gallery / Keyboard-Native GIFs (No Third-Party API)

Users pick GIFs from their device gallery or insert them via the keyboard's
built-in GIF search (Gboard, iOS keyboard, SwiftKey). The app treats GIFs as
animated images flowing through the existing media pipeline — no external
GIF API, no attribution badges, no ongoing cost.

---

## Exact Problem Statement

The current media pipeline already handles image/video/audio transport well, but
GIFs still fall through as generic images in several user-visible places:

- preview text still says "Photo" instead of "GIF",
- notification body still says "Photo" instead of "GIF",
- thumbnail widgets still force `cacheWidth`, which is risky for animated GIF
  rendering,
- there is no explicit UI-side GIF file-size guard,
- and the current tests do not pin GIF behavior across 1:1, groups,
  announcements, and share-intent entry points.

This plan should improve GIF support by extending the existing media pipeline,
not by introducing a parallel GIF subsystem.

---

## Real Scope

What changes in this session:

- add explicit GIF-awareness to the existing media model, preview text,
  notification text, and shared image widgets
- prove that GIFs stay on the animated-image path instead of the static
  optimization path
- add a UI-side file-size guard at the shared wired-screen media seam
- add direct regression coverage for 1:1, group, announcement-admin, and
  share-intent GIF behavior

What does not change in this session:

- no third-party GIF API or search provider
- no new transport, persistence, or retry architecture
- no separate announcement media pipeline
- no feed UI redesign beyond the downstream preview-text vocabulary change
- no lifecycle / transport / recovery work outside the narrow picker guard and
  existing media surfaces

---

## Closure Bar

Definition of "sufficient":

A GIF is **sufficient** when all of the following hold:

| # | Criterion | How to verify |
|---|-----------|---------------|
| S1 | User can pick a `.gif` from gallery and it appears in the attachment strip with the correct GIF affordance; actual animation remains manual-confirmed | Widget test + manual |
| S2 | GIF uploads, sends, and arrives on the receiver with `mime: image/gif` | Unit test on wire envelope |
| S3 | GIF renders through the animated image path in the conversation letter card (not the static optimization path) | Widget proxy + manual |
| S4 | GIF renders through the animated image path in the full-screen viewer | Widget proxy + manual |
| S5 | A "GIF" badge is visible on the thumbnail (grid cell + preview strip) | Widget test: `find.text('GIF')` |
| S6 | GIF is **not re-encoded** by `ImageProcessor` (preserves animation) | Unit test: compressFn never called for `.gif` |
| S7 | Oversized GIFs (>25 MB) are rejected with a user-facing message | Widget test on wired screen |
| S8 | Works the same across **1:1 chat**, **group discussion**, and **announcement admin send** within the current shared media pipeline | Dedicated test groups per message type |
| S9 | Push notification says "GIF" (not "Photo") for GIF-only messages | Unit test on `notificationBodyForMessage` |
| S10 | Preview text says "GIF" (not "Photo") in feed / quoted messages | Unit test on `mediaPreviewText` |
| S11 | Retry-after-failure re-uploads the GIF correctly | Unit test on retry use cases |
| S12 | Share-intent flow preserves the raw `.gif` path and the picker/contact flow passes it through unchanged | Direct share tests |

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
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
- `lib/shared/widgets/media/full_screen_image_viewer.dart`
- `lib/shared/widgets/media/media_preview_text.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/share/application/handle_share_intent_use_case.dart`
- `lib/features/share/application/settle_share_intent_flow.dart`

Primary tests to extend:

- `test/features/conversation/domain/models/media_attachment_test.dart`
- `test/core/media/image_processor_test.dart`
- `test/shared/widgets/media/media_preview_text_test.dart`
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `test/features/conversation/application/upload_media_use_case_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/share/application/handle_share_intent_use_case_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`

---

## Existing Tests Covering This Area

Already useful:

- `media_attachment_test.dart` covers `MediaAttachment` serialization / mapping
- `image_processor_test.dart` covers processable-image behavior
- `media_preview_text_test.dart` covers current photo/video preview labels
- `show_notification_use_case_test.dart` covers current notification-body helper behavior
- `attachment_preview_strip_test.dart` covers preview-strip rendering and remove/upload affordances
- `upload_media_use_case_test.dart` covers mime-agnostic upload behavior
- `send_chat_message_use_case_test.dart` and `send_group_message_use_case_test.dart` cover media propagation in 1:1 and group paths
- `retry_failed_messages_use_case_test.dart` and `retry_failed_group_messages_use_case_test.dart` cover retry behavior
- `media_attachment_flow_test.dart` covers 1:1 media integration flow
- `announcement_happy_path_test.dart` covers current announcement create/send/read-only/react acceptance
- `handle_share_intent_use_case_test.dart` and `share_to_contact_smoke_test.dart` already prove raw share-intent file-path pass-through for image/video shares

Still missing:

- explicit GIF animation-path widget proof
- explicit GIF preview/notification labeling proof
- explicit GIF file-size guard proof
- explicit GIF announcement acceptance proof
- explicit raw `.gif` share-intent pass-through proof

---

## Scope Guard

**Not in scope (and why):**
- GIF search/picker API (Tenor/Giphy) — deliberate decision to avoid third-party dependency
- GIF compression/frame reduction — GIFs are small-palette; re-encoding destroys quality
- Keyboard paste handler — iOS/Android keyboards already route GIFs through image picker
- GIF recording/creation — separate feature
- a new GIF-specific transport or persistence pipeline
- feed-surface redesign beyond the downstream `mediaPreviewText` change
- transport / lifecycle / retry architecture changes unrelated to GIF metadata and rendering

## Accepted Differences / Intentionally Out Of Scope

- actual visual animation is partially a manual/device confirmation; the
  automated widget proof here is the proxy "use the animated image path and do
  not force `cacheWidth` on GIFs"
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
| `MediaAttachment` model | Reuse + extend | Add `isAnimated` getter |
| `MediaGridCell` | Reuse + extend | Remove `cacheWidth` for GIF, add badge |
| `AttachmentPreviewStrip` | Reuse + extend | Remove `cacheWidth` for GIF, add badge |
| `FullScreenImageViewer` | Reuse + verify | Confirm GIF animates (no `cacheWidth` present) |
| `mediaPreviewText` | Modify | "GIF" label instead of "Photo" |
| `notificationBodyForMessage` | Modify | "GIF" label instead of "Photo" |
| Conversation wired (1:1) | Reuse + extend | File size guard |
| Group conversation wired | Reuse + extend | File size guard |

**New files: 1 production file** (`lib/core/constants/media_constants.dart` for `kMaxMediaFileSize`). All other changes are modifications to existing files.
**New test files: 2** (`media_grid_cell_test.dart`, `conversation_wired_gif_test.dart`).

---

## Component Coverage Matrix

| Component | 1:1 Chat | Group Discussion | Announcement (admin) | Notes |
|-----------|----------|------------------|----------------------|-------|
| Gallery pick | Y | Y | Y | Same `MediaPicker` in both wired screens |
| Keyboard insert | Y | Y | Y | OS keyboard routes through image picker |
| Image processing bypass | Y | Y | Y | Shared `ImageProcessor` |
| Upload | Y | Y | Y | Same `uploadMedia` use case |
| Wire envelope | v1/v2 | v3 | v3 | GIF in `media[]` array |
| Send | Y | Y | Y (admin only) | `_canWriteForGroup` gates non-admins |
| Receive + parse | Y | Y | Y | Listeners are mime-agnostic |
| Download | Y | Y | Y | Shared `downloadMedia` use case |
| Animated display | Y | Y | Y | Shared `MediaGridCell` |
| Full-screen viewer | Y | Y | Y | Shared `FullScreenImageViewer` |
| GIF badge | Y | Y | Y | Shared widget |
| Push notification | Y | Y | Y | Shared `notificationBodyForMessage` |
| Preview text | Y | Y | Y | Shared `mediaPreviewText` |
| Retry on failure | Y | Y | Y | Shared retry use cases |
| File size guard | Y | Y | Y | Both wired screens |
| Share extension | Y | — | — | 1:1 only; passes GIF through unchanged |

---

## Regression / Tests To Add First

Before broad implementation work, add the smallest direct proofs that pin the
intended GIF contract:

1. `media_attachment_test.dart`
   - add `isAnimated` coverage so later consumers share one GIF predicate
2. `image_processor_test.dart`
   - lock the explicit GIF bypass so animation-preserving behavior cannot drift
3. `media_preview_text_test.dart` and
   `notification_body_for_message_test.dart`
   - pin user-visible "GIF" vocabulary before touching widgets
4. `media_grid_cell_test.dart` and `attachment_preview_strip_test.dart`
   - pin the animated-image widget path and GIF badge before changing shared UI
5. `conversation_wired_gif_test.dart`
   - pin the file-size guard at the shared picker seam before implementation
6. `announcement_happy_path_test.dart` and share-intent tests
   - pin `S8` and `S12` directly so announcement/share proof is not left
     implicit

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

**Why:** Users see "Photo" for GIFs in feed previews and push notifications. Confusing — should say "GIF".

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

  test('collapsed mode card preview shows GIF for animated media')
    → verify mediaPreviewText returns 'GIF' when called with a GIF attachment
      (covers collapsed_mode_card_body.dart:346 downstream path)
```

**Test file:** `test/features/push/application/notification_body_for_message_test.dart` (add to existing — NOT `show_notification_use_case_test.dart`)

```
group('GIF notification body')
  test('returns "GIF" for single GIF-only message')
    → notificationBodyForMessage('', [gifAttachment]) == 'GIF'

  test('returns text when message has text + GIF')
    → notificationBodyForMessage('check this out', [gifAttachment]) == 'check this out'
```

**Production files:**
- `lib/shared/widgets/media/media_preview_text.dart` — use `isAnimated` to separate GIF count from image count
- `lib/features/push/application/show_notification_use_case.dart` — add GIF detection in `'image'` branch

**Lines changed:** ~15

---

### Phase 4: `MediaGridCell` — Animated display + GIF badge

**Why:** `cacheWidth: 400` may decode GIF as static frame. GIF badge gives visual feedback.

**Test file:** `test/shared/widgets/media/media_grid_cell_test.dart` (new)

```
group('GIF rendering')
  test('renders Image.file WITHOUT cacheWidth for GIF attachment')
    → create GIF MediaAttachment (done, localPath exists)
    → pump MediaGridCell
    → find Image widget → verify cacheWidth is null

  test('renders Image.file WITH cacheWidth 400 for JPEG attachment')
    → create JPEG attachment
    → pump → verify cacheWidth == 400

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

**Production file:** `lib/shared/widgets/media/media_grid_cell.dart`

Changes:
- `_buildContent()`: if `attachment.isAnimated` → `Image.file()` without `cacheWidth`
- `build()` Stack: add `if (attachment.isAnimated && isDone)` → "GIF" badge (bottom-left, semi-transparent background)

**Lines changed:** ~25

---

### Phase 5: `AttachmentPreviewStrip` — GIF thumbnail + badge

**Why:** Preview strip uses `cacheWidth: 200` which may freeze GIF. Also needs badge.

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
- `_Thumbnail`: detect `.gif` extension → render `Image.file` without `cacheWidth`
- Add "GIF" badge (small, bottom-left) — hidden during upload overlay

**Lines changed:** ~20

---

### Phase 6: `FullScreenImageViewer` — Verify GIF animation

**Why:** Viewer uses `Image.file()` without `cacheWidth` — should animate natively. Need test to lock this.

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

### Phase 7: File size guard

**Why:** GIFs can be 50MB+. Reject oversized files before upload.

**Guard placement:** The guard goes in `_processMediaIfNeeded` (not `_pickFromGallery`). Both wired screens have three pick entry points — `_pickFromGallery`, `_pickFromCamera`, `_pickVideoFromCamera` — and all three funnel through `_processMediaIfNeeded`. Placing the guard there covers all media entry paths with a single check per screen.

- `conversation_wired.dart`: `_processMediaIfNeeded` at line 1050, called from lines 993, 1015, 1035
- `group_conversation_wired.dart`: `_processMediaIfNeeded` at line 995, called from lines 944, 964, 982

**Constant file:** `lib/core/constants/media_constants.dart` (new, following pattern of `retry_constants.dart` and `network_constants.dart`):
```dart
const int kMaxMediaFileSize = 25 * 1024 * 1024; // 25 MB
```

**Note:** The codebase has existing 100 MB limits (`local_media_server.dart:43` and `send_voice_message_use_case.dart:20`) which are server/transport-layer limits. The 25 MB `kMaxMediaFileSize` is a UI picker guard — a different layer with a tighter bound. Both are intentional.

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

  test('camera capture over 25MB rejected')
    → configure picker to return 30MB camera capture
    → trigger attach via camera
    → verify rejected

  test('mixed pick: oversized file rejected, valid JPEG kept')
    → pick [30MB.gif, 2MB.jpg]
    → verify only JPEG in pending media

group('file size guard — group')
  test('same guard applies in group conversation wired')
    → same pattern in group context
```

**Production files:**
- `lib/core/constants/media_constants.dart` — NEW: `kMaxMediaFileSize` constant
- `lib/features/conversation/presentation/screens/conversation_wired.dart` — guard at top of `_processMediaIfNeeded`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — guard at top of `_processMediaIfNeeded`

Changes in each `_processMediaIfNeeded`:
```dart
if (File(path).lengthSync() > kMaxMediaFileSize) {
  // reject — throw or return null depending on return type
}
```

**Lines changed:** ~10 per wired screen + 1 new constant file

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

**Test file:** `test/features/conversation/application/retry_failed_messages_use_case_test.dart`

```
group('GIF retry')
  test('failed GIF message retries with correct mime')
    → create failed message with GIF attachment
    → retry → verify re-upload called with mime: 'image/gif'
```

**Test file:** `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`

```
group('GIF group retry')
  test('failed group GIF retries correctly')
    → same pattern for group retry
```

**Production file:** None — verification tests only.

---

### Phase 12: Integration — end-to-end

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
`.gif` path survives the share-intent path and lands unchanged in the picker /
compose flow.

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

**Production file:** None — share-path verification tests only.

---

## Implementation Order Summary

| Step | Phase | Tests | Prod change | Effort |
|------|-------|-------|-------------|--------|
| 1 | Phase 1: `isAnimated` getter | 5 | 1 line | S |
| 2 | Phase 2: ImageProcessor GIF bypass | 3 | 0 lines | S |
| 3 | Phase 3: Preview text + notification label | 7 | ~15 lines | S |
| 4 | Phase 4: MediaGridCell animated + badge | 7 | ~25 lines | M |
| 5 | Phase 5: AttachmentPreviewStrip badge | 5 | ~20 lines | M |
| 6 | Phase 6: FullScreenImageViewer verify | 3 | 0 lines | S |
| 7 | Phase 7: File size guard (in `_processMediaIfNeeded`) | 5 | ~20 lines + 1 new file | M |
| 8 | Phase 8: Upload verification | 3 | 0 lines | S |
| 9 | Phase 9: Send wire envelope | 4 | 0 lines | S |
| 10 | Phase 10: Receive parsing | 2 | 0 lines | S |
| 11 | Phase 11: Retry verification | 2 | 0 lines | S |
| 12 | Phase 12: Integration e2e | 3 | 0 lines | M |
| 13 | Phase 13: Announcement acceptance | 2 | 0 lines | S |
| 14 | Phase 14: Share-intent pass-through | 2 | 0 lines | S |
| **Total** | | **53 tests** | **~81 lines + 1 new file** | |

---

## Production Files Modified

| File | What changes |
|------|-------------|
| `lib/features/conversation/domain/models/media_attachment.dart` | `isAnimated` getter |
| `lib/shared/widgets/media/media_grid_cell.dart` | Skip `cacheWidth` for GIF + "GIF" badge |
| `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart` | Skip `cacheWidth` for GIF + "GIF" badge |
| `lib/shared/widgets/media/media_preview_text.dart` | "GIF" / "N GIFs" label (also affects `collapsed_mode_card_body.dart` downstream) |
| `lib/features/push/application/show_notification_use_case.dart` | "GIF" in notification body |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | File size guard in `_processMediaIfNeeded` (covers gallery + camera + video) |
| `lib/features/groups/presentation/screens/group_conversation_wired.dart` | File size guard in `_processMediaIfNeeded` (covers gallery + camera + video) |
| `lib/core/constants/media_constants.dart` | **NEW:** `kMaxMediaFileSize = 25 * 1024 * 1024` |

## New Test Files

| File | Purpose |
|------|---------|
| `test/shared/widgets/media/media_grid_cell_test.dart` | GIF rendering + badge |
| `test/features/conversation/presentation/screens/conversation_wired_gif_test.dart` | File size guard |

## Existing Test Files Extended

| File | Tests added |
|------|------------|
| `test/features/conversation/domain/models/media_attachment_test.dart` | `isAnimated`, GIF fromJson |
| `test/core/media/image_processor_test.dart` | GIF bypass |
| `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart` | GIF thumbnail + badge |
| `test/shared/widgets/media/media_preview_text_test.dart` | GIF label |
| `test/features/push/application/notification_body_for_message_test.dart` | GIF notification |
| `test/features/conversation/application/upload_media_use_case_test.dart` | GIF upload |
| `test/features/conversation/application/send_chat_message_use_case_test.dart` | GIF in envelope |
| `test/features/groups/application/send_group_message_use_case_test.dart` | GIF in group envelope |
| `test/features/conversation/application/retry_failed_messages_use_case_test.dart` | GIF retry |
| `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` | GIF group retry |
| `test/features/conversation/integration/media_attachment_flow_test.dart` | GIF e2e |
| `test/shared/widgets/media/full_screen_image_viewer_test.dart` | GIF animation |
| `test/features/groups/integration/announcement_happy_path_test.dart` | GIF announcement admin-send / reader-receive acceptance |
| `test/features/share/application/handle_share_intent_use_case_test.dart` | Raw `.gif` share-intent path pass-through |
| `test/features/share/integration/share_to_contact_smoke_test.dart` | GIF share-to-contact pending attachment smoke |

---

## Risk Register

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Flutter `Image.file()` + `cacheWidth` freezes GIF as static | Medium | Phase 4 removes `cacheWidth` for GIF, test verifies |
| Large GIFs cause OOM on low-end devices | Medium | Phase 7 file size guard (25 MB cap) |
| `image_picker` doesn't return GIFs on some Android versions | Low | Depends on OS — out of our control; works on stock Android 10+ |
| GIF animation causes jank in conversation scroll | Low | `MediaGridCell` renders at grid size; only full-screen is full-res |
| Re-encoding GIF via `flutter_image_compress` destroys animation | None | Phase 2 locks bypass behavior — `.gif` excluded from processable set |

---

## Exact Tests And Gates To Run

Direct suites from this plan:

- `test/features/conversation/domain/models/media_attachment_test.dart`
- `test/core/media/image_processor_test.dart`
- `test/shared/widgets/media/media_preview_text_test.dart`
- `test/features/push/application/notification_body_for_message_test.dart`
- `test/shared/widgets/media/media_grid_cell_test.dart`
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `test/shared/widgets/media/full_screen_image_viewer_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_gif_test.dart`
- `test/features/conversation/application/upload_media_use_case_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`
- `test/features/share/application/handle_share_intent_use_case_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`

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
- `share_to_contact_smoke_test.dart` is also a required direct suite even though
  it is not part of a named gate, because `S12` depends on it

---

## Known-Failure Interpretation

- Use `Test-Flight-Improv/test-gate-definitions.md` as the source of truth for
  named-gate membership and known-failure handling
- Pre-existing red tests outside the touched GIF surfaces are not GIF
  regressions unless this change clearly caused or widened them
- No GIF-specific failures are accepted by default; if a GIF-focused direct test
  or named gate fails, treat it as a blocker unless repo evidence proves the
  failure is unrelated and pre-existing
- `announcement_happy_path_test.dart` and `share_to_contact_smoke_test.dart`
  are required direct suites for this plan even though they are not frozen named
  gates

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
  staying intact in `handle_share_intent_use_case.dart` and the share-target
  picker flow

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
  application test and the share-to-contact smoke test
- the implementation stays within the scope guard and accepted-differences
  sections above
