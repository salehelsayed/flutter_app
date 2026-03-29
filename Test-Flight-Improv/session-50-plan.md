# Session 50 Plan: Shared Video Playback Routing And Full-Screen Player

## Final verdict

`stale/already-covered`

## Final plan

### 1. real scope

- Refresh Session `50` against the current repo state only.
- Do not execute the stale plan to add `video_player`, create `lib/shared/widgets/media/full_screen_video_player.dart`, or split video taps away from `FullScreenImageViewer` just to match old prose.
- Treat the current seam as:
  shared 1:1, group, and feed video tap routing into the existing video-capable full-screen viewer, using the already-settled local thumbnail/render contract from Session `49`.
- Explicit non-goals for this session refresh:
  payload changes, auto-download orchestration changes, gallery/carousel redesign, share-target media fixes, Session `48` baseline closure work, and Session `51` closure/doc updates.

### 2. closure bar

- A downloaded video tapped from the current 1:1 conversation, group conversation, or feed preview surface must open a full-screen viewer that actually plays video, supports pause/play, allows seek/scrub, and preserves close/back behavior.
- Images must keep the existing image-gallery behavior.
- Session `50` is closed without new implementation if the current repo already satisfies that user-visible contract through the shared viewer path.

### 3. source of truth

- Current code and current tests beat stale proposal prose where they disagree.
- `Test-Flight-Improv/test-gate-definitions.md` remains the execution source of truth for named gates.
- `Test-Flight-Improv/25-video-upload-bugs-spec-session-breakdown.md` remains the session ledger source, but its original Session `50` implementation shape is stale against the current tree.
- `Test-Flight-Improv/session-49-plan.md` is the dependency refresh source for the settled local thumbnail/render contract.
- Session `48`'s still-open baseline proof state does not reopen the Session `50` viewer seam; it only remains an overall report-closure dependency outside this session.

### 4. session classification

- `stale/already-covered`

### 5. exact problem statement

- The original Session `50` plan assumed three things that are no longer true:
  there was no `video_player` dependency, `FullScreenImageViewer` was image-only, and the current 1:1/group/feed tap routes therefore could not play video.
- Current repo evidence shows the opposite:
  `pubspec.yaml` already includes `video_player`,
  `lib/shared/widgets/media/full_screen_image_viewer.dart` already branches video paths to `_FullScreenVideoPage` backed by `VideoPlayerController.file(...)`,
  that page already supports tap-to-play/pause, `VideoProgressIndicator(... allowScrubbing: true)`, and app-bar close/back behavior,
  and the in-scope 1:1/group/feed surfaces already push media taps into that shared viewer.
- The remaining gap is evidence shape, not product behavior:
  direct route-level regressions for 1:1, group, and feed are lighter than the current code reality, but that is not enough to justify reopening the stale “add a new player” implementation path.

### 6. files and repos to inspect next

- Do not inspect broader repo areas unless a concrete in-scope reproducer exists in the current tree.
- If this session is reopened, inspect only:
  `pubspec.yaml`
  `lib/shared/widgets/media/full_screen_image_viewer.dart`
  `lib/features/conversation/presentation/screens/conversation_screen.dart`
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
  `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
  `test/shared/widgets/media/full_screen_image_viewer_test.dart`
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  `test/features/groups/presentation/group_conversation_wired_test.dart`
  `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`

### 7. existing tests covering this area

- Current direct evidence already exists in:
  `test/shared/widgets/media/full_screen_image_viewer_test.dart`
  `test/shared/widgets/media/media_grid_test.dart`
- Those tests prove the current shared viewer has a video branch and that downloaded video attachments render through thumbnail-based shared media cells with a play affordance.
- The surrounding surface tests exist, but they do not currently pin the full navigation route into the viewer:
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  `test/features/groups/presentation/group_conversation_screen_test.dart`
  `test/features/groups/presentation/group_conversation_wired_test.dart`
  `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
- Session `48`'s landed composer batch UX changes do not materially alter this playback routing seam beyond leaving the same conversation/group viewer entry points in place.

### 8. regression/tests to add first

- None before any production change.
- If a current failing reproducer reopens Session `50`, add exactly one failing route-level regression in the surface that reproduces it first:
  `test/features/conversation/presentation/screens/conversation_screen_test.dart` for 1:1,
  `test/features/groups/presentation/group_conversation_wired_test.dart` for groups,
  `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart` for feed.
- Use a route observer or equivalent navigation probe with a downloaded video attachment; do not add a new player widget test first, because that would assume the stale architecture rather than proving the current shared viewer is insufficient.

### 9. step-by-step implementation plan

1. Stop the original Session `50` implementation path here. Do not add a new dependency or `full_screen_video_player.dart` on current evidence.
2. If downstream execution claims Session `50` still blocks Report `25`, reproduce one current failing media-tap behavior in an in-scope 1:1, group, or feed surface.
3. Add one failing direct regression in the existing surface test file that proves the current shared viewer route is insufficient.
4. Reuse the existing `FullScreenImageViewer` video branch for any minimal fix unless that regression proves the shared viewer architecture itself cannot satisfy the seam.
5. Stop again after the first minimal fix path is identified. If no current reproducer exists, close Session `50` as already covered and leave cross-slice acceptance/doc refresh to Session `51`.

### 10. risks and edge cases

- Video detection in the shared viewer currently depends on `isLikelyVideoPath(path)` extension matching; a path without a video extension would fall back to the image branch. Do not treat that as a real blocker unless an in-scope reproducer proves the app currently generates such paths.
- The current route intentionally opens only for media with `localPath != null` and `downloadStatus == 'done'`; pending/downloading media are still non-playable by design and should not reopen receiver download orchestration in this session.
- Group playback routing lives in `group_conversation_wired.dart`, not the pure screen file, so any reopen-only regression needs to pin the wired navigation seam.
- Session `48` remains still-open because of environment-blocked `baseline` proof, but that is not evidence of a Session `50` product regression.

### 11. exact tests and gates to run

- For the stale/no-code path:
  no mandatory test run is required to progress this plan artifact.
- If a concrete reproducer reopens the session, run these direct suites first:
  `flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart`
  `flutter test test/shared/widgets/media/media_grid_test.dart`
  `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
  `flutter test test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
- If production code changes after that reopen, run the named gates required by the touched surfaces:
  `./scripts/run_test_gates.sh baseline`
  `./scripts/run_test_gates.sh 1to1`
  `./scripts/run_test_gates.sh groups`
  `./scripts/run_test_gates.sh feed`

### 12. known-failure interpretation

- Session `48`'s blocked `baseline` rerun remains an environment/setup problem and does not indicate a Session `50` playback regression.
- A failure counts as new Session `50` evidence only if it reproduces against the current shared viewer/routing contract, not against the stale assumption that “no video player exists.”

### 13. done criteria

- This plan is done when the repo-local Session `50` artifact clearly records that the original “add a new full-screen video player” implementation path is stale against the current code.
- Downstream execution should skip production changes unless a concrete current reproducer and failing direct regression exist.
- Session `51` should inherit closure/doc responsibility using the current shared-viewer contract rather than the stale separate-player plan.

### 14. scope guard

- No new `video_player` dependency work.
- No new `lib/shared/widgets/media/full_screen_video_player.dart` created just to satisfy stale naming.
- No payload, repository, migration, or auto-download orchestration changes.
- No mixed image/video gallery redesign beyond the current shared viewer behavior.
- No Session `48` baseline-proof closure work.
- No Session `51` doc/index/spec refresh in this session artifact.

### 15. accepted differences / intentionally out of scope

- The repo now satisfies the in-scope playback seam through a video-capable `FullScreenImageViewer` rather than a separate `FullScreenVideoPlayer`.
- The feed media-bearing preview surface remains `ScrollableMessagePreview`; the collapsed preview/header expansion behavior is unchanged.
- Session `48`'s baseline-proof closure and Session `51`'s closure/doc ownership remain separate concerns.

### 16. dependency impact

- Session `51` should document the current shared viewer contract instead of reviving the stale separate-player implementation plan.
- Session `48` can still block overall Report `25` closure until its `baseline` proof exists, but that does not block this Session `50` refresh classification.
- If a future reproducer really reopens playback routing, it should reuse the settled Session `49` thumbnail/render contract rather than inventing a new media-path shape.

## Structural blockers remaining

- None after reclassifying Session `50` as `stale/already-covered`.

## Incremental details intentionally deferred

- If maintainers want stronger future-proofing, add one reopen-only route regression per surface to pin current navigation into the shared viewer.
- No direct navigator regression was added now because Session `51` owns acceptance/closure work and there is no current reproducer demanding production changes.

## Accepted differences intentionally left unchanged

- `FullScreenImageViewer` remains the shared image-and-video fullscreen surface.
- There is no separate `full_screen_video_player.dart`, and current evidence does not justify creating one.
- Session `48`'s environment-blocked `baseline` proof remains open outside this session.

## Exact docs/files used as evidence

- `Test-Flight-Improv/25-video-upload-bugs-spec-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/25-video-upload-bugs-spec.md`
- `Test-Flight-Improv/session-49-plan.md`
- `Test-Flight-Improv/session-48-plan.md`
- `pubspec.yaml`
- `lib/shared/widgets/media/full_screen_image_viewer.dart`
- `lib/shared/widgets/media/media_grid.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `lib/core/media/video_thumbnail_cache.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `test/shared/widgets/media/full_screen_image_viewer_test.dart`
- `test/shared/widgets/media/media_grid_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`

## Why the plan is safe or unsafe to implement now

- Safe to skip implementation now:
  the current repo already has the dependency, the shared full-screen viewer already plays video with seek and close behavior, and the in-scope 1:1/group/feed surfaces already route taps into that viewer.
- Unsafe to execute the stale original plan:
  it would add duplicate architecture and unnecessary file churn for behavior the current tree already ships.
