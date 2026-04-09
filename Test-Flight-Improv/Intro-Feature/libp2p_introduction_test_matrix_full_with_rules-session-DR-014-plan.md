# Session DR-014 Plan: Split-brain mutual acceptance heals after reconnect

## Real scope

- Close row `DR-014` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add row-owned proof for the user-visible split-brain mutual-acceptance case
  where one side already reaches `mutualAccepted` and creates the contact while
  the opposite side is still stuck on `accepted + pending` until a later
  reconnect or restart.
- Keep this session evidence-only unless the reproduction proves the current
  product cannot heal without a code change.

## Closure bar

Session `DR-014` is good enough when the repo has direct automated evidence
that:

- one side can temporarily remain on the waiting state while the other side has
  already reached `mutualAccepted`,
- the lagging side later reconnects or restarts and drains the queued second
  `accept` update, and
- all devices converge back to one `mutualAccepted` intro truth without manual
  deletion or duplicate contacts.

## Source of truth

- Breakdown artifact:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- Source matrix:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Reliability audit:
  `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
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
- `lib/features/introduction/application/expire_old_introductions_use_case.dart`

## Planned execution

1. Add a host regression where B accepts, goes offline, C accepts into
   `mutualAccepted`, and B later reconnects and drains the queued second
   `accept`.
2. Add a dedicated three-simulator scenario that reproduces the same waiting vs
   connected split and later heals on reconnect.
3. Run the direct host regression, the dedicated simulator scenario, and the
   intro gate.
4. If the row cannot be truthfully closed without product changes, stop and
   record that blocker instead of forcing a misleading acceptance.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/integration/introduction_multi_node_test.dart \
  --plain-name 'split-brain mutual acceptance heals after reconnect'
```

Required stronger evidence:

```bash
INTRO_E2E_SCENARIO=split-brain ./smoke_test_friends.sh
./scripts/run_test_gates.sh intro
```

## Scope guard

- Do not widen into sender persistence owned by `DR-009`.
- Do not widen into partition-heal introducer recovery owned by `DR-010`.
- Do not widen into offline first-chat proof owned by `DR-011`.
- If the scenario exposes a real unhealed product gap, stop and record that
  blocker instead of inventing speculative repair logic.

## Done criteria

- `DR-014` has row-owned host and simulator proof for split-brain waiting vs
  connected state that later heals on reconnect.
- The direct regression is green.
- `INTRO_E2E_SCENARIO=split-brain ./smoke_test_friends.sh` is green.
- `./scripts/run_test_gates.sh intro` is green.
- Or a real blocker is persisted if the current product cannot heal this row
  truthfully.
