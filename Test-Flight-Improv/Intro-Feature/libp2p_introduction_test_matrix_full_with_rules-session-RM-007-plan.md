# Session RM-007 Plan: Duplicate accept/pass idempotency

## Real scope

- Close row `RM-007` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add or tighten only the row-owned proof for:
  duplicate accept/pass deliveries remain idempotent and do not create
  duplicate intro rows or contact side effects.
- Keep this session test-only unless the new regression exposes a real
  duplicate-processing bug.

## Closure bar

Session `RM-007` is good enough when the repo has direct automated evidence
that:

- duplicate accept delivery does not create duplicate contacts or state drift,
- duplicate pass delivery leaves the intro terminal as `passed`,
- duplicate pass delivery does not create contacts, and
- duplicate pass delivery does not duplicate the intro row itself.

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

- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/shared/fakes/intro_test_user.dart`

## Planned execution

1. Revalidate the existing duplicate-accept regression.
2. Add the smallest missing duplicate-pass regression in the same row-owned
   regression suite.
3. Touch production code only if the new regression exposes a live mismatch.
4. Run the direct regression suite and the named intro gate.
5. Refresh the matrix row and breakdown ledger with the exact landed evidence.

## Exact tests and gates to run

Direct suites:

```bash
flutter test --no-pub test/features/introduction/regression/introduction_regression_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Scope guard

- Do not widen into non-party caller validation owned by `RM-009`.
- Do not widen into stale queued terminal-state reopening owned by `DR-007`.
- Do not refactor response handling unless the new regression proves a live bug.
- Do not treat broad family-level coverage as sufficient; `RM-007` must end
  with exact row-owned evidence.

## Done criteria

- `RM-007` has direct proof for duplicate accept and duplicate pass
  idempotency.
- The direct regression suite is green.
- `./scripts/run_test_gates.sh intro` is green.
- The source matrix and breakdown name the exact evidence used to close the
  row.
