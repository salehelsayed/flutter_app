# Session 03 Plan: Mirrored Option Smoke, Performance, Inventory, And Closure

## real scope

Validate the combined mirrored background feature after Sessions `01` and `02`. This session owns acceptance evidence, representative smoke updates, mirrored Feed performance evidence, representative non-Feed surface evidence, durable coverage-doc updates, source-doc completion notes, and the final breakdown verdict.

This session does not add new product behavior beyond test/acceptance hooks needed to prove the already-landed Settings and renderer work.

## closure bar

The source doc can close when direct tests prove three-option Settings behavior, mirrored persistence, production mirrored rendering, reduced-motion safety, a representative non-Feed shared surface, and Feed route behavior; smoke covers Settings -> mirrored -> Feed -> reopen Settings -> existing cosmic -> Feed -> default restore; performance evidence covers mirrored Feed scrolling against a same-run default baseline or records an exact environment block; docs record exact commands, passed evidence, residual device-only gaps, and final verdict.

## source of truth

- Source doc: `Test-Flight-Improv/83-mirrored-cosmic-background-option.md`
- Breakdown and session plans under `Test-Flight-Improv/83-mirrored-cosmic-background-option-*`
- Coverage inventory: `Test-Flight-Improv/02-integration-test-coverage.md`
- Gate definitions: `Test-Flight-Improv/test-gate-definitions.md`
- Existing smoke/performance tests: `integration_test/settings_background_choice_smoke_test.dart`, `integration_test/feed_performance_test.dart`

## session classification

`acceptance-only`

## exact problem statement

The implementation now supports mirrored storage, Settings selection, and production rendering, but the final acceptance evidence still needs to prove the combined user journey, representative non-Feed rendering, Feed performance, and durable documentation closure without overclaiming unavailable simulator/device coverage.

## files and repos to inspect next

- `integration_test/settings_background_choice_smoke_test.dart`
- `integration_test/feed_performance_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `Test-Flight-Improv/83-mirrored-cosmic-background-option.md`
- `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-breakdown.md`
- `Test-Flight-Improv/02-integration-test-coverage.md`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

Sessions `01` and `02` added or ran focused storage, Settings picker, app-shell, ambient renderer, and Feed screen tests. Existing smoke and performance files cover only the original `Cosmic` background and must be extended for mirrored acceptance.

## regression/tests to add first

- Update `integration_test/settings_background_choice_smoke_test.dart` for mirrored selection, persistence after Settings reopen, switch to existing `Cosmic`, and restore `Default`.
- Add one direct non-Feed mirrored shared-surface assertion, preferably in `conversation_screen_test.dart`.
- Update `integration_test/feed_performance_test.dart` with mirrored cosmic scroll performance against a default baseline.

## step-by-step implementation plan

1. Extend the Settings background smoke with mirrored selection and existing-cosmic/default switching assertions.
2. Add a representative non-Feed mirrored rendering assertion to `conversation_screen_test.dart`.
3. Add mirrored Feed performance coverage alongside existing cosmic performance coverage.
4. Run the final direct batch from Sessions `01` and `02`, the non-Feed representative test, and updated smoke/performance commands where the local device target allows.
5. Update `02-integration-test-coverage.md`, the source doc, the Session `03` plan, and this breakdown with exact evidence and residuals.
6. Persist final breakdown verdict.

## risks and edge cases

- Desktop integration tests can require an explicit device target when multiple devices are available.
- Feed performance can fail from environment noise; record exact output and do not overclaim if frame timings are unavailable.
- Existing dirty user changes in Settings screen/wired tests must not be overwritten.
- Smoke should distinguish existing `Cosmic` from mirrored cosmic by widget type/key, not only by storage string.

## exact tests and gates to run

- `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/posts/phase1/app_shell_controller_test.dart`
- `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test integration_test/settings_background_choice_smoke_test.dart -d macos`
- `flutter test integration_test/feed_performance_test.dart -d macos`

Named gates are not required unless gate definitions are edited. If `02-integration-test-coverage.md` changes only as documentation, `completeness-check` is not required.

## known-failure interpretation

Direct test failures in touched feature tests are blocking. Integration/performance failures caused by missing or ambiguous device targets are environment blocks only when exact command output is recorded; actual assertion failures in mirrored behavior are blocking.

## done criteria

- Updated smoke, non-Feed, and performance evidence exists.
- All runnable direct tests pass.
- Any device/performance environment limitations are recorded with exact commands.
- Coverage doc and source doc reflect mirrored evidence.
- Breakdown ledger marks all sessions resolved and persists final verdict `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `stale/already-covered`.

## scope guard

Do not redesign UI, change production behavior beyond acceptance support, add new named gates unless a new integration/cross-feature test truly needs classification, or widen transport/messaging/group/posts behavior.

## accepted differences / intentionally out of scope

Mobile-device-only and heavy Conversation performance evidence may remain explicit follow-up if unavailable locally. Pixel-perfect visual matching is not required; direct keys and production renderer tests carry distinguishability.

## dependency impact

This is the final session for doc `83`. Later work should reopen only on real regressions or explicitly recorded residual device/performance follow-up.

## reviewer pass

The plan is sufficient. It focuses on combined acceptance and documentation closure without changing the already-landed implementation seams.

## arbiter verdict

No structural blockers remain. The plan is safe to execute now.

## execution result

Session `03-acceptance-performance-closure` is accepted.

Landed changes:

- Extended `integration_test/settings_background_choice_smoke_test.dart` to cover selecting mirrored cosmic, persisting it, seeing `CosmicBackgroundMirrored` on Feed, reopening Settings with mirrored selected, switching to existing `Cosmic`, confirming `CosmicBackground`, and restoring `Default`.
- Added representative non-Feed mirrored rendering coverage in `test/features/conversation/presentation/screens/conversation_screen_test.dart`.
- Extended `integration_test/feed_performance_test.dart` with mirrored cosmic scroll performance against a same-run default baseline.
- Updated `Test-Flight-Improv/02-integration-test-coverage.md` and the source doc with final mirrored evidence and residual-only device/performance notes.

Verification:

- Passed: `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/posts/phase1/app_shell_controller_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/conversation/presentation/screens/conversation_screen_test.dart`
- Passed: `flutter test integration_test/settings_background_choice_smoke_test.dart -d macos`
- Passed: `flutter test integration_test/feed_performance_test.dart -d macos`
  - Existing cosmic default baseline Avg/P90/P99/Worst: `2.31/3.45/8.67/13.17ms`.
  - Existing cosmic scroll Avg/P90/P99/Worst: `2.08/4.54/8.57/11.45ms`.
  - Mirrored cosmic default baseline Avg/P90/P99/Worst: `2.00/3.30/7.23/7.45ms`.
  - Mirrored cosmic scroll Avg/P90/P99/Worst: `1.85/3.43/7.67/10.87ms`.

Residual-only item:

- Mobile-device and heavy Conversation-specific performance validation remains optional release-confidence evidence; no implementation gap remains for doc `83`.

Closure verdict:

`closed`
