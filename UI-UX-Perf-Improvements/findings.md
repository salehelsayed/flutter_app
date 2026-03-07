# UI/UX Performance Findings

Audit date: 2026-03-07

This review treats the request's `PREF-xx` wording as the `PERF-xx` ids used by `UI-UX-Perf-Improvements/plan.md`.

Scope reviewed:
- `UI-UX-Perf-Improvements/plan.md`
- `UI-UX-Perf-Improvements/impl-backlog.md`
- `UI-UX-Perf-Improvements/execution-log.md`
- current implementation and targeted tests in `lib/`, `test/`, and `integration_test/`

Out of scope:
- `PERF-02` and `PERF-04` were intentionally excluded from `plan.md`, so they are not audited below.

## Summary

- The main remaining implementation gaps are in `PERF-03`, `PERF-09`, and `PERF-10`.
- The main remaining validation gaps are in `PERF-00`, `PERF-07`, `PERF-08`, and `PERF-11`.
- I did not find a new sliver/virtualization regression in Feed or Orbit. The code there largely matches the plan, but the follow-up QA bar from the plan is not fully met.

Regression slice run during this review:

```bash
flutter test -r compact \
  test/features/home/presentation/widgets/user_avatar_test.dart \
  test/features/conversation/presentation/screens/conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/features/feed/presentation/screens/feed_screen_test.dart \
  test/features/feed/presentation/screens/feed_wired_test.dart \
  test/features/orbit/presentation/screens/orbit_wired_test.dart \
  test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart
```

Result: all tests passed.

## PERF-00 Baseline And Regression Gates

Status: partial

Gaps:
- The baseline is still heavily anchored to one synthetic macOS Feed harness plus widget tests. The exact observation routes required by the backlog remain without route-level automation for:
  - `Feed idle while new message arrives`
  - `Orbit open -> scroll -> search`
  - `Orbit idle while new message arrives`
  - `Conversation open -> record voice`
  - `Conversation open -> attach video`
  - `Group conversation while messages arrive`
- Screenshot / golden coverage is still missing even though the plan called for screenshots, clips, and before/after captures for route validation and visible deltas.

Evidence:
- `UI-UX-Perf-Improvements/execution-log.md:425-459`
- `UI-UX-Perf-Improvements/plan.md:225-231`
- `UI-UX-Perf-Improvements/plan.md:517`

## PERF-01 Move Avatar Lookup And Caching Out Of Widget Build

Status: implemented for hot list surfaces, but not fully centralized

What is complete:
- `UserAvatar` no longer does sync disk probing in `build`; it now resolves contact avatar paths asynchronously and caches misses/hits in shared notifiers.
- Evidence: `lib/features/home/presentation/widgets/user_avatar.dart:55-133`

Gaps:
- Self-avatar loading is still duplicated and still uses synchronous file probing in multiple wired layers:
  - `lib/features/feed/presentation/screens/feed_wired.dart:182-208`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart:226-252`
  - `lib/features/settings/presentation/screens/settings_wired.dart:71-97`
- That means the hot scroll-path problem is fixed, but the broader backlog goal of moving avatar lookup/caching into a dedicated shared resolver/service is still only partially done.

## PERF-03 Isolate Recording, Processing, And Progress State From Page Rebuilds

Status: partially complete

What is complete:
- The 1:1 conversation path has the intended scoped composer state, and there is a regression test proving header and message-list stability during composer updates.
- Evidence: `test/features/conversation/presentation/screens/conversation_screen_test.dart:215-292`

Gaps:
- Group conversation still uses route-level `setState` for recording duration, waveform/amplitude, upload state, and voice-send completion:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart:573-692`
- That leaves the group conversation header and message list inside the rebuild fan-out that `PERF-03` was meant to isolate when the shared pattern applies.
- There is no equivalent group regression proving that recording / processing updates leave the existing group header and message list mounted. Current group tests cover incremental message/media upserts, not composer-state isolation.

Evidence:
- `test/features/groups/presentation/group_conversation_wired_test.dart:268-310`
- `UI-UX-Perf-Improvements/execution-log.md:431-432`

## PERF-06 Make Group Conversation Updates Incremental

Status: mostly implemented, with one important follow-up gap

What is complete:
- Incoming group messages now upsert without reloading the full page or re-querying the entire media map.
- Evidence: `test/features/groups/presentation/group_conversation_wired_test.dart:268-310`

Gaps:
- Scroll-position preservation is still implicit rather than explicit. `_applyMessageUpdate(...)` updates `_messages` / `_mediaMap`, but there is no anchor/offset preservation logic for the case where the user is reading older messages while new group activity arrives.
- There is also no test covering "user scrolled away from the newest message and then incoming activity arrives", even though the backlog acceptance explicitly called for preserving scroll position.
- The exact route from the backlog, `Group conversation while messages arrive`, is still only covered by widget tests rather than live multi-user route automation.

Evidence:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart:212-218`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart:544-566`
- `UI-UX-Perf-Improvements/execution-log.md:433`

## PERF-07 Virtualize Feed With Slivers Or Builders

Status: implementation looks complete; follow-up evidence is still incomplete

What is complete:
- Feed uses `CustomScrollView` + `SliverList` rather than `SingleChildScrollView` + `Column`.
- Stable `ValueKey`s are attached to feed cards, and the current feed screen / feed wired tests pass.

Gaps:
- I did not find a new structural Feed virtualization bug, but the plan's follow-up bar is still not fully met:
  - no real route-video / screenshot capture
  - no production-data launch harness
  - no exact device-route automation for `Feed idle while new message arrives`
- In practice this means `PERF-07` is code-complete but still validation-incomplete.

Evidence:
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `UI-UX-Perf-Improvements/execution-log.md:425-429`
- `UI-UX-Perf-Improvements/execution-log.md:456-459`

## PERF-08 Virtualize Orbit With Slivers Or Builders

Status: implementation looks complete; follow-up evidence is still incomplete

What is complete:
- Orbit uses `CustomScrollView` / slivers for the list surface.
- `OrbitWired` now feeds `OrbitIntrosViewData` into the sliver-native intro path instead of depending on the old embedded intros widget path.

Gaps:
- `OrbitScreen` still exposes an `introsWidget` fallback (`lib/features/orbit/presentation/screens/orbit_screen.dart:416-423`). Current wired code does not use it, but the screen API still allows a future caller to bypass the sliver-native path and reintroduce an eager intro body.
- The required `Orbit open -> scroll -> search` and `Orbit idle while new message arrives` follow-up routes are still not covered by exact route-level device automation or screenshot capture.

Evidence:
- `lib/features/orbit/presentation/screens/orbit_screen.dart:416-423`
- `UI-UX-Perf-Improvements/execution-log.md:429-430`
- `UI-UX-Perf-Improvements/execution-log.md:456-459`

## PERF-09 Replace Full Feed Reloads With Incremental Thread State

Status: implemented to targeted-snapshot level, but not to the full incremental ideal described in the backlog

What is complete:
- Common Feed events now target one contact or one group instead of calling the old full-feed load path.
- Reaction changes stay scoped to the affected message subtree.

Gaps:
- Targeted refreshes still rebuild the full affected thread from the database:
  - contact refresh calls `loadContactFeedSnapshot(...)`, which calls `loadConversation(...)` for the entire contact history plus attachments
  - group refresh calls `loadGroupFeedSnapshot(...)`, which reloads up to 200 group messages
- This means the implementation is "one-thread-at-a-time" rather than truly "change-at-a-time". Large threads still pay work proportional to thread size.
- `FeedWired` still applies those targeted snapshots through parent `setState`, so one-thread refreshes still rebuild the whole Feed route. `plan.md` explicitly said to re-check that fan-out after `PERF-07`, and that deeper UI scoping was not done.

Evidence:
- `lib/features/feed/presentation/screens/feed_wired.dart:306-371`
- `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart:16-45`
- `lib/features/feed/application/load_group_feed_snapshot_use_case.dart:6-20`

## PERF-10 Replace Full Orbit Reloads With Incremental State Updates

Status: implemented to targeted-entity reload level, but not to the full incremental model described in the backlog

What is complete:
- Single incoming events no longer trigger full `loadOrbitData()` / `loadOrbitGroups()` reloads in the common event paths.
- Existing tests prove the changed friend/group is refreshed in isolation at the repository-query level.

Gaps:
- `OrbitWired` still rebuilds the entire route via `setState` when a single friend or group changes. So the data refresh is incremental, but the UI scoping is still route-wide.
- Search/filter projections are not cached separately from source state:
  - `_displayedFriends` recomputes filtered friends on every build
  - `OrbitScreen._buildMergedItems()` rebuilds and sorts the merged friend/group projection on every build
- This misses the backlog subtask that asked for cached projections separate from source state.

Evidence:
- `lib/features/orbit/presentation/screens/orbit_wired.dart:324-357`
- `lib/features/orbit/presentation/screens/orbit_wired.dart:760-783`
- `lib/features/orbit/presentation/screens/orbit_screen.dart:162-186`
- `lib/features/orbit/application/load_orbit_data_use_case.dart:53-125`
- `lib/features/orbit/application/load_orbit_groups_use_case.dart:65-132`

## PERF-11 Remove Remaining Nested Layout Hotspots

Status: mostly done, but not fully closed

What is complete:
- I did not find the named `IntrinsicWidth` / nested `shrinkWrap` issues still present in the audited hot paths.

Gaps:
- `ScrollableMessagePreview` still uses `ShaderMask`, so this item is not literally fully cleaned up. The backlog allowed deferring that only if it stopped being a measured hotspot; the repo documents that defer, but the code is still there.
- Screenshot / golden follow-up for the subtle layout-preservation changes is still missing, so the plan's visual-regression requirement is not fully satisfied.

Evidence:
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart:134-159`
- `UI-UX-Perf-Improvements/execution-log.md:456-459`

## Overall Read

- The repo appears to have implemented the plan's main code changes for `PERF-01`, `PERF-06`, `PERF-07`, and `PERF-08`.
- The biggest remaining code debt is that `PERF-03`, `PERF-09`, and `PERF-10` stop at "targeted route updates" rather than reaching the more fine-grained controller/notifier/store depth described in the backlog.
- The biggest remaining process debt is `PERF-00`: several required route validations and before/after visual captures still do not exist.
