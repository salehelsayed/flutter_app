# Session DR-009 Plan: Sender-local intro durability before outbound delivery

## Real scope

- Close row `DR-009` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Eliminate the sender-side crash window where a remote party can receive the
  intro before the introducer has durably written the replacement local intro
  row.
- Add the smallest row-owned regression proving the sender-local row survives a
  crash after one remote delivery has already succeeded.

## Closure bar

Session `DR-009` is good enough when the repo has direct automated evidence
that:

- `sendIntroductions(...)` persists the new local intro row before outbound
  delivery staging begins,
- a simulated crash after one remote delivery but before the remaining outbound
  work completes still leaves the sender with exactly one truthful local intro
  row for that pair, and
- the stronger intro and transport evidence stays green after the ordering fix.

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

`implementation-ready`

## Exact files to inspect

- `lib/features/introduction/application/send_introduction_use_case.dart`
- `test/features/introduction/application/send_introduction_test.dart`
- `test/features/introduction/application/introduction_outbound_delivery_test.dart`

## Planned execution

1. Move sender-local intro persistence ahead of outbound delivery staging in
   the intro send chain.
2. Add a crash-window regression that forces a failure after the first remote
   delivery has already succeeded and verify the sender-local row still exists.
3. Run the directly touched intro suites.
4. Run the row-owned stronger evidence: `INTRO_E2E_SCENARIO=repair
   ./smoke_test_friends.sh`, `./scripts/run_test_gates.sh intro`, and
   `./scripts/run_test_gates.sh transport`.
5. Refresh the matrix row, intro inventory, audit note, and breakdown ledger
   with the exact landed evidence.

## Exact tests and gates to run

Direct suites:

```bash
flutter test --no-pub test/features/introduction/application/send_introduction_test.dart
flutter test --no-pub test/features/introduction/application/introduction_outbound_delivery_test.dart
```

Required stronger evidence:

```bash
INTRO_E2E_SCENARIO=repair ./smoke_test_friends.sh
./scripts/run_test_gates.sh intro
FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport
```

## Scope guard

- Do not widen into split-brain acceptance recovery owned by `DR-014`.
- Do not widen into partial fan-out repair owned by `DR-005`.
- Do not invent a new sender-side outbox-to-intro reconstruction layer unless
  the local-first persistence change proves insufficient.
- Do not reopen already accepted rows unless this session's evidence directly
  contradicts them.

## Done criteria

- `DR-009` is closed with direct proof that sender-local intro persistence is
  durable before outbound delivery work.
- The direct suites are green.
- The repair scenario, intro gate, and transport gate are green.
- The source matrix, intro inventory, audit, and breakdown name the exact
  evidence used to close the row.
