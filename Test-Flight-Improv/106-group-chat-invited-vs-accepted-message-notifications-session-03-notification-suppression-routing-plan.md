# 106 Group Chat Invited vs Accepted Message Notifications - Session 03 Plan

Status: accepted

Session: `03-notification-suppression-routing`

## Planning Progress

- 2026-06-04 20:25:37 CEST - Arbiter completed. Files inspected since last update: reviewed plan sections, reviewer findings, closure bar, direct tests, named gates, simulator commands, and scope guard. Decision/blocker: no structural blockers remain; incremental wording details were already applied. Next action: send plan to execution.
- 2026-06-04 20:25:11 CEST - Arbiter started. Files inspected since last update: reviewed plan sections and reviewer findings. Decision/blocker: no new structural blocker identified so far; review findings appear to be applied incremental details. Next action: write arbiter classification and, if no blocker remains, mark the plan execution-ready.
- 2026-06-04 20:25:11 CEST - Reviewer completed. Files inspected since last update: full draft plan. Decision/blocker: sufficient with adjustments; no structural blocker. Adjustments applied for conditional gates and simulator background/tap wording. Next action: start Arbiter.
- 2026-06-04 20:24:17 CEST - Reviewer started. Files inspected since last update: draft plan artifact, source/breakdown evidence already listed, simulator runner path handling, and gate definitions. Decision/blocker: review focus is sufficiency, simulator closure, background local-state feasibility, scope drift into session 04, and known failure interpretation. Next action: write reviewer findings and classify any missing structural items.
- 2026-06-04 20:24:17 CEST - Planner completed. Files inspected since last update: no new files beyond evidence set; draft written in this plan. Decision/blocker: no blocker; draft is implementation-ready in shape and includes a background-safe resolver stop condition, direct RED tests, named gates, and path-addressable reliability simulator commands. Next action: start Reviewer.

## Execution Progress

- 2026-06-04 20:30:41 CEST - Phase: pre-edit status captured. Files inspected: `git status --short` and scoped `git diff --` for planned notification/routing/test/simulator files. Command currently running: none. Decision/blocker: dirty worktree is expected; pre-existing scoped dirty diff found only in `lib/main.dart` for migration/retry wiring unrelated to session 03, so future edits must preserve those hunks. Next action: inspect existing notification fallback and tap-routing seams plus direct tests before adding RED regressions.
- 2026-06-04 20:29:59 CEST - Phase: Executor started. Files inspected: session plan and execution skill contract. Command currently running: none. Decision/blocker: executing session `03-notification-suppression-routing` only as fresh Executor; QA Reviewer role intentionally not performed. Next action: capture dirty worktree status plus scoped diffs for planned touch files before RED-first tests and production edits.
- 2026-06-04 20:28:25 CEST - Phase: contract extracted by execution controller. Files inspected: this session plan, `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-breakdown.md`, `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`, and current `git status --short`. Command currently running: none. Decision/blocker: execution can proceed for session `03-notification-suppression-routing` only; spawned-agent support is available and the Executor prompt will explicitly request `model: gpt-5.5` and `reasoning_effort: xhigh`. Exact scope is receiver-side group-message fallback suppression and tap-routing hardening, preserving accepted/current-member group behavior and `group_invite` Intros routing. Required direct tests are the focused push/background/foreground/route/open/deeplink/dedupe suites listed below; required named gates are `./scripts/run_test_gates.sh groups`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, plus conditional `runtime-telemetry` and `completeness-check` if touched scope requires them; simulator closure requires the listed foreground group push and notification-open smoke commands. Stop condition: if background-safe local-state resolution cannot be implemented narrowly without breaking accepted-member fallback notifications, persist an evidence-gated/blocking result instead of weakening the contract. Next action: spawn the fresh Executor agent.
- 2026-06-04 20:29:40 CEST - Phase: Executor spawned/running. Files inspected/touched by controller: this plan only. Command currently running: spawned Executor agent `019e93e5-d57c-7c50-b8a0-c740da642d5f` with prompt explicitly requesting `model: gpt-5.5` and `reasoning_effort: xhigh`. Decision/blocker: awaiting isolated Executor implementation, direct test/gate evidence, and persisted progress; no controller-side coding is in progress. Next action: wait for Executor completion, then spawn a fresh QA Reviewer.
- 2026-06-04 20:34:17 CEST - Phase: Executor child closed; local sequential fallback started. Files inspected/touched by controller: this plan and `mobile-notification-routing-and-deep-linking` skill guidance. Command currently running: none; Executor agent `019e93e5-d57c-7c50-b8a0-c740da642d5f` was closed after bounded waits with previous status `running`. Decision/blocker: child produced heartbeat-only progress and no code/test/doc completion evidence, so continuing under the skill's bounded local sequential fallback path; no partial child code/test work exists to merge or disambiguate. Next action: perform Executor responsibilities locally, then run local QA before any final verdict.
- 2026-06-04 20:39:25 CEST - Phase: RED regressions added locally. Files inspected/touched: `lib/features/push/application/background_push_notification_fallback.dart`, `lib/features/push/application/background_message_handler.dart`, `lib/features/push/application/handle_foreground_remote_message_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_target.dart`, `lib/main.dart`, `test/features/push/application/background_push_notification_fallback_test.dart`, `test/features/push/application/background_message_handler_test.dart`, and `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`. Command currently running: none. Decision/blocker: RED tests now assert current-member display eligibility, pending/missing/non-member suppression, foreground fallback suppression, background no-show/no-mark suppression, and `group_invite` Intros preservation; production APIs are intentionally not implemented yet. Next action: run the fastest focused RED compile/test slice before production wiring.
- 2026-06-04 20:40:15 CEST - Phase: RED test confirmed. Files inspected/touched: `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`. Command finished: `flutter test --no-pub test/features/push/application/resolve_group_notification_route_target_use_case_test.dart` failed at compile with missing `resolveGroupMessageNotificationDisplayEligibility`, proving the new regression is active before production changes. Decision/blocker: no blocker; proceed to implement the narrow display eligibility API and wire foreground/background call sites. Next action: production edits.
- 2026-06-04 20:42:53 CEST - Phase: production wiring and first focused tests completed. Files touched: `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/background_push_notification_fallback.dart`, `lib/features/push/application/background_message_handler.dart`, `lib/main.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/features/push/application/background_push_notification_fallback_test.dart`, and `test/features/push/application/background_message_handler_test.dart`. Commands finished: `flutter test --no-pub test/features/push/application/resolve_group_notification_route_target_use_case_test.dart` passed; `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart` passed; `flutter test --no-pub test/features/push/application/background_message_handler_test.dart` passed. Decision/blocker: narrow local-state display eligibility now fails closed for ordinary group-message fallback without local identity/current membership, preserves current-member display through explicit proof, keeps `group_invite` on Intros, and background suppression does not show or mark recent remote announcements. Next action: run the remaining required direct tests.
- 2026-06-04 20:44:04 CEST - Phase: required direct tests completed. Files touched: same session 03 production/test set. Commands finished: `flutter test --no-pub test/features/push/application/handle_foreground_remote_message_use_case_test.dart` passed; `flutter test --no-pub test/features/push/application/prepare_notification_open_use_case_test.dart` passed; `flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart` passed; `flutter test --no-pub test/integration/notification_deeplink_integration_test.dart` passed; `flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart` passed. Decision/blocker: all eight required direct tests from the plan have passed. Conditional direct tests were not run because `push_decrypt_preview_test.dart`, `notification_route_target_test.dart`, and `show_notification_use_case_test.dart` contracts were not touched. Next action: run required named gates and conditional `runtime-telemetry` gate because suppression flow events changed.
- 2026-06-04 20:45:31 CEST - Phase: named gate `groups` finished. Files touched: same session 03 production/test set. Command finished: `./scripts/run_test_gates.sh groups` passed. Decision/blocker: no group gate blocker. Next action: run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`.
- 2026-06-04 20:48:14 CEST - Phase: named gate `baseline` finished. Files touched: same session 03 production/test set. Command finished: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed, including macOS smoke portions. Decision/blocker: no baseline blocker. Next action: run conditional `./scripts/run_test_gates.sh runtime-telemetry`.
- 2026-06-04 20:49:00 CEST - Phase: conditional named gate `runtime-telemetry` finished; simulator gates starting. Files touched: same session 03 production/test set. Command finished: `./scripts/run_test_gates.sh runtime-telemetry` passed. Decision/blocker: no telemetry gate blocker; `completeness-check` is not required because no new test files, simulator files, or gate definitions were added. Next action: run reliability simulator closure commands, starting with the required group list pass.
- 2026-06-04 21:01:38 CEST - Phase: simulator closure gap identified. Files inspected: `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart`, `integration_test/foreground_group_push_simulator_bob_harness.dart`, `integration_test/scripts/run_notification_open_ui_smoke.dart`, `integration_test/notification_open_ui_smoke_test.dart`, and app tap-routing code in `lib/main.dart`. Command finished earlier: `$run-flutter-reliability-sims group --list` passed as discovery-only and resolved runnable simulator commands. Decision/blocker: existing foreground simulator only proves S1/S2 accepted-member catch-up/dedupe, and existing notification-open smoke only proves basic group-message/group-invite taps; before simulator gates can count as session 03 closure, add narrow existing-file rows for foreground non-current-member no-fallback and tap routing current/pending/missing outcomes. Next action: patch the two simulator harnesses and orchestrator script, then run direct/simulator gates.
- 2026-06-04 21:07:15 CEST - Phase: simulator rows added and host smoke checked. Files touched: `integration_test/foreground_group_push_simulator_bob_harness.dart`, `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart`, and `integration_test/notification_open_ui_smoke_test.dart`. Commands finished: `dart format` on the three simulator files passed; `flutter test --no-pub integration_test/notification_open_ui_smoke_test.dart` was blocked before test execution by multiple connected devices; `flutter test --no-pub -d macos integration_test/notification_open_ui_smoke_test.dart` passed with the new current-member, pending-invite redirect, and missing-group suppression rows. Decision/blocker: no host compile blocker; existing simulator files were extended, so `completeness-check` remains not required by the plan's new-file/gate-definition condition. Next action: run required `$run-flutter-reliability-sims` foreground and notification-open simulator commands.
- 2026-06-04 21:11:05 CEST - Phase: required simulator gates passed. Files touched: same simulator files plus previously listed session 03 production/test set. Commands finished: `$run-flutter-reliability-sims group --only integration_test/scripts/run_foreground_group_push_simulator_smoke.dart` passed; S1 accepted-member foreground gap recovery PASS, S2 live-first replay dedupe PASS, and new S3 non-current/missing-group foreground fallback suppression PASS with `result=notificationNeeded`, `drainAttempts=1`, `fallbackShown=false`, `genericNotificationCount=0`, and suppression reason `group_missing`. `$run-flutter-reliability-sims group --only integration_test/scripts/run_notification_open_ui_smoke.dart` passed on iOS simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, including rows for current-member group open, pending-invite redirect to Intros, and missing-group suppression without group navigation. Decision/blocker: required simulator closure evidence is now present; no simulator environment blocker remains. Next action: spawn the fresh QA Reviewer and persist the final session 03 execution/QA verdict after review.
- 2026-06-04 21:12:36 CEST - Phase: QA Reviewer completed with blocker; fix loop 1 starting. Files inspected by QA: scoped session 03 code/tests/docs. QA verdict: `qa_blocked`. Blocking issue: `resolveBackgroundPushFallbackDisplayEligibility` only applies membership display eligibility to `isGroupMessageLikeRemoteData`, so legacy payload-only group routes such as `payload=group:<id>|message:<id>` bypass the resolver and can still show dead-end group fallback notifications. Required fix: apply display eligibility to any parsed `NotificationRouteTargetKind.group` route while preserving `group_invite -> intros`, and add focused payload-only group route regressions for denied and allowed display. Next action: run bounded fix loop 1 for this exact issue, then rerun focused push tests and QA.
- 2026-06-04 21:12:50 CEST - Phase: fix loop 1 Executor started. Files inspected: `lib/features/push/application/background_push_notification_fallback.dart`, `test/features/push/application/background_push_notification_fallback_test.dart`, and scoped diffs. Command currently running: spawned fix Executor agent `019e940b-a279-7913-9f74-dc7c8f3ca640` with prompt explicitly requesting `model: gpt-5.5` and `reasoning_effort: xhigh`. Decision/blocker: QA blocker confirmed; current display eligibility checks explicit group-message metadata before parsed route kind, so payload-only `group:<id>|message:<id>` routes bypass the resolver. Next action: patch eligibility to inspect the parsed route target first, keep non-group/`group_invite` routes allowed, and add payload-only denied/allowed regressions.
- 2026-06-04 21:13:28 CEST - Phase: fix loop 1 Executor completed. Files touched: `lib/features/push/application/background_push_notification_fallback.dart` and `test/features/push/application/background_push_notification_fallback_test.dart`. Command finished by fix Executor: `dart format lib/features/push/application/background_push_notification_fallback.dart test/features/push/application/background_push_notification_fallback_test.dart` passed; `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart` passed. Decision/blocker: QA blocker fixed in the scoped helper by applying display eligibility to every parsed `NotificationRouteTargetKind.group` route, including payload-only legacy routes, while non-group routes and `group_invite -> intros` remain allowed without membership. Added focused regressions for payload-only denied `local_member_missing` suppression and current-member fallback preservation. Next action: controller reruns impacted push suites, then fresh QA Reviewer verifies fix-loop sufficiency.
- 2026-06-04 21:14:08 CEST - Phase: fix loop 1 controller verification passed. Files touched: `lib/features/push/application/background_push_notification_fallback.dart`, `test/features/push/application/background_push_notification_fallback_test.dart`, plus previously touched background/display eligibility suites. Command finished: `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/background_message_handler_test.dart test/features/push/application/resolve_group_notification_route_target_use_case_test.dart` passed (`+63`). Decision/blocker: payload-only legacy group fallback is now covered by direct denied/allowed regressions, background handler suppression still passes, and display eligibility use-case regressions still pass. Next action: spawn a fresh QA Reviewer for final session 03 QA.
- 2026-06-04 21:15:49 CEST - Phase: post-fix QA Reviewer completed with second blocker; fix loop 2 starting. Files inspected by QA: scoped session 03 code/tests/docs. QA verdict: `qa_blocked`. Blocking issue: `showForegroundPushFallbackNotificationIfNeeded` reuses background display eligibility, which rejects `RemoteMessage.notification != null`; foreground OS presentation is disabled, so a current-member foreground `group_message` with an FCM notification object and drain error can fail to show the required local fallback. Required fix: keep the background path skipping visible provider notifications, but split foreground eligibility so foreground fallback checks parsed route plus membership without rejecting `message.notification`; add focused regressions for current-member foreground `group_message` with `RemoteNotification` showing fallback and non-current/missing membership still suppressing it. Next action: run bounded fix loop 2 for this exact issue, then rerun focused push tests and QA.
- 2026-06-04 21:18:45 CEST - Phase: fix loop 2 Executor started. Files inspected: `lib/features/push/application/background_push_notification_fallback.dart`, `test/features/push/application/background_push_notification_fallback_test.dart`, and scoped QA blocker. Command currently running: none. Decision/blocker: confirmed the foreground helper delegates into background eligibility and therefore rejects `RemoteMessage.notification != null`; patch will split foreground eligibility from background visible-provider skipping while preserving parsed-route and membership checks. Next action: patch only the scoped fallback helper/test files, then run `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart`.
- 2026-06-04 21:20:05 CEST - Phase: fix loop 2 Executor completed. Files touched: `lib/features/push/application/background_push_notification_fallback.dart`, `test/features/push/application/background_push_notification_fallback_test.dart`, and this plan progress section. Commands finished: `dart format lib/features/push/application/background_push_notification_fallback.dart test/features/push/application/background_push_notification_fallback_test.dart` passed; `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart` passed (`+38`); `flutter test --no-pub test/features/push/application/background_message_handler_test.dart` passed (`+12`). Decision/blocker: QA blocker fixed in the scoped fallback helper by splitting foreground display eligibility from background visible-provider-notification skipping; background eligibility and `firebaseMessagingBackgroundHandler` still suppress local fallback when `RemoteMessage.notification != null`, while foreground fallback now checks parsed route plus group display eligibility without rejecting solely on visible FCM payload. Added regressions for current-member foreground `group_message` with `RemoteNotification` showing fallback and non-current/missing membership suppressing it. Next action: fresh QA Reviewer verifies fix-loop sufficiency.
- 2026-06-04 21:21:01 CEST - Phase: fix loop 2 controller verification passed. Files touched: same fix loop 2 fallback helper/test files plus previously touched background/display eligibility suites. Command finished: `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/background_message_handler_test.dart test/features/push/application/resolve_group_notification_route_target_use_case_test.dart` passed (`+65`). Decision/blocker: foreground current-member visible FCM payload fallback, foreground non-current visible payload suppression, payload-only legacy group suppression/preservation, background visible-provider skip, background group suppression, and display eligibility all pass together. Next action: fresh QA Reviewer, then rerun required direct/named/simulator gates or record any exact blocked gates after QA.
- 2026-06-04 21:21:56 CEST - Phase: full required direct tests rerun after fix loops. Files touched: same session 03 fallback/background/route/test/simulator set. Command finished: `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/background_message_handler_test.dart test/features/push/application/handle_foreground_remote_message_use_case_test.dart test/features/push/application/resolve_group_notification_route_target_use_case_test.dart test/features/push/application/prepare_notification_open_use_case_test.dart test/features/push/application/chat_and_group_push_open_flow_test.dart test/integration/notification_deeplink_integration_test.dart test/integration/group_notification_dedupe_integration_test.dart` passed (`+97`). Decision/blocker: all required direct tests are current after both QA fix loops; conditional direct tests remain not required because preview, route parsing contract files, and show-notification contract files were not touched. Next action: rerun required named gates after production fallback changes.
- 2026-06-04 21:38 CEST - Phase: execution/QA verdict persisted by controller fallback. Files inspected/updated: this plan and the breakdown. Commands finished after fix loop 2: fresh QA Reviewer returned clean; post-fix `./scripts/run_test_gates.sh groups` passed (`+319`); post-fix `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed (host `+98`, loading smoke `+7`, posts smoke `+1`); post-fix `./scripts/run_test_gates.sh runtime-telemetry` passed (`+4`); foreground group push simulator passed including S3 `fallbackShown=false`, reason `group_missing`; notification-open UI smoke passed on iOS simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, including current-member open, pending-invite Intros redirect, and missing-group suppression. Decision/blocker: no session 03 execution blocker remains; the execution child completed evidence but its final artifact patch failed on stale context, so the controller persisted the verdict locally under the bounded fallback. `completeness-check` was not required because existing simulator/test files were extended without new gate definitions. Next action: spawn a fresh closure audit for session `03`, then advance to session `04`.

## final verdict

Final verdict: `accepted`.

Execution/QA verdict: accepted for session `03-notification-suppression-routing`. The implementation now suppresses ordinary group-message local fallback and stale/dead-end tap routing unless local state proves current membership, preserves current-member foreground/background fallback behavior and `group_invite` Intros routing, and carries post-fix direct test, named gate, telemetry, and simulator evidence. Closure audit still owns ledger/source-doc closure and session `04` still owns final mixed-recipient acceptance and matrix closure.

## final plan

### real scope

Session `03-notification-suppression-routing` owns receiver-side defenses for stale, legacy, malformed, or incorrectly targeted ordinary `group_message` notification payloads.

In scope:

- Prevent foreground and background local fallback notifications for ordinary `group_message` payloads unless local state proves the recipient is a current local group member for that `groupId`.
- Keep accepted/current member group-message fallback behavior working when the app should show a notification.
- Preserve `group_invite` routing to Intros.
- Preserve notification tap behavior for current group members and pending-invite redirects.
- Harden missing group / missing invite group-message taps so they are telemetry-backed suppressions or understandable redirects, not silent navigation dead ends.
- Add or extend session-owned direct and simulator evidence for foreground/background suppression and tap routing.

Out of scope:

- Sender-side accepted-recipient filtering, native reliable-send recipient preservation, and relay custody changes. Session `02-recipient-eligibility` is already closed for that scope.
- Final mixed accepted/unaccepted journey closure, final matrix updates, and final program verdict. Session `04-acceptance-closure` owns those.
- Creator/admin status copy, group creation roster semantics, Orbit redesign, notification visual design, APNs/TestFlight provider proof, and broad DB/bootstrap rewrites.

### closure bar

This session is good enough when all of these are true:

- A data-only or foreground `group_message` payload for a group where the local user is not a current group member does not create a local fallback notification, including missing group, stale local group without local membership, expired/declined/revoked/invalid invite state represented by no actionable current membership, and never-stored invite state.
- A `group_message` payload for a valid current local member preserves existing background fallback, foreground fallback-on-drain-error, duplicate suppression, recent remote announcement, active-view suppression, and tap-to-group behavior.
- A `group_invite` payload still routes to Intros and is not reclassified as a group message.
- If a stale or provider-visible group notification is tapped anyway, current local members open the group, pending invite state redirects to Intros, and missing group/missing invite emits explicit leak-safe flow evidence and does not navigate to an empty group.
- RED-first direct regressions exist for background fallback suppression, background handler show/no-show behavior, foreground fallback suppression, tap resolver state handling, and preservation controls for current members and group invites.
- Session-owned simulator proof exists through `$run-flutter-reliability-sims` for foreground group-message suppression and background/terminated notification open or tap behavior. If the required simulator devices are unavailable, execution must mark the session `evidence-gated` rather than accepted.

### source of truth

Authoritative docs:

- `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-breakdown.md`
- `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md`

Authoritative code/test seams:

- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/features/push/application/push_decrypt_preview.dart`
- `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
- `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/core/notifications/notification_route_target.dart`
- `lib/main.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/integration/group_notification_dedupe_integration_test.dart`
- `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart`
- `integration_test/scripts/run_notification_open_ui_smoke.dart` or `scripts/run_ios_notification_tap_ui_smoke.sh` if tap proof is added there.

Disagreement rule: current code and tests win over stale prose; `Test-Flight-Improv/test-gate-definitions.md` plus `scripts/run_test_gates.sh` define named gates, with the script winning if they disagree.

### session classification

`implementation-ready`.

There is no current structural blocker. The executor must still stop and reclassify to `evidence-gated` if it cannot implement a background-safe local-state resolver without breaking accepted-member fallback notifications.

### exact problem statement

Session `02` now prevents ordinary sender fanout from targeting non-joined invitees, but receiver-side push code still trusts a routable `group_message` payload:

- `shouldShowBackgroundPushFallbackNotification` returns true when `NotificationRouteTarget.fromRemoteMessageData` can parse the payload, without checking local group, local membership, or pending-invite state.
- `firebaseMessagingBackgroundHandler` can show a local notification and mark a remote announcement for a group route that the app cannot open.
- `handleForegroundRemoteMessage` returns `notificationNeeded` after a group drain error, and `showForegroundPushFallbackNotificationIfNeeded` can show a group fallback from the same stale payload.
- Tap resolution already refuses stale groups without local membership and redirects pending invites, but missing group/missing invite currently only emits `GROUP_NOTIFICATION_ROUTE_GROUP_MISSING` and returns.

What must improve: group-message fallback display must require current local membership; stale provider-visible or legacy local taps must resolve to group, Intros, or explicit suppression evidence; accepted/current members and invite notifications must keep existing behavior.

### files and repos to inspect next

Production files to inspect/touch narrowly:

- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/features/push/application/push_decrypt_preview.dart` only if suppression composes with background preview resolution.
- `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
- `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `lib/core/notifications/notification_route_target.dart` only if route parsing details change.
- `lib/main.dart` for foreground push and notification tap wiring.
- `lib/core/database/encrypted_db_opener.dart`, `lib/core/database/helpers/groups_db_helpers.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`, and `lib/core/database/helpers/pending_group_invites_db_helpers.dart` only to prove or wire a background-safe local-state resolver.

Tests/harnesses to inspect/touch:

- `test/features/push/application/background_push_notification_fallback_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/features/push/application/push_decrypt_preview_test.dart` if preview composition changes.
- `test/integration/notification_deeplink_integration_test.dart`
- `test/integration/group_notification_dedupe_integration_test.dart`
- `integration_test/foreground_group_push_simulator_bob_harness.dart`
- `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart`
- `integration_test/notification_open_ui_smoke_test.dart`, `integration_test/scripts/run_notification_open_ui_smoke.dart`, or `scripts/run_ios_notification_tap_ui_smoke.sh` for tap simulator proof.
- `Test-Flight-Improv/test-gate-definitions.md` only if new test files or new simulator commands are added.

### existing tests covering this area

Already covered:

- `background_push_notification_fallback_test.dart` documents current permissive group fallback and protected preview copy.
- `background_message_handler_test.dart` covers background show, duplicate fallback suppression, and recent remote announcement marking after successful group fallback display.
- `handle_foreground_remote_message_use_case_test.dart` covers targeted group drains, missing group id telemetry, group invite/intros routing, and current behavior where group drain failures request a local fallback.
- `resolve_group_notification_route_target_use_case_test.dart` covers current group route, pending invite redirect, missing group/invite, stale group without local membership, and recovery after draining.
- `prepare_notification_open_use_case_test.dart`, `chat_and_group_push_open_flow_test.dart`, and `notification_deeplink_integration_test.dart` cover prepare-before-route sequencing for group opens.
- `group_notification_dedupe_integration_test.dart` covers successful background group announcement suppressing later local listener notification for the same message.
- `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart` currently proves accepted-member foreground group catch-up and dedupe, not unaccepted/missing-recipient suppression.

Missing:

- No current test prevents background local fallback display for `group_message` when local membership is missing.
- No current test prevents foreground fallback display after a group drain error caused by missing/non-current group state.
- No simulator scenario currently proves the unaccepted/missing invite receiver state for session 03.
- No tap/open simulator scenario currently proves missing group/missing invite suppression or pending-invite redirect for this report.

### regression/tests to add first

Add RED tests before production changes:

1. `background_push_notification_fallback_test.dart` or a new focused eligibility-use-case test:
   - Current local member for `group_message` returns display-allowed and preserves payload `group:<id>|message:<id>`.
   - Missing group/no pending invite returns display-suppressed with a leak-safe reason such as `group_not_current_member` or `group_missing`.
   - Existing group with absent local member returns display-suppressed.
   - Pending invite state does not display an ordinary group-message fallback; it remains available for tap redirect if an already-visible notification is opened.
   - `group_invite` remains routable to `intros`.
2. `background_message_handler_test.dart`:
   - Inject a resolver that denies a `group_message` fallback and assert no `show` call, no recent remote announcement mark, and a `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED` flow event with no group name/message text.
   - Add the current-member control where the resolver allows fallback and the existing show + mark behavior remains.
3. `handle_foreground_remote_message_use_case_test.dart` and/or `background_push_notification_fallback_test.dart`:
   - Group drain error plus local non-current membership does not request or show a fallback notification.
   - Group drain error plus proven current local membership still requests/shows fallback, preserving accepted-member behavior.
   - `group_invite` and `intros` still use the 1:1/intros path, not group fallback.
4. `resolve_group_notification_route_target_use_case_test.dart` and `notification_deeplink_integration_test.dart`:
   - Current member route opens group.
   - Pending invite redirect remains Intros.
   - Missing group/missing invite emits or returns an explicit missing/suppressed outcome and does not navigate to group.
5. Simulator:
   - Extend `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart` and Bob harness with a session 03 scenario that injects a `group_message` foreground push for a group Bob has not joined or no longer has as current local member, then proves no local fallback notification and no group route.
   - Add or extend a notification-open simulator row in `integration_test/scripts/run_notification_open_ui_smoke.dart` or `scripts/run_ios_notification_tap_ui_smoke.sh` for pending invite redirect and missing group/missing invite suppression.

### step-by-step implementation plan

1. Capture `git status --short` and scoped diffs for planned touch files. Preserve user/other-agent changes; do not revert unrelated dirty worktree edits.
2. Add a small local-state decision seam for group-message notification display. Prefer a focused use case such as `resolveGroupMessageNotificationDisplayEligibility` that accepts `groupId`, `GroupRepository`, optional `PendingGroupInviteRepository`, and optional `localPeerId`, then returns `allowCurrentMember`, `suppressPendingInvite`, `suppressMissing`, or `suppressUnknownLocalIdentity`.
3. Add RED tests for that decision seam and for the existing background/foreground call sites before production wiring.
4. Wire foreground fallback display through the eligibility decision using already-open app repositories in `main.dart`. The handler may still drain first, but fallback display must be denied when local state is not current membership.
5. Wire background fallback through an injectable async display resolver. The executor must first prove a background-safe way to resolve local group/member/pending-invite state using existing encrypted DB and helper patterns. If that cannot be done narrowly, stop and mark the session `evidence-gated`; do not blanket-suppress all group-message fallback and break accepted members.
6. Keep `buildBackgroundPushFallbackNotification` and `resolveBackgroundPushNotification` behavior for accepted/current members intact. If suppression composes with preview decryption, check suppression before expensive decrypt where possible and keep telemetry leak-safe.
7. Harden tap routing only at the existing resolver/main boundary: current member opens group, pending invite opens Intros, missing group/invite emits explicit suppression/missing evidence and does not attempt a group route. Add a small extracted helper only if direct testing `main.dart` behavior would otherwise require a broad widget harness.
8. Extend the existing foreground group push simulator or add the smallest session-owned scenario for unaccepted/missing receiver suppression. Extend an existing notification-open simulator path for missing/pending tap behavior if current direct tests cannot prove tap routing at the UI/open boundary.
9. Update `Test-Flight-Improv/test-gate-definitions.md` only if new test files or new simulator commands are added. Do not update final notification/group matrices in this session unless a new test file needs classification; session `04` owns final matrix closure.
10. Run focused direct tests, then named gates, then the required reliability simulator path commands. If simulator devices are unavailable, persist the attempted command/output and classify as `evidence-gated`.

### risks and edge cases

- Background isolate access to encrypted SQLite and secure key material may not be safely available from the current handler. This is the main stop condition.
- Suppressing all group-message fallback would regress accepted members on Android/iOS data-only paths; the implementation must require current local membership, not just `type == group_message`.
- A pending invite is actionable for invite review, but it is not current membership. Ordinary group-message fallback should not be shown for pending invite state; already-visible taps should redirect to Intros.
- Unknown local identity should fail closed for group-message fallback display, while preserving non-group notification behavior.
- Recent remote announcement gates must not be marked when a local fallback is suppressed or fails to display.
- Flow events must not include group names, message text, ciphertext, nonces, sender names, or canary values.
- Active group suppression and duplicate notification suppression for accepted members must not regress.

### exact tests and gates to run

Focused direct tests:

```bash
flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart
flutter test --no-pub test/features/push/application/background_message_handler_test.dart
flutter test --no-pub test/features/push/application/handle_foreground_remote_message_use_case_test.dart
flutter test --no-pub test/features/push/application/resolve_group_notification_route_target_use_case_test.dart
flutter test --no-pub test/features/push/application/prepare_notification_open_use_case_test.dart
flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart
flutter test --no-pub test/integration/notification_deeplink_integration_test.dart
flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart
```

Conditional focused tests:

```bash
flutter test --no-pub test/features/push/application/push_decrypt_preview_test.dart
flutter test --no-pub test/core/notifications/notification_route_target_test.dart
flutter test --no-pub test/features/push/application/show_notification_use_case_test.dart
```

Run the conditional tests if those files or route/preview/show-notification contracts are touched.

Required named gates:

```bash
./scripts/run_test_gates.sh groups
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
```

Conditional named gates:

```bash
./scripts/run_test_gates.sh runtime-telemetry
./scripts/run_test_gates.sh completeness-check
```

`runtime-telemetry` is required if push decrypt telemetry or telemetry-gated push events change. `completeness-check` is required if adding new test files, new simulator files, or editing gate definitions.

Reliability simulator closure gate:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_foreground_group_push_simulator_smoke.dart
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_notification_open_ui_smoke.dart
```

If tap proof is implemented in the shell APNs tap smoke instead of the Dart notification-open runner, replace the last command with:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only scripts/run_ios_notification_tap_ui_smoke.sh
```

The existing foreground simulator does not yet prove the unaccepted/missing receiver state, so session `03` must add or extend a scenario before the second command can count as closure evidence.

The notification-open simulator proof must include a background/terminated-style tap/open row for current member, pending invite redirect, and missing group/missing invite suppression. This is session-owned tap-routing evidence only; it is not the final mixed-recipient session `04` acceptance matrix.

### known-failure interpretation

- The full Go sweep failure `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree` is a documented session `02` residual and out of scope for session `03` unless new evidence ties it directly to notification suppression/routing.
- Session `03` should not touch Go or relay code. If it does, run focused Go/relay tests for the touched area and classify failures separately.
- The worktree is dirty with many unrelated changes. Only failures in touched push/routing files, direct notification tests, required named gates, and new session-owned simulator scenarios are in scope.
- If `groups` or `baseline` fails, rerun the focused failing file(s) and classify caused-by-session vs pre-existing/other-agent. Do not hide red gates, but do not reopen session `02` for its known Go residual.
- If simulator device resolution fails, the session cannot be accepted; mark it `evidence-gated` with the exact command output.

### done criteria

- RED-first regressions exist and pass for background fallback suppression, background handler no-show/no-mark behavior, foreground fallback suppression, current-member preservation, group invite preservation, and tap resolver missing/pending/current states.
- Production fallback display for ordinary `group_message` requires current local membership in both foreground and background paths.
- Pending invite state never becomes an ordinary group-message fallback notification, while already-visible stale taps still redirect to Intros.
- Current local members keep normal group-message notification behavior and duplicate/active-view suppression.
- Required direct tests, named gates, and path-addressable `$run-flutter-reliability-sims` commands pass, or simulator unavailability is recorded as `evidence-gated`.
- Any new test or simulator file is classified in `Test-Flight-Improv/test-gate-definitions.md` and `completeness-check` passes.
- No final session `04` matrix/closure updates are claimed.

### scope guard

Do not:

- Change sender recipient eligibility, Go native reliable send, relay fanout, or explicit recipient preservation.
- Add a broad notification framework, persistent notification inbox, or UI redesign.
- Blanket-disable group-message fallback notifications.
- Route unaccepted users into group conversations.
- Alter accepted-member message persistence, active conversation suppression, duplicate suppression, mute behavior, or notification copy beyond what suppression tests require.
- Close report 106, update final matrices, or claim mixed-recipient acceptance.

Overengineering signals:

- New database schema solely for suppression state.
- Rewriting app bootstrap/background initialization.
- Moving group invitation lifecycle logic into notification parsing.
- Adding product copy or admin status changes not required to prevent dead-end notifications.

### accepted differences / intentionally out of scope

- Session `03` may add receiver-state simulator evidence, but final mixed accepted/unaccepted multi-recipient acceptance remains session `04`.
- Provider-backed APNs/TestFlight proof remains complementary. Repo-owned direct, smoke, integration, and simulator evidence is sufficient for this session if it covers the session-owned receiver states.
- Pending invite redirects are preserved for stale/already-visible taps, but pending invite state is not treated as permission to show ordinary group-message fallback notifications.
- Missing group/missing invite can be an explicit telemetry-backed suppression rather than a new visible screen, as allowed by the source doc wording.

### dependency impact

- Session `04-acceptance-closure` depends on session `03` to provide receiver-side suppression and tap-routing evidence before final mixed-recipient acceptance.
- If background-safe local-state resolution proves impossible without broad bootstrap work, session `04` must not proceed to final closure; the pipeline should reopen with an evidence-gated prerequisite or a narrower background resolver plan.
- Session `02` should remain closed unless session `03` evidence shows an accepted-recipient fanout regression.

## reviewer findings

Reviewer verdict: sufficient with adjustments.

Findings:

- No structural blocker. The plan has a narrow session `03` scope, preserves sessions `01`/`02`, excludes final session `04` matrix closure, and includes RED-first tests plus direct/named/simulator gates.
- Adjustment applied: `runtime-telemetry` and `completeness-check` are conditional rather than unconditional gates.
- Adjustment applied: simulator closure now explicitly includes foreground suppression plus background/terminated notification open or tap behavior, without claiming final mixed-recipient acceptance.
- Residual risk for execution: background-safe encrypted DB/local-state access is the main feasibility risk, but the plan correctly treats inability to prove it as `evidence-gated` rather than allowing blanket suppression.

## arbiter decision

Arbiter verdict: proceed to execution.

Structural blockers:

- None.

Incremental details:

- Conditional gate wording and simulator background/tap wording were corrected during review.
- Exact event names for new suppression telemetry may be chosen during implementation, as long as they remain leak-safe and direct tests assert the contract.

Accepted differences:

- Session `03` adds receiver-side direct and simulator evidence only. Session `04` still owns final mixed-recipient acceptance and matrix closure.
- Missing group/missing invite can close as telemetry-backed suppression rather than a new user-visible screen.

## structural blockers remaining

None.

## incremental details intentionally deferred

- Exact internal enum names and flow-event names for suppression results.
- Exact simulator row name/number after the executor extends an existing runner. The path-addressable commands above are the stable closure commands.

## accepted differences intentionally left unchanged

- No sender fanout, Go reliable-send, or relay fanout work in this session.
- No final notification/group matrix update unless new test files or simulator commands need gate classification.
- No product copy or notification visual design change unless implementation evidence proves it is necessary to avoid a silent dead end.

## exact docs/files used as evidence

- `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-breakdown.md`
- `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`
- `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-02-recipient-eligibility-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md`
- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/features/push/application/push_decrypt_preview.dart`
- `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
- `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `lib/core/notifications/notification_route_target.dart`
- `lib/main.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/integration/group_notification_dedupe_integration_test.dart`
- `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart`
- `integration_test/foreground_group_push_simulator_bob_harness.dart`
- `scripts/run_test_gates.sh`
- `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/SKILL.md`
- `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh`

## why the plan is safe or unsafe to implement now

Safe to implement now because the scope is confined to receiver-side notification fallback and tap routing, current code/test seams are identified, RED-first tests are specified before production changes, accepted-member preservation is explicit, and simulator-gated closure is required for notification behavior.

The only material risk is background isolate access to local encrypted DB state. The plan handles that risk with a clear stop rule: prove a narrow background-safe resolver or mark the session `evidence-gated`; do not ship a blanket group-message fallback suppression.

## required downstream isolation

Execution should run in a fresh `$implementation-execution-qa-orchestrator` child with `model: gpt-5.5`, `reasoning_effort: xhigh`, approval policy `never`, and no escalated permissions. Closure should then run in a fresh `$implementation-closure-audit-orchestrator` child with the same model settings.

If no downstream agent is available and a local fallback is used, the controller must record the fallback in this plan and keep the same RED-first, QA, gate, and simulator closure contract.
