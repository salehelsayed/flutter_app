> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P2** · [Findings appendix](./appendix-findings.md)

---

# Close the in-conversation feedback, i18n, and performance seams

**Priority: P2** &nbsp;|&nbsp; **Effort: Medium (sum of small/medium items)** &nbsp;|&nbsp; **Type: Polish / fast-follow after P0 stabilization** &nbsp;|&nbsp; **No wire-format or DB-migration changes required** (one optional Go-side additive field for the timestamp-ordering item)

## Why this matters (user experience)

The group-chat feature is functionally correct, but a cluster of visible seams make it feel unfinished and non-native, disproportionately for German and Arabic users:

- A user actively chatting in a compromised group gets **zero in-thread signal** that a member's signing identity changed (possible MITM/impersonation) or that the group key rotated. The data is computed but thrown away before render.
- Tapping a notification for a specific message **does not land the user on that message** — it opens at the newest message and silently highlights something off-screen.
- Every timestamp in the feature is **hardcoded English 12-hour AM/PM with Latin digits**, which is wrong for `de` (expects 24-hour) and `ar` (expects localized digits/markers).
- A burst of incoming messages (offline catch-up, busy group) triggers a **full O(N) DB reload of the group list per message**, producing jank and battery drain exactly when traffic is heaviest.
- Sending your own message while scrolled up **leaves your message off-screen**, so the send looks like it did nothing.
- A "nobody online, stored to relay inbox" send is rendered **identically to a live delivery**, over-promising that the message landed.

None of these break correctness, so they are an ideal fast-follow once the P0 stabilization work is in. Most are small, self-contained, and independently shippable.

## Current behaviour & evidence

| # | Seam | Evidence (file:line) |
|---|------|----------------------|
| 1 | Security status computed, never rendered in conversation | `_loadSecurityStatus` builds `_securityStatus` incl. per-member `GroupMemberIdentitySafety` (`group_conversation_wired.dart:1011-1082`), passed to screen (`group_conversation_wired.dart:3959`). Screen only declares the field (`group_conversation_screen.dart:85,140`); no render use in `build()`. View-state already exposes `shouldShowCompactStatus`/`hasIdentityWarnings`/`hasKeyChangeWarning`/`compactEncryptionLabel`/`compactReviewLabel` (`group_security_status_view_state.dart:56-120`), consumed only by `group_info_screen.dart`. |
| 2 | Notification tap highlights but never scrolls | `highlightedMessageId` threaded as `widget.initialHighlightedMessageId` (`group_conversation_wired.dart:3970`), used only to wrap the matching row in an `AnimatedContainer` (`group_conversation_screen.dart:548,620-632`). No `ensureVisible`/`scrollTo` anywhere in the group presentation layer; only scroll primitive is `jumpTo(0)`/`jumpTo(targetOffset)` in `_restoreScrollAfterMessageUpdate` (`group_conversation_wired.dart:2796-2811`). |
| 3 | Hardcoded AM/PM timestamps | `_formatTime` builds the string manually with `final period = local.hour < 12 ? 'AM' : 'PM'` in `group_conversation_screen.dart:766-774` (used at line 566) and `group_list_screen.dart:307-315` (used at line 239). Correct locale-aware pattern already exists in the same feature: `pending_group_invite_card.dart:171-176` uses `intl.DateFormat.MMMd(l10n.localeName).add_jm()`. |
| 4 | Group list full reload per message, no debounce | `group_list_wired.dart:200-234` subscribes `groupMessageStream`/`groupJoinedStream`/`pendingInviteStream` with `(_) => _loadGroups()`. `_loadGroups` (`127-169`) loops all active groups doing sequential `await getLatestMessage(group.id)` and `await getUnreadCount(group.id)` (`138-143`) plus `_loadPendingInvites`. No debounce/throttle/Timer anywhere in the file. |
| 5 | Optimistic send doesn't scroll into view | `showOptimisticMessage()` (`group_conversation_wired.dart:1641-1651`) and the post-send upsert (`1837-1844`) call `_upsertMessage` inside `setState` only; neither calls `_restoreScrollAfterMessageUpdate` nor `jumpTo(0)`. Incoming messages do scroll via `_applyMessageUpdate` (`2462-2493`). The list is `reverse: true` (`group_conversation_screen.dart:533`), so a user scrolled up (`pixels > _liveEdgeTolerance`, tolerance = 32.0 at `wired:175`) never sees their own send. |
| 6 | `successNoPeers` looks like live delivery | `sendGroupMessage` persists status `'sent'` with `inboxStored: true` and returns `SendGroupMessageResult.successNoPeers` (`send_group_message_use_case.dart:1327-1370`). Wired layer treats `successNoPeers` identically to `success` (`group_conversation_wired.dart:1819-1821`; same in `_onRecordStop`). `LetterCard._statusIcon` maps both `'sent'` and `'sending'` to `Icons.done_rounded` (`letter_card.dart:525-533`); `_statusSemantic` returns `message_status_sent` for `'sent'` (`letter_card.dart:566`). The `inboxStored` distinction is persisted but never surfaced. |
| 7 (optional) | Sender-supplied timestamp ordering | `buildGroupMessageEnvelope` stamps `payload.Timestamp` from `resolveGroupPublishTimestamp(opts)` and `publishedAtNano` from the sender clock (`pubsub.go:427,433,1696-1706`); receiver surfaces `payload.Timestamp` verbatim (`pubsub.go:1736`). DB orders by `timestamp …, id` (`group_messages_db_helpers.dart:172,212,248`). Forward skew > 5 min is already clamped (`handle_incoming_group_message_use_case.dart:1015-1029`); backward / within-window skew still reorders. |

## Root cause(s)

- **Render gap (items 1, 6):** view-state/result enums carry the information (`shouldShowCompactStatus`, `inboxStored`/`successNoPeers`), but the presentation layer drops it — the screen never reads `securityStatus`, and the wired layer collapses two send outcomes into one branch.
- **Missing scroll intent (items 2, 5):** the only scroll helper targets either the live edge (`jumpTo(0)`) or a preserved offset; there is no "scroll to a specific message" path, and explicit user sends are not treated as a "go to live edge" intent.
- **Locale-unaware formatting (item 3):** timestamps are formatted by hand instead of via `intl.DateFormat`, so locale (24h/12h, digit shaping) is ignored. The correct pattern already exists one file over.
- **No coalescing (item 4):** streams are wired 1:1 to a full reload with no debounce and no incremental per-group update path.
- **Trust in sender clock (item 7):** ordering anchors on the sender-supplied payload timestamp with `id` as the only tiebreaker; no receiver-side arrival anchor exists.

## Proposed improvements

### 1. Surface security warnings in-thread (high / security, effort medium)

Render a compact, tappable security banner in the conversation when `securityStatus.shouldShowCompactStatus` is true.

- In `group_conversation_screen.dart`, add a `_buildSecurityBanner(context)` widget inserted in the `Column` in `build()` (line 172-203) directly **under** `_buildHeader(context)` (insert after line 174, before the backlog/history banners), gated on `securityStatus != null && securityStatus!.shouldShowCompactStatus`.
- Content: a shield icon + `securityStatus!.compactEncryptionLabel(l10n)` and `securityStatus!.compactReviewLabel(l10n)` (both already exist, `group_security_status_view_state.dart:105-120`). Color **amber** when `hasIdentityWarnings || hasKeyChangeWarning` (reuse the warning palette already used by `_buildBacklogRetentionBanner`/`_buildHistoryGapRepairBanner`); use a neutral/muted tone for the "pending key" / unverified-only case so it is informational, not alarming.
- Make the banner tappable; `onTap` reuses the existing `onInfo` callback (already wired to `_onInfo` → `GroupInfoWired` at `group_conversation_wired.dart:3428-3450`), which opens Group Info where the full security card lives. No new navigation plumbing needed. (Optional follow-up: deep-link to the security card; out of scope for this item.)
- Add `key: const ValueKey('group-security-banner')` and a `Semantics` label combining the two strings for accessibility and widget tests.

No new strings required — all labels already exist (`group_security_compact_encrypted_epoch`, `group_security_members_need_review`, etc., confirmed in `app_en.arb:603-621`). No wired-layer change beyond what is already passed.

### 2. Scroll to the tapped message on notification open (medium / ux, effort medium)

Add a "scroll to message id" path in the wired layer and invoke it after initial load.

- Add `_scrollToHighlightedMessage()` in `group_conversation_wired.dart`. It computes the reversed-list index for `widget.initialHighlightedMessageId` (reverse list: `reverseIndex = _messages.length - 1 - chronologicalIndex`) and either uses `Scrollable.ensureVisible` on the row's context or, more robustly with `ListView.builder`, estimates an offset and `jumpTo`s, then re-runs `ensureVisible` once the target row is laid out. Wrap in `WidgetsBinding.instance.addPostFrameCallback`.
- Trigger it from `_loadMessages` success (`group_conversation_wired.dart:1095-1104`, alongside `_emitNotificationTapTimingIfNeeded()` at line 1104), **only** when `widget.initialHighlightedMessageId != null` and the id exists in `_messages`. If the id is not yet loaded (paged backlog), set a one-shot pending flag and retry after the next `_loadMessages`/page fetch completes; give up silently after a bounded number of attempts.
- Optionally clear the highlight after ~3s via a `Timer` so the `AnimatedContainer` (`group_conversation_screen.dart:620-632`) fades back; expose the cleared state through existing rebuild plumbing (the highlight is currently sourced from `widget.initialHighlightedMessageId`, so store a nullable local override in state and prefer it over the widget value when set).
- Add a `ValueKey('grp-scroll-target-${id}')` (or reuse `grp-msg-${id}` at `group_conversation_screen.dart:598`) so an integration harness can assert the row is visible.

### 3. Localize timestamps (medium / ux, effort small)

Replace both hand-rolled `_formatTime` methods with `intl.DateFormat.jm`.

- `group_conversation_screen.dart:766-774`: convert `_formatTime` from `static` to an instance method (it is called at line 566 within `build`, so `context` is available) and return `intl.DateFormat.jm(AppLocalizations.of(context)!.localeName).format(timestamp.toLocal())`. Pass `context` (or `localeName`) to the call site at line 566.
- `group_list_screen.dart:307-315`: same change; pass the active `localeName` (the screen already imports `AppLocalizations`).
- Import `package:intl/intl.dart as intl` (already the convention, per `pending_group_invite_card.dart`).

This makes 24h/12h selection and digit shaping follow the active locale automatically (`de` → 24h, `ar` → Eastern Arabic digits). No new strings. Add/adjust a `de`/`ar` golden or unit test asserting `DateFormat.jm('de')` produces 24-hour output.

### 4. Debounce + incremental update for the group list (medium / performance, effort medium)

Coalesce stream-driven reloads and stop doing full O(N) reloads on every message.

- In `group_list_wired.dart`, add a restartable `Timer? _reloadDebounce` and a `_scheduleReload()` that cancels and re-arms a ~200ms timer calling `_loadGroups()` once. Point the three stream listeners (`200-234`) at `_scheduleReload` instead of `(_) => _loadGroups()`. Cancel the timer in `dispose`.
- Incremental fast-path (preferred): the `groupMessageStream` event carries a `groupId`; update only that group's `_latestMessages[groupId]`/`_unreadCounts[groupId]` (two queries for one group) and bump it to the top, instead of re-querying every group. Keep the debounced full reload for join/pending-invite streams (membership changes) and as a periodic correctness backstop.
- Lifecycle resume (`didChangeAppLifecycleState`, `120-125`) should still do an immediate full reload (one-shot, not on the hot path).

No DB or repo signature changes are strictly required, though a future batched `getLatestMessagesForGroups(ids)` would let `_loadGroups` drop from 2N awaited queries to ~2.

### 5. Scroll own optimistic send into view (low / ux, effort small)

On a user-initiated send, always go to the live edge.

- Add a small `_scrollToLiveEdge()` helper (or call `_restoreScrollAfterMessageUpdate(preserveScrollOffset: false, previousOffset: 0)`, which already `jumpTo(0)`s, `group_conversation_wired.dart:2802-2804`).
- Call it in a post-frame callback right after `showOptimisticMessage()` (`1641-1651`). Because the user explicitly initiated the action, unlike incoming messages this should ignore `_shouldPreserveScrollOffset()`. The post-send upsert (`1837-1844`) does not need to re-scroll if the optimistic insert already moved the viewport.

### 6. Truthful indicator for no-peers sends (low → medium / observability, effort small for the minimum)

Surface the existing `inboxStored`/`successNoPeers` distinction so a queued send does not look like a live delivery. **Minimum, ship-now version:**

- In the wired send handlers, split the currently-merged branch (`group_conversation_wired.dart:1819-1821`, and the mirror in `_onRecordStop`): when `result == SendGroupMessageResult.successNoPeers`, persist/render the message with a distinct status that maps to the **already-localized** `message_status_pending_inbox` semantic (`app_en.arb:404`, `letter_card.dart:567`) and a non-failure glyph. Reuse the existing `'pending'` status (→ `Icons.schedule_rounded`, `letter_card.dart:531`) or add an `'inbox'`-flavored mapping; do **not** introduce a failure-looking state — custody is real.
- Keep DB persistence semantics intact (the row is genuinely `'sent'` with `inboxStored: true`); this is a presentation distinction. If a dedicated status string is preferred over reusing `'pending'`, gate it so legacy rows still render.

**Longer-term (out of scope for P2, noted for the backlog):** per-recipient delivery aggregation to drive a real `'delivered'` double-check.

### 7. (Optional) Receiver-side ordering anchor (low / correctness, effort small)

Only if bundling a Go change: emit an additive `receivedAtNano` (monotonic, receiver-side) alongside the existing sender timestamp in the `group_message:received` event (`pubsub.go:1736`), and have the timeline order by a stable `(timestamp, messageId)` tuple with receiver-arrival as the final tiebreaker. This is additive to the event payload (no envelope/wire-encryption change, no DB migration required if arrival is kept transient). Forward skew > 5 min is already clamped (`handle_incoming_group_message_use_case.dart:1015-1029`); this closes backward/within-window skew. **Defer unless a Go release is already going out.**

> Note on timeline reshuffle (related finding): `_loadMessages` sets `_messages` directly from `getMessagesPage` (chronological, `group_conversation_wired.dart:1095-1096`) while `_upsertMessage` runs `orderGroupMessagesForTimeline` (topological quote-threading, `group_message_ordering.dart:15-56`). To prevent the first incoming message from reshuffling rows, also apply `orderGroupMessagesForTimeline()` to the initial load result so initial and incremental orderings match. One-line change; safe to bundle with item 5.

## Affected files & components

| Item | Files |
|------|-------|
| 1 Security banner | `lib/features/groups/presentation/screens/group_conversation_screen.dart`; (read-only ref: `lib/features/groups/presentation/group_security_status_view_state.dart`) |
| 2 Scroll-to-message | `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart` |
| 3 Localized time | `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_list_screen.dart` |
| 4 Debounce/incremental list | `lib/features/groups/presentation/screens/group_list_wired.dart` (optional repo: `group_messages_db_helpers.dart` for a batched query) |
| 5 Optimistic scroll + initial ordering | `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/domain/utils/group_message_ordering.dart` (reuse only) |
| 6 No-peers indicator | `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart` |
| 7 (optional) ordering anchor | `go-mknoon/node/pubsub.go`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/domain/utils/group_message_ordering.dart` |

## Test & verification strategy

**Unit / widget (Flutter):**
- *Item 1:* widget test on `GroupConversationScreen` with a `securityStatus` whose `hasIdentityWarnings`/`hasKeyChangeWarning` is true → assert `ValueKey('group-security-banner')` present + amber + tappable; with `shouldShowCompactStatus == false` → assert absent.
- *Item 3:* unit/golden asserting `DateFormat.jm('de').format(...)` yields 24-hour (e.g. `14:05`) and `'ar'` yields Eastern Arabic digits; pump both screens under `de`/`ar` localizations.
- *Item 4:* fake streams emit a burst of N message events; assert `_loadGroups` (or the per-group query) runs once within the debounce window, not N times. Cover lifecycle-resume immediate reload.
- *Item 5:* with the list scrolled up, drive `_onSend`; assert the controller is at offset 0 after the post-frame callback. Plus a unit test that initial-load and post-incremental orderings are identical for a thread containing a non-adjacent quoted reply.
- *Item 6:* `LetterCard` test asserting a `successNoPeers`-derived status renders the inbox/clock glyph and `message_status_pending_inbox` semantic, distinct from a `'sent'` live delivery.

**Integration harnesses (`integration_test/`):**
- *Item 2:* extend a group conversation harness (e.g. `group_smoke_*_harness.dart`) to launch with `initialHighlightedMessageId` for an older message in a long thread and assert the target row is on-screen after load.
- *Item 4:* `benchmark_group_publish_harness.dart` / a list-focused harness to measure query count and frame jank during an offline catch-up burst before/after.
- *Item 1 / 6:* drive a two-device flow where one member's identity changes (banner) and a zero-peer send (inbox-only indicator) via the multi-device harnesses (`group_multi_device_real_harness.dart`).

**Locale + device matrix (`Test-Flight-Improv/`):**
- Add rows to the Group-Chat test matrices (`Test-Flight-Improv/Group-Chat-Feature/`, e.g. `04-ui-performance.md` for item 4, the C4-02/C4-03 send/receive matrices for items 5/6, and `52-notification-journey-test-matrix.md` for item 2) covering `en`/`de`/`ar` timestamp rendering, RTL banner layout, notification-tap scroll landing, and no-peers indicator. Run on the physical device matrix (iPhone13, Pixel6) given RTL + notification-tap behaviors are device-sensitive.

## Risks, trade-offs & rollout

- **Item 1 (banner):** risk of alarm fatigue / over-warning. Mitigate by reserving amber strictly for `hasIdentityWarnings || hasKeyChangeWarning` and using a muted tone for unverified-only / pending-key. Verify it does not overlap the existing backlog/history banners (stack order in the `Column`).
- **Item 2 (scroll):** `ListView.builder` doesn't lay out off-screen rows, so a single `ensureVisible` on a far row may miss; the offset-estimate-then-ensureVisible retry handles this. Guard against paged backlog (id not yet loaded) and against fighting the user if they scroll during the post-frame jump.
- **Item 3 (time format):** changing `static` → instance methods touches call sites; pure formatting change, low blast radius. Confirm `intl` data is initialized (it already is for `pending_group_invite_card`).
- **Item 4 (debounce):** ~200ms debounce adds slight latency to a single-message list update — acceptable and imperceptible; keep a correctness backstop full reload so incremental updates can't drift. The incremental path must handle group add/remove (fall back to full reload for membership streams).
- **Item 6 (no-peers):** must not look like a failure; reuse the existing non-alarming `pending`/inbox affordance. Persisted status stays `'sent'` so no data semantics change.
- **Item 7:** the only item with cross-stack surface; additive event field, no migration, but requires a Go build (`make all` + `pod install`). Defer unless a Go release is already shipping.

**Rollout:** ship as independent commits behind the same theme branch — items 3, 5, and 6-minimum are smallest and lowest-risk (land first); items 1, 2, 4 next; item 7 only with a Go release. No feature flags needed; each is reversible and UI-local. No wire-format or DB-migration changes (item 7's optional field is additive and transient).

## Effort estimate

| Item | Effort | Notes |
|------|--------|-------|
| 1 Security banner | Medium | New widget + theming + Semantics; reuses existing labels/nav |
| 2 Scroll-to-message | Medium | Robust ensureVisible-with-retry + paged-backlog guard |
| 3 Localized timestamps | Small | Two `_formatTime` replacements |
| 4 Debounce + incremental list | Medium | Debounce small; incremental per-group path is the bulk |
| 5 Optimistic scroll (+ initial ordering) | Small | One helper call + one-line ordering parity fix |
| 6 No-peers indicator (minimum) | Small | Branch split + reuse existing `pending_inbox` semantic |
| 7 Ordering anchor (optional) | Small (Dart) + Go build | Defer unless Go release pending |

**Theme total:** ~Medium. Recommended order: 3 → 5 → 6 → 1 → 2 → 4 → (7 if a Go release is in flight).
