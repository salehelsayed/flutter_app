# Session 25 Plan: Add Failed Group Ordinary Media Retry Parity After Upload Success

## 1. real scope

Close the next high-value reliability gap from `18-group-discussion-reliability-audit.md`: if an ordinary group media message uploads successfully but the later publish step fails, retry should resend the message from its persisted attachments instead of skipping it as “unsupported.”

Concrete repo evidence already narrows the scope:
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart` currently retries only text-only failed rows.
- The current helper `_isTextOnlyRetryPayload(...)` explicitly rejects rows whose persisted retry payload or wire envelope still contains media metadata.
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` currently locks that behavior in with `skips rows that still carry media retry metadata`.
- `retryFailedGroupMessages(...)` does not currently receive a `MediaAttachmentRepository`, and failed `GroupMessage` loads do not hydrate attachment rows automatically, so completed attachments are not actually available in this path yet.
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` already provides the lower-layer durable upload-retry substrate:
  - it reuploads only `upload_pending` group attachments,
  - preserves already-`done` attachments,
  - then resends the full message once the attachment set is complete.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` now gives ordinary group media the needed producer-side durability substrate:
  - it pre-persists the parent row before ordinary media upload
  - it persists `upload_pending` attachment rows before upload
  - it persists completed ordinary-media attachment rows before the final `sendGroupMessage(...)` call
- `test/features/groups/presentation/group_conversation_wired_test.dart` already proves the parent-row durability contract directly for ordinary media.
- Current repo evidence does **not** support voice publish-failure parity in this same session:
  - the voice path pre-persists an `upload_pending` row before upload
  - then builds the completed attachment in memory and passes it to `sendGroupMessage(...)`
  - but does not persist a `done` attachment row before publish failure can happen
  - `sendGroupMessage(...)` persists attachments on success / `successNoPeers`, not on publish-failure return
  - so voice publish-failure retry remains blocked on a producer-side durability gap outside the minimum Session 25 fix

In scope:
- add the missing failed-send ordinary-media retry regression first
- extend `retryFailedGroupMessages(...)` so it can resend messages with persisted `done` attachments loaded from `MediaAttachmentRepository`
- preserve the existing split of responsibilities:
  - `retryIncompleteGroupUploads(...)` still owns unfinished uploads
  - `retryFailedGroupMessages(...)` owns failed resend once attachments are already complete
- add only the minimal dependency threading needed to supply that attachment repo to the retry path
- reuse the original `messageId` and `timestamp` so the existing row is updated in place
- add a direct regression that protects the new `lib/main.dart` dependency threading seam
- keep the fix local to group retry behavior, not a new outbox/job framework

Out of scope:
- changing upload ordering or persistence in the group composer
- voice publish-failure retry parity
- changing the voice sender path to persist completed attachments before publish failure
- adding per-thread send serialization
- changing lifecycle / resume ordering unless a minimal compatibility adjustment is unavoidable
- adding read receipts, ACK protocols, or broader delivery semantics
- broad announcement auth / writer-enforcement work
- changing group message repository loading to eagerly hydrate attachments everywhere when a targeted attachment lookup is sufficient

## 2. session classification

`implementation-ready`

Why:
- after narrowing to ordinary media, the gap is concrete and local to the failed-group-message retry path
- the lower-layer attachment retry substrate already exists
- the repo already has direct tests for both failed retry and incomplete upload recovery
- the only extra plumbing is a small compatibility wiring adjustment because the failed-message retry use case does not currently have attachment-repo access
- this is a narrow correctness/hardening change, not a profiling or evidence-only session
- voice parity is not implementation-ready in the current repo without first closing its producer-side completed-attachment durability gap

## 3. files and repos to inspect next

Primary planning / rationale docs:
- `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/09-network-group-messaging.md`

Primary code:
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/main.dart`

Primary tests:
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart` as the concrete Session 24 foundation evidence
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
  - use the same style of direct source-wiring guard for the new `retryFailedGroupMessages(...)` dependency threading seam
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - it already contains a direct `retryFailedGroupMessages(...)` caller that will need the new dependency if the signature changes
  - it remains the best place for an optional gate-level ordinary-media parity regression if direct coverage alone feels too narrow

Gate / regression references:
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh transport` only if the fix touches lifecycle / resume / recovery wiring

Execution note:
- `./scripts/run_test_gates.sh` remains the execution source of truth for named gate membership.
- `Test-Flight-Improv/test-gate-definitions.md` is still the planning reference for gate membership and documented known failures, but its known-failure ledger must be revalidated against the current repo before being treated as authoritative.
- At least one listed baseline known-failure note is stale:
  - it cites `integration_test/loading_states_smoke_test.dart:288`
  - the current file no longer instantiates `StartupRouter`, so that exact note should not be assumed to still explain a red baseline run
- `Test-Flight-Improv/14-regression-test-strategy.md` remains the policy/rationale reference for why this session adds the regression first and then runs direct suite + gates.
- `Test-Flight-Improv/test-gates-reference.md` is not required for Session 25 because it does not add anything essential beyond the frozen gate definitions.

## 4. existing tests covering this area

Already present and relevant:
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  - proves text-only failed rows are retried in place
  - proves rows with media retry metadata are currently skipped
  - proves retry continues after a per-message publish error
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - proves unfinished group uploads are retried from durable pending rows
  - proves the full message is resent once uploads are complete
  - proves 1:1 upload-pending rows are skipped in the group retry flow
- `test/features/groups/application/send_group_message_use_case_test.dart`
  - proves the core group send contract and result semantics
  - proves media/voice send semantics, push-body behavior, and provided `messageId` / `timestamp` reuse
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  - proves ordinary media now pre-persists the parent row before upload
  - proves the Session 24 durability foundation is already present in the repo for ordinary media
  - also shows that voice currently pre-persists `upload_pending` state, but not a publish-failure-ready completed attachment row
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - provides broader group recovery coverage at the gate/integration layer
  - already proves failed retry after recovery for text, but not for ordinary-media publish-failure parity

What is missing:
- no direct regression currently proves that a failed group message with persisted completed ordinary-media attachments is retried successfully after those attachments are loaded from `MediaAttachmentRepository`
- no direct regression currently proves the wire-envelope-only failed ordinary-media case:
  - `inboxRetryPayload` cleared because inbox store already succeeded
  - `wireEnvelope` still present
  - completed ordinary-media attachments still allow resend
- no direct regression currently pins the intended split of responsibility:
  - `upload_pending` rows still belong to `retryIncompleteGroupUploads(...)`
  - completed-attachment resend belongs to `retryFailedGroupMessages(...)`
- no direct regression currently protects the new `lib/main.dart` dependency threading seam for `retryFailedGroupMessages(...)`
- no current `groups` gate test proves ordinary-media publish-failure retry parity end-to-end; the existing retry acceptance in `group_resume_recovery_test.dart` is text-only
- no current direct regression proves voice publish-failure parity because the current producer path does not yet persist completed voice attachments before publish failure

## 5. regression/tests to add first, if any

Yes. Add the deterministic regression first in `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`.

Because the production fix requires attachment-row access, the direct test should also be wired to an in-memory `MediaAttachmentRepository`.

Minimum first regression:
- failed outgoing group row has ordinary-media retry metadata
- prefer the wire-envelope-only variant (`inboxStored == true`, `inboxRetryPayload == null`) so the regression matches the existing publish-failed / inbox-succeeded contract rather than only the easier payload-present case
- matching completed (`downloadStatus == 'done'`) attachment rows already exist for that message
- retry resends the message in place instead of skipping it
- original `messageId` and `timestamp` are preserved
- final row becomes `sent` or `pending` according to the existing send contract

Required companion regression:
- if attachments for that failed row are still `upload_pending`, the failed-message retry path must continue to skip them so `retryIncompleteGroupUploads(...)` remains the owner of unfinished uploads

Required wiring regression:
- add or extend a small direct lifecycle/source test that proves `lib/main.dart` threads `widget.mediaAttachmentRepository` into `retryFailedGroupMessages(...)`
- keep this in the same lightweight style already used by `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`

Do not add a voice retry regression in Session 25:
- current repo evidence shows voice publish-failure rows do not yet have persisted completed attachments to reload
- that is a producer-side prerequisite, not a retry-use-case-only fix

Do not start with a new integration harness unless the deterministic use-case tests fail to capture the behavior cleanly.

Optional but high-value:
- if `test/features/groups/integration/group_resume_recovery_test.dart` is already touched for the new dependency, add one narrow ordinary-media publish-failure retry case there so the named `groups` gate directly protects the new parity instead of only acting as a broad safety net

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Not required. This session is not profile-gated or evidence-gated.

The repo evidence is already enough to proceed:
- failed message retry currently rejects media rows by design
- incomplete upload recovery already knows how to rebuild the attachment set and resend
- current repo code already gives ordinary group media the completed-attachment durability needed for a retry-only fix
- current repo code does **not** yet give voice publish-failure the same completed-attachment durability, so voice stays out of Session 25 scope
- known-failure assumptions for named gates still need revalidation before they are used as pass/fail explanations

## 7. step-by-step implementation or evidence-collection plan

1. Re-open `retry_failed_group_messages_use_case.dart` and confirm the current skip logic.
   - identify exactly where `_isTextOnlyRetryPayload(...)` rejects media rows
   - confirm that the use case does not currently have attachment-repo access, so completed attachments are not available unless Session 25 adds that dependency
2. Re-open `retry_incomplete_group_uploads_use_case.dart` and extract the minimal reusable resend contract.
   - keep its responsibility boundary intact
   - do not merge the two retry paths into one bigger retry engine
3. Add the failing regression first in `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`.
   - wire the test to an in-memory attachment repo because the production fix depends on that seam
   - prefer the wire-envelope-only failed-row variant so the regression covers the inbox-success contract too
   - use an ordinary-media row, not voice
   - prove completed ordinary-media attachments now allow resend
   - prove `upload_pending` still stays out of this path
   - do not add a voice retry case in this session
4. Add or extend the lightweight direct wiring regression for `lib/main.dart`.
   - prove `retryFailedGroupMessages(...)` now receives `widget.mediaAttachmentRepository`
   - keep the test in the same style as the existing resume upload wiring guard
5. Implement the smallest safe production change in `retry_failed_group_messages_use_case.dart`.
   - add `mediaAttachmentRepo`
   - load persisted attachments for the failed message
   - if the attachment set is complete (`done`), resend through `sendGroupMessage(...)` with `mediaAttachments:`
   - if the attachment set still contains unfinished uploads, continue to skip and let `retryIncompleteGroupUploads(...)` own that message
   - preserve the current per-message error handling and continue-on-error behavior
   - do not change group-message repository hydration shape when a targeted attachment lookup is enough
6. Thread the new dependency through existing callers with the smallest possible surface.
   - `lib/main.dart`
   - any direct test/integration callers such as `test/features/groups/integration/group_resume_recovery_test.dart`
   - touch lifecycle code only if a tiny compatibility note/comment update is unavoidable
7. Keep the retry ownership split explicit:
   - `retryIncompleteGroupUploads(...)` handles unfinished upload recovery
   - `retryFailedGroupMessages(...)` handles publish failure once attachments are already complete
8. Re-run the direct tests.
9. Run the Group Messaging Gate.
10. Run the Baseline Gate.
11. Run the Startup / Transport Gate only if execution unexpectedly changes lifecycle / resume / recovery wiring beyond local parameter threading in `lib/main.dart`.
12. Interpret gate outcomes against the currently documented known failures in `Test-Flight-Improv/test-gate-definitions.md`.
    - revalidate any claimed "known failure" against the current repo state before treating it as pre-existing
    - a pre-existing red `baseline` or `transport` item should not be treated as a Session 25 regression unless the changed code clearly caused or widened it
    - do not rely on stale ledger notes such as the old `loading_states_smoke_test.dart` / `StartupRouter` baseline explanation without checking the current files first

## 8. risks and edge cases

- Do not collapse the clean ownership boundary between failed-send retry and incomplete-upload retry.
- Do not attempt to resend media from `retryFailedGroupMessages(...)` if the attachments are still `upload_pending` or otherwise incomplete.
- Do not require a new generic retry job framework.
- Do not break text-only retry behavior while extending the use case for attachments.
- Do not assume `GroupMessage.media` is hydrated on failed-row loads; fetch persisted attachments through `MediaAttachmentRepository`.
- Do not require `inboxRetryPayload` to be present; publish-failed rows can keep `wireEnvelope` while clearing `inboxRetryPayload` after inbox success.
- Do not lose the original `messageId` / `timestamp` in the resend path.
- Do not accidentally duplicate attachments or rewrite completed attachment metadata incorrectly during retry.
- Do not widen the fix into eager attachment hydration in `GroupMessageRepository` when a targeted per-message lookup is enough.
- Do not widen the fix into group composer, lifecycle ordering, or send serialization work.
- Do not claim voice publish-failure parity from this session; current repo evidence shows the voice producer path does not yet persist completed attachments before publish failure.
- Do not forget the small `lib/main.dart` wiring regression; dependency threading without a direct guard can silently regress later.
- Do not misread a previously documented red named gate as a Session 25 failure if the failure is already listed under known failures in `Test-Flight-Improv/test-gate-definitions.md` and is unrelated to the changed files.
- Do not trust a documented known-failure note without checking that the cited file and failure shape still match the current repo.

## 9. exact tests to run after implementation, if code changes occur

Direct tests:
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test test/core/lifecycle/main_resume_group_upload_wiring_test.dart`

Optional nearby integration safety net:
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart`
  - run this if its direct `retryFailedGroupMessages(...)` caller is touched for signature compatibility
  - also run it if Session 25 adds the optional gate-level ordinary-media retry acceptance case

## 10. subsystem gate(s), if relevant

Required:
- Group Messaging Gate
  - `./scripts/run_test_gates.sh groups`

Not required by default:
- Startup / Transport Gate
  - only if the implementation changes lifecycle, pause/resume, startup, or recovery orchestration rather than only the failed-message retry seam plus local dependency threading

## 11. whether Baseline Gate is required

Yes, if production code changes land in `retry_failed_group_messages_use_case.dart` or closely related group retry paths.

Command:
- `./scripts/run_test_gates.sh baseline`

Interpretation note:
- use `./scripts/run_test_gates.sh` as the canonical gate-membership source
- evaluate any red result against the known-failure ledger in `Test-Flight-Improv/test-gate-definitions.md`, but revalidate the claimed failure against the current repo before relying on that note
- at least one baseline ledger note is stale (`integration_test/loading_states_smoke_test.dart` no longer matches the cited `StartupRouter` failure location), so do not assume the baseline gate is red for the previously documented reason without checking
- only treat it as a Session 25 regression if the changed scope clearly introduced or widened the failure
- do not require unconditional green while unrelated known failures remain documented in the gate ledger

## 12. whether Startup / Transport Gate is required

No, not by default.

Run it only if the implementation changes:
- pause / resume wiring
- startup / recovery ordering
- device-backed recovery orchestration
- bridge / transport behavior beyond the local failed-message retry seam
- or the dependency threading grows beyond a local `lib/main.dart` callback update and starts changing resume orchestration semantics

Command when needed:
- `./scripts/run_test_gates.sh transport`

Interpretation note:
- if `transport` is run, use the same known-failure rule from `Test-Flight-Improv/test-gate-definitions.md`
- revalidate any documented transport failure against current repo state before treating it as pre-existing
- do not reopen unrelated existing transport-gate failures as part of Session 25 unless the retry-parity fix clearly affects them

## 13. done criteria

Session 25 is done when all of the following are true:
- a failed-send ordinary-media retry regression was added first
- the direct regression loads persisted attachment rows through `MediaAttachmentRepository`
- at least one regression covers the wire-envelope-only failed-row case if `inboxRetryPayload` was cleared after inbox success
- `retryFailedGroupMessages(...)` no longer skips messages whose attachments are already fully persisted and complete
- the minimal caller threading is in place so production and direct test callers can supply the attachment repo
- a direct lightweight regression protects the new `lib/main.dart` retry-callsite wiring seam
- the resend uses the original message identity (`messageId`, `timestamp`) and updates the row in place
- the responsibility boundary stays clean:
  - completed attachments can be resent here
  - unfinished uploads still belong to `retryIncompleteGroupUploads(...)`
- text-only retry behavior still works
- the direct tests pass
- `test/features/groups/integration/group_resume_recovery_test.dart` passes if it was edited for signature compatibility or expanded with the optional ordinary-media retry case
- the Group Messaging Gate passes
- the Baseline Gate passes, or any red result is confirmed to be an unrelated currently reproducible known failure rather than a stale ledger note
- the Startup / Transport Gate passes if execution touched that layer

## 14. dependency impact on later sessions if this session blocks

If Session 25 blocks:
- do not start the explicit sequential-send session yet if the remaining blocker is still in the core ordinary-media retry trust path
- the biggest remaining gap in group reliability stays visible to users as “upload finished, but failed publish did not come back on retry”
- unresolved retry-callsite compatibility or stale gate assumptions should be cleared before treating the session as blocked on a deeper architecture problem
- the next determinism step is still useful, but the core trust path for ordinary group media would remain weaker than 1:1 until this gap is closed
