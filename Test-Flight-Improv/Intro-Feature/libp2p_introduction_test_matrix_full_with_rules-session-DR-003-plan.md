# Session DR-003 Plan: Prove local/direct race converges without duplicate receive-side effects

## Real scope

- Close row `DR-003` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add repo-owned isolated proof that the same intro can race through both the
  local and direct paths while still converging to one logical receive result.
- Keep the session evidence-focused unless the race regression exposes a real
  product bug.

## Closure bar

Session `DR-003` is good enough when the repo has direct automated proof that:

- both the local and direct send arms are viable for the same intro target,
- the receiver still materializes only one intro row and one system-message
  side effect for that intro, and
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
- Current delivery code:
  `lib/features/introduction/application/introduction_outbound_delivery.dart`
- Current integration harness:
  `test/shared/fakes/fake_p2p_service_integration.dart`
  and
  `test/features/introduction/integration/introduction_smoke_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The repo already has duplicate-send receive-side dedupe proof, but it does
  not isolate the outbound local/direct race tier itself.
- The fake integration P2P service can make both local and direct arms viable
  for the same target, so this row can close with an isolated race regression
  instead of remaining a doc-only gap.

## Files and repos to inspect next

- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/shared/fakes/fake_p2p_service_integration.dart`
- `lib/features/introduction/application/introduction_outbound_delivery.dart`

## Existing tests covering this area

- `introduction_listener_test.dart` already proves duplicate send replay keeps
  one row, one system message, and one notification.
- No current test proves that a single send actually raced through both local
  and direct outbound arms.

## Regression/tests to add first

- Add a smoke/integration regression where A can reach B via both local and
  direct paths with a timing skew, and B still ends with one intro row and one
  system message.

## Step-by-step implementation plan

1. Add the forced local/direct race regression.
2. Run the targeted smoke suite.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `DR-003`.

## Risks and edge cases

- The test must prove both arms actually fired; otherwise it is not closing the
  right row.
- Keep the closure truthful by citing existing notification dedupe proof rather
  than inventing a new notification harness if the smoke test does not inject
  notifications.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/integration/introduction_smoke_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- If both arms fire and B gets duplicate rows or duplicate system messages,
  that is a current convergence bug.
- If only one arm fires in the test, the regression is not strong enough to
  close the row.

## Done criteria

- The local/direct race tier has direct repo-owned proof.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into relay-probe or app-resume delivery rows.

## Accepted differences / intentionally out of scope

- This session does not add a new notification-service harness; it may reuse
  existing duplicate-send notification evidence instead.
- This session does not add three-simulator proof.

## Dependency impact

- Later delivery-tier rows can cite this regression as the local/direct race
  convergence proof.
