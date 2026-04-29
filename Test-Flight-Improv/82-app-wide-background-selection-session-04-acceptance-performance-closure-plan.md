# Session 04 Plan: Acceptance Performance Closure

# real scope

Validate the combined app-wide background selection rollout from Sessions 01 through 03 and close the source doc with exact evidence. Run feasible direct, smoke, analyzer, and performance-adjacent checks; update durable coverage docs; and record any device-only acceptance that cannot be completed locally.

# closure bar

This session is closed when the final direct test batch passes, app-wide selected-background inventory is recorded, feasible Settings-to-background smoke coverage is run or an exact environment block is documented, analyzer status is recorded honestly, `Test-Flight-Improv/02-integration-test-coverage.md` reflects the durable coverage change, the source doc records completion evidence, and this breakdown has a final allowed verdict.

# source of truth

- `Test-Flight-Improv/82-app-wide-background-selection.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- Sessions 01 through 03 plan artifacts and landed code
- `Test-Flight-Improv/02-integration-test-coverage.md`
- `Test-Flight-Improv/test-gate-definitions.md`

# session classification

`acceptance-only`

# exact problem statement

The implementation now changes the selected background path across shared app surfaces. The remaining risk is not another feature change; it is proving the combined behavior, recording what was and was not executable in this environment, and leaving stable docs that distinguish closed work from follow-up-only device/performance evidence.

# files and repos to inspect next

- `integration_test/settings_background_choice_smoke_test.dart`
- `integration_test/feed_performance_test.dart`
- `Test-Flight-Improv/02-integration-test-coverage.md`
- `Test-Flight-Improv/82-app-wide-background-selection.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- direct test files touched by Sessions 01 through 03

# existing tests covering this area

- Shared `AmbientBackground` widget behavior and static inventory
- Background preference parsing/storage unit tests
- App shell background notifier unit tests
- Settings screen/wired live background and failed-save tests
- Feed wired background preference tests
- Conversation, First Time Experience, Identity Choice, and Posts representative widget tests

# regression/tests to add first

No new code tests are required in this acceptance-only session unless a closure check exposes a missed acceptance gap. Prefer running and documenting the existing direct and integration/performance checks.

# step-by-step implementation plan

1. Run the final direct test batch serially and record pass/fail evidence.
2. Run the feasible analyzer pass and classify existing warnings separately from implementation errors.
3. Attempt Settings background smoke coverage using the repo’s integration test entry point; record exact command and block if no device/runtime supports it.
4. Attempt Feed performance coverage if locally feasible; record exact command and block if device/runtime support is missing.
5. Update source doc `82` with completion/evidence notes.
6. Update `02-integration-test-coverage.md` with the app-wide background coverage inventory.
7. Update this breakdown ledger and add the final program verdict.

# risks and edge cases

- Device-backed integration/performance tests may not run in the current terminal environment.
- Full-project analyzer is known to include unrelated lint debt; closure should not hide that, but it should not reopen doc `82` if there are no implementation errors.
- Documentation must not overclaim simulator/performance evidence that was not run.

# exact tests and gates to run

Direct tests already assigned by implementation sessions:

```bash
flutter test test/features/identity/presentation/widgets/ambient_background_test.dart
flutter test test/features/settings/application/background_preference_use_cases_test.dart
flutter test test/features/posts/phase1/app_shell_controller_test.dart
flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart
flutter test test/features/settings/presentation/screens/settings_screen_test.dart
flutter test test/features/settings/presentation/screens/settings_wired_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "background preference"
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart
flutter test test/features/home/presentation/screens/first_time_experience_screen_test.dart
flutter test test/features/identity/presentation/screens/identity_choice_screen_test.dart
flutter test test/features/posts/phase1/posts_screen_test.dart
```

Acceptance attempts:

```bash
flutter analyze
flutter test integration_test/settings_background_choice_smoke_test.dart
flutter test integration_test/feed_performance_test.dart
```

Named gates are not required unless gate definitions are edited. The implementation touched startup/QR/share route constructors only to carry the background state; direct analyzer and widget coverage are the chosen local closure checks.

# known-failure interpretation

Direct test failures are blocking. Full `flutter analyze` may be nonzero because of existing lint/warning debt; classify whether it reports implementation errors. Device/integration/performance failures caused by missing local device/runtime are acceptable only with exact command and failure recorded.

# done criteria

- Final evidence is written to the source doc and coverage inventory.
- Breakdown session ledger marks Sessions 01 through 04 with closure evidence.
- Final verdict is one of `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `stale`.
- Any residual follow-up is explicit, bounded, and not needed for the implemented local behavior.

# scope guard

Do not make new product changes here unless a direct acceptance check reveals a correctness bug. Do not edit gate definitions unless a new integration/cross-feature test is added and must be classified.

# accepted differences / intentionally out of scope

If local device-backed integration or performance tests cannot run, record them as explicit follow-up rather than inventing replacement evidence. The direct widget/static inventory suite remains the local proof for app-wide selected-background participation.

# dependency impact

This is the final closure session for doc `82`; no downstream implementation sessions remain.

# planning review

The plan is sufficient for acceptance-only closure because implementation work is already landed and directly tested. It focuses on truthful evidence and durable documentation.

# structural blockers remaining

None for local acceptance. Device-backed smoke/performance may depend on external simulator availability.

# exact docs/files used as evidence

- `Test-Flight-Improv/82-app-wide-background-selection.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- `Test-Flight-Improv/02-integration-test-coverage.md`
- Direct test outputs from Sessions 01 through 03

# closure evidence

Outcome: `accepted_with_explicit_follow_up`.

Completed April 28, 2026. Direct suites, macOS Settings smoke, and macOS Feed performance passed. Source doc `82`, this breakdown, and `02-integration-test-coverage.md` record the exact evidence and remaining evidence-only follow-up.

Verified:

- `flutter test integration_test/settings_background_choice_smoke_test.dart -d macos`
- `flutter test integration_test/feed_performance_test.dart -d macos`

Analyzer:

- `flutter analyze` exits nonzero with existing repo-wide lint/warning debt: `1706 issues found`.
- Narrowed touched-file analyzer pass found no implementation errors, but exits nonzero on existing warnings/infos.

Explicit follow-up:

- Run device-backed mobile smoke/performance on one selected iOS or Android target for the Settings background journey.
- Add or run heavy Conversation-specific performance evidence with `Cosmic` selected if release confidence requires it.
