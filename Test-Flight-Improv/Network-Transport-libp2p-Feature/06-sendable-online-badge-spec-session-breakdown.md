# Sendable Online Badge Session Breakdown

## Decomposition artifact

- artifact path: `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-breakdown.md`
- proposal or source doc path: `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec.md`
- decomposition date: `2026-04-19`
- downstream workflow rule:
  - detailed planning happens one session at a time
  - execution must stay inside the Phase 6 badge-semantics contract from the source doc
  - later sessions must refresh against landed code and the persisted ledger before execution
  - do not widen this rollout into relay-speed work, routing-policy redesign, or a second badge-readiness owner outside `P2PService`

## Recommended plan count

3

## Overall closure bar

This rollout is closed only when all of the following are true at the same time:

- `P2PService` / `P2PServiceImpl` becomes the single authoritative owner of the readiness contract that distinguishes:
  - `Offline`
  - `Connecting`
  - `Online`
  - `Online.`
- the service-owned readiness model proves `send-capable` and `inbox-capable` inside a valid proof window, clears stale proof on the spec-defined reset events, and does not let relay truth alone bypass the plain `Online` contract
- the badge renders the exact visible text and semantics contract from the source doc, including the non-punctuation accessibility distinction between `Online` and `Online.`
- cold start, hot restart / resync, degraded resume, and later recovery can reach plain `Online` from proactive proof without requiring user action, while a real user success may still satisfy pending proof first
- benchmark, smoke, and device-backed acceptance surfaces observe the same service-owned readiness transitions the widget consumes and split sendable timing from relay-ready timing truthfully
- existing send routing, inbox fallback delivery semantics, lifecycle continuity, and the already-accepted Phase 3b relay-ready measurements stay correct instead of being papered over by the new badge contract

## Source of truth

- product intent:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec.md`
- regression / gate policy:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- adjacent stable scope guards:
  - `Test-Flight-Improv/10-network-measurement-strategy.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- current service / state seam:
  - `lib/core/services/p2p_service.dart`
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/features/p2p/domain/models/node_state.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- current widget / app-facing readiness seam:
  - `lib/features/p2p/presentation/widgets/connection_status_indicator.dart`
  - `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`
  - `lib/features/home/presentation/screens/first_time_experience_screen.dart`
  - `lib/features/feed/presentation/widgets/feed_header.dart`
- current send / inbox proof-producing seam:
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `lib/core/debug/intro_e2e_runner.dart`
- current lifecycle / transport / benchmark seam:
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/core/lifecycle/background_reconnect_smoke_test.dart`
  - `integration_test/benchmark_time_to_online_harness.dart`
  - `integration_test/benchmark_background_resume_harness.dart`
  - `integration_test/benchmark_relay_recovery_harness.dart`
  - `integration_test/background_reconnect_test.dart`
  - `test/performance/benchmark_time_to_online_test.dart`
  - `test/performance/benchmark_background_resume_test.dart`
  - `test/performance/benchmark_relay_recovery_test.dart`

Current repo facts that govern the split:

- `ConnectionStatusIndicator` currently derives readiness from strict relay truth only: `relayState == 'online'` or non-empty `circuitAddresses`.
- `NodeState` currently exposes relay health and connection details, but no service-owned `send-capable`, `inbox-capable`, proof-window, or dotted-vs-plain readiness state.
- `P2PServiceImpl` currently emits `TIME_TO_ONLINE_BADGE` only from relay-health transitions; the source doc requires separate sendable and relay-ready timing truth plus proof-window events.
- the app already has Dart-side success seams for inbox retrieval/drain and successful send outcomes, and `send_chat_message_use_case.dart` already treats inbox fallback as honest delivered transport instead of a fake success.
- `lib/core/debug/intro_e2e_runner.dart` already contains a narrower "usable transport" concept than strict relay truth, which confirms the codebase already recognizes that usability and relay reservation are not identical.
- benchmark harnesses and many lifecycle / transport tests currently treat `ConnectionHealth.online` as the success condition, so the final rollout must separate the new product contract from older relay-only expectations without silently weakening real-stack coverage.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | `Service-owned readiness proof model, proof-window lifecycle, and proof instrumentation` | `implementation-ready` | `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-1-plan.md` | none | `accepted` | Completed locally with fallback after spawned agents made no progress. Service-owned readiness proof windows, truthful send/inbox proof hooks, and Phase 6 timing events landed. Direct suites passed, and `transport`, `1to1`, plus `baseline` passed on simulator `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` after setting `FLUTTER_DEVICE_ID` in the multi-device environment. |
| `2` | `Badge rendering, semantics, and app-facing readiness consumption` | `implementation-ready` | `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-2-plan.md` | `1` | `accepted` | Completed locally with bounded fallback. The badge now renders service-owned Phase 6 truth, distinguishes `Online` versus `Online.` in semantics, and passed the direct widget suite plus `baseline` on simulator `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. |
| `3` | `Benchmark split, transport acceptance, and rollout closure` | `implementation-ready` | `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-3-plan.md` | `1`, `2` | `accepted_with_explicit_follow_up` | Completed locally with bounded fallback. Phase 6 benchmark helpers, direct benchmark suites, real benchmark harnesses, and the background reconnect smoke were migrated to service-owned readiness truth. Direct benchmark suites passed, the direct simulator harnesses for startup, background resume, and relay recovery all passed on simulator `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and `transport`, `1to1`, plus `baseline` passed on the same simulator; the remaining explicit follow-up is a physical-device run of `integration_test/background_reconnect_test.dart`, which is still simulator-skipped by design. |

## Ordered session breakdown

### Session 1

- title: `Service-owned readiness proof model, proof-window lifecycle, and proof instrumentation`
- session id: `1`
- session classification: `implementation-ready`
- intended plan file: `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-1-plan.md`
- exact scope:
  - add the authoritative Phase 6 readiness projection to the app-facing service state so the service can distinguish:
    - relay-ready
    - send-capable
    - inbox-capable
    - the resulting visible readiness family required by the spec
  - keep relay transport truth bridge-owned, but keep `send-capable` and `inbox-capable` Dart-service-owned; do not move those proofs into widget-local inference or a second badge-readiness service
  - implement proof-window start, reuse, and reset rules in `P2PServiceImpl` for:
    - node stop
    - watchdog restart / host restart
    - identity change
    - explicit reinitialize / new transport session
    - degraded or unhealthy resume / recovery windows
    - per-capability verification failure
  - wire `send-capable` proof from real successful send outcomes in the current window and `inbox-capable` proof from successful inbox retrieval / drain outcomes in the current window without changing existing direct / local / relay / inbox routing policy
  - start proactive proof automatically on cold start, hot restart / already-started resync, and degraded background resume, using the normal inbox retrieval path plus a dedicated safe send-proof mechanism that stays inside the source-doc scope
  - allow a real user send or real inbox success to satisfy pending proof if it wins before the proactive mechanism
  - emit the service-owned Phase 6 event contract needed by the later benchmark session, including:
    - `READINESS_PROOF_WINDOW_START`
    - `READINESS_PROOF_RESULT`
    - `TIME_TO_SENDABLE_BADGE`
    - `TIME_TO_RELAY_READY_BADGE`
    - `FIRST_SEND_SUCCESS_IN_WINDOW`
    - `FIRST_INBOX_SUCCESS_IN_WINDOW`
  - preserve existing relay-recovery and outage attribution rather than replacing it with a new measurement subsystem
- why it is its own session:
  - this is the authoritative correctness seam that every later badge and benchmark assertion depends on
  - it has a distinct direct regression family: service state, lifecycle, proof resets, and send/inbox success plumbing rather than widget rendering or benchmark harness output
  - it leaves a meaningful verified prerequisite state when the service can model truthful Phase 6 readiness before any widget or device acceptance surface is switched over
- likely code-entry files:
  - `lib/core/services/p2p_service.dart`
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/features/p2p/domain/models/node_state.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `lib/core/debug/intro_e2e_runner.dart`
  - any adjacent service-owned helper introduced for proof-window / proof-result state, provided it stays under the same ownership seam
- likely direct tests/regressions:
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/core/lifecycle/background_reconnect_smoke_test.dart`
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `test/core/services/p2p_service_fault_injection_test.dart` if final planning changes how degraded windows or relay-loss resets are projected
  - `test/core/services/p2p_service_addresses_updated_test.dart` if the chosen readiness projection changes app-facing state diffs
- likely named gates:
  - `transport`
  - `1to1`
  - `baseline`
- matrix/closure docs to update when done:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-breakdown.md`
  - keep `Test-Flight-Improv/10-network-measurement-strategy.md` and `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` as scope guards only until final closure proves a stable wording change is warranted
- dependency on earlier sessions:
  - none

### Session 2

- title: `Badge rendering, semantics, and app-facing readiness consumption`
- session id: `2`
- session classification: `implementation-ready`
- intended plan file: `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-2-plan.md`
- exact scope:
  - replace the current relay-only badge inference with rendering that consumes the service-owned readiness state from Session `1`
  - render the exact visible copy contract:
    - `Offline`
    - `Connecting`
    - `Online`
    - `Online.`
  - keep `Online` and `Online.` in the same green ready-state family and make the dot the only required visible distinction unless later product direction explicitly widens the design
  - add or update semantics / accessibility labels so assistive technologies distinguish:
    - online, send and inbox ready, relay reservation pending
    - online, send and inbox ready, relay reservation ready
  - keep the widget a pure renderer of service-owned state; remove or tighten any widget-local delay or fallback behavior that would mask truthful service-owned readiness transitions
  - update any immediate app-facing helpers or consumers that must stay aligned with the badge-ready family after Session `1`, while deferring the heavy benchmark/device acceptance sweep to Session `3`
- why it is its own session:
  - this is a bounded presentation seam with direct widget/semantics regressions that are different from the service/lifecycle seam and the benchmark/device seam
  - the user-visible contract can be verified immediately once Session `1` exposes the right readiness projection
  - splitting the badge renderer from the later real-stack benchmark work prevents performance-harness noise from obscuring simple copy / semantics / rendering regressions
- likely code-entry files:
  - `lib/features/p2p/presentation/widgets/connection_status_indicator.dart`
  - `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`
  - `lib/features/home/presentation/screens/first_time_experience_screen.dart`
  - `lib/features/feed/presentation/widgets/feed_header.dart`
  - any adjacent presentation helper extracted from the current `healthFromState(...)` path, provided it remains a renderer of the service-owned readiness projection
- likely direct tests/regressions:
  - `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`
  - one direct semantics / accessibility regression if the existing widget suite does not already cover semantics assertions cleanly
  - `integration_test/loading_states_smoke_test.dart` if final planning confirms the changed app chrome should be exercised through the baseline smoke instead of widget tests alone
- likely named gates:
  - `baseline`
  - run `transport` only if final planning changes a shared readiness helper that the transport-backed harnesses consume directly before Session `3`
- matrix/closure docs to update when done:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-breakdown.md`
  - do not refresh `00-INDEX.md` or stable closure docs yet; final closure still depends on Session `3`
- dependency on earlier sessions:
  - Session `1`

### Session 3

- title: `Benchmark split, transport acceptance, and rollout closure`
- session id: `3`
- session classification: `implementation-ready`
- intended plan file: `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-3-plan.md`
- exact scope:
  - update the existing benchmark harnesses and their paired performance tests to consume the service-owned Phase 6 event contract instead of relay-only `TIME_TO_ONLINE_BADGE` assumptions
  - preserve relay-ready timing as a truthful secondary metric while adding the required sendable-vs-relay-ready split:
    - `resume_to_sendable_ms`
    - `resume_to_relay_ready_ms`
    - `resume_to_first_send_success_ms`
    - `resume_to_first_inbox_success_ms`
    - `sendable_to_relay_ready_gap_ms`
    - `badge_honesty_gap_ms`
  - adapt transport / device / routing-smoke acceptance surfaces so they prove:
    - plain `Online` can appear before `Online.`
    - send still works during the plain `Online` window
    - inbox retrieval still works during the plain `Online` window
    - relay-ready upgrade remains visible when it arrives later
  - add the missing acceptance proof for the no-user-action path and the user-visible regression described in the source doc, using either a dedicated Phase 6 harness or an equivalent bounded extension of the existing harness set
  - refresh the breakdown ledger and any stable maintenance docs only after the final real-stack evidence shows the Phase 6 split is a truthful improvement instead of a relabel
- why it is its own session:
  - benchmark/performance/device acceptance is a different test family with different runtime cost, failure modes, and maintenance surfaces than Sessions `1` and `2`
  - the rollout only closes when real-stack evidence proves the badge semantics improved user-visible honesty without regressing transport truth
  - splitting this session further into separate benchmark, smoke, and closure sessions would mostly add bookkeeping because the same acceptance evidence governs all three
- likely code-entry files:
  - `integration_test/benchmark_time_to_online_harness.dart`
  - `integration_test/benchmark_background_resume_harness.dart`
  - `integration_test/benchmark_relay_recovery_harness.dart`
  - `integration_test/benchmark_helpers.dart`
  - `integration_test/background_reconnect_test.dart`
  - `test/performance/benchmark_time_to_online_test.dart`
  - `test/performance/benchmark_background_resume_test.dart`
  - `test/performance/benchmark_relay_recovery_test.dart`
  - `integration_test/scripts/run_routing_smoke_e2e.dart`
  - `Test-Flight-Improv/10-network-measurement-strategy.md` only if the final accepted event contract changes the stable measurement guidance
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` only if the final accepted rollout changes the stable wording around send/inbox operability as a maintenance-time scope guard
  - `Test-Flight-Improv/00-INDEX.md` when the rollout reaches a finished verdict
- likely direct tests/regressions:
  - `test/performance/benchmark_time_to_online_test.dart`
  - `test/performance/benchmark_background_resume_test.dart`
  - `test/performance/benchmark_relay_recovery_test.dart`
  - `integration_test/benchmark_time_to_online_harness.dart`
  - `integration_test/benchmark_background_resume_harness.dart`
  - `integration_test/benchmark_relay_recovery_harness.dart`
  - `integration_test/background_reconnect_test.dart`
  - `test/features/conversation/application/send_chat_message_use_case_test.dart` as the direct send-path guard for the plain `Online` window
  - `dart run integration_test/scripts/run_routing_smoke_e2e.dart` phase `1` scope when final planning confirms the badge-semantics change touches shared routing / smoke expectations
- likely named gates:
  - `transport`
  - companion `1to1`
  - `baseline`
- matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-breakdown.md`
  - conditional:
    - `Test-Flight-Improv/10-network-measurement-strategy.md`
    - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    - `Test-Flight-Improv/00-INDEX.md`
- dependency on earlier sessions:
  - Session `1`
  - Session `2`

## Why this is not fewer sessions

- A one-session rollout would mix three materially different seams:
  - service-owned readiness proof and lifecycle resets
  - visible badge rendering / semantics
  - device-backed benchmark and transport acceptance
- Session `1` must stand alone because it establishes the only authoritative readiness owner; without that prerequisite, Session `2` or `3` would either duplicate logic or test against a temporary truth source.
- Session `3` must remain separate because real-stack benchmark and device acceptance is the only honest way to decide whether the new badge semantics deliver user-visible value instead of a relabel.

## Why this is not more sessions

- Splitting send-proof work from inbox-proof work would add bookkeeping without independent verification value because the source doc requires them to converge into one service-owned readiness state and one proof-window contract.
- Splitting widget copy from widget semantics would add a second UI-only session without changing gates, code ownership, or closure evidence.
- Splitting benchmark harness changes from final closure bookkeeping would create a paperwork-only tail; the same real-stack evidence that updates the harnesses is the evidence that decides closure.

## Regression and gate contract

- `Test-Flight-Improv/14-regression-test-strategy.md` applies here as:
  - direct seam regressions first
  - then the named gates whose shared pipelines were touched
  - then the heavier device-backed transport / routing evidence for final acceptance
- Session `1` owns the new or updated direct service/lifecycle/send regressions and must run `transport`, `1to1`, and `baseline` before acceptance because it changes the shared readiness owner and uses send/inbox proof sources.
- Session `2` owns the direct widget / semantics regressions and should keep named-gate scope narrow, defaulting to `baseline` unless final planning proves a broader shared readiness helper changed.
- Session `3` owns the benchmark/performance/device acceptance evidence and must rerun:
  - the direct benchmark suites
  - `transport`
  - companion `1to1`
  - `baseline`
  - routing smoke when final planning confirms the badge-semantics change touches that shared entry seam
- Across the whole rollout, the transport-routing scope guard from the source doc remains strict:
  - no direct/local/relay/inbox routing-policy redesign
  - no relay-speed or reservation-speed work
  - no benchmark-only truth that the production widget does not consume

## Matrix update contract

- This breakdown artifact is the live closure ledger for the rollout and must be updated after every accepted, blocked, or reclassified session.
- The source spec `06-sendable-online-badge-spec.md` remains the product-intent source of truth; do not rewrite it during ordinary execution unless a later closure pass must record a bounded stale or already-covered verdict.
- Stable maintenance docs stay conditional:
  - update `Test-Flight-Improv/10-network-measurement-strategy.md` only if the final accepted event contract changes long-lived measurement guidance
  - update `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` only if the final accepted rollout changes the stable maintenance wording around send/inbox operability and truthful ready-state expectations
  - update `Test-Flight-Improv/00-INDEX.md` only when the rollout reaches a finished final verdict worth recording in the repo-wide index

## Downstream execution path

- Session `1` should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Session `2` should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Session `3` should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- The exact internal storage shape for proof-window state may vary as long as `P2PService` remains the only authoritative owner exposed to the app.
- The proactive send-proof mechanism may vary, but it must stay inside the source-doc scope and must not silently become a routing-policy redesign or a second bridge-owned truth source.
- `Online` and `Online.` remain the same green ready-state family; no broader visual redesign is required for closure beyond the requested dot distinction and accessibility wording.
- The rollout does not require a brand-new benchmark harness if the existing harnesses can be tightened to prove the same Phase 6 contract truthfully.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/10-network-measurement-strategy.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `lib/core/services/p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/p2p/domain/models/node_state.dart`
- `lib/features/p2p/presentation/widgets/connection_status_indicator.dart`
- `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `lib/core/debug/intro_e2e_runner.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`
- `integration_test/benchmark_time_to_online_harness.dart`
- `integration_test/benchmark_background_resume_harness.dart`
- `integration_test/benchmark_relay_recovery_harness.dart`
- `integration_test/background_reconnect_test.dart`
- `test/performance/benchmark_time_to_online_test.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `test/performance/benchmark_relay_recovery_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The source doc already fixes one bounded product contract: the badge should report usable-now truth before relay-ready truth, without widening into transport redesign.
- Current repo evidence shows three clean seams with different verification families:
  - service-owned readiness state and lifecycle proof windows
  - widget rendering / semantics
  - benchmark and real-stack transport acceptance
- The codebase already contains enough building blocks to plan narrowly:
  - one app-facing state owner (`P2PService`)
  - existing send and inbox success seams
  - existing flow-event infrastructure
  - existing benchmark and transport harnesses that can be tightened rather than replaced wholesale

## Program rollout ledger

- Breakdown artifact used:
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-breakdown.md`
- Spawned-agent isolation used:
  `attempted_then_local_fallback`
- Sessions processed:
  `3/3`
- Sessions accepted:
  `2`
- Sessions accepted_with_explicit_follow_up:
  `1`
- Sessions blocked:
  `0`
- Sessions skipped_due_to_dependency:
  `0`
- Plan fallbacks used:
  `3`
- Execution fallbacks used:
  `3`
- Closure fallbacks used:
  `3`
- Final program acceptance verdict:
  `accepted_with_device_follow_up`
- Stable docs updated:
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-1-plan.md`
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-2-plan.md`
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-3-plan.md`
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-breakdown.md`
- Next required session:
  None in the current simulator-only environment. Recommended follow-up: run `integration_test/background_reconnect_test.dart` on a physical device.
