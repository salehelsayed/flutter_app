# DCUTR-004 - Baseline harvest, decision-doc closure, and residual classification

Status: accepted_with_explicit_follow_up

## Planning Progress

- 2026-05-30 00:29:04 CEST - Arbiter completed / plan execution-ready. Files inspected since last update: reviewer findings and plan scope/gate sections. Decision/blocker: no structural blockers; incremental wording details are non-blocking; accepted differences are explicit residuals, not implementation work. Next action: execute only the doc-closure pass later using this plan.
- 2026-05-30 00:28:45 CEST - Reviewer completed / Arbiter started. Files inspected since last update: full draft plan. Decision/blocker: sufficient as-is; checklist coverage, source-of-truth precedence, accepted prior gates, conditional completeness-check trigger, no-new-matrix guard, and residual classifications are explicit. Next action: classify findings and finalize execution-ready status if no structural blocker remains.
- 2026-05-30 00:27:06 CEST - Planner completed / Reviewer started. Files inspected since last update: evidence notes and draft plan content in this file. Decision/blocker: draft is acceptance-only, uses existing stable docs for closure, accepts prior DCUTR-001/002/003 gates rather than re-running behavior tests by default, and treats absent real-device harvest as an explicit residual. Next action: review checklist parity, gate triggers, and scope guard.
- 2026-05-30 00:26:34 CEST - Evidence Collector completed / Planner started. Files inspected since last update: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`, DCUTR-001/002/003 plans, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Test-Flight-Improv/NET-REL-04-baseline-harvest-runbook.md`, `Test-Flight-Improv/99-transport-observability-and-metrics-HARVEST-DECISION.md`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, Go/Dart transport seams and focused tests. Decision/blocker: no structural planning blocker; no concrete valid real-device baseline harvest artifact was found, so final execution must classify production mobile DCUtR as unproven/evidence-gated. Next action: draft the acceptance-only execution plan and gate contract.
- 2026-05-30 00:25:10 CEST - Evidence Collector started. Files inspected since last update: `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`, `git status --short`, `Test-Flight-Improv/` listing. Decision/blocker: target path confirmed and repo has many pre-existing dirty changes; this pass will edit only this plan file. Next action: inspect DCUTR source, breakdown, prior session plans, stable closure docs, and gate definitions.

## Execution Progress

- 2026-05-30 00:30 CEST - Phase: contract extracted / local fallback declared. Files inspected: this plan, source evidence doc, baseline decision gate, NAT/DCUtR tracking doc, transport index, session breakdown, DCUTR-001/002/003 verdicts, harvest runbook, harvest decision doc, gate definitions, and `git status --short`. Decision/blocker: spawned-agent isolation is not available through the current tool surface; continuing with a bounded local sequential Executor then QA fallback. No production code/tests or gate classifications will be edited. Next action: patch only allowed stable docs and this plan's progress/final verdict.
- 2026-05-30 00:34 CEST - Phase: Executor completed documentation closure. Files touched: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`, `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`, and this plan. Decision/blocker: no concrete valid real-device, discovery-enabled, debug-mode baseline artifact was found; stable docs now classify production mobile DCUtR as unproven/evidence-gated, accept DCUTR-001/002/003 scoped evidence, classify simulator/CLI proof as liveness/recovery only, and record the E8 media metadata residual. Next action: run required validation.
- 2026-05-30 00:34 CEST - Phase: required validation completed. Command: `git diff --check` -> PASS. Files inspected: scoped status for allowed docs and `Test-Flight-Improv/test-gate-definitions.md`; stable-doc residual anchors. Decision/blocker: `Test-Flight-Improv/test-gate-definitions.md` was not touched, so `./scripts/run_test_gates.sh completeness-check` was not required or run. Prior DCUTR-001/002/003 behavior gates were accepted from recorded verdicts and not rerun. Next action: QA review.
- 2026-05-30 00:34 CEST - Phase: QA Reviewer completed. Files inspected: final stable docs, plan progress, scoped git status, residual wording, and no-overclaim searches. Decision/blocker: no blocking issues found; no production code/tests, routing/reachability/WebRTC/TURN/STUN/relay-server behavior, Go event names, or Dart metrics contract were changed by this session; no new matrix doc was created. Next action: write final verdict.
- 2026-05-30 00:36 CEST - Phase: closure audit completed. Files inspected: final execution verdict in this plan, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`, source evidence doc, baseline decision gate, NAT/DCUtR tracking doc, transport index, prior DCUTR-001/002/003 verdicts, scoped status for `Test-Flight-Improv/test-gate-definitions.md`, and stable-doc residual anchors. Decision/blocker: DCUTR-004 doc-only execution is accepted with explicit follow-up; no stable-doc accuracy correction was needed. Closure audit edits are limited to this plan and the session breakdown. Next action: final program verdict is recorded in the breakdown.

## real scope

This is an acceptance/documentation closure session for DCUTR-004 only.

In scope for the later execution pass:

- Convert accepted DCUTR-001, DCUTR-002, and DCUTR-003 evidence into the stable closure docs named by the breakdown.
- Classify remaining residuals honestly: production mobile DCUtR success, the missing real-device/debug/discovery-enabled baseline harvest, and the repeated `run_transport_e2e.dart` E8 media metadata orchestrator failure.
- Update only these existing stable docs when execution runs:
  - `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`
  - `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`
  - `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`
  - `Network-Arch/Transport-Reliability/00-INDEX.md`
  - `Test-Flight-Improv/test-gate-definitions.md` only if a test/gate classification actually changes
- Leave prior behavior-test evidence as accepted unless execution finds a concrete contradiction in current code/tests/docs.

Out of scope:

- No production code, tests, routing policy, reachability policy, WebRTC/TURN/STUN, relay-server behavior, Go event-name, or Dart metrics-contract change.
- No new matrix doc. Current repo evidence shows the named source doc, baseline decision gate, NAT/DCUtR tracking doc, transport reliability index, and conditional gate-definition doc are sufficient closure surfaces.
- No manual/device harvest execution in this doc pass. If a concrete captured harvest artifact is not already present in the repo at execution time, record the missing harvest as a residual/evidence gate.

## closure bar

DCUTR-004 is good enough when the stable docs give a truthful, maintenance-ready verdict without implying transport behavior that has not been proven.

Coverage ledger for the explicit DCUTR-004 requirements:

| Requirement | Planned closure proof |
|---|---|
| DCUTR-001 accepted evidence closes Go tracer/anti-false-upgrade controls | Cite the DCUTR-001 accepted verdict and focused Go command from the breakdown; summarize the closed Go tracer event contract, production-private reachability default, test-only feasibility seam, stale limited-state repair, classifier anti-overclaim wording, loopback feasibility classification, and relay-only negative control. |
| DCUTR-002 accepted evidence closes Dart aggregate privacy-safe diagnostics/counters | Cite the DCUTR-002 accepted verdict and focused Flutter/transport-gate evidence; summarize sanitized event forwarding, aggregate hole-punch and relay-to-direct counters, `unknown` inbound preservation, and privacy-safe settings diagnostics. |
| DCUTR-003 accepted-with-follow-up evidence closes relay-only/no-upgrade acceptance | Cite the DCUTR-003 verdict and accepted Go/Flutter/simulator evidence; summarize strict limited-circuit relay-only delivery, exact zero forced relay-only attempts/successes, no `holepunch:success`, no `transport:upgraded`, stable target-peer connection count, and relay failover/recovery no-upgrade behavior. |
| Production mobile DCUtR success remains unproven | Record as residual/evidence-gated unless a concrete real-device, discovery-enabled, debug-mode harvest artifact exists and directly proves a relay-to-direct production mobile upgrade. |
| Simulator/CLI runs are liveness/recovery evidence, not physical NAT traversal proof | State this in source and decision docs wherever simulator or CLI evidence is cited. Do not use `transport`, reliability-sim, loopback, LAN direct, or classifier labels as production DCUtR proof. |
| `run_transport_e2e.dart` E8 residual | Record the DCUTR-003 residual exactly: the reliability-sim runner was attempted twice; Flutter reported `33/33 passed`; the orchestrator downloaded the 69-byte blob; the external proof produced `29/30 passed` with `messageSeen=false`, `attachmentReferenced=false`, and `blobInList=false`. Classify it as an external orchestrator media-metadata residual unless new evidence ties it to DCUTR no-upgrade behavior. |
| Real-device harvest availability | Inspect existing repo docs/artifacts. If no concrete captured `baselineReport()`/decision-gate artifact exists for a real-device, discovery-enabled, debug-mode 1:1 harvest, update the stable docs to say the harvest is unavailable and forbid calling production mobile DCUtR closed. |
| Existing stable docs only | Use the four stable closure docs plus conditional gate definitions. Do not create a new matrix document unless execution proves all existing docs are structurally unable to hold the closure, which current evidence does not support. |
| Test/gate discipline | Re-run `git diff --check`; run `./scripts/run_test_gates.sh completeness-check` only if `Test-Flight-Improv/test-gate-definitions.md` changes because test classification changed. Accept prior DCUTR behavior gates by default. |

Target execution verdict:

- The DCUTR-004 doc-closure session can be accepted when the stable docs are updated and residuals are explicit.
- The overall production mobile DCUtR capability must not be marked `closed` without a valid real-device/debug/discovery-enabled harvest artifact proving the production mobile relay-to-direct case. In the current repo state, the expected product/residual classification is `accepted_with_explicit_follow_up` for the DCUTR evidence run, with production mobile DCUtR and baseline harvest recorded as residual/evidence-gated.

## source of truth

Authoritative sources for execution:

- Active session contract: this plan and `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`.
- Product/problem source: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`.
- Prior accepted session evidence: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-002-plan.md`, and `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-003-plan.md`.
- Baseline/decision source: `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`; read-only supporting runbook `Test-Flight-Improv/NET-REL-04-baseline-harvest-runbook.md`.
- NAT/DCUtR architecture source: `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`.
- Transport reliability index: `Network-Arch/Transport-Reliability/00-INDEX.md`.
- Gate execution source: `Test-Flight-Improv/test-gate-definitions.md` and, if it disagrees, `scripts/run_test_gates.sh`.
- Current code/tests beat stale prose. If docs conflict with code/tests, inspect current code/tests read-only and update docs only if the correction is within this acceptance scope; otherwise stop and replan a new implementation session.

## session classification

`acceptance-only`.

Reason: DCUTR-001, DCUTR-002, and DCUTR-003 already landed and were accepted in the breakdown. DCUTR-004 owns closure wording, baseline decision-gate classification, and residual accounting. It must not add behavior, tests, routes, reachability, metrics contracts, or relay functionality.

## exact problem statement

The remaining risk is not missing transport code in this session. The risk is documentation overclaiming: treating Go tracer proof, Dart aggregate metrics, relay-only no-upgrade proof, simulator/CLI liveness, loopback feasibility, LAN direct dialing, or generic `direct` labels as if they proved production mobile DCUtR success.

User-visible behavior must stay unchanged. The final docs must say that relay delivery remains a valid steady state for unpunchable peers, direct labels are not automatically relay-to-direct DCUtR upgrades, and production mobile DCUtR remains unproven unless a valid real-device harvest proves otherwise.

## files and repos to inspect next

Read/write during execution:

- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`
- `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`
- `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`
- `Network-Arch/Transport-Reliability/00-INDEX.md`
- `Test-Flight-Improv/test-gate-definitions.md` only if classification actually changes

Read-only evidence and consistency checks:

- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-002-plan.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-003-plan.md`
- `Test-Flight-Improv/NET-REL-04-baseline-harvest-runbook.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-HARVEST-DECISION.md`
- `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`
- `scripts/run_test_gates.sh`
- Current code/test seams only if docs conflict: `go-mknoon/node/node.go`, `go-mknoon/node/holepunch_tracer.go`, `go-mknoon/node/holepunch_tracer_test.go`, `go-mknoon/node/holepunch_negative_control_test.go`, `go-mknoon/integration/watchdog_failover_test.go`, `lib/core/bridge/bridge.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/core/debug/transport_metrics.dart`, and the focused Dart tests listed below.

## existing tests covering this area

Accepted from DCUTR-001:

- `cd go-mknoon && go test ./node -run 'TestHolePunchTracer|TestClassifyStreamTransport|TestHolePunchFeasibility|TestHolePunchNegativeControl'` passed.
- Covers Go tracer event contract, classifier mapping-vs-proof split, loopback feasibility classification, test-only public reachability seam, production-private reachability default, stale limited-state repair, and relay-only negative control.

Accepted from DCUTR-002:

- `flutter test test/core/bridge/go_bridge_client_test.dart test/core/debug/transport_metrics_holepunch_test.dart test/core/debug/transport_metrics_privacy_test.dart test/core/debug/transport_metrics_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/core/services/p2p_service_transport_census_test.dart test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` passed in the DCUTR-002 verdict.
- `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed after the unqualified attempt was blocked by multiple connected devices.
- Covers accepted Go event forwarding, sanitized payloads, aggregate metrics/counters, `unknown` inbound preservation, and privacy-safe diagnostics.

Accepted from DCUTR-003:

- `cd go-mknoon && go test ./node -run 'TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash|TestHolePunchTracer|TestClassifyStreamTransport'` passed.
- `cd go-mknoon && go test -tags=integration ./integration -run 'TestSecondRelayAvailablePreventsWatchdogRestart|TestAllRelaysUnavailableEnterDegradedStateAndRecover|TestRendezvousAndInboxStillWorkAfterRelayRestart'` passed.
- `cd go-mknoon && go test -tags=integration ./integration -run 'TestRelayTwoNodesMessage|TestRelayCircuitRecoveryAfterDisconnect|TestRelayCircuitRecoveryPreservesPeerId|TestRelayRefreshRecoversWithoutHostReplacement'` passed.
- Direct Flutter host tests passed; reliability-sim `1to1 --list` passed; reliability-sim `run_wifi_relay_fallback_smoke.dart` passed; `git diff --check` passed.
- Covers forced relay-only delivery/no-upgrade behavior, relay failover/recovery without manufactured upgrades, and simulator relay/recovery liveness.

Known evidence gap:

- Reliability-sim `run_transport_e2e.dart` was attempted twice in DCUTR-003 and failed only at the external E8 media metadata proof after Flutter reported `33/33 passed` and blob download worked. This is not accepted as a DCUTR no-upgrade failure, but must be classified in final closure.
- No concrete valid real-device, discovery-enabled, debug-mode `baselineReport()` harvest artifact was found in the repo during planning. `NET-REL-04-baseline-decision-gate.md` remains pre-harvest with blanks, and `99-transport-observability-and-metrics-HARVEST-DECISION.md` records partial real-device mechanism evidence but not the manual diagnostics-card read or paired-peer harvest needed for this decision.

## regression/tests to add first

None.

This is a doc-only acceptance pass. Adding tests, changing tests, or changing code would be scope expansion. If execution discovers a required behavior proof is absent, it must record the missing proof as a residual/evidence gate or stop for a new implementation plan rather than adding tests inside DCUTR-004.

The only conditional test-doc action is classification maintenance: edit `Test-Flight-Improv/test-gate-definitions.md` only if execution changes a test/gate classification, then run `./scripts/run_test_gates.sh completeness-check`.

## step-by-step implementation plan

1. Reconfirm the worktree and scope before editing:
   - Run `git status --short`.
   - Verify no execution edit is planned outside this plan file and the stable docs listed in `real scope`.
   - Treat existing dirty changes as user/prior-session work; do not revert them.

2. Reconfirm prior session state from current files:
   - Read the DCUTR session ledger and closure evidence in the breakdown.
   - Read the final verdict sections in DCUTR-001, DCUTR-002, and DCUTR-003 plans.
   - If a prior accepted verdict has been removed or contradicted, stop and update this plan rather than guessing.

3. Check for a concrete valid harvest artifact:
   - Inspect `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, `Test-Flight-Improv/NET-REL-04-baseline-harvest-runbook.md`, `Test-Flight-Improv/99-transport-observability-and-metrics-HARVEST-DECISION.md`, and any repo-local files that clearly contain a captured `baselineReport()` or filled decision-gate table.
   - A valid production-mobile/DCUtR harvest artifact must show a real-device, discovery-enabled, debug-mode, 1:1-focused run with raw counts, hole-punch attempt/success/failure counts, relay-to-direct upgrade count, and enough metadata to satisfy the decision-gate validity rules.
   - If no artifact exists, record the missing harvest as residual/evidence-gated and do not call production mobile DCUtR closed.

4. Update `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`:
   - Add or refresh a closure/residual section that maps DCUTR-001, DCUTR-002, and DCUTR-003 accepted evidence to the original test cases.
   - Keep production mobile DCUtR success unproven unless Step 3 found a valid artifact.
   - State simulator/CLI evidence is relay/recovery liveness evidence, not physical NAT traversal proof.
   - Record the E8 media metadata residual exactly as described in the closure bar.

5. Update `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`:
   - If Step 3 found no valid artifact, keep the gate pre-harvest or explicitly mark the validity gate failed/unavailable.
   - Do not reorder NET-REL-01/02/03/05 based on simulator, loopback, LAN-mechanism, or partial device evidence.
   - If a valid artifact exists, fill only the fields the artifact directly supports and apply the existing gate rules without changing policy scope.

6. Update `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`:
   - Bring the status/evidence summary in line with current code: Go tracer and Dart aggregate metrics exist, relay-only/no-upgrade acceptance exists, production reachability remains private, and production mobile DCUtR success remains unproven without a valid harvest.
   - Preserve the distinction between protocol feasibility, label mapping, LAN direct dialing, relay-only safety, and production relay-to-direct DCUtR success.

7. Update `Network-Arch/Transport-Reliability/00-INDEX.md`:
   - Refresh only the NET-REL-02 status/dependency wording needed to reflect closure evidence and residuals.
   - Do not imply NET-REL-02/03 are prioritized, skipped, or policy-decided unless the baseline gate has a valid artifact and explicitly supports that decision.

8. Update `Test-Flight-Improv/test-gate-definitions.md` only if classification actually changes:
   - If no test/gate classification changes, leave it untouched and do not run completeness-check.
   - If a test classification changes, make the smallest existing-doc edit and run `./scripts/run_test_gates.sh completeness-check`.

9. Run required doc hygiene:
   - Always run `git diff --check`.
   - Review the final diff for accidental source/test/code changes and for overclaims such as "production DCUtR closed", "simulator proved NAT traversal", or "LAN direct equals DCUtR upgrade".

10. Final execution summary:
   - Report updated docs, accepted prior evidence, gates run, gates accepted from prior sessions, and residual classifications.
   - Use `accepted_with_explicit_follow_up` for the DCUTR evidence run unless a valid harvest supports a stronger classification.

## risks and edge cases

- Stale docs may still say no tracer or no Dart metrics exist. Current code/tests and accepted DCUTR-001/002/003 verdicts win over stale prose.
- `99-transport-observability-and-metrics-HARVEST-DECISION.md` contains useful real physical-device evidence, but it is not a valid DCUTR baseline harvest: it records no manual diagnostics-card read for a paired real-device 1:1 harvest and no production mobile relay-to-direct upgrade proof.
- `NET-REL-04-baseline-decision-gate.md` is pre-harvest. Filling policy decisions from hypothesis text would be an overclaim.
- A `direct` label may come from LAN/pre-relay direct dialing, loopback feasibility, or a non-circuit stream. It is not by itself a relay-to-direct DCUtR upgrade.
- Reliability-sim and CLI evidence can prove liveness/recovery paths but not physical NAT traversal or production mobile DCUtR success.
- A doc-only closure can accidentally reopen DCUTR-003 because of the E8 media residual. Reopen DCUTR-003 only on a real regression in relay-only/no-upgrade behavior.
- The large dirty worktree includes many pre-existing transport/doc changes. Execution must avoid reverting or reformatting unrelated files.

## exact tests and gates to run

Run during DCUTR-004 execution:

```bash
git diff --check
```

Run only if `Test-Flight-Improv/test-gate-definitions.md` changes because test/gate classification changed:

```bash
./scripts/run_test_gates.sh completeness-check
```

Do not re-run by default; accept from prior session verdicts:

- DCUTR-001 focused Go node proof:

```bash
cd go-mknoon && go test ./node -run 'TestHolePunchTracer|TestClassifyStreamTransport|TestHolePunchFeasibility|TestHolePunchNegativeControl'
```

- DCUTR-002 direct Flutter diagnostic/counter proof and transport gate:

```bash
flutter test test/core/bridge/go_bridge_client_test.dart test/core/debug/transport_metrics_holepunch_test.dart test/core/debug/transport_metrics_privacy_test.dart test/core/debug/transport_metrics_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/core/services/p2p_service_transport_census_test.dart test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart
FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport
```

- DCUTR-003 relay-only/no-upgrade Go, integration, host Flutter, and simulator liveness proof:

```bash
cd go-mknoon && go test ./node -run 'TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash|TestHolePunchTracer|TestClassifyStreamTransport'
cd go-mknoon && go test -tags=integration ./integration -run 'TestSecondRelayAvailablePreventsWatchdogRestart|TestAllRelaysUnavailableEnterDegradedStateAndRecover|TestRendezvousAndInboxStillWorkAfterRelayRestart'
cd go-mknoon && go test -tags=integration ./integration -run 'TestRelayTwoNodesMessage|TestRelayCircuitRecoveryAfterDisconnect|TestRelayCircuitRecoveryPreservesPeerId|TestRelayRefreshRecoversWithoutHostReplacement'
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only integration_test/scripts/run_wifi_relay_fallback_smoke.dart
```

Known non-accepted simulator command from DCUTR-003, to classify but not rerun by default:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only integration_test/scripts/run_transport_e2e.dart
```

Reason: it was attempted twice and failed only at the external E8 media metadata proof after the Flutter test reported `33/33 passed` and blob download worked. DCUTR-004 classifies this residual; it does not use this run as production mobile DCUtR proof.

## known-failure interpretation

- `run_transport_e2e.dart` E8 media metadata failure: known residual from DCUTR-003. Treat as external orchestrator media metadata proof failure unless current evidence ties it to relay-only/no-upgrade behavior. Do not use it to reject DCUTR-003 relay-only acceptance or to prove production DCUtR.
- `./scripts/run_test_gates.sh completeness-check`: latest known gate-doc note says the 2026-05-28 attempt failed with `747/750` files classified and these pre-existing unmatched files: `test/l10n/l10n_integrity_test.dart`, `test/shared/fakes/fake_group_pubsub_network_test.dart`, `test/shared/fakes/seeded_group_reproduction_log_test.dart`. If completeness-check is triggered and only these unchanged known files remain, record them as pre-existing. Any new unmatched file or classification gap caused by DCUTR-004 must be fixed or the gate-doc edit must be reverted.
- Environment/device constraints: absence of physical devices, local discovery, debug build, or a copied `baselineReport()` artifact is an evidence-gated missing harvest, not a failed DCUtR proof.

## done criteria

- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md` records DCUTR-001/002/003 accepted evidence and the remaining residuals without overclaiming production mobile DCUtR.
- `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md` either contains a valid artifact-backed harvest decision or explicitly remains unavailable/pre-harvest/evidence-gated. It does not reorder workstreams from hypothesis-only evidence.
- `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md` reflects current tracer, Dart metrics, relay-only acceptance, and production-private reachability accurately.
- `Network-Arch/Transport-Reliability/00-INDEX.md` reflects the NET-REL-02 status/residual without policy expansion.
- `Test-Flight-Improv/test-gate-definitions.md` is untouched unless classification changes; if touched, `./scripts/run_test_gates.sh completeness-check` was run and classified.
- No production code, tests, routing policy, reachability policy, WebRTC/TURN/STUN, relay-server behavior, Go event names, or Dart metrics contract changed.
- No new matrix doc was created.
- `git diff --check` passes.
- Final summary names which tests/gates were accepted from prior DCUTR verdicts, which gates were actually run in DCUTR-004, and which residuals remain.

## scope guard

Stop and replan if execution appears to require any of the following:

- Changing production code or tests.
- Relaxing `ForceReachabilityPrivate()`, changing AutoNAT/AutoRelay policy, or adding a production path that forces public reachability.
- Changing `holepunch:attempt`, `holepunch:success`, `holepunch:failure`, or `transport:upgraded` names or payload contract.
- Changing `TransportMetrics` bucket names, aggregate privacy contract, or settings diagnostics semantics.
- Adding WebRTC, TURN, STUN, relay-server traversal features, or routing-policy decisions.
- Reclassifying simulator/CLI liveness as physical NAT traversal proof.
- Creating a new matrix doc when existing stable docs can hold closure.

## accepted differences / intentionally out of scope

- Host Go tracer tests, loopback feasibility tests, and Go relay-only negative controls are valuable evidence, but not production mobile DCUtR success.
- Dart/Flutter host tests prove diagnostics/counters/privacy, not real NAT traversal.
- The simulator transport gate and reliability-sim runners prove app/relay/recovery liveness under their fixtures, not physical mobile NAT traversal.
- Relay-only delivery is a successful steady state for unpunchable peers, not a failure requiring direct upgrade.
- A valid baseline harvest is allowed to be absent in this closure; absence must be documented as residual/evidence-gated instead of being hidden.
- `Test-Flight-Improv/NET-REL-04-baseline-harvest-runbook.md` may be read as supporting doctrine but is not in the allowed update set for DCUTR-004 execution.

## dependency impact

- NET-REL-02/NET-REL-03 product decisions remain gated on a valid real-device/debug/discovery-enabled baseline harvest with hole-punch counts. If that artifact is absent, later work must not use DCUTR-004 as a production mobile DCUtR closure claim.
- NET-REL-01 and NET-REL-05 prioritization must continue to rely on the baseline decision gate rules, not on simulator or partial device evidence.
- DCUTR-001/002/003 should reopen only on regressions in their scoped contracts, not merely because production mobile DCUtR or the E8 media residual remains open.
- Future real-device harvest work should update the existing baseline decision gate and relevant tracking docs, not invent a new matrix unless the stable docs are proven structurally insufficient.

## reviewer findings

- Sufficiency: sufficient as-is for an acceptance-only execution pass.
- Missing files, tests, or gates: none structural. The plan names every stable doc allowed for execution, names read-only evidence docs, and makes `git diff --check` mandatory. `./scripts/run_test_gates.sh completeness-check` is correctly conditional on an actual `Test-Flight-Improv/test-gate-definitions.md` classification change.
- Stale assumptions: no unsafe stale assumption found. The plan explicitly says current code/tests beat stale prose and records that no concrete valid real-device baseline harvest artifact was found during planning.
- Overengineering: none. The plan forbids new matrix docs, new tests, behavior changes, and manual harvest execution.
- Decomposition: narrow enough. The executor can update closure docs without deciding routing/reachability/WebRTC/TURN/STUN/relay-server policy.
- Checklist parity: complete. DCUTR-001/002/003 evidence, production mobile residual, simulator/CLI limits, E8 residual, real-device harvest availability, stable-doc-only rule, and gate triggers each have a planned proof or accepted residual.

## arbiter decision

- Structural blockers: none.
- Incremental details intentionally deferred: exact final wording in the stable docs belongs to the later execution pass; no need to pre-author every sentence here.
- Accepted differences intentionally left unchanged: production mobile DCUtR success remains unproven without a valid real-device/debug/discovery-enabled harvest; simulator/CLI proof remains liveness/recovery evidence; E8 remains an external media metadata residual; no code/tests/policy/matrix expansion is allowed.
- Stop rule: satisfied. The plan is safe to execute now as a doc-only acceptance pass.

## Final Execution Verdict

Final verdict: `accepted_with_explicit_follow_up`.

Spawned-agent isolation used: no. The current tool surface did not expose a
spawned child-agent mechanism, so this execution used the documented local
sequential fallback with explicit Executor then QA phases.

Local sequential fallback used: yes.

Files changed:

- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`
- `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`
- `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`
- `Network-Arch/Transport-Reliability/00-INDEX.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-004-plan.md`

Tests added or updated: none.

Evidence captured:

- DCUTR-001 accepted Go tracer/anti-false-upgrade evidence is folded into stable
  docs.
- DCUTR-002 accepted Dart aggregate diagnostics/privacy-safe counter evidence is
  folded into stable docs.
- DCUTR-003 accepted-with-follow-up relay-only/no-upgrade evidence is folded
  into stable docs without reopening relay-only closure.
- No concrete valid real-device, discovery-enabled, debug-mode
  `baselineReport()`/decision-gate artifact exists in the inspected repo docs,
  so production mobile DCUtR success remains unproven/evidence-gated.
- Simulator/CLI proof is classified as relay/recovery liveness evidence, not
  physical NAT traversal proof.
- The repeated `run_transport_e2e.dart` E8 residual is recorded as an external
  orchestrator media-metadata residual: attempted twice; Flutter `33/33 passed`;
  69-byte blob downloaded; external summary `29/30 passed` with
  `messageSeen=false`, `attachmentReferenced=false`, and `blobInList=false`.

Exact tests and gates run:

- `git diff --check` -> PASS.
- `./scripts/run_test_gates.sh completeness-check` was not run because
  `Test-Flight-Improv/test-gate-definitions.md` was untouched and no
  test/gate classification changed.

Prior gates accepted and not rerun:

- DCUTR-001 focused Go node proof.
- DCUTR-002 direct Flutter diagnostics/counter proof and transport gate.
- DCUTR-003 focused Go node proof, Go integration proofs, direct Flutter host
  proof, reliability-sim `1to1 --list`, reliability-sim
  `run_wifi_relay_fallback_smoke.dart`, and prior `git diff --check`.

Blocking issues remaining: none for this acceptance/documentation closure.

Non-blocking follow-ups deferred:

- Capture a valid real-device, discovery-enabled, debug-mode baseline harvest
  before using NET-REL-02/03 to claim production mobile DCUtR success or reorder
  NET-REL workstreams.
- Keep the `run_transport_e2e.dart` E8 media metadata residual separate unless
  later concrete evidence ties it to relay-only/no-upgrade behavior.

Why the session is safe to consider complete:

The stable docs now state the accepted DCUTR-001/002/003 evidence and the
remaining residuals without changing product behavior or overclaiming
production mobile NAT traversal. The decision gate remains pre-harvest, and the
only gate required by this doc-only pass passed.

## Closure Audit Verdict

Closure verdict: `accepted_with_explicit_follow_up` for DCUTR-004 doc-only
execution.

Audited: 2026-05-30 00:36 CEST.

What is closed:

- DCUTR-001 Go tracer/anti-false-upgrade evidence is accepted for its scoped
  contract.
- DCUTR-002 Dart aggregate diagnostics/privacy-safe counter evidence is accepted
  for its scoped contract.
- DCUTR-003 relay-only/no-upgrade acceptance is accepted with the already
  explicit E8 follow-up.
- DCUTR-004 stable-doc closure is accepted for source-doc, baseline-gate,
  NAT/DCUtR tracking, and transport-index wording.

Residual-only / explicit follow-up:

- Production mobile relay-to-direct DCUtR success remains unproven and
  evidence-gated until a valid real-device, discovery-enabled, debug-mode
  baseline harvest exists.
- The valid real-device baseline harvest itself remains unavailable in the
  inspected repo docs and must be captured before NET-REL-02/03 product
  decisions can claim production mobile DCUtR success.
- The repeated `run_transport_e2e.dart` E8 media metadata result remains an
  external orchestrator residual unless later evidence ties it to
  relay-only/no-upgrade behavior.

Still open:

- None for the DCUTR-004 doc-only execution scope.

Closure-audit notes:

- Closure audit validation: `git diff --check` passed after closure edits.
- `Test-Flight-Improv/test-gate-definitions.md` was not touched.
- No production code, tests, policy, event contract, metrics contract, routing,
  reachability, relay-server behavior, WebRTC, TURN, or STUN behavior was
  changed by this doc-only execution or by this closure audit.
- No stable-doc accuracy fix was necessary during closure audit.
