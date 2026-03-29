# Session 45 Plan — 1:1 Cancel Active Uploads And Expose Failed-Media Controls

## real scope

What changes in this session:

- finish the 1:1 UI slice that Session `44` intentionally left open:
  - add an optional cancel affordance to the shared
    `UploadProgressBanner`
  - thread that affordance through
    `ConversationScreen` -> `ConversationWired`
  - wire cancel for the live 1:1 attachment-upload batch so the batch stops at
    the next safe boundary, restores the composer snapshot, marks the
    optimistic row terminally failed via the existing `failed` /
    `upload_failed` contract, and releases upload-tracking state cleanly
- expose retry/delete controls only for outgoing failed 1:1 rows that still
  have persisted media attachments, so the control stays scoped to media-upload
  recovery rather than generic text-message failure
- reuse landed Session `44` primitives instead of inventing new persistence or
  retry contracts:
  - `retryFailedMessage(...)`
  - `markUploadPendingAttachmentsFailedForMessage(...)`
  - `deleteMessage(...)`
  - `deleteOwnedPendingUploadFilesForMessage(...)`
  - `deleteAttachmentsForMessage(...)`
- add the direct widget / wired regressions that pin the cancel path, failed
  media controls, and targeted cleanup behavior

What does not change in this session:

- no group or announcement parity; that remains Session `46`
- no closure-doc refresh or matrix updates beyond this plan file; that remains
  Session `47`
- no new message status such as `cancelled`
- no claim that `bridge.send(...).timeout(...)` is interruptible mid-stream
- no rewrite of `PendingMessageRetrier`, resume ordering, or background retry
  policy
- no widening into generic failed-text retry/delete actions
- no separate voice-upload cancel flow; the voice send path remains a distinct
  seam unless current code evidence forces convergence
- no stable-architecture cleanup of all repo-status/media hydration seams
  beyond what Session `45` needs for the touched 1:1 actions

## closure bar

Session `45` is sufficient when all of the following are true:

- a 1:1 attachment upload that currently shows the existing upload-progress
  banner also exposes a cancel path
- cancel during an active batch does not require interrupting the in-flight
  upload call; instead, once the current upload returns, the batch aborts
  before the next upload or before the final `sendChatMessage(...)`
- cancel restores the original draft / quote / attachments to the composer,
  marks the message row `failed`, terminalizes any persisted `upload_pending`
  attachment rows to `upload_failed`, hides the banner, and releases the
  leave-guard / wake-lock state
- failed outgoing 1:1 rows with persisted media attachments expose retry/delete
  controls, while failed text-only rows do not
- retry uses the existing single-message retry primitive instead of creating a
  second optimistic row
- delete removes only the targeted failed media row, clears its attachment DB
  rows, and only deletes app-owned pending-upload files for that message
- direct regressions cover the cancel path and failed-media actions, and the
  required named gates still pass

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
- current 1:1 production seams:
  `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
  `lib/features/conversation/presentation/widgets/letter_card.dart`
  `lib/features/conversation/presentation/screens/conversation_screen.dart`
  `lib/features/conversation/presentation/screens/conversation_wired.dart`
  `lib/features/conversation/application/load_conversation_use_case.dart`
  `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
  `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
  `lib/features/conversation/domain/repositories/message_repository.dart`
  `lib/core/database/helpers/media_attachments_db_helpers.dart`
  `lib/core/media/media_file_manager.dart`
- current direct tests and seam proofs:
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  `test/features/conversation/presentation/widgets/letter_card_test.dart`
  `test/features/conversation/application/retry_failed_messages_media_test.dart`
  `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  `test/features/conversation/application/load_conversation_use_case_test.dart`
  `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
  `test/core/media/media_file_manager_test.dart`
  `test/core/device/upload_wake_lock_test.dart`

Conflict rules:

- the session breakdown controls scope, order, and the target session unless
  current repo evidence proves it stale
- current code and tests beat stale proposal prose
- `Test-Flight-Improv/test-gate-definitions.md` defines the named gates, but
  `scripts/run_test_gates.sh` wins if the doc and script disagree

Current repo evidence already proves these proposal assumptions stale:

- the repository / DB primitives requested by the proposal are already landed
  in Session `44`; Session `45` should call them, not re-plan them
- a loop-start-only cancel check is not sufficient in current
  `ConversationWired`: if the user cancels during the only upload or the last
  upload in the batch, the code can still fall through into the final
  `sendChatMessage(...)` unless there is also a post-upload / pre-send abort
  check

## session classification

`implementation-ready`

## exact problem statement

Current repo evidence shows Session `45` is partially covered but still missing
the user-facing 1:1 controls:

- Session `44` already landed the safe backend seams:
  message-scoped retry, per-message upload terminalization, single-message
  delete, late-send abort in incomplete-upload recovery, and safe owned-file
  cleanup
- the 1:1 conversation surface already shows relay upload progress, acquires a
  wake lock, warns on back navigation, and restores the composer on upload
  failure
- but the user still cannot cancel a live 1:1 upload batch from the active
  banner
- and a failed outgoing 1:1 media row still has no scoped retry/delete
  controls, so the current visible recovery path is to tap send again from the
  restored composer, which creates a new optimistic row instead of acting on
  the failed row

User-visible behavior that must improve:

- when the tracked 1:1 upload banner is visible for a composer attachment
  batch, the user can cancel that batch and get back to an editable composer
- a failed outgoing 1:1 message with persisted media attachments exposes
  retry/delete controls on that failed row

Behavior that must stay unchanged:

- the app still uses `failed` plus attachment `upload_failed`, not a new
  `cancelled` state
- the currently in-flight upload call is still non-interruptible
- text-only failed messages do not gain these controls
- group / announcement UI remains unchanged in this session

## files and repos to inspect next

Production files:

- `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/application/load_conversation_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/message_repository.dart`
- `lib/core/media/media_file_manager.dart`

Direct tests:

- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/features/conversation/application/retry_failed_messages_media_test.dart`
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `test/features/conversation/application/load_conversation_use_case_test.dart`
- `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- `test/core/media/media_file_manager_test.dart`
- `test/core/device/upload_wake_lock_test.dart`

Only inspect localization files if implementation evidence forces new localized
strings instead of following the existing conversation-surface literal style:

- `lib/l10n/app_en.arb`
- `lib/l10n/app_de.arb`
- `lib/l10n/app_ar.arb`

## existing tests covering this area

Already covered today:

- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  already proves:
  - upload failure restores quote draft and attachments
  - relay upload progress renders and blocks leaving mid-upload
  - send failure after upload restores quote draft and attachments
- `test/features/conversation/application/retry_failed_messages_media_test.dart`
  already proves `retryFailedMessage(...)` only retries the targeted failed row
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  already proves late deletion suppresses the final resend during incomplete
  upload recovery
- `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
  already proves one message's `upload_pending` rows can be terminalized to
  `upload_failed` without touching neighbors
- `test/core/media/media_file_manager_test.dart` already proves owned
  pending-upload cleanup ignores arbitrary source/gallery paths
- `test/core/device/upload_wake_lock_test.dart` already proves the wake lock is
  ref-counted
- `test/features/conversation/application/load_conversation_use_case_test.dart`
  already proves persisted attachments are rehydrated into `message.media`
  across conversation loads

Already partially implemented in production:

- `ConversationWired` already persists optimistic attachments as
  `upload_pending`, tracks relay upload progress, and restores the composer on
  upload failure
- `ConversationScreen` already renders the banner and the shared message card
  list

Missing today:

- no cancel callback or cancel-button rendering on `UploadProgressBanner`
- no 1:1 screen-level rendering for failed-media retry/delete controls
- no wired cancel path from the active 1:1 upload banner into the current send
  loop
- no 1:1 failed-media retry/delete actions that act on the existing failed row
- no targeted refresh helper that guarantees a failed media row keeps hydrated
  attachments after status-only repo updates on a reopened conversation

## regression/tests to add first

Add these regressions before or alongside the first production edits:

- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  should pin the screen contract:
  - banner renders an optional cancel affordance only when the callback is
    supplied
  - failed outgoing messages with media attachments show retry/delete controls
  - incoming rows and failed text-only rows do not show those controls
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  should pin the active cancel path:
  - cancel during a tracked upload restores the composer snapshot
  - the message becomes `failed`
  - persisted `upload_pending` rows are terminalized to `upload_failed`
  - the banner disappears and the wake lock is released
  - the final send is skipped even when cancel happens during the only upload
    or the last upload in the batch
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  should pin failed-media actions:
  - retry acts on the targeted failed row without creating a second optimistic
    row
  - delete removes only the targeted failed row, clears its attachment rows,
    and only cleans owned pending-upload files
- add a dedicated
  `test/features/conversation/presentation/widgets/upload_progress_banner_test.dart`
  only if the screen-level banner assertions become brittle; do not create the
  extra suite by default

These regressions are sufficient because they directly prove the new UI
contract and the two user-facing recovery actions without reopening Session
`44`'s repository behavior.

## step-by-step implementation plan

1. Keep the scope pinned to 1:1 only and confirm the failed-media eligibility
   rule uses existing hydrated attachments rather than a new persistence flag.
   If current repo evidence ever shows reopened failed rows do not hydrate
   media, stop and patch the targeted refresh helper first instead of widening
   the product scope.
2. Extend `UploadProgressBanner` with an optional cancel callback and thread it
   through `ConversationScreen` so the banner stays reusable:
   no callback means current behavior; a callback means show the 1:1 cancel
   affordance.
3. In `ConversationWired`, add the smallest attachment-batch cancel state
   needed for the live 1:1 send flow:
   store the active optimistic message id, the composer snapshot to restore,
   and a cancel-request flag only while the attachment upload batch is in
   progress.
4. Patch the 1:1 upload loop with safe-boundary abort checks in both places
   that matter:
   - before starting another upload
   - after an upload returns and before the final `sendChatMessage(...)`
   On abort, call the landed Session `44` primitives, restore the composer,
   mark the message `failed`, stop upload tracking, and surface an "Upload
   cancelled" snackbar.
5. Add explicit failed-media controls to the message card / screen contract:
   only outgoing `failed` rows with hydrated media attachments get retry/delete
   callbacks. Do not overload long-press reaction UI for this.
6. Implement the 1:1 retry action by calling `retryFailedMessage(...)` with the
   existing repos/services plus `widget.uploadMediaFn` so tests reuse the same
   seam. After the retry completes, refresh only the touched message plus its
   attachments so the UI does not lose media on a status-only repo update.
7. Implement the 1:1 delete action in this order:
   - collect the row's stored attachment paths
   - terminalize any `upload_pending` rows for the message
   - delete only owned pending-upload files / dir for that message
   - delete the message's attachment rows
   - delete the message row
   - remove the row from local UI state
   This keeps cleanup safe for arbitrary source/gallery paths while still
   removing the failed recovery row.
8. Run the direct regressions first, then the required named gates. Stop if the
   new evidence shows the planned UI contract is already satisfied without a
   code change; do not widen into group parity or generic failed-message UX.

## risks and edge cases

- cancel during the only upload or final upload in a batch:
  if the code only checks the flag at loop start, the batch can still fall
  through into `sendChatMessage(...)`
- cancel during a currently in-flight upload:
  the upload itself is still non-interruptible, so the abort must happen after
  that call returns
- status-only repository updates for reopened rows:
  `loadConversation(...)` hydrates `message.media`, but later
  `MessageRepositoryChangeSource` emissions can be bare rows, so the touched
  message may need an explicit rehydrate after retry
- delete for failed rows with done attachments:
  attachment rows should be removed, but file cleanup must stay limited to
  app-owned pending-upload paths
- cancel must not leave wake-lock or pop-guard state stuck on
- delete must be scoped to one row only; adjacent failed media rows must remain
  retryable

## exact tests and gates to run

Direct tests:

- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
- `flutter test test/features/conversation/application/retry_failed_messages_media_test.dart`
- `flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- `flutter test test/core/media/media_file_manager_test.dart`
- `flutter test test/core/device/upload_wake_lock_test.dart`

Run this direct suite only if the implementation touches the reopened-row media
refresh seam:

- `flutter test test/features/conversation/application/load_conversation_use_case_test.dart`

Named gates required by scope:

- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh baseline`

Named gate not required unless the final implementation leaks into feed-owned
1:1 entry points or shared feed conversation rendering:

- `./scripts/run_test_gates.sh feed`

## known-failure interpretation

- no Session `45`-specific known failure is documented in the consulted scope
  docs
- treat new failures in the listed direct 1:1 tests as Session `45`
  regressions, not background noise
- if a named gate fails outside the touched 1:1 upload / message-card files,
  compare it against the current dirty worktree before attributing it to this
  session; do not silently drop a failing direct suite or gate from the plan

## done criteria

- the 1:1 upload-progress banner can expose cancel and that cancel path aborts
  at the next safe boundary without sending the failed row
- cancel restores the composer snapshot, marks the row `failed`, and leaves no
  retryable `upload_pending` rows for that message
- outgoing failed 1:1 rows with media attachments show retry/delete controls,
  while failed text-only rows do not
- retry acts on the existing failed row; delete removes only the targeted row
- direct tests and required named gates pass

## scope guard

- do not add group / announcement parity here
- do not add a new message status or global retry-policy rewrite
- do not broaden into generic failed-message actions for all failed text rows
- do not widen this session into a repository or localization cleanup unless
  the implementation is blocked without it
- do not change the transport truthfulness model by pretending uploads are
  mid-stream cancellable

## accepted differences / intentionally out of scope

- the cancel affordance is tied to the existing tracked upload banner; this
  session does not widen upload-progress instrumentation to every possible
  local-only media transfer path
- the shared banner may stay read-only for the separate 1:1 voice-upload path;
  Session `45` only commits to cancel for the composer attachment batch it is
  directly planning
- the proposal's request for new repository primitives is already satisfied by
  landed Session `44` code; Session `45` should consume those primitives, not
  re-implement them
- localization broadening is intentionally deferred unless the touched files
  already force it
- stable closure-reference refresh remains Session `47`

## dependency impact

- Session `46` depends on the shared banner / failed-media control contract that
  Session `45` lands for 1:1; it should mirror that contract for groups rather
  than inventing a second shape
- if Session `45` discovers the targeted media-refresh helper must be broader
  than one-message 1:1 refresh, stop and revisit the Session `46` assumption
  before copying the same pattern into groups
- Session `47` should not be started from stale decomposition prose; it should
  reference the landed `session-45-plan.md` decisions for what was intentionally
  deferred
