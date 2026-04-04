# 45 - Feed Stack Card Does Not Reorient After Inline Reply

## 1. Title and Type

- Title: Feed stack card does not reorient after inline reply
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply.md`

## 2. Problem Statement

- Users are trying to continue a back-and-forth with the same person directly from the Feed stack card without leaving the Feed screen.
- Today, when the user sends an inline reply from that card, the card itself can collapse and move to its new position in the feed, but the screen stays anchored around the old scroll position instead of following that same card.
- From the user's perspective, the app breaks conversational continuity right after a successful reply. The user is still interacting with the same person, but the screen no longer stays oriented around that card, so sending another quick reply can require manual scrolling and re-finding the thread.

## 3. Impact Analysis

- Who is affected:
  - users who reply inline from Feed stack cards instead of opening the full conversation
  - users who send more than one reply in the same short exchange from the Feed surface
  - users on longer feeds where the active card is not already pinned near the top of the viewport
- When the issue appears:
  - a 1:1 thread is visible as a Feed stack card
  - the user sends a successful inline reply from that card
  - the card changes its visual state and/or feed position after the reply
  - the user wants to keep interacting with that same contact immediately afterward
- Severity:
  - medium, because the bug interrupts a core message-reply flow on a primary surface even though message send itself succeeds
- Frequency:
  - repo evidence supports this as a repeatable UX problem whenever a successful inline reply causes enough card movement that the previous viewport position no longer matches the card's new location
  - precise production frequency is not established by repo evidence alone
- User-visible cost:
  - the screen feels like it loses the active conversation target right after reply
  - follow-up replies become slower because the user has to manually re-orient to the moved card
  - the Feed surface feels less trustworthy as a place for rapid multi-reply exchanges

## 4. Current State

- Affected code areas:
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/inline_reply_input.dart`
- Existing user-visible flow today:
  - Feed content is rendered through a single `CustomScrollView` with `PageStorageKey('feed-scroll')`, so the surface preserves scroll offset as a general feed position rather than as a per-card viewport anchor. Evidence: `lib/features/feed/presentation/screens/feed_screen.dart` lines 230-244 and `test/features/feed/presentation/screens/feed_screen_test.dart` lines 188-225.
  - Feed threads are partitioned into unread/active cards above the session divider and read/replied cards below it, with each section sorted by timestamp. A successful reply can therefore change both a card's visual mode and its placement within the feed. Evidence: `lib/features/feed/presentation/screens/feed_screen.dart` lines 332-395.
  - `FeedCard` shows open mode only while the thread is in open-mode state and no `sessionReply` is active; otherwise it renders the collapsed body. Evidence: `lib/features/feed/presentation/widgets/feed_card.dart` lines 102-205.
  - The collapsed card body continues to expose `InlineReplyInput` with the localized `conversation_continue` hint, so the current product flow already supports continuing the exchange from the same Feed card after a reply. Evidence: `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart` lines 395-412 and `test/features/feed/presentation/screens/feed_wired_test.dart` lines 1534-1607.
  - On successful inline send, `FeedWired` immediately tracks a `SessionReply`, then marks the conversation read and refreshes that contact's Feed item. Evidence: `lib/features/feed/presentation/screens/feed_wired.dart` lines 1501-1573.
  - Focus management exists for the inline composer: `FeedScreen` forwards `shouldRequestFocus` to the card, and `InlineReplyInput` requests focus when that flag changes. Evidence: `lib/features/feed/presentation/screens/feed_screen.dart` lines 718-740 and `lib/features/feed/presentation/widgets/inline_reply_input.dart` lines 99-132.
  - Existing tests already pin adjacent behavior:
    - general feed scroll offset is preserved across an inline Feed/Orbit round trip. Evidence: `test/features/feed/presentation/screens/feed_wired_test.dart` lines 782-847.
    - successful inline reply clears earlier unread preview truth on Feed. Evidence: `test/features/feed/presentation/screens/feed_wired_test.dart` lines 4010-4088.
  - Repo evidence search did not find an existing Feed test that asserts the viewport re-orients to the same card after that card collapses or repositions following a successful inline reply.
- Important constraints and adjacent coverage already present:
  - `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply.md` already covers Feed unread-stack truth after inline reply, not viewport continuity to the moved card.
  - `Test-Flight-Improv/44-feed-orbit-notification-desync.md` already covers cross-surface notification consistency between Feed and Orbit, not keeping the active Feed card visible after reply.
  - The user-reported behavior explicitly accepts that the card itself may move after reply; the gap is that the screen does not stay oriented around that new card position.

## 5. Scope Clarification

- In scope:
  - 1:1 Feed stack-card behavior immediately after a successful inline reply
  - keeping the same contact's card visibly oriented in the viewport after the card changes size and/or feed position
  - follow-up inline replies from that same Feed card without making the user manually hunt for it again
- Explicit non-goals:
  - changing whether the card itself collapses or repositions after reply if that movement is already product-correct
  - Feed unread-preview truth already covered by report `40`
  - Feed/Orbit synchronization already covered by report `44`
  - full conversation screen behavior outside the Feed card flow
  - choosing a specific scrolling or viewport-management implementation seam
- Accepted ambiguities to keep open for the later implementation pass:
  - the exact final viewport alignment, provided the same card is clearly re-oriented as the active interaction target after reply
  - whether the final experience should preserve the card's relative on-screen position exactly or simply keep it comfortably visible for immediate follow-up replying
  - whether the bug reproduces identically across all screen sizes, keyboard states, and long-feed densities, as long as the acceptance criteria cover the visible continuity problem

## 6. Test Cases

### Happy Path

- `TC-45-H01` Given a user is mid-scroll on Feed and replies inline from a visible 1:1 stack card, when the send succeeds and the card moves to its post-reply position, then the Feed screen re-orients to keep that same card visible instead of staying anchored around the old scroll position.
- `TC-45-H02` Given a user just sent one inline reply from a Feed stack card, when they want to continue replying to that same contact immediately, then the same card remains easy to act on without a manual search scroll.
- `TC-45-H03` Given the successful inline reply changes the card from unread/active presentation into its replied/collapsed presentation, when the transition completes, then the viewport still treats that same card as the active interaction target.

### Edge Cases

- `TC-45-E01` Given the active Feed card is far enough down a long list that it is not near the top of the viewport, when the user sends an inline reply, then the screen still re-orients to the card's new position instead of leaving the user centered on stale surrounding content.
- `TC-45-E02` Given the inline reply dismisses the focused composer as part of send, when the card collapses and repositions, then the post-send viewport still keeps the same contact's card visible for immediate follow-up interaction.
- `TC-45-E03` Given a user sends multiple successful inline replies in sequence from the same Feed card, when each reply completes, then the screen continues to re-orient to that card after each movement rather than drifting away after the first send.
- `TC-45-E04` Given the card's post-reply movement is small on one device size and larger on another because of layout density, when the same reply flow is exercised, then the user still remains visually oriented to the same card across both cases.

### Regressions To Preserve

- `TC-45-R01` Bug regression: After a successful inline reply from a Feed stack card, the user must not be left looking at the old scroll position while the same contact's card has moved elsewhere in the feed.
- `TC-45-R02` Given a successful inline reply from Feed, when the card collapses into its replied state, then the existing post-reply card state transition still works normally.
- `TC-45-R03` Given the Feed-only unread cleanup behavior from report `40`, when this viewport bug is addressed later, then Feed must still avoid resurfacing older replied-to unread rows.
- `TC-45-R04` Given general feed scroll preservation already works for Feed/Orbit host transitions, when this same-card reorientation behavior is added later, then normal Feed scroll storage for unrelated navigation round trips must keep working.
- Existing tests that partially cover this area today:
  - `test/features/feed/presentation/screens/feed_screen_test.dart` covers Feed rendering through a `CustomScrollView`.
  - `test/features/feed/presentation/screens/feed_wired_test.dart` covers general Feed scroll persistence across an inline Feed/Orbit round trip.
  - `test/features/feed/presentation/screens/feed_wired_test.dart` covers successful inline reply state transitions and Feed unread-preview truth after reply.
  - `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply.md` and `Test-Flight-Improv/44-feed-orbit-notification-desync.md` define adjacent but different acceptance boundaries.
- Current test gap:
  - no existing test was found for `visible Feed stack card -> successful inline reply -> card repositions -> viewport follows the same card`
  - no existing test was found for consecutive inline replies from the same Feed card while keeping the card visually oriented after each success
