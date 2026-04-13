# Session Plan: CB-007

## Row Contract

- source row: `CB-007`
- matrix contract: Persisted topic namespace matches the real `/mknoon/group/{groupId}` namespace.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows the create path persists the canonical `/mknoon/group/{groupId}` namespace when the bridge omits `topicName`, while still accepting the canonical bridge-returned namespace when it is present.

## Scope Guard

- smallest possible creator-path fix plus direct proof
- do not broaden into unrelated join/rejoin behavior beyond the topic-name contract needed for this row
- preserve existing create flow semantics outside the persisted `topicName` fallback

## Planned Proof

1. Replace the creator-path fallback `group-$groupId` namespace with the canonical `/mknoon/group/$groupId`.
2. Add a create-use-case regression proving the canonical fallback is used when the bridge omits `topicName`.
3. Refresh the matrix, inventory, and breakdown with concrete file-and-test evidence.

## Files Expected

- `lib/features/groups/application/create_group_use_case.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
