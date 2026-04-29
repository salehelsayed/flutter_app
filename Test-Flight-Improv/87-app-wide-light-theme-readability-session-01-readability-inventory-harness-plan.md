# Session 01 Plan: App-wide readability inventory and contrast evidence harness

## real scope

This session creates the doc `87` evidence foundation only. It adds a reusable test helper for contrast ratios, records the current app-wide surface classification inventory in the source doc, and updates the session breakdown ledger when the helper and inventory are verified.

This session does not migrate Orbit, Feed, Conversation, Groups, QR, Share, Posts, or overlay production colors. Those remain owned by later doc-scoped sessions.

## closure bar

Session 01 is complete when later tests can import one helper for `4.5:1` text contrast and `3:1` component contrast checks, doc `87` has an explicit static classification ledger for every required screen and major transient/card group, and the direct helper/theme test passes.

## source of truth

- `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
- `Test-Flight-Improv/87-app-wide-light-theme-readability-session-breakdown.md`
- `Test-Flight-Improv/84-background-readable-theme-extension-session-breakdown.md`
- `Test-Flight-Improv/86-daylight-lagoon-background-option-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- current code and tests under `lib/` and `test/`

If prose conflicts with current code/tests, current code/tests win. If gate prose conflicts with `scripts/run_test_gates.sh`, the script wins.

## session classification

`implementation-ready`

## exact problem statement

Doc `87` requires app-wide readability evidence, but current contrast proof is local to individual tests and the screen inventory is still written as requirement prose rather than a maintenance ledger. Later surface sessions need shared contrast utilities and a stable doc-owned classification baseline before broad UI edits begin.

## files and repos to inspect next

- `test/core/theme/background_readable_colors_test.dart`
- `lib/core/theme/background_readable_colors.dart`
- `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
- `Test-Flight-Improv/87-app-wide-light-theme-readability-session-breakdown.md`

## existing tests covering this area

- `test/core/theme/background_readable_colors_test.dart` already proves dark and representative-light readable roles meet the core contrast threshold, but it carries private helper functions that later screen tests cannot reuse.
- `test/features/identity/presentation/widgets/ambient_background_test.dart` already inventories selected shared-background screens, but it does not classify every doc `87` surface or transient group.

## regression/tests to add first

Add a reusable helper under `test/shared/helpers/` and update `background_readable_colors_test.dart` to consume it. This keeps the helper covered by the existing readable-color contrast test.

## step-by-step implementation plan

1. Add `test/shared/helpers/readability_test_helpers.dart` with `contrastRatio`, `expectTextContrast`, and `expectComponentContrast`.
2. Update `test/core/theme/background_readable_colors_test.dart` to import the helper and remove duplicated local contrast functions.
3. Append a doc `87` Session 01 classification ledger that maps each required screen/transient group to current classification and owning future session.
4. Run `dart format` on changed Dart tests/helpers.
5. Run `flutter test test/core/theme/background_readable_colors_test.dart`.
6. Update this breakdown ledger for Session 01 with accepted status and verification notes.

## risks and edge cases

- The helper must account for alpha blending so semi-transparent foreground colors are tested against their effective background.
- The inventory must not overclaim closure for surfaces that still lack actual content evidence.
- This session must not widen into app-wide color migrations.

## exact tests and gates to run

- `flutter test test/core/theme/background_readable_colors_test.dart`

No named gate is required because this session changes only test helpers and docs plus a theme unit test import.

## known-failure interpretation

Any failure in `test/core/theme/background_readable_colors_test.dart` after this session is in scope because the helper is directly consumed there. Broader unrelated dirty worktree changes are not evidence for or against this session unless they affect this test.

## done criteria

- Reusable contrast helper exists under `test/shared/helpers/`.
- Core readable-color contrast test imports the helper and passes.
- Doc `87` contains a static classification ledger for all source-doc screens and major transient/card groups.
- Breakdown Session 01 ledger row is updated to `accepted`.

## scope guard

Do not migrate production UI colors in this session. Do not add new app behavior, settings, backgrounds, routes, or gates. Do not mark any later surface family closed based only on static inventory.

## accepted differences / intentionally out of scope

Camera/media/pre-preference surfaces may remain classified as intentional dark/camera/media or out-of-selected-background scope when later sessions prove their own readable chrome. Session 01 only records the classification baseline.

## dependency impact

Sessions `02` through `08` depend on this helper and inventory. If this helper changes later, those sessions should refresh their contrast expectations against the final helper API before adding assertions.

