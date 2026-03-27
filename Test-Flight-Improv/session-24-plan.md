# Session 24 Plan: Ordinary Group Media Parent-Row Durability Closure

## 1. real scope

Session 24 is no longer an open implementation session.

Current repo evidence shows the targeted ordinary group media durability gap is already closed on the durable ordinary-media path:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` now persists the optimistic parent `GroupMessage` row before ordinary-media upload begins on the durable path.
- `test/features/groups/presentation/group_conversation_wired_test.dart` already proves:
  - parent-row pre-persist before upload completes
  - upload-failure transition to local `failed` while keeping retryable `upload_pending` attachments
  - explicit `groupNotFound` cleanup
  - explicit `unauthorized` cleanup
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` already proves retry recovery skips `upload_pending` rows when the parent row is missing.

In scope:
- document Session 24 as `stale/already-covered`
- preserve the repo evidence that closes the gap
- verify no local stale summary still treats Session 24 as open implementation work

Out of scope:
- new production code
- new regression tests
- gate reruns for doc-only closure
- any Session 25 or Session 26 work

## 2. session classification

`stale`

Why:
- the repo already covers the Session 24 gap strongly enough
- the required direct regressions are already present
- the governing audit already describes the ordinary-media parent-row gap as closed in the current tree

## 3. files and repos to inspect next

Primary closure docs:
- `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`

Primary production seam:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`

Primary direct proof:
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`

Supporting adjacent coverage:
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`

## 4. existing tests covering this area

Primary direct proof already in repo:
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `ordinary media pre-persists the parent row before upload completes and finalizes after sendGroupMessage`
  - `ordinary media upload failure persists failed parent state and restores composer and quote`
  - `ordinary media group-not-found rejection removes the row and cleans durable media state`
  - `ordinary media unauthorized rejection removes the row and cleans durable media state`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - `skips retry work when upload_pending attachments have no parent group message row`

Supporting adjacent proof:
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
  - background-task protection still covers wired send paths around this seam

## 5. regression/tests to add first, if any

None.

Session 24 is already covered by the existing direct regressions above.

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Required stale-session evidence:
- ordinary-media parent-row pre-persist exists in `group_conversation_wired.dart`
- ordinary-media upload-failure and cleanup contracts are already pinned in `group_conversation_wired_test.dart`
- missing-parent retry skip is already pinned in `retry_incomplete_group_uploads_use_case_test.dart`
- the closure docs do not materially contradict that repo state

## 7. step-by-step implementation or evidence-collection plan

1. Re-open the governing audit and restate the Session 24 target gap.
2. Re-open the current ordinary-media durable send seam in `group_conversation_wired.dart`.
3. Re-open the direct regression tests that prove the gap is already closed.
4. Confirm the retry-layer missing-parent-row regression still exists.
5. Update `Test-Flight-Improv/session-24-plan.md` to stale/closure state.
6. Verify whether any closure summary still incorrectly describes Session 24 as open work.
7. Mark Session 24 `accepted` and continue to Session 25.

## 8. risks and edge cases

- Do not re-open already-landed production work.
- Do not broaden closure evidence beyond the durable ordinary-media path actually covered in code/tests.
- Do not confuse adjacent background-task coverage with the primary Session 24 proof.
- Do not rerun named gates just for doc-only stale closure unless a production edit appears unexpectedly.

## 9. exact tests to run after implementation, if code changes occur

No production implementation is planned for Session 24.

If unexpected production edits appear, the required direct suites would be:
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`

## 10. subsystem gate(s), if relevant

None for the planned doc-only closure.

If unexpected production code changes land in the group messaging seam:
- Group Messaging Gate
  - `./scripts/run_test_gates.sh groups`

## 11. whether Baseline Gate is required

No.

Reason:
- Session 24 is being closed as stale/doc-only work
- Baseline Gate is only required when Flutter production code changes land

## 12. whether Startup / Transport Gate is required

No.

Reason:
- no lifecycle, startup, recovery, or device-backed transport code is being changed

## 13. done criteria

Session 24 is done when all of the following are true:
- the session is explicitly documented as `stale`
- the repo evidence closing the gap is recorded
- no new production implementation is attempted
- any stale summary inside the active session plan is removed
- Session 24 is marked `accepted`

## 14. dependency impact on later sessions if this session blocks

Session 24 should not block later sessions now that the repo evidence is already landed.

If a contradiction were discovered between docs and repo state, that would be a documentation blocker only unless the existing direct proofs were actually missing.
