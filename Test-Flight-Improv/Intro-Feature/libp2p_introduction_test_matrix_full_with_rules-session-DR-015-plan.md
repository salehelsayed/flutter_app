# Session DR-015 Plan: Multiple simultaneous intros stay isolated

## Real scope

- Close row `DR-015` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add row-owned proof for overlapping intro chains that are active at the same
  time and share at least one participant or introducer.
- Keep this session evidence-only unless the new regression proves a real
  product bug that requires a narrow fix.

## Closure bar

Session `DR-015` is good enough when the repo has direct automated proof that:

- two distinct `introductionId` chains can coexist without status bleed,
- one chain can pass while another reaches `mutualAccepted` in the same run,
- only the intended contact edge is created for the chain that reaches mutual
  acceptance, and
- the intro gate stays green after the new proof lands.

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

## Exact problem statement

- The current repo already proves logical isolation for multiple intro IDs at
  the application layer, and it proves sequential multi-hop behavior in the
  multi-node integration suite.
- What is still missing is a direct host-side live regression where overlapping
  intro chains share real listener/delivery timing and still mutate only their
  own row.
- User-visible behavior that must improve: concurrent intro activity must not
  cause one intro chain to adopt the status or contact side effects of another.
- Behavior that must stay unchanged: existing pass semantics, mutual-acceptance
  contact creation, same-pair repair, and different-introducer
  `alreadyConnected` handling.

## Files and repos to inspect next

- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/shared/fakes/intro_test_user.dart`
- `test/shared/fakes/fake_p2p_network.dart`
- `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`

## Existing tests covering this area

- `test/features/introduction/application/mutual_acceptance_test.dart`
  already proves `i1` and `i2` stay logically isolated at the application
  layer.
- `test/features/introduction/integration/introduction_multi_node_test.dart`
  already covers chain/circular intro flows, but those chains are sequential
  rather than overlapping pending chains.
- `./scripts/run_test_gates.sh intro` is the named gate that already includes
  `introduction_multi_node_test.dart`.

## Regression/tests to add first

- Add one host-side multi-node regression in
  `test/features/introduction/integration/introduction_multi_node_test.dart`
  where two intro IDs are alive at once, share a participant, and diverge:
  one chain ends `passed` while the other ends `mutualAccepted`.
- This directly proves row isolation because the same run can detect any
  cross-chain status mutation or wrong contact creation immediately.

## Step-by-step implementation plan

1. Add the new multi-node regression with four users and two overlapping intro
   chains.
2. Reuse existing helpers where possible; add only minimal helper code if the
   current test harness cannot express the overlap cleanly.
3. Run the direct regression first.
4. Run `./scripts/run_test_gates.sh intro`.
5. If both are green, refresh the matrix, inventory, and breakdown for
   `DR-015`. If the regression exposes a real cross-chain bleed, stop and
   record that blocker instead of widening scope.

## Risks and edge cases

- A shared participant may receive two intros at once and must mutate the
  correct row only.
- Contact creation on one chain must not imply completion or contact creation
  on the other chain.
- Accept/pass ordering across two intro IDs can hide mistaken cross-row writes
  if the assertions only inspect final overall status.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/integration/introduction_multi_node_test.dart \
  --plain-name 'simultaneous intro chains stay isolated when one passes and the other reaches mutual acceptance'
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- No intro-gate failure is currently persisted as acceptable after the green
  DR-014 rerun on 2026-04-09.
- Treat any failure in the new direct regression or the intro gate as a
  current session blocker unless it is a clearly unrelated environment failure.

## Done criteria

- `DR-015` has a direct host-side regression proving concurrent intro-chain
  isolation.
- The direct regression is green.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.
- Or a real blocker is persisted if concurrent chains do bleed into each other.

## Scope guard

- Do not widen into replay-hardening owned by `SC-001`.
- Do not widen into same-pair reintroduction repair owned by `DR-013`.
- Do not add a new three-simulator scenario unless the host regression proves
  insufficient to close the row truthfully.
- Do not change product behavior unless the new regression exposes a real bug.

## Accepted differences / intentionally out of scope

- A dedicated three-simulator proof remains optional for `DR-015` because the
  matrix marks fake-network and 3-party E2E evidence as recommended, not
  required.
- This session does not revisit notification-content coverage or Orbit/Feed
  follow-up wiring.

## Dependency impact

- Later replay, dedupe, and multi-chain rows can cite this host regression once
  it lands.
- If this session finds that host-side overlap proof is not enough, later
  evidence-gated rows may need stronger transport-level scenarios as follow-up.
