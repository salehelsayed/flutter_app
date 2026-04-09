# Session IL-013 Plan: Expired intro can be reintroduced as a fresh pending flow

## Real scope

- Close row `IL-013` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add row-owned proof that an expired intro no longer behaves as pending and a
  later same-pair re-introduction starts a fresh valid journey.
- Keep the session test-only unless the new regressions expose a real product
  bug.

## Closure bar

Session `IL-013` is good enough when the repo has direct automated proof that:

- an expired same-pair intro can be replaced locally by a fresh pending intro,
- the same expiry-then-refresh path also converges through the smoke/integration
  seam, and
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
- Current code:
  `lib/features/introduction/application/send_introduction_use_case.dart`
- Current tests:
  `test/features/introduction/application/send_introduction_test.dart`
  and
  `test/features/introduction/integration/introduction_smoke_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The repo already proves expiry filtering and general same-pair refresh
  independently.
- The source row stays partial because no test pins the exact sequence where an
  intro becomes `expired` and then the same pair is reintroduced as a fresh
  valid pending flow.

## Files and repos to inspect next

- `test/features/introduction/application/send_introduction_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `lib/features/introduction/application/send_introduction_use_case.dart`

## Existing tests covering this area

- `send_introduction_test.dart` already proves generic same-pair refresh.
- `introduction_smoke_test.dart` already proves generic same-pair refresh and
  separate expiry behavior.
- No current regression combines expiry and fresh re-introduction in one row-
  owned proof.

## Regression/tests to add first

- Add an application regression for local resend after an expired intro.
- Add a smoke/integration regression for B/C after an intro expires and A
  reintroduces the same pair.

## Step-by-step implementation plan

1. Add the local expired-refresh regression in `send_introduction_test.dart`.
2. Add the smoke expired-refresh regression in
   `introduction_smoke_test.dart`.
3. Run the targeted suites.
4. Run `./scripts/run_test_gates.sh intro`.
5. If green, refresh matrix, inventory, and breakdown for `IL-013`.

## Risks and edge cases

- Make the expired state truthful by updating both `createdAt` and `status`
  before the re-introduction.
- Keep the session scoped to same-introducer same-pair refresh; do not widen
  into different-introducer or transport-repair rows.

## Exact tests and gates to run

Direct suites:

```bash
flutter test --no-pub \
  test/features/introduction/application/send_introduction_test.dart \
  test/features/introduction/integration/introduction_smoke_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- If the expired row is revived instead of replaced, that is a current-session
  lifecycle bug.
- If the old expired row remains alongside the new one, that is a current-
  session dedupe bug.

## Done criteria

- Expiry-then-refresh is pinned in both the local send seam and the
  smoke/integration seam.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into startup healing or stale-delivery rows already owned by
  other sessions.

## Accepted differences / intentionally out of scope

- This session does not add three-simulator proof.
- This session does not change expiry duration or dedupe policy.

## Dependency impact

- Later lifecycle and refresh rows can cite these tests as the explicit
  post-expiry re-introduction proof.
