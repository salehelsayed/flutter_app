# GL-008 Session Plan: Deletion, Closure, And Tombstone Prevent Resurrection

Status: execution-ready reusable

## Planning Progress

- 2026-04-30 18:20 CEST: Fresh planning child wrote an evidence draft but stalled before a reusable plan. The controller verified the draft and persisted the GL-008 correction from `needs_tests_only` to `needs_code_and_tests` in the breakdown.
- 2026-04-30 18:21 CEST: Local plan fallback completed as artifact-only controller work. No product code, tests, source matrix closure, or inventory closure was written by the controller.

## Real Scope

Implement and prove only GL-008: deleted or dissolved groups must not become visible or writable again through old metadata, member, key-rotation, direct key-update, or replay/sync-style events.

In scope:

- Add focused regressions for dissolved groups ignoring old `group_metadata_updated`, member mutation, `key_rotated`, and direct `GroupKeyUpdateListener` events.
- Add focused regressions for locally deleted/missing groups not being recreated by old system-event or direct key-update paths.
- Add the minimum production guard needed for the observed implementation-owned gap: direct key-update handling must not call `group:updateKey`, append a key event, or save a key when the target group is missing or already dissolved.
- Preserve current dissolved-group UI and local cleanup behavior.

Out of scope:

- New product flows for public/discoverable groups, invite links, read receipts, message edit/delete, export controls, or generic file attachments.
- A broad new tombstone table or sync protocol unless the executor proves current absent-group and dissolved-row guards cannot close GL-008.
- Three-device, relay, packet-capture, or raw-protocol proof as required closure evidence for this host-owned implementation session.

## Closure Bar

GL-008 may be accepted only when all of these are true:

- Source matrix row `GL-008` is updated from `Partial` to `Covered` or `Closed`.
- The source matrix row names concrete production files, direct tests, commands, and gate results.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` records the same GL-008 evidence.
- The session ledger and ordered breakdown entry record `accepted` with the GL-008 plan path and closure evidence.
- Direct tests prove old metadata/member/key-event replay and direct key updates cannot resurrect a dissolved or locally deleted group.
- `git diff --check` passes.

## Source Of Truth

- Primary row contract: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`, row `GL-008`.
- Session contract: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`, GL-008 ledger and ordered row.
- Coverage inventory to update after closure: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- Current code and tests beat stale prose if they disagree.
- In implementation-committed mode, row-owned acceptance requires source row `GL-008` to be `Closed` or `Covered`; `accepted_with_explicit_follow_up` is not valid while the row remains `Partial`.

## Session Classification

`implementation-ready`

Corrected row disposition: `needs_code_and_tests`.

Reason: planning evidence found `GroupKeyUpdateListener` decrypts direct key updates, calls `group:updateKey`, appends optional event-log evidence, and saves `GroupKeyInfo` without first checking whether the group exists or is dissolved. That is an implementation-owned resurrection-adjacent gap for GL-008.

## Exact Problem Statement

GL-008 remains `Partial` because existing tests prove durable dissolve fields, repeated dissolve idempotency, dissolved local cleanup, dissolved-topic rejoin suppression, and post-dissolve message/reaction guards, but they do not prove that old metadata, member, key-rotation, direct key-update, or peer-sync-style replay cannot recreate usable group state after closure or local deletion.

The user-visible requirement is that once a group is dissolved or locally deleted, old traffic must not make it look active again, must not restore writable keys, and must not create new visible messages or member state.

## Files And Repos To Inspect Next

- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/delete_group_and_messages_use_case.dart`
- `lib/features/groups/application/dissolve_group_use_case.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
- `test/features/groups/application/dissolve_group_use_case_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`

## Existing Tests Covering This Area

- `dissolve_group_use_case_test.dart` proves dissolve fields, idempotency, partial bridge failure, and repeated dissolve behavior.
- `delete_group_and_messages_use_case_test.dart` proves dissolved local cleanup removes group/member/key/message state without `group:leave`.
- `rejoin_group_topics_use_case_test.dart` proves dissolved groups are skipped.
- `group_message_listener_test.dart` already contains stale membership/metadata replay tests, `group_dissolved` tests, and a broad unauthorized mutation matrix including `group_dissolved`.
- `group_key_update_listener_test.dart` proves normal key update saves, duplicate/tamper event-log behavior, ordering, and bridge update-key failures, but not missing or dissolved group rejection.
- `group_membership_smoke_test.dart` records an offline dissolve/local cleanup integration proof.

## Regression/Tests To Add First

Add failing tests before implementation where possible:

- In `group_key_update_listener_test.dart`, prove a direct key update for a missing group does not call `group:updateKey`, does not append an event-log entry, and does not save a key.
- In `group_key_update_listener_test.dart`, prove a direct key update for a dissolved group does not call `group:updateKey`, does not append an event-log entry, and preserves the existing key.
- In `group_message_listener_test.dart`, add or tighten a GL-008-focused test that after `group_dissolved`, old `group_metadata_updated`, `member_added` or `member_role_updated`, and `key_rotated` system events do not change group metadata, member state, key state, or visible message count.
- In `group_message_listener_test.dart`, add or tighten a missing-group/local-delete proof that old system events for a deleted group do not recreate a group row or visible message.

## Step-By-Step Implementation Plan

1. Record the dirty worktree snapshot with `git status --short` before code/test execution.
2. Add the GL-008 direct key-update regressions in `group_key_update_listener_test.dart`.
3. Add or tighten GL-008 stale system-event replay regressions in `group_message_listener_test.dart`.
4. Run the focused new tests and confirm the direct key-update guard test fails before implementation, unless current code has already changed in the dirty tree.
5. Update `GroupKeyUpdateListener._handleMessage` after decrypting the payload and extracting `groupId`, before `callGroupUpdateKey`, to fetch `groupRepo.getGroup(groupId)` and return without mutation when the group is missing or `isDissolved`.
6. Emit narrow flow events for the two guard returns, for example `GROUP_KEY_UPDATE_LISTENER_GROUP_NOT_FOUND` and `GROUP_KEY_UPDATE_LISTENER_GROUP_DISSOLVED`, without logging protected key material.
7. Keep `GroupMessageListener` changes minimal. If current dissolved/missing-group guards already satisfy the added tests, do not refactor it.
8. Run focused direct tests. Fix only GL-008-owned failures.
9. Run the required named gates listed below.
10. Update the source matrix, test inventory, and breakdown only after tests/gates support `Closed` or `Covered`.

## Risks And Edge Cases

- Direct key updates are one-to-one P2P messages, separate from group system messages, so system-message guards alone do not protect GL-008.
- A missing local group is a local-delete signal in current architecture. The session should prove old events do not recreate state, not invent a broad deleted-groups table unless current tests prove absent-group checks are insufficient.
- `group_dissolved` itself must remain idempotent for existing dissolved groups.
- Flow events must not expose encrypted key material, private keys, invite secrets, media keys, or message plaintext.
- Existing unrelated dirty changes must not be reverted.

## Device/Relay Proof Profile

- Profile: `host-only` for required GL-008 closure evidence.
- Live availability check: run `flutter devices --machine` at execution start only to record that no required device fixture is needed for this session.
- Required closure evidence: focused host-side Flutter tests plus named host gates below.
- Supporting evidence only: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g ./scripts/run_test_gates.sh group-real-network-nightly` may be run only when configured fixtures are available; it is not required for GL-008 acceptance in this corrected host-owned session.
- A single `FLUTTER_DEVICE_ID` only selects the Flutter host target and is not a paired-device proof.

## Exact Tests And Gates To Run

Required direct tests:

```sh
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart
flutter test --no-pub test/features/groups/application/delete_group_and_messages_use_case_test.dart
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
```

Required gates:

```sh
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Optional/supporting only:

```sh
flutter devices --machine
FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g ./scripts/run_test_gates.sh group-real-network-nightly
```

## Known-Failure Interpretation

- A focused GL-008 direct test failure is blocking.
- `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` are required for closure.
- If a broad feature-folder run is attempted and fails only on the previously recorded unrelated MD-011 future-media replay case, do not classify that as a GL-008 regression unless a GL-008 direct test or required gate also fails.
- Missing real-network fixtures for the optional `group-real-network-nightly` command do not block GL-008 host closure.

## Done Criteria

- New GL-008 direct tests fail before the guard if the current dirty tree still lacks it, then pass after implementation.
- Direct key updates for missing or dissolved groups produce no saved key, no `group:updateKey`, and no event-log append.
- Old system events after dissolve or local delete do not resurrect visible group state, member state, metadata, messages, or keys.
- Source matrix row `GL-008` is `Covered` or `Closed` with concrete evidence.
- `test-inventory.md` records the GL-008 closure evidence.
- The session breakdown ledger and ordered entry record `accepted`.
- Required tests and gates pass or have a documented non-GL known-failure interpretation that does not weaken GL-008 closure.

## Scope Guard

- Do not add a generic deleted-groups/tombstones table unless the direct tests prove absent-group and dissolved-row guards cannot satisfy GL-008.
- Do not change group key rotation semantics for active groups.
- Do not alter encryption payload shapes, invite policy, membership roles, notification routing, or media handling.
- Do not broaden into EC-006 replayed tombstone corruption, OS sync range/head/hash primitives, or live multi-peer proof rows.
- Do not accept the session while source row `GL-008` remains `Partial`.

## Accepted Differences / Intentionally Out Of Scope

- Local delete currently removes group state. For GL-008, the minimum acceptable proof is that absent local state cannot be recreated by stale listener or key-update paths; a durable local-delete tombstone table is intentionally out of scope unless proven necessary by tests.
- Three-party real-network peer-sync proof remains supporting evidence for this row and may belong to later evidence-gated rows if host-side closure is complete.
- Message edit/delete tombstones remain unsupported product scope for MS-008 and are not part of GL-008.

## Dependency Impact

- Later stale replay and fork rows may reuse the direct key-update missing/dissolved guard as prerequisite evidence, but they must still close under their own row ids.
- If execution proves durable local-delete tombstones are required, reclassify the session blocker precisely before closure and do not mark GL-008 accepted.
- GL-009 and later lifecycle rows should not depend on GL-008 until the source matrix row is actually `Closed` or `Covered`.

## Reviewer Findings

- Finding: The original tests-only ledger classification was stale. Current direct key-update code can save keys for missing or dissolved groups.
- Finding: Device/relay proof is not required for the corrected host-owned closure, but the optional gate remains listed as supporting evidence only.
- Finding: The plan is narrow enough to implement without inventing a new tombstone subsystem unless tests prove one is necessary.

## Arbiter Decision

No structural blockers remain for execution. The plan is reusable as a GL-008 implementation-ready code-and-tests plan under implementation-committed gap-closure mode.

## Dirty Worktree Snapshot Before Execution

Recorded 2026-04-30 18:24:59 CEST from `git status --short`.

The worktree was already dirty with many prior rollout changes before GL-008 execution. Current-session-relevant pre-execution entries include:

```text
 M Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md
 M Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md
 M Test-Flight-Improv/Group-Chat-Feature/test-inventory.md
 M lib/features/groups/application/group_key_update_listener.dart
 M lib/features/groups/application/group_message_listener.dart
 M lib/features/groups/domain/repositories/group_repository_impl.dart
 M test/features/groups/application/dissolve_group_use_case_test.dart
 M test/features/groups/application/group_key_update_listener_test.dart
 M test/features/groups/application/group_message_listener_test.dart
 M test/features/groups/application/rejoin_group_topics_use_case_test.dart
 M test/features/groups/integration/group_membership_smoke_test.dart
 M test/shared/fakes/in_memory_group_repository.dart
?? Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-008-plan.md
```

No pre-existing short-status entry was present for `lib/features/groups/application/delete_group_and_messages_use_case.dart` or `test/features/groups/application/delete_group_and_messages_use_case_test.dart` at this snapshot. Closure must classify any post-execution delta outside the files above as GL-008-owned, prior-session, harmless, or blocking without reverting unrelated work.

## Execution Result

Recorded 2026-04-30 18:37:42 CEST.

Spawned-agent isolation:

- Executor agent `019ddf37-5769-7f42-8d5a-112e9c8f1995` was spawned with model `gpt-5.5` and reasoning effort `xhigh`.
- The Executor made GL-008 owner-file progress but did not return a trustworthy final handoff after the bounded waits; the controller closed it as no-result/no-final-summary and completed controller-side verification recovery from the on-disk state.
- Separate QA review still required before outer closure because the first Executor handoff did not materialize.

Device/relay profile:

- `flutter devices --machine` was run before coding. Available targets included Android emulator `emulator-5554`, iOS device `00008030-001A6D2801BB802E`, iOS simulators including `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `macos`, and `chrome`.
- GL-008 required closure evidence remains host-only. No paired device or relay fixture is required for this execution proof.
- `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were not set in the execution environment, and optional `group-real-network-nightly` was not run because it is supporting-only and fixtures were not verified as required or cheap/safe.

Files changed or verified for GL-008 execution:

- `lib/features/groups/application/group_key_update_listener.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `lib/features/groups/application/group_message_listener.dart` was verified; current guards satisfied the new GL-008 stale replay tests without a broad GL-008 refactor.
- This plan file was updated with execution evidence.

Implemented behavior:

- Direct `GroupKeyUpdateListener` handling now decrypts the direct key update, extracts `groupId`, then checks `groupRepo.getGroup(groupId)` before `group:updateKey`, event-log append, or key save.
- Missing groups return with `GROUP_KEY_UPDATE_LISTENER_GROUP_NOT_FOUND` and no bridge key update, no event-log append, and no saved key.
- Dissolved groups return with `GROUP_KEY_UPDATE_LISTENER_GROUP_DISSOLVED` and preserve the existing key without bridge key update, event-log append, or new key save.
- Group system-event replay coverage now proves old `group_metadata_updated`, `member_added`, `member_role_updated`, and `key_rotated` events after `group_dissolved` do not mutate metadata, members, keys, or visible message state, and old events for a locally deleted group do not recreate a group row, members, keys, or visible messages.

RED/green note:

- The controller did not capture a clean RED-before-green command because the spawned Executor timed out without a final summary after writing code/tests. On-disk diff shows the GL-008 guard and regressions landed together before controller-side verification. Post-implementation direct tests and gates below passed.

Commands run and outcomes:

```text
dart format lib/features/groups/application/group_key_update_listener.dart lib/features/groups/application/group_message_listener.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/group_message_listener_test.dart
PASS - Formatted 4 files (0 changed).

flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart
PASS - 16 tests passed, including missing and dissolved direct key-update guard regressions.

flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
PASS - 74 tests passed, including GL-008 stale system-event replay regressions.

flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart
PASS - 6 tests passed.

flutter test --no-pub test/features/groups/application/delete_group_and_messages_use_case_test.dart
PASS - 3 tests passed.

flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart
PASS - 18 tests passed.

flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
PASS - 23 tests passed.

./scripts/run_test_gates.sh groups
PASS - Group Messaging Gate completed with 94 tests passed.

./scripts/run_test_gates.sh completeness-check
PASS - 697/697 test files classified.

git diff --check
PASS - no whitespace errors.
```

Known unrelated failures:

- None observed in the required GL-008 direct tests or required gates.
- Existing broad dirty worktree state from prior rollout sessions remains present and was not reverted.

Execution verdict:

- `accepted` for GL-008 execution handoff: required host-side direct tests and required named gates passed, and no broader durable tombstone subsystem or external fixture was required.
- Source matrix, test inventory, and breakdown ledger closure updates were intentionally not performed by this execution child per run constraints; the separate closure child must verify the evidence above before marking row `GL-008` `Closed` or `Covered`.

QA fallback result:

- QA Reviewer agent `019ddf41-aca7-7052-bdd4-fd70f6b4ea91` was spawned with model `gpt-5.5` and reasoning effort `xhigh`, but did not return within the bounded wait and was closed with no file edits.
- Local QA fallback reviewed the GL-008 owner diff and execution evidence. No blocking issues were found for execution handoff.
- Non-blocking closure handoff: source matrix, test inventory, and breakdown ledger still need the separate closure child update required by the run constraints.
