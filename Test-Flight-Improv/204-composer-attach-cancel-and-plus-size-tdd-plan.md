# 204 - Attach-sheet Cancel affordance + "+" button size parity  (Bug ×2, UI)

Status: IMPLEMENTED + host-green (2026-07-04)
Spec: free-text intent (no formal spec) — user report, 2026-07-04:
> 1. When I open a chat to send an image and I change my mind, there is no back/X to go back to the chat — add a back or X so users can go back.
> 2. In group chat and 1:1 chat the "+" attach button is a different size than the "voice note" button — make "+" the same size as the voice-note button.

Disambiguated with the user (2026-07-04): BUG 1 = the **attach source bottom sheet** (Photo Library / Take Photo / Record Video) that pops after tapping `+`. Today it dismisses only by swipe/scrim — no explicit Cancel/X. (The chat header already has a `‹` back button and a staged image already has a per-thumbnail `×`; those are NOT the bug.)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-04 | Evidence Collector (workflow wf_f4b82c58-585, 4 agents: verify→refute / test-inventory / l10n / blind-spot) | compose_area.dart, voice_record_button.dart, attachment_preview_strip.dart, conversation_header.dart, conversation_wired.dart, group_conversation_wired.dart, conversation_screen.dart, group_conversation_screen.dart, compose_area_test.dart, voice_record_button_test.dart, conversation_wired_test.dart, group_conversation_wired_test.dart, run_test_gates.sh, run_host_test_gates.sh, app_en/ar/de.arb, l10n_integrity_test.dart | All 4 claims CONFIRMED; both root causes source-verified; l10n = reuse `btn_cancel`; harness = no new registration | Build matrix |
| 2026-07-04 | Planner | (above) | 5 TCs, widget tier only, host-only closure, no DB/no device-proof | Emit plan |
| 2026-07-04 | Reviewer (sufficiency) | this plan | Blind-spot sweep run (2 rows, 2 justified N/A); zero empty matrix cells | Arbiter |
| 2026-07-04 | Arbiter | this plan | Structurally sufficient; host-only; two identical sheet edits accepted (no refactor) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-04 | contract extraction (git status --short) | — | pre-existing dirty: graphify-arch artifacts, info.plist, spec-doc SKILL.md, 00-INDEX.md, 199/204 plan docs | scope confirmed (leave dirty files untouched) | add RED |
| 2026-07-04 | RED tests added | compose_area_test.dart (+import VoiceRecordButton, +onRecordStart/Stop params, TC-204-01), conversation_wired_test.dart (TC-204-02/03), group_conversation_wired_test.dart (TC-204-04/05); inert scaffolding: `+` key + 2 static const keys | TC-204-01 RED `Size(48,48)` vs `Size(36,36)`; TC-204-02/04 RED `Found 0 widgets with key`; TC-204-03/05 RED Cancel untappable/absent | RED for expected reason ✓ | implement |
| 2026-07-04 | implementation | compose_area.dart (`+` 36→48), conversation_wired.dart (`_onAttach` Cancel ListTile), group_conversation_wired.dart (`_onAttach` Cancel ListTile) | scoped files only (2 identical sheet edits, no shared helper) | on off-screen tap in TC-204-03/05 (sheet below 600px viewport) → switched to `.onTap!()` invocation (file convention, cf. picker tiles :4538) | direct GREEN |
| 2026-07-04 | direct GREEN | (tests above) | compose_area_test **39/39**; conversation_wired_test **108/108**; group_conversation_wired_test **168/168** | reds now green ✓ | preservation |
| 2026-07-04 | preservation GREEN | — | voice_record_button_test **5/5**; l10n_integrity: ONLY pre-existing orbit3 debt (proven via `git stash` on clean HEAD; `.btn_cancel` used, not flagged); `git diff --check` clean | sentinels green (l10n red pre-existing, not scope drift) ✓ | named gates |
| 2026-07-04 | named gates | — | `./scripts/run_test_gates.sh 1to1` **1484/1484**; `./scripts/run_test_gates.sh groups` **1043/1043**; `flutter analyze` (6 changed files) 0 NEW (6 pre-existing info lints in unmodified lines) | gate green ✓ | QA |
| 2026-07-04 | QA (independent) | — | code-reviewer agent adversarial pass: context correctness (`Navigator.pop(ctx)` = sheet builder ctx, matches sibling tiles), 36→48 height-neutral (row=51 before/after, bottom-aligned), 3 keys globally unique, `.btn_cancel` resolves EN/AR/DE | blocking: none | SHIP |

## Source Of Truth
- Intent: inline above (user report + disambiguation).
- Gate definitions: `scripts/run_test_gates.sh` + `scripts/run_host_test_gates.sh` (script wins over prose).
- l10n integrity: `test/l10n/l10n_integrity_test.dart`.
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (204 = next free after 203).

## Session Classification
implementation-ready (host-only; widget tier; no migration; no device-proof).

## Exact Problem Statement
Two independent UI defects in the chat composer, both present in **1:1 and group** chat:

**BUG 2 (size mismatch).** The `+` attachment button renders at `36×36` while the voice-note (mic) button and the send button both render at `48×48`. The `+` is the only composer action button not sized to the 48-pt tap target, so it looks visibly smaller and off the accessible-target baseline. Because the composer widget (`ComposeArea`) is shared, both chat types show the same too-small `+`.

**BUG 1 (no explicit dismiss on the attach sheet).** Tapping `+` opens a modal bottom sheet with three source options (Photo Library / Take Photo / Record Video). The sheet can only be dismissed by swiping it down or tapping the dimmed scrim — there is no visible Cancel/X. A user who taps `+`, changes their mind, and looks for an obvious "go back to the chat" affordance finds none. This holds on both the 1:1 and group attach sheets.

What must improve:
- `+` attach button sized `48×48`, equal to the voice-note button, on both surfaces.
- Each attach sheet (1:1 + group) exposes an explicit **Cancel** row that simply closes the sheet.

What must stay unchanged (→ preserved-green sentinels):
- The three picker options and their pick behavior (`_pickFromGallery` / `_pickFromCamera` / `_pickVideoFromCamera`).
- Any already-staged attachments — Cancel must dismiss the sheet only, never clear pending media.
- The composer row height/alignment (the resize is height-neutral).
- Existing composer/attach tests, and l10n parity/integrity.

## Root Cause (verify → refute confirmed — workflow wf_f4b82c58-585, all 4 claims CONFIRMED)
- **BUG 2:** `compose_area.dart:344-346` sizes the `+` `Container` at `width:36 height:36` (child `Icon(Icons.add_rounded, size:20)`, inside `GestureDetector` `:339` + `Padding(bottom:3)` `:337-338`). The send button is `48×48` (`compose_area.dart:495-496`, comment "Match the VoiceRecordButton (48x48)"); `VoiceRecordButton` is `48×48` (`voice_record_button.dart:102-103`). Row is `crossAxisAlignment: CrossAxisAlignment.end` (`compose_area.dart:334`). `ComposeArea` is the **shared** composer, built at `conversation_screen.dart:427` (1:1) and `group_conversation_screen.dart:265` (group) — one edit fixes both.
- **BUG 1:** the attach sheet is built inline in `_onAttach` → `showModalBottomSheet` at `conversation_wired.dart:2922` (1:1, sheet children `:2934-2984`) and `group_conversation_wired.dart:3228` (group, sheet children `:3241-3291`). Both bodies are byte-identical: `SafeArea > Column` = drag handle + 3 picker `ListTile`s + spacers, **no Cancel/X**. The two sheets are duplicated inline (no shared helper), so the fix is two identical edits.

Refuted / do-NOT-re-introduce:
- "The chat is missing a back button" — **REFUTED**: `conversation_header.dart:60-67` already renders a `chevron_left` back wired to `onBack`. Not the bug.
- "A picked image can't be removed" — **REFUTED**: `attachment_preview_strip.dart:277-294` already renders a per-thumbnail `22×22` `×` remove. Not the bug.
- "Group uses `GroupComposeArea`" — **REFUTED**: `group_compose_area.dart:9` exists but is **dead code** (never instantiated); group uses the shared `ComposeArea`.
- "The 36→48 resize needs a bottom-Padding tweak / shifts the row" — **REFUTED**: row height = `max(39, 44, 51) = 51` today and stays 51 after `+`→48 (bottom-aligned; identical `Padding(bottom:3)` on `+` and send/mic slots). Do NOT touch the padding.
- "A new `picker_cancel` l10n key is required" — **REFUTED as required**: generic `btn_cancel` ("Cancel"/"إلغاء"/"Abbrechen") already exists in all 3 locales (`app_en.arb:427`) → reuse it, zero ARB work. (A picker-scoped key is optional, see Accepted Differences.)

## Real Scope
In scope:
- `compose_area.dart`: `+` `Container` `36×36 → 48×48` (keep `Icon size:20`, keep `Padding(bottom:3)`); add a `ValueKey('composer-attach-button')` on that `Container` for a stable size finder.
- `conversation_wired.dart` `_onAttach`: add a keyed **Cancel** `ListTile` (`Icons.close_rounded`, `l10n.btnCancel`, `onTap: () => Navigator.pop(ctx)`).
- `group_conversation_wired.dart` `_onAttach`: the same Cancel `ListTile` with a distinct key.

Out of scope (owning work named):
- Extracting a shared attach-sheet helper (cleanup — future refactor session).
- Adding Semantics labels to composer action buttons (a11y-labeling pass — see Accepted Differences).
- Any change to the picker options, staging, header back, or thumbnail-remove.

## Files To Inspect Next
Production:
- `lib/features/conversation/presentation/widgets/compose_area.dart` (`:333-378` `+` slot; `:461-524` send/mic slot).
- `lib/features/conversation/presentation/screens/conversation_wired.dart` (`_onAttach` `:2922-2989`; static keys near `:188`).
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` (`_onAttach` `:3228-3296`; `_canWrite` guard `:3229`; `onAttach` gate `:5186`).
- Reference sibling for Cancel style: `_DeleteSheetAction` + `deleteCancelKey` (`conversation_wired.dart:188, 4626-4634`).

Direct tests:
- `test/features/conversation/presentation/widgets/compose_area_test.dart` (BUG-2).
- `test/features/conversation/presentation/screens/conversation_wired_test.dart` (BUG-1 1:1; existing sheet test `:4075-4104`).
- `test/features/groups/presentation/group_conversation_wired_test.dart` (BUG-1 group; media-send patterns `:1536`, `:7331` negative).

Dependency-only context:
- `test/features/conversation/presentation/widgets/voice_record_button_test.dart:27-42` (size-assertion style to mirror).
- `lib/l10n/app_en.arb:427` (`btn_cancel`), `test/l10n/l10n_integrity_test.dart` (literal scan + parity).

## Existing Tests Covering This Area
- `compose_area_test.dart` — covers `+` existence/tap/disabled/dimmed (`:120, :357, :489, :499`), Row grouping (`:504`), send-is-circle (`:523`). **No size assertion on +/mic/send** → BUG-2 test is net-new (not a re-baseline).
- `voice_record_button_test.dart:27-42` — asserts `getSize(VoiceRecordButton) == Size(48,48)` (mirror source).
- `conversation_wired_test.dart:4075-4104` — asserts the 1:1 sheet shows the 3 picker labels (`'Media Library'`/`'Take Photo'`/`'Record Video'`). Extend here for the Cancel assertion.
- `group_conversation_wired_test.dart` — opens the sheet inside media-send tests via tile `onTap` (`:1536, :1763, :7851, :7949`) and a negative `:7331`; **no dedicated sheet-presence test** → group Cancel test is net-new.

Missing coverage gaps: no size lock on the `+` button; no Cancel affordance anywhere on either sheet (`find.text('Cancel')` today only matches the voice `RecordingOverlay`, never the sheet).

Already in curated family arrays?:
- `conversation_wired_test.dart` ∈ `ONE_TO_ONE_TESTS` (`run_test_gates.sh:75`).
- `group_conversation_wired_test.dart` ∈ `GROUP_TESTS` (`run_test_gates.sh:224`).
- `compose_area_test.dart` / `voice_record_button_test.dart` — NOT curated; AUTO-glob via `feature-host-all` (`run_host_test_gates.sh:184`); completeness catch-all classifies them (`run_test_gates.sh:710`).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/features/conversation/presentation/widgets/compose_area_test.dart`::`'attach button matches the voice-note button size (48x48)'`
   - Tier: widget
   - Shape/setup: pump `ComposeArea` with `onRecordStart`/`onRecordStop` non-null, empty `initialText`, `hasAttachments:false` (so the mic `VoiceRecordButton` renders alongside the `+`). Anchor the `+` via `find.byKey(const ValueKey('composer-attach-button'))`.
   - RED on HEAD because: the `+` `Container` is `36×36` → `tester.getSize(attach) == const Size(36,36)`, so `== const Size(48,48)` fails AND `== tester.getSize(find.byType(VoiceRecordButton))` fails.
   - GREEN after fix asserts: `tester.getSize(attach) == const Size(48,48)` AND `tester.getSize(attach) == tester.getSize(find.byType(VoiceRecordButton))` (encodes the user's literal ask: "same size as the voice-note button").
   - Mutation that re-reds: revert `compose_area.dart:344-345` `48→36` → both assertions flip RED.

2. `test/features/conversation/presentation/screens/conversation_wired_test.dart`::`'attach sheet shows a Cancel affordance (1:1)'`
   - Tier: widget (wired)
   - Shape/setup: pump `ConversationWired`, `tester.tap(find.byIcon(Icons.add_rounded))`, `pump(500ms)` (mirror `:4075-4104`).
   - RED on HEAD because: no Cancel row → `find.byKey(const ValueKey('conversation-attach-cancel-action'))` is `findsNothing`.
   - GREEN after fix asserts: that key `findsOneWidget`, its title text is `l10n.btnCancel` ("Cancel"), and the three picker labels are still present (Cancel is additive).
   - Mutation that re-reds: remove the Cancel `ListTile` from `conversation_wired.dart` `_onAttach` → RED.

3. `test/features/conversation/presentation/screens/conversation_wired_test.dart`::`'Cancel closes the attach sheet without picking and keeps staged media (1:1)'`
   - Tier: widget (wired)
   - Shape/setup: (a) stage one attachment via the existing fake-pick path this file already drives (tap `+` → invoke `'Media Library'` tile `onTap`, as at `:4538`), assert `AttachmentPreviewStrip`/`hasAttachments` present; (b) re-open the sheet, tap the Cancel key, `pump`.
   - RED on HEAD because: no Cancel exists to tap (`findsNothing`) — the tap target is absent.
   - GREEN after fix asserts (distinct-event discriminators): **SHEET_DISMISSED** (`find.text('Media Library')` `findsNothing` after tap) **AND NOT PICK_INVOKED** (the fake media picker's call count is unchanged / no `isProcessing` transition) **AND STAGED_INTACT** (`AttachmentPreviewStrip` still `findsOneWidget`; pending count unchanged).
   - Mutation that re-reds: change Cancel `onTap` to also call `_pickFromGallery` (PICK_INVOKED reds), or to clear `_pendingAttachments` (STAGED_INTACT reds), or to drop `Navigator.pop` (SHEET_DISMISSED reds).

4. `test/features/groups/presentation/group_conversation_wired_test.dart`::`'attach sheet shows a Cancel affordance (group)'`
   - Tier: widget (wired)
   - Shape/setup: pump `GroupConversationWired` with `canWrite == true`, tap `Icons.add_rounded`, `pump(500ms)`.
   - RED on HEAD because: `find.byKey(const ValueKey('group-attach-cancel-action'))` is `findsNothing`.
   - GREEN after fix asserts: that key `findsOneWidget`, title `l10n.btnCancel`, three pickers still present.
   - Mutation that re-reds: remove the group Cancel `ListTile` → RED.

5. `test/features/groups/presentation/group_conversation_wired_test.dart`::`'Cancel closes the group attach sheet without picking and keeps staged media (group)'`
   - Tier: widget (wired)
   - Shape/setup: mirror TC-204-03 on the group surface (stage via the `'Media Library'` tile pattern at `:1536`, re-open, tap Cancel).
   - RED on HEAD because: no Cancel to tap.
   - GREEN after fix asserts: SHEET_DISMISSED AND NOT PICK_INVOKED AND STAGED_INTACT (same discriminators as TC-204-03, group instance — the sheets are duplicated, so each surface needs its own lock).
   - Mutation that re-reds: group Cancel `onTap` picks / clears staged / omits `pop`.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| BUG-2 size parity | widget render/size, shared widget → both surfaces | widget | compose_area_test.dart::'attach button matches the voice-note button size (48x48)' | `+` is 36×36 → getSize ≠ Size(48,48) and ≠ mic size | revert compose_area.dart:344-345 48→36 | `flutter test test/features/conversation/presentation/widgets/compose_area_test.dart` | AUTO (glob `feature-host-all`, run_host_test_gates.sh:184); optional pin near `ONE_TO_ONE_TESTS` run_test_gates.sh:76 |
| BUG-1 1:1 present | widget wired, modal sheet contents | widget | conversation_wired_test.dart::'attach sheet shows a Cancel affordance (1:1)' | no Cancel row → find.byKey('conversation-attach-cancel-action') findsNothing | remove Cancel ListTile in conversation_wired.dart _onAttach | `./scripts/run_test_gates.sh 1to1` | already in ONE_TO_ONE_TESTS (run_test_gates.sh:75) + AUTO glob |
| BUG-1 1:1 no-side-effect | widget wired, dismiss + destructive-guard | widget | conversation_wired_test.dart::'Cancel closes the attach sheet without picking and keeps staged media (1:1)' | Cancel absent → not tappable (findsNothing); asserts SHEET_DISMISSED && NOT PICK_INVOKED && STAGED_INTACT | Cancel onTap picks / clears _pendingAttachments / omits pop | `./scripts/run_test_gates.sh 1to1` | already in ONE_TO_ONE_TESTS:75 + AUTO |
| BUG-1 group present | widget wired, modal sheet contents | widget | group_conversation_wired_test.dart::'attach sheet shows a Cancel affordance (group)' | find.byKey('group-attach-cancel-action') findsNothing | remove group Cancel ListTile | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS (run_test_gates.sh:224) + AUTO glob |
| BUG-1 group no-side-effect | widget wired, dismiss + destructive-guard | widget | group_conversation_wired_test.dart::'Cancel closes the group attach sheet without picking and keeps staged media (group)' | Cancel absent → not tappable; asserts SHEET_DISMISSED && NOT PICK_INVOKED && STAGED_INTACT | group Cancel onTap picks / clears staged / omits pop | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS:224 + AUTO |

## Blind-Spot Sweep  (evergreen classes — row added OR justified N/A)
- **Lifecycle / derived-state durability:** **N/A** — the change adds no persisted or event-derived in-memory state. The `+` size is a compile-time constant; Cancel is a stateless dismiss. Nothing to reconstruct on reopen/restart.
- **Sibling-surface consistency:** **Covered.** BUG-2 rides the shared `ComposeArea` and is locked by a surface-agnostic widget test (TC-204-01); the parallel composer action buttons (voice 48, send 48) are already 48 — this fix brings `+` into line, no other gate touched. BUG-1 is locked on **both** duplicated sheets (TC-204-02/03 for 1:1, TC-204-04/05 for group) — the duplicated-sheet "fix one, forget the other" trap is explicitly closed by having a group row.
- **Destructive-action side-effects:** **Covered (TC-204-03/05).** Cancel is the new exit action; its tests assert it removes **nothing** (no pick, no `_pendingAttachments` clear) — dismiss only. This is the load-bearing guard against a Cancel that silently drops staged media.
- **Invariant re-verification under new transitions:** **N/A** — no new state transition is introduced. Cancel makes the pre-existing implicit scrim/swipe dismiss explicit; its side-effect profile is identical (pop-only), which TC-204-03/05 assert equals the scrim's "clears nothing" semantics.

## Invariants (locked by tests)
- INV-1: `+` attach-button size == voice-note-button size (both `48×48`) → TC-204-01.
- INV-2: every attach sheet (1:1 + group) exposes a Cancel affordance → TC-204-02, TC-204-04.
- INV-3: Cancel dismisses the sheet only — never picks, never mutates staged media → TC-204-03, TC-204-05.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot the tree: `git status --short` (record pre-existing dirty files so none are reverted).
2. Add the 5 RED tests (TC-204-01..05). Run the focused RED commands (Acceptance Gates) and confirm each FAILS for the documented reason (size 36≠48; `findsNothing` on the Cancel keys).
3. BUG-2 edit — `compose_area.dart`: change the `+` `Container` `width:36 height:36` → `48/48` and add `key: const ValueKey('composer-attach-button')`. Do NOT touch `Padding(bottom:3)` or `Icon size:20`. Stop-if: composer row height changes or an existing `compose_area_test` reds → replan (the resize is proven height-neutral; a red means an unexpected coupling).
4. BUG-1 edit (1:1) — `conversation_wired.dart` `_onAttach`: after the Record Video `ListTile`, add a Cancel `ListTile` — `key: const ValueKey('conversation-attach-cancel-action')` (mirror as `static const attachSheetCancelKey` on `ConversationWired`, like `deleteCancelKey`), `leading: Icon(Icons.close_rounded, color: sheetColors.iconPrimary)`, `title: Text(AppLocalizations.of(context)!.btnCancel, style: TextStyle(color: sheetColors.textPrimary))`, `onTap: () => Navigator.pop(ctx)` — **and nothing else**.
5. BUG-1 edit (group) — `group_conversation_wired.dart` `_onAttach`: the same Cancel `ListTile` with `key: const ValueKey('group-attach-cancel-action')` (distinct so surface-specific tests target each unambiguously). Stop-if: tempted to extract a shared helper → do NOT (out of scope); apply the two identical edits.
6. Re-run direct GREEN → preservation sentinels → named gates. Confirm `flutter analyze` 0 new + `git diff --check` clean.

## Risks And Edge Cases
- `Icons.close_rounded` is ambiguous (`find.byIcon` also matches the quote-dismiss `compose_area_test.dart:105` and the delete-cancel) → tests MUST anchor on the **ValueKey**, not the icon. Pinned by TC-204-02/04 using `find.byKey`.
- `find.text('Cancel')` also matches the voice `RecordingOverlay` → assert Cancel via the key'd widget (no recording active in these tests), not a bare text find. Pinned by TC-204-02/04.
- Hardcoded-literal l10n scan (`l10n_integrity_test.dart:45-64`) will FAIL if Cancel uses a raw `Text('Cancel')` → must use `l10n.btnCancel`. Pinned by preservation gate.
- Group read-only path: when `!canWrite`, `GroupConversationScreen` renders a read-only banner instead of `ComposeArea` (`group_conversation_screen.dart:262-265`) and `_onAttach` early-returns (`:3229`) — the resized `+` and the Cancel row never appear there; the group presence test must pump with `canWrite == true`.

## Device/Relay Proof Profile
host-only for closure. No OS boundary, no crypto, no transport, no DB migration → no `/sims` row and no device-proof. (Optional, non-gating: a single simulator screenshot to eyeball the 48-pt `+` and the Cancel row — validation only, not a closure gate; see memory `feedback_screenshot_sim_runs_to_debug_and_validate`.)

## Acceptance Gates  (literal — copy/paste)
```bash
# 0. Dirty-tree snapshot (do not revert unrelated files)
git status --short

# 1. RED (BEFORE production edits) — each MUST FAIL for the documented reason
flutter test test/features/conversation/presentation/widgets/compose_area_test.dart \
  --plain-name 'attach button matches the voice-note button size'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'attach sheet shows a Cancel affordance'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'attach sheet shows a Cancel affordance'

# 2. Direct GREEN (AFTER fix) — the 5 new tests pass
flutter test test/features/conversation/presentation/widgets/compose_area_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart

# 3. Preservation sentinels (must stay green)
./scripts/run_test_gates.sh 1to1      # includes conversation_wired_test.dart; expect 0 failures
./scripts/run_test_gates.sh groups    # includes group_conversation_wired_test.dart; expect 0 failures
flutter test test/features/conversation/presentation/widgets/voice_record_button_test.dart  # adjacent size source; 0 failures
flutter test test/l10n/l10n_integrity_test.dart   # no hardcoded 'Cancel'; parity intact; 0 failures

# 4. Full host widget sweep (optional broad; catches the AUTO-globbed compose_area test)
./scripts/run_host_test_gates.sh feature-host-all

# 5. Hygiene
flutter analyze            # 0 new issues
git diff --check
```
Expected: the 3 RED commands FAIL on HEAD; after the fix all commands report **0 failures**. The change adds **5 new host widget tests** (TC-204-01..05); curated gates print their own running totals (baseline + 5).

## Known-Failure Interpretation
- Expected RED: TC-204-01..05 before the fix (size 36≠48; Cancel keys `findsNothing`).
- Pre-existing dirty: unrelated modified files already in the tree (see `git status` at start of session; e.g. graphify-arch artifacts, info.plist) — leave untouched.
- Environment blocker (NOT product): none — host-only, no simulator/device required.
- Scope drift (BLOCKING): any failure outside the touched files (composer/attach sheets) or any l10n-integrity red.

## Done Criteria
- [ ] RED added first (TC-204-01..05), failed for the expected reason.
- [ ] Mutation-verified (each fix has a re-red revert per the matrix).
- [ ] Direct GREEN + preservation sentinels (`1to1`, `groups`, voice-button, l10n-integrity) pass.
- [ ] No DB migration (none needed); no device-proof (none needed).
- [ ] BUG-2 locked at both absolute 48×48 and parity with the mic; BUG-1 Cancel on BOTH sheets with the no-side-effect guard.
- [ ] Every new test auto-globs / runs in its curated gate (verified in a gate run) — no new registration required.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do NOT extract a shared attach-sheet helper — apply two identical `_onAttach` edits (refactor owned by a future cleanup session).
- Do NOT add Semantics labels to only the `+` (would break the current `+`/send symmetry — both are bare `GestureDetector`s today). A11y labeling of composer action buttons is a separate follow-up.
- Do NOT modify `Padding(bottom:3)` or the `+` `Icon size:20` (resize is height-neutral; padding must stay equal to the send/mic slot).
- Do NOT change picker options, `_pickFrom*`, staging, the header back button, or the thumbnail-remove `×`.
- Do NOT add a new l10n key (reuse `btn_cancel`); do NOT introduce a raw `Text('Cancel')` literal.

## Accepted Differences / Intentionally Out Of Scope
- The attach sheet stays duplicated in two `State` classes (no shared helper) — cleanup deferred; both copies get the identical Cancel edit.
- Composer action buttons (`+` and send) remain without Semantics labels — symmetric today; a dedicated a11y pass owns labeling.
- Reusing generic `btn_cancel` rather than a picker-scoped key. If translators later need "Close"≠"Cancel" divergence, add `picker_cancel` to `app_en/ar/de.arb` ("Cancel"/"إلغاء"/"Abbrechen"), run `flutter gen-l10n`, and gate on `flutter test test/l10n/l10n_integrity_test.dart` (procedure documented; not needed now).

## Dependency Impact
- None. Pure additive UI; no contract, model, DB, or transport surface changes. No other session depends on this.

## Reviewer Findings
Sufficiency self-check (references/sufficiency-checklist.md) passed: spec-case totality (both bugs → 5 tiered tests), every fix mutation-verified with a named re-red revert, literal gates with `--plain-name`, harness-registration stated per test (AUTO / already-curated), blind-spot sweep run (2 covered rows + 2 justified N/A), no DB migration / no OS-boundary path (so no simulator/device-proof owed), matrix has zero empty cells in tier/mutation/gate/registration. No PROD-CRITICAL wire/transport leg exists (pure client UI). Refuted findings recorded as do-NOT-re-introduce.

## Arbiter Decision
Structural blockers: none. Deferred details: shared-helper extraction + a11y labeling (owners named). Accepted differences: duplicated sheet edit, generic `btn_cancel` reuse. Verdict: structurally sufficient — hand off to execution (host-only closure).

## Final Execution Verdict
Verdict: **IMPLEMENTED + host-green (SHIP)** | Files changed: 3 prod (`compose_area.dart`, `conversation_wired.dart`, `group_conversation_wired.dart`) + 3 test (`compose_area_test.dart`, `conversation_wired_test.dart`, `group_conversation_wired_test.dart`) | Tests run (+counts): 5 new TCs GREEN + direct files (39/108/168) + preservation (voice 5/5) + gates (1to1 **1484**, groups **1043**); `flutter analyze` 0 new; `git diff --check` clean | Blocking: none | QA verdict: code-reviewer PASS (no blocking issues — pop-ctx correct, resize height-neutral, keys unique, l10n resolves EN/AR/DE) | Non-blocking follow-ups (owner): shared attach-sheet helper extraction (future cleanup session); Semantics/a11y labels on composer action buttons (a11y pass); pre-existing orbit3 l10n-integrity debt — 3 hardcoded literals in `orbit3_screen.dart:1113/1131`, `orbit3_arch_panel.dart:67` (orbit3 owner, unrelated to this change).

### Deviations from plan (all behavior-preserving)
- l10n getter is `l10n.btn_cancel` (snake_case preserved by this project's gen-l10n), NOT `l10n.btnCancel` as the plan wrote. Verified in `app_localizations_en.dart:804`.
- TC-204-03/05 drive Cancel via `tester.widget<ListTile>(find.byKey(...)).onTap!()` instead of `tester.tap(...)`: with staged media the sheet's Cancel row sits at y≈824, below the 600px-tall default test viewport, so a hit-test tap misses. This mirrors how these files already drive the picker tiles (`:4538`). RED still holds (widget lookup throws `found 0 widgets` when the tile is absent); GREEN discriminators (SHEET_DISMISSED / NOT PICK_INVOKED via `pickMultipleMediaCalls==0` / STAGED_INTACT) unchanged.
- Group key added as `GroupConversationWired.attachSheetCancelKey` static const (the plan suggested inline) for parity with the 1:1 `ConversationWired.attachSheetCancelKey` and to avoid a duplicated magic string — same ValueKey value, tests match by value.
