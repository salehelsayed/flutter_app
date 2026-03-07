# UI/UX Performance Execution Log

## Session Metadata

- Date: 2026-03-07
- Source of truth:
  - `UI-UX-Perf-Improvements/plan.md`
  - `UI-UX-Perf-Improvements/impl-backlog.md`
- Explicit exclusions for this run:
  - `PERF-02`
  - `PERF-04`
- Top-level routing skill:
  - `flutter-ui-performance-orchestrator`

## Initial Git State

- Start branch: `UI-UX-Perf-Improvmenets`
- Start HEAD: `b34eef6536a3d6ffa8f9844ef1e64f7efa480de8`
- Dirty-state checkpoint branch: `checkpoint/perf09-pre-execution-20260307`
- Dirty-state checkpoint commit: `8e0f411`
- Execution branch: `perf-exec/main`

Dirty files captured before checkpoint:
- `lib/features/conversation/application/handle_incoming_reaction_use_case.dart`
- `lib/features/conversation/application/reaction_listener.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/feed/application/load_feed_use_case.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `test/features/conversation/application/handle_incoming_reaction_use_case_test.dart`
- `test/features/conversation/application/reaction_listener_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- Untracked:
  - `UI-UX-Perf-Improvements/impl-backlog.md`
  - `UI-UX-Perf-Improvements/plan.md`
  - `lib/features/conversation/domain/models/reaction_change.dart`
  - `lib/features/feed/application/feed_projection.dart`
  - `lib/features/feed/application/feed_reaction_store.dart`
  - `lib/features/feed/application/feed_store.dart`
  - `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart`
  - `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`
  - `lib/features/feed/domain/models/feed_route_changes.dart`
  - `test/features/feed/application/feed_projection_test.dart`
  - `test/features/feed/application/feed_reaction_store_test.dart`
  - `test/features/feed/application/feed_store_test.dart`

## Lane Routing

- `PERF-00`: `flutter-ui-performance-profiler` -> `mobile-perf-qa`
- `PERF-01`: `flutter-rendering-optimization` -> `mobile-perf-qa`
- `PERF-03`: `flutter-state-incremental-updates` -> `mobile-perf-qa`
- `PERF-06`: `flutter-state-incremental-updates` -> `mobile-perf-qa`
- `PERF-07`: `flutter-sliver-virtualization` -> `mobile-perf-qa`
- `PERF-08`: `flutter-sliver-virtualization` -> `mobile-perf-qa`
- `PERF-09`: `flutter-state-incremental-updates` -> `flutter-test-orchestrator` -> `mobile-perf-qa`
- `PERF-10`: `flutter-state-incremental-updates` -> `mobile-perf-qa`
- `PERF-11`: inspect after main lanes, then `flutter-rendering-optimization` or `flutter-sliver-virtualization` -> `mobile-perf-qa`

## Lane Status

- Wave 0
  - `PERF-00`: Complete enough to proceed, with documented route-validation gaps
  - `PERF-09 audit`: Complete
- Wave 1
  - `PERF-01`: Done
  - `PERF-03`: Done
  - `PERF-06`: Done
  - `PERF-07`: Done
  - `PERF-08`: Done
- Wave 2
  - `PERF-10`: Done
  - `PERF-09 reconciliation`: Done
- Wave 3
  - `PERF-11`: Pending
- Wave 4
  - Final verification: Pending

## Notes

- No stop condition has been hit yet.

## Worktree Isolation

- `perf-exec/main`
  - `/Users/I560101/Project-Sat/mknoon-2/flutter_app`
- `perf-exec/lane-b-perf01`
  - `/Users/I560101/Project-Sat/mknoon-2/flutter_app-lanes/b-perf01`
- `perf-exec/lane-c-perf03`
  - `/Users/I560101/Project-Sat/mknoon-2/flutter_app-lanes/c-perf03`
- `perf-exec/lane-d-perf06`
  - `/Users/I560101/Project-Sat/mknoon-2/flutter_app-lanes/d-perf06`
- `perf-exec/lane-e-feed`
  - `/Users/I560101/Project-Sat/mknoon-2/flutter_app-lanes/e-feed`
- `perf-exec/lane-f-orbit`
  - `/Users/I560101/Project-Sat/mknoon-2/flutter_app-lanes/f-orbit`
- `perf-exec/lane-g-perf11`
  - `/Users/I560101/Project-Sat/mknoon-2/flutter_app-lanes/g-perf11`

## Wave 0

### PERF-00 Lightweight Baseline

Environment:
- `flutter --version`: `3.41.1`
- Devices discovered:
  - `macos`
  - multiple iOS simulators
  - `chrome`

Baseline evidence captured:
- `flutter test integration_test/feed_performance_test.dart -d macos`
  - required Wave 0 harness reconciliation:
    - replaced stale `ExpandedComposeInput` assumption with `InlineReplyInput`
    - scoped compose-input probe to the explicitly expanded `thread_0` card
  - final baseline results:
    - `Scroll`: avg `1.70ms`, p99 `3.17ms`, worst `6.58ms`
    - `Expand/Collapse`: avg `2.35ms`, p99 `46.64ms`, worst `60.55ms`
    - `Swipe-to-quote`: avg `1.32ms`, p99 `3.84ms`, worst `3.84ms`
    - `Compose input`: avg `15.69ms`, p99 `42.64ms`, worst `42.64ms`

Baseline limitations:
- No existing automated route harness was found for:
  - launch into real Feed with production-like data
  - Feed -> conversation route push timing
  - Orbit open -> scroll -> search
  - group conversation live incoming activity
- Device paths exist, but route-level before/after capture for those flows remains a QA gap for later follow-up passes.

### PERF-09 Audit And Gap List

Decision:
- `GO`: safe to build later Feed work on top of the current implementation.

Evidence reviewed:
- targeted tests passed:
  - `flutter test test/features/feed/application/feed_projection_test.dart test/features/feed/application/feed_reaction_store_test.dart test/features/feed/application/feed_store_test.dart test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/conversation/application/handle_incoming_reaction_use_case_test.dart test/features/conversation/application/reaction_listener_test.dart`
- targeted analysis:
  - `flutter analyze lib/features/feed lib/features/conversation/application/handle_incoming_reaction_use_case.dart lib/features/conversation/application/reaction_listener.dart lib/features/conversation/domain/models/reaction_change.dart lib/features/conversation/presentation/screens/conversation_wired.dart test/features/feed test/features/conversation/application`
  - result: no blocking errors in the audited `PERF-09` surface; existing repo-wide infos/warnings remain

Confirmed incremental event paths:
- incoming 1:1 message -> `_refreshContactFeedItem`
- contact metadata update -> `_refreshContactFeedItem`
- reaction add/remove -> `_reactionStore.applyChange` without thread reload
- incoming group message -> `_refreshGroupFeedItem`
- mutual intro acceptance -> `_refreshContactFeedItem`
- route-return deltas from Orbit / Group list -> `_applyRouteChanges`
- read-state-affecting local flows -> targeted contact/group refresh, not unconditional full Feed reload

Known intentional broad reloads still present:
- cold start initial load
- explicit route-return flags:
  - `reloadAllContacts`
  - `reloadAllGroups`
- integrity-recovery fallback when targeted snapshot refresh throws

Missing tests to add during later Feed reconciliation:
- focused inline reply / input-focus retention while an incoming contact snapshot refresh lands
- explicit coverage for `reloadAllContacts` / `reloadAllGroups` route-return behavior
- route-level QA for actual live Feed idle/update flows on device, not just widget-harness timing

Issues to fold into later `PERF-09` reconciliation:
- the data refresh is incremental, but `FeedWired` still applies snapshot changes via parent `setState`; after `PERF-07`, re-check whether remaining rebuild fan-out is acceptable or needs finer-grained UI scoping
- `integration_test/feed_performance_test.dart` currently targets the eager Feed structure; it must be updated again after `PERF-07` virtualization so the baseline gate stays valid

## Wave 1

### PERF-01 Move Avatar Lookup And Caching Out Of Widget Build

Lane:
- `perf-exec/lane-b-perf01`

Implementation:
- replaced sync avatar file probing inside `UserAvatar.build` with an async per-peer resolver backed by shared notifiers
- kept the `UserAvatar` call site API stable
- added explicit cache invalidation when profile pictures are downloaded or uploaded locally

Follow-up pattern:
1. local implementation checks
   - `flutter analyze lib/features/home/presentation/widgets/user_avatar.dart lib/features/settings/application/download_profile_picture_use_case.dart lib/features/settings/application/upload_profile_picture_use_case.dart test/features/home/presentation/widgets/user_avatar_test.dart`
   - result: passed, no issues
2. follow-up diff review
   - confirmed the shared avatar widget no longer performs `existsSync()` in `build`
3. targeted QA / regression surface
   - `flutter test test/features/home/presentation/widgets/user_avatar_test.dart test/features/home/presentation/widgets/profile_avatar_widget_test.dart test/features/settings/presentation/widgets/settings_profile_section_test.dart test/features/conversation/presentation/widgets/conversation_header_test.dart test/features/orbit/presentation/widgets/friend_row_test.dart test/features/orbit/presentation/widgets/orbital_visualization_test.dart test/features/feed/presentation/widgets/connection_card_test.dart test/features/settings/application/download_profile_picture_use_case_test.dart test/features/settings/application/upload_profile_picture_use_case_test.dart`
   - result: all tests passed
4. visible UX delta
   - none intended

Residual notes:
- sync avatar file probing still exists in some wired-layer identity/avatar loaders, but the shared list-surface widget hot path is clean, which is the scoped `PERF-01` requirement

### PERF-03 Isolate Recording, Processing, And Progress State From Page Rebuilds

Lane:
- `perf-exec/lane-c-perf03`

Implementation:
- introduced `ConversationComposerViewState` plus an optional composer `ValueListenable` path in `ConversationScreen`
- moved attachment-strip, upload/progress, and recording waveform/duration updates behind a dedicated `_composerState` notifier in `ConversationWired`
- left message, contact, intro-banner, and reaction updates on the existing route state so only the composer subtree churns during recording / processing
- added a regression test proving composer-state updates keep the existing `ConversationHeader` and message-list widgets mounted and unchanged

Follow-up pattern:
1. local implementation checks
   - `flutter analyze lib/features/conversation/presentation/screens/conversation_screen.dart lib/features/conversation/presentation/screens/conversation_wired.dart test/features/conversation/presentation/screens/conversation_screen_test.dart`
   - result: passed, no issues
2. follow-up diff review
   - confirmed recording duration, waveform amplitude, attachment-strip state, upload state, and video processing progress no longer rely on page-wide `setState`
   - confirmed `ConversationScreen` keeps header and message list outside the composer listenable rebuild path
3. targeted QA / regression surface
   - `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/conversation/presentation/screens/conversation_banner_test.dart test/features/conversation/presentation/screens/conversation_audio_source_regression_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart test/features/conversation/presentation/widgets/compose_area_test.dart test/features/conversation/presentation/widgets/recording_overlay_test.dart`
   - result: all tests passed
4. visible UX delta
   - none intended; behavior should remain visually equivalent with a more stable header/list during recording and processing updates

Residual notes:
- no existing automated route harness was found for the exact `impl-backlog.md` observation flows `Conversation open -> record voice` and `Conversation open -> attach video`; the lane used the targeted widget/wired suite above as the best available fallback and leaves real route-level device QA as an outstanding follow-up gap
- group conversation incoming message/media churn is handled separately in `PERF-06`, but the group recording / processing overlay path still uses broader route state and remains an unresolved risk outside the scoped `PERF-03` lane

### PERF-06 Make Group Conversation Updates Incremental

Lane:
- `perf-exec/lane-d-perf06`

Implementation:
- kept the initial group snapshot load, but replaced incoming stream updates and successful local send completions with `_applyMessageUpdate` per-message upserts
- stopped rebuilding the full message page and full media map on incoming group activity; only the changed message plus its media entry are refreshed
- limited initial pending-media download updates to the affected message entry instead of rebuilding the entire media map
- added test instrumentation proving the wired screen no longer calls `getMessagesPage()` or bulk `getAttachmentsForMessages()` on a single incoming message event

Follow-up pattern:
1. local implementation checks
   - `flutter analyze lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart`
   - result: passed, no issues
2. follow-up diff review
   - confirmed `_loadMessages()` remains only for initial route hydration, not for incoming message events or successful send completions
   - confirmed stream-driven updates now reload only the changed message and its media attachments
3. targeted QA / regression surface
   - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_conversation_screen_test.dart`
   - result: all tests passed
4. visible UX delta
   - none intended; goal is reduced list churn, reduced attachment refresh fan-out, and better scroll stability during active group traffic

Residual notes:
- no automated route-level harness exists for the `impl-backlog.md` observation flow `Group conversation while messages arrive`; the wired/widget tests above are the best available fallback and real multi-user device QA remains outstanding
- group recording / processing composer state still follows the older broad route-state pattern; this lane intentionally focused on incremental message/media updates and did not change the recording overlay path

### PERF-07 Virtualize Feed With Slivers Or Builders

Lane:
- `perf-exec/lane-e-feed`

Implementation:
- replaced the eager Feed `SingleChildScrollView` surface with a `CustomScrollView` + `SliverList` structure and explicit spacer/divider entries
- preserved Feed sectioning and card identity by keeping `ValueKey(item.id)` on cards and wiring `findChildIndexCallback` so reused items stay stable under reorder and virtualization
- updated the Feed performance harness and added a dedicated screen test to prove the far-off tail card is not built until scrolled into view
- tuned the Feed sliver cache extent from `600` to `1200` after follow-up showed lazy-mounted cards were entering the viewport too late during fast scroll perf runs

Follow-up pattern:
1. local implementation checks
   - `flutter analyze lib/features/feed/presentation/screens/feed_screen.dart integration_test/feed_performance_test.dart test/features/feed/presentation/screens/feed_screen_test.dart`
   - result: passed, no issues
2. follow-up diff review
   - confirmed Feed now renders through `CustomScrollView` + `SliverList`
   - confirmed unread/read section spacing and `SessionDivider` placement were preserved as explicit feed entries
   - confirmed card identity remains keyed to stable feed ids so expanded / focused subtrees are reusable under sliver virtualization
3. targeted QA / regression surface
   - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart test/features/feed/presentation/screens/feed_wired_test.dart test/features/feed/presentation/widgets/feed_card_test.dart test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart test/features/feed/presentation/widgets/open_mode_card_body_test.dart test/features/feed/presentation/widgets/scrollable_message_preview_test.dart test/features/feed/presentation/widgets/connection_card_test.dart test/features/feed/presentation/widgets/introduction_connection_card_test.dart test/features/feed/integration/expanded_collapsed_card_test.dart test/features/feed/integration/feed_card_flow_test.dart`
   - `flutter test integration_test/feed_performance_test.dart -d macos`
   - result: all tests passed
   - final Feed perf route:
     - `Scroll`: avg `2.80ms`, p99 `12.42ms`, worst `19.58ms`
     - `Expand/Collapse`: avg `2.20ms`, p99 `24.48ms`, worst `30.86ms`
     - `Swipe-to-quote`: avg `1.41ms`, p99 `2.50ms`, worst `2.50ms`
     - `Compose input`: avg `7.86ms`, p99 `23.25ms`, worst `23.25ms`
4. visible UX delta
   - minor structural scroll-behavior change only, as expected for virtualization; no intentional redesign
   - no screenshot set was captured because no existing screenshot harness exists for this Flutter desktop route and the lane targeted no intentional visual redesign

Residual notes:
- the first `PERF-07` follow-up run exposed a stale `SingleChildScrollView` assumption in `integration_test/feed_performance_test.dart`; that harness was updated as part of the lane closeout
- `PERF-07` was not marked done until `PERF-09` reconciliation was rerun on top of the sliver-based Feed, per `plan.md`

### PERF-08 Virtualize Orbit With Slivers Or Builders

Lane:
- `perf-exec/lane-f-orbit`

Implementation:
- replaced the eager Orbit `SingleChildScrollView` + `Column` list surface with a `CustomScrollView` using slivers and a bounded cache extent
- kept the orbital hero section outside the virtualized list body so the list path owns only the list/filter/banner content
- replaced the embedded Orbit intros tab path with sliver-native intro rows so Orbit no longer depends on a nested `ListView` for intros rendering
- kept the existing `introsWidget` fallback for non-migrated callers, but moved `OrbitWired` to the new `OrbitIntrosViewData` sliver path

Follow-up pattern:
1. local implementation checks
   - `flutter analyze lib/features/orbit/presentation/screens/orbit_screen.dart lib/features/orbit/presentation/screens/orbit_wired.dart test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart`
   - result: passed, no issues
2. follow-up diff review
   - confirmed Orbit now renders through `CustomScrollView` + `SliverList`
   - confirmed the orbital hero remains separate from the list sliver path
   - confirmed the Orbit-managed intros path no longer embeds a nested `ListView`
3. targeted QA / regression surface
   - `flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart test/features/orbit/presentation/widgets/orbit_search_trigger_test.dart`
   - result: all tests passed
4. visible UX delta
   - minor structural scroll behavior change only, as expected for virtualization; no intentional redesign

Residual notes:
- no existing automated route harness was found for the exact `impl-backlog.md` observation flow `Orbit open -> scroll -> search`; the lane used the targeted screen and wired/widget suite above as the best available fallback and leaves real route-level device QA as an outstanding follow-up gap
- the non-sliver `introsWidget` fallback remains in `OrbitScreen` for compatibility, but `OrbitWired` now uses the sliver-native path that satisfies the scoped `PERF-08` requirement

## Wave 2

### PERF-09 Replace Full Feed Reloads With Incremental Thread State

Lane:
- `perf-exec/lane-e-feed`

Implementation:
- revalidated the existing incremental Feed refresh paths on top of the virtualized Feed surface without needing new production logic changes in `FeedWired`
- added missing regression coverage for the audit gaps:
  - focused inline reply draft / focus retention across a targeted contact refresh
  - explicit `reloadAllContacts` route-return behavior
  - explicit `reloadAllGroups` route-return behavior
- confirmed the existing incremental contact, group, intro, and reaction update paths still operate correctly after the `PERF-07` structural change

Follow-up pattern:
1. local implementation checks
   - `flutter analyze lib/features/feed/presentation/screens/feed_screen.dart lib/features/feed/presentation/screens/feed_wired.dart integration_test/feed_performance_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/feed/presentation/screens/feed_wired_test.dart`
   - result: passed, no issues
2. follow-up diff review
   - confirmed isolated incoming events still use targeted `_refreshContactFeedItem(...)` / `_refreshGroupFeedItem(...)` paths instead of falling back to full Feed reloads
   - confirmed explicit broad reloads remain only for cold start, explicit `reloadAllContacts` / `reloadAllGroups` route returns, and integrity fallback after targeted refresh errors
   - confirmed the remaining parent-level `setState` fan-out in `FeedWired` stayed functionally correct on top of sliver virtualization, so no further UI-scoping change was required for this plan
3. targeted QA / regression surface
   - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
   - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart test/features/feed/presentation/screens/feed_wired_test.dart test/features/feed/presentation/widgets/feed_card_test.dart test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart test/features/feed/presentation/widgets/open_mode_card_body_test.dart test/features/feed/presentation/widgets/scrollable_message_preview_test.dart test/features/feed/presentation/widgets/connection_card_test.dart test/features/feed/presentation/widgets/introduction_connection_card_test.dart test/features/feed/integration/expanded_collapsed_card_test.dart test/features/feed/integration/feed_card_flow_test.dart`
   - `flutter test integration_test/feed_performance_test.dart -d macos`
   - result: all tests passed
4. visible UX delta
   - none intended; this reconciliation pass was correctness and regression hardening for the already-implemented incremental update model
   - no screenshot set was captured because no existing screenshot harness exists for this Flutter desktop route and the pass targeted no intentional visual redesign

Residual notes:
- real device-route QA for `Feed idle while new message arrives` remains an open gap because the repo still lacks an automated route harness for that exact observation flow
- the Feed still uses route-level `setState` around the incremental store, but the scoped `PERF-09` acceptance criteria are satisfied: common incoming events refresh one contact or one group, route-return reload-all behavior is explicitly covered, and focus/draft state is retained across targeted refresh

### PERF-10 Replace Full Orbit Reloads With Incremental State Updates

Lane:
- `perf-exec/lane-f-orbit`

Implementation:
- added single-entity Orbit snapshot loaders for contacts and groups so `OrbitWired` can refresh one friend or one group without calling the full active/archived loaders
- replaced incoming chat, contact-update, and group-message stream handlers with targeted `_refreshOrbitFriend(...)` and `_refreshOrbitGroup(...)` paths
- converted friend and group archive, unblock, delete, and route-return updates to the same per-entity refresh pattern, leaving full Orbit reloads only for cold start, explicit reload-all route returns, and error fallback
- kept search and filter as derived projections over the in-memory source lists so query context survives targeted updates

Follow-up pattern:
1. local implementation checks
   - `flutter analyze lib/features/orbit/application/load_orbit_data_use_case.dart lib/features/orbit/application/load_orbit_groups_use_case.dart lib/features/orbit/presentation/screens/orbit_wired.dart test/features/orbit/application/load_orbit_data_use_case_test.dart test/features/orbit/application/load_orbit_groups_use_case_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart`
   - result: passed, no issues
2. follow-up diff review
   - confirmed broad `_loadOrbitData()` and `_loadGroupData()` calls were removed from isolated chat/contact/group event paths
   - confirmed full Orbit reloads remain only for cold start, explicit reload-all route returns, and integrity fallback after targeted refresh errors
   - confirmed targeted refresh preserves the canonical active/archived lists and recomputes search/filter projections from in-memory state instead of requerying all rows
3. targeted QA / regression surface
   - `flutter test test/features/orbit/application/load_orbit_data_use_case_test.dart test/features/orbit/application/load_orbit_groups_use_case_test.dart test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart test/features/orbit/presentation/widgets/orbit_search_trigger_test.dart`
   - result: all tests passed
4. visible UX delta
   - none intended; goal is reduced Orbit reload churn while preserving the existing layout and interactions from `PERF-08`

Residual notes:
- no existing automated route harness was found for the exact `impl-backlog.md` observation flows `Orbit open -> scroll -> search` and `Orbit idle while new message arrives`; the lane used targeted application, screen, and widget tests as the best available fallback and leaves real device-route QA as an outstanding follow-up gap
- explicit reload-all paths after QR scan and group-creation return were left intact on purpose because those routes can legitimately mutate multiple Orbit entities outside the safe single-row scope
