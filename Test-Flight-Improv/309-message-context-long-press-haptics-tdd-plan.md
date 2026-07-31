# 309 - Message Context Long-Press Haptics

Status: completed
Type: Feature Improvement
Spec: free-text intent — add a small tactile cue when a message long press opens the context menu in 1:1 and group conversations, for text, media, and voice bubbles
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-31 18:41 CEST | Evidence Collector | `message_context_overlay.dart`, `conversation_screen.dart`, `group_conversation_screen.dart`, `letter_card.dart`, their widget tests, `quiet_confirm.dart`, `run_test_gates.sh` | Confirmed that all requested long-press paths converge on one overlay lifecycle and that overlay opening currently sends no app-owned haptic request | Build the smallest causal widget contract |
| 2026-07-31 18:41 CEST | Planner | same files plus Graphify snapshot and TDD tier/gate references | One shared `lightImpact` mount hook plus direct/group variant coverage is sufficient; no native, schema, transport, or device campaign is required | Run `$tdd-review` before execution |
| 2026-07-31 18:46 CEST | Reviewer | plan, current constructors/callers, audio gesture seam, platform-channel tests, gate discovery | Core bet confirmed; require isolated per-variant call discrimination and an exact path for the direct copy sentinel | Patch the two bounded contract gaps, rerun review lenses, then execute |

## Problem And Evidence

- Behavior to improve: when a user long-presses a text, visual-media, or voice message and its context overlay opens, the app should request one small tactile impact in both 1:1 and group conversations.
- Impact: the menu currently appears without the tactile acknowledgement common to messaging interactions, so long-press recognition feels less immediate.
- Confirmed current gap: `_MessageContextOverlayState` at `lib/features/conversation/presentation/widgets/message_context_overlay.dart:93-103` has no mount-time haptic; the only relevant existing message-action haptic is the later copy confirmation's `HapticFeedback.selectionClick()` at `lib/core/widgets/quiet_confirm.dart:18-21`.
- Confirmed convergence: direct row and visual-media long presses route through `_showMessageContextOverlay` at `lib/features/conversation/presentation/screens/conversation_screen.dart:1369-1389,1583-1656,1812-1830`; group row and visual-media long presses route through the same shared widget at `lib/features/groups/presentation/screens/group_conversation_screen.dart:911-970,1233-1310`. Voice attachments render inside the card body while the card-level long press remains at `lib/features/conversation/presentation/widgets/letter_card.dart:435-470,900-916`.
- Existing coverage: direct and group screen suites already prove text and media long presses open `MessageContextOverlay`; both curated lane arrays already include the affected screen suites at `scripts/run_test_gates.sh:88,397`.
- Missing coverage: no test asserts an opening haptic, the exact `lightImpact` variant, exactly-once behavior across rebuild, or voice-bubble parity.
- Refuted findings: six independent production hooks are not required; current-source constructor census finds only the direct and group production dialogs mounting the shared overlay. A haptic in each bubble renderer would duplicate logic and risks double feedback on media cells.
- Unresolved findings: N/A — OS/device-specific actuator strength remains platform-owned and is not claimed by this app-layer plan.
- Affected production, test, and gate files: `message_context_overlay.dart`; `message_context_overlay_test.dart`; `conversation_screen_test.dart`; `group_conversation_screen_test.dart`. No gate-script edit is expected.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `6f47d12c12806538`; `stale:ios/Flutter/flutter_export_environment.sh` only, an unrelated generated iOS environment file.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Where are onLongPress handlers and contextual menus implemented for 1:1 and group message bubbles including text, media, and voice, and which widget tests plus ONE_TO_ONE_TESTS or GROUP_TESTS gates cover them?" --profile tdd --budget 700`.
- Anchors: `onLongPress` -> `lib/shared/widgets/media/media_grid_cell.dart`; `ONE_TO_ONE_TESTS` -> `scripts/run_test_gates.sh:25`.
- Surfaced proof/gate files: `media_grid_cell.dart`, `media_grid_cell_test.dart`, `group_conversation_screen_test.dart`, and `run_test_gates.sh`.
- Graph gaps requiring source search: the compact graph did not surface `MessageContextOverlay`, the two screen dialog constructors, voice rendering, or the existing copy haptic; targeted current-source searches supplied those anchors.
- Reuse rule: anchors may be handed to review/execution; all conclusions still require current-source or command evidence.

## Scope Contract And Guard

In scope:
- Request `HapticFeedback.lightImpact()` exactly once when a new `MessageContextOverlay` state mounts.
- Prove 1:1 and group text, visual-media, and voice long presses each open the overlay and produce one exact light-impact platform call.

Must preserve:
- Existing overlay layout, actions, callbacks, dismissal, reactions, media targeting, and authorization -> existing direct/group context-overlay suites.
- Copy confirmation remains the distinct later `HapticFeedback.selectionClick()` -> `conversation_screen_test.dart::copy action copies exact multiline text, replaces the prior snackbar, and dismisses the overlay` and `group_conversation_screen_test.dart::long-press copy action copies exact text and dismisses once`.
- Rows that cannot open a context overlay remain unchanged; the haptic belongs to overlay mount, not raw pointer-down or long-press recognition.

Hard `Do not`:
- Do not add native Android/iOS code, a vibration plugin, custom patterns, settings, localization, persistence, schema, wire, crypto, relay, or message-model changes.
- Do not put haptics in both screen handlers and the shared overlay, and do not alter the existing action-confirmation haptic.

Deferred / accepted difference:
- Physical intensity and whether the OS suppresses haptics are device/user-setting concerns. This plan proves the app's exact Flutter platform request and does not claim actuator-strength parity -> owner: platform/OS, because no native implementation changes.

Dependencies:
- Flutter's existing `services.dart` `HapticFeedback` API and `SystemChannels.platform` test seam; no new package.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-309-01 | A newly mounted shared message overlay requests one light impact and ordinary rebuild does not repeat it | `test/features/conversation/presentation/widgets/message_context_overlay_test.dart::emits one light-impact haptic on mount and does not repeat on rebuild` | Widget / mocked `SystemChannels.platform` | HEAD records zero `HapticFeedbackType.lightImpact` calls -> GREEN records exactly one after mount and still one after repump/rebuild | Move the request from `initState` to `build`, or remove it -> rebuild count differs or remains zero and TC-309-01 reds | `flutter test test/features/conversation/presentation/widgets/message_context_overlay_test.dart --plain-name 'emits one light-impact haptic on mount and does not repeat on rebuild'`; AUTO (`test/features/**` glob) |
| TC-309-02 | 1:1 text, visual-media, and voice long presses each open the menu with one light impact | `test/features/conversation/presentation/screens/conversation_screen_test.dart::1:1 text, media, and voice long-press overlays each emit one light impact` | Widget / real `ConversationScreen`, isolated message fixtures, mocked platform channel | For each isolated fixture, HEAD opens the overlay but its reset call list stays empty -> GREEN opens the overlay and records the exact singleton `lightImpact` call before dismissal | Remove the shared mount request or change it to `selectionClick` -> that variant's exact singleton assertion reds | `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name '1:1 text, media, and voice long-press overlays each emit one light impact'`; `ONE_TO_ONE_TESTS` existing registration (`scripts/run_test_gates.sh:88`) |
| TC-309-03 | Group text, visual-media, and voice long presses each open the menu with one light impact | `test/features/groups/presentation/group_conversation_screen_test.dart::group text, media, and voice long-press overlays each emit one light impact` | Widget / real `GroupConversationScreen`, isolated message/media fixtures, mocked platform channel | For each isolated fixture, HEAD opens the overlay but its reset call list stays empty -> GREEN opens the overlay and records the exact singleton `lightImpact` call before dismissal | Bypass group construction or change/remove the shared request -> that variant's overlay/call discriminator reds | `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'group text, media, and voice long-press overlays each emit one light impact'`; `GROUP_TESTS` existing registration (`scripts/run_test_gates.sh:397`) |
| TC-309-04 | Copy retains its later, semantically distinct selection-click confirmation | `test/features/conversation/presentation/screens/conversation_screen_test.dart::copy action copies exact multiline text, replaces the prior snackbar, and dismisses the overlay` plus `test/features/groups/presentation/group_conversation_screen_test.dart::long-press copy action copies exact text and dismisses once` | GREEN sentinel / widget mocked platform channel | GREEN on HEAD for one/two `selectionClick` action confirmations -> remains GREEN alongside additive opening `lightImpact` calls | Replace/remove `showQuietConfirm`'s `selectionClick` -> sentinel reds; replacing opening impact with selection click is caught by TC-309-01..03 | `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name 'copy action copies exact multiline text, replaces the prior snackbar, and dismisses the overlay' && flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'long-press copy action copies exact text and dismisses once'`; existing lane registrations |

### Test Notes

- TC-309-02/03 must run text, visual-media, and voice as isolated pump/open/assert/dismiss cases. Clear the recorded platform calls before every long press; for that variant assert both `MessageContextOverlay.overlayKey` and the exact singleton `MethodCall('HapticFeedback.vibrate', 'HapticFeedbackType.lightImpact')`. An aggregate final count is insufficient because three calls clustered on one variant could hide two bypasses.

## Implementation Steps

1. Snapshot `git status --short` and preserve all unrelated dirty changes. Add TC-309-01..03 before production edits and run the exact causal commands to record assertion REDs caused by absent light-impact calls.
2. Import `package:flutter/services.dart` in `message_context_overlay.dart` and request `HapticFeedback.lightImpact()` from `_MessageContextOverlayState.initState` after `super.initState()`. Stop-if: a causal test proves any requested bubble type bypasses `MessageContextOverlay`; then move only that bypass to a successful-open seam without duplicating shared feedback.
3. No gate registration edit is expected: the new shared test is AUTO-globbed and the modified direct/group files are already in their named lane arrays.
4. Run focused GREEN, TC-309-04 sentinels, a representative remove-call mutation re-red and restore, both affected curated lanes, analyzer, and diff hygiene.

## Risks And Blind Spots

- Duplicate haptics from rebuilding the overlay -> TC-309-01 requires exactly one per state lifetime.
- Wrong feedback strength or reuse of copy's selection event -> TC-309-01..03 match the exact `HapticFeedbackType.lightImpact` argument while TC-309-04 preserves `selectionClick`.
- Sibling-surface consistency -> TC-309-02 and TC-309-03 enumerate text, media, and voice on both requested surfaces.
- Lifecycle / derived-state durability: N/A — no durable or derived state is introduced.
- Destructive-action side effects: N/A — no delete, cleanup, or persistence path changes.
- Invariant re-verification under new transitions: overlay remount is the intended new interaction and TC-309-01 proves one request per mount without rebuild duplication.

## Gate Cadence

- Per-plan closure: three focused causal tests, the two exact copy sentinels, then `./scripts/run_test_gates.sh 1to1` and `./scripts/run_test_gates.sh groups`. No broader family sweep is justified beyond the two affected curated lanes.
- Do not run full `host-all` for this individual plan. Run `./scripts/run_host_test_gates.sh host-all` once after the message-context interaction dependency wave containing Plan 309, and once at final rollout/release closure.
- Shared tests outside feature/core globs: N/A — all new/modified tests are under `test/features/**`.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes
git status --short

# Causal REDs before production edits; each must exit non-zero because the exact
# lightImpact call is absent, while its overlay-presence assertion succeeds
flutter test test/features/conversation/presentation/widgets/message_context_overlay_test.dart --plain-name 'emits one light-impact haptic on mount and does not repeat on rebuild'
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name '1:1 text, media, and voice long-press overlays each emit one light impact'
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'group text, media, and voice long-press overlays each emit one light impact'

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/features/conversation/presentation/widgets/message_context_overlay_test.dart
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart
flutter test test/features/groups/presentation/group_conversation_screen_test.dart

# Affected curated lanes; expect exit 0, target suites selected, zero failures
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups

# Hygiene; expect no new analyzer issues and no whitespace errors
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-309-01..03 fail only on missing exact `lightImpact` platform calls after proving the corresponding overlay exists.
- Green sentinel: TC-309-04 remains green for the existing copy `selectionClick` and callback effects.
- Pre-existing dirty tree / known failure: the working tree already contains Plans 303-308 implementation/plan changes and generated Graphify output; execution must not overwrite or reclassify them.
- Environment blocker: none expected; host widget tests mock the Flutter platform channel and do not require a connected device.
- Scope drift: any need for native code, a new plugin, message-state changes, or per-bubble duplicate hooks blocks completion and requires replanning.

- [x] Every requested bubble/surface behavior has named causal coverage.
- [x] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [x] Copy-action preservation and both curated lane gates pass.
- [x] Existing AUTO/array registration is verified; no unnecessary gate edit lands.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/conversation/presentation/widgets/message_context_overlay_test.dart --plain-name 'emits one light-impact haptic on mount and does not repeat on rebuild'`.
- Preservation command: the two TC-309-04 exact `flutter test ... --plain-name ...` commands.
- Manual registration: none; shared test AUTO-globbed, direct/group screen suites already pinned.
- Migration: none.
- Boundary closure: host-only app request seam; physical actuator strength is explicitly not claimed.
- Unresolved evidence: none.

## Reviewer Findings

- `$tdd-review` initial verdict: `plan-fixes-required`; core bet confirmed; disposition `apply-plan-fixes`.
- L1 evidence truth: clear — current-source constructor census confirms only the direct and group production dialogs mount `MessageContextOverlay`, and voice's inner control owns tap only, leaving the card long-press recognizer active.
- L2 test causality: tightened — TC-309-02/03 now reset and assert per variant instead of permitting an aggregate-only false green; TC-309-04 now names both exact test paths.
- L3 bypass/scope safety: clear — direct plain/media and group plain/media branches all converge before the shared constructor; no background, lifecycle, notification, or native entrypoint mounts this UI.
- L4 gate integrity: clear — the new shared widget test is AUTO-discovered by `feature-host-all`; direct and group screen suites are already pinned in their respective curated arrays.
- L5 boundary/reversibility: N/A for app closure — no state, migration, native implementation, or irreversible effect changes; the plan claims only the Flutter platform request, not physical actuator strength.
- Blind-spot sweep: B-2/B-3/B-4/B-9 were exercised; the only hits were the two corrected L2 contract gaps. B-1/B-5/B-6/B-8/B-10 are N/A; B-7 is clear because the existing Flutter API is the sole mechanism and no fallback is introduced.
- Post-fix verdict: `ready`; disposition `execute`; no user-owned decision remains.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-31 18:50 CEST | causal RED | three planned widget test files | each exact `--plain-name` command exited 1 | overlay presence succeeded; exact haptic list was empty in shared, direct-text, and group-text first cases | expected RED, no blocker | add the shared mount hook |
| 2026-07-31 18:51 CEST | focused GREEN | shared overlay plus direct/group screen tests | three exact causal commands and both exact copy sentinels exited 0 | shared mount/rebuild and all six isolated text/media/voice paths emitted exact `lightImpact`; copy retained `selectionClick` | implementation matches reviewed contract | run mutation and full suites |
| 2026-07-31 18:52 CEST | mutation | `message_context_overlay.dart` | removing `HapticFeedback.lightImpact()` made TC-309-01 exit 1; restored call returned suite to green | representative mutation independently re-reds the contract | mutation proven and restored | run closure gates |
| 2026-07-31 18:59 CEST | closure | production/test files and Graphify overlay | full suites 16/80/73 green; `1to1` 2,524 green plus relay; `groups` 3,266 green plus group/relay Go tails; analyzer/diff/Graphify refresh green | no failures, no registration edit, no scope drift | Plan 309 complete | aggregate `host-all` remains owned by the named wave/final cadence |
