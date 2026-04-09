# Session RM-012 Plan: Introducer mutual-accept convergence without duplicate contacts

## Real scope

- Close row `RM-012` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add row-owned proof that the introducer's local intro row converges to
  `mutualAccepted` after both remote accepts.
- Keep this session test-only unless the new regression exposes a real defect in
  introducer-side convergence or contact handling.

## Closure bar

Session `RM-012` is good enough when the repo has direct automated evidence
that:

- the introducer's persisted intro row reaches `mutualAccepted` after both
  parties accept,
- the introducer's row shows both remote statuses as `accepted`, and
- the introducer does not create extra B/C contacts while processing the final
  convergence.

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

- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/shared/fakes/intro_test_user.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`

## Planned execution

1. Revalidate the existing introducer-local intro proof and live mutual-accept
   flow in the multi-node suite.
2. Add the smallest missing regression that pins introducer convergence to
   `mutualAccepted` and asserts A keeps exactly one contact for B and one for C.
3. Touch production code only if the new regression exposes a real mismatch.
4. Run the multi-node suite and the named intro gate.
5. Refresh the matrix row, breakdown ledger, and test inventory with the exact
   landed evidence.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub test/features/introduction/integration/introduction_multi_node_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Scope guard

- Do not widen into second-accept contact creation semantics already covered by
  `RM-011`.
- Do not widen into split-brain restart/reconnect recovery owned by `DR-014`.
- Do not refactor introducer-side contact handling unless the new regression
  proves a real bug.
- Do not treat broad multi-node coverage as sufficient; `RM-012` must end with
  a direct row-owned introducer assertion.

## Done criteria

- `RM-012` has a direct introducer-side mutual-acceptance regression.
- The direct multi-node suite is green.
- `./scripts/run_test_gates.sh intro` is green.
- The source matrix, breakdown, and inventory name the exact evidence used to
  close the row.
