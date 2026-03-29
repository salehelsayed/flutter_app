# Session 47 Plan — Cross-Slice Acceptance And Closure Refresh For Cancelable Uploads

## real scope

What changes in this session:

- run the closure-owner acceptance pass for the cancelable-upload rollout that
  landed across Sessions `44`, `45`, and `46`
- refresh the stable maintenance docs so they match current repo behavior
  without overclaiming:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
    only if the acceptance pass proves its explicit maintenance promise changed
- refresh `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
  with the final accepted status, closure outcome, and accepted differences
- touch `Test-Flight-Improv/test-gate-definitions.md` only if the acceptance
  pass proves a new note or classification is actually required
- touch `Test-Flight-Improv/00-INDEX.md` or
  `Test-Flight-Improv/17-roadmap-closure-audit.md` only if the stable closure
  refresh would otherwise leave the folder reading order or maintenance state
  misleading

What does not change in this session:

- no reopening of upload implementation, retry plumbing, DB contracts, or UI
  wiring unless current repo evidence proves the docs would otherwise overclaim
- no new product-scope work such as background uploads, a new `cancelled`
  status model, or per-thumbnail mid-upload removal
- no default widening of named gates or new regression creation just because
  the closure docs were stale
- no new matrix document; the existing stable closure refs remain the closure
  owners

## closure bar

Session `47` is sufficient when all of the following are true:

- the stable 1:1 and group closure references accurately describe the landed
  cancelable-upload behavior:
  foreground-only protection, cancel at the next safe boundary, failed-row
  retry/delete controls, and no silent resume-time retry after user
  terminalization
- announcement closure prose is either confirmed still accurate as-is or
  updated narrowly if the shared group maintenance promise changed
- the breakdown artifact records Session `47` as the closure owner and preserves
  the final accepted differences instead of leaving them stranded in session
  plans
- the plan and resulting closure pass record an explicit completeness-check
  decision instead of leaving it implicit
- if current code/test evidence contradicts the intended closure claims, the
  session stops with a narrow correction decision rather than patching prose to
  hide the mismatch

## source of truth

Authoritative sources for this session:

- controlling scope/order artifact:
  `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- proposal/spec under closure:
  `Test-Flight-Improv/24-cancel-media-upload.md`
- regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- named gate and completeness policy:
  `Test-Flight-Improv/test-gate-definitions.md`
- stable closure owners:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- maintenance-state references only if the closure refresh needs them:
  `Test-Flight-Improv/00-INDEX.md`
  `Test-Flight-Improv/17-roadmap-closure-audit.md`
- current production evidence for what actually landed:
  `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
  `lib/features/conversation/presentation/screens/conversation_screen.dart`
  `lib/features/conversation/presentation/screens/conversation_wired.dart`
  `lib/features/conversation/presentation/widgets/letter_card.dart`
  `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
  `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
  `lib/features/conversation/domain/repositories/message_repository.dart`
  `lib/features/conversation/domain/repositories/message_repository_impl.dart`
  `lib/core/database/helpers/media_attachments_db_helpers.dart`
  `lib/core/media/media_file_manager.dart`
  `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
  `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- current direct proof suites for the landed seams:
  `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
  `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
  `test/core/media/media_file_manager_test.dart`
  `test/features/conversation/application/retry_failed_messages_media_test.dart`
  `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  `test/features/conversation/presentation/widgets/letter_card_test.dart`
  `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  `test/features/groups/presentation/group_conversation_screen_test.dart`
  `test/features/groups/presentation/group_conversation_wired_test.dart`
  `test/features/groups/integration/announcement_happy_path_test.dart`

Conflict rules:

- the breakdown controls Session `47` scope and closure ownership unless
  current repo evidence proves it stale
- current code and tests beat stale closure prose or optimistic proposal text
- `scripts/run_test_gates.sh` and `test-gate-definitions.md` define gate truth;
  the plan should not invent a new gate requirement without evidence
- if current repo evidence shows the docs would overclaim, stop and open a
  narrow correction decision instead of broadening Session `47`

## session classification

`acceptance-only`

## exact problem statement

Sessions `44`, `45`, and `46` are accepted in the live breakdown, and current
repo evidence now shows the cancelable-upload seams are present in code and
direct tests:

- the shared upload banner now has an optional cancel affordance
- the 1:1 and group screens thread cancel/retry/delete callbacks through the
  live conversation surfaces
- the wired layers expose message-scoped retry/delete handlers and terminalize
  pending attachments to `upload_failed`
- safe file cleanup is limited to owned pending-upload files
- announcement acceptance coverage still exists through the shared group tree

The remaining gap is closure accuracy, not feature implementation:

- the stable 1:1 and group closure docs still talk about upload protection in a
  way that predates the landed cancel/delete/retry controls
- Session `47` still needs to decide whether the announcement closure doc
  changes at all
- Session `47` still needs to decide whether `test-gate-definitions.md` or
  `completeness-check` need any action

User-visible behavior that must stay accurately represented:

- cancel does not interrupt an in-flight upload RPC mid-stream; it aborts at
  the next safe boundary
- the user-visible terminal state remains `failed` plus attachment
  `upload_failed`, not a new `cancelled` status
- retry acts on the same failed media row instead of creating a duplicate
  optimistic row
- delete only removes the targeted failed row and only deletes app-owned
  pending-upload files
- announcement readers remain read-only

## files and repos to inspect next

Closure and maintenance docs:

- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md` only if closure ownership or reading order
  becomes ambiguous
- `Test-Flight-Improv/17-roadmap-closure-audit.md` only if the closure refresh
  would otherwise contradict the folder’s documented maintenance state

Production evidence files:

- `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/features/conversation/domain/repositories/message_repository.dart`
- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/core/media/media_file_manager.dart`

Direct proof suites:

- `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
- `test/core/media/media_file_manager_test.dart`
- `test/features/conversation/application/retry_failed_messages_media_test.dart`
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`

## existing tests covering this area

Already covered by current repo evidence:

- `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
  proves message-scoped terminalization of `upload_pending` rows to
  `upload_failed`
- `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
  proves 1:1 single-message deletion exists
- `test/core/media/media_file_manager_test.dart` proves owned pending-upload
  cleanup does not delete arbitrary stored source paths
- `test/features/conversation/application/retry_failed_messages_media_test.dart`
  proves targeted retry of a failed 1:1 media row
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  proves late deletion/terminalization suppresses the final resend
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  and `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  prove the 1:1 cancel banner and failed-media controls
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
  proves the shared failed-media action rendering contract
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  and `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  prove the targeted group retry and late-send guard
- `test/features/groups/presentation/group_conversation_screen_test.dart`
  and `test/features/groups/presentation/group_conversation_wired_test.dart`
  prove group cancel/delete/retry parity and read-only bounds
- `test/features/groups/integration/announcement_happy_path_test.dart`
  proves announcement admin controls remain bounded to writers while readers
  stay read-only
- the named gates already cover the broader surrounding behavior:
  `baseline`, `1to1`, and `groups`

Completeness-check evidence:

- `Test-Flight-Improv/test-gate-definitions.md` records
  `./scripts/run_test_gates.sh completeness-check` green on `2026-03-29`
  with `580/580` classified files
- the current bounded repo evidence for Sessions `44` through `46` shows
  modified existing direct suites, but no new cancel-upload-specific
  `*_test.dart` files and no proven new gate classification requirement

What is missing today:

- the stable closure prose has not yet been refreshed to describe the landed
  cancelable-upload behavior
- the breakdown still shows Session `47` as pending
- the closure pass still needs to record whether announcement prose stays
  unchanged and whether `completeness-check` is actually required

## regression/tests to add first

None by default.

This session is closure-only. Current repo evidence already contains the direct
proofs needed for the landed cancelable-upload seams. If the acceptance pass
discovers a behavior that cannot be stated truthfully without adding a brand-new
regression, stop and reopen a narrow correction session instead of expanding
Session `47`.

## step-by-step implementation plan

1. Re-read the Session `47` breakdown slice, the stable closure refs, and the
   gate-definition policy before touching prose.
2. Confirm the landed 1:1 behavior from current code/tests:
   cancel affordance exists, cancel terminalizes pending attachments to
   `upload_failed`, same-row retry/delete controls exist, and owned-file
   cleanup stays bounded.
3. Confirm the landed group and announcement behavior from current code/tests:
   group parity exists, announcement admins inherit the shared group controls,
   and readers remain read-only.
4. Make the completeness-check decision before editing gate docs:
   with the current bounded evidence, no new cancel-upload test files were
   added and no new named-gate classification is proven necessary, so leave
   `test-gate-definitions.md` unchanged unless the closure prose would
   otherwise be ambiguous.
5. Update `19-1to1-message-reliability-closure-reference.md` to describe the
   landed cancelable-upload closure accurately:
   foreground-only protection, next-safe-boundary cancel, same-row retry/delete,
   and owned-file cleanup only.
6. Update `20-group-discussion-reliability-closure-reference.md` with the same
   truthful group/announcement-shared framing, while preserving the existing
   receipt-less architecture notes.
7. Inspect `21-announcement-reliability-closure-reference.md` and either:
   leave it unchanged with an explicit rationale if the existing maintenance
   promise already holds, or patch it narrowly if the shared group wording now
   changes what announcement maintenance must remember.
8. Refresh `24-cancel-media-upload-session-breakdown.md` with final accepted
   status, closure outcome, and the explicit completeness-check decision.
9. Update `00-INDEX.md` and `17-roadmap-closure-audit.md` only if the stable
   closure refresh would otherwise leave the folder’s maintenance-time reading
   order or open/closed state misleading.
10. Stop immediately if acceptance evidence shows a real code/doc mismatch that
    cannot be resolved by truthful closure prose alone; record the blocker and
    do not reopen implementation inside Session `47`.

## risks and edge cases

- overclaiming true cancellation instead of the actual next-safe-boundary
  foreground-only behavior
- implying a new `cancelled` status model when the repo still uses `failed`
  plus attachment `upload_failed`
- claiming failed-media controls for text-only failures when the landed seam is
  media-specific
- claiming arbitrary local gallery/source file deletion when cleanup is limited
  to app-owned pending-upload files
- implying announcement readers gained hidden write-path controls
- editing `test-gate-definitions.md` unnecessarily and forcing a
  `completeness-check` rerun that the bounded evidence does not require
- letting the dirty worktree tempt broad doc cleanup unrelated to the
  cancelable-upload closure slice

## exact tests and gates to run

Direct suites to rerun for acceptance:

- `flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- `flutter test test/features/conversation/domain/repositories/message_repository_impl_test.dart`
- `flutter test test/core/media/media_file_manager_test.dart`
- `flutter test test/features/conversation/application/retry_failed_messages_media_test.dart`
- `flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- `flutter test test/features/groups/integration/announcement_happy_path_test.dart`

Named gates for the closure pass:

- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`

Conditional gates only if evidence forces them:

- `./scripts/run_test_gates.sh completeness-check` only if Session `47`
  edits `Test-Flight-Improv/test-gate-definitions.md` or adds/reclassifies test
  files; current bounded evidence says this is not required by default
- `./scripts/run_test_gates.sh transport` only if the acceptance pass proves
  the cancelable-upload rollout actually changed lifecycle/startup/resume or
  device-backed media-recovery wiring beyond the already evidenced
  repo/use-case/UI seams

Device note:

- if multiple Flutter targets are attached for integration-backed gate runs,
  use `FLUTTER_DEVICE_ID=<device-id>` as documented in
  `Test-Flight-Improv/test-gate-definitions.md`

## known-failure interpretation

- treat `Test-Flight-Improv/test-gate-definitions.md` as the source of truth for
  known failures and current green gate history
- as of `2026-03-29`, `completeness-check`, `baseline`, `1to1`, and `groups`
  are recorded green there; a failure in those paths during Session `47`
  should be treated as a new regression unless it clearly reproduces a
  documented pre-existing known failure
- the documented Posts macOS startup failures are unrelated to this session and
  must not be used to excuse a cancelable-upload regression
- `transport` was last recorded green on `2026-03-26` and is not part of the
  default Session `47` contract
- if a failure appears only because unrelated dirty-worktree changes changed a
  touched test or doc outside this closure slice, stop and classify that as a
  repo-state blocker rather than rewriting the closure prose around it

## done criteria

- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  accurately reflects the landed cancelable-upload behavior
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  accurately reflects the landed group parity behavior
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md` is
  either updated narrowly or explicitly left unchanged with evidence-based
  rationale
- `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md` records
  Session `47` as accepted and preserves the final accepted differences
- the closure pass explicitly records whether `test-gate-definitions.md`
  changed and whether `completeness-check` was actually required
- no new implementation work is silently opened inside this session

## scope guard

- do not change production upload behavior, retry orchestration, DB schema, or
  named-gate membership unless current repo evidence proves the stable docs
  would otherwise overclaim
- do not add new regressions, new gates, or a new closure matrix document by
  default
- do not reopen background-upload architecture, product-scope retry/delete
  expansion, or a new message-status model
- do not broaden the session into general folder cleanup just because
  `00-INDEX.md` or `17-roadmap-closure-audit.md` were inspected

## accepted differences / intentionally out of scope

- no mid-stream transport cancel:
  in-flight upload RPCs are still non-interruptible; cancel takes effect at the
  next safe boundary
- no new `cancelled` status model:
  the repo still uses `failed` plus attachment `upload_failed`
- no blanket deletion of arbitrary source/gallery files:
  cleanup stays limited to app-owned durable pending-upload paths
- no per-thumbnail mid-upload removal contract:
  the accepted user control is batch cancel plus composer restoration
- no background-upload expansion:
  the closure promise remains foreground-only protection and terminalization
- no generic failed-text retry/delete controls:
  this closure slice remains media-upload recovery specific
- no announcement-specific second upload-control architecture:
  announcements remain an acceptance layer on top of shared group behavior

## dependency impact

- after Session `47`, future maintenance should rely on the stable closure
  refs and refreshed breakdown, not on Sessions `44` through `46` plan prose,
  to understand cancelable-upload closure
- if Session `47` needs to edit `test-gate-definitions.md`, it also owns the
  required `completeness-check` rerun; otherwise later work should not assume
  such a rerun happened
- if acceptance evidence exposes a real doc/code mismatch, downstream closure
  refresh work must stop and a new narrow correction session should be planned
  before claiming this proposal closed
