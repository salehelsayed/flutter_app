# Session DR-004 Plan: Isolate relay-probe fallback after direct failure

## Real scope

- Close row `DR-004` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add repo-owned isolated proof that relay-probe fallback succeeds after the
  direct path fails.
- Keep the session evidence-focused unless the isolated regression exposes a
  real delivery bug.

## Closure bar

Session `DR-004` is good enough when the repo has direct automated proof that:

- the direct discovery/dial path fails,
- `probeRelay(...)` is attempted and succeeds,
- the later relay send succeeds and clears the staged outbox row, and
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
- Current isolated test seam:
  `test/features/introduction/application/introduction_outbound_delivery_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The repo already proves inbox fallback and some multi-node relay outcomes.
- The source row remains open because no isolated test pins the relay-probe
  branch inside `deliverIntroductionPayloadReliably(...)`.

## Files and repos to inspect next

- `lib/features/introduction/application/introduction_outbound_delivery.dart`
- `test/features/introduction/application/introduction_outbound_delivery_test.dart`
- `test/core/services/fake_p2p_service.dart`

## Existing tests covering this area

- `introduction_outbound_delivery_test.dart` already covers acked send, sent
  retry state, inbox fallback, and resume retry.
- No current test proves the relay-probe branch itself.

## Regression/tests to add first

- Add an isolated relay-probe fallback regression using a fake P2P service that
  fails the direct dial and returns `RelayProbeResult.connected`.

## Step-by-step implementation plan

1. Add the relay-probe regression to
   `introduction_outbound_delivery_test.dart`.
2. Run the targeted outbound-delivery suite.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `DR-004`.

## Risks and edge cases

- The test must prove the probe happened; a successful send alone is not enough.
- Keep the session scoped to relay-probe fallback, not broader transport fault
  injection.

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

- If probeRelay is never called after direct failure, that is a current
  fallback bug.
- If relay probe succeeds but the staged outbox row remains, that is a current
  delivery-state bug.

## Done criteria

- The relay-probe path has isolated repo-owned proof.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into app-resume or multi-row retry rows.

## Accepted differences / intentionally out of scope

- This session does not add multi-device relay proof.
- This session does not change production fallback policy unless the regression
  exposes a real bug.

## Dependency impact

- Later delivery-tier rows can cite this regression as the isolated relay-probe
  fallback proof.
