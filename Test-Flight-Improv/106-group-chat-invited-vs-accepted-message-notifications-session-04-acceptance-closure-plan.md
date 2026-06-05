# 106 Group Chat Invited vs Accepted Message Notifications - Session 04 Acceptance Closure Plan

Status: accepted

Session: `04-acceptance-closure`

## Planning Progress

- 2026-06-04 21:54:00 CEST - Role: Arbiter completed. Files inspected since last update: final local plan sections, coverage ledger, reviewer findings, exact gates, simulator command selectors, and matrix/doc closure scope. Decision/blocker: no structural blocker remains; the plan is `execution-ready` as an `acceptance-only` session with a required simulator proof and explicit evidence-gated stop rule if devices or relay setup are unavailable. Next action: send this plan to `$implementation-execution-qa-orchestrator`.
- 2026-06-04 21:53:40 CEST - Role: Reviewer completed. Files inspected since last update: local draft plan, source acceptance evidence list, breakdown session 04 contract, test-gate definitions, existing `INV-106` host smoke, and multi-party scenario selector support. Decision/blocker: sufficient with adjustments; required adjustments were to make the multi-layer acceptance ledger explicit, require `$run-flutter-reliability-sims` for `private_invite_terminal_states`, and keep production code out of scope unless a real acceptance blocker is found. Next action: Arbiter classification.
- 2026-06-04 21:53:10 CEST - Role: Planner completed by local fallback. Files inspected since last update: session 01/02/03 closure evidence, `test/features/groups/integration/group_messaging_smoke_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `scripts/run_reliability_simulations.sh`, `Test-Flight-Improv/test-gate-definitions.md`, and stable matrix/closure docs. Decision/blocker: no dependency blocker; existing evidence is close but final closure needs one combined acceptance ledger tying accepted-only fanout, relay/push eligibility, notification suppression, tap routing, simulator proof, and matrix/source closure updates together. Next action: Reviewer.
- 2026-06-04 21:52:44 CEST - Role: planning child no-progress fallback. Files inspected since last update: active child process state and session 04 plan file. Decision/blocker: the fresh `$implementation-plan-orchestrator` child created `planning-intake` and started the Planner role, then no-progressed without writing draft sections or a final verdict; the controller terminated it and continued locally under the planning skill fallback. Next action: complete Planner, Reviewer, and Arbiter roles locally.
- 2026-06-04 21:49:13 CEST - Role: Evidence Collector completed / Planner started. Files inspected since last update: source doc, breakdown, session 01/02/03 plans and closure evidence, `Test-Flight-Improv/test-gate-definitions.md`, existing `INV-106` host smoke, session 03 foreground and notification-open simulator files, `integration_test/scripts/run_group_invite_status_matrix_sim.dart`, `integration_test/group_invite_status_matrix_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/group_multi_party_device_real_harness.dart`, stable notification/group/closure docs, and `run_with_devices.sh group --list` output observed by the planning child. Decision/blocker: no dependency blocker; session 04 remains acceptance-only, but closure must include a required reliability simulator proof and matrix/source closure updates. Next action: write the draft plan and coverage ledger.

## final verdict

Final verdict: `execution-ready`.

This is an `acceptance-only` plan. It may add or extend test/simulator harness evidence and docs, but it should not change production group messaging, invite lifecycle, relay fanout, or notification-routing code unless the acceptance run exposes a real regression that invalidates sessions `01`, `02`, or `03`.

## final plan

### real scope

Session `04-acceptance-closure` owns final proof and final documentation for Report 106.

In scope:

- Prove the full mixed accepted/unaccepted group-message notification journey across the already-closed session slices:
  - invite lifecycle/freshness context from session `01`;
  - accepted-recipient sender/native/relay fanout from session `02`;
  - foreground/background fallback suppression and tap routing from session `03`.
- Add or extend the smallest acceptance evidence in existing test/simulator harnesses when existing evidence is too isolated.
- Update stable matrix and closure docs with final Report 106 evidence and the final program verdict.
- Run final direct tests, named gates, Go gates, completeness classification, and required reliability simulator proof.

Out of scope:

- New product UX copy, new invite states, new notification visual design, Orbit redesign, or broad group creation redesign.
- Reworking production recipient filtering or notification suppression unless acceptance evidence reveals a real regression.
- Provider-backed APNs/TestFlight proof as a hard requirement; repo-owned direct, Go, host, and simulator evidence is the closure contract.
- Reopening the known out-of-scope Go full-sweep failure `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree`.

### closure bar

Session `04` is good enough only when all of these are true:

- A mixed group acceptance proof shows a creator with at least one accepted member and one non-accepted/terminal/missing invitee sending an ordinary group message.
- Accepted members receive the normal message experience and retain current-member notification/tap behavior.
- The non-accepted invitee is excluded from ordinary message recipient IDs, native reliable-send recipient IDs, relay custody/push fanout, and local message persistence.
- Foreground/background group-message fallback display is denied for non-current local membership while preserving accepted-member fallback behavior.
- Notification tap handling is documented and covered for current member, pending invite, and missing group/missing invite states.
- The negative matrix covers pending, expired, declined, revoked/invalid, and missing-invite recipient states as not producing a dead-end ordinary group-message notification.
- Stable docs record the final evidence and no longer read as an open Report 106 bug.
- The breakdown records a final program verdict allowed by its policy: `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`.

If the required simulator devices, relay setup, or multi-party scenario cannot run, classify the session as `evidence-gated`/`still_open` with exact attempted commands. Do not claim full closure on host tests alone.

### source of truth

Authoritative docs and gates:

- `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-breakdown.md`
- `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/91-group-invitation-status-visibility.md`

Current code/tests beat stale prose. `test-gate-definitions.md` is authoritative for named gates and test classification. The session 01/02/03 plans are evidence inputs, not permission to skip the final combined acceptance proof.

### session classification

`acceptance-only`.

The expected edits are acceptance tests/simulator criteria and docs. Production code changes are allowed only if the acceptance evidence exposes a real defect that belongs to an already-closed session; in that case the executor must document the reopened defect and keep the fix narrowly scoped.

### exact problem statement

Report 106 is not fully closed until the repo proves the reported user journey as a whole: a rostered but not accepted invitee must not be treated as an ordinary group-message recipient, must not receive a group-message push/local fallback that opens to no messages, and must remain distinguishable from an accepted/current member while accepted members keep normal message and notification behavior.

Sessions `01`, `02`, and `03` close the component seams, but session `04` must combine that evidence into one acceptance ledger and update stable matrices/docs.

### files and repos to inspect next

Primary acceptance harnesses and criteria:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart`
- `integration_test/foreground_group_push_simulator_bob_harness.dart`
- `integration_test/scripts/run_notification_open_ui_smoke.dart`
- `integration_test/notification_open_ui_smoke_test.dart`

Docs to update:

- `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`
- `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-breakdown.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/91-group-invitation-status-visibility.md` only if creator/status evidence is changed or newly referenced
- `Test-Flight-Improv/test-gate-definitions.md` if new test files are added or existing optional simulator descriptions need Report 106 classification text

Go gates and relay evidence:

- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/group_inbox_test.go`
- `go-relay-server/inbox.go`
- `go-relay-server/inbox_test.go`

### existing tests covering this area

- `test/features/groups/integration/group_messaging_smoke_test.dart` already has `INV-106 mixed accepted and unaccepted invitees target only accepted ordinary-message recipients`, proving accepted-only host recipient IDs and excluding the unaccepted invitee from message persistence.
- Session `02` focused Flutter/Go evidence covers Dart replay, `group:inboxStore`, native `group:sendReliable`, and Go custody preserving explicit accepted recipients.
- Session `03` direct push tests cover group-message fallback display eligibility, background handler suppression, foreground visible-FCM fallback preservation, group invite routing, route resolution, deeplink, and dedupe behavior.
- Session `03` simulator evidence covers foreground non-current/missing fallback suppression and notification-open current/pending/missing routes.
- `integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_invite_terminal_states` already models an accepted Alice/Bob path and non-joined Charlie terminal invite path; extend it rather than introducing a broad new simulator.
- `integration_test/scripts/run_group_invite_status_matrix_sim.dart` covers creator-side invite status display but does not claim relay/testpeer lifecycle proof.

What is still missing before session `04`:

- One explicit Report 106 final acceptance ledger that ties the host recipient/fanout proof, simulator mixed-recipient proof, notification suppression/tap proof, and doc matrix closure together.
- Matrix/closure docs still need durable rows that say Report 106 is closed or accepted with explicit residuals, not merely planned.

### regression/tests to add first

Add or extend acceptance proof before claiming docs closed:

- Extend the existing `private_invite_terminal_states` multi-party simulator verdict/criteria with Report 106 fields, preferably without adding a new scenario:
  - `report106Proof: true`;
  - accepted recipient role receives/persists the post-invite ordinary group message;
  - non-accepted/terminal invitee role does not persist that ordinary group message;
  - sender verdict exposes recipient IDs used for ordinary send/reliable-send where available and excludes the non-accepted invitee;
  - non-accepted/terminal invitee verdict exposes no local fallback/dead-end notification evidence if the harness has notification snapshots available;
  - orchestrator criteria reject sender-only proof, missing accepted-recipient proof, missing non-accepted negative proof, or missing Report 106 fields.
- If the existing simulator cannot expose notification fields narrowly, do not fake them; record an accepted difference that session `03` notification-open/foreground simulators provide the OS-route proof and make the final coverage ledger link that evidence explicitly.
- Extend the existing `INV-106` host smoke only if it lacks a final assertion needed by the coverage ledger, such as relay-recipient/push-fanout metadata or creator invite-status distinction.
- Do not add a new test file unless the existing harnesses cannot express the proof. If a new file is added, update `Test-Flight-Improv/test-gate-definitions.md` and run `completeness-check`.

### step-by-step implementation plan

1. Capture pre-edit status and scoped diffs for session 04 files. Do not revert unrelated dirty changes.
2. Inspect the existing `INV-106` host smoke, session 03 simulator rows, `private_invite_terminal_states` role verdict fields, and `group_multi_party_device_criteria.dart` requirements.
3. Add the minimal Report 106 acceptance fields/criteria to existing simulator harnesses. Prefer `private_invite_terminal_states` because it already has Alice/Bob accepted and Charlie non-joined/terminal invite semantics.
4. Add or tighten host direct assertions only if required by the coverage ledger.
5. Run the narrow direct tests for any edited host files and simulator host compile/smoke checks.
6. Run the exact required direct, named, Go, and simulator gates below.
7. Update stable matrix docs:
   - notification journey rows for invited-but-unaccepted, pending invite, terminal invite, missing invite, accepted current member, foreground fallback, background fallback, and tap routing;
   - group chat matrix rows for invite accept/decline/expiry and group notification eligibility;
   - group closure reference with the final mixed-recipient and relay/fanout evidence;
   - invite status doc only if session 04 adds new creator/status evidence.
8. Update the source doc's session closure progress and the breakdown ledger/final program verdict.
9. Run closure audit. If any required simulator/gate is blocked, record the exact blocker and leave final program verdict `still_open` or `accepted_with_explicit_follow_up` only if allowed by the breakdown policy.

### risks and edge cases

- Multi-simulator reliability proof needs enough booted iPhone simulators and relay addresses. Missing devices are an evidence blocker, not a reason to close on host tests.
- The multi-party harness is large; keep edits local to existing scenario verdict fields and criteria.
- Do not weaken criteria by accepting sender-only proof. Accepted-recipient positive proof and non-accepted negative proof must both be present.
- Do not turn pending invite routing into ordinary group-message routing. Pending invite state remains Intros-only until acceptance.
- Do not broaden final docs into APNs/provider proof unless that evidence was actually run.
- Preserve the session `02` known Go full-sweep follow-up classification.

### exact tests and gates to run

Formatting and focused host checks:

```bash
dart format test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart
flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/background_message_handler_test.dart test/features/push/application/handle_foreground_remote_message_use_case_test.dart test/features/push/application/resolve_group_notification_route_target_use_case_test.dart test/features/push/application/prepare_notification_open_use_case_test.dart test/features/push/application/chat_and_group_push_open_flow_test.dart test/integration/notification_deeplink_integration_test.dart test/integration/group_notification_dedupe_integration_test.dart
flutter test --no-pub -d macos integration_test/notification_open_ui_smoke_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios
```

Go/relay targeted gates:

```bash
cd go-mknoon && go test ./bridge -run TestGroupSendReliable
cd go-mknoon && go test ./node -run 'TestSendGroupMessageReliable|TestGroupInboxStore'
cd go-relay-server && go test ./...
```

Named gates:

```bash
./scripts/run_test_gates.sh groups
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh runtime-telemetry
./scripts/run_test_gates.sh completeness-check
```

Required reliability simulator gates:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 'integration_test/scripts/run_group_multi_party_device_real.dart:private_invite_terminal_states'
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_foreground_group_push_simulator_smoke.dart
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_notification_open_ui_smoke.dart
```

If device resolution fails, record the resolver output and classify the session as evidence-gated/still_open rather than accepted.

### known-failure interpretation

- `cd go-mknoon && go test ./...` is not required for session `04`; if run opportunistically and it still fails on `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree`, preserve the session `02` classification as an out-of-scope native topic join/leave/update lifecycle follow-up.
- A simulator device-resolution failure is an environment/evidence blocker for session `04`, not a product pass.
- Do not hide any new failure in focused direct, named, Go targeted, or required simulator gates. Fix it if it belongs to session `04`; otherwise record the exact out-of-scope reason.

### done criteria

Coverage ledger required before closure:

| Source requirement | Required session 04 proof |
|---|---|
| Mixed accepted/unaccepted journey | `INV-106` host smoke plus `private_invite_terminal_states` simulator Report 106 fields show accepted member positive proof and non-accepted invitee negative proof. |
| Client-node-relay boundary | Host/Go evidence shows explicit accepted `recipientPeerIds`, native reliable send preserves them, relay `group_store` push fanout does not include the non-accepted invitee. |
| Foreground/background notification suppression | Session 03 direct tests and required foreground simulator are rerun; docs cite suppression for non-current/missing routes and accepted-member preservation. |
| Notification tap routing | Notification-open direct/UI simulator covers current member, pending invite Intros redirect, and missing-group suppression. |
| Pending/expired/declined/revoked/invalid/missing negative matrix | Matrix docs map each state to accepted-recipient exclusion and/or receiver-side suppression evidence. |
| Creator/admin invited-vs-accepted clarity | Existing Group Info/invite-status evidence remains linked; update `91` only if new evidence changes that doc. |
| Final stable docs | Source doc, notification matrix, group matrix, group closure reference, and breakdown final verdict are updated and reviewed. |

Session `04` can close only after:

- the final coverage ledger is present in docs;
- all required direct/named/Go/simulator gates either pass or are recorded as exact blockers;
- a fresh `$implementation-execution-qa-orchestrator` execution/QA verdict is accepted or blocked with evidence;
- a fresh `$implementation-closure-audit-orchestrator` closure record updates the breakdown final verdict.

### scope guard

Do not implement new notification display behavior, invite lifecycle behavior, recipient eligibility behavior, or relay protocol behavior unless an acceptance test proves a regression. Keep all routine session `04` edits to existing tests, simulator criteria, gate classification text, and closure docs.

### downstream model contract

Every downstream agent spawned from this plan must explicitly request:

- `model: gpt-5.5`
- `reasoning_effort: xhigh`

## Execution Progress

- 2026-06-04 21:57:10 CEST - Phase: Executor contract extracted. Files inspected or touched: this plan, `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-breakdown.md`, `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`, `Test-Flight-Improv/test-gate-definitions.md`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `git status --short`. Command currently running: none. Decision/blocker: session `04-acceptance-closure` only; acceptance evidence and docs are in scope, production code is out of scope unless acceptance evidence proves a real regression; required simulator proof must run or be classified as evidence-gated/still_open. Next action: inspect existing host smoke, session `03` simulator rows, and `private_invite_terminal_states` verdict/criteria before edits.
- 2026-06-04 21:56:15 CEST - Phase: contract extracted / Executor handoff pending. Files inspected or touched: this plan, `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-breakdown.md`, `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`, and `git status --short`. Command currently running: none. Decision/blocker: no structural blocker; execute session `04-acceptance-closure` only as acceptance-only evidence/doc closure, do not reopen sessions `01`, `02`, or `03`, and keep production code out of scope unless acceptance evidence proves a real regression. Next action: spawn the Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-06-04 21:56:47 CEST - Phase: Executor spawned/running. Files inspected or touched: this plan. Command currently running: spawned Executor `Ptolemy` (`019e9435-9960-71b1-bb93-fce7da7fc730`) assigned acceptance evidence, scoped test/simulator/doc updates, direct tests, named gates, Go gates, and required reliability simulator commands. Decision/blocker: pending Executor result. Next action: bounded wait, then inspect plan/diff/test evidence before QA handoff.
- 2026-06-04 21:59:35 CEST - Phase: spawned Executor no-progressed; local Executor fallback started. Files inspected or touched: this plan, active process state, and scoped diff for session 04 candidate files. Command currently running: none; the execution controller and spawned Executor produced no new test/simulator/doc evidence after the handoff and were terminated. Decision/blocker: no session blocker; continue locally under the execution skill fallback, preserving session 04 acceptance-only scope. Next action: implement minimal Report 106 acceptance evidence in existing harness/criteria/docs, then run required tests and local QA.
- 2026-06-04 22:01:57 CEST - Phase: Report 106 simulator acceptance fields implemented. Files touched: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and this plan. Command finished: `dart format integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart` passed. Decision/blocker: no production code touched; `private_invite_terminal_states` now emits and validates `report106MixedInviteNotificationProof` for Alice sender accepted-only recipients, Bob accepted-member receipt, and Charlie terminal invitee no-message/no-local-fallback proof. Next action: run focused host compile/list and direct tests.
- 2026-06-04 22:04:25 CEST - Phase: first focused host checks passed. Files touched: same session 04 harness/criteria files. Commands finished: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios` passed and listed `private_invite_terminal_states`; `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart` passed (`+86`) including the existing `INV-106` accepted-only recipient smoke. Decision/blocker: no host acceptance blocker. Next action: run focused push/route/deeplink/dedupe direct suite.
- 2026-06-04 22:06:21 CEST - Phase: focused push/route/deeplink direct suite passed. Files touched: no additional files beyond the session 04 harness/criteria and this plan. Command finished: `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/background_message_handler_test.dart test/features/push/application/handle_foreground_remote_message_use_case_test.dart test/features/push/application/resolve_group_notification_route_target_use_case_test.dart test/features/push/application/prepare_notification_open_use_case_test.dart test/features/push/application/chat_and_group_push_open_flow_test.dart test/integration/notification_deeplink_integration_test.dart test/integration/group_notification_dedupe_integration_test.dart` passed (`+97`). Decision/blocker: foreground/background display eligibility, stale removed-group suppression, pending-invite routing, notification open preparation, and local dedupe remain green. Next action: run macOS notification-open UI smoke.
- 2026-06-04 22:07:24 CEST - Phase: macOS notification-open UI smoke passed. Files touched: no additional files. Command finished: `flutter test --no-pub -d macos integration_test/notification_open_ui_smoke_test.dart` passed (`+11`); build emitted existing macOS deployment/link warnings and `Failed to foreground app; open returned 1`, but the smoke completed successfully. Decision/blocker: UI tap routing proof is green for group current-member open, pending invite Intros redirect, and missing-group suppression. Next action: run targeted Go/relay gates.
- 2026-06-04 22:07:58 CEST - Phase: targeted Go/relay gates passed. Files touched: no additional files. Commands finished: `cd go-mknoon && go test ./bridge -run TestGroupSendReliable` passed, `cd go-mknoon && go test ./node -run 'TestSendGroupMessageReliable|TestGroupInboxStore'` passed, and `cd go-relay-server && go test ./...` passed; all reported cached `ok`. Decision/blocker: native/relay targeted boundary evidence remains green. Next action: run named gates (`groups`, macOS `baseline`, `runtime-telemetry`, `completeness-check`).
- 2026-06-04 22:09:26 CEST - Phase: named `groups` gate passed. Files touched: no additional files. Command finished: `./scripts/run_test_gates.sh groups` passed (`+319`). Decision/blocker: broad group host regression gate remains green after session 04 harness/criteria additions. Next action: run macOS `baseline` gate.
- 2026-06-04 22:11:34 CEST - Phase: named macOS `baseline` gate passed. Files touched: no additional files. Command finished: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed; host baseline reported `+98`, loading-states macOS smoke reported `+7`, and posts macOS smoke reported `+1`. Existing macOS deployment/link warnings and `Failed to foreground app; open returned 1` appeared, but all baseline tests passed. Decision/blocker: named baseline evidence remains green. Next action: run `runtime-telemetry`.
- 2026-06-04 22:12:18 CEST - Phase: named `runtime-telemetry` gate passed. Files touched: no additional files. Command finished: `./scripts/run_test_gates.sh runtime-telemetry` passed (`+4`). Decision/blocker: push-preview telemetry threshold coverage remains green. Next action: run `completeness-check`.
- 2026-06-04 22:12:29 CEST - Phase: named `completeness-check` gate passed. Files touched: no additional files. Command finished: `./scripts/run_test_gates.sh completeness-check` passed with `768/768 test files classified`. Decision/blocker: test-map completeness remains green. Next action: run required reliability simulator commands (`group --list`, `private_invite_terminal_states`, foreground group push simulator, notification-open UI smoke).
- 2026-06-04 22:12:50 CEST - Phase: reliability simulator discovery/list passed. Files touched: no additional files. Command finished: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` passed; resolved one-device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, two-device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,38FECA55-03C1-4907-BD9D-8E64BF8E3469`, and four-device `279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76,5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`; dry-run plan included `private_invite_terminal_states`. Decision/blocker: no simulator device-resolution blocker. Next action: run `private_invite_terminal_states` reliability simulator.
- 2026-06-04 22:19:55 CEST - Phase: `private_invite_terminal_states` reliability simulator passed. Files touched: no additional files. Command finished: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 'integration_test/scripts/run_group_multi_party_device_real.dart:private_invite_terminal_states'` passed. Evidence: four-device run id `1780604017626`; orchestrator reported `private_invite_terminal_states proof passed: private_invite_terminal_states verdicts valid for alice, bob, charlie` with verdict files in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_invite_terminal_states_3tBT7b`; Alice/Bob/Charlie `flutter drive` runs all passed. Decision/blocker: main mixed accepted/unaccepted acceptance proof is green. Next action: run foreground group push simulator.
- 2026-06-04 22:25:08 CEST - Phase: foreground group push simulator reliability gate passed. Files touched: no additional files. Command finished: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_foreground_group_push_simulator_smoke.dart` passed. Evidence: two-device run id `1780604420765`; S2 passed with `notificationCount: 1`; S3 passed with `result: notificationNeeded`, `fallbackShown: false`, `genericNotificationCount: 0`, and foreground suppression reason `group_missing`; Alice/Bob `flutter drive` runs passed and wrapper reported `Foreground group push simulator smoke PASSED`. Decision/blocker: foreground fallback suppression rerun is green. Next action: run notification-open UI smoke through reliability wrapper.
- 2026-06-04 22:28:39 CEST - Phase: notification-open UI smoke reliability gate passed. Files touched: no additional files. Command finished: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_notification_open_ui_smoke.dart` passed. Evidence: command `#119` ran on `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Flutter integration output ended `+12: All tests passed!`, and the wrapper reported `Notification-open UI smoke passed on all selected devices` plus `PASS: reliability simulations completed for scope: group`. Decision/blocker: required session 04 simulator gates are green. Next action: local QA review, then closure audit.
- 2026-06-04 22:30:00 CEST - Phase: local Executor/QA fallback verdict. Files touched: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and this plan. Commands finished: all required formatting, focused direct tests, targeted Go/relay gates, named gates, and required reliability simulator gates above passed. Decision/blocker: accepted execution verdict for session `04-acceptance-closure`; no production behavior change was needed and no session 04 blocker remains. Next action: spawn fresh closure audit agent, then update stable docs, session ledger, and final program verdict.

## Closure Progress

- 2026-06-04 22:45:46 CEST - Phase: closure and final acceptance completed. Files inspected or updated: this plan, `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications-session-breakdown.md`, `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`, `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/test-gate-definitions.md`, `integration_test/group_multi_party_device_real_harness.dart`, and `integration_test/scripts/group_multi_party_device_criteria.dart`. Decision/blocker: session `04-acceptance-closure` is accepted and the breakdown records final program verdict `closed`; no session 04 blocker remains. Next action: none for Report 106 unless the recorded gates or evidence regress.
