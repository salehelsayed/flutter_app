# Session SC-002 Plan: Tampered ciphertext or wrong secret key is rejected with no state mutation

## Real scope

- Close row `SC-002` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Keep the existing wrong-key rejection proof and add the missing direct proof
  that a tampered v2 intro envelope is rejected without creating rows,
  contacts, messages, badges, or notifications.
- Do not widen into ML-KEM contact-record mismatch handling owned by
  `SC-003`.

## Closure bar

Session `SC-002` is good enough when the repo has direct automated proof that:

- a wrong-key v2 intro is rejected with no intro row, contact, or notification,
- a tampered v2 ciphertext is also rejected with no intro row, contact, system
  message, or notification, and
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
  `lib/features/introduction/domain/models/introduction_payload.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The listener already rejects wrong-key v2 intros and the inventory cites that
  proof directly.
- The matrix still marks `SC-002` partial because no direct regression pins the
  "tampered ciphertext" branch with an explicit no-mutation contract.
- User-visible behavior that must improve: a corrupted v2 intro envelope must
  fail closed without creating any intro side effects.
- Behavior that must stay unchanged: valid v1/v2 intro delivery, duplicate
  replay hardening from `SC-001`, and the existing wrong-key rejection path.

## Files and repos to inspect next

- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/domain/models/introduction_payload.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/application/introduction_payload_test.dart`
- `test/features/introduction/application/introduction_payload_extended_test.dart`

## Existing tests covering this area

- `introduction_listener_test.dart` already has
  `v2 key mismatch rejects intro, stores nothing, and logs failure`.
- `introduction_payload_test.dart` and
  `introduction_payload_extended_test.dart` already cover v2 envelope parsing
  guards for non-introduction, v1, and missing encrypted-block shapes.
- No current listener regression directly drives a tampered encrypted payload
  through `processIncomingMessage(...)` and proves that nothing mutates.

## Regression/tests to add first

- Add one listener regression that builds a v2 encrypted intro envelope whose
  ciphertext is intentionally corrupted so the decrypted plaintext is invalid.
- Assert `IntroductionMessageProcessOutcome.state == rejected` and that intro
  repo, contact repo, message repo, and notification sinks remain empty.

## Step-by-step implementation plan

1. Add the missing tampered-ciphertext listener regression next to the existing
   wrong-key test.
2. Run the listener test file to verify both wrong-key and tampered paths stay
   green.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `SC-002`. If the
   tampered path exposes a real mutation bug, stop and fix only that seam.

## Risks and edge cases

- The passthrough test bridge does not perform real cryptography, so the test
  should tamper the encrypted envelope in a way that still exercises the
  listener’s failure path truthfully in this repo, such as invalid decrypted
  JSON after decryption.
- Do not over-claim transport proof; this session only closes the row with
  direct listener/application evidence plus the named intro gate.

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

- The wrong-key regression is already green in the current repo.
- Treat any new tampered-payload failure as a current session bug unless it is
  a clearly unrelated environment issue.

## Done criteria

- The repo has a direct tampered-v2 listener regression.
- Wrong-key and tampered-v2 rejections both prove no intro side effects.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into ML-KEM contact-key mismatch handling owned by `SC-003`.
- Do not widen into replay semantics already owned by `SC-001`.
- Do not add simulator or fake-network scenarios in this session.

## Accepted differences / intentionally out of scope

- This session reuses the existing wrong-key listener regression instead of
  duplicating that proof elsewhere.
- This session does not add transport-level tamper scenarios; the row closes on
  direct listener proof plus the named intro gate.

## Dependency impact

- `SC-003` can cite the wrong-key/tamper rejection proofs as adjacent security
  coverage while still owning the contact-record mismatch seam.
