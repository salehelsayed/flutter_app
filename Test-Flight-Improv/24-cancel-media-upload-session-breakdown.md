# 24 - Cancel Media Upload Session Breakdown

## Decomposition artifact updated

- Artifact path: `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- Proposal/source doc path: `Test-Flight-Improv/24-cancel-media-upload.md`
- Session `47` status: `accepted`; this artifact is the stable closure-owner
  record for Report `24`, and future work should reopen only on real
  regressions.
- Report `35` later reopened one narrow 1:1 late-boundary video-cancel seam
  and reclosed it in its own doc-scoped Session `1` without changing the
  broader accepted program state recorded here.
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Final program acceptance verdict

- Final program state: `closed`
- Program-level verdict: the combined Sessions `44` through `47` rollout meets
  the overall closure bar for Report `24`
- Why:
  - user-controlled cancel is landed for active 1:1 and group media uploads,
    with the accepted honest limits preserved:
    next-safe-boundary cancel for 1:1 and batch-bounded cancel for groups
  - cancelled or deleted failed media rows no longer remain in the
    resume-time `upload_pending` retry path
  - failed media retry now acts on the same row instead of creating a duplicate
    optimistic row
  - cleanup remains data-safe and bounded to targeted failed rows plus
    app-owned durable pending-upload files
  - the stable 1:1, group, and announcement maintenance docs now match the
    landed behavior without widening scope into transport-abort or background-
    upload claims
- Acceptance evidence:
  - Sessions `44`, `45`, `46`, and `47` are all accepted in the session ledger
  - Session `47` reran the named gates and direct suites for the rollout, with
    baseline validated on this multi-device machine via
    `FLUTTER_DEVICE_ID=macos`
  - Report `35` later added the missing direct 1:1 proof for cancel-before-
    failure-resolve and late-boundary final-send suppression without reopening
    group parity, retry ownership, or status-model scope
  - `transport` and `completeness-check` were correctly left out because the
    accepted rollout did not widen into lifecycle/startup/device-recovery
    changes or gate-definition changes
- Residual-only outcome for this rollout:
  - none beyond the pre-existing residual-only items already documented in the
    stable messaging closure references
- Still-open implementation items for this rollout:
  - none
- Accepted differences preserved at program level:
  - no mid-stream transport abort was introduced
  - no new `cancelled` status model was introduced
  - delete cleanup remains bounded and does not remove arbitrary stored
    gallery/source files
  - the rollout remains foreground-only rather than broadening into a
    background-upload architecture
  - the later Report `35` follow-up stayed a narrow 1:1 regression reopen
    rather than turning back into a new cross-surface cancelable-upload
    program

## Recommended plan count

- `4`

## Overall closure bar

This proposal is closed only when the current repo supports user-controlled
abandon/retry behavior for media sends without reopening status-model or
background-upload scope:

- users can stop an active 1:1 or group media upload from the live conversation
  surface, with honest foreground-only behavior when the bridge upload already
  in flight cannot be interrupted mid-stream
- a cancelled or deleted failed media message no longer silently re-enters the
  resume-time `upload_pending` retry loop
- users can retry the exact failed media message row instead of creating a new
  duplicate optimistic row
- message deletion and retry-control behavior stay data-safe:
  app-owned durable pending-upload files may be cleaned up, but arbitrary
  gallery/source files are not deleted just because their paths were stored for
  retry
- 1:1, group, and announcement maintenance docs match the landed behavior,
  including the current foreground-upload protection promise and the named gate
  expectations for future changes

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/24-cancel-media-upload.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/17-roadmap-closure-audit.md`

Current-code and current-test reality checks that govern the split:

- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
- `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/core/services/pending_message_retrier.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/conversation/domain/repositories/message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/core/database/helpers/messages_db_helpers.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/core/media/media_file_manager.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_media_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
- `test/core/device/upload_wake_lock_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`

Source-of-truth conflicts that materially affected the split:

- current code beats proposal prose where they disagree:
  `group_conversation_wired.dart` still has upload progress tracking and
  leave-guard behavior without a user-facing cancel control or
  message-scoped retry/delete affordance; the 1:1 half of this split is now
  accepted in Session `45`
- current code beats stale closure prose where they disagree:
  `19-1to1-message-reliability-closure-reference.md` and
  `20-group-discussion-reliability-closure-reference.md` already mention wake
  lock lifetime lasting until uploads are "cancelled"; Session `45` now makes
  that true for 1:1, while the stable closure refs remain deferred to Session
  `47`
- current code beats optimistic cleanup claims:
  ordinary 1:1 optimistic media rows store original local paths via
  `_persistOptimisticAttachments(...)`; they are not all app-owned
  `pending_uploads/...` files, so "delete failed message" cannot safely mean
  "delete any local path recorded on the row"
- current retry ownership matters:
  `retryIncompleteUploads(...)` and `retryIncompleteGroupUploads(...)` own
  `upload_pending` rows, while `retryFailedMessages(...)` and
  `retryFailedGroupMessages(...)` own already-failed rows. A user-visible
  "Retry this failed media message now" control therefore needs message-scoped
  retry plumbing, not just a new button that calls the existing global sweep

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Execution verdict | Closure docs touched | Blocker note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `44` | Terminalize abandoned media sends and add message-scoped retry/delete primitives | `implementation-ready` | `Test-Flight-Improv/session-44-plan.md` | none | `accepted` | `accepted` | live breakdown refreshed; stable closure docs still deferred to Session `47` | none |
| `45` | `1:1 cancel active uploads and expose failed-media controls` | `implementation-ready` | `Test-Flight-Improv/session-45-plan.md` | `44` | `accepted` | `accepted after one bounded fix loop` | live breakdown refreshed; stable closure docs still deferred to Session `47` | none |
| `46` | `Group and announcement parity for cancel and failed-media controls` | `implementation-ready` | `Test-Flight-Improv/session-46-plan.md` | `45` | `accepted` | `accepted after one bounded fix loop` | live breakdown refreshed; stable closure docs still deferred to Session `47` | none |
| `47` | `Cross-slice acceptance and closure refresh for cancelable uploads` | `closure-only` | `Test-Flight-Improv/session-47-plan.md` | `45`, `46` | `accepted` | `accepted` | `19`, `20`, live breakdown, `00`, `17`; `21` and gate definitions intentionally unchanged | none |

## Ordered session breakdown

### Session 44

- Title: Terminalize abandoned media sends and add message-scoped retry/delete primitives
- Session id: `44`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/session-44-plan.md`
- Exact scope:
  land the underlying per-message control contract before wiring new buttons
  into the conversation surfaces
- Exact scope:
  add the shared repository/database helper to atomically mark one message's
  `upload_pending` attachments as `upload_failed`, and add the missing 1:1
  single-message delete path needed by the proposal's delete action
- Exact scope:
  add message-scoped retry primitives for failed media rows so a user action
  can retry exactly one message instead of kicking the entire global retrier
  pipeline
- Exact scope:
  harden the incomplete-upload retriers so a row that the user terminalized or
  deleted mid-retry cannot still fall through into a late final send
- Exact scope:
  keep cleanup data-safe:
  only app-owned durable pending-upload or recorder-owned files may be cleaned
  up automatically; do not delete arbitrary gallery/source files just because
  their path is stored on a failed 1:1 attachment row
- Why it is its own session:
  this is the retry/persistence contract seam.
  The proposal's UI controls are unsafe without it because current code has no
  1:1 single-row delete API, no message-scoped retry entry point, and no
  re-check before the final send in the incomplete-upload retriers
- Likely code-entry files:
  `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- Likely code-entry files:
  `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- Likely code-entry files:
  `lib/core/database/helpers/media_attachments_db_helpers.dart`
- Likely code-entry files:
  `lib/features/conversation/domain/repositories/message_repository.dart`
- Likely code-entry files:
  `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- Likely code-entry files:
  `lib/core/database/helpers/messages_db_helpers.dart`
- Likely code-entry files:
  `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- Likely code-entry files:
  `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- Likely code-entry files:
  `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- Likely code-entry files:
  `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- Likely code-entry files:
  `lib/core/media/media_file_manager.dart`
- Likely code-entry files:
  `test/shared/fakes/fake_media_file_manager.dart`
- Likely direct tests/regressions:
  `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- Likely direct tests/regressions:
  `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/application/retry_failed_messages_media_test.dart`
- Likely direct tests/regressions:
  `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
- Likely direct tests/regressions:
  `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
- Likely direct tests/regressions:
  `test/core/services/pending_message_retrier_test.dart` only if the final
  design changes retrier orchestration rather than staying inside message-scoped
  helpers
- Likely named gates:
  `1to1`
- Likely named gates:
  `groups`
- Likely named gates:
  `baseline`
- Likely named gates:
  `transport` only if the final plan changes `handle_app_resumed.dart`,
  `pending_message_retrier.dart`, or device-backed media-recovery wiring rather
  than staying inside per-message retry/delete helpers
- Matrix/closure docs to update when done:
  defer stable closure-doc updates to Session `47`;
  Session `44` now stands as the accepted record for the retry/delete contract
  while the stable 1:1/group closure references remain deferred to Session
  `47`
- Dependency on earlier sessions:
  none

### Accepted differences / intentionally left unchanged

- Session `44` stops at the repo-level retry/delete and late-send guard
  contract; the 1:1 cancel affordance and screen wiring still belong to
  Session `45`.
- Cleanup stays limited to app-owned durable `pending_uploads/...` data.
  Arbitrary absolute source/gallery paths remain protected and are not deleted
  just because they were stored on the row.
- Stable messaging closure references are still deferred to Session `47`; this
  session only updates the live breakdown record for the landed primitives.

### Session 45

- Title: 1:1 cancel active uploads and expose failed-media controls
- Session id: `45`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/session-45-plan.md`
- Exact scope:
  wire an actual user-facing cancel path into the live 1:1 conversation upload
  flow using the Session `44` primitives
- Exact scope:
  add an optional cancel affordance to the shared
  `UploadProgressBanner` and wire `ConversationWired` so sequential uploads
  stop at the next safe boundary, restore the composer, mark the message as
  terminally failed, and release leave-guard / wake-lock state correctly
- Exact scope:
  expose retry/delete controls only for failed 1:1 messages whose persisted
  attachments still prove this is a media-upload recovery seam, not a generic
  text-message failure action
- Exact scope:
  keep the current honest status model and foreground-only upload architecture:
  do not introduce a new `cancelled` status or pretend the in-flight
  `bridge.send(...).timeout(...)` call is interruptible mid-stream
- Exact scope:
  solve the proposal's "remove / re-attach during upload" complaint by
  returning the composer to an editable state after cancel, not by widening the
  thumbnail strip into per-file mid-upload removal controls
- Why it is its own session:
  this is the 1:1 UI interaction and live-upload wiring seam.
  It has a different direct regression family from the retry primitives in
  Session `44`, and it can land in a fully verified 1:1 state without waiting
  on the group tree
- Likely code-entry files:
  `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
- Likely code-entry files:
  `lib/features/conversation/presentation/widgets/letter_card.dart`
- Likely code-entry files:
  `lib/features/conversation/presentation/screens/conversation_screen.dart`
- Likely code-entry files:
  `lib/features/conversation/presentation/screens/conversation_wired.dart`
- Likely code-entry files:
  `lib/l10n/app_en.arb`
- Likely code-entry files:
  `lib/l10n/app_de.arb`
- Likely code-entry files:
  `lib/l10n/app_ar.arb`
- Likely direct tests/regressions:
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/presentation/widgets/letter_card_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/presentation/widgets/upload_progress_banner_test.dart`
  if the shared banner has no existing dedicated direct suite
- Likely direct tests/regressions:
  `test/core/device/upload_wake_lock_test.dart`
- Likely named gates:
  `1to1`
- Likely named gates:
  `baseline`
- Likely named gates:
  `feed` only if the final implementation leaks into feed-owned 1:1 send entry
  points or shared feed conversation rendering rather than staying inside the
  conversation surface and shared widgets
- Matrix/closure docs to update when done:
  defer stable closure-doc refresh to Session `47`
- Dependency on earlier sessions:
  Session `44`

### Session 45 closure outcome

- Closure verdict: `accepted`
- Execution verdict: `accepted after one bounded fix loop`
- What landed:
  - the upload progress banner now exposes an optional cancel affordance
  - the 1:1 send loop cancels at the next safe boundary, restores the composer snapshot, terminalizes the optimistic row to `failed`, and releases upload-tracking state
  - failed outgoing 1:1 media rows now expose scoped retry/delete controls, while incoming rows and failed text-only rows do not
  - delete only targets the failed row and its app-owned pending-upload files
- Residual-only items:
  - none in the accepted 1:1 slice; group and announcement parity stay with Session `46`
- Still-open items:
  - Session `46` group and announcement parity
  - Session `47` stable closure-reference refresh
- Accepted differences:
  - no new `cancelled` status model was introduced; the existing `failed` / `upload_failed` contract remains the user-visible terminal state
  - banner and action labels stay as conversation-surface literals for this slice; no locale-file changes were required

### Session 46

- Title: Group and announcement parity for cancel and failed-media controls
- Session id: `46`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/session-46-plan.md`
- Exact scope:
  mirror the new upload-cancel and failed-media retry/delete controls into the
  group conversation tree after the 1:1 interaction contract is already landed
- Exact scope:
  keep the group-specific architectural truth:
  the current `Future.wait(...)` upload batch cannot cancel in-flight member
  uploads mid-stream, so the session must discard or terminalize results after
  the parallel batch resolves rather than inventing a new transport-cancel
  architecture
- Exact scope:
  preserve announcement behavior on top of the shared group surface:
  admin writers still send through the shared group pipeline, readers remain
  read-only, and the new controls do not create a separate announcement
  program
- Why it is its own session:
  this is a different UI tree, different send architecture, and different gate
  contract from Session `45`.
  Group uploads use parallel upload completion rules, and the shared-group
  change must be revalidated against announcement behavior
- Likely code-entry files:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely code-entry files:
  `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- Likely code-entry files:
  `lib/features/conversation/presentation/widgets/letter_card.dart` only if the
  Session `45` shared-action affordance needs a final group-safe refinement
- Likely code-entry files:
  `lib/l10n/app_en.arb`
- Likely code-entry files:
  `lib/l10n/app_de.arb`
- Likely code-entry files:
  `lib/l10n/app_ar.arb`
- Likely direct tests/regressions:
  `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely direct tests/regressions:
  `test/features/groups/presentation/group_conversation_screen_test.dart`
  if the group screen still lacks a direct suite for the new surface
- Likely direct tests/regressions:
  `test/features/groups/integration/announcement_happy_path_test.dart`
- Likely direct tests/regressions:
  rerun the Session `44` group retry direct suites if the final UI wiring needs
  a small helper patch in the group retry stack
- Likely named gates:
  `groups`
- Likely named gates:
  `baseline`
- Likely named gates:
  `transport` only if the session reopens resume/recovery wiring rather than
  staying in group surface and already-landed retry helpers
- Matrix/closure docs to update when done:
  defer stable closure-doc refresh to Session `47`;
  use the announcement closure reference as acceptance context, not as a reason
  to create an extra announcement-only implementation session
- Dependency on earlier sessions:
  Session `45`

### Session 46 closure outcome

- Closure verdict: `accepted`
- Execution verdict: `accepted after one bounded fix loop`
- What landed:
  - the group conversation screen now passes the shared upload-cancel affordance
    through the active upload banner
  - the group send flow cancels at the next safe boundary after the parallel
    batch resolves, restores the composer snapshot, terminalizes the optimistic
    row to `failed`, and marks owned attachments `upload_failed`
  - failed outgoing group media rows now expose scoped retry/delete controls,
    while incoming rows, text-only rows, and read-only announcement members do
    not
  - announcement admins keep the shared group behavior; no separate
    announcement send program or transport-level cancel was introduced
- Residual-only items:
  - plain `./scripts/run_test_gates.sh baseline` is environment-sensitive on
    this machine without an explicit `FLUTTER_DEVICE_ID`; the accepted
    verification used `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
- Still-open items:
  - Session `47` stable closure-reference refresh
- Accepted differences:
  - no new `cancelled` status model was introduced; the existing failed-state
    contract remains the user-visible terminal state
  - group cancel remains foreground-safe and batch-bounded; it does not
    interrupt in-flight member uploads mid-stream
  - announcement readers stay read-only; they do not gain hidden write-path
    affordances

### Session 47

- Title: Cross-slice acceptance and closure refresh for cancelable uploads
- Session id: `47`
- Session classification: `closure-only`
- Intended plan file: `Test-Flight-Improv/session-47-plan.md`
- Exact scope:
  run the whole-program acceptance pass after Sessions `44` through `46`, then
  update the stable reliability docs so they truthfully describe user-controlled
  upload cancellation and terminalized retry behavior
- Exact scope:
  update the existing closure references instead of inventing a new matrix doc:
  `19-1to1-message-reliability-closure-reference.md` and
  `20-group-discussion-reliability-closure-reference.md` are the stable closure
  owners for this work
- Exact scope:
  touch `21-announcement-reliability-closure-reference.md` only if the landed
  group behavior changes the explicit maintenance-time announcement promise;
  otherwise use it as an acceptance source of truth and leave the prose stable
- Exact scope:
  update `test-gate-definitions.md` only if new direct files need explicit
  classification or a named-gate note must mention the new cancel/delete
  recovery seam; run `./scripts/run_test_gates.sh completeness-check` when that
  happens
- Exact scope:
  refresh this breakdown artifact with final statuses and accepted differences
  after execution
- Why it is its own session:
  the current stable docs already overclaim cancellation in places, and one
  explicit closure owner is required so the landed code, tests, and
  maintenance-time prose converge after multiple implementation slices
- Likely code-entry files:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Likely code-entry files:
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Likely code-entry files:
  `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- Likely code-entry files:
  `Test-Flight-Improv/test-gate-definitions.md`
- Likely code-entry files:
  `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- Likely code-entry files:
  `Test-Flight-Improv/00-INDEX.md` only if the final closure pass needs folder
  reading-order or maintenance-state refresh
- Likely direct tests/regressions:
  rerun the exact direct suites changed in Sessions `44`, `45`, and `46`
- Likely direct tests/regressions:
  `test/features/groups/integration/announcement_happy_path_test.dart`
- Likely named gates:
  `1to1`
- Likely named gates:
  `groups`
- Likely named gates:
  `baseline`
- Likely named gates:
  `transport` only if any earlier session changed lifecycle/startup/resume or
  device-backed media-recovery wiring
- Likely named gates:
  `./scripts/run_test_gates.sh completeness-check` only if new tests or new
  gate-classification notes are added
- Matrix/closure docs to update when done:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Matrix/closure docs to update when done:
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Matrix/closure docs to update when done:
  `Test-Flight-Improv/21-announcement-reliability-closure-reference.md` only
  if the acceptance pass proves the explicit maintenance promise changed
- Matrix/closure docs to update when done:
  `Test-Flight-Improv/test-gate-definitions.md` only if new tests need frozen
  classification notes
- Matrix/closure docs to update when done:
  `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- Dependency on earlier sessions:
  Sessions `45` and `46`

### Session 47 closure outcome

- Closure verdict: `accepted`
- Execution verdict: `accepted`
- What landed:
  - `19-1to1-message-reliability-closure-reference.md` now records
    foreground-only next-safe-boundary cancel, same-row failed-media
    retry/delete, and app-owned pending-upload cleanup bounds
  - `20-group-discussion-reliability-closure-reference.md` now records
    batch-bounded group cancel, same-row failed-media retry/delete, and the
    shared announcement-reader read-only bounds
  - `21-announcement-reliability-closure-reference.md` stays unchanged because
    its existing maintenance promise still holds: announcements remain an
    acceptance layer on top of shared group send/retry/recovery, admin writers
    inherit the shared controls, and readers stay read-only
  - `00-INDEX.md` and `17-roadmap-closure-audit.md` now reflect Report `24`
    and Sessions `44` through `47` as historical closure artifacts instead of
    leaving that slice implied or backlog-shaped
- Completeness-check decision:
  - `not required`; Session `47` did not edit
    `Test-Flight-Improv/test-gate-definitions.md`, add new test files, or
    reclassify existing tests
- Residual-only items:
  - none beyond the existing residuals already documented in the stable 1:1
    and group closure references
- Still-open items:
  - none in the accepted cancelable-upload rollout; reopen only on a real
    regression
- Accepted differences:
  - no mid-stream transport cancel was introduced; 1:1 remains
    next-safe-boundary and group remains batch-bounded after the current
    parallel upload batch resolves
  - no new `cancelled` status model was introduced; the existing `failed` /
    `upload_failed` contract remains the user-visible terminal state
  - delete remains limited to targeted failed rows plus app-owned durable
    pending-upload files; arbitrary source/gallery paths stay protected
  - `transport` and `completeness-check` were intentionally not rerun because
    the accepted evidence did not widen into
    lifecycle/startup/resume/device-backed recovery changes or
    gate-definition changes

## Why this is not fewer sessions

- One session would be unsafe because the proposal spans three different core
  seams:
  persistence/retry ownership, 1:1 live-upload UI, and group/announcement
  parity. Those seams have different direct-test families and different gate
  expectations.
- A two-session split would still be too coarse:
  the group tree uses parallel upload completion and must be revalidated
  against announcement behavior, while the 1:1 tree has the missing
  single-message delete contract and a different optimistic-attachment storage
  reality.
- Folding closure work into the implementation sessions would leave the current
  stale closure prose unresolved. The repo already has a doc/code mismatch on
  cancellation language, so explicit closure ownership is required.

## Why this is not more sessions

- Splitting Session `44` into separate "DB helper", "message delete", and
  "retry race guard" sessions would leave unsafe half-states where the UI could
  surface delete/cancel while late retry sends are still possible.
- Splitting Session `45` into separate "cancel banner" and "failed-message
  retry/delete UI" sessions would be bookkeeping noise. Both are the same 1:1
  conversation-surface control slice, use the same direct presentation tests,
  and ride the same `1to1` gate contract.
- Splitting Session `46` into separate "group" and "announcement" sessions
  would overstate the architecture. Announcements are an acceptance layer on
  top of shared group reliability, not a separate upload-control subsystem.

## Regression and gate contract

- `Test-Flight-Improv/14-regression-test-strategy.md` applies normally:
  each implementation session should add or update the direct regression first
  for its exact seam before broader gate runs.
- Session `44` is primarily direct-suite heavy:
  repository/use-case regressions first, then `./scripts/run_test_gates.sh 1to1`,
  `./scripts/run_test_gates.sh groups`, and `./scripts/run_test_gates.sh baseline`.
- Session `45` should run the exact 1:1 presentation/use-case direct suites
  first, then `./scripts/run_test_gates.sh 1to1`, then
  `./scripts/run_test_gates.sh baseline`.
- Session `46` should run the exact group presentation direct suites plus
  `test/features/groups/integration/announcement_happy_path_test.dart`, then
  `./scripts/run_test_gates.sh groups`, then
  `./scripts/run_test_gates.sh baseline`.
- `./scripts/run_test_gates.sh transport` is conditional across the whole set:
  run it only if an implementation session changes lifecycle/startup/resume,
  reconnect, `handle_app_resumed.dart`, `pending_message_retrier.dart`, or
  device-backed media-recovery wiring rather than staying inside repo helpers,
  upload controls, and conversation/group surface logic.
- `./scripts/run_test_gates.sh feed` is not part of the default contract for
  this proposal.
  Add it only if the final implementation leaks into feed-owned 1:1 send
  entry points or shared feed conversation rendering.
- If any new test files are added or reclassified, Session `47` owns the
  required `./scripts/run_test_gates.sh completeness-check` pass and any needed
  `test-gate-definitions.md` note updates.

## Matrix update contract

- Do not invent a new upload-cancel matrix doc.
- Session `47` is the closure owner for the stable maintenance docs:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Use `Test-Flight-Improv/21-announcement-reliability-closure-reference.md` as
  an acceptance/closure companion because shared group changes must not regress
  announcement behavior; only update it if the explicit announcement
  maintenance promise actually changes.
- Update `Test-Flight-Improv/test-gate-definitions.md` only if the rollout adds
  new direct files or a frozen classification note needs to mention the new
  cancel/delete recovery seam.
- Refresh `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md` in
  Session `47` so the final statuses and accepted differences are preserved for
  later maintenance.

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- no mid-stream transport cancel:
  `bridge.send(...).timeout(...)` remains non-interruptible once a single file
  upload is already in flight; cancel works at the next safe boundary for 1:1
  and after `Future.wait(...)` resolution for groups
- no new `cancelled` status model by default:
  reuse the existing honest failed-state contract unless a later planning pass
  proves a separate status is required and worth the blast radius
- no blanket deletion of arbitrary local source files:
  cleanup should stay limited to app-owned durable pending-upload directories or
  recorder-owned artifacts, not gallery originals referenced by stored paths
- no per-thumbnail mid-upload remove action:
  the proposal's user need is satisfied by cancelling the batch and restoring
  the composer to an editable state
- no background-upload expansion:
  this remains foreground-only upload protection plus user-controlled terminal
  failure, not a new background job architecture

## Exact docs/files used as evidence

- `Test-Flight-Improv/24-cancel-media-upload.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/17-roadmap-closure-audit.md`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
- `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/core/services/pending_message_retrier.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/conversation/domain/repositories/message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/core/database/helpers/messages_db_helpers.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/core/media/media_file_manager.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_media_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
- `test/core/device/upload_wake_lock_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- the split isolates the real blocker first:
  Session `44` makes the retry/delete contract safe before any new buttons can
  surface it
- each later session ends in a meaningful verified state:
  1:1 can land independently, then group/announcement parity can land without
  reopening the 1:1 tree
- the current stable closure docs already exist for this area, so the rollout
  has a clear closure owner and does not need a new matrix document
- no unresolved structural blocker remains:
  the proposal is implementation-ready once the data-safety and retry-ownership
  differences above are respected during planning

## Downstream execution path

- Session `44` should next go through:
  `$implementation-plan-orchestrator`
  `$implementation-execution-qa-orchestrator`
  `$implementation-closure-audit-orchestrator`
- Session `45` should next go through:
  `$implementation-plan-orchestrator`
  `$implementation-execution-qa-orchestrator`
  `$implementation-closure-audit-orchestrator`
- Session `46` should next go through:
  `$implementation-plan-orchestrator`
  `$implementation-execution-qa-orchestrator`
  `$implementation-closure-audit-orchestrator`
- Session `47` should next go through:
  `$implementation-plan-orchestrator`
  `$implementation-execution-qa-orchestrator`
  `$implementation-closure-audit-orchestrator`
