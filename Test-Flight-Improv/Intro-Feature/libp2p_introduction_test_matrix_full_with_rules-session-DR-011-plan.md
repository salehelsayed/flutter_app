# Session DR-011 Plan: Offline relay intro to first-chat transport proof

## Real scope

- Close row `DR-011` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add the missing repo-owned transport proof for offline relay intro delivery
  that later converges to mutual acceptance and a first working B↔C chat.
- Keep this session evidence-focused: add only the smallest intro E2E harness
  support needed to send and verify the first post-intro chat in the
  three-simulator flow.

## Closure bar

Session `DR-011` is good enough when the repo has direct automated evidence
that:

- A can send an intro while at least one target is offline long enough to
  require store-and-forward inbox delivery,
- the offline side later drains the intro, both sides accept, and the pair
  converges to `mutualAccepted`, and
- the first direct chat after that intro succeeds in both the host regression
  and the dedicated three-simulator scenario.

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
- `lib/core/debug/intro_e2e_runner.dart`
- `smoke_test_friends.sh`
- `lib/features/conversation/application/send_chat_message_use_case.dart`

## Planned execution

1. Add the smallest E2E runner support needed to send one post-intro chat and
   wait for its arrival on the peer.
2. Add a dedicated three-simulator scenario where C is offline during intro
   send, later drains the intro, B and C mutually accept, and B sends the
   first chat to C.
3. Run the direct host regression, the dedicated simulator scenario, and the
   intro gate.
4. Refresh the matrix, inventory, and breakdown only if the new evidence
   truthfully closes the row.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/integration/introduction_multi_node_test.dart \
  --plain-name 'offline relay intro delivery converges to mutual acceptance and first encrypted chat'
```

Required stronger evidence:

```bash
INTRO_E2E_SCENARIO=offline-chat ./smoke_test_friends.sh
./scripts/run_test_gates.sh intro
```

## Scope guard

- Do not widen into partition-heal acceptance recovery owned by `DR-010`.
- Do not widen into split-brain mutual acceptance repair owned by `DR-014`.
- Do not invent a broad conversation smoke framework; keep the harness support
  limited to the intro row's first-chat proof.
- Do not reopen already accepted intro rows unless the new evidence directly
  contradicts them.

## Done criteria

- `DR-011` has row-owned host and simulator proof for offline intro delivery,
  later mutual acceptance, and the first post-intro chat.
- The direct regression is green.
- `INTRO_E2E_SCENARIO=offline-chat ./smoke_test_friends.sh` is green.
- `./scripts/run_test_gates.sh intro` is green.
- The source matrix, inventory, and breakdown name the exact evidence used to
  close the row.
