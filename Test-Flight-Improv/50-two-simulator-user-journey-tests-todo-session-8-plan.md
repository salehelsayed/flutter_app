# Session 8 Plan: Introduction multi-node replay, offline relay, and first-chat proof

## Real scope

- Close the remaining Session 8 coverage asks for `9.1`, `9.4`, `I-1.1`,
  `I-1.4`, `I-3.1`, `I-3.2`, `I-5.2`, `I-5.4`, `I-5.5`, `I-9.1`, `I-9.2`,
  `I-9.3`, `I-9.4`, `I-9.5`, and `I-11.3` from
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`.
- Revalidate the older intro-core audit notes against the current
  `introduction_multi_node`, `introduction_smoke`, `mutual_acceptance`,
  `handle_incoming_introduction`, and `introduction_listener` suites before
  adding any new proofs.
- Treat the still-real missing surface as:
  - first encrypted `B <-> C` chat after mutual acceptance,
  - dual deferred accept replay that converges to contacts,
  - offline/relay intro delivery and offline accept-notification inbox replay,
  - same-pair different-introducer coverage, and
  - one real chain/circular intro proof.
- Keep the session test-first and test-only unless a failing proof exposes a
  real intro production bug.

## Closure bar

Session 8 is good enough when the repo has direct automated evidence that:

- a normal three-user introduction can reach mutual acceptance, create the
  contact/system-message state, and carry the first encrypted `B <-> C` chat,
- out-of-order remote accept responses can be deferred on both nodes, replay
  when the intro arrives, and still converge to contact creation,
- intro sends and accept notifications can fall back through the fake relay
  inbox when peers are unreachable and still converge after drain, and
- the remaining different-introducer, chain, and circular intro rows are
  either directly proven or honestly reclassified against the refreshed repo
  evidence.

The session should not widen into intro UI, Orbit notification routing, or
shared startup work. Session `9` owns those seams.

## Source of truth

- Active controller doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`
- Proposal/source doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- Coverage matrix and gap statements:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- Regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- Gate source of truth:
  `Test-Flight-Improv/test-gate-definitions.md`

When docs disagree with current repo evidence, repo evidence wins.

## Session classification

`implementation-ready`

## Exact problem statement

The current intro stack is stronger than the original audit recorded:

- `test/features/introduction/integration/introduction_multi_node_test.dart`
  already proves live recipient-first and introduced-first convergence,
  idempotent mutual acceptance, `alreadyConnected`, and correct
  `introducedBy` data.
- `test/features/introduction/integration/introduction_smoke_test.dart`
  already proves ordinary send/accept/pass happy-path behavior and grouped
  intro handling.
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
  and
  `test/features/introduction/application/introduction_listener_test.dart`
  already prove deferred-response storage and replay at the unit seam.

The audit is still right that the repo lacks one integrated proof joining
intro acceptance to the first encrypted chat path, and it still lacks a
multi-node proof that deferred/offline intro response replay converges all the
way to contacts. Same-pair different introducers and chain/circular
introducer arcs also remain thin or absent.

The goal is to add only those missing proofs, preferably by extending the
existing intro integration harness instead of inventing another test stack.

## Files and repos to inspect next

Primary direct tests:

- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/features/introduction/application/mutual_acceptance_test.dart`

Test harness likely to extend:

- `test/shared/fakes/intro_test_user.dart`
- `test/shared/fakes/fake_p2p_network.dart`
- `test/shared/fakes/fake_p2p_service_integration.dart`
- `test/shared/fakes/in_memory_message_repository.dart`

Adjacent conversation proof only for reuse, not duplication:

- `test/features/conversation/integration/two_user_message_exchange_test.dart`

Production files only if a new proof exposes a real bug:

- `lib/features/introduction/application/accept_introduction_use_case.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
- `lib/features/introduction/application/introduction_listener.dart`

## Existing tests covering this area

- `introduction_multi_node_test.dart` already covers live mutual acceptance,
  recipient-first and introduced-first ordering, and existing-contact handling.
- `introduction_smoke_test.dart` already covers multi-intro send, one accept
  plus one pass, mutual acceptance, and grouped intro flows.
- `handle_incoming_introduction_test.dart` already covers deferred accept/pass
  replay at the use-case seam.
- `introduction_listener_test.dart` already covers direct nonce confirmation,
  deferred remote accept storage, and replay after the matching `send`.
- `accept_introduction_test.dart` already covers stranger-key v2 encryption and
  v1 fallback on intro notifications.

## Regression/tests to add first

- Extend `intro_test_user.dart` only as needed so intro integration tests can
  observe the real conversation/message seam after mutual acceptance.
- Add one direct multi-node happy-path proof that reaches:
  intro delivery, mutual acceptance, intro system message insertion, first
  encrypted `B <-> C` chat, and persisted receive on the new contact thread.
- Add one direct multi-node deferred replay proof where each side sees the
  other side's accept before the intro and still converges when the intro
  eventually arrives.
- Add one direct offline/relay proof where intro delivery and/or accept
  notifications fall back to inbox and later drain cleanly.
- Add one direct different-introducer proof for the same pair.
- Add one direct chain/circular intro proof only if the refreshed evidence
  still leaves those rows open after the first three additions.

## Step-by-step implementation plan

1. Tighten Session 8 against current evidence from the intro core suites above.
2. Extend the existing intro fake-user harness only enough to inspect
   post-intro conversation state and send one real chat message.
3. Add the smallest direct first-chat proof to
   `introduction_multi_node_test.dart`.
4. Add the smallest dual-deferred replay proof to
   `introduction_multi_node_test.dart`.
5. Add the smallest offline relay/inbox intro proof to
   `introduction_multi_node_test.dart`.
6. Add same-pair different-introducer and chain/circular proofs only if those
   rows still remain open after the earlier steps.
7. Re-run the exact direct Session 8 intro suites.
8. Run `./scripts/run_test_gates.sh 1to1` because the first-chat proof touches
   shared conversation send/listener seams.
9. Run `./scripts/run_test_gates.sh baseline` only if execution ends up
   touching shared production bootstrap or app-root code.
10. Do not run `transport` unless a real production change escapes the intro
    test harness and touches startup/resume/inbox-drain behavior.

## Risks and edge cases

- The first-chat proof must show actual conversation persistence on the new
  intro-created contact, not only another intro notification send.
- The deferred-response proof must replay remote accepts from pending storage,
  not just call helper methods after the intro already exists.
- The offline proof should honestly model the current contract: direct send
  failure with inbox fallback and later drain, not an invented local offline
  send queue that the fake harness does not implement.
- Same-pair different-introducer and circular-chain rows should only be marked
  closed if the new tests actually prove duplicate-contact safety or the final
  connected state, not because they look adjacent.

## Exact tests and gates to run

Direct suites required for Session 8:

```bash
flutter test --no-pub test/features/introduction/integration/introduction_multi_node_test.dart
flutter test --no-pub test/features/introduction/integration/introduction_smoke_test.dart
flutter test --no-pub test/features/introduction/application/introduction_listener_test.dart
flutter test --no-pub test/features/introduction/application/handle_incoming_introduction_test.dart
flutter test --no-pub test/features/introduction/application/mutual_acceptance_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh 1to1
```

Conditional named gate:

```bash
./scripts/run_test_gates.sh baseline
```

Run `baseline` only if execution touches shared production app-root or startup
paths.

## Known-failure interpretation

- Treat unrelated dirty-worktree failures as historical noise unless one of the
  exact Session 8 direct suites or the required `1to1` gate fails.
- If a row closes by honest reclassification against current intro evidence,
  record that explicitly instead of adding redundant tests.
- If a required row cannot be honestly closed without a product change, stop
  and record that as the real blocker instead of inflating the test harness.

## Done criteria

- Session 8 has direct proof or honest reclassification for `9.1`, `9.4`,
  `I-1.1`, `I-1.4`, `I-3.1`, `I-3.2`, `I-5.2`, `I-5.4`, `I-5.5`, `I-9.1`,
  `I-9.2`, `I-9.3`, `I-9.4`, `I-9.5`, and `I-11.3`.
- The exact direct intro suites are green.
- `./scripts/run_test_gates.sh 1to1` is green.
- No intro UI, notification routing, or startup scope was pulled in
  unnecessarily.
- The breakdown ledger is updated with the accepted outcome and exact evidence.

## Scope guard

- No intro notification routing or badge redesign.
- No Orbit/Feed conversation-surface work beyond the intro-created message
  state needed for direct proof.
- No startup-router or push-architecture changes.
- No transport-gate or baseline-gate widening unless a real production bug
  forces it.

## Accepted differences / intentionally out of scope

- Session 8 does not need a new simulator/device harness if the fake-network
  intro integration seam can prove the behavior honestly.
- Session 8 does not own the authoritative matrix refresh; Session `10` still
  records the final accepted differences and stronger-evidence-only leftovers.

## Dependency impact

- Session `8` stays independent of earlier accepted sessions.
- Session `9` should plan against whatever intro conversation/message seam
  evidence lands here instead of duplicating it.
