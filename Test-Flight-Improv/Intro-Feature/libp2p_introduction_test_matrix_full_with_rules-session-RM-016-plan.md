# Session RM-016 Plan: Heal stale pending rows to mutualAccepted, passed, and expired

## Real scope

- Close row `RM-016` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Extend `expireOldIntroductions(...)` coverage from the current narrow
  mutual-accept repair proof to the broader passed/expired healing matrix the
  row requires.
- Keep the session test-only unless the new regressions expose a real startup
  reconciliation bug.

## Closure bar

Session `RM-016` is good enough when the repo has direct automated proof that:

- stale `pending` rows heal to `mutualAccepted` and rerun the missing side
  effects,
- stale `pending` rows heal to `passed` without creating a contact, and
- stale `pending` rows heal to `expired` without creating a contact.

## Source of truth

- Breakdown artifact:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- Source matrix:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Intro inventory:
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- Current code:
  `lib/features/introduction/application/expire_old_introductions_use_case.dart`
- Current tests:
  `test/features/introduction/application/expire_old_introductions_use_case_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The repo already proves one stale mutual-accept repair and the
  already-connected no-op guard.
- The row remains partial because there is no direct passed/expired repair
  matrix and no direct proof that the mutual-accept repair reruns the missing
  system-message side effect.

## Files and repos to inspect next

- `lib/features/introduction/application/expire_old_introductions_use_case.dart`
- `test/features/introduction/application/expire_old_introductions_use_case_test.dart`

## Existing tests covering this area

- `expire_old_introductions_use_case_test.dart` already proves mutual-accept
  contact recreation.
- No current regression proves passed/expired healing in this seam.

## Regression/tests to add first

- Tighten the existing mutual-accept repair test to assert the system-message
  side effect.
- Add a passed-healing regression.
- Add an expired-healing regression.

## Step-by-step implementation plan

1. Extend `expire_old_introductions_use_case_test.dart` with the missing
   healing matrix.
2. Run the targeted expire-old-introductions suite.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `RM-016`.

## Risks and edge cases

- Keep the assertions scoped to startup reconciliation and side effects.
- Do not widen into listener stale-delivery rows or unknown-inbox-sender
  recovery.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/application/expire_old_introductions_use_case_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- If passed or expired rows stay `pending`, that is a current startup repair
  bug.
- If passed or expired repair creates a contact, that is a current side-effect
  bug.

## Done criteria

- The startup healing matrix covers mutualAccepted, passed, and expired.
- The mutual-accept repair also proves the missing system-message side effect.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into multi-node restart proof or transport recovery rows.

## Accepted differences / intentionally out of scope

- This session does not add simulator proof.
- This session does not change the reconciliation algorithm unless the tests
  expose a real bug.

## Dependency impact

- Later startup and recovery rows can cite this test matrix as the row-owned
  expire-old-intros proof.
