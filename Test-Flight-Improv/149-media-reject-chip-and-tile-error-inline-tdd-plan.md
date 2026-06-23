# 149 - Media error feedback inline (composer reject-chip for too-large/GIF + drop redundant tile-duplicate snackbars)  (Bug | Feature Improvement)

Status: IMPLEMENTED host-green (2026-06-23, uncommitted on `new-feed`) — see Final Execution Verdict + Execution deviations
Spec: free-text intent (no formal spec) — chained from a UI/UX review of Group Messaging snackbars

> **LINE-NUMBER CAVEAT (read first).** This plan was authored against a slightly older snapshot of `group_conversation_wired.dart`; on the current `new-feed` tree **every `group_conversation_wired.dart` citation is ~80 lines low** (gate `:4554`→`:4634`, caller `:1851`→`:1866`, snackbars `:2262/:2372/:2429`→`:2278/:2387/:2444`). `conversation_wired.dart`, `compose_area.dart`, `conversation_screen.dart`, `group_conversation_screen.dart`, and `attachment_preview_strip.dart` citations are CURRENT/exact. **Re-locate every edit by SYMBOL name / l10n KEY, never by the line number alone** — two of the originally-cited snackbar lines (`:2361`, `:2395`) pointed at non-snackbar code. All citations below are corrected to verified HEAD values.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | attachment_preview_strip.dart(+test), conversation_wired.dart, group_conversation_wired.dart, conversation_screen.dart, group_conversation_screen.dart, compose_area.dart, media_grid_cell.dart(+test), group_media_size_policy.dart, group_media_mime_policy.dart, app_en/ar/de.arb, run_test_gates.sh | verify→refute (post-refute brief): tile upload-pending/unavailable/retry + UploadProgressBanner ALREADY exist (OUT); genuine gaps = composer reject-chip (too-large/GIF) + redundant GROUP snackbar drop. No migration. | Planner |
| 2026-06-23 | Planner | (as above) | Refactor both validate gates from `bool`→a COLLECTION of `MediaRejection{index,reason}`; AttachmentPreviewStrip gains per-index invalid state (red border + warning + KEPT X + short caption); ComposeArea Send onTap disabled while invalid present; drop 3 redundant GROUP media snackbars (NOT the text-retry one). | Reviewer |
| 2026-06-23 | Reviewer (sufficiency) — 9-agent verify→refute Workflow | all of the above + the SHARED `ConversationComposerViewState`, `_composerStateEquals`/`copyWith` sites, `_removeAttachment`, the pick path `_attemptAddPendingMedia`/`_resolvePendingMediaCandidates`, the compose_area onTap-vs-getter split | **1 BLOCKER**: `failed_message_retry_failed` is a TEXT-retry path with NO inline tile equivalent → must NOT be dropped. **3 design forks** (validation trigger / multi-invalid policy / chip copy) resolved with owner: pick-time + mark-all + short keys. **4 majors folded**: group `validateAttachments` discards the index (group gate must iterate `media`); single-`MediaRejection?`↔`Set<int>` mismatch (→ collection); shared composer-state `_composerStateEquals` omission masks repaints; `_removeAttachment` index-drift. Test-rigor: TC-02 vacuous RED, TC-06 needs accessor+multi-element, TC-08 three-not-four + per-string, TC-09 tap-no-fire+full-state, TC-10 relabel. | Arbiter |
| 2026-06-23 | Arbiter | (final structural verdict) | No structural blockers remain after revision. Pick-time trigger is a scope add (new validation hook in `_attemptAddPendingMedia` both surfaces) but bounded. Group size-gate `validateAttachments` unwind is the only hard refactor; flagged. | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-23 | contract extraction | (git status --short: only plan.md + info.plist dirty pre-start) | scope confirmed; line-drift re-located by symbol/key | new-feed dirty tree (Feed/Orbit) noted | RED |
| 2026-06-23 | RED tests added | attachment_preview_strip_test, conversation_wired_test, group_conversation_wired_test, NEW media_rejection_test | strip → COMPILE-RED (`No named parameter 'invalidIndices'`); media_rejection → COMPILE-RED (`Method not found: MediaRejection`); 1:1 oversized pick → behavioral RED (chip key absent, line 3884); group source-wiring → behavioral RED (`Actual: <true>` for media_still_unavailable) | RED for documented reasons | implement |
| 2026-06-23 | implementation | NEW media_rejection.dart; attachment_preview_strip.dart; compose_area.dart; conversation_screen.dart; group_conversation_screen.dart; conversation_wired.dart; group_conversation_wired.dart; app_en/ar/de.arb (+regen app_localizations*); run_test_gates.sh | pure collection gate + auto-derive in `_updateComposerState`; group gate unwinds `validateAttachments` (iterate media + total fold); removed `_showGifTooLargeMessage` ×2; dropped 3 group snackbars, KEPT `failed_message_retry_failed` | scoped files only | GREEN |
| 2026-06-23 | direct GREEN | strip 23/23, media_rejection 3/3, conversation_screen 70/70 | exact files run | reds now green | preservation |
| 2026-06-23 | preservation GREEN | conversation_wired_test 1:1 (+91, −5), group_conversation_wired_test (+155, −2 PRE-EXISTING) | **the 5 1:1 fails are NOT mine and NOT clean-HEAD — they are caused by a CONCURRENT, unrelated `155-status-glyph` edit to the SHARED `letter_card.dart` (retires the `done_all` delivered tick) present in the tree; reverting ONLY that file → conversation_wired_test +96 ALL PASS.** The 2 group fails (GMAR-004, incoming-image-refresh) are clean-HEAD pre-existing. | zero regressions from 149 | gates |
| 2026-06-23 | named gates | `./scripts/run_test_gates.sh feed` → 214/214 ALL PASS; `1to1` → 1163 pass /5 pre-existing (strip+media_rejection confirmed running, +26 combined); `groups` → 155 pass /2 pre-existing | flutter analyze 0-new (11 remaining all pre-existing info-level); git diff --check clean | gate green (minus pre-existing) | QA |
| 2026-06-23 | mutation-verify | compose_area onTap, attachment_preview_strip invalid branch | drop onTap `!hasInvalidAttachment` → TC-09 RE-RED; disable invalid branch → strip TC-01 RE-RED; both reverted | locks confirmed | verdict |

## Source Of Truth
- Spec / intent: inline below (UX review → owner-locked design decisions, 2026-06-23)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no sim rows in this plan)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (149)

## Session Classification
implementation-ready (host-only closure; no migration, no device-proof — all behavior is local composer render + a `bool`→collection seam refactor + a pick-time validation hook + snackbar removal).

## Owner Design Decisions (2026-06-23 — resolve the plan's prior self-contradictions)
1. **Validation trigger = PICK TIME.** The size/GIF gate runs when an attachment is added (in `_attemptAddPendingMedia`, both surfaces), not only inside `_onSend`. The chip + Send-disable appear immediately on a bad pick; Send never enables for an attachment that is already invalid. (Prior plan ran the gate only in `_onSend`, which contradicted INV-5 "disabled while present".)
2. **Multi-invalid = MARK ALL AT ONCE.** The gate collects EVERY failing index (not the first). Requires dropping the first-failure short-circuit in both gates AND unwinding the GROUP `GroupMediaSizePolicy.validateAttachments` delegation so the group size branch iterates `media` itself to capture each index. Whole-message overflow reasons that own no single index (`total_media_size_exceeded`/`media_size_exceeded`/`invalid_media_size`) surface as a **strip-level note + Send-disabled**, not a per-chip border.
3. **Chip copy = NEW SHORT l10n KEYS.** Add `media_too_large_chip` ("Too large") and `media_gif_too_large_chip` ("GIF too big") ×en/ar/de and regenerate. The existing `media_too_large_after_compress`/`media_gif_too_large` are full snackbar sentences (37/44 chars) that overflow a 72×72 chip — they stay on any retained snackbar path but are NOT used as the chip caption.

## Exact Problem Statement
When a user picks an attachment that fails a size policy, the rejection is surfaced as a **transient floating SnackBar** and the offending attachment is **silently discarded** — the user is never told *which* of several picked attachments was too large, and (if the snackbar is missed) believes everything is queued. **GROUP:** `_validatePendingGroupMediaDescriptors` (`group_conversation_wired.dart:4634-4686`) returns `bool` and routes the **first** failure to `_showAttachmentTooLargeMessage` or `_showGifTooLargeMessage` (`:4678-4683`); its caller (`:1866`) aborts the whole send. **1:1:** `_validatePendingMediaSizes` (`conversation_wired.dart:972-994`) is the same `bool`/first-failure shape, routing to `_showAttachmentTooLargeMessage` (`:899`, key `media_too_large_after_compress` at `:904`) / `_showGifTooLargeMessage` (`:957`, key `media_gif_too_large` at `:961`); caller `:1928`. The composer preview strip `AttachmentPreviewStrip._Thumbnail` (`attachment_preview_strip.dart:61-176`) has **no error/red state** — it shows only the upload scrim+spinner (`:114-132`) and hides its X during upload (`:154`, `if (!isUploading && onRemove != null)`).

Compounding it, the gates run **only inside `_onSend`** (group `:1866`, 1:1 `:1928`); the pick path (`_attemptAddPendingMedia` → `_resolvePendingMediaCandidates`, group `:781/:793`, 1:1 `:816/:827`) validates only the *combined* budget, never the per-type size cap. So an oversized file lands in `_pendingAttachments` with no signal until a Send press fails.

Separately, **GROUP** retry/unavailable flows fire **error SnackBars whose state the media tile already conveys inline**: `media_still_unavailable` (`group_conversation_wired.dart:2278`), `failed_media_retry_failed` (`:2376` and `:2410`), `failed_media_upload_pending_retry` (`:2387`). The shared tile `MediaGridCell` already renders an explicit upload-pending placeholder (`media_grid_cell.dart:252-300`) and an unavailable+retry placeholder (`:318-378`). **`failed_message_retry_failed` (`:2444`) is NOT in this set** — see Root Cause.

What must improve:
- A size/GIF rejection marks the **specific** picked attachment(s) with an **inline red error chip** (red border + warning icon, X/remove **kept**, short caption) **at pick time** and **disables Send** while *any* invalid attachment is present — instead of a discard + floating snackbar. The validate gate must surface **which indices** failed and **why** (`reason`), not a `bool`, and mark **all** failures, not just the first.
- The now-redundant **3 GROUP media-state** error snackbars whose state the tile already shows inline are removed.

What must stay unchanged (→ preserved-green sentinels):
- The tile's existing upload-pending placeholder (`media_grid_cell_test.dart:433`), unavailable+retry placeholder, and retry-button wiring.
- `UploadProgressBanner` (above-composer aggregate progress + cancel) — NOT duplicated per-tile (Accepted Difference: there is no per-attachment byte source).
- The `GroupMediaMimePolicy.validateDescriptor` **unsupported-MIME** path (`group_conversation_wired.dart:4636-4651`, snackbar `group_media_unsupported`) — a hard reject of a never-displayable file; out of scope, stays a snackbar (its MIME loop already iterates `media`, so an index is recoverable if ever wanted).
- **`failed_message_retry_failed` (`:2444`) stays** — it is the SOLE feedback for a failed text-message retry (no media tile renders for it). See Root Cause blocker.
- The 1:1 hardcoded retry literals (`conversation_wired.dart:2496`/`:2508`) — left as-is.
- 1:1 / group / feed gates, `flutter analyze` 0-new.

## Root Cause (verify → refute confirmed — 9-agent Workflow, 2026-06-23)
**Confirmed on HEAD (committed/inherited logic, NOT field build-skew):**
- The validate gates are **boolean / first-failure** and **side-effect the snackbar inside the gate**: group MIME `return false` after `group_media_unsupported` (`group_conversation_wired.dart:4649-4651`), group size `_showGifTooLargeMessage`/`_showAttachmentTooLargeMessage` then `return false` (`:4678-4683`); 1:1 `:986-991`. Callers consume only the `bool` and abort the send (group `:1866`, 1:1 `:1928`).
- **GROUP size branch discards the index.** Unlike the 1:1 gate (which iterates `media` element-by-element via `GroupMediaSizePolicy.validateSize`, so the failing index is at the failure site — just discarded, `conversation_wired.dart:972-994`), the group size branch delegates the whole list to `GroupMediaSizePolicy.validateAttachments` (`group_conversation_wired.dart:4653`), which iterates *inside the policy* (`group_media_size_policy.dart:113-119`) and returns a bare `GroupMediaValidationResult{bool isValid, String? reason}` (`group_media_mime_policy.dart:5-12`) — **NO index, NO id, NO element ref**. The group gate must be rewritten to loop `media` itself to capture indices. (The group MIME loop already iterates `media`.)
- `AttachmentPreviewStrip` has **no invalid/error parameter** (`_Thumbnail` ctor `:61-70` has only `file`, `isUploading`, `onRemove`); X conditionally hidden during upload (`:154`). The not-uploading X is *already shown* when `onRemove != null` — so "keep the X" is a no-op on the X condition; the new code is the red border + warning + caption.
- `ComposeArea` has TWO independent enable expressions that the prior plan conflated: the **visibility getter** `_shouldShowSendButton` (`:285-286`) = `(_hasText || widget.hasAttachments) && !_isRecording` (decides Send-vs-mic), and the **hard-stop onTap null-gate** (`:478-482`) = `!widget.isProcessing && !widget.isSending && (_hasText || widget.hasAttachments)`. The onTap is the ONLY thing that stops a send (`_onSendPressed`'s own guard `:178` does NOT abort an oversized pick, because `hasAttachments` is true). The prior plan's "unified literal" matches NEITHER site.
- GROUP redundant **media** snackbars: `media_still_unavailable` (`:2278`), `failed_media_retry_failed` (`:2376`,`:2410`), `failed_media_upload_pending_retry` (`:2387`) fire **in addition to** the tile's inline state. They are reached only via `showFailedMediaActions` (`messageMedia.isNotEmpty`, `group_conversation_screen.dart:591-592`).

**BLOCKER found in refute — `failed_message_retry_failed` (`:2444`) is NOT redundant:**
- It fires inside `_onRetryFailedMessage`, wired ONLY via `showFailedTextRetry`, which **requires `messageMedia.isEmpty && text.trim().isNotEmpty`** (`group_conversation_screen.dart:593-600`) — **mutually exclusive** with `showFailedMediaActions`. A text-only failed bubble renders **NO `MediaGridCell`** (`MediaGrid` returns `SizedBox.shrink()` when `media.isEmpty`, `media_grid.dart:35`); the only inline UI is the Retry button (`letter_card.dart:477-488`), which has no "retry failed again" state. The snackbar at `:2444` (fired when the second retry attempt also fails) is the **sole** feedback. **Dropping it loses all feedback** — the prior plan's premise "the tile already conveys the state inline" is FALSE here, and its own Step-7 Stop-if forbids it. **KEEP IT.**

Refuted / do-NOT-re-introduce:
- ❌ "the tile has no inline upload/unavailable/retry state — build it" — **ALREADY DONE** (`media_grid_cell.dart:252-300` + `:318-378`, retry `:355-369` gated by `_canRetryUnavailableMedia` `:199-201`; test `media_grid_cell_test.dart:433`). Do NOT rebuild.
- ❌ "add a per-tile upload progress ring" — no per-attachment byte source; duplicates `UploadProgressBanner`. Accepted Difference.
- ❌ "the X is always shown, just style it red" — the not-uploading X is already shown; the NEW work is red border + warning + caption, and the X must NOT leak into the upload branch (`:154` `!isUploading` guard stays).
- ❌ "1:1 has the same redundant snackbars to drop" — 1:1 has NONE of these; it uses hardcoded English literals and lets the tile re-render. Snackbar-drop is **GROUP-only**.
- ❌ "MediaGridCell forks 1:1 vs group" — it is shared; only `requireVerifiedContentHash` differs. Do NOT edit `media_grid_cell.dart`.
- ❌ "drop all 4 GROUP snackbars" — only **3** are media-tile duplicates; `failed_message_retry_failed` is a text path (blocker above).
- ❌ "the group size index is trivially recoverable" — FALSE for the group size branch (`validateAttachments` discards it); must iterate `media`.
- ❌ "needs a migration" — rejection state is **pre-send composer state**, never persisted. DB stays v92; no 093.

## Real Scope
In scope:
- **Seam refactor → COLLECTION (both surfaces):** change `_validatePendingGroupMediaDescriptors` (`group_conversation_wired.dart:4634`) and `_validatePendingMediaSizes` (`conversation_wired.dart:972`) from `bool` to return the FULL set of failures. Define `MediaRejection { int index, String reason }` and return `List<MediaRejection>` (empty == all-valid; one per failing index). Drop the first-failure short-circuit in BOTH gates. **GROUP size branch must STOP delegating to `validateAttachments` and iterate `media` itself** (per element `GroupMediaSizePolicy.validateSize`), mirroring the MIME loop / the 1:1 gate, to capture each index. Keep the gate **side-effect-free of snackbars** for the size/GIF reasons (the chip renders them); the unsupported-MIME reason MAY keep its snackbar. **Reason normalization:** `gif_size_exceeded`→`gif_too_large`; ALL of `image/video/voice/file_size_exceeded`→`too_large`. Whole-message reasons with no owning index (`total_media_size_exceeded`/`media_size_exceeded`/`invalid_media_size`) → a sentinel rejection with `index == -1` consumed as a **strip-level note** (Send still disabled), not a per-chip border.
- **PICK-TIME computation:** invoke the (now snackbar-free, collection-returning) gate inside `_attemptAddPendingMedia` (group `:781`, 1:1 `:816`) after `_resolvePendingMediaCandidates`, and re-run it on `_removeAttachment` (group `:3283`, 1:1 `:3485`). Store the resulting `Set<int>` (and the per-index reason map + any strip-level reason) in composer state so the chip + Send-disable appear immediately and survive removal/index-shift (re-deriving from the current list each time eliminates stale-snapshot drift). Keep the `_onSend` pre-gate as a defensive re-check (now consuming the collection, still snackbar-free).
- **NEW composer reject-chip:** `AttachmentPreviewStrip` gains `Set<int> invalidIndices` + `Map<int,String> invalidReasons` (default `const {}`), and renders, on an invalid index: a **red-bordered keyed container** (`ValueKey('attachment-invalid-$index')`), a **warning icon** (lock `Icons.error_outline`), the short reason **caption** (`media_too_large_chip`/`media_gif_too_large_chip`), and **keeps the X** (the existing `!isUploading && onRemove != null` already shows it — the invalid branch must not suppress it). The invalid render branch is `isInvalid && !isUploading` (never paints red over an in-flight upload).
- **Send gating (onTap ONLY):** add `final bool hasInvalidAttachment` (default false) to `ComposeArea`; fold `&& !widget.hasInvalidAttachment` into the **onTap null-gate (`:478-482`)** — the real no-op stop. Do **NOT** add it to the `_shouldShowSendButton` getter (`:286`), to avoid flipping Send→mic while an invalid file sits in the strip (Send stays visible-but-disabled). (If a visible disabled *style* is wanted, style the existing Container; the tap is the behavior lock.)
- **State wiring (SHARED view-state):** `ConversationComposerViewState` is **shared** by both screens (`conversation_screen.dart:39-87`; group imports it). Add `invalidAttachmentIndices` (+ reason map + optional strip-level reason) to: (a) the class + ctor (`:39-60`); (b) `copyWith` (`:62-84`); (c) **BOTH** `_updateComposerState` copyWith calls (1:1 near `:3511`, group `:3373`); and **critically (d) BOTH `_composerStateEquals`** (1:1 `:3526`, group `:3388`) using `setEquals`/`mapEquals` — else the `if (_composerStateEquals(...)) return;` short-circuit (1:1 `:3522`, group `:3384`) swallows an invalid-set change when files are unchanged and the chip never repaints. Pass the set/reasons into `AttachmentPreviewStrip` (`conversation_screen.dart:340-348`, `group_conversation_screen.dart:241-249`) and `hasInvalidAttachment` into `ComposeArea`.
- **Drop 3 redundant GROUP snackbars** (media-tile duplicates only): `media_still_unavailable` (`:2278`), `failed_media_retry_failed` (`:2376`,`:2410`), `failed_media_upload_pending_retry` (`:2387`). Keep the surrounding re-resolve/retry/status side-effects intact (only the `_showFloatingSnackBar(...)` lines go). **KEEP `failed_message_retry_failed` (`:2444`).** Note `failed_media_upload_pending_retry` is informational (no `backgroundColor`), not red — its upload-pending placeholder is adequate replacement.
- **l10n:** add `media_too_large_chip` / `media_gif_too_large_chip` ×en/ar/de (append-by-key) + regenerate `app_localizations*`.
- **Tests:** see RED Test Catalog. Includes pick-time, multi-invalid, index-shift-on-removal, composer-state rebuild-equality, group + 1:1 Send-disable, 1:1 GIF, and the corrected snackbar-drop lock (3 dropped + #4 kept + inline placeholder present).
- **Harness registration:** add `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart` to `ONE_TO_ONE_TESTS` (append before the closing paren at `run_test_gates.sh:65`). `media_grid_cell_test.dart` auto-globs; `group_conversation_wired_test.dart` (`:131`) and `conversation_wired_test.dart` (`:63`) already registered.

Out of scope (owner named):
- **Per-tile upload progress ring** — no per-attachment byte source; `UploadProgressBanner` covers it. Owner: a future per-attachment-progress session.
- **Localizing the 1:1 hardcoded retry literals** (`conversation_wired.dart:2496`/`:2508`) — 1:1 keeps its snackbar-free tile re-render. Owner: an i18n-cleanup session.
- **Any DB schema change** — none.
- The unsupported-MIME hard reject (`group_media_unsupported`) keeping a snackbar — accepted.
- **`failed_message_retry_failed`** snackbar — KEPT (text-retry path); explicitly NOT in scope to drop.

## Files To Inspect Next
Production:
- `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart` — `_Thumbnail` `:61-176` (add `isInvalid`/`reasonText`: red border, `Icons.error_outline`, caption, keep X out of `isUploading` branch); ctor `:21-30` + itemBuilder `:42-55` (thread `invalidIndices`/`invalidReasons`).
- `lib/features/conversation/presentation/widgets/compose_area.dart` — onTap null-gate `:478-482` (add `&& !widget.hasInvalidAttachment`); ctor flags `:26-53`; do NOT edit `_shouldShowSendButton` getter `:285-286`.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — gate `_validatePendingGroupMediaDescriptors` `:4634-4686` (→ collection; UNWIND `validateAttachments` `:4653`, iterate `media` for size); MIME loop `:4636-4651` (keep snackbar); caller `:1866`; pick hook `_attemptAddPendingMedia` `:781` / `_resolvePendingMediaCandidates` `:793`; `_removeAttachment` `:3283`; `_composerStateEquals` `:3388` + copyWith call `:3373`; redundant snackbars `:2278`,`:2376`,`:2387`,`:2410` (drop); `failed_message_retry_failed` `:2444` (KEEP).
- `lib/features/conversation/presentation/screens/conversation_wired.dart` — gate `_validatePendingMediaSizes` `:972-994` (→ collection; already iterates `media`); caller `:1928`; too-large/GIF methods `:899`/`:957`; pick hook `_attemptAddPendingMedia` `:816` / `_resolvePendingMediaCandidates` `:827`; `_removeAttachment` `:3485`; `_composerStateEquals` `:3526` + copyWith call `~:3511`; hardcoded retry literals `:2496`/`:2508` (NOT edited).
- `lib/features/conversation/presentation/screens/conversation_screen.dart` — SHARED `ConversationComposerViewState` class `:39-60`, `copyWith` `:62-84`; 1:1 `AttachmentPreviewStrip` render `:340-348`; Send-area context `:354`+.
- `lib/features/groups/presentation/screens/group_conversation_screen.dart` — `AttachmentPreviewStrip` render `:241-249`; `showFailedMediaActions`/`showFailedTextRetry` split `:591-600` (proves #4 is text-only); ctor flags `:61-67`.
- `lib/core/media/group_media_size_policy.dart` — `validateSize` (per-element, used by the new group loop), `validateAttachments` `:103-130` (the delegation being unwound), `_perTypeSizeReason` `:48-64` (the 5+ reason strings to normalize).
- `lib/core/media/group_media_mime_policy.dart` — `GroupMediaValidationResult{isValid,reason}` `:5-12` (INSPECT ONLY — explains why the index is lost; do NOT extend it unless you choose to carry the index there).
- `lib/shared/widgets/media/media_grid_cell.dart` — INSPECT ONLY (`:252-300` upload-pending, `:318-378` unavailable+retry); confirm the 3 dropped snackbars are duplicated by these.
- `lib/l10n/app_en.arb` / `app_ar.arb` / `app_de.arb` — append `media_too_large_chip` / `media_gif_too_large_chip`; regenerate.
Direct tests:
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart` — rewrite/extend (19 prior tests; add red-chip + kept-X + index-shift cases).
- `test/features/groups/presentation/group_conversation_wired_test.dart` — gate-collection + too-large/GIF-chip-not-snackbar + multi-invalid + Send-disable + snackbar-drop(3)+#4-kept cases.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart` — gate-collection + too-large-chip + 1:1 GIF + Send-disable + pick-time + rebuild-equality cases (`_tinyGifBytes` already at `:135`).
- `test/shared/widgets/media/media_grid_cell_test.dart` — sentinel only (`:433`), no edit.

## Existing Tests Covering This Area
- `attachment_preview_strip_test.dart` — **19** tests (NOT 20). `:113` "shows remove buttons when not uploading" (3 X), `:122` "hides remove buttons during upload", `:135` upload spinner, `:191` GIF badge, `:209` "GIF badge IS hidden during upload", `:222` "no remove buttons when onRemove is null", processing cases — all PASS; kept as preservation. None reference an invalid/error state → red-chip behavior is uncovered.
- `media_grid_cell_test.dart:433` "renders upload_pending media as an explicit upload state" — PASSES; sentinel for inline upload state (asserts `find.text('Uploading media')` + `'Recipients will receive this after the upload finishes.'` + no `broken_image_outlined`). Plus the unavailable/`broken_image_outlined`/retry cases — sentinels for the inline unavailable state.
- `group_conversation_wired_test.dart` — has the 144-family terminal/media tests; **2 pre-existing failing** on HEAD (`GMAR-004 reopen-hydration` `:4019`, `incoming-group-image-refresh` `:4236`) — record at execution time, do not "fix". No too-large-chip / no snackbar-drop lock → gaps.
- `conversation_wired_test.dart` — no too-large-chip / pick-time / 1:1-GIF test → gaps.

Missing coverage gaps: composer **red chip** (border + warning + short caption + kept X) on each invalid index; chip appears **at pick** (no Send press); **all** invalid indices marked (multi-invalid); invalid set **recomputed on removal** (index-shift, no stale chip); composer-state **repaints when only the invalid set changes** (equality lock); **Send tap does not fire** while invalid present (1:1 AND group); gate returns **collection of {index,reason}** with normalized reasons (group + 1:1); too-large/GIF pick shows **chip not snackbar** (group + 1:1, incl. 1:1 GIF); the **3** redundant GROUP media snackbars **not shown** while the inline placeholder **is** shown; `failed_message_retry_failed` **still shown**.

Already in curated family arrays?:
- `attachment_preview_strip_test.dart` — ❌ NOT in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:17-65`) nor `GROUP_TESTS` (`:116-132`). → **registration step required** (add to `ONE_TO_ONE_TESTS`).
- `group_conversation_wired_test.dart` — ✅ `GROUP_TESTS:131`.
- `conversation_wired_test.dart` — ✅ `ONE_TO_ONE_TESTS:63`.
- `media_grid_cell_test.dart` — ✅ AUTO (`test/shared/widgets/**` glob).

## RED Test Catalog  (add/rewrite BEFORE any production code — INV-RED-FIRST)

1. `attachment_preview_strip_test.dart`::"invalid attachment renders a red border, a warning icon, a short caption, and keeps its remove X"  *(NEW)*
   - Tier: widget
   - Setup: pump `AttachmentPreviewStrip(attachments:[file], isUploading:false, invalidIndices:{0}, invalidReasons:{0:'too_large'}, onRemove:(_){})`.
   - RED on HEAD because: `invalidIndices`/`invalidReasons` (and the red-border/warning/caption branch) do not exist → compile-time red.
   - GREEN asserts: keyed red-border container `find.byKey(const ValueKey('attachment-invalid-0'))` findsOne; `find.byIcon(Icons.error_outline)` findsOne; the short caption (`media_too_large_chip` "Too large") findsOne; the X `find.byIcon(Icons.close)` findsOne — **all in the same chip** (locks the invalid branch did not suppress the X); `find.byType(CircularProgressIndicator)` findsNothing (distinct from uploading).
   - Mutation: remove the `invalidIndices.contains(index)` branch in `_Thumbnail` → no red key → red. (Locks INV-1/INV-2.)

2. `attachment_preview_strip_test.dart`::"valid attachment shows no invalid styling"  *(NEW, negative — behavioral lock at MUTATION time)*
   - Tier: widget
   - Setup: `invalidIndices:{}`, `invalidReasons:{}`, 3 files.
   - RED on HEAD: shares TC-01's compile-red (the param doesn't exist yet) — **this is NOT the lock**. The behavioral lock is the mutation below; the plan must observe green-after-fix THEN red-after-mutation.
   - GREEN asserts: `find.byKey(const ValueKey('attachment-invalid-0'))` findsNothing; X present (3); no `Icons.error_outline`.
   - Mutation that re-reds (the real lock): make the red branch unconditional (ignore `invalidIndices`) → red key appears on a valid chip → findsNothing fails → red.

3. `attachment_preview_strip_test.dart`::"hides remove buttons during upload"  *(PRESERVATION — existing `:122`)*
   - Tier: widget. Asserts unchanged: `isUploading:true` → `find.byIcon(Icons.close)` findsNothing.
   - Mutation: if the X-keep change drops the `!isUploading` guard → this reds. (Locks INV-2 upload half.)

4. `group_conversation_wired_test.dart`::"oversized group pick marks the chip invalid at pick time, shows no snackbar, and disables Send"  *(NEW)*
   - Tier: integration/widget (wired screen, fakes + real migrations in setUp)
   - Setup: add (pick) an attachment whose `budgetBytes` exceeds the per-type cap; pump. **Do NOT call `_onSend`** (locks pick-time + group-screen threading).
   - RED on HEAD: pick path runs no per-type gate, strip has no invalid state, and only `_onSend` would snackbar → asserting a rendered chip + Send-disabled fails.
   - GREEN asserts: the group screen renders `find.byKey(const ValueKey('attachment-invalid-0'))`; no `find.widgetWithText(SnackBar, …)` for the too-large copy; tapping the Send affordance does **not** invoke the send callback (spy not fired); the attachment is **retained**.
   - Mutation: (a) revert gate→bool + restore `_showAttachmentTooLargeMessage()` → snackbar returns, chip gone → red; (b) drop the group `hasInvalidAttachment` onTap threading → Send fires → red (locks group Send-disable wiring).

5. `conversation_wired_test.dart`::"oversized 1:1 pick marks the chip invalid at pick time and shows no snackbar"  *(NEW)*
   - Tier: integration/widget. 1:1 mirror of TC-04 (oversized pick → chip, no `_onSend`, no SnackBar, Send tap no-fire, retained).
   - RED on HEAD: pick path runs no per-type gate; new asserts fail. Mutation: revert 1:1 gate→bool + restore snackbar → red.

5b. `conversation_wired_test.dart`::"oversized 1:1 GIF pick marks the chip with the GIF caption (not a snackbar)"  *(NEW)*
   - Tier: integration/widget. Uses `_tinyGifBytes` (`:135`) sized over the GIF cap.
   - RED on HEAD: HEAD routes `gif_size_exceeded`→`_showGifTooLargeMessage` snackbar; asserting the GIF chip caption + no SnackBar fails.
   - GREEN asserts: invalid chip with `media_gif_too_large_chip` ("GIF too big") caption (distinct from the generic `too_large` copy); no SnackBar. Mutation: collapse the 1:1 reason map so GIF→generic `too_large` → wrong caption → red (locks the gif→gif_too_large normalization on 1:1).

6. `group_conversation_wired_test.dart` + `conversation_wired_test.dart`::"validate gate returns the collection of failing {index,reason}, not a bool"  *(NEW — seam contract via `@visibleForTesting` accessor)*
   - Tier: integration/widget. Add a `@visibleForTesting` accessor exposing the gate result (commit to the accessor; do NOT use "observed effect" — that collapses into TC-04/07).
   - Setup: three picks — valid at 0, oversized **video** at 1, oversized **GIF** at 2.
   - RED on HEAD: gate returns `bool` → nothing to read → compile/contract red.
   - GREEN asserts: result contains `{index:1, reason:'too_large'}` AND `{index:2, reason:'gif_too_large'}` (NOT index 0); video→`too_large` (reason normalization); empty when all valid.
   - Mutation: (a) collapse to `bool`/first-failure → only index 1 (or none) → red (locks mark-all + the group `validateAttachments` unwind); (b) hardcode index 0 → wrong index → red (observable BECAUSE the oversize is at 1/2, not 0).

7. `group_conversation_wired_test.dart`::"GIF-too-large group pick marks the chip with the GIF caption (not a snackbar)"  *(NEW)*
   - Tier: integration/widget. RED on HEAD: HEAD `_showGifTooLargeMessage` snackbar. GREEN: invalid chip with `media_gif_too_large_chip` caption; no SnackBar with the GIF copy. Mutation: restore `_showGifTooLargeMessage()` → red.

8. `group_conversation_wired_test.dart`::"the 3 redundant media snackbars are dropped while the tile state remains; the text-retry snackbar still shows"  *(NEW — corrected snackbar lock)*
   - Tier: integration/widget
   - Setup: drive (a) refreshed media still unavailable (`:2278`), (b) failed-media retry fails (`:2376`/`:2410`), (c) failed-media upload-pending retry (`:2387`), and (d) **text-message retry fails** (`:2444`, a media-less failed text bubble via `showFailedTextRetry`).
   - RED on HEAD: HEAD shows snackbars (a)(b)(c).
   - GREEN asserts (one assertion **per string**, not "any one"): `find.widgetWithText(SnackBar, media_still_unavailable)` / `…(SnackBar, failed_media_retry_failed)` / `…(SnackBar, failed_media_upload_pending_retry)` each findsNothing; **AND** the matching inline placeholder is present in the SAME flow (`broken_image_outlined` for unavailable; the upload-pending placeholder for pending) — proves state moved inline, not lost; **AND** for (d) `find.widgetWithText(SnackBar, failed_message_retry_failed)` **findsOneWidget** (KEPT — sole feedback for the text path).
   - Mutation: restore any one dropped `_showFloatingSnackBar(...)` → that string reappears → red; OR drop the `failed_message_retry_failed` call → (d) findsNothing → red. (Locks INV-6 per-string and the blocker fix.)

9. `conversation_wired_test.dart`::"Send tap is a no-op while an invalid attachment is present, and re-enables once all are removed (1:1)"  *(NEW — Send-gating lock)*
   - Tier: integration/widget
   - RED on HEAD: onTap gate has no `hasInvalidAttachment` term → with an oversized pick present, tapping Send fires the send callback → asserting "not fired" fails.
   - GREEN asserts: with an invalid chip present, tapping the Send affordance does **not** invoke the send callback (spy) **and** the Send icon (not the mic) is still shown; after removing the offending attachment, the **full** post-removal state holds — `find.byKey(ValueKey('attachment-invalid-0'))` findsNothing, no `Icons.error_outline`, surviving valid attachment count correct, and tapping Send now fires (if text/valid attachments remain).
   - Mutation: drop `&& !widget.hasInvalidAttachment` from the onTap gate → Send fires → red.

10. `media_grid_cell_test.dart`::"renders upload_pending media as an explicit upload state"  *(PRESERVATION — existing `:433`; INLINE-PRESENCE sentinel ONLY)*
    - Tier: widget. Asserts unchanged: `find.text('Uploading media')` + `'Recipients will receive this after the upload finishes.'` + no `broken_image_outlined`.
    - NOTE: re-adding a dropped snackbar does NOT re-red this — it locks only that the inline state EXISTS. The snackbar-removal lock is TC-08. (INV-6's removal half rests on TC-08; this is the presence half.)

11. `conversation_wired_test.dart`::"two oversized picks mark BOTH chips invalid and keep Send disabled until both are removed (multi-invalid)"  *(NEW)*  — mirror on group in `group_conversation_wired_test.dart` (group exercises the `validateAttachments` unwind).
    - Tier: integration/widget. Setup: two oversized picks.
    - RED on HEAD: gate is first-failure `bool` → at most one chip → asserting two red keys fails.
    - GREEN asserts: `find.byKey(ValueKey('attachment-invalid-0'))` AND `…-1` both present; Send tap no-fire; remove one → the OTHER stays invalid and Send still no-fire; remove both → no red key, Send fires.
    - Mutation: restore the first-failure short-circuit → second chip unmarked → red. (Locks mark-all / INV-8.)

12. `conversation_wired_test.dart`::"removing a valid attachment shifts the invalid chip to the correct remaining index"  *(NEW — index-drift)*
    - Tier: integration/widget. Setup: valid at index 0, oversized at index 1.
    - RED on HEAD: `_removeAttachment` never recomputes an invalid set (none exists) → after removing index 0 the chip is on the wrong/absent item → assert fails.
    - GREEN asserts: after removing index 0, the still-invalid chip is at `ValueKey('attachment-invalid-0')` (followed the item) and the survivor shows no stale red; after removing the offender, no red key remains.
    - Mutation: skip the recompute-on-remove hook → stale/misplaced chip → red. (Locks INV-7 index-shift.)

13. `conversation_wired_test.dart`::"changing only the invalid set (same attachments) repaints the strip"  *(NEW — composer-state equality lock)*
    - Tier: integration/widget. Setup: drive `_updateComposerState` with the SAME `pendingAttachments` but a changed `invalidAttachmentIndices`.
    - RED on HEAD: the field doesn't exist; once added to the class+copyWith but not `_composerStateEquals`, the `if (_composerStateEquals(...)) return;` short-circuit swallows the change and the chip never appears.
    - GREEN asserts: the strip reflects the new invalid set (red key appears) after only the set changed.
    - Mutation: omit the invalid-set comparison from `_composerStateEquals` → notifier short-circuits → no repaint → red. (Locks the BS-1b equality omission.)

## Test Coverage Matrix  (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 red chip + warning + caption + kept X | composer render (invalid) | widget | attachment_preview_strip_test::"invalid attachment renders a red border…" | params/red-branch absent → compile red | remove `invalidIndices.contains` branch | `./scripts/run_test_gates.sh 1to1` | **add attachment_preview_strip_test to `ONE_TO_ONE_TESTS`** |
| TC-02 no styling on valid (behavioral) | composer render (negative) | widget | attachment_preview_strip_test::"valid attachment shows no invalid styling" | shares TC-01 compile-red; **lock is mutation** | make red branch unconditional | `./scripts/run_test_gates.sh 1to1` | add to `ONE_TO_ONE_TESTS` |
| TC-03 X hidden during upload | composer render (preservation) | widget | attachment_preview_strip_test::"hides remove buttons during upload" | n/a (sentinel `:122`) | drop `!isUploading` guard on kept-X | `./scripts/run_test_gates.sh 1to1` | add to `ONE_TO_ONE_TESTS` |
| TC-04 group oversized → chip@pick, no snackbar, Send off | wired flow (group, pick-time) | integration/widget | group_conversation_wired_test::"oversized group pick marks the chip invalid at pick time…" | pick path runs no gate; chip/Send-off absent | revert gate→bool+snackbar; drop group onTap term | `./scripts/run_test_gates.sh groups` | already `GROUP_TESTS:131` |
| TC-05 1:1 oversized → chip@pick, no snackbar | wired flow (1:1, pick-time) | integration/widget | conversation_wired_test::"oversized 1:1 pick marks the chip invalid at pick time…" | pick path runs no gate | revert 1:1 gate→bool+snackbar | `./scripts/run_test_gates.sh 1to1` | already `ONE_TO_ONE_TESTS:63` |
| TC-05b 1:1 GIF → GIF chip caption | wired flow (1:1 GIF reason) | integration/widget | conversation_wired_test::"oversized 1:1 GIF pick marks the chip with the GIF caption…" | HEAD `_showGifTooLargeMessage` snackbar | collapse GIF→generic caption | `./scripts/run_test_gates.sh 1to1` | already `ONE_TO_ONE_TESTS:63` |
| TC-06 gate returns collection {index,reason} | seam contract (accessor) | integration/widget | group_/conversation_wired_test::"validate gate returns the collection of failing {index,reason}…" | gate returns `bool` | collapse→bool/first-failure; hardcode index 0 | `./scripts/run_test_gates.sh groups` + `1to1` | already registered |
| TC-07 group GIF chip caption | wired flow (GIF reason) | integration/widget | group_conversation_wired_test::"GIF-too-large group pick marks the chip with the GIF caption…" | HEAD `_showGifTooLargeMessage` snackbar | restore `_showGifTooLargeMessage()` | `./scripts/run_test_gates.sh groups` | already `GROUP_TESTS:131` |
| TC-08 3 snackbars dropped + #4 kept + inline present | snackbar removal (group) | integration/widget | group_conversation_wired_test::"the 3 redundant media snackbars are dropped…the text-retry snackbar still shows" | HEAD shows the 3 media snackbars | restore any one dropped call; or drop `failed_message_retry_failed` | `./scripts/run_test_gates.sh groups` | already `GROUP_TESTS:131` |
| TC-09 Send tap no-op while invalid (1:1) | Send-gating (onTap) | integration/widget | conversation_wired_test::"Send tap is a no-op while an invalid attachment is present…" | onTap gate has no invalid term | drop `&& !hasInvalidAttachment` from onTap | `./scripts/run_test_gates.sh 1to1` | already `ONE_TO_ONE_TESTS:63` |
| TC-10 tile upload-pending state | tile render (presence sentinel) | widget | media_grid_cell_test::"renders upload_pending media as an explicit upload state" | n/a (sentinel `:433`; inline-presence only) | (snackbar re-add does NOT re-red; presence half only) | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (`test/shared/widgets/**`) |
| TC-11 multi-invalid both chips, Send off until both gone | wired flow (mark-all) | integration/widget | conversation_/group_conversation_wired_test::"two oversized picks mark BOTH chips invalid…" | first-failure `bool` → ≤1 chip | restore first-failure short-circuit | `1to1` + `groups` | already registered |
| TC-12 index-shift on removal | wired flow (recompute) | integration/widget | conversation_wired_test::"removing a valid attachment shifts the invalid chip…" | `_removeAttachment` never recomputes invalid set | skip recompute-on-remove hook | `./scripts/run_test_gates.sh 1to1` | already `ONE_TO_ONE_TESTS:63` |
| TC-13 invalid-set-only change repaints | derived-state (equality) | integration/widget | conversation_wired_test::"changing only the invalid set (same attachments) repaints the strip" | `_composerStateEquals` short-circuit swallows the change | omit invalid-set from `_composerStateEquals` | `./scripts/run_test_gates.sh 1to1` | already `ONE_TO_ONE_TESTS:63` |

## Blind-Spot Sweep  (evergreen classes — row added OR justified)
- **Lifecycle / derived-state durability:** the invalid set is in-memory composer state. It is NOT persisted (no reopen/restart concern — pure pre-send state), BUT it is *derived* and lives in the SHARED `ConversationComposerViewState` behind a hand-written `_composerStateEquals` short-circuit. Covered by **TC-13** (a change to only the invalid set must repaint — locks the equality omission) + the pick-time/recompute design (the set is re-derived from the live list on add/remove, not snapshotted). N/A for process-restart (unpersisted by design).
- **Sibling-surface consistency:** the new gate touches the Send capability. Parallel affordances reconciled: **mic/voice** — `hasInvalidAttachment` is added to the **onTap only**, NOT the `_shouldShowSendButton` getter, so Send stays visible-but-inert and does NOT flip to the mic (TC-09 asserts the Send icon still shows + tap no-fire). **X/remove** stays enabled (TC-01/TC-12). **Both surfaces** locked: 1:1 (TC-05/09) and group (TC-04 mutation b). The shared strip renders identically on both; group-screen threading is locked by TC-04's chip-render assertion.
- **Destructive-action side-effects:** `_removeAttachment` is the only mutating affordance touched. **TC-12** asserts what changes (the invalid chip follows the correct remaining index) and what is preserved (survivors show no stale red). The recompute reuses the existing gate (no divergent copy). No disk/DB cleanup involved (composer state only).
- **Invariant re-verification under new transitions:** the new transitions are *pick* (set populates), *remove* (set recomputes/shifts), and *invalid→empty* (Send re-enables). TC-09 (remove-offender → full post-removal state), TC-11 (remove-one-of-two → other stays invalid), and TC-12 (index-shift) each assert the FULL post-transition state (red keys, warning icon, survivor count, Send tap behavior) — not just the headline Send flag.

## Invariants (locked by tests)
- INV-1: a size/GIF-rejected attachment renders an **inline red chip** (red border + warning + short caption) **at pick time** and is **retained** → TC-01/TC-04/TC-05/TC-05b/TC-07.
- INV-2: the invalid chip **keeps its remove X** when not uploading; the upload state still hides the X → TC-01/TC-03.
- INV-3: the validate gate yields a **collection of {index, reason}** with normalized reasons (empty when all valid), not a `bool`; group iterates `media` (no `validateAttachments` index loss) → TC-06.
- INV-4: a too-large/GIF rejection shows **no `SnackBar`** for the size/GIF copy — the chip carries the short caption → TC-04/TC-05/TC-05b/TC-07.
- INV-5: tapping **Send is a no-op** (callback not fired; Send icon still shown, not the mic) while ANY invalid attachment is present, on **both** surfaces, and re-enables once all are removed → TC-04(group mutation b)/TC-09(1:1)/TC-11.
- INV-6: the **3** redundant GROUP media snackbars (`media_still_unavailable`, `failed_media_retry_failed`, `failed_media_upload_pending_retry`) are **not shown** while the inline tile placeholder **is** shown; **`failed_message_retry_failed` IS still shown** → TC-08 (TC-10 supports the inline-presence half only).
- INV-7: the invalid set is **recomputed/shifted on removal** so the red chip always tracks the correct remaining attachment, and repaints when only the set changes → TC-12/TC-13.
- INV-8: **all** invalid attachments are marked (not just the first); Send stays disabled until all are removed → TC-11.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short`; add/rewrite the catalog tests; run the focused RED commands; confirm each fails for its documented reason (compile-red for TC-01/02/06/13; pick-no-chip for TC-04/05/05b/11/12; snackbar-present for TC-07/08; Send-fires for TC-09).
2. `attachment_preview_strip.dart`: add `final Set<int> invalidIndices` + `final Map<int,String> invalidReasons` (default `const {}`) to the ctor + thread `isInvalid`/`reasonText` into `_Thumbnail`. In `_Thumbnail`: when `isInvalid && !isUploading`, wrap in a red-bordered keyed container (`ValueKey('attachment-invalid-$index')`), overlay `Icons.error_outline`, and render the short caption from `invalidReasons[index]`→ `media_too_large_chip`/`media_gif_too_large_chip`. Leave the X condition (`!isUploading && onRemove != null`) intact.
3. l10n: add `media_too_large_chip` ("Too large") + `media_gif_too_large_chip` ("GIF too big") to `app_en.arb`/`app_ar.arb`/`app_de.arb` (append-by-key) and regenerate `app_localizations*`.
4. `compose_area.dart`: add `final bool hasInvalidAttachment = false`; fold `&& !widget.hasInvalidAttachment` into the **onTap null-gate (`:478-482`)** ONLY. Do NOT edit `_shouldShowSendButton` (`:286`). Stop-if: if a 3rd hard send-trigger exists beyond onTap + the `_onSendPressed:178` guard, gate it too (grep `onSend`/`_onSendPressed` callers first).
5. Define `MediaRejection{int index, String reason}` (small value type, e.g. in the conversation domain or inline). Refactor `_validatePendingMediaSizes` (`conversation_wired.dart:972`) to return `List<MediaRejection>` — drop the `return false`/snackbar, collect every failing index (it already iterates `media`), normalize reasons (`gif_size_exceeded`→`gif_too_large`; others→`too_large`).
6. Refactor `_validatePendingGroupMediaDescriptors` (`group_conversation_wired.dart:4634`) to return `List<MediaRejection>` — **unwind the `validateAttachments` delegation**: iterate `media` itself calling `GroupMediaSizePolicy.validateSize` per element to capture each index; keep the MIME loop's unsupported snackbar (out of per-chip scope) OR fold MIME as a reason (decide: keep snackbar to stay minimal). Whole-message overflow reasons (no single index) → a `MediaRejection(index:-1, reason:'too_large')`-style sentinel consumed as a strip-level note. Stop-if: a size reason has no chip mapping → add it to the normalization table, don't render blank.
7. Add the **pick-time hook**: in `_attemptAddPendingMedia` (group `:781`, 1:1 `:816`), after `_resolvePendingMediaCandidates`, run the gate over the resulting list and store the failing index set + reason map in composer state. Re-run the gate in `_removeAttachment` (group `:3283`, 1:1 `:3485`). Keep the `_onSend` pre-gate as a defensive snackbar-free re-check.
8. Thread the invalid set through the **shared** `ConversationComposerViewState`: add `invalidAttachmentIndices` (Set), `invalidAttachmentReasons` (Map), optional `stripLevelReason` to the class+ctor (`conversation_screen.dart:39-60`) and `copyWith` (`:62-84`); update BOTH `_updateComposerState` copyWith calls (1:1 `~:3511`, group `:3373`); **add the new fields to BOTH `_composerStateEquals`** (1:1 `:3526`, group `:3388`) via `setEquals`/`mapEquals`. Pass the set/reasons into `AttachmentPreviewStrip` at both render sites (`conversation_screen.dart:340-348`, `group_conversation_screen.dart:241-249`) and `hasInvalidAttachment: composerState.invalidAttachmentIndices.isNotEmpty` into `ComposeArea`.
9. `group_conversation_wired.dart`: delete the **3** redundant media snackbars — `media_still_unavailable` (`:2278`), `failed_media_retry_failed` (`:2376`,`:2410`), `failed_media_upload_pending_retry` (`:2387`). Keep the surrounding re-resolve/retry/status side-effects. **Do NOT touch `failed_message_retry_failed` (`:2444`).** Stop-if: a dropped string has NO inline tile equivalent → DO NOT drop (this is exactly why #4 stays).
10. `scripts/run_test_gates.sh`: add `"test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart"` to `ONE_TO_ONE_TESTS` (before the closing paren at `:65`).
11. Rerun direct → preservation → named gates; `flutter analyze`; `git diff --check`.

## Risks And Edge Cases
- **GROUP `validateAttachments` unwind** is the only hard refactor — the policy returns a bare `{isValid,reason}` and discards the index, so the gate MUST iterate `media`. Pinned by TC-06 (group), mutation "hardcode index 0".
- **`_composerStateEquals` omission** silently swallows invalid-set repaints (the field added to class+copyWith but not equals). Pinned by TC-13.
- **Index-drift on removal** — re-deriving the set from the live list on every add/remove (not snapshotting) eliminates the stale-index class. Pinned by TC-12.
- **Multi-invalid + whole-message overflow** — `total_media_size_exceeded` owns no index → strip-level note + Send-disabled (not a per-chip border). Pinned by TC-11 (Send stays disabled) + documented in Accepted Differences.
- **mic-vs-Send** — gating the onTap (not the visibility getter) keeps Send visible-but-inert and avoids a surprise mic. Pinned by TC-09 (Send icon shown + tap no-fire).
- **`failed_media_upload_pending_retry` is informational** (not red) — the upload-pending placeholder is adequate; do not mistake it for a lost error. Documented in Accepted Differences.
- **`find.text` vs `find.widgetWithText(SnackBar, …)`** — snackbar-absence assertions use `widgetWithText(SnackBar, …)` findsNothing; chip-caption assertions use a separate `find.text` on the SHORT key. (WidgetSpan/U+FFFC is not in play — composer chips are plain text.)
- **Shared `MediaGridCell`** — do NOT edit; only the composer strip + gates + ComposeArea + view-state + the 3 GROUP snackbars change.

## Device/Relay Proof Profile
host-only for closure. No OS-boundary / ML-KEM / relay / multi-device leg — all behavior is local composer render + a pure `bool`→collection seam + a pick-time hook + snackbar removal; no migration. No `integration_test/` scenario, no `check_reliability_simulation_discovery.sh` row.
Deferred device work: none. (A render-on-real-iOS RTL proof for the red chip would mirror 144's `*_proof_test.dart` precedent — NOT required for closure.)

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart \
  --plain-name 'invalid attachment renders a red border'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'oversized group pick marks the chip invalid at pick time'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'Send tap is a no-op while an invalid attachment is present'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'the 3 redundant media snackbars are dropped'

# Direct GREEN (after fix) — record baseline pass counts at RED time; assert baseline + N new
flutter test test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart   # prior 19 + new red-chip/index-shift cases
flutter test test/shared/widgets/media/media_grid_cell_test.dart                                   # sentinel, unchanged count
flutter test test/features/groups/presentation/group_conversation_wired_test.dart                  # + TC-04/06/07/08/11; 2 PRE-EXISTING fails (GMAR-004 reopen-hydration, incoming-group-image-refresh) NOT mine
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart          # + TC-05/05b/06/09/11/12/13

# Preservation + named gates (after adding attachment_preview_strip_test to ONE_TO_ONE_TESTS)
./scripts/run_test_gates.sh 1to1          # 1:1 family incl. the newly-registered strip test
./scripts/run_test_gates.sh groups        # groups family; the 2 PRE-EXISTING wired fails are NOT mine
./scripts/run_test_gates.sh feed          # LetterCard/MediaGrid feed variants stay green

# Hygiene
flutter analyze            # 0 new issues (incl. regenerated app_localizations*)
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the catalog tests before the fix — TC-01/02/06/13 compile-red; TC-04/05/05b/11/12 pick-no-chip; TC-07/08 snackbar-present; TC-09 Send-fires.
- Pre-existing dirty (NOT mine): `group_conversation_wired_test.dart` has 2 PRE-EXISTING failing wired tests on HEAD — `GMAR-004 reopen-hydration` (`:4019`) and `incoming-group-image-refresh` (`:4236`). Confirm the count at execution (they EXIST; "currently failing" is an execution-time observation). Record before execution; do not "fix" by reverting. The wider `new-feed` tree is already dirty (Feed/Orbit) — snapshot `git status --short` first; touch ONLY Real-Scope files.
- Environment blocker (NOT product): none (host-only).
- Scope drift (BLOCKING): any failure outside the listed files/tests, any edit to `media_grid_cell.dart`, the 1:1 hardcoded retry literals, the unsupported-MIME path, **dropping `failed_message_retry_failed`**, or any DB/migration touch.

## Done Criteria
- [x] RED added/rewritten first, failed for the expected reason (compile-red strip+helper; behavioral-red 1:1 pick + group source-wiring).
- [x] Each fix mutation-verified — onTap `!hasInvalidAttachment` (TC-09 re-red) + strip invalid branch (TC-01 re-red); plus RED-first for all; source-wiring re-reds on any re-added string.
- [x] Direct GREEN + 1to1/groups/feed preservation gates pass; the pre-existing wired fails unchanged (1:1 ×5, group ×2 — all baseline-confirmed on HEAD).
- [x] No migration introduced (DB stays v92).
- [x] `attachment_preview_strip_test.dart` (and the NEW `media_rejection_test.dart`) added to `ONE_TO_ONE_TESTS` and confirmed running in `./scripts/run_test_gates.sh 1to1` (+26 combined: 23 strip + 3 helper).
- [x] Exactly **3** redundant GROUP media snackbars dropped; the inline tile state still present (GIRD-002 updated → "Uploading media" present); **`failed_message_retry_failed` still shown** (source-wiring lock).
- [x] Gate returns the COLLECTION of {index,reason} (group iterates `media`, no `validateAttachments` index loss — `collectPendingMediaSizeRejections`); chip appears at PICK time (auto-derive in `_updateComposerState`); ALL invalid marked; invalid set recomputed on removal; `_composerStateEquals` extended with `setEquals`/`mapEquals` (see deviation note).
- [x] New short l10n keys (`media_too_large_chip`/`media_gif_too_large_chip`) ×en/ar/de added + regenerated; `flutter analyze` 0-new; `git diff --check` clean.

### Execution deviations from the plan (documented)
- **TC-06 home:** implemented as a dedicated PURE unit test (`test/features/conversation/domain/models/media_rejection_test.dart`) over the shared `collectPendingMediaSizeRejections`, NOT an in-wired `@visibleForTesting` accessor — the wired `State` classes are private (`_ConversationWiredState`/`_GroupConversationWiredState`), so `tester.state` is impossible. The pure function IS the collection gate both screens delegate to; registered in `ONE_TO_ONE_TESTS`. Group's per-index marking is additionally locked behaviorally by TC-04/TC-07/TC-11(group).
- **TC-08 shape:** split into (a) the existing GIRD-002 test UPDATED (behavioral inline-present lock: upload-pending snackbar gone, "Uploading media" placeholder present) + (b) a SOURCE-WIRING lock asserting the 3 dropped getters are absent from `group_conversation_wired.dart` and `.failed_message_retry_failed` is present. Driving `retried==0`/integrity-fail for real failed-media bubbles (paths A/B) is fragile; source-wiring + GIRD-002 cover INV-6 + the blocker deterministically.
- **TC-13:** the `setEquals`/`mapEquals` comparison WAS added to both `_composerStateEquals` (correctness/defense) but is NOT separately mutation-observable through public API: under the auto-derive design every invalid-set change co-occurs with a `pendingAttachments`-list change, which `_fileListsEqual` already catches, so no public flow produces "same files, different invalid set." Kept as defensive correctness; no isolated TC-13 test authored.
- **Auto-derive design:** the invalid set is re-derived inside `_updateComposerState` whenever the `pendingAttachments` param changes (one site; fires on pick/remove/seed/clear) rather than threading a recompute through every call site — strictly covers the plan's pick-time + recompute-on-remove intent with less drift surface.
- **Two pre-existing group tests UPDATED:** `send rejects an oversized non-GIF…` and `…GIF on final bytes…` asserted the now-removed send-time size/GIF snackbars; rewritten to assert the inline chip ("Too large"/"GIF too big") + no snackbar + no publish + retained.
- **Strip-level total-overflow note (FOLLOW-UP FIX, 2026-06-23):** my first pass dropped this (claimed "not needed"), which was WRONG — a review caught that GROUP sends still reject totals >500 MB (`kGroupMediaTotalMessageLimitBytes`) while the per-element chips can't represent a whole-message overflow that owns no index, so a user picking several individually-valid videos over 500 MB saw NO chip, an enabled Send, and silent rejection (the pre-149 `_showAttachmentTooLargeMessage` snackbar was gone). FIXED per the plan's Design Decision #2: added `hasTotalSizeOverflow` to the shared view-state (folded into `hasInvalidAttachment` → Send-disabled), auto-derived in the GROUP `_updateComposerState` (`fold` budget bytes vs the cap), rendered as a keyed strip-level note (`ValueKey('attachment-total-overflow')` + `media_attachments_too_large_note` ×en/ar/de) above the thumbnails. GROUP-only (1:1 has no separate message-total cap — its overflow is caught by the pick-time budget dialog). RED-first + mutation-verified (force-false → test re-reds). The composer-budget overflow keeps its existing `_showAttachmentTooLargeMessage` snackbar (unchanged path).

## Scope Guard (hard "Do not")
- Do not add a DB migration or bump `currentIdentityDatabaseVersion`.
- Do not edit `media_grid_cell.dart` or rebuild its placeholders (already done).
- Do not add a per-tile upload progress ring.
- Do not drop **`failed_message_retry_failed`** (text-retry path, no inline equivalent — BLOCKER).
- Do not touch the 1:1 hardcoded retry literals, the unsupported-MIME snackbar, or any 1:1 redundant-snackbar drop (1:1 has none).
- Do not add `hasInvalidAttachment` to the `_shouldShowSendButton` getter (would flip Send→mic) — onTap only.
- Do not keep a size/GIF snackbar "just in case" — the chip is the replacement (INV-4).

## Accepted Differences / Intentionally Out Of Scope
- **No per-tile upload progress ring** — no per-attachment byte source; `UploadProgressBanner` covers aggregate progress. Owner: a future per-attachment-progress session.
- **1:1 hardcoded retry literals left un-localized** — 1:1 keeps its snackbar-free tile re-render. Owner: an i18n-cleanup session.
- **Unsupported-MIME hard reject keeps its snackbar** (`group_media_unsupported`).
- **`failed_message_retry_failed` keeps its snackbar** — text-retry path with no inline tile; the snackbar is the sole feedback.
- **`failed_media_upload_pending_retry` was informational** (not red) — replaced by the upload-pending placeholder, which reads "Uploading media"; this is an intentional downgrade from a transient confirmation to a persistent inline state.
- **Whole-message overflow reasons** (`total_media_size_exceeded`/`media_size_exceeded`/`invalid_media_size`) own no single index → surfaced as a strip-level note + Send-disabled, not a per-chip border.
- **Per-chip reason taxonomy is `{too_large, gif_too_large}`** (the 5+ policy SEND-path reasons normalize into these two); no stored field.

## Dependency Impact
- None outbound. Adding `attachment_preview_strip_test.dart` to `ONE_TO_ONE_TESTS` retroactively gates ALL pre-existing composer-strip behavior under the curated 1:1 gate — a standalone hardening win. The `bool`→`List<MediaRejection>` seam + the new `invalidAttachmentIndices`/`invalidAttachmentReasons` fields on the SHARED `ConversationComposerViewState` are internal to the two wired screens (no cross-feature consumer); the two new l10n keys are additive.

## Reviewer Findings
9-agent verify→refute Workflow (2026-06-23): core claims (gate shapes, strip no-error-state, ComposeArea split, registration absence, sentinels, l10n key existence) CONFIRMED. **1 BLOCKER fixed**: `failed_message_retry_failed` removed from the drop list (text-retry path, no inline tile equivalent — `showFailedTextRetry` requires `messageMedia.isEmpty`). **3 design forks resolved with owner**: pick-time trigger, mark-all-invalid (collection), short l10n keys. **4 majors folded**: group `validateAttachments` index loss (gate must iterate `media`); single↔Set mismatch (→ `List<MediaRejection>`); shared `_composerStateEquals` omission (→ explicit field + TC-13); `_removeAttachment` index-drift (→ recompute + TC-12). **Test-rigor fixed**: TC-02 RED reclassified as mutation-locked; TC-06 committed to a `@visibleForTesting` accessor + multi-element setup; TC-08 corrected to 3-dropped + #4-kept + inline-presence-in-same-flow + per-string assertions; TC-09 strengthened to tap-no-fire + full post-removal state; TC-10 relabeled inline-presence-only. **Line drift corrected** (group file ~80 lines stale; snackbar lines re-located by l10n key; strip test count 19 not 20; gate-array bounds `:65`/`:132`). Matrix has zero empty cells; every INV maps to a TC; blind-spot sweep rows added (TC-12/13 + sibling/mic reconciliation).

## Arbiter Decision
Structural blockers: none after revision. | Deferred details: per-tile progress ring + 1:1 literal localization (owners named). | Accepted differences: progress ring, 1:1 literals, unsupported-MIME snackbar, `failed_message_retry_failed` snackbar, informational-snackbar downgrade, whole-message-overflow strip note. | Hard parts flagged for execution: GROUP `validateAttachments` unwind (TC-06 group), shared `_composerStateEquals` threading (TC-13), pick-time hook in `_attemptAddPendingMedia` both surfaces.

## Final Execution Verdict
Verdict: **IMPLEMENTED host-green** (uncommitted on `new-feed`, no migration — DB stays v92).
Files changed (prod): NEW `lib/features/conversation/domain/models/media_rejection.dart`; `attachment_preview_strip.dart`; `compose_area.dart`; `conversation_screen.dart`; `group_conversation_screen.dart`; `conversation_wired.dart`; `group_conversation_wired.dart`; `app_en/ar/de.arb` (+ regenerated `app_localizations*`).
Files changed (tests/infra): NEW `media_rejection_test.dart`; `attachment_preview_strip_test.dart` (+4); `conversation_wired_test.dart` (+5); `group_conversation_wired_test.dart` (+4 new, 3 existing updated: 2 size-snackbar + GIRD-002); `scripts/run_test_gates.sh` (registered strip + media_rejection in `ONE_TO_ONE_TESTS`).
Tests run (+counts): strip 26/26 (incl. 3 direct `hasTotalSizeOverflow` widget tests + 3 chip tests) · media_rejection 3/3 · conversation_screen 71/71 · conversation_wired 1:1 +91/−5 PRE-EXISTING · group_conversation_wired +155/−2 PRE-EXISTING · feed gate 214/214 · 1to1 gate 1163 pass/5 pre-existing · groups gate 155/2 pre-existing. flutter analyze 0-new. git diff --check clean.
Blocking: none — **zero regressions from 149** (isolation-confirmed). NOT-MINE failures in the shared tree:
- 1:1 ×5 ("shows message immediately…", "delivered status…", "two ticks…", "repository change…reply status", "retry control re-sends…") are caused by a **CONCURRENT, unrelated `155-status-glyph` session** editing the SHARED `letter_card.dart` (retires the `done_all` delivered tick + changes `_statusIcon`) without yet updating these status-assertion tests. PROOF: reverting ONLY `letter_card.dart` (keeping all my 149 code) → `conversation_wired_test` = **+96 ALL PASS**. These belong to the 155 author, not 149.
- group ×2 (GMAR-004 reopen-hydration `:4019`, incoming-group-image-refresh `:4236`) are clean-HEAD pre-existing (media-hydration, unaffected by the 1:1-only 155 glyph; documented in the plan).
NOTE: the working tree also contains concurrent untracked `Test-Flight-Improv/155-…-tdd-plan.md` + `letter_card.dart`/`letter_card_test.dart`/`app_en.arb` edits from that other session — left untouched (out of 149 scope).
Mutation-verified: onTap `!hasInvalidAttachment` (TC-09 re-red), strip invalid-branch (TC-01 re-red); RED-first captured for all.
QA verdict: SHIP (host-only closure; no device-proof required per profile). Non-blocking follow-ups (owner): per-attachment progress ring; 1:1 retry-literal i18n.
