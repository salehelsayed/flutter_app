# 25 - Video Upload Bugs Session Breakdown

## Decomposition artifact updated

- Artifact path: `Test-Flight-Improv/25-video-upload-bugs-spec-session-breakdown.md`
- Proposal/source doc path: `Test-Flight-Improv/25-video-upload-bugs-spec.md`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `4`

## Overall closure bar

Report `25` is closed only when the current Flutter tree makes video attachments
usable across the chat/group/feed surfaces it already ships, without widening
into a new media-wire protocol or background-transfer architecture.

Closure is reached only when all of the following are true:

- multi-video gallery selection in both 1:1 and group composers keeps one
  stable processing tile with honest batch context instead of toggling the
  single `isProcessing` flag on and off per file
- sent and received videos stop trying to render the raw video file through
  `Image.file(...)`; shared media surfaces show a real thumbnail when one is
  available and fall back honestly while extraction/download is still pending
- tapping a downloaded video from the current conversation, group, and feed
  preview surfaces opens a real full-screen video player through the shared
  video-capable `FullScreenImageViewer` path instead of an image-only route
- the rollout stays honest about receiver preview timing:
  it may rely on the existing auto-download plus local thumbnail extraction
  path rather than reopening the chat/group wire payload with inline base64
  thumbnails and blurhash
- the stable media/UI docs and the Test-Flight closure/index docs match the
  landed local-thumbnail plus shared-player contract

## Final program acceptance review

- Review date: `2026-03-30`
- Closure verdict: `still_open`
- Completion-auditor result:
  - Session `48` landed the batch video-processing UX; the five direct suites
    plus `./scripts/run_test_gates.sh 1to1` and
    `./scripts/run_test_gates.sh groups` passed
  - Session `49` is accepted as `stale/already-covered` on current repo
    evidence:
    chat/group/feed video surfaces already render through
    `MediaThumbnailImage`, `VideoThumbnailCache`, and the derived
    `.thumb.jpg` sidecar contract
  - Session `50` is accepted as `stale/already-covered` on current repo
    evidence:
    the current 1:1, group, and feed tap routes already open the
    video-capable `FullScreenImageViewer` backed by `video_player`
- What is now considered closed:
  - the Session `49` and Session `50` stale-plan refreshes; do not reopen
    either session without a concrete current reproducer in an in-scope
    surface
- Residual-only items:
  - none; the remaining blocker is not residual because the required
    `baseline` proof is still missing
- Still-open items:
  - Session `48` still lacks a clean `./scripts/run_test_gates.sh baseline`
    pass
  - the missing baseline evidence is environmental/tooling proof, not a new
    product reproducer:
    the direct run could not write Flutter `engine.stamp`, the wrapped macOS
    rerun then failed on CocoaPods ownership during
    `integration_test/loading_states_smoke_test.dart`, and Chrome is
    unsupported for these Flutter integration tests
  - Session `51` stable closure refresh stays intentionally unexecuted while
    that baseline proof is missing; updating `00-INDEX.md`,
    `17-roadmap-closure-audit.md`, or the stable media specs now would
    overclaim closure
- Accepted differences:
  - no inline base64 thumbnail or blurhash payload rollout
  - no new tap-triggered receiver download orchestration path;
    existing auto-download plus local thumbnail extraction remains the
    accepted receiver contract
  - the shared video viewer remains `FullScreenImageViewer`;
    no separate player route is required
- Maintenance-time safety:
  - keep the Session `48` direct suites plus the existing shared
    thumbnail/viewer tests as the direct regression evidence for this report
  - keep `baseline`, `1to1`, and `groups` as the named gates for the landed
    Session `48` change; `feed` should reopen only if a concrete current feed
    reproducer reopens the stale Session `49` or `50` seams
- Safe closure-reference rule:
  - until `baseline` passes cleanly, this breakdown artifact is the only safe
    Report `25` closure reference

## Source of truth

Primary proposal and policy docs:

- `Test-Flight-Improv/25-video-upload-bugs-spec.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `UI-10-Media/media-display-spec.md`
- `UI-10-Media/media-client-spec.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`
- `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`

Current-code and current-test reality checks that govern the split:

- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/full_screen_image_viewer.dart`
- `lib/shared/widgets/media/media_grid.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `lib/core/media/image_processor.dart`
- `lib/core/media/video_process_result.dart`
- `lib/core/media/pending_composer_media.dart`
- `lib/core/media/media_file_manager.dart`
- `lib/core/media/video_thumbnail_cache.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/features/groups/domain/models/group_message_payload.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/core/database/migrations/010_media_attachments.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/main.dart`
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/core/media/image_processor_test.dart`
- `test/core/media/pending_composer_media_test.dart`
- `test/features/conversation/domain/models/media_attachment_test.dart`
- `test/core/database/migrations/010_media_attachments_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
- `test/features/feed/presentation/widgets/message_bubble_test.dart`
- `test/features/share/presentation/share_target_picker_screen_test.dart`

Source-of-truth conflicts that materially affected the split:

- current code beats proposal prose where they disagree:
  incoming 1:1 and group media are already auto-downloaded by
  `chat_message_listener.dart` and `group_message_listener.dart`, so a new
  tap-triggered download orchestration path is not the minimum receiver fix
- current code beats stale media-protocol prose where they disagree:
  `UI-10-Media/media-client-spec.md` still claims inline `thumbnail` and
  `blurhash` payload fields, but current `MediaAttachment`,
  `MessagePayload`, and `GroupMessagePayload` do not implement that contract
- current code shows the black-thumbnail problem is wider than a single
  conversation bubble:
  `media_grid_cell.dart`, `collapsed_mode_card_body.dart`, and
  `scrollable_message_preview.dart` all depend on image-style rendering paths
  for video-bearing surfaces
- current code also shows one adjacent out-of-scope surface:
  `share_target_picker_screen.dart` still previews the first shared file with
  `Image.file(...)`; that is related evidence, but it is not required for the
  minimum safe closure of this report

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Pipeline status | Latest artifact/result | Blocker note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `48` | Composer batch video-processing UX for 1:1 and groups | `implementation-ready` | `Test-Flight-Improv/session-48-plan.md` | none | `still-open` | `execution-blocked` | `2026-03-30`: repo-local batch-processing changes and direct regressions landed; the five direct suites plus `./scripts/run_test_gates.sh 1to1` and `./scripts/run_test_gates.sh groups` passed, but `./scripts/run_test_gates.sh baseline` has no clean pass yet | direct baseline run could not write `/Users/I560101/development/flutter/bin/cache/engine.stamp`; wrapped macOS rerun then failed during `integration_test/loading_states_smoke_test.dart` with pod ownership `not owner`; Chrome rerun is unsupported for Flutter integration tests |
| `49` | Local thumbnail persistence and shared video rendering surfaces | `implementation-ready` | `Test-Flight-Improv/session-49-plan.md` | none | `stale/already-covered` | `plan-refresh-accepted` | `2026-03-30`: plan refresh found current chat/group/feed video surfaces already use `MediaThumbnailImage`, `VideoThumbnailCache`, and a derived `.thumb.jpg` sidecar contract; the original DB/model `thumbnail_path` rollout is stale and should not execute without a new reproducer | none |
| `50` | Shared video playback routing and full-screen player | `implementation-ready` | `Test-Flight-Improv/session-50-plan.md` | `49` | `stale/already-covered` | `plan-refresh-accepted` | `2026-03-30`: plan refresh found current 1:1/group/feed taps already route videos into the shared `FullScreenImageViewer`, which already uses `video_player`; the original player/routing rollout is stale and should not execute without a new reproducer | none |
| `51` | Cross-slice acceptance and closure refresh for Report 25 | `closure-only` | `Test-Flight-Improv/session-51-plan.md` | `48`, `49`, `50` | `skipped_due_to_dependency` | `waiting-on-session-48` | `2026-03-30`: final program acceptance review confirmed Report `25` remains `still_open`; Session `49` and Session `50` stay stale/already-covered, but Session `48` still blocks stable closure until `./scripts/run_test_gates.sh baseline` has a clean pass | final closure refresh is unsafe while Session `48` remains open on missing baseline proof |

## Ordered session breakdown

### Session 48

- Title: Composer batch video-processing UX for 1:1 and groups
- Session id: `48`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/session-48-plan.md`
- Exact scope:
  add batch-aware processing state to `ConversationComposerViewState` and the
  shared composer UI so gallery-selected videos stop toggling a single
  processing card on and off per file
- Exact scope:
  move the batch `isProcessing` lifecycle into `_pickFromGallery()` for both
  `ConversationWired` and `GroupConversationWired`, while preserving the
  existing single-video camera path behavior inside `_preparePendingMedia()`
- Exact scope:
  update `AttachmentPreviewStrip` to show honest batch context such as
  `Processing (3/6)` plus determinate progress, without widening this session
  into DB, thumbnail-persistence, or player work
- Why it is its own session:
  this is the composer-state and send-surface UX seam.
  It has deterministic screen/widget regressions and can land safely before any
  media-storage or playback refactor
- Likely code-entry files:
  `lib/features/conversation/presentation/screens/conversation_screen.dart`
- Likely code-entry files:
  `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- Likely code-entry files:
  `lib/features/conversation/presentation/screens/conversation_wired.dart`
- Likely code-entry files:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely code-entry files:
  `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
- Likely direct tests/regressions:
  `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- Likely direct tests/regressions:
  `test/features/groups/presentation/group_conversation_screen_test.dart`
- Likely direct tests/regressions:
  `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely named gates:
  `baseline`
- Likely named gates:
  `1to1`
- Likely named gates:
  `groups`
- Matrix/closure docs to update when done:
  defer stable closure and media-doc refresh to Session `51`
- Dependency on earlier sessions:
  none

### Session 48 closure outcome

- Closure verdict: `still_open`
- Execution verdict: `blocked`
- What landed:
  - `ConversationComposerViewState` and both conversation screen surfaces now
    carry `processingCurrent` / `processingTotal` so the shared composer UI can
    represent batch progress without rendering misleading `0/0`
  - `_pickFromGallery()` in both wired screens now owns the multi-video batch
    lifecycle, while `_preparePendingMedia()` keeps the single-item processing
    ownership path for camera callers
  - `AttachmentPreviewStrip` now renders honest batch copy such as
    `Processing (2/4)` while preserving the existing determinate progress tile
  - the Session `48` direct regressions landed in the strip, screen, and wired
    test files, including explicit multi-video gallery coverage and
    single-video camera-path coverage for both 1:1 and groups
- Completeness-check decision:
  - `not required`; Session `48` did not add new test files or edit
    `Test-Flight-Improv/test-gate-definitions.md`
- Residual-only items:
  - none; this session is not in a residual-only state because the required
    `baseline` gate still lacks a clean passing run
- Still-open items:
  - rerun `./scripts/run_test_gates.sh baseline` in an environment that can
    write the Flutter SDK cache and owns the CocoaPods workspace so
    `integration_test/loading_states_smoke_test.dart` can complete on macOS
  - keep Session `48` open until the required `baseline` evidence exists, even
    though the five direct suites plus the named `1to1` and `groups` gates
    passed on `2026-03-30`
- Accepted differences:
  - no Session `49` thumbnail-persistence work or Session `50` player-routing
    work was pulled into this slice
  - no stable closure/index/media docs were refreshed yet; Session `51`
    remains the closure owner, and this live breakdown is the only justified
    blocked-state doc update

### Session 49

- Title: Local thumbnail persistence and shared video rendering surfaces
- Session id: `49`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/session-49-plan.md`
- Exact scope:
  add a repo-local thumbnail sidecar contract for videos using the existing
  client media pipeline:
  extend the video-processing result, pending-media shape, attachment model,
  and attachment persistence so a local `thumbnailPath` can survive optimistic
  send, durable upload persistence, reload, and receive-side auto-download
- Exact scope:
  land the minimal DB/storage work needed for that contract:
  a new media-attachment migration, helper/repository plumbing, and the
  `MediaFileManager`/upload/download helpers needed to store thumbnail sidecars
  next to app-owned media files
- Exact scope:
  update shared renderers to prefer `thumbnailPath` for videos instead of
  attempting `Image.file(videoPath)`, including the shared media grid and the
  feed collapsed-preview thumbnail path
- Exact scope:
  keep this session local-file based.
  Do not widen it into inline base64 thumbnails, blurhash, or a cross-payload
  chat/group protocol change
- Why it is its own session:
  this is the thumbnail persistence and shared rendering seam.
  It touches a different direct regression family than Session `48` and has
  real DB/model/storage blast radius that should not be bundled with player UI
- Likely code-entry files:
  `lib/core/media/video_process_result.dart`
- Likely code-entry files:
  `lib/core/media/image_processor.dart`
- Likely code-entry files:
  `lib/core/media/pending_composer_media.dart`
- Likely code-entry files:
  `lib/core/media/media_file_manager.dart`
- Likely code-entry files:
  `lib/features/conversation/domain/models/media_attachment.dart`
- Likely code-entry files:
  `lib/core/database/migrations/043_media_attachment_thumbnail_path.dart`
- Likely code-entry files:
  `lib/core/database/helpers/media_attachments_db_helpers.dart`
- Likely code-entry files:
  `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- Likely code-entry files:
  `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- Likely code-entry files:
  `lib/features/conversation/application/upload_media_use_case.dart`
- Likely code-entry files:
  `lib/features/conversation/application/download_media_use_case.dart`
- Likely code-entry files:
  `lib/features/conversation/presentation/screens/conversation_wired.dart`
- Likely code-entry files:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely code-entry files:
  `lib/shared/widgets/media/media_grid_cell.dart`
- Likely code-entry files:
  `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- Likely code-entry files:
  `lib/main.dart`
- Likely direct tests/regressions:
  `test/core/media/image_processor_test.dart`
- Likely direct tests/regressions:
  `test/core/media/pending_composer_media_test.dart`
- Likely direct tests/regressions:
  `test/core/media/video_process_result_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/domain/models/media_attachment_test.dart`
- Likely direct tests/regressions:
  `test/core/database/helpers/media_attachments_db_helpers_test.dart`
- Likely direct tests/regressions:
  `test/core/database/integration/full_migration_chain_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/application/download_media_use_case_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- Likely direct tests/regressions:
  `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely direct tests/regressions:
  `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
- Likely direct tests/regressions:
  `test/features/posts/phase2/attach_post_media_use_case_test.dart`
- Likely direct tests/regressions:
  `test/shared/widgets/media/media_grid_cell_test.dart`
- Likely named gates:
  `baseline`
- Likely named gates:
  `1to1`
- Likely named gates:
  `groups`
- Likely named gates:
  `feed`
- Matrix/closure docs to update when done:
  defer stable media-doc and index refresh to Session `51`
- Dependency on earlier sessions:
  none

### Session 50

- Title: Shared video playback routing and full-screen player
- Session id: `50`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/session-50-plan.md`
- Exact scope:
  add the app-local video playback surface:
  bring in `video_player`, create
  `lib/shared/widgets/media/full_screen_video_player.dart`, and give the app a
  real full-screen player with play/pause, seek, and close behavior
- Exact scope:
  route video taps away from `FullScreenImageViewer` in the current 1:1,
  group, and feed preview surfaces while preserving existing image-gallery
  behavior for images
- Exact scope:
  keep this session viewer-only.
  Do not reopen message/group payloads, auto-download orchestration, or a
  broader gallery/carousel redesign for mixed image+video swipes
- Why it is its own session:
  this is a new dependency plus player-controller/routing seam.
  It has different regressions and failure modes than the storage/render work
  in Session `49`
- Likely code-entry files:
  `pubspec.yaml`
- Likely code-entry files:
  `lib/shared/widgets/media/full_screen_video_player.dart`
- Likely code-entry files:
  `lib/features/conversation/presentation/screens/conversation_screen.dart`
- Likely code-entry files:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely code-entry files:
  `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- Likely direct tests/regressions:
  `test/shared/widgets/media/full_screen_video_player_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- Likely direct tests/regressions:
  `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely direct tests/regressions:
  `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
- Likely named gates:
  `baseline`
- Likely named gates:
  `1to1`
- Likely named gates:
  `groups`
- Likely named gates:
  `feed`
- Matrix/closure docs to update when done:
  defer final doc refresh to Session `51`
- Dependency on earlier sessions:
  Session `49`

### Session 51

- Title: Cross-slice acceptance and closure refresh for Report 25
- Session id: `51`
- Session classification: `closure-only`
- Intended plan file: `Test-Flight-Improv/session-51-plan.md`
- Exact scope:
  rerun the direct suites and named gates needed to prove the combined
  composer, thumbnail/render, and playback slices, then refresh the stable
  docs so the repo promise matches the landed behavior
- Exact scope:
  update the existing closure owners instead of inventing a new matrix doc:
  the live breakdown artifact, the Test-Flight index/closure audit, and the
  stable media specs should carry the maintenance-time meaning of this rollout
- Exact scope:
  explicitly record the accepted differences preserved by the rollout, most
  importantly:
  no inline base64 thumbnail payload, no blurhash rollout, and no new
  tap-triggered receiver download orchestration path
- Why it is its own session:
  multiple earlier slices touch different surfaces and docs.
  One closure owner is required so the folder does not land code while leaving
  the media specs and index in contradiction with the actual app contract
- Likely code-entry files:
  `Test-Flight-Improv/25-video-upload-bugs-spec-session-breakdown.md`
- Likely code-entry files:
  `Test-Flight-Improv/00-INDEX.md`
- Likely code-entry files:
  `Test-Flight-Improv/17-roadmap-closure-audit.md`
- Likely code-entry files:
  `UI-10-Media/media-client-spec.md`
- Likely code-entry files:
  `UI-10-Media/media-display-spec.md`
- Likely code-entry files:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` only if
  the final landed behavior materially changes the 1:1 maintenance promise
- Likely code-entry files:
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  only if the final landed behavior materially changes the group maintenance
  promise
- Likely direct tests/regressions:
  rerun the exact direct suites added or changed in Sessions `48`, `49`, and
  `50`
- Likely direct tests/regressions:
  run `./scripts/run_test_gates.sh completeness-check` only if new test files
  or test-bucket classifications require it
- Likely named gates:
  `baseline`
- Likely named gates:
  `1to1`
- Likely named gates:
  `groups`
- Likely named gates:
  `feed`
- Matrix/closure docs to update when done:
  this session owns the stable media-doc refresh and the Test-Flight index /
  closure-audit refresh
- Dependency on earlier sessions:
  Sessions `48`, `49`, and `50`

## Why this is not fewer sessions

- Session `48` is a pure composer-state/UI problem.
  Folding it into the thumbnail contract would mix deterministic send-surface
  regressions with DB/storage changes and make it too easy to skip a clean
  widget-level proof for the flicker bug
- Session `49` is the local-thumbnail persistence and shared-render contract.
  It touches migrations, repositories, upload/download helpers, and shared
  renderers; that is a different seam from both batch composer state and player
  controller work
- Session `50` adds a new dependency and a new full-screen player surface.
  Bundling it into Session `49` would create one large session spanning model
  migration, local file persistence, shared renderer behavior, and
  controller-driven playback UI
- Session `51` must stay separate so acceptance, stale-doc refresh, and
  accepted-difference recording do not disappear into earlier implementation
  sessions

## Why this is not more sessions

- there is no independent verification value in a migration-only thumbnail
  session:
  the `thumbnail_path` contract matters only when extraction, persistence, and
  render use it together
- there is no need for separate 1:1, group, and feed playback sessions:
  the affected routes all reuse the same shared media/viewer seam and should be
  verified together
- there is no need for a separate protocol session just to chase inline
  base64 thumbnails:
  current listener-driven auto-download plus local thumbnail extraction is
  enough to fix the reported black-rectangle bug without reopening both chat
  and group wire payloads
- there is no need for a separate share-target-picker session:
  `share_target_picker_screen.dart` is adjacent evidence, but fixing that raw
  preview would widen this report beyond the minimum user-visible closure bar

## Regression and gate contract

- Apply `Test-Flight-Improv/14-regression-test-strategy.md` literally:
  each implementation session adds or updates the direct regression first for
  the seam it changes, then runs the smallest matching named gates
- Session `48` should run the direct composer/widget suites plus:
  `./scripts/run_test_gates.sh 1to1`,
  `./scripts/run_test_gates.sh groups`,
  and `./scripts/run_test_gates.sh baseline`
- Session `49` should run the media/model/storage/render suites plus:
  `./scripts/run_test_gates.sh 1to1`,
  `./scripts/run_test_gates.sh groups`,
  `./scripts/run_test_gates.sh feed`,
  and `./scripts/run_test_gates.sh baseline`
- Session `50` should run the player/routing suites plus:
  `./scripts/run_test_gates.sh 1to1`,
  `./scripts/run_test_gates.sh groups`,
  `./scripts/run_test_gates.sh feed`,
  and `./scripts/run_test_gates.sh baseline`
- `transport` is out unless a later detailed plan proves that the final
  implementation changed startup/resume/reconnect/device-backed media recovery
  wiring instead of staying inside local render/download helpers
- `completeness-check` is closure-session work only if new tests or changed
  classification rules require it

## Matrix update contract

- Do not create a new Report `25` matrix doc
- Session `51` is the closure owner for stable doc refresh
- The existing docs that should carry the maintenance-time meaning are:
  `UI-10-Media/media-client-spec.md`,
  `UI-10-Media/media-display-spec.md`,
  `Test-Flight-Improv/25-video-upload-bugs-spec-session-breakdown.md`,
  `Test-Flight-Improv/00-INDEX.md`,
  and `Test-Flight-Improv/17-roadmap-closure-audit.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` and
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  should only change if the final implementation alters the long-lived 1:1 or
  group maintenance promises rather than just fixing the shared video display
  and playback seam

## Downstream execution path

- Session `48` should next go through:
  `$implementation-plan-orchestrator`,
  `$implementation-execution-qa-orchestrator`,
  `$implementation-closure-audit-orchestrator`
- Session `49` should next go through:
  `$implementation-plan-orchestrator`,
  `$implementation-execution-qa-orchestrator`,
  `$implementation-closure-audit-orchestrator`
- Session `50` should next go through:
  `$implementation-plan-orchestrator`,
  `$implementation-execution-qa-orchestrator`,
  `$implementation-closure-audit-orchestrator`
- Session `51` should next go through:
  `$implementation-plan-orchestrator`,
  `$implementation-execution-qa-orchestrator`,
  `$implementation-closure-audit-orchestrator`

## Structural blockers remaining

- Report `25` remains `still_open` until Session `48` has a clean
  `./scripts/run_test_gates.sh baseline` pass in an environment that can write
  the Flutter SDK cache and owns the CocoaPods workspace needed for
  `integration_test/loading_states_smoke_test.dart`
- Stable closure/index/media-doc refresh remains deferred until that baseline
  proof exists

## Accepted differences intentionally left unchanged

- no inline base64 thumbnail or blurhash rollout in chat/group payloads
- no new tap-triggered receiver download orchestration path;
  the existing auto-download listeners remain the receiver hydration contract
- no share-target-picker raw-video preview redesign
- no posts-media display redesign beyond keeping shared video-processing model
  changes compatible with posts code/tests
- no gallery-wide mixed image/video carousel redesign;
  the required closure is a real video player for tapped videos plus preserved
  image viewing behavior for images

## Exact docs/files used as evidence

- `Test-Flight-Improv/25-video-upload-bugs-spec.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`
- `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/17-roadmap-closure-audit.md`
- `UI-10-Media/media-client-spec.md`
- `UI-10-Media/media-display-spec.md`
- `pubspec.yaml`
- `lib/core/media/video_process_result.dart`
- `lib/core/media/image_processor.dart`
- `lib/core/media/pending_composer_media.dart`
- `lib/core/media/media_file_manager.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/features/groups/domain/models/group_message_payload.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/full_screen_image_viewer.dart`
- `lib/shared/widgets/media/media_grid.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/message_bubble.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `lib/features/share/presentation/screens/share_target_picker_screen.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- `lib/core/database/migrations/010_media_attachments.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/main.dart`
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/core/media/image_processor_test.dart`
- `test/core/media/pending_composer_media_test.dart`
- `test/features/conversation/domain/models/media_attachment_test.dart`
- `test/core/database/migrations/010_media_attachments_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
- `test/features/feed/presentation/widgets/message_bubble_test.dart`
- `test/features/share/presentation/share_target_picker_screen_test.dart`
- `test/shared/widgets/media/full_screen_image_viewer_test.dart`
- `test/shared/widgets/media/media_grid_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- the session count matches real code seams instead of mirroring the proposal’s
  bullet count
- each implementation session has a distinct direct regression family and a
  meaningful verified end state
- the split explicitly records the proposal items that would widen into
  protocol work and keeps them out of the minimum safe implementation set
- closure ownership is assigned clearly to existing docs instead of inventing a
  new matrix artifact
