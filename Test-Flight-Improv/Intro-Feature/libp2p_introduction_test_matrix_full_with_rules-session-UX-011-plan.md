# Session UX-011 Plan: Pin the Orbit pending-intro banner variants

## Real scope

- Close row `UX-011` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add row-owned OrbitScreen widget proof for the intro-review banner across
  zero, singular, and plural pending-intro states.
- Keep the session test-only.

## Closure bar

Session `UX-011` is good enough when the repo has direct automated proof that:

- the Orbit intro banner is hidden when there are no pending review items,
- the banner shows singular copy for one pending intro,
- the banner shows plural copy for multiple pending intros, and
- the intro gate stays green.

## Source of truth

- Breakdown artifact:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- Source matrix:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Intro inventory:
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- Current tests:
  `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- OrbitScreen already has direct widget proof for intro review grouping and the
  `Intros` filter count.
- The remaining open gap is the top-of-screen intro banner shown outside the
  `Intros` tab.
- No dedicated widget test currently pins that banner’s zero/singular/plural
  copy variants.

## Files and repos to inspect next

- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`

## Regression/tests to add first

- Add one no-banner regression for zero pending review items.
- Add one singular-banner regression for exactly one pending intro.
- Add one plural-banner regression for multiple pending intros.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Done criteria

- Orbit intro banner visibility and count-driven copy are directly covered.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully, including the
  final program verdict if this is the last unresolved row.
