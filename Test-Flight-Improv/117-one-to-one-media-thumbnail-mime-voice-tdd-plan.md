# 117 — 1:1 Media: Thumbnail / MIME-policy / Voice TDD Plan

Status: execution-ready
Date: 2026-06-13
Branch: 121-improvements
Source findings: user-triaged "high" tier from the 1:1 reliability audit (`one-to-one-message-reliability-audit-2026-06-11.md`), re-verified in source 2026-06-13 by the `one-to-one-media-unavailable-debug` workflow (run `wf_c6845b58-8e1`, 30 agents) plus direct source reads on this branch.
Related plans (do NOT duplicate): `one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md` (Session E = thumbnail), `111-one-to-one-p0-silent-message-loss-tdd-plan.md`, `112-one-to-one-media-encryption.md`.

---

## Planning Progress

- 2026-06-13 — Re-verified all three finding clusters against the live tree on `121-improvements`. Cited line numbers from the original audit had drifted; the table below carries the **current** anchors.
- 2026-06-13 — Workflow `wf_c6845b58-8e1` independently confirmed the group-MIME render-gate leak into 1:1 (its RANK 5 + unverified findings [3]/[14]/[15]). The thumbnail and voice clusters were verified by direct read (the workflow was video/relay-centric).
- 2026-06-13 — Discovered an **uncommitted** working-tree edit: `local_media_server.dart:525-527` already adds `audio/mp4 → .m4a` (HEAD `:449` still falls through to `.bin`). Finding #3a is therefore *partially fixed but untested*; this plan locks it and extends it.

## Real Scope

Make the 1:1 media UI and storage **truthful** for media that was actually delivered, intact, and playable. Three clusters:

1. **Thumbnail failure ≠ missing media.** A downloaded, intact, playable video whose thumbnail cannot be generated/decoded must not render the identical "Media unavailable" placeholder used for genuinely missing media, and the cache must stop swallowing the failure with zero diagnostics.
2. **Group MIME/size policy must not leak into 1:1 render or 1:1 file naming.** Present, `done`, locally-existing 1:1 media whose real MIME is outside the group allow-list (`video/x-m4v`, `video/x-msvideo`, `video/x-matroska` — produced when the video re-encode falls back to the original container) must still render and open; and the receiver/durable/LAN file naming must give such files a playable extension, never extensionless or `.bin`.
3. **Voice must not silently lose the recording or strand the sender.**
   - 3a — LAN/durable file naming must map `audio/mp4` (the recorder's default MIME) to `.m4a`, never `.bin`.
   - 3b — The 5-minute auto-stop must not silently discard the captured recording with zero user feedback.
   - 3c — A LAN-sent / relay-upload-failed voice note must never persist the OS temp path as its only copy; the sender's own message must not flip to "Media unavailable" after temp purge / iOS container rotation.

## Out Of Scope (explicit)

- The **no-background-receiver-retry** gap (workflow RANK 1–3: one-shot fire-and-forget auto-download, no app-resume/reconnect re-drive). It is the dominant cause of the *generic* "Media unavailable" but is **not** one of these three findings and is owned by `one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md` (Session D) + the 111 workstream. Do not start it here.
- Relay durability / multi-relay failover / orphan adoption (Sessions A–C of the 2026-06-11 plan).
- Group media, posts media, calls. Touch a shared helper (`GroupMediaMimePolicy`, `MediaFilePathConvention`) only as directed below, and only in a way that preserves existing group behavior.

## Closure Bar

Closed only when ALL hold:

- Every test below is written **first**, fails for the intended reason, then passes after the minimal implementation.
- A `done` 1:1 video with a present local file but a failing thumbnail (generation **or** decode) renders a video/playable placeholder and stays openable — never the "Media unavailable" broken-image placeholder — and a thumbnail failure emits a FLOW event.
- A present, `done`, locally-existing 1:1 video/audio attachment with a real-but-non-allowlisted MIME renders and opens; group cells (`requireVerifiedContentHash == true`) keep their current strict gating unchanged.
- `MediaFilePathConvention.extensionFromMime` and `LocalMediaServer._extensionFromMime` both return a playable extension for `audio/mp4`, `video/x-m4v`, `video/x-msvideo`, `video/x-matroska` — never `''` or `.bin`. The uncommitted `audio/mp4` edit is covered by a regression test.
- The 5-minute auto-stop surfaces a user-visible outcome and does not silently drop the recording.
- A voice note whose relay upload fails (or that is delivered only over LAN) has a durable owned local copy; simulating temp-file loss does not flip the sender's own message to pending→failed→unavailable.
- 1:1 Reliability host gate + the touched host suites are green.

## Source Of Truth

- Production code on `121-improvements` is authoritative over any prior report.
- Gates: `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, and the skill gate `run_host_gates.sh 1to1`.
- Graph navigation (per CLAUDE.md): `cd graphify-arch && graphify query "..."` first; raw reads to modify/debug.

---

## Findings → Verified Mechanism (current tree)

| # | Finding | Verified mechanism (file:line, 121-improvements) | Status |
|---|---------|--------------------------------------------------|--------|
| 1 | Thumbnail failure renders identical "Media unavailable" | `video_thumbnail_cache.dart:85` bare `catch (_) { return null; }` swallows every generation error → indistinguishable from "no thumbnail". `media_thumbnail_image.dart:95` returns `widget.error` when resolve→null **and** file missing; `:108-109` `Image.file` errorBuilder returns `widget.error` when the generated thumbnail JPG fails to decode. `media_grid_cell.dart:135` wires `error: _buildUnavailablePlaceholder` (same widget as `:115-117` for failed/missing). `_canRetryUnavailableMedia` (`:102-104`) is false for a `done` row → no retry, no distinction. | live |
| 2 | Group MIME policy leaks into 1:1 cells | `group_media_mime_policy.dart:15-27` allow-list has only `video/mp4`,`video/quicktime` → `validateDescriptor` returns `disallowed_mime` (`:52-55`) for `video/x-m4v`/`x-msvideo`/`x-matroska`. `media_grid_cell.dart:88-95` `_showsUnavailableMedia` ORs in `!_hasAllowedDescriptor`/`!_hasAllowedSize` **unconditionally**, even for 1:1 (`requireVerifiedContentHash == false`). `media_file_path_convention.dart:33-49` `extensionFromMime` returns `''` for those MIMEs → extensionless files. | live |
| 3a | LAN voice saved `.bin` | Recorder emits AAC/`.m4a`; `AudioRecording.mime` defaults to `'audio/mp4'` (`audio_recording.dart:11`). `LocalMediaServer._extensionFromMime` at **HEAD `:449`** maps only `audio/aac`/`audio/m4a`→`.m4a`, so `audio/mp4`→`.bin` (`:455`). Working tree `:525-527` already adds `audio/mp4` (uncommitted, untested). | partial-uncommitted |
| 3b | 5-min auto-stop silent discard | `record_audio_recorder_service.dart:106-111` `_maxDurationTimer` calls `stop()` (returns a valid recording) then `onAutoStopped?.call(recording)`. `conversation_wired.dart:2915-2939` `_onRecorderAutoStopped` resets the composer and emits `CONV_FL_RECORD_AUTO_STOPPED` but **does not save, send, or show any SnackBar** — comment: *"the result is discarded like a too-short recording."* | live |
| 3c | LAN-sent voice persists temp path | `conversation_wired.dart:2689-2700` optimistic voice `MediaAttachment(localPath: recording.filePath, downloadStatus: 'done')` — `recording.filePath` is `getTemporaryDirectory()/voice_<ts>.m4a` (`record_audio_recorder_service.dart:227-231`). Voice has **no** optimistic-time durable copy (unlike images via `_prepareDurableMediaUploads`). The durable copy is made only inside `uploadMedia` on **upload success**; `sendVoiceMessage` returns `uploadFailed` on a null upload (`send_voice_message_use_case.dart:131-135`), leaving the row at the temp path. Temp purge / container rotation → `_resolveAttachmentForDisplay` flips `done`→`pending` (`conversation_wired.dart:~1250`) → `_recoverVisibleMedia` attempts a relay download for a blob never uploaded → `failed` → "Media unavailable" on the sender's own message. | live |

---

## Session Classification

- **Session 1 (TH)** — Thumbnail failure is distinct + diagnosable. Implementation-ready. Extends 2026-06-11 Session E (which targeted only the null-generation+file-present branch).
- **Session 2 (MIME)** — 1:1 descriptor-gate scoping + extension-map completeness (findings #2 and #3a). Implementation-ready. Touches shared `GroupMediaMimePolicy`/`MediaFilePathConvention`/`LocalMediaServer` — preserve group behavior.
- **Session 3 (AUTOSTOP)** — Auto-stop no-silent-loss (finding #3b). Implementation-ready **after one product decision** (below).
- **Session 4 (VOICE-DURABLE)** — Durable voice copy at optimistic-save (finding #3c). Implementation-ready.

**Recommended execution order:** 2 → 1 → 3 → 4. Session 2 lays the extension/descriptor foundation that Session 4's durable-copy naming relies on; Sessions 1 and 3 are independent and can interleave.

---

## Session 1 (TH): Thumbnail Failure Is Not Media Unavailable

### Failing tests (write first)

1. `test/core/media/video_thumbnail_cache_test.dart` — *cache surfaces failure, does not swallow silently.*
   - Arrange: inject a thumbnail generator (new test seam) that throws.
   - Act: `VideoThumbnailCache.resolve(videoPath)` for an existing video file.
   - Assert: a FLOW event (e.g. `VIDEO_THUMBNAIL_GENERATE_FAILED`) is emitted with the path/error, and the result is a typed "generation-failed" signal (still null-equivalent for callers, but observable). **Fails today**: `:85` swallows with zero telemetry.

2. `test/shared/widgets/media/media_grid_cell_test.dart` — *decode failure on a present, done video renders playable, not unavailable.*
   - Arrange: `MediaAttachment(mediaType:'video', downloadStatus:'done', mime:'video/mp4')` with a real on-disk file; `videoThumbnailResolver` returns a path to a **corrupt/undecodable** JPG (or a resolver that returns null while the video file exists). `requireVerifiedContentHash:false` (1:1), `onTap` non-null.
   - Assert: the cell does **not** render `l10n.media_unavailable`; it renders the video placeholder + play overlay (`VideoThumbnailOverlay`) and is tappable (`_canOpen == true`). **Fails today** for the corrupt-JPG path: `media_thumbnail_image.dart:108-109` → `widget.error` → `_buildUnavailablePlaceholder`.

3. `test/shared/widgets/media/media_thumbnail_image_test.dart` — *thumbnail-failure widget is the caller's "video fallback", never reused as the "media unavailable" widget for a present file.* Assert the error/fallback path for a present `mediaPath` resolves to the placeholder branch, not the error branch.

### Implementation (minimal)

- `lib/core/media/video_thumbnail_cache.dart`: replace the bare `catch (_) { return null; }` at `:85` with a catch that `emitFlowEvent(layer:'FL', event:'VIDEO_THUMBNAIL_GENERATE_FAILED', details:{...})` before returning. Add a `thumbnailGenerator` function seam (default `VideoCompress.getFileThumbnail`) for the test.
- `lib/shared/widgets/media/media_thumbnail_image.dart`: for a **video whose `mediaPath` file exists**, a failed/null thumbnail must resolve to `widget.placeholder` (the playable fallback), not `widget.error` — including the `Image.file` `errorBuilder` (`:108-109`) when rendering a generated-but-undecodable thumbnail of a present video. Reserve `widget.error` for the genuinely-missing-file case (`:92` false).
- `lib/shared/widgets/media/media_grid_cell.dart`: ensure a `done` video with a present file but failed thumbnail keeps `_canShowVideoOverlay`/`_canOpen` true (it already is once `_showsUnavailableMedia` stays false). No new "unavailable" routing for thumbnail failure.

### Relationship to 2026-06-11 Session E

If Session E already landed the null-generation+file-present distinction, Session 1 is the **delta**: (a) cache telemetry, (b) the generated-JPG decode-failure path. Keep both tests; they assert end-state regardless of E's status.

### Gate

`flutter test test/shared/widgets/media/media_grid_cell_test.dart test/shared/widgets/media/media_thumbnail_image_test.dart test/core/media/video_thumbnail_cache_test.dart` + 1:1 Reliability host gate.

---

## Session 2 (MIME): 1:1 Descriptor Gate Scoping + Extension Completeness

Covers finding #2 (render leak + extensionless files) and #3a (voice `.bin`), which share the MIME/extension machinery.

### Failing tests (write first)

1. `test/shared/widgets/media/media_grid_cell_test.dart` — *1:1 cell does not gate present media on the group MIME allow-list.*
   - Arrange: `MediaAttachment(mediaType:'video', mime:'video/x-matroska', downloadStatus:'done')` with a present local file; `requireVerifiedContentHash:false`.
   - Assert: not `media_unavailable`; renders/opens. **Fails today**: `_showsUnavailableMedia` true via `!_hasAllowedDescriptor`.
   - Add the inverse guard: same attachment with `requireVerifiedContentHash:true` (group) **still** renders unavailable (behavior preserved).

2. `test/core/media/media_file_path_convention_test.dart` — `extensionFromMime` returns `.m4v`/`.avi`/`.mkv` for `video/x-m4v`/`video/x-msvideo`/`video/x-matroska` and `.m4a` for `audio/mp4`; never `''`. **Fails today** for the video variants (`:48` → `''`).

3. `test/core/local_discovery/local_media_server_test.dart` — `_extensionFromMime` (exercised via the public staging path or a visible-for-testing seam) returns `.m4a` for `audio/mp4` and a playable extension for the three video variants; never `.bin`. **Fails on HEAD** for `audio/mp4`; locks the uncommitted working-tree edit and extends it.

### Implementation (minimal)

- `lib/shared/widgets/media/media_grid_cell.dart:88-95`: scope the group descriptor/size checks to group rendering only — apply `!_hasAllowedDescriptor || !_hasAllowedSize` **only when `requireVerifiedContentHash` is true**. For 1:1, availability is determined by `GroupMediaIntegrityPolicy.isUnavailableMedia` + file presence + `downloadStatus`, not group MIME allow-list membership. (Chosen over widening the allow-list, which would alter group policy cross-feature and admit non-playable containers into group cells.)
- `lib/core/media/media_file_path_convention.dart:33-49`: add `'video/x-m4v':'.m4v'`, `'video/x-msvideo':'.avi'`, `'video/x-matroska':'.mkv'` (audio/mp4→.m4a already present).
- `lib/core/local_discovery/local_media_server.dart:518-534`: keep the uncommitted `audio/mp4` branch; add the three video variants; keep `.enc` for `offer.enc` (unchanged). `.bin` remains only for genuinely unknown types.
- Verify the receiver decrypt-adopt path derives the extension from `MediaFilePathConvention.extensionFromMime` (it does for audio/mp4→.m4a) so an enc-staged LAN voice lands `.m4a` after adoption.

### Notes

- The source of these MIMEs is the video re-encode falling back to the original container (`image_processor.processVideo` returns the original temp on null compress). The fallback is correct; the fix is downstream truthfulness, not changing the fallback.
- Do **not** loosen `validateFile` signature-sniffing (`group_media_mime_policy.dart:96-145`) — that is the real safety gate during download/import and is unaffected.

### Gate

`flutter test test/shared/widgets/media/media_grid_cell_test.dart test/core/media/media_file_path_convention_test.dart test/core/local_discovery/local_media_server_test.dart` + 1:1 Reliability host gate. Run the Group Messaging gate to prove group render behavior is unchanged.

---

## Session 3 (AUTOSTOP): 5-Minute Auto-Stop Does Not Silently Discard

### Product decision required (pick before coding)

The recorder auto-stops at 5 min with a **valid** captured recording; current code discards it silently. Options:

- **(A — recommended) Keep + notify.** Route the auto-stopped recording into the composer's "recording ready" state so the user can review/send/cancel, and show a SnackBar: "Recording reached the 5-minute limit." No silent loss, no surprise auto-send, no new screen. Matches voice plan 110's "auto-stop = discard" only for the *too-short* case; a full-length recording is preserved.
- (B) Auto-send with a SnackBar. Simplest no-loss, but sends without an explicit user gesture — the 2026-06-10 voice work deliberately put auto-send out of scope.
- (C) Notify-and-discard. A SnackBar tells the user it stopped and the clip was dropped. Removes the *silent* part but still loses the recording.

Default to **(A)** unless the owner chooses otherwise; write the test to the chosen option.

### Failing tests (write first)

- `test/core/media/record_audio_recorder_service_test.dart` — with an injected short `maxDuration` and a fake recorder, assert `onAutoStopped` fires with a **non-null** `AudioRecording` (valid file, duration) at the limit. (Confirms the recording is captured, not nulled — guards the seam Session 3 depends on.)
- `test/features/conversation/presentation/screens/conversation_wired_voice_autostop_test.dart` (create) — drive `_onRecorderAutoStopped(recording)` and assert the chosen behavior:
  - Option A: composer enters review/ready state with the recording attached; a SnackBar with the limit message is shown; the recording file is **not** deleted; no auto-send.
  - **Fails today**: `_onRecorderAutoStopped` (`:2915-2939`) resets to idle, shows nothing, drops the recording.

### Implementation (minimal)

- `lib/features/conversation/presentation/screens/conversation_wired.dart:2915-2939`: implement the chosen option. For (A): set composer to the ready/review state holding the auto-stopped recording + show the SnackBar; do not reset to `idle` discarding the clip. Keep the `CONV_FL_RECORD_AUTO_STOPPED` event and add the user-facing surface.
- Add the limit-reached l10n string if one does not exist.

### Gate

`flutter test test/core/media/record_audio_recorder_service_test.dart test/features/conversation/presentation/screens/conversation_wired_voice_autostop_test.dart` + 1:1 Reliability host gate.

---

## Session 4 (VOICE-DURABLE): Voice Note Always Has A Durable Local Copy

Finding #3c. The fix: give voice the same optimistic-time durable copy images get, so the sender's row never depends on the OS temp path or on relay-upload success.

### Failing tests (write first)

1. `test/features/conversation/application/send_voice_message_durable_copy_test.dart` (create) — *relay upload failure does not strand the sender on a temp path.*
   - Arrange: `sendVoiceMessage` with a fake `uploadMedia`/bridge that returns `uploadFailed`; a real temp recording file; a `MediaFileManager` over a temp owned-dir.
   - Assert: the sender's persisted attachment row for the voice `blobId` has `localPath` resolving under the owned media dir (relative `media/<peer>/<blobId>.m4a`), **not** the recorder temp path; and the row is renderable from that durable copy.
   - **Fails today**: on `uploadFailed` the durable copy is never made; the row keeps `recording.filePath`.

2. `test/features/conversation/presentation/screens/conversation_wired_voice_durable_test.dart` (create) — *temp loss does not flip the sender's own voice message to unavailable.*
   - Arrange: send a voice note (LAN leg succeeds / relay fails, or relay succeeds), then delete the OS temp file.
   - Assert: `_resolveAttachmentForDisplay` resolves to the durable owned copy; the message stays playable; no relay download is attempted for a never-uploaded blob. **Fails today.**

### Implementation (minimal)

- Make a durable owned copy of the recording **at optimistic-save time**, mirroring images. Either (a) extend the voice send in `conversation_wired.dart:2689-2718` to copy `recording.filePath` → owned `media/<peer>/<blobId>.m4a` via `mediaFileManager` and persist that path in the optimistic attachment (status `done`), or (b) move the durable copy into `sendVoiceMessage` so it runs **before** the relay upload and survives `uploadFailed`. Prefer (b) for a single owner of voice durability.
- Ensure the relay-failure branch (`conversation_wired.dart:2844-2865`) leaves the attachment pointing at the durable copy (message status may still be `failed` for *delivery* truthfulness — that is a separate concern — but the sender's media must remain playable).
- Reconcile `deleteSourceWhenDone:true` (`send_voice_message_use_case.dart:125`): only delete the recorder temp **after** the durable copy exists.

### Interaction with the out-of-scope receiver-retry gap

This fix is sender-side only. It does not change receiver behavior and does not depend on the receiver-retry work; keep them independent.

### Gate

`flutter test test/features/conversation/application/send_voice_message_durable_copy_test.dart test/features/conversation/presentation/screens/conversation_wired_voice_durable_test.dart` + 1:1 Reliability host gate.

---

## Cross-Session Gates & Commands

- Host gates (per `test-gate-definitions.md` / skill): `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" 1to1` and the touched feature/core suites.
- Named regression: `./scripts/run_test_gates.sh completeness-check` after any new integration/service/lifecycle test is added (classify new tests in `test-gate-definitions.md`).
- After code changes: `graphify update .` to keep the arch graph current.
- Device/simulator proof is **not** required for these four sessions — they are host-provable (widget render, unit MIME/extension, recorder seam, durable-copy persistence). Note: end-to-end *playability* of the saved `.m4v`/`.avi`/`.mkv` on each platform's player is a separate device-confirmation item; this plan only guarantees the file is named playably and the cell renders/opens it.

## Risks & Tradeoffs

- **Session 2 gate scoping**: removing the group descriptor/size gate from 1:1 render relies on signature-sniffing at download/import (`validateFile`) for safety. That gate is unchanged, so 1:1 keeps its real protection; the render gate was never the security boundary. Group cells are explicitly preserved by the `requireVerifiedContentHash` test.
- **Session 3** is a product/UX decision; (A) is recommended but the test must follow the chosen option.
- **Session 4 (b)** changes `sendVoiceMessage` ordering. Keep the change additive (durable copy before upload); do not alter the relay/LAN delivery semantics.
- Shared-helper edits (`MediaFilePathConvention`, `GroupMediaMimePolicy`, `LocalMediaServer`) ripple to group/posts — every shared edit ships with a preserved-behavior test.

## Definition Of Done

All four sessions' tests written-first-red-then-green; closure-bar bullets satisfied; 1:1 Reliability host gate + touched suites + group-render preservation green; `graphify update .` run; uncommitted `audio/mp4` LAN-map edit now covered by a regression test.

---

## Closure Log (2026-06-13)

**Status: IMPLEMENTED on `121-improvements` (uncommitted).** All 4 sessions landed TDD (red→green) in execution order 2 → 1 → 3 → 4.

- **Session 2 (MIME):** `media_grid_cell.dart` `_showsUnavailableMedia` now scopes `!_hasAllowedDescriptor || !_hasAllowedSize` to `requireVerifiedContentHash == true`; `MediaFilePathConvention.extensionFromMime` + `LocalMediaServer._extensionFromMime` gained `video/x-m4v→.m4v`, `video/x-msvideo→.avi`, `video/x-matroska→.mkv` (audio/mp4→.m4a was already present, now regression-locked). Two existing svg/oversized cell tests re-scoped to `requireVerifiedContentHash:true` (the gate's correct home). New: `test/core/media/media_file_path_convention_test.dart`.
- **Session 1 (TH):** Session-E null-resolve distinction was already landed; delta done — `video_thumbnail_cache.dart` added an injectable generator seam + `VIDEO_THUMBNAIL_GENERATE_FAILED` FLOW event in the previously-silent catch; `media_thumbnail_image.dart` errorBuilder returns `placeholder` (not `error`) for a present video with an undecodable thumbnail. New: `test/core/media/video_thumbnail_cache_test.dart`. (Decode tests drive the built `Image`'s `errorBuilder` directly — real `Image.file` decode doesn't run under `testWidgets`.)
- **Session 3 (AUTOSTOP):** **Owner chose "build the review state"** after discovering the plan's Option-A premise was wrong — there was NO review/ready composer state (manual stop sends immediately; enum was `{idle,arming,recording,stopping}`). Added `VoiceRecordingState.reviewing` + `isReviewing`, a review preview + Send/Discard controls in `ComposeArea`, `_onRecorderAutoStopped` now holds the clip + shows the SnackBar (l10n `conversation_voice_limit_reached`, en/ar/de), `_onReviewSend`/`_onReviewDiscard`, extracted shared `_sendVoiceRecording`, dispose cleanup, wired through `ConversationScreen`.
- **Session 4 (VOICE-DURABLE):** `sendVoiceMessage` persists a durable owned copy on relay-upload failure (failure branch only; success path untouched). Persisted as **`upload_pending` + absolute durable path** (NOT `done`) — an adversarial review caught that `done` would make `retryIncompleteUploads` reuse a never-uploaded relay blob (permanent recipient "Media unavailable" on relay-only failures); `upload_pending` keeps it re-uploadable and is never flipped/phantom-downloaded. New: `test/features/conversation/application/send_voice_message_durable_copy_test.dart`.

**Test placement deviation (intentional):** the auto-stop + durable **widget** tests live in `conversation_wired_test.dart` (its `pumpScreen` harness + local fakes aren't importable into a new file); the use-case durable test is its own new file. completeness-check stays green.

**Gates:** completeness-check **844/844**; 1:1 Reliability **793**; Group Messaging **324** (Session-2 group render preservation confirmed); `flutter analyze` on touched files = **0 new** issues. `graphify update .` + `refresh_arch_graph.sh` run. Adversarial review workflow (`wf_f8e85ad5`, 11 agents) confirmed 1 high-severity regression (the Session-4 `done`-vs-retry issue, now fixed) + 1 low comment-accuracy nit (fixed); all other candidate findings refuted.

**Device-confirmation still pending (out of this host-provable scope):** actual per-platform playback of the saved `.m4v`/`.avi`/`.mkv` files (this plan guarantees the file is named playably and the cell renders/opens it). Voice inline-playback note: a relay-failed voice is inline-playable only after a successful re-upload flips it to `done` (`AudioPlayerWidget._isAvailable` gates on `done`); the recording is preserved and the recipient eventually receives it via retry.
