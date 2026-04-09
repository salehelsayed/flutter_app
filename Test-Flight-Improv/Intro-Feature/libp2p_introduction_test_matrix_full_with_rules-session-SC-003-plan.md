# Session SC-003 Plan: Reject intro/contact ML-KEM key mismatches before mutation

## Real scope

- Close row `SC-003` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add a repo-owned reject/escalation path when an intro-carried stranger
  ML-KEM key disagrees with the current contact record for that same peer.
- Land direct regressions for both `acceptIntroduction(...)` and
  `passIntroduction(...)` so the mismatch does not silently proceed.

## Closure bar

Session `SC-003` is good enough when the repo has direct automated proof that:

- `acceptIntroduction(...)` rejects a stranger-key mismatch before mutating the
  intro or sending network traffic,
- `passIntroduction(...)` rejects the same mismatch before mutating the intro or
  sending network traffic, and
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
  `lib/features/introduction/application/accept_introduction_use_case.dart`
  and
  `lib/features/introduction/application/pass_introduction_use_case.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The current accept/pass use cases take the intro-carried stranger ML-KEM key
  first and only fall back to the contact record when the intro omits that key.
- If the current contact record for the same peer already exists with a
  different ML-KEM public key, the current code silently prefers the intro key
  and keeps going.
- That behavior violates the row contract because it can continue across
  conflicting trust material without surfacing a failure.

## Files and repos to inspect next

- `lib/features/introduction/application/accept_introduction_use_case.dart`
- `lib/features/introduction/application/pass_introduction_use_case.dart`
- `test/features/introduction/application/accept_introduction_test.dart`
- `test/features/introduction/application/pass_introduction_test.dart`

## Existing tests covering this area

- `accept_introduction_test.dart` already proves intro-carried stranger-key
  preference and contact-key fallback when the intro omits the key.
- `pass_introduction_test.dart` already proves the same fallback semantics for
  pass.
- No current regression covers the mismatch case itself.

## Regression/tests to add first

- Add an `acceptIntroduction(...)` regression where the intro carries one
  stranger ML-KEM key, the contact repo already has a different key for that
  same peer, and the use case rejects without status mutation or outbound
  delivery.
- Add the same regression for `passIntroduction(...)`.

## Step-by-step implementation plan

1. Add targeted failing regressions for accept/pass mismatch rejection.
2. Add a shared preflight mismatch guard before any local intro mutation or
   outbound delivery occurs.
3. Run the targeted accept/pass suites.
4. Run `./scripts/run_test_gates.sh intro`.
5. If green, refresh matrix, inventory, and breakdown for `SC-003`.

## Risks and edge cases

- The guard must run before local status mutation; otherwise the row would still
  drift locally even if outbound delivery later rejects.
- The mismatch rule should trigger only when both the intro-carried key and the
  current contact key are present and disagree. Missing-key fallback remains
  owned by existing tests and must keep working.

## Exact tests and gates to run

Direct suites:

```bash
flutter test --no-pub \
  test/features/introduction/application/accept_introduction_test.dart \
  test/features/introduction/application/pass_introduction_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- A mismatch regression that still mutates intro state or sends traffic is a
  current-session bug.
- If the safest implementation requires a wider trust-model change than this
  repo seam can support cleanly, record a real blocker instead of silently
  weakening the row.

## Done criteria

- Accept/pass reject intro/contact stranger-key mismatches before mutation.
- Direct tests prove no status mutation and no network delivery on mismatch.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into listener-level decryption mismatch handling owned by
  `SC-002`.
- Do not widen into contact-creation repair policies outside the accept/pass
  send path unless the direct mismatch fix proves insufficient.

## Accepted differences / intentionally out of scope

- This session rejects the mismatch instead of inventing an automatic key-repair
  protocol.
- This session does not add simulator or fake-network scenarios.

## Dependency impact

- Later rows can cite the mismatch guard as the repo-owned trust-edge defense
  for intro responses.
