# Session DR-002 Plan: Resume-triggered inbox-only intro retry

## Real scope

- Close row `DR-002` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Keep this session test-only by adding the missing row-owned proof that app
  resume triggers the intro outbox retrier and that the retrier replays
  retryable intro rows through inbox-only semantics.
- Avoid widening into the broader multi-row cleanup and mixed-status resume
  matrix owned by `DR-008`.

## Closure bar

Session `DR-002` is good enough when the repo has direct automated evidence
that:

- an unacked live intro send leaves a retryable outbox row,
- app resume invokes the pending-introduction retrier, and
- the resume-triggered retrier replays the row through `storeInInbox` without
  re-running the live direct-send path.

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

- `lib/features/introduction/application/introduction_outbound_delivery.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `test/features/introduction/application/introduction_outbound_delivery_test.dart`

## Planned execution

1. Revalidate the existing unacked-send and retryPendingIntroductionDeliveries
   coverage in the outbound-delivery suite.
2. Add the smallest missing regression that seeds a sent intro outbox row,
   runs `handleAppResumed`, and proves resume uses the inbox-only retry path.
3. Touch production code only if the new regression exposes a live mismatch.
4. Run the outbound-delivery suite and the named intro gate.
5. Refresh the matrix row, breakdown ledger, and inventory with the exact
   landed evidence.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub test/features/introduction/application/introduction_outbound_delivery_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Scope guard

- Do not widen into local/direct race or relay-probe isolation owned by
  `DR-003` and `DR-004`.
- Do not widen into multi-row resume cleanup owned by `DR-008`.
- Do not refactor the introduction outbox transport stack unless the new test
  proves a real bug.
- Do not rely on generic resume ordering tests alone; `DR-002` must end with a
  row-owned intro retry assertion.

## Done criteria

- `DR-002` has direct proof for unacked retryable state plus resume-triggered
  inbox-only replay.
- The outbound-delivery suite is green.
- `./scripts/run_test_gates.sh intro` is green.
- The source matrix, breakdown, and inventory name the exact evidence used to
  close the row.
