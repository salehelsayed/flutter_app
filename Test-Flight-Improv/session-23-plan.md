# Session 23 Plan: Extend Local Observability Without Building A New Observability Stack

## 1. real scope

Finish the still-missing local observability pieces from roadmap 16 Session 23 without reopening Session 11 into a broader observability subsystem.

Concrete repo evidence already narrows the scope:
- `lib/core/observability/timing_probe.dart` and `lib/core/observability/session_metrics.dart` do not exist.
- That is not a prerequisite failure by itself, because `Test-Flight-Improv/session-11-plan.md` explicitly says Session 11 should stay local to `emitFlowEvent()` / startup timing and should **not** introduce `lib/core/observability/`.
- The conversation-side decrypt-failure visibility gap is already substantially closed:
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` emits `CHAT_MSG_RECEIVE_DECRYPT_FAILED` and `CHAT_MSG_RECEIVE_DECRYPT_ERROR`.
  - `lib/features/conversation/application/chat_message_listener.dart` emits `CHAT_LISTENER_DECRYPT_FAILED`.
  - the corresponding direct tests already pin those events.
- The real remaining gap is the candidate DB hotspot file `lib/core/database/helpers/posts_db_helpers.dart`, which currently has insert start/success/error flow events but no helper timing probes around the heavier read paths such as `dbLoadPost`, `dbLoadPostsByIds`, and `dbLoadPostsFeed`.

In scope:
- confirm Session 11 is satisfied by the existing inline timing layer
- treat the decrypt-failure observability sub-scope as already satisfied unless execution finds a real missing local signal
- add the smallest safe inline DB helper timing probes in `posts_db_helpers.dart`
- prove those probes via helper-level regression(s) and nearby posts repository tests

Out of scope:
- creating `lib/core/observability/`
- exporter, dashboard, analytics pipeline, or snapshot infrastructure beyond a tiny local-only signal
- redesigning posts repositories or SQL shape
- changing conversation receive behavior unless execution discovers a real missing signal despite the current tests

## 2. session classification

`implementation-ready`

Why:
- the Session 11 prerequisite is satisfied by design, not blocked by missing `lib/core/observability/*`
- the decrypt-failure visibility part of Session 23 is already landed and therefore stale as an execution target
- the remaining DB hotspot observability gap in `posts_db_helpers.dart` is concrete, local, and small enough to implement directly

## 3. files and repos to inspect next

Primary planning / evidence files:
- `Test-Flight-Improv/16-session-todo-roadmap-2.md`
- `Test-Flight-Improv/15-session-todo-roadmap.md` Session 11
- `Test-Flight-Improv/session-11-plan.md`
- `Test-Flight-Improv/10-network-measurement-strategy.md`
- `Test-Flight-Improv/08-network-1to1-messaging.md`
- `Test-Flight-Improv/05-database-storage-performance.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`

Primary code:
- `lib/core/utils/flow_event_emitter.dart`
- `lib/core/utils/startup_timing.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/core/database/helpers/posts_db_helpers.dart`
- `lib/features/posts/domain/repositories/post_repository_impl.dart`

Primary tests:
- `test/core/utils/flow_event_emitter_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/core/database/helpers/posts_db_helpers_test.dart`
- `test/features/posts/phase1/posts_core_repository_test.dart`
- `test/features/posts/phase2/load_posts_feed_viewer_metrics_query_test.dart`
- `test/features/posts/phase5/posts_pins_repository_test.dart` only as optional nearby safety net if helper instrumentation touches pin-adjacent repository behavior unexpectedly

## 4. existing tests covering this area

Already present and relevant:
- `test/core/utils/flow_event_emitter_test.dart` proves the local flow-event output contract and `debugPrint` capture pattern.
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` already proves decrypt-returned-failure and decrypt-throw paths emit the expected local flow events.
- `test/features/conversation/application/chat_message_listener_test.dart` already proves listener-side decrypt-failure handling and `CHAT_LISTENER_DECRYPT_FAILED`.
- `test/core/database/helpers/posts_db_helpers_test.dart` currently covers `dbLoadPostsByIds(...)` shape on a real migrated DB, but not timing probes.
- `test/features/posts/phase1/posts_core_repository_test.dart` exercises `dbLoadPost(...)` and `dbLoadPostsByIds(...)` through `PostRepositoryImpl`.
- `test/features/posts/phase2/load_posts_feed_viewer_metrics_query_test.dart` exercises `dbLoadPostsFeed(...)` through `loadPostsFeed(...)`.
- `test/features/posts/phase5/posts_pins_repository_test.dart` is a nearby repository proof that should stay green if posts helper instrumentation changes nothing but observability.

What is missing:
- no direct regression today proves `posts_db_helpers.dart` emits local timing / hotspot signals for heavy read helpers

## 5. regression/tests to add first, if any

Yes. Add the smallest helper-level regression first in `test/core/database/helpers/posts_db_helpers_test.dart`.

That regression should:
- use the same `debugPrint` capture pattern as `test/core/utils/flow_event_emitter_test.dart`
- run against a real migrated in-memory DB
- prove the chosen heavy read helper(s) in `posts_db_helpers.dart` emit local DB timing signals without changing returned rows

Minimum first target:
- `dbLoadPost(...)` success plus miss behavior

Good narrow extension if the implementation touches them in the same pass:
- `dbLoadPostsByIds(...)`
- `dbLoadPostsFeed(...)`

If `dbLoadPostsByIds(...)` is instrumented in the same pass:
- extend the helper regression to cover the empty-input fast path as well
- prove that the empty-input branch stays quiet or intentionally shaped, but does not become noisy or failing by accident

If execution unexpectedly touches conversation observability code after re-checking the current repo state, add a direct regression first there too. Otherwise leave the conversation tests unchanged because that sub-scope is already covered.

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Not required. This session is not profile-gated or evidence-gated.

The existing repo evidence is already sufficient to proceed:
- Session 11 explicitly chose inline local timing over a new observability package
- conversation decrypt-failure signals already exist and are tested
- `posts_db_helpers.dart` still lacks helper timing probes on the heavy read paths

## 7. step-by-step implementation or evidence-collection plan

1. Reconfirm the Session 11 prerequisite from `Test-Flight-Improv/session-11-plan.md` before narrowing execution to posts helpers. Reopen representative landed inline-timing outputs in:
   - `lib/core/utils/startup_timing.dart`
   - `lib/features/conversation/application/send_chat_message_use_case.dart`
   - `lib/features/conversation/application/download_media_use_case.dart`
   - `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
   - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
   and document that missing `lib/core/observability/*` files are expected, not blocking.
2. Reconfirm the conversation-side decrypt-failure signals in:
   - `handle_incoming_chat_message_use_case.dart`
   - `chat_message_listener.dart`
   and leave that area untouched unless the code or tests reveal a real missing local signal.
3. Add the helper-level regression first in `test/core/database/helpers/posts_db_helpers_test.dart`, using `debugPrint` capture to prove local flow output from the selected helper(s).
4. Add the smallest inline timing probes in `lib/core/database/helpers/posts_db_helpers.dart` only around the heavy outer helper seams, not around every nested subquery or `PRAGMA`.
5. Keep the implementation local to `emitFlowEvent(...)`; do not introduce `lib/core/observability/`, shared exporter plumbing, or repository contract changes.
6. Preserve helper semantics exactly:
   - `dbLoadPost(...)` must still return `null` on a miss
   - `dbLoadPostsByIds(...)` must still preserve the current requested-row behavior
   - `dbLoadPostsFeed(...)` must still preserve current filtering and ordering
7. Rerun the helper regression, the nearby posts repository tests, and `test/core/utils/flow_event_emitter_test.dart`.
8. If only posts helper instrumentation landed, run the Posts / Privacy Gate and the Baseline Gate.
9. Run the 1:1 Reliability Gate only if execution unexpectedly changes conversation observability behavior boundaries.

## 8. risks and edge cases

- Do not misclassify the missing `lib/core/observability/*` files as a blocker; Session 11 explicitly deferred that architecture.
- Do not duplicate the Session 21 conversation work by re-instrumenting decrypt-failure paths that are already visible and tested.
- Do not change return values, row ordering, or null/miss behavior while adding timing probes.
- `dbLoadPost(...)` miss cases must remain non-error outcomes.
- `dbLoadPostsByIds(...)` has an empty-input fast path; instrumentation must not accidentally turn that into noisy or failing behavior.
- `posts_db_helpers.dart` already uses schema-introspection queries internally; timing probes should sit at the helper boundary so the output stays useful instead of overly chatty.
- `emitFlowEvent()` is still local/debug-oriented instrumentation, not a production analytics system.

## 9. exact tests to run after implementation, if code changes occur

Direct tests:
- `flutter test test/core/utils/flow_event_emitter_test.dart`
- `flutter test test/core/database/helpers/posts_db_helpers_test.dart`
- `flutter test test/features/posts/phase1/posts_core_repository_test.dart`
- `flutter test test/features/posts/phase2/load_posts_feed_viewer_metrics_query_test.dart`

Conditional nearby safety-net only if helper instrumentation unexpectedly affects pin-adjacent repository behavior:
- `flutter test test/features/posts/phase5/posts_pins_repository_test.dart`

Only if conversation observability code unexpectedly changes:
- `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `flutter test test/features/conversation/application/chat_message_listener_test.dart`

## 10. subsystem gate(s), if relevant

Required if posts helper instrumentation lands:
- Posts / Privacy Gate
  - `./scripts/run_test_gates.sh posts`

Conditionally required only if execution unexpectedly changes conversation observability behavior:
- 1:1 Reliability Gate
  - `./scripts/run_test_gates.sh 1to1`

## 11. whether Baseline Gate is required

Yes, if Flutter production code changes land in `posts_db_helpers.dart`.

Command:
- `./scripts/run_test_gates.sh baseline`

## 12. whether Startup / Transport Gate is required

No, unless execution unexpectedly changes startup, resume, bridge, or transport code.

The planned scope does not touch those layers.

## 13. done criteria

Session 23 is done when all of the following are true:
- the prerequisite call is explicit: Session 11’s inline timing layer is sufficient by design, and missing `lib/core/observability/*` files are not treated as a blocker
- the decrypt-failure observability sub-scope is either left untouched because the existing Session 21 signals are already sufficient, or only minimally adjusted if execution finds a real gap
- `posts_db_helpers.dart` has local hotspot timing probes or equivalent local signals on the selected heavy read helper seams
- the added observability remains local to `emitFlowEvent(...)` and does not create a new observability subsystem
- helper semantics remain unchanged
- the direct tests pass
- the Posts / Privacy Gate passes if posts helper code changed
- the Baseline Gate passes

## 14. dependency impact on later sessions if this session blocks

If Session 23 blocks:
- later work can still proceed, because the repo already has local timing for send/retry/media flows and explicit decrypt-failure visibility from Session 21
- the main thing that remains weaker is local ranking/debugging of heavy posts DB helper paths
- future posts performance or cleanup sessions would have less direct local evidence for where the helper time is going

This is therefore a useful but non-foundational follow-up, not a release-blocking prerequisite for unrelated sessions.
