# Promoted Admin Scenario 3 Session 01 Plan

Status: accepted_with_simulator_evidence

## Planning Progress

- 2026-05-29T00:30:00+0200 - Arbiter completed. Files inspected since last update: `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_offline_replay_envelope_test.dart`, simulator command `#85`. Decision/blocker: no structural blocker; reopen Bug-1 as a narrow sender-device bootstrap defect and require a failing host regression plus successful simulator proof before final. Next action: implement the guarded bootstrap fix and rerun targeted host and simulator gates.
- 2026-05-29T00:29:00+0200 - Reviewer completed. Files inspected since last update: same as planner. Decision/blocker: plan is sufficient if it does not weaken signed actor/audit verification, relay sender mismatch checks, or general user-message device binding; simulator #85 is adjacent but must be rerun after the fix. Next action: arbiter classification.
- 2026-05-29T00:27:00+0200 - Planner completed. Files inspected since last update: metadata listener and replay-envelope verification seams. Decision/blocker: smallest fix is to let signed metadata events bootstrap the sender's active device only when the trusted member account key matches the incoming snapshot, and let direct replay decrypt account-key signed envelopes for known members that have no device row yet. Next action: reviewer pass.
- 2026-05-29T00:24:00+0200 - Evidence Collector completed. Files inspected since last update: `group_message_listener.dart`, `group_offline_replay_envelope.dart`, `group_info_wired.dart`, simulator log `/tmp/group_scenario85_before_fix_20260529.log`. Decision/blocker: simulator #85 passed but does not disprove the manual Bug-1 path; code still rejects metadata before applying a snapshot when the local sender member has no device and the event arrives from the sender's transport device. Next action: planner pass.
- 2026-05-28T22:48:15+0200 - Arbiter completed. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md`. Decision/blocker: no structural blockers; incremental details documented as optional; accepted differences recorded. Next action: hand plan to execution.

## Execution Progress

- 2026-05-29T00:25:05+0200 - Phase: simulator acceptance completed. Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_offline_replay_envelope_test.dart`, `/tmp/group_scenario85_after_fix_20260529.log`. Command finished: `$CODEX_HOME/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --only 85` passed. Decision/blocker: multi-device `private_admin_metadata_intro_photo_convergence` proved valid verdicts for alice, bob, and charlie with `groupName=test me`, `groupDescription=do you see me?`, `avatarUpdateConverged=true`, `fullFanoutAfterCharlieJoin=true`, `finalMemberStateConverged=true`, and `finalKeyConverged=true`. Next action: final report.
- 2026-05-29T00:22:00+0200 - Phase: host regression and exact Scenario 3 proof completed. Files inspected or touched: group listener/offline replay production and tests. Commands finished: full `group_message_listener_test.dart`, full `group_offline_replay_envelope_test.dart`, and exact Scenario 3 host proof all passed. Decision/blocker: targeted regressions failed before production changes and passed after the sender-device bootstrap fix; no blocker. Next action: run simulator proof required by user.
- 2026-05-29T00:21:00+0200 - Phase: production fix completed. Files inspected or touched: `group_message_listener.dart`, `group_offline_replay_envelope.dart`. Decision/blocker: metadata system events may now bootstrap a no-device admin member only from a signed metadata snapshot whose sender device matches the trusted account public key; direct replay may decrypt account-key-signed envelopes for known members with no device row yet. Authorization, actor signature, signed audit, state hash, and relay-sender checks remain in force. Next action: direct tests.
- 2026-05-28T23:01:14+0200 - Phase: final execution-orchestrator handoff after bounded wait interrupt. Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md`, `test/features/groups/presentation/contact_picker_wired_test.dart`, `/tmp/gm-sc3-001-executor-result.md`, process list. Command finished: terminated remaining nested Executor processes `25912` and `25916`; no matching nested `codex exec` or group `flutter test` process remained afterward. Decision/blocker: Final execution verdict for GM-SC3-001 is `blocked` with blocker class `spawn_or_tool_failure`; the child produced useful on-disk partial evidence but never wrote `/tmp/gm-sc3-001-executor-result.md`, no QA Reviewer was spawned, and required `./scripts/run_test_gates.sh groups` plus `git diff --check` evidence is missing. Trustworthy partial evidence harvested from this plan: the new production-path `ContactPickerWired` promoted-admin invite regression was added first; the first run failed only because the assertion expected a top-level direct sender field; the corrected regression passed before any production fix; EK004 role replay passed; exact Scenario 3 helper-level host proof passed. Production work remains evidence-gated because the new production-path regression did not reproduce a failing seam. Next action: pipeline controller should either rerun a fresh execution/QA pass from the current diff to finish remaining gates and QA, or require real-app logs/device reproduction before any production fix.
- 2026-05-28T23:00:49+0200 - Phase: exact Scenario 3 host proof completed. Files inspected or touched: `test/features/groups/integration/group_admin_metadata_convergence_test.dart`. Command finished: `flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "exact Scenario 3 promoted admin invite, metadata, fanout, and photo journey passes" -r expanded` passed. Decision/blocker: helper-level exact Scenario 3 confirmation remains green; production-path regression also green, so production work remains evidence-gated. Next action: run adjacent direct suites for the represented group invite/member seams.
- 2026-05-28T23:00:26+0200 - Phase: exact Scenario 3 host proof started. Files inspected or touched: `test/features/groups/integration/group_admin_metadata_convergence_test.dart`. Command running: `flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "exact Scenario 3 promoted admin invite, metadata, fanout, and photo journey passes" -r expanded`. Decision/blocker: running required helper-level full journey confirmation after production-path picker proof passed; no production edits. Next action: wait for result.
- 2026-05-28T23:00:16+0200 - Phase: required direct proof completed. Files inspected or touched: `test/features/groups/presentation/group_info_wired_test.dart`. Command finished: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "EK004 promote member stores signed member_role_updated replay envelope" -r expanded` passed. Decision/blocker: promoted role replay proof remains green; no production fix warranted by evidence. Next action: run exact Scenario 3 host proof.
- 2026-05-28T22:59:57+0200 - Phase: required direct proof started. Files inspected or touched: `test/features/groups/presentation/group_info_wired_test.dart`. Command running: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "EK004 promote member stores signed member_role_updated replay envelope" -r expanded`. Decision/blocker: running required role replay proof after evidence-gated contact-picker pass; no production edits. Next action: wait for result.
- 2026-05-28T22:59:45+0200 - Phase: direct regression passed/evidence gate reached. Files inspected or touched: `test/features/groups/presentation/contact_picker_wired_test.dart`. Command finished: `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name "promoted admin invite from production picker carries latest metadata, avatar, existing-member replay, and full membership snapshot" -r expanded` passed. Decision/blocker: production-path promoted-admin picker regression is green before production changes, so no production seam is proven and production edits stop under the plan. Next action: run the remaining required direct proofs and gates as evidence only.
- 2026-05-28T22:59:18+0200 - Phase: direct regression rerun started. Files inspected or touched: `test/features/groups/presentation/contact_picker_wired_test.dart`. Command running: `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name "promoted admin invite from production picker carries latest metadata, avatar, existing-member replay, and full membership snapshot" -r expanded`. Decision/blocker: formatter passed after assertion correction; still no production code changes. Next action: wait for rerun result.
- 2026-05-28T22:59:05+0200 - Phase: regression assertion correction completed. Files inspected or touched: `test/features/groups/presentation/contact_picker_wired_test.dart`. Command running: `dart format test/features/groups/presentation/contact_picker_wired_test.dart`. Decision/blocker: adjusted only the regression to match the existing direct replay envelope contract; no production changes made. Next action: format and rerun the direct regression.
- 2026-05-28T22:58:49+0200 - Phase: direct regression completed/fix test assertion. Files inspected or touched: `test/features/groups/presentation/contact_picker_wired_test.dart`, `lib/features/groups/application/group_membership_update_listener.dart`. Command finished: `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name "promoted admin invite from production picker carries latest metadata, avatar, existing-member replay, and full membership snapshot" -r expanded` failed. Decision/blocker: failure was test assertion shape only, expecting direct sender at top-level `senderId`; production direct membership envelope stores sender under `relayEnvelope.from`. Next action: correct regression assertion without touching production, format if needed, and rerun.
- 2026-05-28T22:58:04+0200 - Phase: direct regression started. Files inspected or touched: `test/features/groups/presentation/contact_picker_wired_test.dart`. Command running: `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name "promoted admin invite from production picker carries latest metadata, avatar, existing-member replay, and full membership snapshot" -r expanded`. Decision/blocker: no production changes have been made; this run determines whether there is a reproducible production seam to patch. Next action: wait for direct regression result.
- 2026-05-28T22:57:55+0200 - Phase: formatting completed. Files inspected or touched: `test/features/groups/presentation/contact_picker_wired_test.dart`. Command finished: `dart format test/features/groups/presentation/contact_picker_wired_test.dart` passed. Decision/blocker: regression file formatted successfully; no blocker. Next action: run the required new production-path regression directly.
- 2026-05-28T22:57:41+0200 - Phase: formatting started. Files inspected or touched: `test/features/groups/presentation/contact_picker_wired_test.dart`. Command running: `dart format test/features/groups/presentation/contact_picker_wired_test.dart`. Decision/blocker: format the regression before executing the direct test; no blocker. Next action: run formatter and record result.
- 2026-05-28T22:57:29+0200 - Phase: regression-first edit completed. Files inspected or touched: `test/features/groups/presentation/contact_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md`. Command running: none. Decision/blocker: added the exact named production-path regression for B-as-promoted-admin inviting C through `ContactPickerWired`; no production code changes made. Next action: format the touched test, then run the new regression directly.
- 2026-05-28T22:55:58+0200 - Phase: regression-first edit started. Files inspected or touched: `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/application/group_invite_auth.dart`, `lib/features/groups/domain/models/group_member.dart`, `lib/features/groups/domain/models/group_model.dart`, `test/features/groups/presentation/contact_picker_wired_test.dart`, `test/core/bridge/fake_bridge.dart`, `test/core/services/fake_p2p_service.dart`. Command running: none. Decision/blocker: target seam is the real `ContactPickerWired._inviteSelected` promoted-admin invite path; no production code changes made. Next action: patch the named production-path regression into `contact_picker_wired_test.dart`.
- 2026-05-28T22:53:22+0200 - Phase: local Executor started. Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md`, `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`, git status. Command running: none. Decision/blocker: plan, breakdown, gate source, skill contract, and dirty worktree loaded; many pre-existing modified files include group production/test files, so edits must preserve local changes. Next action: inspect production/test seams and add the regression-first production-path test before any production code changes.
- 2026-05-28T22:50:22+0200 - Phase: contract extraction started. Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-breakdown.md`, `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`. Command running: none. Decision/blocker: execution/QA orchestrator contract loaded; no blocker. Next action: extract exact phase contract before any coding.
- 2026-05-28T22:50:57+0200 - Phase: contract extracted. Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md`. Command running: none. Decision/blocker: scope is GM-SC3-001 only; add a production-path regression before production fixes; patch only the failing promoted-admin Scenario 3 seam; required direct tests are the new contact-picker production regression, `group_info_wired_test.dart` EK004 role replay, and exact Scenario 3 host proof; required named gate/hygiene are `./scripts/run_test_gates.sh groups` and `git diff --check`; known failures are limited to documented completeness-check unmatched files and do not excuse required group evidence. Next action: spawn fresh Executor agent with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-28T22:51:12+0200 - Phase: Executor spawned/running. Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md`. Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app -s danger-full-access -a never --output-last-message /tmp/gm-sc3-001-executor-result.md -`. Decision/blocker: nested Executor handoff is bounded to the extracted contract and must add the production-path regression before production fixes. Next action: wait for Executor evidence.
- 2026-05-28T22:52:05+0200 - Phase: Executor spawn command failed before child materialized. Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md`. Command running: none; failed command rejected unsupported `-a` option for `codex exec`. Decision/blocker: CLI syntax issue only, no child work or repo changes from the failed spawn. Next action: retry Executor spawn with supported `codex exec` flags while preserving `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-28T22:53:24+0200 - Phase: Executor retry spawned/running. Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md`. Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app -s danger-full-access --dangerously-bypass-approvals-and-sandbox --output-last-message /tmp/gm-sc3-001-executor-result.md -`. Decision/blocker: child materialized and reported `model: gpt-5.5` plus `reasoning effort: xhigh`; no blocker. Next action: wait for Executor implementation and test evidence.

## Closure Progress

- 2026-05-28T23:13:50+0200 - Completion Auditor: audited the post-blocker implementation evidence for `GM-SC3-001`. Current diff shows the failing regression-first test `Scenario 3 C send preserves A and B as durable inbox recipients` in `test/features/groups/application/send_group_message_use_case_test.dart`; the pre-fix failure was `Expected: true Actual: <null>` for `inboxPayload['preserveRecipientPeerIds']`. The accepted production fix is limited to `lib/features/groups/application/send_group_message_use_case.dart` and `lib/features/groups/application/group_offline_replay_envelope.dart`, where explicit `recipientPeerIds` now request `preserveRecipientPeerIds` for initial store and retry store paths. `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` now asserts the retry preserve flag. Classification: `accepted_with_explicit_follow_up`.
- 2026-05-28T23:13:50+0200 - Closure Writer: recorded Scenario 3 as accepted because the new regression failed before the fix and passed after the fix, and the supporting host checks passed: the new C-send regression, retry direct test, `storeGroupOfflineReplayEnvelope can preserve explicit recipients`, promoted-admin invite picker proof, EK004 role replay proof, exact Scenario 3 host proof, formatting, and `git diff --check`. The session remains short of `closed` because `./scripts/run_test_gates.sh groups` is blocked by unrelated `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned` failing with `Bad state: Stale group membership event` at `add_group_member_use_case.dart:281`; the individual `UP-001` rerun still fails the same way after the Scenario 3 fix.
- 2026-05-28T23:13:50+0200 - Closure Reviewer: no production-scope work is reopened for `GM-SC3-001`. Future work should reopen this session only on a real regression in the exact Scenario 3 A/B/C journey or its named direct tests. The residual item is the unrelated `UP-001` group-gate failure, which must be tracked separately before the named group gate can be claimed green.

## real scope

This session is limited to the user-reported Group Messaging Scenario 3:

- A creates a group and promotes B to admin.
- B updates group metadata and group photo.
- A receives B's metadata/photo update.
- B invites C.
- C accepts the latest metadata/photo snapshot.
- A learns C is a member before C sends.
- C sends to A and B.
- A updates the group photo and the update reaches B and C.

The implementation may change only the production paths needed for that journey: promoted-admin role propagation, metadata/photo update broadcast and replay, promoted-admin invite fanout, pending invite materialization, membership update replay, group send recipient selection, and the direct UI/use-case wiring that connects those paths.

## closure bar

Good enough means the exact Scenario 3 is proven through production-facing entry points that can fail in the real app, not only through `GroupTestUser` helper shortcuts. The executor must add a regression that exercises the path through `GroupInfoWired` and/or `ContactPickerWired`/`GroupListWired` and proves the failing production seam before changing code. The existing exact host test in `group_admin_metadata_convergence_test.dart` remains required confirmation, but passing it alone cannot close this session.

## source of truth

- Active contract: `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-breakdown.md`, session `GM-SC3-001`.
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`; `test-gates-reference.md` and `_current-test-map.md` are supporting maps.
- Behavior source of truth: current production code and direct tests win over stale matrix prose.
- Matrix context: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md` can explain GL-004 breadth, but this session must not broaden into the full role-policy matrix.

## session classification

`implementation-ready`

The session has enough evidence to implement after adding a production-path regression. It is not `stale/already-covered` because the current exact host test uses fake/direct delivery and the user reports the real app still fails.

## exact problem statement

The app still allows a real Scenario 3 failure after host tests were added. The likely gap is between helper-level proof and production entry points:

- `test/features/groups/integration/group_admin_metadata_convergence_test.dart` has `exact Scenario 3 promoted admin invite, metadata, fanout, and photo journey passes`, but it uses `FakeGroupPubSubNetwork`, `GroupTestUser`, `_DirectMembershipUpdateHarness`, and manual `_sendDirectReplay` metadata/membership delivery.
- `integration_test/group_admin_metadata_convergence_simulator_test.dart` currently wraps only the older two convergence scenarios and does not run the exact Scenario 3 test.
- The real app path runs through `GroupInfoWired._saveDetails`, `GroupInfoWired._onAddMember`, `ContactPickerWired._inviteSelected`, `GroupListWired._onAcceptPendingInvite`, `GroupConversationWired` send flow, `IncomingMessageRouter`, and `GroupMembershipUpdateListener`.

The user-visible behavior to improve: a promoted admin's metadata/photo update and invite must converge for A/B/C, and group message fanout must use the latest membership. The fix must not weaken authorization, signed transition audit checks, device binding checks, or membership freshness checks.

## files and repos to inspect next

Production files:

- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/update_group_metadata_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/group_membership_update_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/main.dart`
- `lib/core/services/incoming_message_router.dart`

Test and gate files:

- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`
- `test/features/groups/application/send_group_invite_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `integration_test/group_admin_metadata_convergence_simulator_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- `group_admin_metadata_convergence_test.dart` has exact Scenario 3 helper-level host coverage and several adjacent focused tests for promoted-admin metadata, creator learning C, pre-join photo snapshots, invited-member send, and photo fanout.
- `group_info_wired_test.dart` covers metadata edit signing/publish/inbox behavior and `EK004 promote member stores signed member_role_updated replay envelope`.
- `contact_picker_wired_test.dart` covers `members_added` publish, replay inbox store, and direct membership update delivery to existing members.
- `send_group_invite_use_case_test.dart` covers promoted-admin invite using the full current membership snapshot even when the argument config is stale.
- `member_removal_integration_test.dart` covers direct membership update relay sender mismatch rejection.
- `test-gate-definitions.md` places `group_admin_metadata_convergence_test.dart` inside `./scripts/run_test_gates.sh groups`.

Missing coverage: a production-facing Scenario 3 regression that chains the real UI/use-case entry points enough to catch the app bug. Existing tests do not prove that B's real `GroupInfoWired` metadata/photo update, B's real `ContactPickerWired` invite path, C's real pending-invite accept, and C/A real send/update paths all exchange the same latest group config through the app wiring.

## regression/tests to add first

Add a failing production-path regression before implementation. Prefer the smallest test that reproduces the real bug:

1. Add or extend a test in `test/features/groups/presentation/contact_picker_wired_test.dart` for a group created by A where B is a promoted admin (`group.myRole == admin`, B member role admin, `createdBy == A`), B's local group row already has the latest name/description/avatar, and B invites C through `ContactPickerWired`. Assert:
   - `group:updateConfig` uses A/B/C and the latest metadata/avatar.
   - `members_added` publish is signed by B and carries the latest full `groupConfig`.
   - `group:inboxStore`/direct `group_membership_update` targets existing A, not only C.
   - the encrypted invite payload to C includes A/B/C plus the latest metadata/avatar and promoted-admin freshness proof.

2. If that invite-focused test does not reproduce the failure or does not cover all Scenario 3 checkpoints, add a production wrapper test in `test/features/groups/presentation/group_info_wired_test.dart` or a focused integration harness that drives:
   - A promotes B through the real role update path.
   - B saves metadata/photo through `GroupInfoWired._saveDetails`.
   - B invites C through `ContactPickerWired`.
   - C accepts through `acceptPendingGroupInvite` with the same payload shape `GroupListWired` passes.
   - C sends through `sendGroupMessage`/`GroupConversationWired` and recipients include A/B.
   - A's later metadata/photo update goes through the same production metadata path and reaches B/C.

3. Only after a production-path regression identifies the gap should the executor patch production code. If the new production-path regression unexpectedly passes before code changes, stop and reclassify the implementation as evidence-gated rather than claiming the real app bug is fixed.

## step-by-step implementation plan

1. Add the production-path regression described above and run it directly. Capture the failing assertion or, if it passes, capture why it still does not match the real app report.
2. Trace the failing seam to one of these narrow areas:
   - B's promoted admin role is not current when `GroupInfoWired` or `ContactPickerWired` acts.
   - metadata/photo publish, inbox store, direct membership update, or avatar download/regrant does not target the required peers.
   - `ContactPickerWired` builds or sends an invite with stale group config after avatar regrant or membership mutation.
   - C accept materializes a stale or incomplete group config.
   - A does not apply the `members_added` replay before C sends.
   - `sendGroupMessage` recipient selection is using stale local membership.
3. Patch only the production file responsible for the failing seam.
4. Run the new regression until it passes.
5. Run the existing exact Scenario 3 host proof and the focused adjacent tests.
6. If a changed production seam is also represented by the simulator wrapper, update `integration_test/group_admin_metadata_convergence_simulator_test.dart` to include `runExactScenario3PromotedAdminJourney()` only as optional simulator coverage; do not treat that wrapper as real relay proof.
7. Run the named group gate and `git diff --check`.
8. Update only closure docs requested by the downstream closure phase; this planning session should not mark the breakdown closed.

Stop early if the new production-path regression proves the app path is already green in-repo. In that case, preserve the evidence and require device/log reproduction rather than making speculative code changes.

## risks and edge cases

- Direct membership updates are sent with `unawaited`; the production bug may be an ordering/race between invite accept, A learning C, and C sending.
- Metadata/avatar updates must retain signed actor/audit validation and current-admin authorization; do not bypass `_verifyGroupMetadataActorEvent`, `_isAuthorizedMembershipEventSender`, or device-binding checks.
- `ContactPickerWired._refreshAvatarAccessForMembers` may change `avatarBlobId` before invite fanout; existing members and C must receive the same latest config.
- C accept must download/store avatar path when `avatarBlobId` and `avatarMime` are present.
- If publish succeeds but inbox/direct replay fails, the app must surface or persist enough recovery evidence instead of silently claiming convergence.
- Stale membership or metadata watermarks can make real-app replays ignored even when helper tests pass.

## exact tests and gates to run

Regression-first direct commands:

```bash
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name "promoted admin invite from production picker carries latest metadata, avatar, existing-member replay, and full membership snapshot" -r expanded
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "EK004 promote member stores signed member_role_updated replay envelope" -r expanded
flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "exact Scenario 3 promoted admin invite, metadata, fanout, and photo journey passes" -r expanded
```

Adjacent direct commands if the touched seam requires them:

```bash
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart -r expanded
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart -r expanded
flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart --plain-name "promoted admin invite includes the full current membership snapshot" -r expanded
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name "direct membership update rejects relay sender mismatch" -r expanded
flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart -r expanded
```

Required named gate and hygiene:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

Optional simulator wrapper after host proof:

```bash
flutter test -d <device-id> integration_test/group_admin_metadata_convergence_simulator_test.dart --plain-name "exact Scenario 3 promoted admin invite, metadata, fanout, and photo journey passes" -r expanded
```

Only run the optional command if the wrapper is intentionally widened to include the exact Scenario 3 test and a device is available.

## Device/Relay Proof Profile

Classification: host-required production-path proof plus optional simulator proof.

Device-required proof is not selected for this session plan because the immediate gap is that current host proof does not exercise production entry points. No availability check was run for this planning pass. If the executor later promotes this to device-required proof, run the availability/config checks before claiming device coverage:

```bash
flutter devices
printf '%s\n' "${MKNOON_RELAY_ADDRESSES:-}"
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_admin_metadata_intro_photo_convergence --list-scenarios
```

Then run a row-specific device/relay command only if the scenario actually matches B-promoted-admin Scenario 3 or after adding a row-specific scenario. Existing `integration_test/group_admin_metadata_convergence_simulator_test.dart` is a simulator wrapper around fake-stack host helpers, and currently omits the exact Scenario 3 test, so it is optional evidence only until widened.

## known-failure interpretation

- A passing current exact host test is not closure by itself; it is a confirmation test after the production-path gap is fixed.
- A passing `./scripts/run_test_gates.sh groups` before adding a production-path regression is not closure by itself.
- `./scripts/run_test_gates.sh completeness-check` was most recently documented as failing on `747/750` classified files because `test/l10n/l10n_integrity_test.dart`, `test/shared/fakes/fake_group_pubsub_network_test.dart`, and `test/shared/fakes/seeded_group_reproduction_log_test.dart` were unmatched. Do not classify those as regressions for this session unless this work changes completeness rules.
- Optional simulator/device proof that cannot run because no device or relay env is configured must be recorded as unrun, not passed.

## done criteria

- A production-path regression is added or strengthened and fails before the fix for the real Scenario 3 gap.
- The production code fix is limited to the failing seam and makes that regression pass.
- The exact Scenario 3 proof verifies, through production-facing entry points or through a documented combination of production-path regression plus existing full-journey host confirmation: A receives B metadata/photo; B invites C; C accepts with latest metadata/photo; A learns C before C sends; C's message targets/reaches A and B; A's later photo update reaches B and C.
- Required direct tests, `./scripts/run_test_gates.sh groups`, and `git diff --check` pass, or any pre-existing unrelated failure is documented with concrete evidence.
- The plan is not closed solely because old host coverage passes.

## scope guard

Non-goals:

- Do not implement the full GL-004 configurable owner/moderator/member permission matrix.
- Do not redesign group invite policy, key rotation, relay persistence, notification routing, or multi-device admission.
- Do not widen named gates unless `test-gate-definitions.md` already requires it or a deliberate docs update is separately approved.
- Do not weaken signed transition audit, group config state hash, relay sender mismatch, or device binding validation to make the scenario pass.
- Do not rewrite group repositories or database schema unless the failing production seam proves persisted state is the issue.

Overengineering would be adding a new group-state engine, broad retry subsystem, new relay protocol, or generic group reconciliation layer for this one Scenario 3 bug.

## accepted differences / intentionally out of scope

- The broad GL-004 row remains `Partial` because full role-policy configurability is wider than this user-reported regression.
- Real multi-relay/device proof remains optional in this session unless the production-path host regression cannot reproduce the bug or the executor adds a row-specific device scenario.
- Existing `private_admin_metadata_intro_photo_convergence` device harness coverage is adjacent, not exact B-promoted-admin Scenario 3 closure.

## dependency impact

Downstream execution and closure depend on this plan to prevent a fake-only fix. If the production-path regression cannot be made to reproduce the issue, downstream execution should pause and request real-app logs or a device-required scenario instead of changing code speculatively. If the plan changes to device-required proof, closure must record the device IDs, relay env, and exact row-specific command used.

## reviewer findings

Sufficiency: sufficient with adjustments. The plan has explicit scope, closure bar, source of truth, classification, problem statement, files, existing coverage, regression-first rule, implementation steps, tests/gates, known-failure interpretation, done criteria, and scope guard.

Missing files/tests/gates: no structural omissions after tightening the regression section to require production-path mapping for every Scenario 3 checkpoint. The optional simulator wrapper is correctly classified as optional because it currently omits the exact Scenario 3 test and is fake-stack evidence.

Stale assumptions: the plan correctly treats current host pass as insufficient because the user reports real-app failure.

Overengineering: none required; the plan directs executor to patch only the failing production seam.

Minimum needed: add a production-path regression first, then implement only against the reproduced seam.

## arbiter decision

Structural blockers: none.

Incremental details intentionally deferred:

- Device availability was not checked because the final proof profile is host-required with optional simulator evidence. If execution promotes this to device-required, run the listed device/relay checks first.
- Exact naming of the new regression can change during execution as long as the test proves the same Scenario 3 production-path gap before code changes.

Accepted differences:

- Existing fake-stack exact Scenario 3 coverage remains useful confirmation but is not accepted as the closure proof.
- Broad GL-004 role-policy completeness remains out of scope.

Historical planning classification: `implementation-ready`, `Status: execution-ready`.
Current closure status is recorded at the top of this plan and in `Closure Progress`.

## Dirty Worktree Snapshot Before Execution

Captured by the pipeline controller on 2026-05-28 before the execution handoff.
The worktree is broadly dirty with many unrelated UI/doc/test changes already
present. Current session scope is limited to promoted-admin Scenario 3 files.

In-scope dirty files already present before this execution step:

- `lib/features/groups/application/group_membership_update_listener.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/send_group_invite_use_case_test.dart`
- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/_current-test-map.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/test-gates-reference.md`
- `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/promoted-admin-scenario3-session-01-plan.md`

Scope guard for execution: do not revert unrelated dirty files. If execution
touches additional files, classify them against this session's scope in QA.
