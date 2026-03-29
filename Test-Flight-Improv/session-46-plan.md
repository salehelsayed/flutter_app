# Session 46 Plan — Group And Announcement Parity For Cancel And Failed-Media Controls

## real scope

What changes in this session:

- wire the already-landed shared cancel / failed-media affordances into the
  group conversation surface:
  - pass the shared `UploadProgressBanner.onCancel` callback through
    `GroupConversationScreen`
  - pass failed-media retry/delete callbacks through the shared `LetterCard`
    usage in `GroupConversationScreen`
- add group-wired state and handlers for:
  - cancelling an active group media upload batch without inventing mid-stream
    transport cancellation
  - retrying one failed outgoing group media row in place via the existing
    `retryFailedGroupMessage(...)` use case
  - deleting one failed outgoing group media row and its app-owned pending
    upload files without touching neighbors
- keep announcement behavior on the same shared group tree:
  - announcement admins use the same group send / failed-media controls
  - announcement readers remain read-only and do not gain hidden write-path
    actions
- add the direct presentation and acceptance regressions that pin this parity
  slice

What does not change in this session:

- no reopening of 1:1 behavior from Sessions `44` and `45`
- no closure-doc or matrix refresh; that stays Session `47`
- no new message status such as `cancelled`
- no transport-level attempt to interrupt in-flight upload RPCs
- no rewrite of group retry orchestration, resume policy, or background
  recovery architecture
- no widening into generic failed-text retry/delete actions
- no announcement-only screen or separate announcement send program
- no localization sweep unless current repo evidence disproves the existing
  shared literal style
- no voice-only parity expansion unless current group media wiring proves voice
  already rides the exact same seam

## closure bar

Session `46` is sufficient when all of the following are true:

- a writable group or announcement-admin conversation that exposes the active
  upload banner can also surface the shared cancel affordance
- cancel in the group media path does not require interrupting in-flight
  uploads; instead the session marks the batch cancelled, lets the current
  parallel upload set resolve, then restores the composer, marks the optimistic
  row `failed`, and terminalizes owned `upload_pending` attachments to
  `upload_failed`
- failed outgoing group rows with persisted media attachments expose retry and
  delete controls, while incoming rows, text-only failed rows, and read-only
  announcement readers do not
- retry acts on the existing failed group row via
  `retryFailedGroupMessage(...)`, not by creating a new optimistic row
- delete only removes the targeted failed row, clears its attachment rows, and
  only deletes app-owned pending-upload files for that row
- announcement admins retain the shared group behavior, and announcement
  readers remain unable to send or invoke hidden write-path affordances
- direct regressions cover the group surface and announcement acceptance seam,
  and the required named gates still pass

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
- script source of truth for named gate commands:
  `scripts/run_test_gates.sh`
- current shared affordance files:
  `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
  `lib/features/conversation/presentation/widgets/letter_card.dart`
- current group production seams:
  `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
  `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
  `lib/core/media/media_file_manager.dart`
- current direct tests and acceptance seams:
  `test/features/groups/presentation/group_conversation_screen_test.dart`
  `test/features/groups/presentation/group_conversation_wired_test.dart`
  `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  `test/features/groups/integration/announcement_happy_path_test.dart`

Conflict rules:

- the session breakdown controls scope and order unless current repo evidence
  proves it stale
- current code and tests beat stale proposal prose
- `scripts/run_test_gates.sh` wins if it ever diverges from
  `Test-Flight-Improv/test-gate-definitions.md`

Current repo evidence already proves these breakdown/proposal assumptions stale
or narrower than they first appeared:

- shared cancel and failed-media UI affordances already exist in
  `UploadProgressBanner` and `LetterCard`; Session `46` should wire them into
  groups, not redesign them
- the repo already has a targeted retry primitive for groups:
  `retryFailedGroupMessage(...)`
- the repo already has shared attachment terminalization and cleanup seams:
  `markUploadPendingAttachmentsFailedForMessage(...)`,
  `deleteAttachmentsForMessage(...)`, and
  `deleteOwnedPendingUploadFilesForMessage(...)`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
  already exists, so Session `46` does not need to create a brand-new screen
  suite from scratch
- the proposal’s `app_*.arb` changes are not required by current shared widget
  evidence unless implementation chooses to reject the existing literal style

## session classification

`implementation-ready`

## exact problem statement

Current repo evidence shows Session `46` is partially covered but still missing
the user-facing group parity:

- shared widgets already expose the cancel button and failed-media action
  buttons
- group retry infrastructure already supports retrying one failed media row in
  place
- announcement read-only gating already exists through `_canWrite`
- but `GroupConversationScreen` does not currently accept or pass the new
  cancel / retry / delete callbacks
- and `GroupConversationWired` does not currently maintain a cancellable active
  upload state or failed-media row handlers comparable to the landed 1:1 path

User-visible behavior that must improve:

- writable group conversations and announcement-admin conversations must expose
  the same cancel and failed-media recovery affordances already present on the
  shared 1:1 surface
- read-only announcement members must remain read-only, including for the new
  controls

Behavior that must stay unchanged:

- group uploads still use the current batch architecture; no mid-stream upload
  interruption is claimed
- the user-visible terminal state remains `failed` plus attachment
  `upload_failed`
- failed text-only rows do not gain retry/delete controls
- Session `47` still owns stable closure-doc refresh

## files and repos to inspect next

Production files:

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart` only if the
  shared failed-media action conditions need a group-safe refinement
- `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
  only if the shared cancel affordance contract needs a small adjustment
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/core/media/media_file_manager.dart`

Direct tests:

- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart` only
  if Session `46` must refine the shared widget itself

## existing tests covering this area

Already covered today:

- `test/features/groups/presentation/group_conversation_wired_test.dart`
  already proves:
  - group media uploads pre-persist `upload_pending` rows and use the current
    parallel durable path
  - failed media upload restores the composer and keeps durable rows retryable
  - ordinary relay-tracked group uploads show the progress banner, hold the
    wake lock, and guard back navigation while active
  - announcement readers are read-only and cannot keep hidden quote or voice
    write-state
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  already proves `retryFailedGroupMessage(...)` only retries the targeted
  failed media row
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  already proves the late-send guard suppresses the final group send when the
  parent row disappears after uploads complete, which is the same safety seam
  delete/cancel must continue to respect
- `test/features/groups/presentation/group_conversation_screen_test.dart`
  already proves the announcement read-only banner and message-list rendering
- `test/features/groups/integration/announcement_happy_path_test.dart`
  already proves the announcement admin send + reader read-only + reaction
  acceptance path

Already partially implemented in production:

- `GroupConversationWired` already persists durable pending attachments,
  restores the composer on failure, and enforces announcement reader
  read-only behavior
- `GroupConversationScreen` already renders the shared `UploadProgressBanner`
  and shared `LetterCard`

Missing today:

- no group screen props or wiring for `onCancelUpload`,
  `onRetryFailedMedia`, or `onDeleteFailedMedia`
- no group wired cancel state equivalent to the landed 1:1
  `_activeAttachmentUpload`
- no group wired handlers that connect failed-media row actions to the existing
  retry/delete helpers
- no direct announcement acceptance asserting the new controls remain bounded
  to writers/admins after the parity wiring lands

## regression/tests to add first

Add these regressions before or alongside the first production edits:

- `test/features/groups/presentation/group_conversation_screen_test.dart`
  should pin the screen contract:
  - the upload banner renders the shared cancel affordance only when the
    callback is supplied
  - failed outgoing rows with media attachments show retry/delete controls
  - incoming rows, failed text-only rows, and read-only announcement readers do
    not show those controls
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  should pin the group cancel path:
  - cancel during an active group upload restores the composer snapshot
  - the optimistic row becomes `failed`
  - persisted `upload_pending` rows are terminalized to `upload_failed`
  - the banner disappears, the wake lock is released, and the final publish is
    skipped
  - for the parallel durable path, already-running uploads are allowed to
    finish, but their results are discarded once cancellation is observed
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  should pin failed-media row actions:
  - retry targets only the requested failed row through
    `retryFailedGroupMessage(...)`
  - delete removes only the targeted failed row, clears its attachment rows,
    and only deletes owned pending-upload files for that row
- `test/features/groups/integration/announcement_happy_path_test.dart` should
  add or tighten one acceptance assertion proving:
  - announcement admins retain the shared failed-media controls when they own a
    failed media row
  - announcement readers remain read-only and do not surface those controls
- only add or edit `test/features/conversation/presentation/widgets/letter_card_test.dart`
  if shared-widget conditions must change; do not duplicate 1:1 coverage

## step-by-step implementation plan

1. Tighten the group screen contract first.
   Add explicit `onCancelUpload`, `onRetryFailedMedia`, and
   `onDeleteFailedMedia` props to `GroupConversationScreen`, then mirror the
   same failed-media visibility logic already used on the 1:1 screen.

2. Add the group-wired failed-media row handlers.
   Reuse `retryFailedGroupMessage(...)` for retry, and reuse the existing media
   repository plus file-manager cleanup primitives for delete. Refresh the
   touched row from stored attachments after retry so hydrated media stays
   correct after status changes.

3. Add group active-upload cancellation state without inventing new transport
   behavior.
   Mirror the 1:1 controller shape only as far as group needs it: track one
   active group upload batch, surface a cancel request, and stop before the
   final `sendGroupMessage(...)` / `group:publish` once cancellation is
   observed.

4. Apply the cancel path separately to the two current group upload branches.
   For the sequential ordinary fallback branch, follow the landed 1:1 safe
   boundary checks. For the durable parallel branch, record cancellation and
   discard results after the `Future.wait(...)` batch resolves; do not attempt
   to interrupt in-flight uploads.

5. Keep cleanup bounded to the targeted message.
   On cancel or delete, mark that message’s `upload_pending` attachments
   `upload_failed`, clear only that message’s attachment rows as needed, and
   delete only app-owned pending-upload files for that message.

6. Revalidate announcement parity on the shared group surface.
   Ensure admin writers can still send and use the same failed-media recovery
   path, while members remain read-only and never receive hidden write-path
   callbacks.

7. Stop if implementation evidence disproves remaining work.
   If, during implementation, the current repo already wires one of these
   parity seams correctly, do not broaden the session; trim the remaining work
   to only the missing parity or acceptance gap.

## risks and edge cases

- the durable group upload path is parallel, so cancellation can only take
  effect after the already-started upload futures settle
- cancel during a single-file or last-file batch must still suppress the final
  `sendGroupMessage(...)`
- delete or cancel must not affect neighboring failed rows or active uploads
- attachment hydration after retry/delete must not regress reopened group
  conversations into empty media lists
- read-only announcement members must not regain hidden callbacks through screen
  props even if the shared card now supports failed-media actions
- wake-lock release and back-navigation guards must still balance correctly on
  cancel and on ordinary failure

## exact tests and gates to run

Required direct tests:

- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- `flutter test test/features/groups/integration/announcement_happy_path_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`

Conditional direct suites if touched by the final implementation:

- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`

Do not run `transport` unless Session `46` unexpectedly changes resume,
bridge-upload event plumbing, or other transport-gate files.

## known-failure interpretation

- `Test-Flight-Improv/test-gate-definitions.md` documents no accepted known-red
  failures for the Session `46` target suites or the `groups` / `baseline`
  gates
- treat any new failure in the required direct suites or named gates as a real
  regression unless it reproduces on the untouched pre-Session-46 state
- because the repo is already dirty, unrelated failures outside the touched
  Session `46` files are not automatic scope for this session; capture them,
  compare to current HEAD behavior, and only fix them if the Session `46`
  change caused them

## done criteria

- group and announcement-admin conversations expose the shared cancel and
  failed-media recovery controls where appropriate
- read-only announcement members still cannot send and do not surface the new
  controls
- cancel leaves the affected row terminally failed, restores the composer, and
  prevents later auto-retry for that row’s pending attachments
- retry/delete act only on the targeted failed media row
- the required direct suites and named gates pass
- no additional scope is taken on 1:1 behavior, transport architecture, or
  closure-doc refresh

## scope guard

- do not broaden this session into a shared upload-progress event-system
  rewrite just to perfect byte-accurate progress for parallel uploads
- do not add new message states, retry taxonomies, or announcement-only
  presentation branches
- do not reopen 1:1 message/media controls, stable closure docs, or generic
  failed-text actions
- do not turn a parity session into a transport-cancel architecture session

## accepted differences / intentionally out of scope

- group cancellation still cannot interrupt uploads already in flight; it only
  suppresses publish/finalization after the safe boundary
- if parallel upload progress remains best-effort under the existing shared
  progress event model, that is acceptable for Session `46`; perfect aggregate
  byte tracking is not required for closure
- announcement readers remain read-only; parity applies to the admin writer
  path because announcements intentionally reuse the shared group pipeline
- voice-specific cancel parity remains out of scope unless the final code path
  is proven to be the exact same media seam touched here

## dependency impact

- Session `47` depends on this plan’s final implemented scope and test evidence
  to refresh the stable closure docs without overstating transport or 1:1
  changes
- if Session `46` ends up narrower than expected, Session `47` should only
  document the landed group/announcement parity, not infer broader media-send
  architecture changes
- if implementation unexpectedly uncovers a real blocker in shared progress or
  transport plumbing, stop and re-plan rather than quietly expanding Session
  `46`

## Final verdict

`implementation-ready`

## Final plan

- keep Session `46` narrow: group/announcement surface parity only
- reuse the already-landed shared widgets and existing group retry/delete
  primitives
- add the missing group screen and wired callbacks, then pin them with direct
  group presentation tests plus the announcement acceptance suite
- run `groups` and `baseline` after the direct suites

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- only touch `letter_card.dart` or `upload_progress_banner.dart` if the group
  parity wiring exposes a shared-widget gap
- do not add `app_*.arb` work unless current implementation evidence proves the
  existing shared literal pattern is no longer acceptable
- do not widen into transport-gate work unless Session `46` unexpectedly
  touches transport files

## Accepted differences intentionally left unchanged

- no mid-stream transport cancel for already-running group uploads
- no new `cancelled` message state
- no announcement-only implementation branch for the same shared controls
- no voice-path expansion beyond the exact media parity seam landed here

## Exact docs/files used as evidence

- `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- `Test-Flight-Improv/24-cancel-media-upload.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/core/media/media_file_manager.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`

## Why the plan is safe or unsafe to implement now

Safe to implement now because the remaining gap is concrete and bounded:
shared affordances and group retry/delete primitives already exist, the current
group and announcement code paths clearly show the missing wiring points, and
the direct tests/gates needed to prove parity are explicit. No structural gap
remains that would require reopening 1:1 behavior, transport architecture, or
closure-doc work.
