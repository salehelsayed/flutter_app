# INTEGRATE-ST-002 Plan - Standard Integration Contract

Status: accepted

## Scope

Import and verify historical row `ST-002`: "Permutation test for add, remove, key, config, and message event ordering."

This was standard worktree-to-main integration, not gap-closure. The historical source plan and closure evidence stayed the source of truth; no original implementation plan was regenerated.

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-002-plan.md`.
- Source row-owned proof selectors:
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "ST-002 permutes remove re-add key config and message ordering"`
  - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-002 fake-network event ordering permutations converge membership visibility and key"`
- Source 3-party E2E: `N/A`.

## Imported Delta

- `GroupMessageListener` now serializes incoming group message stream handling through `asyncMap`, preserving event ordering under add/remove/key/config/content permutations.
- Delayed stale `member_removed` events after an explicit re-add now repair only the removed interval before the current rejoin, preserving the active re-added member and valid post-readd content.
- Membership-window repair deletes bypass local user-deletion tombstones so buffered valid content can be re-evaluated and re-saved with the same message id after a later re-add.
- `handleReplayEnvelope` gained an explicit `allowMembershipBuffer` opt-in for row-owned listener proof while preserving the existing default offline replay behavior.
- Imported row-owned host selectors in `group_message_listener_test.dart` and `group_messaging_smoke_test.dart`.
- Added a narrow repository regression proving membership repair delete does not weaken normal local-delete tombstone behavior.

## Verification

Passed:

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "ST-002 permutes remove re-add key config and message ordering"`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-002 fake-network event ordering permutations converge membership visibility and key"`
- `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name "ST-002 membership repair delete does not block same-id re-save"`
- `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name "local delete still blocks same-id replay"`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-001"`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "NW-014"`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "KE-012 delayed old config after re-add cannot remove active members"`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "GM-014 member_added event time becomes Charlie re-add joinedAt and removed-window sender traffic stays rejected"`
- `flutter analyze --no-pub lib/core/database/helpers/group_messages_db_helpers.dart lib/features/groups/domain/repositories/group_message_repository.dart lib/features/groups/domain/repositories/group_message_repository_impl.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/application/handle_incoming_group_message_use_case.dart lib/main.dart test/shared/fakes/in_memory_group_message_repository.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `git diff --check`

No iOS simulator/live proof was required because the source row is host/fake-network only.

## Verdict

`accepted`

ST-002 is imported and verified. The integration stayed limited to row-owned ordering, stale-removal repair, membership-repair delete support, host/fake-network proofs, repository support proof, and documentation ledger updates. Existing blocked rows remain unchanged.
