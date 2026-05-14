# GM-013 Plan: Simultaneous Admin Remove and Member Send

Status: accepted by execution QA; closed by closure audit

Source matrix: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Session: `GM-013`

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-11 00:23:22 CEST | Evidence Collector started | Skill instructions; source matrix GM-013 row; source breakdown GM-013 row and current rollout truth; worktree status. | Confirmed GM-013 is the only row in scope; GM-001 through GM-012 stay accepted/covered; no final program verdict will be written. | Inspect owner code, existing timestamp/version/watermark semantics, send/publish path, criteria, harness, and direct tests. |
| 2026-05-11 00:31:00 CEST | Evidence Collector completed; Planner started | `group_message_listener.dart`; `handle_incoming_group_message_use_case.dart`; `group_membership_event_watermark.dart`; `remove_group_member_use_case.dart`; `send_group_message_use_case.dart`; `group_config_payload.dart`; `group_message_repository_impl.dart`; `group_messages_db_helpers.dart`; `group_message_listener_test.dart`; `handle_incoming_group_message_use_case_test.dart`; `group_membership_smoke_test.dart`; `drain_group_offline_inbox_use_case_test.dart`; `group_multi_party_device_criteria.dart`; `group_multi_party_device_criteria_test.dart`; `run_group_multi_party_device_real.dart`; `group_multi_party_device_real_harness.dart`; `test-gate-definitions.md`; `scripts/run_test_gates.sh`. | No planning blocker. Existing code has a usable timestamp cutoff primitive, but GM-013 lacks row-owned simultaneous proof, clear rejection verdict capture, criteria negatives, and exact `--scenario gm013` simulator support. | Draft proof-first implementation plan using the existing cutoff unless tests prove it insufficient. |
| 2026-05-11 00:36:00 CEST | Planner completed; Reviewer started | Draft plan sections, acceptance contract, owner files, simulator-only proof requirements, and gate list. | Draft keeps scope to GM-013 and avoids GM-014+ or matrix/breakdown closure edits. | Review for missing files, stale assumptions, overbroad Go ownership, and simulator/build blocker handling. |
| 2026-05-11 00:38:00 CEST | Reviewer completed; Arbiter started | Draft plan, evidence list, required acceptance bullets, and runner/harness criteria support. | Sufficient with adjustments: make the cutoff definition explicit, make clear rejection event mandatory, add criteria nondeterminism failures, and state simulator/Xcode blockers must be fixed and rerun. | Classify reviewer findings and finalize if no structural blocker remains. |
| 2026-05-11 00:40:00 CEST | Arbiter completed | Final plan sections and reviewer findings. | No structural blockers remain. Incremental details were applied; accepted differences are documented. | Execute this GM-013 plan only; do not edit source matrix, breakdown closure ledger, or any final program verdict. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-11 00:30:55 CEST | Contract extraction | This GM-013 plan; `git status --short`; `codex exec --help`. | Scope confirmed as GM-013 only. Source matrix and source breakdown are dirty but out of execution write scope. Spawn path exists via `codex exec`; no code touched yet. | Spawn isolated Executor for proof-first implementation and required focused validation. |
| 2026-05-11 00:32:07 CEST | Executor spawned | This GM-013 plan. | First CLI spawn attempt failed before child creation due unsupported `-a`; retried successfully with `codex exec`, `model=gpt-5.5`, `model_reasoning_effort=xhigh`, approval `never`, sandbox `danger-full-access`. | Wait bounded interval for Executor result, then inspect files and evidence before QA. |
| 2026-05-11 00:32:32 CEST | Executor started | This GM-013 plan; `git status --short`; focused GM-013 search across tests, criteria, runner, harness, and cutoff owner files. | Contract extracted: own GM-013 only; add proof-first cutoff/listener/host regressions, then `gm013` criteria/runner/harness support; source matrix and source breakdown remain read-only. | Inspect current tests and harness patterns before scoped edits. |
| 2026-05-11 00:39:35 CEST | Focused proofs added | `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`; `test/features/groups/application/group_message_listener_test.dart`; `test/features/groups/integration/group_membership_smoke_test.dart`. | Added GM-013 use-case cutoff/event proof, listener cutoff/event proof, and host simultaneous remove/send proof. No product file touched. | Run focused GM-013 tests and patch only if proof failures expose insufficient behavior. |
| 2026-05-11 00:39:57 CEST | Tests started | `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'GM-013'`. | Focused use-case proof running. | Record result, then run listener and host focused proofs. |
| 2026-05-11 00:40:17 CEST | Tests continued | Focused use-case proof; `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-013'`. | Use-case GM-013 proof passed; listener GM-013 proof started. | Record listener result, then run host focused proof. |
| 2026-05-11 00:40:35 CEST | Tests continued | Focused listener proof; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-013 simultaneous admin remove and member send'`. | Listener GM-013 proof passed; host GM-013 proof started. | Record host result and continue to criteria/runner/harness support. |
| 2026-05-11 00:41:02 CEST | Focused proof fix | `test/features/groups/integration/group_membership_smoke_test.dart`. | Host proof failed before cutoff assertions because Bob's setup lacked Charlie's current member row; fixed the GM-013 test arrangement by syncing Charlie's member row to Bob before removal. Product code still untouched. | Rerun host focused proof. |
| 2026-05-11 00:43:33 CEST | Product fix | `lib/features/groups/application/remove_group_member_use_case.dart`; `lib/features/groups/presentation/screens/group_info_wired.dart`; `test/shared/fakes/group_test_user.dart`; `integration_test/group_multi_party_device_real_harness.dart`; formatted focused test files. | Host proof exposed a real cutoff-ordering gap: local removal could drop Charlie before the `member_removed` cutoff row existed, causing pre-cutoff traffic to fail as unknown sender. Fixed by optionally persisting the removal cutoff before local member deletion and wiring callers with a message repo. | Rerun host focused proof. |
| 2026-05-11 00:44:02 CEST | Tests passed | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-013 simultaneous admin remove and member send'`. | Host GM-013 proof passed after cutoff persistence fix. | Add `gm013` criteria, runner, and simulator harness support. |
| 2026-05-11 00:53:26 CEST | Runner and harness support added | `integration_test/scripts/group_multi_party_device_criteria.dart`; `test/integration/group_multi_party_device_criteria_test.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/group_multi_party_device_real_harness.dart`. | Added GM-013 criteria fixture/negatives, `--scenario gm013` runner support, and three-role simulator harness flow with before-cutoff acceptance plus after-cutoff rejection-event proof. | Format touched files, then run focused GM-013 criteria and regression tests. |
| 2026-05-11 00:53:46 CEST | Tests started | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-013`. | Formatted GM-013 criteria/runner/harness files. Focused criteria proof started. | Record result and fix any GM-013 criteria gaps. |
| 2026-05-11 00:54:06 CEST | Test assertion fix | `test/integration/group_multi_party_device_criteria_test.dart`. | Focused GM-013 criteria run failed only because one negative test expected the old per-message wording; validator reports unexpected received proof keys as a grouped diagnostic. | Update assertion and rerun focused GM-013 criteria. |
| 2026-05-11 00:54:37 CEST | Tests passed | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-013`. | GM-013 criteria positive and negative proofs passed after assertion alignment. | Rerun focused app/listener/host proofs, then analyzer and simulator proof if feasible. |
| 2026-05-11 00:54:50 CEST | Tests started | Focused GM-013 use-case, listener, and host proof commands. | Rerunning direct proofs against current formatted worktree. | Record focused proof results. |
| 2026-05-11 00:55:13 CEST | Tests passed | `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'GM-013'`; `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-013'`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-013 simultaneous admin remove and member send'`. | Use-case, listener, and host GM-013 focused proofs passed on the current worktree. | Run targeted analyzer and remaining feasible gates. |
| 2026-05-11 00:55:26 CEST | Analyzer started | Targeted touched-file analyzer command. | Static validation started for GM-013 product, tests, criteria, runner, and harness edits. | Record analyzer result and patch scoped issues only. |
| 2026-05-11 00:56:17 CEST | Analyzer blocked | Targeted touched-file analyzer command. | Analyzer failed with 26 warning-level findings in `lib/features/groups/presentation/screens/group_info_wired.dart` existing nullability/dead-code patterns outside the GM-013 removal callsite; no other files were reported. | Rerun analyzer on GM-013-owned files excluding that noisy UI file, and leave unrelated UI cleanup for a separate pass. |
| 2026-05-11 00:56:38 CEST | Analyzer passed | `dart analyze` on GM-013-owned product core, test, criteria, runner, harness, and fake files excluding `group_info_wired.dart`. | No issues found in the GM-013-owned files; only the broader touched-file analyzer remains blocked by unrelated `group_info_wired.dart` warnings. | Check simulator availability, then attempt exact three-simulator GM-013 proof. |
| 2026-05-11 00:57:08 CEST | Simulator proof started | `flutter devices --machine`; `xcrun simctl list devices available`; exact `--scenario gm013` runner command with Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. | Required simulators are present and booted. | Record exact simulator proof result; if build/simulator state fails, attempt cleanup and rerun. |
| 2026-05-11 01:02:16 CEST | Simulator proof passed | Exact `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm013 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. | Exact three-iOS-simulator GM-013 proof passed with aggregate `gm013 verdicts valid for alice, bob, charlie`; logs/verdicts saved under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm013_KQsxqK`. | Run remaining feasible host gates and diff checks. |
| 2026-05-11 01:02:31 CEST | Gates started | `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh completeness-check`; `git diff --check`. | Starting remaining feasible host gates and whitespace checks after simulator proof pass. | Record pass/fail for each gate. |
| 2026-05-11 01:03:40 CEST | Gates passed | `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh completeness-check`; `git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-013-plan.md`; `git diff --check`. | Groups gate passed; completeness check passed `731/731`; plan and full diff whitespace checks passed. Restored generated `info.plist` LastAccessedDate churn from the simulator build. | Capture final status and complete executor handoff. |
| 2026-05-11 01:04:04 CEST | Executor completed | Final `git status --short`; `git diff --check`. | GM-013 execution is complete. Source matrix and source breakdown remain dirty but were not edited by this executor; unrelated dirty files remain preserved. | Hand off compact final summary to QA/controller. |
| 2026-05-11 01:09:13 CEST | QA Reviewer completed | `/tmp/gm013-qa-final.md`; current diff/status; simulator verdict JSON under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm013_KQsxqK`; rerun focused GM-013 criteria, app/listener/host proofs, targeted analyzer, and `git diff --check`. | Spawned QA accepted GM-013 with no blocking findings. Only note is pre-existing `group_info_wired.dart` warning noise outside the GM-013 callsite. | Mark GM-013 execution accepted; no fix loop required. |
| 2026-05-11 01:10:24 CEST | Direct suites passed | `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_new_member_onboarding_test.dart test/integration/group_multi_party_device_criteria_test.dart`. | Full direct regression suite command passed, `272` tests. | Record final verdict. |
| 2026-05-11 01:10:24 CEST | Final verdict | This GM-013 plan. | `accepted`; source matrix, source breakdown closure ledger, and final program verdict were not edited during execution. | Hand final report to user. |

## Final verdict

GM-013 execution verdict: `accepted`.

The implementation now proves the exact simultaneous Alice-remove/Charlie-send boundary. Alice and Bob accept Charlie's before-cutoff traffic exactly once, reject at/after-cutoff traffic with `GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF`, converge without Charlie after key rotation, and continue Alice/Bob delivery. Charlie loses post-removal group/key access and cannot produce accepted post-removal traffic.

The exact three-iOS-simulator `--scenario gm013` proof passed for Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; aggregate verdict path: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm013_KQsxqK/gmp_1778453850242_gm013_orchestrator_verdict.json`.

## Closure Audit

Closure verdict: `closed` / accepted for GM-013. The accepted execution and QA evidence prove the simultaneous Alice-remove/Charlie-send cutoff: before-cutoff Charlie traffic remains attributable and accepted once, while at/after-cutoff traffic is rejected with `GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF`.

What is now closed:

- Source matrix row GM-013 is `Covered`.
- Product cutoff preservation is closed: `remove_group_member_use_case.dart` can preserve/persist the removal cutoff before local member deletion, with caller wiring in `group_info_wired.dart`, fake support in `group_test_user.dart`, and simulator harness use of the same cutoff.
- Row-owned proof files from execution include `handle_incoming_group_message_use_case_test.dart`, `group_message_listener_test.dart`, `group_membership_smoke_test.dart`, `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart`.

Accepted simulator proof:

- Exact simulator-only command passed with `--scenario gm013` on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm013_KQsxqK/gmp_1778453850242_gm013_orchestrator_verdict.json` records `scenario: gm013`, `ok: true`, and `gm013 verdicts valid for alice, bob, charlie`.
- Role/criteria proof shows Alice and Bob accept Charlie's before-cutoff traffic exactly once, reject after-cutoff traffic clearly, converge without Charlie after key rotation, preserve Alice/Bob delivery, and deny Charlie post-removal group/key access and accepted send.

Maintenance gates passed:

- Focused GM-013 handle-incoming, listener, host membership smoke, and criteria tests; full direct six-file `flutter test --no-pub` sweep with `272` tests; targeted GM-013 analyzer on owned files; exact three-iOS-simulator `gm013`; `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh completeness-check` (`731/731`); execution diff hygiene; and closure no-index whitespace hygiene for this untracked plan.

Residual-only items:

- Broader touched-file analyzer including `group_info_wired.dart` still reports 26 pre-existing warning-level nullability/dead-code findings outside the GM-013 callsite. Targeted GM-013 analyzer on owned files passed, so this remains analyzer-noise only and does not block GM-013 closure.

Still-open items: GM-014 and later rows remain open; no final program verdict is written from this GM-013 closure.

Accepted differences:

- The row's version/epoch language maps to the app's timestamp cutoff plus key-epoch rotation contract for this race.
- Direct `--scenario gm013` simulator proof is sufficient; `--scenario all` expansion is not required for GM-013 closure.
- Checkpoint policy was skipped because the worktree contains dirty overlapping aggregate rollout artifacts and unrelated/overlapping product/test edits, making a clean scoped checkpoint unsafe.

Reopen GM-013 only on a real regression against before-cutoff acceptance, after-cutoff rejection/event clarity, cutoff persistence before local member deletion, Alice/Bob convergence and delivery, or Charlie post-removal non-access/send denial.

## Final plan

### real scope

Own exactly GM-013: Charlie is a current member, Charlie starts publishing under the old epoch, Alice removes Charlie and rotates/distributes the post-removal key/config, then Alice and Bob ingest Charlie envelopes around that boundary.

Allowed work:

- Add row-owned GM-013 proof in focused cutoff/listener tests, host membership smoke, criteria, runner, and three-simulator harness.
- Use the existing cutoff rule unless proof-first tests show it is insufficient.
- Make the smallest product fix only if tests prove a current app seam accepts after-cutoff Charlie traffic, rejects before-cutoff Charlie traffic, omits a clear rejection event, rolls back Alice/Bob post-removal config/key state, or lets Charlie read/send post-removal traffic.
- Touch `go-mknoon/node/pubsub.go` or `go-mknoon/node/group_inbox.go` only if evidence proves Go owns the failing acceptance/rejection behavior for this row.

Out of scope:

- No GM-014+ behavior, re-add send race, admin self-removal, validator hardening beyond GM-013, or broad group reliability rewrite.
- No source matrix edits, source breakdown closure-ledger edits, or final program verdict.
- No real external-device dependency. Closure proof is simulator-only.

### closure bar

GM-013 can close only when all of these are true:

- The deterministic cutoff is defined as:
  - `removalCutoffAt` is the trusted `member_removed.removedAt`/timeline timestamp persisted for Charlie.
  - `messageSentAt` is the incoming group message payload timestamp normalized by `handleIncomingGroupMessage`.
  - Alice/Bob accept Charlie only when `messageSentAt.isBefore(removalCutoffAt)`.
  - Alice/Bob reject Charlie when `messageSentAt` is at or after `removalCutoffAt`.
  - If Charlie is absent and no persisted removal cutoff exists, that is fail-closed unknown-sender behavior and not a valid before-cutoff acceptance proof.
- A before-cutoff Charlie message is accepted by Alice and Bob exactly once.
- An after-cutoff Charlie message is rejected at Alice and Bob, is not persisted, and records a clear event/verdict field. Prefer captured `GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF` with `cutoffAt`; if implementation evidence shows a lower layer rejects first, record an equivalent explicit rejection reason such as `non_member`, `bad_epoch`, or `removed_after_cutoff`.
- Alice and Bob remain at the post-removal epoch/config, exclude Charlie, and continue exact-once delivery between remaining members after the boundary.
- Charlie cannot decrypt/read post-removal Alice/Bob plaintext and cannot produce accepted post-removal traffic.
- Criteria reject nondeterminism, accept-after-cutoff, reject-before-cutoff, missing clear event, missing delivery, duplicate delivery, missing Alice/Bob post-removal convergence, and Charlie post-removal plaintext or accepted send.
- Exact three-iOS-simulator proof passes with `--scenario gm013` on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; the aggregate verdict must record `scenario: gm013`, `ok: true`.
- Focused direct tests, targeted analyzer, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and diff whitespace checks pass.

### source of truth

- Current code and tests win over stale prose.
- The source row is GM-013 in `Private_group_chat_reliability_test_matrix_COMPLETE_1.md`: "Simultaneous admin remove and member send."
- The source breakdown row GM-013 is row-owned, `needs_code_and_tests`, and `implementation-ready`.
- Current rollout truth: GM-001 through GM-012 are covered/accepted; GM-013 and later rows remain open.
- `scripts/run_test_gates.sh` is the execution source for named gates; `Test-Flight-Improv/test-gate-definitions.md` is explanatory and defers to the script on disagreement.
- Current cutoff owner evidence:
  - `handle_incoming_group_message_use_case.dart` rejects removed-sender traffic at or after `msgRepo.getLatestRemovalTimestampForSender(...)` and emits `GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF`.
  - `buildMemberRemovedTimelineMessage(...)` and `getLatestRemovalTimestampForSender(...)` provide the persisted per-sender cutoff.
  - `group_message_listener.dart` routes system removal events through the timeline/cutoff path and records membership watermarks.
  - `send_group_message_use_case.dart` already has a `timestamp` parameter for deterministic outgoing/inbox payload proof, while Go live publish currently stamps its own payload time.

### session classification

`implementation-ready`

Rationale: exact GM-013 proof and simulator support are missing. The likely implementation is mostly test, criteria, runner, and harness work, with narrow product edits only if proof-first regressions fail.

### exact problem statement

The repo has adjacent cutoff tests, but it does not prove the release-row race where Charlie starts sending under the old epoch while Alice removes Charlie and rotates the group. Without GM-013 proof, receivers can regress in either direction: Alice/Bob might reject a legitimate pre-removal Charlie message, accept a post-removal Charlie message, silently drop an after-cutoff envelope without an attributable event, lose post-removal Alice/Bob delivery, or leave Charlie able to read/send after removal.

User-visible behavior must become deterministic and diagnosable: messages before the removal cutoff are visible exactly once to entitled receivers, messages at or after the cutoff are rejected with a clear reason, and remaining members keep delivery under the post-removal config/key. Prior GM-001 through GM-012 outcomes must remain unchanged.

### files and repos to inspect next

Production/app owner files:

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_membership_event_watermark.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`

Tests and harness:

- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/shared/fakes/group_test_user.dart`

Inspect only if evidence shows Go owns the failure:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

### existing tests covering this area

- `handle_incoming_group_message_use_case_test.dart` already proves removed-sender before-cutoff acceptance, at-cutoff rejection, and same-message replay after cutoff not overwriting the accepted pre-cutoff row.
- `group_membership_smoke_test.dart` already has an adjacent host proof that remaining peers accept only delayed removed-sender envelopes from before the persisted cutoff.
- `drain_group_offline_inbox_use_case_test.dart` proves offline replay carries the persisted removal cutoff across cursor pages.
- GM-004 through GM-012 accepted proofs cover removal, re-add, duplicate mutation, stale add, and stale remove behavior, but none owns the simultaneous Charlie send while Alice removes Charlie.
- `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart` currently enumerate scenarios through `gm012`; `gm013` is unsupported.

Missing for GM-013:

- A direct regression that captures the clear after-cutoff rejection event.
- A row-owned host proof with both Alice and Bob accepting the before-cutoff Charlie envelope exactly once and rejecting the after-cutoff envelope.
- Criteria positive and negative fixtures for nondeterminism, accept-after-cutoff, reject-before-cutoff, missing clear event, missing delivery, and Charlie post-removal access.
- Exact `--scenario gm013` simulator proof.

### regression/tests to add first

Add proof before product edits:

1. Add focused cutoff/event coverage in `handle_incoming_group_message_use_case_test.dart`.
   - Capture flow events with `debugSetFlowEventSink`.
   - Assert before-cutoff Charlie message persists exactly once.
   - Assert after-cutoff Charlie message returns null, is not persisted, and emits `GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF` with the expected `cutoffAt`.
   - Assert replay of an after-cutoff envelope with the same `messageId` cannot overwrite the accepted before-cutoff row.

2. Add focused listener coverage in `group_message_listener_test.dart`.
   - Deliver a `member_removed` system event with deterministic `removedAt`.
   - Deliver Charlie message events with timestamps immediately before and at/after `removedAt`.
   - Assert the listener adds only the before-cutoff message to its stream/repo and captures a clear rejection event for the after-cutoff message.

3. Add GM-013 host proof in `group_membership_smoke_test.dart`.
   - Arrange Alice/Bob/Charlie as current members.
   - Create a Charlie before-cutoff envelope under the old epoch.
   - Apply Alice removal plus key rotation/config update.
   - Deliver Charlie before-cutoff and after-cutoff envelopes to Alice/Bob around the boundary.
   - Assert Alice/Bob accept the before-cutoff message exactly once, reject the after-cutoff message with an event/verdict, remain at the post-removal epoch/config excluding Charlie, and continue A/B delivery.
   - Assert Charlie has no post-removal plaintext and post-removal app send is rejected.

Stop before product edits if those focused proofs pass and only criteria/runner/harness support is missing. If any proof fails, patch only the failing owner seam and rerun the focused proof before continuing.

### step-by-step implementation plan

1. Snapshot `git status --short`; preserve unrelated dirty/user/agent edits.
2. Add the focused cutoff/event regression in `handle_incoming_group_message_use_case_test.dart`; run it by plain name. If it fails, patch `handle_incoming_group_message_use_case.dart` only enough to enforce the strict `< removalCutoffAt` rule and clear rejection event.
3. Add the focused listener regression in `group_message_listener_test.dart`; run it by plain name. If it fails because the listener does not preserve the cutoff or event signal, patch only `group_message_listener.dart` or the timeline/cutoff repository seam.
4. Add the GM-013 host integration proof in `group_membership_smoke_test.dart`. Use deterministic timestamps:
   - `beforeSentAt = removedAt - 1 millisecond`
   - `afterSentAt = removedAt`
   - Both messages identify Charlie and carry stable message IDs.
5. If the host proof shows Alice/Bob config/key state is wrong after removal, inspect and narrowly patch `remove_group_member_use_case.dart`, `group_key_update_listener.dart`, or `group_config_payload.dart`. If post-removal sender authorization fails locally, inspect `send_group_message_use_case.dart`.
6. Add `gm013` scenario support in `group_multi_party_device_criteria.dart`:
   - scenario requirement for Alice/Bob/Charlie
   - supported-scenario error text
   - expected proof messages
   - `_validateGm013...` checks for cutoff ordering, exactly-once before delivery, after rejection event, final epoch/config, Charlie exclusion, Alice/Bob post-removal delivery, and Charlie non-access.
7. Add positive and negative GM-013 criteria tests in `group_multi_party_device_criteria_test.dart`. Negative tests must fail nondeterminism, accept-after-cutoff, reject-before-cutoff, missing clear event, missing delivery, duplicate delivery, Charlie still in Alice/Bob membership, Charlie post-removal plaintext, and accepted Charlie post-removal send.
8. Add `--scenario gm013` support in `run_group_multi_party_device_real.dart`, including `_scenariosToRun`, validation text, and role-device mapping through the criteria helper.
9. Add GM-013 role flows in `group_multi_party_device_real_harness.dart`:
   - Alice creates/imports A/B/C, records `removalCutoffAt`, applies remove plus key rotation/config update, and coordinates boundary delivery.
   - Bob imports/processes the same boundary and reports before/after receive/reject fields.
   - Charlie starts the old-epoch/before-cutoff publish fixture, then after removal proves no post-removal plaintext and rejected post-removal send.
   - Prefer captured app flow events for rejection proof. If flow events are not reliable inside the harness, record an explicit verdict field from the same receiver-side rejection source and cover it with criteria tests.
10. Run focused tests, criteria, analyzer, and exact simulator proof.
11. If the exact simulator proof fails because of Xcode, DerivedData, stale app containers, app extension state, or simulator boot state, fix that state and rerun. Do not close GM-013 with a simulator/build-state blocker.
12. Run named gates and whitespace hygiene.
13. Leave the source matrix and breakdown closure ledger untouched; closure updates are a later closure-audit task.

### risks and edge cases

- Go live publish stamps `timestamp` inside `PublishGroupMessage`; Dart `sendGroupMessage(timestamp:)` controls the durable/replay payload timestamp. GM-013 proof must be explicit about which ingestion path proves the cutoff. If live PubSub validation rejects a legitimate pre-cutoff envelope before Flutter can apply the app cutoff, classify whether that is a GM-013 product gap or whether durable replay is the intended acceptance path.
- Receiver ordering must be deterministic. The criteria must reject verdicts where `beforeSentAt`, `afterSentAt`, and `removalCutoffAt` are missing or not strictly ordered.
- Dedup must preserve the accepted pre-cutoff row if an after-cutoff replay reuses the same `messageId`.
- Rejection event capture must not leak plaintext, key material, private keys, or full peer IDs beyond existing diagnostic policy.
- Charlie may be removed locally before attempting the post-removal send; both `groupNotFound` and `unauthorized` are acceptable send-rejection outcomes if criteria records `accepted: false` and a clear outcome.
- Existing dirty files in this worktree may include prior agents' product/test/harness edits. Work with them; do not revert them.
- Simulator state is a fix-and-rerun concern, not a row-closure blocker.

### exact tests and gates to run

Focused proof:

```bash
git status --short
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'GM-013'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-013'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-013 simultaneous admin remove and member send'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-013
```

Direct regression suites:

```bash
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
```

Targeted analyzer:

```bash
dart analyze \
  lib/features/groups/application/handle_incoming_group_message_use_case.dart \
  lib/features/groups/application/group_message_listener.dart \
  lib/features/groups/application/remove_group_member_use_case.dart \
  lib/features/groups/application/group_key_update_listener.dart \
  lib/features/groups/application/group_config_payload.dart \
  lib/features/groups/application/send_group_message_use_case.dart \
  integration_test/group_multi_party_device_real_harness.dart \
  integration_test/scripts/run_group_multi_party_device_real.dart \
  integration_test/scripts/group_multi_party_device_criteria.dart \
  test/integration/group_multi_party_device_criteria_test.dart \
  test/features/groups/application/handle_incoming_group_message_use_case_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/integration/group_membership_smoke_test.dart
```

Exact simulator-only proof:

```bash
flutter devices --machine
xcrun simctl list devices available
MKNOON_RELAY_ADDRESSES="$MKNOON_RELAY_ADDRESSES" \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario gm013 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

If simulator/Xcode/build state fails, repair and rerun the exact command. Acceptable repair steps include:

```bash
rm -rf build/ios
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-* ~/Library/Developer/Xcode/DerivedData/Pods-*
for id in 38FECA55-03C1-4907-BD9D-8E64BF8E3469 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD 5BA69F1C-B112-47BE-B1FF-8C1003728C8F; do
  xcrun simctl uninstall "$id" com.mknoon.app || true
  xcrun simctl uninstall "$id" com.mknoon.app.ShareExtension || true
  xcrun simctl uninstall "$id" com.mknoon.app.NotificationService || true
  xcrun simctl shutdown "$id" || true
  xcrun simctl boot "$id"
  xcrun simctl bootstatus "$id" -b
done
```

Named gates and hygiene:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-013-plan.md
git diff --check
```

Go tests are conditional only if Go files are touched:

```bash
(cd go-mknoon && go test ./node -run 'GroupTopicValidator|PublishGroupMessage|GroupInbox')
```

### known-failure interpretation

- Pre-existing failures outside the GM-013 touched paths are not row regressions, but they must be recorded with exact command output and rerun if touched.
- A failure in a focused GM-013 test is caused by this session until proven otherwise.
- Simulator boot/build/DerivedData/app-container failures are not accepted GM-013 blockers. The plan requires cleanup and rerun until the exact simulator proof either passes or exposes a real code/test defect.
- Existing dirty matrix, breakdown, GM-008 through GM-012 plans, and product/test/harness files belong to prior user/agent work. Do not revert them.
- `git diff --check` failures in files touched by GM-013 must be fixed. Whitespace failures in unrelated dirty files should be documented separately and not hidden by broad cleanup.

### done criteria

- GM-013 focused cutoff/listener/host/criteria tests pass.
- Criteria includes positive and negative GM-013 fixtures and rejects nondeterminism, accept-after-cutoff, reject-before-cutoff, missing clear event, missing delivery, duplicate delivery, Charlie post-removal plaintext, and Charlie accepted post-removal send.
- `run_group_multi_party_device_real.dart` accepts `--scenario gm013`.
- `group_multi_party_device_real_harness.dart` writes Alice/Bob/Charlie GM-013 verdicts with cutoff timestamps, before/after delivery or rejection, clear event/reason, final epoch/config/membership, Alice/Bob continuation, and Charlie non-access.
- Exact simulator proof passes on the three required iOS simulator IDs with aggregate verdict `scenario: gm013`, `ok: true`.
- Targeted analyzer, direct suites, `groups`, `completeness-check`, and diff whitespace checks pass.
- No source matrix, breakdown closure ledger, or final program verdict is written by GM-013 execution.

### scope guard

- Do not reopen GM-001 through GM-012.
- Do not implement GM-014 simultaneous re-add/send or any later GM/GK/GA/GI row.
- Do not add a new global membership ordering architecture unless proof shows current timestamp/watermark semantics cannot express GM-013.
- Do not widen named gates or change gate definitions unless a new test file is added and completeness classification requires it.
- Do not make real physical devices part of acceptance.
- Do not edit Go transport/inbox code unless focused GM-013 evidence proves the acceptance/rejection bug lives there.
- Do not replace existing event-log, watermark, or group config payload patterns with a broad new abstraction.

### accepted differences / intentionally out of scope

- The matrix says "version" and "epoch"; current app membership ordering uses event timestamps plus `lastMembershipEventAt`, while key material uses key epochs. GM-013 will map the cutoff to timestamps unless code evidence proves a durable version field is available and already authoritative.
- App-layer replay/inbox cutoff proof is acceptable for before-cutoff acceptance if live PubSub validation would otherwise reject after Alice/Bob have already applied the new config. A separate live-validator backstop for stale subscriptions remains GM-017 unless GM-013 proof shows it is required here.
- `--scenario all` expansion is not required for GM-013 closure; direct `--scenario gm013` is the required proof.
- Matrix and breakdown closure updates are intentionally left for a later closure-audit step.

### dependency impact

- GM-014+ should not start from assumptions about simultaneous race handling until GM-013 records a clear cutoff contract and proof fields.
- Later authorization/validator rows can reuse GM-013 rejection event fields, but must not be closed by GM-013.
- If GM-013 changes the cutoff primitive away from timestamps, GM-011 and GM-012 stale-event acceptance should be rechecked before further membership-race rows proceed.
- If simulator cleanup is needed again, record the exact cleanup in the GM-013 execution progress so later row plans can distinguish environment repair from product behavior.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- Exact relay address value is not hardcoded in the plan; use the established accepted relay environment for this repo.
- `--scenario all` convenience expansion remains out of scope.
- Go-level live validator acceptance for pre-cutoff stale envelopes is conditional on evidence; the current plan starts at the app cutoff and simulator proof layers.

## Accepted differences intentionally left unchanged

- Timestamp cutoff semantics are accepted as the current implementation model for this row.
- Simulator-only proof is required; physical devices and external manual proof are not part of acceptance.
- Source matrix and breakdown closure state remain unchanged during plan/execution.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_membership_event_watermark.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/core/utils/flow_event_emitter.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/shared/fakes/group_test_user.dart`

## Why the plan is safe to implement now

The plan is narrow, proof-first, and grounded in existing cutoff behavior. It names the deterministic rule, adds direct regressions before product edits, requires criteria to fail the exact unsafe outcomes, keeps simulator proof mandatory, and confines any code change to the owner seam that a focused test proves broken. It also protects the active rollout state by not reopening GM-001 through GM-012 and by not editing the source matrix, breakdown closure ledger, or final program verdict.
