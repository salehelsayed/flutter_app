# Session 02 Plan: Production Mirrored Visual And Shared Background Rendering

## real scope

Move the mirrored cosmic visual into production-owned runtime code and route `BackgroundPreference.cosmicMirrored` through `AmbientBackground`. Preserve the existing `Default` and `Cosmic` treatments, child layering, hit testing, route constructors, shared-background surface inventory, and reduced-motion behavior.

This session may add direct widget tests for `AmbientBackground`, the new mirrored widget, and representative shared surfaces. It does not own Settings-to-Feed integration smoke, performance evidence, or final documentation closure; those belong to Session `03`.

## closure bar

The session is complete when production code under `lib/` owns a mirrored cosmic background widget, no runtime production code imports from `Test-Flight-Improv`, `AmbientBackground` maps `defaultBackground`, `cosmic`, and `cosmicMirrored` to distinct treatments, disabled animations keep mirrored cosmic static and readable, existing `CosmicBackground` behavior still passes, and direct tests prove mirrored rendering plus shared-surface inventory.

## source of truth

- Product intent and artifact description: `Test-Flight-Improv/83-mirrored-cosmic-background-option.md`
- Provided visual reference only: `Test-Flight-Improv/Background-Feature/cosmic_background_mirrored.dart`
- Existing production lifecycle pattern: `lib/features/identity/presentation/widgets/cosmic_background.dart`
- Existing renderer switch: `lib/features/identity/presentation/widgets/ambient_background.dart`
- Direct renderer tests: `test/features/identity/presentation/widgets/ambient_background_test.dart`

## session classification

`implementation-ready`

## exact problem statement

After Session `01`, the app can store and select `cosmicMirrored`, but `AmbientBackground` only has a compile-safe fallback to the existing `CosmicBackground`. Users need the mirrored preference to render a production-owned mirrored cosmic treatment that is distinguishable from existing `Cosmic`, reduced-motion safe, and shared across the existing selected-background surfaces.

## files and repos to inspect next

- `lib/features/identity/presentation/widgets/cosmic_background.dart`
- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `Test-Flight-Improv/Background-Feature/cosmic_background_mirrored.dart`
- `test/features/identity/presentation/widgets/ambient_background_test.dart`
- Representative surface tests already asserting cosmic rendering, if a direct constructor test is cheap: Feed, Conversation, First Time Experience, Identity Choice, Posts.

## existing tests covering this area

- `ambient_background_test.dart` covers default rendering, existing cosmic rendering, disabled animations for existing cosmic, production import guard, and shared-background surface inventory.
- Representative screen tests already assert existing cosmic appears on some surfaces.

Current gaps are a production mirrored widget, mirrored preference mapping in `AmbientBackground`, mirrored disabled-animation behavior, mirrored-vs-existing-cosmic distinguishability, and import guard coverage for the mirrored artifact.

## regression/tests to add first

- Extend `ambient_background_test.dart` to assert `BackgroundPreference.cosmicMirrored` renders `CosmicBackgroundMirrored`, uses distinct root/painter keys, and does not render `CosmicBackground`.
- Extend disabled-animation coverage for mirrored cosmic to ensure no animated builder/ticker-driven child is exposed and a static painter remains.
- Extend the production import guard to reject `Test-Flight-Improv`, `Background-Feature/cosmic_background.dart`, and `Background-Feature/cosmic_background_mirrored.dart`.
- Keep the shared-background inventory test passing.

## step-by-step implementation plan

1. Add `lib/features/identity/presentation/widgets/cosmic_background_mirrored.dart` by adapting the provided artifact to production patterns from `CosmicBackground`: deterministic seeded stars, `MediaQuery.disableAnimations`/`accessibleNavigation` handling, stopped clock/controller in reduced motion, `RepaintBoundary`, stable root/painter keys, and child layering.
2. Update `AmbientBackground` to import and return `CosmicBackgroundMirrored` for `BackgroundPreference.cosmicMirrored`.
3. Update direct tests for mirrored rendering, distinguishability from existing cosmic, reduced motion, and import guard.
4. Run focused direct tests for ambient rendering and representative existing cosmic tests as needed.
5. Update this plan and the breakdown ledger with exact evidence and residuals.

## risks and edge cases

- Duplicating the standalone artifact directly would introduce random star placement and no reduced-motion stop path, which would make tests flaky and accessibility weaker.
- `AmbientBackground` must not restart the default animation controller for non-default preferences.
- Existing `CosmicBackground` keys and behavior must remain unchanged.
- Production code must not import from `Test-Flight-Improv`.

## exact tests and gates to run

- `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
- Representative non-Feed direct test only if touched constructor behavior requires it.

No named gate is required unless this session changes route orchestration, app bootstrap, or gate definitions.

## known-failure interpretation

Failures in `ambient_background_test.dart` are session-blocking. Existing large screen-test failures are blocking only if they trace to the new enum/widget mapping; unrelated pre-existing failures should be recorded with exact failure text and not hidden.

## done criteria

- Production mirrored widget exists under `lib/`.
- `AmbientBackground` maps mirrored preference to the mirrored widget.
- Existing cosmic still maps to `CosmicBackground`.
- Mirrored disabled-animation coverage passes.
- Import guard rejects production imports from `Test-Flight-Improv`.
- Focused direct tests pass or exact blockers are recorded.

## scope guard

Do not change Settings behavior, storage strings, route propagation architecture, screen layout, Feed interactions, group/post/message transport behavior, or integration smoke files in this session.

## accepted differences / intentionally out of scope

The exact visual pixel match to the standalone artifact is accepted as approximate as long as the mirrored treatment swaps teal/violet emphasis, widens the violet bloom, includes the pink accent, remains recognizable, and uses production lifecycle safeguards. Integration smoke, performance, readability matrix updates, and final source-doc closure are deferred to Session `03`.

## dependency impact

Session `03` depends on this session to provide inspectable mirrored widget keys and production routing so smoke, visual/readability, performance, and final inventory evidence can distinguish `Cosmic` from mirrored cosmic.

## reviewer pass

The plan is sufficient. It narrows the production visual work to a single widget and renderer switch, keeps tests focused on the shared-background seam, and avoids reopening Settings or route architecture.

## arbiter verdict

No structural blockers remain. The plan is safe to implement now.

## execution result

Session `02-production-mirrored-background` is accepted.

Landed changes:

- Added production-owned `CosmicBackgroundMirrored` under `lib/features/identity/presentation/widgets/`.
- Adapted the standalone mirrored artifact into the existing production lifecycle pattern: deterministic seeded stars, reduced-motion/static mode, stopped controller/clock when animations are disabled, repaint boundaries, and stable root/painter keys.
- Updated `AmbientBackground` so `BackgroundPreference.cosmicMirrored` maps to `CosmicBackgroundMirrored`, while existing `cosmic` still maps to `CosmicBackground` and default remains the default ambient treatment.
- Extended shared-background tests for mirrored rendering, distinguishability from existing cosmic, disabled-animation static paint, production import guard coverage, and current shared-background surface inventory.

Verification:

- Passed: `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
- Passed: `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`

Residual for later sessions:

- Session `03` still owns Settings-to-Feed smoke, representative non-Feed acceptance evidence, readability/performance evidence, durable coverage docs, and final source-doc verdict.
