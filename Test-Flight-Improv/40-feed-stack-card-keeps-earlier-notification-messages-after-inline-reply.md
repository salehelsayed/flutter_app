# 40 - Feed Stack Card Keeps Earlier Notification Messages After Inline Reply

## 1. Title and Type

- Title: Feed stack card keeps earlier notification messages after inline reply
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply.md`

## 2. Problem Statement

- Users are trying to continue a 1:1 conversation directly from the Feed stack card after receiving a message notification.
- Today, if contact A sends `message-a-1`, user B replies from the Feed stack card with `message-b-1`, and A later sends `message-a-2`, the reopened stack card shows both `message-a-1` and `message-a-2` as pending notification messages.
- From the user's perspective, the Feed card no longer reflects "what is new since my last reply." Older incoming messages that were already answered keep resurfacing, so the notification stack grows and becomes misleading during an active back-and-forth.

## 3. Impact Analysis

- Who is affected: users who receive 1:1 messages on Feed and reply inline from the stack card instead of switching into the full conversation screen.
- When the issue appears: after at least one unread incoming message opens the stack card, the recipient sends an inline reply from that card, and the same contact sends another incoming message later in the same continuing conversation.
- Severity: medium-high. The bug affects a core messaging surface and makes the unread notification context feel inaccurate even though the user already replied.
- Frequency: repeatable for ongoing exchanges that continue from the Feed card; once the stale unread state remains in the card, later incoming messages can make the preview look progressively longer and less trustworthy.
- User-visible cost: users must mentally figure out which message is actually new, and the card can imply that already-answered messages are still waiting for attention.

## 4. Current State

- Affected code areas:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/domain/models/feed_item.dart`
  - `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
  - `lib/features/feed/domain/utils/group_messages_into_threads.dart`
  - `lib/features/conversation/application/mark_conversation_read_use_case.dart`
- Existing user-visible flow today:
  - Feed cards enter open mode whenever a thread is `unread` or `active` and there is no in-memory `sessionReply`. Open mode renders `thread.unreadMessages`, not just the latest unread item. Evidence: `lib/features/feed/domain/models/feed_item.dart` lines 151-182 and `lib/features/feed/presentation/widgets/open_mode_card_body.dart` lines 75-89.
  - Thread state is derived from all messages currently attached to the contact thread. Both cold-load grouping and live incremental updates treat "has unread incoming + has sent messages" as `ConversationState.active`. Evidence: `lib/features/feed/domain/utils/group_messages_into_threads.dart` lines 38-56 and `lib/features/feed/presentation/screens/feed_wired.dart` lines 870-888.
  - On successful inline send from the Feed card, `FeedWired` stores a `SessionReply`, calls `markConversationRead`, and then updates the feed by applying the sent message back into the card flow when a message object is returned. Evidence: `lib/features/feed/presentation/screens/feed_wired.dart` lines 1499-1580 and `lib/features/conversation/application/mark_conversation_read_use_case.dart` lines 4-29.
  - The incremental update path does not rebuild the thread from a fresh contact snapshot. `_applyIncomingContactMessageToFeed` merges the new message into `currentThread?.messages` and recalculates the card state and unread count from that merged in-memory list. Evidence: `lib/features/feed/presentation/screens/feed_wired.dart` lines 942-984.
  - Later incoming message events clear the in-memory `sessionReply` and again use `_applyIncomingContactMessageToFeed`, so the next open-mode card depends on whatever unread flags remain on the in-memory thread at that moment. Evidence: `lib/features/feed/presentation/screens/feed_wired.dart` lines 1270-1273 and 942-984.
- Important constraints and adjacent coverage already present:
  - `SessionReply` intentionally collapses the card immediately after an inline reply so the UI can show a replied state without waiting for a full feed refresh. Evidence: `lib/features/feed/presentation/screens/feed_wired.dart` lines 1499-1505 and `lib/features/feed/domain/models/session_reply.dart`.
  - Existing state derivation tests confirm that a thread is `active` when unread incoming and sent messages coexist, and `replied` once incoming messages are read and a sent message remains. Evidence: `test/features/feed/domain/utils/group_messages_into_threads_test.dart` lines 120-158.
  - Existing projection coverage confirms that a mark-read refresh can match a cold reload. Evidence: `test/features/feed/application/feed_projection_test.dart` lines 434-470.
  - Existing Feed-wired coverage confirms that an incoming message clears `sessionReply` so the card can reopen, and that expanding after an inline reply still works. Evidence: `test/features/feed/presentation/screens/feed_wired_test.dart` lines 1262-1427.
  - No existing test was found for the full user-visible sequence `incoming unread -> inline reply from Feed card -> later incoming from same contact -> reopened card excludes earlier replied-to notification messages`.

## 5. Scope Clarification

- In scope:
  - 1:1 Feed screen stack-card behavior in notification-led message flows.
  - Inline replies sent directly from the Feed card.
  - Which incoming messages remain visible as unread when the same contact sends another message after the user has already replied from the stack card.
  - Card-level unread preview content and length after the reply happens.
- Explicit non-goals:
  - Full conversation screen behavior outside the Feed card.
  - Notification routing, avatar taps, and collapse affordances already covered by `Test-Flight-Improv/32-notification-card-interactions.md`.
  - Group-thread stack cards.
  - Broader messaging features such as read receipts, typing indicators, or transport-layer reliability.
- Accepted ambiguities to keep open for the later implementation pass:
  - Whether the same stale-unread behavior can also be reproduced from manual Feed-card expansion without a notification-led entry.
  - Whether foreground, background, and cold-start entry paths all share one underlying cause or multiple timing variants.
  - Which implementation seam will ultimately own the unread-reset truth for this card flow.

## 6. Test Cases

### Happy Path

- `TC-40-H01` Given user B opens Feed from a notification for `message-a-1`, when the stack card opens for contact A, then the card shows `message-a-1` as the current unread notification context and still allows an inline reply from that card.
- `TC-40-H02` Given user B replies from that Feed card with `message-b-1`, when the send succeeds, then the card moves into its replied/collapsed state and no longer presents `message-a-1` as still pending unread on the stack card.
- `TC-40-H03` Given `message-a-1` was answered inline with `message-b-1`, when contact A later sends `message-a-2`, then the reopened Feed stack card shows only `message-a-2` as the new unread notification context and does not resurface `message-a-1`.

### Edge Cases

- `TC-40-E01` Given a longer exchange on the Feed card (`message-a-1` -> `message-b-1` -> `message-a-2` -> `message-b-2` -> `message-a-3`), when the card reopens after `message-a-3`, then only the incoming messages since the latest local reply are shown as pending unread.
- `TC-40-E02` Given user B replied inline and contact A sends two more messages before user B interacts again, when the card reopens, then it shows only the post-reply incoming messages in chronological order and excludes any pre-reply incoming messages.
- `TC-40-E03` Given the app stays on the Feed screen after the inline reply, when the next incoming message arrives live from the same contact, then the card still excludes earlier incoming messages that were already answered from the Feed card.
- `TC-40-E04` Given the app backgrounds after the inline reply and user B returns on the next notification from the same contact, when the Feed card opens again, then the unread preview still excludes the earlier replied-to incoming message.

### Regressions To Preserve

- `TC-40-R01` Bug regression: Given `message-a-1` arrived, user B sent `message-b-1` from the Feed card, and `message-a-2` arrives later, when the Feed card opens, then `message-a-1` must not appear in the unread notification stack alongside `message-a-2`.
- `TC-40-R02` Given an incoming message arrives while a `sessionReply` is visible, when the new incoming is received, then the card can return to open mode for that contact instead of staying pinned in replied-only state.
- `TC-40-R03` Given a reply has already moved the card into replied/collapsed mode, when the user taps to expand, then the expanded card still shows the recent interaction history for that contact.
- Existing tests that partially cover this area today:
  - `test/features/feed/presentation/screens/feed_wired_test.dart` covers `incoming message clears session reply so card shows open mode` and `tap to expand works after inline reply from collapsed card`.
  - `test/features/feed/application/feed_projection_test.dart` covers `mark-read transition matches cold load`.
  - `test/features/feed/domain/utils/group_messages_into_threads_test.dart` covers active and replied state derivation.
- Current test gap:
  - No existing test was found for the end-to-end user-visible sequence `incoming unread -> inline reply from Feed card -> later incoming from same contact -> unread preview excludes earlier replied-to messages`.
