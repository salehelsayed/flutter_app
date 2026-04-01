# 31 - Edit Last Sent Message Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/31-edit-last-sent-message.md`
- Decomposition date:
  `2026-03-30`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `3`
- The smallest safe split is one shared editable-message contract session, one
  Orbit/shared-overlay session, and one feed-parity/final-acceptance session.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Retry attempts used | Final execution verdict | Blocker class | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | Shared editable-message persistence and wire contract | `implementation-ready` | `Test-Flight-Improv/31-edit-last-sent-message-session-1-plan.md` | none | `accepted` | `1` | `accepted` | none | `Test-Flight-Improv/31-edit-last-sent-message-session-1-plan.md`, `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md` | Accepted on `2026-03-31` after the bounded local execution fallback landed the shared `edited_at` persistence/migration path, the `send` vs `edit` payload contract, and same-ID receiver-side edit handling, then verified `dart analyze`, the direct Session `1` suites, `./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. |
| `2` | Shared context-menu edit affordance and Orbit conversation edit flow | `implementation-ready` | `Test-Flight-Improv/31-edit-last-sent-message-session-2-plan.md` | `1` | `accepted` | `2` | `accepted` | none | `Test-Flight-Improv/31-edit-last-sent-message-session-2-plan.md`, `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md` | Accepted on `2026-03-31` after the bounded local planning and execution fallbacks landed the shared overlay `Edit` action, Orbit edit-mode prefill/cancel/no-op handling, and the Orbit edited indicator, then verified `dart analyze`, the direct Session `2` presentation suites, `./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. |
| `3` | Feed/stack edit parity, failed-row refresh, and final acceptance | `implementation-ready` | `Test-Flight-Improv/31-edit-last-sent-message-session-3-plan.md` | `2` | `accepted` | `3` | `accepted` | none | `Test-Flight-Improv/31-edit-last-sent-message-session-3-plan.md`, `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md` | Accepted on `2026-03-31` after the bounded local planning, execution, and closure fallbacks landed feed-side last-sent `Edit` gating, inline edit-mode prefill/cancel/no-op handling, in-place edited indicators, and failed-row refresh coverage, then verified narrowed `dart analyze`, the direct Session `3` feed presentation suites, `./scripts/run_test_gates.sh feed`, `./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. |

## Overall closure bar

Report `31` is closed only when all current 1:1 surfaces expose one honest
"edit last sent message" contract without reopening unrelated 1:1 reliability
or delete/history scope:

- Orbit conversations and feed/stack 1:1 cards show `Edit` only for the
  user’s last sent message with editable text.
- Entering edit mode prefills the composer, allows cancel/no-op handling,
  preserves the existing message ID, timestamp/position, quote linkage, media,
  and reactions, and does not create a second message row.
- Edited rows persist an `edited_at` timestamp, render an edited indicator on
  both sender and receiver surfaces, and update in place.
- The wire contract distinguishes normal sends from edits, receiver-side
  duplicate rejection still rejects genuine non-edit duplicates, and offline
  delivery still reuses the existing queued/inbox fallback behavior.
- Group conversations, delete semantics, edit history, undo, and arbitrary
  past-message editing remain out of scope.

## Final program acceptance

- Closure verdict:
  `closed`
- Acceptance date:
  `2026-03-31`
- What is now closed:
  - Orbit conversations and feed/stack 1:1 cards now expose `Edit` only for
    the user’s eligible last-sent text-bearing row through the shared
    long-press overlay contract
  - Orbit and feed edit mode both prefill the composer, allow cancel and
    identical-text no-op handling, preserve the original row/message ID, and
    route changed text through the shared edit contract instead of creating a
    second message row
  - edited rows now persist `edited_at`, update in place, and render edited
    indicators on both Orbit and feed surfaces, including feed previews and
    compact bubbles
  - same-ID edit payloads still reuse the existing queued/inbox delivery path
    while preserving genuine non-edit duplicate rejection
- Residual-only items:
  - none
- Still-open items:
  - none
- Reopen only on real regression:
  - if last-sent-only edit eligibility, edit-mode prefill/cancel/no-op
    handling, or in-place same-ID update behavior regresses on Orbit or feed
    1:1 surfaces
  - if edited indicators or feed failed-row refresh stop reflecting the saved
    edited row accurately
  - if the direct shared/Orbit/feed regressions fail, or if future changes
    touching this feature stop passing the named maintenance gates `feed`,
    companion `1to1`, and explicit macOS `baseline`

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/31-edit-last-sent-message.md`
- `Test-Flight-Improv/26-long-press-message-context-menu.md`
- `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`

Current repo facts that govern closure:

- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  now ships the shared long-press overlay with conditional `Reply`, `Edit`,
  and text-only `Copy`, so this report no longer owns invention of the shared
  action seam.
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
  and `lib/features/feed/presentation/screens/feed_screen.dart` already host
  the shared overlay, and report `31` closed by extending that landed seam
  instead of reintroducing a raw reaction-bar-only path from stale prose.
- `lib/features/conversation/domain/models/conversation_message.dart` now
  persists nullable `editedAt`, and Orbit now renders an edited indicator via
  `lib/features/conversation/presentation/widgets/letter_card.dart`; feed now
  matches that parity because
  `lib/features/feed/domain/models/feed_item.dart` and
  `lib/features/feed/domain/utils/group_messages_into_threads.dart` project
  `editedAt` into `ThreadMessage`.
- `lib/features/conversation/domain/models/message_payload.dart` now
  distinguishes `send` vs `edit` and carries `editedAt`, so the landed scope
  stayed surface parity rather than wire-format invention.
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
  now owns Orbit edit-mode activation, composer prefill/focus, cancel, and
  identical-text no-op suppression on top of the shared edit contract, so
  Session `3` should not reopen Orbit-specific composer work unless a real
  regression is found.
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  now accepts same-ID edit payloads for existing rows while preserving
  duplicate rejection for genuine non-edit duplicates, which closes the shared
  send/receive seam both UI surfaces depend on.
- `lib/core/database/helpers/messages_db_helpers.dart` still upserts on ID via
  `ConflictAlgorithm.replace`, and
  `test/core/database/helpers/messages_db_helpers_test.dart` already proves the
  replace-on-conflict behavior; that makes the row-update half of editing
  smaller than the original report implies.
- `lib/features/feed/domain/models/feed_item.dart` already exposes
  `ThreadFeedItem.lastSentMessage`, so the feed surface can derive "last sent"
  from the full thread item without forcing a new repository query by default;
  `lib/features/feed/presentation/screens/feed_screen.dart` now uses that seam
  to expose `Edit` only for the eligible last-sent text row.
- `lib/features/feed/presentation/screens/feed_wired.dart` only refreshes
  outgoing repo changes for `sent` and `delivered`; Session `3` expanded that
  refresh seam to include `failed` and added feed-owned edit-mode
  prefill/cancel/no-op handling without creating optimistic reply duplicates.
- `lib/features/feed/presentation/widgets/message_bubble.dart`,
  `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`,
  and `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
  now render the feed-side edited indicator and edit-mode banner where the
  edited row or active composer state is shown.
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  explicitly treats editing/deletion as product scope outside the current 1:1
  reliability closure bar, so that doc is a scope guard here, not the closure
  owner for this feature.

Source-of-truth conflicts that materially affected decomposition:

- The Report `31` current-state prose about long-press behavior is stale after
  Report `26`; reply/copy overlay work is already landed and should be reused.
- The Report `31` suggestion to add a dedicated "latest sent" repository query
  is not automatically required by current code. Conversation and feed
  surfaces already carry enough message/thread context to derive the last sent
  message locally unless execution evidence proves otherwise.

## Reviewer pass

- Sufficiency:
  `3` sessions is sufficient. Fewer sessions would bundle a shared send/receive
  contract change together with two different UI host seams; more sessions
  would split tightly coupled work without adding independent verification.
- Merge candidates:
  none.
- Required splits:
  none.
- Missing tests or named gates:
  none for current acceptance. A future reopen still uses the shared
  application/domain/DB regressions, Orbit presentation suites, feed
  presentation suites, plus the named maintenance gates `feed`, companion
  `1to1`, and explicit macOS `baseline`.
- Meaningful verified state:
  yes. Session `1` can land a reusable edit contract with no UI, Session `2`
  can prove Orbit/shared-overlay behavior on top of that contract, and Session
  `3` can prove feed parity plus final cross-surface closure.
- Matrix responsibility:
  clear. This breakdown artifact is the live ledger for the feature, while
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` stays a
  scope guard only.
- Minimum safe session set:
  `3`.

## Arbiter outcome

- Structural blockers:
  none.
- Mergeable sessions:
  none.
- Required splits:
  none.
- Accepted differences:
  - only the last sent 1:1 message is editable
  - media-only rows stay non-editable; text+media rows only edit text
  - no edit history, undo, time limit, or group-conversation support
  - older clients may ignore or duplicate-drop edit payloads as long as they
    do not crash
  - this feature does not reopen delete semantics or the 1:1 reliability
    closure reference unless execution evidence proves a shared reliability
    regression

## Ordered session breakdown

### Session 1

- Title:
  `Shared editable-message persistence and wire contract`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/31-edit-last-sent-message-session-1-plan.md`
- Exact scope:
  - add the nullable message edit metadata needed for 1:1 rows, including an
    `edited_at` persistence path through the DB migration chain, row mapping,
    and in-memory models
  - extend `MessagePayload` (and its v1/v2 parse/serialize helpers) with an
    explicit edit-vs-send discriminator while preserving normal new-message
    behavior
  - land the shared local/apply-edit path so editing a row updates the same
    message ID, preserves the original timestamp and quote linkage, and keeps
    existing reaction/media associations intact
  - teach incoming handling to accept same-ID edit updates while preserving the
    existing duplicate rejection for genuine non-edit duplicates
  - reuse the existing send/offline queueing path for edit payload delivery
    rather than inventing a second transport architecture
- Why it is its own session:
  - this is the shared correctness seam that both UI surfaces depend on
  - it has a distinct direct regression family: DB/model/payload/send/incoming
    behavior, not presentation behavior
  - it should be proven before any surface starts exposing an `Edit` affordance
- Likely code-entry files:
  - `lib/core/database/migrations/002_messages_table.dart`
  - `lib/core/database/migrations/009_quoted_message_id.dart`
  - `lib/core/database/migrations/014_wire_envelope_column.dart`
  - `lib/core/database/helpers/messages_db_helpers.dart`
  - `lib/main.dart`
  - `lib/features/conversation/domain/models/conversation_message.dart`
  - `lib/features/conversation/domain/models/message_payload.dart`
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `lib/features/conversation/domain/repositories/message_repository_impl.dart`
  - `test/shared/fakes/in_memory_message_repository.dart`
- Likely direct tests/regressions:
  - `test/core/database/helpers/messages_db_helpers_test.dart`
  - `test/features/conversation/domain/models/message_payload_test.dart`
  - `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  - `test/features/conversation/application/handle_incoming_chat_message_media_hydration_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` only if execution unexpectedly
    touches inbox-drain, bootstrap, reconnect, or transport-fallback wiring
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact’s session ledger
  - do not reopen
    `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    unless shared reliability semantics or maintenance-time test requirements
    actually change
- Dependency on earlier sessions:
  - none

### Session 2

- Title:
  `Shared context-menu edit affordance and Orbit conversation edit flow`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/31-edit-last-sent-message-session-2-plan.md`
- Exact scope:
  - extend the shared long-press overlay and localization surface with a
    conditional `Edit` action alongside the already-landed `Reply` and `Copy`
    actions
  - compute Orbit-side edit eligibility from current conversation state:
    outgoing only, last sent only, and only when the row still has editable
    text
  - add Orbit composer edit-mode state: prefill text, request focus, expose a
    bounded cancel path, and short-circuit identical-text no-op submits
  - render an edited indicator on Orbit message cards once `edited_at` is
    present
  - keep swipe-to-reply, copy, emoji reactions, media tap behavior, and group
    paths unchanged
- Why it is its own session:
  - the shared overlay plus Orbit host seam is a coherent UI slice with its own
    direct presentation regressions
  - feed uses different draft/focus/thread-refresh wiring and should not be
    mixed into the first UI landing
- Likely code-entry files:
  - `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  - `lib/features/conversation/presentation/widgets/compose_area.dart`
  - `lib/features/conversation/presentation/widgets/letter_card.dart`
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/l10n/app_en.arb`
  - `lib/l10n/app_ar.arb`
  - `lib/l10n/app_de.arb`
- Likely direct tests/regressions:
  - `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
  - `test/features/conversation/presentation/widgets/compose_area_test.dart`
  - `test/features/conversation/presentation/widgets/letter_card_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh 1to1` because the Orbit surface still enters
    the shared 1:1 send/edit contract after Session `1`
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact’s session ledger
  - update `Test-Flight-Improv/test-gate-definitions.md` only if execution adds
    or reclassifies a maintained regression suite
- Dependency on earlier sessions:
  - `1`

### Session 3

- Title:
  `Feed/stack edit parity, failed-row refresh, and final acceptance`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/31-edit-last-sent-message-session-3-plan.md`
- Exact scope:
  - propagate the conditional `Edit` affordance through feed/stack 1:1 cards
    using thread-aware last-sent evaluation from the full `ThreadFeedItem`,
    not just the visible preview subset
  - wire feed draft/focus/edit state so inline compose prefills, cancel, and
    submit behavior match Orbit without breaking existing quote-reply behavior
  - map edit metadata into `ThreadMessage` and `MessageBubble` so feed rows show
    the edited indicator while preserving quote/media rendering
  - make sure feed-side repo/change handling refreshes edited outgoing rows,
    including failed rows that remain `failed` after a local edit save
  - run the final cross-surface acceptance/closure pass and persist the final
    program verdict back into this breakdown artifact
- Why it is its own session:
  - feed still has a distinct host seam: thread-model mapping, session-reply
    state, focus routing, and repo-change refresh
  - this slice owns the feed regression family and the maintenance-time `feed`
    gate decision
- Likely code-entry files:
  - `lib/features/feed/domain/models/feed_item.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
  - `lib/features/feed/presentation/widgets/inline_reply_input.dart`
  - `lib/features/feed/presentation/widgets/message_bubble.dart`
- Likely direct tests/regressions:
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/presentation/widgets/feed_card_test.dart`
  - `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`
  - `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh feed`
  - companion `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact with per-session status and the final
    program acceptance verdict
  - update `Test-Flight-Improv/00-INDEX.md` or
    `Test-Flight-Improv/17-roadmap-closure-audit.md` only if the closure audit
    finds folder-level status drift after the feature lands
- Dependency on earlier sessions:
  - `2`

## Why this is not fewer sessions

- Session `1` changes the shared 1:1 persistence/send/receive contract. It can
  be verified with DB/model/use-case tests and named gates before any UI starts
  exposing `Edit`.
- Session `2` changes the shared overlay plus Orbit’s composer/rendering seam.
  Combining that with Session `1` would bundle correctness and surface work
  into one broad patch with weaker failure isolation.
- Session `3` still has a separate feed host seam: thread-model projection,
  partial-preview eligibility, feed draft/focus state, and repo-change refresh.
  Merging it into Session `2` would mix two different surface families and make
  the feed gate/acceptance decision harder to audit.

## Why this is not more sessions

- Splitting the DB migration away from payload/incoming edit handling would
  create bookkeeping without a meaningful independently verified state.
- Splitting the Orbit edit affordance away from the Orbit edit-mode composer and
  edited rendering would leave a misleading half-feature on the first surface.
- Splitting failed-row feed refresh into its own extra session would be
  hallucination bait; it is part of the same feed parity seam as edit-mode
  propagation and thread-model updates.

## Regression and gate contract

- Session `1` must add or tighten the direct shared-contract regressions first,
  then run the targeted DB/model/application suites, then
  `./scripts/run_test_gates.sh 1to1`, then
  `./scripts/run_test_gates.sh baseline`.
- Session `2` must prove the shared overlay/Orbit edit behavior in targeted
  presentation suites, keep reply/copy/reaction behavior green, and run
  `./scripts/run_test_gates.sh baseline` plus companion
  `./scripts/run_test_gates.sh 1to1`.
- Session `3` must prove feed-specific parity in the targeted feed suites, then
  run `./scripts/run_test_gates.sh feed`, companion
  `./scripts/run_test_gates.sh 1to1`, and
  `./scripts/run_test_gates.sh baseline`.
- `./scripts/run_test_gates.sh transport` is out unless a session unexpectedly
  edits bootstrap, reconnect, inbox-drain, or transport-fallback wiring.
- `./scripts/run_test_gates.sh completeness-check` is only required if a
  session edits `Test-Flight-Improv/test-gate-definitions.md` or changes test
  classification.

## Matrix update contract

- No stable edit-specific closure reference exists for this area yet, so this
  breakdown artifact is the live doc-scoped ledger during rollout.
- The final closure pass may update `Test-Flight-Improv/00-INDEX.md` or
  `Test-Flight-Improv/17-roadmap-closure-audit.md` if the folder-level closure
  record would otherwise stay stale.
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` stays a
  scope guard, not the closure owner for Report `31`, unless execution proves a
  real shared reliability reopening.

## Downstream execution path

- Session `1` should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Session `2` should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Session `3` should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- the feature remains 1:1-only
- only the text portion of a text+media message is editable
- no edit history, undo, or sender-visible read-receipt changes
- older clients may ignore or duplicate-drop edit payloads as long as the app
  stays stable

## Exact docs/files used as evidence

- `Test-Flight-Improv/31-edit-last-sent-message.md`
- `Test-Flight-Improv/26-long-press-message-context-menu.md`
- `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `lib/core/database/migrations/002_messages_table.dart`
- `lib/core/database/helpers/messages_db_helpers.dart`
- `lib/main.dart`
- `lib/features/conversation/domain/models/conversation_message.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/features/conversation/domain/repositories/message_repository.dart`
- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/feed/domain/models/feed_item.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/widgets/message_bubble.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `test/core/database/helpers/messages_db_helpers_test.dart`
- `test/features/conversation/domain/models/message_payload_test.dart`
- `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_media_hydration_test.dart`
- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The split is based on current repo seams, not the stale pre-Report-`26`
  version of the product.
- Each session has doc-scoped plan paths, explicit dependencies, concrete code
  entry files, direct regression families, and named-gate expectations.
- No structural blocker remains, and the accepted differences keep the rollout
  from widening into delete/history/group scope during execution.
