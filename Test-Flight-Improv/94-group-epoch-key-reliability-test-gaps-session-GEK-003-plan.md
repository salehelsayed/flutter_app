# GEK-003 Partial Key-Update Rotation Race and Immediate Send Recovery Plan

Status: execution-ready

## Planning Progress

- `2026-05-09 22:29:48 CEST` - Role: Arbiter completed. Files inspected since last update: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-003-plan.md`. Decision/blocker: no structural blockers remain; reviewer adjustments are incorporated, the Device/Relay Proof Profile is present, and the plan is reusable for execution. Next action: stop planning for GEK-003 and hand this artifact to execution.
- `2026-05-09 22:29:21 CEST` - Role: Reviewer completed; Arbiter started. Files inspected since last update: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-003-plan.md`. Decision/blocker: reviewer classified the plan as sufficient with adjustments; patched the regression to require current-key recipient control and drain-backed durable replay proof. Next action: arbiter will classify remaining findings and decide whether the plan can move to execution-ready.
- `2026-05-09 22:28:28 CEST` - Role: Planner completed; Reviewer started. Files inspected since last update: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-003-plan.md`. Decision/blocker: draft plan written with all mandatory sections and a Device/Relay Proof Profile; reviewer is checking whether the direct regression proves current-key and stale-recipient outcomes tightly enough. Next action: patch any structural sufficiency gaps, then hand off to Arbiter.
- `2026-05-09 22:24:02 CEST` - Role: Evidence Collector completed; Planner started. Files inspected since last update: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/14-regression-test-strategy.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `test/shared/fakes/group_test_user.dart`, `test/core/bridge/fake_bridge.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`. Decision/blocker: no planning blocker; GEK-003 remains a missing combined host/live-equivalent race proof distinct from GEK-001 and GEK-002, with simulator/relay proof still residual unless device fixtures exist. Next action: draft mandatory plan sections, including a Device/Relay Proof Profile.
- `2026-05-09 22:22:06 CEST` - Role: Evidence Collector started. Files inspected since last update: `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`, `git status --short`, intended GEK-003 plan path existence check. Decision/blocker: source session and intended plan path confirmed; no existing GEK-003 plan artifact was present. Next action: inspect the breakdown/source docs, regression gate docs, and direct group epoch-key code/tests for GEK-003 evidence.

## Execution Progress

- `2026-05-09 22:31:51 CEST` - Phase: contract extraction started. Files inspected or touched: this plan, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`, `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`, `git status --short`, `codex --help`, `codex exec --help`. Command currently running: none. Decision/blocker: plan is execution-ready and scoped; spawned-agent capability is available through `codex exec` and must be validated for the required Executor then QA sequence. Next action: finish contract extraction, then spawn a fresh Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- `2026-05-09 22:32:58 CEST` - Phase: contract extracted. Files inspected or touched: this plan and orientation-only breakdown. Command currently running: none. Decision/blocker: execute exactly GEK-003; add the focused regression in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` first; production edits are allowed only for a proven failing seam; required direct selectors, `./scripts/run_test_gates.sh groups`, and `git diff --check` must be recorded; GEK-004 membership/config propagation and GEK-005 final relay acceptance are non-goals. Next action: spawn Executor.
- `2026-05-09 22:33:12 CEST` - Phase: Executor spawned/running. Files inspected or touched: this plan. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -a never -C /Users/I560101/Project-Sat/mknoon-2/flutter_app ...`. Decision/blocker: fresh Executor will add/run the GEK-003 focused regression first, stop on green test-only evidence, or patch only a proven failing seam. Next action: wait for Executor completion and inspect landed evidence.
- `2026-05-09 22:34:09 CEST` - Phase: Executor spawn retry needed after tool invocation failure. Files inspected or touched: this plan. Command currently running: none. Decision/blocker: first `codex exec` attempt exited before child materialization because this CLI rejected `-a never`; no Executor code/test/doc work started, so this is a spawn invocation issue rather than a GEK-003 implementation blocker. Next action: retry fresh Executor spawn with `approval_policy` supplied through `-c` config.
- `2026-05-09 22:34:36 CEST` - Phase: Executor retry spawned/running. Files inspected or touched: this plan. Command currently running: `codex -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -a never -C /Users/I560101/Project-Sat/mknoon-2/flutter_app exec ...`. Decision/blocker: corrected global CLI option placement validated with `codex ... exec --help`; retrying fresh Executor. Next action: wait for Executor completion and inspect landed evidence.
- `2026-05-09 22:35:40 CEST` - Phase: Executor owner-file inspection started. Files inspected or touched: this plan, orientation-only breakdown, `git status --short`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command currently running: none. Decision/blocker: worktree is dirty before this Executor pass; owner test has pre-existing GEK-002 edits and no GEK-003 regression yet. Next action: inspect only GEK-003-relevant owner APIs/helpers before adding the focused regression.
- `2026-05-09 22:38:23 CEST` - Phase: Executor owner-file inspection completed. Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `test/core/bridge/fake_bridge.dart`, `test/shared/fakes/in_memory_group_repository.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`. Command currently running: none. Decision/blocker: GEK-003 can be expressed as a test-only three-context host regression using real rotate, direct key-update listener, send, inbox replay, live diagnostic, and pending-key repair wiring. Next action: edit the owner test only.
- `2026-05-09 22:41:39 CEST` - Phase: Executor implementation decision completed. Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, this plan. Command currently running: none. Decision/blocker: added the required focused GEK-003 regression and formatted the owner test; no production files touched by this Executor pass. Next action: run the focused GEK-003 selector.
- `2026-05-09 22:41:56 CEST` - Phase: focused GEK-003 regression started. Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command currently running: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival'`. Decision/blocker: none. Next action: triage the selector result before any production edit.
- `2026-05-09 22:42:32 CEST` - Phase: focused GEK-003 regression failed and triaged. Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`. Command currently running: none. Decision/blocker: failure class is a proven GEK-003 pending-repair identity seam, not GEK-004 membership/config; missing-key durable replay queued the pending row with relay `from`/transport identity `device-bob` as `senderPeerId` instead of the signed replay account sender `peer-bob`, preventing live diagnostic supersede by real sender. Next action: patch only the pending-key repair queue identity mapping.
- `2026-05-09 22:43:26 CEST` - Phase: Executor production patch completed. Files inspected or touched: `lib/features/groups/application/group_pending_key_repair_service.dart`. Command currently running: none. Decision/blocker: pending-key repair queue now derives account sender and transport identity from the signed replay envelope before falling back to relay `from`; production scope stayed within the proven GEK-003 seam. Next action: rerun the focused GEK-003 selector.
- `2026-05-09 22:43:44 CEST` - Phase: focused GEK-003 regression rerun started. Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`. Command currently running: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival'`. Decision/blocker: none. Next action: record pass/fail and continue only if green.
- `2026-05-09 22:44:18 CEST` - Phase: focused GEK-003 regression finished. Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`. Command currently running: none. Decision/blocker: passed after the pending-repair identity patch. Next action: run required focused safety selectors.
- `2026-05-09 22:44:35 CEST` - Phase: safety selector started. Files inspected or touched: `test/features/groups/application/group_key_update_listener_test.dart`. Command currently running: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'send during pending key update uses old epoch until local update commits'`. Decision/blocker: none. Next action: record result.
- `2026-05-09 22:44:56 CEST` - Phase: safety selector finished. Files inspected or touched: `test/features/groups/application/group_key_update_listener_test.dart`. Command currently running: none. Decision/blocker: passed `send during pending key update uses old epoch until local update commits`. Next action: run next safety selector.
- `2026-05-09 22:44:56 CEST` - Phase: safety selector started. Files inspected or touched: `test/features/groups/application/group_key_update_listener_test.dart`. Command currently running: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'delayed older key update after newer generation does not promote active key'`. Decision/blocker: none. Next action: record result.
- `2026-05-09 22:45:18 CEST` - Phase: safety selector finished. Files inspected or touched: `test/features/groups/application/group_key_update_listener_test.dart`. Command currently running: none. Decision/blocker: passed `delayed older key update after newer generation does not promote active key`. Next action: run next safety selector.
- `2026-05-09 22:45:18 CEST` - Phase: safety selector started. Files inspected or touched: `test/features/groups/application/group_key_update_listener_test.dart`. Command currently running: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'conflicting same-generation key updates keep first accepted material'`. Decision/blocker: none. Next action: record result.
- `2026-05-09 22:45:38 CEST` - Phase: safety selector finished. Files inspected or touched: `test/features/groups/application/group_key_update_listener_test.dart`. Command currently running: none. Decision/blocker: passed `conflicting same-generation key updates keep first accepted material`. Next action: run send epoch-binding safety selector.
- `2026-05-09 22:45:38 CEST` - Phase: safety selector started. Files inspected or touched: `test/features/groups/application/send_group_message_use_case_test.dart`. Command currently running: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'messages before during and after rotation bind to the locally committed epoch'`. Decision/blocker: none. Next action: record result.
- `2026-05-09 22:46:01 CEST` - Phase: safety selector finished. Files inspected or touched: `test/features/groups/application/send_group_message_use_case_test.dart`. Command currently running: none. Decision/blocker: passed `messages before during and after rotation bind to the locally committed epoch`. Next action: run GEK-002 repair safety selector.
- `2026-05-09 22:46:01 CEST` - Phase: safety selector started. Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command currently running: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival'`. Decision/blocker: none. Next action: record result.
- `2026-05-09 22:46:25 CEST` - Phase: safety selector finished. Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command currently running: none. Decision/blocker: passed `GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival`. Next action: run named `groups` gate.
- `2026-05-09 22:46:38 CEST` - Phase: named gate started. Files inspected or touched: group test surfaces. Command currently running: `./scripts/run_test_gates.sh groups`. Decision/blocker: none. Next action: record gate result.
- `2026-05-09 22:47:17 CEST` - Phase: named gate finished. Files inspected or touched: group test surfaces. Command currently running: none. Decision/blocker: `./scripts/run_test_gates.sh groups` passed (`All tests passed`, 103 tests). Next action: run `git diff --check`.
- `2026-05-09 22:47:29 CEST` - Phase: hygiene check started. Files inspected or touched: worktree diff. Command currently running: `git diff --check`. Decision/blocker: none. Next action: record hygiene result.
- `2026-05-09 22:47:52 CEST` - Phase: hygiene check finished and Executor completed. Files inspected or touched: this plan, `lib/features/groups/application/group_pending_key_repair_service.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, worktree diff/status. Command currently running: none. Decision/blocker: `git diff --check` passed; no conditional owner/direct suites were required because this pass did not touch `rotate_and_distribute_group_key_use_case.dart` or `group_message_listener.dart`; completeness check was skipped because no `_test.dart` file was added, removed, or renamed. Next action: hand off to QA Reviewer.
- `2026-05-09 22:50:15 CEST` - Phase: QA Reviewer preparation. Files inspected or touched: this plan, `/tmp/gek003-executor-last.md` handoff status, `git status --short`. Command currently running: none. Decision/blocker: Executor completed the GEK-003 implementation and all required focused selectors/gates; no blocker is present, and the next required workflow step is a fresh QA Reviewer before any final verdict. Next action: spawn the QA Reviewer with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- `2026-05-09 22:50:59 CEST` - Phase: QA Reviewer spawned/running. Files inspected or touched: this plan. Command currently running: `codex -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -a never -C /Users/I560101/Project-Sat/mknoon-2/flutter_app exec -o /tmp/gek003-qa-last.md ...` (session `019e0e81-de38-7841-a73f-6a698306205a`). Decision/blocker: no blocker; QA Reviewer is reviewing Executor scope, diff, and evidence without making fixes. Next action: wait for QA result, then either run a bounded fix loop for blocking findings or write the final QA/final verdict entries.
- `2026-05-09 22:53:03 CEST` - Phase: QA Reviewer completed. Files inspected or touched: this plan, `/tmp/gek003-qa-last.md`, `/tmp/gek003-executor-last.md`, `git status --short`, scoped GEK-003 diff. Command currently running: none. Decision/blocker: QA verdict `pass`; blocking issues `None`; non-blocking follow-ups `None`; fix pass needed `no`. QA independently reran the GEK-003 focused selector and `git diff --check`, both passed, and confirmed the patch stayed in GEK-003 scope without GEK-004 or GEK-005 implementation. Next action: perform final controller QA and write final verdict.
- `2026-05-09 22:53:24 CEST` - Phase: final QA completed. Files inspected or touched: this plan, final `git status --short`, final worktree diff whitespace check. Command currently running: none. Decision/blocker: final controller QA found no blockers; `git diff --check` passed; dirty worktree still contains unrelated pre-existing changes alongside the GEK-003 files. Next action: write final execution verdict.
- `2026-05-09 22:53:24 CEST` - Phase: final verdict. Files inspected or touched: this plan, `lib/features/groups/application/group_pending_key_repair_service.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `/tmp/gek003-executor-last.md`, `/tmp/gek003-qa-last.md`. Command currently running: none. Decision/blocker: verdict `accepted`; GEK-003 focused regression passes, required safety selectors and `./scripts/run_test_gates.sh groups` passed, QA passed, no fix loop was needed, and no blockers remain. Next action: report the final execution verdict to the user.

## real scope

GEK-003 owns one narrow reliability proof and only the fixes required by that proof:

- A rotating member generates epoch `N+1` and direct key-update delivery reaches one eligible recipient but not another.
- The updated recipient sends a normal group message immediately after its local key-update commit, so the outgoing row and replay envelope are bound to epoch `N+1`.
- The stale recipient does not silently lose that message. It must either keep an explicit pending-key or undecryptable state tied to the real message, or repair the durable replay after the missing key update later arrives.
- Existing sender-side epoch snapshotting must remain intact.
- Removed-member exclusion and key-conflict monotonicity from GEK-001 must not weaken.
- GEK-002 durable replay convergence must remain the repair contract for missing-key messages.

Expected implementation is test-first. Production edits are allowed only if the focused GEK-003 regression proves a real gap in the existing partial-delivery/send/repair chain. If the regression passes without production edits, stop and record GEK-003 as evidence-covered during execution/closure rather than inventing a behavior change.

Out of scope for this session:

- GEK-004 delayed membership/config propagation, newly added sender eligibility truth, invite delivery truth, or config catch-up.
- GEK-005 final simulator/relay reconciliation and final program verdict.
- New group receipt semantics, per-recipient ACKs, MLS commit protocol work, account/device registry redesign, or new product UI.
- Fixing the GEK-002 explicit follow-up for old `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date fixtures unless the GEK-003 evidence directly touches receipt/retention semantics.

## closure bar

GEK-003 is good enough when a deterministic app-layer three-actor proof shows all of the following in one focused regression:

- Alice/admin rotates from epoch 1 to epoch 2 and direct key-update distribution is partial: Bob receives and commits epoch 2 while Charlie remains on epoch 1.
- Bob sends immediately after Bob's local epoch-2 commit. Bob's outgoing `GroupMessage.keyGeneration`, durable replay envelope `keyEpoch`, and persisted send state stay epoch 2.
- Charlie's live-path failure is represented by `group:decryption_failed` or an equivalent receive-side missing-key signal, and it creates a visible pending-key state instead of a delivered plaintext row or disappearance.
- Charlie's durable replay for the same Bob message becomes the canonical real `messageId`, superseding any synthetic live placeholder as GEK-002 requires.
- When Charlie later receives the same epoch-2 key update, pending repair retries and the Bob message becomes one visible delivered plaintext row with the original message id, sender, transport identity, text, and epoch.
- Duplicate replay or retry does not create a second row.
- Alice/current-key recipients are not regressed by the partial failure setup.
- Removed/non-member recipients are not added to the key update, inbox, or delivery target set.

Named gates and focused tests must pass or have documented pre-existing failures that are outside GEK-003.

## source of truth

Priority order for disagreements:

1. Current production code and direct tests in this workspace.
2. `Test-Flight-Improv/test-gate-definitions.md` for named gate membership and command source of truth.
3. `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md` for GEK-003 scope, dependency state, and session boundaries.
4. `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md` for the report-level symptom and acceptance gap.
5. `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` for current covered/open classification and closure language.
6. `Test-Flight-Improv/14-regression-test-strategy.md` for broader regression strategy when named gates do not answer a direct command question.

Current evidence says GEK-001 and GEK-002 are already accepted for their own slices. This plan must not reinterpret those sessions as open unless code evidence proves a regression in their contracts.

## session classification

`implementation-ready`

Reason: the source breakdown marks GEK-003 as implementation-ready, and repo evidence identifies a missing combined partial-recipient rotation/send/repair proof. The work may land as a focused test-only evidence session if existing GEK-001 and GEK-002 behavior already satisfy the combined race.

## exact problem statement

The remaining GEK-003 risk is that a partially delivered epoch-key update can split eligible recipients during a rotation boundary. One recipient may commit the new key and send immediately on epoch 2 while another eligible recipient is still on epoch 1. Without a combined proof, that stale recipient could permanently miss the message, get a fake delivered row, or fail to converge from pending repair to plaintext after the key arrives.

User-visible behavior that must improve or be proven:

- The stale recipient must see either a recoverable pending-key state or a repaired delivered message, not a silent absence.
- Once the missing key arrives, the stale recipient must converge to exactly one visible message if durable replay exists.
- Current-key recipients and senders must keep the existing epoch snapshot and dedupe behavior.

Behavior that must stay unchanged:

- Sends still snapshot the latest locally committed key at send time.
- Direct key updates remain monotonic and reject same-generation conflicts as GEK-001 established.
- Live diagnostic plus durable replay convergence remains the GEK-002 contract.
- Group `sent` status remains the current receipt-less group send status; GEK-003 must not add per-recipient ACK semantics.

## files and repos to inspect next

Production files:

- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_pending_key_repair_service.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/main.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`

Direct tests and fakes:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/core/bridge/fake_bridge.dart`

Go/native files should be inspected only if the focused regression indicates a Go active-key or pubsub diagnostic boundary issue:

- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`

## existing tests covering this area

Already covered:

- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` proves key generation, per-recipient direct key-update distribution, partial distribution continuation, timeout behavior, admin promotion after distribution/timeout, and key-rotated system publish ordering.
- `test/features/groups/application/send_group_message_use_case_test.dart` under `MS-018: key rotation epoch binding` proves send-time epoch snapshots and before/during/after rotation sends bind to epochs `1/1/2`.
- `test/features/groups/application/group_key_update_listener_test.dart` proves pending key-update sends keep the old epoch until local update commit, sequential epoch updates, delayed older updates, same-generation conflicts, duplicates, and bridge update failure behavior.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` proves missing future-epoch replay creates a safe pending repair when a pending repo is wired, and GEK-002 proves live decrypt diagnostic plus durable replay plus later key arrival repairs to one visible row.
- `test/features/groups/integration/group_messaging_smoke_test.dart` has `MS018 rotation race preserves message epochs under out-of-order live delivery`, which covers fake-network out-of-order epochs but not real or equivalent stale-key decrypt failure.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go` proves Go active-key monotonicity and previous-epoch grace behavior.
- `lib/main.dart` wires `groupDiagnosticEvents`, `GroupPendingKeyRepairRunner`, and `GroupKeyUpdateListener.retryPendingGroupKeyRepairs`, so production has an intended route from live diagnostic to durable repair to key-arrival retry.

Missing:

- No current test proves partial key-update delivery plus immediate new-epoch send plus stale-recipient live/durable recovery in one scenario.
- Existing fake-network delivery persists plaintext by `keyEpoch` and does not itself simulate cryptographic decrypt failure for stale recipients.
- Existing GEK-002 proof has the repair state machine but does not prove the message was produced by a partial-recipient rotation/send boundary.

## regression/tests to add first

Add one focused GEK-003 regression before any production edits.

Preferred test file:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

Proposed test name:

- `GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival`

Required proof shape:

1. Build Alice, Bob, and Charlie group state with active device identities and epoch-1 key material.
2. Run `rotateAndDistributeGroupKey` as Alice with `sendP2PMessage` capturing direct key-update envelopes.
3. Route only Bob's key-update envelope through a `GroupKeyUpdateListener`; assert Bob commits epoch 2 and Charlie remains on epoch 1.
4. Have Bob call `sendGroupMessage` immediately after Bob's key commit; assert the outgoing row and replay envelope are epoch 2.
5. Simulate Charlie's live stale-key failure by sending a `group:decryption_failed` diagnostic with `keyEpoch: 2` and `localKeyEpoch: 1` into Charlie's `GroupMessageListener`.
6. Feed Bob's same durable replay envelope to Alice/current-key context through `drainGroupOfflineInboxForGroup` and assert Alice can materialize the message once under epoch 2. This is the non-stale recipient control for the partial-recipient setup.
7. Feed Bob's durable replay envelope to Charlie through `drainGroupOfflineInboxForGroup` using the existing cursor bridge helper in the drain test file. The queue helper may be asserted indirectly, but queue-only proof is not enough unless drain-path setup is impossible for a clearly documented reason.
8. Assert Charlie has exactly one visible pending-key row under Bob's real message id, no delivered plaintext row, and no synthetic live placeholder left after durable replay supersedes it.
9. Route Charlie's held key-update envelope through Charlie's `GroupKeyUpdateListener`, wired to `GroupPendingKeyRepairRunner.retryPendingRepairsForRequest`.
10. Assert Charlie now has exactly one delivered plaintext row for Bob's message, with epoch 2 and the original sender/message identity. Re-run retry or replay once and assert no duplicate.

If this regression passes without production changes, do not broaden implementation. Record the test as GEK-003 evidence during execution/closure.

If this regression fails, fix only the failing seam:

- `group_pending_key_repair_service.dart` if live diagnostic and durable replay do not converge to the real message id.
- `drain_group_offline_inbox_use_case.dart` if a missing epoch-2 replay does not queue the pending repair with the correct sender, transport, and replay envelope.
- `group_key_update_listener.dart` if later key arrival does not retry pending repairs only after successful active key promotion.
- `send_group_message_use_case.dart` if Bob's immediate send does not bind row/replay to the latest local committed epoch or target the expected recipient set.
- `rotate_and_distribute_group_key_use_case.dart` only if the direct key-update distribution/promote boundary itself is wrong.

Do not fix membership/config propagation in this session. If the regression fails because Bob or Charlie lacks the correct membership/config state, stop and classify that finding under GEK-004 unless it is only test setup.

## step-by-step implementation plan

1. Add the GEK-003 regression in `drain_group_offline_inbox_use_case_test.dart`.
2. Reuse existing private test helpers in that file where possible: `_CursorInboxBridge`, `_InMemoryGroupPendingKeyRepairRepository`, signed replay construction, and pending repair assertions.
3. If the regression needs duplicated pending-repair fake code from `group_message_listener_test.dart`, extract only a small test fake into `test/shared/fakes/` and update imports. Do not create production abstractions for test wiring.
4. Build three independent `InMemoryGroupRepository`/`InMemoryGroupMessageRepository` contexts for Alice, Bob, and Charlie, or use a minimal helper inside the test file to seed the same group, members, devices, and epoch-1 key.
5. Use `rotateAndDistributeGroupKey` to generate real direct key-update envelopes. Capture target transport peer ids and assert Bob and Charlie were both targeted before dropping Charlie's delivery.
6. Drive Bob's key commit through `GroupKeyUpdateListener`; assert `group:updateKey` was called and Bob's latest local key is epoch 2.
7. Run Bob's immediate `sendGroupMessage`; parse the persisted row and the `group:inboxStore`/retry replay envelope to assert epoch 2 before any Charlie repair starts.
8. Feed the same durable replay through Alice/current-key drain first, or through an equivalent current-key receive context, and assert the message is deliverable for a non-stale eligible recipient.
9. Drive Charlie's stale live diagnostic and durable replay handling through the drain path. Assert the stale recipient has an observable pending state and no plaintext delivery.
10. Deliver Charlie's held key-update envelope through `GroupKeyUpdateListener` with the retry runner wired. Assert key commit triggers repair and final visible state is one delivered row.
11. If the test is red, patch only the exact production seam proven by the failure and rerun the focused regression.
12. Rerun the GEK-001/GEK-002 focused selectors listed below to ensure the combined fix did not regress monotonicity or repair convergence.
13. Run the `groups` named gate and `git diff --check`.
14. During execution closure, update only session-scoped status/evidence in the source spec, inventory, closure reference, and breakdown. Do not write final program acceptance or GEK-004/GEK-005 closure claims.

Stop conditions:

- Stop after the regression passes with no production changes.
- Stop and hand off to GEK-004 if the only failing condition is delayed membership/config propagation.
- Stop and hand off to GEK-005 if the only remaining gap is live multi-device/relay fixture proof.

## risks and edge cases

- Fake-network plaintext delivery can hide stale-key failures; the GEK-003 proof must explicitly simulate or observe `group:decryption_failed` for Charlie before any plaintext row can be persisted.
- Durable replay and live diagnostic may create two placeholders unless GEK-002's supersede rule stays intact.
- Key-arrival retry must happen after `group:updateKey` succeeds and local key persistence commits; retrying before that can finalize the message as undecryptable.
- Same-epoch conflicting key material must still be ignored; do not make repair retry accept a different epoch-2 key for Charlie.
- Older epoch key updates may still be saved as historical material but must not promote active state or repair current pending messages.
- Removed members must not receive the rotated key, durable inbox replay, or repaired plaintext.
- Duplicate durable replay and duplicate retry must stay exactly once.
- Full owner-file drain tests currently include date-sensitive receipt fixtures; do not misclassify those known failures as GEK-003 regressions unless GEK-003 touches receipt retention.
- App resume and notification-tap drains use the same pending repair repository and drain path; avoid changes that only work in the test's direct runner but bypass production wiring.

## Device/Relay Proof Profile

GEK-003 should close with a deterministic host app-layer proof plus named host gates. A single `FLUTTER_DEVICE_ID` is enough to run device-pinned host/simulator commands such as `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, but it is not enough to prove the final live three-party relay behavior because one device cannot represent independent Alice/Bob/Charlie transport timing and partial direct key-update delivery over the real network.

Required for this session:

- Host deterministic three-actor proof in the focused regression.
- `./scripts/run_test_gates.sh groups`.
- Direct GEK-001/GEK-002 safety selectors.

Residual/final acceptance:

- Paired or three-party live device/relay proof remains GEK-005 scope unless the implementation environment already has `FLUTTER_DEVICE_ID`, `MKNOON_RELAY_ADDRESSES`, and any required secondary simulator/device identifiers configured.
- `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> ./scripts/run_test_gates.sh group-real-network-nightly` is supporting evidence only for GEK-003 unless the executor explicitly claims live relay closure. Missing relay/device fixtures are fixture-blocked, not a GEK-003 implementation failure.

## exact tests and gates to run

Focused red/green regression:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival'
```

Required focused safety selectors:

```bash
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'send during pending key update uses old epoch until local update commits'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'delayed older key update after newer generation does not promote active key'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'conflicting same-generation key updates keep first accepted material'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'messages before during and after rotation bind to the locally committed epoch'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival'
```

Owner/direct suites when touched:

```bash
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
```

Named gate and hygiene:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

Conditional commands:

```bash
./scripts/run_test_gates.sh completeness-check
```

Run `completeness-check` only if the implementation adds, removes, or renames a `_test.dart` file. Adding a test to an existing file does not require widening gate membership by itself.

```bash
FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> ./scripts/run_test_gates.sh group-real-network-nightly
```

Run the real-network nightly only if configured fixtures exist and the executor wants supporting live relay evidence. Do not block GEK-003 host closure on missing relay/device fixtures.

## known-failure interpretation

- The full `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` owner-file run may still fail older `PREREQ-GROUP-SYNC-RECEIPTS` cases because fixed `2026-05-01T12:00:00Z` receipt fixtures are outside the seven-day retention cutoff on `2026-05-09`. Treat those as the existing GEK-002 explicit follow-up unless GEK-003 edits receipt or retention behavior.
- If a focused selector listed above fails for key update, send epoch binding, pending repair, or GEK-003 itself, treat it as a GEK-003 blocker.
- If `group-real-network-nightly` cannot run because `FLUTTER_DEVICE_ID`, `MKNOON_RELAY_ADDRESSES`, or multi-relay requirements are absent, record it as fixture-blocked supporting evidence, not as a GEK-003 failure.
- Pre-existing dirty worktree changes must not be reverted. If they affect test results, classify the failure by evidence and avoid claiming GEK-003 broke unrelated areas.
- Existing group receipt-less semantics are not failures. GEK-003 is about stale-key visibility and repair, not proving every recipient acknowledged delivery.

## done criteria

- GEK-003 focused regression exists and passes.
- The regression proves partial key-update delivery, immediate epoch-2 send, stale-recipient pending state, later key arrival repair, exactly-once final plaintext, and no fake delivered live row.
- Any production change is limited to the proven failing seam and has direct focused coverage.
- GEK-001 monotonicity and GEK-002 repair convergence focused selectors still pass.
- `./scripts/run_test_gates.sh groups` passes, or any failure is documented as unrelated and pre-existing with concrete evidence.
- `git diff --check` passes.
- Execution closure updates are session-scoped and do not claim GEK-004, GEK-005, or final program acceptance.

## scope guard

Do not:

- Add group delivery receipts, per-recipient ACK UI, or new send-status semantics.
- Change membership/config propagation, invite eligibility, newly added sender policy, or delayed config catch-up.
- Change Go pubsub validator behavior unless a focused failure proves the native boundary is the GEK-003 root cause.
- Weaken removed-member exclusion, key-update authorization, device binding, signed audit checks, or same-generation conflict rejection.
- Add broad fake-network cryptography simulation if a focused diagnostic plus replay proof can prove the missing app-layer seam.
- Expand the session into final simulator/relay acceptance.
- Update breakdown/source docs during this planning-only task. Those updates belong to execution/closure.

Overengineering signs:

- Creating a general multi-device key sync framework for one regression.
- Adding new production orchestration just to make a test easier.
- Treating receipt fixture maintenance as part of GEK-003.
- Rewriting existing group send or drain architecture without a failing direct proof.

## accepted differences / intentionally out of scope

- Group messaging remains receipt-less. `sent` means the current sender pipeline reached the current durable/live success contract, not that every member has acknowledged receipt.
- Host deterministic proof is accepted for GEK-003 app-layer closure; true live relay timing and packet-level evidence remain GEK-005 residual unless fixtures are already available.
- Fake bridge encryption is plaintext passthrough in tests; the stale-key condition must be represented by the production diagnostic and missing replay key paths, not by pretending fake-network delivery decrypts.
- GEK-004 owns delayed membership/config propagation even if it can create a similar disappearance symptom.
- The GEK-002 fixed-date receipt fixture follow-up remains separate maintenance.
- Existing Go previous-epoch grace behavior is not being redefined.

## dependency impact

- GEK-005 depends on GEK-003 to say whether the partial-recipient rotation/send/repair path is covered by deterministic host evidence, blocked, or still live-fixture-only.
- GEK-004 should proceed separately for delayed membership/config propagation; GEK-003 must not consume that scope.
- If GEK-003 finds a regression in GEK-001 monotonicity or GEK-002 repair convergence, pause GEK-003 implementation and repair the regressed earlier contract first.
- If GEK-003 lands test-only evidence, later closure docs should mark only GEK-003's combined partial-recipient race as covered and still leave GEK-005 final relay/device acceptance open.

## Final verdict

GEK-003 is execution-ready as a focused, test-first implementation session. No structural blockers remain.

## Final plan

The mandatory sections above are the final plan. The executor should start with the focused GEK-003 regression and only patch production code if that regression proves a real gap.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

Exact helper extraction location is deferred to implementation. Prefer no new shared fake unless duplication becomes material.

## Accepted differences intentionally left unchanged

Host deterministic proof closes the app-layer GEK-003 seam; live multi-device/relay proof remains GEK-005 residual unless fixtures are available.

## Exact docs/files used as evidence

- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`
- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_pending_key_repair_service.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/main.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`

## Why the plan is safe or unsafe to implement now

The plan is safe to implement now if kept test-first and session-scoped. It uses existing production seams for rotation, send epoch binding, live decrypt diagnostics, durable replay pending repair, key-arrival retry, and group gate validation. It avoids GEK-004 membership/config scope and GEK-005 final relay acceptance.

## Reviewer pass

Reviewer verdict: sufficient with adjustments.

Findings checked:

- Mandatory sections are present.
- Device/relay profile is present and correctly states that a single `FLUTTER_DEVICE_ID` is not enough for final live three-party relay acceptance.
- The draft stayed out of GEK-004 membership/config propagation and GEK-005 final acceptance.
- Initial draft risk: the proposed regression could have proven only stale-recipient repair without proving the non-stale current-key control. Patched by requiring Alice/current-key drain or equivalent receive proof for the same Bob replay.
- Initial draft risk: allowing direct queue-only durable replay proof could bypass the production drain entry point. Patched by making `drainGroupOfflineInboxForGroup` the required path unless impossible for a documented reason.
- No overengineering found. Helper extraction remains optional and test-scoped.

Minimum needed for sufficiency: keep the regression single-scenario, drain-backed, and test-first; do not add production code unless that regression fails.

## Arbiter pass

Arbiter verdict: execution-ready.

Structural blockers:

- None after the reviewer patch. The closure bar, scope guard, regression-first rule, direct test contract, named gate contract, known-failure interpretation, stop rule, and Device/Relay Proof Profile are explicit.

Incremental details:

- Helper extraction can be decided during implementation. This is non-structural because the plan names the preferred test file and the minimum helper boundary.

Accepted differences:

- Host deterministic live-equivalent proof is accepted for GEK-003 app-layer closure.
- Paired or three-party live relay/device proof remains GEK-005 residual unless fixtures are available during execution.
- GEK-004 membership/config propagation remains separate even if a future failure looks symptomatically similar.

Stop rule result: no structural blocker remains, so planning stops here.
