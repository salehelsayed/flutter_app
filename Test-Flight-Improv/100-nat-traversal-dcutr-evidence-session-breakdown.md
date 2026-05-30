Status: reusable-session-breakdown

# 100 NAT Traversal DCUtR Evidence Session Breakdown

## Run Mode Snapshot

- Snapshot refreshed: 2026-05-29 23:08 CEST
- Active mode: standard
- Degraded local continuation explicitly allowed: no
- Source proposal, matrix, or closure doc path: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`
- Source row/status vocabulary: narrative spec sections with `Existing partial coverage`, `Current gap`, accepted ambiguities, and closure/residual wording; no row-owned matrix statuses are defined in the source doc.
- Overall closure bar: NAT/DCUtR evidence is trustworthy when the app can prove and surface the difference between a real relay-to-direct DCUtR upgrade, an ordinary relay-backed delivery, a LAN/pre-relay direct dial, and an unknown label; relay-only or unpunchable peers remain delivered over relay without false upgrade events or connection thrash; production reachability stays private unless a later decision-gate explicitly changes policy; diagnostics remain aggregate and privacy-safe; and the source/decision docs record only evidence that current tests or a valid harvest can actually support.
- Final verdict policy for this run: use `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`; do not overclaim production DCUtR success from loopback feasibility, LAN direct dial, or simulator evidence; use `still_open` if required session execution/closure is missing or if the closure bar is not met.

## Decomposition Progress

| Phase | Files inspected | Current next action |
|------|-----------------|---------------------|
| Evidence Collector intake | `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`; `Test-Flight-Improv/14-regression-test-strategy.md`; `Test-Flight-Improv/test-gate-definitions.md`; `git status --short` | Inspect NET-REL docs and NAT/DCUtR code seams. |
| Evidence Collector | `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`; `Network-Arch/Transport-Reliability/04-transport-observability.md`; `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`; `Test-Flight-Improv/99-transport-observability-and-metrics.md`; `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`; `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`; Go/Dart code and direct tests listed below | Map closure target and split sessions by proof seam. |
| Closure Mapper | Source doc scope/non-goals, existing NET-REL-04 closure, production `ForceReachabilityPrivate`, Go tracer/test seams, Dart `TransportMetrics` hole-punch counters, relay-only negative-control tests | Keep routing/reachability/WebRTC policy out of scope; isolate evidence and closure work. |
| Session Splitter | Go tracer/classifier proofs, Dart bridge/diagnostics proofs, relay-only recovery acceptance, final harvest/closure docs | Run reviewer and arbiter pass for hidden coupling and gate coverage. |
| Reviewer and Arbiter | Proposed four-session set, gate contracts, matrix ownership, accepted non-goals | No structural blockers. Send sessions downstream in order; refresh later plans against landed code before execution. |

## Recommended Plan Count

Recommended plan count: 4

Create four doc-scoped session plans:

- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-002-plan.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-003-plan.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-004-plan.md`

## Decomposition Artifact

- Artifact path: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code before execution.
- Scope rule: do not execute implementation from this breakdown. Each session must go through planning, execution/QA, and closure before the next dependent session is treated as ready.

## Overall Closure Bar

NAT/DCUtR evidence is trustworthy when the app can prove and surface the difference between a real relay-to-direct DCUtR upgrade, an ordinary relay-backed delivery, a LAN/pre-relay direct dial, and an unknown label; relay-only or unpunchable peers remain delivered over relay without false upgrade events or connection thrash; production reachability stays private unless a later decision-gate explicitly changes policy; diagnostics remain aggregate and privacy-safe; and the source/decision docs record only evidence that current tests or a valid harvest can actually support.

## Source Of Truth

- Product intent and test cases: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`
- Regression model: `Test-Flight-Improv/14-regression-test-strategy.md`
- Gate execution source: `Test-Flight-Improv/test-gate-definitions.md`
- NAT/DCUtR reference: `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`
- Transport observability closure: `Test-Flight-Improv/99-transport-observability-and-metrics.md`
- Transport baseline decision gate: `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`
- Test doctrine and simulator limits: `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`
- Current Go seams: `go-mknoon/node/node.go`, `go-mknoon/node/holepunch_tracer.go`, `go-mknoon/node/transport_label_test.go`, `go-mknoon/node/holepunch_tracer_test.go`, `go-mknoon/node/holepunch_feasibility_test.go`, `go-mknoon/node/holepunch_negative_control_test.go`
- Current bridge/client seams: `go-mknoon/bridge/events.go`, `lib/core/bridge/go_bridge_client.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/core/debug/transport_metrics.dart`
- Current direct tests: `test/core/debug/transport_metrics_holepunch_test.dart`, `test/core/debug/transport_metrics_privacy_test.dart`, `test/core/services/p2p_service_inbound_transport_test.dart`, `test/core/services/p2p_service_transport_census_test.dart`, `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`

## Session Ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status | Execution verdict | Closure docs touched | Residual note |
|------|-------|----------------|--------------------|------------|----------------|-------------------|----------------------|---------------|
| DCUTR-001 | Go DCUtR observation and anti-false-upgrade controls | implementation-ready | `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md` | none | accepted | accepted | `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md` | host-only Go evidence only; DCUTR-004 owns final source-doc and decision-doc closure |
| DCUTR-002 | Dart bridge diagnostics and privacy-safe user-visible counters | implementation-ready | `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-002-plan.md` | DCUTR-001 | accepted | accepted | `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-002-plan.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md` | host Flutter and simulator transport-gate diagnostic/counter evidence only; DCUTR-003 relay-only/no-upgrade acceptance is closed separately; DCUTR-004 owns final source-doc, baseline, and decision-doc closure |
| DCUTR-003 | Relay-only delivery and recovery no-upgrade acceptance | implementation-ready | `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-003-plan.md` | DCUTR-001, DCUTR-002 | accepted_with_explicit_follow_up | accepted_with_explicit_follow_up | `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-003-plan.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md` | relay-only/no-upgrade acceptance closed; production mobile DCUtR remains unproven; simulator/CLI proof is not physical NAT traversal proof; repeated `run_transport_e2e.dart` E8 media metadata orchestrator failure remains for DCUTR-004 classification |
| DCUTR-004 | Baseline harvest, decision-doc closure, and residual classification | acceptance-only | `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-004-plan.md` | DCUTR-001, DCUTR-002, DCUTR-003 | accepted_with_explicit_follow_up | accepted_with_explicit_follow_up | `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-004-plan.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md` | source/baseline/index closure accepted for scoped evidence; production mobile DCUtR and valid real-device harvest remain evidence-gated; E8 media residual remains explicit |

## DCUTR-001 Closure Evidence

Recorded: 2026-05-29 23:28 CEST

- Closure verdict: `accepted` for DCUTR-001, with final source-doc and decision-doc closure explicitly deferred to DCUTR-004.
- Evidence verified: final execution verdict in `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md`; `go-mknoon/node/node.go`; `go-mknoon/node/holepunch_tracer.go`; `go-mknoon/node/holepunch_tracer_test.go`; `go-mknoon/node/transport_label_test.go`; `go-mknoon/node/holepunch_feasibility_test.go`; `go-mknoon/node/holepunch_negative_control_test.go`; `go-mknoon/bridge/events.go`; `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`.
- Tests accepted from the execution verdict: `cd go-mknoon && go test ./node -run 'TestHolePunchTracer|TestClassifyStreamTransport|TestHolePunchFeasibility|TestHolePunchNegativeControl'` passed, and `git diff --check` passed.
- Closure audit did not re-run tests or execute implementation work; it verified recorded evidence and scoped files only.
- Closed for this row: Go tracer observation and event contract, production-private reachability default, test-only forced-public feasibility seam, stale limited-state repair after tracer success, classifier mapping-vs-proof warning, loopback feasibility classification, and relay-only no-upgrade/no-thrash negative control.
- Residual-only: host-only Go evidence is observation/feasibility/negative-control evidence and does not prove production mobile DCUtR success.

## DCUTR-002 Closure Evidence

Recorded: 2026-05-29 23:53 CEST

- Closure verdict: `accepted` for DCUTR-002 only, with final source-doc, baseline, and architecture-decision closure explicitly deferred to DCUTR-004.
- Evidence verified: final execution verdict in `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-002-plan.md`; `lib/core/bridge/bridge.dart`; `lib/core/bridge/go_bridge_client.dart`; `lib/core/services/p2p_service_impl.dart`; `lib/core/debug/transport_metrics.dart`; `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`; `test/core/bridge/go_bridge_client_test.dart`; `test/core/debug/transport_metrics_holepunch_test.dart`; `test/core/debug/transport_metrics_privacy_test.dart`; `test/core/debug/transport_metrics_test.dart`; `test/core/services/p2p_service_inbound_transport_test.dart`; `test/core/services/p2p_service_transport_census_test.dart`; `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`; `go-mknoon/bridge/events.go`; `go-mknoon/node/holepunch_tracer.go`.
- Tests accepted from the execution verdict: `dart format --set-exit-if-changed lib/core/bridge/bridge.dart lib/core/bridge/go_bridge_client.dart lib/core/services/p2p_service_impl.dart test/core/bridge/go_bridge_client_test.dart test/core/debug/transport_metrics_privacy_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` passed with 0 files changed; `flutter test test/core/bridge/go_bridge_client_test.dart test/core/debug/transport_metrics_holepunch_test.dart test/core/debug/transport_metrics_privacy_test.dart test/core/debug/transport_metrics_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/core/services/p2p_service_transport_census_test.dart test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` passed; `git diff --check` passed; `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed after the initial unqualified `./scripts/run_test_gates.sh transport` attempt was blocked before tests by multiple connected devices.
- Closure audit did not re-run tests, gates, or implementation work; it verified recorded evidence and scoped files only.
- Closed for this row: Dart bridge forwarding of `holepunch:attempt`, `holepunch:success`, `holepunch:failure`, and `transport:upgraded`; allowlisted and sanitized transport diagnostic payloads; aggregate hole-punch attempt/success/failure and relay-to-direct upgrade counters; direct inference only from matching accepted upgrade evidence or true live connection evidence; missing inbound transport remains `unknown`; settings/debug aggregate diagnostics include direct, relay, wifi, inbox, unknown, hole-punch counts, and relay-to-direct upgrades without raw/full peer IDs, conversation IDs, raw multiaddrs, or message content.
- Accepted non-triggers: `./scripts/run_test_gates.sh completeness-check` was not required because no new test file or gate classification was introduced; `flutter test test/features/settings/presentation/screens/settings_wired_test.dart` was not required because Settings screen wiring was not changed.
- Residual-only: evidence remains Dart diagnostics/counter proof from host Flutter tests and a simulator transport gate. It does not prove production mobile DCUtR success, real NAT traversal, reachability policy, relay-server behavior, routing policy, WebRTC/TURN/STUN behavior, or final product/architecture closure.
- Still-open for later rows: DCUTR-003 relay-only/no-upgrade acceptance is now recorded separately below; DCUTR-004 owns final source-doc, baseline, and decision-doc closure.

## DCUTR-003 Closure Evidence

Recorded: 2026-05-30 CEST

- Closure verdict: `accepted_with_explicit_follow_up` for DCUTR-003 only. Relay-only/no-upgrade acceptance is closed, with final source-doc, baseline, and architecture-decision closure explicitly deferred to DCUTR-004.
- Evidence verified: final execution verdict in `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-003-plan.md`; `go-mknoon/node/holepunch_negative_control_test.go`; `go-mknoon/integration/watchdog_failover_test.go`; `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`.
- Tests accepted from the execution verdict: `cd go-mknoon && go test ./node -run 'TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash|TestHolePunchTracer|TestClassifyStreamTransport'` passed; `cd go-mknoon && go test -tags=integration ./integration -run 'TestSecondRelayAvailablePreventsWatchdogRestart|TestAllRelaysUnavailableEnterDegradedStateAndRecover|TestRendezvousAndInboxStillWorkAfterRelayRestart'` passed; `cd go-mknoon && go test -tags=integration ./integration -run 'TestRelayTwoNodesMessage|TestRelayCircuitRecoveryAfterDisconnect|TestRelayCircuitRecoveryPreservesPeerId|TestRelayRefreshRecoversWithoutHostReplacement'` passed; direct Flutter host tests passed; reliability-sim `1to1 --list` passed; reliability-sim `run_wifi_relay_fallback_smoke.dart` passed; `git diff --check` passed.
- Closure audit did not re-run Go, Flutter, or simulator tests and did not execute implementation work. It verified recorded evidence, inspected the scoped files, updated only this breakdown and the DCUTR-003 plan, and re-ran `git diff --check`, which passed.
- Closed for this row: strict relay-only delivery over a real limited circuit; receiver-observed relay transport/content for 1:1 delivery; exact zero hole-punch attempts and successes in the forced relay-only negative control; no `holepunch:success`; no `transport:upgraded`; stable target-peer connection count; relay failover/recovery without manufactured upgrade evidence.
- Accepted follow-up / residual-only: production mobile DCUtR success remains unproven; simulator/CLI evidence is relay/recovery liveness evidence, not physical NAT traversal proof; the repeated reliability-sim `run_transport_e2e.dart` E8 media metadata orchestrator failure remains for DCUTR-004 classification after Flutter reported `33/33 passed` and the orchestrator downloaded the 69-byte blob but produced `29/30 passed` with `messageSeen=false`, `attachmentReferenced=false`, and `blobInList=false`.
- Still-open for later rows: DCUTR-004 owns final source-doc, baseline, and decision-doc closure and must classify the production mobile DCUtR residual plus the E8 media metadata residual.
- Reopen rule: DCUTR-003 should reopen only on a real regression in forced relay-only delivery, limited-circuit proof, no-upgrade counters/events, target-peer connection-count stability, or relay-recovery no-upgrade behavior.

## DCUTR-004 Closure Evidence

Recorded: 2026-05-30 00:36 CEST

- Closure verdict: `accepted_with_explicit_follow_up` for DCUTR-004 doc-only execution.
- Evidence verified: final execution verdict in `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-004-plan.md`; stable closure wording in `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, and `Network-Arch/Transport-Reliability/00-INDEX.md`; scoped status for `Test-Flight-Improv/test-gate-definitions.md`; prior DCUTR-001/002/003 closure verdicts in this breakdown and their plans.
- Files changed by the DCUTR-004 execution verdict: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`, and `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-004-plan.md`.
- Closure audit updated only this breakdown and the DCUTR-004 plan. No stable-doc accuracy fix was needed.
- Tests accepted from the execution verdict: `git diff --check` passed; `./scripts/run_test_gates.sh completeness-check` was not run because `Test-Flight-Improv/test-gate-definitions.md` was untouched and no test/gate classification changed.
- Closure audit validation: `git diff --check` passed after closure edits.
- Prior behavior gates accepted and not rerun: DCUTR-001 focused Go node proof; DCUTR-002 direct Flutter diagnostics/counter proof and transport gate; DCUTR-003 focused Go node proof, Go integration proofs, direct Flutter host proof, reliability-sim `1to1 --list`, reliability-sim `run_wifi_relay_fallback_smoke.dart`, and prior `git diff --check`.
- Closed for this row: final stable-doc closure records accepted Go tracer/event contract, Dart aggregate diagnostics/counters, `unknown` inbound preservation, relay-only/no-upgrade acceptance, relay failover/recovery liveness without manufactured upgrades, unchanged production-private reachability, and the proof boundary between real DCUtR upgrades, ordinary relay delivery, LAN/pre-relay direct dials, simulator/CLI liveness, loopback feasibility, and classifier labels.
- Residual-only / accepted follow-up: production mobile relay-to-direct DCUtR success remains unproven and evidence-gated; no concrete repo-local real-device, discovery-enabled, debug-mode `baselineReport()`/decision-gate artifact was found; simulator/CLI proof remains liveness/recovery evidence rather than physical NAT traversal proof; the repeated `run_transport_e2e.dart` E8 media metadata result remains an external orchestrator residual after Flutter reported `33/33 passed`, the orchestrator downloaded the 69-byte blob, and the external proof produced `29/30 passed` with `messageSeen=false`, `attachmentReferenced=false`, and `blobInList=false`.
- Still-open for this row: none in the DCUTR-004 doc-only execution scope.
- Reopen rule: DCUTR-004 source/decision docs should reopen only if a stable doc overclaims production mobile DCUtR, a valid real-device harvest needs to update the baseline decision gate, or a concrete regression contradicts the accepted DCUTR-001/002/003 scoped evidence. The E8 residual should not reopen relay-only/no-upgrade acceptance unless later evidence ties it to that behavior.

## Final Program Verdict

Final program verdict: `accepted_with_explicit_follow_up`.

DCUTR-001, DCUTR-002, DCUTR-003, and DCUTR-004 are closed or accepted for their
scoped evidence contracts. The program is not a production mobile DCUtR success
claim: production mobile relay-to-direct DCUtR remains evidence-gated until a
valid real-device, discovery-enabled, debug-mode baseline harvest proves it.

Closed:

- Go hole-punch tracer event contract and anti-false-upgrade controls.
- Dart aggregate, privacy-safe diagnostics and relay-to-direct counters.
- Relay-only/no-upgrade delivery and relay recovery without false upgrade
  evidence.
- Source evidence doc, baseline decision gate, NAT/DCUtR tracking doc, and
  transport index now carry the accepted scoped evidence and proof boundaries.

Residual-only / follow-up:

- Capture a valid real-device baseline harvest before using NET-REL-02/03 to
  claim production mobile DCUtR success or reorder NET-REL workstreams.
- Keep simulator, CLI, loopback, LAN direct, reliability-sim, and classifier
  evidence limited to liveness, recovery, feasibility, safety, or mapping
  claims.
- Track the `run_transport_e2e.dart` E8 media metadata residual separately from
  DCUTR no-upgrade acceptance unless later evidence proves a behavioral link.

Still-open:

- None for the four-session DCUTR evidence rollout scope.

## Ordered Session Breakdown

### DCUTR-001 - Go DCUtR Observation And Anti-False-Upgrade Controls

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md`
- Exact scope: verify or complete the Go-side hole-punch observation contract: `holepunch.WithTracer` is installed without changing production reachability policy, attempts/successes/failures and `transport:upgraded` events are emitted, stale connection state is corrected after a real upgrade, a test-only public-reachability seam remains explicitly feasibility-only, and classifier tests distinguish stream-label mapping from real upgrade proof.
- Why it is its own session: this is the Go/libp2p proof seam. It must not be mixed with Dart UI/metrics or final product decisions because a green Go component test only proves protocol feasibility, not app-E2E upgrade behavior.
- Likely code-entry files: `go-mknoon/node/node.go`, `go-mknoon/node/holepunch_tracer.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/transport_label_test.go`, `go-mknoon/node/holepunch_tracer_test.go`, `go-mknoon/node/holepunch_feasibility_test.go`, `go-mknoon/node/holepunch_negative_control_test.go`.
- Likely direct tests/regressions: focused `go test ./node -run 'TestHolePunchTracer|TestClassifyStreamTransport|TestHolePunchFeasibility|TestHolePunchNegativeControl'`; broader `cd go-mknoon && go test ./node` if touched files affect shared node behavior. Feasibility tests may skip when loopback DCUtR does not materialize and must not be treated as production app evidence.
- Likely named gates: no Flutter named gate. Use Go node tests and `git diff --check`.
- Matrix/closure docs to update when done: defer final source-doc closure to DCUTR-004. Update `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md` only if the current Go behavior differs from the doc.
- Dependency on earlier sessions: none.

### DCUTR-002 - Dart Bridge Diagnostics And Privacy-Safe User-Visible Counters

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-002-plan.md`
- Exact scope: verify or complete the bridge-to-Dart diagnostic flow for `holepunch:attempt`, `holepunch:success`, `holepunch:failure`, and `transport:upgraded`; record exact aggregate counts in `TransportMetrics`; keep missing inbound transport as `unknown` unless true connection inference exists; ensure settings/debug diagnostics distinguish direct, relay, wifi, inbox, unknown, hole-punch counts, and relay-to-direct upgrades without exposing message content, raw peer IDs, conversation IDs, or multiaddrs.
- Why it is its own session: this is the client-visible evidence seam. It consumes Go events but has different tests, privacy constraints, and Flutter named-gate triggers from the Go tracer itself.
- Likely code-entry files: `lib/core/bridge/go_bridge_client.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/core/debug/transport_metrics.dart`, `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`, `lib/features/settings/presentation/screens/settings_wired.dart`.
- Likely direct tests/regressions: `flutter test test/core/debug/transport_metrics_holepunch_test.dart test/core/debug/transport_metrics_privacy_test.dart test/core/debug/transport_metrics_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/core/services/p2p_service_transport_census_test.dart test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`; add or refresh a bridge-boundary test if planning finds the real `GoBridgeClient` decode path is not covered.
- Likely named gates: direct Flutter tests first. Run `./scripts/run_test_gates.sh transport` if bridge, P2P service, startup/resume, or settings wiring changes. Run `./scripts/run_test_gates.sh completeness-check` if new integration/cross-feature tests are added or gate docs change.
- Matrix/closure docs to update when done: defer final source-doc closure to DCUTR-004. Update `Test-Flight-Improv/test-gate-definitions.md` only for new high-value tests that need explicit classification.
- Dependency on earlier sessions: DCUTR-001 for event names and Go payload shape.

### DCUTR-003 - Relay-Only Delivery And Recovery No-Upgrade Acceptance

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-003-plan.md`
- Exact scope: prove the dominant relay-only case remains a valid successful outcome and does not emit false direct-upgrade evidence. Keep or add acceptance around real limited circuit connections, zero hole-punch success, zero/bounded attempts where appropriate, no `transport:upgraded` events, no connection-count thrash, successful relay-backed 1:1 delivery, and relay-drop/recovery behavior that does not manufacture a DCUtR upgrade.
- Why it is its own session: relay-only correctness is the user-visible safety contract for NAT conditions that cannot be punched. It depends on the tracer and client counters, but it is a different acceptance shape from unit tracer correctness or settings diagnostics.
- Likely code-entry files: `go-mknoon/node/holepunch_negative_control_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/integration/relay_test.go`, `go-mknoon/integration/watchdog_failover_test.go`, `go-mknoon/node/relay_session.go`, `integration_test/transport_e2e_test.dart`, `integration_test/wifi_relay_fallback_smoke_test.dart`, `test/integration/relay_down_degradation_integration_test.dart`.
- Likely direct tests/regressions: focused Go negative-control and relay-session tests; `go test -tags=integration ./integration/...` when real relay integration is in scope and environment allows it; direct Flutter relay-degradation or transport E2E tests only when the changed seam crosses into app wiring.
- Likely named gates: `./scripts/run_test_gates.sh transport` for bridge/resume/reconnect/transport fallback changes; `./scripts/run_test_gates.sh 1to1` if shared 1:1 send/retry behavior changes. Go integration tests may skip when external relay fixtures are unavailable and must be reported as such.
- Matrix/closure docs to update when done: defer final source-doc closure to DCUTR-004. Update `Test-Flight-Improv/test-gate-definitions.md` only if new integration or orchestration tests are introduced.
- Dependency on earlier sessions: DCUTR-001 for trustworthy no-upgrade counters; DCUTR-002 if app-visible metrics or diagnostics are asserted.

### DCUTR-004 - Baseline Harvest, Decision-Doc Closure, And Residual Classification

- Session classification: acceptance-only
- Intended plan file: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-004-plan.md`
- Exact scope: run the acceptance/documentation pass after the proof seams land. Update the source doc, NET-REL-02 tracking doc, baseline decision gate, and transport reliability index with exact evidence, remaining residuals, and any valid harvest results. If a real-device, discovery-enabled, debug-mode harvest is unavailable, record that as an explicit residual/blocker and do not make a DCUtR routing-policy, reachability, WebRTC, TURN, or relay-architecture decision.
- Why it is its own session: it validates multiple previous slices and owns the closure narrative. Combining it with implementation would invite stale evidence and overclaiming from loopback feasibility tests or simulator transport runs.
- Likely code-entry files: docs first: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`, `Test-Flight-Improv/test-gate-definitions.md` only if test classification changed.
- Likely direct tests/regressions: re-run the focused tests from DCUTR-001 through DCUTR-003 that changed; `cd go-mknoon && go test ./node`; relevant direct Flutter metrics/bridge tests; `./scripts/run_test_gates.sh transport`; `./scripts/run_test_gates.sh 1to1` if 1:1 send/retry changed; `./scripts/run_test_gates.sh completeness-check` if gate docs change; `git diff --check`.
- Likely named gates: Startup / Transport, 1:1 Reliability as triggered, completeness-check when docs/gates change, plus Go node/integration tests.
- Matrix/closure docs to update when done: primary closure doc `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`; existing decision/matrix docs `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, and `Network-Arch/Transport-Reliability/00-INDEX.md`. Do not create a new matrix doc unless DCUTR-004 proves no stable existing doc can hold the evidence.
- Dependency on earlier sessions: DCUTR-001, DCUTR-002, DCUTR-003.

## Why This Is Not Fewer Sessions

The minimum safe split is four sessions because the source doc spans different proof boundaries:

- Go/libp2p observation can prove tracer correctness and protocol feasibility, but not app-visible diagnostics.
- Dart bridge and settings diagnostics must separately prove aggregate, privacy-safe user-visible counters and unknown-label behavior.
- Relay-only and recovery acceptance is the dominant real mobile case and must prove successful relay delivery without false DCUtR upgrade evidence.
- Final closure needs to reconcile evidence, baseline-harvest limits, and decision docs without changing routing policy by implication.

Merging these would mix Go and Flutter gates, hide the feasibility-vs-production distinction, or make final docs depend on implementation-time assumptions.

## Why This Is Not More Sessions

The source doc lists many test cases, but several are already grouped by the same verification seam:

- Hole-punch attempts, successes, failures, upgrade events, and stale connection correction are one Go tracer contract.
- Per-stream direct/relay labels and mixed-connection labeling are part of the same Go transport-proof contract.
- `TransportMetrics`, inbound `unknown`, privacy-safe baseline text, and settings display all belong to the same Dart diagnostics contract.
- Relay-only negative controls and relay-recovery behavior share the same "relay is a valid steady state" acceptance bar.

Splitting every assertion into its own plan would create bookkeeping and encourage downstream agents to invent NAT emulation or product scope that the source doc explicitly excludes.

## Regression And Gate Contract

`Test-Flight-Improv/14-regression-test-strategy.md` applies as follows:

- Use direct, focused tests first for each changed seam.
- Run named gates only when the touched code falls under their trigger rules.
- Do not widen frozen gate lists casually; classify new high-value integration/cross-feature tests in `Test-Flight-Improv/test-gate-definitions.md`.
- Do not hide red or skipped tests by omission. Report environment skips, especially real-relay or real-device harvest constraints.

`Test-Flight-Improv/test-gate-definitions.md` applies as follows:

- DCUTR-001 uses Go node tests and `git diff --check`, not Flutter named gates.
- DCUTR-002 uses direct Flutter metrics/bridge/settings tests; run Startup / Transport if bridge/P2P/settings wiring changes.
- DCUTR-003 uses Go relay/negative-control tests and Startup / Transport or 1:1 Reliability only when app transport or 1:1 send seams change.
- DCUTR-004 runs the combined acceptance gates required by the landed code and completeness-check when gate docs change.

## Matrix Update Contract

Use existing stable docs; do not invent a new matrix during implementation.

- Primary closure doc: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`
- Baseline/decision doc: `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`
- Architecture tracking docs: `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`
- Gate/matrix source: `Test-Flight-Improv/test-gate-definitions.md`
- Closure owner: DCUTR-004
- Earlier sessions should only update gate docs if they add tests that need immediate classification; otherwise they should leave final source-doc and decision wording to DCUTR-004.

## Downstream Execution Path

Each session should next go through:

| Session id | Next planning | Execution and QA | Closure |
|------|---------------|------------------|---------|
| DCUTR-001 | `$implementation-plan-orchestrator` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |
| DCUTR-002 | `$implementation-plan-orchestrator` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |
| DCUTR-003 | `$implementation-plan-orchestrator` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |
| DCUTR-004 | `$implementation-plan-orchestrator` | `$implementation-execution-qa-orchestrator` for acceptance/gate/doc updates only | `$implementation-closure-audit-orchestrator` |

## Structural Blockers Remaining

None for decomposition.

DCUTR-004 is acceptance-only and may be evidence-limited if no real-device, discovery-enabled, debug-mode harvest is available. That is not a decomposition blocker; it is a downstream acceptance condition that must be recorded explicitly rather than papered over with simulator or loopback evidence.

## Accepted Differences Intentionally Left Unchanged

- No production routing-policy change, `ForceReachabilityPrivate` relaxation, AutoNAT policy change, WebRTC/TURN/STUN work, relay-server traversal feature, or explicit hole-punch trigger is included.
- A loopback or forced-public DCUtR success is protocol-feasibility evidence, not production app-E2E evidence.
- A LAN/pre-relay direct dial is direct delivery, not a relay-to-direct DCUtR upgrade unless a real upgrade event occurred.
- Relay delivery remains a successful and expected steady state for cellular, symmetric-NAT, or otherwise unpunchable peers.
- Group transport-family census remains bounded by the NET-REL-04/TOM-004 decision; do not infer direct/relay/wifi group labels unless a trustworthy signal exists.
- Standard simulator transport runs must not be treated as proof of physical LAN discovery or favorable NAT traversal.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`
- `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`
- `Network-Arch/Transport-Reliability/00-INDEX.md`
- `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`
- `Network-Arch/Transport-Reliability/03-relay-springboard.md`
- `Network-Arch/Transport-Reliability/04-transport-observability.md`
- `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`
- `go-mknoon/node/node.go`
- `go-mknoon/node/holepunch_tracer.go`
- `go-mknoon/node/holepunch_tracer_test.go`
- `go-mknoon/node/holepunch_feasibility_test.go`
- `go-mknoon/node/holepunch_negative_control_test.go`
- `go-mknoon/node/transport_label_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/bridge/events.go`
- `go-mknoon/integration/relay_test.go`
- `go-mknoon/integration/watchdog_failover_test.go`
- `lib/core/bridge/go_bridge_client.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/debug/transport_metrics.dart`
- `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
- `test/core/debug/transport_metrics_holepunch_test.dart`
- `test/core/debug/transport_metrics_privacy_test.dart`
- `test/core/debug/transport_metrics_test.dart`
- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/core/services/p2p_service_transport_census_test.dart`
- `test/core/services/p2p_service_transport_latency_test.dart`
- `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/wifi_relay_fallback_smoke_test.dart`

## Why The Decomposition Is Safe To Send Into Downstream Planning/Execution

- Every intended plan path is doc-scoped and non-colliding.
- Each session owns one meaningful proof seam with its own direct tests and gate triggers.
- Existing NET-REL-04 closure docs are reused instead of creating a new metrics matrix.
- Evidence-gated claims are isolated so downstream agents do not turn loopback DCUtR, LAN direct dial, or simulator delivery into production NAT-traversal proof.
- Closure and decision-doc updates are assigned to DCUTR-004, so implementation sessions can land focused evidence without prematurely changing the product or architecture policy.
