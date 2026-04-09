# Session UX-002 Plan: Pin exact IntroRow mutual-accept CTA copy

## Real scope

- Close row `UX-002` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Re-verify the row against current widget coverage and avoid reopening states
  that are already directly pinned.
- Add the missing row-owned widget proof for the mutual-accept `Message` CTA.

## Closure bar

Session `UX-002` is good enough when the repo has direct automated proof that:

- pending rows still show `Accept` and `Pass`,
- one-sided accept still shows the waiting copy,
- passed rows still show `Passed`,
- already-connected rows still show `Already connected` with no action CTA, and
- mutual-accepted rows render the exact `Message` CTA and invoke its callback.

## Source of truth

- Breakdown artifact:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- Source matrix:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Intro inventory:
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- Current widget code:
  `lib/features/introduction/presentation/widgets/intro_row.dart`
- Current widget tests:
  `test/features/introduction/presentation/widgets/intro_row_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The breakdown note saying `Already connected` copy is unpinned is stale;
  `intro_row_test.dart` already asserts that label directly.
- The remaining row-owned gap is the exact mutual-accept CTA copy and action:
  the live widget uses `Message`, but no widget regression pins that label or
  the callback path.

## Files and repos to inspect next

- `lib/features/introduction/presentation/widgets/intro_row.dart`
- `test/features/introduction/presentation/widgets/intro_row_test.dart`

## Existing tests covering this area

- `intro_row_test.dart` already covers pending, waiting, passed, and
  already-connected states.
- No current IntroRow widget test asserts the `Message` CTA label or tap path.

## Regression/tests to add first

- Add one `IntroRow` widget regression for a `mutualAccepted` intro that
  renders the exact `Message` CTA and calls `onSendMessage`.

## Step-by-step implementation plan

1. Add the missing mutual-accept CTA widget regression.
2. Run the targeted IntroRow suite.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `UX-002`.

## Risks and edge cases

- Keep the session narrow to IntroRow itself; do not widen into IntrosTab or
  Orbit wiring unless the widget proof fails because of a real product bug.
- Preserve the existing already-covered states and update docs to reflect that
  the prior breakdown note was stale.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/presentation/widgets/intro_row_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- If the widget renders a different CTA than `Message`, that is a current row
  copy bug.
- If the CTA renders but does not invoke the callback, that is a current row
  action bug.

## Done criteria

- The exact `Message` CTA copy and action are pinned in `intro_row_test.dart`.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into feed card CTA copy or notification copy; those belong to
  other seams.

## Accepted differences / intentionally out of scope

- This session does not change IntroRow copy if the live widget already matches
  the source row.
- This session does not add extra presentation snapshots or simulator proof.

## Dependency impact

- Later UI rows can rely on this regression as the source-of-truth mutual-accept
  CTA proof for intro rows.
