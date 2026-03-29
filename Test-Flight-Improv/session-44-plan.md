# Session 44 Plan — Terminalize Abandoned Media Sends And Add Message-Scoped Retry/Delete Primitives

## real scope

What changes in this session:

- add the narrow persistence contract that later cancel/delete UI can call
  safely:
  - a shared attachment-repository/database helper that atomically marks one
    message's `upload_pending` attachment rows as `upload_failed`
  - the missing 1:1 single-message delete path in the message repository /
    DB helper stack
- add message-scoped retry primitives for failed media messages so one user
  action can retry exactly one 1:1 or group row instead of running the entire
  global retry sweep
- harden `retryIncompleteUploads(...)` and
  `retryIncompleteGroupUploads(...)` so a message deleted or terminalized while
  a retry is already uploading cannot still fall through into a late final
  send
- add safe file-cleanup helpers only for app-owned durable pending-upload data;
  cleanup must not delete arbitrary absolute source/gallery paths just because
  they were persisted on a failed row
- wire any new repository constructor callbacks in `lib/main.dart` and update
  test fakes that implement the touched interfaces

What does not change in this session:

- no conversation, group, or announcement UI buttons yet; those belong to
  later sessions in this breakdown
- no new message-status model such as a separate `cancelled` state; this
  session stays inside the existing `failed` / `upload_failed` contract
- no global retrier ordering changes in `handleAppResumed` or
  `PendingMessageRetrier` unless repo evidence forces a callback-shape change
- no schema broadening for attachment ownership markers or transport metadata
- no automatic deletion of arbitrary recorder/gallery/source files without a
  proved app-owned path contract
- no named-gate expansion or closure-doc refresh beyond this plan file

## closure bar

Session `44` is sufficient when all of the following are true:

- the repo exposes one message-scoped terminalization primitive for pending
  attachments and one 1:1 single-message delete primitive
- the repo exposes message-scoped retry entry points for failed media rows in
  both 1:1 and group flows without changing the behavior of the existing global
  retriers
- incomplete-upload retriers re-check the parent row / attachment contract
  before the final send and bail out cleanly when the message was deleted or
  terminalized mid-retry
- file cleanup is explicitly limited to app-owned durable pending-upload data,
  with tests proving arbitrary stored source paths are left alone
- direct tests pin the new per-message contract and current global retry
  behavior still passes
- later UI sessions can call these primitives without re-implementing retry,
  delete, or cleanup policy inside screens

## source of truth

Authoritative sources for this session:

- controlling scope/order artifact:
  `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- proposal under review:
  `Test-Flight-Improv/24-cancel-media-upload.md`
- regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- named gate policy:
  `Test-Flight-Improv/test-gate-definitions.md`
- current production seams:
  `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
  `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
  `lib/core/database/helpers/media_attachments_db_helpers.dart`
  `lib/features/conversation/domain/repositories/message_repository.dart`
  `lib/features/conversation/domain/repositories/message_repository_impl.dart`
  `lib/core/database/helpers/messages_db_helpers.dart`
  `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
  `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
  `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  `lib/core/media/media_file_manager.dart`
  `lib/main.dart`
- current direct tests:
  `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  `test/features/conversation/application/retry_failed_messages_media_test.dart`
  `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
  `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
  `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`

Conflict rules:

- the session breakdown controls scope, ordering, and the classification unless
  current repo evidence proves it stale
- current code and tests beat stale proposal prose on disagreement
- `Test-Flight-Improv/test-gate-definitions.md` defines the named gates, but
  `scripts/run_test_gates.sh` wins if the doc and script ever disagree
- current repo evidence already proves one proposal assumption stale:
  marking attachments `upload_failed` is not by itself sufficient, because the
  incomplete-upload retriers currently save uploaded attachments and then call
  the final send without a pre-send revalidation step

## session classification

`implementation-ready`

## exact problem statement

Current repo evidence shows four missing seams:

- `MediaAttachmentRepository` only exposes global
  `getUploadPendingAttachments()` and per-row status updates; it does not have
  a one-message terminalization primitive for `upload_pending` rows
- the 1:1 `MessageRepository` only deletes by contact, not by message ID,
  while the group message repository already has single-row deletion
- `retryFailedMessages(...)` and `retryFailedGroupMessages(...)` only operate
  over all failed rows; there is no message-scoped retry entry point for a
  single failed media bubble
- `retryIncompleteUploads(...)` and
  `retryIncompleteGroupUploads(...)` upload attachments and then immediately
  call the final send; if a user terminalizes or deletes the row during that
  retry, current code has no final ownership/status re-check to stop a late
  send

User-visible behavior that must improve through this session's underlying
contract:

- later UI can retry or delete one failed media message without kicking the
  whole retrier pipeline
- later UI can terminalize a row and trust that background retry code will not
  resurrect it

Behavior that must stay unchanged in this session:

- current background retry ordering and existing retry limits
- current honest status model for failed media messages
- current split between 1:1 and group send pipelines
- current policy that only app-owned durable files are auto-cleaned

## files and repos to inspect next

Production files:

- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/features/conversation/domain/repositories/message_repository.dart`
- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- `lib/core/database/helpers/messages_db_helpers.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/core/media/media_file_manager.dart`
- `lib/main.dart`

Direct tests from the breakdown:

- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_media_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
- `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
- `test/shared/fakes/fake_media_file_manager.dart`
- `test/core/media/media_file_manager_test.dart`

Known compile-fallout files if the abstract repository interfaces grow:

- `test/shared/fakes/in_memory_media_attachment_repository.dart`
- `test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart`
- `test/features/conversation/domain/repositories/fake_media_attachment_repository.dart`
- `test/features/conversation/application/load_conversation_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_media_hydration_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/features/conversation/application/retry_failed_messages_media_test.dart`
- `test/features/conversation/application/send_voice_message_use_case_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/integration/media_retry_smoke_test.dart`
- `test/core/resilience/c4_partial_drain_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart`
- `test/features/conversation/domain/repositories/fake_message_repository.dart`
- `test/features/contacts/application/delete_contact_use_case_test.dart`
- `test/features/conversation/application/send_voice_message_no_bg_task_test.dart`
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/send_chat_message_no_bg_task_test.dart`
- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `test/features/feed/application/load_feed_use_case_test.dart`
- `test/features/orbit/application/load_orbit_data_use_case_test.dart`

## existing tests covering this area

Covered today:

- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  already pins the global 1:1 incomplete-upload contract:
  per-message grouping, retry-count transitions, terminal `upload_failed`
  after exhaustion, and one final send after all uploads succeed
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  covers the analogous group retry flow, including skipping 1:1 rows,
  preserving done attachments, and terminalizing after max retries
- `test/features/conversation/application/retry_failed_messages_media_test.dart`
  covers failed-message media-aware retry, including done attachments, mixed
  attachment states, and the current global failed-message sweep
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  covers failed group retry support and the current skip behavior for
  incomplete media rows
- `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
  covers per-message attachment load/delete-all behavior and the global
  `upload_pending` query
- `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
  covers message save/load/update flows, but not single-row deletion
- `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
  pins the resume ordering:
  recover stuck -> retry incomplete upload -> retry failed -> retry unacked

Missing today:

- no direct test for atomically marking one message's `upload_pending`
  attachments as `upload_failed`
- no direct test or production API for deleting one 1:1 message by ID
- no message-scoped retry entry point for one failed media row in 1:1 or groups
- no direct regression proving incomplete-upload retriers abort when the user
  terminalizes or deletes the row after uploads started but before the final
  send
- no cleanup test proving arbitrary stored source paths are preserved while
  app-owned pending-upload files are removable

Current tests that pin intentional behavior:

- global retriers still own the all-rows sweep and existing retry ordering
- group delete already exists at the repository boundary; the 1:1 repository is
  the architectural gap
- named gates already cover shared 1:1 and group messaging regressions; this
  session should reuse them rather than widen them

## regression/tests to add first

Add these proofs before production changes broaden:

- one repository test in
  `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
  that seeds mixed attachments across messages, invokes the new message-scoped
  terminalization primitive, and proves only that message's
  `upload_pending` rows flip to `upload_failed`
- one repository test in
  `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
  that deletes a single 1:1 message by ID and leaves neighboring rows intact
- one 1:1 incomplete-upload regression in
  `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  that deletes or terminalizes the message after upload work starts and proves
  the final send is skipped
- one group incomplete-upload regression in
  `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  that proves the same late-send guard for group rows
- one message-scoped retry regression in
  `test/features/conversation/application/retry_failed_messages_media_test.dart`
  proving a targeted retry only touches the requested failed row
- one group message-scoped retry regression in
  `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  proving the targeted path only retries the requested row
- one file-cleanup regression using `test/shared/fakes/fake_media_file_manager.dart`
  and `test/core/media/media_file_manager_test.dart`, proving only
  `pending_uploads/<messageId>/...` data is eligible for cleanup

Why these prove the seam:

- the repository tests pin the new persistence primitives directly
- the incomplete-upload tests catch the specific race the proposal missed
- the targeted retry tests prove later UI can retry one row without re-running
  the whole failed-message sweep
- the cleanup test enforces the data-safety rule instead of leaving it to UI
  callers

## step-by-step implementation plan

1. Add the new repository-contract tests first.
   Start with message-scoped attachment terminalization and 1:1 single-message
   deletion so the persistence seam is pinned before any retry refactor.
2. Extend the 1:1 repository / DB helper stack with the smallest new APIs:
   one single-message delete path and one message-scoped pending-attachment
   terminalization path.
3. Extend `MediaAttachmentRepositoryImpl`, `MessageRepositoryImpl`,
   `lib/main.dart`, and the interface-implementing test fakes so the new
   primitives compile everywhere without changing unrelated behavior.
4. Add narrow message-scoped retry helpers for 1:1 and group failed-media rows.
   Prefer a small helper extracted inside the current use-case files or a thin
   targeted wrapper; do not create a new orchestration layer.
5. Reuse that helper from the existing global retry functions only if doing so
   keeps the current behavior identical and reduces duplication. Stop if the
   refactor starts widening into unrelated retry policy changes.
6. Add the late-send abort guard to both incomplete-upload retriers.
   After upload completion and before the final send, re-read the parent row
   and attachment state; skip the send if the message no longer exists or if
   the message's attachment set proves the user terminalized the row.
7. Add the narrow cleanup helper in `MediaFileManager`.
   Limit automatic cleanup to app-owned pending-upload storage for the target
   message; do not delete arbitrary absolute paths.
8. Run the direct repository/use-case tests.
   Stop if they show the repo already covers a claimed gap or if the late-send
   guard needs a different persistence signal than the breakdown assumed.
9. Run the named gates required by the touched surfaces.
   Keep `transport` out unless the implementation spills into lifecycle or
   retrier ordering code.

## risks and edge cases

- a user can delete or terminalize the row after some attachments were already
  re-uploaded to `done`; the late-send guard must detect the abandoned message
  from current message/attachment state instead of assuming "all uploads
  succeeded" still means "send now"
- the shared `media_attachments` table contains both 1:1 and group rows, so
  new per-message helpers must stay explicit about which parent message
  repository owns the row instead of inventing new ownership metadata
- adding abstract repository methods will break many test fakes unless the
  compile-fallout files are updated in the same session
- cleanup is safety-sensitive because attachment `localPath` can be an arbitrary
  persisted absolute path; only app-owned namespaces should be deleted
- deleting the 1:1 message row before Session `45` UI exists should not require
  inventing a new repository change-stream delete event

## exact tests and gates to run

Direct tests:

- `flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- `flutter test test/features/conversation/domain/repositories/message_repository_impl_test.dart`
- `flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `flutter test test/features/conversation/application/retry_failed_messages_media_test.dart`
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/core/media/media_file_manager_test.dart`
- `flutter test test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
  only if callback shapes or resume wiring change

Named gates:

- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline` if `lib/main.dart` wiring changes
- `./scripts/run_test_gates.sh transport` only if the implementation changes
  `lib/core/services/pending_message_retrier.dart`,
  `lib/core/lifecycle/handle_app_resumed.dart`, or other lifecycle transport
  wiring

## known-failure interpretation

- no session-specific known failure for these exact direct suites was found in
  the inspected docs
- if a failure comes from untouched dirty-worktree files, treat it as
  pre-existing unless the stack trace points to a new repository method
  signature or the new retry/delete logic
- do not drop a direct test or named gate just to keep the run green; follow
  `Test-Flight-Improv/test-gate-definitions.md` and document any real pre-
  existing red instead

## done criteria

- one-message attachment terminalization exists and is covered by direct tests
- 1:1 single-message delete exists and is covered by direct tests
- 1:1 and group message-scoped retry primitives exist and are covered by direct
  tests
- incomplete-upload retriers provably skip the final send when the row was
  deleted or terminalized mid-retry
- cleanup only touches app-owned pending-upload storage
- required direct suites pass, and the required named gates pass for the final
  touched surface set

## scope guard

- do not wire banner buttons, failed-bubble actions, or conversation-screen UI
  in this session
- do not invent a new cancellation state machine or message tombstone model
- do not expand cleanup into generic file-deletion heuristics for arbitrary
  local paths
- do not refactor `PendingMessageRetrier` ordering unless the helper contract
  cannot be implemented without it
- do not widen this into announcement UI or other product-scope parity work;
  keep the session at the repo / retry seam

## accepted differences / intentionally out of scope

- group single-message deletion already exists in the current architecture; the
  missing delete primitive is the 1:1 gap only
- later UI sessions may still need to decide how screens refresh after a delete;
  Session `44` only provides the underlying persistence/retry primitives
- unless implementation-time evidence proves a recorder-owned path namespace in
  the touched files, automatic cleanup should stay limited to
  `pending_uploads/<messageId>/...`
- the shared attachment table remains owner-agnostic; this session should not
  add a new schema field just to distinguish 1:1 from groups

## dependency impact

- Session `45` depends directly on this contract for 1:1 cancel and failed-
  media controls
- Session `46` should reuse the same per-message retry/terminalization seams
  for group and announcement parity instead of duplicating logic in UI code
- if this session discovers the late-send guard needs a different persistence
  signal, Session `45` and Session `46` should pause and replan before wiring
  controls
