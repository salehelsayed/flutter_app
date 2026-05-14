# GM-014 Plan: Simultaneous Re-add and Sender Send

Status: accepted by execution QA; closed by closure audit

Source matrix: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Session: `GM-014`

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-11 01:21:16 CEST | Evidence Collector started | Skill instructions; `git status --short`; source matrix GM-014 row; source breakdown GM-014 row; adjacent GM-013 accepted plan for rollout style and boundary. | Confirmed GM-014 is the only row in scope. GM-001 through GM-013 remain covered/accepted; GM-014 and later remain open. Plan file did not exist and is now the only writable artifact. | Inspect current membership-start, re-add, delayed key/config, inbox repair, criteria, runner, harness, and gate evidence before drafting. |
| 2026-05-11 01:24:55 CEST | Evidence Collector completed; Planner started | `add_group_member_use_case.dart`; `remove_group_member_use_case.dart`; `group_message_listener.dart`; `group_key_update_listener.dart`; `group_config_payload.dart`; `send_group_message_use_case.dart`; `handle_incoming_group_message_use_case.dart`; `drain_group_offline_inbox_use_case.dart`; `group_pending_key_repair_service.dart`; `group_offline_replay_envelope.dart`; `rotate_and_distribute_group_key_use_case.dart`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/group_inbox.go`; `go-relay-server/inbox.go`; GM-006/GM-007/GM-012/GM-013 host and criteria/harness evidence; `scripts/run_test_gates.sh`; `Test-Flight-Improv/test-gate-definitions.md`. | No planning blocker. Current code defines re-add membership start through `member_added` event time and has durable missing-key repair primitives, but GM-014 lacks row-owned delayed key/config proof, criteria negatives, and exact `--scenario gm014` simulator support. | Draft a proof-first plan that first proves the contract, then adds the narrow owner implementation only if delayed key/config repair silently loses Charlie's from-membership-start message. |
| 2026-05-11 01:25:30 CEST | Planner completed; Reviewer started | Draft plan sections, row contract, simulator-only proof requirement, owner file list, direct tests, named gates, and scope guard. | Draft keeps GM-014 isolated, treats delayed key/config silent loss as implementation-owned, and excludes GM-015+ plus source matrix/breakdown closure edits. | Review for missing owner files, stale assumptions, weak acceptance criteria, simulator/build blocker handling, and overbroad Go scope. |
| 2026-05-11 01:29:15 CEST | Reviewer completed; Arbiter started | Full draft plan; delayed config/key ordering risk; key-update retry proof coverage; criteria and simulator closure bar. | Reviewer found the plan sufficient after tightening two items: GM-014 needs row-owned key-update retry proof, and replay/config ordering must be treated as implementation-owned if replay drains before config and would otherwise be dropped. | Apply arbiter stop rule against scope, closure bar, proof order, simulator-only proof, and source-doc write restrictions. |
| 2026-05-11 01:29:15 CEST | Arbiter completed | Reviewer-adjusted plan sections, final tests/gates, known-failure interpretation, scope guard, and accepted differences. | No structural blocker remains. The plan is execution-ready, row-scoped, proof-first, simulator-only, and safe to hand to an implementation executor. | Execute GM-014 only; do not edit source matrix/breakdown closure ledger or final program verdict. |

## Execution Progress

| Timestamp | Phase | Files inspected/touched | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-11 01:31:58 CEST | Contract extracted | `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-014-plan.md`; implementation-execution-qa-orchestrator skill | GM-014 only. Required proof-first regressions, `gm014` runner/harness/criteria support, exact direct tests, targeted analyzer, exact simulator-only proof, `groups`, `completeness-check`, and diff checks. Matrix/breakdown closure/final verdict docs remain out of execution write scope. | Spawn isolated Executor with `model: gpt-5.5`, `reasoning_effort: xhigh`. |
| 2026-05-11 01:34:12 CEST | Executor spawn corrected | No repo files touched beyond this progress section | First `codex exec` attempt failed before child materialized because this CLI does not accept `-a` on `exec`. No Executor work started. | Relaunch Executor with config-based approval policy and same model/reasoning contract. |
| 2026-05-11 01:33:40 CEST | Executor local start | Plan file; implementation-execution-qa-orchestrator skill; `git status --short` | Running as the isolated GM-014 Executor. Worktree is already dirty in prior GM files plus source matrix/breakdown docs; source matrix/breakdown/final verdict remain out of write scope. | Inspect directly referenced owner files/tests and add proof-first GM-014 regressions before product edits. |
| 2026-05-11 01:35:33 CEST | Executor inspection | `group_message_listener.dart`; `drain_group_offline_inbox_use_case.dart`; `group_pending_key_repair_service.dart`; `group_key_update_listener.dart`; `send_group_message_use_case.dart`; related GM-006..GM-013 tests/harness/criteria | `gm014` is not implemented yet. Existing code already has event-time membership snapshots, future-epoch durable replay placeholders, live diagnostic supersession, and key-arrival retry hooks; proof-first tests will determine whether product fixes are needed. | Add focused GM-014 regressions and `gm014` runner/harness/criteria support. |
| 2026-05-11 01:47:55 CEST | Executor edits formatted | `handle_incoming_group_message_use_case.dart`; GM-014 focused tests; `group_multi_party_device_criteria.dart`; `run_group_multi_party_device_real.dart`; `group_multi_party_device_real_harness.dart` | Added proof-first GM-014 regressions, `gm014` criteria/runner/harness support, and one narrow product guard rejecting a re-added sender's removed-window messages after a persisted removal cutoff. | Run focused GM-014 tests and triage failures before any further fixes. |
| 2026-05-11 01:51:02 CEST | Executor focused tests batch 1 | `group_message_listener_test.dart`; `drain_group_offline_inbox_use_case_test.dart`; `group_key_update_listener_test.dart` | `flutter test --no-pub ... --plain-name 'GM-014'` passed for all three application-focused tests. Two first attempts exposed fixture future-timestamp clamping in the new tests, classified as GM-014 test-fixture issues, then passed after using recent-past timestamps. | Run remaining focused GM-014 host smoke and criteria tests. |
| 2026-05-11 01:51:33 CEST | Executor focused tests batch 2 | `group_membership_smoke_test.dart`; `group_multi_party_device_criteria_test.dart` | GM-014 host smoke passed. GM-014 criteria positive and negative tests passed, including silent loss, stale state, leak, duplicate delivery, duplicate member/device, duplicate topic, and duplicate recipient rejection. | Run required adjacent tests before analyzer and simulator proof. |
| 2026-05-11 01:52:50 CEST | Executor adjacent tests | `group_key_update_listener_test.dart`; `drain_group_offline_inbox_use_case_test.dart`; `group_membership_smoke_test.dart`; `member_removal_integration_test.dart`; `group_new_member_onboarding_test.dart` | Required adjacent tests passed: `PREREQ-FUTURE-EPOCH-KEY-REPAIR`, `GEK002`, `GEK003`, GM-006, GM-007, GM-010, GM-012, full member removal integration, and full new-member onboarding. No GM-014-caused adjacent failures found. | Run targeted analyzer, then simulator preflight and exact `--scenario gm014`. |
| 2026-05-11 01:54:08 CEST | Executor analyzer | Targeted owner files/tests/criteria/runner/harness/fakes | First targeted analyzer run failed on one GM-014 test warning (`removedAt` unused), classified as GM-014 cleanup. Removed the unused local, formatted the test, reran the analyzer successfully with only existing info-level lint suggestions, and reran GM-014 drain proof successfully. | Run simulator preflight and exact three-simulator `--scenario gm014`. |
| 2026-05-11 01:59:04 CEST | Executor simulator proof | `flutter devices --machine`; `xcrun simctl list devices available`; `run_group_multi_party_device_real.dart --scenario gm014` | Exact three iOS simulators were available/booted. Required GM-014 simulator proof passed on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Orchestrator verdict: `scenario: gm014`, `ok: true`, detail `gm014 verdicts valid for alice, bob, charlie`, path `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm014_ZPD23U/gmp_1778457290273_gm014_orchestrator_verdict.json`. | Run named `groups` and `completeness-check` gates, then diff checks. |
| 2026-05-11 02:00:00 CEST | Executor final gates | `scripts/run_test_gates.sh`; full worktree diff | `./scripts/run_test_gates.sh groups` passed. `./scripts/run_test_gates.sh completeness-check` passed with `731/731 test files classified`. `git diff --check -- GM-014 plan` and full `git diff --check` passed. | Stop after Executor pass and hand off to QA Reviewer. |
| 2026-05-11 02:01:07 CEST | Executor final hygiene | `info.plist`; `git status --short`; full `git diff --check` | Xcode updated tracked root `info.plist` `LastAccessedDate` during simulator proof. Restored only that generated timestamp churn; `info.plist` is clean again and full `git diff --check` still passes. | Stop after Executor pass and hand off to QA Reviewer. |
| 2026-05-11 02:07:27 CEST | QA Reviewer completed | GM-014 plan progress; executor handoff; GM-014 product/test/runner/harness/criteria diff; simulator verdict JSONs | QA blocked closure: criteria do not enforce one shared re-add timestamp across roles, and harness hard-codes removed-window plaintext plus duplicate topic/recipient proof fields. Source matrix/breakdown/final verdict docs remain out of execution write scope. | Spawn fresh Executor fix pass for only the two QA findings, then rerun required focused proof and QA. |
| 2026-05-11 02:08:36 CEST | Executor fix-pass 1 start | GM-014 plan; criteria; criteria tests; real harness; `git status --short` | Fix scope is limited to QA findings: shared cross-role re-add timestamp validation/proof and measured GM-014 removed-window/duplicate state. Source matrix, source breakdown ledger, and final program verdict remain out of write scope. | Patch criteria/test/harness and only the narrow timestamp propagation needed for the harness proof. |
| 2026-05-11 02:14:38 CEST | Executor fix-pass 1 edits | `group_multi_party_device_criteria.dart`; `group_multi_party_device_criteria_test.dart`; `group_multi_party_device_real_harness.dart`; `group_message_listener.dart`; `group_message_listener_test.dart` | Criteria now rejects cross-role GM-014 re-add timestamp drift. Harness publishes `member_added.eventAt`, measures Charlie removed-window plaintext from actual DB state, measures re-add join requests from flow events, and measures duplicate durable recipients from Alice's recorded recipient list. Listener uses `member_added`/`members_added` `eventAt` when present so live and replay paths share the same membership start. | Run focused GM-014 criteria, listener, and membership tests. |
| 2026-05-11 02:16:03 CEST | Executor fix-pass 1 focused tests | Criteria, listener, membership smoke, targeted analyzer | Passed: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-014`; `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-014'`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-014 simultaneous re-add and sender send'`; `dart analyze` on touched criteria/harness/listener/test files. | Run exact GM-014 three-simulator proof. |
| 2026-05-11 02:21:35 CEST | Executor fix-pass 1 simulator proof | Exact three-simulator `run_group_multi_party_device_real.dart --scenario gm014`; orchestrator and role verdict JSONs; `info.plist` | Required GM-014 simulator proof passed on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Orchestrator verdict is `scenario: gm014`, `ok: true`, detail `gm014 verdicts valid for alice, bob, charlie`, path `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm014_RnOLc5/gmp_1778458583240_gm014_orchestrator_verdict.json`. Alice/Bob/Charlie all recorded `readdAt` and `charlieJoinedAt` as `2026-05-11T00:20:18.655798Z`; Charlie measured `removedWindowPlaintextCount: 0`, `topicJoinRequestCount: 1`, `duplicateTopicJoins: false`, `duplicateDurableRecipients: false`. Xcode touched only generated `info.plist` `LastAccessedDate`; restored that generated churn. | Run named `groups` and `completeness-check` gates, then required diff checks. |
| 2026-05-11 02:22:52 CEST | Executor fix-pass 1 final handoff | `scripts/run_test_gates.sh`; GM-014 plan diff; full worktree diff; `git status --short` | Passed: `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh completeness-check` with `731/731 test files classified`; `git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-014-plan.md`; full `git diff --check`. Source matrix, source breakdown closure ledger, and final program verdict were not edited by this fix pass; pre-existing dirty source docs remain out of this Executor scope. | Hand off to QA with no remaining GM-014 fix-pass blocker. |
| 2026-05-11 02:29:07 CEST | QA Reviewer fix-pass 1 accepted | GM-014 plan progress; GM-014 code/test/runner/harness/criteria diff; latest simulator verdict JSONs; focused GM-014 criteria/listener/smoke reruns; targeted analyzer; diff checks | QA accepted GM-014 with no blocking findings. Original QA blockers are resolved: shared `readdAt`/`charlieJoinedAt` is enforced and present in the latest artifact, and removed-window plaintext, topic-join, and durable-recipient duplicate proof fields are measured rather than hard-coded. Source matrix, source breakdown closure ledger, and final program verdict were not edited for GM-014 execution; inherited dirty source docs still leave GM-014 open. | Final response with accepted verdict and exact evidence. |

## Final Verdict

GM-014 execution verdict: `accepted`.

The implementation now proves the simultaneous Alice re-add/send delayed-key contract. Live and replay paths share Charlie's re-add membership start from `member_added`/`members_added` `eventAt`; removed-window messages are rejected after the persisted removal cutoff; delayed key/config catch-up does not silently lose Alice's from-membership-start message; and duplicate topic joins or durable recipients are rejected by measured criteria.

The exact three-iOS-simulator `--scenario gm014` proof passed for Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; aggregate verdict path: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm014_RnOLc5/gmp_1778458583240_gm014_orchestrator_verdict.json`.

## Closure Audit

Closure verdict: `closed` / accepted for GM-014. The accepted execution and fresh QA pass prove the simultaneous re-add/send delayed-key behavior after one QA-blocked fix pass.

What is now closed:

- Source matrix row GM-014 is `Covered`.
- Product behavior is closed for GM-014: `handle_incoming_group_message_use_case.dart` rejects removed-window messages after a persisted removal cutoff, and `group_message_listener.dart` uses `member_added`/`members_added` `eventAt` when present so live and replay paths preserve one shared re-add membership-start timestamp.
- Row-owned proof files from execution include `group_message_listener_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, `group_key_update_listener_test.dart`, `group_membership_smoke_test.dart`, `group_multi_party_device_criteria_test.dart`, `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart`.

Accepted simulator proof:

- Exact simulator-only command passed with `--scenario gm014` on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm014_RnOLc5/gmp_1778458583240_gm014_orchestrator_verdict.json` records `scenario: gm014`, `ok: true`, and `gm014 verdicts valid for alice, bob, charlie`.
- Role/criteria proof shows Alice/Bob/Charlie share the same `readdAt` and `charlieJoinedAt`, Charlie has zero removed-window plaintext, one measured re-add topic join request, no duplicate topic joins, no duplicate durable recipients, delayed key/config catch-up without silent loss, and A/B/C convergence.

Maintenance gates passed:

- Focused GM-014 listener, offline-inbox, key-update, host membership smoke, and criteria tests.
- Adjacent `PREREQ-FUTURE-EPOCH-KEY-REPAIR`, `GEK002`, `GEK003`, GM-006, GM-007, GM-010, GM-012, full `member_removal_integration_test.dart`, and full `group_new_member_onboarding_test.dart`.
- Targeted analyzer on GM-014 touched files, exact three-iOS-simulator `gm014`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check` (`731/731`), execution diff hygiene, and closure doc whitespace hygiene.

Residual-only items:

- None for the GM-014 product/test contract.

Still-open items: GM-015 and later rows remain open; no final program verdict is written from this GM-014 closure.

Accepted differences:

- The row accepts event-time `joinedAt` from `member_added`/`members_added` as the deterministic membership-start contract rather than adding serialized config `joinedAt`.
- Direct `--scenario gm014` simulator proof is sufficient; `--scenario all` expansion is not required for GM-014 closure.
- Checkpoint policy was skipped because the worktree contains dirty overlapping aggregate rollout artifacts and unrelated/overlapping product/test edits, making a clean scoped checkpoint unsafe.

Reopen GM-014 only on a real regression against shared re-add membership start, delayed key/config repair/catch-up, removed-window exclusion, duplicate topic-join or durable-recipient prevention, or Alice/Bob/Charlie delivery and convergence.

## Final Plan

### real scope

Own exactly GM-014: "Simultaneous re-add and sender send."

Allowed work:

1. Establish a deterministic re-add membership-start contract for Charlie from current repo behavior. The expected contract is that Charlie's membership start is the trusted `member_added` event timestamp applied by `group_message_listener.dart`, because `GroupMember.fromConfigMap(...)` persists `joinedAt: eventAt` for new members and `buildGroupConfigPayload(...)` does not carry a separate joined-at field.
2. Add row-owned regression proof for Alice re-adding Charlie, Alice sending after that membership start under the current/new epoch, Charlie processing key/config later, and Charlie either receiving/decrypting the from-membership-start message exactly once or recording a key-missing repair signal that successfully repairs/catches up.
3. Add `gm014` criteria, runner, and harness support for exact three-iOS-simulator proof.
4. Patch only narrow owner files if proof-first tests show silent loss, stale membership/key state, duplicate Charlie state, missing Alice/Bob delivery, or missing explicit repair.

Do not do:

- Do not reopen GM-001 through GM-013.
- Do not implement GM-015 or later rows.
- Do not edit the source matrix, source breakdown closure ledger, or any final program verdict.
- Do not broadly rewrite group membership, key rotation, relay inbox, or Go pubsub. Touch Go only if row evidence proves Go owns the missing diagnostic or replay/recipient behavior.
- Do not depend on real external devices. Closure proof is simulator-only.

### closure bar

GM-014 can close only when all of these are true:

- Re-add event establishes a deterministic membership start for Charlie. The proof must record the re-add event timestamp and Charlie's persisted `joinedAt`, and they must match at all relevant roles after convergence.
- Alice sends after Charlie's membership start under the current/new epoch while Charlie has not yet processed key/config.
- Charlie later processes key/config and either:
  - receives and decrypts every from-membership-start message exactly once, or
  - records an explicit key-missing repair signal, retains a durable replay placeholder, and then successfully repairs/catches up after key arrival without silent loss.
- Alice and Bob remain converged on the current epoch/config, include Charlie exactly once, continue exact-once delivery, and do not roll back to a stale epoch.
- Charlie has no removed-window plaintext before re-add, no stale epoch after catch-up, exactly one member row/device binding, and no duplicate topic joins or duplicate durable recipients.
- Criteria reject silent loss, missing repair signal, stale key/config, duplicate delivery, missing Alice/Bob delivery, Charlie plaintext leak before re-add, and duplicate Charlie state.
- Exact simulator-only proof passes with `--scenario gm014` on the established Alice/Bob/Charlie simulator IDs, and the aggregate verdict records `scenario: gm014`, `ok: true`.
- Supporting host/listener/criteria tests, targeted analyzer, groups gate, completeness check, and diff whitespace checks pass.

If Xcode, simulator, or Flutter build state fails, GM-014 is not closed. The executor must fix simulator/build state, for example by cleaning DerivedData/build output, uninstalling the app and extensions from the exact three simulators, rebooting those simulator IDs, rerunning device discovery, and rerunning `--scenario gm014`.

### source of truth

- Current code and tests win over stale docs.
- The source row is GM-014 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
- The source breakdown row GM-014 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` is now `covered/accepted` after closure audit.
- Current rollout truth after closure: GM-001 through GM-014 are covered/accepted; GM-015 and later rows remain open.
- `scripts/run_test_gates.sh` is the execution source for named gates. `Test-Flight-Improv/test-gate-definitions.md` is explanatory and defers to the script on disagreement.
- Current repo evidence for the contract:
  - `group_message_listener.dart` handles `member_added` and `members_added`, passes `eventAt` into `GroupMember.fromConfigMap(...)`, applies authoritative config snapshots, syncs Go config, writes timeline messages, and records membership watermarks.
  - `GroupMember.fromConfigMap(...)` preserves existing `joinedAt` or uses supplied `joinedAt`; group config JSON does not include `joinedAt`, so event time is the only deterministic re-add start in current code.
  - `send_group_message_use_case.dart` uses current local members as `recipientPeerIds` for durable group inbox storage and signs replay envelopes with the current key epoch.
  - `drain_group_offline_inbox_use_case.dart` queues missing future-epoch replay as pending key repair and can process replay through `GroupMessageListener.handleReplayEnvelope`.
  - `group_key_update_listener.dart` saves the accepted key, calls `group:updateKey`, and triggers `RetryPendingGroupKeyRepairs` for that epoch after key save.
  - `group_pending_key_repair_service.dart` supersedes a live diagnostic placeholder when a durable replay for the same sender/epoch arrives, and `GroupPendingKeyRepairRunner` replaces the durable placeholder after key arrival.
  - `go-mknoon/node/pubsub.go` emits `group:decryption_failed` on missing or wrong local key; this is useful for explicit live repair signals but not sufficient by itself because live diagnostics lack replay material.
  - `go-relay-server/inbox.go` authorizes group inbox retrieval by `from` or `recipientPeerIds`, so Charlie must be in Alice's sender-side recipient list for catch-up.

### session classification

`implementation-ready`

Rationale: GM-014 lacks direct row proof, criteria negatives, runner/harness support, and exact simulator proof. Existing primitives probably cover the intended repair path, but the row must still add proof and may need narrow owner changes if delayed key/config causes silent loss.

### exact problem statement

The row risk is a race between re-add visibility and key availability. Alice can re-add Charlie and immediately send under the current/new epoch while Charlie has not yet processed the key/config. If Charlie's from-membership-start message only arrives live before key/config, the app can surface a diagnostic without durable replay. If the durable replay is missing, unauthorized, sent to stale recipients, or not retried after key arrival, Charlie silently loses a message he became eligible to receive.

User-visible behavior must become deterministic: Charlie receives/decrypts every message sent after his re-add membership start, or the app records a visible/keyed repair signal and completes catch-up after the current key arrives. Alice and Bob must keep current-epoch delivery and Charlie must not regain access to removed-window plaintext.

What must stay unchanged:

- Prior GM-001 through GM-013 acceptance remains closed.
- Removed-window exclusion from GM-006/GM-007 remains intact.
- Stale add/remove ordering from GM-011/GM-012 remains intact.
- GM-015 admin self-removal policy is not decided here.

### files and repos to inspect next

Production/app owner files:

- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_pending_key_repair_service.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`

Tests and proof infrastructure:

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/shared/fakes/group_test_user.dart`

Inspect or edit only if row evidence proves ownership:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `go-relay-server/inbox.go`

### existing tests covering this area

Already covered or adjacent:

- `group_membership_smoke_test.dart` GM-006 and GM-007 prove re-add current epoch and removed-window exclusion when Charlie already has key/config before the post-readd send.
- `group_membership_smoke_test.dart` GM-010 and GM-012 prove duplicate re-add and stale remove after re-add do not duplicate/strand Charlie, and keep one active device binding.
- `drain_group_offline_inbox_use_case_test.dart::PREREQ-FUTURE-EPOCH-KEY-REPAIR future epoch replay queues and repairs after key arrival` proves durable replay missing-key placeholder and repair after key save.
- `drain_group_offline_inbox_use_case_test.dart::GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival` proves live diagnostic plus durable replay collapses to one repaired visible message.
- `drain_group_offline_inbox_use_case_test.dart::GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival` proves a non-removed stale-key recipient can repair a future-epoch durable replay after delayed key arrival.
- `group_message_listener_test.dart::PREREQ-FUTURE-EPOCH-KEY-REPAIR live decryption failure creates repair placeholder and trigger without normal delivery` proves live diagnostic placeholder creation.
- `group_key_update_listener_test.dart::PREREQ-FUTURE-EPOCH-KEY-REPAIR key arrival retries pending future epoch replay after save` proves accepted key update triggers pending repair retry.

Missing for GM-014:

- No row-owned test proves re-add membership start plus delayed key/config after removal.
- No test proves Alice's post-readd durable recipient list includes Charlie when Alice sends immediately after local re-add.
- No test proves Charlie rejects removed-window plaintext but repairs/receives the post-readd message after delayed key/config.
- No criteria, runner, or harness support for `gm014`.

### regression/tests to add first

Add these before product edits:

1. `group_message_listener_test.dart`
   - Add focused GM-014 listener proof for `member_added` event time.
   - Deliver `member_added` with deterministic `timestamp`/`eventAt`.
   - Assert Charlie's persisted `joinedAt` equals the event time, config sync includes Charlie once, and an older removed-window message remains rejected or absent.

2. `drain_group_offline_inbox_use_case_test.dart`
   - Add focused GM-014 delayed key/config repair proof using Alice/Bob/Charlie contexts.
   - Arrange Charlie removed, Alice re-adds Charlie at `readdAt`, Alice sends at `readdAt + 1s` under epoch 2, and Charlie has membership/config but not epoch 2 key when replay first drains.
   - Assert Charlie queues `groupKeyRepairReasonOfflineMissingKey`, saves exactly one pending placeholder for Alice's post-readd message, has no removed-window plaintext, then `GroupKeyUpdateListener` saves epoch 2 and `GroupPendingKeyRepairRunner` repairs the message exactly once through `GroupMessageListener.handleReplayEnvelope`.

3. `group_key_update_listener_test.dart`
   - Add a GM-014-focused key-arrival proof, separate from the existing prerequisite test.
   - Start with a pending GM-014 durable replay/key repair for Charlie's post-readd epoch.
   - Deliver Charlie's delayed key update and assert the accepted key save triggers exactly one retry, clears or supersedes the pending placeholder, and does not regress Alice/Bob current epoch/config.

4. `group_membership_smoke_test.dart`
   - Add row-owned GM-014 host proof that uses the app/fake stack, not only low-level repair helpers.
   - Record `readdAt`, Alice's post-readd send timestamp/key epoch, Charlie's delayed key/config processing, Alice/Bob convergence, Charlie no removed-window plaintext, and no duplicate member/device/recipient state.

5. `test/integration/group_multi_party_device_criteria_test.dart`
   - Add positive GM-014 fixture and negative fixtures rejecting:
     - silent loss of Alice's post-readd message,
     - missing repair signal when delayed key path is used,
     - stale Charlie key/config after catch-up,
     - duplicate delivery,
     - missing Alice/Bob delivery,
     - Charlie removed-window plaintext leak,
     - duplicate Charlie member/device/topic/recipient state.

Stop rule after tests:

- If all focused tests pass with only criteria/runner/harness additions, keep production changes limited to proof support.
- If any test shows silent loss or missing explicit repair, patch the narrow owner path that failed. Do not defer as a prerequisite.

### step-by-step implementation plan

1. Confirm current dirty worktree before editing and avoid reverting unrelated user/agent changes.
2. Add a GM-014-focused membership-start regression in `group_message_listener_test.dart`.
   - If the test proves `eventAt` is not persisted as Charlie's re-add `joinedAt`, patch `group_message_listener.dart` or `group_config_payload.dart` narrowly so re-add event time is deterministic.
3. Add the GM-014 delayed-key durable repair regression in `drain_group_offline_inbox_use_case_test.dart`.
   - Use current `queueMissingGroupReplayKeyRepairFromEnvelope`, `GroupPendingKeyRepairRunner`, and `GroupKeyUpdateListener`.
   - Patch only the failing owner if Charlie's placeholder, repair request, retry, or exact-once repaired message is missing.
   - Make the config/key ordering explicit. Preferred proof path is: Charlie applies the re-add config/member event, durable replay first sees missing epoch key, then delayed key arrival retries and repairs. If replay can drain before config and fail as `unknown_sender` or equivalent, patch the owner path so that state is retryable after config/key arrival instead of silently final.
4. Add a GM-014-focused key-arrival retry proof in `group_key_update_listener_test.dart` if the durable repair path depends on delayed key update retry.
   - Patch `group_key_update_listener.dart` only if accepted key save does not trigger the GM-014 pending repair exactly once.
5. Add/adjust host proof in `group_membership_smoke_test.dart`.
   - Extend `GroupTestUser` only if needed to publish `member_added` with explicit `eventAt`, inspect inbox recipients, or simulate delayed key/config without real devices.
   - Keep helper changes test-only and deterministic.
6. Add `gm014` support to `group_multi_party_device_criteria.dart`.
   - Add `_gm014Requirement` with roles `alice`, `bob`, `charlie`.
   - Include `gm014` in scenario validation messages.
   - Add `_validateGm014SimultaneousReaddSendProof(...)`.
   - Define expected messages so Alice/Bob/Charlie delivery is explicit and Charlie has only post-readd allowed traffic.
7. Add GM-014 criteria tests in `group_multi_party_device_criteria_test.dart`.
8. Add `--scenario gm014` to `run_group_multi_party_device_real.dart`.
   - Do not add `gm014` to `all`; direct `--scenario gm014` is the row closure proof.
9. Add `gm014` to `integration_test/group_multi_party_device_real_harness.dart`.
   - Alice creates A/B/C, removes Charlie, rotates to current epoch, re-adds Charlie at deterministic `readdAt`, captures/delays Charlie key/config processing, sends Alice post-readd message under epoch 2, lets Charlie later process key/config and drain/retry.
   - Verdict fields must include `gm014SimultaneousReaddSendProof` for membership start, delayed key/config, repair signal or direct decrypt, exact-once repaired/delivered message, Alice/Bob convergence, no removed-window plaintext, no stale epoch, one Charlie row/device binding, and no duplicate joins/recipients.
10. Only if host or simulator evidence proves Go ownership, inspect and narrowly patch:
   - `go-mknoon/node/pubsub.go` if missing/wrong-key live diagnostics are absent or malformed.
   - `go-mknoon/node/group_inbox.go` or `go-relay-server/inbox.go` if durable replay retrieval is impossible despite Charlie being listed as a recipient.
11. Run the exact tests and gates below. If simulator/build state fails, perform cleanup and rerun until `gm014` has a valid pass or a real product/test failure remains.

### risks and edge cases

- Live decryption diagnostics alone do not carry replay material. The plan must prove durable replay exists or the app has another explicit repair path that succeeds.
- Charlie may receive config before key, key before config, or both after Alice's send. The row's required proof is config/key slightly later; tests should make the order explicit and record it.
- If replay arrives before Charlie's config/member state, the executor must prove that path either waits/retries after config or is outside the chosen GM-014 contract. It must not become a permanent undecryptable record that hides silent loss.
- Sender-side recipient selection may miss Charlie if Alice sends before local re-add is committed. That is silent loss and must be fixed in GM-014.
- Replay signature verification requires Alice's member/device binding in Charlie's local config before replay decrypt. If config arrives after durable replay, the proof must drain again or defer until config exists instead of marking undecryptable.
- Duplicate live diagnostic plus durable replay must collapse to one visible message, not one placeholder plus one delivered duplicate.
- Previous removal cutoff must still prevent removed-window plaintext from becoming visible after re-add.
- `GroupKeyUpdateListener` saves keys only after bridge `group:updateKey` succeeds. Failed bridge update is not closure; fix simulator/build state or product code and rerun.
- Simulator proof can be invalidated by stale app containers, Xcode DerivedData, app extension residue, or a half-booted simulator. Treat those as environment cleanup work, not GM-014 acceptance.

### exact tests and gates to run

Focused direct tests:

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-014'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GM-014'`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'GM-014'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-014 simultaneous re-add and sender send'`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-014`

Adjacent regression tests:

- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK002'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK003'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-006'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-007'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-010'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-012'`
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`

Targeted static validation:

- `dart analyze lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/remove_group_member_use_case.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_key_update_listener.dart lib/features/groups/application/group_config_payload.dart lib/features/groups/application/send_group_message_use_case.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart lib/features/groups/application/group_pending_key_repair_service.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/shared/fakes/group_test_user.dart`

Named gates and hygiene:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-014-plan.md`
- `git diff --check`

Simulator-only proof:

1. Preflight:
   - `flutter devices --machine`
   - `xcrun simctl list devices available`
2. Required exact proof:
   - `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm014 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
3. Verdict requirements:
   - aggregate verdict JSON records `scenario: gm014`, `ok: true`;
   - detail includes `gm014 verdicts valid for alice, bob, charlie`;
   - role verdicts carry the GM-014 proof fields listed in the closure bar.

If any Go owner file is touched, add the relevant module-local test:

- `(cd go-mknoon && go test ./node -run 'GroupTopicValidator|UpdateGroupKey|DecryptionFailed|GroupInbox')`
- `(cd go-relay-server && go test ./... -run 'GroupInbox|InboxDedup')`

### known-failure interpretation

- Existing dirty files in the worktree are not automatically GM-014 regressions. Read diffs before editing touched files and preserve unrelated user/agent changes.
- Source matrix and breakdown files are already dirty in this worktree; do not edit them for GM-014 planning or execution unless the user explicitly asks.
- Analyzer findings outside the GM-014 touched set, such as previously noted `group_info_wired.dart` warning noise from GM-013, are residual unless the GM-014 executor changes that file or depends on the failing callsite.
- Simulator/Xcode/build-state failures are never closure evidence. Clean/build/reboot/uninstall as needed and rerun exact GM-014 proof.
- Relay availability or simulator transient failures must be separated from product failures by rerun after cleanup. A product failure is one that reproduces after clean simulator/build state.

### done criteria

GM-014 is done only when:

- The GM-014 plan artifact remains scoped to this row and no final program verdict is written.
- Focused tests prove the membership-start and delayed key/config contract.
- Criteria tests reject every negative listed in the closure bar.
- `run_group_multi_party_device_real.dart` accepts `--scenario gm014`.
- Exact three-iOS-simulator `--scenario gm014` passes on the established Alice/Bob/Charlie simulator IDs with `scenario: gm014`, `ok: true`.
- Charlie's final proof shows either direct exact-once receipt or explicit missing-key repair plus successful catch-up; no silent loss.
- Alice/Bob remain converged, current epoch/config, exact-once delivery.
- Charlie has no removed-window plaintext, no stale epoch, one member row/device binding, and no duplicate topic joins/recipients.
- Focused direct tests, targeted analyzer, `groups`, `completeness-check`, and diff whitespace checks pass.

### scope guard

Non-goals:

- No GM-015 admin/creator policy.
- No GM-016 subscription cleanup unless GM-014 proof directly exposes duplicate topic joins as part of this row.
- No new product-level invite architecture.
- No general history repair redesign.
- No broad Go libp2p/pubsub rewrite.
- No real external-device proof.
- No `--scenario all` expansion requirement.

Overengineering signals:

- Adding a new cross-row membership timeline system instead of using the existing event watermark and `joinedAt` contract.
- Replacing relay group inbox semantics when `recipientPeerIds` already prove targeted durable replay.
- Changing key rotation policy for all rows when GM-014 only needs delayed key/config repair after re-add.
- Treating a transient simulator/build failure as accepted closure.

### accepted differences / intentionally out of scope

- Live pubsub missing-key diagnostics are accepted as a signal only when paired with durable replay or another successful repair/catch-up path. A live placeholder that later becomes undecryptable without replay is not GM-014 closure.
- Direct `--scenario gm014` is sufficient; `--scenario all` does not need to include GM-014.
- Current group config payloads do not serialize `joinedAt`. GM-014 accepts event-time `joinedAt` as the deterministic membership-start contract unless proof shows it cannot be applied reliably.
- Go pubsub and relay inbox are out of scope unless exact row proof shows missing diagnostics, missing recipient authorization, or unrecoverable replay storage despite correct Dart-side state.

### dependency impact

- GM-015 and later rows should proceed only after GM-014 establishes the re-add/send delayed-key contract or explicitly documents a failing implementation gap.
- Later duplicate/subscription/key rows depend on GM-014 preserving one Charlie member row, one active device binding, no duplicate topic joins, and no stale epoch after catch-up.
- If GM-014 changes the membership-start contract away from event time, GM-006/GM-007/GM-010/GM-012 adjacent proofs should be rerun and later row plans must cite the updated contract.

## Reviewer Findings

Reviewer status: passed after tightening.

Findings:

- The plan has enough repo evidence to be execution-safe for GM-014 only. It identifies the current membership-start contract as re-add `member_added` event time, not serialized config state, and requires direct proof before relying on it.
- The original draft relied too much on adjacent key-update prerequisite coverage. The final plan now requires a GM-014-focused `group_key_update_listener_test.dart` proof when delayed key retry is part of the closure path.
- The config-before-key path was explicit, but replay-before-config needed a sharper stop rule. The final plan now treats permanent `unknown_sender`/config-missing replay loss as a GM-014 implementation-owned gap unless the executor proves that ordering is outside the chosen row contract.
- Go scope is sufficiently bounded. `go-mknoon/node/pubsub.go`, `go-mknoon/node/group_inbox.go`, and `go-relay-server/inbox.go` are inspect-or-edit only if row evidence proves ownership.
- Simulator/build-state handling is sufficient: Xcode, DerivedData, app/extension residue, stale simulator state, and transient relay/device failures cannot be accepted as GM-014 closure.

## Arbiter Decision

Arbiter status: `execution-ready`.

Decision: proceed with this plan for GM-014 only.

The closure bar is concrete, simulator-only, and falsifiable. The plan keeps GM-001 through GM-013 closed, avoids GM-015+ work, forbids source matrix/breakdown closure edits, and gives the executor permission to implement the narrow owner fix if proof-first tests expose silent loss or missing repair after re-add.

## Structural Blockers Remaining

None.

## Incremental Details Intentionally Deferred

- Exact helper names and fixture shapes are deferred to the executor after reading current test helper APIs.
- Exact simulator cleanup commands are deferred to the executor's environment state, but cleanup and rerun are mandatory if Xcode/simulator/build state fails.
- Go module tests are deferred unless a Go owner file is touched.

## Accepted Differences Intentionally Left Unchanged

- Event-time `joinedAt` remains the planned deterministic membership-start contract unless focused proof shows the repo cannot apply it reliably.
- Direct `--scenario gm014` is the required simulator proof; `--scenario all` expansion is not part of this row.
- Live missing-key diagnostics are accepted only with durable replay or successful repair/catch-up. A live placeholder without replay material is not closure.
- GM-014 closure audit updates the source matrix and source breakdown GM-014 closure rows; no final program verdict is written.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-013-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_pending_key_repair_service.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `go-relay-server/inbox.go`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/shared/fakes/group_test_user.dart`

## Why The Plan Is Safe Or Unsafe To Implement Now

Safe to implement now because it is row-scoped, proof-first, simulator-only, and has a concrete closure bar. The plan does not require source matrix/breakdown closure edits and treats missing delayed-key or delayed-config behavior as GM-014 implementation-owned instead of deferring behind a vague prerequisite.
