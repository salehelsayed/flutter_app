Status: final-program-verdict-residual_only

# 101 Relay Springboard Direct Escalation Session Breakdown

Final program verdict: residual_only.
Recorded: 2026-05-30 09:33 CEST.

## Decomposition Progress

| Phase | Source doc | Intended breakdown path | Files inspected | Current next action |
|---|---|---|---|---|
| Evidence Collector | `Test-Flight-Improv/101-relay-springboard-direct-escalation.md` | `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-breakdown.md` | Source doc, `14-regression-test-strategy.md`, `test-gate-definitions.md`, NET-REL-02/03/06/07 docs, NET-REL-04 decision gate, DCUTR-004 closure docs, Go node seams, focused Go/Dart tests, `git status --short` | Map closure target and split by evidence gate, Go policy, Go send integration, and closure. |
| Closure Mapper | same | same | Source scope/non-goals, NET-REL-02 accepted evidence, NET-REL-03 tracking doc, `Network-Arch/Transport-Reliability/00-INDEX.md`, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md` | Keep reachability/routing/WebRTC/TURN/relay-server architecture decisions out of this decomposition unless the evidence gate later unblocks them. |
| Session Splitter | same | same | Current `go-mknoon/node/node.go`, `holepunch_tracer.go`, `relay_session.go`, `pubsub.go`, Flutter diagnostics seams, and direct tests listed below | Split one currently runnable evidence/decision session from blocked implementation and closure sessions. |
| Reviewer | same | same | Proposed 4-session set, plan-file naming, gate triggers, matrix ownership, accepted non-goals | Reviewer verdict: sufficient. No sessions should merge; no required split. Implementation sessions must remain prerequisite-blocked. |
| Arbiter | same | same | Review findings and mandatory output requirements | No decomposition structural blocker. The intentional product/evidence blocker is recorded as a prerequisite on RSD-002/RSD-003/RSD-004. |

## Recommended Plan Count

Recommended plan count: 4

Create four doc-scoped session plans:

- `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-001-plan.md`
- `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-002-plan.md`
- `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-003-plan.md`
- `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-004-plan.md`

Only RSD-001 is currently runnable. RSD-002 and RSD-003 are prerequisite-blocked because the source doc and NET-REL-02/04 evidence state that production mobile relay-to-direct success is still unproven and no reachability or routing policy decision has been made. RSD-004 is closure-only and depends on the earlier verdicts.

## Decomposition Artifact

- Artifact path: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code, current dirty-worktree state, and any new baseline-harvest evidence before execution.
- Scope rule: do not execute implementation from this breakdown. Each session must go through `$implementation-plan-orchestrator`, `$implementation-execution-qa-orchestrator`, and `$implementation-closure-audit-orchestrator` before dependent sessions are treated as ready.

## Run Mode Snapshot

- Active mode: standard.
- Degraded local continuation explicitly allowed: no.
- Source proposal path: `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`.
- Source status vocabulary: session-ledger statuses `pending`, `accepted`, `accepted_with_explicit_follow_up`, `blocked`, `prerequisite-blocked`, `skipped_due_to_dependency`, and final program verdicts `closed`, `accepted_with_explicit_follow_up`, `residual_only`, `still_open`. The source doc is not a row-owned Open/Closed matrix.
- Overall closure bar: represent 1:1 relay springboard behavior honestly; keep relay delivery successful and truthful; do not report direct unless a non-circuit, non-limited connection or accepted relay->direct upgrade exists; gate any direct-escalation implementation on a valid NET-REL-02/04 baseline decision; preserve group direct-first, relay reservation health, and 1:1 relay delivery; update source, NET-REL tracking, baseline decision, and gate docs with exact evidence.
- Final verdict policy: `closed` only if the evidence gate and closure docs fully satisfy the closure bar; `accepted_with_explicit_follow_up` only for non-blocking residuals after the closure bar is met; `residual_only` only if no broad program should reopen and a narrow residual remains; `still_open` if any required session remains blocked, evidence is missing, or the closure bar is unmet.

## Controller Progress

- 2026-05-30 00:00 Europe/Berlin - Controller - Run-mode snapshot persisted; `RSD-001` selected as the only currently runnable session; next action is a fresh `$implementation-plan-orchestrator` child for `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-001-plan.md`.
- 2026-05-30 09:33 CEST - Batch local pipeline fallback - Spawned pipeline produced trustworthy current-doc progress (`RSD-001` plan and docs) but no persisted final program verdict inside the bounded waits. Local fallback accepted `RSD-001`, skipped `RSD-002`/`RSD-003` due to the no-proceed decision, accepted closure-only `RSD-004`, and persisted the final verdict below.

## Overall Closure Bar

This rollout is closed only when 1:1 relay springboard behavior is represented honestly: relay-backed conversations remain successful and are not reported as direct unless a real non-circuit, non-limited connection or accepted relay->direct upgrade evidence exists; relay-only peers produce no false upgrade diagnostics or churn; any direct-escalation implementation is gated by a valid NET-REL-02/04 baseline decision; group direct-first behavior, relay reservation health, and existing 1:1 relay delivery remain stable; and the source, NET-REL tracking, baseline decision, and gate docs record the exact evidence without overclaiming production mobile DCUtR.

## Source Of Truth

- Product intent and scope: `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`
- Regression strategy: `Test-Flight-Improv/14-regression-test-strategy.md`
- Gate execution source: `Test-Flight-Improv/test-gate-definitions.md`
- Springboard tracking doc: `Network-Arch/Transport-Reliability/03-relay-springboard.md`
- NAT/DCUtR prerequisite and proof limits: `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`
- Transport index and dependency graph: `Network-Arch/Transport-Reliability/00-INDEX.md`
- Test doctrine and false-positive controls: `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`
- Relay compatibility constraint: `Network-Arch/Transport-Reliability/07-relay-backward-compatibility.md`
- Baseline decision gate: `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`
- Adjacent accepted evidence: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md` and `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`
- Current Go seams: `go-mknoon/node/node.go`, `go-mknoon/node/holepunch_tracer.go`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/pubsub.go`
- Current Flutter diagnostics seams: `lib/core/bridge/go_bridge_client.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/core/debug/transport_metrics.dart`, `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
- Current focused tests: `go-mknoon/node/holepunch_tracer_test.go`, `go-mknoon/node/holepunch_negative_control_test.go`, `go-mknoon/node/holepunch_feasibility_test.go`, `go-mknoon/node/transport_label_test.go`, `go-mknoon/node/send_message_recovery_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/integration/watchdog_failover_test.go`, `go-mknoon/integration/relay_test.go`, `test/core/bridge/go_bridge_client_test.dart`, `test/core/debug/transport_metrics_holepunch_test.dart`, `test/core/debug/transport_metrics_privacy_test.dart`, `test/core/services/p2p_service_inbound_transport_test.dart`, `test/core/services/p2p_service_transport_census_test.dart`, `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`, `integration_test/transport_e2e_test.dart`, and `integration_test/wifi_relay_fallback_smoke_test.dart`

## Session Ledger

| Session id | Title | Classification | Intended plan file | Depends on | Initial status |
|---|---|---|---|---|---|
| RSD-001 | NET-REL-03 Evidence Gate And Proceed/Defer Decision | evidence-gated | `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-001-plan.md` | none | pending |
| RSD-002 | Peer-Scoped Relay Springboard Ledger And Anti-Thrash Policy | prerequisite-blocked | `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-002-plan.md` | RSD-001 proceed verdict | prerequisite-blocked |
| RSD-003 | 1:1 Direct Escalation, Migration, And Relay Fallback Integration | prerequisite-blocked | `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-003-plan.md` | RSD-001, RSD-002 | prerequisite-blocked |
| RSD-004 | Acceptance, Baseline Classification, And Stable Doc Closure | closure-only | `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-004-plan.md` | RSD-001 plus any executed RSD-002/RSD-003 work | prerequisite-blocked |

## Pipeline Result Ledger

| Session id | Final status | Result evidence | Notes |
|---|---|---|---|
| RSD-001 | accepted | `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-001-plan.md` | No valid repo-local real-device, discovery-enabled, debug-mode 1:1 baseline harvest artifact was found; NET-REL-03 has no proceed verdict. |
| RSD-002 | skipped_due_to_dependency | RSD-001 no-proceed decision | Peer-scoped relay springboard policy must not run until a valid harvest provides a proceed boundary. |
| RSD-003 | skipped_due_to_dependency | RSD-001 no-proceed decision and RSD-002 skipped | 1:1 direct escalation/send-path integration must not run without the evidence gate and policy layer. |
| RSD-004 | accepted | `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-004-plan.md` | Closure recorded as evidence-gated/residual-only with no production code/test changes. |

## Ordered Session Breakdown

### RSD-001 - NET-REL-03 Evidence Gate And Proceed/Defer Decision

- Session classification: evidence-gated
- Intended plan file: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-001-plan.md`
- Exact scope: perform the decision-gate pass that decides whether relay springboard implementation is allowed to proceed. Inspect current repo evidence for a valid real-device, discovery-enabled, debug-mode, 1:1-focused baseline harvest with direct/relay/wifi/inbox/unknown counts, hole-punch attempt/success/failure counts, relay->direct upgrade count, and enough metadata to satisfy `NET-REL-04-baseline-decision-gate.md`. If the artifact is absent, record RSD-002/RSD-003 as blocked/deferred rather than inventing a routing or reachability policy. No production code changes.
- Why it is its own session: the source doc explicitly inherits the NET-REL-02 evidence gate. Implementation before this decision would convert an unresolved product/physics question into code.
- Likely code-entry files: docs and evidence only: `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, `Network-Arch/Transport-Reliability/03-relay-springboard.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`.
- Likely direct tests/regressions: normally documentation/evidence validation plus `git diff --check`. If the plan finds a new harvest artifact, validate the exact commands and copied report evidence from that artifact. Do not substitute simulator, CLI, loopback, LAN direct, or transport-label evidence for production mobile DCUtR proof.
- Likely named gates: none unless gate docs or tests are edited. Run `./scripts/run_test_gates.sh completeness-check` only if `Test-Flight-Improv/test-gate-definitions.md` changes or new tests are classified.
- Matrix/closure docs to update when done: source doc `101`, NET-REL-03 tracking doc, NET-REL-04 baseline decision gate, NET-REL-02 doc only if the prerequisite evidence classification changes, and `00-INDEX.md`.
- Dependency on earlier sessions: none.

### RSD-002 - Peer-Scoped Relay Springboard Ledger And Anti-Thrash Policy

- Session classification: prerequisite-blocked
- Intended plan file: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-002-plan.md`
- Exact scope: if and only if RSD-001 records a proceed verdict, implement or complete the Go peer-scoped policy layer needed before any active 1:1 direct escalation. The layer should model a peer as on relay and eligible or ineligible for upgrade, track attempts, successes, failures, last attempt, last success transport, bounded cooldown/ceiling, and no-thrash diagnostics. It must not change relay-server protocols, WebRTC/TURN/STUN architecture, or production reachability policy unless RSD-001 explicitly supplied that decision.
- Why it is its own session: anti-thrash and truthful state are the battery/reliability guardrail. Wiring direct attempts without this state would make relay-only mobile peers vulnerable to repeated failed upgrade work.
- Likely code-entry files: `go-mknoon/node/node.go`, a new or existing Go node policy file if local patterns justify it, `go-mknoon/node/holepunch_tracer.go`, `go-mknoon/node/relay_session.go` only if status exposure needs to reference relay health, `go-mknoon/node/config.go` for bounded timing constants.
- Likely direct tests/regressions: new focused Go unit tests for ledger state, cooldown reset on success, exact no-further-attempts after ceiling, and no false direct success; adjacent `go test ./node -run 'TestHolePunchTracer|TestHolePunchNegativeControl|TestClassifyStreamTransport|TestSendMessage'`; `git diff --check`.
- Likely named gates: no Flutter named gate unless the policy exposes new bridge/client diagnostics. If bridge payloads change, run direct Flutter diagnostics tests and the Startup / Transport Gate.
- Matrix/closure docs to update when done: RSD-004 owns final stable-doc closure. During RSD-002, update only plan-local evidence and `Test-Flight-Improv/test-gate-definitions.md` if new high-value Go/Flutter tests require classification.
- Dependency on earlier sessions: RSD-001 must say springboard implementation should proceed and must name the selected policy boundary or explicitly allow a contained implementation experiment.

### RSD-003 - 1:1 Direct Escalation, Migration, And Relay Fallback Integration

- Session classification: prerequisite-blocked
- Intended plan file: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-003-plan.md`
- Exact scope: after RSD-002 lands, integrate the peer-scoped policy into the 1:1 send/recovery path. For eligible active peers, attempt the selected direct-escalation path within bounded timing, confirm success only from a non-circuit, non-limited connection or accepted upgrade event, ensure subsequent 1:1 sends prefer/observe the actual direct stream, and preserve relay fallback for unpunchable peers. Self-heal must not become relay-only if direct has been confirmed, but relay-only delivery must remain successful.
- Why it is its own session: this is the user-visible Go/libp2p behavior change. It needs integration and negative-control proof that is different from pure policy/ledger tests.
- Likely code-entry files: `go-mknoon/node/node.go`, `go-mknoon/node/pubsub.go` only as a reference for direct-first group patterns, `go-mknoon/node/holepunch_tracer.go`, `go-mknoon/node/transport_label_test.go`, `go-mknoon/node/holepunch_negative_control_test.go`, `go-mknoon/node/holepunch_feasibility_test.go`, `go-mknoon/node/send_message_recovery_test.go`, and bridge/metrics files only if event payloads or client-visible inference change.
- Likely direct tests/regressions: Go node integration around relay-only NW002 staying `Limited == true` with zero upgrade success and stable connection count; protocol-feasibility relay->direct tests only when the harness can prove `conn.Stat().Limited == false`; send self-heal tests proving retry still uses bounded recovery; transport-label tests proving stream-owned classification; Go integration relay/watchdog tests if recovery behavior changes. Do not accept a `{direct, relay}` set as direct-upgrade proof.
- Likely named gates: `./scripts/run_test_gates.sh 1to1` if shared 1:1 send/retry semantics change; `./scripts/run_test_gates.sh transport` if bridge, resume, reconnect, or transport fallback changes; direct Go node and Go integration tests are mandatory for Go-only behavior.
- Matrix/closure docs to update when done: RSD-004 owns final stable-doc closure. Update `Test-Flight-Improv/test-gate-definitions.md` only if new tests or gate classifications are introduced.
- Dependency on earlier sessions: RSD-001 proceed verdict and RSD-002 accepted ledger/policy evidence.

### RSD-004 - Acceptance, Baseline Classification, And Stable Doc Closure

- Session classification: closure-only
- Intended plan file: `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-004-plan.md`
- Exact scope: close the rollout based on what actually happened. If RSD-001 deferred springboard work, record the product decision and residual honestly. If RSD-002/RSD-003 executed, re-run the accepted focused tests and named gates, classify the baseline result, update stable NET-REL docs and source doc with exact evidence, and preserve the distinction between relay delivery, LAN/direct-address delivery, loopback feasibility, stream label mapping, and real relay->direct upgrade.
- Why it is its own session: closure spans multiple prior proof seams and must not be mixed with implementation-time assumptions. It is the guard against docs overclaiming production mobile DCUtR.
- Likely code-entry files: docs first: `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`, `Network-Arch/Transport-Reliability/03-relay-springboard.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md` if prerequisite evidence changes, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, and `Test-Flight-Improv/test-gate-definitions.md` if classifications change.
- Likely direct tests/regressions: rerun the focused Go/Dart tests changed by RSD-002/RSD-003; `cd go-mknoon && go test ./node`; selected `go test -tags=integration ./integration -run ...` relay/watchdog tests when behavior touched integration paths; relevant direct Flutter bridge/metrics/settings tests; `git diff --check`.
- Likely named gates: Startup / Transport and 1:1 Reliability if implementation touched bridge/transport/1:1 send paths; completeness-check if test-gate docs changed. Baseline/no-code deferral closure may need only doc validation and `git diff --check`.
- Matrix/closure docs to update when done: source doc `101`, NET-REL-03, `00-INDEX.md`, NET-REL-04 baseline decision gate, and optionally NET-REL-02 and `test-gate-definitions.md` only when evidence or classifications changed. Do not create a new matrix doc unless RSD-004 proves these existing docs cannot hold the evidence.
- Dependency on earlier sessions: RSD-001 plus any executed RSD-002/RSD-003 sessions.

## Why This Is Not Fewer Sessions

The minimum safe split is four sessions because the work has a hard evidence gate before code, a battery/reliability policy seam before direct attempts, a separate Go send-path integration seam, and a final closure pass that must reconcile proof boundaries. Merging RSD-001 into implementation would hide the current product blocker. Merging RSD-002 and RSD-003 would invite direct-attempt wiring without first proving anti-thrash behavior. Merging RSD-004 into implementation would make stable docs depend on assumptions instead of landed evidence.

## Why This Is Not More Sessions

The source doc lists many test cases, but most group under four verification boundaries: decision-gate evidence, peer-scoped upgrade policy, send-path integration with negative controls, and final closure. Splitting transport labels, hole-punch counters, relay-only delivery, and diagnostics into separate sessions would mostly duplicate the already accepted DCUTR-001/002/003 evidence unless new implementation actually changes those seams.

## Regression And Gate Contract

`Test-Flight-Improv/14-regression-test-strategy.md` applies by using direct focused tests first, then named gates only when touched code triggers them. New integration/cross-feature/core-service tests must be classified in `Test-Flight-Improv/test-gate-definitions.md`, and red/skipped environment-bound tests must be reported rather than hidden.

`Test-Flight-Improv/test-gate-definitions.md` applies as follows:

- RSD-001 uses evidence/doc validation and `git diff --check`; no named gate unless gate docs or tests change.
- RSD-002 uses focused Go node tests first. Startup / Transport is required only if bridge/P2P/diagnostics payloads change.
- RSD-003 uses Go node and Go integration tests, plus `./scripts/run_test_gates.sh 1to1` for shared 1:1 send/retry changes and `./scripts/run_test_gates.sh transport` for bridge/resume/reconnect/fallback changes.
- RSD-004 reruns the focused evidence from executed sessions, runs triggered named gates, and runs `./scripts/run_test_gates.sh completeness-check` when gate docs or test classification changed.

False-positive controls are mandatory: a direct-upgrade success must be paired with a relay-only/no-direct-address control; a direct label must be tied to the actual stream or a non-circuit, non-limited connection; simulator, CLI, loopback, LAN direct, or label-only evidence cannot be used as production mobile relay->direct proof.

## Matrix Update Contract

No new matrix doc should be created during decomposition. The existing stable closure surfaces are:

- `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`
- `Network-Arch/Transport-Reliability/03-relay-springboard.md`
- `Network-Arch/Transport-Reliability/00-INDEX.md`
- `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`
- `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md` when prerequisite evidence changes
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md` only if new evidence reclassifies accepted DCUTR proof
- `Test-Flight-Improv/test-gate-definitions.md` only when tests or gate classifications change

RSD-004 owns final stable-doc updates. Earlier sessions should record evidence in their own plan files and avoid rewriting closure docs except to correct a proven stale fact that would mislead downstream planning.

## Downstream Execution Path

For each session, run the downstream skills in order:

| Session id | Next downstream path |
|---|---|
| RSD-001 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator`; if the decision is defer/no valid harvest, record RSD-002/RSD-003 as still prerequisite-blocked. |
| RSD-002 | Run downstream only after RSD-001 records a proceed verdict. Refresh the plan against landed code and current NET-REL docs before implementation. |
| RSD-003 | Run downstream only after RSD-001 proceeds and RSD-002 is accepted. Refresh against the actual ledger/policy implementation and current tests. |
| RSD-004 | Run downstream after RSD-001 and any executed implementation sessions. If implementation was deferred, close as evidence-gated/residual-only with no code gates beyond doc validation. |

## Structural Blockers Remaining

No structural blocker remains in the decomposition itself.

Product/evidence blocker intentionally recorded: production mobile relay->direct DCUtR success is still unproven, and the source doc does not authorize a reachability, routing, WebRTC, TURN, relay-server, or AutoRelay architecture decision. That blocker belongs to RSD-001 and keeps RSD-002/RSD-003 from being implementation-ready today.

## Accepted Differences Intentionally Left Unchanged

- Relay remains the correct steady state for many cellular, symmetric-NAT, or otherwise unpunchable pairs.
- A stream label of `direct`, a LAN/pre-relay direct dial, a loopback feasibility run, or simulator/CLI liveness evidence is not production mobile relay->direct proof.
- No relay-server protocol, STUN/TURN/WebRTC, AutoRelay, or production reachability policy change is included in this decomposition.
- Existing group direct-first behavior is treated as adjacent reference behavior, not as proof that 1:1 springboard exists.
- Background/foreground upgrade suppression is not assumed to exist in Go; if future planning needs it, the signal must be explicitly designed or kept in a Dart-layer scope.

## Exact Docs/Files Used As Evidence

- `/Users/I560101/.codex/skills/implementation-session-decomposer/SKILL.md`
- `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`
- `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`
- `Network-Arch/Transport-Reliability/00-INDEX.md`
- `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`
- `Network-Arch/Transport-Reliability/03-relay-springboard.md`
- `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`
- `Network-Arch/Transport-Reliability/07-relay-backward-compatibility.md`
- `go-mknoon/node/node.go`
- `go-mknoon/node/holepunch_tracer.go`
- `go-mknoon/node/relay_session.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/holepunch_tracer_test.go`
- `go-mknoon/node/holepunch_negative_control_test.go`
- `go-mknoon/node/holepunch_feasibility_test.go`
- `go-mknoon/node/transport_label_test.go`
- `go-mknoon/node/send_message_recovery_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/integration/watchdog_failover_test.go`
- `go-mknoon/integration/relay_test.go`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/debug/transport_metrics.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `test/core/debug/transport_metrics_holepunch_test.dart`
- `test/core/debug/transport_metrics_privacy_test.dart`
- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/core/services/p2p_service_transport_census_test.dart`
- `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/wifi_relay_fallback_smoke_test.dart`

## Why The Decomposition Is Safe To Send Into Downstream Planning/Execution

The artifact uses only doc-scoped plan paths, leaves implementation blocked behind the current evidence gate, assigns matrix/closure responsibility to a dedicated closure session, and binds future sessions to existing regression gates and negative-control doctrine. It does not execute implementation work, does not create a new matrix doc, and does not overwrite unrelated dirty-worktree changes.

## Final Program Verdict

Verdict: residual_only.

Local pipeline fallback used: yes. The spawned pipeline produced trustworthy doc-owned progress but did not persist a final program verdict before the bounded waits expired.

Docs completed: `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`, `Network-Arch/Transport-Reliability/03-relay-springboard.md`, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`, this breakdown, `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-001-plan.md`, and `Test-Flight-Improv/101-relay-springboard-direct-escalation-session-RSD-004-plan.md`.

What is now closed: the current doc 101 rollout has a durable no-proceed decision for NET-REL-03 implementation under current evidence. Stable docs now say relay springboard direct-escalation work must not proceed from simulator, CLI, loopback, LAN/direct-label, or label-mapping evidence.

Residual-only item: capture a valid real-device, discovery-enabled, debug-mode 1:1 NET-REL-04 baseline harvest with direct/relay/wifi/inbox/unknown counts, hole-punch attempt/success/failure counts, relay-to-direct upgrade count, and cross-network/co-location metadata. If that artifact appears later, reopen the decision gate before planning RSD-002/RSD-003.

Skipped sessions: RSD-002 and RSD-003 are skipped_due_to_dependency for this run, not accepted implementation. No relay springboard policy, direct escalation, send-path migration, reachability policy, WebRTC/TURN/STUN, AutoRelay, relay-server protocol, bridge payload, UI, production code, or test changes were made for doc 101.

Verification: RSD-001 ran `flutter devices --machine`, `xcrun simctl list devices available`, targeted `rg` evidence searches, and `git diff --check` (passed). The final local pipeline fallback reran `git diff --check` after these verdict edits, and it passed. No named gate was required because `Test-Flight-Improv/test-gate-definitions.md`, production code, and tests were not edited for this doc.
