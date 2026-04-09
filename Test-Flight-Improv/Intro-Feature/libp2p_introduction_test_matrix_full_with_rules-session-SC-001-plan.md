# Session SC-001 Plan: Replay of the same intro never duplicates side effects

## Real scope

- Close row `SC-001` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Fix and prove replay idempotency for duplicate intro delivery at the
  application/listener layer without widening into unrelated crypto, transport,
  or UI feature work.
- Reuse existing fake-network replay coverage where it already proves row/contact
  idempotency; add only the missing direct side-effect proof.

## Closure bar

Session `SC-001` is good enough when the repo has direct automated proof that:

- duplicate `send` replay does not duplicate rows, system messages, or local
  notifications,
- duplicate `accept` replay after a successful mutual acceptance does not
  duplicate contacts, system messages, or local notifications, and
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
  `lib/features/introduction/application/introduction_listener.dart`
  and
  `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- Existing tests already cover duplicate `send` row dedupe and one fake-network
- replay path that avoids duplicate contacts.
- Current listener behavior still shows a fresh "New Connection" notification on
  replayed `accept` messages that keep the intro at `mutualAccepted`, even when
  contact creation is already idempotent.
- User-visible behavior that must improve: replayed intro traffic must stay
  side-effect free across rows, contacts, system messages, and notifications.
- Behavior that must stay unchanged: valid first-time `send`, `accept`, `pass`,
  deferred replay, and mutual-acceptance contact creation.

## Files and repos to inspect next

- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`

## Existing tests covering this area

- `handle_incoming_introduction_test.dart` already covers duplicate `send` by
  `introductionId` and stale/terminal duplicate `send` behavior.
- `introduction_listener_test.dart` already covers deferred replay and mutual
  acceptance notifications, but not duplicate-notification suppression on replay.
- `introduction_multi_node_test.dart` already covers the late-delivery replay
  path with one row/contact edge under the fake network.

## Regression/tests to add first

- Add listener regressions for duplicate `send` replay and duplicate `accept`
  replay after mutual acceptance.
- The duplicate `accept` regression should fail against current code unless the
  listener suppresses replay-side notifications correctly.

## Step-by-step implementation plan

1. Add the missing listener replay regressions.
2. Run the direct listener test file or targeted tests to confirm the failing
   seam.
3. Make the smallest listener/use-case fix that suppresses duplicate replay side
   effects without breaking the first valid delivery.
4. Run the targeted replay tests.
5. Run `./scripts/run_test_gates.sh intro`.
6. If green, refresh matrix, inventory, and breakdown for `SC-001`. If replay
   idempotency requires broader transport or envelope changes, stop and record a
   blocker instead.

## Risks and edge cases

- A replayed `accept` can leave row/contact state unchanged while still causing
  duplicate notification side effects if the listener only checks final status.
- A fix that suppresses all duplicate `accept` handling could accidentally break
  deferred-response replay for the first late `send`.
- Duplicate `send` and duplicate `accept` need separate proof because they pass
  through different branches.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/application/introduction_listener_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- No intro-gate failure is currently persisted as acceptable after the green
  DR-015 rerun on 2026-04-09.
- Treat any replay-regression failure as a current session bug unless it is a
  clearly unrelated environment issue.

## Done criteria

- The repo has direct listener replay proofs for duplicate `send` and duplicate
  `accept`.
- Replay no longer duplicates contacts, system messages, or notifications.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into ciphertext tamper handling owned by `SC-002`.
- Do not widen into broader transport dedupe or envelope normalization owned by
  later security/replay rows unless the direct replay fix proves insufficient.
- Do not add new simulator scenarios in this session.

## Accepted differences / intentionally out of scope

- Existing fake-network late-delivery replay coverage is reused as row/contact
  evidence instead of duplicating it with another multi-node scenario.
- This session does not change UI copy, Orbit/Feed follow-up wiring, or push
  notification content.

## Dependency impact

- Later replay and stale-delivery rows can cite the new listener regressions.
- If this session cannot suppress duplicate replay side effects locally, later
  replay-hardening work likely needs a broader handler or envelope contract
  change.
