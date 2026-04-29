# Final verdict

Session `03-acceptance-performance-closure` is `acceptance-only`.

# real scope

- Extend existing integration/performance acceptance harnesses to include Daylight Lagoon.
- Run the final direct tests that can run locally.
- Attempt device-backed integration/performance commands where available, or record the exact environment limitation.
- Update the source doc and breakdown with the final verdict.

# closure bar

The doc can close when the production Daylight option has direct unit/widget evidence, representative surface evidence, smoke/performance harness coverage, and a persisted final verdict. Device-only commands may remain explicit follow-up only if the local environment lacks a target device.

# source of truth

- `Test-Flight-Improv/86-daylight-lagoon-background-option.md`
- `Test-Flight-Improv/86-daylight-lagoon-background-option-session-breakdown.md`
- Existing smoke/performance harnesses:
  - `integration_test/settings_background_choice_smoke_test.dart`
  - `integration_test/feed_performance_test.dart`

# session classification

`acceptance-only`

# exact problem statement

The implementation and representative widgets now cover Daylight locally, but final acceptance needs the existing Settings-to-Feed smoke and Feed performance harnesses to know about the first production light background.

# files and repos to inspect next

- `integration_test/settings_background_choice_smoke_test.dart`
- `integration_test/feed_performance_test.dart`
- final docs under `Test-Flight-Improv/86-*`

# existing tests covering this area

The smoke currently covers default, cosmic, and mirrored cosmic. The performance harness currently compares cosmic and mirrored cosmic against default.

# regression/tests to add first

Add Daylight selection/reopen/switch-back coverage to the smoke and a Daylight scroll performance scenario to the performance harness.

# step-by-step implementation plan

1. Extend the smoke harness with Daylight selection, persistence, Feed rendering, and dark-background switch-back assertions.
2. Extend Feed performance with a Daylight background comparison.
3. Run final local direct suites.
4. Attempt integration/performance commands if a device is available; otherwise record the device block.
5. Update closure docs and breakdown verdict.

# risks and edge cases

- Integration tests may be device-backed in this repo.
- Performance evidence may be environment-sensitive and should not be overclaimed without a real device/simulator run.
- Smoke assertions should avoid depending on animation settling.

# exact tests and gates to run

Local direct suites:

```bash
flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/settings/presentation/screens/settings_wired_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart test/core/theme/background_readable_colors_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/orbit/presentation/screens/orbit_screen_loading_test.dart
```

Device-backed acceptance when a device is available:

```bash
flutter test integration_test/settings_background_choice_smoke_test.dart -d <device>
flutter test integration_test/feed_performance_test.dart -d <device>
```

Named gates: none unless behavior beyond background/readable rendering changed.

# known-failure interpretation

Direct local failures are blocking. Device/performance commands that cannot start due to missing device are recorded as explicit follow-up, not as passed evidence.

# done criteria

- Smoke/performance harnesses include Daylight.
- Final direct suites pass locally.
- Final verdict is persisted in the breakdown and source doc.

# scope guard

Do not widen into unrelated route behavior, transport, messaging, posts, groups, or notification gates.

# accepted differences / intentionally out of scope

Simulator/device chrome and performance results are accepted with explicit follow-up only if the local environment cannot run them.

# dependency impact

This is the final doc closure session. No later session should run unless the final verdict remains `still_open` or `blocked`.
