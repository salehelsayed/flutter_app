# Session SC-008 Plan: Preserve terminal intro truth across stale send delivery

## Real scope

- Close row `SC-008` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add row-owned regression proof that stale `send` deliveries do not regress
  terminal intro rows back to pending.
- Keep the session test-only unless the new proof exposes a real behavior bug.

## Closure bar

Session `SC-008` is good enough when the repo has direct automated proof that:

- a stale `send` cannot replace a `passed` intro with a new pending row,
- a stale `send` cannot replace an `expired` intro with a new pending row,
- a stale `send` cannot replace an `alreadyConnected` intro with a new pending
  row, and
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
  `test/features/introduction/application/handle_incoming_introduction_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The repo already has scattered terminal-state coverage and one stale `send`
  regression for `passed`.
- The source row requires a row-owned matrix that proves the same no-regression
  contract for `passed`, `expired`, and `alreadyConnected`.
- Without those direct tests, the matrix row remains only partially pinned even
  if current behavior happens to be correct.

## Files and repos to inspect next

- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`

## Existing tests covering this area

- `handle_incoming_introduction_test.dart` already proves the `passed` stale
  send guard.
- Other files cover expiry and already-connected behavior in adjacent seams,
  but not the row-owned stale-delivery matrix itself.

## Regression/tests to add first

- Add a stale-`send` regression that preserves `expired`.
- Add a stale-`send` regression that preserves `alreadyConnected`.

## Step-by-step implementation plan

1. Add the missing stale-delivery regressions in
   `handle_incoming_introduction_test.dart`.
2. Run the targeted handle-incoming suite.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `SC-008`.

## Risks and edge cases

- Keep the assertions focused on row truth: existing terminal row survives,
  stale row is not stored, and status does not regress.
- Do not widen into response replay, notification, or startup-healing seams
  owned by other rows.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/application/handle_incoming_introduction_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- If a stale `send` replaces any terminal row with pending state, that is a
  current-session product bug.
- If the new regressions pass and the gate stays green, the row can close as
  covered.

## Done criteria

- Stale `send` regressions cover `passed`, `expired`, and `alreadyConnected`.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into `SC-004`, `DR-007`, or startup reconciliation rows unless
  the direct stale-send matrix reveals a real gap in current behavior.

## Accepted differences / intentionally out of scope

- This session does not add new production behavior unless the stale-send
  regressions prove one is necessary.
- This session does not add simulator or multi-node transport proof.

## Dependency impact

- Later security and UX rows can cite this row-owned matrix as the terminal
  stale-send preservation proof for intro visibility and badge semantics.
