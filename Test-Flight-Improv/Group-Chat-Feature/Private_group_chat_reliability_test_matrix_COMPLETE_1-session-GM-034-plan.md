# GM-034 Implementation Plan: Membership Update While Direct PubSub Receive Is Running

Status: accepted/closed

## Planning Progress

- 2026-05-11 22:58:00 CEST - Planner completed. Files inspected since last update: none. Decision/blocker: draft plan written with regression-first execution and device proof requirements. Next action: run Reviewer.
- 2026-05-11 23:01:00 CEST - Reviewer started. Files inspected since last update: draft plan. Decision/blocker: no blocker; check specificity, closure bar, gates, and device proof profile. Next action: record sufficiency findings.
- 2026-05-11 23:02:00 CEST - Reviewer completed. Files inspected since last update: draft plan. Decision/blocker: sufficient with one tightening adjustment: make the canonical host/device membership update an unrelated `member_removed` for Charlie, with optional `member_added` only if cheap, so execution does not drift. Next action: run Arbiter.
- 2026-05-11 23:03:00 CEST - Arbiter started. Files inspected since last update: reviewer-pass plan. Decision/blocker: classify reviewer output. Next action: finalize reusable plan if no structural blocker remains.
- 2026-05-11 23:04:00 CEST - Arbiter completed. Files inspected since last update: reviewer-pass plan. Decision/blocker: no structural blockers remain; plan is execution-ready for GM-034 only. Next action: execute in a separate implementation pass when requested.

## Execution Progress

- 2026-05-11 23:58:00 CEST - Closure Writer final status recorded. Files touched since last update: this plan only. Decision/blocker: GM-034 is accepted/closed for documentation after the repo-owned listener blocker was superseded by Recovery Executor implementation plus QA Reviewer pass; source matrix and breakdown closure updates are handled in the closure phase. Evidence anchor: listener suite exit 0 with `105` tests passed, GM-029 selector exit 0, GM-034 host proof exit 0, exact device proof exit 0, groups gate exit 0, and completeness-check `732/732` classified. Next action: keep historical blocked entries as superseded audit trail and use the source matrix/breakdown as current closure references.
- 2026-05-11 23:46:03 CEST - Focused recovery selectors completed. Files touched since last update: `lib/features/groups/application/group_message_listener.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`, this plan. Commands completed: `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "GM-014 member_added event time becomes Charlie re-add joinedAt and removed-window sender traffic stays rejected"` exit 0; `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "PREREQ-SIGNED-COMMIT-AUDIT valid signed transition applies live and duplicate replay is idempotent while tampered replay is blocked"` first attempt exit 1 (`peer-audit-new` null), then after signed-audit event-time fix exit 0; `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "duplicate member_added keeps one canonical member state and one UI stream event"` exit 0; `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "self-removal calls leaveGroup and emits on groupRemovedStream"` exit 0; `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "duplicate self-removal emits one removal signal and leaves once"` exit 0; `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "does not notify after self-removal deletes the group"` exit 0; `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "duplicate members_added keeps one timeline row and member set"` exit 0. Decision/blocker: all seven required focused signatures are now green after using verified signed audit `eventAt` for signed add events that omit container `eventAt`. Next action: run full `group_message_listener_test.dart --reporter expanded`.
- 2026-05-11 23:44:14 CEST - Recovery patch formatted. Files touched since last update: `lib/features/groups/application/group_message_listener.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`, this plan. Command completed: `dart format lib/features/groups/application/group_message_listener.dart test/shared/fakes/in_memory_group_message_repository.dart` exit 0. Decision/blocker: listener now resolves explicit `member_removed.removedAt` / `member_added` / `members_added.eventAt` ahead of config versions, skips duplicate add replays before event-log append/config sync/timeline emit when the deterministic timeline row already exists, and the fake `count` excludes hidden cutoff markers. Next action: run the seven focused recovery selectors in order.
- 2026-05-11 23:39:44 CEST - Recovery Executor pass started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-034-plan.md`, `lib/features/groups/application/group_message_listener.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`, `test/features/groups/application/group_message_listener_test.dart`, `git status --short`. Command currently running: none. Decision/blocker: executing only the repo-owned listener-gate recovery blocker under the narrowed write scope; broad dirty worktree is treated as user/prior-run work. Next action: inspect owner-file implementations, patch timestamp precedence/idempotence/hidden cutoff behavior, then run the seven focused selectors before the full listener gate.
- 2026-05-11 23:27:40 CEST - QA Reviewer completed. Files inspected since last update: `/tmp/gm034_qa_result.txt`, `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm034_xoW6M1/orchestrator_verdict.json`, `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm034_xoW6M1/gmp_1778534173894_bob_verdict.json`, GM-034 owner-file diffs, and source matrix/breakdown diffs. Command completed: spawned QA Reviewer exit 0. Decision/blocker: QA found no GM-034-owned blocker, verified exact device proof `scenario=gm034` with `ok=true`, confirmed Bob received both order-case Alice messages exactly once, and found no GM-034 execution edits to the read-only source matrix or session-breakdown closure ledger. QA classified the red `group_message_listener_test.dart` command as an external/pre-existing non-GM-034 listener/idempotence/self-removal failure. Next action: record controller final verdict; no GM-034 same-session recovery pass.
- 2026-05-11 23:28:00 CEST - Final execution verdict recorded: `blocked_not_accepted`. Files touched since last update: this plan only. Evidence passed: `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-034"` exit 0; required Go direct and race GM-034/GL-011 commands exit 0; `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name "GM-034"` exit 0; combined member-removal/group-membership command exit 0; onboarding command exit 0; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` exit 0; `./scripts/run_test_gates.sh completeness-check` exit 0 with `732/732 test files classified`; exact 3-party GM-034 proof with relay env and Alice/Bob/Charlie simulators `560D3E2D-78F8-4D28-A010-16B399581C99,511B36DA-7113-41A7-A718-4450C87C0E62,DE36DBBE-64FC-4652-AAD9-17329A1BA245` exit 0. Blocking evidence: required `flutter test test/features/groups/application/group_message_listener_test.dart` exit 1 with pre-existing non-GM-034 GM-014/PREREQ duplicate-system-event/self-removal listener failures in dirty listener files not touched by GM-034. Blocker class: `external_pre_existing_required_gate_failure`. Next safe action: route/fix the listener-suite blocker in its owning session, then rerun that required gate before considering a broader accepted verdict; keep GM-034 source row Open until the source matrix is updated in a closure phase.
- 2026-05-11 23:34:00 CEST - Recovery Input recorded by controller after gap-closure reconciliation of the required gate failure. Files inspected since last update: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/domain/repositories/group_message_repository.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`. Failing command reproduced: `flutter test test/features/groups/application/group_message_listener_test.dart --reporter expanded` exit 1. Blocker class corrected from `external_pre_existing_required_gate_failure` to `repo_owned_required_gate_blocker`. Failing tests/signature: GM-014 removed-window re-add removes no Charlie because stale default `groupConfig.configVersion` overrides explicit `removedAt`/`eventAt`; PREREQ-SIGNED-COMMIT-AUDIT valid signed add is ignored because default config version is older than the inferred membership watermark; duplicate `member_added`/`members_added` replays save or emit duplicate timeline rows because equal-version replays are allowed; self-removal and post-removal notification tests count the hidden cutoff marker as a visible message in the in-memory repository. Owner files for recovery: `lib/features/groups/application/group_message_listener.dart` and `test/shared/fakes/in_memory_group_message_repository.dart`, with focused listener tests as proof. Next action: fresh recovery plan/execution pass; do not close GM-034 until the listener gate is green or a narrower non-repo blocker is proven.
- 2026-05-11 23:23:38 CEST - QA Reviewer handoff started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-034-plan.md`, `/tmp/gm034_executor_result.txt`, GM-034 owner-file status. Command currently running: none. Decision/blocker: Executor completed row-owned GM-034 implementation and exact device proof; required `group_message_listener_test.dart` failed with pre-existing non-GM-034 listener/idempotence/self-removal failures. Next action: spawn separate QA Reviewer with bounded evidence to classify sufficiency and final verdict.
- 2026-05-11 22:55:13 CEST - Executor local pass started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-034-plan.md`, `/Users/I560101/.codex/skills/run-flutter-host-gates/SKILL.md`, `git status --short`. Command currently running: none. Decision/blocker: executing GM-034 only; all pre-existing dirty files, including GM-033/earlier GM-034 deltas, are treated as user/prior-run work. Planned owner files to inspect/touch: `test/features/groups/integration/group_membership_smoke_test.dart`, `go-mknoon/node/pubsub_delivery_test.go`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/integration/group_multi_party_device_criteria_test.dart`. Next action: inspect owner-file patterns and add/verify the GM-034 host regression first.
- 2026-05-11 22:56:31 CEST - Owner-file inspection completed for host regression. Files inspected since last update: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `test/shared/fakes/group_test_user.dart`, pre-existing diffs for GM owner files. Command currently running: none. Decision/blocker: no existing GM-034 host regression was found; fake network supports held/reversed delivery and `GroupTestUser.removeMember` emits canonical unrelated `member_removed`. Next action: touch `test/features/groups/integration/group_membership_smoke_test.dart` to add the RED GM-034 host test.
- 2026-05-11 22:58:03 CEST - Host regression added. Files touched since last update: `test/features/groups/integration/group_membership_smoke_test.dart`. Command currently running: `dart format test/features/groups/integration/group_membership_smoke_test.dart`. Decision/blocker: GM-034 host test now stages Bob-held fake-network deliveries for `message_then_config` and `config_then_message`, with Alice/Bob stable and Charlie removed. Next action: format, then run the exact GM-034 Flutter direct test.
- 2026-05-11 22:58:22 CEST - Format completed. Files touched since last update: `test/features/groups/integration/group_membership_smoke_test.dart`. Command completed: `dart format test/features/groups/integration/group_membership_smoke_test.dart` exit 0. Command currently running: `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-034"`. Decision/blocker: running regression-first direct test to classify RED/GREEN before production changes. Next action: inspect result and patch production only if RED proves a product gap.
- 2026-05-11 22:58:51 CEST - Flutter GM-034 direct test completed. Files touched since last update: none. Command completed: `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-034"` exit 0. Decision/blocker: host regression is GREEN; no Flutter production patch justified by RED evidence. Next action: inspect `go-mknoon/node/pubsub_delivery_test.go` and add/verify `TestGM034` encrypted PubSub proof.
- 2026-05-11 23:01:15 CEST - Go PubSub proof added. Files inspected/touched since last update: `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/group.go`, Go event helper tests. Command currently running: `gofmt -w go-mknoon/node/pubsub_delivery_test.go`. Decision/blocker: `TestGM034StableMemberDeliverySurvivesUnrelatedConfigUpdateOrders` now covers message/config and config/message order with A/B stable and unrelated Charlie config removal. Next action: format and run required Go direct command.
- 2026-05-11 23:01:36 CEST - Go format completed. Files touched since last update: `go-mknoon/node/pubsub_delivery_test.go`. Command completed: `gofmt -w go-mknoon/node/pubsub_delivery_test.go` exit 0. Command currently running: `(cd go-mknoon && go test ./node -run 'TestGM034|TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription|TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree' -count=1)`. Decision/blocker: running required Go direct proof and adjacent GL-011 coverage. Next action: inspect result and patch Go production only if RED proves a product gap.
- 2026-05-11 23:02:18 CEST - Go direct proof completed. Files touched since last update: none. Command completed: `(cd go-mknoon && go test ./node -run 'TestGM034|TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription|TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree' -count=1)` exit 0. Command currently running: `(cd go-mknoon && go test -race ./node -run 'TestGM034|TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree' -count=1)`. Decision/blocker: Go proof is GREEN; no Go production patch justified. Next action: run required race proof.
- 2026-05-11 23:02:57 CEST - Go race proof completed. Files touched since last update: none. Command completed: `(cd go-mknoon && go test -race ./node -run 'TestGM034|TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree' -count=1)` exit 0. Command currently running: none. Decision/blocker: Go GM-034 proof is GREEN. Next action: inspect/touch GM-034 device criteria, runner, harness, and criteria test support.
- 2026-05-11 23:10:47 CEST - GM-034 device support added and formatted. Files inspected/touched since last update: `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/integration/group_multi_party_device_criteria_test.dart`. Command completed: `dart format integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` exit 0. Command currently running: none. Decision/blocker: runner/criteria/harness now recognize `gm034` as a three-role Alice/Bob/Charlie scenario with Bob order proof fields. Next action: run `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name "GM-034"`.
- 2026-05-11 23:11:11 CEST - GM-034 criteria test started. Files touched since last update: none. Command currently running: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name "GM-034"`. Decision/blocker: validating device verdict criteria before broader host gates. Next action: inspect result and fix only GM-034-attributable criteria/harness gaps.
- 2026-05-11 23:11:24 CEST - GM-034 criteria test completed. Files touched since last update: none. Command completed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name "GM-034"` exit 0. Decision/blocker: criteria tests are GREEN. Next action: run combined member-removal/group-membership host regression command.
- 2026-05-11 23:11:36 CEST - Combined member-removal/group-membership command started. Files touched since last update: none. Command currently running: `flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart`. Decision/blocker: validating GM-034 host coverage alongside adjacent member-removal integration coverage. Next action: inspect result and fix only GM-034-attributable failures.
- 2026-05-11 23:12:08 CEST - Combined member-removal/group-membership command completed. Files touched since last update: none. Command completed: `flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart` exit 0. Decision/blocker: adjacent host regressions are GREEN. Next action: run `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`.
- 2026-05-11 23:12:18 CEST - New-member onboarding command started. Files touched since last update: none. Command currently running: `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`. Decision/blocker: running required adjacent onboarding regression. Next action: inspect result.
- 2026-05-11 23:12:37 CEST - New-member onboarding command completed. Files touched since last update: none. Command completed: `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart` exit 0. Decision/blocker: onboarding regression is GREEN. Next action: run `flutter test test/features/groups/application/group_message_listener_test.dart`.
- 2026-05-11 23:12:46 CEST - Group message listener command started. Files touched since last update: none. Command currently running: `flutter test test/features/groups/application/group_message_listener_test.dart`. Decision/blocker: running required listener regression. Next action: inspect result.
- 2026-05-11 23:13:20 CEST - Group message listener command completed. Files inspected/touched since last update: `git status --short -- test/features/groups/application/group_message_listener_test.dart lib/features/groups/application/group_message_listener.dart ...`; no GM-034 edits made to those files. Command completed: `flutter test test/features/groups/application/group_message_listener_test.dart` exit 1. Decision/blocker: 7 existing listener/idempotence/self-removal failures observed (`GM-014 member_added event time...`, `PREREQ-SIGNED-COMMIT-AUDIT valid signed transition...`, duplicate `member_added`/`members_added` timeline rows, and self-removal notification/leave count assertions). These are not GM-034-attributable because GM-034 touched no listener production/test files and the dirty listener files pre-existed this Executor scope. Next action: do not patch; continue required gates and classify downstream repeats against this blocker.
- 2026-05-11 23:13:37 CEST - Groups gate started. Files touched since last update: none. Command currently running: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`. Decision/blocker: running required named host gate despite prior non-GM-034 listener blocker. Next action: inspect result and classify failures.
- 2026-05-11 23:14:15 CEST - Groups gate completed. Files touched since last update: none. Command completed: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` exit 0. Decision/blocker: named groups gate is GREEN. Next action: run `./scripts/run_test_gates.sh completeness-check`.
- 2026-05-11 23:14:29 CEST - Completeness-check gate started. Files touched since last update: none. Command currently running: `./scripts/run_test_gates.sh completeness-check`. Decision/blocker: running required completeness gate after groups gate. Next action: inspect result.
- 2026-05-11 23:14:47 CEST - Completeness-check gate completed. Files touched since last update: none. Command completed: `./scripts/run_test_gates.sh completeness-check` exit 0. Decision/blocker: completeness check PASS (`732/732 test files classified`). Next action: run live device/process preflight before exact GM-034 three-party proof.
- 2026-05-11 23:15:01 CEST - Device preflight commands started. Files touched since last update: none. Commands currently running: `flutter devices --machine`, `xcrun simctl list devices available`, `pgrep -af 'run_group_multi_party_device_real|flutter drive|dart.*group_multi_party_device_real'`. Decision/blocker: candidate device IDs from the plan are stale until refreshed live. Next action: inspect live devices and active-process evidence.
- 2026-05-11 23:15:36 CEST - Device preflight commands completed. Files touched since last update: none. Commands completed: `flutter devices --machine` exit 0; `xcrun simctl list devices available` exit 0; `pgrep -af 'run_group_multi_party_device_real|flutter drive|dart.*group_multi_party_device_real'` exit 1. Decision/blocker: live Flutter devices include usable booted iOS simulators `560D3E2D-78F8-4D28-A010-16B399581C99`, `511B36DA-7113-41A7-A718-4450C87C0E62`, `DE36DBBE-64FC-4652-AAD9-17329A1BA245`, `A369E083-CFED-40F7-8925-72A088575E38`; no matching active proof/drive process found. Next action: run exact three-party GM-034 proof with Alice/Bob/Charlie on the first three live iOS 26.2 simulators.
- 2026-05-11 23:15:50 CEST - Exact GM-034 three-party proof started. Files touched since last update: none. Command currently running: `MKNOON_RELAY_ADDRESSES='...' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm034 -d 560D3E2D-78F8-4D28-A010-16B399581C99,511B36DA-7113-41A7-A718-4450C87C0E62,DE36DBBE-64FC-4652-AAD9-17329A1BA245`. Decision/blocker: using live Alice/Bob/Charlie iOS simulator tuple and exact relay env. Next action: inspect proof output and classify pass/blocker.
- 2026-05-11 23:18:03 CEST - Exact GM-034 three-party proof still running. Files touched since last update: none. Command currently running: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm034 -d 560D3E2D-78F8-4D28-A010-16B399581C99,511B36DA-7113-41A7-A718-4450C87C0E62,DE36DBBE-64FC-4652-AAD9-17329A1BA245`. Decision/blocker: no harness failure output yet; process check shows active `flutter drive`/build-related processes. Next action: continue waiting for role output or failure.
- 2026-05-11 23:21:36 CEST - Exact GM-034 three-party proof completed. Files touched since last update: none. Command completed: `MKNOON_RELAY_ADDRESSES='...' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm034 -d 560D3E2D-78F8-4D28-A010-16B399581C99,511B36DA-7113-41A7-A718-4450C87C0E62,DE36DBBE-64FC-4652-AAD9-17329A1BA245` exit 0. Decision/blocker: proof passed for Alice, Bob, and Charlie; shared evidence directory `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm034_xoW6M1`. Next action: collect final changed-path and evidence summary for QA handoff.
- 2026-05-11 23:22:23 CEST - Executor evidence collection completed. Files inspected since last update: changed owner-file status, Bob GM-034 verdict proof, GM-034 line anchors. Command completed: `pgrep -af 'run_group_multi_party_device_real|flutter drive|dart.*group_multi_party_device_real'` exit 1. Decision/blocker: no proof process left running; only non-GM-034 blocker remains the pre-existing dirty listener suite failures recorded above. Next action: hand off Executor evidence; do not perform QA Reviewer role.
- 2026-05-11 22:53:00 CEST - Contract extraction started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-034-plan.md`, `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`. Decision/blocker: using `$implementation-execution-qa-orchestrator` with required spawned Executor/QA isolation; repo has broad pre-existing dirty work treated as user/prior-run work. Next action: extract exact GM-034 scope, gates, owner files, and hand off to spawned Executor.
- 2026-05-11 22:53:13 CEST - Contract extraction completed. Files inspected since last update: source matrix GM-034 row, session-breakdown row 49, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, GM runner/criteria/test entry files. Decision/blocker: GM-034 scope is regression-first host proof, Go encrypted PubSub proof, GM-034 3-party criteria/runner/harness support, exact required tests/gates/device proof; source matrix and breakdown ledgers are read-only this execution phase. Next action: spawn Executor with bounded owner files.
- 2026-05-11 22:53:26 CEST - Executor spawned/running. Files inspected since last update: none. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...` for GM-034 Executor. Decision/blocker: no blocker yet; Executor must add host regression first, patch only RED-proven gaps, add Go/device proof support, and record exact evidence here. Next action: wait bounded interval, then inspect assigned-file progress.
- 2026-05-11 22:54:14 CEST - Executor spawn attempt failed before materializing. Files inspected since last update: none. Command currently running: none. Decision/blocker: CLI rejected approval flag placement; no child repo edits or test evidence were produced. Next action: respawn Executor once with corrected top-level Codex CLI approval/sandbox options.
- 2026-05-11 22:54:55 CEST - Executor respawned/running. Files inspected since last update: none. Command currently running: `codex -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -a never exec ...` for GM-034 Executor. Decision/blocker: child materialized with session id `019e18d2-3253-77e2-80e5-33302ff978ef`. Next action: wait bounded interval, then inspect assigned-file progress and Executor result.

## real scope

GM-034 owns exactly this row: while B is receiving direct PubSub traffic, a membership config update also arrives, and a valid A message must not be lost solely because local config timing changed. The execution scope is:

- Add an exact deterministic GM-034 host regression proving the two delivery orders: valid A message then config update, and config update then valid A message.
- Add or verify a real encrypted Go PubSub proof for the same stable-member boundary while `UpdateGroupConfig` changes unrelated membership state.
- Add GM-034 support to the existing 3-party real-device proof runner/harness if no current row-specific device proof exists.
- Apply the smallest product fix only if the regression fails. If the regression passes without product code changes, stop at tests/harness/evidence.

Out of scope: unrelated membership rows, GM-033 acceptance, generic PubSub rewrites, relay architecture, invite UX, notification behavior, broad cleanup, and source matrix or breakdown ledger edits during this planning turn.

## closure bar

GM-034 is closable only when the source matrix row can be marked `Covered` or `Closed` with concrete evidence that:

- B persists exactly one valid A message when the message and membership config update are delivered in both orders.
- B applies the membership timeline/config update deterministically without dropping, duplicating, or misclassifying the valid A message.
- Real encrypted direct PubSub receive validates/decrypts the A message while local config changes unrelated membership.
- A 3-party device/E2E proof exists for GM-034 or the row remains open with an explicit external fixture blocker.

## source of truth

- Primary row contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-034.
- Session contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row 49 / GM-034.
- Execution gates: `Test-Flight-Improv/test-gate-definitions.md`; if it conflicts with gate scripts, `scripts/run_test_gates.sh` wins.
- Current code and tests win over stale prose.

## session classification

`implementation-ready`

Reason: current evidence shows a row-owned gap. Adjacent coverage exists, but no exact GM-034 regression and no `gm034` multi-party device runner support were found.

## exact problem statement

Reported risk: B can lose a valid group message from A when a local membership config update arrives at nearly the same time as direct PubSub receive. User-visible failure is an intermittent missing group message even though A and B remain valid members and the message decrypts/validates under the correct group key and sender identity. The fix must preserve current membership boundary semantics: removed senders stay rejected after their cutoff, stale updates stay stale, and unrelated config updates must not turn valid A traffic into loss.

## files and repos to inspect next

Production and bridge seams:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

Tests and harnesses:

- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_real_crypto_onboarding_test.dart`

## existing tests covering this area

- `group_message_listener.dart` has a per-group `_groupConfigWorkQueue` for system membership events, but normal user messages go through `handleIncomingGroupMessage` outside that queue.
- `handle_incoming_group_message_use_case.dart` checks group existence, sender membership/device binding, removal cutoffs, self removal windows, duplicate message IDs, and then persists the incoming message.
- `go-mknoon/node/pubsub.go` validates incoming PubSub envelopes against the current in-memory `groupConfigs` and decrypts received messages from `groupKeys`.
- `go-mknoon/node/pubsub_delivery_test.go` includes `TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription`, which proves active subscription membership replacement affects C traffic as expected, but it does not prove valid A-to-B traffic survives both config/message delivery orders.
- `go-mknoon/node/pubsub_test.go` includes `TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree`, which covers validator race freedom during config replacement, but not receive persistence/timeline semantics.
- `group_message_listener_test.dart` covers stale add/remove, duplicate system replay, member add/remove config sync, and timeline behavior. It does not stage a valid user message and membership update together in both delivery orders.
- `group_membership_smoke_test.dart` and `group_new_member_onboarding_test.dart` cover many add/remove/re-add boundaries, including add-send boundaries, but no exact GM-034 row proof was found.
- `integration_test/scripts/run_group_multi_party_device_real.dart` and `group_multi_party_device_criteria.dart` currently support `gm001` through `gm025`, `gm033`, and `all`; `gm034` is unsupported.

## regression/tests to add first

Add the exact GM-034 regression before product changes:

1. Host fake-network regression in `test/features/groups/integration/group_membership_smoke_test.dart`.
   - Use `FakeGroupPubSubNetwork.holdDeliveriesFor(bob.peerId)` to stage direct deliveries to B.
   - Use two fresh fixtures/order cases: `message_then_config` and `config_then_message`.
   - A remains admin/sender, B remains receiver, and C/Charlie is the membership-update target.
   - Publish a valid A message and a `member_removed` system config update for Charlie, then release held deliveries in normal and reverse order. Add a `member_added` variant only if it stays in the same test fixture and does not obscure the row-owned removal/update proof.
   - Assert B persists the A message exactly once, applies the membership timeline/config update, and does not emit a loss/empty/drop surrogate.

2. Go encrypted direct PubSub regression in `go-mknoon/node/pubsub_delivery_test.go`.
   - Keep A and B stable members.
   - Change B's local config for an unrelated C membership mutation while A publishes valid encrypted direct PubSub messages.
   - Cover explicit orders and, if stable, a short concurrent publish/update loop.
   - Assert `group_message:received` for every A marker and no validation reject for A.

3. GM-034 device criteria/harness regression.
   - Add `gm034` scenario support to `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_real_harness.dart`, and `group_multi_party_device_criteria_test.dart`.
   - Require three roles: Alice, Bob, Charlie.
   - Bob's verdict must prove both delivery orders, exact message IDs/texts, no duplicates, and deterministic membership timeline/config state.

## step-by-step implementation plan

1. Add the host regression only, run it by exact `--plain-name`, and observe whether current code already satisfies GM-034.
2. If the host regression fails, fix only the failing seam:
   - If B rejects a valid A message after an unrelated config update, inspect `handleIncomingGroupMessage` membership/device binding and the applied config snapshot.
   - If a system update blocks or reorders user persistence incorrectly, adjust only `GroupMessageListener` ordering/state handling needed for GM-034.
   - If duplicate/system replay interferes, preserve current dedupe and stale-boundary behavior while fixing only the valid-message loss.
3. Add the Go encrypted PubSub regression. If it fails, inspect `groupTopicValidator`, `UpdateGroupConfig`, `handleGroupSubscription`, and config/key snapshot lifetimes. Keep any Go fix limited to stable config/key reads or validation boundaries.
4. Add `gm034` support to the real multi-party device proof runner and criteria. Use the same semantic scenario as the host test: A-to-B valid message plus C membership update in both delivery orders.
5. Run direct tests and gates. Fix only regressions attributable to GM-034 changes.
6. After all required proof is green, the execution/closure pass may update the source matrix row to `Covered` or `Closed` with evidence. Do not do that before evidence exists.

Stop early if step 1 and step 2 prove the repo already handles GM-034 and the only gap is proof; in that case the implementation is tests/harness/evidence only.

## risks and edge cases

- Config update removes the sender or receiver: not this row's valid-message proof unless timestamps/cutoffs make the message valid. Keep the main regression on an unrelated third member so A and B remain valid.
- Timestamp/cutoff semantics: use fixed timestamps and assert deterministic boundary behavior.
- Device binding: include sender device/transport IDs in fake-network and Go tests so the proof exercises current device guards.
- Duplicate delivery: assert exactly one persisted A message by `messageId`.
- Stale update interaction: do not weaken GM-011/GM-012/GM-013 style stale and removed-window behavior.
- Go PubSub nondeterminism: avoid broad stress loops as the only proof; keep explicit order cases deterministic.
- Real-device fixture availability: relay env and clean app targets must be present, or the device proof remains externally blocked.

## exact tests and gates to run

Regression-first direct runs:

```bash
flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-034"
(cd go-mknoon && go test ./node -run 'TestGM034|TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription|TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree' -count=1)
(cd go-mknoon && go test -race ./node -run 'TestGM034|TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree' -count=1)
flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name "GM-034"
```

Row-listed and companion tests:

```bash
flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart
flutter test test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
```

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Device proof, after `gm034` runner support exists and relay env is set:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' \
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm034 \
  -d 560D3E2D-78F8-4D28-A010-16B399581C99,511B36DA-7113-41A7-A718-4450C87C0E62,DE36DBBE-64FC-4652-AAD9-17329A1BA245
```

## known-failure interpretation

- Current dirty worktree includes prior and GM-033 changes. Treat them as intentional user/prior-run work and do not revert them.
- GM-033 is currently `blocked/external_fixture`; do not treat GM-033 device proof state as GM-034 evidence.
- `MKNOON_RELAY_ADDRESSES` is currently unset. A GM-034 device proof cannot be accepted until that exact env is supplied.
- `run_group_multi_party_device_real.dart --scenario gm034` is currently expected to fail as unsupported. That is a GM-034 implementation gap, not an external fixture failure.
- If real-device runs fail because relay env is missing or selected devices are not clean/distinct, classify as external fixture until the fixture is corrected.
- Existing documented macOS integration startup failures for posts phase 2-5 are unrelated unless GM-034 changes touch those files, which this plan forbids.

## done criteria

- Exact GM-034 host regression exists and passes for both delivery orders.
- Exact encrypted Go PubSub regression exists and passes, including the race-oriented run where required.
- GM-034 multi-party device runner support exists, criteria tests pass, and a 3-party device proof either passes or is explicitly recorded as externally blocked by relay/fixture with no product-code ambiguity.
- Row-listed direct Flutter tests and group gate commands pass or have pre-existing unrelated failures documented.
- No product code outside the GM-034 seams is changed.
- Source matrix GM-034 is not accepted until evidence supports `Covered` or `Closed`.

## scope guard

Do not:

- Reopen GM-001 through GM-033.
- Convert this into a generic message ordering subsystem rewrite.
- Change relay storage, inbox repair, notifications, invite policy, or UI surfaces.
- Weaken removed-member rejection, stale membership watermarks, group dissolution, duplicate message dedupe, or device binding.
- Update source matrix or breakdown ledgers in this planning-only pass.

Overengineering would be introducing a global event sequencer, broad transaction layer, or cross-feature ordering abstraction before the exact GM-034 regression proves a need.

## accepted differences / intentionally out of scope

- Host fake-network tests prove deterministic listener/repository behavior but not cryptography; Go and device proofs cover validation/decryption.
- Go local-node tests prove encrypted PubSub behavior without Flutter UI; device proof covers Flutter app orchestration.
- GM-034 does not require changing behavior for messages sent by a removed sender after cutoff.
- GM-033 remains intentionally separate and blocked by its own external fixture status.

## dependency impact

- Later GM closure work can reuse the GM-034 device scenario pattern, but this session should not generalize beyond GM-034.
- If GM-034 requires a product fix in shared listener or Go PubSub validation, rerun adjacent membership rows and the group gate because GM-011 through GM-018 can be affected.
- If GM-034 runner support is added, update criteria tests and completeness classification as needed; if runner support is deferred, GM-034 must stay open.

## Device/Relay Proof Profile

Live planning refresh, 2026-05-11 CEST:

- `flutter devices --machine` reported usable targets including `Pixel 6` (`21071FDF600CSC`), Android emulator `emulator-5554`, connected iPhone `00008030-001A6D2801BB802E`, booted iOS simulators `560D3E2D-78F8-4D28-A010-16B399581C99`, `511B36DA-7113-41A7-A718-4450C87C0E62`, `DE36DBBE-64FC-4652-AAD9-17329A1BA245`, `A369E083-CFED-40F7-8925-72A088575E38`, and additional iOS 26.1 booted simulators.
- `xcrun simctl list devices available` confirmed booted iOS simulators: `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `1B098DFF-6294-407A-A209-BBF360893485`, `560D3E2D-78F8-4D28-A010-16B399581C99`, `511B36DA-7113-41A7-A718-4450C87C0E62`, `DE36DBBE-64FC-4652-AAD9-17329A1BA245`, `A369E083-CFED-40F7-8925-72A088575E38`.
- Process check for active `run_group_multi_party_device_real` or `flutter drive` jobs returned no matches. No current process contention was observed; future contention from matching active jobs should be treated as external unless the GM-034 executor started it.
- `MKNOON_RELAY_ADDRESSES` is currently unset. The exact app relay profile required by `group_multi_party_device_criteria.dart` must be supplied before real device proof can run.
- Current GM multi-party runner does not support `gm034`; device proof is not currently runnable for GM-034 even though enough distinct devices are available.
- Candidate clean 3-party iOS simulator set after runner support and relay env are available: Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`.
- Clean-fixture requirement: use distinct Flutter app targets, no active `flutter drive`/GM runner processes, fresh runner `runId`, and per-role DB names generated by `E2E_DB_NAME=group_multi_party_gm034_<runId>_<role>.db`.

## reviewer findings

Reviewer verdict: sufficient with adjustment.

- Missing files/tests/gates: none structurally missing after adding explicit GM-034 device harness support and exact Go/Flutter regressions.
- Stale assumptions: the plan correctly treats current `gm034` device support as absent; it does not assume device proof is runnable today.
- Overengineering: no broad subsystem rewrite is planned. The only risk was ambiguous `member_removed or member_added` wording, tightened to canonical third-party `member_removed`.
- Decomposition: sufficient. Regression-first host proof, Go encrypted proof, then 3-party device proof keeps executor scope bounded.
- Minimum needed for sufficiency: keep A and B stable members, mutate Charlie membership, prove both delivery orders, and do not mark GM-034 covered until concrete evidence exists.

## arbiter decision

Arbiter verdict: execution-ready.

Structural blockers:

- None remaining.

Incremental details:

- Exact helper names inside `group_multi_party_device_real_harness.dart` can be chosen during execution, as long as the GM-034 scenario and criteria prove Bob's two order cases.
- A `member_added` companion variant is optional and must not replace the canonical `member_removed` proof.

Accepted differences:

- Device proof is not currently runnable because `gm034` runner support is absent and `MKNOON_RELAY_ADDRESSES` is unset. This is documented as a current fixture/implementation precondition, not closure evidence.
- Host fake-network proof, Go PubSub proof, and device proof are intentionally complementary rather than interchangeable.

## Recovery Plan - Listener Gate Blocker

Planning status: `execution-ready` for one same-session recovery pass.

Planner timestamp: 2026-05-11 23:36 CEST.

Evidence inspected:

- Current failing gate: `flutter test test/features/groups/application/group_message_listener_test.dart --reporter expanded` exits 1.
- Failing signatures are the expected recovery-input signatures: GM-014 explicit remove/re-add timing, signed member-add audit application/idempotence, duplicate `member_added` UI emission, self-removal visible-message counts, post-self-removal notification count, and duplicate `members_added` timeline/updateConfig replay.
- Owner seams inspected: `GroupMessageListener._handleSystemMessage`, `_resolveIncomingMembershipVersion`, `_shouldIgnoreStaleMembershipEvent`, `_shouldIgnoreStaleMemberRemovedEvent`, `_handleMemberAdded`, `_handleMembersAdded`, `_handleMemberRemoved`, `_saveTimelineMessagePreservingReadState`, `_applyAuthoritativeGroupConfigSnapshot`, and `InMemoryGroupMessageRepository` visible-message helpers/count.

Recovery classification: `implementation-ready` / `repo_owned_required_gate_blocker`.

Real scope:

- Fix only the required listener gate blocker that prevents GM-034 closure.
- Production owner file: `lib/features/groups/application/group_message_listener.dart`.
- Test-fake owner file: `test/shared/fakes/in_memory_group_message_repository.dart`.
- Proof owner file: `test/features/groups/application/group_message_listener_test.dart` only if an assertion needs to name the corrected behavior more explicitly; do not weaken existing expectations to make the gate pass.
- Do not touch GM-034 device runner, Go PubSub proof, source matrix rows, session-breakdown ledgers, relay fixtures, or unrelated group/chat behavior in this recovery pass.

Closure bar:

- The exact required gate `flutter test test/features/groups/application/group_message_listener_test.dart --reporter expanded` exits 0.
- Focused failing selectors pass individually before the full listener gate.
- The fix preserves GM-034 row-owned proof already collected and does not reopen GM-033 device acceptance.
- No source matrix or breakdown acceptance update happens in this recovery pass; closure remains a later pipeline phase after this blocker is green.

Behavioral fixes to implement:

1. Preserve explicit membership event timestamps over stale default config versions.
   - Replace the current resolver behavior where `groupConfig.configVersion` always overrides `member_removed.removedAt` or `member_added`/`members_added.eventAt`.
   - For membership event rows with an explicit transition timestamp, use that explicit timestamp for stale checks, member `joinedAt`, removal cutoffs, timeline IDs, and `lastMembershipEventAt`.
   - Keep `groupConfig.configVersion` authoritative only when the event lacks an explicit transition timestamp or when implementing a true versioned config replay where no stronger event-specific timestamp exists.

2. Do not reject the first valid signed membership add from inferred legacy watermarks.
   - When `GroupModel.lastMembershipEventAt` is null, do not let inferred values from group creation, existing member `joinedAt`, latest key time, or legacy/default `configVersion` suppress a valid signed `member_added` before any real persisted membership watermark exists.
   - After the signed add is accepted, record its explicit event time as the membership watermark and keep the tampered replay rejection path unchanged.

3. Make duplicate `member_added` and `members_added` replays idempotent.
   - Equal-version duplicate replays must not re-run `_syncGroupConfig`, must not save/emit a second timeline event, and must not append duplicate event-log entries.
   - Preserve canonical member state after the first application.
   - Keep legitimate newer membership events applying, stale older events rejected, and same-version conflict/tamper detection intact.
   - Prefer a small idempotence guard near the stale-check/source-event/timeline boundary over broad queue or repository rewrites.

4. Keep hidden self-removal cutoff markers hidden from visible-message counts.
   - The cutoff marker written by self-removal must remain retrievable by `getMessage` and usable by `getLatestRemovalTimestampForSender`.
   - It must not count as a visible message in in-memory test helpers such as `count`, `getMessageCount`, latest-message, page, unread, thread summary, or content-existence helpers.
   - The real repository behavior should not be changed unless focused evidence shows the production repository exposes the marker visibly.

Focused tests to run first:

```bash
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "GM-014 member_added event time becomes Charlie re-add joinedAt and removed-window sender traffic stays rejected"
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "PREREQ-SIGNED-COMMIT-AUDIT valid signed transition applies live and duplicate replay is idempotent while tampered replay is blocked"
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "duplicate member_added keeps one canonical member state and one UI stream event"
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "self-removal calls leaveGroup and emits on groupRemovedStream"
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "duplicate self-removal emits one removal signal and leaves once"
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "does not notify after self-removal deletes the group"
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "duplicate members_added keeps one timeline row and member set"
```

Full recovery proof and adjacent guardrails:

```bash
flutter test test/features/groups/application/group_message_listener_test.dart --reporter expanded
flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart
flutter test test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-034"
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

Risks and edge cases:

- Timestamp precedence must not weaken GM-011/GM-012/GM-013 stale and removed-window semantics.
- Removing equal replay side effects must not block crash-recovery cases where the first event was not actually applied; if needed, key idempotence from deterministic timeline/source-event existence rather than timestamp alone.
- Hidden cutoff filtering must not hide real `sys-member_removed` timeline rows; only `groupRemovalCutoffMessageIdPrefix` markers are invisible.
- Signed audit duplicate/tamper behavior must remain strict: exact duplicate is idempotent, changed replay is rejected before mutation.

Known-failure interpretation:

- Treat the listener gate as repo-owned until a narrower non-repo blocker is proven. Do not reclassify these failures as external/pre-existing merely because GM-034 did not originally touch the listener files.
- If an additional listener failure appears after these fixes, isolate it with a focused selector and classify whether it is caused by the recovery patch before touching unrelated behavior.

Done criteria:

- All seven reproduced failing signatures are green.
- Full `group_message_listener_test.dart` is green.
- Adjacent membership/onboarding/GM-034 host and groups gate commands are green or any remaining failure is proven unrelated with exact command output and file ownership.
- GM-034 remained `blocked_not_accepted` only until the later closure phase could update the source matrix and breakdown with the recovered listener-gate evidence.

Reviewer/arbiter decision:

- Reviewer verdict: sufficient. The plan names exact owner files, exact failure signatures, a narrow behavioral contract, and focused proof commands.
- Arbiter verdict: no structural blockers. Proceed to a fresh implementation/QA recovery pass; do not broaden into GM-034 row proof, device proof, source matrix closure, or unrelated listener cleanup.

## Recovery Executor Final Verdict - 2026-05-11 23:48:42 CEST

Verdict: executor recovery implementation complete; ready for separate QA Reviewer. No executor blocker remains.

Files touched by this recovery pass:

- `lib/features/groups/application/group_message_listener.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-034-plan.md`

Files intentionally not edited by this recovery pass:

- `test/features/groups/application/group_message_listener_test.dart` remained pre-existing dirty/prior-run work; assertions were not weakened.
- Source matrix, session-breakdown ledger, Go PubSub files, device harness/runner/criteria files, and unrelated UI/network files were not edited.

Implemented behavior:

- Explicit `member_removed.removedAt` and `member_added`/`members_added.eventAt` now win over stale/default config versions for membership event ordering, joinedAt, cutoffs, timeline IDs, and watermark.
- Verified signed add audit `eventAt` is used as the membership event time when signed `member_added`/`members_added` payloads omit container `eventAt`, so the first valid signed add is not suppressed by inferred legacy/default watermarks.
- Exact duplicate `member_added`/`members_added` replays are idempotent by deterministic timeline existence before event-log append, `_syncGroupConfig`, timeline save, or stream emission.
- True versioned config replays remain strict when `groupConfig.configVersion` is the event version itself, preserving GM-029 stale-order behavior.
- Hidden self-removal cutoff markers remain retrievable by `getMessage` and usable by `getLatestRemovalTimestampForSender`, while in-memory visible count/page/latest/unread/thread summary/content-existence helpers hide them.

Exact commands/results:

- `dart format lib/features/groups/application/group_message_listener.dart test/shared/fakes/in_memory_group_message_repository.dart` exit 0.
- `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "GM-014 member_added event time becomes Charlie re-add joinedAt and removed-window sender traffic stays rejected"` exit 0.
- `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "PREREQ-SIGNED-COMMIT-AUDIT valid signed transition applies live and duplicate replay is idempotent while tampered replay is blocked"` first retry exit 1 (`peer-audit-new` null), after signed audit event-time fix exit 0.
- `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "duplicate member_added keeps one canonical member state and one UI stream event"` exit 0.
- `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "self-removal calls leaveGroup and emits on groupRemovedStream"` exit 0.
- `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "duplicate self-removal emits one removal signal and leaves once"` exit 0.
- `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "does not notify after self-removal deletes the group"` exit 0.
- `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "duplicate members_added keeps one timeline row and member set"` exit 0.
- `flutter test test/features/groups/application/group_message_listener_test.dart --reporter expanded` first retry exit 1 on `GM-029 older versioned config snapshots are ignored after newer version and same-version replay is idempotent`; triaged as recovery-caused by treating explicit `removedAt` as stronger than matching true `configVersion`.
- `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "GM-029 older versioned config snapshots are ignored after newer version and same-version replay is idempotent"` exit 0 after resolver correction.
- `flutter test test/features/groups/application/group_message_listener_test.dart --reporter expanded` exit 0, `105` tests passed.
- `flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart` exit 0, `68` tests passed.
- `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart` exit 0, `7` tests passed.
- `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-034"` exit 0, `1` test passed.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` exit 0, `134` tests passed.

Blocking issues remaining: none for the Executor recovery scope. The earlier `blocked_not_accepted` state is superseded by the Recovery Executor and QA Reviewer evidence and by the closure-phase source matrix/breakdown updates.

## Recovery QA Reviewer Result - 2026-05-11 23:52:15 CEST

Verdict: `qa_passed`.

Files inspected:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-034-plan.md`
- `lib/features/groups/application/group_message_listener.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/features/groups/application/group_message_listener_test.dart` as proof context only
- `test/features/groups/integration/group_membership_smoke_test.dart` as proof context only

Diff/behavior review:

- Timestamp precedence is narrow: explicit `member_removed.removedAt` and `member_added`/`members_added.eventAt` feed membership stale checks, timeline IDs, joinedAt/cutoffs, and watermarking, while true matching config-version replays remain strict.
- Signed audit behavior remains strict: accepted same-hash replay returns before mutation, changed replay is rejected, and signed add audit `eventAt` is used only when the container lacks an explicit event timestamp.
- Duplicate `member_added`/`members_added` replay handling is limited to deterministic timeline-existence idempotence before event-log append, config sync, timeline save, or stream emission.
- Hidden self-removal cutoff markers remain retrievable through `getMessage` and `getLatestRemovalTimestampForSender`, but are excluded from in-memory visible page/latest/count/unread/thread summary/content-existence helpers.

Commands/results:

- `flutter test test/features/groups/application/group_message_listener_test.dart --reporter expanded` exit 0, `105` tests passed.
- `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "GM-029 older versioned config snapshots are ignored after newer version and same-version replay is idempotent"` exit 0, `1` test passed.
- `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-034"` exit 0, `1` test passed.

Blocking findings: none. This QA pass does not update the source matrix or session-breakdown closure ledger.

## Closure Writer Result - 2026-05-11 23:58:00 CEST

Verdict: `accepted/closed`.

The earlier listener blocker is superseded by the recovery Executor plus QA pass. Current closure evidence includes the GM-034 host fake-network proof, Go direct and race proof, GM-034 criteria proof, exact three-party device proof, recovered listener suite (`105` passed), GM-029 selector pass, member-removal plus membership smoke (`68` passed), onboarding (`7` passed), groups gate (`134` passed), and completeness-check (`732/732` classified). Residual-only items for GM-034: none.
