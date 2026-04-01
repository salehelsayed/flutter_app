# Session 3 Plan: Feed/Stack Edit Parity, Failed-Row Refresh, and Final Acceptance

## Evidence collector summary

- Sessions `1` and `2` are now accepted in
  `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md`, so the
  shared edit contract and Orbit edit UX are already landed and should be
  reused rather than reopened.
- `lib/features/feed/presentation/screens/feed_screen.dart` already hosts the
  shared `MessageContextOverlay`, but its long-press path currently exposes
  reactions, `Reply`, and conditional `Copy` only; it does not route a feed
  `Edit` action or evaluate last-sent eligibility.
- `lib/features/feed/presentation/screens/feed_wired.dart` already owns feed
  draft text, active quote IDs, focus routing, and inline send behavior, but
  it has no feed edit-mode state and still treats every inline submit as a new
  outgoing reply.
- `lib/features/feed/domain/models/feed_item.dart`,
  `lib/features/feed/domain/utils/group_messages_into_threads.dart`, and
  `lib/features/feed/presentation/screens/feed_wired.dart` currently project
  text, status, quotes, and media into `ThreadMessage`, but they do not
  project `editedAt`, so feed rows cannot render edited state yet.
- `lib/features/feed/presentation/widgets/message_bubble.dart` renders the
  compact feed row footer, but it has no edited-indicator seam.
- `lib/features/feed/presentation/screens/feed_wired.dart` refreshes outgoing
  repository changes only for `sent` and `delivered`; it ignores `failed`, so
  an edited failed row can stay stale in feed even though the repository emits
  a replacement message.
- Existing feed tests already cover quote preview, swipe-to-reply, session
  reply state, incremental retry refresh, and long-press reply wiring, so
  Session `3` can extend those suites instead of inventing a new surface.

## Real scope

- Add the conditional `Edit` affordance to feed/stack 1:1 thread cards using
  full-thread last-sent evaluation rather than just the currently visible
  preview slice.
- Add feed-owned edit-mode state that reuses the existing inline composer
  draft/focus seam, provides a bounded cancel path, and suppresses
  identical-text no-op submits.
- Route a changed feed edit submit through the accepted shared edit contract
  from Session `1` without creating a session-reply duplicate row.
- Project edit metadata into `ThreadMessage` and render an edited indicator in
  feed message bubbles and previews where the edited row is shown.
- Refresh feed thread cards on outgoing repository change events for edited
  rows that remain `failed`, then finish the final report-31 acceptance pass.

Out of real scope for this session:

- Reworking Orbit behavior that Session `2` already accepted unless a real
  regression is discovered during feed parity work.
- Group edit affordances, delete semantics, edit history, undo, edit timers,
  or arbitrary past-message editing.
- A generic cross-surface composer-state framework beyond the smallest feed
  seam needed to close report `31`.

## Closure bar

- Feed/stack long-press shows `Edit` only for the user's last sent 1:1
  text-bearing message, even when a newer incoming row exists or the visible
  preview is a subset of the full thread.
- Entering feed edit mode prefills the inline composer, requests focus, exposes
  a cancel path, and keeps quote-reply behavior honest instead of mixing quote
  and edit state.
- Submitting unchanged text from feed edit mode is a no-op and does not create
  a new row, session-reply placeholder, or duplicate send attempt.
- Submitting changed text updates the same message ID through the shared edit
  contract, preserving quote/media associations and row position.
- Feed message bubbles render an edited indicator when `editedAt` is present.
- Outgoing repository change refresh picks up edited rows that remain `failed`
  as well as `sent` and `delivered`.
- Direct feed regressions pass, plus `./scripts/run_test_gates.sh feed`,
  companion `./scripts/run_test_gates.sh 1to1`, and
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`.
- The breakdown artifact is updated to an honest final verdict for report `31`.

## Source of truth

- Active session contract:
  - `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md`
  - `Test-Flight-Improv/31-edit-last-sent-message.md`
- Accepted upstream sessions to reuse, not reopen:
  - `Test-Flight-Improv/31-edit-last-sent-message-session-1-plan.md`
  - `Test-Flight-Improv/31-edit-last-sent-message-session-2-plan.md`
- Reused overlay behavior and scope context:
  - `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- Regression and gate authority:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Scope guard:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Current code and accepted breakdown facts beat stale report prose when they
  disagree.

## Session classification

`implementation-ready`

## Exact problem statement

- The shared edit payload/persistence contract and Orbit UX are already
  accepted, but feed/stack cards still cannot enter edit mode because their
  long-press overlay does not expose `Edit`.
- Feed cards currently build edit eligibility from no feed-specific seam at
  all, so they cannot enforce the product rule "last sent only" across the
  full thread state.
- Feed inline compose state currently assumes every submit is a new outgoing
  reply, which would incorrectly create optimistic session-reply UI for edits.
- Feed thread projection currently drops `editedAt`, so the feed surface cannot
  render an edited indicator even when the repository row is already edited.
- Feed outgoing repository refresh ignores `failed`, so an edited failed row
  can remain visually stale after a local save/update.
- Session `3` must close these feed-specific seams and then record the final
  report verdict without widening into group editing or broader composer
  architecture work.

## Files and repos to inspect next

Exact production files:

- `lib/features/feed/domain/models/feed_item.dart`
- `lib/features/feed/domain/utils/group_messages_into_threads.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `lib/features/feed/presentation/widgets/inline_reply_input.dart`
- `lib/features/feed/presentation/widgets/message_bubble.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
  for the already-landed shared `editChatMessage(...)` seam

Exact direct tests:

- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/presentation/widgets/feed_card_test.dart`
- `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`
- `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
- `test/features/feed/presentation/widgets/message_bubble_test.dart`
  only if `message_bubble.dart` changes

## Existing tests covering this area

- `test/features/feed/presentation/screens/feed_screen_test.dart` already pins
  quote-preview mapping, session-reply rendering, and long-press reply wiring
  through the shared overlay seam.
- `test/features/feed/presentation/screens/feed_wired_test.dart` already pins
  feed draft focus, inline reply send behavior, quote persistence, optimistic
  session reply, and incremental retry refresh on outgoing rows.
- `test/features/feed/presentation/widgets/feed_card_test.dart`,
  `open_mode_card_body_test.dart`, and `collapsed_mode_card_body_test.dart`
  already pin open vs collapsed card structure and quote-preview behavior.
- `test/features/feed/presentation/widgets/message_bubble_test.dart` already
  covers outgoing footer/status rendering if Session `3` changes that footer.

Current coverage gaps:

- no test proves feed `Edit` visibility for last-sent vs older sent vs incoming
  vs media-only rows
- no test proves feed edit activation prefills the inline composer and requests
  focus
- no test proves feed edit cancel or identical-text no-op behavior
- no test proves feed changed-text submit routes through the shared edit path
  without optimistic session-reply duplication
- no test proves feed rows render edited state
- no test proves repository-change refresh updates edited rows that remain
  `failed`

## Regression/tests to add first

- Add feed-screen regressions that prove:
  - `Edit` appears only for the eligible last-sent text row
  - a newer incoming row does not suppress edit eligibility on the last sent
    row
  - older sent rows, incoming rows, media-only rows, and group rows do not
    expose `Edit`
- Add feed-wired regressions that prove:
  - edit activation prefills the inline composer and requests focus
  - entering edit mode clears any incompatible quote/session-reply state
  - cancel exits edit mode without mutating the original row
  - unchanged edit submit is a no-op
  - changed edit submit updates the same row via the shared edit path
  - edited failed rows refresh in place from repository change events
- Add widget regressions for edited-indicator rendering in feed rows if the
  changed widget surface needs direct pinning.

Only add `message_bubble_test.dart`, `open_mode_card_body_test.dart`, or
`collapsed_mode_card_body_test.dart` if execution changes those widgets. Do
not fabricate extra widget churn just to satisfy the likely-file list.

## Step-by-step implementation plan

1. Extend feed thread projection with edit metadata.
   Add nullable `editedAt` to `ThreadMessage` and thread builders so feed can
   carry the already-persisted shared edit state end to end.
2. Teach `FeedScreen` to compute feed edit eligibility from the full
   `ThreadFeedItem`:
   - 1:1 only
   - outgoing only
   - last sent only
   - text-bearing rows only
   Then pass a new optional `Edit` callback into the shared overlay without
   changing group behavior.
3. Add the smallest feed-owned edit state in `FeedWired`.
   Prefer a bounded seam:
   - currently edited message ID per contact thread
   - original text snapshot for no-op detection
   - edit activation handler
   - cancel handler
   - inline submit branch that calls `editChatMessage(...)`
   Reuse existing `_draftTexts`, `_activeFocusPeerId`, and focus plumbing
   instead of inventing a second composer architecture.
4. Keep quote/session-reply behavior honest while editing.
   Edit activation should clear incompatible quote/session-reply state for that
   card, and edit submit must not create a new optimistic `SessionReply`.
5. Render edited state on feed rows.
   Add the smallest edited-indicator seam to `MessageBubble` and any preview
   widgets that surface the edited row.
6. Expand feed repository-change refresh to include `failed` so edited failed
   rows repaint from repository emissions without a full reload.
7. Land direct feed regressions alongside implementation, then run the required
   named gates.
8. Update the breakdown artifact with Session `3` acceptance and the final
   report-31 verdict. Update folder-level closure docs only if the closure
   audit finds real status drift.

## Risks and edge cases

- Feed edit eligibility can drift if it uses the visible preview instead of the
  full thread model; the user must be able to edit their last sent row even if
  a newer incoming message exists or the row is off the newest-preview edge.
- Feed edit mode must not reuse optimistic reply/session-reply UI or it will
  visually create a fake second message while editing an existing one.
- Quote state and edit state can conflict on the same inline composer; Session
  `3` needs one honest precedence rule instead of allowing both at once.
- Edited failed rows are easy to miss because repository refresh currently
  filters them out even though the repository emits a changed message.
- Feed row rendering must keep quote/media/reaction layout intact when the
  edited indicator is added.
- Group cards share some feed widgets; Session `3` must keep group edit support
  out of scope and avoid accidentally surfacing `Edit` there.

## Exact tests and gates to run

Direct tests:

- `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- `flutter test test/features/feed/presentation/widgets/feed_card_test.dart`
- `flutter test test/features/feed/presentation/widgets/open_mode_card_body_test.dart`
  only if `open_mode_card_body.dart` changes
- `flutter test test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
  only if `collapsed_mode_card_body.dart` changes
- `flutter test test/features/feed/presentation/widgets/message_bubble_test.dart`
  only if `message_bubble.dart` changes

Fast structural validation:

- `dart analyze lib/features/feed/domain/models/feed_item.dart lib/features/feed/domain/utils/group_messages_into_threads.dart lib/features/feed/presentation/screens/feed_screen.dart lib/features/feed/presentation/screens/feed_wired.dart lib/features/feed/presentation/widgets/feed_card.dart lib/features/feed/presentation/widgets/open_mode_card_body.dart lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart lib/features/feed/presentation/widgets/scrollable_message_preview.dart lib/features/feed/presentation/widgets/inline_reply_input.dart lib/features/feed/presentation/widgets/message_bubble.dart`
  narrowed to the files actually changed

Named gates:

- `./scripts/run_test_gates.sh feed`
- `./scripts/run_test_gates.sh 1to1`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

Not required for Session `3` as currently scoped:

- `./scripts/run_test_gates.sh transport`
- `./scripts/run_test_gates.sh completeness-check` unless execution changes
  maintained test-gate classification docs

## Known-failure interpretation

- The accepted Session `2` state already proved `1to1` and the explicit macOS
  `baseline` invocation can pass before feed parity starts.
- In this local environment, `baseline` must be run as
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` because the
  integration portion otherwise aborts on device ambiguity; that is an
  invocation issue, not a product failure.
- MacOS linker/deployment-target warnings observed during baseline are not
  failing test results by themselves.
- Any new failure in the feed direct suites or in `feed`, `1to1`, or
  `baseline` after the Session `3` changes should be treated as a real Session
  `3` blocker unless it reproduces on the already-accepted Session `2` state.

## Done criteria

- Feed/stack 1:1 rows expose `Edit` only on the eligible last-sent text row.
- Feed edit mode prefills the inline composer, requests focus, and supports
  cancel.
- Feed identical-text edit submits are no-ops.
- Feed changed-text edit submits update the same row via the shared edit path.
- Feed rows render an edited indicator when `editedAt` is present.
- Feed repository refresh updates edited failed rows without full reload.
- Direct Session `3` regressions pass.
- `feed`, companion `1to1`, and explicit macOS `baseline` gates pass.
- The breakdown artifact records Session `3` acceptance and the final report
  verdict for report `31`.

## Scope guard

- Do not reopen Orbit implementation details that Session `2` already accepted
  unless a feed-driven regression requires a narrow shared fix.
- Do not add group edit affordances or any generic "edit any past message"
  capability.
- Do not expand into delete semantics, edit history, undo, or edit timers.
- Do not redesign transport, retry, inbox, or persistence architecture already
  accepted in Session `1`.
- Do not add batch-level or extra session-level retry logic outside the current
  bounded pipeline.

## Accepted differences / intentionally out of scope

- Media-only rows remain non-editable; text+media rows edit text only.
- Group cards continue to support reply/reaction behavior only, not edit.
- Feed may use a bounded per-thread edit-state seam instead of a new global
  multi-surface composer-state framework.
- Folder-level closure docs should stay untouched unless the final closure pass
  finds actual status drift after report `31` is closed.

## Dependency impact

- This session is the final report-31 implementation slice; no later report-31
  session remains after it.
- If execution discovers a tiny shared widget seam that both Orbit and feed
  should use, land it only if it keeps Orbit behavior honest and does not
  silently widen into new product scope.
- If execution proves feed parity requires reopening accepted Session `2`
  behavior, stop and refresh the breakdown instead of silently widening.

## Reviewer pass

- Sufficiency verdict:
  - sufficient with two cautions
- Missing structural items:
  - none
- Required cautions:
  - keep last-sent evaluation tied to the full thread, not the visible preview
  - do not let edit submit create optimistic session-reply UI
- Overengineering to avoid:
  - generic cross-surface composer architecture
  - group edit support
  - reopening delete/history scope

## Arbiter outcome

- Structural blockers:
  - none
- Incremental details intentionally deferred:
  - whether `feed_card.dart`, `open_mode_card_body.dart`, or
    `collapsed_mode_card_body.dart` need API changes should be decided during
    execution based on the smallest honest seam
- Accepted differences:
  - a bounded per-contact feed edit-state map is acceptable if it closes the
    feature without forcing a broader draft-state refactor
