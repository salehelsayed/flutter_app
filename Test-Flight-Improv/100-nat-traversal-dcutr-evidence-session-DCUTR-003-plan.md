# DCUTR-003 Relay-Only Delivery And Recovery No-Upgrade Acceptance Plan

Status: accepted_with_explicit_follow_up

## Planning Progress

- 2026-05-29 23:59:06 CEST - Arbiter completed. Files inspected since last update: reviewer findings and final plan sections. Decision/blocker: no structural blockers remain; plan is execution-ready for DCUTR-003 only. Next action: downstream execution/QA may consume this file without changing Go event names, Dart metrics contract, reachability policy, relay server behavior, NAT policy, or final source-doc closure.
- 2026-05-29 23:59:06 CEST - Reviewer completed / Arbiter started. Files inspected since last update: plan draft only. Decision/blocker: sufficient as-is; checklist coverage, device/relay proof profile, environment-gated real relay/CLI language, reliability-sim command paths, named gates, and scope guard are explicit. Next action: classify findings and finalize reusable status.
- 2026-05-29 23:57:36 CEST - Planner completed / Reviewer started. Files inspected since last update: current draft content and evidence ledger. Decision/blocker: draft covers the user checklist, Go/integration/Flutter proof tiers, named gates, and environment-gated real relay/CLI evidence. Next action: review for missing simulator-gate language, overclaiming, and scope leaks.
- 2026-05-29 23:56:23 CEST - Evidence Collector completed / Planner started. Files inspected since last update: source doc, session breakdown, accepted DCUTR-001/002 plans, gate definitions, regression strategy, NAT/DCUtR and simulation docs, Go tracer/relay/integration tests, Flutter transport E2E and relay-degradation tests. Decision/blocker: no prerequisite blocker; DCUTR-003 must be a relay-only acceptance plan with environment-gated real relay/CLI proof language. Next action: draft mandatory plan sections and checklist coverage ledger.
- 2026-05-29 23:55:04 CEST - Evidence Collector started. Files inspected since last update: `git status --short`, `rg --files` transport/doc/test inventory. Decision/blocker: required plan artifact created; dirty worktree contains many pre-existing transport/doc changes, so planning must avoid modifying anything except this file. Next action: inspect breakdown, source doc, prior accepted DCUTR plans, gate definitions, and direct relay/DCUtR tests.

## Execution Progress

- 2026-05-30 00:23 CEST - Local continuation completed after spawned execution/QA stalled. Files touched since last update: `go-mknoon/node/holepunch_negative_control_test.go`, `go-mknoon/integration/watchdog_failover_test.go`, this plan. Commands finished: focused Go node proof passed; focused Go local integration proof passed; external real-relay integration proof passed; direct Flutter host tests passed; `git diff --check` passed; reliability-sim device list resolved; `run_wifi_relay_fallback_smoke.dart` passed; `run_transport_e2e.dart` was run twice and failed both times only at the external orchestrator E8 media metadata proof after the Flutter test reported `33/33 passed` and the orchestrator could still download the blob. Decision/blocker: DCUTR-003 relay-only/no-upgrade acceptance is implemented and verified for the scoped Go and Flutter recovery proofs; the repeated transport E2E media-metadata failure is unrelated to DCUTR-003 touched files and remains an explicit residual for DCUTR-004 classification. Next action: closure audit may accept DCUTR-003 with the E2E residual recorded and must not treat simulator/CLI evidence as production mobile DCUtR success.
- 2026-05-30 00:06:13 CEST - Go proof commands passed. Files touched since last update: none. Commands finished: `cd go-mknoon && go test ./node -run 'TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash|TestHolePunchTracer|TestClassifyStreamTransport'` passed after patch (`ok github.com/mknoon/go-mknoon/node 4.647s`); `cd go-mknoon && go test -tags=integration ./integration -run 'TestSecondRelayAvailablePreventsWatchdogRestart|TestAllRelaysUnavailableEnterDegradedStateAndRecover|TestRendezvousAndInboxStillWorkAfterRelayRestart'` passed (`ok github.com/mknoon/go-mknoon/integration 24.115s`); `cd go-mknoon && go test -tags=integration ./integration -run 'TestRelayTwoNodesMessage|TestRelayCircuitRecoveryAfterDisconnect|TestRelayCircuitRecoveryPreservesPeerId|TestRelayRefreshRecoversWithoutHostReplacement'` passed (`ok github.com/mknoon/go-mknoon/integration 11.154s`). Decision/blocker: `cd go-mknoon && go test ./node` not triggered because `node.go`, shared relay helpers, send-message recovery, and tracer code were not changed. Next action: run the required direct Flutter host tests.
- 2026-05-30 00:04:51 CEST - DCUTR-003 Go test patch landed. Files touched since last update: `go-mknoon/node/holepunch_negative_control_test.go`, `go-mknoon/integration/watchdog_failover_test.go`. Decision/blocker: negative control now uses strict `SendMessageWithTransport` over the forced circuit and verifies receiver `message:received` transport/content; local relay recovery tests now attach event collectors and assert no `holepunch:success` or `transport:upgraded`. Next action: rerun focused Go node proof, then focused Go integration proof.
- 2026-05-30 00:03:38 CEST - Pre-edit regression passed / scoped tests inspected. Files inspected since last update: `go-mknoon/node/holepunch_negative_control_test.go`, `go-mknoon/integration/watchdog_failover_test.go`, `go-mknoon/integration/local_relay_harness_test.go`, `go-mknoon/integration/relay_test.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/holepunch_tracer.go`, `lib/core/debug/transport_metrics.dart`, `lib/core/services/p2p_service_impl.dart`. Command finished: `cd go-mknoon && go test ./node -run 'TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash|TestHolePunchTracer|TestClassifyStreamTransport'` passed (`ok github.com/mknoon/go-mknoon/node 4.638s`). Decision/blocker: focused relay-only/no-upgrade regression was green before edits; negative-control send is still non-fatal and local relay recovery tests lack no-upgrade collectors. Next action: patch only DCUTR-003 Go test files.
- 2026-05-30 00:01:57 CEST - Executor contract extracted / pre-edit regression queued. Files inspected since last update: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-003-plan.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`, `git status --short`. Decision/blocker: scope is DCUTR-003 only; acceptance requires strict limited-circuit relay-only delivery, exact zero hole-punch attempts/successes, no `holepunch:success`, no `transport:upgraded`, stable target-peer connection count, relay recovery no-upgrade assertions, and fixture-gated simulator/CLI evidence without production mobile DCUtR claims. Next action: run the required focused Go node regression before any DCUTR-003 code/test edit.
- 2026-05-30 00:00:26 CEST - Contract extracted / Executor handoff preparing. Files inspected since last update: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-003-plan.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`, `$implementation-execution-qa-orchestrator`, `git status --short`. Decision/blocker: scope is DCUTR-003 only; required sequence is relay-only/no-upgrade regressions first, then patch only DCUTR-003-scoped files if failures are in scope; spawned Executor and QA Reviewer must use `gpt-5.5` with `model_reasoning_effort=xhigh`. Next action: spawn fresh Executor to run the focused relay-only/no-upgrade regressions and implementation pass.

## real scope

This session proves that relay-only delivery and relay recovery are successful outcomes and do not create false DCUtR upgrade evidence.

In scope:

- Verify or add acceptance that a production-private, relay-only peer pair stays on a real limited circuit connection.
- Verify or add acceptance that this relay-only pair records zero hole-punch successes, zero upgrade events, and exact zero attempts when no direct route or reachable address exists.
- Verify or add acceptance that the relay-only peer connection count does not oscillate during a steady polling window.
- Verify or add acceptance that a relay-backed 1:1 message can be delivered successfully without requiring a direct upgrade.
- Verify or add acceptance that relay drop/recovery continues to deliver or recover messages without emitting `transport:upgraded` or `holepunch:success`.
- Verify Dart-side relay/inbox recovery acceptance only where it consumes the accepted DCUTR-002 metrics and recovery surface. Keep it aggregate and do not add per-peer or per-address diagnostics.

Out of scope:

- No Go event-name changes.
- No Dart metrics contract change.
- No production reachability-policy change.
- No relay server behavior change.
- No NAT traversal, AutoNAT, WebRTC, TURN/STUN, or explicit hole-punch trigger change.
- No final source-doc, baseline, or decision-doc closure. DCUTR-004 owns that.
- No production mobile DCUtR success claim from local relay, simulator, loopback, LAN direct, or label-only evidence.

## closure bar

DCUTR-003 is good enough when the repo can prove the dominant relay-only case is both successful and non-upgraded.

Checklist coverage ledger:

| User-listed requirement | Required planned proof |
|---|---|
| Dominant relay-only case remains valid success | A strict Go relay-only 1:1 delivery proof sends over a forced circuit route and observes receiver delivery, plus Flutter 1:1 degradation/recovery tests prove app-level delivery/retry remains successful without direct upgrade. |
| Real limited circuit connections | Go local circuit relay proof must call the NW002 pattern: clear direct route state, clear peerstore direct addrs, dial by `DialPeerViaRelay`, and assert `conn.Stat().Limited == true` throughout the steady-state window. |
| Zero hole-punch success | Relay-only Go proof must assert `tracer.Successes() == 0` and no `holepunch:success` events. |
| Zero or bounded attempts where appropriate | Forced relay-only/private proof must assert exact `tracer.Attempts() == 0`. If a real-relay/device fixture emits attempts because the environment exposed usable direct addresses, the test must fail the relay-only proof or classify that run as not the relay-only negative control, not silently accept it. |
| No `transport:upgraded` events | Go collectors and Dart metrics/recovery proof must assert zero `transport:upgraded` events and `relayToDirectUpgrades == 0` for relay-only/recovery paths. |
| No connection-count thrash | Steady relay-only Go proof must snapshot `ConnsToPeer(target)` after the circuit dial and assert the count stays stable during the polling window. Relay-drop tests may change relay-peer counts by design, but must not show target-peer phantom upgrade/downgrade loops. |
| Successful relay-backed 1:1 delivery | Add or tighten Go acceptance so `SendMessageWithTransport` over the forced circuit succeeds, returns/records `transport == relay`, and the receiver emits `message:received`. The current non-fatal send in `TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash` is insufficient if it remains non-fatal at execution time. |
| Relay-drop/recovery does not manufacture upgrade | Local Go integration relay restart/failover tests and app-level relay degradation tests must assert no `holepunch:success` or `transport:upgraded` evidence is emitted while rendezvous/inbox/live delivery recovers over relay/inbox. |
| Do not overclaim production mobile DCUtR success | Final execution summary must classify the proof as host Go local-relay plus conditional external-relay/device evidence only; production mobile NAT success remains unproven. |

The closure bar is not met if delivery only proves liveness with `direct||relay||inbox` set-acceptance and never proves the no-upgrade counters/events.

## source of truth

- Active session contract: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`, row `DCUTR-003`.
- Product/test intent: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`.
- Accepted prerequisite event and metrics contracts: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-002-plan.md`, `go-mknoon/bridge/events.go`, `go-mknoon/node/holepunch_tracer.go`, `lib/core/debug/transport_metrics.dart`, `lib/core/services/p2p_service_impl.dart`.
- Gate execution source: `scripts/run_test_gates.sh`. If it disagrees with `Test-Flight-Improv/test-gate-definitions.md`, the script wins.
- Test proof doctrine: `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`.

Current code and focused tests win over stale prose. The breakdown and source doc define the session boundary. DCUTR-004 owns final doc closure if wording needs reconciliation after execution.

## session classification

`implementation-ready`

Reason: prerequisites DCUTR-001 and DCUTR-002 are accepted in the breakdown, and this session has deterministic host Go tests to add or tighten first. Real external relay and Flutter CLI/device proof are required where their fixtures are available, but fixture absence is an environment-gated proof limitation, not a planning blocker.

## exact problem statement

The missing acceptance risk is false upgrade evidence in the most common real-world outcome: peers deliver over relay and never become direct. The app must treat that as success, not as a failed DCUtR journey, and must not fabricate direct-upgrade events, counters, or labels during relay-only delivery or relay recovery.

User-visible behavior must stay stable: 1:1 delivery succeeds through relay or inbox fallback when direct traversal is impossible. Diagnostics must make absence of upgrade evidence clear. Production reachability remains private and no change in this session should make cellular or symmetric-NAT peers appear to have successful DCUtR.

## Device/Relay Proof Profile

Primary proof tier: host Go real-stack, local circuit relay.

- Uses a real libp2p local circuit relay from `startNW002LocalCircuitRelay`.
- Proves the actual route with `conn.Stat().Limited == true`, not a string default.
- Proves no false upgrade with tracer counters and emitted event assertions.
- Does not prove production mobile DCUtR success.

Secondary proof tier: Go external relay integration.

- `go test -tags=integration ./integration/...` can prove real relay liveness/recovery when the configured relay is reachable.
- `go-mknoon/integration/relay_test.go` explicitly skips when `SKIP_RELAY_TESTS` is set or the relay is unreachable. Such a skip is environment-gated, not accepted DCUtR evidence.

Flutter proof tier: host and simulator/app integration.

- Host Flutter tests prove app-level relay/inbox degradation and transport metrics contract.
- `integration_test/transport_e2e_test.dart` and `integration_test/wifi_relay_fallback_smoke_test.dart` are 1 device plus Go CLI peer fixtures. They are useful liveness/recovery evidence only when the orchestrator/CLI fixture is present.
- Standard simulator reliability runs use the configured relay and typically disable LAN discovery; they cannot prove physical NAT traversal or production mobile DCUtR.
- Required reliability-sim command uses the `1to1` scope with the relevant runner paths. If devices or CLI fixtures are unavailable, classify the session as evidence-gated for simulator/CLI proof and do not call production mobile DCUtR closed.

## files and repos to inspect next

Production and contract files:

- `go-mknoon/node/node.go`
- `go-mknoon/node/holepunch_tracer.go`
- `go-mknoon/bridge/events.go`
- `lib/core/debug/transport_metrics.dart`
- `lib/core/services/p2p_service_impl.dart`

Focused Go tests and helpers:

- `go-mknoon/node/holepunch_negative_control_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/holepunch_tracer_test.go`
- `go-mknoon/node/send_message_recovery_test.go`
- `go-mknoon/node/relay_session_test.go`
- `go-mknoon/integration/local_relay_harness_test.go`
- `go-mknoon/integration/relay_test.go`
- `go-mknoon/integration/watchdog_failover_test.go`

Focused Flutter tests and runners:

- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/core/debug/transport_metrics_holepunch_test.dart`
- `test/core/debug/transport_metrics_privacy_test.dart`
- `test/integration/relay_down_degradation_integration_test.dart`
- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/wifi_relay_fallback_smoke_test.dart`
- `integration_test/scripts/run_transport_e2e.dart`
- `integration_test/scripts/run_wifi_relay_fallback_smoke.dart`
- `scripts/run_test_gates.sh`
- `scripts/run_reliability_simulations.sh`

## existing tests covering this area

- `go-mknoon/node/holepunch_negative_control_test.go` currently covers relay-only negative control with a real local circuit route, exact zero attempts/successes, no `transport:upgraded`, and stable connection count. Its send over circuit is non-fatal, so it is not yet enough for the successful 1:1 delivery requirement if execution confirms that remains true.
- `go-mknoon/node/pubsub_delivery_test.go` provides the NW002 local relay helpers: local relay service, direct route clearing, no direct peerstore addrs, and `assertNW002LimitedCircuitConn`.
- `go-mknoon/node/holepunch_tracer_test.go` covers tracer event/counter behavior and stale limited-state repair after a real tracer success.
- `go-mknoon/node/relay_session_test.go` covers relay state transitions, failure thresholds, recovery coalescing, and watchdog behavior, but it is pure state-machine coverage and does not prove transport events.
- `go-mknoon/integration/relay_test.go` covers real external relay connection, two-node message delivery, circuit address recovery, and relay refresh, but it skips when the external relay fixture is unavailable and does not currently assert no DCUtR upgrade evidence.
- `go-mknoon/integration/watchdog_failover_test.go` uses local relay pairs to prove failover, degraded/recovered states, rendezvous, and inbox delivery through relay recovery, but it needs no-upgrade event assertions for DCUTR-003.
- `test/core/services/p2p_service_inbound_transport_test.dart` covers DCUTR-002 metric consumption, including exact attempt/success/failure/upgrade counts and direct inference only after accepted upgrade evidence.
- `test/integration/relay_down_degradation_integration_test.dart` covers app-level 1:1 degradation, failed-send persistence, online-transition recovery, and inbox transport for recovery; it does not by itself prove Go relay-limited circuits or absence of `transport:upgraded`.
- `integration_test/transport_e2e_test.dart` and `integration_test/wifi_relay_fallback_smoke_test.dart` cover real app/Go/CLI liveness and fallback when fixtures are present, but they intentionally accept multiple live transports in several scenarios and must not be treated as specific DCUtR proof without added event/counter assertions.

## regression/tests to add first

Add or verify tests before production edits:

1. Tighten or split `TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash`.
   - Keep the existing forced relay-only setup.
   - Replace the non-fatal `SendMessage` exercise with a strict delivery assertion if the current handler supports it:
     - call `SendMessageWithTransport(nodeB.PeerId(), "I1-NC relay-only ping", 5000)`;
     - assert no error;
     - assert `result.Transport == "relay"`;
     - assert receiver event `message:received` contains the sent content and `transport == "relay"`.
   - Continue asserting `conn.Stat().Limited == true`, `tracer.Attempts() == 0`, `tracer.Successes() == 0`, no `holepunch:success`, no `transport:upgraded`, and stable `ConnsToPeer` count.
   - If strict send fails because the node-package harness lacks an app-like stream/ack path, add a new focused test using existing node package helpers rather than weakening the acceptance to non-fatal liveness.

2. Add or verify relay-drop/recovery no-upgrade acceptance in `go-mknoon/integration/watchdog_failover_test.go`.
   - Use callback collectors for involved nodes.
   - Exercise surviving-relay and all-relays-down-then-recover paths already present in `TestSecondRelayAvailablePreventsWatchdogRestart` and `TestAllRelaysUnavailableEnterDegradedStateAndRecover`.
   - Assert rendezvous/inbox delivery succeeds as today.
   - Assert no collected `holepunch:success` or `transport:upgraded` event is emitted during recovery.
   - Do not require exact attempt count in this external-package integration test unless an exported counter or event makes it trustworthy without changing production API.

3. Add or verify a Dart/app metrics no-upgrade regression only if the execution touches Dart recovery or metrics code.
   - Preferred file: `test/integration/relay_down_degradation_integration_test.dart` or `test/core/services/p2p_service_inbound_transport_test.dart`.
   - Assert relay/inbox degradation recovery leaves `TransportMetrics.relayToDirectUpgrades == 0` and does not infer `direct` without a matching `transport:upgraded` event.
   - Do not add any raw peer IDs, multiaddrs, message content, or conversation IDs to diagnostics.

If these regressions already exist at execution time, cite them and proceed directly to verification.

## step-by-step implementation plan

1. Re-read all scoped dirty files before editing. Treat existing changes as user-owned and patch only around them.
2. Verify DCUTR-001 and DCUTR-002 accepted contracts still exist: Go event names in `go-mknoon/bridge/events.go`, tracer behavior in `go-mknoon/node/holepunch_tracer.go`, and Dart metric names in `lib/core/debug/transport_metrics.dart`.
3. Add or tighten the Go relay-only negative-control delivery test first.
4. Run only the focused Go node test command. If it fails, fix the smallest test harness or node-package behavior needed to make relay-limited delivery strict without changing production reachability or NAT policy.
5. Add or tighten local Go integration relay-drop/recovery no-upgrade assertions.
6. Run the focused Go integration command for `watchdog_failover` and the external-relay command where the fixture is available. Record environment skips exactly.
7. Add Dart/app no-upgrade regression only if Dart recovery/metrics behavior changes or if execution needs app-level proof that relay/inbox recovery does not increment upgrade counters.
8. Run direct Flutter tests listed below. If only Go tests changed and no Flutter/Dart files changed, keep Flutter tests as verification evidence but do not patch Flutter code.
9. Run named gates triggered by touched files: `transport` for bridge/resume/reconnect/transport fallback, `1to1` for shared 1:1 send/retry/listener/inbox behavior, and `completeness-check` for new test-file or gate-doc classification.
10. Run the reliability-sim `1to1` runner paths when simulator/device and relay/CLI fixtures are available. If not, record the environment blocker using the exact missing fixture/device language.
11. Stop after DCUTR-003 tests and plan status are updated. Do not update the final source doc or architecture decision docs.

## risks and edge cases

- Relay-only success can be accidentally weakened into "delivery worked somehow"; the Go proof must assert `conn.Stat().Limited == true` and `transport == relay`.
- A relay drop naturally changes relay-peer connection counts; only steady target-peer phantom upgrade/downgrade loops are forbidden.
- Real external relay tests may skip because `SKIP_RELAY_TESTS` is set or the relay is unreachable; that is not a green real-relay proof.
- Simulator/CLI transport E2E can run self-contained fallback scenarios without a CLI peer fixture; that does not satisfy relay-drop/CLI recovery acceptance.
- Existing E2E tests often accept `direct||relay||inbox` for liveness. That is acceptable only as liveness evidence, not as no-upgrade evidence.
- Tightening Go local relay tests may expose timing flake; use bounded polling and existing helper patterns rather than broad sleeps.
- Any Dart metrics assertion must stay aggregate and privacy-safe.
- Existing dirty worktree changes in shared transport files must not be reverted.

## exact tests and gates to run

Focused Go node proof:

```bash
cd go-mknoon && go test ./node -run 'TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash|TestHolePunchTracer|TestClassifyStreamTransport'
```

Broader Go node command if `node.go`, shared relay helpers, send-message recovery, or tracer code changes:

```bash
cd go-mknoon && go test ./node
```

Focused Go local integration proof:

```bash
cd go-mknoon && go test -tags=integration ./integration -run 'TestSecondRelayAvailablePreventsWatchdogRestart|TestAllRelaysUnavailableEnterDegradedStateAndRecover|TestRendezvousAndInboxStillWorkAfterRelayRestart'
```

External real-relay integration proof, environment-gated:

```bash
cd go-mknoon && go test -tags=integration ./integration -run 'TestRelayTwoNodesMessage|TestRelayCircuitRecoveryAfterDisconnect|TestRelayCircuitRecoveryPreservesPeerId|TestRelayRefreshRecoversWithoutHostReplacement'
```

If this command skips because `SKIP_RELAY_TESTS` is set or the configured relay is unreachable, report it as "real external relay fixture unavailable; proof environment-gated", not as a pass.

Direct Flutter host tests:

```bash
flutter test \
  test/core/services/p2p_service_inbound_transport_test.dart \
  test/core/debug/transport_metrics_holepunch_test.dart \
  test/core/debug/transport_metrics_privacy_test.dart \
  test/integration/relay_down_degradation_integration_test.dart \
  test/features/conversation/integration/two_user_message_exchange_test.dart
```

Transport integration named gate when bridge, resume, reconnect, transport fallback, or app bootstrap paths change:

```bash
./scripts/run_test_gates.sh transport
```

If a specific device is required:

```bash
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
```

1:1 reliability named gate when shared 1:1 send, retry, listener, inbox, or recovery behavior changes:

```bash
./scripts/run_test_gates.sh 1to1
```

Completeness gate when new test files, gate docs, or gate scripts change:

```bash
./scripts/run_test_gates.sh completeness-check
```

Reliability simulator/CLI closure profile for 1:1 relay recovery, environment-gated:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
```

Then run the DCUTR-relevant runner paths when devices and relay/CLI fixtures are available:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only integration_test/scripts/run_transport_e2e.dart
```

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only integration_test/scripts/run_wifi_relay_fallback_smoke.dart
```

If device resolution fails, report the number of booted iPhone simulators found and whether one-device or two-device proof was needed. If the orchestrator runs without a CLI peer fixture, classify only the self-contained scenarios as run and leave CLI relay/recovery proof evidence-gated.

Formatting and whitespace:

```bash
git diff --check
```

## known-failure interpretation

- A failure in the focused Go node negative-control command is in scope unless it is caused by unrelated dirty worktree edits outside the DCUTR-003 files.
- A `go test -tags=integration ./integration ...` skip caused by `SKIP_RELAY_TESTS` or relay reachability is an environment-gated missing proof, not a regression and not a production DCUtR result.
- A Flutter transport gate failure due only to missing `FLUTTER_DEVICE_ID`, missing booted simulator, or app launch infrastructure is environment-gated. Record exact output.
- A reliability-sim failure to resolve devices or CLI fixtures means simulator/CLI proof remains evidence-gated. Do not replace it with host-only proof while calling the session fully production closed.
- Existing red tests outside touched DCUTR-003 files should be named as pre-existing or unrelated only with concrete evidence.

## done criteria

- The plan/work result remains scoped to DCUTR-003 only.
- Go local relay proof demonstrates a real limited circuit route for the peer pair.
- Go relay-only proof asserts exact zero hole-punch attempts, exact zero successes, no `holepunch:success`, no `transport:upgraded`, stable target peer connection count, and successful relay-backed 1:1 message delivery.
- Relay-drop/recovery proof demonstrates recovery or fallback delivery without `holepunch:success` or `transport:upgraded`.
- Dart/app proof, if touched, demonstrates relay/inbox recovery does not increment relay-to-direct upgrade counters or infer direct without accepted upgrade evidence.
- Required focused Go tests pass or are classified with exact in-scope failure details.
- Required direct Flutter tests pass if Dart/app seams are touched, or any failure is classified exactly.
- Required named gates run when their trigger applies, or their device/fixture blockers are recorded.
- Reliability-sim 1:1 runner paths run when available, or the missing device/CLI fixture is recorded as an explicit evidence gate.
- No Go event names, Dart metrics contract, production reachability policy, relay server behavior, NAT traversal policy, or final source-doc closure changes occur.
- Final execution summary does not overclaim production mobile DCUtR success.

## scope guard

Do not broaden this session into a direct-upgrade implementation, reachability policy decision, relay server feature, WebRTC/TURN/STUN work, settings redesign, baseline harvest, or final NAT/DCUtR product verdict. Do not reinterpret a LAN direct dial or per-stream `direct` label as a DCUtR upgrade. Do not relax `ForceReachabilityPrivate()` or add a production path that forces public reachability. Do not change the names or shape of `holepunch:attempt`, `holepunch:success`, `holepunch:failure`, or `transport:upgraded`.

## accepted differences / intentionally out of scope

- A relay-only delivery is a successful result, not a failed upgrade.
- Local Go circuit-relay evidence is high-quality relay-only proof, but it is not production mobile NAT proof.
- External real-relay and Flutter CLI/device proof are fixture-dependent and may be environment-gated.
- Simulator transport runs cannot prove physical DCUtR NAT traversal and must not be used to claim production mobile DCUtR success.
- Group relay-only delivery examples can support relay doctrine, but DCUTR-003 closure is centered on 1:1 relay-only delivery and recovery.
- Final source-doc, NET-REL baseline, and architecture decision closure stay deferred to DCUTR-004.

## dependency impact

- DCUTR-004 depends on this session for a trustworthy relay-only/no-upgrade acceptance record before it updates the source doc, baseline decision gate, and residual classification.
- If DCUTR-003 cannot add strict relay-backed 1:1 delivery proof, DCUTR-004 must not mark relay-only delivery acceptance closed; it should record an evidence-gated blocker.
- If real external relay or simulator/CLI proof is unavailable, later closure may still accept host Go relay-only proof, but must label production mobile DCUtR and real-relay/device proof as residual or evidence-gated.

## Final Execution Verdict

Verdict: `accepted_with_explicit_follow_up` for DCUTR-003.

Implementation summary:

- `go-mknoon/node/holepunch_negative_control_test.go` now strictly proves relay-only 1:1 delivery over a forced limited circuit with `SendMessageWithTransport`, receiver-side `message:received` transport/content validation, exact zero hole-punch attempts, exact zero successes, no `holepunch:success`, no `transport:upgraded`, and stable target-peer connection count.
- `go-mknoon/integration/watchdog_failover_test.go` now collects relay-recovery events and fails if local relay failover/recovery emits `holepunch:success` or `transport:upgraded` while rendezvous/inbox recovery remains successful.
- No Go event names, Dart metrics contract, production reachability policy, relay-server behavior, NAT policy, or final source-doc closure changed.

Verification:

- `cd go-mknoon && go test ./node -run 'TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash|TestHolePunchTracer|TestClassifyStreamTransport'` passed.
- `cd go-mknoon && go test -tags=integration ./integration -run 'TestSecondRelayAvailablePreventsWatchdogRestart|TestAllRelaysUnavailableEnterDegradedStateAndRecover|TestRendezvousAndInboxStillWorkAfterRelayRestart'` passed.
- `cd go-mknoon && go test -tags=integration ./integration -run 'TestRelayTwoNodesMessage|TestRelayCircuitRecoveryAfterDisconnect|TestRelayCircuitRecoveryPreservesPeerId|TestRelayRefreshRecoversWithoutHostReplacement'` passed.
- `flutter test test/core/services/p2p_service_inbound_transport_test.dart test/core/debug/transport_metrics_holepunch_test.dart test/core/debug/transport_metrics_privacy_test.dart test/integration/relay_down_degradation_integration_test.dart test/features/conversation/integration/two_user_message_exchange_test.dart` passed.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list` passed and resolved one-device, two-device, and intro-device simulator sets.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only integration_test/scripts/run_wifi_relay_fallback_smoke.dart` passed.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only integration_test/scripts/run_transport_e2e.dart` was attempted twice and failed both times at the external orchestrator E8 media metadata proof: Flutter reported `33/33 passed`, the orchestrator downloaded the 69-byte blob, but `messageSeen=false`, `attachmentReferenced=false`, and `blobInList=false`, producing `29/30 passed`. This is recorded as an unrelated transport E2E media residual, not as a DCUTR-003 no-upgrade failure.
- `git diff --check` passed.

Residual for DCUTR-004:

- Production mobile DCUtR success remains unproven.
- Standard simulator and CLI proof is relay/recovery liveness evidence only, not physical NAT traversal evidence.
- The repeated `run_transport_e2e.dart` E8 media metadata orchestrator failure must be classified in final closure; it should not be used to reopen relay-only/no-upgrade acceptance unless a later failure ties it to the DCUTR-003 touched Go tests.

## Closure Audit Verdict

Recorded: 2026-05-30 CEST

Closure verdict: `accepted_with_explicit_follow_up` for DCUTR-003 only.

Completion auditor findings:

- Verified touched DCUTR-003 scope from current files and recorded execution evidence: `go-mknoon/node/holepunch_negative_control_test.go`, `go-mknoon/integration/watchdog_failover_test.go`, and this plan.
- Verified the relay-only closure bar is met: forced limited circuit delivery uses `SendMessageWithTransport`, records receiver-side `message:received` content/transport, keeps exact zero hole-punch attempts and successes, emits no `holepunch:success` or `transport:upgraded`, and holds a stable target-peer connection count.
- Verified relay recovery closure is met: local relay failover/recovery tests collect node events and fail on `holepunch:success` or `transport:upgraded` while rendezvous/inbox recovery remains successful.
- Accepted recorded proof commands: focused Go node proof passed; focused Go local integration proof passed; external real-relay integration proof passed; direct Flutter host tests passed; reliability-sim `1to1 --list` passed; reliability-sim `run_wifi_relay_fallback_smoke.dart` passed; `git diff --check` passed.
- Closure audit did not re-run Go, Flutter, or simulator tests and did not edit code. It inspected the scoped evidence and re-ran `git diff --check`, which passed.

Closed for DCUTR-003:

- Relay-only/no-upgrade acceptance is closed.
- Relay-backed 1:1 delivery over a real limited circuit is accepted as a valid successful outcome.
- Absence of false DCUtR upgrade evidence is closed for the scoped relay-only and relay-recovery paths.
- Relay recovery without manufactured `transport:upgraded` or `holepunch:success` evidence is closed.

Accepted follow-up / residual-only items for DCUTR-004:

- Production mobile DCUtR success remains unproven.
- Simulator and CLI proof is relay/recovery liveness evidence, not physical NAT traversal proof.
- The repeated reliability-sim `run_transport_e2e.dart` E8 media metadata orchestrator failure remains an explicit final-closure classification item: Flutter reported `33/33 passed` and the orchestrator downloaded the 69-byte blob, but `messageSeen=false`, `attachmentReferenced=false`, and `blobInList=false`, producing `29/30 passed`.
- Final source-doc, baseline, and architecture decision closure remain deferred to DCUTR-004.

Reopen rule:

- Reopen DCUTR-003 only for a real regression in forced relay-only delivery, limited-circuit proof, no-upgrade counters/events, target-peer connection-count stability, or relay-recovery no-upgrade behavior. Do not reopen it only because production mobile DCUtR or the E8 media metadata residual remains unclassified.

## Reviewer findings

Sufficiency: sufficient as-is.

- Missing files, tests, or gates: none structural. The plan names focused Go node tests, Go integration tests, direct Flutter host tests, `transport`, `1to1`, `completeness-check`, and the reliability-sim `1to1` runner paths for `run_transport_e2e.dart` and `run_wifi_relay_fallback_smoke.dart`.
- Stale or incorrect assumptions: none found. The plan treats DCUTR-001 and DCUTR-002 as accepted because the breakdown records them accepted, and it defers final source-doc closure to DCUTR-004.
- Overengineering: none structural. Reliability-sim is included only as an environment-gated 1:1 relay/recovery proof because this session touches mobile transport/recovery acceptance.
- Decomposition: sufficiently narrow. Implementation is verification-first and stops at relay-only/no-upgrade acceptance.
- Checklist parity: complete. Every user-listed behavior maps to a concrete proof, gate, accepted difference, or environment-gated blocker.
- Minimum needed to implement safely: follow the regression-first order, preserve existing dirty worktree changes, and avoid production reachability/NAT/relay-server/event/metrics changes.

## Arbiter decision

Classification: `execution-ready`

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact external relay and simulator device IDs are execution-time facts.
- Exact reliability-sim command numbers should come from the required `--list` pass before execution; the reusable plan uses stable runner paths.
- Existing dirty worktree failures, if any, must be classified during execution with concrete command output.

Accepted differences intentionally left unchanged:

- Host Go local-relay proof is not production mobile DCUtR success.
- Simulator and CLI proof can show liveness/recovery, but not physical NAT traversal.
- Real external relay/CLI fixtures may be unavailable and must be reported as environment-gated.
- DCUTR-004, not DCUTR-003, owns source-doc, baseline, and final architecture-decision closure.
