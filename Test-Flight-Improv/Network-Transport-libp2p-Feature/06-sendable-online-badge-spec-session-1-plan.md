# Session 1 Plan: Service-Owned Readiness Proof Model, Proof-Window Lifecycle, and Proof Instrumentation

## Final verdict

Accepted locally with bounded fallback. Session `1` landed the service-owned readiness projection, proof-window lifecycle, truthful send/inbox proof hooks, and the required direct and named-gate evidence. The only environment override needed was `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F` because the gate script otherwise stopped before execution in a multi-device Flutter environment.

## Final plan

### 1. Real scope

This session changes only the authoritative Phase 6 readiness owner and its proof-window mechanics:

- add an app-facing service-owned readiness projection that can distinguish:
  - relay-ready
  - send-capable
  - inbox-capable
  - the visible ready-state family required by the source doc
- keep relay truth bridge-owned, but keep send/inbox proof Dart-owned; do not create a second badge-readiness service or widget-local readiness inference
- start, reuse, and reset readiness proof windows on the exact Session 1 lifecycle boundaries that matter:
  - cold start
  - hot restart / already-started resync
  - degraded background resume / new recovery window
  - node stop / restart / reinitialize
  - capability-specific verification failure
- wire proof recording from:
  - successful foreground send outcomes
  - successful inbox drain / retrieval outcomes
  - the proactive proof attempts required by the source doc
- emit the new service-owned Phase 6 proof and badge timing events needed by later sessions

This session does not:

- switch the visible badge copy or semantics
- widen into relay-speed or routing-policy work
- redesign direct/local/relay/inbox send behavior
- add a second observability subsystem beyond the existing flow-event layer
- broaden proof ownership into every feature-local sender unless current code already centralizes that seam

### 2. Closure bar

Session 1 is good enough only if all of the following are true:

- one app-facing service-owned state can express the readiness inputs later sessions need without widget inference
- proof-window start, reuse, and reset rules are explicit and correctly applied across start, stop, and degraded-resume transitions
- proactive proof starts automatically on the scoped startup/resume paths, and real success can satisfy a pending proof first
- send proof alone does not unlock ready state
- inbox proof alone does not unlock ready state
- relay truth alone does not bypass the plain `Online` contract
- the required direct service/lifecycle/send tests pass
- the required named gates pass without widening the session scope

### 3. Source of truth

- active source doc:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec.md`
- active session contract:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-breakdown.md`
- regression / gate authority:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- stable scope guards:
  - `Test-Flight-Improv/10-network-measurement-strategy.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- current code/tests that beat stale prose on disagreement:
  - `lib/core/services/p2p_service.dart`
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/features/p2p/domain/models/node_state.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/core/lifecycle/background_reconnect_smoke_test.dart`
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`

On disagreement:

- current code and tests beat stale prose
- `test-gate-definitions.md` and the actual gate script define named-gate execution
- the Phase 6 source doc defines the product contract as long as repo evidence does not prove it stale

### 4. Session classification

`implementation-ready`

Reason:

- the source doc fixes the intended contract clearly enough for a bounded service-first implementation
- the likely state, lifecycle, proof-source, and event seams are all known in the current repo
- the direct tests that should pin this session are already nearby and do not require inventing a new subsystem

### 5. Exact problem statement

The repo currently exposes relay truth as the only app-facing readiness signal:

- `ConnectionStatusIndicator` and its helper treat relay-ready as the green-badge condition
- `P2PServiceImpl` emits `TIME_TO_ONLINE_BADGE` only when relay health becomes good
- `NodeState` has no app-facing send/inbox proof or proof-window fields

The repo also already has enough evidence to avoid a broader redesign:

- `send_chat_message_use_case.dart` already has truthful successful-send boundaries, including delivered inbox fallback
- `drainOfflineInbox()` already uses the durable staged-inbox path on start/resume
- `handle_app_resumed.dart` already sequences health-check and inbox-drain work, but the relay-only resume timing helpers in `P2PServiceImpl` are not currently wired through the `P2PService` interface

What must improve in Session 1:

- the service must own the readiness truth the later badge and harness work will consume
- the service must know when a new proof window begins and when old proof must be discarded
- send/inbox proof must come from real successful outcomes, not raw transport-looking hints
- proactive proof must start automatically on the scoped start/resume paths
- the new proof and timing events must exist before later benchmark and widget sessions can use them

What must stay unchanged:

- routing semantics for direct/local/relay/inbox sends
- relay ownership of relay-ready truth
- the broader measurement strategy and transport architecture

### 6. Files and repos to inspect next

Exact production files:

- `lib/core/services/p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/p2p/domain/models/node_state.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/core/debug/intro_e2e_runner.dart`

Exact direct tests:

- `test/core/services/p2p_service_impl_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`

Conditionally relevant direct suites if implementation changes the app-facing state diff or degraded-reset semantics:

- `test/core/services/p2p_service_addresses_updated_test.dart`
- `test/core/services/p2p_service_fault_injection_test.dart`

### 7. Existing tests covering this area

Already present:

- `test/core/services/p2p_service_impl_test.dart`
  - pins relay-state parsing, health-check behavior, and relay-only `TIME_TO_ONLINE_BADGE`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - pins resume sequencing through bridge health, immediate health check, and inbox drain
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - pins grouped resume follow-up behavior around the same lifecycle entry point
- `test/core/lifecycle/background_reconnect_smoke_test.dart`
  - pins degraded-to-online recovery behavior through the current relay-only readiness contract
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - pins truthful delivered outcomes for direct/local/relay and inbox-fallback send paths

Current gaps:

- no direct test proves a service-owned proof window or its reset rules
- no direct test proves send proof and inbox proof must both be present before the app is ready
- no direct test proves degraded resume cannot reuse stale pre-background proof
- no direct test proves proactive proof can move the app toward readiness without user action
- no direct test proves a real successful send can satisfy pending proof without changing transport semantics
- no direct test proves the new Phase 6 events are emitted from service-owned readiness transitions

### 8. Regression/tests to add first

- add `p2p_service_impl` regressions for:
  - send proof alone does not unlock readiness
  - inbox proof alone does not unlock readiness
  - relay truth alone does not bypass the usable-now contract
  - proof-window reset on node stop / restart and degraded-resume transitions
  - proactive proof start on cold start and degraded resume
  - real success satisfying a pending proof before the proactive attempt finishes
  - service-owned Phase 6 event emission
- add lifecycle regressions for:
  - degraded resume invalidating stale pre-background proof
  - no-user-action resume/start paths still beginning proactive proof
- extend `send_chat_message_use_case_test.dart` or an adjacent narrow collaborator test so a truthful successful send outcome records send proof without changing delivery semantics or routing

### 9. Step-by-step implementation plan

1. Inspect and choose the smallest additive app-facing readiness shape.
   Prefer one service-owned projection consumed through existing `currentState` / `stateStream` seams instead of a second stream or badge-only state object.
   If `NodeState` carries the new fields, make sure its copy/update path can explicitly clear stale proof state rather than inheriting nullable values forever.
2. Add centralized proof-window bookkeeping in `P2PServiceImpl`.
   This should include:
   - current proof-window identity or equivalent reset token
   - send/inbox proof flags plus source details as needed for later events
   - helpers to start, reset, and invalidate proof on the scoped lifecycle boundaries
3. Wire actual lifecycle entry points to the new bookkeeping.
   Current evidence shows `markResumeStarted()` and `checkResumeAlreadyOnline()` exist only on `P2PServiceImpl`, while `handle_app_resumed.dart` receives a `P2PService` interface.
   Either expose the minimum additive interface needed for readiness-proof lifecycle tracking or replace the dormant relay-only helper path with a narrower Phase 6-safe alternative.
4. Add proof recording for real successful outcomes.
   - send proof: record only from truthful successful Dart-side send outcomes
   - inbox proof: record only from successful inbox drain / retrieval outcomes in the current window
   Do not infer proof from connection counts, relay state, listen addresses, or bridge health.
5. Start proactive proof on the scoped start/resume flows.
   Reuse the existing inbox-drain path for inbox proof.
   For send proof, use the smallest safe proactive mechanism that stays inside Phase 6 scope.
   Stop and refresh the plan instead of widening scope if the only viable option would redesign routing or send architecture.
6. Emit the Phase 6 service-owned events.
   Keep existing relay-outage / relay-recovery instrumentation intact where still truthful, and add the new proof-window / sendable / relay-ready events alongside it.
7. Land the direct regressions first or alongside the implementation, then run the exact tests and named gates below.

Stop rule:

- if the proactive send-proof requirement cannot be implemented safely without a broader transport redesign, a new backend contract, or widget-local fake proof, stop and mark the session blocked instead of widening scope
- if the chosen app-facing state shape cannot clear stale proof truthfully inside the existing `NodeState` update path, stop and tighten that shape before adding more behavior

### 10. Risks and edge cases

- `NodeState.copyWith(...)` currently uses `??` semantics for nullable fields, which can make stale nullable proof fields hard to clear if the new state shape is not designed carefully
- `handle_app_resumed.dart` only sees the `P2PService` interface today, so dormant `P2PServiceImpl` resume timing helpers are not usable without a narrow interface or lifecycle adjustment
- the public `retrieveInbox()` API still calls destructive `inbox:retrieve`, while proactive startup/resume flows already use durable `drainOfflineInbox()`; Session 1 must not accidentally mix those paths into misleading proof behavior
- additive readiness fields can widen state-diff churn and break tests if they are not threaded carefully through `_stateMeaningfullyChanged(...)`
- proactive send proof must not send visible user content or silently change routing policy
- service-owned proof events must not double-count when a proactive proof and a real user success land in the same window

### 11. Exact tests and gates to run

Direct tests:

- `flutter test test/core/services/p2p_service_impl_test.dart`
- `flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `flutter test test/core/lifecycle/background_reconnect_smoke_test.dart`
- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`

Named gates:

- `./scripts/run_test_gates.sh transport`
- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh baseline`

Conditional direct suites only if implementation touches those seams materially:

- `flutter test test/core/services/p2p_service_addresses_updated_test.dart`
- `flutter test test/core/services/p2p_service_fault_injection_test.dart`

### 12. Known-failure interpretation

- This plan does not currently rely on a documented known failure for the required direct tests.
- Treat a failing new Session 1 regression as a real blocker.
- If a named gate fails, compare against current HEAD and existing gate notes before attributing it to Session 1, but do not relabel a readiness-proof regression as legacy noise.
- A gate failure caused by unrelated device/environment setup should be recorded as such only if the failure is clearly outside the changed readiness/send/inbox seam.

### 13. Done criteria

- one service-owned readiness state or equivalent app-facing projection now distinguishes the Phase 6 readiness inputs truthfully
- proof-window start, reset, and invalidation behavior is implemented for the scoped lifecycle boundaries
- proactive proof starts on the scoped startup/resume paths
- send/inbox proof comes only from truthful successful outcomes
- the new Phase 6 service-owned events exist and are covered by direct tests
- all required direct tests pass
- `transport`, `1to1`, and `baseline` pass

### 14. Scope guard

- do not change visible badge copy, semantics, or dot rendering in this session
- do not redesign routing policy, relay reservation behavior, or inbox transport semantics
- do not add a second readiness owner outside `P2PService`
- do not add a new metrics/export framework
- do not broaden proof producers to every feature-local sender unless current code already centralizes that seam cleanly

### 15. Accepted differences / intentionally out of scope

- the exact internal storage shape for proof-window state may vary as long as the service remains the only authoritative owner exposed to the app
- the proactive send-proof mechanism may vary, but only within the existing transport architecture and Phase 6 scope guard
- Session 1 need not finalize public widget rendering or benchmark/reporting output; those belong to Sessions `2` and `3`

### 16. Dependency impact

- Session `2` depends on this session to expose a truthful app-facing readiness state for the badge to render
- Session `3` depends on this session to expose proof-window IDs / sources and the sendable-vs-relay-ready timing events
- if Session 1 must widen into a bigger transport redesign to satisfy proactive send proof, the breakdown must be refreshed before Sessions `2` and `3` proceed

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- broadening send-proof producers beyond the narrow shared send-success seam plus the proactive proof path
- maintenance-doc wording changes for measurement or 1:1 closure references; those belong to final closure only if the landed result truly changes stable maintenance guidance

## Accepted differences intentionally left unchanged

- relay-ready truth remains bridge-owned
- public widget semantics and copy remain unchanged until Session `2`
- benchmark/reporting split and device-backed acceptance remain unchanged until Session `3`

## Exact docs/files used as evidence

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/10-network-measurement-strategy.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `lib/core/services/p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/p2p/domain/models/node_state.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/core/debug/intro_e2e_runner.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`

## Why the plan is safe to implement now

- The source doc fixes the product contract tightly enough that Session 1 can stay inside one bounded service/lifecycle seam.
- Current repo evidence already shows where the truth must live and where the hooks already exist:
  - `P2PServiceImpl` owns the app-facing state stream
  - `send_chat_message_use_case.dart` already defines truthful successful-send outcomes
  - `drainOfflineInbox()` already owns the durable proactive inbox path
- The main ambiguity is the safe proactive send-proof path, and the plan has an explicit stop rule if that seam would require a broader redesign instead of a narrow additive implementation.

## Execution evidence

- Production seams landed:
  - `lib/core/services/p2p_service.dart`
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/features/p2p/domain/models/node_state.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
- Direct regressions passed:
  - `flutter test test/core/services/p2p_service_impl_test.dart`
  - `flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/core/lifecycle/background_reconnect_smoke_test.dart test/features/conversation/application/send_chat_message_use_case_test.dart`
- Named gates passed:
  - `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`
  - `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh 1to1`
  - `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline`
- Session `1` remains within scope:
  - no visible badge-copy or semantics change yet
  - no benchmark/reporting split yet
  - no routing-policy redesign
