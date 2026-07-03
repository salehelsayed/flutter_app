# 194 - Orbit Inner-Circle Per-Node Unread Indicator ("Messenger Orbit")

**New Feature** (product-confirmed: alternative **B** chosen from the approved interactive mockup
`Test-Flight-Improv/194-orbit-unread-indicator-mockups.html`; evidence: 2-agent extraction workflow
`wf_315ce45e-25f` + very-thorough Explore sweep + inline source verification of every load-bearing claim)

---

## 1. Problem Statement

Since plan 193, the **Inner-Circle view is the default surface of the Orbit tab**: on every entry the
user lands on the orbital visualization (`OrbitViewMode.innerCircle`, reset on every rising edge —
`orbit_wired.dart:493-497`). On that surface, a friend node gives **no indication whatsoever that the
friend has sent messages the user hasn't read**.

- The data already exists per friend: `OrbitFriend.unreadCount` (`orbit_friend.dart:16`) is populated
  on every load/refresh from `messageRepo.getUnreadCountForContact` (via
  `ConversationThreadSummary.unreadCount`, `load_orbit_data_use_case.dart:137,175`).
- The **all-chats list view** renders it (green `UnreadCountBadge` pill on rows,
  `friend_row.dart:144-150`), and the nav bar renders aggregate counts (Feed tab).
- The **inner-circle nodes render nothing**: neither `OrbitalVisualization`
  (`orbital_visualization.dart`) nor `OrbitalAvatar` (`orbital_avatar.dart`) reads `unreadCount`.

So on the default landing surface of the app's social map, user-a cannot see that user-b sent them a
message. They must toggle to the all-chats view, or leave for the Feed tab, to learn who wants their
attention. This inverts the point of making Inner-Circle the default (193): the most-featured surface
is the least informative one.

**Affected**: all users, all platforms, whenever ≥1 inner-circle friend has `unreadCount > 0` — a
routine daily state for a messenger.

### Chosen product design (approved mockup, alternative B)

A friend node with `unreadCount > 0` gets a **"messenger orbit"**: a thin accent ring hugging the
avatar with small glowing satellites revolving around it — **one satellite per unread message, capped
at 3** — in the app's existing **green unread accent** (`#1DB954` family). **No numerals** on the
node. The visual vocabulary is borrowed from the contact-profile hero orbit the user singled out
(`_OrbitRingsPainter` + 28s rotation, `contact_profile_screen.dart:60,77-80,242-247,730-776`):

| Design element | Approved value (from mockup B) | Donor reference |
|---|---|---|
| Ring | ~1.1 logical px stroke, accent-tinted, circular, hugging the node (~1.3-1.4× avatar radius) | ring stroke 1.1px (`contact_profile_screen.dart:742-747`) |
| Satellites | min(unreadCount, 3) dots; halo ≈2.6× core radius at ~0.16 alpha, core at ~0.95 alpha | satellite halo/core (`:756-765`) |
| Satellite phases | ~34° / ~189° / ~292° initial angles, fixed relative phase | angles 0.6/3.3/5.1 rad (`:751-770`) |
| Motion | rigid rotation of the whole satellite field, linear, infinite, ~9s/revolution (sped up from the profile's 28s so it reads as *activity*) | 28s repeat controller (`:77-80`) |
| Accent | green unread family `#1DB954`→`#18A349` (the app's existing unread semantic) | `unread_count_badge.dart:71` |
| Count display | none (no numerals) — satellites only | product decision (B, not A/C) |
| Clearing | indicator disappears when the friend's messages become read from ANY surface (opening the chat from Orbit, from a notification, from Feed/all-chats) | existing `unreadCount` projection |
| Reduce-motion | rotation must freeze under OS reduce-motion; the indicator itself must remain visible statically | convention `cosmic_background.dart:82-102` |

## 2. Impact Analysis

| Dimension | Assessment |
|---|---|
| Severity | Degrades experience (no data loss, no reliability impact) — a glanceability gap on the default surface |
| Frequency | Every time an inner-circle friend has unread messages and the user is on (or returns to) the Orbit tab — daily-path |
| User-visible consequence | The default view looks identical whether nobody or everybody has written; users learn to distrust/skip the inner circle and route through Feed or the list view |
| Workaround | Toggle to all-chats view (193 button) where the green pill shows, or use the Feed tab badge |
| Risk of NOT fixing | The 193 default-view investment underdelivers; "orbit as ambient social radar" value proposition is broken |
| Platform differences | None expected (pure Flutter presentation; reduce-motion flags exist on both iOS and Android) |

## 3. Current State

### 3.1 Data: per-friend unread count (exists, correct, unused on this surface)

| Artifact | File:line | Fact |
|---|---|---|
| `OrbitFriend.unreadCount` | `lib/features/orbit/domain/models/orbit_friend.dart:16` (default 0 at `:32`) | model field, populated on every build |
| Population | `lib/features/orbit/application/load_orbit_data_use_case.dart:137` | `unreadCount: summary.unreadCount` |
| Source query | `load_orbit_data_use_case.dart:175` | `messageRepo.getUnreadCountForContact(peerId)` |
| Ordering | `load_orbit_data_use_case.dart:204-210` | friends sorted `lastMessageTimestamp` DESC |
| Read-marking | `lib/features/conversation/application/mark_conversation_read_use_case.dart:7-30` | `markConversationAsRead(contactPeerId)` zeroes the count in DB |

### 3.2 Presentation: what renders unread today

| Surface | Renders unread? | File:line |
|---|---|---|
| All-chats list rows (193 `allChats` view) | YES — green pill `UnreadCountBadge` (`#1DB954`→`#18A349`, 99+ cap, 300ms elasticOut appear, pulse on change, instant vanish at 0) | `friend_row.dart:144-150`, `unread_count_badge.dart:25-32,58-92` |
| Inner-circle nodes (193 default view) | **NO** — neither the visualization nor the avatar widget reads `unreadCount` | `orbital_visualization.dart`, `orbital_avatar.dart` |
| Nav bar Orbit tab badge | Not unread — it shows `projection.reviewCount` (pending intros + group invites) | `orbit_screen.dart:307-337` |
| Nav bar Feed tab badge | Aggregate unread (red gradient), not per-friend | `nav_bar_button.dart:100-140` |

### 3.3 Inner-circle geometry (the host surface)

- Canvas 320×320, center 160 (`orbital_visualization.dart:23-24`).
- Ring 1: radius 62, **first 5 friends**, 38px avatars; Ring 2: radius 108, **next 8 friends**, 30px
  avatars, +15° stagger (`:25-28,45-47,169-179`).
- **13-friend cap**; friends 14+ collapse into a "+N" `OverflowBadge` (`:47`,
  `overflow_badge.dart:25-93`). Because ordering is `lastMessageTimestamp` DESC, a friend who just
  messaged normally jumps into the visible 13 — but a friend can hold `unreadCount > 0` while 13
  other conversations have newer messages, leaving the unread friend **hidden in the overflow**.
- Entrance: per-avatar scale+fade, staggered `globalIndex * 40ms`, gated by `motionEnabled`
  (`orbital_avatar.dart:21,75-82`).
- Node semantics today: `'Open chat with {username}'`, button (`orbital_visualization.dart:112,140`,
  `orbital_avatar.dart:124-125`). Tap opens the 1:1 conversation (`_onFriendTap`).
- The dashed teal/violet backdrop rings are static (`orbital_ring_painter.dart:8-59,79`).

### 3.4 Refresh triggers — when the projection (and thus any indicator) updates

Verified inventory of everything that re-reads `unreadCount` into the orbit projection
(`_refreshOrbitFriend` → `_publishAllProjections`, `orbit_wired.dart:742-783,360-363`):

| Trigger | Path | File:line |
|---|---|---|
| Incoming 1:1 message, Orbit active | listener → `_refreshOrbitFriend(peerId)` | `orbit_wired.dart:1643-1652` |
| Incoming message, Orbit off-screen | dirty-buffered (`_dirtyFriendPeerIds`) → replayed once on the inactive→active rising edge | `:1646-1648`, `_onAppShellChanged :477-490`, `_replayDirtyOrbitWork :503-526` |
| Opening the chat **from Orbit** (node tap or row tap) | background `markConversationRead` at push + `pushedRoute.whenComplete` → `_refreshOrbitFriend` on return | `:1979-1988`, `_markConversationReadInBackground :2017-2030` |
| External routes report changes (Feed-side conversation opens etc.) | `externalRouteChangesListenable` → `_applyRouteChanges` → `_refreshOrbitFriend` per changed contact / full `_loadOrbitData` | `:2049-2060` |
| Contact updates stream | `_refreshOrbitFriend(contact.peerId)` (dirty-buffered when inactive) | `:1673-1677` |
| Initial load / full reloads | `_loadOrbitData()` | `:580,608` |

**Not found**: any direct subscription to read-marking events. Surfaces that mark a conversation read
*without* traversing one of the paths above (candidate: notification-tap routing into the
conversation while Orbit is the active tab underneath — the pushed route has no orbit
`whenComplete` hook and no rising edge fires on pop) have **no verified refresh trigger**. Whether
the count on the Orbit surface goes stale in that window is exactly what the read-surface test cases
below must pin.

### 3.5 Motion conventions the feature must obey

- **Reduce-motion**: ambient animations check `MediaQuery.disableAnimations || accessibleNavigation`
  and freeze (`cosmic_background.dart:82-102`). `OrbitalAvatar` exposes `motionEnabled`
  (`orbital_avatar.dart:21,75-82`) but does not itself read MediaQuery.
- **Off-screen pause (163)**: the Orbit pane sits behind `TickerMode(enabled: isActive)` when it is
  not the selected shell tab — tickers pause, subscriptions stay live and dirty-buffer.
- **Performance**: `integration_test/orbit_performance_harness.dart` exercises the inner-circle view
  explicitly (193) with frame-budget expectations.

### 3.6 Existing tests and gates

| Asset | Covers | Does NOT cover |
|---|---|---|
| `test/features/orbit/presentation/widgets/orbital_visualization_test.dart` | ring caps 5/8, overflow >13, tap targets, semantics | any unread indicator |
| `test/features/orbit/presentation/widgets/orbital_avatar_test.dart` | entrance animation, border, tap | unread satellites, reduce-motion |
| `test/features/orbit/presentation/screens/orbit_wired_test.dart` | projections, listeners | unread-driven node state |
| `test/features/orbit/presentation/screens/orbit_view_split_test.dart` (193) | view toggle behavior | — |
| `test/l10n/orbit_strings_parity_test.dart` (193, TC-193-14) | en/ar/de ARB parity for orbit view-split keys | any new 194 strings |
| `scripts/run_test_gates.sh` | 193 registered `orbit_view_split_test.dart` + `orbit_strings_parity_test.dart` in GROUP_TESTS (`test/l10n` lives outside the feature-host glob — explicit append required) | 194 tests |

### 3.7 Branch context / hazards

- Branch `new-orbit` carries **uncommitted 193 work** (`orbit_view_mode.dart`,
  `orbit_view_toggle_button.dart`, edits in `orbit_screen.dart` / `orbit_wired.dart`); 194 layers on
  top of that working-tree state.
- `conversation_wired.dart` has been edited by **concurrent sessions** recently — read-surface line
  refs there (e.g. `_markAsRead` on route entry) must be re-verified at implementation time.
- 193 memory notes a **pre-existing RED `l10n_integrity` gate on orbit3 keys** — unrelated to 194 but
  will show up in gate runs.

## 4. Scope Clarification

| Area | Status | Note |
|---|---|---|
| Per-node unread indicator on the Inner-Circle view (both rings, 38px and 30px nodes) | **IN SCOPE** | the feature |
| Indicator clearing when messages are read from ANY surface (orbit-opened chat, notification tap, feed/all-chats path) | **IN SCOPE (behavioral requirement)** | mechanism unspecified here; §3.4 documents today's triggers and the one unverified window |
| Indicator appearing live while the user watches the orbit (message arrival) | **IN SCOPE** | active-listener path exists (§3.4) |
| Reduce-motion, off-screen ticker pause, entrance-animation compatibility | **IN SCOPE** | must follow §3.5 conventions |
| Screen-reader semantics for unread state on nodes + any new l10n strings (en/ar/de) | **IN SCOPE** | today's label is only "Open chat with X" |
| All-chats list rows / `UnreadCountBadge` pill | **UNCHANGED** | already correct; regression-guard only |
| Nav-bar badges (Feed red aggregate, Orbit reviewCount) | **UNCHANGED** | different semantics |
| Numerals/count display on orbital nodes | **OUT OF SCOPE** | product decision: alternative B (no numerals), not A/C |
| Overflow "+N" badge aggregating hidden friends' unread | **OUT OF SCOPE (deferred)** | documented limitation; hidden-friend TC only guards non-crash + list-view fallback |
| Group nodes / group unread | **OUT OF SCOPE** | inner circle renders 1:1 friends only |
| orbit2/orbit3 prototypes | **OUT OF SCOPE** | kDebugMode mocks (193 finding) |
| Data-layer / DB / bridge changes | **OUT OF SCOPE** | `unreadCount` plumbing exists end-to-end |
| Contact-profile hero orbit (`_OrbitRingsPainter`) | **UNCHANGED** | donor visual only |

## 5. Test Cases

IDs: `TC-194-NN`. "Indicator" below = the messenger-orbit ring + satellites on a friend node.
"Lit friend" = friend with `unreadCount > 0`.

### Group 1 — Rendering fundamentals

- **TC-194-01** — Inner-circle view with 3 friends, friend[1] has `unreadCount = 2`, others 0.
  Expected: exactly one node shows the indicator (friend[1]); the other nodes and the center self
  node show none.
- **TC-194-02** — Lit friend with `unreadCount = 1`. Expected: indicator shows exactly **1**
  satellite.
- **TC-194-03** — `unreadCount = 2` → **2** satellites; `unreadCount = 3` → **3** satellites.
- **TC-194-04 (boundary)** — `unreadCount = 4`. Expected: exactly **3** satellites (cap), not 4, no
  numeral anywhere on the node.
- **TC-194-05 (boundary)** — `unreadCount = 120`. Expected: 3 satellites; no "99+" or other text on
  the node.
- **TC-194-06** — Lit friend on ring 1 (38px avatar, index ≤ 4) AND lit friend on ring 2 (30px
  avatar, index 5-12) in the same projection. Expected: both nodes show correctly-scaled indicators;
  ring/satellite geometry does not overlap a neighboring node's tap target.
- **TC-194-07** — All 13 visible friends lit simultaneously. Expected: 13 indicators render; no
  layout overflow errors; frame build completes (widget-test pump succeeds without exceptions).
- **TC-194-08** — Indicator uses the green unread accent family (`#1DB954`), not the red nav-badge
  family and not the per-peer identity hue. Expected: rendered ring/satellite color resolves to the
  green accent.
- **TC-194-09 (regression)** — `unreadCount = 0` for all friends. Expected: node subtree contains no
  indicator elements at all (not merely invisible — absent), and existing geometry/semantics tests in
  `orbital_visualization_test.dart` still pass unmodified in their assertions about node structure.

### Group 2 — Appearing live

- **TC-194-10** — Orbit tab active, inner-circle view, friend has 0 unread. An incoming 1:1 message
  from that friend arrives (chat-message listener fires). Expected: the friend's node shows the
  indicator without leaving/re-entering the screen; friend re-sorts per `lastMessageTimestamp`
  ordering as today.
- **TC-194-11** — Same as TC-194-10 with the friend already lit at 1; second message arrives.
  Expected: satellite count becomes 2; no full re-entrance animation of the node.
- **TC-194-12** — Message arrives while the Orbit tab is off-screen (Feed active). User switches to
  Orbit. Expected: on entry (inner-circle view, per 193 reset) the friend's node is already lit —
  dirty-buffer replay path.
- **TC-194-13** — Message arrives from a friend currently hidden in the "+N" overflow (14th+ by
  recency). Expected: friend jumps into the visible 13 by recency ordering (existing behavior) and
  arrives lit; no crash.

### Group 3 — Clearing on read, per surface (the core promise)

- **TC-194-14** — Lit friend (count 2). User taps the friend's **orbital node**, conversation opens,
  user returns to Orbit (route pop). Expected: node no longer lit.
- **TC-194-15** — Lit friend. User toggles to all-chats view (193 button), taps the friend's **row**,
  reads, returns, toggles back to inner-circle. Expected: node not lit; list pill also gone
  (existing behavior, regression guard).
- **TC-194-16** — Lit friend. Conversation is opened and read via the **notification-tap route**
  while Orbit is the active tab underneath; user returns to Orbit. Expected: node no longer lit.
  (§3.4: this is the window with no verified refresh trigger today — this test defines the required
  behavior regardless of mechanism.)
- **TC-194-17** — Lit friend. Conversation is opened and read starting from the **Feed surface**;
  user then switches to the Orbit tab. Expected: node not lit on entry.
- **TC-194-18** — Conversation is open in the foreground when a new message arrives (conversation
  marks it read on arrival). User returns to Orbit. Expected: node not lit — the indicator never
  flashes for messages that were read the moment they arrived. (Transient in-and-out during the
  open-chat window is acceptable only if the final settled state is unlit.)
- **TC-194-19 (state transition)** — Lit friend at 3 satellites; count transitions to 0 while the
  Orbit surface is visible (e.g. read-marking completes after return). Expected: indicator clears
  (decays or disappears) with no residual ring/satellite artifacts and no exception from an
  in-flight animation.
- **TC-194-20 (recovery)** — App is killed and relaunched with a friend whose DB unread count is 2.
  Expected: cold-started Orbit inner-circle shows the friend lit — indicator state derives from
  persisted data, not from having witnessed the message event.

### Group 4 — Motion discipline

- **TC-194-21** — With animations enabled, the satellite field of a lit node rotates continuously
  (rigid, linear); satellites keep fixed relative phase.
- **TC-194-22 (reduce-motion)** — `MediaQuery.disableAnimations = true` (and separately
  `accessibleNavigation = true`). Expected: rotation is frozen/never started, but the indicator (ring
  + satellites) is still statically visible — unread information must not be motion-only.
- **TC-194-23 (163 off-screen pause)** — Orbit pane behind `TickerMode(enabled: false)` (another shell
  tab active). Expected: no indicator ticker advances while hidden; on re-activation the indicator
  resumes without error.
- **TC-194-24** — Entrance compatibility: node with `motionEnabled = false` (existing param).
  Expected: node appears instantly as today AND its indicator appears without entrance animation.
- **TC-194-25 (cleanup)** — Dispose the inner-circle view while ≥1 indicator is animating (navigate
  away / toggle to all-chats / pump a replacement widget). Expected: no ticker leak, no
  "disposed with active ticker" assertion, no exception.

### Group 5 — Interaction & accessibility integrity

- **TC-194-26** — Tap target: tapping a lit node (including on/near the indicator ring) opens the
  chat exactly as tapping an unlit node; effective tap target stays ≥ the existing
  `_minTapTargetSize` (48).
- **TC-194-27** — Semantics: a lit node's semantic label communicates the unread state (e.g. today's
  "Open chat with {username}" augmented with an unread phrase); an unlit node's label is unchanged.
  Label must come from l10n (no hardcoded English).
- **TC-194-28 (l10n parity)** — Any new ARB keys introduced for TC-194-27 exist in **en, ar, de**
  and are locked by the orbit strings parity test (extend `test/l10n/orbit_strings_parity_test.dart`).
- **TC-194-29 (RTL)** — Locale `ar`, RTL directionality. Expected: node positions remain physical
  (193 lock — orbit geometry does not mirror), indicators render at their nodes, no RTL layout
  exception.
- **TC-194-30 (light surface)** — Background preference with light readable palette (e.g.
  daylightLagoon). Expected: indicator remains visible (green accent on light surface), no invisible
  indicator state.

### Group 6 — Regression guards on neighbors

- **TC-194-31** — Overflow badge: 16 friends, some lit inside the visible 13, at least one lit friend
  hidden beyond 13. Expected: "+N" badge renders exactly as today (no unread decoration), hidden lit
  friend causes no error; toggling to all-chats still shows that friend's green pill (fallback
  surface intact).
- **TC-194-32** — 193 view toggle: toggling inner-circle ↔ all-chats repeatedly with lit friends.
  Expected: no state leak between surfaces; pill and indicator each render only on their own surface;
  view still resets to inner-circle on every Orbit re-entry.
- **TC-194-33** — `UnreadCountBadge` list pill behavior (appear/pulse/99+/vanish) is unchanged —
  existing tests keep passing.
- **TC-194-34** — Center self node and dashed backdrop rings are visually unchanged (no indicator on
  self; `OrbitalRingPainter` untouched).

### Group 7 — Performance

- **TC-194-35** — Orbit performance harness (`integration_test/orbit_performance_harness.dart`,
  inner-circle view) with ≥4 lit friends animating. Expected: existing frame-budget assertions of the
  harness still pass with indicators active.
- **TC-194-36** — Rotation repaint containment: while satellites rotate, repaints are bounded to the
  indicator layer(s) — pumping frames on a lit inner-circle view does not rebuild the full
  `OrbitalVisualization` subtree every frame (widget-test observable: no per-frame rebuild of
  unrelated node widgets).

---

*Prerequisite artifacts: approved mockup `Test-Flight-Improv/194-orbit-unread-indicator-mockups.html`
(alternative B), 193 view-split spec/plan (`193-orbit-inner-circle-default-view-split-*.md`).*
