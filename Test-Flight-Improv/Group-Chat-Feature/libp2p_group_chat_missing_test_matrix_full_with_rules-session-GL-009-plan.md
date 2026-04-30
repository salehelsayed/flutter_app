# GL-009 Session Plan - Settings Versioning, Actor Signature, and Canonical Group State Hash

Status: execution-ready

## Planning Progress

- 2026-04-30 20:35:30 CEST - Arbiter completed. Files inspected since last update: reviewed scoped fixture recovery handoff in this plan. Decision/blocker: no structural blockers remain; `test/features/groups/integration/group_resume_recovery_test.dart` is a valid one-pass GL-009 recovery owner because the required row gates fail only on its stale unsigned metadata fixture. Next action: hand off one fresh scoped fixture execution pass; do not edit source matrix, test inventory, breakdown ledger, or production code in planning.
- 2026-04-30 20:35:30 CEST - Arbiter started. Files inspected since last update: reviewer result and scoped recovery section. Decision/blocker: classify findings for reuse safety. Next action: mark reusable if no structural blocker remains.
- 2026-04-30 20:35:30 CEST - Reviewer completed. Files inspected since last update: scoped recovery section, failing fixture, helper/listener evidence, required gates. Decision/blocker: sufficient with no structural blocker; scope, owner file, tests/gates, done criteria, and guard prevent production weakening or closure-doc drift. Next action: Arbiter pass.
- 2026-04-30 20:35:30 CEST - Planner completed. Files inspected since last update: `group_resume_recovery_test.dart`, `group_config_payload.dart`, `group_message_listener.dart`, `bridge.dart`, `fake_bridge.dart`, `scripts/run_test_gates.sh`, `Test-Flight-Improv/test-gate-definitions.md`. Decision/blocker: draft one scoped fixture recovery pass that signs only the integration helper's manual metadata envelopes using existing GL-009 helpers. Next action: Reviewer pass.
- 2026-04-30 20:35:30 CEST - Evidence Collector completed. Files inspected since last update: this plan recovery input, `group_resume_recovery_test.dart` `publishMetadataUpdate`, current metadata actor-event helpers, listener verification seam, bridge sign/verify helpers, fake bridge behavior, and gate definitions. Decision/blocker: evidence confirms production sign/verify landed and focused owner tests passed; required gates fail because the integration fixture still emits unsigned `group_metadata_updated`. Next action: Planner pass.

## Execution Progress

- 2026-04-30 20:44:57 CEST - phase: QA Reviewer spawned/running; files inspected/touched: Executor summary, scoped fixture diff/status, this plan progress; command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app --dangerously-bypass-approvals-and-sandbox`; decision/blocker: Executor reported all required recovery checks passed and no blockers; next action: QA Reviewer validates scope adherence, behavior, and evidence without editing code.
- 2026-04-30 20:43:52 CEST - phase: scoped diff check finish / Executor verdict; files inspected/touched: scoped diff-check output, `test/features/groups/integration/group_resume_recovery_test.dart`, this plan progress; command: `git diff --check -- test/features/groups/integration/group_resume_recovery_test.dart Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md`; decision/blocker: passed with no output; all required recovery checks passed and no blocker remains for this scoped fixture pass; next action: hand off ready for QA review.
- 2026-04-30 20:43:27 CEST - phase: scoped diff check start; files inspected/touched: plan progress; command: `git diff --check -- test/features/groups/integration/group_resume_recovery_test.dart Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md`; decision/blocker: running final required check after all test gates passed; next action: record diff-check result and final Executor verdict.
- 2026-04-30 20:43:18 CEST - phase: broad integration suite finish; files inspected/touched: integration suite output, plan progress; command: `flutter test --no-pub test/features/groups/integration`; decision/blocker: passed, 116 tests; no remaining integration fixture failure observed; next action: run scoped `git diff --check`.
- 2026-04-30 20:42:55 CEST - phase: broad integration suite start; files inspected/touched: plan progress; command: `flutter test --no-pub test/features/groups/integration`; decision/blocker: running third required check after focused fixture and groups gate passed; next action: record result.
- 2026-04-30 20:42:45 CEST - phase: named gate finish; files inspected/touched: groups gate output, plan progress; command: `./scripts/run_test_gates.sh groups`; decision/blocker: passed, 94 tests; previous unsigned metadata fixture blocker is cleared in this gate; next action: run `flutter test --no-pub test/features/groups/integration`.
- 2026-04-30 20:42:17 CEST - phase: named gate start; files inspected/touched: plan progress; command: `./scripts/run_test_gates.sh groups`; decision/blocker: running second required check after focused fixture proof passed; next action: record gate result.
- 2026-04-30 20:42:08 CEST - phase: focused fixture test finish; files inspected/touched: focused test output, plan progress; command: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "offline member reconnects after repeated metadata edits and converges to the final metadata state"`; decision/blocker: passed, 1 test; trace shows `payload.sign`, Charlie/Bob `payload.verify`, Bob convergence to newer metadata, and stale older replay ignored; next action: run `./scripts/run_test_gates.sh groups`.
- 2026-04-30 20:41:40 CEST - phase: focused fixture test start; files inspected/touched: plan progress; command: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "offline member reconnects after repeated metadata edits and converges to the final metadata state"`; decision/blocker: running first required check after signed fixture patch; next action: record result.
- 2026-04-30 20:41:28 CEST - phase: scoped fixture implementation complete; files inspected/touched: `test/features/groups/integration/group_resume_recovery_test.dart`, this plan progress; command: none; decision/blocker: `publishMetadataUpdate` now builds one shared `groupConfig`, signs a canonical metadata actor payload through `callSignPayload`, embeds `actorEvent`, and configures Bob/Charlie `payload.verify` success plus admin deterministic `payload.sign`; next action: run focused metadata convergence test.
- 2026-04-30 20:40:47 CEST - phase: scoped fixture Executor recovery start; files inspected/touched: plan recovery section, `test/features/groups/integration/group_resume_recovery_test.dart`, `group_config_payload.dart`, `group_info_wired.dart`, `group_message_listener.dart`, `bridge.dart`, `fake_bridge.dart`; command: scoped `sed`/`rg`/`git diff` reads; decision/blocker: execute only `Scoped Fixture Recovery Pass - 2026-04-30`, preserve existing dirty-tree edits, and patch only the metadata convergence fixture plus this progress log; next action: implement signed metadata actor envelope fixture.
- 2026-04-30 20:38:10 CEST - phase: scoped fixture recovery contract extraction started; files inspected/touched: this plan `Scoped Fixture Recovery Pass - 2026-04-30`, `test/features/groups/integration/group_resume_recovery_test.dart`, `group_config_payload.dart`, `group_message_listener.dart`, `bridge.dart`, `fake_bridge.dart`; command: none; decision/blocker: executing only the scoped fixture recovery section, with production sign/verify and all unrelated dirty-tree edits preserved; next action: record exact scope/tests, then spawn Executor.
- 2026-04-30 20:38:10 CEST - phase: scoped fixture recovery contract extracted; files inspected/touched: this plan recovery section and owner fixture; command: none; decision/blocker: editable code owner is only `test/features/groups/integration/group_resume_recovery_test.dart` plus same-file imports, plan progress may be updated, required checks are the focused metadata convergence test, `./scripts/run_test_gates.sh groups`, `flutter test --no-pub test/features/groups/integration`, and scoped `git diff --check`; next action: spawn Executor with model `gpt-5.5` and reasoning effort `xhigh`.
- 2026-04-30 20:38:45 CEST - phase: Executor spawned/running; files inspected/touched: this plan progress section; command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app --dangerously-bypass-approvals-and-sandbox`; decision/blocker: fresh Executor is being launched for the scoped fixture recovery owner file only; next action: wait for Executor result, inspect fixture/plan delta, then run QA.

- 2026-04-30 20:07:42 CEST - phase: executor-start heartbeat; files inspected/touched: plan progress section only; command: none; decision/blocker: starting fresh implementation pass within GL-009 owner scope before inspecting implementation files; next action: extract plan contract, then inspect scoped group payload/listener/UI/test files.
- 2026-04-30 20:08:05 CEST - phase: contract extracted; files inspected/touched: plan `Fresh Implementation Pass Reopen - 2026-04-30`; command: `sed`/`rg` plan contract reads; decision/blocker: execute only GL-009 publish-time signing and receive-time verification in owner files, focused tests first, no matrix/inventory/breakdown/schema/Go/relay/doc edits; next action: inspect scoped helper/listener/UI/test files and preserve existing partial work.
- 2026-04-30 20:08:20 CEST - phase: focused test start; files inspected/touched: plan progress section only; command: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`; decision/blocker: running first required focused listener suite before edits to confirm GL-009 RED surface; next action: record result, then inspect owner files.
- 2026-04-30 20:08:46 CEST - phase: focused test finish; files inspected/touched: listener test execution output and plan progress section; command: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`; decision/blocker: failed with 73 passed / 4 failed, matching GL-009-owned unsigned, valid signed verify-order, signed-payload mismatch, and invalid-signature actor-envelope tests; next action: inspect scoped helper/listener/UI/test files and wire missing sign/verify behavior.
- 2026-04-30 20:11:24 CEST - phase: owner-file inspection complete / edit start; files inspected/touched: `group_config_payload.dart`, `group_message_listener.dart`, `group_info_wired.dart`, `group_message_listener_test.dart`, `group_info_wired_test.dart`, supporting `update_group_metadata_use_case.dart`, `bridge.dart`, `fake_bridge.dart`; command: scoped `sed`/`rg`; decision/blocker: helper surface and `beforePersist` seam already exist, listener lacks pre-append verify and UI lacks `payload.sign`; next action: patch listener/UI plus focused fixtures/assertions only.
- 2026-04-30 20:14:44 CEST - phase: implementation patch complete / focused retest start; files inspected/touched: five GL-009 Dart owner files plus plan progress; command: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`; decision/blocker: patched receive-time state-hash plus actor-envelope verification before append/apply and updated signed metadata fixtures; next action: record listener retest result.
- 2026-04-30 20:15:15 CEST - phase: focused test finish; files inspected/touched: listener suite output and plan progress; command: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`; decision/blocker: passed, 77 tests; next action: run presentation focused suite `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`.
- 2026-04-30 20:15:33 CEST - phase: focused test start; files inspected/touched: plan progress section; command: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`; decision/blocker: running second required focused presentation suite after listener pass; next action: record presentation result and fix only GL-009-owned focused failures if any.
- 2026-04-30 20:16:02 CEST - phase: focused test finish; files inspected/touched: presentation suite output and plan progress; command: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`; decision/blocker: passed, 28 tests including signed actor envelope publish path and signing-failure abort coverage; next action: run scoped `git diff --check`.
- 2026-04-30 20:16:16 CEST - phase: scoped diff check start; files inspected/touched: plan progress section; command: `git diff --check -- lib/features/groups/application/group_config_payload.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_info_wired_test.dart Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md`; decision/blocker: focused tests passed, checking scoped whitespace/diff hygiene before broader host gates; next action: record diff-check result.
- 2026-04-30 20:16:46 CEST - phase: scoped diff check finish; files inspected/touched: diff-check output and plan progress; command: `git diff --check -- lib/features/groups/application/group_config_payload.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_info_wired_test.dart Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md`; decision/blocker: passed with no output; next action: run broader GL-009 host regression set in plan order.
- 2026-04-30 20:17:09 CEST - phase: broader host test start; files inspected/touched: plan progress section; command: `flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart`; decision/blocker: starting first broader GL-009 host regression after focused pass; next action: record result.
- 2026-04-30 20:17:30 CEST - phase: broader host test finish; files inspected/touched: update metadata use-case test output and plan progress; command: `flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart`; decision/blocker: passed, 6 tests; next action: run `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart`.
- 2026-04-30 20:17:46 CEST - phase: broader host test start; files inspected/touched: plan progress section; command: `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart`; decision/blocker: running create-group regression for signed canonical creation adjacency; next action: record result.
- 2026-04-30 20:18:06 CEST - phase: broader host test finish; files inspected/touched: create group use-case test output and plan progress; command: `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart`; decision/blocker: passed, 13 tests; next action: run `flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart`.
- 2026-04-30 20:18:20 CEST - phase: broader host test start; files inspected/touched: plan progress section; command: `flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart`; decision/blocker: running dissolve regression after create-group pass; next action: record result.
- 2026-04-30 20:18:38 CEST - phase: broader host test finish; files inspected/touched: dissolve group use-case test output and plan progress; command: `flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart`; decision/blocker: passed, 6 tests; next action: run `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`.
- 2026-04-30 20:18:50 CEST - phase: broader host test start; files inspected/touched: plan progress section; command: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`; decision/blocker: running group membership smoke regression; next action: record result.
- 2026-04-30 20:19:13 CEST - phase: broader host test finish; files inspected/touched: group membership smoke output and plan progress; command: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`; decision/blocker: passed, 23 tests; next action: run `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`.
- 2026-04-30 20:19:28 CEST - phase: broader host test start; files inspected/touched: plan progress section; command: `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`; decision/blocker: running database migration chain regression from GL-009 host set; next action: record result.
- 2026-04-30 20:20:10 CEST - phase: broader host test finish; files inspected/touched: full migration chain output and plan progress; command: `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`; decision/blocker: passed, 6 tests; next action: run broad application suite `flutter test --no-pub test/features/groups/application`.
- 2026-04-30 20:20:42 CEST - phase: broad application suite start; files inspected/touched: plan progress section; command: `flutter test --no-pub test/features/groups/application`; decision/blocker: starting broad groups application suite; known-failure rule applies only for unrelated MD-011 future-media replay if focused GL-009 evidence stays green; next action: record suite result.
- 2026-04-30 20:21:43 CEST - phase: broad application suite finish; files inspected/touched: broad application suite output, filtered rerun output, and plan progress; command: `flutter test --no-pub test/features/groups/application`; decision/blocker: failed with 510 passed / 1 failed; filtered rerun identifies the known plan-listed unrelated `drain_group_offline_inbox_use_case_test.dart` MD-011 future-media replay failure (`Expected: null`, got `GroupMessage(id: msg-md011-future-media-replay, groupId: group-1, isIncoming: true)`), with no GL-009 metadata/signature/state-hash failure; next action: run `./scripts/run_test_gates.sh completeness-check` and `./scripts/run_test_gates.sh groups` before final non-blocking classification.
- 2026-04-30 20:22:00 CEST - phase: named gate start; files inspected/touched: plan progress section; command: `./scripts/run_test_gates.sh completeness-check`; decision/blocker: starting required completeness gate after broad app suite known MD-011 failure; next action: record result.
- 2026-04-30 20:22:18 CEST - phase: named gate finish; files inspected/touched: completeness-check output and plan progress; command: `./scripts/run_test_gates.sh completeness-check`; decision/blocker: passed, 697/697 test files classified; next action: run `./scripts/run_test_gates.sh groups`.
- 2026-04-30 20:22:32 CEST - phase: named gate start; files inspected/touched: plan progress section; command: `./scripts/run_test_gates.sh groups`; decision/blocker: starting required groups gate; next action: record result.
- 2026-04-30 20:23:51 CEST - phase: named gate finish; files inspected/touched: groups gate output, `group_resume_recovery_test.dart` failing fixture read-only inspection, and plan progress; command: `./scripts/run_test_gates.sh groups`; decision/blocker: failed with 93 passed / 1 failed in `test/features/groups/integration/group_resume_recovery_test.dart` (`offline member reconnects after repeated metadata edits and converges to the final metadata state`) because its test helper publishes unsigned `group_metadata_updated`, now rejected with `GROUP_MESSAGE_LISTENER_METADATA_SIGNATURE_INVALID`; this is GL-009 behavior but fixture edit is outside the executor owner-file scope; next action: run final requested `flutter test --no-pub test/features/groups/integration` for exact standalone outcome, then finish blocked unless scope is expanded for that fixture.
- 2026-04-30 20:24:07 CEST - phase: broad integration suite start; files inspected/touched: plan progress section; command: `flutter test --no-pub test/features/groups/integration`; decision/blocker: running final requested broad integration command after groups gate failure to capture exact standalone outcome; next action: record result and final executor blocker/readiness status.
- 2026-04-30 20:24:55 CEST - phase: broad integration suite finish; files inspected/touched: broad integration output and plan progress; command: `flutter test --no-pub test/features/groups/integration`; decision/blocker: failed with 115 passed / 1 failed, same `group_resume_recovery_test.dart` unsigned metadata fixture rejected by GL-009 actor-envelope verification; next action: record Executor completion as blocked because required groups/integration gates remain red outside the allowed owner-file edit scope.
- 2026-04-30 20:25:13 CEST - phase: Executor complete; files inspected/touched: GL-009 owner files plus read-only failing integration fixture inspection and plan progress; command: none; decision/blocker: production/focused GL-009 owner scope is implemented and focused checks pass, but required `groups` and broad integration gates remain red on `group_resume_recovery_test.dart` unsigned metadata fixture outside the allowed executor edit scope; next action: hand off blocked result for QA/controller decision on expanding fixture scope.
- 2026-04-30 20:26:45 CEST - phase: QA start; files inspected/touched: plan progress section, Executor final result, scoped git status; command: spawned QA Reviewer with model `gpt-5.5` and reasoning effort `xhigh`; decision/blocker: Executor returned blocked due required `groups`/integration failures on an out-of-scope unsigned metadata fixture; next action: QA Reviewer validates code/test delta, scope, and blocker classification without editing source files.
- 2026-04-30 20:28:33 CEST - phase: final execution classification; files inspected/touched: plan progress section, Executor final result, scoped dirty-file status; command: QA Reviewer was interrupted after controller requested immediate classification and no further broad gates; decision/blocker: GL-009 is blocked pending a scoped fixture update to sign metadata in `test/features/groups/integration/group_resume_recovery_test.dart`; focused owner-file implementation is green but GL-009 is not ready for closure while required `./scripts/run_test_gates.sh groups` and `flutter test --no-pub test/features/groups/integration` remain red; next action: request/authorize a scoped fixture fix pass or leave GL-009 open.

## Recovery Input - Integration Metadata Fixture Signature Pass

- recorded: 2026-04-30 20:29:54 CEST
- blocker class: implementation-owned integration fixture gap
- blocker signature: GL-009 | implementation-owned integration fixture gap | `group_resume_recovery_test.dart` publishes unsigned `group_metadata_updated` in `publishMetadataUpdate`, causing `./scripts/run_test_gates.sh groups` and `flutter test --no-pub test/features/groups/integration` to fail after the GL-009 sign/verify implementation landed | likely owner file `test/features/groups/integration/group_resume_recovery_test.dart`; helper surface `lib/features/groups/application/group_config_payload.dart` should remain read-only unless a compile-safe helper import is missing.
- failing tests/gates:
  - `./scripts/run_test_gates.sh groups`: one failure in `test/features/groups/integration/group_resume_recovery_test.dart`.
  - `flutter test --no-pub test/features/groups/integration`: same fixture failure.
- missing contract: the integration test's metadata replay helper must build the same canonical signed metadata actor event required by GL-009, using the admin identity public/private keys and the existing `buildGroupMetadataActorEventPayload`, `canonicalizeGroupMetadataActorEventPayload`, and `buildSignedGroupMetadataActorEventEnvelope` helpers, so live and replayed metadata events remain valid under the new fail-closed receive path.
- scope guard: do not weaken production signature verification, do not grandfather unsigned metadata, do not edit source matrix/test inventory/breakdown ledger during this recovery, and do not change unrelated integration scenarios.
- next action: return to Plan Preparation for GL-009 and tighten this plan for one scoped fixture fix pass.

- 2026-04-30 20:05:35 CEST - Contract extraction started. Files inspected since last update: this plan, implementation-execution-qa-orchestrator skill, `git status --short`, `codex exec --help`. Command currently running: none. Decision/blocker: spawned-agent path is available through `codex exec`; extracting the fresh implementation pass contract before coding. Next action: record extracted scope/tests and spawn Executor.
- 2026-04-30 20:05:35 CEST - Contract extracted. Files inspected since last update: this plan including `Fresh Implementation Pass Reopen - 2026-04-30`. Command currently running: none. Decision/blocker: execute GL-009 only; owner files are `group_config_payload.dart`, `group_message_listener.dart`, `group_info_wired.dart`, `group_message_listener_test.dart`, and `group_info_wired_test.dart`; required focused tests start with `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` and `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`, then scoped `git diff --check`, then broader host gates after focused pass. Next action: spawn Executor with model `gpt-5.5` and reasoning effort `xhigh`.
- 2026-04-30 20:06:02 CEST - Executor spawned/running. Files inspected or touched since last update: this plan. Command currently running: `codex exec --model gpt-5.5 -c model_reasoning_effort="xhigh" ...`. Decision/blocker: fresh Executor is being launched with the GL-009 owner-file scope and required focused-first test order. Next action: wait for Executor result, then inspect owner-file delta and spawned result summary.
- 2026-04-30 20:06:46 CEST - Executor spawn retry. Files inspected or touched since last update: this plan. Command currently running: none. Decision/blocker: first `codex exec` invocation exited before child materialization because approval policy was passed as an unsupported subcommand option; no owner files were touched by that failed launch. Next action: retry with the approval policy on the top-level `codex` command.

## real scope

Implement the missing GL-009 behavior for group metadata/settings updates only:

- Publish-time metadata edits must include a Dart-visible signed actor event envelope in the `group_metadata_updated` system payload.
- Receive-time `group_metadata_updated` handling must verify that signed actor envelope before any local group/member mutation, `group:updateConfig` sync, metadata timeline row, or event-log append.
- The signed payload must bind the actor identity, event type, group id, update timestamp/version, canonical config state hash, and the exact group config being applied.
- Replay/tamper closure should reuse the existing monotonic metadata watermark and canonical state-hash checks, but add signature-envelope absence/mismatch/invalid-signature fail-closed behavior.

Do not implement unrelated governance features, new permissions UI, new group settings products, new network protocol work, new database schema, or broad event-log redesign.

## owner files

Recovery pass 1 owner files only:

- `lib/features/groups/application/group_config_payload.dart`: keep the partial actor-event helper implementation as the canonical owner for `actorEvent`, `signedPayload`, `signature`, `signatureAlgorithm`, canonical signed payload generation, and envelope/config equivalence checks. Only adjust it if the existing helper is structurally wrong for the publish/receive contract.
- `lib/features/groups/application/group_message_listener.dart`: verify `group_metadata_updated.actorEvent` with `payload.verify` before metadata state mutation, `group:updateConfig`, metadata timeline insertion, or event-log append.
- `lib/features/groups/presentation/screens/group_info_wired.dart`: call `payload.sign` before local metadata persistence, publish, or inbox-store; embed the signed actor envelope in the outgoing `group_metadata_updated` system payload.
- `test/features/groups/application/group_message_listener_test.dart`: preserve the four RED GL-009 signature-envelope tests unless they are structurally wrong, and make them pass by fixing production receive behavior.
- `test/features/groups/presentation/group_info_wired_test.dart`: add or tighten publish-path assertions for `payload.sign`, embedded `actorEvent`, no private-key leakage in the system payload, and signing-failure abort-before-persist/publish/inbox-store.

Supporting evidence files, not recovery edit owners unless current code unexpectedly lacks the required seam:

- `lib/features/groups/application/update_group_metadata_use_case.dart`: current evidence shows `updateGroupMetadata` already has `beforePersist`, so recovery should use that seam from `GroupInfoWired` instead of editing this file.
- `lib/core/bridge/bridge.dart`: current `callSignPayload` and `callVerifyPayload` command contracts are sufficient and should be reused unchanged.
- `lib/core/database/helpers/group_event_log_db_helpers.dart`: current canonical JSON helper is sufficient and should be reused unchanged.

Broader regression tests to rerun after the five owner files are fixed:

- `test/features/groups/application/update_group_metadata_use_case_test.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/dissolve_group_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`

## closure bar

GL-009 is good enough when an admin metadata edit produces a signed canonical actor event and every Dart receive path for `group_metadata_updated` rejects unsigned, invalidly signed, mismatched, stale, or state-hash-tampered metadata changes before they mutate local state or bridge config.

The closure bar is code plus direct tests. Documentation rows can move to `Covered` only after execution records passing direct tests/gates and exact evidence. This planning session must not update the matrix, inventory, or breakdown ledger.

## source of truth

- Current code and direct tests are authoritative over stale prose.
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md` is authoritative for GL-009 status and acceptance text.
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md` is authoritative for the one-session scope and expected gate list.
- `scripts/run_test_gates.sh` wins over `Test-Flight-Improv/test-gate-definitions.md` when gate definitions disagree.
- Existing `group_config_payload.dart` state hash/version helpers and `group_event_log_db_helpers.dart` canonical JSON helper should be reused instead of inventing a parallel canonicalization scheme.

## session classification

`implementation-ready`

No prerequisite is missing. The row is not already covered because current receive-time metadata handling verifies authorization and `stateHash`, but has no Dart-level signed actor envelope verification before applying metadata.

## exact problem statement

Current metadata updates already have deterministic `configVersion` and `stateHash`, and publish payloads include actor key material through `callGroupPublish`. The missing behavior is that the JSON system payload itself does not expose a signed actor event envelope, and `GroupMessageListener` does not verify such an envelope before accepting a received metadata config snapshot.

User-visible behavior that must improve: a forged or tampered group metadata event must not rename a group, change description/avatar, update members, sync the bridge validator, create a timeline row, or append an event-log record unless the actor signature and canonical config hash verify.

Behavior that must stay unchanged: valid admin metadata edits still update local UI state, publish and offline-store the metadata event, sync the bridge config, preserve avatar recovery behavior, and remain stale/replay protected by metadata timestamps.

## files and repos to inspect next

Production files:

- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/core/bridge/bridge.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/core/database/helpers/group_event_log_db_helpers.dart`
- `lib/features/groups/application/update_group_metadata_use_case.dart`
- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/dissolve_group_use_case.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/core/database/helpers/groups_db_helpers.dart`

Tests and gates:

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/application/update_group_metadata_use_case_test.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/dissolve_group_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- `update_group_metadata_use_case_test.dart` proves local metadata changes update the group row and that `buildGroupConfigPayload` emits deterministic `configVersion` plus canonical `stateHash` stable across member ordering and sensitive to tampering.
- `group_message_listener_test.dart` proves metadata updates apply valid config snapshots, ignore unauthorized senders, reject state-hash tampering, reject stale rollback after restart, keep duplicate metadata timeline rows idempotent, and preserve avatar recovery behavior.
- `group_info_wired_test.dart` proves admin edits publish `group_metadata_updated` payloads with actor peer/public/private key material at the bridge boundary and with version/hash-bearing `groupConfig`.
- `create_group_use_case_test.dart` already proves a signed canonical `group_created` event pattern and no private-key leakage in the persisted event payload.
- `group_event_log_db_helpers_test.dart` is adjacent evidence for canonical event-log payload ordering, idempotent replay, conflicting replay rejection, and hash-chain tamper detection.

Missing test coverage:

- No `group_message_listener_test.dart` regression currently fails an unsigned `group_metadata_updated` from an otherwise authorized admin.
- No receive-path test currently proves `payload.verify` is called with the actor public key, canonical signed metadata payload, and signature before `_applyAuthoritativeGroupConfigSnapshot`.
- No receive-path test currently proves a signed-payload/config mismatch or invalid signature fails closed while a valid signed payload still applies.
- No publish-path test currently proves `GroupInfoWired` calls `payload.sign` and embeds a signed actor event inside the JSON system payload itself.

## regression contract

Regression-first rule: add failing receive-path tests for unsigned/invalid/mismatched metadata actor envelopes before implementation, then add publish-path signing tests before changing the UI publish flow.

Implementation must preserve these existing contracts:

- `configVersion` remains derived from `lastMetadataEventAt` for metadata updates and remains stable/deterministic in `buildGroupConfigPayload`.
- `stateHash` remains canonical, member-order-stable, and sensitive to metadata/member tampering.
- Valid admin metadata events still apply after signature verification and still sync `group:updateConfig`.
- Unauthorized senders, stale metadata timestamps, duplicate exact replays, and state-hash mismatches still fail closed or remain idempotent as current tests require.
- Event-log append for metadata events happens only after authorization, stale-check pass, state-hash validation, and actor signature verification.
- Signing failure on the local admin edit path must not produce a publish/inbox-store call and must not persist a new local metadata state as if a signed settings change occurred.

## regression/tests to add first

Add the receive-path RED tests first in `test/features/groups/application/group_message_listener_test.dart`:

1. Authorized admin metadata event with valid `stateHash` but no signed actor envelope is ignored with no group mutation, no `group:updateConfig`, no timeline row, and no event-log append.
2. Valid signed actor envelope applies the metadata change and records evidence that `payload.verify` used the actor public key, canonical signed payload JSON, and signature before config sync.
3. Signed-payload mismatch fails closed, for example the signed payload binds one `groupConfig` or `stateHash` while the outer event carries a different config.
4. `payload.verify` returning `{ok: true, valid: false}` or `{ok: false}` fails closed.
5. Existing stale/replay and duplicate metadata tests are updated to use valid signed actor envelopes so the monotonic-version contract remains covered under the new signature requirement.

Then add publish-path tests in `test/features/groups/presentation/group_info_wired_test.dart`:

1. Admin metadata edit calls `payload.sign` before `group:publish`, embeds `signature`, `signatureAlgorithm: ed25519`, and canonical `signedPayload` in `group_metadata_updated`, and the signed payload includes actor peer id, username, public key, event type, group id, updatedAt/configVersion, stateHash, and exact groupConfig.
2. The published and inbox-stored system payloads do not include `senderPrivateKey`, actor private key, or any other private key in the signed payload.
3. Signing failure prevents local metadata persistence, publish, inbox-store, and misleading success UI.

Keep `update_group_metadata_use_case_test.dart` as the version/hash proof; add only a small helper-level canonical payload test there if the implementation places metadata actor-event builders in `group_config_payload.dart`.

## step-by-step implementation plan

1. Add metadata actor-event helper functions to `lib/features/groups/application/group_config_payload.dart`.
   - Build an unsigned payload with `schemaVersion: 1`, `eventType: group_metadata_updated`, `groupId`, `updatedAt`, `actor` `{peerId, username, publicKey}`, `groupConfigVersion`, `groupConfigStateHash`, and the exact `groupConfig`.
   - Canonicalize with `canonicalizeGroupEventLogPayload` so signing and verification use the same stable JSON ordering as the existing group event log.
   - Provide a validator that checks the outer system payload and signed payload agree on event type, group id, updatedAt, config version, state hash, and full config before bridge signature verification is trusted.
2. Add a narrow pre-persist signing barrier to `updateGroupMetadata`.
   - Keep the public behavior unchanged for existing callers by adding an optional callback such as `beforePersist(GroupModel updated)`.
   - Run the callback after validation and candidate `GroupModel` creation, but before `groupRepo.updateGroup(updated)`.
   - If the callback throws, do not persist the new metadata and let the caller surface the existing save-error path.
3. Update `GroupInfoWired` metadata save flow.
   - Fetch members and build `groupConfig` from the candidate `GroupModel` inside the `beforePersist` callback.
   - Build and sign the canonical actor-event payload with `callSignPayload(bridge: widget.bridge, dataToSign: canonicalPayload, privateKey: identity.privateKey)`.
   - If signing fails or returns an empty signature, throw before local persistence, `callGroupPublish`, `group:inboxStore`, and local success messaging that claims remote propagation.
   - Add the signed actor envelope to `sysText` under a single explicit field such as `actorEvent` containing `signedPayload`, `signature`, and `signatureAlgorithm`.
4. Update `GroupMessageListener` metadata receive flow.
   - For `group_metadata_updated`, after authorization and stale checks but before `appendSystemEventLog()` and `_handleGroupMetadataUpdated`, verify the actor event envelope.
   - Fail closed when the envelope is missing, malformed, uses a non-`ed25519` algorithm, references a different `groupId`, event type, actor, updatedAt, config version, state hash, or config, or when `callVerifyPayload` returns false.
   - Require the signed actor peer id to match `senderId`.
   - Use the current stored sender member public key as the preferred verification key; if no trusted public key exists for the sender, fail closed rather than accepting a self-asserted key. The signed actor public key must match the trusted member public key when present.
   - Emit a narrow flow event such as `GROUP_MESSAGE_LISTENER_METADATA_SIGNATURE_INVALID` or `GROUP_MESSAGE_LISTENER_METADATA_SIGNATURE_MISSING` for diagnostics, without leaking payload contents.
5. Preserve existing metadata behavior after verification.
   - Leave `isGroupConfigStateHashValid`, `_applyAuthoritativeGroupConfigSnapshot`, `_syncGroupConfig`, avatar download/retry behavior, timeline message generation, and metadata watermark semantics intact except for test fixture updates.
   - Ensure `appendSystemEventLog()` stores the already-verified actor envelope as part of the payload and is not called for unsigned/invalid metadata events.
6. Update direct tests in the order listed above.
   - Use `FakeBridge.responses['payload.verify'] = {'ok': true, 'valid': true}` for valid receive events and inspect `bridge.sentMessages` to assert canonical data/signature/public key.
   - Use existing config builders for `stateHash` so tests exercise the same canonical hash path as production.
   - Keep old unsigned metadata fixture expectations only where the test is explicitly proving fail-closed behavior.
7. Stop if evidence shows Go already attaches a verifiable metadata signature into the Dart event map that can be consumed directly. In that case, adapt `GroupMessageListener` to verify that existing field and do not add a second signed envelope.

## risks and edge cases

- Legacy unsigned metadata events will fail closed. That is intentional for GL-009 closure, but tests should make the compatibility decision explicit.
- Existing groups whose stored admin member lacks a public key cannot verify metadata actor signatures. Fail closed for this row; do not invent a trust-on-first-use fallback in this session.
- A malicious event could carry a valid signature over a different config. The signed-payload/outer-payload equivalence check is mandatory before state apply.
- State-hash validation and signature validation are both required. A valid signature over a tampered hash or a valid hash without signature is insufficient.
- Stale events must remain ignored without mutating state; a stale valid signature is not a newer version.
- Duplicate exact replays should remain idempotent and should not create duplicate timeline rows.
- Bridge verification timeout or bridge error must be treated as invalid, matching `callVerifyPayload` false-return semantics.
- Signing failure must happen before local metadata persistence through the pre-persist callback. Do not rely on a rollback-after-save path unless the callback approach proves impossible against current code.

## exact tests and gates to run

Focused direct tests:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart
flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart
flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart
flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart
git diff --check
```

Row and named gates:

```bash
flutter test --no-pub test/features/groups/application
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh groups
flutter test --no-pub test/features/groups/integration
```

Supporting/non-required external proof:

```bash
FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly
```

## Device/Relay Proof Profile

Classification: host-only closure is sufficient for GL-009.

Reasoning: the uncovered behavior is a Dart publish/receive contract for metadata-event signing and verification. It is exercised through deterministic host tests using `FakeBridge` for `payload.sign` and `payload.verify`, plus existing fake-network group integration gates. The real-network nightly command currently runs `integration_test/multi_relay_failover_test.dart` with `MKNOON_REQUIRE_MULTI_RELAY=true`; it proves multi-relay fixture delivery/failover, not the metadata actor-signature acceptance rule.

Therefore `group-real-network-nightly` is supporting release confidence only and is not required to mark GL-009 covered. No live device or relay availability check was run during planning because the plan does not require device/relay proof. If a reviewer later decides to require it, the executor must first record exact `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` values and run the command above; missing envs must be recorded as fixture-blocked, not skipped evidence.

## known-failure interpretation

- Treat failures in the focused direct tests as GL-009 blockers unless they are plainly caused by unrelated dirty-worktree state and can be isolated with a clean focused rerun.
- The broad `flutter test --no-pub test/features/groups/application` command has prior matrix evidence of an unrelated MD-011 future-media replay failure. If that exact failure recurs, record it as pre-existing/non-blocking only if all GL-009 focused tests, `./scripts/run_test_gates.sh groups`, and `git diff --check` pass.
- Any new failure involving `group_message_listener_test.dart`, `group_info_wired_test.dart`, metadata state hash/version, `payload.sign`, `payload.verify`, event-log append, or metadata timeline rows is GL-009-owned until proven otherwise.
- `completeness-check` failures are GL-009-owned if the executor adds or reclassifies test files. If only existing test files are edited, a completeness failure may still be pre-existing but must be recorded with the missing path/classification.

## done criteria

- Valid admin metadata edits produce a signed actor event envelope in the JSON system payload and no private key leaks into that payload.
- Receive-time `group_metadata_updated` rejects missing, malformed, mismatched, or invalid signatures before local state mutation, bridge config sync, timeline insert, or event-log append.
- Receive-time `group_metadata_updated` still rejects canonical `stateHash` tampering and stale version rollback.
- Valid signed metadata events still apply config, sync the bridge, and create one expected timeline row.
- Exact focused tests and required gates above have been run and outcomes recorded.
- Matrix/inventory/breakdown updates are performed only by the execution or closure step after evidence exists, not by this planning session.

## scope guard

Non-goals:

- Do not implement a new group governance/event-sourcing architecture.
- Do not add a new database table, migration, or durable actor-signature index unless the executor finds current event-log append cannot store the verified payload at all.
- Do not change Go libp2p PubSub signing, peer scoring, relay behavior, or group encryption.
- Do not redesign member role permissions or settings UI.
- Do not broaden to membership add/remove/role/dissolve signed envelopes unless the exact helper extraction is needed and existing behavior is preserved.
- Do not make `group-real-network-nightly` a blocking GL-009 closure gate unless new evidence shows the host tests cannot exercise the signature rule.

Overengineering signals:

- Adding trust-on-first-use key acceptance for missing actor keys.
- Introducing a second canonical JSON implementation.
- Adding product-visible settings version UI.
- Changing unrelated feed, push, media, or notification behavior to make broad gates pass.

## accepted differences / intentionally out of scope

- Existing Go `group:publish` signs/encrypts group messages internally, but GL-009 needs a Dart-visible signed actor event envelope for metadata state changes. The plan intentionally adds that Dart-level contract rather than treating Go transport signing as sufficient evidence.
- Initial group creation already has a signed canonical event-log payload; this session reuses that pattern for metadata but does not retrofit every membership event type.
- Device/relay proof is recommended release evidence, not a blocker for this host-code metadata signature gap.
- Legacy unsigned metadata events are not preserved as trusted input in this row. They fail closed until a future compatibility plan defines a safe migration policy.

## dependency impact

- GL-009 closure supports later governance, moderation, and state-convergence rows that assume metadata settings changes have signed actor provenance and deterministic state hashes.
- If this plan changes to require a database schema or new event-log architecture, dependent rows that rely on group event-log closure must be revisited.
- If the executor cannot require trusted actor public keys for old groups, future compatibility/migration work should be split into a separate session rather than weakening GL-009 fail-closed behavior.

## reviewer / arbiter closure bar

Reviewer must answer whether the plan is sufficient as-is, sufficient with adjustments, or insufficient, and must specifically check:

- Does the plan add RED tests before implementation?
- Does receive-time verification happen before mutation, bridge sync, timeline row, and event-log append?
- Does the signature bind the exact config and canonical state hash?
- Does the plan avoid broad Go/network/device scope?
- Are exact tests and known-failure interpretations clear enough for implementation?

Arbiter stop rule:

- If the reviewer finds no structural blocker, mark the plan reusable and stop.
- If the reviewer finds a structural blocker, patch this file once, then run one final reviewer and arbiter pass.
- Incremental naming preferences or optional extra tests are deferred unless they change implementation safety.

## Final verdict

Reusable and execution-ready for GL-009 only.

## Final plan

Implement a host-code metadata actor-signature contract: sign the canonical metadata actor event before local persistence/publish, verify that signature before receive-time metadata apply, and keep the existing config version/state-hash/replay protections intact.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- Exact helper function names can be chosen during implementation as long as `group_config_payload.dart` remains the canonical owner and no second canonical JSON scheme is introduced.
- Real-network nightly evidence can be collected later as supporting release confidence, but is not required for GL-009 closure.

## Accepted differences intentionally left unchanged

- Go transport signing remains separate from the Dart-visible metadata actor event required by this row.
- Non-metadata membership and dissolve event signing is out of scope for this GL-009 session.
- Legacy unsigned metadata events fail closed rather than being grandfathered into trust.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/update_group_metadata_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/core/bridge/bridge.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/core/database/helpers/group_event_log_db_helpers.dart`
- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/dissolve_group_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/core/database/helpers/groups_db_helpers.dart`
- `test/features/groups/application/update_group_metadata_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/dissolve_group_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`

## Why the plan is safe to implement now

The plan targets one observed missing contract, adds RED tests before code, uses existing bridge signing/verification and canonical JSON helpers, avoids DB/network/product-scope expansion, defines exact fail-closed points, and records how to classify known broad-gate failures without hiding GL-009 regressions.

## Pre-Execution Dirty Worktree Snapshot

Recorded by controller before fresh GL-009 execution handoff on 2026-04-30 20:04:14 CEST with `git status --short`.

The worktree remains broadly dirty from prior rollout/user work. For this fresh handoff, GL-009-owned files are limited to the current plan plus these owner files/tests:

```text
 M lib/features/groups/application/group_config_payload.dart
 M lib/features/groups/application/group_message_listener.dart
 M lib/features/groups/presentation/screens/group_info_wired.dart
 M test/features/groups/application/group_message_listener_test.dart
 M test/features/groups/presentation/group_info_wired_test.dart
?? Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md
```

All other dirty paths in `git status --short` must be treated as pre-existing or other-row work unless execution makes a GL-009-scoped, explicitly recorded change to them.

Recorded by controller before GL-009 execution on 2026-04-30 19:17:36 CEST with `git status --short`.

The worktree was already broadly dirty from prior rollout/user work. Scoped GL-009-relevant paths already dirty before execution:

```text
 M Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md
 M lib/features/groups/application/group_config_payload.dart
 M lib/features/groups/application/group_message_listener.dart
 M lib/features/groups/presentation/screens/group_info_wired.dart
 M test/core/database/integration/full_migration_chain_test.dart
 M test/features/groups/application/create_group_use_case_test.dart
 M test/features/groups/application/dissolve_group_use_case_test.dart
 M test/features/groups/application/group_message_listener_test.dart
 M test/features/groups/application/update_group_metadata_use_case_test.dart
 M test/features/groups/integration/group_membership_smoke_test.dart
 M test/features/groups/presentation/group_info_wired_test.dart
?? Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md
```

## Execution Result

Prior execution status: blocked

Recorded by controller-local verification fallback on 2026-04-30 19:28:42 CEST after the fresh execution child was closed for failing to persist a verdict.

Blocker class: implementation-owned execution incomplete.

The spawned execution child left scoped GL-009 code/test deltas, but did not finish the required production contract or record an execution verdict. The current on-disk implementation adds metadata actor-event helpers and RED receive-path tests, but production code still does not call `payload.sign` in `GroupInfoWired` and does not call `payload.verify` or `extractGroupMetadataActorEventVerificationData` in `GroupMessageListener` before metadata apply/event-log append.

Commands run by controller-local verification fallback:

```text
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart
git diff --check -- lib/features/groups/application/group_config_payload.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_info_wired_test.dart Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md
```

Results:

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` failed: 73 passed, 4 failed. The failing tests are GL-009-owned RED tests:
  - `authorized admin metadata event with valid state hash but no signed actor envelope is ignored` mutated the group to `Renamed Group` instead of staying `Test Group`.
  - `group_metadata_updated refreshes group metadata and stores a timeline event` did not call `payload.verify` before `group:updateConfig`.
  - `signed group_metadata_updated payload mismatch is ignored` mutated the group to `Outer Name` instead of staying `Test Group`.
  - `invalid group_metadata_updated actor signature is ignored` mutated the group to `Renamed Group` instead of staying `Test Group`.
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart` passed, but this is not sufficient GL-009 closure evidence because the publish-path test still does not assert `payload.sign` or an embedded `actorEvent` envelope.
- `git diff --check` passed for the scoped GL-009 files.

Changed files observed in scoped execution diff:

- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md`

Closure may not proceed for GL-009. The source matrix row must remain `Partial`, and the row cannot be accepted until a fresh implementation pass wires publish-time signing and receive-time verification before mutation, then reruns the focused GL-009 tests successfully.

## Recovery Input

Recorded by pipeline controller on 2026-04-30 19:36:21 CEST for same-session recovery pass 1.

- blocker class: implementation-owned execution incomplete
- blocker signature: GL-009 | implementation-owned execution incomplete | `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` failed four GL-009 signature-envelope tests | owner files `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`
- failing tests:
  - `authorized admin metadata event with valid state hash but no signed actor envelope is ignored`
  - `group_metadata_updated refreshes group metadata and stores a timeline event`
  - `signed group_metadata_updated payload mismatch is ignored`
  - `invalid group_metadata_updated actor signature is ignored`
- missing contract:
  - Publish path must call `payload.sign`, embed `actorEvent.signedPayload`, `actorEvent.signature`, and `actorEvent.signatureAlgorithm`, and fail before persistence/publish/inbox-store when signing fails.
  - Receive path must verify `actorEvent` with `payload.verify` before group mutation, bridge config sync, metadata timeline insertion, or event-log append.
  - Receive path must reject missing, mismatched, malformed, and invalid-signature metadata actor envelopes without mutating group state.
- current touched owner files:
  - `lib/features/groups/application/group_config_payload.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
- recovery instruction: tighten this same GL-009 plan around the partial actor-envelope implementation, preserve the RED tests unless they are structurally wrong, finish only the publish-time signing and receive-time verification contract, then rerun the focused GL-009 tests and scoped `git diff --check`.

## Pre-Recovery Execution Dirty Worktree Snapshot

Recorded by pipeline controller before GL-009 same-session recovery execution on 2026-04-30 19:43:27 CEST with `git status --short`.

The worktree is broadly dirty from prior rollout/user work. The scoped GL-009 recovery owner paths observed dirty before this recovery execution are:

```text
 M lib/features/groups/application/group_config_payload.dart
 M lib/features/groups/application/group_message_listener.dart
 M lib/features/groups/presentation/screens/group_info_wired.dart
 M test/features/groups/application/group_message_listener_test.dart
 M test/features/groups/presentation/group_info_wired_test.dart
?? Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md
```

The executor must not revert unrelated dirty files. Scope comparison after recovery should treat changes to the five owner files above plus this plan file as GL-009-scoped unless inspection shows unrelated edits.

## Recovery Pass 1 Execution Contract

Classification: `implementation-ready`

Run mode: implementation-committed gap-closure. This is not evidence-only and not acceptance-only.

Recovery real scope:

- Finish only the GL-009 metadata actor-envelope contract left incomplete by the prior execution.
- Keep the partial helper/test work already present unless the executor proves a structural bug in it.
- Edit only the five recovery owner files listed in `## owner files`.
- Do not update the source matrix, test inventory, breakdown ledger, closure reference, database schema, Go/libp2p code, UI design, or later-session docs in this recovery pass.

Current evidence the executor should trust:

- `group_config_payload.dart` already defines `groupMetadataActorEventEnvelopeField`, `groupMetadataActorEventSignedPayloadField`, `groupMetadataActorEventSignatureField`, `groupMetadataActorEventSignatureAlgorithmField`, `buildGroupMetadataActorEventPayload`, `canonicalizeGroupMetadataActorEventPayload`, `buildSignedGroupMetadataActorEventEnvelope`, and `extractGroupMetadataActorEventVerificationData`.
- `updateGroupMetadata` already accepts `beforePersist`; use this seam from `GroupInfoWired` to guarantee signing failure aborts before `groupRepo.updateGroup(updated)`.
- `GroupInfoWired` currently calls `updateGroupMetadata` before building `sysText`, and no `payload.sign` call is present in the metadata edit path.
- `GroupMessageListener` currently calls `appendSystemEventLog()` for `group_metadata_updated` before `_handleGroupMetadataUpdated`, and `_handleGroupMetadataUpdated` can mutate state/sync/timeline without `payload.verify`.
- The four failing receive tests are valid GL-009 RED tests unless code inspection proves an assertion is wired to the wrong seam.

Publish recovery instructions for `GroupInfoWired`:

1. In the metadata save path, prepare nullable locals for `refreshedMembers`, `groupConfig`, and `sysText` before calling `updateGroupMetadata`.
2. Pass `beforePersist` to `updateGroupMetadata`.
3. Inside `beforePersist`, fetch the current members, build `groupConfig` from the candidate `updated` group, build the unsigned actor payload with actor peer id, username, public key, `groupId`, `updatedAt`, `groupConfigVersion`, `groupConfigStateHash`, and exact `groupConfig`, canonicalize it, and call:

   ```dart
   callSignPayload(
     bridge: widget.bridge,
     dataToSign: canonicalPayload,
     privateKey: identity.privateKey,
   )
   ```

4. If signing returns `ok != true`, a missing/non-string signature, or an empty signature, throw from `beforePersist`; this must prevent local group persistence, timeline save, `group:publish`, and `group:inboxStore`.
5. On signing success, build `sysText` with:

   - `__sys: group_metadata_updated`
   - `updatedAt`
   - `groupConfig`
   - `actorEvent.signedPayload`
   - `actorEvent.signature`
   - `actorEvent.signatureAlgorithm`

6. Keep private keys out of `sysText`, `actorEvent`, and the signed payload. The existing bridge transport payload may still carry `senderPrivateKey` for `callGroupPublish`; do not treat that existing bridge call shape as a GL-009 private-key leak.
7. After `updateGroupMetadata` returns, use the signed `sysText` and fetched members for timeline save, publish, and inbox-store. Do not rebuild a divergent `groupConfig` after signing.

Receive recovery instructions for `GroupMessageListener`:

1. In the `group_metadata_updated` branch, keep authorization and stale-watermark checks first.
2. Before `appendSystemEventLog()` and before `_handleGroupMetadataUpdated`, validate the outer `groupConfig` and `stateHash`. Do not append the event log if `isGroupConfigStateHashValid` fails.
3. Resolve the trusted sender member/public key from the local group repository. If the sender has no trusted public key, fail closed.
4. Call `extractGroupMetadataActorEventVerificationData` with the parsed system payload, `groupId`, `senderId`, `senderUsername`, and trusted actor public key.
5. If extraction returns null, fail closed without calling `payload.verify`, without appending the event log, and without mutating group state.
6. If extraction succeeds, call `callVerifyPayload` with the extracted public key, canonical signed payload string, and signature.
7. If `callVerifyPayload` returns false, fail closed without appending the event log or mutating group state.
8. Only after state-hash validation and actor signature verification pass may the listener call `appendSystemEventLog()` and `_handleGroupMetadataUpdated`.
9. Keep `_handleGroupMetadataUpdated`'s existing state-hash guard as a defensive duplicate if that is the smallest safe implementation, but do not rely on it as the only guard because it runs after the current append point.

Focused test recovery instructions:

- Preserve and pass these receive-path tests in `group_message_listener_test.dart`:
  - `authorized admin metadata event with valid state hash but no signed actor envelope is ignored`
  - `group_metadata_updated refreshes group metadata and stores a timeline event`
  - `signed group_metadata_updated payload mismatch is ignored`
  - `invalid group_metadata_updated actor signature is ignored`
- Add or tighten `group_info_wired_test.dart` assertions so a metadata edit:
  - calls `payload.sign` before `group:publish` and `group:inboxStore`
  - embeds `actorEvent.signedPayload`, `actorEvent.signature`, and `actorEvent.signatureAlgorithm`
  - signs the same canonical config that is published and inbox-stored
  - excludes private keys from the system payload and signed payload
  - aborts before local persistence, timeline save, publish, and inbox-store when signing fails

Recovery exact tests and gates:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart
git diff --check -- lib/features/groups/application/group_config_payload.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_info_wired_test.dart Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md
```

After those pass, run the broader existing GL-009 host regression set from `## exact tests and gates to run` unless the controller explicitly limits recovery verification to focused tests. `group-real-network-nightly` remains supporting release confidence only and is not required for this host-code recovery closure.

Recovery known-failure interpretation:

- The four named `group_message_listener_test.dart` failures are GL-009-owned until fixed.
- A passing `group_info_wired_test.dart` is not closure evidence unless it now asserts `payload.sign` and embedded `actorEvent`.
- Any failure in metadata `stateHash`, `configVersion`, `payload.sign`, `payload.verify`, event-log append ordering, or metadata timeline insertion is GL-009-owned in this recovery pass.
- Dirty worktree changes outside the five owner files must not be reverted or normalized by the recovery executor.

Recovery done criteria:

- `GroupInfoWired` signs the canonical metadata actor payload before persistence/publish/inbox-store and embeds `actorEvent.signedPayload`, `actorEvent.signature`, and `actorEvent.signatureAlgorithm`.
- Signing failure leaves the prior local group metadata unchanged and produces no metadata timeline save, publish, or inbox-store.
- `GroupMessageListener` rejects missing, malformed, mismatched, invalid-signature, and state-hash-invalid metadata events before event-log append, group mutation, bridge config sync, or metadata timeline insertion.
- Valid signed metadata events still update group metadata, sync bridge config, append one event-log entry, and create one timeline row.
- The two focused test commands and scoped `git diff --check` above pass.

## Recovery Pass 1 Final Verdict

Reusable and execution-ready for GL-009 same-session recovery pass 1.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact private helper names in `GroupMessageListener` can be chosen during implementation.
- Broader host gates remain in the original plan; recovery handoff requires the focused commands first.

Accepted differences intentionally left unchanged:

- Device/relay proof remains host-only/supporting for GL-009.
- Legacy unsigned metadata events fail closed.
- Non-metadata membership/dissolve actor envelopes stay out of scope.

Why this recovery plan is safe now: it is bounded to the partial GL-009 owner files, reuses existing canonical payload and bridge helpers, gives the executor exact publish/receive ordering, preserves the four valid RED tests, and prevents closure until focused signature-envelope tests pass.

## Recovery Input - Pass 2

Recorded by pipeline controller on 2026-04-30 19:48:24 CEST after recovery pass 1 execution materialization failed to produce code/test progress.

- blocker class: implementation-owned execution incomplete plus fresh-child execution no-progress
- blocker signature: GL-009 | implementation-owned execution incomplete | missing `payload.sign` in `GroupInfoWired`, missing `payload.verify` before metadata append/apply in `GroupMessageListener`, prior focused `group_message_listener_test.dart` four signature-envelope failures | owner files `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`
- recovery pass 1 executor state:
  - first recovery execution child was closed after no owner-file mtimes moved and no execution result landed
  - narrower recovery execution child was closed after no owner-file mtimes moved and no execution result landed
  - controller-local fallback is verification-only because degraded local code-writing is not allowed in this implementation-committed run
- current verification evidence:
  - `rg` finds `actorEvent` helper code in `group_config_payload.dart`
  - `rg` finds `group_info_wired.dart` still builds `group_metadata_updated` without `callSignPayload` or `payload.sign`
  - `rg` finds `group_message_listener.dart` still calls `appendSystemEventLog()` and `_handleGroupMetadataUpdated` in the `group_metadata_updated` branch without `callVerifyPayload`, `payload.verify`, or `extractGroupMetadataActorEventVerificationData`
- pass 2 instruction: keep the same blocker signature and tighten only the handoff/execution instructions if useful; then attempt the final allowed same-session recovery execution pass. If the same signature remains after pass 2, record GL-009 as blocked.

## Recovery Pass 2 Final Execution Handoff

Classification: `implementation-ready`

Run mode: implementation-committed gap-closure. This is the final allowed same-session recovery execution pass for the same blocker signature.

Reuse `## Recovery Pass 1 Execution Contract` unchanged as the execution source of truth. The owner files, focused tests, device/relay proof profile, and scope guard remain structurally safe and unchanged.

Pass 2 executor requirements:

- Implement only the missing publish-time `payload.sign` wiring in `GroupInfoWired` and receive-time `payload.verify` wiring in `GroupMessageListener`.
- Keep the existing `group_config_payload.dart` actor-event helpers unless a direct compile/test failure proves a helper-level adjustment is required.
- Preserve the existing RED receive-path tests and add/tighten only the publish-path tests required by the pass 1 contract.
- Run the focused recovery commands from `## Recovery Pass 1 Execution Contract` first and record the result before any broader host gates.
- Do not update the source matrix, test inventory, closure docs, breakdown ledger, database schema, Go/libp2p code, device/relay requirements, or unrelated dirty files in this execution pass.

Final same-session stop rule:

- If the final execution pass again makes no owner-file code/test progress or leaves `GroupInfoWired` without `payload.sign` and `GroupMessageListener` without `payload.verify` before metadata append/apply, stop same-session recovery and record GL-009 as blocked.
- Do not attempt a third same-session recovery pass for this blocker signature.

## Recovery Pass 2 Final Planning Verdict

Reusable and execution-ready for GL-009 final same-session recovery pass.

Structural blockers remaining: none.

Incremental details intentionally deferred: none beyond the pass 1 handoff details already deferred.

Accepted differences intentionally left unchanged:

- Device/relay proof remains supporting release confidence only.
- Legacy unsigned metadata events fail closed.
- Non-metadata membership/dissolve actor envelopes remain out of scope.

## Recovery Pass 2 Execution Result

Status: blocked

Recorded by pipeline controller-local verification fallback on 2026-04-30 19:54:10 CEST after the final allowed same-session recovery execution child was closed for no-progress.

Blocker class: implementation-owned execution incomplete with same-session recovery exhausted.

Blocker signature: GL-009 | implementation-owned execution incomplete | missing `payload.sign` in `GroupInfoWired`, missing `payload.verify` before metadata append/apply in `GroupMessageListener`, prior focused `group_message_listener_test.dart` four signature-envelope failures | owner files `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`.

Execution attempts for this signature:

- Initial GL-009 execution child left partial helper/RED-test deltas but no verdict.
- Recovery pass 1 execution child made no owner-file code/test progress and was closed.
- Recovery pass 1 narrower execution child made no owner-file code/test progress and was closed.
- Recovery pass 2 final execution child made no owner-file code/test progress and was closed.

Controller-local verification evidence:

- `stat` showed no GL-009 owner-file mtime movement after the final recovery handoff.
- `rg` still finds `GroupInfoWired` building `group_metadata_updated` without `callSignPayload` or `payload.sign`.
- `rg` still finds `GroupMessageListener` calling `appendSystemEventLog()` and `_handleGroupMetadataUpdated` in the `group_metadata_updated` branch without `callVerifyPayload`, `payload.verify`, or `extractGroupMetadataActorEventVerificationData`.
- The prior focused command `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` remains the current failure evidence for the four GL-009 signature-envelope tests. It was not rerun after pass 2 because no implementation progress landed.

Commands run for pass 2 verification:

```text
stat -f '%Sm %N' -t '%Y-%m-%d %H:%M:%S %Z' lib/features/groups/application/group_config_payload.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_info_wired_test.dart Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md
git diff --stat -- lib/features/groups/application/group_config_payload.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_info_wired_test.dart Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md
rg -n "callSignPayload|callVerifyPayload|extractGroupMetadataActorEventVerificationData|payload\\.sign|payload\\.verify|Recovery Pass 2 Execution Result|Status:|Recovery Pass 2" lib/features/groups/application/group_message_listener.dart lib/features/groups/presentation/screens/group_info_wired.dart Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md
```

Results:

- No final-pass owner-file implementation progress was visible.
- No focused recovery tests were run after pass 2 because there was no new implementation to validate.
- GL-009 is not ready for closure. Source matrix row GL-009 must remain `Partial`.
- Same-session recovery for this blocker signature is exhausted; do not attempt a third same-session recovery pass under this controller run.

## Fresh Implementation Pass Reopen - 2026-04-30

Status: execution-ready and reusable for one fresh implementation pass.

This section supersedes the same-session recovery handoffs above for the next executor only. It does not erase the persisted blocker: GL-009 remains blocked for closure until the source matrix row can be updated to `Covered` or `Closed` with concrete code and test evidence by a later execution/closure step.

Session classification: `implementation-ready`.

Run mode: implementation-committed gap closure. This is not evidence-only and not acceptance-only.

### real scope

Finish the GL-009 metadata actor-envelope contract already partially started on disk:

- `GroupInfoWired` must call `payload.sign` through `callSignPayload` before local metadata persistence, metadata timeline save, `group:publish`, or `group:inboxStore`.
- `GroupInfoWired` must embed `actorEvent.signedPayload`, `actorEvent.signature`, and `actorEvent.signatureAlgorithm` in the published and inbox-stored `group_metadata_updated` system payload.
- `GroupMessageListener` must verify the embedded actor envelope through `payload.verify`/`callVerifyPayload` before metadata event-log append, group mutation, `group:updateConfig`, or metadata timeline insert.
- Existing config version, canonical state hash, stale-watermark, duplicate replay, and avatar recovery behavior must stay intact.

No matrix, inventory, breakdown ledger, closure-reference, database schema, Go/libp2p, relay, device-lab, or non-GL-009 product work belongs in this pass.

### exact blocker

Current code evidence still shows:

- `lib/features/groups/presentation/screens/group_info_wired.dart` builds `group_metadata_updated` without `callSignPayload` or `payload.sign`.
- `lib/features/groups/application/group_message_listener.dart` calls `appendSystemEventLog()` and `_handleGroupMetadataUpdated()` in the `group_metadata_updated` branch without `callVerifyPayload`, `payload.verify`, or `extractGroupMetadataActorEventVerificationData`.
- The focused receive tests in `test/features/groups/application/group_message_listener_test.dart` already define the GL-009 RED cases for unsigned, valid signed, signed-payload mismatch, and invalid-signature metadata actor envelopes.

### owner files for the fresh pass

The executor may edit only these GL-009 owner files unless a direct compile failure proves a same-feature import/test fixture adjustment is required:

- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`

Supporting evidence files should be inspected but not edited by default:

- `lib/features/groups/application/update_group_metadata_use_case.dart`
- `lib/core/bridge/bridge.dart`
- `test/core/bridge/fake_bridge.dart`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

### implementation steps

1. Reuse the existing metadata actor-event helper surface in `group_config_payload.dart`; adjust it only if a focused test or analyzer failure proves the helper contract is wrong.
2. In `GroupInfoWired`, use `updateGroupMetadata(beforePersist: ...)` as the signing barrier. Build the candidate `groupConfig`, canonical actor payload, and signed envelope inside that callback, then abort by throwing if `payload.sign` fails or returns an empty signature.
3. Ensure the exact signed `groupConfig` is the one placed in `sysText` for local timeline, publish, and inbox-store; do not rebuild a divergent config after signing.
4. Keep private keys out of `sysText`, `actorEvent`, and `signedPayload`. The existing bridge publish request may still carry `senderPrivateKey` because that is the bridge transport contract, not the JSON system payload.
5. In `GroupMessageListener`, keep authorization and stale-watermark checks first, then validate `groupConfig`/state hash, extract actor-event verification data with the trusted sender member public key, call `callVerifyPayload`, and only then append the event log and apply metadata.
6. Missing, malformed, mismatched, unsupported-algorithm, untrusted-public-key, invalid-signature, bridge-error, or state-hash-invalid metadata events must fail closed without event-log append or state mutation.
7. Preserve existing stale/replay/idempotency tests by giving valid signed actor envelopes to fixtures that are meant to pass under the new signature requirement.

### tests and gates

Run these focused checks first:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart
git diff --check -- lib/features/groups/application/group_config_payload.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_info_wired_test.dart Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md
```

After focused checks pass, run the broader GL-009 host regression set:

```bash
flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart
flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart
flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart
flutter test --no-pub test/features/groups/application
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh groups
flutter test --no-pub test/features/groups/integration
```

### host-only Device/Relay Proof Profile

Device/relay proof is not required for GL-009 closure because the missing behavior is a Dart publish/receive signing and verification contract that can be proven with deterministic host tests and `FakeBridge` `payload.sign`/`payload.verify` calls. `group-real-network-nightly` remains supporting release confidence only:

```bash
FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly
```

If this optional command is attempted without fixture values, record it as fixture-blocked rather than closure evidence.

### known-failure interpretation

- The four existing GL-009 actor-envelope receive failures are GL-009-owned until fixed.
- Any focused failure involving `payload.sign`, `payload.verify`, `actorEvent`, metadata state hash, metadata event-log append ordering, metadata timeline insertion, or `group:updateConfig` is GL-009-owned until proven unrelated.
- A broad `test/features/groups/application` failure may be recorded as pre-existing only if both focused GL-009 suites, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and scoped `git diff --check` pass and the failing case is demonstrably unrelated to metadata actor envelopes.

### done criteria

- Publish path signs the canonical metadata actor payload before persistence/publish/inbox-store and embeds the signed actor envelope in the JSON system payload.
- Signing failure leaves prior local metadata unchanged and produces no metadata timeline save, publish, or inbox-store.
- Receive path rejects unsigned, malformed, mismatched, unsupported-algorithm, invalid-signature, bridge-error, untrusted-key, state-hash-invalid, and stale metadata events before event-log append or mutation.
- Valid signed metadata events still update metadata, sync `group:updateConfig`, append one event-log entry, and create one timeline row.
- Focused tests and required host gates above pass with outcomes recorded by the execution/closure step.
- Source matrix GL-009 remains `Partial` until a later execution/closure update records concrete code/test evidence and marks the row `Covered` or `Closed`.

### scope guard

Do not add new governance features, permission systems, key rotation semantics, event-log schemas, migrations, Go validators, relay/device orchestration, compatibility grandfathering for unsigned metadata, or broad cleanup. Do not revert unrelated dirty-tree edits. Do not keep retrying the same no-progress execution loop inside one controller pass; this handoff is for one fresh implementation attempt, after which unresolved `payload.sign`/`payload.verify` wiring must be recorded as blocked again.

### accepted differences / intentionally out of scope

- Go transport signing is not accepted as a substitute for the Dart-visible metadata actor envelope required by GL-009.
- Legacy unsigned metadata events fail closed in this row.
- Non-metadata membership, dissolve, invite, key-rotation, and audit event signatures stay outside this GL-009 pass.

### dependency impact

GL-009 closure unblocks later metadata governance and state-convergence rows that assume settings changes have signed actor provenance. If the fresh executor proves a schema or wider event-log architecture is required, stop and reclassify the row rather than broadening this pass.

### reviewer sufficiency result

Sufficient as-is for one fresh implementation pass.

Missing files, tests, regressions, or gates: none for the planning handoff. The direct owner files, focused tests, broader host gates, and optional real-network proof profile are explicit.

Stale or incorrect assumptions: none found. Same-session recovery exhaustion remains a persisted blocker for the previous controller run, but it does not prevent a future fresh implementation pass because the blocker is still implementation-owned and confined to GL-009 owner files.

Overengineering check: no broad schema, Go, relay, governance, or compatibility migration work is included.

Minimum needed to execute safely: implement only the publish-time `payload.sign` wiring and receive-time `payload.verify` ordering described above, then run the focused GL-009 tests first.

### arbiter decision

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact private helper names in `GroupMessageListener` and `GroupInfoWired`.
- Optional `group-real-network-nightly` release-confidence proof.

Accepted differences intentionally left unchanged:

- Go transport signing is separate from the Dart-visible metadata actor envelope.
- Legacy unsigned metadata events fail closed.
- Non-metadata event signatures remain out of scope.

Final verdict: reusable and execution-ready for GL-009 only. Closure is still blocked until the implementation pass produces concrete code/test evidence and a later closure step updates the source matrix row to `Covered` or `Closed`.

## Scoped Fixture Recovery Pass - 2026-04-30

Status: execution-ready and reusable for one fresh scoped fixture execution pass.

This section supersedes earlier GL-009 implementation handoffs for the next executor only. It does not reopen production sign/verify work: the latest execution evidence records focused owner tests passing, while required row gates remain blocked by one stale unsigned integration fixture.

### real scope

Update only the metadata replay fixture in `test/features/groups/integration/group_resume_recovery_test.dart` so the existing `publishMetadataUpdate` helper emits a production-shaped signed `group_metadata_updated` actor envelope.

The fixture update must:

- Build one `groupConfig` with `buildGroupConfigPayload(updatedGroup, members)` and use that exact map in both the signed actor payload and outer system payload.
- Build the actor payload with `buildGroupMetadataActorEventPayload` using the admin peer id, username, public key, event time, group id, config version, config state hash, and exact group config.
- Canonicalize with `canonicalizeGroupMetadataActorEventPayload`.
- Sign through `callSignPayload` or the same bridge command path with `admin.privateKey`, using a deterministic nonempty fake signature response if needed.
- Embed `buildSignedGroupMetadataActorEventEnvelope(...)` under `groupMetadataActorEventEnvelopeField`.
- Configure the relevant fake bridges for deterministic `payload.verify` success where the live and offline recipients process these signed metadata events.

Do not change production signing, verification, listener ordering, metadata state-hash logic, UI publish behavior, source matrix, test inventory, breakdown ledger, Go/libp2p code, relay/device fixtures, or unrelated integration scenarios.

### exact blocker

`./scripts/run_test_gates.sh groups` and `flutter test --no-pub test/features/groups/integration` fail in `test/features/groups/integration/group_resume_recovery_test.dart` because `publishMetadataUpdate` manually publishes unsigned `group_metadata_updated` payloads. Production now correctly rejects those events with `GROUP_MESSAGE_LISTENER_METADATA_SIGNATURE_INVALID`.

### owner files for the scoped recovery pass

Editable owner:

- `test/features/groups/integration/group_resume_recovery_test.dart`

Read-only evidence/support:

- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/core/bridge/bridge.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

Any required edit outside `test/features/groups/integration/group_resume_recovery_test.dart` is a blocker for this recovery pass unless it is a same-file import adjustment needed to compile the fixture.

### step-by-step implementation plan

1. In `publishMetadataUpdate`, keep `updateGroupMetadata(...)` and the member fetch, then assign the returned `buildGroupConfigPayload(...)` to a local `groupConfig`.
2. Build and canonicalize the metadata actor event with the existing helpers from `group_config_payload.dart`.
3. Sign the canonical payload with the admin identity private key through the bridge signing path; configure the admin fake bridge response locally if the fake bridge would otherwise return no signature.
4. Add the signed actor envelope to the JSON system payload and preserve the existing outer `updatedAt`, `groupConfig`, sender fields, message ids, and older/newer event order.
5. Configure Bob and Charlie verification responses for this scenario so live delivery and offline drain exercise production verification successfully.
6. Stop and re-plan if the fixture cannot compile against the existing helper surface without production changes.

### exact tests and gates to run

Focused fixture proof:

```bash
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "offline member reconnects after repeated metadata edits and converges to the final metadata state"
```

Required GL-009 row gates after the focused proof passes:

```bash
./scripts/run_test_gates.sh groups
flutter test --no-pub test/features/groups/integration
git diff --check -- test/features/groups/integration/group_resume_recovery_test.dart Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md
```

Optional sanity checks if the executor needs to confirm production owner scope stayed green:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart
```

### known-failure interpretation

- Any remaining `GROUP_MESSAGE_LISTENER_METADATA_SIGNATURE_INVALID` in the focused fixture or required row gates is GL-009-owned until proven unrelated.
- A failure caused by editing production sign/verify behavior is out of scope for this recovery and must stop the pass.
- The known broad `test/features/groups/application` MD-011 future-media replay failure is not part of this fixture recovery gate set and must not be used to classify the scoped fixture pass.
- Dirty worktree changes outside the owner file and this plan must not be reverted, normalized, or counted as recovery evidence.

### done criteria

- The existing metadata convergence test passes with signed newer and older metadata events.
- Bob's offline drain converges to the newer metadata and ignores the older replay through the existing stale-watermark behavior.
- Charlie's live path accepts the signed metadata through the existing listener verification path.
- The required `groups` gate and broad groups integration command pass or any remaining failure is recorded with an exact non-GL-009 blocker.
- `git diff --check` passes for the owner file and this plan file.
- No production code, source matrix, test inventory, or breakdown ledger is edited by this recovery planning pass.

### scope guard

Do not weaken signature verification, grandfather unsigned metadata, add compatibility fallback behavior, change listener ordering, change canonical state-hash logic, add migrations, edit Go/libp2p or relay code, alter unrelated integration tests, update closure docs, or broaden GL-009 into governance/membership/key-rotation signing. The only acceptable code/test change for the next executor is the scoped fixture update in `group_resume_recovery_test.dart`.

### accepted differences / intentionally out of scope

- The fixture may use deterministic fake `payload.sign` and `payload.verify` responses; real Ed25519 cryptography remains covered by the bridge contract, not this host integration fixture.
- Real-network nightly evidence remains supporting release confidence only and is not required for this scoped fixture recovery.
- Source row closure remains a later execution/closure responsibility after evidence exists.

### dependency impact

This recovery pass is required before GL-009 can be closed because the row's required gates include `group_resume_recovery_test.dart`. Later sessions should remain paused until this gate blocker is resolved or recorded as a non-GL-009 blocker with exact evidence.

### reviewer sufficiency result

Sufficient as-is for one scoped fixture execution pass. The plan has one editable owner file, uses existing production helper APIs, names the exact failing gates, and preserves the fail-closed GL-009 contract.

### arbiter decision

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact deterministic fake signature string.
- Whether the executor confirms RED by rerunning the focused fixture before editing.

Accepted differences intentionally left unchanged:

- Production sign/verify code is read-only for this recovery.
- Source matrix, test inventory, and breakdown ledger stay unchanged during planning.

Final verdict: reusable and execution-ready for one scoped GL-009 fixture recovery pass.
