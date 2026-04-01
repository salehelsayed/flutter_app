# Session 52 Plan: Shared Anchored Long-Press Overlay and Orbit Conversation Adoption

## Evidence collector summary

- `ConversationScreen` still routes `LetterCard.onLongPress` to `_showReactionBar(...)`, which opens `ReactionBar` through `showDialog(..., barrierColor: Colors.transparent)` and only exposes emoji reactions plus the full-picker handoff.
- `LetterCard` already exposes long-press, and `ConversationScreen` already has access to `message.id`, `message.text`, `message.media`, `message.isIncoming`, current reactions, and the pressed card render box.
- `ComposeArea` owns its own `FocusNode` and quote preview UI, but has no `shouldRequestFocus` seam; `InlineReplyInput` already uses that exact pattern on the feed side.
- Current direct tests cover long-press dispatch, `ReactionBar` behavior, quote preview rendering, and swipe-to-reply send persistence, but they do not yet prove a blurred context overlay, copy gating, or composer focus handoff after long-press reply.
- `ReactionBar` is reused by feed and group screens today, so Session 52 must avoid a refactor that forces feed/group adoption before Session 53.

## Real scope

- Introduce a shared long-press overlay host for Orbit 1:1 that composes:
  - a full-screen blurred dismissal layer
  - the existing quick-reaction bar anchored above the pressed message
  - a two-action glass context menu below the pressed message
- Adopt that overlay only from `ConversationScreen` / `LetterCard` long-press.
- Support `Reply` for both incoming and sent Orbit messages by reusing the existing quote path.
- Support `Copy` only when the pressed message has non-empty text.
- Add the missing conversation-composer focus-request plumbing needed for long-press `Reply`.

## Closure bar

- Long-press on sent and received Orbit messages shows one overlay with blur, anchored reactions, and a `Reply` / `Copy` menu.
- `Reply` dismisses the overlay, activates the existing quote preview, and requests focus for the conversation text field.
- `Copy` copies the exact message text and dismisses the overlay; no-text messages do not expose an active copy action.
- Reaction tap, `+` picker handoff, background tap, and back-button dismissal preserve current Orbit semantics.
- Permanent conversation-level regressions land for overlay appearance, reply activation/focus, and copy gating.
- `baseline` remains the required named gate; `1to1` is only required if implementation crosses into quoted-message send/persist logic instead of staying UI/focus-only.

## Source of truth

- Active session contract:
  - `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
  - `Test-Flight-Improv/26-long-press-message-context-menu.md`
- Regression/gate authority:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Scope guard against reliability expansion:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Current code and tests win over stale prose when they disagree.
- If `test-gate-definitions.md` and `./scripts/run_test_gates.sh` ever disagree, the script wins.

## Session classification

`implementation-ready`

## Exact problem statement

- Orbit long-press currently exposes only `ReactionBar` in a transparent dialog, so the long-press gesture does not surface `Reply`, does not support `Copy`, and does not blur the background.
- Orbit quote activation currently reaches only the existing swipe-to-reply path; long-press reply parity for sent messages is missing.
- The conversation composer cannot currently request focus from a new reply action even though the feed inline reply input already has a `shouldRequestFocus` pattern.
- This session must improve long-press discoverability and action parity without changing swipe-to-reply rules, reaction transport, or 1:1 send/retry/recovery semantics.

## Files and repos to inspect next

Exact production files:

- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/reaction_bar.dart`
- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_de.arb`
- `lib/l10n/app_ar.arb`

Blast-radius references only; not planned Session 52 edit targets:

- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/feed/presentation/widgets/inline_reply_input.dart`

Exact direct tests:

- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/widgets/reaction_bar_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/features/conversation/presentation/widgets/compose_area_test.dart`

Probable new direct test if a dedicated overlay host is extracted:

- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`

## Existing tests covering this area

- `test/features/conversation/presentation/widgets/letter_card_test.dart`
  - proves `LetterCard` long-press dispatch still fires.
- `test/features/conversation/presentation/widgets/reaction_bar_test.dart`
  - proves preset emoji rendering, `+` handling, dismiss behavior, and scale animation.
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - proves quote preview rendering, incoming-only swipe wrapper behavior, and message-list composition.
- `test/features/conversation/presentation/widgets/compose_area_test.dart`
  - proves quote preview rendering and clearing, but not any focus-request behavior.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - proves swipe-to-reply activates quoted-message send persistence, but not long-press reply, copy, or focus.

Current coverage gaps:

- no test proves the new long-press overlay content or dismissal behavior
- no test proves sent-message long-press reply parity
- no test proves text-only copy gating or clipboard behavior
- no test proves composer focus request after long-press reply

## Regression/tests to add first

- Add a `ConversationScreen` regression for long-press on a received text message:
  - prove blur-host overlay appears with reactions above and `Reply` / `Copy` actions below.
- Add a `ConversationScreen` regression for long-press on a sent text message:
  - prove long-press `Reply` exists for outgoing Orbit messages without changing swipe-to-reply rules.
- Add a `ConversationScreen` or dedicated overlay-widget regression for a no-text/media-only message:
  - prove `Copy` is hidden or disabled while the rest of the overlay still works.
- Add a `ComposeArea` regression for the new focus-request seam:
  - prove a request focuses the text field without wiping existing draft text.
- Add a `ConversationWired` vertical-slice regression:
  - long-press `Reply` activates quote preview, requests focus, and still sends the correct `quotedMessageId`.

## Step-by-step implementation plan

1. Add a minimal shared long-press overlay host adjacent to `reaction_bar.dart`.
   It should own the blurred full-screen backdrop, anchored placement, and glass context menu while composing the existing `ReactionBar` instead of rewriting reaction behavior inline.
2. Keep `ReactionBar` backward-compatible for current feed/group call sites.
   If the overlay host needs richer anchor data, add it there rather than forcing feed/group screens to adopt new `ReactionBar` constructor requirements during Session 52.
3. Replace `ConversationScreen._showReactionBar(...)` with a new Orbit-only overlay show path.
   Capture the pressed message metadata and pressed card render box, then wire:
   - emoji taps to the current `onReactionSelected`
   - `+` to the current full-picker flow
   - `Reply` to the existing `widget.onQuoteReply`
   - `Copy` to `Clipboard.setData` only when `message.text.trim().isNotEmpty`
4. Add a local composer focus-request seam in `ConversationScreen` and pass it into `ComposeArea`.
   Mirror the existing `InlineReplyInput.shouldRequestFocus` pattern instead of inventing a new controller architecture.
5. Update `ComposeArea` to honor a one-shot focus request without clobbering draft text or causing repeated focus grabs on ordinary rebuilds.
6. Reuse existing localized strings only if they fit the menu wording exactly enough.
   If not, add dedicated ARB entries for the overlay menu labels and copy feedback; do not widen into a general quote-preview localization cleanup.
7. Land the direct regressions first or alongside the implementation.
   Stop immediately if the work would require feed callback-contract widening or group-surface adoption; that belongs to Session 53 or later.

## Risks and edge cases

- `ReactionBar` is shared by Orbit, feed, and group screens today; a breaking API change there would widen scope immediately.
- Overlay dismissal has multiple exits:
  - reaction tap
  - `+` full-picker handoff
  - background tap
  - system back
  All must dismiss exactly once and leave no duplicate overlays.
- Messages near the top edge still need safe on-screen placement; the anchored bar/menu must clamp rather than render off-screen.
- `Copy` must stay text-only:
  - do not copy media preview labels
  - do not expose `Copy` for blank-text or media-only rows
- Focus request must be one-shot:
  - it must not overwrite draft text
  - it must not steal focus on unrelated later rebuilds
- Existing quote preview strings are currently hardcoded outside ARB-backed menu text; do not let Session 52 turn into a repo-wide localization cleanup.

## Exact tests and gates to run

Direct tests:

- `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `flutter test test/features/conversation/presentation/widgets/compose_area_test.dart`
- `flutter test test/features/conversation/presentation/widgets/reaction_bar_test.dart`
- `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
- `flutter test test/features/conversation/presentation/widgets/message_context_overlay_test.dart` if that new widget test file is added

Named gates:

- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh 1to1` only if implementation changes the quoted-message send/persist path instead of staying in UI/focus activation

Not required for Session 52 as currently scoped:

- `./scripts/run_test_gates.sh feed`
- `./scripts/run_test_gates.sh transport`

## Known-failure interpretation

- No Session 52-specific known failures are documented in `test-gate-definitions.md` for these direct conversation presentation tests or the `baseline` gate.
- Any failure in the newly added direct overlay/focus/copy regressions should be treated as a real Session 52 regression.
- A failing named gate should only be treated as pre-existing if it is already documented in repo tracking or can be reproduced on unmodified HEAD; do not relabel new conversation-overlay failures as historical noise.

## Done criteria

- Orbit long-press on sent and received messages shows the new blurred overlay with anchored reactions and the two-action menu.
- `Reply` dismisses the overlay, shows the quote preview, and requests composer focus.
- `Copy` copies exact text and is unavailable for no-text messages.
- Existing Orbit reaction selection, `+` picker handoff, back-dismiss, and background-dismiss semantics still work.
- Direct conversation regressions pass.
- `./scripts/run_test_gates.sh baseline` passes.
- No feed, group, transport, or 1:1 reliability scope is widened beyond the bounded overlay/focus work.

## Scope guard

- Do not plan or implement Session 53 feed/stack adoption work here.
- Do not adopt the new overlay in feed cards or group conversation surfaces in this session.
- Do not redesign swipe-to-reply; it remains incoming-only.
- Do not change reaction persistence, transport, full emoji picker behavior, send durability, retry behavior, or recovery sequencing.
- Do not reopen 1:1 reliability scope for missing product features.
- Do not broaden into general quote-preview localization cleanup unless a new overlay string absolutely requires adjacent changes.

## Accepted differences / intentionally out of scope

- Feed and group surfaces may continue using the old bare `ReactionBar` after Session 52.
- Existing quote preview copy such as `Replying to` / `Message unavailable` may remain unchanged even if new overlay menu strings become localized.
- Full emoji picker behavior remains the current bottom-sheet path.
- Copy remains text-only; no media transcript, filename, or attachment metadata copy is part of this session.

## Dependency impact

- Session 53 depends on the shared overlay host/contract introduced here.
- Session 53 must refresh against landed Session 52 code before execution, especially if the overlay host file name, constructor shape, or test hooks differ from this plan.
- If Session 52 unexpectedly requires changes in quoted-message send/persist plumbing, the downstream dependency should be reclassified and Session 53 should not proceed on the old assumption that this was UI-only overlay/focus work.

## Reviewer pass

- Sufficiency verdict:
  - sufficient with minor caution
- Missing structural items:
  - none
- Required caution:
  - keep `ReactionBar` compatibility explicit so feed/group callers do not become accidental Session 52 work
  - keep `1to1` gate conditional on actual send/persist edits, not on UI-only quote activation
- Overengineering to avoid:
  - do not invent a global overlay framework
  - do not move copy behavior into a broader service layer when UI-side clipboard patterns already exist in the repo

## Arbiter outcome

- Structural blockers:
  - none
- Incremental details intentionally deferred:
  - final overlay-host file name
  - whether existing generic copy strings are acceptable or dedicated ARB entries are cleaner
- Accepted differences:
  - feed/group adoption remains outside Session 52
  - existing quote-preview copy/localization gaps remain outside Session 52
