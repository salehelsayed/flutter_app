# 200 - App-wide avatar aspect-ratio stretch (exact-policy square decode + never-cropped uploads)  (Bug)

Status: IMPLEMENTED + COMMITTED (host-green 2026-07-04, branch new-orbit)
Spec: free-text intent (no formal spec) — user report 2026-07-03 ("group profile picture displayed stretched; check every place images/avatars are displayed"), root-caused + adversarially verified in workflow `wf_0396f589-131` (B1, verdict **confirmed**); plan grounding `wf_0e48db0b-199` (G200). Dossier: memory `project_orbit_seven_bug_debug_2026_07_03.md`.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-03 | Evidence Collector (wf_0396f589 B1 + verify) | group_avatar.dart, user_avatar.dart, profile_avatar_widget.dart, share_target_picker_screen.dart, image_processor.dart, avatar_normalization_helper.dart, group_avatar_storage.dart, SDK image_provider.dart, 9e17f597 diff | Root cause two-half (render exact-policy + upload never-crops), CONFIRMED; render-side fix mandatory (fallback commits raw bytes) | ground test mechanics |
| 2026-07-04 | Evidence Collector (wf_0e48db0b G200) | all lock tests, run_test_gates.sh, pubspec, flutter_image_compress pkg source, SDK 3.41.4 | ResizeImage.policy PUBLIC; package:image ABSENT (new dep); existing locks stay green under fit (MUST extend); 4-widget inventory still exhaustive | write plan |
| 2026-07-04 | Planner (this session) | grounding dossiers | crop-after-compress inside processAvatar; shared provider helper in lib/shared/widgets/media/ | reviewer pass |
| 2026-07-04 | Reviewer (sufficiency) | | (pending) | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-04 | baseline (HEAD eeaff05f) | — | other-session sweep: groups 1022 GREEN, feed 285 GREEN, feature-host-all PASS | clean slate (avatar files unmodified) | add dep |
| 2026-07-04 | dep add | pubspec.yaml/.lock | `image: ^4.8.0` → direct main (image-4.8.0 in cache; pub get offline) | infra only | RED |
| 2026-07-04 | RED tests added | group_avatar_test, user_avatar_test, profile_avatar_widget_test, share_target_picker_screen_test, NEW avatar_normalization_helper_test, image_processor_test, group_info_wired_test | 7 render RED (policy exact≠fit; TC-200-07 ratio 1.0≠2.0); TC-200-08 (compresspath≠NEW), TC-200-11 (1024≠512), TC-200-12 (preview 1024≠512); guards 09/10/15 green | RED for documented reasons | impl |
| 2026-07-04 | implementation | NEW avatar_image_provider.dart; group_avatar/user_avatar/profile_avatar/share_target (render→fit); image_processor.dart (crop) | **ADDED GUARD**: crop also pass-through when `width==height` (square) — a defensive correctness/quality improvement (never re-encode an already-square avatar → no quality loss / wasted CPU / extra temp file). Empirically NOT required to keep existing suites green: the byte-asserted fixtures (pass_post_along oversized-omit, post_pass smoke) are UNDECODABLE minimal PNGs → protected by the undecodable guard; the one decodable 1×1 fixture (group_info_wired `_tinyPngBytes`) is not byte-asserted. Locked by strengthened TC-200-09 (solidJpeg 512×512, genuinely decodable). **DEVIATION**: crop runs INLINE not `compute()` (isolate-spawn variance would flake existing tiny-fixture pick tests on this contended host; avatar pick is one-shot spinner-guarded) | scoped files only | GREEN |
| 2026-07-04 | direct GREEN | — | 6 focused files: 70/70 pass; TC-200-12 wired green (small 120×60 fixture so inline crop fits the 50ms pick pump window) | reds now green | sentinels |
| 2026-07-04 | preservation GREEN | — | collision-risk suites 48/48: pass_post_along + post_pass_media_avatar_smoke + group_avatar_storage + download_profile_picture (square-guard empirically confirmed) | sentinels green | gates |
| 2026-07-04 | mutation QA | — | fit→exact → 7 render red; crop-disable → TC-200-08/11/12 red; both restored | mutation-verified | gates |
| 2026-07-04 | named gates | — | `groups` 1022 pass +2 known ML-004/GM-036 flakes (pass standalone 91/91); analyze 0 findings in changed files (2 pre-existing errors in untouched integration_test/); `git diff --check` clean; feature-host-all + core-host-all RUNNING | groups green | host globs + graph refresh |

## Source Of Truth
- Spec / intent: inline below (user report + verified dossier)
- Gate definitions: scripts/run_test_gates.sh (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh (not needed — no integration_test/ additions)
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready

## Exact Problem Statement
When a group admin changes the group picture — or any contact has a non-square profile photo — the image renders **stretched** (squashed to a square) everywhere avatars appear: group chat app bar (`group_conversation_screen.dart:309`), group info header (`:198`), groups list rows (`group_card.dart:52`), Orbit ring nodes (`orbital_visualization.dart:313` groups, `:169` centre, `orbital_avatar.dart:132` friends), 1:1 conversation header, message rows, member lists, contact picker, settings profile, QR-scan result, feed/post cards — 36 `UserAvatar(` call sites plus all `GroupAvatar`/`ProfileAvatarWidget` sites, and the share-sheet preview thumb on arbitrary shared images.

What must improve: avatars render as an **aspect-preserving cover-crop inside their clip** for any source aspect ratio, including non-square files already distributed to devices; newly picked avatars are additionally committed as true 512×512 squares so the canonical contract becomes honest.
What must stay unchanged (→ preserved-green sentinels): the 156 QW-4 bounded-decode memory win (no full-res decodes); GIF exemption (file-branch GIFs bypass `ResizeImage` — `group_avatar_test.dart:84-112`, share test L128-138); ValueKey reload contracts (`user_avatar_test.dart:29-51`); `errorBuilder` fallbacks; share test's inner-`FileImage` cast (`share_target_picker_screen_test.dart:122-125`); `prepareAvatar` StateError/null-compress contracts (`image_processor_test.dart:238-256`); upload mime `image/jpeg` + allowedPeers payload locks (`group_avatar_storage_test.dart:158-188`); NORMALIZATION_FALLBACK raw-bytes commit locks (`:190-240`).

## Root Cause (verify → refute confirmed — wf_0396f589 B1, verdict confirmed)
**Render half (the stretch):** commit `9e17f597` (156 QW-4) added BOTH `cacheWidth` **and** `cacheHeight` `= round(size*dpr)` to every avatar `Image.memory`/`Image.file`:
- `lib/features/groups/presentation/widgets/group_avatar.dart:115-116` (memory) + `:126-129` (file, gif-exempt)
- `lib/features/home/presentation/widgets/user_avatar.dart:131-132` (memory) + `:161-164` (file, gif-exempt)
- `lib/features/home/presentation/widgets/profile_avatar_widget.dart:84-85` (memory only)
- `lib/features/share/presentation/screens/share_target_picker_screen.dart:223-224` (144×144, gif-exempt)

With both dims set, Flutter wraps the provider in `ResizeImage` with the **default `ResizeImagePolicy.exact`** (SDK `image_provider.dart:1266`; policy field public at `:1286`; Flutter 3.41.4), documented as decoding to the exact target "regardless of … intrinsic aspect ratio. This case is similar to `BoxFit.fill`" (`:838-841`, decode branch `:1364-1377`). The bitmap is squashed square **at decode time**; `BoxFit.cover` then paints the pre-distorted square 1:1. Square sources are unaffected — matching the symptom.

**Upload half (why non-square files exist):** `ImageProcessor.processAvatar` (`lib/core/media/image_processor.dart:67-79`) claims "always 512x512" (`:64` — FALSE) but `flutter_image_compress` `minWidth`/`minHeight` scale **proportionally** (verified in plugin native source; no crop API exists in flutter_image_compress 2.4.0). No `ImageCropper`/crop step exists anywhere in `lib/`. Non-square picks are committed, uploaded (`group_avatar_storage.dart:84/166`), re-normalized aspect-preserving on receive (`:235`), and the receive-side `NORMALIZATION_FALLBACK` (`:240-267`) commits **raw** downloaded bytes — so the render-side fix is **mandatory**: it is the only guard for files already on members' disks and for fallback-committed bytes; the upload-side crop alone cannot heal them.

Refuted / do-NOT-re-introduce:
- "BoxFit is wrong at some render site" — REFUTED: every avatar site is `BoxFit.cover` inside a clip; the distortion happens at decode, not paint.
- "Some other both-dims site exists" — REFUTED: lib-wide `cacheHeight` grep confirms the 4 widgets above are exhaustive; `media_thumbnail_image.dart:15/27/115` accepts `cacheHeight` but **no caller passes it** (`attachment_preview_strip.dart:168` and `media_grid_cell.dart:234` pass `cacheWidth` only — single-dim decode preserves aspect). Do NOT "fix" MediaThumbnailImage.
- "Upload-side crop is sufficient alone" — REFUTED: NORMALIZATION_FALLBACK + already-distributed files + old-build senders.

## Real Scope
In scope:
1. **(A — render, mandatory)** Shared aspect-safe provider helper (new `lib/shared/widgets/media/avatar_image_provider.dart`): `ImageProvider avatarResizedProvider(ImageProvider inner, int cacheSize)` → `ResizeImage(inner, width: cacheSize, height: cacheSize, policy: ResizeImagePolicy.fit)`. All 4 widgets switch from the `Image.memory/Image.file` cache params to `Image(image: avatarResizedProvider(MemoryImage(...)/FileImage(...), cacheSize), ...)`, manually carrying `key:`, `fit: BoxFit.cover`, `width/height`, `gaplessPlayback: false`, `errorBuilder:`, and `filterQuality:` where present (`share_target_picker_screen.dart:225` FilterQuality.low) — GIF file-branch exemption stays at call sites (raw `FileImage`, no wrap).
2. **(B — lock extension, mandatory)** Extend TC-06/TC-07/TC-08/TC-08b/share-2b to assert `resize.policy == ResizeImagePolicy.fit` (without this, the policy fix is mutation-invisible: width/height asserts are identical under fit).
3. **(C — upload, companion)** Square center-crop inside `ImageProcessor.processAvatar` AFTER the existing successful compress: decode compressed file with **`package:image`** (new direct dependency; pure Dart), `copyCrop` centered square (512×512 given the ≥512 min-dims compress output), `encodeJpg` quality 85, write a **NEW** file, return its path. **Crop is strictly best-effort (reviewer-caught BLOCKING contract, fixed here):** if the compress output file is MISSING or its bytes are UNDECODABLE, skip the crop entirely and return the compress result unchanged — several existing suites drive processAvatar with fake compressors that return unwritten paths (`image_processor_test.dart:191-216`) or junk bytes asserted byte-identical downstream (`group_avatar_storage_test.dart:132-156` normalized-commit L154, `pass_post_along_use_case_test.dart:429-441` payload bytes); a crop that throws or re-encodes there reds them all. Compress-null / non-processable early-return paths unchanged (no crop on failure — preserves `image_processor_test.dart:238` and the `prepareAvatar` StateError contract). `compute()` offload for the decode/crop (new pattern, noted).
4. Correct the `:64` doc comment to the now-true contract.

Out of scope (owners named):
- MediaThumbnailImage `policy: fit` pass-through hardening (aspect-safe today; separate hygiene follow-up).
- Full-screen viewer / media grid (already aspect-safe: `BoxFit.contain`, single-dim).
- Re-uploading/re-crushing avatars already on disk (render-side fit heals display; no data migration).
- Group avatar same-path staleness (`group_avatar.dart:44-49` resolver; adjacent finding, separate follow-up).
- iOS/Android native share-extension thumbnails (Flutter-side only here).

## Files To Inspect Next
Production: lib/features/groups/presentation/widgets/group_avatar.dart; lib/features/home/presentation/widgets/user_avatar.dart; lib/features/home/presentation/widgets/profile_avatar_widget.dart; lib/features/share/presentation/screens/share_target_picker_screen.dart; lib/core/media/image_processor.dart; lib/features/settings/application/helpers/avatar_normalization_helper.dart; NEW lib/shared/widgets/media/avatar_image_provider.dart; pubspec.yaml (add `image:`).
Direct tests: test/features/groups/presentation/widgets/group_avatar_test.dart; test/features/home/presentation/widgets/user_avatar_test.dart; test/features/home/presentation/widgets/profile_avatar_widget_test.dart; test/features/share/presentation/share_target_picker_screen_test.dart; test/core/media/image_processor_test.dart; NEW test/features/settings/application/helpers/avatar_normalization_helper_test.dart; test/features/groups/presentation/group_info_wired_test.dart (funnel).
Dependency-only context: group_avatar_storage.dart (+test), download_profile_picture_use_case.dart (+test), repost_avatar_snapshot_preparer.dart, pass_post_along_use_case_test.dart (512-min lock), settings_wired.dart:433-480, first_time_experience_wired.dart:479-514, upload_profile_picture_use_case.dart:70-97, lib/shared/widgets/media/media_thumbnail_image.dart (precedent, do not modify).

## Existing Tests Covering This Area
- group_avatar_test.dart — TC-08 memory (L30-52) + file (L54-82) cacheW/H==round(size*dpr); GIF exempt (L84-112). **In GROUP_TESTS** (run_test_gates.sh:230, "156 QW-4" comment :229). Extraction pattern: `tester.widget<Image>(find.byType(Image)).image as ResizeImage`.
- user_avatar_test.dart — ValueKey reload (L29-51), path-resolve (L60-104), TC-06 (L109-126), TC-07 (L128-153). Auto-glob only.
- profile_avatar_widget_test.dart — delegation/camera (L12-51), TC-08b (L56-73). Auto-glob only.
- share_target_picker_screen_test.dart — 2b thumb 144×144 + inner FileImage cast (L110-127); GIF exempt (L128-138). Auto-glob only.
- image_processor_test.dart — processAvatar args probe (L190-256 via injectable `CompressFileFn`); `.gif` non-processable (L31). Auto-glob (core-host-all).
- group_avatar_storage_test.dart — normalized-commit, upload payload, NORMALIZATION_FALLBACK raw-commit + signature-reject (L132-240+). Auto-glob only.
- profile_picture_flow_test.dart (4a-4g, in **OPTIONAL_MANUAL_TESTS** :311), download_profile_picture_use_case_test.dart, pass_post_along_use_case_test.dart (512-min probe lock L435-436), post_pass_media_avatar_smoke_test.dart (real 1×1 PNG fixture L728-797). Auto-glob only.

Missing coverage gaps: no test decodes an image and asserts dimensions/aspect (the bug class is fully unlocked — bug shipped with all locks green); no dedicated AvatarNormalizationHelper test file; nothing locks processAvatar output pixels (the ":64" lie was uncatchable); settings/FTE pick flows have zero avatar coverage (pickers constructed inline — not fakeable at widget level).
Already in curated family arrays?: group_avatar_test (GROUP_TESTS :230), group_info_wired_test (GROUP_TESTS :226), profile_picture_flow_test (OPTIONAL_MANUAL_TESTS :311); all others auto-glob only.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
1. `test/features/groups/presentation/widgets/group_avatar_test.dart` :: extend TC-08 memory + TC-08 file → `'…and uses ResizeImagePolicy.fit (TC-200-01/02)'`
   - Tier: widget (host). Shape: existing TC-08 pump (dpr seam `tester.view.devicePixelRatio=3.0` + reset; file branch: tempDir write + `UserAvatar.setDocumentsDir` + `tester.runAsync` 50ms + pump). New assert: `expect((image.image as ResizeImage).policy, ResizeImagePolicy.fit)`; keep width/height==144/80 asserts (max-bounds under fit).
   - RED on HEAD: `group_avatar.dart:115-116/126-129` use cache params → default `exact` → policy assert fails.
   - GREEN after fix: helper-wrapped provider carries `policy: fit`.
   - Mutation that re-reds: revert `policy: ResizeImagePolicy.fit` to default (or back to cache params) → TC-200-01/02 red. (Width/height asserts alone would NOT re-red — this is the load-bearing extension.)
   - ALSO assert `expect(image.errorBuilder, isNotNull)` here AND in rows 2-4. **Reviewer-caught (BLOCKING, fixed here):** NO errorBuilder assertion exists anywhere in the avatar/share test dirs today — the "errorBuilder fallbacks stay unchanged" claim was a phantom sentinel over the exact constructions Step 4 rewrites (`group_avatar.dart:117/130`, `user_avatar.dart:133/165`, `share_target_picker_screen.dart:226`). This new assert IS the lock; mutation: drop `errorBuilder` in the rewrite → red.
2. `test/features/home/presentation/widgets/user_avatar_test.dart` :: extend TC-06/TC-07 → `policy == fit` + inner provider type preserved (`resize.imageProvider is MemoryImage` / `is FileImage`) (TC-200-03/04)
   - RED on HEAD: `user_avatar.dart:131-132/161-164` default exact. Mutation: revert helper call in either branch → red.
3. `test/features/home/presentation/widgets/profile_avatar_widget_test.dart` :: extend TC-08b → `policy == fit` (TC-200-05)
   - RED on HEAD: `profile_avatar_widget.dart:84-85`. Mutation: revert → red.
4. `test/features/share/presentation/share_target_picker_screen_test.dart` :: extend 2b → `policy == fit`, keep 144/144 + `(resize.imageProvider as FileImage).file.path` cast; ADD `filterQuality == FilterQuality.low` (`:225` — reviewer-caught carry-list omission) + `errorBuilder != null` (TC-200-06)
   - RED on HEAD: `share_target_picker_screen.dart:223-224`. Mutation: revert → red. GIF test (L128) must stay `isA<FileImage>` — unchanged.
5. `test/features/groups/presentation/widgets/group_avatar_test.dart` :: `'oversized non-square avatar bytes decode with preserved aspect ratio (TC-200-07)'`
   - Tier: widget (host), NEW pattern (behavioral proof of the fix, not just structure). Shape: real **288×144** PNG bytes — the fixture MUST exceed the 144×144 decode target box in BOTH dims. **Reviewer-caught (both reviewers, BLOCKING, fixed here):** `ResizeImage` defaults `allowUpscaling: false` and the decode branches CLAMP target dims to intrinsic dims (SDK `image_provider.dart:1368-1375`, doc `:849-853`) — a small 4×2 fixture decodes 4×2 (ratio preserved) and the test is GREEN on HEAD. Do NOT shrink the fixture. Generate inside `tester.runAsync` via `ui.PictureRecorder`→`toImage(288,144)`→`toByteData(png)` (hardcoded-fixture precedent: `test/features/posts/improvement/post_pass_media_avatar_smoke_test.dart:728+`). Pump GroupAvatar(memory branch, size 48, dpr 3.0 → target 144); extract `provider = tester.widget<Image>(find.byType(Image)).image`; inside `tester.runAsync`: `provider.resolve(const ImageConfiguration())` + `ImageStreamListener` completer; assert `img.width / img.height == 2.0` (±rounding).
   - RED on HEAD: exact policy decodes the 288×144 source to 144×144 → ratio 1.0.
   - GREEN: fit policy decodes 144×72 → ratio 2.0 (SDK `:1378`).
   - Mutation: flip helper policy `fit`→`exact` → red (the true mutation-revert for the whole render half). Note: real decode MUST run inside `runAsync` (testWidgets sync-IO rule, project memory).
6. NEW `test/features/settings/application/helpers/avatar_normalization_helper_test.dart` :: `'prepareAvatar commits a 512x512 square jpeg in a NEW file for a non-square input (TC-200-08)'` + `'square input stays square (TC-200-09)'` + `'compress-null path still returns input path and skips crop (TC-200-10)'` + `'missing/undecodable compress output passes through unchanged — crop skipped (TC-200-15)'`
   - Tier: unit/application (host, plain `test()`). Shape: real ImageProcessor with REAL compressor replaced by fake `CompressFileFn` that emits a known non-square jpg (e.g. writes a real 1024×512 image via package:image in setUp) — then crop runs on that output; decode result with `package:image` `decodeImage` and assert `width == height == 512` AND `outputPath != inputPath` AND `outputPath != compressOutputPath`; TC-200-10: fake compressor returns null → `processAvatar` returns inputPath (existing contract, `image_processor_test.dart:238`) and helper throws StateError (existing `avatar_normalization_helper.dart:25-29`).
   - TC-200-15 mechanics: (a) fake compressor returns a path WITHOUT writing a file (the `image_processor_test.dart:191-216` fixture shape) → processAvatar returns that path unchanged, no throw; (b) fake compressor writes undecodable junk bytes (the `group_avatar_storage_test.dart` 0xCA 0xFE 0xBA 0xBE shape) → returns the compress path with bytes byte-identical. This is the CONTRACT GUARD that keeps every fake-compressor-based lock green (image_processor probes; group_avatar_storage normalized-commit + fallback; pass_post_along payload bytes `:429-441`). Green-by-construction pre-fix (no crop on HEAD) — explicit INV-RED-FIRST exemption, mutation-backed.
   - RED on HEAD: no crop exists — width stays 1024 ≠ 512 height (TC-200-08).
   - Mutation: remove the crop step → TC-200-08 red; make crop overwrite the compress file in place → "NEW file" assert red; crop-before-compress reorder → `outputPath != compressOutputPath` identity assert red (reviewer-corrected: the reorder does NOT change the 512 probe args, so THIS row catches it, not TC-200-11); make crop throw/re-encode on missing/undecodable input → TC-200-15 red.
7. `test/core/media/image_processor_test.dart` :: extend processAvatar group → crop-step probe: compressor receives minWidth/minHeight **512 unchanged**; output is square when compress output is decodable (TC-200-11)
   - RED shape: green-by-construction pre-fix for the 512 args (existing L191 lock); the added "output is square" assert is red on HEAD (same mechanism as row 6, at the processor tier — the fake compressor for THIS assert must WRITE a real decodable non-square image; the existing unwritten-path fixture is reused only for TC-200-15's pass-through leg). Mutation: delete crop → square assert red. (Reviewer-corrected: a crop-before-compress reorder does NOT change the 512 probe args — that mutation belongs to TC-200-08's path-identity assert.)
8. `test/features/groups/presentation/group_info_wired_test.dart` :: `'admin picks a non-square photo → editor preview + committed canonical avatar are square (TC-200-12)'`
   - Tier: wired (host). Shape: existing FakeMediaPicker + injectable `widget.imageProcessor` seam (`group_info_wired_test.dart:3129-3171`; production: `lib/features/groups/presentation/screens/group_info_wired.dart` — `_pickAvatar :2462`, seam `:2474` — reviewer-corrected path+lines); picker returns a real non-square jpg; assert preview `Image.memory` bytes decode square (runAsync) — funnel proof that the pick flow routes through the cropping normalizer.
   - RED on HEAD: preview bytes keep source aspect. Mutation: bypass normalizer in `_pickAvatar` → red.
9. Preservation sentinels (existing, must stay green — no edits except where named): GIF exemptions (group_avatar_test L84-112, share L128-138); ValueKey reload (user_avatar_test L29-51); NORMALIZATION_FALLBACK locks (group_avatar_storage_test L190-240); pass_post_along 512-min probe (L435-436 — stays because crop is after compress); upload payload mime `image/jpeg` (group_avatar_storage_test L158-188 — crop emits jpeg); profile_picture_flow_test 4a-4g.

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-200-01 | UI decode policy (group, memory) | widget | group_avatar_test.dart::TC-08-ext memory policy fit | default exact policy | drop `policy: fit` param | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS (:230) + AUTO (glob) |
| TC-200-02 | UI decode policy (group, file) | widget | group_avatar_test.dart::TC-08-ext file policy fit | default exact policy | drop helper on file branch | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS + AUTO |
| TC-200-03 | UI decode policy (user, memory) | widget | user_avatar_test.dart::TC-06-ext policy fit + MemoryImage inner | default exact | drop helper (memory) | `flutter test test/features/home/presentation/widgets/user_avatar_test.dart` | AUTO (feature-host-all) |
| TC-200-04 | UI decode policy (user, file) | widget | user_avatar_test.dart::TC-07-ext policy fit + FileImage inner | default exact | drop helper (file) | same | AUTO |
| TC-200-05 | UI decode policy (profile) | widget | profile_avatar_widget_test.dart::TC-08b-ext policy fit | default exact | drop helper | `flutter test test/features/home/presentation/widgets/profile_avatar_widget_test.dart` | AUTO |
| TC-200-06 | UI decode policy (share thumb) | widget | share_target_picker_screen_test.dart::2b-ext policy fit | default exact | drop helper | `flutter test test/features/share/presentation/share_target_picker_screen_test.dart` | AUTO |
| TC-200-07 | decode-aspect behavioral proof | widget (runAsync decode) | group_avatar_test.dart::oversized non-square decodes preserved-aspect | exact+intrinsic-clamp → 144×144 (ratio 1.0) from the OVERSIZED 288×144 fixture (small fixtures are green on HEAD — clamp) | policy fit→exact in helper | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS + AUTO |
| TC-200-08 | upload crop contract | unit/application | avatar_normalization_helper_test.dart::non-square → 512×512 NEW file | no crop step exists | delete crop step | `flutter test test/features/settings/application/helpers/avatar_normalization_helper_test.dart` | AUTO (feature-host-all) — NEW file |
| TC-200-09 | crop idempotence (square in) | unit/application | avatar_normalization_helper_test.dart::square stays square | (green-by-design guard; red if crop distorts) | crop emits non-square → red (centering NOT pixel-locked — Accepted Difference) | same | AUTO |
| TC-200-10 | failure-contract preservation | unit/application | avatar_normalization_helper_test.dart::compress-null skips crop, StateError | square assert absent on HEAD; contract row guards fix | crop runs on null-compress path | same | AUTO |
| TC-200-11 | crop square-output + 512-args lock | unit | image_processor_test.dart::processAvatar square output (decodable fixture) | output-square assert red | delete crop step | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (core/**) |
| TC-200-15 | crop pass-through contract (missing/undecodable compress output) | unit/application | avatar_normalization_helper_test.dart + image_processor_test.dart::TC-200-15 pass-through legs | green-by-construction pre-fix (contract guard, INV-RED-FIRST exemption, mutation-backed) | make crop throw/re-encode on undecodable or missing input | `./scripts/run_host_test_gates.sh core-host-all` + feature-host-all | AUTO |
| TC-200-12 | pick-funnel wiring (wired) | wired widget | group_info_wired_test.dart::non-square pick → square preview | preview keeps source aspect | bypass normalizer in `_pickAvatar` | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS (:226) |
| TC-200-13 | GIF exemption preserved | widget | group_avatar_test.dart L84-112 + share L128-138 (existing) | n/a — sentinel | route gif through ResizeImage → red | `./scripts/run_test_gates.sh groups` | existing |
| TC-200-14 | reload/error contracts preserved | widget | user_avatar_test.dart L29-104 (existing key locks) + NEW `errorBuilder != null` asserts inside TC-200-01..06 | key sentinel exists; errorBuilder lock is NEW (reviewer-caught: NO pre-existing errorBuilder test anywhere) | drop key or errorBuilder in the rewrite → red | feature-host-all | existing + AUTO |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** old non-square files already on disk must render un-stretched WITHOUT re-upload — TC-200-02/04 (file branches) + TC-200-07 prove the render-side heal on file-sourced providers. Covered.
- **Sibling-surface consistency:** the parallel bounded-decode surface `MediaThumbnailImage` (attachment strip, media grid) is single-dim → aspect-safe; justified N/A for behavior change, and Scope Guard forbids "fixing" it here. The share thumb (the one both-dims sibling) IS covered (TC-200-06).
- **Destructive-action side-effects:** N/A — no delete/cleanup path changes. The crop writes a NEW file; temp accumulation matches the existing prepareAvatar temp-file pattern (same directory lifecycle).
- **Invariant re-verification under new transitions:** the NORMALIZATION_FALLBACK transition (raw bytes committed on normalize failure) invalidates any "all canonical files are square" assumption — re-verified by keeping fallback locks green (TC-200-13-adjacent, `group_avatar_storage_test.dart:190-240`) AND by the render-side rows which do not assume square input.

## Invariants (locked by tests)
- INV-200-1: No avatar render site decodes with both-dims exact policy → TC-200-01..06 (+ lib-wide `cacheHeight` sweep in QA).
- INV-200-2: Decoded avatar bitmap preserves source aspect ratio → TC-200-07.
- INV-200-3: processAvatar success path emits square 512×512 jpeg in a NEW file; failure/undecodable paths pass through unchanged → TC-200-08/09/10/11/15.
- INV-200-4: GIF file-branch never wraps in ResizeImage → existing locks (TC-200-13).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot; record the groups + feature-host-all/core-host-all baselines. THEN pubspec.yaml: add `image: ^4.x` (direct dep) + `flutter pub get` — test-enabling infra only, no production behavior (reviewer-caught: rows 6/7 need package:image to COMPILE; without this ordering they fail to compile rather than fail for the documented reason — INV-RED-FIRST intact).
2. Add ALL RED tests (rows 1-8); run the focused commands; confirm each fails for its documented reason (policy==exact; ratio==1.0 from the OVERSIZED fixture; width≠height). TC-200-09/10/15 legs are fix-contract guards (green-by-construction pre-fix, mutation-backed) — do not expect them red.
3. NEW `lib/shared/widgets/media/avatar_image_provider.dart`: `avatarResizedProvider(ImageProvider inner, int cacheSize)` → `ResizeImage(inner, width: cacheSize, height: cacheSize, policy: ResizeImagePolicy.fit)` (structural precedent: `media_thumbnail_image.dart`).
4. Switch the 4 widgets to `Image(image: avatarResizedProvider(...))`, carrying key/fit/width/height/gaplessPlayback/errorBuilder verbatim; GIF file-branch keeps raw `FileImage`. Stop-if: any existing ValueKey/errorBuilder lock reds → carry the missing param, do not weaken the lock.
5. `ImageProcessor.processAvatar`: after successful `_compressFile`, decode→`copyCrop` centered square→`encodeJpg(quality: 85)`→write NEW file (compute() offload); return new path. Fix the `:64` doc. Failure paths untouched.
6. Rerun direct REDs → GREEN; then preservation sentinels; then named gates.
7. `graphify update .` && `./graphify-arch/refresh_arch_graph.sh` (repo root — never from inside graphify-arch/).

## Risks And Edge Cases
- **Silently-inert locks**: under fit, old width/height asserts stay green — the policy asserts (rows 1-4) are the ONLY mutation guard; QA must run the fit→exact mutation explicitly.
- Extreme aspect ratios (panorama): fit decodes cover-axis slightly under box → minor upscale softness at 36-88px (imperceptible; accepted).
- `CompressFileFn` typedef is a load-bearing seam faked in ≥4 test files — do NOT change its shape; crop is a separate post-step (pinned by TC-200-11 ordering).
- `pass_post_along_use_case_test.dart:435-436` pins 512-min compressor args — crop-after-compress keeps it green by design.
- GIF-as-.jpg on the download path (extension-based `isProcessableImage`) — pre-existing edge, out of scope; crop tests must not assume real JPEG bytes on fake-committed download paths.
- package:image is a NEW dep + compute() is a NEW pattern in lib/core/media — keep the crop function top-level for compute compatibility.

## Device/Relay Proof Profile
host-only for closure (pure decode/render + local file processing; no OS boundary, no crypto, no relay, no DB migration). Optional belt-and-braces: manual on-sim visual check of a non-square group avatar after the fix. No /sims row.

## Acceptance Gates  (literal)
```bash
# RED (before production edits) — must FAIL for the documented reasons
flutter test test/features/groups/presentation/widgets/group_avatar_test.dart
flutter test test/features/home/presentation/widgets/user_avatar_test.dart
flutter test test/features/home/presentation/widgets/profile_avatar_widget_test.dart
flutter test test/features/share/presentation/share_target_picker_screen_test.dart
flutter test test/features/settings/application/helpers/avatar_normalization_helper_test.dart
flutter test test/core/media/image_processor_test.dart

# Direct GREEN (after fix) — same six commands, all pass

# Preservation sentinels + named gates
./scripts/run_test_gates.sh groups            # expect: all pass; last recorded 1010 at 9b784bfd close-out (+3 QA since; re-derive baseline BEFORE the RED batch; 1 known ML-004 flake passes standalone)
./scripts/run_host_test_gates.sh feature-host-all   # expect: exit 0 (no numeric baseline recorded — capture pre-change)
./scripts/run_host_test_gates.sh core-host-all      # expect: exit 0
flutter test test/features/groups/application/group_avatar_storage_test.dart   # fallback + payload locks stay green
flutter test test/features/posts/phase4/pass_post_along_use_case_test.dart     # 512-min probe stays green

# Mutation verification (QA)
# flip policy fit→exact in avatar_image_provider.dart → TC-200-01..07 red; restore
# delete crop step → TC-200-08/11 red; restore

# Hygiene
flutter analyze            # 0 new (5 pre-existing findings in untouched files)
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the six focused commands above before implementation (policy/aspect/square asserts).
- Pre-existing dirty: graphify-arch/* meta + info.plist at repo root (documented; do not revert).
- Environment blocker (NOT product): none expected (host-only).
- Scope drift (BLOCKING): any red outside the listed files (e.g. MediaThumbnailImage tests, conversation media suites).

## Done Criteria
- [x] RED added first, failed for documented reasons (7 render + TC-200-08/11/12; guards green-by-design).
- [x] Mutation-verified (fit→exact → 7 render red; crop-disable → TC-200-08/11/12 red; square-guard removal → TC-200-09 red; all restored).
- [x] Direct GREEN + sentinels + `groups` gate (1022 + 2 known flakes) + feature-host-all (exit 0, 643) + core-host-all (exit 0) pass.
- [x] No DB migration (none needed).
- [x] No OS-boundary claims (host-only closure).
- [x] New helper test auto-globs (green in feature-host-all).
- [x] flutter analyze 0 new in changed files; git diff --check clean; both graphs refreshed.

## Scope Guard (hard "Do not")
- Do not change `CompressFileFn`'s typedef shape.
- Do not touch `MediaThumbnailImage`, media grid, attachment strip, full-screen viewer.
- Do not weaken/delete the GIF-exemption, NORMALIZATION_FALLBACK, ValueKey-reload, or inner-FileImage locks — extend only.
- Do not add an image-cropping UI (out of scope; render+silent-crop only).
- Do not modify orbit files (201/202 own those).

## Execution Reviewer Pass (2026-07-04, 4-lens adversarial workflow wf_060c61e5-597)
5 findings, all nit/minor (zero blocking, zero correctness/carry-list/crop-math defects — those were verified correct):
- **[minor] Main-isolate crop CPU** — inline `_squareCropAvatar` decodes/encodes on the UI isolate (vs the prior native-background compress). Accepted: avatar pick is one-shot + spinner-guarded; inline avoids `compute()` isolate-spawn variance flaking the pick-flow tests on this contended host. Bounded (short side floored at 512). See Accepted Differences.
- **[nit ×2] +1 orphaned temp file** — FIXED: crop branch now best-effort-deletes the pre-square `_compressed.jpg` intermediate (net-zero temp files vs prior behavior; inner try/catch so a delete failure never discards the successful crop).
- **[nit] TC-200-09 tautological** — FIXED: strengthened to lock the square-skip pass-through (asserts `outPath == compressedPath` + byte-identical); now REDs under square-guard removal (mutation-verified). This is the sole test making the square-guard load-bearing.
- **[minor] user_avatar `.gif` branch untested** — WON'T-FIX (documented): `user_avatar._resolveAvatarPath` hardcodes the path to `$peerId.jpg`, so `realPath` can never end in `.gif`; the gif-conditional is unreachable defensive code and no black-box test can exercise it. Kept per Scope Guard (do not weaken gif exemptions).

## Accepted Differences / Intentionally Out Of Scope
- **Inline crop (not `compute()`)**: pure-Dart decode/copyCrop/encodeJpg runs on the main isolate during avatar pick — a brief, spinner-guarded, one-shot cost. Chosen over the plan's `compute()` because isolate-spawn timing variance flaked the pick-flow widget tests (fixed 50ms `runAsync` window) on this CPU-contended host. Follow-up: move to `compute()` if a large-aspect-ratio pick ever shows perceptible jank (crop fn is already top-level/compute-ready).
- Square-guard is defensive/quality (not test-rescuing) — see implementation-row note; existing byte-asserted fixtures are undecodable minimal PNGs.
- Panorama softness under fit (imperceptible at avatar sizes).
- Avatars distributed BEFORE this fix remain non-square on disk (display-healed only) — no re-upload campaign.
- MediaThumbnailImage policy hardening — follow-up hygiene.
- Settings/FTE pick flows stay untestable at widget tier (inline `ImagePicker()`); funnel covered at helper + group_info tiers.
- Crop centering is not pixel-locked (an off-center square crop passes TC-200-08/09) — accepted; add a distinct-edge-color pixel assert only if product cares (reviewer note).

## Dependency Impact
- Plan 201's find-chip avatars (UserAvatar/GroupAvatar in chips) inherit this fix automatically — 200 should land first or the chips render stretched non-square avatars.
- Orbit ring GroupAvatar (197-lineage) renders correctly only after 200.

## Reviewer Findings
Two independent reviewers (workflow `wf_a8091cae-3b0`, 2026-07-04; 26 + 24 claims spot-verified in source/SDK). Both returned **draft-blocking-findings**; ALL findings applied in place:
- **BLOCKING (both): TC-200-07 vacuous as first drafted** — `allowUpscaling: false` clamps exact-policy decode to intrinsic dims (SDK `image_provider.dart:1368-1375`), so the original 4×2 fixture was GREEN on HEAD. FIXED: fixture is now 288×144 (must exceed the 144×144 target box in both dims); RED reason corrected; clamp documented so executors don't shrink it.
- **BLOCKING (r0): phantom errorBuilder sentinel** — no errorBuilder assertion existed anywhere; the claim was an untested assumption over constructions the refactor rewrites. FIXED: `errorBuilder != null` asserts added to TC-200-01..06; TC-200-14 re-scoped.
- **BLOCKING (r1): unspecified crop behavior for missing/undecodable compress output** would red image_processor_test (unwritten-path fake), group_avatar_storage_test (junk-bytes commit L154), pass_post_along (:429-441). FIXED: best-effort pass-through contract specified in Real Scope C + new TC-200-15 contract-guard row.
- MINOR (applied): dep-add moved BEFORE the RED batch (compile ordering); TC-200-11's reorder mutation re-assigned to TC-200-08's path-identity assert; `filterQuality: FilterQuality.low` added to the share carry-list + TC-200-06; group_info_wired path/line + GROUP_TESTS :226 anchor corrections; crop-centering not pixel-locked → recorded as Accepted Difference; baselines must be recorded pre-RED (already mandated).

## Arbiter Decision
Structural blockers: none remaining (all three blocking findings fixed in place; the vacuous-fixture fix restores the mutation-verified + no-vacuous-coverage gates; the pass-through contract restores the preservation gates). | Deferred details: exact `image:` version pin at `pub get` time; crop-centering pixel assert only if product asks. | Accepted differences: as listed. Plan is **implementation-ready**.

## Final Execution Verdict
**IMPLEMENTED + host-green + COMMITTED on branch new-orbit 2026-07-04.** Render half (4 widgets → `ResizeImagePolicy.fit` via new `lib/shared/widgets/media/avatar_image_provider.dart`) + upload half (`ImageProcessor.processAvatar` inline center-square crop with missing/undecodable/already-square pass-through). Both mutation halves re-red-verified. Gates: `groups` 1022 (+2 known ML-004/GM-036 flakes, pass standalone), `feature-host-all` exit 0 (643 files), `core-host-all` exit 0, collision suites 48 (pass_post_along oversized-omit, post_pass smoke byte-exact, group_avatar_storage, download_profile_picture) — all green. 4-lens adversarial review (wf_060c61e5-597): 5 nit/minor findings, 3 fixed (temp cleanup, TC-200-09 strengthened) + 2 accepted (inline-vs-compute, unreachable user_avatar gif). Deviations from plan (both documented above): (1) crop runs INLINE not `compute()`; (2) added `width==height` square-guard (defensive quality, not test-required). Graphs refreshed. Device proof: host-only closure per Device/Relay Proof Profile (no OS boundary); optional on-sim visual check of a non-square group avatar deferred.
