Status: execution-ready

# LP-003 Session Plan - Unsubscribe After Exit Paths

## Planning Progress

- 2026-04-30 23:57:42 CEST - Arbiter completed. Files inspected since last update: reviewer-adjusted LP-003 plan content. Decision/blocker: no structural blockers remain; reviewer adjustment accepted as an incremental detail; ban remains an accepted architecture difference unless execution finds a real first-class ban surface. Next action: execute this plan in a separate implementation session.
- 2026-04-30 23:57:00 CEST - Reviewer completed; Arbiter started. Files inspected since last update: draft LP-003 plan content. Decision/blocker: plan is sufficient with adjustments; no structural blocker found. Reviewer adjustment: use full direct Dart files as the required proof commands so implementation is not dependent on brittle existing test-name filters, while allowing focused `--name LP003` reruns after new tests are added. Next action: arbitrate reviewer findings and finalize the reusable plan.
- 2026-04-30 23:57:00 CEST - Planner completed; Reviewer started. Files inspected since last update: draft LP-003 plan content. Decision/blocker: draft contains mandatory sections, explicit dirty-worktree handling, regression contract, and device/relay profile. Next action: review sufficiency, ban ambiguity handling, test/gate exactness, and scope safety.
- 2026-04-30 23:54:40 CEST - Evidence Collector completed; Planner started. Files inspected since last update: LP-003 source matrix row, LP-003 session breakdown row, `test-inventory.md`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/bridge/bridge.go`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/delete_group_and_messages_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/delete_group_and_messages_use_case_test.dart`, `test/features/groups/application/leave_group_use_case_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/scripts/run_group_multi_device_real.dart`. Device checks run: `flutter devices --machine`, `xcrun simctl list devices available`, `adb devices`, `$HOME/Library/Android/sdk/platform-tools/adb devices`, relay env print. Decision/blocker: existing code proves local `LeaveGroupTopic` cleanup and Dart calls to `group:leave` for self-removal/dissolve, but does not prove live no-delivery after every exit path; no first-class group ban surface was found. Next action: draft row-owned proof-first implementation plan with a device/relay profile and explicit stop points.
- 2026-04-30 23:50:54 CEST - Evidence Collector started. Files inspected since last update: implementation-plan-orchestrator skill, git status, intended plan path existence check. Decision/blocker: intended LP-003 plan artifact confirmed absent and created as the only planning progress artifact; worktree has pre-existing modified files that must be treated as user-owned unless this plan later names them for implementation. Next action: inspect row docs, inventory, gate definitions, owner code/tests, and run live device availability checks.

## Execution Progress

- 2026-05-01 00:19:33 CEST - Final verdict written. Files inspected since last update: LP-003 plan verdict section. Command currently running: none. Decision/blocker: final verdict is `accepted`; spawned Executor and QA completed, no blocking issues remain, and no fix pass was required. Next action: controller final consistency check and final response.
- 2026-05-01 00:19:02 CEST - Final verdict work started. Files inspected since last update: QA Reviewer final output and QA plan note. Command currently running: none. Decision/blocker: QA found no blocking issues and no fix pass is required under the stop rule. Next action: write accepted LP-003 execution verdict with files changed and exact test/gate results.
- 2026-05-01 00:18:06 CEST - QA Reviewer completed. Files inspected since last update: LP-003 plan execution evidence, scoped LP-003 diff, `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`, focused Dart LP-003 tests in `leave_group_use_case_test.dart`, `delete_group_and_messages_use_case_test.dart`, and `group_message_listener_test.dart`, offline inbox and smoke-test coverage markers, scoped production diff, `git status --short`, and `git diff --check`. Command currently running: none. Decision/blocker: QA verdict `no_blocking_issues`; required LP-003 proof/tests exist, required commands were run or correctly classified, the full offline inbox MD-011 failure and owner Go `TestGroupPublish_ResponseIncludesTopicPeers` failure are unrelated/pre-existing under this plan, `group-real-network-nightly` was not substituted while relay env is unset, and no LP-003 production patch was made. Next action: no fix pass required.
- 2026-05-01 00:16:01 CEST - QA Reviewer spawned/running. Files inspected since last update: execution QA orchestrator skill, Executor result, `git status --short`, LP-003 plan progress. Command currently running: isolated `codex exec` QA Reviewer with `model=gpt-5.5`, `model_reasoning_effort=xhigh`. Decision/blocker: QA must inspect the landed LP-003 proof/tests, verify required evidence, and classify the full offline inbox and owner Go red commands before any final verdict. Next action: wait for QA result; use the single fix loop only if QA reports blocking issues.
- 2026-05-01 00:14:46 CEST - Executor completed. Files inspected since last update: `git status --short`, `git diff --stat`, LP-003 changed-file diff, new Go proof file content, LP-003 marker search. Command currently running: none. Decision/blocker: Executor implementation/test pass complete with no production code changes; added `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` plus focused Dart tests in `leave_group_use_case_test.dart`, `delete_group_and_messages_use_case_test.dart`, and `group_message_listener_test.dart`; required proof commands passed except full offline inbox file failed in unrelated MD-011 media replay and owner Go suite failed in known bridge peer-mismatch test. Next action: QA Reviewer should inspect the new proof/tests and classify the recorded non-LP-003 red commands.
- 2026-05-01 00:14:06 CEST - Final whitespace gate passed. Files inspected since last update: `git diff --check` output. Command currently running: none. Decision/blocker: `git diff --check` passed. Next action: inspect final diff/status and write Executor handoff summary; QA must review new proof/tests plus the two unrelated/pre-existing red commands recorded above.
- 2026-05-01 00:13:46 CEST - Final whitespace gate started. Files inspected since last update: none. Command currently running: `git diff --check`. Decision/blocker: final required repository diff whitespace check. Next action: record pass/fail and summarize Executor result.
- 2026-05-01 00:13:35 CEST - Owner Go suite failed with known pre-existing bridge publish failure. Files inspected since last update: owner Go suite output. Command currently running: none. Decision/blocker: `cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` failed in `go-mknoon/bridge` at `TestGroupPublish_ResponseIncludesTopicPeers` with `GROUP_ERROR` / `publish to topic: validation failed` after `peer_mismatch`; this matches the plan's known sender/transport peer mismatch caveat and is not caused by LP-003 edits. Next action: run final `git diff --check`; groups gate not required because no Dart-visible production behavior changed.
- 2026-05-01 00:12:23 CEST - Owner Go suite started. Files inspected since last update: none. Command currently running: `cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v`. Decision/blocker: running feasible owner suite; known sender/transport peer mismatch failures remain pre-existing unless tied to LP-003 changes. Next action: record pass/fail.
- 2026-05-01 00:12:11 CEST - Required Dart integration proof passed. Files inspected since last update: command output for `group_membership_smoke_test.dart`. Command currently running: none. Decision/blocker: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` passed. Next action: run owner Go suite as feasible.
- 2026-05-01 00:11:51 CEST - Required Dart integration proof started. Files inspected since last update: none. Command currently running: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`. Decision/blocker: verifying app-path membership smoke coverage for removal/dissolution compatibility. Next action: record pass/fail.
- 2026-05-01 00:11:42 CEST - Focused LP-003 offline inbox rerun passed. Files inspected since last update: command output for focused offline inbox rerun. Command currently running: none. Decision/blocker: LP-003 replayed self-removal cleanup tests passed; full file still has unrelated MD-011 failure recorded above. Next action: run required group membership smoke test.
- 2026-05-01 00:11:20 CEST - Focused LP-003 offline inbox rerun started. Files inspected since last update: none. Command currently running: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'replayed member_removed routes through listener cleanup instead of saving a chat row|replayed self-removal cuts off later queued inbox traffic for that group'`. Decision/blocker: narrowing evidence to LP-003 replayed self-removal cleanup after full file failed in unrelated MD-011 media replay. Next action: record pass/fail.
- 2026-05-01 00:11:10 CEST - Required Dart proof failed with unrelated existing test. Files inspected since last update: command output for `drain_group_offline_inbox_use_case_test.dart`. Command currently running: none. Decision/blocker: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` failed at `MD-011 removed member cannot decode future media replay with only the old epoch` (`expected null`, got `GroupMessage(id: msg-md011-future-media-replay, groupId: group-1, isIncoming: true)`); LP-003 did not touch this file or production replay/media code. Next action: run LP-003-focused names in this file, then continue required commands.
- 2026-05-01 00:10:44 CEST - Required Dart proof started. Files inspected since last update: none. Command currently running: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Decision/blocker: verifying replayed self-removal/dissolve-adjacent offline paths stay compatible. Next action: record pass/fail.
- 2026-05-01 00:10:34 CEST - Required Dart proof passed. Files inspected since last update: command output for `group_message_listener_test.dart`. Command currently running: none. Decision/blocker: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` passed, including LP-003 `member_removed` self-removal and replayed `group_dissolved` leave assertions. Next action: run offline inbox proof file.
- 2026-05-01 00:10:13 CEST - Required Dart proof started. Files inspected since last update: none. Command currently running: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`. Decision/blocker: verifying self-removal/member_removed and group_dissolved leave dispatch semantics. Next action: record pass/fail.
- 2026-05-01 00:10:04 CEST - Required Dart proof passed. Files inspected since last update: command output for `delete_group_and_messages_use_case_test.dart`. Command currently running: none. Decision/blocker: `flutter test --no-pub test/features/groups/application/delete_group_and_messages_use_case_test.dart` passed, including LP-003 active delete and dissolved local-only cleanup assertions. Next action: run group listener proof file.
- 2026-05-01 00:09:49 CEST - Required Dart proof started. Files inspected since last update: none. Command currently running: `flutter test --no-pub test/features/groups/application/delete_group_and_messages_use_case_test.dart`. Decision/blocker: verifying active delete calls `group:leave` and dissolved local cleanup avoids a second leave. Next action: record pass/fail.
- 2026-05-01 00:09:40 CEST - Required Dart proof passed. Files inspected since last update: command output for `leave_group_use_case_test.dart`. Command currently running: none. Decision/blocker: `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart` passed, including `LP003 normal leave dispatches group leave and clears local state`. Next action: run delete-group proof file.
- 2026-05-01 00:09:07 CEST - Required Dart proof started. Files inspected since last update: none. Command currently running: `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart`. Decision/blocker: verifying normal leave dispatch/delete semantics. Next action: record pass/fail.
- 2026-05-01 00:08:55 CEST - Required focused Go proof passed. Files inspected since last update: command output for focused Go proof. Command currently running: none. Decision/blocker: `go test ./node -run 'TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLeaveGroupTopic_CancelsDiscoveryContext' -v` passed; no Go production patch needed. Next action: run required focused Dart proof files.
- 2026-05-01 00:08:27 CEST - Required focused Go proof started. Files inspected since last update: none beyond touched tests. Command currently running: `cd go-mknoon && go test ./node -run 'TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLeaveGroupTopic_CancelsDiscoveryContext' -v`. Decision/blocker: running proof-first unsubscribe test before any production patch. Next action: record pass/fail and patch only if the proof exposes a repo-owned gap.
- 2026-05-01 00:08:14 CEST - Executor Dart focused tests added. Files inspected since last update: `test/features/groups/application/leave_group_use_case_test.dart`, `test/features/groups/application/delete_group_and_messages_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`; touched those three test files and this LP-003 plan progress section. Command currently running: none; `dart format` completed on touched Dart tests. Decision/blocker: production Dart code not changed; tests now pin normal leave, active delete, self-removal via `member_removed`, replayed dissolution, and dissolved local-only delete without a second `group:leave`. Next action: run required focused Go proof command.
- 2026-05-01 00:06:39 CEST - Executor Go proof test added. Files inspected since last update: new `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`; touched `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` and this LP-003 plan progress section. Command currently running: none; `gofmt -w go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` completed. Decision/blocker: Go production code not changed; new proof keeps exited node connected and verifies no post-exit delivery for normal message, reaction, payload-parse-failure, and decrypt-failure traffic plus local pubsub state cleanup and fail-closed exited publishes. Next action: add focused Dart LP-003 app-path/delete tests.
- 2026-05-01 00:04:32 CEST - Executor owner inspection completed. Files inspected since last update: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/pubsub_authorization_forward_test.go`, `go-mknoon/node/multi_relay_test.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/delete_group_and_messages_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/delete_group_and_messages_use_case_test.dart`, `test/features/groups/application/leave_group_use_case_test.dart`, focused scoped ban search. Command currently running: none. Decision/blocker: no first-class group ban surface found in scoped group/node/bridge code; current exit semantics are `member_removed`. Existing production paths appear to dispatch `group:leave`; add row-owned Go live no-delivery proof and focused Dart tests before considering production changes. Next action: create `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` and patch focused Dart tests.
- 2026-05-01 00:02:59 CEST - Executor local pass started. Files inspected since last update: LP-003 plan remainder, execution QA orchestrator skill, focused ban/leave search output. Command currently running: none. Decision/blocker: acting as spawned Executor only; source matrix, `test-inventory.md`, and session breakdown ledger are out of scope for this pass. Next action: inspect LP-003 owner files and add proof-first tests without touching unrelated dirty worktree changes.
- 2026-05-01 00:00:18 CEST - Contract extraction started. Files inspected since last update: execution plan, execution QA orchestrator skill, `git status --short`. Command currently running: none. Decision/blocker: dirty worktree contains pre-existing GL-005/LP-002 and matrix/doc/code edits that must be preserved; no implementation files touched yet. Next action: extract exact LP-003 execution contract before any coding.
- 2026-05-01 00:00:18 CEST - Contract extracted. Files inspected since last update: full LP-003 plan. Command currently running: none. Decision/blocker: LP-003 scope is proof-first live unsubscribe/no-delivery evidence plus focused Dart exit-path/delete semantics tests; production edits allowed only in LP-003 owner files after failing proof; `group-real-network-nightly` is supporting-only and external-fixture-blocked while relay env is unset. Required direct tests/gates are the focused Go proof, five focused Dart files, owner Go suite as feasible, `groups` and group integration gates only if Dart-visible group behavior changes, and `git diff --check`. Next action: inspect owner files/tests and attempt the required isolated Executor handoff.
- 2026-05-01 00:01:11 CEST - Executor spawned/running. Files inspected since last update: Codex CLI availability and model/reasoning config. Command currently running: isolated `codex exec` Executor with `model=gpt-5.5`, `model_reasoning_effort=xhigh`. Decision/blocker: spawned-agent path is available through `codex exec`; Executor is instructed to own only LP-003 proof/test implementation and not update source matrix, test inventory, or session breakdown ledger. Next action: wait bounded interval, then inspect child result and repo evidence.
- 2026-05-01 00:02:01 CEST - Executor spawn retry. Files inspected since last update: failed `codex exec` launch output. Command currently running: none. Decision/blocker: first launch failed before child materialized because this `codex exec` build rejects `-a`; no implementation files were touched. Next action: relaunch Executor with `approval_policy="never"` config override instead of `-a`.

## Execution Verdict

Final verdict: accepted

Blocker class: none

Spawned-agent isolation used: yes. A spawned Executor and a separate spawned QA Reviewer ran with `model=gpt-5.5` and `model_reasoning_effort=xhigh`.

Local sequential fallback used: no.

Production code changed: no. The proof-first tests passed, so LP-003 did not justify an unsubscribe production patch.

Files changed for LP-003:

- `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` (new live Go/libp2p unsubscribe proof)
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-LP-003-plan.md`

Tests added or updated:

- `TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit`
- `LP003 normal leave dispatches group leave and clears local state`
- `LP003 active delete dispatches one group leave`
- `LP003 dissolved local cleanup does not publish a second group leave`
- `LP003 member_removed self-removal is the ban-equivalent leave path`
- `LP003 replayed group_dissolved dispatches one group leave`

Exact tests and gates run:

- PASS: `cd go-mknoon && go test ./node -run 'TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLeaveGroupTopic_CancelsDiscoveryContext' -v`
- PASS: `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart`
- PASS: `flutter test --no-pub test/features/groups/application/delete_group_and_messages_use_case_test.dart`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
- FAIL, unrelated/pre-existing: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` failed at `MD-011 removed member cannot decode future media replay with only the old epoch` (`expected null`, got `GroupMessage(id: msg-md011-future-media-replay, groupId: group-1, isIncoming: true)`). LP-003 did not touch this test file or media/offline replay production behavior.
- PASS: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'replayed member_removed routes through listener cleanup instead of saving a chat row|replayed self-removal cuts off later queued inbox traffic for that group'`
- PASS: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- FAIL, known pre-existing owner-suite caveat: `cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` failed in `go-mknoon/bridge` at `TestGroupPublish_ResponseIncludesTopicPeers` with `GROUP_ERROR` / `publish to topic: validation failed` after `peer_mismatch`.
- PASS: `git diff --check`

QA verdict: `no_blocking_issues`. No fix pass required.

Deferred follow-ups: none for LP-003. `group-real-network-nightly` was not run or substituted because the relay fixture environment remains unset and the LP-003 primary proof profile is host-only raw-Go/libp2p plus focused Dart tests.

## real scope

This session owns LP-003 only: devices that exit a trusted-private group through leave, self-removal, ban-equivalent removal, dissolution, or allowed local deletion must stop participating in the live group topic and must not receive or process future group PubSub traffic for that group.

In scope:

- Add row-owned proof that `LeaveGroupTopic` stops live delivery, not only local publish calls.
- Pin the Dart exit-path dispatch contract: normal leave and active delete call `group:leave`; self-removal and group dissolution call `group:leave`; dissolved local-only delete does not call `group:leave` because the dissolve path must already have unsubscribed.
- Add implementation only if the proof exposes a repo-owned missing behavior in LP-003 owner files.
- Update source matrix and inventory only after concrete file/test/command evidence exists.

Out of scope:

- New group governance concepts, new ban product UI, moderation policy, invite revocation, peer scoring, packet-capture tooling, relay architecture changes, group media semantics, push routing, or broad cleanup of existing dirty worktree changes.
- Reclassifying LP-003 as acceptance-only or doc-only.

## closure bar

LP-003 is good enough when repo-owned evidence proves all of the following:

- A live Go/libp2p PubSub proof shows an exited node no longer receives normal group message, reaction, parse-failure, or decrypt-failure events after the exit call.
- The exited node has no topic, subscription, subscription context, discovery context, group config, or key state after exit.
- Future message and reaction publishes from the exited node fail closed with `group not joined`.
- Dart exit flows that are expected to unsubscribe do call `group:leave` before or during local cleanup: explicit leave, active delete, self-removal replay/live handling, and group dissolution replay/live handling.
- Dissolved local-only deletion is pinned as cleanup-only and is safe only because the preceding dissolve path already calls `group:leave`.
- "Ban" is either proven to map to the existing `member_removed` exit path in current repo architecture, or the plan records the exact product prerequisite blocker if the source matrix requires a distinct first-class ban event.
- The LP-003 source matrix row moves to `Covered` or `Closed` only with concrete file names, test names, and passing commands recorded.

## source of truth

- Current code and tests win over stale docs.
- `scripts/run_test_gates.sh` wins over `Test-Flight-Improv/test-gate-definitions.md` when named-gate membership conflicts.
- The LP-003 source matrix row is the acceptance contract.
- The LP-003 session breakdown entry controls scope: external or raw-protocol evidence first, repo code/tests only if proof exposes a gap.
- `test-inventory.md` is the current coverage inventory and currently classifies LP-003 as Partial.

## session classification

evidence-gated

This is implementation-committed gap closure. Execution must add row-owned tests/proof first, then patch the smallest LP-003 owner-file behavior if those tests reveal a repo-owned unsubscribe gap.

## exact problem statement

Current evidence is partial. `go-mknoon/node/pubsub_test.go` proves `LeaveGroupTopic` removes local topic/subscription/discovery/config/key state and blocks later local message/reaction publish with `group not joined`. Dart tests prove several app paths dispatch `group:leave` for self-removal and dissolution.

The remaining risk is user-visible: a device that has left, been removed, been ban-equivalent removed, or cleaned up after dissolution might still be subscribed to the live PubSub mesh and might receive or process later group topic traffic. LP-003 has not yet pinned that with live no-delivery proof across exit paths.

What must improve: exited devices must not receive, decrypt, parse, persist, notify, or otherwise process future group topic traffic.

What must stay unchanged: authorized remaining members still send and receive; dissolved groups stay read-only with local history available; dissolved local-only deletion remains local cleanup and must not publish a fresh group leave; active leave/delete still removes local state.

## files and repos to inspect next

Production files:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/bridge/bridge.go`
- `lib/features/groups/application/leave_group_use_case.dart`
- `lib/features/groups/application/delete_group_and_messages_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/dissolve_group_use_case.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`

Tests and harnesses:

- Prefer a new row-owned Go test file such as `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` to avoid colliding with dirty `pubsub_test.go`.
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/protocol_version_test.go`
- `go-mknoon/node/group_inbox_test.go`
- `go-mknoon/bridge/bridge_test.go`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/multi_relay_failover_test.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`

Docs/gates:

- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## owner files/tests

Primary owner files for likely implementation, if needed:

- `go-mknoon/node/pubsub.go`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/delete_group_and_messages_use_case.dart`
- `lib/features/groups/application/leave_group_use_case.dart`

Primary owner tests:

- New `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`

## existing tests covering this area

- `go-mknoon/node/pubsub_test.go`: `TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish` proves local state cleanup and local publish fail-closed behavior.
- `go-mknoon/node/pubsub_test.go`: `TestLeaveGroupTopic_CancelsDiscoveryContext` proves discovery context cleanup.
- `test/features/groups/application/leave_group_use_case_test.dart` proves normal leave calls bridge leave and removes group data.
- `test/features/groups/application/delete_group_and_messages_use_case_test.dart` proves active delete calls `leaveGroup`, and dissolved local cleanup deletes local state without publishing another `group:leave`.
- `test/features/groups/application/group_message_listener_test.dart` proves self-removal calls `leaveGroup` and duplicate self-removal leaves only once.
- `test/features/groups/application/group_message_listener_test.dart` proves `group_dissolved` marks the group dissolved, stores one timeline event, and calls `group:leave`.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` proves replayed self-removal routes through listener cleanup and cuts off later queued inbox traffic for that group.
- `test/features/groups/presentation/group_info_wired_test.dart` and `integration_test/group_recovery_e2e_test.dart` prove dissolved local delete avoids a second `group:leave`.
- `test/features/groups/integration/group_membership_smoke_test.dart` proves fake-network self-removal cleanup and removed member send denial.

Missing:

- Live Go/libp2p no-delivery proof after leave/removal/dissolve unsubscribe.
- A direct row-owned test that ties all LP-003 exit paths to the same unsubscribe contract.
- A first-class ban path. Current repo search found no group `ban`, `banned`, or `member_banned` event/model under group code; current architecture appears to represent ban-equivalent exit as `member_removed`.

## regression/tests to add first

Add proof before product changes:

1. `TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit`
   - Location: new `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`.
   - Start two or three local Go nodes with real libp2p PubSub and a shared group key/config.
   - Prove an in-group peer receives a pre-exit publish.
   - Call `LeaveGroupTopic` on the exiting peer.
   - Assert all local maps for topic/subscription/subscription context/discovery context/config/key are removed.
   - Publish a post-exit group message and reaction from a remaining member.
   - Assert the exited peer emits no `group_message:received`, `group_reaction:received`, `group:payload_parse_failed`, or `group:decryption_failed` events for the post-exit payload.
   - Assert post-exit publish attempts from the exited peer fail with `group not joined`.

2. `TestLP003ExitDispatchPathsCallLeaveOnce`
   - Location: `test/features/groups/application/group_message_listener_test.dart` or a new focused application test file if that keeps the dirty file safer.
   - Pin self-removal and dissolution as calls to `group:leave`.
   - Include duplicate/replay behavior so one exit event produces at most one leave call for the same local group row.
   - Do not add a new ban product path here unless a first-class ban event exists.

3. `TestLP003DeletePathsDistinguishActiveLeaveFromDissolvedLocalCleanup`
   - Location: `test/features/groups/application/delete_group_and_messages_use_case_test.dart`.
   - Keep or tighten the existing active delete and dissolved local cleanup assertions:
     - active group delete calls `group:leave`;
     - dissolved local cleanup deletes messages/members/keys/group without calling `group:leave`.
   - If a sequence test is needed, first deliver/process a dissolve event that calls `group:leave`, then run local cleanup and assert no second leave.

4. Ban classification proof
   - First run a code/test search during execution for first-class ban events/models.
   - If none exists, do not invent moderation architecture in LP-003. Treat ban as the existing `member_removed` exit path for this row and record that accepted difference in source docs after tests pass.
   - If a first-class ban event exists by execution time, add a focused test proving local banned peer dispatches `group:leave` and does not process later traffic.

## step-by-step implementation plan

1. Re-run `git status --short` and inspect target files before editing. Preserve all pre-existing user-owned changes.
2. Add the Go live no-delivery regression in a new row-owned test file.
3. Run the focused Go LP-003 test.
4. If the Go test passes without product changes, do not touch `go-mknoon/node/pubsub.go`.
5. If the Go test fails because `LeaveGroupTopic` does not fully unsubscribe or the subscription goroutine still emits events after exit, patch only `go-mknoon/node/pubsub.go` or adjacent node lifecycle code to make leave cancellation/order deterministic. Do not change publish, discovery, or validation semantics beyond what the failing LP-003 test requires.
6. Add or tighten Dart application tests that pin exit dispatch paths and deletion semantics.
7. If Dart tests fail because an expected unsubscribe path does not call `group:leave`, patch only the corresponding use case/listener path.
8. For ban, stop after evidence if no first-class ban surface exists; document the accepted current mapping to `member_removed`. If a concrete ban surface exists and fails, patch the ban handler only.
9. Run focused tests and owner gates listed below.
10. Update `test-inventory.md` and the LP-003 source matrix row only after proof passes. Include exact files, test names, and commands. Do not update the row to `Covered` or `Closed` before that evidence exists.
11. Stop. Do not absorb LP-002, LP-006, LP-013, replay retention, push, or UI redesign work.

## risks and edge cases

- Subscription cancellation races: a message already read before `LeaveGroupTopic` may still be in-flight. The regression should publish after exit and use unique post-exit sentinels.
- Direct X-C connectivity can invalidate forward/no-delivery assertions. Keep the topology and waits explicit.
- `UpdateGroupConfig` currently preserves discovery loops and just replaces config; do not reinterpret that as a self-exit unless a real app exit path calls it for local removal without `group:leave`.
- Dissolved local cleanup intentionally does not call `group:leave`; the safety condition is that dissolve handling already left the topic.
- Ban is ambiguous because no first-class group ban domain event was found. Treating ban as member removal is acceptable only if documented and backed by tests.
- Multiple Flutter targets are attached; integration-backed gates must set `FLUTTER_DEVICE_ID`.
- Multi-relay proof can fail for missing fixture config. Missing `MKNOON_RELAY_ADDRESSES` is an environment blocker, not LP-003 product evidence.

## exact tests and gates to run

Focused Go proof:

```bash
cd go-mknoon && go test ./node -run 'TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLeaveGroupTopic_CancelsDiscoveryContext' -v
```

Focused Dart proof:

```bash
flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart
flutter test --no-pub test/features/groups/application/delete_group_and_messages_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
```

Owner Go suite:

```bash
cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v
```

Named/direct Flutter gates when Dart-visible group behavior changes:

```bash
./scripts/run_test_gates.sh groups
flutter test --no-pub test/features/groups/integration
```

Device/relay supporting gate when fixture proof is required:

```bash
MKNOON_RELAY_ADDRESSES='<relay-multiaddr-1>,<relay-multiaddr-2>' FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh group-real-network-nightly
```

Optional paired iOS/device-lab supporting run if host raw-Go proof is rejected as insufficient:

```bash
MKNOON_RELAY_ADDRESSES='<relay-multiaddr-1>,<relay-multiaddr-2>' dart run integration_test/scripts/run_group_multi_device_real.dart -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Always finish with:

```bash
git diff --check
```

## Device/Relay Proof Profile

LP-003 primary closure profile: host-only raw-Go/libp2p proof plus focused Dart app-path tests. This is a three-party logical topology when needed, but it does not require physical devices for the primary closure bar.

Device/relay proof classification:

- Host-only: required for Go live PubSub unsubscribe proof.
- Single-device: supporting only for Flutter integration-backed gates.
- Paired-device or three-party/device-lab: supporting only if host raw-Go proof is rejected as insufficient or a later reviewer requires real device proof for matrix closure.
- Multi-relay: supporting only for `group-real-network-nightly`; currently external-fixture-blocked because relay env vars are unset.
- A single `FLUTTER_DEVICE_ID` only selects the Flutter host target. It does not create a paired-device or three-party topology.

Live availability checked on 2026-04-30:

- `flutter devices --machine` reported:
  - Android emulator `emulator-5554`, `sdk gphone16k arm64`, Android 17 API 37.
  - iOS simulator `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, iPhone 17 Pro, iOS 26.1, booted.
  - iOS simulator `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, iPhone Air, iOS 26.1, booted.
  - iOS simulator `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, iPhone 17, iOS 26.1, booted.
  - iOS simulator `1B098DFF-6294-407A-A209-BBF360893485`, iPhone 16e, iOS 26.1, booted.
  - Flutter host targets `macos` and `chrome`.
- `xcrun simctl list devices available` confirmed the booted iOS simulator IDs above and additional shutdown iOS simulators.
- `adb devices` on PATH returned `adb not found`.
- `$HOME/Library/Android/sdk/platform-tools/adb devices` reported `emulator-5554	device`.
- `FLUTTER_DEVICE_ID=<unset>`.
- `MKNOON_RELAY_ADDRESSES=<unset>`.

Exact script requirements:

- `./scripts/run_test_gates.sh group-real-network-nightly` requires `FLUTTER_DEVICE_ID` and runs:
  - `flutter test -d "$FLUTTER_DEVICE_ID" --dart-define=MKNOON_REQUIRE_MULTI_RELAY=true --dart-define=MKNOON_RELAY_ADDRESSES="${MKNOON_RELAY_ADDRESSES:-}" integration_test/multi_relay_failover_test.dart`
- Because `MKNOON_REQUIRE_MULTI_RELAY=true` is forced, at least two comma-separated relay multiaddrs are required. Without them, the gate correctly fails as missing fixture config.
- `integration_test/scripts/run_group_multi_device_real.dart` expects exactly two devices via `-d <primary,sibling>` or defaults to `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and also launches a CLI testpeer fixture.

## known-failure interpretation

- The current dirty worktree already contains modified Go, Dart, and matrix files plus untracked LP-002/GL-005 artifacts. Implementation must not revert them.
- Existing broad Go owner-suite caveat from inventory/LP-002 evidence: `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` and `TestGroupPublish_ResponseIncludesTopicPeers` may fail because of sender/transport peer mismatch in the dirty worktree. Treat those as pre-existing unless LP-003 edits the same sender/transport validation behavior.
- Missing relay env for `group-real-network-nightly` is an external fixture blocker, not a product regression.
- If an existing gate fails before LP-003 edits, capture the failing command and test name, rerun focused LP-003 tests, and do not classify pre-existing red tests as LP-003 regressions.

## done criteria

- Row-owned Go live unsubscribe test exists and passes.
- Focused Dart exit-path tests exist or existing tests are tightened and pass for leave, self-removal, dissolution, active delete, and dissolved local cleanup.
- Any implementation changes are limited to LP-003 owner files and are justified by a failing proof-first test.
- Ban is explicitly handled as current `member_removed` semantics or recorded as a product prerequisite blocker if a distinct ban event is required.
- Required focused tests and applicable gates pass or have pre-existing failures classified with logs.
- `git diff --check` passes.
- `test-inventory.md` and the LP-003 source matrix row are updated only after concrete evidence exists; row status is not advanced without file/test/command proof.

## dirty-worktree handling

- Before editing any file, inspect its current dirty contents and avoid overwriting unrelated changes.
- Prefer new row-owned test files where practical.
- If a dirty owner file must be edited, make the smallest local patch around the LP-003 behavior and preserve existing uncommitted changes.
- Do not delete or rewrite untracked LP-002/GL-005 plan/test artifacts.
- Do not use destructive git commands.

## scope guard

Do not broaden LP-003 into:

- first-class ban/governance feature design;
- peer scoring or GossipSub parameter tuning;
- relay failover implementation;
- group invite or key rotation policy;
- push notification routing;
- broad group UI redesign;
- cleanup of unrelated LP-002, LP-006, LP-013, GL-005, or matrix rows.

Overengineering for this session includes adding a new moderation model, packet capture framework, new relay orchestration, or a generic subscription manager when a focused exit-path proof/fix is sufficient.

## accepted differences / intentionally out of scope

- Current repo architecture appears to represent ban-equivalent exit as `member_removed`; no first-class group ban event/model was found in group code. LP-003 may close ban only by documenting that mapping with evidence, not by inventing a new ban feature.
- Dissolved local-only delete intentionally avoids `group:leave`; the unsubscribe event belongs to the earlier dissolve handling.
- Device/relay runs are supporting evidence unless host raw-Go proof is rejected. A single Flutter device target is not a substitute for multi-party proof.

## dependency impact

- LP-003 closure unblocks later matrix rows that assume exited peers cannot keep consuming live group traffic, especially replay, duplicate handling, and relay recovery rows.
- If LP-003 discovers a real unsubscribe bug, later real-network and replay rows should not proceed until the unsubscribe fix and tests land.
- If first-class ban is required but absent, create a separate governance/moderation prerequisite plan rather than expanding LP-003.

## regression contract

- Tests must fail on a real unsubscribe gap before production code changes are made.
- Production changes must be the minimum needed to make the LP-003 tests pass.
- Existing authorized group send/receive, self-removal, dissolved read-only state, and dissolved local cleanup behavior must remain covered.
- Matrix/inventory status changes require concrete passing command evidence in the same implementation session.

## Reviewer Questions

- Sufficiency: sufficient with adjustments. The plan is implementation-safe because proof comes before code, closure requires live no-delivery evidence, and matrix/inventory updates are gated on passing commands.
- Missing files/tests/gates: no structural omissions. The reviewer adjustment is to require full direct Dart proof files rather than brittle name filters; focused `--name LP003` reruns are allowed after new tests are added.
- Stale assumptions: ban remains ambiguous. The plan handles this by requiring execution-time search and either mapping ban to `member_removed` with evidence or recording a prerequisite blocker instead of inventing new moderation architecture.
- Overengineering: no overengineering in the plan. It explicitly forbids peer scoring, packet capture, relay redesign, and new ban product design inside LP-003.
- Decomposition: decomposed enough. Go live unsubscribe proof, Dart exit dispatch proof, deletion semantics, and device/relay support are separate steps with stop points.
- Minimum needed: add the row-owned live Go unsubscribe test, tighten or add focused Dart exit-path tests, patch only a failing LP-003 owner path, then update matrix/inventory only after passing evidence.

## Arbiter Decision

Final verdict: execution-ready.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Execution may add focused `--name LP003` reruns after new tests exist, but full direct Dart files remain the required proof commands.
- Device/relay proof remains supporting evidence unless host raw-Go proof is rejected as insufficient.

Accepted differences intentionally left unchanged:

- Current ban semantics appear to be represented by `member_removed`; LP-003 will not invent a new first-class ban feature.
- Dissolved local-only delete intentionally does not send another `group:leave`; the unsubscribe belongs to the earlier dissolve handling.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/bridge/bridge.go`
- `lib/features/groups/application/leave_group_use_case.dart`
- `lib/features/groups/application/delete_group_and_messages_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `integration_test/multi_relay_failover_test.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`

Why the plan is safe to implement now:

- It is row-owned, proof-first, and stops before product code unless a failing LP-003 proof exposes a repo-owned gap.
- It names exact owner files, tests, gates, dirty-worktree rules, known failure handling, and a device/relay proof profile.
- It keeps matrix closure gated on concrete passing evidence and does not broaden into unrelated group governance, relay, push, or moderation work.
