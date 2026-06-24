# Flutter App Performance Report — Why It Feels Slow & Buggy, and How to Fix It

**Codebase:** ~221k LOC / 880 Dart files · NO state-management library (raw `setState` everywhere) · `compute()`/`Isolate.run` used **zero** times · crypto (ML-KEM/AES-GCM) via Go FFI bridge · encrypted SQLite (`sqflite_sqlcipher`) · 10 continuous `.repeat()` animations.

---

## Executive Summary

The app feels heavy for two independent reasons that compound: **the raster thread never rests, and the chat/feed screens redo too much work per interaction.**

In plain language:

1. **Everything is blurred over an animation that never stops.** Every chat bubble, the header, the composer, and the nav bar sit on top of a default background ("AmbientBackground") that runs an infinite 8-second glow loop on ~16 screens. Because `BackdropFilter` (Gaussian blur) re-samples whatever is painted behind it, the blur re-runs **every single frame even when you do nothing** — the device stays warm, scrolling never feels glassy, and the GPU has no spare budget when you actually do scroll. There is also **no `RepaintBoundary`** isolating the screen content from the glow, so the chrome repaints continuously too.

2. **Chats and the feed recompute their whole world on every event.** Opening a conversation, receiving a message, or reacting re-runs an O(N) "display grouping" pass over the *entire* (uncapped, ever-growing) message list — twice, with two `DateTime` parses and an `intl.DateFormat` allocation per message. After a notification tap, a relay drain replays M messages and each one fires its own whole-screen `setState`, so the cost is O(M×N). The home Feed compounds this with an unbounded N+1 query that decrypts **every message of every contact** on the UI isolate just to show preview rows.

**The 3–6 highest-leverage fixes (named):**

| # | Fix | Why it matters |
|---|-----|----------------|
| 1 | **`critic-1` — drop the per-bubble `BackdropFilter`**, replace with a semi-opaque solid fill | Removes 8–12 Gaussian-blur passes per scroll frame on the raster thread; bubbles are already 75–95% opaque so the visual loss is minimal. |
| 2 | **`navigation-hangs-1` / `rebuild-storms-1` — `RepaintBoundary`-isolate `child` in AmbientBackground** + honor reduce-motion app-wide | Stops the whole-screen-content repaint on every glow tick across every screen; mirrors the already-shipping `CosmicBackground` fix. |
| 3 | **`critic-2` — stop the ambient glow from animating at idle on chat surfaces** | Makes the always-mounted header/composer/nav-bar blur layers cacheable instead of re-rasterizing 60×/sec at rest. |
| 4 | **`main-isolate-blocking-1` / `rebuild-storms-2,3` — memoize `_buildDisplayItems` + coalesce the relay-drain burst** | Kills the O(M×N) rebuild storm on notif-tap and the per-interaction O(N) recompute in long chats. |
| 5 | **`db-persistence-1` / `db-persistence-2` — bound the Feed N+1 query + add a `(contact_peer_id, timestamp)` index** | Feed open stops decrypting entire conversation histories on the UI isolate; the hot message query stops doing a filesort. |
| 6 | **`images-media-1` — add `cacheWidth`/`cacheHeight` to `UserAvatar`/`GroupAvatar`** | Stops decoding 512px JPEGs into 36–100px circles app-wide; the most frequently rendered image in the app. |

---

## Quick Wins

Small effort, high (or broad) impact — ship these first.

| Change | File(s) | User-visible impact | Effort |
|--------|---------|--------------------|--------|
| Drop per-bubble Gaussian blur → semi-opaque fill (`critic-1`) | `letter_card.dart:712-715` (hot path; `:198` is dead legacy) | Smoother scroll in every chat; chat "feels light" | Small |
| Wrap `child` in `RepaintBoundary` in default ambient bg (`navigation-hangs-1`, `lists-scrolling-2`) | `ambient_background.dart:191` | Static chrome stops repainting every frame on all screens | Small |
| Add `cacheWidth`/`cacheHeight` to avatar `Image.memory`/`Image.file` (`images-media-1`) | `user_avatar.dart:119,144`; `group_avatar.dart:105,113` | Less scroll-in decode hitch; ~1MB→~63KB per avatar; fewer cache evictions | Small |
| Honor `MediaQuery.disableAnimations` app-wide in `_shouldAnimate` (`animations-repaint-4`) | `ambient_background.dart:116-120` | Reduce-Motion users get a static frame everywhere (today: feed only) | Small |
| Add composite index `(contact_peer_id, timestamp)` (`db-persistence-2`) | new migration 093; query at `messages_db_helpers.dart:114-131,166-171` | Faster chat/feed open as history grows; removes filesort | Small |
| Add `idx_group_messages_group_ts` (`db-persistence-5`) | new migration; `018_group_messages_tables.dart` | Faster feed open for multi-group users | Small |
| Memoize `RingAvatarGenerator.generate` (LRU) + add `==`/`hashCode` to data classes (`main-isolate-blocking-3`) | `ring_avatar.dart:34`; `ring_avatar_generator.dart:5-51` | Less scroll stutter/GC churn in photoless lists; stops needless re-raster | Small |
| Add one-shot sentinel to `scrubLegacyGroupSecretsToSecureStorage` (`cold-start-2`) | `legacy_group_secret_storage_scrub.dart:7-31` | Cold start stops double-scanning the encrypted DB every launch | Small |
| Build `Map<String,Message>` once, resolve quotes O(1) (`lists-scrolling-1`, `navigation-hangs-4`) | `conversation_screen.dart:498-500`; `group_conversation_screen.dart:930-933` | Removes O(N²) quote scan tail on long reply-heavy chats | Small |
| Gate `_resolveHydratedMediaForMessage` on actual media presence + dedup (`reactive-streams-2`) | `conversation_wired.dart:1523-1549,3806` | Text/status events stop hitting the attachments table; one fewer rebuild per incoming msg | Small |
| Set `kOrbit2/3PrototypeEnabled = kDebugMode` (`navigation-hangs-5`, `animations-repaint-3`) | `orbit2_prototype.dart:8`; `orbit3_prototype.dart:10` | Experimental constellation tabs (heavy blur animation) no longer reachable in release | Small |
| Allow `cacheWidth` for GIFs (drop `isGifImage ? null`) (`images-media-3`) | `media_thumbnail_image.dart:114-115` | GIF grid cells stop decoding full-res per frame | Small |

---

## Findings by Impact

### Critical

*No findings retain a critical adjusted severity. The two originally-critical Feed findings (`reactive-streams-1`, `db-persistence-1`) were corrected by the verifier — `reactive-streams-1` was **refuted** (status flips already use an in-memory patch path, not a full reload) and `db-persistence-1` was downgraded to **high**. Both are addressed under High below.*

### High

**Per-bubble `BackdropFilter` blur runs 8–12 Gaussian passes per scroll frame (`critic-1`)**
- **Symptom:** Scrolling any conversation stutters/drops frames; chat never feels light; worse with more scrollback. UI thread can be idle while the raster thread misses its 16ms budget.
- **Root cause:** Every message bubble wraps itself in `ClipRRect + BackdropFilter(ImageFilter.blur(sigma 24))` — a `saveLayer` + two-pass Gaussian blur sampling the (animating) backdrop. With ~8–12 bubbles visible, that's 8–12 blur passes/frame, and because the ambient glow behind them moves, the result can't be raster-cached even at rest.
- **Location:** `lib/features/conversation/presentation/widgets/letter_card.dart:712-715` (the live hot path; `:196-199` is the dead `bubbleLayout:false` legacy branch). Enabled by `conversation_screen.dart:585` and `group_conversation_screen.dart:665` (`bubbleLayout: true`).
- **Fix:** Replace `BackdropFilter` with a plain `DecoratedBox`/`Container` using a semi-opaque solid color (`readableColors.surfaceRaised`/`surfaceSubtle` already provide the tint); keep `ClipRRect` for corner clipping. If a frosted look is required, render **one** backdrop blur for the whole list region, not per row. Profile raster thread before/after with the DevTools timeline.
- **Effort / Risk:** Small / Low (visual-only, no state change).

**Always-mounted chrome blur re-runs over the 60fps-animating ambient background (`critic-2`)**
- **Symptom:** Chat and feed screens feel heavy and drain battery *even when idle*; device gets warm just sitting on a chat.
- **Root cause:** Header (`sigma 20`), composer (`sigma 20`), group panels (`sigma 12`/`30`), and nav bar (`sigma 28`) are all `BackdropFilter` layers mounted for the screen's lifetime, sitting in front of the animating `AmbientBackground` glows. A `BackdropFilter`'s input is the live backdrop, so an animating backdrop makes the blur un-cacheable — it re-executes every frame with zero user interaction.
- **Location:** `conversation_header.dart:34-36`, `compose_area.dart:312-314`, `group_compose_area.dart:102-103`, `group_name_panel.dart:40-41`, `feed_navigation_bar.dart:33-37`; backdrop = `ambient_background.dart:139-189`.
- **Fix:** Stop the ambient glow from animating while a chat surface is foregrounded — extend the chat/group call sites to pass `reduceMotion` (the feed already does this at `feed_screen.dart:187-190`), or gate `_shouldAnimate`. This makes the chrome blur inputs static and cacheable. **Do not** wrap the glows in a `RepaintBoundary` expecting it to help the blur — the backdrop content still changes every frame. Optionally lower sigmas / drop blur on chrome.
- **Effort / Risk:** Medium / Low.

**Default ambient background repaints the entire screen at 60fps (no `RepaintBoundary` around content) (`navigation-hangs-1`, `lists-scrolling-2`, `rebuild-storms-1`, `animations-repaint-1`)**
- **Symptom:** Nothing ever feels "light" — constant low-grade stutter, scroll never glassy, battery drain on every screen.
- **Root cause:** `_DefaultAmbientBackground` builds a `Stack` with two `AnimatedBuilder` glows **and** the screen `child` as a bare third sibling with no `RepaintBoundary`. The 8s `repeat()` marks the shared paint layer dirty every tick, re-recording the chrome's display list. `ListView.builder` rows have their own boundaries (spared), but header/composer/banners/empty states repaint continuously. `CosmicBackground` already does the right thing (`cosmic_background.dart:119,133`).
- **Location:** `ambient_background.dart:191` (bare `child`), `:45-52` (repeat), `:139-189` (glows). 16 call sites.
- **Fix:** Wrap `child` in `RepaintBoundary(child: child)` (mirror `cosmic_background.dart:133`); wrap each glow in its own `RepaintBoundary`; hoist the constant gradient `Container` out of the `AnimatedBuilder` via the `child:` param and animate only the `Positioned` offset (kills per-frame `Decoration`/shader allocation).
- **Effort / Risk:** Small / Low.

**Conversation recomputes full O(N) grouping + double `DateTime` parse on every build, over an uncapped list (`main-isolate-blocking-1`, `rebuild-storms-2`, `rebuild-storms-3`)**
- **Symptom:** Open a chat from a notification or background it, then receive a burst — the list hitches as messages "pop in"; the longer the thread, the worse each interaction feels. The core "interactions stutter inside chats" symptom.
- **Root cause:** `build() → _buildMessageList() → _buildDisplayItems()` runs **unconditionally** on every `setState`, doing two forward passes over the whole message list, **two** `DateTime` parses per message (`_formatDateLabel`→`DateTime.parse` at `:707/:937` AND `DateTime.tryParse` at `:717`), plus an `intl.DateFormat` allocation per older message, then `items.reversed.toList()`. The list is never trimmed (`_messages = [...olderMessages, ..._messages]`), so cost scales with thread length × scroll depth. During a relay drain each saved message fires its own whole-screen `setState` (no coalescing) → O(M×N).
- **Location:** `conversation_screen.dart:447,684-781,707,717`; `format_day_separator_label.dart:44`; fed by `conversation_wired.dart:4116-4121,1307`; `message_repository_impl.dart:141`. Mirror in `group_conversation_screen.dart:782`.
- **Fix:** (a) Memoize the `List<_DisplayItem>` keyed on `messages` length/first-id/last-id + relevant flags; recompute only in `didUpdateWidget` when the list actually changes. (b) Coalesce `messageChanges` into one per-frame flush via `SchedulerBinding.addPostFrameCallback` / a 16ms microtask so a drain of M rows triggers **one** rebuild. (c) Decouple the awaited `_resolveHydratedMediaForMessage` from the text upsert. (d) Cache parsed `DateTime` (and the `DateFormat` per locale) — ideally parse once at ingest onto `ConversationMessage`. (e) Cap the in-memory window (~300 messages) with older-page eviction.
- **Effort / Risk:** Medium / Low (the grouping pass is pure given its inputs).

**Feed N+1 loads the ENTIRE conversation history per contact (no LIMIT), SQLCipher-decrypted on the UI isolate (`db-persistence-1`)**
- **Symptom:** Feed/home tab is slow to open and stutters on launch and on return; the more and longer your conversations, the longer the freeze before the list appears.
- **Root cause:** `loadContactFeedItems` loops every active contact calling unbounded `getMessagesForContact` → `dbLoadMessagesForContact` (`db.query('messages', ... orderBy timestamp ASC)` with **no limit**). Every row is decrypted and rebuilt via `ConversationMessage.fromMap` on the root isolate (no `compute`/isolate offload anywhere). Cost is O(contacts × messages/contact), per feed mount.
- **Location:** `load_feed_use_case.dart:35-38`; `messages_db_helpers.dart:151-188`; `message_repository_impl.dart:153-160`; `feed_wired.dart:374,470-479,603`.
- **Fix:** For the preview row, replace the per-contact loop with a single `getConversationThreadSummaries(allContactPeerIds)` (already exists, `message_repository_impl.dart:455`, used by orbit). **Caveat:** `ThreadFeedItem.messages` carries the full per-thread list consumed by the in-feed focused thread view and reaction loading — so lazy-load full messages on thread *focus* (or a capped `getMessagesPage`) rather than dropping them entirely.
- **Effort / Risk:** Medium / Low–Medium (model/UI change, not a one-line LIMIT).

**Missing composite/covering index on the hot message query (`db-persistence-2`)**
- **Symptom:** Opening a chat and the feed get progressively slower as history grows; first frame of a busy conversation lags.
- **Root cause:** Every load filters `contact_peer_id = ? AND hidden_at IS NULL ORDER BY timestamp`, but only single-column `idx_messages_contact` and `idx_messages_ts` exist (plus a 3-col unread index that can't satisfy the order-by). SQLite seeks the contact's rows, then does a residual `hidden_at` filter and a separate filesort — each touched page decrypted by SQLCipher. The unbounded feed query (`db-persistence-1`) amplifies this.
- **Location:** `002_messages_table.dart:21,26`; `006_read_at_column.dart:48-49`; query `messages_db_helpers.dart:114-131,166-171`.
- **Fix:** Ship migration 093: `CREATE INDEX IF NOT EXISTS idx_messages_contact_ts ON messages(contact_peer_id, timestamp)` (optionally partial `WHERE hidden_at IS NULL`). Online, idempotent, no data change. Verify with `EXPLAIN QUERY PLAN`.
- **Effort / Risk:** Small / Low.

**Avatars decode at full 512px into 36–100px targets (no `cacheWidth`/`cacheHeight`) (`images-media-1`)**
- **Symptom:** Lists/chats/orbit stutter on first paint and on scroll-back; memory grows; re-navigation re-janks as oversized bitmaps get evicted and re-decoded.
- **Root cause:** `UserAvatar` and `GroupAvatar` pass only logical `width`/`height`, never `cacheWidth`/`cacheHeight`, so the engine decodes the ≥512px JPEG to a ~1MB RGBA bitmap per avatar and uploads a full-size texture for a tiny circle. The media layer already knows the fix (`media_grid_cell.dart:234` uses `cacheWidth: 400`). Orbit places dozens at once.
- **Location:** `user_avatar.dart:119-126,144-152`; `group_avatar.dart:105-112,113-120`; source floor `image_processor.dart:67-79`.
- **Fix:** `final dpr = MediaQuery.devicePixelRatioOf(context); cacheWidth: (size*dpr).round(), cacheHeight: (size*dpr).round()` on all four photo branches. Keep GIFs unscaled (follow `media_thumbnail_image.dart:114-115`). Keys unchanged, so cache-bust still works. Optionally lower `processAvatar` to ~256px.
- **Effort / Risk:** Small / Low.

### Medium

**FeedWired rebuilds the full Orbit + Feed trees on every tab-switch `setState` (`navigation-hangs-2`)**
- **Symptom:** Switching/swiping between Feed and Orbit stutters, especially with many contacts/groups.
- **Root cause:** On the tab-switch commit (`switchTo → notifyListeners → _onShellChanged → setState`), `build()` allocates a brand-new `FeedScreen` (~40 params) and `OrbitWired` (~45 params), neither memoized, forcing a one-time reconcile of both subtrees. `setBackgroundPreference` triggers the same even when only the background changed. *(The verifier refuted the "per-frame during swipe" claim — `feedBody`/`orbitBody` are built once and referenced inside the `AnimatedBuilder` closure, so the swipe itself is cheap.)*
- **Location:** `feed_wired.dart:2182-2195` (`_onShellChanged`→setState), `:2356` (new FeedScreen), `:2205-2250` (new OrbitWired), `:2400-2431` (AnimatedBuilder ignores `child:`); `app_shell_controller.dart:22-35`.
- **Fix:** Hoist pre-built panes into the `AnimatedBuilder`'s `child:` param; wrap each pane in `RepaintBoundary`; narrow `_onShellChanged` so background-only notifications don't `setState` the whole shell; optionally memoize the two pane instances in fields.
- **Effort / Risk:** Medium / Low.

**Conversation subscribes to BOTH the live and durable streams for the same incoming message (`reactive-streams-2`)**
- **Symptom:** Redundant work on every incoming message — two full-list rebuilds + an extra encrypted-DB attachments query, amplified under bursts. *(Verifier refuted the "visible double-render" claim — both paths converge on `_upsertMessageById` which replaces in place.)*
- **Root cause:** The 131 reliability fix widened the `messageChanges` filter to accept incoming inserts (`:1518`); the screen also listens to `incomingMessageStream`. One live message fires both, and the repo-change path runs an awaited `_resolveHydratedMediaForMessage` (a `getAttachmentsForMessage` read) unconditionally — even for text/status-only events.
- **Location:** `conversation_wired.dart:1480-1500,1502-1558,3806`.
- **Fix:** Short-circuit the `messageChanges` handler when `message.isIncoming && alreadyShown` (already computed at `:1526`); guard the media resolve on actual media presence. **Keep both streams** (dropping `incomingMessageStream` risks a 131-class reliability regression).
- **Effort / Risk:** Small–Medium / Low.

**Orbit tab stays mounted alongside Feed and stays fully reactive off-screen (`reactive-streams-3`, `animations-repaint-2`)**
- **Symptom:** Sluggishness that worsens after you've opened the Orbit tab once — both Feed and Orbit do reloads on the same background events, and two ambient loops run forever in parallel.
- **Root cause:** `_hasMountedOrbitHost` latches `true` and never resets; the off-screen tab is only `Transform.translate`d (which does **not** mute tickers — only `Offstage`/`TickerMode`/dispose do). `OrbitWired`'s intro/group/**chat** subscriptions stay live; `_onAppShellChanged` only `setState`s, never pauses. *(Verifier corrections: the heavy `_loadOrbitData` is only the error fallback — handlers call lighter single-entity refreshes; there is no orbit empty-state pulse; the dup is two ambient loops, not three animations.)*
- **Location:** `feed_wired.dart:2007-2013,2191-2192,2386-2426`; `orbit_wired.dart:407-447,866-935`.
- **Fix:** Wrap each tab body in `TickerMode(enabled: thisTabActive && !midSwipe)` (or `Offstage` the inactive side at rest) to pause the inactive ambient loop; gate the off-screen orbit subscriptions on `activeTab` via pause/resume or a single dirty-flag + coalesced reload on re-activation (include the higher-frequency chat-message subscription).
- **Effort / Risk:** Medium / Low.

**Per-message-event feed refresh re-reads the whole conversation (`db-persistence-3`, partial `reactive-streams-1`)**
- **Symptom:** While sitting on the feed, deletes/hides and **every inline reply sent from the feed** cause brief stutters. *(Verifier: status flips already use the in-memory patch path — the genuine full-reload trigger is send-from-feed at `feed_wired.dart:1800`, plus delete/hide/archived/error branches.)*
- **Root cause:** `loadContactFeedSnapshot → loadConversation → getMessagesForContact` is the same unbounded read as `db-persistence-1`.
- **Location:** `load_contact_feed_snapshot_use_case.dart:28`; `load_conversation_use_case.dart:27`; `feed_wired.dart:630,1800,1241-1248,950,961,1005`.
- **Fix:** For send-success, merge the just-sent message incrementally (no DB re-read). For delete/hide, back the snapshot with `loadConversationPage(pageSize ~30-50)` instead of unbounded `loadConversation`. **Do not** use the single-row summary here — it breaks `ThreadFeedItem.hasReply`/multi-message preview semantics.
- **Effort / Risk:** Medium / Low–Medium.

**Group feed loads up to 200 messages/group with no composite index + non-sargable `id NOT LIKE` (`db-persistence-5`)**
- **Symptom:** Feed open is slower when you belong to several groups; group previews lag first paint.
- **Root cause:** `limit:200` per group, only single-column indices, an `id NOT LIKE 'sys-member_removed_cutoff:%'` filter that can't use an index, and a secondary `id DESC` sort. Each row SQLCipher-decrypted on the UI isolate.
- **Location:** `load_feed_use_case.dart:96-100`; `group_messages_db_helpers.dart:168-175`; `018_group_messages_tables.dart:35,40`.
- **Fix:** Add `idx_group_messages_group_ts ON group_messages(group_id, timestamp)`; replace the per-group `limit:200` loop with a batched group-summary query modeled on `dbLoadConversationThreadSummaries`. **Do not** naively drop to limit-1 — it breaks unread counts (`group_group_messages_into_threads.dart` scans all returned rows).
- **Effort / Risk:** Medium / Low.

**`intl.DateFormat` constructed per visible chat row every build (`lists-scrolling-3`)**
- **Symptom:** Constant per-frame overhead building chat rows; worse under fast scroll. (Microsecond-scale across ~5–15 visible rows — bundle with other per-build reductions, not a standalone fix.)
- **Root cause:** `_formatTime` does `DateTime.parse` (1:1 only) + `Localizations.localeOf` + `intl.DateFormat.jm(locale)` per row inside the itemBuilder.
- **Location:** `conversation_screen.dart:579,952-960`; `group_conversation_screen.dart:663,1051-1054`.
- **Fix:** Hoist a single per-locale memoized `DateFormat` in `_buildMessageList` and pass the formatter (or pre-formatted string) into the row; reuse the `DateTime` already parsed in `_buildDisplayItems`.
- **Effort / Risk:** Small / Low.

**Row materialization + media path resolution run on the UI isolate (`db-persistence-7`)**
- **Symptom:** Feed paint stalls turning decrypted rows into Dart objects and resolving attachment paths synchronously relative to the frame. *(Verifier: the central "make resolveStoredPath sync" premise is partly wrong — `resolveStoredPath` awaits a `path_provider` channel hop, but a sync twin **already exists**.)*
- **Root cause:** `loadContactFeedItems` awaits `mediaFileManager.resolveStoredPath` inside a nested loop (a platform-channel hop per attachment, serializing the loop), then maps via `copyWith`, then groups.
- **Location:** `load_feed_use_case.dart:48-61,71-75`; `load_conversation_use_case.dart:95-107`; `message_repository_impl.dart:157-158,507-511`; sync twin `media_file_manager.dart:56`.
- **Fix:** Swap the awaited loops to the existing `resolveStoredPathSync` (startup-seeded docs dir); debounce/coalesce the stream-driven full reloads. **Do not** move `fromMap`/grouping to an isolate — the cost is the serialized async chain, not CPU, and isolate transfer of these objects isn't cheap.
- **Effort / Risk:** Medium / Low.

**First open of a conversation entrance-animates every visible row with its own controller (`lists-scrolling-4`)**
- **Symptom:** The reveal frame after tapping into a chat (the high-attention moment) janks as the list entrance-animates. *(Verifier: 1:1 only; `AnimatedBuilder` caches the child subtree so the cost is N controllers + Opacity/Transform compositing, not full rebuilds; fires on the async reveal frame, not literally the first frame.)*
- **Root cause:** `shouldAnimate = !widget.initialLoadDone || isNew` wraps **every** initial row in `_AnimatedLetterCard` (own `AnimationController`, 3 Tweens, Opacity + double Transform).
- **Location:** `conversation_screen.dart:646`, `_AnimatedLetterCardState:1103-1158`.
- **Fix:** Change to `shouldAnimate = isNew` so only appended messages animate; if a first-paint fade is wanted, use one `FadeTransition` for the whole list; avoid `Transform.scale` (forces a layer).
- **Effort / Risk:** Medium / Low.

**Cold-start work awaited before `runApp()` (`cold-start-1`, `cold-start-2`, `main-isolate-blocking-2`)**
- **Symptom:** Black/splash screen lingers on every cold open; cold start gets slower as media/group-key history accumulates.
- **Root cause:** On normal launch, `await startLiveServices()` (Firebase wait + notification-plugin init = 3 `MethodChannel` round-trips + ~25 listener starts) runs before `runApp` — even though share-launch already proves it's safely deferrable via `deferredRuntimeStartup`. Separately, `scrubLegacyGroupSecretsToSecureStorage` has **no sentinel**, so it re-scans two encrypted tables every launch (the `WHERE NOT NULL` filters still match migrated `secure:`-prefixed rows). *(Verifier: `bridge.initialize` is cheap, not a heavy round-trip; `ensureFirebaseReady` is also awaited separately at `:389` and must be moved too; magnitudes are tens of ms, not the full stall implied.)*
- **Location:** `main.dart:3080-3082,3090,389-393`; `flutter_notification_service.dart:39-44`; `legacy_group_secret_storage_scrub.dart:7-31,41-45,80-84`.
- **Fix:** (a) Always pass `startLiveServices` as `deferredRuntimeStartup` (drop the `isShareLaunch` special-case); move `notificationService.initialize()` post-frame (already gated behind `_handleInitialLocalNotificationLaunchWhenReady`); to actually get Firebase off the critical path also move the `:389` `ensureFirebaseReady`. (b) Add a one-shot sentinel `if (await secureKeyStore.containsKey('legacy_group_secrets_scrubbed')) return;` (mirror `migrate_secrets_to_secure_storage.dart:23`); the real prefix is `secure:` (not `secureref:`). Measure with the existing `StartupTiming` marks.
- **Effort / Risk:** Medium (defer) + Small (sentinel) / Low.

---

## Cross-Cutting Recommendations

These are systemic patterns that recur across many findings — fixing the pattern is higher-leverage than each instance.

- **A `RepaintBoundary`-around-animations policy.** Every always-on animated surface (`AmbientBackground`, `EmptyCircleState`, Orbit prototypes) must isolate its animated layer **and** its static content into separate `RepaintBoundary`s, the way `CosmicBackground`/`daylight_lagoon_background` already do. Make this a lint/review checklist item: any `.repeat()` controller driving a sibling of screen content is a bug.

- **A "blur is expensive — prove you need it" rule.** `BackdropFilter` is the single most expensive primitive in this app and it's applied per-bubble plus on every chrome layer, over an animating backdrop. Default to a semi-opaque solid fill; reserve `BackdropFilter` for at most one full-region layer, and never place one in front of a continuously animating backdrop.

- **App-wide reduce-motion + lifecycle gating for continuous animations.** Drive `_shouldAnimate` off `MediaQuery.disableAnimations`/`accessibleNavigation` on **all** surfaces (today: feed only), and `TickerMode`-freeze off-screen tabs in the dual-mounted shell. (Note: app-background and route-occlusion are already handled by the framework — don't add redundant `WidgetsBindingObserver` plumbing per `reactive-streams-5`.)

- **A granular-rebuild discipline to replace broad `setState`.** With no state-management library, the pattern that works (already used well for the voice-amplitude path via `ValueNotifier`/`ValueListenableBuilder`) should be extended: memoize derived view-models (`_buildDisplayItems`), key recomputation on input identity, and move volatile non-list state below a boundary so a `_isSending` flip doesn't re-run the whole list pass.

- **A stream coalescing layer.** There is no debounce/throttle anywhere on reactive paths. Introduce a per-frame flush (microtask / `addPostFrameCallback`) or short trailing debounce between the per-row repository change stream and UI `setState`, so a relay drain of M messages produces one rebuild, not M.

- **A list-virtualization + `cacheWidth` standard.** Bound in-memory message windows (cap + evict), always pass `cacheWidth`/`cacheHeight` sized to display pixels on every `Image.*`, and prefer lazy `ListView.builder`/`SliverList` everywhere. The feed slivers and media grid already set the bar; avatars and chat lists need to meet it.

- **DB indexing + query-bounding standard.** Every hot `WHERE … ORDER BY …` needs a covering composite index; every list query needs a `LIMIT`/page; avoid non-sargable predicates (`id NOT LIKE`). N+1 contact/group loops should become single batched summary queries. (Crypto offload is **not** needed — the Go bridge already runs ML-KEM/AES-GCM off the platform main thread and passes file paths, not bytes; `compute()`/`Isolate.run` is the wrong tool here. The real DB cost is row volume + missing indices + UI-isolate `fromMap`, not crypto.)

---

## Suggested Roadmap

### Phase 1 — Quick Wins (this week, mostly small/low-risk)
- `critic-1` (drop per-bubble blur), `navigation-hangs-1`/`lists-scrolling-2` (`RepaintBoundary` + gradient hoist), `animations-repaint-4` (reduce-motion app-wide)
- `images-media-1`, `images-media-2`, `images-media-3` (avatar + GIF `cacheWidth`)
- `db-persistence-2`, `db-persistence-5` (add composite indices — migrations 093/094)
- `main-isolate-blocking-3` (RingAvatar memoize + `==`), `lists-scrolling-1`/`navigation-hangs-4` (quote map), `lists-scrolling-3` (DateFormat hoist)
- `cold-start-2` (scrub sentinel), `reactive-streams-2` (dedup + media-presence guard), `lists-scrolling-4` (entrance animation → `isNew` only)
- `navigation-hangs-5`/`animations-repaint-3` (gate prototype flags to `kDebugMode`)

### Phase 2 — Structural (next, medium effort)
- `critic-2` (stop idle ambient animation on chat surfaces — unblocks chrome-blur caching)
- `main-isolate-blocking-1`/`rebuild-storms-2`/`rebuild-storms-3` (memoize `_buildDisplayItems` + coalesce drain burst + cache timestamps + cap window)
- `db-persistence-1` + `db-persistence-3` (bound the Feed N+1 → summary query + lazy thread load; bound the per-event refresh)
- `navigation-hangs-2` (hoist panes into `AnimatedBuilder.child` + pane `RepaintBoundary`s)
- `reactive-streams-3`/`animations-repaint-2` (`TickerMode`-freeze + pause off-screen orbit subscriptions)
- `cold-start-1`/`main-isolate-blocking-2` (defer `startLiveServices` + Firebase + notification init on normal launch)
- `db-persistence-7` (swap to `resolveStoredPathSync` + debounce feed reloads)

### Phase 3 — Deeper (later, larger or lower-leverage)
- `cold-start-4` (re-stage DI so a minimal shell paints before the heavy graph — large refactor; verifier notes construction is cheap, so prioritize the deferral above over lazy DI)
- `cold-start-3` (incremental iOS keychain mirroring + post-frame), `cold-start-5` (parallelize the two independent launch probes)
- `db-persistence-6` (contacts/groups indices — low value, social-graph-bounded)
- `animations-repaint-5` (EmptyCircleState reduce-motion gate — only call sites already wrap it in `RepaintBoundary`+`TickerMode`), `reactive-streams-4` (centralize `_stateMeaningfullyChanged`)

---

## Appendix: Not Acted On

Findings the verifier marked **refuted**, **already-mitigated**, or **off-hot-path** — listed for transparency.

- **`reactive-streams-1`** (orig. *critical*, "Feed reloads the entire conversation on every status flip") — **Refuted.** Normal incoming + sent/delivered/failed flips route to `_applyIncomingContactMessageToFeed` (in-memory merge, `refreshUnreadCount:false`); the full reload only fires on delete/hide/archived/error. Residual cost is covered by `db-persistence-1`/`db-persistence-3`.
- **`db-persistence-4`** (orig. *high*, "no WAL → 5s reader-vs-writer hang") — **Refuted.** `sqflite` uses a single serialized native connection; all reads and writes share one Dart-level FIFO mutex and never hit the rollback-journal exclusive lock. WAL would not fix the claimed hang.
- **`critic-3`** (orig. *medium*, "first-open blur shader-compile stutter") — **Refuted.** Flutter 3.41.4 with Impeller default-enabled (no `FLTDisableImpeller`) precompiles pipelines; the legacy SkSL first-use compile jank doesn't apply. Steady-state blur cost is covered by `critic-1`/`critic-2`.
- **`lists-scrolling-6`** (orig. *low*, "group list uses eager `ListView`") — **Refuted / off-hot-path.** `GroupListWired`/`GroupListScreen` are not mounted in the live `new-feed` app (no route from `main.dart`/`StartupRouter`; test-only references). The 134/135 Feed redesign replaced the old group-list tab.
- **`reactive-streams-4`** (orig. *low*, node-state stream no `distinct`) — **Off-hot-path.** All high-frequency callers already pre-gate with `_stateMeaningfullyChanged`; the sole UI subscriber dedupes; emits at 30s-poll / connect / push cadence, never per-frame.
- **`reactive-streams-5`** (orig. *low*, ambient loop not paused on background/off-screen) — **Refuted.** Framework already mutes the ticker for routes covered by opaque `MaterialPageRoute` and suspends frames when backgrounded; proposed lifecycle plumbing is redundant.
- **`navigation-hangs-5`** (orig. *low*, prototypes shipped on) — **Off-hot-path** (kept as Phase 1 hygiene). Orbit2/3 are only mounted when the user manually selects an experimental tab (default tab is feed) and dispose on leaving; zero launch/feed/orbit/scroll cost.
- **`main-isolate-blocking-4`** / **`images-media-2`** (own-avatar full-res decode in settings/profile) — **Off-hot-path** (folded into the `images-media-1` change). Single-instance, off-isolate decode on an infrequently-visited screen; memory-footprint polish, not a frame-stall.
- **`cold-start-3`** (iOS keychain mirroring every launch) — Confirmed but downgraded to **low** (iOS-only, launch-only, dominated by reads/skips; unrelated to navigation jank). Addressed in Phase 3.
- **`cold-start-4`** (synchronous DI graph before `runApp`) — Construction confirmed but the **causal jank claim is largely refuted**: AOT object allocation is sub-ms; the real pre-frame cost is the awaited startup (`cold-start-1`), so prioritize deferral over lazy DI.
- **`cold-start-5`** (three serial launch probes) — Confirmed but **low**: 2–3 `MethodChannel` round-trips, sub-ms to low-ms; only the share-probe + docs-dir are safely parallelizable (Firebase must stay gated behind `!isShareLaunch`).
- **`animations-repaint-5`** (EmptyCircleState pulse) — Confirmed code but **off-hot-path**: it's the onboarding/QR screen (not the orbit tab), and both call sites already wrap it in `RepaintBoundary`+`TickerMode`. Only the unconditional `..repeat()` reduce-motion gate remains, low value.
