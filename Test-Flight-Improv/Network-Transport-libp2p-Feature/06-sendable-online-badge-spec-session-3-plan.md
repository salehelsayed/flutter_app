# Session 3 Plan: Benchmark Split, Transport Acceptance, and Rollout Closure

## Final verdict

Accepted locally with bounded fallback and an explicit physical-device follow-up. Session `3` stayed inside the intended measurement and acceptance seam: the benchmark helpers and direct/per-device harnesses now consume the Phase 6 service-owned event contract, the direct benchmark suite passed, the direct simulator benchmark harnesses for startup, background resume, and relay recovery all passed on simulator `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and the `transport`, `1to1`, plus `baseline` gates all passed on the same simulator. The remaining unexecuted surface in this environment is the real-device-only path of `integration_test/background_reconnect_test.dart`, which was updated and included in the transport gate but skipped on the simulator.

## Final plan

### 1. Real scope

This session changes only the benchmark and acceptance seam:

- update the benchmark helpers and paired performance tests to consume:
  - `TIME_TO_SENDABLE_BADGE`
  - `TIME_TO_RELAY_READY_BADGE`
  - `FIRST_SEND_SUCCESS_IN_WINDOW`
  - `FIRST_INBOX_SUCCESS_IN_WINDOW`
- preserve relay-ready timing as the secondary dotted-badge metric instead of treating legacy relay-only green timing as the primary result
- derive and print the required Phase 6 metrics:
  - `resume_to_sendable_ms`
  - `resume_to_relay_ready_ms`
  - `resume_to_first_send_success_ms`
  - `resume_to_first_inbox_success_ms`
  - `sendable_to_relay_ready_gap_ms`
  - `badge_honesty_gap_ms`
- adapt the background reconnect smoke so it can validate the Phase 6 product contract with the real service-owned badge state instead of relay-only `ConnectionHealth.online`
- keep the service owner, routing policy, and widget renderer unchanged unless a measurement surface cannot read the already-landed Phase 6 truth without a tiny compatibility helper

This session does not:

- redesign direct/local/relay/inbox routing behavior
- change the Phase 6 proof-window owner from `P2PService`
- redesign badge visuals or semantics
- widen into general transport performance tuning

### 2. Closure bar

Session `3` is good enough only if all of the following are true:

- the benchmark harnesses read the service-owned Phase 6 event contract instead of treating relay-only `TIME_TO_ONLINE_BADGE` as the badge truth
- direct benchmark tests cover the sendable-versus-relay-ready split for cold start, degraded resume, and recovery
- the real-stack benchmark harnesses print the Phase 6 split metrics and source attribution from the service-owned flow events
- the device/background smoke uses the Phase 6 badge state and proves the usable badge contract without waiting only for dotted relay truth
- direct benchmark tests pass
- `transport`, `1to1`, and `baseline` still pass

### 3. Source of truth

- active source doc:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec.md`
- active session contract:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-breakdown.md`
- regression / gate authority:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- benchmark / smoke seam:
  - `integration_test/benchmark_helpers.dart`
  - `integration_test/benchmark_time_to_online_harness.dart`
  - `integration_test/benchmark_background_resume_harness.dart`
  - `integration_test/benchmark_relay_recovery_harness.dart`
  - `integration_test/background_reconnect_test.dart`
  - `test/performance/benchmark_harness.dart`
  - `test/performance/benchmark_time_to_online_test.dart`
  - `test/performance/benchmark_background_resume_test.dart`
  - `test/performance/benchmark_relay_recovery_test.dart`

On disagreement:

- current code and direct tests beat stale prose
- the Phase 6 spec fixes the measurement contract
- named gates stay authoritative for shared regression coverage

### 4. Session classification

`implementation-ready`

Reason:

- the service already emits the required Phase 6 events
- Session `2` kept the widget seam compatible long enough for this migration
- the remaining work is concentrated in harness helpers, benchmark assertions, and one device smoke surface

### 5. Exact problem statement

The current benchmark and smoke surfaces still assume relay-ready equals the first green badge:

- `integration_test/benchmark_*` harnesses still read `TIME_TO_ONLINE_BADGE` and `waitForOnline(...)`
- `test/performance/benchmark_*` tests still assert relay-only badge timing rather than Phase 6 sendable timing
- `integration_test/background_reconnect_test.dart` still polls `ConnectionHealth.online`

What must improve:

- benchmark metrics must come from the service-owned Phase 6 events already emitted by `P2PServiceImpl`
- sendable and relay-ready timing must be reported separately
- smoke/acceptance surfaces must use `NodeState.badgeReadinessState` when they reason about the user-visible badge

What must stay unchanged:

- relay-ready timing remains measurable
- the rollout stays additive and compatibility-minded for legacy helpers used outside this doc's seam
- the service-owned readiness logic from Session `1` remains the source of truth

### 6. Files and repos to inspect next

Production / integration helpers:

- `integration_test/benchmark_helpers.dart`
- `integration_test/benchmark_time_to_online_harness.dart`
- `integration_test/benchmark_background_resume_harness.dart`
- `integration_test/benchmark_relay_recovery_harness.dart`
- `integration_test/background_reconnect_test.dart`

Direct tests:

- `test/performance/benchmark_harness.dart`
- `test/performance/benchmark_time_to_online_test.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `test/performance/benchmark_relay_recovery_test.dart`

### 7. Existing tests covering this area

Already present:

- direct benchmark suites for cold start, resume, and relay recovery
- device-backed benchmark harnesses for the same families
- background reconnect smoke on the real bridge

Current gaps:

- the direct benchmark suites do not yet assert the Phase 6 sendable-versus-relay-ready split
- the integration harnesses do not yet print `resume_to_sendable_ms`, `resume_to_relay_ready_ms`, or the honesty/gap metrics from shared `proofWindowId`
- the device smoke still reasons about relay-only health instead of the visible badge state

### 8. Regression/tests to add first

- add helper coverage for waiting on:
  - sendable badge reached
  - plain `Online`
  - dotted `Online.`
- update direct benchmark tests to assert the Phase 6 events and shared `proofWindowId` relationships
- update the real benchmark harnesses to print the Phase 6 metrics from event details instead of relay-only badge timing
- update the background reconnect smoke to validate the Phase 6 badge states and real send/inbox operations in the usable window

### 9. Step-by-step implementation plan

1. Add bounded benchmark-helper utilities for Phase 6 badge-state waiting and event lookup/derivation.
2. Migrate the direct benchmark tests to those helpers and assert the new Phase 6 event contract.
3. Migrate the three real benchmark harnesses so they print sendable, relay-ready, first-send, first-inbox, honesty-gap, and attribution metrics from the service-owned events.
4. Tighten `background_reconnect_test.dart` so it reasons about `NodeState.badgeReadinessState` and validates the usable badge window plus later relay-ready upgrade.
5. Run the direct benchmark suites.
6. Run the required named gates:
   - `transport`
   - `1to1`
   - `baseline`
7. Update the breakdown ledger and close the rollout only if the evidence stays green.

Stop rule:

- if a measurement surface cannot read the landed Phase 6 truth without reopening the service-owner contract or redesigning routing, stop and refresh the breakdown instead of widening scope

### 10. Risks and edge cases

- warm-background work is asynchronous, so direct tests must wait for the service-owned events instead of assuming `startNode(...)` captures them synchronously
- some runs may collapse `Online` and `Online.` into the same instant; the harnesses must report that honestly instead of manufacturing a gap
- healthy resume may still use the existing already-online compatibility signal if no new proof window is created
- device smoke must not rely on widget-local inference or punctuation-only checks

### 11. Exact tests and gates to run

Direct tests:

- `flutter test test/performance/benchmark_time_to_online_test.dart test/performance/benchmark_background_resume_test.dart test/performance/benchmark_relay_recovery_test.dart`

Named gates:

- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`
- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh 1to1`
- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline`

Optional direct device-backed spot checks if a named gate failure points at this seam:

- `flutter test integration_test/benchmark_time_to_online_harness.dart -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
- `flutter test integration_test/benchmark_background_resume_harness.dart -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
- `flutter test integration_test/benchmark_relay_recovery_harness.dart -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F`

### 12. Known-failure interpretation

- direct benchmark failures are real blockers because this session changes the event contract those tests are meant to guard
- a named-gate failure in transport or shared baseline coverage is a blocker unless it is clearly unrelated to the touched files
- `background_reconnect_test.dart` remains platform-conditional; a simulator skip is not itself a blocker

### 13. Done criteria

- direct benchmark tests assert the Phase 6 event contract
- integration harnesses print the required Phase 6 split metrics and attribution
- device/background smoke reasons about sendable/dotted badge states instead of relay-only online
- direct benchmark tests pass
- `transport`, `1to1`, and `baseline` pass
- the breakdown ledger is updated to a finished rollout verdict

### 14. Scope guard

- do not redesign routing policy
- do not move readiness ownership out of `P2PService`
- do not change badge copy or styling
- do not widen into unrelated benchmark families outside the Phase 6 seam

### 15. Accepted differences / intentionally out of scope

- legacy `TIME_TO_ONLINE_BADGE` may remain for compatibility as long as the updated harnesses no longer treat it as the canonical sendable metric
- widget timing remains supplementary; Session `3` does not require new widget event names
- stable maintenance docs are updated only if the final accepted evidence changes their long-lived wording materially

### 16. Dependency impact

- this is the final execution session for the rollout; closure docs and any stable maintenance-note updates depend on its accepted evidence

## Structural blockers remaining

- none

## Execution evidence

Landed files:

- `lib/core/services/p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `test/performance/benchmark_harness.dart`
- `test/performance/benchmark_time_to_online_test.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `test/performance/benchmark_relay_recovery_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/core/services/fake_p2p_service.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `integration_test/benchmark_helpers.dart`
- `integration_test/benchmark_time_to_online_harness.dart`
- `integration_test/benchmark_background_resume_harness.dart`
- `integration_test/benchmark_relay_recovery_harness.dart`
- `integration_test/background_reconnect_test.dart`

Direct verification:

- `flutter test test/performance/benchmark_time_to_online_test.dart test/performance/benchmark_background_resume_test.dart test/performance/benchmark_relay_recovery_test.dart`
- `flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart test/performance/benchmark_background_resume_test.dart`

Direct simulator harness verification:

- `flutter test integration_test/benchmark_time_to_online_harness.dart -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
- `flutter test integration_test/benchmark_background_resume_harness.dart -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
- `flutter test integration_test/benchmark_relay_recovery_harness.dart -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F`

Named gate verification:

- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`
- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh 1to1`
- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline`

Accepted implementation notes:

- the benchmark helpers now expose Phase 6 badge-state waiters plus proof-window metric derivation helpers
- the direct benchmark tests now assert `TIME_TO_SENDABLE_BADGE`, `TIME_TO_RELAY_READY_BADGE`, and shared `proofWindowId` relationships instead of relay-only badge timing
- `handleAppResumed()` now preserves a caller-owned resume marker long enough for the real app lifecycle to emit the healthy `background_resume_already_online` compatibility signal after resume completion, while still clearing internally-owned resume markers for direct callers
- the real benchmark harnesses now print:
  - `resume_to_sendable_ms`
  - `resume_to_relay_ready_ms`
  - `resume_to_first_send_success_ms`
  - `resume_to_first_inbox_success_ms`
  - `sendable_to_relay_ready_gap_ms`
  - `badge_honesty_gap_ms`
- `integration_test/background_reconnect_test.dart` now validates the Phase 6 badge states and plain-`Online` window semantics, but its real-device path was not executed in this simulator-only environment

## Exact docs/files used as evidence

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `integration_test/benchmark_helpers.dart`
- `integration_test/benchmark_time_to_online_harness.dart`
- `integration_test/benchmark_background_resume_harness.dart`
- `integration_test/benchmark_relay_recovery_harness.dart`
- `integration_test/background_reconnect_test.dart`
- `test/performance/benchmark_harness.dart`
- `test/performance/benchmark_time_to_online_test.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `test/performance/benchmark_relay_recovery_test.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/p2p/domain/models/node_state.dart`

## Why the plan is safe to implement now

- the Phase 6 event contract already exists in the service, so Session `3` can stay focused on consumers and acceptance surfaces
- the remaining files are all measurement or smoke surfaces rather than product logic owners
- the required gates are known and already align with the breakdown contract
