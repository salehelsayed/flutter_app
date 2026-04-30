# GL-001 Session Plan: Group ID Uniqueness And Duplicate-Create Safety

## Source Row

- source matrix: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- source row id: `GL-001`
- scenario: Group ID uniqueness and duplicate-create safety
- current source status: `Partial`
- priority: `P0`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- dependency: none

## Scope

- Add direct tests for the existing create-group path when the bridge returns the same `groupId` more than once.
- Pin the current repository contract for duplicate create events: one canonical group row, one creator member row, one latest key row, and the canonical topic name for the returned group id.
- Keep the session limited to GL-001. Do not add broader signed create-event, protocol-topic, tombstone, metadata-conflict, or multi-device coverage.

## Expected Code And Test Touches

- Primary test file: `test/features/groups/application/create_group_use_case_test.dart`
- Primary implementation file, only if the test exposes a real bug: `lib/features/groups/application/create_group_use_case.dart`
- Supporting fake, only if necessary for assertions: `test/shared/fakes/in_memory_group_repository.dart`
- Source docs after acceptance: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md` and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## Execution Steps

1. Add a focused unit test that calls `createGroup` twice while the bridge returns the same `groupId`, `topicName`, group key, and epoch.
2. Assert the repository has exactly one canonical group for that id, the saved group keeps `/mknoon/group/<groupId>`, the creator membership is not duplicated, and the latest key remains the canonical key for the duplicate id/epoch.
3. Assert the bridge create command was invoked twice so the test represents duplicate create-event handling rather than a skipped second call.
4. If the test fails because duplicate persistence creates extra rows or invalid state, make the smallest implementation fix in the create use case or in-memory repository contract.
5. Update the GL-001 row in the source matrix from `Partial` to `Closed` or `Covered` only after the direct test passes.
6. Add a compact GL-001 entry to `test-inventory.md` with the exact test file and behavior proven.

## Required Verification

- Direct gate: `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart`
- Broader named gate when feasible: `flutter test --no-pub test/features/groups`
- If the broader gate is not run, record the reason in the execution result and closure note.

## Done Criteria

- GL-001 has a passing direct test proving duplicate returned group ids converge to one canonical group state.
- Source matrix row `GL-001` is updated to `Closed` or `Covered` with concrete file/test evidence.
- `test-inventory.md` records GL-001 coverage with the test path and assertion summary.
- The breakdown ledger records GL-001 as accepted only after the matrix and inventory evidence are present.

## Scope Guard

- Do not close GL-002, GL-008, GL-009, or any libp2p topology row from this work.
- Do not introduce new product semantics for bridge-level signed create events or network topic subscriptions unless the direct GL-001 test exposes a bug that cannot be closed locally.
- Do not weaken existing create-group happy-path, key rollback, announcement, or topic fallback tests.
