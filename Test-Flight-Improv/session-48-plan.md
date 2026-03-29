# Session 48 Plan - Composer Batch Video-Processing UX For 1:1 And Groups

## Final Verdict

`ACCEPTED`

## Final Plan

### Real Scope

What changes in this session:

- add batch-aware processing metadata to the shared composer view state used by
  both 1:1 and group conversation screens
- move gallery multi-video processing ownership from per-file
  `_preparePendingMedia()` toggles to batch-owned lifecycle handling inside
  `_pickFromGallery()` in both wired screens
- update the shared attachment preview strip so the processing tile shows honest
  single-video vs batch context, for example `Processing` or
  `Processing (3/6)`, while keeping the existing determinate progress display
- preserve constructor and legacy-screen paths so non-listenable callers do not
  regress when the new batch fields are added

What does not change in this session:

- no thumbnail extraction, thumbnail persistence, or video rendering changes
- no full-screen video player routing
- no database, repository, migration, or wire-payload changes
- no parallelized media processing; gallery selection can remain sequential
- no new shared abstraction that merges the 1:1 and group wired screens

### Closure Bar

Session 48 is sufficient when all of the following are true:

- selecting multiple videos from gallery in 1:1 and group composers keeps one
  stable processing tile visible for the whole batch instead of flipping
  `isProcessing` on and off per file
- the processing tile exposes honest batch context using the shared composer UI:
  single-video paths show single-video text, and multi-video gallery paths show
  current/total context without ever rendering `0/0`
- the existing camera single-video paths still use the current per-file
  processing behavior and do not require batch counters
- composer state updates for batch counters are not dropped by the
  `_composerStateEquals(...)` short-circuit checks in either wired screen
- direct widget/screen/wired regressions and the named `baseline`, `1to1`, and
  `groups` gates pass without widening into Session 49 or 50 work

### Source Of Truth

Authoritative sources for this session:

- session scope and dependency contract:
  - `Test-Flight-Improv/25-video-upload-bugs-spec-session-breakdown.md`
- bug statement and intended UX:
  - `Test-Flight-Improv/25-video-upload-bugs-spec.md`
- regression gate source of truth:
  - `scripts/run_test_gates.sh`
  - `Test-Flight-Improv/test-gate-definitions.md`
- current code reality for the targeted seam:
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
  - `lib/features/conversation/presentation/widgets/compose_area.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/media/image_processor.dart`
  - `lib/core/media/pending_composer_media.dart`
  - `lib/core/media/media_picker.dart`
- current tests and test seams:
  - `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `test/features/groups/presentation/group_conversation_screen_test.dart`
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/shared/fakes/fake_media_picker.dart`

Conflict rules:

- the Session 48 breakdown wins over the broader bug spec on scope boundaries
- landed code wins over stale prose if the proposal overclaims behavior
- `scripts/run_test_gates.sh` wins over `test-gate-definitions.md` if they ever
  disagree
- if implementation evidence shows this work requires thumbnail persistence,
  player routing, or storage changes, stop and defer to Sessions `49` and `50`
  instead of broadening Session `48`

### Session Classification

`implementation-ready`

### Exact Problem Statement

Current repo behavior matches the reported flicker bug:

- both `_pickFromGallery()` implementations process selected media sequentially
  and call `_preparePendingMedia(...)` once per picked file
- both `_preparePendingMedia(...)` implementations toggle the single
  `isProcessing` flag on entry and clear it in `finally` for every processable
  video
- `ConversationComposerViewState` currently carries only one `isProcessing`
  boolean and one `processingProgress` value, so the UI cannot represent
  "video 3 of 6"
- `AttachmentPreviewStrip` currently appends exactly one processing tile and
  only renders a percent, so the user sees a tile that disappears and reappears
  between videos instead of a stable batch indicator
- both wired screens short-circuit composer updates with `_composerStateEquals`;
  if batch counter fields are added but not compared there, UI updates for
  current/total can be silently dropped

User-visible improvement required in this session:

- gallery-selected multi-video batches in both 1:1 and groups must show one
  continuous processing tile with honest batch context

Behavior that must stay unchanged:

- single-file camera image/video flows keep their existing processing lifecycle
- attachment addition, upload, retry, cancel, and quote-restoration behavior
  stay unchanged

### Files And Repos To Inspect Next

Primary production edit candidates:

- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`

Reference seams that should guide implementation but should not need product
changes unless evidence proves otherwise:

- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/core/media/image_processor.dart`
- `lib/core/media/pending_composer_media.dart`
- `lib/core/media/media_picker.dart`

Direct tests to update/add in this session:

- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/shared/fakes/fake_media_picker.dart` as the existing batch-pick seam

### Existing Tests Covering This Area

- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
  already proves the strip renders a single determinate processing tile and can
  show it beside attachments, but it does not cover batch current/total text or
  single-video vs batch labeling rules
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  already proves composer listenable updates do not rebuild the header or
  message list and currently asserts processing-percent rendering, but it does
  not cover new batch counters
- `test/features/groups/presentation/group_conversation_screen_test.dart`
  provides the same no-rebuild composer-state seam for groups, but also only
  checks percent rendering today
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  and `test/features/groups/presentation/group_conversation_wired_test.dart`
  already cover attachment preview persistence through upload failure/cancel
  flows, which protects adjacent composer behavior, but neither file currently
  pins gallery multi-video processing lifecycle or camera-path preservation

### Regression/Tests To Add First

- add widget-level regression coverage in
  `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
  for:
  - batch label rendering when `processingTotal > 1`
  - single-video label rendering when batch counters are unset or `1`
  - unchanged single processing tile count while attachments are present
- extend
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  and
  `test/features/groups/presentation/group_conversation_screen_test.dart`
  so composer listenable updates assert batch text and still prove header/list
  elements are not rebuilt
- add 1:1 wired regression coverage in
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  using `FakeMediaPicker` plus an injected `ImageProcessor` with controllable
  video progress so a multi-video gallery batch can prove:
  - the processing tile stays mounted for the entire batch
  - the batch counter advances across videos instead of resetting via flicker
  - mixed selection counts videos honestly
- add matching group wired regression coverage in
  `test/features/groups/presentation/group_conversation_wired_test.dart`
- add one direct single-video camera-path regression across 1:1 and groups so
  the batch refactor does not accidentally remove existing processing behavior
  from `_pickVideoFromCamera()` or `_pickFromCamera()` callers that still rely
  on `_preparePendingMedia(...)`

### Step-By-Step Implementation Plan

1. Add the failing direct regressions listed above before changing production
   code. Use the existing `FakeMediaPicker` seam and injectable
   `ImageProcessor(compressVideo: ...)` callbacks rather than introducing new
   test-only architecture.
2. Extend `ConversationComposerViewState` in
   `lib/features/conversation/presentation/screens/conversation_screen.dart`
   with batch metadata such as `processingCurrent` and `processingTotal`, both
   defaulting to zero. Update `copyWith(...)` accordingly.
3. Update `ConversationScreen` and `GroupConversationScreen` constructor
   surfaces and `_legacyComposerState` builders so legacy non-listenable callers
   can still represent the richer processing state without breaking existing
   defaults.
4. Update `AttachmentPreviewStrip` and `_ProcessingThumbnail` to accept and
   render the new batch metadata while preserving the existing "one extra tile
   appended when processing" layout contract. Keep the label logic local to the
   widget so callers do not duplicate string rules.
5. Update `_composerStateEquals(...)` in both wired screens so changes to batch
   counters produce UI updates.
6. Refactor `_preparePendingMedia(...)` in both wired screens so it can run in
   two modes:
   - batch-owned gallery mode: only report progress, do not own
     `isProcessing` start/stop
   - existing single-item mode: retain the current start/stop processing
     behavior for camera callers
7. Move batch lifecycle handling into both `_pickFromGallery()` methods:
   - pre-count processable videos from the selected files
   - if the count is zero, keep current non-processing behavior
   - if the count is non-zero, set batch state once before the loop
   - advance `processingCurrent` only for video files
   - clear batch state once in a `finally` block so errors and unmounts do not
     leave stale UI behind
8. Re-run the direct test files first. If those pass, run the named
   `baseline`, `1to1`, and `groups` gates.
9. Stop immediately if implementation evidence shows the batch UI cannot be
   completed without touching thumbnail extraction, persistence, or playback
   routing; that is Session `49` or `50` work, not Session `48`.

### Risks And Edge Cases

- mixed image/video gallery selections must count only processable videos in the
  batch label while still allowing the non-video items through the existing
  sequential flow
- if `imageProcessor` is null, current code does not treat the file as a
  processable video; Session 48 should preserve that contract
- state reset must happen on exceptions and on `mounted == false` paths so the
  composer does not get stuck in processing mode after navigation or picker
  failures
- counter defaults must never render misleading `Processing (0/0)` text
- batch state must not accidentally disable the attachment strip after each file
  or break existing upload/retry/cancel flows that rely on pending attachments
  staying intact
- both wired screens currently duplicate the seam; drifting implementations
  would create 1:1/group parity bugs, so tests must land in both files

### Exact Tests And Gates To Run

Direct tests:

- `flutter test test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`

Named gates:

- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh groups`

Not required unless this session unexpectedly edits gate definitions:

- `./scripts/run_test_gates.sh completeness-check`

### Known-Failure Interpretation

- `Test-Flight-Improv/test-gate-definitions.md` does not document an active
  known failure for the targeted direct test files or for the named
  `baseline`, `1to1`, and `groups` gates
- treat any new failure in the added Session 48 direct regressions as a real
  regression until disproved
- if a named-gate failure appears outside the composer/video-processing seam,
  compare it with the pre-session baseline before attributing it to Session `48`
- do not change gate membership or weaken assertions to make this session pass

### Done Criteria

- both wired gallery pickers hold one continuous processing tile for multi-video
  batches
- the shared preview strip shows correct single-video vs batch labeling and
  still shows determinate percent progress
- camera single-video processing behavior remains intact
- no stale composer updates are dropped because of missing equality checks
- all direct tests listed above and the named `baseline`, `1to1`, and `groups`
  gates are green
- no production files outside the Session 48 scope guard are modified

### Scope Guard

Non-goals for this session:

- no thumbnail extraction or `thumbnailPath` work
- no `MediaAttachment`, DB, migration, repository, or `MediaFileManager`
  changes
- no shared media-grid or feed rendering changes
- no `FullScreenImageViewer` replacement or new video player
- no protocol additions such as inline thumbnails or blurhash
- no background upload architecture changes

What would count as overengineering:

- introducing a new shared presenter/controller layer just to avoid the small
  duplicated 1:1 and group changes
- coupling Session 48 to Session 49 storage/render work
- parallelizing processing or changing upload semantics when the bug is only the
  composer-state lifecycle

### Accepted Differences / Intentionally Out Of Scope

- 1:1 and group implementations may remain duplicated as long as behavior stays
  aligned and both have direct regression coverage
- single-video camera flows may continue to show only `Processing` without
  batch counters
- attachment thumbnails themselves remain image-file based in this session even
  though video thumbnails are still a later problem
- later sessions may reuse the batch-state contract, but Session 48 does not
  need to create a reusable cross-session abstraction up front

### Dependency Impact

- Session `49` should assume the composer batch-state contract from Session `48`
  is settled and should not reopen it unless thumbnail-persistence work proves a
  concrete regression
- Session `50` depends on Session `49`, not Session `48`, but its player-routing
  UI should inherit whatever final batch-processing tile contract lands here
- Session `51` closure refresh must record the final Session `48` direct tests
  and gate evidence, but it should not reinterpret Session `48` scope

## Structural Blockers Remaining

- none

## Incremental Details Intentionally Deferred

- exact phrasing between `Processing` and `Processing videos` can be settled
  during implementation as long as batch context remains honest and tests pin
  the chosen copy
- no attempt to deduplicate the 1:1 and group gallery helpers in this session

## Accepted Differences Intentionally Left Unchanged

- no parity work for feed/shared-media/player surfaces
- no change to the current sequential processing order
- no attempt to make image-only selections show batch processing state

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/25-video-upload-bugs-spec-session-breakdown.md`
- `Test-Flight-Improv/25-video-upload-bugs-spec.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/core/media/image_processor.dart`
- `lib/core/media/pending_composer_media.dart`
- `lib/core/media/media_picker.dart`
- `test/shared/fakes/fake_media_picker.dart`
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

## Why The Plan Is Safe To Implement Now

The plan is safe because the current code and tests expose a narrow, isolated
seam: the batch flicker comes from per-file `isProcessing` ownership in the two
gallery pickers, while the shared screen/widget layer already has deterministic
test seams for composer-state rendering. The plan keeps Session 48 limited to
that lifecycle/UI contract, adds direct regressions before refactoring, and
stops short of the thumbnail and playback work already split into Sessions `49`
and `50`.
