Status: accepted

# DCUTR-001 Go DCUtR Observation And Anti-False-Upgrade Controls Plan

## Planning Progress

- 2026-05-29 23:27 CEST - Arbiter completed. Files inspected since prior update: reviewer findings and final plan sections. Decision: no structural blockers; plan is reusable for DCUTR-001 execution only. Next: downstream execution/QA may consume this file.
- 2026-05-29 23:26 CEST - Arbiter started. Files inspected since prior update: reviewer findings. Decision: classify reviewer feedback into blockers/details/accepted differences. Next: finalize reusable status if no structural blocker remains.
- 2026-05-29 23:25 CEST - Reviewer completed. Files inspected since prior update: plan draft only. Decision: sufficient with one incremental detail accepted; no missing Flutter simulator gate and no structural blocker. Next: arbiter classification.
- 2026-05-29 23:23 CEST - Planner completed. Files inspected since prior update: `go-mknoon/node/*holepunch*`, `transport_label_test.go`, and focused test search for stale upgrade assertions. Decision: draft includes one likely missing regression for stale limited connection state while preserving verification-first execution. Next: reviewer pass.
- 2026-05-29 23:19 CEST - Planner started. Files inspected since prior update: no new files. Decision: produce a narrow verification-first plan with targeted implementation only if current code/tests fail the contract. Next: write durable plan sections.

## Execution Progress

- 2026-05-29 23:22 CEST - Phase: QA Reviewer started. Files inspected or touched: plan, breakdown, Executor result, and scoped DCUTR-001 diff read-only; plan progress touched. Command: none yet. Decision: fresh QA review is limited to DCUTR-001; no code fixes, Flutter/mobile gates, relay-server behavior, or production reachability-policy changes. Next: verify scoped diff, required evidence, gate sufficiency, and done criteria.
- 2026-05-29 23:20 CEST - Phase: Executor verification/result summary. Files inspected or touched: plan progress only after tests. Command: `cd go-mknoon && go test ./node -run 'TestHolePunchTracer|TestClassifyStreamTransport|TestHolePunchFeasibility|TestHolePunchNegativeControl'` -> PASS (`ok github.com/mknoon/go-mknoon/node 12.600s`); `git diff --check` -> PASS; `date '+%Y-%m-%d %H:%M %Z'`. Decision: focused DCUTR-001 Go contract is satisfied by existing Go code/tests plus the narrow NAT doc correction; no gate failure to triage; broader `cd go-mknoon && go test ./node` not run because no Go production/shared helper files were changed by this Executor. Result: ready for controller/QA review; final execution verdict intentionally not written here.
- 2026-05-29 23:21 CEST - Phase: Executor completed / QA spawn requested. Files inspected or touched: Executor result `/tmp/dcutr001-executor-result.md`, execution progress only. Command: nested Executor `019e759a-6808-7623-b865-1e3721349a9e` completed. Decision: Executor produced trustworthy code/doc delta and exact required test evidence; no hidden state is needed beyond files and result output. Next: spawn fresh QA Reviewer with `model=gpt-5.5`, `model_reasoning_effort=xhigh`.
- 2026-05-29 23:21 CEST - Phase: QA Reviewer spawned/running. Files inspected or touched: execution progress only. Command: nested `codex exec` session `019e759d-7f6d-73e3-b31a-76d2984ca4b0` with `model=gpt-5.5`, `model_reasoning_effort=xhigh`, approval `never`, sandbox `danger-full-access`. Decision: spawned-agent isolation active for QA Reviewer. Next: bounded wait for QA sufficiency findings.
- 2026-05-29 23:20 CEST - Phase: Executor doc correction. Files inspected or touched: `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, plan progress. Command: `apply_patch`, `date '+%Y-%m-%d %H:%M %Z'`. Decision: no Go production edit required; doc wording now reflects the current Go tracer observation seam while preserving production-private reachability, feasibility-only loopback wording, relay-only negative-control semantics, and no production DCUtR success claim. Next: run the required focused Go command and `git diff --check`.
- 2026-05-29 23:19 CEST - Phase: Executor scoped inspection. Files inspected or touched: `go-mknoon/node/holepunch_tracer_test.go`, `go-mknoon/node/holepunch_tracer.go`, `go-mknoon/node/node.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/transport_label_test.go`, `go-mknoon/node/holepunch_feasibility_test.go`, `go-mknoon/node/holepunch_negative_control_test.go`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`, plan progress. Command: `sed`/`rg` inspection and `date '+%Y-%m-%d %H:%M %Z'`. Decision: `TestHolePunchTracer_SuccessClearsStaleLimitedConnectionState` already exists and covers clearing stale `Limited` state after tracer success; production `holepunch.WithTracer` and `ForceReachabilityPrivate()` are already correct; classifier, feasibility, negative-control, and event payload docs preserve the required anti-overclaim semantics. NAT/DCUtR doc still contains stale no-tracer/no-code wording. Next: patch only narrow NAT doc wording, then run the required focused Go command and `git diff --check`.
- 2026-05-29 23:17 CEST - Phase: controller re-entry / contract extracted. Files inspected or touched: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`, skill instructions. Command: `sed -n '1,260p' ...`, `codex exec --help`. Decision: execute DCUTR-001 only; prior hidden child-agent state is unavailable, but `codex exec` is available for fresh spawned Executor/QA agents with `model=gpt-5.5` and `model_reasoning_effort=xhigh`. Next: spawn fresh Executor for the plan's focused Go implementation/verification pass.
- 2026-05-29 23:17 CEST - Phase: Executor spawn retry. Files inspected or touched: `~/.codex/config.toml`, `codex exec --help`, execution progress only. Command: initial `codex exec ... -a never ...` rejected before child start because this subcommand does not accept `-a`; config already has `approval_policy = "never"`. Decision: no child work materialized and no code/test delta exists from the failed spawn. Next: retry Executor with accepted `codex exec` options, `model=gpt-5.5`, and `model_reasoning_effort=xhigh`.
- 2026-05-29 23:17 CEST - Phase: Executor spawned/running. Files inspected or touched: execution progress only. Command: nested `codex exec` session `019e759a-6808-7623-b865-1e3721349a9e` with `model=gpt-5.5`, `model_reasoning_effort=xhigh`, approval `never`, sandbox `danger-full-access`. Decision: spawned-agent isolation active for Executor. Next: bounded wait for implementation/test evidence.
- 2026-05-29 23:14 CEST - Phase: before contract extraction / dirty-worktree snapshot. Files inspected or touched: plan and breakdown read only; no code edits. Command: `git status --short`. Decision: existing dirty worktree is user-owned context; record it before any code/test edits. Next: extract DCUTR-001 contract and spawn isolated Executor.

```text
 M Network-Arch/Transport-Reliability/00-INDEX.md
 M Network-Arch/Transport-Reliability/01-lan-wifi-reliability.md
 M Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md
 M go-mknoon/bridge/events.go
 M go-mknoon/node/node.go
 M go-mknoon/node/transport_label_test.go
 M info.plist
 M integration_test/wifi_transport_test.dart
 M lib/core/bridge/bridge.dart
 M lib/core/bridge/go_bridge_client.dart
 M lib/core/local_discovery/bonsoir_discovery_service.dart
 M lib/core/local_discovery/disabled_local_discovery_service.dart
 M lib/core/local_discovery/local_discovery_service.dart
 M lib/core/local_discovery/local_p2p_service.dart
 M lib/core/local_discovery/local_ws_server.dart
 M lib/core/services/p2p_service.dart
 M lib/core/services/p2p_service_impl.dart
 M lib/core/utils/flow_event_emitter.dart
 M lib/features/conversation/application/send_chat_message_use_case.dart
 M lib/features/conversation/presentation/screens/conversation_wired.dart
 M lib/features/feed/presentation/screens/feed_wired.dart
 M lib/features/identity/presentation/startup_router.dart
 M lib/features/settings/presentation/screens/settings_wired.dart
 M lib/main.dart
 M test/core/local_discovery/fake_local_discovery_service.dart
 M test/core/local_discovery/fake_local_p2p_service.dart
 M test/core/local_discovery/local_p2p_service_test.dart
 M test/core/resilience/c2_ack_drop_test.dart
 M test/core/resilience/c3_half_open_test.dart
 M test/core/services/fake_p2p_service.dart
 M test/core/services/incoming_message_router_posts_engagement_test.dart
 M test/core/services/incoming_message_router_posts_pass_test.dart
 M test/core/services/incoming_message_router_posts_pins_test.dart
 M test/core/services/incoming_message_router_posts_presence_test.dart
 M test/core/services/incoming_message_router_posts_test.dart
 M test/core/services/incoming_message_router_profile_test.dart
 M test/core/services/incoming_message_router_test.dart
 M test/core/services/p2p_service_fault_injection_test.dart
 M test/features/contact_request/application/accept_and_reciprocate_use_case_test.dart
 M test/features/contact_request/application/send_contact_request_use_case_test.dart
 M test/features/conversation/application/send_chat_message_no_bg_task_test.dart
 M test/features/conversation/application/send_chat_message_use_case_test.dart
 M test/features/conversation/application/send_voice_message_no_bg_task_test.dart
 M test/features/conversation/integration/send_then_lock_delivery_test.dart
 M test/features/conversation/integration/two_user_message_exchange_test.dart
 M test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart
 M test/features/conversation/presentation/screens/conversation_wired_gif_test.dart
 M test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart
 M test/features/conversation/presentation/screens/conversation_wired_test.dart
 M test/features/feed/presentation/screens/feed_wired_bg_task_test.dart
 M test/features/groups/application/send_group_message_use_case_test.dart
 M test/features/identity/presentation/screens/startup_router_test.dart
 M test/features/introduction/integration/intro_wiring_smoke_test.dart
 M test/features/push/application/register_push_token_use_case_test.dart
 M test/features/settings/application/upload_profile_picture_use_case_test.dart
 M test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart
 M test/features/settings/presentation/screens/settings_wired_test.dart
 M test/shared/fakes/fake_p2p_service_integration.dart
?? Network-Arch/Transport-Reliability/01-lan-wifi-IMPLEMENTATION-PLAN.md
?? Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md
?? Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md
?? Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-HARVEST-DECISION.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-001-plan.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-002-plan.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-003-plan.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-004-plan.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-005-plan.md
?? Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md
?? Test-Flight-Improv/99-transport-observability-and-metrics.md
?? Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md
?? Test-Flight-Improv/NET-REL-04-baseline-harvest-runbook.md
?? go-mknoon/node/holepunch_feasibility_test.go
?? go-mknoon/node/holepunch_negative_control_test.go
?? go-mknoon/node/holepunch_tracer.go
?? go-mknoon/node/holepunch_tracer_test.go
?? go-relay-server/metrics_test.go
?? lib/core/debug/transport_metrics.dart
?? lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart
?? test/core/debug/
?? test/core/local_discovery/local_peer_ttl_test.dart
?? test/core/local_discovery/local_ws_integration_i1_i2_test.dart
?? test/core/services/p2p_service_inbound_transport_test.dart
?? test/core/services/p2p_service_lan_availability_test.dart
?? test/core/services/p2p_service_local_media_wiring_test.dart
?? test/core/services/p2p_service_transport_census_test.dart
?? test/core/services/p2p_service_transport_latency_test.dart
?? test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart
```

- 2026-05-29 23:14 CEST - Phase: after contract extraction. Files inspected or touched: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md`, `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`. Command: none. Decision: DCUTR-001 is host-only Go proof; no Flutter device/simulator availability check is required. Exact scope is Go tracer/node/classifier/negative-control/doc wording only, production `ForceReachabilityPrivate()` must remain unchanged, and production DCUtR success must not be claimed from loopback, LAN, simulator, or label-mapping evidence. Next: spawn isolated Executor for the focused implementation/verification pass.
- 2026-05-29 23:14 CEST - Phase: Executor spawn requested / before implementation. Files inspected or touched: execution progress only. Command: none. Decision: implementation must be isolated in a fresh Executor agent; no production code edits have been made by this controller. Next: Executor inspects scoped files, adds or verifies `TestHolePunchTracer_SuccessClearsStaleLimitedConnectionState`, runs required Go/profile commands, and records results here.
- 2026-05-29 23:14 CEST - Phase: Executor spawned/running. Files inspected or touched: execution progress only. Command: nested agent `019e7597-4add-7bc3-814e-4444a01f26b1` (`Linnaeus`) with `model=gpt-5.5`, `reasoning_effort=xhigh`. Decision: spawned-agent isolation is active after one corrected spawn retry; next action is bounded wait for Executor completion evidence.
- 2026-05-29 23:15 CEST - Phase: Executor before implementation / scoped inspection. Files inspected or touched: `go-mknoon/node/holepunch_tracer_test.go`, `go-mknoon/node/holepunch_tracer.go`, `go-mknoon/node/node.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/transport_label_test.go`, `go-mknoon/node/holepunch_feasibility_test.go`, `go-mknoon/node/holepunch_negative_control_test.go`, `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`; plan progress touched. Command: inspection only plus `date '+%Y-%m-%d %H:%M %Z'`. Decision: `holepunch.WithTracer` and production `ForceReachabilityPrivate()` are already present, classifier/feasibility/negative-control tests contain the required anti-overclaim wording, `bridge/events.go` documents the current event names, the stale limited-state tracer regression is missing, and the NAT doc still has stale no-tracer/no-code wording. No Flutter device/simulator availability check is required for this host-only Go row. Next: add the focused stale-state regression and narrow NAT doc correction without changing production reachability or Flutter surfaces.

## real scope

This session owns the Go-side DCUtR observation contract only.

In scope:

- Verify or complete `holepunch.WithTracer` installation in `go-mknoon/node/node.go`.
- Preserve production `libp2p.ForceReachabilityPrivate()` and keep `ForceReachabilityPublic()` behind the explicit test-only seam.
- Verify or complete Go events and counters for hole-punch attempts, successes, failures, and `transport:upgraded`.
- Verify or complete stale connection-state correction after a real tracer success.
- Verify classifier tests say exactly what they prove: stream multiaddr label mapping, not real DCUtR proof.
- Verify feasibility and negative-control tests classify loopback/public-reachability behavior as protocol feasibility and relay-only/private behavior as the dominant production-shaped case.
- Update `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md` only if execution confirms its current wording still contradicts current Go behavior.

Out of scope:

- No production reachability-policy change.
- No AutoNAT, routing, WebRTC, TURN/STUN, relay-server, Dart metrics, Flutter UI, or simulator/device app work.
- No claim that loopback feasibility, LAN direct dial, or simulator evidence proves production DCUtR success.

## closure bar

The session is good enough when the Go node can truthfully observe DCUtR without changing reachability behavior and the tests prevent false upgrade evidence.

Coverage ledger:

| Requirement | Planned proof |
|------|------|
| `holepunch.WithTracer` installed | Inspect `go-mknoon/node/node.go`; focused Go tests must compile against the tracer seam. |
| Production reachability remains private | Inspect `node.go`; tests use `SetForcePublicReachabilityForTests(true)` only in feasibility setup and leave it false in negative control. |
| Attempt/success/failure events emitted | `TestHolePunchTracer_AttemptThenSuccess_CountsAndEmits` and `TestHolePunchTracer_FailureAndNoEnd_NoSuccessEmitted`; add a narrow subtest only if execution finds a missing failure/event case. |
| `transport:upgraded` emitted only on real success path | Tracer unit success test expects one upgrade event; failure/no-end tests and relay-only negative control expect zero. |
| Stale connection state corrected after upgrade | Add or verify a focused `holepunch_tracer_test.go` regression that preloads a stale limited connection entry, drives a successful `EndHolePunchEvt`, and asserts `Limited` is cleared without requiring a real network upgrade. |
| Public reachability seam remains feasibility-only | `holepunch_feasibility_test.go` comments/setup plus plan scope guard; test may skip and must not be used as production evidence. |
| Classifier tests distinguish mapping from proof | `transport_label_test.go` comments and tests must keep stub classifier evidence separate from real `Limited == true`/non-circuit proof. |
| Relay-only case does not manufacture upgrades | `TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash` must assert relay-limited connection throughout, exact zero attempts/successes, no upgrade event, and stable connection count. |

## source of truth

- Active session contract: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`, row `DCUTR-001`.
- Product/test intent: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`.
- Go behavior and tests: current working tree under `go-mknoon/node/` and `go-mknoon/bridge/events.go`.
- NAT/DCUtR architecture wording: `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`.
- Gate rules: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` if named Flutter gates are relevant. For this session, they are not.

If prose and code disagree, current code plus focused tests win for implementation. If gate docs and script disagree, the script wins, but this session should not need a Flutter named gate.

## session classification

`implementation-ready`

Reason: the current dirty tree already appears to contain most Go-side seams, but execution still has a concrete likely gap to verify or fill: a focused stale-connection-state regression. Implementation is narrow, deterministic, and host-only.

## exact problem statement

The risk is false DCUtR evidence. A per-stream `direct` label, a LAN direct dial, a loopback feasibility upgrade, or a simulator transport path can be mistaken for a production relay-to-direct DCUtR success. The Go node must report attempts, successes, failures, and relay-to-direct upgrade events only from the libp2p hole-punch tracer, keep production reachability private, repair stale connection metadata after a real upgrade, and prove relay-only peers do not emit false upgrades or thrash.

User-visible behavior must stay unchanged: relay-backed delivery remains valid, private production reachability remains the default, and this session must not promise that cellular or symmetric-NAT peers become direct.

## Device/Relay Proof Profile

This is a host-only Go proof profile.

- Direct proof uses `cd go-mknoon && go test ./node ...`.
- Relay proof is local Go circuit-relay/NW002 harness evidence, not device, simulator, or production-network evidence.
- `TestHolePunchFeasibility_LoopbackUpgradeObservable` is protocol-feasibility only. A pass proves that a controlled loopback forced-public setup can observe an upgrade; a skip means the local loopback did not materialize DCUtR and is not a failure of production delivery.
- `TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash` is the production-shaped safety control because production remains private and relay-only is a valid steady state.
- No `$run-flutter-reliability-sims` gate is required because this session does not touch Flutter mobile multi-device flows, OS notification state, integration_test, or app UI routing.
- Forbidden evidence claim: do not close production DCUtR success from loopback feasibility, LAN direct dial, simulator transport, or a `direct` stream label without a tracer success and a real non-limited non-circuit connection.

## files and repos to inspect next

Production/contract files:

- `go-mknoon/node/node.go`
- `go-mknoon/node/holepunch_tracer.go`
- `go-mknoon/bridge/events.go`
- `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md` only if behavior/docs still disagree

Focused test files:

- `go-mknoon/node/holepunch_tracer_test.go`
- `go-mknoon/node/transport_label_test.go`
- `go-mknoon/node/holepunch_feasibility_test.go`
- `go-mknoon/node/holepunch_negative_control_test.go`
- `go-mknoon/node/pubsub_delivery_test.go` only for existing NW002 helper behavior

## existing tests covering this area

- `TestHolePunchTracer_AttemptThenSuccess_CountsAndEmits` covers attempts, success counters, `holepunch:success`, and `transport:upgraded`.
- `TestHolePunchTracer_FailureAndNoEnd_NoSuccessEmitted` covers failure/no-end anti-false-success behavior.
- `TestClassifyStreamTransport_CircuitToNonCircuitFlipsRelayToDirect` covers relay/direct multiaddr mapping and explicitly says it is not upgrade proof.
- `TestClassifyStreamTransport_MixedConns_UsesStreamOwnConn` covers stream-owned connection labeling when relay and direct sibling connections exist.
- `TestHolePunchFeasibility_LoopbackUpgradeObservable` covers forced-public loopback feasibility when DCUtR materializes and skips otherwise.
- `TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash` covers the relay-only no-upgrade/no-thrash negative control.

Observed gap to verify first: no focused test was found for `markPeerUpgradedToDirect` clearing stale limited connection metadata after a tracer success.

## regression/tests to add first

Before touching production code, add or verify one focused unit regression in `go-mknoon/node/holepunch_tracer_test.go`:

- Suggested name: `TestHolePunchTracer_SuccessClearsStaleLimitedConnectionState`.
- Setup: create a tracer test node and valid remote peer ID, preload `n.connections[remote.String()]` with `Limited: true` and a circuit-looking address, then trace a successful `EndHolePunchEvt`.
- Assert: `tracer.Successes() == 1`, exactly one `transport:upgraded` event is emitted, and the saved `connectionInfo.Limited` becomes `false`.
- Optional address assertion: only assert address resampling if a real host/direct conn is part of the test. Do not fake a production DCUtR upgrade through a stub stream.

If execution discovers an equivalent regression already exists, do not duplicate it; cite it and proceed to verification.

## step-by-step implementation plan

1. Re-read the relevant dirty files before editing and treat all existing changes as user-owned.
2. Run no broad gates before implementation; use inspection and the focused test names only.
3. Add the stale limited-connection regression first if it is still missing.
4. If that test fails because `markPeerUpgradedToDirect` is incomplete, fix only `go-mknoon/node/holepunch_tracer.go` or the minimum adjacent node code needed to clear stale state on successful tracer events.
5. Verify `node.go` still installs `holepunch.WithTracer` and keeps production `ForceReachabilityPrivate()` unless `SetForcePublicReachabilityForTests(true)` is explicitly set before `Start()`.
6. Verify `bridge/events.go` documents the Go event names and payload shape already emitted by the tracer. Patch only if the docs contradict current event names.
7. Verify classifier tests preserve the mapping-vs-proof warnings. Patch only if wording or assertions overclaim a real upgrade from stub streams.
8. Verify feasibility and negative-control tests preserve the evidence classification. Patch only if they can overclaim production success, fail instead of skip for loopback non-materialization, or allow false upgrade events.
9. Inspect `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`. If it still says there is no tracer/no code changed without qualifying current working-tree behavior, update that doc narrowly to reflect the Go observation seam and keep final source-doc closure deferred to DCUTR-004.
10. Stop as soon as the Go observation contract and focused tests are satisfied. Do not start Dart metrics, Flutter diagnostics, relay recovery acceptance, or final harvest docs.

## risks and edge cases

- The feasibility test may skip because loopback DCUtR does not materialize; that is acceptable and must be reported as feasibility-limited, not hidden.
- Production `ForceReachabilityPrivate()` may legitimately result in zero hole-punch attempts; this is expected for relay-only/private cases.
- A `direct` classifier result from a non-circuit stream is not proof of DCUtR; it can be LAN/pre-relay direct dial.
- Libp2p does not necessarily emit `EvtPeerConnectednessChanged` for relay-to-direct upgrade, so stale `connections` metadata needs tracer-driven correction.
- Dirty worktree changes in the same files must be preserved; execution should patch around them, not revert.

## exact tests and gates to run

Focused command:

```bash
cd go-mknoon && go test ./node -run 'TestHolePunchTracer|TestClassifyStreamTransport|TestHolePunchFeasibility|TestHolePunchNegativeControl'
```

Broader Go node command if production node behavior, shared helpers, or NW002 helpers are touched:

```bash
cd go-mknoon && go test ./node
```

Diff hygiene:

```bash
git diff --check
```

No Flutter named gate is required for DCUTR-001. Do not run simulator, device, `integration_test`, or `$run-flutter-reliability-sims` gates for this session unless implementation unexpectedly crosses into Flutter/mobile surfaces, in which case stop and replan instead of broadening silently.

## known-failure interpretation

- `TestHolePunchFeasibility_LoopbackUpgradeObservable` may skip when loopback DCUtR does not materialize. Treat that as neutral feasibility evidence, not a pass proving production upgrade and not a failure proving production cannot upgrade.
- If the focused command fails in the new stale-state regression, fix the Go tracer/helper path.
- If relay/NW002 tests fail from local relay timing, rerun once to distinguish flake from regression, then report exact failure text and do not claim closure.
- If `cd go-mknoon && go test ./node` exposes unrelated pre-existing failures outside the focused DCUtR tests, record them separately and keep the focused command as the direct closure signal.
- `git diff --check` failures in unrelated dirty files should be reported as pre-existing only if confirmed outside this session's edits; do not clean unrelated user-owned changes.

## done criteria

- The plan's coverage ledger is satisfied with code/tests or explicit no-change evidence.
- Production `ForceReachabilityPrivate()` remains unchanged.
- Test-only public reachability remains available only through `SetForcePublicReachabilityForTests` and is described as feasibility-only.
- Tracer emits attempt, success, failure, and `transport:upgraded` events without changing connection policy.
- Stale limited connection state is corrected after a successful tracer event and covered by a focused regression or an equivalent existing test.
- Classifier tests and comments do not overclaim real upgrades from stream-label mapping.
- Relay-only negative control asserts no false attempts/successes/upgrades and no connection thrash.
- Focused Go command passes, except feasibility skip is explicitly reported as neutral.
- `cd go-mknoon && go test ./node` passes if shared node behavior was touched, or any unrelated/pre-existing failure is documented.
- `git diff --check` is clean for this session's edits.

## scope guard

Do not:

- change production reachability away from `ForceReachabilityPrivate()`;
- add AutoNAT/adaptive reachability behavior;
- change dial/send behavior to prefer or require direct paths;
- change relay server behavior;
- add Dart `TransportMetrics`, Flutter settings diagnostics, or UI work;
- use simulator/device evidence to close this Go session;
- treat loopback forced-public success, LAN direct dial, or `classifyStreamTransport == "direct"` as production DCUtR proof;
- rewrite broad transport docs beyond the narrow stale/current-behavior correction required for this session.

## accepted differences / intentionally out of scope

- Relay-only delivery is an expected successful steady state for many mobile/NAT pairs.
- Loopback forced-public DCUtR is protocol-feasibility evidence only.
- LAN/pre-relay direct dial is direct delivery but not a relay-to-direct DCUtR upgrade.
- Standard Flutter simulator transport evidence cannot prove physical NAT traversal.
- Final source-doc closure, baseline harvest, and product decision wording belong to DCUTR-004.

## dependency impact

DCUTR-002 depends on the event names and payload shape produced here for Dart bridge diagnostics and privacy-safe counters. DCUTR-003 depends on the no-false-upgrade negative control and relay-only semantics. DCUTR-004 depends on the final evidence classification from this session and must not overclaim production DCUtR success if feasibility only skips or passes locally.

If execution changes event names, payload fields, or the reachability seam, DCUTR-002 and later plans must be refreshed before execution. If execution finds the Go tracer cannot be installed safely without changing production reachability policy, stop and reclassify the session as `evidence-gated` or `prerequisite-blocked`.

## reviewer pass

Sufficiency: sufficient as-is for execution.

- Missing files/tests/gates: no structural omissions. The likely missing stale-state regression is explicitly planned first. A `ProtocolErrorEvt` failure subtest would be useful but is incremental because the failure event contract is already covered by failed `EndHolePunchEvt`.
- Stale or incorrect assumptions: none found. The plan correctly treats `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md` as potentially stale where it says no tracer/no code changed.
- Overengineering: none. The plan avoids AutoNAT, routing, relay-server, Dart, Flutter UI, and simulator work.
- Decomposition: narrow enough; it isolates Go/libp2p observation from Dart diagnostics, relay-only acceptance, and final closure sessions.
- Checklist coverage: every DCUTR-001 row requirement maps to an owner file, proof, test, or explicit out-of-scope/accepted-difference item.
- Simulator gate review: no `$run-flutter-reliability-sims` gate is required because the work is Go host-side and does not touch mobile app multi-device flows or OS/device state.

## arbiter decision

Final verdict: reusable execution-ready plan for DCUTR-001 only.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- A dedicated `ProtocolErrorEvt` subtest may be added if the implementer wants extra branch coverage, but it is not required for safe execution because the failure/no-upgrade contract is already covered by failed `EndHolePunchEvt` and relay-only negative-control tests.

Accepted differences intentionally left unchanged:

- Host-only Go tests do not prove production mobile NAT traversal.
- Loopback forced-public feasibility may pass, skip, or remain unavailable without changing the production claim.
- Relay-only delivery remains valid and is not a failed DCUtR implementation.

Exact docs/files used as evidence:

- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-breakdown.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`
- `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `go-mknoon/node/node.go`
- `go-mknoon/node/holepunch_tracer.go`
- `go-mknoon/bridge/events.go`
- `go-mknoon/node/holepunch_tracer_test.go`
- `go-mknoon/node/transport_label_test.go`
- `go-mknoon/node/holepunch_feasibility_test.go`
- `go-mknoon/node/holepunch_negative_control_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/go.mod`

Why the plan is safe to implement now:

- It has a bounded owner-file set, starts with a focused regression for the one observed gap, preserves production reachability policy, contains exact Go commands and diff hygiene, and explicitly forbids overclaiming production DCUtR success from loopback, LAN, simulator, or classifier-label evidence.

## final execution verdict

Verdict: accepted

Recorded: 2026-05-29 23:27 CEST

Files changed by this session:

- `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`
- `Test-Flight-Improv/100-nat-traversal-dcutr-evidence-session-DCUTR-001-plan.md`

Execution summary:

- Verified the Go tracer seam, production `ForceReachabilityPrivate()` default, test-only forced-public seam, event-name contract, classifier anti-overclaim wording, feasibility-only loopback wording, relay-only negative control, and existing stale limited-state repair regression.
- No Go production code change was needed for DCUTR-001. The only product-facing update was a narrow NAT/DCUtR doc correction so the architecture tracking doc no longer says the Go tracer seam is absent.
- No Dart, Flutter UI, relay-server behavior, production reachability policy, AutoNAT, WebRTC/TURN/STUN, routing, or simulator/device scope was added.

Tests and gates:

- `cd go-mknoon && go test ./node -run 'TestHolePunchTracer|TestClassifyStreamTransport|TestHolePunchFeasibility|TestHolePunchNegativeControl'` -> PASS (`ok github.com/mknoon/go-mknoon/node`, cached on controller rerun after executor PASS).
- `git diff --check` -> PASS.
- `cd go-mknoon && go test ./node` was not required because this session did not change Go production or shared helper code.
- No Flutter named gate was required for this host-only Go/doc session.

Residuals:

- Host-only Go evidence remains observation, classifier, feasibility, and negative-control evidence. It does not prove production mobile DCUtR success.
- Per-session source-doc and decision-doc closure remains assigned to DCUTR-004.

## closure audit verdict

Closure verdict: accepted for DCUTR-001. This is session-level acceptance with the explicit follow-up that final source-doc, baseline-harvest, and product-decision closure still belongs to DCUTR-004.

Recorded: 2026-05-29 23:28 CEST

Completion auditor classification:

- `accepted_with_explicit_follow_up` for the overall DCUTR evidence run because DCUTR-004 still owns final source/decision docs.
- `closed` for the DCUTR-001 Go observation row: the scoped tracer, event, private-reachability, stale-state repair, classifier-warning, feasibility-only, and relay-only negative-control evidence is present and matches the final execution verdict.

Verified closure evidence:

- Final execution verdict above is `accepted` and records the focused Go command passing: `cd go-mknoon && go test ./node -run 'TestHolePunchTracer|TestClassifyStreamTransport|TestHolePunchFeasibility|TestHolePunchNegativeControl'`.
- Final execution verdict records `git diff --check` passing.
- No tests were re-run during closure audit; this audit verified the recorded evidence and inspected the scoped files only.
- `go-mknoon/node/node.go` still installs `holepunch.WithTracer` and keeps production `libp2p.ForceReachabilityPrivate()` unless the test-only `SetForcePublicReachabilityForTests(true)` seam is enabled before `Start()`.
- `go-mknoon/node/holepunch_tracer.go` emits `holepunch:attempt`, `holepunch:success`, `holepunch:failure`, and `transport:upgraded`; successful tracer events call `markPeerUpgradedToDirect`.
- `go-mknoon/node/holepunch_tracer_test.go` covers attempt/success events, failure/no-end no-upgrade behavior, and stale `Limited` connection-state repair after a successful tracer event.
- `go-mknoon/node/transport_label_test.go`, `go-mknoon/node/holepunch_feasibility_test.go`, and `go-mknoon/node/holepunch_negative_control_test.go` preserve the anti-overclaim split between label mapping, loopback protocol feasibility, and relay-only production-shaped safety.
- `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md` now describes the Go observation seam without claiming production mobile DCUtR success.

Residual-only items:

- Host-only Go evidence remains observation, feasibility, classifier, and negative-control evidence. It does not prove production mobile DCUtR success.
- DCUTR-002, DCUTR-003, and DCUTR-004 remain pending by design; DCUTR-004 owns final source-doc and decision-doc closure.

Reopen DCUTR-001 only on a real regression in the Go tracer event contract, production-private reachability default, test-only public reachability seam, stale limited-state repair, classifier anti-overclaim wording, or relay-only no-upgrade/no-thrash safety.

Closure reviewer result: no accidental production DCUtR success claim, routing-policy change, Dart/Flutter scope expansion, relay-server scope expansion, or premature source-doc closure was introduced by this closure pass.
