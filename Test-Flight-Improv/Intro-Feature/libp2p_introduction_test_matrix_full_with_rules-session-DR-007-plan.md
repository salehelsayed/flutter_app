# Session DR-007 Plan: Stale queued terminal intro reopen protection

## Real scope

- Close row `DR-007` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add or tighten only the row-owned proof for:
  duplicate network deliveries and stale queued intro envelopes do not reopen
  a terminal intro.
- Keep this session test-only unless the new regression exposes a live
  mismatch in intro send/replay handling.

## Closure bar

Session `DR-007` is good enough when the repo has direct automated evidence
that:

- a duplicate `send` for the same `introductionId` does not reopen a terminal
  intro row,
- an older same-pair queued `send` does not replace a terminal intro with a
  new pending row, and
- the existing terminal intro remains terminal after the stale delivery path
  is exercised.

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
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/features/introduction/application/mutual_acceptance_test.dart`

## Planned execution

1. Revalidate the existing terminal-pass behavior that already proves
   `accept` after `passed` stays terminal.
2. Add the smallest row-owned `send` regressions proving duplicate and stale
   queued `send` envelopes do not reopen a terminal intro row.
3. Touch production code only if the new regression exposes a live reopen bug.
4. Run the directly touched intro suites and the named intro gate.
5. Refresh the matrix row and breakdown ledger with the exact landed evidence.

## Exact tests and gates to run

Direct suites:

```bash
flutter test --no-pub test/features/introduction/application/handle_incoming_introduction_test.dart
flutter test --no-pub test/features/introduction/application/mutual_acceptance_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Scope guard

- Do not widen into re-introduction repair owned by `DR-013`.
- Do not widen into sender-crash durability owned by `DR-009`.
- Do not widen into the broader terminal-state matrix owned by `SC-008`
  beyond the stale queued delivery seam needed to close `DR-007`.
- Do not refactor intro transport or retry orchestration unless the new
  regression proves a live reopen bug.

## Done criteria

- `DR-007` has direct proof that duplicate and stale queued `send` deliveries
  do not reopen a terminal intro row.
- The direct suites are green.
- `./scripts/run_test_gates.sh intro` is green.
- The source matrix and breakdown name the exact evidence used to close the
  row.
