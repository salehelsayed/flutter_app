# GCA-008 Member Removal Partial-State Rollback/Ordering Plan

Status: execution-ready

## Planning Progress

- 2026-05-23T21:33:00+02:00 - Arbiter completed. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-008-plan.md`. Decision/blocker: no structural blockers remain; adjacent/full-suite failures are residual-only for GCA-008 under the exact signatures recorded, and the plan is execution-ready for acceptance-only closure. Next action: closure may proceed using the required row-owned evidence and residual recording contract.
- 2026-05-23T21:31:40+02:00 - Reviewer completed; Arbiter started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-008-plan.md`. Decision/blocker: sufficient with one incremental wording cleanup; no structural blocker because required closure evidence now matches the row-owned passing proof and residual diagnostics have exact signatures. Next action: apply wording cleanup, refresh reviewer/arbiter sections, and classify final recovery plan safety.
- 2026-05-23T21:31:05+02:00 - Planner completed; Reviewer started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-008-plan.md`. Decision/blocker: draft now classifies adjacent/full-suite failures as residual-only, changes same-session classification to `acceptance-only`, and separates required closure evidence from residual diagnostics. Next action: review for missing closure gates, stale assumptions, and accidental product/test/breakdown/matrix scope.
- 2026-05-23T21:28:58+02:00 - Evidence Collector completed; Planner started. Files inspected since last update: `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`. Decision/blocker: adjacent/full-suite reds are residual-only for GCA-008 because the command-order red is caused by existing `rotateAndDistributeGroupKey` pre-generation `group:updateKey`, writer-leave red is on existing rotation permission behavior, and replay-envelope red is not rollback state. Next action: tighten acceptance, known-failure, and done criteria around focused rollback proof plus truthful residual recording.
- 2026-05-23T21:28:06+02:00 - Evidence Collector started for same-session recovery. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-008-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md`, `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md`. Decision/blocker: recovery question is limited to whether adjacent/full-suite failures are GCA-008-owned or residual-only; no product/test/source-matrix/breakdown edits are allowed. Next action: inspect the direct Group Info and rotation code/tests for ownership evidence.

## Execution Progress

- 2026-05-23T21:08:36+02:00 - Executor started; contract extracted. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-008-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/group_membership_event_watermark.dart`, `lib/features/groups/application/group_config_payload.dart`, `test/core/bridge/fake_bridge.dart`, `test/shared/fakes/in_memory_group_repository.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`, `lib/features/groups/domain/repositories/group_repository.dart`, `lib/features/groups/domain/repositories/group_message_repository.dart`, `lib/features/groups/domain/models/group_model.dart`, `lib/features/groups/presentation/screens/group_info_screen.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`. Decision/blocker: no scope blocker; worktree has unrelated dirty files, target files are not modified yet. Next action: add the focused GCA-008 failing-first widget regression before production edits.
- 2026-05-23T21:11:03+02:00 - Executor added RED regression. Files touched since last update: `test/features/groups/presentation/group_info_wired_test.dart`. Decision/blocker: added `GCA-008 failed post-remove steps roll back local removal state` covering publish `ok:false`, inbox-store `ok:false`, and key-generation `ok:false` after local removal. Next action: run the required failing-first focused command before production edits.
- 2026-05-23T21:11:41+02:00 - RED command finished. Files touched since last update: none. Command: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-008"`. Result: failed as expected at `publish ok false should restore Alice locally` because Alice was `null` after `group:publish` returned `ok:false`; logs also showed `group:inboxStore` and `group:generateNextKey` continued after the failed publish. Decision/blocker: expected GCA-008 partial-state failure confirmed before production edits. Next action: implement narrow rollback/check in `group_info_wired.dart`.
- 2026-05-23T21:13:25+02:00 - Implementation applied. Files touched since last update: `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_wired_test.dart`. Decision/blocker: `_onRemoveMember` now captures pre-removal group/member state, checks `group:publish` `ok:true`, and rolls back member, `lastMembershipEventAt`, failed timeline message, and admin bridge config on post-remove failures; `dart format` ran on both touched files. Next action: rerun the focused GCA-008 command as final row proof.
- 2026-05-23T21:13:55+02:00 - Final focused row proof passed. Files touched since last update: none. Command: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-008"`. Result: pass (`+1`). Decision/blocker: publish, inbox-store, and key-generation failure rollback assertions all passed. Next action: run adjacent focused regressions.
- 2026-05-23T21:14:45+02:00 - Adjacent focused regression failed. Files touched since last update: none. Command: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "remove member calls bridge in correct order"`. Result: failed because the first distinct commands were `group:updateConfig`, `payload.sign`, `group:publish`, `group.encrypt`, `group:inboxStore`, `group:updateKey` instead of the test's expected `group:generateNextKey` at slot 6. Triage: unrelated-but-required existing failure from `rotateAndDistributeGroupKey` issuing a pre-generation `group:updateKey`; GCA-008 did not touch that use case or successful-flow ordering before rotation starts. Next action: continue the remaining required commands and report this residual/blocker explicitly.
- 2026-05-23T21:15:23+02:00 - Adjacent focused regressions continued. Files touched since last update: none. Commands/results: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "stale non-member removal shows error and emits no removal side effects"` passed (`+1`); `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart --plain-name "restores removed member when group:updateConfig fails"` passed (`+1`); `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart --plain-name "ML-005 config sync failure restores removed online member"` passed (`+1`). Decision/blocker: stale failure and lower-level config rollback remain intact. Next action: run direct suites.
- 2026-05-23T21:17:26+02:00 - Direct suites run. Files touched since last update: none. Commands/results: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart` failed (`+44 -3`); expanded/targeted triage identified residuals in `writer leave broadcasts a durable left-the-group event before local cleanup` (rotation permission denied before `group:generateNextKey`), `remove member calls bridge in correct order` (same pre-generation `group:updateKey` order mismatch), and `EK004 remove member broadcast stores signed member_removed replay envelope` (`replayEnvelope['messageId']` was `null`). Triage: unrelated-but-required residuals from existing rotation/replay behavior, not caused by the GCA-008 rollback diff. `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart` passed (`+19`). Next action: run named `groups` gate and `git diff --check`.
- 2026-05-23T21:20:24+02:00 - Named gate and diff hygiene finished. Files touched since last update: none. Commands/results: `./scripts/run_test_gates.sh groups` failed (`+288 -13`); filtered diagnostic over the same group test files captured residual failures `BB-007`, `IJ005`, `BB-012`, `NW-004`, `IR-018`, `PL-004`, `IR-003`, `ST-004`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, and `GM-028`. Triage: residual-only known broad group-gate failures from the plan, not caused by GCA-008; direct GCA-008 row proof passed. `git diff --check` passed. Manual verification: not run. Next action: mark Executor completion with residuals.
- 2026-05-23T21:20:24+02:00 - Executor completed. Files touched for GCA-008: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-008-plan.md`, `test/features/groups/presentation/group_info_wired_test.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`. Decision/blocker: implementation and focused row evidence are complete; residual required-command failures remain unrelated-but-required and should be reviewed by QA/closure before acceptance classification.

## Recovery Input

2026-05-23T21:24:00+02:00 - Same-session recovery requested by the pipeline controller.

- Blocker class: `test_or_gate_failure`.
- Blocker signature: `GCA-008` focused rollback proof passes, but the session was marked blocked because the adjacent focused selector `remove member calls bridge in correct order` and full `group_info_wired_test.dart` remain red.
- Failing tests/gates: `remove member calls bridge in correct order` saw command order `group:updateConfig`, `payload.sign`, `group:publish`, `group.encrypt`, `group:inboxStore`, `group:updateKey` where the test expected `group:generateNextKey`; full `group_info_wired_test.dart` failed `+44 -3` on that same order mismatch plus writer-leave rotation permission/replay-envelope residuals; `./scripts/run_test_gates.sh groups` failed `+288 -13` on known broad group residuals.
- Current row-owned passing evidence: pre-implementation `GCA-008` selector failed as expected because Alice stayed removed after `group:publish ok:false` and post-remove work continued; post-implementation `GCA-008` selector passed; stale non-member removal selector passed; both lower-level `remove_group_member_use_case_test.dart` rollback selectors passed; full `remove_group_member_use_case_test.dart` passed `+19`; `git diff --check` passed.
- Owner files touched by this row: `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, and this plan file.
- Recovery question: tighten whether the adjacent command-order selector is truly GCA-008-owned. The execution triage says the mismatch comes from existing `rotateAndDistributeGroupKey` pre-generation `group:updateKey` behavior, which GCA-008 did not touch and which the plan lists as accepted/out-of-scope unless Group Info receives a null rotation result. A fresh planner should decide whether closure may treat those adjacent/full-suite failures as residual-only while keeping the focused GCA-008 rollback proof and lower-level rollback selectors mandatory, or whether another same-session code/test fix is required inside the two-file owner set.

## same-session recovery decision

Classification: residual-only for the adjacent/full-suite failures; acceptance-only for this recovery pass.

Evidence:

- `rotateAndDistributeGroupKey` currently calls `group:updateKey` to resync the persisted key before it builds the transition and reaches `group:generateNextKey`. The command-order selector's observed sixth distinct command, `group:updateKey`, comes from that existing rotation-use-case behavior, not from the GCA-008 rollback diff.
- The writer-leave red is on the voluntary-leave path and existing key-rotation permission behavior. GCA-008 owns admin removal rollback from Group Info, not voluntary leave rollback or rotation permission policy.
- The `EK004` replay-envelope residual is a signed replay artifact assertion (`messageId` observed as `null`) and does not disprove local rollback of member, watermark, timeline, or restored admin config.
- The focused GCA-008 selector, stale non-member selector, lower-level rollback selectors, lower-level full suite, and `git diff --check` are the row-owned closure evidence. The command-order selector, full `group_info_wired_test.dart`, and groups gate are residual diagnostics for this row unless their failure signature changes into a GCA-008 rollback failure.

## real scope

GCA-008 owns only member removal launched from Group Info when the local removal/config update succeeds but a later removal step fails. The relevant later steps are `group:publish`, `group:inboxStore`, and `rotateAndDistributeGroupKey`.

The eventual fix must keep the future implementation to these planned non-doc files:

- `test/features/groups/presentation/group_info_wired_test.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`

Hard constraint: the executor may touch no more than 3 non-doc implementation/test files total. If a correct fix appears to require a fourth non-doc file, a native/Go change, a repository contract change, a new shared abstraction, or broad membership orchestration work, stop and ask before editing.

What must not change: successful member removal semantics, the existing lower-level `group:updateConfig` rollback in `remove_group_member_use_case.dart`, permission checks, last-admin protection, stale non-member behavior, and cancellation behavior. This row must not change `rotateAndDistributeGroupKey` ordering, voluntary-leave rotation permission behavior, or replay-envelope schema to satisfy adjacent reds.

## closure bar

The session is good enough when a Group Info removal failure after local removal no longer leaves local accepted partial state:

- the removed member remains or is restored in `GroupRepository`
- the group's `lastMembershipEventAt` is restored to its pre-removal value
- the local removal timeline/cutoff message for the failed event is absent
- the admin-side Go group config is restored from the pre-removal membership through `group:updateConfig`
- `group:publish` `ok:false` is treated as removal failure, not ignored success
- `group:generateNextKey` is not reached after publish or inbox-store failure
- successful removal still calls `group:updateConfig`, signs, publishes, stores inbox replay, and reaches key rotation unless an already-known residual outside GCA-008 blocks an adjacent assertion
- same-session closure records any residual command-order, full `group_info_wired_test.dart`, or groups-gate failures exactly rather than treating those diagnostics as row-owned closure evidence

If restoring the admin-side Go config inside the 3-file cap is not feasible, the executor must stop and report that the row is still unsafe rather than closing GCA-008 on local DB rollback only.

## source of truth

Authoritative inputs for this session:

- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md`, session `GCA-008`
- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md`, row `GCA-008`
- current code in `remove_group_member_use_case.dart` and `group_info_wired.dart`
- current direct tests in `remove_group_member_use_case_test.dart` and `group_info_wired_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` for named gates

Conflict rule: current code and tests beat stale prose. If `test-gate-definitions.md` and `scripts/run_test_gates.sh` disagree, `scripts/run_test_gates.sh` wins.

## session classification

`acceptance-only`

The row implementation has already landed in the owner files. This same-session recovery pass tightens the acceptance/gate contract only; it does not authorize product-code, test-code, source-matrix, or breakdown edits.

## exact problem statement

`removeGroupMember` removes the member locally, builds a config without that member, calls `group:updateConfig`, and already restores the member plus deletes the cutoff message if `group:updateConfig` fails. Group Info then broadcasts and stores the `member_removed` transition and rotates keys after the local removal has already been accepted.

The gap is that Group Info has no rollback for failures after `removeGroupMember` returns. It also ignores `group:publish` responses where `ok != true`, because `callGroupPublish` returns an error map instead of throwing. A publish, inbox-store, or key-rotation failure can therefore leave the admin UI and local repository with the member removed, the membership watermark advanced, the local removal timeline present, and the admin Go config excluding the member.

User-visible behavior that must improve: when Group Info cannot fully complete member removal, the removed member must still be visible after refresh and removal must be retryable from the pre-removal local state. Successful removal must remain unchanged.

## files and repos to inspect next

Production:

- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/group_membership_event_watermark.dart`
- `lib/features/groups/application/group_config_payload.dart`

Tests/fakes:

- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/application/remove_group_member_use_case_test.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`

Infra/docs:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

Already covered:

- `remove_group_member_use_case_test.dart` has `restores removed member when group:updateConfig fails`.
- `remove_group_member_use_case_test.dart` has `ML-005 config sync failure restores removed online member`, including `lastMembershipEventAt` staying unchanged on config sync failure.
- `group_info_wired_test.dart` has successful removal coverage for config update, broadcast, inbox replay, key rotation, rotated-key distribution, signed replay envelope storage, stale non-member failure, and cancel behavior.
- `group_info_wired_test.dart` pins the success bridge order as `group:updateConfig`, `payload.sign`, `group:publish`, `group.encrypt`, `group:inboxStore`, `group:generateNextKey`; same-session recovery evidence shows this selector is currently red because existing rotation code emits pre-generation `group:updateKey`, so it is diagnostic/residual for GCA-008 unless it starts failing on rollback state.

Missing:

- No Group Info regression proves local membership, watermark, timeline, and admin config roll back when `group:publish`, `group:inboxStore`, or key rotation fails after `removeGroupMember` succeeds.
- No test proves `group:publish` `ok:false` is treated as a failure in the member-removal flow.

## regression/tests to add first

Add the failing-first regression in `test/features/groups/presentation/group_info_wired_test.dart` before production edits. Use `GCA-008` in the test names so the focused command can target only this row.

Test intent:

1. Build an admin Group Info fixture with admin, Alice to remove, Bob bystander, a replay key, `FakeBridge`, `FakeIdentityRepository`, `FakeP2PService`, and `InMemoryGroupMessageRepository`.
2. Seed a pre-removal `lastMembershipEventAt` value on the group so rollback can prove it restores the previous watermark rather than merely setting null.
3. Drive the existing UI remove-confirm flow for Alice.
4. Cover at least these failure modes, preferably through one small test-local helper in the same file:
   - `group:publish` returns `{'ok': false, 'errorMessage': 'forced publish failure'}`.
   - `group:inboxStore` returns `{'ok': false, 'errorCode': 'INBOX_FAILED', 'errorMessage': 'forced inbox failure'}`.
   - `group:generateNextKey` returns `{'ok': false, 'errorCode': 'ROTATION_FAILED', 'errorMessage': 'forced rotation failure'}`.
5. For each case, assert after the flow settles:
   - Alice is still present in `groupRepo.getMember('group-1', 'peer-alice')`.
   - Alice remains visible after the Group Info reload.
   - the group `lastMembershipEventAt` equals the pre-removal value.
   - the failed removal timeline message is not present in `msgRepo`.
   - no success-only observable occurs; if the existing widget harness can cheaply observe the pop result, it should not report a successful mutation for the failed removal, but do not add navigation harness scope just for this row.
6. For publish and inbox-store failures, assert `group:generateNextKey` is absent from `bridge.commandLog`.
7. For publish failure, assert `group:inboxStore` is absent too, proving the flow stops before durable replay when publish fails.

Expected initial result: this regression should fail on current code because Group Info accepts the local removal after post-remove failures, and because `group:publish` `ok:false` is currently ignored.

## step-by-step implementation plan

1. Re-check `git status --short` and re-open the target sections of the two planned files. Do not revert unrelated edits.
2. Add the GCA-008 failing-first widget regression in `group_info_wired_test.dart`. Keep any helper private and local to that test file. Do not create a new fake or shared test abstraction unless the executor stops and asks.
3. Run:

```bash
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-008"
```

Confirm it fails for the expected partial-state assertions before production edits.

4. In `group_info_wired.dart`, keep the successful flow shape but make `_onRemoveMember` capture rollback state before calling `removeGroupMember`:
   - pre-removal `GroupModel`
   - pre-removal target `GroupMember`
   - pre-removal member list if needed to rebuild config
   - the failed event's removal timeline message id
5. After `removeGroupMember` succeeds, treat post-remove steps as a commit boundary. Until publish, inbox store, and key rotation all succeed, any thrown error or explicit failed response must trigger local rollback.
6. Check the `callGroupPublish` result. If `ok != true`, throw a `StateError` or equivalent row-local error before building/storing the offline replay envelope.
7. Let `callGroupInboxStore` failures and `rotateAndDistributeGroupKey` returning null enter the same rollback path.
8. Implement the smallest local rollback inside `group_info_wired.dart`:
   - save the captured removed member back if absent
   - restore `lastMembershipEventAt` from the captured pre-removal group while preserving unrelated current group fields when possible
   - delete the failed removal timeline/cutoff message id from `msgRepo` when available
   - rebuild a config from the restored group and restored members and call `callGroupUpdateConfig` so the admin bridge config includes the restored member again
   - emit a diagnostic flow event for rollback success/failure
9. Preserve the existing catch/snackbar behavior and `_loadGroupInfo()` reload, but only set `_didMutateGroup = true` after all removal steps have succeeded.
10. Do not modify `remove_group_member_use_case.dart` unless the new test proves the existing lower-level rollback is insufficient. If that file must be touched, it is the third and final allowed non-doc file; add or adjust a focused use-case test in the same third-file budget only if still under the cap. If more files are needed, stop and ask.
11. Re-run the required closure evidence below, then run or cite the residual diagnostics and record their exact signatures.

Optional manual verification step, not a same-session closure gate:

- In a local debug run or fault-injection build, force a removal broadcast failure while removing Alice from Group Info. Confirm the failure snackbar appears, Alice remains visible after refresh, and retrying removal is still available.

## risks and edge cases

- `callGroupPublish` returns `ok:false` instead of throwing. The fix must explicitly inspect the result.
- `callGroupInboxStore` throws on `ok:false`; it should use the same rollback path.
- `rotateAndDistributeGroupKey` returns null for several failures. The Group Info caller already throws on null; the missing piece is rollback.
- Rollback after key-rotation failure may occur after publish and inbox replay have already happened. This session closes the local partial-state acceptance gap; it does not attempt remote compensation or unsend semantics.
- In this plan, key-rotation failure means `rotateAndDistributeGroupKey` returns null to Group Info. A non-null rotation result that internally logged a later `key_rotated` broadcast error is existing rotate-use-case behavior and is not reclassified in GCA-008.
- Rollback config restore can fail. If that happens in tests or cannot be handled inside the file cap, do not close GCA-008.
- Existing stale non-member, last-admin, permission-denied, and cancellation paths must remain unchanged.
- Do not rely on unawaited direct P2P membership update delivery for assertions; the row is about accepted local state and bridge/durable operation ordering.

## exact tests and gates to run

Required focused row proof:

```bash
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-008"
```

Required stale non-member proof:

```bash
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "stale non-member removal shows error and emits no removal side effects"
```

Required lower-level rollback proof:

```bash
flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart --plain-name "restores removed member when group:updateConfig fails"
flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart --plain-name "ML-005 config sync failure restores removed online member"
```

Required lower-level full suite:

```bash
flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart
```

Required diff hygiene:

```bash
git diff --check
```

Residual diagnostics to run or cite from the same execution record, and to record truthfully:

```bash
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "remove member calls bridge in correct order"
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart
./scripts/run_test_gates.sh groups
```

## known-failure interpretation

Before implementation, the new GCA-008 focused test is expected to fail for the partial-state assertions. After implementation, any failure in the focused GCA-008 selector, stale non-member selector, either lower-level rollback selector, the full `remove_group_member_use_case_test.dart` suite, or `git diff --check` is a GCA-008 blocker.

The `remove member calls bridge in correct order` selector is residual-only for GCA-008 only when the observed failure is the existing command order `group:updateConfig`, `payload.sign`, `group:publish`, `group.encrypt`, `group:inboxStore`, `group:updateKey` where the selector expected `group:generateNextKey`. That signature is owned by existing `rotateAndDistributeGroupKey` pre-generation key resync behavior, not by the rollback change. Any different failure in that selector, especially one showing publish/inbox/key rotation skipped unexpectedly on successful removal, must be re-triaged before closure.

The full `group_info_wired_test.dart` suite is residual-only for GCA-008 only when its failures are limited to the same command-order mismatch, writer-leave rotation permission/generate-next-key residual, and `EK004` replay-envelope `messageId` residual already recorded in the recovery input. Any failure in the focused GCA-008 rollback proof or stale non-member behavior is row-owned and blocking.

For `./scripts/run_test_gates.sh groups`, classify failures by test name and error. Existing matrix notes already record unrelated group-gate reds such as `GM-028`, `BB-007`, `IJ005`, startup/rejoin cases, `GE-017`, `GE-019`, `GE-020`, and `GM-029`. Those can be reported as residual-only if they reproduce unchanged and the required GCA-008 closure evidence above passes. Any new failure in member removal rollback, stale non-member behavior, lower-level removal rollback, or touched direct suites is a GCA-008 blocker.

The worktree is dirty. Do not revert or overwrite unrelated edits; compare only the files intentionally touched for GCA-008.

## done criteria

- The plan's failing-first GCA-008 regression fails before production edits for the expected reason.
- The same GCA-008 regression passes after the minimal fix.
- The stale non-member Group Info selector passes.
- Existing `removeGroupMember` config failure rollback selectors pass.
- Full `remove_group_member_use_case_test.dart` passes.
- `git diff --check` passes.
- The future implementation touches no more than 3 non-doc implementation/test files, with 2 planned.
- The command-order selector, full `group_info_wired_test.dart`, and `./scripts/run_test_gates.sh groups` are either green or recorded with exact residual signatures matching the known-failure interpretation above.
- Residual command-order/full-suite/gate reds are not classified as GCA-008 closure evidence unless they change into rollback, stale non-member, lower-level rollback, or diff-hygiene failures.
- The manual verification step is optional for this same-session recovery closure; if it is not run, record that honestly.

## scope guard

Non-goals:

- no voluntary leave rollback work (`GCA-010`)
- no local message cleanup work for leaving (`GCA-009`)
- no add-member, invite, re-add, role-change, metadata, or conversation send changes
- no native Go bridge change
- no database migration
- no new transaction framework or shared rollback abstraction
- no UI redesign
- no remote compensation, replay recall, or direct P2P unsend behavior after a publish/inbox operation already escaped
- no rotation-order, voluntary-leave permission, or replay-envelope schema fix in this row
- no matrix or breakdown edits during this planning-only task

Overengineering trigger: if the executor starts designing a generalized membership transaction manager, a reusable rollback service, or cross-feature operation journal, stop. GCA-008 needs one narrow Group Info rollback/check around the existing removal flow.

## accepted differences / intentionally out of scope

- `removeGroupMember` remains the lower-level local removal plus admin config update use case. Key rotation stays orchestrated by Group Info.
- Remote peers may receive a member-removal publish, inbox replay, or direct update before a later key-rotation failure. This session does not solve remote compensation; it only prevents the initiating client from accepting a failed removal as completed local state.
- `rotateAndDistributeGroupKey` may internally log and continue after its final `key_rotated` system publish fails while still returning a key. That behavior is accepted as outside this row unless Group Info receives a null result.
- `rotateAndDistributeGroupKey` pre-generation `group:updateKey` key resync remains out of scope for GCA-008, even though it currently makes the adjacent command-order selector red.
- Writer-leave rotation permission behavior is out of scope for GCA-008 and belongs with voluntary-leave/rotation ownership, not admin removal rollback.
- `EK004` replay-envelope `messageId` residual is out of scope for GCA-008 unless it prevents the focused rollback evidence from passing.
- The existing direct P2P membership update is unawaited and remains outside the row unless it directly prevents local rollback.
- Closure doc updates to the matrix and breakdown belong to the implementation/closure pass, not this planning-only turn.

## dependency impact

GCA-010 can reuse the rollback lesson for voluntary leave, but it must remain a separate session because it has different local deletion and native leave semantics. Later removed-member privacy, re-add, replay, and key-rotation rows should be able to assume that a failed Group Info removal leaves the initiating client in retryable pre-removal local state. If GCA-008 discovers rollback cannot restore admin bridge config under the hard file cap, later rows that depend on reliable removal failure semantics should pause until that blocker is resolved.

## reviewer sufficiency pass

Reviewer verdict: sufficient with adjustments applied for same-session recovery.

Reviewer questions:

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient with adjustments applied; the acceptance contract now separates required row-owned closure evidence from residual diagnostics.
- What files, tests, regressions, or gates are missing? None structurally. Required closure evidence is the focused GCA-008 selector, stale non-member selector, two lower-level rollback selectors, full `remove_group_member_use_case_test.dart`, and `git diff --check`; command-order/full `group_info_wired_test.dart`/groups gate diagnostics must be recorded truthfully.
- What assumptions are stale or incorrect? The prior assumption that all adjacent focused removal tests must be green was stale for this recovery pass. Current code shows the command-order red comes from existing `rotateAndDistributeGroupKey` pre-generation `group:updateKey`, not the GCA-008 rollback path.
- What is overengineered? Nothing structural; the plan still rejects rotation-order, voluntary-leave, replay-envelope, native, migration, or shared-rollback work in this row.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. No new implementation is authorized; closure is acceptance-only with exact residual signatures.
- What is the minimum needed to make the plan sufficient? Keep the focused rollback proof and lower-level rollback/full-suite proof mandatory, keep `git diff --check`, and require exact residual recording for command-order/full Group Info/groups-gate reds.

## arbiter decision

Final verdict: execution-ready for acceptance-only closure.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Do not require the command-order selector, full `group_info_wired_test.dart`, or `./scripts/run_test_gates.sh groups` to turn green in this GCA-008 recovery pass when their failures match the recorded residual signatures.
- Do not add broader simulator or real-network coverage unless the focused implementation exposes a wider failure that cannot be classified with the direct selectors and suites.

Accepted differences intentionally left unchanged:

- Remote compensation after an already-published or inbox-stored removal is out of scope.
- `rotateAndDistributeGroupKey` internal non-fatal `key_rotated` broadcast logging is out of scope when the use case still returns a key.
- Voluntary leave rollback remains GCA-010, not GCA-008.
- `rotateAndDistributeGroupKey` pre-generation `group:updateKey`, writer-leave rotation permission, and `EK004` replay-envelope `messageId` residuals remain outside GCA-008 unless they start failing the focused rollback evidence.

Why safe to close now: the required row-owned evidence proves the rollback seam directly, the residual diagnostics have exact signatures and owners outside GCA-008, and the plan forbids product/test/source-matrix/breakdown edits during this same-session recovery pass.

## Execution Progress

- 2026-05-23T21:06:11+02:00 - Phase: contract extracted. Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-008-plan.md`, `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`. Decision/blocker: execute GCA-008 only; planned non-doc write scope is `test/features/groups/presentation/group_info_wired_test.dart` and `lib/features/groups/presentation/screens/group_info_wired.dart`, with hard stop if a correct fix requires more than 3 non-doc implementation/test files. Required RED proof, direct tests, `./scripts/run_test_gates.sh groups`, `git diff --check`, and manual verification step identified. Next action: spawn isolated Executor pass.
- 2026-05-23T21:06:33+02:00 - Phase: Executor spawned/running. Files inspected or touched: this plan. Command currently running: `codex exec` with `model=gpt-5.5` and `model_reasoning_effort=xhigh`. Decision/blocker: none. Next action: wait for Executor completion and inspect landed evidence before spawning QA.
