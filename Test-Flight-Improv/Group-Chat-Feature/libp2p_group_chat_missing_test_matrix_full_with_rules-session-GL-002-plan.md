# GL-002 Session Plan - Initial Membership Signed Epoch

## Planning Progress

- 2026-04-30 17:43:05 CEST - Local plan fallback after the spawned planning child failed to write the intended plan file under bounded polling. Repo inspection showed the gap is implementation-owned: `createGroup` persists the creator group/member/key state, and group event-log helpers exist for incoming/system/key-update flows, but the create path has no signed canonical initial membership event or signed create-time event-log surface.

## Real Scope

Implement the narrow create-time evidence surface for GL-002:

- `createGroup` must be able to produce a signed, canonical initial membership/create event after the local group, creator member, and initial key epoch are known.
- The event must carry the creator peer ID, username, Ed25519 public key, ML-KEM public key, admin role, join timestamp, group ID/topic/name/type, created timestamp, and initial key epoch.
- The event must be persisted through the existing tamper-evident `group_event_log` append seam when the production caller provides the append callback.
- The normal create path must continue to persist the group, creator member, and initial key as before.

Do not implement a broad MLS commit model, multi-party transition graph, remote replay protocol, or unrelated metadata/settings signature flow in this session.

## Closure Bar

GL-002 can close only when the source matrix row becomes `Covered` or `Closed` with concrete evidence that:

- the create path signs canonical initial membership/create data with the creator private key via the existing bridge signing command,
- the signed event is appended to the durable group event log with a stable source event ID and canonical payload,
- the payload proves creator device identity and initial epoch after reloading persisted state,
- direct tests pass and the row note names the files and commands.

If the implementation cannot land that code and proof, leave GL-002 `Partial` and mark the session blocked rather than accepting it.

## Source Of Truth

- Primary row: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`, row `GL-002`.
- Breakdown contract: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`, session `GL-002`.
- Inventory row: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, row `GL-002`.
- Current code and tests win over stale prose.
- Gate definitions: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.

## Session Classification

`implementation-ready`

Discovered-gap correction: GL-002 is `needs_code_and_tests`, not `needs_tests_only`, because current code inspection shows no signed create-time membership-event/event-log surface exists to test.

## Device/Relay Proof Profile

- Profile: `host-only`.
- Live device availability check: not required for closure. The row uses device identity as persisted creator identity, not as a physical simulator/device-lab proof.
- Required closure evidence: host-side use-case and DB/event-log tests.
- `FLUTTER_DEVICE_ID`: irrelevant for the GL-002 direct closure evidence. A single Flutter device target is not sufficient or necessary for the signed create-time event contract.
- Relay addresses: not applicable.

## Exact Problem Statement

The current `createGroup` implementation saves the group row, the creator admin member row, and the bridge-returned key epoch, and `create_group_use_case_test.dart` already proves that persistence. GL-002 remains `Partial` because the create path does not sign a canonical initial membership/create event and does not append a durable event-log entry that can be independently inspected after restart. This leaves the initial membership epoch as persisted state only, not as signed event evidence.

## Files And Repos To Inspect Next

- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/main.dart`
- `lib/core/bridge/bridge.dart`
- `lib/core/database/helpers/group_event_log_db_helpers.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/core/database/helpers/group_event_log_db_helpers_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`

## Existing Tests Covering This Area

- `test/features/groups/application/create_group_use_case_test.dart` already proves group/member/key persistence, creator peer ID, username, public keys, admin role, join timestamp, and bridge-returned key epoch.
- `test/core/database/helpers/group_event_log_db_helpers_test.dart` proves canonical payload ordering, append behavior, replay idempotency, tamper detection, and hash-chain verification for the existing event-log helper.
- `test/core/database/integration/full_migration_chain_test.dart` already includes the `group_event_log` migration in the chain.
- Listener tests prove other event families can append to the event log, but they do not cover create-time initial membership.

## Regression/Tests To Add First

Add focused tests in `test/features/groups/application/create_group_use_case_test.dart` before or with the implementation:

- a regression that supplies `creatorPrivateKey` and `appendGroupEventLogEntry`, stubs `payload.sign`, creates a group, and asserts:
  - the bridge receives `group:create` before `payload.sign`,
  - the data sent to `payload.sign` is deterministic/canonical and includes creator identity, admin role, joined/created timestamp, group ID/topic/type, and initial key epoch,
  - the appended event log entry has a stable event type such as `group_created` or `initial_membership_created`,
  - `sourcePeerId` is the creator peer ID,
  - `sourceEventId` is stable for the group and create event,
  - payload contains the returned signature and signed canonical payload,
  - persisted group/member/key state can still be read after the event append.
- a failure regression for sign failure or event-log append failure. The preferred behavior is fail closed with rollback of the group/member/key rows so the app does not show a group whose initial membership event could not be signed.

Keep the existing persistence test green.

## Step-By-Step Implementation Plan

1. Snapshot the dirty worktree before execution and treat all pre-existing dirty files as prior-session state.
2. Extend `createGroup` with the smallest compatible optional parameters needed for signed create-time evidence, likely:
   - `String? creatorPrivateKey`
   - `AppendGroupEventLogEntry? appendGroupEventLogEntry`
3. Build the canonical unsigned initial membership/create payload only after the group, creator member, and selected key epoch are known. Use deterministic key ordering, following existing QR/contact-request signing patterns with `SplayTreeMap` and `jsonEncode`.
4. Sign that canonical payload through `callSignPayload` when both `creatorPrivateKey` and `appendGroupEventLogEntry` are provided. Do not fake signing in Dart.
5. Append the signed create event through `appendGroupEventLogEntry`, including the signature, canonical unsigned payload, creator identity, role, joined timestamp, group ID/topic/name/type, created timestamp, and initial key epoch.
6. If signing or append fails after group/member/key persistence, roll back via the existing `_rollbackCreatedGroup` path and rethrow a clear `StateError`.
7. Thread the callback and creator private key through `createGroupWithMembers` and the production create-group picker path so real group creation can append the event log when the DB helper is wired. If a caller is a test-only direct call and omits the optional callback/private key, preserve existing behavior.
8. Add or update direct tests in `create_group_use_case_test.dart` for signed event append, canonical payload shape, command ordering, rollback on signing/append failure, and existing persistence behavior.
9. Update GL-002 in the source matrix and test inventory to `Covered` only after direct tests pass, with exact files and commands.
10. Run the required direct tests and gates below.

## Dirty Worktree Snapshot Before Execution

- 2026-04-30 17:45:00 CEST - Controller ran `git status --short` before GL-002 execution. The worktree was already broadly dirty from prior rollout work, including the source matrix, inventory, many group/chat/media/push implementation and test files, existing untracked session plans, event-log/migration/media helpers, and Go libp2p files. Current-session planning additions before execution are limited to this GL-002 plan and the GL-002 reclassification/controller-progress edits in the breakdown. Execution must compare any new deltas against GL-002 scope before closure.

## Risks And Edge Cases

- Partial create after signing or event-log failure must not leave a visible group without signed initial membership evidence.
- Canonical payload ordering must be stable across Dart map insertion order.
- Optional parameters must not break existing tests, fakes, or call sites that do not yet have event-log wiring.
- Production create wiring must avoid leaking private key material into the event payload, logs, or persisted event rows.
- Duplicate group ID behavior should remain idempotent and should not append conflicting create events for the same group/source event ID.

## Exact Tests And Gates To Run

Direct:

```bash
flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart
flutter test --no-pub test/core/database/helpers/group_event_log_db_helpers_test.dart
```

Broader session gates:

```bash
flutter test --no-pub test/features/groups/application
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh groups
git diff --check
```

`group-real-network-nightly` is not required to close this row because the Device/Relay Proof Profile is host-only.

## Known-Failure Interpretation

- The existing broad `flutter test --no-pub test/features/groups` failure in `drain_group_offline_inbox_use_case_test.dart` is MD-011 future-media replay related and must not be misclassified as GL-002 unless the direct GL-002 tests or touched create/event-log files introduce it.
- If `./scripts/run_test_gates.sh groups` fails outside create, membership, or event-log surfaces, record the exact failing file and compare against prior dirty-session failures before blocking GL-002.

## Done Criteria

- `createGroup` can sign and append a canonical create-time initial membership event when production wiring supplies the creator private key and event-log append callback.
- Direct tests prove the event payload, signature field, source event ID, creator identity, admin role, joined timestamp, and initial key epoch.
- Direct tests prove rollback on signing or event-log append failure.
- Required direct tests pass.
- GL-002 source matrix and inventory entries are updated from `Partial` to `Covered` or `Closed` with concrete file-and-command evidence.
- Breakdown ledger records GL-002 closure without claiming unrelated rows.

## Scope Guard

Do not:

- implement a full MLS-like signed commit transition model,
- add remote replay/fork verification beyond the create event append,
- change group PubSub envelope signing,
- change invite, metadata, key-rotation, dissolve, or add-member semantics except where a compile-safe optional signature/callback must be threaded,
- store private keys or raw secret material in the event log,
- close EK-004, EK-010, DB-002, or other signature/event-log rows with this GL-002 evidence.

## Accepted Differences / Intentionally Out Of Scope

- The create-time event is a narrow signed initial membership/create evidence record, not the final architecture for every future membership/key transition.
- Host-only proof is accepted for GL-002 because the row's missing contract is deterministic persistence and signature evidence, not live relay/device delivery.
- Existing listener event-log coverage remains separate and should not be counted as GL-002 closure unless the create path itself appends the event.

## Dependency Impact

Closing GL-002 gives later governance, event-log, and key-epoch rows a reliable initial-state anchor. If GL-002 remains blocked, later sessions that depend on independently verifiable create-time membership state must stay prerequisite-blocked or avoid overclaiming their own closure.

## Execution Result

- 2026-04-30 18:16:20 CEST - Execution fallback verdict: passed for GL-002. Fresh execution child no-progressed under bounded polling; the controller-local bounded fallback implemented only the scoped create-time signed-event surface and tests.
- Scoped implementation delta:
  - `lib/features/groups/application/create_group_use_case.dart` now accepts optional creator private key plus event-log append callback, signs a canonical `group_created` initial membership payload, appends it to the group event log, and rolls back created group/member/key state if signing or append fails.
  - `lib/features/groups/application/create_group_with_members_use_case.dart` threads the creator private key and optional event-log append callback into `createGroup`.
  - `lib/features/groups/application/group_message_listener.dart` exposes its existing append callback for create-flow wiring.
  - `lib/features/groups/presentation/screens/create_group_picker_wired.dart` passes the listener append callback into group creation.
  - `test/features/groups/application/create_group_use_case_test.dart` adds direct tests for signed create-time event payload/signature evidence and rollback on signing or append failure.
- Scope classification: the broad dirty worktree predates this session. Current-session implementation files are within the GL-002 create/member/event-log scope; preexisting unrelated modified files were not reverted.
- Commands run:
  - `dart format lib/features/groups/application/create_group_use_case.dart lib/features/groups/application/create_group_with_members_use_case.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/presentation/screens/create_group_picker_wired.dart test/features/groups/application/create_group_use_case_test.dart` - pass.
  - `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart` - pass, `+13`.
  - `flutter test --no-pub test/core/database/helpers/group_event_log_db_helpers_test.dart` - pass, `+4`.
  - `git diff --check` - pass.
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --reporter expanded` - pass, `+72`.
  - `flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart` - pass, `+6`.
  - `flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart` - pass, `+6`.
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` - pass, `+23`.
  - `./scripts/run_test_gates.sh completeness-check` - pass, `697/697 test files classified`.
  - `./scripts/run_test_gates.sh groups` - pass, `+94`.
  - `flutter test --no-pub test/features/groups/application` - failed only on the preexisting MD-011 case `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart:2207`, where future-media replay still persisted a message instead of returning `null`; this failure is outside GL-002 and was already called out in the plan's Known-Failure Interpretation.
- Closure handoff: GL-002 is eligible for source matrix/inventory closure as `Covered` once the closure step records this evidence without claiming unrelated EK/DB/MD rows.
