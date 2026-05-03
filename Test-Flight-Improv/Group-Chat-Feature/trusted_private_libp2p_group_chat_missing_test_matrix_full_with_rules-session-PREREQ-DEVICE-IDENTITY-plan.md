Status: accepted

# PREREQ-DEVICE-IDENTITY Plan

## Planning Progress
- 2026-05-01T13:32:00+02:00 - Arbiter completed. Files inspected since last update: reviewer findings and final plan. Decision/blocker: no structural blockers remain; migration-number refresh is an execution stop condition if `062` is already claimed, not a planning blocker. Next action: execute the plan through regression-first implementation.
- 2026-05-01T13:31:00+02:00 - Arbiter started. Files inspected since last update: reviewer sufficiency findings. Decision/blocker: classify review findings and stop if no structural blocker remains. Next action: finalize status if safe.
- 2026-05-01T13:30:00+02:00 - Reviewer completed. Files inspected since last update: full draft plan. Decision/blocker: plan is sufficient after including DB/config propagation, offline replay, Go internal envelope/config files, dirty-worktree handling, source-doc updates, and device/relay proof profile. Next action: run arbiter pass.
- 2026-05-01T13:28:00+02:00 - Reviewer started. Files inspected since last update: draft plan content and direct evidence summary. Decision/blocker: draft includes exact scope, owner files, tests, gates, device profile, and dirty-worktree handling. Next action: review for missing files, stale assumptions, overreach, and closure bar sufficiency.
- 2026-05-01T13:27:00+02:00 - Planner completed. Files inspected since last update: direct source/docs/code evidence gathered by Evidence Collector. Decision/blocker: plan drafted as implementation-ready, host/fake-network first, with paired iOS as supporting proof and Android paired proof fixture-blocked. Next action: run strict reviewer pass.

## Execution Progress
- 2026-05-01T14:58:30+02:00 - Plan status header aligned to `accepted`; final diff hygiene re-run passed: `git diff --check`. Files changed since last update: plan status header/progress evidence only. Decision/blocker: final docs and code diff remain whitespace-clean. Next action: return final execution verdict.
- 2026-05-01T14:58:15+02:00 - Final diff hygiene passed after closure-doc updates: `git diff --check`. Files changed since last update: none beyond progress evidence. Decision/blocker: no whitespace or conflict-marker issues remain in the accepted PREREQ-DEVICE-IDENTITY diff. Next action: return final execution verdict.
- 2026-05-01T14:58:00+02:00 - Post-verdict closure-doc update completed; final diff hygiene starting. Files changed since last update: current session breakdown ledger row and final program verdict entry. Decision/blocker: breakdown now records `PREREQ-DEVICE-IDENTITY` as `accepted`/`qa_passed`; EK-011 remains `Partial` and `PREREQ-WELCOME-KEY-PACKAGE` remains the owner for welcome/key-package validation. Next action: run `git diff --check` on the final doc/code state.
- 2026-05-01T14:57:15+02:00 - Final verdict accepted. Files changed since last update: session plan progress/final-verdict only. Decision/blocker: PREREQ-DEVICE-IDENTITY is accepted with host/fake-network, targeted Go validator, named gates, completeness, and diff hygiene green; EK-003 closure evidence is documented and EK-011 remains `Partial`. Next action: return final execution verdict.
- 2026-05-01T14:57:00+02:00 - Final QA Reviewer completed and final verdict work starting. Files inspected since last update: final QA result, targeted Flutter/Go gate output, source matrix/test inventory/breakdown status, and EK-011 status. Decision/blocker: final QA verdict is `pass/no_blocking`; only residual risk is a non-blocking hardening gap for a separate outgoing-send unregistered-device branch regression. Next action: update this plan final verdict and run final diff hygiene.
- 2026-05-01T14:56:30+02:00 - Final QA Reviewer starting. Files inspected since last update: `/tmp/prereq-device-identity-fixpass.txt`, current progress log, dirty worktree status, and implementation-execution QA skill contract. Decision/blocker: single allowed fix loop completed with green host/fake-network gates; final QA will verify the four prior blockers, EK-003 closure evidence, EK-011 Partial status, and doc/gate sufficiency without further edits. Next action: spawn isolated final QA Reviewer.
- 2026-05-01T14:56:00+02:00 - Final tracked diff hygiene check passed: `git diff --check`. Files changed since last update: none. Decision/blocker: fix-pass evidence is complete for current session; source matrix, test inventory, and breakdown remain deliberately unchanged for final closure and EK-011 remains `Partial`. Next action: return compact fix-pass result.
- 2026-05-01T14:55:30+02:00 - Focused offline replay proof rerun passed after adding explicit notification side-effect assertion: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` (`43/43`). Files changed since last update: `drain_group_offline_inbox_use_case_test.dart`. Decision/blocker: invalid registered-device replay is now proven to avoid message storage, event-log append, listener stream emission, and local notification side effects. Next action: final tracked diff hygiene check and compact handoff.
- 2026-05-01T14:54:00+02:00 - Executor fix-pass handoff complete. Files changed since last update: session plan evidence only. Decision/blocker: QA blocking findings for invite/admission local device identity, registered-device production send, key distribution/listener device binding, and offline replay device binding are addressed with host/fake-network proof; tracked diff hygiene rerun passed. Source matrix, inventory, and breakdown are deliberately left for final closure; EK-011 remains `Partial`. Go device validator was not rerun because no Go files changed; Android paired evidence remains external-fixture-blocked. Next action: return compact fix-pass result.
- 2026-05-01T14:53:30+02:00 - Diff hygiene passed: `git diff --check`. Files changed since last update: none. Decision/blocker: no whitespace or conflict-marker issues in the dirty diff. Next action: record fix-pass docs/handoff status; source matrix, inventory, and breakdown remain for final closure and EK-011 stays `Partial`.
- 2026-05-01T14:53:00+02:00 - Named gate passed: `./scripts/run_test_gates.sh completeness-check` (`700/700` test files classified). Files changed since last update: none. Decision/blocker: completeness classifier is green. Next action: run `git diff --check`.
- 2026-05-01T14:52:30+02:00 - Named gate passed: `./scripts/run_test_gates.sh groups` (`101/101`). Files changed since last update: none. Decision/blocker: canonical group messaging gate is green after device-identity fix pass. Next action: run named gate `./scripts/run_test_gates.sh completeness-check`.
- 2026-05-01T14:51:00+02:00 - Relevant fake-network integration proof passed: `flutter test --no-pub test/features/groups/integration/group_multi_device_convergence_test.dart test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_new_member_onboarding_test.dart test/features/groups/integration/group_resume_recovery_test.dart` (`65/65`). Files changed since last update: none. Decision/blocker: listener, invite round-trip, onboarding, multi-device convergence, and resume replay remain green under fake network. Next action: run named gate `./scripts/run_test_gates.sh groups`.
- 2026-05-01T14:49:30+02:00 - Focused invite/admission proof rerun passed: `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart` (`72/72`). Files changed since last update: none. Decision/blocker: send/handle/accept device-bound invite paths reject missing/wrong local device identity, wrong transport, wrong key package, and unregistered target devices before side effects. Next action: run relevant fake-network integration smoke.
- 2026-05-01T14:48:30+02:00 - Broader impacted message/listener/offline replay block passed: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` (`244/244`). Files changed since last update: none. Decision/blocker: production send, incoming message validation, listener side effects, and offline replay remain green together. Next action: rerun focused invite/admission proof after the fix-pass edits.
- 2026-05-01T14:47:30+02:00 - Focused offline replay proof passed: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` (`43/43`). Files changed since last update: fixed the offline replay side-effect test callback return. Decision/blocker: valid registered-device replay is accepted and invalid registered-device replay is rejected before message/event-log/listener side effects. Next action: run broader impacted message/listener/offline replay block.
- 2026-05-01T14:46:30+02:00 - Focused send/key distribution/listener tests passed after fix-pass implementation: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart` (`112/112`). Files changed since last update: tightened rotate source-device fallback and corrected focused assertions. Decision/blocker: registered sender-device sends, active/revoked key targeting, unbound source rejection, and wrong local recipient rejection now have green host proof. Next action: run offline replay proof.
- 2026-05-01T14:45:00+02:00 - Executor fix-pass implementation completed; focused tests starting. Files changed since last update: invite handle/accept/listener wiring, production accept UI wiring, production send device resolution, key rotation/listener device fallback, system replay sender-device guard, focused invite/send/key/replay tests. Decision/blocker: code now avoids peer-id fallback for device-bound invite/admission, resolves registered sender devices before group sends, rejects registered key updates without active source/local recipient devices, and rejects replayed system events from unbound devices. Next action: run focused Flutter tests for each QA finding.
- 2026-05-01T14:31:00+02:00 - Executor fix-pass implementation starting. Files inspected since last update: invite listener/handle/accept paths, group list accept path, message send path, key rotation/listener, offline replay drain/listener, identity model, main wiring, focused tests. Decision/blocker: apply narrow fixes for device fallback removal, production local-device wiring, registered sender-device send resolution, registered key-source/recipient fail-closed behavior, and replay/system device binding. Next action: patch owner files and add focused regressions for QA findings.
- 2026-05-01T14:23:26+02:00 - Executor fix pass started. Files inspected since last update: QA report, Executor report, `git status --short`, current execution log. Decision/blocker: one bounded fix pass will address only the four QA blocking findings; no welcome/key-package lifecycle, revocation UX, trust UI, relay schema, or unrelated dirty files. Next action: re-read owner files and current diffs before scoped edits.
- 2026-05-01T14:22:19+02:00 - QA Reviewer completed with blocking findings; fix pass starting. Files inspected since last update: QA final report. Decision/blocker: QA found missing production/evidence closure for local device identity in invite/admission, registered-device production send, key distribution/listener active/revoked and invalid-device regressions, and offline replay valid/invalid device proof. Next action: spawn isolated Executor fix pass scoped only to those blocking findings.
- 2026-05-01T14:14:27+02:00 - QA Reviewer starting. Files inspected since last update: Executor final report and current execution progress log. Decision/blocker: Executor reports PREREQ-DEVICE-IDENTITY complete with host/fake-network, Go, named gates, completeness, and final diff hygiene green; no QA review has run yet. Next action: spawn isolated QA Reviewer to inspect diff, docs, EK-003 closure bar, EK-011 Partial status, and test evidence.
- 2026-05-01T14:11:08+02:00 - Diff hygiene rerun passed: `git diff --check`. Files changed since last update: none. Decision/blocker: no whitespace/conflict-marker issues after doc edits. Next action: Executor completion.
- 2026-05-01T14:11:08+02:00 - Executor completion. Files changed since last update: none. Decision/blocker: PREREQ-DEVICE-IDENTITY implementation and evidence are complete for Executor role; no final QA review performed. Required host/fake-network Flutter, Go, named gates, completeness, and diff hygiene passed; EK-011 full welcome/key-package lifecycle remains out of scope. Next action: hand off to isolated QA Reviewer.
- 2026-05-01T14:10:45+02:00 - Source-doc update completed. Files changed since last update: source matrix EK-003/EK-011 rows and remaining-partial owner table, `test-inventory.md` EK-003/EK-011 crosswalks, breakdown summary/current-session/ordered/reopened/final-verdict rows. Decision/blocker: EK-003 now records `Covered`; EK-011 remains `Partial` with only device-bound admission dependency satisfied. Next action: rerun `git diff --check` after doc edits, then complete Executor handoff.
- 2026-05-01T14:10:45+02:00 - Diff hygiene rerun starting: `git diff --check`. Files inspected since last update: markdown source docs. Decision/blocker: verify doc patches did not introduce whitespace issues. Next action: record pass/fail.
- 2026-05-01T14:09:21+02:00 - Diff hygiene check passed: `git diff --check`. Files changed since last update: none. Decision/blocker: no whitespace or conflict-marker issues reported. Next action: update source matrix, inventory, and breakdown evidence docs for EK-003/EK-011 without running QA review.
- 2026-05-01T14:09:21+02:00 - Source-doc update starting. Files inspected since last update: source matrix EK-003/EK-011 rows, inventory EK-003/EK-011 crosswalks, breakdown current-status/reopened/final-verdict rows. Decision/blocker: EK-003 closure bar is met by green host/fake-network evidence; EK-011 must remain `Partial` with only device-bound admission prerequisite recorded. Next action: patch docs and then record Executor completion.
- 2026-05-01T14:05:55+02:00 - Named gate passed: `./scripts/run_test_gates.sh completeness-check` (`700/700` test files classified). Files changed since last update: none. Decision/blocker: completeness classifier is green. Next action: run `git diff --check`.
- 2026-05-01T14:05:55+02:00 - Diff hygiene check starting: `git diff --check`. Files inspected since last update: none. Decision/blocker: verify no whitespace/conflict-marker issues in the dirty diff. Next action: record pass/fail.
- 2026-05-01T14:05:32+02:00 - Named gate passed: `./scripts/run_test_gates.sh groups` (101 tests). Files changed since last update: none. Decision/blocker: canonical group messaging gate is green after focused fixture updates. Next action: run named gate `completeness-check`.
- 2026-05-01T14:05:32+02:00 - Named gate starting: `./scripts/run_test_gates.sh completeness-check`. Files inspected since last update: none. Decision/blocker: verify repository completeness classifier after implementation and tests. Next action: record pass/fail.
- 2026-05-01T14:05:02+02:00 - Narrowed group edge smoke rerun passed: `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart` (7 tests). Files changed since last update: none after fixture fix. Decision/blocker: high fan-out fake-network member/device hydration is green and network counters remain scoped to chat publishes. Next action: rerun named gate `groups`.
- 2026-05-01T14:05:02+02:00 - Named gate rerun starting: `./scripts/run_test_gates.sh groups`. Files inspected since last update: none. Decision/blocker: confirm full group gate after edge fixture fix. Next action: record pass/fail and fix only in-scope regressions.
- 2026-05-01T14:04:40+02:00 - Group edge fixture fix applied. Files changed since last update: `group_edge_cases_smoke_test.dart`. Decision/blocker: high fan-out now hydrates member/device rosters for all added users before simultaneous sends, resets network counters after hydration, and filters stored membership system rows from chat-message assertions. Next action: rerun edge smoke, then rerun named gate `groups`.
- 2026-05-01T14:03:09+02:00 - Narrowed group messaging smoke rerun passed: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart` (13 tests). Files changed since last update: assertion filter for stored membership system rows. Decision/blocker: group messaging smoke now accepts member-added system rows while checking regular chat-message convergence. Next action: rerun named gate `groups`.
- 2026-05-01T14:03:09+02:00 - Named gate rerun starting: `./scripts/run_test_gates.sh groups`. Files inspected since last update: none. Decision/blocker: confirm full group gate after smoke fixture fixes. Next action: record pass/fail and fix only in-scope regressions.
- 2026-05-01T14:01:42+02:00 - Group gate fixture fix applied. Files changed since last update: `group_messaging_smoke_test.dart`. Decision/blocker: round-robin and MS004 smoke fixtures now broadcast member-added events after listeners start so existing fake-network members hydrate new member/device rosters before accepting live traffic. Next action: rerun `group_messaging_smoke_test.dart`, then rerun `groups` gate.
- 2026-05-01T14:00:03+02:00 - Named gate failed: `./scripts/run_test_gates.sh groups`. Files inspected since last update: `scripts/run_test_gates.sh`, `group_messaging_smoke_test.dart`, gate output. Decision/blocker: three gate failures reported; narrowed `group_messaging_smoke_test.dart` shows two fixture failures where existing members reject later member traffic because member-added hydration was missing under the new fail-closed sender membership/device binding. Next action: fix the smoke fixtures to hydrate added members, rerun the narrowed file, then rerun the gate.
- 2026-05-01T13:59:26+02:00 - Go PREREQ/device block passed: `cd go-mknoon && go test ./node -run 'TestPREREQDeviceIdentity|TestGroupTopicValidator_Device' -v`. Files changed since last update: none. Decision/blocker: device-pattern node validator tests are green. Next action: run named gate `groups`.
- 2026-05-01T13:59:26+02:00 - Named gate starting: `./scripts/run_test_gates.sh groups`. Files inspected since last update: none. Decision/blocker: run the canonical group gate after targeted Flutter and Go coverage. Next action: record pass/fail and fix only in-scope regressions.
- 2026-05-01T13:58:59+02:00 - Go validator block passed: `cd go-mknoon && go test ./internal ./node -run 'TestMarshalParseGroupEnvelope|TestGroupMember|TestGroupTopicValidator_.*Device|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch|TestGroupTopicValidator_SpoofedPublicKey|TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature|TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies' -v`. Files changed since last update: none. Decision/blocker: envelope round trip, group member serialization, transport binding, device binding, spoofed key, and forged security-event signature tests are green. Next action: run the narrowed PREREQ/device Go block.
- 2026-05-01T13:58:59+02:00 - Go PREREQ/device block starting: `cd go-mknoon && go test ./node -run 'TestPREREQDeviceIdentity|TestGroupTopicValidator_Device' -v`. Files inspected since last update: none. Decision/blocker: verify any PREREQ-named or device-pattern node tests. Next action: record pass/fail and fix in-scope Go regressions.
- 2026-05-01T13:58:17+02:00 - Integration block rerun passed: `flutter test --no-pub test/features/groups/integration/group_multi_device_convergence_test.dart test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_new_member_onboarding_test.dart test/features/groups/integration/group_resume_recovery_test.dart` (65 tests). Files changed since last update: none. Decision/blocker: fake-network multi-device, invite round trip, onboarding, and resume recovery are green together. Next action: start Go envelope/config validator tests.
- 2026-05-01T13:58:17+02:00 - Go validator block starting: `cd go-mknoon && go test ./internal ./node -run 'TestMarshalParseGroupEnvelope|TestGroupMember|TestGroupTopicValidator_.*Device|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch|TestGroupTopicValidator_SpoofedPublicKey|TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature|TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies' -v`. Files inspected since last update: none. Decision/blocker: verify envelope device fields plus transport/public-key validation in Go. Next action: record pass/fail and fix in-scope Go regressions.
- 2026-05-01T13:57:42+02:00 - Narrowed integration reruns passed: `invite_round_trip_test.dart` (14 tests), `group_new_member_onboarding_test.dart` (6 tests), and `group_resume_recovery_test.dart` (39 tests). Files changed since last update: none after the fixture fix. Decision/blocker: all remaining integration files are green independently with sender membership fixtures restored. Next action: rerun full integration block.
- 2026-05-01T13:57:42+02:00 - Integration block rerun starting: `flutter test --no-pub test/features/groups/integration/group_multi_device_convergence_test.dart test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_new_member_onboarding_test.dart test/features/groups/integration/group_resume_recovery_test.dart`. Files inspected since last update: none. Decision/blocker: confirm the four-file fake-network integration block is green after fixture fixes. Next action: record rerun outcome.
- 2026-05-01T13:57:15+02:00 - Resume integration fixture fix applied. Files changed since last update: `group_resume_recovery_test.dart`. Decision/blocker: cursor/backlog tests now register their legacy offline senders as group members before replay so the new device/member binding does not reject fixtures that are not meant to test unknown-sender behavior. Next action: rerun `group_resume_recovery_test.dart`, then full integration block.
- 2026-05-01T13:55:02+02:00 - Narrowed integration triage starting: rerun `invite_round_trip_test.dart`, `group_new_member_onboarding_test.dart`, and `group_resume_recovery_test.dart` separately. Files inspected since last update: none. Decision/blocker: isolate the five remaining combined-block failures without changing scope. Next action: record exact per-file failures and fix only in-scope device-identity regressions.
- 2026-05-01T13:54:43+02:00 - Integration block rerun failed: `flutter test --no-pub test/features/groups/integration/group_multi_device_convergence_test.dart test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_new_member_onboarding_test.dart test/features/groups/integration/group_resume_recovery_test.dart`. Files inspected since last update: combined output. Decision/blocker: five failures remain in the combined integration block; output is dominated by flow logs, so the next step is to rerun remaining integration files separately to isolate exact failing cases. Next action: run narrowed integration reruns for invite round trip, onboarding, and resume recovery.
- 2026-05-01T13:53:45+02:00 - Integration block rerun starting: `flutter test --no-pub test/features/groups/integration/group_multi_device_convergence_test.dart test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_new_member_onboarding_test.dart test/features/groups/integration/group_resume_recovery_test.dart`. Files inspected since last update: none. Decision/blocker: confirm fake-network multi-device, invite round trip, onboarding, and resume recovery after device-roster fake fixes. Next action: record rerun outcome.
- 2026-05-01T13:53:45+02:00 - Narrowed integration reruns passed: `flutter test --no-pub test/features/groups/integration/group_multi_device_convergence_test.dart` (6 tests) and `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name "multi-group resume doesn't burst"` (1 test). Files changed since last update: none. Decision/blocker: same-member sibling device convergence and corrected resume burst fixture are green in isolation. Next action: rerun full integration block.
- 2026-05-01T13:52:02+02:00 - Integration fixes applied. Files changed since last update: `fake_group_pubsub_network.dart`, `group_test_user.dart`, `group_resume_recovery_test.dart`. Decision/blocker: fake member identity now includes all registered sibling devices for a peer, bridge-backed fake sends carry sender device/transport ids, local fake sends store device transport ids, and the resume burst fixture now seeds `other-peer` as a group member. Next action: rerun narrowed integration files and then full integration block.
- 2026-05-01T13:49:58+02:00 - Integration block failed: `flutter test --no-pub test/features/groups/integration/group_multi_device_convergence_test.dart test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_new_member_onboarding_test.dart test/features/groups/integration/group_resume_recovery_test.dart`. Files inspected since last update: combined output. Decision/blocker: seven failures; visible issues include same-user sibling device messages rejected as unbound in fake-network convergence and a resume-recovery burst assertion seeing zero drained messages. Next action: run failing integration files separately, fix in-scope fake/device propagation defects, then rerun the integration block.
- 2026-05-01T13:49:21+02:00 - Test block passed on rerun: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` (241 tests). Files changed since last update: none. Decision/blocker: live and offline message/listener paths are green with sender device binding. Next action: start fake-network integration block.
- 2026-05-01T13:49:21+02:00 - Test block starting: `flutter test --no-pub test/features/groups/integration/group_multi_device_convergence_test.dart test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_new_member_onboarding_test.dart test/features/groups/integration/group_resume_recovery_test.dart`. Files inspected since last update: none. Decision/blocker: verify fake-network multi-device, invite round trip, onboarding, and resume recovery. Next action: record pass/fail and fix in-scope failures.
- 2026-05-01T13:48:53+02:00 - Narrowed handler rerun passed: `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart` (45 tests). Files changed since last update: none. Decision/blocker: removed-sender replay setup correction is green. Next action: rerun full message/listener/offline block.
- 2026-05-01T13:48:53+02:00 - Test block rerun starting: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Files inspected since last update: none. Decision/blocker: confirm full live/offline message path after setup fix. Next action: record rerun outcome.
- 2026-05-01T13:48:31+02:00 - Message handler test setup fix applied. Files changed since last update: `handle_incoming_group_message_use_case_test.dart`. Decision/blocker: removed-sender replay test now persists the cutoff before accepting the pre-cutoff row. Next action: rerun handler test, then full message/listener/offline block.
- 2026-05-01T13:47:45+02:00 - Message/offline block failed, narrowed to `handle_incoming_group_message_use_case_test.dart`. Files inspected since last update: removed-sender replay test and incoming handler membership/removal cutoff logic. Decision/blocker: one existing test setup persisted the removal cutoff after the pre-cutoff delivery even though the handler requires the cutoff to admit removed-sender history; this is a test setup mismatch, not a production device-binding blocker. Next action: persist cutoff before the accepted pre-cutoff delivery and rerun handler/full message block.
- 2026-05-01T13:47:09+02:00 - Test block passed on rerun: `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart` (36 tests). Files changed since last update: none. Decision/blocker: per-device key distribution and listener binding regressions are green. Next action: start group message/listener/offline replay block.
- 2026-05-01T13:47:09+02:00 - Test block starting: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Files inspected since last update: none. Decision/blocker: verify live/offline sender device binding and no side effects on invalid devices. Next action: record pass/fail and fix in-scope failures.
- 2026-05-01T13:46:48+02:00 - Key block fix applied. Files changed since last update: `rotate_and_distribute_group_key_use_case_test.dart`. Decision/blocker: EK004 assertion now includes device-bound source/recipient fields in the canonical signed payload. Next action: rerun key distribution/listener block.
- 2026-05-01T13:46:48+02:00 - Test block rerun starting: `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart`. Files inspected since last update: none. Decision/blocker: confirm key distribution/listener behavior after assertion update. Next action: record rerun outcome.
- 2026-05-01T13:46:27+02:00 - Test block failed: `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart`. Files inspected since last update: key rotation EK004 assertion and key-update signature helper. Decision/blocker: single failure in old member-only signed payload expectation; actual payload correctly includes source and recipient device binding fields. Next action: update the EK004 assertion and rerun key block.
- 2026-05-01T13:46:02+02:00 - Test block passed on rerun: `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart` (68 tests). Files changed since last update: none. Decision/blocker: invite send/handle/accept legacy and signed paths are green with device-aware canonical payloads. Next action: start key distribution/listener block.
- 2026-05-01T13:46:02+02:00 - Test block starting: `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart`. Files inspected since last update: none. Decision/blocker: verify per-active-device targets and key update source/local recipient device binding. Next action: record pass/fail and fix in-scope failures.
- 2026-05-01T13:45:40+02:00 - Targeted invite/admission rerun passed: `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart --name "IJ002 rejects invalid invite signature|EC001 invalid invite accepts classify failures|IJ013 copied pending invite rejects wrong local identity"` (3 tests). Files changed since last update: none. Decision/blocker: canonical signing fixture fix restores expected verification and wrong-identity classification. Next action: rerun full invite/admission block.
- 2026-05-01T13:45:40+02:00 - Test block rerun starting: `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart`. Files inspected since last update: none. Decision/blocker: confirm surrounding invite/admission behavior after fixture fix. Next action: record rerun outcome.
- 2026-05-01T13:45:17+02:00 - Invite/admission fix applied. Files changed since last update: `handle_incoming_group_invite_use_case_test.dart`, `accept_pending_group_invite_use_case_test.dart`. Decision/blocker: test signing helpers now use `GroupInvitePayload.canonicalInviteSignedPayload()` so newly added device fields stay in the signed surface. Next action: rerun targeted failing invite/admission tests, then rerun the full invite/admission block.
- 2026-05-01T13:44:06+02:00 - Test block failed: `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart`. Files inspected since last update: failing assertions in handle/accept invite tests. Decision/blocker: failures are in-scope rejection ordering/classification: invalid signature test did not call fake `payload.verify`, EC001/IJ013 wrong-local-identity accepts returned `invalidPayload`, and one additional handle invite IJ002 failure needs targeted rerun detail. Next action: inspect resolver ordering, fix classification without broad behavior changes, and rerun targeted/full invite block.
- 2026-05-01T13:43:33+02:00 - Test block passed: `flutter test --no-pub test/core/database/migrations/062_group_member_device_identities_test.dart test/core/database/helpers/group_members_db_helpers_test.dart test/core/database/integration/full_migration_chain_test.dart` (18 tests). Files changed since last update: none. Decision/blocker: migration 062, helper persistence, and full migration chain are green. Next action: start invite/admission application block.
- 2026-05-01T13:43:33+02:00 - Test block starting: `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart`. Files inspected since last update: none. Decision/blocker: verify device-bound send/handle/accept admission behavior while preserving legacy invite paths. Next action: record pass/fail and fix in-scope failures.
- 2026-05-01T13:43:10+02:00 - Test block passed on rerun: `flutter test --no-pub test/features/groups/domain/models/group_member_test.dart test/features/groups/domain/models/group_invite_payload_test.dart` (27 tests). Files changed since last update: none. Decision/blocker: model roster round trip and invite canonical device binding regressions are green. Next action: start DB migration/helper/full-chain block.
- 2026-05-01T13:43:10+02:00 - Test block starting: `flutter test --no-pub test/core/database/migrations/062_group_member_device_identities_test.dart test/core/database/helpers/group_members_db_helpers_test.dart test/core/database/integration/full_migration_chain_test.dart`. Files inspected since last update: none. Decision/blocker: verify `devices_json` migration, helper persistence, and full migration chain. Next action: record pass/fail and fix in-scope failures.
- 2026-05-01T13:42:51+02:00 - Test block rerun starting: `flutter test --no-pub test/features/groups/domain/models/group_member_test.dart test/features/groups/domain/models/group_invite_payload_test.dart`. Files changed since last update: `group_invite_payload_test.dart` fixture typing. Decision/blocker: compile fix is test-only and in scope. Next action: record rerun outcome.
- 2026-05-01T13:42:32+02:00 - Test block failed: `flutter test --no-pub test/features/groups/domain/models/group_member_test.dart test/features/groups/domain/models/group_invite_payload_test.dart`. Files inspected since last update: `group_invite_payload_test.dart`. Decision/blocker: compile error at `group_invite_payload_test.dart:158` because nested fixture access was inferred as `Object?`; `group_member_test.dart` completed its five tests before the compile failure. Next action: fix test fixture typing and rerun this exact block.
- 2026-05-01T13:41:58+02:00 - Test block starting: `flutter test --no-pub test/features/groups/domain/models/group_member_test.dart test/features/groups/domain/models/group_invite_payload_test.dart`. Files inspected since last update: none. Decision/blocker: run model and signed invite payload regressions first to catch schema/canonical payload errors before wider suites. Next action: record pass/fail and fix in-scope failures.
- 2026-05-01T13:41:40+02:00 - Implementation pass completed. Files changed since last update: group member model/config propagation, migration `062`, DB version wiring, invite/admission device binding, key distribution/listener binding, live/offline message/reaction binding, fake-network device identities, Go envelope/config validator, and focused model/DB/invite/Go regressions. Decision/blocker: implementation stayed within PREREQ device identity and EK-011 admission prerequisite; no full welcome lifecycle, revocation UX, trust UI, or relay schema expansion added. Next action: run required direct test/gate blocks and record exact outcomes.
- 2026-05-01T13:21:41+02:00 - Owner-file inspection completed. Files inspected since last update: `group_member.dart`, `group_members_db_helpers.dart`, migrations `017/057/061`, `lib/main.dart` diff, group repository/fake repository, `group_config_payload.dart`, invite payload/policy/send/handle/accept/listener/auth files, key rotation/listener/signature files, send/handle/listen/drain offline group message files, fake group pubsub/user files, Go internal envelope and node pubsub/group files plus diffs. Decision/blocker: dirty tree already contains invite signature/policy, MS-002 transport binding, fake multi-device routing, and key-update signature groundwork; missing scope is first-class device roster plus device-aware binding through these existing paths. Next action: implement roster model/migration/config propagation and update invite/key/replay/Go validation seams.
- 2026-05-01T13:18:52+02:00 - Executor local pass started. Files inspected since last update: session plan, `git status --short`, migration stop condition via `lib/main.dart` and missing `062_group_member_device_identities.dart`. Decision/blocker: `062` is free and DB version is 61, so execution may proceed; worktree is heavily dirty and owner-file diffs must be inspected before edits. Next action: inspect owner files and existing dirty diffs before implementation.
- 2026-05-01T13:17:40+02:00 - Executor spawn retry. Files inspected since last update: no owner files. Decision/blocker: first `codex exec` attempt exited before child start due CLI option order; no code/test/doc work from child. Next action: relaunch Executor with global options before `exec`.
- 2026-05-01T13:16:48+02:00 - Executor spawning. Files inspected since last update: extracted contract and migration stop condition. Decision/blocker: spawn isolated `codex exec` Executor with `model=gpt-5.5` and `model_reasoning_effort=xhigh`; no code owner files touched yet. Next action: wait bounded interval, then inspect progress/evidence.
- 2026-05-01T13:16:29+02:00 - Contract extracted. Files inspected since last update: source matrix EK-003/EK-011 rows, breakdown PREREQ-DEVICE-IDENTITY row, inventory EK-003/EK-011 crosswalks, gate definitions, migration list, `lib/main.dart`. Decision/blocker: scope is first-class group member device roster plus invite/admission, Go envelope/config validation, key distribution, offline replay, and fake-network proofs; required direct tests/gates are the plan-listed Flutter/Go suites plus `groups`, `completeness-check`, and `git diff --check`; `062` is still free and DB version is 61. Next action: spawn isolated Executor.
- 2026-05-01T13:15:31+02:00 - Orchestrator started and contract extraction pending. Files inspected since last update: skill file, session plan, `git status --short`, live device commands. Decision/blocker: `codex exec` is available for spawned isolation; worktree is heavily dirty; live profile shows host/fake-network first, iOS supporting devices booted, Android paired proof external-fixture-blocked because `adb` is not installed and `emulator-5556` is absent. Next action: extract the contract before spawning Executor.

## Device/Relay Proof Profile

Live check already refreshed at `2026-05-01T13:05:34+02:00`:

- `flutter devices --machine`: single iOS default `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` booted; paired iOS `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` booted; spare iOS `1B098DFF-6294-407A-A209-BBF360893485` booted; physical iOS `00008030-001A6D2801BB802E`; Android `emulator-5554`; macOS; Chrome.
- `xcrun simctl list devices available`: confirms the iOS simulators above.
- `adb devices`: failed because `adb` is not installed; Android paired target `emulator-5556` is missing.
- Current row starts with host/fake-network proof. Paired iOS may be supporting if a real-device proof is needed after the host matrix is green.
- Android paired proof is external-fixture-blocked until both `adb` and `emulator-5556` are available.
- When env is unset, execution must inline this for any single-device group-real-network supporting gate:

```bash
FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g ./scripts/run_test_gates.sh group-real-network-nightly
```

Optional paired-iOS supporting proof, only after the host/fake-network device matrix is green:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_device_real.dart -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

## real scope

This session owns the repo-owned device identity prerequisite for EK-003, plus the EK-011 portion where welcome/admission must bind to the intended device before a later welcome/key-package session can validate richer package semantics.

Implement first-class group device identity data as a narrow compatibility layer:

- Keep `GroupMember.peerId` as the member/account identity used by existing membership rows.
- Add a first-class per-member device roster, with at least device id, transport/libp2p peer id, device signing public key, device ML-KEM/key-package public material, active/revoked status if needed, and a stable key-package id/hash if the implementation needs to prove package binding without owning full welcome-package validation.
- Persist the roster with the group member, expected intake path `lib/core/database/migrations/062_group_member_device_identities.dart` and matching helper/model changes. If migration `062` is already claimed by a concurrent dirty-tree change, stop and refresh this plan before coding rather than silently choosing another version.
- Carry that device roster through `groupConfig` snapshots and membership events so Go validators, Flutter listeners, and offline replay all see the same member-to-device binding.
- Bind invite/admission to the recipient device, not only the recipient member peer id.
- Bind Go group envelopes or an explicitly versioned successor envelope to sender member id plus sender device id/transport peer id and verify the registered device key before accepting messages, reactions, and security-relevant membership events.
- Distribute group keys to eligible active devices, not just member rows, and reject direct key updates from an unbound source device or to the wrong local recipient device.
- Bind offline replay to the sender device identity and reject valid-looking member payloads from an invalid or mismatched device before message/key/member side effects.

What does not change:

- Do not implement full MLS welcome/key-package semantics, weak-key validation, signed welcome admission proof, key-package tombstones, or stale/wrong-recipient welcome repair beyond the device-bound fields needed here. Those remain `PREREQ-WELCOME-KEY-PACKAGE`.
- Do not implement device compromise recovery, per-device revocation UX, sibling approval flows, trust-center UI, or safety-number UI. Those are later product/security rows.
- Do not replace libp2p, relay storage, message encryption algorithms, or group roles/permission policy.
- Do not mark EK-011 `Covered` from this session alone.

## closure bar

Good enough for this prerequisite means EK-003 can be closed only after all of these are true in code and tests:

- A valid bound device for member B can send a group message/reaction or security-relevant membership event, receive/apply a direct group key update, accept an invite intended for that device, and replay offline group traffic.
- An invalid device that claims B's member identity, uses B's member public key, or has a valid-looking payload but an unbound device id, device public key, key package, or transport Peer ID is rejected before local state mutation, key promotion, event-log append, message persistence, normal listener emission, mailbox drain success, or notification side effects.
- Group member device roster data round-trips through model, DB migration, repository/helper, `groupConfig`, invite payload signed data, Go config/envelope validation, key distribution, and offline replay paths.
- Legacy member-level Peer ID/public-key behavior remains backward compatible for existing rows/tests until all active call sites write the new roster.
- Direct host/fake-network proof is green. Paired iOS proof may supplement but cannot replace missing host regressions.

## source of truth

- Active session contract: this plan file once status is `execution-ready`.
- Source matrix: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`, especially EK-003 and EK-011.
- Reopened prerequisite row: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`, row `PREREQ-DEVICE-IDENTITY`.
- Current evidence ledger: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, especially EK-003 and EK-011 crosswalks.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md`; the public gate command is `./scripts/run_test_gates.sh <gate>`.
- On disagreement, current code/tests win over stale prose; `test-gate-definitions.md` wins for named-gate membership; this plan wins only for the current session scope unless repo evidence proves it stale.

## session classification

`implementation-ready`

Reason: the blocker is repo-owned missing model/protocol/test coverage. Host/fake-network proof can start immediately. Android paired proof is fixture-blocked, but it is supplemental and not required to make the host implementation safe.

## exact problem statement

EK-003 asks for member identity key, device key, and Peer ID binding. Current code only proves a member-level binding:

- Dart `GroupMember` is keyed by `groupId` and `peerId`, with member public key and ML-KEM public key fields but no device roster.
- `GroupInvitePolicy.allowedDevices` currently stores the recipient peer id; it is device-shaped naming but not first-class device identity.
- `sendGroupInvite`, `handleIncomingGroupInvite`, and `acceptPendingGroupInvite` bind invite/admission to recipient peer id, not a specific registered device/key-package identity.
- `rotateAndDistributeGroupKey` sends one encrypted key update per non-self member with an ML-KEM key, not per active member device.
- Go v3 `GroupEnvelope` carries `senderId`, `senderPublicKey`, signature, epoch, and encrypted payload. PubSub validation binds `senderId` to the libp2p transport Peer ID and the member public key, but there is no separate sender device id/key-package binding.
- Offline replay already carries `transportPeerId`/relay `from` checks, but it has no device identity/key-package validation equivalent to live PubSub.
- `group_multi_device_convergence_test.dart` proves same-peer sibling behavior in fakes, but it does not prove valid-device versus invalid-device production behavior.

User-visible behavior that must improve: only a registered, bound device for a group member can send, receive key material, accept admission material, or apply security-relevant group events. An unbound sibling, spoofed transport Peer ID, or mismatched device key must fail closed without creating ghost UI rows, group membership, promoted keys, or replay side effects.

Behavior that must stay unchanged: existing valid group messaging, invites, key rotation, membership changes, offline replay, role authorization, and recent MS-002 transport Peer ID proof must remain green.

## files and repos to inspect next

Production Dart model/persistence:

- `lib/features/groups/domain/models/group_member.dart`
- `lib/core/database/migrations/017_groups_tables.dart`
- `lib/core/database/migrations/057_group_member_permissions.dart`
- `lib/core/database/migrations/061_group_message_transport_peer_id.dart`
- `lib/core/database/migrations/062_group_member_device_identities.dart` expected new file if migration number is still free
- `lib/core/database/helpers/group_members_db_helpers.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/main.dart`

Invite/admission and key material:

- `lib/features/groups/domain/models/group_invite_payload.dart`
- `lib/features/groups/domain/models/group_invite_policy.dart`
- `lib/features/groups/domain/models/pending_group_invite.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/group_invite_listener.dart`
- `lib/features/groups/application/group_invite_auth.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_key_update_signature.dart`

Group events, live send, and replay:

- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`

Go:

- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/internal/group_envelope_test.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_authorization_forward_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`

Fakes/tests:

- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/features/groups/domain/models/group_member_test.dart`
- `test/features/groups/domain/models/group_invite_payload_test.dart`
- `test/core/database/helpers/group_members_db_helpers_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/groups/application/send_group_invite_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/integration/group_multi_device_convergence_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

## existing tests covering this area

- `test/features/groups/domain/models/group_member_test.dart` currently covers member map round-trip, role parsing, and equality by `(groupId, peerId)`.
- `test/features/groups/domain/models/group_invite_payload_test.dart` covers v1/v2 invite serialization, policy parsing, signature envelope validation, reuse policy, and malformed invite rejection.
- `test/features/groups/application/send_group_invite_use_case_test.dart`, `handle_incoming_group_invite_use_case_test.dart`, and `accept_pending_group_invite_use_case_test.dart` cover signed inline invite flow, missing ML-KEM handling, wrong recipient peer behavior, revocation/consumption, and repair-pending materialization failures.
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` covers role authorization, encrypting to non-self member ML-KEM keys, distribution ordering, timeouts, and skipped members without ML-KEM.
- `test/features/groups/application/group_key_update_listener_test.dart` covers direct key-update signature/authorization behavior.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` covers MS-002 transport Peer ID replay behavior, sender mismatch rejection, future-epoch placeholders, removed-sender cutoff behavior, and encrypted replay.
- `test/features/groups/integration/group_multi_device_convergence_test.dart` covers same-peer sibling fake-network delivery/locality, but not production valid-device versus invalid-device admission.
- `go-mknoon/node/pubsub_test.go` covers member serialization, transport Peer ID matching, transport mismatch rejection, bad signatures, spoofed public keys, non-member rejection, and member config updates.
- `go-mknoon/internal/group_envelope_test.go` covers v3 envelope round-trip and basic parser validation.

Missing: no test proves a registered device roster, no test proves unbound sibling/device rejection while the member id is valid, no Go test verifies device key-package binding, no key-update test proves per-device recipients/source device validation, and no offline replay test rejects an invalid device with an otherwise valid member id.

## regression/tests to add first

Add failing regressions before production changes, then make them pass:

- Model/DB: `group_member_test.dart` and `group_members_db_helpers_test.dart` prove a member with two active devices round-trips device id, transport Peer ID, device signing key, ML-KEM/key-package public material, and status; legacy rows without device JSON expose a safe fallback device only where explicitly allowed.
- Migration: `test/core/database/migrations/062_group_member_device_identities_test.dart` proves existing `group_members` rows gain the device roster column without data loss and fresh install schema has it.
- Invite/admission: invite payload tests prove signed inner payload and policy bind the recipient member plus recipient device; send/handle/accept tests prove wrong device id, wrong transport Peer ID, wrong key package, or missing local device identity rejects before group/member/key/pending-consumption/mailbox side effects.
- Go live envelope: internal/node tests prove a valid bound device is accepted, a same-member unbound device is rejected, a device public-key mismatch is rejected, and a transport Peer ID mismatch is still rejected.
- Key distribution: rotation/listener tests prove distribution targets every active eligible device, skips revoked/ineligible devices, and rejects direct key updates from unbound source devices or to the wrong local recipient device before key promotion/save.
- Offline replay: drain/listener tests prove valid bound-device replay is accepted and invalid-device replay with a valid member id creates no normal message, key, event-log, listener, or notification side effect.
- Integration: extend `group_multi_device_convergence_test.dart` with distinct device identities under the same member and an invalid cloned sibling that cannot send, apply key updates, or admit itself.

## step-by-step implementation plan

1. Dirty-worktree intake:
   - Run `git status --short`.
   - Inspect every intended owner file before editing. Treat all pre-existing dirty changes as user/prior-session work.
   - If a relevant file already contains an attempted device identity implementation, work with it and update this plan only if the architecture differs materially.
   - If migration `062` already exists or `lib/main.dart` database version has moved past `61`, stop and refresh the migration path before writing code.

2. Add the model and persistence seam:
   - Add a small `GroupMemberDeviceIdentity` value object in `group_member.dart` or an adjacent groups domain model if local style prefers separation.
   - Add `GroupMember.devices` with validation helpers for active devices, lookup by device id and transport Peer ID, and a controlled legacy fallback.
   - Add expected migration `062_group_member_device_identities.dart` to add `group_members.devices_json`; wire it through `lib/main.dart`.
   - Update `GroupMember.fromMap/toMap`, `group_members_db_helpers.dart`, repository implementations, and in-memory fakes.
   - Stop here and reconsider if model tests show existing equality/hash behavior would silently collapse distinct member/device identities. Member equality should stay member-scoped; device identity should be explicit, not hidden in equality.

3. Propagate device roster through group config and membership events:
   - Update `group_config_payload.dart` to include device roster data in member maps and state hash canonicalization.
   - Update create/add/remove/role/member-sync paths that serialize `groupConfig.members`.
   - Preserve existing public key and ML-KEM fields for backward compatibility while device-aware code uses the device roster.
   - Add regression tests proving signed metadata/membership hash changes when device roster changes and old configs still parse safely.

4. Bind invite send and admission to device identity:
   - Change invite construction to target a recipient device identity/key-package, not only `recipientPeerId`.
   - Rename or reinterpret `allowedDevices` only if tests make the old peer-id use impossible; otherwise add explicit `allowedDeviceIds`/recipient-device fields and keep legacy parsing guarded.
   - Include recipient member id, recipient device id, recipient transport Peer ID, key-package id/hash/public key material, and inviter source device identity in the signed payload.
   - In handle/accept paths, require local device identity to match the bound recipient device before materialization. Wrong/missing device identity must reject before deleting retryable pending state unless the failure is a hard security failure already covered by existing policy.

5. Bind Go group envelopes to device identity:
   - Extend `go-mknoon/node.GroupMember` with device roster data and update config JSON compatibility.
   - Extend `go-mknoon/internal.GroupEnvelope` or add a clearly versioned successor envelope with sender member id plus sender device id/transport Peer ID/device public key.
   - Update publish paths to sign data that binds group id, epoch, ciphertext, sender member id, sender device id, and sender transport Peer ID.
   - Update validator lookup to find member by member id, then active device by sender device id/transport Peer ID, then verify the signature with the registered device key. Keep existing transport Peer ID mismatch rejection.
   - Keep legacy v3 behavior only if necessary for existing persisted traffic, and make that compatibility explicit in tests.

6. Make key distribution device-scoped:
   - Update rotation to build recipient device targets from active member devices with ML-KEM/key-package public material.
   - Sign direct key update payloads with source member plus source device identity and bind recipient device id/transport Peer ID.
   - Update `GroupKeyUpdateListener` to verify source member role/permission, source device binding, source device signature, and local recipient device binding before `group:updateKey`, event-log append, or key save.

7. Make offline replay device-scoped:
   - Extend `group_offline_replay_envelope.dart` and replay-drain validation to carry and verify sender member id, sender device id, sender transport Peer ID, and the device signature/key binding.
   - For relay-provided `from`, require it to match the sender device transport Peer ID where present.
   - Reject invalid-device replay before saving normal messages, enriching sparse live copies, appending event log entries, emitting listener messages, or showing notifications.

8. Update fake network and integration harnesses:
   - Update `FakeGroupPubSubNetwork` and `GroupTestUser` so same-user devices have distinct device identities while sharing a member identity.
   - Keep existing same-peer sibling behavior tests green where they are intentionally testing local-device state, but add explicit invalid-device tests that cannot pass by sharing `peerId`.

9. Run the direct tests and gates below.

10. After implementation only, update source docs:
   - Update the source matrix EK-003 row to `Covered` only if the closure bar is met with concrete files/commands.
   - Update EK-011 notes only to say the device-bound admission prerequisite is satisfied; leave welcome/key-package-specific blockers Partial until `PREREQ-WELCOME-KEY-PACKAGE` closes them.
   - Update `test-inventory.md` EK-003/EK-011 crosswalks with exact evidence.
   - Update the session breakdown row and ledger with commands, caveats, and residual blockers.
   - Update this plan's execution evidence/status in-place or hand it to the closure-audit session, depending on the pipeline controller's convention.

## risks and edge cases

- Legacy rows without device rosters could be rejected too aggressively. Add an explicit fallback policy and tests for upgraded users.
- Same account with multiple devices must not duplicate group member rows or collapse device identities into one transport identity.
- An invalid device may have a valid member id and member public key; validators must fail on device binding before state mutation.
- Key rotation can partially distribute to devices. Existing timeout/continue behavior should remain, but key promotion must not accept updates from unbound devices.
- Offline replay must be equivalent to live validation; replay must not trust relay `from` alone.
- Invite repair-pending behavior must stay retryable for material failures, while hard security/device mismatch failures should fail closed consistently with current invite policy.
- State hashes and signed config snapshots must include device roster data, otherwise stale configs could roll back devices.
- Dirty worktree may contain prior-session edits in the same files. Do not revert them; re-read before each patch.

## exact tests and gates to run

Regression-first and direct Dart tests:

```bash
flutter test --no-pub test/features/groups/domain/models/group_member_test.dart test/features/groups/domain/models/group_invite_payload_test.dart
flutter test --no-pub test/core/database/migrations/062_group_member_device_identities_test.dart test/core/database/helpers/group_members_db_helpers_test.dart test/core/database/integration/full_migration_chain_test.dart
flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
flutter test --no-pub test/features/groups/integration/group_multi_device_convergence_test.dart test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_new_member_onboarding_test.dart test/features/groups/integration/group_resume_recovery_test.dart
```

Go tests:

```bash
cd go-mknoon && go test ./internal ./node -run 'TestMarshalParseGroupEnvelope|TestGroupMember|TestGroupTopicValidator_.*Device|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch|TestGroupTopicValidator_SpoofedPublicKey|TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature|TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies' -v
cd go-mknoon && go test ./node -run 'TestPREREQDeviceIdentity|TestGroupTopicValidator_Device' -v
```

Named gates and hygiene:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Supporting device/relay gate only after host proof is green and only if execution needs real-network confidence:

```bash
FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g ./scripts/run_test_gates.sh group-real-network-nightly
```

Optional paired-iOS supporting proof:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_device_real.dart -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

## known-failure interpretation

- Direct tests added or modified for this session must be green. A failure in those files is a session blocker unless the executor records a pre-existing failure before edits and proves it is unrelated to device identity.
- `groups` and `completeness-check` failures must be triaged against `Test-Flight-Improv/test-gate-definitions.md` known-failure notes and the dirty-worktree baseline. Do not claim closure if the failure is in a touched path or any device/invite/key/replay path.
- If `group-real-network-nightly` or paired-iOS proof is skipped, record it as supplemental not run; do not use missing Android paired proof as a blocker for this host/fake-network-first prerequisite.
- If `adb devices` still fails or `emulator-5556` remains absent, classify Android paired proof as external-fixture-blocked, not a repo implementation failure.

## done criteria

- `Status: execution-ready` plan was followed or updated with a documented reason before implementation deviated.
- Device identity/key-package data is first-class in member model/persistence, group config, invite/admission, Go envelope/config validation, key distribution, and offline replay.
- At least one valid-device case and one invalid-device case is proven for live Go validation, invite/admission, direct key update, offline replay, and fake-network multi-device integration.
- Invalid-device attempts produce no unauthorized group/member/key/message/event-log/listener/notification side effects.
- Existing member-level valid behavior, transport Peer ID mismatch rejection, signature rejection, invite repair-pending behavior, and key rotation ordering remain green.
- Required direct tests, Go tests, `groups`, `completeness-check`, and `git diff --check` pass or have a documented non-touched pre-existing failure that does not affect this closure.
- EK-003 source docs are updated with exact evidence only after tests pass. EK-011 remains Partial except for a note that device-bound admission prerequisite is done.

## scope guard

Non-goals:

- No full welcome/key-package validation matrix, weak ML-KEM validation, stale package tombstones, or signed welcome admission proof.
- No per-device revocation/compromise recovery product flow.
- No new UI warnings, trust-center surfaces, or safety-number redesign.
- No broad relay-server schema work unless offline replay cannot carry device proof without an existing opaque envelope field. Prefer app/Go envelope validation first.
- No replacing current role/permission semantics or changing group types.
- No mass refactor of every group test. Update only tests needed for direct device identity regressions and compilation.

Overengineering signals:

- Designing a generic account/device registry for all app features before the group prerequisite is green.
- Implementing MLS commits or a full key-package lifecycle under this session.
- Adding user-visible verification UX to close a protocol/model gap.
- Treating paired-device or Android fixture work as required before host/fake-network regressions prove the core behavior.

## accepted differences / intentionally out of scope

- The shipped app currently treats member peer id and transport Peer ID as the same identity in many paths. This session may keep compatibility for legacy rows but must not treat that as EK-003 closure for new device-aware paths.
- Full EK-011 closure remains out of scope. This session can satisfy only the device-bound admission dependency; `PREREQ-WELCOME-KEY-PACKAGE` must still own valid/stale/malformed/wrong-recipient/weak/signed package validation.
- Android paired proof is unavailable in the current fixture state and is intentionally left as external-fixture-blocked.
- Paired iOS proof is supporting evidence, not a substitute for direct host tests.

## dependency impact

- EK-003 depends directly on this session and should not be marked `Covered` until this plan's closure bar is met.
- EK-011 can cite this session only for device-bound admission. It still depends on `PREREQ-WELCOME-KEY-PACKAGE`.
- EK-008/device compromise recovery, future per-device revocation, and trust/verification UI should build on the device roster produced here rather than inventing a separate model.
- Any later signed commit/audit, remote event family, or replay freshness work should include the device identity fields in its signed/canonical payloads.

## dirty-worktree handling

- Current intake saw a heavily dirty tree, including source docs, likely owner files, Go files, Dart group files, tests, and many untracked plan files.
- The executor must not revert or overwrite changes it did not make.
- Before editing any touched file, read the current file and, when useful, `git diff -- <path>` to understand pre-existing edits.
- If a touched file has concurrent changes that already solve part of this plan, preserve them and narrow implementation to the remaining gap.
- If concurrent changes make the exact plan unsafe, stop and update this plan with a new evidence-backed path before implementation.

## source docs to update after execution

Do not update these during planning-only work. After implementation and verification:

- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- This plan file's execution evidence/status if the pipeline convention keeps per-session evidence in the plan.

## Reviewer Findings

Reviewer verdict: sufficient as finalized.

- Missing files caught by review: the likely owner list alone was too narrow. A first-class device model also needs `group_config_payload.dart`, group member DB migration/helper/repository paths, group event serializers/listeners, offline replay envelope/drain paths, Go internal envelope/config structs, and fakes.
- Stale assumption caught by review: `allowedDevices` is not proof of device identity because current send/accept code populates it with recipient peer id.
- Regression contract risk: direct Go and offline replay invalid-device tests must be added first, not only multi-device happy path tests.
- Overreach risk: full welcome/key-package validation and device revocation are intentionally deferred.
- Minimum sufficiency adjustment: make database/config propagation, offline replay, Go internal envelope/config, and source-doc updates explicit; mark Android paired proof external-fixture-blocked.

## Arbiter Decision

Structural blockers in draft: none after the reviewer adjustments above are included in the plan.

Incremental details:

- Exact final wire field names may differ if implementation finds an established local naming convention, but the semantics in the closure bar are mandatory.
- If migration `062` is already claimed before execution starts, update this plan with the concrete next migration number before code edits.

Accepted differences:

- This prerequisite does not close full EK-011 welcome/key-package validation.
- Paired-iOS and single-device real-network gates are supporting, not primary closure evidence.
- Android paired proof remains fixture-blocked.

## Final verdict

`accepted`

## Final plan

Use this file as the doc-scoped implementation plan for `PREREQ-DEVICE-IDENTITY`. Execute host/fake-network regressions first, implement the smallest first-class group device roster and binding path, run direct tests and named gates, then update source docs only after evidence is green.

## Structural blockers remaining

None in the plan. Execution must stop only if migration numbering or concurrent dirty-tree changes invalidate the planned owner paths.

## Incremental details intentionally deferred

- Exact final field names for device/key-package JSON.
- Optional paired-iOS supporting proof if host coverage is already sufficient.
- Android paired proof until fixtures exist.

## Accepted differences intentionally left unchanged

- No full welcome/key-package lifecycle.
- No per-device revocation/compromise recovery flow.
- No UI verification work.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/models/group_invite_payload.dart`
- `lib/features/groups/domain/models/group_invite_policy.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/core/database/migrations/017_groups_tables.dart`
- `lib/core/database/migrations/057_group_member_permissions.dart`
- `lib/core/database/migrations/061_group_message_transport_peer_id.dart`
- `lib/core/database/helpers/group_members_db_helpers.dart`
- `lib/main.dart`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/pubsub.go`
- `test/features/groups/integration/group_multi_device_convergence_test.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`

## Why the plan is safe or unsafe to implement now

Safe to implement now. The plan is narrow to the missing device identity prerequisite, starts with host/fake-network regressions, protects current dirty-tree work, requires direct invalid-device proofs before source-row closure, and leaves unrelated welcome/key-package, revocation, UI, and Android fixture work out of scope.
