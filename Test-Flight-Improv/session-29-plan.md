# Session 29 Plan: Add Lean Local Measurement For Messaging Reliability

## 1. real scope

Close only the four highest-value measurement gaps from `10-network-measurement-strategy.md`, using the existing local `emitFlowEvent()` approach instead of building a new observability subsystem.

Targeted gaps from `## Critical Measurement Gaps`:
- **E2E Message Latency**
- **Media Throughput**
- **Retry Effectiveness**
- **Connection / Discovery Timing**

This session is intentionally narrower than the full strategy in report 10. It should improve local timing/counter visibility for the messaging paths that now matter most after the group-discussion and announcement reliability work.

Concrete repo evidence already narrows the scope:
- `lib/features/groups/application/send_group_message_use_case.dart` already emits `GROUP_SEND_MSG_TIMING`.
- `lib/features/conversation/application/upload_media_use_case.dart` already emits `MEDIA_UPLOAD_TIMING`.
- `lib/features/conversation/application/download_media_use_case.dart` already emits `MEDIA_DOWNLOAD_TIMING`.
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart` already emits `RETRY_FAILED_GROUP_MESSAGES_TIMING`.
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` already emits `RETRY_INCOMPLETE_GROUP_UPLOADS_TIMING`.
- `lib/features/groups/application/rejoin_group_topics_use_case.dart` already emits `GROUP_REJOIN_TOPICS_TIMING`.
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` already emits `GROUP_DRAIN_OFFLINE_INBOX_TIMING`.
- `lib/core/lifecycle/handle_app_resumed.dart` already has debug timing around inbox drain, rejoin, and retries, but the local flow-event picture is still uneven and not yet cleanly comparable end-to-end.

In scope:
- normalize and complete local timing/counter signals for the four targeted measurement gaps
- improve correlation across group/announcement send, media, retry, and resume/rejoin timing
- keep all new measurement local to `emitFlowEvent(...)` style output
- add only the smallest missing timing/counter events needed to compare reliability paths
- prove the new local signals with direct deterministic tests

Out of scope:
- creating `lib/core/observability/timing_probe.dart`
- creating `lib/core/observability/session_metrics.dart`
- exporter/dashboard/analytics infrastructure
- broad DB hotspot work
- decrypt/error visibility work outside the already-landed signals
- product-facing metrics UI
- wide instrumentation of every helper or nested sub-step

## 2. session classification

`implementation-ready`

Why:
- the targeted gaps are concrete and local
- the repo already has most of the needed event/timing seams
- the missing work is mostly normalization, completion, and direct proof rather than a new platform

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
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`

Primary tests:
- `test/core/utils/flow_event_emitter_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart` only as a broader safety net if needed

Gate / regression references:
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh transport` only if the implementation changes lifecycle / resume / recovery orchestration

Execution note:
- `Test-Flight-Improv/test-gate-definitions.md` is the execution source of truth for named gates and known failures.
- `Test-Flight-Improv/14-regression-test-strategy.md` is the policy/rationale reference for how to combine direct suites with named gates.
- `Test-Flight-Improv/test-gates-reference.md` is not required for Session 29.

## 4. existing tests covering this area

Already present and relevant:
- `test/core/utils/flow_event_emitter_test.dart`
  - proves the local flow-event output contract and debugPrint capture style
- `test/features/groups/application/send_group_message_use_case_test.dart`
  - covers group/announcement send outcomes that can carry timing metadata
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  - covers retry outcome behavior for failed sends
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - covers upload recovery and resend behavior
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
  - covers rejoin behavior that should carry timing output
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - covers group inbox drain behavior and resume catch-up flows
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - broader integration safety net for resume/recovery behavior

What is still missing:
- no single consistent local contract yet ties send, retry, media, and rejoin/drain timing into a narrow comparable set
- some targeted paths already emit timings, but the output shape and tags are not yet clearly normalized for group/announcement comparison
- `handle_app_resumed.dart` currently has useful debug timing, but not a fully consistent local event summary for the four targeted measurement gaps

## 5. regression/tests to add first, if any

Yes. Add direct instrumentation regressions first, but only at the smallest deterministic seams.

Minimum first tests:
- one direct test proving the selected messaging send path emits the intended normalized timing event shape
- one retry test proving the selected retry path emits the intended timing/counter details
- one rejoin/drain test proving the selected connection/discovery timing event shape

Preferred pattern:
- capture `debugPrint` output the same way `test/core/utils/flow_event_emitter_test.dart` already does
- assert only the event name and the few key tags/fields that matter
- do not create brittle tests that snapshot entire logs

Do not start with new integration tests unless the deterministic use-case tests are insufficient to prove the new local signals.

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Not required. This session is not profile-gated or evidence-gated.

The repo evidence is already enough to proceed:
- local timing events already exist in several key seams
- the remaining gap is coherence and coverage, not total absence

## 7. step-by-step implementation or evidence-collection plan

1. Re-open report 10 and lock the session to only these four gaps:
   - E2E message latency
   - media throughput
   - retry effectiveness
   - connection/discovery timing
2. Inventory the current local timing events in the targeted code files.
   - identify what already exists and should be preserved
   - identify only the smallest missing tags/events that would make comparison easier
3. Define one narrow local event contract per gap.
   - message send total
   - media upload/download total
   - retry outcome timing/counters
   - rejoin/drain timing
4. Add the failing direct tests first.
   - keep them deterministic and local
   - use `debugPrint` capture rather than a new metrics harness
5. Implement the smallest safe instrumentation changes.
   - prefer normalizing existing `emitFlowEvent(...)` output
   - only add new events where a gap is real
   - do not add a new observability package or shared metrics buffer
6. Keep the instrumentation useful for the recent group/announcement work.
   - compare text/media/voice send totals where practical
   - include enough tags to distinguish group vs announcement paths when the same use case serves both
   - keep resume/rejoin timing tied to actual group recovery steps rather than abstract generic counters
7. Re-run the direct tests.
8. Run the Group Messaging Gate if group/application code changed.
9. Run the Baseline Gate if Flutter production code changed.
10. Run the Startup / Transport Gate only if the implementation touched `handle_app_resumed.dart` or other lifecycle/recovery orchestration.
11. Interpret gate results against the known-failure ledger in `Test-Flight-Improv/test-gate-definitions.md`.
    - a pre-existing red `baseline` or `transport` item should not be treated as a Session 29 regression unless the changed code clearly caused or widened it

## 8. risks and edge cases

- Do not accidentally turn this into `TimingProbe` / `SessionMetrics` infrastructure work.
- Do not duplicate already-sufficient timing events just to rename everything.
- Do not add noisy nested-helper instrumentation that makes the output less useful.
- Do not change business logic or return values while adding instrumentation.
- Do not widen this into DB hotspot work beyond the four selected measurement gaps.
- Do not widen this into decrypt/error instrumentation work already covered elsewhere.
- Do not misread a previously documented red named gate as a Session 29 failure if the failure is already listed under known failures in `Test-Flight-Improv/test-gate-definitions.md` and is unrelated to the changed files.

## 9. exact tests to run after implementation, if code changes occur

Direct tests:
- `flutter test test/core/utils/flow_event_emitter_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `flutter test test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

Optional nearby integration safety net only if the direct tests leave a resume/recovery ambiguity:
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart`

## 10. subsystem gate(s), if relevant

Required only if group/application or lifecycle code changes land:
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
- only treat it as a Session 29 regression if the changed scope clearly introduced or widened the failure
- do not require unconditional green while unrelated known failures remain documented in the gate ledger

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
- do not reopen unrelated existing transport-gate failures as part of Session 29 unless the measurement changes clearly affect them

## 13. done criteria

Session 29 is done when all of the following are true:
- the session stays limited to the four selected measurement gaps
- the missing local timing/counter coverage for those gaps is added or normalized using existing `emitFlowEvent(...)` style instrumentation
- no new observability package or exporter/dashboard infrastructure is introduced
- the direct instrumentation tests pass
- the Group Messaging Gate passes if group/application code changed
- the Baseline Gate passes
- the Startup / Transport Gate passes if the implementation touched that layer

## 14. dependency impact on later sessions if this session blocks

If Session 29 blocks:
- the app still keeps its current local instrumentation, so reliability work does not regress
- what remains weaker is fast local comparison of send/media/retry/rejoin behavior after the recent group/announcement hardening
- future tuning sessions would have less clean evidence, but this is not a release-blocking prerequisite for core messaging correctness
