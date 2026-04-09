# Session DR-012 Plan: Symmetric inbox fallback for pass notifications

## Real scope

- Close row `DR-012` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add the missing symmetric proof that `pass` notifications, not just
  `accept`, fall back to inbox while the introducer or other party is
  unreachable and later converge correctly after drain.
- Keep this session evidence-only: no intro product behavior changes unless the
  new proof exposes a real functional gap.

## Closure bar

Session `DR-012` is good enough when the repo has direct automated evidence
that:

- a responder can pass an intro while the introducer and the other party are
  unreachable,
- those pass notifications are later drained from inbox storage by the offline
  recipients, and
- all affected rows converge to `passed` without duplicate contacts or
  contradictory final states.

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

`evidence-gated`

## Exact files to inspect

- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `smoke_test_friends.sh`
- `lib/core/debug/intro_e2e_runner.dart`
- `lib/features/introduction/application/pass_introduction_use_case.dart`

## Planned execution

1. Add a symmetric host regression for pass-notification inbox fallback.
2. Add a dedicated three-simulator scenario where the responder passes while A
   and the stranger are offline, then both later drain the pass notification.
3. Run the direct host regression, the dedicated simulator scenario, and the
   intro gate.
4. Refresh the matrix, inventory, and breakdown only if the new evidence
   truthfully closes the row.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/integration/introduction_multi_node_test.dart \
  --plain-name 'pass notifications fall back to inbox while peers are unreachable and converge after drain'
```

Required stronger evidence:

```bash
INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh
./scripts/run_test_gates.sh intro
```

## Scope guard

- Do not widen into offline first-chat proof owned by `DR-011`.
- Do not widen into split-brain recovery owned by `DR-014`.
- Do not reopen accept-fallback coverage unless the new pass regression
  directly contradicts it.
- Do not introduce new retry machinery or delivery semantics unless the new
  proof exposes a real bug.

## Done criteria

- `DR-012` has row-owned host and simulator proof for symmetric pass fallback
  to inbox and later convergence after drain.
- The direct regression is green.
- `INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh` is green.
- `./scripts/run_test_gates.sh intro` is green.
- The source matrix, inventory, and breakdown name the exact evidence used to
  close the row.
