# 149 - Media error feedback inline (composer reject-chip for too-large/GIF + drop redundant tile-duplicate snackbars)  (Bug | Feature Improvement)

Status: awaiting-review
Spec: free-text intent (no formal spec) — chained from a UI/UX review of Group Messaging snackbars

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | attachment_preview_strip.dart(+test), conversation_wired.dart, group_conversation_wired.dart, conversation_screen.dart, group_conversation_screen.dart, compose_area.dart, media_grid_cell.dart(+test), app_en/ar/de.arb, run_test_gates.sh | verify→refute (post-refute brief): tile upload-pending/unavailable/retry + UploadProgressBanner ALREADY exist (OUT); genuine gaps = composer reject-chip (too-large/GIF) + redundant GROUP snackbar drop. No migration. `attachment_preview_strip_test.dart` LOCKS old behavior + has NO curated gate owner. `group_conversation_wired_test.dart` IS already in `GROUP_TESTS:131` (144's reg landed). | Planner |
| 2026-06-23 | Planner | (as above) | Refactor both validate gates from `bool`→`MediaRejection?{index,reason}`; AttachmentPreviewStrip gains per-index invalid state (red border + warning + KEPT X); ComposeArea Send disabled while invalid present; drop 4 redundant GROUP snackbars whose tile already conveys state; localize the 3 hardcoded 1:1 retry literals only if folded inline (kept OUT — see Accepted Differences). | Reviewer |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline below (UX review → user-locked design decisions)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no sim rows in this plan)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (next-free = 149; files go to 148)

## Session Classification
implementation-ready (host-only closure; no migration, no device-proof — all behavior is local composer render + a `bool`→struct seam refactor + snackbar removal)

## Exact Problem Statement
When a user picks an attachment that fails a size policy, the rejection is surfaced as a **transient floating SnackBar** and the offending attachment is **silently discarded** — the user is never told *which* of several picked attachments was too large, and (if the snackbar is missed) believes everything is queued. **GROUP:** `_validatePendingGroupMediaDescriptors` (`group_conversation_wired.dart:4554-4606`) returns `bool` and routes the **first** failure to `_showAttachmentTooLargeMessage` (`media_too_large_after_compress`, `:1090-1095`) or `_showGifTooLargeMessage` (`media_gif_too_large`, `:1148-1152`). **1:1:** `_validatePendingMediaSizes` (`conversation_wired.dart:972-994`) is the same `bool`/first-failure shape, routing to the 1:1 copies of those messages (`:904`/`:961`). The composer preview strip `AttachmentPreviewStrip._Thumbnail` (`attachment_preview_strip.dart:61-176`) has **no error/red state** — it can only show the upload scrim+spinner (`:114-132`) and hides its X (remove) button during upload (`:154`).

Separately, **GROUP** retry/unavailable flows fire **error SnackBars whose state the media tile already conveys inline**: `media_still_unavailable` (`group_conversation_wired.dart:2262`), `failed_media_retry_failed` (`:2361`/`:2395`), `failed_media_upload_pending_retry` (`:2372`), `failed_message_retry_failed` (`:2429`). The shared tile `MediaGridCell` already renders an explicit upload-pending placeholder (`media_grid_cell.dart:252-300`, `upload_progress_title`/`post_media_pending_upload_desc`) and an unavailable+retry placeholder (`:318-378`, `Icons.broken_image_outlined` + `media_could_not_verify`/`media_unavailable` + a keyed retry button `unavailable-media-retry-…`). So those snackbars are redundant doubles of an inline state.

What must improve:
- A size/GIF rejection marks the **specific** picked attachment with an **inline red error chip** in the composer (red border + warning icon, X/remove **kept**) and **disables Send** while an invalid attachment is present — instead of a discard + floating snackbar. The validate gate must surface **which index** failed and **why** (`reason`), not just a `bool`.
- The now-redundant **GROUP** error snackbars whose state the tile already shows inline are removed.

What must stay unchanged (→ preserved-green sentinels):
- The tile's existing upload-pending placeholder (`media_grid_cell_test.dart:433` "renders upload_pending media as an explicit upload state"), unavailable+retry placeholder, and retry-button wiring (`onRetryUnavailableMedia` thread `letter_card.dart:367` → `media_grid.dart` → `MediaGridCell:367`).
- `UploadProgressBanner` (above-composer aggregate progress + cancel) — NOT duplicated per-tile (Accepted Difference: there is no per-attachment byte source; `UploadProgressViewState` is a single aggregate).
- The `GroupMediaMimePolicy.validateDescriptor` **unsupported-MIME** path (`group_conversation_wired.dart:4561-4571`, snackbar `group_media_unsupported`) — a hard reject of a never-displayable file, NOT a per-chip size reason; out of scope, stays a snackbar.
- The 1:1 hardcoded retry literals (`conversation_wired.dart:2496`/`:2508`) — left as-is (no inline tile-duplicate to drop on the 1:1 side; localizing them is a separate i18n cleanup, see Accepted Differences).
- 1:1 / group / feed gates, `flutter analyze` 0-new.

## Root Cause (verify → refute confirmed)
**Confirmed on HEAD (tree dirty on `new-feed`, but these files' rejection logic is committed/inherited, NOT field build-skew):**
- The validate gates are **boolean / first-failure** and **side-effect the snackbar inside the gate**: `group_conversation_wired.dart:4571` (`return false` after `_showFloatingSnackBar(group_media_unsupported)`), `:4598-4604` (`_showGifTooLargeMessage`/`_showAttachmentTooLargeMessage` then `return false`); `conversation_wired.dart:986-991` (same). Callers consume only the `bool` and **abort the whole send** (`group_conversation_wired.dart:1851`, `conversation_wired.dart:1928`), so the failing attachment is never identified to the UI; the picked attachments stay in `pendingAttachments` only because the send aborts, but the user gets no per-item signal.
- `AttachmentPreviewStrip` has **no invalid/error parameter**: `_Thumbnail` only knows `isUploading` (`:63`) and `onRemove` (`:64`); there is no per-index error set, no red border, no warning icon. Its X is **conditionally hidden** (`:154`, `if (!isUploading && onRemove != null)`) — the chip cannot show "invalid but still removable".
- `ComposeArea` Send enable is purely `(_hasText || hasAttachments) && !isProcessing && !isSending && !_isRecording` (`compose_area.dart:286`,`:478-481`) — it has **no notion of an invalid attachment**, so Send stays enabled even when a too-large file sits in the strip (the gate re-rejects on press, snackbar again).
- GROUP redundant snackbars: `media_still_unavailable` (`:2262`), `failed_media_retry_failed` (`:2361`,`:2395`), `failed_media_upload_pending_retry` (`:2372`), `failed_message_retry_failed` (`:2429`) fire **in addition to** the tile already rendering the matching inline state (`media_grid_cell.dart:252-300` upload-pending, `:318-378` unavailable+retry).

Refuted / do-NOT-re-introduce:
- ❌ "the tile has no inline upload/unavailable/retry state — build it" — **ALREADY DONE**: `media_grid_cell.dart:252-300` (`_buildUploadPendingPlaceholder`) + `:318-378` (`_buildUnavailablePlaceholder` with keyed retry `:357` gated by `_canRetryUnavailableMedia` `:199-201`). Test `media_grid_cell_test.dart:433` locks it. Do NOT rebuild.
- ❌ "add a per-tile upload progress ring" — **WRONG**: there is no per-attachment byte source (`UploadProgressViewState` is a single aggregate); a per-tile ring would duplicate `UploadProgressBanner` (rendered above the composer at `group_conversation_screen.dart:213`-region / `conversation_screen.dart:302`-region). Accepted Difference, not a gap.
- ❌ "the X is always shown, just style it red" — **FALSE**: the X is hidden during upload (`attachment_preview_strip.dart:154`). The invalid chip must KEEP its X *without* entering the upload branch — a NEW state, not a style tweak. Locked test `attachment_preview_strip_test.dart:122` ("hides remove buttons during upload") stays green; the new red-chip test asserts X present in the *invalid-not-uploading* state.
- ❌ "1:1 has the same redundant snackbars to drop" — **FALSE**: `conversation_wired.dart` has NONE of `media_still_unavailable`/`failed_media_retry_failed`/`failed_media_upload_pending_retry`/`failed_message_retry_failed`; it uses HARDCODED ENGLISH literals (`'Retry unavailable right now.'` `:2508`, `'Could not retry media message.'` `:2496`) and lets the tile re-render unavailable inline (no error snackbar). Snackbar-drop is **GROUP-only**.
- ❌ "MediaGridCell forks between 1:1 and group, edit each copy" — **FALSE**: `MediaGridCell` is shared 1:1+group via `MediaGrid`/`letter_card.dart:367`; the only fork is `requireVerifiedContentHash` (group `true` at `group_conversation_screen.dart:654`; default `false` at `media_grid_cell.dart:43`). Do NOT cite `letter_card_group.dart:69` (that is a FEED widget, wrong surface).
- ❌ "needs a migration for an attachment error column" — **FALSE**: rejection state is **pre-send composer state**, never persisted. Pure presentation. DB stays v92; no 093.

## Real Scope
In scope:
- **Seam refactor (both surfaces):** change `_validatePendingGroupMediaDescriptors` (`group_conversation_wired.dart:4554`) and `_validatePendingMediaSizes` (`conversation_wired.dart:972`) from `bool` to return a small value `MediaRejection?` (`null` == all-valid; else `{int index, String reason}` where `reason ∈ {too_large, gif_too_large, unsupported_mime}`). The `MediaAttachment.id == pending.file.path` mapping (`group_conversation_wired.dart:4577`) makes a path→index recovery trivial; the size policy iterates `media` in order so the failing index is known at the failure site. Keep the gate **side-effect-free of snackbars** for the size/GIF reasons (the chip renders them); the unsupported-MIME reason MAY keep its snackbar (out of per-chip scope).
- **NEW composer reject-chip:** `AttachmentPreviewStrip` gains `Set<int> invalidIndices` (or `Map<int,String> invalidReasons`) + renders, on an invalid index, a **red border** + a small **warning icon overlay** + **keeps the X** (remove affordance) even though not uploading. The two size l10n keys (`media_too_large_after_compress`, `media_gif_too_large`) are rendered **on/under the chip** (e.g. tooltip/caption), not as a snackbar.
- **Send gating:** thread the invalid-present flag into `ComposeArea` so Send is **disabled while any invalid attachment is present** (`compose_area.dart:286`/`:478-481` enable condition gains `&& !hasInvalidAttachment`).
- **State wiring:** the two wired screens hold the invalid set (computed by the refactored gate at pick time / on `_onSend` pre-gate), pass it through `ConversationComposerViewState` / the group composer state into the screen, into `AttachmentPreviewStrip`, and clear an index's invalid flag when that attachment is removed.
- **Drop redundant GROUP snackbars** (only where the tile already conveys the state inline): `media_still_unavailable` (`group_conversation_wired.dart:2262`), `failed_media_retry_failed` (`:2361`,`:2395`), `failed_media_upload_pending_retry` (`:2372`), `failed_message_retry_failed` (`:2429`).
- **Tests:** rewrite `attachment_preview_strip_test.dart` for the red-chip + kept-X contract; add validate-gate-returns-struct cases (group + 1:1); add wired "too-large → chip not snackbar" cases (group + 1:1); add snackbar-drop locks (group).
- **Harness registration:** add `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart` to `ONE_TO_ONE_TESTS` (composer strip is shared; 1:1 family is the natural owner). `media_grid_cell_test.dart` is auto-globbed. `group_conversation_wired_test.dart` (`:131`) and `conversation_wired_test.dart` (`:63`) are already registered.

Out of scope (owner named):
- **Per-tile upload progress ring** — no per-attachment byte source; `UploadProgressBanner` already covers it. Owner: a future "per-attachment progress" session if a per-item byte stream is ever added.
- **Localizing the 1:1 hardcoded retry literals** (`conversation_wired.dart:2496`/`:2508`/`:2535`) — only needed if 1:1 retry copy is folded inline, which this plan does NOT do (1:1 keeps its snackbar-free tile re-render). Owner: an i18n-cleanup session.
- **A persisted-failed-reaction / any DB schema change** — no migration here.
- The unsupported-MIME hard reject (`group_media_unsupported`) keeping a snackbar — accepted.

## Files To Inspect Next
Production:
- `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart` — `_Thumbnail` `:61-176` (add invalid state: red border, warning icon, keep X out of the `isUploading` branch); `AttachmentPreviewStrip` ctor `:21-30` + `itemBuilder` `:42-55` (thread `invalidIndices`).
- `lib/features/conversation/presentation/widgets/compose_area.dart` — Send enable `:286`,`:478-481`; ctor flags `:26-53` (add `hasInvalidAttachment`).
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — gate `_validatePendingGroupMediaDescriptors` `:4554-4606`; caller `:1851`; too-large/GIF messages `:1090-1095`/`:1148-1152`; redundant snackbars `:2262`,`:2361`,`:2372`,`:2395`,`:2429`; unsupported-MIME path `:4561-4571` (keep).
- `lib/features/conversation/presentation/screens/conversation_wired.dart` — gate `_validatePendingMediaSizes` `:972-994`; caller `:1928`; too-large/GIF messages `:899`/`:957`-region (`:904`/`:961`); hardcoded retry literals `:2496`/`:2508` (NOT edited).
- `lib/features/groups/presentation/screens/group_conversation_screen.dart` — `AttachmentPreviewStrip` render `:241-249`; composer section `:236-`; ctor flags `:62-67`,`:130-135`,`:175`,`:248`.
- `lib/features/conversation/presentation/screens/conversation_screen.dart` — `AttachmentPreviewStrip` render `:340-348`; `ConversationComposerViewState` `:41-75`,`:118-119`; Send-area context `:354`+.
- `lib/shared/widgets/media/media_grid_cell.dart` — INSPECT ONLY (shared tile, already has the inline placeholders `:252-300`/`:318-378`); confirm the dropped snackbars are duplicated by these.
- `lib/l10n/app_en.arb` / `app_ar.arb` / `app_de.arb` — append-by-key (line offsets diverge en vs ar/de). Reuse existing `media_too_large_after_compress` (`:421`) + `media_gif_too_large` (`:422`) on the chip; OPTIONAL new short remove tooltip key only if needed (prefer reuse — no new key planned unless the chip caption needs a distinct string).
Direct tests:
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart` — rewrite (locks old behavior); add red-chip + kept-X cases.
- `test/features/groups/presentation/group_conversation_wired_test.dart` — add gate-struct + too-large-chip-not-snackbar + snackbar-drop cases.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart` — add gate-struct + too-large-chip-not-snackbar (1:1).
- `test/shared/widgets/media/media_grid_cell_test.dart` — sentinel only (`:433` upload-pending), no edit.
Dependency-only context:
- `lib/features/groups/domain/group_media_size_policy.dart` / `group_media_mime_policy.dart` (reason strings `gif_size_exceeded` etc. — not edited; the gate maps them to chip reasons).

## Existing Tests Covering This Area
- `attachment_preview_strip_test.dart:113` "shows remove buttons when not uploading" (3 X) — PASSES; **kept**, the red chip must not break the not-uploading X count.
- `attachment_preview_strip_test.dart:122` "hides remove buttons during upload" (X findsNothing) — PASSES; **kept** (invalid chip is a distinct state from uploading; X still hidden during upload). **Locks the old "no error state" assumption only implicitly** — no error param exists, so the red-chip behavior is uncovered → must ADD.
- `attachment_preview_strip_test.dart:135` "shows upload overlay spinner during upload" / `:144` "no spinner when not uploading" / `:153` "onRemove fires with correct index" / `:191` "GIF thumbnail shows a GIF badge" / `:209` "GIF badge hidden during upload" / `:222` "no remove buttons when onRemove is null" / processing cases `:231-354` — PASS; **kept** as preservation (red-chip must not perturb them).
- `media_grid_cell_test.dart:433` "renders upload_pending media as an explicit upload state" — PASSES; **sentinel** (proves the tile already conveys upload state; basis for dropping `failed_media_upload_pending_retry`). Plus the unavailable/`broken_image_outlined`/retry cases (`:493`,`:525`,`:603`,`:634`,`:664`) — sentinels for dropping `media_still_unavailable`/`failed_media_retry_failed`.
- `group_conversation_wired_test.dart` — has terminal/media tests (144 family) but NO test that a too-large pick shows a chip instead of a snackbar, and NO snackbar-drop lock for the 4 redundant snackbars → gaps.
- `conversation_wired_test.dart` — no too-large-chip test → gap.

Missing coverage gaps: composer **red chip** (border + warning + **kept X**) on an invalid index; **Send disabled** while invalid present; validate gate returns **{index, reason}** not `bool` (group + 1:1); too-large/GIF pick shows **chip not snackbar** (group + 1:1); the 4 redundant GROUP snackbars **not shown** (locks).

Already in curated family arrays?:
- `attachment_preview_strip_test.dart` — ❌ **NOT** in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:17-63`) nor `GROUP_TESTS` (`:116-131`). It auto-globs only under whole-`test/`-dir discovery, not the curated 1:1/group gate. → **registration step required** (add to `ONE_TO_ONE_TESTS`).
- `group_conversation_wired_test.dart` — ✅ in `GROUP_TESTS` (`:131`, 144's reg already landed; **brief's "not present" note is stale** — recorded, no action).
- `conversation_wired_test.dart` — ✅ in `ONE_TO_ONE_TESTS` (`:63`).
- `media_grid_cell_test.dart` — ✅ AUTO (regex glob for `test/shared/widgets/**`).

## RED Test Catalog  (add/rewrite BEFORE any production code — INV-RED-FIRST)

1. `attachment_preview_strip_test.dart`::"invalid attachment renders a red border, a warning icon, and keeps its remove X"  *(NEW)*
   - Tier: widget
   - Shape/setup: pump `AttachmentPreviewStrip(attachments:[file], isUploading:false, invalidIndices:{0}, onRemove:(_){})`; pump.
   - RED on HEAD because: `invalidIndices` (and the red-border/warning render branch) does not exist on `AttachmentPreviewStrip` → compile-time red.
   - GREEN after fix asserts: the chip shows a red border (assert via a keyed `Container`/`DecoratedBox` `ValueKey('attachment-invalid-0')` carrying a red `Border`), a warning icon (`find.byIcon(Icons.error_outline)` or `Icons.warning_amber_rounded` — pick one and lock it), AND the remove X is present (`find.byIcon(Icons.close)` `findsOneWidget`).
   - Mutation that re-reds: remove the `invalidIndices.contains(index)` red-border/warning branch in `_Thumbnail` → no red key → red.
   - Distinct-state discriminator: assert the chip is NOT in the upload branch — `find.byType(CircularProgressIndicator)` `findsNothing` (the invalid state is distinct from uploading).

2. `attachment_preview_strip_test.dart`::"valid attachment shows no invalid styling"  *(NEW, negative)*
   - Tier: widget
   - Shape/setup: `invalidIndices:{}` with 3 files.
   - RED on HEAD because: the keyed invalid container doesn't exist (compile red on the shared symbol once test 1 introduces it; before that, asserting `findsNothing` on the red key fails to compile too) — bound to the same param.
   - GREEN asserts: `find.byKey(const ValueKey('attachment-invalid-0'))` `findsNothing`; X present (3); no warning icon.
   - Mutation: make the red branch unconditional (ignore `invalidIndices`) → red key appears on a valid chip → red.

3. `attachment_preview_strip_test.dart`::"hides remove buttons during upload"  *(PRESERVATION — existing `:122`, kept green)*
   - Tier: widget
   - Asserts unchanged: `isUploading:true` → `find.byIcon(Icons.close)` `findsNothing`. Guards that the kept-X-when-invalid change does NOT leak the X into the upload state.
   - Mutation: if the new X-keep logic drops the `!isUploading` guard, this reds.

4. `group_conversation_wired_test.dart`::"too-large group attachment marks the chip invalid and shows no too-large snackbar"  *(NEW)*
   - Tier: integration/widget (wired screen, fakes + real migrations in setUp)
   - Shape/setup: pick an attachment whose `budgetBytes` exceeds the size policy; drive `_onSend`; pump.
   - RED on HEAD because: HEAD calls `_showAttachmentTooLargeMessage` (`media_too_large_after_compress` snackbar) and the strip has no invalid state; asserting the chip invalid + `find.text(<too-large copy>)` appears as a CHIP caption (not a `SnackBar`) + `find.widgetWithText(SnackBar, …)` `findsNothing` fails.
   - GREEN asserts: the composer strip shows the invalid chip for the picked attachment; the too-large copy is rendered inline (chip caption), NOT inside a `SnackBar`; Send is disabled (assert the ComposeArea send affordance disabled / `hasInvalidAttachment` true); the attachment is **retained** in the strip (not discarded).
   - Mutation: revert the gate to `bool` + restore `_showAttachmentTooLargeMessage()` → snackbar returns, chip gone → red.
   - Distinct-event discriminator: assert NO `SnackBar` containing the too-large copy AND the chip caption text present (chip ≠ snackbar).

5. `conversation_wired_test.dart`::"too-large 1:1 attachment marks the chip invalid and shows no too-large snackbar"  *(NEW)*
   - Tier: integration/widget
   - Shape/setup: 1:1 mirror of TC-04 (oversized pick → `_onSend`).
   - RED on HEAD because: HEAD `_validatePendingMediaSizes` returns `bool` + `_showAttachmentTooLargeMessage` snackbar; new asserts fail.
   - GREEN asserts: invalid chip present, inline too-large copy (not in `SnackBar`), Send disabled, attachment retained.
   - Mutation: revert 1:1 gate to `bool` + restore snackbar → red.

6. `group_conversation_wired_test.dart`::"validate gate returns the failing index and reason, not a bool"  *(NEW — seam unit-ish via wired harness)*
   - Tier: integration/widget (exercise the gate via the wired State, asserting on observed effect since the method is private; OR a `@visibleForTesting` accessor returning the `MediaRejection?`)
   - Shape/setup: two valid + one oversized GIF at index 1; invoke the gate.
   - RED on HEAD because: the gate returns `bool` (no index/reason) → the assertion that index==1 and reason=='gif_too_large' has nothing to read → compile/contract red.
   - GREEN asserts: rejection.index == the oversized item's index; rejection.reason maps GIF→`gif_too_large`, plain oversize→`too_large`; `null` when all valid.
   - Mutation: collapse the struct back to `bool` (or hardcode index 0) → wrong index → red.

7. `group_conversation_wired_test.dart`::"GIF-too-large group pick marks the chip invalid with the GIF copy (not a snackbar)"  *(NEW)*
   - Tier: integration/widget
   - RED on HEAD because: HEAD routes `gif_size_exceeded`→`_showGifTooLargeMessage` snackbar (`media_gif_too_large`); asserting the GIF copy on the chip + no `SnackBar` fails.
   - GREEN asserts: invalid chip for the GIF index; `media_gif_too_large` copy rendered inline; no `SnackBar` with that copy.
   - Mutation: restore `_showGifTooLargeMessage()` in the gate → snackbar returns → red.

8. `group_conversation_wired_test.dart`::"redundant media-state snackbars are dropped (tile conveys state)"  *(NEW — snackbar-drop lock)*
   - Tier: integration/widget
   - Shape/setup: drive the four redundant paths: (a) refreshed media still unavailable (`:2262`), (b) failed-media retry fails (`:2361`/`:2395`), (c) failed-media upload pending retry (`:2372`), (d) failed-message retry fails (`:2429`).
   - RED on HEAD because: HEAD shows these snackbars; asserting `find.widgetWithText(SnackBar, <each l10n string>)` `findsNothing` fails (HEAD shows them).
   - GREEN asserts: none of `media_still_unavailable` / `failed_media_retry_failed` / `failed_media_upload_pending_retry` / `failed_message_retry_failed` appears in a `SnackBar`; the underlying retry/refresh side-effects (re-resolve, status change) still occur.
   - Mutation: restore any one `_showFloatingSnackBar(...)` call → that string reappears in a SnackBar → red.
   - Distinct-event discriminator: assert the inline tile state still present (e.g. the unavailable placeholder / `broken_image_outlined` for the unavailable case) AND the snackbar absent — proves state moved inline, not lost.

9. `conversation_wired_test.dart`::"Send stays disabled while an invalid attachment is present (1:1)"  *(NEW — Send-gating lock)*
   - Tier: integration/widget
   - RED on HEAD because: `ComposeArea` Send enable has no `hasInvalidAttachment` term → with an oversized pick present, Send is enabled (it only re-rejects on press) → asserting disabled fails.
   - GREEN asserts: with an invalid chip present, the send affordance is disabled; after removing the offending attachment, Send re-enables (if text/other valid attachments remain).
   - Mutation: drop the `&& !hasInvalidAttachment` term from the enable condition → Send enabled → red.

10. `media_grid_cell_test.dart`::"renders upload_pending media as an explicit upload state"  *(PRESERVATION — existing `:433`, kept green)*
    - Tier: widget
    - Asserts unchanged: `find.text('Uploading media')` + `find.text('Recipients will receive this after the upload finishes.')` + no `broken_image_outlined`. Sentinel proving the tile already conveys the upload-pending state that `failed_media_upload_pending_retry` duplicated.

## Test Coverage Matrix  (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 red chip + kept X | composer render (invalid state) | widget | attachment_preview_strip_test::"invalid attachment renders a red border, a warning icon, and keeps its remove X" | `invalidIndices`/red-branch absent → compile red | remove `invalidIndices.contains` red/warning branch | `./scripts/run_test_gates.sh 1to1` | **add attachment_preview_strip_test to `ONE_TO_ONE_TESTS`** |
| TC-02 no-invalid styling on valid | composer render (negative) | widget | attachment_preview_strip_test::"valid attachment shows no invalid styling" | red key absent → compile red on shared param | make red branch unconditional | `./scripts/run_test_gates.sh 1to1` | add to `ONE_TO_ONE_TESTS` |
| TC-03 X hidden during upload | composer render (preservation) | widget | attachment_preview_strip_test::"hides remove buttons during upload" | n/a (sentinel `:122`) | drop `!isUploading` guard on kept-X | `./scripts/run_test_gates.sh 1to1` | add to `ONE_TO_ONE_TESTS` |
| TC-04 group too-large → chip not snackbar | wired flow (group) | integration/widget | group_conversation_wired_test::"too-large group attachment marks the chip invalid …" | HEAD `_showAttachmentTooLargeMessage` snackbar + no chip | revert gate→bool + restore snackbar | `./scripts/run_test_gates.sh groups` | already in `GROUP_TESTS:131` |
| TC-05 1:1 too-large → chip not snackbar | wired flow (1:1) | integration/widget | conversation_wired_test::"too-large 1:1 attachment marks the chip invalid …" | HEAD `bool` gate + too-large snackbar | revert 1:1 gate→bool + restore snackbar | `./scripts/run_test_gates.sh 1to1` | already in `ONE_TO_ONE_TESTS:63` |
| TC-06 gate returns {index,reason} | seam contract | integration/widget | group_conversation_wired_test::"validate gate returns the failing index and reason, not a bool" | gate returns `bool` (no index/reason) | collapse struct→bool / hardcode index 0 | `./scripts/run_test_gates.sh groups` | already in `GROUP_TESTS:131` |
| TC-07 group GIF-too-large chip copy | wired flow (GIF reason) | integration/widget | group_conversation_wired_test::"GIF-too-large group pick marks the chip invalid with the GIF copy …" | HEAD `_showGifTooLargeMessage` snackbar | restore `_showGifTooLargeMessage()` | `./scripts/run_test_gates.sh groups` | already in `GROUP_TESTS:131` |
| TC-08 redundant snackbars dropped | snackbar removal (group) | integration/widget | group_conversation_wired_test::"redundant media-state snackbars are dropped …" | HEAD shows the 4 snackbars | restore any one `_showFloatingSnackBar(...)` | `./scripts/run_test_gates.sh groups` | already in `GROUP_TESTS:131` |
| TC-09 Send disabled while invalid | Send-gating (1:1) | integration/widget | conversation_wired_test::"Send stays disabled while an invalid attachment is present (1:1)" | `ComposeArea` enable has no invalid term | drop `&& !hasInvalidAttachment` | `./scripts/run_test_gates.sh 1to1` | already in `ONE_TO_ONE_TESTS:63` |
| TC-10 tile upload-pending state | tile render (preservation) | widget | media_grid_cell_test::"renders upload_pending media as an explicit upload state" | n/a (sentinel `:433`) | (re-add `failed_media_upload_pending_retry` snackbar would not red THIS; this guards inline-state presence) | `./scripts/run_host_test_gates.sh feature-host-all` (AUTO glob) | AUTO (`test/shared/widgets/**` glob) |

## Invariants (locked by tests)
- INV-1: a size/GIF-rejected attachment renders an **inline red chip** (red border + warning) and is **retained** (never silently discarded) → TC-01/TC-04/TC-05/TC-07.
- INV-2: the invalid chip **keeps its remove X** even though it is not in the upload state; the upload state still hides the X → TC-01/TC-03.
- INV-3: the validate gate yields the **failing index + reason** (`null` when all valid), not a bare `bool` → TC-06.
- INV-4: a too-large/GIF rejection shows **no `SnackBar`** for the size/GIF copy — the chip carries it → TC-04/TC-05/TC-07.
- INV-5: **Send is disabled** while any invalid attachment is present, and re-enables once it is removed → TC-09.
- INV-6: the 4 redundant GROUP media-state snackbars (`media_still_unavailable`, `failed_media_retry_failed`, `failed_media_upload_pending_retry`, `failed_message_retry_failed`) are **not shown**; the inline tile state remains → TC-08/TC-10.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short`; add/rewrite the 10 catalog tests; run the focused RED commands; confirm each fails for its documented reason (compile-red for TC-01/02/06; snackbar-present for TC-04/05/07/08; Send-enabled for TC-09).
2. `attachment_preview_strip.dart`: add `final Set<int> invalidIndices` (default `const {}`) to `AttachmentPreviewStrip` ctor + pass `isInvalid: invalidIndices.contains(index)` (and optionally a `reasonText`) into `_Thumbnail`. In `_Thumbnail`: when `isInvalid && !isUploading`, wrap the `ClipRRect` in a red-bordered keyed container (`ValueKey('attachment-invalid-$index')`), overlay a warning icon (lock `Icons.error_outline`), and **render the remove X** by relaxing the X condition to `(!isUploading && onRemove != null)` — unchanged for upload (X still hidden when uploading), but the invalid (not-uploading) chip now shows it (it already would; the new bit is the red/warning + an optional caption). Add the reason caption (reuse `media_too_large_after_compress` / `media_gif_too_large`) as a small text/tooltip on the chip.
3. `compose_area.dart`: add `final bool hasInvalidAttachment` (default false); fold `&& !widget.hasInvalidAttachment` into the Send enable expression (`:286` getter + the `:478-481` onPressed gate). Stop-if: if Send enable is computed in more than these two spots, gate ALL of them (grep before editing).
4. `group_conversation_wired.dart`: refactor `_validatePendingGroupMediaDescriptors` (`:4554`) to return `MediaRejection?` — keep the unsupported-MIME snackbar (out of per-chip scope) OR fold it into the struct as `unsupported_mime` (decide: keep snackbar to stay minimal); for size/GIF, compute the failing **index** (path→index via `pending.file.path`) + reason and return it WITHOUT calling `_showGifTooLargeMessage`/`_showAttachmentTooLargeMessage`. Update caller `:1851` to set the wired invalid-index state + NOT abort-silently (retain attachments, mark invalid, block send via the new flag).
5. `conversation_wired.dart`: mirror step 4 on `_validatePendingMediaSizes` (`:972`) + caller `:1928`. Do NOT touch the hardcoded retry literals.
6. Wire the invalid set through the view-states: `ConversationComposerViewState` (`conversation_screen.dart:41-75`) + the group composer state gain an `invalidAttachmentIndices` field; the screens pass it into `AttachmentPreviewStrip` (`conversation_screen.dart:340-348`, `group_conversation_screen.dart:241-249`) and into `ComposeArea` as `hasInvalidAttachment`. On attachment removal, clear that index's invalid flag (recompute or shift the set).
7. `group_conversation_wired.dart`: delete the 4 redundant snackbars — `media_still_unavailable` (`:2262`), `failed_media_retry_failed` (`:2361`,`:2395`), `failed_media_upload_pending_retry` (`:2372`), `failed_message_retry_failed` (`:2429`). Keep the surrounding re-resolve/retry/status side-effects intact (only the `_showFloatingSnackBar(...)` lines go). Stop-if: a dropped string has NO inline tile equivalent → DO NOT drop it (re-scope).
8. l10n: NO new keys required (reuse `media_too_large_after_compress` `:421` + `media_gif_too_large` `:422` on the chip; reuse `conversation_context_delete` if a remove label is needed). If a chip caption truly needs a distinct short string, add ONE key to en/ar/de append-by-key + regenerate; otherwise skip l10n entirely.
9. `scripts/run_test_gates.sh`: add `"test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart"` to the `ONE_TO_ONE_TESTS` array (`:17-63`).
10. Rerun direct → preservation → named gates; `flutter analyze`; `git diff --check`.

## Risks And Edge Cases
- **Index drift on removal**: removing attachment `k` shifts later indices; the invalid set must be recomputed (or re-run the gate) after any removal so the red chip follows the right item → pinned by TC-09's "remove → Send re-enables" leg + a strip removal pump.
- **Invalid vs uploading collision**: a chip cannot be both; the invalid render branch must be `isInvalid && !isUploading` so an in-flight upload never paints red → TC-03 sentinel + TC-01 discriminator (no `CircularProgressIndicator`).
- **Send-enable computed in >1 place** in `compose_area.dart` (getter `:286` + onPressed `:478-481`) → both must gain the term, else Send looks disabled but still fires → grep-all in step 3.
- **Dropping a snackbar that has NO inline equivalent**: only the 4 named GROUP snackbars are dropped; the unsupported-MIME (`group_media_unsupported`) and the 1:1 hardcoded literals are KEPT → INV-6 scoped, step 7 Stop-if.
- **WidgetSpan/U+FFFC** breaking `find.text` on bubble bodies is NOT in play here (composer chips/snackbars are plain text), but for the wired snackbar-absence assertions use `find.widgetWithText(SnackBar, …)` (not bare `find.text`, which would also catch an inline chip caption) → TC-04/07/08 use `widgetWithText(SnackBar, …)` findsNothing + a separate chip-caption `find.text` findsOneWidget.
- **Shared MediaGridCell**: do NOT edit it; only the composer strip + gates + ComposeArea + the GROUP wired snackbars change. 1:1 tile behavior is untouched (Accepted Difference).

## Device/Relay Proof Profile
host-only for closure. No OS-boundary / ML-KEM / relay / multi-device leg — all behavior is local composer render + a pure `bool`→struct seam + snackbar removal; no migration. No `integration_test/` simulator scenario and no `check_reliability_simulation_discovery.sh` row needed.
Deferred device work: none. (If a render-on-real-iOS proof is later desired for the red chip under RTL, it mirrors 144's `*_proof_test.dart` precedent — NOT required for closure.)

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart \
  --plain-name 'invalid attachment renders a red border'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'too-large group attachment marks the chip invalid'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'Send stays disabled while an invalid attachment is present'

# Direct GREEN (after fix)
flutter test test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart   # prior 20 + new red-chip cases
flutter test test/shared/widgets/media/media_grid_cell_test.dart                                   # sentinel, unchanged count
flutter test test/features/groups/presentation/group_conversation_wired_test.dart                  # + TC-04/06/07/08; 2 PRE-EXISTING fails (GMAR-004 reopen-hydration, incoming-group-image-refresh) are NOT mine
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart          # + TC-05/09

# Preservation + named gates (after adding attachment_preview_strip_test to ONE_TO_ONE_TESTS)
./scripts/run_test_gates.sh 1to1          # 1:1 family incl. the newly-registered strip test
./scripts/run_test_gates.sh groups        # groups family; the 2 PRE-EXISTING wired fails are NOT mine
./scripts/run_test_gates.sh feed          # LetterCard/MediaGrid feed variants stay green

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the catalog tests before the fix — TC-01/02/06 compile-red (missing params/struct); TC-04/05/07/08 snackbar-present; TC-09 Send-enabled.
- Pre-existing dirty (NOT mine): `group_conversation_wired_test.dart` shows 2 PRE-EXISTING failing wired tests on HEAD — `GMAR-004 reopen-hydration` and `incoming-group-image-refresh` (media reopen/hydration, unrelated). Record before execution; do not "fix" by reverting. The wider `new-feed` tree is already dirty (Feed/Orbit work per `git status`) — snapshot `git status --short` first; touch ONLY the Real-Scope files.
- Environment blocker (NOT product): none (host-only; no sim/device).
- Scope drift (BLOCKING): any failure outside the listed files/tests, any edit to `media_grid_cell.dart`, the 1:1 hardcoded retry literals, the unsupported-MIME path, or any DB/migration touch.

## Done Criteria
- [ ] RED added/rewritten first, failed for the expected reason.
- [ ] Each fix mutation-verified (re-red revert named in the matrix).
- [ ] Direct GREEN + 1to1/groups/feed preservation gates pass; the 2 pre-existing wired fails unchanged.
- [ ] No migration introduced (rejection state is pre-send composer state; DB stays v92).
- [ ] `attachment_preview_strip_test.dart` added to `ONE_TO_ONE_TESTS` and confirmed running in `./scripts/run_test_gates.sh 1to1`.
- [ ] 4 redundant GROUP snackbars dropped; the inline tile state still present (TC-08/TC-10).
- [ ] Existing `media_too_large_after_compress` / `media_gif_too_large` keys now render on the chip (no new key, OR exactly one new key × en/ar/de regenerated if a caption needs it); `flutter analyze` 0-new; `git diff --check` clean.

## Scope Guard (hard "Do not")
- Do not add a DB migration or bump `currentIdentityDatabaseVersion` (rejection state is unpersisted composer state).
- Do not edit `media_grid_cell.dart` or rebuild its upload-pending / unavailable / retry placeholders (already done — refuted finding).
- Do not add a per-tile upload progress ring (no per-attachment byte source; duplicates `UploadProgressBanner` — Accepted Difference).
- Do not touch the 1:1 hardcoded retry literals (`conversation_wired.dart:2496`/`:2508`), the unsupported-MIME snackbar (`group_media_unsupported`), or any 1:1 redundant-snackbar drop (1:1 has none).
- Do not keep a size/GIF snackbar "just in case" — the chip is the replacement (INV-4).

## Accepted Differences / Intentionally Out Of Scope
- **No per-tile upload progress ring** — there is no per-attachment byte source (`UploadProgressViewState` is a single aggregate); `UploadProgressBanner` above the composer already shows aggregate progress + cancel. Owner: a future per-attachment-progress session if a per-item byte stream is added.
- **1:1 hardcoded retry literals left un-localized** — only required if 1:1 retry copy is folded inline; this plan keeps 1:1's snackbar-free tile re-render, so no inline copy is needed. Owner: an i18n-cleanup session.
- **Unsupported-MIME hard reject keeps its snackbar** (`group_media_unsupported`) — it rejects a never-displayable file (not a size reason a chip caption would clarify); accepted.
- **Per-chip reason is the current size-policy reason** (one reason per chip), reusing the existing two keys; no new reason taxonomy or stored field.

## Dependency Impact
- None outbound. The harness-registration fix (adding `attachment_preview_strip_test.dart` to `ONE_TO_ONE_TESTS`) retroactively gates ALL pre-existing composer-strip behavior (upload overlay, GIF badge, processing tile, remove-index) under the curated 1:1 gate — a standalone hardening win. The `bool`→`MediaRejection?` seam is internal to each wired screen (no cross-feature consumer).

## Reviewer Findings
<to be filled by sufficiency reviewer — matrix has zero empty cells; every INV maps to a TC; every behavior-bearing edit has a named mutation-revert; preservation sentinels (TC-03/TC-10) named with gate cmd; the one PROD-shared widget (AttachmentPreviewStrip) is registered into a curated gate (ONE_TO_ONE_TESTS). Note the stale-brief correction: GROUP_TESTS already contains group_conversation_wired_test.dart at :131, so no group registration step is needed.>

## Arbiter Decision
Structural blockers: none anticipated (host-only; no migration; no device leg). | Deferred details: per-tile progress ring + 1:1 literal localization (owners named). | Accepted differences: progress ring, 1:1 literals, unsupported-MIME snackbar (all documented above).

## Final Execution Verdict
Verdict: (to be filled post-execution) | Files changed: attachment_preview_strip.dart, compose_area.dart, group_conversation_wired.dart, conversation_wired.dart, group_conversation_screen.dart, conversation_screen.dart, run_test_gates.sh (+ 3 test files) | Tests run (+counts): (fill) | Blocking: (fill) | QA verdict: (fill) | Non-blocking follow-ups (owner): per-attachment progress ring; 1:1 retry-literal i18n.
