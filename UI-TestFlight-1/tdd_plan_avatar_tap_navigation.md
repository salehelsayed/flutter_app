# TDD Plan: Avatar Tap Navigates to Full Conversation

## Goal

When a user taps the **profile picture (UserAvatar)** on a feed card, navigate them to the full conversation screen (same as "View earlier messages"). The existing header tap behavior (expand/collapse) must remain unchanged — only the avatar area gets the new navigation behavior.

---

## Current Behavior

| Area tapped | Card mode | Current behavior |
|---|---|---|
| **Header row** (collapsed) | Collapsed | Expands the card (`onTapExpand`) |
| **Header row** (open) | Open | No tap handler (static) |
| **"View earlier messages"** | Open / Expanded | Navigates to `ConversationWired` via `onViewFullConversation` |
| **UserAvatar** | Any | No dedicated handler — absorbed by parent `GestureDetector` |

## Target Behavior

| Area tapped | Card mode | New behavior |
|---|---|---|
| **UserAvatar** | Any (open, collapsed, expanded) | Navigate to full conversation (`onViewFullConversation`) |
| **Header row (excluding avatar)** | Collapsed | Still expands the card (unchanged) |
| **Header row** | Open | Still no-op (unchanged) |

---

## Architecture

Both card body widgets already receive the navigate-to-conversation callback from `FeedCard`:

- `OpenModeCardBody.onViewEarlier` — set to `widget.onViewFullConversation` at `feed_card.dart:166`
- `CollapsedModeCardBody.onViewFullConversation` — set to `widget.onViewFullConversation` at `feed_card.dart:195`

**No new callbacks or prop plumbing needed.** Each card body just wraps its avatar in a `GestureDetector` using the callback it already has.

```
FeedScreen (already has onViewFullConversation callback)
  └─ FeedCard (already receives and passes onViewFullConversation)
       ├─ OpenModeCardBody  ← wrap avatar with existing onViewEarlier
       └─ CollapsedModeCardBody ← wrap avatar with existing onViewFullConversation
```

---

## Files to Modify

| File | Change |
|---|---|
| `lib/features/feed/presentation/widgets/open_mode_card_body.dart` | In `_buildHeader()`, wrap `UserAvatar` / group icon in `GestureDetector(onTap: onViewEarlier)` |
| `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart` | In `_buildHeader()`, wrap `UserAvatar` / group icon in `GestureDetector(onTap: onViewFullConversation)`, keeping the outer `GestureDetector(onTap: onTapExpand)` in `build()` unchanged |

**No changes needed in:**
- `FeedCard` — already passes `onViewFullConversation` to both card bodies
- `FeedScreen` — already passes `onViewFullConversation` to `FeedCard`
- `FeedWired` — `_onReplyToMessage` already handles navigation
- `FeedItem` models — no domain change

---

## TDD Steps

### Phase 1: OpenModeCardBody — Avatar tap navigates to conversation

#### Test 1.1: Tapping UserAvatar fires `onViewEarlier` (1:1 thread)

**File:** `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`

```dart
testWidgets('tapping avatar fires onViewEarlier', (tester) async {
  var tapped = false;
  final thread = ThreadFeedItem(/* ... unread messages ... */);

  await tester.pumpWidget(wrap(OpenModeCardBody(
    thread: thread,
    onViewEarlier: () => tapped = true,
  )));

  await tester.tap(find.byType(UserAvatar));
  expect(tapped, isTrue);
});
```

**Implementation:**
In `_buildHeader()`, wrap `UserAvatar(peerId: thread.displayId, size: 42)` with `GestureDetector(onTap: onViewEarlier)`. Same for the group icon `Container`.

#### Test 1.2: Group thread — tapping group icon fires `onViewEarlier`

The header branches on `thread.isGroup` (not `groupType`), so one group test covers all group types (chat, announcement, qa) — they all render the same icon.

```dart
testWidgets('group thread: tapping group icon fires onViewEarlier', (tester) async {
  var tapped = false;
  final groupThread = GroupThreadFeedItem(
    groupType: GroupType.chat,
    /* ... unread messages ... */
  );

  await tester.pumpWidget(wrap(OpenModeCardBody(
    thread: groupThread,
    onViewEarlier: () => tapped = true,
  )));

  await tester.tap(find.byIcon(Icons.group_rounded));
  expect(tapped, isTrue);
});
```

---

### Phase 2: CollapsedModeCardBody — Avatar tap navigates while header still expands

This is the trickiest part. Currently the **entire header row** is wrapped in a single `GestureDetector(onTap: onTapExpand)` at `build()` line 88. We nest a smaller `GestureDetector` on just the avatar **inside** `_buildHeader()` to intercept that tap area. Flutter hit-testing lets the inner detector win its region while everything else (name, time, checkmark, padding) falls through to the outer one.

**Keep the outer `GestureDetector` in `build()` unchanged** — do NOT remove or split it.

#### Test 2.1: Tapping avatar fires `onViewFullConversation` (NOT `onTapExpand`)

```dart
testWidgets('tapping avatar fires onViewFullConversation, not onTapExpand', (tester) async {
  var navigated = false;
  var expandTapped = false;
  final thread = ThreadFeedItem(/* ... read state ... */);

  await tester.pumpWidget(wrap(CollapsedModeCardBody(
    thread: thread,
    onViewFullConversation: () => navigated = true,
    onTapExpand: () => expandTapped = true,
  )));

  await tester.tap(find.byType(UserAvatar));
  expect(navigated, isTrue);
  expect(expandTapped, isFalse);
});
```

**Implementation:**
In `_buildHeader()`, wrap just the avatar widget in `GestureDetector(onTap: onViewFullConversation)` so it intercepts its own tap area.

```dart
// In build() — UNCHANGED from current code:
GestureDetector(
  onTap: onTapExpand,
  behavior: HitTestBehavior.opaque,
  child: _buildHeader(),   // avatar internally intercepts its own area
),

// In _buildHeader() — only the avatar line changes:
Widget _buildHeader() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
    child: Row(
      children: [
        // Avatar — navigates to full conversation
        GestureDetector(
          onTap: onViewFullConversation,
          child: thread.isGroup
              ? _buildGroupIcon()
              : UserAvatar(peerId: thread.displayId, size: 42),
        ),
        const SizedBox(width: 12),
        Expanded(child: _buildHeaderText()),
        if (_isReplied) _buildRepliedCheckmark(),
      ],
    ),
  );
}
```

#### Test 2.2: Tapping the display name still fires `onTapExpand`

```dart
testWidgets('tapping display name still fires onTapExpand', (tester) async {
  var navigated = false;
  var expandTapped = false;
  final thread = ThreadFeedItem(
    contactUsername: 'Alice',
    /* ... */
  );

  await tester.pumpWidget(wrap(CollapsedModeCardBody(
    thread: thread,
    onViewFullConversation: () => navigated = true,
    onTapExpand: () => expandTapped = true,
  )));

  await tester.tap(find.text('Alice'));
  expect(expandTapped, isTrue);
  expect(navigated, isFalse);
});
```

#### Test 2.3: Tapping the timestamp still fires `onTapExpand`

```dart
testWidgets('tapping timestamp still fires onTapExpand', (tester) async {
  var expandTapped = false;
  final thread = ThreadFeedItem(/* with known time string */);

  await tester.pumpWidget(wrap(CollapsedModeCardBody(
    thread: thread,
    onTapExpand: () => expandTapped = true,
  )));

  await tester.tap(find.text(thread.latestMessage.time));
  expect(expandTapped, isTrue);
});
```

#### Test 2.4: Group thread collapsed — tapping group icon fires `onViewFullConversation`

```dart
testWidgets('group thread collapsed: tapping icon navigates', (tester) async {
  var navigated = false;
  var expandTapped = false;
  final groupThread = GroupThreadFeedItem(
    groupType: GroupType.chat,
    /* ... read state ... */
  );

  await tester.pumpWidget(wrap(CollapsedModeCardBody(
    thread: groupThread,
    onViewFullConversation: () => navigated = true,
    onTapExpand: () => expandTapped = true,
  )));

  await tester.tap(find.byIcon(Icons.group_rounded));
  expect(navigated, isTrue);
  expect(expandTapped, isFalse);
});
```

#### Test 2.5: When expanded, tapping avatar still fires `onViewFullConversation`

```dart
testWidgets('expanded card: tapping avatar navigates', (tester) async {
  var navigated = false;
  final thread = ThreadFeedItem(/* ... */);

  await tester.pumpWidget(wrap(CollapsedModeCardBody(
    thread: thread,
    isExpanded: true,
    onViewFullConversation: () => navigated = true,
  )));

  await tester.tap(find.byType(UserAvatar));
  expect(navigated, isTrue);
});
```

#### Test 2.6: Tapping replied checkmark still fires `onTapExpand` (regression guard)

This test guards against the exact regression the nested-GestureDetector approach prevents.

```dart
testWidgets('tapping replied checkmark still fires onTapExpand', (tester) async {
  var expandTapped = false;
  var navigated = false;
  final thread = ThreadFeedItem(
    conversationState: ConversationState.replied,
    lastRepliedAt: DateTime(2026, 2, 9, 15, 0),
    /* ... */
  );

  await tester.pumpWidget(wrap(CollapsedModeCardBody(
    thread: thread,
    onViewFullConversation: () => navigated = true,
    onTapExpand: () => expandTapped = true,
  )));

  // Tap the checkmark icon in the trailing position
  await tester.tap(find.byIcon(Icons.check_rounded));
  expect(expandTapped, isTrue);
  expect(navigated, isFalse);
});
```

---

### Phase 3 (optional): Integration — Full flow from FeedScreen through FeedWired

> **Note:** Phases 1–2 already prove avatar tap fires the existing callback. The callback chain
> from `FeedCard` → `FeedScreen` → `FeedWired` → `Navigator.push(ConversationWired)` is already
> covered by existing "View earlier messages" integration tests (`feed_wired_test.dart:1759`,
> `:3291`), since the avatar tap reuses the same callbacks. These FeedWired-level tests are
> high-cost (3600+ lines of setup) for marginal extra confidence. Write only if you want
> belt-and-suspenders coverage.

#### Test 3.1: FeedWired navigates to ConversationWired when avatar tapped

**File:** `test/features/feed/presentation/screens/feed_wired_test.dart`

```dart
testWidgets('tapping feed card avatar navigates to conversation', (tester) async {
  // Setup: seed a contact + incoming message so a ThreadFeedItem appears
  // ... (use existing FeedWired test setup pattern with fakes)

  await tester.pumpWidget(buildFeedWired());
  await tester.pumpAndSettle();

  final feedCardAvatars = find.descendant(
    of: find.byType(FeedCard),
    matching: find.byType(UserAvatar),
  );
  await tester.tap(feedCardAvatars.first);
  await tester.pumpAndSettle();

  expect(find.byType(ConversationWired), findsOneWidget);
});
```

**Existing regression coverage** — no new tests needed, just run the full suite:
- Header expand: `feed_card_test.dart:324`, `collapsed_mode_card_body_test.dart:191`
- "View earlier messages": `feed_card_flow_test.dart:280`, `feed_wired_test.dart:1759`
- Group navigation: `feed_wired_test.dart:3291`
- Inline reply: existing `inline_reply_input_test.dart` tests

---

## Implementation Order (Red-Green-Refactor)

| Step | Action | Files |
|---|---|---|
| 1 | Write Tests 1.1–1.2 (OpenModeCardBody) | `open_mode_card_body_test.dart` |
| 2 | **RED** — run tests, confirm failure | |
| 3 | Implement: wrap avatar in `GestureDetector(onTap: onViewEarlier)` | `open_mode_card_body.dart` |
| 4 | **GREEN** — run tests, confirm pass | |
| 5 | Write Tests 2.1–2.6 (CollapsedModeCardBody) | `collapsed_mode_card_body_test.dart` |
| 6 | **RED** — run tests, confirm failure | |
| 7 | Implement: nest `GestureDetector(onTap: onViewFullConversation)` on avatar inside `_buildHeader()` | `collapsed_mode_card_body.dart` |
| 8 | **GREEN** — run tests, confirm pass | |
| 9 | Run ALL existing feed tests — verify no regressions | |
| 10 | **REFACTOR** — clean up if needed | |
| 11 | _(Optional)_ Write Test 3.1 (FeedWired integration) | `feed_wired_test.dart` |

---

## Edge Cases to Consider

1. **Blocked contacts** — Out of scope. The current `_buildBlockedOverlay()` uses `Positioned.fill` over the entire card (`feed_card.dart:215`), which absorbs all taps. Avatar tap will not work on blocked cards without additional changes to the overlay, and that's a separate design decision.
2. **Group threads** — Group icon tap navigates to group conversation for consistency. Both card bodies already receive the right callback for groups via the same `onViewEarlier` / `onViewFullConversation` params.
3. **Connection cards** — These use a larger 98px avatar for new connections, not message threads. Out of scope — these don't have a "conversation" to navigate to (user taps "Send a message" instead).
4. **Tap target size** — The 42px avatar is small. Consider wrapping with a minimum 48x48 tap target for accessibility (Material guidelines). This can be done with `SizedBox(width: 48, height: 48)` around the `GestureDetector`.
5. **Visual feedback** — Consider adding an `InkWell` or `Material` splash effect on avatar tap to give the user visual confirmation. Optional polish step.

---

## Summary of Changes

- **2 files modified** (open_mode_card_body.dart, collapsed_mode_card_body.dart)
- **0 new files** created
- **0 new callbacks** — uses existing `onViewEarlier` and `onViewFullConversation`
- **~8 new tests** across 2 test files (+ 1 optional integration test)
- **No model/domain changes** — purely presentation layer
