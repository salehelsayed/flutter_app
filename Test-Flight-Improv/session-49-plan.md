# Session 49 Plan: Local Thumbnail Persistence and Shared Video Rendering Surfaces

## Final verdict

`stale/already-covered`

## Final plan

### 1. real scope

- Refresh Session `49` against the current repo state only.
- Do not execute the original `thumbnail_path` DB/model/payload plan unless a concrete failing in-scope reproducer exists in the current tree.
- Treat the current in-scope seam as:
  shared chat/group/feed video thumbnail rendering from local files, plus the local sidecar contract already implemented through derived `.thumb.jpg` paths.
- Explicit non-goals for this session refresh:
  `thumbnail_path` schema work, `MediaAttachment` wire/payload changes, blurhash/base64 thumbnails, share-target preview fixes, Session `50` routing/player redesign, Session `51` closure/doc work.

### 2. closure bar

- In-scope shared video surfaces must render through `MediaThumbnailImage` and `VideoThumbnailCache`, not through raw `Image.file(videoPath)` paths.
- The local thumbnail contract is satisfied by a derived sidecar path next to the local video path:
  `derivedVideoThumbnailPath(videoPath)` yields `<video>.thumb.jpg`, and `VideoThumbnailCache.resolve(...)` reuses that file on later renders/reloads.
- Session `49` is considered closed without new implementation if no current chat/group/feed surface still needs the original DB-backed thumbnail plan to meet the Report `25` closure bar.

### 3. source of truth

- Current code and current tests beat the stale decomposition/proposal prose where they disagree.
- `Test-Flight-Improv/test-gate-definitions.md` remains the execution source of truth for named gates.
- `UI-10-Media/media-client-spec.md` is stale for inline thumbnail/base64/blurhash fields and must not override the current repo-local derived-sidecar contract.
- `Test-Flight-Improv/25-video-upload-bugs-spec-session-breakdown.md` remains the session ledger source, but its Session `49` implementation shape is stale against the landed tree.

### 4. session classification

- `stale/already-covered`

### 5. exact problem statement

- The original Session `49` breakdown assumed three things that are no longer true in the current repo:
  shared media surfaces still attempted to render video files as images, there was no repo-local thumbnail sidecar contract, and the full-screen path had no video-capable viewer.
- Current repo evidence shows the opposite for the in-scope chat/group/feed surfaces:
  `MediaGridCell` and the feed collapsed preview already render via `MediaThumbnailImage`, that widget already resolves or generates a local `.thumb.jpg` sidecar via `VideoThumbnailCache`, and `FullScreenImageViewer` already branches to video playback for video paths.
- The remaining original Session `49` prescription would add DB/model/repository churn to duplicate an already-working derived-path contract without a current failing reproducer.

### 6. files and repos to inspect next

- Do not inspect broader repo areas unless a current failing reproducer exists.
- If this session is reopened, inspect only:
  `lib/shared/widgets/media/media_thumbnail_image.dart`
  `lib/core/media/video_thumbnail_cache.dart`
  `lib/shared/widgets/media/media_grid_cell.dart`
  `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
  `lib/features/conversation/application/load_conversation_use_case.dart`
  `lib/features/feed/application/load_feed_use_case.dart`
  `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`
  `lib/features/conversation/presentation/screens/conversation_wired.dart`
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`

### 7. existing tests covering this area

- Current direct evidence already exists in:
  `test/shared/widgets/media/media_grid_test.dart`
  `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
  `test/shared/widgets/media/full_screen_image_viewer_test.dart`
  `test/features/conversation/application/load_conversation_use_case_test.dart`
  `test/features/feed/application/load_feed_use_case_test.dart`
  `test/features/feed/application/feed_projection_test.dart`
- The breakdown’s cited `test/shared/widgets/media/media_grid_cell_test.dart` does not exist in the current repo; the current shared-grid coverage lives in `test/shared/widgets/media/media_grid_test.dart`.
- Session `48` landed batch-processing changes in the conversation/group wired screens, but those changes do not reopen this renderer/persistence seam.

### 8. regression/tests to add first

- None before any production change.
- If a current failing in-scope surface is reproduced, add exactly one failing direct regression in an existing file first:
  `test/shared/widgets/media/media_grid_test.dart` for shared grid rendering,
  `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart` for collapsed feed preview,
  `test/features/conversation/application/load_conversation_use_case_test.dart` or `test/features/feed/application/feed_projection_test.dart` for reload/relative-path hydration.
- Do not add a new migration or repository test first; that would assume the stale DB-backed approach before proving the derived-sidecar contract is insufficient.

### 9. step-by-step implementation plan

1. Stop the original Session `49` implementation path here. Do not add `043_media_attachment_thumbnail_path.dart`, `MediaAttachment.thumbnailPath`, or repository API widening on current evidence.
2. If downstream execution wants to challenge this stale classification, reproduce one current failing chat/group/feed seam in the repo as it exists now.
3. Add one failing direct regression in an existing test file that proves the reproducer against the current `MediaThumbnailImage` and `VideoThumbnailCache` contract.
4. Reuse the existing derived-sidecar contract for any minimal fix; do not jump to DB/model/payload work unless the reproducer proves the current architecture cannot satisfy the seam.
5. Stop again after the first minimal fix path is identified. If the failing regression cannot be reproduced, close Session `49` as already covered.

### 10. risks and edge cases

- Lazy first-render thumbnail extraction may still show a brief placeholder before the cache resolves; that is not by itself evidence that the stale DB-backed plan is needed.
- Pre-upload 1:1 optimistic rows still follow the current local file contract; do not widen this session into a new durable pre-upload architecture.
- `share_target_picker_screen.dart` still previews the first shared file with `Image.file(...)`; that is adjacent evidence but explicitly out of scope for Report `25` minimum closure.
- Any attempt to add DB-backed thumbnail state now risks broad test-double and repository churn while duplicating the current derived-path contract.

### 11. exact tests and gates to run

- For the stale/no-code path:
  no mandatory test run is required to progress this plan artifact.
- If a concrete reproducer reopens the session, run these direct suites first:
  `flutter test test/shared/widgets/media/media_grid_test.dart`
  `flutter test test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
  `flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart`
  `flutter test test/features/conversation/application/load_conversation_use_case_test.dart`
  `flutter test test/features/feed/application/load_feed_use_case_test.dart`
  `flutter test test/features/feed/application/feed_projection_test.dart`
- If production code changes after that reopen, run the named gates required by the touched surfaces:
  `./scripts/run_test_gates.sh baseline`
  `./scripts/run_test_gates.sh 1to1`
  `./scripts/run_test_gates.sh groups`
  `./scripts/run_test_gates.sh feed`

### 12. known-failure interpretation

- Session `48` remains still-open only because `./scripts/run_test_gates.sh baseline` is environment-blocked; that is not a Session `49` regression and must not block this refresh.
- A failure in a new reopen-only regression counts as new only if it reproduces against the current `MediaThumbnailImage` and `VideoThumbnailCache` path, not against the stale breakdown assumptions.

### 13. done criteria

- This plan is done when the repo-local Session `49` artifact clearly records that the original DB/migration implementation path is stale against the current code.
- Downstream execution should skip production changes unless a concrete current reproducer and failing direct regression exist.
- If such a reproducer never materializes, Session `49` can close as already covered and Session `50` must be refreshed separately against the actual current player/routing state.

### 14. scope guard

- No `thumbnail_path` DB column.
- No `MediaAttachment` payload or wire-format thumbnail fields.
- No blurhash/base64 thumbnail rollout.
- No share-target preview fix.
- No player dependency, routing redesign, or Session `50` viewer work.
- No Session `51` closure/doc updates in this session artifact.

### 15. accepted differences / intentionally out of scope

- The repo now satisfies the in-scope thumbnail/render seam with a derived local sidecar path instead of persisted DB thumbnail metadata.
- `UI-10-Media/media-client-spec.md` remains stale for inline thumbnail/base64/blurhash fields and is intentionally not reopened here.
- `lib/features/share/presentation/screens/share_target_picker_screen.dart` remains out of scope even though it still uses `Image.file(...)` for the first shared file preview.
- Session `50` may still own tap-routing/doc cleanup decisions, but it must be refreshed against the current `FullScreenImageViewer` video-capable state rather than the stale “no player exists” assumption.

### 16. dependency impact

- Session `50` should be re-planned before execution because the current repo already contains video-capable full-screen viewing, so its original starting assumptions are stale.
- Session `51` should record the current derived-sidecar thumbnail contract if the overall report closes, rather than reviving the stale DB/payload thumbnail prose.

## Structural blockers remaining

- None after reclassifying Session `49` as `stale/already-covered`.

## Incremental details intentionally deferred

- If maintainers want stronger acceptance evidence, add one reopen-only regression around relative-path video reload in an existing loader/widget test file before touching production code.

## Accepted differences intentionally left unchanged

- The current repo derives local thumbnail sidecars from `localPath` instead of persisting a separate thumbnail field.
- The share-target preview surface stays unchanged.
- Session `50` and Session `51` ownership boundaries stay intact even though their stale assumptions were noted during this refresh.

## Exact docs/files used as evidence

- `Test-Flight-Improv/25-video-upload-bugs-spec-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/25-video-upload-bugs-spec.md`
- `UI-10-Media/media-client-spec.md`
- `UI-10-Media/media-display-spec.md`
- `lib/core/media/video_process_result.dart`
- `lib/core/media/image_processor.dart`
- `lib/core/media/pending_composer_media.dart`
- `lib/core/media/media_file_manager.dart`
- `lib/core/media/video_thumbnail_cache.dart`
- `lib/core/database/migrations/010_media_attachments.dart`
- `lib/core/database/migrations/042_media_attachment_reliability_columns.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/main.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/load_conversation_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/feed/application/load_feed_use_case.dart`
- `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/message_bubble.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `lib/shared/widgets/media/media_grid.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `lib/shared/widgets/media/full_screen_image_viewer.dart`
- `lib/features/posts/application/attach_post_media_use_case.dart`
- `lib/features/posts/application/post_surface_hydrator.dart`
- `lib/features/share/presentation/screens/share_target_picker_screen.dart`
- `test/core/media/video_process_result_test.dart`
- `test/core/media/image_processor_test.dart`
- `test/core/media/pending_composer_media_test.dart`
- `test/core/media/media_file_manager_test.dart`
- `test/core/database/helpers/media_attachments_db_helpers_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/conversation/application/upload_media_use_case_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/features/conversation/application/load_conversation_use_case_test.dart`
- `test/features/conversation/domain/models/media_attachment_test.dart`
- `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/feed/application/load_feed_use_case_test.dart`
- `test/features/feed/application/feed_projection_test.dart`
- `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
- `test/shared/widgets/media/media_grid_test.dart`
- `test/shared/widgets/media/full_screen_image_viewer_test.dart`
- `test/features/posts/phase2/attach_post_media_use_case_test.dart`

## Why the plan is safe or unsafe to implement now

- Safe to stop the original Session `49` implementation path now because the current repo already provides the in-scope user-visible behavior through `MediaThumbnailImage`, `VideoThumbnailCache`, shared media grids, and a video-capable full-screen viewer.
- Unsafe to implement the stale DB/model/payload plan now because it would widen schema, repository, and test-double blast radius without current evidence that the derived-sidecar contract fails the in-scope chat/group/feed surfaces.
