# GON-010 Plan: Real-Network Group Harness Pass Criteria

## real scope

- Tighten the existing two-simulator group smoke orchestrator so weak receiver evidence cannot pass G2/G4/G5/G7/G8.
- Add host-side criteria tests for the orchestrator logic.
- Record real-network new-member, three-party media, and full Group + Announcement simulator matrix items as device-lab residuals when they cannot be run locally.

## closure bar

- G2 requires 5/5 Bob receiver-visible messages.
- G4 requires Bob's recovered inbox message to have a non-negative `e2eMs`.
- G5 rejects pending or missing receiver entries instead of relying on timeline length.
- G7 requires Bob to receive both pre-rotation and post-rotation messages.
- G8 requires Bob receiver-visible receipt, not only Alice publish success.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-010`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-17, TC-18, and TC-20.

## session classification

`implementation-ready`

## exact problem statement

Report 85 explicitly calls out that the existing G2/G4/G5/G7/G8 two-simulator group smoke rows can pass with partial, pending, or sender-only evidence. Before those rows can count toward real-network sufficiency, the orchestrator must fail when Bob's receiver-visible proof is absent.

## files and repos to inspect next

- `integration_test/scripts/run_routing_smoke_e2e.dart`
- `integration_test/group_smoke_alice_harness.dart`
- `integration_test/group_smoke_bob_harness.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- The paired simulator harnesses produce JSON signal files for G1 through G8.
- The existing orchestrator consumes those signals but has permissive pass criteria for several rows.

## regression/tests to add first

- Add a host-side criteria unit test for G2/G4/G5/G7/G8 pass/fail cases.

## step-by-step implementation plan

1. Extract group smoke pass criteria to an importable Dart helper.
2. Change `run_routing_smoke_e2e.dart` to use strict criteria for G2/G4/G5/G7/G8.
3. Add tests proving partial/pending/sender-only fixtures fail and complete receiver-visible fixtures pass.
4. Run the new criteria test and `dart analyze` on the orchestrator/helper.
5. Update source docs and the session breakdown with the local closure and device-lab residual.

## risks and edge cases

- This does not create or run a new paired-simulator scenario for mid-conversation new-member join or three-party media fan-out.
- Tightened pass criteria may cause existing simulator runs to fail until the underlying receiver behavior is reliable.

## exact tests and gates to run

- `flutter test test/integration/routing_smoke_group_criteria_test.dart`
- `dart analyze integration_test/scripts/run_routing_smoke_e2e.dart integration_test/scripts/routing_smoke_group_criteria.dart`
- `./scripts/run_test_gates.sh completeness-check`

## known-failure interpretation

- Criteria test failure means the simulator orchestrator can still report a false pass.
- Analyze failure means the script/helper extraction broke the runnable orchestrator.

## done criteria

- Strict criteria helper and tests are in place.
- Orchestrator uses the helper for G2/G4/G5/G7/G8.
- Docs state that this closes the false-pass acceptance gap but not the full real-network device-lab matrix.

## scope guard

- Do not fake TC-17/TC-18/TC-20 receiver evidence without paired simulator output.
- Do not add third-device simulator orchestration in this local patch.

## accepted differences / intentionally out of scope

- Real GossipSub new-member join, three-party media fan-out, and Group + Announcement recovery matrix still require explicit device-lab execution.

## dependency impact

- Later simulator sessions can rely on the stricter G-row criteria to reject pending receiver evidence.
