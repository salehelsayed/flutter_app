# 33 - Delete Message For Me / Everyone Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/33-delete-message-for-me-everyone.md`
- Decomposition date:
  `2026-03-31`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `3`
- The smallest safe split is one shared deletion-contract session, one
  Orbit/shared-overlay delete-UX session, and one feed-parity/final-acceptance
  session.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Retry attempts used | Final execution verdict | Blocker class | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | Shared delete contract, durable queueing, and recipient tombstone semantics | `implementation-ready` | `Test-Flight-Improv/33-delete-message-for-me-everyone-session-1-plan.md` | none | `accepted` | `0` | `accepted` | none | `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md` | Accepted on `2026-03-31` after landing the deleted-row migration/model/repository contract, the dedicated `message_deletion` payload/router/listener/use-case path, and shared cleanup semantics, then verifying `dart analyze`, the direct Session `1` shared-contract suites, `./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. |
| `2` | Shared delete affordance and Orbit conversation delete UX | `implementation-ready` | `Test-Flight-Improv/33-delete-message-for-me-everyone-session-2-plan.md` | `1` | `accepted` | `1` | `accepted` | none | `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md` | Accepted on `2026-03-31` after landing the shared delete overlay action, the Orbit delete sheet/gating/rendering flow, deleted-row placeholder behavior, and the repo-change refresh cleanup path, then verifying focused `message_context_overlay`, `conversation_screen`, `conversation_wired`, and `letter_card` suites plus `./scripts/run_test_gates.sh 1to1` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. A single bounded local fallback was used after the spawned Session `2` planning/execution path no-progressed. |
| `3` | Feed parity, quoted-message fallout, and final acceptance | `implementation-ready` | `Test-Flight-Improv/33-delete-message-for-me-everyone-session-3-plan.md` | `2` | `accepted` | `1` | `accepted` | none | `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md` | Accepted on `2026-03-31` after landing feed delete affordance parity, deleted latest-message fallback, deleted quoted-parent unavailable handling, and feed-side delete refresh cleanup, then verifying the direct Session `3` feed suites plus `./scripts/run_test_gates.sh feed`, `./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. A single bounded local execution fallback was used after the spawned Session `3` execution step no-progressed due to an agent usage-limit error. |

## Overall closure bar

Report `33` is closed only when current 1:1 message surfaces expose one honest
delete contract without reopening unrelated 1:1 reliability, group, or
contact-delete scope:

- long-press on an eligible 1:1 message exposes `Delete` alongside the
  existing reaction/reply/copy/edit overlay contract
- the delete confirmation surface offers one honest choice set:
  `Delete for Me`, `Delete for Everyone` only when the sender can legitimately
  unsend, and `Cancel`
- local-only delete removes the row and cleans up local attachment/reaction
  state without touching the peer
- delete-for-everyone reuses a durable shared contract so the sender stops
  showing the original content, the recipient gets a tombstone/placeholder
  instead of the original content, and offline/inbox fallback still works
- deleted quoted parents render as unavailable in quote previews rather than
  leaking original text/media
- Orbit and feed surfaces stay in parity for delete affordance, delete results,
  latest-message updates, and empty-state transitions
- group conversations, batch delete, undo, time limits, and contact-level
  delete semantics remain out of scope

## Final program acceptance

- Closure verdict:
  `closed`
- Acceptance date:
  `2026-03-31`
- What is now closed:
  - eligible 1:1 message surfaces now expose one honest delete contract across
    Orbit and feed, including `Delete for Me`, conditional `Delete for
    Everyone`, and `Cancel`
  - sender-side delete-for-me and delete-for-everyone flows now keep feed
    projections honest by removing stale latest-message, preview, quote, and
    composer state after local or shared delete fallout lands
  - deleted quoted parents now resolve to unavailable state instead of leaking
    original content on current 1:1 conversation and feed surfaces
  - the shared contract, Orbit UX, and feed parity path all passed the
    required direct suites plus the named `feed`, `1to1`, and `baseline`
    gates, so report `33` closes on the current repo state
- Residual-only items:
  - none
- Still-open items:
  - none
- Reopen only on real regression:
  - if eligible 1:1 feed or Orbit message surfaces stop exposing the shared
    delete affordance/confirmation contract
  - if delete-for-me or delete-for-everyone leaves stale latest-message,
    quote-preview, composer, or empty-state behavior behind on feed or
    conversation surfaces
  - if deleted quoted parents start leaking original text/media again instead
    of resolving to unavailable state
  - if the direct delete regressions or the named `feed`, `1to1`, or
    `baseline` gates stop passing after future changes in this area

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/33-delete-message-for-me-everyone.md`
- `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`

Current repo facts that governed the split:

- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  already implements the shared long-press overlay with `Reply`, conditional
  `Copy`, and conditional `Edit`, so delete should extend that seam rather than
  reintroducing an older reaction-bar-only interaction path.
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
  and `lib/features/feed/presentation/screens/feed_screen.dart` already host
  that shared overlay contract, which means delete UX should stay shared where
  possible and split only where host-specific state differs.
- `lib/features/conversation/domain/repositories/message_repository.dart` and
  `message_repository_impl.dart` already expose local hard-delete helpers, but
  they are local-only and do not provide recipient tombstones, durable delete
  signaling, or sender/recipient authorization semantics.
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
  already contains a failed-media delete cleanup cascade that proves the
  current local message/media cleanup seam; Session `1` should reuse that shape
  rather than invent a second cleanup architecture.
- `lib/features/conversation/domain/models/message_payload.dart` already uses
  an action-aware send/edit contract for `chat_message`, and
  `lib/core/services/incoming_message_router.dart` already routes distinct
  message `type` streams. That means delete can use either a dedicated payload
  type or another action-aware extension, but the router and backward-compat
  behavior must be planned explicitly.
- `lib/features/conversation/domain/models/conversation_message.dart` and the
  messages table currently carry `edited_at` and `quoted_message_id` but no
  deletion metadata, so sender-hidden vs recipient-tombstone behavior is a
  shared persistence concern, not a pure UI toggle.
- Quote-preview seams already treat a missing or empty quoted parent as
  unavailable in `conversation_wired.dart`,
  `scrollable_message_preview.dart`, and the related compose/message-bubble
  tests, which makes deleted-parent quote fallout a real but bounded extension
  of existing unavailable-quote behavior rather than a brand-new rendering
  system.
- `Test-Flight-Improv/test-gate-definitions.md` keeps notification and other
  cross-feature suites outside the frozen gates, while shared 1:1 contract
  changes still belong to `1to1`, feed surface changes belong to `feed` with
  companion `1to1` when feed-originated send/delete paths move, and broad
  startup/bootstrap changes would still pull in `baseline` or `transport`.

Source-of-truth conflicts that materially affected decomposition:

- The source report mixes hard-delete wording ("message disappears") with a
  recipient placeholder requirement. Planning must choose one honest shared row
  contract that preserves offline durability and quote/unavailable semantics
  instead of trying to satisfy both with contradictory storage behavior.
- The source report starts from stale context-menu prose. Current repo state
  already has the shared overlay contract from Reports `26` and `31`, so this
  feature should extend that seam rather than inventing a second delete-only
  interaction surface.

## Reviewer pass

- Sufficiency:
  `3` sessions is sufficient. Fewer sessions would bundle a new shared
  persistence/wire authorization seam together with two different UI host
  families; more sessions would split tightly coupled delete-for-me /
  delete-for-everyone / tombstone work without improving independent
  verification.
- Merge candidates:
  none.
- Required splits:
  none.
- Missing tests or named gates:
  none at decomposition time. The execution plans still need direct shared
  contract regressions, Orbit presentation regressions, feed regressions, and
  the named gates called out below.
- Meaningful verified state:
  yes. Session `1` can land a reusable delete contract with no surface work,
  Session `2` can prove Orbit/shared-overlay behavior on top of that contract,
  and Session `3` can prove feed parity plus final cross-surface closure.
- Matrix responsibility:
  clear. No stable delete-feature closure reference exists for this area yet,
  so this breakdown artifact is the live doc-scoped ledger.
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
  - group delete remains out of scope
  - batch delete, undo, time limits, and edit-history style recovery remain
    out of scope
  - older clients may ignore an unknown delete signal as long as they do not
    crash
  - sender-side delete-for-everyone may need to reuse a tombstone-style row or
    equivalent hidden durable record if current queue semantics require it; the
    planning step must make that contract explicit instead of silently assuming
    a pure hard delete can still queue offline delivery

## Ordered session breakdown

### Session 1

- Title:
  `Shared delete contract, durable queueing, and recipient tombstone semantics`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/33-delete-message-for-me-everyone-session-1-plan.md`
- Exact scope:
  - add the shared persistence/model metadata needed for local delete-for-me
    and delete-for-everyone semantics, including any deletion timestamp /
    tombstone / sender-hidden state required by the current durable queue model
  - introduce the delete wire contract and router/incoming handling needed for
    recipient-side delete-for-everyone processing with sender authorization
  - reuse the current local message/media/reaction cleanup seams so local
    delete and remote tombstone application both clean up attachment state
    honestly
  - preserve quote-parent fallback behavior so deleted parents resolve as
    unavailable rather than leaking prior content
  - keep group, contact-level delete, and failed-media delete semantics
    unchanged except where the shared cleanup helpers become reusable
- Why it is its own session:
  - this is the shared correctness seam that both UI surfaces depend on
  - it has a distinct direct regression family: DB/model/payload/router/use
    case behavior, not presentation behavior
  - it must be proven before either surface starts exposing a `Delete`
    affordance
- Likely code-entry files:
  - `lib/core/database/migrations/002_messages_table.dart`
  - `lib/core/database/helpers/messages_db_helpers.dart`
  - `lib/features/conversation/domain/models/conversation_message.dart`
  - `lib/features/conversation/domain/models/message_payload.dart`
  - `lib/core/services/incoming_message_router.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `lib/features/conversation/domain/repositories/message_repository.dart`
  - `lib/features/conversation/domain/repositories/message_repository_impl.dart`
  - `lib/features/conversation/domain/repositories/reaction_repository.dart`
  - `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- Likely direct tests/regressions:
  - `test/core/database/helpers/messages_db_helpers_test.dart`
  - `test/features/conversation/domain/models/message_payload_test.dart`
  - `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
  - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  - `test/features/conversation/application/handle_incoming_chat_message_media_hydration_test.dart`
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `test/features/conversation/integration/two_user_message_exchange_test.dart`
  - `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` only if execution unexpectedly
    edits bootstrap, reconnect, inbox-drain, or transport-fallback wiring
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact's session ledger
  - keep `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    as a scope guard only unless shared reliability semantics truly reopen
- Dependency on earlier sessions:
  - none

### Session 2

- Title:
  `Shared delete affordance and Orbit conversation delete UX`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/33-delete-message-for-me-everyone-session-2-plan.md`
- Exact scope:
  - extend the shared long-press overlay/localization surface with a
    conditional `Delete` action alongside the already-landed `Reply`, `Edit`,
    and `Copy` actions
  - add the delete confirmation sheet/dialog and Orbit-side ownership/status
    gating for `Delete for Me`, `Delete for Everyone`, and `Cancel`
  - wire Orbit delete actions through the shared Session `1` contract,
    including failed-message constraints, local cleanup, and recipient
    tombstone results
  - render deleted-message placeholders or sender-hidden behavior honestly in
    Orbit rows without breaking reply/copy/reaction behavior on unaffected rows
- Why it is its own session:
  - this is the first surface host seam on top of the shared contract
  - it has a distinct direct regression family in shared overlay and Orbit
    presentation tests
  - it can land and be verified before feed parity work starts
- Likely code-entry files:
  - `lib/l10n/app_en.arb`
  - `lib/l10n/app_de.arb`
  - `lib/l10n/app_ar.arb`
  - `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/conversation/presentation/widgets/letter_card.dart`
  - `lib/features/conversation/presentation/widgets/compose_area.dart`
- Likely direct tests/regressions:
  - `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `test/features/conversation/presentation/widgets/letter_card_test.dart`
  - `test/features/conversation/presentation/widgets/compose_area_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact's session ledger
- Dependency on earlier sessions:
  - `1`

### Session 3

- Title:
  `Feed parity, quoted-message fallout, and final acceptance`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/33-delete-message-for-me-everyone-session-3-plan.md`
- Exact scope:
  - extend feed/stack cards with the shared `Delete` action and delete
    confirmation flow using the accepted Session `1` contract
  - render deleted latest messages, placeholder/hidden results, and next-latest
    fallback honestly in feed cards and previews
  - ensure quote previews on feed surfaces show unavailable when the quoted
    parent has been deleted, and keep message-bubble affordance gating honest
  - prove feed updates correctly when the latest or only message is deleted,
    including empty-state / next-latest transitions
  - finish the final report-33 acceptance/closure pass
- Why it is its own session:
  - feed has its own projection, preview, latest-message, and open-mode card
    seams distinct from Orbit
  - it needs its own direct regression family plus the `feed` named gate
  - the final acceptance decision depends on both surfaces being in parity
- Likely code-entry files:
  - `lib/features/feed/domain/models/feed_item.dart`
  - `lib/features/feed/domain/utils/group_messages_into_threads.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
  - `lib/features/feed/presentation/widgets/message_bubble.dart`
- Likely direct tests/regressions:
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`
  - `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
  - `test/features/feed/presentation/widgets/message_bubble_test.dart`
  - `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
  - `test/features/feed/integration/expanded_collapsed_card_test.dart`
  - `test/features/feed/integration/feed_card_flow_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh feed`
  - companion `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact's session ledger
  - update folder-level closure docs only if the final closure audit finds
    stale status outside this report
- Dependency on earlier sessions:
  - `2`

## Why this is not fewer sessions

- Session `1` changes the shared persistence/wire/authorization contract. It
  must be verified with DB/model/router/use-case tests and named gates before
  any surface starts exposing `Delete`.
- Session `2` changes the shared overlay plus Orbit delete-flow/rendering seam.
  Combining that with Session `1` would bundle correctness and surface work
  into one broad patch with weaker failure isolation.
- Session `3` still has a separate feed host seam: thread projection, latest
  preview fallout, feed open-mode affordance gating, and empty-state updates.
  Merging it into Session `2` would mix two different surface families and
  make the feed gate/final acceptance decision harder to audit.

## Why this is not more sessions

- Splitting delete-for-me and delete-for-everyone into separate shared sessions
  would create bookkeeping without a meaningful independently verified state;
  both rely on the same message-deletion metadata and cleanup seams.
- Splitting Orbit delete affordance away from its confirmation sheet and row
  rendering would leave a misleading half-feature on the first surface.
- Splitting feed quote fallout away from latest-message / empty-state fallout
  would be hallucination bait; they are part of the same feed projection and
  rendering seam.

## Regression and gate contract

- Session `1` must add or tighten the direct shared-contract regressions first,
  then run the targeted DB/model/router/application suites, then
  `./scripts/run_test_gates.sh 1to1`, then
  `./scripts/run_test_gates.sh baseline`.
- Session `2` must prove the shared overlay/Orbit delete behavior in targeted
  presentation suites and run companion `./scripts/run_test_gates.sh 1to1`
  plus `./scripts/run_test_gates.sh baseline`.
- Session `3` must prove feed parity in the targeted feed suites, then run
  `./scripts/run_test_gates.sh feed`, companion
  `./scripts/run_test_gates.sh 1to1`, and
  `./scripts/run_test_gates.sh baseline`.
- `./scripts/run_test_gates.sh transport` is out unless a session unexpectedly
  edits bootstrap, reconnect, inbox-drain, or transport-fallback wiring.
- `./scripts/run_test_gates.sh completeness-check` is only required if a
  session edits `Test-Flight-Improv/test-gate-definitions.md` or reclassifies
  tests.

## Matrix update contract

- No stable delete-message closure reference exists for this area yet, so this
  breakdown artifact is the live doc-scoped ledger during rollout.
- The final closure pass may update `Test-Flight-Improv/00-INDEX.md` or
  `Test-Flight-Improv/17-roadmap-closure-audit.md` if folder-level closure
  state would otherwise stay stale.
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` stays
  a scope guard, not the closure owner for Report `33`, unless execution
  proves a real shared reliability reopening.

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

- group delete remains out of scope
- batch delete, undo, and time limits remain out of scope
- contact-level delete and failed-media delete flows remain supported through
  their existing product surfaces
- older clients may ignore unknown delete signals as long as they stay stable

## Exact docs/files used as evidence

- `Test-Flight-Improv/33-delete-message-for-me-everyone.md`
- `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `lib/features/conversation/domain/models/conversation_message.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/core/services/incoming_message_router.dart`
- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `test/features/conversation/presentation/widgets/compose_area_test.dart`
- `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
