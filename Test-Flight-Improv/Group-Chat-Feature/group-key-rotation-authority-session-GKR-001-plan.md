Status: execution-ready

# GKR-001 - Owner-only rotation authority Plan

## Planning Progress

- 2026-05-23 20:10:15 CEST - Arbiter completed. Files inspected since last update: no new files. Decision/blocker: no structural blockers; plan is reusable and execution-safe for one narrow host-only session. Next action: execute the plan TDD-first in a separate implementation pass.
- 2026-05-23 20:10:15 CEST - Arbiter started. Files inspected since last update: no new files. Decision/blocker: reviewer found the plan sufficient with one documentation adjustment for an explicit Device/Relay Proof Profile section. Next action: classify review findings and finalize status.
- 2026-05-23 20:10:15 CEST - Reviewer completed. Files inspected since last update: no new files. Decision/blocker: sufficient with adjustment; required sections, scoped files, red test, owner guard placement, KE-020 preservation, and host-only verification are present. Next action: add explicit proof-profile section and run arbiter.
- 2026-05-23 20:10:15 CEST - Reviewer started. Files inspected since last update: no new files. Decision/blocker: checking for missing sections, stale assumptions, hidden scope expansion, and verification gaps. Next action: complete sufficiency review.
- 2026-05-23 20:08:04 CEST - Planner completed. Files inspected since last update: no new files. Decision/blocker: draft plan created around one owner guard and focused host-only tests. Next action: reviewer sufficiency pass.

## Execution Progress

- 2026-05-23 20:12:01 CEST - Executor started. Files inspected or touched since last update: plan, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`. Command/result: `git status --short` showed many unrelated dirty/untracked files, while the two owned source/test files were not listed dirty. Decision/blocker: no scope blocker; nested spawned agents are not available in this session, so execution proceeds as a bounded local executor/QA pass. Next action: add the GKR-001 non-owner admin denial test before production changes.
- 2026-05-23 20:12:46 CEST - Red test completed. Files inspected or touched since last update: `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`. Command/result: `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'GKR-001 non-owner admin cannot rotate group key'` failed as expected with `Expected: null Actual: GroupKeyInfo(groupId: group-1, keyGeneration: 2)` after bridge update/generate/sign/encrypt/promote/publish events. Decision/blocker: red confirmed current code allows non-owner admin rotation. Next action: add the owner-only guard before bridge side effects.
- 2026-05-23 20:13:14 CEST - Executor implementation completed. Files inspected or touched since last update: `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`. Command/result: added `group.createdBy != selfPeerId` denial after existing rotate-permission denial and before source-device/persisted-key/bridge work. Decision/blocker: no blocker. Next action: rerun GKR-001 selector.
- 2026-05-23 20:13:14 CEST - GKR-001 selector completed. Files inspected or touched since last update: no new files. Command/result: `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'GKR-001 non-owner admin cannot rotate group key'` passed; output ended `00:00 +1: All tests passed!` and flow showed only begin plus permission-denied events. Decision/blocker: non-owner admin denial now blocks before bridge side effects. Next action: run KE-020 selector.
- 2026-05-23 20:13:22 CEST - KE-020 selector completed. Files inspected or touched since last update: no new files. Command/result: `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'KE-020 concurrent rotations allocate unique increasing epochs'` passed; output ended `00:00 +1: All tests passed!`. Decision/blocker: per-group serialized owner rotation still allocates epochs 2 and 3. Next action: run full focused use-case file.
- 2026-05-23 20:13:29 CEST - Full focused test file completed. Files inspected or touched since last update: no new files. Command/result: `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` passed; output ended `00:00 +35: All tests passed!`. Decision/blocker: no rotation-use-case regression detected. Next action: run scoped analyze/format and diff check.
- 2026-05-23 20:14:22 CEST - Hygiene and local QA completed. Files inspected or touched since last update: `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, plan. Command/result: `dart analyze lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` passed with `No issues found!`; `dart format --set-exit-if-changed lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` passed with `Formatted 2 files (0 changed) in 0.03 seconds.`; `git diff --check` passed with no output. Decision/blocker: scoped diff review shows only the owner guard, GKR-001 test, and this plan update. Next action: finalize execution result.

## Execution Result

Verdict: complete.

Changed files:

- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/group-key-rotation-authority-session-GKR-001-plan.md`

Implementation summary:

- Added a GKR-001 regression test proving a non-owner admin cannot rotate the group key, does not touch the bridge, does not persist epoch 2, and does not leave a pending rotation draft.
- Added the minimum owner-only guard in `rotateAndDistributeGroupKey` after the existing rotate-permission check and before source-device resolution, persisted-key restore, pending-draft loading, generation, distribution, promotion, publish, or local key persistence.
- Preserved owner rotation behavior, explicit rotate-permission denial, and KE-020 same-group serialization.

Verification:

- RED: `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'GKR-001 non-owner admin cannot rotate group key'` failed before implementation with `Expected: null Actual: GroupKeyInfo(groupId: group-1, keyGeneration: 2)`.
- GREEN: `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'GKR-001 non-owner admin cannot rotate group key'` passed.
- GREEN: `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'KE-020 concurrent rotations allocate unique increasing epochs'` passed.
- GREEN: `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` passed with `00:00 +35: All tests passed!`.
- GREEN: `dart analyze lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` passed with `No issues found!`.
- GREEN: `dart format --set-exit-if-changed lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` passed with `Formatted 2 files (0 changed) in 0.03 seconds.`.
- GREEN: `git diff --check` passed with no output.

Residual notes:

- The worktree still contains unrelated dirty and untracked files outside this session scope. They were not edited or reverted for GKR-001.

## Objective

Session classification: `implementation-ready`.

Real scope: add an owner-only local rotation authority guard in `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart` and add/update focused tests in `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`.

Exact problem statement: `rotateAndDistributeGroupKey` currently authorizes rotation through `GroupMemberPermissions.allows(GroupMemberPermission.rotateKeys, selfMember.role)`. Because `GroupMemberPermissions._defaultForRole` allows all admin roles to rotate, a non-owner admin can reach the persisted-key restore and `group:generateNextKey` path. This can create competing same-epoch material when multiple admins rotate from the same current epoch.

Closure bar: a non-owner admin returns `null` before any bridge-side generation, update, distribution, promotion, publish, pending-draft write, or epoch-2 local key persistence. Existing owner rotation behavior, explicit rotate permission denial, pending-draft reuse, distribution-before-promotion, and KE-020 same-group serialization remain green.

Source of truth: current code and focused tests win over stale prose. The active session contract is `Test-Flight-Improv/Group-Chat-Feature/group-key-rotation-authority-session-breakdown.md`. Gate source of truth is `Test-Flight-Improv/test-gate-definitions.md`, with `scripts/run_test_gates.sh` winning if those disagree.

Dependency impact: later group key-safety work can rely on only the group owner locally initiating rotation. If later requirements need multi-admin rotation, that is a separate protocol design session, not an adjustment to this guard.

## Device/Relay Proof Profile

Profile: host-only.

Required proof:

- Focused Flutter unit test selector for the new GKR-001 non-owner admin denial.
- Focused Flutter unit test selector for `KE-020 concurrent rotations allocate unique increasing epochs`.
- Full host-side rotation use-case test file.
- Scoped Dart analyzer/format checks for the touched production and test files.
- `git diff --check`.

Not required:

- iOS, Android, macOS, or simulator/device execution.
- Relay addresses, multi-relay fixtures, live pubsub peers, or fake-network integration proof.
- Go bridge/node tests, because this session only blocks Flutter-side local authority before existing bridge calls.

## Scope Guard

Only this session may change:

- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- this plan, if execution findings require a small correction before implementation begins

The owner source for this session is `GroupModel.createdBy`. The guard must be an additional release guard, not a replacement for the existing rotate-permission check. An owner whose member permission explicitly denies `rotateKeys` must still be denied by the existing path.

Do not change Go bridge/node code, group key generation semantics, repository schemas, local key storage pruning, pending key rotation draft behavior, distribution retry behavior, source-device binding, signed transition audit behavior, pubsub publish behavior, UI, notification routing, relay behavior, or the KE-020 per-group FIFO queue.

Accepted differences / intentionally out of scope: this plan does not design distributed multi-admin rotation, cross-device owner election, durable cross-process locks, invite/role reconciliation, or real network/device proof. It also does not broaden the frozen group named gate list.

Overengineering signals: new abstractions, new repository methods, migration work, role model redesign, new bridge commands, or changes outside the two owner files are out of scope unless direct evidence shows the owner check cannot be implemented with `group.createdBy`.

## Red Test

Existing tests covering this area:

- `allows writer with rotate permission override to rotate keys` proves explicit rotate permission still works for the current owner because the fixture group is created by `selfPeerId`.
- `denies admin whose rotate permission override is false` proves explicit permission denial still wins.
- `ML-013 bare writer and removed peer cannot rotate keys` proves non-admin and missing-member denial does not hit generate/update/persist.
- `KE-013 ...` selectors cover persisted-key restore before generation and fail-closed generation/restore cases.
- `KE-020 concurrent rotations allocate unique increasing epochs` proves same-process local rotation serialization remains intact.
- `NW-013 ...` selectors cover pending-draft reuse/fail-closed behavior after generation.

Regression to add first:

Add one focused test in `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, near the existing rotate-denial tests, named close to:

```dart
test('GKR-001 non-owner admin cannot rotate group key', () async { ... });
```

Test setup:

- Keep `selfPeerId` as the local caller and keep the local member as `MemberRole.admin` with no explicit permission override.
- Update or recreate the fixture group so `createdBy` is a different stable peer id, for example `peer-owner`, while `myRole` remains `GroupRole.admin`.
- Keep the persisted epoch-1 key from setup.
- Call `rotateAndDistributeGroupKey` with the same sender identity used by existing tests.

Expected red assertions before implementation:

- `result` is `null`.
- `bridge.commandLog` is empty, or at minimum does not contain `group:updateKey`, `group:generateNextKey`, `message.encrypt`, `payload.sign`, or `group:publish`.
- `await groupRepo.getLatestKey(groupId)` remains epoch `1`.
- `await groupRepo.getKeyByGeneration(groupId, 2)` is `null`.
- `await groupRepo.getPendingKeyRotation(groupId)` is `null`.

Why this is the right red test: with current code, an admin without an override passes the default `rotateKeys` permission check and can reach bridge update/generate. The test fails until owner authority is checked before any bridge side effect.

## Minimal Implementation

Files and repos to inspect next:

- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/core/bridge/fake_bridge.dart` only if command logging assertions need confirmation
- `test/shared/fakes/in_memory_group_repository.dart` only if persistence assertions need confirmation

Step-by-step implementation plan:

1. Re-run `git status --short` and inspect any unexpected dirty state in the two target files before editing. Do not revert unrelated files.
2. Add the GKR-001 red test first and run its focused selector. It should fail because current code lets a non-owner admin proceed.
3. In `rotateAndDistributeGroupKey`, add the minimal owner guard after the current group lookup and existing member/rotate-permission denial, but before `_resolveSourceDevice`, `getLatestKey`, `callGroupUpdateKey`, pending-draft loading, and `callGroupGenerateNextKey`.
4. The guard should compare `group.createdBy` to `selfPeerId`; when they differ, emit the same permission-denied style flow event or an equally narrow denial event, then return `null`.
5. Do not alter `_withSerializedGroupRotation`, pending draft helpers, distribution helpers, or bridge helper calls.
6. Re-run the GKR-001 selector. Then run the KE-020 selector to prove serialization still commits epochs `2` and `3`.
7. Run the full focused use-case test file and hygiene commands listed below. Stop if the owner guard causes unrelated rotation behavior changes instead of loosening tests.

Risks and edge cases:

- Placing the guard after the persisted-key restore would still call `group:updateKey`, violating the no-update requirement.
- Checking only `group.myRole == GroupRole.admin` would not distinguish owner from non-owner admin and would leave the bug open.
- Replacing the existing permission check would regress explicit `rotateKeys: false` denial for the owner.
- Moving or widening the per-group queue risks KE-020 regressions and is outside this session.

## Verification Commands

Run these host-only commands from `/Users/I560101/Project-Sat/mknoon-2/flutter_app`:

```bash
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'GKR-001 non-owner admin cannot rotate group key'
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'KE-020 concurrent rotations allocate unique increasing epochs'
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart
dart analyze lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart
dart format --set-exit-if-changed lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart
git diff --check
```

Known-failure interpretation:

- The new GKR-001 selector must fail before the guard and pass after it.
- The KE-020 selector must stay green after the guard; any regression there is in scope because the session explicitly preserves local rotation serialization.
- The full use-case file should pass. If it fails due to unrelated pre-existing dirty work, record the exact failing tests and rerun the GKR-001 and KE-020 selectors to separate session regressions from ambient failures.
- `git diff --check` is required by the breakdown. If it fails on unrelated pre-existing files, record the exact paths and also run a scoped whitespace check on the two target files.

## Dirty Worktree/Concurrency Note

The planning intake saw a dirty worktree with many unrelated modified and untracked files. The target source and target test were not listed as dirty at intake, but the executor must re-check because other agents may edit concurrently.

Do not revert, overwrite, reformat, or clean unrelated files. If another change appears in either target file before implementation, read it and adapt the owner guard/test around the current content instead of restoring an older version.

The session changes local authorization only. It must not add device/simulator dependencies, relay fixtures, cross-process locking, or Go bridge changes.

## Done Criteria

- The plan has been executed TDD-first: the GKR-001 test fails before implementation and passes after the minimal guard.
- Non-owner admin rotation returns `null` before any `group:updateKey`, `group:generateNextKey`, `message.encrypt`, `payload.sign`, `group:publish`, pending-draft persistence, or epoch-2 local key persistence.
- Owner rotation behavior and explicit permission denial behavior are preserved.
- `KE-020 concurrent rotations allocate unique increasing epochs` remains green.
- All verification commands either pass or have exact, pre-existing unrelated failures recorded with the GKR-001 and KE-020 selectors green.
- No files outside the scoped use case, focused test, and session documentation are edited for this session.

## Reviewer Pass

Sufficiency verdict: sufficient as-is after adding the explicit `Device/Relay Proof Profile` section.

Reviewer answers:

- Missing files, tests, regressions, or gates: none for this session. The plan names the only production/test files, the new red selector, the KE-020 preservation selector, the full focused test file, analyzer/format, and `git diff --check`.
- Stale or incorrect assumptions: none found. Current code authorizes through role-backed `rotateKeys`; `GroupModel.createdBy` is the available owner source; the fake bridge command log and in-memory repository support the planned assertions.
- Overengineering: none in the plan. It explicitly rejects repository/API/schema/Go/device/relay changes and keeps the implementation to one early guard.
- Decomposition sufficiency: sufficient. One red test, one local guard, and one preservation selector minimize implementation ambiguity.
- Minimum needed: keep the guard after group/member lookup and existing rotate-permission denial but before any bridge or persistence side effect; keep the red test on a non-owner admin with no explicit deny override.

## Arbiter Decision

Structural blockers remaining: none.

Incremental details intentionally deferred:

- A separate event name for owner-denied rotation is optional; using the existing permission-denied style event is acceptable if the test asserts behavior rather than telemetry.
- Broader group named gate runs are not required for this host-only session unless the executor finds an unexpected cross-file behavior change.

Accepted differences intentionally left unchanged:

- Owner-only local rotation is a release guard, not a distributed multi-admin key-rotation protocol.
- This plan does not address cross-process locking, cross-device owner election, relay/device proof, Go key generation behavior, or existing unrelated group gate residuals.

Final verdict: execution-ready. The plan is safe to implement now as one narrow TDD session.
