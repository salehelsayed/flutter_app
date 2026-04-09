# Session DR-010 Plan: Partition-heal intro convergence evidence

## Real scope

- Close row `DR-010` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add the missing repo-owned proof for partition healing after divergent intro
  delivery or divergent accepts across A, B, and C.
- Keep this session evidence-only: do not change intro product behavior unless
  the new proof exposes a live gap that prevents truthful closure.

## Closure bar

Session `DR-010` is good enough when the repo has direct automated evidence
that:

- B and C can both reach `mutualAccepted` while the introducer A is partitioned
  away,
- A later reconnects or resumes, drains the queued intro responses, and
  converges to the same final intro truth as B and C, and
- the row-owned proof exists both in repo-local host coverage and in a
  three-simulator E2E intro scenario.

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

## Planned execution

1. Add a targeted multi-node regression where A is partitioned away while B and
   C accept, then later resumes and converges.
2. Add a matching three-simulator intro scenario using the existing intro E2E
   step runner and stopped-node behavior.
3. Run the direct host regression, the dedicated simulator scenario, and the
   intro gate.
4. Refresh the matrix, inventory, and breakdown only if the new evidence
   truthfully closes the row.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/integration/introduction_multi_node_test.dart \
  --plain-name 'introducer heals after partitioned accept deliveries and converges with B and C'
```

Required stronger evidence:

```bash
INTRO_E2E_SCENARIO=partition ./smoke_test_friends.sh
./scripts/run_test_gates.sh intro
```

## Scope guard

- Do not widen into sender-local persistence owned by `DR-009`.
- Do not widen into offline relay first-chat proof owned by `DR-011`.
- Do not widen into the user-visible split-brain waiting bug owned by `DR-014`
  unless this exact partition proof exposes it directly.
- Do not claim closure from resend-only repair coverage; the row needs real
  partition-divergence proof.

## Done criteria

- `DR-010` has row-owned host and simulator proof for partition-heal
  convergence across A, B, and C.
- The direct regression is green.
- `INTRO_E2E_SCENARIO=partition ./smoke_test_friends.sh` is green.
- `./scripts/run_test_gates.sh intro` is green.
- The source matrix, inventory, and breakdown name the exact evidence used to
  close the row.
