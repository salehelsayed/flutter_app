# Session DR-008 Plan: Retry multiple intro outbox rows cleanly on resume

## Real scope

- Close row `DR-008` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add repo-owned proof that intro retry logic handles multiple retryable rows
  and cleans already-delivered inbox rows.
- Keep the session evidence-focused unless the retry matrix exposes a real
  product bug.

## Closure bar

Session `DR-008` is good enough when the repo has direct automated proof that:

- multiple failed and stalled intro outbox rows are retried in one pass,
- previously delivered+inbox rows are cleaned instead of retried forever, and
- the final delivered count matches the actual cleanup/retry outcomes.

## Source of truth

- Breakdown artifact:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- Source matrix:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Intro inventory:
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- Current retry code:
  `lib/features/introduction/application/introduction_outbound_delivery.dart`
- Current tests:
  `test/features/introduction/application/introduction_outbound_delivery_test.dart`
  and
  `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The repo already proves single-row intro retry and that `handleAppResumed`
  calls the intro retry callback in the right step.
- The row remains open because no test proves multiple failed/stalled rows plus
  delivered+inbox cleanup in the real retry function.

## Files and repos to inspect next

- `lib/features/introduction/application/introduction_outbound_delivery.dart`
- `test/features/introduction/application/introduction_outbound_delivery_test.dart`
- `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`

## Existing tests covering this area

- `introduction_outbound_delivery_test.dart` already proves single-row inbox
  retry and delivered+inbox cleanup separately.
- No current regression runs the multi-row matrix in one pass.

## Regression/tests to add first

- Add a retry matrix regression with failed, sent/stalled, and delivered+inbox
  rows in the same repo state.

## Step-by-step implementation plan

1. Add the multi-row retry regression.
2. Run the targeted outbound-delivery suite.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `DR-008`.

## Risks and edge cases

- The test must distinguish actual inbox store calls from cleanup-only deletion.
- Keep the session scoped to intro retry semantics, not broader app-resume
  orchestration.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/application/introduction_outbound_delivery_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- If delivered+inbox rows are retried instead of cleaned, that is a current
  cleanup bug.
- If multiple failed/stalled rows are not all processed, that is a current
  retry fan-out bug.

## Done criteria

- The intro outbox retry matrix covers multiple rows and cleanup semantics.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into message/media retry rows or transport probe rows.

## Accepted differences / intentionally out of scope

- This session does not add a new `handleAppResumed` end-to-end integration
  harness.
- This session does not change retry policy unless the regression exposes a
  real bug.

## Dependency impact

- Later resume/retry docs can cite this regression as the intro multi-row retry
  cleanup proof.
