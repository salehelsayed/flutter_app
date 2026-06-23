# 134 - Feed Redesign: "Letters" Pending-Reply Inbox  (New Feature / Full Replacement)

Status: awaiting-review
Spec: free-text intent — the user-provided **mknoon Feed redesign spec** (§1–§10), six screenshots, and the locked product decisions captured below. No formal `Test-Flight-Improv/NN-*.md` spec doc; this plan IS the source-verified design.

Branch context: `new-feed`. Grounding artifact (6 graphify-explorer slices + critic, full `file:line` map of the current Feed vs every spec section): `/private/tmp/claude-501/-Users-I560101-Project-Sat-mknoon-2-flutter-app/3efd853b-e6e4-4f4f-a839-b5371dd44b8c/tasks/wflv8hnt7.output`.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-20 | Evidence Collector | feed_item.dart, feed_screen.dart, feed_wired.dart, load_feed_use_case.dart, ring_avatar_generator.dart, ring_avatar_spec.dart, feed_colors.dart, background_readable_colors.dart, scrollable_message_preview.dart, message_bubble.dart, connection_card.dart, all feed widget/tests (via 6-slice graphify workflow + critic) | Current feed is real-data "Feed Live 2" — inverts the spec's mental model; RingAvatar+djb2 already exist (huge reuse) | Lock product forks (done) |
| 2026-06-20 | Planner | tier-matrix.md, plan-template.md, run_test_gates.sh (FEED family), migrations/ (max 091) | Host-closable; new migration 092 (DB v92); 4 product decisions locked by user | Emit matrix + RED catalog |
| 2026-06-20 | Reviewer (sufficiency) | this doc vs sufficiency-checklist.md (workflow wf_b807a834-d4c: 3 reviewers + arbiter) | draft-needs-fixes → all 7 blocking + 12 recommended fixes applied | re-verify totality |
| 2026-06-20 | Arbiter | revised doc | no structural blockers; deferred = design hexes + external-routing behavioral test | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | | RED for expected reason | |
| | implementation (P0→P8) | | | scoped files only | |
| | direct GREEN | | | reds now green | |
| | preservation GREEN | | | sentinels green | |
| | named gates | | `./scripts/run_test_gates.sh feed` | gate green | |
| | QA (independent) | | | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline below (the mknoon Feed redesign spec §1–§10 + screenshots) + the 4 locked product decisions.
- Gate definitions: `scripts/run_test_gates.sh` — **`FEED_TESTS` array (lines 62-66) must be updated** (it currently lists three tests this plan deletes).
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no new simulator scenario — host-closable).
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (next-free **134**); migrations max **091** → next-free **092** (DB **v92**).

## Session Classification
**implementation-ready** — host-closable (pure-domain projection + real-SQLCipher migration + widget/gesture tests). No ML-KEM / relay / multi-device crypto → **no device-proof is the closure gate**. On-device motion/gesture smoke is an *optional* polish pass, not a gate (see Device/Relay Proof Profile).

---

## Exact Problem Statement

The current Feed (`lib/features/feed/`, "Feed Live 2") is a **real-data chat-log surface**: it shows every active contact + every thread regardless of state, partitioned into "unread/active" above a `SessionDivider` and "replied/read" below it, with per-message timestamps, delivery-status ticks, "(edited)", unread-count pills, "You replied <time>", quote previews, time-gap dividers, "View earlier messages", `maxPreview=3` windowing, and a **composer embedded in every card**. (`feed_screen.dart:322-386`, `feed_item.dart:9-21`, `message_bubble.dart:302-337`, `collapsed_mode_card_body.dart:167-216`, `open_mode_card_body.dart:165-166`.)

The redesign **inverts the mental model** to a **pending-reply inbox**: the Feed shows *only* messages waiting on the user; replying to or dismissing a card **removes it** so the screen visibly empties to "You're all caught up"; history lives only in the conversation view. Cards show **only incoming content + sender identity** (no timestamps, receipts, "you replied", unread counts). There is **one shared composer** that appears only while a card is focused and *appends* outgoing green bubbles while staying open. Swipe-right commits & clears; swipe-left dismisses (with Undo). Bubbles use a single tokenized container with four role fills; identity is a deterministic `RingAvatar` glyph + a per-sender accent hue. (Spec §1–§10; screenshots confirm the focused state adds an **"Open full conversation ↗"** link above the composer.)

**Who experiences it / why it matters:** every user on every app open. The current surface is information-dense and never "completes"; the redesign makes the Feed an actionable, self-emptying inbox. Because the app is wired to **real DB data** (not the spec's React demo letters), the redesign must keep the real-data sourcing and layer a pending-only projection + a new "cleared" persistence on top of it, without regressing send-truthfulness, the Orbit screen, or the app-wide unread badge.

**What must improve:** the entire Feed presentation + interaction model (§1–§8) + token foundation (§9) + reduced-motion (§7).

**What must stay unchanged (→ preserved-green sentinels):**
- Conversation view (`ConversationWired`/`GroupConversationWired`) and its composer/`QuotePreviewBar` (`compose_area.dart:323`) — reactions/edit/delete/copy move *here*.
- Orbit screen widgets that share `UnreadCountBadge` (`friend_row.dart:145`, `group_row.dart:203`) — remove **feed usages only**, never the widget file.
- The **3** external `FeedWired` instantiation sites (verified by `grep 'FeedWired('`: `startup_router.dart:341`, `qr_scanner_wired.dart:383`, `first_time_experience_wired.dart:242`) + posts/share machinery threaded through `FeedWired`. (`share_intent_service.dart` and `main.dart` mention `FeedWired` only in **comments** — doc-touch-up at most, not a contract migration.)
- The app-wide unread badge (`_totalUnreadCountNotifier`) and Orbit badge (`_orbitBadgeCountNotifier`) semantics — a **dismiss must not change them** (decision 2).
- Global `glowColorForPeerId` (70/50) used by `user_avatar.dart:173`, `connection_card.dart:227` and other screens — untouched.

## Root Cause (verify → refute confirmed)
Not a bug — a redesign. The "findings" are **current-state facts**, each verified with `file:line` by the 6-slice graphify map and cross-checked by the critic pass. Highlights that survived adversarial review:
- **`RingAvatar` + `djb2` already exist and match §4** — `ring_avatar_generator.dart:93-100` (djb2, seed 5381, 32-bit) and `glowColorForPeerId` `:202-211` (`hue=(hash>>16)%360`, HSL). 4-ring `CustomPainter` accepts any size (`ring_avatar.dart:18-45`, `ring_avatar_painter.dart`). Only the **saturation/luminance differ**: `RingAvatarConstants.glowSaturation=70 / glowLuminance=50` (`ring_avatar_spec.dart:95-98`) vs spec **72/67**. → reuse djb2, add a feed-local 72/67 accent helper.
- **The pending-reply model has NO persistence analog** — `loadFeed` returns all contacts + all threads sorted by timestamp, no filter (`load_feed_use_case.dart:142-157`); `FeedStore` is upsert-only (`feed_store.dart:71-97`); the only "remove" levers are read-marking (ripples into Orbit + badge) or account archive (too heavy). → **new feed-only `cleared` table + migration 092** (decision 2).
- **`BackgroundReadableColors` ThemeExtension** already exposes `surfaceSubtle/surfaceRaised/border/textPrimary/textSecondary/textMuted` (`background_readable_colors.dart:16-31`) — map directly; only teal/green/blur/radius/space/typography tokens are net-new.

**Refuted / do-NOT-re-introduce (investigated, deliberately not planned):**
- A per-letter `{rtl?}` *model field* (spec §2) — **refuted as redundant**: `detectTextDirection` (`text_direction_utils.dart:8`) already derives direction per string at render (`message_bubble.dart:266`). Plan keeps render-derived RTL; **do not add a dead `rtl` field**.
- Changing global `glowColorForPeerId` to 72/67 — **refuted**: would ripple the avatar-glow hue into Orbit/profile/connection screens. Add a *separate* feed accent helper instead.
- "Replay demo letters" reset (§6) — **refuted for production**: the feed is real-data; no demo source exists. Out of scope (dev-only at most).
- Reusing `CheckmarkBurstAnimation`/`ExpandedComposeInput`/`MessageFeedItem`/`connectedVia` — **dead code** today; do not build on them.

## Real Scope
**In scope (full replacement of `lib/features/feed/` presentation + domain projection):**
1. **Tokens (§9):** new `FeedTokens` `ThemeExtension` (+ `AppText`/`AppSpace` const, `NavBarTheme` precedent). Delete `FeedColors` after migrating its 19 feed call sites.
2. **Identity (§4):** `accentColorForPeerId(peerId)` = djb2 → `hsl(hue,72%,67%)` (reusing `djb2Hash`); wire `RingAvatar` into feed at sizes 40/32/30(/32 composer); sender-name accent.
3. **Bubble (§3):** one tokenized `LetterBubble` widget, four role fills, focused teal-glow, `BackdropFilter` blur, no timestamp/status/edited/unread chrome.
4. **Letter shapes + card anatomy (§2/§5):** pending-only view-models (1:1 single/stacked, group per-sender runs, system connection/introduction); 1:1 (avatar40, no header), group (per-run avatar32 + accent label, no cap), system (avatar40 + muted label + green "tap to say hi" bubble).
5. **Projection + persistence (§1, decision 2):** pending-only filter over the existing real-data sourcing; **migration 092 `feed_cleared_threads`** + `FeedClearedRepository`; cleared-watermark filter + re-surface on new incoming; ordered store supporting remove + Undo re-insert-at-index.
6. **Interactions (§6):** focus→collapse-others + single shared composer (append-green-bubble-stay-open, dynamic verb, "Open full conversation ↗") + `Dismissible` swipe-right commit / swipe-left dismiss + Undo SnackBar + gesture gating + "You're all caught up" empty state.
7. **Send-truthfulness (decision 4):** non-tick "tap to retry" affordance for failed/pending outgoing replies — keyed on **`SendChatMessageResult`** (`send_chat_message_use_case.dart:112`; `success`/`encryptionRequired`/`sendFailed`) and/or the persisted `message.status` transition `'sending'→'failed'` (`feed_wired.dart:1655/1708/1732`). (NOTE: `SendMessageResult` in `p2p/.../send_message_use_case.dart:5` is a *different* enum — do not key on it.)
8. **Motion + a11y (§7):** focus/glide/toast motion honoring `MediaQuery.disableAnimations`.
9. **Wiring/cleanup:** reduce the **`FeedScreen`** StatelessWidget contract (its sole production build site is `feed_wired.dart:3093`); the **`FeedWired` external constructor is UNCHANGED** — its construction sites need no param changes (they pass repositories, not FeedScreen callbacks). l10n (en/ar/de); remove obsolete widgets (feed usages only); update `FEED_TESTS` array + delete obsolete tests; update `feed_performance_test` fixtures. See **§"Dry-Run Execution-Readiness Amendments"** for the exact reduced FeedScreen contract + all call sites.

**Decision G (group composer sourcing — resolves a cross-slice open question):** a focused **group** letter's composer verb and outgoing route source from the **group** ("Reply to &lt;group name&gt;…" + `_onGroupInlineSend(groupId)` / `_openGroupConversation(groupId)`), NOT from any per-sender run's `peerId`. Locked by the TC-21 group sub-case.

**Out of scope (owner named):**
- Conversation-view changes beyond *receiving* the moved reactions/edit/delete/copy entry points — owned by a follow-up "conversation interaction parity" session if the conversation view lacks any of them today.
- "Replay demo letters" demo mode — dev-only, not shipped (deferred / never).
- Orbit redesign, posts redesign, native/notification routing changes.
- Real-relay / multi-device convergence — N/A for this UI redesign.

## Files To Inspect Next
**Production — domain/projection/persistence:** `lib/features/feed/application/{load_feed_use_case.dart,feed_projection.dart,feed_store.dart,load_contact_feed_snapshot_use_case.dart,load_group_feed_snapshot_use_case.dart}`; `lib/features/feed/domain/models/feed_item.dart`; `lib/features/feed/domain/utils/group_group_messages_into_threads.dart`; **new** `lib/features/feed/domain/utils/group_sender_runs.dart`, `lib/features/feed/domain/models/feed_letter.dart`, `lib/core/database/migrations/092_feed_cleared_threads.dart`, `lib/features/feed/data/feed_cleared_repository*.dart`.
**Production — presentation:** `lib/features/feed/presentation/screens/{feed_screen.dart,feed_wired.dart}`; **new** widgets `letter_bubble.dart`, `letter_card_one_to_one.dart`, `letter_card_group.dart`, `letter_card_system.dart`, `feed_composer.dart`, `feed_swipe_card.dart` (Dismissible host), `caught_up_empty_state.dart`, `feed_ring_avatar.dart`.
**Production — tokens/identity:** `lib/core/theme/feed_tokens.dart` (new), `lib/core/theme/app_theme.dart` (register extension), `lib/core/utils/ring_avatar_generator.dart` (add `accentColorForPeerId`).
**External instantiation sites (3 real constructor calls — verified):** `lib/features/identity/presentation/startup_router.dart:341` (`buildFeed`), `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart:383` (route builder), `lib/features/home/presentation/screens/first_time_experience_wired.dart:242` (route builder). NOT instantiations (comments only, doc-touch-up at most): `lib/core/services/share_intent_service.dart:27`, `lib/main.dart:3029`. **DB version constant:** `lib/core/database/app_database_version.dart:1` (`currentIdentityDatabaseVersion = 91` → **92**), consumed at `lib/main.dart:436` and referenced by `migration_database_manifest.dart:77,119`.
**Direct + integration tests:** all of `test/features/feed/**` (most rewritten/deleted), `integration_test/feed_performance_test.dart`.
**Dependency-only context:** `lib/core/theme/background_readable_colors.dart`, `lib/core/theme/glassmorphism.dart`, `lib/features/home/presentation/widgets/{ring_avatar.dart,ring_avatar_painter.dart}`, `lib/l10n/{app_en,app_ar,app_de}.arb`, `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`.

## Existing Tests Covering This Area
- `test/features/feed/application/load_feed_use_case_test.dart` — full-history projection (exists; **REWRITE** to pending-only).
- `test/features/feed/application/feed_store_test.dart` — upsert-only store (exists; **REWRITE** for remove/undo/ordered).
- `test/features/feed/presentation/screens/feed_screen_test.dart`, `feed_wired_test.dart` — wide-prop harness (exist; **MODIFY** to new contract; keep `buildFeedWired()` DI + `pumpFeedFrames` bounded-pump + fake listeners).
- `test/features/feed/presentation/widgets/message_bubble_test.dart` — time/status/edited/reactions (exist; **DELETE those**, **PORT** the RTL/BiDi direction tests to `letter_bubble_test.dart`).
- `test/features/feed/integration/{feed_card_flow_test.dart,expanded_collapsed_card_test.dart,feed_color_smoke_test.dart}` — open/collapsed/SessionReply/maxPreview/FeedColors (exist; **DELETE** — they assert behaviors the redesign removes; **all three are in `FEED_TESTS`** so the array must be updated in the same change).
- `test/features/feed/presentation/widgets/{unread_count_badge_test.dart,replied_indicator_test.dart,more_messages_hint_test.dart,view_earlier_link_test.dart,session_divider_test.dart,time_gap_divider_test.dart,quote_preview_bar_test.dart,swipe_to_quote_bubble_test.dart,expanded_compose_input_test.dart,checkmark_burst_animation_test.dart}` — **DELETE feed-only widgets' tests** (keep `unread_count_badge`/`quote_preview_bar` widget files for orbit/conversation).
- `test/core/utils/ring_avatar_generator_test.dart` — djb2/known-vector/glow-hue (exists; **EXTEND** with `accentColorForPeerId` 72/67 cases). **Template for §4.**
- `connection_card_test.dart`, `introduction_connection_card_test.dart` — ThemeExtension token pattern + introducedBy (exist; **REWRITE** to new system-letter anatomy).

**Missing coverage gaps:** pending-only projection, cleared-flag persistence/migration, re-surface, per-sender runs, focus→collapse-others, single shared composer append/stay-open, Dismissible commit/dismiss, Undo re-insert, "Open full conversation ↗", "You're all caught up", reduced-motion, never-silent send, gesture-arena coexistence, dismiss-does-not-touch-badge isolation.

**Already in curated family arrays?:** `FEED_TESTS` (3 tests, all being deleted). No feed test is in any other family. `feed_performance_test.dart` runs via its own integration harness (not `flutter test` glob).

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> All wired/screen tests mount `AmbientBackground` whose `repeat()` loop **hangs `pumpAndSettle`** — use the existing `pumpFeedFrames()` / bounded `tester.pump(Duration)` only (confirmed `feed_wired_test.dart:271-275`). Global-isolation temp-file teardown must be **sync `deleteSync`** (`flutter_test_config.dart`).

1. `test/features/feed/application/feed_pending_projection_test.dart::excludes read/replied/cleared, keeps only pending`
   - Tier: unit/application. Setup: fake contact/message/group repos + fake `FeedClearedRepository`; seed (a) unread-incoming thread, (b) all-read thread, (c) thread answered after last incoming, (d) cleared thread.
   - RED on HEAD because: the function does not exist yet / `loadFeed` returns all four (`load_feed_use_case.dart:156-157` has no filter).
   - GREEN asserts: only (a) present; emits `FL/FEED_PENDING_PROJECTED {kept:1}`.
   - Mutation that re-reds: revert the pending filter → (b)(c)(d) reappear.
2. `…feed_pending_projection_test.dart::cleared thread re-surfaces when a newer incoming arrives`
   - Tier: unit. RED on HEAD: re-surface predicate absent. GREEN: thread with incoming `ts > cleared_at_ms` is pending again; emits `FL/FEED_RESURFACE`. Mutation: revert watermark comparison (`>=` vs `>`) → stays hidden, red.
   - Distinct-event discriminator: assert `FEED_RESURFACE` **AND NOT** `FEED_PENDING_PROJECTED{kept:0}`.
3. `test/features/feed/domain/group_sender_runs_test.dart::collapses consecutive same-sender unread lines into runs, no cap, incoming-only`
   - Tier: unit. RED: `groupSenderRuns` util absent. GREEN: 5 messages [Mara,Mara,Bob,Mara,(outgoing)] → runs [Mara×2, Bob×1, Mara×1], outgoing dropped, no `maxPreview` truncation. Mutation: cap runs at 3 → 4th run lost, red.
4. `test/core/utils/ring_avatar_generator_test.dart::accentColorForPeerId is djb2 hsl(hue,72%,67%) and deterministic`
   - Tier: unit. RED: `accentColorForPeerId` absent. GREEN: same peerId → same color; HSL saturation 0.72, lightness 0.67; known-vector hue == `(djb2('Mara')>>16)%360`. Mutation: change 0.72→0.70 → red (proves it is NOT the old glow helper).
5. `test/features/feed/presentation/widgets/letter_bubble_test.dart::role fills + no chrome`
   - Tier: widget. RED: `LetterBubble` absent. GREEN (4 cases): incoming-resting→surfaceSubtle+borderSoft; incoming-focused→surfaceRaised+teal400 border+teal glow `BoxShadow`; outgoing→greenFill15+green500 right-aligned; system→greenFill15+green500. radius 16, padding 8×14, has `BackdropFilter`. Asserts **no** `Text` matching a time pattern, **no** status-tick icon. Mutation: re-add `Text(time)` in the bubble → "no time" assertion red.
6. `…letter_bubble_test.dart::RTL Arabic text renders rtl (ported from message_bubble_test)`
   - Tier: widget. RED: new widget. GREEN: Arabic content → `Directionality.of == rtl` via `detectTextDirection`. Mutation: force `TextDirection.ltr` → red.
7. `test/features/feed/presentation/widgets/letter_card_one_to_one_test.dart::avatar40 top-aligned, bubble stack, NO name/header`
   - Tier: widget. RED: widget absent. GREEN: finds `RingAvatar` size 40, N stacked `LetterBubble`s, and `findsNothing` for any contact-name `Text` header. Mutation: render the name → "no name" red.
8. `test/features/feed/presentation/widgets/letter_card_group_test.dart::per-sender run = avatar32 + "Sender · ⛁ Group" accent label + bubbles; every line`
   - Tier: widget. RED: widget absent. GREEN: per run a `RingAvatar` size 32 + a `RichText` whose sender span color == `accentColorForPeerId(senderPeerId)` and group span == token muted + `Icons`/symbol groups icon; all unread lines present (no "N more"). Mutation: tint sender name with token textPrimary → accent-color assertion red.
9. `test/features/feed/presentation/widgets/letter_card_system_test.dart::connection vs introduction anatomy + green "tap to say hi"`
   - Tier: widget. RED: widget absent. GREEN: connection → avatar40 + muted "Connected" label + verified icon (green token) + one green bubble "tap to say hi"; introduction → "Introduced by Alice" + handshake icon. Mutation: drop the green bubble → red.
10. `test/features/feed/presentation/screens/feed_focus_test.dart::tap focuses card; OTHER cards collapse+fade; nav fades (not keyboard-hide); composer + "Open full conversation" appear`
    - Tier: widget (bounded pumps). **Fixture MUST mount ≥3 cards** so collapse-others is load-bearing. RED: focus model is in-place expand, no collapse-others, per-card composer, NavBar hard-hidden only when keyboard up (`feed_screen.dart:210,223-226,685-825`, `feed_wired.dart:2960-3017`). GREEN: before tap → resting state has **no** `FeedComposer` and **no** "Open full conversation ↗" (`findsNothing`), NavBar opacity 1.0. After tapping one card → the **other two** cards reach `AnimatedOpacity` opacity 0 / collapsed `AnimatedSize` (max-height→0) while the focused one stays opaque; the single `FeedComposer` and "Open full conversation ↗" appear; NavBar fades via `AnimatedOpacity`→0 **without the keyboard being raised** (feed-screen-local fade, not the shared `FeedNavigationBar`). Mutations: (a) remove the collapse-others branch → sibling cards stay opaque, red; (b) revert to keyboard-gated hard-hide → focus-without-keyboard NavBar opacity stays 1.0, red; (c) render the link/composer ungated on `focusedId` → resting `findsNothing` flips red.
11. `…feed_focus_test.dart::composer placeholder verb (1:1 / group / system) + append-green-bubble-stay-open`
    - Tier: widget. RED: per-card `InlineReplyInput` clears+unfocuses (`inline_reply_input.dart:136-143`); no shared composer; no name-based verb. GREEN: focusing a **1:1** card → hint "Reply to &lt;contact name&gt;…"; focusing a **group** card → hint "Reply to &lt;**group** name&gt;…" **and** send routes via `_onGroupInlineSend(groupId)` (NOT a sender run's peerId — see Decision G below); focusing a **system** card → "Message &lt;name&gt;…"; entering text + send → a new outgoing green `LetterBubble` appended AND composer stays focused with hint "Add another…". emits `FL/FEED_SEND_APPEND`. Mutations: (a) revert append-and-stay (collapse on send) → composer gone, red; (b) source the group verb/route from a sender run's peerId instead of the group → group-name/route assertion red.
12. `test/features/feed/presentation/screens/feed_swipe_test.dart::swipe-right (focused) commits — green-check past ~92px, removes, marks read+cleared`
    - Tier: widget. RED: no `Dismissible` in feed. GREEN: focus card; drag right past threshold → card removed; `FeedClearedRepository.markCleared` called with read=true; left-edge green-check indicator widget shown during drag; emits `FL/FEED_CLEAR_COMMIT`. Under-threshold drag → springs back, no removal. Mutation: lower-threshold-only revert / remove `confirmDismiss` direction gate → commit fires while resting, red.
13. `…feed_swipe_test.dart::swipe-left (resting) dismisses — red indicator, Undo toast, cleared-only (no read)`
    - Tier: widget. RED: no swipe-dismiss. GREEN: resting card; drag left → removed; red right-edge indicator; SnackBar "Removed <name> · Undo"; `markCleared` called with read=false; emits `FL/FEED_CLEAR_DISMISS`. Distinct-event discriminator: assert `FEED_CLEAR_DISMISS` **AND NOT** `FEED_CLEAR_COMMIT` (proves dismiss ≠ commit; dismiss must not mark read). Mutation: make dismiss call `markConversationRead` → a sentinel asserting unread-count unchanged flips red.
14. `…feed_swipe_test.dart::Undo re-inserts at original index and reverses cleared`
    - Tier: widget. RED: no Undo. GREEN: dismiss the middle of 3 cards → tap Undo → card returns at index 1; `FeedClearedRepository.clearCleared` (undo) called; emits `FL/FEED_CLEAR_UNDO`. Mutation: re-insert at index 0 (append) → order assertion red.
15. `…feed_swipe_test.dart::gesture gating + dominant-axis + tap-suppression`
    - Tier: widget. RED: spec gating absent. GREEN: right-swipe disabled while resting; left-swipe disabled while focused; a primarily-vertical drag scrolls the list (no commit/dismiss); a horizontal drag suppresses the card tap (no focus toggle). Mutation: remove axis-lock → vertical drag triggers dismiss, red.
16. `test/features/feed/presentation/screens/feed_caught_up_test.dart::draining to zero shows green done_all "You're all caught up"`
    - Tier: widget. RED: empty state is "Your feed is ready" card (`feed_screen.dart:1146-1174`). GREEN: with zero pending items → `Icons.done_all` (green token) + l10n `feed_all_caught_up`; **no** "Your feed is ready". Mutation: keep the old empty card → new-copy assertion red.
17. `…feed_swipe_test.dart::failed/pending outgoing reply shows non-tick "tap to retry", never silent`
    - Tier: widget. RED: the new `LetterBubble`/composer has no failed-send affordance (spec drops ticks; nothing replaces them). GREEN: an outgoing reply whose `SendChatMessageResult` is `sendFailed` (or whose persisted `message.status=='failed'`) → renders a tappable retry affordance (no status-tick icon); tapping invokes the resend callback; emits `FL/FEED_SEND_RETRY_SHOWN`. Mutation: drop the affordance (silent) → red.
18. `test/features/feed/presentation/screens/feed_reduced_motion_test.dart::prefers-reduced-motion uses instant transitions`
    - Tier: widget. RED: no `disableAnimations` handling in feed (grep nil). GREEN: with `MediaQuery(disableAnimations:true)`, focus-collapse + glide durations are `Duration.zero`; no entrance `repeat()`. Mutation: ignore the flag → non-zero duration assertion red.
19. `test/core/database/migrations/092_feed_cleared_threads_test.dart::creates table, idempotent, preserves data`
    - Tier: migration host — **real SQLCipher** (`sqfliteFfiInit()` + `databaseFactoryFfi.openDatabase(inMemoryDatabasePath)`). RED: migration absent. GREEN: (a) after **upgrade** v91→v92, `PRAGMA table_info(feed_cleared_threads)` has columns `thread_kind, thread_id, cleared_at_ms` + PK(thread_kind,thread_id); (b) **clean open directly at v92** (fresh DB created at version 92) has the same table/columns/PK; (c) running the migration twice is a no-op; (d) pre-existing tables/rows preserved. Mutation: revert the `CREATE TABLE` → PRAGMA red.
20. `test/features/feed/data/feed_cleared_repository_test.dart::markCleared/clearCleared/getWatermarks round-trip + survives reopen`
    - Tier: integration (real SQLCipher). RED: repo absent. GREEN: `markCleared(threadKind, threadId, clearedAtMs, {required bool markRead})` persists; `getClearedWatermarks()` returns `Map<(threadKind,threadId), int clearedAtMs>`; `clearCleared(threadKind, threadId)` removes it; values survive close+reopen. Mutation: make `markCleared` a no-op → getter red. (**Param name pinned to `markRead:` everywhere — P1/P4/P6 all call it.**)
21. `test/features/feed/presentation/screens/feed_contract_preservation_test.dart::reduced contract still injects+exposes posts/share deps`
    - Tier: widget (preservation/contract — **NOT RED-first**; a smoke that builds the *new* contract cannot compile against HEAD, so it is GREEN-by-construction). RED proxy: a temporary mutation that drops a posts/share dep from the wiring → build throws. GREEN asserts: building `FeedWired` with the reduced contract still injects and reaches `PostRepository` / `PendingPostTargetStore` / `PostsPrivacySettingsRepository` so share-to-contact keeps working. Mutation: drop a required posts dep wiring → build throws, red.
    - **Scope note:** the 3 external constructor sites (`startup_router.dart:341`, `qr_scanner_wired.dart:383`, `first_time_experience_wired.dart:242`) are covered **compile-only** by `flutter analyze`; there is **no behavioral test** of their feed-entry routing (acknowledged gap — see Risks "external feed-entry routing").
22. `test/l10n/feed_strings_parity_test.dart::new feed strings exist in en/ar/de; removed strings gone`
    - Tier: unit. RED: new keys absent. GREEN: `feed_all_caught_up`, `feed_reply_to_name`, `feed_message_name`, `feed_add_another`, `feed_removed_undo`, `feed_open_full_conversation`, `feed_tap_to_say_hi`, `feed_connected`, `feed_introduced_by` present in all three `.arb`; `feed_you_replied`/`feed_previously_seen`/`feed_view_earlier_messages` absent (**confirm these 3 keys exist on HEAD before asserting removal**). Mutation: omit ar key → parity red.
    - **Overlap note:** `test/l10n/l10n_integrity_test.dart` ALREADY enforces identical key+placeholder sets across en/de/ar (`:10-43`). Put the new test in `test/l10n/` and scope it to the **feed-specific** checks (removed-keys-gone + specific-keys-present); leave cross-locale parity to the existing integrity test (which will auto-police the new keys).
23. `test/features/feed/domain/feed_letter_model_test.dart::1:1 single vs stacked; connection vs introduction` (TC-04, TC-06)
    - Tier: unit. RED: pending letter view-models absent. GREEN: one incoming → single-text letter; ≥2 consecutive incoming → stacked `texts[]`; `ConnectionFeedItem.introducedBy==null` → `isSystem` new-connection letter; `introducedBy!=null` → introduction letter carrying the introducer name. Mutations: merge stacked into one / drop the introducedBy branch → red.
24. `test/features/feed/presentation/widgets/letter_card_*_test.dart::card renderers wire RingAvatar at feed sizes` (TC-09, re-anchored)
    - Tier: widget. RED: feed cards wire `UserAvatar`/`GroupAvatar` at **size 42** (`open_mode_card_body.dart:131`, `collapsed_mode_card_body.dart:144`), not `RingAvatar` at spec sizes. GREEN (at the real call sites, NOT a standalone wrapper): `letter_card_one_to_one` renders `RingAvatar` size **40**; `letter_card_group` renders a per-run `RingAvatar` size **32**; system card 40, composer 32. Mutation: set a card avatar to the legacy **42** → size assertion red. (Folds into TC-16/17.)
25. `test/core/theme/feed_tokens_test.dart::FeedTokens ThemeExtension resolves spec tokens + lerp` (TC-10)
    - Tier: widget/theme (`test/core/**`). RED: `FeedTokens` extension absent. GREEN: `Theme.of(context).extension<FeedTokens>()` returns non-null with `teal400/tealFill08/green500/greenFill15/surfaceSubtle/surfaceRaised/borderSoft/canvas/blurLetter/blurNav/radiusFull/space3/textMessage/leadingMessage/textMeta`; `lerp(t)` interpolates a representative token. Mutation: drop a token field (or unregister the extension) → resolve red.
26. `…feed_swipe_test.dart::card commit coexists with the screen-level Feed↔Orbit horizontal swipe host` (TC-35)
    - Tier: widget gesture. RED: only the screen-level host swipe exists (`feed_wired.dart:2703-2832`); no card-level arbitration. GREEN: a horizontal drag **starting on a focused card** commits it (Dismissible wins) and does NOT switch Feed↔Orbit; a horizontal drag on the **background/list** still switches Feed↔Orbit. Mutation: remove the per-card-vs-host arena arbitration → background swipe triggers a card commit (or vice-versa), red.
27. `…letter_bubble_test.dart::bubble max-width ~76%` (TC-15b, §3)
    - Tier: widget. RED: new widget; the dropped `MessageBubble` had `0.78` (`message_bubble.dart:82-85`) — not inherited. GREEN: `LetterBubble` wraps content in a `ConstrainedBox` with `maxWidth == MediaQuery width * ~0.76` (token-driven). Mutation: remove the `ConstrainedBox` / set fraction 1.0 → red.
28. `…feed_focus_test.dart::scroll list bottom padding ~170px` (TC-19b, §8)
    - Tier: widget. RED: current bottom padding is `60 + inset` (`feed_screen.dart:1107`) — last card sits under the floating composer/nav. GREEN: the scrollable's bottom padding/`SliverPadding` is ~170px (token-driven). Mutation: revert to `60 + inset` → red.
29. `…letter_card_system_test.dart::tapping the green "tap to say hi" bubble fires the REAL send/navigate callback` (TC-18b, §5)
    - Tier: widget. RED: new system letter; the real `onSendMessage`/navigate wiring (`connection_card.dart:356`) must survive the visual rebuild. GREEN: tapping the system letter's green bubble invokes the real `onSendMessage`/`buildConversationRoute` callback for that `peerId`. Mutation: stub the bubble `onTap` to a no-op → callback-not-invoked red.
30. `…feed_swipe_test.dart::Undo vs live re-surface — no duplicate during the 4s window` (TC-37)
    - Tier: widget. RED: no dedupe between the undo-snapshot restore and live-stream re-surface. GREEN: dismiss a card, emit a **newer** incoming on that thread, THEN tap Undo → exactly **one** card for that thread (documented ordering winner), not two. Mutation: skip dedupe between undo-snapshot and live re-surface → two cards / order red.
31. `test/features/feed/presentation/widgets/feed_shared_widget_survival_test.dart::UnreadCountBadge + QuotePreviewBar still compile & mount` (TC-38, INV-9)
    - Tier: widget. RED: (proxy) if either widget file is deleted, the import fails to compile. GREEN: mounting `UnreadCountBadge` and `QuotePreviewBar` from their library paths renders (proves the files survive for orbit/conversation; only feed *usages* were removed). Mutation: delete a widget file → import red.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 pending-only (§1) | pure logic | unit | feed_pending_projection_test::excludes read/replied/cleared | no filter (`load_feed_use_case:156`) | revert filter | `flutter test test/features/feed/application/` | add to `FEED_TESTS` |
| TC-02 cleared filter (dec2) | pure logic | unit | feed_pending_projection_test::cleared excluded | predicate absent | revert watermark check | `flutter test test/features/feed/application/` | add to `FEED_TESTS` |
| TC-03 re-surface (default) | pure logic | unit | feed_pending_projection_test::re-surfaces on newer incoming | predicate absent | `>`→`>=` flip | `flutter test test/features/feed/application/` | AUTO (glob) |
| TC-04 1:1 single/stacked (§2) | pure logic | unit | feed_letter_model_test::single vs stacked texts | model absent | merge→split | `flutter test test/features/feed/domain/` | AUTO (glob) |
| TC-05 group runs no-cap (§2/§5) | pure logic | unit | group_sender_runs_test::collapse runs, no cap, incoming-only | util absent | cap at 3 | `flutter test test/features/feed/domain/` | add to `FEED_TESTS` |
| TC-06 system letters (§2) | pure logic | unit | feed_letter_model_test::connection vs introduction | derive absent | drop introducedBy branch | `flutter test test/features/feed/domain/` | AUTO (glob) |
| TC-07 rtl render-derived (§2) | widget | widget | letter_bubble_test::RTL Arabic rtl | new widget | force ltr | `flutter test test/features/feed/presentation/widgets/` | AUTO (glob) |
| TC-08 accent 72/67 (§4) | pure logic | unit | ring_avatar_generator_test::accentColorForPeerId | helper absent | 0.72→0.70 | `flutter test test/core/utils/ring_avatar_generator_test.dart` | AUTO (`test/core/**`) |
| TC-09 RingAvatar feed sizes (§4) | widget | widget | letter_card_*_test::cards wire RingAvatar 40/32 at real call sites | cards wire UserAvatar size 42 (`open_mode_card_body:131`) | set card avatar to legacy 42 | `flutter test test/features/feed/presentation/widgets/` | add to `FEED_TESTS` |
| TC-10 FeedTokens (§9) | widget/theme | widget | feed_tokens_test::extension resolves teal400/green500/blur/space + lerp | extension absent | drop token | `flutter test test/core/theme/` | AUTO (`test/core/**`) |
| TC-11 incoming-resting bubble (§3) | widget | widget | letter_bubble_test::role fills | widget absent | swap fill | `flutter test test/features/feed/presentation/widgets/letter_bubble_test.dart` | add to `FEED_TESTS` |
| TC-12 focused bubble glow (§3) | widget | widget | letter_bubble_test::role fills (focused) | widget absent | drop glow | (as TC-11) | add to `FEED_TESTS` |
| TC-13 outgoing green (§3) | widget | widget | letter_bubble_test::role fills (outgoing) | widget absent | use teal | (as TC-11) | add to `FEED_TESTS` |
| TC-14 system green bubble (§3) | widget | widget | letter_bubble_test::role fills (system) | widget absent | drop green | (as TC-11) | add to `FEED_TESTS` |
| TC-15 no chrome (§1/§3) | widget | widget | letter_bubble_test::no time/status/edited | widget absent | re-add Text(time) | (as TC-11) | add to `FEED_TESTS` |
| TC-15b max-width ~76% (§3) | widget | widget | letter_bubble_test::maxWidth ~0.76 | new widget; 0.78 not inherited | remove ConstrainedBox / set 1.0 | (as TC-11) | add to `FEED_TESTS` |
| TC-16 1:1 anatomy (§5) | widget | widget | letter_card_one_to_one_test::avatar40, no name | widget absent | render name | `flutter test test/features/feed/presentation/widgets/` | add to `FEED_TESTS` |
| TC-17 group anatomy (§5) | widget | widget | letter_card_group_test::per-run avatar32 + accent label | widget absent | textPrimary name | `flutter test test/features/feed/presentation/widgets/` | add to `FEED_TESTS` |
| TC-18 system anatomy (§5) | widget | widget | letter_card_system_test::connection/introduction + green bubble | widget absent | drop green bubble | `flutter test test/features/feed/presentation/widgets/` | add to `FEED_TESTS` |
| TC-18b system real callback (§5) | widget | widget | letter_card_system_test::green bubble fires real onSendMessage/navigate | new widget; wiring (`connection_card:356`) must survive | stub onTap to no-op | `flutter test test/features/feed/presentation/widgets/` | add to `FEED_TESTS` |
| TC-19 focus→collapse-others + nav fade (§6/§8) | widget (≥3 cards) | widget | feed_focus_test::other cards fade/collapse; nav fades w/o keyboard | in-place expand; nav hard-hide on keyboard | remove collapse branch / revert to keyboard-gated hard-hide | `flutter test test/features/feed/presentation/screens/feed_focus_test.dart` | add to `FEED_TESTS` |
| TC-19b bottom padding ~170px (§8) | widget | widget | feed_focus_test::scroll bottom padding ~170px | current 60+inset (`feed_screen:1107`) | revert to 60+inset | (as TC-19) | add to `FEED_TESTS` |
| TC-20 shared composer + open-conv link (§6/§8) | widget | widget | feed_focus_test::composer + "Open full conversation" appear | per-card composer | remove link/composer | (as TC-19) | add to `FEED_TESTS` |
| TC-21 verb placeholder 1:1/group/system (§6) | widget | widget | feed_focus_test::Reply to / Message verb + group sources GROUP name/route | fixed name-less hint; group sourcing undefined | source group verb/route from a sender peerId | (as TC-19) | add to `FEED_TESTS` |
| TC-22 append-stay (§6) | widget | widget | feed_focus_test::append green bubble, stay open | clears+unfocuses | collapse-on-send | (as TC-19) | add to `FEED_TESTS` |
| TC-23 swipe-right commit (§6) | widget gesture | widget | feed_swipe_test::commit, green-check, read+cleared | no Dismissible | remove direction gate | `flutter test test/features/feed/presentation/screens/feed_swipe_test.dart` | add to `FEED_TESTS` |
| TC-24 swipe-left dismiss (§6) | widget gesture | widget | feed_swipe_test::dismiss, red, Undo, cleared-only | no swipe-dismiss | dismiss→markRead | (as TC-23) | add to `FEED_TESTS` |
| TC-25 Undo re-insert (§6) | widget | widget | feed_swipe_test::Undo re-inserts at index | no Undo | re-insert at 0 | (as TC-23) | add to `FEED_TESTS` |
| TC-26 gesture gating (§6) | widget gesture | widget | feed_swipe_test::axis-lock + tap-suppression | gating absent | remove axis-lock | (as TC-23) | add to `FEED_TESTS` |
| TC-27 caught-up empty (§6) | widget | widget | feed_caught_up_test::done_all + copy | old empty card | keep old card | `flutter test test/features/feed/presentation/screens/feed_caught_up_test.dart` | add to `FEED_TESTS` |
| TC-28 migration 092 (dec2) | migration | migration host (real SQLCipher) | 092_feed_cleared_threads_test::create/idempotent/preserve | migration absent | revert CREATE TABLE | `flutter test test/core/database/migrations/092_feed_cleared_threads_test.dart` | AUTO (`test/core/**`) |
| TC-29 cleared repo (dec2) | repo+DB | integration (real SQLCipher) | feed_cleared_repository_test::round-trip + reopen | repo absent | markCleared no-op | `flutter test test/features/feed/data/` | add to `FEED_TESTS` |
| TC-30 never-silent send (dec4) | widget | widget | feed_swipe_test::failed reply tap-to-retry | no replacement for tick | drop affordance | (as TC-23) | add to `FEED_TESTS` |
| TC-31 reduced-motion (§7) | widget | widget | feed_reduced_motion_test::instant transitions | flag unhonored | ignore flag | `flutter test test/features/feed/presentation/screens/feed_reduced_motion_test.dart` | add to `FEED_TESTS` |
| TC-32 contract preservation (blast) | widget preservation (NOT RED-first) | widget | feed_contract_preservation_test::reduced contract still reaches posts/share deps | green-by-construction; RED proxy = drop a posts dep | drop a posts dep wiring → build throws | `flutter test test/features/feed/presentation/screens/ && flutter analyze` | AUTO (glob) + analyze (3 sites compile-only) |
| TC-33 dismiss-isolation (dec2/blast) | widget | widget | feed_swipe_test::dismiss leaves unread badge/Orbit unchanged | dismiss would mark read | dismiss→markRead | (as TC-23) | add to `FEED_TESTS` |
| TC-34 l10n parity (blast) | pure logic | unit | feed_strings_parity_test::en/ar/de keys | keys absent | omit ar key | `flutter test test/l10n/ && flutter gen-l10n` | AUTO (glob) |
| TC-35 gesture-arena coexist | widget gesture | widget | feed_swipe_test::card commit vs Feed↔Orbit host swipe | new gesture vs host | remove arena arbitration | (as TC-23) | add to `FEED_TESTS` |
| TC-36 perf preservation | perf integration | integration_test | feed_performance_test::frame budgets (new fixtures) | fixtures use old model | n/a (preservation) | `flutter test integration_test/feed_performance_test.dart` (device/sim) | own harness (no glob) |
| TC-37 Undo vs live re-surface | widget | widget | feed_swipe_test::no duplicate during 4s Undo window | no dedupe snapshot vs stream | skip dedupe | (as TC-23) | add to `FEED_TESTS` |
| TC-38 shared-widget survival (INV-9) | widget | widget | feed_shared_widget_survival_test::UnreadCountBadge+QuotePreviewBar mount | (proxy) delete file → import fails | delete a widget file | `flutter test test/features/feed/presentation/widgets/` | AUTO (glob) |

## Invariants (locked by tests)
- **INV-1 (pending-only):** the feed contains a thread iff it has an incoming-unread message newer than its cleared watermark and the user has not answered since → TC-01/02/03.
- **INV-2 (dismiss isolation):** swipe-left dismiss writes `feed_cleared` only; it never mutates read-state, the unread badge, the Orbit badge, or archive → TC-24/33 (discriminator `FEED_CLEAR_DISMISS` AND NOT `FEED_CLEAR_COMMIT`).
- **INV-3 (commit semantics):** swipe-right commit marks read + cleared and removes the card; no navigation → TC-23.
- **INV-4 (Undo fidelity):** Undo restores both the cleared row deletion and the original list index → TC-14/25.
- **INV-5 (incoming-only cards):** feed cards render no outgoing/own message except the session's just-appended replies; no timestamps/status/edited/unread chrome → TC-15/05/16.
- **INV-6 (one identity color):** sender name accent and its avatar derive from the *same* `accentColorForPeerId` (72/67); global glow (70/50) is untouched → TC-08/17.
- **INV-7 (never-silent send):** a failed/pending outgoing reply always shows a retry affordance → TC-30.
- **INV-8 (reduced-motion):** all feed motion collapses to `Duration.zero` under `disableAnimations` → TC-31.
- **INV-9 (shared-widget non-deletion):** `UnreadCountBadge` and `QuotePreviewBar` widget files survive (orbit/conversation keep them); only feed usages are removed → TC-38 + preservation gates.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Dry-Run Execution-Readiness Amendments  (from the P0–P8 read-only `Plan`-agent dry-run, workflow `wf_2aa14fa4-a05`)
**These supersede the prose above where they conflict. Verdict: ready-after-amendments.** Resolve the 6 cross-phase contracts FIRST.

**Cross-phase contracts (pin before any RED test):**
1. **Reduction target = `FeedScreen`, not `FeedWired`.** The `FeedWired` external ctor (`feed_wired.dart:192-232`) is UNCHANGED — all 35 deps stay. Only the inner `FeedScreen` StatelessWidget contract (`feed_screen.dart:33-131`) shrinks, at its sole prod build site `feed_wired.dart:3093`. **Reduced FeedScreen contract:** KEEP `username, userAvatarBytes, userPeerId, feedItems, feedItemsListenable, feedLoaded, onUsernameChanged, p2pService, onSwitchView, activeTab, totalUnreadCount(+Listenable), orbitBadgeCount(+Listenable), onAvatarTap, backgroundPreference, readableToneOverride`; KEEP-and-repurpose `onSendMessage` (system "tap to say hi"), `onViewFullConversation`→`onOpenFullConversation`, `onGroupTap`; **REMOVE** the per-card composer/quote/edit/sessionReply/reaction set (`onReplyToMessage, expandedCardId, onToggleExpand, onInlineSend, draftTexts, activeFocusPeerId, onDraftChanged, onInputFocusChanged, editing*, onEditMessage, onDeleteMessage, onCancelEdit, activeQuoteMessageIds, onQuoteReply, onClearQuote, onAttach, sessionReplies, reactions, reactionListenableForMessage, onReactionSelected, onGroupInlineSend, onGroupAttach, onGroupReactionTap/Selected`); **NET-NEW** (the plan omitted these) `focusedId, onFocusCard, onClearFocus, onComposerSend(threadId,text), onComposerDraftChanged(threadId,text), onSwipeCommit(threadId), onSwipeDismiss(threadId), onUndoDismiss(threadId)`.
2. **`markCleared` signature pinned:** `markCleared(String threadKind, String threadId, int clearedAtMs, {required bool markRead})`. Used by P1/P4/P6.
3. **`ClearedWatermarks` shape pinned (P1↔P4↔P6 contract):** `Map<(String threadKind, String threadId), int clearedAtMs>`; `threadKind ∈ {'contact','group','connection'}`; `threadId` = peerId/groupId/contactPeerId. Connection letters use **presence** (a cleared row exists → drop), not a timestamp compare.
4. **The pending+cleared filter lives in `FeedStore`, NOT only `loadFeed`.** Add `setWatermarks(...)` + run `projectPendingFeed(...)` inside `_buildItems`/`_publish` (`feed_store.dart:16-24`). Otherwise any of the 12 live listeners (`feed_wired.dart:768/807/843/874/1096/1136/1182/1302`) re-publishes a just-cleared card. **This is the highest project-wide risk.**
5. **Ordered-store model:** use a **cleared-overlay** (dismiss *hides* the item in its sorted slot; Undo *un-hides*) rather than a positional list fighting the timestamp re-sort. **TC-37 dedupe winner = the live newer re-surface** (drop the Undo snapshot if a newer incoming arrived).
6. **INV-1 (exact):** keep a thread iff it has an incoming-unread message with `timestamp.millisecondsSinceEpoch` **strictly >** its watermark **AND** no outgoing message after the newest incoming ("not answered since"). Compare via `ThreadMessage.timestamp` (already `DateTime`, `feed_item.dart:77`) — NEVER raw model `timestamp` (String for 1:1, DateTime for group).

**Call-site reality (corrects the plan):** `FeedWired` has **4** construction sites (add `integration_test/feed_wired_init_performance_harness.dart:336`, registered in `check_reliability_simulation_discovery.sh:323`). `FeedScreen` has **7** sites: `feed_wired.dart:3093`, `test/features/feed/.../feed_screen_test.dart`, `integration_test/feed_performance_test.dart:127`, `test/features/loading_states_smoke_test.dart:37`, `integration_test/loading_states_smoke_test.dart:41`, `integration_test/settings_background_choice_smoke_test.dart:90`. The last three pass only survivors `{username, feedItems, feedLoaded, onSwitchView, activeTab, backgroundPreference}` and assert ValueKeys `feed-loading-card-0`/`feed-loading-status` (`feed_screen.dart:1186/1217`) — **P4/P7 must preserve those keys; P8 must NOT delete these as "feed tests".**

**Per-phase corrections:**
- **P1:** add a new file `lib/core/database/helpers/feed_cleared_threads_db_helpers.dart` (free fns `dbMarkFeedClearedThread/dbClearFeedClearedThread/dbLoadFeedClearedThreads`, db-as-first-arg); `FeedClearedRepositoryImpl` takes **closures** over them (the repo's universal closure-injection DI), NOT a raw `Database`; production wiring in `main.dart` near `postsPrivacySettingsRepository` (~1129). Migration/repo tests use **plain sqflite FFI** (`openDatabase(inMemoryDatabasePath)`, no password) — the migration SQL is cipher-agnostic (mirror the 081 / posts_privacy tests); "real SQLCipher" was over-stated. `accentColorForPeerId` is a **static** method on `RingAvatarGenerator` (hardcode 0.72/0.67, reuse `djb2Hash`; do not touch `glowColorForPeerId`). `AppText`/`AppSpace` classes do NOT exist → fold `textMessage/leadingMessage/textMeta/space3` directly into `FeedTokens`. `FeedTokens` needs a `context.feedTokens` getter with a `?? FeedTokens.dark` const fallback (mirror `BackgroundReadableColorsContext`). Run `test/features/account_migration/` as a **schema-hash preservation sentinel** (adding a table changes the computed schemaHash in `migration_database_schema_inventory.dart`). The version-flow file is `lib/features/account_migration/domain/models/migration_database_manifest.dart` (reads the constant symbolically — do NOT edit it).
- **P2:** decide **focused-only blur** vs card-level blur before coding — per-bubble `BackdropFilter` on hundreds of group bubbles is a real perf hazard (N saveLayers/frame) and likely visually inert on near-opaque surfaces. Confirm RED-entry-5's "has BackdropFilter" scope accordingly.
- **P3:** stack 1:1 from `ThreadFeedItem.unreadMessages` (`feed_item.dart:152`, **uncapped**) — NOT `previewMessages` (capped at 3; TC-04 would pass at 3 and silently fail at 4+). **TC-18b correction:** the system "tap to say hi" callback is a **parameterless `VoidCallback?` pre-bound to the `ConnectionFeedItem`** (`feed_screen.dart:754/765`) — there is no `buildConversationRoute` and no peerId param in the connection path. `RingAvatar({required peerId, size})` is named-param and **drops avatar photos** (intentional per §4 — flag for sign-off). `ring_avatar_spec.dart` is under `lib/core/utils/`.
- **P4:** DEFER deletion of `ConversationState`/`MessageFeedItem`/`connectedVia`/time-gap utils to **P8** — they still feed the live snapshot builders P5/P6 use; P4 only stops partitioning + adds the store-held filter.
- **P5:** the new `FeedComposer` must **NOT** unfocus on send (`InlineReplyInput._onSendPressed` at `inline_reply_input.dart:141` calls `_focusNode.unfocus()` — that collapses it) — instead clear text + keep focus + swap hint to `feed_add_another`. Group cards have **no** focus plumbing today (`_visibleActiveFocusPeerId` ignores groups, `feed_wired.dart:2640`) → unify `focusedId` to carry a `'group:<id>'` key. The send-FAILURE path currently CLEARS the optimistic bubble (`_restoreFeedComposerState`→`_sessionReplies.clear`) — TC-30 needs the failed bubble to **persist** with retry (behavior reversal). `SessionReplyTracker` is single-reply-per-key → "Add another" needs an ordered list or a refresh-based append (de-dupe vs `saveMessage`). Wrap the faded NavBar in **`IgnorePointer`** (`AnimatedOpacity(0)` still hit-tests). "Open full conversation" for groups routes by item, not id (`_openGroupConversation(item)`) → provide a `focusedId→item` lookup.
- **P6:** **KEEP** `swipe_to_quote_bubble.dart` + its test (used by `conversation_screen.dart`/`group_conversation_screen.dart`) — remove only the FEED usage (in `scrollable_message_preview.dart`, deleted with P4). Do **not** copy its axis-lock arithmetic (it's per-frame `dx`, not cumulative) — use `Dismissible`'s built-in axis handling. **Gesture arena:** the screen-level Feed↔Orbit swipe is a raw `Listener` claiming at 12px **before** Dismissible's ~18px slop → add a `_feedCardSwipeActive` host gate (mirror the existing `blockedByOrbitRow` pattern) set on card pointer-DOWN, so the host yields while a card swipe is live.
- **P7:** sequence **last** — its reduced-motion target (focus-collapse/nav-fade/Dismissible/toast) doesn't exist until P5/P6 land; thread a single `motion(Duration)` helper through P5/P6 + the existing scroll glides (`feed_screen.dart:921/941`). `AmbientBackground._controller.repeat()` is an infinite loop used by 17 screens → decide app-wide vs `isFeedSurface`-scoped gate (match the already-gated cosmic/daylight siblings), read `MediaQuery` in `didChangeDependencies`, and **OR `accessibleNavigation`** with `disableAnimations`. Drop the `username` param from the caught-up empty state. Fix the existing copy assertions (`feed_wired_test.dart:586`, `feed_screen_test.dart:154/198-202/342`) **in P7**, not P8.
- **P8:** migration 092 needs **BOTH** an `onCreate` call (`main.dart` ~529, after `runPendingGroupInvitesInviterMlKemMigration`) **AND** an `onUpgrade` `if (oldVersion < 92)` block (~811) — dispatch is inline if-blocks, there is no manifest/switch (TC-28b fresh-install fails if onCreate is omitted; the onCreate closure is inline and not importable, so TC-28b calls `runFeedClearedThreadsMigration` directly). **Do NOT delete** `unread_count_badge_test.dart`, `quote_preview_bar_test.dart`, `swipe_to_quote_bubble_test.dart` (their widgets survive for orbit/conversation/groups). **l10n:** the genuinely-new set is **8** keys (`feed_all_caught_up, feed_reply_to_name, feed_message_name, feed_add_another, feed_removed_undo, feed_open_full_conversation, feed_tap_to_say_hi, feed_connected`) — `feed_introduced_by` ALREADY exists; **do not remove `feed_you`** (groups use it). **Pull keys forward:** add `feed_all_caught_up` in **P7** and `feed_removed_undo` + the Undo label in **P6** (with `@`-placeholder metadata in en/ar/de + `flutter gen-l10n`) — they won't compile in the phase that asserts them otherwise. Add `test/l10n/l10n_integrity_test.dart`'s **hardcoded-literal scanner** as a preservation gate (every new feed string must route through `AppLocalizations`).

## Step-By-Step Implementation Plan
Land in dependency order; add the relevant RED tests at the **start of each phase**, confirm they fail for the documented reason, then implement.

**P0 — Snapshot & contract.** `git status --short` (record dirty tree); enumerate the `FeedScreen`/`FeedWired` prop set that survives the redesign (target ≈ the new reduced contract). Stop-if: a posts/share dep has no clean home in the new contract → replan the contract before touching call sites.

**P1 — Foundations (tokens + identity + migration).** RED: TC-08, TC-10, TC-28, TC-29.
- `lib/core/theme/feed_tokens.dart`: `FeedTokens extends ThemeExtension<FeedTokens>` with teal400/tealFill08/green500/greenFill15/surfaceSubtle/surfaceRaised/borderSoft/canvas/blurLetter/blurNav/radiusFull/space3 + `AppText`(textMessage/leadingMessage/textMeta) + `lerp`; register in `app_theme.dart`. Reuse `BackgroundReadableColors` mappings where they exist.
- `ring_avatar_generator.dart`: add `Color accentColorForPeerId(String peerId)` reusing `djb2Hash` → `HSLColor.fromAHSL(1, hue, 0.72, 0.67)`. **Do not** alter `glowColorForPeerId`.
- `lib/core/database/migrations/092_feed_cleared_threads.dart` + bump **`lib/core/database/app_database_version.dart:1`** `currentIdentityDatabaseVersion` 91→**92** (flows to `openDatabase` at `main.dart:436` and to `migration_database_manifest.dart:77,119`); `FeedClearedRepository` (`markCleared(kind,id,clearedAtMs,{bool markRead})`, `clearCleared`, `getClearedWatermarks`).

**P2 — Bubble (§3).** RED: TC-07, TC-11..15. New `letter_bubble.dart` (tokenized, 4 roles, focused glow, `GlassmorphicContainer`/`BackdropFilter` blur, no chrome; render-derived RTL). Port the RTL tests from `message_bubble_test.dart`.

**P3 — Letter models + card renderers (§2/§5).** RED: TC-04/05/06/09/16/17/18. New `feed_letter.dart` (pending view-models), `group_sender_runs.dart`, `feed_ring_avatar.dart`; `letter_card_one_to_one.dart`, `letter_card_group.dart`, `letter_card_system.dart`. Preserve the real `onSendMessage`/navigate wiring for system letters.

**P4 — Pending projection + ordered store + cleared filter (§1, dec2).** RED: TC-01/02/03. Rewrite `load_feed_use_case` (or add `feed_pending_projection.dart`) to filter by cleared watermark + pending predicate over the existing real-data sourcing (keep `loadContactFeedItems`/`loadGroupFeedItems` DB calls); rework `feed_store.dart` to an **ordered list with remove + insert-at-index** (supersedes upsert-only). Delete `SessionReply*`, `ConversationState` partition, `MessageFeedItem`, `connectedVia`, `split_thread_by_time_gap`, `has_significant_time_gap`, `maxPreview` getters. Emit `FEED_PENDING_PROJECTED`/`FEED_RESURFACE`.

**P5 — Focus + shared composer (§6/§8).** RED: TC-19/20/21/22, TC-30. Replace per-card composer with one screen-level `feed_composer.dart` driven by `focusedId`; focus→collapse-others via `AnimatedSize`+`AnimatedOpacity`; nav `AnimatedOpacity`→0 while focused/committing (feed-screen-local, **not** in the shared `FeedNavigationBar`); append-green-bubble-stay-open; dynamic verb; "Open full conversation ↗" → existing `buildConversationRoute`/`_openGroupConversation`; never-silent retry affordance. Emit `FEED_SEND_APPEND`/`FEED_SEND_RETRY_SHOWN`.

**P6 — Swipe + Undo + gesture arena (§6).** RED: TC-23/24/25/26/33/35. `feed_swipe_card.dart` wrapping each card in `Dismissible` (`confirmDismiss` direction-gated: `startToEnd` only while focused → commit; `endToStart` only while resting → dismiss; threshold ~0.25 ≈ 92px); left-edge green-check + right-edge red backgrounds; `onDismissed` → `markCleared` (commit: read+cleared / dismiss: cleared-only) + remove; Undo `SnackBarAction` re-inserts at original index + `clearCleared`. Reconcile with the screen-level Feed↔Orbit host swipe (dominant-axis on first move; suppress tap after drag; remove `SwipeToQuoteBubble`). Emit `FEED_CLEAR_COMMIT`/`FEED_CLEAR_DISMISS`/`FEED_CLEAR_UNDO`. Stop-if: the gesture arena double-fires → resolve arbitration explicitly, do not ship a flaky swipe.

**P7 — Empty state + reduced motion (§6/§7).** RED: TC-16(caught-up→TC-27)/TC-31. `caught_up_empty_state.dart` (green `done_all` + `feed_all_caught_up`); gate all feed motion on `MediaQuery.disableAnimations`.

**P8 — Wiring, cleanup, l10n, gates.** RED: TC-32/34. **The `FeedWired` external ctor does NOT change** — the 4 `FeedWired` sites (`startup_router.dart:341`, `qr_scanner_wired.dart:383`, `first_time_experience_wired.dart:242`, `integration_test/feed_wired_init_performance_harness.dart:336`) compile as-is; the contract reduction is internal to `FeedScreen` at `feed_wired.dart:3093`. Verify the **7 `FeedScreen` call sites** (see §Amendments) still pass valid survivor props (`flutter analyze`); add l10n keys to en/ar/de + `flutter gen-l10n`; remove obsolete widgets (**feed usages only**); **delete** `feed_card_flow_test`/`expanded_collapsed_card_test`/`feed_color_smoke_test` + obsolete widget tests and **update `FEED_TESTS`** in `run_test_gates.sh` (remove the 3 deleted, add the new curated feed tests); re-author `feed_performance_test.dart` fixtures (TC-36). Final: rerun direct → preservation → named gates → analyze.

## Risks And Edge Cases
- **Stream re-insertion vs cleared:** the 12 live listeners (`feed_wired.dart:503-533`) can push a thread the projection must re-filter through the cleared watermark → pinned by TC-02/03 + the ordered store.
- **Undo vs live churn:** an incoming message arriving during the 4s Undo window — Undo restores index from the captured snapshot; a *newer* incoming re-surfaces independently (TC-03). Capture original index at dismiss time.
- **Gesture arena triple-consumer** (Feed↔Orbit host swipe / removed bubble swipe / new Dismissible) → TC-35 + axis-lock (TC-26).
- **Group "no cap" on real data:** a group with hundreds of unread lines renders every run — bound card height with internal scroll if needed; perf pinned by TC-36. Flag if a real group exceeds a sane line budget.
- **Shared-widget deletion trap:** deleting `UnreadCountBadge`/`QuotePreviewBar` files would break orbit/conversation → INV-9 + preservation gates.
- **DB version bump** must accompany migration 092 or upgrades skip it → TC-28 (run-twice) + a clean-open-at-v92 assertion.
- **External feed-entry routing is compile-only:** the 4 `FeedWired` construction sites keep their ctor unchanged (reduction is internal to `FeedScreen`), so they compile as-is; they have **no behavioral test** of post-connect/startup feed-entry routing — manual smoke after the change. Do not assume green tests prove the routing. (See §Amendments for the full FeedScreen vs FeedWired call-site map.)
- **RingAvatar has no glow-suppression parameter:** `RingAvatar(peerId, size)` always renders the hash-derived center glow (`ring_avatar.dart:18-45`). The plan keeps the glow (consistent with §4). If a letter design must drop it, that is a **new** `showGlow` ctor flag (not present today) — flag before building.

## Device/Relay Proof Profile
**host-only for closure.** No ML-KEM / relay / multi-device boundary is involved; all behavior is provable at unit/widget/migration tiers + a real-SQLCipher repo test.
- Optional polish (NOT a gate): on-device smoke of swipe feel, focus-collapse motion, and reduced-motion on a real iPhone/Pixel — manual, post-host-green.
- No `classify_path`/dart-define/`--scenario` registration (no `integration_test/` simulator scenario added). `feed_performance_test.dart` runs via its existing perf harness on a device/sim, not the host glob.

## Acceptance Gates  (literal — copy/paste, with expected counts)
> **Count protocol:** at **P0** (before any edit) run each preservation gate once and **pin the real baseline number** in place of every `<pin@P0>` placeholder below (e.g. `# expect: 824 passed / 0 fail`). A *count* regression (fewer passed than baseline) is then a detectable failure, not just a red. Re-pin the feed-family count at P8 after `FEED_TESTS` is updated.
```bash
# --- RED (before production edits) — must FAIL for the documented reason ---
flutter test test/features/feed/application/feed_pending_projection_test.dart   # TC-01..03
flutter test test/core/utils/ring_avatar_generator_test.dart --plain-name 'accentColorForPeerId'  # TC-08
flutter test test/core/database/migrations/092_feed_cleared_threads_test.dart   # TC-28
flutter test test/features/feed/presentation/widgets/letter_bubble_test.dart    # TC-11..15

# --- Direct GREEN (after each phase) ---
flutter test test/features/feed/                       # expect: <pin@P8> passed / 0 fail (feed host floor)
flutter test test/core/utils/ring_avatar_generator_test.dart test/core/theme/ test/core/database/migrations/092_feed_cleared_threads_test.dart
flutter test test/l10n/feed_strings_parity_test.dart && flutter gen-l10n

# --- Preservation sentinels (must stay green — pin counts at P0) ---
./scripts/run_test_gates.sh feed                       # Feed / Surface Gate (after FEED_TESTS updated): expect <pin@P8> passed
flutter test test/features/orbit/ test/features/orbit2/   # expect: <pin@P0> passed / 0 fail (UnreadCountBadge reuse intact)
flutter test test/features/conversation/                  # expect: <pin@P0> passed / 0 fail (QuotePreviewBar + moved reactions/edit/delete intact)
flutter test test/features/feed/presentation/screens/feed_contract_preservation_test.dart  # posts/share deps reachable (TC-32)
# Broad host sweep (run_host_test_gates.sh confirmed present):
./scripts/run_host_test_gates.sh feature-host-all      # expect: <pin@P0> passed / 0 fail

# --- Migration (real SQLCipher) ---
flutter test test/core/database/migrations/092_feed_cleared_threads_test.dart
flutter test test/features/feed/data/feed_cleared_repository_test.dart

# --- Perf preservation (device/sim harness) ---
flutter test integration_test/feed_performance_test.dart   # frame budgets green on new fixtures

# --- Hygiene ---
flutter analyze            # 0 new issues (also proves all 3 external constructor sites compile against the new contract)
git diff --check
```
> `scripts/run_host_test_gates.sh` is confirmed present (subcommands: `1to1 | host-all | feature-host-all | core-host-all | performance-host | move-feature`); `feature-host-all` is the broad sweep above.

## Known-Failure Interpretation
- **Expected RED:** every RED-catalog test before its phase lands (documented reason per entry).
- **Pre-existing dirty:** the graphify-arch/* and `0f3e9170 "new Feed"` snapshot churn already in the tree — record in P0; do not revert.
- **Environment blocker (NOT product):** `feed_performance_test.dart` needs a sim/device; absence is not a closure blocker for host gates.
- **Scope drift (BLOCKING):** any failure in orbit/conversation/posts/notification suites caused by deleting a shared widget or changing read-state semantics — fix in scope, do not suppress.

## Done Criteria
- [ ] RED added first per phase, failed for the expected reason.
- [ ] Mutation-verified (each fix has a re-red revert per the matrix).
- [ ] Direct GREEN + preservation sentinels + `run_test_gates.sh feed` pass.
- [ ] Migration 092 has a real-SQLCipher setUp test (create + idempotent + preserve + clean-open-at-v92).
- [ ] No OS-boundary/multi-device path (host-only closure); optional device motion smoke noted.
- [ ] `FEED_TESTS` array updated (3 removed, new curated feed tests added) and verified via `run_test_gates.sh feed`.
- [ ] l10n keys in en/ar/de; `flutter gen-l10n` clean.
- [ ] `flutter analyze` 0 new (all 3 external constructor sites compile); `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do **not** delete `UnreadCountBadge` or `QuotePreviewBar` widget files (orbit/conversation own them) — remove feed *usages* only.
- Do **not** change `glowColorForPeerId` (70/50) or any non-feed avatar screen.
- Do **not** make swipe-dismiss touch read-state / unread badge / Orbit / archive (INV-2).
- Do **not** add an `rtl` model field (render-derived only).
- Do **not** build "Replay demo letters" / a demo letter source in production.
- Do **not** change conversation-view, posts, Orbit, or notification routing beyond receiving the moved interaction entry points.

## Accepted Differences / Intentionally Out Of Scope
- "Replay demo letters" reset — dev-only / not shipped (real-data feed).
- Swipe-right commit does not navigate; the "Open full conversation ↗" link is the only feed→conversation navigation.
- Exact `--teal-400/--green-500/--teal-fill-08/--green-fill-15/--blur-letter` hexes are derived from the spec token names + screenshots + existing palette; a design-system handoff can refine the literal values without changing structure.
- Keeping a minimal `FeedHeader` and the gated `orbit2` tab (reversible).

## Dependency Impact
- A follow-up "conversation interaction parity" session depends on this if the conversation view lacks any of reactions/edit/delete/copy that this plan removes from the feed (verify during P8; file a session if a gap exists).

## Reviewer Findings
Adversarial 3-reviewer + arbiter sufficiency pass (workflow `wf_b807a834-d4c`, 2026-06-20). Initial verdict **draft-needs-fixes**; all blocking + recommended fixes below have been **applied** to this revision:
- **Source corrections (applied):** external `FeedWired` constructor sites are **3, not 5** (`startup_router.dart:341`, `qr_scanner_wired.dart:383`, `first_time_experience_wired.dart:242`; the other two were comments); the send enum is **`SendChatMessageResult`** (`send_chat_message_use_case.dart:112`), not `SendMessageResult`; DB version constant is `app_database_version.dart:1` (=91→92); `test/l10n/l10n_integrity_test.dart` already enforces locale parity (new test scoped to feed-specific checks); `RingAvatar` has no glow-suppression param. Conversation view **already has** reactions/edit/delete/copy entry points (`message_context_overlay.dart` + `conversation_screen.dart:657-731`) — confirming Decision 3 is not a hidden new feature.
- **Vacuous-RED fixes (applied):** TC-32 reframed as a contract-preservation test (not RED-first); TC-09 re-anchored to the card renderers' real call sites (size 42→40/32 mutation).
- **Spec-totality fixes (applied):** added RED-catalog entries for TC-04/06/09/10/35 and new TC-15b (max-width), TC-18b (system real callback), TC-19b (bottom padding), TC-37 (Undo-vs-re-surface), TC-38 (shared-widget survival); strengthened TC-19 (≥3-card fixture + NavBar fade-not-keyboard-hide) and TC-20/TC-21 (resting-absence discriminator; group composer sources the group — Decision G).
- **Gate fixes (applied):** added the count-pinning protocol (capture baselines at P0/P8); migration test gained the clean-open-at-v92 assertion.
- **Confirmed strengths (uncontested):** mutation-verification complete; catalog-level non-vacuous REDs with flow-event discriminators; real-SQLCipher migration test; host-only scope justified; refuted findings recorded; per-test harness registration present.

## Arbiter Decision
Structural blockers: **none remaining** after this revision. Deferred details: exact `--teal-400/--green-500/*-fill/--blur-letter` hex values (design-system handoff; structure unaffected); behavioral routing test for the 3 external feed-entry sites (compile-only via `flutter analyze` — documented gap in Risks). Accepted differences: as listed in §"Accepted Differences". **Verdict: structurally sufficient — ready for execution hand-off.**

## Final Execution Verdict
**EXECUTED & HOST-GREEN (2026-06-20).** All 9 phases (P1→P8) landed TDD via orchestrated workflows + graphify-arch grounding; full-replacement complete. Gates: `flutter test -j 1 test/features/feed/` **+280 / 0 skipped / 0 failed**; `run_test_gates.sh feed` **+200**; `flutter analyze` 0 new (only 2 PRE-EXISTING integration-harness `dbExistsMessageByContent` errors); preservation conversation **+1264**, orbit2 **+57**, orbit green (pre-existing isolation flakes only); migration 092 / DB v92 (onCreate+onUpgrade) + real-FFI tests; l10n en/ar/de + gen-l10n clean; `git diff --check` clean. 17 dead feed-only widget/util files + 93 skipped removed-behavior tests + 3 obsolete integration tests deleted; shared `UnreadCountBadge`/`QuotePreviewBar`/`SwipeToQuoteBubble` kept (INV-9). `FEED_TESTS` rebuilt (25 entries).

**Adversarial review (workflow `wf_c4bae0e8-19e`, 5 dimensions × verify):** INV-1/2/4/5/6/7/8/9 + all 6 Scope-Guard items + projection/dedup/pin/gesture-arena + test integrity all PASS. Found+FIXED 3 production bugs that every gate had missed (now regression-tested, mutation-verified):
1. **INV-3 (HIGH):** swipe-right commit never marked the conversation read in prod (`markThreadRead` closure unwired) → wired read-mark + badge refresh into `_onSwipeCommit` (REG-INV3).
2. **(HIGH):** focused CONNECTION-card commit re-pinned the cleared card + leaked focus (focus id bare vs swipe id `connection:`) → `_endFocusSessionForThread` strips the prefix (REG-CONN-FOCUS).
3. **(MEDIUM):** leaving the feed surface (tab switch / host-swipe / open-conversation) left the composer mounted + thread pinned (`_clearFeedComposerFocus` cleared only the legacy field) → now ends the new focus session (REG-LEAVE-SURFACE).

Also found+fixed (review of the dedup): a **connection-vs-thread double-render** (a contact with a 1:1 thread also showed a "tap to say hi" system letter) → suppressed in `projectPendingFeed`; this exposed a latent **append-stay** bug (focused card vanished on reply because the projection drops "answered" threads, previously masked by the duplicate connection card) → store-level focus PIN, cleared on defocus/commit/dismiss.

**Residual / follow-ups (non-blocking):** (a) `feed_performance_test.dart` (TC-36) has a minimal compile-fix only — full perf-fixture re-author to the letter-card model is device-harness scope; (b) TC-28 fresh-install onCreate wiring is unguarded by host tests (onCreate closure not importable — acknowledged limitation); (c) optional on-device motion/gesture smoke; (d) pre-existing orbit/orbit2 `l10n_integrity_test` failures (`de:orbit_preview_photo` plural false-positive + 3 hardcoded literals) are out of feed scope. No device/relay/multi-device path involved (host-only closure achieved).

**Pre-execution dry-run (workflow `wf_2aa14fa4-a05`, 2026-06-20):** read-only `Plan`-agent walkthrough of all 9 phases against HEAD → **ready-after-amendments**. All 6 cross-phase blockers + per-phase corrections folded into §"Dry-Run Execution-Readiness Amendments" (FeedScreen-not-FeedWired reduction; store-held cleared filter; cleared-overlay store + TC-37 winner; `markCleared(markRead:)`; watermark key shape; INV-1 exact predicate; corrected call-site counts; l10n forward-pull; shared-widget keep list; migration onCreate+onUpgrade dual wiring). No structural blockers remain; proceed in order **P1 → P0 artifact → P3 (pure-domain) → P2 → P4 → P5 → P6 → P7 → P8**.
