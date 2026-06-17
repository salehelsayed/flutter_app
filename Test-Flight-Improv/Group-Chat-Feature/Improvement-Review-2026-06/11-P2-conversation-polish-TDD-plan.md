> Part of the **[Group Chat Improvement Review](./README.md)** · TDD plan for **[finding 11 (P2)](./11-P2-in-conversation-feedback-and-i18n-polish.md)**

---

# TDD plan — close 3 of the 7 in-conversation polish seams (items 3, 5, 2)

**Status: READY TO IMPLEMENT — re-verified 2026-06-17** · Branch base: `124-harness-refactor` · **No DB migration, no wire-format change, no Go build.** Dart-only, presentation-layer.

> **Re-verification (2026-06-17, 5-agent fan-out against the current dirty tree):** All **3 seams (items 3, 5, 2) are still present** and the fixes remain sound — start implementing. Two things changed since the 2026-06-16 read: (1) **line anchors drifted** — `group_conversation_wired.dart` +~2–27 lines, `group_conversation_wired_test.dart` +~110 lines (commit `b63c19d5` Finding-02 tests), `group_conversation_screen.dart` +~3 lines (uncommitted Finding-05 `send_failed` work); `group_list_screen.dart` is **unchanged** (anchors exact). Corrected anchors are inline below. (2) **The pre-flight regression worry was a false alarm** — see the corrected Pre-flight step 2 and Phase A RED step 2.

## Why this scope (the critical read)

Finding 11 lists 7 seams. A 14-agent verify-then-adversarially-refute pass (2026-06-16) re-checked every one against **current HEAD** (not the doc's 2026-06-06 line numbers, which have all shifted as commits 106/107 + features 111–125 grew these files). Result: **all 7 are still present** — the doc's prose is accurate — but only **3 are worth a fix cycle now**. The other 4 are deliberately out of scope:

| # | Seam | Present on HEAD? | In this plan? | Why |
|---|------|:---:|:---:|------|
| 3 | Hardcoded AM/PM timestamps | ✅ | ✅ **Yes** | Real i18n **bug** in *shipped* `de`/`ar` locales (`supportedLocales [ar,de,en]`). Near-mechanical port of the **proven in-repo pattern** the 1:1 screen already uses. |
| 5 | Own-send doesn't scroll into view (+ initial-load ordering parity) | ✅ | ✅ **Yes** | Real "did it send?" papercut when scrolled up. Reuses existing `_restoreScrollAfterMessageUpdate`. Tiny + contained. |
| 2 | Notification tap highlights but never scrolls | ✅ | ✅ **Yes** | Genuine navigation gap; existing tests *masque* it (assert cue exists, not visibility). Higher friction (lazy `ListView` + needs a `GlobalKey`). |
| 1 | Security status computed, never rendered in-thread | ✅ | ❌ No | Same warnings already render one tap away in Group Info. **Product decision** on inline placement, not a bug. |
| 4 | Group list O(N) reload per message, no debounce | ✅ | ❌ No | Pure perf hygiene; leaf screen, low N, cheap local queries, `setState`s coalesce per frame. Zero correctness impact. Backlog. |
| 6 | `successNoPeers` renders like live delivery | ✅ | ❌ No | **Deliberate, documented** decision (`send_group_message_use_case.dart:1570-1572`: a permanent pending clock is "misleading"). Inbox-*fail* already persists `'failed'`. Not a truthfulness bug. |
| 7 | Receiver-side ordering anchor (`receivedAtNano`) | ✅ | ❌ Defer | Doc itself: "defer unless a Go release is going out." Forward skew >5min already clamped; residual is rare. Needs `gomobile bind` + native release. |

All HEAD line numbers below were read on 2026-06-16; treat them as anchors and re-confirm before editing.

**Corrected anchors (read 2026-06-17 — supersede the inline 2026-06-16 numbers):**

| Anchor (plan ref) | 2026-06-16 | 2026-06-17 (current) |
|---|---|---|
| `group_conversation_screen.dart` `_formatTime` (AM/PM literal) | `:868-876` (lit `:874`) | `:871-879` (lit `:877`) |
| `group_conversation_screen.dart` `_formatTime` call site | `:589` | `:592` |
| `group_list_screen.dart` `_formatTime` / call site / `_buildGroupCard` | `:307-315` / `:239` / `:226` | **unchanged** `:307-315` / `:239` / `:226` |
| `conversation_screen.dart` 1:1 sibling pattern | `:823-827` | `:823-831` |
| `group_conversation_wired.dart` `_restoreScrollAfterMessageUpdate` | `:3363` | `:3389-3404` |
| `..._wired.dart` text optimistic (`showOptimisticMessage`/`optimisticDisplayed=true`) | `:1883` | `:1891` (true at `:1900`) |
| `..._wired.dart` voice optimistic setState | `:3665-3670` | `:3691-3696` |
| `..._wired.dart` post-send text upsert (do NOT scroll) | `:2071` | `:2088-2093` |
| `..._wired.dart` post-send voice upsert (do NOT scroll) | `:3770` | `:3797-3801` |
| `..._wired.dart` `_loadMessages` raw `_messages = messages` (the bug) | `:1253` | `:1251` |
| `..._wired.dart` `_upsertMessage` orders timeline | `:3247` | `:3265-3273` (orders at `:3273`) |
| `..._wired.dart` `orderGroupMessagesForTimeline` import | — | present `:59` (no new import) |
| `group_conversation_screen.dart` `_buildHighlightedMessageCue` | `:695` | `:698-742` |
| `group_conversation_screen.dart` highlight keys (shell / cue) | `:707` / `:718` | `:710` / `:721` |
| `group_conversation_screen.dart` `.reversed` display build / `reverse: true` | `:692` / `:537-540` | `:695` / `:540` |
| `..._wired.dart` `_loadMessages` post-frame (`_emitNotificationTapTimingIfNeeded`) | `:1260-1262` | `:1258-1260` |
| `..._wired.dart` screen construction (where `highlightAnchorKey` is passed) | `:4684` | `:4723` |
| `..._wired_test.dart` `buildWidget` factory / hard-coded `Locale('en')` | `:926-989` / `:954` | **unchanged** `:926-989` / `:954` |
| `..._wired_test.dart` GroupMessage fixture | `:4562-4573` | `:4676-4684` |
| `..._wired_test.dart` scroll-offset assertion pattern | `:4581-4607` | `:4693-4703` |
| `..._wired_test.dart` "incoming preserves scroll offset" + `getMessagesPageCalls == 1` | `:4555` / `:4608` | `:4668` / `:4720` |
| `..._wired_test.dart` existing highlight tests (cue-exists, mask item 2) | `:4380` / `:4448` | `:4488` / `:4560` |
| `conversation_screen_test.dart` locale pump / `ar` pump | `:66-69` / `:1277` | **unchanged** `:66-69` / `:1277` |

Confirmed absent (as the plan assumes): `test/features/groups/domain/utils/group_message_ordering_test.dart` and the `domain/utils` test dir do not exist; no existing scroll-to-highlighted logic; `intl: any` present `pubspec.yaml:35`; `supportedLocales == [ar, de, en]` `app_localizations.dart:97-101`. Note both group screens still **lack** the `import 'package:intl/intl.dart' as intl;` — add it in GREEN (Phase A already calls for this).

## Pre-flight (do once, before any code)

1. **Confirm green baseline** for the suites this plan touches:
   - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
   - `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
   - `flutter test test/features/groups/presentation/group_list_screen_test.dart test/features/groups/presentation/group_card_test.dart`
   - `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
2. **Regression-surface grep** (run it, but the risk is smaller than it looks):
   `GRAPH_OK=1 grep -rnE "'(AM|PM)'|[0-9]:[0-9][0-9] (AM|PM)" test/features/groups test/features/conversation`
   **2026-06-17 finding:** the 13 hits are **all in widget tests that pass a *pre-formatted* time string as a prop** — `group_card_test.dart:69` / `group_card_bidi_test.dart:39` feed `lastMessageTime: '9:30 AM'` (`GroupCard.lastMessageTime` is `final String?`), and `letter_card_test.dart` (×11) feeds `time: '3:30 PM'` (`LetterCard.time` is `final String`). **None of them invoke `_formatTime`**, so making `_formatTime` locale-aware **does not touch them** — no reconciliation needed. (`LetterCard` is the 1:1 row, whose screen-level `_formatTime` is already localized anyway.) The real test surface is the *screen* level — see Phase A RED.
3. `intl` is already a direct dependency (`pubspec.yaml: intl: any`). The 1:1 sibling proves the harness renders `DateFormat.jm` under non-en locales (`test/.../conversation_screen_test.dart:1277` pumps `Locale('ar')`).

**Recommended landing order: 3 → 5 → 2** (smallest/safest first). Each item is an independent commit.

## Shared test conventions (reuse, don't reinvent)

- **Locale pumping:** wrap under `MaterialApp(locale: Locale('de'|'ar'|'en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, …)` — pattern at `conversation_screen_test.dart:66-69` and `group_conversation_wired_test.dart:953-956`.
- **GroupConversationWired factory:** `buildWidget({…, String? initialHighlightedMessageId})` at `group_conversation_wired_test.dart:926-989`. It hard-codes `locale: Locale('en')` at :954 — **add a `Locale locale = const Locale('en')` param** threaded to the `MaterialApp` so item-3 wired tests (if needed) and future locale tests can pump non-en.
- **GroupMessage fixture:** direct constructor `GroupMessage(id, groupId, senderPeerId, senderUsername, text, timestamp, createdAt, isIncoming)` — see `group_conversation_wired_test.dart:4562-4573`.
- **Scroll-offset assertion pattern (canonical):** `final controller = tester.widget<ListView>(find.byKey(const ValueKey('group-messages'))).controller!;` then `controller.jumpTo(240)` / read `controller.offset` — `group_conversation_wired_test.dart:4581-4607`. The list is `reverse: true`, so **offset 0 == live edge (newest)**, `group_conversation_screen.dart:537-540`.
- **Highlight keys (production contract):** `ValueKey('grp-highlight-<id>')` shell + `ValueKey('grp-highlight-cue-<id>')` accent bar, `group_conversation_screen.dart:707,718`.

---

## Phase A — Item 3: locale-aware timestamps (effort: SMALL, risk: LOW)

### Invariant
Time-of-day rendering in both group screens follows the active locale: `de` → 24-hour (`14:05`, no AM/PM), `ar` → Eastern-Arabic digits + localized marker, `en` → unchanged (`2:05 PM`). **No new l10n strings.** Day separators (`format_day_separator_label.dart`) are a *separate* concern — do not touch.

### RED — write failing tests first
1. **`test/features/groups/presentation/group_conversation_screen_test.dart`** — new group `'localized timestamps'`:
   - Pump `GroupConversationScreen` (via its existing `buildTestWidget`) with one message at a fixed UTC instant that is `14:05` **local** (construct with an explicit local `DateTime` to avoid TZ flakiness — e.g. build the message timestamp from `DateTime(2026, 2, 9, 14, 5)` and assert on the local-formatted string).
   - `Locale('de')` → `expect(find.textContaining('14:05'), findsOneWidget); expect(find.textContaining('PM'), findsNothing);`
   - `Locale('en')` → `expect(find.textContaining('2:05'), findsOneWidget);` and the `PM` marker present.
   - `Locale('ar')` → assert the rendered time string contains an Eastern-Arabic digit (e.g. `expect(find.textContaining('١'), findsWidgets)` or compare against `intl.DateFormat.jm('ar').format(local)` computed in-test). Keep this assertion tolerant (compare to the live `DateFormat` output) so it can't rot on ICU data updates.
2. **`test/features/groups/presentation/group_list_screen_test.dart`** — mirror the `de` 24-hour + `en` cases at the **screen** level (pump `GroupListScreen` with a group whose `lastMsg.timestamp` is a fixed local `DateTime`, assert the rendered `GroupCard` text). **Not `group_card_test.dart`** — `GroupCard.lastMessageTime` is a pre-formatted `String?` prop, so the formatting under test lives in `group_list_screen._formatTime`, not in the card. Test where `_formatTime` actually runs.

These fail today: both `_formatTime` bodies emit literal `'AM'/'PM'` (`group_conversation_screen.dart:874`, `group_list_screen.dart:313`).

### GREEN — implementation
- **`lib/features/groups/presentation/screens/group_conversation_screen.dart`**
  - Add `import 'package:intl/intl.dart' as intl;`.
  - Convert `static String _formatTime(DateTime timestamp)` (`:868-876`) → instance `String _formatTime(BuildContext context, DateTime timestamp)` returning:
    ```dart
    final locale = Localizations.localeOf(context).toString();
    return intl.DateFormat.jm(locale).format(timestamp.toLocal());
    ```
    (Exactly the 1:1 sibling pattern, `conversation_screen.dart:823-827`.)
  - Update the call site `time: _formatTime(message.timestamp)` (`:589`) → `_formatTime(context, message.timestamp)`. `context` is in scope there (inside `itemBuilder: (context, index)`).
- **`lib/features/groups/presentation/screens/group_list_screen.dart`**
  - Add the `intl` import (if absent).
  - `_formatTime` (`:307-315`) → `String _formatTime(BuildContext context, DateTime timestamp)` with the same body.
  - Call site `_formatTime(lastMsg.timestamp)` (`:239`) → `_formatTime(context, lastMsg.timestamp)`. `context` is the `_buildGroupCard(BuildContext context, …)` param (`:226`).
- Delete the now-unused manual `hour`/`minute`/`period` math.

### Verify / regression
- New tests green; reconcile any pre-existing `AM`/`PM` literal assertions surfaced in Pre-flight step 2.
- `flutter analyze` clean (watch for "unused import" if a screen no longer needs a symbol).

---

## Phase B — Item 5: own-send scrolls to live edge + initial-load ordering parity (effort: SMALL, risk: LOW)

Two independent sub-fixes, bundled (same method family, both tiny).

### Invariant
**(a)** A user-initiated send **always** lands the user at the live edge (offset 0), even when scrolled up — because the user just acted, there is no "reading history" ambiguity for your *own* send. **(b)** Initial-load order equals post-upsert order: `_loadMessages` applies the same `orderGroupMessagesForTimeline` that `_upsertMessage` does, so the first incoming/sent message never reshuffles existing rows.

### RED — failing tests
1. **Own-send scroll** (`group_conversation_wired_test.dart`, mirror the `:4555` offset test):
   - Seed 40 messages, pump, grab the `group-messages` controller, `controller.jumpTo(240)`, assert `controller.offset > 32`.
   - Drive a text send (enter text into the composer + tap send; reuse the send-driving helper used by existing composer tests). The optimistic insert fires before the network result, so it is deterministic regardless of bridge outcome.
   - `await pumpFrames(...)`; **assert `controller.offset` is `closeTo(0, 1.0)`**. Fails today (send path never scrolls).
2. **Initial-load ordering parity** — two layers:
   - **New unit suite** `test/features/groups/domain/utils/group_message_ordering_test.dart` (none exists today): lock `orderGroupMessagesForTimeline` — chronological passthrough, a non-adjacent quoted reply placed directly after its parent, missing-parent graceful placement, and a stable result for `length < 2`. This pins behavior before we widen its use.
   - **Parity test** (wired or screen): build a thread where chronological order ≠ quote-threaded order (a reply quoting an older message, with another message in between). Assert the **initial rendered row order** equals the order after a subsequent `_upsertMessage`. Fails today (`_loadMessages` sets `_messages = messages` raw at `:1253`; `_upsertMessage` threads at `:3247`).

### GREEN — implementation
- **`lib/features/groups/presentation/screens/group_conversation_wired.dart`**
  - Add a helper near `_restoreScrollAfterMessageUpdate` (`:3363`):
    ```dart
    void _scrollToLiveEdge() {
      _restoreScrollAfterMessageUpdate(preserveScrollOffset: false, previousOffset: 0);
    }
    ```
    (Reuses the existing post-frame `jumpTo(0)` path; no new scroll logic.)
  - Call `_scrollToLiveEdge()` at the **two optimistic-insert sites** (post-frame after the `setState`):
    - text send — inside `showOptimisticMessage()` after `optimisticDisplayed = true;` (`:1883`).
    - voice send — after the optimistic `setState` at `:3665-3670`.
  - Do **not** add it to the post-send upserts (`:2071`, `:3770`) — the optimistic insert already moved the viewport; re-scrolling there would fight a user who scrolled away during upload.
  - **(b)** In `_loadMessages`, wrap the page result: `_messages = orderGroupMessagesForTimeline(messages);` at `:1253` (import already present — it's used at `:3247`).

### Verify / regression
- The `:4555` "incoming message preserves scroll offset" test must stay green — incoming path still routes through `_shouldPreserveScrollOffset()` (`:3358`); only the *send* path changed.
- The two existing highlight tests (`:4380`, `:4448`) and `getMessagesPageCalls == 1` (`:4608`) stay green: their threads have no quotes, so `orderGroupMessagesForTimeline` is an order-preserving no-op.
- **Pagination note:** `getMessagesPage` returns a page; `orderGroupMessagesForTimeline` only reorders within the loaded set and tolerates a quoted parent absent from the page (`group_message_ordering.dart:34-41`). Safe.

---

## Phase C — Item 2: scroll the notification-tapped message into view (effort: MEDIUM, risk: MEDIUM)

The hardest of the three: a lazy `reverse: true` `ListView.builder` doesn't lay out off-screen rows, so a far target's `grp-highlight-<id>` widget isn't even built, and `Scrollable.ensureVisible` can't reach an unbuilt row.

### Invariant
When the conversation opens from a notification tap (`initialHighlightedMessageId != null`) **and** that id exists in the loaded set, the matching row is **brought on-screen** (not merely highlighted). Best-effort + bounded: if the id isn't in the loaded page, set a one-shot pending flag, retry after the next load, give up silently after a small cap. Never fight the user if they scroll during the post-frame jump.

### RED — failing test (expose the masked gap)
In `group_conversation_wired_test.dart`, new test `'scrolls the notification-tapped older message into view'`:
- Seed **40** messages; set `initialHighlightedMessageId` to the **oldest** id (far from the live edge / offset 0).
- Pump + `pumpFrames`.
- `expect(find.byKey(ValueKey('grp-highlight-<oldest>')), findsOneWidget);` **and** assert it is within the viewport via `tester.getRect(...)` against the list's rect.
- **Today this FAILS** (`findsNothing` — the row is never built). Contrast: the existing `:4380`/`:4448` tests pass only because their target is one of 2 on-screen messages — they assert the cue *exists*, never visibility. (Leave those as-is; they still pass after the fix since the already-visible target needs no scroll.)

### GREEN — implementation
- **`group_conversation_screen.dart`:** thread an optional `GlobalKey? highlightAnchorKey` from the wired layer; in `_buildHighlightedMessageCue` (`:695`), attach it to the highlighted row's outer widget (alongside the existing `ValueKey('grp-highlight-<id>')`). A `GlobalKey` gives the wired layer a `currentContext` for `ensureVisible`.
- **`group_conversation_wired.dart`:** add `_scrollToHighlightedMessage()` and a `final GlobalKey _highlightAnchorKey = GlobalKey();` (passed into the screen at `:4684`-adjacent props):
  1. Guard: `widget.initialHighlightedMessageId != null`, not already done, and the id is in `_messages` (else set `_pendingHighlightScroll = true` and return — retried from `_loadMessages`).
  2. Compute the **reversed** index: `reverseIndex = _messages.length - 1 - chronologicalIndex` (display list is `.reversed`, `group_conversation_screen.dart:692`).
  3. Coarse jump to build the row: `final est = (reverseIndex / _messages.length) * _scrollController.position.maxScrollExtent; _scrollController.jumpTo(est.clamp(0, maxExtent));`
  4. Post-frame, refine: `if (_highlightAnchorKey.currentContext != null) Scrollable.ensureVisible(_highlightAnchorKey.currentContext!, alignment: 0.5, duration: …);` else retry (bounded, ≤5) via `addPostFrameCallback`.
  5. Wrap the whole thing in `WidgetsBinding.instance.addPostFrameCallback`.
- **Trigger:** from `_loadMessages` success, in the existing post-frame block at `:1260-1262`, alongside `_emitNotificationTapTimingIfNeeded()` — call `_scrollToHighlightedMessage()`.
- **Optional (nice-to-have, can split out):** clear the highlight after ~3s via a `Timer`, storing a nullable local `_highlightOverride` preferred over `widget.initialHighlightedMessageId`, so the cue fades. Keep out of the minimum if it complicates the test.

### Verify / regression
- New RED test green; `:4380`/`:4448`/`:4555` green.
- If `ensureVisible` proves flaky under `flutter_test` (no real layout pass for far rows), fall back to asserting the coarse-jump alone renders the row + `getRect` overlaps the viewport — document whichever the implementation lands on.
- **Carry-over note for the 1:1 screen:** `conversation_wired.dart` almost certainly has the same scroll-to gap. Out of scope here, but file a follow-up so they converge (the screen-level `_formatTime` in 1:1 is *already* localized — only the scroll-to-tapped path would need this).

---

## Risks, trade-offs & rollout

- **Item 3:** changing `static` → instance `_formatTime` touches call sites only; pure formatting. Only real risk = tests asserting literal `AM`/`PM` (handled in Pre-flight). `de`/`ar` ICU data is already exercised by the 1:1 ar test, so no `initializeDateFormatting` needed.
- **Item 5:** own-send unconditionally jumps to edge — correct because the user acted. The `(b)` ordering wrap is order-preserving for quote-free threads (the common case) and only *fixes* reshuffle for quoted threads.
- **Item 2:** the only non-trivial one. `GlobalKey` + estimate-then-`ensureVisible` with bounded retry is the standard lazy-list pattern; guard against (a) id not in page (pending-retry), (b) user scrolling mid-jump (don't re-fight after first success).
- **Rollout:** 3 independent commits behind the same theme branch, order 3 → 5 → 2. No feature flags, each reversible and UI-local. No wire/DB/Go changes.

## Gate commands

```
flutter analyze
flutter test test/features/groups/presentation/group_conversation_screen_test.dart \
             test/features/groups/presentation/group_conversation_wired_test.dart \
             test/features/groups/presentation/group_list_screen_test.dart \
             test/features/groups/presentation/group_card_test.dart \
             test/features/groups/domain/utils/group_message_ordering_test.dart \
             test/features/conversation/presentation/widgets/letter_card_test.dart
./scripts/run_test_gates.sh groups
```

## Out of scope (explicit)

Items **1** (security banner — product decision), **4** (list debounce — perf nit), **6** (no-peers indicator — intentional design), **7** (`receivedAtNano` — defer to a Go release). Each was confirmed still-present on HEAD but judged not worth a fix cycle now; rationale in the scope table above.
