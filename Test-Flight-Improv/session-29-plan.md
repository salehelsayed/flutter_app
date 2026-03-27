# Session 29 Plan: Add Lean Local Measurement For Messaging Reliability

## 1. real scope

Close only the four highest-value measurement gaps from `10-network-measurement-strategy.md`, using the existing local `emitFlowEvent()` approach instead of building a new observability subsystem.

Targeted gaps from `## Critical Measurement Gaps`:
- **E2E Message Latency**
  - For Session 29, treat this as one honest representative correlation slice, not a full new transport-to-receive observability rollout across every messaging path.
  - Do not claim full E2E coverage unless at least one receive-side seam is touched and directly tested in the same pass.
- **Media Throughput**
- **Retry Effectiveness**
- **Connection / Discovery Timing**

This session is intentionally narrower than the full strategy in report 10. It should improve local timing/counter visibility for the messaging paths that now matter most after the group-discussion and announcement reliability work, while also covering the shared 1:1 messaging/media seams already present in the repo.

Concrete repo evidence already narrows the scope:
- `lib/features/conversation/application/send_chat_message_use_case.dart` already emits `CHAT_MSG_SEND_TIMING`.
- `lib/features/conversation/application/upload_media_use_case.dart` already emits `MEDIA_UPLOAD_TIMING`.
- `lib/features/conversation/application/download_media_use_case.dart` already emits `MEDIA_DOWNLOAD_TIMING`.
- `lib/features/conversation/application/retry_failed_messages_use_case.dart` already emits `RETRY_FAILED_MESSAGES_TIMING`.
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart` already emits `RETRY_INCOMPLETE_UPLOADS_TIMING`.
- `lib/features/groups/application/send_group_message_use_case.dart` already emits `GROUP_SEND_MSG_TIMING`.
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart` already emits `RETRY_FAILED_GROUP_MESSAGES_TIMING`.
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` already emits `RETRY_INCOMPLETE_GROUP_UPLOADS_TIMING`.
- `lib/features/groups/application/rejoin_group_topics_use_case.dart` already emits `GROUP_REJOIN_TOPICS_TIMING`.
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` already emits `GROUP_DRAIN_OFFLINE_INBOX_TIMING`.
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` and `lib/features/groups/application/handle_incoming_group_message_use_case.dart` already emit receive-side flow events, but not a normalized timing/correlation summary.
- `lib/core/lifecycle/handle_app_resumed.dart` already has debug timing around inbox drain, rejoin, and retries, but it should stay inspect-only unless the use-case-local event picture is still insufficient after inventory.

In scope:
- normalize and complete local timing/counter signals across the shared 1:1 messaging/media seams and the recent group/announcement recovery seams already using `emitFlowEvent(...)`
- improve correlation across representative send, media, retry, and rejoin/drain timing without creating a new observability layer
- keep all new measurement local to `emitFlowEvent(...)` style output
- add only the smallest missing tags/events needed to compare reliability paths
- prove the new local signals with direct deterministic tests in the touched conversation and/or group families
- touch one representative receive-side seam only if needed to keep the `E2E Message Latency` claim honest
- prefer use-case-local seams; edit `handle_app_resumed.dart` only if a real lifecycle-summary gap remains after inventory

Out of scope:
- creating `lib/core/observability/timing_probe.dart`
- creating `lib/core/observability/session_metrics.dart`
- exporter/dashboard/analytics infrastructure
- full transport-to-receive observability rollout across every path
- broad DB hotspot work
- decrypt/error visibility work outside the already-landed signals
- product-facing metrics UI
- wide instrumentation of every helper or nested sub-step
- changing business logic or transport orchestration for measurement alone

## 2. session classification

`implementation-ready`

Why:
- the targeted gaps are concrete and local
- the repo already has timing seams in both shared 1:1 and group/recovery code paths
- the missing work is mostly normalization, completion, and direct proof rather than a new platform
- the scope is now explicit about when receive-side or lifecycle files are actually required
- gate expectations can be evaluated against the current known-failure ledger instead of assuming unconditional green

## 3. files and repos to inspect next

Primary planning / rationale docs:
- `Test-Flight-Improv/10-network-measurement-strategy.md`
- `Test-Flight-Improv/session-23-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
- `Test-Flight-Improv/13-announcement-use-case-audit.md`

Primary code:
- `lib/core/utils/flow_event_emitter.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` only if a representative receive-side correlation seam is needed
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart` only if a representative group receive-side correlation seam is needed
- `lib/core/lifecycle/handle_app_resumed.dart` inspect only; edit only if the use-case-local picture stays insufficient

Primary tests:
- `test/core/utils/flow_event_emitter_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/upload_media_use_case_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` only if a representative receive-side correlation seam is touched
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` only if a representative group receive-side correlation seam is touched
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` only if lifecycle summary events are touched
- `test/core/lifecycle/app_lifecycle_recovery_test.dart` only if lifecycle summary events are touched
- `test/features/groups/integration/group_resume_recovery_test.dart` only as a broader safety net if needed
- `test/features/groups/integration/announcement_happy_path_test.dart` only as an optional nearby direct suite if announcement-specific behavior is touched

Gate / regression references:
- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh transport` only if the implementation changes lifecycle / resume / recovery orchestration

Execution note:
- `scripts/run_test_gates.sh` is the canonical source of truth for named gates if it ever diverges from prose.
- `Test-Flight-Improv/test-gate-definitions.md` is the execution source of truth for named gates and known failures.
- `Test-Flight-Improv/14-regression-test-strategy.md` is the policy/rationale reference for how to combine direct suites with named gates.
- `Test-Flight-Improv/test-gates-reference.md` is not required for Session 29.

## 4. existing tests covering this area

Already present and relevant:
- `test/core/utils/flow_event_emitter_test.dart`
  - proves the local flow-event output contract and debugPrint capture style
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - covers the shared 1:1 send behavior on a path that already emits `CHAT_MSG_SEND_TIMING`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
  - covers 1:1 retry outcome behavior on a path that already emits `RETRY_FAILED_MESSAGES_TIMING`
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  - covers 1:1 upload-recovery ordering and resend behavior on a path that already emits `RETRY_INCOMPLETE_UPLOADS_TIMING`
- `test/features/conversation/application/upload_media_use_case_test.dart`
  - covers media upload success/failure behavior on a path that already emits `MEDIA_UPLOAD_TIMING`
- `test/features/conversation/application/download_media_use_case_test.dart`
  - covers media download success/failure behavior on a path that already emits `MEDIA_DOWNLOAD_TIMING`
- `test/features/groups/application/send_group_message_use_case_test.dart`
  - covers group/announcement send outcomes that can carry timing metadata
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  - covers retry outcome behavior for failed group sends
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - covers group upload recovery and resend behavior
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
  - covers rejoin behavior on a path that already emits timing output
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - covers group inbox drain behavior and already captures `[FLOW]` output in at least one error-path case
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  - already proves receive-side flow events for decrypt failure/error paths and provides the capture pattern if a representative receive-side proof is needed
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - covers lifecycle ordering if `handle_app_resumed.dart` is touched
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - covers lifecycle recovery wiring if `handle_app_resumed.dart` is touched
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - broader integration safety net for resume/recovery behavior

What is still missing:
- no direct regression today asserts the timing event shape for `CHAT_MSG_SEND_TIMING`, `RETRY_FAILED_MESSAGES_TIMING`, `RETRY_INCOMPLETE_UPLOADS_TIMING`, `MEDIA_UPLOAD_TIMING`, or `MEDIA_DOWNLOAD_TIMING`
- the current group application suites mostly prove behavior, not a normalized timing-contract output; the drain suite has some flow-event capture, but not a complete normalized timing contract
- no representative receive-side correlation proof exists if this session keeps the `E2E Message Latency` label
- `handle_app_resumed.dart` currently has ordering tests, but no direct test yet proves a normalized lifecycle summary event if that layer is touched

## 5. regression/tests to add first, if any

Yes. Add direct instrumentation regressions first, but only at the smallest deterministic seams.

Minimum first tests:
- one direct send-path test proving the selected normalized timing event shape for the representative send family touched in the same pass
- one direct media test proving the selected `MEDIA_UPLOAD_TIMING` or `MEDIA_DOWNLOAD_TIMING` shape, and both if both are normalized
- one retry test proving the selected retry path emits the intended timing/counter details
- one rejoin/drain test proving the selected connection/discovery timing event shape if group recovery seams are touched
- one receive-side direct test only if the session keeps the `E2E Message Latency` label for a representative path rather than narrowing the final result to send-side latency correlation readiness

Preferred pattern:
- capture `debugPrint` output the same way `test/core/utils/flow_event_emitter_test.dart` already does
- assert only the event name and the few key tags/fields that matter
- do not create brittle tests that snapshot entire logs
- add the regression inside the existing use-case test files for the touched seam before widening into any new integration coverage

Do not start with new integration tests unless the deterministic use-case tests are insufficient to prove the new local signals.

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Not required. This session is not profile-gated or evidence-gated.

The repo evidence is already enough to proceed:
- local timing events already exist in several key seams across both 1:1 and group/recovery paths
- the remaining gap is coherence and direct proof, not total absence
- the current gate ledger shows baseline and transport as revalidated green, so this session can treat those gates as regression checks rather than pre-existing failures

## 7. step-by-step implementation or evidence-collection plan

1. Re-open report 10 and lock the session to only these four gaps.
   - treat `E2E Message Latency` as one honest representative correlation slice, not a full new rollout, unless receive-side proof is explicitly added
   - keep the rest of the session focused on media throughput, retry effectiveness, and connection/discovery timing
2. Inventory the current local timing events in the targeted 1:1, media, group, and optional lifecycle files.
   - identify what already exists and should be preserved
   - identify only the smallest missing tags/events that would make comparison easier
3. Define one narrow local event contract per gap.
   - representative 1:1 or group send total
   - media upload/download total
   - retry outcome timing/counters for the touched family
   - rejoin/drain timing
   - if needed, one receive-side correlation seam that makes the E2E wording honest
4. Add the failing direct tests first.
   - keep them deterministic and local
   - use `debugPrint` capture rather than a new metrics harness
   - start with the touched conversation/group use-case tests rather than creating new harnesses
5. Implement the smallest safe instrumentation changes.
   - prefer normalizing existing `emitFlowEvent(...)` output
   - only add new events where a gap is real
   - prefer use-case-local seams
   - touch `handle_app_resumed.dart` only if inventory shows a real lifecycle-summary gap that cannot be covered sufficiently at use-case seams
6. Keep the instrumentation useful for the recent group/announcement work and the shared conversation/media pipeline.
   - compare representative 1:1 and group/announcement send totals where practical
   - include enough tags to distinguish group vs announcement paths when the same use case serves both
   - keep resume/rejoin timing tied to actual recovery steps rather than abstract generic counters
7. Re-run the direct tests.
8. Run the 1:1 Reliability Gate if shared conversation send, retry, upload, download, or representative receive code changed.
9. Run the Group Messaging Gate if group/application code changed.
10. Run the Baseline Gate if Flutter production code changed.
11. Run the Startup / Transport Gate only if the implementation touched `handle_app_resumed.dart` or other lifecycle/recovery orchestration.
12. Interpret gate results against the known-failure ledger in `Test-Flight-Improv/test-gate-definitions.md`.
    - for `baseline` and `transport`, require no new failures or widened failures beyond the current ledger
    - do not downgrade a failure unless it maps cleanly to a documented unrelated issue in the current ledger

## 8. risks and edge cases

- Do not accidentally turn this into `TimingProbe` / `SessionMetrics` infrastructure work.
- Do not duplicate already-sufficient timing events just to rename everything.
- Do not widen this into broad receive-side instrumentation if one representative seam or narrower wording makes the scope honest.
- Do not touch `handle_app_resumed.dart` just to mirror use-case-local timing that already exists.
- Do not skip the 1:1 Reliability Gate when shared conversation/media code changes.
- Do not add noisy nested-helper instrumentation that makes the output less useful.
- Do not change business logic or return values while adding instrumentation.
- Do not widen this into DB hotspot work beyond the four selected measurement gaps.
- Do not widen this into decrypt/error instrumentation work already covered elsewhere.
- Do not misread a previously documented red named gate as a Session 29 failure if the failure is already listed under known failures in `Test-Flight-Improv/test-gate-definitions.md` and is unrelated to the changed files.
- Do not require unconditional green from `baseline` or `transport` while unrelated known failures remain recorded in the gate ledger.

## 9. exact tests to run after implementation, if code changes occur

Direct tests:
- `flutter test test/core/utils/flow_event_emitter_test.dart`
- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`
- `flutter test test/features/conversation/application/upload_media_use_case_test.dart`
- `flutter test test/features/conversation/application/download_media_use_case_test.dart`
- `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `flutter test test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

Conditional receive-side direct tests only if a representative receive correlation seam is touched:
- `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart`

Conditional lifecycle direct tests only if `handle_app_resumed.dart` or lifecycle summary events are touched:
- `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart`

Optional nearby safety nets only if the direct tests leave ambiguity:
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart`
- `flutter test test/features/groups/integration/announcement_happy_path_test.dart` only if announcement-specific send/read/react behavior is touched

## 10. subsystem gate(s), if relevant

Required when shared conversation send, retry, upload, download, or representative receive code changes:
- 1:1 Reliability Gate
  - `./scripts/run_test_gates.sh 1to1`

Required when group/application code changes land:
- Group Messaging Gate
  - `./scripts/run_test_gates.sh groups`

Conditionally required:
- Startup / Transport Gate
  - only if the implementation changes lifecycle, resume, startup, or recovery orchestration

## 11. whether Baseline Gate is required

Yes, if Flutter production code changes land in the targeted measurement files.

Command:
- `./scripts/run_test_gates.sh baseline`

Interpretation note:
- evaluate any red result against the known-failure ledger in `Test-Flight-Improv/test-gate-definitions.md`
- treat any failure in the baseline gate as a Session 29 regression unless it maps cleanly to a documented unrelated issue in the current ledger
- the current ledger does not record an open Baseline Gate failure, so this gate should be expected to pass unless Session 29 introduces a regression

## 12. whether Startup / Transport Gate is required

No, not by default.

Run it only if the implementation changes:
- `handle_app_resumed.dart`
- rejoin / drain orchestration in a way that affects startup/resume behavior
- lifecycle-level recovery timing rather than only local application-level event details

Command when needed:
- `./scripts/run_test_gates.sh transport`

Interpretation note:
- if `transport` is run, use the same known-failure rule from `Test-Flight-Improv/test-gate-definitions.md`
- do not treat a transport failure as acceptable unless it maps cleanly to a documented unrelated issue in the current ledger
- the current ledger does not record an open Startup / Transport Gate failure, so this gate should be expected to pass unless Session 29 introduces a regression

## 13. done criteria

Session 29 is done when all of the following are true:
- the session stays limited to the four selected measurement gaps
- the scope stays honest: either a representative receive-side proof exists for any path called `E2E`, or the landed result is explicitly limited to send-side latency correlation readiness rather than full E2E rollout
- the missing local timing/counter coverage for the touched 1:1, media, group, and/or recovery seams is added or normalized using existing `emitFlowEvent(...)` style instrumentation
- no new observability package or exporter/dashboard infrastructure is introduced
- the direct instrumentation tests for the touched files pass
- the 1:1 Reliability Gate passes if shared conversation/media code changed
- the Group Messaging Gate passes if group/application code changed
- the Baseline Gate is rerun and shows no new or widened failures beyond the current known-failure ledger
- the Startup / Transport Gate is rerun if the implementation touched that layer and shows no new or widened failures beyond the current known-failure ledger

## 14. dependency impact on later sessions if this session blocks

If Session 29 blocks:
- the app still keeps its current local instrumentation, so reliability work does not regress
- what remains weaker is fast local comparison of representative 1:1/group send, media, retry, and rejoin behavior after the recent group/announcement hardening
- any representative receive-side latency correlation proof may remain incomplete
- future tuning sessions would have less clean evidence, but this is not a release-blocking prerequisite for core messaging correctness
