# Session 1 Plan: Shared Editable-Message Persistence and Wire Contract

## Evidence collector summary

- `ConversationMessage` has no edit metadata today, so neither DB rows nor UI
  projections can represent "edited" state yet.
- `MessagePayload` has no action discriminator, so the wire format cannot tell
  a normal new message from an edit update.
- `handleIncomingChatMessage(...)` still treats any same-ID incoming payload as
  `duplicate`, which preserves real deduplication but blocks receiver-side edit
  updates.
- `dbInsertMessage(...)` already uses `ConflictAlgorithm.replace`, and the
  helper tests already prove same-ID upsert behavior. The missing work is the
  edit contract around that upsert, not row replacement itself.
- `sendChatMessage(...)` already supports caller-provided `messageId` and
  `timestamp`, plus the existing direct/send-or-inbox fallback, so Session 1
  should reuse that path rather than inventing a second transport architecture.
- `ThreadFeedItem.lastSentMessage` already exists on the feed side, so this
  session does not need to widen into a new "latest sent" repository query
  unless execution evidence disproves the local-derivation path.

## Real scope

- Add the shared persistence and wire contract needed to edit an existing 1:1
  message row in place.
- Add the message edit metadata (`edited_at` and model wiring) needed for later
  Orbit/feed rendering.
- Add the wire discriminator and receiver-side handling needed to distinguish
  edit updates from genuine duplicate new-message deliveries.
- Reuse the existing shared 1:1 send / queue / inbox fallback path for edits.

## Closure bar

- A local edit can update the same 1:1 message ID without creating a second DB
  row and without changing the original user-visible message ordering.
- The shared model and row mapping persist an edit timestamp.
- The wire format can distinguish `send` from `edit` without regressing normal
  new-message behavior.
- Receiver-side handling updates an existing message on edit while keeping real
  duplicate new-message rejection intact.
- Direct DB/model/application regressions land for the edit contract, and the
  required named gates pass.

## Source of truth

- Active session contract:
  - `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md`
  - `Test-Flight-Improv/31-edit-last-sent-message.md`
- Reused upstream UI/scope context:
  - `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- Regression/gate authority:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Scope guard:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Current code and tests beat stale prose when they disagree.
- If `test-gate-definitions.md` and `./scripts/run_test_gates.sh` disagree, the
  script wins.

## Session classification

`implementation-ready`

## Exact problem statement

- The repo can replace a same-ID row, but it has no supported notion of "this
  payload is an edit of an existing message" across model, DB, send, and
  receive layers.
- Without edit metadata, later Orbit/feed sessions cannot render an edited
  indicator or preserve edit state across reloads.
- Without an action discriminator, receiver-side dedup cannot distinguish a
  legitimate edit update from a real duplicate new-message delivery.
- Session 1 must land one shared edit contract without widening into
  conversation/feed UI affordances, delete semantics, groups, or edit history.

## Files and repos to inspect next

Exact production files:

- `lib/main.dart`
- `lib/core/database/helpers/messages_db_helpers.dart`
- `lib/core/database/migrations/002_messages_table.dart`
- `lib/core/database/migrations/009_quoted_message_id.dart`
- `lib/core/database/migrations/014_wire_envelope_column.dart`
- `lib/features/conversation/domain/models/conversation_message.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/features/conversation/domain/repositories/message_repository.dart`
- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `test/shared/fakes/in_memory_message_repository.dart`

Probable new production file:

- `lib/core/database/migrations/043_messages_edited_at.dart`

Exact direct tests:

- `test/core/database/helpers/messages_db_helpers_test.dart`
- `test/features/conversation/domain/models/message_payload_test.dart`
- `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_media_hydration_test.dart`

## Existing tests covering this area

- `test/core/database/helpers/messages_db_helpers_test.dart`
  - proves same-ID replace behavior in the `messages` table.
- `test/features/conversation/domain/models/message_payload_test.dart`
  - proves current v1/v2 payload parse/serialize behavior.
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  - proves current duplicate rejection and receiver-side persistence behavior.
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - proves shared send path behavior, caller-provided message IDs, and inbox
    fallback.
- `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
  - proves repository row mapping/load behavior.

Current coverage gaps:

- no test proves message edit metadata round-trips through DB/model mapping
- no test proves same-ID edit payloads update in place while real non-edit
  duplicates still reject
- no test proves shared edit delivery keeps the same ID/original timestamp while
  setting edit metadata

## Regression/tests to add first

- Add payload regressions that round-trip the edit action through both v1 and
  v2 helper paths without regressing normal sends.
- Add DB/model regressions that persist and reload `edited_at` on message rows.
- Add incoming-handler regressions that:
  - accept same-ID edit payloads for known contacts and update the existing row
  - still reject same-ID non-edit payloads as genuine duplicates
- Add send/edit regressions that prove the shared local edit path preserves the
  original message ID/timestamp while reusing the existing send-or-inbox
  delivery path.

## Step-by-step implementation plan

1. Add the new nullable edit metadata to the message persistence chain.
   Prefer a dedicated forward migration plus model/row-mapping updates instead
   of editing old migrations in place.
2. Extend `MessagePayload` with a narrow action discriminator that defaults to
   normal send behavior when absent.
   Keep backward-compatible parsing so older payloads still read as ordinary
   sends.
3. Decide the smallest shared edit entry point:
   - either extend `sendChatMessage(...)` with explicit edit metadata/action
   - or add a narrow edit wrapper that reuses `sendChatMessage(...)`
   In either case, keep one shared transport path and avoid a second retry /
   inbox architecture.
4. Teach receiver-side handling to update an existing same-ID row only when the
   payload is explicitly an edit.
   Preserve the existing duplicate result for ordinary same-ID new-message
   payloads.
5. Land the direct DB/model/application regressions before or alongside the
   implementation and stop if the work starts requiring UI-surface or feed
   eligibility logic. That belongs to Sessions `2` and `3`.

## Risks and edge cases

- Older peers will not know about edit semantics, so parse/default behavior
  must stay backward-compatible and non-crashing.
- Same-ID row replacement can accidentally wipe fields such as quote linkage,
  transport semantics, or cached retry envelope if the edit contract rebuilds a
  row too loosely.
- Receiver-side edit acceptance must not silently turn real duplicate new
  messages into edits.
- Offline edit delivery must continue using the shared send/inbox fallback path
  rather than creating a second queue or status model.
- This session must not widen into UI-side last-message eligibility logic.

## Exact tests and gates to run

Direct tests:

- `flutter test test/core/database/helpers/messages_db_helpers_test.dart`
- `flutter test test/features/conversation/domain/models/message_payload_test.dart`
- `flutter test test/features/conversation/domain/repositories/message_repository_impl_test.dart`
- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`
- `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `flutter test test/features/conversation/application/handle_incoming_chat_message_media_hydration_test.dart`

Named gates:

- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh baseline`

Not required for Session 1 as currently scoped:

- `./scripts/run_test_gates.sh feed`
- `./scripts/run_test_gates.sh transport` unless execution unexpectedly edits
  bootstrap, reconnect, inbox-drain, or transport-fallback wiring

## Known-failure interpretation

- No Session 1-specific known failures are documented for these direct suites
  or named gates.
- Any new failure in the added edit regressions should be treated as a real
  Session 1 blocker.
- A failing named gate should only be treated as historical if it is already
  documented or reproduced on unmodified HEAD. Do not relabel edit-contract
  regressions as legacy noise.

## Done criteria

- The repo has one shared 1:1 edit contract across DB/model/payload/send/receive.
- Editing an existing row updates the same message ID, preserves original
  ordering inputs, and persists edit metadata.
- Receiver-side same-ID edit updates work while real non-edit duplicates still
  reject.
- Direct DB/model/application regressions pass.
- `./scripts/run_test_gates.sh 1to1` passes.
- `./scripts/run_test_gates.sh baseline` passes.

## Scope guard

- Do not add Orbit/feed `Edit` affordances in this session.
- Do not add delete semantics, edit history, undo, time limits, or group edit
  support.
- Do not introduce a new transport, retry, or inbox architecture for edits.
- Do not widen into a dedicated "latest sent" repository query unless current
  local-derivation assumptions are disproved during execution.

## Accepted differences / intentionally out of scope

- Older clients may ignore or duplicate-drop edit payloads as long as they stay
  stable.
- This session only prepares edit metadata and delivery semantics for later UI
  sessions; it does not itself surface edited indicators or edit controls.
- Group message contracts stay unchanged.

## Dependency impact

- Session `2` depends on this session to provide a real shared edit contract for
  Orbit submission and edited rendering.
- Session `3` depends on this session for feed-side edit submission and
  in-place refresh behavior.
- If execution proves a dedicated repository query or a larger transport change
  is truly required, the breakdown must be refreshed before later sessions run.

## Reviewer pass

- Sufficiency verdict:
  - sufficient with minor caution
- Missing structural items:
  - none
- Required caution:
  - keep the edit contract narrow so the row replacement path preserves quoted
    message linkage, retry envelope handling, and transport semantics
  - keep genuine duplicate rejection explicit for non-edit payloads
- Overengineering to avoid:
  - do not invent a second edit-specific transport/retry architecture
  - do not add UI eligibility logic or feed-specific refresh work here

## Arbiter outcome

- Structural blockers:
  - none
- Incremental details intentionally deferred:
  - exact helper/use-case shape for the shared edit entry point
  - whether repository-level helper methods need tightening after direct RED
- Accepted differences:
  - no UI affordance work in Session `1`
  - no delete/history/group scope in Session `1`
