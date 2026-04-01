# Session 2 Plan - Client durable inbox staging, replay, and reject observability

## Final verdict

`implementation-ready`

Current repo evidence still shows the open Report `41` seam is on the Flutter
client side after Session `1`:

- `lib/core/services/p2p_service_impl.dart` still drains the relay inbox by
  retrieving a page and immediately injecting raw envelopes into the live
  message stream.
- The existing production path still uses destructive local semantics even
  after the relay now supports staged retrieve plus explicit ack:
  there is no durable local row that survives an app crash, resume, or later
  restart after fetch but before visible conversation persistence.
- `lib/features/conversation/application/chat_message_listener.dart` and
  `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  still drop fetched chat envelopes locally for reasons such as missing ML-KEM
  secret, decrypt failure, unknown sender, duplicate delivery, or edit without
  original, but today those drops leave no durable reject record tied to the
  relay fetch.
- `lib/main.dart` still creates `P2PServiceImpl` without any durable inbox
  staging repository or chat-replay callback, so production startup/resume
  remains vulnerable to silent post-fetch loss.

This session is therefore the bounded client recovery seam for Report `41`:
stage relay-backed inbox entries durably before ack/delete, replay them from
local storage, and record exact reject reasons for chat envelopes that fail
after fetch.

## Final plan

### real scope

- Add a dedicated durable local staging table for fetched relay inbox entries.
- Move the production `P2PServiceImpl` drain path in `lib/main.dart` onto the
  Session `1` `retrieve_pending` + `ack` contract when the staging repository
  is available.
- Replay already-staged inbox entries before fetching new relay pages.
- For chat-message inbox envelopes, process replay through the existing chat
  listener logic using a returned disposition instead of fire-and-forget stream
  delivery.
- Record one exact durable reject reason per dropped chat envelope with enough
  identifiers to correlate the relay `entry_id`, sender, timestamp, and
  client-side reject disposition.
- Preserve current non-chat inbox routing behavior while keeping the durable
  chat-message recovery contract truthful and additive.

### closure bar

- A fetched relay inbox entry is durably represented locally before the client
  acks relay deletion.
- Restart or resume can replay staged inbox rows that were fetched earlier but
  not yet committed to visible conversation storage.
- Chat-message replay produces one of three durable outcomes:
  committed, retryable, or rejected with an exact reason code.
- Missing ML-KEM secret availability is no longer collapsed into generic
  `notChatMessage` handling for staged v2 chat envelopes.
- `P2PServiceImpl` production wiring in `lib/main.dart` uses the staging
  repository and the chat replay disposition callback.
- Direct migration/helper/service/listener regressions pass, and named gates
  are run honestly with any pre-existing unrelated failures recorded as such.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Current code and tests beat stale prose when they disagree.
- Verified repo seams:
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/core/services/incoming_message_router.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `lib/features/conversation/domain/repositories/message_repository_impl.dart`
  - `lib/core/database/helpers/messages_db_helpers.dart`
  - `lib/core/database/migrations/`
  - `lib/main.dart`
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/core/inbox/inbox_round_trip_test.dart`
  - `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  - `test/features/conversation/application/chat_message_listener_test.dart`
  - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- Session `1` made relay retrieval truthfully two-phase, but the Flutter client
  still has no durable local recovery record between fetch and local message
  persistence.
- The current drain path can therefore fetch and ack relay entries, then still
  lose the incoming chat message before it reaches the local thread.
- Current chat receive result codes are too coarse to distinguish a retryable
  missing-key condition from permanent rejects such as duplicate delivery or
  unknown sender.
- Report `41` cannot honestly progress to notification-open parity until the
  client-side fetch-to-persist seam is durable and observable.

### files and repos to inspect next

- Production files:
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `lib/core/database/migrations/045_inbox_staging_entries.dart`
  - `lib/core/database/helpers/inbox_staging_db_helpers.dart`
  - one new adjacent inbox-staging repository under `lib/core/inbox/`
  - `lib/main.dart`
- Direct tests:
  - `test/core/database/migrations/045_inbox_staging_entries_test.dart`
  - `test/core/database/helpers/inbox_staging_db_helpers_test.dart`
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/features/conversation/application/chat_message_listener_test.dart`
  - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  - `test/core/inbox/inbox_round_trip_test.dart`
  - `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  - `test/core/resilience/c4_partial_drain_test.dart` if the new durable drain
    path changes how partial failures replay on retry
- Closure docs:
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
  - defer the stable closure doc refresh to Session `3` unless final evidence
    proves Session `2` alone safely changes that wording

### existing tests covering this area

- `test/core/services/p2p_service_impl_test.dart` already covers inbox drain
  cadence and budgets, but not durable local staging before ack.
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  already covers decrypt failure, duplicate, and unknown sender branches, but
  not a dedicated missing-ML-KEM-secret disposition for staged replay.
- `test/features/conversation/application/chat_message_listener_test.dart`
  already covers listener-side notification and decrypt-failure behavior, but
  not a public replay disposition contract that Session `2` can reuse.
- `test/core/inbox/inbox_round_trip_test.dart` and
  `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  already prove the logical inbox recovery path, but not restart-safe durable
  staging or exact reject observability.
- Missing today:
  - no migration/helper proof for a durable inbox staging table
  - no direct proof that staged rows replay before new relay fetch pages
  - no direct proof that ack happens only after local staging succeeds
  - no direct proof that dropped staged chat envelopes persist an exact reject
    reason

### regression/tests to add first

- Add migration and helper tests first to pin the staging table schema,
  ordering, and durable reject metadata.
- Add use-case and listener tests next to pin:
  - `missingMlKemSecret` as a distinct chat receive outcome
  - exact listener replay dispositions for blocked sender, duplicate,
    edit-without-original, unknown sender, decrypt failure, and retryable
    missing-key/error cases
- Add `P2PServiceImpl` tests to pin:
  - replay of already-staged rows before relay fetch
  - `retrieve_pending` + local stage + `ack`
  - chat replay deletes or retains the staged row according to the returned
    disposition
- Refresh inbox round-trip and offline integration proofs only after the direct
  staging seam is covered.

### step-by-step implementation plan

1. Add migration `045` and a dedicated helper file for inbox staging rows with
   deterministic ordering and durable reject metadata.
2. Add a small adjacent repository under `lib/core/inbox/` that wraps those
   helpers and exposes staging, recoverable-load, reject, retry, and delete
   operations.
3. Extend `handleIncomingChatMessage` to return a distinct retryable
   `missingMlKemSecret` outcome instead of collapsing that path into
   `notChatMessage`.
4. Extend `ChatMessageListener` with a public replay/processing method that
   returns a disposition suitable for Session `2` recovery while keeping the
   existing stream-driven behavior for live messages.
5. Add an additive durable-drain branch in `P2PServiceImpl` that is activated
   when the inbox staging repository is injected:
   - replay staged rows first
   - fetch relay rows with `retrieve_pending`
   - persist them locally
   - ack relay entries after staging succeeds
   - process staged chat rows via the callback and finalize rows according to
     the returned disposition
   - preserve current fallback routing for non-chat inbox envelopes
6. Wire the staging repository and replay callback through `lib/main.dart`
   without broadening into Session `3` notification-open routing changes.
7. Run the direct regressions and named gates listed below.
8. Stop and re-evaluate if execution unexpectedly requires a broader group
   inbox redesign, unread-count rewrite, or app-root notification routing
   changes. Those belong to Session `3` or out of scope.

### risks and edge cases

- The staging table must dedupe by stable relay `entry_id` so repeated relay
  fetches after an ack failure do not create multiple local rows.
- Chat replay must treat missing ML-KEM secret as retryable, not as a permanent
  discard.
- Non-chat inbox envelopes must not regress while Session `2` tightens the chat
  recovery seam.
- The durable drain branch must stay additive so tests and harnesses that do
  not inject the staging repository can still use the legacy path safely.
- Existing macOS named gate failures from Session `1` may still appear and must
  be reported honestly if unchanged.

### exact tests and gates to run

- Direct tests:
  - `flutter test test/core/database/migrations/045_inbox_staging_entries_test.dart`
  - `flutter test test/core/database/helpers/inbox_staging_db_helpers_test.dart`
  - `flutter test test/core/services/p2p_service_impl_test.dart`
  - `flutter test test/features/conversation/application/chat_message_listener_test.dart`
  - `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  - `flutter test test/core/inbox/inbox_round_trip_test.dart`
  - `flutter test test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  - `flutter test test/core/resilience/c4_partial_drain_test.dart` if the final
    implementation materially changes the existing partial-failure semantics
- Named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport`

### known-failure interpretation

- The new migration/helper/staging regressions have no accepted failure
  exemption in this session.
- If `1to1`, `baseline`, or `transport` still fail for the same unrelated
  pre-existing reasons recorded in Session `1`, record that explicitly instead
  of pretending Session `2` caused them.
- A real failure in the new durable chat staging path is blocking for this
  session.

### done criteria

- Production `P2PServiceImpl` no longer acks fetched relay chat envelopes
  before the client has a durable local staging row for them.
- Staged chat envelopes replay after restart/resume until they are either
  stored successfully or durably rejected with an exact reason.
- Missing ML-KEM secret, decrypt failure, unknown sender, duplicate delivery,
  and edit-without-original are distinguishable in the durable replay path.
- Direct migration/helper/service/listener regressions pass.
- Session `2` can be recorded as accepted in the breakdown without claiming the
  final notification-open parity work from Session `3`.

### scope guard

- Do not fix `lib/main.dart` warm/local notification-open preparation parity in
  this session.
- Do not redesign the broader direct-message inbox architecture for every
  feature that can fall back to `storeInInbox`.
- Do not rewrite unread counts, read receipts, or the app shell.
- Do not reopen the relay/server contract from Session `1` unless a concrete
  Session `2` bug proves that prerequisite is insufficient.
