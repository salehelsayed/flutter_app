# Session 05 Plan: Acceptance, Performance, Inventory, And Closure

## real scope

Record final rollout evidence from the local fallback, classify what is closed, and preserve explicit follow-ups for work not completed in this pass.

## closure bar

The rollout may close only as `accepted_with_explicit_follow_up`: the core readable-theme contract, selected-background propagation, and representative Settings/Feed/Conversation/Orbit widget evidence landed, while exhaustive inventory, representative-light integration, transient overlay migration, and Feed performance remain required before a production light background ships.

## source of truth

- `Test-Flight-Improv/84-background-readable-theme-extension.md`
- `Test-Flight-Improv/84-background-readable-theme-extension-session-breakdown.md`
- direct test outputs from this rollout

## session classification

`acceptance-only`

## exact problem statement

The full source doc includes exhaustive inventory, integration, and performance evidence. The local fallback produced a safe representative implementation but not exhaustive production-light acceptance.

## files and repos to inspect next

- `integration_test/settings_background_choice_smoke_test.dart`
- `integration_test/feed_performance_test.dart`
- `Test-Flight-Improv/02-integration-test-coverage.md`
- current hard-coded color search output across shared-background surfaces

## existing tests covering this area

Direct unit/widget coverage now exists for the readable contract and representative migrated surfaces. Existing integration/performance harnesses remain available.

## regression/tests to add first

Before shipping a production light background, add or extend integration coverage for dark-to-light and light-to-dark readable foreground consistency, and run Feed performance with the readable theme active.

## step-by-step implementation plan

1. Run direct unit/widget evidence.
2. Run existing Settings background-choice integration smoke when simulator build allows.
3. Record analyzer status and known existing analyzer warnings.
4. Update source doc and breakdown ledger with accepted follow-ups.

## risks and edge cases

Do not overclaim exhaustive light-background readiness while hard-coded background-sensitive colors still remain outside representative migrated surfaces.

## exact tests and gates to run

- `flutter test --no-pub test/core/theme/background_readable_colors_test.dart`
- `flutter test --no-pub test/features/identity/presentation/widgets/ambient_background_test.dart`
- `flutter test --no-pub test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/conversation/presentation/widgets/conversation_header_test.dart test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
- `flutter analyze --no-pub lib/core/theme/background_readable_colors.dart lib/core/theme/app_theme.dart lib/features/identity/presentation/widgets/ambient_background.dart test/core/theme/background_readable_colors_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart`
- `flutter test --no-pub -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/settings_background_choice_smoke_test.dart`

## known-failure interpretation

A broad targeted analyzer over all changed presentation files currently reports existing issues in `feed_screen.dart`, `settings_screen.dart`, and long-lived tests. These are not introduced by the readable-theme contract but should be cleaned separately if full-file analyzer cleanliness becomes a release gate.

## done criteria

Persist the breakdown final verdict and source-doc evidence without claiming exhaustive production-light readiness.

## scope guard

Do not add a production light background option in this session.

## accepted differences / intentionally out of scope

Exhaustive shared-background hard-coded color inventory, transient overlay migration, representative-light integration smoke, and Feed performance are explicit follow-ups before production light backgrounds ship.

## dependency impact

Future light background work can build on the readable theme contract but must not ship until the explicit follow-ups are closed.

## closure result

`accepted_with_explicit_follow_up`

Evidence:

- `flutter test --no-pub test/core/theme/background_readable_colors_test.dart` passed.
- `flutter test --no-pub test/features/identity/presentation/widgets/ambient_background_test.dart` passed.
- `flutter test --no-pub test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/conversation/presentation/widgets/conversation_header_test.dart test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` passed.
- `flutter analyze --no-pub lib/core/theme/background_readable_colors.dart lib/core/theme/app_theme.dart lib/features/identity/presentation/widgets/ambient_background.dart test/core/theme/background_readable_colors_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart` passed.
- `flutter test --no-pub -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/settings_background_choice_smoke_test.dart` passed.
- `flutter test --no-pub -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/feed_performance_test.dart` passed. Feed scroll stayed within the source-doc budget: average `2.86ms`, P99 `10.89ms`, worst `19.38ms`; cosmic scroll average `1.90ms`, P99 `8.05ms`, worst `8.18ms`; mirrored cosmic scroll average `1.65ms`, P99 `7.56ms`, worst `8.66ms`.
