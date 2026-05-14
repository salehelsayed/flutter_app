# GO-012 Deterministic Fake Flake Budget Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 22:38 CEST - Local gap-closure pass reached GO-012 after GO-008 and GO-009 closure. Files inspected: source matrix GO-012 row, session-breakdown GO-012 row, existing session ledgers, `test/shared/fakes/fake_group_pubsub_network.dart`, selected group fake-network integration tests, and current test inventory. Decision: reclassify as active `needs_code_and_tests` work because the source row was `Open`, no adjacent GO-012 plan existed, `FakeGroupPubSubNetwork` used an unseeded `Random()`, delivery delays depended on wall-clock `Future.delayed`, and there was no exact repeat flake-budget runner.

## Original Source Row

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GO-012 | Flake budget for reliability tests is zero for deterministic fakes | Fake network tests. | 1. Run core fake tests many times. 2. Track flakes. | No nondeterministic misses; fake clock controls waits/backoff. | P0 | Open | Recommended | Required | Required | Required | N/A | Avoid hiding intermittent bug as test flake. |

## Reconciliation Verdict

GO-012 was repo-owned because the row requires deterministic fake-network behavior and repeat proof, and the missing pieces were in this repo. The fake network owned random delivery drops and delay scheduling, so an `Open` row could not be closed by external fixture status or by prior adjacent reliability tests alone.

## Device/Relay Proof Profile

- Profile: host fake-network deterministic flake-budget proof.
- Source matrix marks 3-Party E2E as N/A.
- No live device, simulator, relay, OS notification, or multi-relay proof is required for GO-012 closure.
- Supporting named gate: `./scripts/run_test_gates.sh groups`.

## Scope

Own exactly GO-012:

- Make fake-network drop behavior deterministic by default and resettable.
- Make fake-network delay scheduling injectable so tests can control waits without wall-clock sleeps.
- Add exact row-owned tests for seeded repeatability and reset repeatability.
- Add a reusable repeat runner for selected deterministic fake-network reliability selectors.
- Prove the repeat runner completes with zero failures.

## Out Of Scope

- Goroutine leak detection, which remains GO-010.
- Live relay/device proof, because GO-012 3-Party E2E is N/A.
- Broadly rewriting existing GE/GR reliability tests beyond adding a row-owned repeat runner.
- Treating a runner selector bug as product reliability evidence; selector correctness is closed in this row before acceptance.

## Owner Files

- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/fake_group_pubsub_network_test.dart`
- `scripts/run_group_fake_flake_budget.sh`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-012-plan.md`

## Required Validation

```sh
dart format --set-exit-if-changed test/shared/fakes/fake_group_pubsub_network.dart test/shared/fakes/fake_group_pubsub_network_test.dart
dart analyze test/shared/fakes/fake_group_pubsub_network.dart test/shared/fakes/fake_group_pubsub_network_test.dart
flutter test --no-pub test/shared/fakes/fake_group_pubsub_network_test.dart
GO012_REPEAT_COUNT=5 ./scripts/run_group_fake_flake_budget.sh
./scripts/run_test_gates.sh groups
git diff --check -- test/shared/fakes/fake_group_pubsub_network.dart test/shared/fakes/fake_group_pubsub_network_test.dart scripts/run_group_fake_flake_budget.sh Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-012-plan.md
```

## Done Criteria

- Source row GO-012 is `Covered` with concrete code/test/gate evidence.
- Fake-network random drops are seedable and reset to a repeatable sequence.
- Fake-network delivery delays can be controlled by tests without wall-clock waiting.
- Exact GO-012 tests pass.
- Repeat fake flake-budget runner passes five iterations with zero failures.
- No `accepted_with_explicit_follow_up` is used for unresolved GO-012 gaps.

## Execution Evidence

- Runtime and harness hardening:
  - `test/shared/fakes/fake_group_pubsub_network.dart` now accepts `randomSeed` and injectable `delay`, uses a seeded `Random`, and resets the seed in `resetCounters()`.
  - `publish`, `publishReaction`, and held-delivery release paths use the injected delay scheduler instead of directly sleeping with `Future.delayed`.
  - `scripts/run_group_fake_flake_budget.sh` runs the exact fake-network GO-012 tests plus selected GE-017/GE-019/GE-020/restart and resume-recovery fake-network reliability selectors in a repeat loop.
- Exact tests:
  - `test/shared/fakes/fake_group_pubsub_network_test.dart::GO-012 seeded drops and scheduled delays are repeatable` proves two fresh seeded networks produce the same delivered message sequence and the same scheduled delay list without wall-clock waiting.
  - `test/shared/fakes/fake_group_pubsub_network_test.dart::GO-012 resetCounters restores seeded drop sequence` proves a single network resets to the same seeded drop sequence after `resetCounters()`.
- Validation evidence:
  - First Dart format run formatted the fake-network files; the final `dart format --set-exit-if-changed ...` rerun passed with no changes.
  - `dart analyze test/shared/fakes/fake_group_pubsub_network.dart test/shared/fakes/fake_group_pubsub_network_test.dart` passed with no issues.
  - `flutter test --no-pub test/shared/fakes/fake_group_pubsub_network_test.dart` passed (`+2 All tests passed`).
  - The first repeat-runner attempt exposed a repo-owned script selector issue: `--plain-name 'GE-017|GE-019|GE-020|message is received after app restart with rejoin'` matched no tests and exited 79. The script was corrected to use `--name` for regex selectors.
  - Final `GO012_REPEAT_COUNT=5 ./scripts/run_group_fake_flake_budget.sh` passed with `GO-012 fake flake budget passed: 5 iterations, 0 failures`.
  - Final `./scripts/run_test_gates.sh groups` passed (`+159 All tests passed`).
  - `git diff --check` on GO-012 owner code, runner, source matrix, breakdown, test inventory, and this plan passed.

## Final Verdict

GO-012 is accepted/closed. The source matrix row is `Covered` with deterministic fake-network seed/reset and delay-scheduler code, exact row-owned tests, five-iteration zero-flake runner evidence, named groups gate evidence, and no residual GO-012 gap. Residual-only: none. Continue from GL-010, the next unresolved session in ordered ledger order.
