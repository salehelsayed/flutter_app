# Audit 43 Session 2 Plan: Terminal Cancel Semantics For Direct-Message Media Sends

## Real scope

- Make an accepted direct-message media cancel terminal for that same attempt across later retry ownership and resume recovery.
- Keep the current direct-conversation cancel affordance, optimistic persistence, and existing failed-media controls for genuinely failed uploads unless the cancel-specific regression proves they must branch.
- Add the smallest direct regressions needed to prove that a cancelled attempt no longer re-uploads, retries, resumes, or reaches recipient delivery.

## Closure bar

- Once the user accepts cancel for an in-flight direct-message media upload, that same message attempt is no longer treated as an ordinary retryable failed-media row.
- `retryFailedMessages(...)` does not pick the cancelled attempt back up.
- Resume-time incomplete-upload recovery and pending-message retry orchestration do not resurrect the cancelled attempt.
- Existing direct cancel UX remains truthful: cancel still restores the composer snapshot and still suppresses the final send path for that attempt.
- Required direct tests pass, plus `1to1` and `baseline`; `transport` runs only if the landed change truly widens into shared lifecycle orchestration.

## Source of truth

- Active controller artifact:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
- Adjacent reopened-seam history:
  `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-breakdown.md`
- Policy/gates:
  `Test-Flight-Improv/14-regression-test-strategy.md`,
  `Test-Flight-Improv/test-gate-definitions.md`
- Stable maintenance references still owned by later closure:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`,
  `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`,
  `Test-Flight-Improv/00-INDEX.md`
- Current code and tests beat stale closure prose if they disagree.

## Session classification

- `implementation-ready`

## Exact problem statement

- `lib/features/conversation/presentation/screens/conversation_wired.dart`
  already accepts cancel on the active upload banner, marks that message's
  `upload_pending` attachments as `upload_failed`, restores the composer, and
  suppresses the immediate final send path.
- That restored row still lands as ordinary `message.status == 'failed'` with
  persisted media attachments, which means downstream retry ownership still
  treats it like a normal failed media send.
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  currently re-resolves any failed message with persisted attachments whose
  attachments are not all `done`; it does not distinguish user-cancelled
  terminal rows from genuinely retryable failures.
- `lib/core/services/pending_message_retrier.dart` later invokes
  `retryFailedMessages(...)`, so resume recovery can inherit the same wrong
  retryability if the persisted state is not made terminal enough.
- Existing `conversation_wired_test.dart` coverage proves cancel suppresses
  the immediate send boundary and failure snackbar, but it does not prove that
  manual retry or resume-time retry ownership cannot resurrect the cancelled
  attempt later.

## Files and repos to inspect next

- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/core/services/pending_message_retrier.dart` only if the final fix
  requires a shared orchestration guard beyond the retry use case itself
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
  and implementation only if a persisted terminal marker beyond current
  `upload_failed` is required
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
  only if the final proof must show recipient non-delivery beyond the direct
  wired and retry seams

## Existing tests covering this area

- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  already covers cancel on the active upload banner, cancel-before-failure
  resolution, send suppression, and composer restore.
- `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`
  covers failed-media retry and re-upload ownership, but not a cancel-terminal
  exception to that retry behavior.
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  already covers late-send abort for deleted or terminalized attachment states.
- No current direct regression proves that a cancelled attempt stays terminal
  under manual retry or resume-driven retry ownership.

## Regression/tests to add first

- Add a direct retry-use-case regression in
  `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`
  proving that a failed message row produced by accepted cancel is skipped
  rather than re-uploaded and re-sent.
- Add a direct conversation-wired regression in
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  proving the cancelled row no longer surfaces as the ordinary retryable
  failed-media affordance if that is the chosen user-visible contract.
- Add a resume-adjacent proof only if the final implementation touches
  `retryIncompleteUploads(...)` or `pending_message_retrier.dart`; otherwise
  rely on the direct retry-use-case proof because resume recovery delegates to
  that same retry ownership.

## Step-by-step implementation plan

1. Reproduce the downstream retry seam in
   `retry_failed_messages_media_reupload_test.dart` for a cancelled row.
2. Inspect the smallest terminal marker that can distinguish
   user-cancelled media attempts from ordinary retryable failures.
3. Prefer a narrow persisted marker or filter that keeps the current upload
   architecture intact and avoids inventing a broader message-state redesign.
4. Update the direct conversation surface only as much as needed so the
   cancelled attempt no longer presents itself like a normal retryable
   failed-media row.
5. Run the exact direct suites first.
6. Run `1to1` and `baseline`, then stop unless the fix truly widened into
   shared lifecycle or startup orchestration that requires `transport`.

## Risks and edge cases

- Video plus caption must remain covered; cancel cannot accidentally clear only
  the media portion while still sending the text.
- A late upload completion after cancel must not fall back into send.
- Resume recovery must not reanimate the cancelled attempt through the shared
  failed-message retrier.
- The fix must not break legitimate retry for genuinely failed media rows.
- If the chosen terminal marker requires repository persistence changes,
  message hydration and delete controls must remain coherent.

## Exact tests and gates to run

- Direct tests:
  - `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `flutter test test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`
- Conditional direct tests:
  - `flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
    if the landed fix changes resume-time upload recovery or late-send guards
  - `flutter test test/core/services/pending_message_retrier_test.dart`
    if the landed fix changes shared retry orchestration
  - `flutter test test/features/conversation/integration/media_attachment_flow_test.dart`
    only if a broader recipient non-delivery proof becomes necessary
- Named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
- Conditional named gates:
  - `./scripts/run_test_gates.sh transport`
    only if the landed fix materially changes lifecycle, resume, reconnect,
    inbox-drain, or startup-owned retry behavior

## Known-failure interpretation

- Treat any failure in the new cancel-terminal retry regression, the existing
  wired cancel tests, or the required gates as session-relevant until proven
  otherwise.
- If a broader gate fails for a pre-existing unrelated reason, capture the
  exact failing file and why it is unrelated before accepting Session 2.
- Do not classify an expected change in cancel semantics as a pre-existing
  failure; the new regression is the source of truth for this seam.

## Done criteria

- A cancelled direct-message media attempt is no longer retried by the normal
  failed-media retry ownership.
- The conversation surface no longer presents the cancelled attempt as an
  ordinary retryable failed-media row if the landed contract requires that
  distinction.
- Existing cancel send-suppression behavior still passes.
- Required direct tests pass.
- Required named gates pass, or any unrelated pre-existing failure is
  explicitly evidenced under the gate definitions.

## Scope guard

- Do not reopen the broader cancelable-upload program from Report `24`.
- Do not invent a new cross-product upload architecture or a general-purpose
  cancel protocol unless the narrow regressions prove it is unavoidable.
- Do not widen into group or announcement upload parity in this session.
- Do not edit frozen gate definitions.

## Accepted differences / intentionally out of scope

- No promise of true mid-stream transport abort; the closure bar is terminal
  user-visible semantics for that same attempt.
- No group or announcement parity work in this session.
- No new message-status redesign by default; only add a stronger persisted
  terminal marker if the direct regressions prove current `failed` plus
  `upload_failed` is insufficient.

## Dependency impact

- Session `7` depends on this session landing with explicit retry/resume proof
  so the final closure sweep can honestly refresh Reports `24`, `35`, and `19`.
- Sessions `3`, `4`, and `5` remain otherwise independent.
- Session `6` still depends only on Session `5`.
