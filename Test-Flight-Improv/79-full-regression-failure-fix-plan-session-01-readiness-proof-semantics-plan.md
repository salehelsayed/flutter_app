# Session 01 Plan: Readiness Proof Semantics

## Final verdict

`implementation-ready` as the planning verdict. Session 01 execution closure is recorded below.

This session was safe to execute as a narrow correctness fix. At planning time, the false-positive seam was localized to `P2PServiceImpl` staged inbox drain readiness proof handling: a failed `inbox:retrieve_pending` response looked the same as a successful empty page to the caller, and the caller recorded inbox proof success unconditionally.

## Session 01 closure audit

Closure verdict: `closed` for Session 01 only.

Completion auditor:

- Landed files: `lib/core/services/p2p_service_impl.dart` and `test/core/services/p2p_service_impl_test.dart`.
- Added regressions: `retrieve_pending ok:false does not record inbox proof success` and `retrieve_pending ok:true empty inbox records inbox proof success`.
- RED evidence: the negative regression failed pre-fix because `inboxCapabilityReady` was `true`.
- Post-fix verification passed:
  - `flutter test test/core/services/p2p_service_impl_test.dart --plain-name "retrieve_pending ok:false does not record inbox proof success"`
  - `flutter test test/core/services/p2p_service_impl_test.dart`
  - `flutter test test/core/services/p2p_service_fault_injection_test.dart`
  - `flutter test test/performance/benchmark_time_to_online_test.dart`
  - `flutter test test/performance/benchmark_background_resume_test.dart`
  - `dart format --output=none --set-exit-if-changed ...`
- Named gates: none required because no bridge command shape, transport fallback, bootstrap, or resume/reconnect behavior changed.

Closure writer:

- Closed: failed `inbox:retrieve_pending` responses no longer record inbox proof success, set `inboxCapabilityReady`, or complete `TIME_TO_SENDABLE_BADGE` through inbox proof attribution.
- Closed: successful `ok:true` empty inbox responses remain an explicit successful inbox proof.
- Residual-only items for Session 01: none.
- Still open outside Session 01: relay/device diagnosis, aggregate feature-test stability, feed performance, and final full-regression acceptance remain Sessions 02-05.
- Accepted differences: public `retrieveInbox()` and bridge/startup/transport behavior remain unchanged; local staged replay is still useful recovery work but is not relay inbox capability proof by itself.
- Reopen only on real regression: reopen Session 01 only if a failed durable `retrieve_pending` attempt can again mark inbox readiness successful or emit inbox/sendable success telemetry.

Closure reviewer:

- The closure evidence matches the landed file set and direct test scope.
- No whole-doc 79 closure is claimed.
- No named gate status is changed.
- Sessions 02-05 remain open in the breakdown and source doc.

## Final plan

### 1. real scope

Change only the Session 01 readiness proof semantics for durable automatic inbox drain:

- add a regression proving `inbox:retrieve_pending` returning `ok:false` does not record inbox proof success
- make failed `retrieve_pending` distinguishable from a successful empty page inside `P2PServiceImpl`
- preserve and explicitly pin that `ok:true` with an empty `messages` list is a valid inbox capability proof
- keep existing durable stage-then-ack replay behavior unchanged for successful pages with messages
- keep public `retrieveInbox()` behavior unchanged except as indirect context for proof semantics

This session does not fix emulator relay startup, aggregate feature-test flakiness, feed performance, message retry UX, relay architecture, or any Go bridge implementation.

### 2. closure bar

The session is good enough when all of these are true in the current architecture:

- `retrieve_pending ok:false` cannot emit `FIRST_INBOX_SUCCESS_IN_WINDOW`
- `retrieve_pending ok:false` cannot set `NodeState.inboxCapabilityReady` to `true`
- `retrieve_pending ok:false` cannot be the missing half that emits `TIME_TO_SENDABLE_BADGE`
- `retrieve_pending ok:true` with no messages remains an explicit successful inbox proof
- failures still emit error/failure telemetry without destructive fallback to `inbox:retrieve`
- existing staged inbox replay, ack, malformed-row, and positive readiness tests continue to pass

### 3. source of truth

Authoritative task docs:

- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`

Regression and gate authority:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/14-regression-test-strategy.md`

Current code and tests that beat stale prose on disagreement:

- `lib/core/services/p2p_service_impl.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/features/p2p/domain/models/node_state.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_fault_injection_test.dart`
- `test/performance/benchmark_time_to_online_test.dart`
- `test/performance/benchmark_background_resume_test.dart`

If docs and script disagree on named gates, `scripts/run_test_gates.sh` wins. If docs and current code/tests disagree on behavior, current code/tests win until the new regression proves the required correction.

### 4. session classification

`implementation-ready`.

Reason: the source and breakdown identify a deterministic service bug with local fake-bridge coverage. No emulator, relay preflight, full regression run, or performance baseline is needed before implementing this session.

### 5. exact problem statement

`P2PServiceImpl._retrievePendingInboxPage(...)` returns `(replayed: 0, staged: 0, hasMore: false)` for both:

- `inbox:retrieve_pending` exception or `ok:false`
- `ok:true` with an empty inbox

`_drainOfflineInboxDurably()` then calls `_recordSuccessfulInboxProof(source: 'drain_offline_inbox', trigger: 'system_action')` after the page attempt regardless of whether the bridge response succeeded. That can mark `inboxCapabilityReady` true, emit `FIRST_INBOX_SUCCESS_IN_WINDOW`, and, if send proof has also succeeded, emit `TIME_TO_SENDABLE_BADGE` even though relay inbox retrieval failed.

User-visible behavior that must improve: the app must not present itself as sendable or inbox-capable from a failed relay inbox proof. Behavior that must stay unchanged: a successful empty relay inbox page is still a valid proof that the inbox path is reachable.

### 6. files and repos to inspect next

Production files:

- `lib/core/services/p2p_service_impl.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/features/p2p/domain/models/node_state.dart`

Direct tests:

- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_fault_injection_test.dart`
- `test/performance/benchmark_time_to_online_test.dart`
- `test/performance/benchmark_background_resume_test.dart`

Gate/config files:

- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

Repository scope: this Flutter app repo only.

### 7. existing tests covering this area

Already covered:

- `test/core/services/p2p_service_impl_test.dart` has durable inbox drain tests for successful `retrieve_pending`, staging, ack, replay, malformed-row handling, unsupported command safety, pagination, and Phase 6 readiness windows.
- `test/core/services/p2p_service_impl_test.dart` currently proves a successful empty `retrieve_pending` can contribute to readiness through `warmBackground reaches sendable state from proactive proofs before relay-ready`.
- `test/core/services/p2p_service_impl_test.dart` proves relay-ready alone does not unlock readiness and degraded resume starts a new proof window.
- `test/performance/benchmark_time_to_online_test.dart` and `test/performance/benchmark_background_resume_test.dart` assert `TIME_TO_SENDABLE_BADGE`, `FIRST_SEND_SUCCESS_IN_WINDOW`, and `FIRST_INBOX_SUCCESS_IN_WINDOW` attribution relationships.
- `lib/features/p2p/domain/models/node_state.dart` defines `usabilityReady` as `isStarted && sendCapabilityReady && inboxCapabilityReady`.

Missing:

- no direct test proves `retrieve_pending ok:false` leaves `inboxCapabilityReady == false`
- no direct test proves `retrieve_pending ok:false` does not emit `FIRST_INBOX_SUCCESS_IN_WINDOW`
- no direct test proves `retrieve_pending ok:false` cannot complete sendable readiness when send proof succeeds
- no direct test explicitly names the positive empty-inbox contract as `ok:true` empty means inbox proof success
- `test/core/services/p2p_service_fault_injection_test.dart` has broader service fault coverage but no `retrieve_pending` readiness-proof-specific assertion

### 8. regression/tests to add first

Add or update tests in `test/core/services/p2p_service_impl_test.dart` before changing production code:

1. Negative regression in `Phase 6 readiness proof windows`:
   - start the node in a degraded but started state
   - make `inbox:retrieve_pending` return `{'ok': false, 'errorMessage': 'relay unavailable'}`
   - make `inbox:store` return `{'ok': true}` so send proof can succeed
   - call `warmBackground()`
   - assert `sendCapabilityReady == true`
   - assert `inboxCapabilityReady == false`
   - assert badge state remains `BadgeReadinessState.connecting`
   - assert no `FIRST_INBOX_SUCCESS_IN_WINDOW`
   - assert no `TIME_TO_SENDABLE_BADGE`
   - assert a failed inbox proof/result or retrieve-pending error event is emitted

2. Positive empty-inbox counterpart:
   - use `inbox:retrieve_pending` returning `{'ok': true, 'messages': [], 'hasMore': false}`
   - make `inbox:store` return `{'ok': true}`
   - assert `inboxCapabilityReady == true`
   - assert exactly one `FIRST_INBOX_SUCCESS_IN_WINDOW` with `source == 'drain_offline_inbox'`
   - assert `TIME_TO_SENDABLE_BADGE` is emitted once when send proof also succeeds

If the negative regression already passes before implementation, stop and reclassify the session as `stale/already-covered` after documenting the new evidence. If the positive empty-inbox case fails before implementation, stop and resolve the contract mismatch before changing code.

### 9. step-by-step implementation plan

1. Add the negative regression first and confirm it fails against current code.
2. Add or strengthen the positive empty-inbox proof test so the desired `ok:true` empty behavior is explicit.
3. Change `_retrievePendingInboxPage(...)` to return an explicit retrieval-success signal, such as `retrieveSucceeded` or `proofSucceeded`, in addition to `replayed`, `staged`, and `hasMore`.
4. Return the success signal as `false` for exceptions and `response['ok'] != true`; keep the existing retrieve-pending error event.
5. Return the success signal as `true` for `response['ok'] == true`, including empty `messages`, all-malformed pages, and normal staged pages.
6. In `_drainOfflineInboxDurably()`, call `_recordSuccessfulInboxProof(...)` only when the first relay `retrieve_pending` page succeeded.
7. When the first relay `retrieve_pending` page failed, call `_recordCapabilityProofFailure(capability: 'inbox', source: 'drain_offline_inbox', trigger: 'system_action', failureReason: ...)` or otherwise preserve a clear failed-proof event; do not set `inboxCapabilityReady` true.
8. Keep `_continueDrainingOfflineInboxDurably(...)` behavior narrow: use the explicit success signal to avoid continuing after failed pages, but do not add new background retry architecture.
9. Run the direct tests listed below. Run the conditional transport gate only if implementation changes bridge commands, resume/reconnect flow, transport fallback, or app bootstrap behavior.
10. Stop after Session 01 evidence. Do not proceed into Session 02 relay/device diagnosis or any full-regression closure work.

### 10. risks and edge cases

- A failed relay retrieve with local staged rows replayed must not prove relay inbox capability by accident.
- `ok:true` with empty messages must stay a positive proof; otherwise cold-start/resume sendable timing can regress.
- `ok:true` with malformed rows should still count as a successful relay retrieve while preserving malformed-row handling.
- Pagination must not continue forever or mark success from later background pages after the first proof failed.
- Concurrent `warmBackground()` send and inbox proof futures can emit send proof first; the negative regression must prove send success alone does not unlock sendable state.
- `NodeState.usabilityReady` must remain the conjunction of started, send-ready, and inbox-ready.
- No destructive fallback to `inbox:retrieve` should be introduced for this proof.

### 11. exact tests and gates to run

Regression-first direct test command:

```bash
flutter test test/core/services/p2p_service_impl_test.dart --plain-name "retrieve_pending ok:false does not record inbox proof success"
```

Post-fix direct tests:

```bash
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/core/services/p2p_service_fault_injection_test.dart
flutter test test/performance/benchmark_time_to_online_test.dart
flutter test test/performance/benchmark_background_resume_test.dart
```

Named gates:

- No frozen named gate is required if the implementation stays inside `P2PServiceImpl` readiness proof result handling and direct tests pass.
- If the implementation changes bridge command shape, resume/reconnect sequencing, transport fallback, or app bootstrap behavior, run:

```bash
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
```

Do not run `benchmark-sim`, feed, groups, or full regression as part of Session 01 unless the implementation intentionally changes those surfaces, which would violate this plan's scope guard.

### 12. known-failure interpretation

- The source doc's relay/device startup failures belong to Session 02. They are not Session 01 regressions unless this session changes bridge, resume, reconnect, transport fallback, or app bootstrap behavior and the transport gate newly fails.
- The aggregate `test/features` failures belong to Session 03 and should not be reclassified from Session 01 evidence.
- The feed P99 failure belongs to Session 04 and should not affect this plan.
- Full regression closure belongs to Session 05.
- If one of the direct Session 01 tests fails after the fix, treat it as blocking unless the failure is proven unrelated to readiness proof semantics with a narrow rerun.
- Generated or environment noise in build output is not evidence for changing this plan.

### 13. done criteria

- The new negative regression fails before production changes and passes after.
- The explicit positive `ok:true` empty-inbox proof test passes.
- `retrieve_pending ok:false` leaves `inboxCapabilityReady == false`.
- `retrieve_pending ok:false` emits no `FIRST_INBOX_SUCCESS_IN_WINDOW`.
- `retrieve_pending ok:false` emits no `TIME_TO_SENDABLE_BADGE` even when send proof succeeds.
- Existing durable inbox drain tests still pass.
- The exact post-fix direct tests pass, or any failure is documented as unrelated and pre-existing with command evidence.
- No production or test changes outside the Session 01 file set are needed.

### 14. scope guard

Non-goals:

- do not edit Go relay/node code
- do not redesign relay readiness or AutoRelay behavior
- do not change public badge copy or widget policy
- do not change message retry UX
- do not change feed, groups, posts, intro, push, or notification routing
- do not modify `scripts/run_test_gates.sh` or gate definitions
- do not add a new readiness service or new persistence layer
- do not replace durable `retrieve_pending` with destructive `inbox:retrieve`

Overengineering signals:

- adding broad retry/backoff architecture for failed `retrieve_pending`
- changing bridge protocol shape when a Dart-side result wrapper is enough
- rewriting staging, ack, or replay flows unrelated to proof success
- adding emulator or relay preflight work to this session

### 15. accepted differences / intentionally out of scope

- Public `retrieveInbox()` uses `inbox:retrieve`; this session only fixes automatic durable `retrieve_pending` proof semantics.
- `ok:true` empty relay inbox is intentionally accepted as inbox-capability proof because it proves the inbox retrieve path is reachable.
- `ok:false` and exceptions are failure paths for proof purposes even if they safely return no messages to callers.
- Local staged replay is useful recovery work but is not, by itself, proof that the relay inbox retrieve path is healthy.
- Relay/device startup evidence, aggregate feature flake evidence, feed performance evidence, and final full regression acceptance remain separate sessions.

### 16. dependency impact

- Session 02 relay/device diagnosis should refresh after this lands because readiness attribution will no longer report false inbox success during relay retrieve failures.
- Session 05 full-regression closure depends on this session to prevent misclassifying relay/device failures as successful sendable readiness.
- If this plan changes from service-local proof semantics into bridge/startup behavior, Session 02 planning and the transport gate contract must be revisited before execution continues.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- Adding a separate exception-specific regression is optional; the implementation should naturally treat exceptions the same as `ok:false` because both are failed relay retrieve attempts.
- Adding a new named gate is deferred because `test/core/services/*.dart` and `test/performance/*.dart` are already classified as direct suites, and no gate membership change is required.
- Full-regression rerun and source-doc closure notes are deferred to Session 05.

## Accepted differences intentionally left unchanged

- `ok:true` empty inbox remains a successful inbox proof.
- Public destructive `retrieveInbox()` semantics remain unchanged.
- Relay-ready truth remains bridge-owned; send/inbox proof truth remains service-owned.
- Device-backed relay startup failures are intentionally not addressed in Session 01.

## Exact docs/files used as evidence

- `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `scripts/run_test_gates.sh`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/features/p2p/domain/models/node_state.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_fault_injection_test.dart`
- `test/performance/benchmark_time_to_online_test.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `test/shared/fakes/lifecycle_bridge.dart`

## Why the plan is safe or unsafe to implement now

Safe to implement now. The plan has one service-local behavior change, starts with a failing regression for the escaped bug, preserves the explicit positive empty-inbox contract, names exact direct tests, keeps named gates conditional on actual blast radius, and stops before unrelated relay/device, aggregate, feed, or full-regression closure work.
