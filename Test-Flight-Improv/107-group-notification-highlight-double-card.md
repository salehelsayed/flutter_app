# 1. Title and Type

- Title: Group chat messages can look duplicated or double-stacked
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/107-group-notification-highlight-double-card.md`

# 2. Problem Statement

- Users are trying to read a group chat and trust that each visible card represents one logical message.
- Today, some incoming group messages can appear as if two cards are stacked on top of each other.
- The visible symptom has two plausible repo-backed causes that must be distinguished:
  - two persisted group-message rows for one logical incoming message, usually with different `id` values; and
  - a single notification-targeted row receiving an extra full-card highlight border.
- The adjacent investigation makes the data-duplication category credible, but it does not prove that every same-content, same-timestamp, different-id pair is a duplicate; existing reliability coverage intentionally preserves distinct stable message ids in that situation.
- From the user's perspective, both outcomes look like a duplicated or broken message card, especially on dark backgrounds.
- The final group chat experience should either render one coherent message row for one logical incoming delivery or use a polished focus cue that does not resemble a second card.

# 3. Impact Analysis

- Who is affected: group chat users reading incoming messages, especially after redelivery, replay, retry, or notification-anchor routes.
- When it appears: when the same logical message survives as more than one persisted row, or when a notification-open route targets a specific message id and the focus treatment adds a second full-card outline.
- Severity: medium-high for the data-duplication path because recipients can see two rows for what appears to be one send, and reactions can attach to only one of the visible copies.
- Severity: medium for the notification-focus path because the message remains readable but the route highlight can still look like an accidental duplicate card.
- Frequency: repo evidence supports repeatability for the notification-highlight route. The data-duplication trigger is not proven from static analysis alone, but existing tests and persistence rules prove that same-content messages with different stable ids can coexist and render as separate rows.
- Regression risk: high if the later fix uses blanket content-based dedupe for message-id-bearing rows, because PGC-007 deliberately protects legitimate distinct stable-id messages that happen to share content and timestamp.
- User-visible cost: users may think the sender sent the same message twice, the app duplicated a delivery, or a reaction belongs to the wrong copy.

# 4. Current State

- Adjacent investigation:
  - `Test-Flight-Improv/Group-Chat-Feature/double-stacked-message-cards-investigation-2026-06-04.md` argues that the screenshot is more consistent with duplicate persisted rows than with a pure UI artifact.
  - The investigation is useful because it distinguishes the data-duplication category from the notification-highlight double-border path.
  - Critical read: the investigation is strongest when the screenshot truly shows two persisted rows with different reaction state, because reactions are keyed by message id. It is weaker on the exact trigger that produces the second divergent id.
  - Critical read: the recommended broad text-message content dedupe is not directly compatible with the existing PGC-007 contract unless the later pass first proves a stronger logical-delivery identity than same text and same timestamp.
  - The investigation is not definitive on the exact trigger that produces a second divergent id; it explicitly leaves on-device database, flow-log, and wire-message-id evidence as open confirmation work.
- Data and dedup evidence:
  - Incoming group handling treats a non-empty `messageId` as `stableMessageId`. Evidence: `lib/features/groups/application/handle_incoming_group_message_use_case.dart:54-57`.
  - Message-id dedupe is performed before and after event-log handling when `stableMessageId` is present. Evidence: `lib/features/groups/application/handle_incoming_group_message_use_case.dart:86-137` and `lib/features/groups/application/handle_incoming_group_message_use_case.dart:461-512`.
  - The content-based fallback is only used when `stableMessageId == null`. Evidence: `lib/features/groups/application/handle_incoming_group_message_use_case.dart:567-587`.
  - When no stable id exists, a new UUID is minted before saving. Evidence: `lib/features/groups/application/handle_incoming_group_message_use_case.dart:589-609`.
  - The live listener serializes the stream through `asyncMap`, but replayed envelopes also enter `_handleQueuedUserMessage`; when `_userMessageWorkKey` returns `null` for id-less user messages, that per-message queue is bypassed. Evidence: `lib/features/groups/application/group_message_listener.dart:194-205`, `lib/features/groups/application/group_message_listener.dart:249-250`, and `lib/features/groups/application/group_message_listener.dart:354-383`.
  - The Flutter sender resolves a non-empty outgoing message id and reuses it in both the publish envelope and inbox payload. Evidence: `lib/features/groups/application/send_group_message_use_case.dart:230-279` and `lib/features/groups/application/send_group_message_use_case.dart:756-780`.
  - The offline replay builder includes the same message id and timestamp in the replay payload. Evidence: `lib/features/groups/application/send_group_message_use_case.dart:850-860` and `lib/core/bridge/bridge_group_helpers.dart:353-357`.
  - The Go bridge path also mints a message id if missing, stores it in the envelope and payload extra fields, and forwards payload timestamp plus extra fields into the Dart receive event. Evidence: `go-mknoon/node/pubsub.go:422-463`, `go-mknoon/node/pubsub.go:1678-1693`, and `go-mknoon/node/pubsub.go:1728-1746`.
  - Offline inbox replay normally forwards `payload['messageId']` into `handleReplayEnvelope`; one history-gap repair path drops id-less payloads before replay. Evidence: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart:665-685` and `lib/features/groups/application/drain_group_offline_inbox_use_case.dart:1381-1402`.
  - `group_messages` has `id TEXT PRIMARY KEY`; the group and timestamp indexes are non-unique. Evidence: `lib/core/database/migrations/018_group_messages_tables.dart:16-40`.
  - `dbInsertGroupMessage` inserts the row and only handles unique conflicts on `group_messages.id`. Evidence: `lib/core/database/helpers/group_messages_db_helpers.dart:8-58`.
  - `GroupMessageRepositoryImpl.saveMessage` checks and inserts by message id, while `existsByContent` is a separate helper path. Evidence: `lib/features/groups/domain/repositories/group_message_repository_impl.dart:215-247` and `lib/features/groups/domain/repositories/group_message_repository_impl.dart:395-407`.
  - Loading group messages returns all rows for the group ordered by `timestamp ASC, id ASC`; it does not collapse same-content rows. Evidence: `lib/core/database/helpers/group_messages_db_helpers.dart:194-230`.
  - Existing PGC-007 coverage proves that two incoming messages with the same content and timestamp but different stable message ids both persist and appear in the loaded page, including the event-log path. Evidence: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart:1355-1447`.
  - The PGC-INCOMING-1 plan documents that this behavior is intentional: content-based duplicate detection must run only for legacy incoming messages without a stable non-empty wire `messageId`. Evidence: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-INCOMING-1-plan.md`.
- UI rendering evidence:
  - `GroupConversationWired._upsertMessage` replaces only when an existing row has the same `message.id`; otherwise it adds the message. Evidence: `lib/features/groups/presentation/screens/group_conversation_wired.dart:2917-2926`.
  - `orderGroupMessagesForTimeline` builds ordering around a `byId` map and placed ids, so different ids remain different timeline items. Evidence: `lib/features/groups/domain/utils/group_message_ordering.dart:15-56`.
  - Group message rows use `ValueKey('grp-msg-${message.id}')`, so different ids get distinct list rows. Evidence: `lib/features/groups/presentation/screens/group_conversation_screen.dart:610-624`.
  - Reactions are looked up by `message.id`, so duplicate logical rows with different ids can show different reaction state. Evidence: `lib/features/groups/presentation/screens/group_conversation_screen.dart:585`.
  - A normal `LetterCard` already has one rounded bordered surface. Evidence: `lib/features/conversation/presentation/widgets/letter_card.dart:83-96`.
  - Incoming writable rows are wrapped by `SwipeToQuoteBubble`, but its idle reply affordance sits behind the row and does not add a full-card border. Evidence: `lib/features/groups/presentation/screens/group_conversation_screen.dart:626-631` and `lib/features/feed/presentation/widgets/swipe_to_quote_bubble.dart:126-160`.
- Notification-focus evidence:
  - A group notification route passes `routeTarget.messageId` into `GroupConversationWired` as `initialHighlightedMessageId`. Evidence: `lib/main.dart:2769-2785`.
  - `GroupConversationWired` forwards `widget.initialHighlightedMessageId` to `GroupConversationScreen.highlightedMessageId` on every build. Evidence: `lib/features/groups/presentation/screens/group_conversation_wired.dart:4264-4271`.
  - When a row is highlighted, the entire padded row is wrapped in an outer `AnimatedContainer` with its own rounded border and surface color. Evidence: `lib/features/groups/presentation/screens/group_conversation_screen.dart:633-645`.
  - Existing tests assert that a notification-anchor target creates a `grp-highlight-*` wrapper and that only the target is highlighted. Evidence: `test/features/groups/presentation/group_conversation_wired_test.dart:4021-4078`.
  - Existing tests also assert that reaction inspection still works from a notification-anchor highlighted group message. Evidence: `test/features/groups/presentation/group_conversation_wired_test.dart:4081-4164`.

# 5. Scope Clarification

- In scope:
  - Group conversation rows that appear duplicated, stacked, or double-carded.
  - Incoming text rows, especially short messages where duplicate rows are visually easy to confuse with a card rendering defect.
  - Reaction-bearing rows where only one visible copy carries the reaction.
  - Message rows reached from live delivery, replay or recovery paths, normal group chat entry, and notification-anchor entry.
  - The user-visible notification focus treatment for a targeted group message.
  - Preservation of long-press context actions, reaction inspection, quote reply, media tap, swipe-to-reply, and normal message readability.
  - Diagnostic acceptance that distinguishes "two persisted rows" from "one row with an extra focus border."
  - Diagnostic acceptance that distinguishes "same logical delivery under divergent ids" from "two legitimate stable-id sends with identical visible fields."
- Non-goals:
  - No broad redesign of group chat cards, feed cards, conversation cards, or the app background system.
  - No change to group invite notification behavior or accepted-vs-invited recipient rules.
  - No change to ordinary repeated messages that are truly distinct user sends.
  - No blanket collapse of all same-content, same-timestamp, message-id-bearing rows.
  - No requirement to prove the exact divergent-id trigger from static analysis alone.
  - No acceptance of a result that only hides duplicate persisted rows visually while the same duplicate logical messages remain visible again after reload, reaction updates, or notification routing.
- Accepted ambiguities for the later implementation pass:
  - The exact root trigger for divergent ids remains open until database, flow-log, or wire evidence confirms it.
  - The exact logical-identity rule remains open, but acceptance must be stricter than visible text plus timestamp because existing stable-id preservation depends on that distinction.
  - The exact visual language for notification focus remains open as long as it is polished, readable, and does not look like a second card.
  - The exact duration or persistence of any focus cue remains open as long as the final user-visible state avoids a lasting duplicate-card impression.
  - The later pass may decide how to classify one logical delivery versus two intentionally repeated user sends, but acceptance must protect legitimate repeated messages from being collapsed incorrectly.

# 6. Test Cases

## Happy Path

- `TC-107-H01` Given a user receives one logical incoming group text message, when the conversation renders, then the user sees one coherent message row for that logical delivery.
- `TC-107-H02` Given runtime evidence shows the same logical incoming group message was observed through live delivery and replay or recovery, when both paths settle, then the user still sees one coherent row rather than two stacked or adjacent duplicate cards.
- `TC-107-H03` Given a user opens a group chat from a notification targeting a specific text message, when the conversation renders, then the target message is identifiable without looking like two message cards are stacked together.
- `TC-107-H04` Given the targeted or deduplicated incoming message has sender name, avatar, body text, timestamp, and reaction controls, when the row is visible, then all content remains readable and spatially coherent.
- `TC-107-H05` Given a notification-targeted group message has reactions, when the user taps a reaction chip, then the reaction details surface still opens and remains aligned with the single intended message.
- `TC-107-H06` Given a notification-targeted group message supports long press, when the user long-presses it, then reply, copy, and reaction actions remain available as before.

## Edge Cases

- `TC-107-E01` Given two persisted rows have the same visible content, sender, timestamp, and logical delivery context but different ids, when the group conversation loads, then the user does not see two duplicate cards for one logical delivery.
- `TC-107-E02` Given a duplicate-looking row has a reaction attached to only one persisted id, when the conversation renders, then the user sees one coherent message/reaction state instead of a reacted copy and an unreacted copy.
- `TC-107-E03` Given two messages have the same short text but are intentionally sent as separate user actions, when the conversation renders, then both legitimate messages remain visible as separate rows.
- `TC-107-E04` Given the targeted incoming message is wrapped for swipe-to-reply, when the row is idle, then the swipe affordance does not make the row look like a second card.
- `TC-107-E05` Given the targeted message includes a quote preview, when the row renders, then the quote preview and focus state do not visually compete or overlap.
- `TC-107-E06` Given the targeted message includes image, video, or audio media, when the row renders, then the media preview remains inspectable and the row still avoids a duplicate-card appearance.
- `TC-107-E07` Given the group chat uses a dark or image background, when a targeted or recently deduplicated message is visible, then the row remains readable without creating two visible card outlines.
- `TC-107-E08` Given the group chat uses a light readable background, when a targeted or recently deduplicated message is visible, then the row remains visible without becoming heavy or card-like.
- `TC-107-E09` Given no `highlightedMessageId` is provided, when the group chat opens normally, then message rows render with their standard card treatment and no notification-focus artifact appears.
- `TC-107-E10` Given two incoming rows have different stable non-empty message ids and the available evidence only proves same sender, same text, and same timestamp, when the conversation renders, then acceptance must not collapse one row unless stronger same-logical-delivery evidence is present.
- `TC-107-E11` Given a legacy id-less duplicate delivery repeats with identical sanitized content and timestamp, when both copies are handled, then it remains deduped to one visible row.

## Regressions To Preserve

- `TC-107-R01` Bug regression: Given one logical incoming group message reaches local storage under more than one row id, when the group chat renders or reloads, then the user must not see duplicate or stacked message cards for that one logical delivery.
- `TC-107-R02` Bug regression: Given a group notification opens to a targeted incoming message, when the row is rendered, then the row must not present both the normal message card and an additional card-like highlighted container that makes the message look duplicated.
- `TC-107-R03` Given a notification-anchor target exists, when the conversation renders, then only the targeted message receives the focus treatment and older or newer messages do not appear highlighted.
- `TC-107-R04` Given incoming swipe-to-reply is enabled, when a user swipes the incoming row, then quote reply still triggers and the row returns to a coherent resting state.
- `TC-107-R05` Given a user long-presses a targeted or previously duplicate-looking message, when the context overlay opens, then the selected message preview matches the actual row and does not appear as a duplicate message in the list.
- `TC-107-R06` Given group reaction inspection is available from a targeted or previously duplicate-looking message, when the user opens the reaction details surface, then the reaction state and participant labels remain correct.
- `TC-107-R07` Given normal group conversation entry from the group list, Orbit, or Feed does not include a highlighted message id, when the chat opens, then normal rows are visually unchanged.
- `TC-107-R08` Preservation regression: Given the PGC-007 stable-id scenario of same sender, same content, same timestamp, and two distinct non-empty message ids without proof of same logical delivery, when the group chat renders, then both legitimate messages remain visible.

## Existing Coverage And Gaps

- Existing coverage:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` covers same-content, same-timestamp incoming messages with different stable ids persisting as two rows, including the event-log path. This is a preservation constraint against blanket content-only dedupe.
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` covers legacy no-id same-content duplicate suppression.
  - `test/features/groups/presentation/group_conversation_wired_test.dart` covers notification-anchor targeting and asserts `grp-highlight-*` appears only on the target message.
  - `test/features/groups/presentation/group_conversation_wired_test.dart` covers reaction inspection from a notification-anchor highlighted group message.
  - `test/features/groups/presentation/group_conversation_screen_test.dart` covers incoming swipe-to-quote wrapping and read-only behavior.
- Current gaps:
  - No existing test appears to prove that one logical incoming delivery cannot become two visible rows after live/replay/recovery convergence.
  - No existing test appears to prove that a same-content, same-timestamp, different-id pair is the same logical delivery using row ids, raw wire ids, flow events, replay/live source evidence, or reaction target evidence.
  - No existing test appears to connect duplicate persisted group-message rows to the final group conversation UI.
  - No existing test appears to assert that reaction state remains coherent when a duplicate-looking message would otherwise have reactions on only one row id.
  - No existing test appears to assert that the notification-anchor focus state avoids a duplicate-card or stacked-card appearance.
  - No existing visual acceptance evidence appears to cover duplicate-looking group messages across dark and light readable backgrounds.
  - No existing end-to-end-style evidence appears to cover group message redelivery/replay, notification-open journeys, and final polished row appearance together.

## Acceptance Evidence

- TDD evidence is required: the later implementation must first establish a failing or reproducing evidence path for the double-card bug before accepting code changes, then show the same evidence passing after the change.
- Diagnostic evidence is required: acceptance must identify whether each reproduced double-card symptom is caused by two persisted group-message rows, a single highlighted row with an extra visual border, or another documented cause.
- Diagnostic evidence for the duplicate-row path must capture enough fields to distinguish root categories: local row ids, group id, sender id, text, timestamp, created-at, incoming flag, reaction target message id when present, `GROUP_HANDLE_INCOMING_MSG_SUCCESS` count, `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` `dedupeBy` values, and raw live/replay `messageId` values when available.
- Unit evidence is required for the deterministic duplicate classification rules that decide when one logical incoming delivery should remain one visible message and when two same-text sends must remain separate.
- Unit evidence must preserve PGC-007: distinct stable non-empty message ids with the same content and timestamp remain distinct unless additional same-logical-delivery evidence is proven by the later rule.
- Data integration evidence is required to prove duplicate logical deliveries do not remain as two user-visible group-message rows after reload, reaction update, or timeline ordering.
- Data integration evidence must also prove legitimate stable-id same-content messages are not lost, so the acceptance cannot pass by reintroducing blanket content dedupe for message-id-bearing rows.
- Widget evidence is required for the focused group conversation row states: targeted incoming text, targeted outgoing text, targeted quoted message, targeted media message, targeted reaction-bearing message, duplicate-looking incoming text, and non-highlighted normal entry.
- Integration evidence is required for the live/replay or recovery journey: one logical group message observed through more than one delivery path must settle into one coherent user-visible row with coherent reaction state.
- Integration evidence is required for the notification-anchor route: a group notification target with a message id must open the conversation, identify the intended message, preserve context/reaction actions, and avoid a duplicate-card appearance in the rendered UI.
- Smoke evidence is required for adjacent group chat entry points: opening from group list, Orbit, Feed, and notification routes must preserve normal row rendering and message interactions.
- Simulator evidence is required for device-context notification confidence: foreground or background notification-open behavior must route to the intended group message and show a polished focus state without a stacked-card impression.
- Visual evidence is required for both dark and light readable backgrounds so the acceptance cannot pass while the issue remains visible only under one background style.
- The final acceptance evidence must explicitly include the regression and preservation cases `TC-107-R01`, `TC-107-R02`, and `TC-107-R08`; passing tests that only assert a `grp-highlight-*` key exists or only collapse same-content rows are not sufficient.
