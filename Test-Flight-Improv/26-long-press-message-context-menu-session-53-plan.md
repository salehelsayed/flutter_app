# Session 53 Plan: Feed/Stack Adoption, Focus Parity, and Cross-Surface Acceptance

## Evidence collector summary

- Session `52` already landed the shared overlay seam in [lib/features/conversation/presentation/widgets/message_context_overlay.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/presentation/widgets/message_context_overlay.dart) and Orbit now uses it from [lib/features/conversation/presentation/screens/conversation_screen.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/presentation/screens/conversation_screen.dart) with anchored geometry, text-only copy gating, reply activation for sent and incoming messages, and one-shot composer focus requests through [lib/features/conversation/presentation/widgets/compose_area.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/presentation/widgets/compose_area.dart).
- Feed still uses the old presenter path at the screen layer: [lib/features/feed/presentation/screens/feed_screen.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/screens/feed_screen.dart) opens bare `ReactionBar` dialogs from `_showReactionBar(...)` / `_showGroupReactionBar(...)` with `barrierColor: Colors.transparent` and no `Reply` / `Copy` menu.
- Landed feed long-press still uses the old ID-only seam, and the current workspace contains a single uncommitted widening in [lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart) to `void Function(ThreadMessage message, BuildContext bubbleContext)? onMessageLongPress`; [lib/features/feed/presentation/widgets/feed_card.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/feed_card.dart), [lib/features/feed/presentation/widgets/open_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/open_mode_card_body.dart), and [lib/features/feed/presentation/widgets/scrollable_message_preview.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/scrollable_message_preview.dart) remain on `void Function(String messageId)? onMessageLongPress`.
- `flutter analyze` confirms the current workspace mismatch is real and blocking: the remaining argument-type errors are at [lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart):314 and [lib/features/feed/presentation/widgets/feed_card.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/feed_card.dart):210.
- Feed still lacks end-to-end anchor/message recovery on the surviving old path: [lib/features/feed/presentation/widgets/message_bubble.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/message_bubble.dart) exposes only `VoidCallback? onLongPress`, and [lib/features/feed/presentation/widgets/scrollable_message_preview.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/scrollable_message_preview.dart) currently bubbles only `msg.id`.
- Feed quote persistence is already closed through the existing send path, but focus parity is still missing: [lib/features/feed/presentation/screens/feed_wired.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/screens/feed_wired.dart) `_onQuoteReply(...)` sets only `_activeQuoteMessageIds`, while reply focus is driven separately by `_activeFocusPeerId`.
- Feed’s inline composer already has a `shouldRequestFocus` seam in [lib/features/feed/presentation/widgets/inline_reply_input.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/inline_reply_input.dart), so Session `53` can reuse current feed focus state before considering any deeper input refactor.
- Current feed tests prove swipe-to-reply durability and callback dispatch, not overlay adoption:
  - [test/features/feed/presentation/screens/feed_wired_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/screens/feed_wired_test.dart) already proves feed swipe-to-reply persists `quotedMessageId`.
  - [test/features/feed/presentation/screens/feed_screen_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/screens/feed_screen_test.dart) proves quote-preview text mapping, not long-press overlay behavior.
  - [test/features/feed/presentation/widgets/feed_card_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/feed_card_test.dart) still proves only the old `String messageId` long-press callback shape.
  - [test/features/feed/presentation/widgets/scrollable_message_preview_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/scrollable_message_preview_test.dart) does not yet prove `ThreadMessage + BuildContext` forwarding.
  - [test/features/feed/presentation/widgets/message_bubble_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/message_bubble_test.dart) does not yet prove the pressed bubble can surface a usable anchor context.
- [Test-Flight-Improv/test-gate-definitions.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/test-gate-definitions.md) records 2026-03-29 green revalidation for `baseline`, `1to1`, and `feed`, so Session `53` does not inherit a standing macOS-only baseline carve-out.

## Real scope

- Adopt the landed shared `MessageContextOverlay` on feed 1:1 thread cards that currently long-press into the bare `ReactionBar`.
- Finish propagating and normalize the partially widened feed long-press callback contract only as much as needed so the host can recover:
  - target message metadata already present in `ThreadMessage`
  - the pressed bubble render context for overlay anchoring
- Support feed long-press `Reply` for both incoming and sent 1:1 thread messages by reusing the existing quote/send path.
- Request focus for the active feed inline composer after long-press `Reply` using the existing feed focus state unless direct regressions prove a narrower input fix is required.
- Support feed long-press `Copy` only for non-empty message text, matching the Orbit gating already landed in Session `52`.
- Cover both open-mode cards and expanded collapsed-mode previews because both route through `ScrollableMessagePreview` and `MessageBubble`.

What does not change:

- swipe-to-reply stays incoming-only
- reaction transport and full-picker behavior stay unchanged
- quoted-message send/persist architecture stays unchanged unless direct evidence proves the feed entry point still diverges
- the current workspace callback mismatch is a preflight issue to reconcile, not additional product scope

## Closure bar

- Long-press on sent and incoming feed 1:1 thread messages shows one blurred overlay with anchored reactions above and `Reply` / `Copy` below, reusing the landed shared overlay contract.
- Long-press `Reply` dismisses the overlay, activates the existing feed quote preview, and moves focus into the correct inline composer.
- Long-press `Copy` copies exact message text, dismisses the overlay, and stays hidden for no-text/media-only messages.
- Reaction tap, `+` picker handoff, background tap, and back-button dismissal preserve current feed semantics.
- Permanent feed-side regressions land for overlay appearance, copy gating, outgoing-message reply parity, and focus activation.
- Required named proof is `feed` plus companion `1to1`, with `baseline` still run for final cross-surface acceptance and no inherited Session `52` failure carve-out.

## Source of truth

- Active session contract:
  - [Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md)
  - [Test-Flight-Improv/26-long-press-message-context-menu.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/26-long-press-message-context-menu.md)
- Regression/gate authority:
  - [Test-Flight-Improv/test-gate-definitions.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/test-gate-definitions.md)
  - [Test-Flight-Improv/14-regression-test-strategy.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/14-regression-test-strategy.md)
- Scope guard against reliability drift:
  - [Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md)
- Reference implementation for overlay semantics and one-shot focus behavior:
  - [lib/features/conversation/presentation/screens/conversation_screen.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/presentation/screens/conversation_screen.dart)
  - [test/features/conversation/presentation/screens/conversation_screen_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/conversation/presentation/screens/conversation_screen_test.dart)
- Current code and current tests beat stale prose when they disagree.
- Workspace-only uncommitted changes do not change the landed Session `53` contract; they must be reconciled before execution.

## Session classification

`prerequisite-blocked`

## Exact problem statement

- Feed 1:1 thread cards still open the old transparent `ReactionBar` dialog, so long-press does not yet expose the new blur-host overlay, `Reply`, or `Copy` on that surface.
- On landed HEAD, feed still bubbles only `messageId`; in the current workspace, [lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart) alone widens to `ThreadMessage + BuildContext`, leaving the stack analyze-broken and still insufficient to anchor `MessageContextOverlay` end-to-end.
- Feed quote activation from long-press is still missing for sent messages because only incoming swipe-to-reply is currently wired, and `_onQuoteReply(...)` does not yet request inline-composer focus.
- The landed product scope is still the one named by the breakdown, but the current workspace cannot be executed safely until that local callback mismatch is reconciled across the full feed widget stack.
- This session must close the user-visible parity gap between Orbit and feed thread cards without reopening 1:1 reliability architecture, group-specific product scope, or reaction transport behavior.

## Files and repos to inspect next

Exact production files:

- [lib/features/feed/presentation/screens/feed_screen.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/screens/feed_screen.dart)
- [lib/features/feed/presentation/screens/feed_wired.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/screens/feed_wired.dart)
- [lib/features/feed/presentation/widgets/feed_card.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/feed_card.dart)
- [lib/features/feed/presentation/widgets/open_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/open_mode_card_body.dart)
- [lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart)
- [lib/features/feed/presentation/widgets/scrollable_message_preview.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/scrollable_message_preview.dart)
- [lib/features/feed/presentation/widgets/message_bubble.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/message_bubble.dart)
- [lib/features/feed/presentation/widgets/inline_reply_input.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/inline_reply_input.dart)
- [lib/features/conversation/presentation/screens/conversation_screen.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/presentation/screens/conversation_screen.dart)
- [lib/features/conversation/presentation/widgets/compose_area.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/presentation/widgets/compose_area.dart)
- [lib/features/conversation/presentation/widgets/message_context_overlay.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/presentation/widgets/message_context_overlay.dart)

Exact direct tests:

- [test/features/feed/presentation/screens/feed_screen_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/screens/feed_screen_test.dart)
- [test/features/feed/presentation/screens/feed_wired_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/screens/feed_wired_test.dart)
- [test/features/feed/presentation/widgets/feed_card_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/feed_card_test.dart)
- [test/features/feed/presentation/widgets/scrollable_message_preview_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/scrollable_message_preview_test.dart)
- [test/features/feed/presentation/widgets/message_bubble_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/message_bubble_test.dart)
- [test/features/feed/presentation/widgets/inline_reply_input_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/inline_reply_input_test.dart)
- [test/features/conversation/presentation/screens/conversation_screen_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/conversation/presentation/screens/conversation_screen_test.dart)

Conditional companion proof:

- [test/features/conversation/integration/quote_reply_thread_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/conversation/integration/quote_reply_thread_test.dart) only if implementation changes observable quoted-message persistence expectations rather than staying on the existing feed entry path
- [test/features/conversation/presentation/widgets/message_context_overlay_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/conversation/presentation/widgets/message_context_overlay_test.dart) if the shared overlay widget itself changes

## Existing tests covering this area

- [test/features/feed/presentation/screens/feed_wired_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/screens/feed_wired_test.dart)
  - proves swipe-to-reply shows quote preview and persists `quotedMessageId` on send
  - proves focused inline draft survives targeted refresh
  - does not prove long-press overlay adoption, sent-message reply parity from long-press, or copy gating
- [test/features/feed/presentation/screens/feed_screen_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/screens/feed_screen_test.dart)
  - proves active quote id maps to visible quote preview text
  - proves read-only announcement/group card rules
  - does not prove feed long-press overlay UI
- [test/features/feed/presentation/widgets/feed_card_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/feed_card_test.dart)
  - proves open-mode long-press dispatch reaches `onMessageLongPress`
  - still encodes the stale `String messageId` contract and does not prove anchored context or overlay content
- [test/features/feed/presentation/widgets/message_bubble_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/message_bubble_test.dart)
  - proves bubble rendering and generic callback dispatch only
  - does not expose bubble context or message metadata to the host
- [test/features/feed/presentation/widgets/scrollable_message_preview_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/scrollable_message_preview_test.dart)
  - proves quote-text resolution and media rendering
  - does not prove the widened long-press callback shape or outgoing long-press reply availability
- [test/features/feed/presentation/widgets/inline_reply_input_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/inline_reply_input_test.dart)
  - covers rendering, send button, attach button, BiDi behavior, and voice affordances
  - does not prove reply-triggered focus requests
- [test/features/conversation/presentation/screens/conversation_screen_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/conversation/presentation/screens/conversation_screen_test.dart)
  - proves the Orbit reference behavior for incoming/outgoing long-press reply, text-only copy gating, and copy feedback
  - guides parity expectations, but does not by itself prove feed wiring

Current coverage gaps:

- no direct feed regression proves `MessageContextOverlay` appears on long-press
- no direct feed regression proves `Copy` is text-only on feed surfaces
- no direct feed regression proves long-press `Reply` works for sent messages
- no direct feed regression proves feed quote activation requests inline-composer focus

## Regression/tests to add first

- Add a `FeedScreen` regression for long-press on a received 1:1 thread message:
  - prove the blurred overlay appears with anchored reactions and `Reply` / `Copy`
- Add a `FeedScreen` regression for long-press on a sent 1:1 thread message:
  - prove long-press `Reply` exists for outgoing feed messages without changing swipe-to-reply rules
- Add a `FeedScreen` or `FeedCard` regression for a no-text/media-only feed message:
  - prove `Copy` is hidden while the overlay still renders and reactions still work
- Add a `FeedWired` vertical-slice regression:
  - long-press `Reply` activates quote preview, requests focus for the correct inline composer, and still persists `quotedMessageId` on send
- Add a `ScrollableMessagePreview` or `MessageBubble` regression only if the callback contract changes:
  - prove the widened long-press callback forwards the selected `ThreadMessage` and a usable bubble context instead of only `messageId`
- Add an `InlineReplyInput` focus regression only if direct feed tests show the current `shouldRequestFocus` seam needs a narrow rising-edge fix

## Step-by-step implementation plan

1. Reconcile the current workspace and choose one coherent feed long-press contract before behavior work.
   Landed HEAD is still ID-only, while the local edit in [lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart) widens to `ThreadMessage + BuildContext`; execution should either return to landed behavior first or carry one explicit typed contract through [lib/features/feed/presentation/widgets/feed_card.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/feed_card.dart), [lib/features/feed/presentation/widgets/open_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/open_mode_card_body.dart), and [lib/features/feed/presentation/widgets/scrollable_message_preview.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/scrollable_message_preview.dart) without keeping both shapes alive.
   Preferred shape: bubble-level long-press passes `BuildContext`, preview-level callback passes the current `ThreadMessage` plus that context, and higher feed widgets thread it upward without inventing a new abstraction layer or leaving mixed callback signatures behind.
2. Keep group/announcement call sites compile-safe while changing the shared feed widgets.
   Group cards may continue routing to the bare group `ReactionBar`; do not add new group reply/copy behavior unless it falls out of the shared widget change with no extra logic or gate burden.
3. Replace the 1:1 feed `_showReactionBar(...)` path in `FeedScreen` with a feed-specific `MessageContextOverlay` presenter.
   Reuse the landed overlay widget, compute `anchorRect` from the pressed bubble context, look up the current reaction, and gate `Copy` on `message.text.trim().isNotEmpty`.
4. Wire long-press `Reply` through the existing feed quote path and feed focus state.
   Update `FeedWired._onQuoteReply(...)` or adjacent reply plumbing so the selected contact thread both stores the active quote id and requests focus for the matching inline composer.
5. Reuse the existing quoted-message send contract.
   Stop if implementation evidence shows the feed long-press path would require new quoted-message persistence logic instead of calling the same path already proven by swipe-to-reply.
6. Add copy behavior without widening platform/service scope.
   Use `Clipboard.setData(...)` and existing localized copy feedback already landed for Session `52` if it reads correctly on feed; only touch shared overlay or strings if the current seam cannot be reused as-is.
7. Land the direct feed regressions first or alongside the code change.
   Update the stale ID-only widget tests as part of this step so the repo no longer codifies the old callback seam as intended behavior.
   Stop if the needed fix turns into a broader shared-input redesign, group-product rollout, or 1:1 reliability refactor.
8. Run direct suites, then named gates in this order:
   - direct feed/widget tests
   - `feed`
   - companion `1to1`
   - `baseline`

## Risks and edge cases

- Anchor geometry risk:
  - feed bubbles live inside scrollable previews and collapsed/open card variants, so the callback must preserve a render context that still maps to the pressed bubble
- Shared-widget blast radius:
  - `FeedCard`, `OpenModeCardBody`, `CollapsedModeCardBody`, and `ScrollableMessagePreview` are shared by 1:1 and group cards
- Partial-migration risk:
  - the repo is already analyzer-red in the targeted files, so implementation must finish the chosen callback shape instead of adding compatibility layers that keep both signatures alive
- Focus behavior risk:
  - using existing `activeFocusPeerId` may be sufficient, but a sticky `shouldRequestFocus` contract could steal focus again on later rebuilds if not handled carefully
- Copy gating risk:
  - no-text/media-only rows must still allow reactions and reply while keeping `Copy` unavailable
- Semantics-preservation risk:
  - reaction tap, `+` picker handoff, background tap, and back dismissal must still dismiss exactly once
- Swipe parity risk:
  - swipe-to-reply must remain incoming-only even after long-press `Reply` is enabled for sent rows
- Reliability scope risk:
  - any evidence that long-press reply bypasses the existing feed send path would force companion `1to1` proof and possibly reclassification if the send contract must change

## Exact tests and gates to run

Direct tests:

- `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- `flutter test test/features/feed/presentation/widgets/feed_card_test.dart`
- `flutter test test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
- `flutter test test/features/feed/presentation/widgets/message_bubble_test.dart`
- `flutter test test/features/feed/presentation/widgets/inline_reply_input_test.dart`
- `flutter test test/features/conversation/presentation/widgets/message_context_overlay_test.dart` only if the shared overlay widget changes
- `flutter test test/features/conversation/integration/quote_reply_thread_test.dart` only if quoted-message persistence behavior changes rather than remaining on the existing feed path

Named gates:

- `./scripts/run_test_gates.sh feed`
- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh baseline`

Not required for Session `53` as currently scoped:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh transport`
- any new named gate or matrix doc

## Known-failure interpretation

- [Test-Flight-Improv/test-gate-definitions.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/test-gate-definitions.md) records 2026-03-29 green revalidation for `baseline`, `1to1`, and `feed`; there is no standing Session `52` baseline exception to inherit here.
- The current analyzer mismatch at [lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart):314 and [lib/features/feed/presentation/widgets/feed_card.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/feed_card.dart):210 is the active workspace blocker for Session `53` preflight and must be resolved before running feature validation.
- Any failure in the new feed direct regressions is a real Session `53` regression.
- Any `feed`, `1to1`, or `baseline` gate failure is a real Session `53` regression unless it is already documented in [Test-Flight-Improv/test-gate-definitions.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/test-gate-definitions.md) and reproducible on unmodified HEAD.

## Done criteria

- The feed long-press callback contract is coherent across `FeedCard`, `OpenModeCardBody` / `CollapsedModeCardBody`, and `ScrollableMessagePreview`; no temporary type mismatch remains.
- Feed 1:1 thread cards long-press into the shared blurred overlay instead of the bare `ReactionBar`.
- The overlay exposes `Reply` and text-only `Copy` for sent and incoming feed messages.
- Long-press `Reply` activates the existing quote preview and moves focus into the matching inline composer.
- Sending from that reply path still persists the correct `quotedMessageId`.
- Direct feed regressions pass.
- `./scripts/run_test_gates.sh feed` passes.
- `./scripts/run_test_gates.sh 1to1` passes.
- `./scripts/run_test_gates.sh baseline` passes.
- No new group-product behavior, swipe-rule changes, reaction-pipeline changes, or 1:1 reliability architecture changes are introduced.

## Scope guard

- Do not redesign `MessageContextOverlay` into a new global overlay framework.
- Do not widen Session `53` into group/announcement-specific reply/copy product work.
- Do not pull `ExpandedComposeInput` into scope unless current execution evidence shows the feed reply surface actually routes through it; current repo state still uses `InlineReplyInput` on the targeted feed cards.
- Do not change swipe-to-reply rules; it remains incoming-only.
- Do not change reaction persistence, transport behavior, full emoji picker behavior, or feed-to-conversation navigation.
- Do not reopen 1:1 reliability design, retry sequencing, send durability, or quoted-message persistence unless direct evidence shows the feed entry path is still bypassing the closed contract.
- Do not paper over the current callback mismatch with `dynamic`, `Object?`, or an unnecessary adapter DTO; keep one explicit typed feed long-press contract.
- Do not invent a new named gate or update `test-gate-definitions.md` unless execution adds a new maintained integration or cross-feature suite.

## Accepted differences / intentionally out of scope

- Group and announcement cards may remain on the old bare reaction-bar interaction in this session even if the shared callback seam has to change for compile safety.
- If group cards inherit harmless callback-shape changes through shared widgets, document that as an implementation consequence rather than widening this plan into group-specific regressions.
- `ExpandedComposeInput` and its direct tests stay out unless execution evidence shows the feed reply surface actually routes through that widget.
- Existing quote-preview strings and broader localization cleanup remain out of scope unless current shared copy-feedback strings are unusable on feed.
- Orbit's one-shot focus reset is a reference seam, not a requirement to copy conversation-screen internals if feed can reach the same user-visible parity more narrowly.

## Dependency impact

- Session `53` depends on the shared overlay and Orbit focus seam already landed in Session `52`.
- Report `26` cannot honestly close until Session `53` lands because feed thread cards are the remaining user-visible parity gap named by the breakdown closure bar.
- If Session `53` reveals that feed long-press reply still bypasses the shared quoted-message send contract, later closure must revisit the Session `53` classification and possibly reopen reliability proof, not silently patch around it.
- If Session `53` stays UI-only as planned, downstream work should skip any new reliability or group sessions for this report.

## Reviewer pass

- Sufficiency verdict:
  - sufficient with adjustments already incorporated
- Missing structural items after refresh:
  - reconcile the current workspace-only callback mismatch before implementation starts
- Stale assumptions corrected in this plan:
  - feed has not yet adopted `MessageContextOverlay`
  - landed HEAD is still on the old `String messageId` seam, while the current workspace contains a single uncommitted widening in `collapsed_mode_card_body.dart` that makes the feed stack analyze-red
  - Session `52` already landed the shared overlay and Orbit focus seam
  - the gate docs no longer carry a standing Session `52` baseline failure carve-out for `baseline`, `1to1`, or `feed`
- Overengineering to avoid:
  - a new cross-feature overlay abstraction
  - a custom long-press DTO if `ThreadMessage + BuildContext` is enough
  - a broad `InlineReplyInput` rewrite before direct tests prove it is needed

## Arbiter outcome

- Structural blockers:
  - the current workspace contains a callback-signature mismatch between [lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart), [lib/features/feed/presentation/widgets/feed_card.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/feed_card.dart), and [lib/features/feed/presentation/widgets/scrollable_message_preview.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/scrollable_message_preview.dart) that keeps targeted `flutter analyze` red; execution is unsafe until that stack is restored to one coherent contract
- Incremental details intentionally deferred:
  - final long-press callback type name and exact function signature
  - whether `InlineReplyInput` needs a rising-edge-only focus fix or can reuse existing feed focus state untouched
  - whether the shared overlay widget needs any feed-specific adjustment at all
- Accepted differences:
  - group/announcement behavior remains outside the core Session `53` closure bar unless it falls out of shared feed widget reuse with no extra scope
  - Orbit remains the parity reference for behavior, not a mandate to copy unrelated conversation-screen implementation details
