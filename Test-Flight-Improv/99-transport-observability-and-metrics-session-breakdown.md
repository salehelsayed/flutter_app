Status: reusable-session-breakdown

# 99 Transport Observability and Metrics Session Breakdown

## Decomposition Progress

| Phase | Files inspected | Current next action |
|------|-----------------|---------------------|
| Initial intake | `Test-Flight-Improv/99-transport-observability-and-metrics.md`; `Test-Flight-Improv/14-regression-test-strategy.md`; `Test-Flight-Improv/test-gate-definitions.md`; `Test-Flight-Improv/` and `Network-Arch/` markdown search results; `git status --short` | Continue Evidence Collector against code, direct tests, relay metrics, and transport reliability docs. |
| Evidence Collector | `lib/core/debug/transport_metrics.dart`; `lib/core/services/p2p_service_impl.dart`; `lib/features/conversation/application/send_chat_message_use_case.dart`; `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`; `go-relay-server/metrics.go`; direct transport tests; transport E2E docs | Map closure target and decide split around independently verifiable seams. |
| Closure Mapper | Source doc scope/non-goals; NET-REL-04/06 docs; named gate definitions; group send and local discovery seams | Split sessions by code owner, gate family, and closure bar. |
| Session Splitter | Dart diagnostics, LAN discovery, relay server, group messaging, and final acceptance evidence | Run reviewer and arbiter pass for hidden coupling or missing gates. |
| Reviewer and Arbiter | Proposed five-session set, gate contracts, matrix ownership, accepted non-goals | No structural blockers. Send sessions downstream in order, refreshing later plans against landed code. |

## Recommended Plan Count

Recommended plan count: 5

Create five session plans, all doc-scoped:

- `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-001-plan.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-002-plan.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-003-plan.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-004-plan.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-005-plan.md`

## Decomposition Artifact

- Artifact path: `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/99-transport-observability-and-metrics.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code before execution.
- Scope rule: do not execute implementation from this breakdown. Each session must go through planning, execution/QA, and closure before the next dependent session is treated as ready.

## Overall Closure Bar

Transport diagnostics are trustworthy enough for TestFlight reliability work when the app can show a session-scoped, aggregate-only baseline for direct, relay, wifi, inbox, failed-rung, unknown, latency, and LAN availability states; send-path flow events no longer leak message-derived preview text; relay Prometheus metrics have focused contract tests; group-message transport evidence is either implemented from existing safe signals or explicitly closed as unsupported without protocol/product expansion; and final acceptance evidence does not claim LAN success from the standard simulator setup.

## Source Of Truth

- Product intent: `Test-Flight-Improv/99-transport-observability-and-metrics.md`
- Regression model: `Test-Flight-Improv/14-regression-test-strategy.md`
- Gate execution source: `Test-Flight-Improv/test-gate-definitions.md`
- Transport observability reference: `Network-Arch/Transport-Reliability/04-transport-observability.md`
- Transport test doctrine and simulator limits: `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`
- Existing Dart diagnostics: `lib/core/debug/transport_metrics.dart`
- Existing production transport hooks: `lib/core/services/p2p_service_impl.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`, `lib/main.dart`
- Existing settings surface: `lib/features/settings/presentation/screens/settings_wired.dart`, `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
- Existing local discovery seam: `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/local_discovery/local_discovery_service.dart`
- Existing relay metrics: `go-relay-server/metrics.go`, `go-relay-server/main.go`, `go-relay-server/inbox.go`
- Existing direct tests: `test/core/debug/transport_metrics_test.dart`, `test/core/debug/transport_metrics_privacy_test.dart`, `test/core/services/p2p_service_inbound_transport_test.dart`, `test/core/services/p2p_service_transport_census_test.dart`, `test/core/services/p2p_service_transport_latency_test.dart`, `test/core/utils/flow_event_emitter_test.dart`
- Existing integration limits: `integration_test/transport_e2e_test.dart`, `integration_test/wifi_relay_fallback_smoke_test.dart`, `integration_test/wifi_transport_test.dart`

## Run Mode Snapshot

- Active mode: standard.
- Degraded local continuation explicitly allowed: no.
- Source proposal, matrix, or closure doc path: `Test-Flight-Improv/99-transport-observability-and-metrics.md`.
- Source row/status vocabulary used by this doc: proposal sections and gap bullets rather than a row-status matrix; closure evidence must be concrete code, test, and doc evidence and must not overclaim simulator LAN proof.
- Overall closure bar: transport diagnostics are trustworthy enough for TestFlight reliability work when the app can show a session-scoped, aggregate-only baseline for direct, relay, wifi, inbox, failed-rung, unknown, latency, and LAN availability states; send-path flow events no longer leak message-derived preview text; relay Prometheus metrics have focused contract tests; group-message transport evidence is either implemented from existing safe signals or explicitly closed as unsupported without protocol/product expansion; and final acceptance evidence does not claim LAN success from the standard simulator setup.
- Final verdict policy: persist exactly one of `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`; use `still_open` if any required session remains blocked, any required closure result is missing, or the overall closure bar is not met.

## Session Ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
|------|-------|----------------|--------------------|------------|----------------|
| TOM-001 | Dart diagnostics privacy and settings readout proof | implementation-ready | `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-001-plan.md` | none | accepted |
| TOM-002 | LAN availability production snapshot wiring | implementation-ready | `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-002-plan.md` | TOM-001 refresh if diagnostics/card APIs change | accepted |
| TOM-003 | Relay Prometheus metrics contract tests | implementation-ready | `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-003-plan.md` | none | accepted |
| TOM-004 | Group transport-census evidence boundary | evidence-gated | `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-004-plan.md` | TOM-001, TOM-002 | accepted |
| TOM-005 | Cross-seam acceptance and closure update | acceptance-only | `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-005-plan.md` | TOM-001, TOM-002, TOM-003, TOM-004 | accepted |

## Ordered Session Breakdown

### TOM-001 - Dart Diagnostics Privacy And Settings Readout Proof

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-001-plan.md`
- Exact scope: remove or replace message-derived `textPreview` fields from transport-adjacent send flow events; add a direct send-path privacy regression; add a focused settings diagnostics card or settings-wired smoke proving the visible card reads aggregate transport mix, rung counts, latency, LAN line, and baseline report after metrics change and refresh.
- Why it is its own session: it is the smallest user-visible Dart diagnostics hardening slice. It touches privacy and the settings readout, but both close the same local diagnostics surface and can be verified with host-side Flutter tests before broader LAN, relay, or group work.
- Likely code-entry files: `lib/features/conversation/application/send_chat_message_use_case.dart`, `lib/core/utils/flow_event_emitter.dart` only if sanitizer coverage needs a narrow addition, `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`, `lib/features/settings/presentation/screens/settings_wired.dart`.
- Likely direct tests/regressions: `test/core/debug/transport_metrics_privacy_test.dart`, `test/core/utils/flow_event_emitter_test.dart`, `test/features/conversation/application/send_chat_message_use_case_test.dart`, a new or existing focused settings widget/screen test for `SettingsTransportDiagnosticsCard`.
- Likely named gates: direct Flutter tests first; `./scripts/run_test_gates.sh 1to1` when the send use case changes; `./scripts/run_test_gates.sh baseline` if settings or app wiring changes beyond the card.
- Matrix/closure docs to update when done: classify any newly added integration/cross-feature test in `Test-Flight-Improv/test-gate-definitions.md` if required. Defer final source-doc closure wording to TOM-005.
- Dependency on earlier sessions: none.

### TOM-002 - LAN Availability Production Snapshot Wiring

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-002-plan.md`
- Exact scope: wire `TransportMetrics.updateLanAvailability` to production local-discovery state so diagnostics distinguish disabled/inactive discovery, active zero-peer discovery, and active nonzero discovered-peer snapshots without storing peer IDs, hosts, ports, or multiaddrs.
- Why it is its own session: LAN availability has a different source seam from the transport counters. It depends on `LocalP2PService.discoveredPeersStream` and lifecycle start/stop/restart behavior, and it must not make false simulator LAN claims.
- Likely code-entry files: `lib/core/services/p2p_service_impl.dart`, `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/local_discovery/local_discovery_service.dart`, `lib/core/local_discovery/disabled_local_discovery_service.dart`, `lib/main.dart` only if construction or dependency flow needs a narrow adjustment.
- Likely direct tests/regressions: `test/core/debug/transport_metrics_test.dart`, `test/core/services/p2p_service_inbound_transport_test.dart` or a new focused `p2p_service` LAN metrics test, `test/core/local_discovery/local_p2p_service_test.dart`, `test/core/local_discovery/fake_local_p2p_service.dart` as the fake seam.
- Likely named gates: direct local-discovery and core-service tests; `./scripts/run_test_gates.sh transport` for transport/lifecycle confidence. Do not treat standard simulator runs as proof of true LAN success.
- Matrix/closure docs to update when done: TOM-005 owns source-doc closure. Update `Test-Flight-Improv/test-gate-definitions.md` only if a new high-value integration or orchestration test is added and needs classification.
- Dependency on earlier sessions: refresh against TOM-001 if settings diagnostics card APIs or report rendering changed.

### TOM-003 - Relay Prometheus Metrics Contract Tests

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-003-plan.md`
- Exact scope: add dedicated relay-side metrics contract tests for existing aggregate Prometheus counters/gauges/histograms and the live `/metrics` handler contract, using deltas around global `promauto` metrics rather than absolute values.
- Why it is its own session: this is Go relay-server work with a separate toolchain and verification path. It does not require Flutter changes and should not be bundled with client diagnostics.
- Likely code-entry files: `go-relay-server/metrics.go`, `go-relay-server/main.go`, `go-relay-server/inbox.go`, likely new `go-relay-server/metrics_test.go`; test helper placement should follow existing relay-server test style.
- Likely direct tests/regressions: `cd go-relay-server && go test ./...`; focused tests around `relay_inbox_stored_total`, connection active/total counters if a deterministic hook exists, `relay_stream_duration_seconds{proto,result}`, and negative controls for unchanged metrics.
- Likely named gates: no Flutter named gate. Run relay Go tests and `git diff --check`; final TOM-005 can include broader Go/Dart gates if earlier sessions touch both sides.
- Matrix/closure docs to update when done: TOM-005 owns source-doc closure. `Test-Flight-Improv/test-gate-definitions.md` usually does not need a change for Go-only unit tests unless gate documentation is expanded.
- Dependency on earlier sessions: none.

### TOM-004 - Group Transport-Census Evidence Boundary

- Session classification: evidence-gated
- Intended plan file: `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-004-plan.md`
- Exact scope: determine and implement only the group diagnostics contract that current architecture can prove without routing, protocol, relay privacy, or analytics changes. If existing group send/drain signals can safely feed aggregate `TransportMetrics` buckets or a clearly named group-specific rung, add the narrow production hook and exact-count tests. If the current bridge/native result lacks a safe direct/relay/wifi/inbox signal, record that as an accepted difference and do not invent labels.
- Why it is its own session: group messaging uses a different send/receive stack, gate family, and privacy surface from 1:1 chat. The repo currently has group `transportPeerId` identity fields and publish/inbox fanout evidence, but no explicit `TransportMetrics` injection in group send paths; planning must separate real evidence from speculative labels.
- Likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, group retry use cases if they are already the terminal send owner, and only then shared `TransportMetrics` wiring if the contract is safe.
- Likely direct tests/regressions: focused group application tests such as `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`; add exact-count or accepted-difference tests only after evidence proves the available signal.
- Likely named gates: direct group application tests first; `./scripts/run_test_gates.sh groups` when group send, drain, retry, or listener code changes.
- Matrix/closure docs to update when done: TOM-005 owns final source-doc closure. If new group integration tests are added, classify them in `Test-Flight-Improv/test-gate-definitions.md`.
- Dependency on earlier sessions: refresh after TOM-001/TOM-002 so the client diagnostics contract and LAN terminology are stable.

### TOM-005 - Cross-Seam Acceptance And Closure Update

- Session classification: acceptance-only
- Intended plan file: `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-005-plan.md`
- Exact scope: run the integrated acceptance pass across the Dart diagnostics, LAN snapshot, Go relay metrics, and group evidence outcomes; update the source doc and gate/matrix docs with exact closure evidence, residual risks, and simulator LAN limitations. Do not add new product scope unless a prior session left an explicit blocker that planning refresh accepts.
- Why it is its own session: it validates multiple earlier slices and owns the documentation closure. Combining it with implementation would invite stale evidence and make it easy to overclaim LAN or relay/client cross-check results.
- Likely code-entry files: docs only unless a prior session left a narrowly planned acceptance test; `Test-Flight-Improv/99-transport-observability-and-metrics.md`, `Test-Flight-Improv/test-gate-definitions.md`, and this breakdown ledger if downstream orchestration records status here.
- Likely direct tests/regressions: re-run the focused tests added or touched by TOM-001 through TOM-004; `cd go-relay-server && go test ./...`; `./scripts/run_test_gates.sh 1to1`; `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh transport`; `./scripts/run_test_gates.sh completeness-check` when gate docs change. Device-backed LAN evidence is optional/manual unless a credible physical-device or discovery-enabled variant is available.
- Likely named gates: 1:1 Reliability, Group Messaging, Startup / Transport, completeness-check, plus relay Go tests.
- Matrix/closure docs to update when done: `Test-Flight-Improv/99-transport-observability-and-metrics.md` and `Test-Flight-Improv/test-gate-definitions.md`. Do not create a new matrix doc unless TOM-005 proves there is no stable existing doc to extend.
- Dependency on earlier sessions: TOM-001, TOM-002, TOM-003, TOM-004.

## Why This Is Not Fewer Sessions

The minimum safe split is five sessions because the remaining work spans different owners and proof shapes:

- Dart diagnostics privacy/settings work is host-testable and should land before broader acceptance.
- LAN availability has a lifecycle/local-discovery seam and cannot share the same proof as send-path privacy.
- Relay Prometheus metrics are Go relay-server work with global metric delta constraints and a separate gate.
- Group diagnostics are evidence-gated because current group fields are not the same as transport-type labels.
- Final acceptance must validate all prior slices and update docs without overclaiming simulator LAN behavior.

Merging any of these would either mix Go and Flutter gates, hide the group evidence uncertainty, or couple final closure to implementation-time assumptions.

## Why This Is Not More Sessions

The source doc contains many test cases, but several are already partially covered by existing direct tests:

- `TransportMetrics` canonical buckets, rung counts, latency stats, and baseline report are already covered by `test/core/debug/transport_metrics_test.dart`.
- Unknown inbound transport, explicit relay, direct inference, and local wifi receive are already covered by `test/core/services/p2p_service_inbound_transport_test.dart`.
- Send-path exact census and failed-send non-counting are already covered by `test/core/services/p2p_service_transport_census_test.dart`.
- Latency bucket separation is already covered by `test/core/services/p2p_service_transport_latency_test.dart`.
- Baseline-report privacy and sanitizer negative controls are already partially covered by `test/core/debug/transport_metrics_privacy_test.dart` and `test/core/utils/flow_event_emitter_test.dart`.

Splitting each remaining assertion into its own plan would create bookkeeping rather than independent verified states. The five sessions above group by meaningful seam and gate value.

## Regression And Gate Contract

`Test-Flight-Improv/14-regression-test-strategy.md` applies as follows:

- Use direct, focused tests first for each changed seam.
- Run named gates when shared transport, 1:1 send, group send, settings/app wiring, or startup/transport code changes.
- Do not widen frozen gates casually; classify new high-value tests in `Test-Flight-Improv/test-gate-definitions.md` when they sit outside implicit direct-suite buckets.
- Do not hide red tests by omission. Known completeness-check issues must remain documented rather than erased.

`Test-Flight-Improv/test-gate-definitions.md` applies as follows:

- TOM-001 should use the 1:1 Reliability Gate when `send_chat_message_use_case.dart` changes.
- TOM-002 should use the Startup / Transport Gate when `P2PServiceImpl`, local discovery, or startup/resume LAN wiring changes.
- TOM-003 should use relay Go tests, not a Flutter named gate.
- TOM-004 should use the Group Messaging Gate when group send, drain, retry, or listener behavior changes.
- TOM-005 should run the combined acceptance gates needed by the landed code and update completeness classification when new tests are introduced.

## Matrix Update Contract

Use existing stable docs; do not invent a new matrix during implementation.

- Primary closure doc: `Test-Flight-Improv/99-transport-observability-and-metrics.md`
- Gate/matrix source: `Test-Flight-Improv/test-gate-definitions.md`
- Reference-only unless facts change: `Network-Arch/Transport-Reliability/04-transport-observability.md`, `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`
- Closure owner: TOM-005
- Earlier sessions should only update gate docs if they add tests that require immediate classification; otherwise they should leave final wording to TOM-005.

## Downstream Execution Path

Each session should next go through:

| Session id | Next planning | Execution and QA | Closure |
|------|---------------|------------------|---------|
| TOM-001 | `$implementation-plan-orchestrator` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |
| TOM-002 | `$implementation-plan-orchestrator` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |
| TOM-003 | `$implementation-plan-orchestrator` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |
| TOM-004 | `$implementation-plan-orchestrator` with evidence-gated scope first | `$implementation-execution-qa-orchestrator` only after the plan fixes the safe group contract | `$implementation-closure-audit-orchestrator` |
| TOM-005 | `$implementation-plan-orchestrator` | `$implementation-execution-qa-orchestrator` for acceptance/gate/doc updates only | `$implementation-closure-audit-orchestrator` |

## Structural Blockers Remaining

None for decomposition.

TOM-004 is intentionally evidence-gated, not structurally blocked. Its downstream plan must decide whether current group send/drain signals can support an aggregate diagnostics claim without inventing a transport label.

## Accepted Differences Intentionally Left Unchanged

- No routing-policy, NAT traversal, relay protocol, delivery semantics, or hole-punch implementation is included.
- No analytics exporter, dashboard, opt-in telemetry collector, or telemetry policy decision is included.
- No relay 1:1-vs-group traffic classification is required unless a later plan proves a privacy-safe existing signal.
- Standard simulator transport runs must not be treated as proof of true LAN discovery or wifi transport success.
- Existing client metric class, basic census, inbound unknown handling, latency buckets, and aggregate baseline report are treated as already partially covered; this breakdown targets the remaining gaps.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/99-transport-observability-and-metrics.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Network-Arch/Transport-Reliability/04-transport-observability.md`
- `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`
- `lib/core/debug/transport_metrics.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/local_discovery/local_discovery_service.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `go-relay-server/metrics.go`
- `go-relay-server/main.go`
- `go-relay-server/inbox.go`
- `test/core/debug/transport_metrics_test.dart`
- `test/core/debug/transport_metrics_privacy_test.dart`
- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/core/services/p2p_service_transport_census_test.dart`
- `test/core/services/p2p_service_transport_latency_test.dart`
- `test/core/utils/flow_event_emitter_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/wifi_relay_fallback_smoke_test.dart`
- `integration_test/wifi_transport_test.dart`

## Why The Decomposition Is Safe To Send Into Downstream Planning/Execution

- Every intended plan path is doc-scoped and non-colliding.
- Each session has a narrow code owner, test family, and named-gate contract.
- Existing coverage is reused instead of being replanned as duplicate sessions.
- Evidence-gated group work is isolated so downstream agents do not hallucinate a transport signal the current architecture may not expose.
- Closure and matrix updates are assigned to TOM-005, so implementation sessions can land focused changes without rewriting the rollout doc prematurely.

## Final Program Verdict

Final verdict: closed

Completed sessions:

- TOM-001 accepted: Dart send-path privacy and settings diagnostics readout evidence landed.
- TOM-002 accepted: production LAN availability snapshots are wired to local discovery lifecycle and count-only peer snapshots.
- TOM-003 accepted: relay Prometheus metrics contract tests landed.
- TOM-004 accepted: group diagnostics are explicitly bounded to aggregate fanout/custody evidence; no speculative transport-family metrics hook was added.
- TOM-005 accepted: source-doc closure and final verification evidence landed.

Accepted residuals are recorded in `Test-Flight-Improv/99-transport-observability-and-metrics.md`: standard simulator runs are not proof of physical LAN success, and group direct/relay/wifi transport-family census remains out of scope until a trustworthy native/bridge signal exists.
