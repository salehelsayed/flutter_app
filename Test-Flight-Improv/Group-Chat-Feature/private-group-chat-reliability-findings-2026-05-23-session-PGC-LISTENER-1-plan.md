# PGC-LISTENER-1 Execution Plan

Status: execution-ready

## Planning Progress

- 2026-05-23T23:30:00+02:00 - Arbiter completed - Files inspected since last update: reviewer-patched plan artifact. Decision/blocker: no structural blockers remain; incremental details are documented and intentionally deferred; accepted differences are explicit. Plan is execution-ready. Next action: hand off for implementation without editing product/test code in this planning turn.
- 2026-05-23T23:29:05+02:00 - Arbiter started - Files inspected since last update: reviewer-patched plan artifact. Decision/blocker: classifying reviewer findings into structural blockers, incremental details, and accepted differences. Next action: finalize execution-ready status if no structural blocker remains.
- 2026-05-23T23:28:10+02:00 - Reviewer completed - Files inspected since last update: the draft plan artifact itself. Decision/blocker: sufficient with adjustments; patched direct `PGC-008` stream coverage, explicit fake repo file, partial unique-index wording, and exact `PGC-009` static-check file lists. No structural blocker remains for Arbiter review. Next action: Arbiter classification.
- 2026-05-23T23:26:05+02:00 - Reviewer started - Files inspected since last update: the draft plan artifact itself. Decision/blocker: reviewing mandatory-section coverage, `PGC-009` conditionality, direct regression strength, exact gates, and hidden scope expansion. Next action: patch only sufficiency gaps, then move to Arbiter.
- 2026-05-23T23:24:20+02:00 - Planner completed - Files inspected since last update: no new files beyond the evidence set. Decision/blocker: drafted an implementation-ready plan for `PGC-008` and `PGC-018`, plus a conditional durable-storage plan for `PGC-009` with exact blockers if migration/helper/repository scope cannot be owned coherently. Next action: run Reviewer sufficiency pass.

## real scope

This session owns only rows `PGC-008`, `PGC-009`, and `PGC-018` from `private-group-chat-reliability-findings-2026-05-23-matrix.md`.

In scope:

- `PGC-008`: make `GroupMessageListener.stop()` awaitable, await stream subscription cancellation where callers can use it, and guard all listener controller emissions so late async handlers cannot write to closed controllers during `dispose()`.
- `PGC-018`: detect system payloads before the bridge-null branch and ensure bridge-less listener construction never persists raw `{"__sys": ...}` JSON as a visible user chat message.
- `PGC-009`: implement durable pending storage for membership-dependent user messages only if the executor can coherently add and wire the adjacent migration, DB helper, domain model, repository, production wiring, and focused tests in the same session.

Out of scope:

- Go/native bridge changes, relay changes, PubSub validator changes, protocol/AAD/signature migrations, UI changes, notification policy changes, key-retention policy, and send-path status changes.
- Broad membership conflict semantics beyond flushing user messages that were already judged eligible for membership-dependent buffering.
- Durable bridge-less system-message replay. `PGC-018` only prevents visible raw-system-message persistence when no bridge is available.

## closure bar

The session is good enough when:

- `PGC-008` has a direct regression proving shutdown can be awaited and that late in-flight listener work cannot add to closed message, removal, or reaction streams.
- `PGC-018` has a direct regression replacing the current faulty no-bridge system-message expectation: no visible message row, no UI stream emission, and a clear flow event when `_bridge == null`.
- `PGC-009` either has a durable pending-membership-message repository wired in production and proven across restart-style listener recreation, or is explicitly marked blocked with the exact blocker from this plan while `PGC-008` and `PGC-018` still close.
- The source matrix rows and the session breakdown ledger are updated truthfully after implementation evidence exists.

## source of truth

Authoritative sources:

- Current code and tests win over stale prose.
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md` defines the row findings and scope.
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md` defines session `PGC-LISTENER-1`, its intended plan path, and its rule that `PGC-009` may become blocked if durable storage exceeds safe scope.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define named gates; the script wins on disagreement.
- `lib/features/groups/application/group_message_listener.dart` is the production seam for all three rows.

Dirty-worktree rule:

- Before editing any product or test file in execution, inspect `git diff -- <file>` for that file. Preserve unrelated user edits and patch around them.

## session classification

`implementation-ready`

This classification is strict and conditional: `PGC-008` and `PGC-018` are implementation-ready. `PGC-009` is implementation-ready only if the executor can own the full adjacent storage slice listed below. If that slice is not coherent at execution time, classify only `PGC-009` as `prerequisite-blocked` and continue closing `PGC-008` and `PGC-018`.

Exact `PGC-009` blockers to record if encountered:

- `PGC-009 blocked: missing coherent group_pending_membership_messages migration/helper/repository/main-wiring scope after current DB version 71`.
- `PGC-009 blocked: durable pending membership storage would require unrelated storage architecture or protocol changes outside PGC-LISTENER-1`.
- `PGC-009 blocked: dirty worktree conflicts in the migration/helper/repository/listener files prevent safe ownership without overwriting unrelated edits`.

## exact problem statement

`PGC-008`: `GroupMessageListener.stop()` currently returns `void`, calls `cancel()` without awaiting it, then `dispose()` closes controllers immediately. Existing async handlers can still reach `_messageController.add`, `_removedController.add`, or `_reactionChangeController.add` after disposal.

`PGC-009`: membership-dependent user messages for unknown senders are buffered only in `_pendingMembershipDependentMessagesByGroup`, an in-memory map capped at 50 entries per group. A restart or process kill loses messages that should flush after a later membership add or startup recovery.

`PGC-018`: `_handleMessage` treats text starting with `{"__sys":` as a system payload only when `_bridge != null`. A bridge-less listener currently falls through to normal user-message handling and has an existing test named `system message without bridge falls through as regular message` that expects the bad persistence behavior.

User-visible improvement:

- Shutdown/dispose should not produce late stream errors or stale UI emissions.
- A valid late-join message should survive restart until its sender becomes an active member, when durable storage is coherently available.
- Raw system JSON should never appear as chat text simply because the listener lacks a bridge.

Must stay unchanged:

- Existing authorized system-message handling with a bridge.
- Existing membership eligibility checks before buffering.
- Existing no-body, malformed schema, topic mismatch, duplicate, removed-sender, key-repair, notification, media auto-download, and reaction behavior except for guarded emissions after shutdown.

## files and repos to inspect next

Production files:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/main.dart`
- `lib/core/database/migrations/072_group_pending_membership_messages.dart` if `PGC-009` proceeds
- `lib/core/database/helpers/group_pending_membership_messages_db_helpers.dart` if `PGC-009` proceeds
- `lib/features/groups/domain/models/group_pending_membership_message.dart` if `PGC-009` proceeds
- `lib/features/groups/domain/repositories/group_pending_membership_message_repository.dart` if `PGC-009` proceeds
- `lib/features/groups/domain/repositories/group_pending_membership_message_repository_impl.dart` if `PGC-009` proceeds

Test and fake files:

- `test/features/groups/application/group_message_listener_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/in_memory_group_pending_membership_message_repository.dart` if `PGC-009` proceeds
- `test/core/database/migrations/072_group_pending_membership_messages_test.dart` if `PGC-009` proceeds
- `test/core/database/helpers/group_pending_membership_messages_db_helpers_test.dart` if `PGC-009` proceeds
- `test/core/database/integration/full_migration_chain_test.dart` if `PGC-009` proceeds

Reference patterns:

- `lib/core/database/migrations/063_group_pending_key_repairs.dart`
- `lib/core/database/helpers/group_pending_key_repairs_db_helpers.dart`
- `lib/features/groups/domain/models/group_pending_key_repair.dart`
- `lib/features/groups/domain/repositories/group_pending_key_repair_repository.dart`
- `lib/features/groups/domain/repositories/group_pending_key_repair_repository_impl.dart`
- `lib/core/database/migrations/069_group_message_local_deletions.dart`
- `lib/core/database/helpers/group_message_local_deletions_db_helpers.dart`

## existing tests covering this area

- `test/features/groups/application/group_message_listener_test.dart` has `disposes correctly`, but it only sends an event after disposal; it does not hold an in-flight async handler or prove awaited cancellation.
- `test/features/groups/application/group_message_listener_test.dart` has broad system-message coverage with a bridge, including member add/remove/metadata/key rotation duplicate behavior.
- `test/features/groups/application/group_message_listener_test.dart` currently has a faulty no-bridge test that expects raw system JSON to persist as a normal message. That test must be changed under `PGC-018`.
- `test/features/groups/application/group_message_listener_test.dart` has DE-017 membership-dependent buffer/flush/repair coverage using the in-memory queue.
- `test/features/groups/integration/group_resume_recovery_test.dart` has DE-017 fake-network coverage for membership-dependent buffering, flushing, and repair, but it does not prove process-kill durable replay.
- DB migration and helper patterns are covered by migration-specific tests plus `test/core/database/integration/full_migration_chain_test.dart`.

## regression/tests to add first

Add failing/proving tests before product changes:

1. `PGC-018 no-bridge system payload is rejected or deferred without visible chat persistence` in `group_message_listener_test.dart`.
   - Construct `GroupMessageListener` without `bridge`.
   - Send a `member_added` system payload.
   - Assert no saved group message, no group-message stream emission, no membership mutation unless an explicit no-bridge handler is added, and a flow event such as `GROUP_MESSAGE_LISTENER_SYSTEM_NO_BRIDGE_REJECTED` or `GROUP_MESSAGE_LISTENER_SYSTEM_NO_BRIDGE_DEFERRED`.

2. `PGC-008 stop awaits cancellation and late handler does not emit after dispose` in `group_message_listener_test.dart`.
   - Use a gated fake repository or bridge so a live message handler is in flight.
   - Start the listener, enqueue the message, wait until the handler is gated, call `await listener.stop()` and/or `listener.dispose()`, release the gate, and assert no uncaught closed-controller error and no post-stop stream emission.
   - Cover message, removed-group, and reaction stream emissions if private emit helpers are introduced. A single helper-level test or three narrow stream-path tests are acceptable; do not leave `_removedController.add` unproven if it is routed through the same guard.

3. If `PGC-009` proceeds, add storage tests before wiring:
   - Migration test proves `group_pending_membership_messages` schema, indexes, idempotency, and per-group/message uniqueness.
   - Helper/repository test proves upsert, oldest-first loading, sender-filtered loading, delete-after-flush, and per-group cap pruning.
   - Listener restart test proves: listener A buffers an unknown-sender eligible user message into durable storage, listener A is disposed, listener B is created with the same repos, membership becomes valid, the pending message flushes exactly once, and the durable pending row is deleted.
   - Startup sweep test proves: if membership became durable before listener restart, listener start drains eligible durable pending rows without waiting for another membership event.

If `PGC-009` blocks, do not add partial durable-storage tests. Record the blocker in this plan, the matrix, and the breakdown ledger.

## step-by-step implementation plan

1. Pre-edit safety:
   - Run `git status --short`.
   - For every file about to be edited, run `git diff -- <file>` and preserve unrelated dirty edits.

2. Add the `PGC-018` regression and fix:
   - In `_handleMessage`, compute `isSystemPayload` immediately after `text` extraction.
   - Route system payloads before user-message empty/media handling and before membership buffering.
   - If `_bridge != null`, keep existing `_handleSystemMessage` behavior.
   - If `_bridge == null`, emit a narrow diagnostic and return before `handleIncomingGroupMessage`.
   - Replace the existing no-bridge fall-through test expectation with no visible persistence.

3. Add the `PGC-008` regression and fix:
   - Add listener lifecycle fields such as `_isStopping`, `_isDisposed`, and an idempotent `_stopFuture` if needed.
   - Change `stop()` to `Future<void> stop()` and await `_subscription?.cancel()`, `_reactionSubscription?.cancel()`, and `_diagnosticSubscription?.cancel()`.
   - Keep `dispose()` synchronous for existing callers, but make it mark disposed before controller closure and avoid throwing if called repeatedly.
   - Add small private emit helpers for message, removal, and reaction controller writes. Helpers must no-op when disposed or when the controller is closed.
   - Replace direct `_messageController.add`, `_removedController.add`, and `_reactionChangeController.add` calls with the helpers.
   - Preserve existing callers that invoke `listener.stop();` without awaiting; Dart allows ignoring the returned `Future`, but tests and new call sites should await where deterministic shutdown matters.

4. Decide `PGC-009` storage coherence before editing DB files:
   - Proceed only if the executor can add migration `072`, helper, model, repository, main wiring, fake/test helper wiring, and focused tests without conflicting with unrelated dirty worktree changes.
   - If not coherent, stop `PGC-009` immediately with one exact blocker from `session classification`; continue steps for `PGC-008` and `PGC-018`.

5. If `PGC-009` proceeds, add durable storage:
   - Add migration `072_group_pending_membership_messages` and bump `lib/main.dart` DB version from 71 to 72.
   - Add the migration to both fresh install and `oldVersion < 72` upgrade chains.
   - Add table `group_pending_membership_messages` with at least: `id`, `group_id`, `sender_peer_id`, nullable `message_id`, `payload_json`, `received_at`, `created_at`, `updated_at`; indexes for `(group_id, sender_peer_id, received_at)`, `(group_id, received_at)`, and a partial unique index on `(group_id, message_id)` when `message_id` is present and nonempty.
   - Keep the existing per-group cap of 50 by pruning oldest pending rows after save.
   - Add domain model and repository methods for save/upsert, list by group/senders, bounded startup list, delete by id, delete by group/message id, and prune group.
   - Wire repository construction in `main.dart` and inject it into `GroupMessageListener`.
   - Keep the listener constructor parameter optional so existing tests and narrow callers can stay in-memory until updated.

6. If `PGC-009` proceeds, update listener buffering and flushing:
   - When `_bufferMembershipDependentMessage` accepts an eligible user message, save it to durable repo if present, then keep the in-memory queue for same-process flush.
   - On `_flushMembershipDependentMessages`, merge in-memory pending rows with durable rows for the added sender ids, preserve oldest-first ordering, and delete durable rows only after successful flush or permanent before-join rejection.
   - On listener `start()`, schedule a bounded startup sweep of durable pending rows whose sender is already a current group member. Do not block stream subscription startup on this sweep.
   - Use `rethrowOnError: true` for durable flush replay so transient processing errors do not delete durable pending rows.
   - Never durably store system payloads in this repository.

7. Documentation closure after tests pass:
   - Update rows `PGC-008`, `PGC-009`, and `PGC-018` in `private-group-chat-reliability-findings-2026-05-23-matrix.md`.
   - Update `PGC-LISTENER-1` in `private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`.
   - If new test files are added, confirm they classify under `./scripts/run_test_gates.sh completeness-check`; no gate-definition edit should be needed for core database and feature-local tests.

## risks and edge cases

- `dispose()` is synchronous, so it cannot await cancellation. The guard helpers are required even after `stop()` becomes awaitable.
- Controller add guards must cover all message, removal, and reaction emissions, including auto-download re-emits and diagnostic placeholder/rejected-outbound emissions.
- Durable pending rows must not turn system payloads into user messages.
- Durable pending rows must not bypass current membership, removed-sender cutoff, before-joined, key-epoch, duplicate-message-id, or schema guards.
- Startup sweep must be bounded so a large pending table does not block listener start.
- Durable rows must not be deleted on transient replay failures.
- No-id legacy messages can be stored with generated pending ids, but duplicate persistence must still rely on existing no-message-id content/timestamp dedupe.
- Dirty worktree edits in listener tests are likely. Execution must patch around them instead of rewriting the file wholesale.

## exact tests and gates to run

Minimum direct tests for `PGC-008` and `PGC-018`:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "PGC-008"
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "PGC-018"
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
```

Additional direct tests if `PGC-009` proceeds:

```bash
flutter test --no-pub test/core/database/migrations/072_group_pending_membership_messages_test.dart
flutter test --no-pub test/core/database/helpers/group_pending_membership_messages_db_helpers_test.dart
flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "PGC-009"
```

Static and formatting gates:

```bash
dart format --set-exit-if-changed lib/features/groups/application/group_message_listener.dart test/features/groups/application/group_message_listener_test.dart
```

If `PGC-009` proceeds, include the new/changed DB and repository files in the same `dart format --set-exit-if-changed` command.

Expected `PGC-009` format file list:

```bash
dart format --set-exit-if-changed \
  lib/features/groups/application/group_message_listener.dart \
  lib/main.dart \
  lib/core/database/migrations/072_group_pending_membership_messages.dart \
  lib/core/database/helpers/group_pending_membership_messages_db_helpers.dart \
  lib/features/groups/domain/models/group_pending_membership_message.dart \
  lib/features/groups/domain/repositories/group_pending_membership_message_repository.dart \
  lib/features/groups/domain/repositories/group_pending_membership_message_repository_impl.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/shared/fakes/group_test_user.dart \
  test/shared/fakes/in_memory_group_pending_membership_message_repository.dart \
  test/core/database/migrations/072_group_pending_membership_messages_test.dart \
  test/core/database/helpers/group_pending_membership_messages_db_helpers_test.dart \
  test/core/database/integration/full_migration_chain_test.dart
```

```bash
flutter analyze --no-pub lib/features/groups/application/group_message_listener.dart test/features/groups/application/group_message_listener_test.dart
git diff --check
```

If `PGC-009` proceeds, include `lib/main.dart`, new DB/model/repository files, new DB tests, and `test/core/database/integration/full_migration_chain_test.dart` in the scoped analyzer command.

Expected `PGC-009` analyzer file list:

```bash
flutter analyze --no-pub \
  lib/features/groups/application/group_message_listener.dart \
  lib/main.dart \
  lib/core/database/migrations/072_group_pending_membership_messages.dart \
  lib/core/database/helpers/group_pending_membership_messages_db_helpers.dart \
  lib/features/groups/domain/models/group_pending_membership_message.dart \
  lib/features/groups/domain/repositories/group_pending_membership_message_repository.dart \
  lib/features/groups/domain/repositories/group_pending_membership_message_repository_impl.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/shared/fakes/group_test_user.dart \
  test/shared/fakes/in_memory_group_pending_membership_message_repository.dart \
  test/core/database/migrations/072_group_pending_membership_messages_test.dart \
  test/core/database/helpers/group_pending_membership_messages_db_helpers_test.dart \
  test/core/database/integration/full_migration_chain_test.dart
```

Named gates:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

`group-real-network-nightly` is not required for this session unless the executor changes relay/device behavior, which this plan forbids.

## known-failure interpretation

- No `PGC-LISTENER-1` direct test failure is acceptable as a known failure.
- Failures in new migration/helper/repository tests, `group_message_listener_test.dart`, or `full_migration_chain_test.dart` are session-owned until proven unrelated by a pre-existing baseline from the same dirty worktree.
- If `./scripts/run_test_gates.sh groups` is red, compare against the exact failure output from this run and current gate docs. Only failures clearly unrelated to listener shutdown, system payload routing, durable pending membership buffering, group resume recovery, membership smoke, or startup rejoin can be classified as pre-existing.
- If `./scripts/run_test_gates.sh completeness-check` is red only because a newly added test file is unclassified, that is session-owned and must be fixed by putting the file in an already-classified path or updating gate classification intentionally.
- Historical docs mentioning old residual failures are not enough to waive a new failure without current command output.

## done criteria

- Plan execution modifies only files required by rows `PGC-008`, `PGC-009`, and `PGC-018` plus their closure docs.
- `PGC-008` has an awaitable shutdown path and closed-controller guards proven by direct tests.
- `PGC-018` no longer persists raw system JSON without a bridge and has a direct test proving it.
- `PGC-009` is either durably implemented and tested across restart-style listener recreation/startup sweep, or is explicitly recorded as blocked with one exact blocker while `PGC-008` and `PGC-018` are closed.
- Required direct tests, formatting, analyzer, `git diff --check`, `groups`, and `completeness-check` have run or have exact current blockers recorded.
- Matrix and breakdown docs reflect the actual result, including partial close plus `PGC-009` blocker if applicable.

## scope guard

Do not:

- Change Go, relay, platform bridge bindings, crypto protocol, message envelope signatures, AAD, or PubSub validation.
- Add UI affordances, notification UX, product settings, or user-facing copy beyond optional internal flow-event names.
- Reuse `group_pending_key_repairs` for membership-dependent user-message buffering; it has a different lifecycle and semantics.
- Replace group message persistence, broad membership conflict handling, content dedupe policy, or group key retention.
- Add unbounded pending-table drains or background schedulers.
- Use this session to fix unrelated dirty worktree failures.

Overengineering threshold:

- If durable pending membership storage requires more than a narrow table/helper/model/repository/listener/main/test slice, stop and block `PGC-009`.

## accepted differences / intentionally out of scope

- Bridge-less system payloads are rejected/deferred, not fully replayed or applied. Applying system payloads without a bridge would require broader config-sync and system-event semantics.
- Durable membership-dependent buffering is only for user messages that pass the existing eligibility checks. It does not store malformed events, system messages, reactions, key-repair placeholders, or arbitrary replay envelopes.
- Host/fake-network proof is sufficient for this listener/storage session. Real-device proof remains optional because no transport or relay behavior changes are planned.
- No-id legacy messages may still rely on existing content/timestamp duplicate protection after durable replay; this session does not invent a new legacy message identity protocol.

## dependency impact

- Closing `PGC-008` reduces disposal flake risk for later listener and group integration rows.
- Closing `PGC-018` prevents bridge-less recovery/test construction from creating visible raw system chat rows, which makes later replay and recovery evidence cleaner.
- Closing `PGC-009` enables later group membership/restart reliability work to assume pending membership-dependent user messages survive process kill. If blocked, later rows that rely on restart-stable membership buffering must either skip that assumption or take the blocked storage slice first.
- `PGC-SEND-1`, Go hardening rows, and relay rows must not be pulled into this session.

## Evidence Collector Notes

- The source matrix marks all three rows `Open` and identifies `group_message_listener.dart` plus focused listener tests as owner scope for `PGC-008` and `PGC-018`.
- The breakdown explicitly allows `PGC-009` to split into blocked if durable storage exceeds current safe scope.
- `GroupMessageListener` currently holds `_pendingMembershipDependentMessagesByGroup` as an in-memory map and caps it with `_maxPendingMembershipDependentMessagesPerGroup = 50`.
- `_handleMessage` currently checks `text.startsWith('{"__sys":') && _bridge != null`, which leaves a bridge-null fall-through path.
- Existing no-bridge test currently expects the faulty fall-through persistence.
- DB version is currently 71 in `lib/main.dart`; fresh and upgrade chains are explicit and have nearby migration/helper/repository patterns for group pending key repairs and local deletions.
- Named `groups` and `completeness-check` gates are defined by `scripts/run_test_gates.sh`; `Test-Flight-Improv/test-gate-definitions.md` says the script wins.

## Reviewer Pass

Verdict: sufficient with adjustments applied.

Reviewer questions:

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient with adjustments; the draft already had scope, closure, source of truth, regression-first rules, gates, and a `PGC-009` stop rule.
- What files, tests, regressions, or gates were missing? The draft needed the explicit in-memory pending-membership fake file, exact `PGC-009` format/analyzer file lists, and a clearer requirement to prove removed-stream emission guards if private emit helpers are introduced.
- What assumptions were stale or incorrect? None found. Current code confirms bridge-null system fall-through and RAM-only pending membership buffering.
- What was overengineered? No structural overengineering found. Durable storage is bounded to one table/helper/model/repository/listener/main/test slice with a stop rule.
- Is the work decomposed enough to minimize hallucination during implementation? Yes; execution starts with direct regressions, then separate listener lifecycle, bridge-null system routing, and conditional durable storage.
- Minimum needed to make the plan sufficient: the patched clarifications above.

## Arbiter Decision

Final verdict: execution-ready.

Structural blockers:

- None.

Incremental details intentionally deferred:

- Exact internal helper names for guarded stream emission.
- Exact flow-event suffix for bridge-less system payload rejection/defer.
- Whether repository implementation tests live in a dedicated file or are covered through helper plus listener tests, as long as the durable-storage behavior is directly proven.

Accepted differences intentionally left unchanged:

- Bridge-less system payloads are not applied as membership/config mutations in this session.
- Durable storage is limited to membership-dependent user messages, not reactions, system events, key-repair placeholders, or arbitrary replay envelopes.
- Real-device proof is not required because this is listener/storage behavior, not transport behavior.

Why this plan is safe to implement now:

- It has regression-first tests, exact owner files, explicit gates, dirty-worktree safety instructions, and a hard `PGC-009` stop rule that still allows `PGC-008` and `PGC-018` to close if durable storage becomes incoherent.
