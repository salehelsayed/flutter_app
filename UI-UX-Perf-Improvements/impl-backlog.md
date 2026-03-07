# UI/UX Performance Implementation Backlog

This backlog converts the read-only UI/UX performance audit into an execution plan.

Ranking rule:
- Impact: expected improvement to perceived speed, scroll smoothness, input responsiveness, and route transition quality.
- Effort: engineering complexity, refactor risk, and number of surfaces touched.
- Order below is optimized for impact vs effort, not just absolute impact.


  Will Definitely Change Visible UX

  - PERF-02 Loading skeletons and navigate-first hydration
      - Changes loading states, empty-to-loaded transitions, and route-entry experience.
      - Steady-state screen design can stay the same.
  - PERF-04 Reduce blur on repeated list surfaces
      - This will change the visual style of cards/messages/chrome because blur is a core
        part of the current look.
      - Even if done carefully, the appearance will be noticeably different.

  May Cause Minor Visible Changes

  - PERF-07 Virtualize Feed with slivers/builders
      - Not intended as a redesign, but spacing, insert timing, and scroll behavior can
        shift slightly.
  - PERF-08 Virtualize Orbit with slivers/builders
      - Same as Feed: mostly structural, but some small layout/scroll presentation
        differences are likely.
  - PERF-11 Remove remaining nested layout hotspots
      - Likely small changes only, such as username edit width behavior or preview fade
        behavior.

  Should Not Intentionally Change Appearance

  - PERF-00 Baseline and regression gates
  - PERF-01 Move avatar lookup/caching out of widget build
  - PERF-03 Isolate recording/processing/progress state
  - PERF-06 Make group conversation updates incremental
  - PERF-09 Replace full Feed reloads with incremental thread state
  - PERF-10 Replace full Orbit reloads with incremental state updates

  Least Visually Risky First
  If you want performance gains while preserving the current look, start with:

  1. PERF-01
  2. PERF-03
  3. PERF-06
  4. PERF-09
  5. PERF-10

## Cross-Cutting Rule

### PERF-00 Baseline and Regression Gates

Impact: Medium  
Effort: Low  
Priority: Mandatory prerequisite

Scope:
- Capture baseline traces for Feed, Orbit, Conversation, Group Conversation, onboarding, and QR flows.
- Record build/raster timing during steady scroll, route push, typing, recording, and media attach flows.
- Use the same device class for before/after comparisons.

Primary files:
- `lib/features/feed/...`
- `lib/features/orbit/...`
- `lib/features/conversation/...`
- `lib/features/groups/...`

Acceptance:
- Every task below ships with before/after profile notes.
- We keep a short benchmark table in this file or a sibling profiling doc.
- No task is marked done without verifying route latency, scroll smoothness, and input responsiveness on device.

Suggested target gates:
- No obvious jank while scrolling 50+ feed/orbit items on a mid-range device.
- Typing and recording UI stay responsive during background updates.
- New routes show content or a skeleton immediately instead of a blank frame.

## Ranked Backlog

| Rank | ID | Item | Impact | Effort | Why It Is Here |
| --- | --- | --- | --- | --- | --- |
| 1 | PERF-01 | Move avatar lookup and caching out of widget build | High | Low | Removes sync file I/O from hot scroll paths with limited refactor scope |
| 2 | PERF-02 | Add loading skeletons and navigate-first hydration | High | Low | Fastest perceived-performance win across Feed and conversation entry points |
| 3 | PERF-03 | Isolate recording, processing, and progress state from page rebuilds | High | Low | Eliminates high-frequency full-screen rebuilds during voice/video workflows |
| 4 | PERF-04 | Reduce blur on repeated list surfaces | High | Medium | Large raster/paint win without changing product flows |
| 5 | PERF-06 | Make group conversation updates incremental | High | Medium | Good payoff with smaller blast radius than Feed or Orbit |
| 6 | PERF-07 | Virtualize Feed with slivers or builders | Very High | Medium-High | Foundational scale fix for the most important surface |
| 7 | PERF-08 | Virtualize Orbit with slivers or builders | High | Medium-High | Same scaling issue as Feed, slightly less critical |
| 8 | PERF-09 | Replace full Feed reloads with incremental thread state | Very High | High | Biggest long-term responsiveness win in the app |
| 9 | PERF-10 | Replace full Orbit reloads with incremental state updates | High | High | Prevents repeated contact-wide DB work on every event |
| 10 | PERF-11 | Remove remaining nested layout hotspots | Medium | Low | Cleanup item after major wins to reduce residual layout cost |

## Current UI/UX Baseline

Use this section as the "before" reference when validating changes.

### Global Visual Language

Current look:
- Major screens sit on a dark animated ambient background with moving glow orbs.
- The app uses a frosted-glass style heavily: blurred headers, blurred cards, blurred composer areas, and a blurred floating nav bar.
- White translucent fills, soft borders, and teal/green accents are used more than solid surfaces.
- Motion is present in many places: background drift, card entrances, list row entrances, empty-state pulses, and route transitions.

What to watch in every performance change:
- Does the screen still feel like the same product, or did it become flatter, less luminous, or less animated?
- Did spacing, card height, scroll physics, route timing, or visual hierarchy change?
- Did any optimized surface start popping in, flickering, or changing order in a noticeable way?

### Feed

Current look:
- Animated ambient background.
- Fixed top header with profile/avatar area.
- Floating glass bottom nav bar.
- Large frosted cards with rounded corners and soft glow.
- Open and collapsed thread cards both look layered and premium.
- Inline reply field is a glossy pill.
- Connection cards are oversized hero cards with strong celebratory styling.

Where to observe:
- App launch into Feed.
- Feed idle state.
- Feed scrolling with many cards.
- Expanding and collapsing a card.
- Sending an inline reply.
- Receiving a new message or reaction while Feed is open.

### Orbit

Current look:
- Animated ambient background.
- Large orbital hero visualization at the top.
- Search trigger and close button float over content.
- Friend rows are translucent rounded cards.
- Swipe actions reveal behind rows.
- Intros tab is visually part of the same scroll surface.

Where to observe:
- Opening Orbit from Feed.
- Scrolling the friends list.
- Opening search and typing.
- Switching between all, archived, and intros.
- Receiving a new message while Orbit is open.

### Conversation (1:1)

Current look:
- Frosted sticky header over animated background.
- Full-width glass message cards with blur and edge accents.
- Composer is a blurred bottom surface with animated send button.
- Attachment strip sits above the composer.
- Reactions, intro banner, and recording overlay add layered UI states.

Where to observe:
- Opening a conversation from Feed.
- Opening a conversation from Orbit.
- Scrolling long message history.
- Receiving a new message while the thread is open.
- Recording voice.
- Attaching image/video.
- Long-pressing to react.

### Group Conversation

Current look:
- Similar overall tone to 1:1 conversation, but with a simpler header.
- Messages use the same glass letter-card language.
- Composer and attachment strip behave similarly to 1:1.

Where to observe:
- Opening a group from Feed or Orbit.
- Receiving new group messages live.
- Uploading media or voice.
- Scrolling older messages with media attachments.

### Settings

Current look:
- Frosted sticky header.
- Profile avatar and username at the top.
- Glass-style settings cards.
- Floating nav bar remains visible.

Where to observe:
- Opening Settings from Feed avatar tap.
- Viewing profile section and avatar rendering.
- Scrolling the settings page.

### First-Time Experience and QR Surfaces

Current look:
- Strong ambient background presence.
- Staggered entrance animations.
- QR card and scan card appear as hero elements.
- Empty circle state pulses continuously.

Where to observe:
- First-time experience screen.
- QR display screen.
- QR scanner screen.

## Observation Routes

Use these exact routes for before/after comparison videos or screenshots.

| Route | What to capture | Relevant PERF items |
| --- | --- | --- |
| Launch app into Feed | First paint, loading state, first scroll | PERF-02, PERF-04, PERF-07, PERF-09 |
| Feed -> expand thread card | Card expansion, preview list, inline reply | PERF-04, PERF-07, PERF-09, PERF-11 |
| Feed -> tap thread -> conversation | Route push timing, shell visibility, first loaded messages | PERF-02, PERF-04, PERF-09 |
| Feed idle while new message arrives | Reorder, unread badge, reaction update, nav badge | PERF-07, PERF-09 |
| Orbit open -> scroll -> search | Hero stability, row rendering, search responsiveness | PERF-08, PERF-10 |
| Orbit idle while new message arrives | Row reorder, unread badge change, intros count | PERF-08, PERF-10 |
| Conversation open -> record voice | Header stability, list stability, composer responsiveness | PERF-03, PERF-04 |
| Conversation open -> attach video | Processing progress, composer behavior, list stability | PERF-03, PERF-04 |
| Group conversation while messages arrive | Incremental insertion, media stability, scroll feel | PERF-03, PERF-06 |
| Settings open | Header appearance, avatar rendering, scroll smoothness | PERF-01, PERF-04 |
| FTE / QR display | Ambient motion, staged entrances, empty-state motion | n/a |

## PERF Observation Map

This maps each backlog item to the part of the app it can visibly affect.

| PERF | Primary surfaces to inspect | What it looks like now | What might look or feel different after |
| --- | --- | --- | --- |
| PERF-00 | All major routes | No visible product change intended | Only profiling discipline and acceptance checks change |
| PERF-01 | Feed cards, Orbit rows, conversation headers, message cards, Settings avatar, FTE avatar | Avatars render from bytes, file, ring avatar, or fallback icon; current behavior may mask sync disk work | Appearance should stay the same; watch for avatar pop-in, fallback flashes, stale avatars, or delayed image load |
| PERF-02 | Feed initial load, Orbit initial load, route into conversation | Some routes can feel empty or data-gated before content appears | Skeletons, placeholders, or earlier shell rendering will be visible; this changes loading UX intentionally |
| PERF-03 | 1:1 conversation composer, group composer, recording overlay, video processing states | During recording or processing, the whole screen may feel heavier because broad rebuilds happen | Appearance should stay nearly identical; watch for smoother composer updates and a more stable header/list during recording |
| PERF-04 | Feed cards, connection cards, message bubbles, letter cards, conversation header, composer, nav bar | Strong frosted-glass blur is a defining part of the current aesthetic | Surfaces may look flatter, clearer, less diffused, or less glowy; this is the biggest deliberate appearance risk |
| PERF-06 | Group conversation message list and media attachments | New group activity can cause broad reload behavior | Look should stay the same; watch for less list churn, less attachment flicker, and more stable insertion behavior |
| PERF-07 | Feed list, card spacing, section divider placement, scroll behavior | Feed is currently a full eager scroll surface with premium large cards | No redesign intended; watch for small differences in scroll feel, item insertion timing, cached card state, and spacing consistency |
| PERF-08 | Orbit list, intros tab, search results, swipe rows | Orbit currently combines hero content and eager list rendering in one surface | No redesign intended; watch for search result timing, row animation changes, swipe behavior, and list spacing |
| PERF-09 | Feed thread ordering, unread badges, reactions, inline reply state, session reply indicators | Feed often refreshes as a whole after data changes | No redesign intended; watch for different reorder timing, state preservation, reaction updates, and whether focused inputs remain stable |
| PERF-10 | Orbit row ordering, unread counts, archived rows, blocked state, intros count | Orbit often refreshes large sections after incoming events | No redesign intended; watch for row order timing, badge updates, and whether filters/search preserve context |
| PERF-11 | Username edit width, intros list layout, friend picker list, preview fade behavior | A few small layout behaviors are currently shaped by intrinsic sizing, shrink-wrapped lists, and shader fades | Minor visible changes are possible in text-field width, preview fading, and list spacing; should be subtle |

## Backlog Details

### PERF-01 Move Avatar Lookup and Caching Out of Widget Build

Impact: High  
Effort: Low

Problem:
- `UserAvatar` checks the filesystem synchronously during `build`.
- The widget is used in Feed, Orbit, Conversation, Settings, and multiple headers.

Primary files:
- `lib/features/home/presentation/widgets/user_avatar.dart`
- `lib/features/feed/presentation/widgets/connection_card.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/widgets/conversation_header.dart`
- `lib/features/orbit/presentation/widgets/friend_row.dart`
- `lib/features/orbit/presentation/widgets/orbital_visualization.dart`

Tasks:
- Move avatar path existence checks to the wired/state layer or a dedicated avatar cache service.
- Pass resolved avatar state into `UserAvatar` as bytes, file path, or `ImageProvider`.
- Memoize missing avatar results so repeated fallback checks are avoided.
- Audit all hot list surfaces to ensure no sync disk access remains in `build`.

Acceptance:
- No `existsSync`, file probing, or synchronous avatar resolution inside `build`.
- Scrolling Feed and Orbit does not trigger repeated avatar disk checks.
- Avatar fallback behavior remains identical.

### PERF-02 Add Loading Skeletons and Navigate-First Hydration

Impact: High  
Effort: Low

Problem:
- Feed can render as empty while loading.
- Some navigation paths wait for data before pushing the next screen.
- This makes the app feel slower than it is.

Primary files:
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`

Tasks:
- Add skeleton cards or placeholder rows for Feed and Orbit initial load.
- Push conversation routes immediately, then hydrate message content in place.
- Keep optimistic content visible during refresh instead of replacing sections with emptiness.
- Ensure route transitions always land on a stable scaffold, header, and composer quickly.

Acceptance:
- No blank Feed state during initial load.
- Opening a conversation shows shell UI immediately.
- Perceived route speed improves even when data load time stays the same.

### PERF-03 Isolate Recording, Processing, and Progress State From Page Rebuilds

Impact: High  
Effort: Low

Problem:
- Voice recording duration, amplitude, and video processing progress update the entire page state.
- Message list, header, and non-changing UI rebuild during high-frequency updates.

Primary files:
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/features/conversation/presentation/widgets/recording_overlay.dart`

Tasks:
- Move recording duration, waveform, and processing progress into small isolated state holders.
- Drive recording UI with `ValueNotifier`, scoped `StreamBuilder`, or a dedicated controller widget.
- Keep message list and header outside the rebuild path of progress updates.

Acceptance:
- Recording and video processing updates do not rebuild the message list.
- Typing remains smooth while recording UI is active.
- No visible layout jitter in the composer during progress updates.

### PERF-04 Reduce Blur on Repeated List Surfaces

Impact: High  
Effort: Medium

Problem:
- The app uses many `BackdropFilter`s inside scrolling content and above animated backgrounds.
- This is expensive in Feed cards, message cards, headers, and bottom chrome.

Primary files:
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/connection_card.dart`
- `lib/features/feed/presentation/widgets/message_bubble.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/widgets/conversation_header.dart`
- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`

Tasks:
- Keep blur only on a few top-level chrome surfaces per screen.
- Replace repeated card-level blur with translucent fills, gradients, borders, and static shadows.
- Validate visual parity with screenshots before and after.
- If blur remains on a list surface, add explicit justification in code comments or the design note.

Acceptance:
- Repeated message/feed cards no longer use heavy blur.
- The app preserves the visual language without stacking multiple blur layers in scrollable content.
- Raster times improve during Feed and conversation scroll.

### PERF-06 Make Group Conversation Updates Incremental

Impact: High  
Effort: Medium

Problem:
- Group conversation currently reloads full message history, media maps, and pending downloads when new group messages arrive.

Primary files:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`

Tasks:
- Append or update incoming group messages in memory instead of reloading the whole thread.
- Resolve or download media only for changed messages.
- Avoid rebuilding the whole `mediaMap` on each incoming event.
- Preserve scroll position during incremental updates.

Acceptance:
- New group messages appear without full list churn.
- Existing attachments do not flicker or re-resolve unnecessarily.
- Group conversation feels stable during active multi-user chat.

### PERF-07 Virtualize Feed With Slivers or Builders

Impact: Very High  
Effort: Medium-High

Problem:
- Feed renders all content eagerly inside `SingleChildScrollView` plus `Column`.
- Every off-screen card still pays layout and build cost.

Primary files:
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/connection_card.dart`
- `lib/features/feed/presentation/widgets/introduction_connection_card.dart`

Tasks:
- Replace `SingleChildScrollView` + `Column` with `CustomScrollView` or `ListView.builder`.
- Preserve section logic for unread/active items and lower-priority items.
- Convert static gaps and divider insertions into sliver/list items.
- Keep the floating nav bar behavior unchanged.

Acceptance:
- Feed only builds visible cards plus a small cache extent.
- Scroll smoothness remains stable as thread count grows.
- Feed memory and layout cost scale linearly with visible content, not total content.

### PERF-08 Virtualize Orbit With Slivers or Builders

Impact: High  
Effort: Medium-High

Problem:
- Orbit merges friends and groups into a full eager list inside a `SingleChildScrollView`.
- Search and filter changes rebuild the entire surface.

Primary files:
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/orbit/presentation/widgets/friend_row.dart`
- `lib/features/orbit/presentation/widgets/swipeable_friend_row.dart`
- `lib/features/introduction/presentation/widgets/intros_tab.dart`

Tasks:
- Convert the scrollable list section to a builder-backed list or sliver stack.
- Keep the orbital hero section separate from the list rendering path.
- Avoid `shrinkWrap` list usage inside the intros tab when embedded in Orbit.
- Ensure swipe interactions still work with virtualization.

Acceptance:
- Orbit builds only visible rows.
- Search/filter changes do not cause full eager rebuild of the entire merged list.
- Intros content scales without nested non-virtualized list cost.

### PERF-09 Replace Full Feed Reloads With Incremental Thread State

Impact: Very High  
Effort: High

Problem:
- Feed state is recomputed from the database for almost every meaningful event.
- `loadFeed()` loops contacts, messages, attachments, and group messages repeatedly.

Primary files:
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/application/load_feed_use_case.dart`
- `lib/features/feed/domain/utils/group_messages_into_threads.dart`
- `lib/features/feed/domain/utils/group_group_messages_into_threads.dart`

Tasks:
- Introduce an in-memory feed thread store keyed by contact or group id.
- Update only the affected thread on new chat, reaction, intro, read-state, or group events.
- Separate unread-count refresh from full thread reconstruction.
- Defer full DB reload to cold start, explicit refresh, or data integrity fallback.

Acceptance:
- Incoming single-message events update one thread, not the whole feed.
- Reaction changes update one message subtree, not all feed items.
- Feed remains responsive as contact and message counts grow.

### PERF-10 Replace Full Orbit Reloads With Incremental State Updates

Impact: High  
Effort: High

Problem:
- Orbit reloads contact-wide data on new messages, contact updates, and group events.
- The underlying use case performs multiple queries per contact.

Primary files:
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/orbit/application/load_orbit_data_use_case.dart`
- `lib/features/orbit/application/load_orbit_groups_use_case.dart`

Tasks:
- Introduce an in-memory orbit state model for active, archived, blocked, and grouped intros.
- Update friend rows and unread counts incrementally from streams.
- Avoid recomputing all friend metadata for isolated changes.
- Cache search/filter projections separately from source state.

Acceptance:
- Single incoming events do not trigger full Orbit reloads.
- Search remains responsive while new events arrive.
- Orbit state updates feel immediate and stable with larger data sets.

### PERF-11 Remove Remaining Nested Layout Hotspots

Impact: Medium  
Effort: Low

Problem:
- There are still smaller layout patterns that add unnecessary cost.
- These include `IntrinsicWidth`, nested `shrinkWrap` lists, and shader-masked preview lists.

Primary files:
- `lib/features/home/presentation/widgets/editable_username_widget.dart`
- `lib/features/introduction/presentation/widgets/intros_tab.dart`
- `lib/features/introduction/presentation/screens/friend_picker_screen.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`

Tasks:
- Replace `IntrinsicWidth` in username editing with a fixed or bounded layout approach.
- Remove `shrinkWrap` where the parent already constrains the list.
- Re-evaluate `ShaderMask` usage in message preview; prefer simpler fade approaches if profiling shows cost.
- Audit similar patterns across picker and settings surfaces.

Acceptance:
- No unnecessary `IntrinsicWidth` or nested shrink-wrapped builders remain on hot paths.
- Layout passes are reduced on text entry and list rendering.

## Suggested Delivery Plan

### Phase 1: Fast Wins

Items:
- PERF-00
- PERF-01
- PERF-02
- PERF-03
- PERF-04

Expected outcome:
- Immediate improvement to perceived responsiveness and scroll smoothness without major architecture changes.

### Phase 2: Medium Refactors

Items:
- PERF-06
- PERF-07
- PERF-08

Expected outcome:
- Feed and Orbit become scalable for larger datasets.
- Group chat stops feeling unstable during active updates.

### Phase 3: Structural State Refactors

Items:
- PERF-09
- PERF-10
- PERF-11

Expected outcome:
- Event-driven UI updates stop forcing full DB-to-UI recomputation.
- Performance improvements hold as data volume grows.

## Definition of Done

A backlog item is done only when:
- The implementation matches the scope above.
- The UI behavior remains functionally correct.
- Before/after profiling notes are captured.
- Scroll, typing, route push, and media workflows were verified on device.
- No new user-facing visual regressions are introduced without design sign-off.







