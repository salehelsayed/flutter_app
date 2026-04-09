# Session RM-006 Plan: Accept/pass stranger delivery key priority

## Real scope

- Close row `RM-006` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add or tighten only the row-owned proof for:
  accept/pass sends reach both the introducer and the stranger, prefer
  intro-carried stranger ML-KEM keys when present, and fall back to contact
  ML-KEM keys when the intro record does not carry one.
- Keep this session test-only unless the new regression exposes a real bug in
  the current response delivery path.

## Closure bar

Session `RM-006` is good enough when the repo has direct automated evidence
that:

- accept sends reach both the introducer and the stranger,
- pass sends reach both the introducer and the stranger,
- the stranger path encrypts with intro-carried ML-KEM keys when present, and
- the stranger path falls back to contact ML-KEM keys when the intro record
  lacks them.

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
- `lib/features/introduction/application/introduction_outbound_delivery.dart`
- `test/features/introduction/application/accept_introduction_test.dart`
- `test/features/introduction/application/pass_introduction_test.dart`

## Planned execution

1. Revalidate the existing both-recipient and intro-carried-key response tests.
2. Add the smallest missing regressions for stranger contact-key fallback in
   both accept and pass flows.
3. Touch production code only if the new regressions expose a real mismatch.
4. Run the direct response suites and the named intro gate.
5. Refresh the matrix row and breakdown ledger with the exact landed evidence.

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

- Do not widen into non-party caller validation owned by `RM-009`.
- Do not widen into inbox fallback symmetry or retry semantics owned by `DR-*`
  rows.
- Do not refactor the shared response flow unless the new regressions prove a
  live mismatch.
- Do not treat broad family-level coverage as sufficient; `RM-006` must end
  with exact row-owned evidence.

## Done criteria

- `RM-006` has direct proof for both-recipient delivery plus intro-key and
  contact-fallback stranger encryption behavior.
- The direct response suites are green.
- `./scripts/run_test_gates.sh intro` is green.
- The source matrix and breakdown name the exact evidence used to close the
  row.
