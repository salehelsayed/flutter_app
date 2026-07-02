# 193 - Orbit Screen Split: Inner-Circle Default View + Toggleable Classic "All Chats" View

**Feature Improvement**

## Problem Statement

The shipped Orbit tab renders **two surfaces stacked on one screen**:

1. **Inner-Circle surface** — the `OrbitalVisualization` orbital-rings widget (top 13 friends by recency: 5 on ring 1, 8 on ring 2, `+N` overflow badge) inside a collapsible header, captioned "YOUR INNER CIRCLE" / "Close Friends".
2. **All-chats surface** — a scrollable merged list of all 1:1 friends + groups (sorted by last activity), with filter tabs (All / Intros / Archived), the intro banner, My-QR/Scan pills, search, and row swipe actions.

Both surfaces are welded into one `Column`: the visualization is a header above the list, and the list occupies the remaining space. There is no way to view the Inner-Circle as its own full surface, and no way to choose between the two presentations.

**The requested change (product decision, confirmed):**

- The Orbit screen shows **only the Inner-Circle view** — the all-chats list is no longer stacked below it.
- The classic **all-chats list becomes a separate, alternative view** of the Orbit screen.
- **Every entry into Orbit defaults to the Inner-Circle view** ("always Inner-Circle": cold start, bottom-nav tap, edge swipe from Feed, and re-entry after a tab switch all land on Inner-Circle; the choice is NOT persisted in-session or across launches).
- A **button at the top-left** of the Orbit screen switches between the Inner-Circle view and the classic all-chats view (bidirectional).

**Who is affected:** all users, on both iOS and Android, every time they open the Orbit tab.

**Confirmed target:** the shipped Orbit screen (`lib/features/orbit/` — `OrbitWired`/`OrbitScreen`). The orbit2/orbit3 prototypes are `kDebugMode`-only, mock-data-driven, have no all-chats surface, and are explicitly out of scope.

## Impact Analysis

| Dimension | Assessment |
|---|---|
| Severity | UX restructuring of a primary navigation surface — one of the two shell tabs every user lives in. Not a crash/loss bug, but a change to how every chat is reached. |
| Frequency | Every Orbit entry, every user, every session. |
| User-visible consequence | The default Orbit experience becomes the Inner-Circle visualization. Reaching a chat that is not in the top-13 requires one extra tap (top-left toggle → all-chats). Reaching intros/archived/search/QR requires the all-chats view. |
| Discoverability risk | If the toggle is missed, users may believe their full chat list is gone. The intro-notification deep link must keep landing on the intros list or pending intros/invites become unreachable from notifications. |
| Regression surface | Large: ~60 widget tests in `orbit_wired_test.dart` assert on the list being the default surface; 3 simulator/E2E tests pump `OrbitWired` and tap list rows by visible name; one shell-level lock ("orbit search state survives tab round trip") is inverted by the "always Inner-Circle on entry" decision. |
| Workarounds | None — this is a deliberate product restructure, not a defect. |

## Current State

All paths relative to repo root. All line numbers verified against the working tree (branch `new-orbit`).

### Screen composition (the two surfaces)

| Item | Location | Fact |
|---|---|---|
| Live Orbit UI (pure layout) | `lib/features/orbit/presentation/screens/orbit_screen.dart:175` (`OrbitScreen`), `build` :327-584 | Stack :335 → SafeArea Column :338-339 → header surface + list surface. |
| Inner-Circle surface | `orbit_screen.dart:342-393` | Collapsible header (`AnimatedBuilder(collapseAnimation)` :346-364) wrapping `OrbitalVisualization` :367-374 (blocked friends filtered out :370-372) + "Close Friends" caption :375-388. |
| Inner-Circle widget | `lib/features/orbit/presentation/widgets/orbital_visualization.dart` | 320×320 :23; ring 1 = first 5 @62px radius/38px avatars, ring 2 = next 8 @108px/30px :25-28, :45-46; overflow badge when >13 :47, :146-160; centered title "YOUR INNER CIRCLE" :52-63; avatar tap opens the 1:1 chat :109-113; **no visible name `Text`s** (Semantics labels only :112). |
| All-chats surface | `orbit_screen.dart:396-453` | `Expanded > CustomScrollView` (`cacheExtent: 600` :404); slivers: `FriendsListHeader` (QR pills) :417-421, `FriendsFilterToggle` :424-430 (hidden while searching :422-431), intro banner :433-435/:586-645, content sliver :440, bottom spacer :441-448. |
| List renderer | `orbit_screen.dart:662-712` | `_buildContentSliver`: merged friends+groups `SliverList` :696-711; `OrbitFriendItem → _buildFriendRow` :971-1005, `OrbitGroupItem → _buildGroupRow` :1007-1035; intros filter swaps the sliver in place :666-669/:729-741. |
| Inner-circle membership rule | `orbit_screen.dart:976` | Positional: `projection.allFriends.indexOf(friend) < 13`; list badge shown only during search :995. Membership = first 13 of the recency sort, not user-curated. |
| Sort | `lib/features/orbit/presentation/screens/orbit_wired.dart:810-824` | Friends desc by `lastMessageTimestamp`; groups desc by `lastActivityTimestamp`; merged via `OrbitItem.sortKey` (`lib/features/orbit/domain/models/orbit_item.dart:21,31-32`). |
| Data source coupling | `orbit_wired.dart:276-345` | Header projection (`allFriends`) and list projection share the same `_activeFriends`; two `ValueNotifier`s scope rebuilds (:221-224); rebuild-scoping is test-locked via `debugOnHeaderBuild`/`debugOnListBuild` (:144-145). |
| Header collapse | `orbit_wired.dart:1761-1779` | Bound ONLY to search: open → `animateTo(0)` :1764, close → `animateTo(1.0)` :1776; controller starts expanded :385-389. List scroll only hides the search trigger (`_onScroll` :1743-1759). |
| Top-left today | `orbit_screen.dart:327-584` (whole build) | **Nothing.** No top bar exists. Topmost element is the centered viz title. All overlays are bottom-anchored except `ExpandableFab` at **physical top-right** (:563-579; `Positioned(top: safeTop+8, right: 16)` `lib/features/groups/presentation/widgets/expandable_fab.dart:123-126` — physical, does not mirror in RTL, so top-left is free in both LTR and RTL). |

### Entry paths and hosting

| Path | Location | Behavior |
|---|---|---|
| Bottom-nav Orbit tap | `lib/features/feed/presentation/widgets/feed_navigation_bar.dart:81-87` → `feed_wired.dart:2488-2490` → `app_shell_controller.dart:31-38` | Slides the 2-pane Feed↔Orbit host to the orbit pane. |
| Edge swipe from Feed | `lib/features/feed/presentation/screens/feed_wired.dart:2335-2486` | Threshold/velocity swipe completes into Orbit; blocked while an orbit row action is open (:2364-2371; `orbit_wired.dart:360-369`). |
| Intro/invite notification tap | `lib/main.dart:3406-3432` (`openIntroNotificationOrbitRoute`) + :4248-4297 | Switches shell tab to orbit, pushes a **new standalone `OrbitWired`** slide-up route with `initialFilterTab: 'intros'` (:4291); restores the previous tab on pop (:3427-3429). Passes `appShellController` :4287 and `feedUnreadCountListenable` :4288, so it renders **persistent nav, no close button** (verified: `orbit_wired.dart:2186-2188`, `orbit_screen.dart:265`; locked by `test/features/push/application/intro_notification_orbit_route_test.dart:98,133-134`). |
| Return from a conversation | `orbit_wired.dart:1901-1947` | `ConversationWired` is pushed on top; pop lands back on the still-mounted Orbit pane. The user never "re-enters" Orbit. |
| Conversation notification tap | `lib/main.dart:4202-4241` | Pushes `ConversationWired` **directly** — does NOT route through Orbit. |
| Default shell tab | `lib/features/feed/application/app_shell_controller.dart:17`, `lib/main.dart:2403` | Cold start lands on Feed; the active tab is never persisted. No view-mode preference of any kind is persisted anywhere in the shell. |
| Pane lifecycle | `feed_wired.dart:375, 2482-2483, 2692-2697` | Orbit pane is lazily mounted then **latched forever**; off-screen it keeps state with `TickerMode` muting (:2730-2754) and per-reason dirty-bucket replay on reactivation (`orbit_wired.dart:447-483`) — the plan-163 invariants. |
| `initialFilterTab` | `orbit_wired.dart:143,190,374` | Honored only at `initState`; embedded mount passes `null` (`feed_wired.dart:2533`). |

### List-coupled features (everything living on the all-chats surface today)

| Feature | Location | Notes |
|---|---|---|
| Filter tabs All/Intros/Archived | `orbit_screen.dart:424-430`; `friends_filter_toggle.dart:38-60` | Intros review surface is a filter STATE of the list, not a screen. |
| Intro banner | `orbit_screen.dart:433-435,586-645`; jump handler `orbit_wired.dart:2237` | Shown when `reviewCount > 0`; jumps to intros filter. |
| My QR / Scan pills | `friends_list_header.dart:37-49`; handlers `orbit_wired.dart:1990-2112` | Scan handler also dispatches account-migration QR codes. |
| Search | trigger `orbit_screen.dart:538-556`; dock :495-520; handlers `orbit_wired.dart:1743-1791` | Filters friends only, hides groups (:301), collapses the Inner-Circle header (:1764), no-results state in the list sliver (`orbit_screen.dart:678-684`). |
| Row swipe actions | `swipeable_friend_row.dart:11`; `orbit_screen.dart:983-1001,1014-1031` | Archive/block/delete; open action gates the host swipe via `onRowActionOpenChanged`. |
| Unread badges / previews / time | `friend_row.dart:41-46,131-153`; `group_row.dart:15-68`; `orbit_media_preview_label.dart:17` | Orbit-only row widgets (verified: imported nowhere else in lib/). |
| Orbit nav badge | `orbit_screen.dart:303-325` (from list projection `reviewCount`); independent recompute when Orbit unmounted: `feed_wired.dart:528-590` | Intros + actionable invites count. |
| Contact-request dialog | `orbit_wired.dart:1669-1708` | Modal, independent of either surface; never gated off-screen (comment :454). |
| Empty/loading states | loading skeletons `orbit_screen.dart:714-727`; archived empty state :686-694 (`archived_empty_state.dart:6`); search no-results :678-684 | **The 'all' tab has NO empty state** — zero friends+groups renders header/filter/QR over blank space. |
| Live updates | `orbit_wired.dart:918-1018,1586-1667` | Targeted per-id row refresh + re-sort on 1:1 message, contact update, group message, invite, intro streams. |

### Naming/caption facts

- "Close Friends" (`orbit_close_friends`, `lib/l10n/app_en.arb:185`) currently appears **twice**: under the visualization (`orbit_screen.dart:378-388`) and as the list header title (`friends_list_header.dart:29`). Both-present-at-once is asserted by `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart:291-337`.
- "YOUR INNER CIRCLE" = `orbit_inner_circle_title`, `app_en.arb:1161`. l10n has en+ar+de parity requirements (ar is RTL).
- `OrbitFriend` doc-comment claims sort "by messageCount" (`orbit_friend.dart:6`) but the actual sort is by timestamp — pre-existing doc/code mismatch.

### Existing tests that encode today's behavior

| Test | What it locks | Effect of this change |
|---|---|---|
| `test/features/orbit/presentation/screens/orbit_wired_test.dart` (~60 tests; in `GROUP_TESTS` gate `scripts/run_test_gates.sh:227`) | Nearly every test asserts list rows/filters/intros/badges on the default surface | Breaks wholesale — each list assertion needs the all-chats view active first |
| `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`, `orbit_intros_wiring_test.dart` | Archived/intros list surfaces on default view | Breaks same way |
| `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart:291-337` | BOTH "Close Friends" texts in one tree | Superseded by design — surfaces no longer co-exist |
| `test/features/feed/presentation/screens/feed_wired_test.dart:926-989` | "orbit search state survives an inline host tab round trip" | **Inverted** by the always-Inner-Circle decision — needs a new lock |
| `feed_wired_test.dart:859` | Feed scroll survives orbit round trip | Must keep passing |
| `test/features/feed/presentation/screens/feed_swipe_test.dart` | Host swipe vs row-swipe arbitration | Must keep passing |
| `integration_test/cold_start_message_render_simulator_test.dart` (reliability-sim `1to1` + `group` suites, `scripts/check_reliability_simulation_discovery.sh:285-289`) | Pumps fresh `OrbitWired`, asserts contact/group names visible, taps `find.text(name)` to open threads (:344-377) | Breaks — the viz has no visible name texts; thread-open flow must go through the all-chats view |
| `integration_test/group_delete_preserves_friends_simulator_test.dart`, `group_invite_accept_spinner_simulator_test.dart` (gate `group-lifecycle-sim`) | List rows / invite cards on default surface | Break same way |
| `test/features/push/application/intro_notification_orbit_route_test.dart:78-134` | Intro route shows persistent nav + intros list | Must keep passing (intros reachable from notifications) |
| `test/features/orbit/presentation/widgets/orbital_visualization_test.dart` | Ring placement/overflow/taps | Safe (widget unchanged) |
| `integration_test/orbit_performance_harness.dart` (perf target `ORBIT`, `run_test_gates.sh:339-345`) | Frame timings, `OverflowBadge` per scenario | Badge lives on the viz — structurally safe; timings may shift |
| `feed_wired_test.dart:2126-2279` + `app_shell_controller_test.dart` | Plan-163 off-screen pause / change-kind invariants | Must keep passing in both views |
| `orbit2/orbit3` prototype suites + source guards | Prototype gating and toggles | Out of scope; must remain untouched |

### Test harness registration conventions (for the plan that follows)

- Host tiers auto-glob `test/features/**` (`scripts/run_host_test_gates.sh:183-187`); curated headline locks are frozen arrays in `scripts/run_test_gates.sh` (e.g. `GROUP_TESTS` :227).
- Simulator/E2E tests register in `scripts/check_reliability_simulation_discovery.sh` (+ `OPTIONAL_MANUAL_TESTS`); performance lanes via `PERFORMANCE_TARGETS` (incl. `ORBIT`).

## Scope Clarification

| Area | Status | Notes |
|---|---|---|
| Shipped Orbit screen (`lib/features/orbit/`) — split into Inner-Circle view (default) + all-chats view (alternative), top-left toggle | **In scope** | The whole feature. |
| Default rule: every Orbit entry (nav tap, edge swipe, cold start) lands on Inner-Circle | **In scope** | Confirmed product decision: reset on every entry; no in-session or cross-launch persistence of the chosen view. |
| Exception: intro-notification route lands on the all-chats surface with the intros filter active | **In scope** | Hard constraint — otherwise intros/invites become unreachable from notifications. |
| Return-from-conversation is NOT an entry | **In scope** | Popping a conversation pushed from within Orbit returns to whichever view was active. |
| List-coupled affordances (filter tabs, intro banner, QR pills, search, row swipe actions, empty states) travel with the all-chats view | **In scope** | They are structurally part of the list surface today. |
| Inner-Circle view keeps: visualization (rings/overflow/avatar-tap-opens-chat), caption/title, create-group FAB, persistent nav bar (with live badge), contact-request dialog | **In scope** | Existing behaviors that must survive on the new default view. |
| Orbit nav badge (`reviewCount`) correct regardless of active view and while Orbit is off-screen | **In scope** | Both the projection path and the unmounted recompute path. |
| Plan-163 invariants (off-screen pause, dirty replay, TickerMode, change kinds) in both views | **In scope** | Regression bar. |
| Feed↔Orbit host swipe + row-action gating contracts | **In scope (unchanged behavior)** | The toggle must not fight the horizontal gesture arena. |
| Inner-circle membership semantics (positional top-13 by recency) | **Out of scope — unchanged** | No curated/pinned circle; ring constants 5/8/13 unchanged. |
| `OrbitalVisualization` internals (ring geometry, sizes) | **Out of scope — unchanged** | |
| orbit2/orbit3 prototypes, their tabs, flags, and source-guard tests | **Out of scope — unchanged** | Prototypes stay debug-only; this change ships on the `orbit` tab. |
| App shell tab model (`AppShellTab`), bottom nav bar buttons | **Out of scope — unchanged** | The alternative view is internal to the Orbit screen, not a new shell tab. |
| Conversation-notification routing | **Out of scope — unchanged** | Never routed through Orbit. |
| Feed screen, feed unread badge | **Out of scope — unchanged** | |
| 1:1/group conversation screens | **Out of scope — unchanged** | |
| Persisting a view-mode preference | **Out of scope** | Explicitly rejected by the product decision ("always Inner-Circle"). |

## Test Cases

IDs: `TC-193-NN`. "Inner-Circle view" = the new default Orbit view; "all-chats view" = the alternative classic list view.

### Group A — Default view on every entry (TC-193-01 … 07)

- **TC-193-01 — Cold start, nav tap.** Fresh app launch (default tab = Feed) with ≥1 contact and ≥1 group; tap the Orbit bottom-nav button. Expected: the Inner-Circle view is shown — orbital visualization visible; no friend/group list rows, no filter tabs, no QR pills, no intro banner visible.
- **TC-193-02 — Edge swipe entry.** From Feed, edge-swipe into Orbit past the completion threshold. Expected: Inner-Circle view is shown (same as TC-193-01).
- **TC-193-03 — Re-entry resets the view.** In Orbit, toggle to all-chats; switch to Feed via bottom nav; tap Orbit again. Expected: Inner-Circle view is shown (the all-chats choice is not remembered across entries).
- **TC-193-04 — Return from a conversation is not an entry.** Toggle to all-chats; tap a friend row to open the 1:1 conversation; pop back. Expected: still the all-chats view, scroll position and filter preserved.
- **TC-193-05 — Process restart.** Toggle to all-chats; kill and relaunch the app; navigate to Orbit. Expected: Inner-Circle view (nothing persisted).
- **TC-193-06 — Intro-notification deep link overrides the default.** With a pending introduction, tap its notification. Expected: Orbit opens showing the **all-chats surface with the intros filter active** and persistent nav (no close button); the pending intro row is visible without any extra tap; popping the route restores the previously active tab.
- **TC-193-07 — Conversation notification unaffected.** Tap a 1:1 message notification. Expected: the conversation screen opens directly; Orbit is not involved; on back, the user is where they were before (regression).

### Group B — Top-left toggle button (TC-193-10 … 16)

- **TC-193-10 — Toggle exists on the Inner-Circle view.** On the default view, a button is present at the top-left of the screen; tapping it switches to the all-chats view (list rows, filter tabs, QR pills become visible; the orbital visualization is no longer the active surface).
- **TC-193-11 — Toggle is bidirectional.** On the all-chats view, the top-left button is present; tapping it returns to the Inner-Circle view.
- **TC-193-12 — Rapid toggling is safe.** Tap the toggle 5 times in quick succession (faster than any transition animation). Expected: no crash, no frozen intermediate state; the screen ends deterministically on the view matching the parity of taps.
- **TC-193-13 — RTL layout.** Run the Orbit screen under the Arabic locale. Expected: the toggle is present, visible, and tappable; it does not overlap the create-group FAB (which sits at physical top-right) in either LTR or RTL.
- **TC-193-14 — Localization parity.** Any user-visible label/tooltip on the toggle has en, ar, and de translations (no raw key / English fallback in ar/de).
- **TC-193-15 — Accessibility.** The toggle exposes a meaningful semantics label describing the destination view (screen-reader can distinguish "switch to all chats" from "switch to Inner-Circle").
- **TC-193-16 — Gesture arena.** A horizontal drag starting on the toggle does not get swallowed as a tap, and a tap on the toggle does not trigger the Feed↔Orbit host pane swipe. Host edge-swipe from elsewhere on the screen still exits to Feed per the existing threshold/velocity contract.

### Group C — Inner-Circle view content (TC-193-20 … 28)

- **TC-193-20 — Ring layout regression.** With 20 active contacts, the Inner-Circle view shows the 5 most-recent on ring 1, the next 8 on ring 2, and a "+7" overflow badge (existing `OrbitalVisualization` contract, unchanged).
- **TC-193-21 — Blocked friends excluded.** A blocked contact inside the top-13 by recency does not appear in the visualization.
- **TC-193-22 — Avatar tap opens the chat.** Tapping a ring avatar opens that friend's 1:1 conversation; popping returns to the Inner-Circle view.
- **TC-193-23 — Create-group FAB.** The expandable FAB (create group / announcement) is visible and functional on the Inner-Circle view.
- **TC-193-24 — Nav bar + badge.** The persistent bottom nav is visible on the Inner-Circle view; with 2 pending intros the Orbit badge shows 2 while the Inner-Circle view is active.
- **TC-193-25 — No list-surface leakage.** On the Inner-Circle view: no friend/group rows, no filter tabs, no QR pills, no intro banner, and no search affordance are visible (search belongs to the all-chats view).
- **TC-193-26 — Zero-contacts state.** A fresh identity with 0 contacts and 0 groups opens Orbit. Expected: the Inner-Circle view renders without error and shows a meaningful state (not an entirely blank screen); the toggle to all-chats still works.
- **TC-193-27 — Live reorder while visible.** While the Inner-Circle view is active, an incoming 1:1 message from a friend currently outside the top-13 arrives. Expected: the visualization updates — that friend enters the rings (and the displaced friend moves out/into the overflow count) without leaving the view.
- **TC-193-28 — Contact-request dialog.** A contact request arriving while the Inner-Circle view is active still presents the request dialog (modal is independent of the active view).

### Group D — All-chats view parity (regression) (TC-193-30 … 38)

- **TC-193-30 — Merged list.** The all-chats view shows friends and groups interleaved, sorted by last activity descending (existing interleave lock).
- **TC-193-31 — Filter tabs.** All / Intros / Archived tabs work: intros shows pending intro rows + invite cards; archived shows archived items and the archived empty state when none.
- **TC-193-32 — Intro banner.** With pending intros, the banner appears on the all-chats view and tapping it activates the intros filter.
- **TC-193-33 — QR pills.** My-QR and Scan open from the all-chats view; scanning an account-migration QR still dispatches to the migration flow.
- **TC-193-34 — Search.** Search opens from the all-chats view; typing filters friends and hides groups; the no-results state shows for a non-matching query; closing search restores the full list.
- **TC-193-35 — Row swipe actions.** Archive/block/delete swipes work on rows; while a row action is open, the Feed↔Orbit host swipe is blocked (existing contract).
- **TC-193-36 — Row content.** Unread count badges, media preview labels, and relative timestamps render on rows as today.
- **TC-193-37 — Live updates.** While the all-chats view is active, an incoming 1:1 message refreshes exactly that friend's row and re-sorts it to the top; a group message does the same for the group row (targeted-refresh locks).
- **TC-193-38 — Group lifecycle.** Pending invite cards appear, accepting shows the inline state, and a joined group appears in the list (existing invite/join locks) — all on the all-chats view.

### Group E — Shell integration & plan-163 invariants (TC-193-40 … 45)

- **TC-193-40 — Off-screen freshness into the default view.** With Orbit visited once then Feed active, messages arrive from a friend outside the current top-13. Re-enter Orbit. Expected: the Inner-Circle view reflects the new recency order immediately (dirty-bucket replay ran on reactivation).
- **TC-193-41 — Off-screen freshness into the list.** Same setup; re-enter Orbit and toggle to all-chats. Expected: rows reflect all events that arrived while off-screen (order, previews, unread counts).
- **TC-193-42 — Badge while unmounted.** Before Orbit is ever visited (pane not mounted), a pending intro arrives. Expected: the Orbit nav badge on the Feed screen updates (independent recompute path, regression).
- **TC-193-43 — Off-screen pause.** With Feed active and Orbit off-screen (in either view), incoming events do not trigger orbit rebuild churn; animations are ticker-muted (plan-163 assertions keep passing).
- **TC-193-44 — Feed state survival.** Feed scroll position survives an Orbit round trip (existing lock, unchanged).
- **TC-193-45 — Host swipe regression.** Feed↔Orbit swipe completion thresholds/velocity behavior are unchanged with the new default view active (feed_swipe locks keep passing).

### Group F — Superseded locks & E2E flows (TC-193-50 … 53)

- **TC-193-50 — Search-survival lock replaced.** The existing lock "orbit search state survives an inline host tab round trip" (`feed_wired_test.dart:926-989`) is superseded: after toggling to all-chats, opening search, switching to Feed, and returning to Orbit, the expected state is the **Inner-Circle view** (search session no longer showing). A new lock must encode this.
- **TC-193-51 — Cold-start E2E thread-open flow.** The cold-start simulator flow (fresh `OrbitWired` mount → find contact and group by visible name → tap to open both threads) must remain provable end-to-end: from a fresh Orbit mount, both a 1:1 thread and a group thread can be reached and render their messages (via the all-chats view, since the visualization renders no name texts). The `1to1` and `group` reliability-sim suites must pass with the updated flow.
- **TC-193-52 — Dual-caption lock replaced.** The assertion that "Close Friends" appears twice in one tree (`orbit_screen_loading_test.dart:291-337`) is superseded: the two captions never co-exist on one surface after the split. Each view's caption/title set must be asserted per-view.
- **TC-193-53 — Performance lanes.** The `ORBIT` performance harness target still passes on the restructured screen (frame-timing budget unchanged); the group-lifecycle-sim scenarios (`DELETE_PRESERVES_FRIENDS`, `INVITE_ACCEPT_SPINNER`) pass with their list interactions performed on the all-chats view.
