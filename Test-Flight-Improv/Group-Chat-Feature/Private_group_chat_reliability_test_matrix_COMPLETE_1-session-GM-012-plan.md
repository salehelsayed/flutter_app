Status: accepted/closed

# GM-012 Plan: Add Then Stale Remove Arrives Out Of Order

## Planning Progress

- 2026-05-10T21:28:39Z | Arbiter completed | Files inspected since last update: reviewer pass and final plan sections. | Decision/blocker: no structural blockers remain; reviewer adjustment was an incremental detail and has been applied; accepted differences are documented. | Next action: run doc hygiene and report the final verdict.
- 2026-05-10T21:28:10Z | Reviewer completed; Arbiter started | Files inspected since last update: draft GM-012 plan sections and mandatory-section/header scan. | Decision/blocker: sufficient with one non-structural adjustment: make Bob's post-stale-remove send mandatory so the closure bar proves Alice/Bob/Charlie delivery exactly, not an optional reduced flow. | Next action: classify the reviewer finding and finalize if no structural blocker remains.
- 2026-05-10T21:28:10Z | Planner completed; Reviewer started | Files inspected since last update: draft GM-012 plan content. | Decision/blocker: draft contains all mandatory plan sections, simulator-only proof, exact IDs, named gates, diff hygiene, scope guard, and reopen conditions. | Next action: review for stale assumptions, missing gates/proofs, and overbroad scope.
- 2026-05-10T21:26:08Z | Evidence Collector completed; Planner started | Files inspected since last update: `group_message_listener.dart`, `group_message_listener_test.dart`, `group_membership_smoke_test.dart`, `group_multi_party_device_real_harness.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, `test-gate-definitions.md`, `add_group_member_use_case.dart`, `remove_group_member_use_case.dart`, `group_test_user.dart`, `flutter devices --machine`, `xcrun simctl list devices available` | Decision/blocker: no planning blocker; GM-012 is not closed by the nearby listener test because row-owned host, criteria, runner, durable recipient, send/decrypt, key/config, and exact simulator proof are missing. | Next action: draft the execution plan with proof-first implementation, simulator-only evidence, and closure/reopen conditions.
- 2026-05-10T21:24:30Z | Evidence Collector started | Files inspected since last update: source matrix row GM-012 via `rg`; session breakdown row GM-012 via `rg`; repo status via `git status --short`; `implementation-plan-orchestrator/SKILL.md` | Decision/blocker: target plan file did not exist; worktree has unrelated dirty matrix, breakdown, product, test, and harness edits that must be preserved. | Next action: inspect current membership listener, row-adjacent tests, runner, harness, criteria, and gate definitions before drafting.

## Execution Progress

- 2026-05-10T22:10:19Z | QA recovery final verdict written | Files inspected or touched: `/tmp/gm012_executor_result.txt`, aggregate verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm012_KrNL8h/gmp_1778450066004_gm012_orchestrator_verdict.json`, Alice/Bob/Charlie role verdict JSONs in the same directory, current GM-012 diffs/status, source matrix GM-012 row, breakdown GM-012 rows, and this plan progress section only. | QA findings/verdict: `accepted`; this entry supersedes the prior `spawn_or_tool_failure` QA note because local recovery QA verified the landed GM-012 evidence and found no blocking issues. Executor changed paths are within the GM-012 plan scope or direct targeted-analyzer fallout; the source matrix GM-012 row and breakdown GM-012 ledger/inventory rows remain unchanged/open by execution. | Evidence verified: aggregate verdict records `scenario: gm012`, `ok: true`, and exact role devices Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; role verdicts prove final A/B/C membership includes Charlie exactly once, one Charlie member row and one active device binding, epoch `2`, stale remove ignored, unique post-readd recipients including Charlie where applicable, Alice/Bob/Charlie delivery including Bob's send leg, and no stale stranding. Focused reruns passed: GM-012 listener regression, GM-012 host smoke, GM-012 criteria, JSON artifact validation, full `git diff --check`, tracked plan-scoped `git diff --check -- <plan>`, and no-index plan whitespace check for the untracked plan file. | Next action: none for GM-012 QA recovery; accepted with no blockers.
- 2026-05-10T22:05:43Z | QA Reviewer blocked without final report | Files inspected or touched: isolated QA child read this plan, `/tmp/gm012_executor_result.txt`, GM-012 diffs, and simulator verdict/log artifacts; controller touched this plan progress section only. | QA findings/verdict: `BLOCKED` with blocker class `spawn_or_tool_failure`; the isolated QA Reviewer produced partial inspection evidence but did not write `/tmp/gm012_qa_result.txt` or return the requested concise QA verdict before the bounded wait was exhausted, so GM-012 cannot be formally accepted in this execution pass. | Evidence inspected before termination: aggregate verdict `gmp_1778450066004_gm012_orchestrator_verdict.json` showed `scenario: gm012`, `ok: true`, exact role device IDs, and role verdict paths; role verdicts showed Charlie exactly once in final member sets, `charlieMemberRowCount: 1`, `charlieActiveDeviceBindingCount: 1`, epoch `2`, and Alice/Bob/Charlie post-stale-remove sent/received legs including Bob. | Next action: rerun an isolated QA Reviewer pass from the existing executor evidence; no fix-pass Executor has been started because the blocker is missing QA finalization, not an identified code/test defect.
- 2026-05-10T22:00:56Z | Final status inspected; generated side effect cleaned | Files inspected or touched: `info.plist`, final `git status --short`, this plan progress section. | Result: removed simulator/Xcode `LastAccessedDate` timestamp churn from `info.plist`; final status still contains expected prior dirty matrix/breakdown/GM-008-through-GM-012 plan files and prior GM-008-through-GM-011 product/test/harness edits alongside GM-012 executor changes. | Hygiene rerun: full `git diff --check` and plan-specific `git diff --check` passed. | Next action: hand off to separate QA Reviewer review.
- 2026-05-10T22:00:10Z | Diff hygiene passed; Executor handoff preparing | Files inspected or touched: this plan progress section and full worktree diff. | Result: plan-specific `git diff --check` passed; full `git diff --check` passed. | Failure triage: no hygiene failures. | Next action: inspect final status/diff summary and hand off to separate QA Reviewer review.
- 2026-05-10T21:59:47Z | Completeness gate passed; diff hygiene starting | Files inspected or touched: `scripts/run_test_gates.sh`, completeness classification output, this plan progress section. | Result: `./scripts/run_test_gates.sh completeness-check` passed with `731/731 test files classified`. | Commands: `git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-012-plan.md`; `git diff --check`. | Next action: record hygiene result, inspect final diff/status, and prepare Executor handoff.
- 2026-05-10T21:59:28Z | Groups gate passed; completeness gate starting | Files inspected or touched: `scripts/run_test_gates.sh`, group messaging gate suites, this plan progress section. | Result: `./scripts/run_test_gates.sh groups` passed. | Command: `./scripts/run_test_gates.sh completeness-check`. | Next action: record result, then run diff hygiene.
- 2026-05-10T21:58:38Z | Simulator proof passed; named gates starting | Files inspected or touched: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, simulator verdict files, this plan progress section. | Result: exact GM-012 three-iOS-simulator proof passed for Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; aggregate verdict `gmp_1778450066004_gm012_orchestrator_verdict.json` records `scenario: gm012`, `ok: true`, and valid role verdicts. | Verdict path: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm012_KrNL8h`. | Command: `./scripts/run_test_gates.sh groups`. | Next action: run required named gates and hygiene.
- 2026-05-10T21:54:07Z | Simulator discovery passed; exact GM-012 proof starting | Files inspected or touched: `flutter devices --machine`, `xcrun simctl list devices available`, this plan progress section. | Result: Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` are available and booted. | Command: `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm012 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. | Next action: record simulator result or triage/fix any simulator/build failure.
- 2026-05-10T21:53:40Z | Direct suites completed; simulator discovery starting | Files inspected or touched: `test/integration/group_multi_party_device_criteria_test.dart`, this plan progress section. | Result: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed. | Commands: `flutter devices --machine`; `xcrun simctl list devices available`. | Next action: verify exact simulator IDs, then run the GM-012 simulator proof.
- 2026-05-10T21:53:23Z | Direct suite passed; final direct suite starting | Files inspected or touched: `test/features/groups/integration/group_new_member_onboarding_test.dart`, this plan progress section. | Result: `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed. | Command: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`. | Next action: record result, then run simulator-only GM-012 proof.
- 2026-05-10T21:53:06Z | Direct suite passed; next direct suite starting | Files inspected or touched: `test/features/groups/application/add_group_member_use_case_test.dart`, this plan progress section. | Result: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart` passed. | Command: `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`. | Next action: record result, then continue direct suites.
- 2026-05-10T21:52:49Z | Direct suite passed; next direct suite starting | Files inspected or touched: `test/features/groups/application/member_removal_integration_test.dart`, this plan progress section. | Result: `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart` passed. | Command: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart`. | Next action: record result, then continue direct suites.
- 2026-05-10T21:52:25Z | Direct suite passed; next direct suite starting | Files inspected or touched: `test/features/groups/integration/group_membership_smoke_test.dart`, this plan progress section. | Result: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` passed. | Command: `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`. | Next action: record result, then continue direct suites.
- 2026-05-10T21:50:53Z | Direct suite passed; next direct suite starting | Files inspected or touched: `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, this plan progress section. | Result: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` passed. | Command: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`. | Next action: record result, then continue direct suites.
- 2026-05-10T21:50:20Z | Direct suite started | Files inspected or touched: `test/features/groups/application/group_message_listener_test.dart`, this plan progress section. | Command: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`. | Next action: record result, then continue direct suites.
- 2026-05-10T21:50:20Z | Targeted analyzer passed; direct regression suites starting | Files inspected or touched: targeted analyzer file set and this plan progress section. | Result: exact targeted analyzer command exited 0; remaining output is two informational `use_null_aware_elements` suggestions in `group_key_update_listener.dart`. | Failure triage: no blocking analyzer failure remains. | Next action: run the required direct regression suites.
- 2026-05-10T21:49:50Z | Targeted analyzer failed and was triaged; lint-only required cleanup applied | Files inspected or touched: `lib/features/groups/application/group_key_update_listener.dart`, this plan progress section. | Result: targeted analyzer failed on pre-existing `group_key_update_listener.dart` warnings (`unnecessary_null_comparison`, `dead_code`, `unnecessary_non_null_assertion`). | Failure triage: unrelated-but-required; this file is part of the mandated targeted analyzer command and the cleanup is lint-only after the existing non-null source-peer guard. | Fix: removed the unreachable null branch and no-op non-null assertions. | Next action: rerun the exact targeted analyzer.
- 2026-05-10T21:48:37Z | Focused criteria proof passed; targeted analyzer starting | Files inspected or touched: `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, this plan progress section. | Result: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-012` passed. | Failure triage: none. | Next action: run the required targeted analyzer before simulator proof.
- 2026-05-10T21:48:11Z | GM-012 criteria, runner, and harness support added; focused criteria test starting | Files inspected or touched: `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, this plan progress section. | Decision/blocker: added `gm012` scenario requirement, expected Alice/Charlie/Bob proof messages, stale-remove-readd criteria validation, positive and negative criteria fixtures, runner `--scenario gm012`, and three-role harness flow. | Command: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-012`. | Next action: run focused criteria proof and fix any criteria/harness compile or validation failures.
- 2026-05-10T21:42:22Z | Focused host proof passed; criteria and runner edits starting | Files inspected or touched: `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, this plan progress section. | Result: rerun `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-012 add then stale remove arrives out of order'` passed. | Failure triage: prior failure closed as caused-by-session test setup. | Next action: add GM-012 criteria positive/negative tests plus runner/harness support.
- 2026-05-10T21:41:33Z | Focused host proof failed and was triaged; narrow test setup fix applied | Files inspected or touched: `test/features/groups/integration/group_membership_smoke_test.dart`, this plan progress section. | Result: first host run failed because Alice's latest fake bridge config still reflected the remove-v2 config. | Failure triage: caused by this session's new test setup, not product code; the fake `GroupTestUser.addMember` bootstrap helper does not call the product `addGroupMember` bridge-config path. | Fix: switched the GM-012 v3 re-add setup to `addGroupMember` plus explicit Charlie bootstrap. | Next action: rerun the exact focused host proof.
- 2026-05-10T21:40:20Z | Host integration proof added; focused host test starting | Files inspected or touched: `test/features/groups/integration/group_membership_smoke_test.dart`, this plan progress section. | Decision/blocker: added GM-012 host proof for final A/B/C membership, one Charlie row/device binding, current key/config, stale-remove no-op, unique durable recipients including Charlie, and Alice/Bob/Charlie delivery including Bob's send leg. | Command: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-012 add then stale remove arrives out of order'`. | Next action: run focused host proof and triage any failure before product edits.
- 2026-05-10T21:38:09Z | Focused listener proof passed | Files inspected or touched: `test/features/groups/application/group_message_listener_test.dart`, this plan progress section. | Result: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-012'` passed. | Failure triage: none; current product stale-remove logic satisfies the proof, so no product fix is warranted at this point. | Next action: add GM-012 host integration, criteria, runner, and simulator harness support.
- 2026-05-10T21:37:45Z | Focused listener proof added; focused listener test starting | Files inspected or touched: `test/features/groups/application/group_message_listener_test.dart`, this plan progress section. | Decision/blocker: added GM-012 remove-v2/readd-v3/restart/stale-remove-v2 listener regression with version-3 joined/device/config assertions; no product files changed. | Command: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-012'`. | Next action: run the focused listener proof and classify any failure before product edits.
- 2026-05-10T21:36:16Z | Executor inspection completed | Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_event_watermark.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/shared/fakes/group_test_user.dart`; touched this plan progress section only. | Decision/blocker: GM-011 patterns are reusable; current listener stale-remove guard appears capable of expressing GM-012 via timestamp watermark plus re-added `joinedAt`, but proof must be added and run before any product fix. | Next action: add and run the focused GM-012 listener regression.
- 2026-05-10T21:32:42Z | Executor started | Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-012-plan.md`, `git status --short`, `implementation-execution-qa-orchestrator/SKILL.md`; touched this plan progress section only. | Decision/blocker: proceeding as Executor only; GM-012 scope is proof-first stale version-2 remove after version-3 re-add with simulator-only closure evidence. | Next action: inspect owner files and existing GM-011 patterns before adding GM-012 tests.
- 2026-05-10T21:31:10Z | Controller contract extraction started | Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-012-plan.md`, `git status --short`, `implementation-execution-qa-orchestrator/SKILL.md`; touched this plan progress section only. | Decision/blocker: execution contract is concrete and scoped to GM-012; source matrix and session breakdown closure rows remain untouched; isolated child execution will use `codex exec` with `model=gpt-5.5` and `model_reasoning_effort=xhigh`. | Next action: spawn the Executor child agent for the first implementation pass.

## Closure Audit

Closure verdict: `closed` / accepted for GM-012. The accepted execution and QA evidence prove that a version-2 stale `member_removed` delivered after a version-3 re-add is ignored, so Charlie remains current and unstranded.

What is now closed:

- Source matrix row GM-012 is `Covered`.
- Existing timestamp watermark behavior is accepted as sufficient for stale remove-after-readd; no GM-012 product behavior fix was required.
- The only product-path file touched by execution was `lib/features/groups/application/group_key_update_listener.dart` for lint-only targeted-analyzer cleanup.
- Row-owned proof files from execution: `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and this plan.

Accepted simulator proof:

- Exact simulator-only command passed with `--scenario gm012` on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm012_KrNL8h/gmp_1778450066004_gm012_orchestrator_verdict.json` records `scenario: gm012`, `ok: true`, and `gm012 verdicts valid for alice, bob, charlie`.
- Role verdicts prove final A/B/C membership includes Charlie exactly once, one Charlie member row and one active device binding, final epoch `2` with current config, stale remove ignored, no Charlie stranding, unique durable recipients including Charlie where applicable, and exact Alice/Bob/Charlie delivery including Bob's send leg.

Maintenance gates passed:

- Focused GM-012 listener regression, focused GM-012 host integration, focused GM-012 criteria, full listener suite, full `group_membership_smoke_test.dart`, `member_removal_integration_test.dart`, `add_group_member_use_case_test.dart`, `group_new_member_onboarding_test.dart`, full `group_multi_party_device_criteria_test.dart`, targeted analyzer, exact three-iOS-simulator `gm012`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`.
- QA recovery reran the focused listener, host, and criteria proofs plus diff hygiene and accepted the evidence.

Residual-only items: none for GM-012.

Still-open items: GM-013 and later rows remain open; no final program verdict is written from this GM-012 closure.

Accepted differences:

- The row's version-2/version-3 language maps to deterministic timestamp ordering in the current app code.
- Direct `--scenario gm012` simulator proof is sufficient; `--scenario all` expansion is not required for GM-012 closure.
- Checkpoint policy was skipped because the worktree contains dirty overlapping aggregate rollout artifacts and unrelated/overlapping product/test edits, making a clean scoped checkpoint unsafe.

Reopen GM-012 only on a real regression against stale-remove rejection after newer re-add, Charlie member/device uniqueness, current config/key preservation, durable-recipient inclusion, or exact A/B/C post-readd delivery.

## real scope

Own exactly GM-012: remove Charlie at version 2, re-add Charlie at version 3, deliver the older version 2 `member_removed` late, then prove final membership, config/key state, durable recipients, and delivery remain current with Charlie re-added.

Allowed execution work:

- Add row-owned GM-012 proof in the listener, host integration, criteria, runner, and simulator harness.
- Make the smallest product fix only if proof-first tests show the late older remove can delete/strand Charlie, roll back current config/key state, drop durable recipients, or break Alice/Bob/Charlie delivery.
- Touch only files needed for GM-012 behavior/proof and direct fallout from those edits.

Explicitly not in scope:

- Do not edit the source matrix or session breakdown closure rows during execution.
- Do not reopen GM-001 through GM-011. They remain Covered.
- Do not implement GM-013 or later race/durable-recipient/key-package rows.
- Do not depend on real external devices; GM-012 E2E proof is iOS-simulator-only.

## closure bar

GM-012 can close only when all of these are true:

- The scenario applies `member_removed` version 2 for Charlie, applies `member_added`/re-add version 3 for Charlie, then delivers the version 2 remove after version 3.
- Final Alice, Bob, and Charlie state keeps Charlie re-added/current because version 3 wins.
- Charlie has exactly one active membership row and exactly one active device binding after the stale remove replay.
- The old remove does not delete Charlie, strand Charlie without a group, unsubscribe/disable the current device binding, roll back validator/group config, roll back key state, or restore an older removed-window access decision.
- Alice/Bob/Charlie can send and receive under the current post-readd config/key state with exact-once proof: Bob and Charlie receive Alice, Alice and Bob receive Charlie, and Alice receives Bob.
- Durable recipients include Charlie for post-readd sends and remain unique; removed-window messages from adjacent rows are not reclassified.
- Criteria reject stale-remove stranding, Charlie removal, duplicate Charlie membership/device binding, config/key rollback, missing durable recipients, missing delivery, and incomplete/mismatched role proof.
- The exact simulator verdict records `scenario: gm012`, `ok: true`, and valid Alice/Bob/Charlie role verdicts on the three requested iOS simulators:
  - Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`
  - Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`
  - Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
- `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` pass after the GM-012 implementation.

## source of truth

- Current code and tests win over stale prose.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-012 defines the scenario and expected behavior.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row GM-012 now records `covered/accepted`; GM-013 and later rows remain open.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define named gates; if they disagree, the script wins.
- In current code, row "version 2/version 3" should be represented by deterministic membership event timestamps unless implementation evidence finds a separate durable version field. The relevant current guards are `GroupMessageListener._shouldIgnoreStaleMembershipEvent`, `_shouldIgnoreStaleMemberRemovedEvent`, and `Group.lastMembershipEventAt`.
- This doc is now the GM-012 closure reference because it has reached `Status: accepted/closed`.

## session classification

accepted/closed

Rationale: row-owned listener, host, criteria, runner, and exact simulator proof passed. The proof showed existing timestamp watermark behavior is sufficient for stale remove-after-readd, so no GM-012 product behavior fix was required.

## exact problem statement

GM-012 was open before execution because the repo lacked row-owned proof that a late older remove cannot undo a newer re-add. The concrete risk was that Alice removes Charlie, Alice re-adds Charlie with current membership/key/config state, then a delayed remove event applies after the re-add and strands Charlie: Charlie may lose local group state, disappear from validator config or durable recipients, lose key/device binding state, or fail to send/decrypt current messages.

Accepted execution proved the current user-visible behavior: after the stale remove is delivered late, Charlie remains a current member and Alice/Bob/Charlie delivery remains reliable and exact. Covered behavior from GM-001 through GM-011 remains unchanged.

## files and repos to inspect next

Production and helper seams:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_membership_event_watermark.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `test/shared/fakes/group_test_user.dart`

Host tests and simulator proof:

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Inspect-only unless Flutter/app proof shows a relay validator or durable inbox gap that cannot be proven at the app seam:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

## existing tests covering this area

- `test/features/groups/application/group_message_listener_test.dart` includes `older member_removed cannot roll back a newer added admin state after restart`. This proves the listener can ignore an older `member_removed` after a newer `member_added` when the existing member's `joinedAt` is after the remove timestamp, but it does not close GM-012 because it lacks row-specific host, criteria, runner/harness, durable-recipient, send/decrypt, and exact simulator proof.
- `group_message_listener.dart` currently has `_shouldIgnoreStaleMemberRemovedEvent`: it ignores stale removes at or before the membership watermark unless the existing member joined at or before the older remove, in which case the older remove can still apply. GM-012 must prove the re-added Charlie's current `joinedAt`/version-3 state wins.
- GM-011 added stale add-after-remove proof and `--scenario gm011`; those patterns are reusable but GM-012 must be separate because the winner is current re-add rather than current removal.
- `integration_test/scripts/group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart` currently enumerate scenarios through `gm011`; GM-012 scenario support is missing.
- `Test-Flight-Improv/test-gate-definitions.md` places `group_membership_smoke_test.dart` inside the Group Messaging Gate and requires completeness classification for new integration/cross-feature/orchestration tests.

## regression/tests to add first

Add proof before product edits:

1. Add a focused GM-012 listener regression in `group_message_listener_test.dart`.
   - Arrange Alice/Bob/Charlie and persist a version-2 remove timestamp followed by a version-3 re-add timestamp.
   - Restart or recreate the listener to prove durability, then deliver the older version-2 `member_removed` replay.
   - Assert Charlie remains present with the version-3 role/device state, `lastMembershipEventAt` remains version 3, `group:updateConfig` is not called for the stale remove, and no stale remove timeline/config rollback is accepted.

2. Add a GM-012 host integration proof in `group_membership_smoke_test.dart`.
   - Reuse GM-006/GM-007 remove/re-add setup and GM-011 stale-envelope injection style.
   - Capture the version-2 remove envelope, apply the version-3 re-add, then deliver the version-2 remove late through the app listener replay path.
   - Assert Alice/Bob/Charlie converge on A/B/C, Charlie has one active member row and one active device binding, latest config/key remains current, durable recipients include Charlie exactly once for current sends, and Alice/Bob/Charlie current sends/decrypts are exact.

3. Add GM-012 criteria positive and negative tests in `group_multi_party_device_criteria_test.dart`.
   - Positive fixture must include a complete `gm012StaleRemoveReaddProof`.
   - Negative fixtures must fail stale-remove stranding, Charlie missing from final membership, duplicate Charlie member/device binding, config/key rollback, stale durable recipients, missing Alice/Bob/Charlie delivery, missing or false proof fields, role mismatch, and non-`gm012` scenario values.

Stop before product edits if the focused listener and host proof pass with only test/harness/criteria support. If a proof fails, fix the narrow failing seam and rerun the focused proof before continuing.

## step-by-step implementation plan

1. Snapshot the worktree with `git status --short`; preserve unrelated dirty/user/other-agent edits.
2. Add the focused GM-012 listener regression in `group_message_listener_test.dart`; run it by plain name and record whether current stale-remove logic passes or fails.
3. If the listener regression fails, patch only the stale-remove ordering seam:
   - Preserve the existing timestamp watermark model unless a durable version field is found.
   - Ensure an older `member_removed` cannot remove a current member whose re-add/joinedAt is after the remove event.
   - Ensure stale remove payload `groupConfig` cannot overwrite current config/key/device state.
4. Add the GM-012 host proof in `group_membership_smoke_test.dart`.
   - Use deterministic timestamps: remove version 2 at `t2`, re-add version 3 at `t3`, then replay remove `t2` after `t3`.
   - Verify Charlie's member row, device binding, group presence, latest key/config, durable recipients, send result, and received-message counts.
5. If host proof fails outside the listener guard, patch only the directly implicated app seam:
   - `add_group_member_use_case.dart` if re-add does not persist a current joinedAt/device binding.
   - `remove_group_member_use_case.dart` if an older remove can still apply after a current re-add.
   - `group_key_update_listener.dart` or config payload handling only if key/config rollback is proven.
6. Add `gm012` support in `group_multi_party_device_criteria.dart`: scenario requirement, supported-scenario error text, expected message declarations, and `_validateGm012...` proof validation.
7. Add positive and negative GM-012 criteria tests in `group_multi_party_device_criteria_test.dart`.
8. Add `--scenario gm012` support in `run_group_multi_party_device_real.dart`, including `_scenariosToRun`, error/help text, and three-role selection.
9. Add GM-012 role flows in `group_multi_party_device_real_harness.dart`:
   - Alice creates A/B/C group, captures/remembers the version-2 remove envelope, removes Charlie, re-adds Charlie at version 3 with current config/key/device binding, then signals late delivery of the version-2 remove.
   - Bob and Charlie process the same ordering and report final membership/config/key proof.
   - Alice, Bob, and Charlie each perform current post-stale-remove proof sends/receives and write per-role verdicts with durable recipient lists.
10. Run focused host/criteria/analyzer commands, then the exact simulator-only proof.
11. If simulator or Xcode state fails, fix simulator/build state and rerun. Do not close GM-012 as blocked for environment state. Acceptable cleanup includes clearing relevant Runner/Pods DerivedData, removing `build/ios`, uninstalling `com.mknoon.app`, `com.mknoon.app.ShareExtension`, and `com.mknoon.app.NotificationService` from the three exact simulators, rebooting the exact simulators, rerunning discovery, and rerunning the exact GM-012 command.
12. Run named gates and hygiene. Do not update matrix or breakdown closure status during execution.

## risks and edge cases

- Version mapping: the row uses version 2/version 3, while current app code uses event timestamps and `lastMembershipEventAt`; tests must make the mapping explicit and deterministic.
- Joined-at correctness: GM-012 only holds if the re-added Charlie has current version-3 joinedAt/device binding state. A stale or preserved old joinedAt may let the conflict branch apply the older remove.
- Config rollback: the stale remove envelope may carry a config excluding Charlie; it must not overwrite the current re-add config.
- Key rollback/stranding: Charlie must retain the current key/config needed for current delivery and must not be left with an unusable group or old epoch.
- Durable recipients: current post-readd sends must include Charlie exactly once; missing or duplicate recipient proof should fail criteria.
- Simulator state: DerivedData, stale app containers, boot state, or build cache can invalidate E2E execution; this is fixable execution work, not accepted closure evidence.

## exact tests and gates to run

Focused proof:

```bash
git status --short
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-012'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-012 add then stale remove arrives out of order'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-012
```

Direct regression suites:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
```

Targeted analyzer:

```bash
dart analyze \
  lib/features/groups/application/group_message_listener.dart \
  lib/features/groups/application/add_group_member_use_case.dart \
  lib/features/groups/application/remove_group_member_use_case.dart \
  lib/features/groups/application/group_key_update_listener.dart \
  lib/features/groups/application/group_config_payload.dart \
  integration_test/group_multi_party_device_real_harness.dart \
  integration_test/scripts/run_group_multi_party_device_real.dart \
  integration_test/scripts/group_multi_party_device_criteria.dart \
  test/integration/group_multi_party_device_criteria_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/integration/group_membership_smoke_test.dart \
  test/shared/fakes/group_test_user.dart
```

Exact simulator-only proof:

```bash
flutter devices --machine
xcrun simctl list devices available
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario gm012 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Named gates and hygiene:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-012-plan.md
git diff --check
```

## known-failure interpretation

- A failing focused GM-012 regression before the product fix is expected evidence and should drive the narrow fix.
- Existing dirty changes outside GM-012 are not work for this session unless they directly affect GM-012 proof.
- GM-001 through GM-011 are covered. Do not reopen those rows for unrelated failures; classify failures as regressions only if GM-012 edits caused them.
- Simulator/Xcode/build-state failures must be remediated and rerun on the exact iOS simulators. They are not acceptable "blocked" closure evidence.
- Host-only proof, Android proof, macOS proof, or real external-device proof is insufficient for GM-012 closure.

## done criteria

- GM-012 listener regression proves a version-2 stale remove cannot roll back version-3 re-add after restart/replay.
- GM-012 host integration proves final A/B/C membership, exactly one Charlie membership/device binding, current config/key state, durable recipients including Charlie, and exact Alice/Bob/Charlie current delivery.
- GM-012 criteria positive and negative tests reject all closure-bar failure modes.
- Runner and harness support direct `--scenario gm012`.
- Exact three-iOS-simulator verdict records `scenario: gm012`, `ok: true`, and valid Alice/Bob/Charlie role verdicts using the requested simulator IDs.
- `groups`, `completeness-check`, and diff hygiene pass.
- Execution records evidence paths and exact commands in closure notes without editing the source matrix or session breakdown.

## rollback / reopen conditions

Reopen or keep GM-012 open if any of these occur:

- Late version-2 remove deletes Charlie, causes Charlie's current send/decrypt to fail, or removes Charlie from Alice/Bob current config.
- Charlie has zero or more than one active membership row, zero or more than one active device binding, or duplicate durable recipient entries.
- Current post-readd sends omit Charlie from durable recipients or fail exact delivery.
- Key/config state rolls back to the removed window or diverges across Alice/Bob/Charlie.
- Criteria accept a stale-remove stranding fixture, Charlie removal fixture, key/config rollback fixture, missing durable-recipient fixture, or missing-delivery fixture.
- Exact simulator proof is missing, uses non-iOS targets, uses real external devices, or lacks `scenario: gm012` with `ok: true`.

## scope guard

Non-goals:

- No source matrix or breakdown closure edits in the GM-012 execution session.
- No GM-013+ implementation.
- No broad rewrite of membership versioning, storage, key distribution, bridge commands, Go relay state, or `--scenario all` expansion unless a GM-012 proof failure makes a tiny local change necessary.
- No changes to covered GM-001 through GM-011 behavior except incidental regression fixes directly caused by GM-012 edits.
- No physical-device dependency.

Overengineering signals:

- Replacing the timestamp watermark system before tests prove it cannot express GM-012.
- Moving durable-recipient enforcement into unrelated relay/server layers without app-seam proof.
- Promoting the multi-party runner into a named gate instead of keeping it row-owned evidence.

## accepted differences / intentionally out of scope

- The row's "version" language maps to timestamp ordering in current app code. This is accepted unless implementation discovers a durable version field already used by membership events.
- `--scenario all` does not need to include GM-012 for closure; direct `--scenario gm012` proof is required.
- Go relay files are inspect-only unless Flutter/device evidence proves a validator or durable-inbox behavior cannot be proven or fixed in app code.
- Prior rows GM-001 through GM-011 remain closed/covered and are not re-audited here.

## dependency impact

- GM-013+ race/removal rows depend on GM-012 preserving deterministic membership ordering when stale events arrive late.
- GM-019/GM-020 durable-recipient rows should use GM-012 evidence only for the post-readd inclusion case; removed-window recipient exclusion remains owned by their rows.
- If GM-012 changes the stale-remove guard or re-add joinedAt semantics, later remove/re-add plans must reuse the new invariant and rerun their direct gates rather than inventing a second ordering rule.

## reviewer pass

- Sufficiency: sufficient with adjustment.
- Missing files, tests, or gates: none structurally missing after requiring listener, host, criteria, runner/harness, exact simulator proof, `groups`, `completeness-check`, and diff hygiene.
- Stale or incorrect assumptions: the plan correctly treats row versions as deterministic timestamps in current code and defers any durable-version model unless implementation evidence finds one.
- Overengineering: none required; the plan explicitly rejects broad membership-version rewrites and Go relay changes unless GM-012 proof requires a narrow fix.
- Decomposition: sufficient; proof-first listener/host work comes before product edits, then criteria/runner/harness, then exact simulator evidence.
- Minimum adjustment applied: Bob's post-stale-remove send is mandatory so delivery closure is complete for Alice, Bob, and Charlie.

## arbiter decision

- Structural blockers: none.
- Incremental details: require the Bob send leg as part of exact Alice/Bob/Charlie delivery proof; applied in the closure bar and harness steps.
- Accepted differences: timestamp ordering stands in for version ordering in the current architecture; direct `--scenario gm012` proof is sufficient without changing `--scenario all`; Go relay files remain inspect-only unless app/device evidence requires a narrow follow-up.
- Final classification: execution-ready.
