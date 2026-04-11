# MessageContextOverlay Feature -- Test Inventory

**Date:** 2026-04-10 (reconciled)
**Scope:** All overlay-focused widget and screen tests, plus adjacent reaction/reply/delete/edit application and integration tests used to close row-owned MessageContextOverlay matrix gaps.

---

## How to Run

**All overlay widget tests (dedicated widget):**

```sh
flutter test --no-pub test/features/conversation/presentation/widgets/message_context_overlay_test.dart
```

**Reaction bar widget tests:**

```sh
flutter test --no-pub test/features/conversation/presentation/widgets/reaction_bar_test.dart
```

**Reaction display widget tests:**

```sh
flutter test --no-pub test/features/conversation/presentation/widgets/reaction_display_test.dart
```

**Full emoji picker widget tests:**

```sh
flutter test --no-pub test/features/conversation/presentation/widgets/full_emoji_picker_test.dart
```

**Message bubble widget tests (overlay-adjacent):**

```sh
flutter test --no-pub test/features/feed/presentation/widgets/message_bubble_test.dart
```

**Letter card widget tests (overlay-adjacent):**

```sh
flutter test --no-pub test/features/conversation/presentation/widgets/letter_card_test.dart
```

**Feed card widget tests (overlay-adjacent):**

```sh
flutter test --no-pub test/features/feed/presentation/widgets/feed_card_test.dart
```

**Scrollable message preview widget tests (overlay-adjacent):**

```sh
flutter test --no-pub test/features/feed/presentation/widgets/scrollable_message_preview_test.dart
```

**Quote preview bar widget tests:**

```sh
flutter test --no-pub test/features/feed/presentation/widgets/quote_preview_bar_test.dart
```

**Conversation screen overlay integration:**

```sh
flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart
```

**Conversation wired overlay integration:**

```sh
flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart
```

**Feed screen overlay integration:**

```sh
flutter test --no-pub test/features/feed/presentation/screens/feed_screen_test.dart
```

**Feed wired overlay integration:**

```sh
flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart
```

**Group conversation screen overlay integration:**

```sh
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart
```

**Group conversation wired overlay integration:**

```sh
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart
```

**Notification-open first-frame integration harness:**

```sh
flutter test --no-pub integration_test/notification_open_ui_smoke_test.dart -d macos
```

---

## Summary

| Category | Files | Test Cases |
|----------|------:|-----------:|
| Widget (MessageContextOverlay) | 1 | 14 |
| Widget (ReactionBar) | 1 | 6 |
| Widget (ReactionDisplay) | 1 | 5 |
| Widget (FullEmojiPicker) | 1 | 3 |
| Widget (MessageBubble — overlay-adjacent) | 1 | 14 of 35 |
| Widget (LetterCard — overlay-adjacent) | 1 | 13 of 46 |
| Widget (FeedCard — overlay-adjacent) | 1 | 6 of 23 |
| Widget (ScrollableMessagePreview — overlay-adjacent) | 1 | 6 of 18 |
| Widget (QuotePreviewBar) | 1 | 8 |
| Conversation Screen (overlay integration) | 1 | 32 |
| Conversation Wired (overlay + edit/delete flows) | 1 | 28 |
| Feed Screen (overlay integration) | 1 | 12 |
| Feed Wired (overlay + edit/delete flows) | 1 | 15 |
| Group Conversation Screen (overlay integration) | 1 | 6 |
| Group Conversation Wired (overlay + reaction/quote) | 1 | 7 of 62 |
| Notification Open Integration | 1 | 8 |
| **Primary Total** | **16** | **183** |
| Adjacent application & integration tests (1:1) | 22 | see §9 |
| Adjacent application & integration tests (group) | 16 | see §10 |

---

## 1. Widget Layer

### 1.1 MessageContextOverlay
**File:** `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`

| # | Test | What it covers |
|---|------|----------------|
| 1 | renders reaction bar plus reply and copy actions when copy is enabled | Overlay shows reaction bar, reply button, copy button, and emoji row |
| 2 | renders the selected message between the reaction bar and menu | Selected message widget positioned between reaction bar and menu; layout order verified |
| 3 | clamps the selected message stack near the top edge | Layout clamping respects safe-area insets when anchor is near top |
| 4 | clamps the selected message stack near the bottom edge | Layout clamping keeps menu visible when anchor is near bottom |
| 5 | renders edit action when enabled | Edit button appears when `showEditAction: true` |
| 6 | renders delete action as the danger action when enabled | Delete button appears when `showDeleteAction: true` |
| 7 | renders reply, edit, copy, then delete in stable keyed order when all actions are enabled | Action ordering stays deterministic when all four actions are visible |
| 8 | hides copy action when message text is unavailable | Copy button hidden when `showCopyAction: false` (media-only) |
| 9 | fires onEditTap when the edit action is pressed | `onEditTap` callback invoked on edit tap |
| 10 | fires onDeleteTap when the delete action is pressed | `onDeleteTap` callback invoked on delete tap |
| 11 | double tapping copy only invokes the callback once | Rapid duplicate copy taps are collapsed to one callback |
| 12 | double tapping a preset reaction only emits once | Rapid duplicate reaction taps are collapsed to one callback |
| 13 | dismisses when the blurred backdrop is tapped | `onDismiss` callback invoked on backdrop tap |
| 14 | localizes the overlay in Arabic RTL without layout exceptions | RTL locale renders without layout overflow or exceptions |

### 1.2 ReactionBar
**File:** `test/features/conversation/presentation/widgets/reaction_bar_test.dart`

| # | Test | What it covers |
|---|------|----------------|
| 1 | renders 6 preset emojis + "+" button | Quick-bar shows the preset emoji row and the expand button |
| 2 | fires onReactionSelected with correct emoji | Tap on a preset chip emits the correct emoji string |
| 3 | fires onPlusTap on "+" tap | Expand button invokes `onPlusTap` |
| 4 | non-preset currentEmoji does not falsely highlight any preset chip | Reopening the bar with a non-preset current emoji keeps all preset chips unhighlighted |
| 5 | fires onDismiss on barrier tap | Barrier tap invokes `onDismiss` |
| 6 | scale animation runs (0.8→1.0, 200ms) | Entry animation timing and scale range verified |

### 1.3 ReactionDisplay
**File:** `test/features/conversation/presentation/widgets/reaction_display_test.dart`

| # | Test | What it covers |
|---|------|----------------|
| 1 | renders nothing when reactions empty | No chip widgets rendered for empty list |
| 2 | renders emoji chips grouped by emoji with counts | Same-emoji reactions collapse into one chip with the grouped count |
| 3 | highlights chip when ownPeerId matches sender | Own-reaction chip shows highlight styling |
| 4 | fires onReactionTap with emoji string on tap | Chip tap emits the correct emoji string |
| 5 | renders non-preset emoji chips inline without fallback | Non-preset emoji renders inline without fallback text or loss |

### 1.4 FullEmojiPicker
**File:** `test/features/conversation/presentation/widgets/full_emoji_picker_test.dart`

| # | Test | What it covers |
|---|------|----------------|
| 1 | renders grid of emojis | Emoji grid renders with expected items |
| 2 | fires onSelected on tap | Tap returns the selected emoji |
| 3 | category tabs render and switch | Category tab switching works correctly |

### 1.5 MessageBubble (overlay-adjacent)
**File:** `test/features/feed/presentation/widgets/message_bubble_test.dart`
*14 overlay-relevant tests out of 35 total in the file; covers the feed bubble widget used as the overlay's selected-message rendering surface.*

| # | Test | What it covers |
|---|------|----------------|
| 1 | renders edited indicator for edited outgoing rows | `(edited)` label visible on edited outgoing messages |
| 2 | renders deleted placeholder instead of linkable body text | Deleted messages show placeholder, not original text |
| 3 | renders quote bar when quotedText is provided | Quote bar renders with quoted text |
| 4 | renders unavailable quote bar | Quote bar shows unavailable state for missing source |
| 5 | Arabic quote text drives RTL on quote bar | RTL directionality for Arabic quoted text |
| 6 | English quote text drives LTR on quote bar | LTR directionality for English quoted text |
| 7 | renders inline reaction chips when reactions provided | Inline reaction chips render below message text |
| 8 | no ReactionDisplay when reactions empty | No chip widgets when reactions list is empty |
| 9 | long-press fires onLongPress callback | Long-press gesture invokes the callback that opens the overlay |
| 10 | no ReactionDisplay widget when reactions provided | Standalone ReactionDisplay absent in inline layout |
| 11 | onReactionTap fires with emoji when chip tapped | Inline chip tap emits emoji to shared reaction state machine |
| 12 | no reactions still keeps timestamp in footer | Timestamp stays in footer row when reactions are absent |
| 13 | multiple reaction emojis render inline with counts | Multiple grouped emoji chips render with correct counts |
| 14 | own reaction chip has teal border inline | Own-reaction chip shows teal highlight border |

### 1.6 LetterCard (overlay-adjacent)
**File:** `test/features/conversation/presentation/widgets/letter_card_test.dart`
*13 overlay-relevant tests out of 46 total in the file; covers the conversation letter card used as the overlay's selected-message rendering surface.*

| # | Test | What it covers |
|---|------|----------------|
| 1 | shows edited indicator when the row is edited | `(edited)` label visible on edited conversation rows |
| 2 | shows deleted placeholder styling when the row is deleted | Deleted rows render placeholder styling |
| 3 | Arabic quote text drives RTL on quote bar | RTL directionality for Arabic quoted text |
| 4 | English quote text drives LTR on quote bar | LTR directionality for English quoted text |
| 5 | Arabic-first mixed quoted text drives RTL on quote bar | Mixed-script quoted text follows first-language directionality |
| 6 | fires onLongPress on long-press | Long-press gesture invokes the callback that opens the overlay |
| 7 | fires onReactionTap when chip tapped | Inline chip tap emits emoji to shared reaction state machine |
| 8 | reactions and timestamp share the same Row | Reaction chips and timestamp coexist in the footer row |
| 9 | no reactions still right-aligns timestamp in footer Row | Timestamp alignment preserved when reactions are absent |
| 10 | no standalone ReactionDisplay when reactions provided | Standalone display absent in inline layout |
| 11 | multiple reaction emojis render inline with counts | Multiple grouped emoji chips render with correct counts |
| 12 | own reaction chip has teal border inline | Own-reaction chip shows teal highlight border |
| 13 | shows retry and delete controls when callbacks are wired | Failed-message retry/delete inline controls render |

### 1.7 FeedCard (overlay-adjacent)
**File:** `test/features/feed/presentation/widgets/feed_card_test.dart`
*6 overlay-relevant tests out of 23 total in the file; covers the feed card that hosts open-mode and expanded-collapsed long-press, reaction display, and quote preview integration.*

| # | Test | What it covers |
|---|------|----------------|
| 1 | active quote preview is rendered in collapsed mode | Quote preview bar renders inside collapsed feed card |
| 2 | open-mode card renders ReactionDisplay when reactions exist | Reaction chips render in open-mode card body |
| 3 | long-press on message in open-mode fires onMessageLongPress | Long-press gesture invokes the callback that opens the overlay |
| 4 | long-press on message in expanded collapsed card provides message and bubble context | Long-press in expanded collapsed card forwards message + bubble context |
| 5 | onReactionTap fires with message ID and emoji | Inline chip tap emits emoji to shared reaction state machine |
| 6 | expanded collapsed card renders ReactionDisplay when reactions exist | Reaction chips render in expanded collapsed card body |

### 1.8 ScrollableMessagePreview (overlay-adjacent)
**File:** `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
*6 overlay-relevant tests out of 18 total in the file; covers the scrollable message preview used inside expanded collapsed feed cards for quote resolution and long-press forwarding.*

| # | Test | What it covers |
|---|------|----------------|
| 1 | resolves quoted text from sibling messages | Quote bar renders with resolved sibling message text |
| 2 | resolves quoted text from quoteLookupMessages when parent is outside preview slice | Quote bar resolves from external lookup when parent is not in visible slice |
| 3 | shows unavailable when the quoted parent was deleted | Deleted quoted parent degrades to unavailable state |
| 4 | long-press forwards the selected message and bubble context | Long-press on message forwards to host overlay callback |
| 5 | shows unavailable for unknown quoted message | Unknown quoted message ID degrades to unavailable state |
| 6 | long-press forwards message and bubble context | Long-press on group message forwards to host overlay callback |

### 1.9 QuotePreviewBar
**File:** `test/features/feed/presentation/widgets/quote_preview_bar_test.dart`
*8 tests covering the quote preview bar widget used above the composer during reply mode.*

| # | Test | What it covers |
|---|------|----------------|
| 1 | renders "Replying to" label | "Replying to" label text present |
| 2 | renders quoted text | Quoted message text rendered in bar |
| 3 | Arabic quoted text drives RTL | RTL directionality for Arabic quoted text |
| 4 | Arabic-first mixed quoted text drives RTL | RTL directionality for Arabic-first mixed text |
| 5 | English quoted text drives LTR | LTR directionality for English quoted text |
| 6 | text has maxLines 2 with ellipsis overflow | Quoted text truncation at 2 lines |
| 7 | shows dismiss icon when onDismiss is provided | "x" dismiss button visible when callback wired |
| 8 | hides dismiss icon when onDismiss is null | "x" dismiss button hidden when no callback |

---

## 2. Conversation Screen (Overlay Integration)

### 2.1 ConversationScreen -- overlay tests
**File:** `test/features/conversation/presentation/screens/conversation_screen_test.dart`
*32 overlay-relevant tests out of 54 total `testWidgets` in the file.*

| # | Test | What it covers |
|---|------|----------------|
| | **Long-press / Overlay open & dismiss** | |
| 1 | long-press on incoming text shows the overlay and backdrop dismisses without side effects | Overlay opens on long-press; reaction bar, reply, copy, selected message all present; backdrop dismiss fires without mutations |
| 2 | long-press reply is available for outgoing messages | Long-press on outgoing message shows overlay with selected message; reply tap invokes `onQuoteReply` with correct id; overlay dismissed |
| 3 | rapid repeat long-press keeps a single overlay active | Second long-press while overlay is open does not stack a second instance |
| | **Edit action visibility** | |
| 4 | edit action appears for the last sent text row even when a newer incoming row exists | Edit action visible only for most-recent outgoing message |
| 5 | edit action skips deleted outgoing rows and still targets the latest live outgoing message | Deleted outgoing rows are ignored by latest-sent scanning |
| 6 | edit action stays hidden for older sent rows | Edit action not present when long-pressing an older outgoing message |
| 7 | edit action stays hidden when edit mode is disabled or the callback is not wired | Edit suppressed when `isEditEnabled=false` or no edit callback |
| 8 | edit action stays hidden when own identity is missing, the row is incoming, or the row is owned by another peer | Edit suppressed for non-owner / identity-missing / incoming rows |
| 9 | shows edit banner and routes cancel action | Edit banner appears and cancel callback clears it |
| | **Busy-state edit suppression** | |
| 10 | pending attachments keep reply copy and delete available while edit stays hidden | Edit hidden during pending-attachment state |
| 11 | uploading attachments keep reply copy and delete available while edit stays hidden | Edit hidden during upload state |
| 12 | sending keeps reply copy and delete available while edit stays hidden | Edit hidden during send state |
| 13 | processing keeps reply copy and delete available while edit stays hidden | Edit hidden during processing state |
| 14 | recording keeps reply copy and delete available while edit stays hidden | Edit hidden during recording state |
| | **Copy action** | |
| 15 | copy action copies exact multiline text, replaces the prior snackbar, and dismisses the overlay | Clipboard receives exact text; overlay dismissed; snackbar replacement verified |
| 16 | copy action localizes the snackbar in Arabic while preserving mixed-script clipboard text | Arabic snackbar localization; mixed-script clipboard fidelity |
| 17 | copy action stays safe when the conversation screen is disposed during the clipboard await | No crash when context disposed during async clipboard write |
| | **Content filtering** | |
| 18 | media-only long-press hides copy action | Copy and edit actions hidden for media-only messages; reply still available |
| 19 | whitespace-only long-press hides edit and copy but keeps reply and delete available | Whitespace-only rows suppress edit and copy |
| | **Delete action** | |
| 20 | delete action is available on normal visible rows | Delete action present on non-deleted messages |
| 21 | delete taps dismiss the overlay before opening one next-frame sheet even under a rapid double tap | Overlay dismissed before bottom sheet; no stacked sheets on double-tap |
| 22 | delete action stays hidden when the callback is not wired | Delete suppressed when no delete callback is provided |
| 23 | deleted rows render placeholder and stay inert | Long-press on deleted placeholder does not open the overlay |
| 24 | quoted deleted parents render as unavailable | Replies whose quoted parent was later deleted degrade to unavailable |
| | **Quote / Reply** | |
| 25 | wraps incoming messages with swipe-to-quote when enabled | Incoming non-deleted rows expose the swipe-to-reply affordance |
| 26 | does not wrap outgoing messages with swipe to quote | Swipe-to-reply stays hidden for outgoing rows |
| 27 | does not wrap deleted messages with swipe to quote | Deleted placeholders excluded from swipe-to-reply |
| 28 | renders quoted replies and unavailable fallback in list | Reply rows render quoted text or unavailable fallback |
| 29 | renders media preview text for quoted media replies | Reply rows resolve quoted media-only parents to `mediaPreviewText(...)` |
| 30 | quoted replies live-resolve updated parent text after the source is edited | Latest edited parent text reflected in reply row without destabilizing |
| | **System rows** | |
| 31 | renders intro system rows through IntroSystemMessage in order | System transport rows render through `IntroSystemMessage`; long-press stays inert |
| | **Restart** | |
| 32 | after restart, conversation screen rebuilds stored reply edit delete and reaction state without stale pre-restart UI | Dispose/rebuild pass swaps in final stored truth without stale cache |

---

## 3. Conversation Wired (Overlay + Edit/Delete Flows)

### 3.1 ConversationWired -- overlay end-to-end tests
**File:** `test/features/conversation/presentation/screens/conversation_wired_test.dart`
*28 overlay-relevant tests out of 60 total `testWidgets` in the file.*

| # | Test | What it covers |
|---|------|----------------|
| | **Quote / Reply** | |
| 1 | long-press reply on an outgoing message requests focus and sends quotedMessageId | Overlay reply shows quote preview, focuses composer; send persists `quotedMessageId` |
| 2 | swipe-to-reply sends quotedMessageId and clears preview | Swipe entry produces the same quote state and persistence contract as overlay Reply |
| 3 | clearing quote removes the preview and the next send has no quotedMessageId | Clearing quote preview removes `quotedMessageId` from next send |
| 4 | swipe-to-reply voice send preserves quotedMessageId | Voice send after swipe-to-reply keeps `quotedMessageId` |
| | **Edit** | |
| 5 | edit action prefills the composer and cancel exits edit mode | Edit prefills composer, focuses input, shows edit banner; cancel clears both |
| 6 | edit action clears active quote mode before entering edit mode | Edit entry dismisses any active quote preview first |
| 7 | identical-text edit submit is a no-op | Submitting unchanged text does not call `editFn`, leaves message untouched |
| 8 | starting a reply clears active edit mode | Reply entry dismisses active edit mode |
| 9 | changed edit submit updates the same row through the shared edit path | Changed text calls `editFn` with correct id + text; `editedAt` set; `quotedMessageId` preserved |
| 10 | pending attachments suppress edit while reply, copy, and delete remain available | Edit hidden when pending attachments present |
| | **Copy** | |
| 11 | copy action leaves repo, bridge, and p2p collaborators untouched | Clipboard copy runs without additional repo writes, bridge sends, or P2P activity |
| 12 | copy remains local-only when delete wins during the async clipboard path | Copy/delete race keeps copy local-only; delete tombstone wins visible row state |
| | **Delete** | |
| 13 | delivered outgoing rows offer delete-for-me and delete-for-everyone | Overlay delete tap opens sheet with both options |
| 14 | incoming rows only offer delete-for-me and cancel | Incoming messages: no delete-for-everyone |
| 15 | identity-missing rows only offer delete-for-me and cancel | Missing identity suppresses delete-for-everyone |
| 16 | sender-mismatch rows only offer delete-for-me and cancel | Sender mismatch suppresses delete-for-everyone |
| 17 | failed outgoing rows only offer delete-for-me and cancel | Failed outgoing: no delete-for-everyone |
| 18 | delete-for-me removes the row from Orbit locally | Delete-for-me removes message from repo and list |
| 19 | canceling the delete sheet leaves the message unchanged | Cancel is a no-op |
| 20 | deleting the message currently being edited exits edit mode immediately | Delete during edit clears edit state |
| 21 | deleting the message currently being quoted exits quote mode immediately | Delete during quote clears quote state |
| 22 | hidden outgoing tombstones are removed from the Orbit list | Hidden tombstones pruned from visible list |
| 23 | failed outgoing delete tombstones stay visible in the Orbit list | Failed tombstones remain retryable |
| | **Incoming mutations** | |
| 24 | incoming reactions refresh the open Orbit conversation and stay correct after reopen | Reaction mutations refresh without manual reload |
| 25 | incoming edited messages refresh the open Orbit conversation and stay correct after reopen | Edit mutations refresh without manual reload |
| 26 | incoming deleted tombstones refresh into the Orbit placeholder and stay correct after reopen | Delete mutations refresh without manual reload |
| | **Failure recovery** | |
| 27 | upload failure restores quote draft and attachments | Upload failure restores composer state |
| 28 | send failure after upload restores quote draft and attachments | Post-upload send failure restores composer state |

---

## 4. Feed Screen (Overlay Integration)

### 4.1 FeedScreen -- overlay tests
**File:** `test/features/feed/presentation/screens/feed_screen_test.dart`
*12 overlay-relevant tests out of 23 total `testWidgets` in the file.*

| # | Test | What it covers |
|---|------|----------------|
| 1 | incoming long-press opens shared overlay and routes reply through feed callback | Long-press opens overlay with reaction bar, selected message, reply, copy; reply tap invokes `onQuoteReply` with correct peerId + messageId; overlay dismissed |
| 2 | sent long-press in expanded collapsed card exposes reply action | Long-press on sent message in expanded card shows overlay with reply; reply tap returns correct messageId |
| 3 | feed edit action appears only on the last sent row even when a newer incoming row exists | Edit action visible on last sent message; hidden on older sent rows |
| 4 | feed hides edit for media-only outgoing rows | Edit action hidden when last sent message has only media |
| 5 | feed delete action routes through the shared overlay callback | Delete tap invokes `onDeleteMessage` with correct peerId + messageId; overlay dismissed |
| 6 | deleted feed rows stay inert and never reopen the overlay | Deleted direct-thread rows render placeholder; long-press does not reopen overlay |
| 7 | collapsed feed preview renders edited indicator | Collapsed card shows `(edited)` label for messages with `editedAt` |
| 8 | after restart, feed direct-thread screen rebuilds stored reply edit delete and reaction state without stale pre-restart UI | Dispose/rebuild pass swaps in final stored truth without stale cache |
| 9 | copy action copies exact text and dismisses the overlay | Copy tap writes exact text to clipboard; overlay dismissed; snackbar shown |
| 10 | copy action stays safe after the feed host context changes during the clipboard await | No crash when context changes during async clipboard write |
| 11 | media-only long-press hides copy action | Copy action hidden for media-only messages; reply still available |
| 12 | whitespace-only long-press hides edit and copy but keeps reply and delete available in feed | Whitespace-only rows suppress edit and copy |

---

## 5. Feed Wired (Overlay + Edit/Delete Flows)

### 5.1 FeedWired -- overlay end-to-end tests
**File:** `test/features/feed/presentation/screens/feed_wired_test.dart`
*15 overlay-relevant tests out of 84 total `testWidgets` in the file.*

| # | Test | What it covers |
|---|------|----------------|
| | **Quote / Reply** | |
| 1 | long-press reply shows preview, focuses composer, and persists quotedMessageId on send | Overlay reply shows quote preview in inline composer; send persists `quotedMessageId` |
| 2 | swipe-to-reply shows preview and persists quotedMessageId on send | Swipe entry produces same quote persistence contract |
| 3 | long-press reply on sent feed message focuses composer and persists quotedMessageId on send | Overlay reply on sent message in expanded card; send persists correct `quotedMessageId` |
| 4 | group swipe-to-reply shows preview and persists quotedMessageId on send | Group-thread swipe-to-reply preserves `quotedMessageId` |
| 5 | inline reply restores quote and draft on send failure | Send failure restores quote draft and text |
| 6 | group inline reply restores quote and draft on send failure | Group send failure restores quote draft and text |
| 7 | incremental group updates preserve quoted replies in feed cards | Group refresh preserves quoted reply rendering |
| | **Edit** | |
| 8 | long-press edit prefills the feed composer and cancel exits edit mode | Edit prefills inline composer; cancel clears both |
| 9 | identical feed edit submit is a no-op | Unchanged text does not call `editChatMessageFn` |
| 10 | changed feed edit submit updates the same row and does not create a session reply | Changed text updates row in-place with `(edited)` indicator; no duplicate session reply |
| 11 | failed outgoing repository edit refresh updates the open feed card without reload | Edit failure refreshes card without full reload |
| | **Delete** | |
| 12 | feed delete-for-me removes the thread row and keeps the contact card | Delete-for-me removes message; contact card remains |
| 13 | feed delete-for-everyone refreshes to the next latest visible message | Delete-for-everyone removes message; card falls back to next latest |
| 14 | feed keeps the deleted placeholder visible while sender delete is failed | Failed delete tombstone stays visible and retryable |
| 15 | incoming deleted messages refresh the feed card to the deleted placeholder | Incoming delete refreshes card to placeholder |

---

## 6. Group Conversation Screen (Overlay Integration)

### 6.1 GroupConversationScreen -- overlay tests
**File:** `test/features/groups/presentation/group_conversation_screen_test.dart`
*6 overlay-relevant tests out of 20 total `testWidgets` in the file.*

| # | Test | What it covers |
|---|------|----------------|
| 1 | wraps incoming messages with swipe-to-quote when enabled | Group incoming rows expose the swipe-to-reply affordance |
| 2 | does not wrap outgoing messages with swipe-to-quote | Swipe-to-reply hidden for outgoing group rows |
| 3 | does not wrap incoming messages with swipe-to-quote for readers | Reader-role members do not get swipe-to-reply |
| 4 | renders quoted replies from existing parent messages | Group reply rows render quoted parent text |
| 5 | renders unavailable fallback when quoted parent is missing | Missing quoted source shows unavailable state |
| 6 | resolves quoted media-only parent from mediaMap | Media-only quoted parents resolve to media preview text |

---

## 7. Group Conversation Wired (Overlay + Reaction/Quote)

### 7.1 GroupConversationWired -- overlay-adjacent tests
**File:** `test/features/groups/presentation/group_conversation_wired_test.dart`
*7 overlay-relevant tests out of 62 total `testWidgets` in the file.*

| # | Test | What it covers |
|---|------|----------------|
| 1 | swipe-to-reply sends quotedMessageId and clears preview | Group swipe-to-reply preserves `quotedMessageId` on send |
| 2 | upload failure restores quote draft and attachments | Group media upload failure restores composer state |
| 3 | publish failure restores quote draft and attachments | Group publish failure restores composer state |
| 4 | voice upload failure restores the quoted reply target | Group voice upload failure preserves quote target |
| 5 | voice publish failure restores the quoted reply target | Group voice publish failure preserves quote target |
| 6 | reaction UI is disabled when reactionRepo is null | Long-press does not show reaction bar when reactions are disabled |
| 7 | incoming reaction change stream updates UI state | Incoming reaction stream updates visible state |

---

## 8. Notification Open Integration

### 8.1 Notification Open UI Smoke
**File:** `integration_test/notification_open_ui_smoke_test.dart`

| # | Test | What it covers |
|---|------|----------------|
| 1 | warm remote chat tap renders backlog before route completes | Warm remote chat opens honor prepare-then-route ordering |
| 2 | cold remote chat open still renders conversation messages | Cold remote chat opens land on conversation shell with backlog visible |
| 3 | group invite tap lands on intros surface with invite visible | Group invite notification keeps intros routing intact |
| 4 | warm local chat tap uses the same prepare-then-route flow | Warm local taps reuse prepare/drain/route ordering |
| 5 | cold remote open applies a pre-open delete before the first readable conversation frame | `DL-010` recipient first open never flashes deleted plaintext |
| 6 | warm local notification open after delete never surfaces the original body inside the app shell | `DL-020` in-app shell opens to deleted truth |
| 7 | warm remote open after background edit and delete shows only the latest stored state on first render | `SC-009` background-open resolves to latest state |
| 8 | relaunch open rebuilds stored quote edit delete and reaction state without stale pre-restart UI | `SC-001` full recreate restores all state on first frame |

---

## 9. Adjacent Application & Integration Tests

These tests live in use-case, integration, and database test files. They are not primary overlay tests, but they close specific rows in the MessageContextOverlay coverage matrix.

### 9.1 Reaction Use Cases

| File | Total Tests | Overlay-Relevant Coverage |
|------|-------------|--------------------------|
| `test/features/conversation/application/handle_incoming_reaction_use_case_test.dart` | 15 | sender-agreement validation before mutation; missing/deleted target rejection; duplicate/stale delivery idempotence |
| `test/features/conversation/application/send_reaction_use_case_test.dart` | 7 | preset happy-path persistence and send; non-preset emoji payloads unchanged; dual-failure explicit `sendFailed` (no false local success) |
| `test/features/conversation/application/remove_reaction_use_case_test.dart` | 5 | toggle-off delete semantics; dual-failure safety (no false local removal) |
| `test/features/conversation/application/reaction_listener_test.dart` | 10 | missing-target ignore (no spurious events); start/stop/dispose lifecycle single-subscription safety |
| `test/features/conversation/integration/emoji_reaction_exchange_test.dart` | 6 | preset convergence on both sides; add-then-remove toggle convergence; replacement semantics (one final reaction per sender/message) |

### 9.2 Edit Use Cases

| File | Total Tests | Overlay-Relevant Coverage |
|------|-------------|--------------------------|
| `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` | 34 | same-id edit preserves id/timestamps, sets `editedAt`, keeps quote linkage; edit-first stores hidden placeholder then materializes; cross-author rejection; duplicate/stale ignore; late edit after delete ignored; late original does not resurrect deleted row |
| `test/features/conversation/application/send_chat_message_use_case_test.dart` | 59 | outbound edit payload preserves original id, timestamp, createdAt, `quotedMessageId`, `action='edit'`, and `editedAt` |
| `test/features/conversation/application/chat_message_listener_test.dart` | 35 | edit-first phantom-free live listener path; idempotent start; stop cancels delivery |

### 9.3 Delete Use Cases

| File | Total Tests | Overlay-Relevant Coverage |
|------|-------------|--------------------------|
| `test/features/conversation/application/delete_message_use_case_test.dart` | 3 | delete-for-me hard delete + artifact cleanup (preserves unrelated files); unacked live delete-for-everyone keeps visible `sent` tombstone with retry metadata; full transport failure keeps visible failed tombstone |
| `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart` | 10 | delete-first tombstone creation; unauthorized rejection; sender agreement (stream/v2/payload must agree); artifact cleanup (owned only); duplicate idempotence; key-missing/undecryptable rejection; blocked-sender retraction of authored messages |
| `test/features/conversation/application/message_deletion_listener_test.dart` | 3 | idempotent start; stop cancels delivery; dispose safe |
| `test/features/conversation/integration/message_deletion_roundtrip_test.dart` | 5 | live delete-for-everyone convergence; inbox ordering convergence; blocked-sender convergence; restart tombstone preservation |

### 9.4 Quote / Reply Integration

| File | Total Tests | Overlay-Relevant Coverage |
|------|-------------|--------------------------|
| `test/features/conversation/integration/quote_reply_thread_test.dart` | 7 | `quotedMessageId` survives send/receive/serialization; missing source stays readable with preserved id; offline inbox restart preserves `quotedMessageId` |

### 9.5 Offline / Retry Integration

| File | Total Tests | Overlay-Relevant Coverage |
|------|-------------|--------------------------|
| `test/features/conversation/integration/offline_inbox_roundtrip_test.dart` | 8 | edit-first inbox drain phantom-free until original arrives; offline edit survives receiver restart |
| `test/features/conversation/integration/send_then_lock_delivery_test.dart` | 14 | failed send/edit/delete retry convergence through pause/resume |
| `test/features/conversation/domain/models/message_payload_test.dart` | 42 | v1/v2 envelope preserves edit `action='edit'` and `editedAt` metadata; `quotedMessageId` round-trip |

### 9.6 Database & Migration

| File | Total Tests | Overlay-Relevant Coverage |
|------|-------------|--------------------------|
| `test/core/database/migrations/016_message_reactions_test.dart` | 8 | UNIQUE `(message_id, sender_peer_id)` constraint prevents duplicate own reactions |
| `test/core/database/migrations/044_messages_deleted_state_test.dart` | 3 | existing rows get null deleted state values after upgrade |
| `test/core/database/integration/full_migration_chain_test.dart` | 6 | step-by-step upgrade preserves seeded data (schema safety for overlay state) |
| `test/core/database/helpers/messages_db_helpers_test.dart` | 56 | persists `edited_at` when present; persists deleted state metadata when present |
| `test/features/conversation/domain/repositories/message_repository_impl_test.dart` | 19 | `getMessagesForContact` excludes hidden tombstone rows |
| `test/features/conversation/domain/models/message_deletion_payload_test.dart` | 5 | delete payload serialization and sender-agreement validation |

---

## 10. Adjacent Group Application & Integration Tests

These tests live in group-specific use-case, integration, model, and database test files. They are the group-messaging counterparts to the 1:1 adjacent tests in §9 and close group-side overlay matrix gaps for reactions, send/receive, retry, and persistence.

### 10.1 Group Message Use Cases

| File | Total Tests | Overlay-Relevant Coverage |
|------|-------------|--------------------------|
| `test/features/groups/application/send_group_message_use_case_test.dart` | 54 | pre-persist/reconciliation status state machine; publish + inbox store concurrent paths; retry payload retention; media attachment persistence |
| `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` | 24 | deduplication (ID + content); dissolution boundary; sender removal boundary; sanitization; media attachment persistence |
| `test/features/groups/application/group_message_listener_test.dart` | 56 | system-message routing; normal message persistence; notification suppression; auto-download; reaction routing; replay envelope handling |

### 10.2 Group Reaction Use Cases

| File | Total Tests | Overlay-Relevant Coverage |
|------|-------------|--------------------------|
| `test/features/groups/application/send_group_reaction_use_case_test.dart` | 6 | group reaction send happy path; failure modes |
| `test/features/groups/application/remove_group_reaction_use_case_test.dart` | 3 | group reaction removal; failure safety |
| `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart` | 6 | incoming group reaction validation and persistence |
| `test/features/groups/integration/group_reaction_roundtrip_test.dart` | 1 | end-to-end group reaction exchange convergence |

### 10.3 Group Retry Use Cases

| File | Total Tests | Overlay-Relevant Coverage |
|------|-------------|--------------------------|
| `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` | 10 | failed group send recovery; text-only vs media retry paths |
| `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart` | 3 | stuck 'sending' → 'failed' transition for retry pickup |
| `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` | 7 | relay inbox store retry for pending messages |
| `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` | 7 | media upload retry for upload_pending attachments |

### 10.4 Group Models & Persistence

| File | Total Tests | Overlay-Relevant Coverage |
|------|-------------|--------------------------|
| `test/features/groups/domain/models/group_message_test.dart` | 8 | GroupMessage fromMap/toMap round-trip; nullable field serialization |
| `test/features/groups/domain/models/group_message_payload_test.dart` | 2 | group message payload serialization |
| `test/features/groups/domain/models/group_reaction_payload_test.dart` | 6 | group reaction payload serialization and validation |
| `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` | 26 | group message persistence; status updates; inbox stored tracking; retry payload management |
| `test/core/database/helpers/group_messages_db_helpers_test.dart` | 16 | group message DB insert/update/query; reliability column persistence |

---

## Gaps

- No dedicated unit tests for overlay action visibility logic in isolation (tested indirectly through screen/wired tests)
- No test for the `onPlusTap` → full emoji picker → selection round-trip as a single end-to-end flow (each component is tested individually)
- No test for overlay animation timing (fade-in/fade-out curves)
- No test for overlay positioning with keyboard visible (viewport insets shift)
- No E2E / simulator tests specifically targeting the overlay flow
- No group conversation overlay tests for edit, copy, or delete actions (group overlay coverage is limited to swipe-to-reply, quote rendering, and reaction disable/update)
- No group conversation screen test for long-press opening the overlay (only swipe-to-reply is tested)
- No group-specific integration test for edit or delete round-trips (only 1:1 conversation edit/delete round-trips are covered)
