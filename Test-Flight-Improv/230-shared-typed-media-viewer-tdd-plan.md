# 230 - Shared Typed Media Viewer And Video Controls

Status: IMPLEMENTED (host-green 2026-07-10; all 8 TC rows GREEN, 7/7 representative mutations re-red, legacy viewer sentinel + group wired preservation gates GREEN, `flutter analyze` clean)
Type: Feature Improvement
Spec: free-text intent — expose safe per-item media actions and modern video controls from one shared viewer without importing any messaging transport
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | `full_screen_image_viewer.dart`, its widget tests and 1:1/group/feed callers, `video_player` dependency, media attachment model/repository, shared library plan 228 | HEAD's path-only viewer cannot identify the current message/attachment or safely expose lane-owned actions. Its player only toggles play/pause and scrubs. A typed, callback-only viewer seam can add metadata, action capability rendering, speed/seek, lifecycle pause, and durable resume without touching transport. | Add typed-viewer and fake-playback RED tests before refactoring callers. |
| 2026-07-10 | Planner | revised plan 228 owner-lane, local-state replay and playback contracts; typed viewer action/resume cases | Action-bearing/resumable items must carry explicit `direct`/`group` ownership, fail closed for `unresolved`, and mirror plan 228's known-duration, unknown-duration, non-video and completion rules. | Strengthen typed identity and resume fixtures before execution. |

## Problem And Evidence

- Behavior to improve: the full-screen viewer must know which received attachment is visible, expose only actions authorized by its caller, show useful metadata, and provide accessible seek/speed/resume controls for video.
- Impact: path-only pages make delete/share/forward/save callbacks ambiguous after a swipe, while the current player offers no explicit elapsed/duration, skip, speed, mute, or restart-safe resume behavior.
- Confirmed current mechanism: `FullScreenImageViewer` accepts `localPath`, `allPaths`, `initialIndex`, and a path-based `videoPageBuilder` at `lib/shared/widgets/media/full_screen_image_viewer.dart:19`; pages are selected only by string path.
- Confirmed current gap: the app bar contains Back and an optional page counter at `lib/shared/widgets/media/full_screen_image_viewer.dart:62`; no action or metadata contract exists.
- Confirmed current mechanism: `_FullScreenVideoPage` constructs `VideoPlayerController.file`, auto-plays the active page, pauses an inactive page, toggles on tap, and uses `VideoProgressIndicator` at `lib/shared/widgets/media/full_screen_image_viewer.dart:133` and `:171`.
- Confirmed current gap: no widget-level playback adapter exists, so speed, seek, lifecycle, and position persistence cannot be tested causally without a plugin texture.
- Existing coverage: `test/shared/widgets/media/full_screen_image_viewer_test.dart` proves video-builder selection, image/GIF branches, and page swiping; group wired tests prove opening the viewer. None fails for current-item identity, action authorization, lifecycle pause, or video resume.
- Missing coverage: action callback identity and owner after swipe, unresolved-item fail-closed behavior, metadata semantics, fake-controller controls, owner-aware persistence throttling/final flush, unknown-duration revalidation, non-video rejection, background/page pause, legacy callers, and LTR/RTL accessibility.
- Refuted findings: the viewer should not decide whether a user may forward/delete/save. Those policies differ by 1:1, discussion, and announcement and belong to plans 231–242.
- Unresolved findings: native picture-in-picture is intentionally excluded from this execution-ready slice because HEAD has no platform/PiP seam; evidence-gated plan 243 owns it rather than blocking typed viewer actions.
- Affected production, test, and gate files: `lib/shared/widgets/media/full_screen_image_viewer.dart`; new typed viewer/action/playback adapter files under `lib/shared/widgets/media/`; viewer localizations; shared viewer tests; existing feed, direct, and group call-site sentinels.

## Scope Contract And Guard

In scope:
- Add immutable `MediaViewerItem`, `MediaViewerKind`, `MediaViewerProtection`, `MediaViewerAction`, and `MediaViewerActionCapabilities` types. Stable attachment/message IDs, explicit `MediaOwnerLane.direct/group` for action-bearing or resumable message media, local path, MIME, byte size, image dimensions or video duration, caption, sender label, timestamp, download/integrity availability, and local protection state travel with each page. Legacy path-only pages remain ownerless and action/resume-ineligible.
- Add optional typed `items`, initial item identity/index, and an async `onAction(item, action)` callback. The viewer renders only capabilities supplied by the lane owner, rejects `unresolved`/missing ownership before dispatch, and rechecks the exact current item and owner immediately before dispatch.
- Keep path-only construction and `FullScreenVideoPageBuilder` working while existing non-message surfaces migrate; typed items are mandatory only for action-bearing lane callers.
- Add an injectable playback adapter around `VideoPlayerController` with play/pause, relative/absolute seek, elapsed/duration, mute, and speeds `0.5x`, `1x`, `1.5x`, `2x`.
- Restore a local position through plan 228's owner-aware repository callback, checkpoint at bounded intervals, flush on pause/page change/dispose, and reset to zero on completion. Known-duration video clamps to `0..duration`; unknown-duration video stores non-negative progress and re-clamps when duration becomes known; non-video and unresolved/ownerless items never read or write resume state.
- Pause on inactive page, app background/inactive/detached, route exit, initialization failure, and disposal; never start a non-current page.

Must preserve:
- Existing image pinch/zoom, GIF decode behavior, page order/counter, error fallback, and injected video builder -> current viewer tests plus TC-230-07.
- Action results are awaited once, surface typed success/cancel/failure state, and never pop or mutate a chat optimistically on failure -> TC-230-02.
- Captions/sender labels and local paths are never logged by the shared viewer -> TC-230-08.
- Playback persistence is local-only and uses the v96 fields from plan 228; it never enters `MediaAttachment.toJson`, and ordinary replay preserves it -> plan 228 TC-228-03/08/10 plus TC-230-05/05B.

Hard `Do not`:
- Do not import `P2PService`, Bridge APIs, direct/group send use cases, repositories that delete messages, relay APIs, or any `go-mknoon` package into shared viewer code.
- Do not infer lane, role, sender direction, view-once state, or authorization from a path/string; the caller supplies explicit capabilities and protection.
- Do not default a missing/unresolved owner to direct/group or call any action/resume mutation for an unresolved item.
- Do not implement save/share/forward/delete/bookmark/storage side effects here; invoke the supplied callback with the exact current item.
- Do not add picture-in-picture, background audio, native platform code, wire fields, message types, migrations, or unbounded media loading.

Deferred / accepted difference:
- Concrete per-lane action policies and side effects -> plans 231–242.
- Native save/share -> plan 227; library/bookmark/resume storage -> plan 228; storage eviction -> plan 229.
- Picture-in-picture is owned by `Test-Flight-Improv/243-native-media-picture-in-picture-tdd-plan.md` after a native/plugin seam is selected; this plan must not imply PiP support.

Dependencies:
- Plan 228 must land first and owns DB v96, explicit media ownership, fail-closed unresolved rows, replay-safe local state, and the bookmark/playback-position repository contract; this plan consumes those APIs without altering schema.
- Plan 227 defines egress result vocabulary, but only lane action coordinators call it.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-230-01 | Swiping changes the typed current item, and every menu label/callback receives that exact attachment/message/owner identity once. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::actions always target the currently visible typed item and owner` | widget host / direct and group typed items from different parents + callback recorder | HEAD compile RED: typed API absent -> action on page 2 records only item 2 with its group owner and counter remains correct | dispatch `items[initialIndex]`, drop/flip owner, or use path lookup -> TC-230-01 red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'actions always target the currently visible typed item and owner'`; AUTO (`host-all`; `test/shared/widgets/**`) |
| TC-230-02 | Unsupported/protected/unavailable/unresolved actions are absent or disabled and cannot dispatch; async cancel/failure leaves the viewer mounted with one truthful result. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::capabilities and ownership fail closed and action outcomes settle once` | widget host / capability and direct/group/unresolved ownership matrix + completer callback | HEAD compile RED -> only allowed controls exist; unresolved/denied taps call zero times; cancel/failure produces no route/message mutation | default a missing capability/owner to allowed/direct or double-submit while pending -> TC-230-02 red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'capabilities and ownership fail closed and action outcomes settle once'`; AUTO (`host-all`; `test/shared/widgets/**`) |
| TC-230-03 | Caption, sender, timestamp, MIME/type, byte size, image dimensions or video duration, and page position describe the current item with localized LTR/RTL semantics and no raw path. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::metadata and action semantics follow current item in LTR and RTL` | widget host / heterogeneous image+video items, localization delegates, semantics tester | HEAD compile RED -> both directions expose the correct current-item metadata/order and no path text/semantic value | reuse prior-page metadata, omit size/dimensions/duration, or expose path as label -> TC-230-03 red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'metadata and action semantics follow current item in LTR and RTL'`; AUTO (`host-all`; `test/shared/widgets/**`) |
| TC-230-04 | Video controls expose play/pause, ±10-second seek with duration clamps, mute, elapsed/duration, and four playback speeds. | `test/shared/widgets/media/media_video_controls_test.dart::seek speed mute and time controls drive one active adapter safely` | widget host / fake playback adapter + fake clock | HEAD compile RED: adapter/controls absent -> exact commands and clamped positions are observed | omit lower/upper clamp, target inactive adapter, or leave speed menu stale -> TC-230-04 red | `flutter test test/shared/widgets/media/media_video_controls_test.dart --plain-name 'seek speed mute and time controls drive one active adapter safely'`; AUTO (`host-all`; `test/shared/widgets/**`) |
| TC-230-05 | Resume position restores through the exact item owner after initialization, checkpoints at a bounded cadence, flushes on pause/exit, and resets after completion. | `test/shared/widgets/media/media_video_resume_test.dart::owner aware resume restores throttles flushes and resets on completion` | widget/application host / fake adapter + strict owner-aware MediaLibraryRepository callback + fake clock | HEAD compile RED -> restore seeks once after init; every read/write carries exact attachment and direct/group owner; tick storm writes bounded count; fresh reopen resumes; completion stores zero | omit/flip owner, write every frame, seek before initialization, or keep completed duration -> TC-230-05 red | `flutter test test/shared/widgets/media/media_video_resume_test.dart --plain-name 'owner aware resume restores throttles flushes and resets on completion'`; AUTO (`host-all`; `test/shared/widgets/**`) |
| TC-230-05B | Unknown-duration video progress remains non-negative and is re-clamped when duration appears; known duration clamps immediately; non-video and unresolved/ownerless items cause zero resume mutations. | `test/shared/widgets/media/media_video_resume_test.dart::resume obeys known unknown nonvideo and unresolved contracts` | widget/application host / fake adapters with null/known duration + strict mutation recorder | HEAD compile RED -> unknown stores non-negative, later metadata update clamps, known overrun clamps, image/unresolved/ownerless records zero repository calls | pass negative/over-duration values, skip later clamp, or write resume for image/unresolved -> TC-230-05B red | `flutter test test/shared/widgets/media/media_video_resume_test.dart --plain-name 'resume obeys known unknown nonvideo and unresolved contracts'`; AUTO (`host-all`; `test/shared/widgets/**`) |
| TC-230-06 | Page change, app background/inactive/detached, route exit, failure, and disposal pause/dispose exactly the owned controller; foreground alone does not auto-play. | `test/shared/widgets/media/media_video_lifecycle_test.dart::only current visible video may play across lifecycle transitions` | widget host / fake lifecycle + multiple fake adapters | HEAD partial: page change pauses but lifecycle seam absent -> all transition counts exact and stale pages never restart | remove lifecycle observer or play every initialized page -> TC-230-06 red | `flutter test test/shared/widgets/media/media_video_lifecycle_test.dart`; AUTO (`host-all`; `test/shared/widgets/**`) |
| TC-230-07 | Existing path-only image, GIF, video-builder, and page-swipe contracts remain supported during caller migration. | `test/shared/widgets/media/full_screen_image_viewer_test.dart` | `GREEN sentinel` / existing widget fixtures | GREEN on HEAD -> remains GREEN after typed API lands | require typed fields for legacy call or route GIF through video -> sentinel red | `flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart`; AUTO (`host-all`; `test/shared/widgets/**`) |
| TC-230-08 | Shared viewer has no transport imports and diagnostic events contain stable redacted IDs/outcomes, not paths or user metadata. | `test/shared/widgets/media/media_viewer_boundary_test.dart::viewer remains callback-only transport-free and diagnostics are redacted` | shell-contract + host unit / source scan + fake event sink | HEAD RED: typed module absent -> forbidden import scan empty and emitted maps exclude path/caption/sender | import a lane use case or log `item.toString()` -> TC-230-08 red | `flutter test test/shared/widgets/media/media_viewer_boundary_test.dart`; AUTO (`host-all`; `test/shared/widgets/**`) |

### Test Notes

- Fake playback adapters prove decisions and lifecycle deterministically. Existing `video_player` integration remains the concrete adapter; this plan does not claim native codec or PiP proof.
- Capability tests assert absence/disabled semantics and callback non-invocation, not only icon presence.
- Resume writes are keyed by `(MediaOwnerLane, attachmentId)`. Missing/unresolved owner or attachment ID disables persistence rather than falling back to path identity.

## Implementation Steps

1. Snapshot `git status --short`; add TC-230-01/02/04/06 and keep the legacy viewer test GREEN before production edits.
2. Add typed item/action/capability contracts and a compatibility constructor normalization layer. Stop-if an action requires importing a lane delivery/delete repository.
3. Extract the playback adapter and controls; add lifecycle ownership and current-page fencing.
4. Wire owner-aware local resume callbacks to plan 228's repository with bounded checkpointing, exact known/unknown-duration behavior, non-video/unresolved rejection, and completion reset; add localized metadata/action semantics.
5. Migrate only action-bearing direct/group callers in their owning plans, then run focused tests, preservation gates, mutation re-reds, and hygiene.

## Risks And Blind Spots

- Wrong-item destructive action after swipe -> TC-230-01 binds stable current identity at dispatch time.
- Authorization accidentally inferred in shared UI -> TC-230-02/08 make capabilities fail closed and transport-free.
- Playback controller leaks/races -> TC-230-06 counts ownership across all lifecycle exits.
- Lifecycle / derived-state durability: TC-230-05/05B reconstruct the viewer/repository, validate throttled final state, and re-clamp when duration arrives.
- Sibling-surface consistency: TC-230-07 preserves feed and legacy callers while lane plans migrate explicitly.
- Destructive-action side effects: none occur in this plan; TC-230-02 ensures the callback boundary cannot double-dispatch.
- Invariant re-verification under new transitions: every page/lifecycle transition rechecks current item/owner/controller before play or dispatch in TC-230-01/05/06; duration discovery revalidates persisted position in TC-230-05B.

## Acceptance Gates

```bash
git status --short

# First causal RED; expect non-zero because typed viewer items/actions/owners are absent
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'actions always target the currently visible typed item and owner'

# Focused GREEN
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart
flutter test test/shared/widgets/media/media_video_controls_test.dart
flutter test test/shared/widgets/media/media_video_resume_test.dart
flutter test test/shared/widgets/media/media_video_lifecycle_test.dart
flutter test test/shared/widgets/media/media_viewer_boundary_test.dart

# Preservation and owning host gates
flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'incoming group image refreshes on open recipient route after background download without reopen'
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_host_test_gates.sh host-all --list

flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-230-01 compile-fails because `MediaViewerItem`, explicit owner identity, and action callbacks do not exist.
- Green sentinel: current path-only image/GIF/video-builder/page-swipe tests remain GREEN.
- Pre-existing dirty tree / known failure: record at execution start; do not absorb unrelated changes.
- Environment blocker: none for this host slice; no native PiP/codec claim is made.
- Scope drift: any message payload, send/delete use case, platform native code, relay, Bridge, or Go change blocks this plan.

- [x] Every behavior has a named causal test or explicit preservation sentinel (TC-230-01..08 + legacy sentinel TC-230-07).
- [x] Current-item/owner identity, fail-closed unresolved behavior, known/unknown-duration playback, non-video rejection, durability, lifecycle, and accessibility pass (79/79 media-dir tests GREEN).
- [x] Representative identity/capability/clamp/lifecycle mutations re-red — 7/7 (dispatch-initial-item, ignore-eligibility, omit-seek-clamp, drop-resume-throttle, no-op-lifecycle, log-item.toString, forbidden-import).
- [x] Existing viewer and feature host gates pass with semantic outcomes (full_screen_image_viewer_test GREEN; group_conversation_wired background-download preservation GREEN; host-all discovers all 5 new test files).
- [x] `flutter analyze` has no new issues (touched lib/test/l10n all clean); `git diff --check` is clean.
- [x] Scope Contract And Guard is respected (callback-only, transport-free by TC-230-08 import scan; no callers migrated per Handoff; no wire/DB/native/PiP change; consumes plan 228 v96 state via a `MediaViewerResumeStore` callback, never a repository import).

## Handoff

- First causal RED command: `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'actions always target the currently visible typed item and owner'`.
- Preservation command: `flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart`.
- Manual registration: none; shared widget/application tests are auto-globbed by `host-all` (not `feature-host-all`). The literal `host-all --list` gate verifies discovery while focused commands execute the files.
- Migration: none; consumes DB v96 state from plan 228.
- Boundary closure: host fake-controller and widget proof; no transport, native codec, or picture-in-picture claim.
- Unresolved evidence: native picture-in-picture requires the platform seam decision and device proof in plan 243.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
| 2026-07-10 | contracts + adapter + resume + controls + viewer | `lib/shared/widgets/media/media_viewer_item.dart` (new), `media_playback_adapter.dart` (new), `media_video_resume_controller.dart` (new), `media_video_controls.dart` (new), `full_screen_typed_media_viewer.dart` (new) | `flutter analyze lib/shared/widgets/media/` -> No issues | typed `MediaViewerItem`/capabilities/protection; injectable `MediaPlaybackAdapter` (extends-inherited `seekBy` clamp so the fake exercises it); `MediaViewerResumeStore` callback (no repository import); owner-aware resume w/ throttle + `isCompleted`-gated completion-vs-overrun; per-page `WidgetsBindingObserver` lifecycle fencing | keep legacy `FullScreenImageViewer` untouched (TC-230-07); no callers migrated (owned by 231-242) | l10n + tests |
| 2026-07-10 | l10n | `app_en/de/ar.arb` (+11 keys each), regenerated `app_localizations*.dart` | `flutter gen-l10n` exit 0; `l10n_integrity_test` GREEN | action + control tooltips localized; metadata rendered as computed values (no hardcoded-literal gate hits) | l10n arb/generated diffs are additive media_viewer-only (verified +11/-0, no contamination) | tests |
| 2026-07-10 | RED tests + GREEN | 6 new test files under `test/shared/widgets/media/` (5 test + `fake_media_playback_adapter.dart` helper) | `flutter test test/shared/widgets/media/` -> 79/79 GREEN | TC-230-01..08 GREEN; fake adapter extends the real interface so the seek-clamp mutation re-reds through it; RTL PageView reverse handled | mutation re-reds | gates |
| 2026-07-10 | mutations + gates | prod files (string-swap mutations, reverted) | 7/7 mutations RED-then-restored; `git diff --check` clean; `host-all --list` discovers all 5 files | identity/capability/clamp/throttle/lifecycle/redaction/import all causal | never `git checkout` on the shared dirty tree — inverse string swaps only | COMMIT |
