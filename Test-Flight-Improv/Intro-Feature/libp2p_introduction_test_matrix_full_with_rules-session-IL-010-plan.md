# Session IL-010 Plan: Already-connected intros stay visible and non-actionable

## Real scope

- Close row `IL-010` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add or tighten only the row-owned proof for:
  already-connected intros stay visible in the intro UI, expose no accept/pass
  actions, and do not inflate the pending badge.
- Keep this session test-only unless the current widget contract is proven
  wrong by the new regression.

## Closure bar

Session `IL-010` is good enough when the repo has direct automated evidence
that:

- an already-connected intro remains visible to the user,
- the surfaced row is non-actionable in UI terms,
- already-connected rows do not inflate pending badge counts, and
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

- `lib/features/introduction/presentation/widgets/intro_row.dart`
- `test/features/introduction/presentation/widgets/intro_row_test.dart`
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`

## Planned execution

1. Revalidate the existing already-connected load and pending-count contract.
2. Add the smallest missing widget regression for the visible non-actionable
   `Already connected` UI state.
3. Touch production code only if the widget regression exposes a real mismatch.
4. Run the direct row tests and the named intro gate.
5. Refresh the matrix row and breakdown ledger with the exact landed evidence.

## Exact tests and gates to run

Direct suites:

```bash
flutter test --no-pub test/features/introduction/presentation/widgets/intro_row_test.dart
flutter test --no-pub test/features/introduction/application/handle_incoming_introduction_test.dart
flutter test --no-pub test/features/introduction/integration/introduction_multi_node_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Scope guard

- Do not widen into mutual-accept `Message` CTA work owned by `UX-002`.
- Do not widen into Orbit sliver/grouping coverage unless the current row
  proves incorrect there.
- Do not change intro business logic outside the already-connected display
  contract unless the new regression proves a live mismatch.
- Do not treat broad family-level coverage as sufficient; `IL-010` must end
  with exact row-owned evidence.

## Done criteria

- `IL-010` has direct proof for already-connected visibility, non-actionability,
  and no pending-badge inflation.
- The direct row suites are green.
- `./scripts/run_test_gates.sh intro` is green.
- The source matrix and breakdown name the exact evidence used to close the
  row.
