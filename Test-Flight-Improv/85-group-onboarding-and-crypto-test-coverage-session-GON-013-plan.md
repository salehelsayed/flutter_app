# GON-013 Plan: Relay Failover And Same-Account Multi-Device Consistency

## real scope

- Keep TC-32 relay/libp2p failover distinct from fake-network inbox recovery.
- Keep TC-33 same-account simulator consistency distinct from host fake-backed multi-device convergence.
- Add only closure-run guardrails where fixture absence could otherwise look like passing coverage.

## closure bar

- Relay-selector and relay operation fallback tests pass at the Go node layer.
- Fake-network group recovery tests that cover partition/heal, duplicate live+inbox, and cursor order pass.
- Same-account host convergence tests pass.
- Fixture-backed relay and same-account simulator residuals remain explicit unless a device-lab run proves them.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-013`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-32 and TC-33.

## session classification

`implementation-ready`

## exact problem statement

Report 85 requires receiver-visible relay failover, replay ordering, and same-account multi-device simulator proof. The current repo has strong local evidence, but the real relay and real same-account simulator checks are fixture-bound and outside named gates. A closure run must not silently pass when those fixtures are absent.

## files and repos to inspect next

- `integration_test/multi_relay_failover_test.dart`
- `go-mknoon/node/multi_relay_test.go`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_multi_device_convergence_test.dart`
- `integration_test/group_multi_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`

## existing tests covering this area

- `go-mknoon/node/multi_relay_test.go` covers multi-relay selection and fallback attempts across dial, rendezvous, inbox, group inbox cursor retrieval, media upload, and profile download paths.
- `group_resume_recovery_test.dart` covers duplicate live+inbox dedupe, cursor-ordered backlog drain, partition/heal recovery, and resumed live delivery after heal.
- `group_multi_device_convergence_test.dart` covers same-user sent-history convergence, membership convergence without duplicate self-membership, and device-local mute/unread/notification state.
- `group_multi_device_real_harness.dart` plus `run_group_multi_device_real.dart` is the fixture-backed two-device proof harness, but it is outside the standard gate.

## regression/tests to add first

- Add an explicit `MKNOON_REQUIRE_MULTI_RELAY` closure flag to `multi_relay_failover_test.dart` so missing multi-relay configuration fails loudly when a closure/nightly job requires the fixture.
- Classify the same-account host oracle and real-device orchestrator in gate docs without promoting them into frozen named gates.

## step-by-step implementation plan

1. Add the strict multi-relay fixture-required flag.
2. Classify same-account host and real-device evidence in the gate docs/script where appropriate.
3. Run focused Go relay fallback tests.
4. Run focused group recovery and same-account host tests.
5. Run the strict relay fixture-required command locally and confirm it fails with a clear missing-fixture message.
6. Update Report 85 and closure references with accepted evidence and residual simulator/device-lab requirements.

## risks and edge cases

- A skipped integration test is not closure evidence for TC-32.
- Host fake-backed same-account convergence is useful product-contract evidence, but it is not a real same-account simulator run.
- Go relay fallback tests prove operation fallback attempts, not receiver-visible group convergence across a live relay outage.

## exact tests and gates to run

- `go test ./go-mknoon/node -run 'Test.*Relay|Test.*Inbox|Test.*Rendezvous|Test.*MediaUpload|Test.*ProfileDownload'`
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "temporary partition replays missed backlog in cursor order and resumes live delivery after heal"`
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "same message is not duplicated if both pubsub and group inbox deliver it"`
- `flutter test test/features/groups/integration/group_multi_device_convergence_test.dart`
- Expected local fixture check: `flutter test integration_test/multi_relay_failover_test.dart --dart-define=MKNOON_REQUIRE_MULTI_RELAY=true` fails when `MKNOON_RELAY_ADDRESSES` has fewer than two entries.

## known-failure interpretation

- Go relay fallback failures are real TC-32 regressions.
- Host recovery or multi-device failures are real product-contract regressions.
- The strict multi-relay fixture check should fail locally without relay config; a pass without relays would be a closure bug.

## done criteria

- Strict fixture absence cannot be mistaken for closure.
- Focused local proofs pass.
- Docs record TC-32 and TC-33 as partial with explicit real relay/simulator residuals.

## scope guard

- Do not claim live relay failover or same-account simulator closure without running the fixture-backed commands on devices.

## accepted differences / intentionally out of scope

- Full direct-to-relay fallback, relay-down, multi-relay failover, and same-account two-device simulator execution remain Nightly / Release Pool work.

## dependency impact

- GON-015 can reconcile final closure using these explicit partial classifications.
