# Session 02 Plan: Production Cosmic Background and Feed Filter

# real scope

Add production-owned cosmic background rendering and the shared `AmbientBackground` filter that allows cosmic only on the explicit Feed surface.

In scope:

- production cosmic widget under `lib/`
- `AmbientBackground` support for `BackgroundPreference.cosmic`
- explicit per-call Feed surface signal with a default non-Feed behavior
- default rendering for every non-Feed surface, even with stored `cosmic`
- reduced-motion or disabled-animation static cosmic state
- widget tests for the Feed flag x preference matrix and production-source rendering

Out of scope:

- Feed preference loading or Settings return refresh
- simulator smoke and Feed performance closure
- changing route layouts or Feed cards
- applying cosmic to Settings, Conversation, Posts, Orbit, onboarding, groups, QR, share, or future non-Feed surfaces

# closure bar

This session is done when the app owns a production cosmic background widget, `AmbientBackground` renders cosmic only when called as Feed plus `BackgroundPreference.cosmic`, all other combinations render the existing default treatment, reduced-motion disables continuous cosmic drift/twinkle while keeping the visual recognizable, and direct ambient background tests pass without importing from `Test-Flight-Improv/`.

# source of truth

- `Test-Flight-Improv/81-feed-cosmic-background-option.md`
- `Test-Flight-Improv/81-feed-cosmic-background-option-session-breakdown.md`
- `Test-Flight-Improv/Background-Feature/cosmic_background.dart` as read-only design evidence
- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `test/features/identity/presentation/widgets/ambient_background_test.dart`

Current production code and tests win over the standalone design artifact.

# session classification

`implementation-ready`

# exact problem statement

Production code recognizes the `cosmic` preference after Session 01, but `AmbientBackground` still falls through to the default ambient treatment. The provided cosmic design lives under `Test-Flight-Improv/` and cannot be a production runtime dependency. The shared background widget also needs a central Feed-only guard so non-Feed surfaces never become cosmic by accidentally passing the stored preference.

# files and repos to inspect next

- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `Test-Flight-Improv/Background-Feature/cosmic_background.dart`
- `test/features/identity/presentation/widgets/ambient_background_test.dart`

# existing tests covering this area

`ambient_background_test.dart` currently proves child rendering, default background base color/glows, and the shared call-site inventory. It does not cover `cosmic`, Feed-only filtering, production-source import safety, or reduced-motion behavior.

# regression/tests to add first

- Extend `ambient_background_test.dart` for all four combinations of Feed flag x preference.
- Add proof that cosmic renders a production widget with recognizable gradient/starfield layers and child content.
- Add reduced-motion coverage with `MediaQueryData(disableAnimations: true)`.
- Add a static import scan that production `lib/` code does not import from `Test-Flight-Improv/`.

# step-by-step implementation plan

1. Add a production `CosmicBackground` widget under `lib/features/identity/presentation/widgets/`.
2. Port the provided design conservatively: deep radial gradient, drifting blooms, stars, and child content.
3. Add deterministic star generation or a testable bounded frame so widget tests do not depend on random placement.
4. Add reduced-motion handling that stops continuous animation and paints a static recognizable frame.
5. Add an `isFeedSurface` flag to `AmbientBackground`, defaulting to false.
6. Route `BackgroundPreference.cosmic` to `CosmicBackground` only when `isFeedSurface` is true; every other case renders `_DefaultAmbientBackground`.
7. Add direct widget/static tests and run `ambient_background_test.dart`.

# risks and edge cases

- A default `isFeedSurface: false` is required so new non-Feed surfaces remain default unless explicitly opted in.
- Continuous animation must not keep running when platform disable-animation is active.
- Tests should not wait for animation settlement because both default and cosmic backgrounds animate.
- The production widget must not import from the spec/docs directory.

# exact tests and gates to run

Direct tests:

- `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`

Named gates:

- No named gate is required by default. Run `./scripts/run_test_gates.sh baseline` only if startup/onboarding route code changes, and `./scripts/run_test_gates.sh completeness-check` only if gate definitions are edited.

# known-failure interpretation

Failures in `ambient_background_test.dart` are blocking. Unrelated generated cache noise or simulator artifacts are not blockers unless caused by touched production/test files.

# done criteria

- Production `CosmicBackground` exists under `lib/`.
- `AmbientBackground` has an explicit Feed surface signal and central filter.
- Feed/cosmic renders cosmic; Feed/default, non-Feed/cosmic, and non-Feed/default render default.
- Reduced-motion cosmic renders without an animated child builder.
- Direct ambient background tests pass.
- The breakdown ledger records Session `02-cosmic-background-filter` outcome.

# scope guard

Do not wire Feed to load the preference in this session. Do not edit Feed route behavior, performance tests, Settings return flow, or simulator smoke. Do not apply cosmic to any non-Feed route.

# accepted differences / intentionally out of scope

The production cosmic widget may use deterministic star placement for testability; the source doc does not require star positions to persist identically across mounts.

# dependency impact

Session `03-feed-preference-wiring` depends on the central `AmbientBackground` filter and Feed opt-in flag. If this session blocks, Feed should not pass the stored cosmic preference yet.

# execution result

Verdict: `accepted`

Evidence:

- Added production `CosmicBackground` under `lib/features/identity/presentation/widgets/cosmic_background.dart`.
- Added deterministic star generation for testable production rendering without importing the `Test-Flight-Improv/` artifact.
- Added disabled-animation/reduced-motion handling that renders a static cosmic frame without an `AnimatedBuilder`.
- Added `AmbientBackground.isFeedSurface`, defaulting to false.
- Centralized the Feed-only filter in `AmbientBackground`: `cosmic` renders cosmic only for Feed surfaces; non-Feed cosmic and default preferences render the existing default treatment.
- Extended `ambient_background_test.dart` for the Feed flag x preference matrix, reduced-motion static mode, production-source import safety, and existing call-site inventory.

Verification:

- `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
  - Result: passed on April 28, 2026.

Closure:

- Session `02-cosmic-background-filter` is accepted.
- No named gate was required because this session changed the shared widget only and did not alter startup routing or gate definitions.
