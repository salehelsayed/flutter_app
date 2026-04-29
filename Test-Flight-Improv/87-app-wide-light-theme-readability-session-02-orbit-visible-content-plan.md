# Session 02 Plan: Orbit visible content and observed Daylight failure closure

## real scope

This session closes the observed Orbit Daylight Lagoon readability failure for visible content paths: top labels, Friends header, QR/scan pills, filter tabs and count badges, friend rows, group rows, archived/no-results states, intro banner text, search dock, and row chevrons.

It does not change introduction acceptance, group membership, QR scan behavior, navigation semantics, swipe action behavior, persistence, or transport logic.

## closure bar

Orbit visible content is good enough when Daylight Lagoon uses readable foreground/surface roles for the visible list and chrome named above, actual friend and group rows have readable usernames/previews/timestamps/actions, archived/no-results and search states are readable, and existing dark-background behavior remains role-backed. A focused Orbit widget test must prove the Daylight visible path with actual rows.

## source of truth

- `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
- `Test-Flight-Improv/87-app-wide-light-theme-readability-session-breakdown.md`
- `lib/core/theme/background_readable_colors.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- Orbit widgets under `lib/features/orbit/presentation/widgets/`
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

Current code and tests win over stale prose. Named gate membership follows `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.

## session classification

`implementation-ready`

## exact problem statement

Orbit currently has partial light-background support for loading and no-results paths, but visible content still includes dark-background-only white or muted-white foregrounds and translucent white card surfaces. On Daylight Lagoon this can make the Friends header, filters, rows, previews, timestamps, and search controls low contrast or effectively invisible.

## files and repos to inspect next

- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/orbit/presentation/widgets/friends_list_header.dart`
- `lib/features/orbit/presentation/widgets/friends_filter_toggle.dart`
- `lib/features/orbit/presentation/widgets/friend_row.dart`
- `lib/features/orbit/presentation/widgets/group_row.dart`
- `lib/features/orbit/presentation/widgets/archived_empty_state.dart`
- `lib/features/orbit/presentation/widgets/orbit_search_dock.dart`
- `lib/features/groups/presentation/widgets/group_type_badge.dart`
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`

## existing tests covering this area

`orbit_screen_loading_test.dart` already covers loading placeholders, Daylight Lagoon background rendering, bottom nav spacing, and search dock placement. It does not cover actual friend/group rows, visible header/filter text, or search dock foreground colors on Daylight Lagoon.

## regression/tests to add first

Add a focused widget test that renders Orbit under `BackgroundPreference.daylightLagoon` with one friend, one group, active filters, and visible search/chrome; then assert representative text/icon colors meet contrast against the readable surfaces and the Daylight background is present.

## step-by-step implementation plan

1. Import `BackgroundReadableColors` into the Orbit widgets with hardcoded foreground/surface colors.
2. Replace background-sensitive row, header, filter, archived empty, intro banner, and search dock colors with readable roles.
3. Keep semantic accent colors for positive actions where contrast remains sufficient; darken group type badge accents on light surfaces.
4. Add a visible-content Daylight Lagoon widget regression in `orbit_screen_loading_test.dart`.
5. Run `dart format` on touched Dart files.
6. Run `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`.

## risks and edge cases

- The Orbit header has two `Close Friends` labels with different hierarchy; both must be readable without relying on white text.
- Search dock is bottom-positioned and should remain readable without changing layout.
- Group type badge colors need a darker light-surface variant or the badge can become decorative but unreadable.
- Swipe action buttons stay gradient/dark action surfaces and are not changed unless direct evidence shows they are unreadable.

## exact tests and gates to run

- `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`

No named gate is required because this session changes only Orbit presentation color roles and widget tests. Run intro companion tests only if introduction behavior changes; this session must avoid that.

## known-failure interpretation

Any failure in the Orbit widget test is in scope. Asset-loading noise already suppressed by existing helpers remains treated as unrelated test harness noise. Broader dirty worktree changes are not part of this session unless they affect the Orbit test directly.

## done criteria

- Orbit visible rows/header/filter/search/archived/intro banner colors consume readable roles.
- Daylight Lagoon visible-content test passes.
- Breakdown ledger marks Session 02 accepted with exact verification.

## scope guard

Do not alter Orbit data loading, intro actions, group actions, navigation, archive/delete/block behavior, QR scan behavior, or app-shell state. Do not broaden into group list or conversation surfaces; those are later sessions.

## accepted differences / intentionally out of scope

Orbit swipe action buttons remain gradient action surfaces in this session because their white foregrounds sit on intentional dark/accent gradients, not on Daylight Lagoon's light surface.

## dependency impact

Session 07 may revisit Orbit confirmation dialogs and other transient Orbit surfaces. It should not reopen the main visible Orbit list path unless a real regression is found.

