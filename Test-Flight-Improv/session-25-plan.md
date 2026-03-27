# Session 25 Plan: Ordinary Group Failed-Send Retry Parity Closure

## 1. real scope

Session 25 is no longer an open implementation session.

Current repo evidence shows the ordinary group media publish-failure retry gap is already closed:
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart` now accepts `mediaAttachmentRepo`, reloads persisted attachments, retries rows whose attachments are fully `done`, and keeps `upload_pending` rows owned by `retryIncompleteGroupUploads(...)`.
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` now proves:
  - wire-envelope-only ordinary-media retry after inbox success cleared `inboxRetryPayload`
  - `upload_pending` attachments are still skipped here
  - rows with no resendable persisted attachments are still skipped
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart` now proves `lib/main.dart` threads `widget.mediaAttachmentRepository` into `retryFailedGroupMessages(...)` on resume.
- `test/features/groups/integration/group_resume_recovery_test.dart` already uses the new dependency shape at the direct retry seam.

Scope for Session 25 now:
- document the session as `stale/already-covered`
- preserve the current ordinary-media retry parity evidence
- update stale docs that still describe failed group retry as text-only

Out of scope:
- new production code
- new retry architecture
- voice publish-failure parity
- per-thread send serialization
- gate reruns caused only by doc edits

Important residual note:
- Session 25 closes ordinary-media failed-send retry parity, not universal voice parity.
- The voice producer path still does not persist a completed attachment row before the publish-failure window, so that narrower residual remains outside this session’s stale closure.

## 2. session classification

`stale`

Why:
- the targeted ordinary-media retry gap is already covered in the current repo
- the direct regression proof and resume wiring proof already exist
- the remaining work on this reliability axis is narrower than the original Session 25 scope and should not be conflated with ordinary-media closure

## 3. files and repos to inspect next

Primary closure docs:
- `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`

Primary production seam:
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/main.dart`

Primary direct proof:
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`

Supporting adjacent coverage:
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

## 4. existing tests covering this area

Primary direct proof already in repo:
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  - `retries a failed media row from persisted done attachments when inboxRetryPayload was cleared after inbox success`
  - `skips rows whose persisted media attachments are still upload_pending`
  - `skips media retry rows when no resendable persisted attachments exist`
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
  - `main.dart passes mediaAttachmentRepository into retryFailedGroupMessages on resume`

Supporting adjacent proof:
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - keeps unfinished upload ownership in the separate retry path
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - current retry callsite already uses the attachment-repo dependency shape

## 5. regression/tests to add first, if any

None.

Session 25’s ordinary-media retry parity regressions are already present.

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Required stale-session evidence:
- `retry_failed_group_messages_use_case.dart` retries persisted `done` attachments
- direct tests cover ordinary-media resend and `upload_pending` skip behavior
- `lib/main.dart` resume wiring is protected by a direct source-level test
- stale docs claiming “failed group retries are still text-only” are updated

Direct proof rerun used for this closure pass:
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/core/lifecycle/main_resume_group_upload_wiring_test.dart`

## 7. step-by-step implementation or evidence-collection plan

1. Re-open the retry use case and direct tests.
2. Re-open the resume wiring guard in `main_resume_group_upload_wiring_test.dart`.
3. Re-run the smallest direct proof for the landed retry parity seam.
4. Update `Test-Flight-Improv/session-25-plan.md` to stale/closure state.
5. Update stale reliability summaries that still describe failed group retry as text-only.
6. Mark Session 25 `accepted` and continue to Session 26.

## 8. risks and edge cases

- Do not overclaim voice publish-failure parity from the current ordinary-media closure.
- Do not reopen the retry path just because the earlier docs were stale.
- Do not collapse the ownership split between `retryFailedGroupMessages(...)` and `retryIncompleteGroupUploads(...)`.
- Do not rerun named gates for doc-only closure unless unexpected production edits appear.

## 9. exact tests to run after implementation, if code changes occur

No production implementation is planned for Session 25.

If unexpected production edits appear, the required direct suites would be:
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test test/core/lifecycle/main_resume_group_upload_wiring_test.dart`

Optional nearby integration safety net if the retry callsite changes again:
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart`

## 10. subsystem gate(s), if relevant

None for the planned doc-only closure.

If unexpected production code changes land in the retry/recovery seam:
- Group Messaging Gate
  - `./scripts/run_test_gates.sh groups`

## 11. whether Baseline Gate is required

No.

Reason:
- Session 25 is being closed as stale/doc-only work
- Baseline Gate is only required when Flutter production code changes land

## 12. whether Startup / Transport Gate is required

No.

Reason:
- no lifecycle or recovery behavior is being changed in this closure pass
- the existing resume wiring proof is already present and was rerun directly

## 13. done criteria

Session 25 is done when all of the following are true:
- the session is explicitly documented as `stale`
- the landed ordinary-media retry parity evidence is recorded
- stale docs no longer describe failed group retry as text-only
- no new production implementation is attempted
- Session 25 is marked `accepted`

## 14. dependency impact on later sessions if this session blocks

Session 25 should not block later sessions now that the targeted ordinary-media retry seam is already landed.

If a contradiction were discovered, it would be a documentation/evidence blocker unless the direct retry proof was actually missing or failing.
