# GON-015 Plan: Recurring Gate Sufficiency And Final Reconciliation

## real scope

- Add a recurring fixture-backed group real-network command instead of relying on informal Nightly / Release Pool classification.
- Keep fixture execution separate from local closure: this session can prove the command fails clearly without configured relays, not that a relay lab passed.
- Reconcile the source doc, gate definitions, closure references, breakdown ledger, and final verdict.

## closure bar

- A script command exists for the group real-network nightly gate.
- The command requires an explicit device target and forces strict multi-relay fixture mode.
- Missing fixture evidence fails clearly rather than becoming a skipped pass.
- `completeness-check` passes.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-015`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-21 and final acceptance.

## session classification

`closure-only`

## exact problem statement

The repo had fixture-backed real-network group tests classified as Nightly / Release Pool, but no script-level recurring gate command made the fixture requirement explicit. TC-21 needs at least one real-network group scenario in a recurring command that fails clearly when prerequisites are unavailable.

## files and repos to inspect next

- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`
- `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`

## existing tests covering this area

- `integration_test/multi_relay_failover_test.dart` runs 1:1 transport and group recovery suites when at least two relay addresses are provided.
- GON-013 added `MKNOON_REQUIRE_MULTI_RELAY=true` so fixture absence fails clearly.

## regression/tests to add first

- Add `./scripts/run_test_gates.sh group-real-network-nightly`.
- Classify the previously unmatched Settings background smoke so completeness check reports the whole repo inventory.

## step-by-step implementation plan

1. Add the script command that requires `FLUTTER_DEVICE_ID` and passes strict relay fixture defines.
2. Update gate definitions with the recurring command and any completeness-only classification.
3. Verify script syntax.
4. Run `completeness-check`.
5. Run the group real-network nightly command locally with no relay fixture and confirm it fails with the intended missing-fixture message.
6. Persist final source-doc and breakdown verdicts.

## risks and edge cases

- Local missing-fixture failure is not a successful relay run.
- TC-21 can close the gate-wiring requirement while simulator rows still require device-lab execution.

## exact tests and gates to run

- `bash -n scripts/run_test_gates.sh`
- `./scripts/run_test_gates.sh completeness-check`
- Expected local fixture check: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh group-real-network-nightly`

## known-failure interpretation

- The local `group-real-network-nightly` command should fail without `MKNOON_RELAY_ADDRESSES`; a pass without relays would be a closure bug.
- In CI/device lab, the same command should pass only with a real `FLUTTER_DEVICE_ID` and at least two configured relay addresses.

## done criteria

- TC-21 is covered for recurring command wiring and strict fixture failure.
- The final program verdict is persisted as accepted with explicit device-lab follow-up.

## scope guard

- Do not mark the full simulator matrix closed without configured device-lab runs.

## accepted differences / intentionally out of scope

- The standard `all` gate remains host/frozen-gate scope and does not run the heavy real-network nightly command.

## dependency impact

- Future release work can invoke `group-real-network-nightly` directly as the recurring fixture-backed gate.
