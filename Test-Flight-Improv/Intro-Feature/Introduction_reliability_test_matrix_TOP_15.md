# Friend Introductions Reliability Test Matrix — Top 15 Release-Gate Tests

## Scope

This matrix is a release-gate test plan for the **Friend Introductions / Intros** feature. It is intentionally focused on the reliability scenario under review:

> User-A introduces User-B to User-C. User-C accepts before User-B receives the original intro. User-B must durably receive the original intro or a repaired equivalent, must durably store C's early accept as a pending response, and must replay that response once the intro arrives. The system must converge to a direct B-C contact after both sides accept.

The matrix avoids duplicating broad happy-path, UI copy, general duplicate handling, migration-shape, serialization, and existing simulator scenarios already listed by the team. These rows target the remaining failure classes that can permanently break delivery, orphan out-of-order accepts, regress terminal state, or create false mutual acceptance.

## Source bundle reviewed

- `lib/features/introduction/application/send_introduction_use_case.dart`
- `lib/features/introduction/application/introduction_outbound_delivery.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/core/database/helpers/pending_introduction_responses_db_helpers.dart`
- `lib/core/database/migrations/046_pending_introduction_responses.dart`
- `lib/core/database/migrations/047_introduction_outbox.dart`
- `lib/core/database/helpers/introduction_outbox_db_helpers.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/core/services/incoming_message_router.dart`
- `lib/features/introduction/application/accept_introduction_use_case.dart`
- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
- `lib/features/introduction/domain/models/introduction_payload.dart`
- `lib/features/introduction/domain/models/introduction_model.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
- `lib/core/database/helpers/introductions_db_helpers.dart`
- `lib/core/services/pending_message_retrier.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`

## Scope caveat

The uploaded files show the critical application and persistence paths, but not the full fake-network harness, relay/inbox implementation, CI inventory, or all existing tests. Therefore, `Current status` is marked `Open` unless your repo already contains a direct equivalent test that proves the full contract in the row.

Do not mark a row `Covered` based on adjacent tests unless the existing test has the same failure injection, persistence boundary, and final convergence assertion.

## Actors

- **A** = introducer. Creates the introduction and sends the `send` payload to B and C.
- **B** = recipient. In the target reliability scenario, B misses the original intro and may receive C's accept first.
- **C** = introduced party. Accepts before B has the original intro.
- **X** = unauthorized peer, forged sender, stale sender, or malformed transport source.
- **Relay / Inbox** = durable delivery path used when local/direct send cannot complete.
- **Crash hook** = deterministic test seam that stops execution after a specific DB or network step, then restarts the app/repository.

## Status legend

- **Covered** = a direct automated test already exists and proves the user-visible contract.
- **Partial** = adjacent coverage exists, but the full crash/out-of-order/durable convergence contract is not proven.
- **Open** = add this test or explicitly map it to a direct equivalent before treating intros as reliable.
- **Unsupported** = capability is intentionally not supported and should be blocked or documented.

## Priority guide

- **P0** = release-blocking reliability, durability, convergence, or trust contract.
- **P1** = important hardening before broad rollout.
- **P2** = useful but not required for this reliability scenario.

All rows in this matrix are **P0** because each row can permanently break the target introduction scenario or create a false final state.

## Minimum introduction reliability invariants

- Creating an intro must atomically create durable outbound work for both introduced parties before the system can claim the intro was sent.
- A local accept/pass status must not be committed without durable outbound work to the introducer and the other introduced party.
- If B receives C's `accept` before B receives A's `send`, B must durably stage the response and replay it once the intro arrives.
- Pending responses must not be orphaned if a repair/re-send replaces the introduction ID.
- Terminal states are monotonic: `mutualAccepted`, `alreadyConnected`, `passed`, and `expired` must not be downgraded or revived by stale responses.
- Incoming `send`, `accept`, and `pass` messages must be bound to the actual transport sender, not only to untrusted payload fields.
- Durable inbox delivery must not be dropped because the introduction listener was not subscribed at the moment the router emitted a broadcast stream event.
- Retry must attempt every viable delivery path, or must have a documented reason for limiting retry to a single durable path.
- Fan-out dedupe IDs must be target-safe so that A→B cannot suppress A→C, and C→A cannot suppress C→B.
- Every P0 row must assert final DB state, pending-response state, outbox state, visible intro state, and B-C contact existence/non-existence where applicable.

## Code-review risk anchors that shaped this matrix

- `send_introduction_use_case.dart:124-205` deletes existing pair introductions, creates a new `introductionId`, saves the intro row, then sequentially calls reliable delivery for B and C. A crash between those steps can leave missing outbox work.
- `introduction_outbound_delivery.dart:15-62` stages an outbox row inside each individual delivery call. The caller does not stage both fan-out legs atomically with intro creation.
- `accept_introduction_use_case.dart:79-133` persists local accepted status before sending accept payloads to A and the other introduced party.
- `handle_incoming_introduction_use_case.dart:112-180` replaces older same-pair intro rows and only replays pending responses for the incoming `introductionId`.
- `introduction_repository_impl.dart:113-119` deletes pending responses and outbox rows when an introduction is deleted.
- `handle_incoming_introduction_use_case.dart:350-398` applies late responses to existing rows and then re-derives overall status, which must be guarded so terminal states cannot regress.
- `introductions_db_helpers.dart:291-333` updates party status without a SQL guard on current status or terminal overall state.
- `handle_incoming_introduction_use_case.dart:459-477` deletes pending rows for `success` or `rejected`, but not for idempotent `alreadyExists` replay.
- `introduction_listener.dart:182-313` parses/decrypts payloads and calls the handler without an explicit transport-sender-to-payload-sender binding check.
- `incoming_message_router.dart:16-25` uses broadcast controllers; `incoming_message_router.dart:197-198` emits introduction messages through the introduction broadcast stream.
- `handle_app_resumed.dart:136-140` drains offline inbox on resume; this must occur only after the introduction listener is ready, or the drain must be durable until processed.
- `introduction_payload.dart:213-218` builds envelope message IDs from `introductionId`, `action`, and `senderPeerId`, but not `targetPeerId`.
- `introduction_outbound_delivery.dart:99-165` retries retryable outbox rows using inbox storage only, while the initial path tries local/direct/relay/inbox.
- `046_pending_introduction_responses.dart:14-28` and `pending_introduction_responses_db_helpers.dart:57-63` provide durable pending response staging and deterministic load order; tests must prove this survives crash and replay.
- `047_introduction_outbox.dart:13-37` and `introduction_outbox_db_helpers.dart:49-64` provide durable outbound retry storage; tests must prove every required fan-out leg is staged and drained.

## Coverage policy used in this matrix

### Coverage legend

- **Required** = should exist before this feature is considered production-ready.
- **Recommended** = high-value additional proof.
- **N/A** = not necessary for that row.

### Rules

**Unit**: use for repository guards, status derivation, response replay behavior, sender binding helpers, message ID generation, retry row selection, and deterministic fake clocks.

**Integration**: use for DB transaction boundaries, crash/restart persistence, outbox staging, pending response replay, listener/router ordering, and contact creation side effects.

**Smoke**: keep small but release-blocking: crash-safe send staging, out-of-order C accept before B send, repair/re-send with pending response preservation, and final mutual acceptance.

**Fake Network**: use deterministic delivery loss, delayed messages, duplicate messages, partitioned peers, fake relay/inbox, fake direct send ACKs, and fake crash hooks.

**3-Party E2E**: use A/B/C simulators for every row where the final user-visible failure is B missing the intro, B missing C's accept, A/B/C disagreeing on state, or B-C contact not being created.

## Matrix — maximum 15 rows

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| INTRO-REL-001 | Crash after intro row save before any outbound leg is staged | A introduces B to C. Test has a crash hook immediately after `saveIntroduction(model)` and before the first `deliverIntroductionPayloadReliably` call. | 1. Start A's send flow. 2. Persist the intro row. 3. Crash before B or C outbox row is saved. 4. Restart A. 5. Run introduction outbox recovery/retry. | Recovery detects the intro row has no durable B/C send work, stages both missing send deliveries, and eventually delivers the same intro truth to B and C. No manual re-send is required. | P0 | Covered | Recommended | Required | Required | Required | Required | Covered by atomic intro+both-send-outbox persistence in `test/core/database/helpers/intro_db_helpers_test.dart` and delivery-stage crash coverage in `test/features/introduction/application/send_introduction_test.dart`. Verified by the direct evidence sweep (`flutter test ... intro_db_helpers_test.dart send_introduction_test.dart accept_introduction_test.dart handle_incoming_introduction_test.dart introduction_listener_test.dart p2p_service_impl_test.dart`, 154 tests) and `./scripts/run_test_gates.sh intro` (203 tests). |
| INTRO-REL-002 | Crash between B and C fan-out staging | A introduces B to C. Crash hook fires after B's send leg is staged/sent but before C's leg is staged. | 1. Start A's send flow. 2. Stage or send A→B. 3. Crash before A→C staging. 4. Restart A. 5. Run outbox repair. 6. Drain deliveries. | B and C both have durable send rows or delivery proofs for the same intro ID. C is not permanently missing the intro because A crashed during sequential fan-out. | P0 | Covered | Recommended | Required | Required | Required | Required | Covered by the same atomic intro/outbox transaction tests plus `send_introduction_test.dart` proving both B/C target rows exist before delivery-stage crash. Verified by the direct evidence sweep (154 tests) and `./scripts/run_test_gates.sh intro` (203 tests). |
| INTRO-REL-003 | Crash after local accept status update before accept outbox staging | C has received the intro and taps Accept. A and B have not yet received C's accept. Crash hook fires after C's local status is set to `accepted` and before any accept payload is staged. | 1. C accepts. 2. Persist C local accepted status. 3. Crash before C→A or C→B outbox rows. 4. Restart C. 5. Run accept/outbox recovery. | C's accepted local state is reconciled with missing outbound work. C→A and C→B accept payloads are staged and delivered without requiring C to tap Accept again. | P0 | Covered | Required | Required | Required | Required | Required | Covered by atomic local response+accept fan-out persistence in `test/core/database/helpers/intro_db_helpers_test.dart` and `test/features/introduction/application/accept_introduction_test.dart` crash coverage proving local accept and both fan-out rows are persisted before delivery-stage crash. Verified by the direct evidence sweep (154 tests) and `./scripts/run_test_gates.sh intro` (203 tests). |
| INTRO-REL-004 | Crash after C's accept reaches A but before B is staged | C accepts while B has not received the original intro. A is reachable; B is offline or inbox-only. Crash hook fires after C→A succeeds and before C→B staging. | 1. Deliver C→A accept. 2. Crash before C→B outbox save. 3. Restart C. 4. Run recovery/retry. 5. Deliver A→B intro later. | C→B accept is eventually delivered or stored in B's inbox. If B still lacks the intro, B stores the accept as a pending response and replays it when A→B send arrives. | P0 | Covered | Recommended | Required | Required | Required | Required | Covered by `accept_introduction_test.dart` proving both C→A and C→B accept fan-out rows exist before delivery-stage crash and `handle_incoming_introduction_test.dart` proving accept-before-send deferral and replay. Verified by the direct evidence sweep (154 tests) and `./scripts/run_test_gates.sh intro` (203 tests). |
| INTRO-REL-005 | C accept pending under old intro ID survives A repair/re-send | B missed `introId-1`. C accepted `introId-1`. B receives C→B accept before A→B send. A later repairs by re-send or refresh. | 1. A sends `introId-1` to C only. 2. C accepts. 3. Deliver C→B accept first. 4. Assert B has pending response for `introId-1`. 5. A repairs/re-sends. 6. Deliver repaired send to B. | Either A reuses `introId-1`, or pending response data is migrated/rekeyed to the replacement intro. B replays C's accept and can reach mutual acceptance after B accepts. No orphan pending row remains. | P0 | Covered | Required | Required | Required | Required | Required | Covered by `intro_db_helpers_test.dart` rekeying staged responses to a replacement intro id, `send_introduction_test.dart` re-sending same pair rekeys pending responses, and intro multi-node repair/re-send coverage in the intro gate. Verified by the direct evidence sweep (154 tests) and `./scripts/run_test_gates.sh intro` (203 tests). |
| INTRO-REL-006 | Mutual/connected terminal state cannot be downgraded by late pass | B and C have already reached `mutualAccepted` or `alreadyConnected` for the intro. A stale `pass` exists in relay/inbox or pending replay. | 1. Create mutual acceptance and B-C contact. 2. Deliver delayed `pass` from B or C for the same intro ID. 3. Reload intro rows and contacts. | Intro remains `mutualAccepted` or `alreadyConnected`. B-C contact remains. Late pass is rejected or consumed as stale; it does not downgrade status or remove contact. | P0 | Covered | Required | Required | Required | Required | Required | Covered by `test/features/introduction/application/handle_incoming_introduction_test.dart` test `late pass does not downgrade a mutually accepted intro`, which seeds `peer-C` as an existing contact and asserts `contactExists('peer-C')` before and after the late pass. Verified by `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart` (`00:00 +29: All tests passed!`) and `./scripts/run_test_gates.sh intro` (`All tests passed!`). |
| INTRO-REL-007 | Passed/expired terminal state cannot be revived by late accept | Intro is already `passed` or `expired`. A stale `accept` arrives later from either party. | 1. Put intro into `passed` and repeat for `expired`. 2. Deliver delayed `accept` for the same intro ID. 3. Reload DB/UI state and contacts. | Existing intro remains terminal. No B-C contact is created from stale accept. A new connection is possible only through an explicit new valid intro flow. | P0 | Covered | Required | Required | Recommended | Required | Required | Covered by `test/features/introduction/application/handle_incoming_introduction_test.dart` tests `late accept does not revive a passed intro` and `late accept does not revive an expired intro`, which assert stale accept returns `rejected`, preserves terminal state and persisted terminal state, and leaves `contactExists('peer-C')` false before and after. Verified by `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart` (30 tests) and `./scripts/run_test_gates.sh intro` (203 tests). |
| INTRO-REL-008 | Pending replay consumes idempotent `alreadyExists` responses | B has a pending C accept. By the time replay runs, the same response was already applied or the intro is terminal. | 1. Insert a pending accept row. 2. Make intro already reflect that response or already terminal. 3. Run pending response replay. 4. Run replay a second time. | Replay treats `alreadyExists` as consumed. Pending row is deleted or tombstoned. Handler does not throw a retryable error and does not loop forever. | P0 | Covered | Required | Required | N/A | Recommended | N/A | Covered by `handle_incoming_introduction_test.dart` terminal/deferred replay coverage that consumes already-applied or terminal pending responses and leaves pending rows empty. Verified by the direct evidence sweep (154 tests) and `./scripts/run_test_gates.sh intro` (203 tests). |
| INTRO-REL-009 | Forged accept before original intro is rejected, not staged | B has no intro row yet. Unauthorized X sends a payload claiming `responderId=C`. | 1. Route X→B forged `accept` before A→B send. 2. Inspect pending response table. 3. Later deliver real A→B send. 4. Let B accept. | B rejects the forged response because transport sender does not match responder. No pending C accept is staged. Later real intro does not replay forged data or create a false contact. | P0 | Covered | Required | Required | Required | Required | Required | Covered by `introduction_listener_test.dart` rejecting deferred responses when transport sender does not match responder and `handle_incoming_introduction_test.dart` rejecting transport sender mismatch before staging. Verified by the direct evidence sweep (154 tests) and `./scripts/run_test_gates.sh intro` (203 tests). |
| INTRO-REL-010 | Forged accept after intro row exists is rejected | B already has a valid intro row for A/B/C. Unauthorized X sends `accept` or `pass` claiming to be C. | 1. Deliver X→B forged response. 2. Process via listener and handler. 3. Inspect intro statuses, pending responses, and contacts. | No status changes. No pending row is created. No B-C contact is created. Handler emits rejection/diagnostic instead of applying untrusted payload fields. | P0 | Covered | Required | Required | Recommended | Required | Required | Covered by `test/features/introduction/application/handle_incoming_introduction_test.dart` test `valid existing intro rejects forged live accept and pass without state changes`, which seeds valid existing A/B/C intro rows, sends forged live `accept` and `pass` responses from `peer-forger` claiming `peer-C`, and asserts rejected result, unchanged stored intro state, no pending response, and no B-C contact creation. Verified by `flutter test --no-pub test/features/introduction/application/handle_incoming_introduction_test.dart` (`+31`) and `./scripts/run_test_gates.sh intro` (`+204`). |
| INTRO-REL-011 | Misaddressed intro `send` is rejected | Payload has A/B/C fields, but receiver is D. The message is otherwise parseable and decryptable. | 1. Route A→D intro `send`. 2. Process via introduction listener. 3. Inspect D's intro table, notifications, and system messages. | D stores nothing and shows no intro. Handler rejects because local `ownPeerId` is neither `recipientId` nor `introducedId`. | P0 | Covered | Required | Required | Recommended | Required | N/A | Covered by `handle_incoming_introduction_test.dart` tests rejecting sends not addressed to this user and rejecting missing/blank required peer ids before local truth is stored. Verified by the direct evidence sweep (154 tests) and `./scripts/run_test_gates.sh intro` (203 tests). |
| INTRO-REL-012 | Recipient ML-KEM key consistency supports C→B early accept | A has a fresh B ML-KEM key passed into send flow, but contact repo has stale or null B ML-KEM key. C accepts before B receives the original intro. | 1. A sends intro using fresh B key. 2. Verify payload delivered to C contains the same effective B key. 3. C accepts. 4. Deliver C→B accept before A→B send. | C encrypts its accept to B with the effective fresh B key. B decrypts and stages the pending response. No early accept is lost due to stale key metadata embedded in C's intro row. | P0 | Covered | Required | Required | Required | Required | Required | Covered by `send_introduction_test.dart` proving the effective recipient ML-KEM key is used consistently for encryption and persisted intro metadata. Verified by the direct evidence sweep (154 tests) and `./scripts/run_test_gates.sh intro` (203 tests). |
| INTRO-REL-013 | Fan-out message IDs are target-safe under relay dedupe | Relay/inbox dedupe is configured to reject duplicate message IDs unless scoped by target. | 1. A stores `send` to B and C. 2. C stores `accept` to A and B. 3. Drain all inboxes. 4. Inspect stored relay records and delivered messages. | All target-specific fan-out legs are stored and delivered. Test fails if A→B suppresses A→C or C→A suppresses C→B because message ID lacks `targetPeerId`. | P0 | Covered | Required | Required | Required | Required | Required | Covered by relay target-scoped dedupe tests `go-relay-server/inbox_dedup_test.go` `TestInboxStoreDedup_SameIdDifferentRecipient` and `go-relay-server/backend_redis_test.go` `TestRedisInboxBackend_DedupesByMessageIDPerRecipient`. Verified by `cd go-relay-server && go test .` (`ok github.com/mknoon/relay-server`). |
| INTRO-REL-014 | Offline inbox drain cannot drop intro when listener starts late | Router is running, but `IntroductionListener` is not subscribed yet. B has an offline inbox item containing A's intro send or C's accept. | 1. Drain B's offline inbox while listener is absent. 2. Start listener. 3. Run drain/recovery again. 4. Inspect DB state. | Message is processed exactly once, or remains durable until processed. Broadcast stream timing must not drop the intro/accept silently. | P0 | Covered | Recommended | Required | Required | Required | Required | Covered by `test/core/services/p2p_service_impl_test.dart` durable inbox staging tests for committed introduction entries and retryable introduction outcomes, plus production wiring that calls `IntroductionListener.processIncomingMessage` directly for staged introduction replay. Verified by the direct evidence sweep (154 tests) and `./scripts/run_test_gates.sh intro` (203 tests). |
| INTRO-REL-015 | Retry uses direct/relay when inbox store fails | A or C has retryable intro outbox row. Inbox storage currently fails, but the target is now reachable by local/direct/relay send. | 1. Insert failed/sent outbox row. 2. Make `storeInInbox` fail. 3. Make direct or relay send succeed. 4. Run retry. 5. Inspect outbox and recipient DB. | Retry delivers through the available path and deletes or marks the row delivered. It does not remain failed solely because inbox storage failed. | P0 | Covered | Required | Required | Recommended | Required | N/A | Covered by `test/features/introduction/application/introduction_outbound_delivery_test.dart` tests `retryPendingIntroductionDeliveries delivers a failed row through direct send when inbox storage fails` and `retryPendingIntroductionDeliveries delivers a failed row through relay probe when inbox storage fails`, which seed failed retryable rows, force inbox storage failure, then prove acknowledged direct/relay retry delivers and clears the outbox. RED direct regression failed before implementation with `Expected: <1> Actual: <0>`. Verified by the full direct file passing with 11 tests, scoped `git diff --check`, `./scripts/run_test_gates.sh intro` passing with 204 tests, `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passing, and `INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh` passing with `Intro E2E harness passed`. |

## P0 smoke subset

Run these as the smallest release-blocking introduction reliability suite:

- `INTRO-REL-001`
- `INTRO-REL-003`
- `INTRO-REL-005`
- `INTRO-REL-006`
- `INTRO-REL-009`
- `INTRO-REL-014`

Passing only the smoke subset is not enough to claim the feature is reliable. It is the minimum fast gate. The full 15-row matrix should run in CI before release.

## Recommended implementation structure

- Add deterministic crash hooks around repository writes and outbound delivery calls. Use them only in tests.
- Add a fake intro network that can independently drop, delay, duplicate, or reorder A→B, A→C, C→A, C→B, B→A, and B→C deliveries.
- Add a fake relay/inbox that captures raw envelopes, message IDs, target peer IDs, sender peer IDs, and store/retrieve attempts.
- Add a local DB restart helper that closes and reopens the SQLCipher database without clearing tables.
- Add an assertion helper for intro convergence:
  - A/B/C agree on intro ID or documented replacement mapping.
  - B and C have the correct individual statuses.
  - Overall status is correct and monotonic.
  - Pending response table is empty after successful replay.
  - Outbox rows are either delivered/deleted or still retryable with a clear reason.
  - B-C contact exists only after both sides accept.
- Add transport-sender assertions in listener/handler tests, not just payload-level assertions.
- Run the core fake-network tests repeatedly with deterministic fake time. Flake budget for P0 reliability rows should be zero.

## Handoff checklist

Before marking the introduction feature reliable, require one of the following for every row:

- A new automated test exists and passes.
- An existing automated test is mapped to the row with matching failure injection and assertions.
- The product explicitly declares the scenario unsupported and blocks it in code.

Rows that only prove the happy path, UI copy, duplicate rendering, or generic resend behavior should not be used to satisfy this matrix unless they also prove the exact durability and convergence contract described in the row.
