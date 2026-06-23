# 154 - Quiet success (mute/details/copy) -> haptic + control state, snackbar channel reserved for errors  (Feature Improvement)

Status: awaiting-review
Spec: free-text intent (no formal spec) — chained from a UI/UX review of Group Messaging snackbars

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | group_info_wired.dart (mute :478-537, details :1938-2025), group_conversation_screen.dart (copy :1031-1044, overlay pop :1011), conversation_screen.dart (1:1 copy :879-893), orbit2_screen.dart (:109 haptic precedent), group_list_wired.dart (decline :335-367), app_en/ar/de.arb, run_test_gates.sh, group_conversation_screen_test.dart, group_info_wired_test.dart, conversation_screen_test.dart | verify→refute complete: success snackbars redundant w/ control/field state (mute switch+bell flips, details fields re-render); COPY has NO control state (overlay popped first) → must keep a visible cue; group_info_wired.dart MISSING services.dart import; both conversation screens ALREADY import it; `conversation_context_copied` has exactly 2 lib call sites | Planner |
| 2026-06-23 | Planner | (as above) | mute/details: drop success snackbar + `HapticFeedback.selectionClick()`, lean on control/field. copy: replace floating snackbar with haptic + a tiny non-error quiet-confirm cue (keep `conversation_context_copied`). KEEP all error snackbars (mute_update_failed, details error :2012-2022, decline_failed). NO migration. | Reviewer |
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
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (this file = 154)

## Session Classification
implementation-ready (host-only closure; no migration, no device-proof; pure presentation)

## Exact Problem Statement
Three **success** actions in Group Messaging (and the parity 1:1 copy) confirm themselves with a transient ~4s **snackbar** even though the surface already shows the result, OR the snackbar is the only cue when it doesn't need to be a full error-styled banner. This dilutes the snackbar channel: when a real **error** snackbar (mute failed, details broadcast failed, decline failed) appears, the user has been trained to ignore it because "snackbars just mean it worked."

Specifically:
- **MUTE / RESTORE** (`group_info_wired.dart:478-509`): `setGroupMuted` (`:485`) returns, then `setState(_group = updatedGroup)` (`:495-498`) **flips the Switch + bell icon + description** immediately, and only THEN a snackbar `group_info_notifications_muted` / `group_info_notifications_restored` (`:503/:506`) appears. The control already reflects the new state — the snackbar is redundant.
- **DETAILS updated** (`group_info_wired.dart:1938-1947`): `_loadGroupInfo()` (`:1939`) **re-renders the name/description fields** to the new values, then a snackbar `group_info_details_updated` (`:1944`) appears. The field re-render is the surviving confirmation; the snackbar is redundant.
- **COPY (group)** (`group_conversation_screen.dart:1031-1043`): `Clipboard.setData` + a floating snackbar `conversation_context_copied`. The long-press overlay is **popped (`Navigator.of(dialogContext).pop()` `:1011`) BEFORE `_copyMessageText`** runs, so by the time copy completes there is **no control state at all** — the snackbar is the only cue. **1:1 copy is identical** (`conversation_screen.dart:879-892`, same key `:888`). HAZARD: dropping the cue entirely would make copy **invisible**; it must keep a small, visually-distinct (non-error) confirmation.

What must improve:
- Mute/restore and details-updated: **drop the success snackbar**; add a tactile `HapticFeedback.selectionClick()` and rely on the already-updated control / field state. (`group_info_wired.dart` must **add** `import 'package:flutter/services.dart';` — it does not currently import it.)
- Copy (group + 1:1): replace the full floating snackbar with `HapticFeedback.selectionClick()` **plus** a minimal, visually-distinct **quiet-confirm** cue (a short success-styled pill / brief auto-dismiss confirmation, NOT the standard error snackbar). Keep `conversation_context_copied` for the cue text.

What must stay unchanged (→ preserved-green sentinels):
- **Error snackbars stay**: `group_info_mute_update_failed` (`:527`), the details failure/rollback path (`:2012-2022`, `detailsUpdateFailedMessage` / `detailsUpdateQueuedMessage` / recovery-wait), and `group_invite_decline_failed` (`group_list_wired.dart`, key `:1311`).
- The **DECLINE success** snackbar (`group_list_wired.dart:525-526`) is **owned by plan 153 (Undo)** — do NOT touch it here.
- Clipboard text fidelity (multiline / mixed-script / Arabic) and the overlay-dismiss-once behavior of the long-press menu.
- LetterCard / feed / 1:1 / group render suites; `flutter analyze` 0-new.

## Root Cause (verify → refute confirmed)
The redundancy is **committed on HEAD** (tree dirty on `new-feed` for unrelated Feed/Orbit work; these specific lines are not part of that churn):
- Mute success snackbar fires AFTER the control already flipped: `group_info_wired.dart:495-498` flips state, `:499-509` shows the snackbar.
- Details success snackbar fires AFTER `_loadGroupInfo()` re-renders fields: `group_info_wired.dart:1939` re-renders, `:1941-1947` shows the snackbar.
- Copy snackbar is the SOLE cue because the overlay is popped first: `group_conversation_screen.dart:1011` pops, then `:1031-1043` copies + shows snackbar (1:1: `conversation_screen.dart:879-892`).
- `group_info_wired.dart` does **not** import `package:flutter/services.dart` (confirmed: grep returns no match) → `HapticFeedback` is unavailable until the import is added.
- HapticFeedback precedent exists in-tree: `lib/features/orbit2/presentation/screens/orbit2_screen.dart:109` `HapticFeedback.selectionClick(); // tactile confirmation the toggle fired`.

Refuted / do-NOT-re-introduce:
- ❌ "copy can be haptic-only like mute/details" — **FALSE**; copy has **no control state** (overlay popped at `:1011` before `_copyMessageText`). Haptic-only would make copy silent → MUST keep a small visible cue.
- ❌ "drop `conversation_context_copied` because the snackbar goes away" — **FALSE**; the key is reused by the new quiet-confirm pill. It has **exactly two** lib call sites (`group_conversation_screen.dart:1039`, `conversation_screen.dart:888`); only remove the key if BOTH sites stop using it (they don't).
- ❌ "both conversation screens need the services.dart import added" — **FALSE**; both already import it (`conversation_screen.dart:5`, `group_conversation_screen.dart:5`). Only `group_info_wired.dart` needs the import.
- ❌ "the decline success snackbar is in scope" — **FALSE**; it is owned by plan 153 (Undo). Out of scope here.
- ❌ "remove the mute/details error snackbars too" — **FALSE**; errors are exactly what the reserved channel is FOR. Keep `group_info_mute_update_failed`, the details error/rollback path, `group_invite_decline_failed`.
- ❌ HapticFeedback precedent at `contact_profile_screen.dart:92` or `friends_list_header.dart` — **NOT used as the cited anchor** (wrong/old paths per brief); cite `orbit2_screen.dart:109`, confirmed real.

## Real Scope
In scope:
- `group_info_wired.dart`: **add** `import 'package:flutter/services.dart';`. In `_onMuteChanged` (`:478-509`): delete the success snackbar (`:499-509`); after the `setState` flip (`:495-498`) call `HapticFeedback.selectionClick()`. In the details-save success branch (`:1938-1947`): delete the success snackbar (`:1941-1947`); after `await _loadGroupInfo()` (`:1939`) call `HapticFeedback.selectionClick()`. **Keep** the catch/error snackbars (mute `:524-530`, details `:2012-2022`).
- COPY shared quiet-confirm: build a **tiny shared helper** `showQuietConfirm(BuildContext, String message)` (new file `lib/core/widgets/quiet_confirm.dart`) that (a) `HapticFeedback.selectionClick()` and (b) shows a small, success-styled, auto-dismiss confirmation **visually distinct** from an error snackbar — implemented as a short SnackBar with a distinguishing `key: const ValueKey('quiet-confirm')` + reduced duration + non-error styling (so tests assert the quiet-confirm key, NOT a generic error SnackBar). (No reusable pill/toast widget exists — `Orbit*Pill` are buttons/search inputs, not toasts.)
- `group_conversation_screen.dart` `_copyMessageText` (`:1031-1044`): replace the snackbar body with `showQuietConfirm(context, AppLocalizations.of(context)!.conversation_context_copied)`.
- `conversation_screen.dart` `_copyMessageText` (`:879-893`): same replacement (services.dart already imported).
- Tests: rewrite the snackbar-locking assertions (see RED catalog) and EXTEND the SystemChannels.platform mock to capture `HapticFeedback.vibrate` (mute/details/copy haptic RED).
- Harness: **add `test/features/groups/presentation/group_info_wired_test.dart` to `GROUP_TESTS`** (not currently curated). `group_conversation_screen_test.dart` (GROUP_TESTS:130) and `conversation_screen_test.dart` (ONE_TO_ONE_TESTS:62) are already curated.
- l10n: NO new keys. Keep `conversation_context_copied` (still used by the pill). Note that `group_info_notifications_muted` / `_restored` / `group_info_details_updated` become **unused** by production — leave them in the arb files for now (removal is a no-op cleanup that risks unrelated l10n churn; flag, don't delete).

Out of scope (owning work named):
- DECLINE success snackbar / Undo affordance — **plan 153**.
- Removing the now-unused `group_info_notifications_*` / `group_info_details_updated` arb keys (and their generated getters) — a separate l10n-cleanup pass; deleting them would touch `app_localizations*.dart` generated files unnecessarily.
- Any redesign of the long-press context menu, the mute use-case, or the details-broadcast pipeline.
- A bespoke animated toast/pill widget — the minimal distinct SnackBar is the agreed cue.

## Files To Inspect Next
Production:
- `lib/features/groups/presentation/screens/group_info_wired.dart` — imports `:1-7` (ADD services.dart), `_onMuteChanged` `:478-537` (success snackbar `:499-509`, error snackbar `:524-530`), details success `:1938-1947`, details error path `:2012-2022`.
- `lib/features/groups/presentation/screens/group_conversation_screen.dart` — overlay pop `:1011`, `_copyMessageText` `:1031-1044`, services import `:5`.
- `lib/features/conversation/presentation/screens/conversation_screen.dart` — `_copyMessageText` `:879-893`, services import `:5`.
- `lib/core/widgets/quiet_confirm.dart` — NEW shared helper (haptic + distinct quiet-confirm cue).
- `lib/features/orbit2/presentation/screens/orbit2_screen.dart:109` — HapticFeedback precedent (reference only).
Direct tests:
- `test/features/groups/presentation/group_info_wired_test.dart` — mute test `:2854` (snackbar assert `:2893`), details snackbar assert `:3718` (inside EK004 `:3627`).
- `test/features/groups/presentation/group_conversation_screen_test.dart` — copy test `:540` (mock `:548-557`, snackbar asserts `:576-577`).
- `test/features/conversation/presentation/screens/conversation_screen_test.dart` — copy test `:1331` (mock `:1339`, asserts `:1376-1389`), Arabic copy `:1393` (asserts `:1430-1431`).
Dependency-only context:
- `lib/features/groups/application/set_group_muted_use_case.dart` (`setGroupMuted` — not edited).
- `lib/l10n/app_en.arb` / `app_ar.arb` / `app_de.arb` (`conversation_context_copied` at `:223` each — reused, not edited).

## Existing Tests Covering This Area
- `group_info_wired_test.dart:2854` "toggles mute state and persists it to the repository" — asserts switch flips `:2886-2891`, repo persists `:2892`, AND snackbar `:2893` `expect(find.text('Notifications muted for this group'), findsOneWidget)`. PASSES on HEAD. **`:2893` locks OLD behavior → must be rewritten** (drop snackbar assert; assert haptic fired; keep switch+repo asserts).
- `group_info_wired_test.dart:3627` "EK004 PREREQ-SIGNED-COMMIT-AUDIT admin metadata edit …" — asserts fields re-render (`:3716-3717`) AND snackbar `:3718` `expect(find.text('Group details updated'), findsOneWidget)`. PASSES on HEAD. **`:3718` locks OLD behavior → rewrite** (drop snackbar assert; assert haptic; keep field-render asserts). NOTE: `:3226/:3267/:3316/:3370` already assert `'Group details updated' findsNothing` (error/rollback paths) — those stay green unchanged.
- `group_conversation_screen_test.dart:540` "long-press copy action copies exact text and dismisses once" — mock filters only `Clipboard.setData` (`:549`); asserts clipboard fired `:573-574`, overlay gone `:575`, AND `find.byType(SnackBar) findsOneWidget` `:576` + `find.text('Message copied to clipboard') findsOneWidget` `:577`. PASSES. **`:576-577` lock OLD behavior → rewrite** (assert quiet-confirm key + haptic; assert NO generic error SnackBar).
- `conversation_screen_test.dart:1331` "copy action copies exact multiline text, replaces the prior snackbar, and dismisses the overlay" — asserts `find.byType(SnackBar) findsOneWidget` `:1376/:1388` + `'Message copied to clipboard'` `:1377/:1389`. PASSES. **Rewrite** to the quiet-confirm cue + haptic.
- `conversation_screen_test.dart:1393` "copy action localizes the snackbar in Arabic …" — asserts `find.byType(SnackBar)` `:1430` + Arabic text `:1431`. PASSES. **Rewrite** to assert the quiet-confirm cue carries the localized text (keep clipboard-fidelity assert `:1429`).
- `conversation_screen_test.dart:872`/`:1508` "…findsNothing" cases (copy unavailable / disposed) assert `'Message copied to clipboard' findsNothing` — those **stay green** (no quiet-confirm should appear there either).

Missing coverage gaps: NO test asserts a haptic on mute/details/copy (the SystemChannels.platform mock currently filters only `Clipboard.setData`); NO test asserts the **absence** of the success snackbar for mute/details; NO test asserts copy uses a **distinct** cue (not a generic error SnackBar).

Already in curated family arrays?:
- `group_conversation_screen_test.dart` ✅ `GROUP_TESTS` (`run_test_gates.sh:130`).
- `conversation_screen_test.dart` ✅ `ONE_TO_ONE_TESTS` (`:62`).
- `letter_card_test.dart` ✅ `GROUP_TESTS` (`:129`) — unaffected here, sentinel only.
- **`group_info_wired_test.dart` ❌ NOT in `GROUP_TESTS`** (`:116-132` lists `group_conversation_screen_test.dart` `:130` and `group_conversation_wired_test.dart` `:131`, not `group_info_wired_test.dart`). → registration step required.

## RED Test Catalog  (add/rewrite BEFORE any production code — INV-RED-FIRST)

1. `group_info_wired_test.dart`::"toggles mute state and persists it to the repository"  *(rewrite of `:2854`/`:2893`)*
   - Tier: integration/widget (wired screen, in-memory fakes)
   - Shape/setup: pump GroupInfoWired with an unmuted group; install a SystemChannels.platform mock that records `call.method == 'HapticFeedback.vibrate'` (extend the existing pattern); tap `ValueKey('group-mute-switch')`; `pumpFrames`.
   - RED on HEAD because: HEAD shows the `group_info_notifications_muted` snackbar (`:503`) and fires **no** haptic. New asserts (switch `isTrue` `:2891` + repo muted `:2892` + **haptic captured** + **no** `find.text('Notifications muted for this group')`) fail on both the snackbar-present and haptic-absent legs.
   - GREEN after fix asserts: switch flips `isTrue`; `groupRepo.getGroup().isMuted == true`; `HapticFeedback.vibrate` captured ≥1; `find.text('Notifications muted for this group') findsNothing`.
   - Mutation that re-reds: re-add the mute success snackbar (`showSnackBar(... group_info_notifications_muted ...)`) OR delete the `HapticFeedback.selectionClick()` call → red.
   - Discriminator: assert haptic captured AND success-snackbar text absent (one without the other passes a half-fix).

2. `group_info_wired_test.dart`::"admin details edit confirms via field re-render + haptic, no snackbar"  *(rewrite of the snackbar assert at `:3718` inside EK004 `:3627`; split into a focused case OR retarget the existing assert — keep the field/render + commandLog asserts intact)*
   - Tier: integration/widget
   - Shape/setup: drive the edit-details save (rename + description), platform mock capturing `HapticFeedback.vibrate`; `pumpFrames`.
   - RED on HEAD because: HEAD shows `group_info_details_updated` snackbar (`:1944`) and fires no haptic; new asserts (fields show new values `:3716-3717` + **haptic captured** + **no** `find.text('Group details updated')`) fail.
   - GREEN asserts: `find.text('Renamed Group') findsWidgets` + `find.text('Fresh description') findsOneWidget`; `HapticFeedback.vibrate` captured ≥1; `find.text('Group details updated') findsNothing`; existing `bridge.commandLog` ordering (`:3720-3724`) unchanged.
   - Mutation that re-reds: re-add the details success snackbar OR remove the haptic call → red.
   - Discriminator: keep the error-path `findsNothing` asserts (`:3226/:3267/:3316/:3370`) green — proves we only removed the SUCCESS snackbar, not the error ones.

3. `group_conversation_screen_test.dart`::"long-press copy action copies exact text and dismisses once"  *(rewrite of `:540`, asserts `:576-577`)*
   - Tier: widget
   - Shape/setup: EXTEND the platform mock (`:548-557`) so it ALSO captures `call.method == 'HapticFeedback.vibrate'` (currently only `Clipboard.setData`); long-press, tap copy.
   - RED on HEAD because: HEAD shows the floating snackbar (`group_conversation_screen.dart:1036-1043`) and fires no haptic; new asserts (clipboard fidelity kept `:573-574` + overlay gone `:575` + **quiet-confirm** `find.byKey(ValueKey('quiet-confirm')) findsOneWidget` carrying `'Message copied to clipboard'` + **haptic captured**) fail.
   - GREEN asserts: `clipboardCalls == 1`; `copiedText == copiedMessage`; overlay `findsNothing`; `find.byKey(const ValueKey('quiet-confirm')) findsOneWidget`; the quiet-confirm text resolves `conversation_context_copied`; `HapticFeedback.vibrate` captured ≥1.
   - Mutation that re-reds: revert `_copyMessageText` to the plain `showSnackBar(...)` (drop `showQuietConfirm`) → quiet-confirm key absent + no haptic → red.
   - Distinct-event discriminator: assert the quiet-confirm KEY (`ValueKey('quiet-confirm')`) is present — distinguishes the reserved error-snackbar channel from the success cue (a half-fix that left a keyless error-styled SnackBar would fail).

4. `conversation_screen_test.dart`::"copy action copies exact multiline text, replaces the prior snackbar, and dismisses the overlay"  *(rewrite of `:1331`, asserts `:1376-1389`)*
   - Tier: widget
   - Shape/setup: extend platform mock (`:1339-1348`) to also capture `HapticFeedback.vibrate`; two-copy sequence (`copy-1`, then `copy-2`).
   - RED on HEAD because: HEAD asserts a generic floating SnackBar with the copied text (`:1376-1389`); new asserts (clipboard fidelity `:1385-1386` + overlay gone `:1387` + quiet-confirm key present + replaces prior + haptic captured) fail because HEAD fires no haptic and uses a keyless snackbar.
   - GREEN asserts: `clipboardCalls == 2`; `copiedText == copiedMessage`; overlay `findsNothing`; `find.byKey(const ValueKey('quiet-confirm')) findsOneWidget` (single, prior replaced); `HapticFeedback.vibrate` captured ≥1.
   - Mutation that re-reds: revert 1:1 `_copyMessageText` to the plain snackbar → red.

5. `conversation_screen_test.dart`::"copy action localizes the quiet confirm in Arabic while preserving mixed-script clipboard text"  *(rewrite of `:1393`, asserts `:1430-1431`)*
   - Tier: widget
   - Shape/setup: locale `ar`; platform mock captures clipboard + haptic; long-press + copy.
   - RED on HEAD because: HEAD asserts a generic SnackBar `:1430` with the Arabic text `:1431`; new asserts (clipboard fidelity kept `:1429` + quiet-confirm key carrying `'تم نسخ الرسالة إلى الحافظة'` + haptic captured) fail (no haptic, keyless snackbar).
   - GREEN asserts: `copiedText == copiedMessage`; `find.byKey(const ValueKey('quiet-confirm')) findsOneWidget`; the quiet-confirm shows `'تم نسخ الرسالة إلى الحافظة'`; haptic captured.
   - Mutation that re-reds: revert 1:1 copy cue → red.

6. `conversation_screen_test.dart`::"copy unavailable / disposed shows neither snackbar nor quiet-confirm"  *(preservation sentinel — existing `:872` / `:1508` `findsNothing` cases extended)*
   - Tier: widget
   - Asserts: in the copy-unavailable (`:872`) and disposed-during-await (`:1508`) cases, `find.text('Message copied to clipboard') findsNothing` AND `find.byKey(const ValueKey('quiet-confirm')) findsNothing`. No change expected; guards against the quiet-confirm leaking into the no-op/disposed paths.
   - Mutation that re-reds: make `showQuietConfirm` unconditional (drop the `mounted`/`maybeOf` guard) → cue appears on the disposed path → red.

## Test Coverage Matrix  (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 mute → haptic + control, no snackbar | screen state + haptic + snackbar-absent | integration/widget | group_info_wired_test::"toggles mute state and persists it to the repository" | HEAD shows `group_info_notifications_muted` snackbar + no haptic | re-add mute success snackbar OR drop `HapticFeedback.selectionClick()` | `./scripts/run_test_gates.sh groups` | **add `group_info_wired_test.dart` to `GROUP_TESTS`** |
| TC-02 details → haptic + field render, no snackbar | screen render + haptic + snackbar-absent | integration/widget | group_info_wired_test::"admin details edit confirms via field re-render + haptic, no snackbar" | HEAD shows `group_info_details_updated` snackbar + no haptic | re-add details success snackbar OR drop haptic | `./scripts/run_test_gates.sh groups` | add `group_info_wired_test.dart` to `GROUP_TESTS` |
| TC-03 group copy → haptic + quiet-confirm, no error snackbar | widget render + haptic + distinct cue | widget | group_conversation_screen_test::"long-press copy action copies exact text and dismisses once" | HEAD shows floating `conversation_context_copied` snackbar (keyless) + no haptic | revert `_copyMessageText` to plain `showSnackBar` | `./scripts/run_test_gates.sh groups` | AUTO (already in `GROUP_TESTS:130`) |
| TC-04 1:1 copy → haptic + quiet-confirm | widget render + haptic + replace-prior | widget | conversation_screen_test::"copy action copies exact multiline text, replaces the prior snackbar, and dismisses the overlay" | HEAD shows keyless floating snackbar + no haptic | revert 1:1 `_copyMessageText` to plain snackbar | `./scripts/run_test_gates.sh 1to1` | AUTO (already in `ONE_TO_ONE_TESTS:62`) |
| TC-05 1:1 copy Arabic localized cue | l10n + cue + clipboard fidelity | widget | conversation_screen_test::"copy action localizes the quiet confirm in Arabic while preserving mixed-script clipboard text" | HEAD shows keyless snackbar w/ Arabic text + no haptic | revert 1:1 copy cue | `./scripts/run_test_gates.sh 1to1` | AUTO (`ONE_TO_ONE_TESTS:62`) |
| TC-06 copy no-op/disposed shows no cue | guard / negative | widget | conversation_screen_test::"copy unavailable / disposed shows neither snackbar nor quiet-confirm" | n/a pre-feature; mutation-verifiable | drop the `mounted`/`maybeOf` guard in `showQuietConfirm` | `./scripts/run_test_gates.sh 1to1` | AUTO (`ONE_TO_ONE_TESTS:62`) |

## Invariants (locked by tests)
- INV-1: muting/unmuting fires `HapticFeedback.selectionClick()` and shows **no** `group_info_notifications_muted/_restored` snackbar; the switch+repo state still flips → TC-01.
- INV-2: a successful details edit fires the haptic and shows **no** `group_info_details_updated` snackbar; the name/description fields still re-render → TC-02.
- INV-3: copy (group + 1:1) fires the haptic and shows a **distinct quiet-confirm cue** (`ValueKey('quiet-confirm')`) carrying `conversation_context_copied`, **not** a generic error-style SnackBar → TC-03/04/05.
- INV-4: clipboard text fidelity (multiline / mixed-script / Arabic) is unchanged → TC-03/04/05.
- INV-5: the quiet-confirm cue does **not** appear on the copy-unavailable / disposed paths → TC-06.
- INV-6 (channel reservation, preserved): error snackbars stay — `group_info_mute_update_failed`, the details error/rollback path, `group_invite_decline_failed` — proven by the still-green error-path asserts (`group_info_wired_test.dart:3226/:3267/:3316/:3370`) → TC-02 discriminator + preservation gate.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short`. Add/rewrite the 6 catalog tests; run the focused cmds; confirm each fails for its documented reason (snackbar present / no haptic / no quiet-confirm key).
2. `lib/core/widgets/quiet_confirm.dart` (NEW): `void showQuietConfirm(BuildContext context, String message)` that (a) calls `HapticFeedback.selectionClick()`, then (b) via `ScaffoldMessenger.maybeOf(context)` (null-guarded; no-op if unmounted/no messenger) hides the current SnackBar and shows a short, success-styled SnackBar `key: const ValueKey('quiet-confirm')`, reduced `duration` (~1.2s), `behavior: SnackBarBehavior.floating`, non-error styling. Import `package:flutter/material.dart` + `package:flutter/services.dart`. Stop-if: a SnackBar can't carry a stable findable key in this Flutter version → fall back to a minimal `OverlayEntry` pill with the same `ValueKey('quiet-confirm')` (still no new l10n).
3. `group_info_wired.dart`: add `import 'package:flutter/services.dart';` (after `package:flutter/material.dart` `:7`). In `_onMuteChanged`: after the `setState` flip (`:495-498`) call `HapticFeedback.selectionClick();` and DELETE the success `showSnackBar` block (`:499-509`). Keep the catch error snackbar (`:524-530`) untouched. In the details success branch: after `await _loadGroupInfo();` (`:1939`) call `HapticFeedback.selectionClick();` and DELETE the success `showSnackBar` block (`:1941-1947`). Keep the details error/rollback snackbar (`:2012-2022`) untouched.
4. `group_conversation_screen.dart` `_copyMessageText` (`:1031-1044`): replace the `messenger?..hideCurrentSnackBar()..showSnackBar(...)` body with `showQuietConfirm(context, AppLocalizations.of(context)!.conversation_context_copied);` (keep `Clipboard.setData` first). services.dart already imported (`:5`).
5. `conversation_screen.dart` `_copyMessageText` (`:879-893`): same replacement, keeping the `if (!mounted) return;` guard before showing the cue. services.dart already imported (`:5`).
6. Do NOT touch the DECLINE snackbar (`group_list_wired.dart`) — owned by 153.
7. `scripts/run_test_gates.sh`: add `"test/features/groups/presentation/group_info_wired_test.dart"` to the `GROUP_TESTS` array (`:116-132`).
8. Rerun direct → preservation → named gates; `flutter analyze` (0-new); `git diff --check`. Note (do NOT delete) the now-unused arb keys `group_info_notifications_muted/_restored/group_info_details_updated`.

## Risks And Edge Cases
- **Copy invisibility** if the cue is dropped: copy has no control state (overlay popped at `:1011`) → the quiet-confirm cue is mandatory → pinned by TC-03/04/05.
- **Cue indistinguishable from an error snackbar**: would re-pollute the reserved channel → the `ValueKey('quiet-confirm')` discriminator + non-error styling pin it (TC-03).
- **Cue leaking onto the disposed/no-op copy path** → `mounted`/`maybeOf` guard, pinned by TC-06.
- **Haptic mock channel**: `HapticFeedback.selectionClick()` routes through `SystemChannels.platform` as method `HapticFeedback.vibrate` — tests MUST capture that exact method string (the existing mocks only filtered `Clipboard.setData`); a mock that returns `null` for all other methods is required so clipboard still works.
- **services.dart import only in group_info_wired.dart**: adding it to the conversation screens would be a redundant duplicate-import analyze warning — they already import it; pinned by `flutter analyze` 0-new.
- **Unused l10n keys**: leaving `group_info_notifications_*` / `group_info_details_updated` unreferenced is harmless (arb keys without consumers don't fail analyze); deleting them would churn generated `app_localizations*.dart` — explicitly deferred.

## Device/Relay Proof Profile
host-only for closure. Pure presentation (snackbar removal, haptic call, a local cue) — no OS-boundary / ML-KEM / relay / multi-device / migration leg. `HapticFeedback` is mocked at the `SystemChannels.platform` boundary in widget tests; no device evidence required. (A render-proof is not warranted — there is no new persisted surface, only a transient cue + a method-channel call already exercised via the platform mock.)

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/groups/presentation/group_info_wired_test.dart \
  --plain-name 'toggles mute state and persists it to the repository'
flutter test test/features/groups/presentation/group_conversation_screen_test.dart \
  --plain-name 'long-press copy action copies exact text and dismisses once'
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart \
  --plain-name 'copies exact multiline text'

# Direct GREEN (after fix)
flutter test test/features/groups/presentation/group_info_wired_test.dart
flutter test test/features/groups/presentation/group_conversation_screen_test.dart
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart

# Preservation + named gates (after adding group_info_wired_test to GROUP_TESTS)
./scripts/run_test_gates.sh groups        # group_info_wired now curated; expect prior green + rewritten cases; the 2 PRE-EXISTING wired fails (GMAR-004 reopen-hydration, incoming-group-image-refresh) are NOT mine
./scripts/run_test_gates.sh 1to1          # conversation_screen_test copy cases green
./scripts/run_test_gates.sh feed          # LetterCard / feed unaffected, stay green

# Hygiene
flutter analyze            # 0 new issues (esp. no duplicate services.dart import)
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the 6 catalog tests before the fix (success-snackbar present / no haptic captured / no quiet-confirm key).
- Pre-existing dirty (NOT mine): the Groups suite has **2 pre-existing failing wired tests** — `GMAR-004` reopen-hydration and incoming-group-image-refresh (in `group_conversation_wired_test.dart`, unrelated to this plan). Record before execution; do not "fix" by reverting.
- The wider tree is already dirty on `new-feed` (uncommitted Feed/Orbit work per `git status`) — snapshot `git status --short` first; touch only the Real-Scope files.
- Environment blocker (NOT product): none (host-only, no sim/device).
- Scope drift (BLOCKING): any failure outside the listed files/tests, or any change to the DECLINE snackbar (153) / error snackbars.

## Done Criteria
- [ ] RED added/rewritten first, failed for the expected reason (snackbar-present + haptic-absent legs).
- [ ] Each fix mutation-verified (re-red revert named in the matrix).
- [ ] Direct GREEN + groups/1to1/feed preservation gates pass; the 2 pre-existing wired fails unchanged.
- [ ] No migration introduced (pure presentation).
- [ ] `group_info_wired_test.dart` added to `GROUP_TESTS` and confirmed running in `./scripts/run_test_gates.sh groups`.
- [ ] `group_info_wired.dart` imports `package:flutter/services.dart`; both conversation screens left with their single existing import (no duplicate).
- [ ] Mute + details success snackbars removed; copy uses haptic + distinct `quiet-confirm` cue; error snackbars (mute_update_failed, details error path, decline_failed) untouched.
- [ ] `flutter analyze` 0-new; `git diff --check` clean.

## Scope Guard (hard "Do not")
- Do not add a DB migration or bump `currentIdentityDatabaseVersion` (no schema change).
- Do not touch the DECLINE success snackbar / Undo affordance (`group_list_wired.dart`) — owned by plan 153.
- Do not remove or rename `conversation_context_copied` (reused by the quiet-confirm cue) — and only ever remove a copy-cue key after BOTH call sites (group :1039, 1:1 :888) stop using it.
- Do not remove the error snackbars: `group_info_mute_update_failed`, the details error/rollback path (`:2012-2022`), `group_invite_decline_failed`.
- Do not delete the now-unused `group_info_notifications_*` / `group_info_details_updated` arb keys or regenerate `app_localizations*.dart` in this plan (deferred l10n cleanup).
- Do not add `services.dart` to the conversation screens (already imported → duplicate-import warning).
- Do not build a bespoke animated toast widget — the minimal keyed SnackBar (or OverlayEntry fallback) is the cue.

## Accepted Differences / Intentionally Out Of Scope
- The unused success-l10n keys remain in the arb files (no consumer) — accepted; a follow-up l10n-cleanup pass owns their removal (it touches generated getters).
- The quiet-confirm cue is a short keyed SnackBar (or OverlayEntry fallback), not a new design-system pill component — accepted; no reusable toast/pill exists and building one is out of scope.
- Mute/details rely on the already-updated control/field as the confirmation; only copy keeps a visible cue (because it has no control state) — accepted asymmetry per root cause.

## Dependency Impact
- None outbound. Plan 153 (Undo) owns the DECLINE snackbar independently; this plan deliberately does not touch it. The harness-registration fix (adding `group_info_wired_test.dart` to `GROUP_TESTS`) retroactively gates ALL existing group-info behavior (mute/details/invite/role) under the curated Group gate — a standalone hardening win.

## Reviewer Findings
<pending — Reviewer (sufficiency) pass to fill: confirm the SystemChannels.platform `HapticFeedback.vibrate` capture string is correct in this Flutter version; confirm the keyed-SnackBar findability or the OverlayEntry fallback; confirm the EK004 rewrite (TC-02) does not weaken the signed-commit/audit asserts it shares a test with.>

## Arbiter Decision
<pending — final structural verdict: host-only closure, no migration, no device-proof; matrix has zero empty cells across tier/mutation/gate/registration; the only registration add is `group_info_wired_test.dart` → `GROUP_TESTS`.>

## Final Execution Verdict
<pending execution>
