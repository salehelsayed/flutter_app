# Session RM-009 Plan: Non-party caller guard for accept/pass

## Real scope

- Close row `RM-009` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Fix the current repo gap where `acceptIntroduction` and `passIntroduction`
  treat any caller who is not the recipient as the introduced party.
- Add the smallest direct regressions proving non-party callers cannot mutate
  intro state or send outbound responses.

## Closure bar

Session `RM-009` is good enough when the repo has direct automated evidence
that:

- a caller who is neither the recipient nor the introduced party cannot
  execute `acceptIntroduction`,
- a caller who is neither the recipient nor the introduced party cannot
  execute `passIntroduction`,
- neither use case mutates the stored intro row for a non-party caller, and
- neither use case emits response deliveries for a non-party caller.

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

- `lib/features/introduction/application/accept_introduction_use_case.dart`
- `lib/features/introduction/application/pass_introduction_use_case.dart`
- `test/features/introduction/application/accept_introduction_test.dart`
- `test/features/introduction/application/pass_introduction_test.dart`

## Planned execution

1. Add explicit recipient/introduced ownership checks to both response use
   cases.
2. Add the smallest direct no-mutation regressions for non-party callers.
3. Run the direct accept/pass suites and the named intro gate.
4. Refresh the matrix row, breakdown ledger, and test inventory note with the
   exact landed evidence.

## Exact tests and gates to run

Direct suites:

```bash
flutter test --no-pub test/features/introduction/application/accept_introduction_test.dart
flutter test --no-pub test/features/introduction/application/pass_introduction_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Scope guard

- Do not widen into inbound unknown-responder handling that is already owned by
  `RM-008`.
- Do not widen into duplicate-delivery or retry semantics owned by other rows.
- Do not refactor shared response delivery unless the non-party guard requires
  it.
- Do not treat checklist prose as closure; `RM-009` must end with landed code
  plus direct regressions.

## Done criteria

- `RM-009` has code-level non-party caller guards in both response use cases.
- The direct accept/pass suites are green.
- `./scripts/run_test_gates.sh intro` is green.
- The source matrix, breakdown, and inventory note the exact evidence used to
  close the row.
