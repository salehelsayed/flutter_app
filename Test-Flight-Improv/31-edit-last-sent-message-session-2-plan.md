# Session 2 Plan: Shared Context-Menu Edit Affordance and Orbit Conversation Edit Flow

## Evidence collector summary

- Session `1` is now accepted in
  `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md`, so the
  shared persistence/send/receive edit contract already exists and Session `2`
  can stay UI-scoped.
- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  currently exposes `Reply` plus conditional `Copy` only; it has no edit
  affordance or localization key for conversation-specific edit text.
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
  already owns the long-press overlay routing and the composer-focus handoff
  used by reply, so it is the correct Orbit host seam for conditional edit
  visibility and edit activation.
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
  already owns Orbit draft state in `_draftText`, quote state in
  `_activeQuoteMessageId`, and the send submission branch in `_onSend(...)`;
  it does not yet own any edit-mode state.
- `lib/features/conversation/presentation/widgets/compose_area.dart` already
  supports `initialText` and `shouldRequestFocus`; Session `2` should reuse
  that seam for edit prefill/focus instead of inventing a second composer
  architecture.
- `lib/features/conversation/presentation/widgets/letter_card.dart` currently
  renders reactions, timestamp, and delivery status in the footer, but no
  edited indicator.
- Existing Orbit presentation tests already pin reply/copy overlay behavior,
  quote/focus handoff, and draft hydration, so Session `2` can extend those
  suites rather than creating a new test surface.

## Real scope

- Add a conditional `Edit` action to the shared long-press overlay for the
  Orbit conversation surface only when the pressed row is the user's last sent
  1:1 message and still has editable text.
- Add Orbit-owned edit-mode state that reuses the current composer prefill and
  focus path, supports an explicit cancel path, and suppresses identical-text
  no-op submits.
- Route an actual Orbit edit submit through the accepted shared edit contract
  from Session `1`.
- Render an edited indicator on Orbit message cards when `editedAt` is present.

Out of real scope for this session:

- Feed/stack edit affordances, feed inline edit state, feed edited indicators,
  or feed repo-refresh parity. That belongs to Session `3`.
- Delete semantics, edit history, undo, edit time limits, group editing, or a
  generic multi-surface composer-mode framework.

## Closure bar

- Orbit long-press shows `Edit` only for the user's last sent text-bearing 1:1
  message and keeps `Reply`, `Copy`, reactions, media tap, and swipe-to-reply
  behavior honest.
- Tapping `Edit` prefills the Orbit composer with the row text, requests focus,
  and exposes a bounded cancel path back to normal compose mode.
- Submitting unchanged text from edit mode is a no-op and does not send or
  persist a second row.
- Submitting changed text uses the shared edit contract so the same message ID
  updates in place.
- Orbit message cards show an edited indicator when `editedAt` is present.
- Direct Orbit/widget regressions pass, plus companion `1to1` and `baseline`
  named gates.

## Source of truth

- Active session contract:
  - `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md`
  - `Test-Flight-Improv/31-edit-last-sent-message.md`
- Reused overlay behavior and scope context:
  - `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- Regression and gate authority:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Scope guard:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Current code and tests beat stale prose when they disagree.
- ARB files are the localization source of truth; generated localization Dart
  files should update only as required by the new conversation edit strings.

## Session classification

`implementation-ready`

## Exact problem statement

- The shared edit contract now exists, but Orbit still has no user-visible way
  to enter that contract because the shared long-press overlay exposes only
  reply/copy actions.
- Orbit also lacks edit-mode state, so there is no supported path to prefill
  the composer with an existing row, cancel the edit, or suppress identical
  no-op submissions.
- Even if an edited row lands from Session `1`, Orbit cards do not currently
  render any edited indicator, so users cannot tell that an in-place update
  happened.
- Session `2` must close the Orbit/shared-overlay UI seam without widening into
  feed parity, generic composer refactors, or additional transport work.

## Files and repos to inspect next

Exact production files:

- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_de.arb`
- `lib/l10n/app_ar.arb`
- generated localization outputs under `lib/l10n/` only if the ARB changes
  require them

Exact direct tests:

- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/features/conversation/presentation/widgets/compose_area_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`

## Existing tests covering this area

- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
  proves the current overlay chrome, reply action, conditional copy action,
  and backdrop dismissal behavior.
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  proves long-press reply/copy visibility on Orbit rows and the existing
  quote-preview plumbing.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  proves quote reply activation, composer focus handoff, quoted send routing,
  and repo-change refresh on outgoing rows.
- `test/features/conversation/presentation/widgets/compose_area_test.dart`
  proves `initialText` hydration, focus requests, and existing quote-preview
  behavior; this means Session `2` can usually reuse the seam rather than
  re-architect it.
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
  proves outgoing footer status behavior and body/quote rendering, but does not
  yet cover an edited indicator.

Current coverage gaps:

- no test proves conditional `Edit` visibility for last-sent vs non-last vs
  incoming vs media-only rows
- no test proves Orbit edit-mode activation, cancel, or identical-text no-op
- no test proves Orbit routes an edit submit through the shared edit path
- no test proves Orbit cards render edited state

## Regression/tests to add first

- Add overlay/widget regressions for the new `Edit` affordance:
  - rendered when enabled
  - absent when disabled
  - callback fires and overlay dismiss behavior stays intact
- Add Orbit screen regressions that prove:
  - `Edit` appears only on the eligible last-sent text row
  - incoming, older sent, and media-only rows do not expose it
  - tapping `Edit` routes through the new Orbit callback path
- Add Orbit wired regressions that prove:
  - edit activation prefills composer text and requests focus
  - cancel exits edit mode without mutating the original row
  - unchanged text submit is a no-op
  - changed text submit calls the shared edit path and preserves the original
    message row identity
- Add `LetterCard` regressions for edited-indicator rendering.

Only add `ComposeArea` regressions if execution actually changes that widget.
Do not fabricate a composer refactor just to satisfy the likely-file list.

## Step-by-step implementation plan

1. Add the narrow conversation-specific localization strings needed for:
   - context-menu `Edit`
   - edit-mode banner/cancel text if the chosen Orbit UI needs them
   - edited indicator text
   Prefer conversation-specific keys over reusing posts/pinned-post strings.
2. Extend `MessageContextOverlay` with an optional `Edit` action seam.
   Keep reply/copy ordering and divider behavior honest when `Edit` is absent.
3. Teach `ConversationScreen` to compute edit eligibility from current message
   state:
   - outgoing only
   - last sent only
   - text-bearing rows only
   Route `Edit` taps through a new callback and reuse the existing focus
   request pattern already used by reply.
4. Add Orbit-owned edit state in `ConversationWired`.
   Prefer the smallest new state:
   - currently edited message identity / original text
   - activation handler
   - cancel handler
   - `_onSend(...)` branch that short-circuits unchanged text and otherwise
     calls the shared edit contract from Session `1`
   Reuse the existing `_draftText` plus `initialText` seam unless execution
   proves a tiny additional composer prop is needed.
5. Render an edited indicator in `LetterCard` for rows where `editedAt` is
   present.
   Keep delivery status, reactions, and quote/media layout unchanged.
6. Land direct Orbit/widget regressions alongside the implementation, then run
   the required named gates.
7. Stop if the work starts requiring feed thread-model edits, feed refresh
   behavior, or feed inline-composer state. That belongs to Session `3`.

## Risks and edge cases

- The long-press eligibility check can drift if it uses newest-overall instead
  of newest outgoing; Orbit must use the user's last sent row, even if a newer
  incoming message exists.
- A new edit callback seam can easily regress reply/copy overlay behavior if
  divider ordering or dismiss timing changes.
- Orbit edit mode must not send unchanged text or create a second message row.
- The edit submit path must preserve existing quoted/media associations by
  delegating to the shared edit contract instead of rebuilding a partial row in
  the UI layer.
- If a failed outgoing row is edited locally and remains `failed`, Orbit still
  needs to update the visible row in place; do not narrow repo-change refresh
  behavior while adding edit state.
- This session must not widen into feed inline-compose state, feed refresh
  parity, or group behavior.

## Exact tests and gates to run

Direct tests:

- `flutter test test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `flutter test test/features/conversation/presentation/widgets/compose_area_test.dart`
  only if `compose_area.dart` changes

Fast structural validation:

- `dart analyze lib/features/conversation/presentation/widgets/message_context_overlay.dart lib/features/conversation/presentation/screens/conversation_screen.dart lib/features/conversation/presentation/screens/conversation_wired.dart lib/features/conversation/presentation/widgets/letter_card.dart`
  plus any changed localization-generated files

Named gates:

- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh baseline`

Not required for Session `2` as currently scoped:

- `./scripts/run_test_gates.sh feed`
- `./scripts/run_test_gates.sh transport`

## Known-failure interpretation

- Session `1` already proved the current repo can pass `1to1` and `baseline`
  for the shared edit contract.
- In this local environment, `baseline` needs an explicit `FLUTTER_DEVICE_ID`
  for its `integration_test/` portion because Flutter aborts when multiple
  devices are available; that is an environment invocation issue, not a product
  failure.
- MacOS linker and deployment-target warnings observed during the explicit
  baseline run are not failing test results by themselves.
- Any new failure in the Orbit/widget suites or in the named gates after the
  Session `2` UI edits should be treated as a real Session `2` blocker unless
  it is reproduced on the already-accepted Session `1` state.

## Done criteria

- Orbit long-press exposes `Edit` only on the eligible last-sent text row.
- Tapping `Edit` prefills the composer and requests focus.
- Orbit exposes a cancel path out of edit mode.
- Orbit suppresses identical-text edit submits.
- Changed-text edit submits update the same row via the shared edit contract.
- Orbit cards render an edited indicator when `editedAt` is present.
- Direct Session `2` regressions pass.
- Companion `1to1` and `baseline` gates pass.

## Scope guard

- Do not add feed/stack edit affordances, feed inline edit state, or feed
  edited-indicator work in this session.
- Do not refactor the entire composer into a generic multi-mode framework if a
  bounded Orbit-only seam closes the feature honestly.
- Do not add delete semantics, edit history, undo, edit timers, or group edit
  support.
- Do not change the shared transport, retry, inbox, or dedup architecture from
  Session `1`.

## Accepted differences / intentionally out of scope

- Media-only rows remain non-editable; text+media rows only edit text.
- Feed parity remains intentionally deferred to Session `3`.
- This session may use a bounded Orbit-specific edit banner/state seam instead
  of forcing a new reusable cross-surface composer abstraction.
- Older clients may ignore edit semantics as already accepted by Session `1`;
  Session `2` only needs to stay stable on the current client.

## Dependency impact

- Session `3` depends on this session to prove the honest user-facing Orbit edit
  contract before feed parity is attempted.
- If execution discovers a shared widget seam that Session `3` should reuse,
  land it only if it closes Orbit safely now and does not force feed behavior
  changes in the same patch.
- If execution proves Orbit needs feed-thread or feed-refresh changes to work
  correctly, stop and refresh the breakdown instead of silently widening.

## Reviewer pass

- Sufficiency verdict:
  - sufficient with one caution
- Missing structural items:
  - none
- Required caution:
  - keep edit eligibility explicitly tied to "last sent" rather than "latest
    overall message"
  - do not introduce a generic composer-mode abstraction unless the minimal
    Orbit-host seam fails
- Overengineering to avoid:
  - feed parity work
  - generic cross-surface draft-stack preservation work
  - transport or repository redesign

## Arbiter outcome

- Structural blockers:
  - none
- Incremental details intentionally deferred:
  - whether `compose_area.dart` changes at all should be decided during
    execution, based on whether the existing `initialText` and focus seam is
    enough
- Accepted differences:
  - Orbit may use a bounded local edit-mode banner/state seam now; feed can
    reuse or replace it in Session `3` after refreshing against landed code
