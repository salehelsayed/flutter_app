# GON-011 Plan: Two-Simulator Journey Harness Startup Reliability

## real scope

- Remove the false startup failure observed when Alice waits for Bob identity while Bob is still building.
- Apply the same identity-wait fix to the group Alice harness.
- Record the full Discussion and Announcement UI journey as residual simulator/device-lab work.

## closure bar

- Alice-side two-simulator harnesses do not fail their own test before the orchestrator's startup timeout can cover Bob build/startup latency.
- The attempted paired run and remaining simulator gap are documented truthfully.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-011`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-27 and TC-28.

## session classification

`implementation-ready`

## exact problem statement

The paired simulator run can fail before any Discussion or Announcement journey evidence is collected because Alice waits only 120 seconds for Bob's identity file, while Bob may still be building and starting. The orchestrator was widened to 15 minutes, but the child harness still had the narrower timeout.

## files and repos to inspect next

- `integration_test/routing_smoke_alice_harness.dart`
- `integration_test/group_smoke_alice_harness.dart`
- `integration_test/scripts/run_routing_smoke_e2e.dart`

## existing tests covering this area

- `run_routing_smoke_e2e.dart` launches Alice first, waits for `alice_ready`, then launches Bob.
- The local paired run on `2026-04-29` reached Alice ready, launched Bob, then failed because Alice timed out waiting for `bob_identity.json` before Bob completed startup.

## regression/tests to add first

- No new host unit is needed for this timeout-only harness fix; use static analysis and the observed paired-run failure as the regression evidence.

## step-by-step implementation plan

1. Extend Alice's wait for `bob_identity.json` in `routing_smoke_alice_harness.dart`.
2. Extend the matching group Alice wait for `bob_identity.json` in `group_smoke_alice_harness.dart`.
3. Run static analysis on the touched harness files.
4. Update source docs and the session ledger with the attempted device run result and remaining journey residual.

## risks and edge cases

- This does not prove the full TC-27 or TC-28 UI journey.
- A later paired run may expose real receiver, unread, restart, or Announcement permission failures after it gets past startup.

## exact tests and gates to run

- `dart analyze integration_test/routing_smoke_alice_harness.dart integration_test/group_smoke_alice_harness.dart`
- Attempted paired run: `dart run integration_test/scripts/run_routing_smoke_e2e.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`

## known-failure interpretation

- Timeout on `bob_identity.json` before Bob is ready is a harness coordination failure, not a product Discussion/Announcement receiver-visible result.

## done criteria

- The Alice-side identity waits are aligned with the orchestrator startup window.
- Docs state that TC-27/TC-28 are still simulator residuals until a full paired run completes with receiver-visible assertions.

## scope guard

- Do not claim Discussion or Announcement journey closure from a run that did not reach scenario execution.

## accepted differences / intentionally out of scope

- Announcement admin media/voice, reader reaction, blocked compose, and no stranded optimistic bubble remain explicit simulator-matrix work.

## dependency impact

- Later paired simulator runs should no longer fail before Bob identity is written during slow first builds.
