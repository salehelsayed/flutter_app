# 143 - Outgoing image bubble renders empty while the photo decodes (no loading frame)  (Bug)

Status: IMPLEMENTED host-green (2026-06-22) — uncommitted on `new-feed`. Diff = `media_thumbnail_image.dart` (+10) + 2 media test files. Adversarial review: SHIP / 0 defects.
Spec: free-text intent (no formal spec) — diagnosed 2026-06-22 via `/workflows` (5-agent trace + adversarial synthesis) and re-verified in source. Sibling plans: `141-notif-open-inbox-drain-not-started-tdd-plan.md`, `142-relay-media-push-payload-too-large-tdd-plan.md`.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-22 | Evidence Collector | `/workflows` 5-agent trace; `media_thumbnail_image.dart`, `media_grid_cell.dart`, `media_grid.dart`, `conversation_wired.dart`, `group_conversation_wired.dart`, `letter_card.dart` | RC = `Image.file` has no `frameBuilder`; placeholder unused on image path. Survived refute (3 alternatives rejected) | tier/test/harness facts |
| 2026-06-22 | Planner | `test/shared/widgets/media/*`, `run_host_test_gates.sh`, `run_test_gates.sh`, MediaThumbnailImage callers | widget tier; existing test home; host-all auto-globs test/shared | RED catalog + matrix |
| 2026-06-22 | Reviewer (sufficiency) | this doc | see Reviewer Findings | — |
| 2026-06-22 | Arbiter | this doc | see Arbiter Decision | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-22 | contract extraction (git status --short) | `/tmp/143-dirty-baseline.txt` (154 dirty new-feed files) | the 3 target files NOT in baseline → clean start | scope confirmed | add RED |
| 2026-06-22 | RED tests added | `media_thumbnail_image_test.dart` (TC-01/02/03/05 + `dart:async`), `media_grid_cell_test.dart` (TC-04) | `flutter test …media_thumbnail_image_test.dart` → `+7 -3`; TC-01 fails `Expected: not null / Actual: <null>` (frameBuilder==null); TC-04/TC-05 pass on HEAD (locks) | RED for expected reason | implement |
| 2026-06-22 | implementation | `lib/shared/widgets/media/media_thumbnail_image.dart` `_buildImage` (+10 lines: `frameBuilder`) | single scoped edit; `media_grid_cell.dart` untouched (net) | scoped files only | GREEN |
| 2026-06-22 | direct GREEN | — | `flutter test …/media/{thumbnail,grid_cell,grid}_test.dart` → **+40 All tests passed** | reds now green | mutation |
| 2026-06-22 | mutation-verified | — (temp mutations, all reverted) | A remove frameBuilder→TC-01/02/03 RED; B invert→`+0 -2`; C drop `?? SizedBox.shrink()`→`+0 -1`; D cell `placeholder:null`→TC-04 RED; E break video-wait branch→TC-05 RED | all 5 tests bite | preservation |
| 2026-06-22 | preservation GREEN | — | feed `+214`, 1to1 `+1012`, groups `+507`; conversation_screen `+66`, group_conversation `+62`, letter_card `+81`, attachment_preview_strip `+19`; analyze 0 issues; `git diff --check` clean; diff = exactly 3 files | sentinels green | QA |
| 2026-06-22 | caller audit | — | only 2 MediaThumbnailImage construct sites (`media_grid_cell.dart:228`, `attachment_preview_strip.dart:89`); BOTH pass non-null sized placeholders → no layout-shift / empty-box path in prod | safe | QA |
| 2026-06-22 | QA (independent) | — | adversarial review workflow `wf_0d73cad5-c82` (3 lenses: correctness/callers/test-rigor → 2 raw findings → adversarial verify) → **SHIP, 0 confirmed defects** | none blocking | hardening |
| 2026-06-22 | review-driven hardening (TC-06) | `media_thumbnail_image_test.dart` (+TC-06) | review-noted gap: resolved-video-thumbnail path also runs `_buildImage`→frameBuilder, untested. Added TC-06 (drive frameBuilder on a `video` widget). GREEN; mutation `frameBuilder` image-only→TC-06 RED (`+10 -1`), TC-01/02/03 stay green | locked | full sweep |
| 2026-06-22 | umbrella host-all (full) | — | `host-all --continue-on-failure` ran ALL **869** files. My 3 media files PASS (`PASS: #866/#867/#869`). **9 failures, ALL pre-existing & non-media**: `intro_db_helpers`, `main_invite_sweep_wiring`, `group_conversation_wired` (group-bridge timeouts), `ambient_background`, `orbit_wired`, `inbox_custody_verify`, `group_multi_party_device_criteria` (device-gated), `l10n_integrity`, `go-mknoon/node`. NONE reference `MediaThumbnailImage`/`MediaGridCell` (verified via `rg`); 7/9 match committed HEAD, `orbit_wired` is dirty new-feed work (not mine). `group_conversation_wired` re-confirmed failing with my fix present (group-crypto, not media). | media tests green; 0 new failures attributable to 143 | DONE |

## Source Of Truth
- Spec / intent: inline below (workflow run `wf_8d271a9e-a13`).
- Gate definitions: `scripts/run_test_gates.sh` + `scripts/run_host_test_gates.sh` (script wins over prose).
- Numbering: `Test-Flight-Improv/00-INDEX.md` (real max `139`; `140`=Orbit3, `141`/`142` taken) → this is `143`.

## Session Classification
implementation-ready (single shared-widget edit; deterministic widget host floor is the closure gate — no migration, no device-proof required).

## Exact Problem Statement
When a user sends an image in a 1:1 chat, the outgoing message bubble appears **empty** (a correctly-sized but transparent box, "as if I didn't select/send media") for a few seconds, then the thumbnail pops in — which reads as a failed send.

The optimistic bubble is built **correctly**: the row carries the picked file (`localPath = <picked file>`, `downloadStatus: 'done'`) from the first frame, the box is size-reserved by `AspectRatio(4/3)`, and the `'done'` status passes the render gate immediately. The bubble is empty purely because the image has not **decoded** yet: `MediaThumbnailImage._buildImage` renders a bare `Image.file(...)` with **no `frameBuilder`/`loadingBuilder`**, so Flutter paints transparent inside the sized box while it reads + decodes + resizes the full-resolution photo to `cacheWidth:400`. The widget already *has* a `placeholder` field and `MediaGridCell` already *passes* a sized placeholder for images — it is simply never used on the image-decode path.

What must improve: an outgoing (or any) image must show its **sized loading placeholder during decode**, never a transparent/empty box. The thumbnail may still appear on the first decoded frame, but the gap must no longer look empty/failed.
What must stay unchanged (→ preserved sentinels): the decoded image still renders (image + video), the video thumbnail path (async `VideoThumbnailCache` + placeholder-while-waiting), the `errorBuilder` fallback, and every media-render surface (1:1 / group / feed / posts / attachment preview) that shares this widget.

## Root Cause (verify → refute confirmed)
Survived adversarial refute (workflow `wf_8d271a9e-a13`; key files re-read directly):
- `lib/shared/widgets/media/media_thumbnail_image.dart:106-129` — `_buildImage` returns `Image.file(File(resolvedPath), fit, cacheWidth, cacheHeight, errorBuilder: …)` with **no `frameBuilder`/`loadingBuilder`**. For `mediaType=='image'`, `build()` returns `_buildImage` directly (`:74-75`). → transparent while decoding.
- `media_thumbnail_image.dart:16` — the widget HAS a `Widget? placeholder` field; it is only consulted in the **video** branch (`:80,:91,:94,:96`) and the video `errorBuilder` (`:124`), never for image decode.
- `lib/shared/widgets/media/media_grid_cell.dart:235-237` — for a done image, `MediaThumbnailImage` is built with `placeholder: isVideo ? Container(…) : _buildLoadingPlaceholder()` — i.e. a **non-null sized** placeholder is already supplied for images; the fix only needs `_buildImage` to USE it.
- `media_grid.dart:51-52` — `AspectRatio(4/3)` reserves the box, so the empty window is a sized-but-transparent box (not a collapse).
- Optimistic insert is correct: `conversation_wired.dart:1970-2026` (1:1) and `group_conversation_wired.dart:1861-1876` (group) build media with `localPath=<picked>`, `downloadStatus:'done'` on the FIRST row; the merge guard `conversation_wired.dart:3593-3617` keeps it 'done' across reloads.

Refuted / do-NOT-re-introduce:
- **"upload_pending status gate causes it" (gap == upload time).** REJECTED — that path shows `_buildUploadPendingPlaceholder` = a spinner **with "upload pending" text** (`media_grid_cell.dart:208,252-300`); the user reports an EMPTY box, and the displayed in-memory row stays `'done'` (merge guard). [It is a *separate* latent issue — see Accepted Differences.]
- **"empty/text bubble inserted first, media attached later."** REJECTED — first optimistic row already carries the media.
- **"source-temp → durable-path `existsSync` race."** REJECTED — copy not move; sub-frame; would show the *unavailable* placeholder, not a transparent box, and not for "a few seconds".
- **"async/remote thumbnail generation."** REJECTED for images — only `mediaType=='video'` uses the async `VideoThumbnailCache` FutureBuilder; images render `Image.file` directly.
- **Build-skew.** N/A — `frameBuilder` is verifiably absent on HEAD.

## Real Scope
In scope (one shared widget):
- `lib/shared/widgets/media/media_thumbnail_image.dart` `_buildImage` (`:111`): add `frameBuilder: (context, child, frame, wasSynchronouslyLoaded) => (wasSynchronouslyLoaded || frame != null) ? child : (widget.placeholder ?? const SizedBox.shrink())`. One edit fixes every caller (1:1, group, feed, posts, attachment preview) because they all route image rendering through this widget.

Out of scope (named owners):
- **Upload-pending render gate** (`media_grid_cell.dart:208` shows a spinner instead of the existing local image if you re-enter the chat mid-upload) — different symptom (visible spinner, not empty); owns a **separate follow-up plan** (render the existing local file during upload + a small "sending" chip; treat `upload_pending` as a send-state, not a render gate).
- `precacheImage` and fade-in animation — optional latency/polish enhancements (see Accepted Differences), not required for the empty-box fix.
- Bug 1 (`141`), Bug 2 (`142`).

## Files To Inspect Next
Production: `lib/shared/widgets/media/media_thumbnail_image.dart` (`_buildImage` 106-129; `build` 72-99; `placeholder` field 16).
Direct test: `test/shared/widgets/media/media_thumbnail_image_test.dart` (EXISTS — extend).
Preservation context: `test/shared/widgets/media/media_grid_cell_test.dart`, `media_grid_test.dart`; `media_grid_cell.dart:228-240` (placeholder wiring); callers — `letter_card.dart`, `letter_bubble.dart` (feed), `post_card.dart` (posts), `attachment_preview_strip.dart`, `conversation_wired.dart`, `group_conversation_wired.dart`.

## Existing Tests Covering This Area
- `test/shared/widgets/media/media_thumbnail_image_test.dart` — EXISTS; covers current build branches (image/video/error). **Gap: no test asserts a loading placeholder is shown while an image is undecoded** (today there is none to assert).
- `media_grid_cell_test.dart` / `media_grid_test.dart` — cover the cell/grid render gates + sizing. Preservation sentinels.
- Surface suites (`conversation_screen_test`, `letter_card_*`, `feed_*`, posts) exercise the widget indirectly.
Missing coverage gap: the image-decode loading state (the whole bug) is untested.
Curated arrays: the shared media widget tests are **not** in any `run_test_gates.sh` family array; they run under **`run_host_test_gates.sh host-all`** (which globs `rg --files test -g '*_test.dart'` minus `test/performance/`). Surface suites are in `FEED_TESTS`/`ONE_TO_ONE_TESTS`/`GROUP_TESTS`/`POSTS_TESTS`.

## RED Test Catalog (add BEFORE any production code — INV-RED-FIRST)
1. `test/shared/widgets/media/media_thumbnail_image_test.dart`::`image shows the supplied placeholder while the first frame is undecoded (frame == null)`
   - Tier: widget (`WidgetTester`).
   - Shape/setup: pump `MediaThumbnailImage(mediaType:'image', mediaPath:<any>, placeholder: const SizedBox(key: Key('ph-sentinel')))` inside a `MaterialApp`. `final img = tester.widget<Image>(find.byType(Image));` assert `img.frameBuilder != null`; then invoke `final w = img.frameBuilder!(ctx, const SizedBox(key: Key('child')), null, false);` and assert `w` is the placeholder (its key == `ph-sentinel`), NOT the child and NOT a bare `SizedBox.shrink`.
   - RED on HEAD because: `_buildImage` passes no `frameBuilder` → `img.frameBuilder == null` → the `!= null` assertion (and the invocation) fail.
   - GREEN after fix asserts: while decoding, the sized placeholder is returned.
   - Mutation that re-reds: remove the `frameBuilder` arg → `frameBuilder == null` → RED.
   - Distinct discriminator: assert the returned widget's key is `ph-sentinel` (placeholder) AND NOT `child` — distinguishes "placeholder shown" from "child shown" / "empty".
2. `test/shared/widgets/media/media_thumbnail_image_test.dart`::`image shows the decoded child once a frame is available or synchronously loaded`
   - Tier: widget.
   - Shape/setup: same pump; `img.frameBuilder!(ctx, child, 0, false)` must return `child` (key `child`); and `img.frameBuilder!(ctx, child, null, true)` (wasSynchronouslyLoaded) must also return `child`.
   - RED on HEAD because: `frameBuilder == null` → invocation throws/asserts.
   - GREEN: decoded/sync frames bypass the placeholder and show the image.
   - Mutation that re-reds: invert the condition (return placeholder when `frame != null`) → returns placeholder → RED.
3. `test/shared/widgets/media/media_thumbnail_image_test.dart`::`null placeholder falls back to SizedBox.shrink (no crash)`
   - Tier: widget.
   - Shape/setup: pump with `placeholder: null`; `img.frameBuilder!(ctx, child, null, false)` returns a `SizedBox` (shrink), not a throw.
   - RED on HEAD because: `frameBuilder == null` → invocation throws.
   - GREEN: defensive `?? const SizedBox.shrink()` path.
   - Mutation that re-reds: drop the `?? const SizedBox.shrink()` → null-deref/throws → RED.
4. `test/shared/widgets/media/media_grid_cell_test.dart`::`done image cell passes a non-null sized placeholder to MediaThumbnailImage` (wiring lock — preservation)
   - Tier: widget.
   - Shape/setup: pump `MediaGridCell` with a done image attachment (existing local file fixture); `final mti = tester.widget<MediaThumbnailImage>(find.byType(MediaThumbnailImage));` assert `mti.placeholder != null`.
   - RED on HEAD because: passes today — authored to FAIL if a future change nulls the image placeholder (which would make the §1 fix render `SizedBox.shrink` = empty again).
   - GREEN: the input the fix consumes stays present.
   - Mutation that re-reds: change `media_grid_cell.dart:235-237` to `placeholder: null` for images → `mti.placeholder == null` → RED.
5. `test/shared/widgets/media/media_thumbnail_image_test.dart`::`video thumbnail path unchanged (FutureBuilder placeholder while resolving)` (preservation)
   - Tier: widget.
   - Shape/setup: pump `MediaThumbnailImage(mediaType:'video', videoThumbnailResolver: <slow/never-completing>, placeholder: Key('ph'))`; before the future completes, assert the placeholder is in the tree and no `Image` for a thumbnail yet (the video branch is untouched by the `_buildImage` frameBuilder change except that the *resolved* thumbnail now also gets a placeholder while decoding — assert that does not regress the waiting state).
   - RED on HEAD because: passes today — guards against the frameBuilder edit breaking the video FutureBuilder branch.
   - GREEN: video waiting state unchanged.
   - Mutation that re-reds: if the fix accidentally returns `child` for `frame==null` (over-trims), the resolved-video decode would flash empty — caught by §1/§2; this row locks the FutureBuilder-waiting branch specifically.

## Test Coverage Matrix (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 placeholder while decoding | widget render-state | widget | `media_thumbnail_image_test.dart::image shows the supplied placeholder while the first frame is undecoded (frame == null)` | `frameBuilder == null` (no loading frame) | remove `frameBuilder` → RED | `flutter test test/shared/widgets/media/media_thumbnail_image_test.dart` | **AUTO** under `./scripts/run_host_test_gates.sh host-all` (globs `test/**`; NOT feature/core-host-all, NOT a curated array) |
| TC-02 decoded child shown | widget render-state | widget | `media_thumbnail_image_test.dart::image shows the decoded child once a frame is available or synchronously loaded` | `frameBuilder == null` → throws | invert condition → RED | `flutter test test/shared/widgets/media/media_thumbnail_image_test.dart` | AUTO (host-all) |
| TC-03 null-placeholder safety | defensive | widget | `media_thumbnail_image_test.dart::null placeholder falls back to SizedBox.shrink (no crash)` | `frameBuilder == null` → throws | drop `?? SizedBox.shrink()` → RED | `flutter test test/shared/widgets/media/media_thumbnail_image_test.dart` | AUTO (host-all) |
| TC-04 cell placeholder wiring lock | preservation | widget | `media_grid_cell_test.dart::done image cell passes a non-null sized placeholder to MediaThumbnailImage` | passes today (lock) | `placeholder: null` for image → RED | `flutter test test/shared/widgets/media/media_grid_cell_test.dart` | AUTO (host-all) |
| TC-05 video path unchanged | preservation | widget | `media_thumbnail_image_test.dart::video thumbnail path unchanged (FutureBuilder placeholder while resolving)` | passes today (lock) | break video FutureBuilder branch → RED | `flutter test test/shared/widgets/media/media_thumbnail_image_test.dart` | AUTO (host-all) |
| TC-06 video-thumb decode gets frameBuilder (review-added) | preservation/robustness | widget | `media_thumbnail_image_test.dart::resolved video thumbnail also gets the decode placeholder (frameBuilder is not image-only)` | `frameBuilder == null` → throws | scope `frameBuilder` to `mediaType=='image'` only → TC-06 RED (`+10 -1`), image TCs stay green | `flutter test test/shared/widgets/media/media_thumbnail_image_test.dart` | AUTO (host-all) |

## Invariants (locked by tests)
- INV-1: an image shows its sized placeholder while the first frame is undecoded — never a transparent/empty box. → TC-01.
- INV-2: once a frame is decoded (or synchronously loaded), the image child is shown. → TC-02.
- INV-3: `placeholder == null` degrades to `SizedBox.shrink` without crashing. → TC-03.
- INV-4: `MediaGridCell` keeps passing a non-null sized placeholder for image cells (the input the fix consumes). → TC-04.
- INV-5: the video thumbnail path (async resolve + placeholder-while-waiting) is unchanged. → TC-05.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (tree is mid-`new-feed`). Add RED tests TC-01..TC-03 (+ preservation TC-04/05); `flutter test test/shared/widgets/media/media_thumbnail_image_test.dart` → confirm TC-01..03 RED (`frameBuilder == null`).
2. `media_thumbnail_image.dart` `_buildImage` (`:111`): add the `frameBuilder` returning `widget.placeholder ?? const SizedBox.shrink()` until `wasSynchronouslyLoaded || frame != null`. Single edit; applies to the image branch and the resolved-video-thumbnail branch (both call `_buildImage`). Stop-if: any caller passes a non-sized placeholder that breaks layout → it doesn't (cell passes sized widgets), but TC-04 guards it.
3. Rerun direct → preservation → host-all (below). Stop-if: a surface suite reds → replan, do not hack.

## Risks And Edge Cases
- **GIF images** (`cacheWidth:null` branch) still go through `_buildImage` → they also get the placeholder while decoding (fine/desired). Pinned by TC-01 (mediaType image covers gif since the frameBuilder is unconditional in `_buildImage`).
- **Video resolved-thumbnail decode** now also shows the placeholder briefly (a black `Container` for video) — an improvement, not a regression. Pinned by TC-05.
- **Layout shift:** the placeholder must fit the reserved `AspectRatio` box — it does (cell placeholders are sized, `_buildLoadingPlaceholder` fills). No new layout risk.
- The fix does NOT change *when* the thumbnail appears (decode latency is unchanged) — it only removes the *empty* appearance. Optional precache/fade (Accepted Differences) reduce the latency itself.

## Device/Relay Proof Profile
host-only for closure — the deterministic widget tests (direct `frameBuilder` invocation) fully prove the behavior; no simulator/device/relay needed and no migration. Optional manual visual confirmation (send an image; observe a loading placeholder then the photo, never an empty box) is a nice-to-have, not the gate.

## Acceptance Gates (literal — copy/paste)
```bash
git status --short > /tmp/143-dirty-baseline.txt

# RED (before the edit) — must FAIL because frameBuilder is null
flutter test test/shared/widgets/media/media_thumbnail_image_test.dart \
  --plain-name 'image shows the supplied placeholder while the first frame is undecoded (frame == null)'   # RED

# Direct GREEN (after the edit)
flutter test test/shared/widgets/media/media_thumbnail_image_test.dart

# Preservation sentinels (shared widget + cell + grid)
flutter test test/shared/widgets/media/media_grid_cell_test.dart test/shared/widgets/media/media_grid_test.dart

# Surface suites that render through MediaThumbnailImage (1:1 / group / feed / posts)
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh posts

# Umbrella host gate that auto-globs the new test
./scripts/run_host_test_gates.sh host-all

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: TC-01, TC-02, TC-03 before the edit.
- Pre-existing dirty: large uncommitted `new-feed` tree — compare against `/tmp/143-dirty-baseline.txt`; the only intended change is `media_thumbnail_image.dart` (+ the two media test files).
- Scope drift (BLOCKING): any change to `media_grid_cell.dart` render gates, `conversation_wired`/`group_conversation_wired` optimistic insert, or the upload-pending path = out of scope.

## Done Criteria
- [x] RED added first (TC-01..03), failed because `frameBuilder == null` (`Expected: not null / Actual: <null>`).
- [x] Mutation-verified — 6 mutations: remove frameBuilder (TC-01/02/03), invert condition (TC-01/02), drop `?? SizedBox.shrink()` (TC-03), null cell placeholder (TC-04), break video-wait branch (TC-05), scope frameBuilder image-only (TC-06). Each re-reds its test; all reverted.
- [x] Direct GREEN (41 media-widget tests) + media-widget preservation + 1to1 (`+1012`)/groups (`+507`)/feed (`+214`) gates + media-rendering surface tests (conversation_screen/group_conversation/letter_card/attachment_preview_strip). `posts` family is device-gated integration tests (env: multiple devices, no clean sim) — out of host-only closure profile. `host-all` auto-globs the new tests (#866/867/869); the abort-run died on a PRE-EXISTING unrelated failure — full `--continue-on-failure` sweep run to confirm no new failures.
- [x] No migration (none) — N/A.
- [x] `flutter analyze` 0 new (3 changed items, "No issues found"); `git diff --check` clean; lib/ diff limited to `media_thumbnail_image.dart` (+10) + 2 test files (`media_grid_cell.dart` has zero net change).

## Scope Guard (hard "Do not")
- Do not touch the upload-pending render gate (`media_grid_cell.dart:208`) or the optimistic-insert code — separate follow-up.
- Do not change `cacheWidth`, the video FutureBuilder, or the `errorBuilder` semantics.
- Do not add precache/animation in this plan (Accepted Differences).

## Accepted Differences / Intentionally Out Of Scope
- **`precacheImage` at optimistic insert** (conversation_wired ~`:2021`, group ~`:1903`) and a short `AnimatedOpacity`/`AnimatedSwitcher` fade-in of the decoded child — reduce/soften the decode latency itself. Optional polish; can be a fast follow-up with its own small tests. Not needed to fix the *empty-box* report.
- **Upload-pending-shows-spinner-instead-of-local-image** (re-enter chat mid-upload) — separate plan; render the existing local file during upload.

## Dependency Impact
- None. Pure additive render-robustness on a shared widget; improves every media surface (1:1/group/feed/posts/attachment preview) at once.

## Reviewer Findings
Sufficiency: 5 TCs, each tier+file+name+RED-reason+mutation+gate+registration (zero empty matrix cells). INV-1..INV-5 locked. RED tests are deterministic (direct `frameBuilder` invocation — no real-decode-timing flake). Refuted alternatives (upload_pending / empty-first-insert / existsSync race / async-thumbnail) recorded so they are not re-planned. Preservation sentinels named with literal gates; host-all registration correctly identified (test/shared auto-globs there, not in feature/core-host-all or curated arrays). No migration, no device-proof required — justified because the fix is a pure synchronous render-builder whose behavior is fully host-provable.

## Arbiter Decision
Structural blockers: none. Deferred details: precache/fade + upload_pending gate (separate, named). Verdict: structurally sufficient — hand off to execution.

## Final Execution Verdict
Verdict: **SHIPPED (host-green, closure gate met).** | Files changed: 3 — `lib/shared/widgets/media/media_thumbnail_image.dart` (+10: the `frameBuilder`), `test/shared/widgets/media/media_thumbnail_image_test.dart` (+TC-01/02/03/05/06 + `dart:async`), `test/shared/widgets/media/media_grid_cell_test.dart` (+TC-04). `media_grid_cell.dart` = zero net change (mutations reverted). | Tests run (+counts): media-widget direct **41** green; surface gates feed **+214** / 1to1 **+1012** / groups **+507**; media-rendering surfaces conversation_screen **+66** / group_conversation_screen **+62** / letter_card **+81** / attachment_preview_strip **+19**; full `host-all` **869** files — 3 media files PASS, the 9 failures are all pre-existing non-media `new-feed` branch issues. `flutter analyze` 0 issues; `git diff --check` clean. | Mutation-verified: 6 mutations (remove/invert/drop-fallback/null-cell-placeholder/break-video-wait/scope-image-only) each re-red their TC; all reverted. | Blocking: none. | QA verdict: adversarial review workflow `wf_0d73cad5-c82` → **SHIP, 0 confirmed defects** (3 lenses cleared; 2 raw test-rigor findings refuted; the one legitimate coverage note drove the added TC-06). | Device/relay: not required (host-only closure per profile; `posts` integration + `group_multi_party_device_criteria` are device-gated and out of scope). | Non-blocking follow-ups (owner): precache/fade-in polish; upload-pending render-gate plan (`media_grid_cell.dart:208`).
