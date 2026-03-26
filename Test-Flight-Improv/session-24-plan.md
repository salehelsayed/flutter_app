# Session 24 Plan: Make Ordinary Group Media Durable Before Upload Starts

## 1. real scope

Close the first high-value reliability gap from `18-group-discussion-reliability-audit.md`: ordinary group media should persist the parent `GroupMessage` row before upload begins so “send media, lock the phone, recover on resume” is as trustworthy as the stronger existing voice path.

Concrete repo evidence already narrows the scope:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` already creates durable `upload_pending` attachment rows before upload for ordinary media.
- That same path still leaves `sendGroupMessage(...)` as the first place that owns the final parent message-row save.
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` requires `groupMsgRepo.getMessage(messageId)` and skips recovery when the parent row is missing.
- `test/features/groups/presentation/group_conversation_wired_test.dart` already proves the voice path persists the durable parent row before upload.
- The current ordinary-media path still routes non-success results through the local restore/failed path rather than the voice-only explicit cleanup branch for `groupNotFound` / `unauthorized`.
- The ordinary media path still lacks the same direct regression.

In scope:
- add the missing ordinary-media regression first
- persist the parent `GroupMessage` row before ordinary media upload begins
- keep `sendGroupMessage(...)` responsible for final status transitions and final persisted message state
- preserve current optimistic UI behavior, durable pending attachment behavior, and parallel media upload behavior
- prove that resume-time recovery still has a parent message row to resolve
- make the post-change ordinary-media failure contract explicit for:
  - upload failure before `sendGroupMessage(...)`
  - `groupNotFound`
  - `unauthorized`

Out of scope:
- extending failed group media/voice retry parity after publish failure
- adding a per-thread send serializer
- changing group status semantics
- changing announcement behavior
- changing startup / transport / bridge behavior unless the narrow fix unexpectedly requires a minimal compatibility adjustment

## 2. session classification

`implementation-ready`

Why:
- the gap is concrete and local to the ordinary group-media send path
- the stronger voice path already shows the intended durability shape
- the required tests and gates already exist, but this session must explicitly pin the new ordinary-media failure/cleanup contract before execution
- this is a narrow correctness fix, not a profiling or evidence-only session

## 3. files and repos to inspect next

Primary planning / rationale docs:
- `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/09-network-group-messaging.md`

Primary code:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`

Primary tests:
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart` only as broader gate-level recovery coverage, not as the primary seam proof for this session

Gate / regression references:
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh transport` only if the fix touches lifecycle / resume / recovery wiring

Execution note:
- `Test-Flight-Improv/test-gate-definitions.md` is the execution source of truth for named gates and known failures.
- `Test-Flight-Improv/14-regression-test-strategy.md` remains the policy/rationale reference for why this session adds the regression first and then runs direct suite + gates.
- `Test-Flight-Improv/test-gates-reference.md` is not required for Session 24 because it does not add anything essential beyond the frozen gate definitions.

## 4. existing tests covering this area

Already present and relevant:
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  - proves ordinary media persists `upload_pending` rows before upload and uploads from durable copies
  - proves the voice path persists the durable parent message row before upload
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
  - proves background-task protection across lock / unmount flows on the wired send paths
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - proves pending group uploads are retried only for group messages and republished after upload recovery
  - does not yet pin the specific parent-row-missing dependency that motivates this session
- `test/features/groups/application/send_group_message_use_case_test.dart`
  - proves the core group send contract and final message-state behavior
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - acts only as broader group-recovery coverage inside the named gate, not as the targeted proof for the ordinary-media parent-row gap

What is missing:
- no direct regression currently proves that the ordinary media path persists the parent `GroupMessage` row before upload starts
- no direct regression currently proves the ordinary media path now has the same parent-row durability guarantee that the voice path already has
- no direct regression currently pins the exact upload-failure contract once the parent row is saved before upload completes:
  - persisted parent row transitions to local `failed`
  - durable `upload_pending` attachment rows remain retryable
  - composer / quote restore still works
- no direct regression currently pins the exact `groupNotFound` / `unauthorized` contract once ordinary media also pre-persists the parent row
- no retry-layer regression currently pins that `retryIncompleteGroupUploads(...)` skips recovery when the parent message row is missing, which is the lower-layer dependency this session is closing

## 5. regression/tests to add first, if any

Yes. Add the orchestration regression first in `test/features/groups/presentation/group_conversation_wired_test.dart`.

That regression should prove:
- ordinary media creates durable `upload_pending` attachment rows before upload starts
- the parent `GroupMessage` row is already persisted with `status == 'sending'` before the gated upload completes
- the message is still finalized correctly after upload + `sendGroupMessage(...)` complete

Add one narrow companion regression in the same file for the new early-persist behavior:
- if upload fails before `sendGroupMessage(...)` runs:
  - the already-persisted parent row becomes local `failed`
  - durable `upload_pending` attachment rows remain retryable
  - composer / quote restore behavior still works
- if `sendGroupMessage(...)` returns `groupNotFound` or `unauthorized`, pin the final ordinary-media contract explicitly rather than leaving it implicit
  - if Session 24 mirrors the voice path, assert local row removal + attachment cleanup + pending-upload-dir cleanup
  - if Session 24 intentionally keeps a different contract, assert that exact contract directly

Preferred first test shape:
- gate the ordinary media upload function
- tap send on a message with media
- assert the pending attachment rows exist
- assert the parent message row already exists before the upload gate is released
- release the upload gate
- assert the final message row is still `sent` / `pending` according to the existing send contract

Add one narrow companion regression in `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`:
- prove the retry path depends on the parent message row for an `upload_pending` attachment set
  - when the parent row is missing, no upload or publish attempt should run and the attachment set should stay pending
- keep it lower-layer and deterministic rather than widening into a new integration harness

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Not required. This session is not profile-gated or evidence-gated.

The repo evidence is already enough to proceed:
- ordinary media currently persists attachments before upload
- retry recovery currently requires the parent message row
- voice already demonstrates the intended parent-row durability pattern

## 7. step-by-step implementation or evidence-collection plan

1. Re-open the ordinary media send path in `group_conversation_wired.dart` and the stronger voice path in the same file.
   - confirm exactly where the ordinary media path writes durable attachments
   - confirm exactly where the voice path persists the parent optimistic message row before upload
2. Add the failing ordinary-media regression first in `test/features/groups/presentation/group_conversation_wired_test.dart`.
   - make the test mirror the voice durability test as closely as possible
   - prove the parent row exists before the upload finishes
   - add one narrow companion regression for upload failure that pins:
     - persisted parent row -> `failed`
     - durable pending attachments remain retryable
     - composer / quote restore behavior
   - add one narrow companion regression for `groupNotFound` / `unauthorized` that pins the exact chosen cleanup contract
3. Add one narrow companion regression in `retry_incomplete_group_uploads_use_case_test.dart`.
   - prove the retry path depends on the parent message row for an `upload_pending` set
   - prove the no-parent-row case performs no upload / publish work and leaves the attachment set pending
   - keep it deterministic and lower-layer
4. Implement the smallest safe production change in `group_conversation_wired.dart`.
   - persist the optimistic/durable parent `GroupMessage` row before ordinary media upload starts
   - keep `sendGroupMessage(...)` responsible for final state transitions
   - do not change the non-media text path
   - do not change the already-strong voice path unless a tiny shared helper extraction is the smallest safe option
5. Preserve current ordinary-media behavior:
   - durable `upload_pending` attachment rows still exist before upload
   - parallel upload behavior remains intact
   - optimistic UI still shows the in-flight message
   - upload failure leaves the pre-persisted parent row in the intended local `failed` state while composer restore behavior still works
   - pending-upload dir cleanup still runs on success
   - `groupNotFound` / `unauthorized` now follow one explicit pinned contract rather than an implicit fallback path
6. Re-run the direct tests.
7. Run the Group Messaging Gate.
8. Run the Baseline Gate.
9. Run the Startup / Transport Gate only if execution unexpectedly changes lifecycle / resume / recovery wiring rather than just the parent-row persistence point.
10. Interpret gate outcomes against the currently documented known failures in `Test-Flight-Improv/test-gate-definitions.md`.
    - A pre-existing red `baseline` or `transport` item should not be treated as a Session 24 regression unless the changed code clearly caused or widened it.
    - `baseline` is currently known-red because of the existing `loading_states_smoke_test.dart` build failure.
    - `transport` is currently known-red / env-sensitive and should stay conditional for this session unless the change escapes the local persistence seam.

## 8. risks and edge cases

- Do not accidentally create duplicate parent message rows by persisting the optimistic row early and then saving again through `sendGroupMessage(...)`.
- The row-ID collision path already replaces by message ID; the real risk is clobbering fields that must survive the early save rather than creating duplicate rows.
- Do not regress the current parallel media-upload behavior while moving parent-row persistence earlier.
- Do not break the no-media text path, which is already strong.
- Do not weaken the already-correct voice path while trying to “share” too much code.
- Do not lose the intended local failure contract when upload fails after the optimistic row has already been persisted:
  - row becomes `failed`
  - durable attachments stay retryable
  - composer / quote restore still works
- Do not leave the `groupNotFound` / `unauthorized` result path implicit once ordinary media also pre-persists the parent row.
- If the session mirrors the voice cleanup contract for `groupNotFound` / `unauthorized`, explicitly delete the local row, attachment rows, and pending-upload dir.
- Do not break cleanup of pending-upload directories after a successful send.
- Do not accidentally change status semantics from the current honest `sending` -> `sent/pending/failed` model.
- Keep the change local to the ordinary media durability gap; do not widen into failed-send media retry parity or send serialization in the same session.
- Do not misread a previously documented red named gate as a Session 24 failure if the failure is already listed under known failures in `Test-Flight-Improv/test-gate-definitions.md` and is unrelated to the changed files.

## 9. exact tests to run after implementation, if code changes occur

Direct tests:
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`

Conditional direct safety net if production changes cross the send-use-case boundary:
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`

Optional nearby integration safety net if the direct tests still expose a broader recovery-path ambiguity or if the ordinary-media parent-row persistence point unexpectedly affects broader widget resume coverage:
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart`

## 10. subsystem gate(s), if relevant

Required:
- Group Messaging Gate
  - `./scripts/run_test_gates.sh groups`

Not required by default:
- Startup / Transport Gate
  - only if the implementation changes lifecycle, pause/resume, startup, or recovery orchestration rather than only the parent-row persistence point

## 11. whether Baseline Gate is required

Yes, if production code changes land in `group_conversation_wired.dart`.

Command:
- `./scripts/run_test_gates.sh baseline`

Interpretation note:
- evaluate any red result against the known-failure ledger in `Test-Flight-Improv/test-gate-definitions.md`
- only treat it as a Session 24 regression if the changed scope clearly introduced or widened the failure
- do not require unconditional green while unrelated known failures remain documented in the gate ledger
- current known-failure note: `baseline` is already red because `integration_test/loading_states_smoke_test.dart` fails to build in the repo-wide gate validation

## 12. whether Startup / Transport Gate is required

No, not by default.

Run it only if the implementation changes:
- pause / resume wiring
- startup / recovery ordering
- device-backed media recovery wiring
- lock / unlock orchestration beyond the local parent-row persistence point

Command when needed:
- `./scripts/run_test_gates.sh transport`

Interpretation note:
- if `transport` is run, use the same known-failure rule from `Test-Flight-Improv/test-gate-definitions.md`
- do not reopen unrelated existing transport-gate failures as part of Session 24 unless the ordinary-media durability fix clearly affects them
- do not require unconditional green while unrelated documented transport failures remain unchanged
- current known-failure note: `transport` is already partly red / env-sensitive in the repo ledger, so it should remain conditional unless Session 24 touches that layer

## 13. done criteria

Session 24 is done when all of the following are true:
- an ordinary-media regression was added first
- the ordinary media path now persists the parent `GroupMessage` row before upload begins
- the parent row is visible as `sending` while upload is still in flight
- existing ordinary-media behavior remains intact:
  - durable `upload_pending` attachment rows are still written first
  - uploads still run from durable copies
  - optimistic display still works
  - upload failure now has an explicit pinned contract:
    - local row becomes `failed`
    - durable pending attachments remain retryable
    - composer / quote restore still works
  - final success state still comes from the normal `sendGroupMessage(...)` contract
- the ordinary-media `groupNotFound` / `unauthorized` result path is explicitly pinned rather than left implicit
- the retry-layer regression proves the ordinary-media durability change now matches the parent-row dependency used by `retryIncompleteGroupUploads(...)`
- the direct tests pass
- the Group Messaging Gate passes
- the Baseline Gate has been run and shows no new failures beyond the currently documented known-failure ledger
- the Startup / Transport Gate has been run and shows no new failures beyond the currently documented known-failure ledger if execution touched that layer

## 14. dependency impact on later sessions if this session blocks

If Session 24 blocks:
- do not start the failed-send media/voice retry-parity session yet, because parent-row durability is the cleaner foundation for trustworthy ordinary-media recovery
- the explicit send-serialization session could still proceed independently, but it should remain lower priority than closing the media durability gap
- the overall group-discussion reliability program remains incomplete on the most user-visible “send media, lock phone, recover on resume” path
