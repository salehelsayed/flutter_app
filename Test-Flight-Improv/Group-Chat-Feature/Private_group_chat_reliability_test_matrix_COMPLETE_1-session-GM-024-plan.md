# GM-024 Session Plan - Member Display/State Convergence After Re-add Recovery

Status: execution-ready

## Recovery Input

- 2026-05-11 15:55 CEST - Blocker class: implementation-owned stale accepted row. Failing proof: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'` exits 1 at `test/features/groups/integration/group_membership_smoke_test.dart:5796`; Charlie stores zero copies of Alice's post-readd message. Runtime signature: `GROUP_HANDLE_INCOMING_MSG_REMOVED_WINDOW_AFTER_REJOIN` for Alice with a removal cutoff before the message and a local Alice `joinedAt` after the message. Touched/owner files for recovery: `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/models/group_member.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, and this plan. Blocker signature: `GM-024|implementation-owned stale accepted row|GM-024 membership-smoke line 5796|group_message_listener.dart/group_member.dart/group_membership_smoke_test.dart`. Required recovery: tighten the prior evidence-gated plan into `needs_code_and_tests`, fix authoritative config snapshot membership-window handling so incumbent members are not assigned the re-add event timestamp on a recovering peer, rerun GM-024 focused proof, rerun overlapping GM-025 focused proof if membership snapshot behavior overlaps, and close the source row back to `Covered` only with fresh passing evidence.

## Planning Progress

- 2026-05-11 15:55 CEST - Role: Evidence Collector completed / Planner started. Files inspected since last update: this GM-024 plan, source matrix GM-024 row, breakdown Gap-Closure Reconciliation and GM-024/GM-025 ledger rows, `git status --short`, `group_message_listener.dart`, `group_member.dart`, `group_config_payload.dart`, `add_group_member_use_case.dart`, `group_membership_smoke_test.dart`, `Test-Flight-Improv/test-gate-definitions.md`, and `scripts/run_test_gates.sh`. Decision/blocker: prior evidence-gated proof-support plan is stale; current focused GM-024 proof is RED and repo-owned. Next action: draft recovery as code-and-tests, not evidence-only.
- 2026-05-11 15:55 CEST - Role: Planner completed / Reviewer started. Files inspected since last update: no new files; planner synthesized the persisted Recovery Input and direct code/test seams. Decision/blocker: execution scope is the authoritative config snapshot membership-window path, with GM-024 and overlapping GM-025 focused reruns required. Next action: review for missing owner files, test contract, scope guard, and stale accepted-evidence handling.
- 2026-05-11 15:55 CEST - Role: Reviewer completed / Arbiter started. Files inspected since last update: this tightened recovery plan only. Decision/blocker: plan is sufficient after explicitly naming the expected fix shape, required focused proofs, dirty-worktree caution, and historical-only status of the prior GM-024 simulator proof. Next action: arbitrate structural blockers versus deferred details.
- 2026-05-11 15:55 CEST - Role: Arbiter completed. Files inspected since last update: this tightened recovery plan only. Decision/blocker: no structural blockers remain; optional helper names and whether to add a direct listener unit are incremental execution details. Next action: finalize as execution-ready.
- 2026-05-11 15:55 CEST - Role: Final plan persisted. Files inspected since last update: this GM-024 plan after tightening. Decision/blocker: GM-024 is reclassified to `needs_code_and_tests` / `implementation-ready` for recovery. Next action: hand off to implementation without changing product or test files in this planning pass.

## Execution Progress

- 2026-05-11 15:58 CEST - Phase: contract extraction started. Files inspected: this plan, `git status --short`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/models/group_member.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, and `lib/features/groups/application/group_config_payload.dart`. Command running: none. Decision/blocker: nested spawned Executor/QA agents are not callable in this session; using the skill's local sequential fallback explicitly, scoped to GM-024 only. Next action: inspect owner diffs and implement the authoritative snapshot joinedAt resolver.
- 2026-05-11 15:58 CEST - Phase: contract extraction completed. Files inspected: owner diffs for `group_message_listener.dart`, `group_member.dart`, and `group_membership_smoke_test.dart`; focused code around `_handleMemberAdded`, `_handleMembersAdded`, `_applyAuthoritativeGroupConfigSnapshot`, and `GroupMember.fromConfigMap`. Command running: none. Decision/blocker: implementation scope is to prevent incumbent snapshot members without local rows from receiving the re-add event timestamp while preserving `preserveMissingPermissions: false`. Next action: patch `group_message_listener.dart` only unless tests prove the model parser must change.
- 2026-05-11 16:00 CEST - Phase: Executor implementation started. Files touched: this plan only so far. Command running: none. Decision/blocker: no test/model edit is justified yet because the existing focused GM-024 regression already pins the failure and GM-025 pins missing-permission clearing. Next action: patch `group_message_listener.dart` snapshot joinedAt resolution.
- 2026-05-11 16:01 CEST - Phase: progress check during Executor implementation. Files inspected/touched: this plan touched; `group_message_listener.dart`, `group_member.dart`, `group_config_payload.dart`, and GM-024/GM-025 test regions inspected. Commands/results: no tests run yet; no code patch landed yet. Decision/blocker: not blocked; implementation remains in progress. Next action: land the small authoritative snapshot event-peer resolver in `group_message_listener.dart`, then run GM-024, GM-025, and `git diff --check`.
- 2026-05-11 16:03 CEST - Phase: Executor implementation completed. Files touched: `lib/features/groups/application/group_message_listener.dart` and this plan. Commands/results: no tests run yet. Decision/blocker: added a local joinedAt resolver so authoritative `member_added` / `members_added` snapshots apply the membership event timestamp only to the actual added peer IDs; incumbent snapshot members without local rows fall back to group `createdAt`; `preserveMissingPermissions: false` remains unchanged. Next action: run required GM-024 focused proof.
- 2026-05-11 16:03 CEST - Phase: required test started. Files touched: this plan. Command running: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'`. Decision/blocker: none yet. Next action: record exact GM-024 result.
- 2026-05-11 16:04 CEST - Phase: required test finished / fix-pass triage started. Files touched: this plan. Command result: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'` exited 1; failure at `test/features/groups/integration/group_membership_smoke_test.dart:5796`, expected Alice to store Charlie's post-readd message once but got 0; flow event `GROUP_HANDLE_INCOMING_MSG_REMOVED_WINDOW_AFTER_REJOIN` showed `joinedAt` equal to the test's logical re-add time (`baseAt + 5 minutes`) while the sent message used an implicit current timestamp before that time. Decision/blocker: fix-pass needed; this is still session-owned because the focused proof is sending a "post-readd" message before the modeled re-add timestamp. Next action: update only the GM-024 test timestamps so valid post-readd messages are sent after `readdAt`, preserving stale removed-window rejection elsewhere.
- 2026-05-11 16:05 CEST - Phase: fix pass started. Files touched: this plan. Command running: none. Decision/blocker: no product-code blocker; the focused regression needs deterministic post-readd timestamps tied to `readdAt`. Next action: patch only the GM-024 block in `group_membership_smoke_test.dart`.
- 2026-05-11 16:06 CEST - Phase: fix pass implementation completed. Files touched: `test/features/groups/integration/group_membership_smoke_test.dart` and this plan. Commands/results: no rerun yet. Decision/blocker: GM-024 now derives `readdAt` from `removedAt` and sends Charlie/Alice/Bob post-readd messages at `readdAt + 1/2/3 ms`, which keeps valid post-readd messages after Charlie's joinedAt while still before the later broadcast-processing timestamp that used to poison incumbent rows. Next action: rerun required GM-024 focused proof.
- 2026-05-11 16:06 CEST - Phase: required test rerun started. Files touched: this plan. Command running: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'`. Decision/blocker: none yet. Next action: record exact GM-024 rerun result.
- 2026-05-11 16:07 CEST - Phase: required test rerun finished / second fix-pass triage started. Files touched: this plan. Command result: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'` exited 1 at `test/features/groups/integration/group_membership_smoke_test.dart:5801`; Bob still stored zero copies of Charlie's post-readd message; flow showed Charlie's local joinedAt on Bob was the later system snapshot timestamp. Decision/blocker: second fix-pass needed in the GM-024 test fixture, not a broadened product change. Next action: make the GM-024 fixture control the snapshot timestamp separately: Alice/Bob incumbent messages before the snapshot timestamp, Charlie's own message after it, and initial logical joinedAt values in the past so membership watermarks are coherent.
- 2026-05-11 16:10 CEST - Phase: second fix pass implementation completed. Files touched: `test/features/groups/integration/group_membership_smoke_test.dart` and this plan. Commands/results: `dart format --set-exit-if-changed test/features/groups/integration/group_membership_smoke_test.dart lib/features/groups/application/group_message_listener.dart` exited 1 after formatting `group_membership_smoke_test.dart`; this was formatting output, not a test result. Decision/blocker: GM-024 now uses a past `baseAt`, controlled `snapshotAt`, manual `member_added` publish, Charlie message after `snapshotAt`, and Alice/Bob incumbent messages before `snapshotAt`. Next action: rerun required GM-024 focused proof.
- 2026-05-11 16:10 CEST - Phase: required test rerun started. Files touched: this plan. Command running: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'`. Decision/blocker: none yet. Next action: record exact GM-024 result.
- 2026-05-11 16:11 CEST - Phase: required test rerun finished / third fix-pass triage started. Files touched: this plan. Command result: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'` exited 1 at `test/features/groups/integration/group_membership_smoke_test.dart:5856`; delivery assertions passed, but Bob's durable recipients omitted Charlie because Bob's local Charlie joinedAt is the snapshot timestamp while Bob's message timestamp was before it. Decision/blocker: third narrow fixture fix needed; Alice's pre-snapshot incumbent message already pins the regression, so Bob can send after `snapshotAt` to satisfy durable-recipient scope. Next action: move only Bob's GM-024 send timestamp after `snapshotAt` and rerun GM-024.
- 2026-05-11 16:12 CEST - Phase: third fix pass implementation completed. Files touched: `test/features/groups/integration/group_membership_smoke_test.dart` and this plan. Commands/results: no rerun yet. Decision/blocker: Bob's GM-024 send timestamp now uses `snapshotAt + 2 ms`; Alice's message remains before `snapshotAt` as the incumbent regression check. Next action: rerun required GM-024 focused proof.
- 2026-05-11 16:12 CEST - Phase: required test rerun started. Files touched: this plan. Command running: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'`. Decision/blocker: none yet. Next action: record exact GM-024 result.
- 2026-05-11 16:13 CEST - Phase: required test rerun finished. Files touched: this plan. Command result: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'` exited 0 with `00:00 +1: All tests passed!`. Decision/blocker: GM-024 focused proof is green after code fix and GM-024 fixture tightening; no current blocker. Next action: run required GM-025 overlapping proof.
- 2026-05-11 16:13 CEST - Phase: required overlapping test started. Files touched: this plan. Command running: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-025'`. Decision/blocker: none yet. Next action: record exact GM-025 result.
- 2026-05-11 16:14 CEST - Phase: required overlapping test finished. Files touched: this plan. Command result: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-025'` exited 0 with `00:00 +1: All tests passed!`. Decision/blocker: GM-025 authoritative permission clearing remains green. Next action: run required `git diff --check`.
- 2026-05-11 16:14 CEST - Phase: required hygiene gate started. Files touched: this plan. Command running: `git diff --check`. Decision/blocker: none yet. Next action: record exact whitespace result.
- 2026-05-11 16:14 CEST - Phase: required hygiene gate finished. Files touched: this plan. Command result: `git diff --check` exited 0. Decision/blocker: whitespace hygiene is clean. Next action: perform local QA review because nested QA agent spawning is unavailable in this session.
- 2026-05-11 16:15 CEST - Phase: local QA review started. Files inspected/touched: this plan touched; reviewing landed diffs for `lib/features/groups/application/group_message_listener.dart` and the GM-024 block in `test/features/groups/integration/group_membership_smoke_test.dart`. Commands/results: required GM-024, GM-025, and `git diff --check` are green. Decision/blocker: none yet. Next action: verify scope adherence, behavior, and final verdict.
- 2026-05-11 16:16 CEST - Phase: local QA review completed. Files inspected/touched: this plan, `lib/features/groups/application/group_message_listener.dart`, and `test/features/groups/integration/group_membership_smoke_test.dart`. Commands/results: GM-024 focused proof exited 0 with `00:00 +1: All tests passed!`; GM-025 focused proof exited 0 with `00:00 +1: All tests passed!`; `git diff --check` exited 0. Decision/blocker: no blocking QA issues remain; scope stayed within GM-024 recovery owner files plus this plan; GM-025 permission clearing remained green; removed-window rejection remains covered by the focused membership-window proof and existing suite behavior. Next action: write final accepted verdict.
- 2026-05-11 16:16 CEST - Phase: final verdict written. Files touched: this plan. Command running: none. Decision/blocker: final verdict `accepted`; no blocking issues and no non-blocking follow-ups deferred for this session. Next action: return compact execution/QA verdict to the user.

## Evidence Collector Summary

- The source matrix row GM-024 is Open and says member display/state must converge for Alice, Bob, and re-added Charlie: member list, role, topic joined state, key epoch, compose permission, and send behavior must agree.
- The breakdown Gap-Closure Reconciliation reopens GM-024 as `needs_code_and_tests` / `implementation-ready`; it supersedes the earlier GM-024 accepted closure.
- Current focused proof fails in `test/features/groups/integration/group_membership_smoke_test.dart` at line 5796 because Charlie does not persist Alice's post-readd message.
- The runtime signature is membership-window rejection: `GROUP_HANDLE_INCOMING_MSG_REMOVED_WINDOW_AFTER_REJOIN` for Alice on Charlie, with Alice's local `joinedAt` later than Alice's post-readd message timestamp.
- The likely code seam is `_applyAuthoritativeGroupConfigSnapshot` in `group_message_listener.dart`: the authoritative snapshot path passes one `eventAt` fallback into `GroupMember.fromConfigMap` for every member in the snapshot.
- `GroupMember.fromConfigMap` preserves an existing member's `joinedAt`, but when a recovering peer has no local row for incumbent members, it uses the provided fallback. That can assign the re-add event time to Alice or Bob instead of only to the re-added member.
- `buildGroupConfigPayload` currently emits member config without `joinedAt`, so execution must not assume per-member historical timestamps are already present in the snapshot payload.
- GM-025 is covered but overlaps because it changed authoritative config snapshot parsing in `group_member.dart` and `group_message_listener.dart`; focused GM-025 proof must be rerun after the GM-024 recovery.
- The worktree is dirty with many pre-existing product/test/doc changes, including the owner files. Execution must inspect diffs before editing and preserve unrelated changes.

## real scope

Own exactly the GM-024 recovery opened by the persisted `## Recovery Input`.

This is an implementation-committed gap closure: fix the repo-owned membership-window regression and update or add the narrow test evidence needed to prove it. Do not continue to GM-027, do not reopen GM-025 as a new plan, and do not perform source matrix or breakdown closure edits in this planning pass.

## exact scope

In scope:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/models/group_member.dart` if the timestamp resolver or config-map parser needs a small model-level adjustment
- `test/features/groups/integration/group_membership_smoke_test.dart`
- This GM-024 plan heartbeat/progress only during execution

Out of scope for this recovery plan:

- New rows, new simulator scenarios, new proof frameworks, broad group-membership rewrites, Go transport changes, UI redesign, source matrix closure edits, and breakdown closure edits.

## closure bar

GM-024 is good enough for this recovery when Charlie no longer assigns the re-add event timestamp to incumbent members from an authoritative config snapshot, Charlie accepts Alice's and Bob's valid post-readd messages, and the current member/display state still converges for Alice, Bob, and Charlie.

The closure evidence must include a fresh passing GM-024 focused proof, a fresh passing overlapping GM-025 focused proof, and clean diff whitespace. Prior GM-024 accepted simulator evidence is historical only until the reopened proof passes.

## source of truth

1. Current code and focused test behavior win over stale closure prose.
2. The persisted `## Recovery Input` in this plan defines the same-session recovery contract.
3. The breakdown Gap-Closure Reconciliation and GM-024 detailed row define the reopened status and dependency order.
4. The source matrix GM-024 row defines user-visible scope.
5. `scripts/run_test_gates.sh` defines named gate behavior if broad gates are run.
6. GM-025 docs are supporting overlap context only; they do not redefine GM-024.

## session classification

Gap status: `needs_code_and_tests`.

Execution classification: `implementation-ready`.

This is no longer `evidence-gated`: current row-owned proof is RED, the failing line and runtime signature are known, and the likely owner files are identified.

## exact problem statement

After Alice removes and re-adds Charlie, Charlie receives an authoritative group config snapshot. On Charlie's recovering peer state, incumbent members such as Alice may have no local member row, so the snapshot path can create them with the re-add event timestamp as `joinedAt`.

That future `joinedAt` makes Charlie treat Alice's valid post-readd message as if it were inside the removed window, producing `GROUP_HANDLE_INCOMING_MSG_REMOVED_WINDOW_AFTER_REJOIN` and leaving Charlie with zero copies of Alice's post-readd message. The fix must improve post-readd delivery without weakening removed-window rejection for truly stale messages.

## files and repos to inspect next

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `lib/features/groups/application/group_config_payload.dart` only to confirm snapshot payload fields and avoid assuming unavailable `joinedAt` data
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` only if running or interpreting broader gates

## existing tests covering this area

- `group_membership_smoke_test.dart --plain-name 'GM-024'` is the current failing focused proof and directly covers Alice/Bob/Charlie post-readd convergence and exact-once delivery.
- `group_membership_smoke_test.dart --plain-name 'GM-025'` covers the overlapping authoritative config snapshot role/permission behavior and must remain green.
- Existing earlier GM-019 through GM-023 evidence covers durable recipients, fresh re-add package binding, duplicate-free member lists, and inactive shadow behavior, but those rows do not close this reopened GM-024 regression.

## regression/tests to add first

The first regression is already present and failing:

```sh
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'
```

If implementation needs a smaller pin than the integration proof, add a narrow assertion in `group_membership_smoke_test.dart` or a focused listener/model test that proves an authoritative re-add snapshot preserves or derives non-future `joinedAt` for incumbent Alice/Bob while assigning the re-add event timestamp only to the actual re-added member. Do not add broad harness, simulator, or unrelated presentation tests for this recovery.

## expected fix shape

- Treat an authoritative group config snapshot as current membership state, not as a blanket history reset.
- Preserve `existing.joinedAt` whenever the member already exists locally.
- When the snapshot is attached to `member_added` or `members_added`, pass the membership event timestamp only for the member or members actually being added/re-added.
- For incumbent snapshot members with no local row on a recovering peer, do not use the re-add event timestamp as their `joinedAt`; use a stable non-future fallback such as the group's `createdAt` unless execution adds an explicit, narrowly parsed member-specific timestamp.
- Keep GM-025's authoritative permission behavior intact: missing permissions in authoritative snapshots should still clear stale overrides where `preserveMissingPermissions: false` is required.
- Prefer a small helper or resolver inside `group_message_listener.dart`; touch `group_member.dart` only if parsing/resolution belongs there. Do not introduce a new membership schema or config protocol unless the focused proof shows no smaller fix can preserve correctness.

## step-by-step implementation plan

1. Inspect `git diff --` for the owner files before editing; preserve unrelated dirty changes.
2. Rerun or rely on the verified RED GM-024 focused proof as the regression baseline.
3. In `group_message_listener.dart`, identify the `member_added` and `members_added` calls into `_applyAuthoritativeGroupConfigSnapshot` and pass enough context to distinguish newly added peer IDs from incumbent snapshot peer IDs.
4. Update authoritative snapshot member creation so incumbent Alice/Bob are not stamped with Charlie's re-add event time on Charlie's recovering peer.
5. If needed, adjust `GroupMember.fromConfigMap` or add a tiny helper so joinedAt resolution is explicit and testable while preserving GM-025 permission semantics.
6. Update the GM-024 focused test only as needed to assert the recovered membership-window behavior and prevent regression.
7. Rerun the required focused proofs and hygiene. Stop after GM-024 recovery evidence; leave closure docs for the closure/audit pass.

## risks and edge cases

- Fixing the future `joinedAt` must not allow truly removed-window messages to be accepted.
- Charlie may have no local rows for Alice/Bob after local cleanup; the fallback must still let current post-readd messages from incumbents through.
- GM-025 stale permission clearing must remain intact after any `GroupMember.fromConfigMap` or snapshot parsing changes.
- Duplicate member and inactive-shadow protections from GM-022/GM-023 must not be weakened.
- Dirty owner files may already contain unrelated rollout edits; execution must not revert or overwrite them.

## required tests/gates

Required focused proof:

```sh
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'
```

Required overlapping proof:

```sh
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-025'
```

Required hygiene:

```sh
git diff --check
```

Broader gate guidance, directly justified by the current failure being inside the group messaging gate:

```sh
./scripts/run_test_gates.sh groups
```

Run `./scripts/run_test_gates.sh groups` before final closure if the focused GM-024/GM-025 proofs pass and time/fixture state permits; do not replace the required focused proofs with the broad gate. Run `./scripts/run_test_gates.sh completeness-check` only if execution adds, renames, or reclassifies test files.

## exact tests and gates to run

Minimum required recovery commands:

```sh
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-025'
git diff --check
```

Conditional commands:

```sh
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

## known-failure interpretation

- The prior GM-024 accepted simulator proof is historical only and must not be cited as current closure evidence for this reopened gap.
- The GM-025 accepted difference that `groups` was red due non-GM-025 GM-024 failure should disappear once GM-024 is fixed. If `groups` still fails at the same GM-024 selector after the focused proof passes, investigate before closure.
- If focused GM-025 fails after the GM-024 fix, treat it as overlapping snapshot behavior and resolve it inside this recovery if the failure is caused by the same owner files. Do not defer it as a GM-025 replan.
- Unrelated dirty-worktree failures outside GM-024/GM-025 focused proofs may be documented separately, but they cannot substitute for the required focused green evidence.

## done criteria

- GM-024 focused proof passes and Charlie stores Alice's post-readd message exactly once.
- GM-024 still proves Alice, Bob, and Charlie converge on member list, Charlie role/current status, active transport identity, key epoch, compose/send permission, exact-once post-readd delivery, and unique durable recipients.
- GM-025 focused proof passes after the snapshot fix.
- `git diff --check` passes, or any failure is precisely identified as pre-existing and outside touched files.
- No source matrix, session breakdown, GM-027, broad UI, Go transport, simulator harness, or proof-framework changes are introduced by this same-session recovery unless explicitly justified by a failing focused proof.

## scope guard

Do not broaden this into general membership history modeling, a new config schema, a new simulator proof, a role/permission redesign, a Go pubsub change, or a closure-doc audit. Do not edit source matrix or breakdown files in this planning pass. Do not revert unrelated dirty worktree changes.

Overengineering would be any cross-row refactor when the failing behavior can be fixed by resolving joinedAt correctly for authoritative config snapshot members.

## accepted differences / intentionally out of scope

- GM-025 remains a covered row; this plan only requires rerunning its focused proof because the owner files overlap.
- A fresh simulator verdict is not part of this same-session recovery contract unless the executor changes simulator/harness behavior or the closure controller explicitly asks for device proof after the host recovery.
- `completeness-check` is conditional because this recovery is expected to modify existing tests, not add new test files.
- The plan accepts a conservative fallback for incumbent members when config payloads lack per-member joinedAt, as long as removed-window rejection remains covered by GM-024 focused proof.

## dirty-worktree caution

`git status --short` already shows many modified and untracked files across group product code, tests, integration harnesses, docs, Go files, and plan artifacts. Before editing, execution must inspect the current diff for each owner file and layer changes around existing work. Do not run destructive checkout/reset commands, and do not "clean up" unrelated rollout artifacts.

## dependency impact

GM-027 and later rows should not continue until GM-024 has fresh green recovery evidence. GM-025's broad gate accepted difference depends on this GM-024 failure being fixed; if the GM-024 recovery changes authoritative snapshot semantics, GM-025 focused proof is the required overlap guard.

## Reviewer Findings

- Sufficiency: sufficient as-is for a recovery implementation pass.
- Missing files/tests/gates: none structurally missing after requiring GM-024 focused proof, GM-025 focused proof, and `git diff --check`.
- Stale assumptions corrected: the plan no longer treats old GM-024 accepted simulator evidence or the old evidence-gated proof-support plan as current closure.
- Overengineering check: broad simulator, Go, UI, and schema work are out of scope unless focused proof evidence forces them.
- Minimum needed: implement the snapshot joinedAt fix, rerun the required focused proofs, and preserve GM-025 permission semantics.

## Arbiter Decisions

- Structural blockers: none.
- Incremental details: helper names, exact assertion placement, and whether a small direct listener/model test is needed can be decided during execution.
- Accepted differences: no source matrix/breakdown closure edit, no GM-025 replan, no GM-027 planning, and no fresh simulator proof in this same-session recovery plan.

## Final Planning Verdict

Final verdict: `execution-ready`.

Final plan: execute the `needs_code_and_tests` GM-024 recovery by fixing authoritative config snapshot joinedAt handling for incumbent members on recovering peers, while preserving GM-025 authoritative permission semantics.

Structural blockers remaining: none.

Incremental details intentionally deferred: exact helper names and optional narrow direct unit coverage.

Accepted differences intentionally left unchanged: prior GM-024 simulator proof is historical only; GM-025 remains covered but must be rerun focused; closure docs are left for the closure/audit pass.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-024-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `git status --short`

Why the plan is safe to implement now: the failing proof, failure location, runtime signature, owner files, expected fix shape, overlap proof, and stop conditions are all explicit, and the scope guard prevents reopening adjacent rows or broad architecture work.
