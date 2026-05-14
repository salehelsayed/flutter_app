# GM-015 Plan - Admin Removes Self/Creator Policy Is Explicit

Status: accepted by execution QA; closed by closure audit

## Execution Progress

| Time | Phase | Files inspected or touched | Command | Decision/blocker | Next action |
| --- | --- | --- | --- | --- | --- |
| 2026-05-11 03:19:56 CEST | QA Reviewer completed; execution accepted | GM-015 plan, Executor report, GM-015 diffs, focused tests, targeted analyzer, `groups`, `completeness-check`, diff checks, simulator verdict artifacts | `codex exec ... /tmp/gm015-qa-final.md`; QA reran `flutter test --no-pub ... --plain-name 'GM-015'`; `dart analyze ...`; `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh completeness-check`; `git diff --check`; inspected `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm015_gOh1Lx/gmp_1778461641801_gm015_orchestrator_verdict.json` | Accepted. Blocking issues: none. QA confirmed `block_last_admin/no_op`, exact simulator IDs, `gm015` criteria/runner/harness support, row-owned proof, and no source matrix/breakdown closure/final-program-verdict edit by GM-015 execution. | Report final GM-015 accepted verdict. |
| 2026-05-11 03:14:15 CEST | Diff checks passed; Executor completed | GM-015 changed files plus existing dirty worktree inspection | `git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-015-plan.md`; `git diff --check`; `git status --short`; `find /var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm015_gOh1Lx -maxdepth 1 -type f -name '*verdict*.json' -print`; `sed -n '1,220p' /var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm015_gOh1Lx/gmp_1778461641801_gm015_orchestrator_verdict.json` | Both diff checks passed. Exact orchestrator verdict path is `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm015_gOh1Lx/gmp_1778461641801_gm015_orchestrator_verdict.json`, with `scenario: gm015`, `ok: true`, and the required Alice/Bob/Charlie device IDs. Existing dirty source matrix/breakdown files were observed but not edited by this Executor; no final program verdict was edited. | Stop after Executor pass and hand off to QA Reviewer. |
| 2026-05-11 03:13:43 CEST | Completeness gate passed | Test classification gate | `./scripts/run_test_gates.sh completeness-check` | Passed: `731/731 test files classified`; `Completeness check PASS`. | Run diff whitespace checks and inspect final changed-file set. |
| 2026-05-11 03:13:22 CEST | Groups gate passed | Group messaging and membership gate suites | `./scripts/run_test_gates.sh groups` | Passed. The gate completed with `All tests passed!`. | Run `./scripts/run_test_gates.sh completeness-check`, then diff checks. |
| 2026-05-11 03:12:38 CEST | Exact simulator proof passed | `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/group_multi_party_device_real_harness.dart`; simulator verdicts under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm015_gOh1Lx` | `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm015 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` | Passed. Orchestrator reported `gm015 proof passed: gm015 verdicts valid for alice, bob, charlie`; logs/verdicts are in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm015_gOh1Lx`. | Run `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, then diff checks. |
| 2026-05-11 03:06:28 CEST | Adjacent tests and analyzer passed | Adjacent group membership/remove/leave/dissolve/role/listener suites; targeted analyzer files | `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart`; `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart`; `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`; `flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart`; `flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart`; `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'stored creator who is no longer admin cannot dissolve the group'`; `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'RP005 demoted creator receive-side mutations are rejected before side effects'`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'sole admin cannot leave while only writer members remain'`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'multi-admin leave keeps remaining admin healthy and synchronized'`; `dart analyze ...` | All adjacent tests passed. Targeted analyzer exited 0 with three existing info-level `use_null_aware_elements` notes in `send_group_message_use_case.dart`; no GM-015 compile/analyzer errors remain. | Run exact three-simulator `--scenario gm015`, then named gates and diff checks. |
| 2026-05-11 03:03:26 CEST | Focused GM-015 tests passed | GM-015 focused suites | `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart --plain-name 'GM-015'`; `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart --plain-name 'GM-015'`; `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-015'`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-015'`; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-015` | All five focused GM-015 tests passed after the narrow implementation. | Run adjacent regression tests and targeted analyzer. |
| 2026-05-11 03:02:16 CEST | Narrow implementation added | `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/group_multi_party_device_real_harness.dart`; `test/features/groups/integration/group_membership_smoke_test.dart` | `apply_patch`; `dart format ...` | Added explicit `VoluntaryLeaveBroadcastSkipReason.lastAdmin`, `gm015` criteria/runner/harness support, and fixed the GM-015 smoke fixture so Bob's local setup includes Charlie. Product policy remains `block_last_admin/no_op`. | Rerun focused GM-015 tests, then widen to adjacent tests/analyzer/gates. |
| 2026-05-11 02:58:41 CEST | Focused RED/GREEN triage | `test/features/groups/application/remove_group_member_use_case_test.dart`; `test/features/groups/application/leave_group_use_case_test.dart`; `test/features/groups/application/member_removal_integration_test.dart`; `test/features/groups/integration/group_membership_smoke_test.dart`; `test/integration/group_multi_party_device_criteria_test.dart` | `flutter test --no-pub ... --plain-name 'GM-015'`; `flutter test --no-pub ... --plain-name GM-015` | Direct remove and leave tests passed. Member-removal integration failed to compile because `VoluntaryLeaveBroadcastResult.skipReason`/`VoluntaryLeaveBroadcastSkipReason` do not exist. Criteria tests failed because `gm015` is unsupported. Smoke test exposed a test fixture setup gap: Bob's fake repo did not receive Charlie in setup before the GM-015 policy assertions. | Patch the narrow explicit skip reason, add `gm015` criteria/runner/harness support, and fix the smoke fixture setup without changing product policy. |
| 2026-05-11 02:57:38 CEST | Proof-first tests added | `test/features/groups/application/remove_group_member_use_case_test.dart`; `test/features/groups/application/leave_group_use_case_test.dart`; `test/features/groups/application/member_removal_integration_test.dart`; `test/features/groups/integration/group_membership_smoke_test.dart`; `test/integration/group_multi_party_device_criteria_test.dart` | `apply_patch` | Added GM-015 direct, integration, smoke, and criteria regressions before product edits. Criteria and voluntary-leave tests intentionally require explicit last-admin skip proof that the current product code/criteria do not yet expose. | Run focused GM-015 tests to capture RED result and classify gaps. |
| 2026-05-11 02:53:55 CEST | Owner files inspected | `lib/features/groups/application/remove_group_member_use_case.dart`; `lib/features/groups/application/leave_group_use_case.dart`; `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart`; `lib/features/groups/application/send_group_message_use_case.dart`; `test/features/groups/application/remove_group_member_use_case_test.dart`; `test/features/groups/application/leave_group_use_case_test.dart`; `test/features/groups/application/member_removal_integration_test.dart`; `test/features/groups/integration/group_membership_smoke_test.dart`; `test/shared/fakes/group_test_user.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart`; `test/integration/group_multi_party_device_criteria_test.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/group_multi_party_device_real_harness.dart` | `rg -n`; `sed -n` | Direct remove/leave already block sole-admin mutation. The voluntary-leave broadcast helper currently returns a generic skipped result for last-admin and missing-member cases, so GM-015 needs proof-first coverage for that explicitness gap. | Add GM-015 tests first, then run focused tests before product/harness fixes. |
| 2026-05-11 02:51:02 CEST | Executor started | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-015-plan.md`; `/Users/I560101/.codex/skills/flutter-test-orchestrator/SKILL.md`; `/Users/I560101/.codex/skills/run-flutter-reliability-sims/SKILL.md`; `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`; `git status --short` | `sed -n`; `git status --short`; `date '+%Y-%m-%d %H:%M:%S %Z'` | Executor pass started. Scope is GM-015 only; existing dirty source matrix/breakdown files are out of scope and will not be edited. | Inspect owner code/tests, then add proof-first GM-015 regressions before product edits. |
| 2026-05-11 02:49:06 CEST | Contract extracted | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-015-plan.md`; `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`; `git status --short`; `codex exec --help` | `sed -n`; `git status --short`; `codex exec --help` | GM-015 scope is explicit: preserve `block_last_admin/no_op`, add proof-first focused regressions and `gm015` criteria/runner/harness support, run required tests/gates/simulator proof, and do not edit source matrix/breakdown closure/final verdict. Worktree is dirty with prior rollout changes; spawning is available through `codex exec`. | Spawn isolated Executor agent with `model: gpt-5.5` and `reasoning_effort: xhigh`. |
| 2026-05-11 02:50:04 CEST | Executor spawn retry | GM-015 plan execution progress | `codex exec ... -a never` | Initial spawn command failed before child materialization because `codex exec` does not accept `-a`; no child work or file edits occurred. | Relaunch Executor with supported `codex exec` flags. |

## Planning Progress

| Time | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-11 02:41:00 CEST | Evidence Collector started | Source GM-015 row and breakdown GM-015 ledger references. | Evidence must determine current intended creator/admin invariant from code/tests before choosing block, transfer, or dissolve policy. | Inspect application use cases, group models/repositories/helpers, direct tests, criteria, runner, harness, and gate definitions. |
| 2026-05-11 02:45:45 CEST | Evidence Collector completed; Planner started | `remove_group_member_use_case.dart`; `leave_group_use_case.dart`; `broadcast_voluntary_leave_use_case.dart`; `dissolve_group_use_case.dart`; `send_group_message_use_case.dart`; `group_message_listener.dart`; `group_config_payload.dart`; group role/member models and repositories; `group_info_wired.dart`; direct remove/leave/role/dissolve/listener tests; `group_membership_smoke_test.dart`; `member_removal_integration_test.dart`; `group_multi_party_device_criteria.dart`; `group_multi_party_device_criteria_test.dart`; `run_group_multi_party_device_real.dart`; `group_multi_party_device_real_harness.dart`; `scripts/run_test_gates.sh`; `test-gate-definitions.md`. | Current intended policy is block-last-admin/no-op: direct removal, leave, and demotion block the last admin; stored creator identity is not permanent authority after demotion. GM-015 still lacks row-owned criteria and exact simulator `gm015` proof, and broadcast voluntary leave returns a skipped result without a reason. | Draft a proof-first, GM-015-only plan that preserves the existing block policy unless focused tests expose an implementation-owned explicitness gap. |
| 2026-05-11 02:46:10 CEST | Planner completed; Reviewer started | Draft `Final Plan` sections for GM-015 scope, closure, source of truth, tests, simulator proof, known-failure interpretation, done criteria, and scope guard. | Draft selects the evidence-backed block policy, treats missing explicit voluntary-leave reason as implementation-owned if RED tests expose it, and keeps GM-016+ plus source-ledger edits out of scope. | Review for missing files/tests/gates, stale assumptions, overbroad scope, and simulator-only proof handling. |
| 2026-05-11 02:46:28 CEST | Reviewer completed; Arbiter started | Full draft plan; source row contract; direct remove/leave/role/listener evidence; criteria/runner/harness requirements; exact simulator and gate contract. | Reviewer found the plan sufficient with one minor wording cleanup: the integration test should call public `broadcastVoluntaryLeaveAndRotateKey`, not an underscored helper name. No structural blocker found. | Apply wording cleanup, then run arbiter stop rule against closure bar, proof order, and scope guard. |
| 2026-05-11 02:47:15 CEST | Arbiter completed | Reviewer-adjusted plan sections, test/gate contract, simulator-only closure bar, known-failure interpretation, scope guard, and accepted differences. | No structural blocker remains. Incremental wording cleanup is already applied; no second planning loop is required. | Execute GM-015 only; do not edit source matrix/breakdown closure ledger, GM-001..GM-014 artifacts, GM-016+ artifacts, or final program verdict. |

## Final Verdict

Planning verdict: `execution-ready`.

GM-015 should execute as a proof-first implementation session using the repo's current intended `block_last_admin/no_op` policy. The direct block behavior mostly exists; the open implementation-owned gap is row-owned proof plus any narrow explicit-result cleanup needed if `broadcastVoluntaryLeaveAndRotateKey` or a caller can otherwise look like ambiguous success.

## Closure Audit

Closure verdict: `closed` / accepted for GM-015. Accepted execution proves the repo's explicit `block_last_admin/no_op` policy for sole creator/admin self-removal and leave.

What is now closed:

- Source matrix row GM-015 is `Covered`.
- Product behavior is closed for GM-015: `remove_group_member_use_case.dart` and `leave_group_use_case.dart` reject the only admin before mutation, and `broadcast_voluntary_leave_use_case.dart` returns `VoluntaryLeaveBroadcastSkipReason.lastAdmin`.
- Row-owned proof files include `remove_group_member_use_case_test.dart`, `leave_group_use_case_test.dart`, `member_removal_integration_test.dart`, `group_membership_smoke_test.dart`, `group_multi_party_device_criteria_test.dart`, `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart`.

Accepted simulator proof:

- Exact simulator-only command passed with `--scenario gm015` on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm015_gOh1Lx/gmp_1778461641801_gm015_orchestrator_verdict.json` records `scenario: gm015`, `ok: true`, and `gm015 verdicts valid for alice, bob, charlie`.
- Role/criteria proof shows Alice remains creator/admin, final members stay Alice/Bob/Charlie, key epoch stays unchanged, each role has an active admin, Bob and Charlie each send after the blocked attempts, and no writerless zombie group exists.

Maintenance gates passed:

- Focused GM-015 remove, leave, member-removal integration, membership smoke, and criteria tests.
- Adjacent remove/leave/dissolve/role/listener/smoke tests, targeted analyzer, exact three-iOS-simulator `gm015`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check` (`731/731`), and diff checks.

Residual-only items:

- None for the GM-015 product/test contract. The targeted analyzer had only pre-existing info-level `send_group_message_use_case.dart` suggestions.

Still-open items: GM-016 and later rows remain open; no final program verdict is written from this GM-015 closure.

Accepted differences:

- The row accepts `block_last_admin/no_op` rather than transfer-admin or dissolve behavior because current repo policy and tests prove last-admin blocks.
- Direct `--scenario gm015` simulator proof is sufficient; `--scenario all` expansion is not part of GM-015 closure.
- Checkpoint policy was skipped because dirty overlapping aggregate rollout artifacts, overlapping product/test edits, and simulator/Xcode `info.plist` `LastAccessedDate` metadata make a clean scoped checkpoint unsafe.

Reopen GM-015 only on a real regression against last-admin self-removal/leave blocking, explicit block/skip reasons, unchanged group/member/key state, Bob/Charlie post-attempt delivery, or the active-admin invariant.

## Final Plan

### real scope

Own exactly GM-015: "Admin removes self/creator policy is explicit."

The current repo policy is `block_last_admin/no_op`. Preserve that policy unless proof-first tests disprove the evidence below. The session should make the policy explicit and deterministic for both self-removal and creator/admin leave:

- Alice is creator and the only admin of a private group with Bob and Charlie as remaining writer members.
- Alice attempts to remove herself through the remove-member path.
- Alice attempts to leave through the voluntary-leave/local-leave path.
- The operation is blocked with a clear result, reason, or event.
- Alice remains creator/admin, Bob and Charlie remain members, keys/config are not corrupted, and Bob/Charlie can still send to the group.

Allowed implementation, only if the first regressions expose a gap:

- Add or tighten an explicit block reason/result for last-admin/creator self-removal or voluntary leave.
- Add focused caller handling only where an existing caller otherwise turns the block into ambiguous success.
- Add `gm015` criteria, runner, harness, and row-owned host/unit tests.

Do not do:

- Do not implement transfer-admin or dissolve policy unless existing code/tests already prove that is the intended policy. Current evidence points to block-last-admin.
- Do not change GM-001 through GM-014 behavior or reopen their artifacts.
- Do not edit the source matrix, source breakdown closure ledger, or any final program verdict.
- Do not implement GM-016 or later rows.
- Do not depend on real external devices.
- Do not broaden into group role redesign, creator transfer, group ownership schema, or Go pubsub/relay work unless GM-015 proof shows Go owns writerless delivery semantics.

### closure bar

GM-015 is closed only when all of these are true:

- The product policy is explicit and deterministic. For the current repo this means `block_last_admin/no_op`: removing or leaving as the sole creator/admin is rejected before membership, config, topic, key, or local group deletion changes.
- The rejection has a clear reason/result/event. Existing direct messages are `lastAdminRemovalBlockedMessage` and `lastAdminLeaveBlockedMessage`; if a helper returns a silent `skipped`, add a narrow reason/result or prove the caller surfaces the explicit `leaveGroup` rejection.
- Alice remains present as creator/admin, the group remains active and not dissolved, and the final member set is exactly Alice, Bob, and Charlie.
- There is no writerless zombie group: every role verdict has at least one admin, the admin is an active member, the stored group exists, `isDissolved` is false, and `createdBy` still points to Alice for the block policy.
- Post-attempt sends match the chosen policy. For block/no-op, Bob and Charlie each send after the blocked attempts and Alice/Bob/Charlie receive the expected messages without stale membership, missing delivery, or silent group disappearance.
- Criteria reject writerless zombie state, ambiguous success, missing clear reason/event, stale admin role, missing remaining-member delivery, silent group disappearance, unexpected dissolution, and mutation after a blocked operation.
- Exact three-iOS-simulator proof passes with `--scenario gm015` on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; the orchestrator verdict records `scenario: gm015`, `ok: true`.
- Focused tests, criteria tests, adjacent remove/leave/dissolve regressions, targeted analyzer, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and diff whitespace checks pass.

If Xcode, simulator, or Flutter build state fails, GM-015 is not closed. The executor must fix simulator/build state and rerun the exact proof. Required remediation can include `flutter clean`/build cleanup, DerivedData cleanup, uninstalling the app and extensions from the exact simulator UDIDs, rebooting those simulator IDs, re-running device discovery, and then rerunning `--scenario gm015`.

### source of truth

- Current code and tests beat stale prose.
- Source row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-015.
- Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` GM-015 rows and session ledger.
- Current rollout truth after closure audit: GM-001 through GM-015 are covered/accepted; GM-016 and later remain open.
- `scripts/run_test_gates.sh` is the execution source for named gates; `Test-Flight-Improv/test-gate-definitions.md` explains the gate scope and defers to the script on disagreement.
- Current app policy evidence:
  - `remove_group_member_use_case.dart` defines `lastAdminRemovalBlockedMessage` and blocks removing a member with `MemberRole.admin` when `adminCount <= 1` before local removal or `group:updateConfig`.
  - `leave_group_use_case.dart` defines `lastAdminLeaveBlockedMessage` and blocks local leave for `GroupRole.admin` when the member list has exactly one admin before `group:leave`, key cleanup, member cleanup, or group deletion.
  - `broadcast_voluntary_leave_use_case.dart` skips voluntary leave broadcast/key rotation for a last admin before the later `leaveGroup` rejection; this is a likely explicitness seam to test.
  - `update_group_member_role_use_case.dart` blocks demoting the last admin and allows self-demotion only when another admin remains, which confirms the repo invariant is admin-count based rather than creator-transfer based.
  - `group_message_listener.dart` receive-side authorization states that stored creator identity alone is not sufficient once the creator is demoted or removed; current authority is active admin/permissions, not permanent creator status.
  - `group_config_payload.dart` keeps `createdBy` static in config and member roles in the `members` list; it has no transfer-owner field.
  - `send_group_message_use_case.dart` allows normal chat members to send when the group exists, is not dissolved, and the sender remains a member.
  - `dissolve_group_use_case.dart` is an explicit alternate policy path but current self-leave/remove evidence does not select dissolve for GM-015.

### session classification

`implementation-ready`

Rationale: the intended policy is known from current code and tests, but GM-015 lacks row-owned acceptance around creator/admin self-removal plus creator leave, criteria negatives, exact `gm015` runner/harness support, and simulator-only proof. If focused RED tests show the policy is not explicit enough at a helper/caller boundary, that is a GM-015 implementation-owned gap.

### exact problem statement

The row risk is a private group that loses its only admin/creator or appears to succeed at self-removal/leave without a clear policy outcome. That can leave Bob and Charlie in a writerless zombie group: local group rows may exist, writer sends may appear accepted or rejected inconsistently, configs may still name a removed creator, and nobody has valid admin authority to repair membership.

User-visible behavior must be deterministic. With the current block policy, Alice must be told clearly that she cannot remove herself or leave while she is the only admin. Nothing should mutate, and Bob/Charlie should still be able to send normal chat messages afterward.

What must stay unchanged:

- Multi-admin removal/leave remains allowed where existing tests already cover it.
- Demoted creator receive-side mutation rejection remains intact.
- Dissolution remains an explicit admin action, not an accidental fallback from self-removal/leave.
- GM-001 through GM-014 accepted behavior stays closed.

### files and repos to inspect next

Production owner files:

- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/leave_group_use_case.dart`
- `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart`
- `lib/features/groups/application/dissolve_group_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/application/group_role_update_authorization.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart` only if an explicit block reason/result is lost at the UI callsite.

Tests/proof infrastructure:

- `test/features/groups/application/remove_group_member_use_case_test.dart`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/dissolve_group_use_case_test.dart`
- `test/features/groups/application/update_group_member_role_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart` only if UI caller behavior changes.
- `test/shared/fakes/group_test_user.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

Inspect only if row evidence proves app-layer checks are insufficient:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

### existing tests covering this area

Existing direct coverage:

- `remove_group_member_use_case_test.dart` already blocks removing the last admin before local or bridge changes and allows removing an admin when another admin remains.
- `leave_group_use_case_test.dart` already blocks a sole admin from leaving, preserves group/member state, and avoids `group:leave`.
- `update_group_member_role_use_case_test.dart` blocks demoting the last admin and allows self-demotion only when another admin remains.
- `group_info_wired_test.dart` already verifies the sole-admin leave UI stays on screen and shows `lastAdminLeaveBlockedMessage`.
- `group_message_listener_test.dart` verifies a stored creator who is no longer admin cannot dissolve the group and demoted creator receive-side mutations are rejected before side effects.
- `group_membership_smoke_test.dart` already covers sole admin leave blocked while writers remain, plus multi-admin leave/removal staying synchronized.
- `member_removal_integration_test.dart` covers voluntary leave/key rotation for non-last-admin/writer leave and remaining-member send on the rotated epoch.
- `dissolve_group_use_case_test.dart` covers explicit dissolution as a separate admin operation.

Missing for GM-015:

- No row-owned test covers Alice as creator/admin attempting both self-removal and leave in one policy proof.
- No host/integration proof requires Bob and Charlie to send after the blocked attempts.
- No proof asserts the final state has no writerless zombie group across all roles.
- No criteria test rejects ambiguous success, missing clear reason/event, stale admin role, missing remaining-member delivery, or silent group disappearance.
- No runner/harness support exists for `gm015`; current criteria/runner/harness enumerate only GM-001 through GM-014.

### regression/tests to add first

Add these regressions before product edits:

1. `remove_group_member_use_case_test.dart`
   - Add `GM-015 blocks creator/admin self-removal before mutation`.
   - Arrange Alice as `createdBy`, local `GroupRole.admin`, and sole `MemberRole.admin`; Bob/Charlie as writers; seed a latest key.
   - Call `removeGroupMember(memberPeerId: alicePeerId, selfPeerId: alicePeerId)`.
   - Assert `StateError` contains `lastAdminRemovalBlockedMessage`, no `group:updateConfig`, no member removal, `createdBy` unchanged, one admin remains, key unchanged, and no timeline/config mutation.

2. `leave_group_use_case_test.dart`
   - Add `GM-015 blocks creator/admin leave before cleanup`.
   - Arrange the same Alice/Bob/Charlie group.
   - Call `leaveGroup`.
   - Assert `StateError` contains `lastAdminLeaveBlockedMessage`, no `group:leave`, group/members/keys unchanged, `isDissolved` false, and Alice still admin.

3. `member_removal_integration_test.dart`
   - Add `GM-015 blocked creator leave keeps remaining-member sends healthy`.
   - Exercise `broadcastVoluntaryLeaveAndRotateKey`/`leaveGroup` together if possible. If `VoluntaryLeaveBroadcastResult.skipped` is ambiguous, add the narrow explicit reason/result first and assert it.
   - After the blocked attempt, send from Bob and Charlie through `sendGroupMessage`; assert expected recipients include Alice and the other writer, messages persist as sent, and keys/config are unchanged.

4. `group_membership_smoke_test.dart`
   - Add row-owned fake-network host proof named with `GM-015`.
   - Alice creates group, adds Bob/Charlie, attempts self-removal and leave, then Bob and Charlie send.
   - Assert Alice/Bob/Charlie all keep the same group, final member sets include all three, Alice is the only admin/creator, Bob/Charlie sends deliver to the other roles, and no removal/dissolve/leave event is observed.

5. `group_multi_party_device_criteria_test.dart`
   - Add positive `gm015` fixture and negative fixtures that reject writerless zombie group, ambiguous success, missing clear reason/event, stale admin role, missing Bob/Charlie post-attempt delivery, silent group disappearance, unexpected dissolve, and mutation after block.

Stop rule after tests:

- If the first direct tests pass and prove explicit block semantics, production changes should be limited to criteria/runner/harness proof support.
- If the voluntary-leave helper or a UI caller returns ambiguous success, patch only that seam with an explicit reason/result or surfaced error, then rerun the focused RED/GREEN tests.
- If tests show transfer or dissolve is already the real current policy, stop and revise this plan before implementation; do not mix policies.

### step-by-step implementation plan

1. Confirm the worktree is dirty and avoid reverting unrelated changes. Scope writes to GM-015 owner files/tests and this plan's future execution progress only.
2. Add the direct RED tests in `remove_group_member_use_case_test.dart` and `leave_group_use_case_test.dart`.
3. Run the two focused RED tests by plain name. If they already pass, record that no production change is needed for those direct seams.
4. Add the integration/host GM-015 tests in `member_removal_integration_test.dart` and `group_membership_smoke_test.dart`.
5. If a test exposes a gap:
   - Prefer preserving `block_last_admin/no_op`.
   - Patch `broadcast_voluntary_leave_use_case.dart` to return an explicit reason/result for last-admin skip if needed.
   - Patch `group_info_wired.dart` only if the existing UI loses the clear reason.
   - Patch `remove_group_member_use_case.dart` or `leave_group_use_case.dart` only if direct blocks do not fire before mutation.
6. Add `gm015` to `integration_test/scripts/group_multi_party_device_criteria.dart`:
   - scenario requirement for Alice/Bob/Charlie,
   - expected messages for Bob and Charlie post-attempt sends,
   - proof-field validator for `gm015AdminSelfRemovalPolicyProof`,
   - failure strings for writerless zombie, ambiguous success, missing clear reason/event, stale admin role, missing delivery, silent disappearance, unexpected dissolve, and mutation after block.
7. Add positive and negative criteria tests in `test/integration/group_multi_party_device_criteria_test.dart`.
8. Add `gm015` to `integration_test/scripts/run_group_multi_party_device_real.dart` scenario parsing/listing and keep `all` unchanged unless existing runner conventions require expanding it later.
9. Add `gm015` to `integration_test/group_multi_party_device_real_harness.dart`:
   - roles: Alice/Bob/Charlie,
   - Alice creates the group and adds Bob/Charlie,
   - Alice attempts self-removal and leave and records block reasons/events,
   - Bob and Charlie send post-attempt proof messages,
   - each role records final group/member/admin/creator state, key epoch, send/receive proof, and the GM-015 proof object.
10. Format changed Dart files.
11. Run focused tests and targeted analyzer.
12. Run exact simulator-only `--scenario gm015`.
13. Run named gates, completeness check, and diff whitespace checks.
14. Stop. Do not close the source matrix/breakdown ledger and do not write a final program verdict.

### risks and edge cases

- Silent helper skip: `broadcastVoluntaryLeaveAndRotateKey` currently returns `skipped` for more than one condition. The plan must reject ambiguous success for GM-015 if this result reaches acceptance evidence without an explicit reason.
- Split caller semantics: UI leave calls voluntary-broadcast first and then `leaveGroup`; direct tests must ensure the final user-visible result is still explicit.
- Partial mutation before rejection: tests must assert no member deletion, no `group:updateConfig`, no `group:leave`, no key cleanup, no `member_removed` publish, and no dissolve state.
- Creator vs admin drift: current code treats active admin role as authority; tests must prove stored `createdBy` alone does not create or remove authority.
- Remaining-member sends: Bob/Charlie post-attempt sends must prove normal chat send still works and that no group disappeared locally on any role.
- Offline/replay drift: simulator proof must measure actual role state after drains, not hard-code success fields.
- Simulator build state: Xcode/DerivedData/stale app install failures are infrastructure blockers to fix and rerun, not acceptable GM-015 closure evidence.

### exact tests and gates to run

Focused direct tests:

```bash
flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart --plain-name 'GM-015'
flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart --plain-name 'GM-015'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-015'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-015'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-015
```

Adjacent regression tests:

```bash
flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart
flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart
flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'stored creator who is no longer admin cannot dissolve the group'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'RP005 demoted creator receive-side mutations are rejected before side effects'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'sole admin cannot leave while only writer members remain'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'multi-admin leave keeps remaining admin healthy and synchronized'
```

Targeted analyzer:

```bash
dart analyze \
  lib/features/groups/application/remove_group_member_use_case.dart \
  lib/features/groups/application/leave_group_use_case.dart \
  lib/features/groups/application/broadcast_voluntary_leave_use_case.dart \
  lib/features/groups/application/dissolve_group_use_case.dart \
  lib/features/groups/application/group_message_listener.dart \
  lib/features/groups/application/group_config_payload.dart \
  lib/features/groups/application/send_group_message_use_case.dart \
  integration_test/scripts/group_multi_party_device_criteria.dart \
  integration_test/scripts/run_group_multi_party_device_real.dart \
  integration_test/group_multi_party_device_real_harness.dart \
  test/features/groups/application/remove_group_member_use_case_test.dart \
  test/features/groups/application/leave_group_use_case_test.dart \
  test/features/groups/application/member_removal_integration_test.dart \
  test/features/groups/integration/group_membership_smoke_test.dart \
  test/integration/group_multi_party_device_criteria_test.dart
```

Simulator proof:

```bash
flutter devices --machine
xcrun simctl list devices available
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm015 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Named gates and hygiene:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-015-plan.md
git diff --check
```

### known-failure interpretation

- Existing dirty worktree state and already-open GM-016+ rows are not failures by themselves.
- Pre-existing analyzer warnings outside GM-015 touched files are residual only if targeted analyzer on touched files passes and the failure list is unchanged.
- Existing source matrix and source breakdown dirty state must not be normalized or closed by GM-015 implementation.
- Simulator/Xcode/build failures are not product acceptance. Fix the simulator/build state and rerun exact `--scenario gm015`.
- A failed `groups` or `completeness-check` gate after GM-015 edits is blocking unless the failure is proven unrelated and pre-existing with exact command evidence.
- Criteria failure is never accepted as residual for GM-015 because criteria are the row-owned acceptance oracle.

### done criteria

- Plan-executed code chooses and documents one policy: current `block_last_admin/no_op`, unless evidence forces a pre-implementation plan revision.
- Alice self-removal and Alice creator/admin leave are blocked with clear reasons before mutation.
- Alice/Bob/Charlie final state has one active admin, Alice still present as creator/admin, Bob/Charlie still present as writers, no dissolution, no local group deletion, no key/config corruption.
- Bob and Charlie post-attempt sends deliver exactly as expected for the no-op block policy.
- `gm015` criteria reject all listed bad states and accept the positive fixture.
- Exact three-iOS-simulator `--scenario gm015` passes and writes aggregate verdict `scenario: gm015`, `ok: true`.
- Focused tests, adjacent regressions, targeted analyzer, `groups`, `completeness-check`, and diff checks pass.
- No source matrix, source breakdown closure ledger, GM-001..GM-014 artifact, GM-016+ artifact, or final program verdict is edited.

### scope guard

Non-goals:

- No role/permission schema redesign.
- No creator transfer implementation unless current code/tests already prove transfer is the intended policy and this plan is revised first.
- No automatic dissolve fallback from self-removal or leave.
- No broad group-message delivery rewrite.
- No Go relay/pubsub changes unless GM-015 evidence shows app-layer policy is correct but Go still creates writerless delivery semantics.
- No UI redesign; only pass through an explicit existing reason if needed.
- No source matrix/breakdown closure edits.
- No `--scenario all` expansion unless existing runner mechanics force it; direct `--scenario gm015` is the row closure proof.

Overengineering signs:

- Adding owner/creator migration fields for a block policy.
- Introducing admin election or transfer algorithms.
- Rewriting all membership events when the gap is a missing explicit reason.
- Adding broad runner scenarios beyond GM-015.

### accepted differences / intentionally out of scope

- Current repo treats active admin role as authority and keeps `createdBy` as static creator metadata. GM-015 accepts that for the block policy.
- Transfer-admin and explicit dissolve are acceptable matrix policies in general, but they are intentionally out of scope unless evidence disproves the existing block-last-admin invariant.
- Multi-admin creator leave/removal is covered by adjacent tests and remains allowed where another admin exists; GM-015 is the sole-admin/creator policy row.
- Physical devices are intentionally out of scope; proof is simulator-only.
- GM-016 removed-member unsubscribe behavior remains open and must not be pulled into GM-015.

### dependency impact

- GM-016 and later membership/remove rows depend on GM-015 not leaving writerless or ambiguous groups.
- Later closure should reopen GM-015 only on a real regression against last-admin self-removal/leave blocking, clear reason/event, no mutation, valid admin state, or Bob/Charlie post-attempt delivery.
- If implementation evidence changes the policy from block to transfer or dissolve, stop and revise this plan before coding because criteria, simulator proof, and done criteria all depend on the chosen policy.

## Reviewer Notes

Reviewer verdict: sufficient with adjustment.

- Missing files/tests/gates: none structural. `leave_group_use_case.dart` is correctly included even though it was not in the likely-owner list, because GM-015 explicitly covers Alice leaving.
- Stale assumptions: none found. Current code proves block-last-admin/no-op and active-admin authority; the plan requires revision if focused tests disprove that.
- Overengineering: no blocker. Transfer, dissolve, schema ownership, and Go relay/pubsub are guarded out unless evidence forces them.
- Decomposition: sufficient. Direct use-case tests come before production edits, then host proof, criteria, runner/harness, simulator proof, and named gates.
- Minimum adjustment applied: corrected the integration-test instruction to use public `broadcastVoluntaryLeaveAndRotateKey`.

## Arbiter Decision

Arbiter verdict: `execution-ready`.

Structural blockers: none.

Incremental details intentionally deferred:

- Exact names/field shapes for `gm015AdminSelfRemovalPolicyProof` can be finalized during implementation as long as criteria enforce the closure bar.
- `--scenario all` expansion remains deferred; direct `--scenario gm015` is sufficient for this row.

Accepted differences intentionally left unchanged:

- The repo's current policy is block-last-admin rather than transfer-admin or dissolve.
- `createdBy` remains static creator metadata, while active admin/member roles remain the authority source.
- GM-016 unsubscribe cleanup remains a separate open row.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/leave_group_use_case.dart`
- `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart`
- `lib/features/groups/application/dissolve_group_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `test/features/groups/application/remove_group_member_use_case_test.dart`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/dissolve_group_use_case_test.dart`
- `test/features/groups/application/update_group_member_role_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

Why the plan is safe to implement now:

- It uses current code/tests to select a single policy instead of inventing a transfer/dissolve design.
- It puts direct RED/GREEN tests before production edits and narrows implementation to explicitness gaps.
- It requires simulator-only proof and rejects simulator/build failure as closure evidence.
- It preserves GM-001 through GM-014, keeps GM-016+ out of scope, and forbids source matrix/breakdown closure edits or a final program verdict.
