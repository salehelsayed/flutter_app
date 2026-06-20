# Orbit2 — Floating-Avatars Visual Prototype (TDD Plan v2)

> **Status:** Implemented (prototype). Visuals/UX only — **no DB, no backend, no real
> messages.** Goal: a *runnable* alternative to the Orbit screen so we can feel the UI/UX
> on-device and decide whether to adopt it. Orbit stays untouched; Orbit2 lives behind a
> temporary 3rd nav tab (`kOrbit2PrototypeEnabled`).
>
> **v2** folds in a multi-lens UX critique (41 verified findings → prioritized). Changes from
> v1 are tagged **[UX]** below. Guiding principle the design now optimizes for: *give the
> user real value and make reaching a chat seamless* — see everyone, notice who's reaching
> out, open them in one tap.

---

## 0. Decisions (from review)

| Decision | Choice |
| --- | --- |
| Default layout | **Inner gravity** + an in-screen **switcher to preview all 4 templates live** |
| Tap avatar / bubble opens | **Self-contained mock chat screen** |
| Idle motion | **Still by default.** An avatar bobs + breathing-glows **only while it has an unread message**, then settles |
| Entry point | **Temporary 3rd "Orbit2" nav tab** (flag-gated) |

**Keep:** the **Inner Circle** orbital visualization at the top (reused).
**Replace:** the bottom rectangular chat table → a **free-floating, draggable avatar canvas**.

---

## 1. Design concept — "Living Constellation"

Dark cosmic canvas. The Inner Circle is the **core** (you at center, your 13 closest in
rings). Below, your **wider circle floats freely** — sized by how much you talk to them, and
they wake up when they message you. One composition, not two stitched zones.

**Two interaction tiers** (size is the primary cue; reinforced, never duplicated):

| | **Size-A** (high) | **Size-B** (low) |
| --- | --- | --- |
| Diameter | 76 px | 48 px |
| Idle glow | soft, **desaturated** peer hue | softer, desaturated |
| Idle ring | neutral hairline | none |
| Label | same pill + opacity as B (size carries the tier) | same pill (just smaller circle) |

**[UX] Three reserved visual channels (no glow soup).** Findings showed the reused
`UserAvatar` paints its own halo, the tier added a second, and per-peer hues span all
colors — so "attention" wouldn't read. Fixed:
- **Identity** = the peer's hue, but **desaturated + dim** when idle (so 11 simultaneous
  halos stay calm). The canvas passes `showGlow:false` to `UserAvatar` and owns the single glow.
- **Tier** = size (+ a touch of glow intensity), and **spatial centrality** in Inner-gravity.
- **Attention** = the green accent `0xFF1DB954` **reserved exclusively** for an unread
  avatar: a bright pulsing green ring + glow. Idle avatars never wear green.

**[UX] Complement, not duplicate.** 24 mock friends. The Inner Circle gets the **top 13**
(this also exercises the overflow badge). The floating canvas gets the **other 11**
(disjoint — no friend appears twice), with a deliberate Size-A/Size-B mix so the tier
language still reads.

**Default templates (switchable live).** A compact **floating glass switcher** (not a
full-width bar across the seam) — Gravity / Nebula / Honeycomb / Tiered. Switching animates
every avatar (`AnimatedPositioned`) into the new template. Default = Inner gravity, whose
dense Size-A cluster sits **high, hugging the Inner Circle**, so the two halves read as one.

**Motion = attention.** Avatars are calm and still. On a message, **that** avatar bobs +
breathing-glows and a frosted bubble blooms (sender + snippet + time). Open it → it settles.

**[UX] Bubble lifecycle (self-calming canvas).** Bubbles don't pile up forever:
- **Auto-collapse** after ~7 s → a small quiet **unread dot** on the avatar; motion stops.
- **Tap empty space** = dismiss/mark-seen → all bloomed bubbles collapse to dots, **without**
  opening any chat.
- **Concurrent arrivals**: staggered bloom, **cap of 3** visible bubbles (oldest collapses to
  a dot but stays unread), bubble auto-flips to avoid screen edges.

**[UX] Message bubble:** frosted glass over a ≥0.6-alpha dark floor (legible over the
starfield/glows), sender name (accent) + message (`maxLines:2`, ellipsis) + a static time
label; bounded width `min(canvas*0.55, 220)`; tail flips left/right toward the avatar (and
**mirrors in RTL**).

**[UX] Find a friend.** Orbit ships search; Orbit2 keeps a lightweight **search pill** in the
canvas chrome: typing **dims non-matches** (doesn't hide them) so the constellation stays
legible and the comparison against Orbit is fair.

**[UX] Discoverability (taught on-screen, not just in a README):**
- **Drag affordance** — press/drag lifts the avatar (~1.08 scale + shadow + haptic).
- **Size legend** — one muted caption: "Bigger = closer · tap to chat · drag to rearrange".
- **Inviting demo control** — a primary "**Simulate a message ✨**" pill (not a "debug button"),
  Reset secondary.
- **Prototype framing** — a "Prototype · sample data" chip; the mock chat composer is a
  visible stub ("Sending is disabled in this preview").

**[UX] Reduced motion (P0).** Motion is the unread cue, so it must degrade, not vanish.
When `MediaQuery.disableAnimations` (or `accessibleNavigation`) is on: **don't run** the
bob/breathing loops; instead show a **static** green ring + the bubble immediately, and make
the entrance instant. (The reused `AmbientBackground` ignores reduce-motion, so the new
loops are gated independently.)

**[UX] Accessibility.** Each canvas avatar is wrapped in `Semantics(button, label: "<name>,
<tier>, <unread+snippet>")` with a tier-then-name `OrdinalSortKey` so screen-reader traversal
is stable regardless of drag/template. Size-B keeps a ≥48 px hit region.

**Mock chat screen.** Self-contained, swipe-back: header (avatar + name + "Demo" chip),
**per-friend distinct** sample thread with static time labels, and a stub composer.

---

## 2. Architecture & files

```
lib/features/orbit2/
  orbit2_prototype.dart           # const kOrbit2PrototypeEnabled
  domain/models/
    avatar_tier.dart              # AvatarTier {sizeA,sizeB} + fromMessageCount + dims
    orbit2_friend.dart            # Orbit2Friend: OrbitFriend + tier + seededMessage
    orbit2_incoming_message.dart  # senderName, text, timeLabel (static mock)
    orbit2_layout_template.dart   # enum + layoutPositions() (pure, deterministic)
  application/
    orbit2_mock_data.dart         # buildMockOrbit2(): 24 friends; buildMockThread()
  presentation/
    screens/
      orbit2_screen.dart          # the screen (state: template, positions, unread/bloomed)
      orbit2_mock_chat_screen.dart
    widgets/
      floating_avatar.dart        # circle + tier visuals + attention motion/glow + lift
      incoming_message_bubble.dart
      orbit2_floating_canvas.dart # positions, drag+clamp+z-order, bubbles, search-dim
      orbit2_controls.dart        # template switcher + simulate/reset + search pill + legend
```

**Reused as-is (no edits):** `orbital_visualization.dart` (Inner Circle, scaled ~0.8),
`user_avatar.dart` (with `showGlow:false`), `ambient_background.dart`, `orbit_friend.dart` +
`ContactModel`, `ring_avatar_generator.dart` (`glowColorForPeerId`),
`conversation_route_transition.dart` (swipe-back push).

**Entry-point edits (additive, flag-gated):**
- `app_shell_tab.dart` — add `orbit2 = 'orbit2'` to the set.
- `feed_navigation_bar.dart` — 3rd `NavBarButton` (reuses the orbit svg), shown only when
  `kOrbit2PrototypeEnabled`.
- `feed_wired.dart` — `build()` short-circuits: `activeTab == 'orbit2'` → `Scaffold(body:
  Orbit2Screen(...))` (does **not** thread into the 2-pane swipe host).
- `l10n` en/ar/de.

---

## 3. Data + layout

- `AvatarTier.fromMessageCount(c) => c >= 20 ? sizeA : sizeB`; `diameter` 76/48.
- `layoutPositions(template, {canvas, tiers, margin})` — **pure & deterministic** (no
  `Random`), then a relaxation pass enforces **per-pair spacing** `rᵢ+rⱼ+12` (so no overlap;
  ≥56 px even for two Size-B) and clamps inside bounds. Invariants (unit-tested):
  - innerGravity: mean Size-A distance-from-canvas-center < mean Size-B.
  - tieredBands: `max(A.y) < min(B.y)` (band-locked during relaxation).
  - all: count matches; all centers in bounds; pairwise spacing ≥ 56.
- Mock data: 24 friends (descending interaction). Inner Circle = first 13; canvas = last 11
  (≈4 Size-A + 7 Size-B). 2–3 canvas friends pre-seeded with bubbles (one on the central
  cluster); one long name + one long message to exercise clamping.

---

## 4. TDD test list (`test/features/orbit2/...`)

**Pure unit:** (1) tier threshold incl. boundary; (2) positions count == tiers; (3) all
in-bounds + pairwise spacing ≥56, all templates; (4) innerGravity mean-distance invariant;
(5) tieredBands band invariant; (6) determinism (call twice → equal); (7) empty/single tier
don't throw.

**Widget:** (8) Inner Circle renders at top; (9) one avatar per **canvas** friend (11), and
inner/canvas peer sets are **disjoint** + overflow badge present; (10) Size-A diameter >
Size-B; (11) drag moves + **clamps** in-bounds (drag far off → stays within [r,w-r]); (11b)
≤8 px jitter opens chat, 30 px move repositions & does **not** open chat; (12) switch to
Tiered → band invariant holds on screen; (13) seeded friend shows bubble with sender+text,
bounded/ellipsized; (14) **reduced-motion**: with `disableAnimations`, unread avatar has
bubble + static ring + **no running ticker**; (15) tap avatar → mock chat (name in header);
(16) tap bubble → mock chat + that avatar's unread clears; (16b) tap empty space collapses
bubbles to dots **without** pushing chat; (17) "Simulate" adds a bubble; after ~7 s it
auto-collapses to a dot (drive with explicit `pump`); (18) Reset restores template positions;
(19) mock chat renders sample bubbles + stub composer (send is a no-op) + time label, and two
friends differ; (20) screen wrapped in `AmbientBackground`; (21) a seeded avatar's `Semantics`
label contains the name + "unread".

**Entry:** (22) `AppShellTab.isValid('orbit2')`; (23) `FeedNavigationBar` shows a 3rd Orbit2
button → `onSwitchView('orbit2')`.

> **Harness gotchas:** looping animations ⇒ **never `pumpAndSettle`** (use `pump(Duration)`);
> reset any `debugDefaultTargetPlatformOverride` in-body (try/finally); off-screen taps ⇒
> size the surface / `ensureVisible`.

---

## 5. Build phases (each: tests → implement → green → analyze)

0. Flag + 3rd tab + placeholder body (reach the tab).
1. Models + layout math (pure).
2. Mock data + Inner Circle + static two-size canvas + AmbientBackground.
3. Drag (clamp/lift/z-order/tap-vs-drag) + template switcher + Reset + search-dim.
4. Bubble lifecycle (bloom → auto-collapse → dot), attention motion/glow, reduced-motion,
   concurrent cap/stagger, "Simulate".
5. Tap → mock chat (per-friend threads, time labels, stub composer, framing).
6. Polish: entrance stagger, Semantics, RTL bubble, l10n (en/ar/de), final analyze + tests.

---

## 6. Non-goals / honesty

- No DB/backend/real messages; positions & unread state are **in-memory for the session**.
- Don't regress Orbit; Orbit2 is additive & flag-gated; mock chat composer is a stub.
- **Scale caveat:** validated only at ≤~13 canvas friends — the no-scroll model is **unproven**
  at higher counts (a "mock population" toggle is provided to feel it).
- **Groups omitted:** this models 1:1 friends only, so it cannot yet be judged a full
  chat-list replacement; whether the floating metaphor extends to groups is open.
- Adopt-time follow-ups: real interaction-tier signal, position persistence, real chat wiring,
  search/filter parity (Intros/Archived), group nodes, perf at N>~30, full a11y/contrast audit.

---

## 11. v3 — one unified, magnetic, draggable space (review round 2)

Feedback folded in; the screen is no longer "top section + bottom section" — it is **one canvas**.

1. **No presence/online indicator.** No "online" dot anywhere. The only avatar badge is the
   green **unread** dot (a message cue, not presence).
2. **Merge top + bottom into one space.** The Inner Circle is no longer pinned to the top — it
   is a **draggable cluster** the user can move anywhere (e.g. to the bottom). New title-less
   `Orbit2InnerCircle` (composes the existing `OrbitalRingPainter`/`OrbitalAvatar`/`UserAvatar`/
   `OverflowBadge`). Pan the cluster to move it (`_innerCenter`); tapping a ring avatar still
   opens its chat (tap-vs-pan via slop).
3. **Magnet repulsion.** Floating avatars are pushed out of a circular exclusion zone around
   the cluster: `renderPos = repel(home, innerCenter, radius)` — homes within `radius` snap to
   the boundary, outside sit at `home`; as the cluster drags, nearby avatars slide away
   (`AnimatedPositioned`) and flow back. Homes laid out below the cluster's default band
   (`topInset`) so the default is clean.
4. **Promote by long-press → drag into the cluster.** One `GestureDetector` per floating
   avatar (arbitrated by slop/timeout): **tap** = open chat, **quick drag** = reposition,
   **long-press then drag** = carry; released inside the cluster radius ⇒ **added to the Inner
   Circle** (`onPromote`: friend moves floating→inner; cluster grows; floating layout drops it
   without disturbing the rest). Cluster highlights while a carried avatar hovers.
5. **Sleeker view selector.** Always-open chips → a compact glassy **expandable selector** in a
   floating bottom **dock** (collapsed = current template; tap = 4 options pop up; pick =
   collapse). Dock also holds an expandable **search** pill and **Simulate**. Canvas stays dominant.

**New/changed:** `orbit2_inner_circle.dart` (new), `orbit2_dock.dart` (new selector/search/
simulate, replaces `orbit2_controls.dart`), `orbit2_layout_template.dart` (+`repel()`+`topInset`),
`orbit2_floating_canvas.dart` → unified `Orbit2Canvas`, `orbit2_screen.dart` (split inner/
floating state + promote).

**Added v3 tests:** `repel()` unit (outside⇒unchanged, inside⇒boundary, centre⇒radius,
deterministic); inner circle renders + drag moves it; magnet (cluster near a floating avatar ⇒
its centre ≥ radius away); promote (long-press-carry onto cluster ⇒ floating−1, inner+1);
selector (collapsed shows current; tap reveals 4; pick switches + collapses). Kept:
tap-opens-chat, bubble lifecycle, reduced motion, two sizes, semantics.

---

## 12. v4 — declutter + safe layout + meaningful add-to-circle (review round 3)

1. **Template switch never overlaps the Inner Circle.** `layoutPositions` now takes an
   `exclusionCenter` + `exclusionRadius` (the cluster's CURRENT position) instead of the old
   top-only `topInset`; the relaxation pass pushes every home out of that zone. The canvas
   passes `_innerCenter` as the exclusion, so switching templates after dragging the cluster
   to the bottom lays the avatars out *around* it — no overlap. (`repel()` still handles live
   dragging between switches.) Unit-tested: every position ≥ `exclusionRadius` from the centre
   for all four templates.
2. **Meaningful "add to your Inner Circle".** The long-press-carry interaction is now guided:
   while carrying, the cluster shows an inviting green ring + a centred **"Drop here to add"**
   hint; when the carried avatar is actually over it, it **brightens, scales up, and reads
   "Release to add {name}"**; on release it promotes with a haptic **and a confirmation
   SnackBar "{name} added to your inner circle"**, and the friend now lives in — and moves
   with — the cluster. (`Orbit2InnerCircle` gains `carryActive` / `highlighted` / `dropLabel`.)
3. **Incoming-message tray (declutter).** Avatars with an open bubble are no longer drawn in
   place among the scattered circles — they're **pulled into a clean top tray**
   (`Orbit2MessageTray`): stacked cards of avatar + bubble + time, tapping opens the chat.
   The canvas hides those avatars (`bloomedPeerIds`) until the bubble auto-collapses to a dot,
   then they flow back. No more bubbles cluttering the constellation.

**New/changed:** `orbit2_layout_template.dart` (exclusion zone), `orbit2_inner_circle.dart`
(drop affordance), `orbit2_message_tray.dart` (new), `orbit2_floating_canvas.dart` (exclusion
+ hide bloomed + carry affordance, no in-place bubbles), `orbit2_screen.dart` (tray + promote
confirmation), l10n (`orbit2_drop_hint` / `orbit2_release_to_add` / `orbit2_promoted`).

**Added v4 tests:** exclusion-zone unit (no avatar inside the cluster zone, all templates);
"incoming-message avatars are pulled into the top tray" (bloomed avatar absent from canvas,
bubble present in tray); promote shows the confirmation. Total: **30 Orbit2 tests green.**

---

## 13. v5 — single size, centered rings, 3rd orbit, drag-to-merge, groups (round 4)

- **Single avatar size.** Floating avatars are one uniform size (`kFloatingAvatarDiameter = 40`,
  inner-circle scale); tier now only biases arrangement, not size. Glow + ring uniform too.
- **#1 Centered/aligned rings.** Replace `OrbitalRingPainter` (fixed 62/108 radii) with a
  custom dashed-ring painter drawn at the ACTUAL avatar-ring radii, centred on the box → the
  dotted orbits pass through the avatars and are concentric with the user's centre avatar.
- **#2 Third orbit on overflow.** The Inner Circle holds ring1(5)+ring2(8)=13; extra friends
  show a tappable **"+N"**. Tapping it **grows the cluster** and reveals a **3rd ring**
  (next 8) with its own dotted orbit; repulsion radius grows so the floating field makes room.
- **#3 Drag-to-merge → new orbit.** Dropping one floating friend **onto another** creates a
  **new group** ("orbit") from the two (they leave the scattered field; a group node appears).
- **#4 Group chats.** New `Orbit2Group` (id, name, members, seeded message). Seeded mock groups
  render as **clustered nodes** (2–3 overlapping mini-avatars + name + group badge); tapping
  opens a mock group chat; group messages also surface in the top tray.

New/changed: `orbit2_group.dart` (new), `orbit2_group_node.dart` (new cluster widget),
`orbit2_inner_circle.dart` (custom painter + 3rd ring + tappable overflow + expand),
`orbit2_floating_canvas.dart` (unified friend/group items + drag-to-merge + dynamic inner
size), `orbit2_mock_data.dart` (groups), `orbit2_mock_chat_screen.dart` (group mode),
`orbit2_message_tray.dart` (group items), `orbit2_screen.dart` (groups/merge/expand state),
l10n. Tests: ring-centering, overflow→3rd-ring, drag-to-merge creates a group, groups render
+ open, plus the single-size updates.

---

## 14. v6 — orbit management: shrink, group-as-orbit, add-when-expanded, remove (round 5)

- **#1 Shrink the expanded inner circle.** Expand ("+N") now pairs with a **"Show less"**
  control at the clear bottom-centre of the cluster (the "+N" moved there too, since on the
  ring it was occluded by a ring avatar). Tap to collapse back to the original size; expand/
  collapse re-centres so the larger/smaller cluster always fits.
- **#2 A merged group is a new orbit.** `Orbit2GroupNode` is redrawn as a **mini inner-circle**
  (members orbit a small group hub on a dotted ring), so overlapping two friends creates a new
  *orbit*, not a blob.
- **#3 Add-while-expanded now works.** Root cause was the "+N" tap landing on an occluding
  floating avatar (so expand never happened / a chat opened); fixed by relocating the control.
  Long-press-carry-to-promote works in both collapsed and expanded states (tested).
- **#4 Remove from the inner circle.** Inner-circle members are now **long-press-draggable
  OUT**: hold a member, drag it past the cluster's zone and release → it's removed (demoted to
  a floating friend) with a confirmation. (Bug found + fixed: hiding the carried member mid-
  gesture removed its `GestureDetector` and cancelled the drag; the member now stays mounted
  but invisible during the carry.)

Plus the earlier note: the moving green/red background glows were removed (static `Orbit2Backdrop`).

Files: `orbit2_inner_circle.dart` (collapse control + member drag-out + 48px hit targets),
`orbit2_group_node.dart` (orbital redesign), `orbit2_floating_canvas.dart` (member carry-out +
demote + per-item group size + carried-out overlay), `orbit2_screen.dart` (`_demote` +
recenter-on-expand), l10n. **33 Orbit2 tests green** (added: shrink/restore, add-when-expanded,
remove-member; kept the rest).

---

## 15. v7 — TDD PLAN: bottom orbit · drop messages · sleek expand · breathing room · search-glows-inner · no-overlap (round 6)

> **Status: ✅ IMPLEMENTED (2026-06-19).** All 6 improvements landed; `flutter test test/features/orbit2/` = **31/31 green**, `flutter analyze lib/features/orbit2/` clean, feed nav-bar test green.
> Build order followed: #2 (delete surface) → #1 (reposition) → #6 (no-merge/no-overlap) → #4 (spacing+names) → #5 (search glow) → #3 (control polish).
>
> **What shipped & key reconciliations found during build:**
> - **#1 bottom orbit:** `kBottomReserve = 120`; `_defaultInner(s) = Offset(s.width/2, max(_innerRadius+8, s.height - kBottomReserve - _innerRadius))`. Floating avatars fill the upper canvas.
> - **#2 remove message surface:** deleted `orbit2_incoming_message.dart`, `seededMessage`, `Simulate` pill, bloom/unread/auto-collapse timers. Tapping opens the mock chat only.
> - **#3 sleek expand control:** the full-width pill is gone — replaced by `_OrbitExpandNode`, a ~30px frosted circular "orbital node" (BackdropFilter + green ring/glow) at the cluster's `bottom: -4`, showing `+N` collapsed / a chevron expanded (keyed `inner-expand-toggle`, since the dock selector reuses the same chevron icon).
> - **#4 breathing room + double-tap to hide names:** `layoutPositions(minSpacing:)` floor — `kNamedSpacing = 76` (names shown) vs `kBareSpacing = 54` (hidden); relaxation runs **460 iters** (its worst-pair equilibrium is ~78.9, so 76 is reliably reached). Double-tap empty canvas toggles `namesVisible`. **GOTCHA:** the node box must *always reserve* the label-row height (`height: d + 30`) and keep the gap inside a `Flexible` — otherwise `AnimatedPositioned` lags the instant children-swap and the `Column` overflows by a few px. Label width capped at 72 (< spacing) so names never collide.
> - **#5 search glows inner members:** `Orbit2InnerCircle.searchQuery`; matching members wrapped in a keyed glow `Container(key: inner-glow-<peerId>)`, non-matches dimmed.
> - **#6 no merge → separate on drop:** merge disabled; `_separateOnDrop` pushes a dropped node out of any overlap (≤40 iters, `sep = rᵢ+rⱼ+8`).
>
> Original plan text retained below for reference.

### Decisions / reconciliations
- **#1 vs the bottom dock + #2:** With the Inner Circle default at the BOTTOM and the
  incoming-message tray removed, the cluster sits just **above** the dock:
  `_defaultInner(s) = Offset(s.width/2, s.height - kBottomReserve - _innerRadius)`
  (`kBottomReserve` ≈ dock height + margin). Floating avatars now fill the **upper** canvas.
- **#2 scope:** remove the *whole* incoming-message subsystem — `Simulate`, the top tray,
  bubbles, `bloomed`/`unreadDots`/auto-collapse timers, and all seeded messages. Tapping an
  avatar/group still opens the mock chat (kept). Groups remain the 2 seeded mocks.
- **#6:** disable drag-to-**merge** (the "disappear"); dropping one avatar on another now just
  **separates** them. No new groups are created for now.

### #2 — Remove incoming messages / Simulate  *(do first: shrinks the surface)*
- Delete `orbit2_message_tray.dart`, `incoming_message_bubble.dart`,
  `orbit2_incoming_message.dart`. Strip from `orbit2_screen.dart`: `_bloomed`, `_unreadDots`,
  `_collapseTimers`, `_seedBubbles`/`_seedOne`/`_bloom`/`_collapse`/`_dismissAllBubbles`/
  `_simulate`, the tray `Positioned`, the seeded-message fields in mock data. From
  `orbit2_floating_canvas.dart`: drop `bloomedPeerIds`/`unreadDots`/`onDismissBubbles` (no
  bubble hiding, no unread dot). From `orbit2_dock.dart`: drop `onSimulate` + the Simulate pill.
- **Tests:** `find.byType(Orbit2MessageTray)` / `IncomingMessageBubble` / `find.text('Simulate')`
  ⇒ `findsNothing`; tapping an avatar still pushes `Orbit2MockChatScreen`. Delete the old
  bloom/auto-collapse/simulate/tray tests.

### #1 — Inner circle default at the bottom
- Change `_defaultInner` (above) + `kBottomReserve`. Re-centre on reset/expand keeps it bottom.
- **Tests:** on a tall surface, `getCenter(Orbit2InnerCircle).dy > screenHeight * 0.6`; the
  mean floating-avatar centre `.dy` is **less** than the inner-circle centre `.dy` (they sit above it).

### #6 — No merge, no overlap
- Remove `onMerge`/`_merge`/`_onFriendDrop`-merge + the "New group created" snackbar.
- New on-drop **separation**: in `onPanEnd`, if the dropped node's centre is within `rA+rB+pad`
  of any other node, push it radially outward to the nearest clear spot (a few separation
  iterations, clamped to bounds). Live drag still follows the finger; only the *resting* drop
  is de-overlapped.
- **Tests:** dropping friend-1 onto friend-2's centre ⇒ friend count **unchanged** and
  `Orbit2GroupNode` count **unchanged** (no merge); after settle, `dist(center1, center2) ≥
  r1+r2` (no overlap). Layout-time non-overlap already covered by the existing spacing test.

### #4 — Breathing room for names + double-tap to toggle names
- `layoutPositions` takes a spacing mode: **names visible ⇒** larger min separation
  (`kNamedSpacing` ≈ 96 so the ~100px-wide labels under adjacent avatars don't collide);
  **names hidden ⇒** avatar-only (`kBareSpacing` ≈ 52). Re-lay-out (bump `layoutVersion`) on toggle.
- `_namesVisible` state on the screen; **double-tap the canvas background** toggles it. The
  per-node `_NameLabel` is shown only when visible.
- **Tests (unit):** with `kNamedSpacing`, pairwise centre distance ≥ `kNamedSpacing − ε` for all
  templates; with `kBareSpacing`, ≥ `kBareSpacing`. **(widget):** by default labels render
  (name `Text` present); double-tapping the canvas hides them (name `Text` gone) and re-spaces
  tighter (a sampled pair's distance shrinks); double-tap again restores names + spacing.

### #5 — Search also glows inner-circle members
- Thread `searchQuery` into `Orbit2InnerCircle`; a member whose name matches gets a **green
  glow ring** (and non-matches dim a touch). Floating-avatar search-dim unchanged.
- **Tests:** pump, type a name that's in the inner circle (e.g. an inner member) into the search
  field ⇒ that member exposes a `@visibleForTesting` `highlighted`/glow marker (present for the
  match, absent for a non-match). Searching a floating name still dims floating non-matches.

### #3 — Sleek expand/collapse control (frontend-design)
- **Design direction — "orbital node, not a banner":** replace the full-width pill with a
  **small (~30px) circular frosted-glass node** seated at the cluster's bottom edge (6-o'clock
  gap, just inside the box — clear of the avatar rings, so it stays tappable). Thin green accent
  ring + soft glow; **collapsed** shows a tiny "+N" in the accent; **expanded** shows a "⌃"
  chevron (no count). Micro-interaction: a quick scale-pulse + ring-brighten on tap. It reads as
  a small orbital "more" satellite consistent with the dotted-orbit language — not a green bar.
- **Tests:** the control's rendered size ≤ ~36px (compact, not full-width); collapsed-with-
  overflow shows "+N", tap ⇒ cluster grows (3rd ring) + control becomes the chevron; tap ⇒
  collapses back (size restored). (Reuses the existing expand/collapse size assertions.)

### Net test delta
Add: #1 bottom-position (×2), #6 no-merge + no-overlap (×2), #4 spacing modes (unit ×2) +
names toggle (widget ×1), #5 inner search-glow (×1), #3 compact-control (×1). Remove: tray/
bubble/simulate/auto-collapse tests. Keep: inner-circle drag, promote, demote, expand/collapse,
groups render+open, layout selector, single-size, reduced-motion (now trivially satisfied since
no message motion remains).

## 16. v8 — TDD PLAN: +N joins the orbit · inner-circle names · Messages view · manage the circle (round 7)

> **Status: ✅ IMPLEMENTED (2026-06-19).** All 4 improvements + the shared union foundation landed TDD;
> `flutter test test/features/orbit2/` = **56/56 green**, `flutter analyze lib` clean, feed nav-bar green.
> Build order followed: foundation (`Orbit2InnerItem`) → #1 → #2 → #4 → #3. Implementation notes vs the
> plan below: **#2 does NOT force-expand** (that would break the v7 `+3`/#1 regression locks) — instead
> names-on grows the cluster (360 collapsed / 440 expanded) and **shrinks the inner avatars** (radii
> fractions unchanged, so #1's `0.31` ring geometry holds) to open ~20px label gaps; expand to see all 16.
> **#4 uses tap-to-toggle** in Manage mode (no per-member corner badges — decorative `IgnorePointer`
> `+`/`–` glyphs only) and the Manage control is a compact **icon pill** (keyed `orbit2-manage-toggle`)
> so the dock never overflows when search opens; the promote/demote **snackbar floats above the dock**
> (`margin bottom 70`) so it never covers the controls. **#3** diversified the mock last-line `timeLabel`s
> via a stable `_variantOf` (not `hashCode`) so recency ordering does real work. Inner groups render a
> distinct glyph keyed `inner-group-<id>`. Produced by a map→design→**adversarial-critique** workflow
> (14 agents) then an adversarial **post-implementation review** pass; fixes folded in.
> **User decisions locked:** #2 = *auto-grow + spread rings* (show ALL inner names by enlarging the
> cluster); #4 = *allow GROUPS inside the inner circle* (mixed friend/group membership).
> **Honesty note:** `lib/features/orbit2/**` is **untracked in git** — there is no committed
> "incoming-message subsystem" to revive; #3 is **net-new**, styled to echo the deleted v7 surface.
> Harness gotchas as before: tall 440×950 surface first; two-pump `settle()`, never `pumpAndSettle`
> (looping anims); ValueKey targeting; drain SnackBar timers with `pump(seconds: 2)`.

### Shared foundation (build FIRST) — `Orbit2InnerItem` union  [prereq for #1, #2, #4, and #3's inner source]
The inner circle is `List<OrbitFriend>` today (`orbit2_inner_circle.dart:22`, screen `_innerFriends`).
#4 (groups in circle) forces a heterogeneous list; #1 (slot count) and #2 (labels) must read it
uniformly. Land this as a **pure refactor with zero behavior change** and keep every v7 test green
*before* any feature work.
- **New** `lib/features/orbit2/domain/models/orbit2_inner_item.dart`: a union
  `Orbit2InnerItem.friend(OrbitFriend) | .group(Orbit2Group)` exposing `id`, `displayName`,
  `bool get isGroup`, and **id-keyed `==`/`hashCode`** (so `contains`/`removeWhere`/dedup work).
- Refactor `Orbit2InnerCircle.friends → items (List<Orbit2InnerItem>)`; `avatarFor` branches
  friend→`OrbitalAvatar` / group→a small group glyph (see #4 for the glyph decision); `matches()`
  and the glow wrapper key off `item.id`/`item.displayName`; the dim `Opacity` wraps whichever
  widget the branch built (critique: glow/dim must apply to BOTH branches, not just the friend path).
- Screen: `_innerFriends → _innerItems`; seed it friends-only from mock (existing names), so the
  initial set stays all-friends and `find.byType(OrbitalAvatar).first` in the v7 remove test still
  hits a friend.
- **Distinct key namespace:** an inner group renders with key `inner-group-<id>` — NEVER reuse the
  canvas `group-node-<id>` (else `findsNothing`/`findsOneWidget` collide with a duplicate-key crash).
- **Tests (unit, `orbit2_models_test.dart`):** `Orbit2InnerItem.friend(f)` → `!isGroup`,
  `id==f.peerId`, `displayName==f.username`; `.group(g)` → `isGroup`, `id==g.id`,
  `displayName==g.name`; two friend items with the same peerId are `==`. **Regression gate:** the
  whole v7 suite (10 `FloatingAvatar`, 2 canvas `Orbit2GroupNode`, `+3` overflow,
  `inner-glow-orbit2-inner-0`, carry-promote 9, drag-out 11, templates) stays GREEN after the refactor.

### #1 — the "+N" / chevron node joins the OUTER ORBIT (a ring slot, not a chip below the cluster)
Today `_OrbitExpandNode` is `Positioned(bottom:-4)`, floating below the rings with no orbit under it
(`orbit2_inner_circle.dart:216-235`). Put it **on the outermost VISIBLE ring** so it reads as the last
member slot sitting on a drawn dotted orbit.
- **Decision:** outermost visible ring = **ring2 collapsed / ring3 expanded** (the rings with a drawn
  dotted orbit at each state, `ringRadii` `:87`). Reserve ONE extra slot: `outerCount = outer.length +
  (showNode ? 1 : 0)` and place the node at the final index using the *same* `_pos()`+`Positioned`
  formula members use. **All members stay visible**; `+N` stays truthful (`= items.length − shownCap`);
  the outer ring intentionally re-spaces 8→9 slots (document it). Counts items uniformly, so a promoted
  **group** also occupies an outer slot (composes with #4).
- **Preserve the v7 `#3` lock:** keep `_OrbitExpandNode` at 30×30 and add **no Container wrapper**
  (the test asserts the first `Container` ancestor of `+3` is ≤36). Wrap only in a bare
  `Positioned`+`GestureDetector(key 'inner-expand-toggle', behavior: opaque, onTap: onOverflowTap)`.
- **Critique fixes:** (a) ring2 members are tap-inflated to **48×48** hit boxes (`:93-94`) — the node's
  slot must clear them; (b) accept the collapsed→expanded ring jump (node moves ring2→ring3),
  documented.
- **Files:** `orbit2_inner_circle.dart` only (derive `outerR`/`outerRing` from the SAME `expanded`
  flag as `ringRadii` so it never lands on an undrawn orbit).
- **Tests (`orbit2_screen_test.dart`):**
  - Node is INSIDE the box (`nodeCenter.dy < innerCenter.dy + innerW/2`) and at the outer radius
    (`(node−center).distance ≈ ring2R` collapsed; `≈ ring3R` after expand) — **RED today** (escapes via
    `bottom:-4`).
  - **No-overlap, tightened:** the node occupies a *distinct angular slot* (its polar angle differs from
    every member's by ≈`360/outerCount`±few°) AND its 30px box does not rect-intersect any outer member's
    **48px** hit box — not a loose centre-distance floor.
  - **Tap disambiguation:** tapping the nearest outer member's *centre* opens that member's chat; tapping
    the node expands. (Catches the 48px hit-box steal.)
  - **Truthfulness as membership grows:** promote a floating friend (inner→17) → node reads `+4` and is
    still on the outer ring.
  - **Reset path:** expand (chevron on ring3) → tap **Reset** → node back on ring2 showing `+3`.
  - **Keep GREEN:** the existing `#3` compact-control test, unchanged.

### #2 — double-tap names ALSO labels inner-circle members  (AUTO-GROW + SPREAD, per decision)
Plain labels under all 16 members overlap (critique proved a name printed across a neighbour's face;
rings 1&2 are *always* full because the inner list is always 16 regardless of the population toggle).
So labels require more room — **grow and spread the cluster when names are on.**
- **Decision (auto-grow):** when `namesVisible` is true the inner circle (a) **auto-expands** (all 3
  rings shown) and (b) uses a larger `_innerSize` "names size" (≈ **400**, vs 240/320), so ring radii
  (`.18/.31/.44`) spread far enough that each member's label sits in the **radial gap** to the next ring
  and the outermost ring's labels point outward into empty space. The canvas computes the names-size and
  feeds the bigger exclusion radius so floating avatars are repelled further up (accepted crowding of the
  upper canvas — the chosen trade).
- **Label widget:** a tiny no-pill `_InnerNameLabel` (fontSize ≈10, w600, 1-line ellipsis, maxWidth
  budgeted to the ring's arc spacing, subtle text-shadow for contrast), emitted as a **sibling
  `Positioned`** centred on each member's `_pos` slot in the inter-ring gap — never wrapped into the
  member's tap geometry, never on the reserved `+N` control slot (it's a control, not a friend).
  Labels read `item.displayName` (works for friend AND group items). Dim/hide parity with the avatar
  (carried-out → omitted via `!hidden`, not `Opacity(0)`; search-dimmed → 0.28).
- **Centre user:** static localized **"You"** label under the centre when names on (zero plumbing;
  closes the critique's asymmetry note).
- **Search peek (closes the collapsed-search UX gap):** the search-matched inner member always renders
  its name regardless of `namesVisible`, so searching a member shows *who* glowed even before double-tap.
- **Files:** `orbit2_inner_circle.dart` (add `namesVisible` ctor flag default **false**; label loop;
  `_InnerNameLabel`; force-expanded-when-names), `orbit2_floating_canvas.dart` (pass
  `namesVisible: widget.namesVisible`; compute the bigger inner/exclusion size when names on).
- **Tests (`orbit2_screen_test.dart`) — must assert LEGIBILITY, not just presence:**
  - Names on → an inner **ring1** name (`Karim`), a **ring2** name (`Hadi`), and a **ring3** name
    (`Yara`) are each `findsOneWidget`; **RED today**.
  - **Geometry (the real point):** with names on, `tester.getRect()` of two adjacent labels do **not**
    intersect, AND a label rect does not intersect a neighbouring `OrbitalAvatar` rect (kills the
    "name across a face" bug).
  - Box-overflow guard: promote friends to fill ring3, names on, assert the outermost label rect stays
    within the `Orbit2InnerCircle` rect.
  - Double-tap OFF removes inner labels AND canvas labels (`Karim` and `Idris` both gone), ON restores.
  - Centre "You" present when names on, absent when off. Carried-out member's label disappears.
  - **Keep GREEN:** v7 `#4` canvas-name toggle (`Idris`), `#5` search-glow (`Layla`), `#3` compact node
    (inner labels are siblings/no-pill → not a wider `Container` ancestor of `+3`).

### #3 — "Messages" view in the layout menu: avatar + last-incoming bubble, recency-ordered, inner circle hidden
- **Decision: a separate `enum Orbit2ViewMode { constellation, messages }`** — NOT a 5th
  `Orbit2LayoutTemplate` (a 5th enum would be force-fed through the `layoutPositions` bounds/spacing unit
  tests and auto-appear as a bogus "spatial layout"). A **"Messages" row** is prepended into the existing
  layout-selector menu; picking it sets `messages`, picking any of the 4 templates flips back to
  `constellation` (restores the inner circle) — satisfies "in the same menu" + "switching back restores
  the circle" with no extra control.
- **Render by SWAP:** screen Stack's first child = `viewMode==constellation ? Orbit2Canvas(...) :
  Orbit2InboxView(...)`. New `orbit2_inbox_view.dart`: a `ListView` of read-only rows
  `[avatar | name + bubble + timeLabel]` — no inner circle, no promote/demote/names toggle. Friend avatar
  = `UserAvatar(size:44)`, group = `Orbit2GroupNode(size:44)` **inside a fixed 44×44 SizedBox** (its glow
  + `Clip.none` would otherwise overflow the row). Each row `Semantics(button:true)` + key
  `inbox-row-<id>`; tap reuses `_openChat`/`_openGroup`.
- **Make recency REAL (critique: it's a no-op today — every mock thread ends `'now'`):** diversify the
  **last** line's `timeLabel` across thread variants (variant0 `'now'`, variant1 `'12:41'`, variant2
  `'Mon'`; the two groups one `'now'`, one `'14:30'`) and **pin the variant to a stable index**, NOT
  `String.hashCode` (hashCode isn't stable across release builds). Add `recencyRank` (`now`→0,
  `HH:MM`→1, weekday→2) + `inboxEntries(...)` sorting by `(recencyRank asc, title asc)`. **Groups have no
  `messageCount`** — do not sort on it; tiebreak on title only (documented).
- **Hide constellation chrome in Messages mode:** the `orbit2_hint` text ("Drag the orbit · long-press a
  friend…") and the search pill are **hidden** when `viewMode==messages` (they advertise gestures the
  list doesn't have). Dock stays so the user can switch back.
- **Inner source = the `Orbit2InnerItem` union** (so it composes with #4's groups-in-circle); de-dup by id.
- **l10n:** add `orbit2_view_messages` ("Messages") + `orbit2_inbox_empty` ("No conversations yet"),
  placeholder-free, to en/ar/de **by key adjacency** (append after the last `orbit2_*` key — never by
  absolute line number, never between a key and its `@`-metadata); then `flutter gen-l10n`. Empty state
  is unreachable from the screen (always ≥3 rows) — keep it but unit-test the widget in isolation and
  note it's defensive.
- **Wiring:** thread `viewMode`+`onMessagesView` through **both** `Orbit2Dock` (stateless, forward) and
  `Orbit2LayoutSelector` (stateful, consumes); template rows' `selected:` requires `constellation` mode.
- **Tests:**
  - *Unit (`orbit2_models_test.dart`):* `recencyRank` mapping; `inboxEntries` produce **≥2 distinct
    recencyRanks** and an `HH:MM` entry sorts before a weekday entry (this FAILS until the data is
    diversified — forces the fix); dedup + determinism.
  - *Widget (`orbit2_screen_test.dart`):* open Messages from the menu → `Orbit2InnerCircle` `findsNothing`
    + `Orbit2InboxView` `findsOneWidget` + ≥1 `inbox-row-`; tap a **friend** row near the top → opens that
    friend's chat; `scrollUntilVisible` a **group** row → opens the group chat (groups sort last);
    switch Gravity→Messages→Nebula lands on Nebula with the circle back; collapsed pill shows "Messages"
    while in messages mode; template rows render unselected in messages mode; **keep GREEN** the v7
    "no message surface / Simulate absent" + 2-canvas-group-count test on the DEFAULT screen.

### #4 — explicitly MANAGE the inner circle: add/remove friends AND GROUPS  (per decision)
Long-press-carry exists but is undiscoverable; make it explicit, and allow **groups** in the circle.
- **Decision — "Manage" mode + tap-to-toggle (no corner badges):** a **"Manage"/"Done" pill** (in the
  dock) flips `manageMode`. While on:
  - tapping a **floating** friend/group node **adds** it to the inner circle (promote);
  - tapping an **inner** member **removes** it (demote back to the canvas);
  - each node shows a *decorative* `+` / `–` glyph overlay that is **`IgnorePointer`** (visual affordance
    only). The whole-node `onTap` is **rerouted** to add/remove and the node's `onPan*`/`onLongPress*` are
    **gated to null** in manage mode. This deliberately avoids per-member corner badges (critique proved a
    badge overlaps neighbours on the tight rings: ring1 hit boxes already ~touch) and avoids the v6 carry-
    cancel gesture-arena conflict.
- **Groups in the circle (the model work):** built on the shared `Orbit2InnerItem` union. An inner group
  renders as a **distinct simple glyph** — a `UserAvatar`-sized circle with `Icons.group_rounded`, NOT a
  mini-`Orbit2GroupNode` (critique: at inner-ring sizes ~29px the mini-orbit is a 4.7px illegible smudge).
  Key `inner-group-<id>`; searchable/glowable/removable like a friend via `item.id`/`displayName`.
- **Promote/demote plumbing:** keep the existing friend long-press-carry + drag-out (friend-only;
  `_carryOut` stays `OrbitFriend?`). Group add/remove goes **only** through Manage tap. `_promoteGroup`
  removes the group from `_groups` (so it leaves the canvas) and adds an `Orbit2InnerItem.group`;
  `_demoteGroup` returns it to `_groups`. **Dedup by id** (no double-add).
- **Distinct SnackBar copy** so tests discriminate friend vs group: `orbit2_promoted` ("{name} added to
  your inner circle") for friends, **new** `orbit2_promoted_group` ("Group {name} added to your inner
  circle"); `orbit2_removed` reused (or a group variant) — plus structural assertions.
- **Lifecycle:** `_reset` and `_cyclePopulation` force `manageMode=false` and rebuild the inner set from
  mock (clearing promoted groups) so no stale badges/ids dangle.
- **Avoid whole-canvas reshuffle:** prefer invalidating only the changed id on demote rather than bumping
  `_layoutVersion` (which re-lays-out every floating node — the "calm constellation" the plan protects).
- **Files:** new `orbit2_inner_item.dart` (foundation), `orbit2_inner_circle.dart` (group glyph + manage
  remove tap + `–` overlay), `orbit2_floating_canvas.dart` (manage add tap + `+` overlay + gesture
  gating), `orbit2_dock.dart` (Manage pill), `orbit2_screen.dart` (`_manageMode`, `_innerItems`,
  `_promoteGroup`/`_demoteGroup`, dedup, lifecycle), l10n en/ar/de + `flutter gen-l10n`.
- **Tests (`orbit2_screen_test.dart`, drain SnackBar timers):**
  - Manage on → tap a floating friend → `FloatingAvatar` 10→9 + "added to your inner circle".
  - Manage on → tap a floating **group** → canvas `group-node-orbit2-group-work` `findsNothing` AND an
    inner `inner-group-orbit2-group-work` **appears** AND "Group … added" snackbar.
  - Manage on → tap an inner member → `FloatingAvatar` 10→11 + "removed…".
  - Promote a group, search "Work Crew" → `inner-glow-orbit2-group-work` glows (negative: a non-match
    inner group does not carry the glow key).
  - **Gesture gating:** a short drag on a floating node in Manage mode does **not** reposition it; tapping
    a node in Manage mode does **not** open chat (add/remove instead). Toggling **Done** restores
    open-chat-on-tap.
  - **Idempotency (not a tautology):** promoting the same id twice grows `_innerItems` by exactly 1.
  - **Lifecycle:** cycling population (or Reset) while Manage is on clears manage mode and leaves no
    dangling inner group / truthful counts.
  - *Unit:* the union model tests from the shared foundation.

### Cross-improvement sequencing (critiques flagged shared edit sites)
`#1`, `#2`, `#4` all edit `Orbit2InnerCircle.avatarFor`/the ring loop, and `#3` consumes the inner set.
Build order: **Foundation (`Orbit2InnerItem`, green refactor) → #1 (+N slot) → #2 (names + auto-grow) →
#4 (Manage add/remove) → #3 (Messages view).** Each step: write listed tests RED → implement GREEN →
`flutter analyze lib/features/orbit2/` clean → keep the whole `test/features/orbit2/` suite + the feed
nav-bar test green. `#3` is independent of the cluster but reuses the union, so it lands after #4.

### Net test delta (v8)
**Add** — foundation union (unit ×~2); #1 ring-slot + tap-disambiguation + truthful-+N + reset (×~5);
#2 inner-name presence (ring1/2/3) + **non-overlap geometry** + box-overflow + toggle + "You" (×~6);
#3 recencyRank/inboxEntries units (×3) + Messages swap/round-trip/row-open/pill/empty (×~6);
#4 manage add friend/group, remove, group-glow, gesture-gating, idempotency, lifecycle (×~8).
**Keep (regression locks)** — every v7 test, especially `#3` compact-`+N`, `#4` canvas-names,
`#5` search-glow, "no message surface", canvas group count, carry-promote/drag-out counts.
**Remove** — none.

### Open questions (for an on-device eyeball)
- #2 auto-grow size (~400) on a real phone vs the 950-tall test surface: confirm the enlarged cluster +
  the squeezed upper canvas feels right, and that the outermost ring's labels don't run off-screen when
  ring3 fills via promotes.
- #1: is the 8→9 outer-ring re-spacing (to host the `+N` slot) visually acceptable, or should `+N`
  sit at a fixed canonical angle (e.g. 6 o'clock) for muscle memory?
- #4: the inner group glyph (group icon vs mini-orbit) — eyeball legibility on the ring; and whether
  removing a group should restore it to its old drag position or accept a reshuffle.
- #3: "Messages" vs "Inbox" wording; Messages-mode search pill — hide (planned) vs repurpose to filter
  rows; icon choice (`forum`/`inbox`/`chat_bubble`).

### Post-implementation adversarial review — fixes applied (2026-06-19)
An 11-agent review of the *shipped* code (each finding adversarially verified in source) surfaced 6
issues; **4 fixed, 1 by-design, 1 subsumed**:
- **FIXED (high) — promote/demote reshuffled the whole canvas.** `_ensureLayout` wholesale-replaced
  `_homes` on any membership churn, snapping every manually-dragged node to a fresh layout. Now it does a
  *hard* relayout only on a deliberate change (template / size / expand / names / reset); membership-only
  churn **preserves every surviving node's position** and only seeds genuinely-new ids.
- **FIXED (high) — cancelled long-press stranded a phantom.** A carry-out (or promote carry) interrupted by
  a `PointerCancel` (OS gesture, backgrounding, ancestor claiming the pointer) skipped `onLongPressEnd`,
  leaving the member hidden + a stuck ghost until screen rebuild. Wired `onLongPressCancel` →
  clears `_carryOut`/`_carrying`. Regression test dispatches a real `gesture.cancel()`.
- **FIXED (medium) — outermost-ring labels ran off-screen** once ring3 fills via promotes (label box
  reached ~x450 on a 440 screen). Labels are now **clamped inside the cluster box** on both axes.
- **FIXED (medium) — Reduce Motion ignored by the inner circle.** Threaded `motionEnabled` into
  `Orbit2InnerCircle` → `OrbitalAvatar` (new backward-compatible param; skips the scale-in entrance) and
  gated the highlight `AnimatedScale`. Original Orbit-feature tests still green.
- **BY DESIGN — population-cycle resets the inner circle/groups.** Intended lifecycle (the
  `#4 cycle-clears-manage` test locks it); cycling regenerates the mock at scale N.
- **SUBSUMED — demoted-group lands at a fresh seed.** The `_homes`-preservation fix removes the
  whole-canvas snap; the re-added node now gets a single exclusion-aware seed (no reshuffle of others).
  Restoring a node to its exact pre-promote spot remains a possible polish (open question above).
