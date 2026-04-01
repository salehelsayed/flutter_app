# Session 2 Plan: Shared Delete Affordance and Orbit Conversation Delete UX

## Evidence collector summary

- Session `1` is now accepted in
  `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`,
  so the shared delete contract already exists: local delete-for-me hard
  delete, delete-for-everyone durable tombstones, recipient authorization, and
  hidden sender-side retry rows.
- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  currently exposes `Reply`, conditional `Edit`, and conditional `Copy`; it
  has no `Delete` action or danger-action styling.
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
  already owns the long-press overlay routing, message-level action gating,
  copy snackbar, and Orbit quote-preview resolution. It does not yet consume
  the new `isDeleted` metadata or expose a delete callback.
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
  already owns Orbit draft/edit state, failed-media local delete cleanup, and
  the current dialog/sheet host seams. It does not yet own any message-delete
  confirmation flow or call the shared Session `1` delete use cases.
- `lib/features/conversation/presentation/widgets/letter_card.dart` already
  renders edited state and unavailable quoted-parent copy, but it has no
  deleted-message placeholder body and no deleted-row interaction policy.
- `lib/features/conversation/domain/models/conversation_message.dart` now
  exposes `isDeleted` and `isHidden`, and visible conversation loaders already
  exclude hidden rows. That means sender-side delete-for-everyone disappearance
  should come "for free"; Session `2` mainly needs the Orbit affordance,
  confirmation, and recipient tombstone rendering.
- Existing Orbit presentation tests already cover the long-press overlay,
  edit-mode activation, failed-media delete cleanup, reply/copy behavior, and
  empty-state rendering, so Session `2` can extend those suites instead of
  inventing new test surfaces.

## Real scope

- Add a conditional `Delete` action to the shared long-press overlay for Orbit
  conversation rows.
- Add one honest Orbit-hosted delete confirmation surface with:
  - `Delete for Me`
  - `Delete for Everyone` only when the shared contract allows it
  - `Cancel`
- Wire Orbit delete actions through the accepted Session `1` contract:
  - local delete-for-me for incoming, outgoing, failed, and other local-only
    rows
  - delete-for-everyone only for eligible outgoing delivered rows
- Render recipient-side deleted-message tombstones honestly in Orbit with a
  placeholder instead of leaked original text/media.
- Keep Orbit quote fallback honest when the quoted parent exists locally as a
  deleted tombstone rather than a missing row.

Out of real scope for this session:

- Feed/stack delete affordances, feed latest-message fallout, feed empty-state
  transitions, or final doc acceptance. That belongs to Session `3`.
- Reopening the shared delete wire/persistence contract from Session `1`
  unless execution finds a real Orbit-blocking bug in the landed code.
- Group delete, contact-level delete, batch delete, undo, time limits, or a
  generic cross-surface delete framework.
- A second tombstone interaction design for deleted rows. A bounded inert
  placeholder is acceptable for Orbit if that is the smallest honest surface.

## Closure bar

- Long-press on an eligible Orbit 1:1 message exposes `Delete` alongside the
  existing shared overlay actions without regressing reactions, reply, copy, or
  edit on unaffected rows.
- Tapping `Delete` opens one Orbit-hosted confirmation flow that offers:
  - `Delete for Me` for locally deletable rows
  - `Delete for Everyone` only for outgoing delivered non-deleted rows that the
    sender owns
  - `Cancel` with no state change
- `Delete for Me` removes the row locally through the shared cleanup path,
  including failed/media rows, and Orbit reflows or reaches empty state
  honestly.
- `Delete for Everyone` hides the sender row locally via the shared hidden-row
  contract and leaves recipient tombstones rendering as placeholders instead of
  blank cards.
- Orbit quote previews treat deleted quoted parents as unavailable rather than
  silently dropping the quote bar or leaking old content.
- Direct Orbit/widget regressions pass, plus companion `1to1` and explicit
  macOS `baseline`.

## Source of truth

- Active session contract:
  - `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
  - `Test-Flight-Improv/33-delete-message-for-me-everyone.md`
- Reused overlay and Orbit host context:
  - `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
  - `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md`
- Regression and gate authority:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Scope guard:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Current code and tests beat stale prose when they disagree.
- ARB files are the localization source of truth; generated localization Dart
  files should update only as required by the new delete strings.

## Session classification

`implementation-ready`

## Exact problem statement

- The shared delete contract now exists, but Orbit still has no user-visible
  way to enter it because the shared long-press overlay exposes no `Delete`
  affordance.
- Orbit also lacks a delete confirmation host, so there is no honest place to
  express the row-level choice between local delete and delete-for-everyone.
- Recipient-side tombstones currently arrive as empty-text, empty-media rows,
  but Orbit does not render them as deleted placeholders yet.
- Orbit quote rendering currently distinguishes missing quoted parents from
  present ones; if a quoted parent survives as a deleted tombstone, the screen
  still needs to render that quote as unavailable instead of silently dropping
  it.
- Session `2` must close the shared-overlay and Orbit-host seam without
  widening into feed parity or shared transport redesign.

## Files and repos to inspect next

Exact production files:

- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/conversation/domain/models/conversation_message.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_de.arb`
- `lib/l10n/app_ar.arb`
- generated localization outputs under `lib/l10n/` only if the ARB changes
  require them
- `lib/features/conversation/presentation/widgets/compose_area.dart` only if
  execution needs a bounded quote-preview copy or draft-state adjustment

Exact direct tests:

- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/features/conversation/presentation/widgets/compose_area_test.dart`
  only if `compose_area.dart` changes

## Existing tests covering this area

- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
  already proves reply/copy/edit action rendering and overlay dismissal.
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  already proves long-press overlay visibility, edit gating for last-sent rows,
  copy behavior, unavailable quote rendering for missing parents, and failed
  media controls.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  already proves Orbit edit-mode activation, identical-text no-op handling,
  failed-media delete cleanup, and long-press reply behavior.
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
  already proves edited indicators, quote-bar rendering, and failed-media
  action controls.

Current coverage gaps:

- no test proves the shared overlay renders `Delete` or keeps its ordering
  honest when `Delete` is absent
- no test proves Orbit exposes `Delete` for received and sent rows while
  withholding delete-for-everyone for incoming/failed/sending rows
- no test proves Orbit cancel vs delete-for-me vs delete-for-everyone routing
- no test proves recipient tombstones render a deleted placeholder instead of a
  blank card
- no test proves Orbit quote bars treat deleted quoted parents as unavailable

## Regression/tests to add first

- Add overlay/widget regressions for the new `Delete` affordance:
  - rendered when enabled
  - absent when disabled
  - callback fires
  - existing reply/edit/copy actions still render in the intended order
- Add Orbit screen regressions that prove:
  - long-press on normal visible rows exposes `Delete`
  - delete remains available for incoming and outgoing rows
  - deleted placeholders stay inert or otherwise avoid leaking copy/edit affordances
  - quoted rows whose parent is deleted render `Message unavailable`
- Add Orbit wired regressions that prove:
  - tapping `Delete` opens the confirmation surface
  - incoming and failed/sending outgoing rows only offer `Delete for Me`
  - eligible outgoing delivered rows offer `Delete for Everyone`
  - cancel is a no-op
  - delete-for-me removes the row locally and updates empty state when needed
  - delete-for-everyone routes through the shared delete path and hides the
    sender row locally
  - recipient tombstones render the deleted placeholder on the visible row
- Add `LetterCard` regressions for deleted placeholder rendering if execution
  adds an explicit card prop/seam.

Only add `ComposeArea` regressions if execution actually changes that widget.
Do not fabricate a composer refactor just to satisfy the likely-file list.

## Step-by-step implementation plan

1. Add the narrow conversation delete localization strings.
   Include:
   - context-menu `Delete`
   - delete-sheet title/body and action labels
   - deleted-message placeholder copy
   Prefer conversation-scoped keys over reusing contact-delete strings.
2. Extend `MessageContextOverlay` with an optional `Delete` action seam.
   Keep reply/edit/copy behavior intact and add `Delete` as the bounded danger
   action rather than reordering the non-danger actions.
3. Teach `ConversationScreen` the new Orbit delete eligibility and deleted-row
   rendering rules.
   Prefer the smallest policy:
   - normal visible 1:1 rows can expose the delete action
   - system intro rows remain outside the delete affordance
   - deleted tombstones either stay inert or expose only the bounded behavior
     needed by the chosen Orbit contract
   - quote-preview resolution treats deleted/empty quoted parents as
     unavailable
4. Add Orbit-hosted delete flow in `ConversationWired`.
   Reuse the existing host-state pattern from edit/failed-media actions:
   - add injectable delete callbacks/typedefs if tests need seams comparable to
     `editChatMessageFn`
   - resolve the pressed row from current `_messages`
   - show one bounded confirmation dialog/bottom sheet
   - call `deleteMessageForMe(...)` or `deleteMessageForEveryone(...)`
   - update local state via repo changes and/or immediate `_messages` refresh
     without inventing a second state container
5. Render recipient tombstones honestly in `LetterCard`/Orbit list rendering.
   Show a localized deleted placeholder for visible deleted rows, suppress old
   text/media leakage, and keep sender-hidden rows invisible via the existing
   query contract.
6. Land direct Orbit/widget regressions alongside the implementation, then run
   the required named gates.
7. Stop if the work starts requiring feed thread-projection changes, feed
   latest-message fallbacks, or final doc closure logic. That belongs to
   Session `3`.

## Risks and edge cases

- Delete-for-everyone eligibility must stay aligned with the shared Session `1`
  contract: outgoing, sender-owned, delivered, and not already deleted.
- Orbit must not accidentally expose delete affordances on system rows or other
  non-user messages just because long-press plumbing is shared.
- A deleted tombstone with empty text/media can otherwise render as an almost
  blank card; the Orbit placeholder must be explicit.
- Quote fallback can drift if the screen only treats missing quoted parents as
  unavailable. Deleted-but-present parents need the same unavailable outcome.
- Failed-media inline delete controls already exist; do not regress or replace
  them while adding the long-press delete path.
- This session must not invent a reusable feed/orbit delete-state framework if
  a bounded Orbit-host seam closes the feature honestly now.

## Exact tests and gates to run

Direct tests:

- `flutter test --no-pub test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `flutter test --no-pub test/features/conversation/presentation/widgets/letter_card_test.dart`
- `flutter test --no-pub test/features/conversation/presentation/widgets/compose_area_test.dart`
  only if `compose_area.dart` changes

Fast structural validation:

- `dart analyze lib/features/conversation/presentation/widgets/message_context_overlay.dart lib/features/conversation/presentation/screens/conversation_screen.dart lib/features/conversation/presentation/screens/conversation_wired.dart lib/features/conversation/presentation/widgets/letter_card.dart`
  plus any changed localization-generated files

Named gates:

- `./scripts/run_test_gates.sh 1to1`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

## Known-failure interpretation

- No known red test is accepted for this session by default.
- If a direct suite or named gate fails, treat it as a session blocker unless
  the same failure reproduces unchanged on the current branch and clearly does
  not involve the Orbit delete seam.
- Do not skip `1to1` or `baseline` just because the Orbit widget tests are
  green; the shared delete affordance now reaches the accepted Session `1`
  contract and needs the maintenance gates.

## Done criteria

- Orbit long-press exposes a shared overlay `Delete` action with honest gating.
- Orbit delete confirmation offers the correct option set for incoming,
  outgoing, and failed/sending states.
- Local delete removes the row and preserves unaffected conversation behavior.
- Delete-for-everyone hides sender content locally and recipient tombstones
  render a localized placeholder.
- Deleted quoted parents render as unavailable on Orbit surfaces.
- All direct tests above pass, plus `./scripts/run_test_gates.sh 1to1` and
  explicit macOS `baseline`.
- The breakdown artifact is updated with an honest Session `2` verdict.

## Scope guard

- Do not add feed/stack delete affordances, feed preview fallback logic, or
  feed empty-state transitions in this session.
- Do not redesign the shared delete wire contract, inbox retry behavior, or
  hidden-row persistence from Session `1` unless Orbit execution proves a real
  blocking bug.
- Do not refactor the entire long-press overlay into a generic action system if
  a bounded delete seam closes the Orbit requirement.
- Do not widen into group delete, contact delete, undo, timers, or message
  history.

## Accepted differences / intentionally out of scope

- A bounded Orbit dialog or bottom sheet is acceptable; this session does not
  need to standardize a new app-wide multi-action confirmation component.
- Visible deleted tombstones may remain non-interactive in Orbit if that is the
  smallest honest way to avoid leaking reactions/copy/edit behavior on deleted
  content.
- Failed and sending rows may stay local-delete-only, matching the accepted
  shared contract.
- Feed parity remains intentionally deferred to Session `3`.

## Dependency impact

- Session `3` depends on this session to land the shared overlay `Delete`
  affordance and honest Orbit delete rendering before feed parity starts.
- If execution extracts a small overlay/localization seam that feed can reuse
  safely, land it only if it closes Orbit now without forcing feed behavior
  changes in the same patch.
- If execution proves Orbit needs feed-thread or feed-latest-message changes to
  behave honestly, stop and refresh the breakdown instead of silently widening.

## Reviewer pass

- Sufficiency verdict:
  - sufficient with one caution
- Missing structural items:
  - none
- Required caution:
  - keep delete-for-everyone gating explicitly aligned with the landed shared
    use-case contract instead of re-deriving a looser UI rule
  - keep deleted quoted-parent handling explicit so placeholder rows do not
    silently collapse quote previews
- Overengineering to avoid:
  - feed parity work
  - app-wide delete framework work
  - transport/retry redesign

## Arbiter outcome

- Structural blockers:
  - none
- Incremental details intentionally deferred:
  - whether `compose_area.dart` changes at all should be decided during
    execution, based on whether the existing quote-preview seam is already
    enough
- Accepted differences:
  - Orbit may use the smallest honest delete confirmation host now; feed can
    reuse or replace it in Session `3` after refreshing against landed code
  - deleted tombstones can stay visible placeholders without introducing a new
    inline tombstone action surface

## Final verdict

`sufficient`
