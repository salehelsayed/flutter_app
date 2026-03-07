# Remaining UI/UX Performance Implementation Plan

Source audit: `UI-UX-Perf-Improvements/findings.md` dated 2026-03-07.

Supporting inputs:
- `UI-UX-Perf-Improvements/plan.md`
- `UI-UX-Perf-Improvements/impl-backlog.md`
- current code and test coverage in `lib/`, `test/`, and `integration_test/`

This plan is for the remaining gaps only. It does not reopen `PERF-02` or `PERF-04`, and it does not assume a new sliver rewrite is needed for Feed or Orbit. The remaining work is mostly deeper state scoping, lighter incremental data refresh, route-level QA automation, and one residual layout cleanup.

## Planning Principles

- Keep cold start and explicit refresh paths intact. Optimize live updates first.
- Reuse current good patterns before inventing new architecture:
  - `ConversationScreen` already isolates composer updates behind a `ValueListenable`.
  - `FeedStore`, `FeedReactionStore`, and `feed_projection.dart` already provide useful building blocks.
  - Orbit already has targeted entity refresh tests; it now needs narrower UI scoping and cached projections.
- Do not run multiple mutating lanes against the same feature files at the same time.
- Treat screenshot and route-capture work as a required deliverable, not optional polish.

## Agent Layout

| Agent | Scope | PERF items | Primary file ownership | Can run in parallel with |
| --- | --- | --- | --- | --- |
| Agent A | Baseline, screenshots, route automation, final QA | `PERF-00`, validation for `07/08/11` | `integration_test/`, `UI-UX-Perf-Improvements/`, QA docs | all feature lanes after baseline harness shape is fixed |
| Agent B | Shared avatar resolver and self-avatar cleanup | `PERF-01` gap | `lib/features/home/...`, `lib/features/settings/...`, plus small adoption changes in Feed/Orbit | Agent C and Agent D until adoption touches their wired files |
| Agent C | Group conversation state isolation and incremental stability | `PERF-03`, `PERF-06` | `lib/features/groups/...`, group tests | Agents A, B, D |
| Agent D | Feed incremental state depth and rebuild scoping | `PERF-09`, Feed validation follow-up for `PERF-07` | `lib/features/feed/...`, Feed tests | Agents A, B, C |
| Agent E | Orbit incremental state depth, cached projections, API hardening | `PERF-10`, follow-up hardening for `PERF-08` | `lib/features/orbit/...`, Orbit tests | Agents A, B, C |
| Agent F | Residual hotspot cleanup after main lanes settle | `PERF-11` | small cleanup files only | Agent A only |

## Wave Plan

### Wave 0: Coordinator and Baseline

Run first:

1. Agent A creates the route matrix and capture harness for the exact missing routes from `findings.md`:
   - Feed idle while new message arrives
   - Orbit open -> scroll -> search
   - Orbit idle while new message arrives
   - Conversation open -> record voice
   - Conversation open -> attach video
   - Group conversation while messages arrive
2. Agent A decides the capture path:
   - primary: `integration_test/` route harnesses plus screenshot capture
   - fallback: simulator/device screenshots and documented manual QA if a fully automated path is blocked
3. Agent A adds a short baseline table to a sibling doc or `execution-log.md` with device, build mode, and pass/fail notes.

Exit gate:
- the team knows exactly how before/after evidence will be collected for each remaining lane
- no implementation lane marks itself done without an Agent A follow-up pass

### Wave 1: Safe Parallel Feature Lanes

Run in parallel after Wave 0 starts:

- Agent B Phase 1: introduce a shared avatar resolver/cache service without touching Feed/Orbit architecture yet
- Agent C: complete group conversation isolation and scroll-stability work
- Agent D Phase 1: remove Feed's heavy per-event snapshot reloads for the common live-update paths
- Agent E Phase 1: separate Orbit source state from derived projections and stop route-wide data recomputation for isolated events

### Wave 2: UI Scoping and Adoption

Run after the corresponding Wave 1 lane is stable:

- Agent B Phase 2: adopt the shared avatar resolver in Feed and Orbit while those files are already open for their state-refactor passes
- Agent D Phase 2: narrow Feed rebuild scope so one thread update does not rebuild the whole route
- Agent E Phase 2: narrow Orbit rebuild scope and remove the `introsWidget` escape hatch from `OrbitScreen`

### Wave 3: Residual Cleanup

Run last:

- Agent F inspects the remaining `PERF-11` hotspots after Feed and Orbit have settled
- Agent A captures final screenshots and reruns the exact touched routes

## Detailed Lane Plans

### Agent A: Baseline, Route Automation, and Closeout

Targets:
- `PERF-00`
- validation debt for `PERF-07`, `PERF-08`, `PERF-11`

Primary tasks:

1. Extend the existing Feed performance harness instead of replacing it.
   - Build on `integration_test/feed_performance_test.dart`
   - Add a route-level live-update scenario for "Feed idle while new message arrives"
   - Record build timing notes in profile mode when possible
2. Add Orbit route automation.
   - Create an Orbit-focused integration or widget-driven route harness for "open -> scroll -> search"
   - Add a live-update scenario for "Orbit idle while new message arrives"
3. Add group/conversation route capture harnesses.
   - one route for recording voice / attach video in 1:1 conversation
   - one route for active group updates while the screen stays open
4. Add screenshot capture for key states.
   - pre-change and post-change captures for Feed card expansion, Orbit search, group active chat, and preview fade surfaces
   - if full golden infrastructure is too expensive immediately, land deterministic screenshots first and add targeted goldens only for the subtle layout surfaces
5. Maintain the benchmark log.
   - device
   - build mode
   - route
   - before/after notes
   - visible UX differences

Recommended files:
- `integration_test/feed_performance_test.dart`
- new Orbit/group route tests under `integration_test/`
- `UI-UX-Perf-Improvements/execution-log.md` or a new profiling sibling doc
- `Testing-Tracking/` docs only if the test harness needs operator instructions

Done when:
- every remaining lane has an exact before/after route check
- screenshot coverage exists for the subtle visual deltas called out in `findings.md`
- blocked device-only checks are written down explicitly

### Agent B: Shared Avatar Resolver and Self-Avatar Cleanup

Targets:
- `PERF-01` remaining centralization gap

Current issue:
- self-avatar file loading is duplicated in `FeedWired`, `OrbitWired`, and `SettingsWired`
- each caller still performs its own file probing instead of using one shared resolver/cache

Phase 1 tasks:

1. Extract a shared resolver.
   - create a small service or helper that resolves avatar bytes from:
     - `avatarBlob`
     - `avatarVersion`
     - stored avatar file path
   - cache both hit and miss results
   - keep async file access out of widget build paths
2. Use one ownership rule for invalidation.
   - invalidate by peer id plus avatar version
   - preserve existing fallback behavior when no stored file exists
3. Add focused tests for cache hit, cache miss, and invalidation.

Phase 2 adoption tasks:

1. Replace the duplicated identity avatar loaders in:
   - `lib/features/feed/presentation/screens/feed_wired.dart`
   - `lib/features/orbit/presentation/screens/orbit_wired.dart`
   - `lib/features/settings/presentation/screens/settings_wired.dart`
2. Keep `UserAvatar` API stable unless a break is unavoidable.
3. Verify no avatar flash/regression on Feed header, Orbit hero/header, and Settings profile.

Recommended files:
- new shared resolver under `lib/features/home/` or `lib/shared/`
- `lib/features/home/presentation/widgets/user_avatar.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`

Done when:
- no screen owns its own self-avatar file probing logic
- the shared resolver is the single place that knows how avatar bytes are loaded and cached

### Agent C: Group Conversation Isolation and Incremental Stability

Targets:
- `PERF-03`
- `PERF-06`

Current issue:
- `GroupConversationWired` still uses route-level `setState` for recording duration, waveform, upload state, and voice-send completion
- `_applyMessageUpdate(...)` is incremental for messages/media, but scroll position preservation is still implicit and untested

Phase 1 tasks: isolate composer-state churn

1. Mirror the proven 1:1 conversation pattern.
   - introduce a group composer view-state object and `ValueListenable`
   - drive attachment preview, recording duration, amplitude, upload state, and processing progress through that listenable
   - keep header and message list outside the high-frequency update subtree
2. Remove high-frequency route `setState` from:
   - recorder duration stream
   - recorder amplitude stream
   - upload start/finish
   - video processing progress
3. Keep the current visual behavior unchanged.

Phase 2 tasks: explicit scroll anchor preservation

1. Add a "user at live edge" check around incoming message updates.
   - if user is at the live edge, allow the list to stay pinned to newest content
   - if user is reading older messages, preserve the current viewport anchor across insertions
2. Only resolve/download media for changed messages.
   - keep `_loadResolvedAttachmentsForMessage(...)`
   - avoid rebuilding unrelated `mediaMap` entries
3. Keep pending download updates scoped to the affected message id.

Test plan:

1. Add a pure UI stability test similar to `ConversationScreen`'s composer test.
   - prove group header and message list widget identity stay stable while recording/progress state changes
2. Extend `group_conversation_wired_test.dart`.
   - incoming message while scrolled away from newest preserves scroll offset within tolerance
   - recording/progress updates do not remount header/list
   - media updates touch only the changed message path
3. Add Agent A route capture for "Group conversation while messages arrive".

Recommended files:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- possibly a new group composer-state model file
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

Done when:
- recording and processing updates no longer rebuild the whole group route
- incoming group activity does not yank the user off older content
- tests explicitly prove the stability contract

### Agent D: Feed Incremental State Depth and Rebuild Scoping

Targets:
- `PERF-09`
- validation hardening for `PERF-07`

Current issue:
- common Feed events still call `loadContactFeedSnapshot(...)` or `loadGroupFeedSnapshot(...)`
- those paths rebuild entire thread snapshots from the database
- `FeedWired` still applies those snapshots through parent `setState`, so one-thread changes still rebuild the route

Phase 1 tasks: make live updates lighter than full-thread reloads

1. Keep canonical Feed state keyed by thread identity.
   - contact id -> connection item + thread item state
   - group id -> group thread item state
2. Introduce event reducers for the common event types:
   - incoming contact message
   - contact metadata update
   - reaction change
   - introduction completion
   - incoming group message
   - route-return change set from Orbit/Groups
3. Replace full-history refreshes on those paths with smaller queries.
   - contact live updates should use latest-message/unread/metadata queries, not `loadConversation(...)` for the whole history
   - group live updates should use latest-message/unread queries, not `getMessagesPage(limit: 200)` on each event
4. Keep full reload only for:
   - cold start
   - explicit full refresh
   - integrity fallback when reducer assumptions fail
5. Cap in-memory thread payload to what the Feed card actually needs.
   - preserve the message window required by `CardThreadFeedItem` preview/expanded states
   - do not treat Feed as the owner of full conversation history

Phase 2 tasks: narrow rebuild scope

1. Upgrade the Feed store from a passive map to a notifier-backed controller.
   - stable ordered list of row ids
   - per-row listenable for thread/connection data
   - keep reaction updates on the existing per-message reaction notifiers
2. Make `FeedScreen` rebuild only the affected row when one thread changes.
   - preserve stable row keys
   - keep expansion state, inline draft, quote target, and focus tied to stable thread ids
3. Re-check reorder behavior.
   - one thread moving in the list must not reset unrelated card state
   - inline reply focus should survive updates to other rows
4. Fold the shared avatar resolver adoption into this phase for `FeedWired`.

Test plan:

1. Extend `test/features/feed/application/feed_projection_test.dart`.
   - add parity tests for reducer-driven contact/group updates against cold-load output
   - add integrity-fallback tests
2. Extend `test/features/feed/presentation/screens/feed_wired_test.dart`.
   - prove unrelated rows keep widget identity when one thread updates
   - prove inline reply focus survives unrelated incoming events
   - prove route-return changes still scope to changed contact/group ids
3. Keep `feed_screen_test.dart` as the virtualization guard.
4. Agent A adds the missing route-level live-update capture for Feed.

Recommended files:
- `lib/features/feed/application/feed_store.dart`
- `lib/features/feed/application/feed_projection.dart`
- new Feed controller/notifier files if needed
- `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart`
- `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- Feed application and screen tests

Done when:
- common single-thread events no longer reload whole thread history
- a one-thread update does not rebuild the whole Feed route
- existing sliver virtualization remains intact and validated on live-update routes

### Agent E: Orbit Incremental State, Cached Projections, and API Hardening

Targets:
- `PERF-10`
- follow-up hardening for `PERF-08`

Current issue:
- Orbit refreshes only one friend or group at a time now, but still uses route-wide `setState`
- `_displayedFriends` and `OrbitScreen._buildMergedItems()` recompute filtered/sorted projections on every build
- `OrbitScreen` still exposes `introsWidget`, which could bypass the sliver-native path later

Phase 1 tasks: separate source state from projections

1. Introduce an Orbit state controller with canonical source maps.
   - active friends by id
   - archived friends by id
   - active groups by id
   - archived groups by id
   - blocked peer ids
   - intro data and counts
2. Add projection caching keyed by:
   - source-state version
   - active filter tab
   - search query
3. Keep source updates incremental.
   - one friend update patches one source entry
   - one group update patches one source entry
   - intro changes patch intro state without disturbing unrelated rows
4. Reserve full `loadOrbitData()` / `loadGroupData()` for cold start or integrity fallback.

Phase 2 tasks: narrow UI rebuilds and remove the fallback API

1. Rebuild only the sections whose projection changed.
   - hero/header state
   - list projection
   - search dock state
   - intro counter/banner
2. Remove `introsWidget` from `OrbitScreen`.
   - keep only the sliver-native `OrbitIntrosViewData` path
   - update tests to enforce that the embedded eager path cannot be reintroduced
3. Fold the shared avatar resolver adoption into this phase for Orbit identity/avatar loading.

Test plan:

1. Extend `test/features/orbit/presentation/screens/orbit_wired_test.dart`.
   - prove unrelated updates preserve the active search query and visible filtered result set
   - prove only the affected entity is queried for common live-update paths
   - add widget identity checks for unaffected rows if practical
2. Add projection/controller unit tests if the cache logic is moved into a separate class.
3. Extend `orbit_screen_archived_groups_test.dart`.
   - enforce sliver-only intros rendering
   - cover the `introsWidget` API removal
4. Agent A adds the missing Orbit route captures.

Recommended files:
- new Orbit controller/projection files under `lib/features/orbit/`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/orbit/application/load_orbit_data_use_case.dart`
- `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- Orbit presentation/application tests

Done when:
- common single-entity events no longer cause route-wide Orbit rebuilds
- search/filter projections are cached separately from source state
- the screen API cannot silently reintroduce an eager intros body

### Agent F: Residual Hotspot Cleanup

Targets:
- `PERF-11`

Current issue:
- the main named intrinsic/nested-list problems are gone
- the remaining concrete hotspot in the audit is the `ShaderMask` in `ScrollableMessagePreview`
- visual follow-up coverage is still missing for subtle layout changes

Tasks:

1. Measure first, then simplify.
   - confirm whether `ScrollableMessagePreview` is still a hotspot after the Feed/Orbit state work lands
2. If still hot, replace the `ShaderMask` fade with a cheaper effect.
   - static gradient overlay
   - clipped foreground decoration
   - or a simpler edge treatment that preserves readability
3. Only revisit username width, intro list, or picker layout if profiling shows they still matter after the bigger lanes land.
4. Add screenshot coverage for the changed preview treatment.

Recommended files:
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- only touch other `PERF-11` files if profiling justifies it

Done when:
- the remaining hotspot is either removed or explicitly documented as acceptable after measurement
- subtle visual changes have screenshot evidence

## Review Gates After Every Lane

Use this closeout sequence every time:

1. The feature agent runs targeted local tests for its lane.
2. A separate follow-up review checks the diff against the relevant `PERF-xx` acceptance criteria.
3. Agent A reruns only the touched observation routes.
4. Screenshot/before-after capture is attached for any visible change, including subtle preview/layout changes.
5. The lane is marked done only if both behavior and UX stability checks pass.

## Recommended Merge Order

1. Agent A baseline harness and route matrix
2. Agent B Phase 1 shared avatar resolver
3. Agents C, D Phase 1, and E Phase 1 in parallel
4. Agent D Phase 2 and Agent E Phase 2
5. Agent B Phase 2 adoption in any remaining caller not already covered
6. Agent F residual cleanup
7. Agent A final verification pass and benchmark log update

## Main Risks and Mitigations

- Risk: Feed and Orbit state optimizations diverge from cold-load truth.
  - Mitigation: extend parity tests that compare reducer/projection results to full-load output.
- Risk: route-level rebuild scoping breaks focus, expansion, swipe, or ordering semantics.
  - Mitigation: add widget identity and focus-retention tests before removing broad `setState`.
- Risk: screenshot/golden work gets deferred again.
  - Mitigation: make Agent A a required lane with explicit artifacts before sign-off.
- Risk: `PERF-11` cleanup fights in-flight Feed/Orbit changes.
  - Mitigation: run it only after Feed and Orbit lanes are stable.
