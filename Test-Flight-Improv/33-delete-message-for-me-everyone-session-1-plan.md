# Session 1 Plan: Shared Delete Contract, Durable Queueing, and Recipient Tombstone Semantics

## Evidence collector summary

- `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
  marks Session `1` as the shared correctness seam that both UI surfaces
  depend on.
- `lib/features/conversation/domain/repositories/message_repository.dart` and
  `message_repository_impl.dart` already support local hard delete via
  `deleteMessage(id)`, but that helper is local-only and cannot represent a
  recipient tombstone or an offline delete-for-everyone retry.
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
  already has `_onDeleteFailedMedia(...)`, which proves the current local
  cleanup shape: delete pending files, delete attachment rows, delete the
  message row, and update local UI.
- `lib/features/conversation/domain/models/message_payload.dart` already carries
  shared send/edit semantics for `chat_message`, while
  `lib/core/services/incoming_message_router.dart` already routes by top-level
  message `type`; this makes a dedicated `message_deletion` envelope safer
  than overloading `chat_message` again.
- `lib/features/conversation/domain/models/conversation_message.dart` and the
  `messages` table currently have `edited_at` and `quoted_message_id`, but no
  deletion metadata. A recipient placeholder or sender-hidden tombstone cannot
  be represented yet.
- Quote-preview seams in `conversation_wired.dart` and
  `scrollable_message_preview.dart` already treat missing or empty parents as
  unavailable, so deleted-parent quote behavior can reuse an existing fallback
  contract if deleted rows are represented honestly.

## Real scope

- Add the shared DB/model metadata required to represent a deleted/tombstoned
  1:1 message row and distinguish it from a normal row.
- Introduce a dedicated `message_deletion` wire payload plus router/incoming
  handling for delete-for-everyone.
- Add shared application/use-case logic for:
  - local delete-for-me hard delete with media/reaction cleanup
  - delete-for-everyone sender flow that removes original content locally while
    keeping enough durable state to retry delivery offline
  - recipient-side authorized tombstone application with attachment cleanup
- Preserve quote-parent fallback semantics so deleted parents resolve as
  unavailable.

Out of real scope for this session:

- Exposing `Delete` in Orbit or feed UI.
- Designing the final bottom sheet/dialog or localization strings.
- Feed latest-message / empty-state rendering changes.
- Group delete, batch delete, undo, time limits, or contact-level delete work.

## Closure bar

- The messages schema and `ConversationMessage` can represent deleted/tombstone
  state without breaking existing load/order/replay semantics.
- `Delete for Me` is a shared local cleanup path: the message row is removed,
  attachment/reaction state is cleaned up, and the peer is untouched.
- `Delete for Everyone` uses a dedicated delete signal that can be retried
  offline and applied by the recipient without inventing a second transport
  architecture.
- Recipients only accept delete-for-everyone when the signal comes from the
  original sender of the message; missing or spoofed deletes do not crash and
  do not corrupt state.
- Deleted quoted parents resolve as unavailable via the shared data contract,
  even before Orbit/feed-specific placeholder rendering lands.
- Direct shared-contract regressions pass, plus `./scripts/run_test_gates.sh
  1to1` and explicit macOS `baseline`.

## Source of truth

- Active session contract:
  - `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
  - `Test-Flight-Improv/33-delete-message-for-me-everyone.md`
- Reused upstream surface context:
  - `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
  - `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md`
- Regression and gate authority:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Scope guard:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Current code and tests beat stale prose when they disagree.

## Session classification

`implementation-ready`

## Exact problem statement

- The repo has only local hard delete helpers today. There is no shared row
  contract for a deleted/tombstoned message, so delete-for-everyone cannot
  preserve offline durability and quote safety.
- There is no dedicated incoming delete signal type, so recipients cannot
  process remote deletion requests or reject spoofed ones.
- The current source doc mixes hard-delete disappearance with recipient
  placeholder behavior. For this architecture, a pure hard delete for
  delete-for-everyone is unsafe because it throws away the row that would
  otherwise carry durable retry state and quote fallback semantics.
- Session `1` must establish a single honest shared contract before any UI
  exposes `Delete`.

## Files and repos to inspect next

Exact production files:

- `lib/main.dart`
- `lib/core/database/migrations/043_messages_edited_at.dart`
- `lib/core/database/helpers/messages_db_helpers.dart`
- `lib/features/conversation/domain/models/conversation_message.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/core/services/incoming_message_router.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/domain/repositories/message_repository.dart`
- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- `lib/features/conversation/domain/repositories/reaction_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/core/media/media_file_manager.dart`

Exact direct tests:

- `test/core/database/migrations/043_messages_edited_at_test.dart`
- `test/core/database/helpers/messages_db_helpers_test.dart`
- `test/features/conversation/domain/models/message_payload_test.dart`
- `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_media_hydration_test.dart`
- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`

Infra/config files:

- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`

## Existing tests covering this area

- `test/core/database/helpers/messages_db_helpers_test.dart` already pins
  insert/load/delete helpers, replace-on-conflict behavior, and the current
  `edited_at` migration path.
- `test/features/conversation/domain/models/message_payload_test.dart` already
  covers send/edit payload serialization and parsing.
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
  already covers the durable send/edit contract, including preserved IDs,
  `wireEnvelope`, and offline/inbox fallback semantics.
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  already covers duplicate rejection and same-ID edit handling.
- `test/features/conversation/integration/two_user_message_exchange_test.dart`
  and `offline_inbox_roundtrip_test.dart` already prove cross-device delivery
  and inbox replay for the shared 1:1 transport path.

Current coverage gaps:

- no schema/helper test for deleted/tombstone metadata
- no payload test for a dedicated delete signal
- no shared use-case test for delete-for-me local cleanup
- no shared use-case/integration test for sender delete-for-everyone plus
  recipient tombstone application
- no auth test for spoofed delete signals
- no missing-message delete-signal test

## Regression/tests to add first

- Add DB/migration/helper regressions that prove:
  - deleted/tombstone metadata migrates cleanly on fresh install and upgrade
  - delete-for-me still hard-deletes the row
  - delete-for-everyone preserves a tombstone row with cleared content and
    stable identity
- Add payload/router regressions that prove:
  - a dedicated `message_deletion` payload round-trips
  - older `chat_message` payload behavior stays unchanged
- Add shared application regressions that prove:
  - delete-for-me performs local cleanup only
  - delete-for-everyone persists durable retry state locally
  - incoming delete-for-everyone only applies when the sender owns the target
    row
  - missing-message deletes are ignored without error
- Extend one or two 1:1 integration suites only after the unit/use-case seams
  are green, so cross-device/offline proof stays narrow and high-value.

## Step-by-step implementation plan

1. Define the shared row contract for delete-for-everyone.
   Use a tombstone-style message row for delete-for-everyone instead of a pure
   hard delete, so the app can preserve durable retry state, stable message ID,
   and quote-parent fallback semantics. Keep delete-for-me as a local hard
   delete.
2. Add the additive messages migration and model/repository plumbing.
   Introduce the next sequential migration, bump `lib/main.dart`, add row
   columns and model fields/getters, and thread the new fields through helper
   queries and repository snapshots.
3. Add the dedicated delete payload and incoming router seam.
   Prefer a new `message_deletion` type so older clients can ignore it safely
   via the unknown-type path instead of misparsing it as a normal chat row.
4. Implement shared delete application helpers/use cases.
   Reuse the failed-media delete cleanup shape for local deletion. Add a shared
   tombstone apply helper for delete-for-everyone that:
   - clears original text/media payload from the row
   - keeps enough metadata for placeholder rendering later
   - deletes attachment/reaction state
   - persists a delete envelope for retry until delivery succeeds
5. Implement authorized incoming delete processing.
   Validate the sender against the original row, ignore missing/spoofed
   deletes, and apply the tombstone cleanup to the recipient row.
6. Tighten direct regressions first, then extend one cross-device/offline
   integration proof.
7. Run named gates and update the Session `1` ledger only after the shared
   contract is truly stable.

## Risks and edge cases

- A pure hard delete for delete-for-everyone will likely destroy the only row
  currently carrying durable retry state; do not assume offline delivery still
  works unless the row contract proves it.
- Delete signals must not allow one contact to delete another sender's message.
- Attachment cleanup must distinguish local pending-upload files from durable
  downloaded media files and must not delete unrelated files.
- Reactions tied to a deleted row can become orphaned unless explicitly cleaned
  up.
- Latest-message summary queries may need to tolerate tombstone rows without
  breaking ordering or feed-thread projection.
- Quote-parent fallback must stay "unavailable" rather than leaking deleted
  content through old quoted text.

## Exact tests and gates to run

Direct tests:

- `flutter test test/core/database/helpers/messages_db_helpers_test.dart`
- `flutter test test/features/conversation/domain/models/message_payload_test.dart`
- `flutter test test/features/conversation/domain/repositories/message_repository_impl_test.dart`
- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`
- `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `flutter test test/features/conversation/application/handle_incoming_chat_message_media_hydration_test.dart`
- `flutter test test/features/conversation/integration/two_user_message_exchange_test.dart`
- `flutter test test/features/conversation/integration/offline_inbox_roundtrip_test.dart`

Named gates:

- `./scripts/run_test_gates.sh 1to1`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

Conditional:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` only if the
  implementation ends up editing bootstrap, reconnect, inbox-drain, or
  transport-fallback wiring outside the shared 1:1 send path.

## Known-failure interpretation

- No known red test is accepted for this session by default.
- If a direct suite or named gate fails, treat it as a session blocker unless
  the same failure is reproduced on the unchanged current branch and clearly
  does not involve the delete-contract seam.
- Do not drop `1to1` or `baseline` just because a narrower direct test went
  green; the point of this session is shared durability, not a local helper
  patch.

## Done criteria

- The DB/model/repository layer can represent deleted/tombstone rows without
  breaking existing load/order behavior.
- Delete-for-me hard-deletes locally with media/reaction cleanup.
- Delete-for-everyone persists a durable delete envelope locally, clears the
  original content, and can retry offline/inbox delivery.
- Recipient-side incoming delete processing is authorized, idempotent, and
  ignores missing/spoofed targets safely.
- Deleted parents resolve as unavailable through the shared data contract.
- All direct tests above pass, plus `./scripts/run_test_gates.sh 1to1` and
  explicit macOS `baseline`.
- The breakdown artifact is updated with an honest Session `1` verdict.

## Scope guard

- Do not add Orbit or feed delete buttons, dialogs, or placeholder visuals in
  this session.
- Do not widen into group delete, contact-level delete, or failed-media UX
  redesign.
- Do not invent a second durable queue table unless the row-based tombstone
  contract is disproven by repo evidence during implementation.
- Do not touch `Test-Flight-Improv/test-gate-definitions.md` unless execution
  truly changes classification rules.

## Accepted differences / intentionally out of scope

- Delete-for-everyone uses a tombstone-style durable row contract in this
  session rather than a pure hard delete, because the source doc's offline
  durability requirement and placeholder requirement conflict with immediate
  row removal.
- Older clients may ignore `message_deletion` as an unknown type as long as
  they do not crash.
- Final placeholder copy and surface-specific delete affordances wait for
  Sessions `2` and `3`.

## Dependency impact

- Session `2` depends on this plan landing a stable shared delete API plus
  row/rendering metadata for Orbit UI.
- Session `3` depends on this plan landing shared quote/unavailable semantics
  and durable delete state that feed can project and render.
- If implementation evidence disproves the tombstone-row contract, stop and
  refresh the Session `2` and `3` assumptions before coding further.

## Final verdict

`sufficient`

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- Exact localization keys and delete-sheet wording belong to Session `2`.
- Feed latest-message / empty-state wording belongs to Session `3`.

## Accepted differences intentionally left unchanged

- Group delete remains out of scope.
- Batch delete, undo, and time limits remain out of scope.
- Contact-level delete continues using its current full-thread deletion path.

## Exact docs/files used as evidence

- `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
- `Test-Flight-Improv/33-delete-message-for-me-everyone.md`
- `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `lib/features/conversation/domain/models/conversation_message.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/core/services/incoming_message_router.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- `lib/core/database/helpers/messages_db_helpers.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `test/core/database/helpers/messages_db_helpers_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`

## Why the plan is safe to implement now

- The plan isolates the shared contract before any UI work, which matches the
  repo's existing edit/send rollout pattern and minimizes hallucination.
- It makes the key architecture choice explicit: delete-for-everyone needs a
  durable tombstone contract, not an immediate hard delete, to satisfy offline
  retry and quote safety together.
- The regression contract is concrete and tied to existing repo seams, so
  implementation can be stopped if the evidence disproves the chosen contract.
