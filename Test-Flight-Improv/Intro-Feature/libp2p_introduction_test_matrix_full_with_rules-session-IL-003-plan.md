# Session IL-003 Plan: Friend picker filtering and reintroduction eligibility

## Real scope

- Close row `IL-003` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add or tighten only the row-owned proof for:
  recipient / self / blocked / archived contacts are not selectable, while
  prior same-pair introductions still allow reintroduction.
- Keep this session test-only unless the existing picker flow exposes a real
  product bug during execution.

## Closure bar

Session `IL-003` is good enough when the repo has direct automated evidence
that:

- the active recipient is excluded from picker choices,
- the current user/self contact is excluded,
- blocked contacts are excluded,
- archived contacts are excluded or otherwise absent from the active picker
  contract,
- a prior same-pair introduction does not make the friend permanently
  ineligible for reselection, and
- the source matrix plus breakdown can point to exact direct proof for that
  row.

## Source of truth

- Breakdown artifact:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- Source matrix:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Intro inventory:
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`

When docs and repo evidence disagree, repo evidence wins.

## Session classification

`implementation-ready`

## Exact files to inspect

- `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
- `lib/features/introduction/presentation/screens/friend_picker_screen.dart`
- `test/features/introduction/presentation/screens/friend_picker_test.dart`
- `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`

## Planned execution

1. Revalidate the current picker contract in the wired and pure screen tests.
2. Add the smallest missing regression(s) for any uncovered `IL-003` filters or
   reselection behavior.
3. Touch production code only if a new regression exposes a real mismatch in
   the live picker contract.
4. Run the direct picker suites and the named intro gate.
5. Refresh the matrix row and breakdown ledger with the exact landed evidence.

## Exact tests and gates to run

Direct suites:

```bash
flutter test --no-pub test/features/introduction/presentation/screens/friend_picker_test.dart
flutter test --no-pub test/features/introduction/presentation/screens/friend_picker_wired_test.dart
flutter test --no-pub test/features/introduction/regression/introduction_regression_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Scope guard

- Do not widen into send-progress UX, confirmation-screen coverage, Orbit
  surfaces, or notification behavior.
- Do not change intro business logic outside the picker contract unless a new
  regression proves the picker is currently wrong.
- Do not treat broad family-level coverage as sufficient; `IL-003` must end
  with exact row-owned evidence.

## Done criteria

- `IL-003` has direct picker proof covering the required filter/reselection
  rules.
- The direct picker suites are green.
- `./scripts/run_test_gates.sh intro` is green.
- The source matrix and breakdown name the exact evidence used to close the
  row.
