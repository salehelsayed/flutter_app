# EK-013 Session Plan - Group Key Retention And Secure Storage Policy

## Scope

- Source row: `EK-013` - Obsolete keys are deleted and secrets use secure storage or defined backup policy.
- Source status at intake: `Open`.
- Breakdown class: `needs_code_and_tests | implementation-ready`.
- Closure target: rotated group key material has a bounded local retention policy, obsolete generations are removed from SQLCipher-backed local storage and shared push secure storage, and the backup/export posture is explicitly documented by existing secure storage and SQLCipher contracts.

## Scope Guard

- Keep this row to group key material already modeled by `GroupKeyInfo`, `group_keys`, `GroupRepositoryImpl`, and key rotation/update save paths.
- Do not introduce a backup product, export UI, broad secret-redaction framework, first-class per-device key packages, or secure-delete/memory-wipe primitives. Those remain owned by DB-006, DB-008, SP-006, SP-007, and SP-005.
- Do not change replay semantics beyond the defined local retention contract. Retain the current and immediately previous key generation so current delivery and previous-epoch grace/replay behavior remain supported; delete generations older than that.
- Treat SQLCipher `group_keys` as approved encrypted local database storage for app-owned group operation, and shared push `SecureKeyStore` mirrors as platform secure storage required for notification extension access.

## Implementation Plan

1. Add a focused group-key DB helper that deletes keys older than a retention floor for a group.
   - Likely file: `lib/core/database/helpers/group_keys_db_helpers.dart`.
   - Helper shape: `dbDeleteGroupKeysBeforeGeneration(Database db, String groupId, int minKeyGenerationToKeep)`.
   - Emit DB flow events without logging key material.

2. Extend `GroupRepositoryImpl` with an optional injected delete-obsolete helper and enforce retention after `saveKey`.
   - Likely file: `lib/features/groups/domain/repositories/group_repository_impl.dart`.
   - After saving/mirroring a key, load all keys for the group if `dbLoadAllGroupKeys` and the new delete helper are available.
   - Compute the latest known generation and delete keys with `keyGeneration < latest - 1`.
   - Delete matching shared-push secure-store mirrors for pruned keys before or after DB deletion, using existing `_deleteGroupKeyMirror`.
   - Preserve graceful degradation when optional helpers are absent.

3. Wire production repository construction to the new helper.
   - Likely file: `lib/main.dart`.

4. Keep test fakes aligned with repository semantics where useful.
   - Likely file: `test/shared/fakes/in_memory_group_repository.dart`.
   - Retain latest plus previous generation on save so fake-backed integration tests see the same bounded key history.

5. Add direct tests.
   - Likely file: `test/features/groups/domain/repositories/group_repository_impl_test.dart`.
   - Add a repository test proving saving generations 1, 2, and 3 leaves 2 and 3 available, deletes generation 1 from DB, and deletes the generation-1 shared secure-store mirror.
   - Existing `removeAllKeys` and `mirrorAllKeysToSecureStore` tests remain part of the secure-store deletion/mirror proof.

## Focused Gates

Run during execution:

```bash
flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart
flutter test --no-pub test/features/groups/application/rotate_group_key_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart
cd go-mknoon && go test ./bridge ./node -run 'GroupRotate|GroupGenerate|GroupUpdate|GroupTopicValidator|WrongKeyEpoch|RejectsUnknownFutureEpoch' -v
```

Closure gates after docs:

```bash
./scripts/run_test_gates.sh completeness-check
git diff --check
```

## Expected Classification Rules

Classify EK-013 as `accepted | closure-verified` only if:

- saving a newer generation prunes obsolete generations older than the immediately previous generation;
- pruned generations are removed from `group_keys` and from shared push `SecureKeyStore` mirrors;
- current and immediately previous generations remain available for current delivery and previous-epoch grace/replay behavior;
- leave/delete continues to remove all group keys and secure-store mirrors;
- no test or code path logs or exports key material.

Classify as `blocked | prerequisite-blocked` if the repo cannot delete obsolete key generations without breaking existing replay/key-update behavior or if a broader backup/export product decision is required before any bounded retention policy can be enforced.

## Regression Contract

- Current key rotation, distribution, key-update listener, and Go validator/key-epoch tests remain green.
- Existing `getLatestKey`, `getKeyByGeneration` for the immediately previous key, `removeAllKeys`, and secure-store mirroring behavior remain green.
- Docs must distinguish this bounded EK-013 closure from broader future rows for debug export, user-controlled backups, per-device key packages, and memory lifetime.

## Execution Evidence

Result: `accepted | closure-verified`.

Implemented a bounded latest-plus-previous group-key retention policy:

- Added `dbDeleteGroupKeysBeforeGeneration` in `lib/core/database/helpers/group_keys_db_helpers.dart` to delete obsolete `group_keys` rows below a per-group retention floor without logging key material.
- Extended `GroupRepositoryImpl.saveKey` in `lib/features/groups/domain/repositories/group_repository_impl.dart` to prune obsolete group key generations after saving and mirroring a key. The policy keeps the latest generation and the immediately previous generation, removes older SQLCipher rows, and deletes matching shared push `SecureKeyStore` mirrors.
- Wired the production repository in `lib/main.dart` to the new DB helper.
- Aligned `test/shared/fakes/in_memory_group_repository.dart` with the same latest-plus-previous retention behavior for fake-backed group tests.
- Added `saveKey prunes obsolete generations from DB and shared push storage` to `test/features/groups/domain/repositories/group_repository_impl_test.dart`.

Confirmed closure behavior:

- Saving generations 1, 2, and 3 leaves generations 2 and 3 available and deletes generation 1 from both `group_keys` and the shared push secure-store mirror.
- `removeAllKeys` still clears all group key DB rows and shared push mirrors.
- `mirrorAllKeysToSecureStore` still mirrors existing persisted rows.
- Rotation, distribution, key-update listener, and Go key-epoch/validator paths remain green.

Focused gates passed:

- `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart` (23 tests).
- `flutter test --no-pub test/features/groups/application/rotate_group_key_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart` (29 tests).
- `cd go-mknoon && go test ./bridge ./node -run 'GroupRotate|GroupGenerate|GroupUpdate|GroupTopicValidator|WrongKeyEpoch|RejectsUnknownFutureEpoch' -v`.

Accepted differences and boundaries:

- SQLCipher `group_keys` remains the approved app-local encrypted database store for current and previous group-operation keys.
- The shared push secure-store mirror remains the approved platform secure storage path for notification-extension access and is pruned with the DB rows.
- This session does not implement a user-controlled backup/export product, per-device key packages, debug export redaction, or secure memory wiping; those remain separate rows.
