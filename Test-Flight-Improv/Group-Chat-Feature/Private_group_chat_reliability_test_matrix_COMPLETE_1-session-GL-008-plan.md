# GL-008 Leave Cancels Subscription And Discovery Plan

Status: execution-ready

## Planning Progress

- 2026-05-10T02:29:06Z - Arbiter completed. Files inspected since last update: reviewer findings and final plan sections. Decision/blocker: no structural blockers remain; reviewer adjustments are incremental details already incorporated; plan is execution-ready. Next action: execute later in a separate implementation session, starting with the GL-008 Go regression.
- 2026-05-10T02:28:50Z - Arbiter started. Files inspected since last update: reviewer findings, adjusted test/gate contract, scope guard, accepted differences. Decision/blocker: no structural blocker apparent; classify reviewer adjustments next. Next action: write arbiter decision and final readiness status.
- 2026-05-10T02:28:08Z - Reviewer completed. Files inspected since last update: GL-008 draft plan, existing gate/test commands, discovery event steps from `pubsub.go`. Decision/blocker: sufficient with adjustments; no structural blocker. Next action: Arbiter will classify the reviewer adjustment and decide whether the plan can become execution-ready.
- 2026-05-10T02:27:53Z - Reviewer started. Files inspected since last update: draft plan content and mandatory-section coverage. Decision/blocker: no blocker found yet; likely adjustment is to make event filtering/race proof more explicit. Next action: complete sufficiency review and patch any non-structural gaps.
- 2026-05-10T02:26:32Z - Planner completed. Files inspected since last update: Evidence Collector findings and existing test names from `go test ./node -list`. Decision/blocker: draft plan is tests-only with a stop rule if the regression proves a production bug or requires a new fake-time/test seam. Next action: Reviewer will check sufficiency, gates, stale assumptions, and scope containment.

## Execution Progress

- 2026-05-10T02:30:46Z - Contract extracted. Files inspected since last update: this GL-008 plan, `Test-Flight-Improv/test-gate-definitions.md`, `git status --short`, and initial `rg` over Go owner files/tests. Decision/blocker: tests-only contract is concrete; source matrix/breakdown updates are intentionally deferred; dirty unrelated work is present and must be preserved. Next action: attempt nested Executor materialization with `model: gpt-5.5` and `reasoning_effort: xhigh`; use local sequential fallback only if child materialization fails under the skill rules.
- 2026-05-10T02:31:25Z - Executor spawning. Files inspected since last update: `codex --help` and `codex exec --help`. Command running: `codex exec -m gpt-5.5 -c reasoning_effort="xhigh" ...`. Decision/blocker: CLI supports a bounded fresh child attempt. Next action: wait for Executor result, then spawn separate QA Reviewer if trustworthy evidence materializes.
- 2026-05-10T02:31:55Z - Executor spawn retry. Files inspected or touched since last update: plan progress only. Command outcome: first `codex exec` command rejected unsupported `-a` option before child materialization; no repo work came from that attempt. Decision/blocker: retry once with supported non-interactive options. Next action: wait for corrected Executor child result.
- 2026-05-10T02:32:53Z - Executor child started. Files inspected since last update: this GL-008 plan, `Test-Flight-Improv/test-gate-definitions.md`, `git status --short`, and `rg` over `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/rendezvous.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`, and `go-mknoon/node/pubsub_delivery_test.go`. Decision/blocker: dirty owner files exist from earlier work and must be preserved; GL-008 remains tests-only unless the new regression proves a production gap. Next action: inspect the exact leave/discovery/test helper bodies and add the row-owned regression.
- 2026-05-10T02:35:48Z - Owner seams inspected. Files inspected since last update: `go-mknoon/node/pubsub.go` (`JoinGroupTopic`, `LeaveGroupTopic`, `handleGroupSubscription`, discovery/dial helpers, `runGroupDiscoveryCycle`, `groupPeerDiscoveryLoop`), `go-mknoon/node/rendezvous.go` (`RendezvousDiscover`, `RendezvousUnregister`), `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/group_security_harness_test.go`, and `go-mknoon/node/node_test.go` event collector helpers. Decision/blocker: existing hooks and collectors can drive an active registered discovery loop and assert post-leave silence without production seams. Next action: add `TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave` in the existing unsubscribe exit-path test file.
- 2026-05-10T02:37:56Z - Executor child closed and local fallback started. Files inspected or touched since last update: plan progress and `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`. Command outcome: child stayed running after bounded waits without adding the required regression or returning a trustworthy result; only progress notes were written. Decision/blocker: classify the child attempt as `spawn_or_tool_failure` and use the skill's local sequential fallback because the execution contract is concrete and there is no partial code/test landing to reconcile. Next action: perform Executor responsibilities locally, then run the required commands before local QA.
- 2026-05-10T02:42:37Z - Local Executor editing. Files inspected or touched since last update: `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/config.go`, event collector helpers, and this plan. Decision/blocker: existing hooks can avoid real 30s sleeps and no production edit is needed. Next action: add the GL-008 regression and helper assertions, then run the exact required commands.
- 2026-05-10T02:43:44Z - Local Executor edit completed. Files touched since last update: `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` and this plan. Command finished: `gofmt -w go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`. Decision/blocker: tests-only regression added; no production, Flutter, source matrix, or breakdown files touched by GL-008. Next action: run direct Go proof.
- 2026-05-10T02:44:17Z - Direct Go proof completed. Files touched since last update: this plan. Command finished: `(cd go-mknoon && go test ./node -run 'TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestLeaveGroupTopic_CancelsDiscoveryContext|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit|TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup' -count=1)` -> PASS (`ok github.com/mknoon/go-mknoon/node 11.830s`). Decision/blocker: direct GL-008 and related leave/live-delivery/unjoined publish proof passed. Next action: run row Go sweep.
- 2026-05-10T02:44:51Z - Row Go sweep completed. Files touched since last update: this plan. Command finished: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)` -> PASS (`ok github.com/mknoon/go-mknoon/node 11.954s`). Decision/blocker: row sweep passed. Next action: run direct race proof.
- 2026-05-10T02:45:30Z - Direct race proof failed and triaged. Files inspected or touched since last update: race output, `go-mknoon/node/node.go`, and this plan. Command finished: `(cd go-mknoon && go test -race ./node -run 'TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit' -count=1)` -> FAIL. Decision/blocker: caused by this session's new test using `startLocalNodeForMultiRelayTestWithCollector`, which assigns `eventCallback` after `Start` and races with background event emission under `-race`; production behavior was not implicated. Next action: fix the test harness usage by starting the GL-008 collector node with the callback installed before `Start`, then rerun required proof.
- 2026-05-10T02:45:58Z - Race fix applied. Files touched since last update: `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` and this plan. Command finished: `gofmt -w go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`. Decision/blocker: GL-008 now uses a test-local collector node helper that installs the callback before `Start`; still tests-only. Next action: rerun direct Go proof and then the remaining required commands.
- 2026-05-10T02:46:34Z - Direct Go proof rerun completed. Files touched since last update: this plan. Command finished: `(cd go-mknoon && go test ./node -run 'TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestLeaveGroupTopic_CancelsDiscoveryContext|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit|TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup' -count=1)` -> PASS (`ok github.com/mknoon/go-mknoon/node 11.825s`). Decision/blocker: direct proof remains green after race-harness fix. Next action: rerun row Go sweep.
- 2026-05-10T02:47:07Z - Row Go sweep rerun completed. Files touched since last update: this plan. Command finished: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)` -> PASS (`ok github.com/mknoon/go-mknoon/node 11.934s`). Decision/blocker: row sweep remains green after race-harness fix. Next action: rerun direct race proof.
- 2026-05-10T02:47:50Z - Direct race proof rerun failed and triaged. Files inspected or touched since last update: race output and this plan. Command finished: `(cd go-mknoon && go test -race ./node -run 'TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit' -count=1)` -> FAIL. Decision/blocker: unrelated-to-production but required-command blocking issue in existing LP003 test harness; `startLocalNodeForMultiRelayTestWithCollector` also assigns `eventCallback` after `Start`. Next action: update LP003 in the same test file to use the race-safe collector-start helper, then rerun required commands.
- 2026-05-10T02:48:16Z - LP003 race-harness fix applied. Files touched since last update: `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` and this plan. Command finished: `gofmt -w go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`. Decision/blocker: required race command's existing LP003 collector path now uses the same before-`Start` callback helper; still tests-only. Next action: rerun direct Go proof, row sweep, and race proof.
- 2026-05-10T02:49:31Z - Go proof set rerun completed. Files touched since last update: this plan. Commands finished: `(cd go-mknoon && go test ./node -run 'TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestLeaveGroupTopic_CancelsDiscoveryContext|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit|TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup' -count=1)` -> PASS (`ok github.com/mknoon/go-mknoon/node 11.947s`); `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)` -> PASS (`ok github.com/mknoon/go-mknoon/node 11.965s`); `(cd go-mknoon && go test -race ./node -run 'TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit' -count=1)` -> PASS (`ok github.com/mknoon/go-mknoon/node 13.071s`). Decision/blocker: all Go direct, row, and race proof is green with tests-only changes. Next action: run Flutter startup rejoin smoke.
- 2026-05-10T02:49:59Z - Flutter startup rejoin smoke completed. Files touched since last update: this plan. Command finished: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` -> PASS (`00:00 +3: All tests passed!`). Decision/blocker: required Flutter companion smoke passed; `./scripts/run_test_gates.sh groups` is not required because GL-008 touched no production behavior and no Flutter/Dart files. Next action: run `git diff --check`.
- 2026-05-10T02:50:28Z - Diff check and local QA completed. Files inspected since last update: landed diff for `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`, this plan, and `git status --short`. Command finished: `git diff --check` -> PASS. Decision/blocker: local QA found no blocking issues; scope stayed tests-only, production/Flutter/source-matrix/session-breakdown files were not touched for GL-008, all required commands passed, and the conditional groups gate was not required. Next action: write final verdict.
- 2026-05-10T02:50:28Z - Final verdict written. Files touched since last update: this plan. Decision/blocker: `accepted`; no blocking issues remain and no execution-phase follow-ups are required. Next action: closure phase may update source matrix and session breakdown separately as requested.

## real scope

GL-008 owns exactly this source row: leaving an already joined group while its discovery loop is active must cancel the group subscription and discovery loop before app state is deleted, then stay silent for that group. The executable work is tests-only unless the new GL-008 regression proves otherwise.

In scope:

- Add or verify one row-owned Go regression for `LeaveGroupTopic(G)` on an active group topic.
- Prove no post-leave group discovery/register/dial events for `G`, no post-leave inbound group events for the leaving node, and post-leave publish/reaction attempts fail as `group not joined`.
- Update only the GL-008 source matrix/breakdown evidence after the regression and gates pass.

Out of scope:

- GL-009 validator unregister/rejoin freshness.
- GL-010 unknown-group leave no-op behavior.
- Flutter/Dart behavior changes, unless the regression proves app bridge-before-delete ordering is the source of the gap.
- Broad group recovery, key rotation, membership removal, or durable offline replay behavior.

## closure bar

Good enough for GL-008 means a deterministic row-owned regression proves all of these:

- `LeaveGroupTopic` cancels the discovery context and subscription context, cancels the pubsub subscription, closes/removes the topic, and removes config/key state for the group.
- After leave, the leaving node emits no further `group:discovery`, `group_message:received`, `group_reaction:received`, `group:payload_parse_failed`, or `group:decryption_failed` events for the left group during the test's bounded post-leave window.
- A post-leave `PublishGroupMessage` and `PublishGroupReaction` from the leaving node fail with `group not joined`.
- Existing leave cleanup, live-delivery cutoff, unjoined publish, and startup rejoin smoke tests stay green.

## source of truth

- Active task contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GL-008 and the corresponding session-breakdown row.
- Current code and tests win over stale prose.
- `Test-Flight-Improv/test-gate-definitions.md` is the named-gate source of truth; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` has a stale/conflicting `GL-008` entry from a different source matrix and different semantics; do not use it to close this GL-008 row.

## session classification

implementation-ready

Disposition: tests-only remains valid. Repo evidence shows the production leave path already cancels discovery and subscription before deleting group config/key, and the Flutter leave path already calls the bridge leave command before local group/member/key deletion. The missing artifact is exact GL-008 row coverage.

## exact problem statement

The current source matrix leaves GL-008 open because existing tests do not directly prove that an active group discovery loop and live subscription stay silent after `LeaveGroupTopic(G)`.

User-visible behavior to protect: after a member leaves or deletes an active group, the device must stop live group discovery and live message delivery for that group, and local sends from that device must fail honestly as not joined.

Must stay unchanged: normal joins, normal post-join publish/receive, startup group rejoin, known-member discovery, validator behavior, unknown-group leave behavior, and app local cleanup ordering.

## files and repos to inspect next

Production files:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/bridge/bridge.go`
- `lib/features/groups/application/leave_group_use_case.dart`
- `lib/features/groups/application/delete_group_and_messages_use_case.dart`

Test and gate files:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`

## existing tests covering this area

- `go-mknoon/node/pubsub_test.go::TestLeaveGroupTopic_CancelsDiscoveryContext` proves `groupDiscoveryCtx` is removed on leave.
- `go-mknoon/node/pubsub_test.go::TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish` proves leave removes topic/subscription/subscription-context/discovery-context/config/key state and blocks post-leave publish/reaction as `group not joined`.
- `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go::TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit` proves a live exited peer receives no post-exit group message/reaction/parse/decrypt events and cannot publish after exit.
- `go-mknoon/node/pubsub_delivery_test.go::TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup` proves unjoined publish returns an error and zero peer count.
- Flutter leave/delete tests prove app code dispatches `group:leave` and then clears local group state for normal leave/delete flows.

Missing: one exact GL-008 regression that combines active discovery-loop cancellation, no post-leave group discovery/register/dial evidence, no inbound events, and post-leave publish failure under the current source matrix.

## regression/tests to add first

Add the direct Go regression first, before any production edit:

- Preferred name: `TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave`.
- Preferred location: `go-mknoon/node/pubsub_test.go` if the test is mostly local state/discovery-hook based; `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` if it reuses the existing live multi-node post-exit delivery harness.
- Use existing test seams first: `rendezvousRegisterHook`, `rendezvousDiscoverHook`, `waitForCircuitAddressHook`, event collector helpers, and a test-controlled `relayReady` channel.
- Avoid real 30 second sleeps. If the row cannot be tested without adding a fake-time/sleep seam or other production-only test hook, stop and reclassify the session as code+tests with that seam as the scope correction.
- Filter post-leave discovery evidence by `groupId` and by discovery steps that represent register/discover/dial work, including `registered`, `discover_failed`, `discover_result`, `direct_dial`, `known_member_*`, and `dial_*`/`direct_dial_*` steps.

The regression should fail only if one of these is true:

- leave does not cancel/remove active discovery/subscription state,
- a post-leave discovery/register/dial event is emitted for the left group,
- a post-leave inbound group event is emitted for the leaving node,
- post-leave publish/reaction does not fail as `group not joined`.

## step-by-step implementation plan

1. Re-read the current `LeaveGroupTopic`, `groupPeerDiscoveryLoop`, `runGroupDiscoveryCycle`, `handleGroupSubscription`, and existing leave tests before editing.
2. Add `TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave` as a RED-first regression using existing hooks and event collectors.
3. Drive discovery to an active, observable point, then call `LeaveGroupTopic(groupId)`.
4. Assert local pubsub state is removed for `groupId`.
5. Assert post-leave publish and reaction fail with `group not joined`.
6. Assert no new group discovery/register/dial events and no inbound group events are emitted for `groupId` after the post-leave baseline.
7. If the new test is green without production edits, keep this as tests-only and update the GL-008 source matrix/breakdown evidence.
8. If the new test fails because production emits post-leave discovery or inbound events, stop and replan GL-008 as code+tests; likely production candidates are `LeaveGroupTopic`, `groupPeerDiscoveryLoop` context checks, `runGroupDiscoveryCycle`, or subscription-handler shutdown.
9. If the new test cannot be made deterministic without a new fake-time/sleep seam, stop and replan as code+tests for the minimal seam. Do not sneak a production seam into a tests-only execution.

## risks and edge cases

- Discovery cancellation while `groupPeerDiscoveryLoop` is sleeping versus while it is inside a discovery cycle.
- In-flight subscription delivery that has already returned from `sub.Next(ctx)` when leave starts.
- Real timer waits around `GroupDiscoveryInterval` or `GroupDiscoveryWarmInterval` making the regression slow or flaky.
- Event assertions accidentally matching discovery from another group; always filter by `groupId`.
- GL-009 validator unregister and GL-010 unknown leave are adjacent but separate rows.

## exact tests and gates to run

Direct Go proof:

```bash
(cd go-mknoon && go test ./node -run 'TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestLeaveGroupTopic_CancelsDiscoveryContext|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit|TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup' -count=1)
```

Row Go sweep:

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)
```

Direct race proof for the new cancellation regression:

```bash
(cd go-mknoon && go test -race ./node -run 'TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit' -count=1)
```

Flutter companion smoke from the breakdown:

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Named gate if production behavior changes or any Flutter/Dart file is touched:

```bash
./scripts/run_test_gates.sh groups
```

Always finish with:

```bash
git diff --check
```

## known-failure interpretation

- Direct GL-008 Go regression failures are GL-008 failures unless the failure is clearly a compile break from unrelated dirty work.
- Existing broad-suite failures outside the direct commands do not block GL-008 closure unless they involve group leave, group discovery, group subscription, or startup rejoin behavior.
- If `./scripts/run_test_gates.sh groups` is run and fails outside the touched GL-008 surface, record the exact failing test and keep the direct GL-008 evidence separate.
- Dirty unrelated files in the worktree are not GL-008 evidence and must not be reverted.

## done criteria

- The new or verified row-owned GL-008 regression exists and passes.
- Existing leave cleanup, live-delivery cutoff, unjoined publish, row Go sweep, Flutter startup rejoin smoke, and `git diff --check` pass or have clearly documented unrelated failures.
- Source matrix row GL-008 and the breakdown GL-008 ledger/order row are updated only after passing evidence exists.
- No production code changes are made unless a failed regression forces a documented scope correction.

## scope guard

Do not change:

- validator unregister/rejoin behavior for GL-009,
- unknown-group leave behavior for GL-010,
- group key/config update behavior,
- Flutter UI, repositories, or local database schema,
- broad discovery/backoff policy,
- relay/rendezvous protocol behavior.

Overengineering for this session includes adding a new discovery scheduler, adding broad fake-clock infrastructure, changing public APIs, rewriting discovery loops, or expanding closure to removed-member, validator, or unknown-leave rows.

## accepted differences / intentionally out of scope

- The current Go loop uses real timers, not a fake-time scheduler. A deterministic existing-hook test is preferred; lack of fake time is accepted only if the test remains bounded and non-flaky.
- `RendezvousUnregister` has no hook. GL-008 requires no further discovery/register/dial events after leave; exact unregister accounting belongs only if a future row explicitly requires it.
- App-local dissolved cleanup can delete local state without `group:leave`; GL-008 covers normal active leave/delete paths where `group:leave` is called.

## dependency impact

GL-008 closure supports later confidence for removed-member unsubscribe rows such as GM-016 and for normal leave/delete reliability, but it must not close GL-009, GL-010, GM-016, or LP rows by implication. If GL-008 becomes code+tests, later leave/rejoin plans should wait for the corrected leave cancellation behavior before relying on it.

## Reviewer Findings

Sufficiency: sufficient with adjustments.

Missing files/tests/gates: no missing production files; add direct race proof for the new active cancellation regression and explicit discovery-event filtering so the test does not overcount unrelated events.

Stale assumptions: the `test-inventory.md` GL-008 entry is stale for this source matrix and must not be used as closure evidence.

Overengineering check: the plan correctly rejects fake-clock infrastructure and production seams during tests-only execution unless the executor stops and reclassifies the session.

Minimum needed for sufficiency: keep the plan tests-only, add one GL-008 Go regression, run direct Go/race/smoke gates, and stop on any code-seam or production-behavior proof.

## Arbiter Decision

Final classification: execution-ready, tests-only.

Structural blockers: none.

Incremental details incorporated:

- Add explicit discovery-event step filtering for post-leave register/discover/dial assertions.
- Add a direct race proof for the new active leave cancellation regression.

Accepted differences:

- Existing code has real timers rather than fake time; the execution plan prefers existing hooks and bounded waits, with a stop rule if that is not deterministic.
- `RendezvousUnregister` is not directly hooked; GL-008 does not require unregister accounting.
- GL-009 validator unregister and GL-010 unknown leave remain separate rows.

Why safe to implement now: the plan changes no production behavior by default, identifies the exact missing regression, names the files and gates, and includes a hard stop if evidence proves code is needed.
