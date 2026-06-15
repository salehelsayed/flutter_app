# Session E Plan: Thumbnail Failure Is Not Media Unavailable

Status: execution-ready

Source doc: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`
Breakdown artifact: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`
Session row: Session E, `Thumbnail Failure Is Not Media Unavailable`

## Planning Progress

- 2026-06-11 23:39 CEST - Planner completed. Files inspected since last update: shared `MediaThumbnailImage` call sites in composer and feed preview, `VideoThumbnailCache` call sites, thumbnail-related shared tests. Decision/blocker: draft is narrow and implementation-ready pending reviewer pass; no production implementation was made. Next action: reviewer sufficiency pass.
- 2026-06-11 23:42 CEST - Reviewer started. Files inspected since last update: draft plan structure via `rg` and full plan readback. Decision/blocker: check mandatory sections, simulator ownership, checklist coverage, test/gate contract, and scope guard. Next action: record sufficiency findings.
- 2026-06-11 23:43 CEST - Reviewer completed. Files inspected since last update: draft plan readback. Decision/blocker: sufficient as-is; no missing structural file/test/gate coverage found. Incremental details are limited to implementation-time API shape choices. Next action: arbiter classification and final status.
- 2026-06-11 23:44 CEST - Arbiter started. Files inspected since last update: reviewer findings and final draft. Decision/blocker: classify findings into structural blockers, incremental details, and accepted differences. Next action: persist execution-ready verdict.
- 2026-06-11 23:45 CEST - Arbiter completed. Files inspected since last update: final draft and reviewer pass. Decision/blocker: no structural blockers; plan is execution-ready for Session E only. Next action: implement in a future execution pass, leaving simulator/final matrix/source-report closure to Session F.

## Execution Progress

- 2026-06-11 23:32 CEST - Contract extracted. Files inspected since last update: this Session E plan, session breakdown, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/codebase-test-inventory.md`, scoped owner-file `git status`/`git diff`, and a `graphify-arch` query for media thumbnail fallback context. Command currently running: none. Decision/blocker: execution contract is concrete; nested child-agent tools are unavailable in this session, so this execution will use the skill's bounded local sequential fallback and record that fallback explicitly. Existing dirty owner-file edits were observed in `media_grid_cell.dart`, `letter_card.dart`, and related tests; they will not be reverted or claimed as Session E work unless directly modified for this session. Next action: read current owner files and add failing-first Session E regressions.
- 2026-06-11 23:32 CEST - Local Executor fallback running. Files inspected or touched since last update: `lib/shared/widgets/media/media_grid_cell.dart`, `lib/shared/widgets/media/media_thumbnail_image.dart`, `lib/core/media/video_thumbnail_cache.dart`, `test/shared/widgets/media/media_grid_cell_test.dart`, `test/shared/widgets/media/media_thumbnail_image_test.dart`; touched `test/shared/widgets/media/media_grid_cell_test.dart` to add the four required failing-first regressions. Command currently running: `flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name "video thumbnail failure shows video fallback, not unavailable"` next. Decision/blocker: production not changed yet; RED capture started. Next action: run each required plain-name regression before implementation.
- 2026-06-11 23:32 CEST - RED capture triage. Files touched since last update: `test/shared/widgets/media/media_grid_cell_test.dart` only. Commands completed: `video thumbnail failure shows video fallback, not unavailable` unexpectedly passed before implementation because host thumbnail resolution did not deterministically return `null`; first `failed video media still shows unavailable retry` attempt failed due a too-small 120px fixture overflow, then passed after adjusting the fixture to 160px and is classified as an already-green guard; `missing-file done video is unavailable, not fallback` failed because current code did not render the expected unavailable state; `pending video remains loading without retry or play` failed because current code rendered no loading indicator. Decision/blocker: thumbnail-failure regression needs the plan-approved deterministic resolver seam before valid RED evidence. Next action: add a tiny thumbnail resolver seam without changing behavior, update the grid-cell regression to force `null`, then rerun that plain-name test for RED.
- 2026-06-11 23:32 CEST - RED capture completed. Files touched since last update: `lib/shared/widgets/media/media_thumbnail_image.dart`, `lib/shared/widgets/media/media_grid_cell.dart`, and `test/shared/widgets/media/media_grid_cell_test.dart` for a behavior-neutral optional thumbnail resolver seam. Command completed: `flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name "video thumbnail failure shows video fallback, not unavailable"` failed for the intended reason after the seam, showing `Media unavailable` when the resolver returned `null` for an existing local video. Decision/blocker: valid RED evidence captured for the primary bug; two other behavior regressions are RED, failed-video retry is already green as a guard. Next action: implement the display-policy fix.
- 2026-06-11 23:32 CEST - Implementation completed. Files touched since last update: `lib/shared/widgets/media/media_grid_cell.dart`, `lib/shared/widgets/media/media_thumbnail_image.dart`, `test/shared/widgets/media/media_grid_cell_test.dart`, `test/shared/widgets/media/media_thumbnail_image_test.dart`. Command completed: `dart format lib/shared/widgets/media/media_grid_cell.dart lib/shared/widgets/media/media_thumbnail_image.dart test/shared/widgets/media/media_grid_cell_test.dart test/shared/widgets/media/media_thumbnail_image_test.dart`. Decision/blocker: `MediaThumbnailImage` now maps null video thumbnail results to placeholder only when the source file exists; `MediaGridCell` now requires an existing local file before done media can open or show video overlay, and pending media returns loading. Next action: run required GREEN plain-name checks and focused suites.
- 2026-06-11 23:32 CEST - Required direct GREEN checks completed. Files touched since last update: none. Commands completed and passed: `flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name "video thumbnail failure shows video fallback, not unavailable"`, `flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name "failed video media still shows unavailable retry"`, `flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name "missing-file done video is unavailable, not fallback"`, and `flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name "pending video remains loading without retry or play"`. Decision/blocker: direct requirement checks are green. Next action: run full focused suites and conditional thumbnail compatibility suites.
- 2026-06-11 23:32 CEST - Conditional suite triage started. Files touched since last update: none. Commands completed: `flutter test test/shared/widgets/media/media_grid_cell_test.dart` passed; `flutter test test/shared/widgets/media/media_thumbnail_image_test.dart` passed; `flutter test test/shared/widgets/media/media_grid_test.dart` failed in `renders generated thumbnail for downloaded video attachments` because `MediaGridCell` eagerly built its unavailable `error` widget while the minimal shared-grid test wrapper did not install `AppLocalizations`. Decision/blocker: classify as a Session E-caused lazy-construction compatibility issue, not a production policy failure. Next action: make the error widget lazy, then rerun the suite.
- 2026-06-11 23:32 CEST - Focused and conditional suites completed. Files touched since last update: `lib/shared/widgets/media/media_grid_cell.dart` only, to make the unavailable `error` widget lazy with `Builder` so thumbnail-success paths do not eagerly require app localizations. Commands completed and passed: `flutter test test/shared/widgets/media/media_grid_test.dart`, `flutter test test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart --plain-name "CollapsedModeCardBody media thumbnail"`, and `flutter test test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`. Decision/blocker: focused and caller compatibility evidence is green; `letter_card.dart` was not touched by Session E. Next action: run recommended `./scripts/run_test_gates.sh 1to1`.
- 2026-06-11 23:32 CEST - Named gate started. Files touched since last update: none. Command currently running: `./scripts/run_test_gates.sh 1to1`. Decision/blocker: pending gate result. Next action: record pass/failure and triage if needed.
- 2026-06-11 23:32 CEST - Named gate completed. Files touched since last update: none. Command completed and passed: `./scripts/run_test_gates.sh 1to1`. Decision/blocker: recommended Session E gate is green. Next action: run `graphify update .` and `git diff --check` on touched files.
- 2026-06-11 23:32 CEST - Final formatting and diff hygiene completed. Files touched since last update: `test/shared/widgets/media/media_grid_cell_test.dart` only, reverting an accidental unrelated fixture-size change. Commands completed and passed: `dart format ...` on touched Dart files, `git diff --check -- <Session E touched files>`, and `flutter test test/shared/widgets/media/media_grid_cell_test.dart`. Command completed with non-blocking note: `graphify update .` rebuilt `graphify-out/graph.json` and `GRAPH_REPORT.md`, skipped HTML because the full graph has 94645 nodes. Decision/blocker: no whitespace/test blocker; graph refresh should be rerun once more because the test fixture cleanup happened after the first refresh. Next action: rerun `graphify update .`, then perform local QA review.
- 2026-06-11 23:32 CEST - Final graph refresh completed. Files touched since last update: graph outputs under `graphify-out`. Command completed: `graphify update .` rebuilt `graphify-out/graph.json` and `GRAPH_REPORT.md`; HTML was skipped because the full graph has 94645 nodes, which exceeds the 5000-node visualization limit. Decision/blocker: graph refresh evidence captured with a non-blocking HTML-viz skip. Next action: run final scoped `git diff --check`, then local QA review.
- 2026-06-11 23:32 CEST - Final scoped diff check completed. Files touched since last update: none. Command completed and passed: `git diff --check -- lib/shared/widgets/media/media_grid_cell.dart lib/shared/widgets/media/media_thumbnail_image.dart test/shared/widgets/media/media_grid_cell_test.dart test/shared/widgets/media/media_thumbnail_image_test.dart Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-E-plan.md`. Decision/blocker: no whitespace blocker. Next action: local QA review.
- 2026-06-11 23:32 CEST - Local QA completed and final verdict written. Files inspected since last update: final scoped diffs, final implementation/test lines, and recorded test/gate evidence. Command currently running: none. Decision/blocker: no QA blocking issues remain; local fallback execution is sufficient for Session E. Next action: stop with `accepted_with_explicit_follow_up`, leaving simulator/final documentation closure to Session F.

## real scope

Session E changes only the local display policy for completed video attachments whose thumbnail decode/generation fails.

In scope:

- A `done` video attachment with an existing local source file and no usable thumbnail must render a video fallback/play affordance, not the real `Media unavailable` placeholder.
- True unavailable states must stay visually unavailable: `failed`, `integrity_failed`, invalid descriptor/size/verification state, missing local source file, and upload-failed/cancelled states.
- Pending/downloading/upload-pending states must stay loading/uploading states, not become playable fallbacks.
- Retry controls must stay tied to true retryable media failure status through `GroupMediaIntegrityPolicy.isRetryableDownloadFailure`, not thumbnail cache failure.
- The change may touch shared thumbnail helpers only as needed to distinguish thumbnail-null reasons.

Out of scope:

- Transport, relay, retry, duplicate replay, download, upload, database, lifecycle, notification, or simulator work.
- Final matrix/source-report/closure updates. Session F owns those.
- UI redesign beyond replacing the false unavailable presentation with the existing video fallback/play treatment.

## closure bar

Session E is good enough when the widget policy proves every Session E requirement below:

| Requirement | Planned proof |
| --- | --- |
| Separate video thumbnail decode/generation failure from true media unavailability. | Add a failing widget regression where an existing local `.mp4` has no derived thumbnail and thumbnail generation resolves `null`; after implementation it shows video fallback/play and no unavailable text/icon/retry. |
| Done video with valid local path renders video fallback/play affordance. | Same regression must assert `VideoThumbnailOverlay` is present, `onTap` still fires, and `Media unavailable`/broken-image/retry controls are absent. |
| Failed attachments still show unavailable/retry where appropriate. | Add or extend a failed direct video case with `onRetryUnavailableMedia`, asserting unavailable text, retry semantics/key, no `MediaThumbnailImage`, no video overlay, and callback invocation. |
| Pending attachments still show loading states. | Add or extend a pending video case, asserting a loading indicator or upload-pending copy as appropriate and no retry/play affordance. |
| Missing-file attachments do not become playable fallbacks. | Add a done video case whose `localPath` points to a missing file, asserting unavailable or loading state according to existing policy, no tap, and no video play affordance. |
| Retry stays tied to true failure, not thumbnail failure. | The thumbnail-failure case must assert no unavailable retry; the failed-video case must assert retry appears and invokes the callback. |

Focused widget tests must fail first for the intended current behavior, then pass after implementation. This session does not close the overall 1:1 media-unavailable plan; Session F owns simulator acceptance, final `./scripts/run_test_gates.sh 1to1` combined validation if not run here, source-report updates, matrix updates, and stable closure-reference updates.

## source of truth

- Current production code and tests win over rollout prose if behavior has moved.
- Active source contract: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`.
- Session decomposition contract: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`, Session E row.
- Root-cause report: `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`.
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.
- Test inventory source: `Test-Flight-Improv/codebase-test-inventory.md`.
- Graph navigation evidence: `graphify-arch` query for `MediaGridCell`, `MediaThumbnailImage`, `VideoThumbnailCache`, `LetterCard`, unavailable media, video thumbnail fallback, and retry.

## session classification

`implementation-ready`

Rationale: Session D is accepted with explicit follow-up, the Session E row is the next ordered runnable, and the failure is isolated to widget/display policy with direct host widget regressions. No simulator is required to close this session because the session does not alter multi-device transport, relay state, OS lifecycle, or end-to-end delivery. Simulator and final documentation closure remain Session F-owned.

## exact problem statement

The current thumbnail path can make a playable local video look like true missing media. `MediaGridCell` builds `MediaThumbnailImage` for `done` image/video attachments with non-null `localPath` and passes `_buildUnavailablePlaceholder(context)` as `error`. `MediaThumbnailImage` asks `VideoThumbnailCache.resolve` for video thumbnails and returns `widget.error` when the future completes with `null`. `VideoThumbnailCache.resolve` currently returns `null` for multiple reasons, including missing source files, unsupported paths, and thumbnail-generation exceptions.

The user-visible bug is that a `done` direct 1:1 video with an existing local file can display `Media unavailable` after thumbnail generation fails. That should instead show a video fallback/play affordance. Real unavailable conditions must stay unavailable and retryable where the attachment status allows retry.

## files and repos to inspect next

Production files:

- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `lib/core/media/video_thumbnail_cache.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/shared/widgets/media/media_grid.dart`
- If `MediaThumbnailImage` API changes: `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
- If `MediaThumbnailImage` API changes: `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`

Tests:

- `test/shared/widgets/media/media_grid_cell_test.dart`
- `test/shared/widgets/media/media_thumbnail_image_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart` only if `LetterCard` or media-grid callback wiring changes
- If shared thumbnail API behavior changes: `test/shared/widgets/media/media_grid_test.dart`
- If feed thumbnail preview behavior changes: `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`

Docs/gates:

- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/codebase-test-inventory.md`

## existing tests covering this area

- `test/shared/widgets/media/media_grid_cell_test.dart` already covers GIF display, invalid done media rendering unavailable, group verified video thumbnail derivation, done image without local path loading, and integrity-failed image/video unavailable rendering.
- The same file already verifies retry semantics for at least one failed media case with `onRetryUnavailableMedia`.
- `test/shared/widgets/media/media_thumbnail_image_test.dart` covers GIF cache-size behavior and JPEG resize behavior, but not video thumbnail future success/failure or fallback policy.
- `test/features/conversation/presentation/widgets/letter_card_test.dart` covers failed media action wiring and `MD-012` unavailable media actions being separate from failed-message resend, but it does not prove thumbnail-generation failure policy.
- `test/shared/widgets/media/media_grid_test.dart` and feed collapsed-card tests use `derivedVideoThumbnailPath` fixtures for successful video thumbnail display, which should remain green if the shared thumbnail helper is changed carefully.

Missing coverage:

- No current test forces `VideoThumbnailCache.resolve` or the video thumbnail future to return `null` while the source video file exists.
- No current test pins that a missing local video file must not be treated as a playable thumbnail-failure fallback.
- No current direct video retry case proves failed video remains unavailable and retryable after the thumbnail policy changes.

## regression/tests to add first

Add focused regressions before production changes:

1. `test/shared/widgets/media/media_grid_cell_test.dart`: `video thumbnail failure shows video fallback, not unavailable`
   - Create an existing temp `.mp4` local file without a derived thumbnail file.
   - Pump a `MediaGridCell` with `downloadStatus: done`, `mediaType: video`, `mime: video/mp4`, `localPath` set to that file, and an `onTap` callback.
   - Let the video thumbnail future settle.
   - Current code should fail by showing `Media unavailable` or the broken-image icon after thumbnail resolution returns `null`.
   - Passing behavior: no `Media unavailable`, no broken-image icon, no `Retry unavailable media`, `VideoThumbnailOverlay` is visible, and tapping the cell invokes `onTap`.
   - If the host test environment unexpectedly generates a thumbnail and the test passes before implementation, introduce the smallest deterministic test seam, such as a video thumbnail resolver override in `MediaThumbnailImage` or `VideoThumbnailCache`, then keep the behavior assertions at the grid-cell level.

2. `test/shared/widgets/media/media_grid_cell_test.dart`: `failed video media still shows unavailable retry`
   - Create a failed direct video attachment with `downloadStatus: failed` and an `onRetryUnavailableMedia` callback.
   - Assert unavailable text/icon are shown, `MediaThumbnailImage` and `VideoThumbnailOverlay` are absent, retry semantics/key are present, and tapping retry invokes the callback.

3. `test/shared/widgets/media/media_grid_cell_test.dart`: `missing-file done video is unavailable, not fallback`
   - Use `downloadStatus: done`, `mediaType: video`, and a `localPath` pointing to a file that does not exist.
   - Assert it does not show the video play affordance, does not invoke `onTap`, and renders the existing unavailable or loading state chosen by the implementation.
   - Prefer unavailable for a done row with an explicit missing local file; keep pending/no-path rows as loading.

4. `test/shared/widgets/media/media_grid_cell_test.dart`: `pending video remains loading without retry or play`
   - Use `downloadStatus: pending`, `mediaType: video`, and no durable local file.
   - Assert loading state, no unavailable retry, and no video play affordance.

Add `test/shared/widgets/media/media_thumbnail_image_test.dart` coverage only if the implementation adds or changes a thumbnail-result API in `MediaThumbnailImage`/`VideoThumbnailCache`. Keep those tests focused on result mapping, not full media-grid policy.

## step-by-step implementation plan

1. Re-read the target production files and tests because this worktree is dirty and `media_grid_cell.dart` has uncommitted edits.
2. Add the focused regressions above and run each new test by `--plain-name` to confirm RED for the intended reason.
3. Separate thumbnail result reasons without adding transport or persistence behavior.
   - Preferred small shape: add a tiny typed result in `video_thumbnail_cache.dart`, such as success path, source missing, unsupported/skipped, and generation failed; preserve existing `resolve(String)` behavior for any current callers if practical.
   - Acceptable simpler shape: keep `resolve(String)` but make `MediaThumbnailImage`/`MediaGridCell` explicitly distinguish an existing source video file from a missing source file before mapping thumbnail `null` to fallback.
   - Do not add async streams, DB lookups, retry scheduling, or media repair from this display widget.
4. Update `MediaThumbnailImage` so video thumbnail generation failure for an existing video source returns `placeholder` or a supplied video fallback instead of `error`.
   - Image decode errors must continue to use `error`.
   - Explicit thumbnail image decode errors should continue to use `error` unless a test proves they are only thumbnail failures with an existing video source.
5. Update `MediaGridCell` only as needed to:
   - Pass a video fallback placeholder for done videos with existing local files.
   - Keep `_buildUnavailablePlaceholder` for true unavailable states.
   - Ensure `_canOpen` and `_canShowVideoOverlay` do not become true for missing-file or failed/pending attachments.
6. Re-check `LetterCard` only if callback wiring or media-grid arguments change. Do not modify it for display policy if `MediaGridCell` can own the fix.
7. Run focused tests. If shared thumbnail API changed, run the shared/feed preview tests that instantiate `MediaThumbnailImage`.
8. Run `dart format` on touched Dart files only.
9. Run `git diff --check` scoped to touched files.
10. Run `graphify update .` after implementation to keep the graph current.
11. Stop. Do not update final source report, test matrix, closure reference, or Session F plan from this session.

Stop and replan if:

- The only way to distinguish missing source files from thumbnail failures requires a database/repository contract change.
- The fix requires changing video playback, camera capture, compression, relay media, or direct retry behavior.
- The new thumbnail fallback regression passes before implementation and cannot be made deterministic with a tiny local test seam.

## risks and edge cases

- `VideoThumbnailCache.resolve` currently collapses unsupported path, missing source file, existing generated thumbnail miss, and generation failure into `null`; changing only the UI mapping can accidentally make missing files look playable.
- `MediaGridCell._canShowVideoOverlay` currently depends on media type and unavailable status, not file existence; missing-file done rows need explicit protection if the unavailable mapping changes.
- Shared `MediaThumbnailImage` call sites in composer and feed previews may inherit fallback behavior if the helper changes; run their focused tests if the public API or error mapping changes.
- Host widget tests may rely on `video_compress` throwing `MissingPluginException`; if plugin behavior differs locally, use a deterministic resolver seam rather than depending on platform codec availability.
- Do not validate full video playability in this session. Existing local file existence plus done attachment status is the display boundary; playback failure belongs to a separate video-player UX bug if observed.

## exact tests and gates to run

Required direct RED/GREEN checks:

```bash
flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name "video thumbnail failure shows video fallback, not unavailable"
flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name "failed video media still shows unavailable retry"
flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name "missing-file done video is unavailable, not fallback"
flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name "pending video remains loading without retry or play"
```

Required focused suites after implementation:

```bash
flutter test test/shared/widgets/media/media_grid_cell_test.dart
flutter test test/shared/widgets/media/media_thumbnail_image_test.dart
```

Conditional suites:

```bash
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name "MD-012 unavailable media actions are separate from failed-message resend"
flutter test test/shared/widgets/media/media_grid_test.dart
flutter test test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart --plain-name "CollapsedModeCardBody media thumbnail"
```

Run the conditional suites only if the implementation touches `LetterCard`, `MediaGrid`, `MediaThumbnailImage` public API, or feed/composer thumbnail behavior.

Named gates:

```bash
./scripts/run_test_gates.sh 1to1
```

For this Session E plan, `./scripts/run_test_gates.sh 1to1` is recommended if the session pipeline requires a named gate after shared conversation media widget changes. It is mandatory before overall A-F closure and remains Session F-owned for final combined validation if not run here.

No simulator command is required to accept Session E alone. Session F owns:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1
```

## known-failure interpretation

- New Session E regressions must fail before implementation for the intended visual-policy reason. A pre-implementation pass is invalid evidence unless the test is tightened or a deterministic thumbnail-failure seam is added.
- Existing unrelated red tests in the dirty worktree do not block this session, but any red in touched Session E files must be fixed or explicitly classified.
- `video_compress` host behavior can vary. A `MissingPluginException` caught by `VideoThumbnailCache` and mapped to thumbnail-null is acceptable test setup; an uncaught plugin exception is a production/test failure to fix in the thumbnail seam.
- If `./scripts/run_test_gates.sh 1to1` fails in suites unrelated to touched files, record the failing test names and prior dirty-worktree context; do not claim final closure until Session F or the owning session resolves/classifies them.

## done criteria

- Coverage ledger in `closure bar` is satisfied with tests or explicit notes in the implementing session's final evidence.
- New widget regressions fail first and pass after implementation.
- `done` video with existing local file plus thumbnail failure renders fallback/play affordance, not `Media unavailable`, and remains tappable.
- Failed video media renders unavailable UI and retry callback wiring remains active where supplied.
- Pending video media remains loading/uploading and non-tappable.
- Done video with missing local file does not render fallback/play and does not invoke media tap.
- Focused suites in `exact tests and gates to run` pass according to the touched-file scope.
- No transport, retry, relay, database, simulator, source-report, matrix, or stable closure-reference files are changed by this session.
- `graphify update .` is attempted after implementation; if graph update fails for an environmental reason, record the failure without broadening code scope.

## scope guard

Do not implement:

- Session F simulator acceptance or any simulator scenario discovery.
- Final source-report, matrix, closure-reference, or gate-definition updates unless a new test file truly needs classification.
- Direct retry, duplicate replay repair, media download, local-WiFi fallback, relay durability, or transport changes.
- Camera capture, video compression, stored thumbnail extraction, remote thumbnail upload, or video-player UX changes.
- A new media availability service, database probe, background repair loop, or lifecycle recovery path.
- Product redesign of unavailable/loading/video fallback visuals.

Overengineering triggers:

- Adding repository or DB access to `MediaGridCell`/`MediaThumbnailImage`.
- Adding retry scheduling from a thumbnail widget.
- Replacing the thumbnail cache with a broad media pipeline abstraction.
- Updating group media or feed behavior beyond necessary shared-helper compatibility.

## accepted differences / intentionally out of scope

- Session E host widget evidence can prove the display-policy seam but cannot prove the full A-to-B in-app camera video journey. Session F owns that simulator proof.
- Existing generated-thumbnail success behavior should remain unchanged; this session only changes the fallback when generation fails.
- A done row with an existing local file is treated as displayable even if video playback later fails; playback validation is a separate concern.
- Unsupported video filename extensions should not be made unavailable solely because thumbnail generation cannot derive a frame if the attachment is `done` and the local source file exists. If the existing player cannot open that format, defer to a separate playback capability bug unless current capture/send emits it.
- Final matrix/source-report/closure docs stay unchanged until Session F gathers A-E evidence.

## dependency impact

- Session F depends on Session E to avoid counting thumbnail-generation failure as a true media-unavailable recovery failure in final simulator/manual evidence.
- If Session E discovers that missing-file detection cannot be done inside the widget/helper seam, pause and replan before Session F because the display contract would need a deeper availability source.
- If Session E adds a new test file rather than extending existing files, Session F or the implementing session must update `Test-Flight-Improv/test-gate-definitions.md`/inventory classification as appropriate. Extending existing test files needs no matrix or gate-definition update.

## reviewer pass

- Sufficiency verdict: sufficient as-is.
- Missing files/tests/gates: none structural. The plan names the likely production files, direct media widget regressions, conditional shared-call-site suites, and the named `1to1` gate ownership.
- Stale assumptions: none found. Current code still maps video thumbnail `null` to `widget.error`, and `MediaGridCell` currently supplies the real unavailable placeholder as that error.
- Overengineering: none required by the plan. The preferred typed thumbnail result is small and local; the plan explicitly rejects DB/repository/media-pipeline expansion.
- Decomposition: narrow enough to implement without Session F or deeper transport work.
- Minimum needed for sufficiency: already present. Implementation must preserve the RED-first requirement and the missing-file guard.
- Checklist coverage: every Session E scope item maps to a planned proof in the closure-bar ledger.

## arbiter decision

- Final verdict: execution-ready for Session E only.
- Structural blockers: none.
- Incremental details: implementation may choose the exact local API shape for distinguishing thumbnail-generation failure from missing source file, as long as the RED/GREEN widget tests and missing-file guard remain intact.
- Accepted differences: simulator acceptance, full `1to1` final combined validation if deferred, source-report updates, matrix updates, and stable closure-reference updates remain Session F-owned; Session E host widget evidence is sufficient only for this display-policy slice.
- Stop rule: no new structural blocker was found, so no reviewer/arbiter loop is needed.

## Final Execution Verdict

- Verdict: `accepted_with_explicit_follow_up`.
- Spawned-agent isolation used: no nested Executor/QA child tools were available in this session.
- Local sequential fallback used: yes, per the user's explicit fallback allowance and the skill's bounded fallback path; Executor and QA responsibilities were performed sequentially in this isolated execution pass.
- Files changed for Session E: `lib/shared/widgets/media/media_grid_cell.dart`, `lib/shared/widgets/media/media_thumbnail_image.dart`, `test/shared/widgets/media/media_grid_cell_test.dart`, `test/shared/widgets/media/media_thumbnail_image_test.dart`, and this plan file. `graphify update .` refreshed ignored graph outputs under `graphify-out`. Pre-existing dirty edits in `letter_card.dart`, `letter_card_test.dart`, and upload-pending portions of `media_grid_cell.dart`/`media_grid_cell_test.dart` were preserved and are not claimed as Session E work.
- Tests added or updated: grid-cell regressions for video thumbnail failure fallback, failed-video unavailable retry, missing-file done video, and pending-video loading; thumbnail-helper regressions for null video thumbnail with existing versus missing source files.
- RED evidence captured: primary thumbnail-failure regression first passed due host thumbnail behavior, then failed for the intended `Media unavailable` reason after the deterministic resolver seam; missing-file and pending-video regressions failed before implementation; failed-video retry was already green and remained as a guard.
- Exact tests and gates run: all required plain-name checks, full `media_grid_cell_test.dart`, full `media_thumbnail_image_test.dart`, conditional `media_grid_test.dart`, conditional collapsed feed media-thumbnail plain-name suite, `attachment_preview_strip_test.dart`, recommended `./scripts/run_test_gates.sh 1to1`, `dart format` on touched Dart files, scoped `git diff --check`, and `graphify update .`.
- Blocking issues remaining: none.
- Non-blocking follow-ups deferred: Session F still owns simulator acceptance and final source-report/matrix/closure-reference updates; graph HTML visualization was skipped by graphify because the full graph exceeds the 5000-node viz limit, while `graph.json` and `GRAPH_REPORT.md` were updated.
- Why safe to consider Session E complete: done videos with an existing local source now retain the video fallback/play affordance when thumbnail resolution returns `null`; missing files, failed media, and pending media do not become playable fallbacks; retry remains tied to true retryable media failure policy.
